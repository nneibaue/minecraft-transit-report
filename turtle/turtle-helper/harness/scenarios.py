"""Named harness scenarios (D-01, D-14).

Each scenario is a plain async function ``(dev, args)`` that drives one FakeDevice against the
real bridge and returns normally on pass. It raises ScenarioError, TimeoutError or
SpendRefusedError on failure; ``harness.main`` turns that into the one-line verdict and exit
code. Every wait here goes through FakeDevice.expect*, so every wait is bounded.
"""

from __future__ import annotations

import asyncio

from harness.harness import (
    COMPUTER_CAPS,
    TURTLE_CAPS,
    FakeDevice,
    Frame,
    Scenario,
    ScenarioArgs,
    ScenarioError,
    SpendRefusedError,
    unknown_tool,
)

HELLO_WINDOW = 5.0  # seconds without a close after hello = the bridge accepted it
SHORT_WINDOW = 3.0  # follow-up "still open" windows after a probe
RECONNECT_WAIT = 2.0  # pause between a local drop and the same-id reconnect
SILENCE_WINDOW = 5.0  # how long "nothing arrived" must last to count as ignored
MODEL_WINDOW = 30.0  # generous bound for a real model round trip (devices-question)
WORKER_HOLD = 60.0  # how long the worker side of devices-question stays registered
TEST_UUID = "00000000-0000-4000-8000-000000000001"  # fixed uuid for scripted chat events
ERROR_FALLBACK = "something went wrong"  # bridge.on_event's catch-all say text (pre- and post-swap)


def is_error_fallback(text: object) -> bool:
    """True when a say text is bridge.on_event's catch-all reply, not an answer.

    The bridge answers any exception that escapes the agent with
    ``say("Sorry <user>, something went wrong: <ErrorName>")``. That frame is a real ``say``
    cmd on the wire, so a scenario that only waits for one would pass on it (02-04 saw exactly
    that on a 400 from the API). Matched on the shape, not the exact user or error name.
    """
    if not isinstance(text, str):
        return False
    stripped = text.strip()
    return stripped.startswith("Sorry") and ERROR_FALLBACK in stripped.lower()


def _cmd(tool: str, **args: object) -> Frame:
    """A synthetic cmd frame for calling build_reply() directly (no wire round trip)."""
    return {"type": "cmd", "cid": f"local-{tool}", "tool": tool, "args": dict(args)}


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ScenarioError(message)


async def hello_handshake(dev: FakeDevice, args: ScenarioArgs) -> None:
    """HARN-01: connect, send hello, and prove it was accepted (no close within the window)."""
    await dev.connect()
    await dev.expect_no_close(HELLO_WINDOW)


async def status_command(dev: FakeDevice, args: ScenarioArgs) -> None:
    """HARN-03: the fake worker advertises client.lua's caps and answers them with its shapes.

    The canned-response check is a direct, zero-network assertion of build_reply() against
    each primitive in client.lua's tools table: the only live way to make the bridge send a
    cmd to this device is the paid agent loop, which this phase reserves for devices-question
    (D-05). The scenario then connects for real and stays registered for a window, proving the
    device is ready to answer whatever arrives later (Phase 3/4, or incidentally if a paid run
    calls ``status``).
    """
    _require(dev.role == "worker", "status-command needs --role worker")
    expected_caps = list(TURTLE_CAPS if args.turtle else COMPUTER_CAPS)
    _require(dev.caps == expected_caps, f"caps {dev.caps} != client.lua's {expected_caps}")

    status = dev.build_reply(_cmd("status"))
    _require({"id", "is_turtle", "pos", "peripherals"} <= status.keys(), f"status: {status}")
    _require(status["id"] == dev.device_id, f"status.id should be the device id: {status}")
    _require(status["is_turtle"] is args.turtle, f"status.is_turtle should be {args.turtle}")
    _require(("fuel" in status) is args.turtle, f"fuel only on a turtle: {status}")

    chest = dev.build_reply(_cmd("list_chest", name="minecraft:chest_0"))
    _require({"name", "size", "items"} <= chest.keys(), f"list_chest: {chest}")
    _require(chest["name"] == "minecraft:chest_0", f"list_chest.name echoes args.name: {chest}")

    push_args: dict[str, object] = {
        "from": "minecraft:chest_0",
        "slot": 1,
        "dest": "minecraft:chest_1",
    }
    push = dev.build_reply(_cmd("push_one_slot", **push_args))
    _require(isinstance(push.get("moved"), int), f"push_one_slot returns {{moved: int}}: {push}")

    bogus = dev.build_reply(_cmd("bogus"))
    _require(bogus == unknown_tool("bogus"), f"unknown tool reply: {bogus}")

    turtle_only = ("move", "turn", "dig", "inspect", "refuel")
    if args.turtle:
        _require("moved" in dev.build_reply(_cmd("move", dir="forward", steps=2)), "move shape")
        _require(dev.build_reply(_cmd("turn", dir="left")) == {"ok": True}, "turn shape")
        _require("dug" in dev.build_reply(_cmd("dig", dir="forward")), "dig shape")
        _require({"forward", "up", "down"} <= dev.build_reply(_cmd("inspect")).keys(), "inspect")
        _require({"before", "after"} <= dev.build_reply(_cmd("refuel", count=1)).keys(), "refuel")
    else:
        for tool in turtle_only:
            _require(
                dev.build_reply(_cmd(tool)) == unknown_tool(tool),
                f"a computer must answer 'unknown tool {tool}' like client.lua",
            )

    # The wire shape session() sends: data wrapped as ok/data, errors passed through.
    envelope = FakeDevice.envelope("c1", status)
    _require(envelope["ok"] is True and envelope["data"] == status, f"result shape: {envelope}")
    error = FakeDevice.envelope("c2", bogus)
    _require(
        error == {"type": "result", "cid": "c2", "ok": False, "error": "unknown tool bogus"},
        f"error result shape: {error}",
    )
    print(
        f"status-command: build_reply matches client.lua for status, list_chest, push_one_slot, "
        f"unknown tool{' and the five turtle tools' if args.turtle else ''}",
        flush=True,
    )

    await dev.connect()
    await dev.expect_no_close(HELLO_WINDOW)


async def drop_and_reconnect(dev: FakeDevice, args: ScenarioArgs) -> None:
    """HARN-04 with D-11 and D-12: garbage frame survives, drop and rejoin, same-id replacement.

    1. Connect and get accepted.
    2. D-12: send one raw non-JSON payload, then prove the device is still registered with a
       normal exchange -- a harmless event the bridge logs and a websocket ping -- and no close
       within a further window.
    3. HARN-04: close locally, wait, reconnect under the same id; the second hello is accepted.
    4. D-11: open a third connection with the same id while the second is still open. The
       bridge must close the second (stale) socket with code 4000 and keep the third; the
       replacement touches only this one device id (RESIL-03's concurrency guarantee).
    """
    await dev.connect()
    await dev.expect_no_close(RECONNECT_WAIT)

    await dev.send_raw("this is not json {")
    await dev.send_event("harness-probe", note="sent after a malformed frame")
    latency = await dev.ping(SHORT_WINDOW)
    print(f"drop-and-reconnect: ping after malformed frame answered in {latency * 1000:.1f}ms")
    await dev.expect_no_close(SHORT_WINDOW)

    await dev.close()
    await asyncio.sleep(RECONNECT_WAIT)
    second = dev.clone()
    await second.connect()
    try:
        await second.expect_no_close(HELLO_WINDOW)
        third = dev.clone()
        await third.connect()
        try:
            code = await second.expect_close(HELLO_WINDOW)
            _require(code == 4000, f"stale same-id socket closed with {code}, expected 4000")
            await third.expect_no_close(SHORT_WINDOW)
            print("drop-and-reconnect: stale socket closed 4000, replacement stayed registered")
        finally:
            await third.close()
    finally:
        await second.close()


async def wrong_token(dev: FakeDevice, args: ScenarioArgs) -> None:
    """RESIL-04 (and CR-01): a hello carrying the --token override is closed with code 4001.

    Run it twice -- ``--token wrong-value-0001`` and ``--token ""`` (the empty-token case
    D-13 calls out) -- both must see the same 4001 close, proving the bridge's non-empty,
    exact-match token check rejects them uniformly. The bridge's own log line for it is
    ``rejected device harness-chat from <addr>: bad token`` (D-16); the token value appears in
    neither that line nor this harness's wire log.
    """
    _require(
        args.token != args.settings.bridge_token,
        'wrong-token needs a --token value that differs from BRIDGE_TOKEN (use --token "" '
        "for the empty case)",
    )
    await dev.connect()
    code = await dev.expect_close(HELLO_WINDOW)
    _require(code == 4001, f"bridge closed with {code}, expected 4001 (bad token)")
    kind = "empty" if args.token == "" else "wrong"
    print(f"wrong-token: {kind} token rejected with close code 4001", flush=True)


async def disallowed_player(dev: FakeDevice, args: ScenarioArgs) -> None:
    """RESIL-05: a prefixed chat event from a player not in ALLOWED_PLAYERS triggers nothing.

    on_event drops the event on the allow-list before the agent is ever called, so no --spend
    is needed and no model call can happen. The harness cannot read the bridge's terminal, so
    it passes by absence: no cmd (and no close) within SILENCE_WINDOW after the event. A full
    RESIL-05 proof also greps the bridge's own output for ``ignoring <user> (not allowed)``
    (D-16, unchanged this phase).
    """
    _require(dev.role == "chat", "disallowed-player needs --role chat")
    settings = args.settings
    user = "harness-nobody"
    while user in settings.allowed_players:  # never collide with a real allowed name
        user += "-x"
    await dev.connect()
    await dev.expect_no_close(RECONNECT_WAIT)
    await dev.send_event(
        "chat",
        user=user,
        text=f"{settings.command_prefix} what devices are connected?",
        uuid=TEST_UUID,
        hidden=True,
    )
    try:
        frame = await dev.expect(
            lambda f: f.get("type") in ("cmd", "close"), SILENCE_WINDOW, "cmd or close frame"
        )
    except TimeoutError:
        print(
            f"disallowed-player: nothing arrived for {SILENCE_WINDOW:g}s after the event from "
            f"{user!r}; the bridge log should show 'ignoring {user} (not allowed)'",
            flush=True,
        )
        return
    raise ScenarioError(f"bridge reacted to a disallowed player's event: {frame}")


async def devices_question(dev: FakeDevice, args: ScenarioArgs) -> None:
    """HARN-02: the one paid scenario -- '$robot what devices are connected?' answered in chat.

    Two terminals (D-02), worker first::

        uv run harness --role worker --scenario devices-question
        uv run harness --role chat --scenario devices-question --spend

    The worker side sends no chat event and needs no --spend: it registers with client.lua's
    caps and stays for WORKER_HOLD seconds, auto-answering any cmd, so it is listed (and can
    answer ``status``) while the model runs. The chat side refuses to send anything unless
    --spend is on the command line (D-15), then emits the scripted event from the first
    allowed player and passes when a ``say`` cmd arrives within MODEL_WINDOW carrying a real
    answer -- the bridge's ``Sorry ..., something went wrong: ...`` fallback fails it; a
    ``list_devices`` cmd is accepted first in case a later agent loop forwards it. The paid
    runs themselves are Plan 02-04 (pre-swap) and Plan 02-07 (post-swap).
    """
    if dev.role == "worker":
        await dev.connect()
        await dev.expect_no_close(RECONNECT_WAIT)
        print(f"devices-question: worker registered; holding for {WORKER_HOLD:g}s", flush=True)
        await dev.expect_no_close(WORKER_HOLD - RECONNECT_WAIT)
        return
    if not args.spend:
        raise SpendRefusedError(
            "devices-question sends a prefixed chat event from an allowed player, which costs "
            "one real model call; re-run with --spend to do that deliberately (nothing was sent)"
        )
    settings = args.settings
    await dev.connect()
    await dev.expect_no_close(RECONNECT_WAIT)
    await dev.send_event(
        "chat",
        user=settings.allowed_players[0],
        text=f"{settings.command_prefix} what devices are connected?",
        uuid=TEST_UUID,
        hidden=True,
    )

    def is_tool(frame: Frame, *names: str) -> bool:
        return frame.get("type") == "cmd" and frame.get("tool") in names

    first = await dev.expect(
        lambda f: is_tool(f, "list_devices", "say"), MODEL_WINDOW, "list_devices or say cmd"
    )
    said = first
    if not is_tool(first, "say"):
        said = await dev.expect(lambda f: is_tool(f, "say"), MODEL_WINDOW, "say cmd")
    say_args = said.get("args")
    text = say_args.get("text") if isinstance(say_args, dict) else None
    print(f"devices-question: robot said {text!r}", flush=True)
    _require(isinstance(text, str) and text.strip() != "", f"say cmd without text: {said}")
    _require(
        not is_error_fallback(text),
        f"the say was the bridge's error fallback, not an answer: {text!r} "
        "(check the bridge log for the exception)",
    )


SCENARIOS: dict[str, Scenario] = {
    "hello-handshake": hello_handshake,
    "status-command": status_command,
    "drop-and-reconnect": drop_and_reconnect,
    "wrong-token": wrong_token,
    "disallowed-player": disallowed_player,
    "devices-question": devices_question,
}

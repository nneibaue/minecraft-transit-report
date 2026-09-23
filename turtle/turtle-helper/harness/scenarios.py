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
    unknown_tool,
)

HELLO_WINDOW = 5.0  # seconds without a close after hello = the bridge accepted it
SHORT_WINDOW = 3.0  # follow-up "still open" windows after a probe
RECONNECT_WAIT = 2.0  # pause between a local drop and the same-id reconnect


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


SCENARIOS: dict[str, Scenario] = {
    "hello-handshake": hello_handshake,
    "status-command": status_command,
    "drop-and-reconnect": drop_and_reconnect,
}

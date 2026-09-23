"""Fake device harness: a terminal stand-in for chat.lua and client.lua (Phase 2, D-01..D-04).

The harness speaks only the wire protocol against the real, running bridge. It imports
``bridge.settings`` for the host, port, token, command prefix and allowed players -- never
``bridge.bridge`` or ``bridge.agent`` -- so it stays correct straight through the agent swap.

    uv run harness --role chat|worker --scenario <name> [--turtle] [--spend] [--token <override>]

One fake device per process (D-02). Every frame in either direction prints as one line (D-04):
timestamp, device id, ``->`` (device to bridge) or ``<-`` (bridge to device), then the compact
JSON exactly as it went over the wire. The one exception is a hello frame's token, which is
replaced by a placeholder so the shared secret never reaches the terminal or a saved transcript.

Exit codes: 0 the scenario passed, 1 it failed, 2 the harness refused to run (spend guard,
unknown scenario, invalid configuration).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from pydantic import ValidationError
from websockets.asyncio.client import ClientConnection, connect
from websockets.exceptions import ConnectionClosed

from bridge.settings import Settings

Role = Literal["chat", "worker"]
Direction = Literal["in", "out"]
Frame = dict[str, object]

# Capability lists mirror client.lua's capabilities(): every tools.<name> key, sorted with
# table.sort, so the advertised order is deterministic and matches a real device (plan 02-01).
COMPUTER_CAPS: tuple[str, ...] = ("list_chest", "push_one_slot", "status")
TURTLE_CAPS: tuple[str, ...] = (
    "dig",
    "inspect",
    "list_chest",
    "move",
    "push_one_slot",
    "refuel",
    "status",
    "turn",
)
CHAT_CAPS: tuple[str, ...] = ("say",)

TOKEN_PLACEHOLDER = "***"
ARROWS: dict[Direction, str] = {"out": "->", "in": "<-"}
CONNECT_TIMEOUT = 10.0


class ScenarioError(Exception):
    """A scenario expectation was not met; main() prints FAIL and exits 1 (D-14)."""


class SpendRefusedError(Exception):
    """The harness declined to send a paid chat event because --spend was absent (D-15)."""


def compact(frame: Frame) -> str:
    """Serialise a frame the way it is sent: compact JSON, no spaces."""
    return json.dumps(frame, separators=(",", ":"))


def _parse_frame(text: str) -> Frame:
    """Decode one inbound payload; anything but a JSON object becomes an 'unparsed' frame."""
    try:
        parsed = json.loads(text)
    except ValueError:
        return {"type": "unparsed", "raw": text}
    if isinstance(parsed, dict):
        return parsed
    return {"type": "unparsed", "raw": text}


def log_wire(device_id: str, direction: Direction, payload: Frame | str) -> str:
    """Print and return one wire-log line: timestamp, device id, arrow, compact JSON (D-04).

    A dict is serialised with the same compact separators FakeDevice sends; a string is
    printed verbatim (inbound frames, or a raw outbound payload). A hello frame has its
    ``token`` value replaced by ``***`` before printing -- this line is what a human pastes
    into the checkpoint transcripts Plans 02-04/02-07 commit, so the real value must never
    appear in it. Every other field of every other frame type prints unredacted.
    """
    if isinstance(payload, str):
        text = payload
        frame = _parse_frame(payload)
    else:
        text = compact(payload)
        frame = payload
    if frame.get("type") == "hello" and "token" in frame:
        text = compact({**frame, "token": TOKEN_PLACEHOLDER})
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    line = f"{stamp} {device_id} {ARROWS[direction]} {text}"
    print(line, flush=True)
    return line


def unknown_tool(tool: str) -> Frame:
    """The reply client.lua's session() sends for a tool it does not have."""
    return {"ok": False, "error": f"unknown tool {tool}"}


@dataclass(frozen=True)
class SpendGuard:
    """What the device must know to refuse a paid chat event unless --spend was given (D-15).

    The bridge only calls the model for a prefixed chat event from an allowed player, so that
    is the one shape the harness refuses to emit without the flag on the command line.
    """

    allowed_players: tuple[str, ...]
    command_prefix: str
    spend: bool

    def check(self, user: object, text: object) -> None:
        """Raise SpendRefusedError if this chat event would reach the model without --spend."""
        if self.spend:
            return
        prefixed = str(text).strip().lower().startswith(self.command_prefix.lower())
        if user in self.allowed_players and prefixed:
            raise SpendRefusedError(
                f"a {self.command_prefix!r} chat event from allowed player {user!r} costs one "
                "model call; pass --spend to send it deliberately"
            )


@dataclass(frozen=True)
class ScenarioArgs:
    """Command-line choices and the shared settings a scenario may consult."""

    spend: bool
    turtle: bool
    token: str
    settings: Settings


class FakeDevice:
    """One fake in-game device: a websocket client that mirrors chat.lua or client.lua (D-03).

    ``connect()`` opens the socket, sends the hello and starts ``run()`` in the background.
    ``run()`` logs every inbound frame, queues it for ``expect()``, and auto-answers every
    ``cmd`` with ``build_reply()`` wrapped as a ``result`` -- exactly what the Lua does.
    When the socket closes, a synthetic ``{"type": "close", "code", "reason"}`` frame is
    queued so a scenario can await the close code the bridge sent.
    """

    def __init__(
        self,
        role: Role,
        device_id: str,
        host: str,
        port: int,
        token: str,
        caps: Sequence[str],
        turtle: bool = False,
        spend_guard: SpendGuard | None = None,
    ) -> None:
        if role not in ("chat", "worker"):
            raise ValueError(f"role must be 'chat' or 'worker', not {role!r}")
        self.role: Role = role
        self.device_id = device_id
        self.host = host
        self.port = port
        self.token = token
        self.caps = list(caps)
        self.turtle = turtle
        self.spend_guard = spend_guard
        self.ws: ClientConnection | None = None
        self.frames: asyncio.Queue[Frame] = asyncio.Queue()
        self.seen: list[Frame] = []  # every frame ever observed, for post-hoc inspection
        self._reader: asyncio.Task[None] | None = None

    # ------------------------------------------------------------------ identity
    @property
    def wire_role(self) -> str:
        """The role sent in hello: chat.lua says 'chat'; client.lua says 'turtle' or 'computer'."""
        if self.role == "chat":
            return "chat"
        return "turtle" if self.turtle else "computer"

    @property
    def url(self) -> str:
        """Bridge websocket URL, the same ws://host:port the Lua files point at locally."""
        return f"ws://{self.host}:{self.port}"

    def clone(self) -> FakeDevice:
        """A fresh, unconnected device with the same identity -- for reconnecting under one id."""
        return FakeDevice(
            self.role,
            self.device_id,
            self.host,
            self.port,
            self.token,
            self.caps,
            self.turtle,
            self.spend_guard,
        )

    def _require_ws(self) -> ClientConnection:
        if self.ws is None:
            raise RuntimeError(f"{self.device_id}: not connected; call connect() first")
        return self.ws

    # ------------------------------------------------------------------ sending
    async def connect(self) -> None:
        """Open the websocket, start the reader, and send the hello frame."""
        if self.ws is not None:
            raise RuntimeError(f"{self.device_id}: already connected; use clone() for another")
        self.ws = await asyncio.wait_for(connect(self.url), CONNECT_TIMEOUT)
        self._reader = asyncio.create_task(self.run(), name=f"reader:{self.device_id}")
        await self._send(
            {
                "type": "hello",
                "id": self.device_id,
                "token": self.token,
                "role": self.wire_role,
                "caps": self.caps,
            }
        )

    async def _send(self, frame: Frame) -> None:
        ws = self._require_ws()
        log_wire(self.device_id, "out", frame)
        await ws.send(compact(frame))

    async def send_event(self, name: str = "chat", **fields: object) -> None:
        """Send a scripted event; chat events carry user, text, uuid, hidden like chat.lua."""
        if name == "chat" and self.spend_guard is not None:
            self.spend_guard.check(fields.get("user"), fields.get("text"))
        await self._send({"type": "event", "name": name, **fields})

    async def send_raw(self, payload: str) -> None:
        """Send a string exactly as given, no JSON encoding -- for the malformed-frame proof."""
        ws = self._require_ws()
        log_wire(self.device_id, "out", payload)
        await ws.send(payload)

    async def ping(self, timeout: float) -> float:
        """Round-trip a websocket ping and return its latency; proves the socket is still alive."""
        pong = await self._require_ws().ping()
        return await asyncio.wait_for(pong, timeout)

    async def close(self) -> None:
        """Scenario-initiated local close; waits for the reader to observe it."""
        if self.ws is None:
            return
        await self.ws.close()
        if self._reader is not None:
            await self._reader

    # ------------------------------------------------------------------ canned replies
    def build_reply(self, cmd_msg: Frame) -> Frame:
        """The canned reply for one cmd frame, mirroring the Lua the role stands in for (D-03).

        Worker role returns the data shape client.lua's tools table produces for each
        primitive and client.lua's own ``unknown tool <name>`` error for anything else; chat
        role returns chat.lua's ``say`` result and its ``base only supports say`` error. The
        bridge-local ``list_devices`` is answered by either role with this device's entry.
        """
        tool = str(cmd_msg.get("tool"))
        raw_args = cmd_msg.get("args")
        args: dict[str, object] = raw_args if isinstance(raw_args, dict) else {}
        if tool == "list_devices":
            # Keyed on the tool name, not the role: today's bridge answers list_devices from its
            # own registry and never sends it, but a later agent loop could forward it to
            # whichever connection default_worker() picks, so either role answers it.
            return {self.device_id: {"role": self.wire_role, "caps": list(self.caps)}}
        if self.role == "chat":
            return self._chat_reply(tool)
        return self._worker_reply(tool, args)

    @staticmethod
    def _chat_reply(tool: str) -> Frame:
        if tool == "say":
            return {"ok": True, "data": {"queued": True}}
        return {"ok": False, "error": "base only supports say"}

    def _worker_reply(self, tool: str, args: dict[str, object]) -> Frame:
        if tool == "status":
            status: Frame = {
                "id": self.device_id,
                "is_turtle": self.turtle,
                "pos": {"x": 0, "y": 64, "z": 0},
                "peripherals": ["minecraft:chest_0", "minecraft:chest_1"],
            }
            if self.turtle:
                status["fuel"] = 1000
            return status
        if tool == "list_chest":
            return {
                "name": args.get("name", "minecraft:chest_0"),
                "size": 27,
                "items": [{"slot": 1, "name": "minecraft:cobblestone", "count": 64}],
            }
        if tool == "push_one_slot":
            limit = args.get("limit")
            return {"moved": limit if isinstance(limit, int) else 64}
        if self.turtle:
            if tool == "move":
                steps = args.get("steps")
                requested = steps if isinstance(steps, int) else 1
                return {"moved": requested, "requested": requested}
            if tool == "turn":
                return {"ok": True}
            if tool == "dig":
                return {"dug": True}
            if tool == "inspect":
                return {"forward": "air", "up": "air", "down": "minecraft:stone"}
            if tool == "refuel":
                return {"before": 1000, "after": 1000}
        return unknown_tool(tool)

    @staticmethod
    def envelope(cid: object, reply: Frame) -> Frame:
        """Wrap a build_reply() value as the result frame the Lua session loops send.

        Canned data becomes ``ok: true, data: <reply>``. A reply that is already an error or
        a chat-style ``{ok, data}`` envelope (client.lua's unknown-tool error, chat.lua's say
        result) is sent as-is.
        """
        if isinstance(reply.get("ok"), bool) and ("error" in reply or "data" in reply):
            return {"type": "result", "cid": cid, **reply}
        return {"type": "result", "cid": cid, "ok": True, "data": reply}

    # ------------------------------------------------------------------ receiving
    async def run(self) -> None:
        """Background reader: log, queue and auto-answer inbound frames until the socket closes."""
        ws = self._require_ws()
        try:
            async for raw in ws:
                text = raw if isinstance(raw, str) else raw.decode("utf-8", "replace")
                log_wire(self.device_id, "in", text)
                frame = _parse_frame(text)
                self._observe(frame)
                if frame.get("type") == "cmd":
                    await self._send(self.envelope(frame.get("cid"), self.build_reply(frame)))
        except ConnectionClosed:
            pass
        finally:
            close: Frame = {"type": "close", "code": ws.close_code, "reason": ws.close_reason}
            log_wire(self.device_id, "in", close)
            self._observe(close)

    def _observe(self, frame: Frame) -> None:
        self.seen.append(frame)
        self.frames.put_nowait(frame)

    async def expect(
        self, predicate: Callable[[Frame], bool], timeout: float, what: str = "matching frame"
    ) -> Frame:
        """Await the next frame satisfying ``predicate``; TimeoutError if none arrives in time.

        Frames that do not match are consumed (they stay in ``seen``). Every wait is bounded
        (D-14): there is no unbounded receive anywhere in the harness.
        """
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while True:
            remaining = deadline - loop.time()
            if remaining <= 0:
                raise TimeoutError(f"{self.device_id}: no {what} within {timeout:g}s")
            try:
                frame = await asyncio.wait_for(self.frames.get(), remaining)
            except TimeoutError:
                raise TimeoutError(f"{self.device_id}: no {what} within {timeout:g}s") from None
            if predicate(frame):
                return frame

    async def expect_close(self, timeout: float) -> int:
        """Await the connection closing and return the close code the bridge sent."""
        frame = await self.expect(lambda f: f.get("type") == "close", timeout, "close frame")
        code = frame.get("code")
        return code if isinstance(code, int) else 1006

    async def expect_no_close(self, timeout: float) -> None:
        """Prove the hello was accepted: fail if the bridge closes the socket within the window."""
        try:
            frame = await self.expect(lambda f: f.get("type") == "close", timeout, "close frame")
        except TimeoutError:
            return
        raise ScenarioError(
            f"{self.device_id}: bridge closed the connection within {timeout:g}s "
            f"(code={frame.get('code')}, reason={frame.get('reason')!r})"
        )


Scenario = Callable[[FakeDevice, ScenarioArgs], Awaitable[None]]


# ---------------------------------------------------------------------- CLI
def make_device(
    role: Role, turtle: bool, host: str, port: int, token: str, guard: SpendGuard
) -> FakeDevice:
    """Build the one device this process plays, with the caps its Lua counterpart advertises."""
    if role == "chat":
        return FakeDevice("chat", "harness-chat", host, port, token, CHAT_CAPS, False, guard)
    caps = TURTLE_CAPS if turtle else COMPUTER_CAPS
    return FakeDevice("worker", "harness-worker", host, port, token, caps, turtle, guard)


def build_parser() -> argparse.ArgumentParser:
    """The harness command line; built before Settings() so --help needs no .env."""
    # Local import: scenarios.py imports FakeDevice from this module, so importing it at the
    # top would be circular. Argument parsing itself has no side effects.
    from harness.scenarios import SCENARIOS

    parser = argparse.ArgumentParser(
        prog="harness",
        description="Fake device harness: play a chat or worker device against the running bridge.",
    )
    parser.add_argument("--role", choices=["chat", "worker"], required=True)
    parser.add_argument("--scenario", choices=sorted(SCENARIOS), required=True)
    parser.add_argument(
        "--turtle", action="store_true", help="worker connects as role 'turtle' with movement caps"
    )
    parser.add_argument(
        "--spend",
        action="store_true",
        help="allow the one scenario that costs a real model call (devices-question)",
    )
    parser.add_argument(
        "--token", default=None, help="hello token override (wrong-token scenario); may be empty"
    )
    return parser


async def run_scenario(name: str, scenario: Scenario, dev: FakeDevice, args: ScenarioArgs) -> int:
    """Run one scenario, close the primary device, then print the verdict line and exit code."""
    verdict, code = f"PASS: {name}", 0
    try:
        await scenario(dev, args)
    except SpendRefusedError as exc:
        verdict, code = f"REFUSED: {name} - {exc}", 2
    except (ScenarioError, TimeoutError, ConnectionClosed, OSError) as exc:
        verdict, code = f"FAIL: {name} - {exc}", 1
    finally:
        await dev.close()
    print(verdict, flush=True)
    return code


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point for ``uv run harness``: parse args, load settings, run the scenario."""
    parser = build_parser()
    args = parser.parse_args(argv)
    from harness.scenarios import SCENARIOS

    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
        return 2
    token: str = args.token if args.token is not None else settings.bridge_token
    guard = SpendGuard(tuple(settings.allowed_players), settings.command_prefix, args.spend)
    dev = make_device(args.role, args.turtle, settings.host, settings.port, token, guard)
    scenario_args = ScenarioArgs(args.spend, args.turtle, token, settings)
    print(f"harness: {dev.device_id} ({dev.wire_role}) -> {dev.url} scenario={args.scenario}")
    return asyncio.run(run_scenario(args.scenario, SCENARIOS[args.scenario], dev, scenario_args))


if __name__ == "__main__":
    sys.exit(main())

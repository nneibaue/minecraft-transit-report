"""In-process checks for bridge.py's hello handshake and command bookkeeping (Phase 2 plan 02-02).

Zero-spend, no live server: ``bridge.handler`` and ``bridge.send_cmd`` are driven with a fake
websocket object, so nothing here touches the network or the model. The pytest suite is deferred
to v1.1 (PROJECT.md), so this module has no test-framework dependency: every ``test_*`` function
is pytest-collectable later, and running the file directly emits TAP so the run can be checked
mechanically today.

    uv run python tests/test_bridge_resilience.py
"""

from __future__ import annotations

import asyncio
import inspect
import json
import logging
import sys
import traceback
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from pydantic import ValidationError  # noqa: E402
from websockets.exceptions import ConnectionClosed  # noqa: E402

from bridge import bridge as b  # noqa: E402
from bridge.settings import Settings  # noqa: E402

TOKEN = "correct-horse-battery"
WRONG_TOKEN = "wrong-token-value"


def make_settings(**overrides: Any) -> Settings:
    """Build a Settings for tests without reading any .env file on this machine."""
    values: dict[str, Any] = {
        "bridge_token": TOKEN,
        "allowed_players": ["Nate"],
        "anthropic_api_key": "sk-ant-test",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def hello(**fields: Any) -> str:
    """A hello frame with a valid token; pass id=None to omit the id field."""
    frame: dict[str, Any] = {"type": "hello", "token": TOKEN, "role": "computer", "caps": []}
    frame.update(fields)
    return json.dumps({k: v for k, v in frame.items() if v is not None})


class FakeWs:
    """Just enough of websockets' ServerConnection for handler() and send_cmd()."""

    def __init__(
        self,
        first: str | None = None,
        frames: list[str] | None = None,
        addr: tuple[str, int] = ("127.0.0.1", 50000),
    ) -> None:
        self._first = first
        self._frames = list(frames or [])
        self.remote_address = addr
        self.sent: list[str] = []
        self.closed: tuple[int, str] | None = None
        self._released = asyncio.Event()

    async def recv(self) -> str:
        if self._first is None:
            await asyncio.Future()  # never answers: the hello-timeout path
        assert self._first is not None
        return self._first

    async def send(self, data: str) -> None:
        if self.closed is not None:
            raise ConnectionClosed(None, None)
        self.sent.append(data)

    async def close(self, code: int = 1000, reason: str = "") -> None:
        if self.closed is None:
            self.closed = (code, reason)
        self.release()

    def release(self) -> None:
        """End the message loop from the test side (peer went away)."""
        self._released.set()

    def __aiter__(self) -> FakeWs:
        return self

    async def __anext__(self) -> str:
        if self._frames:
            return self._frames.pop(0)
        await self._released.wait()
        raise StopAsyncIteration


def reset() -> None:
    b.settings = make_settings()
    b.devices.clear()
    b.pending.clear()
    getattr(b, "pending_by_device", {}).clear()


@contextmanager
def capture_logs() -> Iterator[list[logging.LogRecord]]:
    records: list[logging.LogRecord] = []
    handler = logging.Handler()
    handler.emit = records.append  # type: ignore[method-assign]
    previous = (b.log.level, b.log.propagate)
    b.log.setLevel(logging.DEBUG)
    b.log.propagate = False  # keep bridge log lines off the TAP stream
    b.log.addHandler(handler)
    try:
        yield records
    finally:
        b.log.removeHandler(handler)
        b.log.setLevel(previous[0])
        b.log.propagate = previous[1]


def messages(records: list[logging.LogRecord], level: int) -> list[str]:
    return [r.getMessage() for r in records if r.levelno == level]


async def until(pred: Callable[[], bool], what: str, timeout: float = 1.0) -> None:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while not pred():
        assert loop.time() < deadline, f"timed out waiting for: {what}"
        await asyncio.sleep(0.005)


# ----------------------------------------------------------------- Task 1: hello handshake
async def test_non_hello_type_closes_4000_expected_hello() -> None:
    reset()
    ws = FakeWs(json.dumps({"type": "event", "name": "chat"}), addr=("10.0.0.7", 41000))
    with capture_logs() as records:
        await b.handler(ws)  # type: ignore[arg-type]
    assert ws.closed == (4000, "expected hello"), ws.closed
    warnings = messages(records, logging.WARNING)
    assert len(warnings) == 1, warnings
    assert "41000" in warnings[0] and "event" in warnings[0], warnings[0]
    assert not b.devices


async def test_hello_without_id_closes_4000_missing_id() -> None:
    reset()
    ws = FakeWs(hello(id=None), addr=("10.0.0.7", 41001))
    with capture_logs() as records:
        await b.handler(ws)  # type: ignore[arg-type]
    assert ws.closed == (4000, "hello missing id"), ws.closed
    warnings = messages(records, logging.WARNING)
    assert len(warnings) == 1, warnings
    assert "41001" in warnings[0], warnings[0]
    assert not b.devices


async def test_bad_token_closes_4001_and_never_logs_token() -> None:
    reset()
    ws = FakeWs(hello(id="dev-1", token=WRONG_TOKEN), addr=("10.0.0.7", 41002))
    with capture_logs() as records:
        await b.handler(ws)  # type: ignore[arg-type]
    assert ws.closed == (4001, "bad token"), ws.closed
    warnings = messages(records, logging.WARNING)
    assert len(warnings) == 1, warnings
    assert "dev-1" in warnings[0] and "41002" in warnings[0], warnings[0]
    for text in (r.getMessage() for r in records):
        assert WRONG_TOKEN not in text and TOKEN not in text, text
    assert "dev-1" not in b.devices


async def test_same_id_reconnect_replaces_stale_socket() -> None:
    reset()
    old = FakeWs(hello(id="dev-1"), addr=("10.0.0.7", 41003))
    new = FakeWs(hello(id="dev-1"), addr=("10.0.0.7", 41004))
    with capture_logs() as records:
        old_task = asyncio.create_task(b.handler(old))  # type: ignore[arg-type]
        await until(lambda: b.devices.get("dev-1", {}).get("ws") is old, "old registered")
        new_task = asyncio.create_task(b.handler(new))  # type: ignore[arg-type]
        try:
            await until(lambda: b.devices.get("dev-1", {}).get("ws") is new, "new registered")
            assert old.closed == (4000, "replaced"), old.closed
            await asyncio.wait_for(old_task, 1)
            # The stale handler's cleanup must not deregister its replacement (WR-01).
            assert b.devices.get("dev-1", {}).get("ws") is new, b.devices
            infos = messages(records, logging.INFO)
            replaced = [m for m in infos if "dev-1" in m and "replacing stale" in m]
            assert len(replaced) == 1, infos
        finally:
            old.release()
            new.release()
            await asyncio.gather(old_task, new_task, return_exceptions=True)


def test_empty_bridge_token_rejected_by_settings() -> None:
    try:
        make_settings(bridge_token="")
    except ValidationError as exc:
        assert any(e["loc"] == ("bridge_token",) for e in exc.errors()), exc.errors()
    else:
        raise AssertionError("Settings(bridge_token='') validated instead of raising")


# ----------------------------------------------------------------- runner (TAP output)
TESTS: list[Callable[[], Any]] = [
    test_non_hello_type_closes_4000_expected_hello,
    test_hello_without_id_closes_4000_missing_id,
    test_bad_token_closes_4001_and_never_logs_token,
    test_same_id_reconnect_replaces_stale_socket,
    test_empty_bridge_token_rejected_by_settings,
]


def main() -> int:
    logging.getLogger().setLevel(logging.CRITICAL)  # keep bridge log lines off the TAP stream
    passed = failed = 0
    print(f"1..{len(TESTS)}")
    for n, fn in enumerate(TESTS, 1):
        try:
            if inspect.iscoroutinefunction(fn):
                asyncio.run(fn())
            else:
                fn()
        except Exception as exc:
            failed += 1
            print(f"not ok {n} - {fn.__name__}")
            detail = "".join(traceback.format_exception_only(type(exc), exc)).strip()
            print("  ---")
            print(f"  error: {detail}")
            print("  ...")
        else:
            passed += 1
            print(f"ok {n} - {fn.__name__}")
    print(f"# tests {len(TESTS)}")
    print(f"# pass {passed}")
    print(f"# fail {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

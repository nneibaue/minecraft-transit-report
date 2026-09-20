"""
bridge.py : the brain. A websocket server that in-game devices connect to,
plus a Claude agent loop that turns chat requests into device commands.

See turtle-helper/README.md "Setup > 1. Bridge" for the uv + .env setup recipe.
Every configuration default and required environment variable lives in bridge/settings.py.

    uv run bridge/bridge.py
"""

from __future__ import annotations

import asyncio
import json
import logging
import sys
import uuid
from pathlib import Path
from typing import TYPE_CHECKING, cast

import anthropic
from pydantic import ValidationError
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

# bridge.py always runs directly as __main__ via `uv run bridge/bridge.py`, which makes this
# file's own directory (bridge/) sys.path[0]. That collides with this sibling bridge.py file
# when Python resolves the "bridge" package name, raising a circular-import error. Prepending
# the project root ensures the real bridge/ package resolves first. Documented fallback in
# plan 01-01 Task 1, confirmed necessary by empirical testing during execution.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bridge import agent  # noqa: E402
from bridge.settings import Settings  # noqa: E402

if TYPE_CHECKING:
    from websockets.asyncio.server import ServerConnection

log = logging.getLogger("bridge")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# ----------------------------------------------------------------- filled in by main()
settings: Settings
client: anthropic.AsyncAnthropic

# ----------------------------------------------------------------- device registry
devices: dict[str, dict[str, object]] = {}  # id -> {"ws", "role", "caps"}
pending: dict[str, asyncio.Future[dict[str, object]]] = {}  # cid -> future resolved by result


async def send_cmd(
    device_id: str, tool: str, args: dict[str, object] | None = None
) -> dict[str, object]:
    """Send a command to one device and wait for its result."""
    dev = devices.get(device_id)
    if not dev:
        return {"ok": False, "error": f"device '{device_id}' is not connected"}
    cid = uuid.uuid4().hex[:8]
    fut: asyncio.Future[dict[str, object]] = asyncio.get_running_loop().create_future()
    pending[cid] = fut
    websocket = cast("ServerConnection", dev["ws"])
    await websocket.send(json.dumps({"type": "cmd", "cid": cid, "tool": tool, "args": args or {}}))
    try:
        return await asyncio.wait_for(fut, settings.cmd_timeout)
    except TimeoutError:
        return {"ok": False, "error": f"{device_id} did not answer within {settings.cmd_timeout}s"}
    finally:
        pending.pop(cid, None)


async def say(text: str, to: str | None = None) -> None:
    """Speak in game chat via the connected chat device, if any."""
    base = next((d for d, v in devices.items() if v["role"] == "chat"), None)
    if base:
        await send_cmd(base, "say", {"text": text, "to": to, "prefix": settings.robot_name})
    else:
        log.warning("no chat device connected; would say: %s", text)


def default_worker() -> str | None:
    """Pick a connected turtle or computer device to run tools against."""
    for d, v in devices.items():
        if v["role"] in ("turtle", "computer"):
            return d
    return None


# ----------------------------------------------------------------- websocket handling
async def handler(websocket: ServerConnection) -> None:
    """Handle one device connection: hello handshake, then the event/result loop."""
    try:
        raw = await asyncio.wait_for(websocket.recv(), 10)
        hello = json.loads(raw)
    except Exception:
        await websocket.close(4000, "expected hello")
        return
    if hello.get("type") != "hello" or hello.get("token") != settings.bridge_token:
        log.warning("rejected connection from %s", websocket.remote_address)
        await websocket.close(4001, "bad token")
        return

    dev_id = hello["id"]
    devices[dev_id] = {
        "ws": websocket,
        "role": hello.get("role", "computer"),
        "caps": hello.get("caps", []),
    }
    log.info(
        "device connected: %s (%s) caps=%s",
        dev_id,
        devices[dev_id]["role"],
        devices[dev_id]["caps"],
    )

    try:
        async for raw in websocket:
            msg = json.loads(raw)
            t = msg.get("type")
            if t == "result":
                fut = pending.get(msg.get("cid"))
                if fut and not fut.done():
                    fut.set_result(msg)
            elif t == "event":
                asyncio.create_task(on_event(dev_id, msg))
    except ConnectionClosed:
        pass
    finally:
        devices.pop(dev_id, None)
        log.info("device disconnected: %s", dev_id)


async def on_event(dev_id: str, ev: dict[str, object]) -> None:
    """Dispatch a device event; only "chat" events from allowed players reach the agent."""
    if ev.get("name") == "chat":
        user = str(ev.get("user", ""))
        text = str(ev.get("text", "")).strip()
        if not text.lower().startswith(settings.command_prefix.lower()):
            return
        if settings.allowed_players and user not in settings.allowed_players:
            log.info("ignoring %s (not allowed)", user)
            return
        request = text[len(settings.command_prefix):].strip() or "hello"
        try:
            await agent.handle_request(user, request)
        except Exception as e:  # never let one bad request kill the bridge
            log.exception("request failed")
            await say(f"Sorry {user}, something went wrong: {type(e).__name__}", to=user)
    else:
        log.info("event from %s: %s", dev_id, ev)


async def main() -> None:
    """Load and validate config, verify credentials, wire up the agent, then serve forever."""
    global settings, client
    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}")
        raise SystemExit(1) from None

    client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)

    try:
        await client.models.retrieve(settings.model)
    except anthropic.AuthenticationError:
        log.error("invalid or revoked ANTHROPIC_API_KEY")
        raise SystemExit(1) from None
    except anthropic.NotFoundError:
        log.error("unknown model: %s", settings.model)
        raise SystemExit(1) from None
    except anthropic.APIConnectionError as exc:
        log.warning("could not verify model (connection issue): %s; bridge will still listen", exc)
    else:
        log.info("verified model: %s", settings.model)

    env_file = Path(__file__).resolve().parent.parent / ".env"
    env_file_desc = str(env_file) if env_file.exists() else "none"
    log.info(
        "config: model=%s host=%s:%d prefix=%r allowed_players=%s "
        "ping_interval=%s ping_timeout=%s env_file=%s",
        settings.model,
        settings.host,
        settings.port,
        settings.command_prefix,
        settings.allowed_players,
        settings.ping_interval,
        settings.ping_timeout,
        env_file_desc,
    )
    log.info("bridge_token: %s", "set" if settings.bridge_token else "NOT SET")

    agent.configure(settings, client, devices, send_cmd, say, default_worker)

    async with serve(
        handler,
        settings.host,
        settings.port,
        ping_interval=settings.ping_interval or None,
        ping_timeout=settings.ping_timeout or None,
    ):
        log.info("listening on ws://%s:%d", settings.host, settings.port)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())

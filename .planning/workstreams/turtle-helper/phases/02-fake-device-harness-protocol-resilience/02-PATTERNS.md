# Phase 2: Fake Device Harness & Protocol Resilience - Pattern Map

**Mapped:** 2026-09-22  
**Files analyzed:** 9 new/modified files  
**Analogs found:** 7 with tracked source matches / 9 total

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `turtle/turtle-helper/harness/` (package) or `harness.py` | CLI tool / test harness | WebSocket client, event-driven | `bridge/bridge.py` | partial — websocket async/logging patterns; no tracked Lua harness ref |
| `bridge/bridge.py` (D-10, D-11, D-12, D-16 amendments) | WebSocket server handler | connection management, error handling | Self (existing) | exact — in-place amendments |
| `bridge/settings.py` (CR-01 fold-in) | Configuration validation | config parsing | Self (existing) | exact — one-line amendment |
| `bridge/agent.py` (D-05 final: Pydantic AI rewrite) | AI agent with typed tools | tool-use loop, per-player history | Self (current hand-rolled version) | exact — full rewrite but same role and data flow |
| `turtle/client.lua` (D-07 rewrite) | Device primitives | command execution, tool dispatch | Self (Phase 1 starter) | exact — prune and keep patterns |
| `turtle/turtle-helper/.gitignore` | Version control | N/A | Self (existing) | exact — one-line addition |
| `turtle/turtle-helper/README.md` (D-17 Harness section) | Documentation | N/A | Self (existing) | exact — append section |
| `turtle/turtle-helper/CLAUDE.md` (D-17 amendments) | Architecture documentation | N/A | Self (existing) | exact — update sections |
| `turtle/turtle-helper/pyproject.toml` (add pydantic-ai) | Project metadata | N/A | Self (existing) | exact — add dependency |

---

## Pattern Assignments

### `turtle/turtle-helper/harness/` Package (CLI tool, WebSocket client, event-driven)

**Closest Analogs:**
- `bridge/bridge.py` — async/await patterns, websocket handling via `websockets.asyncio`, logging setup, dependency injection style
- `bridge/agent.py` — structured data patterns, per-run context

**Imports pattern** (from `bridge/bridge.py` lines 11–34):

```python
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
```

For harness (client-side), substitute:
```python
import websockets.asyncio.client
from websockets.exceptions import ConnectionClosedError
```

**Async function pattern** (from `bridge/bridge.py` lines 51–68, `send_cmd`):

```python
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
```

Harness pattern: WebSocket client connect, send JSON, await receive with timeout, catch exceptions.

**Logging pattern** (from `bridge/bridge.py` lines 39–40):

```python
log = logging.getLogger("bridge")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# Usage:
log.info("device connected: %s (%s) caps=%s", dev_id, role, caps)
log.warning("rejected connection from %s", websocket.remote_address)
```

For harness: One line per wire message with timestamp, device ID, arrow direction, and compact JSON.

**CLI argument parsing** (no tracked analog; use stdlib argparse):

```python
import argparse

parser = argparse.ArgumentParser(description="Fake device harness for protocol testing")
parser.add_argument("--role", choices=["chat", "worker"], required=True)
parser.add_argument("--scenario", required=True, help="scenario name to run")
parser.add_argument("--turtle", action="store_true", help="use turtle role (worker only)")
parser.add_argument("--spend", action="store_true", help="allow paid API calls")
parser.add_argument("--token", help="override bridge token")
args = parser.parse_args()
```

---

### `bridge/bridge.py` Amendments (D-10, D-11, D-12, D-16)

**Analog:** Self (existing code)

**D-10: Drop handling in `send_cmd`** (lines 51–68, add try/except for `ConnectionClosed`):

Current code (lines 62–68):
```python
await websocket.send(json.dumps({"type": "cmd", "cid": cid, "tool": tool, "args": args or {}}))
try:
    return await asyncio.wait_for(fut, settings.cmd_timeout)
except TimeoutError:
    return {"ok": False, "error": f"{device_id} did not answer within {settings.cmd_timeout}s"}
finally:
    pending.pop(cid, None)
```

Fix (wrap send and wait in try/except):
```python
websocket = cast("ServerConnection", dev["ws"])
try:
    await websocket.send(json.dumps({"type": "cmd", "cid": cid, "tool": tool, "args": args or {}}))
    return await asyncio.wait_for(fut, settings.cmd_timeout)
except ConnectionClosed:
    return {"ok": False, "error": f"{device_id} disconnected during command"}
except TimeoutError:
    return {"ok": False, "error": f"{device_id} did not answer within {settings.cmd_timeout}s"}
finally:
    pending.pop(cid, None)
```

Also add cleanup in `handler` finally block to resolve pending futures for the device:
```python
finally:
    # D-10: resolve any pending futures for this device
    for cid, fut in list(pending.items()):
        if fut.get_context().get("device_id") == dev_id:  # or track pending by device separately
            fut.set_result({"ok": False, "error": f"{dev_id} disconnected"})
            pending.pop(cid, None)
    devices.pop(dev_id, None)
    log.info("device disconnected: %s", dev_id)
```

**D-11: Socket replacement in `handler`** (lines 89–130, check socket identity in finally):

Current code (lines 102–107, 127–129):
```python
dev_id = hello["id"]
devices[dev_id] = {
    "ws": websocket,
    "role": hello.get("role", "computer"),
    "caps": hello.get("caps", []),
}
# ...
finally:
    devices.pop(dev_id, None)
    log.info("device disconnected: %s", dev_id)
```

Fix (replace old connection and check socket in finally):
```python
dev_id = hello.get("id")
if not dev_id:
    log.warning("rejected hello with no id from %s", websocket.remote_address)
    await websocket.close(4000, "hello missing id")
    return

# D-11: Replace stale connection
old_ws = devices.get(dev_id)
if old_ws and old_ws.get("ws") is not websocket:
    log.info("replacing stale device %s from %s", dev_id, websocket.remote_address)
    try:
        await old_ws["ws"].close(4000, "replaced")
    except Exception:
        pass

devices[dev_id] = {
    "ws": websocket,
    "role": hello.get("role", "computer"),
    "caps": hello.get("caps", []),
}

# ...

finally:
    # Only deregister if this socket is still the current one
    if devices.get(dev_id, {}).get("ws") is websocket:
        devices.pop(dev_id, None)
    log.info("device disconnected: %s", dev_id)
```

**D-12: Malformed frame handling in `handler` message loop** (lines 116–124, add try/except around message parsing):

Current code (lines 116–124):
```python
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
```

Fix (wrap message handling, log and continue on errors):
```python
try:
    async for raw in websocket:
        try:
            msg = json.loads(raw)
            t = msg.get("type")
            if t == "result":
                cid = msg.get("cid")
                if not cid or cid not in pending:
                    log.warning("result with unknown cid from %s: %s", dev_id, cid)
                    continue
                fut = pending.get(cid)
                if fut and not fut.done():
                    fut.set_result(msg)
            elif t == "event":
                asyncio.create_task(on_event(dev_id, msg))
            elif t is None:
                log.warning("frame with no type from %s: %.200s", dev_id, raw)
            else:
                log.warning("unknown frame type from %s: %s", dev_id, t)
        except json.JSONDecodeError:
            log.warning("malformed JSON from %s: %.200s", dev_id, raw[:200])
            continue
        except Exception as e:
            log.warning("frame handling error from %s: %s", dev_id, e)
            continue
except ConnectionClosed:
    pass
```

**D-16: Enhanced rejection logging** (lines 97–100, name the reason):

Current code (lines 97–100):
```python
if hello.get("type") != "hello" or hello.get("token") != settings.bridge_token:
    log.warning("rejected connection from %s", websocket.remote_address)
    await websocket.close(4001, "bad token")
    return
```

Fix (distinguish reasons):
```python
if hello.get("type") != "hello":
    log.warning("rejected non-hello from %s: type=%s", websocket.remote_address, hello.get("type"))
    await websocket.close(4000, "expected hello")
    return

device_id = hello.get("id")
if not device_id:
    log.warning("rejected hello with no id from %s", websocket.remote_address)
    await websocket.close(4000, "hello missing id")
    return

if hello.get("token") != settings.bridge_token:
    log.warning("rejected device %s from %s: bad token", device_id, websocket.remote_address)
    await websocket.close(4001, "bad token")
    return
```

---

### `bridge/settings.py` Amendment (CR-01 fold-in)

**Analog:** Self (existing code, lines 50–52)

**Current code:**
```python
bridge_token: str = Field(
    description="Shared secret devices must present in their hello handshake."
)
```

**Fix (add min_length=1):**
```python
bridge_token: str = Field(
    min_length=1,
    description="Shared secret devices must present in their hello handshake."
)
```

---

### `bridge/agent.py` Rewrite (D-05 final plan: Pydantic AI)

**Analog:** Self (current hand-rolled version, lines 32–281)

**Existing pattern: System template** (lines 32–47, carried unchanged):

```python
SYSTEM_TEMPLATE = """You are {robot_name}, a helpful robot assistant living inside a Minecraft
(All the Mods 9) world, in the spirit of Heinlein's Hired Girl. Players give you chores in chat;
you carry them out using turtles and computers connected to you, then report back briefly.

Rules:
- Call list_devices first if you don't know what's connected. Pass "device" only when there are
  several.
- Prefer high-level tools (sort_chest) over step-by-step movement. Do not walk a turtle around
  one block at a time unless asked.
- When something can't be done, say so plainly and suggest what would fix it (e.g. a missing
  rule).
- Finish every task with exactly one say() containing a short, friendly summary (1-2 sentences).
  No markdown in chat.
- Item ids look like "minecraft:iron_ingot" or "mekanism:hdpe_sheet". Inventory names look like
  "minecraft:chest_3".
"""
```

**Existing pattern: Tool definitions** (lines 72–223, to be converted to typed functions):

Example from `DEVICE_TOOLS` (lines 74–89):
```python
{
    "name": "status",
    "description": "Fuel, position, and attached peripherals of a device.",
    "input_schema": {"type": "object", "properties": {"device": {"type": "string"}}},
},
{
    "name": "list_chest",
    "description": "List the items in an inventory on the wired network.",
    "input_schema": {
        "type": "object",
        "properties": {
            "device": {"type": "string"},
            "name": {"type": "string", "description": "peripheral name e.g. minecraft:chest_0"},
        },
        "required": ["name"],
    },
},
```

Convert to typed functions (D-06):
```python
from pydantic import BaseModel, Field
from pydantic_ai import RunContext

class StatusArgs(BaseModel):
    device: str | None = Field(None, description="device id; default to any available worker")

async def status_tool(ctx: RunContext, device: str | None = None) -> dict[str, object]:
    """Fuel, position, and attached peripherals of a device."""
    device_id = device or default_worker()
    if not device_id:
        raise ValueError("no turtle or computer connected")
    result = await send_cmd(device_id, "status", {})
    if not result.get("ok"):
        return result
    return result.get("data", {})

class ListChestArgs(BaseModel):
    device: str | None = Field(None, description="device id")
    name: str = Field(..., description="peripheral name e.g. minecraft:chest_0")

async def list_chest_tool(ctx: RunContext, device: str | None = None, name: str = "") -> dict[str, object]:
    """List the items in an inventory on the wired network."""
    device_id = device or default_worker()
    if not device_id:
        raise ValueError("no turtle or computer connected")
    result = await send_cmd(device_id, "list_chest", {"name": name})
    if not result.get("ok"):
        return result
    return result.get("data", {})
```

**Existing pattern: Per-player history** (lines 225–226):

```python
histories: dict[str, list[dict[str, object]]] = {}  # per-player conversation memory
MAX_TURNS = 20
```

In Pydantic AI, this becomes `message_history` on the Agent object, auto-maintained per context.

**Existing pattern: `run_tool` dispatch** (lines 229–242):

```python
async def run_tool(name: str, args: dict[str, object]) -> dict[str, object]:
    """Execute a tool by name with JSON args, return a JSON-safe result."""
    if name == "list_devices":
        return {d: {"role": v["role"], "caps": v["caps"]} for d, v in devices.items()}
    if name == "say":
        to_arg = args.get("to")
        to = to_arg if isinstance(to_arg, str) else None
        await say(str(args["text"]), to)
        return {"ok": True}
    device_arg = args.pop("device", None)
    device = device_arg if isinstance(device_arg, str) else default_worker()
    if not device:
        return {"ok": False, "error": "no worker device connected"}
    return await send_cmd(device, name, args)
```

In Pydantic AI, individual tools call `send_cmd` directly; the framework handles dispatch and error handling.

**Existing pattern: `handle_request` with message history** (lines 245–281):

```python
async def handle_request(user: str, text: str) -> None:
    """Process a chat request through the tool-use loop and speak the result."""
    log.info("request from %s: %s", user, text)
    hist = histories.setdefault(user, [])
    hist.append({"role": "user", "content": f"[{user}] {text}"})

    def _bad_start() -> bool:
        return hist[0]["role"] != "user" or not isinstance(hist[0]["content"], str)

    while len(hist) > 1 and (len(hist) > MAX_TURNS * 2 or _bad_start()):
        hist.pop(0)

    for _ in range(12):  # cap tool rounds per request
        resp = await client.messages.create(
            model=settings.model,
            max_tokens=1024,
            system=system,
            tools=cast(Any, DEVICE_TOOLS + LOCAL_TOOLS),
            messages=cast(Any, hist),
        )
        hist.append({"role": "assistant", "content": resp.content})
        if resp.stop_reason != "tool_use":
            break
        results = []
        for block in resp.content:
            if block.type == "tool_use":
                out = await run_tool(block.name, dict(block.input))
                log.info("tool %s(%s) -> %s", block.name, block.input, json.dumps(out)[:200])
                results.append(
                    {"type": "tool_result", "tool_use_id": block.id, "content": json.dumps(out)}
                )
        hist.append({"role": "user", "content": results})
```

In Pydantic AI, this becomes:
```python
async def handle_request(user: str, text: str) -> None:
    """Process a chat request through the agent and speak the result."""
    log.info("request from %s: %s", user, text)
    toolset = build_toolset()  # per-run filtering (D-09)
    result = await agent.run(
        text,
        toolsets=[toolset],
        context=RunContext(...) or similar keying mechanism for per-player history
    )
    # result.data contains the final text from the model
    await say(result.data)
    # message_history is auto-maintained by agent
```

---

### `turtle/client.lua` Rewrite (D-07)

**Analog:** Self (Phase 1 starter, lines 1–214)

**Pattern to keep: readFile/writeFile helpers** (lines 18–24):

```lua
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end

local function writeFile(path, s)
  local f = fs.open(path, "w"); f.write(s); f.close()
end
```

**Pattern to keep: tools dispatch table structure** (lines 60–178):

```lua
local tools = {}

function tools.status()
  -- ...
  return out
end

function tools.list_chest(args)
  -- ...
  return result
end

-- if turtle then
--   function tools.move(args) ... end
--   etc.
-- end
```

**Pattern to keep: capabilities() and session() loop** (lines 181–214):

```lua
local function capabilities()
  local caps = {}
  for name in pairs(tools) do caps[#caps + 1] = name end
  table.sort(caps)
  return caps
end

local function session(ws)
  ws.send(textutils.serialiseJSON({
    type = "hello", id = DEVICE_ID, token = TOKEN,
    role = turtle and "turtle" or "computer", caps = capabilities(),
  }))
  log("connected as", DEVICE_ID)

  while true do
    local raw = ws.receive()
    if raw == nil then return end
    local msg = textutils.unserialiseJSON(raw)
    if msg and msg.type == "cmd" then
      local tool = tools[msg.tool]
      -- execute and send result
    end
  end
end
```

**Patterns to remove in D-07:**
- `loadRules()` / `saveRules()` (lines 38–48) — moved to Python bridge
- `sort_chest` (lines 86–103) — composition moved to Python; primitive `list_chest` and `push_one` stay
- `list_rules` / `add_rule` / `remove_rule` / `set_overflow` (lines 105–127) — moved to Python local tools
- `destFor()` helper (lines 50–55) — moved to Python

**Primitives to keep:**
- `status()` (lines 63–72)
- `list_chest(args)` (lines 75–83)
- New: `push_one_slot(args)` — wraps `pushItems`, sends one slot to a destination
- `move(args)` / `turn(args)` / `dig(args)` / `inspect()` / `refuel(args)` (lines 132–167, if turtle)
- `run_lua(args)` (lines 171–177, if ALLOW_EVAL)

---

### `.gitignore` Amendment

**Analog:** Self (existing)

**Current (if it exists):**
```gitignore
# (existing entries)
```

**Add:**
```gitignore
rules.json
```

---

### `README.md` Amendment (D-17 Harness section)

**Analog:** Self (existing)

**Append after existing "Setup" sections:**

```markdown
## Harness: Protocol Testing and Integration

The harness is a standalone Python tool that simulates a device connecting to the bridge, runs scripted scenarios with expectations, and validates the wire protocol.

### Installation

The harness is part of the same `uv` project; no separate install needed.

### Quick Start

**Two terminals:** Start the bridge in one, the harness in another.

```bash
# Terminal 1: bridge
uv run bridge/bridge.py

# Terminal 2: harness
uv run harness --role chat --scenario hello-handshake
```

### Scenarios

Each scenario runs a sequence of steps (connect, send events, wait for commands, expect results) and exits with 0 (pass) or 1 (fail).

| Scenario | Role | What it proves | Terminal recipe |
|----------|------|---------------|-----------------|
| `hello-handshake` | chat | HARN-01: hello handshake, wire messages print correctly | `uv run harness --role chat --scenario hello-handshake` |
| `devices-question` | chat | HARN-02: chat event → model call → say result (one paid call) | Start worker first: `uv run harness --role worker --scenario status-command` in terminal 2; then `uv run harness --role chat --scenario devices-question --spend` in terminal 1 |
| `status-command` | worker | HARN-03: worker device answers status and other tool commands | `uv run harness --role worker --scenario status-command` |
| `drop-and-reconnect` | chat | HARN-04, RESIL-03: drop during command, reconnect, old command fails cleanly, new command succeeds | `uv run harness --role chat --scenario drop-and-reconnect` |
| `wrong-token` | chat | RESIL-04: bad token rejected with close code 4001 and logged | `uv run harness --role chat --scenario wrong-token --token bad_value` |
| `disallowed-player` | chat | RESIL-05: chat from non-allowed player ignored, logged, no model call | `uv run harness --role chat --scenario disallowed-player` |

### Flags

- `--spend` (chat role only): Allow the devices-question scenario to emit a real chat event (costs one API call). Required to run the paid scenario. Always specified explicitly so API spend is intentional.
- `--turtle`: Add turtle-specific movement capabilities to the worker role. Default: computer role only.
- `--token <override>`: Override the bridge token from `.env` with a custom value. Used for the wrong-token scenario.

### Output

Each scenario prints one line per wire message: timestamp, device ID, direction arrow (`→` bridge, `←` device), and the compact JSON exactly as it went over the wire. The process exits 0 on pass and 1 on fail, with a one-line verdict.

```
2026-09-22 10:15:32.123 device-1 → {"type":"hello","id":"device-1","token":"secret","role":"chat","caps":["say"]}
2026-09-22 10:15:32.145 device-1 ← {"type":"cmd","cid":"abc123","tool":"list_devices","args":{}}
...
PASS: devices-question (1 result matched, 0 timeouts)
```

---
```

---

### `CLAUDE.md` Amendments (D-17)

**Analog:** Self (existing sections)

**Dev loop convention line (update):**

Current:
```markdown
- Dev loop: run `bridge.py` locally behind a tunnel, edit Lua via `edit` in game or pastebin/wget.
```

Updated:
```markdown
- Dev loop: run `bridge.py` locally behind a tunnel; test with the harness (`uv run harness --role <role> --scenario <name>`); edit Lua via `edit` in game or pastebin/wget.
```

**Architecture section (add thin-Lua rule and rules-on-bridge):**

After the existing architecture diagram, add:

```markdown
### Composition and Persistence (Phase 2+)

- **Thin Lua, thick Python.** Lua exposes one-to-one CC:Tweaked primitives (status, list_chest, push_one_slot, movement, etc.); Python composes them into high-level tools (sort_chest, pathfinding, etc.). This keeps Lua simple and testable on the device, while composition logic lives where it's easy to debug and version-control (the bridge).
- **Rules on the bridge.** Sorting rules persist in `rules.json` beside `.env` on the bridge, not on the device. Devices store only their secret token and the Lua code. Local tools (`add_rule`, `remove_rule`, `list_rules`, `set_overflow`) edit the bridge-side file.
```

---

### `pyproject.toml` Amendment

**Analog:** Self (existing, lines 1–38)

**Current dependencies (lines 6–10):**
```toml
dependencies = [
    "websockets==17.1",
    "anthropic==1.7.0",
    "pydantic-settings==2.15.0",
]
```

**Updated (add pydantic-ai):**
```toml
dependencies = [
    "websockets==17.1",
    "anthropic==1.7.0",
    "pydantic-settings==2.15.0",
    "pydantic-ai-slim[anthropic]==2.46.0",
]
```

**Also add `[project.scripts]` entry for the harness** (after `[tool.hatch.build.targets.wheel]`):

```toml
[project.scripts]
harness = "harness:main"
```

(This allows `uv run harness --role ... --scenario ...` without the sys.path workaround `bridge.py` needs.)

---

## Shared Patterns

### Async WebSocket Handling and Error Recovery

**Source:** `bridge/bridge.py` (lines 21–24, 51–68, 89–130)

**Apply to:** Harness WebSocket client, bridge handler

```python
from websockets.exceptions import ConnectionClosed, ConnectionClosedError

# Harness client connect with timeout:
try:
    ws = await asyncio.wait_for(
        websockets.asyncio.client.connect(f"ws://{settings.host}:{settings.port}"),
        timeout=10
    )
except (asyncio.TimeoutError, OSError) as e:
    log.error("failed to connect: %s", e)
    return 1

# Send JSON and await with timeout (harness):
try:
    await ws.send(json.dumps(message))
    response = await asyncio.wait_for(ws.recv(), timeout=10)
except ConnectionClosed:
    log.info("connection closed during operation")
except asyncio.TimeoutError:
    log.warning("no response within timeout")
```

### JSON Serialization and Message Shapes

**Source:** `bridge/bridge.py` (line 62), `client.lua` (lines 189–192, 199–200)

**Apply to:** Harness and bridge wire protocol

```python
# Bridge (Python):
await websocket.send(json.dumps({
    "type": "cmd",
    "cid": cid,
    "tool": tool,
    "args": args or {}
}))

# Harness (Python, same):
await ws.send(json.dumps({
    "type": "hello",
    "id": device_id,
    "token": token,
    "role": role,
    "caps": capabilities
}))
```

### Logging: Device Operations and Errors

**Source:** `bridge/bridge.py` (lines 39–40, 108–113, 129, 140, 146–147)

**Apply to:** All Python modules in harness and bridge

```python
log = logging.getLogger(__name__)

# Connection lifecycle:
log.info("device connected: %s (%s) caps=%s", dev_id, role, caps)
log.info("device disconnected: %s", dev_id)

# Errors and rejections:
log.warning("rejected device %s from %s: bad token", device_id, remote_address)
log.warning("malformed JSON from %s: %.200s", device_id, payload[:200])

# Tool execution (for bridge agent):
log.info("tool %s(%s) -> %s", tool_name, args, json.dumps(result)[:200])

# For harness:
log.info("%s %s → %s", timestamp, device_id, json.dumps(message))
log.info("%s %s ← %s", timestamp, device_id, json.dumps(message))
```

### Settings and Configuration

**Source:** `bridge/settings.py` (lines 29–66)

**Apply to:** Any new config in bridge or harness

```python
from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    host: str = Field(default="127.0.0.1", description="...")
    port: int = Field(default=8765, description="...")
    bridge_token: str = Field(min_length=1, description="...")
    
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )
```

### Type Hints and Function Signatures

**Source:** `bridge/bridge.py` (lines 51–68, 152–203), `bridge/agent.py` (lines 20–29, 245)

**Apply to:** All Python functions

```python
from __future__ import annotations
from typing import TYPE_CHECKING, Awaitable, Callable, cast

# Function signatures with full type hints:
async def send_cmd(
    device_id: str, tool: str, args: dict[str, object] | None = None
) -> dict[str, object]:
    ...

# Async callables as type aliases:
SendCmdFn = Callable[[str, str, dict[str, object] | None], Awaitable[dict[str, object]]]
```

---

## No Analog Found

Files with no close match in the codebase or requiring new patterns:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `turtle/turtle-helper/harness/` (package structure & main CLI) | CLI tool | event-driven | New capability; patterns adapted from bridge.py async/logging, but no tracked harness reference; follows stdlib argparse and asyncio conventions |
| `turtle/turtle-helper/rules.json` (git-ignored runtime file) | sorting rule persistence | file I/O | New file created at runtime; schema and location pattern follow `.env` approach in settings.py |

---

## Metadata

**Analog search scope:** `turtle/turtle-helper/bridge/`, `turtle/turtle-helper/base/`, `turtle/turtle-helper/turtle/`, project root config files

**Files scanned:** 4 Python modules, 2 Lua files (untracked), 3 config/doc files

**Pattern extraction methodology:**
- Extracted imports, type hints, and async patterns from existing bridge.py for harness WebSocket client
- Extracted handler pattern (with future refinements for D-10/D-11/D-12) from bridge.py itself
- Extracted Settings pattern from settings.py for config validation pattern
- Extracted agent structure (tool schemas, per-player history, hand-rolled loop) from agent.py as baseline for Pydantic AI rewrite
- Extracted protocol shapes and tool structure from client.lua for D-07 rewrite guidance
- Extracted logging patterns from all Python modules

**Date:** 2026-09-22

---

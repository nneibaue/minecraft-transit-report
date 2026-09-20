# Architecture: turtle-helper v1.0 Local Round Trip

**Research Date:** 2026-09-19  
**Milestone:** v1.0 Local Round Trip (Windows 11 PC, dedicated ATM9 server, bridge.py local)  
**Confidence:** HIGH (all findings from direct code inspection of starter files)

## Executive Summary

The v1.0 round trip integrates four new capabilities into the single-file `bridge.py` and its paired Lua clients (`chat.lua`, `client.lua`):

1. **Fake device harness** — a separate Python file (`harness.py`) that speaks only the wire protocol, exercises the bridge without the game, and resets between test runs.
2. **Fake brain / no-API mode** — a minimal seam in `bridge.py` (a `Brain` interface or env-var switch) that replaces `anthropic.AsyncAnthropic()` with a deterministic stub, allowing protocol tests to run without `ANTHROPIC_API_KEY` or API spend.
3. **In-game data flow** — a precisely-documented path from chat input through three event loops to Chat Box output, with identified choke points (websocket message matching, outbox queue, 1.1s send cooldown).
4. **BRIDGE_TOKEN env configuration** — a `.env.example` + PowerShell/Bash recipe that keeps the token out of the repo but available to both the bridge and in-game Lua files via a per-device `secret.txt` in the server's computer folder on disk.

**Integration Philosophy:** Keep it minimal, one file until it hurts, preserve the existing loop code unchanged (so the fake brain can be swapped in/out with a one-line env var change).

---

## 1. Fake Device Harness

### 1.1 Design: Separate Module, Wire Protocol Only

**File:** `turtle/turtle-helper/harness/harness.py` (new)

**Principle:** The harness speaks only the JSON protocol. It does not import `bridge.py`, does not know about `DEVICE_TOOLS` or `LOCAL_TOOLS`, and does not reimplement the agent loop. It is a minimal websocket client that:
- Connects to the bridge
- Sends a `hello` message with a role (chat, turtle, or computer)
- Emits scripted or interactive events
- Receives and displays `cmd` messages
- Sends back canned or computed `result` messages
- Handles reconnect on bridge restart

### 1.2 Shape: `FakeDevice` Class + Scripted Scenarios

```python
class FakeDevice:
    def __init__(self, device_id: str, role: str, token: str, bridge_url: str):
        self.device_id = device_id
        self.role = role  # "chat", "turtle", "computer"
        self.token = token
        self.bridge_url = bridge_url
        self.ws = None
    
    async def connect(self):
        """Open websocket, send hello, enter message loop."""
        
    async def send_event(self, event_type: str, **kwargs):
        """Send an event (e.g., 'chat' with user, text, uuid, hidden)."""
        
    async def handle_cmd(self, cmd: dict) -> dict:
        """Receive cmd, respond with result (canned or computed)."""
        
    async def run_scenario(self, scenario: list[dict]):
        """Execute a pre-defined scenario: [{action: 'wait', 'send_event', 'close', ...}]."""
```

**Scenarios (YAML or JSON config, loaded into the harness):**
```yaml
scenario_list_devices_via_chat:
  - action: send_event
    event_type: chat
    user: Nate
    text: "$robot what devices are connected?"
    hidden: true
  - action: expect_say
    text_contains: ["turtle", "computer"]
  - action: close

scenario_chat_reconnect:
  - action: connect
    role: chat
  - action: wait
    seconds: 1
  - action: close
  - action: wait
    seconds: 2
  - action: reconnect
```

### 1.3 What It Exercises

| Capability | How Exercised |
|---|---|
| `hello` handshake | Sends on connect with correct role and caps |
| Chat events | Sends `event {name: "chat", user, text, hidden}` |
| `cmd` / `result` round trip | Receives cmd, replies with result (canned based on tool name) |
| Reconnect | Closes, waits, reconnects; bridge should re-register the device |
| Multiple devices | Multiple harness instances (or one harness with multiple roles in sequence) |
| Token validation | Attempts bad token, expects close(4001) |

### 1.4 Canned Results for Testing

The harness does not need to actually move turtles or read inventories. For each tool, provide a minimal pass-through result:

```python
canned_responses = {
    "list_devices": {"device-1": {"role": "chat", "caps": ["say"]}, ...},
    "say": {"ok": True},
    "status": {"id": "test-device", "is_turtle": True, "pos": None, "peripherals": [], "fuel": 100},
    "list_chest": {"name": "minecraft:chest_0", "size": 27, "items": []},
    "sort_chest": {"moved": 0, "no_rule": [], "destination_full": []},
    # ... one per tool
}
```

When a cmd arrives, look up the tool name in this dict and send the result. No logic, no side effects.

### 1.5 What It Does NOT Need

- Does not call Claude API or any model
- Does not parse the `DEVICE_TOOLS` schema or know what tools exist
- Does not implement the agent loop or tool dispatch
- Does not touch `chat.lua` or `client.lua` — it is a pure Python consumer of the wire protocol

**Confidence:** HIGH — the protocol is already defined in `bridge.py` lines 41–55 (send_cmd) and 179–208 (handler), and the message shapes are explicit JSON.

---

## 2. Fake Brain: No-API Mode in bridge.py

### 2.1 The Seam: Replace `anthropic.AsyncAnthropic()` with a Brain Interface

**Current state (line 34):**
```python
claude = anthropic.AsyncAnthropic()
```

**New state:**
```python
BRAIN_MODE = os.environ.get("BRAIN", "claude").lower()

# Define a minimal Brain interface that both real and fake modes implement
class Brain:
    async def create_message(self, model: str, max_tokens: int, system: str, tools: list, messages: list):
        """
        Returns an object with:
            .content = list of blocks (each has .type, and if type=="tool_use": .id, .name, .input)
            .stop_reason = "tool_use" or "end_turn"
        """
        raise NotImplementedError

class RealBrain(Brain):
    def __init__(self):
        self.client = anthropic.AsyncAnthropic()
    
    async def create_message(self, **kwargs):
        return await self.client.messages.create(**kwargs)

class FakeBrain(Brain):
    async def create_message(self, **kwargs):
        # See section 2.2
        pass

if BRAIN_MODE == "fake":
    brain = FakeBrain()
else:
    brain = RealBrain()
```

**Replacement point in `handle_request()` (line 161):**
```python
# Old:
resp = await claude.messages.create(
    model=MODEL, max_tokens=1024, system=SYSTEM,
    tools=DEVICE_TOOLS + LOCAL_TOOLS,
    messages=hist,
)

# New:
resp = await brain.create_message(
    model=MODEL, max_tokens=1024, system=SYSTEM,
    tools=DEVICE_TOOLS + LOCAL_TOOLS,
    messages=hist,
)
```

The rest of `handle_request()` (lines 166–175) does not change — it reads `resp.content`, checks `resp.stop_reason`, iterates `block.type`, accesses `block.id`, `block.name`, `block.input`.

### 2.2 FakeBrain Implementation

**Simple deterministic mode:**
```python
class FakeBrain(Brain):
    async def create_message(self, model: str, max_tokens: int, system: str, tools: list, messages: list):
        # Examine the last user message to decide what to do
        last_msg = next((m for m in reversed(messages) if m.get("role") == "user"), None)
        text = (isinstance(last_msg.get("content"), str) and last_msg["content"]) or ""
        
        # Rule 1: if "devices" in the text, call list_devices
        if "devices" in text.lower():
            return self._response_with_tool_use("list_devices", {})
        
        # Rule 2: if "say" would be appropriate (catch-all), just say something generic
        # (This is mainly for tests; in a real scenario the model does more work.)
        return self._response_terminal("Completed.")
    
    def _response_with_tool_use(self, tool_name: str, tool_input: dict):
        """Return a response that looks like Claude's tool_use block."""
        class Block:
            def __init__(self, type_, id_, name, input_):
                self.type = type_
                self.id = id_
                self.name = name
                self.input = input_
        
        class Resp:
            def __init__(self, blocks, stop_reason):
                self.content = blocks
                self.stop_reason = stop_reason
        
        return Resp(
            [Block("tool_use", "fake-1", tool_name, tool_input)],
            "tool_use"
        )
    
    def _response_terminal(self, text: str):
        """Return a response that ends the loop."""
        class Block:
            def __init__(self, type_, text):
                self.type = type_
                self.text = text
        
        class Resp:
            def __init__(self, blocks):
                self.content = blocks
                self.stop_reason = "end_turn"
        
        return Resp([Block("text", text)])
```

**Why this shape works:**
- `handle_request()` line 167 does `for block in resp.content` — works with a list.
- Line 170 checks `if block.type == "tool_use"` — works with a Block object that has `.type`.
- Lines 171–172 access `block.id`, `block.name`, `block.input` — all present on our Block.
- The loop continues if `resp.stop_reason == "tool_use"` — we control that.

### 2.3 Special Case: Answering `list_devices` Without a Model Round Trip

**Optional optimization:** Since `list_devices` is a LOCAL_TOOL (line 113–115 in bridge.py), and the harness scenario might call it, detect this in the bridge's `handle_request()` before calling the model:

```python
async def handle_request(user: str, text: str):
    # ... history setup ...
    
    # Fast path: if the request is just "what devices are connected", answer it locally
    if text.lower().strip() in ("what devices are connected?", "list devices"):
        # Synthesize a response that does list_devices and then says the result
        out = run_tool("list_devices", {})  # NOTE: run_tool is async; would need await
        device_list = ", ".join(out.keys()) or "none"
        await say(f"Connected: {device_list}")
        return
    
    # ... rest of handle_request (model call, tool loop) ...
```

This is optional. The fake brain can also handle "devices" by calling `list_devices` as a tool use block, and the loop will dispatch it normally.

**Confidence:** HIGH — the structure of `handle_request()` and `run_tool()` is explicit in the code (lines 138–147, 150–175).

---

## 3. In-Game Data Flow: Chat Input to Chat Box Output

### 3.1 Step-by-Step Data Path

**Starting point:** Player types `$robot what devices are connected?` in Minecraft chat.

**Step 1: Chat event originates in game**
- Advanced Peripherals Chat Box peripheral emits a `chat` event → CC:Tweaked's `os.pullEvent("chat")` in `chat.lua:53`.
- Event tuple: `{event_name="chat", username, message, uuid, isHidden}` (per CC:Tweaked docs for 1.20.1).

**Step 2: chat.lua forwards to bridge**
- `chat.lua:54–59` captures the event, serializes it to JSON: `{type="event", name="chat", user=ev[2], text=ev[3], uuid=ev[4], hidden=ev[5]}`.
- Sends via `ws.send()` on the persistent websocket connection.
- Process: Lua coroutine (single-threaded, blocked in `os.pullEvent()`).
- Thread: CC:Tweaked's main Lua VM (one per computer, synchronous with game tick, but the websocket I/O does not block the game client).

**Step 3: bridge.py receives event**
- WebSocket server's `handler()` coroutine (line 179) receives the JSON in the async loop.
- Line 195: `async for raw in ws:` — reads messages from `chat.lua`'s websocket.
- Line 196: parses JSON → `msg`.
- Lines 201–202: if `msg.type == "event"`, fires `asyncio.create_task(on_event(...))` — does NOT await it; the handler loop continues receiving messages immediately.
- **Threading:** Asyncio event loop (one per bridge.py process), non-blocking.

**Step 4: on_event() dispatches to handle_request()**
- `on_event()` coroutine (line 210) receives the unpacked message.
- Line 211–217: filters by event name ("chat"), extracts user and text, checks PREFIX and ALLOWED_PLAYERS whitelist.
- Line 220: calls `await handle_request(user, request)` — this is an await, so the coroutine yields control until handle_request completes.
- **Threading:** Asyncio event loop (same loop as handler).

**Step 5: Agent loop (handle_request())**
- `handle_request()` (line 150) builds conversation history, calls the model (or fake brain), dispatches tools in a loop (up to 12 rounds, line 160).
- When `resp.stop_reason == "tool_use"` (line 167), iterates over tool use blocks (line 170), calls `run_tool()` for each (line 172).
- Line 172: `out = await run_tool(...)` — for device tools, this calls `send_cmd()` (line 41), which sends a JSON cmd and awaits a result Future with a 120s timeout (line 51).
- **Choke points:**
  - If the device is not connected, `send_cmd()` returns an error immediately (line 45).
  - If the device does not reply within 120s, the request times out (line 52).
  - If `send_cmd()` is in flight when the device disconnects, the Future is abandoned (the `except asyncio.TimeoutError` and `finally` blocks handle cleanup, but the pending dict is not cleaned automatically if the device closes early — **BUG CANDIDATE**).

**Step 6: Device command and result**
- Bridge sends JSON cmd to the device (line 49): `{type: "cmd", cid, tool, args}`.
- `client.lua:196–209` (turtle) or `chat.lua:62–66` (chat) receives the cmd, dispatches to the tool, sends back a result.
- Bridge's `handler()` receives the result JSON (line 195), resolves the corresponding Future by `cid` (line 198–200).
- `send_cmd()` returns the result dict to the tool loop.

**Step 7: Tool result added to history**
- `handle_request()` line 174: appends `{type: "tool_result", tool_use_id: block.id, content: json.dumps(out)}` to history.
- Loop continues; next model call sees the tool results (line 163–164).

**Step 8: Model calls say() at the end**
- After tool loops end (stop_reason != "tool_use"), `handle_request()` does nothing more — the agent's `say()` call is executed *during* one of the earlier tool-use rounds or in the final text block.
- `say()` function (line 58) finds the chat device by role (line 59: `v["role"] == "chat"`), calls `send_cmd(base, "say", {...})`.
- Result: the bridge sends `{type: "cmd", cid, tool: "say", args: {text, to, prefix}}` to `chat.lua`.

**Step 9: chat.lua receives say command, queues it**
- `chat.lua:62–64` receives the cmd, inserts it into `outbox` table.
- Returns a result `{cid, ok: true}` to the bridge.
- **Threading:** Lua coroutine (blocked in `os.pullEvent()`, woken by `websocket_message` event).

**Step 10: drainOutbox() sends via Chat Box**
- `chat.lua:25–44` — `drainOutbox()` runs in parallel with the event loop via `parallel.waitForAny()` (line 91).
- Drains the outbox at 1.1s intervals (line 39: `sleep(SEND_GAP)`).
- Calls `chatBox.sendMessage()` or `sendMessageToPlayer()` (line 31–33).
- **Threading:** Lua coroutine, parallel to the event loop. If the Chat Box send fails, the message is requeued (line 36).

**End point:** Chat appears in-game chat, visible to all players (or whisper if `to` is specified).

### 3.2 Latency and Threading Summary

| Phase | Process | Thread/Coroutine | Blocking? | Timeout |
|-------|---------|------------------|-----------|---------|
| 1. Chat event | Minecraft + CC:Tweaked | Lua VM (single-threaded) | N/A (event-driven) | — |
| 2. Forward to bridge | chat.lua | Lua VM | Websocket I/O is non-blocking (HTTP/websocket handled by CC:Tweaked's HTTP client) | 30s (CC:Tweaked default) |
| 3. Bridge receive | bridge.py handler | asyncio (non-blocking) | N/A | — |
| 4. Agent loop | bridge.py on_event/handle_request | asyncio (non-blocking) | Awaits model; awaits device results | 120s per device cmd (CMD_TIMEOUT) |
| 5. Device cmd | client.lua or base chat.lua | Lua VM (single-threaded) | Websocket send is non-blocking | 30s (CC:Tweaked default) |
| 6. Chat Box send | chat.lua drainOutbox | Lua VM (parallel coroutine) | Chat Box API is blocking (~50ms per send); queue respects 1.1s cooldown | — |

**Choke points (where messages can be dropped):**

1. **Device not connected.** If the turtle/computer is not connected to the bridge, `send_cmd()` returns error immediately. The agent can detect this and respond gracefully.
2. **Device timeout (120s).** If the device takes longer than 120s to respond, the request times out. The agent can detect this and retry or give up.
3. **Chat event filtering.** If the event doesn't start with PREFIX or the user is not in ALLOWED_PLAYERS, the event is silently logged and ignored (line 216).
4. **Websocket reconnect.** If `chat.lua`'s websocket closes (device disconnects from bridge), the chat loop exits and reconnects (line 91 in chat.lua). Messages sent during reconnect are lost. Recovery: the game stays up, and the next request will succeed once the websocket is re-established.
5. **Bridge unavailable.** If the bridge crashes, `chat.lua` keeps retrying (5s backoff in client.lua line 226; would need to add same to chat.lua if not already there). **See chat.lua line 87–89 — connectLoop already does this.**

### 3.3 Startup Order and Reconnect Cases

**Case 1: Devices up before bridge (normal dev startup)**
```
chat.lua starts -> tries to connect to bridge -> fails -> 5s retry loop
client.lua starts -> tries to connect to bridge -> fails -> 5s retry loop
... (both backoff)
bridge.py starts -> listens on :8765
chat.lua -> connect succeeds -> sends hello -> enters event loop
client.lua -> connect succeeds -> sends hello -> enters event loop
(now a chat command will work)
```

**Confidence:** HIGH — `client.lua` line 216–226 and `chat.lua` line 76–89 both implement the retry loop explicitly.

**Case 2: Bridge restarts while devices are connected**

```
[Devices are connected and idle; chat.lua and client.lua are blocked in receive loops]

bridge.py crashes / restarts

[Devices' websockets are closed by the server (peer closed connection)]

chat.lua: line 70 triggers -> on_event("websocket_closed") -> session() returns -> connectLoop line 87 sleeps 5s -> reconnects
client.lua: line 203 triggers -> on_event("websocket_closed") -> session() returns -> line 226 sleeps 5s -> reconnects

[Meanwhile, bridge.py has restarted and is listening again]

chat.lua: reconnects -> sends hello -> devices dict is reset, so device is re-registered
client.lua: reconnects -> sends hello -> devices dict is reset, so device is re-registered

[BUT: any in-flight handle_request() that was running is LOST. The Future in pending dict is orphaned.]
```

**In-flight command during bridge restart:**
- User sends `$robot ...` while bridge is healthy.
- `handle_request()` is executing, waiting on `send_cmd()` (line 51: `await asyncio.wait_for(fut, CMD_TIMEOUT)`).
- Bridge crashes.
- The Future is never resolved; `await` raises `asyncio.TimeoutError` after 120s (or immediately if the event loop closes).
- `handle_request()` catches the timeout (line 52) and returns error.
- The original `on_event()` coroutine completes (line 220 await returns).
- Chat loop can continue (handler's `async for` loop does not notice the inner exception).

**Possible issue (not a blocker for v1.0):** If the bridge restart happens *between* a tool result being placed in the `pending` dict (line 48) and the device message arriving (line 198), the pending dict entry accumulates (line 55 `finally` cleans it up on timeout, but not on immediate restart). The `pending` dict is local to bridge.py, so it's reset on restart anyway. Not a leak.

**Confidence:** HIGH — The exception handling in `send_cmd()` (line 51–55) and `handle_request()` (line 220 wrapped in try/except at line 219) is explicit.

**Case 3: Device reboots mid-command**

```
Agent is calling send_cmd("turtle-1", "sort_chest", ...).
Bridge has sent the cmd, is awaiting the result (line 51).
Turtle reboots (or user runs `client` again).

Turtle's websocket closes (from the bridge's perspective).
Bridge's handler() for turtle-1 exits cleanly (line 203–207).
Turtle is removed from devices dict (line 206).

Meanwhile, send_cmd() is still awaiting the result.
After 120s (or if turtle never reconnects), the timeout fires.
send_cmd() returns error to the agent.
The agent can retry if appropriate.

If the turtle reconnects within 120s:
Turtle: websocket established, sends hello, new cid is issued, device re-registered (same ID "turtle-1", new ws object).
Bridge: send_cmd() is still awaiting the OLD cid on the OLD websocket.
The new result (on the new websocket) does not resolve the old Future.
Timeout occurs.

But: the device is now re-registered and ready for the next request.
```

**Implication:** A device reboot mid-command does NOT lose the device permanently; it just times out that command. The next command will succeed (once the device reconnects).

**Confidence:** HIGH — The device registry (line 37) uses device ID as the key, and the websocket is stored as a value, so reconnecting the same device ID with a new ws object replaces the old entry.

---

## 4. BRIDGE_TOKEN Configuration

### 4.1 Problem

**Current state (PROJECT.md line 62):** "No API key in Lua, in the repo, or in the world save; `secret.txt` on devices holds only the bridge token."

The token must:
- Be shared between the bridge (Python) and all Lua devices.
- NOT be committed to the GitHub repo.
- Be independently regenerated or stored on each machine (dev PC, server, each device folder).
- Be accessible at import time in `bridge.py` line 27: `TOKEN = os.environ["BRIDGE_TOKEN"]`.

### 4.2 Solution: .env.local + DevOps Recipe

**File: `.env.example` (committed to repo)**
```bash
# Bridge configuration for turtle-helper
# Copy to .env.local on your machine and fill in real values

# WebSocket server port (optional; default 8765)
PORT=8765

# Claude model to use (required; e.g. claude-sonnet-5, claude-haiku-4-5)
MODEL=claude-sonnet-5

# Shared secret between bridge and all in-game devices
# Generate once: openssl rand -hex 24
# or: python -c "import secrets; print(secrets.token_hex(24))"
# Store the same value in secret.txt on each in-game computer
BRIDGE_TOKEN=

# Comma-separated list of player names allowed to issue commands
# (API calls cost money; only trusted players)
ALLOWED_PLAYERS=

# Anthropic API key (required)
ANTHROPIC_API_KEY=

# Optional: chat command prefix (default: $robot)
COMMAND_PREFIX=$robot

# Optional: robot name shown in chat (default: Robot)
ROBOT_NAME=Robot
```

**File: `.env.local` (your machine, never committed)**
```bash
# (User creates this by copying .env.example and filling in values)
PORT=8765
MODEL=claude-sonnet-5
BRIDGE_TOKEN=3a7f2e91c4d8b5a6f9e2c1d3a4b5c6d7e8f9a0b1c2d3e4f
ALLOWED_PLAYERS=Nate
ANTHROPIC_API_KEY=sk-ant-...
```

**File: `.gitignore` (already exists, add if not present)**
```
.env
.env.local
.env.*.local
.env.*.example
```

### 4.3 Loading in bridge.py

**Current code (line 27):**
```python
TOKEN = os.environ["BRIDGE_TOKEN"]
```

**Updated code (to support both env var and .env.local):**
```python
from dotenv import load_dotenv  # pip install python-dotenv

load_dotenv(".env.local")  # Load from .env.local if it exists; .env vars take precedence
TOKEN = os.environ.get("BRIDGE_TOKEN") or os.environ["BRIDGE_TOKEN"]  # Fail if not set
```

**Better approach (no extra dependency):**
```python
import os

# Load from .env.local if it exists (simple parser, no dependency)
if os.path.exists(".env.local"):
    with open(".env.local") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                key, _, val = line.partition("=")
                if key and key not in os.environ:  # env vars take precedence
                    os.environ[key] = val.strip('\'"')

TOKEN = os.environ["BRIDGE_TOKEN"]  # Crash if not set
```

**Confidence:** HIGH — this is standard env-var practice; no special Fabric/CC:Tweaked knowledge needed.

### 4.4 Where `secret.txt` Lives on Each Device

**Topology:** Dedicated ATM9 server running on the same Windows PC as the bridge.

**Server's world folder structure:**
```
C:\Users\nneib\AppData\Local\Packages\...\Modded Minecraft\...\world\
  computercraft\          (if using CC:Tweaked's disk cache / persistent storage)
    computer\
      0\                  (Computer ID 0 — the chat box's Advanced Computer)
        secret.txt        <- contains the BRIDGE_TOKEN
        chat.lua
      1\                  (Computer ID 1 — the sorter turtle)
        secret.txt        <- contains the BRIDGE_TOKEN
        client.lua
      ...
  ...
```

**OR (more common in Fabric servers):**
```
C:\Users\nneib\...\server\
  world\
    ...
  (No persistent CC:Tweaked files on disk; Lua files are loaded via wget/edit in-game)
```

**Best practice for local dev:**

1. Find the server's world folder (documented in the server launcher or config).
2. Create the folder structure `computercraft/computer/{id}/` if it doesn't exist.
3. Place `secret.txt` directly in that folder.
4. When the in-game computer boots (or `startup.lua` runs), it reads `secret.txt` from the working directory (which CC:Tweaked defaults to the computer's folder on disk).

**Example setup script (PowerShell):**
```powershell
# Variables (customize for your server path)
$SERVER_ROOT = "C:\path\to\minecraft\server"
$BRIDGE_TOKEN = "3a7f2e91c4d8b5a6f9e2c1d3a4b5c6d7e8f9a0b1c2d3e4f"
$WORLD = "world"  # or "world_the_nether", etc.

# Ensure computercraft folder exists
$CC_PATH = "$SERVER_ROOT\$WORLD\computercraft\computer"
mkdir -Force $CC_PATH

# Create secret.txt on each computer
foreach ($COMP_ID in @(0, 1, 2, 3)) {
    $COMP_FOLDER = "$CC_PATH\$COMP_ID"
    mkdir -Force $COMP_FOLDER
    $BRIDGE_TOKEN | Out-File -FilePath "$COMP_FOLDER\secret.txt" -Encoding UTF8 -NoNewline
    Write-Host "Created $COMP_FOLDER\secret.txt"
}
```

**Bash equivalent (for local dev on WSL or Git Bash on Windows):**
```bash
SERVER_ROOT="/mnt/c/path/to/minecraft/server"
BRIDGE_TOKEN="3a7f2e91c4d8b5a6f9e2c1d3a4b5c6d7e8f9a0b1c2d3e4f"
WORLD="world"

CC_PATH="$SERVER_ROOT/$WORLD/computercraft/computer"
mkdir -p "$CC_PATH"

for COMP_ID in 0 1 2 3; do
    echo -n "$BRIDGE_TOKEN" > "$CC_PATH/$COMP_ID/secret.txt"
    echo "Created $CC_PATH/$COMP_ID/secret.txt"
done
```

**Confidence:** HIGH — This is the documented way CC:Tweaked loads persistent files (line 19 in client.lua and line 19 in chat.lua both read from "secret.txt" in the working directory).

---

## 5. Suggested Build Order (Independently Verifiable Steps)

The milestone scope is: bridge boots, harness proves protocol, fake brain proves agent loop, real in-game round trip, reconnect. The order respects dependencies (bridge must run before testing it; harness can test bridge protocol without a model; model can be swapped out without changing the loop code).

### Phase 5.1: Environment Setup (Prerequisite)

**Deliverable:** Bridge can start without crashing; env vars are documented and optional values have defaults.

**Steps:**
1. Create `bridge/.env.example` with all env vars documented (see section 4.2).
2. Update `bridge.py` line 27 to load `.env.local` if it exists (section 4.3).
3. Set `MODEL` default from placeholder `"claude-sonnet-4-5"` (line 28) to a real current model (e.g., `"claude-sonnet-5"`).
4. Update `bridge.py` line 34 to handle missing `BRIDGE_TOKEN` gracefully (currently crashes; should log a clear error message).
5. Test: `python bridge.py` with no env vars should print "BRIDGE_TOKEN not set" and exit cleanly. With `BRIDGE_TOKEN=test`, it should start and listen.

**Files modified:**
- `bridge/bridge.py` (lines 27–34, exception handling)

**Files created:**
- `bridge/.env.example`
- `bridge/.gitignore` (if not present)

**Verification:** Bridge starts, listens on port 8765, does not crash on startup.

---

### Phase 5.2: Fake Brain Seam (Model Replacement)

**Deliverable:** `bridge.py` can run with a fake model that deterministically answers "devices" by calling `list_devices` without spending API money.

**Steps:**
1. Define `Brain` interface in `bridge.py` (abstract base or duck-typed protocol).
2. Create `RealBrain` wrapper around `anthropic.AsyncAnthropic()`.
3. Create `FakeBrain` that implements the same interface; hardcodes responses for `list_devices` (section 2.2).
4. Add `BRAIN_MODE` env var (default "claude"); instantiate `brain` based on it.
5. Replace line 161's `await claude.messages.create(...)` with `await brain.create_message(...)`.
6. Verify the rest of `handle_request()` (lines 166–175) does not change — it should work with both brains.

**Files modified:**
- `bridge/bridge.py` (lines 27–35 for brain selection, lines 161 for model call)

**No new files** (seam is internal to bridge.py).

**Verification:** 
- `BRAIN=claude python bridge.py` starts (requires valid `ANTHROPIC_API_KEY`).
- `BRAIN=fake python bridge.py` starts without an API key.
- Fake brain responds deterministically (can log and assert expected outputs).

---

### Phase 5.3: Fake Device Harness (Protocol Testing)

**Deliverable:** A terminal-driven harness that connects to bridge, sends scripted events, and verifies responses. Protocol tests run without the game or any model.

**Steps:**
1. Create `harness/harness.py` with `FakeDevice` class (section 1.2).
2. Implement scenarios (YAML or JSON config file) for key paths:
   - Hello handshake and token validation.
   - Chat event from a "chat" device.
   - Device command and result round-trip.
   - Reconnect after bridge restart.
3. Create a simple test runner (`harness/test_scenarios.py` or `harness/run.py`) that:
   - Starts the bridge in a subprocess (or assumes it's running).
   - Instantiates `FakeDevice` for a scenario.
   - Runs the scenario (await calls to connect, send_event, handle_cmd, close).
   - Logs results.
4. Document how to run: `python -m pytest harness/test_scenarios.py -v` or `python harness/run.py scenario_name`.

**Files created:**
- `harness/harness.py` (FakeDevice class)
- `harness/scenarios.yaml` (or .json) (scripted scenarios)
- `harness/test_scenarios.py` (pytest tests) or `harness/run.py` (CLI runner)

**No modifications** to bridge.py (the harness only uses the wire protocol).

**Verification:**
- `BRAIN=fake python bridge.py` in one terminal.
- `python -m pytest harness/` in another (or `python harness/run.py`) — all scenarios pass.
- The harness logs show hello, event, cmd, result exchanges clearly.

---

### Phase 5.4: Lua Setup on Local Server (File Placement)

**Deliverable:** The `secret.txt` token and Lua files (`chat.lua`, `client.lua`) are on the dedicated server, ready to run.

**Steps:**
1. Generate a token: `python -c "import secrets; print(secrets.token_hex(24))"` → save to `.env.local` as `BRIDGE_TOKEN`.
2. Create the token in `.env.local` (phase 5.1).
3. Run the setup script from section 4.4 (PowerShell or Bash) to place `secret.txt` in each computer folder on the server.
4. Manually (or via a one-line script) place `chat.lua` and `client.lua` into the server's `computercraft/computer/{0,1,...}/` folders.
   - Alternatively, document how to `wget` them from this repo branch on GitHub (fast dev loop).
5. Document the server's world path and computer IDs in `turtle/turtle-helper/README.md` or a `.local-setup.md` file.

**Files modified:**
- `.planning/workstreams/turtle-helper/README.md` or new `.planning/workstreams/turtle-helper/.local-setup.md` (document server folder paths)

**Files created (in server, not in repo):**
- `{server}/world/computercraft/computer/0/secret.txt`, `chat.lua` (Chat Box computer)
- `{server}/world/computercraft/computer/1/secret.txt`, `client.lua` (Sorter turtle/computer)

**Verification:**
- `secret.txt` exists on at least one computer in the server (check on disk or in game via `edit secret.txt`).
- `BRIDGE_URL` in both Lua files points to `ws://127.0.0.1:8765`.
- CC:Tweaked's `computercraft-server.toml` allows `127.0.0.1` (see section 4.1 in README.md).

---

### Phase 5.5: Real In-Game Round Trip

**Deliverable:** A player types `$robot what devices are connected?` and hears a spoken answer listing actual in-game devices.

**Steps:**
1. Start the dedicated ATM9 server.
2. Ensure `chat.lua` and `client.lua` are running (add to `startup.lua` or start manually).
3. Start `python bridge.py` with `BRAIN=claude` (requires `ANTHROPIC_API_KEY` and valid `MODEL`).
4. Log into the game as the `ALLOWED_PLAYERS` user.
5. Type `$robot what devices are connected?` in chat.
6. Verify:
   - The bridge logs show the chat event received and processed.
   - The agent calls `list_devices`, gets the device registry, and calls `say()`.
   - The Chat Box speaks the device list in game.
7. Test a few variations:
   - `$robot status` (calls `status` tool on default device).
   - `$robot [non-whitelisted-player] what devices are connected?` (chat event ignored, bridge logs note).

**Files modified:** None (uses existing bridge.py and Lua).

**Verification:**
- Chat box outputs a spoken message listing devices.
- Bridge logs show the request, tool calls, and result.
- In game, the Chat Box peripheral displays the message.

---

### Phase 5.6: Reconnect Test

**Deliverable:** Bridge restarts while devices are connected; devices reconnect; next request works.

**Steps:**
1. Devices are connected and idle (previous step's state).
2. Stop the bridge (Ctrl+C on `python bridge.py`).
3. Wait 10 seconds (or until devices log "disconnected, retrying in 5s").
4. Restart the bridge: `python bridge.py`.
5. Devices should reconnect within 10 seconds (5s backoff + connection time).
6. Type a new command: `$robot what devices are connected?`.
7. Verify the request succeeds (Chat Box speaks the answer).

**Files modified:** None.

**Verification:**
- Bridge start logs show no device initially.
- Within 10s, both devices reconnect (logs show "device connected").
- Chat command works as in phase 5.5.
- Bridge logs show no errors or hanging Futures.

---

### Phase 5.7: Token Rotation + Security Test (Optional, v1.0+ milestone)

**Deliverable:** Confirm that changing the token invalidates old connections.

**Steps:**
1. Note the current token in `.env.local`.
2. Change it to a different value.
3. Restart the bridge.
4. An in-game device tries to reconnect; it still has the old token in `secret.txt`.
5. Verify the bridge rejects it (logs show "bad token", closes with code 4001).
6. Update `secret.txt` on the device with the new token.
7. Device reconnects; connection succeeds.

**Files modified:** None (test only).

**Verification:**
- Mismatched token → connection rejected.
- Matching token → connection accepted.

---

## 6. Build Order Summary Table

| Phase | Deliverable | Files Modified | Files Created | Verifiable |
|-------|-------------|-----------------|---------------|-----------|
| 5.1 | Bridge starts, env vars documented | `bridge/bridge.py` | `bridge/.env.example`, `.gitignore` | Bridge boots without env vars |
| 5.2 | Fake brain seam, no API spend | `bridge/bridge.py` | None | `BRAIN=fake` mode works |
| 5.3 | Harness proves protocol | None | `harness/harness.py`, scenarios, tests | Harness tests pass |
| 5.4 | Lua on server, secret.txt placed | README or new `.local-setup.md` | None (server files) | `secret.txt` exists in game |
| 5.5 | Real in-game round trip | None | None | Chat command heard in game |
| 5.6 | Bridge restart, devices reconnect | None | None | Chat command works after restart |
| 5.7 | Token rotation (optional) | None | None | Wrong token rejected |

---

## 7. New vs Modified Files: Explicit List

### Modified Files (Existing Code)

| File | Changes | Lines Affected |
|---|---|---|
| `bridge/bridge.py` | Load `.env.local`; add Brain interface; instantiate brain based on BRAIN_MODE; replace model call | 27–35 (env loading), 138–148 (brain class), 161 (model call) |
| `.planning/workstreams/turtle-helper/README.md` or new `.local-setup.md` | Add section "Local Setup on Windows" with server folder structure, token generation, secret.txt placement | New section |

### New Files

| File | Purpose | Phase |
|---|---|---|
| `bridge/.env.example` | Documented env vars template | 5.1 |
| `harness/harness.py` | FakeDevice class, protocol testing | 5.3 |
| `harness/scenarios.yaml` (or `.json`) | Scripted test scenarios | 5.3 |
| `harness/test_scenarios.py` (or `run.py`) | Test runner using pytest or CLI | 5.3 |

### Server-Local Files (Not Committed)

| File | Purpose | Phase |
|---|---|---|
| `.env.local` | Local env vars (git-ignored) | 5.1 |
| `{server}/world/computercraft/computer/{0,1}/secret.txt` | Shared token | 5.4 |
| `{server}/world/computercraft/computer/{0,1}/{chat,client}.lua` | Lua code on server (dev: may also be in repo + wget, or manually edited in game) | 5.4 |

---

## 8. Integration Checklist

### For Code Review

- [ ] `bridge.py` exports a `Brain` interface that both `RealBrain` and `FakeBrain` implement.
- [ ] `FakeBrain.create_message()` returns an object with `.content` (list of blocks) and `.stop_reason` ("tool_use" or other).
- [ ] Each block in `.content` has `.type` ("tool_use", "text"), and tool_use blocks have `.id`, `.name`, `.input`.
- [ ] `handle_request()` line 161 uses `await brain.create_message(...)` instead of `await claude.messages.create(...)`.
- [ ] The rest of `handle_request()` (lines 166–175) is unchanged (loop reads `resp.content`, `resp.stop_reason`, `block.type`, `block.id`, etc.).
- [ ] `BRAIN_MODE` env var controls which brain is instantiated.
- [ ] Bridge loads from `.env.local` and respects `BRIDGE_TOKEN`, `ANTHROPIC_API_KEY`, `MODEL` env vars.
- [ ] Error message is clear if `BRIDGE_TOKEN` is missing.

### For Harness Review

- [ ] `FakeDevice` speaks only JSON (no Python bridge imports).
- [ ] Scenarios are data-driven (YAML/JSON config, not hardcoded in code).
- [ ] Scenarios cover: hello, chat event, cmd/result, reconnect, bad token.
- [ ] Harness logs clearly show protocol exchanges (hello, event, cmd, result, close).

### For Lua Review

- [ ] Both `chat.lua` and `client.lua` read `BRIDGE_TOKEN` from `secret.txt`.
- [ ] Both implement reconnect loops (5s backoff).
- [ ] `chat.lua` has dual event loops: one for chat input, one for Chat Box send queue.
- [ ] `client.lua` dispatches tools via `pcall` and sends results back.

### For Local Setup Review

- [ ] `.env.example` documents all required and optional env vars.
- [ ] Setup instructions explain where `secret.txt` goes on the server.
- [ ] Server's `computercraft-server.toml` allows `127.0.0.1` (or documentation points to this rule).

---

## 9. Confidence Assessment

| Area | Confidence | Notes |
|---|---|---|
| Fake device harness design | **HIGH** | Wire protocol is explicit in bridge.py; no reimplementation of agent loop needed. |
| Fake brain seam | **HIGH** | Existing `handle_request()` structure is explicit; seam is minimal and preserves existing loop code. |
| Data flow for in-game round trip | **HIGH** | All functions (handler, on_event, handle_request, send_cmd, run_tool) are explicit in bridge.py; event signatures are defined in CC:Tweaked API docs for 1.20.1. |
| Device reconnect behavior | **HIGH** | Reconnect loops are explicit in both Lua files; device registry dict uses ID as key. |
| BRIDGE_TOKEN env configuration | **HIGH** | Standard env-var practice; CC:Tweaked file I/O is explicit. |
| Server topology and file placement | **MEDIUM–HIGH** | Assumes standard ATM9 server structure; local folder paths depend on Windows version and Minecraft launcher. Recommend testing on actual machine. |
| CC:Tweaked 1.20.1 event signatures | **MEDIUM** | Event tuple shapes inferred from `chat.lua` line 53 and README.md §3. Should verify against actual CC:Tweaked docs for Minecraft 1.20.1 when Lua first runs. |

---

## 10. Gaps and Assumptions

### Known Unknowns (To Be Verified During Implementation)

1. **CC:Tweaked websocket event tuple order.** Line 53–59 in `chat.lua` assumes the `chat` event is `{event_name, user, text, uuid, hidden}`. Should verify against actual CC:Tweaked 1.20.1 release notes or in-game test.
2. **Chat Box send() return value.** Line 31 in `chat.lua` assumes `sendMessage()` returns `(ok, err)` tuple. Should verify against Advanced Peripherals 1.20.1 docs.
3. **URL matching in websocket_message events.** Line 60 in `chat.lua` does `ev[2] == BRIDGE_URL`. Whether CC:Tweaked hand back the exact string passed to `http.websocket()` (not a parsed URL) should be tested.
4. **Server world folder location.** Phase 5.4 assumes a standard ATM9 server structure. Actual path depends on the launcher used. Document for the author's specific setup.
5. **Token length.** Using `secrets.token_hex(24)` = 48 hex chars. Should verify this fits in `secret.txt` and is not truncated by CC:Tweaked's file I/O.

### Out of Scope (v1.0)

- Multi-device dispatch (currently uses `default_worker()`, line 66–70, which just picks the first available device).
- Scheduled chores or timed tasks (bridge architecture supports it; not implemented this milestone).
- Device state persistence (rules.json persists to device, not bridge; bridge has no `database`).
- Production hosting (local only, no tunnel).
- Any LLM call from Lua (`ALLOW_EVAL` stays off).

---

## 11. References

**Starter Code (HIGH confidence — direct inspection):**
- `bridge/bridge.py` lines 27–55 (send_cmd), 138–148 (run_tool), 150–175 (handle_request), 179–226 (handler, on_event)
- `turtle/client.lua` lines 188–214 (session, tool dispatch), 216–227 (reconnect loop)
- `base/chat.lua` lines 46–74 (session, event handling), 76–92 (connectLoop, drainOutbox)

**CC:Tweaked 1.20.1 API (MEDIUM–HIGH confidence — standard library, verified via README.md):**
- `http.websocket(url)` → websocket object with `.send(json_string)` and `.receive()`.
- `os.pullEvent(name)` → event tuple (name, arg1, arg2, ...).
- `peripheral.find(type)` and `peripheral.wrap(name)` → peripheral objects.
- `textutils.serialiseJSON(table)` and `unserialiseJSON(json_string)`.

**Advanced Peripherals 1.20.1 (MEDIUM confidence — not verified; inferred from code):**
- Chat Box peripheral has `.sendMessage(text, prefix)` and `.sendMessageToPlayer(text, player, prefix)`.
- Chat event has signature `{event="chat", username, message, uuid, isHidden}`.

---

**Research Complete: 2026-09-19**


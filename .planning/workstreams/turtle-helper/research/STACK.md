# Technology Stack — turtle-helper v1.0 Local Round Trip

**Milestone:** v1.0 Local Round Trip (round-trip test on Windows PC with local ATM9 server)  
**Researched:** 2026-09-19  
**Overall confidence:** HIGH (all package versions verified on current PyPI/docs; all API claims sourced from official docs)

## Executive Summary

The turtle-helper stack is minimal and deliberate: Python 3.12.10 with `websockets`, `anthropic`, and `pytest` for testing; CC:Tweaked 1.111.0 and Advanced Peripherals 0.7.40r as shipped in All the Mods 9 1.20.1; the `java.net.http` equivalent in the Minecraft protocol stack. The Python bridge runs in a local venv, connects in-game devices via websockets, and dispatches tool calls to Claude Sonnet 5 (or Haiku 4.5 if cost-critical). No framework, no database, one file until it hurts — by design. Key action item: `bridge.py` must migrate from the deprecated legacy `websockets.serve()` API (will be removed by 2030) to the current `websockets.asyncio.server.serve()`, and the model ID placeholder must be replaced.

## Recommended Stack

### Core Python Runtime & Libraries

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Python (runtime) | 3.12.10 (Windows Store launcher) | Python interpreter | Fixed by project constraint; already installed on your PC. |
| websockets | 17.1 (Aug 2026) | Async WebSocket server | Built-in to stdlib is Java; Python needs third-party. 17.1 is current; legacy impl deprecated in 14.0, will be removed by 2030. |
| anthropic | 1.7.0 (Sept 18, 2026) | Claude API client | Official SDK; latest; `AsyncAnthropic`, `messages.create`, `tool_use` flow all current and stable. |
| pytest | 9.1.1 (June 2026) | Unit test framework | Standard testing harness; protocol tests and utility unit tests run here. |
| pytest-asyncio | 1.4.0 (May 2026) | Async test support | Enables `@pytest.mark.asyncio` decorator for async test functions. Requires pytest ≥ 8.4.0. |

### Minecraft 1.20.1 Forge Server (All the Mods 9 0.2.61)

| Mod | Version | Purpose | Why Shipped This Way |
|-----|---------|---------|----------------------|
| CC:Tweaked | 1.111.0-1.20.1 | Lua scripting in-game | ATM9 0.2.61 includes this version; all Lua APIs verified against it. |
| Advanced Peripherals | 0.7.40r-1.20.1 | Chat Box and extended peripherals | ATM9 0.2.61 includes this version; Chat Box API verified against 0.7.x docs. |
| Forge Loader | (ATM9 default) | Mod loading | Hosts the Minecraft server; config in `world/serverconfig/computercraft-server.toml`. |

### CC:Tweaked HTTP/WebSocket Configuration (1.20.1)

| Setting | Default | Relevant to This Project |
|---------|---------|--------------------------|
| `http.enabled` | `true` | Must be enabled for any HTTP or WebSocket. |
| `websocket_enabled` | `true` (if http_enabled) | Required for `http.websocket()` calls. |
| `http.max_websocket_message` | 131072 bytes (128 KB) | Hard limit on message size; protocol uses JSON, typical ~1 KB messages. |
| `max_websockets` | 4 per computer | Two devices (chat + worker) = 2 open sockets; well within limit. |
| `http.timeout` | 30000 ms (30 s) | HTTP request timeout; websocket connection timeout sourced here. |

**Local address rule** (required for `ws://127.0.0.1:8765`):
```toml
# In world/serverconfig/computercraft-server.toml
[[http.rules]]
host = "127.0.0.1"
action = "allow"
```

Rule order matters — this rule must appear *before* the default private-address deny rule (if present). Add it at the top of the `[[http.rules]]` array to ensure it's checked first.

## Claude Model IDs (2026-09)

| Model | ID | Cost (1M tokens) | Best For |
|-------|----|--------------------|----------|
| Sonnet 5 | `claude-sonnet-5` | $3 in / $15 out | **Recommended default** — fast, capable, good cost-per-token for agentic loops with tool use. |
| Haiku 4.5 | `claude-haiku-4-5-20251001` | $0.80 in / $4 out | Cost-sensitive agents; sufficient for device coordination. Use if API spend is a concern. Alias: `claude-haiku-4-5`. |
| Opus 5 | `claude-opus-5` | $15 in / $75 out | High-complexity reasoning; overkill for turtle chore dispatch. |
| Fable 5.1 | `claude-fable-5-1` | $0.20 in / $1 out | Fastest; limited reasoning; may underperform on multi-step chores. |

**Starter fix:** Replace placeholder `claude-sonnet-4-5` with `claude-sonnet-5`. Set via `MODEL` env var at bridge startup.

## Lua APIs (CC:Tweaked 1.111.0 + Advanced Peripherals 0.7.40r)

### WebSocket Connection and Protocol

**Creating a WebSocket connection:**
```lua
local ws, err = http.websocket(url [, headers])
-- returns: ws (handle) or false, err (string)
```

**Sending and receiving:**
```lua
ws.send(message [, binary])  -- throws if ws closed or message too large
local msg, isBinary = ws.receive([timeout])  -- blocks; returns msg (string) and isBinary (bool), or nil, reason on timeout
ws.close()  -- terminates; no further send/recv
```

**Event-driven alternative** (used in starter's `chat.lua` and `client.lua`):
```lua
local event, url, msg, isBinary = os.pullEvent("websocket_message")
-- event is "websocket_message", url is the connection's URL string,
-- msg is the received message, isBinary indicates binary flag
```

**Connection lifecycle events:**
```lua
local event, url, reason, code = os.pullEvent("websocket_closed")
-- event is "websocket_closed", url is connection URL,
-- reason is server-provided close reason (string, nil if abnormal),
-- code is close code from RFC 6455 (number, nil if abnormal)
```

**Async connection (rarely used; included for completeness):**
```lua
http.websocketAsync(url [, headers])
-- fires websocket_success or websocket_failure event when done
local event, url, handle = os.pullEvent("websocket_success")
local event, url, error = os.pullEvent("websocket_failure")
```

### JSON Serialization and Empty Collections

**Serializing tables to JSON:**
```lua
local json_string = textutils.serialiseJSON(table)
-- Encodes Lua tables as JSON; distinguishes empty arrays from empty objects
```

**Deserializing JSON to tables:**
```lua
local lua_table = textutils.unserialiseJSON(json_string)
-- JSON null becomes nil by default (use options to get json_null instead)
-- Empty JSON arrays become empty_json_array constant (not a plain empty table)
```

**Empty array sentinel:**
```lua
textutils.empty_json_array  -- table constant; use when you need to serialize an empty array
if items == textutils.empty_json_array then print("no items") end
-- Without this, an empty table serializes as {} (JSON object), not [] (JSON array)
```

**JSON null sentinel:**
```lua
textutils.json_null  -- table constant; use to serialize explicit JSON null
local json_with_null = textutils.serialiseJSON({value = textutils.json_null})
-- Produces: {"value":null}
```

**Key gotcha:** The starter's Lua uses `textutils.empty_json_array` correctly (lines 82, 100, 107 in `client.lua`), but verify on first run that empty `items` tables serialize as `[]` not `{}`.

### Advanced Peripherals Chat Box (0.7.40r)

**Finding and wrapping the Chat Box:**
```lua
local chatBox = peripheral.find("chatBox")
if not chatBox then error("no Chat Box attached") end
```

**Sending broadcast message:**
```lua
local ok, err = chatBox.sendMessage(message [, prefix, brackets, bracketColor, range, utf8Support])
-- message: string to broadcast
-- prefix: shown as [prefix] in chat (default from mod config, e.g. "Robot")
-- All other params optional; see Advanced Peripherals docs for details
-- Returns: true on success, or nil, error_string on failure
```

**Sending message to specific player:**
```lua
local ok, err = chatBox.sendMessageToPlayer(message, username [, prefix, brackets, bracketColor, range, utf8Support])
-- username: exact player name (case-sensitive)
-- Returns: true on success, or nil, error_string on failure
```

**Listening for chat events:**
```lua
local event, uuid, username, message, isHidden, encodedUtf8Message = os.pullEvent("chat")
-- event: string "chat"
-- uuid: player UUID (string, nil if from /say command)
-- username: player name (string, "[say]" if from /say command)
-- message: the chat text (string)
-- isHidden: true if message sent privately to Chat Boxes (not visible in public chat)
-- encodedUtf8Message: UTF-8 encoded version of message (string)
```

**Send cooldown and queuing:** Chat Box has a ~1 second internal cooldown between sends. The starter's `chat.lua` (line 9: `SEND_GAP = 1.1`) respects this with a queue and fixed delay. Do not attempt sends faster than 1 per second or the mod silently drops excess messages.

**Hidden message behavior:** Messages prefixed with `$` (e.g., `$robot ...`) are sent with `isHidden = true` by Advanced Peripherals, making them visible only to Chat Boxes, not in public chat. This is why the `COMMAND_PREFIX = "$robot"` pattern works.

## Python Implementation: websockets API Migration

### Current Status

The starter's `bridge.py` (lines 230, 179) uses the legacy `websockets.serve()` API:
```python
# DEPRECATED (will be removed by 2030)
async with websockets.serve(handler, "0.0.0.0", PORT, ping_interval=20, ping_timeout=20):
    await asyncio.Future()

async def handler(ws):
    # Old API: ws is WebSocketServerProtocol; path param optional
    raw = await asyncio.wait_for(ws.recv(), 10)
    ...
```

### Migration to Current API

**New import and serve() signature:**
```python
from websockets.asyncio.server import serve

async def handler(websocket):
    # New API: websocket is ServerConnection; no path parameter
    # send/recv/close methods identical to old API
    try:
        raw = await asyncio.wait_for(websocket.recv(), 10)
        msg = json.loads(raw)
    except Exception:
        await websocket.close(4000, "expected hello")
        return
    ...
```

**Key changes:**
1. Import: `from websockets import serve` → `from websockets.asyncio.server import serve`
2. Handler signature: `async def handler(ws, path)` → `async def handler(websocket)` (path is gone)
3. Connection object: `WebSocketServerProtocol` → `ServerConnection` (mostly transparent; same send/recv/close)
4. Request metadata (if needed later): `ws.path` → `websocket.request.path`, `ws.request_headers` → `websocket.request.headers`

**The serve() context manager is identical:**
```python
async with serve(handler, "0.0.0.0", PORT, ping_interval=20, ping_timeout=20):
    await asyncio.Future()
```

**Reason:** websockets 17.0+ deprecated the legacy implementation (14.0+) and made the new `websockets.asyncio.server` the default. Code written against the new API works today and will continue working; code against the legacy API has a removal timeline (2030).

## Test Stack

### Unit Tests (No Anthropic API Spend)

**Protocol and device harness:**
```bash
pytest tests/test_protocol.py -v
```
Tests the JSON message protocol, device hello handshake, tool dispatch, and result handling without invoking Claude. Use a mock/stub `AsyncAnthropic` so protocol tests run for free.

**Config parsing:**
```bash
pytest tests/test_config.py -v
```
If/when bridge config is externalized (currently env vars only), test load/parse/default logic here.

**Scheduler timing** (if added):
```bash
pytest tests/test_scheduler.py -v
```
If a device reconnect scheduler is added, test backoff and retry logic with a mock clock.

### Integration Tests (Optional Anthropic API Spend)

**End-to-end bridge loop** (not required for v1.0):
```bash
pytest tests/test_bridge_e2e.py -v --anthropic-live
```
Only run with `--anthropic-live` flag if you want to spend API calls on full-stack tests. v1.0 milestone satisfies via manual testing (fake device + real game clients).

### Test Configuration

**pytest.ini or pyproject.toml:**
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
```

**asyncio_mode = "auto"** allows `async def test_*()` functions to work without `@pytest.mark.asyncio` decorator (optional convenience). Use `"strict"` (default) to require explicit decorator.

## Development Environment Setup

### Windows PowerShell

```powershell
# Create and activate venv
python -m venv .venv
.\.venv\Scripts\Activate.ps1

# If execution policy blocks this:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Install pinned dependencies
pip install -r requirements.txt

# Verify
python --version
pip show websockets anthropic
```

### Windows Git Bash (MSYS2/MinGW)

```bash
# Create and activate venv
python -m venv .venv
source .venv/Scripts/activate

# Install pinned dependencies
pip install -r requirements.txt

# Verify
python --version
pip show websockets anthropic
```

### requirements.txt (Pinned Versions)

```
websockets==17.1
anthropic==1.7.0
pytest==9.1.1
pytest-asyncio==1.4.0
```

**Why pin?** Reproducibility across machines and time. When v1.0 is tested and working, these versions worked. Don't float them unless you have a reason (bug fix, new feature needed).

**Upgrading safely:** Run `pip list --outdated` to see what's available. Test new versions in a separate venv before committing to production.

## Integration Points with Existing Starter

### bridge.py Changes Required

1. **Import change** (line 21):
   ```python
   # OLD:
   # import websockets
   
   # NEW:
   from websockets.asyncio.server import serve
   ```

2. **Handler signature** (line 179):
   ```python
   # OLD:
   # async def handler(ws):
   
   # NEW:
   async def handler(websocket):
       # Rename internal `ws` variable to `websocket` throughout function
       # OR keep using `ws` internally by aliasing: ws = websocket
   ```

3. **Model ID** (line 28):
   ```python
   # OLD:
   MODEL = os.environ.get("MODEL", "claude-sonnet-4-5")
   
   # NEW:
   MODEL = os.environ.get("MODEL", "claude-sonnet-5")
   ```

4. **serve() call** (line 230):
   ```python
   # No change needed; the call signature is the same
   async with serve(handler, "0.0.0.0", PORT, ping_interval=20, ping_timeout=20):
   ```

### Lua Files (No Changes Required for v1.0)

- **chat.lua** and **client.lua** use only stable APIs (`http.websocket`, `textutils`, `os.pullEvent`). No breaking changes in 1.111.0 relative to their usage. Verify on first run that events fire as expected.

### Environment Variables (No Changes)

- `ANTHROPIC_API_KEY` — unchanged
- `BRIDGE_TOKEN` — unchanged
- `ALLOWED_PLAYERS` — unchanged
- `ALLOW_EVAL` — unchanged (stays `false` for v1.0)
- `MODEL` — value must change from placeholder to current model ID

## What NOT to Add (And Why)

| Category | Temptation | Decision | Reason |
|----------|-----------|----------|--------|
| **Config storage** | Cloth Config / owo-lib | Use hand-rolled env vars | No in-game GUI this milestone; two settings (BRIDGE_TOKEN, MODEL) fit in environment. Adding a library for it is premature. |
| **Database** | SQLAlchemy / Tortoise ORM | Persist rules.json on device, config as env var | Small project; sorting rules live on the turtle (or worker computer) and are persisted via `rules.json` locally. No server-side persistence needed. |
| **Web framework** | Flask / FastAPI | Bare asyncio + websockets | Bridge is a websocket server + Claude loop. No HTTP routes, no REST API, no static files. A framework would be overhead with zero benefit. |
| **Logging** | structlog / loguru | Use Python's `logging` module | Built-in logging is sufficient; bridge.py already uses it (line 23). One file means simple logging strategy. |
| **CLI / argument parsing** | Click / argparse | Environment variables only | Config is small (3 env vars). argparse adds ceremony for zero gain; env vars are how Minecraft mods pass config to their scripts. |
| **Schema validation** | Pydantic / marshmallow | Hardcoded schema in DEVICE_TOOLS | Tool definitions are static; validate at import time or skip (model input is already trusted via ALLOWED_PLAYERS; device input is validation-by-schema-check). |
| **Async utilities** | anyio / trio | asyncio only | asyncio is standard library; websockets and anthropic both use it natively. A second async runtime adds complexity. |
| **Dependency injection** | dependency-injector | Manual composition | Bridge has one `AsyncAnthropic()` client, one device registry dict, one per-player history dict. Inject by hand (or pass as params). |
| **Rednet / modem coordination** | Custom comms layer | Every device talks only to bridge | Architecture decision (PROJECT.md): no device-to-device messaging. Rednet would invite cross-device bugs. Bridge sees everything. |
| **LLM call from Lua** | Any Lua HTTP client | Keep API key outside Minecraft | Security decision. No Lua ever calls Claude directly. Bridge is the only API-key holder. |

## Alternatives Considered

| Component | Recommended | Alternative | Why Not |
|-----------|-------------|-------------|---------|
| **WebSocket server** | `websockets` 17.1 | `aiohttp`, `starlette`, `fastapi` | websockets is lightweight and focused; aiohttp/starlette/fastapi are full web frameworks. Bridge needs only WebSocket, not HTTP routing. |
| **Claude client** | `anthropic` 1.7.0 | `openai`, `ollama`, `llamacpp` | Project constraint: Claude API with tool use. Other clients incompatible. |
| **HTTP client (if ever needed)** | `httpx` or `aiohttp` | `requests` | If non-WebSocket HTTP endpoints appear (unlikely), `httpx` is async-native. `requests` blocks. Don't add until needed. |
| **Config parsing** | Env vars + hand Gson in Lua | `configparser`, `toml` | Config is tiny. Standard library covers it. External library is premature. |
| **Fake device harness** | Terminal-driven Python test client | Mock via monkeypatch | Real websocket client needed to test the protocol transport layer itself (frame marshalling, timeouts, reconnects). Monkeypatch can't test those. |
| **Logging destination** | Console (stdout) | File / syslog / cloud | Dev/local testing: console is fine. When bridge moves to a VPS, redirect stdout to a file or to a log aggregator. Use standard Python logging config to change this *without* code changes. |

## Limits and Constraints

| Constraint | Value | Implication |
|-----------|-------|-------------|
| CC:Tweaked WebSocket message | ≤ 131 KB per message | JSON protocol messages are ~1 KB; well within limit. No fragmentation needed. |
| CC:Tweaked concurrent open sockets | ≤ 4 per computer | Two devices (chat + worker) = 2 sockets. Safe headroom. |
| CC:Tweaked HTTP request timeout | 30 s default | WebSocket handshake bounded by this; once open, keep-alive pings (20s interval) maintain liveliness. |
| Anthropic token limit | Varies by model (Sonnet 5: 200K) | Agent loop bounded by MAX_TURNS (20 per request). Typical tool dispatch well under 200K tokens. |
| Chat Box send cooldown | ~1 s (mod-hardcoded) | Starter's SEND_GAP = 1.1 s respects this. Don't queue more than one send per second or drops occur silently. |
| Bridge command timeout | 120 s (line 32 in bridge.py) | Device must answer a tool command within 2 minutes or bridge assumes it timed out. Reasonable for turtle movement / chest sorting. |

## Sources

- **websockets** (HIGH): [PyPI websockets 17.1](https://pypi.org/project/websockets/), [official docs server API](https://websockets.readthedocs.io/en/stable/reference/asyncio/server.html), [upgrade guide](https://websockets.readthedocs.io/en/stable/howto/upgrade.html)
- **anthropic** (HIGH): [PyPI anthropic 1.7.0](https://pypi.org/project/anthropic/), [Claude Platform Docs — Python SDK](https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/python)
- **Claude models** (HIGH): [Claude Platform Docs — Model IDs](https://platform.claude.com/docs/en/about-claude/models/model-ids-and-versions)
- **pytest / pytest-asyncio** (HIGH): [PyPI pytest 9.1.1](https://pypi.org/project/pytest/), [PyPI pytest-asyncio 1.4.0](https://pypi.org/project/pytest-asyncio/), [pytest-asyncio docs](https://pytest-asyncio.readthedocs.io/)
- **CC:Tweaked 1.111.0** (HIGH): [tweaked.cc official API docs](https://tweaked.cc/module/http.html), [textutils docs](https://tweaked.cc/module/textutils.html), [websocket event signatures](https://tweaked.cc/event/websocket_message.html), [Modrinth release 1.111.0](https://modrinth.com/mod/cc-tweaked/version/1.111.0), [ATM9 0.2.61 modlist](https://www.curseforge.com/minecraft/modpacks/all-the-mods-9/files/5458414)
- **Advanced Peripherals 0.7.40r** (HIGH): [Official docs Chat Box API](https://docs.advanced-peripherals.de/0.8/peripherals/chat_box/), [Modrinth 0.7.40r](https://modrinth.com/mod/advancedperipherals/version/1.20.1-0.7.40r), [ATM9 modlist source](https://www.curseforge.com/minecraft/modpacks/all-the-mods-9/files/5458414)
- **Forge 1.20.1 Config** (HIGH): [CC:Tweaked guide — local IPs](https://tweaked.cc/guide/local_ips.html)
- **Python 3.12.10** (HIGH): Windows Store launcher (installed); [Python 3.12 release notes](https://www.python.org/downloads/release/python-31210/)

## Version Compatibility Matrix

| Component | Version | Compatible With | Verified |
|-----------|---------|-----------------|----------|
| websockets | 17.1 | Python 3.11+ | Yes (requires 3.11+; your 3.12.10 OK) |
| anthropic | 1.7.0 | Python 3.10+, asyncio | Yes |
| pytest | 9.1.1 | Python 3.8+, pytest-asyncio 1.4.0 | Yes |
| pytest-asyncio | 1.4.0 | pytest ≥ 8.4.0 | Yes (9.1.1 ≥ 8.4.0) |
| CC:Tweaked | 1.111.0 | Forge 1.20.1, ATM9 0.2.61 | Yes (verified in modlist) |
| Advanced Peripherals | 0.7.40r | Forge 1.20.1, CC:Tweaked 1.111.0 | Yes (verified in modlist) |
| Python (runtime) | 3.12.10 | All of above | Yes (in use; 3.11+ required for websockets 17.1) |

---

*Last updated: 2026-09-19 (v1.0 Local Round Trip research phase)*

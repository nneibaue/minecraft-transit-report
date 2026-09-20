# Domain Pitfalls: turtle-helper v1.0 Local Round Trip

**Scope:** Common mistakes when bringing the turtle-helper starter (bridge.py, client.lua, chat.lua) to life on a Windows 11 PC with a local All the Mods 9 Forge server and bridge.py both running locally. Focus: integration pitfalls between bridge, harness, and CC:Tweaked devices that have never run in game.

**Researched:** 2026-09-19
**Confidence:** HIGH (code inspection + official docs) for CC:Tweaked/Advanced Peripherals APIs; MEDIUM (cross-checked migration docs) for websockets library drift; HIGH for Anthropic SDK semantics.

---

## 1. Python `websockets` API Drift and Timeout Interaction

### Critical Pitfall: Legacy `websockets.serve()` Deprecation Blocks Future Python Updates

**What goes wrong:**
`bridge.py` line 230 uses the legacy API:
```python
async with websockets.serve(handler, "0.0.0.0", PORT, ping_interval=20, ping_timeout=20):
```
This is `websockets.legacy.server.serve()` (pre-12.0 API). The library deprecated the legacy API in version 14.0 and will remove it by 2030. If the venv pins `websockets` without an upper bound, a future `pip install --upgrade` pulls version 14+ which raises `DeprecationWarning`, or eventually 2030+ which breaks entirely.

**Why it happens:**
The websockets library modernized its API around 2024. The old `async def handler(ws)` handler signature and `serve()` function moved to `websockets.legacy` in 14.0. The new API (`websockets.asyncio.server.serve`) has a different handler signature `async def handler(websocket)` and different semantics. The starter picked up the old API when originally written; most tutorials still show it.

**Consequences:**
- Immediate: DeprecationWarning on websockets 14.x, unclear error messages on 15+
- Medium term: code breaks silently when Forge server runs and tries to reconnect, or logs spam with unintelligible tracebacks
- Long term: if author updates Python or installs to a fresh machine after 2030, bridge won't start at all

**Prevention:**
1. **Pin websockets version to a pre-14.0 release in requirements.txt** (e.g., `websockets==13.0.1`) with an explicit comment explaining the deprecation.
2. **Plan migration to the new API (websockets 14+) as a separate task**, but do NOT attempt it during v1.0 round trip (too risky when Lua is untested). The new handler signature and message handling differs; that's a medium-complexity refactor.
3. **Add a version check test** in bridge startup: `import websockets; assert websockets.__version__ < '14.0', "websockets 14+ requires migration to new API"` — fails fast with a clear error if someone upgrades.

**Warning signs:**
- DeprecationWarning about `websockets.legacy` when bridge starts
- `AttributeError: module 'websockets' has no attribute 'serve'` on websockets 15+
- Bridge never receives `hello` from Lua even though Lua console shows no connection error

**Phase ownership:** **Bridge environment (Phase 1) — validate and pin version before harness work.**

---

### Moderate Pitfall: `ping_interval` / `ping_timeout` Interact with CC:Tweaked's Socket Timeouts

**What goes wrong:**
`bridge.py` line 230 sets `ping_interval=20, ping_timeout=20`. This tells websockets to send a Ping frame every 20 seconds and expect a Pong back within 20 seconds. If no Pong arrives, websockets closes the connection.

CC:Tweaked's `http.websocket()` has its own internal socket timeout (typically 10–30 seconds per the server config). If the Lua device is slow to respond to Ping (e.g., if it's doing a long sort), the bridge may close the connection before Lua's socket timeout fires, or vice versa. This causes asymmetric connection deaths: the bridge sees the connection closed but the Lua device still thinks it's open (or thinks the bridge closed it), leading to reconnect loops.

**Why it happens:**
Two independent timeout mechanisms running in parallel, with no coordination. The websockets library assumes all peers implement the WebSocket RFC ping/pong correctly and respond within the timeout. CC:Tweaked implements the RFC but may be delayed by in-game tick processing or long Lua operations.

**Consequences:**
- Device reconnects even though no actual network failure occurred
- "Spurious" reconnects every 20–40 seconds if the device is busy
- Bridge logs show `websockets.exceptions.ConnectionClosed` but Lua sees no close event until the next message attempt
- Queue of results waiting for commands gets stuck because the connection flapped

**Prevention:**
1. **Set `ping_interval=None` and `ping_timeout=None` on the bridge** (line 230) to disable automatic ping/pong entirely. We don't need heartbeat detection for a LAN device that's always on the same network.
2. **Or: increase both to 60 seconds** if you want keep-alive for edge cases (NAT hole-punching), but then also increase CC:Tweaked's socket timeout in `computercraft-server.toml` to match or exceed.
3. **Test with sustained operations**: run a `sort_chest` that takes 5–10 seconds and verify no reconnect happens.

**Warning signs:**
- Bridge logs repeat `device disconnected: ...` then `device connected: ...` every 20–40 seconds
- Lua console shows no "disconnected" or "retrying" message; device thinks it's still connected
- Parallel reconnect storms if multiple devices are connected

**Phase ownership:** **Bridge environment (Phase 1) — decide ping strategy before devices connect.**

---

### Moderate Pitfall: `ConnectionClosed` Not Caught in `send_cmd()` Leaks Pending Futures

**What goes wrong:**
In `bridge.py` lines 41–55, `send_cmd()` creates a future in `pending[cid]` and waits for a result. If the device's connection closes while waiting (line 51 `await asyncio.wait_for(fut, CMD_TIMEOUT)`), the future never resolves. The `finally` block (line 54) cleans up `pending`, but only if `send_cmd()` completes. If the websocket closes and the device reconnects, the old `pending` dict still holds the orphaned future.

Specifically: if the device disconnects *during* a send on line 49 (`await dev["ws"].send(...)`), that send may raise `websockets.ConnectionClosed`. This exception is not caught, so `pending[cid] = fut` is never cleaned up. The next reconnect registers a new websocket, but the old pending future is still in the dict, consuming a tiny amount of memory and cluttering the event loop.

Over time (many reconnects), this is a slow memory leak. More immediately, if a caller is awaiting the old future and the device never reconnects with the same command ID, that task hangs forever.

**Why it happens:**
The code assumes `send()` always succeeds or times out. ConnectionClosed is an edge case that can happen if the device closes the socket between the device registration (line 190) and the send (line 49).

**Consequences:**
- Slow memory leak: pending dict grows to hundreds of entries over a day of restarts
- Stuck awaiters: if a tool call is awaiting a result and the device disconnects, the task hangs until max_tokens exhaustion
- Hard to debug: no error message, just silent hang or gradual slowdown

**Prevention:**
1. **Wrap the send in a try/except:**
```python
async def send_cmd(device_id: str, tool: str, args: dict | None = None) -> dict:
    dev = devices.get(device_id)
    if not dev:
        return {"ok": False, "error": f"device '{device_id}' is not connected"}
    cid = uuid.uuid4().hex[:8]
    fut = asyncio.get_running_loop().create_future()
    pending[cid] = fut
    try:
        await dev["ws"].send(json.dumps({"type": "cmd", "cid": cid, "tool": tool, "args": args or {}}))
        return await asyncio.wait_for(fut, CMD_TIMEOUT)
    except (asyncio.TimeoutError, websockets.ConnectionClosed) as e:
        if isinstance(e, asyncio.TimeoutError):
            return {"ok": False, "error": f"{device_id} did not answer within {CMD_TIMEOUT}s"}
        else:
            return {"ok": False, "error": f"{device_id} disconnected during send"}
    finally:
        pending.pop(cid, None)
```
2. **Or: catch at the connection level** in `handler()` and clean up all pending futures for that device on disconnect (line 206).

**Warning signs:**
- `len(pending)` dict grows over time even with successful commands and reconnects
- Arbitrary tools silently hang or return timeout after device reconnects
- Lua reconnect logs show device is back, but bridge never gets `hello` and old pending futures clog the loop

**Phase ownership:** **Bridge environment (Phase 1) — fix in send_cmd() before harness testing.**

---

## 2. Anthropic SDK Tool-Use Loop Mistakes

### Critical Pitfall: Appending SDK `MessageContent` vs. Dict to History Breaks Round-Trips

**What goes wrong:**
`bridge.py` line 166 appends the raw SDK response to history:
```python
hist.append({"role": "assistant", "content": resp.content})
```

`resp.content` is a `list[ContentBlock]` (SDK Pydantic model objects), NOT a list of dicts. When the history is passed back to `messages.create()` on line 161, the SDK accepts the objects directly (Pydantic serializes them), but the history is now a mix of types: some entries have `content` as lists of dicts (from tool results, line 175), others have lists of SDK objects (from responses). This works fine for the *next* API call, but if you serialize the history to JSON (e.g., to log it or persist it), or if you introspect it for debugging, you get a mix of serializable and non-serializable objects.

More critically: if the history is used to compute prompt length or is passed to a different model client, or if the SDK version changes how it handles mixed types, the code silently produces wrong results or crashes.

**Why it happens:**
The Anthropic SDK is permissive and accepts both plain dicts and Pydantic models in message history, so the bug doesn't manifest immediately. The starter was written to "just get it working" and didn't explicitly convert to dicts.

**Consequences:**
- History is inconsistent (mixed SDK objects and dicts), making debugging harder
- If someone later adds logging that JSON-serializes history, it crashes with `TypeError: Object of type TextBlock is not JSON serializable`
- If history is persisted between bridge restarts, unpickling fails
- Token counting (if added later) gives wrong results on mixed-type entries
- Future SDK versions may enforce stricter typing and break this code

**Prevention:**
1. **Always convert SDK responses to dicts before appending:**
```python
# Instead of:
# hist.append({"role": "assistant", "content": resp.content})
# Use:
hist.append({"role": "assistant", "content": [block.model_dump() for block in resp.content]})
```
2. **Or: use the SDK's `.model_dump()` method on the entire response** if available.
3. **Add a test assertion** that history is JSON-serializable: `json.dumps(hist)` should never raise TypeError.

**Warning signs:**
- Logs show `TypeError: Object of type ... is not JSON serializable` when history is logged
- History introspection code fails: `hist[i]["content"]` returns an object without expected dict keys
- Token estimation is wildly wrong on subsequent turns

**Phase ownership:** **Fake brain (Phase 3) — test with a stubbed response that exercises the history loop, verify it's JSON-serializable.**

---

### Critical Pitfall: `tool_result` Content Format Mismatch with SDK Semantics

**What goes wrong:**
`bridge.py` line 174 builds the tool result correctly:
```python
results.append({"type": "tool_result", "tool_use_id": block.id, "content": json.dumps(out)})
```

This is correct for Anthropic SDK 0.20.0+ (January 2024): `content` is a JSON string (the result of `json.dumps(out)`). However, if the SDK is downgraded to 0.19.x or earlier, or if the code is copy-pasted into a project using a different Anthropic wrapper, the format is wrong. The earlier SDK expects `content` to be a plain Python dict or string, not a JSON-serialized string *inside* a string. This causes the model to see the tool result as an unparseable JSON string, not as structured data, leading to hallucination ("I got this result but I can't read it, so I'll guess").

**Why it happens:**
The Anthropic SDK changed the tool_result format between versions. The starter was written for the current SDK but doesn't pin the version, so a downgrade or upgrade breaks it silently.

**Consequences:**
- Model receives tool results as opaque strings, not structured data
- Model hallucinates or gives wrong answers ("The device didn't respond" even though it did)
- Requests enter infinite retry loops because the model never sees the real response
- API costs balloon because the model can't make progress and retries

**Prevention:**
1. **Pin the Anthropic SDK version** in `requirements.txt`: `anthropic==0.94.0` (or whatever current stable version).
2. **Add a version check test** at bridge startup: `import anthropic; assert version_tuple(anthropic.__version__) >= (0, 20, 0)` — fail fast with a clear error.
3. **Validate tool result format on first device command**: capture the first tool_result dict and verify it's JSON-serializable and follows the spec (type, tool_use_id, content as string).

**Warning signs:**
- Model responds "I don't understand the device's response" or "The device didn't answer" even when it did
- Tool results appear in logs as unparseable strings: `"content": "{\\"ok\\": true, \\"data\\": ...}"`
- Requests get retried many times (stop_reason == "tool_use" repeatedly) with no progress

**Phase ownership:** **Fake brain (Phase 3) — test with a stubbed response that checks the tool_result format matches SDK expectations.**

---

### Moderate Pitfall: Missing `tool_result` for a `tool_use` ID Leaves Model Waiting

**What goes wrong:**
`bridge.py` lines 169–175 iterate over `resp.content`, find all tool_use blocks, and build a result for each. If a tool_use block is skipped (e.g., due to a missing tool in the device, or a crash in `run_tool()`), no `tool_result` is appended for that ID. The model never sees the result, so on the next `messages.create()` call, it's still waiting for a response to that tool_use. The model may retry the same tool, or hang indefinitely if the loop caps at 12 iterations (line 160).

For example: if `run_tool("list_devices", {})` raises an exception not caught, line 174 is skipped, and that tool_use_id never gets a result. The next iteration calls the model again, and the model sees its previous tool_use with no result, so it retries.

**Why it happens:**
The starter has a try/except on `run_tool()` (line 172 implicitly must succeed), but what if `run_tool()` itself raises an unexpected exception? The code doesn't have an explicit try/except around the loop building results.

**Consequences:**
- Model stalls waiting for a result that will never come
- Retries accumulate, burning API tokens
- From the user's perspective, the robot goes silent and eventually returns "something went wrong" after 12 retries
- Hard to debug because the exception in `run_tool()` is buried in logs

**Prevention:**
1. **Always build a result, even if the tool fails:**
```python
results = []
for block in resp.content:
    if block.type == "tool_use":
        try:
            out = await run_tool(block.name, dict(block.input))
            log.info("tool %s(%s) -> %s", block.name, block.input, json.dumps(out)[:200])
        except Exception as e:
            log.exception("tool %s failed with exception", block.name)
            out = {"ok": False, "error": f"internal error: {type(e).__name__}: {str(e)}"}
        results.append({"type": "tool_result", "tool_use_id": block.id, "content": json.dumps(out)})
```
2. **Test with a stubbed response that includes a tool_use** and verify every tool_use gets a result.

**Warning signs:**
- Model repeats the same tool_use request 3+ times in a row
- Bridge logs show exception in `run_tool()` but no tool_result in history
- Requests timeout or cap at 12 iterations with the model stuck on the same tool

**Phase ownership:** **Fake brain (Phase 3) — test tool error handling with a response that calls a non-existent tool.**

---

### Moderate Pitfall: History Trimming Cuts Between `tool_use` and `tool_result`

**What goes wrong:**
`bridge.py` lines 154–158 trim history to keep it bounded:
```python
def _bad_start():
    return hist[0]["role"] != "user" or not isinstance(hist[0]["content"], str)
while len(hist) > 1 and (len(hist) > MAX_TURNS * 2 or _bad_start()):
    hist.pop(0)
```

This pops from the front of history if it's too long. The check `_bad_start()` is supposed to ensure history always starts with a user message (plain string, not tool_result), but if the trimming *pauses* between a tool_use and its tool_result, the history becomes invalid. For example:
- hist[0]: user message
- hist[1]: assistant message with tool_use
- hist[2]: user message with tool_result for that tool_use
- Pop hist[0] because it's old
- Now hist[0] is the assistant tool_use block with no preceding user message before the history starts

When passed back to the API, the model sees a tool_use with no user message above it, which violates the contract.

**Why it happens:**
The trimming logic pops one entry at a time (line 158) without checking that it's not orphaning a tool_use/tool_result pair. The check _bad_start() only ensures the first entry *is* a user message, not that it *has* context.

**Consequences:**
- API rejects the request: `BadRequestError: invalid message structure`
- Model sees a dangling tool_use and may hallucinate the result
- User request fails with "something went wrong" (line 223 catch-all)

**Prevention:**
1. **Trim in logical units**: pop user + assistant message pairs together, or entire tool_use/tool_result pairs.
2. **Or: trim from the end instead of the front** (keep recent context), which is usually more valuable anyway.
3. **Add a validation test** that passes the trimmed history to `messages.create()` and catches `BadRequestError` early.

**Warning signs:**
- Bridge logs: `"invalid message structure"` error from the API
- Errors happen intermittently after many requests (when history is long enough to trim)
- History introspection shows a tool_use block at the very top with no user message above it

**Phase ownership:** **Fake brain (Phase 3) — test with many requests to trigger history trimming, verify no invalid message structure errors.**

---

### Minor Pitfall: `max_tokens=1024` Too Small for Complex Tool Responses

**What goes wrong:**
`bridge.py` line 161 sets `max_tokens=1024`. If the model's response (text + all tool_use blocks) exceeds 1024 tokens, the response is truncated and `stop_reason` is set to `"max_tokens"` instead of `"tool_use"` or `"end_turn"`. The loop exits early, the tool_use is incomplete, and the model never gets a result for it.

This happens if:
- A tool_use block is incomplete (missing arguments)
- The model's response includes long explanatory text before the tool_use
- Multiple tool_use blocks are packed tightly

**Why it happens:**
1024 tokens is a conservative default to keep costs low, but it's tight for a back-and-forth loop with large tool schemas (e.g., the list_devices tool returns a large dict of devices and capabilities).

**Consequences:**
- Model's tool calls get truncated, device receives malformed commands
- Model retries with fewer details in its reasoning, possibly calling the wrong tool
- Requests fail or produce wrong results

**Prevention:**
1. **Monitor stop_reason in logs** and alert if it's "max_tokens".
2. **Increase max_tokens to 2048 or 4096** for this use case. Tool-calling loops typically need headroom.
3. **Test with list_devices response that includes many devices** and verify stop_reason is "tool_use" or "end_turn", never "max_tokens".

**Warning signs:**
- Bridge logs show `stop_reason == "max_tokens"` on any request with many devices connected
- Tool calls have missing or partial arguments: `"args": {"text": "So..."`
- Requests fail unpredictably when multiple devices are connected

**Phase ownership:** **Fake brain (Phase 3) — tune max_tokens during testing, no need to fix before first end-to-end run.**

---

## 3. CC:Tweaked Lua on 1.20.1

### Critical Pitfall: `http.websocket()` Fails Silently with "Domain Not Permitted" for `localhost`

**What goes wrong:**
`client.lua` line 217 and `chat.lua` line 78 call `http.websocket(BRIDGE_URL)`. If `BRIDGE_URL` is `ws://localhost:8765`, CC:Tweaked blocks it by default. The call returns `nil, "Domain not permitted"` (error string). The code catches this as an error (line 224 in client.lua, line 84 in chat.lua), logs it, and retries in 5 seconds.

The issue: on Windows 11, `localhost` resolves to IPv6 `::1` first, and CC:Tweaked's default rule blocks all private/loopback addresses. Even if you manually edit `computercraft-server.toml` to allow `127.0.0.1`, the DNS lookup may return `::1` first, which is still blocked.

**Why it happens:**
CC:Tweaked denies all private and local IP ranges by default (`[[http.rules]] host = "$private" action = "deny"` in `computercraft-server.toml`). Windows 11 prefers IPv6, so `localhost` resolves to `::1`. The server rule `host = "127.0.0.1"` doesn't match `::1`, so the connection is denied.

**Consequences:**
- Lua prints `connect failed: Domain not permitted - retrying in 5s` forever
- Device never connects, even though the bridge is running
- User sees nothing; it *looks* like the bridge isn't running, when really it's a firewall rule

**Prevention:**
1. **Use `ws://127.0.0.1:8765` (IPv4 literal) instead of `localhost`** in both client.lua and chat.lua. This bypasses DNS and always resolves to IPv4 loopback.
2. **In `computercraft-server.toml` (in the world/serverconfig/ folder), add this rule** (before any deny rule):
```toml
[[http.rules]]
host = "127.0.0.1"
action = "allow"
```
   Or allow both IPv4 and IPv6:
```toml
[[http.rules]]
host = "127.0.0.0/8"
action = "allow"

[[http.rules]]
host = "::/1"
action = "allow"  # This is experimental; 127.0.0.1 is safer
```
3. **Restart the Minecraft server** after editing serverconfig/computercraft-server.toml. Changes to server config don't hot-reload; the server must restart.
4. **Test from the Lua prompt:** `http.websocket("ws://127.0.0.1:8765")` should connect (or return a websocket object), not throw "Domain not permitted".

**Warning signs:**
- Lua console: `connect failed: Domain not permitted - retrying in 5s` repeating forever
- Bridge is running (you can telnet to port 8765), but Lua never connects
- Same error on both client.lua and chat.lua (not a Lua bug, but a config issue)

**Phase ownership:** **Server config (Phase 2) — must be applied before any in-game device test.**

---

### Moderate Pitfall: `ws.receive()` Blocks Forever; No Timeout Parameter Exists

**What goes wrong:**
`client.lua` line 196 and `chat.lua` line 52 call `ws.receive()` in a loop. If the bridge closes the connection gracefully, `receive()` returns `nil` (line 196 in client.lua), and the loop exits. But if the connection hangs (e.g., the bridge is frozen), `receive()` blocks indefinitely with no way to time out from Lua.

The websocket object doesn't expose a `receive(timeout)` method; CC:Tweaked doesn't support timed receives on websockets (unlike some other libraries). So if the bridge never sends a message and never closes the connection, the Lua device hangs forever waiting for data.

**Why it happens:**
CC:Tweaked's HTTP API is synchronous from the Lua perspective. `receive()` is a blocking call with no timeout. The only escape is if the connection closes (server disconnects, timeout at the TCP level, etc.) or if the Lua coroutine is cancelled from outside.

**Consequences:**
- Lua device appears frozen / unresponsive in-game
- If the device is running in a coroutine via `parallel.waitForAny` (as chat.lua does, line 91), it hangs that entire parallel block
- The only recovery is to restart the device

**Prevention:**
1. **Don't rely on receive() to time out; rely on the bridge** to send keep-alive pings or close the connection. If the bridge is unresponsive, the bridge itself is the problem (fix Phase 1).
2. **Use `parallel.waitForAny` with a timer** to ensure the device doesn't hang waiting for a single message:
   ```lua
   local function session(ws)
       ws.send(textutils.serialiseJSON({type = "hello", ...}))
       while true do
           local rawOrNil = ws.receive()
           if rawOrNil == nil then return end
           -- process message
       end
   end
   
   local function timeout()
       while true do
           sleep(30)  -- check every 30 seconds
           error("websocket receive hung for 30s")
       end
   end
   
   parallel.waitForAny(session, timeout)  -- session or timeout, whichever exits first
   ```
3. **Or: accept the hang as a design limitation** and rely on manual restart or the OS-level socket timeout (typically 30–120 seconds per TCP RFC). For a small private server, this is probably fine.

**Warning signs:**
- Lua device appears to run fine initially (logs show "connected"), then goes silent and never responds to chat
- Device doesn't reconnect on bridge restart
- Device is consuming CPU (OS shows the Lua thread busy) but Minecraft is unresponsive

**Phase ownership:** **In-game run (Phase 5) — observe on first real device test; if it hangs, add a fallback timer or accept the limitation.**

---

### Moderate Pitfall: `websocket_message` Event URL Must Match Exactly (String Comparison)

**What goes wrong:**
`chat.lua` line 60 filters incoming websocket messages:
```lua
elseif ev[1] == "websocket_message" and ev[2] == BRIDGE_URL then
```

This checks if the event's URL (second argument) is exactly equal to the string stored in `BRIDGE_URL`. If `BRIDGE_URL` is set to `ws://127.0.0.1:8765` when the connection is made, but the event returns `ws://127.0.0.1:8765/` (with trailing slash), the strings don't match, and the message is ignored.

More commonly: if BRIDGE_URL changes during runtime (e.g., reconnect after restart), the check fails for messages from the old connection.

**Why it happens:**
CC:Tweaked returns the URL exactly as passed to `http.websocket()`, but URL normalization (trailing slashes, case sensitivity, port presence) varies. The Lua code does a naive string comparison instead of URL parsing.

**Consequences:**
- Device receives chat events or commands from the bridge but ignores them because the URL doesn't match
- Device appears to be connected (no error) but never processes incoming messages
- Silent failure: logs show no error, just no response

**Prevention:**
1. **Don't modify BRIDGE_URL after connection** — set it once at the top of the script and never change it.
2. **Test with a simple echo to verify the URL matches**: after connecting, immediately send a test message, receive the echo, and log both URLs to confirm they're identical.
3. **Or: relax the URL match** by parsing both URLs:
   ```lua
   local function url_matches(url1, url2)
       return url1:gsub("/$", "") == url2:gsub("/$", "")  -- ignore trailing slash
   end
   ```

**Warning signs:**
- Device logs show `connected as ...` but never logs `receive` events
- Bridge sends a `say` command but the Chat Box never speaks
- Device responds to periodic pings from the bridge but not to chat events

**Phase ownership:** **In-game run (Phase 5) — verify on first chat test; add a debug log of the received URL if messages aren't flowing.**

---

### Moderate Pitfall: `textutils.serialiseJSON` Empty Tables and Nil Fields

**What goes wrong:**
`client.lua` lines 82, 100–101 handle empty arrays by replacing them with `textutils.empty_json_array`:
```lua
if #items == 0 then items = textutils.empty_json_array end
```

This works for empty arrays, but what about:
1. **Nil fields in a table**: `{a = 1, b = nil, c = 3}` serializes to `{"a": 1, "c": 3}` (nil is omitted).
2. **Null values**: if you need to represent JSON `null`, you must use `textutils.json_null`, not `nil`.
3. **Mixed arrays/objects**: `{1, 2, x = "hello"}` is ambiguous; serialiseJSON makes a guess (often wrong).

If bridge.py receives `{no_rule = [], destination_full = []}` (empty arrays from client.lua line 100–101), and Python's json.loads() reads it, the Python dict has empty lists. But if the response is `{no_rule = nil}` (Lua omitted it), the Python dict doesn't have the key at all, and the model's tool schema validation fails ("missing required field").

**Why it happens:**
Lua's table model (associative arrays with optional integer keys) doesn't map cleanly to JSON (objects vs arrays). `serialiseJSON` has to guess. The starter correctly handles empty arrays with `textutils.empty_json_array`, but doesn't handle nil fields or null values uniformly.

**Consequences:**
- Tool results are missing fields that the bridge expects
- Model receives a truncated or invalid response structure
- Bridge validation fails or the model hallucinates

**Prevention:**
1. **Always use tables explicitly: `{no_rule = textutils.empty_json_array}` (never `{}`), and return all expected fields even if they're empty.**
2. **In `sort_chest` (line 86–102), ensure all return fields are always present:**
   ```lua
   local unsorted, stuck = {}, {}
   if #unsorted == 0 then unsorted = textutils.empty_json_array end
   if #stuck == 0 then stuck = textutils.empty_json_array end
   return {moved = moved, no_rule = unsorted, destination_full = stuck}
   ```
   — This is already done correctly. Ensure all other tools do the same.
3. **Test tool result schema**: on first `list_devices` call, inspect the returned JSON in bridge logs and verify all expected fields are present.

**Warning signs:**
- Bridge receives tool results with missing keys: `{"moved": 47}` instead of `{"moved": 47, "no_rule": [], "destination_full": []}`
- Model responds "the device didn't return expected fields"
- JSON schema validation errors in bridge logs

**Phase ownership:** **In-game run (Phase 5) — verify in first tool call; check all tools return consistent field sets.**

---

### Moderate Pitfall: `os.pullEvent()` vs. `os.pullEventRaw()` and Ctrl+T Termination

**What goes wrong:**
`client.lua` line 196 and `chat.lua` line 53 call `os.pullEvent()` in their loops. This is the correct choice. However, if Ctrl+T is pressed (the in-game interrupt key), `os.pullEvent()` raises a `Terminated` exception, which is caught by the outer `pcall` (line 219 in client.lua, line 80 in chat.lua), and the device shuts down.

This is the *intended* behavior, so not a pitfall here. The pitfall is if someone accidentally changes this to `os.pullEventRaw()`, which does NOT raise Terminated on Ctrl+T. Then Ctrl+T stops working as a way to interrupt the device.

**Why it happens:**
Confusion about which function to use. Both exist; one filters Terminated, one doesn't. Some tutorials show `os.pullEventRaw()` for edge cases.

**Consequences:**
- Device can't be interrupted from the Lua console (Ctrl+T is ignored)
- Device blocks forever listening, can only be stopped by restarting Minecraft

**Prevention:**
1. **Keep `os.pullEvent()` (not `os.pullEventRaw()`)** in both client.lua and chat.lua. Don't change it.
2. **Add a comment explaining this choice** if you modify the code later.

**Warning signs:**
- Ctrl+T in the Lua console doesn't interrupt the device
- Device is running but unresponsive to keyboard input

**Phase ownership:** **In-game run (Phase 5) — document in CLAUDE.md that Ctrl+T is the way to stop devices.**

---

### Minor Pitfall: `parallel.waitForAny()` Event Consumption Between Coroutines

**What goes wrong:**
`chat.lua` line 91 uses `parallel.waitForAny(connectLoop, drainOutbox)` to run two coroutines: one listens for websocket messages, the other drains the outbound message queue. Each coroutine calls `os.pullEvent()`. 

CC:Tweaked ensures each coroutine gets its own copy of the event queue, so an event consumed by `connectLoop` (e.g., `websocket_message`) doesn't affect `drainOutbox`. This is correct and is not a pitfall — it's the intended behavior.

The pitfall is if someone misunderstands this and assumes events are shared, or moves event-handling code between coroutines without understanding the consequences.

**Why it happens:**
Misunderstanding of how parallel works; tutorial confusion.

**Consequences:**
- If misunderstood, refactoring can break event handling inadvertently

**Prevention:**
1. **Document in chat.lua** that each coroutine has its own event queue.
2. **Don't move calls to `os.pullEvent()` between connectLoop and drainOutbox** without testing; they're independent.

**Warning signs:**
- After refactoring, chat messages aren't received (connectLoop didn't pull the event) or aren't sent (drainOutbox didn't pull the timer event)

**Phase ownership:** **In-game run (Phase 5) — document; no code change needed.**

---

### Minor Pitfall: `startup.lua` and Computer Label/ID Folder Mapping

**What goes wrong:**
When you place a computer or turtle in the world, Minecraft assigns it a unique ID (visible as `os.getComputerID()`). CC:Tweaked stores the computer's persistent state (files, label) in a per-ID folder on disk: `<world>/computercraft/computer/<id>/`. If you label the computer `sorter`, CC:Tweaked also creates a symlink or recognizes it by that label, but the folder is still the ID.

If you edit files directly on disk (e.g., place client.lua into the folder before the computer boots), the files appear when the computer starts. But if the computer boots first and you then edit files, the computer doesn't see the changes until it reboots. This is often fine, but if you're trying to iterate quickly during development, it's a gotcha.

More critically: if you place startup.lua on disk and the computer has already booted with a different startup.lua (or no startup), the old one is still in RAM, and the computer won't run the new one until restart.

**Why it happens:**
CC:Tweaked reads startup.lua at boot time and caches it in memory. File changes on disk aren't reflected until the computer restarts.

**Consequences:**
- You edit client.lua, expect it to run on the next `client` command, but the old version runs
- You add `shell.run("client")` to startup.lua on disk, reboot the computer, and it doesn't run
- Iteration is slow because every code change requires a reboot

**Prevention:**
1. **Always reboot the computer after editing files** (`/shutdown` in the Lua console, then `/start`).
2. **Use `wget` or pastebin to load files dynamically** instead of placing them on disk (but this requires internet, not ideal for a local server).
3. **Or: set up a dev loop** that uses the `edit` command in-game and copies to the device; this is slower but avoids the disk-persistence gotcha.
4. **Document in README.md** that changes to Lua files require a reboot.

**Warning signs:**
- You edit a file, run the program, and it uses the old version
- Changes to startup.lua don't take effect until reboot
- Iterating on the client code is tedious

**Phase ownership:** **Dev-loop setup (Phase 2 or early Phase 5) — document; consider a fast way to get files onto devices without reboots (e.g., a local web server that serves Lua files, or a pastebin-like script).**

---

## 4. Advanced Peripherals Chat Box on 1.20.1

### Critical Pitfall: Chat Event Argument Order and the Hidden Flag

**What goes wrong:**
`chat.lua` line 55 assumes the chat event signature is:
```lua
local ev = {os.pullEvent()}
-- ev[1] == "chat", ev[2] == username, ev[3] == message, ev[4] == uuid, ev[5] == isHidden
user = ev[2], text = ev[3], uuid = ev[4], hidden = ev[5] == true,
```

Advanced Peripherals on 1.20.1 fires the event with these exact arguments, in this order. If the version is wrong (1.19.2 vs 1.20.1 differ), or if a future update reorders arguments, the fields are swapped and the code collects wrong data.

More immediately: if you copy this code to a different server or version, and the event signature is different, messages won't be collected correctly.

**Why it happens:**
Mods evolve; event signatures change between versions. The starter was written for ATM9 (which pins AP version 0.7.35b or later for 1.20.1), but the code doesn't validate the event structure.

**Consequences:**
- Chat messages are collected with swapped fields: username is treated as message, etc.
- Bridge receives `{user: "hello world", text: "Nate", ...}` (backwards)
- Model doesn't recognize commands because usernames are in the text field

**Prevention:**
1. **Add a version check at startup**: inspect the Chat Box's `about()` method (if it exists) or log the first chat event to verify the field order.
2. **Or: add defensive assertion** in chat.lua after the first chat event:
   ```lua
   if ev[1] == "chat" then
       local user, text, uuid, hidden = ev[2], ev[3], ev[4], ev[5]
       assert(type(user) == "string" and #user > 0, "chat event arg 2 should be username string")
       assert(type(text) == "string", "chat event arg 3 should be message text")
       -- ... rest of processing
   ```
3. **Document in CLAUDE.md** the exact event signature expected and which mod version it's for.

**Warning signs:**
- Chat messages appear in bridge with field values swapped (username is very long, text is a single word)
- Model doesn't recognize `$robot` commands
- Bridge logs show strange user/text combinations

**Phase ownership:** **In-game run (Phase 5) — verify on first chat message; add debug log of the event structure if needed.**

---

### Moderate Pitfall: `sendMessage()` vs. `sendMessageToPlayer()` Argument Order

**What goes wrong:**
`chat.lua` line 31 calls `sendMessageToPlayer()`:
```lua
ok, err = chatBox.sendMessageToPlayer(m.text, m.to, m.prefix or DEFAULT_NAME)
```

The argument order (based on Advanced Peripherals 0.7.35b) is: message, username, prefix, brackets, bracketColor, range, utf8Support. The code passes: text, player, prefix. This is correct.

However, if the mod version is different, or if there's a typo in bridge.py when building the command (e.g., swapping text and to), the arguments can be wrong. For example, if bridge.py sends `{text: "hello", to: null}`, the chat.lua code is fine, but if it sends `{text: null, to: "hello"}`, sendMessageToPlayer tries to send a null message to the player "hello", which fails.

**Why it happens:**
bridge.py has only been tested with a fake device harness, never with real in-game code. A typo or logic error in the `say()` tool implementation (bridge.py line 58–62) could pass wrong arguments.

**Consequences:**
- Chat Box reports an error, message isn't sent
- Player doesn't get a response to their command

**Prevention:**
1. **Test the say() tool with a real Chat Box** on first in-game run. Send a few test messages and verify they appear.
2. **Add logging in chat.lua** to print the arguments before sending:
   ```lua
   if m.to then
       log("sending to player", m.to, ":", m.text)
       ok, err = chatBox.sendMessageToPlayer(m.text, m.to, m.prefix or DEFAULT_NAME)
   else
       log("broadcasting:", m.text)
       ok, err = chatBox.sendMessage(m.text, m.prefix or DEFAULT_NAME)
   end
   ```
3. **Verify bridge.py's say() builds the args correctly** (check that `args["text"]` and `args["to"]` are the right fields).

**Warning signs:**
- Chat Box logs show send failures: `"send failed: ..."`
- Messages are queued but never arrive
- Player types a command, bridge processes it, but no reply in chat

**Phase ownership:** **In-game run (Phase 5) — test say() on first device connection.**

---

### Minor Pitfall: Chat Box Cooldown and Requeue on Failure

**What goes wrong:**
`chat.lua` line 9 sets `SEND_GAP = 1.1` seconds to respect the Chat Box's ~1 second cooldown. If messages are sent faster, the Chat Box ignores them or returns an error. The code catches the error (line 35) and re-queues the message.

However, if the bridge sends multiple `say` commands in quick succession (e.g., several tool results in one turn), and the queue drains at 1.1s per message, the user waits a long time for all responses to appear in chat.

More critically: if the Chat Box's cooldown is actually 2 seconds (configurable), and the code sends at 1.1s intervals, every other message is dropped silently.

**Why it happens:**
The hardcoded SEND_GAP value assumes a specific cooldown; it's not configurable and doesn't validate the actual cooldown at runtime.

**Consequences:**
- Messages appear in chat out of order or with long delays
- If cooldown is longer than 1.1s, messages are lost

**Prevention:**
1. **Don't rely on a hardcoded value; query the Chat Box's cooldown config** at startup (if the API exposes it) and adjust SEND_GAP accordingly.
2. **Or: test the actual cooldown** by timing how fast the Chat Box accepts messages, and set SEND_GAP based on that.
3. **Or: accept the limitation** and document in README.md: "Messages are sent at ~1.1s intervals due to Chat Box cooldown."

**Warning signs:**
- Messages appear in chat with unpredictable delays
- If cooldown is misconfigured, every Nth message is missing

**Phase ownership:** **In-game run (Phase 5) — verify message delivery is reliable; tune SEND_GAP if needed.**

---

### Minor Pitfall: Chat Box Range Limits and Message Size

**What goes wrong:**
Advanced Peripherals Chat Box has a message range (default ~50 blocks) and a max message length. If a message exceeds the length or is sent outside the range, it's silently dropped or returns an error.

The code doesn't validate message length before sending.

**Why it happens:**
The starter's tools return relatively small messages, so this rarely surfaces. But if a tool returns a large response (e.g., a full chest inventory), and it's serialized to a long message, it could exceed the limit.

**Consequences:**
- Messages are silently dropped
- User sees no response

**Prevention:**
1. **Test with the largest expected message** (e.g., a list_rules response with 50 rules).
2. **Or: add validation** in chat.lua to truncate messages that are too long.

**Warning signs:**
- Some responses don't appear in chat, others do (depends on response size)

**Phase ownership:** **In-game run (Phase 5) — low priority; test if needed.**

---

## 5. Local Dedicated Server + Bridge on Windows PC

### Critical Pitfall: `computercraft-server.toml` Location and Server Restart Required

**What goes wrong:**
The `computercraft-server.toml` configuration file for CC:Tweaked on a Forge server is located in `<world>/serverconfig/computercraft-server.toml` (per world), not in the global `.minecraft/config/` folder. If you edit the wrong file, the changes don't take effect. Also, changes to server config require a full server restart; they don't hot-reload.

For ATM9 on a dedicated server, the world folder is typically `<server>/world/serverconfig/` or `<server>/saves/<world-name>/serverconfig/`.

**Why it happens:**
Forge has two config locations: global (client + server common) and per-world server-specific. The HTTP rules for CC:Tweaked are per-world because different worlds might have different security policies.

**Consequences:**
- You edit the global config file and the rule doesn't apply
- You edit the file, reload the server (not restart), and the old rule is still active
- Device still can't connect; it's a confusing gotcha

**Prevention:**
1. **Locate the correct file** using the Forge server logs (they print the config path on startup) or by finding the world folder manually.
2. **Add the allow rule for 127.0.0.1** to `<world>/serverconfig/computercraft-server.toml`:
```toml
[[http.rules]]
host = "127.0.0.1"
action = "allow"
```
   (If the file doesn't exist, create it or edit the existing one.)
3. **Stop the server completely** (not just reload), then restart it.
4. **Verify the change took effect** by checking the server logs or testing `http.websocket("ws://127.0.0.1:8765")` from a Lua console.

**Warning signs:**
- You edit serverconfig/computercraft-server.toml but device still gets "Domain not permitted"
- Server reload via `/reload` doesn't help; only a full restart works

**Phase ownership:** **Server config (Phase 2) — must be done before any in-game device test.**

---

### Moderate Pitfall: Rule Ordering and the Default Deny

**What goes wrong:**
CC:Tweaked's HTTP rules are checked in order. The first rule that matches is applied. If you have a deny rule before your allow rule, the deny wins. Also, if no rules match, the default is deny.

Example:
```toml
[[http.rules]]
host = "$private"
action = "deny"

[[http.rules]]
host = "127.0.0.1"
action = "allow"
```

The first rule denies all private addresses. The second rule allows 127.0.0.1. But 127.0.0.1 is private, so it matches the first rule and is denied before the second rule is checked.

**Why it happens:**
The order of TOML tables is not guaranteed (or is ordered by file position, depending on the TOML parser). If you append the allow rule at the bottom, it may come after the deny rule in the final config.

**Consequences:**
- Allow rule is never reached
- Device still gets "Domain not permitted"

**Prevention:**
1. **Place the allow rule before the deny rule** in computercraft-server.toml:
```toml
[[http.rules]]
host = "127.0.0.1"
action = "allow"

[[http.rules]]
host = "$private"
action = "deny"
```
2. **Or: remove the deny rule entirely** if you're only running local devices (not recommended for production, but fine for dev).
3. **Test with a Lua console**: `http.websocket("ws://127.0.0.1:8765")` should connect, not error.

**Warning signs:**
- Allow rule is in the file, but device still can't connect
- If you move the allow rule to the top and restart, it works

**Phase ownership:** **Server config (Phase 2) — document the rule order in README.md.**

---

### Moderate Pitfall: Windows Firewall Not a Factor for Loopback; Port Conflicts Are

**What goes wrong:**
On Windows 11, the Windows Firewall does not block loopback traffic (127.0.0.1 or ::1). So if the bridge is running on port 8765 and the server is on the same machine, there's no firewall issue.

However, if another application is already using port 8765, the bridge fails to start with "Address already in use". This is easy to miss if you don't check the bridge's startup logs.

**Why it happens:**
Port 8765 is not a well-known port, but it could be used by another service. Common causes: a previous bridge instance that didn't shut down cleanly, or a proxy service.

**Consequences:**
- Bridge fails to start
- User doesn't realize the bridge isn't running and blames Lua code

**Prevention:**
1. **Check the bridge startup logs** to confirm it's listening on port 8765.
2. **On Windows, use `netstat -ano | findstr :8765`** to see what's using the port (if anything).
3. **If port 8765 is unavailable, change it** in bridge.py (line 26) and in all Lua files (BRIDGE_URL).
4. **Add a startup check** in bridge.py to log which port it's listening on and confirm it's successful.

**Warning signs:**
- Bridge logs say `listen on :8765` but Lua still can't connect
- `netstat` shows something else is using port 8765

**Phase ownership:** **Bridge environment (Phase 1) — verify on startup.**

---

### Minor Pitfall: IPv6 `::1` vs IPv4 `127.0.0.1` on Windows 11

**What goes wrong:**
On Windows 11, DNS resolution prefers IPv6 if available. `localhost` resolves to `::1` first, then `127.0.0.1`. If you set `BRIDGE_URL = "ws://localhost:8765"` in Lua and the bridge is listening on `0.0.0.0` (which binds to IPv4), the connection may fail or be slow (timeout on IPv6, then fall back to IPv4).

CC:Tweaked's websocket implementation may not handle IPv6 well or may have a separate timeout for IPv6 attempts.

**Why it happens:**
Windows 11 has IPv6 enabled by default; happy eyeballs algorithm tries IPv6 first.

**Consequences:**
- Connection is slow (waits for IPv6 timeout, then retries IPv4)
- Or: connection fails entirely if IPv6 is broken in the environment

**Prevention:**
1. **Use IPv4 literal `ws://127.0.0.1:8765`** instead of `localhost` (already recommended above).
2. **Or: explicitly bind the bridge to `0.0.0.0` and ensure both IPv4 and IPv6 are available** (advanced, not needed for dev).

**Warning signs:**
- Connection attempts are very slow (~10–30 seconds before connecting)
- Connection fails if IPv6 is disabled or misconfigured

**Phase ownership:** **Bridge environment + Lua setup (Phase 1–2) — use IPv4 literal from the start.**

---

## 6. Fake Harness and No-API-Spend Testing Traps

### Critical Pitfall: Fake Model Responses Must Match SDK Object Shapes

**What goes wrong:**
When testing the bridge without spending API tokens, you might stub the `messages.create()` call with a fake response:
```python
async def fake_create(*args, **kwargs):
    return type('Response', (), {
        'content': [{'type': 'text', 'text': 'Hello'}],
        'stop_reason': 'end_turn'
    })()

anthropic.AsyncAnthropic.messages.create = fake_create
```

This works if the bridge code only accesses `response.content` and `response.stop_reason` as attributes. But if the code iterates over `response.content` and expects each item to have `.type` and `.id` attributes (as ContentBlock objects do), the fake dict-based response breaks:
```python
for block in resp.content:
    if block.type == "tool_use":  # fails: dict has no .type attribute
```

**Why it happens:**
The Anthropic SDK returns Pydantic model objects (MessageContent, ContentBlock, etc.), not plain dicts. Fake responses that use plain dicts don't match the SDK's object shape.

**Consequences:**
- Tests pass with fake responses but fail in production with real SDK responses
- Errors like `AttributeError: 'dict' object has no attribute 'type'`
- Bridge is broken when deployed

**Prevention:**
1. **Use the SDK's actual response classes in fakes**, not plain dicts:
```python
from anthropic.types import Message, ContentBlock, TextBlock, ToolUseBlock

async def fake_create(*args, **kwargs):
    return Message(
        id="msg-123",
        type="message",
        role="assistant",
        content=[TextBlock(type="text", text="Hello")],
        model="claude-sonnet-5",
        stop_reason="end_turn",
        stop_sequence=None,
        usage={"input_tokens": 10, "output_tokens": 5}
    )
```
2. **Or: construct fake responses using the SDK's `.model_validate()` or from_dict methods** to ensure they're properly structured.
3. **Test against both fake and stubbed-real responses** (e.g., mock the HTTP layer and return real Message objects) to catch shape mismatches.

**Warning signs:**
- Fake tests pass, real bridge fails with AttributeError
- Tests work with stubbed `messages.create()`, fail when you switch to real API

**Phase ownership:** **Fake brain (Phase 3) — ensure fake responses use correct SDK shapes, test with both fake and real shapes.**

---

### Moderate Pitfall: Tests Accidentally Call Real API When `ANTHROPIC_API_KEY` Is Set

**What goes wrong:**
If your shell has `ANTHROPIC_API_KEY` set (for real bridge testing), and you run a test suite that's supposed to use a fake/stubbed response, the real API might be called if the stub is incomplete. For example:
```python
def test_harness():
    # Fake response, but the stub doesn't cover all paths
    anthropic.AsyncAnthropic.messages.create = fake_create
    
    # This calls the stubbed create()
    # But if fake_create raises an exception, the original create() is called as a fallback
    # And suddenly $0.01 is spent on a real API call
```

Or: if the fake response is only stubbed for `messages.create()`, but the code also calls `messages.stream()` or other methods, the real API is called.

**Consequences:**
- Surprise API charges on test runs
- Tests are no longer truly free
- Hard to debug because the test *looks* like it's using a fake

**Prevention:**
1. **Set `ANTHROPIC_API_KEY` to a fake value in tests** or unset it:
```python
import os
os.environ.pop("ANTHROPIC_API_KEY", None)
# Or:
os.environ["ANTHROPIC_API_KEY"] = "sk-fake-key-for-testing"

# Client will either fail early or refuse to make real calls
```
2. **Mock the entire `anthropic` module**, not just `messages.create()`:
```python
from unittest.mock import MagicMock, patch

@patch("anthropic.AsyncAnthropic")
def test_harness(mock_anthropic):
    mock_anthropic.return_value.messages.create = fake_create
    # Now ALL calls to anthropic go through the mock
```
3. **Add an assertion at the start of each test**:
```python
def test_harness():
    assert os.environ.get("ANTHROPIC_API_KEY", "").startswith("sk-fake-"), \
        "ANTHROPIC_API_KEY should be fake for tests"
```

**Warning signs:**
- Unexpected charges on your API account during test runs
- Test logs show real API calls (tokens, model, latency)

**Phase ownership:** **Harness (Phase 2) and Fake brain (Phase 3) — set up CI/local test to prevent real API calls.**

---

### Minor Pitfall: Harness and Bridge Deadlock on Command with No Result

**What goes wrong:**
The fake harness sends a `cmd` message to the bridge and waits for a `result`. If the bridge never sends a result (e.g., because the tool doesn't exist, or the device disconnects), the harness hangs forever waiting for the result.

Example: harness sends `{type: "cmd", cid: "a1", tool: "sort_chest", args: {...}}`. The bridge looks for a device with role "turtle" or "computer", finds none, and returns `{ok: false, error: "..."}`. But if the harness doesn't wait for results on a timer, it blocks forever.

**Consequences:**
- Harness hangs, test doesn't complete
- CI/CD pipeline times out

**Prevention:**
1. **Add a receive timeout in the harness**:
```python
result = ws.recv(timeout=5)  # wait up to 5 seconds for a result
```
2. **Or: send a ping/pong to detect dead connections**:
```python
# After sending a command, check if the bridge is still responsive
await ws.send(json.dumps({"type": "ping"}))
pong = ws.recv(timeout=2)  # should get pong back
```
3. **Or: test scenarios in isolation**: test list_devices without needing a worker device, etc.

**Warning signs:**
- Harness hangs on a command send; test times out
- No error message, just stuck waiting

**Phase ownership:** **Harness (Phase 2) — add timeouts to recv() calls, design tests to not require worker device if possible.**

---

## Summary: Pitfall Prevention by Phase

| Phase | Key Pitfall to Address | Ownership |
|-------|------------------------|-----------|
| **Phase 1: Bridge environment** | websockets legacy API pin, ping timeouts, port availability, IPv4 literal, startup validation | bridge.py version pins + startup log |
| **Phase 2: Server config** | computercraft-server.toml location, rule ordering, allow 127.0.0.1, server restart | world/serverconfig/computercraft-server.toml + README |
| **Phase 2: Harness** | Fake response shapes, no API spending, receive timeouts | mock setup + test design |
| **Phase 3: Fake brain** | History consistency, tool_result format, pending futures, truncation edge cases | bridge.py tests with fake responses |
| **Phase 5: In-game run** | Domain not permitted error, websocket URL matching, textutils schema, chat event order, say() tool | first device connection + logs |
| **Phase 6: Reconnect** | Connection lifecycle, reconnect loop, no spurious closes | sustained operation test |

---

## Sources

### Python websockets
- [Changelog - websockets 14.0+ documentation](https://websockets.readthedocs.io/en/14.0/project/changelog.html)
- [Upgrade to the new asyncio implementation - websockets 17.0 documentation](https://websockets.readthedocs.io/en/stable/howto/upgrade.html)
- [Keepalive and latency - websockets 17.0.1 documentation](https://websockets.readthedocs.io/en/stable/topics/keepalive.html)

### Anthropic SDK
- [Python SDK - Claude Platform Docs](https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/python)
- [Feedback wanted: Tool helpers · anthropics/anthropic-sdk-python · Discussion #1036](https://github.com/anthropics/anthropic-sdk-python/discussions/1036)
- [Returning tool results: tool_result content block | Anthropic Api Intermediate Course](https://theneuralbase.com/anthropic-api/learn/intermediate/returning-tool-results-tool-result-content-block/)

### CC:Tweaked (1.20.1)
- [http.websocket API](https://tweaked.cc/module/http.html)
- [Allowing access to local IPs - CC:Tweaked guide](https://tweaked.cc/guide/local_ips.html)
- [textutils module](https://tweaked.cc/module/textutils.html)
- [parallel module](https://tweaked.cc/module/parallel.html)
- [os module](https://tweaked.cc/module/os.html)
- [Issue #695: http.get() and http.websocket() - Could not connect](https://github.com/cc-tweaked/CC-Tweaked/issues/695)
- [Discussion #626: local host not permitted](https://github.com/cc-tweaked/CC-Tweaked/discussions/626)

### Advanced Peripherals (1.20.1)
- [Chat Box documentation - Advanced Peripherals 0.7](https://docs.advanced-peripherals.de/0.7/peripherals/chat_box/)
- [Chat Box - Advanced Peripherals-Documentation](https://github.com/IntelligenceModding/Advanced-Peripherals-Documentation/blob/0.7/docs/peripherals/chat_box.md)

### Forge / Minecraft Server Config
- [Configuration - Wiki | Vampirism](https://wiki.vampirism.dev/docs/wiki/configuration) (general Forge config layout)
- [Server/Forge Mod Config files - Mods Discussion - Minecraft Forums](https://www.minecraftforum.net/forums/mapping-and-modding-java-edition/minecraft-mods/mods-discussion/2668295-server-forge-mod-config-files)

### Windows Networking
- [localhost vs. 127.0.0.1 with IPv6 on Windows 11](https://www.elevenforum.com/t/localhost-vs-127-0-0-1-with-microsofts-sshd.37562/)
- [Python 3.12 asyncio on Windows - Event loop policies](https://docs.python.org/3.12/library/asyncio-policy.html)


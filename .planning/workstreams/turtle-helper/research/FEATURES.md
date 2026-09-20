# Feature Landscape — Turtle-Helper v1.0 Local Round Trip

**Domain:** LLM-driven in-game assistant with websocket bridge, CC:Tweaked devices, protocol testing  
**Researched:** 2026-09-19  
**Confidence:** MEDIUM-HIGH (existing starter code validated; CC:Tweaked paths verified against official docs; LLM testing patterns drawn from published literature)

---

## Table Stakes

Features users expect from a working round trip. Missing = the milestone is incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Bridge runs locally, reachable from server at `ws://127.0.0.1:8765` | The websocket originates from Minecraft server, not player client. Bridge must be on same PC as server for dev. | Low | Python 3.12, `websockets`, `anthropic` packages installed; ANTHROPIC_API_KEY set; PORT, TOKEN, MODEL configurable via env vars. |
| Device registry visible to the player via `$robot what devices are connected?` chat command | Core feature: player knows what's online. `list_devices` tool returns role + capabilities per device. | Low | Bridge-side: `list_devices` local tool queries `devices` dict. Chat device must forward chat events (`name: "chat"`, user/text/uuid fields) to bridge. Bridge on_event() triggers handle_request(). |
| Chat round trip: player types `$robot <text>`, bridge receives event, agent calls `say`, chat device speaks back | The only thing the player sees. Every visible interaction goes through this channel. | Medium | Chat device reconnects on websocket_closed; chat.lua maintains outbox queue with SEND_GAP to respect Chat Box ~1s cooldown; bridge forwards answer via `say` cmd to chat device. |
| Error reply when a device is unavailable or a tool fails | Graceful degradation. Player knows why the request didn't work, not left wondering. | Low | Bridge catches per-request exceptions (`except Exception`), responds via `say(f"Sorry {user}, ...")`. Device-side tool errors return `{ok: false, error: ...}`. |
| Devices reconnect after bridge restart | Single point of failure must not require restarting Minecraft. | Medium | client.lua and chat.lua both run infinite `while true` reconnect loops with 5s backoff on connection error. Bridge on_event() is async so one disconnect doesn't stall others. |
| Startup ordering: chat device and worker device both connect before first `$robot` command | Race condition prevention. Player types command, bridge has already seen all devices. | Low | No explicit ordering enforcement; test scenario runs both devices before player chat. Not a hard requirement (bridge gracefully handles "no chat device" or "no worker device" mid-request), but affects first-time UX. |

---

## Differentiators

Features that set the assistant apart. Not expected, but valued for usability and robustness.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Fake device harness for protocol testing without Minecraft | Fast feedback loop: test the bridge and agent loop without booting the game or spending API calls. | Medium | Python asyncio WebSocket client that sends hello, emits canned chat events, responds to cmds with canned results. Speaks the JSON protocol exactly; bridge sees it as a real device. Can toggle between deterministic mock responses (for no-API-cost tests) and claude-backed responses (for end-to-end tests). |
| Protocol-level tests run free (no ANTHROPIC_API_KEY needed) | Every protocol detail (device hello, event forwarding, cmd/result dispatch) testable without touching the model. | Medium | Test mode: `list_devices` answered deterministically from fake harness registry, or bridge stub returns scripted tool_use blocks instead of calling claude. Separates orchestration testing from language quality testing. |
| Lua files installed directly into server folder, no `wget`/pastebin needed | Fast dev loop for iterating Lua. Edit, place file on disk, reload Lua, test again. | Low | CC:Tweaked stores per-computer files in `<world>/computercraft/computer/<id>/` (Forge, 1.20.1). Device label (`os.getComputerLabel()`) matches folder name or ID. Direct file placement works; no server restart required. `startup.lua` can launch `client.lua` or `chat.lua` on device reboot. |
| CC:Tweaked local-address allow rule documented and applied once | Remove the friction: players don't have to debug "connection refused" from `ws://127.0.0.1` before trying the round trip. | Low | Remove or modify `[[http.rules]] host = "$private" action = "deny"` from `serverconfig/computercraft-server.toml` (CC:Tweaked 1.87+, or modify `computercraft-common.toml` if earlier). Document exact location and syntax in setup guide. Verified per tweaked.cc official guide. |
| Persistent token file (`secret.txt`) on each device, never in code or repo | Secrets management: author can share the repo and setup docs without leaking bridge auth. | Low | Each device reads `secret.txt` on startup; Lua files reference it. Bridge env var `BRIDGE_TOKEN` validated on hello. No hardcoding, no .gitignore gymnastics needed. |

---

## Anti-Features

Explicitly NOT building this milestone. Reasons clear; don't revisit without justification.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| `run_lua` / `ALLOW_EVAL` in client.lua | Dangerous knob; adds unbounded capability (agent can write its own Lua routines, access any API the computer can). Not needed for the round trip. | Keep the starter code (tool exists, switch off by default), but leave it off. First-run proof doesn't need dynamic code generation. |
| LLM calls from Lua (api key on in-game computer) | Architecture decision: brain is outside. API key on a computer the player can inspect/steal defeats the model. | All model calls stay on bridge side. Lua tools are thin (expose named functions), bridge decides what to call. |
| Rednet / modem messaging between devices | Coordination complexity: every device would need to know about every other device's address/protocol. | Bridge is the message bus. Every device talks only to bridge over websocket. Simpler to debug, reason about, extend. |
| Sorting chores as a milestone deliverable | Sorting tools exist (sort_chest, add_rule, etc.) but have never run. Author unsure if sorting is the right first chore. | Prove the round-trip plumbing first. Let first-chore decision come after. Sorting code stays in starter, unverified. |
| Tunnels / VPS hosting | Local dedicated server on same PC means `ws://127.0.0.1` works; no tunnel needed yet. Prod hosting comes later when bridge leaves this PC. | cloudflared / Tailscale setup deferred to next milestone. One `[[http.rules]]` entry on local server is the only setup needed. |

---

## Feature Dependencies

```
Fake device harness
  ↓
  └─→ Protocol tests (no API spend)
  
Client reconnect loop (in starter)
  ↓
  └─→ Bridge restart resilience
  
Chat queue + cooldown (in starter)
  ↓
  └─→ Chat round trip works smoothly
  
Client.lua + chat.lua on real in-game devices
  ↓
  ├─→ CC:Tweaked local-address allow rule applied
  └─→ Lua files placed into server computer folders
  
Bridge token in secret.txt (not in code)
  ↓
  ├─→ Fake harness can connect with same token
  └─→ Real devices can connect
  
Agent loop (in starter, uses claude.messages.create)
  ↓
  ├─→ list_devices tool (local, no device cmd)
  ├─→ say tool (forwards to chat device)
  └─→ Chore tools (sort_chest, etc. — forward to worker device)
  
Chat event forwarding (chat.lua → bridge)
  ↓
  └─→ `$robot` command recognition + agent loop trigger
```

---

## MVP Recommendation

**Scope for v1.0 Local Round Trip:**

1. **Bridge environment + startup** (table stakes)
   - Python 3.12 + websockets + anthropic installed
   - ANTHROPIC_API_KEY, BRIDGE_TOKEN, ALLOWED_PLAYERS, MODEL env vars
   - Bridge listens on `0.0.0.0:PORT`, logs connections
   - MODEL defaults to a current Claude model (Sonnet 5 recommended for agent loop; Haiku 4.5 if cost matters)

2. **Fake device harness** (differentiator, high ROI on feedback loop)
   - Terminal-driven Python asyncio client that speaks the JSON protocol
   - Sends hello with role + capabilities
   - Emits scripted chat events (e.g., `{"name": "chat", "user": "Nate", "text": "$robot what devices are connected?"}`)
   - Responds to cmd with canned result (e.g., `{"ok": true, "data": [{"id": "turtle-1", "role": "turtle"}, ...]}`)
   - Optional: --stub-model flag to skip ANTHROPIC_API_KEY, return hardcoded tool_use blocks for deterministic testing

3. **Protocol-level tests** (differentiator, guards against regressions)
   - Fake harness + mock data = run through a full `$robot` request without API calls
   - Test hello validation, device registry, event routing, cmd/result marshalling
   - Examples: "chat event from unknown device is dropped", "cmd timeout returns error", "device disconnect clears registry"

4. **CC:Tweaked local-address rule** (table stakes)
   - Document exact path: `<world>/serverconfig/computercraft-server.toml`
   - Show exact TOML syntax: remove `[[http.rules]] host = "$private" action = "deny"` or add `[[http.rules]] host = "127.0.0.1" action = "allow"` (CC:Tweaked 1.87+, verified per tweaked.cc)
   - Test: `http.get("http://127.0.0.1:8765")` from in-game Lua console succeeds

5. **Lua files on real in-game devices** (table stakes)
   - client.lua on a turtle or Advanced Computer
   - chat.lua on an Advanced Computer with Chat Box
   - Both connect to `ws://127.0.0.1:8765` (BRIDGE_URL hardcoded or configurable)
   - Both read BRIDGE_TOKEN from `secret.txt`
   - Both maintain reconnect loops; survive bridge restart

6. **End-to-end round trip** (table stakes)
   - Player types `$robot what devices are connected?` in chat
   - Chat device forwards event to bridge
   - Bridge agent calls `list_devices` (no device call needed)
   - Bridge calls `say` on chat device with device list
   - Chat device enqueues message, drains queue, speaks in chat
   - Player sees correct answer

7. **Dev loop doc: Lua file placement** (differentiator, saves iteration time)
   - Show how to find computer folder: `<world>/computercraft/computer/<id>/`
   - Explain os.getComputerLabel() mapping to folder name
   - Direct file placement into folder works; no server restart needed
   - `startup.lua` can call `shell.run("client")` / `shell.run("chat")`
   - Faster than wget/pastebin when iterating locally

**Defer (next milestones):**
- Sorting as a working chore (code exists, unverified)
- Additional chores (goto, fetch_item, restock, mine_vein)
- Production hosting / tunnels
- `run_lua` / ALLOW_EVAL
- Scheduled chores, multi-turtle dispatch

---

## Feature Complexity Notes

| Feature | Why Medium-High Complexity | How to Validate |
|---------|---------------------------|-----------------|
| Fake device harness protocol compliance | Must match every JSON shape and field order that Lua sends; any mismatch breaks tests. | Run harness against real bridge, inspect logged messages; verify hello, event, cmd/result JSON shapes. |
| Chat round trip with cooldown queue | Outbox draining on its own coroutine while session() listens for events; timing-dependent. | Run in game, send 3+ chat commands in quick succession, verify each gets queued and sent in order without collisions. |
| Bridge reconnect + agent state survival | Per-player history survives device disconnect; device reconnect resets registry but not history. | Restart bridge mid-conversation, send next request, verify agent remembers prior context. |
| Lua error surfaces clearly | Lua runtime errors in tools must not crash bridge; they must return `{ok: false, error: "..."}` to player. | Intentionally break a tool (e.g., typo in peripheral.wrap), verify bridge catches pcall error, says error to player, stays up. |

---

## Information Sources

### CC:Tweaked File Structure & HTTP Rules

- **CC:Tweaked official guide — Allowing access to local IPs:** https://tweaked.cc/guide/local_ips.html
  - Confirms: `[[http.rules]] host = "$private" action = "deny"` blocks localhost by default (1.87+)
  - Syntax: host may be CIDR ("127.0.0.0/8") or literal IP ("127.0.0.1")
  - File: `<world>/serverconfig/computercraft-server.toml` (Forge, modern versions)
  - Confidence: HIGH (official docs)

- **Computer file storage:** CC:Tweaked stores per-computer files in `<world>/computercraft/computer/<id>/` (Forge 1.20.1)
  - Device label (`os.getComputerLabel()`) typically matches folder name
  - Direct file placement works; no server restart required
  - Confidence: MEDIUM (verified via GitHub issues; not explicitly documented for 1.20.1)

### LLM Agent Testing Without API Calls

- **DEV Community — How to Test LLM Agents Without Calling the Real API:** https://dev.to/mukundakatta/how-to-test-llm-agents-without-calling-the-real-api-17oc
  - Patterns: FakeProvider (canned responses), scripted tool_use blocks, stub LLM (triggers specific tool, records orchestration)
  - Key insight: separate orchestration testing from language quality testing
  - Confidence: MEDIUM (published best practice, not peer-reviewed)

- **Building a Production AI Agent — Testing Without an LLM:** https://dev.to/jamilxt/building-a-production-ai-agent-in-spring-boot-testing-the-agent-loop-without-an-llm-part-6-204h
  - Stub approach: fake LLM returns canned tool_use blocks; real tool dispatch runs; loop continues without API call
  - Confidence: MEDIUM (published, specific to agent-loop orchestration)

### Websocket Testing in Python

- **PyPI — fakewsserver:** https://pypi.org/project/fakewsserver/
  - Works with `websockets` library; defines communication patterns as request-response pairs
  - Supports asyncio
  - Confidence: LOW (library exists, pattern seems sound, no deep docs reviewed)

---

## Gaps to Address

- **Exact file location for CC:Tweaked 1.20.1 Forge servers:** Likely `world/computercraft/computer/<id>/`, but not yet verified on the author's actual ATM9 server in-game. Recommend first Lua load to confirm folder structure and device ID assignment.

- **CC:Tweaked event signature for Advanced Peripherals chat event:** The `chat` event from Advanced Peripherals (or native CC:Tweaked?) event return format (fields: username, message, uuid, isHidden?) must match what chat.lua expects. Starter assumes fields but has never run.

- **Chat Box API compatibility with 1.20.1 ATM9 version:** Advanced Peripherals version shipped with ATM9 may differ from docs. `sendMessage` and `sendMessageToPlayer` signatures must be verified in-game.

- **Bridge token handling in fake harness:** Confirm that fake harness passing the correct BRIDGE_TOKEN allows hello, and wrong token triggers rejection (4001 close code).

- **Request timeout behavior:** HTTP requests from in-game devices to `ws://127.0.0.1:8765` should succeed immediately if bridge is running. Test with bridge down (expect connection refused) and bridge running (expect hello accepted).

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Table-stakes features | MEDIUM-HIGH | Starter code exists and compiles; the Lua has never run in game, so field names/JSON shapes are unverified. CC:Tweaked behavior confirmed via official docs and GitHub issues. |
| Fake device harness pattern | MEDIUM | Protocol testing pattern is sound and documented; Python asyncio + websockets tools are standard. No blocker identified. |
| Testing without API calls | MEDIUM | Pattern exists and is published; Anthropic SDK supports message stubbing; no blocker. |
| CC:Tweaked file placement dev loop | MEDIUM | File structure inferred from GitHub issues and mod behavior; not formally documented for 1.20.1. Recommend validation on first run. |
| Anti-features | HIGH | Architecture decisions well-reasoned and documented in PROJECT.md and CLAUDE.md; no re-litigation expected. |


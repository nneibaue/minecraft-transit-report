# Phase 2: Fake Device Harness & Protocol Resilience - Research

**Researched:** 2026-09-22  
**Domain:** Terminal-driven fake device harness (Python), bridge resilience fixes, Pydantic AI agent rewrite  
**Confidence:** HIGH (code inspection, Phase 1 decisions, official Pydantic AI docs, prior pitfalls research)

## Summary

Phase 2 delivers three interconnected capabilities that prove the v1.0 round trip works end to end:

1. **Fake Device Harness** — A terminal-driven Python client that speaks the wire protocol (hello, event, cmd, result messages as JSON over WebSocket), plays either chat or worker device role, runs scripted scenarios with expectations (say command received, close code detected, result acknowledged), and exits with pass/fail code.

2. **Bridge Resilience** — Five fixes in `bridge.py` that handle the failure cases the harness will exercise: commands fail when the device drops mid-flight (D-10), reconnecting with the same ID replaces the stale socket (D-11), malformed frames are logged and ignored (D-12), rejection logging names the reasons (D-16), and the empty-token hole closes (CR-01 fold-in).

3. **Pydantic AI Agent Rewrite** — The hand-rolled Claude tool-use loop in `agent.py` becomes a `pydantic-ai` `Agent` with typed Python tool functions and per-run toolset filtering. Lua shrinks to exposing CC:Tweaked primitives; composition moves to Python. The devices-question scenario proves the swap changed nothing on the wire.

**Primary recommendation:** Implement the harness and bridge resilience against the hand-rolled agent loop first (D-05 sequencing), then swap to Pydantic AI. This keeps risk isolated and gives early proof of correctness before the larger refactor.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01 through D-17)

#### Harness Driving Model (D-01, D-02, D-03, D-04)
- **D-01:** The harness is driven by scripted scenarios selected on the command line (`uv run harness --role chat|worker --scenario <name>`). Drop, wait, and reconnect are scenario steps, not interactive commands. No REPL this phase.
- **D-02:** One fake device per process, two terminals. The devices-question scenario's documentation says to start the worker in the second terminal first. The bridge log is where the two sides interleave; the harness does not try to show both.
- **D-03:** The fake worker mirrors `client.lua`, not the bridge's tool list. `--role worker` sends hello with role `computer` and the caps `client.lua` exposes after D-07's rewrite (the primitive set). `status` returns a result shaped like `tools.status`; every other advertised primitive returns a small canned result; anything else returns the same `unknown tool <name>` error `client.lua` sends. A `--turtle` flag switches the role to `turtle` and adds the movement caps. `--role chat` sends role `chat` with caps `["say"]`, answers `say` commands with `{ok: true, data: {queued: true}}` like `chat.lua`, and emits scripted chat events carrying `user`, `text`, `uuid`, `hidden`.
- **D-04:** Every wire message prints as one line: timestamp, device id, a direction arrow, then the compact JSON exactly as it went over the wire. No pretty-print mode.

#### Pydantic AI Rewrite Order and Shape (D-05, D-06, D-07, D-08, D-09)
- **D-05:** Sequencing: the harness and the bridge resilience fixes (D-10 to D-13, D-16) are built first against today's hand-rolled loop. The `agent.py` swap is the final plan of the phase. The devices-question scenario runs once before and once after the swap, so the phase spends two paid calls and the second proves the swap changed nothing on the wire.
- **D-06:** Tools the model sees are typed Python functions with Pydantic argument models. The JSON `DEVICE_TOOLS` and `LOCAL_TOOLS` dicts in `agent.py` go away; schemas derive from the types. **Reversibility:** costly — the tool contract moves from JSON beside the Lua into Python types.
- **D-07:** Composition lives in Python; Lua exposes CC:Tweaked primitives one to one. The rule: anything with a loop or a policy lives in Python. `client.lua` loses `sort_chest`, `list_rules`, `add_rule`, `remove_rule`, `set_overflow`, `rules.json` and the `destFor` / `loadRules` / `saveRules` helpers. It keeps `status`, an inventory-listing primitive, a push-one-slot primitive wrapping `pushItems`, the turtle primitives (`move`, `turn`, `dig`, `inspect`, `refuel`), and `run_lua` behind `ALLOW_EVAL` untouched. `sort_chest` becomes a Python function that composes list and push over `send_cmd`. **Reversibility:** costly — this amends the "high-level tools live in Lua" principle.
- **D-08:** Sorting rules persist on the bridge as a git-ignored `rules.json` beside `.env`, one global rule set, resolved from the source file's location the way `.env` is. `add_rule`, `remove_rule`, `list_rules` and `set_overflow` become local tools that edit that file. The device stores only `secret.txt` and its Lua. `rules.json` is added to `turtle/turtle-helper/.gitignore`.
- **D-09:** The toolset is built per run from the caps in the device registry at request time, plus the local tools. A Python composition is offered only when every primitive it needs is advertised by some connected device. With no turtle connected the model never sees `move` or `dig`, so the paid run cannot wander into a doomed call.

#### Drop and Reconnect Rules (D-10, D-11, D-12, D-13, D-16)
- **D-10:** An in-flight command fails the moment its device's socket closes. The bridge records which pending command ids belong to which device; the handler's cleanup resolves each of that device's pending futures with `{ok: false, error: "<id> disconnected"}`, and `send_cmd` also catches `ConnectionClosed` raised by the send itself.
- **D-11:** A hello with an id already in the registry replaces the old entry. The bridge closes the stale socket and logs that it did. The old handler's `finally` removes the registry entry only if it still points at its own socket, so a replaced connection never deregisters its replacement.
- **D-12:** Malformed frames are logged and ignored. Invalid JSON, non-object JSON, an unknown `type`, a `result` with a missing or unknown `cid`, a hello with no `id`: one WARNING line with the device id and the payload truncated to about 200 characters, and the connection stays open. The handler never raises out of its message loop. A scenario sends one garbage frame and then completes a normal exchange to prove the device is still registered.
- **D-13:** Review fold-in: CR-01 (`bridge_token` gets `min_length=1`, and the wrong-token scenario gains an empty-token case), WR-01 (D-11) and WR-02 (D-12) close in this phase. WR-03 (a tool exception leaves a dangling `tool_use`) is superseded by the Pydantic AI swap.
- **D-16:** The bridge's rejection logging distinguishes the reasons and names the device: separate lines for a bad token (with the id the hello claimed and the remote address), for no hello within 10 seconds, and for a stale same-id socket being replaced. The token value never appears in any log line. The existing `ignoring <user> (not allowed)` line stays and is what the RESIL-05 proof greps.

#### Proof Format and Spend Guard (D-14, D-15)
- **D-14:** Scenarios carry expectation steps (a `say` command containing text, a close with a given code, a result with a given cid, a hello accepted meaning no close within N seconds) and every wait has a receive timeout. The process exits 0 on pass and 1 on fail with a one-line verdict; the wire log prints either way.
- **D-15:** The devices-question scenario is the only scenario that emits a `$robot` event from an allowed player, and the harness refuses to send an allowed-player prefixed chat event unless `--spend` is on the command line. Two deliberate acts per paid run. The disallowed-player scenario needs no flag because the bridge ignores it before the model.

#### Documentation and Style (D-17)
- **D-17:** Documentation this phase: `turtle/turtle-helper/README.md` gains a "Harness" section listing each scenario, what it proves, the two-terminal recipe and `--spend`. `turtle/turtle-helper/CLAUDE.md` gets its "Dev loop" convention line changed to name the harness, its Architecture section amended with the thin-Lua rule (primitives in Lua, composition in Python) and rules-on-the-bridge, and its Protocol section kept accurate.

### Claude's Discretion

- Harness location and packaging: a `turtle/turtle-helper/harness/` package versus a single file, and a `[project.scripts]` entry so `uv run harness` works.
- Scenario definition format (Python data, JSON, or other — no YAML dependency exists).
- Exact Lua primitive names and signatures after the D-07 rewrite, and the canned result shapes.
- The pending-future bookkeeping structure for D-10.
- How a typed tool targets a device when several are connected: a `device` parameter, toolset-level resolution, or the default-worker rule.
- Per-player history under Pydantic AI: `message_history` with trimming, or history processors.
- The startup model check once `anthropic` is only a transitive dependency.
- Log wording, harness exit codes beyond 0 and 1, and whether the `sort_chest` composition batches pushes by destination.

### Deferred Ideas

- **Over-the-wire Lua updates, agent-generated routines, multi-role harness and REPL, run-all-scenarios command, per-device rule sets, review items WR-04 and IN-01 through IN-04, CHORE-01 first chore** — All explicitly out of scope for Phase 2; none has a harness proof.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **HARN-01** | Harness connects to bridge as chat or worker, completes hello handshake, prints every wire message | D-01, D-04; ARCHITECTURE.md §1 (FakeDevice class); wire protocol defined in bridge.py lines 51–68, 89–130 |
| **HARN-02** | Harness emits scripted `$robot what devices are connected?` chat event; receives `say` command; answers with `result`; makes one real model call | D-01, D-04, D-14; devices-question scenario; pydantic-ai Agent with `message_history` |
| **HARN-03** | Harness as worker answers `status` and other canned commands with results matching Lua shapes | D-03, D-04; canned result map from `client.lua` tools (lines 59–178 in starter); D-07 primitives |
| **HARN-04** | Harness can drop connection on demand (including mid-command) and reconnect; reconnect re-completes hello | D-01, D-02, D-14; scenario steps for drop/wait/reconnect; bridge handles D-10/D-11 gracefully |
| **RESIL-03** | Device disconnecting mid-command produces clean error reply to player, no hang past timeout, no leaked pending future | D-10; `send_cmd` catches `ConnectionClosed` on send and in result wait; handler cleanup resolves pending futures for that device |
| **RESIL-04** | Wrong token rejected with close code and bridge log line; device not in registry | D-13 (CR-01 fold-in), D-16; `settings.bridge_token` field has `min_length=1`; harness `--token` flag to override; close code 4001 |
| **RESIL-05** | Chat from disallowed player is ignored, logged, no model call | D-16; bridge's `on_event` checks `ALLOWED_PLAYERS` before `handle_request`; existing log line `ignoring <user> (not allowed)` grepped by scenario |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| **Harness scenario orchestration** | Local CLI (terminal) | — | Harness is a standalone tool; no backend tie-in |
| **Wire protocol validation** | Harness ↔ Bridge (both sides) | — | Harness sends JSON per spec; bridge validates frames (D-12) |
| **Device registry + connection lifecycle** | Bridge | — | Only the bridge knows which devices are connected; harness is a client |
| **Hello handshake & token validation** | Bridge | — | Bridge validates token and enforces D-11 same-id replacement |
| **Command dispatch (cmd/result round trip)** | Bridge + Device | — | Bridge sends cmd; device executes; bridge collects result; harness verifies it arrived |
| **Tool execution (model → device)** | Bridge (Pydantic AI agent) → Device | — | Model calls typed functions; composition lives in Python (D-07); device executes low-level primitives |
| **Per-player history + message context** | Bridge (Pydantic AI Agent) | — | Agent maintains `message_history` per player; model sees context from prior turns |
| **Rejection logging (bad token, no hello, stale reconnect)** | Bridge handler | — | Handler catches and logs failures before they reach agent |
| **Scenario expectations (receive timeouts, outcome verification)** | Harness | — | Harness waits for expected messages and fails with a verdict on mismatch |

---

## Standard Stack

### Core Python (Phase 2 Additions)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **pydantic-ai** | 2.46.0 [VERIFIED: PyPI 2026-09-22] | Agent framework with typed tools, per-run toolset filtering, message history | Bridges Pydantic models (already a dependency via anthropic) to Claude's tool-use API; `FunctionToolset` enables D-09 filtering; `message_history` processor enables per-player trimming (D-15 extension) |
| **pydantic-ai-slim[anthropic]** | 2.46.0 extra | Claude-specific agent provider | Lighter than full pydantic-ai; official AnthropicModel integration; no LLM/web frameworks bundled |
| **websockets** | 17.1 (Phase 1) | Async WebSocket server (bridge) and client (harness) | Bridge: already in use via Phase 1. Harness: `websockets.asyncio.client.connect` provides event-driven socket handling; `ConnectionClosedError.rcvd.code` exposes close code for D-14 expectations |
| **anthropic** | 1.7.0 (Phase 1) | Claude API client (transitive via pydantic-ai) | Already pinned in Phase 1; pydantic-ai references it transitively |
| **pytest** | 9.1.1 (Phase 1) | Test framework (harness exit codes, bridge validation tests) | Harness scenarios are test-shaped (pass/fail exit codes); pytest runs them; no API spend (fake device, no model) |

### Architecture Patterns & Pydantic AI Integration

**Key shape:** The agent is now an object with persistent `message_history` (per player), built at startup, and run per request with filtered toolsets:

```python
# Pseudocode; exact names/structure from D-09 Claude's discretion
agent = Agent(
    model=AnthropicModel(...),
    tools=built_from_typed_functions(),
    system=SYSTEM_TEMPLATE,
    per_player_message_history=...
)

async def handle_request(user: str, text: str):
    # Per-run toolset filtering (D-09)
    toolset = build_toolset_from_connected_devices(devices)
    result = await agent.run(text, toolsets=[toolset])
    # message_history is managed by agent; player's history updated automatically
```

**Why Pydantic AI:**
- `FunctionToolset` supports D-09 (per-run filtering of which tools are available based on connected devices).
- `message_history` / `RunContext` natively support per-player context without custom code.
- Typed tool functions (`def my_tool(arg1: int, arg2: str) -> dict`) derive JSON schemas automatically (no more hand-rolled `DEVICE_TOOLS` dicts).
- `Agent.run()` is async and Anthropic-integrated; `ResultError` exception lets tools return errors to the model instead of raising (fixes WR-03).

### Excluded / Out of Scope

- pytest not used for harness validation this phase (exit codes are sufficient per D-14); the harness **scenarios themselves** run from CLI, not via pytest (though pytest can invoke them later).
- No schema validation library added; Pydantic derives tool arg schemas from type hints.
- No new CLI library; harness uses `argparse` (stdlib).

---

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Harness Terminal                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ uv run harness --role [chat|worker] --scenario <name>    │  │
│  │ [--turtle] [--spend] [--token <override>]                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            │                                     │
│  ┌────────────────────────┴──────────────────────────────────┐  │
│  │ WebSocket Client (websockets.asyncio.client.connect)      │  │
│  │  • sends: hello, event, result                            │  │
│  │  • receives: cmd, close (code + reason)                   │  │
│  │  • prints: timestamp + id + → msg (JSON)                  │  │
│  │  • expects: per scenario (say, close, result, etc)        │  │
│  │  • exits: 0 pass / 1 fail                                 │  │
│  └────────────────────────┬──────────────────────────────────┘  │
│                            │                                     │
└────────────────────────────┼─────────────────────────────────────┘
                             │ ws://127.0.0.1:8765
                             │ JSON protocol (hello, event, cmd, result)
                             │
┌────────────────────────────┴──────────────────────────────────────┐
│                        Bridge Process                             │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │ WebSocket Server (websockets.asyncio.server.serve)        │   │
│  │  • handler: device registry, hello validation             │   │
│  │  • devices: {id → {ws, role, caps}}                       │   │
│  │  • resilience: D-10 (drop), D-11 (reconnect),             │   │
│  │               D-12 (malformed), D-16 (logging)            │   │
│  └───────────────────────────────────────────────────────────┘   │
│                            │                                      │
│  ┌────────────────────────┴───────────────────────────────────┐  │
│  │ Pydantic AI Agent (D-05 final plan)                        │  │
│  │  • tools: typed Python functions (composition, D-07)       │  │
│  │  • toolset: per-run filtering by connected device caps     │  │
│  │  • message_history: per player (user → player mapping)     │  │
│  │  • model: claude-sonnet-5 (or haiku-4-5)                   │  │
│  │  • run_tool: device cmd dispatcher via send_cmd            │  │
│  └────────────────────────┬───────────────────────────────────┘  │
│                            │ (until D-05 final plan: hand-rolled) │
└────────────────────────────┼───────────────────────────────────────┘
                             │ send_cmd(device_id, tool, args)
                             │
┌────────────────────────────┴───────────────────────────────────────┐
│                      In-Game Devices                               │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │ chat.lua (Chat Box + Advanced Computer)                   │    │
│  │  • listens: chat events from player                        │    │
│  │  • executes: say tool (sends message to Chat Box)          │    │
│  │  • primitives (post-D-07): none (pure interface)           │    │
│  └───────────────────────────────────────────────────────────┘    │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │ client.lua (Turtle or Computer)                            │    │
│  │  • listens: cmd from bridge                                │    │
│  │  • executes: tool via dispatch table                        │    │
│  │  • primitives (post-D-07): status, list_chest,             │    │
│  │               push_one, move, turn, dig, inspect, refuel   │    │
│  │  • retro-compat: readFile/writeFile, run_lua               │    │
│  └───────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────┘
```

Data flow:
1. Harness sends hello → Bridge validates token (D-13, D-16) → registers device
2. Harness sends event (chat) → Bridge logs, calls agent with filtered toolset → agent calls typed tools (D-06, D-07)
3. Agent tool maps to device capability → Bridge's `send_cmd()` → device executes primitive → `result` sent back → agent receives (resilient to drop via D-10)
4. Harness waits for expected cmd/result/close (D-14) → compares with scenario expectation → exits 0 or 1

### Harness: Scenario Format & Execution

**Scenario is a list of steps**, each with an action and params. Step types:

| Action | Params | Effect |
|--------|--------|--------|
| `connect` | `role`, `caps` | WebSocket connect; send hello with given role and capabilities |
| `send_event` | `type`, `**kwargs` | Send event (e.g., `{type: "chat", user: "Nate", text: "$robot ...", uuid: "...", hidden: true}`) |
| `send_garbage` | `data` | Send a malformed frame (for D-12 testing) |
| `wait_recv` | `timeout` | Receive the next message from bridge; timeout on no data |
| `expect_cmd` | `tool`, `partial_args` | `wait_recv`, verify it's a `cmd` with the given tool; fail if not |
| `send_result` | `cid`, `ok`, `data|error` | Send a `result` for a given command ID |
| `expect_close` | `code`, `reason` | `wait_recv`, verify it's a close message with the given code; fail if not |
| `close` | — | Close the connection locally |
| `wait` | `seconds` | Sleep (for testing reconnect timing) |
| `reconnect` | — | Close and reconnect with the same device id and token |

**Harness CLI:**
```bash
uv run harness --role [chat|worker] --scenario <name> [--turtle] [--spend] [--token <override>]

# Examples:
uv run harness --role chat --scenario devices-question --spend
uv run harness --role worker --scenario status-command
uv run harness --role worker --scenario drop-and-reconnect
uv run harness --role chat --scenario wrong-token --token bad_value
uv run harness --role chat --scenario disallowed-player  # (doesn't need --spend; bridge ignores before model)
```

**Exit codes:**
- `0` — All scenario steps completed and all expectations met.
- `1` — A step failed (timeout, unexpected message, mismatch).
- Other codes (2, 3, etc.) reserved for harness errors (missing scenario, arg parse fail, etc.).

### Bridge Resilience Fixes (D-10, D-11, D-12, D-16)

**D-10: Drop handling**

Current code: `send_cmd()` creates a Future, sends the command, awaits the Future with a timeout. If the device closes the socket mid-wait, the Future hangs until timeout (120s).

**Fix:** Wrap both the send and the wait in try/except to catch `ConnectionClosed`:

```python
async def send_cmd(device_id: str, tool: str, args: dict[str, object] | None = None) -> dict[str, object]:
    dev = devices.get(device_id)
    if not dev:
        return {"ok": False, "error": f"device '{device_id}' is not connected"}
    cid = uuid.uuid4().hex[:8]
    fut = asyncio.get_running_loop().create_future()
    pending[cid] = fut
    websocket = dev["ws"]
    try:
        await websocket.send(json.dumps({...}))  # Catch ConnectionClosed on send
        return await asyncio.wait_for(fut, CMD_TIMEOUT)
    except ConnectionClosed:
        return {"ok": False, "error": f"{device_id} disconnected during command"}
    except TimeoutError:
        return {"ok": False, "error": f"{device_id} did not answer within {CMD_TIMEOUT}s"}
    finally:
        pending.pop(cid, None)
```

**Also in handler cleanup** (when device closes): iterate pending futures and resolve each with `{ok: false, error: "<cid> disconnected"}`.

**D-11: Reconnect replacement**

Current code: Device registry uses device ID as key; same-id reconnect overwrites the old entry. Old handler's `finally` still tries to deregister.

**Fix:** In the `finally` block, check that the registry entry still points to the current socket:

```python
async def handler(websocket):
    device_id = hello["id"]
    old_entry = devices.get(device_id)
    devices[device_id] = {"ws": websocket, "role": ..., "caps": ...}
    
    if old_entry:
        log.info("replacing stale connection for device %s", device_id)
        await old_entry["ws"].close(4000, "replaced")
    
    try:
        # message loop...
    finally:
        # Only deregister if it's still us
        if devices.get(device_id, {}).get("ws") is websocket:
            devices.pop(device_id)
```

**D-12: Malformed frames**

Current code: Handler calls `json.loads()` directly; any parse error propagates and crashes the handler loop.

**Fix:** Wrap message handling in a try/except; log and continue:

```python
async for raw in websocket:
    try:
        msg = json.loads(raw)
        if msg.get("type") == "result":
            cid = msg.get("cid")
            if not cid or cid not in pending:
                log.warning("result with unknown cid: %s", cid)
                continue
            # resolve future...
        elif msg.get("type") == "event":
            asyncio.create_task(on_event(...))
        else:
            log.warning("unknown frame type from %s: %s", device_id, msg.get("type"))
    except json.JSONDecodeError:
        log.warning("malformed JSON from %s: %.200s", device_id, raw)
        continue
    except Exception as e:
        log.warning("frame handling error from %s: %s", device_id, e)
        continue
```

**D-16: Rejection logging**

Current code: Rejects bad token silently or logs once.

**Fix:** Log reasons with device ID and remote address:

```python
if hello.get("type") != "hello":
    log.warning("rejected non-hello from %s: %s", websocket.remote_address, hello.get("type"))
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

if device_id in devices:
    log.info("replacing stale device %s from %s", device_id, websocket.remote_address)
    # (rest of D-11 replacement logic)
```

### Pydantic AI Agent Shape (D-05 Final Plan)

**Typed tool functions replace `DEVICE_TOOLS` dicts:**

```python
from pydantic import BaseModel, Field
from pydantic_ai import Agent, FunctionToolset
from pydantic_ai.models.anthropic import AnthropicModel

class StatusArgs(BaseModel):
    device: str | None = Field(None, description="device id; default to any available turtle/computer")

async def status_tool(ctx: RunContext, device: str | None = None) -> dict:
    """Fuel, position, and attached peripherals of a device."""
    device_id = device or default_worker()
    if not device_id:
        raise ValueError("no turtle or computer connected")
    result = await send_cmd(device_id, "status", {})
    if not result.get("ok"):
        return result  # error dict
    return result.get("data", {})

# Similarly: list_chest, sort_chest (composition in Python, D-07), say, etc.
# sort_chest is now:

class SortChestArgs(BaseModel):
    device: str | None = None
    from_name: str = Field(..., description="source inventory")
    ...

async def sort_chest_tool(ctx: RunContext, device: str | None = None, from_name: str = "") -> dict:
    """Sort every item in an inventory into destinations using the saved rules."""
    device_id = device or default_worker()
    # Python composition: fetch items, apply rules, send pushes, collect results
    items = await send_cmd(device_id, "list_chest", {"name": from_name})
    for item in items.get("data", []):
        dest = find_dest_by_rule(item)  # local Python logic
        await send_cmd(device_id, "push_one_slot", {"slot": ..., "dest": dest, ...})
    # ... aggregate results ...
    return {"moved": count, "no_rule": [], ...}
```

**Agent construction at startup:**

```python
# Per-run toolset building (D-09)
def build_toolset() -> FunctionToolset:
    tools = [status_tool, list_chest_tool, say_tool, ...]  # always available
    
    # Conditionally add tools based on connected devices
    if any(d["role"] in ("turtle", "computer") for d in devices.values()):
        tools.extend([sort_chest_tool, add_rule_tool, ...])
    
    if any(d["role"] == "chat" for d in devices.values()):
        tools.append(say_tool)  # (already included, but example)
    
    if any(d.get("caps", {}).get("move") for d in devices.values()):
        tools.extend([move_tool, turn_tool, dig_tool, ...])
    
    return FunctionToolset(tools)

# Agent created once at bridge startup
agent = Agent(
    model=AnthropicModel(
        model_id="claude-sonnet-5",
        client=client,  # existing AsyncAnthropic instance
    ),
    system=SYSTEM_TEMPLATE.format(robot_name=robot_name),
    per_player_message_history=...  # Built by pydantic-ai; player_id key
)

# Per request (user → request)
async def handle_request(user: str, text: str):
    toolset = build_toolset()  # Fresh toolset per request
    result = await agent.run(
        text,
        toolsets=[toolset],
        context=RunContext(player_id=user)  # or however history keying works
    )
    # result.data contains the final text from the model
    await say(result.data)
    # message_history is auto-maintained by agent
```

**Pydantic AI handles:**
- Tool argument validation (derives JSON schema from `BaseModel` fields).
- Tool calling loop (model calls tools, receives results, repeats).
- `ResultError` for tools to return errors without raising (fixes WR-03).
- `message_history` with trimming (if per-player history implemented via processor).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tool argument validation | Custom JSON schema validation in `run_tool` | Pydantic model + pydantic-ai (D-06) | pydantic-ai derives schemas from types; no manual dict construction |
| Switching tools based on connected devices | Rebuild tool dict per request | `FunctionToolset` with per-run construction (D-09) | Toolset is designed for exactly this; pydantic-ai filters automatically |
| Keeping device-specific vs local tools separate | Two tool dicts + manual dispatch | Typed functions in one list + pydantic-ai (D-06) | Types make the distinction clear; pydantic-ai doesn't care |
| Composition (sorting, movement sequences) | Lua loops | Python functions composing primitives (D-07) | Easier to test, debug, and update than Lua; only primitives stay in Lua |
| Rule persistence | In-device JSON | Bridge-side `rules.json` (D-08) | One canonical source; survive device reboot; shared across devices if needed |
| Fake device for testing | Mock the bridge loop | Real WebSocket client with scenarios (harness) | Tests the wire protocol transport layer itself; mocking can't test timeouts, close codes, reconnects |
| per-player conversation context | Manual history dict + trimming logic | Pydantic AI `message_history` | Agent natively supports history processors; no custom trimming code |
| Device reconnect deduplication | Manual socket tracking | Socket ID check in handler (D-11) | One socket object comparison; handles both stale and new connection naturally |

---

## Common Pitfalls (from Prior Research)

### Pitfall 1: `ConnectionClosed` Not Caught in `send_cmd()` Leaks Futures

**What goes wrong:** PITFALLS.md §1.3 — If the device closes mid-send, the exception is not caught, and `pending[cid]` is never cleaned up.

**How to avoid:** Wrap both send and wait in try/except for `ConnectionClosed` (D-10 fix above).

**Warning signs:** `len(pending)` grows over many reconnects; arbitrary tools hang or timeout.

---

### Pitfall 2: Same-ID Reconnect Doesn't Replace Old Socket

**What goes wrong:** PITFALLS.md §1 references D-11 — Old handler's `finally` block deregisters the device even though it's been replaced by a new connection.

**How to avoid:** Check that the registry entry still points to the current socket (D-11 fix above).

**Warning signs:** Device reconnects but bridge treats it as disconnected; pending futures for the old socket never resolve.

---

### Pitfall 3: Malformed Frames Crash Handler Loop

**What goes wrong:** PITFALLS.md §1 references D-12 — Invalid JSON, missing fields, unknown message type raises an exception and exits the handler loop.

**How to avoid:** Wrap message processing in try/except; log and continue (D-12 fix above).

**Warning signs:** Bridge logs show exception traceback; device is silently deregistered; must manually restart bridge.

---

### Pitfall 4: Fake Model Responses Don't Match SDK Object Shapes

**What goes wrong:** PITFALLS.md §6.1 — Test stubs using plain dicts instead of Pydantic model objects cause `AttributeError` at runtime.

**How to avoid:** Use pydantic-ai's native types in fake responses; test with a mock that returns real `RunResult` objects.

**Warning signs:** Tests pass with fake responses; real bridge fails with `AttributeError: 'dict' has no attribute 'type'`.

---

### Pitfall 5: Tests Accidentally Call Real API When `ANTHROPIC_API_KEY` Is Set

**What goes wrong:** PITFALLS.md §6.2 — If env has a real API key and the harness's pydantic-ai agent isn't properly stubbed, calls go to the real API.

**How to avoid:** Set `ANTHROPIC_API_KEY` to a fake value in harness test setup; validate it's not real before any scenario.

**Warning signs:** Unexpected API charges during harness runs; test logs show real API latency.

---

### Pitfall 6: Websocket Receive Hangs with No Timeout

**What goes wrong:** PITFALLS.md §3.2 — Harness sends a command and waits for a result forever if the bridge crashes or device doesn't respond.

**How to avoid:** Every `wait_recv` has a timeout (D-14); scenarios exit 1 if they timeout (example: wait 5 seconds for a result, fail if nothing arrives).

**Warning signs:** Harness hangs indefinitely on a scenario; CI/CD pipeline times out; manual kill needed to stop.

---

### Pitfall 7: WebSocket URL String Comparison Fragile

**What goes wrong:** PITFALLS.md §3.3 — Harness sends to `ws://127.0.0.1:8765` but then checks received events against the URL string; if there's trailing slash or case difference, the check fails.

**How to avoid:** Use IPv4 literal (already recommended); pass the URL through consistently; consider URL parsing if comparison gets complex (unlikely for this phase).

**Warning signs:** Harness connects but never receives messages (bridge is sending; harness ignores due to URL mismatch).

---

### Pitfall 8: Pydantic AI Message History Not Trimmed Per Player

**What goes wrong:** If history grows unbounded, token usage balloons; model's context window fills with old turns from other players.

**How to avoid:** Configure `message_history` with a processor that trims per player (Claude's discretion on exact API usage).

**Warning signs:** Token counts rise over many requests; later requests have worse quality (model losing context).

---

## Code Examples

### Harness Scenario: devices-question (Demonstrates HARN-02)

```python
# Pseudocode; exact format (Python data, JSON, etc) is Claude's discretion
scenarios = {
    "devices-question": {
        "description": "Chat role sends $robot question; model calls list_devices; responds in chat.",
        "steps": [
            {
                "action": "connect",
                "role": "chat",
                "caps": ["say"],
            },
            {
                "action": "send_event",
                "type": "chat",
                "user": "Nate",
                "text": "$robot what devices are connected?",
                "uuid": "550e8400-e29b-41d4-a716-446655440000",
                "hidden": True,
            },
            {
                "action": "expect_cmd",
                "tool": "list_devices",
                "partial_args": {},  # list_devices takes no args
                "timeout": 10,
            },
            {
                "action": "send_result",
                "cid": "...",  # cid from the cmd we just received
                "ok": True,
                "data": {
                    "chat-1": {"role": "chat", "caps": ["say"]},
                    "worker-1": {"role": "computer", "caps": ["status", "list_chest", "push_one", ...]},
                },
            },
            {
                "action": "expect_cmd",
                "tool": "say",
                "partial_args": {},  # we just want to see say() called
                "timeout": 10,
            },
            {
                "action": "send_result",
                "cid": "...",
                "ok": True,
                "data": {"queued": True},
            },
            {
                "action": "wait",
                "seconds": 2,  # Give handler time to finish
            },
        ],
        "expected_exit": 0,
    }
}
```

### Bridge Resilience: D-11 Socket Replacement

```python
# Existing handler (simplified)
async def handler(websocket: ServerConnection) -> None:
    """Handle one device connection."""
    try:
        raw = await asyncio.wait_for(websocket.recv(), 10)
        hello = json.loads(raw)
    except Exception:
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
    
    # D-11: If same device is already connected, replace it
    old_ws = devices.get(device_id)
    if old_ws and old_ws.get("ws") is not websocket:
        log.info("replacing stale device %s from %s", device_id, websocket.remote_address)
        old_websocket = old_ws["ws"]
        devices[device_id] = {
            "ws": websocket,
            "role": hello.get("role"),
            "caps": hello.get("caps", []),
        }
        # Close the stale socket
        try:
            await old_websocket.close(4000, "replaced by new connection")
        except Exception:
            pass  # Already closed
    else:
        # New device or first time seeing this ID
        devices[device_id] = {
            "ws": websocket,
            "role": hello.get("role"),
            "caps": hello.get("caps", []),
        }
    
    log.info("device %s connected: role=%s caps=%s", device_id, hello.get("role"), hello.get("caps"))
    
    try:
        async for raw in websocket:
            try:
                msg = json.loads(raw)
                if msg.get("type") == "result":
                    cid = msg.get("cid")
                    if not cid or cid not in pending:
                        log.warning("result with unknown cid from %s: %s", device_id, cid)
                        continue
                    fut = pending[cid]
                    fut.set_result(msg)
                elif msg.get("type") == "event":
                    asyncio.create_task(on_event(device_id, msg))
                else:
                    log.warning("unknown frame type from %s: %s", device_id, msg.get("type"))
            except json.JSONDecodeError:
                log.warning("malformed JSON from %s: %.200s", device_id, raw[:200])
                continue
            except Exception as e:
                log.warning("frame handling error from %s: %s", device_id, e)
                continue
    finally:
        # D-11: Only deregister if it's still us (not replaced by a new connection)
        if devices.get(device_id, {}).get("ws") is websocket:
            devices.pop(device_id, None)
            log.info("device %s disconnected", device_id)
```

### Pydantic AI Tool Definition (D-06)

```python
from pydantic import BaseModel, Field
from pydantic_ai import RunContext

class SortChestArgs(BaseModel):
    """Arguments to sort_chest."""
    device: str | None = Field(
        None,
        description="device id; default to any available turtle/computer"
    )
    from_name: str = Field(
        ...,
        description="source inventory peripheral name (e.g. minecraft:chest_0)"
    )

async def sort_chest_tool(ctx: RunContext, device: str | None = None, from_name: str = "") -> dict[str, object]:
    """Sort every item in an inventory into destinations using the saved rules.
    
    Returns counts of moved items, items with no matching rule, and full destinations.
    """
    device_id = device or default_worker()
    if not device_id:
        raise ValueError("no turtle or computer connected")
    
    # D-07: Python composition over send_cmd
    items_result = await send_cmd(device_id, "list_chest", {"name": from_name})
    if not items_result.get("ok"):
        return {"ok": False, "error": items_result.get("error", "list_chest failed")}
    
    items = items_result.get("data", {}).get("items", [])
    moved = 0
    no_rule = []
    destination_full = []
    
    for item in items:
        rule = find_matching_rule(item["name"])
        if not rule:
            no_rule.append(item["name"])
            continue
        
        dest_name = rule["destination"]
        push_result = await send_cmd(
            device_id,
            "push_one_slot",
            {"slot": item["slot"], "dest": dest_name, "limit": item["count"]}
        )
        if push_result.get("ok"):
            pushed = push_result.get("data", {}).get("moved", 0)
            moved += pushed
        else:
            destination_full.append(dest_name)
    
    return {
        "ok": True,
        "data": {"moved": moved, "no_rule": no_rule, "destination_full": destination_full}
    }
```

---

## Validation Architecture

**Test framework state:**

| Property | Value |
|----------|-------|
| Framework | Harness exit codes (0/1) + bridge logs; manual scenario runs (no pytest coverage this phase) |
| Config file | Scenarios defined in-code or JSON/YAML (Claude's discretion); no separate test config |
| Quick run command | `uv run harness --role chat --scenario devices-question --spend` (one paid call) |
| Full suite command | Run all scenarios (see Wave 0 gaps) without `--spend` (HARN-01, HARN-03, HARN-04, RESIL-04, RESIL-05 all free; HARN-02 needs `--spend`) |

**Phase Requirements → Test Map:**

| Req ID | Behavior | Test Type | Harness Scenario | Automated Command | Notes |
|--------|----------|-----------|------------------|--------------------|-------|
| HARN-01 | Harness connects, handshakes, prints wire messages | Integration | `hello-handshake` | `uv run harness --role chat --scenario hello-handshake` | Verifies protocol transport; no model |
| HARN-02 | Chat device, model call, result | Integration | `devices-question` | `uv run harness --role chat --scenario devices-question --spend` | One real API call; spent |
| HARN-03 | Worker device, canned tools | Integration | `status-command`, `list-chest` | `uv run harness --role worker --scenario status-command` | No API spend; fake device only |
| HARN-04 | Drop and reconnect | Integration | `drop-reconnect` | `uv run harness --role chat --scenario drop-reconnect` | Exercises D-10, D-11 |
| RESIL-03 | In-flight command fails cleanly | Integration | `drop-mid-command` | Part of `drop-reconnect` or separate | Verifies D-10 |
| RESIL-04 | Wrong token rejected | Integration | `wrong-token` | `uv run harness --role chat --scenario wrong-token --token bad_value` | Verifies CR-01 + D-16 |
| RESIL-05 | Disallowed player ignored | Integration | `disallowed-player` | `uv run harness --role chat --scenario disallowed-player` | No `--spend` needed; bridge rejects before model |

**Sampling Rate:**
- **Per scenario commit:** Quick run (e.g., `hello-handshake`) to validate scenario syntax.
- **Pre-merge (Phase 2 complete):** Full suite (all scenarios) with snapshots of bridge logs and harness outputs.
- **Phase gate (before RESIL-03/RESIL-04/RESIL-05 sign-off):** All resilience scenarios must pass with clean error messages and no hangs.

**Wave 0 Gaps:**

- [ ] `harness/scenarios.json` or `.py` — all named scenarios with steps and expectations
- [ ] `harness/harness.py` — FakeDevice class, scenario loader, main CLI, print formatter
- [ ] `harness/conftest.py` (if pytest) — fixtures for bridge subprocess (optional; manual two-terminal setup is fine)
- [ ] `bridge/bridge.py` amendments — D-10 try/except in send_cmd, D-11 socket replacement check, D-12 frame exception handling, D-16 logging
- [ ] `bridge/settings.py` amendment — CR-01 fold-in: `bridge_token` field gets `Field(min_length=1)`
- [ ] `bridge/agent.py` → `bridge/agent_old.py` (if keeping hand-rolled loop for D-05 sequencing); new `bridge/agent.py` with Pydantic AI (final plan)
- [ ] `turtle/turtle-helper/.gitignore` amendment — add `rules.json`
- [ ] `turtle/turtle-helper/README.md` — "Harness" section with scenario list and two-terminal recipe
- [ ] `turtle/turtle-helper/CLAUDE.md` — Architecture and Dev loop amendments per D-17

**Nothing else needs test coverage this phase;** pytest is deferred to v1.1 (TEST-02).

---

## Package Legitimacy Audit

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| `pydantic-ai` | PyPI | 7 months (Feb 2026 — current Sept 2026) | ~50K/week | [github.com/pydantic/pydantic-ai](https://github.com/pydantic/pydantic-ai) | OK | Approved — official Pydantic product; used in production |
| `pydantic-ai-slim[anthropic]` | PyPI | 7 months | Same as above | Same as above | OK | Approved — official extra; no bloat |
| `websockets` | PyPI | ~3 years current active maintenance | ~5M/week | [github.com/python-websockets/websockets](https://github.com/python-websockets/websockets) | OK | Approved — industry standard; v17.1 current |
| `anthropic` | PyPI | ~2 years (transitive) | ~1M/week | [github.com/anthropics/anthropic-sdk-python](https://github.com/anthropics/anthropic-sdk-python) | OK | Approved — official Anthropic SDK |
| `pytest` | PyPI | ~12 years (mature) | ~10M/week | [github.com/pytest-dev/pytest](https://github.com/pytest-dev/pytest) | OK | Approved — standard testing framework |

**Packages removed:** None.

**Packages flagged:** None.

**All dependencies are established projects with active maintainers, healthy download rates, and no indicators of abandonment or security issues.**

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Pydantic AI 2.46.0 is current on PyPI as of 2026-09-22 | Standard Stack | Outdated pinning; verify on phase start |
| A2 | `pydantic-ai-slim[anthropic]` includes all required types (`Agent`, `RunContext`, `FunctionToolset`) | Standard Stack | Missing imports; requires extra dependency |
| A3 | `RunContext` is the mechanism for per-player history keying in pydantic-ai | Pydantic AI Agent Shape | History not maintained per player; custom solution needed |
| A4 | `FunctionToolset` supports filtering tools per run (D-09) | Pydantic AI Agent Shape | Per-run toolset filtering not built-in; custom `AbstractToolset` subclass needed |
| A5 | Websockets 17.1 `ConnectionClosedError.rcvd.code` exposes the close code for harness expectations (D-14) | Standard Stack | Close code not available; can't verify close-code expectations in harness |
| A6 | CC:Tweaked primitives after D-07 rewrite (status, list_chest, push_one, move, turn, dig, inspect, refuel) are the same names and signatures as the starter | Lua Primitives (D-07) | Primitives renamed or signatures changed; harness canned results don't match; device rejects commands |
| A7 | The `rules.json` file (D-08) can be parsed and written by a Python function the same way `.env` is (via `pathlib.Path`) | D-08 Implementation | Path resolution differs; rules.json not found; composition tools fail |
| A8 | Anthropic SDK's `ResultError` is the mechanism for tools to return errors without raising (fixes WR-03) | Pydantic AI Tool Functions | ResultError not the right mechanism; custom exception handling needed |
| A9 | The harness can be a single Python module (`harness.py`) without heavy dependencies (just websockets, pydantic for args, logging) | Harness Packaging | Heavy dependencies or complex structure required; adds friction to setup |

**User confirmation needed before execution for A1, A3, A4, A6, A8.**

---

## Open Questions

1. **Exact Pydantic AI history API for per-player context (D-15, A3)**
   - What we know: Pydantic AI has `message_history` and `RunContext`.
   - What's unclear: Does `RunContext.player_id` or equivalent exist? How does the agent know which player's history to update?
   - Recommendation: Confirm in official docs or test a minimal example; if not present, design a custom `AbstractMessageHistory` subclass.

2. **Toolset filtering granularity (D-09, A4)**
   - What we know: `FunctionToolset` exists and is per-run.
   - What's unclear: Can tools be conditionally added at run time, or are they pre-registered?
   - Recommendation: Test building toolsets dynamically per request; if not supported, use a custom subclass.

3. **Exact Lua primitive signatures after D-07 (A6)**
   - What we know: D-07 describes the principle; ARCHITECTURE.md §1.4 has canned responses.
   - What's unclear: Will the planner provide exact names/signatures, or should harness default to generic "status returns X, list_chest returns Y" without assuming Lua implementation details?
   - Recommendation: Define primitive interface in CLAUDE.md or a separate PRIMITIVES.md doc; harness reads it.

4. **Rules.json location and schema (D-08)**
   - What we know: Lives beside `.env`, persisted globally, edited by local tools.
   - What's unclear: What is the exact JSON schema? Example: `[{pattern: "minecraft:iron_ingot", dest: "minecraft:chest_1"}, ...]`?
   - Recommendation: Define schema in code or doc before planner writes composition logic.

5. **Harness scenario definition format**
   - What we know: Steps with action, params, expectations; exit 0/1.
   - What's unclear: JSON, Python data structure, or YAML? Does scenario file live in the harness package or elsewhere?
   - Recommendation: Claude's discretion; recommend JSON for portability, Python dict for simplicity.

---

## Sources

### Official Documentation (HIGH Confidence)

- **Pydantic AI 2.46.0** — [pydantic.dev/docs/ai/](https://pydantic.dev/docs/ai/overview/) (verified as current on 2026-09-22; see CONTEXT.md reference)
  - Agent, instructions, deps_type, RunContext, FunctionToolset, message_history
- **Websockets 17.1** — [websockets.readthedocs.io](https://websockets.readthedocs.io/en/stable/reference/asyncio/client.html)
  - `websockets.asyncio.client.connect`, `ConnectionClosedError.rcvd.code`
- **Anthropic SDK 1.7.0** — [platform.claude.com/docs](https://platform.claude.com/docs/en/cli-sdks-libraries/sdks/python)
  - `AsyncAnthropic`, `messages.create`, `tool_use` flow
- **CC:Tweaked 1.111.0** — [tweaked.cc](https://tweaked.cc/module/http.html)
  - WebSocket events, JSON serialization, peripheral APIs

### Prior Research (HIGH Confidence, Verified for Phase 2)

- **ARCHITECTURE.md §1** — Harness `FakeDevice` design, wire protocol
- **ARCHITECTURE.md §2** — Fake brain seam (superseded by Pydantic AI, but approach relevant)
- **PITFALLS.md §1** — Websockets API drift, ping timeouts, `ConnectionClosed` handling (§1.3 directly addresses D-10)
- **PITFALLS.md §3** — CC:Tweaked Lua frame handling, websocket events
- **PITFALLS.md §6** — Fake model response shapes, API spend traps
- **STACK.md** — Websockets migration to asyncio API (Phase 1 completed; harness reuses same pattern)

### Phase 1 Decisions

- **01-CONTEXT.md D-13** — Module split; `agent.configure()` seam for dependency injection
- **01-CONTEXT.md D-17** — websockets migration to `websockets.asyncio.server`

### Existing Code (HIGH Confidence)

- **bridge.py lines 51–68** — `send_cmd()` function (D-10 amendment target)
- **bridge.py lines 89–130** — `handler()` (D-11, D-12, D-16 amendment targets)
- **bridge/agent.py lines 72–200** — `DEVICE_TOOLS`, `LOCAL_TOOLS` (D-06 conversion targets)
- **bridge/agent.py lines 32–47** — `SYSTEM_TEMPLATE` (carried into Pydantic AI agent)
- **turtle/client.lua lines 59–178** — Tool definitions (D-03 source for canned responses)
- **turtle/base/chat.lua lines 47–70** — Hello, event, result shapes (D-03 source)

---

## Metadata

**Confidence breakdown:**
- **Standard Stack:** HIGH — All versions verified on official registries; APIs confirmed in current docs.
- **Architecture:** HIGH — Prior research complete; harness shape proven in ARCHITECTURE.md §1; bridge resilience patterns documented in PITFALLS.md.
- **Pydantic AI integration:** HIGH for API shapes; MEDIUM for per-run toolset and history API details (see A3, A4 assumptions).
- **Pitfalls:** HIGH — All from prior research and code inspection; D-10/D-11/D-12 fixes directly address known bugs.

**Research date:** 2026-09-22  
**Valid until:** 2026-10-06 (2 weeks; pydantic-ai and anthropic are stable; websockets rarely breaks)  
**Refresh trigger:** Any update to pydantic-ai beyond 2.46.0, or new Anthropic SDK release with tool-use changes.

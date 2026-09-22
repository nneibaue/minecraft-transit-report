# Phase 2: Fake Device Harness & Protocol Resilience - Context

**Gathered:** 2026-09-22
**Status:** Ready for planning

<domain>
## Phase Boundary

A terminal-driven Python fake device (`uv run harness --role chat|worker --scenario <name>`) plays either device role against the running bridge, prints every wire message in both directions, and proves through named scenarios with expectation steps and exit codes: the hello handshake, the one paid devices-question call, canned worker answers, a drop while a command is in flight followed by a reconnect, a wrong token rejected, and a disallowed player ignored. The bridge-side changes those proofs demand land in the same phase: pending futures fail the moment their device drops, a same-id reconnect replaces the stale socket, malformed frames are logged and ignored, rejection log lines name the reason and the device, and the empty-token hole from the Phase 1 review closes.

The phase ends with the agent rewrite carried over from Phase 1: `bridge/agent.py` moves onto Pydantic AI with typed Python tool functions and a per-run toolset filtered to what connected devices advertise. By the author's decision, composition moves to Python at the same time: `turtle/client.lua` shrinks to CC:Tweaked primitives, `sort_chest` becomes a Python function over those primitives, and sorting rules persist on the bridge instead of the device. A short README "Harness" section and an updated CLAUDE.md dev-loop line and architecture note land now.

Not in Phase 2: any in-game run (Phase 4), server config and on-disk Lua placement (Phase 3), the pytest suite and fake brain (v1.1), over-the-wire Lua updates and agent-generated routines (deferred, see below), changes to `base/chat.lua`. Sorting stays a non-deliverable: the `sort_chest` composition is ported, not proven, because only a paid model call can trigger it and no success criterion covers it.

</domain>

<decisions>
## Implementation Decisions

### Harness driving model
- **D-01:** The harness is driven by scripted scenarios selected on the command line: `uv run harness --role chat|worker --scenario <name>`. Drop, wait and reconnect are scenario steps, not interactive commands. No REPL this phase.
- **D-02:** One fake device per process, two terminals. The devices-question scenario's documentation says to start the worker in the second terminal first. The bridge log is where the two sides interleave; the harness does not try to show both.
- **D-03:** The fake worker mirrors `client.lua`, not the bridge's tool list. `--role worker` sends hello with role `computer` and the caps `client.lua` exposes after D-07's rewrite (the primitive set). `status` returns a result shaped like `tools.status`; every other advertised primitive returns a small canned result; anything else returns the same `unknown tool <name>` error `client.lua` sends. A `--turtle` flag switches the role to `turtle` and adds the movement caps. `--role chat` sends role `chat` with caps `["say"]`, answers `say` commands with `{ok: true, data: {queued: true}}` like `chat.lua`, and emits scripted chat events carrying `user`, `text`, `uuid`, `hidden`.
- **D-04:** Every wire message prints as one line: timestamp, device id, a direction arrow, then the compact JSON exactly as it went over the wire. No pretty-print mode.

### Pydantic AI rewrite: order and shape
- **D-05:** Sequencing: the harness and the bridge resilience fixes (D-10 to D-13, D-16) are built first against today's hand-rolled loop. The `agent.py` swap is the final plan of the phase. The devices-question scenario runs once before and once after the swap, so the phase spends two paid calls and the second proves the swap changed nothing on the wire.
- **D-06:** Tools the model sees are typed Python functions with Pydantic argument models. The JSON `DEVICE_TOOLS` and `LOCAL_TOOLS` dicts in `agent.py` go away; schemas derive from the types. — **Reversibility:** costly — the tool contract moves from JSON beside the Lua into Python types, so going back means re-deriving every dict and reconnecting it to `client.lua`.
- **D-07:** Composition lives in Python; Lua exposes CC:Tweaked primitives one to one. The rule: anything with a loop or a policy lives in Python. `client.lua` loses `sort_chest`, `list_rules`, `add_rule`, `remove_rule`, `set_overflow`, `rules.json` and the `destFor` / `loadRules` / `saveRules` helpers. It keeps `status`, an inventory-listing primitive, a push-one-slot primitive wrapping `pushItems`, the turtle primitives (`move`, `turn`, `dig`, `inspect`, `refuel`), and `run_lua` behind `ALLOW_EVAL` untouched. `sort_chest` becomes a Python function that composes list and push over `send_cmd`; the model still sees one `sort_chest` tool and still gives one summary. The `readFile` / `writeFile` helpers and the `tools` dispatch table stay so a later push-script or load-routine primitive slots in without another rewrite. — **Reversibility:** costly — this amends the "high-level tools live in Lua" principle in `turtle/turtle-helper/CLAUDE.md` and the PROJECT.md constraints; the planner updates the Phase 2 entry in ROADMAP.md and the PROJECT.md constraint and key-decisions table. The workflow's scope caution was raised and the author reaffirmed: this is the author's decision. Exact primitive names and signatures are Claude's discretion (see below).
- **D-08:** Sorting rules persist on the bridge as a git-ignored `rules.json` beside `.env`, one global rule set, resolved from the source file's location the way `.env` is. `add_rule`, `remove_rule`, `list_rules` and `set_overflow` become local tools that edit that file. The device stores only `secret.txt` and its Lua. `rules.json` is added to `turtle/turtle-helper/.gitignore`.
- **D-09:** The toolset is built per run from the caps in the device registry at request time, plus the local tools. A Python composition is offered only when every primitive it needs is advertised by some connected device. With no turtle connected the model never sees `move` or `dig`, so the paid run cannot wander into a doomed call.

### Drop and reconnect rules
- **D-10:** An in-flight command fails the moment its device's socket closes. The bridge records which pending command ids belong to which device; the handler's cleanup resolves each of that device's pending futures with `{ok: false, error: "<id> disconnected"}`, and `send_cmd` also catches `ConnectionClosed` raised by the send itself. After the drop scenario, `pending` is empty and nothing waited for `CMD_TIMEOUT` (RESIL-03, Phase 1 D-15).
- **D-11:** A hello with an id already in the registry replaces the old entry. The bridge closes the stale socket and logs that it did. The old handler's `finally` removes the registry entry only if it still points at its own socket, so a replaced connection never deregisters its replacement. Closes review WR-01.
- **D-12:** Malformed frames are logged and ignored. Invalid JSON, non-object JSON, an unknown `type`, a `result` with a missing or unknown `cid`, a hello with no `id`: one WARNING line with the device id and the payload truncated to about 200 characters, and the connection stays open. The handler never raises out of its message loop. Closes review WR-02. A scenario sends one garbage frame and then completes a normal exchange to prove the device is still registered.
- **D-13:** Review fold-in: CR-01 (`bridge_token` gets `min_length=1`, and the wrong-token scenario gains an empty-token case, so the harness must be able to send a hello with an arbitrary token that overrides the settings value), WR-01 (D-11) and WR-02 (D-12) close in this phase. WR-03 (a tool exception leaves a dangling `tool_use`) is superseded by the Pydantic AI swap; the planner confirms the new loop returns a tool error to the model instead of raising. WR-04 and IN-01 through IN-04 stay open.

### Proof format and spend guard
- **D-14:** Scenarios carry expectation steps (a `say` command containing text, a close with a given code, a result with a given cid, a hello accepted meaning no close within N seconds) and every wait has a receive timeout. The process exits 0 on pass and 1 on fail with a one-line verdict; the wire log prints either way. Each Phase 2 success criterion maps to "run scenario X, exit 0", plus a bridge-log grep where the criterion names a log line.
- **D-15:** The devices-question scenario is the only scenario that emits a `$robot` event from an allowed player, and the harness refuses to send an allowed-player prefixed chat event unless `--spend` is on the command line. Two deliberate acts per paid run. The disallowed-player scenario needs no flag because the bridge ignores it before the model. The harness already imports `bridge.settings` (Phase 1 D-02), so it knows the prefix and the allowed players.
- **D-16:** The bridge's rejection logging distinguishes the reasons and names the device: separate lines for a bad token (with the id the hello claimed and the remote address), for no hello within 10 seconds, and for a stale same-id socket being replaced. The token value never appears in any log line. The existing `ignoring <user> (not allowed)` line stays and is what the RESIL-05 proof greps. The wrong-token scenario expects close code 4001 on its side.
- **D-17:** Documentation this phase: `turtle/turtle-helper/README.md` gains a "Harness" section listing each scenario, what it proves, the two-terminal recipe and `--spend`. `turtle/turtle-helper/CLAUDE.md` gets its "Dev loop" convention line changed to name the harness, its Architecture section amended with the thin-Lua rule (primitives in Lua, composition in Python) and rules-on-the-bridge, and its Protocol section kept accurate. "Current state" still says the Lua has not run; DOC-02 in Phase 5 changes that. Phase 5 extends rather than rewrites.

### Claude's Discretion
- Harness location and packaging: a `turtle/turtle-helper/harness/` package versus a single file, and a `[project.scripts]` entry so `uv run harness` works without the `sys.path` workaround `bridge.py` needed.
- Scenario definition format. No YAML dependency exists in the project; plain Python data or JSON avoids adding one.
- Exact Lua primitive names and signatures after the D-07 rewrite, and the canned result shapes, which must match the Lua exactly.
- The pending-future bookkeeping structure for D-10.
- How a typed tool targets a device when several are connected: a `device` parameter on each tool, toolset-level resolution, or the default-worker rule.
- Per-player history under Pydantic AI: `message_history` with trimming like today's `MAX_TURNS`, or history processors.
- The startup model check once `anthropic` is only a transitive dependency.
- Log wording, harness exit codes beyond 0 and 1, and whether the `sort_chest` composition batches pushes by destination.
- The style rules from Phase 1 D-16 apply to every new Python file: type hints on every function, `from __future__ import annotations`, ruff and mypy passing on `bridge/` and the harness.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/workstreams/turtle-helper/ROADMAP.md` — Phase 2 goal and the five success criteria; the planner adds the D-07 scope widening to this entry
- `.planning/workstreams/turtle-helper/REQUIREMENTS.md` — HARN-01 through HARN-04, RESIL-03 through RESIL-05; "Out of Scope" (sorting not a deliverable, `run_lua` off, pytest deferred); v2 TEST and CHORE lists
- `.planning/workstreams/turtle-helper/PROJECT.md` — Constraints ("pydantic-ai is added in Phase 2"; "adding a chore stays one Lua function plus one schema entry" is amended by D-06 and D-07) and Key Decisions (D-07 and D-08 need a row)

### Prior phase
- `.planning/workstreams/turtle-helper/phases/01-bridge-environment/01-CONTEXT.md` — D-01 and D-02 (Settings and the shared `.env` the harness reads), D-09 (one uv project covers the harness), D-13 (module split and the `agent.configure` seam), D-14 (Pydantic AI lands here), D-15 (`send_cmd` fix lands here), D-16 (style rules), and the Deferred Ideas entry sketching the Pydantic AI shape
- `.planning/workstreams/turtle-helper/phases/01-bridge-environment/01-REVIEW.md` — CR-01, WR-01, WR-02 close in this phase (D-13); WR-03 is superseded by the swap

### Research already done (verify, do not repeat)
- `.planning/workstreams/turtle-helper/research/ARCHITECTURE.md` §1 — harness design: `FakeDevice` class, scenario steps, the "speaks only the wire protocol, never imports `bridge.py`" principle. §1.4's canned result for every bridge tool is superseded by D-03 (mirror the Lua instead)
- `.planning/workstreams/turtle-helper/research/PITFALLS.md` §1 "ConnectionClosed not caught in send_cmd" (D-10); §6 "Fake harness and no-API-spend traps" and "Harness and bridge deadlock on command with no result" (receive timeouts, D-14)
- `.planning/workstreams/turtle-helper/research/STACK.md` — websockets 17 asyncio API

### Existing code
- `turtle/turtle-helper/bridge/bridge.py` — `send_cmd` (lines 51–68), `handler` (89–130), `on_event` (132–149), `main` (152–203); D-10 to D-12 and D-16 land here
- `turtle/turtle-helper/bridge/agent.py` — `DEVICE_TOOLS` (72–198) and `LOCAL_TOOLS` (200–223) are the schemas D-06 turns into typed functions; `SYSTEM_TEMPLATE` (32–47) carries over as the agent's instructions; `handle_request(user, text)` is the surface `bridge.py` keeps calling
- `turtle/turtle-helper/bridge/settings.py` — `Settings`; the harness imports it for host, port, token, prefix and allowed players; CR-01 fix lands here
- `turtle/turtle-helper/turtle/client.lua` — tools (59–178): what stays as primitives versus what D-07 moves to Python; session loop (188–214): the exact `result` shapes the fake worker mimics
- `turtle/turtle-helper/base/chat.lua` — hello shape (47–49), chat event shape (56–59), `say` result (64), unknown-command error (66); the fake chat device copies these; the file itself is not changed
- `turtle/turtle-helper/CLAUDE.md` — Architecture and Conventions sections amended by D-17
- `turtle/turtle-helper/README.md` — gains the "Harness" section (D-17)
- `turtle/turtle-helper/pyproject.toml`, `.env.example`, `.gitignore` — pydantic-ai dependency, `rules.json` ignore, any new env keys

### Style role model: the human-design project (WSL)
Read from a Windows session with `MSYS_NO_PATHCONV=1 wsl.exe -d ubuntu -- cat <path>`.
- `/home/nneibaue/code/human-design/.github/instructions/python.instructions.md` — Pydantic v2, enums, naming, type hints, path handling
- `/home/nneibaue/code/human-design/docs/engineering-standards.md` — "Pydantic-First Backend Modeling", "Python Style"
- `/home/nneibaue/code/human-design/pyproject.toml` — ruff and mypy configuration already mirrored in Phase 1

### Pydantic AI (researcher verifies against pydantic-ai 2.46)
- https://pydantic.dev/docs/ai/overview/ — `Agent`, `instructions`, `deps_type`, `RunContext`, `run`
- https://pydantic.dev/docs/ai/models/anthropic/ — `pydantic-ai-slim[anthropic]`, `AnthropicModel(provider=AnthropicProvider(anthropic_client=...))`
- https://pydantic.dev/docs/ai/tools/ — function tools with typed arguments (D-06)
- https://pydantic.dev/docs/ai/tools-toolsets/toolsets/ — `FunctionToolset`, per-run `toolsets=`, filtering (D-09)
- https://pydantic.dev/docs/ai/message-history/ — `message_history` for per-player memory

### CC:Tweaked and websockets (for D-07 primitives and the harness client)
- https://tweaked.cc/generic_peripheral/inventory.html — `list()`, `size()`, `pushItems(toName, fromSlot, limit, toSlot)` behind the push-one-slot primitive
- https://tweaked.cc/module/textutils.html — `serialiseJSON`, `empty_json_array`
- https://websockets.readthedocs.io/en/stable/reference/asyncio/client.html — `websockets.asyncio.client.connect`, `ConnectionClosedError.rcvd.code` for the close-code expectation

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bridge.py` `handler`, `send_cmd`, `on_event`: the resilience work (D-10 to D-12, D-16) edits these in place; `on_event`'s per-request exception catch and its `ignoring <user> (not allowed)` line stay as they are.
- `agent.py` `SYSTEM_TEMPLATE` and each `DEVICE_TOOLS` description: carried into the Pydantic AI agent as instructions and tool docstrings.
- `client.lua` `tools.status`, `tools.list_chest`, the turtle tools and the `session` loop: the primitive set D-07 keeps; `sort_chest`'s loop (lines 86–103) is the reference for the Python composition.
- `chat.lua` lines 47–70: the exact hello, chat event and `say` result shapes the fake chat device reproduces.
- `settings.Settings`: the harness's source of host, port, token, prefix and allowed players; also where `min_length=1` lands for CR-01.
- `research/ARCHITECTURE.md` §1.2: a `FakeDevice` sketch with `connect`, `send_event`, `handle_cmd`, `run_scenario` that matches D-01 to D-03.

### Established Patterns
- Async everything: `asyncio` plus `websockets` plus the async Anthropic client; no threads. The harness follows suit with `websockets.asyncio.client`.
- Config is env-only through `Settings`; the harness adds command-line flags for role, scenario, `--spend`, `--turtle`, and a token override for the wrong-token case, nothing else.
- One websocket per device, JSON messages `hello {type,id,token,role,caps}`, `event {type,name,user,text,uuid,hidden}`, `cmd {type,cid,tool,args}`, `result {type,cid,ok,data|error}`. Phase 2 does not change these shapes; the Lua rewrite only changes which tool names appear in `caps`.
- Both Lua files answer an application-level `{type: "ping"}` the bridge never sends; harmless, leave it.
- Imports have no side effects (Phase 1 D-13); the harness module must keep that property so `--help` works with no `.env`.

### Integration Points
- The harness connects to `ws://{settings.host}:{settings.port}` and imports `bridge.settings` only, never `bridge.bridge` or `bridge.agent`.
- `bridge.py` keeps calling `agent.handle_request(user, request)`; the Pydantic AI agent lives behind that surface so the swap touches `bridge.py` only where `agent.configure` is replaced by agent construction in `main`.
- The per-run toolset (D-09) reads the same `devices` registry `list_devices` and `default_worker` already use.
- `rules.json` (D-08) resolves beside `.env` using the same `Path(__file__)` pattern `settings.py` uses.
- README "Setup > 1. Bridge" from Phase 1 is where the "Harness" section follows.

### Gotchas surfaced during discussion
- `Settings()` requires `ANTHROPIC_API_KEY`, `BRIDGE_TOKEN` and `ALLOWED_PLAYERS`; the harness inherits that by importing it. Acceptable because it shares `.env`, but `--help` must not construct `Settings`.
- `handler` today does `hello["id"]`, which raises on a hello with no id; D-12 covers it.
- `send_cmd` looks up `dev["ws"]` once and sends; a same-id replacement (D-11) means a command issued to the old socket must fail through D-10, not be silently sent to the new one.
- `bridge.py` needs a `sys.path.insert` hack to run as a script; a `[project.scripts]` entry for the harness avoids repeating it.
- In PowerShell `$robot` is a variable reference; scenario text and README examples quote it in single quotes.
- No Lua runtime exists on this PC or in WSL. The rewritten `client.lua` is parsed with `luaparse` (npm) in the scratchpad before it is committed.
- Bash tool commands over roughly 8 KB fail to parse here; large files are written with the file tool.
- pytest is not a dependency (v1.1); the harness's exit-code scenarios are the test surface this phase.

</code_context>

<specifics>
## Specific Ideas

- "Keep the Lua side as thin as possible because it is more difficult to maintain than Python": the rule adopted in D-07, with the real driver being testability, since Lua only runs in the game while Python runs against the harness.
- "Let's do them both now": typed tool functions and the composition move happen together in this phase, not one after the other.
- "Throw fable at it": the author does not want the work scaled down for effort's sake, and asked for the strongest available model on this phase's execution. If the GSD model profile allows a per-phase override, the planner notes it.
- "The agents in Python may return Lua with loops ... there will have to be some form of client-side updates because the bridge is version controlled": captured as two deferred capabilities below, with the D-07 constraint that the Lua keeps its dispatch table and file helpers.
- Two terminals, worker first, is the documented recipe for the devices question.

</specifics>

<deferred>
## Deferred Ideas

- **Over-the-wire Lua updates.** The bridge pushes script updates to devices, since only the bridge is version controlled and running somewhere. New capability, own phase. Phase 2's only obligation: the primitive rewrite keeps the `tools` dispatch table and the `readFile` / `writeFile` helpers so a push-script primitive slots in later.
- **Agent-generated routines.** Python agents return Lua with loops so a turtle can grow its own skills (a Voyager-style skill library). This is the `run_lua` / `ALLOW_EVAL` knob v1.0 keeps off; `run_lua` stays behind the flag untouched in this phase.
- **Multi-role harness process and a REPL mode.** Both considered and set aside; either could return as a Phase 4 debugging aid.
- **A run-all-scenarios command.** Set aside as the pytest-shaped thing v1.1 TEST-02 already owns.
- **Per-device rule sets.** One global rule set is enough for one worker; revisit when a second worker on a different wired network exists.
- **Review items WR-04 and IN-01 through IN-04.** Left open; none has a harness proof.
- **CHORE-01 first chore.** Where thin-Lua gets applied to a chore that is actually proven in game (v2).

No todos were reviewed; none matched this phase.

</deferred>

---

*Phase: 02-fake-device-harness-protocol-resilience*
*Context gathered: 2026-09-22*

---
phase: 02-fake-device-harness-protocol-resilience
plan: 05
subsystem: agent
tags: [pydantic-ai, anthropic, typed-tools, FunctionToolset, message_history, D-06, D-09, WR-03]

# Dependency graph
requires:
  - phase: 01-bridge-environment
    provides: the bridge/settings/agent module split and the agent.configure(settings, client, devices, send_cmd, say, default_worker) seam bridge.main() calls once
  - phase: 02-fake-device-harness-protocol-resilience (02-01)
    provides: the post-D-07 client.lua primitive set and signatures the typed tools mirror (push_one_slot takes from/slot/dest/limit)
  - phase: 02-fake-device-harness-protocol-resilience (02-02)
    provides: send_cmd that never raises and always returns a dict, which every device tool returns unchanged
  - phase: 02-fake-device-harness-protocol-resilience (02-04)
    provides: the pre-swap transcript and the observation that the model's say call carried to:null
provides:
  - "bridge/agent.py on pydantic-ai-slim[anthropic] 2.46.0: eight typed device-forwarding tools (status, list_chest, push_one_slot, move, turn, dig, inspect, refuel), each with its own Pydantic argument model, validated by pydantic-ai before the body runs"
  - "list_devices and say as always-available local tools; SayArgs keeps text required and to optional"
  - "build_toolset() -> FunctionToolset[None]: per-run D-09 filtering, a device primitive is offered only when some connected device advertises it in caps"
  - "Module-level agent: Agent[None, str] built once inside configure() on AnthropicModel(settings.model, provider=AnthropicProvider(anthropic_client=<bridge.py's client>)) with instructions=system and no tools of its own"
  - "handle_request(user, text) on agent.run(message_history=histories[user], toolsets=[build_toolset()], usage_limits=UsageLimits(request_limit=12)); histories: dict[str, list[ModelMessage]] replaced only after a successful run and trimmed on turn boundaries (HISTORY_LIMIT=40)"
  - "tests/test_agent.py: 23 zero-spend TAP tests driving the tools, toolset and handle_request through pydantic-ai's FunctionModel"
affects: [02-06 composition tools (sort_chest, rules) layered on build_toolset, 02-07 post-swap paid devices-question run and transcript comparison, 02 code review, 04 in-game round trip]

# Actuals (#2632) - estimateTokens scale (chars/4 over the realized diff), not a harness token count.
actuals:
  tokens: 13300
  tasks: 3
  commits: 7
plan_head_before: 53d57ebed0754eb69fb5b772713dabe204909bfb

# Tech tracking
tech-stack:
  added:
    - "pydantic-ai-slim[anthropic]==2.46.0 (direct; pulls pydantic-graph 2.46.0, genai-prices, griffelib, logfire-api, opentelemetry-api); anthropic 1.7.0 stays a direct dependency"
  patterns:
    - "Typed tool = one BaseModel argument class (DeviceArgs subclass) + one async def taking (ctx: RunContext[None], args: <Model>); pydantic-ai uses the function name as the tool name, the docstring as the description and the model's schema as the tool schema"
    - "Device tools never raise: _forward resolves args.device or default_worker(), returns {ok: False, error: 'no turtle or computer connected'} when nothing is connected, otherwise returns send_cmd's dict unchanged; wire dicts omit unset optionals (exclude_none) so the Lua side sees nil"
    - "Per-run toolset: build_toolset() is called inside handle_request for every request and handed to agent.run(toolsets=[...]); nothing is registered on the Agent itself"
    - "Zero-spend agent tests: Script(FunctionModel) plays the model and records info.function_tools per call, Recorder fakes the injected callables, agent.override(model=...) swaps the model under handle_request"

key-files:
  created:
    - turtle/turtle-helper/tests/test_agent.py
  modified:
    - turtle/turtle-helper/bridge/agent.py
    - turtle/turtle-helper/pyproject.toml
    - turtle/turtle-helper/uv.lock
    - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/deferred-items.md

key-decisions:
  - "SayArgs.to stays str | None = None (null accepted, meaning broadcast): the 02-04 pre-swap say cmd carried to:null and 02-07 compares the post-swap wire like-for-like, so defaulting to a whisper would have introduced a wire difference; the prompt still opens with [<player>] so the model can whisper by name"
  - "The injected bridge.say() callable is held as agent.say_in_chat so the model-facing tool can be a real module-level function named say like the other nine tools; configure()'s parameter order and signature are unchanged"
  - "History trimming drops whole oldest turns (cut only at a ModelRequest carrying a UserPromptPart) to HISTORY_LIMIT=40 messages rather than using a history processor; a single turn is bounded by UsageLimits(request_limit=12) so it can never exceed the cap on its own"
  - "UsageLimits(request_limit=12) carries over the old loop's 12-round cap per request as a spend guard; exceeding it raises UsageLimitExceeded into bridge.on_event's existing catch-all"
  - "The dependency bump is its own chore(02-05) commit ahead of the first RED test so pyproject.toml and uv.lock land together and the test/feat commits stay test-only/code-only"
  - "Task 1 left handle_request as a NotImplementedError stub between the feat commits because its acceptance criteria forbid any DEVICE_TOOLS/run_tool remnant while Task 3 owns the rebuild; the plan is one swap from bridge.py's point of view and the bridge was never started mid-plan"

patterns-established:
  - "RESEARCH.md is a pointer, not an authority: every pydantic-ai symbol was verified against the installed 2.46.0 source before use (its ResultError and RunContext-history claims do not exist; ModelRetry/RetryPromptPart and message_history= do)"
  - "RED evidence is persisted per task and classified with gsd check tdd-red-evidence before any GREEN edit"

requirements-completed: [HARN-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Eight typed device-forwarding tools with Pydantic argument models; a malformed call (list_chest without name) is rejected by pydantic-ai as a RetryPromptPart before the tool body runs, and every tool returns send_cmd's dict without raising"
    requirement: HARN-02
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_list_chest_without_name_is_rejected_before_the_tool_runs"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_device_tool_returns_send_cmd_result_without_raising"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_push_one_slot_wire_args_match_client_lua"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_every_primitive_is_a_typed_tool_with_the_lua_signature"
        status: pass
    human_judgment: false
  - id: D2
    description: "build_toolset() implements D-09: only list_devices/say with no devices, exactly a computer's advertised primitives, all eight for a turtle, unknown caps ignored, rebuilt from the live registry on every call"
    requirement: HARN-02
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_toolset_with_no_devices_has_only_local_tools"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_toolset_with_computer_worker_adds_only_its_caps"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_toolset_is_rebuilt_from_the_live_registry_each_call"
        status: pass
      - kind: other
        ref: "plan verify snippet: uv run python - (build_toolset with devices={}) -> TOOLSET_EMPTY_OK"
        status: pass
    human_judgment: false
  - id: D3
    description: "Agent built once inside configure() on bridge.py's own AsyncAnthropic client with the formatted SYSTEM_TEMPLATE as instructions and no tools of its own; the model sees exactly the per-run toolset"
    requirement: HARN-02
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_configure_builds_the_agent_on_the_injected_anthropic_client"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_agent_has_no_tools_of_its_own_and_uses_system_as_instructions"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_handle_request_runs_the_model_with_the_per_run_toolset"
        status: pass
    human_judgment: false
  - id: D4
    description: "handle_request(user, text) keeps the Phase 1 signature, keeps per-player message_history isolated, leaves history untouched when the run fails, trims only on turn boundaries and cuts off a runaway tool loop"
    requirement: HARN-02
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_handle_request_keeps_the_phase_1_signature"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_handle_request_keeps_history_per_player"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_failed_run_raises_and_leaves_that_players_history_untouched"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_history_is_bounded_and_trimmed_on_turn_boundaries"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_runaway_tool_loop_is_cut_off_and_history_untouched"
        status: pass
    human_judgment: false
  - id: D5
    description: "bridge.py untouched, configure() signature preserved, pydantic-ai-slim[anthropic]==2.46.0 pinned in pyproject.toml and uv.lock, ruff/ruff format/mypy clean on bridge/, harness/ and the new tests"
    verification:
      - kind: other
        ref: "git diff --quiet 53d57eb -- turtle/turtle-helper/bridge/bridge.py -> UNCHANGED"
        status: pass
      - kind: other
        ref: "cd turtle/turtle-helper && uv run ruff check bridge/ harness/ tests/test_agent.py && uv run ruff format --check bridge/agent.py tests/test_agent.py && uv run mypy bridge/ harness/ tests/test_agent.py"
        status: pass
      - kind: other
        ref: "grep -q 'pydantic-ai-slim\\[anthropic\\]==2.46.0' turtle/turtle-helper/pyproject.toml && grep -q 'pydantic-ai' turtle/turtle-helper/uv.lock"
        status: pass
    human_judgment: false
  - id: D6
    description: "The swap changes nothing on the wire for the devices question (say cmd shape, to:null semantics, one say per task) - only the 02-07 paid post-swap run can show this"
    requirement: HARN-02
    verification: []
    human_judgment: true
    rationale: "Wire-level parity against a real model needs the second paid devices-question run, which belongs to plan 02-07 by D-05; nothing in this plan makes a model call"

# Metrics
duration: 19 min
completed: 2026-09-25
status: complete
---

# Phase 02 Plan 05: Agent core on pydantic-ai (typed tools, per-run toolset, Agent construction) Summary

**bridge/agent.py now runs on pydantic-ai 2.46.0: eight typed device-forwarding tools plus list_devices/say, a per-run toolset filtered by live device caps (D-09), an Agent built once inside configure() on bridge.py's own Anthropic client, and handle_request on agent.run() with per-player message_history - with bridge.py untouched and 23 zero-spend tests proving it.**

## Performance

- **Duration:** 19 min
- **Started:** 2026-09-25T04:19:14Z
- **Completed:** 2026-09-25T04:38:00Z
- **Tasks:** 3 (all tdd="true", RED -> GREEN each; REFACTOR not needed)
- **Files modified:** 4 code files (agent.py, pyproject.toml, uv.lock, tests/test_agent.py) + deferred-items.md

## Accomplishments

- D-06 landed: the hand-rolled `DEVICE_TOOLS`/`LOCAL_TOOLS` JSON dicts and the `run_tool` dispatcher are gone. Each client.lua primitive is a typed `async def` taking `(ctx: RunContext[None], args: <PydanticModel>)`; pydantic-ai derives the schema from the model and the description from the docstring (the old description strings are carried over verbatim), and validates the model's arguments before the body runs. A `list_chest` call without `name` comes back to the model as a `RetryPromptPart` and never reaches a device.
- D-09 landed: `build_toolset()` seeds a fresh `FunctionToolset` with `list_devices`/`say` and adds a device primitive only when some connected device advertises it in `caps`. With nothing connected the model sees two tools; with a plain computer it sees `status`/`list_chest`/`push_one_slot` and never `move`/`dig`; with a turtle it sees all eight. `handle_request` calls it on every request, so the set follows connects and disconnects.
- The Agent is constructed once in `configure()` as `Agent(AnthropicModel(settings.model, provider=AnthropicProvider(anthropic_client=new_client)), instructions=system)` - the same client `bridge.main()` already verified the model against, no second client, no tools registered on the Agent itself.
- `handle_request(user, text)` keeps its Phase 1 signature. It runs `agent.run(f"[{user}] {text}", message_history=histories.get(user, []), toolsets=[build_toolset()], usage_limits=UsageLimits(request_limit=12))` and stores `trim_history(result.all_messages())` only after the run returns. A failure anywhere inside the run propagates to `bridge.on_event`'s catch-all and leaves that player's history exactly as it was (closes WR-03 structurally). Trimming drops whole oldest turns to 40 messages, never splitting a tool_use from its tool_result.
- Wire compatibility with 02-01's Lua: `push_one_slot` maps `from_name` -> `from`; unset optionals (`steps`, `limit`, `count`) are omitted from the wire dict; `dig` defaults `dir` to `forward`. The device tool result dict is returned to the model unchanged.
- 23 zero-spend tests in `tests/test_agent.py` (same dependency-free TAP shape as 02-02's script; `uv run python tests/test_agent.py`). pydantic-ai's `FunctionModel` plays the model and records `info.function_tools` per call, so D-09 is asserted at the model boundary, not just on the toolset object.

## Task Commits

TDD cycle per task (RED evidence classified `RED_EVIDENCE_OK` by `gsd check tdd-red-evidence` before each GREEN):

0. **Dependency** - `1bf4813` (chore) - `pydantic-ai-slim[anthropic]==2.46.0` in pyproject.toml + uv.lock
1. **Task 1: typed device-forwarding tools** - RED `99eb5cc` (test, 7 failing on target `test_list_chest_without_name_is_rejected_before_the_tool_runs`) -> GREEN `a59d6d8` (feat, 7/7)
2. **Task 2: local tools, Agent construction, per-run toolset** - RED `b5c32b7` (test, target `test_toolset_with_no_devices_has_only_local_tools`) -> GREEN `932c453` (feat, 17/17)
3. **Task 3: handle_request on agent.run, per-player history** - RED `11ef4d4` (test, target `test_handle_request_keeps_history_per_player`) -> GREEN `c44fa82` (feat, 23/23)

REFACTOR: no commit for any task - the GREEN implementations already share `_forward`, and a final read-through found nothing worth a behaviour-neutral change.

**Plan metadata:** see the docs commit that adds this file.

## Files Created/Modified

- `turtle/turtle-helper/bridge/agent.py` - rewritten (316 lines): injected globals (`say` renamed `say_in_chat`, new `agent`), unchanged `SYSTEM_TEMPLATE`, `configure()` now builds the Agent, `DeviceArgs` + 8 argument models, `_forward`, 8 device tools, `list_devices`/`SayArgs`/`say`, `DEVICE_PRIMITIVES`, `build_toolset()`, `histories`/`HISTORY_LIMIT`/`REQUEST_LIMITS`, `trim_history`, `handle_request`
- `turtle/turtle-helper/tests/test_agent.py` - new, 23 TAP tests (Recorder fakes, Script/FunctionModel, per-task sections)
- `turtle/turtle-helper/pyproject.toml` - one dependency line added; `[project.scripts] harness` and hatch `packages = ["bridge", "harness"]` preserved
- `turtle/turtle-helper/uv.lock` - resolved alongside
- `.planning/.../deferred-items.md` - 02-04's `say to:null` item resolved with this plan's decision; two new 02-05 items (see Deferred)

`bridge/bridge.py` is byte-identical to `53d57eb` (`git diff --quiet` confirms).

## Decisions Made

- **`SayArgs.to` stays optional (`str | None = None`, null = broadcast).** 02-04 asked for "required, or default to the requesting player". The pre-swap say cmd carried `to: null` and D-05's whole point for 02-07 is a like-for-like wire comparison, so changing the default would have manufactured a difference. The prompt still opens with `[<player>]`, so the model can whisper by name when it chooses. Recorded in deferred-items.md; revisit after 02-07 if the broadcast is unwanted.
- **`say_in_chat` for the injected callable.** The plan's tool named `say` and the injected global named `say` collided; keeping the model-facing tool as a real module-level function `say` (discoverable like the other nine) won, and the bridge callable moved to `say_in_chat`. `configure(settings, client, devices, send_cmd, say, default_worker)` is unchanged.
- **Trim by whole turns, not a history processor.** `trim_history` keeps at most 40 messages and cuts only at a `ModelRequest` carrying a `UserPromptPart`; a turn is bounded by `request_limit=12` (at most 24 messages) so it can never exceed the cap alone. Simpler to test than a processor and it keeps `histories` a plain dict bridge.py-side code can inspect.
- **`UsageLimits(request_limit=12)`** carries over the old loop's `for _ in range(12)` as the per-request spend guard.
- **Dependency as a separate `chore(02-05)` commit** before the first RED, so `test(...)` and `feat(...)` commits stay test-only/code-only and pyproject.toml/uv.lock land together.
- **Prompt format `[user] text` kept** from the old loop (the model needs to know who is asking; this is what the pre-swap run sent).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing logging] Per-tool log line carried over from the old loop**
- **Found during:** Task 3 (handle_request)
- **Issue:** The old loop logged `tool name(args) -> result` for every call; pydantic-ai logs nothing through stdlib logging, so 02-07's bridge-log reading would have lost tool diagnostics. The plan text did not mention logging.
- **Fix:** `_forward` logs `tool <name>@<device>(<wire>) -> <result[:200]>` at INFO after `send_cmd` returns.
- **Files modified:** turtle/turtle-helper/bridge/agent.py
- **Verification:** ruff/mypy clean; tests unaffected (the TAP runner leaves the bridge logger at default level)
- **Committed in:** c44fa82

**2. [Rule 3 - Blocking] Interim `handle_request` stub between Task 1 and Task 3**
- **Found during:** Task 1
- **Issue:** Task 1's acceptance criteria forbid any `DEVICE_TOOLS`/`run_tool` identifier, but the old `handle_request` depended on both and Task 3 owns its rebuild. Deleting them made the old loop uncompilable.
- **Fix:** Task 1 GREEN shipped `handle_request` as a `NotImplementedError` stub with the Phase 1 signature; Task 3 GREEN replaced it. The bridge was never started mid-plan (per the dispatch's instructions), and `configure()` kept working throughout.
- **Files modified:** turtle/turtle-helper/bridge/agent.py
- **Committed in:** a59d6d8 (stub), c44fa82 (rebuild)

---

**Total deviations:** 2 auto-fixed (1 missing logging, 1 blocking intermediate state)
**Impact on plan:** No scope change. The plan's must_haves (bridge.py untouched, configure signature, per-run toolset from the live registry, tools returning send_cmd's dict) all hold.

## Issues Encountered

- **RESEARCH.md mis-stated the pydantic-ai API**, as the dispatch warned: there is no `ResultError` (tool errors are `ModelRetry`; argument validation failures become `RetryPromptPart` inside `_agent_graph.py`), `RunContext` is not a history mechanism (`message_history=` on `agent.run` is), and per-run `toolsets=` is supported. Everything used was verified against the installed 2.46.0 source and a scratchpad prototype before the RED tests were written. `AgentInfo.function_tools`, `FunctionToolset.tools`, `Agent.override(model=)`, `AnthropicModel.client`, `UsageLimits.request_limit` all confirmed.
- **Two test-helper bugs surfaced in Task 2 GREEN** (fixed in the same feat commit `932c453`): the `configure()` helper's `devices or {}` swapped an empty dict for a fresh one so the live-registry test could not mutate the real registry; and pydantic-ai strips surrounding whitespace from instructions, so the comparison is against `a.system.strip()`.
- **RED-chain lint stops before Task 3's run**: ruff N818 (test exception needed an `Error` suffix -> `ModelBlewUpError`) and a mypy inference on a mixed list literal (`list[list[ToolCallPart] | str]` annotation added). Neither touched production code.
- In Task 2 RED, `test_say_without_text_is_rejected_before_it_speaks` already passed because pydantic-ai happily wrapped the injected fake `say` callable as a tool and rejected the missing `text`; not the target test, and it is meaningful now that `say` is the real tool.
- WSL style role model (`human-design` CLAUDE.md, engineering-standards.md, python.instructions.md) was readable and followed: `from __future__ import annotations`, typed public functions, Pydantic v2 models at the boundary, ruff + mypy strict, line length 100, semantic names (`DeviceArgs`, `trim_history`, `say_in_chat`).

## TDD Gate Compliance

| Task | RED commit | GREEN commit | REFACTOR | RED evidence |
|------|------------|--------------|----------|--------------|
| 1 | 99eb5cc `test(02-05)` | a59d6d8 `feat(02-05)` | none needed | RED_EVIDENCE_OK (7 fail / exit 1) |
| 2 | b5c32b7 `test(02-05)` | 932c453 `feat(02-05)` | none needed | RED_EVIDENCE_OK (9 fail / exit 1) |
| 3 | 11ef4d4 `test(02-05)` | c44fa82 `feat(02-05)` | none needed | RED_EVIDENCE_OK (5 fail / exit 1) |

Every RED preceded its GREEN in `git log`; the dependency bump is a `chore(02-05)` commit ahead of the first RED.

## Verification

Plan-level `<verification>` re-run after the last commit:

- `cd turtle/turtle-helper && uv run ruff check bridge/ && uv run mypy bridge/` -> clean (also clean for `harness/` and `tests/test_agent.py`; `ruff format --check bridge/agent.py tests/test_agent.py` -> already formatted)
- `build_toolset()` with `devices = {}` -> `TOOLSET_EMPTY_OK` (plan's own verify snippet)
- `grep -q 'async def handle_request(user: str, text: str) -> None' bridge/agent.py` -> PASS
- `uv run python tests/test_agent.py` -> 23/23; `uv run python tests/test_bridge_resilience.py` -> 11/11 still green
- `git diff --quiet 53d57eb -- turtle/turtle-helper/bridge/bridge.py` -> unchanged

## Known Stubs

None. No placeholder values, skipped tests or unrun verifies. The Task 1 interim `handle_request` stub existed only between commits `a59d6d8` and `c44fa82` and is gone.

## Threat Flags

None new. The one new surface (the `pydantic-ai-slim[anthropic]` dependency, T-02-05a) is in the plan's threat register and was installed at the exact audited pin; T-02-05b (bounded histories) is enforced by `trim_history` + `request_limit`, T-02-05c (tools the model must not see) by `build_toolset()` and proven at the model boundary by `test_handle_request_runs_the_model_with_the_per_run_toolset`.

## Deferred (out of scope here, logged in deferred-items.md)

- Pre-existing mypy error at `tests/test_bridge_resilience.py:112` (ignore code needs `assignment` too) - not caused by this plan; for 02-06's cleanup pass with the bridge.py formatting debt.
- pydantic-ai prints a one-time observability banner to stderr on the first `agent.run` when Logfire is unconfigured; set `PYDANTIC_AI_NO_BANNER=1` (bridge.py or `.env.example`) before 02-07 reads the bridge log. The tests set it themselves.
- 02-02's item about `asyncio.create_task(on_event(...))` holding no reference lives in bridge.py, which this plan may not touch; its natural home is now 02-06.

## User Setup Required

None - no external service configuration required. No `.env` change; `ANTHROPIC_API_KEY`/`BRIDGE_TOKEN` were never read.

## Next Phase Readiness

- **02-06 (composition tools):** add `sort_chest` and the rule tools as more typed functions; gate a composition in `build_toolset()` on *all* of its primitives being in `advertised` (e.g. `sort_chest` needs `list_chest` and `push_one_slot`), and compose over the injected `send_cmd` exactly as `_forward` does. `DEVICE_PRIMITIVES` is the place to extend for device tools; local/composed tools join the `FunctionToolset([...])` seed. Remember `SYSTEM_TEMPLATE` already tells the model to prefer `sort_chest`.
- **02-07 (post-swap paid run):** what the wire should show unchanged - one `say` cmd `{text, to, prefix}` from bridge.say(), `to` null when the model omits it, the request prompt `[Nate] what devices are connected?`. New failure surfaces that reach `on_event`'s "Sorry <user>, something went wrong: <ExceptionName>" path: `UsageLimitExceeded` (12 model rounds) and `UnexpectedModelBehavior` (a tool's argument validation failed twice). Consider the banner env var before capturing the bridge log.
- Tests for the whole Python side: `uv run python tests/test_bridge_resilience.py` (11) and `uv run python tests/test_agent.py` (23), both zero-spend.

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-25*

## Self-Check: PASSED

- 3 key files present; 7 plan commits found in git log; commits measured from plan_head_before 53d57eb = 7; no uncommitted code under turtle/turtle-helper.

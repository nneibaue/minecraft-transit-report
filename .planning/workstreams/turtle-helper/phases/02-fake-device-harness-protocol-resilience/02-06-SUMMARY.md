---
phase: 02-fake-device-harness-protocol-resilience
plan: 06
subsystem: agent
tags: [pydantic-ai, sort_chest, rules.json, lua-patterns, composition, D-07, D-08, D-09, tdd, tap, ruff, mypy]

# Dependency graph
requires:
  - phase: 02-fake-device-harness-protocol-resilience
    provides: "02-05: agent.py on pydantic-ai 2.46.0 with typed device tools, build_toolset() from live caps, handle_request on agent.run, tests/test_agent.py fakes (Recorder, Script, FunctionModel); 02-01: client.lua's list_chest/push_one_slot primitives and the removed on-device sort loop's return shape; 02-02: send_cmd never raises, tests/test_bridge_resilience.py FakeWs"
  - phase: 01-bridge-environment
    provides: "settings.py's Path(__file__).resolve().parent.parent / '.env' pattern that rules_path mirrors; the anthropic client bridge.py verifies the model with at boot"
provides:
  - "bridge/agent.py: rules_path beside .env, SortRule/RuleBook models, load_rulebook()/save_rulebook() (atomic temp-file replace), load_rules() JSON view; list_rules/add_rule/remove_rule/set_overflow local tools always in the toolset (D-08)"
  - "bridge/agent.py: sort_chest(SortChestArgs) composing list_chest then one push_one_slot per matched item over send_cmd, returning {moved, no_rule, destination_full}; ChestListing/PushResult validate device data; SortOutcome carries partial progress on failure (D-07)"
  - "bridge/agent.py: COMPOSITIONS table; a composition is offered only when ONE connected device advertises every primitive it needs (D-09)"
  - "bridge/lua_pattern.py: Lua string.find semantics for rule patterns by translation to re (classes, sets, lazy '-', anchors); %b/%f/back-references and malformed patterns raise LuaPatternError, which add_rule turns into a ModelRetry"
  - "turtle/turtle-helper/.gitignore ignores rules.json; bridge.py holds event tasks in background_tasks; pydantic-ai's first-run banner is off; ruff/format/mypy clean across bridge/ harness/ tests/"
  - "tests/test_agent_composition.py: 16 zero-spend TAP tests; tests/test_bridge_resilience.py now 12"
affects: [02-07 CLAUDE.md thin-Lua and rules-on-the-bridge amendments and post-swap paid run, 02 code review, 04 in-game round trip, CHORE-01 first proven chore]

# Actuals (#2632) - estimateTokens scale (chars/4 over the realized diff), not a harness token count.
actuals:
  tokens: 12775
  tasks: 3
  commits: 7
plan_head_before: a8ab694ddcee53bd806a600467c213999912ece3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Bridge-side state files resolve from the source file's location (Path(__file__).resolve().parent.parent), never the cwd, and are written whole through a sibling .tmp then Path.replace()"
    - "Device data crossing into a composition is validated at the boundary with a small Pydantic model (ChestListing, PushResult); an invalid frame becomes an {ok: False, error} result, never an exception"
    - "A composition returns partial progress with its error (SortOutcome.failed) so the model can summarise honestly after a failed step"
    - "Tool argument validation that Pydantic cannot express (a Lua pattern that must compile) raises ModelRetry inside the tool so the model gets a retry prompt and nothing is persisted"
    - "Compositions are gated per device: COMPOSITIONS maps each to the primitive set one connected device must advertise in full"

key-files:
  created:
    - turtle/turtle-helper/bridge/lua_pattern.py
    - turtle/turtle-helper/tests/test_agent_composition.py
  modified:
    - turtle/turtle-helper/bridge/agent.py
    - turtle/turtle-helper/bridge/bridge.py
    - turtle/turtle-helper/.gitignore
    - turtle/turtle-helper/tests/test_agent.py
    - turtle/turtle-helper/tests/test_bridge_resilience.py
    - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/deferred-items.md

key-decisions:
  - "rules.json is a typed RuleBook (ordered SortRule list + optional overflow) behind load_rulebook()/save_rulebook(); load_rules() is the JSON view list_rules returns; a missing file is an empty book, a corrupt one raises to on_event's catch-all rather than being silently discarded"
  - "Rule patterns keep Lua string.find semantics on the bridge (bridge/lua_pattern.py translates to re); %b, %f and back-references are rejected, and add_rule refuses an unmatchable pattern with ModelRetry before saving"
  - "sort_chest is gated on a single device advertising both list_chest and push_one_slot (COMPOSITIONS), not on the union of all devices' caps, because it sends every command to one device"
  - "sort_chest stops at the first failed push and returns the device error plus the progress so far; no_rule and destination_full list each item id once"
  - "The pydantic-ai banner is switched off with pydantic_ai.BANNER_ENABLED = False inside configure() (the documented switch in the installed 2.46.0), not via an env var, so imports stay side-effect free and .env.example needs no new key"
  - "anthropic stays a direct pyproject dependency: bridge.py's boot check constructs anthropic.AsyncAnthropic itself and calls models.retrieve before pydantic-ai wraps that client"
  - "The pre-02-01 Lua sort_chest body is not preserved anywhere in git (client.lua was first tracked after the rewrite); the port follows the plan's spec and 02-01-SUMMARY's description (list, first-match rule, overflow fallback, push per slot, moved/no_rule/destination_full)"

patterns-established:
  - "Composition tools: DeviceArgs subclass for arguments, resolve device via args.device or default_worker(), compose over the injected send_cmd, validate device data with a model, return a dict"
  - "Two-file TAP layout: tests/test_agent_composition.py imports the fakes from tests/test_agent.py instead of duplicating them"

requirements-completed: [HARN-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Sorting rules persist on the bridge in rules.json beside .env (resolved from agent.py's location); list_rules/add_rule/remove_rule/set_overflow edit it and are always offered; a missing file is an empty rule book"
    requirement: HARN-02
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_rules_path_sits_beside_env_resolved_from_the_source_file"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_load_rules_without_a_file_returns_an_empty_rule_book"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_add_rule_then_list_rules_shows_the_rule_in_process_and_on_disk"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_remove_rule_drops_the_first_exact_match_only"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_set_overflow_is_saved_and_reported_by_list_rules"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_rule_tools_are_always_offered_whatever_is_connected"
        status: pass
      - kind: other
        ref: "plan 02-06 Task 1 <verify>: uv run python - <<PYEOF ... print('RULES_LOAD_OK') (printed RULES_LOAD_OK, exit 0)"
        status: pass
    human_judgment: false
  - id: D2
    description: "rules.json is git-ignored on its own line in turtle/turtle-helper/.gitignore and git check-ignore confirms it; no rules.json was ever committed"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_rules_json_is_git_ignored"
        status: pass
      - kind: other
        ref: "grep -q '^rules.json$' turtle/turtle-helper/.gitignore && git check-ignore -q turtle/turtle-helper/rules.json (exit 0)"
        status: pass
    human_judgment: false
  - id: D3
    description: "sort_chest composes list_chest then push_one_slot per matched item (first matching rule wins, overflow catches the rest), returns {moved, no_rule, destination_full}, propagates the device's list_chest error, stops on a failed push with progress, and is offered only when one device advertises both primitives"
    requirement: HARN-02
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_sort_chest_is_offered_only_when_one_device_has_both_primitives"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_sort_chest_args_take_from_name_and_an_optional_device"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_sort_chest_pushes_each_matched_item_and_reports_what_it_could_not_place"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_sort_chest_first_matching_rule_wins_then_overflow_catches_the_rest"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_sort_chest_returns_the_list_chest_error_and_pushes_nothing"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_sort_chest_stops_on_a_failed_push_and_reports_progress"
        status: pass
      - kind: other
        ref: "plan 02-06 Task 2 <verify>: gating script printed SORT_CHEST_GATING_OK (exit 0); grep 'async def sort_chest' + 'push_one_slot' in agent.py (exit 0)"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_toolset_with_computer_worker_adds_only_its_caps (and the three other toolset tests now expecting sort_chest)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Rule patterns match with Lua string.find semantics (%a/%d/%l classes, %. literal, sets, lazy '-', ^/$ anchors); unsupported or malformed patterns are rejected, and add_rule answers one with a retry prompt without saving"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_lua_patterns_match_like_string_find_not_like_regex"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_add_rule_rejects_a_malformed_lua_pattern_with_a_retry"
        status: pass
    human_judgment: false
  - id: D5
    description: "Final cleanup: no pre-swap dead code, anthropic still a direct dependency, ruff check / ruff format --check / mypy clean across bridge/ harness/ tests/, uv lock --check clean, pydantic-ai banner off, bridge.py holds its event tasks"
    verification:
      - kind: other
        ref: "cd turtle/turtle-helper && uv run ruff check bridge/ harness/ tests/ && uv run ruff format --check bridge/ harness/ tests/ && uv run mypy bridge/ harness/ tests/ && uv lock --check (all exit 0)"
        status: pass
      - kind: other
        ref: "grep -q '\"anthropic==' turtle/turtle-helper/pyproject.toml (exit 0); grep MAX_TURNS|DEVICE_TOOLS|LOCAL_TOOLS|run_tool bridge/agent.py -> no matches"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent_composition.py#test_configure_turns_off_the_pydantic_ai_first_run_banner"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_event_task_is_held_until_it_finishes"
        status: pass
    human_judgment: false
  - id: D6
    description: "sort_chest moves real items between real inventories in game with the same behaviour as the removed Lua loop"
    verification: []
    human_judgment: true
    rationale: "Sorting is a v1.0 non-deliverable (PROJECT.md, CONTEXT.md): the composition is ported and proven against scripted device replies, not against CC:Tweaked's pushItems; only a paid model call against real devices could exercise it, which is a later milestone's chore proof"

# Metrics
duration: 17 min
completed: 2026-09-25
status: complete
---

# Phase 02 Plan 06: Agent composition - sort_chest, rules.json, cleanup Summary

**Sorting rules now live on the bridge as a typed, git-ignored `rules.json` edited by four always-on local tools, and `sort_chest` is a cap-gated Python composition over `list_chest` + `push_one_slot` with Lua-pattern matching, on an `agent.py`/`bridge.py` that is ruff-, format- and mypy-clean across `bridge/ harness/ tests/`.**

## Performance

- **Duration:** 17 min
- **Started:** 2026-09-25T04:44:19Z
- **Completed:** 2026-09-25T05:01:18Z
- **Tasks:** 3 (Tasks 1 and 2 TDD, Task 3 plain)
- **Files modified:** 8 (2 created)

## Accomplishments

- **D-08 realised.** `rules_path = Path(__file__).resolve().parent.parent / "rules.json"` mirrors `settings.py`'s `.env` expression, so the file sits beside `.env` whatever the process cwd. `SortRule`/`RuleBook` model the file; `load_rulebook()` treats a missing file as an empty book with `overflow: null` (the old Lua `loadRules()` fallback), `save_rulebook()` writes via a sibling `.tmp` and `Path.replace()`. `list_rules`, `add_rule` (`{"ok": True, "count": n}`), `remove_rule` (first exact pattern match, `{"removed": bool}`) and `set_overflow` (`{"overflow": dest}`) carry the pre-swap tool descriptions verbatim and are in `build_toolset()`'s base set alongside `list_devices`/`say`. `rules.json` is git-ignored.
- **D-07's Python half realised.** `sort_chest(SortChestArgs{device?, from_name})` resolves the device (`args.device or default_worker()`), sends `list_chest {name}`, propagates a failed listing unchanged, validates the data as `ChestListing`, then for each item resolves `destination_for(item.name, book)` (first rule whose Lua pattern matches, else the overflow) and sends `push_one_slot {from, slot, dest, limit: count}`. It returns `{"moved": total, "no_rule": [...], "destination_full": [...]}`; a failed push stops the loop and returns `{"ok": False, "error": ..., moved, no_rule, destination_full}` so the model can report honestly.
- **D-09 for compositions.** A `COMPOSITIONS` table maps `sort_chest` to `{list_chest, push_one_slot}`; the tool is offered only when a single connected device advertises the whole set (a computer and a turtle both do; two devices holding one primitive each do not; no devices never).
- **Lua patterns kept honest.** `bridge/lua_pattern.py` translates a rule pattern to a Python regex with `string.find` semantics (`%a`/`%d`/`%l`/... classes and their negations, `%` escapes, `[...]` sets with classes and ranges, `*`/`+`/`-`(lazy)/`?`, `^`/`$` anchors, captures as plain groups). `%b`, `%f`, back-references and malformed patterns raise `LuaPatternError`; `add_rule` turns that into a `ModelRetry` so the model is told and nothing is saved.
- **Cleanup closed out.** No pre-swap dead code; `anthropic==1.7.0` confirmed as a direct dependency that `bridge.py`'s boot check uses directly; `bridge.py` formatted (one slice-spacing change); `pydantic_ai.BANNER_ENABLED = False` set in `configure()`; the mypy `type: ignore` in the resilience tests widened; `bridge.py` now holds its event tasks in `background_tasks` (covered by a new test). `uv run ruff check`, `uv run ruff format --check` and `uv run mypy` are clean over `bridge/ harness/ tests/`; `uv lock --check` clean; 12 + 23 + 16 TAP tests pass with zero spend.

## Task Commits

TDD cycle per task (RED evidence classified `RED_EVIDENCE_OK` by `gsd check tdd-red-evidence` before each GREEN):

1. **Task 1: rules.json persistence, rule-management local tools (D-08)**
   - RED `4b6d30b` `test(02-06)`: 7 new tests (all failing) + `LOCAL_TOOLS`/descriptions in `test_agent.py` (6 failing there for the intended reason)
   - GREEN `ce3b9df` `feat(02-06)`: `rules_path`, models, load/save, four tools, base toolset, `.gitignore`
   - REFACTOR: none needed
2. **Task 2: sort_chest - Python composition over list_chest + push_one_slot (D-07)**
   - RED `4ceb3da` `test(02-06)`: 8 new tests (all failing) + `COMPOSITIONS` expectations in `test_agent.py` (4 failing there)
   - GREEN `ab8a77d` `feat(02-06)`: `bridge/lua_pattern.py`, `ChestListing`/`PushResult`/`SortOutcome`, `destination_for`, `sort_chest`, `COMPOSITIONS` gating, `add_rule` pattern validation
   - REFACTOR: none needed
3. **Task 3: Final cleanup pass**
   - `981981b` `style(02-06)`: `ruff format bridge/bridge.py`, formatting only
   - `3fec691` `fix(02-06)`: hold event tasks in `bridge.py` + test; mypy ignore widened
   - `bc74867` `chore(02-06)`: banner off in `configure()` + test, dead-code/dependency confirmation, deferred items resolved

**Plan metadata:** see the `docs(02-06)` commit following this file.

| Task | RED commit | GREEN commit | REFACTOR | RED evidence |
|------|------------|--------------|----------|--------------|
| 1 | 4b6d30b `test(02-06)` | ce3b9df `feat(02-06)` | none needed | RED_EVIDENCE_OK (7 fail / exit 1) |
| 2 | 4ceb3da `test(02-06)` | ab8a77d `feat(02-06)` | none needed | RED_EVIDENCE_OK (8 fail / exit 1) |
| 3 | n/a (plain task) | 981981b / 3fec691 / bc74867 | - | - |

## Files Created/Modified

- `turtle/turtle-helper/bridge/agent.py` - rules section (`rules_path`, `SortRule`, `RuleBook`, `load_rulebook`, `save_rulebook`, `load_rules`, `AddRuleArgs`/`RemoveRuleArgs`/`SetOverflowArgs`, four rule tools), compositions section (`ChestItem`, `ChestListing`, `PushResult`, `SortOutcome`, `SortChestArgs`, `destination_for`, `sort_chest`), `COMPOSITIONS` and its gate in `build_toolset()`, `pydantic_ai.BANNER_ENABLED = False` in `configure()`
- `turtle/turtle-helper/bridge/lua_pattern.py` - new: `matches()`, `compile_pattern()` (cached), `to_regex()`, `LuaPatternError`
- `turtle/turtle-helper/bridge/bridge.py` - `background_tasks` set held by `handler()`; ruff formatting
- `turtle/turtle-helper/.gitignore` - `rules.json`
- `turtle/turtle-helper/tests/test_agent_composition.py` - new: 16 TAP tests (rules, sort_chest, Lua patterns, banner), reusing `test_agent.py`'s fakes
- `turtle/turtle-helper/tests/test_agent.py` - `LOCAL_TOOLS` now the six always-on tools, `COMPOSITIONS = ["sort_chest"]` in the capable-worker expectations, rule tool descriptions carried
- `turtle/turtle-helper/tests/test_bridge_resilience.py` - `test_event_task_is_held_until_it_finishes` (12 tests), ignore widened
- `.planning/.../deferred-items.md` - three items marked `status: resolved`

## Decisions Made

- `load_rules()` returns the plain JSON object (the plan's shape, what `list_rules` hands the model) while the code works on the typed `RuleBook`; a corrupt `rules.json` raises (surfacing through `on_event`'s "Sorry ... ValidationError" path) rather than silently starting from empty and overwriting the author's rules on the next `add_rule`.
- Lua-pattern semantics are implemented as a translation to `re` rather than a hand-written matcher: rules such as `^minecraft:.*_log$`, `%a+:iron_ingot` or `chest_%d+$` behave as they did in game, while the unsupported `%b`/`%f`/`%1` are refused at `add_rule` time instead of misbehaving at sort time.
- `sort_chest` gating is per device (one device must advertise both primitives), as the plan requires; the tool still targets `args.device or default_worker()`, so the model passes `device` when several workers are connected (same convention as every forwarding tool).
- `no_rule` and `destination_full` are de-duplicated item ids in slot order; several stacks of one item read as one entry in the model's summary.
- A failed push ends the run with the device's error and the counts so far; continuing past a broken destination would hide the misconfigured rule the model should report.
- The banner is disabled through the library's documented `BANNER_ENABLED` switch inside `configure()` (the one deliberate side-effect point), not via `os.environ` at import time, preserving Phase 1 D-13's "imports have no side effects".
- Task 3's optional `create_task` reference fix was taken (minimal: module set + done-callback) because `bridge.py` was already being touched for formatting and the fix is covered by one new in-process test.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] `add_rule` validates the Lua pattern before saving**
- **Found during:** Task 2 (designing `destination_for`)
- **Issue:** The plan's `add_rule` appended any string; a pattern the matcher cannot handle would only fail later, inside `sort_chest`, on every run until removed.
- **Fix:** `add_rule` compiles the pattern with `lua_pattern.compile_pattern()` and raises `ModelRetry` on `LuaPatternError`, so the model is told and nothing is persisted.
- **Files modified:** `bridge/agent.py`, `tests/test_agent_composition.py`
- **Verification:** `test_add_rule_rejects_a_malformed_lua_pattern_with_a_retry`
- **Committed in:** ab8a77d

**2. [Rule 2 - Missing Critical] Device data validated at the composition boundary; failed pushes stop the loop**
- **Found during:** Task 2
- **Issue:** The plan's loop indexed `result["items"]` and `push["moved"]` directly; a malformed or failed device reply would have raised `KeyError` out of the tool (or silently miscounted), and the plan did not say what a failed push does.
- **Fix:** `ChestListing`/`PushResult` validate `data`; an invalid frame or a failed push returns `SortOutcome.failed(error)` with the progress so far.
- **Files modified:** `bridge/agent.py`
- **Verification:** `test_sort_chest_stops_on_a_failed_push_and_reports_progress`, `test_sort_chest_returns_the_list_chest_error_and_pushes_nothing`
- **Committed in:** ab8a77d

**3. [Rule 1 - Bug] `bridge.py` kept no reference to its event tasks (files_modified widened)**
- **Found during:** Task 3 (deferred item from 02-02, taken as the orchestrator allowed)
- **Issue:** `asyncio.create_task(on_event(...))` with no reference; asyncio holds tasks weakly, so a long request could be collected mid-flight.
- **Fix:** module-level `background_tasks` set, add on create, discard on done.
- **Files modified:** `bridge/bridge.py`, `tests/test_bridge_resilience.py` (both outside the plan's `files_modified`)
- **Verification:** `test_event_task_is_held_until_it_finishes`; 12/12 resilience tests
- **Committed in:** 3fec691

**Scope widening (not fixes):** `bridge/lua_pattern.py` (new module - a Lua-pattern translator does not belong inside `agent.py`), `tests/test_agent_composition.py` (new test file), `tests/test_agent.py` (expectations for the new base set), `tests/test_bridge_resilience.py` (mypy ignore, per the orchestrator's Task 3 list), `bridge/bridge.py` (formatting, per the orchestrator's Task 3 list), `deferred-items.md` (status updates). `pyproject.toml` was listed in `files_modified` but needed no change: `anthropic` was already direct and no dependency moved.

---

**Total deviations:** 3 auto-fixed (2 missing-critical, 1 bug) plus documented file-list widening.
**Impact on plan:** All three make the composition and the bridge safer against bad device data and long requests; no scope creep beyond the plan's objective and the orchestrator's cleanup list.

## Issues Encountered

- The pre-02-01 `client.lua` (with the original `sort_chest`/`destFor` bodies) is not in git or anywhere in `.planning/`: client.lua's first commit (`96438fc`) is the post-rewrite file. The port therefore follows the plan's stated semantics and 02-01-SUMMARY's description; the pre-swap `agent.py` at `53d57eb` supplied the exact tool descriptions and argument names, which are carried verbatim.
- A patch script turned a `"\n"` escape into a literal newline in `save_rulebook()`, caught immediately by ruff/mypy/tests before the GREEN commit.
- The carried `add_rule` and `sort_chest` descriptions are 96 and 116 characters, so their one-line docstrings carry `# noqa: E501` rather than being reworded (pydantic-ai reads the docstring as the description the model sees).
- WSL was available; the human-design `engineering-standards.md` and `python.instructions.md` were read (Pydantic-first boundaries, `pathlib`, small typed functions, no `dict[str, Any]` as domain structures) and shaped `RuleBook`/`ChestListing`/`SortOutcome`.

## Known Stubs

None. `sort_chest` is fully wired to `send_cmd`; it is unproven against a real inventory by design (sorting is a v1.0 non-deliverable), which coverage entry D6 records as human judgment, not a stub.

## Threat Flags

None beyond the plan's register. T-02-06a (rules.json committed by accident) is mitigated by the `.gitignore` line and `test_rules_json_is_git_ignored`; T-02-06b (tampered rules.json) remains accepted - only the bridge process reads it, and a pattern it cannot compile is refused at `add_rule` while one edited on disk by hand fails loudly at load.

## User Setup Required

None - no external service configuration required. `rules.json` is created on the first `add_rule`/`set_overflow`; nothing needs to exist beforehand.

## Next Phase Readiness

- **02-07 (docs + post-swap paid run):** `turtle/turtle-helper/CLAUDE.md`'s Architecture bullet "Sorting, pathing, vein-mining live in Lua" and "Current state" ("Rules persist in `rules.json` on the device") are now false and are 02-07's amendments (D-17): rules live in the bridge's git-ignored `rules.json` beside `.env`; `sort_chest` is a Python composition; adding a chore is one typed Python tool function plus a `tools.xxx` Lua entry only for a new primitive. The bridge log no longer carries the pydantic-ai banner. The wire for the devices question is unchanged by this plan (the rule tools and `sort_chest` only add entries to the tool list the model sees; with the fake worker connected, `sort_chest` will be in that list).
- **Deferred items still open:** `harness/scenarios.py` `devices_question` passing on the error-fallback `say` (02-07); `SayArgs.to` revisit after 02-07.
- **Tests for the whole Python side:** `uv run python tests/test_bridge_resilience.py` (12), `uv run python tests/test_agent.py` (23), `uv run python tests/test_agent_composition.py` (16); all zero-spend.

## Self-Check: PASSED

- Created files present on disk: `turtle/turtle-helper/bridge/lua_pattern.py`, `turtle/turtle-helper/tests/test_agent_composition.py`.
- Commits `4b6d30b`, `ce3b9df`, `4ceb3da`, `ab8a77d`, `981981b`, `3fec691`, `bc74867` present in `git log`.
- `commits: 7` measured via `git rev-list --count a8ab694..HEAD` at SUMMARY time; `git status` shows no uncommitted change under `turtle/turtle-helper/` (the pre-existing untracked `CLAUDE.md` and `base/` are 02-07's).

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-25*

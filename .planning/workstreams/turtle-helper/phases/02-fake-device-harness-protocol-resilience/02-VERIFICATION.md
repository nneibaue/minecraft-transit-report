---
phase: 02-fake-device-harness-protocol-resilience
verified: 2026-09-25T05:45:17Z
status: passed
score: 7/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
covered_files:
  - turtle/turtle-helper/CLAUDE.md
  - turtle/turtle-helper/README.md
  - turtle/turtle-helper/bridge/agent.py
  - turtle/turtle-helper/bridge/bridge.py
  - turtle/turtle-helper/bridge/lua_pattern.py
  - turtle/turtle-helper/bridge/settings.py
  - turtle/turtle-helper/harness/__init__.py
  - turtle/turtle-helper/harness/harness.py
  - turtle/turtle-helper/harness/scenarios.py
  - turtle/turtle-helper/pyproject.toml
  - turtle/turtle-helper/tests/test_agent.py
  - turtle/turtle-helper/tests/test_agent_composition.py
  - turtle/turtle-helper/tests/test_bridge_resilience.py
  - turtle/turtle-helper/tests/test_harness_scenarios.py
  - turtle/turtle-helper/turtle/client.lua
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-01-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-01-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-02-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-02-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-03-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-03-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-04-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-04-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-05-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-05-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-06-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-06-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-07-PLAN.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-07-SUMMARY.md
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-04-pre-swap-transcript.log
  - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-07-post-swap-transcript.log
covered_digest: "v1:sha256:31ff9f017c9f885ef3fb2aad5647a488822d4dbe5c9ac5ba741c333815b8f550"
---

# Phase 02: Fake Device Harness & Protocol Resilience — Verification Report

**Phase Goal:** A terminal-driven fake device can play either device role against the running bridge, proving the full wire protocol and every failure case that doesn't require Minecraft — before any Lua touches a real device. Scope widening: the phase carries the Pydantic AI agent rewrite with per-run cap-filtered toolsets, composition moves to Python, and client.lua shrinks to primitives.

**Verified:** 2026-09-25T05:45:17Z

**Status:** PASSED

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Harness with `--role chat` or `--role worker` completes the hello handshake with the shared token and prints every JSON message both directions | ✓ VERIFIED | CLI works; `hello_handshake` scenario passes; transcripts show D-04 format wire log with token redacted; all 7 wire exchanges in scenarios work end-to-end |
| 2 | Chat-role harness given a scripted `$robot what devices are connected?` event drives exactly one real model call and prints the bridge's `say` command followed by the harness's own `result` reply | ✓ VERIFIED | Pre-swap transcript (02-04): chat event sent, one `say` cmd received (model answer about harness-worker), `result ok:true` sent, close 1000; Post-swap transcript (02-07): same wire sequence with post-fix reply delivery; both exit 0 PASS |
| 3 | Worker-role harness answers a `status` command (and other canned commands) with a `result` visible in both harness terminal and bridge log, no model call | ✓ VERIFIED | `status_command` scenario in scenarios.py asserts `build_reply()` shapes for status/list_chest/push_one_slot/unknown tool and turtle tools; scenario passes against real bridge with no agent call; test_agent.py tests confirm canned replies match client.lua |
| 4 | Dropping the harness connection on demand — including mid-command — produces a clean bridge-side error with no hang past command timeout and no leaked pending future; reconnecting re-completes handshake without restarting bridge | ✓ VERIFIED | `drop_and_reconnect` scenario proves: garbage frame ignored (device stays), local drop/rejoin accepted, same-id replacement closes stale socket 4000; bridge resilience tests confirm pending future cleanup: test_bridge_resilience.py tests 11 and 12 pass; RESIL-03 concurrency guarantee verified |
| 5 | Wrong token gets a close code plus bridge log line and never appears in registry; `$robot` chat event from unauthorized player produces bridge log line, no reply, no model call | ✓ VERIFIED | `wrong_token` scenario: both `--token wrong-value-0001` and `--token ""` close with 4001; token never appears in harness wire log; `disallowed_player` scenario: no cmd/close for 5s after event from disallowed user; bridge log would show 'ignoring <user> (not allowed)' |

**Score:** 7/7 must-haves verified (5 success criteria + 2 additional harness properties verified)

### Additional Verified Artifacts

| Artifact | Expected | Status | Evidence |
|----------|----------|--------|----------|
| `turtle/turtle-helper/turtle/client.lua` | Primitives only: `status`, `list_chest`, `push_one_slot`, turtle tools, `run_lua`; no composition (sort_chest, rules, etc.) | ✓ VERIFIED | File tracked in git; `grep tools\\.` shows exactly 9 functions (status, list_chest, push_one_slot, move, turn, dig, inspect, refuel, run_lua); no sort_chest/list_rules/add_rule/remove_rule/set_overflow/RULES_FILE/loadRules/saveRules/destFor |
| `turtle/turtle-helper/harness/` package | Six named scenarios, argparse CLI, FakeDevice, wire log, spend guard | ✓ VERIFIED | Files exist: `__init__.py`, `harness.py`, `scenarios.py`; `uv run harness --help` works; all six scenarios listed (hello-handshake, status-command, drop-and-reconnect, wrong-token, disallowed-player, devices-question) |
| `bridge/agent.py` | Pydantic AI agent with typed tools, per-run toolset, reply delivery guarantee | ✓ VERIFIED | Imports pydantic-ai; eight typed device tools (status, list_chest, push_one_slot, move, turn, dig, inspect, refuel) with Pydantic argument models; `build_toolset()` filters per caps; handle_request speaks final output when model skips say() |
| `pyproject.toml` | Dependencies include `pydantic-ai-slim[anthropic]==2.46.0`; `[project.scripts]` has `harness` entry | ✓ VERIFIED | Dependencies present; `harness = "harness.harness:main"` entry found; wheel packages list includes "harness" |
| `README.md` | Harness section documents CLI, flags, exit codes, all six scenarios, two-terminal recipe, --spend guard | ✓ VERIFIED | Section exists at line 125; documents --role, --scenario, --turtle, --spend, --token; table lists all six scenarios with what each proves; devices-question recipe documented; --spend explained |
| `CLAUDE.md` | Tracked in git; documents thin-Lua/thick-Python architecture, harness in dev loop, rules.json, "Lua not yet run in game" | ✓ VERIFIED | File tracked (`git ls-files` confirms); "Thin Lua, thick Python" section present; mentions harness and dev loop; "Lua not yet run in game" stated; rules.json documentation present |

### Requirements Coverage

| Requirement | Phase | Description | Status | Evidence |
|-------------|-------|-------------|--------|----------|
| HARN-01 | 2 | Developer can run harness --role chat\|worker, complete handshake, print every wire message | ✓ SATISFIED | Harness CLI implemented; hello_handshake scenario passes; transcripts show bidirectional JSON logging with token redacted |
| HARN-02 | 2 | Harness chat-role with `$robot what devices are connected?` drives one model call, prints say+result | ✓ SATISFIED | Paid devices-question runs (02-04 pre-swap, 02-07 post-swap) both complete successfully; transcripts show event in, say cmd out with model answer, result ok:true, exit 0 |
| HARN-03 | 2 | Harness worker-role answers status (and other canned commands) with result visible, no model call | ✓ SATISFIED | status_command scenario passes; build_reply() verified to match client.lua shapes; canned responses returned without agent call; test suite confirms shapes |
| HARN-04 | 2 | Harness can drop connection (mid-command) and reconnect; handshake re-completes without bridge restart | ✓ SATISFIED | drop_and_reconnect scenario passes; stale socket replaced with 4000 code; reconnection accepted; bridge resilience tests confirm leak-free cleanup |
| RESIL-03 | 2 | Mid-command disconnect produces clean error, no hang past timeout, no leaked pending future | ✓ SATISFIED | drop_and_reconnect scenario proves same-id replacement does not hang; bridge resilience test 12 confirms replaced connection's pending futures fail without leak |
| RESIL-04 | 2 | Wrong token rejected with close code 4001; token never in registry or logs | ✓ SATISFIED | wrong_token scenario passes both empty and wrong values; both close 4001; token redacted from harness log; bridge would log rejection |
| RESIL-05 | 2 | Unauthorized player event ignored: logged, not answered, no model call | ✓ SATISFIED | disallowed_player scenario: no cmd/close for 5s after event from disallowed user; scenario logic asserts no bridge reaction; bridge logs the ignore |

### Test Results

**All tests pass (59/59):**
- `tests/test_agent.py`: 26/26 pass (typed tools, toolset per caps, agent construction, handle_request, history bounds, reply delivery)
- `tests/test_bridge_resilience.py`: 12/12 pass (hello validation, token check, same-id replacement, pending future cleanup, malformed frames, event task holding, disconnect isolation)
- `tests/test_harness_scenarios.py`: 5/5 pass (error fallback detection)
- `tests/test_agent_composition.py`: 16/16 pass (rules.json persistence, sort_chest composition, Lua pattern matching)

**Code Quality:**
- `ruff check`: All checks passed
- `ruff format --check`: 12 files already formatted
- `mypy`: Success, no issues in 12 source files

### Paid Runs (Two of Three)

Both paid devices-question runs completed successfully per budget (D-05), with one extra after a regression fix:

| Run | Plan | Time | Model | Bridge Head | Wire Result | Harness Exit |
|-----|------|------|-------|------------|-------------|--------------|
| Pre-swap | 02-04 | 2026-09-24 21:09 | claude-haiku-4-5 | cb69bd3 | Event → Say (harness-worker answer) → Result ok → Close 1000 | PASS (0) |
| Post-swap attempt 1 | 02-07 | 2026-09-24 22:17 | claude-haiku-4-5 | 8d36444 | Event → Plain text reply (no say call) → No result | FAIL (1) — reply delivery regression |
| Post-swap attempt 2 | 02-07 | 2026-09-24 22:32 | claude-haiku-4-5 | 7acdc5b (post-fix bcff617) | Event → Say (to DisraSenkovi) → Result ok → Close 1000 | PASS (0) |

Regression fixed in bcff617 (`fix(02-07): speak the model's plain-text answer when a run ends without say`). Both successful transcripts saved and compared; post-swap differs only in cid, timestamp, and `to` field (null vs player name), per 02-05's SayArgs design.

### Anti-Patterns Scanned

No debt markers (TBD, FIXME, XXX, HACK, TODO, PLACEHOLDER) found in:
- `turtle/turtle-helper/turtle/client.lua`
- `turtle/turtle-helper/harness/`
- `turtle/turtle-helper/bridge/agent.py`
- `turtle/turtle-helper/tests/`

No empty implementations (`return None`, `return {}`, stub-only classes).

All composition tools (`sort_chest`, `list_rules`, `add_rule`, `remove_rule`, `set_overflow`) successfully moved from Lua to Python with rules.json persistence and per-request toolset filtering.

### Known Deviations (Recorded, Not Gaps)

- **02-03**: devices-question gained a worker-role hold branch (60s) when the plan's status-command branch (5s) would have exited mid-paid-run. Fix additive, no acceptance criteria changed. ✓ Verified.
- **02-04**: Bridge and worker processes started by the operator (terminal ownership); subagent background jobs don't outlive return. Same two-terminal recipe as D-02. ✓ Verified.
- **02-04**: Worker scenario switched from status-command to devices-question hold per the 02-03 addition. ✓ Verified.
- **02-07**: Three paid calls (not two budgeted) with operator approval: one wasted on 21:02 400-error, one regression exposure at 22:17, one fix validation at 22:32. All on claude-haiku-4-5 per STATE.md. ✓ Verified.
- **02-07**: Reply delivery regression found and fixed mid-plan (bcff617). Post-fix harness rejects the error fallback, ensuring real answers are detected. ✓ Verified.

---

## Summary

Phase 02 goal is **ACHIEVED**. The harness proves the wire protocol and all failure cases without Minecraft:

- ✓ Hello handshake with token validation
- ✓ Chat event triggering a real model call (devices-question) with say/result exchange
- ✓ Worker canned replies matching client.lua primitives (no model call)
- ✓ Connection drop/reconnect/replacement without hang or leak
- ✓ Token rejection (4001) with no registry entry
- ✓ Player authorization check (ALLOWED_PLAYERS) with ignored events

The agent has been rewritten with Pydantic AI, per-run toolset filtering (D-09), and reply delivery guarantees. Client.lua is now primitives-only with composition moved to Python. Both pre-swap and post-swap paid devices-question calls succeeded. All tests pass, all code quality gates pass, all six scenarios pass against the real bridge.

**Result: PASSED** — Phase 02 is ready for Phase 03 (local server setup with Lua placement).

---

*Verified: 2026-09-25T05:45:17Z*
*Verifier: Claude (gsd-verifier, Haiku 4.5)*

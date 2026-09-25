---
phase: 02-fake-device-harness-protocol-resilience
plan: 07
subsystem: docs
tags: [harness, README, CLAUDE.md, devices-question, paid-call, post-swap, transcript, pydantic-ai, say, reply-delivery, HARN-02, D-05, D-15, D-17, claude-haiku-4-5]

# Dependency graph
requires:
  - phase: 02-fake-device-harness-protocol-resilience
    provides: "02-03: the harness package and the six scenarios README documents (with the real --role/--scenario/--turtle/--spend/--token flags); 02-04: the pre-swap transcript this plan's post-swap run is compared against, and the false-PASS observation fixed here; 02-05/02-06: the fully swapped pydantic-ai agent (typed tools, per-run toolset, sort_chest, rules.json) the paid run proves and CLAUDE.md now describes"
  - phase: 01-bridge-environment
    provides: "The operator's real .env (ANTHROPIC_API_KEY, BRIDGE_TOKEN, ALLOWED_PLAYERS, MODEL=claude-haiku-4-5) and the bridge/settings/agent module split"
provides:
  - "turtle/turtle-helper/README.md '## Harness' section: what the harness is, the real CLI, exit codes 0/1/2, the one-line wire log, a table of all six scenarios with what each proves and its exact invocation, the two-terminal devices-question recipe (worker first, 60 s hold), and --spend as the code-enforced deliberate act (D-17, D-15)"
  - "turtle/turtle-helper/CLAUDE.md (first tracked commit): Dev loop names the harness against the local bridge and the zero-spend TAP tests; Architecture gains 'Thin Lua, thick Python' (primitives in Lua one to one, loops and policy in Python, per-request toolset, rules.json beside .env); Protocol shapes untouched; 'Adding a chore' no longer names DEVICE_TOOLS; Current state still says the Lua has not run in game (D-17)"
  - "02-07-post-swap-transcript.log: verbatim wire log of the post-swap paid devices-question run (chat event out, one say cmd in addressed to the requesting player, result ok:true, close 1000, PASS: devices-question, exit 0) with a commented provenance header, proving HARN-02 against the fully swapped agent (D-05)"
  - "bridge/agent.py reply-delivery guarantee: when a run ends without a say ToolReturnPart, handle_request speaks the model's plain-text final output to the requesting player via say_in_chat and logs the final output every run; instructions nudge the model to answer through say() (fix for the regression the first post-swap paid attempt exposed)"
  - "harness/scenarios.py: devices-question fails (exit 1) on an empty say text or the bridge's 'Sorry <user>, something went wrong: <Error>' fallback (02-04's false positive closed)"
affects: [02 code review, 03 server setup (the Lua placement dev loop CLAUDE.md now names), 04 in-game round trip (say delivery contract, device-naming product question), 05 docs (DOC-02 flips the 'Lua not yet run' line)]

# Actuals (#2632) - estimateTokens scale (chars/4 over the realized diff), not a harness token count.
actuals:
  tokens: 7600
  tasks: 4
  commits: 8
plan_head_before: 8d3644428e76ef3ce69e52d2d1087969e13fc0b7

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reply delivery is guaranteed by the bridge, not assumed of the model: handle_request checks result.new_messages() for a say ToolReturnPart (the return part, not the call part) and speaks result.output to the requester when none is present; the instruction is the nudge, the fallback is the guarantee"
    - "A harness PASS requires a non-fallback answer: scenario expectation steps reject bridge.on_event's error-fallback say shape, so an upstream API failure reads FAIL"
    - "Saved transcripts carry a commented provenance header (time, model, commit, which terminal ran what, which attempts are not part of the proof) above a verbatim body that is never edited after capture"

key-files:
  created:
    - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-07-post-swap-transcript.log
    - turtle/turtle-helper/tests/test_harness_scenarios.py
  modified:
    - turtle/turtle-helper/README.md
    - turtle/turtle-helper/CLAUDE.md
    - turtle/turtle-helper/bridge/agent.py
    - turtle/turtle-helper/harness/scenarios.py
    - turtle/turtle-helper/tests/test_agent.py
    - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/deferred-items.md

key-decisions:
  - "The bridge guarantees reply delivery: handle_request speaks the model's plain-text final output to the requesting player when the run ends without a say ToolReturnPart, never repeats an answer the model already spoke, and logs the final output every run; Pydantic AI's output_type=str invites a plain-text final answer, so the pre-swap reliance on the model always calling say() was luck, not a contract"
  - "D-05's paid-call budget was exceeded by one with the operator's explicit go-ahead: the first post-swap attempt (22:17) exposed the reply-delivery regression and failed, so the phase made three paid calls (02-04 pass, 02-07 fail, 02-07 pass), all on claude-haiku-4-5; a fourth earlier 400/no-credit attempt during 02-04 is not counted as a call"
  - "The devices-question scenario rejects the bridge's error-fallback say shape rather than requiring the answer to name a connected device id: the chat process cannot know a worker is connected, and the transcript prints the say text for the human read"
  - "Post-swap say carried to: DisraSenkovi (a whisper) where pre-swap carried to: null (broadcast); accepted as a legitimate wire difference because SayArgs.to stayed optional (02-05) and the instructions now nudge the model to address the player; the frame shape and sequence are identical"
  - "Setup ownership for the paid run stayed with the operator's terminals (as in 02-04): the executor proved boot and worker registration on PORT=8766 and stopped its processes; the operator ran bridge, worker (devices-question 60 s hold, not status-command) and chat terminals"

patterns-established:
  - "Docs that describe the code are corrected in the same plan that discovers them stale (README Layout/Protocol/Adding-a-chore rows), rather than logged as deferred items"

requirements-completed: [HARN-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "README.md '## Harness' section documents all six scenarios with what each proves and its exact invocation, the two-terminal devices-question recipe (worker first), and --spend as the deliberate, code-enforced act"
    verification:
      - kind: other
        ref: "plan 02-07 Task 1 <verify>: F=turtle/turtle-helper/README.md; grep -q '## Harness' && grep -q 'hello-handshake' && grep -q 'devices-question' && grep -q -- '--spend' (exit 0, re-run at close-out); all six scenario names present; line 171 'Start the worker first'"
        status: pass
    human_judgment: false
  - id: D2
    description: "CLAUDE.md's Dev loop names the harness; Architecture states the thin-Lua/rules-on-the-bridge rule; Protocol shapes unchanged; Current state still says the Lua has not run in game; the file is tracked in git"
    verification:
      - kind: other
        ref: "plan 02-07 Task 2 <verify>: grep -qi 'harness' && grep -qi 'rules.json|rules on the bridge|rules persist' && grep -q 'not yet run in game|never run in game|Lua not yet run' turtle/turtle-helper/CLAUDE.md (exit 0, re-run at close-out)"
        status: pass
      - kind: other
        ref: "git ls-files --error-unmatch turtle/turtle-helper/CLAUDE.md (exit 0; first tracked in a2b4f46)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Post-swap paid devices-question run passes on the wire against the fully swapped agent: chat event out, one inbound say cmd within two seconds, result ok:true, close 1000, PASS: devices-question, exit 0; same frame sequence as the pre-swap transcript"
    requirement: HARN-02
    verification:
      - kind: manual_procedural
        ref: "operator: cd turtle/turtle-helper && uv run harness --role chat --scenario devices-question --spend (2026-09-24 22:32 local, bridge on HEAD 7acdc5b, MODEL=claude-haiku-4-5) -> PASS: devices-question, exit 0"
        status: pass
      - kind: other
        ref: "grep -c 'PASS: devices-question' 02-07-post-swap-transcript.log -> 1; grep -c '\"tool\": \"say\"' -> 1; grep -c '\"type\":\"result\"' -> 1 (cid 59e50799, ok:true); close code 1000; sequence hello -> event -> say cmd -> result -> close -> PASS matches 02-04-pre-swap-transcript.log line for line"
        status: pass
    human_judgment: false
  - id: D4
    description: "The model's spoken post-swap answer is a correct, non-fallback devices answer ('You've got a worker computer and a chat computer hooked up ...') addressed to the requesting player"
    requirement: HARN-02
    verification:
      - kind: manual_procedural
        ref: "transcript line 27/29: say text names a worker computer and a chat computer, to: DisraSenkovi, not the 'Sorry ... something went wrong' fallback"
        status: pass
    human_judgment: true
    rationale: "The tightened scenario asserts only that the say text is non-empty and not the bridge's error fallback; whether the prose actually answers the question (and whether it should name harness-worker by id, as the pre-swap answer did) is a human read"
  - id: D5
    description: "Reply-delivery regression fixed: a run whose model answers in plain text without calling say is spoken to the requester and logged; an answer already spoken via say is not repeated; a blank output speaks nothing"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_plain_text_answer_is_spoken_to_the_requester_when_the_model_skips_say"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_answer_the_model_spoke_through_say_is_not_repeated"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_blank_final_output_without_say_speaks_nothing"
        status: pass
      - kind: other
        ref: "uv run python tests/test_agent.py at close-out -> tests 26, pass 26, fail 0"
        status: pass
    human_judgment: false
  - id: D6
    description: "devices-question scenario fails on the bridge's error-fallback say (02-04's false positive closed)"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_harness_scenarios.py#test_the_bridge_error_fallback_is_recognised"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_harness_scenarios.py#test_a_real_devices_answer_is_not_a_fallback"
        status: pass
      - kind: other
        ref: "uv run python tests/test_harness_scenarios.py at close-out -> tests 5, pass 5, fail 0"
        status: pass
    human_judgment: false

# Metrics
duration: 30 min (execution 22:10-22:32 local incl. two paid attempts and the reply-delivery fix; close-out continuation ~8 min; checkpoint waited on the operator between)
completed: 2026-09-25
status: complete
---

# Phase 02 Plan 07: Harness Docs, CLAUDE.md Amendments, Post-Swap Paid Run Summary

**README "Harness" section and CLAUDE.md thin-Lua/rules-on-bridge amendments shipped; the post-swap paid devices-question run passed with the same wire shape as pre-swap, after a first attempt exposed and fixed a reply-delivery regression (the model answered in plain text and the swapped agent dropped it)**

## Performance

- **Duration:** ~30 min of execution across two executors (22:10-22:32 local, then this close-out at 22:34-22:42); the `blocking-human` checkpoint waited on the operator in between
- **Started:** 2026-09-25T05:10:51Z (first task commit, 0b9cbea)
- **Completed:** 2026-09-25T05:42:00Z
- **Tasks:** 4/4 (3 auto + 1 human-action checkpoint, resolved by the operator's run)
- **Files modified:** 8 (README.md, CLAUDE.md, bridge/agent.py, harness/scenarios.py, tests/test_agent.py, tests/test_harness_scenarios.py, deferred-items.md, the new transcript)

## Accomplishments

- README.md gained `## Harness` (its own H2 after the Setup block): what the harness is, the real CLI flags, exit codes 0/1/2, the wire-log line format, a six-row scenario table with what each proves and its exact `uv run harness --role ... --scenario ...` invocation, the two-terminal devices-question recipe (worker first, 60 s hold, then the chat terminal with `--spend`), and `--spend` documented as the code-enforced deliberate act (D-17, D-15). Rows still describing the pre-Phase-2 design were corrected in passing.
- CLAUDE.md is tracked for the first time and reflects the final architecture: Dev loop names the harness against the local bridge (no tunnel) and the zero-spend TAP tests; a "Thin Lua, thick Python" subsection states D-07/D-08; Protocol shapes are untouched; "Adding a chore" no longer names `DEVICE_TOOLS`; "Current state" still says the Lua has not run in game (Phase 5's DOC-02 owns that).
- HARN-02 proven a second time against the fully swapped Pydantic AI agent: the operator's 22:32 run produced one inbound `say` cmd within two seconds of the chat event, `result ok:true`, `close 1000`, `PASS: devices-question`, exit 0. The transcript is saved with a provenance header and compared against 02-04's pre-swap transcript below.
- The first post-swap attempt (22:17) did NOT pass: the model answered in plain text after `list_devices` and the swapped `handle_request` spoke nothing, so the harness timed out. That is a real observable change on the wire, exactly what D-05's second paid call exists to catch. Fixed in bcff617; the second attempt then passed. Details under Deviations.
- The 02-04 false positive (harness passing on the bridge's error-fallback say) is closed: `devices-question` now fails on an empty or fallback say text, with five zero-network TAP tests.

## Post-swap vs pre-swap transcript comparison (plan `<verification>`)

Both transcripts (`02-04-pre-swap-transcript.log`, `02-07-post-swap-transcript.log`) show the identical frame sequence:

| Step | Pre-swap (21:09, HEAD cb69bd3, hand-rolled loop) | Post-swap (22:32, HEAD 7acdc5b, pydantic-ai + fix) | Same? |
|------|------|------|------|
| 1 | `hello {id: harness-chat, token: ***, role: chat, caps: [say]}` out | identical | yes |
| 2 | `event chat {user: DisraSenkovi, text: "$robot what devices are connected?", uuid, hidden: true}` out (+2.0 s) | identical (+2.0 s) | yes |
| 3 | `cmd {cid: a50ed22a, tool: say, args: {text, to: null, prefix: Robot}}` in (+3.2 s) | `cmd {cid: 59e50799, tool: say, args: {text, to: "DisraSenkovi", prefix: Robot}}` in (+1.9 s) | shape yes; `cid`, latency, text and `to` differ |
| 4 | `result {cid: a50ed22a, ok: true, data: {queued: true}}` out | `result {cid: 59e50799, ok: true, data: {queued: true}}` out | yes (cid differs) |
| 5 | `close {code: 1000, reason: ""}` in | identical | yes |
| 6 | `PASS: devices-question`, exit 0 | identical | yes |

Neither transcript shows a `list_devices` cmd on the chat socket, as expected: `list_devices` is a bridge-local tool and never crosses the wire (the bridge log is where its call is visible). One `say` cmd each, no retries, no extra frames.

Legitimate differences: `cid` values, timestamps, the answer text, and `"to"`. Pre-swap the model broadcast (`to: null`); post-swap the say was addressed to `DisraSenkovi`. `SayArgs.to` stayed optional in 02-05 precisely so this comparison could be like-for-like, and the frame accepts both; the whisper is the effect of the instruction nudge added in bcff617 ("Answer through say(), not as plain text: players only read game chat") together with the `[<player>]` prompt prefix, or of the bridge speaking on the model's behalf (the log line distinguishes the two; the operator's bridge log was not captured in the transcript). Either way it is a better default for a `$robot` question and not a protocol change.

Answer-text difference worth noting for Phase 4: the pre-swap answer named `harness-worker` by id and its chest access; the post-swap answer said "a worker computer and a chat computer" without the id. The tightened harness only checks for a non-fallback say; whether the model should be nudged to name device ids is a product question for the in-game phase, not a defect here.

## Task Commits

Each task was committed atomically (all on `main`, sequential mode, ledger base 8d36444):

1. **Rule 1 deviation (before Task 1): harness false-PASS fix** - `0b9cbea` (fix)
2. **Task 1: README.md "Harness" section** - `f33c938` (docs)
3. **Task 2: CLAUDE.md Dev loop / Architecture / Protocol amendments; file first tracked** - `a2b4f46` (docs)
4. **Bookkeeping: 02-04 false-PASS deferred item marked resolved** - `2fb724d` (docs)
5. **Task 3: swapped bridge + worker booted for the post-swap run** - no commit (evidence only: the previous executor saw the swapped agent boot and the worker register on PORT=8766, then stopped its processes)
6. **Rule 1 deviation (found by the first post-swap paid attempt): reply-delivery regression** - `d107778` (test, RED), `bcff617` (fix, GREEN), `7acdc5b` (docs, deferred-items note)
7. **Task 4: human-triggered paid devices-question run (post-swap)** - checkpoint resolved by the operator's 22:32 run; transcript committed as `ed354d3` (docs)

**Plan metadata:** see the final `docs(02-07): complete ... plan` commit.

## Files Created/Modified

- `turtle/turtle-helper/README.md` - new `## Harness` section; corrected Layout, Protocol example (`push_one_slot`, not `sort_chest`), "Adding a chore", `run_lua` knob and "Next chores" rows
- `turtle/turtle-helper/CLAUDE.md` - first tracked; Dev loop, "Thin Lua, thick Python" subsection, "Adding a chore", Current state sorting/MODEL bullets corrected; "Lua not yet run in game" kept verbatim
- `turtle/turtle-helper/bridge/agent.py` - `_spoke()` helper; `handle_request` speaks the plain-text final output to the requester when no `say` ToolReturnPart is present, logs the final output every run; instructions gain the "Answer through say()" line; docstrings describe the contract
- `turtle/turtle-helper/harness/scenarios.py` - `is_error_fallback()`; `devices-question` chat branch requires a non-empty, non-fallback say text
- `turtle/turtle-helper/tests/test_agent.py` - tests 24-26 (plain-text answer whispered and logged; model-spoken answer not repeated; blank output speaks nothing); test 24 raises the bridge logger to INFO for its duration
- `turtle/turtle-helper/tests/test_harness_scenarios.py` - new, 5 zero-network TAP checks including the verbatim 21:02 fallback text and the 21:09 real answer
- `.planning/.../02-07-post-swap-transcript.log` - new, verbatim post-swap run with provenance header
- `.planning/.../deferred-items.md` - 02-04 false-PASS item marked resolved; new 02-07 reply-delivery item recorded and marked resolved

## Decisions Made

- **The bridge guarantees reply delivery.** After `agent.run`, `handle_request` checks `result.new_messages()` for a `say` `ToolReturnPart` (the return part, not the call part: a say that failed validation never spoke). With none and a non-blank `result.output`, it calls `say_in_chat(answer, user)` and logs that it spoke on the model's behalf; the final output is logged every run (200 chars). Root cause of the regression: an `Agent[None, str]` invites a plain-text final answer; the pre-swap loop had the same reliance on the model calling `say` and merely got lucky. The instruction is the nudge, the fallback is the guarantee.
- **Paid-call budget exceeded by one, deliberately.** D-05 budgeted two paid calls for the phase. Three were made: 02-04 pre-swap (pass), 02-07 first attempt at 22:17 (fail, exposed the regression), 02-07 second attempt at 22:32 (pass), with the operator's explicit go-ahead for the third. A fourth, earlier attempt at 21:02 during 02-04 hit an API 400 (no credit) and is recorded in 02-04's SUMMARY. All on claude-haiku-4-5 per the STATE.md decision, so the comparison is like-for-like.
- **Fallback rejection, not device-id matching, for the harness.** The stricter "say text must name a connected device id" variant was not adopted: the chat process cannot know a worker is connected, and the transcript prints the say text for the human read. The post-swap answer would in fact have failed that stricter check.
- **`to: "DisraSenkovi"` vs `to: null` accepted as a legitimate difference** (see comparison above); `SayArgs.to` stays optional per 02-05.
- **Setup ownership stayed with the operator** (as in 02-04): a subagent's background processes do not outlive its return, so Task 3's acceptance criterion was met as evidence (swapped agent boots, worker registers) on PORT=8766 because the operator's own bridge held 8765; the operator then ran bridge, worker and chat terminals for the paid call.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reply-delivery regression: plain-text model answer dropped after the swap**
- **Found during:** Task 4 (first post-swap paid attempt, 2026-09-24 22:17, claude-haiku-4-5, HEAD 2fb724d)
- **Issue:** The model made two round trips (`list_devices`, then the answer as plain text) and never called `say`. The swapped `handle_request` did nothing with `result.output` ("the model speaks through the say tool; nothing is spoken here"), so no cmd reached the chat device, nothing was logged, and the harness reported `FAIL: devices-question - harness-chat: no list_devices or say cmd within 30s`. D-05's stated purpose for this paid call is to "confirm the swap changed nothing observable on the wire"; the first attempt observed a change, and this fix restores the pre-swap contract that every `$robot` question gets a spoken answer.
- **Fix:** `_spoke()` + the delivery fallback and logging in `handle_request`; instructions gain "Answer through say(), not as plain text: players only read game chat"; docstrings updated. RED first (d107778, reproducing the 22:17 shape with a FunctionModel script), then GREEN (bcff617).
- **Files modified:** turtle/turtle-helper/bridge/agent.py, turtle/turtle-helper/tests/test_agent.py, deferred-items.md
- **Verification:** tests 24-26 in tests/test_agent.py (26/26 pass at close-out); the second paid attempt at 22:32 passed with one say cmd 1.9 s after the chat event.
- **Committed in:** d107778, bcff617, 7acdc5b

**2. [Rule 1 - Bug] Harness false-PASS on the bridge's error-fallback say**
- **Found during:** Before Task 1 (carried in from 02-04's deferred item; the plan's post-swap re-run touches this scenario)
- **Issue:** `devices-question` printed PASS on any `say` frame, including `Sorry <user>, something went wrong: BadRequestError` (observed 21:02 during 02-04). A 400 from the API read as a pass.
- **Fix:** `is_error_fallback()` recognising `bridge.on_event`'s catch-all shape (unchanged by the swap: `handle_request` lets exceptions propagate to that handler); the chat branch now requires a non-empty, non-fallback say text and exits 1 otherwise.
- **Files modified:** turtle/turtle-helper/harness/scenarios.py, turtle/turtle-helper/tests/test_harness_scenarios.py (new), deferred-items.md
- **Verification:** 5/5 TAP checks pass at close-out, including the verbatim 21:02 fallback text (rejected) and the 21:09 real answer (accepted).
- **Committed in:** 0b9cbea, 2fb724d

**3. [Rule 3 - Blocking] Task 3 setup ownership and plan-text corrections**
- **Found during:** Task 3
- **Issue:** The plan has the executor leave the bridge and worker running for Task 4 and later "stop the background processes"; subagent processes do not outlive their return (same as 02-04). The plan also names `--scenario status-command` for the worker side, whose 5 s window cannot be the worker of a paid run, and the operator's own bridge held 8765.
- **Fix:** The executor verified the swapped bridge boots and a worker registers on PORT=8766 (acceptance criterion met as evidence) and stopped its processes; the operator ran the bridge, the worker with `--scenario devices-question` (60 s hold), and the chat terminal. The "stop the background processes" clause of Task 4's verification is not applicable.
- **Files modified:** none
- **Verification:** The 22:32 run connected first try and the model saw the worker (its answer describes a worker computer).
- **Committed in:** n/a

**4. [Rule 2 - Missing/incorrect docs] README rows describing the pre-Phase-2 design corrected; `## Harness` placed as its own H2**
- **Found during:** Task 1
- **Issue:** The plan asks only to append a Harness section, but the Layout row, the Protocol example (`sort_chest` cmd), "Adding a chore", the `run_lua` knob line and "Next chores" still described on-device composition and `DEVICE_TOOLS` (removed in 02-01/02-05). Leaving them would have made the new section contradict the page it sits on. The section was placed as its own H2 after the whole Setup block rather than inside "Setup > 1. Bridge".
- **Fix:** Corrected those rows in the same commit; likewise CLAUDE.md's "Current state" sorting and MODEL bullets were brought to the bridge-side reality while the "Lua not yet run in game" statement was kept verbatim.
- **Files modified:** turtle/turtle-helper/README.md, turtle/turtle-helper/CLAUDE.md
- **Verification:** Plan verify greps for Tasks 1 and 2 pass at close-out.
- **Committed in:** f33c938, a2b4f46

---

**Total deviations:** 4 (2 Rule 1 bugs, 1 Rule 3 blocking, 1 Rule 2 docs). File list widened beyond the plan's README.md / CLAUDE.md to harness/scenarios.py, tests/test_harness_scenarios.py, bridge/agent.py, tests/test_agent.py and deferred-items.md.
**Impact on plan:** Deviation 1 is the substantive one: without it the phase's proof would have been a failed paid run, and the in-game round trip in Phase 4 would have dropped answers whenever Haiku chose prose over the tool. Deviation 2 makes the proof trustworthy. No scope creep beyond correctness.

## Issues Encountered

- The first post-swap paid attempt failed (see Deviation 1), costing one paid call over D-05's budget; the operator approved the third call.
- Port 8765 was held by the operator's bridge when the executor ran Task 3, so boot evidence was gathered on PORT=8766.
- The bridge logger is unconfigured under the TAP runner; test 24 raises it to INFO for the test's duration (restored after) so its log-line assertion can observe the "answer for ..." line.

## Authentication Gates

None. The paid call is a `blocking-human` checkpoint by design (T-02-07a), resolved by the operator running `--spend` in their own terminal; the executor never ran it.

## User Setup Required

None - no external service configuration required beyond the operator's existing `.env`.

## Next Phase Readiness

- Phase 02's requirement set is proven: HARN-01..04 and RESIL-03..05 via the free scenarios and TAP suites (02-03/02-02), HARN-02 twice (02-04 pre-swap, this plan post-swap); CR-01/WR-01/WR-02 closed in 02-02, WR-03 superseded by the swap (a tool exception now becomes a tool error to the model or the on_event fallback, and `histories` is only replaced after a successful run).
- For Phase 3/4: the observed post-swap answer did not name `harness-worker` explicitly ("a worker computer and a chat computer"); the harness only checks for a non-fallback say. Whether the model should be nudged to name device ids is a product question for the in-game phase, not a defect here.
- For Phase 4: the reply-delivery contract is now "the model may speak via say during the run; if it does not, the bridge whispers the final output to the requester". The bridge log line `answer for <user> (spoken via say | plain text, not spoken by the model): ...` tells which path fired; worth reading on the first in-game run.
- For Phase 5 (DOC-02): CLAUDE.md's "Lua not yet run in game" line and README's Harness section are the anchors to update once real devices have connected.
- Phase complete (7/7 plans); phase completion itself is the orchestrator's after verification.

## Self-Check: PASSED

- Files: README.md, CLAUDE.md, 02-07-post-swap-transcript.log, 02-04-pre-swap-transcript.log all present on disk (`[ -f ]`).
- Commits: 0b9cbea, f33c938, a2b4f46, 2fb724d, d107778, bcff617, 7acdc5b, ed354d3 all resolve (`git cat-file -e`); `git rev-list --count 8d36444..HEAD` = 8 before the metadata commit.
- Plan verify greps for Tasks 1 and 2 re-run at close-out: pass. `tests/test_agent.py` 26/26, `tests/test_harness_scenarios.py` 5/5.
- Transcript: `PASS: devices-question` x1, `"tool": "say"` x1, `"type":"result"` x1 (ok:true), close 1000.

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-25*

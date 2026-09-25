---
phase: 02-fake-device-harness-protocol-resilience
plan: 04
subsystem: testing
tags: [harness, devices-question, paid-call, spend-guard, transcript, HARN-02, D-05, D-15, claude-haiku-4-5]

# Dependency graph
requires:
  - phase: 02-fake-device-harness-protocol-resilience
    provides: "02-03: the harness package, the devices-question scenario with its --spend guard and its 60 s worker-hold branch; 02-02: the resilient bridge the run was made against; 02-01: client.lua's primitive caps the fake worker advertises"
  - phase: 01-bridge-environment
    provides: "The operator's real .env (ANTHROPIC_API_KEY, BRIDGE_TOKEN, ALLOWED_PLAYERS, MODEL) and the hand-rolled agent loop in bridge/agent.py that this run proves before the Pydantic AI swap"
provides:
  - "02-04-pre-swap-transcript.log: verbatim wire log of the pre-swap paid devices-question run (chat event out, say cmd in naming harness-worker, result ok:true, close 1000, PASS: devices-question, exit 0), with a commented provenance header"
  - "HARN-02 proven against today's hand-rolled agent loop with one completed real model call (first of the phase's two budgeted paid calls, D-05)"
  - "Two observations for later plans: the devices-question scenario passes on the bridge's error-fallback say text (false positive, fix in 02-07), and the model's say call carried to: null (carry into 02-05's typed say tool)"
affects: [02-05 agent core (say tool `to` field), 02-07 post-swap devices-question run and transcript comparison, 02 code review, 04 in-game round trip]

# Actuals (#2632) - same estimateTokens scale as the plan's estimate (chars/4 over the realized diff)
actuals:
  tokens: 660
  tasks: 2
  commits: 1
plan_head_before: cb69bd36350e4741ba2c37cc22261e7bd156bb35

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Paid runs are a human act: the executor never runs --spend; the operator runs it in their own terminal and the transcript is the artifact the plan commits"
    - "Long-lived processes a paid run depends on (bridge, worker hold) are owned by the operator's terminals, not by a subagent whose background jobs die when it returns"
    - "Saved transcripts carry a commented `#` provenance header (time, model, commit, which terminal ran what, which earlier attempts are not part of the proof) above a verbatim body"

key-files:
  created:
    - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-04-pre-swap-transcript.log
  modified:
    - .planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/deferred-items.md

key-decisions:
  - "Task 1's bridge and worker-hold processes were started by the operator in their own terminals, not by an executor: a subagent's background processes do not outlive its return, and a bridge started from the orchestrator's session was killed by a session restart (two --spend attempts hit WinError 1225 for that reason, with no API call made)"
  - "The worker side of the paid run is `uv run harness --role worker --scenario devices-question` (the 60 s hold branch 02-03 added), not the plan text's `--scenario status-command`, whose 5 s window would have exited before the chat run"
  - "Both paid runs (02-04 and 02-07) use claude-haiku-4-5 via the operator's local .env MODEL setting (already recorded in STATE.md; not re-added here) so 02-07's wire comparison is like-for-like"

patterns-established:
  - "The transcript body is never edited after capture; provenance and caveats go in the `#` header so Plan 02-07 can diff the wire lines directly"

requirements-completed: [HARN-02]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Saved pre-swap transcript shows the full devices-question exchange: outbound `$robot what devices are connected?` chat event, inbound `say` cmd, `result ok:true` reply, `close 1000`, and `PASS: devices-question` with exit 0"
    requirement: HARN-02
    verification:
      - kind: manual_procedural
        ref: "operator: cd turtle/turtle-helper && uv run harness --role chat --scenario devices-question --spend (2026-09-24 21:09 local) -> PASS: devices-question, exit 0"
        status: pass
      - kind: other
        ref: "grep -q 'PASS: devices-question' && grep -q '\"tool\": \"say\"' && grep -q '\"type\":\"result\",\"cid\":\"a50ed22a\",\"ok\":true' 02-04-pre-swap-transcript.log -> TRANSCRIPT_VERIFIED"
        status: pass
    human_judgment: false
  - id: D2
    description: "The model's spoken answer is a correct devices answer: it names the connected `harness-worker` computer and its chest access and says no turtles are connected, rather than the bridge's error fallback"
    requirement: HARN-02
    verification:
      - kind: manual_procedural
        ref: "transcript line 19/21: 'Right now I only see one computer, \"harness-worker\", which can list and access a connected chest, plus the chat interface. No turtles or sorting network are hooked up at the moment.'"
        status: pass
    human_judgment: true
    rationale: "The harness asserts only that a say cmd arrived (it passed the 21:02 BadRequestError fallback too); whether the text actually answers the question is read by a human until 02-07 tightens the scenario"

# Metrics
duration: 7 min (close-out continuation; the paid run itself was 2026-09-24 21:09 local, checkpoint open since 2026-09-23)
completed: 2026-09-25
status: complete
---

# Phase 02 Plan 04: Paid devices-question run, pre-swap Summary

**HARN-02 proven against the pre-swap hand-rolled agent loop with one real claude-haiku-4-5 call: the harness's `$robot what devices are connected?` event came back as a `say` cmd naming `harness-worker`, and the verbatim transcript is saved for Plan 02-07's post-swap wire comparison.**

## Performance

- **Duration:** 7 min for this close-out continuation (2026-09-25T04:12:51Z to 2026-09-25T04:19Z). The checkpoint itself was open from 2026-09-23T20:32Z until the operator's successful run on 2026-09-24 21:09 local.
- **Started:** 2026-09-25T04:12:51Z (continuation dispatch)
- **Completed:** 2026-09-25T04:19:00Z
- **Tasks:** 2 of 2 (Task 1 performed by the operator, Task 2 a resolved `blocking-human` checkpoint)
- **Files modified:** 2 (1 created, 1 appended)

## Accomplishments

- First of the phase's two budgeted paid calls (CONTEXT.md D-05) made deliberately by the operator with `--spend` (D-15), against the pre-swap loop at repo HEAD `cb69bd3`, MODEL=claude-haiku-4-5.
- Transcript saved at `02-04-pre-swap-transcript.log` and committed unedited: hello (token redacted by the harness), chat event, `say` cmd `a50ed22a` with the devices answer, `result ok:true`, `close 1000`, `PASS: devices-question`.
- The plan's `<verification>` re-run on the file: `PASS: devices-question` present, `say` cmd and `result` exchange present (`TRANSCRIPT_VERIFIED`). No `list_devices` cmd appears on the chat side because `list_devices` is a bridge-local tool, not a device cmd; the harness's `list_devices or say` expectation was satisfied by the `say` directly.
- Two real findings captured for downstream plans (see Issues Encountered and Next Phase Readiness).

## Task Commits

1. **Task 1: Start the real bridge and a long-held worker harness connection** - no commit (no file changes; performed in the operator's terminals, see Deviations)
2. **Task 2: Human-triggered paid devices-question run (pre-swap)** - `7006e6c` (docs: save pre-swap devices-question transcript)

**Plan metadata:** see the final `docs(02-04): complete ...` commit.

## Files Created/Modified

- `.planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-04-pre-swap-transcript.log` - Verbatim wire log of the successful run with a commented provenance header (capture time, model, commit, terminals, and the earlier attempts that are not part of the proof). Body untouched; Plan 02-07 diffs against it.
- `.planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/deferred-items.md` - Appended "From plan 02-04": the devices-question false positive and the `to: null` observation, with the suggested fixes and their natural homes.

## Decisions Made

- **Setup ownership moved to the operator.** Task 1's bridge and worker processes ran in the operator's own terminals (C and A). A subagent's background processes do not outlive its return, and the bridge the orchestrator started from its own session was killed by a session restart. The acceptance criteria (bridge listening, worker registered and held) were met observably: the chat run connected, the model saw `harness-worker`, and the run passed.
- **Worker side uses the devices-question hold branch.** `uv run harness --role worker --scenario devices-question` holds for 60 s auto-answering cmds; the plan text's `status-command` exits after 5 s and could not have been connected when the chat run started.
- **Model is claude-haiku-4-5 for both paid runs.** Already recorded as a Phase 02 decision in STATE.md after the 21:02 attempt; Plan 02-07 must use the same model. The `.env` MODEL edit was an in-place replace made with the operator's explicit approval; no secret value was printed and nothing in the repo changed (`.env.example` still says `claude-sonnet-5`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1 processes owned by the operator's terminals, not an executor**
- **Found during:** Task 1 (Start the real bridge and a long-held worker harness connection)
- **Issue:** The plan has the executor start `bridge.py` and the worker harness in the background and "leave both running for Task 2". A subagent's background jobs end when it returns, and a bridge started from the orchestrator session died on a session restart, so the operator's first two `--spend` attempts failed with `[WinError 1225] The remote computer refused the network connection` (no bridge on 8765; no API call made).
- **Fix:** The operator started the bridge (terminal C) and the worker hold (terminal A) themselves, then ran the chat scenario (terminal B). Same two-terminal recipe as D-02, with a human owning the long-lived processes.
- **Files modified:** none
- **Verification:** The successful 21:09 run connected on the first try and the model's answer names `harness-worker`, which is only possible with the bridge listening and the worker registered.
- **Committed in:** n/a (no file changes)

**2. [Rule 1 - Bug] Plan's worker command corrected to the devices-question hold branch**
- **Found during:** Task 1
- **Issue:** `uv run harness --role worker --scenario status-command` exits after status-command's 5 s window, so Task 1's own acceptance criterion ("worker harness process is still running when this task completes") could not hold and the paid run would have found no worker.
- **Fix:** Worker side ran `--scenario devices-question`, the 60 s worker-hold branch Plan 02-03 added for exactly this purpose (02-03 key decision; D-02 recipe).
- **Files modified:** none (plan-text correction only; the transcript header records the command actually used)
- **Verification:** Transcript line 19: the model reports `harness-worker` connected.
- **Committed in:** n/a

**3. Plan `<verification>` clause "stop the background bridge and worker harness processes started in Task 1" not applicable**
- **Found during:** Task 2 verification
- **Issue:** Those processes belong to the operator's terminals, not to this executor; per the continuation brief this executor starts and stops nothing.
- **Fix:** Skipped. The operator closes their own terminals.
- **Files modified:** none

---

**Total deviations:** 3 (1 blocking/ownership, 1 plan-text bug, 1 verification clause not applicable). None changed harness or bridge code; `files_modified` stays empty as planned.
**Impact on plan:** None on the proof. Plan 02-07 (the post-swap paid run) should be written with the operator owning the bridge and worker processes from the start, and with the worker on `--scenario devices-question`.

## Issues Encountered

- **Two refused-connection attempts (no spend).** `[WinError 1225]` because no bridge was listening on 8765 (see Deviation 1). No request reached the API.
- **21:02 attempt: API 400, account out of credit (MODEL=claude-sonnet-5).** `bridge.py` caught the `BadRequestError` and sent its fallback `say("Sorry DisraSenkovi, something went wrong: BadRequestError")`. The operator topped up the account and switched MODEL to `claude-haiku-4-5` for the remaining paid runs.
- **Harness false positive.** On that 21:02 attempt the harness still printed `PASS: devices-question`, because `devices_question` (`harness/scenarios.py` lines 260-264) only checks that a `say` cmd arrived and prints its text; it never inspects the text. The scenario should fail when the say text is the bridge's "something went wrong" fallback (or, better, when it does not name a connected device id). Not fixed here (this plan modifies no code); logged in `deferred-items.md` for Plan 02-07 or the phase code-review pass.
- **Transcript provenance.** The successful run's output was transcribed from the operator's terminal into the log file by the orchestrator, with the caveats above in a `#` header. The body is the wire lines verbatim; the hello token was redacted by the harness itself.

## Authentication Gates

None. The `blocking-human` checkpoint was a spend gate, not an auth gate: the operator had valid credentials and the only human step was deliberately triggering the paid call.

## User Setup Required

None - no external service configuration required. The run used the operator's existing Phase 1 `.env`.

## Next Phase Readiness

- **Plan 02-07 (post-swap run):** compare its transcript line-for-line against `02-04-pre-swap-transcript.log` (chat event, a `say` cmd with an answer naming `harness-worker`, `result ok:true`, `close 1000`). Use MODEL=claude-haiku-4-5 again. Tighten `devices_question` first so the error-fallback text cannot pass (see Issues Encountered). Have the operator own the bridge and worker-hold terminals from the start.
- **Plan 02-05 (typed Pydantic AI tools):** the model's `say` call carried `"to": null`, so the reply broadcast instead of addressing the asker. Make `to` required in the typed `say` tool, or default it to the requesting player.
- **Spend ledger:** one of the phase's two budgeted paid calls is used (one completed model call; the 21:02 attempt was rejected by the API with 400 before any completion). One remains for 02-07.
- Plans 02-05 and 02-06 are unblocked (they depend on 02-03/02-04 only through the saved transcript, which now exists).

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-25*

## Self-Check: PASSED

- transcript exists on disk; deferred-items.md exists; commit 7006e6c present
- commits measured from ledger cb69bd36350e4741ba2c37cc22261e7bd156bb35: 1 (matches frontmatter)

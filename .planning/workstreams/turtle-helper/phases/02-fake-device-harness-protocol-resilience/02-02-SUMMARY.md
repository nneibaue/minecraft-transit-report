---
phase: 02-fake-device-harness-protocol-resilience
plan: 02
subsystem: bridge
tags: [websockets, asyncio, pydantic-settings, resilience, tdd, tap]

# Dependency graph
requires:
  - phase: 01-bridge-environment
    provides: bridge/bridge.py on websockets.asyncio.server, typed Settings with the allowed_players min_length guard, the 01-REVIEW findings CR-01/WR-01/WR-02
provides:
  - handler() hello path with four distinct rejection outcomes (expected hello 4000, hello missing id 4000, bad token 4001, stale same-id socket closed 4000 "replaced") whose log lines name the reason, remote address and device id but never the token value (D-16)
  - Same-id reconnect replaces the stale registry entry; the stale handler's cleanup never deregisters its replacement (D-11, closes WR-01)
  - send_cmd() returns {ok: False, error: "<id> disconnected during command"} instead of raising ConnectionClosed; pending and the new pending_by_device index are cleared on every exit path (D-10)
  - fail_pending(device_id, error) resolves only one device's in-flight futures; called from the disconnect cleanup and from the replacement path
  - Message loop logs one WARNING and continues on invalid JSON, non-object JSON, unknown cid, unknown type, or any per-frame exception (D-12, closes WR-02)
  - Settings.bridge_token has min_length=1, so BRIDGE_TOKEN= fails at startup (CR-01)
  - tests/test_bridge_resilience.py: 11 zero-spend in-process checks with a dependency-free TAP runner
affects: [02-03 harness scenarios (wrong-token, drop-reconnect, garbage-frame), 02-06 Python sort_chest composition over send_cmd, 02-05 agent rewrite (on_event unchanged)]

# Actuals (#2632) — same estimateTokens scale as the plan's estimate (chars/4 over the realized diff)
actuals:
  tokens: 5985
  tasks: 3
  commits: 5
plan_head_before: 038efa1282ed07043b73c3fe39a1aeb00b23561b

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Rejection logging names reason + remote address + claimed device id; secrets are never interpolated into log lines"
    - "Register-then-close on same-id reconnect, with socket-identity guard in finally so a stale handler cannot deregister its replacement"
    - "Reverse index pending_by_device: dict[str, set[str]] alongside pending, cleaned on every send_cmd exit and on disconnect"
    - "Per-frame try/except with log-and-continue inside the websocket read loop; the loop ends only when the socket does"
    - "Dependency-free tests: plain test_* coroutines driven with a FakeWs, run as a script that emits TAP (pytest-collectable later)"

key-files:
  created:
    - turtle/turtle-helper/tests/test_bridge_resilience.py
  modified:
    - turtle/turtle-helper/bridge/bridge.py
    - turtle/turtle-helper/bridge/settings.py

key-decisions:
  - "Tests are a dependency-free script emitting TAP rather than a pytest suite: PROJECT.md defers pytest to v1.1, the plan's tdd=true tasks still need committed RED tests, and the gsd RED-evidence gate parses TAP; the test_* functions are pytest-collectable when v1.1 adds it"
  - "The D-11 replacement path fails the old socket's in-flight commands itself (fail_pending) and the finally cleanup runs only when the socket is still the registered one, so a slow stale-handler exit can never fail commands already sent over the replacement"
  - "On same-id reconnect the new socket is registered before the old one is closed (RESEARCH's D-11 sample order) so the device is never unregistered while the best-effort close of a possibly-dead socket waits"
  - "A non-object hello (valid JSON that is not a dict) is rejected as 'expected hello' instead of raising AttributeError outside the try block — the hello half of WR-02"

patterns-established:
  - "Rejection log line shape: 'rejected <remote>: <reason>' before the device id is known, 'rejected device <id> from <remote>: <reason>' after"
  - "Disconnect error payload shape: {ok: False, error: '<id> disconnected'} from cleanup, '<id> disconnected during command' from a failed send"

requirements-completed: [RESIL-03, RESIL-04, RESIL-05]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Hello validation: non-hello type, missing id and bad token each close with their own code/reason and one WARNING that names the remote address (and device id once known) but never the token value; BRIDGE_TOKEN= is rejected at startup"
    requirement: RESIL-04
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_non_hello_type_closes_4000_expected_hello"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_hello_without_id_closes_4000_missing_id"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_bad_token_closes_4001_and_never_logs_token"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_empty_bridge_token_rejected_by_settings"
        status: pass
    human_judgment: false
  - id: D2
    description: "Same-id reconnect closes the old socket 4000 'replaced', logs one INFO line naming the device, keeps the new entry registered after the stale handler exits, and fails the old socket's in-flight commands"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_same_id_reconnect_replaces_stale_socket"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_replaced_connection_fails_its_in_flight_commands"
        status: pass
    human_judgment: false
  - id: D3
    description: "send_cmd never raises ConnectionClosed to its caller, indexes each in-flight cid under its device, and leaves pending and pending_by_device empty after success, timeout, or disconnect"
    requirement: RESIL-03
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_send_cmd_returns_error_when_send_raises_connection_closed"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_send_cmd_tracks_pending_cid_per_device_until_resolved"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_send_cmd_timeout_clears_pending_and_device_index"
        status: pass
      - kind: other
        ref: "plan 02-02 Task 2 <verify>: uv run python - <<PYEOF ... print('D10_OK') (printed D10_OK, exit 0)"
        status: pass
    human_judgment: false
  - id: D4
    description: "A garbage frame, a non-object frame, a result with an unknown cid, or an unknown type each log one WARNING naming the device (payload truncated to 200 chars) and the connection keeps processing later frames"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_malformed_frames_are_logged_and_loop_continues"
        status: pass
    human_judgment: false
  - id: D5
    description: "A device disconnect resolves only that device's pending futures with {ok: False, error: '<id> disconnected'}; another device's pending command is untouched"
    requirement: RESIL-03
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_disconnect_resolves_only_that_devices_pending_futures"
        status: pass
    human_judgment: false
  - id: D6
    description: "RESIL-05 (disallowed player ignored, logged, no model call): declared by this plan but its code path (on_event's allowed_players check and the 'ignoring <user> (not allowed)' line) is untouched here"
    requirement: RESIL-05
    verification: []
    human_judgment: true
    rationale: "No change in this plan; the live proof is plan 02-03's disallowed-player harness scenario, which greps the existing log line"

# Metrics
duration: 12min
completed: 2026-09-23
status: complete
---

# Phase 02 Plan 02: Bridge Protocol Resilience Summary

**bridge.py's hello handshake now rejects with distinct codes and token-free log lines, same-id reconnects replace the stale socket, send_cmd fails cleanly on disconnect via a per-device pending index, malformed frames are logged and skipped, and an empty BRIDGE_TOKEN fails at startup — all proven by 11 zero-spend in-process tests**

## Performance

- **Duration:** 12 min
- **Started:** 2026-09-23T19:51:04Z
- **Completed:** 2026-09-23T20:03:00Z
- **Tasks:** 3 (two TDD, one auto)
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- `handler()` hello path split into four sequential checks (D-16): non-hello type or no hello within 10 s closes 4000 "expected hello", missing id closes 4000 "hello missing id", token mismatch closes 4001 "bad token". Each logs one WARNING naming the remote address and, once known, the claimed device id; the submitted token value never appears in any log line. Non-object hello JSON is rejected instead of raising.
- Same-id reconnect (D-11, closes WR-01): the new socket is registered, one INFO line names the device, the old socket is closed 4000 "replaced" best-effort, and the old handler's `finally` deregisters only when the entry still points at its own socket.
- `send_cmd()` (D-10, RESIL-03): `send` and the result wait share one try/except; `ConnectionClosed` returns `{ok: False, error: "<id> disconnected during command"}`; the new `pending_by_device: dict[str, set[str]]` index is filled on registration and emptied in `finally` alongside `pending`, dropping empty sets.
- `fail_pending(device_id, error)` resolves exactly one device's in-flight futures. It runs from the disconnect cleanup (guarded by socket identity) and from the replacement path, so no ordering of a stale handler's exit can touch commands sent over the replacement.
- Message loop (D-12, closes WR-02): invalid JSON, non-dict JSON, a result with a missing/unknown cid, an unknown type, and any other per-frame exception each log one WARNING (payload truncated to 200 chars) and `continue`; the loop ends only when the socket does.
- `Settings.bridge_token` gets `min_length=1` (CR-01): `BRIDGE_TOKEN=` now raises `ValidationError` at startup exactly like an empty `ALLOWED_PLAYERS`.
- `tests/test_bridge_resilience.py`: 11 checks driving `handler()` and `send_cmd()` with a `FakeWs`, no network, no model call, no new dependency; `uv run python tests/test_bridge_resilience.py` emits TAP and exits non-zero on failure.

## Task Commits

Each task was committed atomically (TDD tasks as RED then GREEN; no REFACTOR commit was needed — the GREEN implementations needed no cleanup pass):

1. **Task 1: Hello validation rewrite, stale-socket replacement, CR-01**
   - RED `00b2fe7` (test) — five failing tests; RED evidence `RED_EVIDENCE_OK`, re-verified against the pre-fix code after a test-capture fix
   - GREEN `2031f4f` (feat)
2. **Task 2: send_cmd catches ConnectionClosed, per-device pending index**
   - RED `aa0ec38` (test) — three failing tests; RED evidence `RED_EVIDENCE_OK` (target test failed with `ConnectionClosed` escaping `send_cmd`)
   - GREEN `0c122a1` (feat)
3. **Task 3: Malformed-frame handling, disconnect-triggered cleanup** — `6d13be6` (feat, with three tests)

**Plan metadata:** see the `docs(02-02)` commit that adds this file.

## TDD Gate Compliance

RED (`test(02-02)`) precedes GREEN (`feat(02-02)`) for both `tdd="true"` tasks (`00b2fe7` → `2031f4f`, `aa0ec38` → `0c122a1`). Both RED runs were persisted and classified `RED_EVIDENCE_OK` by `gsd_run check tdd-red-evidence` (target tests `test_bad_token_closes_4001_and_never_logs_token` and `test_send_cmd_returns_error_when_send_raises_connection_closed`). No REFACTOR commit — none needed.

## Files Created/Modified

- `turtle/turtle-helper/bridge/bridge.py` — `pending_by_device` index, `fail_pending()`, hello path rewrite with D-16 logging and D-11 replacement, disconnect-safe `send_cmd`, log-and-continue message loop, guarded `finally` cleanup
- `turtle/turtle-helper/bridge/settings.py` — `bridge_token` gains `min_length=1`
- `turtle/turtle-helper/tests/test_bridge_resilience.py` — `FakeWs`, `capture_logs`, 11 `test_*` coroutines/functions, TAP runner

## Decisions Made

- **Dependency-free TAP test script instead of pytest.** PROJECT.md defers the pytest suite to v1.1 and the Rule-3 exclusion forbids adding packages as an auto-fix, yet the plan's `tdd="true"` tasks require committed RED tests and the gsd RED gate parses TAP `# tests/# pass/# fail` plus `not ok N - name` lines. Plain `test_*` functions with a 25-line runner satisfy all three and become pytest-collectable for free later.
- **`fail_pending` runs from the replacement path, not only from `finally`.** The plan put cleanup in `finally` and told me to keep the socket-identity guard; combining the two naively would either skip cleanup for a replaced socket (guard true only for the live socket) or, if unguarded, let a slow stale-handler exit fail commands already sent over the replacement. Having the new connection fail the old socket's commands before closing it, and guarding the `finally`, is correct under every ordering. `pending_by_device` bookkeeping structure was explicitly Claude's discretion (RESEARCH "Claude's Discretion").
- **Register the new socket before closing the old one.** `ServerConnection.close()` can wait up to `close_timeout` (10 s) on a dead peer; registering first keeps the device reachable during that wait and is the order RESEARCH's D-11 sample uses. The plan text said "close then register" — the observable contract (old closed 4000 "replaced", new registered, one INFO line) is identical and is what the tests assert.
- **Non-dict hello handled in the first check.** WR-02 named the hello handshake as one of the two AttributeError sites; the plan's Task 1 only listed the type check, so `isinstance(hello, dict)` was folded into it (Rule 2 below).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Non-object hello JSON rejected instead of crashing the handler**
- **Found during:** Task 1 (hello validation rewrite)
- **Issue:** WR-02 lists `hello.get("type")` on a non-dict `json.loads` result as an uncaught `AttributeError`; the plan's four checks assumed `hello` is a dict
- **Fix:** First check is `not isinstance(hello, dict) or hello.get("type") != "hello"`, logging the Python type name when it is not a dict, closing 4000 "expected hello"
- **Files modified:** `turtle/turtle-helper/bridge/bridge.py`
- **Verification:** ruff + mypy clean; covered by the same code path `test_non_hello_type_closes_4000_expected_hello` exercises
- **Committed in:** `2031f4f`

**2. [Rule 2 - Missing Critical] Hello-timeout / unparseable-hello path gets its own WARNING line**
- **Found during:** Task 1
- **Issue:** D-16 requires a separate log line "for no hello within 10 seconds"; the plan's action listed only the four post-parse checks, leaving the pre-existing silent `except Exception: close(4000)` path unlogged
- **Fix:** `log.warning("rejected %s: no valid hello within 10s (%s)", remote, type(exc).__name__)` before the existing close
- **Files modified:** `turtle/turtle-helper/bridge/bridge.py`
- **Verification:** ruff + mypy clean (not unit-tested: the path needs a 10 s wait)
- **Committed in:** `2031f4f`

---

**Total deviations:** 2 auto-fixed (2 missing critical)
**Impact on plan:** Both are D-12/D-16 requirements the plan's action text omitted; no scope change.

## Issues Encountered

- **Test log capture read nothing on the first GREEN run.** The TAP runner sets the root logger to CRITICAL to keep bridge log lines off stdout, and the `bridge` logger inherited that level, so `capture_logs` saw no WARNING records. Fixed by setting the logger level explicitly (and `propagate = False`) inside `capture_logs`. Because that changed the test, RED was re-established against the committed pre-fix code (`git show HEAD:…` into the working tree, run, restore) and re-classified `RED_EVIDENCE_OK` before proceeding — the corrected target test fails on the intended reason (no device id in the old log line).
- **Replacement-log assertion was too loose:** it matched any INFO line containing "replac", which also caught the stale handler's "replacement stays registered" exit line. Tightened to the "replacing stale" line; the replacement event is logged exactly once as the behavior requires.
- Requirement IDs RESIL-03/04/05 are shared with sibling plans in this phase (the harness scenarios), so `requirements.ready-ids` reported 0/3 ready and they were not marked complete here; they flip when the last declaring plan finishes.

## Known Stubs

None — every behavior added is wired and exercised; no placeholder values or TODOs were introduced.

## Threat Flags

None beyond the plan's register. `pending_by_device` growth (T-02-02b) is bounded by the `finally` cleanup and `fail_pending`; no new endpoints, auth paths, or file access were added.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02-03 (harness) can exercise every outcome here live: wrong token → 4001 with a "rejected device <id> from <addr>: bad token" line; empty `BRIDGE_TOKEN=` → startup `config error: bridge_token: …`; drop mid-command → the agent gets `{ok: False, error: "<id> disconnected"}` immediately instead of waiting out `cmd_timeout`; reconnect under the same id → one "replacing stale connection" INFO line; garbage frame → one "ignoring malformed JSON from <id>" WARNING and the device stays registered.
- `send_cmd`'s contract for 02-06's Python `sort_chest` composition: every call returns a dict with `ok`; it never raises `ConnectionClosed` and never hangs past `cmd_timeout`.
- Deferred (out of scope, logged in `deferred-items.md`): `asyncio.create_task(on_event(...))` keeps no task reference; natural home is the 02-05/02-06 agent rewrite.

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-23*

## Self-Check: PASSED

Files created/modified exist on disk; task commits 00b2fe7, 2031f4f, aa0ec38, 0c122a1, 6d13be6 present; commits measured from plan_head_before ledger = 5.

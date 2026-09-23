---
phase: 02-fake-device-harness-protocol-resilience
plan: 03
subsystem: testing
tags: [harness, websockets, asyncio, argparse, fake-device, wire-log, spend-guard, D-01, D-04, D-14, D-15]

# Dependency graph
requires:
  - phase: 02-fake-device-harness-protocol-resilience
    provides: "02-01: client.lua's primitive tool set (the caps and canned shapes the fake worker mirrors); 02-02: distinct hello close codes (4000/4001), same-id replacement (4000 'replaced'), log-and-continue on malformed frames, non-empty bridge_token"
  - phase: 01-bridge-environment
    provides: "bridge/settings.py Settings (host, port, bridge_token, command_prefix, allowed_players) that the harness imports; the websockets 17 asyncio API"
provides:
  - "turtle/turtle-helper/harness/ package: FakeDevice (connect, send_event, send_raw, build_reply, envelope, run, expect, expect_close, expect_no_close, ping, close, clone), log_wire (D-04 one-line compact JSON with the hello token redacted), SpendGuard (D-15), ScenarioArgs, the argparse CLI and `uv run harness` script entry"
  - "Six named scenarios in harness/scenarios.py: hello-handshake, status-command, drop-and-reconnect, wrong-token, disallowed-player, devices-question; exit 0 pass / 1 fail / 2 refused"
  - "Live proofs against the real bridge with zero API spend: HARN-01, HARN-03, HARN-04, RESIL-03 (concurrency half), RESIL-04 (wrong and empty token), RESIL-05"
  - "HARN-02's devices-question scenario fully defined and gated behind --spend, with a worker-side hold branch so the D-02 two-terminal recipe works for Plan 02-04's paid run"
affects: [02-04 paid devices-question run, 02-05/02-06 agent swap (harness never imports bridge.agent), 02-07 post-swap re-run and README Harness section, 04 in-game round trip]

# Actuals (#2632) - same estimateTokens scale as the plan's estimate (chars/4 over the realized diff)
actuals:
  tokens: 8480
  tasks: 3
  commits: 3
plan_head_before: ea2d90c4b1f396cbcfec40ecaa4e70dbf85a785a

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Harness imports bridge.settings only; every other bridge behaviour is observed over the wire"
    - "Wire log: `<timestamp> <device id> -> or <- <compact JSON>`; the hello token is the one redacted field"
    - "Bounded waits everywhere: expect()/expect_close()/expect_no_close() all take a timeout; 'hello accepted' is proven by absence of a close within a window"
    - "Close codes surface as a synthetic {type: close, code, reason} frame on the device's queue, read from ws.close_code after the reader loop ends"
    - "Spend guard in two layers: the scenario refuses before connecting, and FakeDevice.send_event refuses a prefixed chat event from an allowed player without --spend"
    - "Scenarios are plain async (dev, args) functions registered in a dict; failures are exceptions, main() turns them into a one-line verdict and exit code"

key-files:
  created:
    - turtle/turtle-helper/harness/__init__.py
    - turtle/turtle-helper/harness/harness.py
    - turtle/turtle-helper/harness/scenarios.py
  modified:
    - turtle/turtle-helper/pyproject.toml

key-decisions:
  - "Exit code 2 (REFUSED) is distinct from 1 (FAIL): a spend-guard refusal, unknown scenario or config error is not a protocol failure, and Plan 02-04's operator should not read it as one"
  - "The spend guard is enforced inside FakeDevice.send_event as well as in the devices-question scenario, so no future scenario can send a paid event by accident"
  - "devices-question has a worker-role branch that holds the connection for 60s auto-answering cmds: status-command's 5s window cannot be the worker side of a paid run, and D-02 says to start the worker first"
  - "Device ids are fixed (harness-chat / harness-worker) and reconnects use FakeDevice.clone(); no --id flag, per CONTEXT.md's 'nothing else' on flags"
  - "The verdict line prints after the local close so a pasted transcript reads in wire order"
  - "Ran every live check on PORT=8766 via the environment override because the operator's own bridge still held 8765; the harness reads host/port from Settings, so both sides agreed without touching .env"

patterns-established:
  - "Scenario docstrings state the requirement they prove and, where the harness cannot see it, the bridge log line a human greps (D-16)"
  - "Canned worker replies come from build_reply() keyed on role + --turtle, never on the caps list, so a direct assertion needs no connection"

requirements-completed: [HARN-01, HARN-02, HARN-03, HARN-04, RESIL-03, RESIL-04, RESIL-05]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "Harness package, CLI and wire log: `uv run harness --help` works with no Settings() call; log_wire prints D-04 lines with the hello token redacted; hello-handshake completes against the real bridge"
    requirement: HARN-01
    verification:
      - kind: other
        ref: "uv run harness --help -> EXIT:0 HELP_OK"
        status: pass
      - kind: unit
        ref: "python -c log_wire('dev-1','out',{hello with SUPER-SECRET-SENTINEL-0001}) -> TOKEN_REDACTED_OK"
        status: pass
      - kind: integration
        ref: "PORT=8766 uv run harness --role chat --scenario hello-handshake -> PASS, HARNESS_EXIT:0 (bridge log: device connected: harness-chat (chat) caps=['say'])"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fake worker mirrors client.lua: caps equal the sorted primitive list (computer and --turtle), build_reply shapes for status/list_chest/push_one_slot/unknown tool and the five turtle tools, envelope() matches session()'s result frame; registers live"
    requirement: HARN-03
    verification:
      - kind: unit
        ref: "plan 02-03 Task 2 <verify> build_reply script -> BUILD_REPLY_OK"
        status: pass
      - kind: integration
        ref: "PORT=8766 uv run harness --role worker --scenario status-command (and --turtle) -> PASS x2, exit 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "drop-and-reconnect: malformed frame ignored with the device still registered (probe event + ping + no close), local drop and same-id reconnect accepted, third same-id connection closes the stale socket 4000 'replaced' while the replacement stays registered"
    requirement: HARN-04
    verification:
      - kind: integration
        ref: "PORT=8766 uv run harness --role worker --scenario drop-and-reconnect -> PASS, exit 0; bridge log shows 'ignoring malformed JSON from harness-worker', 'replacing stale connection', 'stale connection for harness-worker closed; replacement stays registered'"
        status: pass
    human_judgment: false
  - id: D4
    description: "wrong-token: a wrong value and an empty value both close 4001 'bad token'; the token value never appears in the harness wire log or the bridge log"
    requirement: RESIL-04
    verification:
      - kind: integration
        ref: "uv run harness --role chat --scenario wrong-token --token wrong-value-0001 -> PASS (T1:0); --token \"\" -> PASS (T2:0); grep -c wrong-value-0001 bridge log = 0"
        status: pass
    human_judgment: false
  - id: D5
    description: "disallowed-player: a prefixed chat event from a name outside ALLOWED_PLAYERS produces no cmd and no close for 5s; the bridge logs 'ignoring harness-nobody (not allowed)'"
    requirement: RESIL-05
    verification:
      - kind: integration
        ref: "uv run harness --role chat --scenario disallowed-player -> PASS (T3:0); bridge log line 'ignoring harness-nobody (not allowed)' present"
        status: pass
    human_judgment: false
  - id: D6
    description: "RESIL-03 concurrency guarantee: the same-id replacement affects only the one device id being replaced (stale socket 4000, replacement untouched); leak-freedom itself was proven in-process by Plan 02-02"
    requirement: RESIL-03
    verification:
      - kind: integration
        ref: "drop-and-reconnect two-connection step -> 'stale socket closed 4000, replacement stayed registered'"
        status: pass
    human_judgment: false
  - id: D7
    description: "devices-question definition and spend guard: chat role refuses with exit 2 and sends nothing without --spend; worker role holds the connection 60s; with --spend it sends the scripted event from the first allowed player and expects a say cmd within 30s"
    requirement: HARN-02
    verification:
      - kind: other
        ref: "uv run harness --role chat --scenario devices-question (no --spend) -> EXIT:2, REFUSED line, no wire lines"
        status: pass
      - kind: integration
        ref: "PORT=8766 uv run harness --role worker --scenario devices-question -> PASS after 60s hold (T4:0)"
        status: pass
    human_judgment: true
    rationale: "The --spend path was deliberately never run here (D-05/D-15 spend guard); whether the pre-swap agent loop actually answers with a say cmd is proven by the paid run in Plan 02-04, which a human triggers"

# Metrics
duration: 13min
completed: 2026-09-23
status: complete
---

# Phase 02 Plan 03: Fake Device Harness Summary

**A `uv run harness` CLI whose FakeDevice mirrors chat.lua/client.lua over the real wire protocol, prints every frame as one redacted D-04 line, and proves the hello handshake, canned worker replies, malformed-frame tolerance, drop/reconnect/same-id replacement, wrong- and empty-token rejection, and disallowed-player silence live against the real bridge with zero API spend; the paid devices-question scenario is defined and refuses to run without `--spend`**

## Performance

- **Duration:** 13 min
- **Started:** 2026-09-23T20:14:42Z
- **Completed:** 2026-09-23T20:27:42Z
- **Tasks:** 3
- **Files modified:** 4 (3 created, 1 modified)

## Accomplishments

- `harness/harness.py`: `FakeDevice` opens `ws://{settings.host}:{settings.port}` with `websockets.asyncio.client.connect`, sends the hello (`chat` / `computer` / `turtle` with `--turtle`), runs a background reader that logs, queues and auto-answers every frame, and exposes bounded `expect` / `expect_close` / `expect_no_close` plus `send_event`, `send_raw`, `ping`, `close` and `clone`. `build_reply` returns client.lua's data shapes (`status` with `fuel` only on a turtle, `list_chest`, `push_one_slot {moved}`, the five turtle tools, `unknown tool <name>`), chat.lua's `say` result and `base only supports say`, and a `list_devices` entry for either role; `envelope` wraps them exactly as `session()` does.
- `log_wire` prints `<timestamp> <device id> -> | <- <compact JSON>`; a hello frame's `token` is replaced by `***` before printing and every other field of every other frame prints verbatim. The only place the harness ever shows a token is that placeholder.
- CLI: `--role`, `--scenario` (choices from the registry), `--turtle`, `--spend`, `--token` are parsed before `Settings()` so `--help` needs no `.env`; verdict `PASS:` / `FAIL: <name> - <reason>` / `REFUSED: ...` with exit 0 / 1 / 2. `[project.scripts] harness = "harness.harness:main"` and the wheel `packages` list make `uv run harness` work with no `sys.path` workaround.
- `harness/scenarios.py`: six scenarios registered by kebab-case name. All five free ones passed live against the real bridge (started by this executor on port 8766), and the bridge log for each run shows the D-12, D-11, D-16 and RESIL-05 lines the phase's success criteria name.
- `SpendGuard` (D-15) in two layers: `devices-question` refuses before connecting without `--spend`, and `FakeDevice.send_event` independently refuses a prefixed chat event from an allowed player, so no scenario can spend by accident.

## Task Commits

1. **Task 1: Harness skeleton (FakeDevice, wire log, CLI, hello-handshake)** - `bfed9f7` (feat) — tracer task; its three `<verify>` blocks were re-run after the final edits (HELP_OK, TOKEN_REDACTED_OK, live PASS) before expansion
2. **Task 2: Worker role (status-command, drop-and-reconnect with malformed frame and same-id replacement)** - `f385399` (feat)
3. **Task 3: Chat role (wrong-token incl. empty, disallowed-player, gated devices-question, list_devices reply)** - `423eba8` (feat)

**Plan metadata:** see the `docs(02-03)` commit that adds this file.

## Files Created/Modified

- `turtle/turtle-helper/harness/__init__.py` - package marker
- `turtle/turtle-helper/harness/harness.py` - `FakeDevice`, `log_wire`, `SpendGuard`, `ScenarioArgs`, `ScenarioError` / `SpendRefusedError`, CLI `main()`
- `turtle/turtle-helper/harness/scenarios.py` - the six scenario coroutines and `SCENARIOS`
- `turtle/turtle-helper/pyproject.toml` - `[project.scripts] harness`, `packages = ["bridge", "harness"]`

## Live evidence (all on `PORT=8766`, bridge started and stopped by this executor)

| Scenario | Result | Bridge log line observed |
|---|---|---|
| `hello-handshake` (chat) | PASS, exit 0 | `device connected: harness-chat (chat) caps=['say']` |
| `status-command` (computer and `--turtle`) | PASS x2, exit 0 | `device connected: harness-worker (turtle) caps=['dig', 'inspect', 'list_chest', 'move', 'push_one_slot', 'refuel', 'status', 'turn']` |
| `drop-and-reconnect` (worker) | PASS, exit 0 | `ignoring malformed JSON from harness-worker: this is not json {` / `device harness-worker reconnected ...: replacing stale connection` / `stale connection for harness-worker closed; replacement stays registered`; harness saw `{"type":"close","code":4000,"reason":"replaced"}` on the stale socket |
| `wrong-token --token wrong-value-0001` | PASS, exit 0 | `rejected device harness-chat from ('127.0.0.1', ...): bad token`; 0 occurrences of the value in the log |
| `wrong-token --token ""` | PASS, exit 0 | same 4001 `bad token` line |
| `disallowed-player` | PASS, exit 0 | `ignoring harness-nobody (not allowed)`; no cmd for 5 s |
| `devices-question` (chat, no `--spend`) | REFUSED, exit 2 | nothing sent (no wire lines) |
| `devices-question` (worker) | PASS after 60 s hold, exit 0 | `device connected: harness-worker (computer) ...` |

ruff (`E,F,W,I,N,UP,B,C4`), `ruff format --check` and mypy (`disallow_untyped_defs`, pydantic plugin) are clean on `bridge/`, `harness/` and `tests/`. `uv run python tests/test_bridge_resilience.py` from 02-02 is untouched.

## Decisions Made

- **Exit code 2 for refusals.** D-14 fixes 0/1 for pass/fail; RESEARCH reserved higher codes for harness errors. A spend refusal, unknown scenario name or `Settings` validation error returns 2 so a transcript never confuses "I declined to spend" with "the protocol broke".
- **Two-layer spend guard.** The plan put the `args.spend` check in the scenario; `FakeDevice.send_event` also consults a `SpendGuard` built from `settings.allowed_players` / `settings.command_prefix`, matching T-02-03a's "code-enforced" wording so the property holds for every future scenario, not just this one.
- **Synthetic close frame.** websockets' async iteration ends silently on 1000 and raises `ConnectionClosedError` on 4xxx; reading `ws.close_code` / `ws.close_reason` in the reader's `finally` and queueing `{type: close, code, reason}` gives scenarios one uniform way to await either.
- **Consumed non-matching frames.** `expect()` drops frames that fail its predicate (they stay in `dev.seen`); `disallowed-player` therefore waits on `cmd OR close` so a bridge-initiated close during the silence window is a failure, not a silent pass.
- **Device ids fixed, `clone()` for reconnects.** `harness-chat` / `harness-worker`; a turtle is still `harness-worker` with role `turtle`. No `--id` flag was added (CONTEXT.md: role, scenario, `--spend`, `--turtle`, token override, nothing else).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] `devices-question` gained a worker-role hold branch**
- **Found during:** Task 3 (devices-question definition)
- **Issue:** D-02's recipe says to start the worker in the second terminal first, but the only worker scenario (`status-command`) disconnects after a 5 s window — shorter than a real model round trip — so Plan 02-04's paid run would have had no worker registered when `list_devices` ran.
- **Fix:** `devices_question` with `--role worker` connects with client.lua's caps and holds the connection for `WORKER_HOLD` (60 s), auto-answering any cmd, then passes. It sends no chat event, so it needs no `--spend` and cannot spend. The chat-role branch is exactly the plan's: refuse without `--spend`, otherwise send the scripted event and expect `say` within 30 s.
- **Files modified:** `turtle/turtle-helper/harness/scenarios.py`
- **Verification:** live run on 8766: `PASS: devices-question` after the hold, exit 0; the no-`--spend` chat run still exits 2 and sends nothing
- **Committed in:** `423eba8`

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Additive; no acceptance criterion changed. Plan 02-04's recipe is `uv run harness --role worker --scenario devices-question` in terminal 2, then `uv run harness --role chat --scenario devices-question --spend` in terminal 1.

## Issues Encountered

- **Port 8765 was busy** with the operator's hand-started bridge from the checkpoint. Per the continuation instructions the executor never touched that process; every bridge instance and harness run here used `PORT=8766` exported in the same shell (pydantic-settings lets a real environment variable override the `.env` value). The bridge log confirms `host=127.0.0.1:8766`.
- **ruff N818** required the exception names `ScenarioError` / `SpendRefusedError` instead of the plan-neutral `ScenarioFailed` / `SpendRefused`; renamed before the Task 1 commit.
- One Bash invocation over the ~8 KB limit was rejected before parsing (no partial effect); the file was written with the Write tool instead.
- The tracer gate (Task 1, `type="tracer"`, interactive run with `human_verify_mode=end-of-phase` and automated-only `<verify>`) re-ran all three verifies after the final edits and continued without a checkpoint.

## Known Stubs

None. The canned reply values (`pos {0,64,0}`, two chest peripherals, `moved 64`, `fuel 1000`) are the fake device's deliberate D-03 stand-ins for hardware, not placeholders awaiting data; the shapes are what the bridge consumes.

## Threat Flags

None beyond the plan's register. T-02-03a is mitigated in two layers (scenario + `send_event`); T-02-03c holds (every `expect*` and the connect carry a timeout; the longest bounded wait is the 60 s worker hold); T-02-03b unchanged (`--token` never touches `.env` and `log_wire` redacts the hello token whatever its value).

## User Setup Required

None - no external service configuration required. Plan 02-04's paid run needs the same `.env` the operator already created.

## Next Phase Readiness

- **Plan 02-04 (paid run, pre-swap):** terminal 2 `uv run harness --role worker --scenario devices-question` (holds 60 s), then terminal 1 `uv run harness --role chat --scenario devices-question --spend`. The chat side expects a `list_devices` or `say` cmd within 30 s and passes on `say`; the wire log lines it prints are safe to paste (hello token redacted). If the operator's bridge is on a non-default port, export `PORT` for the harness too.
- **Plans 02-05/02-06 (agent swap):** the harness imports only `bridge.settings`; nothing here changes when `bridge.agent` is rewritten. `build_reply` already answers `list_devices` on either role should the new loop forward it.
- **Plan 02-07 (README/CLAUDE.md):** document the six scenarios, the three exit codes, `--turtle`, `--token ""`, the two-terminal recipe above, and that the RESIL-05 / D-16 proofs also grep the bridge terminal.
- Requirement IDs HARN-02 (and any others also declared by 02-04..02-07) are subject to the shared-ID gate; see the requirements step outcome in the metadata commit.

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-23*

## Self-Check: PASSED

- `turtle/turtle-helper/harness/__init__.py`, `harness/harness.py`, `harness/scenarios.py` exist on disk and are tracked; `pyproject.toml` modification committed.
- Commits `bfed9f7`, `f385399`, `423eba8` present in `git log`.
- `commits: 3` measured via `git rev-list --count ea2d90c..HEAD` at SUMMARY time; working tree clean for every file this plan touched.

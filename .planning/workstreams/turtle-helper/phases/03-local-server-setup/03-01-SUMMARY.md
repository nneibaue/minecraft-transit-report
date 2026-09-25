---
phase: 03-local-server-setup
plan: 01
subsystem: infra
tags: [deploy, cc-tweaked, pydantic-settings, toml, launcher, tap-tests]

requires:
  - phase: 01-bridge-environment
    provides: Settings model with .env resolved from the source file, [project.scripts] precedent
  - phase: 02-fake-device-harness-protocol-resilience
    provides: harness.py CLI shape (build_parser before Settings, exit 2 on config error), dependency-free TAP test layout
provides:
  - "uv run deploy: idempotent 127.0.0.1 allow rule in computercraft-server.toml, gated on a stopped server"
  - "Marker-file opt-in placement of chat.lua, client.lua, startup.lua, secret.txt, bridge.txt into world/computercraft/computer/<id>/"
  - "uv run launch: bridge and run.bat in their own console windows (operator-only)"
  - "Settings.server_dir (optional; blank SERVER_DIR= is None)"
affects: [03-02, 03-03, 03-04, 04-first-in-game-run, 05-docs]

actuals:
  tokens: 8890
  tasks: 3
  commits: 4
plan_head_before: 5b62322f710e6593de75fb05fe35449ee08a36fc

tech-stack:
  added: []
  patterns:
    - "Text-level TOML insertion that keeps the file's own line endings (open with newline='')"
    - "Server-running gate by TCP probe of the game port, not world/session.lock"
    - "Byte-exact device file writes (shutil.copy2 / write_bytes), never text-mode writes"
    - "Launcher tests patch subprocess.Popen to raise, so no test can start a live process"

key-files:
  created:
    - turtle/turtle-helper/deploy/__init__.py
    - turtle/turtle-helper/deploy/deploy.py
    - turtle/turtle-helper/deploy/rules.py
    - turtle/turtle-helper/deploy/server_state.py
    - turtle/turtle-helper/deploy/launcher.py
    - turtle/turtle-helper/tests/test_deploy_rules.py
    - turtle/turtle-helper/tests/test_deploy_files.py
  modified:
    - turtle/turtle-helper/bridge/settings.py
    - turtle/turtle-helper/pyproject.toml
    - turtle/turtle-helper/.env.example

key-decisions:
  - "Blank SERVER_DIR= maps to None via a BeforeValidator; pydantic-settings otherwise parses it as Path('.') and deploy would treat the cwd as the server root"
  - "insert_allow_rule reads and writes with newline='' and matches the anchor in the file's own line ending, so a Windows text-mode write never rewrites every LF in computercraft-server.toml to CRLF"
  - "launcher opens each process with CREATE_NEW_CONSOLE instead of cmd /c start <title>: subprocess argv quoting cannot produce the quoted title start needs, so start would have tried to run a program named Bridge"
  - "Marked folders sort numeric ids numerically (5 before 10), non-numeric names after, so the reboot list reads in id order"
  - "Marker file is _marker.txt; bridge URL file is bridge.txt (D-03/D-06 discretion, per RESEARCH.md recommendation)"

patterns-established:
  - "deploy CLI mirrors harness.py: build_parser() before Settings(), config error -> exit 2, step failure -> exit 1"
  - "Every deploy-written file is overwritten on every run: Lua edits, token rotation and hand-edited startup.lua all converge on one re-run"

requirements-completed: [SRV-01, SRV-02, SRV-03, SRV-04]

coverage:
  - id: D1
    description: "Idempotent 127.0.0.1 allow rule inserted before the $private deny, skipped while the server runs, ValueError on a missing anchor, line endings preserved"
    requirement: SRV-01
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_deploy_rules.py (tests 1-5, 8-12)"
        status: pass
      - kind: other
        ref: "plan Task 1 <automated> IDEMPOTENT_OK script; uv run deploy twice against a temp fixture SERVER_DIR (md5 identical after run 2)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Game-port TCP probe decides whether the server is running"
    requirement: SRV-01
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_deploy_rules.py#test_server_probe_is_false_when_nothing_listens, #test_server_probe_is_true_when_the_port_accepts"
        status: pass
    human_judgment: false
  - id: D3
    description: "Marker-only placement of byte-identical chat.lua/client.lua plus startup.lua, token-only secret.txt, ws://127.0.0.1:8765 bridge.txt; unmarked folders untouched; idempotent; token never printed"
    requirement: SRV-03
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_deploy_files.py (10 tests)"
        status: pass
      - kind: other
        ref: "uv run deploy twice against a temp fixture with computers 0 (unmarked), 3, 12 and a dummy BRIDGE_TOKEN: md5 identical, computer 0 untouched, token absent from output"
        status: pass
    human_judgment: false
  - id: D4
    description: "Per-computer folder path world/computercraft/computer/<id>/ on the real server (SRV-02)"
    requirement: SRV-02
    verification: []
    human_judgment: true
    rationale: "Only fixtures were used here; the path is confirmed against the real server by Plans 03-03/03-04 after the first in-game file write creates it"
  - id: D5
    description: "startup.lua relaunches chat or client on reboot (SRV-04)"
    requirement: SRV-04
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_deploy_files.py#test_startup_lua_detects_role_and_is_always_overwritten"
        status: pass
    human_judgment: true
    rationale: "The script's content is proven here, but rebooting into the right role is observable only on a real CC:Tweaked device (Phase 3 later plans / Phase 4)"
  - id: D6
    description: "uv run launch builds the bridge and run.bat commands and refuses without SERVER_DIR or run.bat, spawning nothing"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_deploy_rules.py (tests 13-15)"
        status: pass
    human_judgment: true
    rationale: "launcher.main() is never run by an agent (live-run rule); the operator opens the two windows the first time they use it"

duration: 8min
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 01: Deploy Engine Summary

**`uv run deploy` adds the CC:Tweaked 127.0.0.1 allow rule once, only while the server is stopped, and places byte-identical Lua, a role-detecting startup.lua, a token-only secret.txt and a bridge.txt into marker-opted computer folders. `uv run launch` opens the bridge and run.bat side by side. Everything was proven against temp fixtures only.**

## Performance

- **Duration:** about 8 min
- **Started:** 2026-09-25T08:44:26Z
- **Completed:** 2026-09-25T08:52:30Z
- **Tasks:** 3
- **Files modified:** 10 (7 created, 3 modified)

## Accomplishments
- The tracer slice runs end to end: Settings.server_dir, then rules.py, then server_state.py, then the `deploy` CLI. The real `uv run deploy` ran twice against a fixture SERVER_DIR: the first run inserted the rule, the second left the file byte-identical, and LF line endings were kept.
- Marker-scan file placement is proven on fixtures. Re-runs are byte-identical, a token rotation converges, unmarked folders are never touched, and the token shows up in no output stream.
- A minimal launcher with a pure command builder. No test can spawn a process, because `subprocess.Popen` is patched to raise.
- 25 new zero-network TAP checks (15 in test_deploy_rules.py, 10 in test_deploy_files.py). All six test suites pass, and ruff and mypy are clean on bridge/, harness/, deploy/ and tests/.

## Task Commits

1. **Task 1: Settings.server_dir, TOML rule logic, server-running gate, CLI skeleton** (tracer): `d4d2c23` (feat)
2. **Task 2: Marker scan and file placement** (TDD):
   - RED: `d04dde0` (test). 10 failing tests plus signature-only stubs.
   - GREEN: `fb9995c` (feat)
   - REFACTOR: none needed
3. **Task 3: Minimal launcher**: `f159cc5` (feat)

## Files Created/Modified
- `turtle/turtle-helper/deploy/deploy.py`: the `uv run deploy` entry point, with the allow-rule step, marker scan, per-folder placement and summary table
- `turtle/turtle-helper/deploy/rules.py`: `rule_already_present`, `insert_allow_rule` (idempotent, anchor-checked, keeps line endings)
- `turtle/turtle-helper/deploy/server_state.py`: `is_server_running` (TCP probe of port 25565)
- `turtle/turtle-helper/deploy/launcher.py`: `build_launch_commands` (pure) and the operator-only `main()`
- `turtle/turtle-helper/deploy/__init__.py`: package marker
- `turtle/turtle-helper/bridge/settings.py`: optional `server_dir`, with blank mapped to None
- `turtle/turtle-helper/pyproject.toml`: `deploy` and `launch` scripts; `deploy` added to the wheel packages
- `turtle/turtle-helper/.env.example`: `SERVER_DIR=` documented
- `turtle/turtle-helper/tests/test_deploy_rules.py`, `tests/test_deploy_files.py`: TAP tests

## Tracer Feedback Gate

The run was interactive with `human_verify_mode=end-of-phase`, and the tracer's `<verify>` is automated-only, so the checkpoints.md rule for that case applied (row 3). Both `<automated>` commands were re-run and passed (IDEMPOTENT_OK; EXIT:0 + HELP_OK), so the plan went on to the remaining tasks with no checkpoint.

## TDD Gate Compliance

- RED `d04dde0` came before GREEN `fb9995c`. The RED evidence record (target `test_deploy_writes_byte_identical_lua_copies`, exit 1, 10/10 failing on assertions) was checked by `gsd-tools check tdd-red-evidence` and came back `RED_EVIDENCE_OK`.
- The RED commit also added signature-only stubs to deploy.py (they return `[]` and write nothing). Without them the RED run would have been an import error, which the checker classifies as INVALID_RED.

## Decisions Made
See `key-decisions` in the frontmatter. In brief: blank SERVER_DIR is None, the toml's line endings are kept, the launcher uses CREATE_NEW_CONSOLE, ids sort numerically, and the file names are `_marker.txt` and `bridge.txt`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Blank `SERVER_DIR=` parsed as `Path('.')`**
- **Found during:** Task 1
- **Issue:** pydantic-settings 2.15 turns an empty env value into `Path('.')`, not None. The `.env.example` default (`SERVER_DIR=`) would therefore have pointed deploy at the current working directory.
- **Fix:** added a `blank_to_none` BeforeValidator (`OptionalPath = Annotated[Path | None, ...]`). The field is still typed `Path | None` with default None.
- **Files modified:** turtle/turtle-helper/bridge/settings.py
- **Verification:** empty, whitespace, unset and real-path values now parse to None, None, None and the path
- **Committed in:** d4d2c23

**2. [Rule 1 - Bug] `write_text` would have turned the toml's line endings into CRLF**
- **Found during:** Task 1
- **Issue:** the plan specified `read_text`/`write_text`. On Windows a text-mode write turns every `\n` into `\r\n`, which would rewrite the line endings of the whole real `computercraft-server.toml`.
- **Fix:** read and write with `newline=""`, detect the file's own line ending, and match the anchor and insert the block in that ending.
- **Files modified:** turtle/turtle-helper/deploy/rules.py
- **Verification:** `test_crlf_file_keeps_crlf_line_endings`; the fixture CLI run kept LF (checked with `cat -A`)
- **Committed in:** d4d2c23

**3. [Rule 1 - Bug] `cmd /c start Bridge ...` would not open a titled window**
- **Found during:** Task 3
- **Issue:** `start` reads its first argument as a window title only when it is quoted, and subprocess's argv quoting leaves `Bridge` unquoted. The plan's literal argv would have made `start` try to run a program named `Bridge`.
- **Fix:** `subprocess.Popen(cmd, cwd=..., creationflags=subprocess.CREATE_NEW_CONSOLE)` for each process. Also added two refusals, each exiting with code 2 before anything is spawned: a missing `run.bat`, and a non-Windows platform.
- **Files modified:** turtle/turtle-helper/deploy/launcher.py
- **Verification:** 3 launcher TAP tests, plus a one-off check that the patched `Popen` really is reached (and so intercepted) when the configuration is valid
- **Committed in:** f159cc5

**4. [Plan inconsistency] test_deploy_rules.py created in Task 1**
- Task 3 says the file was "created by Task 1", but Task 1's `<files>` list omits it. I created it in Task 1 with 12 rules/probe/CLI tests, and Task 3 extended it.

**5. [Discretion] Numeric-aware ordering of marked folders**
- The plan says to sort by folder name. I sort numeric ids numerically (5 before 10), so the order is still deterministic but reads in id order. Non-numeric names sort after the numeric ones.

---

**Total deviations:** 3 auto-fixed bugs (Rule 1), 1 plan-inconsistency resolution, 1 discretionary ordering choice.
**Impact on plan:** each fix stops the code from silently doing the wrong thing on the real Windows server. No scope creep.

## Issues Encountered
- Git Bash's `/tmp` is not visible to Windows Python. The RED evidence output was therefore re-captured in the session scratchpad before the checker could read it.
- A stale `.git/gsd-plan-head-before-03-01` from the default workstream's own phase 03 (dated 2026-09-08) was already present. The commit ledger for this plan went to `.git/gsd-plan-head-before-turtle-helper-03-01` so the other file was left alone.

## User Setup Required
None for this plan. `SERVER_DIR` must be set in `.env` before the real-server plans (03-03/03-04) run `uv run deploy`.

## Next Phase Readiness
- Plan 03-02 (Lua amendments: read bridge.txt, label-or-id naming, first `git add` of base/chat.lua) can go ahead. deploy already copies whatever `base/chat.lua` and `turtle/client.lua` hold on disk.
- Plans 03-03/03-04 point `uv run deploy` at the real SERVER_DIR. The server must be stopped for the allow-rule step, and every marked device needs a reboot afterwards.
- Git's CRLF conversion (`core.autocrlf`) affects checked-out Lua. deploy copies the working-tree bytes, so the LOOP-05 diff against the working tree stays clean either way.

## Self-Check: PASSED
- All 10 key files found on disk
- Commits d4d2c23, d04dde0, fb9995c, f159cc5 found in git log

---
*Phase: 03-local-server-setup*
*Completed: 2026-09-25*

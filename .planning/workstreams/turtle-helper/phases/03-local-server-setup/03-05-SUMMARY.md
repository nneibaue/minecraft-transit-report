---
phase: 03-local-server-setup
plan: 05
subsystem: infra
tags: [computercraft, cc-tweaked, install-lua, startup-lua, live-server, token-isolation, d-19]

# Dependency graph
requires:
  - phase: 03-local-server-setup
    provides: "03-04's install.lua (wget run installer) and repo startup.lua (boot-time update, role launch)"
  - phase: 03-local-server-setup
    provides: "03-03's live allow rule for 127.0.0.1 in computercraft-server.toml"
provides:
  - "Device A (computer 0, chat role) installed from GitHub main with only the wget line and the typed token, auto-launching chat after reboot and connected to the bridge as device-0"
  - "Confirmed per-computer folder path <SERVER_DIR>/world/computercraft/computer/<numeric id>/ (SRV-02)"
  - "Verbatim D-13 smoke-check shapes (success, denied, refused) for 03-06's README"
  - "Token-isolation proof: the token exists only in computer/0/secret.txt (SRV-03)"
  - "Developer deploy path removed (D-19): no deploy.py, no deploy script, no _marker.txt skip in startup.lua"
affects: [03-06, phase-04-in-game-round-trip, phase-06-remote-host-setup]

# Actuals (#2632)
actuals:
  tokens: 7400
  tasks: 4
  commits: 2
plan_head_before: 4df20214704ea70a6b4b86c3ad20b427d9262bf7

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One device install path only: in-game wget run install.lua, then startup.lua's boot-time update (D-19)"
    - "Live-server proofs are read-only, in-process Python checks that print paths, ids and counts, never the token"

key-files:
  created: []
  modified:
    - turtle/turtle-helper/startup.lua
    - turtle/turtle-helper/pyproject.toml
    - turtle/turtle-helper/deploy/__init__.py
    - turtle/turtle-helper/deploy/launcher.py
    - turtle/turtle-helper/bridge/settings.py
    - turtle/turtle-helper/.env.example
    - turtle/turtle-helper/tests/test_device_lua.py
    - turtle/turtle-helper/tests/test_deploy_rules.py
  deleted:
    - turtle/turtle-helper/deploy/deploy.py
    - turtle/turtle-helper/tests/test_deploy_files.py

key-decisions:
  - "D-19 applied mid-plan: the developer deploy path (deploy.py, the deploy script, test_deploy_files.py, startup.lua's _marker.txt skip) is deleted; rules.py, server_state.py, launcher.py and test_deploy_rules.py are kept for Phase 6"
  - "launcher.py now defines its own REPO_ROOT instead of importing it from the deleted deploy.py; SERVER_DIR is documented as used by uv run launch"
  - "The per-computer folder is <SERVER_DIR>/world/computercraft/computer/<numeric id>/, confirmed on the live server (device A = computer/0/)"
  - "Device A's startup.lua is the 4df2021 version, which still has the marker skip; it is dead code there (no _marker.txt) and is replaced only by re-running the wget line, since startup.lua does not update itself"

patterns-established:
  - "Checks against the live world compare the token in-process (bytes in / ==) and scan UTF-8 and UTF-16LE, including .gz logs"

requirements-completed: [SRV-01, SRV-02, SRV-03, SRV-04, SRV-05]

coverage:
  - id: D1
    description: "Developer deploy path removed (D-19); remaining host-side helpers, device Lua invariants, lint and types green"
    requirement: SRV-02
    verification:
      - kind: unit
        ref: "uv run python tests/test_deploy_rules.py (10/10) && uv run python tests/test_device_lua.py (10/10, incl. test_no_device_file_knows_a_marker)"
        status: pass
      - kind: other
        ref: "uv run ruff check bridge/ harness/ deploy/ tests/ && uv run mypy bridge/ harness/ deploy/"
        status: pass
      - kind: other
        ref: "luaparse (luaVersion 5.2) over base/chat.lua, turtle/client.lua, startup.lua, install.lua -> LUA_PARSE_OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "Real folder layout confirmed: computer/0/ holds exactly chat.lua, client.lua, startup.lua, bridge.txt, secret.txt, byte-identical to main at 4df2021; bridge.txt is ws://127.0.0.1:8765"
    requirement: SRV-02
    verification:
      - kind: integration
        ref: "scratchpad layout4b.py against Settings().server_dir -> REAL_LAYOUT_OK computer/0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Token isolation: zero hits in repo files, git history and server logs; the only world hit is computercraft/computer/0/secret.txt"
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "scratchpad isolation4c.py -> TOKEN_ISOLATION_OK 1 ['computercraft/computer/0/secret.txt']"
        status: pass
    human_judgment: false
  - id: D4
    description: "Device A installed with only the wget line and typed token, then after reboot startup.lua updated/launched chat on its own and the bridge logged device-0 connected"
    requirement: SRV-04
    verification:
      - kind: manual_procedural
        ref: "Operator's in-game BOOT_OUTPUT and BRIDGE_LOG (Task 3)"
        status: pass
    human_judgment: true
    rationale: "In-game behaviour observed and reported by the operator; no automated check can drive a CC:Tweaked computer"
  - id: D5
    description: "D-13 smoke check run at a real lua prompt with the bridge up: success, denied-address and no-listener shapes captured verbatim"
    requirement: SRV-01
    verification:
      - kind: manual_procedural
        ref: "Operator's SMOKE_OK / SMOKE_DENIED / SMOKE_REFUSED (Task 3)"
        status: pass
    human_judgment: true
    rationale: "Run in game by the operator on a second computer; the text is recorded, not machine-checked"

# Metrics
duration: 20min
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 05: First In-Game Install and Live Proofs Summary

**Computer 0 was set up from GitHub main with one `wget run` line and the typed token. After reboot it started chat on its own and connected as device-0. `computer/<id>/` is confirmed as the real folder path, the token exists only in `computer/0/secret.txt`, and the developer deploy path is gone (D-19).**

## Performance

- **Duration:** about 20 min (including the operator's in-game time)
- **Started:** 2026-09-25T10:48:30Z
- **Completed:** 2026-09-25T11:08:00Z
- **Tasks:** 4 (Task 1 by the orchestrator, Task 3 by the operator)
- **Files modified:** 10 (8 modified, 2 deleted)

## Captured In-Game Text (fixed keys for 03-06)

FOLDER_PATH: `<SERVER_DIR>/world/computercraft/computer/<numeric id>/`, observed as `world/computercraft/computer/0/` for device A (computer id 0). Folder names under `computer/` are numeric ids (`0`, `1`).

DEVICE_A: computer id 0, no label (connects as `device-0`), role chat (Advanced Computer with a Chat Box attached), caps `['say']`

INSTALLER_OUTPUT: not captured. The operator rebooted before copying it. The installed files are confirmed on disk: `computer/0/` holds chat.lua, client.lua, startup.lua, bridge.txt and secret.txt, byte-identical to main at 4df2021.
```
(not captured — operator rebooted first; installed files confirmed on disk)
```

SMOKE_OK: `table: 3c9a6ef1 nil`

SMOKE_DENIED: `Domain not permitted`

SMOKE_REFUSED: `Could not connect`

(Full lines as printed: `false Domain not permitted` and `false Could not connect`. After each, the REPL printed `1`, which is `print`'s return count and not part of the message. The smoke checks ran at the `lua` prompt of a second computer with the bridge running, which D-13 allows.)

BOOT_OUTPUT:
```
CraftOS 1.9
Use the "edit" program to create and edit your programs.
chat.lua up to date
client.lua up to date
[1:11]  connected to bridge
```

BRIDGE_LOG: `bridge: device connected: device-0 (chat) caps=['say']`

## Accomplishments

- Device A (computer 0) was installed on the live server from GitHub main using only the in-game `wget run` line and the typed token. After `reboot`, startup.lua checked chat.lua and client.lua against main ("up to date"), launched chat because a Chat Box is attached, and the bridge logged `device-0 (chat)` connecting. No step was taken on the PC. This covers SRV-04 and the install half of SRV-05.
- The D-13 smoke check ran at a real `lua` prompt. The success, denied-address and refused shapes were captured verbatim for 03-06's README (SRV-01).
- SRV-02 path confirmed (`REAL_LAYOUT_OK computer/0`):
  - `computer/0/` holds exactly chat.lua, client.lua, startup.lua, bridge.txt and secret.txt, with no extra files created by CC.
  - chat.lua and client.lua are byte-identical to the repo and to 4df2021.
  - startup.lua equals 4df2021's version.
  - bridge.txt is exactly `ws://127.0.0.1:8765`.
  - secret.txt equals BRIDGE_TOKEN. This was compared in-process and never printed.
- SRV-03 token isolation (`TOKEN_ISOLATION_OK 1`):
  - 231 repo files (tracked and untracked-unignored), 6.7 MB of `git log --all -p`, 335 world files and 21 server log files were scanned in UTF-8 and UTF-16LE, with .gz files decompressed.
  - The only hit is `computercraft/computer/0/secret.txt`.
- The developer deploy path is removed per D-19. The remaining test suites, ruff, mypy and luaparse are all green.

## Task Commits

1. **Task 1: Push main to GitHub (D-18):** done by the orchestrator (push `5bd01f7..4df2021`). No executor commit.
2. **Task 2: Confirm raw GitHub serves the pushed bytes:** read-only; printed `SAME` for all four files, then `RAW_MATCH_OK`. No commit.
3. **Task 3: In-game install of device A, smoke check, reboot:** done by the operator. No commit.
4. **Task 4 (revised under D-19):**
   - 4a: `4e4861a` (refactor) removes the developer deploy path.
   - 4b and 4c: read-only proofs, no commit.
   - 4d: this SUMMARY.

Commits measured from the ledger base 4df2021: 2. One is `4e4861a`. The other is `29f7d15`, the orchestrator's D-19 CONTEXT docs commit, which falls inside the range but is not plan work.

## Files Created/Modified

- `turtle/turtle-helper/startup.lua`: the `_marker.txt` branch and its header comment are removed, so every device updates chat.lua and client.lua on boot. The validated download with local fallback is unchanged.
- `turtle/turtle-helper/pyproject.toml`: the `deploy = "deploy.deploy:main"` script is dropped; `launch` is kept.
- `turtle/turtle-helper/deploy/__init__.py`: the docstring now describes the host-side helpers that are kept.
- `turtle/turtle-helper/deploy/launcher.py`: defines its own `REPO_ROOT`, since it previously imported it from deploy.py.
- `turtle/turtle-helper/bridge/settings.py`, `.env.example`: SERVER_DIR is now described as required by `uv run launch`.
- `turtle/turtle-helper/tests/test_device_lua.py`: the marker-skip test is replaced by `test_no_device_file_knows_a_marker`, which checks that `_marker` is absent from startup.lua and install.lua.
- `turtle/turtle-helper/tests/test_deploy_rules.py`: the five `deploy.main()` CLI tests, the `run_main` helper and the now-unused `fixture_toml` helper are dropped. The rules, server-probe and launcher tests stay (10 tests).
- Deleted: `turtle/turtle-helper/deploy/deploy.py` and `turtle/turtle-helper/tests/test_deploy_files.py`.

## Decisions Made

- D-19 was applied in this plan's Task 4 rather than in a separate plan, because it removes the device-B half of this plan's own scope.
- Device A's on-device startup.lua was left as the 4df2021 version, which still contains the marker skip. D-19 says this is dead code there and harmless. Re-running the wget line is how a device picks up a new startup.lua.

## Deviations from Plan

### D-19 decision change (plan text lagged the decision)

**1. [Decision change, D-19] The developer deploy path was removed, and device B and `uv run deploy` were dropped from Task 4**
- **Found during:** between Task 3 and Task 4. D-19 was committed as `29f7d15` while the plan file still described Task 4 with device B and `uv run deploy`. A planner is rewriting 03-05-PLAN.md and 03-06-PLAN.md in parallel. This executor did not edit any PLAN file.
- **Deleted:** `deploy/deploy.py`, `tests/test_deploy_files.py`, the `deploy` entry in `[project.scripts]`, and startup.lua's `_marker.txt` skip together with its test.
- **Kept for Phase 6:** `deploy/rules.py`, `deploy/server_state.py`, `deploy/launcher.py` and `tests/test_deploy_rules.py`.
- **Device B dropped:** the second computer (computer id 1) has an empty `_marker.txt` and nothing else in `world/computercraft/computer/1/`. It is no longer part of the phase. Its folder was left untouched. The operator can break that block or ignore it; nothing reads `_marker.txt` any more.
- **Task 4's checks were rewritten:**
  - The layout check now covers only device A and does not run a deploy.
  - The isolation check expects exactly one world hit.
  - The fixed-key list no longer includes DEVICE_B.
- **Committed in:** `4e4861a`

### Auto-fixed Issues

**2. [Rule 3 - Blocking] launcher.py imported REPO_ROOT from the deleted deploy.py**
- **Found during:** Task 4a
- **Issue:** `from deploy.deploy import REPO_ROOT` would break `uv run launch` and `test_deploy_rules.py` once deploy.py was gone.
- **Fix:** launcher.py now defines `REPO_ROOT = Path(__file__).resolve().parent.parent`, the same value as before.
- **Verification:** the three launcher tests pass, and mypy is clean.
- **Committed in:** `4e4861a`

**3. [Rule 3 - Blocking] test_deploy_rules.py imported deploy.deploy and tested its CLI**
- **Found during:** Task 4a
- **Issue:** the kept test file imported `deploy.deploy` and had five `test_main_*` tests of the deleted `deploy.main()`, which covered the allow-rule step's CLI wrapper.
- **Fix:** removed the import, the `run_main` helper, the five tests and the now-unused `fixture_toml` helper. `insert_allow_rule` and `rule_already_present` are still covered directly by the five rules tests.
- **Verification:** 10/10 pass, and ruff is clean.
- **Committed in:** `4e4861a`

---

**Total deviations:** 1 decision change (D-19) and 2 auto-fixed blocking issues.
**Impact on plan:** the scope shrank to one install path. Every remaining proof (SRV-01 smoke text, SRV-02 path, SRV-03 isolation, SRV-04 boot launch, SRV-05 install half) was made on the live server.

## Issues Encountered

- INSTALLER_OUTPUT was not captured because the operator rebooted first. The installed files on disk, which are byte-identical to main, stand in for it.
- `bridge/settings.py` and `.env.example` have CRLF line endings in the working copy (core.autocrlf=true), so the first scripted edit missed them and was reapplied with CRLF-aware matching. There was no content impact.
- The first 4b script run printed secret.txt's byte length alongside the "equals BRIDGE_TOKEN" line. It never printed the content, and the length is not repeated here.

## Requirements

The proofs for SRV-02 (installer path and confirmed folder), SRV-03 (isolation), SRV-04 (reboot relaunch) and the install half of SRV-05 are now complete on the live server. They are not yet marked Complete in REQUIREMENTS.md. `requirements.ready-ids` reports 0 of 5 ready, because 03-06 also declares SRV-01..05 (the #2388 shared-ID gate). They will flip when 03-06's SUMMARY lands. SRV-05's update-on-push proof belongs to 03-06.

## User Setup Required

None. There is one optional cleanup: computer 1 (formerly device B) holds only an empty `_marker.txt` and can be broken or ignored.

## Next Phase Readiness

- 03-06 can use the SMOKE_DENIED text (`Domain not permitted`) and the SMOKE_REFUSED text (`Could not connect`) verbatim, and FOLDER_PATH as observed.
- 03-06 is still pending on two points:
  - chat.lua's and client.lua's Setup comments still say `uv run deploy` writes secret.txt and bridge.txt (03-06 already plans comment-only edits there).
  - README.md and CLAUDE.md still need the D-19 wording, without a developer-shortcut section.
- Device A runs the 4df2021 startup.lua, which still has the marker skip. For 03-06's update proof, only chat.lua and client.lua update on reboot. startup.lua changes need a re-run of the wget line.

---
*Phase: 03-local-server-setup*
*Completed: 2026-09-25*

## Self-Check: PASSED

- Modified files present; deploy.py and test_deploy_files.py deleted; commit 4e4861a found
- All eight fixed keys present at line start; SUMMARY contains no token value (checked in-process)

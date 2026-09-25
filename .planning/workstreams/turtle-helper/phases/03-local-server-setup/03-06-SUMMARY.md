---
phase: 03-local-server-setup
plan: 06
subsystem: infra
tags: [computercraft, cc-tweaked, install-lua, startup-lua, readme, live-server, update-path, d-19]

# Dependency graph
requires:
  - phase: 03-local-server-setup
    provides: "03-05's device A (computer 0) installed from main with the wget line, the observed smoke-check text, FOLDER_PATH, and the D-19 removal of the developer deploy path"
  - phase: 03-local-server-setup
    provides: "03-04's startup.lua boot-time update (validated download, local-copy fallback) and install.lua"
provides:
  - "README.md single-path admin recipe: the one wget line, token/URL/reboot steps, repair, 'Updating' (push + reboot) and 'Smoke check' with the observed text; no second placement path (D-19)"
  - "CLAUDE.md and .env.example aligned: wget + boot-time update dev loop, device-storage sentence, line-1 header convention, deploy/ in the lint list, passphrase note for BRIDGE_TOKEN"
  - "Live proof that push to main + reboot updated device A's chat.lua and client.lua with no PC-side step (SRV-05 update half)"
  - "Repo and full git history still token-free after the docs commit (SRV-03)"
affects: [phase-04-in-game-round-trip, phase-05-docs, phase-06-remote-host-setup]

# Actuals (#2632)
actuals:
  tokens: 3100
  tasks: 5
  commits: 1
plan_head_before: 6b7ab5f951fc8814444c7e0dc408b1733ef77f02

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A docs commit that also carries a comment-only Lua edit doubles as the update payload for a live push-and-reboot proof"
    - "Live update proofs compare device files to origin/main blobs in-process and read file mtimes; they never write to the world and never print the token"

key-files:
  created: []
  modified:
    - turtle/turtle-helper/README.md
    - turtle/turtle-helper/CLAUDE.md
    - turtle/turtle-helper/.env.example
    - turtle/turtle-helper/base/chat.lua
    - turtle/turtle-helper/turtle/client.lua

key-decisions:
  - "The update path is proven by bytes on disk: device A's chat.lua and client.lua equal origin/main (c1a773e), differ from c1a773e~1, and were rewritten at 11:26:26Z, after the payload commit; startup.lua, bridge.txt and secret.txt were untouched since the 10:54:47Z install"
  - "Device A's startup.lua is blob 8db52b5, introduced by 4b4dd67 (03-04) and unchanged at 4df2021: the pre-D-19 version whose marker branch is dead there; it changes only when the wget line is re-run"
  - "The offline fallback was skipped by the operator (skip-offline) and stays judgment-verified from startup.lua's fetch branch plus test_device_lua.py"

patterns-established:
  - "Git calls in live-check scripts run with cwd at the repo top level, because pathspecs after -- are resolved relative to the working directory"

requirements-completed: [SRV-01, SRV-02, SRV-03, SRV-04, SRV-05]

coverage:
  - id: D1
    description: "README.md, CLAUDE.md and .env.example describe one install path (the wget line), the push-and-reboot update and the observed smoke-check text, and no PC-side placement path"
    requirement: SRV-02
    verification:
      - kind: other
        ref: "Task 1 README check -> README_RECIPE_OK"
        status: pass
      - kind: other
        ref: "Task 1 docs grep (git grep for uv run deploy / _marker / developer shortcut) -> DOCS_D19_OK"
        status: pass
    human_judgment: false
  - id: D2
    description: "chat.lua and client.lua carry comment-only Setup updates (the update payload); both parse and keep their line-1 headers"
    requirement: SRV-05
    verification:
      - kind: other
        ref: "Task 1 git diff -U0 origin/main comment-only check -> COMMENT_ONLY_PAYLOAD_OK"
        status: pass
      - kind: unit
        ref: "luaparse (luaVersion 5.2) -> LUA_PARSE_OK; uv run python tests/test_device_lua.py -> 10/10, # fail 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "raw.githubusercontent.com served the pushed install.lua, startup.lua, chat.lua and client.lua before the reboot"
    requirement: SRV-05
    verification:
      - kind: integration
        ref: "Task 3 blob-hash compare of raw URLs vs origin/main -> SAME x4, RAW_MATCH_OK"
        status: pass
    human_judgment: false
  - id: D4
    description: "After the push and a reboot, device A's chat.lua and client.lua equal origin/main and differ from the pre-payload versions, with no PC-side step; secret.txt and bridge.txt unchanged; startup.lua is a version from main; no marker file in any device folder"
    requirement: SRV-05
    verification:
      - kind: integration
        ref: "Task 5 update check (git anchored at repo top) -> UPDATE_PATH_OK installed=['0'], STARTUP_LUA computer/0 matches 4b4dd67"
        status: pass
    human_judgment: false
  - id: D5
    description: "Device A came back up after the reboot and reconnected to the bridge as device-0"
    requirement: SRV-04
    verification:
      - kind: manual_procedural
        ref: "Operator report at Task 4: 'everything looked fine on reboot' (boot lines and bridge line not pasted)"
        status: pass
    human_judgment: true
    rationale: "The reconnect was observed by the operator in game and in the bridge terminal but not pasted; no automated check can read the operator's bridge console or drive a CC:Tweaked computer"
  - id: D6
    description: "No bridge token in any repo file or anywhere in git history after the docs commit"
    requirement: SRV-03
    verification:
      - kind: integration
        ref: "Task 5 in-process repo + git log --all -p scan -> REPO_TOKEN_CLEAN_OK"
        status: pass
    human_judgment: false
  - id: D7
    description: "With GitHub unreachable, startup.lua prints '<file>: <reason>; using the local copy' and still launches the device's program"
    requirement: SRV-05
    verification: []
    human_judgment: true
    rationale: "The operator skipped the optional offline reboot (skip-offline); the fallback is judgment-verified by reading startup.lua's fetch branch and by test_device_lua.py"

# Metrics
duration: 9min
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 06: Single-Path Admin Recipe and Push-and-Reboot Update Proof Summary

**README.md now leads with the one `wget run` install line and documents push-to-main plus reboot as the whole update path, with the smoke-check text observed on the live server. Rebooting device A after the push pulled the new chat.lua and client.lua from main with no PC-side step. Its token and URL were unchanged, and the repo and its history stayed token-free.**

## Performance

- **Duration:** about 9 min of executor time (the push and the operator's in-game reboot happened between executor runs)
- **Started:** 2026-09-25T11:20:35Z
- **Completed:** 2026-09-25T11:29:25Z
- **Tasks:** 5 (Task 2 by the orchestrator, Task 4 by the operator)
- **Files modified:** 5

## Captured Evidence (fixed keys)

UPDATE_PATH_OK: `UPDATE_PATH_OK installed=['0']`. Device A's (computer 0) `chat.lua` and `client.lua` are byte-identical to `origin/main` (c1a773e) and differ from their pre-payload versions (`c1a773e~1`). `secret.txt` still equals BRIDGE_TOKEN and `bridge.txt` is still `ws://127.0.0.1:8765`; both were compared in-process and never printed. No device folder holds a marker file. On-disk mtimes (UTC): `chat.lua` and `client.lua` 11:26:26Z, after the payload commit (11:23:54Z) and the push. `startup.lua`, `bridge.txt` and `secret.txt` are still at 10:54:47Z, the 03-05 install time. Only the two files startup.lua updates were rewritten.

STARTUP_LUA_ON_A: `4b4dd67`, pre-D-19, dead marker branch, harmless. The check printed `STARTUP_LUA computer/0 matches 4b4dd67`. That commit (03-04) introduced blob `8db52b5`, which is the same blob `4df2021`'s tree carries, so this is the startup.lua installed from 4df2021 as expected. The check labels each blob with the commit that introduced it. The only later startup.lua on main is `4e4861a` (D-19, marker branch removed), which device A gets only when the wget line is re-run.

BOOT_A_AFTER_PUSH: the operator reported that the reboot looked fine but did not paste the lines verbatim. The on-disk byte check and mtimes above are the evidence that startup.lua printed `updated chat.lua` / `updated client.lua` rather than `up to date`, since both files were rewritten at the reboot.
```
(not pasted: operator reported "everything looked fine on reboot")
```

BRIDGE_LOG_AFTER_PUSH: not pasted. The operator reported that everything looked fine. The expected line, by 03-05's observed shape, is `bridge: device connected: device-0 (chat) caps=['say']`. It was not seen by this executor.

LEFTOVER_MARKER: left. Computer 1, the former device B, was untouched and still holds only its empty `_marker.txt`, which was confirmed by a read-only listing. It is not a turtle-helper device and nothing reads that file.

OFFLINE_FALLBACK: skip-offline. The operator chose to skip it. The GitHub-unreachable fallback stays judgment-verified: in startup.lua's `fetch()`, every failure (no `http`, a failed `http.get`, a non-200 status, an empty body, a wrong header, a failed compile) returns `nil, reason`, and the loop then prints `<name>: <reason>; using the local copy` and still reaches the `shell.run` role launch. test_device_lua.py pins the header and validation invariants.

REPO_TOKEN_CLEAN_OK: `REPO_TOKEN_CLEAN_OK`. Zero token hits in tracked and untracked-unignored repo files and in `git log --all -p`, scanned after the docs commit c1a773e.

## Accomplishments

- **README "Setup > 2. In game"** is now the single admin path (D-14, D-15, D-17, D-19):
  - It leads with `wget run https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/install.lua`.
  - It then covers the hidden token prompt (first install only), pressing Enter to keep `ws://127.0.0.1:8765`, and `reboot`.
  - It adds a repair paragraph, "#### Updating" (push, wait up to about 5 minutes for raw GitHub's cache, reboot; `updated <file>` / `<file> up to date` / `...; using the local copy`) and "#### Smoke check" with the text observed in 03-05.
  - The paste-by-hand recipe is gone.
- **README "Setup > 1. Bridge"** names `<SERVER_DIR>/world/serverconfig/computercraft-server.toml`, the rule's place before `$private`, editing with the server stopped, and a full restart. It also adds `uv run launch` and the passphrase advice for BRIDGE_TOKEN.
- **CLAUDE.md** now has the wget/boot-update dev loop, the `secret.txt`, `bridge.txt`, `startup.lua` storage sentence, the line-1 header convention, and `deploy/` in the ruff/mypy list. **.env.example** recommends a short, distinctive passphrase.
- **The update half of SRV-05 is proven live.** The orchestrator pushed `4df2021..c1a773e`, raw GitHub served the new bytes, and the operator rebooted device A. Device A then held the new chat.lua and client.lua, and nobody did anything on the PC.
- **SRV-03 re-proven after the docs change.** The repo and all history are token-free.

## Task Commits

1. **Task 1: single-path recipe docs and comment-only Lua payload.** Commit `c1a773e` (docs). README_RECIPE_OK, DOCS_D19_OK, COMMENT_ONLY_PAYLOAD_OK and LUA_PARSE_OK passed, and test_device_lua.py ran 10/10.
2. **Task 2: push main (checkpoint).** Done by the orchestrator: `4df2021..c1a773e`, after which origin/main == HEAD == c1a773e. No executor commit.
3. **Task 3: confirm raw GitHub serves the payload.** Read-only. It printed `SAME` x4 and `RAW_MATCH_OK` on the first attempt. No commit.
4. **Task 4: reboot device A (checkpoint).** Done by the operator, who said "skip-offline, left. everything looked fine on reboot". No commit.
5. **Task 5: prove the update landed and the repo stayed token-free.** Read-only. UPDATE_PATH_OK and REPO_TOKEN_CLEAN_OK passed. No code commit; this SUMMARY is the only output.

The ledger measures 1 commit from base `6b7ab5f`, which is `c1a773e`.

## Files Created/Modified

- `turtle/turtle-helper/README.md`: rewrites "Setup > 2. In game" as the single wget path with repair, Updating and Smoke check, and extends "Setup > 1. Bridge" (toml path, rule placement, full restart, `uv run launch`, passphrase).
- `turtle/turtle-helper/CLAUDE.md`: Dev loop, device-storage sentence, line-1 header convention, `deploy/` in the lint list.
- `turtle/turtle-helper/.env.example`: the BRIDGE_TOKEN comment recommends a typeable passphrase and keeps the `python -c secrets` alternative. The value stays empty.
- `turtle/turtle-helper/base/chat.lua`, `turtle/turtle-helper/turtle/client.lua`: comment-only Setup notes pointing at install.lua and startup.lua. This is the update payload.

## Decisions Made

- The byte comparison against origin/main, plus the file mtimes, is the primary evidence for the reboot, since the operator's boot and bridge lines were not pasted. Only chat.lua and client.lua changed at 11:26:26Z, which is exactly what startup.lua's update loop writes.
- STARTUP_LUA_ON_A is recorded as `4b4dd67`, the commit that introduced the blob and the one the check prints, and cross-checked as identical to 4df2021's startup.lua.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 5's update-check script resolved git pathspecs relative to `turtle/turtle-helper`**
- **Found during:** Task 5, first check
- **Issue:** The script runs from `turtle/turtle-helper`. `git log ... -- turtle/turtle-helper/<file>` reads a pathspec relative to the working directory, so it matched nothing, returned an empty sha, and `git show ~1:...` failed with exit 128. The first assertion (chat.lua == origin/main) had already passed before the failure.
- **Fix:** `git_out` now runs git with `cwd` set to the repo top level (`git rev-parse --show-toplevel`). Two guard asserts check that the looked-up shas are non-empty, and a `PRE_PAYLOAD` line names the parent it compared against. Every assertion from the plan is unchanged.
- **Files modified:** none. The script is inline and was run from the shell, and the PLAN file was not edited.
- **Verification:** the fixed run printed `PRE_PAYLOAD base/chat.lua = c1a773e~1`, `PRE_PAYLOAD turtle/client.lua = c1a773e~1`, `STARTUP_LUA computer/0 matches 4b4dd67` and `UPDATE_PATH_OK installed=['0']`.
- **Committed in:** n/a (read-only check)

### Evidence substitution (operator did not paste lines)

**2. BOOT_A_AFTER_PUSH and BRIDGE_LOG_AFTER_PUSH are the operator's summary report, not verbatim lines**
- **Found during:** Task 4 resume
- **Issue:** Task 5's precondition and one acceptance criterion expect the pasted boot lines (containing `updated chat.lua` and `updated client.lua`) and a pasted `device connected:` line. The operator reported only "everything looked fine on reboot".
- **Handling:** Per the orchestrator's continuation instructions, the precondition was treated as met on the operator's report. Lines the operator did not paste are not reproduced as if observed. The update itself is proven from disk by UPDATE_PATH_OK and the mtimes. The bridge reconnect stays a human-judgment item (coverage D5).

---

**Total deviations:** 1 auto-fixed (blocking check-script bug) and 1 evidence substitution (operator report in place of pasted lines).
**Impact on plan:** None on the outcome. The byte-level proof of the update path is stronger than the pasted text would have been. Only the bridge-reconnect observation rests on the operator's word.

## Issues Encountered

- The operator skipped the optional offline reboot. The fallback stays judgment-verified, as the plan allows.

## Requirements

With 03-04, 03-05 and 03-06 all summarized, the shared-ID gate no longer blocks SRV-01..SRV-05:
- SRV-01: 03-03 live rule and 03-05 smoke text, now documented in the README.
- SRV-02: a single installer path, the confirmed `computer/<id>/` folder, and `reboot` documented.
- SRV-03: token isolation (03-05), re-scanned here.
- SRV-04: reboot relaunch (03-05, and again here).
- SRV-05: one-line install (03-05) and push-plus-reboot update (here).

## User Setup Required

None. There is optional cleanup: computer 1 still holds an empty `_marker.txt` and can be broken or ignored.

## Next Phase Readiness

- All six plans of Phase 3 are complete, so the phase is ready for `/gsd-verify-work 03`.
- Phase 4 can take its first real round trip on device A (computer 0, chat role, device-0). It still needs a worker device installed with the same wget line.
- Device A still runs the pre-D-19 startup.lua until someone re-runs the wget line on it. That is harmless, because it holds no marker file.

---
*Phase: 03-local-server-setup*
*Completed: 2026-09-25*

## Self-Check: PASSED

- All five modified files exist, and commit c1a773e is on HEAD and origin/main
- UPDATE_PATH_OK, STARTUP_LUA_ON_A, BOOT_A_AFTER_PUSH, BRIDGE_LOG_AFTER_PUSH, LEFTOVER_MARKER, OFFLINE_FALLBACK and REPO_TOKEN_CLEAN_OK each start a line, and the SUMMARY contains no token value (checked in-process before commit)

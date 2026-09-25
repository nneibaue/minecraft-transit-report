---
phase: 03-local-server-setup
plan: 04
subsystem: device-lua
tags: [lua, cc-tweaked, installer, wget, http, deploy, tap-tests]

requires:
  - phase: 03-local-server-setup
    provides: "03-01 deploy engine (marker scan, byte-exact copies, secret.txt/bridge.txt writes); 03-02 Lua reading bridge.txt and the '-- <name> :' first lines"
provides:
  - "turtle/turtle-helper/startup.lua: boot-time update of chat.lua and client.lua from the pinned raw base on main, validated before any write, skipped on _marker.txt devices, then D-08 role launch"
  - "turtle/turtle-helper/install.lua: the one-line 'wget run' installer (masked one-time token, Enter-keeps-default bridge URL, all-or-nothing validated downloads, foreign-startup guard)"
  - "uv run deploy copies the repo startup.lua verbatim and checks every source before writing"
  - "tests/test_device_lua.py: 10 zero-network invariant checks over the four device Lua files"
affects: [03-05, 03-06, 04-first-in-game-round-trip, 05-docs]

actuals:
  tokens: 5809
  tasks: 2
  commits: 3
plan_head_before: c40de4ef287d89fcb06cbb6cae982d24f1c3dd10

tech-stack:
  added: []
  patterns:
    - "Device download contract: http.get table form (binary, timeout 10), status 200, non-empty body, '-- <name>' header, compile-only load(body, '=' .. name, 't', {}); only then fs.open(name, 'wb')"
    - "Deploy-managed devices are exactly the _marker.txt devices; startup.lua skips the GitHub step there"
    - "Token-safety test: no line with a global print/write/printError call may name the token variable"

key-files:
  created:
    - turtle/turtle-helper/startup.lua
    - turtle/turtle-helper/install.lua
    - turtle/turtle-helper/tests/test_device_lua.py
  modified:
    - turtle/turtle-helper/deploy/deploy.py
    - turtle/turtle-helper/tests/test_deploy_files.py

key-decisions:
  - "startup.lua skips the GitHub update when _marker.txt exists (planner reconciliation of D-14 vs D-16, kept as planned); deleting _marker.txt returns a device to GitHub updates"
  - "deploy maps device names to repo paths in one LUA_SOURCES table and checks every source with is_file() before the first copy, so a missing file raises FileNotFoundError naming only its repo-relative path"
  - "install.lua falls back to ws://127.0.0.1:8765 as the pre-filled URL when an existing bridge.txt is not a ws:// or wss:// URL, so Enter can never loop on a bad stored value"
  - "install.lua warns (never deletes) when a file named startup exists, because CraftOS runs /startup instead of /startup.lua"

patterns-established:
  - "Every device Lua file's line 1 is '-- <file name> :', and tests/test_device_lua.py pins it because devices reject downloads without it"
  - "One pinned BASE constant, identical in startup.lua and install.lua, joined only with fixed FILES paths"

requirements-completed: []

coverage:
  - id: D1
    description: "deploy copies the repo startup.lua byte-identical (CRLF and non-ASCII fixture), a hand edit is replaced on re-run, and a missing startup.lua or client.lua raises FileNotFoundError naming the repo path, with no token in it and nothing written"
    requirement: SRV-04
    verification:
      - kind: unit
        ref: "tests/test_deploy_files.py#test_startup_lua_is_the_repo_copy_and_always_overwritten"
        status: pass
      - kind: unit
        ref: "tests/test_deploy_files.py#test_missing_repo_startup_lua_writes_nothing"
        status: pass
      - kind: unit
        ref: "tests/test_deploy_files.py#test_any_missing_repo_source_writes_nothing"
        status: pass
    human_judgment: false
  - id: D2
    description: "startup.lua and install.lua text invariants: pinned raw base, download headers, validation before write, marker skip, update-before-role-check order, masked token prompt, no token print, no localhost"
    requirement: SRV-05
    verification:
      - kind: unit
        ref: "tests/test_device_lua.py (10 tests, # fail 0)"
        status: pass
      - kind: other
        ref: "luaparse {luaVersion:'5.2'} over base/chat.lua, turtle/client.lua, startup.lua, install.lua -> LUA_PARSE_OK"
        status: pass
    human_judgment: false
  - id: D3
    description: "The in-game install and the boot-time update actually work on a CC:Tweaked computer (wget run, masked prompt, Enter default, update or fallback, role launch)"
    requirement: SRV-05
    verification: []
    human_judgment: true
    rationale: "No Lua runtime on this PC and the raw URLs 404 until Plan 03-05 pushes main; the in-game run is Plan 03-05's checkpoint"

duration: 5min
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 04: In-game Installer and Auto-updating Startup Summary

**A repo `startup.lua` now refreshes `chat.lua` and `client.lua` from GitHub `main` on every boot. It writes a file only after the download returns 200, the body is non-empty, the header matches and the Lua compiles; otherwise it keeps the local copy. It skips the update on `_marker.txt` developer devices and then launches chat or client. `install.lua` is the one-line `wget run` installer. It asks for the token once with masked input and keeps the existing URL when you press Enter. `uv run deploy` now copies the same `startup.lua` instead of generating one.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-09-25T10:38:18Z
- **Completed:** 2026-09-25T10:43:29Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- `turtle/turtle-helper/startup.lua` (53 lines) holds one pinned `BASE`, a `FILES` table and a `fetch(name, path)`. `fetch` closes the handle on every path and checks the status, a non-empty body, the `-- <name>` header and a compile-only `load`. The update step prints `up to date`, `updated <name>` or `<name>: <reason>; using the local copy`. D-08's role check follows unchanged. The file never reads `secret.txt` and never calls `read(`.
- `turtle/turtle-helper/install.lua` (124 lines) runs strictly in order: banner with id and label; y/n guard before replacing a foreign `startup.lua`; all three downloads into memory, where any failure prints one line and writes nothing; masked token prompt only when `secret.txt` is missing or blank; URL prompt pre-filled from `bridge.txt` or `ws://127.0.0.1:8765`, which must start with `ws://` or `wss://`; the writes; a summary that shows `secret.txt (kept)` when kept.
- `deploy/deploy.py` no longer contains the generated startup script. `LUA_SOURCES` maps each device file to its repo path, every source is checked before anything is written, and all three are copied with `shutil.copy2`. The docstrings and `--help` say that `startup.lua` comes from the repo and that marked devices skip the boot-time GitHub update.
- `tests/test_deploy_files.py` has 12 tests, all passing. `tests/test_device_lua.py` has 10 tests, all passing. luaparse accepts all four device Lua files under Lua 5.2. ruff check and format pass, and mypy is clean on bridge, harness, deploy and the new test file.
- A mutation pass over copies of the Lua files was run as a sanity check and not committed. It covered `print(newToken)`, `write('x' .. newToken)`, a `localhost` comment, a foreign `https://` URL, a `/dev/` base, a `secret.txt` read in `startup.lua`, and a disabled marker guard. The tests caught all seven.

## Task Commits

1. **Task 1 RED: failing deploy tests for the repo startup.lua**: `af61811` (test). The RED evidence was verified with `check tdd-red-evidence`, and all three target tests returned RED_EVIDENCE_OK.
2. **Task 1 GREEN: repo startup.lua, deploy copies it**: `4b4dd67` (feat)
3. **Task 2: install.lua and tests/test_device_lua.py**: `0c00a5b` (feat)

**Plan metadata:** the docs(03-04) commit that includes this SUMMARY

## Files Created/Modified
- `turtle/turtle-helper/startup.lua`: boot-time validated update, marker skip, role launch (new, tracked)
- `turtle/turtle-helper/install.lua`: the one-line in-game installer (new, tracked)
- `turtle/turtle-helper/deploy/deploy.py`: copies the repo startup.lua and checks every source before writing
- `turtle/turtle-helper/tests/test_deploy_files.py`: `STARTUP_FIXTURE` plus three new tests; the old role-text test is replaced
- `turtle/turtle-helper/tests/test_device_lua.py`: 10 zero-network Lua invariant checks (new)

## Decisions Made
- The marker skip stays as the planner reconciled it: marked devices are the deploy-managed ones, and deleting `_marker.txt` returns a device to GitHub updates. The operator can still veto it at review.
- If a stored `bridge.txt` is not a ws/wss URL, install.lua pre-fills the default instead, so pressing Enter always gets a valid value.
- A file named `startup` (no extension) takes precedence over `startup.lua` in CraftOS. install.lua prints a note about it but never deletes it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The plan's test count of 12 did not match the tests it specified; added the any-source test**
- **Found during:** Task 1 RED
- **Issue:** The plan replaces one of the ten existing tests and adds two, which makes 11. Its acceptance criteria and verify step still require 12. The plan's action also says any missing source must raise before anything is written, and no specified test covered a source other than startup.lua.
- **Fix:** Added `test_any_missing_repo_source_writes_nothing`. It deletes the fake repo's `turtle/client.lua` and asserts `FileNotFoundError` naming `client.lua`, no token in the message, and an unchanged folder. It was RED against the old code, which copied chat.lua first and raised a Windows error that did not name the file.
- **Files modified:** turtle/turtle-helper/tests/test_deploy_files.py
- **Verification:** 12/12 pass. The RED evidence for this test was RED_EVIDENCE_OK.
- **Committed in:** af61811

**2. [Rule 1 - Bug] The marker-skip test passed even with the guard removed**
- **Found during:** Task 2 (mutation sanity pass)
- **Issue:** The plan's check was `"_marker.txt" in startup.lua`. It still passed with the `fs.exists` guard disabled, because the header comment names the file.
- **Fix:** The test now requires the code guard `if fs.exists("_marker.txt") then`.
- **Files modified:** turtle/turtle-helper/tests/test_device_lua.py
- **Verification:** The disabled-guard mutant now fails the test, and the real file passes.
- **Committed in:** 0c00a5b

**3. [Rule 2 - Missing critical] install.lua handles a stored invalid URL and a shadowing `startup` file**
- **Found during:** Task 2
- **Issue:** (a) A non-ws value in `bridge.txt` would be pre-filled, and pressing Enter would loop forever. (b) CraftOS runs a file named `startup` instead of `startup.lua`, so an install on such a computer would silently never start turtle-helper.
- **Fix:** (a) The pre-fill falls back to `DEFAULT_URL` unless the stored value passes `isBridgeUrl`. (b) After writing, install.lua prints a note when `startup` exists and is not a directory. It deletes nothing.
- **Files modified:** turtle/turtle-helper/install.lua
- **Verification:** luaparse passes, and test_device_lua is 10/10.
- **Committed in:** 0c00a5b

---

**Total deviations:** 3 auto-fixed (2 bug, 1 missing critical)
**Impact on plan:** All three tighten the planned behaviour or its tests. There is no scope creep, and no wire protocol or bridge code changed.

## Issues Encountered
- Bash heredocs on this host turn `\\n` into a real newline, so two Python patch scripts first aborted on their own assertions before writing anything. They were rerun from scratchpad files. `$'\r'` also reaches grep mangled. Line endings were therefore checked with Python: `startup.lua`, `install.lua` and the test file have 0 CR bytes in both the committed blob and the worktree, which matters because raw GitHub serves the blob.
- `requirements.ready-ids` blocks SRV-02..05 because plans 03-05 and 03-06 also declare them and have no SUMMARY yet, so no requirement was marked complete here.

## User Setup Required

None. The in-game run belongs to Plan 03-05.

## Next Phase Readiness
- Plan 03-05 Task 1 can push `main`. Until then the raw URLs for `install.lua` and `startup.lua` return 404, so both scripts would print their "could not download" or "using the local copy" lines.
- The in-game check still to do: `wget run .../install.lua` on a fresh computer, the masked token prompt, Enter keeping `ws://127.0.0.1:8765`, then reboot, then `updated`/`up to date` lines, then chat or client launching. A re-run should keep `secret.txt`.
- README and `turtle/turtle-helper/CLAUDE.md` still describe deploy as the only path and say "not pastebin/wget". That is 03-06's or Phase 5's doc work.

---
*Phase: 03-local-server-setup*
*Completed: 2026-09-25*

## Self-Check: PASSED
- FOUND: turtle/turtle-helper/startup.lua (tracked)
- FOUND: turtle/turtle-helper/install.lua (tracked)
- FOUND: turtle/turtle-helper/deploy/deploy.py
- FOUND: turtle/turtle-helper/tests/test_deploy_files.py
- FOUND: turtle/turtle-helper/tests/test_device_lua.py (tracked)
- FOUND: commits af61811, 4b4dd67, 0c00a5b

---
phase: 03-local-server-setup
plan: 02
subsystem: device-lua
tags: [lua, cc-tweaked, websocket, deploy, bridge-url]

requires:
  - phase: 03-local-server-setup
    provides: "03-01 deploy engine writes bridge.txt (ws://<HOST>:<PORT>, no trailing newline) and secret.txt beside byte-identical copies of base/chat.lua and turtle/client.lua"
provides:
  - "Both device Lua files default to ws://127.0.0.1:8765 and override BRIDGE_URL from bridge.txt when present"
  - "chat.lua names itself by computer label, else device-<id>, same as client.lua"
  - "base/chat.lua is git-tracked"
affects: [03-03, 03-04, 04-first-in-game-round-trip]

actuals:
  tokens: 1300
  tasks: 2
  commits: 1
plan_head_before: 2b0b4c8867c9bdaf7644c4953e12392ab86e8a70

tech-stack:
  added: []
  patterns:
    - "Device config file override: readFile('<name>.txt'), trim with gsub('%s+$', ''), reassign the existing top-level local (never re-declare it)"

key-files:
  created:
    - turtle/turtle-helper/base/chat.lua
  modified:
    - turtle/turtle-helper/turtle/client.lua

key-decisions:
  - "The bridge.txt read is a plain reassignment of the top-level local BRIDGE_URL, so the websocket closures and the websocket_message/closed URL match see the overridden value"
  - "The Setup comments in both files now point at uv run deploy instead of telling the operator to edit BRIDGE_URL"

patterns-established:
  - "Deploy-written device files (secret.txt, bridge.txt) are read with the one readFile helper and trimmed the same way"

requirements-completed: [SRV-01, SRV-02]

coverage:
  - id: D1
    description: "Both Lua files have no wss://YOUR-BRIDGE-HOST placeholder and no localhost string, fall back to ws://127.0.0.1:8765, and override BRIDGE_URL from bridge.txt"
    requirement: SRV-01
    verification:
      - kind: other
        ref: "grep checks: no YOUR-BRIDGE-HOST, no localhost (case-insensitive), 127.0.0.1:8765 and readFile(\"bridge.txt\") in both files"
        status: pass
    human_judgment: false
  - id: D2
    description: "chat.lua DEVICE_ID follows the label-or-device-<id> rule (D-10)"
    requirement: SRV-02
    verification:
      - kind: other
        ref: "grep -q 'os.getComputerLabel() or (\"device-\" .. os.getComputerID())' turtle/turtle-helper/base/chat.lua"
        status: pass
    human_judgment: false
  - id: D3
    description: "base/chat.lua is git-tracked"
    requirement: SRV-02
    verification:
      - kind: other
        ref: "git ls-files --error-unmatch turtle/turtle-helper/base/chat.lua"
        status: pass
    human_judgment: false
  - id: D4
    description: "Both files parse under Lua 5.2 grammar"
    verification:
      - kind: other
        ref: "luaparse {luaVersion:'5.2'} on base/chat.lua and turtle/client.lua -> LUA_PARSE_OK"
        status: pass
    human_judgment: false
  - id: D5
    description: "The bridge.txt override actually takes effect on a CC:Tweaked computer (the device connects to the URL deploy wrote)"
    verification: []
    human_judgment: true
    rationale: "No Lua runtime on this PC; the override only runs in game, which is Plan 03-04's smoke check and Phase 4's first round trip"

duration: 1min
completed: 2026-09-25
status: complete
---

# Phase 3 Plan 02: Lua Bridge URL and Device Naming Summary

**`chat.lua` and `client.lua` now default to `ws://127.0.0.1:8765` and take their URL from the `bridge.txt` that deploy writes. `chat.lua` names itself by computer label or `device-<id>` instead of `"base"`, and it is in git for the first time.**

## Performance

- **Duration:** 1 min (after context load)
- **Started:** 2026-09-25T08:55:48Z
- **Completed:** 2026-09-25T08:56:39Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- The `wss://YOUR-BRIDGE-HOST` placeholder is gone from both files. The fallback is the IPv4 literal `ws://127.0.0.1:8765`, and `localhost` appears in neither file (D-06, Pitfall 1).
- Both files read `bridge.txt` right after `secret.txt` with the existing `readFile` helper, trim it with the same `gsub("%s+$", "")`, and reassign the existing top-level `BRIDGE_URL`. There is exactly one `local BRIDGE_URL` per file, so nothing shadows it.
- `chat.lua`'s `DEVICE_ID` is now `os.getComputerLabel() or ("device-" .. os.getComputerID())`, the same rule `client.lua` uses (D-10).
- `turtle/turtle-helper/base/chat.lua` was added to git in the Task 1 commit.
- Both files parse cleanly with luaparse (Lua 5.2 grammar). The existing deploy TAP suite still passes (10/10).

## Task Commits

1. **Task 1: Amend chat.lua and client.lua, first git-add of chat.lua**: `6a3934d` (feat)
2. **Task 2: Syntax-check both files (luaparse, Lua 5.2)**: verification only, no file changes, no commit. Output was `LUA_PARSE_OK`, exit 0.

**Plan metadata:** see the docs(03-02) commit that includes this SUMMARY

## Files Created/Modified
- `turtle/turtle-helper/base/chat.lua`: IPv4 fallback URL, `bridge.txt` override, label-or-id `DEVICE_ID`, Setup comment updated. Newly tracked.
- `turtle/turtle-helper/turtle/client.lua`: IPv4 fallback URL, `bridge.txt` override, Setup comment updated.

## Decisions Made
- The override uses the variable name `BRIDGE_FILE` and fits on one `if ... then ... end` line in each file, so the change stays small and identical in both files.
- The trailing comment on each `BRIDGE_URL` line reads `-- default; bridge.txt overrides it`, which replaces the old "change me" note.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Setup comments still told the operator to edit BRIDGE_URL**
- **Found during:** Task 1
- **Issue:** The header of `chat.lua` (line 5) and the numbered Setup steps in `client.lua` (lines 7 to 9) said to edit `BRIDGE_URL` by hand and to add `shell.run("client")` to startup.lua. Both instructions are wrong once deploy writes `bridge.txt` and `startup.lua`.
- **Fix:** Rewrote those comment lines to say that `uv run deploy` writes `secret.txt` and `bridge.txt`, and that the `BRIDGE_URL` default applies when `bridge.txt` is missing. Code lines outside the planned edits were not touched.
- **Files modified:** turtle/turtle-helper/base/chat.lua, turtle/turtle-helper/turtle/client.lua
- **Verification:** All Task 1 greps still pass, and luaparse passes.
- **Committed in:** 6a3934d

---

**Total deviations:** 1 auto-fixed (1 stale-instruction fix)
**Impact on plan:** Comment-only change in the two planned files. No scope creep.

## Issues Encountered
- Git warns "LF will be replaced by CRLF the next time Git touches it" for both files. They were LF on disk before and after the edit, so the edit did not change line endings. `core.autocrlf` could still make a fresh checkout CRLF. If that matters for Phase 4's LOOP-05 byte diff, it is an existing condition of the repo that this plan did not introduce. It is noted here for that phase.

## User Setup Required

None. No external service configuration is required.

## Next Phase Readiness
- Deploy (03-01) now copies Lua that reads the `bridge.txt` it writes. Plans 03-03 and 03-04 can go ahead.
- The override has not yet run on a CC:Tweaked computer. The first real proof is Plan 03-04's smoke check and Phase 4's first round trip.
- `turtle/turtle-helper/CLAUDE.md` still says "The device stores only `secret.txt` and its Lua". D-06 amends that. The Phase 3 docs plan or Phase 5's DOC-02 should update it.

---
*Phase: 03-local-server-setup*
*Completed: 2026-09-25*

## Self-Check: PASSED
- FOUND: turtle/turtle-helper/base/chat.lua (tracked)
- FOUND: turtle/turtle-helper/turtle/client.lua
- FOUND: commit 6a3934d

---
phase: 04-in-game-round-trip
plan: 01
subsystem: device-lua
tags: [cc-tweaked, advanced-peripherals, lua, chat-box, debug, pydantic-ai, prompt]

requires:
  - phase: 03-local-server-setup
    provides: push-to-main then reboot update path, RAW_MATCH check, device A (computer 0) connected as device-0
provides:
  - chat.lua puts back the "$" that AP 0.7.46r strips from hidden chat, so "$robot ..." reaches the bridge's prefix check
  - DEBUG marker (fs.exists("debug")) and dbg() in chat.lua and client.lua, logging to the screen and debug.log
  - three text tests pinning the restore, the marker and the no-token rule for device output
  - one SYSTEM_TEMPLATE Rules bullet for direct, one-or-two-sentence, plain-ASCII answers
  - all of it on origin/main and served byte-identical by raw GitHub
affects: [04-02, 04-03, phase-05-docs]

actuals:
  tokens: 10700   # chars/4 over the four changed files (42,799 chars); the diff alone is ~1,060
  tasks: 4
  commits: 3
plan_head_before: f6e13602f3e48d8a53187edb6f38cbc2d5e9b076

tech-stack:
  added: []
  patterns:
    - "Device debug output is gated on a marker file (mkdir debug / rm debug), never a committed constant"
    - "Device output calls (print/write/printError/log/dbg) never mention the token or hello frame, pinned by DEVICE_OUTPUT_CALL"

key-files:
  created: []
  modified:
    - turtle/turtle-helper/base/chat.lua
    - turtle/turtle-helper/turtle/client.lua
    - turtle/turtle-helper/tests/test_device_lua.py
    - turtle/turtle-helper/bridge/agent.py

key-decisions:
  - "DEBUG is a marker (fs.exists(\"debug\") at program start), not a constant: toggled per device with no commit, and main can never ship with it on"
  - "The $ restore lives in chat.lua and only adds $ when hidden text does not already start with $; the bridge keeps trusting only the $robot prefix"
  - "dbg() skips the debug.log write when fs.open returns nil instead of raising inside the session"

patterns-established:
  - "code_lines(name) in tests/test_device_lua.py skips Lua comment lines so prose never trips a negative check"

requirements-completed: [LOOP-03, LOOP-05]

coverage:
  - id: D1
    description: "chat.lua restores the leading $ on hidden chat before building the unchanged event frame (type, name, user, text, uuid, hidden)"
    requirement: LOOP-03
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_device_lua.py#test_chat_restores_the_dollar_ap_strips"
        status: pass
      - kind: other
        ref: "luaparse 5.2 over chat.lua, client.lua, startup.lua, install.lua (LUA_PARSE_OK)"
        status: pass
    human_judgment: true
    rationale: "The text test pins the code; whether a real hidden $robot message now reaches the bridge is only observable in game (Plan 04-02 reads debug.log and the bridge log)"
  - id: D2
    description: "DEBUG marker in chat.lua and client.lua defaults off, logs to screen and debug.log when a debug file/folder exists, and never logs the token or hello frame"
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_device_lua.py#test_debug_is_a_marker_file"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_device_lua.py#test_device_output_never_shows_the_token"
        status: pass
    human_judgment: false
  - id: D3
    description: "SYSTEM_TEMPLATE's last Rules bullet asks for a direct one-or-two-sentence plain-ASCII answer; {robot_name} stays the only placeholder"
    verification:
      - kind: unit
        ref: "uv run python -c '...SYSTEM_TEMPLATE.format(...)' (PROMPT_LINE_OK) and tests/test_agent.py (26/26)"
        status: pass
    human_judgment: false
  - id: D4
    description: "origin/main carries the three 04-01 commits and raw GitHub serves install.lua, startup.lua, base/chat.lua and turtle/client.lua byte-identical; no 04-01 commit touches harness/"
    requirement: LOOP-05
    verification:
      - kind: other
        ref: "Plan 04-01 Task 4 four-file RAW_MATCH one-liner (RAW_MATCH_OK) and HARNESS_UNTOUCHED_OK"
        status: pass
    human_judgment: false

duration: 3min
completed: 2026-09-25
status: complete
---

# Phase 4 Plan 01: Repo Ready for the First In-Game Request Summary

**chat.lua puts back the `$` that Advanced Peripherals 0.7.46r strips from hidden chat. Both device files gained a `debug`-marker DEBUG log to the screen and debug.log. The prompt gained a plain-ASCII short-answer line. All of it is pushed and served by raw GitHub.**

## Performance

- **Duration:** about 3 min
- **Started:** 2026-09-25T16:55:44Z
- **Completed:** 2026-09-25T16:58:39Z
- **Tasks:** 4 (Task 1 was the tracer)
- **Files modified:** 4

## Accomplishments

- A hidden chat event carrying `robot what devices are connected?` now leaves chat.lua as `$robot what devices are connected?`, with the same six frame keys. Text that already starts with `$`, and non-hidden text, pass through unchanged.
- `DEBUG = fs.exists("debug")` and `dbg(...)` in both device files. chat.lua logs:
  - `chat event: user=… text=… uuid=… hidden=… extra=…`, with the raw values before the restore;
  - `say: to=… prefix=… text=…` before each Chat Box call;
  - `say returned: ok=… err=…` after it.

  client.lua logs `recv: <frame>` and `result: <frame>`. The hello and pong sends are never logged.
- Three new text tests take `tests/test_device_lua.py` from 10 to 13. They check the restore line comes before the frame, that no device output call mentions `token` or `hello`, and that the marker is present with no `DEBUG = true`.
- SYSTEM_TEMPLATE gained one Rules bullet: answer a general question directly through say(), in one or two sentences, in plain ASCII.

## Task Commits

1. **Task 1 (tracer): restore the `$`, DEBUG in chat.lua, tests, push, RAW_MATCH:** `c318561` (fix)
2. **Task 2: DEBUG marker in client.lua:** `92ad735` (feat)
3. **Task 3: D-07 prompt line:** `3bde837` (feat)
4. **Task 4: push main, four-file RAW_MATCH, harness untouched:** no commit. Pushed `c318561..3bde837`.

RAW_MATCH output, after Task 1's push (narrowed to chat.lua):
```
SAME base/chat.lua
RAW_MATCH_OK
```
RAW_MATCH output, after Task 4's push:
```
SAME install.lua
SAME startup.lua
SAME base/chat.lua
SAME turtle/client.lua
RAW_MATCH_OK
HARNESS_UNTOUCHED_OK
```

## FIXES (for Plan 04-03's fix list)

- AP 0.7.46r strips every $ from a hidden chat message (Events.onChatBox String.replace); chat.lua puts the prefix back when hidden. Found by jar inspection before the first run; in-game confirmation pending (Plan 04-02 reads debug.log)

## Files Created/Modified

- `turtle/turtle-helper/base/chat.lua`: the DEBUG marker and `dbg`, the `$` restore in the `chat` branch, and `say` / `say returned` debug lines around the Chat Box call.
- `turtle/turtle-helper/turtle/client.lua`: the same DEBUG marker and `dbg`, plus `recv:` and `result:` debug lines in `session`.
- `turtle/turtle-helper/tests/test_device_lua.py`: `DEVICE_OUTPUT_CALL`, `DEBUG_FILES`, `DOLLAR_RESTORE`, `code_lines()` and three tests.
- `turtle/turtle-helper/bridge/agent.py`: one SYSTEM_TEMPLATE Rules bullet.

## Decisions Made

- DEBUG is a marker file, per RESEARCH Code Example 2 (Claude's discretion under D-11). Turn it on with `mkdir debug` and a reboot, off with `rm debug`. `fs.exists` and `fs.open` resolve from the device root, so `debug.log` sits in `<SERVER_DIR>/world/computercraft/computer/<id>/`.
- `dbg` joins its arguments into one line first. That same line goes to `log("DEBUG", line)` and to debug.log, so the screen and the file always match.
- The restore regex is kept as its own `DOLLAR_RESTORE` constant, so the test body stays under ruff's line length.

## Deviations from Plan

None to the plan's code or tests. Two process notes:

- **The plan-commit ledger was stale.** `.git/gsd-plan-head-before-04-01` already existed from the other workstream's (Fabric transit display) plan 04-01, pointing at `5b4a2e5`. It was reset to this plan's real base `f6e1360` before the first commit. `commits: 3` is measured from that base.
- **ruff format re-wrapped one assert** in the new `test_device_output_never_shows_the_token`, applied before the Task 1 commit. It is formatting only.

## Issues Encountered

None. Both pushes were accepted, and raw GitHub served the new bytes on the first fetch each time.

## User Setup Required

None. The D-07 prompt line reaches the model only after the operator restarts the bridge (Plan 04-02 Task 1). The device files install on each device's next reboot.

## Next Phase Readiness

- Ready for 04-02. The chat-only loop can start once the operator restarts the bridge and reboots device A. `mkdir debug` on device A before that reboot turns on the debug.log capture.
- Not changed, as the plan required (D-09): the outbox requeue (Pitfall 2), the bridge-side ASCII fold (Finding 6) and the ping question. They stay as they are until something shows up in game.

## Self-Check: PASSED

- FOUND: turtle/turtle-helper/base/chat.lua, turtle/turtle-helper/turtle/client.lua, turtle/turtle-helper/tests/test_device_lua.py, turtle/turtle-helper/bridge/agent.py
- FOUND commits: c318561, 92ad735, 3bde837
- Plan verification re-run:
  - LUA_PARSE_OK on all four Lua files;
  - test_device_lua.py 13/13 and test_agent.py 26/26;
  - ruff check, ruff format --check and mypy clean;
  - RAW_MATCH_OK for all four device files;
  - HARNESS_UNTOUCHED_OK.

---
*Phase: 04-in-game-round-trip*
*Completed: 2026-09-25*

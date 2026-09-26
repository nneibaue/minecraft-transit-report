---
phase: 04-in-game-round-trip
plan: 03
subsystem: device-lua
tags: [cc-tweaked, advanced-peripherals, client-lua, second-computer, list-chest, chunk-loading, in-game, haiku, byte-compare]

requires:
  - phase: 04-in-game-round-trip
    provides: "04-01's $ restore and debug marker; 04-02's output-tool say and ASCII fold; the base computer (device-0) connected and answering in game"
  - phase: 03-local-server-setup
    provides: "the one wget install line, startup.lua role detection, the push-then-reboot update path, the read-only world-folder byte compare and the repo token scan"
provides:
  - "LOOP-02 in game: a bare Advanced Computer installed with the wget line connects as `device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']`"
  - "LOOP-03 with two devices: the devices question names device-0 and device-3 as separate devices"
  - "LOOP-04 tool error: `$robot what is in minecraft:chest_99?` gets a plain reply and the bridge stays up; client.lua's cmd/result loop ran in game for the first time (CMD_RESULT_LOOP_OK computer/3)"
  - "LOOP-05 end state: computers 0, 2 and 3 run chat.lua and client.lua byte-identical to origin/main with no debug files (DEVICES_MATCH_MAIN_OK), and the repo and its history hold no token (REPO_TOKEN_CLEAN_OK)"
  - "Phase 5's inputs: normal (debug-free) boot text for both computers, verbatim bridge connect and request lines, FIX_LIST, VERIFIED_FACTS, NOTES_FOR_PHASE_5 and the phase paid-call total"
affects: [phase-05-resilience-and-docs, phase-06-remote-host-setup]

actuals:
  tokens: 10741   # measured chars/4 over this SUMMARY, the only file the plan changed (no code file changed)
  tasks: 5
  commits: 0      # measured: git rev-list --count f630c0c..HEAD before the SUMMARY commit; zero production commits
plan_head_before: f630c0ce3aa19524e6bcc3311e57ee286b814761

tech-stack:
  added: []
  patterns:
    - "During live sessions the orchestrator runs the bridge as a background process with its output captured to a gitignored log, so bridge evidence is copied, not transcribed (author-directed)"
    - "A second computer's placement is part of the install recipe: within simulation distance of the player, a few blocks from the base computer, not touching the Chat Box"

key-files:
  created:
    - .planning/workstreams/turtle-helper/phases/04-in-game-round-trip/04-03-SUMMARY.md
  modified: []

key-decisions:
  - "Placement rule, not code: the second computer must sit within the server's simulation distance of where the player types (in practice a few blocks from the base computer, not touching the Chat Box); computer 2 (far) was superseded by computer 3 (near)"
  - "client.lua's failure frame {type, cid, ok:false, error} held in game and already matches the harness's error-envelope key set, so D-10 needed no harness mirror; the plan closed with zero fix(04-03) commits"
  - "Author-directed: the orchestrator runs the bridge with a captured log during live sessions; Phase 5's proof session should plan on that"

patterns-established:
  - "Evidence for a live step is the orchestrator-captured bridge log plus read-only world-folder checks; the author only acts in game"

requirements-completed: [LOOP-02, LOOP-03, LOOP-04, LOOP-05]

coverage:
  - id: D1
    description: "LOOP-02: the second computer (bare Advanced Computer, wget line, typed token, reboot) connects as `device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']`; no new (chat) line and no replacement of device-0"
    requirement: LOOP-02
    verification:
      - kind: other
        ref: "orchestrator-captured bridge log logs/bridge-2026-09-25.log, 19:53:36 `device connected: device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']` (SECOND_CONNECT); again at 20:03:41 and 20:03:48 after the debug-off reboots (BRIDGE_CONNECT_LINES)"
        status: pass
    human_judgment: false
  - id: D2
    description: "LOOP-03 with two devices: `$robot what devices are connected` gets a reply naming device-0 and device-3 as separate devices, no fallback"
    requirement: LOOP-03
    verification:
      - kind: other
        ref: "bridge log 19:54:41 `answer for DisraSenkovi (plain text, not spoken by the model): You've got two devices connected: ... (device-0) ... (device-3) ...` (DEVICES_ANSWER_2)"
        status: pass
    human_judgment: true
    rationale: "Whether the whispered reply answers the question correctly is a human read; the author read it in chat and confirmed by proceeding"
  - id: D3
    description: "LOOP-04 tool error: `$robot what is in minecraft:chest_99?` gets a plain-language 'no such chest' reply and the bridge keeps running"
    requirement: LOOP-04
    verification:
      - kind: other
        ref: "bridge log 20:00:43 `answer for DisraSenkovi (plain text, not spoken by the model): There's no chest called minecraft:chest_99 ...` (TOOL_ERROR_ANSWER); later bridge lines at 20:03 show it still running"
        status: pass
    human_judgment: true
    rationale: "Plain-language adequacy of the reply is a human read; the author read it in chat and confirmed by proceeding"
  - id: D4
    description: "client.lua's receive, dispatch and result path ran in game on the second computer: a list_chest cmd in, a failing result frame out with keys type, cid, ok, error"
    requirement: LOOP-04
    verification:
      - kind: other
        ref: "Plan 04-03 Task 3 check, discovery narrowed to the folder whose debug.log holds the round trip (CMD_RESULT_LOOP_OK computer/3)"
        status: pass
    human_judgment: false
  - id: D5
    description: "LOOP-05 and D-11 end state: every turtle-helper device folder (computers 0, 2, 3) holds chat.lua and client.lua byte-identical to origin/main, main == origin/main for both files, no `debug` or `debug.log` left on any device, and no token in the repo or its history"
    requirement: LOOP-05
    verification:
      - kind: other
        ref: "Plan 04-03 Task 5 check 1, run verbatim from turtle/turtle-helper (DEVICES_MATCH_MAIN_OK ['0', '2', '3'], exit 0; run by the orchestrator and re-run by the Task 5 executor)"
        status: pass
      - kind: other
        ref: "Plan 04-03 Task 5 check 2, Phase 3's repo and history token scan verbatim (REPO_TOKEN_CLEAN_OK, exit 0; run twice)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Placement finding: a second computer placed far from the base computer unloads with its chunk (simulation-distance=10) and drops off the bridge; placed a few blocks away it stays connected"
    verification:
      - kind: other
        ref: "bridge log `device disconnected: device-2` at 19:52:19 when the author teleported away; device-3 near the base computer stayed connected through both questions"
        status: pass
    human_judgment: true
    rationale: "The cause (chunk unload) is inferred from the author's placement and the disconnect timing, not asserted by a test; the wording of the placement rule is Phase 5's recipe to judge"
  - id: D7
    description: "D-12 capture: the normal, debug-free start-up text of both computers (BOOT_A_NORMAL, BOOT_SECOND_NORMAL)"
    verification: []
    human_judgment: true
    rationale: "Transcribed from the author's screenshots of the computer screens; no file on disk records what a CraftOS screen printed"

duration: 9h 15m
completed: 2026-09-25
status: complete
---

# Phase 4 Plan 03: Second Computer and Phase Close Summary

**A bare Advanced Computer installed with the one wget line connected as `device-3 (computer)`. With it, the devices question named device-0 and device-3. A `list_chest` on a chest that does not exist ran client.lua's cmd/result loop in game for the first time and got a plain "no such chest" reply. After debug was turned off, all three turtle-helper device folders were proven byte-identical to origin/main and the repo holds no token. The plan needed no code fix. The one finding is about placement: a second computer placed far away unloads with its chunk.**

## Phase 4 in one look

What ran in game, on the ATM9 server with CC:Tweaked 1.116.1 and Advanced Peripherals 0.7.46r, on 2026-09-25:

- **The base computer** (computer 0, the one with the Chat Box) connects as `device-0 (chat) caps=['say']`. `$robot` questions typed in chat reach the bridge and get one model-worded `[Robot]` reply. This was proven in 04-02, and again here with both computers connected.
- **The second computer** (computer 3, a bare Advanced Computer) connects as `device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']`. It advertises all three caps sorted, with nothing attached. It answered a real `list_chest` command with a failure result frame.
- **LOOP-03:** the devices question named exactly one device (the chat device) with only the base computer. With the second computer it named device-0 and device-3.
- **LOOP-04:** both kinds of unfulfillable request got a plain reply and the bridge stayed up. One kind has no second computer (04-02). The other is a tool error on the second computer (this plan).
- **LOOP-05:** every first-run fix lives in the repo and is pushed. Every device runs origin/main's Lua with debug off. No token is in the repo or its history.

The four FIX_LIST lines (in full under FIX_LIST below):

1. 04-01 `c318561`: AP strips every `$` from hidden chat. chat.lua puts the prefix back.
2. 04-02 `8b7f082`: `say` is now the agent's output tool, so the run ends when the model speaks. Before this, answers came twice, then UnexpectedModelBehavior.
3. 04-02 `e6dd9a4`: `bridge.say()` folds answers to plain ASCII, because the Chat Box shows non-ASCII as mojibake.
4. 04-03, no commit: put the second computer a few blocks from the base computer. A far computer unloads with its chunk.

Paid calls: **10 requests for the whole phase**, all claude-haiku-4-5: 0 in 04-01, 6 in 04-02 and 4 in 04-03. The author typed every one of them in game. No agent made a paid call.

## Performance

- **Duration:** 9h 15m wall clock, of which about eight hours was the author's break. The live work ran 2026-09-26T02:30Z to 03:10Z (19:30 to 20:10 local, UTC-7). The Task 5 close-out ran from about 03:15Z to 03:25Z.
- **Started:** 2026-09-25T18:10:00Z, when the orchestrator presented Task 1.
- **Completed:** 2026-09-26T03:25Z (about), at the SUMMARY commit.
- **Tasks:** 5 of 5.
- **Files modified:** 0 code files. The only file this plan wrote is this SUMMARY, plus the workstream STATE.md, ROADMAP.md and REQUIREMENTS.md at close-out.

## Accomplishments

- The second computer connected with the right role and caps on its first boot. No Lua error surfaced (LOOP-02).
- The devices question named both devices by id (LOOP-03, two devices).
- A tool error on the second computer got a plain reply, and the bridge kept running (LOOP-04). client.lua's receive, dispatch and result path ran for real. The result frame it sent is on record, and its key set matches the harness's error envelope.
- Debug is off on every device. All three device folders equal origin/main byte for byte, and the repo and its history are token-free (LOOP-05, D-11).
- Phase 5 has what it needs: the debug-free boot text, the bridge's connect and request lines copied from a captured log, the fix list, the verified facts, the notes and the paid-call count.

## Task Commits

| Task | Name | Type | Commit(s) |
|------|------|------|-----------|
| 1 | Install the second computer with debug on | checkpoint:human-action | none. Live steps by the author. Computer 2 (placed far away) was superseded by computer 3 (placed near). |
| 2 | Devices question with both computers, then the tool error | checkpoint:human-verify | none |
| 3 | CMD_RESULT_LOOP check and start of the SUMMARY | auto | none. Read-only check, run by the orchestrator. |
| 4 | Debug off on both computers, normal start-up text | checkpoint:human-action | none |
| 5 | Prove both devices equal main, repo token-free, write the fix list | auto | this SUMMARY's docs commit |

There are zero `fix(04-03)` commits, because no code needed changing. `git rev-list --count f630c0c..HEAD` was 0 before the SUMMARY commit. The main branch's Lua equals origin/main (`e6dd9a4` for both device files).

## Files Created/Modified

- `.planning/workstreams/turtle-helper/phases/04-in-game-round-trip/04-03-SUMMARY.md`: this file, the phase's evidence file for Phase 5.
- No Lua, bridge, harness or test file changed. The plan's `files_modified` (client.lua, chat.lua, test_device_lua.py) were listed only in case the second computer surfaced a bug, and it did not.

## Evidence

The orchestrator wrote the Task 1-4 sections below during execution. The Task 5 executor completed the rest. Every fenced block is pasted or transcribed verbatim from one of these sources, and nothing is reconstructed:
- the operator's terminal;
- the author's screenshots;
- the device logs;
- the orchestrator-captured bridge log.

## How the live steps ran (deviation, author-directed)

From Task 2 on, the author asked the orchestrator to run the bridge itself and capture its output ("I want you to manage the bridge process in a way that you can capture the output. I'll just do the minecraft part"). The author stopped his own bridge; the orchestrator started `uv run bridge/bridge.py` as a background process of the Claude Code session at 19:48:10 local (PID 40968) with stdout/stderr appended to `turtle/turtle-helper/logs/bridge-2026-09-25.log` (gitignored via `logs/`), and armed a log watch. The plan's "no agent starts the bridge" prohibition was set aside by the author for this reason; the in-game steps stayed the author's. BRIDGE_CONNECT_LINES and BRIDGE_REQUEST_LOG below are copied from that captured log, so they are exact.

## Task 1 evidence (2026-09-25)

Pre-flight: the four-file RAW_MATCH printed SAME for install.lua, startup.lua, base/chat.lua and turtle/client.lua, then RAW_MATCH_OK (main == origin/main at e6dd9a4 for those files).

### First attempt: computer 2, placed far away (superseded)

The second computer (a bare Advanced Computer, nothing attached) after the one wget line, the typed token, Enter for the default URL, `mkdir debug` and `reboot` (transcribed from the author's screenshot):

```
CraftOS 1.9
Feeling creative? Use a printer to print a book!
chat.lua up to date
client.lua up to date
[0:51]  connected as device-2
```

The bridge's `device connected:` line (transcribed from the author's screenshot of his own bridge window):

```
2026-09-25 19:34:55,696 INFO connection open
2026-09-25 19:34:55,698 INFO device connected: device-2 (computer) caps=['list_chest', 'push_one_slot', 'status']
```

The first devices question (19:36:24, author's bridge, pasted) then answered "You've got one device connected: a chat interface (me)..." twice (the second time with "use list_devices" added), two API calls each, i.e. the tool ran and saw only device-0:

```
2026-09-25 19:36:24,490 INFO request from DisraSenkovi: what devices are connected
2026-09-25 19:36:25,542 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 19:36:27,427 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 19:36:27,434 INFO answer for DisraSenkovi (spoken via say): You've got one device connected: a chat interface (me). No storage or sorting systems are set up yet. Want to add some chests or a sorting network?
2026-09-25 19:37:39,083 INFO request from DisraSenkovi: what devices are connected? use list_devices
2026-09-25 19:37:39,952 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 19:37:41,366 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 19:37:41,371 INFO answer for DisraSenkovi (spoken via say): You've got one device connected: a chat interface (me). No storage or sorting systems are set up yet. Want to add some chests or a sorting network?
```

Diagnosis: not code. The author had placed computer 2 far from the base computer (his words: "ah yes i did place it far away!"). server.properties has `simulation-distance=10`, so when he walked back to the base computer to type, computer 2's chunk unloaded, the computer went offline and the bridge dropped it (the orchestrator-captured log later showed exactly that: `device disconnected: device-2` at 19:52:19 when the author teleported away from it). The ping-timeout theory was tested first and rejected: with the orchestrator's bridge and both devices idle for 100 s (more than two 20 s + 20 s ping cycles), the log held 2 connects, 0 disconnects, 0 replacements. Computer 2 stays in the world. Its folder later had its `debug` marker removed on disk (see Task 4).

### Second attempt: computer 3, within a few blocks of the base computer

SECOND_CONNECT (from the orchestrator-captured bridge log; the author installed it with the same wget line, token, Enter, `mkdir debug`, `reboot`):

```
2026-09-25 19:53:36,401 INFO connection open
2026-09-25 19:53:36,402 INFO device connected: device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']
```

Acceptance: N = 3 (not 0); role `computer`; caps sorted `list_chest, push_one_slot, status` (edge LOOP-02/ordering and LOOP-02/empty); no new `(chat)` connect line and no `replacing stale connection` line for device-0 (edge LOOP-02/adjacency).

Orchestrator read-only check of the world folder after the connect (never opens secret.txt):

```
0 turtle-helper ['bridge.txt', 'chat.lua', 'client.lua', 'debug', 'debug.log', 'secret.txt', 'startup.lua']
1 - ['_marker.txt']
2 turtle-helper ['bridge.txt', 'chat.lua', 'client.lua', 'debug', 'secret.txt', 'startup.lua']
3 turtle-helper ['bridge.txt', 'chat.lua', 'client.lua', 'debug', 'secret.txt', 'startup.lua']
base/chat.lua SAME
turtle/client.lua SAME
```

(computer 1 is the retired Phase 3 device B folder holding only `_marker.txt`.)

## Task 2 evidence (orchestrator-captured bridge log, verbatim)

BRIDGE_REQUEST_LOG (the devices question with both computers, LOOP-03, D-03, D-12; then the tool error, LOOP-04, D-05):

```
2026-09-25 19:54:39,377 INFO request from DisraSenkovi: what devices are connected
2026-09-25 19:54:40,453 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 19:54:41,466 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 19:54:41,469 INFO answer for DisraSenkovi (plain text, not spoken by the model): You've got two devices connected: a chat receiver (device-0) for talking, and a computer (device-3) that can list chests, move items, and report its status.
2026-09-25 19:54:41,473 INFO spoke the final output to DisraSenkovi on the model's behalf
2026-09-25 20:00:41,375 INFO request from DisraSenkovi: what is in minecraft:chest_99?
2026-09-25 20:00:42,824 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 20:00:42,859 INFO tool list_chest@device-3({'name': 'minecraft:chest_99'}) -> {'ok': False, 'type': 'result', 'error': '/client.lua:69: no inventory called minecraft:chest_99', 'cid': '25705706'}
2026-09-25 20:00:43,828 INFO HTTP Request: POST https://api.anthropic.com/v1/messages?beta=true "HTTP/1.1 200 OK"
2026-09-25 20:00:43,830 INFO answer for DisraSenkovi (plain text, not spoken by the model): There's no chest called minecraft:chest_99 connected to the network. What chests do you have that I should check instead?
2026-09-25 20:00:43,831 INFO spoke the final output to DisraSenkovi on the model's behalf
```

DEVICES_ANSWER_2 (LOOP-03, two devices): "You've got two devices connected: a chat receiver (device-0) for talking, and a computer (device-3) that can list chests, move items, and report its status." Names device-0 and device-3 as separate devices, no fallback. The model answered in plain text (two API calls: list_devices, then text) and the bridge whispered it to the requester, the 02-07 delivery guarantee. The `answer for` line, repeated from the block above:

```
2026-09-25 19:54:41,469 INFO answer for DisraSenkovi (plain text, not spoken by the model): You've got two devices connected: a chat receiver (device-0) for talking, and a computer (device-3) that can list chests, move items, and report its status.
```

TOOL_ERROR_ANSWER (LOOP-04, tool error): "There's no chest called minecraft:chest_99 connected to the network. What chests do you have that I should check instead?" Plain language, no fallback; the bridge kept running (the next lines are its own). The tool call and the `answer for` line, repeated from the block above:

```
2026-09-25 20:00:42,859 INFO tool list_chest@device-3({'name': 'minecraft:chest_99'}) -> {'ok': False, 'type': 'result', 'error': '/client.lua:69: no inventory called minecraft:chest_99', 'cid': '25705706'}
2026-09-25 20:00:43,830 INFO answer for DisraSenkovi (plain text, not spoken by the model): There's no chest called minecraft:chest_99 connected to the network. What chests do you have that I should check instead?
```

CHAT_REPLY_AS_SHOWN: the author chose "use the log" instead of chat screenshots. The two replies are the `answer for` texts above. In both runs the model ended with plain text rather than calling `say`, so the bridge spoke the text on the model's behalf. It was sent as a whisper to DisraSenkovi and showed in chat as `[Robot] <text>`, visible to that player only. The author read both replies in chat and confirmed by proceeding to the next step. No screenshot exists, so no other chat formatting is claimed. The texts as the bridge logged them:

```
You've got two devices connected: a chat receiver (device-0) for talking, and a computer (device-3) that can list chests, move items, and report its status.
There's no chest called minecraft:chest_99 connected to the network. What chests do you have that I should check instead?
```

Both texts are plain ASCII, and the author reported no mojibake. These lines cannot show whether 04-02's ASCII fold changed anything in them, so the fold's in-game effect on a non-ASCII answer is still unseen.

## Task 3 check (orchestrator, read-only against `<SERVER_DIR>/world/computercraft/computer/`)

The plan's discovery asserts exactly one turtle-helper folder besides computer 0; there are two (computer 2, the far one, and computer 3), so the orchestrator ran the same check with the discovery narrowed to the folder whose debug.log carries the list_chest round trip. Output:

```
turtle-helper folders other than 0: ['2', '3'] (plan expected exactly one; computer 2 is the far, unloaded one)
CMD_RESULT_LOOP_OK computer/3
```

CMD_RESULT_LOOP: computer 3's `debug.log`, complete (2 lines; the handshake is never logged, so no token):

```
recv: {"type": "cmd", "cid": "25705706", "tool": "list_chest", "args": {"name": "minecraft:chest_99"}}
result: {"ok":false,"type":"result","error":"/client.lua:69: no inventory called minecraft:chest_99","cid":"25705706"}
```

The result frame's keys are type, cid, ok and error, as RESEARCH Finding 7 predicted. The `/client.lua:<line>` prefix comes from the shell's chunk name. It reads line 69 because the 04-01 DEBUG lines are in place.

Comparison with the harness, done by the Task 5 executor:
- The harness cans only successful `list_chest` replies. `harness/scenarios.py` line 85 requires `{"name", "size", "items"}`, so there is no failing `list_chest` to mirror.
- Its canned failure envelope is `FakeDevice.envelope("c2", bogus) == {"type": "result", "cid": "c2", "ok": False, "error": "unknown tool bogus"}` (`harness/scenarios.py` lines 117-120; `harness/harness.py` `envelope()` passes an error reply through as-is).
- That is the same key set as the in-game frame: type, cid, ok, error. The only difference is the error text. client.lua's pcall adds the `/client.lua:<line>:` prefix to a raised error, while an unknown tool is returned as a plain string.
- No wire-shape difference, so D-10 needs no mirror.

## Task 4 evidence (D-11 end state, D-12)

BOOT_A_NORMAL: the base computer (the one with the Chat Box) after `rm debug`, `rm debug.log`, `reboot` (transcribed from the author's screenshot; no DEBUG line):

```
CraftOS 1.9
Programs that are placed in the "startup" folder in
the root of a computer are started on boot.
chat.lua up to date
client.lua up to date
[10:58]  connected to bridge
```

BOOT_SECOND_NORMAL: the second computer (computer 3) after the same (transcribed from the author's screenshot; no DEBUG line):

```
CraftOS 1.9
On an advanced computer you can use "fg" or "bg" to
run multiple programs at the same time.
chat.lua up to date
client.lua up to date
[11:31]  connected as device-3
```

BRIDGE_CONNECT_LINES (orchestrator-captured bridge log, verbatim; the base computer's reboot, then the second computer's, which the author rebooted twice):

```
2026-09-25 20:03:08,539 INFO connection closed
2026-09-25 20:03:08,539 INFO device disconnected: device-0
2026-09-25 20:03:21,305 INFO connection open
2026-09-25 20:03:21,306 INFO device connected: device-0 (chat) caps=['say']
2026-09-25 20:03:28,340 INFO connection closed
2026-09-25 20:03:28,340 INFO device disconnected: device-3
2026-09-25 20:03:41,977 INFO connection open
2026-09-25 20:03:41,979 INFO device connected: device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']
2026-09-25 20:03:44,337 INFO connection closed
2026-09-25 20:03:44,338 INFO device disconnected: device-3
2026-09-25 20:03:48,468 INFO connection open
2026-09-25 20:03:48,469 INFO device connected: device-3 (computer) caps=['list_chest', 'push_one_slot', 'status']
```

The far computer (computer 2) could not be reached in game again ("i cant get to the far computer"). Its folder held only the empty `debug` marker directory and no `debug.log` (a client.lua device logs command frames only, never chat), so the author deleted that one empty folder on disk in Explorer (`<SERVER_DIR>\world\computercraft\computer\2\debug`) while the computer was unloaded; the orchestrator wrote nothing into the world folder. Computer 2 stays in the world, unloaded, with main's Lua and no debug files.

Orchestrator read-only listing after the reboots (before the far marker was deleted):

```
0 ['bridge.txt', 'chat.lua', 'client.lua', 'secret.txt', 'startup.lua']
2 ['bridge.txt', 'chat.lua', 'client.lua', 'debug', 'secret.txt', 'startup.lua']
3 ['bridge.txt', 'chat.lua', 'client.lua', 'secret.txt', 'startup.lua']
```

## Task 5 checks

The orchestrator's run, verbatim from the plan:

```
=== check 1: DEVICES_MATCH_MAIN
DEVICES_MATCH_MAIN_OK ['0', '2', '3']
exit=0
=== check 2: REPO_TOKEN_CLEAN
REPO_TOKEN_CLEAN_OK
exit=0
```

What each check proves:
- **Check 1:** main == origin/main for base/chat.lua and turtle/client.lua. Computers 0, 2 and 3 hold both files byte-identical to origin/main. No `debug` or `debug.log` is left in any of them.
- **Check 2:** no tracked or untracked repo file, and no commit in `git log --all -p`, contains the token.

The Task 5 executor re-ran both checks verbatim from `turtle/turtle-helper` at 2026-09-26T03:17Z, read-only. secret.txt was never opened and the token was never printed:

```
DEVICES_MATCH_MAIN_OK ['0', '2', '3']
exit=0
REPO_TOKEN_CLEAN_OK
exit=0
```

The untracked draft of this SUMMARY was on disk during the re-run, so check 2 scanned it too.

## Phase 4 record for Phase 5

FIX_LIST: one line per fix across the phase. Each line gives what was wrong, the fix and the commit sha, in the wording Phase 5 D-13's `Verified in game` block reuses.

```
2026-09-25, CC:Tweaked 1.116.1 / Advanced Peripherals 0.7.46r (04-01): AP 0.7.46r strips every `$` from a hidden chat message (Events.onChatBox String.replace), so `$robot ...` reached chat.lua as `robot ...`. Fix: chat.lua puts the prefix back when the message is hidden. Found by jar inspection before the first run; confirmed in game by the DEBUG line (`text=robot what is atm9`, `hidden=true`). Commit c318561.
2026-09-25, CC:Tweaked 1.116.1 / Advanced Peripherals 0.7.46r (04-02): with `say` as a plain pydantic-ai function tool, Haiku returned an empty turn after speaking, pydantic-ai retried it ("Please return text or call a tool"), the answer was spoken twice and the run failed with UnexpectedModelBehavior. Fix: `say` is the agent's output tool, so the run ends when the model speaks. Commit 8b7f082.
2026-09-25, CC:Tweaked 1.116.1 / Advanced Peripherals 0.7.46r (04-02): Haiku wrote a real em dash despite the plain-ASCII prompt line, and AP shows non-ASCII as mojibake. Fix: `bridge.say()` folds every answer to plain ASCII before the Chat Box call. Commit e6dd9a4.
2026-09-25, CC:Tweaked 1.116.1 / Advanced Peripherals 0.7.46r (04-03): a second computer placed far from the base computer unloads with its chunk (server `simulation-distance=10`) and drops off the bridge, so `list_devices` no longer sees it. Fix: placement only; put the second computer a few blocks from the base computer, not touching the Chat Box. No commit (recipe wording for Phase 5).
```

VERIFIED_FACTS: shapes that held with no fix. Each fact is claimed only where this phase saw it. None of these was proven for a turtle, `push_one_slot` or a non-empty `list_chest`.

```
2026-09-25, CC:Tweaked 1.116.1 / Advanced Peripherals 0.7.46r:
- AP `chat` event order is chat, username, message, uuid, isHidden. Seen: device A's debug.log (04-02),
  `chat event: user=... text=... uuid=... hidden=true extra=nil`.
- chatBox.sendMessage (broadcast, to=nil) and sendMessageToPlayer (whisper) return ok=true.
  Seen: device A's debug.log (04-02), `say returned: ok=true err=nil`.
- The `websocket_message` URL match works: every `say` the bridge sent arrived on the base computer (04-02, 04-03),
  and client.lua on computer 3 received its cmd frame (`recv:` line in its debug.log, 04-03).
- client.lua's failure result shape is {"ok":false,"type":"result","error":"/client.lua:69: no inventory called minecraft:chest_99","cid":"..."}
  (04-03 Task 3, list_chest on a missing chest). Matches RESEARCH Finding 7. The harness cans only successful list_chest
  replies, and its error envelope has the same keys, so there was nothing to mirror under D-10.
- client.lua with nothing attached advertises caps=['list_chest', 'push_one_slot', 'status'], sorted, as role computer
  (04-03, computers 2 and 3). startup.lua picks the computer role when no Chat Box is attached.
- Idle stability: both devices connected and idle for 100 s on the orchestrator's bridge with 0 disconnects
  (more than two 20 s + 20 s ping cycles), so CC:Tweaked answers the bridge's keepalive pings. This answers
  Phase 5 D-04's question early for that 100 s window only; D-04's 5-minute window is still Phase 5's.
- The bridge's own log line `tool <name>@<device>(args) -> result` exists and is the place to read tool calls
  (04-03, `tool list_chest@device-3(...)`).
```

NOTES_FOR_PHASE_5: items carried from 04-02's list, plus what this plan found or was asked for. None is done here (D-09: fix only what blocks the loop).

```
Carried from 04-02:
- Author request (2026-09-25): show the robot's replies on the 2x2 Advanced Monitor block above the base computer
  (next to the Chat Box). New Lua in chat.lua (peripheral.find("monitor"), wrap and scroll the say text), pushed and
  rebooted like any device change. Propose as a quick task after Phase 4, or fold into Phase 5.
- RESEARCH Pitfall 7: Phase 5 D-01's Lua prefix check must test the re-prefixed text, because AP strips every $.
- Whisper vs broadcast: the model whispered most answers (to=DisraSenkovi) and broadcast one (to=nil); both work.
  Which one answers should use is a Phase 5 taste decision.
- A question typed without $robot goes to public chat for everyone and the bridge ignores it (seen once, by accident);
  expected, nothing to fix.
New in 04-03:
- D-04 docs note: Advanced Peripherals hides `$` messages from public chat, so other players see a broadcast answer
  without the question it answers.
- Placement rule for the recipe: the second computer must sit within the server's simulation distance of where the
  player types; in practice a few blocks from the base computer, not touching the Chat Box (a Chat Box beside it would
  make it a second base computer). A far-away computer unloads with its chunk and drops off the bridge.
- The model sometimes answers in plain text instead of calling say; the bridge then speaks it (both 04-03 answers).
  Both paths deliver the answer. When a tool ran first, it costs two API calls either way.
- Computer 2 stays in the world, unloaded, with main's Lua and a copy of the token in its folder (secret.txt). The
  author may break it or re-place it later; if it is broken, its folder and token copy stay on disk until deleted.
- The author now prefers the orchestrator to run the bridge with a captured log during live sessions. Phase 5's proof
  session should plan on that (it changes D-05's "the operator runs the bridge" and makes D-06's pasted bridge lines
  exact copies instead).
- `client.lua:69` in the error prefix is the current line number; it moves with any edit above that line (for example
  if Phase 5's D-02 changes client.lua), so docs should quote it as `/client.lua:<line>:`.
- The idle check ran 100 s with 0 disconnects (VERIFIED_FACTS); D-04's full 5-minute window still runs in Phase 5.
- No mojibake was reported in 04-03; neither answer needed the ASCII fold, so its in-game effect is still unseen.
- The Phase 2 concern "the Lua has never run in game" is now resolved for both files: chat.lua in 04-02 and
  client.lua in 04-03. STATE.md's blocker line can be closed at phase verification.
```

PAID_CALLS: paid model requests in Phase 4. The author typed all of them in game, and no agent made one. Model claude-haiku-4-5 (D-06).

```
Phase 4 total: 10 requests, model claude-haiku-4-5.
  04-01: 0
  04-02: 6 (atm9, docs, whats in a name, ars_nouveau, chest, devices). Derived from device A's debug.log
         hidden $robot chat events, which map 1:1 to `request from` lines (04-02-SUMMARY PAID_CALLS_04_02).
  04-03: 4, counted from bridge logs:
         author's bridge        19:36:24  what devices are connected                     (device-2 missing)
         author's bridge        19:37:39  what devices are connected? use list_devices   (device-2 missing)
         orchestrator's bridge  19:54:39  what devices are connected                     (LOOP-03, two devices)
         orchestrator's bridge  20:00:41  what is in minecraft:chest_99?                  (LOOP-04, tool error)
         Each 04-03 request made two API calls (two HTTP 200 lines per request in the bridge log).
```

## Plan-level verification

| Check | Result |
|-------|--------|
| LOOP-02: pasted `device connected: device-<N> (computer) caps=['list_chest', 'push_one_slot', 'status']` | PASS. `device-3`, 19:53:36 (SECOND_CONNECT), and again at 20:03:41 and 20:03:48. N is not 0, and device-0 was not replaced. |
| LOOP-03, two devices: the reply names both | PASS. It names device-0 and device-3 (DEVICES_ANSWER_2). |
| LOOP-04, tool error: plain reply, bridge survives; CMD_RESULT_LOOP_OK | PASS. TOOL_ERROR_ANSWER; the bridge logged the debug-off reconnects afterwards; CMD_RESULT_LOOP_OK computer/3. |
| LOOP-05: DEVICES_MATCH_MAIN_OK with no debug files left, plus FIX_LIST | PASS. `['0', '2', '3']`, run by the orchestrator and re-run by the executor. FIX_LIST has 4 lines. |
| REPO_TOKEN_CLEAN_OK | PASS (run twice) |
| D-11 end state: no `debug` / `debug.log` on any device, both rebooted with DEBUG off | PASS. Check 1 asserts it. BOOT_A_NORMAL and BOOT_SECOND_NORMAL hold no DEBUG line. |
| D-10: a wire-shape difference is mirrored in harness/ | N/A. The key set matches the harness error envelope, and no code changed. |

Success criteria:
- Two real computers are connected with the right roles and caps: met. device-0 is `(chat) caps=['say']` and device-3 is `(computer)` with the three computer caps.
- The devices question names both: met.
- A tool error is answered in plain words, and the bridge survives it: met.
- Both devices run exactly main's Lua with debug off: met. So does computer 2, which the check also covers.
- Phase 5 has the captured text, the fix list and the paid-call count: met. See the keys above and "Phase 4 in one look".

Frontmatter must-haves not covered above:
- Edge LOOP-03/ordering: any order passes. The reply lists device-0 first.
- Prohibitions held:
  - Nothing was attached to the second computer.
  - No agent printed the token or wrote into the world folder. The author deleted computer 2's empty `debug` folder himself.
  - No agent acted in game or made a paid call.
  - The orchestrator did run the bridge, at the author's direction (deviation b).

## Decisions Made

- The second computer's placement is a recipe rule, not a code change: within simulation distance of the player, a few blocks from the base computer and not touching the Chat Box. Computer 3 replaced computer 2 rather than chunk-loading computer 2.
- The in-game failure frame matches the harness's error-envelope key set, so D-10 required no harness or test change.
- CHAT_REPLY_AS_SHOWN is taken from the bridge log at the author's choice, not from screenshots.
- The author directed that the orchestrator runs the bridge with a captured log during live sessions. This is recorded for Phase 5's proof session.

## Deviations from Plan

**(a) The orchestrator ran the checkpoints and Task 3 inline.** The plan's own "How this plan runs" section prescribes this, so it is not a rule deviation. This executor re-ran Task 5's checks, completed this SUMMARY and did the close-out.

**(b) Author-directed: the orchestrator ran the bridge and captured its log from Task 2 on.**
- The plan says "no agent starts or stops a process". The author set that aside in his words: "I want you to manage the bridge process in a way that you can capture the output. I'll just do the minecraft part".
- The bridge ran from 19:48:10 local, PID 40968, logging to `turtle/turtle-helper/logs/bridge-2026-09-25.log` (gitignored).
- It is still running. This executor did not touch it.
- Effect: BRIDGE_REQUEST_LOG, BRIDGE_CONNECT_LINES and SECOND_CONNECT are exact copies rather than transcriptions.

**(c) Task 3's discovery was narrowed.** The plan asserts exactly one turtle-helper folder besides computer 0, but two exist: computer 2 (far) and computer 3 (near). The orchestrator narrowed discovery to the folder whose debug.log carries the list_chest round trip, and stated this next to the output. Task 5's check 1 needs no narrowing, because it covers every device folder.

**(d) The first second-computer attempt was superseded.**
- Computer 2 was placed far away and dropped off the bridge when its chunk unloaded. The two devices questions on the author's bridge (19:36:24, 19:37:39) therefore saw only device-0.
- After diagnosis, the author placed computer 3 near the base computer.
- Computer 2 could not be reached in game for Task 4. Its empty `debug` marker folder was deleted on disk by the author in Explorer while the computer was unloaded. The orchestrator wrote nothing into the world folder.
- Two paid calls went to this attempt. They are counted in PAID_CALLS.

**(e) CHAT_REPLY_AS_SHOWN comes from the bridge log.** At the author's choice ("use the log"), the replies are the two `answer for` texts, and no chat screenshot exists. The plan asked for "the reply exactly as it shows in chat", so the record states what chat showed (a `[Robot] <text>` whisper to DisraSenkovi) and claims nothing beyond it.

**(f) There are zero `fix(04-03)` commits.** Nothing in the code needed changing. The second computer's first run surfaced no Lua error, and the one finding is placement.

**(g) Process note on the plan commit ledger.** `.git/gsd-plan-head-before-04-03` did not exist. It was written as `f630c0c` (04-02's docs commit), and `commits: 0` is measured from that base. The orchestrator's tracking commits are not counted. Older `(04-03)` commits in history belong to the Fabric transit display workstream.

---

**Total deviations:** 7 recorded: 1 by design (a), 1 author-directed (b), 4 execution adaptations (c, d, e, f) and 1 process note (g). No code auto-fixes. **Impact:** none on the outcome. The narrowed discovery and the superseded computer are covered by Task 5's all-folder check, and the captured bridge log made the evidence more exact than pastes would have been.

## Issues Encountered

- Computer 2, placed far from the base computer, unloaded with its chunk and dropped off the bridge. As a result two paid questions saw only device-0. The placement was diagnosed and computer 3 was placed near the base computer. The finding is FIX_LIST line 4.
- The ping-timeout theory for the drop was tested first and rejected. The 100 s idle window showed 0 disconnects.
- Computer 2's `debug` marker could not be removed in game. The author removed the empty folder on disk.

## User Setup Required

None.

## Next Phase Readiness

Phase complete, ready for verification.

- All four of this plan's requirements (LOOP-02 through LOOP-05) are marked Complete. The shared-ID gate reported 4/4 ready. LOOP-01 was marked in 04-02.
- Phase 5 (resilience proofs and docs) has its inputs in this file:
  - D-11 "What you should see": BOOT_A_NORMAL, BOOT_SECOND_NORMAL, BRIDGE_CONNECT_LINES, BRIDGE_REQUEST_LOG, CHAT_REPLY_AS_SHOWN.
  - D-13 "Verified in game": FIX_LIST, VERIFIED_FACTS.
  - The rest of its planning: NOTES_FOR_PHASE_5 and PAID_CALLS.
- State at the end of the plan:
  - The orchestrator's bridge (PID 40968) is still running.
  - device-0 and device-3 are connected with debug off.
  - Computer 2 is in the world, unloaded.
  - `main` is one docs commit ahead of `origin/main` until the orchestrator pushes. The device Lua is equal on both.
- STATE.md's Phase 2 blocker "The Lua has still never run in game" is resolved by 04-02 (chat.lua) and 04-03 (client.lua). It can be closed at phase verification.

## Self-Check: PASSED

- FOUND: this SUMMARY on disk.
- Commits: none for this plan (`git rev-list --count f630c0c..HEAD` = 0 before this commit). The 04-01 and 04-02 fix commits `c318561`, `8b7f082` and `e6dd9a4` that FIX_LIST cites exist and are on origin/main.
- The thirteen keys are each at the start of a line, each with fenced evidence:
  - SECOND_CONNECT, DEVICES_ANSWER_2, TOOL_ERROR_ANSWER, CMD_RESULT_LOOP;
  - BOOT_A_NORMAL, BOOT_SECOND_NORMAL, BRIDGE_CONNECT_LINES, BRIDGE_REQUEST_LOG, CHAT_REPLY_AS_SHOWN;
  - FIX_LIST, VERIFIED_FACTS, NOTES_FOR_PHASE_5, PAID_CALLS.
- Every fenced block from the orchestrator's draft is kept byte for byte.
- `requirements-completed` equals the plan's `requirements`: [LOOP-02, LOOP-03, LOOP-04, LOOP-05].
- No token, `.env` content or secret.txt content appears anywhere in this file. REPO_TOKEN_CLEAN_OK was re-run with the draft on disk.
- Task 5 checks: DEVICES_MATCH_MAIN_OK ['0', '2', '3'] and REPO_TOKEN_CLEAN_OK, both exit 0.

---
*Phase: 04-in-game-round-trip*
*Completed: 2026-09-25*

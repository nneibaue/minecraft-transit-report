---
phase: 04-in-game-round-trip
plan: 02
subsystem: chat-loop
tags: [cc-tweaked, advanced-peripherals, chat-box, pydantic-ai, output-tool, ascii-fold, in-game, haiku]

requires:
  - phase: 04-in-game-round-trip
    provides: "04-01's $ restore in chat.lua, the debug-marker DEBUG log, the D-07 prompt line, all on origin/main (RAW_MATCH_OK)"
  - phase: 03-local-server-setup
    provides: "device A (computer 0, the base computer with the Chat Box) installed from GitHub main, push-then-reboot update path, read-only world-folder byte compares"
provides:
  - "A working chat loop with the base computer alone: `$robot <question>` in game gets one model-worded [Robot] reply (D-03)"
  - "Finding 1 confirmed in game: AP strips the $ from hidden chat and chat.lua's restore makes $robot reach the bridge (DOLLAR_STRIP_SEEN 6)"
  - "say is the agent's output tool, so a spoken answer ends the run: no duplicate answer, no UnexpectedModelBehavior fallback (8b7f082)"
  - "bridge.say() folds every answer to plain ASCII before the Chat Box call (e6dd9a4, Finding 6)"
  - "LOOP-04 with no second computer: plain-language 'nothing to do it with' reply and the bridge stays up"
  - "LOOP-03 base-computer-only: the devices question names exactly one connected device, the chat device"
affects: [04-03, phase-05-resilience-and-docs]

actuals:
  tokens: 22100   # chars/4 over the four files the two fixes changed (88,551 chars); the diff alone is ~5,200
  tasks: 5
  commits: 2      # measured: git rev-list --count 7b4bf5a..HEAD before the SUMMARY commit
plan_head_before: 7b4bf5a4d3f2aea9c37499314a101a2eeaa8bcd0

tech-stack:
  added: []
  patterns:
    - "The model's spoken reply is the run's output: say is registered as a pydantic-ai ToolOutput, not a function tool"
    - "Chat Box text is ASCII-folded in bridge.say(); the prompt's plain-ASCII line is the preference, the fold is the guarantee"
    - "In-game evidence comes from the device's own debug.log (read-only), so nobody transcribes the screen"

key-files:
  created:
    - .planning/workstreams/turtle-helper/phases/04-in-game-round-trip/04-02-SUMMARY.md
  modified:
    - turtle/turtle-helper/bridge/agent.py
    - turtle/turtle-helper/tests/test_agent.py
    - turtle/turtle-helper/bridge/bridge.py
    - turtle/turtle-helper/tests/test_bridge_resilience.py

key-decisions:
  - "say is the agent's output tool (output_type=[str, ToolOutput(say, name=\"say\")]): calling it ends the run, so pydantic-ai never asks for a follow-up text turn that Haiku answers with an empty response"
  - "Every answer is folded to plain ASCII inside bridge.say() (ascii_fold) before the Chat Box call, because Haiku ignored the plain-ASCII prompt line once and the Chat Box shows non-ASCII as mojibake"
  - "The first loop needed no Lua fix beyond 04-01's $ restore: both 04-02 fixes are bridge-side, the device wire is unchanged and harness/ is untouched (D-10)"

patterns-established:
  - "Bridge-side loop fixes need only a bridge restart by the operator, no push-and-reboot of a device"

requirements-completed: [LOOP-01, LOOP-03, LOOP-04, LOOP-05]

coverage:
  - id: D1
    description: "LOOP-01: after the reboot onto 04-01's chat.lua the bridge logs `device connected: device-0 (chat) caps=['say']`, and device A runs origin/main's chat.lua with the debug marker"
    requirement: LOOP-01
    verification:
      - kind: other
        ref: "Plan 04-02 Task 2 check (DEVICE_A_READY_OK) plus the pasted LOOP01_CONNECT bridge line"
        status: pass
    human_judgment: false
  - id: D2
    description: "LOOP-05: every loop fix lives in the repo and is pushed; device A's chat.lua and client.lua equal origin/main; debug.log holds hidden `text=robot` chat events (Finding 1)"
    requirement: LOOP-05
    verification:
      - kind: other
        ref: "Plan 04-02 Task 5 check (DOLLAR_STRIP_SEEN 6, CHAT_LOOP_PROVEN_OK)"
        status: pass
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_device_lua.py (13/13)"
        status: pass
    human_judgment: false
  - id: D3
    description: "say as the agent's output tool: a spoken answer ends the run with no empty follow-up turn and no duplicate"
    requirement: LOOP-05
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_agent.py#test_say_ends_the_run_so_no_empty_follow_up_turn_is_requested (suite 28/28)"
        status: pass
    human_judgment: false
  - id: D4
    description: "bridge.say() folds answers to plain ASCII before the Chat Box call (Finding 6)"
    requirement: LOOP-05
    verification:
      - kind: unit
        ref: "turtle/turtle-helper/tests/test_bridge_resilience.py#test_say_folds_non_ascii_to_plain_ascii_before_the_chat_box (suite 13/13)"
        status: pass
    human_judgment: true
    rationale: "The unit test proves the fold; the fix went live at the operator's 10:50:55 bridge restart and no question has been asked since, so the absence of mojibake in game is first seen in Plan 04-03"
  - id: D5
    description: "D-03: the author's own ATM9 question (ars_nouveau) got one model-worded [Robot] reply, not the fallback"
    verification: []
    human_judgment: true
    rationale: "The reply's quality and its appearance in game chat were judged by the author reading chat; a whispered in-game reply cannot be asserted by a test"
  - id: D6
    description: "LOOP-04, no second computer: the chest question got a plain reply saying the robot has nothing to look into chests with, and the bridge stayed up"
    requirement: LOOP-04
    verification: []
    human_judgment: true
    rationale: "Whether the wording is a plain-language 'cannot do it' reply is a human read of the in-game reply; the bridge surviving is shown by the next question's answer"
  - id: D7
    description: "LOOP-03, base computer only: the devices question named exactly one connected device (the chat device) and no other"
    requirement: LOOP-03
    verification: []
    human_judgment: true
    rationale: "The spoken reply names 'a chat device' rather than the id device-0; judging that it answers the question correctly is a human read"

duration: 1h 0m
completed: 2026-09-25
status: complete
---

# Phase 4 Plan 02: Base-Computer-Only Round Trip Summary

**`$robot` questions typed in game now get exactly one model-worded [Robot] reply through the real base computer and Chat Box. Two bridge-side fixes made that work: `say` became pydantic-ai's output tool (`8b7f082`), and answers are folded to plain ASCII before the Chat Box (`e6dd9a4`). The device's own debug.log confirms that AP strips the `$` and that chat.lua's restore works (6 hidden `text=robot` events).**

## Performance

- **Duration:** about 1h 0m, most of it the author typing questions in game.
- **Started:** 2026-09-25T17:00:00Z. The orchestrator presented Task 1 at that time.
- **Completed:** 2026-09-25T18:00:06Z
- **Tasks:** 5 of 5
- **Files modified:** 4, all bridge-side: `bridge/agent.py`, `tests/test_agent.py`, `bridge/bridge.py`, `tests/test_bridge_resilience.py`. No Lua file changed in this plan.

## Accomplishments

- The chat loop works end to end with the base computer alone. It carried six `$robot` requests from game chat through the Chat Box event, chat.lua, the bridge, Haiku and back through the Chat Box.
- Finding 1 is confirmed in game. Every hidden `$robot` message reached chat.lua as `text=robot ...` with `hidden=true`, and the bridge still accepted it, so chat.lua's `$` restore works (DOLLAR_STRIP_SEEN 6).
- Round 1 failed with a duplicate answer and then `UnexpectedModelBehavior`. Fix 1 made `say` the agent's output tool. After it, every question got exactly one reply.
- LOOP-04, no second computer: the chest question got a plain "I can't see into chests" reply. The devices question after it was answered too, so the bridge stayed up.
- LOOP-03, base computer only: the devices question named exactly one connected device, the chat device.
- Finding 6 was seen as a real em dash in a reply. Fix 2 folds every answer to plain ASCII inside `bridge.say()`.

## Task Commits

| Task | Name | Type | Commit(s) |
|------|------|------|-----------|
| 1 | Pre-flight: bridge restarted, `mkdir debug` + reboot on the base computer, LOOP-01 re-confirmed | checkpoint:human-action | none (live steps by the operator and author) |
| 2 | DEVICE_A_READY_OK check and start of the SUMMARY | auto | none (read-only check, run by the orchestrator) |
| 3 | ATM9 question and fix loop (2 rounds) | checkpoint:human-verify | `8b7f082` fix(04-02): make say the agent's output tool so the run ends when the model speaks; `e6dd9a4` fix(04-02): fold answers to plain ASCII before the Chat Box (Finding 6) |
| 4 | LOOP-04 chest question, then LOOP-03 devices question | checkpoint:human-verify | none |
| 5 | Prove the chat loop from disk and record it | auto | this SUMMARY's docs commit |

Both fix commits are on origin/main (`main` == `origin/main` == `e6dd9a4` when Task 5 ran).

## Files Created/Modified

- `turtle/turtle-helper/bridge/agent.py`: `configure()` registers `say` as the agent's output tool with `output_type=[str, ToolOutput(say, name="say")]`. A plain-text final answer is still spoken by the bridge.
- `turtle/turtle-helper/tests/test_agent.py`: updated for the output-tool shape (28 tests). Adds the regression test `test_say_ends_the_run_so_no_empty_follow_up_turn_is_requested`.
- `turtle/turtle-helper/bridge/bridge.py`: new `ascii_fold` helper, applied in `say()` before the Chat Box frame is sent. It maps typographic punctuation to ASCII, strips accents and drops emoji.
- `turtle/turtle-helper/tests/test_bridge_resilience.py`: adds `test_say_folds_non_ascii_to_plain_ascii_before_the_chat_box` (13 tests).

## Evidence

Every fenced block in Tasks 1-4 below is pasted or transcribed verbatim from the operator's terminal, the author's screenshots or the device's debug.log. Nothing is reconstructed. The Task 1-4 sections were written by the orchestrator during execution; the Task 5 executor completed the rest.

## Task 1 evidence (2026-09-25)

CONFIG_LINE: the bridge's `config:` and `bridge_token:` lines after the operator restarted the bridge (`uv run .\bridge\bridge.py`, 10:04 local). No secret values appear in these lines.

```
2026-09-25 10:04:01,821 INFO HTTP Request: GET https://api.anthropic.com/v1/models/claude-haiku-4-5 "HTTP/1.1 200 OK"
2026-09-25 10:04:01,824 INFO verified model: claude-haiku-4-5
2026-09-25 10:04:01,824 INFO config: model=claude-haiku-4-5 host=127.0.0.1:8765 prefix='$robot' allowed_players=['DisraSenkovi'] ping_interval=20 ping_timeout=20 env_file=C:\Users\nneib\code\minecraft-transit-report\turtle\turtle-helper\.env
2026-09-25 10:04:01,824 INFO bridge_token: set
2026-09-25 10:04:01,830 INFO server listening on 127.0.0.1:8765
2026-09-25 10:04:01,830 INFO listening on ws://127.0.0.1:8765
```

Read-back (A6 settled): model is claude-haiku-4-5, prefix is `$robot`, the one allowed player is DisraSenkovi (exact case). No `.env` change was needed.

BOOT_A_DEBUG: what the base computer (computer 0, the one with the Chat Box) printed after `mkdir debug` and `reboot` (transcribed from the author's screenshot).

```
CraftOS 1.9
Use "pastebin put" to upload a program to pastebin.
chat.lua up to date
client.lua up to date
[16:46]  connected to bridge
```

Note: both files printed `up to date` rather than `updated`. Task 2's byte-compare (below) confirms the on-disk chat.lua already equals origin/main, so the device had pulled 04-01's files on an earlier boot; this is not a stale raw-GitHub copy.

LOOP01_CONNECT: the bridge's new `device connected:` line (transcribed from the author's screenshot).

```
2026-09-25 10:08:07,035 INFO connection open
2026-09-25 10:08:07,039 INFO device connected: device-0 (chat) caps=['say']
```

## Task 2 check (orchestrator, read-only against `<SERVER_DIR>/world/computercraft/computer/0/`)

```
DEVICE_A_READY_OK
exit=0
```

(device A's chat.lua == origin/main and contains `"$" .. text`; the `debug` marker exists.)

## Task 3 fix loop

### Round 1: `$robot what is atm9` (about 10:09 local)

What the author saw in chat: the answer twice, then `[Robot] Sorry DisraSenkovi, something went wrong: UnexpectedModelBehavior`.

Device A `debug.log` (read from disk; verbatim):

```
chat event: user=DisraSenkovi text=robot what is atm9 uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=nil prefix=Robot text=ATM9 is short for "All the Mods 9," the modpack we're playing in right now. It's a massive kitchen-sink modpack with hundreds of mods including Create, Mekanism, Applied Energistics, and tons more - there's so much to explore and build with.
say returned: ok=true err=nil
say: to=nil prefix=Robot text=ATM9 is short for "All the Mods 9," the modpack we're playing in right now. It's a massive kitchen-sink modpack with hundreds of mods including Create, Mekanism, Applied Energistics, and tons more - there's so much to explore and build with.
say returned: ok=true err=nil
say: to=DisraSenkovi prefix=Robot text=Sorry DisraSenkovi, something went wrong: UnexpectedModelBehavior
say returned: ok=true err=nil
```

Bridge traceback tail (pasted by the author):

```
pydantic_ai.exceptions.ToolRetryError: Please return text or call a tool.

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "C:\Users\nneib\code\minecraft-transit-report\turtle\turtle-helper\bridge\bridge.py", line 222, in on_event
    await agent.handle_request(user, request)
  File "C:\Users\nneib\code\minecraft-transit-report\turtle\turtle-helper\bridge\agent.py", line 553, in handle_request
    result = await agent.run(
  ...
  File "C:\Users\nneib\code\minecraft-transit-report\turtle\turtle-helper\.venv\Lib\site-packages\pydantic_ai\_agent_graph.py", line 398, in consume_output_retry
    raise exceptions.UnexpectedModelBehavior(message) from error
pydantic_ai.exceptions.UnexpectedModelBehavior: Exceeded maximum output retries (1)
```

Diagnosis: the Lua side worked end to end (Finding 1 confirmed: `text=robot what is atm9`, `hidden=true`; the Chat Box call returned ok). The bug was bridge-side: with `say` as a plain function tool, the model spoke through it and then, told to answer only through say(), returned an empty turn. pydantic-ai 2.46.0 treats an empty response as non-actionable, retried it with "Please return text or call a tool", the model said the same answer again (the duplicate in chat), returned empty again, and the output-retry budget (1) was exceeded.

Fix 1 (`8b7f082`): `say` is now the agent's output tool (`output_type=[str, ToolOutput(say, name="say")]` in `bridge/agent.py` configure()), so calling it ends the run with the spoken text as the output. No follow-up turn is requested, nothing is duplicated, and each answered question costs one model call fewer. Plain-text answers still work and are still spoken by the bridge. The device wire is unchanged (no harness change under D-10); `tests/test_agent.py` updated (28 tests), regression test `test_say_ends_the_run_so_no_empty_follow_up_turn_is_requested` added. Bridge-side, so no reboot: the operator restarted the bridge.

### Round 2 (after the bridge restart, about 10:2x-10:37 local)

The author asked several questions; every one got exactly one reply and no fallback. From device A's `debug.log` (verbatim `chat event:` and `say:` lines; a public line the author typed without `$robot` is shown for completeness, the bridge ignores those):

```
chat event: user=DisraSenkovi text=robot do you have access to the docs uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=DisraSenkovi prefix=Robot text=I don't have access to external documentation or the internet. However, I can help you with questions about the All the Mods 9 modpack if you ask directly—things like recipes, mod m[...]
say returned: ok=true err=nil
chat event: user=DisraSenkovi text=robot whats in a name uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=DisraSenkovi prefix=Robot text=That's a deep question! But I'm just a sorting robot -- ask me about mods, recipes, or I can help organize your items.
say returned: ok=true err=nil
chat event: user=DisraSenkovi text=what are some things i can do with ars_nouveau uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=false extra=nil
chat event: user=DisraSenkovi text=robot what are some things i can do with ars_nouveau uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=DisraSenkovi prefix=Robot text=Ars Nouveau is a spellcasting mod! You can create custom spells by combining glyphs (effects) and behaviors, craft magical gear, transmute materials, and automate tasks with spells. You'll need to gather mana from the world and progress through different spell tiers as you level up your Magic Affinity.
say returned: ok=true err=nil
```

ATM9_ANSWER (D-03): the ars_nouveau reply as shown in chat (transcribed from the author's screenshot; the say line above is the on-disk copy):

```
<DisraSenkovi> what are some things i can do with ars_nouveau
[Robot] Ars Nouveau is a spellcasting mod! You can create custom spells by combining glyphs (effects) and behaviors, craft magical gear, transmute materials, and automate tasks with spells. You'll need to gather mana from the world and progress through different spell tiers as you level up your Magic Affinity.
```

Bridge `request from` / `answer for` lines for this question: not pasted by the author; the device debug.log lines above are the on-disk record.

Finding 6 sighted: the docs reply holds a real em dash (`directly\xe2\x80\x94things` in the log bytes), which the Chat Box shows as mojibake. Pre-approved fix applied.

Fix 2 (`e6dd9a4`): `bridge.say()` folds the text to plain ASCII before the Chat Box call (`ascii_fold` in `bridge/bridge.py`: typographic punctuation to ASCII, accents stripped, emoji dropped). Prompt line stays as the preference; the fold is the guarantee. Test `test_say_folds_non_ascii_to_plain_ascii_before_the_chat_box` added (13 tests in `tests/test_bridge_resilience.py`). Bridge-side: the operator restarts the bridge; no reboot.

## Task 4 evidence (from device A's `debug.log`, verbatim)

```
chat event: user=DisraSenkovi text=robot what is in the chest next to you uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=DisraSenkovi prefix=Robot text=I don't have any turtles or inventory readers connected, so I can't see into chests. Connect one and I'll be happy to help!
say returned: ok=true err=nil
chat event: user=DisraSenkovi text=robot what devices are connected uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=DisraSenkovi prefix=Robot text=Right now I only have a chat device connected. No turtles, chests, or inventory readers yet -- connect some and I can start helping with sorting and item management!
say returned: ok=true err=nil
```

NO_WORKER_ANSWER (LOOP-04): the chest question got a plain reply saying it has nothing to look into chests with, not the fallback. Bridge `answer for` line: not pasted by the author; the device debug.log lines above are the on-disk record. The chest lines, repeated from the block above:

```
chat event: user=DisraSenkovi text=robot what is in the chest next to you uuid=d5c030d0-88ab-4d73-997e-3a370791ced1 hidden=true extra=nil
say: to=DisraSenkovi prefix=Robot text=I don't have any turtles or inventory readers connected, so I can't see into chests. Connect one and I'll be happy to help!
say returned: ok=true err=nil
```

DEVICES_ANSWER_1 (LOOP-03, base computer only): the devices question got its own reply after the failure request, so the bridge stayed up (LOOP-04 concurrency). Bridge line pasted by the author:

```
2026-09-25 10:37:16,387 INFO answer for DisraSenkovi (spoken via say): Right now I only have a chat device connected. No turtles, chests, or inventory readers yet -- connect some and I can start helping with sorting and item management!
```

Note for the verifier: the reply names "a chat device" rather than the id `device-0`; it names exactly one connected device and no other, which is the LOOP-03 substance. Phase 2's 02-07 decision already chose not to require the id in the spoken text. Plan 04-03's two-device question will show whether ids get named when it matters.

Bridge still running after both: yes (the devices reply arrived after the chest reply; the author confirmed the window kept printing).

State at the end of the plan: the operator restarted the bridge at 10:50:55 local (17:50:55Z) to load fix 2. The base computer reconnected at 10:50:58 local with `device connected: device-0 (chat) caps=['say']`. The orchestrator reported this from the operator's terminal. No question has been asked since that restart, so fix 2's first in-game use falls in Plan 04-03. Device A still has the `debug` marker and `debug.log`, which Plan 04-03 Task 4 removes.

## Running fix list (Task 3)

(one line per fix: symptom, cause, fix, sha)

1. Symptom: answer spoken twice, then "something went wrong: UnexpectedModelBehavior" on every question. Cause: say was a plain function tool, so pydantic-ai demanded a text turn after it and Haiku returned an empty one (twice). Fix: say registered as the agent's output tool, ending the run when the model speaks. Commit `8b7f082`.
2. Symptom: a real em dash in the docs reply (`directly\xe2\x80\x94things`), mojibake in chat per Finding 6. Cause: Haiku ignored the plain-ASCII prompt line once. Fix: `ascii_fold` in `bridge.say()`. Commit `e6dd9a4`.

## Task 5: from-disk proof and the remaining keys

DOLLAR_STRIP_SEEN: output of Task 5's check, run from `turtle/turtle-helper` at 2026-09-25T17:58Z. It is read-only against `<SERVER_DIR>/world/computercraft/computer/0/` and prints a count, never the log lines.

```
DOLLAR_STRIP_SEEN 6
CHAT_LOOP_PROVEN_OK
exit=0
```

The check asserts four things:
- main == origin/main for `base/chat.lua` and `turtle/client.lua`;
- device A's on-disk `chat.lua` and `client.lua` equal origin/main;
- debug.log holds 6 `chat event:` lines with `text=robot` and `hidden=true`, which is Finding 1 seen in game;
- the count matches the six hidden `$robot` events in the Task 3 and Task 4 blocks above.

FIXES_04_02: one line per fix (symptom, cause, fix, sha). The first line is carried from 04-01.

```
0. (04-01) AP 0.7.46r strips every $ from a hidden chat message (Events.onChatBox String.replace); chat.lua puts the prefix back when hidden. Found by jar inspection before the first run; confirmed in game by the DEBUG line (debug.log: text=robot ... hidden=true, 6 events; DOLLAR_STRIP_SEEN 6). c318561
1. Symptom: answer spoken twice, then "something went wrong: UnexpectedModelBehavior" on every question. Cause: say was a plain function tool, so pydantic-ai demanded a text turn after it and Haiku returned an empty one (twice). Fix: say registered as the agent's output tool, ending the run when the model speaks. 8b7f082
2. Symptom: a real em dash in the docs reply (directly\xe2\x80\x94things), mojibake in chat per Finding 6. Cause: Haiku ignored the plain-ASCII prompt line once. Fix: ascii_fold in bridge.say(). e6dd9a4
```

PAID_CALLS_04_02: paid model requests made by the author typing in game. No agent made one.

```
6 requests, model claude-haiku-4-5:
  atm9 (round 1), docs, whats in a name, ars_nouveau (round 2), chest, devices (Task 4)
Source: derived from device A's debug.log hidden $robot chat events, which map 1:1 to the bridge's
`request from` lines; the bridge's `request from` lines themselves were not pasted by the author.
Round 1's single request made about four API calls inside pydantic-ai (say, empty, say again, empty)
before the output-retry limit. After fix 1 each request ends when the model calls say.
```

NOTES_FOR_PHASE_5: found or asked for during 04-02 and deliberately not done here (D-09: fix only what blocks the loop).

```
- Author request during 04-02 (2026-09-25): show the robot's replies on the 2x2 Advanced Monitor block placed
  above the base computer (four Advanced Monitors, next to the Chat Box). New Lua in chat.lua
  (peripheral.find("monitor"), wrap and scroll the say text), pushed and rebooted like any device change.
  Deliberately not done inside the Phase 4 fix loop (D-09: fix only what blocks the loop); propose as a quick
  task right after Phase 4, or fold into Phase 5.
- RESEARCH Pitfall 7: Phase 5 D-01's Lua prefix check must test the re-prefixed text, because AP strips every $.
- The model whispers most answers (to=DisraSenkovi) and broadcast the first one (to=nil); both work. Whether
  answers should be broadcast or whispered is a Phase 5 taste decision.
- A question typed without $robot goes to public chat for everyone and is ignored by the bridge (seen once, by
  accident); expected, nothing to fix.
- Not seen in 04-02: idle reconnect churn, an outbox wedge (Pitfall 2 requeue). Mojibake was seen once and is
  now folded bridge-side (e6dd9a4); its in-game confirmation is Plan 04-03's first question.
```

## Plan-level verification

| Check | Result |
|-------|--------|
| LOOP-01: pasted `device connected: device-0 (chat) caps=['say']` | PASS (LOOP01_CONNECT, 10:08:07; again at 10:50:58 after the fix 2 restart) |
| D-03: the ATM9 question gets a model-worded reply, not the fallback | PASS (ATM9_ANSWER, ars_nouveau reply) |
| LOOP-04: plain reply with no second computer; the bridge survives | PASS (NO_WORKER_ANSWER; DEVICES_ANSWER_1 arrived afterwards) |
| LOOP-03, base computer only: exactly one device named | PASS on substance (names "a chat device" rather than the id `device-0`; see the note under DEVICES_ANSWER_1) |
| LOOP-05: DEVICE_A_READY_OK and CHAT_LOOP_PROVEN_OK | PASS (both printed, exit 0) |
| LOOP-05: every fix is a pushed `fix(04-02)` commit | PASS (`8b7f082`, `e6dd9a4`; main == origin/main == e6dd9a4) |
| D-10: a wire change is mirrored in harness/ | N/A: neither fix changed the device wire; `git diff --name-only 7b4bf5a..HEAD` touches nothing under harness/ |
| Test suites (zero spend), re-run at Task 5 | test_agent 28/28, test_bridge_resilience 13/13, test_device_lua 13/13, test_harness_scenarios 5/5 |

Success criteria:
- A `$robot` question typed in game gets a spoken answer through the real base computer: met.
- An unfulfillable request gets a plain reply, and the bridge survives it: met.
- The devices question is answered correctly with one device connected: met. It names the chat device, not the id.
- All first-run fixes live in the repo: met. Both are on origin/main and neither was edited on a device.

## Decisions Made

- `say` is the agent's output tool, not a function tool. Calling it ends the run, so pydantic-ai 2.46.0 never asks for a follow-up turn that Haiku fills with an empty response. As a side effect, each answered question costs one model call fewer. A plain-text final answer is still spoken by the bridge (the 02-07 guarantee holds).
- The ASCII fold lives in `bridge.say()`, one place for every spoken line. The D-07 prompt line stays as the preference.
- The devices reply naming "a chat device" rather than `device-0` is accepted for LOOP-03 base-computer-only, in line with 02-07's decision not to require ids in spoken text. Plan 04-03's two-device question is where ids matter.

## Deviations from Plan

**1. Execution split: the orchestrator ran Tasks 2-4 and the fix loop inline, and this executor only closed out.** This is how the plan's own "How this plan runs" section prescribes it (D-08), so it is not a rule deviation. The Task 5 executor ran the from-disk check, completed this SUMMARY and did the state updates.

**2. Fix 1 changes the bridge architecture: `say` is registered as an output tool instead of a function tool.**
- **Found during:** Task 3, round 1.
- **Issue:** the answer was spoken twice, then `UnexpectedModelBehavior: Exceeded maximum output retries (1)`, then the fallback reply.
- **Fix:** the orchestrator applied it as the fix that unblocked the loop.
- **Files modified:** `bridge/agent.py`, `tests/test_agent.py`.
- **Verification:** 28/28 tests pass, and every round 2 question got exactly one reply.
- **D-10:** the device wire did not change, so harness/ is untouched.
- **Committed in:** `8b7f082`.

**3. Fix 2 is the plan's pre-approved Finding 6 ASCII fold, applied on sight of a real em dash in debug.log.**
- **Files modified:** `bridge/bridge.py`, `tests/test_bridge_resilience.py`.
- **Verification:** 13/13 tests pass.
- **Committed in:** `e6dd9a4`.

**4. Process note: the plan commit ledger.** `.git/gsd-plan-head-before-04-02` did not exist. It was written as `7b4bf5a`, the orchestrator's tracking commit right before this plan's first fix. `commits: 2` is measured from that base. Older `(04-02)` commits in history belong to the Fabric transit display workstream.

---

**Total deviations:** 2 code fixes in the loop, both bridge-side (1 blocking architectural fix, 1 pre-approved on-sight fix), plus 2 process notes. **Impact:** both fixes were needed for a correct, readable reply in chat. No Lua change, no wire change, no scope creep.

## Issues Encountered

- Round 1 failed with `UnexpectedModelBehavior`, after a duplicated answer. Fixed by fix 1.
- A real em dash in the docs reply (Finding 6). Fixed by fix 2.
- The author never pasted the bridge's `request from` / `answer for` lines for the ATM9 and chest questions. Only the devices `answer for` line was pasted. Device A's debug.log is the on-disk record, and the paid-call tally is derived from it.

## User Setup Required

None. The operator already restarted the bridge to load fix 2 (10:50:55 local).

## Next Phase Readiness

- Ready for 04-03 (the second computer, LOOP-02). The bridge is running with both fixes, and the base computer is connected as `device-0 (chat)`.
- 04-03's first question is also the first in-game use of the ASCII fold.
- Plan 04-03 Task 4 removes device A's `debug` marker and `debug.log`.
- LOOP-03, LOOP-04 and LOOP-05 stay Pending in REQUIREMENTS.md until 04-03 finishes, because 04-03 declares them too (shared-ID gate). LOOP-01 is marked Complete now.
- The Phase 2 concern that the Lua had never run in game is now resolved for the chat side. client.lua's first in-game run is 04-03.

## Self-Check: PASSED

- FOUND: this SUMMARY; `turtle/turtle-helper/bridge/agent.py`, `tests/test_agent.py`, `bridge/bridge.py`, `tests/test_bridge_resilience.py`.
- FOUND commits: `8b7f082` and `e6dd9a4`, on origin/main.
- The ten keys are each at the start of a line: CONFIG_LINE, BOOT_A_DEBUG, LOOP01_CONNECT, ATM9_ANSWER, NO_WORKER_ANSWER, DEVICES_ANSWER_1, DOLLAR_STRIP_SEEN, FIXES_04_02, PAID_CALLS_04_02, NOTES_FOR_PHASE_5.
- No token, `.env` content or secret.txt content appears anywhere in this file.
- Task 5 check: DOLLAR_STRIP_SEEN 6 and CHAT_LOOP_PROVEN_OK.

---
*Phase: 04-in-game-round-trip*
*Completed: 2026-09-25*

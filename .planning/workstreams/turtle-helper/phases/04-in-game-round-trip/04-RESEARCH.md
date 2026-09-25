# Phase 4: In-Game Round Trip - Research

**Researched:** 2026-09-25
**Domain:** CC:Tweaked 1.116.1 + Advanced Peripherals 0.7.46r device Lua against the existing Python bridge (first in-game run)
**Confidence:** HIGH for the event, Chat Box and websocket facts (read from the server's own jars). MEDIUM for how chat renders text, since nothing has been seen on screen yet.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Sequence and devices
- **D-01:** Chat computer first, alone. Connect, the first request, the answer, the failure reply and the Lua fixes are all done with device A only. The worker is added as the last step of the phase, after the chat loop works.
- **D-02:** The worker is one more Advanced Computer running `client.lua`, placed anywhere, with no peripherals and no Chat Box (a Chat Box would make `startup.lua` run `chat`). It is installed with the same one `wget run` line, the typed token and `reboot` (Phase 3 D-14/D-15). It connects as role `computer` with caps `status`, `list_chest`, `push_one_slot`. LOOP-02 is met when the bridge logs it with role and caps and a devices answer includes it. No turtle this phase; the turtle branch of `client.lua` stays unproven. — **Reversibility:** reversible — a turtle is the same install on a different block.

#### The first request and what counts as an answer
- **D-03:** The first in-game request is a free-form question about ATM9 that the author picks at the keyboard (a mod, a recipe, anything), not the devices question. Its purpose is to test the Claude connection end to end. Any real spoken answer in chat counts; the bridge's "something went wrong" fallback does not (the harness's standard). The devices question runs afterwards as the LOOP-03 check, once with chat alone (a correct answer names `device-0` as the chat device and no workers) and once after the worker joins; its wording is not constrained beyond being correct.
- **D-04:** Whisper versus broadcast is the model's choice (`say` keeps its optional `to`); the bridge's plain-text fallback whispers to the requester. No change to the `say` tool. Note for the docs: Advanced Peripherals hides `$`-prefixed messages from public chat, so a broadcast answer appears to other players without its question.
- **D-05:** The LOOP-04 failure case is a request that needs hands while no worker is connected (for example asking what is in a chest). The model has no device tool in that run and must say plainly that it has nothing to do it with. Runs during the chat-only stage. After the worker joins, a second failure case, a tool error on the worker (for example `list_chest` on a made-up inventory name), is recommended if one more call is affordable: it is the only thing this phase that exercises `client.lua`'s `cmd`/`result` loop. Claude's call in the plan whether to include it.
- **D-06:** No fixed spend budget. Every paid call is the author typing in game, so the author controls spend; the plan records the count of paid calls at the end. Model `claude-haiku-4-5`.
- **D-07:** The agent's instructions (`SYSTEM_TEMPLATE`) frame the robot as taking chores. If the researcher or planner judges a one-line addition is needed so a general question gets answered rather than deflected, and to keep answers to a sentence or two for the Chat Box, add it minimally; do not rework the prompt. Claude's call.

#### The fix loop
- **D-08:** The author and the orchestrator iterate directly, no executor per fix. The loop: the author pastes the error from the device screen (and a bridge log line when relevant); the orchestrator fixes the repo file, syntax-checks it with luaparse, commits, pushes `main`, and confirms raw GitHub serves the new bytes (Phase 3's RAW_MATCH check); the author reboots the device; repeat until the ATM9 question is answered in chat. The plan expresses this as one checkpoint that loops, with the plan's tasks being the fixed points around it (worker install, LOOP-05 proof, capture). Per the live-run rule, no agent starts the bridge, the server or a device.
- **D-09:** Every fix lands in the repo first; nothing is patched on the device. Only bugs that block the loop are fixed, no speculative rewrites. The LOOP-05 proof at the end is a read-only byte compare of `computer/<id>/chat.lua` and `client.lua` on both devices against `origin/main` (Phase 3's scratchpad method, never printing the token), plus a list of the fixes made, in the words Phase 5's "Verified in game" block (05 D-13) will reuse.
- **D-10:** A Lua fix that changes a wire shape (a result field, a caps name, an event field) must be mirrored the same day in `harness/` (Phase 2 D-03: the fake worker mirrors `client.lua`) and in `tests/`, so the harness keeps telling the truth. A fix that only changes how `chat.lua` reads an event or calls the Chat Box touches nothing else.

#### Diagnostics and capture
- **D-11:** A `DEBUG` knob, default off, in both `chat.lua` and `client.lua`, kept in the repo. When on: `chat.lua` prints the raw chat event fields as received and the `say` arguments right before the Chat Box call together with the call's return; `client.lua` prints each `cmd` received and the `result` it sends. It never prints the token (the hello frame is not printed). On for the first run; `main` ends the phase with it off. The mechanism is Claude's call: a constant flipped by commit, or a marker file beside `secret.txt` so no commit is needed to toggle it per device.
- **D-12:** Once the loop works, the author pastes, once: device A's boot lines, the bridge log for one request (the event line, the answer line, the say), the chat reply as shown in game, and the worker's connect line. These are the text Phase 5's "What you should see" (05 D-11) and "Verified in game" (05 D-13) are built from. Lines not pasted are not reconstructed.

### Claude's Discretion
- Labels: none needed; ids stay `device-<id>` (device A is `device-0`). If the devices answer reads badly, `label set <name>` on a device is the fix and needs no code.
- The `DEBUG` mechanism (D-11) and its output wording.
- Whether the instruction line in D-07 is added at all.
- Whether the worker tool-error call in D-05 is included.
- Commit granularity and message scope during the fix loop (small `fix(04-NN)` commits per bug are expected).
- The order of the last steps: worker install, then the second devices question, then the optional tool error, then the LOOP-05 byte check and the capture.
- Plan shape, per the workstream's coarse granularity: few plans, 3-5 tasks each. A natural split is (1) DEBUG knob and any prompt line, pushed to `main`; (2) the chat-only loop as one looping checkpoint; (3) worker install, proofs and capture.

### Deferred Ideas (OUT OF SCOPE)
- **Turtle worker.** The turtle branch of `client.lua` (`move`, `turn`, `dig`, `inspect`, `refuel`) stays unproven until a chore needs it (CHORE-02 or later).
- **Wired modem network with chests, and proving `list_chest` / `push_one_slot` / `sort_chest` in game.** CHORE-01's territory; nothing in this phase wires a chest.
- **A constrained devices-answer format (names plus roles in one line).** Offered, not chosen; the model answers freely. Revisit if answers are unclear once two devices exist.
- **Labels for the two computers.** Optional, no code; use `label set` if `device-<id>` reads badly.
- **Merging the chat and worker roles.** Still deferred from Phase 3 D-09; the URL-routing constraint stands. The author's confusion is real, so Phase 5's docs pass explains the split instead.
- **Patching Lua on the device in the in-game editor.** Rejected for this phase (D-09); the push-and-reboot loop is the only path.
- **Executor-per-fix plan shape.** Rejected as too slow for a first-run debugging loop (D-08).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LOOP-01 | `chat.lua` on an Advanced Computer with a Chat Box connects and appears in the bridge log as role `chat` | Already observed in Phase 3 (`device connected: device-0 (chat) caps=['say']`). The re-confirmation is the boot after Plan 1's push. See "Bridge log lines" below. |
| LOOP-02 | `client.lua` on a turtle or Advanced Computer connects and appears with its role and caps | The worker's folder will most likely be `computer/2` (see "Worker id"). Expected caps `['list_chest', 'push_one_slot', 'status']` (sorted). `status` on a bare computer returns right away. |
| LOOP-03 | An allowed player's `$robot what devices are connected?` gets a correct spoken list | **Blocked until Finding 1 is fixed.** AP strips the `$`, so the bridge never sees `$robot`. `list_devices` is a bridge-local tool (no worker command). |
| LOOP-04 | An unfulfillable request gets a plain-language reply and the bridge stays up | With no worker, `build_toolset` exposes no device tools, so the model must say so. The optional worker tool error returns `ok=false` with a `/client.lua:<line>: no inventory called <name>` string. |
| LOOP-05 | First-run Lua errors are fixed in the repo copies | Findings 1-6 list what the jars say will or may fire. Byte-compare method from 03-06. DEBUG marker plus `debug.log` for capture. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

The root `.claude/CLAUDE.md` describes the other product, the Fabric transit display mod. Its Java/Fabric stack rules do not apply here. What does apply:
- **GSD workflow enforcement:** edits go through a GSD command. The orchestrator-led fix loop (D-08) runs inside `/gsd-execute-phase`.
- **Turtle-helper conventions** (from STATE.md and the orchestrator): Python lives under `turtle/turtle-helper/` (uv, pydantic-settings, Pydantic AI, ruff + mypy). Tests are dependency-free TAP scripts under `tests/`, run as `uv run python tests/<file>.py`. Lua stays thin: fixes correct call shapes and event reads, and no logic moves into Lua.
- **Line-1 header invariant:** every device file must start with `-- <name>`. `startup.lua` and `install.lua` reject a download without it.
- **No token printing, ever:** this covers DEBUG output and any debug file written to the world.

## Summary

I read the server's own jars for this research: `AdvancedPeripherals-1.20.1-0.7.46r.jar` and `cc-tweaked-1.20.1-forge-1.116.1.jar`, both in `Server-Files-1.1.1/mods`. They settle most of what the phase had marked "never run in game". The most important result is a bug that is certain to fire: **Advanced Peripherals 0.7.46r removes every `$` from a hidden chat message before it queues the `chat` event.** The player types `$robot what devices are connected?`. `chat.lua` receives `robot what devices are connected?` with `isHidden = true`. The bridge's prefix check (`"$robot"`) then fails, and the bridge returns without logging anything. The first in-game request would get total silence, with no log line and no spend. The prior research (PITFALLS.md §4) did not know this.

The rest of the assumed shapes hold. The event order is `chat, username, message, uuid, isHidden`: four values, with no fifth `messageUtf8` in this build. The Chat Box methods have the argument order `chat.lua` uses and return `true` or `nil, "<reason>"`. The `websocket_message` URL argument is the exact string passed to `http.websocket`, so `ev[2] == BRIDGE_URL` matches. `ws.receive()` returns `nil` on close. Three latent problems are verified from the code but will only fire under certain conditions:
- `chat.lua` requeues *every* failed send at the head of the outbox forever. That includes permanent failures such as `incorrect player name/uuid` when a player has logged off.
- Non-ASCII in model answers (dashes, curly quotes, emoji) will show as mojibake. The bridge escapes them, CC decodes them to UTF-8 bytes, and the Chat Box then reads those bytes one byte per character.
- Ctrl+T does not stop a connected device, because `pcall(session)` catches `Terminated`. Recipes should say "hold Ctrl+R" to reboot a running device.

**Primary recommendation:** In Plan 1, fix the `$` strip in `chat.lua` before the first run: when `hidden` is true, add the `$` back in front of the text before forwarding. This keeps the wire contract the bridge and harness already use, so D-10 needs no harness change. Add the DEBUG knob as a marker (`fs.exists("debug")`). When it is on, lines go to the screen and are also appended to `debug.log`, which the orchestrator reads straight from `world/computercraft/computer/<id>/`. Add one D-07 prompt line that invites direct answers and plain ASCII. Push, confirm RAW_MATCH, then start the in-game loop.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hearing `$robot` chat, restoring the `$` AP stripped | Device: `chat.lua` | — | It is an event-read correction (D-10: touches nothing else). Only the device sees the `hidden` flag next to the raw text. |
| Prefix and allow-list checks, model call, reply guarantee | Bridge (`bridge.py` `on_event`, `agent.handle_request`) | — | Already built in Phase 2. Unchanged. |
| Answer wording, brevity, ASCII | Bridge (`agent.py` `SYSTEM_TEMPLATE`) | — | D-07's one line. The model's text is decided here, not in Lua. |
| Speaking in chat (cooldown, whisper vs broadcast) | Device: `chat.lua` `drainOutbox` | AP Chat Box | Thin wrapper over two AP calls. |
| Executing a worker tool, returning a `result` | Device: `client.lua` | — | Primitive only. Errors are caught by `pcall` and become `ok=false`. |
| Diagnostics (DEBUG) | Device (screen + `debug.log`) | PC reads the world folder read-only | Reading the device folder straight from disk avoids transcribing text off the CC screen. |
| Delivering fixes | GitHub `main`, then `startup.lua` on reboot | — | Phase 3's only update path. |

## Verified Facts (the first-run unknowns)

### Finding 1 — AP strips every `$` and sets `isHidden` [VERIFIED: AP 0.7.46r jar, `Events.onChatBox` bytecode]

`de.srendi.advancedperipherals.common.events.Events.onChatBox(ServerChatEvent)`, from `javap -c` in this session:
```
30: aload_1
31: ldc_w  #297   // String $
34: invokevirtual  java/lang/String.startsWith
37: ifeq   57
42: invokevirtual  net/minecraftforge/event/ServerChatEvent.setCanceled:(Z)V
46: ldc_w  #297   // String $
49: ldc    #187   // String            (empty string)
51: invokevirtual  java/lang/String.replace:(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Ljava/lang/String;
55: iconst_1       // isHidden = true
```
- This is `String.replace("$", "")`, which removes **every** `$` in the message, not only the leading one. `$robot costs $5` arrives as `robot costs 5`.
- The event is cancelled, so the message is hidden from public chat (consistent with D-04's note).
- `onCommand` does the same for `/say $...`.

What the bridge does with the stripped text [VERIFIED: `bridge/bridge.py:212-216`, verbatim]:
```python
    if ev.get("name") == "chat":
        user = str(ev.get("user", ""))
        text = str(ev.get("text", "")).strip()
        if not text.lower().startswith(settings.command_prefix.lower()):
            return
```
The prefix is `command_prefix: str = Field(default="$robot", description="Chat prefix that triggers the agent.")` [VERIFIED: `bridge/settings.py:49-51`]. `robot what...` fails `startswith("$robot")`, so the bridge returns silently. There is no log line, no reply and no model call.

What `chat.lua` forwards today [VERIFIED: `base/chat.lua:58-63`, verbatim]:
```lua
    if ev[1] == "chat" then
      -- ev: "chat", username, message, uuid, isHidden
      ws.send(textutils.serialiseJSON({
        type = "event", name = "chat",
        user = ev[2], text = ev[3], uuid = ev[4], hidden = ev[5] == true,
      }))
```
The harness sends the shape the bridge expects: `text=f"{settings.command_prefix} what devices are connected?"` with `hidden=True` [VERIFIED: `harness/scenarios.py:262-267`]. Adding the `$` back in `chat.lua` (Code Example 1) makes the real device match the harness, so no harness or test change is needed under D-10.

The published docs page (https://docs.advanced-peripherals.de/0.7/peripherals/chat_box/) says a `$` message "will not be sent to the global chat but it will still fire the chat event". It does not say the `$` is removed [CITED]. It also documents a 5th event value, `messageUtf8`, and a `utf8Support` send parameter, and **neither exists in 0.7.46r** (see Findings 2 and 3). That page describes a newer build. The jar wins.

### Finding 2 — `chat` event order: `chat, username, message, uuid, isHidden` [VERIFIED: `ChatBoxPeripheral.lambda$update$6`]

```
30: ldc_w #349  // String chat
33: iconst_4    // 4 arguments after the name
40: Events$ChatMessageObject.username()
47: Events$ChatMessageObject.message()
54: Events$ChatMessageObject.uuid()
61: Events$ChatMessageObject.isHidden()   -> Boolean.valueOf
68: IComputerAccess.queueEvent(String, Object[])
```
`chat.lua`'s `ev[2]..ev[5]` reads are correct. `username` comes from `ServerChatEvent.getUsername()`, the exact-case profile name. The bridge's allow check is case-sensitive: `if settings.allowed_players and user not in settings.allowed_players:` [VERIFIED: `bridge/bridge.py:217`]. So `ALLOWED_PLAYERS` must match the in-game name's case exactly.

### Finding 3 — Chat Box signatures, returns, cooldown [VERIFIED: `ChatBoxPeripheral` + `OperationAbility` bytecode]

| Call | Argument indexes (0-based, from `getString`/`optString`/`optInt`) | Success | Failure returns |
|------|------|---------|-----------------|
| `sendMessage(message, prefix?, brackets?, bracketColor?, range?)` | 0 message; 1 prefix (default config `"AP"`); 2 brackets `"[]"`; 3 color `""`; 4 range `-1` | `true` | `nil, "incorrect bracket string (e.g. [], {}, <>, ...)"` |
| `sendMessageToPlayer(message, username, prefix?, brackets?, bracketColor?, range?)` | 0 message; 1 username; 2 prefix; 3 brackets; 4 color; 5 range | `true` (also when the player is out of range: it just doesn't send) | `nil, "incorrect player name/uuid"`; `false, "NOT_SAME_DIMENSION"` (only when multi-dimension is off) |
| Any call during the cooldown | — | — | `nil, "%s is on cooldown"` (format string, `OperationAbility.performOperation`) |

- Neither method reads a 7th `utf8Support` argument in this build. `sendMessage`'s last read is `optInt(4, -1)` and `sendMessageToPlayer`'s is `optInt(5, -1)`.
- The player lookup is by UUID if the string matches the UUID regex, else `PlayerList.getPlayerByName` (`m_11255_`). An offline player gives `nil, "incorrect player name/uuid"`.
- `chat.lua`'s calls match exactly: `chatBox.sendMessageToPlayer(m.text, m.to, m.prefix or DEFAULT_NAME)` and `chatBox.sendMessage(m.text, m.prefix or DEFAULT_NAME)` [VERIFIED: `base/chat.lua:35,37`].

Server config in effect [VERIFIED: `Server-Files-1.1.1/config/Advancedperipherals/peripherals.toml:54,57,59,168`, verbatim]:
```
defaultChatBoxPrefix = "AP"
chatBoxMaxRange = -1
chatBoxMultiDimensional = true
chatMessageCooldown = 1000
```
Range is infinite and cross-dimension is on, so a whisper reaches the author anywhere. The cooldown is 1000 ms, and `SEND_GAP = 1.1` covers it. PITFALLS.md's "default ~50 blocks" range does not apply to this server.

### Finding 4 — the websocket URL match and `ws.receive()` [VERIFIED: CC 1.116.1 jar]

- `HTTPAPI.websocket` passes the Lua string argument unchanged as `Websocket.address`. It is used for URI parsing too, but the *original string* is what is stored. `WebsocketHandler` queues `websocket_message` with `websocket.address()`. So `ev[2]` is byte-identical to the `BRIDGE_URL` that `chat.lua` passed to `http.websocket(BRIDGE_URL)`, and the check at `base/chat.lua:64` (`elseif ev[1] == "websocket_message" and ev[2] == BRIDGE_URL then`) always matches its own socket. This agrees with Phase 3 D-09 (per-URL routing in `WebsocketHandle$ReceiveCallback`).
- `WebsocketHandle.receive()` calls `checkOpen()` first, which throws `"attempt to use a closed file"` if the socket is already closed. While waiting, a matching `websocket_message` returns `(message, binary)`, and a matching `websocket_closed` returns nothing (`nil`). `client.lua:143-144` (`local raw = ws.receive()` / `if raw == nil then return end -- closed`) is correct. A throw is caught by `pcall(session, ws)`.
- The Lua wrapper `http.websocket` in `rom/apis/http/http.lua:365-387` waits with `os.pullEvent()` for `websocket_success`/`websocket_failure` whose url `== actual_url`. It returns the handle, or `false, err`.
- Keepalive: the Netty pipeline includes `WebSocketClientProtocolHandler`, whose base class normally answers protocol pings. That is Phase 5 D-04's territory. If device A churns every ~40 s, note it and do not chase it [ASSUMED: Netty auto-pong default].

### Finding 5 — JSON edge cases on this wire [VERIFIED: `rom/apis/textutils.lua` in the 1.116.1 jar]

| Case | Behaviour | Effect here |
|------|-----------|-------------|
| Incoming `"to": null` (bridge sends `{"text":..,"to":null,"prefix":..}` for a broadcast) | `unserialiseJSON` returns `nil` for `null` unless `parse_null = true` (textutils.lua:634-638) | `msg.args.to` is `nil`, so `sendMessage`. Correct. |
| Incoming `[]` | Becomes the shared `textutils.empty_json_array` sentinel (691-692) | Never mutate a decoded empty array. Nothing does today. |
| Outgoing empty table | `{}` (object), never `[]` (serializeJSONImpl, `next(t) == nil` → `"{}"`) | `status` on a bare worker sends `"peripherals":{}`, and `pos` is omitted (nil). The model sees that raw. It's not a loop blocker and there's nothing to mirror unless it's "fixed". |
| `list_chest` with no items | Already uses `textutils.empty_json_array` (`client.lua:62`) | Correct. |
| Outgoing non-ASCII bytes | Escaped as `\u00XX` per byte by default | Harmless for ASCII player names and text. |
| Incoming `\uXXXX` | Decoded with `utf8.char(...)` into UTF-8 bytes (textutils.lua:586-589) | See Finding 6. |

### Finding 6 — non-ASCII model text becomes mojibake in chat [VERIFIED mechanism; ASSUMED on-screen result]

The chain has three steps:
1. `bridge.py:69` sends `json.dumps(...)` with the default `ensure_ascii=True`, so `—` goes over the wire as `\u2014`.
2. CC's `unserialiseJSON` turns that into the three bytes `E2 80 94`.
3. The Chat Box reads its Lua string argument through Cobalt `LuaString.decode`, which maps **each byte to one char** (`baload; sipush 255; iand; i2c`, from `cobalt-0.9.6.jar` inside the CC jar). The Chat Box therefore receives `â` plus two control characters.

Haiku often uses em dashes, curly apostrophes and the occasional emoji. There is no `utf8Support` flag in 0.7.46r (Finding 3) to fix this on the device. The cheap mitigation is D-07's prompt line asking for plain ASCII. The fallback, if it still shows, is an ASCII fold in `bridge.say()`. That's bridge-side with no wire change, so apply it only if it's seen (D-09).

### Finding 7 — `client.lua` failure shapes for the D-05 tool error [VERIFIED: code + CC shell]

- With a made-up name, `peripheral.wrap(args.name)` returns `nil`. Then `error("no inventory called " .. tostring(args.name))` runs (`client.lua:57`), `pcall` catches it, and the reply is `{type="result", cid=..., ok=false, error="<pos>: no inventory called <name>"}`.
- CC's shell loads programs with chunk name `"@/" .. path` (`rom/programs/shell.lua:161`), so `<pos>` is `/client.lua:<line>`. The line number moves when DEBUG lines are added.
- `tools.status` on a bare Advanced Computer calls `gps.locate(2)`. With no wireless modem, `gps.locate` returns `nil` immediately and prints nothing when not in debug mode (`rom/apis/gps.lua:117-122`). So `status` answers at once, with no `pos` key.

### Finding 8 — stopping or rebooting a device that is running `chat`/`client` [VERIFIED]

- `os.pullEvent` raises `error("Terminated", 0)` on a terminate event (`bios.lua:41-47`). A press of Ctrl+T while a session is open is caught by `pcall(session, ws)`. The device logs `session error: Terminated` and reconnects 5 s later, and a second Ctrl+T during that `sleep(5)` actually stops the program.
- CC's terminal widget has hold timers for terminate, reboot and shutdown (`TerminalWidget.TERMINATE_TIME = 0.5f`, with `rebootTimer`/`shutdownTimer` fields).
- **Recipes should say "hold Ctrl+R until the screen clears" to reboot a running device**, not "type `reboot`": while `chat.lua` or `client.lua` runs, there is no shell prompt. Holding Ctrl+R for about 0.5 s reboots, which is exactly what the fix loop needs [ASSUMED: the same 0.5 s threshold applies to the reboot timer as to terminate].

### Bridge log lines the plan will capture (D-12) [VERIFIED: `bridge/bridge.py`, `bridge/agent.py`]

- Connect: `device connected: %s (%s) caps=%s` (bridge.py:159-164). Disconnect: `device disconnected: %s`.
- A `$robot` chat event has **no "event from" line**. `event from %s: %s` only fires for non-chat events (bridge.py:226-227). The first line of a request is `request from %s: %s` (agent.py `handle_request`).
- It is followed by `answer for %s (%s): %s`, where the second field is `spoken via say` or `plain text, not spoken by the model`, and possibly `spoke the final output to %s on the model's behalf`.
- A non-allowed player gives `ignoring %s (not allowed)`. A prefix mismatch (Finding 1) gives **nothing**.
- The boot config line prints `model=... allowed_players=[...]` and `bridge_token: set` without secrets (bridge.py:257-269). **The plan's pre-flight step confirms `MODEL` and the author's exact-case name from this line.** It does not read `.env`, which a hook blocks for Bash anyway.

### Worker id and folder [VERIFIED: world folder listing]

- `world/computercraft/ids.json` holds `{"computer": 1}`. Folders `computer/0` (device A: `bridge.txt chat.lua client.lua secret.txt startup.lua`) and `computer/1` (only `_marker.txt`, the retired device B) exist.
- A freshly placed Advanced Computer will most likely get id **2**, connecting as `device-2`. If the author reuses computer 1's block, it will be `device-1` with a harmless leftover `_marker.txt`.
- The LOOP-05 byte compare should **discover** device folders: any `computer/*/` holding `startup.lua` and `secret.txt`. It should not hardcode `2`.
- Both devices hold both `chat.lua` and `client.lua`, because `startup.lua` updates both. So the compare covers 2 files × 2 folders.

## Standard Stack

No new libraries. Everything is already in the repo or the game.

| Component | Version | Purpose |
|-----------|---------|---------|
| CC:Tweaked | 1.116.1 (`cc-tweaked-1.20.1-forge-1.116.1.jar`; the 1.113.1 jar in `mods/` is skipped by Forge per Phase 3) | `http.websocket`, `textutils`, `peripheral`, `fs` |
| Advanced Peripherals | 0.7.46r (`mods.toml` `version = "0.7.46r"`) | Chat Box `chat` event, `sendMessage`/`sendMessageToPlayer` |
| Bridge | existing (`websockets==17.1`, `anthropic==1.7.0`, `pydantic-ai-slim[anthropic]==2.46.0`, `pydantic-settings==2.15.0`) | unchanged, except for the optional D-07 prompt line |
| luaparse (dev tool, throwaway dir) | 0.3.1 (`npm view luaparse version`) | Lua 5.2 syntax check before every push. No Lua runtime exists on the PC or in WSL. |
| JDK javap | `~/.jdks/openjdk-26.0.2.1/bin/javap.exe` | Jar inspection if a new first-run surprise needs checking |

## Package Legitimacy Audit

This phase installs no project packages. luaparse is installed only into a throwaway scratch directory as a syntax checker, as in Phases 2 and 3. It is never added to `pyproject.toml` or the repo.

| Package | Registry | Verdict | Disposition |
|---------|----------|---------|-------------|
| luaparse | npm | not re-audited (existing dev-only tool, already used in Phases 2–3) | Approved as before, scratch-only |

**Packages removed:** none. **Packages flagged:** none.

## Architecture Patterns

### Data flow of one request (with the Finding 1 fix)

```
player types "$robot what devices are connected?"
   │
   ▼
AP Events.onChatBox ── cancels public chat, strips every "$", isHidden=true
   │   queueEvent("chat", "Name", "robot what devices...", uuid, true)
   ▼
chat.lua session loop ── [DEBUG: raw fields] ── hidden? text = "$"..text
   │   ws.send {"type":"event","name":"chat","user","text":"$robot ...","uuid","hidden":true}
   ▼
bridge.on_event ── prefix "$robot"? ── no ──► return (silent)
   │ yes                    allowed_players? ── no ──► log "ignoring X (not allowed)"
   ▼
agent.handle_request ── log "request from" ── model run (list_devices is bridge-local)
   │   say tool / or plain-text fallback ── log "answer for ..."
   ▼
bridge.say → send_cmd(device-0, "say", {text, to|null, prefix:"Robot"})
   ▼
chat.lua websocket_message (ev[2]==BRIDGE_URL) → outbox + result{queued=true}
   ▼
drainOutbox ── [DEBUG: args + return] ── sendMessageToPlayer / sendMessage ── sleep 1.1
   ▼
"[Robot] ..." in game chat
```
If a request needs hands, the bridge instead does `send_cmd(worker, tool, args)` → `client.lua ws.receive()` → `pcall(tool)` → `result{ok, data|error}`.

### Plan shape the research supports (coarse, 3 plans)

1. **04-01 (autonomous, code only):**
   - Finding 1 fix in `chat.lua`.
   - DEBUG marker in both Lua files.
   - D-07 prompt line.
   - Two text-level tests in `tests/test_device_lua.py`: DEBUG output never references `TOKEN`, and chat.lua re-adds `$` on `hidden`.
   - Checks: luaparse on both files, `uv run python tests/test_device_lua.py`, `uv run python tests/test_agent.py`, ruff, mypy.
   - Push `main`, then RAW_MATCH.
2. **04-02 (one looping checkpoint, chat computer only):**
   - Pre-flight: the operator starts the bridge and pastes its `config:` line; the author runs `mkdir debug` on the base computer and holds Ctrl+R.
   - The ATM9 question, fix loop until answered (D-08).
   - Devices question #1 (LOOP-03, chat only).
   - The no-worker request (LOOP-04).
3. **04-03 (worker, proofs, capture):**
   - Worker install on the second computer (wget line, token, reboot) and its bridge line (LOOP-02).
   - Devices question #2.
   - Optional D-05 tool error.
   - `rm debug` and `rm debug.log` on both, then Ctrl+R.
   - D-12 capture of the normal (non-debug) boot lines.
   - LOOP-05 byte compare against `origin/main`.
   - Fix list and paid-call count.

### Anti-Patterns to Avoid
- **Fixing Finding 1 on the bridge side** (accepting `robot ...` when `hidden`): that changes what the harness must send (D-10 churn). It also makes the bridge trust a flag in place of a prefix. Fix it where the stripping is observed, in `chat.lua`.
- **Printing the hello frame or any table containing `TOKEN` under DEBUG.** Log only the event fields, `cmd` frames received, and `result` frames sent.
- **Leaving `debug.log` in the world at the end.** Phase 3's token-isolation style checks scan the world. DEBUG lines never hold the token, but the file is noise that Phase 5's docs shouldn't describe.
- **`{` or `}` in the D-07 line.** `SYSTEM_TEMPLATE.format(robot_name=...)` (agent.py `configure`) would raise at bridge boot.
- **"Type `reboot`"** in a recipe for a running device (Finding 8).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Getting device text to the PC | Transcribing the 51×19 CC screen by hand | `debug.log` in the device folder, read-only from `<SERVER_DIR>/world/computercraft/computer/<id>/`; for crash traces, an F2 screenshot (`C:\Users\nneib\curseforge\minecraft\Instances\All the Mods 9 - ATM9\screenshots\`, the newest PNG) | Exact bytes, no transcription errors. The folder layout is proven in Phase 3. |
| Checking a push reached raw GitHub | Waiting a fixed 5 min | The 03-06 RAW_MATCH one-liner (`git hash-object` of the raw URL vs `origin/main:` blob) | Exists and was proven in Phase 3 |
| Proving the device equals `main` | Eyeballing | The 03-06 byte compare (in-process, token never printed), with folder discovery | Proven method |
| Lua syntax check | Anything needing a Lua runtime | luaparse `luaVersion: '5.2'` in a `mktemp -d` dir | No Lua on PC or WSL. Avoid `//`, bitwise operators and `goto` labels in the fixes, because luaparse's 5.2 grammar and Cobalt disagree on some 5.3 syntax. |

## Common Pitfalls

### Pitfall 1: silent first request (Finding 1)
**What goes wrong:** No reply, no bridge log line, no spend.
**How to avoid:** Fix it in Plan 1 (Code Example 1).
**Warning sign:** The DEBUG line shows `text` without `$` and `hidden=true`.

### Pitfall 2: the outbox wedges on a permanent send failure
**What goes wrong:** `drainOutbox` reinserts every failed message at position 1 (`base/chat.lua:39-42`: `if not ok then log("send failed:", err, "- requeueing") table.insert(outbox, 1, m) end`). `incorrect player name/uuid` is permanent, for example a player who logged off before the answer, or a model-invented `to`. It retries every 1.1 s forever, blocks every later reply, and fills the screen.
**How to avoid:** If it's seen, requeue only when `err` contains `"cooldown"` and drop and log otherwise (Code Example 3). D-09 says fix only on sight, but the code is ready.
**Warning signs:** `send failed: incorrect player name/uuid - requeueing` repeating.

### Pitfall 3: mojibake in answers (Finding 6)
**How to avoid:** Put plain ASCII in the D-07 line. Fold on the bridge only if it's still seen.
**Warning sign:** `â` followed by odd glyphs where punctuation should be.

### Pitfall 4: `ALLOWED_PLAYERS` case or spelling
**What goes wrong:** An exact-case mismatch gives `ignoring <Name> (not allowed)` and no reply.
**How to avoid:** In pre-flight, read the bridge's `config:` line (Finding: log lines). The 02-07 transcript shows `to: DisraSenkovi`, so that name is already in the list. Confirm it is the author's in-game name.

### Pitfall 5: a stale raw GitHub copy re-installs the old bug
**How to avoid:** Run RAW_MATCH before every "hold Ctrl+R". `startup.lua` also rejects a download that doesn't compile (`load(body, ..., {})`) and keeps the local copy, so a syntax slip degrades to "using the local copy" and doesn't brick the device.

### Pitfall 6: the worker gets a Chat Box or turtle upgrade
**What goes wrong:** `startup.lua` runs `chat` on any computer where `peripheral.find("chatBox")` succeeds. A Chat Box adjacent to the second computer, or a chatty-turtle upgrade, makes it a second chat device.
**How to avoid:** The recipe says to place the second computer away from the Chat Box, with nothing attached.

### Pitfall 7: Phase 5 D-01's Lua prefix check
**What goes wrong:** Phase 5's offline reply compares the text against `$robot` in `chat.lua`. It must run on the re-prefixed text, or test `hidden and text:find("^robot")`, because of Finding 1.
**How to avoid:** Record this in the fix list so Phase 5 inherits it.

## Code Examples

These were checked with luaparse 5.2 in this session (`LUA_PARSE_OK`).

### 1. `chat.lua`: restore the `$` AP stripped (the one certain fix)
```lua
    if ev[1] == "chat" then
      -- AP 0.7.46r: ev = "chat", username, message, uuid, isHidden. A "$"-prefixed message
      -- arrives hidden with every "$" removed; put the prefix back so the bridge sees "$robot".
      local user, text, uuid, hidden = ev[2], ev[3], ev[4], ev[5] == true
      dbg("chat event:", textutils.serialise({ user = user, text = text, uuid = uuid, hidden = ev[5] }))
      if hidden then text = "$" .. text end
      ws.send(textutils.serialiseJSON({
        type = "event", name = "chat", user = user, text = text, uuid = uuid, hidden = hidden,
      }))
```

### 2. DEBUG marker (both files; recommended over a committed constant)
```lua
local DEBUG = fs.exists("debug")   -- on: `mkdir debug` then hold Ctrl+R; off: `rm debug`
local function dbg(...)
  if not DEBUG then return end
  log("DEBUG", ...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local f = fs.open("debug.log", "a"); f.writeLine(table.concat(parts, " ")); f.close()
end
```
Why the marker is better than a constant:
- Toggling needs no commit, push or RAW_MATCH wait.
- `main` can never ship with DEBUG on (D-11's end state is automatic).
- It works per device, and the LOOP-05 byte compare is unaffected.
- `debug.log` lets the orchestrator read DEBUG output from disk rather than having the author copy the screen.

`log` must be defined before `dbg`. In `chat.lua`, call `dbg` right before each Chat Box call and right after with `tostring(ok), tostring(err)`. In `client.lua`, call `dbg("cmd", raw)` after `ws.receive()` and `dbg("result", json)` before `ws.send(json)`. The hello is never passed to `dbg`.

### 3. (Hold unless seen) requeue only on cooldown
```lua
      if not ok then
        if type(err) == "string" and err:find("cooldown", 1, true) then
          table.insert(outbox, 1, m)      -- "%s is on cooldown": try again after SEND_GAP
        else
          log("send failed:", err, "- dropped")
        end
      end
```

### 4. D-07 prompt line (one bullet appended to `SYSTEM_TEMPLATE`'s Rules)
The current framing is `Players give you chores in chat; you carry them out using turtles and computers connected to you, then report back briefly.` [VERIFIED: `bridge/agent.py:48-63`]. Recommended addition, with no braces:
```
- Players may also just ask a question (about the modpack, a mod, a recipe); answer it
  directly from what you know, through say(), in one or two sentences. Use plain ASCII
  only: no emoji, curly quotes or long dashes, which game chat cannot show.
```
`tests/test_agent.py` only asserts that the instructions equal `a.system.strip()`, so the addition does not break it.

### Verification commands (the planner's `<automated>` blocks)
- luaparse, from the Phase 3 plans:
  ```
  cd "$(mktemp -d)" && npm i luaparse --silent >/dev/null 2>&1 && node -e "require('luaparse').parse(require('fs').readFileSync(process.argv[1],'utf8'),{luaVersion:'5.2'}); console.log('LUA_PARSE_OK')" "<abs path>"
  ```
  Run it once per Lua file.
- Tests: `uv run python tests/test_device_lua.py` and `uv run python tests/test_agent.py`, from `turtle/turtle-helper`.
- Lint and types: `uv run ruff check .` and `uv run mypy bridge`, if `agent.py` changes.
- RAW_MATCH: the 03-06-PLAN Task 3 one-liner (`03-06-PLAN.md:236`), limited to `base/chat.lua` and `turtle/client.lua`.
- New text tests for `test_device_lua.py`:
  - `chat.lua` contains `"$" .. text` gated on `hidden`.
  - In `chat.lua` and `client.lua`, no line that calls `print`, `log` or `dbg` mentions `TOKEN`.
  - Neither file declares `DEBUG = true`.
  - The existing `GLOBAL_OUTPUT_CALL` regex (`test_device_lua.py:34`) only covers `print`/`write`/`printError`. The new test must add `log(` and `dbg(`.

## State of the Art

| Old assumption (PITFALLS.md / REQUIREMENTS notes) | Verified for this server | Impact |
|---|---|---|
| `$robot` reaches the device as typed | `$` removed from the whole message, `isHidden = true` | Certain silent failure until fixed |
| Chat Box range "default ~50 blocks" | `chatBoxMaxRange = -1`, multi-dimensional on | No range concern |
| `sendMessageToPlayer` has a 7th `utf8Support` argument | Not in 0.7.46r (reads up to index 5) | No device-side unicode fix exists |
| Cooldown might be 2 s | 1000 ms configured; failure is `nil, "<op> is on cooldown"` | `SEND_GAP = 1.1` is right |
| Docs page = installed behaviour | The docs page describes a newer AP (5-value event) | Trust the jar |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Mojibake actually renders as visible garbage in the client, rather than being normalised somewhere | Finding 6 | Low: the prompt line costs nothing either way |
| A2 | Holding Ctrl+R reboots after about 0.5 s like terminate (only `TERMINATE_TIME` is named in the jar) | Finding 8 | Low: the author holds it longer, or uses Ctrl+T twice then `reboot` |
| A3 | Netty's `WebSocketClientProtocolHandler` auto-answers the bridge's 20 s pings | Finding 4 | Phase 5 D-04 owns it; device A stayed connected in Phase 3 |
| A4 | The new worker gets id 2 | Worker id | None: the byte compare discovers folders |
| A5 | `PlayerList.getPlayerByName` is case-insensitive, so a model-cased `to` still finds the player | Finding 3 | Low: the bridge fallback uses the exact event name anyway |
| A6 | DisraSenkovi (from the 02-07 transcript) is the author's in-game name | Pitfall 4 | Low: the pre-flight read of the `config:` line settles it |

No finding contradicts a locked decision. D-11 explicitly left the mechanism open, and the marker plus `debug.log` fits it. D-09's "only bugs that block the loop" covers Finding 1: it blocks the loop with certainty and is verified from the jar, not speculative.

## Open Questions

1. **Fix Finding 1 before the first run, or let it show up live?**
   - What we know: it is certain from the jar, and a live occurrence costs one silent attempt and one push cycle with no spend.
   - Recommendation: fix it in 04-01 and list it in the fix list as "found by jar inspection before the first run; confirmed in game by the DEBUG line". Seeing the DEBUG `chat event:` line with the stripped text on the first run still confirms it in game.
2. **Include the D-05 worker tool error?**
   - Recommendation: **yes**. It is one Haiku call and the only exercise of `client.lua`'s `cmd`/`result` loop (Finding 7 gives the expected shape). Suggested wording: `$robot what is in minecraft:chest_99?` with the worker connected.
3. **Does `peripherals: {}` (object) from a bare worker's `status` need mirroring?**
   - Recommendation: no. It's not a fix and not a loop blocker. Note it as an observed shape for Phase 5's "Verified in game" if `status` is ever called.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node/npm (luaparse) | Lua syntax check | ✓ | node v26.8.1, luaparse 0.3.1 | — |
| javap | Jar re-checks | ✓ (not on PATH) | `~/.jdks/openjdk-26.0.2.1/bin/javap.exe` | — |
| uv + Python 3.12 | tests, bridge | ✓ (used in Phases 1–3) | — | — |
| Server `mods/` jars | Verification source | ✓ | CC 1.116.1, AP 0.7.46r | — |
| Server world folder (read-only) | `debug.log`, byte compare | ✓ | `computer/0`, `computer/1` present | — |
| Running bridge, server, devices | All in-game steps | operator-owned | — | none: human checkpoints |

## Validation Architecture

Skipped: `workflow.nyquist_validation` is `false` in `.planning/workstreams/turtle-helper/config.json`. The verification commands above are what the plans use.

## Security Domain

Skipped: `security_enforcement` is `false` for this workstream. The one standing rule carries over as a test: no DEBUG line or debug file may contain the token.

## Sources

### Primary (HIGH)
- `AdvancedPeripherals-1.20.1-0.7.46r.jar` (server `mods/`), `javap -c`:
  - `Events.onChatBox`/`onCommand`
  - `ChatBoxPeripheral` (`update`, `sendMessage`, `sendMessageToPlayer`, `getPlayer`)
  - `OperationAbility.performOperation`
  - `META-INF/mods.toml`
- `cc-tweaked-1.20.1-forge-1.116.1.jar`:
  - `HTTPAPI.websocket`, `Websocket`, `WebsocketHandle(.receive, $ReceiveCallback)`, `WebsocketHandler`, `Websocket$1` pipeline
  - `CobaltLuaMachine.toObject`
  - `cobalt-0.9.6.jar` `LuaString.decode`
  - `TerminalWidget`
  - `rom/apis/textutils.lua`, `rom/apis/http/http.lua`, `rom/apis/gps.lua`, `rom/programs/shell.lua`, `bios.lua`
- Server config `config/Advancedperipherals/peripherals.toml`, and `world/computercraft/ids.json` plus the folder listing.
- Repo: `base/chat.lua`, `turtle/client.lua`, `startup.lua`, `install.lua`, `bridge/bridge.py`, `bridge/agent.py`, `bridge/settings.py`, `harness/harness.py`, `harness/scenarios.py`, `tests/test_device_lua.py`.
- Phase 3 `03-CONTEXT.md` D-09, `03-05-SUMMARY.md`, `03-06-SUMMARY.md`, `03-06-PLAN.md` (RAW_MATCH).

### Secondary (MEDIUM)
- https://docs.advanced-peripherals.de/0.7/peripherals/chat_box/: fetched. It describes a newer 0.7.x than the installed jar (5-value event, `utf8Support`).

### Tertiary (LOW)
- None relied on.

## Metadata

**Confidence breakdown:**
- Event, Chat Box and websocket facts: HIGH, read from the exact jars the server loads.
- Plan shape and DEBUG mechanism: HIGH. They follow the locked decisions and proven Phase 3 methods.
- On-screen rendering (mojibake, Ctrl+R timing): MEDIUM/LOW. Confirmed by the first run.

**Research date:** 2026-09-25
**Valid until:** the server's AP or CC:Tweaked jar changes. Re-check `mods/` names first.

# Phase 5: Real-Device Resilience & Documentation - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning

<domain>
## Phase Boundary

On real in-game devices, the round trip survives a bridge restart and devices that boot before the bridge is running, and stays connected while idle; the outage is visible in game instead of silent; the two Lua device scripts retry quietly; and `turtle/turtle-helper/README.md` and `turtle/turtle-helper/CLAUDE.md` describe the local path as it was actually run. The documented default model becomes the one every paid run has used. Requirements RESIL-01, RESIL-02, DOC-01, DOC-02, plus an amendment to BRIDGE-03 (D-12).

Facts as of 2026-09-25 (not guesses):

- Phase 4 (the first in-game round trip) has not started. This context was gathered ahead of it. Phase 5 depends on Phase 4: the Lua changes below (D-01, D-02) land on top of whatever Phase 4 fixes in `chat.lua` and `client.lua`, and DOC-02's fix list (D-13) is filled from Phase 4's summaries.
- Device A is computer 0, chat role, no label, connects as `device-0`, installed from `main` with the one `wget run` line (Phase 3). The worker device does not exist yet; Phase 4 installs it the same way.
- Both Lua files already retry every 5 seconds after a drop or a failed connect and print one line per attempt. `startup.lua` is a plain run with no supervisor loop (Phase 3 D-08). The bridge pings every 20 s with a 20 s timeout (Phase 1 D-06); whether CC:Tweaked answers pings is unconfirmed in game.
- The operator's `.env` runs `MODEL=claude-haiku-4-5`; `bridge/settings.py`, `.env.example`, README and CLAUDE.md say `claude-sonnet-5`.
- The server loads CC:Tweaked 1.116.1 and Advanced Peripherals 0.7.46r (Phase 3).

Not in Phase 5: Phase 4's first run and its Lua fixes; hosting the bridge on the friend's machine and the `run.bat` patch (Phase 6, HOST-01/HOST-03); a supervisor or restart loop in `startup.lua` (deferred again, D-03); queueing `$robot` requests typed during an outage (rejected, see Deferred); a bridge log file; per-player history surviving a bridge restart; proving sorting in game; any wire-protocol change; any change to the agent's behaviour.

</domain>

<decisions>
## Implementation Decisions

### Device reconnect behaviour (Lua)
- **D-01:** A `$robot` message typed while the chat computer has no open session to the bridge gets a local "offline" reply from `chat.lua` through its own Chat Box, addressed to that player only, via the existing outbox queue (so the Chat Box cooldown still holds). No bridge or model is involved. The wording is Claude's call but must read as clearly not a bridge answer (for example `[Robot] I'm offline, try again in a moment`). `chat.lua` needs its own prefix constant mirroring the bridge's default `$robot` (the bridge's `COMMAND_PREFIX` is not known to the device; if someone changes the prefix in `.env`, the offline reply simply does not fire for the custom prefix, and the README says so). A message from a player not in `ALLOWED_PLAYERS` also gets the offline reply; it costs nothing and the device cannot know the allow-list. — **Reversibility:** reversible — a few lines in one Lua file.
- **D-02:** Retry cadence stays 5 seconds fixed in both `chat.lua` and `client.lua` (RESIL-01's "within their retry interval" means within about 5 s). Output becomes quiet: one line when the bridge first becomes unreachable, including the reason `http.websocket` gave (for example `bridge unreachable (Could not connect), retrying every 5s`), nothing while retrying, one line on connect (`connected to bridge`). Same behaviour in both files; exact wording is Claude's call.
- **D-03:** No supervisor loop. `startup.lua` keeps its plain `shell.run` of `chat` or `client`; a Lua error drops to the prompt with the error visible. RESIL-01/02 are about the bridge going away, and the connect loops already survive every network failure. Phase 3's deferred "supervisor loop or abort window" stays deferred (see Deferred Ideas).
- **D-04:** An idle-stability check is added to the proof session: both devices connected and idle for about 5 minutes, and the bridge log shows no `device disconnected` or `device connected` lines in that window. This catches ping-timeout churn that a 5 s retry loop would otherwise hide. If churn shows, `PING_INTERVAL` / `PING_TIMEOUT` in `.env` is the knob (Phase 1 D-06: 0 disables), not a code change; whatever was found goes into the README and the "Verified in game" block (D-13).

### The proof session
- **D-05:** All live checks run in one operator sitting from one short checklist, as one plan checkpoint. Order: (a) the D-01/D-02 Lua changes are pushed to `main` and both devices rebooted so they run the new code (the Phase 3 D-16 update path; raw GitHub may lag up to about 5 minutes); (b) RESIL-01: Ctrl+C the bridge, run `uv run bridge/bridge.py` again, watch both devices reconnect within about 5 s (bridge log shows `device connected` for both, since the registry is empty after a restart), then ask `$robot what devices are connected?`; (c) RESIL-02: Ctrl+C the bridge, `reboot` both devices, watch each print the unreachable line, start the bridge, watch both connect, ask the devices question again; (d) D-04's idle window; (e) report. The offline reply (D-01) is tried during (c) while the bridge is down. Per the project's live-run rule, the operator runs the bridge and the devices; no agent starts either, and the plan hands the operator the checklist and waits.
- **D-06:** Evidence is the operator's pass/fail word per check, in a line or two, plus the bridge's `device connected` lines when they are handy to paste. Nothing is required verbatim. The verifier records the proofs as operator-observed (`human_judgment: true`), as Phase 3 did for the reboot. The same sitting is also the one chance to capture real text for D-11, so the checklist asks the operator to paste the device screen lines and bridge lines once; lines nobody captured are left out of the README rather than reconstructed.
- **D-07:** Spend budget is three paid model calls on `claude-haiku-4-5`: the devices question after RESIL-01, again after RESIL-02, and one spare for a retry. Each is `$robot what devices are connected?` typed by the operator in game. Nothing else in the phase spends.

### README end-to-end pass (DOC-01)
- **D-08:** Extend in place. `Setup > 1. Bridge`, `2. In game`, `3. Talk to it` keep their places. A short ordered checklist goes at the top of `Setup` ("from a clean server to the first answer") linking to each section, so DOC-01's "sufficient to redo from a clean server" is met without restructuring. Gaps the proofs reveal are filled and stale lines fixed. Phase 6 will amend the hosting part again, so no prose is written for a hosting story that changes next phase. `2. In game` opens with a two-sentence explanation of the two computers, added after the Phase 4 discussion: the base computer with the Chat Box is the robot's mouth, any other computer running `client.lua` is its hands, and there are two because CC:Tweaked routes websocket events by URL; the recipes say "the base computer" and "the second computer", not "chat" and "worker".
- **D-09:** One document, developer voice, addressed to the person who runs the bridge and edits the code. The admin-facing part for the non-developer friend arrives with Phase 6's setup script, not here.
- **D-10:** Proven content only. `3. Talk to it` leads with the devices question; the sorting examples are either dropped or kept under an explicit "implemented on the bridge, not yet run in game" note (Claude's call which). The `Safety knobs` line saying the MODEL default is a placeholder is corrected (D-12). `Next chores to add` shrinks to a pointer at CLAUDE.md's `Next up` (D-14) so one list stays current.
- **D-11:** A `What you should see` section, built only from text captured in Phase 3, 4 or 5 runs, never from memory: device boot lines, the bridge's `device connected` line, the offline reply, and what a bridge restart looks like from both sides (device: unreachable line, then connected; bridge: `device disconnected`, then `device connected`). The existing `Smoke check` subsection folds into it. The reconnect behaviour (5 s retries, quiet output, offline reply, the prefix caveat from D-01) is described here or under `2. In game`, Claude's call.

### CLAUDE.md (DOC-02) and the model default
- **D-12:** The default model becomes `claude-haiku-4-5`: the `model` default in `bridge/settings.py`, the `MODEL=` line in `.env.example`, README and CLAUDE.md. Sonnet 5 stays documented as the stronger option via `MODEL=` override. This amends BRIDGE-03's wording in `REQUIREMENTS.md` and the "Known issues in the starter" sentence in `PROJECT.md`; a Key Decisions row is recommended. The bridge's boot-time `models.retrieve` check applies to whichever ID is configured, so a bad default still fails fast. — **Reversibility:** reversible — one default value and four doc lines.
- **D-13:** Phase 4's Lua fixes (and anything Phase 5 learns, such as ping behaviour) are recorded as a `Verified in game` block under `Conventions` in CLAUDE.md: one line per fact future edits must respect (event signatures, JSON shapes, URL matching, Chat Box call signatures, retry behaviour), each dated and tagged with the versions it was seen on (CC:Tweaked 1.116.1, Advanced Peripherals 0.7.46r). `Current state` gets one line: the round trip ran in game on the date it did, fixes are listed under Conventions, and the harness plus the wget/reboot loop is the dev loop. The "Lua not yet run in game" sentence goes.
- **D-14:** CLAUDE.md `Next up` becomes: 1. the bridge on the friend's machine behind `run.bat` (Phase 6); 2. choose and prove the first real chore (open per CHORE-01; sorting is implemented on the bridge but unproven); 3. `goto`/`refuel` policy, `fetch_item`, `restock`/`mine_vein`, scheduled chores and multi-turtle dispatch as today. README's `Next chores` points at this list (D-10).

### Claude's Discretion
- Exact offline-reply wording (D-01), the name of the local prefix constant in `chat.lua`, and how the retry wait pulls events (see Gotchas: `sleep(5)` discards chat events).
- Exact wording of the unreachable and connected lines (D-02), and whether `client.lua` and `chat.lua` share the text verbatim.
- Checklist wording and layout for the operator; the recommended order in D-05 may be reordered if it saves a reboot.
- Whether the sorting examples are dropped or kept under a note (D-10); where the reconnect behaviour is described (D-11).
- Date and version format of the `Verified in game` lines (D-13); whether PROJECT.md's Context paragraph on the model is rewritten or just corrected.
- No bridge code change is expected for the proofs; the existing `device connected` / `device disconnected` lines are the evidence. If the researcher finds the idle check needs a bridge log line, say so in RESEARCH.md rather than adding one silently.
- Plan shape, per the workstream's coarse granularity: one plan per wave with 3-5 tasks. A natural split is (1) Lua changes plus the model default plus the push, (2) the proof sitting, (3) the docs pass, which must come last because D-11 needs the captured text. No harness scenario is added for the Lua-only behaviours; `tests/test_device_lua.py` invariants must still pass and new Lua is parsed with luaparse before commit.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

ROADMAP.md carries no `Canonical refs:` line for this phase; the list below is the accumulated set.

### Phase scope and requirements
- `.planning/workstreams/turtle-helper/ROADMAP.md` — Phase 5 entry: goal and four success criteria; Phase 6 entry (what the hosting story becomes, so D-08/D-09 do not pre-empt it).
- `.planning/workstreams/turtle-helper/REQUIREMENTS.md` — RESIL-01, RESIL-02, DOC-01, DOC-02; BRIDGE-03 (amended by D-12); Verification Notes (the AP `chat` event and Chat Box signatures are unverified until Phase 4).
- `.planning/workstreams/turtle-helper/PROJECT.md` — Core Value ("pieces reconnect on their own"), Constraints "Resilience" and "Chat etiquette" (one `say()` per task, ~1 s cooldown, which D-01 must respect), Context "Known issues in the starter" (the model sentence D-12 corrects), Key Decisions table (D-12 row).
- `.planning/workstreams/turtle-helper/STATE.md` — Blockers/Concerns: the MODEL reconcile item (closed by D-12) and the Phase 2 note that Haiku once answered in plain text (agent behaviour, Phase 4's territory).

### Prior phases
- `.planning/workstreams/turtle-helper/phases/01-bridge-environment/01-CONTEXT.md` — D-06 (ping settings and the "CC:Tweaked answers pings?" question D-04 finally tests), D-12 (README bridge section shape), D-18 (Sonnet 5 default, amended by D-12 here).
- `.planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-CONTEXT.md` — D-10/D-11 (bridge-side disconnect and same-id reconnect handling the proofs rely on), D-17 (docs extend rather than rewrite; DOC-02 changes "Current state" in Phase 5).
- `.planning/workstreams/turtle-helper/phases/03-local-server-setup/03-CONTEXT.md` — D-08/D-16 (`startup.lua` role detection and boot-time update), D-13 (smoke-check text rule: from the real run, never memory), D-14..D-19 (the single install path the README already documents), Deferred "Supervisor loop or abort window in `startup.lua`" (D-03 keeps it deferred).
- `.planning/workstreams/turtle-helper/phases/03-local-server-setup/03-05-SUMMARY.md` — device A facts, captured boot and bridge lines (`connected to bridge`, `device connected: device-0 (chat) caps=['say']`), the verbatim smoke-check shapes.
- `.planning/workstreams/turtle-helper/phases/03-local-server-setup/03-06-SUMMARY.md` — the push-and-reboot update proof method (byte compare against `origin/main`, mtimes), the note that `startup.lua` is not self-updating and device A runs the pre-D-19 version.
- Phase 4 artifacts, once they exist: `.planning/workstreams/turtle-helper/phases/04-*/04-CONTEXT.md` and the `04-*-SUMMARY.md` files — the Lua fixes D-13 records and the worker device's id and role. The planner must not plan Phase 5 until these exist.

### Research already done (verify, do not repeat)
- `.planning/workstreams/turtle-helper/research/PITFALLS.md` — §1 "`ping_interval` / `ping_timeout` Interact with CC:Tweaked's Socket Timeouts" (about lines 43-70: the churn D-04 tests for; disabling pings is the documented fallback); §3 "`ws.receive()` Blocks Forever" (about 361-407), "`websocket_message` Event URL Must Match Exactly" (409-446), "`os.pullEvent()` vs `os.pullEventRaw()`" (492-516, keep `os.pullEvent`), "`parallel.waitForAny()` Event Consumption Between Coroutines" (518-542, relevant to the D-01 event loop in `chat.lua`); §4 "Chat Box Cooldown and Requeue on Failure" (663-690) and "`sendMessage()` vs `sendMessageToPlayer()` Argument Order" (621-661) for the offline reply.

### Existing code
- `turtle/turtle-helper/base/chat.lua` — `connectLoop` (the `sleep(5)` retry D-02 quiets and D-01 turns into an event loop), `session` (chat events are forwarded only here today; `websocket_closed` matched by URL), `outbox`/`drainOutbox` (the queue D-01 reuses; `sendMessageToPlayer(text, to, prefix)`).
- `turtle/turtle-helper/turtle/client.lua` — the bottom `while true` connect loop (D-02), `session` with blocking `ws.receive()`.
- `turtle/turtle-helper/startup.lua` — unchanged by this phase (D-03); line-1 header convention.
- `turtle/turtle-helper/bridge/bridge.py` — `handler` cleanup around lines 196-207 (`device disconnected: <id>`, the replacement branch), the connect log at line 159, `send_cmd`/`fail_pending` (D-10). No change expected.
- `turtle/turtle-helper/bridge/settings.py` — `model` default (D-12), `ping_interval` / `ping_timeout` fields (D-04's knob).
- `turtle/turtle-helper/.env.example` — `MODEL=` line (D-12), ping lines.
- `turtle/turtle-helper/README.md` — `Setup` (D-08 checklist goes at its top), `Setup > 1. Bridge` (model mention), `2. In game` and its `Updating` / `Smoke check` subsections (D-11 folds the latter in), `3. Talk to it` (D-10), `Safety knobs` (stale MODEL line), `Next chores to add` (D-10 pointer).
- `turtle/turtle-helper/CLAUDE.md` — `Current state` (D-13 one-liner; the "Lua not yet run in game" sentence goes; the MODEL bullet changes), `Next up` (D-14), `Conventions` (new `Verified in game` block, D-13; `Dev loop` line stays).
- `turtle/turtle-helper/tests/test_device_lua.py` — invariants every Lua edit must keep (line-1 header, no token printing, pinned URLs).
- `turtle/turtle-helper/harness/` — unchanged; the devices question recipe there is not what D-07 uses (the proofs type it in game).

### CC:Tweaked and Advanced Peripherals (for D-01/D-02; researcher verifies against the 1.20.1 versions on the server)
- https://tweaked.cc/module/http.html — `http.websocket` return shape and error strings (`Could not connect`, `Domain not permitted` already observed).
- https://tweaked.cc/event/websocket_closed.html and https://tweaked.cc/event/websocket_message.html — the events `chat.lua` matches by URL.
- https://tweaked.cc/module/os.html — `os.pullEvent`, `os.startTimer`; `sleep` is a filtered `pullEvent("timer")` that drops other events for that coroutine, which is why D-01's retry wait cannot be `sleep`.
- https://tweaked.cc/module/parallel.html — event delivery to both coroutines in `chat.lua`.
- https://docs.advanced-peripherals.de/0.7/peripherals/chat_box/ — `sendMessageToPlayer` signature and the cooldown, for the offline reply (0.7.x is the 1.20.1 line; confirm the page version matches 0.7.46r).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `chat.lua` `outbox` + `drainOutbox`: the offline reply is one `table.insert(outbox, {text=..., to=user})`; cooldown handling, requeue on failure and the `[Robot]` prefix come for free, and queued items survive a session drop.
- `chat.lua` `session`'s `chat` event branch: the `user`/`text` fields the offline reply needs are already unpacked there; the same unpacking moves into (or is shared with) the retry wait.
- Bridge log lines `device connected: <id> (<role>) caps=[...]` and `device disconnected: <id>`: the evidence D-05/D-06 look for; nothing new to add.
- Phase 3's live-check style (read-only scratchpad scripts that compare device files to `origin/main` and never print the token): reuse to confirm both devices picked up the D-01/D-02 Lua before the proofs, instead of trusting the reboot.
- README `Smoke check` subsection: the "verbatim from the real run" pattern D-11 extends.

### Established Patterns
- Thin Lua, thick Python (Phase 2 D-07): the offline reply and the quiet retry are the only Lua behaviour this phase adds; nothing with a policy goes into Lua.
- One install/update path: push to `main`, then `reboot`; there is no PC-side placement, so the proofs can only run on Lua that is already on `main`.
- Live processes are operator-owned; plans hand over a checklist and wait; paid calls are the operator's deliberate act.
- Docs record observed text, never reconstructed text (Phase 3 D-13, extended by D-11).
- Coarse granularity for this workstream: few plans, 3-5 tasks each, no nyquist/security/code-review gates; one plan-checker pass and the verifier stay.

### Integration Points
- `chat.lua` and `client.lua` connect loops (D-01, D-02); `bridge/settings.py` `model` default and `.env.example` (D-12); README sections named above (D-08..D-11); CLAUDE.md sections named above (D-13, D-14); `REQUIREMENTS.md` BRIDGE-03 and `PROJECT.md` (D-12 amendment).
- Phase 4's fixed Lua is the base for D-01/D-02; Phase 4's summaries feed D-13.
- Phase 6 replaces the hosting paragraph in `Setup > 1. Bridge` and adds the admin-facing docs; D-08/D-09 leave that room.

### Gotchas surfaced during discussion
- In `chat.lua`, `chat` events are handled only inside `session`; during the `sleep(5)` between attempts the coroutine's filtered `pullEvent("timer")` discards them, so D-01 needs the retry wait to be a small event loop (`os.startTimer(5)` plus `os.pullEvent` handling `timer` and `chat`), not `sleep`. `drainOutbox` runs in parallel and keeps draining regardless.
- After a bridge restart the registry is empty, so reconnects log as `device connected`, not as the `reconnected ... replacing stale connection` line (that one only fires when the old socket is still registered). Do not expect the replacement line in the RESIL-01 evidence.
- If CC:Tweaked does not answer WebSocket pings, the bridge closes each device every 40 s and the 5 s retry reconnects it; only the idle check (D-04) would show it, as a steady `device disconnected` / `device connected` rhythm.
- Per-player histories live in bridge memory and are lost on restart; the post-restart devices question starts a fresh conversation. Not a problem, just not to be mistaken for a bug.
- Device A still runs the pre-D-19 `startup.lua` (dead marker branch); harmless, and irrelevant here since `startup.lua` is not touched. Only `chat.lua` and `client.lua` update on reboot; raw GitHub can serve the previous file for a few minutes after a push.
- In PowerShell `$robot` is a variable reference; any pasted command or README example quotes it in single quotes.
- No Lua runtime exists on this PC or in WSL; parse changed Lua with luaparse (npm) in the scratchpad before committing.
- Bash tool commands over roughly 8 KB fail here; write large files with the file tool.
- `bridge/settings.py` and `.env.example` have CRLF line endings in the working copy; scripted edits need CRLF-aware matching (seen in Phase 3).

</code_context>

<specifics>
## Specific Ideas

- "Budget three, allow a retry": the author chose a larger spend budget than recommended so the plan never has to come back and ask for one more call.
- "Switch the default to Haiku 4.5": the documented default should be exactly what has been proven in game, even though it amends BRIDGE-03.
- Recommended options were accepted everywhere else: the offline reply, quiet 5 s retries, no crash loop, the idle check, one sitting with the operator's word as evidence, README extended in place in developer voice with proven content only and a "What you should see" section, and a "Verified in game" block in CLAUDE.md.
- The author's standing process preference for this workstream (recorded 2026-09-25): keep it coarse, ask only real questions, no pedantic verification.

</specifics>

<deferred>
## Deferred Ideas

- **Queue and forward `$robot` requests typed during an outage.** Rejected for v1.0: stale requests would fire minutes later and each costs a model call. The offline reply (D-01) covers the user-visible gap.
- **Supervisor or restart loop in `startup.lua`, with or without an abort window.** Deferred again (D-03). Revisit only if a real Lua crash on a device turns out to be common.
- **Bridge log file beside `.env`, machine-checked proofs.** Not needed for v1.0 evidence (D-06). Worth reconsidering in Phase 6, where a log the friend can send would help remote debugging.
- **Admin versus developer README split.** Phase 6's job, alongside its setup script (D-09).
- **Per-player history surviving a bridge restart.** Not needed; noted so nobody reads the fresh conversation after a restart as a bug.
- **Hard-kill restart variant (Task Manager instead of Ctrl+C).** Not run; the OS closes the socket either way, so devices see `websocket_closed` in both cases.
- **Harness scenario for the offline reply or the quiet retry.** Lua-only behaviour the harness cannot exercise; left out.
- **Whether answers should name device ids.** Agent behaviour observed in Phase 2 (STATE.md blocker); Phase 4's territory.
- **Computer 1's leftover `_marker.txt`.** Operator cleanup, outside the repo; nothing reads it.

No todos were reviewed; none matched this phase.

</deferred>

---

*Phase: 05-real-device-resilience-documentation*
*Context gathered: 2026-09-25*

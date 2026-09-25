# Phase 4: In-Game Round Trip - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Real `chat.lua` on device A (computer 0, an Advanced Computer with a Chat Box) and real `client.lua` on a second Advanced Computer connect to the local bridge; the author types a `$robot` request in game chat and hears a spoken answer; a request that cannot be fulfilled gets a plain-language reply instead of silence; every Lua bug the first run surfaces is fixed in the repo, and the files on the devices are byte-identical to `main` at the end. The chat computer comes first and alone; the worker is the last step. Requirements LOOP-01 through LOOP-05.

Facts as of 2026-09-25 (not guesses):

- Device A already connected in Phase 3: `http.websocket`, the hello frame, `secret.txt`/`bridge.txt`, `startup.lua`'s role detection and the boot-time update are proven. The bridge logged `device connected: device-0 (chat) caps=['say']`, so LOOP-01 is a re-confirmation.
- Never run in game: the Advanced Peripherals `chat` event signature (`chat, user, text, uuid, hidden` assumed), the `websocket_message` URL match on the incoming `say` command, the `chatBox.sendMessageToPlayer` / `sendMessage` calls, and all of `client.lua`'s `ws.receive()` command loop and tools.
- The devices question is answered from the bridge's own registry (`list_devices` is a local tool). It never sends a command to a worker, so only a request that needs hands exercises `client.lua`'s command path.
- The bridge guarantees a reply: a plain-text final answer is whispered to the requester, and an exception becomes the "something went wrong" fallback (Phase 2). Paid calls run on `claude-haiku-4-5` from the operator's `.env` (Phase 5 D-12 makes it the default).
- The dev loop is push to `main` then `reboot`; raw GitHub may serve the old file for up to about 5 minutes. `startup.lua` does not update itself; device A still runs the pre-D-19 version, which is harmless.
- The author is confused by the chat/worker split and asked why not test with chat only. The answer, recorded so nobody re-explains it: chat is the mouth (Chat Box), a worker is hands (any other computer running `client.lua`); two computers because CC:Tweaked routes websocket events by URL (Phase 3 D-09); with chat alone everything but LOOP-02 can be proven.

Not in Phase 4: the offline reply and quiet retries (Phase 5 D-01/D-02, which land on top of this phase's fixes); bridge-restart and devices-before-bridge proofs (Phase 5); the README and CLAUDE.md pass (Phase 5); a turtle worker; chests, wired modems or any sorting proof (CHORE-01, later); any change to the wire protocol; merging the two roles.

</domain>

<decisions>
## Implementation Decisions

### Sequence and devices
- **D-01:** Chat computer first, alone. Connect, the first request, the answer, the failure reply and the Lua fixes are all done with device A only. The worker is added as the last step of the phase, after the chat loop works.
- **D-02:** The worker is one more Advanced Computer running `client.lua`, placed anywhere, with no peripherals and no Chat Box (a Chat Box would make `startup.lua` run `chat`). It is installed with the same one `wget run` line, the typed token and `reboot` (Phase 3 D-14/D-15). It connects as role `computer` with caps `status`, `list_chest`, `push_one_slot`. LOOP-02 is met when the bridge logs it with role and caps and a devices answer includes it. No turtle this phase; the turtle branch of `client.lua` stays unproven. — **Reversibility:** reversible — a turtle is the same install on a different block.

### The first request and what counts as an answer
- **D-03:** The first in-game request is a free-form question about ATM9 that the author picks at the keyboard (a mod, a recipe, anything), not the devices question. Its purpose is to test the Claude connection end to end. Any real spoken answer in chat counts; the bridge's "something went wrong" fallback does not (the harness's standard). The devices question runs afterwards as the LOOP-03 check, once with chat alone (a correct answer names `device-0` as the chat device and no workers) and once after the worker joins; its wording is not constrained beyond being correct.
- **D-04:** Whisper versus broadcast is the model's choice (`say` keeps its optional `to`); the bridge's plain-text fallback whispers to the requester. No change to the `say` tool. Note for the docs: Advanced Peripherals hides `$`-prefixed messages from public chat, so a broadcast answer appears to other players without its question.
- **D-05:** The LOOP-04 failure case is a request that needs hands while no worker is connected (for example asking what is in a chest). The model has no device tool in that run and must say plainly that it has nothing to do it with. Runs during the chat-only stage. After the worker joins, a second failure case, a tool error on the worker (for example `list_chest` on a made-up inventory name), is recommended if one more call is affordable: it is the only thing this phase that exercises `client.lua`'s `cmd`/`result` loop. Claude's call in the plan whether to include it.
- **D-06:** No fixed spend budget. Every paid call is the author typing in game, so the author controls spend; the plan records the count of paid calls at the end. Model `claude-haiku-4-5`.
- **D-07:** The agent's instructions (`SYSTEM_TEMPLATE`) frame the robot as taking chores. If the researcher or planner judges a one-line addition is needed so a general question gets answered rather than deflected, and to keep answers to a sentence or two for the Chat Box, add it minimally; do not rework the prompt. Claude's call.

### The fix loop
- **D-08:** The author and the orchestrator iterate directly, no executor per fix. The loop: the author pastes the error from the device screen (and a bridge log line when relevant); the orchestrator fixes the repo file, syntax-checks it with luaparse, commits, pushes `main`, and confirms raw GitHub serves the new bytes (Phase 3's RAW_MATCH check); the author reboots the device; repeat until the ATM9 question is answered in chat. The plan expresses this as one checkpoint that loops, with the plan's tasks being the fixed points around it (worker install, LOOP-05 proof, capture). Per the live-run rule, no agent starts the bridge, the server or a device.
- **D-09:** Every fix lands in the repo first; nothing is patched on the device. Only bugs that block the loop are fixed, no speculative rewrites. The LOOP-05 proof at the end is a read-only byte compare of `computer/<id>/chat.lua` and `client.lua` on both devices against `origin/main` (Phase 3's scratchpad method, never printing the token), plus a list of the fixes made, in the words Phase 5's "Verified in game" block (05 D-13) will reuse.
- **D-10:** A Lua fix that changes a wire shape (a result field, a caps name, an event field) must be mirrored the same day in `harness/` (Phase 2 D-03: the fake worker mirrors `client.lua`) and in `tests/`, so the harness keeps telling the truth. A fix that only changes how `chat.lua` reads an event or calls the Chat Box touches nothing else.

### Diagnostics and capture
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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

ROADMAP.md carries no `Canonical refs:` line for this phase; the list below is the accumulated set.

### Phase scope and requirements
- `.planning/workstreams/turtle-helper/ROADMAP.md` — Phase 4 entry: goal and five success criteria; Phase 5 entry (what this phase must leave ready).
- `.planning/workstreams/turtle-helper/REQUIREMENTS.md` — LOOP-01 through LOOP-05; Verification Notes (LOOP-03 spends; the AP `chat` event and Chat Box signatures are HIGH confidence from docs but unverified in this world).
- `.planning/workstreams/turtle-helper/PROJECT.md` — Context "Known issues in the starter" (the list of suspected first-run mistakes), Constraints "Chat etiquette" (one `say()` per task, ~1 s cooldown) and "Security" (`ALLOWED_PLAYERS`; the author's in-game name must be in the operator's `.env` before the first request), Key Decisions (reply-delivery guarantee; harness passes only on a non-fallback `say`).
- `.planning/workstreams/turtle-helper/STATE.md` — Blockers/Concerns: "Lua has still never run in game" (this phase closes it) and "Haiku answered in plain text once" (the bridge fallback covers it).

### Prior phases
- `.planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-CONTEXT.md` — D-03 (the harness mirrors `client.lua`'s shapes; D-10 here keeps them in step), D-07 (the primitive set `client.lua` advertises), D-15 (the spend guard is a harness rule; in game the operator's keypress is the guard).
- `.planning/workstreams/turtle-helper/phases/03-local-server-setup/03-CONTEXT.md` — D-08 (role detection by Chat Box: why the worker must not have one), D-09 (one role per computer, verified against the CC:Tweaked jar), D-10 (naming), D-13 (smoke check), D-14..D-19 (the one install path and the push-and-reboot update).
- `.planning/workstreams/turtle-helper/phases/03-local-server-setup/03-05-SUMMARY.md` — device A facts, the captured boot and bridge lines, the RAW_MATCH check, the read-only layout and token-isolation check style.
- `.planning/workstreams/turtle-helper/phases/03-local-server-setup/03-06-SUMMARY.md` — the byte-compare-against-`origin/main` method for the LOOP-05 proof, the raw GitHub cache note.
- `.planning/workstreams/turtle-helper/phases/05-real-device-resilience-documentation/05-CONTEXT.md` — D-01/D-02 (Lua changes that follow this phase; do not do them here), D-07 (spend style), D-11/D-13 (what this phase's captured text is for), D-12 (model default).

### Research already done (verify, do not repeat)
- `.planning/workstreams/turtle-helper/research/PITFALLS.md` — §4 "Chat Event Argument Order and the Hidden Flag" (about lines 578-619: the assumed `chat, user, text, uuid, hidden` order and the debug-log suggestion D-11 adopts), "`sendMessage()` vs `sendMessageToPlayer()` Argument Order" (621-661), "Chat Box Cooldown and Requeue" (663-690), "Chat Box Range Limits and Message Size" (692-715: keep answers short); §3 "`websocket_message` Event URL Must Match Exactly" (409-446), "`textutils.serialiseJSON` Empty Tables and Nil Fields" (448-490), "`os.pullEvent()` vs `os.pullEventRaw()`" (492-516, keep `os.pullEvent`), "`parallel.waitForAny()` Event Consumption" (518-542); §1 "`ping_interval` / `ping_timeout`" (43-70: if device A drops every 40 s during this phase, that is the ping question Phase 5 D-04 owns; note it, do not fix it here).

### Existing code
- `turtle/turtle-helper/base/chat.lua` — `session` (the `chat` event branch and the `websocket_message` URL match are the two untested reads), `drainOutbox` (the two Chat Box calls), the `SEND_GAP` cooldown.
- `turtle/turtle-helper/turtle/client.lua` — `session` (`ws.receive()` loop, `cmd` dispatch, `result` shapes), `tools.status` (uses `gps.locate`, which returns nil without GPS; fine), `capabilities()`.
- `turtle/turtle-helper/startup.lua` — role detection; not changed by this phase (a change would need the wget line re-run on each device).
- `turtle/turtle-helper/install.lua` — the worker install (D-02).
- `turtle/turtle-helper/bridge/bridge.py` — `on_event` (the `$robot` prefix and `ALLOWED_PLAYERS` checks, the catch-all error fallback), `say`, the `device connected` / `event from` / `request from` / `answer for` log lines D-12 captures.
- `turtle/turtle-helper/bridge/agent.py` — `SYSTEM_TEMPLATE` (lines 48-63; D-07), `list_devices` (229-231), `SayArgs`/`say` (234-244; D-04), `handle_request` (538-571; the plain-text fallback).
- `turtle/turtle-helper/harness/` — the canned result shapes that mirror `client.lua`; D-10 keeps them aligned with any Lua fix.
- `turtle/turtle-helper/tests/test_device_lua.py` — invariants every Lua edit must keep (line-1 header, no token printing, pinned URLs); D-11's DEBUG output must pass the no-token check.

### CC:Tweaked and Advanced Peripherals (researcher verifies against CC:Tweaked 1.116.1 and Advanced Peripherals 0.7.46r, the versions the server loads)
- https://tweaked.cc/event/websocket_message.html and https://tweaked.cc/event/websocket_closed.html — event shapes and the URL argument `chat.lua` compares.
- https://tweaked.cc/module/http.html — `http.websocket`, `Websocket.receive` / `send` / `close`.
- https://tweaked.cc/module/textutils.html — `serialiseJSON` / `unserialiseJSON`, `empty_json_array`.
- https://docs.advanced-peripherals.de/0.7/peripherals/chat_box/ — the `chat` event fields and order, `sendMessage` / `sendMessageToPlayer` signatures, cooldown and range; confirm the page matches 0.7.46r.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 3's read-only scratchpad checks: RAW_MATCH (raw GitHub serves the pushed bytes) before each reboot in the fix loop, and the byte compare of device files against `origin/main` for LOOP-05; both never print the token.
- The bridge's existing log lines (`event from`, `request from`, `answer for ... (spoken via say | plain text ...)`, `spoke the final output ... on the model's behalf`) already tell the whole story of one request; D-12 captures them, nothing new to add.
- `harness/` canned shapes: the reference for what `client.lua`'s results must look like when the worker is checked with a tool error (D-05) and the place to mirror any shape fix (D-10).
- luaparse in the scratchpad (Phase 2 and 3) for syntax-checking every Lua change before it is pushed; there is no Lua runtime on this PC or in WSL.

### Established Patterns
- Live processes are operator-owned; the plan hands the author a short recipe per step and waits for the paste.
- One install and update path (push to `main`, `reboot`); the fix loop rides on it, so every fix is a commit on `main`.
- Thin Lua: fixes correct call shapes and event reads; no logic moves into Lua.
- Docs record observed text only (Phase 3 D-13, Phase 5 D-11): the paste in D-12 is the source, nothing is reconstructed.
- Coarse granularity for this workstream: few plans, no nyquist/security/code-review gates, one plan-checker pass, the verifier.

### Integration Points
- `chat.lua` and `client.lua` (fixes and the DEBUG knob); `harness/` and `tests/` only if a wire shape changes (D-10); `bridge/agent.py` `SYSTEM_TEMPLATE` only if D-07's line is added.
- Phase 5 takes over the fixed Lua (its D-01/D-02 edits), the fix list (its D-13) and the captured text (its D-11).
- The operator's `.env`: `ALLOWED_PLAYERS` must contain the author's in-game name and `MODEL` is `claude-haiku-4-5`; the plan's first step confirms both without printing secrets.

### Gotchas surfaced during discussion
- The worker must not have a Chat Box attached, or `startup.lua` runs `chat` on it and the bridge gets two chat devices and no worker.
- The hello frame carries the token; any DEBUG print of outgoing frames must skip or redact the hello. `tests/test_device_lua.py` pins "no token printing".
- `$`-prefixed chat is hidden from public chat by Advanced Peripherals; only Chat Boxes see the request. Other players see a broadcast answer with no question.
- The devices question never sends a command to the worker; only a hands-needed request does (D-05).
- Raw GitHub can serve the previous file for up to about 5 minutes after a push; check RAW_MATCH before asking for a reboot, or the reboot re-installs the old bug.
- `startup.lua` is not self-updating; if a fix ever has to touch it, the wget line must be re-run on each device (it keeps `secret.txt`).
- If device A disconnects and reconnects on its own every 40 s or so while idle, that is the ping question (PITFALLS §1, Phase 5 D-04): note it in the fix list, do not chase it here.
- In PowerShell `$robot` is a variable reference; any command or README example quotes it in single quotes.
- Bash tool commands over roughly 8 KB fail here; write large files with the file tool. `bridge/settings.py` and `.env.example` have CRLF endings in the working copy.

</code_context>

<specifics>
## Specific Ideas

- "What is a worker? what is chat? why can't we just test with chat?": the author does not carry the chat/worker model in their head and should not have to. The plan's recipes say "the base computer (the one with the Chat Box)" and "the second computer", not "chat" and "worker". Phase 5's README pass should open its in-game section with the two-sentence explanation (mouth versus hands, two computers because of CC:Tweaked's URL routing).
- "chat first. lets ask something else then": get the loop working with the base computer alone before a second computer exists (D-01).
- "lets ask something more interesting. Something about atm9? I just want to test the claude connection for now": the first request is the author's own free-form ATM9 question; the devices question is the check, not the moment (D-03).
- Recommended options accepted for the rest: Advanced Computer worker, direct push-and-reboot fix loop with no executor per fix, DEBUG knob kept in the repo.
- Standing process preference for this workstream: coarse, few questions, no pedantic verification.

</specifics>

<deferred>
## Deferred Ideas

- **Turtle worker.** The turtle branch of `client.lua` (`move`, `turn`, `dig`, `inspect`, `refuel`) stays unproven until a chore needs it (CHORE-02 or later).
- **Wired modem network with chests, and proving `list_chest` / `push_one_slot` / `sort_chest` in game.** CHORE-01's territory; nothing in this phase wires a chest.
- **A constrained devices-answer format (names plus roles in one line).** Offered, not chosen; the model answers freely. Revisit if answers are unclear once two devices exist.
- **Labels for the two computers.** Optional, no code; use `label set` if `device-<id>` reads badly.
- **Merging the chat and worker roles.** Still deferred from Phase 3 D-09; the URL-routing constraint stands. The author's confusion is real, so Phase 5's docs pass explains the split instead.
- **Patching Lua on the device in the in-game editor.** Rejected for this phase (D-09); the push-and-reboot loop is the only path.
- **Executor-per-fix plan shape.** Rejected as too slow for a first-run debugging loop (D-08).

No todos were reviewed; none matched this phase.

</deferred>

---

*Phase: 04-in-game-round-trip*
*Context gathered: 2026-09-25*

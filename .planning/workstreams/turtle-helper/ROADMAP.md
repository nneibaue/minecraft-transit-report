# Roadmap: Turtle Helper — v1.0 Local Round Trip

## Overview

Five phases carry the round trip from a bare Python environment to a proven, documented, self-healing loop between game chat and the bridge. Phase 1 gets `bridge.py` itself onto solid ground — pinned environment, the current `websockets` asyncio API, a real model ID, fail-fast secrets — with nothing else depending on the game yet. Phase 2 stands up a terminal-driven fake device harness and uses it to drive every protocol and security failure case that doesn't need Minecraft at all: handshake, the one paid devices-question call, worker command answering, mid-command disconnects, bad tokens, and disallowed players. Phase 3 turns to the dedicated ATM9 server itself — the CC:Tweaked allow rule, on-disk Lua placement, per-device `secret.txt`, and `startup.lua` — so real devices have somewhere to live. Phase 4 is the milestone's key moment: real `chat.lua` and `client.lua` on real devices connect, and `$robot what devices are connected?` gets a correct spoken answer in game chat, with any first-run Lua bugs fixed in the repo. Phase 5 closes the loop with the two proofs that need real, already-connected devices — bridge restart and devices-before-bridge — and brings README.md and CLAUDE.md up to date now that the round trip has actually run.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Bridge Environment** - `bridge.py` starts locally on a pinned Python environment, the current `websockets` API, a real model ID, and env-based secrets (completed 2026-09-20)
- [ ] **Phase 2: Fake Device Harness & Protocol Resilience** - A terminal-driven fake device proves the wire protocol and every game-free failure case against the running bridge
- [ ] **Phase 3: Local Server Setup** - The dedicated ATM9 server allows local websocket connections and hosts each device's Lua, token, and startup script on disk
- [ ] **Phase 4: In-Game Round Trip** - Real `chat.lua` and `client.lua` on real devices connect and answer the devices question in chat
- [ ] **Phase 5: Real-Device Resilience & Documentation** - Bridge-restart and devices-before-bridge proofs on real devices, and the docs now describe the proven path

## Phase Details

### Phase 1: Bridge Environment

**Goal**: `bridge.py` starts on this PC from a pinned, reproducible Python environment, on the current `websockets` asyncio server API, with a current Claude model ID and secrets sourced only from the environment — the foundation every later phase connects to.
**Depends on**: Nothing (first phase)
**Requirements**: BRIDGE-01, BRIDGE-02, BRIDGE-03, BRIDGE-04
**Success Criteria** (what must be TRUE):

  1. Following the documented venv recipe (PowerShell and Git Bash) and installing from a pinned `requirements.txt` produces a working environment, and `python bridge.py` prints a listening-on-8765 log line with no import errors.
  2. The bridge's server code calls `websockets.asyncio.server.serve` with a single-argument handler, and no call to the legacy `websockets.serve` remains anywhere in the file.
  3. Running `bridge.py` with `BRIDGE_TOKEN` unset exits immediately with a one-line error message instead of a stack trace; with it set, the startup log shows the resolved `MODEL` as `claude-sonnet-5` (or an env override), never the old placeholder ID.
  4. `BRIDGE_TOKEN`, `ALLOWED_PLAYERS`, and `ANTHROPIC_API_KEY` are read only from environment variables via a documented, git-ignored local recipe (e.g. a git-ignored `.env` plus a committed example) — no secret value is hardcoded anywhere in `bridge.py`.

**Plans**: 2/2 plans executed
Plans:

- [x] 01-01-PLAN.md — uv environment + typed Settings + settings.py/agent.py/bridge.py split, listening on the new websockets API (Wave 1)
- [x] 01-02-PLAN.md — README.md and PROJECT.md updated for the uv recipe and the relaxed Python footprint (Wave 1)

### Phase 2: Fake Device Harness & Protocol Resilience

**Goal**: A terminal-driven fake device can play either device role against the running bridge, proving the full wire protocol and every failure case that doesn't require Minecraft — before any Lua touches a real device.
**Depends on**: Phase 1
**Requirements**: HARN-01, HARN-02, HARN-03, HARN-04, RESIL-03, RESIL-04, RESIL-05
**Success Criteria** (what must be TRUE):

  1. Running the harness with `--role chat` or `--role worker` against the local bridge completes the hello handshake with the shared token and prints every JSON message sent and received in both directions.
  2. The chat-role harness, given a scripted `$robot what devices are connected?` event, drives exactly one real model call and prints the bridge's `say` command followed by the harness's own `result` reply (this is the only criterion in this phase that spends an API call).
  3. The worker-role harness answers a `status` command (and other canned commands) with a `result` message visible in both the harness terminal and the bridge log, with no model call involved.
  4. Dropping the harness's connection on demand — including while a command is in flight — produces a clean bridge-side error with no hang past the command timeout and no leaked pending future, and reconnecting the harness re-completes the hello handshake without restarting the bridge.
  5. Two security proofs run from the harness alone: connecting with a deliberately wrong token gets a close code plus a bridge log line and never appears in the device registry; a scripted `$robot` chat event from a player not in `ALLOWED_PLAYERS` produces a bridge log line noting it was ignored, no chat reply, and no model call.

**Scope widening (D-05/D-06/D-07/D-08, author's decision during phase discussion):** The phase also
carries the Phase-1-deferred Pydantic AI agent rewrite: `bridge/agent.py` moves onto typed
`pydantic-ai-slim[anthropic]` tools with per-run, cap-filtered toolsets, replacing the hand-rolled
JSON tool-schema loop. Composition moves to Python at the same time — `turtle/client.lua` shrinks to
one-to-one CC:Tweaked primitives, `sort_chest` becomes a Python function composed over `send_cmd`, and
sorting rules persist in a git-ignored `rules.json` beside `.env` on the bridge instead of on the
device. This amends the "high-level tools live in Lua" principle in `PROJECT.md` (see its Key
Decisions table).

**Plans**: 6/7 plans executed

Plans:
**Wave 1**

- [x] 02-01-PLAN.md — Lua primitive rewrite: strip composition, add push_one_slot (D-07) (Wave 1)
- [x] 02-02-PLAN.md — Bridge resilience: send_cmd/pending cleanup, reconnect replacement, malformed frames, CR-01 (Wave 1)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-03-PLAN.md — Fake device harness core + six scenarios (Wave 2)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-04-PLAN.md — Paid devices-question run, pre-swap (1st of 2 paid calls) (Wave 3)

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-05-PLAN.md — Agent core: typed pydantic-ai tools, per-run toolset, Agent construction (Wave 4)

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 02-06-PLAN.md — Agent composition: sort_chest, rules.json, cleanup (Wave 5)

**Wave 6** *(blocked on Wave 5 completion)*

- [ ] 02-07-PLAN.md — Harness docs, CLAUDE.md amendments, paid devices-question run post-swap (2nd of 2 paid calls) (Wave 6)

### Phase 3: Local Server Setup

**Goal**: The dedicated ATM9 server accepts local websocket connections from the bridge and hosts each device's Lua, token, and startup script directly on disk, so real devices have somewhere to run in the next phase.
**Depends on**: Phase 1
**Requirements**: SRV-01, SRV-02, SRV-03, SRV-04
**Success Criteria** (what must be TRUE):

  1. `world/serverconfig/computercraft-server.toml` carries an `[[http.rules]]` entry allowing host `127.0.0.1` placed before the default private-range deny; after a server restart, a documented in-game one-line smoke check (`http.websocket` to the bridge's address) succeeds instead of being blocked.
  2. `chat.lua` and `client.lua` are placed directly into their respective per-computer folders on disk with no GitHub push or pastebin step, and the actual folder path is confirmed against the running server and corrected in the docs if it differs from the researched guess (`<world>/computercraft/computer/<id>/` is MEDIUM confidence going in).
  3. Each device's folder contains its own `secret.txt` holding only the bridge token; a repo-wide search for the token value confirms it appears nowhere else in the Lua, the repo, or version control.
  4. Each device's folder contains a `startup.lua` that launches `chat` or `client` as appropriate, and rebooting the computer in-game (without touching the bridge) brings the script back up on its own.

**Plans**: TBD

### Phase 4: In-Game Round Trip

**Goal**: Real `chat.lua` and `client.lua` run on real in-game devices, connect to the bridge, and answer the devices question in chat — the milestone's key moment — with first-run Lua bugs fixed in the repo rather than patched live.
**Depends on**: Phase 2, Phase 3
**Requirements**: LOOP-01, LOOP-02, LOOP-03, LOOP-04, LOOP-05
**Success Criteria** (what must be TRUE):

  1. `chat.lua` running on an Advanced Computer with a Chat Box attached connects to the bridge and appears in the bridge log as role `chat`.
  2. `client.lua` running on a turtle or Advanced Computer connects to the bridge and appears in the bridge log with its role and capability list.
  3. A player in `ALLOWED_PLAYERS` typing `$robot what devices are connected?` in game chat gets a spoken-back, correct list of connected devices (this is the only criterion in this phase that spends an API call).
  4. A `$robot` request that cannot be fulfilled (worker device missing, tool error) gets a plain-language error reply in chat rather than silence, and the bridge process is still running afterward.
  5. Every Lua runtime error surfaced by the first real run (event signatures, JSON shapes, URL matching, Chat Box call signatures) is fixed in the repo copies of `chat.lua` and `client.lua`, confirmed by diffing the repo files against what's deployed on the devices.

**Plans**: TBD

### Phase 5: Real-Device Resilience & Documentation

**Goal**: The round trip survives a bridge restart and devices starting before the bridge, and README.md / CLAUDE.md now describe the proven local path end to end instead of the pre-milestone "never run" state.
**Depends on**: Phase 4
**Requirements**: RESIL-01, RESIL-02, DOC-01, DOC-02
**Success Criteria** (what must be TRUE):

  1. Restarting `bridge.py` while both real devices are connected leads to both reconnecting on their own within their retry interval (visible in the bridge log), and the next `$robot` request works without touching either device.
  2. Starting both real devices before the bridge is running shows them retrying, then connecting on their own once the bridge comes up, with no device reboot needed.
  3. `turtle/turtle-helper/README.md` documents the full local path end to end — env recipe, allow rule, on-disk file placement, `secret.txt`, `startup.lua`, harness usage — sufficient to redo the setup from a clean server.
  4. `turtle/turtle-helper/CLAUDE.md` "Current state" reflects that the round trip has run in game, lists the specific Lua fixes made in Phase 4, and names the harness as the dev loop — no longer says the Lua has never run.

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|-----------------|--------|-----------|
| 1. Bridge Environment | 2/2 | Complete    | 2026-09-20 |
| 2. Fake Device Harness & Protocol Resilience | 6/7 | In Progress|  |
| 3. Local Server Setup | 0/TBD | Not started | - |
| 4. In-Game Round Trip | 0/TBD | Not started | - |
| 5. Real-Device Resilience & Documentation | 0/TBD | Not started | - |

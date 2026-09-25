# Requirements: Turtle Helper — v1.0 Local Round Trip

**Defined:** 2026-09-19
**Core Value:** A player types `$robot ...` in game chat and gets a correct answer or action back, through a loop whose pieces reconnect on their own after any one of them restarts.

## v1 Requirements

Requirements for milestone v1.0. Each maps to a roadmap phase.

### Bridge Environment (BRIDGE)

- [x] **BRIDGE-01**: Developer can start `bridge.py` on this PC from a pinned Python environment (`requirements.txt` with exact versions, venv recipe for PowerShell and Git Bash) and it listens on port 8765
- [x] **BRIDGE-02**: Bridge runs on the current `websockets` asyncio server API (`websockets.asyncio.server.serve`, single-argument handler) on the pinned current version, with no deprecated legacy `websockets.serve` call remaining
- [x] **BRIDGE-03**: Bridge defaults to a current Claude model ID (`claude-sonnet-5`), overridable by the `MODEL` env var; no placeholder model ID remains in the code
- [x] **BRIDGE-04**: Bridge reads `BRIDGE_TOKEN`, `ALLOWED_PLAYERS` and `ANTHROPIC_API_KEY` from the environment via a documented, git-ignored local env recipe, and a missing `BRIDGE_TOKEN` fails fast with a one-line message instead of a stack trace

### Fake Device Harness (HARN)

- [x] **HARN-01**: Developer can run a Python harness that connects to the local bridge as either a chat device or a worker device (role chosen on the command line), completes the hello handshake with the shared token, and prints every wire message in both directions
- [x] **HARN-02**: Harness playing the chat device can emit a scripted `$robot what devices are connected?` chat event and then receives the bridge's `say` command and answers it with a `result` (this path makes one real model call)
- [x] **HARN-03**: Harness playing a worker device answers incoming commands (at least `status`) with canned results so the bridge's device-forwarding path is exercised without the game
- [x] **HARN-04**: Harness can drop its connection on demand (including while a command is in flight) and reconnect, so the failure proofs in RESIL can be driven from a terminal

### Local Server Setup (SRV)

- [x] **SRV-01**: The dedicated ATM9 server's `world/serverconfig/computercraft-server.toml` carries an `[[http.rules]]` allow rule for host `127.0.0.1` placed before the default private-range deny; the exact file, rule, ordering, restart requirement, and an in-game one-line smoke check are documented
- [ ] **SRV-02**: Developer can place `chat.lua` and `client.lua` directly into the server's per-computer folders on disk (`<world>/computercraft/computer/<id>/`) with `uv run deploy`, with the folder-to-device mapping and the reload step documented; this is the developer's no-push path (the admin-facing install is SRV-05)
- [ ] **SRV-03**: Each device reads the bridge token from `secret.txt` in its own folder; the token appears nowhere in the Lua, the repo, or the world save other than those per-device files
- [ ] **SRV-04**: Each device has a `startup.lua` that launches `chat` or `client`, so devices come back on their own after a server restart or device reboot
- [ ] **SRV-05**: A non-technical server admin can set up a new device with a single in-game command (`wget run` of `install.lua` from GitHub `main`), typing only the bridge token once; after that, pushing Lua changes to `main` and rebooting the device is the whole update path (`startup.lua` re-downloads the Lua on boot and falls back to the local copies when GitHub is unreachable)

### In-Game Round Trip (LOOP)

- [ ] **LOOP-01**: `chat.lua` on an Advanced Computer with a Chat Box attached connects to the local bridge and appears in the bridge log as role `chat`
- [ ] **LOOP-02**: `client.lua` on a turtle or Advanced Computer connects to the local bridge and appears in the bridge log with its role and capability list
- [ ] **LOOP-03**: A player in `ALLOWED_PLAYERS` types `$robot what devices are connected?` in game chat and the robot speaks back a correct list of the connected devices
- [ ] **LOOP-04**: A `$robot` request that cannot be fulfilled (worker device missing, tool error) gets a plain-language error reply in chat rather than silence, and the bridge stays up
- [ ] **LOOP-05**: Lua runtime errors found on first run (event signatures, JSON shapes, URL matching, Chat Box calls) are fixed in the repo copies of `chat.lua` and `client.lua`, not only on the device

### Resilience and Security Proofs (RESIL)

- [ ] **RESIL-01**: Restarting the bridge while both devices are connected leads to both reconnecting on their own within their retry interval, and the next `$robot` request works without touching the devices
- [ ] **RESIL-02**: Devices started before the bridge keep retrying and connect on their own once the bridge comes up; no device reboot needed
- [x] **RESIL-03**: A device that disconnects or reboots while a command is in flight produces a clean error reply to the player, the bridge does not hang past its command timeout, and no pending future is left behind
- [x] **RESIL-04**: A device presenting a wrong token is rejected with a close code and a bridge log line, and is not added to the registry
- [x] **RESIL-05**: A `$robot` message from a player not in `ALLOWED_PLAYERS` is ignored: logged, not answered, no model call made

### Documentation (DOC)

- [ ] **DOC-01**: `turtle/turtle-helper/README.md` documents the local dedicated-server path end to end: env recipe, allow rule, on-disk file placement, `secret.txt`, `startup.lua`, and harness usage
- [ ] **DOC-02**: `turtle/turtle-helper/CLAUDE.md` "Current state" reflects that the round trip has run in game, lists the Lua fixes made, and names the harness as the dev loop

## v2 Requirements

Deferred to a later milestone. Tracked but not in the v1.0 roadmap.

### No-Spend Testing (TEST)

- **TEST-01**: A fake brain (scripted `tool_use` blocks behind a single seam) lets the full agent loop run with no API key and no spend
- **TEST-02**: A pytest protocol suite (hello/token rejection, registry add and remove, command timeout, the devices question) runs with one command and no API key

### First Chore (CHORE)

- **CHORE-01**: The first real chore is chosen and proven in game (sorting or otherwise; the author is not sure sorting is the right one)
- **CHORE-02**: `goto(x, y, z)` with GPS and simple pathing
- **CHORE-03**: Refuel policy and a `fuel_low` event
- **CHORE-04**: `fetch_item(name, count)` via an ME or RS bridge
- **CHORE-05**: `restock(machine, item, count)` and `mine_vein`

### Hosting and Operations (HOST)

- **HOST-01**: Bridge runs on an always-on host or behind a tunnel so the real ATM9 server can reach it
- **HOST-02**: Scheduled chores (bridge-side timers) and multi-turtle dispatch

## Out of Scope

Explicitly excluded from v1.0. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Sorting chores as a deliverable | Code stays in `client.lua` unverified; the author is not sure sorting is the right first chore, so that decision waits |
| Fake brain and pytest suite | Author chose the harness alone for v1.0; the bridge only calls the model on a `$robot` event, so handshake and registry checks already cost nothing |
| `run_lua` / `ALLOW_EVAL` | Most dangerous knob in the project; not needed for the round trip; stays off |
| Any LLM call from Lua | Architecture decision; the API key never lives on an in-game computer |
| Rednet / modem messaging between devices | Every device talks only to the bridge |
| Tunnels and production hosting | Bridge and server share one PC this milestone; returns when the bridge leaves it |
| The Fabric transit-display mod | Separate product in this repo, planned under the `default` workstream |

## Traceability

Which phases cover which requirements. Filled in during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| BRIDGE-01 | Phase 1 | Complete |
| BRIDGE-02 | Phase 1 | Complete |
| BRIDGE-03 | Phase 1 | Complete |
| BRIDGE-04 | Phase 1 | Complete |
| HARN-01 | Phase 2 | Complete |
| HARN-02 | Phase 2 | Complete |
| HARN-03 | Phase 2 | Complete |
| HARN-04 | Phase 2 | Complete |
| SRV-01 | Phase 3 | Complete |
| SRV-02 | Phase 3 | Pending |
| SRV-03 | Phase 3 | Pending |
| SRV-04 | Phase 3 | Pending |
| SRV-05 | Phase 3 | Pending |
| LOOP-01 | Phase 4 | Pending |
| LOOP-02 | Phase 4 | Pending |
| LOOP-03 | Phase 4 | Pending |
| LOOP-04 | Phase 4 | Pending |
| LOOP-05 | Phase 4 | Pending |
| RESIL-01 | Phase 5 | Pending |
| RESIL-02 | Phase 5 | Pending |
| RESIL-03 | Phase 2 | Complete |
| RESIL-04 | Phase 2 | Complete |
| RESIL-05 | Phase 2 | Complete |
| DOC-01 | Phase 5 | Pending |
| DOC-02 | Phase 5 | Pending |

**Coverage:**

- v1 requirements: 24 total
- Mapped to phases: 24
- Unmapped: 0 ✓

## Verification Notes

- HARN-02 and LOOP-03 each make a real model call; every other v1 requirement is verifiable with no API spend because the bridge only calls the model when a `$robot` chat event arrives.
- SRV-02's on-disk computer folder path is MEDIUM confidence from research; confirm it on the first Lua placement and correct the docs if it differs.
- The Advanced Peripherals `chat` event argument order and Chat Box method signatures are HIGH confidence from docs but unverified in this world; LOOP-05 exists to absorb whatever the first run reveals.

---
*Requirements defined: 2026-09-19*
*Last updated: 2026-09-19 after scoping with research*

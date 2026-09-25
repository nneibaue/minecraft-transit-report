# Turtle Helper

## What This Is

An LLM-driven in-game assistant for the author's All the Mods 9 server (Minecraft 1.20.1 Forge, CC:Tweaked + Advanced Peripherals), in the spirit of the Hired Girl robots in Heinlein's *The Door into Summer*. Players give it chores in chat with a `$robot` prefix; a Python bridge outside the game turns the request into tool calls against in-game turtles and computers over websockets, and the robot reports back in chat. Built for the author and a small group of friends.

The brain lives outside the game. In-game devices are dumb executors that expose named tools; the bridge decides what to call.

## Core Value

A player types `$robot ...` in game chat and gets a correct answer or action back, through a loop whose pieces reconnect on their own after any one of them restarts.

## Current Milestone: v1.0 Local Round Trip

**Goal:** Prove the turtle-helper plumbing end to end with a dedicated ATM9 server and `bridge.py` both running on the author's PC: `$robot what devices are connected?` typed in game chat gets a correct spoken answer.

**Target features:**
- Bridge runs locally from a pinned Python environment with a current Claude model, reachable from the local dedicated server at `ws://127.0.0.1:8765`
- Fake device harness speaks the device protocol from a terminal so the bridge and agent loop can be exercised without the game; protocol tests spend no API calls
- CC:Tweaked local-address allow rule and device setup applied on the local dedicated server and documented
- `chat.lua` and `client.lua` run on real in-game devices, connect, survive a bridge restart, and answer the devices question in chat; the never-run Lua fixed as needed

## Requirements

### Validated

- ✓ Architecture decided and written down: brain outside the game, dumb device executors, bridge as message bus, one websocket per device, chat as the interface (`turtle/turtle-helper/CLAUDE.md`)
- ✓ Protocol defined: `hello` / `event` / `cmd` / `result` JSON messages, one websocket per device
- ✓ `bridge.py` starter written: websocket server, device registry, Claude tool-use loop, per-player history, `list_devices` and `say` local tools — compiles, never run against a device
- ✓ `client.lua` and `chat.lua` starters written: reconnect loops, hello handshake, tool dispatch, Chat Box send queue — never run in game
- ✓ Bridge starts on this PC from a pinned, uv-managed Python environment, on the current `websockets` asyncio server API, with a current Claude model ID and env-based secrets via a typed `Settings` model (BRIDGE-01..04) — Phase 1
- ✓ Fake device harness (`uv run harness --role chat|worker --scenario <name>`) plays either device against the running bridge: hello handshake with the token redacted in the wire log, canned command replies, drop-and-reconnect mid-command with no leaked future, wrong-token and disallowed-player rejection, and the devices question answered live (HARN-01..04, RESIL-03..05) — Phase 2
- ✓ Agent loop rewritten on Pydantic AI: typed tool functions, a per-run toolset filtered from live device caps, per-player message history, and a bridge-side guarantee that the model's final answer reaches chat; `client.lua` reduced to one-to-one CC:Tweaked primitives; `sort_chest` composed in Python with rules in a git-ignored `rules.json` beside `.env` (Phase 2 D-05..D-09, unproven in game) — Phase 2

### Active

Full list with REQ-IDs in `REQUIREMENTS.md`. In brief:

- [x] The local dedicated ATM9 server allows CC:Tweaked access to `127.0.0.1`; Lua goes onto devices by one in-game `wget run` of `install.lua` from GitHub `main`, and `startup.lua` re-downloads `chat.lua`/`client.lua` on every boot; tokens live only in per-device `secret.txt`, typed once at install; `startup.lua` relaunches on reboot (SRV-01..05, completed 2026-09-25)
- [ ] Real `chat.lua` and `client.lua` connect, `$robot what devices are connected?` is answered in chat, failures get a plain-language reply, and first-run Lua fixes land in the repo (LOOP-01..05)
- [ ] Proven on real devices: bridge restart reconnect and devices-before-bridge startup (RESIL-01..02; RESIL-03..05 were proven from the harness in Phase 2)
- [ ] README and CLAUDE.md describe the local path end to end and no longer say the Lua has never run (DOC-01..02)

### Out of Scope

- Sorting chores as a milestone deliverable — `sort_chest` and the rule tools now live in Python on the bridge (Phase 2) with zero-spend tests, but remain unproven in game; the author is not sure sorting is the right first chore, so choosing and proving the first real chore is a later milestone
- Fake brain (scripted `tool_use`) and a pytest protocol suite — deferred to v1.1 by the author's scoping choice; Phase 2 covered zero-spend agent testing with Pydantic AI's `FunctionModel`/`TestModel` inside dependency-free TAP scripts instead, and the bridge only calls the model on a `$robot` event, so handshake and registry checks with the harness cost nothing
- New chores (`goto`, `refuel` policy, `fetch_item`, `restock`, `mine_vein`, scheduled chores, multi-turtle dispatch) — listed in the starter's "next up"; none are needed to prove the round trip
- Production hosting (VPS / Render / Fly) and tunnels (cloudflared / Tailscale) — local dedicated server and local bridge on the same PC need neither; comes back when the bridge moves off this PC
- `run_lua` / `ALLOW_EVAL` — stays off; not needed for the round trip and is the most dangerous knob in the project
- Any LLM call from Lua — architecture decision; the API key never lives on an in-game computer
- Rednet / modem messaging between devices — every device talks only to the bridge
- The Fabric transit-display mod — separate product in this repo, planned under the `default` workstream

## Context

**Repository placement.** `turtle/turtle-helper/` sits beside the author's other CC:Tweaked scripts (`quarry.lua`, `crater.lua`, `bridge.lua`, ...) which are installed in game by `wget` from the raw GitHub URL on `main`. The folder is untracked at milestone start. Three parts: `bridge/bridge.py` (Python, runs on the PC), `base/chat.lua` (Advanced Computer + Chat Box), `turtle/client.lua` (turtle or Advanced Computer). The starter's own `CLAUDE.md` and `README.md` are the architecture and setup reference and should stay accurate as the code changes.

**Local test topology.** Dedicated ATM9 server, `bridge.py`, and the author's client all on one Windows PC. The websocket originates from the server process, so the Lua files point at `ws://127.0.0.1:8765` and CC:Tweaked's default block on local addresses must be lifted in that server's `computercraft-server.toml` (an `[[http.rules]]` entry allowing host `127.0.0.1`). No tunnel. The dev loop settled in Phase 3 is the same as the admin path: push to `main`, then `reboot` the device; `startup.lua` pulls the Lua on boot. The on-disk placement idea was built and then removed (Phase 3, D-19) because the eventual server admin is a non-developer friend at another location; Phase 6 moves the bridge onto her machine behind `run.bat`.

**Machine state at milestone start.** Python 3.12.10 on PATH (Windows Store launcher); `websockets` and `anthropic` not installed; `ANTHROPIC_API_KEY` not set in the shell. No `requirements.txt` / `pyproject.toml` / venv in the starter.

**Known issues in the starter.** `MODEL` defaults to a placeholder ID that must be replaced with a current model (Sonnet 5, `claude-sonnet-5`, is the sensible default for a tool-using agent loop; Haiku 4.5 if cost matters more). `bridge.py` requires `BRIDGE_TOKEN` at import time and crashes without it. The Lua has never executed: expect API-name and JSON-shape mistakes (`textutils.serialiseJSON` handling of empty tables, `http.websocket` return shapes, the `chat` event signature from Advanced Peripherals) to surface on first run. `chat.lua` matches `websocket_message` events by string-comparing the event URL to `BRIDGE_URL`; whether CC:Tweaked hands back the exact string passed in is worth verifying on first run.

**Testing without the game.** Both `chat.lua` and `client.lua` are thin: a Python fake device that sends `hello`, emits a `chat` event, and answers `cmd` with canned `result`s reproduces everything the bridge sees. The Claude call is the only piece that costs money; protocol tests need a way to run the bridge with the model call stubbed, or to answer `list_devices` without a model round trip. Built in Phase 2 as `turtle/turtle-helper/harness/` with six named scenarios; only `devices-question` spends, and only behind an explicit `--spend` flag, while the agent's own tests stub the model with Pydantic AI's `FunctionModel`.

**Author background.** Experienced software engineer, comfortable in Python; has shipped several CC:Tweaked Lua scripts in this repo already. CC:Tweaked and Advanced Peripherals API specifics matter and should be checked against the docs for the 1.20.1 versions ATM9 ships, not assumed.

## Constraints

- **Tech stack**: Python 3.12 with `asyncio`, `websockets`, `anthropic`; CC:Tweaked Lua for Minecraft 1.20.1 Forge (ATM9); Advanced Peripherals Chat Box — fixed by the server the author plays on
- **Security**: shared `BRIDGE_TOKEN` on every connection; `ALLOWED_PLAYERS` whitelist because every request costs the author money; `ALLOW_EVAL` stays off — these are the three knobs the starter already defines and none may be weakened for testing convenience
- **Secrets**: no API key in Lua, in the repo, or in the world save; `secret.txt` on devices holds only the bridge token
- **Resilience**: devices reconnect on their own after a bridge restart, and one bad request must never take the bridge down (the starter already catches per-request exceptions; keep it that way)
- **Chat etiquette**: one `say()` per task; Chat Box has a ~1 s send cooldown that the queue in `chat.lua` must respect
- **Dependencies**: uv-managed project (`pyproject.toml` + committed `uv.lock`) with `websockets`, `anthropic`, and `pydantic-settings` as direct dependencies (`pydantic` itself arrives transitively via `anthropic`); `pydantic-ai-slim[anthropic]` was added in Phase 2, with `anthropic` kept direct for the boot-time model check. Still no web framework, no database. The Python side is the three-module `bridge/settings.py` / `bridge/agent.py` / `bridge/bridge.py` split decided in Phase 1 (D-13), not the original one-file starter
- **Abstraction**: small project — no plugin systems, no premature device abstraction; adding a chore
  is now (Phase 2 D-06/D-07 amendment) "one typed Python tool function, plus a `tools.xxx` Lua entry
  only if it needs a new device-side primitive" — composition (loops, policy) stays in Python, never
  in Lua; the pre-Phase-2 wording ("one Lua function plus one schema entry") described the hand-rolled
  JSON-schema loop that Phase 2 replaces

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Brain outside the game; devices are dumb executors | The API key cannot live on an in-game computer, and high-level tools in Lua keep the model from micro-stepping a turtle | — Pending (inherited from starter) |
| Bridge is the only message bus; one websocket per device | No rednet or modem coordination to debug; the bridge sees every device directly | — Pending (inherited from starter) |
| One install path: in-game `wget run` of `install.lua` plus boot-time self-update; the developer deploy shortcut was removed the same day it shipped | The real admin is a non-SWE friend hosting the server elsewhere; every extra path or PC-side step is friction, not safety | ✓ Good — 2026-09-25 |
| Turtle-helper planned as its own GSD workstream, not a replacement milestone | The Fabric transit-display milestone is mid-flight (phases 6–10 pending); a flat-mode milestone would have archived its phases and overwritten its roadmap | ✓ Good — 2026-09-19 |
| v1.0 scope is the round trip only; sorting is not a deliverable | Author is not sure sorting is the right first chore; proving plumbing first keeps the first-chore decision open | — Pending |
| Fake device harness in scope alongside real in-game testing | The bridge's whole surface is a JSON protocol, so a terminal stand-in gives a fast loop; the in-game run stays required because the Lua has never executed | ✓ Good — 2026-09-24, Phase 2: five scenarios proved zero-spend, the paid path proved twice, and the harness caught a real regression before any device existed |
| Local dedicated server on the same PC; no tunnel | Same box means `ws://127.0.0.1` plus one CC:Tweaked allow rule; tunnels return only when the bridge leaves this PC | — Pending |
| Migrate the bridge to the current `websockets` asyncio server API now, rather than pin below 14.0 | Research split on this (stack said migrate, synthesizer said pin). It is a three-line change the harness verifies with no game involved, and a new project should not start on a deprecated API line. Author chose migrate on 2026-09-19 | ✓ Good — 2026-09-20, Phase 1 shipped on `websockets.asyncio.server.serve` |
| v1.0 terminal testing is the fake device harness only; fake brain and pytest suite deferred to v1.1 | Author's scoping choice. The bridge only calls the model on a `$robot` event, so handshake, registry and reconnect checks with the harness already cost nothing; only the devices-question path spends one model call | ✓ Good — 2026-09-24; Pydantic AI's `FunctionModel` gave zero-spend agent tests (59 TAP checks across four scripts) without a separate fake brain |
| Relax the Python dependency footprint; drop `requirements.txt` for a uv-managed `pyproject.toml`/`uv.lock` | Amends BRIDGE-01 (D-09): the lockfile replaces `requirements.txt` for reproducible installs. `pydantic-settings` (Phase 1) and `pydantic-ai` (Phase 2) are worth the added dependency for typed config and the Phase 2 agent-loop rewrite | ✓ Good — 2026-09-20 |
| Config is fail-fast and typed: missing vars or an empty `ALLOWED_PLAYERS` are validation errors (exit 1), never silent defaults | Closes the "empty allow-list means everyone" hole; pydantic-settings 2.15 needed `NoDecode` + `min_length=1` for comma-separated lists. Phase 1 code review flagged that `BRIDGE_TOKEN` still lacks the same `min_length=1` guard (REVIEW.md CR-01) | ✓ Good — 2026-09-20; token guard closed in Phase 2 (`bridge_token` `min_length=1`, 02-02) |
| Composition moves from Lua to Python; `client.lua` shrinks to one-to-one CC:Tweaked primitives (Phase 2 D-07) | Lua is harder to maintain and test than Python (only runs in-game); the real driver is testability — Python composition runs against the harness, Lua never did. Amends the "high-level tools live in Lua" principle from the starter. Author reaffirmed after the workflow raised the scope caution | ✓ Good — 2026-09-24, shipped in Phase 2 (`client.lua` primitives + `push_one_slot`; `sort_chest` composed in `agent.py`); unproven in game |
| Sorting rules persist on the bridge as a git-ignored `rules.json` beside `.env`, not on the device (Phase 2 D-08) | One global rule set is enough for one worker; the device now stores only `secret.txt` and its Lua, keeping devices dumber and the bridge the single source of truth for rule state | ✓ Good — 2026-09-24, shipped in Phase 2 with Lua-pattern rule matching on the bridge; unproven in game |
| The bridge guarantees reply delivery: when a run ends without the model calling `say`, `handle_request` speaks the final text to the requesting player (Phase 2, 02-07) | Pydantic AI's `output_type=str` invites a plain-text final answer; the first post-swap paid run dropped its reply for exactly that reason, and the pre-swap loop had only been lucky that the model chose the tool | ✓ Good — 2026-09-24, post-swap paid run passed after the fix |
| Paid harness runs use `claude-haiku-4-5`, and the long-lived processes they need (bridge, worker hold) are the operator's terminals, not a subagent's | A run costs fractions of a cent; subagent background processes die when the agent returns, and a session restart killed an orchestrator-started bridge | ✓ Good — 2026-09-24; the two-call budget was exceeded by one with the author's go-ahead |
| The harness passes only on a non-fallback `say`, not on the answer naming a device id | The chat process cannot know which workers are connected; an error fallback must never read as PASS, which it once did on an out-of-credit API 400 | ✓ Good — 2026-09-24 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-24 after Phase 2*

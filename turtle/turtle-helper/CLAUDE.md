# turtle-helper — project context for Claude Code

## What this is
An LLM-driven in-game assistant for Minecraft ATM9 (CC:Tweaked + Advanced Peripherals), in the
spirit of the Hired Girl robots in Heinlein's *The Door into Summer*. Players give it chores in
chat; it carries them out with turtles/computers and reports back. The brain runs outside the game.

## Architecture (decided; don't re-litigate without reason)
```
[Chat Box]─[Advanced Computer: base/chat.lua]──wss──┐
                                                    ├──[bridge/bridge.py]──Claude API
[turtle or computer: turtle/client.lua]──────wss────┘
```
- **Brain is outside the game.** No LLM calls from Lua (API key would live on an in-game computer).
- **Devices are dumb executors.** `client.lua` exposes `tools.<name>(args) -> table`; the bridge decides.
- **Bridge is the message bus.** Every device opens its own websocket; no rednet/modems between devices.
- **The websocket originates from the Minecraft server**, not the player's client. Bridge must be
  reachable from the server machine. This milestone (v1.0): dedicated server and bridge on the same
  PC, `ws://127.0.0.1:8765`, with an `[[http.rules]]` allow for `127.0.0.1` in
  `computercraft-server.toml` (CC:Tweaked blocks private/local addresses by default). No tunnel;
  a tunnel or a small always-on host returns only when the bridge leaves this PC.
- **High-level tools for the model, primitives on the device.** The model still calls `sort_chest`,
  not `forward` x40 - but the composition runs in Python (see below). Movement primitives exist
  for debugging only.
- **Chat is the interface.** Trigger prefix `$robot` (`$` messages are hidden from public chat by AP).
  One `say()` per task with a short summary; Chat Box has a ~1s send cooldown (queued in chat.lua).

### Thin Lua, thick Python (Phase 2, D-07 / D-08)
- **CC:Tweaked primitives live in Lua, one to one.** `client.lua` exposes `status`, `list_chest`,
  `push_one_slot` (a computer), plus `move`, `turn`, `dig`, `inspect`, `refuel` on a turtle, and
  `run_lua` behind `ALLOW_EVAL`. Its `tools` dispatch table and `readFile`/`writeFile` helpers stay
  so a later push-script primitive slots in without a rewrite.
- **Anything with a loop or a policy lives in Python on the bridge.** `bridge/agent.py` holds the
  typed tools the model sees (pydantic-ai, one Pydantic argument model per tool) and the
  compositions over `send_cmd`: `sort_chest` is `list_chest` then one `push_one_slot` per matched
  item. The toolset is rebuilt per request from the caps connected devices advertise; a
  composition is offered only when one connected device advertises every primitive it needs.
- **Sorting rules persist on the bridge**, in a git-ignored `rules.json` beside `.env` (resolved
  from the source file's location, like `.env`), edited by the `add_rule` / `remove_rule` /
  `list_rules` / `set_overflow` local tools. Rule patterns keep Lua `string.find` semantics
  (`bridge/lua_pattern.py`). The device stores `secret.txt`, `bridge.txt`, `startup.lua` and its
  Lua (Phase 3 D-06/D-16).
- Why: Lua only runs in game, Python runs against the harness. Testability drove this, not taste.

## Protocol (JSON, one websocket per device)
- `hello {id, token, role: turtle|computer|chat, caps[]}` — device → bridge, once
- `event {name, ...}` — device → bridge (e.g. `chat {user, text, uuid, hidden}`)
- `cmd {cid, tool, args}` → `result {cid, ok, data | error}` — bridge ↔ device

Adding a chore = one typed Python tool function in `bridge/agent.py` (argument model + async
function; the schema derives from the types), plus a `tools.xxx` entry in `client.lua` only if it
needs a new device-side primitive. The message shapes above do not change.

## Current state
- Bridge, agent and harness run end to end from a terminal (Phase 2: fake devices, drop/reconnect,
  wrong token, disallowed player, and the paid devices question all proven), but **Lua not yet run
  in game** (no Lua runtime where it was authored). First in-game job: get `$robot what devices are
  connected?` answering end to end.
- Sorting tools implemented on the bridge: `sort_chest` (composes `list_chest` + `push_one_slot`,
  which uses `pushItems` over a wired network, so the device doesn't carry items),
  `add_rule`/`remove_rule`/`list_rules`, `set_overflow`. Rules persist in `rules.json` beside
  `.env` on the bridge. First matching Lua pattern wins. Sorting is ported, not yet proven.
- `run_lua` (agent writes its own routines, Voyager-style) exists behind `ALLOW_EVAL=false`.
- `MODEL` is read from `.env` by `bridge/settings.py` (`.env.example` defaults to
  `claude-sonnet-5`); the bridge verifies the id against the API at boot.

## Security knobs
`BRIDGE_TOKEN` (shared secret in `secret.txt` on each device), `ALLOWED_PLAYERS` whitelist
(API costs are Nate's), `ALLOW_EVAL` off by default.

## Next up (rough priority)
1. First end-to-end run; fix any Lua errors CC reports.
2. `goto(x,y,z)` with GPS + simple pathing; `refuel` policy / `fuel_low` event.
3. `fetch_item(name, count)` via ME Bridge or RS Bridge.
4. `restock(machine, item, count)`, `mine_vein`.
5. Scheduled chores (bridge-side timers), multi-turtle dispatch.

## Conventions
- Lua: CC:Tweaked 1.20.x APIs (`textutils.serialiseJSON`, `textutils.empty_json_array` for empty
  lists, `http.websocket`). Keep tools pure functions returning JSON-safe tables; errors via `error()`.
  Line 1 of `base/chat.lua`, `turtle/client.lua` and `startup.lua` must keep its `-- <file name>`
  header, because devices refuse any download that does not start with it
  (`tests/test_device_lua.py` pins this).
- Python: asyncio + `websockets` + `pydantic-ai` (Anthropic provider) + `pydantic-settings`, uv-managed
  (`pyproject.toml` + `uv.lock`). Three modules: `bridge/settings.py`, `bridge/agent.py`,
  `bridge/bridge.py`. Type hints on every function, `from __future__ import annotations`, ruff
  (check + format) and mypy clean on `bridge/`, `harness/`, `deploy/`, `tests/`. `deploy/` now holds
  only the host-side helpers: the allow rule, the server probe and `uv run launch`.
- Dev loop: run `uv run bridge/bridge.py` locally and drive it with the harness
  (`uv run harness --role chat|worker --scenario <name>`; every scenario except `devices-question`
  spends nothing, and that one needs `--spend`). Zero-spend TAP tests live in `tests/`
  (`uv run python tests/test_agent.py` etc.). No tunnel this milestone. Devices are set up in game
  with the one `wget run` line for `install.lua` (token typed once, Phase 3 D-14/D-15), and
  `startup.lua` updates `chat.lua` and `client.lua` from `main` on every reboot (D-16); there is
  no PC-side placement path (D-19).

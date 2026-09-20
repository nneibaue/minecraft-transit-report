# turtle-helper

An in-game robot assistant for ATM9 (CC:Tweaked + Advanced Peripherals) with the brain running
outside the game. Three parts, one protocol.

```
you type "$robot sort the dump chest"
        │
[Chat Box]─[Advanced Computer: base/chat.lua]──wss──┐
                                                    ├──[bridge/bridge.py]──Claude API
[Turtle or Computer: turtle/client.lua]──────wss────┘
```

## Layout

| path | runs on | job |
|---|---|---|
| `base/chat.lua` | Advanced Computer with a Chat Box attached | forwards chat to the bridge, speaks replies (cooldown-safe queue) |
| `turtle/client.lua` | turtle **or** stationary Advanced Computer | executes tools: `sort_chest`, `list_chest`, `add_rule`, … ; movement tools appear only on a turtle |
| `bridge/bridge.py` | your PC (dev) / a small always-on host (prod) | websocket server + Claude agent loop |

## Protocol (all JSON over one websocket per device)

```jsonc
// device -> bridge, once
{"type":"hello","id":"turtle-1","token":"…","role":"turtle","caps":["sort_chest","move",…]}
// device -> bridge, when something happens
{"type":"event","name":"chat","user":"Nate","text":"$robot sort the dump chest","hidden":true}
// bridge -> device, then device -> bridge
{"type":"cmd","cid":"a1","tool":"sort_chest","args":{"from":"minecraft:chest_0"}}
{"type":"result","cid":"a1","ok":true,"data":{"moved":47,"no_rule":[],"destination_full":[]}}
```

Adding a chore = add a `tools.xxx` function in `client.lua` and a matching schema entry in
`DEVICE_TOOLS` in `bridge.py`. Nothing else changes.

## Setup

### 1. Bridge

**Prerequisites**

- [uv](https://docs.astral.sh/uv/) — install via `winget install --id astral-sh.uv --exact`
  (PowerShell). In Git Bash, run that same winget command from a PowerShell/cmd prompt, or use
  the [official installer script](https://docs.astral.sh/uv/getting-started/installation/) if
  `uv` isn't on `PATH` afterward.
- Verify: `uv --version`

**Setup**

```bash
cd turtle-helper
uv sync                    # installs from the committed uv.lock, creates .venv
cp .env.example .env       # local secrets file, git-ignored
```

**Configure** — fill in the new `.env`:

- `ANTHROPIC_API_KEY` — from the [Anthropic console](https://console.anthropic.com)
- `BRIDGE_TOKEN` — generate with `python -c "import secrets; print(secrets.token_hex(24))"`;
  save it, it goes in `secret.txt` in game
- `ALLOWED_PLAYERS` — comma-separated player names allowed to give orders

**Run**

```bash
uv run bridge/bridge.py
```

Listens on `ws://127.0.0.1:8765` by default; `HOST`, `PORT`, `MODEL`, and the other settings
documented in `.env.example` can all be overridden in `.env`.

Expose it to the Minecraft **server** (the websocket originates from the server, not your
client). This milestone runs the dedicated server and the bridge on the same PC; hosting the
bridge elsewhere and tunneling to it (cloudflared, Tailscale, a VPS) returns in a later milestone.

- **Same box as the MC server:** use `ws://127.0.0.1:8765`, but the server admin must allow it in
  `computercraft-server.toml` (local addresses are blocked by default):
  ```toml
  [[http.rules]]
  host = "127.0.0.1"
  action = "allow"
  ```

### 2. In game

On the base computer (Chat Box attached, wired modem optional):
```
edit secret.txt      -> paste BRIDGE_TOKEN
edit chat.lua        -> paste base/chat.lua, set BRIDGE_URL
chat
```

On the sorter (turtle or Advanced Computer), on the same **wired modem network** as the chests:
```
label set sorter
edit secret.txt      -> paste BRIDGE_TOKEN
edit client.lua      -> paste turtle/client.lua, set BRIDGE_URL
client
```
Put `shell.run("client")` / `shell.run("chat")` in `startup.lua` so they survive restarts.

Find inventory names with `peripheral.getNames()` in the Lua prompt, or right-click a wired modem
on a chest (it prints the name). The sorter uses `pushItems`, so items move over the network
without the device carrying them; a stationary computer works as well as a turtle for this job.

### 3. Talk to it

```
$robot what devices are connected?
$robot set overflow to minecraft:chest_9
$robot add a rule: anything with "ingot" goes to minecraft:chest_2
$robot sort minecraft:chest_0
$robot what's in overflow?
```

Messages starting with `$` are hidden from public chat by Advanced Peripherals; only Chat Boxes see
them. Change `COMMAND_PREFIX` if you want a different trigger word.

## Safety knobs

- `BRIDGE_TOKEN` — connections without it are dropped.
- `ALLOWED_PLAYERS` — chat from anyone else is ignored (the API key is yours; every request costs you).
- `ALLOW_EVAL` in `client.lua` (default `false`) — enables a `run_lua` tool so the agent can write
  its own routines. Powerful, Voyager-style, and also lets it do anything a program on that
  computer can do. Turn on deliberately, and add `run_lua` to `DEVICE_TOOLS` when you do.
- `MODEL` env var — set to whatever current model you want; default is a placeholder.

## Next chores to add

`goto(x,y,z)` (GPS + simple pathing), `fetch_item(name, count)` via an ME/RS Bridge,
`restock(machine, item, count)`, `mine_vein`. Each is Lua on the device + one schema entry.

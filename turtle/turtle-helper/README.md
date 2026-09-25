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
| `turtle/client.lua` | turtle **or** stationary Advanced Computer | exposes CC:Tweaked primitives one-to-one: `status`, `list_chest`, `push_one_slot`; movement primitives appear only on a turtle |
| `bridge/bridge.py` + `bridge/agent.py` | your PC (dev) / a small always-on host (prod) | websocket server + Pydantic AI agent with typed tools; compositions such as `sort_chest` and the sorting rules live here |
| `harness/` | your terminal | fake chat/worker device that speaks the protocol against the bridge, no game needed (see [Harness](#harness)) |

## Protocol (all JSON over one websocket per device)

```jsonc
// device -> bridge, once
{"type":"hello","id":"turtle-1","token":"…","role":"turtle","caps":["status","list_chest","push_one_slot","move",…]}
// device -> bridge, when something happens
{"type":"event","name":"chat","user":"Nate","text":"$robot sort the dump chest","hidden":true}
// bridge -> device, then device -> bridge (one primitive per cmd; the bridge composes the chore)
{"type":"cmd","cid":"a1","tool":"push_one_slot","args":{"from":"minecraft:chest_0","slot":3,"dest":"minecraft:chest_2"}}
{"type":"result","cid":"a1","ok":true,"data":{"moved":64}}
```

Adding a chore = one typed Python tool function in `bridge/agent.py` (anything with a loop or a
policy lives there), plus a `tools.xxx` function in `client.lua` only if it needs a new
device-side primitive. The wire shapes above never change.

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
- `BRIDGE_TOKEN` — the shared secret every device presents. It is typed once per device at the
  in-game installer's hidden prompt, so a short but distinctive passphrase is easiest. For a random
  one, run `python -c "import secrets; print(secrets.token_hex(24))"`. It lives only in `.env` and
  in each device's `secret.txt`, never in the repo.
- `ALLOWED_PLAYERS` — comma-separated player names allowed to give orders

**Run**

```bash
uv run bridge/bridge.py
```

Listens on `ws://127.0.0.1:8765` by default; `HOST`, `PORT`, `MODEL`, and the other settings
documented in `.env.example` can all be overridden in `.env`.

With `SERVER_DIR` in `.env` set to the server's root folder (where `run.bat` lives),

```bash
uv run launch
```

opens the bridge and the server's `run.bat` in two windows (Windows only) and returns. It does
not watch or restart either one.

Expose it to the Minecraft **server** (the websocket originates from the server, not your
client). This milestone runs the dedicated server and the bridge on the same PC; hosting the
bridge elsewhere and tunneling to it (cloudflared, Tailscale, a VPS) returns in a later milestone.

- **Same box as the MC server:** use `ws://127.0.0.1:8765`. CC:Tweaked blocks local addresses by
  default, so the server needs one allow rule in
  `<SERVER_DIR>/world/serverconfig/computercraft-server.toml`:
  ```toml
  [[http.rules]]
  host = "127.0.0.1"
  action = "allow"
  ```
  - Add it by hand while the server is stopped, as its own block placed **before** the stock
    `$private` deny rule (rules are read top to bottom).
  - A full server restart applies it; `/reload` does not.
  - Forge rewrites this file when the server boots and keeps the rule. That was checked on this
    server, which loads CC:Tweaked 1.116.1.
  - Write `127.0.0.1`, never the hostname `localhost`: Windows resolves `localhost` to `::1`,
    which the `$private` deny blocks.
  - The [smoke check](#smoke-check) below confirms the rule from a computer in game.

Before touching the game, you can exercise the running bridge from a terminal with the
[harness](#harness) below; every scenario but one spends nothing.

### 2. In game

Every device, the base computer with the Chat Box and any sorter alike, is set up the same way,
entirely in game, with one line at its prompt:

```
wget run https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/install.lua
```

1. At `Bridge token (typing is hidden):`, type the bridge token (`BRIDGE_TOKEN` from `.env`) and
   press Enter. Only the first install on a computer asks for it.
2. At `Bridge URL (press Enter to keep it):`, press Enter to keep `ws://127.0.0.1:8765`.
3. Type `reboot`.

After the reboot the device runs `chat` if a Chat Box is attached, and `client` otherwise; nothing
is configured per device. The installer puts `chat.lua`, `client.lua`, `startup.lua`, `bridge.txt`
and `secret.txt` in the computer's own folder on the server,
`<SERVER_DIR>/world/computercraft/computer/<id>/`; the `id` command shows a computer's number.
`label set <name>` is optional: the bridge shows the label, or `device-<id>` without one.

To repair a device, run the same line again. It keeps `secret.txt` and offers the current bridge
URL as the default, and it asks before replacing a `startup.lua` that is not turtle-helper's own.
To change a device's token, run `rm secret.txt`, then the line again.

A sorter (turtle or Advanced Computer) sits on the same **wired modem network** as the chests.
Find inventory names with `peripheral.getNames()` in the Lua prompt, or right-click a wired modem
on a chest (it prints the name). The sorter uses `pushItems`, so items move over the network
without the device carrying them; a stationary computer works as well as a turtle for this job.

#### Updating

Push the change to `main`, wait up to about 5 minutes (raw.githubusercontent.com caches files for
a few minutes), then type `reboot` on each device. On every boot `startup.lua` downloads `chat.lua`
and `client.lua` from `main` and prints, for each file, `updated <file>` or `<file> up to date`.

If GitHub is unreachable, or a download is incomplete or is not the expected Lua file, it prints
`<file>: <reason>; using the local copy` and runs the last good copy, so a GitHub outage never
stops a device.

`startup.lua` does not update itself, and `install.lua` runs only when you run it. A change to
either one reaches a device only when you re-run the wget line on it, which keeps `secret.txt`.

#### Smoke check

With the bridge running, type `lua` at any computer's prompt, then each line below. After lines 2
and 3 the prompt also prints `1`, which is `print`'s own return value; ignore it.

1. ```lua
   ws, err = http.websocket("ws://127.0.0.1:8765") print(ws, err) if ws then ws.close() end
   ```
   prints `table: <address> nil` (for example `table: 3c9a6ef1 nil`): a handle, so the
   connection works. The bridge logs a `no valid hello` warning for this bare connection, which
   is expected.
2. ```lua
   print(http.websocket("ws://127.0.0.2:8765"))
   ```
   prints `false Domain not permitted`. This is what any computer sees for an address no allow
   rule covers, and also what `ws://127.0.0.1:8765` gives while the allow rule is missing.
3. ```lua
   print(http.websocket("ws://127.0.0.1:8766"))
   ```
   prints `false Could not connect`. This is what you see when the rule is present but nothing
   listens on that port, and also what `ws://127.0.0.1:8765` gives while the bridge is not running.

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

## Harness

`harness/` is a terminal-driven fake device. It speaks the same wire protocol as `chat.lua` and
`client.lua` against the running bridge, prints every frame in both directions, and proves one
named scenario per run with an exit code. No game involved, and no API spend except the one
scenario that asks for it explicitly.

Start the bridge first (`uv run bridge/bridge.py`, above). The harness reads `HOST`, `PORT`,
`BRIDGE_TOKEN`, `COMMAND_PREFIX` and `ALLOWED_PLAYERS` from the same `.env` (it never imports the
bridge itself, only its settings). Then, from `turtle-helper`:

```bash
uv run harness --role chat|worker --scenario <name> [--turtle] [--spend] [--token <value>]
```

| flag | meaning |
|---|---|
| `--role chat` | play `chat.lua`: id `harness-chat`, caps `["say"]`, answers `say` with `{queued: true}` |
| `--role worker` | play `client.lua` on a computer: id `harness-worker`, caps `status`, `list_chest`, `push_one_slot`, canned results in the Lua's shapes |
| `--turtle` | the worker connects as role `turtle` and adds `move`, `turn`, `dig`, `inspect`, `refuel` |
| `--spend` | allow the one scenario that costs a real model call (`devices-question`); see below |
| `--token <value>` | override the hello token (for `wrong-token`); may be empty |

Exit code `0` is a pass (`PASS: <scenario>`), `1` a failed expectation (`FAIL: <scenario> - <why>`),
and `2` a refusal (`REFUSED: ...`: no `--spend`, or a config error) - a refusal is not a protocol
failure. Every wire message prints as one line - timestamp, device id, `->` sent or `<-` received,
then the compact JSON exactly as it went over the wire; the hello token is the one field the log
redacts. Every wait is bounded, so a scenario never hangs on a bridge that stopped answering.

### Scenarios

| scenario | role | proves | run |
|---|---|---|---|
| `hello-handshake` | chat or worker | the hello is accepted: no close arrives within 5 s | `uv run harness --role chat --scenario hello-handshake` |
| `status-command` | worker | the fake worker advertises exactly `client.lua`'s caps and answers `status`, `list_chest`, `push_one_slot` and an unknown tool with the Lua's result shapes, then stays registered | `uv run harness --role worker --scenario status-command` (add `--turtle` for the turtle set) |
| `drop-and-reconnect` | chat or worker | a garbage frame is logged and ignored (the device stays registered), a drop followed by a same-id rejoin is accepted, and a second same-id connection replaces the stale socket, which is closed with code `4000` | `uv run harness --role worker --scenario drop-and-reconnect` |
| `wrong-token` | chat or worker | a wrong or empty token is closed with code `4001`; the bridge logs `rejected device harness-chat from <addr>: bad token` without the token value | `uv run harness --role chat --scenario wrong-token --token wrong-value-0001`, then again with `--token ""` |
| `disallowed-player` | chat | a prefixed chat event from a player not in `ALLOWED_PLAYERS` produces nothing for 5 s; the bridge logs `ignoring <user> (not allowed)`. Costs nothing: the bridge drops it before the model | `uv run harness --role chat --scenario disallowed-player` |
| `devices-question` | worker + chat, two terminals | `$robot what devices are connected?` is answered by a `say` cmd that is a real answer (the bridge's `Sorry ..., something went wrong: ...` fallback fails it). **The one paid scenario.** | see below |

The bridge's own log is where the two sides of an exchange interleave; each harness process shows
only its own device.

### devices-question: two terminals and `--spend`

This is the only scenario that sends a prefixed chat event from an allowed player, so it is the only
one that makes the bridge call the model. Start the worker first, so it is registered when the model
asks what is connected:

```bash
# terminal 1 - the fake worker registers with client.lua's caps and holds for 60 s, answering any cmd
uv run harness --role worker --scenario devices-question

# terminal 2, within those 60 s - the paid call
uv run harness --role chat --scenario devices-question --spend
```

Terminal 2 passes when a `say` cmd arrives within 30 s carrying an answer (a `list_devices` cmd
before it is accepted too), and prints `devices-question: robot said '...'` so you can read what the
model actually said. A good answer names `harness-worker`.

`--spend` is the deliberate act. Without it the chat side refuses before connecting
(`REFUSED: devices-question - ...`, exit 2) and nothing is sent. The guard is enforced in code, in
two places: the scenario refuses up front, and the fake device itself refuses to send any
`$robot`-prefixed chat event from an allowed player unless the flag was given, so no scenario can
spend by accident. Every other scenario needs no flag and spends nothing.

## Safety knobs

- `BRIDGE_TOKEN` — connections without it are dropped.
- `ALLOWED_PLAYERS` — chat from anyone else is ignored (the API key is yours; every request costs you).
- `ALLOW_EVAL` in `client.lua` (default `false`) — enables a `run_lua` tool so the agent can write
  its own routines. Powerful, Voyager-style, and also lets it do anything a program on that
  computer can do. Turn on deliberately, and add a matching typed `run_lua` tool in
  `bridge/agent.py` when you do (the bridge only offers tools a connected device advertises).
- `MODEL` env var — set to whatever current model you want; default is a placeholder.

## Next chores to add

`goto(x,y,z)` (GPS + simple pathing), `fetch_item(name, count)` via an ME/RS Bridge,
`restock(machine, item, count)`, `mine_vein`. Each is a typed tool in `bridge/agent.py`, plus a
new Lua primitive only where the device has to do something it cannot do yet.

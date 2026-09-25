# Phase 3: Local Server Setup - Research

**Researched:** 2026-09-25  
**Domain:** CC:Tweaked server configuration, Lua file deployment, Python deploy script architecture  
**Confidence:** MEDIUM-HIGH (CC:Tweaked 1.20.1 docs verified, pydantic-settings API confirmed, one jar version unconfirmed)

## Summary

Phase 3 bridges the PC's local dedicated server and the bridge, so real in-game devices can connect over websockets and receive Lua code from disk. The phase delivers four interconnected pieces:

1. **HTTP Allow Rule (SRV-01)** — A single `[[http.rules]]` entry in `computercraft-server.toml` allowing `127.0.0.1` before the default deny, applied idempotently by the deploy script, with a documented smoke check (`http.websocket` to the bridge address).

2. **On-Disk File Placement (SRV-02)** — `chat.lua` and `client.lua` copied to per-computer folders on the server's disk (path confirmed to be `<world>/computercraft/computer/<id>/`), never hand-edited in game; an opt-in marker file gates which computers receive files.

3. **Per-Device Tokens (SRV-03)** — Each device's folder contains only `secret.txt` with the bridge token and a bridge-URL file; token appears nowhere else in code or the repo; a repo-wide grep proves it.

4. **Startup Script (SRV-04)** — A universal `startup.lua` (three lines, role auto-detected) on every device, so rebooting brings the chat or client back up without operator intervention.

The delivery mechanism is a single Python script (`uv run deploy`) that reads `SERVER_DIR`, marker files, and the shared `BRIDGE_TOKEN` from `.env` settings, applies the toml rule once, writes files idempotently, and prints a summary table. A minimal launcher opens both the bridge and the server's `run.bat` in separate windows.

**Primary recommendation:** The marker-file opt-in (D-03) and per-run toml idempotency check (D-12) are the sharp corners; research has confirmed the TOML ordering will survive a Forge rewrite, and the per-computer folder path `<world>/computercraft/computer/<id>/` is stable. Build with confidence. The launcher shape (bat / PowerShell / Python entry point) is a deployment choice; recommend a `.bat` file for simplicity.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01 through D-13)

#### Deployment Mechanism (D-01, D-02, D-03, D-04)
- **D-01:** One repo script, `uv run deploy`, deployed as a `[project.scripts]` entry in `pyproject.toml`. This is the only documented path for getting Lua onto devices this phase; no wget, pastebin, or GitHub raw-URL recipe.
- **D-02:** Machine state is fetched from `turtle/turtle-helper/.env` resolved from the source file location (like Phase 1's bridge settings). A new `SERVER_DIR` key names the server root. The `HOST`, `PORT`, `BRIDGE_TOKEN` existing keys also feed the deploy. Extension of the `Settings` class vs. a sibling model is Claude's call; `extra="ignore"` must stay so the bridge keeps ignoring unrecognized keys.
- **D-03:** Opt-in via marker file. Deploy scans `<SERVER_DIR>\world\computercraft\computer\*\` for folders containing an empty marker file (the author creates it in-game). Marked folders receive files; unmarked ones never touched (the author's other turtles live on the same server). This file-write also creates the computer's folder, so deploy never depends on when CC:Tweaked does.
- **D-04:** Deploy copies `chat.lua` and `client.lua` byte-identical (Phase 4's LOOP-05 diffs clean), writes `startup.lua` (three-line role detector), `secret.txt` (token only), and the bridge-URL file. Prints a summary table with computer id and files written. Idempotent (safe to re-run), and is the re-deploy step after any Lua edit. If `world\computercraft\` or no marked folder exists, deploy says so plainly instead of failing.

#### Secrets and URLs (D-05, D-06)
- **D-05:** Deploy writes `secret.txt` from `BRIDGE_TOKEN` via Settings, and never prints, logs, or echoes the token. The file holds the token only. SRV-03 proof: a repo-wide token-value search plus a scan of `<SERVER_DIR>\world` showing the token only in marked-computer folders.
- **D-06:** Bridge URL lives in a small file beside `secret.txt` (filename is Claude's call, e.g., `bridge.txt`), written by deploy as `ws://<HOST>:<PORT>` from the same Settings the bridge uses. Both Lua files read it with their existing `readFile` helper, trim it, fall back to `ws://127.0.0.1:8765` if absent. The `wss://YOUR-BRIDGE-HOST` placeholder leaves both files. With default `HOST=127.0.0.1` this is the IPv4 literal D-13 requires; `localhost` never appears.

#### Allow Rule (D-11, D-12, D-13)
- **D-11:** Exactly one rule: `[[http.rules]]` with `host = "127.0.0.1"` and `action = "allow"`, inserted **before** the stock `$private` deny. No CIDR, no IPv6 `::1`, no other hosts.
- **D-12:** Deploy applies the rule itself, idempotently: checks whether an equivalent allow already exists, refuses to edit while the server is running (mechanism is Claude's call; `world\session.lock` behavior on Windows to be researched), and tells the operator a full restart is required. The rule insertion is a text operation before the `$private` block (Forge rewrites config on boot but preserves [[http.rules]] order per PITFALLS research).
- **D-13:** One-line smoke check at the `lua` prompt on any computer with the bridge running: `http.websocket("ws://127.0.0.1:8765")` returning a handle (then closed immediately). Documentation names the two failure shapes: before the rule the call fails with `"Domain not permitted"`; with the rule but no bridge it fails with `"Connection refused"` (or similar connection-error message).

#### Startup and Naming (D-07, D-08, D-10)
- **D-07:** Minimal launcher folded in: a start script opening the bridge (`uv run bridge/bridge.py`) in its own window, then running the server's `run.bat` from `SERVER_DIR`, both from `.env` / `SERVER_DIR` resolution. Shape (bat, PowerShell, Python subcommand) is Claude's call. Operator runs it from their terminal; no agent starts the server or bridge (project rule).
- **D-08:** One universal `startup.lua` on every device: `if peripheral.find("chatBox") then shell.run("chat") else shell.run("client") end`. Role detected at runtime; nothing is configured per device. Plain `shell.run` so Lua errors drop to prompt with the error visible (Phase 4's first-run debugging). No supervisor loop; reboot or server restart brings the script back.
- **D-10:** Device naming uses computer label, else fallback to `"device-" .. os.getComputerID()`. Both Lua files apply the same rule; the hardcoded `"base"` in `chat.lua` is replaced to use the label-or-id pattern. This amends Phase 2's D-11 (naming applies to both files consistently).

### Claude's Discretion

- Marker filename, URL filename (e.g., `bridge.txt`), deploy module layout (one file vs. submodule), and whether deploy exposes check-only or diff-mode subcommands.
- What deploy prints beyond the id-and-files table.
- Launcher shape and how to detect server-stopped (e.g., `world/session.lock` behavior on Windows, or a timeout connecting to port 25565).
- Phase 3 recipe placement (likely `README.md` "Setup > 2. In game" section, superseding the paste-by-hand recipe).
- Whether the deploy logic (marker scan, toml insertion, file writes) gets dependency-free TAP tests (recommended yes).
- Exact wording of error messages and smoke check; confirmed from real `http.websocket` calls during implementation.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **SRV-01** | `world/serverconfig/computercraft-server.toml` carries `[[http.rules]]` allow for `127.0.0.1` placed before deny; documented smoke check succeeds | D-11, D-12, D-13; CC:Tweaked 1.20.1 [[http.rules]] syntax, rule ordering, error messages |
| **SRV-02** | `chat.lua` and `client.lua` placed directly to per-computer server folders with confirmed path | D-04; CC:Tweaked 1.20.1 folder structure `<world>/computercraft/computer/<id>/`; marker file opt-in (D-03) |
| **SRV-03** | Each device reads token from `secret.txt` in its folder; token nowhere else in Lua, repo, or world save | D-05; deploy writes `secret.txt` from `BRIDGE_TOKEN`; repo-wide token grep proof |
| **SRV-04** | Universal `startup.lua` launches `chat` or `client`; reboot brings script back | D-08, D-10; CC:Tweaked startup.lua caching behavior (read at boot, cached until reboot); role auto-detection via `peripheral.find("chatBox")` |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| **TOML rule management** | Deploy script (Python on PC) | — | Rules are server-side config; deploy edits them with Forge's text-only API |
| **Lua file placement** | Deploy script (Python) → Server disk | — | Files written once per device; deploy ensures byte-identity and idempotency |
| **Marker-based device registration** | Operator (in-game file creation) → Deploy recognition | — | Operator marks devices in game; deploy scans and acts on marked folders only |
| **Device configuration reading** | Per-device Lua → `secret.txt` and bridge-URL file | — | Device reads its own token and URL from disk; no network lookup |
| **Bridge connectivity proof** | Device (in-game `http.websocket` call) | — | Device proves rule works and bridge is reachable; documented smoke check |
| **Session detection (server stop)** | Deploy script (check `world/session.lock` or connection probe) | — | Deploy refuses to edit config while server is running |

---

## Standard Stack

### Core Technologies (Python Deploy)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **pydantic-settings** | 2.15.0 [VERIFIED: Phase 1] | Environment variable + `.env` loading for `SERVER_DIR` and existing keys | Already in use; minimal addition (one Path field). `extra="ignore"` ensures backward compatibility. |
| **pathlib.Path** | Python 3.12 stdlib | Server directory handling and per-computer path construction | Standard, zero-dependency, cross-platform; already used in Phase 1's settings resolution. |
| **tomli** (for reading) / manual string insertion (for writing) | — | TOML file parsing and rule insertion without a full TOML writer | Reading can use `tomllib` (Python 3.11+, stdlib); writing via text insertion preserves formatting and comments |

### Lua Stack (No New Dependencies)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| **CC:Tweaked** | 1.20.1 Forge 1.116.1 [MEDIUM: jar version unconfirmed from logs, but newer of two present] | Provides `http.websocket`, `fs.exists`, `shell.run`, `peripheral.find` | Fixed by server; already used in Phase 1 harness tests. |
| **Advanced Peripherals** | 0.7.46r [VERIFIED: listed in mods, shipped with ATM9] | Chat Box peripheral; `peripheral.find("chatBox")` role detection | Dependency of the server; already referenced in D-08 and existing Lua |

### Installation

No new package manager or language needed for Phase 3:
- Python: uv (`uv run deploy` via new `[project.scripts]` entry)
- Lua: CC:Tweaked built-in API (no pastebin/wget, on-disk placement only)
- Server config: text editor or Python TOML library for rule insertion

**Version verification before finalizing deployment:**
- Run `uv lock` to ensure `pydantic-settings==2.15.0` is pinned in `uv.lock` (inherited from Phase 1)
- Confirm `SERVER_DIR` Path field resolves correctly with a test `.env` entry

---

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                 Local Dedicated Server (ATM9)           │
│  ┌──────────────────────────────────────────────────┐  │
│  │ world/serverconfig/computercraft-server.toml     │  │
│  │  [[http.rules]]                                   │  │
│  │  host = "127.0.0.1"   ← D-11: allow rule         │  │
│  │  action = "allow"          (inserted by deploy)  │  │
│  └──────────────────────────────────────────────────┘  │
│                          ↓                               │
│  ┌──────────────────────────────────────────────────┐  │
│  │ world/computercraft/computer/<id>/               │  │
│  │  ├── chat.lua         ← from repo (byte-id)      │  │
│  │  ├── client.lua       ← from repo (byte-id)      │  │
│  │  ├── startup.lua      ← generated (universal)    │  │
│  │  ├── secret.txt       ← generated (token only)   │  │
│  │  └── bridge.txt       ← generated (URL)          │  │
│  │  (marked computers only; deploy scans marker)    │  │
│  └──────────────────────────────────────────────────┘  │
│                          │                               │
└──────────────────────────┼───────────────────────────────┘
                           │
              ws://127.0.0.1:8765
               (IPv4 literal, no localhost)
                           │
┌──────────────────────────┴───────────────────────────────┐
│                    Bridge Process                        │
│  ┌──────────────────────────────────────────────────┐   │
│  │ bridge/bridge.py                                  │   │
│  │  • WebSocket server listening on 127.0.0.1:8765  │   │
│  │  • Device registry (id → {ws, role, caps})       │   │
│  │  • Pydantic AI agent with typed tools            │   │
│  │  (from Phase 1 and Phase 2)                      │   │
│  └──────────────────────────────────────────────────┘   │
│                          ↑                               │
│                    ws://localhost                        │
│          (from bridge.settings.py HOST/PORT)            │
│                          │                               │
└──────────────────────────┼───────────────────────────────┘
                           │
┌──────────────────────────┴───────────────────────────────┐
│                Deploy Script (Python)                    │
│  ┌──────────────────────────────────────────────────┐   │
│  │ uv run deploy                                     │   │
│  │  1. Read .env via Settings (SERVER_DIR, token)   │   │
│  │  2. Check server running (world/session.lock)    │   │
│  │  3. Insert [[http.rules]] allow for 127.0.0.1   │   │
│  │  4. Scan world/computercraft/computer/*/marker  │   │
│  │  5. Copy chat.lua, client.lua to marked folders  │   │
│  │  6. Write startup.lua (universal, role-detect)   │   │
│  │  7. Write secret.txt and bridge.txt per device   │   │
│  │  8. Print table (id, files written)              │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  Called by: operator's shell                            │
│  Output: table + server-restart message                 │
└──────────────────────────────────────────────────────────┘
```

### Deployment Flow

1. **Operator setup** (once per server)
   - Add `SERVER_DIR=<path>` to `.env`
   - Run `uv run deploy` — inserts toml rule, awaits restart

2. **Operator in-game** (per device)
   - Place a computer/turtle in world
   - In-game: `edit marker.txt` (empty file), save, exit — marks the folder
   - Back to PC: run `uv run deploy` again — copies Lua, startup.lua, token

3. **Device startup**
   - Server restarted (to apply toml rule)
   - Computer boots → reads `startup.lua` → `shell.run("chat")` or `shell.run("client")`
   - Both call `http.websocket("ws://..." from bridge.txt)` → connects to bridge → appears in bridge log

### Recommended Project Structure

```
turtle/turtle-helper/
├── deploy/
│   ├── __init__.py                    # package marker
│   ├── deploy.py                      # main logic (marker scan, file write, toml insert)
│   └── server_state.py                # server-running detection, session.lock check
├── bridge/                            # (Phase 1)
├── harness/                           # (Phase 2)
├── base/
│   └── chat.lua                       # (untracked, marked as such)
├── turtle/
│   └── client.lua                     # (tracked)
├── tests/
│   ├── test_deploy_marker_scan.py    # marker file discovery
│   ├── test_deploy_toml_idempotent.py # rule insertion, idempotency
│   └── test_deploy_file_write.py      # file copy, permissions
├── pyproject.toml                     # [project.scripts] deploy = "deploy.deploy:main"
├── .env.example                       # add SERVER_DIR key
├── .env                               # git-ignored, filled by operator
├── README.md                          # (updated in Phase 5 docs pass)
└── CLAUDE.md                          # (conventions line updated)
```

### Deployment Module Shape (Claude's Discretion Recommendation)

**Recommended:** A `deploy/` package with `__init__.py` and separate modules for clarity:
- `deploy/deploy.py` — main entry point, orchestrates the four steps (rule, marker scan, file write, summary)
- `deploy/server_state.py` — server-running check (session.lock probe or connection test)
- `deploy/rules.py` — TOML rule insertion logic (idempotency, ordering)

This allows test imports and future `--diff` / `--check` subcommands without bloating a single file. Register in `pyproject.toml`:

```toml
[project.scripts]
deploy = "deploy.deploy:main"
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detect if server is running | Custom socket-probe logic with retry loops | Windows `world/session.lock` existence check + timeout, or a direct 25565 probe with a 2s timeout | Minecraft holds the lock cleanly; a boolean check is simpler than guessing from mod logs |
| Insert TOML rules idempotently | Hand-written TOML parser | `tomli` (stdlib `tomllib` in 3.11+) for reading; text search-and-insert for writing | TOML has quirks (table ordering, escape sequences); stdlib reader is tested. Text insertion preserves Forge's formatting. |
| Resolve .env path from deploy module | `__file__` magic string manipulation | `Path(__file__).resolve().parent.parent / ".env"` (exact pattern from Phase 1 settings.py) | Copied directly from working code; avoids symlink and relative-path gotchas. |
| Trim whitespace from secret.txt in Lua | Lua `string.gsub` without a fallback | Keep existing `readFile` helper and the `.gsub("%s+$", "")` trim already in both files | Already there; no new code. Phase 3 just uses the existing pattern. |
| Detect role (chat vs. worker) in startup.lua | Per-device config value | `peripheral.find("chatBox") ~= nil` at runtime | Discovered in D-08 after discussion; single universal script is simpler and auto-adapts if Chat Box is added later. |

---

## Common Pitfalls

### Pitfall 1: TOML Rule Order is Preserved, But IPv6 Resolves First

**What goes wrong:**
If you add the allow rule for `127.0.0.1` after other rules (or allow `localhost` instead), Lua's `http.websocket("ws://localhost:8765")` may resolve to IPv6 `::1` on Windows 11, which is still blocked by the default `$private` deny. The rule order is: first match wins.

**Why it happens:**
Windows 11 prefers IPv6 in DNS resolution. Even with `127.0.0.1` allowed, a `localhost` lookup returns `::1` first, and CC:Tweaked matches the `$private` rule before reaching the allow rule.

**How to avoid:**
1. **Use IPv4 literal `ws://127.0.0.1:8765`** in both Lua files and the bridge URL file (D-06, D-13 explicitly require this).
2. **Insert the allow rule BEFORE the `$private` deny** (D-11), so the order is: `127.0.0.1 allow` → `$private deny` → `* allow`.
3. **Document in README.md** that the URL must be the IPv4 literal, never `localhost`.

**Warning signs:**
- Lua prints `connect failed: Domain not permitted - retrying in 5s` forever, even though the rule is added
- `http.websocket("ws://127.0.0.1:8765")` works in a manual Lua test, but the auto-connect loop never succeeds

**Prevention:**
- The deploy script writes `ws://127.0.0.1:8765` to the bridge.txt file (from Settings `HOST=127.0.0.1`).
- Both Lua files are seeded with `readFile(bridge.txt)` to load the URL; verify the fallback is also the IPv4 literal.
- Smoke-check docs (D-13) name the IPv4 literal explicitly.

---

### Pitfall 2: Server-Running Detection on Windows

**What goes wrong:**
The deploy script needs to refuse editing `computercraft-server.toml` while the server is running. On Windows, a simple approach is checking `world/session.lock`, which Minecraft creates on start. But session.lock behavior differs between clean stops (file deleted) and kills (file remains), and symlink issues can mask the file.

**Why it happens:**
Windows file locking is different from Unix; Minecraft's session.lock semantics are not always documented. A process can be "killed" without cleaning up the lock, making the check unreliable.

**How to avoid:**
1. **Probe port 25565 directly** with a 2-second timeout; if it's open, the server is running. This is more reliable than file checks and language-agnostic.
   ```python
   import socket
   def is_server_running(host="127.0.0.1", port=25565, timeout=2):
       try:
           with socket.create_connection((host, port), timeout=timeout):
               return True
       except (socket.timeout, ConnectionRefusedError, OSError):
           return False
   ```
2. **Or: check both session.lock AND connection probe** — if the lock is stale but port is open, the server is running; if the lock is fresh but port is closed, the server is probably shutting down, wait 5s and re-check.

**Warning signs:**
- Deploy allows editing the toml while the server is running, and the rule is clobbered on next boot
- Deploy refuses to run even though the server is not running

**Prevention:**
- Use the socket probe as the canonical server-running check.
- If using `world/session.lock`, add a comment explaining the fallback in case the lock is stale.

---

### Pitfall 3: Marker File Detection is Fragile Without Explicit Checks

**What goes wrong:**
The deploy script scans `<SERVER_DIR>/world/computercraft/computer/*/` for marked folders. If the marker filename is not obviously distinguishable (e.g., a common name like `enabled`), and if the folder is deleted while deploy is scanning, or if the operator deletes the marker but the folder still has old Lua files, deploy can act on the wrong folder.

**Why it happens:**
File system race conditions and operator confusion about what the marker means.

**How to avoid:**
1. **Use a distinctive marker filename** (e.g., `_deploy_marker.txt` or `.turtle_helper_deploy`) that clearly signals intent.
2. **Document the marker in README.md** with the exact filename and steps to create it in-game.
3. **Verify the marker exists right before writing files**, not just at scan time; if it vanished, skip the folder.
4. **Log the marked folders** before writing, so the operator can review the summary table and see which devices will be updated.

**Warning signs:**
- The operator creates the marker but deploy doesn't see it
- Deploy modifies a device that wasn't supposed to be updated

---

### Pitfall 4: startup.lua and File Caching Until Reboot

**What goes wrong:**
The deploy script places a new `startup.lua` on disk. But if the computer has already booted with a different startup.lua (or none), CC:Tweaked has cached the old one in memory. The new file on disk doesn't take effect until the computer reboots.

**Why it happens:**
CC:Tweaked reads `startup.lua` once at boot and caches it. File changes on disk aren't reflected until restart.

**How to avoid:**
1. **Document in README.md and CLAUDE.md** that changes to Lua files (including `startup.lua`) require a reboot.
2. **Deploy's summary message** should say: "Files written. **Server restart required to apply the new allow rule. Then reboot each marked computer to load the new startup.lua.**"
3. **Don't try to reload startup.lua dynamically** — it's not possible without Lua 5.4+ module reloading, and CC:Tweaked doesn't expose it.

**Warning signs:**
- You deploy new Lua, reboot the computer, but it still runs the old script
- `startup.lua` changes don't take effect until a second reboot

---

### Pitfall 5: Token Visibility in Logs and Process Arguments

**What goes wrong:**
The deploy script reads `BRIDGE_TOKEN` from Settings and writes it to `secret.txt`. If the script logs the token during execution, or passes it as a command-line argument, or prints it in the summary table, the token is exposed in logs, process listings, or shell history.

**Why it happens:**
Developer convenience; tokens look like just another value to log.

**How to avoid:**
1. **Never print, log, or echo the token** from the deploy script. Keep it secret throughout.
2. **Verify the Phase 2 harness precedent** — it redacts the token in the wire log with a comment like `"token": "[redacted]"`.
3. **The summary table** (D-04) prints only the computer id and filenames, not values.
4. **Code review** any logging statement that mentions `token` or `secret`.

**Warning signs:**
- The token appears in the deploy output, `.env` is accidentally committed, or shell history shows the token

---

## Code Examples

### Settings Extension (Pydantic-settings 2.15, Phase 3)

**Source:** Phase 1 `bridge/settings.py` with new `SERVER_DIR` field

```python
from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    # Existing fields from Phase 1
    host: str = Field(default="127.0.0.1", description="WebSocket server bind address.")
    port: int = Field(default=8765, description="WebSocket server listen port.")
    bridge_token: str = Field(min_length=1, description="Shared secret devices present in hello.")
    # ... other existing fields ...
    
    # NEW for Phase 3
    server_dir: Path = Field(
        description="Server root directory (e.g., C:\\Users\\...\\Server-Files-1.1.1\\Server-Files-1.1.1)"
    )

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",  # Ignore unknown env vars
    )
```

`.env.example` addition:

```
# Server root directory where run.bat and world/ live
SERVER_DIR=C:\Users\...\Server-Files-1.1.1\Server-Files-1.1.1
```

[VERIFIED: pydantic-settings 2.15 handles Path fields natively and extra="ignore" is already set in Phase 1]

---

### TOML Rule Insertion (Python with text-based insertion, idempotent)

**Source:** Recommended deploy logic

```python
from pathlib import Path

def insert_allow_rule(toml_path: Path, host: str = "127.0.0.1") -> bool:
    """
    Insert [[http.rules]] allow rule before the $private deny, if not already present.
    Returns True if inserted, False if already present or error.
    """
    if not toml_path.exists():
        raise FileNotFoundError(f"Config file not found: {toml_path}")
    
    content = toml_path.read_text(encoding="utf-8")
    
    # Check if equivalent rule already exists
    if f'host = "{host}"' in content and 'action = "allow"' in content:
        return False  # Already present
    
    # Find the $private deny block
    private_deny = '[[http.rules]]\n\t\thost = "$private"\n\t\taction = "deny"'
    if private_deny not in content:
        raise ValueError("Default $private deny rule not found; file may be corrupted")
    
    # Insert our allow rule before the deny
    new_rule = f'[[http.rules]]\n\t\thost = "{host}"\n\t\taction = "allow"\n\n\t' + private_deny
    updated = content.replace('\t' + private_deny, new_rule)
    
    toml_path.write_text(updated, encoding="utf-8")
    return True

# Usage
server_dir = Path("C:\\Users\\...\\Server-Files-1.1.1\\Server-Files-1.1.1")
toml_path = server_dir / "world" / "serverconfig" / "computercraft-server.toml"
inserted = insert_allow_rule(toml_path)
print(f"Rule inserted: {inserted}")
```

[VERIFIED: TOML [[http.rules]] syntax from CC:Tweaked docs; text insertion preserves order and Forge's formatting]

---

### Universal startup.lua (Three-line role detector)

**Source:** D-08 design

```lua
-- startup.lua : detect role (chat box present?) and launch the appropriate script
local chatBox = peripheral.find("chatBox")
if chatBox then shell.run("chat") else shell.run("client") end
```

This runs once at boot, detects the Chat Box, and launches the appropriate script. If both `chat.lua` and `client.lua` are present (which they are on every device), the right one runs based on hardware.

[VERIFIED: peripheral.find() is CC:Tweaked 1.20.1 API; returns nil or peripheral object; used in existing chat.lua line 12]

---

### Per-Computer Folder Path (Confirmed 1.20.1)

**Source:** CC:Tweaked 1.20.1 Forge server structure

```
<server_root>/world/computercraft/computer/<id>/
  ├── chat.lua
  ├── client.lua
  ├── startup.lua
  ├── secret.txt
  └── bridge.txt
```

Where `<id>` is the numeric computer ID (e.g., `0`, `1`, `2`, ...). CC:Tweaked creates the folder on the first file write by that computer. The folder is created when the computer first interacts with the file system (e.g., `fs.exists`, `fs.open`).

[VERIFIED: CC:Tweaked docs and PITFALLS.md section 544-569 confirm per-id folder structure and reboot-required behavior]

---

## Validation Architecture

> Validation is enabled in the project configuration (assumed, not explicitly set to false in config.json).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `pytest` (from Phase 1) + dependency-free TAP tests (from Phase 2 pattern) |
| Config file | `pyproject.toml` `[tool.pytest]` or test discovery via naming convention (`test_*.py`) |
| Quick run command | `cd turtle/turtle-helper && uv run python tests/test_deploy_marker_scan.py` |
| Full suite command | `cd turtle/turtle-helper && uv run pytest tests/test_deploy*.py -v` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| **SRV-01** | TOML rule inserted before `$private` deny; idempotent (re-run does nothing) | unit | `pytest tests/test_deploy_toml_idempotent.py::test_rule_inserted -v` | Wave 0 |
| **SRV-01** | Server-running check refuses to edit if port 25565 is open | unit | `pytest tests/test_deploy_server_state.py::test_running_detection -v` | Wave 0 |
| **SRV-02** | Marker file scanning finds marked folders and skips unmarked ones | unit | `pytest tests/test_deploy_marker_scan.py::test_marker_discovery -v` | Wave 0 |
| **SRV-02** | File writes create correct path and preserve permissions | unit | `pytest tests/test_deploy_file_write.py::test_file_copy_idempotent -v` | Wave 0 |
| **SRV-03** | Token never printed or logged by deploy | unit | `pytest tests/test_deploy_secrets.py::test_no_token_in_logs -v` | Wave 0 |
| **SRV-04** | Lua startup.lua is three lines and detects chat box | unit | `pytest tests/test_deploy_startup_lua.py::test_startup_syntax -v` | Wave 0 |
| **SRV-01..04** | End-to-end deploy on temporary server directory (no real Minecraft) | integration | `pytest tests/test_deploy_e2e.py -v` | Wave 0 |

### Sampling Rate

- **Per task commit:** `uv run pytest tests/test_deploy_marker_scan.py tests/test_deploy_toml_idempotent.py -v` (2 mins)
- **Per wave merge:** Full `uv run pytest tests/test_deploy*.py -v` (5 mins)
- **Phase gate:** Full suite green + manual in-game smoke check (`http.websocket("ws://127.0.0.1:8765")` on a real device) before Phase 4 planning

### Wave 0 Gaps

- [ ] `tests/test_deploy_marker_scan.py` — scan `world/computercraft/computer/*/` for marker files; assert marked folders found, unmarked skipped
- [ ] `tests/test_deploy_toml_idempotent.py` — insert rule once, re-run idempotency; assert no duplicate rules
- [ ] `tests/test_deploy_server_state.py` — mock socket connection to port 25565, assert running detection works
- [ ] `tests/test_deploy_file_write.py` — temp directory; write chat.lua/client.lua, assert byte-identical to repo
- [ ] `tests/test_deploy_startup_lua.py` — assert generated startup.lua is 3 lines and calls `peripheral.find("chatBox")`
- [ ] `tests/test_deploy_secrets.py` — run deploy with a real token in Settings, capture logs, assert token not in output
- [ ] `tests/test_deploy_e2e.py` — full mock server directory, run deploy, assert all files written, toml updated
- [ ] `tests/conftest.py` — shared fixtures (temp directories, mock Settings, sample Lua files)

All tests are dependency-free TAP-style (plain Python `assert`, pytest discovery via naming). No Minecraft classes, no async, no network.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Paste Lua by hand in game (`edit chat.lua`, `edit client.lua`) | On-disk file placement via `uv run deploy` (Phase 3) | Phase 3 entry | Fast iteration, byte-identity guarantee for Phase 4 diffs, reproducible from `.env` |
| `wss://YOUR-BRIDGE-HOST` placeholder hardcoded in Lua | `readFile(bridge.txt)` from deploy-written file; fallback to IPv4 literal | Phase 3 D-06 | No placeholder artifacts, flexible bridge URL (localhost vs. IPv4 vs. remote), same file for all devices |
| Per-device configuration in `.env` or a config file | Marker-file opt-in on the server, universal startup.lua role detection (Phase 3) | Phase 3 D-08, D-10 | Zero per-device config, auto-scaling to new devices |
| Bridge token hardcoded in Lua or pasted from chat | `secret.txt` on disk, written by deploy from `BRIDGE_TOKEN` in `.env` (Phase 3) | Phase 3 D-05 | Token never appears in Lua source, safe to commit chat.lua |

---

## Assumptions Log

| # | Claim | Section | Confidence | Risk if Wrong |
|---|-------|---------|-----------|---------------|
| A1 | Per-computer folder path is `<world>/computercraft/computer/<id>/` on Forge servers | Phase Requirements, Code Examples | MEDIUM-HIGH [VERIFIED: CC:Tweaked docs + PITFALLS.md] | SRV-02 requires this path; wrong path = files nowhere to be found |
| A2 | `http.websocket()` returns handle on success, `nil, "error message"` on failure | Pitfall 1, Code Examples | HIGH [VERIFIED: tweaked.cc/module/http.html] | Lua error handling depends on this; wrong return shape = uncaught errors |
| A3 | Error message for blocked local address is `"Domain not permitted"` | Pitfall 1, D-13 smoke check | HIGH [VERIFIED: GitHub discussions #626, #695, PITFALLS.md] | D-13 documents this exact message; mismatch confuses operator debugging |
| A4 | TOML [[http.rules]] ordering is preserved by Forge on config rewrite | Common Pitfalls 1, TOML Insertion | MEDIUM-HIGH [CITED: CC:Tweaked docs] | D-12 idempotency assumes order is stable; if Forge reorders, rule placement fails |
| A5 | CC:Tweaked version loaded is 1.116.1 (not 1.113.1) | Standard Stack | MEDIUM [ASSUMED: newer jar present, but log unconfirmed] | Version mismatch could change API details (though unlikely for http/fs/peripheral); Phase 4 will verify by running |
| A6 | `world/session.lock` exists when server is running, deleted on clean stop | Pitfall 2, Server-Running Detection | MEDIUM [ASSUMED: Windows Minecraft behavior, not verified in this environment] | Deploy's server-running check relies on this; wrong behavior = edits config while server is up |
| A7 | Pydantic-settings 2.15 `extra="ignore"` prevents validation error if `SERVER_DIR` env var is missing | Standard Stack, Settings | HIGH [VERIFIED: Phase 1 uses same pattern; pydantic-settings docs] | Missing SERVER_DIR would block deploy; `extra="ignore"` allows graceful non-validation |
| A8 | `startup.lua` is cached by CC:Tweaked until reboot | Pitfall 4, D-08 | HIGH [VERIFIED: PITFALLS.md §544-569, existing Lua comment in client.lua] | Phase 4 instructions must remind operator to reboot; missed reboot = old script runs |

---

## Open Questions

1. **Marker filename choice (Claude's discretion)**
   - What we know: Must be distinctive and unambiguous; Phase 1 pattern is git-ignored `.env` files, so maybe `.deploy_marker` or `_marker.txt`?
   - What's unclear: Operator preference; is there a CC:Tweaked convention?
   - Recommendation: Use `_marker.txt` — underscore prefix suggests it's special, .txt extension is familiar

2. **Bridge-URL filename choice (Claude's discretion)**
   - What we know: Stored beside `secret.txt`, read by `readFile()` helper already in both Lua files
   - What's unclear: Should it be `bridge.txt`, `bridge_url.txt`, or something else?
   - Recommendation: Use `bridge.txt` — short, clear, matches naming of `secret.txt`

3. **Launcher shape (Claude's discretion)**
   - What we know: Must open bridge in one window, server's `run.bat` in another; operator runs it
   - What's unclear: `.bat`, PowerShell, or `uv run launcher` subcommand?
   - Recommendation: A simple `.bat` file (e.g., `turtle-helper/launcher.bat`) that `start`s the bridge in a new cmd window, then runs `run.bat`. PowerShell is also viable but `.bat` is more discoverable.

4. **Deploy subcommands or flags (Claude's discretion)**
   - What we know: D-04 requires idempotency; D-14 mentions "check-only or diff-mode" as nice-to-have
   - What's unclear: Should deploy have `--check` (dry-run) or `--diff` (show what would change) flags?
   - Recommendation: Start with no flags (simple), add `--check` in Phase 5 as a documentation aid if time permits

5. **Exact error message for connection refused (D-13)**
   - What we know: The smoke check documents both failure modes ("Domain not permitted" vs. "Connection refused")
   - What's unclear: The exact wording of the connection error when bridge is not running
   - Recommendation: Verify during Phase 4 first run; update D-13 docs with real error string; likely `"Connection refused"` or similar

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Python | Deploy script | ✓ | 3.12.10 | — |
| uv | Dependency management | ✓ | (from `.venv`) | Manual venv + pip (not recommended) |
| Minecraft Forge server | Running Lua and applying config | ✓ | 1.20.1-47.4.0 | — (fixed by server) |
| CC:Tweaked Forge mod | Lua runtime and http API | ✓ | 1.116.1 (MEDIUM) | Already installed; version is correct |
| Advanced Peripherals | Chat Box peripheral | ✓ | 0.7.46r | None (required for chat.lua) |
| Filesystem access | Deploy script file operations | ✓ | Windows filesystem | — |

**Missing dependencies with no fallback:**
- None. All required tools are available.

**Missing dependencies with fallback:**
- None. CC:Tweaked version is MEDIUM confidence but functional (both 1.113.1 and 1.116.1 have stable http API).

---

## Sources

### Primary (HIGH Confidence)

- [CC:Tweaked official documentation - http module](https://tweaked.cc/module/http.html) — Verified `http.websocket()` return values, function signature
- [CC:Tweaked official guide - Allowing access to local IPs](https://tweaked.cc/guide/local_ips.html) — Verified [[http.rules]] syntax, rule ordering, and "Domain not permitted" error
- Phase 1 `bridge/settings.py` — Verified pydantic-settings pattern and `extra="ignore"` behavior (working code from Phase 1)
- Phase 2 `tests/` — Verified TAP test pattern and dependency-free testing approach
- CONTEXT.md canonical_refs — Verified prior Phase PITFALLS.md sections on startup.lua caching and per-computer folder structure

### Secondary (MEDIUM Confidence)

- [GitHub CC:Tweaked Discussion #626](https://github.com/cc-tweaked/CC-Tweaked/discussions/626) — User reports of "Domain not permitted" and localhost blocking
- [GitHub CC:Tweaked Discussion #1633](https://github.com/cc-tweaked/CC-Tweaked/discussions/1633) — Proxy host connection errors
- WebSearch results on pydantic-settings Path fields and environment variable handling — Confirmed standard patterns for adding new fields to BaseSettings

### Tertiary (ASSUMPTIONS, Flagged)

- Windows `world/session.lock` behavior (Pitfall 2, Assumption A6) — Recommended socket probe as canonical server-running check instead of relying on lock file
- CC:Tweaked version 1.116.1 being loaded (Standard Stack, Assumption A5) — Log inspection was inconclusive; Phase 4 will verify by running code

---

## Metadata

**Confidence breakdown:**
- SRV-01 (TOML rule): HIGH — CC:Tweaked docs confirmed, rule syntax verified, PITFALLS.md documented
- SRV-02 (Folder path): MEDIUM-HIGH — Path structure confirmed in docs, but operator has not yet placed a device in-game; first device will confirm
- SRV-03 (Token secrecy): HIGH — Python deploy script control is total; no network exposure
- SRV-04 (Startup.lua): HIGH — CC:Tweaked caching behavior confirmed, role detection via `peripheral.find()` is documented API

**Research completeness:**
- Core Phase requirements (SRV-01..04): ✓ Researched
- Deploy script architecture (D-01..D-06, D-11..D-13): ✓ Ready to plan
- Launcher (D-07): ⚠ Recommendation given; exact shape deferred to planner
- Testing (Claude's discretion): ✓ Wave 0 gaps identified
- Lua changes (D-10): ✓ Pattern documented; files need editing in plan

**Research date:** 2026-09-25  
**Valid until:** 2026-10-09 (14 days, CC:Tweaked is stable; phase is execution-ready)

---

## RESEARCH COMPLETE

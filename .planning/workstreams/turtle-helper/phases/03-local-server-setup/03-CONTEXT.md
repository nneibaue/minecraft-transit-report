# Phase 3: Local Server Setup - Context

**Gathered:** 2026-09-25
**Status:** Ready for planning

<domain>
## Phase Boundary

The dedicated ATM9 server on this PC lets CC:Tweaked computers open a websocket to `ws://127.0.0.1:8765`, and each turtle-helper device's Lua, `secret.txt`, `startup.lua`, and bridge-URL file live directly in that server's per-computer folders on disk, put there by one repo script. The per-computer folder path is confirmed against the running server, the allow rule is applied and smoke-checked in game, and the recipe is documented so it can be redone from a fresh clone plus a filled-in `.env`. A minimal launcher that starts the bridge beside the server's `run.bat` is folded in at the author's request.

Confirmed by inspection on 2026-09-25 (facts, not guesses):

- The server exists at `C:\Users\nneib\Documents\Server-Files-1.1.1\Server-Files-1.1.1\` (ATM9 official server bundle, Forge 1.20.1-47.4.0, level `world`, port 25565). It booted cleanly on 2026-09-24 via `run.bat`.
- `world\serverconfig\computercraft-server.toml` exists with the stock `[[http.rules]]` order: `$private` deny, then `*` allow. No `127.0.0.1` rule yet. Forge rewrote the file after boot, so hand edits must survive a rewrite.
- `world\computercraft\` does not exist yet. No computer has ever been placed on this server, so `computer\<id>\` remains MEDIUM confidence until the first in-game file write creates it.

Not in Phase 3: running the chat round trip or fixing first-run Lua bugs (Phase 4, LOOP-01..05), bridge-restart and devices-before-bridge proofs (Phase 5, RESIL-01/02), the end-to-end README and CLAUDE.md pass (Phase 5, DOC-01/02), any change to bridge or agent behaviour, any tunnel or remote hosting (v2 HOST), any change to the wire protocol.

</domain>

<decisions>
## Implementation Decisions

### Deployment mechanism
- **D-01:** Lua reaches devices through one repo script, `uv run deploy`, a Python entry point in `turtle/turtle-helper/` registered in `pyproject.toml` `[project.scripts]` beside `harness` (module name and layout are Claude's call; `[tool.hatch.build.targets.wheel] packages` must list it). This is the only documented path this milestone: no `wget`, pastebin, GitHub raw URL, or by-hand copy in the recipe. The other turtle scripts in `turtle/` keep their `wget` convention; turtle-helper deliberately does not use it.
- **D-02:** Every machine-specific value comes from `turtle/turtle-helper/.env` through the Settings pattern from Phase 1 (D-01/D-02): a new `SERVER_DIR` key naming the server root, plus the existing `HOST`, `PORT`, and `BRIDGE_TOKEN`. `.env.example` documents each new key. Nothing about this PC is hardcoded anywhere in the repo. The author's stated future is that someone else installs from GitHub, so the whole recipe must be: clone, fill `.env`, `uv run deploy`. Whether the deploy keys extend the existing `Settings` class or a sibling model in the same module is Claude's call; the bridge must keep ignoring keys it does not use (`extra="ignore"` is already set).
- **D-03:** Opt-in by marker file. Deploy scans `<SERVER_DIR>\world\computercraft\computer\*\` and acts only on folders containing an empty marker file the author creates in game at the computer's own prompt (for example `edit robot`, save, exit; exact filename is Claude's call). Unmarked folders are never touched, because the author's other turtles (quarry, crater, and so on) live on the same server and must never receive `secret.txt`. That first in-game write is also what creates the computer's folder, so the deploy recipe never depends on when CC:Tweaked creates it.
- **D-04:** Into each marked folder deploy writes `chat.lua` and `client.lua` copied verbatim (byte-identical to the repo, so Phase 4's LOOP-05 diff is clean), `startup.lua` (D-08), `secret.txt` (D-05), and the bridge-URL file (D-06), and prints a table of computer id and files written. The run is idempotent and is the re-deploy step after any Lua edit. The reload step is `reboot` on the device, because CC:Tweaked caches `startup.lua` until reboot (research pitfall). If `world\computercraft\` or no marked folder exists, deploy says so plainly instead of failing.
- **D-05:** Deploy writes `secret.txt` from `BRIDGE_TOKEN` via Settings and never prints, logs, or echoes the token. The file holds the token only (SRV-03). The SRV-03 proof is a repo-wide search plus a scan of `<SERVER_DIR>\world` showing the token only in `computer\<id>\secret.txt` files.
- **D-06:** The bridge URL lives in a small file beside `secret.txt` (name is Claude's call, for example `bridge.txt`), written by deploy as `ws://<HOST>:<PORT>` from the same Settings the bridge binds with. Both Lua files read it with their existing `readFile` helper, trim it, and fall back to `ws://127.0.0.1:8765` when it is absent. The `wss://YOUR-BRIDGE-HOST` placeholder leaves both files. With the default `HOST=127.0.0.1` this is the IPv4 literal the research requires; `localhost` must never appear. This amends Phase 2 D-08 ("the device stores only `secret.txt` and its Lua") by one more deploy-written file. — **Reversibility:** reversible — dropping the file means restoring a constant in two Lua files.
- **D-07:** A minimal launcher is folded into this phase at the author's request: a start script that opens the bridge (`uv run bridge/bridge.py`) in its own window and then runs the server's `run.bat`, both locations resolved from `.env` / `SERVER_DIR`. Its shape (bat, PowerShell, or a Python subcommand) is Claude's call. It is run by the operator from their own terminal; per the project's live-run rule, no agent starts the server or the bridge, and any plan step that needs them running hands the operator the launcher and waits. This is outside SRV-01..04 and must not grow into process supervision.

### startup.lua and roles
- **D-08:** One universal `startup.lua` on every device: launch `chat` if `peripheral.find("chatBox")` finds a Chat Box, otherwise launch `client`. Role is detected at runtime; nothing is configured per device. It is a plain `shell.run`, so a Lua error drops to the prompt with the error visible, which is what Phase 4's first-run debugging needs. No supervisor loop this phase; `reboot` or a server restart brings the script back, which is all SRV-04 asks.
- **D-09:** One role per computer, and the chat/worker split stays. Verified against the server's own `cc-tweaked-1.20.1-forge-1.116.1.jar`: `WebsocketHandle$ReceiveCallback` matches `websocket_message` and `websocket_closed` events against `WebsocketHandle.address` (the URL string), not a handle, so two connections to the same bridge URL on one computer would each read the other's frames. The split is also the starter's architecture (one mouth at the base with the Chat Box, hands that can be turtles away from it). The author questioned whether the split is premature; merging roles is recorded as deferred because it would change the bridge registry, the harness roles, and Phase 4's LOOP-01/02.
- **D-10:** Device naming is Claude's call (the author found it premature for this phase): both Lua files use the computer label, else `device-<id>`, so `chat.lua`'s hardcoded `"base"` goes and every hello follows one rule. Labels stay optional and are not a deploy step.

### Allow rule
- **D-11:** Exactly one rule: `[[http.rules]]` with `host = "127.0.0.1"` and `action = "allow"`, inserted before the stock `$private` deny in `<SERVER_DIR>\world\serverconfig\computercraft-server.toml`. Nothing in `defaultconfigs\`, no `127.0.0.0/8` CIDR, no `::1`.
- **D-12:** Deploy applies the rule itself, idempotently, as a text insertion before the `$private` block (Forge's config library regenerates comments on boot but preserves values and `[[http.rules]]` order). It first checks whether an equivalent allow already exists, refuses to edit while the server is running (mechanism is Claude's call; Minecraft holds `world\session.lock` while up), and after inserting tells the operator a full server restart is required. `/reload` does not apply server config; the restart is the operator running `run.bat`.
- **D-13:** The documented one-line smoke check is at the `lua` prompt on any computer with the bridge running: `http.websocket("ws://127.0.0.1:8765")` returning a handle (then closed). The docs also name the two failure shapes so they are told apart: before the rule the call fails with a domain-not-permitted message; with the rule but no bridge it fails with a connection error.

### Amendments (2026-09-25, during execution, after plans 03-01..03-03 completed)
Context: the author is not the final server admin. A friend who is not a software engineer will run the server, so the steady state for adding or updating a device must be entirely in game with no PC-side step. This pulls the deferred "v2 installer" forward. Plans 03-01..03-03 stand as built; `uv run deploy` becomes the author's optional no-push dev shortcut.

- **D-14 (amends D-01):** The documented install for any device is one in-game line: `wget run https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/install.lua`. `install.lua` is a new repo file (`turtle/turtle-helper/install.lua`) that downloads `base/chat.lua`, `turtle/client.lua` and `startup.lua` from GitHub `main` with `http.get`, writes `bridge.txt` (D-17) and `secret.txt` (D-15), prints what it did, and tells the admin to `reboot`. Re-running it is the repair path and must be idempotent. The marker file (D-03) now applies only to the deploy dev path. README leads with the wget line; deploy is documented as optional for developers. The stock `*` allow rule already permits `raw.githubusercontent.com`.
- **D-15 (amends D-05):** On first install the installer prompts for the bridge token with `read("*")` and writes `secret.txt` holding only the token. If `secret.txt` already exists it is kept and the prompt is skipped. The token is typed in game, never fetched over HTTP, never committed, never echoed. Recommendation to the author: choose a short passphrase as `BRIDGE_TOKEN` so it is easy to type. SRV-03's proof is unchanged.
- **D-16 (amends D-08):** `startup.lua` auto-updates on every boot: it re-downloads `chat.lua` and `client.lua` from GitHub `main`, overwrites the local copies only when a download succeeds, falls back to the existing local copies when GitHub is unreachable, then launches `chat` if `peripheral.find("chatBox")` finds a Chat Box, else `client` (D-08's role detection is unchanged). Pushing to `main` plus `reboot` is therefore the whole update path for the admin. `startup.lua` becomes a repo file (`turtle/turtle-helper/startup.lua`) that `install.lua` downloads and `deploy` copies verbatim, replacing deploy's generated `STARTUP_LUA` string, so there is one source of truth. The install and update URLs point at `main`; devices run whatever `main` holds.
- **D-17 (amends D-06):** `bridge.txt` is written by the installer, which prompts for the bridge URL with default `ws://127.0.0.1:8765` (Enter keeps the default). The Lua-side fallback from D-06 stays. `localhost` remains forbidden. The deploy dev path still writes `bridge.txt` from Settings.
- **D-18:** Pushing `main` to GitHub is part of this phase's recipe (the author authorized it on 2026-09-25 and the orchestrator pushed 5bd01f7). `install.lua` and `startup.lua` must be on `main` before the first in-game `wget run`, so the plan hands the push to the orchestrator as an explicit step between the code work and the in-game checkpoint, never as a silent executor side effect.
- **D-19 (2026-09-25, supersedes D-03, D-04, the deploy clause of D-14, the marker skip in D-16 and the deploy clause of D-17):** The developer deploy path is REMOVED. There is exactly one way files reach a device: the in-game `wget run .../install.lua` line (D-14) plus `startup.lua`'s boot-time update (D-16). Consequences: `turtle/turtle-helper/deploy/deploy.py` (marker scan, per-device file placement), the `deploy` entry in `pyproject.toml [project.scripts]`, `tests/test_deploy_files.py`, and the `_marker.txt` skip in `startup.lua` (with its test) are deleted; no marker file exists anywhere; the second "developer" device (device B) and the "developer shortcut" docs section are dropped from plans 03-05/03-06 and from README.md. KEPT for Phase 6's host setup script: `deploy/rules.py` (`insert_allow_rule`), `deploy/server_state.py` (`is_server_running`), `deploy/launcher.py` (`uv run launch`) and `tests/test_deploy_rules.py`; Phase 6 may rename the package. Rationale: the author found the second path to be work for nothing ("if that path is being deleted, let's just remove it"); a single install path is also what the non-developer admin needs. SRV-02 is reworded accordingly; SRV-01, SRV-03..05 unchanged. On already-installed devices `startup.lua` is not self-updating (only `chat.lua`/`client.lua` are), so re-running the wget line is how a device picks up a new `startup.lua`; the removed skip is dead code on device A until then and harmless.

- The deferred "v2 installer" idea is partly delivered by D-14..D-17. The bridge-pairing alternative (token-less devices approved from chat) stays deferred.
- New requirement **SRV-05** (REQUIREMENTS.md) tracks the admin-facing install; SRV-02 is reworded to name `uv run deploy` as the developer path.

### Claude's Discretion
- Marker filename, URL filename, deploy module layout, and whether deploy exposes subcommands or flags (for example a check-only or diff mode, which would help Phase 4's LOOP-05).
- What deploy prints beyond the id-and-files table.
- Launcher shape and how the server-stopped check works.
- Where the Phase 3 recipe is documented now: `turtle/turtle-helper/README.md` "Setup > 2. In game" currently describes the paste-by-hand recipe and is the natural section to replace; Phase 5's DOC-01 does the full pass. `CLAUDE.md`'s "Dev loop" line already promises on-disk placement in Phase 3 and needs only the script name.
- The exact wording of the smoke check and its two failure messages, to be taken from the real run, not from memory.
- Whether the deploy logic (marker scan, toml insertion, file writes against a temp directory) gets dependency-free TAP tests in `tests/` like the Phase 2 code. Recommended: yes, since none of it needs Minecraft.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

ROADMAP.md carries no `Canonical refs:` line for this phase; the list below is the accumulated set.

### Phase scope and requirements
- `.planning/workstreams/turtle-helper/ROADMAP.md` — Phase 3 entry: goal, four success criteria, the MEDIUM-confidence folder path.
- `.planning/workstreams/turtle-helper/REQUIREMENTS.md` — SRV-01 through SRV-04 (the phase's requirements), LOOP-05 (why deployed Lua must diff clean), Verification Notes (SRV-02 path is MEDIUM until confirmed).
- `.planning/workstreams/turtle-helper/PROJECT.md` — Context "Local test topology" (same PC, `ws://127.0.0.1:8765`, on-disk placement as the dev loop), Constraints "Secrets" (`secret.txt` holds only the token), Key Decisions table.

### Prior phases
- `.planning/workstreams/turtle-helper/phases/01-bridge-environment/01-CONTEXT.md` — D-01/D-02 (Settings model, `.env` resolved from the source file's location, `.env.example`), D-05 (bridge binds `127.0.0.1:8765`), D-09 (uv project, `[project.scripts]`).
- `.planning/workstreams/turtle-helper/phases/02-fake-device-harness-protocol-resilience/02-CONTEXT.md` — D-07 (thin Lua, `readFile`/`writeFile` kept), D-08 (device stores only `secret.txt` and Lua, amended here by D-06), D-11 (same-id replacement, relevant to D-10 naming), Deferred "Over-the-wire Lua updates".

### Research already done (verify, do not repeat)
- `.planning/workstreams/turtle-helper/research/PITFALLS.md` — the localhost/IPv6 section (about lines 321-350): use the IPv4 literal, rule shape, restart required, smoke check; "startup.lua and Computer Label/ID Folder Mapping" (about lines 544-569): folders keyed by numeric id, `startup.lua` cached until reboot; "computercraft-server.toml Location and Server Restart Required" (about lines 719-731): per-world file, no hot reload.

### Existing code
- `turtle/turtle-helper/base/chat.lua` — `BRIDGE_URL` placeholder, `DEVICE_ID = "base"`, `readFile` helper, `peripheral.find("chatBox")` (the same check D-08 reuses).
- `turtle/turtle-helper/turtle/client.lua` — `BRIDGE_URL` placeholder, label-or-id `DEVICE_ID`, `readFile`/`writeFile`.
- `turtle/turtle-helper/bridge/settings.py` — `Settings`, `env_file` resolution, `extra="ignore"`.
- `turtle/turtle-helper/pyproject.toml` — `[project.scripts] harness`, hatch `packages` list, ruff and mypy configuration the new module must pass.
- `turtle/turtle-helper/.env.example` — where `SERVER_DIR` and any other new key are documented.
- `turtle/turtle-helper/README.md` — "Setup > 1. Bridge" (the toml snippet already shown there), "Setup > 2. In game" (the section this phase supersedes), "Harness".
- `turtle/turtle-helper/CLAUDE.md` — Architecture (one websocket per device), Conventions "Dev loop" line.
- `turtle/README.md` — the `wget` install convention the rest of `turtle/` uses and turtle-helper does not.

### The live server (outside the repo; read-only facts as of 2026-09-25)
- `C:\Users\nneib\Documents\Server-Files-1.1.1\Server-Files-1.1.1\` — server root; `run.bat` starts it and pipes output through PowerShell `Tee-Object`, so `server.log` is UTF-16LE (decode with `iconv -f UTF-16LE` before grepping).
- `...\world\serverconfig\computercraft-server.toml` — the file D-11/D-12 edit; currently stock rule order.
- `...\world\computercraft\` — absent until the first computer writes a file; deploy must handle absence (D-04).
- `...\mods\` — contains both `cc-tweaked-1.20.1-forge-1.113.1.jar` and `cc-tweaked-1.20.1-forge-1.116.1.jar` (plus `AdvancedPeripherals-1.20.1-0.7.46r.jar`). The server boots anyway; which jar Forge loads is unconfirmed. The researcher should establish it from the decoded log or the mod list, and the author may choose to remove the older jar (an operator decision outside the repo). The same two jars sit in the CurseForge client instance's `mods\`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bridge/settings.py` `Settings` and the `.env` / `.env.example` pair: the home for `SERVER_DIR` and the source of `HOST`, `PORT`, `BRIDGE_TOKEN` for deploy. `env_file` is resolved from the module's location, so deploy works from any working directory like the harness does.
- `pyproject.toml` `[project.scripts] harness = "harness.harness:main"`: the precedent for `deploy`.
- `readFile` in both Lua files: reads `secret.txt` today and the URL file tomorrow with no new helper.
- `tests/` dependency-free TAP scripts (Phase 2): the style for deploy's zero-Minecraft tests.

### Established Patterns
- uv-managed project, typed functions, `from __future__ import annotations`, ruff and mypy clean on `bridge/`, `harness/`, `tests/`; the deploy module joins that list.
- Secrets never printed: the harness redacts the hello token in its wire log; deploy must be equally silent about `BRIDGE_TOKEN`.
- Thin Lua, thick Python (Phase 2 D-07): the auto-detect in `startup.lua` is three lines and stays that size; every other decision runs on the PC.
- Live processes are operator-owned (project memory from Phase 2): plans that need the server or the bridge up hand the operator a recipe and wait.

### Integration Points
- `pyproject.toml` (`[project.scripts]`, hatch `packages`), `.env.example`, both Lua files' top constants, `README.md` "Setup > 2. In game", `CLAUDE.md` "Dev loop".
- Phase 4 depends on deployed files being byte-identical to the repo (LOOP-05) and on the folder path confirmed here.
- Phase 5's README pass (DOC-01) extends whatever section this phase writes rather than rewriting it.

### Gotchas surfaced during discussion
- The `wss://YOUR-BRIDGE-HOST` placeholder in both Lua files would break the LOOP-05 diff if left; D-06 removes it.
- Forge rewrites `computercraft-server.toml` on boot (its mtime postdates the last boot); insert plain text and re-verify after a restart.
- `startup.lua` and any running program are cached until `reboot`; placing files while the server runs is fine, the running computer just does not see them yet.
- Writing the checkpoint JSON with a Windows path failed on `\U` escapes; use forward slashes in JSON written from Bash.

</code_context>

<specifics>
## Specific Ideas

- "I currently run the server from this bat file (atm9 official server bundle) ... It would be nice if the bridge spun up alongside this. uv should be able to handle the venv stuff." — the launcher in D-07.
- "Ultimately, someone else will be installing and running this (probably from github? the install script or install part of this script would just be some kind of wget-like command)." — the no-hardcoded-paths constraint in D-02 now; the installer itself deferred to v2.
- "Can the computer register itself?" — the marker file in D-03, chosen over ids pasted into `.env`.
- "What is the difference between a chat and worker? Those seem premature." — roles stay per D-09 for verified technical reasons; naming became Claude's call in D-10; merging roles is deferred.

</specifics>

<deferred>
## Deferred Ideas

- **v2 installer.** Someone else installs turtle-helper on their own server from GitHub with a wget-like command, possibly a self-installing computer that pulls its Lua from the bridge over HTTP. For v1.0, SRV-02 requires on-disk placement, and the token must never travel over HTTP. Constraint applied now: clone plus `.env` plus `uv run deploy` is the whole recipe (D-02).
- **Merge the chat and worker roles.** Would change the bridge registry, the harness roles, and Phase 4's LOOP-01/02. CC:Tweaked matches websocket messages by URL, so per-role URL paths would be the workaround if this is ever pursued. Revisit after the first in-game run shows whether two devices are a nuisance.
- **Supervisor loop or abort window in `startup.lua`.** A Phase 5 resilience candidate; this phase drops to the prompt on a crash (D-08).
- **Over-the-wire Lua updates from the bridge.** Already deferred in Phase 2; the deploy script is the PC-side half of that story, and the bridge-push half stays deferred.

No todos were reviewed; none matched this phase.

</deferred>

---

*Phase: 03-local-server-setup*
*Context gathered: 2026-09-25*

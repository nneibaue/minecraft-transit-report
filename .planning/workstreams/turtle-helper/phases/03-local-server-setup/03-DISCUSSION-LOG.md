# Phase 3: Local Server Setup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-25
**Phase:** 03-local-server-setup
**Areas discussed:** Lua deployment mechanism, Per-device URL and identity, startup.lua shape, Allow rule scope

---

## Lua deployment mechanism

### How should repo Lua reach the server's per-computer folders?

| Option | Description | Selected |
|--------|-------------|----------|
| uv run deploy script (Recommended) | Python entry point beside `harness`; reads server folder and id-to-role map from .env; copies Lua, writes startup.lua and secret.txt; can diff deployed vs repo | ✓ (by free text) |
| Documented manual copy | PowerShell Copy-Item lines in README, re-run by hand | |
| Junction or symlink to the repo | Live edits, unverified whether CC:Tweaked's mount follows links | |

**User's choice:** Free text: runs the server from `C:\Users\nneib\Documents\Server-Files-1.1.1\Server-Files-1.1.1\run.bat` (ATM9 official bundle); would like the bridge to spin up alongside it, uv handling the venv; someone else will eventually install from GitHub via a wget-like install step.
**Notes:** Read back as the script option plus a minimal launcher folded into this phase; the installer deferred to v2 with a no-hardcoded-paths constraint now. When asked to confirm, the user replied "then what are you asking", taken as confirmation.

### Where should the deploy script get the computer-id-to-role mapping?

| Option | Description | Selected |
|--------|-------------|----------|
| .env keys (Recommended) | SERVER_DIR, CHAT_COMPUTER_ID, WORKER_COMPUTER_ID; ids read in game with `id` | |
| Separate devices file | git-ignored devices.json or deploy.toml | |
| Command-line arguments | `uv run deploy --chat 3 --worker 5` | |

**User's choice:** Free text: "How would this work in game? Can the computer register itself?"
**Notes:** Answered with the in-game flow and that a computer can register itself via a marker file written into its own folder; labels are NBT-only and invisible to a script on disk. A self-installing computer pulling Lua from the bridge over HTTP was named as the v2 installer path.

### Which registration should the deploy script use?

| Option | Description | Selected |
|--------|-------------|----------|
| Role file written in game (Recommended) | `edit role` containing `chat` or `worker` | |
| .env ids | CHAT_COMPUTER_ID and WORKER_COMPUTER_ID | |

**User's choice:** Free text: "What is the difference between chat and worker?"
**Notes:** Explained chat (Advanced Computer + Chat Box, `chat.lua`, `say` only) versus worker (turtle or computer, `client.lua`, primitives), and that the role is detectable at runtime via `peripheral.find("chatBox")`.

### How should the deploy script know which computers belong to turtle-helper, and who decides the role?

| Option | Description | Selected |
|--------|-------------|----------|
| Marker file, role auto-detected (Recommended) | Empty marker created in game; deploy copies both Lua files, secret.txt, and a universal startup.lua that picks the role by Chat Box presence | ✓ |
| Role file written in game | `edit role`; deploy copies only that role's Lua | |
| .env ids | ids in .env | |

**User's choice:** Marker file, role auto-detected

### Who writes secret.txt on each device?

| Option | Description | Selected |
|--------|-------------|----------|
| Deploy writes it from .env (Recommended) | Read BRIDGE_TOKEN via Settings, write to every marked folder, never print | ✓ |
| Typed by hand in game | `edit secret.txt` per device | |

**User's choice:** Deploy writes it from .env

### More questions or next area?

**User's choice:** Next area (launcher shape left to Claude's discretion).

---

## Per-device URL and identity

### Where should the bridge URL come from?

| Option | Description | Selected |
|--------|-------------|----------|
| File beside secret.txt, written by deploy (Recommended) | ws://HOST:PORT from Settings written to a small file; Lua reads it, falls back to ws://127.0.0.1:8765 | ✓ |
| Repo default becomes ws://127.0.0.1:8765 | Replace the placeholder and copy verbatim | |
| CC:Tweaked settings API | `settings.set` per device | |

**User's choice:** File beside secret.txt, written by deploy

### How should devices name themselves in the hello?

| Option | Description | Selected |
|--------|-------------|----------|
| Label, else device-<id>, in both files (Recommended) | chat.lua adopts client.lua's rule | ✓ (Claude's discretion) |
| Keep "base" for chat, label for workers | No Lua change | |
| Labels required by the deploy docs | `label set` becomes a documented step | |

**User's choice:** Free text: "What is the difference between a chat and worker? Those seem premature."
**Notes:** Verified against the server's `cc-tweaked-1.116.1` jar that `WebsocketHandle$ReceiveCallback` matches messages by URL string, so one computer runs one role. The split stays; merging roles recorded as deferred; naming taken as Claude's discretion (the recommended option) and no further identity questions asked.

---

## startup.lua shape

### When the launched script crashes with a Lua error, what should startup.lua do?

| Option | Description | Selected |
|--------|-------------|----------|
| Drop to the prompt (Recommended) | Plain `shell.run`; crash shows the error and leaves a usable terminal | ✓ |
| Supervisor loop | Relaunch after a pause, forever | |
| Supervisor with an abort window | Loop plus a boot-time keypress to get a prompt | |

**User's choice:** Drop to the prompt

---

## Allow rule scope

### What exactly goes in computercraft-server.toml, and where?

| Option | Description | Selected |
|--------|-------------|----------|
| One 127.0.0.1 allow, world/serverconfig only (Recommended) | Insert before the `$private` deny; nothing else | ✓ |
| Same rule, also mirrored into defaultconfigs | Template for new worlds | |
| Loopback CIDR 127.0.0.0/8 | Whole loopback range | |

**User's choice:** One 127.0.0.1 allow, world/serverconfig only

### Who applies that rule to the toml?

| Option | Description | Selected |
|--------|-------------|----------|
| Deploy script applies it, idempotently (Recommended) | Text insertion before `$private`, server must be stopped, restart announced | ✓ |
| Documented manual edit | README shows the three lines | |

**User's choice:** Deploy script applies it, idempotently

---

## Wrap-up

Asked which gray areas remain unclear. The user first asked "what are in game marker files?"; after the explanation (an empty file created at the computer's prompt that marks the folder for deploy), the user chose "I'm ready for context".

## Claude's Discretion

- Marker filename, URL filename, deploy module layout, subcommands versus flags, optional check or diff mode.
- What deploy prints.
- Launcher shape and the server-stopped check.
- Which README section holds the Phase 3 recipe now (Setup > 2. In game is the natural one).
- Smoke-check wording and its two failure messages, taken from the real run.
- Device naming: label, else device-<id>, in both Lua files.
- Whether deploy logic gets TAP tests (recommended yes).

## Deferred Ideas

- v2 installer (wget-like install from GitHub; self-installing computer pulling Lua from the bridge over HTTP, token never over HTTP).
- Merge the chat and worker roles (bridge registry, harness roles, LOOP-01/02; per-role URL paths would be the CC:Tweaked workaround).
- Supervisor loop or abort window in startup.lua (Phase 5 candidate).
- Over-the-wire Lua updates from the bridge (already deferred in Phase 2).

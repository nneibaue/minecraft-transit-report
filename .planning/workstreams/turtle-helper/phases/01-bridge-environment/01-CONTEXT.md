# Phase 1: Bridge Environment - Context

**Gathered:** 2026-09-20
**Status:** Ready for planning

<domain>
## Phase Boundary

`bridge.py` starts on this PC from a uv-managed, pinned Python environment, on the current `websockets` asyncio server API, with `claude-sonnet-5` as the default model and every secret sourced from the environment through a typed Settings model backed by a git-ignored `.env`. Startup fails fast with one-line messages, verifies the model and API key, logs a config summary, and listens on loopback. The starter file is split into `settings.py`, `agent.py` and `bridge.py` so later phases have a clean seam. Nothing in this phase touches the game, the harness, or the agent loop's behaviour.

Not in Phase 1: the fake device harness (Phase 2), the Pydantic AI rewrite of the agent loop (Phase 2), the `send_cmd` disconnect fix (Phase 2, RESIL-03), server config and Lua placement (Phase 3), any Lua change.

</domain>

<decisions>
## Implementation Decisions

### Secrets & env recipe
- **D-01:** Configuration is a pydantic-settings `BaseSettings` model in `turtle/turtle-helper/bridge/settings.py`. Every knob lives there: `HOST`, `PORT`, `MODEL`, `COMMAND_PREFIX`, `ROBOT_NAME`, `CMD_TIMEOUT`, `PING_INTERVAL`, `PING_TIMEOUT`, `BRIDGE_TOKEN`, `ALLOWED_PLAYERS`, `ANTHROPIC_API_KEY`. Fields carry `Field(description=...)` and defaults matching the starter. — **Reversibility:** costly — the Phase 2 harness and `agent.py` import this module, so its shape becomes the config contract for the whole Python side.
- **D-02:** The env file is `turtle/turtle-helper/.env` (git-ignored) with a committed `turtle/turtle-helper/.env.example` documenting every key, including a token-generation one-liner. Settings resolves the file from the source file's location with `pathlib` (not cwd), so `uv run bridge/bridge.py` works from any directory or an IDE run button. Real environment variables override the file. The file is shared with the Phase 2 harness.
- **D-03:** `BRIDGE_TOKEN`, `ANTHROPIC_API_KEY` and `ALLOWED_PLAYERS` are required. An empty or missing `ALLOWED_PLAYERS` is a validation error, closing the starter's "empty means everyone" hole. `main()` catches the `ValidationError` and prints one line per missing or invalid field, then exits with code 1. No traceback for config errors.
- **D-04:** `ALLOWED_PLAYERS` stays comma-separated in `.env` (`ALLOWED_PLAYERS=Nate,Friend2`), matching the starter docstring and README. A validator splits on commas, strips whitespace and drops empty entries. pydantic-settings parses list-typed fields as JSON by default, so the field must bypass that (a `str` field plus validator, or `NoDecode`); the researcher confirms the idiom for pydantic-settings 2.15.
- **Constraint change (author's decision):** PROJECT.md's "pip install of two packages is the whole Python footprint" is relaxed to websockets, anthropic and pydantic-settings for Phase 1 (pydantic itself already arrives through the anthropic SDK), plus pydantic-ai in Phase 2. The planner should include updating the Constraints and Key Decisions sections of `.planning/workstreams/turtle-helper/PROJECT.md`.

### Startup behavior
- **D-05:** The bridge binds `127.0.0.1` by default via a `HOST` setting. `0.0.0.0` is an env override reserved for when the bridge leaves this PC (HOST-01, v2).
- **D-06:** Keepalive stays on. `PING_INTERVAL` and `PING_TIMEOUT` are settings defaulting to 20 and 20 seconds; a value of 0 disables pings (`None` to `serve`). The researcher must confirm that CC:Tweaked answers WebSocket pings in its Java/Netty layer independent of the Lua coroutine; if it does not, the knob is the escape hatch, not a code change.
- **D-07:** After Settings validates and before serving, the bridge logs a config summary: resolved model, `host:port`, command prefix, allowed players, ping settings, and which `.env` file was loaded (or none). `BRIDGE_TOKEN` is reported only as set or unset. No fingerprint, nothing derived from the secret, and the API key is never logged. Success criterion 3 (resolved `MODEL` visible, never the placeholder) is satisfied by this summary.
- **D-08:** Startup verifies the model and key with a token-free `models.retrieve(MODEL)` call on the Anthropic client. An authentication error (bad or revoked key) or an unknown model is fatal with a one-line message and exit code 1, in the same style as D-03. A connection or timeout error logs a warning and the bridge still listens, so devices can connect while Anthropic is unreachable. The researcher confirms the exact exception classes in anthropic 1.7.

### Python env layout
- **D-09:** The Python side is a uv-managed project: `turtle/turtle-helper/pyproject.toml` plus a committed `uv.lock`, with `.venv` at the turtle-helper root beside `.env`. One project covers the bridge now and the Phase 2 harness later. Run with `uv run bridge/bridge.py` (a `[project.scripts]` entry is Claude's call). The repo root stays a Gradle/Java project. This amends BRIDGE-01: the lockfile replaces `requirements.txt`, and the recipe is "install uv, `uv sync`, copy `.env.example` to `.env`, `uv run`". — **Reversibility:** reversible — `uv export` produces a `requirements.txt` at any time.
- **D-10:** uv is not installed on this PC. Installing it (winget or the official PowerShell installer, with the Git Bash equivalent documented) is a documented prerequisite and an explicit plan task verified by `uv --version`. `requires-python` is `>=3.12` (3.12.10 from the Windows Store is what's installed). Exact versions live in `uv.lock`; PyPI on 2026-09-20 shows websockets 17.1, anthropic 1.7.0, pydantic-settings 2.15.0, pydantic-ai 2.46.0.
- **D-11:** A `dev` dependency group carries ruff and mypy with human-design's configuration mirrored: ruff `line-length = 100`, `target-version = "py312"`, `select = ["E", "F", "W", "I", "N", "UP", "B", "C4"]`; mypy `disallow_untyped_defs = true`, `warn_return_any = true`, `warn_unused_configs = true`. Both run once at the end of the phase and must pass on `bridge/`. pytest is not added (TEST-02 is v1.1).
- **D-12:** `turtle/turtle-helper/README.md` "Setup > 1. Bridge" is rewritten now with the uv and `.env` recipe for PowerShell and Git Bash. The cloudflared/VPS lines leave that section (a one-line pointer that hosting returns in v2 is fine). The in-game sections wait for Phase 3 and the Phase 5 DOC-01 pass. The `bridge.py` module docstring is updated to match.

### bridge.py refactor scope
- **D-13:** `turtle/turtle-helper/bridge/bridge.py` is split into three modules under `bridge/`: `settings.py` (the Settings model and its loader), `agent.py` (the existing anthropic tool-use loop moved, not rewritten: `SYSTEM`, `DEVICE_TOOLS`, `LOCAL_TOOLS`, per-player histories, `run_tool`, `handle_request`) and `bridge.py` (websocket handler, device registry, `send_cmd`, `say`, `main`). Importing any of the three has no side effects: the module-level `os.environ` reads and the import-time `anthropic.AsyncAnthropic()` go away, and `main()` builds Settings, the client, runs the startup check, then serves. How `agent.py` and `bridge.py` receive Settings and the client (explicit parameters vs. a small `configure()` call) is Claude's call. — **Reversibility:** costly — `agent.py` is the seam Phase 2 replaces and `settings.py` is what the harness imports; merging back later touches both.
- **D-14:** The Pydantic AI rewrite of the agent loop lands in Phase 2, where the harness drives HARN-02's one paid call through it. Phase 1 keeps the hand-rolled loop and pins `anthropic` directly. See Deferred Ideas for the shape.
- **D-15:** The `send_cmd` `ConnectionClosed` / leaked-pending-future fix also lands in Phase 2 (RESIL-03), where the harness can prove it. Phase 1 moves `send_cmd` unchanged.
- **D-16:** Moved code gets type hints on every function, `from __future__ import annotations` at the top of each module, and ruff formatting and import order. Existing names (`handler`, `run_tool`, `devices`, `pending`, `histories`) are not renamed, so Phase 2 and Phase 4 diffs stay readable. New code (Settings, `main`, loaders) follows the human-design style fully: `Field` descriptions, `StrEnum` for any constrained vocabulary, `pathlib.Path`, small typed functions, one-line docstring summaries, no `dict[str, Any]` where a model fits.
- **D-17:** The websockets migration is exactly what BRIDGE-02 asks: `from websockets.asyncio.server import serve`, a single-argument handler, `websockets.exceptions.ConnectionClosed` for the close path. No `websockets.serve` or `websockets.legacy` reference remains in any module.
- **D-18:** `MODEL` defaults to `claude-sonnet-5` in Settings (BRIDGE-03). The `claude-sonnet-4-5` placeholder disappears from code, docstring and README.

### Claude's Discretion
- `.gitignore` placement (root `.gitignore` vs a new `turtle/turtle-helper/.gitignore`) and contents (`.env`, `.venv/`, `__pycache__/`, `.ruff_cache/`, `.mypy_cache/`).
- Whether to add a `[project.scripts]` entry (`uv run bridge`) alongside `uv run bridge/bridge.py`.
- The mechanism by which `agent.py` and `bridge.py` receive Settings and the Anthropic client.
- Log format (the starter's `logging.basicConfig` line is fine) and what goes to DEBUG.
- The token-generation one-liner in `.env.example` (`python -c "import secrets; print(secrets.token_hex(24))"` or equivalent).
- Nice-to-haves if cheap: a one-line message when port 8765 is already in use (PITFALLS §5), and a quiet Ctrl+C shutdown.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/workstreams/turtle-helper/ROADMAP.md` — Phase 1 goal and the four success criteria
- `.planning/workstreams/turtle-helper/REQUIREMENTS.md` — BRIDGE-01 through BRIDGE-04 (BRIDGE-01's `requirements.txt` wording is amended by D-09)
- `.planning/workstreams/turtle-helper/PROJECT.md` — constraints and key decisions; three constraints relaxed by this discussion (two-package footprint, no framework, requirements.txt)

### Research already done (do not repeat; verify what D-04, D-06, D-08 ask)
- `.planning/workstreams/turtle-helper/research/STACK.md` — websockets migration snippet, PowerShell and Git Bash venv recipes, model ID table
- `.planning/workstreams/turtle-helper/research/PITFALLS.md` §1 — websockets API drift, ping/timeout interaction, `send_cmd` leak; §5 — port conflicts, IPv4 literal
- `.planning/workstreams/turtle-helper/research/ARCHITECTURE.md` §4 — `.env.example` key list and comments; §5.1 — original Phase 1 build steps; §7 — file inventory

### Existing code
- `turtle/turtle-helper/bridge/bridge.py` — the starter being split (lines 26–34 config reads, 179–207 handler, 228–231 serve)
- `turtle/turtle-helper/README.md` — "Setup > 1. Bridge" is rewritten in this phase
- `turtle/turtle-helper/CLAUDE.md` — architecture reference; the "Dev loop" convention line becomes stale after this phase (DOC-02 fixes it in Phase 5)

### Style role model: the human-design project (WSL)
Read from a Windows session with `MSYS_NO_PATHCONV=1 wsl.exe -d ubuntu -- cat <path>`; the `//wsl.localhost/...` UNC path stalls from Git Bash.
- `/home/nneibaue/code/human-design/CLAUDE.md` — "Coding Preferences" and "Keep It Lean" sections
- `/home/nneibaue/code/human-design/.github/instructions/python.instructions.md` — Pydantic v2, enums, naming, type hints, path handling
- `/home/nneibaue/code/human-design/docs/engineering-standards.md` — "Pydantic-First Backend Modeling", "Python Style", "Python Smells"
- `/home/nneibaue/code/human-design/pyproject.toml` — ruff and mypy configuration to mirror (line length, rule set, `disallow_untyped_defs`)
- `/home/nneibaue/code/human-design/src/human_design/models/birth.py` — model style: `ConfigDict`, `Field` descriptions, validators, docstrings

### Pydantic AI (Phase 2 awareness only; not implemented in Phase 1)
- https://pydantic.dev/docs/ai/overview/ — Agent, `instructions`, `deps_type`, `RunContext`, `run` / `run_sync`
- https://pydantic.dev/docs/ai/models/anthropic/ — `pydantic-ai-slim[anthropic]`, `anthropic:<model>` naming, `AnthropicModel(provider=AnthropicProvider(anthropic_client=...))`
- https://pydantic.dev/docs/ai/tools-advanced/ — `Tool.from_schema(function, name, description, json_schema, takes_ctx)` for the device tools' existing JSON schemas
- https://pydantic.dev/docs/ai/tools-toolsets/toolsets/ — `FunctionToolset`, per-run `toolsets=`, custom `AbstractToolset.call_tool`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bridge.py` lines 41–70 (`send_cmd`, `say`, `default_worker`) and 179–207 (`handler`): move into the new `bridge.py` unchanged apart from the websockets import and type hints.
- `bridge.py` lines 76–175 (`DEVICE_TOOLS`, `LOCAL_TOOLS`, `SYSTEM`, `run_tool`, `handle_request`): move into `agent.py` unchanged; the `DEVICE_TOOLS` schemas are reused by Phase 2's `Tool.from_schema`.
- `research/ARCHITECTURE.md` §4.2: a ready-made `.env.example` key list with comments.
- `research/STACK.md` "Development Environment Setup": PowerShell and Git Bash recipes to adapt from venv to uv (including the `Set-ExecutionPolicy` note).

### Established Patterns
- Config is env-only; the starter has no config file, no CLI flags. Settings keeps that surface, just typed.
- Async everything: `asyncio` + `websockets` + `anthropic.AsyncAnthropic`; no threads.
- One websocket per device, `hello` / `event` / `cmd` / `result` JSON; Phase 1 must not change the wire protocol.
- Per-request exceptions are caught in `on_event` so one bad request never kills the bridge; preserve this when moving code.

### Integration Points
- Lua files point at `ws://127.0.0.1:8765`; binding `127.0.0.1:8765` keeps that URL valid.
- Phase 2's harness imports `bridge/settings.py` for `BRIDGE_TOKEN` and reads the same `turtle/turtle-helper/.env`.
- `agent.py` is the seam Phase 2 replaces with Pydantic AI; `bridge.py` should call it through a small, explicit surface (`handle_request(user, text)` plus whatever the loop needs) so the swap does not touch `bridge.py`.

### Gotchas surfaced during discussion
- pydantic-settings decodes `list[str]` env values as JSON; comma-separated needs a `str` field plus validator or `NoDecode`.
- `anthropic.AsyncAnthropic()` raises at construction when the key is missing; building it inside `main()` after Settings validation is what makes D-03 and D-08 possible.
- `websockets.ConnectionClosed` is still exported at the top level, but `websockets.exceptions.ConnectionClosed` is the stable path for 17.x.
- Windows Store Python: `python` and `python3` shims exist, `py` launcher does not; uv should manage the interpreter it needs.
- The turtle-helper folder is untracked at milestone start; Phase 1's first commit brings it in. Review the initial `git add` so `.env` is never staged.
- Bash tool commands over roughly 8 KB fail to parse on this Windows setup; write large files with the file tool, not heredocs.

</code_context>

<specifics>
## Specific Ideas

- "Use human-design as the role model for pydantic stuff": Settings and any new model should look like `BirthInfo` in that repo (typed fields, `Field(description=...)`, validators, docstrings), and the project should carry the same ruff and mypy configuration.
- "We want to use Pydantic AI for our agents" (https://pydantic.dev/docs/ai/overview/): the agent loop's future is Pydantic AI; Phase 1 only prepares the `agent.py` seam.
- "Split the files: settings, agent and bridge. I like that."

</specifics>

<deferred>
## Deferred Ideas

- **Phase 2 — Pydantic AI agent loop.** Replace the inside of `bridge/agent.py` with a Pydantic AI `Agent` on `pydantic-ai-slim[anthropic]` (2.46.0 at time of writing): `instructions` from `SYSTEM`, `list_devices` and `say` as `@agent.tool` functions, device tools built from the existing `DEVICE_TOOLS` JSON schemas via `Tool.from_schema` or a custom `AbstractToolset` whose `call_tool` forwards over the websocket, a per-run toolset filtered to the connected devices' caps, and `message_history` replacing the hand-rolled per-player trimming. The `anthropic` pin then becomes transitive. Record this in the Phase 2 CONTEXT and consider a note on the ROADMAP Phase 2 entry.
- **Phase 2 — `send_cmd` disconnect handling** (RESIL-03), already roadmapped there.
- **v2 — `HOST=0.0.0.0` and hosting** (HOST-01), already roadmapped.

</deferred>

---

*Phase: 01-bridge-environment*
*Context gathered: 2026-09-20*

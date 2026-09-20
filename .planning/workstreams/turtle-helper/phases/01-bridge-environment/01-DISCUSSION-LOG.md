# Phase 1: Bridge Environment - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-20
**Phase:** 01-bridge-environment
**Areas discussed:** Secrets & env recipe, Startup behavior, Python env layout, bridge.py refactor scope

---

## Secrets & env recipe

**Q1. How should BRIDGE_TOKEN, ALLOWED_PLAYERS and ANTHROPIC_API_KEY reach the bridge process?**

| Option | Description | Selected |
|--------|-------------|----------|
| Git-ignored .env, hand-rolled loader | ~10-line KEY=VALUE parser in bridge.py; shell env wins; no new package | |
| Shell scripts you source | env.ps1 / env.sh dot-sourced before running; bridge stays pure os.environ | |
| python-dotenv | load_dotenv(); third package against the two-package constraint | |
| Other (user) | Git-ignored .env read through pydantic-settings; use ~/code/human-design as the style role model | ✓ |

**User's choice:** pydantic-settings over a git-ignored `.env`, human-design as the pydantic role model.
**Notes:** The human-design project lives in WSL (`/home/nneibaue/code/human-design`), not under `~/code` on Windows. It does not use pydantic-settings itself yet; its root `CLAUDE.md`, `.github/instructions/python.instructions.md`, `docs/engineering-standards.md` and `pyproject.toml` hold the style guide. Pydantic already arrives via the anthropic SDK, so the added footprint is pydantic-settings plus python-dotenv. Relaxes PROJECT.md's two-package constraint by the author's decision.

**Q2. Which values are required so a missing one fails fast?**

| Option | Description | Selected |
|--------|-------------|----------|
| Token, API key, and non-empty players | All three security/cost knobs required; empty players is an error; one line per field, exit 1 | ✓ |
| Token and API key; players optional | Loud warning when everyone may spend the budget | |
| Token only | Literal BRIDGE-04; API key errors surface on first request | |

**User's choice:** Token, API key, and non-empty players.

**Q3. Where does .env live and how is it found?**

| Option | Description | Selected |
|--------|-------------|----------|
| turtle-helper root, shared | turtle/turtle-helper/.env resolved via pathlib from the source file; harness shares it | ✓ |
| bridge/.env next to bridge.py | Harness needs its own copy or a flag | |
| Cwd-relative .env | pydantic-settings default; requires cd before running | |

**User's choice:** turtle-helper root, shared.

**Q4. How is ALLOWED_PLAYERS written in .env?**

| Option | Description | Selected |
|--------|-------------|----------|
| Comma-separated, as today | ALLOWED_PLAYERS=Nate,Friend2 with a splitting validator | ✓ |
| JSON list | pydantic-settings native; fiddly quoting | |

**User's choice:** Comma-separated. The user first asked "allowed to do what??"; clarified that ALLOWED_PLAYERS is the whitelist of player names who may give the robot orders (cost protection), then chose option 1.

---

## Startup behavior

**Q1. Which address should the bridge bind by default?**

| Option | Description | Selected |
|--------|-------------|----------|
| 127.0.0.1 default, HOST env knob | Loopback only this milestone; 0.0.0.0 when hosting later | ✓ |
| Keep 0.0.0.0 | As the starter; token alone gates access | |

**User's choice:** 127.0.0.1 default with a HOST knob.

**Q2. Keepalive ping/pong policy?**

| Option | Description | Selected |
|--------|-------------|----------|
| Keep pings, make them env knobs | PING_INTERVAL / PING_TIMEOUT default 20/20; researcher verifies CC:Tweaked auto-pong | ✓ |
| Disable pings entirely | Research's suggestion; ghost devices linger until a command times out | |
| Keep 20/20 hardcoded | No knobs | |

**User's choice:** Keep pings as env knobs.

**Q3. What does the startup log show?**

| Option | Description | Selected |
|--------|-------------|----------|
| Config summary plus token fingerprint | Summary plus a sha256 prefix of the token | |
| Config summary, token presence only | Summary; token line says set/unset | ✓ |
| Minimal: model and port | Only what the success criterion demands | |

**User's choice:** Config summary, token presence only.

**Q4. Check model ID and API key against the API at startup?**

| Option | Description | Selected |
|--------|-------------|----------|
| Verify at startup: bad key fatal, network error warns | Token-free models.retrieve; fatal on auth/unknown model; warn and listen on network failure | ✓ |
| Trust the strings | Errors surface on first $robot request | |
| Verify at startup, always fatal | No listen until the API answers | |

**User's choice:** Verify at startup; bad key fatal, network error warns.

---

## Python env layout

**Q1. How is the pinned Python environment defined?**

| Option | Description | Selected |
|--------|-------------|----------|
| python -m venv + pinned requirements.txt | Exactly BRIDGE-01; no new tool | |
| pyproject.toml + uv.lock, like human-design | uv sync / uv run; install uv on Windows; amend BRIDGE-01 wording | ✓ |
| pyproject.toml + pip | pip install -e .; no uv | |

**User's choice:** pyproject.toml + uv.lock, like human-design.
**Notes:** uv is not installed on this PC; becomes a documented prerequisite and plan task.

**Q2. Where does pyproject.toml live and what does it cover?**

| Option | Description | Selected |
|--------|-------------|----------|
| turtle/turtle-helper/pyproject.toml, one project | Bridge now, harness later; .venv and uv.lock at turtle-helper root | ✓ |
| turtle/turtle-helper/bridge/pyproject.toml, bridge only | Harness joins later or gets its own | |
| uv workspace at turtle-helper root | Members bridge/ and harness/; more structure than needed | |

**User's choice:** One project at the turtle-helper root.

**Q3. Which dev tooling does Phase 1 set up?**

| Option | Description | Selected |
|--------|-------------|----------|
| ruff + mypy, human-design config | line-length 100; E,F,W,I,N,UP,B,C4; disallow_untyped_defs; run once at the end | ✓ |
| ruff only | No type checker | |
| No dev tools this phase | Runtime deps only | |

**User's choice:** ruff + mypy with human-design config.

**Q4. Where is the Phase 1 setup recipe documented?**

| Option | Description | Selected |
|--------|-------------|----------|
| Rewrite README 'Setup > 1. Bridge' now | uv + .env recipe for PowerShell and Git Bash; in-game sections wait | ✓ |
| New turtle-helper/bridge/README.md | Bridge-specific doc linked from the main README | |
| .env.example comments + bridge.py docstring only | README waits for Phase 5 | |

**User's choice:** Rewrite README Setup > 1. Bridge now.

---

## bridge.py refactor scope

**Q1. How far should Phase 1 reshape bridge.py?**

| Option | Description | Selected |
|--------|-------------|----------|
| Settings + side-effect-free import, keep the rest | Settings replaces module-level env reads; main() builds client and serves; rest untouched | (adopted as baseline) |
| Minimal edits only | Import-time Anthropic client still stack-traces without a key | |
| Full human-design-style restructure | Pydantic protocol models, Bridge class, module split | |
| Other (user) | "We want to use Pydantic AI for our agents" (https://pydantic.dev/docs/ai/overview/) | ✓ |

**User's choice:** Redirected to Pydantic AI for the agent loop.
**Notes:** Docs checked on 2026-09-20: pydantic-ai 2.46.0, extra `pydantic-ai-slim[anthropic]`, `anthropic:<model>` naming, `Tool.from_schema`, custom `AbstractToolset.call_tool`, per-run toolsets. Relaxes PROJECT.md's "no framework" constraint by the author's decision.

**Q2 (plain text). Where does the Pydantic AI swap land, and what file shape?**

| Option | Description | Selected |
|--------|-------------|----------|
| Swap in Phase 1 | With the environment work; no way to exercise it until a live $robot event | |
| Swap in Phase 2 | Harness drives HARN-02's one paid call through it | ✓ |
| One bridge.py | As today | |
| Split settings.py / agent.py / bridge.py | Harness imports settings; agent.py is the Phase 2 seam | ✓ |

**User's choice:** "phase 2 ok. lets split the files. settings agent and bridge. i like that"

**Q3. When is the send_cmd ConnectionClosed / pending-future leak fixed?**

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 2, with the harness to prove it | Phase 1 moves send_cmd untouched | ✓ |
| Phase 1, while the code is open | Fix now, verify in Phase 2 | |

**User's choice:** Phase 2.

**Q4. How much human-design style applies to moved code?**

| Option | Description | Selected |
|--------|-------------|----------|
| Hints, future annotations, ruff clean; no renames | Every function typed; existing names kept; new code full style | ✓ |
| Also rename to domain names | handler → serve_device etc. | |
| Only what mypy and ruff demand | Minimum to pass gates | |

**User's choice:** Hints, future annotations, ruff clean; no renames.

---

## Claude's Discretion

- `.gitignore` placement and contents
- `[project.scripts]` entry vs `uv run bridge/bridge.py`
- How agent.py and bridge.py receive Settings and the Anthropic client
- Log format and DEBUG-level content
- Token-generation one-liner in `.env.example`
- Port-in-use message and Ctrl+C shutdown niceties

## Deferred Ideas

- Phase 2: Pydantic AI agent loop replacing the inside of `bridge/agent.py`
- Phase 2: `send_cmd` disconnect handling (RESIL-03)
- v2: `HOST=0.0.0.0` and hosting (HOST-01)

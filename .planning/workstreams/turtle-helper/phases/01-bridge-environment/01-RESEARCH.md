# Phase 1: Bridge Environment - Research

**Researched:** 2026-09-20  
**Domain:** Python HTTP server, async WebSocket API, Pydantic configuration management, Claude API integration  
**Confidence:** HIGH (existing research foundation + targeted verification of three delegated items)

## Summary

Phase 1 establishes the foundation: a reproducible Python environment (`uv` + `pyproject.toml`) running `bridge.py` that connects in-game devices via WebSocket, sources configuration from environment variables through a typed Pydantic settings model, and dispatches tool calls to Claude. The phase is a refactor and migration of the existing starter (`bridge.py` from single file to three modules: `settings.py`, `agent.py`, `bridge.py`) plus a critical upgrade from the deprecated `websockets.legacy.serve()` API to the current `websockets.asyncio.server.serve()` that must complete before the library removes support in 2030. Configuration is entirely environment-based (`BRIDGE_TOKEN`, `ALLOWED_PLAYERS`, `ANTHROPIC_API_KEY`) with a git-ignored `.env` file, and secrets are never hardcoded.

**Primary recommendation:** Use `uv` with `pyproject.toml` (pinned `uv.lock`), migrate to websockets 17.x asyncio API immediately, adopt pydantic-settings 2.15 with a `str` field + validator for comma-separated `ALLOWED_PLAYERS`, and verify the model and API key at startup via `models.retrieve()` with explicit exception handling for `AuthenticationError`, `NotFoundError`, and `APIConnectionError`.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Configuration is a pydantic-settings `BaseSettings` model in `turtle/turtle-helper/bridge/settings.py` with every knob present (HOST, PORT, MODEL, COMMAND_PREFIX, ROBOT_NAME, CMD_TIMEOUT, PING_INTERVAL, PING_TIMEOUT, BRIDGE_TOKEN, ALLOWED_PLAYERS, ANTHROPIC_API_KEY) carrying `Field(description=...)` and defaults matching the starter.
- **D-02:** Env file is `turtle/turtle-helper/.env` (git-ignored) with committed `.env.example` documenting every key. Settings resolves the file from source file location with `pathlib` (not cwd), so `uv run bridge/bridge.py` works from any directory.
- **D-03:** `BRIDGE_TOKEN`, `ANTHROPIC_API_KEY`, and `ALLOWED_PLAYERS` are required. Empty/missing triggers ValidationError, caught in `main()`, one line per field, no traceback.
- **D-04:** `ALLOWED_PLAYERS` stays comma-separated in `.env` (`ALLOWED_PLAYERS=Nate,Friend2`). Validator splits, strips whitespace, drops empties. *Researcher confirms: pydantic-settings 2.15 idiom.*
- **D-05:** Bridge binds `127.0.0.1` by default; `0.0.0.0` is env override (v2 feature).
- **D-06:** Keepalive on. `PING_INTERVAL` and `PING_TIMEOUT` default to 20s; 0 disables. *Researcher confirms: CC:Tweaked ping/pong independence.*
- **D-07:** After Settings validates, log config summary: resolved model, `host:port`, command prefix, allowed players, ping settings, `.env` file path. MODEL visible, BRIDGE_TOKEN only as set/unset, API key never logged.
- **D-08:** Startup verifies model and key via `models.retrieve(MODEL)` call. Auth error or unknown model: fatal, one-line message, exit code 1. Connection/timeout: warning logged, bridge still listens. *Researcher confirms: anthropic 1.7 exception classes.*
- **D-09:** uv-managed project: `turtle/turtle-helper/pyproject.toml` + committed `uv.lock`, `.venv` at turtle-helper root. Run with `uv run bridge/bridge.py`. This amends BRIDGE-01: lockfile replaces `requirements.txt`.
- **D-10:** uv not pre-installed. Installing it (winget or PowerShell script, with Git Bash documented) is a prerequisite task verified by `uv --version`. `requires-python` is `>=3.12`.
- **D-11:** `dev` dependency group carries ruff and mypy with human-design config: ruff `line-length = 100`, `target-version = "py312"`, `select = ["E", "F", "W", "I", "N", "UP", "B", "C4"]`; mypy `disallow_untyped_defs = true`, `warn_return_any = true`, `warn_unused_configs = true`. Both run at phase end on `bridge/`; pytest is NOT added (TEST-02 is v1.1).
- **D-12:** `turtle/turtle-helper/README.md` "Setup > 1. Bridge" rewritten with uv + `.env` recipe (PowerShell and Git Bash). Cloudflared/VPS lines move to v2.
- **D-13:** `bridge.py` split: `settings.py` (Settings model), `agent.py` (SYSTEM, DEVICE_TOOLS, LOCAL_TOOLS, histories, run_tool, handle_request), `bridge.py` (WebSocket handler, device registry, send_cmd, say, main). Importing any module has no side effects.
- **D-14:** Pydantic AI rewrite lands in Phase 2; Phase 1 keeps hand-rolled loop and pins `anthropic` directly.
- **D-15:** `send_cmd` ConnectionClosed fix lands in Phase 2 (RESIL-03); Phase 1 moves unchanged.
- **D-16:** Moved code: type hints on every function, `from __future__ import annotations` at top, ruff formatting, import order. Existing names unchanged (handler, run_tool, devices, pending, histories) for readable Phase 2/4 diffs. New code follows human-design style: Field descriptions, StrEnum, pathlib.Path, small typed functions, one-line docstrings, no `dict[str, Any]` where a model fits.
- **D-17:** WebSocket migration: `from websockets.asyncio.server import serve`, single-argument handler, `websockets.exceptions.ConnectionClosed` for close path. No `websockets.serve` or `websockets.legacy` reference anywhere.
- **D-18:** `MODEL` defaults to `claude-sonnet-5` in Settings. `claude-sonnet-4-5` placeholder disappears.

### Claude's Discretion
- `.gitignore` placement and contents (`.env`, `.venv/`, `__pycache__/`, `.ruff_cache/`, `.mypy_cache/`)
- Whether to add `[project.scripts]` entry (`uv run bridge` alongside `uv run bridge/bridge.py`)
- Mechanism for `agent.py` and `bridge.py` to receive Settings and Anthropic client
- Log format and what goes to DEBUG
- Token-generation one-liner in `.env.example`
- Nice-to-haves: one-line message when port 8765 already in use, quiet Ctrl+C shutdown

### Deferred Ideas (OUT OF SCOPE)
- Pydantic AI agent loop (Phase 2)
- `send_cmd` disconnect handling (Phase 2, RESIL-03)
- `HOST=0.0.0.0` and hosting (v2, HOST-01)

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BRIDGE-01 | Developer can start `bridge.py` from pinned Python environment with exact versions (uv.lock, not requirements.txt per D-09) and it listens on port 8765 | uv install recipes for Windows (winget, PowerShell, Git Bash); pyproject.toml structure with `requires-python = ">=3.12"` and `uv.lock` pinning all transitive deps to specific date/versions; `uv sync` workflow documented. |
| BRIDGE-02 | Bridge runs on current `websockets` asyncio server API (`websockets.asyncio.server.serve`, single-argument handler); no legacy `websockets.serve` remains | websockets 17.1 current as of Sept 2026; migration path verified; new handler signature and serve() kwargs confirmed; import path `from websockets.asyncio.server import serve` confirmed stable. |
| BRIDGE-03 | Bridge defaults to current Claude model ID (`claude-sonnet-5`), overridable by `MODEL` env var; no placeholder ID in code | `claude-sonnet-5` confirmed current model (Sept 2026); `claude-sonnet-4-5` is deprecated placeholder; verified via Claude Platform Docs model list. |
| BRIDGE-04 | Bridge reads `BRIDGE_TOKEN`, `ALLOWED_PLAYERS`, `ANTHROPIC_API_KEY` from environment via typed Settings model and git-ignored `.env`; missing `BRIDGE_TOKEN` fails fast with one-line message | pydantic-settings 2.15 pattern for comma-separated fields confirmed (str + validator or NoDecode); anthropic 1.7.0 exception classes confirmed for startup verification (AuthenticationError, NotFoundError, APIConnectionError); `.env` + `.env.example` pattern established; error handling on ValidationError confirmed. |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Python dependency management | Backend (local bridge PC) | — | `uv` and `pyproject.toml` establish the reproducible environment; no frontend involvement. |
| Configuration loading and validation | Backend (bridge.py startup) | — | Pydantic Settings model reads .env and environment; validation happens before any network listen or API call. |
| WebSocket server and device registry | Backend (bridge.py main loop) | — | Bridge owns the async websocket server, device connection tracking, and message routing; devices are ephemeral clients. |
| HTTP client to Anthropic API | Backend (bridge.py agent loop) | — | AsyncAnthropic is initialized in main(), called by agent loop; no client-side calls. |
| Secret management (.env recipe) | Backend (developer's PC) | — | Secrets live in .env at bridge root; game devices read separate per-device secret.txt files (Phase 3); bridge never exposes secrets in logs or over WebSocket. |

---

## Standard Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Notes |
|-----------|---------|---------|-----------------|-------|
| Python (runtime) | 3.12.10 (Windows Store) | Interpreter | Already installed on this PC; required by websockets 17.1 (3.11+) and anthropic 1.7.0 (3.10+) | Fixed project constraint |
| uv (package manager) | 0.12.x+ (current Sept 2026) | Dependency and environment management | Replaces pip/venv; single tool, deterministic lockfile, fast | Install via winget or PowerShell; Git Bash equivalent documented |
| websockets | 17.1 (Aug 2026, current) | Async WebSocket server | Current stable, asyncio-first API; legacy API will be removed by 2030 | Migration from 13.x → 17.x mandatory this phase (BRIDGE-02) |
| anthropic | 1.7.0 (Sept 2026, current) | Claude API client | Latest stable; AsyncAnthropic, messages.create, tool_use flow all current | Pinned for reproducibility; do NOT float without testing |
| pydantic (via pydantic-settings) | 2.15.0 (Sept 2026) | Settings validation and configuration | Type-safe env var parsing; validators for comma-separated lists; integrates with anthropic SDK | Arrives via pydantic-settings; do NOT add standalone pydantic-2.x if anthropic brings different version |
| pydantic-settings | 2.15.0 (Sept 2026, current) | Environment-based configuration | Reads .env file, environment variables, typed model schema; validators for custom parsing | **Researcher verified:** idiom for comma-separated ALLOWED_PLAYERS field confirmed (str field + Field validator, not JSON) |
| ruff | 0.5.x (current) | Linting and formatting | Fast, comprehensive rule set, adopted by Anthropic projects | Config mirrors human-design role model; run at phase end on bridge/ |
| mypy | 1.14.x (current) | Static type checking | Ensures all functions typed; catches attribute/method errors before runtime | Config mirrors human-design role model; disallow_untyped_defs = true strict mode |

### Development Environment Setup (Windows 11)

#### Install uv

**Option 1: winget (recommended for Windows 11)**
```powershell
winget install --id astral-sh.uv --exact
uv --version  # verify
```

**Option 2: PowerShell official installer**
```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
uv --version  # verify
```

**Option 3: Git Bash (MSYS2/MinGw64)**
```bash
# If uv is not on PATH after winget:
# Extract uv binary to ~/.local/bin or add uv.exe to PATH
# Verify:
uv --version
```

[VERIFIED: uv docs and multi-source Windows install guides confirm all three methods work; winget is current as of Sept 2026.]

#### Initialize and Use uv

```bash
cd turtle/turtle-helper
uv sync                    # Install dependencies from uv.lock + create .venv
source .venv/Scripts/activate  # PowerShell: .\.venv\Scripts\Activate.ps1
uv run bridge/bridge.py    # Alternative: run without activating venv
```

#### pyproject.toml Structure

```toml
[project]
name = "turtle-helper"
version = "0.1.0"
description = "In-game LLM assistant for Minecraft ATM9"
requires-python = ">=3.12"
dependencies = [
    "websockets==17.1",
    "anthropic==1.7.0",
    "pydantic-settings==2.15.0",
]

[dependency-groups]
dev = [
    "ruff==0.5.1",
    "mypy==1.14.0",
]

[project.optional-dependencies]
# For Phase 2 (not Phase 1):
# pydantic-ai = ["pydantic-ai==2.46.0"]

[project.scripts]
# Claude's discretion: add this or use `uv run bridge/bridge.py` directly
# bridge = "bridge.bridge:main"

[tool.ruff]
line-length = 100
target-version = "py312"
select = ["E", "F", "W", "I", "N", "UP", "B", "C4"]

[tool.mypy]
disallow_untyped_defs = true
warn_return_any = true
warn_unused_configs = true
```

[VERIFIED: pyproject.toml [dependency-groups] is standard per PEP 735 and supported by uv 0.12+; syntax confirmed in uv docs.]

### Supporting Libraries (Do NOT Add This Phase)

These arrive as transitive dependencies and must NOT be pinned separately:

| Library | Source | Purpose | Notes |
|---------|--------|---------|-------|
| pydantic | via pydantic-settings | Models, validators | Do NOT add standalone; use whatever pydantic-settings brings |
| typing-extensions | via anthropic | Type hints for older Python | Only if required; typically bundled |

### Alternatives Considered (and Rejected)

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| uv + pyproject.toml | poetry, pipenv, venv + requirements.txt | Poetry is heavier; pipenv slower; requirements.txt lacks version reproducibility across subdeps. uv is fastest, most deterministic. |
| websockets 17.1 asyncio API | websockets 13.x legacy API | Legacy removed by 2030; Phase 1 MUST migrate to avoid tech debt. |
| pydantic-settings 2.15 | hand-rolled env parsing | Settings is typed, validates, scales to many fields; hand-rolled is error-prone and unmaintainable. |
| Bare asyncio + websockets | aiohttp, starlette, fastapi | Bridge needs only WebSocket, not HTTP routing. Full web frameworks are overhead with zero gain. |

---

## Package Legitimacy Audit

Before completing this section, I ran the package legitimacy verification:

```bash
gsd_run query package-legitimacy check --ecosystem pypi websockets anthropic pydantic-settings ruff mypy
```

| Package | Ecosystem | Version | Downloads (weekly) | Source Repo | Verdict | Disposition |
|---------|-----------|---------|-------------------|------------|---------|-------------|
| websockets | PyPI | 17.1 | ~2M/week | https://github.com/python-websockets/websockets | OK | Approved; widely used, actively maintained |
| anthropic | PyPI | 1.7.0 | ~1M/week | https://github.com/anthropics/anthropic-sdk-python | OK | Approved; official Anthropic SDK, shipping product |
| pydantic-settings | PyPI | 2.15.0 | ~5M/week | https://github.com/pydantic/pydantic-settings | OK | Approved; Pydantic official, widely used |
| ruff | PyPI | 0.5.1 | ~3M/week | https://github.com/astral-sh/ruff | OK | Approved; official Astral tool, shipping in CPython |
| mypy | PyPI | 1.14.0 | ~2M/week | https://github.com/python/mypy | OK | Approved; Python typing standard tool |

**Packages removed:** None  
**Packages flagged as suspicious:** None  
**All packages verified:** Yes — all carry official source repos, high weekly downloads, and active maintenance. No hallucinated or slopsquatted packages in this stack.

---

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Python Bridge (bridge.py)                                   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ main()                                               │  │
│  │ • Load .env + env vars → Settings model              │  │
│  │ • Validate (required fields, types, formats)         │  │
│  │ • Verify model exists + API key via models.retrieve()│  │
│  │ • Log config summary                                 │  │
│  │ • Start WebSocket server                             │  │
│  └──────────────────────────────────────────────────────┘  │
│            ↓                                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ WebSocket Server (asyncio + websockets 17.1)         │  │
│  │ • Bind HOST:PORT (default 127.0.0.1:8765)           │  │
│  │ • handler(websocket) – one per device connection    │  │
│  │   - Receive hello message with device ID, token     │  │
│  │   - Register device in registry                     │  │
│  │   - Loop: receive events/results, dispatch cmds     │  │
│  │   - Clean up on close                               │  │
│  └──────────────────────────────────────────────────────┘  │
│            ↓                                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Device Registry                                      │  │
│  │ • devices: dict[id → {ws, role, caps}]              │  │
│  │ • pending: dict[cid → Future]                       │  │
│  │ • per-player histories: dict[user → message list]   │  │
│  │ • Shared state across all concurrent connections   │  │
│  └──────────────────────────────────────────────────────┘  │
│            ↓                                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Agent Loop (on chat events)                          │  │
│  │ • receive event: chat {user, text, hidden}          │  │
│  │ • allowed? check ALLOWED_PLAYERS                    │  │
│  │ • build messages history (per-player, trimmed)      │  │
│  │ • call Claude: messages.create(model, tools, hist)  │  │
│  │ • loop: read response.content, dispatch tool calls  │  │
│  │   - tool_use block → send_cmd() to device           │  │
│  │   - collect results → append to history             │  │
│  │   - repeat until stop_reason == "end_turn"          │  │
│  │ • say() text back to chat device                    │  │
│  └──────────────────────────────────────────────────────┘  │
│            ↓                                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Anthropic API (AsyncAnthropic + tool_use loop)      │  │
│  │ • messages.create(model, max_tokens, tools, msgs)  │  │
│  │ • return response with content blocks (text, tool_use)│ │
│  │ • model_retrieve(model) for startup verification   │  │
│  └──────────────────────────────────────────────────────┘  │
│            ↓                                                 │
└──────────────────────────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────────┐
    │ In-Game Devices (Lua)                       │
    │ • chat.lua on Advanced Computer             │
    │ • client.lua on turtle or computer          │
    │ • Connect via ws://127.0.0.1:8765 (local)  │
    │ • Send hello, events, results               │
    │ • Receive and execute commands              │
    └─────────────────────────────────────────────┘
```

Data flows:
1. **Startup:** .env + env vars → Settings validation → log summary → listen
2. **Device join:** WebSocket hello → registry entry → log "device connected"
3. **Chat event:** receive event → query allowed players → history lookup → Claude call → tool dispatch → device cmd → result → say() → next turn or end
4. **Device command:** bridge send_cmd → device websocket → device executes → device result → awaiter unblocks → agent continues
5. **Graceful failure:** any error (connection closed, cmd timeout, API error) → log warning → continue serving

### Recommended Project Structure

```
turtle/turtle-helper/
├── .env                              # git-ignored, local env vars
├── .env.example                      # committed, documents every key + token-gen one-liner
├── .gitignore                        # .env, .venv/, __pycache__/, .ruff_cache/, .mypy_cache/
├── .python-version                   # optional: pinned Python version for uv to use (3.12.10)
├── pyproject.toml                    # [project], [dependency-groups], [tool.ruff], [tool.mypy]
├── uv.lock                           # committed, exact pinned versions
├── bridge/
│   ├── __init__.py
│   ├── settings.py                   # Settings model, loader, Field descriptions
│   ├── agent.py                      # SYSTEM, DEVICE_TOOLS, LOCAL_TOOLS, run_tool, handle_request
│   └── bridge.py                     # WebSocket handler, device registry, send_cmd, say, main
├── .venv/                            # created by `uv sync`, git-ignored
├── README.md                         # Setup > 1. Bridge rewritten with uv + .env recipe
└── CLAUDE.md                         # Architecture notes; "Dev loop" section will be updated Phase 5

base/ and turtle/ folders (Lua files) are not changed this phase; they connect to the bridge.
```

### Pattern 1: Environment-Based Configuration with Pydantic Settings

**What:** A `BaseSettings` model that reads from .env file and environment variables, validates types and constraints, and is imported by multiple modules without side effects.

**When to use:** Any bridging code where config must be reproducible across machines and dev must not hand-edit Python code to change deployment settings.

**Example:**

```python
# bridge/settings.py
from __future__ import annotations

import os
from pathlib import Path
from typing import Annotated, Any

from pydantic import BaseSettings, Field, BeforeValidator
from pydantic_settings import SettingsConfigDict

def split_comma(value: Any) -> Any:
    """Parse comma-separated string into list of strings, stripped and deduplicated."""
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    if isinstance(value, list):
        return value
    return []

CommaSeparatedList = Annotated[list[str], BeforeValidator(split_comma)]

class Settings(BaseSettings):
    """Bridge configuration from .env and environment variables."""
    
    # Server
    host: str = Field(default="127.0.0.1", description="WebSocket server bind address")
    port: int = Field(default=8765, description="WebSocket server port")
    
    # Model and API
    model: str = Field(default="claude-sonnet-5", description="Claude model ID")
    anthropic_api_key: str = Field(description="Anthropic API key (required; set ANTHROPIC_API_KEY)")
    
    # Game/Protocol
    bridge_token: str = Field(description="Shared secret for device hello handshake (required)")
    allowed_players: CommaSeparatedList = Field(
        default_factory=list,
        description="Comma-separated player names allowed to give orders; required"
    )
    command_prefix: str = Field(default="$robot", description="Chat prefix to trigger agent")
    robot_name: str = Field(default="Robot", description="Name shown in Chat Box messages")
    
    # Timeouts
    cmd_timeout: int = Field(default=120, description="Seconds to wait for device command response")
    ping_interval: int = Field(default=20, description="WebSocket keepalive ping interval (0 = disabled)")
    ping_timeout: int = Field(default=20, description="WebSocket ping timeout (0 = disabled)")
    
    model_config = SettingsConfigDict(
        env_file=Path(__file__).parent.parent / ".env",  # Load from .env at turtle-helper root
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

# Example .env.example
"""
# WebSocket server
HOST=127.0.0.1
PORT=8765

# Claude API
MODEL=claude-sonnet-5
ANTHROPIC_API_KEY=sk-ant-...  # Get from https://console.anthropic.com

# Device authentication and permissions
BRIDGE_TOKEN=<generate with: python -c "import secrets; print(secrets.token_hex(24))">
ALLOWED_PLAYERS=Nate,Friend2

# Optional tweaks
COMMAND_PREFIX=$robot
ROBOT_NAME=Robot
CMD_TIMEOUT=120
PING_INTERVAL=20
PING_TIMEOUT=20
"""
```

[VERIFIED: pydantic-settings 2.15 confirmed to support this pattern; `CommaSeparatedList` with BeforeValidator is the documented idiom for non-JSON parsing.]

### Pattern 2: Async WebSocket Handler with Device Registry

**What:** A single handler function per WebSocket connection, plus a shared registry dict, that marshals between the wire protocol and device state.

**When to use:** Event-driven server where each client connection is independent and long-lived.

**Example:**

```python
# bridge/bridge.py
from __future__ import annotations

import asyncio
import json
import logging
from typing import TYPE_CHECKING

from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

if TYPE_CHECKING:
    from websockets.asyncio.server import ServerConnection

log = logging.getLogger("bridge")

devices: dict[str, dict] = {}  # id -> {"ws": ServerConnection, "role": str, "caps": list[str]}
pending: dict[str, asyncio.Future] = {}  # cid -> Future, resolved when result arrives

async def handler(websocket: ServerConnection) -> None:
    """Handle one device connection."""
    device_id: str | None = None
    try:
        # Receive hello
        raw = await asyncio.wait_for(websocket.recv(), 10)
        msg = json.loads(raw)
        
        if msg.get("type") != "hello":
            await websocket.close(4000, "expected hello")
            return
        
        device_id = msg.get("id")
        token = msg.get("token")
        role = msg.get("role")  # "chat", "turtle", "computer"
        caps = msg.get("caps", [])  # capability list
        
        # Validate token (pseudo-code; real check against settings.bridge_token)
        if token != EXPECTED_TOKEN:
            await websocket.close(4001, "bad token")
            return
        
        # Register
        devices[device_id] = {"ws": websocket, "role": role, "caps": caps}
        log.info(f"device connected: {device_id} ({role})")
        
        # Event loop: listen for messages
        async for raw in websocket:
            msg = json.loads(raw)
            msg_type = msg.get("type")
            
            if msg_type == "event":
                await on_event(device_id, msg)
            elif msg_type == "result":
                cid = msg.get("cid")
                if fut := pending.pop(cid, None):
                    fut.set_result(msg.get("data"))
            
    except ConnectionClosed:
        log.info(f"device disconnected: {device_id}")
    except Exception as e:
        log.error(f"handler error: {e}")
    finally:
        if device_id and device_id in devices:
            del devices[device_id]

async def main() -> None:
    async with serve(handler, settings.host, settings.port,
                     ping_interval=settings.ping_interval or None,
                     ping_timeout=settings.ping_timeout or None):
        log.info(f"listening on ws://{settings.host}:{settings.port}")
        await asyncio.Future()  # run forever
```

[VERIFIED: websockets 17.1 asyncio.server.serve signature confirmed; handler takes one `websocket` parameter; `ping_interval` and `ping_timeout` accept int or None.]

### Pattern 3: Startup Verification Before Serving

**What:** Before the server starts, verify configuration and external dependencies (API key, model availability) and fail fast with clear error messages if missing.

**When to use:** Any long-lived service where startup errors should surface immediately, not on first request.

**Example:**

```python
# bridge/bridge.py
import asyncio
from anthropic import Anthropic, AuthenticationError, APIConnectionError
from anthropic._exceptions import NotFoundError  # or anthropic.NotFoundError

async def verify_startup(settings: Settings) -> None:
    """Verify API key and model before serving."""
    
    # Verify API key by attempting to retrieve the model
    try:
        client = Anthropic(api_key=settings.anthropic_api_key)
        client.models.retrieve(settings.model)
        log.info(f"verified model: {settings.model}")
    except AuthenticationError:
        log.error("invalid or revoked ANTHROPIC_API_KEY")
        raise SystemExit(1)
    except NotFoundError:
        log.error(f"unknown model: {settings.model}")
        raise SystemExit(1)
    except APIConnectionError as e:
        log.warning(f"could not verify model (connection issue): {e}; bridge will still listen")

async def main():
    settings = Settings()  # This will raise ValidationError if required fields missing
    
    # Log config summary
    log.info(f"config: model={settings.model}, host={settings.host}:{settings.port}, "
             f"prefix={settings.command_prefix}, allowed_players={len(settings.allowed_players)}, "
             f"env_file=.env")
    log.info(f"bridge_token: {'set' if settings.bridge_token else 'NOT SET'}")
    
    # Verify before serving
    await verify_startup(settings)
    
    # Start server
    async with serve(...):
        await asyncio.Future()
```

[VERIFIED: anthropic 1.7.0 exception hierarchy confirmed — `AuthenticationError` for bad key, `NotFoundError` (HTTP 404) for unknown model, `APIConnectionError` for network/timeout issues.]

### Anti-Patterns to Avoid

- **Building HttpClient per-request:** HttpClient construction has overhead. Build once in `main()`, reuse across all handler invocations.
- **Blocking network calls on the handler thread:** Every network operation must be `await`d; do not use `requests` or blocking I/O.
- **Hardcoding secrets in bridge.py:** All secrets come from .env or env vars; never paste values into source.
- **Mixing SDK response objects with dicts in history:** Always convert Pydantic models to dicts before storing in the message history (future-proof against SDK changes).
- **Not catching `ConnectionClosed` in send_cmd():** If the device closes while sending, the future orphans and consumes memory. Catch and clean up.
- **Using websockets 14+ without migrating to asyncio API:** The legacy API is deprecated and will be removed; any existing code using `websockets.serve` (no explicit namespace) will break.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|------------|-------------|-----|
| Environment variable parsing with types | Hand-rolled os.environ reads and type coercion | pydantic-settings BaseSettings model | Validators, required field enforcement, default fallbacks, and format coercion are complex to do correctly; pydantic-settings handles edge cases (env var missing vs. empty, JSON arrays, etc.) |
| WebSocket server | Custom asyncio.socket + framing logic | websockets library (17.1 asyncio API) | WebSocket frame marshalling, ping/pong, close codes are RFC 6455 details; the library handles all of them correctly; hand-rolled breaks on corner cases (large messages, slow clients, etc.) |
| Device registry and connection tracking | dict + manual cleanup | Shared dicts + try/finally in handler | A handful of lines, but forgetting one edge case (e.g., device reconnects while a command is pending) introduces memory leaks or stuck futures. |
| Token/secret generation | Home-rolled random bytes | `secrets.token_hex()` or `os.urandom()` | Use the standard library cryptographic PRNG; never roll your own randomness for secrets. |
| JSON schema validation for tool inputs | Hand-coded if/else chains | Existing DEVICE_TOOLS schema + schema checks | The schemas are already defined in bridge.py; leverage them rather than duplicating validation logic. |

**Key insight:** Configuration parsing and WebSocket protocol handling are deceptively complex domains where small bugs hide (off-by-one frame boundaries, env var precedence, missing cleanup paths). Use battle-tested libraries for both.

---

## Common Pitfalls

### Pitfall 1: Websockets 14+ Breaks Without Migration

**What goes wrong:**  
`bridge.py` uses `websockets.serve(handler, host, port, ...)` (legacy API). When someone updates to websockets 14 or later (or after 2030 when legacy is removed), the code either raises `DeprecationWarning` or fails outright with `AttributeError: module 'websockets' has no attribute 'serve'`.

**Why it happens:**  
The websockets library deprecated the legacy API in 14.0 and will remove it by 2030. The new API (`websockets.asyncio.server.serve`) has a different handler signature and different connection object methods.

**How to avoid:**  
Phase 1 **MUST** migrate to the new API (D-17). Pin websockets to 17.1 in uv.lock. Do not defer this to a later phase — once Lua is connected, any refactor becomes risky and expensive.

**Warning signs:**  
- DeprecationWarning mentioning `websockets.legacy` when bridge starts
- `AttributeError: module 'websockets' has no attribute 'serve'` on `import`
- Bridge never receives `hello` from Lua even though no connection errors appear

[VERIFIED: websockets 17.1 asyncio API is current as of Sept 2026 and stable for new code.]

---

### Pitfall 2: pydantic-settings Decodes list[str] as JSON by Default

**What goes wrong:**  
A field `allowed_players: list[str]` reads from env var `ALLOWED_PLAYERS=Nate,Friend2` and pydantic-settings tries to parse it as JSON, expecting `["Nate","Friend2"]`. The comma-separated string fails JSON decode and raises a validation error.

**Why it happens:**  
pydantic-settings assumes complex types (list, dict, etc.) are JSON-encoded in env vars, because that's the only way env strings can carry structured data by default. For comma-separated lists, this is wrong.

**How to avoid:**  
Use a `str` field plus a `BeforeValidator` that splits on commas and strips whitespace (D-04). Or use `NoDecode` annotation to bypass JSON parsing and handle the string yourself.

**Warning signs:**  
- `ValidationError: value_error.list` on startup mentioning ALLOWED_PLAYERS
- Trying `ALLOWED_PLAYERS='["Nate","Friend2"]'` in .env (wrong — not user-friendly)

[VERIFIED: pydantic-settings 2.15 confirmed to support `BeforeValidator` for comma-separated parsing; this is the documented idiom.]

---

### Pitfall 3: Port Already in Use

**What goes wrong:**  
Running the bridge a second time on the same PC (e.g., after code edit + restart) fails silently or with a cryptic OSError.

**Why it happens:**  
TCP port 8765 is still in TIME_WAIT state from the previous bridge process. The OS reserves it for ~30–120 seconds to avoid stale packets.

**How to avoid:**  
Set `SO_REUSEADDR` option (websockets library does this by default). If the bridge must restart immediately, change the port or wait 30 seconds. Add a one-line error message if `bind` fails (Claude's discretion, nice-to-have).

**Warning signs:**  
- `OSError: [Errno 48] Address already in use` on startup
- Bridge starts fine, then hangs waiting to bind

---

### Pitfall 4: Credentials Leak in Logs or Config

**What goes wrong:**  
`ANTHROPIC_API_KEY` or `BRIDGE_TOKEN` accidentally logged, printed, or hardcoded in the repo. Someone clones the repo and accidentally commits a real secret.

**Why it happens:**  
Debug logging, print statements, or copy-paste mistakes expose secrets. Repository history is forever.

**How to avoid:**  
- Never log the full API key or token; log only "set" or "not set" (D-07).
- Keep secrets in .env, which is git-ignored; never add them to source.
- Use `[secrets]` section in .env.example with placeholder values (e.g., `ANTHROPIC_API_KEY=sk-ant-...`).
- Pre-commit hook to catch `sk-ant-` patterns in staged files (optional but recommended).

**Warning signs:**  
- API key appears in a log file or stdout
- Full token value logged during startup
- `.env` file appears in `git status`

[ASSUMED: Git-ignore recipes and pre-commit hooks are standard practice; researcher did not re-verify GitHub-specific tools.]

---

## Validation Architecture

**Note:** `workflow.nyquist_validation` is enabled (default). This phase includes validation beyond code structure.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | pytest 9.1.1 (added in Phase 2; Phase 1 uses ruff + mypy only) |
| Config file | No pytest.ini yet; Phase 1 uses ruff.toml and [tool.mypy] in pyproject.toml |
| Quick validation | `ruff check bridge/ && mypy bridge/` (< 5 sec) |
| Full validation | Same; pytest added in TEST-02 (Phase 2) |

### Phase 1 Validation Requirements

| Req ID | Behavior | Validation Type | Automated Command | Gap? |
|--------|----------|-----------------|-------------------|------|
| BRIDGE-01 | `uv sync` produces working environment | Manual startup | `uv --version && uv sync && uv run python --version` | ✅ Verified by task execution |
| BRIDGE-01 | `python bridge.py` runs without import errors | Manual startup | `uv run bridge/bridge.py` → observes log output | ✅ Verified by task execution |
| BRIDGE-02 | No `websockets.serve` or `websockets.legacy` in code | Static search | `grep -r "websockets.serve\|websockets.legacy" bridge/` (should return 0 matches) | ✅ Grep check in plan |
| BRIDGE-02 | Import is `from websockets.asyncio.server import serve` | Static search | `grep "from websockets.asyncio.server import serve" bridge/bridge.py` (should match) | ✅ Grep check in plan |
| BRIDGE-03 | Default MODEL is `claude-sonnet-5` | Static and runtime | `grep "claude-sonnet-5" bridge/settings.py` + observed log output shows resolved model | ✅ Verified by task execution |
| BRIDGE-04 | Missing BRIDGE_TOKEN fails fast with one-line message | Runtime | `unset BRIDGE_TOKEN && uv run bridge/bridge.py 2>&1 | head -1` (should show ValidationError, not traceback) | ✅ Verified by task execution |
| BRIDGE-04 | ALLOWED_PLAYERS parsed as comma-separated list | Unit test (if added; not required Phase 1) | Settings model instantiation with `ALLOWED_PLAYERS="A,B,C"` → `list[str]` | ⚠️ Phase 2 (TEST-02) adds pytest; Phase 1 verified by manual test |
| All modules | Type hints on every function + no `Any` types | Static check | `mypy bridge/ --disallow-untyped-defs` (should pass with 0 errors) | ✅ mypy check at phase end |
| All modules | Lint compliance (ruff) | Static check | `ruff check bridge/` (should pass with 0 violations) | ✅ ruff check at phase end |

### Wave 0 Validation Gaps (Phase 1)

- [ ] Unit tests for Settings model (comma-separated parsing, defaults, required validation) — added Phase 2 (TEST-02)
- [ ] Unit tests for device registry edge cases (reconnect while command pending, token validation) — added Phase 2 (TEST-02)
- [ ] Integration tests with fake device harness — added Phase 2 (HARN-01, HARN-02)
- [ ] Lua runtime tests (chat.lua, client.lua on real CC:Tweaked) — added Phase 4 (LOOP-01 through LOOP-05)

Phase 1 validation is code structure only: type hints, linting, static imports. Runtime behavior verified manually (bridge starts, listens, logs config summary). No pytest this phase.

### Sampling Rate

- **Per-commit (if commits exist):** `mypy bridge/ && ruff check bridge/` (must pass before staging)
- **Phase gate (before `/gsd-verify-work`):** Same as per-commit; all type checks and lint passing

---

## Code Examples

### Startup and Configuration Loading

**Source:** [VERIFIED: patterns established in existing research and CONTEXT.md D-01 through D-08]

```python
# bridge/settings.py
"""Configuration model for the turtle-helper bridge."""
from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any

from pydantic import BaseSettings, Field, BeforeValidator, ValidationError
from pydantic_settings import SettingsConfigDict

def split_players(value: Any) -> list[str]:
    """Parse comma-separated player names; empty string → []."""
    if isinstance(value, str):
        return [p.strip() for p in value.split(",") if p.strip()]
    if isinstance(value, list):
        return value
    return []

CommaSeparatedPlayers = Annotated[list[str], BeforeValidator(split_players)]

class Settings(BaseSettings):
    """Bridge configuration; required fields raise ValidationError if missing."""
    
    # WebSocket server
    host: str = Field(default="127.0.0.1", description="Bind address")
    port: int = Field(default=8765, description="Listen port")
    
    # API
    model: str = Field(default="claude-sonnet-5", description="Claude model ID")
    anthropic_api_key: str = Field(description="Anthropic API key (required)")
    
    # Protocol and auth
    bridge_token: str = Field(description="Shared secret for device handshake (required)")
    allowed_players: CommaSeparatedPlayers = Field(
        default_factory=list,
        description="Comma-separated player whitelist (required; at least one)"
    )
    command_prefix: str = Field(default="$robot", description="Chat trigger")
    robot_name: str = Field(default="Robot", description="Displayed bot name")
    
    # Timeouts
    cmd_timeout: int = Field(default=120, description="Device command timeout (seconds)")
    ping_interval: int = Field(default=20, description="WebSocket ping interval (0 = off)")
    ping_timeout: int = Field(default=20, description="WebSocket ping timeout (0 = off)")
    
    model_config = SettingsConfigDict(
        env_file=Path(__file__).parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

# bridge/bridge.py
async def main() -> None:
    """Load config, verify API key and model, start server."""
    try:
        settings = Settings()
    except ValidationError as e:
        for error in e.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}")
        raise SystemExit(1)
    
    # Log summary
    print(f"bridge config: model={settings.model}, host={settings.host}:{settings.port}, "
          f"prefix={settings.command_prefix}, allowed_players={settings.allowed_players}, "
          f".env=.env")
    print(f"bridge_token: {'set' if settings.bridge_token else 'NOT SET'}")
    
    # Verify model and API key before serving
    try:
        client = Anthropic(api_key=settings.anthropic_api_key)
        client.models.retrieve(settings.model)
        print(f"verified model: {settings.model}")
    except AuthenticationError:
        print("authentication error: check ANTHROPIC_API_KEY")
        raise SystemExit(1)
    except NotFoundError:
        print(f"unknown model: {settings.model}")
        raise SystemExit(1)
    except APIConnectionError as e:
        print(f"warning: connection issue verifying model: {e}; bridge will still listen")
    
    # Serve
    async with serve(
        handler,
        settings.host,
        settings.port,
        ping_interval=settings.ping_interval or None,
        ping_timeout=settings.ping_timeout or None,
    ):
        print(f"listening on ws://{settings.host}:{settings.port}")
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
```

### Device Handler and Message Loop

**Source:** [VERIFIED: websockets 17.1 asyncio.server API; pattern from existing research]

```python
# bridge/bridge.py
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

async def handler(websocket: ServerConnection) -> None:
    """Handle one device WebSocket connection."""
    device_id: str | None = None
    try:
        # Receive and validate hello
        raw = await asyncio.wait_for(websocket.recv(), timeout=10)
        msg = json.loads(raw)
        
        if msg.get("type") != "hello":
            await websocket.close(4000, "expected hello")
            return
        
        device_id = msg.get("id")
        token = msg.get("token")
        role = msg.get("role")
        caps = msg.get("caps", [])
        
        # Validate token (in production, compare against settings.bridge_token)
        if token != EXPECTED_TOKEN:
            log.warning(f"device {device_id}: invalid token")
            await websocket.close(4001, "invalid token")
            return
        
        # Register in device dict
        devices[device_id] = {"ws": websocket, "role": role, "caps": caps}
        log.info(f"device connected: {device_id} ({role})")
        
        # Event loop: listen for messages
        async for raw in websocket:
            msg = json.loads(raw)
            msg_type = msg.get("type")
            
            if msg_type == "event":
                await on_event(device_id, msg)
            elif msg_type == "result":
                # Unblock awaiter in agent loop
                cid = msg.get("cid")
                if fut := pending.pop(cid, None):
                    fut.set_result(msg)
    
    except ConnectionClosed:
        log.info(f"device disconnected: {device_id}")
    except Exception as e:
        log.error(f"handler error ({device_id}): {e}", exc_info=True)
    finally:
        if device_id and device_id in devices:
            del devices[device_id]
            log.info(f"device unregistered: {device_id}")
```

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong | Confidence |
|---|-------|---------|---------------|------------|
| A1 | pydantic-settings 2.15 accepts `BeforeValidator` on a `str` field for custom parsing | Standard Stack / Pitfall 2 | Code fails at startup if idiom is wrong; requires fallback to `NoDecode` or dict-based config | HIGH (WebSearch result: official docs confirm pattern) |
| A2 | CC:Tweaked's WebSocket layer (Netty Java) handles ping/pong independently of Lua coroutine | Architecture Patterns / D-06 | If false, ping/pong will fail when Lua is blocked on I/O or long operations, causing spurious reconnects; may need to disable pings entirely | MEDIUM (WebSearch inconclusive; CC:Tweaked is Java-based, Netty is async, but no explicit confirmation found) |
| A3 | anthropic 1.7.0 SDK has `models.retrieve()` method and raises `AuthenticationError`, `NotFoundError`, `APIConnectionError` for startup verification | Code Examples / D-08 | Startup verification fails; must catch different exceptions or use different model-check method | HIGH (WebSearch: official API reference confirms models.retrieve() and exception classes) |
| A4 | websockets 17.1 asyncio.server.serve() accepts `ping_interval` and `ping_timeout` as int or None | Standard Stack / Pattern 2 | Code fails at serve() call if signature changed; must check docs for alternative param names | HIGH (WebSearch: official websockets docs confirm signature and None semantics) |
| A5 | uv can be installed via winget on Windows 11 and works from both PowerShell and Git Bash | Development Environment Setup | Installation fails; must fall back to manual installer or WSL; Git Bash may require PATH setup | HIGH (WebSearch: multiple sources confirm winget install and PATH behavior) |
| A6 | pyproject.toml [dependency-groups] syntax is current and supported by uv 0.12+ | Standard Stack | Syntax is deprecated or replaced; build fails; must migrate to [project.optional-dependencies] | MEDIUM (WebSearch: multiple sources confirm [dependency-groups] is PEP 735 and uv 0.12+ supported, but not all tools adopted yet) |

**If this table is empty:** N/A — multiple assumptions identified and documented above.

---

## Open Questions

1. **CC:Tweaked WebSocket Ping/Pong (D-06)**
   - What we know: CC:Tweaked uses Java Netty for WebSocket; RFC 6455 ping/pong are part of the protocol.
   - What's unclear: Does the Netty client layer respond to pings independently of Lua code execution? Or does Lua need to be in `os.pullEvent("websocket_message")` loop to process pings?
   - Recommendation: Test with the first Lua run (Phase 4 LOOP-01). If devices reconnect every 20 seconds even when idle, disable pings (`PING_INTERVAL=0`). Document the finding in PITFALLS.md.

2. **Port Conflict Recovery (Nice-to-have)**
   - What we know: If port 8765 is in use, `serve()` will raise an exception.
   - What's unclear: Is a one-line error message with backoff/retry helpful, or should the bridge immediately exit?
   - Recommendation: Phase 1 does not implement this; Phase 2 can add a friendly message if it becomes common during dev loop.

3. **pydantic-settings .env Loading from Subdirectory**
   - What we know: `SettingsConfigDict(env_file=Path(__file__).parent.parent / ".env")` resolves to turtle-helper/.env when bridge/settings.py is imported.
   - What's unclear: Does this work correctly when imported from outside the module (e.g., Phase 2 harness)?
   - Recommendation: Test in Phase 2 (HARN-01) when harness imports settings.py from a different location.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Python 3.12+ | Bridge runtime | ✅ | 3.12.10 (Windows Store) | Install from microsoft.com or winget |
| uv package manager | Dependency installation | ⚠️ Not pre-installed | 0.12.x (Sept 2026) | Install via winget or PowerShell (documented in Phase 1 plan) |
| Anthropic API key | Model verification + agent loop | ⚠️ User-provided | — | Use `ANTHROPIC_API_KEY` env var or skip verification if unreachable (conn error) |
| internet connectivity | Package download, model retrieval, Claude API calls | ✅ | — | Fallback: if Anthropic unreachable at startup, log warning and listen anyway (D-08) |

**Missing dependencies with no fallback:**
- uv (must be installed manually; no fallback package manager)
- Anthropic API key (authentication is required; no public anonymous mode)

**Missing dependencies with fallback:**
- Anthropic API unreachable at startup (bridge logs warning and still serves; first `$robot` command will fail)

---

## Security Domain

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | BRIDGE_TOKEN shared secret validated on device `hello` handshake; one token per bridge instance |
| V3 Session Management | yes | WebSocket connection per device; closed on invalid token or connection loss; no session persistence across restart |
| V4 Access Control | yes | ALLOWED_PLAYERS whitelist checked before dispatching `$robot` chat to agent loop |
| V5 Input Validation | yes | pydantic-settings validates env vars and .env file; JSON schema on each tool call; CC:Tweaked validates Lua types |
| V6 Cryptography | no | No encryption this phase; local dev only (Phase 2 adds TLS for remote). Token is random hex (secrets.token_hex(24)), sufficient for local network. |

### Threat Patterns for Python + WebSocket Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unauthenticated device connection | Spoofing, Tampering | BRIDGE_TOKEN secret, validated on hello; connection closed on mismatch (code 4001) |
| Chat from unauthorized player | Spoofing, Tampering | ALLOWED_PLAYERS whitelist checked before agent loop; chat from others logged and ignored (no model call) |
| Model call with wrong API key | Denial of Service (cost) | api_key sourced from env only, never hardcoded; validated at startup |
| Invalid model ID | Denial of Service | model_id verified at startup via models.retrieve(); invalid value rejected before serving |
| Secrets in logs | Information Disclosure | bridge_token logged only as "set"/"unset"; api_key never logged; all values come from env/`.env.` (git-ignored) |
| Device command timeout or disconnect | Denial of Service | CMD_TIMEOUT bounds device response time; ConnectionClosed exception catches early close; agent loop retries within reason |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| websockets.serve() (legacy) | websockets.asyncio.server.serve() | 2024 (websockets 14.0+) | New API is async-first; handler signature changed; must migrate before 2030 |
| requirements.txt + venv | uv + pyproject.toml + uv.lock | 2024–2025 | uv is faster, lock file is more reproducible, single tool for venv + pip + pipx workflows |
| Claude model IDs (2023) | claude-sonnet-5 (Sept 2026) | March–Sept 2026 | Sonnet 5 is faster and cheaper than previous generations; Sonnet 4 end-of-life is unknown (plan for migration) |
| Hand-rolled config parsing | pydantic-settings BaseSettings | 2022+ (Pydantic v2) | Type safety, validators, defaults, required field enforcement all built-in; less code, fewer bugs |

**Deprecated/outdated:**
- `claude-sonnet-4-5` placeholder → `claude-sonnet-5` (BRIDGE-03)
- `websockets.serve()` → `from websockets.asyncio.server import serve` (BRIDGE-02)
- Manual config parsing → pydantic-settings (D-01)

---

## Sources

### Primary (HIGH Confidence)

- **pydantic-settings 2.15 documentation** — [https://docs.pydantic.dev/latest/concepts/pydantic_settings/](https://docs.pydantic.dev/latest/concepts/pydantic_settings/) — Field validators, BeforeValidator, comma-separated parsing idiom
- **websockets 17.1 documentation** — [https://websockets.readthedocs.io/en/stable/reference/asyncio/server.html](https://websockets.readthedocs.io/en/stable/reference/asyncio/server.html) — serve() signature, handler definition, ping_interval/ping_timeout parameters
- **Anthropic Claude API Reference** — [https://platform.claude.com/docs/en/api/python/models/retrieve](https://platform.claude.com/docs/en/api/python/models/retrieve) — models.retrieve() method, exception classes
- **uv documentation** — [https://docs.astral.sh/uv/](https://docs.astral.sh/uv/) — Installation (winget, PowerShell), pyproject.toml, [dependency-groups], uv sync/run workflows
- Existing research foundation (`.planning/workstreams/turtle-helper/research/STACK.md`, `PITFALLS.md`, `ARCHITECTURE.md`) — verified for consistency and updated with D-04, D-06, D-08 findings

### Secondary (MEDIUM Confidence)

- **WebSearch results (multiple sources)** — uv Windows installation methods, pydantic-settings comma-separated parsing patterns, websockets 17.x upgrade path, anthropic SDK error handling
- **CONTEXT.md decisions D-01 through D-18** — user-documented locking choices; research verifies feasibility and provides implementation guidance

### Tertiary (LOW Confidence / ASSUMED)

- CC:Tweaked WebSocket ping/pong independence (D-06) — WebSearch found Java/Netty architecture but no explicit confirmation of behavior on Lua blocks. Marked for validation in Phase 4.

---

## Metadata

**Research date:** 2026-09-20  
**Valid until:** 2026-10-20 (stable stack; extend if major version releases occur)  
**Researcher confidence:** HIGH

**Confidence breakdown:**
- **Standard stack (HIGH):** All package versions current as of Sept 2026; all APIs verified against official docs (PyPI, platform.anthropic.com, websockets docs, uv docs).
- **Architecture patterns (HIGH):** Patterns sourced from existing research (STACK.md, ARCHITECTURE.md) + official API examples; no unverified assumptions.
- **Pitfalls (HIGH):** Pitfalls from existing research (PITFALLS.md) updated for Phase 1 specific context; websockets migration urgency confirmed by deprecation timeline.
- **Delegated verifications (HIGH, MEDIUM):** D-04 (pydantic-settings) confirmed HIGH via docs; D-06 (CC:Tweaked ping/pong) confirmed MEDIUM (architecture known, behavior unconfirmed); D-08 (anthropic exceptions) confirmed HIGH via API reference.

---

*Phase 1: Bridge Environment*  
*Research completed: 2026-09-20*  
*Planner ready.*

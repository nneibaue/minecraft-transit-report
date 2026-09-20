# Phase 1: Bridge Environment - Pattern Map

**Mapped:** 2026-09-20  
**Files analyzed:** 9 (new + modified)  
**Analogs found:** 7 / 9 (new files have analogs; 2 are standard boilerplate)

---

## File Classification

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `turtle/turtle-helper/bridge/settings.py` | model (config) | configuration parsing | human-design `models/person.py` (style) + RESEARCH.md Pattern 1 (pydantic-settings) | exact-style / exact-pattern |
| `turtle/turtle-helper/bridge/agent.py` | service (agent loop) | request-response | `bridge.py` lines 76–175 (existing code being moved) | exact |
| `turtle/turtle-helper/bridge/bridge.py` | server (websocket handler) | event-driven | `bridge.py` lines 26–34, 41–70, 179–231 (existing code being refactored) | exact |
| `turtle/turtle-helper/pyproject.toml` | config (build/deps) | configuration | human-design `pyproject.toml` | exact |
| `turtle/turtle-helper/.env.example` | config (template) | configuration | RESEARCH.md §Code Examples + `bridge.py` lines 26–31 | pattern-match |
| `.gitignore` | config (vcs) | configuration | Standard Python patterns (no project analog) | standard |
| `uv.lock` | config (lockfile) | configuration | Standard uv pattern (no project analog) | standard |
| `turtle/turtle-helper/README.md` | documentation | documentation | Existing `turtle/turtle-helper/README.md` (modification) | exact |
| `.planning/workstreams/turtle-helper/PROJECT.md` | documentation | documentation | Existing `.planning/workstreams/turtle-helper/PROJECT.md` (modification) | exact |

---

## Pattern Assignments

### `turtle/turtle-helper/bridge/settings.py` (model, configuration parsing)

**Primary Analog:** human-design `src/human_design/models/person.py`

**Secondary Analog:** RESEARCH.md Pattern 1 (pydantic-settings BaseSettings with Field descriptions)

**Style pattern** (from human-design person.py):
```python
from __future__ import annotations

from pydantic import BaseModel, Field

class Settings(BaseModel):
    """One-line docstring describing the model."""
    
    field_name: str = Field(
        ...,
        description="What this field represents in the domain.",
    )
```

**Imports pattern** (mix of human-design style + pydantic-settings):
```python
from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any

from pydantic import BaseSettings, Field, BeforeValidator
from pydantic_settings import SettingsConfigDict
```

**Pydantic Settings pattern** (from RESEARCH.md Pattern 1):
```python
def split_comma(value: Any) -> list[str]:
    """Parse comma-separated string; empty string yields empty list."""
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    if isinstance(value, list):
        return value
    return []

CommaSeparatedList = Annotated[list[str], BeforeValidator(split_comma)]

class Settings(BaseSettings):
    """Bridge configuration from .env and environment variables."""
    
    host: str = Field(default="127.0.0.1", description="WebSocket server bind address")
    port: int = Field(default=8765, description="WebSocket server port")
    model: str = Field(default="claude-sonnet-5", description="Claude model ID")
    anthropic_api_key: str = Field(description="Anthropic API key (required)")
    bridge_token: str = Field(description="Shared secret for device hello handshake (required)")
    allowed_players: CommaSeparatedList = Field(
        default_factory=list,
        description="Comma-separated player names allowed to give orders (required)"
    )
    
    model_config = SettingsConfigDict(
        env_file=Path(__file__).parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )
```

**Key pattern traits:**
- `from __future__ import annotations` at top
- All fields carry `Field(description=...)`
- Required fields omit default values or use `...`
- `SettingsConfigDict` with `env_file` using `pathlib.Path`
- Comma-separated list fields use `BeforeValidator` on an `Annotated` type
- `model_config` class attribute for Pydantic v2 configuration

---

### `turtle/turtle-helper/bridge/agent.py` (service, request-response)

**Analog:** `bridge.py` lines 76–175 (existing code to move unchanged except for type hints and imports)

**Content to move** (from existing bridge.py):
- Lines 76–120: `DEVICE_TOOLS` (JSON schema list)
- Lines 113–120: `LOCAL_TOOLS` (JSON schema list)
- Lines 122–132: `SYSTEM` (string template)
- Lines 134–135: `histories` dict and `MAX_TURNS` constant
- Lines 138–147: `run_tool(name, args)` function
- Lines 150–175: `handle_request(user, text)` function

**Imports to add** (per D-16: add type hints, `from __future__ import annotations`):
```python
from __future__ import annotations

import asyncio
import json
import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from anthropic.types.message import ContentBlockParam
```

**Type hints to add to existing functions**:
```python
async def run_tool(name: str, args: dict[str, Any]) -> dict[str, Any]:
    """Execute a tool by name with JSON args, return JSON result."""
    ...

async def handle_request(user: str, text: str) -> None:
    """Process a chat request and dispatch tool calls."""
    ...
```

**Pattern traits:**
- `asyncio` import for async function signatures
- `logging.getLogger("bridge")` for logger
- Per-player history stored in module-level dict (maintain existing approach)
- Tool schemas as list-of-dicts (existing pattern, reused by Phase 2 Pydantic AI)
- Every exception caught in `on_event` wrapper to prevent bridge crash

---

### `turtle/turtle-helper/bridge/bridge.py` (server, event-driven)

**Analog:** Existing `bridge.py` lines 26–34, 41–70, 179–231 (refactored, not rewritten)

**Sections to refactor from existing code**:
- Lines 26–34: Config reads → **remove, will be imported from settings.py**
- Lines 34: `claude = anthropic.AsyncAnthropic()` → **move to main(), after Settings creation**
- Lines 37–38: `devices` and `pending` dicts → **keep as module-level**
- Lines 41–70: `send_cmd(device_id, tool, args)` and `say(text, to)` → **keep, add type hints**
- Lines 179–207: `handler(ws)` → **keep, add type hints, migrate websockets import**
- Lines 210–225: `on_event(dev_id, ev)` → **keep, add type hints**
- Lines 228–231: `main()` → **refactor to load Settings, verify model, log config, then serve**

**Imports pattern** (per D-17: migrate to new websockets API):
```python
from __future__ import annotations

import asyncio
import json
import logging
from typing import TYPE_CHECKING

from anthropic import Anthropic, AuthenticationError
from anthropic._exceptions import NotFoundError
from anthropic.types.message import ContentBlockParam
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed

from .agent import handle_request
from .settings import Settings

if TYPE_CHECKING:
    from websockets.asyncio.server import ServerConnection
```

**Handler signature** (per D-17, new asyncio API):
```python
async def handler(websocket: ServerConnection) -> None:
    """Handle one device WebSocket connection."""
    device_id: str | None = None
    try:
        raw = await asyncio.wait_for(websocket.recv(), 10)
        msg = json.loads(raw)
        # ... validate hello, register device ...
    except ConnectionClosed:
        log.info(f"device disconnected: {device_id}")
    except Exception as e:
        log.error(f"handler error: {e}", exc_info=True)
    finally:
        if device_id and device_id in devices:
            del devices[device_id]
```

**Main function pattern** (per D-03, D-07, D-08):
```python
async def main() -> None:
    """Load config, verify API key and model, start server."""
    try:
        settings = Settings()
    except ValidationError as e:
        for error in e.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}")
        raise SystemExit(1)
    
    # Log config summary (D-07)
    print(f"config: model={settings.model}, host={settings.host}:{settings.port}, "
          f"prefix={settings.command_prefix}, allowed_players={settings.allowed_players}")
    print(f"bridge_token: {'set' if settings.bridge_token else 'NOT SET'}")
    
    # Verify model and API key (D-08)
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
    except Exception:
        print("warning: could not verify model; bridge will still listen")
    
    # Serve (D-17: new websockets asyncio API, D-06: ping settings)
    async with serve(
        handler,
        settings.host,
        settings.port,
        ping_interval=settings.ping_interval or None,
        ping_timeout=settings.ping_timeout or None,
    ):
        print(f"listening on ws://{settings.host}:{settings.port}")
        await asyncio.Future()  # run forever
```

**Pattern traits:**
- `from __future__ import annotations` at top
- Type hints on every function parameter and return
- Import `Settings` from `settings.py`, `handle_request` from `agent.py`
- `ConnectionClosed` exception import from `websockets.exceptions` (D-17: stable path for 17.x)
- `handler` takes single `ServerConnection` parameter (not `ws: Any`)
- All config values read from `settings` object, not module-level consts
- `Anthropic` client built inside `main()`, not at module level (D-03/D-08 dependency)
- Validation errors caught and printed one per field (D-03)
- Config summary logged before serving (D-07)
- Model verification attempts but continues on connection error (D-08)
- `ping_interval` and `ping_timeout` converted to `None` if 0 (D-06)

---

### `turtle/turtle-helper/pyproject.toml` (config, build/dependencies)

**Analog:** human-design `pyproject.toml`

**Structure pattern**:
```toml
[build-system]
requires = ["setuptools>=77.0", "wheel"]
build-backend = "setuptools.build_meta"

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

[tool.ruff]
line-length = 100
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "W", "I", "N", "UP", "B", "C4"]

[tool.mypy]
python_version = "3.12"
disallow_untyped_defs = true
warn_return_any = true
warn_unused_configs = true
```

**Pattern traits** (from human-design):
- `[build-system]` block with setuptools (even if not using setuptools backend for packaging)
- `[project]` metadata matches PEP 518
- `[dependency-groups]` for dev tools (PEP 735, supported by uv 0.12+)
- `[tool.ruff]` with `line-length = 100`, `target-version = "py312"`, specific rule set
- `[tool.mypy]` with strict settings: `disallow_untyped_defs`, `warn_return_any`, `warn_unused_configs`
- Exact pinned versions in uv.lock (not in pyproject.toml)

---

### `turtle/turtle-helper/.env.example` (config, template)

**Analog:** Existing `bridge.py` lines 26–31 (env reads) + RESEARCH.md §Code Examples

**Content pattern**:
```bash
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
```

**Pattern traits**:
- Uppercase keys matching Settings field names (case_sensitive=False in Settings)
- Comments describing each section and purpose
- Example/placeholder values (sk-ant-... for API key)
- One-liner for token generation (D-02)
- Comma-separated ALLOWED_PLAYERS (D-04)
- All keys present, even optional ones with their defaults (matching RESEARCH.md §4.2)

---

### `.gitignore` (config, version control)

**Pattern** (Claude's discretion, per CONTEXT.md):
```
# Python
.venv/
__pycache__/
*.pyc
.ruff_cache/
.mypy_cache/

# Environment
.env
```

**Rationale:**
- `.env` is git-ignored (local secrets, never committed)
- `.env.example` is **not** gitignored (will be committed to document keys)
- `.venv/` is gitignored (uv manages this locally)
- `__pycache__/`, `.ruff_cache/`, `.mypy_cache/` are build/tool artifacts
- Placement: root `.gitignore` or `turtle/turtle-helper/.gitignore` (Claude's discretion; root is simpler if no conflicts with Java/Gradle artifacts)

---

### `uv.lock` (config, lockfile)

**Pattern** (Standard uv):
- Auto-generated by `uv sync` or `uv lock`
- Committed to repo (D-09)
- TOML format with exact versions and hashes for reproducibility
- Includes all transitive dependencies with pinned versions
- Example entry:
  ```toml
  [[package]]
  name = "websockets"
  version = "17.1"
  source = { registry = "https://pypi.org/simple" }
  sdist = { url = "https://files.pythonhosted.org/packages/...", hash = "..." }
  wheels = [{ url = "...", hash = "..." }]
  
  [[package]]
  name = "anthropic"
  version = "1.7.0"
  ...
  ```

**Pattern traits:**
- Generated by uv (humans do not edit by hand)
- Commit it so all developers/runners get the same versions
- If updating a dependency: edit `pyproject.toml`, then `uv lock` to regenerate `uv.lock`

---

### `turtle/turtle-helper/README.md` (documentation, modification)

**Analog:** Existing `turtle/turtle-helper/README.md`

**Section to rewrite:** "Setup > 1. Bridge"

**Current text** (existing lines 39–48):
```markdown
### 1. Bridge

cd bridge
pip install websockets anthropic
export ANTHROPIC_API_KEY=sk-ant-...
export BRIDGE_TOKEN=$(openssl rand -hex 24)
export ALLOWED_PLAYERS=Nate
python bridge.py
```

**New text** (D-09, D-02, D-12):
```markdown
### 1. Bridge

**Prerequisites:**
- uv package manager. Install via `winget install astral-sh.uv` (PowerShell) or follow the [official uv installer](https://docs.astral.sh/uv/getting-started/installation/) for Git Bash.
- Verify: `uv --version`

**Setup:**

```bash
cd turtle-helper
uv sync                    # Install dependencies from uv.lock (creates .venv)
cp .env.example .env       # Local secrets file (git-ignored)
```

**Configure:** Edit `turtle-helper/.env`:
```bash
# Get your API key from https://console.anthropic.com
ANTHROPIC_API_KEY=sk-ant-...

# Generate a secure token:
BRIDGE_TOKEN=$(python -c "import secrets; print(secrets.token_hex(24))")

# Comma-separated player names allowed to give orders:
ALLOWED_PLAYERS=Nate,Friend2
```

**Run:**

```bash
uv run bridge/bridge.py    # Listens on :8765
```

Leave `HOST`, `PORT`, `MODEL`, and other settings at their defaults, or override them in `.env`.

**Expose to the Minecraft server** (see notes below for dev vs prod):
```

**Pattern traits**:
- uv installation methods (PowerShell + Git Bash)
- `uv sync` to create venv and install deps
- `.env.example` → `.env` copy pattern
- Example `.env` editing with real keys
- Token generation one-liner (D-02)
- Comma-separated ALLOWED_PLAYERS (D-04)
- `uv run bridge/bridge.py` instead of activating venv
- Explicit mention of defaults and override pattern

---

### `.planning/workstreams/turtle-helper/PROJECT.md` (documentation, modification)

**Analog:** Existing `.planning/workstreams/turtle-helper/PROJECT.md`

**Sections to modify:**

**1. Constraints section**

Current (line 70–76):
```
- **Dependencies**: `pip install` of two packages is the whole Python footprint; no framework, no database, one file until it hurts
```

New (per D-09, D-04):
```
- **Dependencies**: uv-managed project with websockets, anthropic, pydantic-settings (transitive pydantic arrives via anthropic); Phase 2 adds pydantic-ai. No hand-rolled config parsing, no framework heavier than what Pydantic provides.
```

**2. Key Decisions section**

Add entry (D-09, D-04):
```markdown
| Relaxation: Python dependency footprint (2026-09-19) | Phase 1 adds pydantic-settings for type-safe config; Phase 2 adds pydantic-ai. This is acceptable overhead for the safety and maintainability gained. Constraint changed from "two packages" to "Pydantic ecosystem + websockets + anthropic." | ✓ Good — 2026-09-20 |
```

**Pattern traits:**
- Document when a locked constraint is relaxed (it affects all downstream phases)
- Rationale short but clear
- Date and status at end of line

---

## Shared Patterns

### Configuration & Environment

**Source:** `settings.py` (new), following pydantic-settings v2 pattern

**Apply to:** All modules that need configuration (bridge.py imports and uses Settings)

**Pattern:**
- Configuration is a single `BaseSettings` model, loaded once in `main()`
- All env vars are uppercase in `.env` and code
- Required fields omit defaults; validation errors crash at startup with one line per field
- `pathlib.Path` for file paths, especially `.env` location
- `BeforeValidator` for custom parsing (comma-separated lists)
- Never build the `AsyncAnthropic` client at module level; defer to `main()` after Settings validates

### Startup Verification

**Source:** `bridge.py` main() function (pattern from RESEARCH.md Pattern 3)

**Apply to:** `bridge.py` startup sequence

**Pattern:**
```python
# 1. Load and validate Settings (catches missing required fields)
try:
    settings = Settings()
except ValidationError as e:
    for error in e.errors():
        print(f"config error: {error['loc'][0]}: {error['msg']}")
    raise SystemExit(1)

# 2. Log config summary (D-07: show resolved model, never show secrets in full)
print(f"config: model={settings.model}, host={settings.host}:{settings.port}")
print(f"bridge_token: {'set' if settings.bridge_token else 'NOT SET'}")

# 3. Verify external dependencies (D-08: auth error or unknown model is fatal)
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
except Exception:
    # Connection/timeout error: log warning, continue
    print("warning: could not verify model; bridge will still listen")
```

### Type Hints & Imports

**Source:** human-design Python conventions + D-16 (moved code gets type hints)

**Apply to:** All Python modules in bridge/

**Pattern:**
- `from __future__ import annotations` at top of every `.py` file
- Every function has parameter type hints and return type hints
- Use `TYPE_CHECKING` import block for types only needed at type-check time
- Avoid `Any`; use concrete types or `dict[str, T]` if needed
- Module docstring as one-line summary

### WebSocket Event Loop

**Source:** Existing `bridge.py` handler function + D-17 (websockets asyncio API)

**Apply to:** `bridge.py` handler and on_event functions

**Pattern:**
```python
async def handler(websocket: ServerConnection) -> None:
    """Handle one device connection."""
    device_id: str | None = None
    try:
        # Receive hello, validate token, register device
        raw = await asyncio.wait_for(websocket.recv(), 10)
        msg = json.loads(raw)
        
        if msg.get("type") != "hello" or msg.get("token") != settings.bridge_token:
            await websocket.close(4001, "invalid token")
            return
        
        device_id = msg.get("id")
        devices[device_id] = {"ws": websocket, "role": ..., "caps": ...}
        
        # Listen for messages
        async for raw in websocket:
            msg = json.loads(raw)
            if msg.get("type") == "result":
                # Unblock awaiter
                cid = msg.get("cid")
                if fut := pending.pop(cid, None):
                    fut.set_result(msg)
            elif msg.get("type") == "event":
                asyncio.create_task(on_event(device_id, msg))
    
    except ConnectionClosed:
        log.info(f"device disconnected: {device_id}")
    except Exception as e:
        log.error(f"handler error: {e}", exc_info=True)
    finally:
        if device_id and device_id in devices:
            del devices[device_id]
```

---

## No Analog Found

None. All Phase 1 files either have direct analogs in the existing codebase or follow established patterns from RESEARCH.md and the human-design role model.

---

## Metadata

**Analog search scope:** Existing `turtle/turtle-helper/bridge/bridge.py` (single Python file, 236 lines), human-design repo via WSL for style models, RESEARCH.md for pydantic-settings and websockets patterns

**Files scanned:** 1 existing Python file; 2 external role model repos (human-design, RESEARCH.md)

**Pattern extraction date:** 2026-09-20

**Git-tracked source verification:** All analogs verified as git-tracked:
- Existing `turtle/turtle-helper/bridge/bridge.py` — tracked (active source)
- human-design repo files accessed via WSL for reference only (not embedded in PATTERNS.md, style only)
- RESEARCH.md code examples sourced from project research artifacts (tracked)


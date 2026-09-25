# Phase 3: Local Server Setup - Pattern Map

**Mapped:** 2026-09-25  
**Files analyzed:** 14 new/modified files  
**Analogs found:** 11 with tracked source matches / 14 total

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `turtle/turtle-helper/deploy/deploy.py` | CLI service entry point | request-response (local file I/O, config) | `harness/harness.py` | exact — argparse, main(), Settings import, exit codes |
| `turtle/turtle-helper/deploy/__init__.py` | Package marker | N/A | `bridge/__init__.py` | exact — package structure |
| `bridge/settings.py` (D-02 amendment) | Config validation model | configuration load | Self (existing) | exact — add Path field for `server_dir` |
| `.env.example` (D-02 amendment) | Config documentation | N/A | Self (existing) | exact — add `SERVER_DIR` key |
| `tests/test_deploy_marker_scan.py` | Unit test | zero-network testing | `tests/test_harness_scenarios.py` | exact — TAP style, dependency-free |
| `tests/test_deploy_toml_idempotent.py` | Unit test | zero-network testing | `tests/test_bridge_resilience.py` | exact — TAP style, no pytest framework |
| `tests/test_deploy_file_write.py` | Unit test | zero-network testing | same as above | exact — TAP style |
| `tests/test_deploy_server_state.py` | Unit test | zero-network testing | same as above | exact — TAP style |
| `tests/test_deploy_secrets.py` | Unit test | zero-network testing | same as above | exact — TAP style |
| `tests/test_deploy_startup_lua.py` | Unit test | zero-network testing | same as above | exact — TAP style |
| `tests/test_deploy_e2e.py` | Integration test | zero-network testing | same as above | exact — TAP style |
| `turtle/turtle-helper/base/chat.lua` (D-10 amendment) | Lua device client | local file read, HTTP client | Self (existing, untracked) | exact — update DEVICE_ID naming; add bridge URL read |
| `turtle/turtle-helper/turtle/client.lua` (D-06 amendment) | Lua device client | local file read, HTTP client | Self (existing) | exact — add bridge URL read |
| `pyproject.toml` (D-01 amendment) | Project config | N/A | Self (existing) | exact — add `[project.scripts]` and packages list entry |

---

## Pattern Assignments

### `turtle/turtle-helper/deploy/deploy.py` (CLI service, local file I/O)

**Closest Analogs:**
- `harness/harness.py` — main() entry point, argparse, Settings import, exit codes, error handling
- `bridge/settings.py` — Settings pattern with env_file resolution

**Imports pattern** (from `harness/harness.py` lines 18–31):

```python
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Literal

from pydantic import ValidationError

from bridge.settings import Settings
```

For deploy.py:
```python
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

from pydantic import ValidationError

from bridge.settings import Settings
```

**CLI entry point pattern** (from `harness/harness.py` lines 409–471):

```python
def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(
        prog="harness",
        description="Fake device harness: play a chat or worker device against the running bridge.",
    )
    parser.add_argument("--role", choices=["chat", "worker"], required=True)
    # ... more arguments ...
    return parser

def main(argv: Sequence[str] | None = None) -> int:
    """Entry point: parse args, load settings, run the scenario."""
    parser = build_parser()
    args = parser.parse_args(argv)
    
    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
        return 2
    
    # ... main logic ...
    print(f"deployment summary: ...")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

For deploy.py:
```python
def build_parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    parser = argparse.ArgumentParser(
        prog="deploy",
        description="Deploy Lua files and configuration to the local Minecraft server.",
    )
    # No required arguments; settings come from .env
    return parser

def main(argv: Sequence[str] | None = None) -> int:
    """Entry point: load settings, check server state, deploy files and rules."""
    parser = build_parser()
    args = parser.parse_args(argv)
    
    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
        return 2
    
    # ... deploy logic: check server, insert rule, scan markers, write files ...
    print(f"deployment summary table ...")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

**Error handling pattern** (from `harness/harness.py` lines 450–467):

```python
try:
    settings = Settings()
except ValidationError as exc:
    for error in exc.errors():
        print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
    return 2

try:
    # ... operation that could raise OSError, ValueError, etc. ...
except (OSError, ValueError, FileNotFoundError) as exc:
    print(f"deployment error: {exc}", file=sys.stderr)
    return 1
except Exception as exc:
    print(f"unexpected error: {exc}", file=sys.stderr)
    return 2
```

---

### `bridge/settings.py` Amendment (D-02: Add `server_dir` field)

**Analog:** Self (existing code, lines 29–67)

**Current structure** (lines 29–68):
```python
class Settings(BaseSettings):
    """Bridge configuration; required fields raise ValidationError if missing or empty."""

    host: str = Field(default="127.0.0.1", description="WebSocket server bind address.")
    port: int = Field(default=8765, description="WebSocket server listen port.")
    bridge_token: str = Field(
        min_length=1,
        description="Shared secret devices present in their hello handshake; required, non-empty.",
    )
    # ... other fields ...

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )
```

**Add new field** (after `bridge_token` or at end of fields, before `model_config`):

```python
server_dir: Path | None = Field(
    default=None,
    description="Server root directory for local deployment (e.g., C:\\...\\Server-Files-1.1.1\\Server-Files-1.1.1).",
)
```

The field is optional for now (bridges that don't deploy set it to None); deploy.py will require it via env validation.

---

### `.env.example` Amendment (D-02: Add `SERVER_DIR` key)

**Analog:** Self (existing, lines 1–29)

**Add after `PING_TIMEOUT=20`:**

```
# Server root directory where run.bat and world/ live (required for deploy).
# Leave blank if not running a local dedicated server on this PC.
SERVER_DIR=
```

Or with a Windows path example:

```
# Server root directory where run.bat and world/ live (required for deploy).
# Example: C:\Users\...\Server-Files-1.1.1\Server-Files-1.1.1
SERVER_DIR=
```

---

### `tests/test_deploy_marker_scan.py` (Unit test: marker file discovery)

**Closest Analog:** `tests/test_harness_scenarios.py` (TAP style, dependency-free)

**Pattern** (from `test_harness_scenarios.py` lines 1–88):

```python
"""Zero-network checks for deploy marker scanning (Phase 3).

No bridge, no socket, no filesystem access to a real server: only the logic
that identifies marked folders. Same dependency-free TAP layout as Phase 2 tests.

    uv run python tests/test_deploy_marker_scan.py
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from deploy.deploy import scan_marked_folders  # noqa: E402

def test_scan_returns_empty_when_no_marker_found() -> None:
    """No marked folders = empty list."""
    # (use a temp dir with no markers)
    pass

def test_scan_finds_folder_with_marker() -> None:
    """Folder with marker file is included."""
    pass

TESTS = [
    test_scan_returns_empty_when_no_marker_found,
    test_scan_finds_folder_with_marker,
    # ... more tests ...
]

def main() -> int:
    passed = failed = 0
    print(f"1..{len(TESTS)}")
    for n, fn in enumerate(TESTS, 1):
        try:
            fn()
        except Exception as exc:
            failed += 1
            print(f"not ok {n} - {fn.__name__}")
            detail = "".join(traceback.format_exception_only(type(exc), exc)).strip()
            print("  ---")
            print(f"  error: {detail}")
            print("  ...")
        else:
            passed += 1
            print(f"ok {n} - {fn.__name__}")
    print(f"# tests {len(TESTS)}")
    print(f"# pass {passed}")
    print(f"# fail {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
```

**Key elements:**
- `from __future__ import annotations` (line 3)
- `sys.path.insert(0, ...)` for local imports (line 10)
- Plain `def test_*()` functions with `assert` or raise on failure
- No pytest decorators or framework imports
- Manual TAP output loop at `main()` (lines 64–83)
- Run with `uv run python tests/test_deploy_marker_scan.py`

---

### `tests/test_deploy_toml_idempotent.py` (Unit test: TOML rule idempotency)

**Analog:** `tests/test_bridge_resilience.py` (TAP style, mocking, no network)

**Pattern** (similar to above, but with temp files):

```python
"""Zero-network checks for TOML rule insertion idempotency (Phase 3).

No bridge, no socket, no real server: only the logic that inserts and
re-checks the [[http.rules]] allow rule.

    uv run python tests/test_deploy_toml_idempotent.py
"""

from __future__ import annotations

import sys
import tempfile
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from deploy.deploy import insert_allow_rule  # noqa: E402

def test_rule_inserted_before_private_deny() -> None:
    """Rule is inserted and appears before $private deny."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
        # Write a minimal TOML with the $private deny block
        f.write('[[http.rules]]\n  host = "$private"\n  action = "deny"\n')
        toml_path = Path(f.name)
    
    try:
        inserted = insert_allow_rule(toml_path)
        assert inserted, "rule should be inserted"
        content = toml_path.read_text()
        assert 'host = "127.0.0.1"' in content
        assert 'action = "allow"' in content
        # Check order: allow should come before $private
        allow_pos = content.find('host = "127.0.0.1"')
        private_pos = content.find('host = "$private"')
        assert allow_pos < private_pos, "allow rule must come before $private"
    finally:
        toml_path.unlink()

def test_rule_idempotent_on_rerun() -> None:
    """Inserting the same rule twice does not duplicate it."""
    # ... similar setup ...
    inserted1 = insert_allow_rule(toml_path)
    assert inserted1
    inserted2 = insert_allow_rule(toml_path)
    assert not inserted2, "second run should detect rule already present"
    # Count occurrences of the rule
    count = toml_path.read_text().count('host = "127.0.0.1"')
    assert count == 1, "rule should appear exactly once"

TESTS = [test_rule_inserted_before_private_deny, test_rule_idempotent_on_rerun]

def main() -> int:
    # ... TAP output loop (same pattern as above) ...
    pass

if __name__ == "__main__":
    sys.exit(main())
```

---

### `turtle/turtle-helper/base/chat.lua` Amendment (D-10: Device naming)

**Analog:** Self (existing code, untracked; lines 1–92)

**Current naming** (lines 7–8):
```lua
local BRIDGE_URL   = "wss://YOUR-BRIDGE-HOST"   -- <-- change me
local DEVICE_ID    = "base"
```

**Amended** (D-10: use label-or-id pattern):
```lua
local BRIDGE_URL   = "wss://YOUR-BRIDGE-HOST"   -- <-- change me
local DEVICE_ID    = os.getComputerLabel() or ("device-" .. os.getComputerID())
```

This matches the pattern already in `client.lua` (line 12).

**Also add bridge URL file read** (D-06: after readFile helper definition, lines 15–19):

Current:
```lua
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end
local TOKEN = (readFile("secret.txt") or error("secret.txt missing")):gsub("%s+$", "")
```

Amended:
```lua
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end
local TOKEN = (readFile("secret.txt") or error("secret.txt missing")):gsub("%s+$", "")
local bridge_url_file = readFile("bridge.txt")  -- D-06: bridge URL from file
if bridge_url_file then
  BRIDGE_URL = bridge_url_file:gsub("%s+$", "")  -- trim whitespace
end
```

---

### `turtle/turtle-helper/turtle/client.lua` Amendment (D-06: Bridge URL file read)

**Analog:** Self (existing code, lines 1–214)

**Current naming and constants** (lines 11–13):
```lua
local BRIDGE_URL = "wss://YOUR-BRIDGE-HOST"      -- <-- change me (ws:// for local dev)
local DEVICE_ID  = os.getComputerLabel() or ("device-" .. os.getComputerID())
local ALLOW_EVAL = false   -- set true to let the agent run arbitrary Lua (run_lua tool)
```

**Add bridge URL file read** (D-06: after readFile helper definition, lines 16–25):

Current helper:
```lua
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end

-- Kept alongside readFile so a later push-script / load-routine primitive can
-- slot in without another rewrite (nothing on the device writes files today).
local function writeFile(path, s)
  local f = fs.open(path, "w"); f.write(s); f.close()
end

local TOKEN = readFile("secret.txt")
if not TOKEN then error("secret.txt missing: put the bridge token in it") end
TOKEN = TOKEN:gsub("%s+$", "")
```

Amended (add after TOKEN init):
```lua
local TOKEN = readFile("secret.txt")
if not TOKEN then error("secret.txt missing: put the bridge token in it") end
TOKEN = TOKEN:gsub("%s+$", "")

-- D-06: load bridge URL from file if it exists, else use the default
local bridge_url_file = readFile("bridge.txt")
if bridge_url_file then
  BRIDGE_URL = bridge_url_file:gsub("%s+$", "")  -- trim whitespace
end
```

This keeps the `wss://YOUR-BRIDGE-HOST` placeholder in the source but allows deploy to override it at runtime.

---

### `pyproject.toml` Amendment (D-01: Add deploy entry point)

**Analog:** Self (existing, lines 19–27)

**Current `[project.scripts]`** (line 20):
```toml
[project.scripts]
harness = "harness.harness:main"
```

**Add**:
```toml
[project.scripts]
harness = "harness.harness:main"
deploy = "deploy.deploy:main"
```

**Current `[tool.hatch.build.targets.wheel] packages`** (line 27):
```toml
packages = ["bridge", "harness"]
```

**Update to**:
```toml
packages = ["bridge", "harness", "deploy"]
```

---

## Shared Patterns

### Settings Configuration and Environment Loading

**Source:** `bridge/settings.py` (lines 1–9, 29–67)

**Apply to:** Any module that needs configuration

```python
from __future__ import annotations

from pathlib import Path
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    """Typed, validated configuration sourced from .env and the environment."""
    
    field_name: type = Field(
        default=value,
        description="Human-readable description of this field."
    )
    
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parent.parent / ".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",  # Ignore unknown env vars
    )
```

Key points:
- `Path(__file__).resolve().parent.parent / ".env"` resolves `.env` relative to the source file's parent directory, not the CWD
- `case_sensitive=False` allows `SERVER_DIR` in `.env` to map to `server_dir` field
- `extra="ignore"` ensures bridge keeps accepting its fields even if deploy adds new ones

---

### CLI Entry Point with Error Handling

**Source:** `harness/harness.py` (lines 409–471)

**Apply to:** Any CLI tool (deploy, etc.)

```python
def build_parser() -> argparse.ArgumentParser:
    """Build and return the argument parser."""
    parser = argparse.ArgumentParser(
        prog="tool-name",
        description="Short description of the tool.",
    )
    parser.add_argument("--option", help="An optional flag")
    return parser

def main(argv: Sequence[str] | None = None) -> int:
    """Entry point: parse args, validate config, run main logic, return exit code."""
    parser = build_parser()
    args = parser.parse_args(argv)
    
    try:
        settings = Settings()
    except ValidationError as exc:
        for error in exc.errors():
            print(f"config error: {error['loc'][0]}: {error['msg']}", file=sys.stderr)
        return 2  # Config error
    
    try:
        # ... main logic ...
        return 0  # Success
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1  # Runtime error
    except Exception as exc:
        print(f"unexpected error: {exc}", file=sys.stderr)
        return 2  # Unexpected error

if __name__ == "__main__":
    sys.exit(main())
```

Exit codes:
- `0`: Success
- `1`: Runtime error (file not found, permission denied, validation failed)
- `2`: Configuration error (missing .env, invalid setting, refusal to proceed)

---

### TAP-Style Unit Tests (Dependency-Free)

**Source:** `tests/test_harness_scenarios.py` (lines 1–88) and `tests/test_bridge_resilience.py` (lines 1–99)

**Apply to:** All new test files

```python
"""Short description of what is being tested.

No external dependencies or frameworks; runs with uv run python tests/test_*.py

    uv run python tests/test_deploy_marker_scan.py
"""

from __future__ import annotations

import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Import the module(s) being tested
from deploy.deploy import function_under_test  # noqa: E402

def test_case_one() -> None:
    """Short description of what this test checks."""
    # Arrange
    # Act
    # Assert
    assert condition, "message"

def test_case_two() -> None:
    """Another test."""
    assert something_else

TESTS = [test_case_one, test_case_two]

def main() -> int:
    """Run all tests and print TAP output."""
    passed = failed = 0
    print(f"1..{len(TESTS)}")
    for n, fn in enumerate(TESTS, 1):
        try:
            fn()
        except Exception as exc:
            failed += 1
            print(f"not ok {n} - {fn.__name__}")
            detail = "".join(traceback.format_exception_only(type(exc), exc)).strip()
            print("  ---")
            print(f"  error: {detail}")
            print("  ...")
        else:
            passed += 1
            print(f"ok {n} - {fn.__name__}")
    print(f"# tests {len(TESTS)}")
    print(f"# pass {passed}")
    print(f"# fail {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
```

Key points:
- No pytest, no unittest, no framework
- `sys.path.insert(0, ...)` allows relative imports from the parent package
- TAP (Test Anything Protocol) output: `1..<count>` header, `ok/not ok` per test, summary
- Test discovery: naming convention `test_*.py` in `tests/` directory
- Run: `uv run python tests/test_name.py`

---

### Lua File Reading Pattern (Existing)

**Source:** `turtle/client.lua` (lines 16–29) and `base/chat.lua` (lines 15–19)

**Apply to:** Any Lua file that reads `secret.txt` or the bridge URL file

```lua
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end

-- Usage: read token and trim whitespace
local TOKEN = readFile("secret.txt")
if not TOKEN then error("secret.txt missing: put the bridge token in it") end
TOKEN = TOKEN:gsub("%s+$", "")

-- Usage: read bridge URL, trim, fall back to default
local bridge_url_file = readFile("bridge.txt")
if bridge_url_file then
  BRIDGE_URL = bridge_url_file:gsub("%s+$", "")
end
```

Key points:
- `readFile` returns `nil` if the file does not exist (no error)
- `.gsub("%s+$", "")` removes trailing whitespace (newlines, spaces)
- Fallback to a default if the file is absent (D-06 pattern)
- Device name: `os.getComputerLabel() or ("device-" .. os.getComputerID())`

---

## No Analog Found

Files with no direct match in the codebase (using new patterns or implementation choices):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `deploy/` package structure | CLI service | request-response | New capability; patterns adapted from harness.py and settings.py |
| `startup.lua` (generated by deploy) | Lua startup script | config/startup | Generated (not tracked); three-line universal script from RESEARCH.md |
| Launcher script (shape TBD) | Process launcher | process spawn | New capability; shape (bat, PowerShell, Python) deferred to implementation |

---

## Metadata

**Analog search scope:** `turtle/turtle-helper/bridge/`, `turtle/turtle-helper/harness/`, `turtle/turtle-helper/tests/`, `turtle/turtle-helper/base/` (untracked), `turtle/turtle-helper/turtle/`

**Files scanned:** 5 Python modules (bridge, harness, tests), 2 Lua files, 3 config files (pyproject.toml, .env.example, CLAUDE.md)

**Pattern extraction methodology:**
- CLI entry point and error handling from `harness/harness.py` (lines 409–471)
- Settings pattern (env_file resolution, extra="ignore") from `bridge/settings.py` (lines 1–67)
- Imports and type hint conventions from all Python modules
- TAP test structure from `tests/test_harness_scenarios.py` and `tests/test_bridge_resilience.py`
- Lua file reading pattern from `client.lua` and `chat.lua`
- Device naming pattern from `client.lua` (label-or-id) for consistency across both scripts

**Date:** 2026-09-25

---

## Special Notes

### File: `turtle/turtle-helper/base/chat.lua`

This file is **untracked in git** (noted in scope note). It exists on disk but has never been committed. Patterns are extracted from the file's current state (lines 1–92), and Phase 4 (LOOP-05) expects the deployed version to diff cleanly against the repo version after Phase 3 edits. The two amendments (D-10 device naming, D-06 bridge URL read) are the only changes this file needs.

### File: `startup.lua`

This file is **generated by the deploy script**; it does not exist in the repo. The three-line universal role detector from RESEARCH.md Code Examples (§ Universal startup.lua, lines 450–455) is the complete content:

```lua
-- startup.lua : detect role (chat box present?) and launch the appropriate script
local chatBox = peripheral.find("chatBox")
if chatBox then shell.run("chat") else shell.run("client") end
```

No analog needed; copied directly from RESEARCH.md.

### Settings Extension Safety

The `extra="ignore"` setting in `bridge/settings.py` (line 66) ensures that if deploy adds new keys to `.env` (e.g., `SERVER_DIR`), the bridge continues to load without validation errors. The bridge simply ignores `SERVER_DIR` and other unknown keys. This allows both modules to share the same `.env` file safely.

---

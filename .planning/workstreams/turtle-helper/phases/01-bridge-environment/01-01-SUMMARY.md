---
phase: 01-bridge-environment
plan: 01
subsystem: infra
tags: [uv, pydantic-settings, websockets, anthropic, python]

requires: []
provides:
  - "uv-managed Python environment (pyproject.toml + committed uv.lock) for turtle-helper"
  - "bridge/settings.py: typed Settings model, the config contract Phase 2's harness imports"
  - "bridge/agent.py: the hand-rolled Claude tool-use loop, isolated behind configure() for Phase 2's Pydantic AI swap"
  - "bridge/bridge.py: websocket server on the current websockets asyncio API, fail-fast startup, credential verification"
affects: [phase-2-fake-device-harness, phase-2-pydantic-ai-agent-loop]

actuals:
  tokens: 34746
  tasks: 3
  commits: 5
  plan_head_before: 055d4426bbf1d8759c6524e4acf1cf9d888d3694

tech-stack:
  added: [uv, pydantic-settings==2.15.0, websockets==17.1, anthropic==1.7.0, ruff==0.5.1, mypy==1.14.0, hatchling]
  patterns:
    - "Typed BaseSettings model with NoDecode + BeforeValidator for comma-separated env fields"
    - "Zero-side-effect module split: settings.py / agent.py / bridge.py, wired together via a configure() handoff called once from main()"
    - "Fail-fast startup: ValidationError -> one line per field, SystemExit(1), no traceback"
    - "Token-free startup credential verification via client.models.retrieve() before serving"

key-files:
  created:
    - turtle/turtle-helper/pyproject.toml
    - turtle/turtle-helper/uv.lock
    - turtle/turtle-helper/.gitignore
    - turtle/turtle-helper/.env.example
    - turtle/turtle-helper/bridge/__init__.py
    - turtle/turtle-helper/bridge/settings.py
    - turtle/turtle-helper/bridge/agent.py
  modified:
    - turtle/turtle-helper/bridge/bridge.py

key-decisions:
  - "Added NoDecode to the ALLOWED_PLAYERS field alongside BeforeValidator: pydantic-settings 2.15 JSON-decodes list[str] env values before validators run, so the plan's literal BeforeValidator-only recipe raised a raw JSONDecodeError on a comma-separated value. Confirmed empirically; NoDecode was RESEARCH.md's own documented fallback."
  - "Added Field(min_length=1) to allowed_players: without it, ALLOWED_PLAYERS= (present but empty) validated successfully to [] instead of raising ValidationError, silently reopening the 'empty means everyone' hole the phase exists to close."
  - "Inserted sys.path.insert(0, project_root) at the top of bridge.py before the bridge.* imports: running bridge/bridge.py directly as a script puts bridge/'s own directory on sys.path[0], which self-collides with the sibling bridge.py file when Python resolves the 'bridge' package name. This is the documented fallback the plan itself flagged as a contingency; confirmed necessary by empirical testing, not a guess."
  - "Added plugins = [\"pydantic.mypy\"] to [tool.mypy] in pyproject.toml: without it, mypy treats Settings() as a plain BaseModel requiring every field as a call-arg, flagging bridge_token/allowed_players/anthropic_api_key as missing even though pydantic-settings resolves them from the environment at runtime. This is pydantic's own official mypy plugin, not a workaround."
  - "Cast tools=/messages= to Any in agent.py's client.messages.create() call: the hand-rolled tool-use loop (moved unchanged from the starter per D-14) stores tool schemas and message history as plain JSON-shaped dicts, which don't structurally match the Anthropic SDK's generated TypedDict unions. Casting at this one interop boundary avoids re-typing the entire hand-rolled loop against SDK internals, which is explicitly out of scope until Phase 2's Pydantic AI rewrite."

requirements-completed: [BRIDGE-02, BRIDGE-03]
# BRIDGE-01 and BRIDGE-04 are also declared by plan 01-02 (shared-ID gate, #2388) and stay
# unmarked in REQUIREMENTS.md until 01-02 finishes and produces its own SUMMARY.

coverage:
  - id: D1
    description: "uv-managed Python environment: pyproject.toml + committed uv.lock, bridge/ installable as a package"
    requirement: BRIDGE-01
    verification:
      - kind: other
        ref: "cd turtle/turtle-helper && uv sync && uv run python -c \"from bridge.settings import Settings; from bridge import agent; print('IMPORT_OK')\""
        status: pass
    human_judgment: true
    rationale: "BRIDGE-01 is jointly declared with plan 01-02 (shared-ID gate); full requirement completion needs 01-02's README/doc work too. This plan's slice (env + import) is proven, but the requirement itself isn't marked complete yet."
  - id: D2
    description: "websockets asyncio server API migration: from websockets.asyncio.server import serve, single-argument handler, no legacy references"
    requirement: BRIDGE-02
    verification:
      - kind: other
        ref: "! grep -rEq 'websockets\\.(serve|legacy)' bridge/"
        status: pass
      - kind: other
        ref: "grep -q 'from websockets.asyncio.server import serve' bridge/bridge.py"
        status: pass
    human_judgment: false
  - id: D3
    description: "Default Claude model ID is claude-sonnet-5, no placeholder remains"
    requirement: BRIDGE-03
    verification:
      - kind: other
        ref: "grep -q 'claude-sonnet-5' bridge/settings.py && ! grep -rq 'claude-sonnet-4-5' bridge/"
        status: pass
    human_judgment: false
  - id: D4
    description: "Typed Settings model reads BRIDGE_TOKEN/ALLOWED_PLAYERS/ANTHROPIC_API_KEY from env/.env; missing or empty required fields fail fast with a one-line message"
    requirement: BRIDGE-04
    verification:
      - kind: other
        ref: "env -u BRIDGE_TOKEN -u ANTHROPIC_API_KEY -u ALLOWED_PLAYERS uv run bridge/bridge.py -> EXIT_CODE:1, no traceback"
        status: pass
      - kind: other
        ref: "env BRIDGE_TOKEN=... ALLOWED_PLAYERS= ANTHROPIC_API_KEY=... uv run bridge/bridge.py -> EXIT_CODE:1, no traceback"
        status: pass
    human_judgment: true
    rationale: "BRIDGE-04 is jointly declared with plan 01-02 (shared-ID gate); not marked complete in REQUIREMENTS.md until 01-02 finishes, even though this plan's config-reading and fail-fast behavior is fully proven above."
  - id: D5
    description: "bridge.py split into settings.py / agent.py / bridge.py, each importable with zero side effects; startup verifies the model and API key before serving"
    verification:
      - kind: other
        ref: "uv run python -c \"from bridge.settings import Settings; from bridge import agent; print('IMPORT_OK')\""
        status: pass
      - kind: other
        ref: "env ... ANTHROPIC_API_KEY=sk-ant-invalid-deliberately-bad-0001 uv run bridge/bridge.py -> EXIT_CODE:1, one-line ERROR, no traceback"
        status: pass
    human_judgment: true
    rationale: "The full happy path (valid real ANTHROPIC_API_KEY reaching the 'listening on ws://127.0.0.1:8765' line, with the verified-model INFO line preceding it) needs a real API key the developer controls -- explicitly called out as Manual-Only in the plan's own <verification> section, not automatable in this session."
  - id: D6
    description: "ruff and mypy both pass clean on bridge/"
    verification:
      - kind: other
        ref: "uv run ruff check bridge/"
        status: pass
      - kind: other
        ref: "uv run mypy bridge/"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-09-20
status: complete
---

# Phase 1 Plan 1: Bridge Environment Summary

**uv-managed Python environment with a typed pydantic-settings config, the bridge starter split into settings.py/agent.py/bridge.py, migrated to the current websockets asyncio API, and startup credential verification against the real Anthropic API.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-09-20T10:40:58Z
- **Completed:** 2026-09-20T11:00:28Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments
- Installed `uv` (winget) and created a `pyproject.toml` + committed `uv.lock` pinning websockets 17.1, anthropic 1.7.0, pydantic-settings 2.15.0, with a `ruff`/`mypy` dev group and a `hatchling` build backend so `bridge/` installs as an importable package
- `bridge/settings.py`: a typed `pydantic-settings` `BaseSettings` model with all eleven config fields, `NoDecode` + `BeforeValidator` for the comma-separated `ALLOWED_PLAYERS` field, and `min_length=1` closing the "empty means everyone" hole
- Split the starter into `bridge/settings.py` (config), `bridge/agent.py` (the hand-rolled Claude tool-use loop, moved unchanged in logic), and `bridge/bridge.py` (websocket server, device registry, `main()`) -- each importable with zero side effects, wired together via a `configure()` handoff
- Migrated to `websockets.asyncio.server.serve` with a single-argument handler and `websockets.exceptions.ConnectionClosed`; no legacy reference remains
- Startup now verifies the Anthropic API key and model via a token-free `client.models.retrieve()` call: fatal one-line exit on `AuthenticationError`/`NotFoundError`, a warning-and-continue on `APIConnectionError`
- `ruff check bridge/` and `mypy bridge/` (with `pydantic.mypy` plugin) both pass with zero issues

## Task Commits

Each task was committed atomically:

1. **Task 1: uv environment + typed Settings + the settings.py/agent.py/bridge.py split** - `7b85bfd` (feat)
2. **Task 2: Startup verification against the real Anthropic API** - `ba034cd` (feat)
3. **Task 3: Lint and type-check bridge/ to green** - `bc88daa` (refactor)

**Plan metadata:** (this commit, following this SUMMARY)

_Note: two unrelated commits (`b523318`, `704dcae`, touching `turtle/platform.lua` -- a different area of the repo) landed from a concurrent process during this execution window. They are not part of this plan; see "Concurrent Commits Observed" below._

## Files Created/Modified
- `turtle/turtle-helper/pyproject.toml` - `[project]`, `[dependency-groups]`, `[build-system]`/`[tool.hatch...]`, `[tool.ruff]`, `[tool.mypy]` (with `pydantic.mypy` plugin)
- `turtle/turtle-helper/uv.lock` - generated lockfile, 22 pinned packages
- `turtle/turtle-helper/.gitignore` - `.env`, `.venv/`, `__pycache__/`, `.ruff_cache/`, `.mypy_cache/`
- `turtle/turtle-helper/.env.example` - all eleven Settings keys, uppercase, with the token-generation one-liner
- `turtle/turtle-helper/bridge/__init__.py` - package marker
- `turtle/turtle-helper/bridge/settings.py` - `class Settings(BaseSettings)`, `split_comma_separated()`, `CommaSeparatedPlayers`
- `turtle/turtle-helper/bridge/agent.py` - `DEVICE_TOOLS`, `LOCAL_TOOLS`, `histories`, `run_tool()`, `handle_request()`, `configure()`, `SYSTEM_TEMPLATE`
- `turtle/turtle-helper/bridge/bridge.py` - `devices`, `pending`, `send_cmd()`, `say()`, `default_worker()`, `handler()`, `on_event()`, `main()` (rewritten)

## Decisions Made
See `key-decisions` in frontmatter above -- five auto-fixes, all documented as deviations below with full rationale.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ALLOWED_PLAYERS comma-separated parsing needed NoDecode, not just BeforeValidator**
- **Found during:** Task 1 (Settings model, empirical test of the plan's literal recipe)
- **Issue:** The plan's action text specifies `Annotated[list[str], BeforeValidator(split_comma_separated)]`. Testing `ALLOWED_PLAYERS=TestPlayer,Foo` against this raised a raw `pydantic_settings.exceptions.SettingsError` wrapping a `JSONDecodeError` -- pydantic-settings 2.15 JSON-decodes `list[str]`-typed env values before any validator runs.
- **Fix:** Added `NoDecode` to the `Annotated` type alias, documented in RESEARCH.md's own Pitfall 2 as the fallback idiom.
- **Files modified:** bridge/settings.py
- **Verification:** `ALLOWED_PLAYERS=TestPlayer,Foo` now parses to `['TestPlayer', 'Foo']`
- **Committed in:** 7b85bfd

**2. [Rule 2 - Missing Critical] Empty ALLOWED_PLAYERS validated successfully instead of raising ValidationError**
- **Found during:** Task 1 (testing the must-have truth: "An empty ALLOWED_PLAYERS value fails Settings validation")
- **Issue:** `ALLOWED_PLAYERS=` (present, empty string) parsed to `[]` without error -- silently reopening the "empty means everyone allowed" security hole the phase exists to close (T-1-02 in the threat model).
- **Fix:** Added `Field(min_length=1, ...)` to `allowed_players`.
- **Files modified:** bridge/settings.py
- **Verification:** `ALLOWED_PLAYERS=` now raises `ValidationError: List should have at least 1 item after validation, not 0`, exits 1, no traceback
- **Committed in:** 7b85bfd

**3. [Rule 3 - Blocking] Circular import running bridge.py directly as a script**
- **Found during:** Task 1 (running `uv run bridge/bridge.py` for the fail-fast verify check)
- **Issue:** `ImportError: cannot import name 'agent' from partially initialized module 'bridge' (most likely due to a circular import)`. Running `bridge/bridge.py` as `__main__` puts its own directory (`bridge/`) at `sys.path[0]`, which self-collides with the sibling `bridge.py` file when Python resolves the top-level `bridge` package name.
- **Fix:** Inserted `sys.path.insert(0, str(Path(__file__).resolve().parent.parent))` before the `bridge.*` imports -- exactly the fallback the plan itself flagged as a contingency ("If Check A ... still fails ... insert sys.path.insert...").
- **Files modified:** bridge/bridge.py
- **Verification:** `uv run bridge/bridge.py` imports cleanly and reaches config validation
- **Committed in:** 7b85bfd

**4. [Rule 3 - Blocking] mypy flagged Settings() as missing required call-args**
- **Found during:** Task 3 (mypy check)
- **Issue:** `mypy` reported `Missing named argument "bridge_token"/"allowed_players"/"anthropic_api_key" for "Settings"` at the `Settings()` call site in `bridge.py`'s `main()`. Vanilla mypy doesn't know pydantic-settings resolves these fields from the environment at runtime.
- **Fix:** Added `plugins = ["pydantic.mypy"]` to `[tool.mypy]` in pyproject.toml -- pydantic's own official mypy plugin, standard practice for typed pydantic-settings projects.
- **Files modified:** pyproject.toml
- **Verification:** `mypy bridge/` passes with zero errors
- **Committed in:** bc88daa

**5. [Rule 3 - Blocking] anthropic SDK's typed tool/message params didn't structurally match the hand-rolled loop's plain dicts**
- **Found during:** Task 3 (mypy check)
- **Issue:** `mypy` flagged `tools=DEVICE_TOOLS + LOCAL_TOOLS` and `messages=hist` in `client.messages.create(...)` as incompatible with the SDK's generated `ToolParam`/`MessageParam` TypedDict unions.
- **Fix:** Cast both arguments to `Any` at this one call site, with a comment explaining why (the hand-rolled loop, moved unchanged from the starter per D-14, stores schemas/history as plain JSON-shaped dicts; re-typing the whole loop against SDK internals is out of scope until Phase 2's Pydantic AI rewrite).
- **Files modified:** bridge/agent.py
- **Verification:** `mypy bridge/` passes with zero errors; behavior unchanged (same runtime dict values, just cast for the type checker)
- **Committed in:** bc88daa

---

**Total deviations:** 5 auto-fixed (2 bugs closing a real security/correctness gap, 3 blocking issues preventing task completion)
**Impact on plan:** All five were necessary for correctness or to satisfy the plan's own stated acceptance criteria and must-have truths. No scope creep -- each fix stayed within the file(s) the relevant task already touched, except the pydantic.mypy plugin addition to pyproject.toml, which was in scope for Task 3's "lint and type-check bridge/ to green" goal even though pyproject.toml wasn't in Task 3's `<files>` list.

## Issues Encountered

**Plan verify-block command/description mismatch (Task 1, third automated check).** The plan's third automated `<verify>` command for Task 1 sets `ALLOWED_PLAYERS=TestPlayer` (non-empty) but its `<fails_when>` description says "an empty ALLOWED_PLAYERS must fail Settings validation, not crash." Running the command literally as written (foreground, no backgrounding) hangs forever, since a non-empty, well-formed config reaches the listening state and never exits on its own -- confirmed by hitting the 120s tool timeout and having to kill the process manually. I ran the check the description actually intended (`ALLOWED_PLAYERS=` empty), which passed (exit 1, no traceback), and separately confirmed the non-empty-config path reaches "listening on ws://127.0.0.1:8765" via the plan's own fourth (backgrounded, 6s sleep) check. No code fix needed -- this is a plan-authoring inconsistency, not a bridge.py bug. Flagging here so `/gsd-verify-work` or a future plan-fix pass can correct the literal command in `01-01-PLAN.md`.

## Concurrent Commits Observed

While this plan was executing (2026-09-20 03:35-04:00 local), two commits unrelated to this plan landed on `main` from what appears to be a concurrent process or session: `b523318` ("feat(turtle): add platform.lua, a serpentine platform builder") and `704dcae` ("fix(turtle): platform starts at the block ahead, not under the turtle"), both touching `turtle/platform.lua` and `turtle/README.md` -- a different area of the repo than anything this plan touches. They do not conflict with or affect this plan's files. Flagging for visibility since this executor was briefed to run as the sole sequential executor on the main working tree; if that assumption doesn't hold, concurrent writes to `main` are a risk worth the user's awareness.

## User Setup Required

None - no external service configuration required this plan. (A real `ANTHROPIC_API_KEY` and `BRIDGE_TOKEN` are needed for the manual-only happy-path verification described in the plan's `<verification>` section, but setting those up is the user's own `.env` per `README.md`, not a new requirement this plan introduces.)

## Next Phase Readiness

- `bridge/settings.py` and the `configure()` seam are ready for Phase 2's fake device harness and Pydantic AI agent-loop rewrite to import against, per D-13/D-14.
- Plan 01-02 (same phase) still owns the README rewrite (D-12) and the remainder of BRIDGE-01/BRIDGE-04's requirement completion (shared-ID gate).
- Manual-only verification (real API key: unknown-MODEL path, connection-error path, full happy path) remains open per the plan's own `<verification>` section -- not a blocker, explicitly scoped as developer-only follow-up.

## Self-Check: PASSED

- All 8 created/modified files confirmed present on disk (`turtle/turtle-helper/{pyproject.toml,uv.lock,.gitignore,.env.example,bridge/__init__.py,bridge/settings.py,bridge/agent.py,bridge/bridge.py}`)
- All 3 task commits confirmed in `git log` (`7b85bfd`, `ba034cd`, `bc88daa`)
- Re-ran acceptance criteria: `def configure(` in agent.py, `agent.configure(` in bridge.py, `client.models.retrieve(` in bridge.py -- all present
- Re-ran plan-level verification: `ruff check bridge/` and `mypy bridge/` both pass clean

---
*Phase: 01-bridge-environment*
*Completed: 2026-09-20*

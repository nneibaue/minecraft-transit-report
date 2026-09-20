---
phase: 01-bridge-environment
plan: 02
subsystem: infra
tags: [uv, docs, readme, project-md]

requires:
  - phase: 01-bridge-environment
    provides: "The actual uv sync / .env.example / uv run bridge/bridge.py recipe built by 01-01, which this plan's README rewrite documents verbatim"
provides:
  - "README.md 'Setup > 1. Bridge' section documenting the uv install, uv sync, .env.example -> .env copy, and uv run bridge/bridge.py recipe"
  - "PROJECT.md Constraints and Key Decisions reflecting the relaxed Python dependency footprint (websockets + anthropic + pydantic-settings, pydantic-ai in Phase 2)"
affects: [phase-2-fake-device-harness, phase-5-doc-pass]

actuals:
  tokens: 2099
  tasks: 2
  commits: 2
  plan_head_before: 207560e3edf46c8b23f88fe8a99e6cf12a15a6ea

tech-stack:
  added: []
  patterns:
    - "Documentation-only plan: no code, no new symbols — see 01-01-PLAN.md for code artifacts"

key-files:
  created: []
  modified:
    - turtle/turtle-helper/README.md
    - .planning/workstreams/turtle-helper/PROJECT.md

key-decisions:
  - "PROJECT.md's 'Machine state at milestone start' sentence mentioning the absence of requirements.txt/pyproject.toml/venv was left unchanged — it is a historical fact about the pre-phase starter state, not a recipe instruction, so D-09's 'update requirements.txt wording to uv.lock' scope did not apply to it."

requirements-completed: [BRIDGE-01, BRIDGE-04]

coverage:
  - id: D1
    description: "README.md 'Setup > 1. Bridge' documents the uv install (winget primary, Git Bash fallback), uv sync, the .env.example -> .env copy, and uv run bridge/bridge.py, replacing the old pip-based install block"
    requirement: BRIDGE-01
    verification:
      - kind: other
        ref: "grep -q 'uv sync' README.md && grep -q 'uv run bridge/bridge.py' README.md && grep -q '.env.example' README.md"
        status: pass
    human_judgment: false
  - id: D2
    description: "README.md Setup section documents that BRIDGE_TOKEN, ALLOWED_PLAYERS, and ANTHROPIC_API_KEY are set via the git-ignored .env file, not shell export commands"
    requirement: BRIDGE-04
    verification:
      - kind: other
        ref: "! grep -Eq 'export (ANTHROPIC_API_KEY|BRIDGE_TOKEN|ALLOWED_PLAYERS)=' README.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "PROJECT.md Constraints and Key Decisions reflect the relaxed Python dependency footprint (websockets + anthropic + pydantic-settings, uv-managed, pydantic-ai arriving in Phase 2)"
    verification:
      - kind: other
        ref: "grep -q 'pydantic-settings' PROJECT.md && grep -q 'uv' PROJECT.md && ! grep -q 'pip install. of two packages is the whole Python footprint' PROJECT.md"
        status: pass
    human_judgment: false

duration: 5min
completed: 2026-09-20
status: complete
---

# Phase 1 Plan 2: Bridge Environment Documentation Summary

**README.md's bridge setup recipe rewritten for uv + .env, and PROJECT.md's Constraints/Key Decisions updated to reflect the relaxed Python dependency footprint (websockets, anthropic, pydantic-settings; pydantic-ai in Phase 2).**

## Performance

- **Duration:** 5 min
- **Started:** 2026-09-20T11:04:19Z
- **Completed:** 2026-09-20T11:09:24Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Rewrote `README.md`'s "Setup > 1. Bridge" section: uv Prerequisites (winget install, Git Bash fallback, `uv --version` verify), Setup (`uv sync`, `cp .env.example .env`), Configure (the three required `.env` keys with generation/lookup instructions), and Run (`uv run bridge/bridge.py`, default port note)
- Replaced the old raw `export ANTHROPIC_API_KEY=...` / `export BRIDGE_TOKEN=...` / `export ALLOWED_PLAYERS=...` shell instructions with the git-ignored `.env` recipe
- Replaced the Dev (cloudflared/Tailscale) and Prod (VPS/Render/Fly) bullet points with a one-line pointer that hosting and tunnels return in a later milestone, per D-12 — left the "Same box as the MC server" `computercraft-server.toml` snippet untouched (Phase 3 scope)
- Updated `PROJECT.md`'s Constraints "Dependencies" bullet to name the uv-managed project, `websockets`/`anthropic`/`pydantic-settings` direct dependencies, `pydantic-ai` arriving in Phase 2, and the `settings.py`/`agent.py`/`bridge.py` split (replacing the stale "one file" / "two packages" wording)
- Added a new Key Decisions row recording the dependency-footprint relaxation (dated 2026-09-20, per CONTEXT.md's "Constraint change" note and D-09)

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite README.md "Setup > 1. Bridge" with the uv + .env recipe** - `fa9fa39` (docs)
2. **Task 2: Amend PROJECT.md Constraints and Key Decisions for the relaxed Python footprint** - `1e88e3b` (docs)

**Plan metadata:** (this commit, following this SUMMARY)

## Files Created/Modified
- `turtle/turtle-helper/README.md` - "Setup > 1. Bridge" section rewritten for the uv + `.env` recipe
- `.planning/workstreams/turtle-helper/PROJECT.md` - Constraints "Dependencies" bullet and a new Key Decisions row

## Decisions Made
- Left PROJECT.md's "Machine state at milestone start" sentence (mentioning no `requirements.txt`/`pyproject.toml`/venv existed pre-phase) unchanged — it is a historical fact about the starter's pre-phase state, not a live recipe, so it was out of scope for D-09's wording update.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- BRIDGE-01 and BRIDGE-04 are now fully satisfied: 01-01's code-side proof plus this plan's documented recipe both exist. Both requirement IDs are marked complete in REQUIREMENTS.md as part of this plan's close-out (shared-ID gate cleared — 01-01 finished first).
- Phase 1 is complete: both 01-01-PLAN.md and 01-02-PLAN.md have SUMMARY.md files. Ready for `/gsd-plan-phase 2` (fake device harness + Pydantic AI agent-loop rewrite) and `/gsd-verify-work 1`.
- `turtle/turtle-helper/CLAUDE.md`'s "Dev loop: ... one file until it hurts" line is now stale (the bridge is a three-module split) — flagged for DOC-02 in Phase 5, not touched here since it was outside this plan's `<files>` scope.

## Self-Check: PASSED

- `turtle/turtle-helper/README.md` and `.planning/workstreams/turtle-helper/PROJECT.md` confirmed present on disk with the expected edits
- Both task commits confirmed in `git log` (`fa9fa39`, `1e88e3b`)
- Re-ran all four automated `<verify>` checks from both tasks — all pass
- Re-ran acceptance criteria for both tasks — all satisfied (uv commands present, no export-secret lines, Dev/Prod bullets replaced with one-liner, "Same box" snippet unchanged, Constraints bullet updated, Key Decisions row added, old two-package sentence removed)

---
*Phase: 01-bridge-environment*
*Completed: 2026-09-20*

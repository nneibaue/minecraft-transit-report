---
phase: "2"
slug: "fake-device-harness-protocol-resilience"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: true
wave_0_complete: true
created: "2026-09-22"
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None — pytest is deferred to v1.1 (REQUIREMENTS.md TEST-02). This phase's own deliverable, the fake device harness itself, IS the test tool: its scenarios are the automated proofs. |
| **Config file** | none |
| **Quick run command** | `cd turtle/turtle-helper && uv run ruff check bridge/ && uv run mypy bridge/` |
| **Full suite command** | The five free harness scenarios run against a real, backgrounded `uv run bridge/bridge.py` process: `hello-handshake`, `status-command`, `drop-and-reconnect`, `wrong-token` (x2: arbitrary + empty), `disallowed-player` — plus `uv run ruff check bridge/` / `uv run mypy bridge/`. `devices-question` is excluded from the full suite (spends real money; runs only in Plans 02-04/02-07's gated checkpoints). |
| **Estimated runtime** | ~60-90 seconds (mostly bridge startup + a few seconds per scenario's timeouts) |

---

## Sampling Rate

- **After every task commit:** `uv run ruff check bridge/` (or `harness/` once it exists) — fast, catches syntax/type regressions immediately
- **After every plan wave:** The relevant free harness scenarios for that wave's requirements, against a freshly-backgrounded real bridge
- **Before `/gsd-verify-work`:** All five free scenarios green, `ruff`/`mypy` clean on `bridge/`
- **Max feedback latency:** ~20 seconds (bridge startup wait, 15s max, dominates)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | HARN-03 | T-02-01a / T-02-01b | Composition removed from device; rules.json no longer on-device | static | `git ls-files --error-unmatch turtle/turtle-helper/turtle/client.lua` | ✅ | ⬜ pending |
| 02-01-02 | 01 | 1 | HARN-03 | — | N/A | static | luaparse syntax check + grep primitive-set assertions | ✅ | ⬜ pending |
| 02-02-01 | 02 | 1 | RESIL-04 | T-02-02c / T-02-02e | Token never logged; CR-01 empty-token hole closed | static+unit | grep checks + `min_length=1` count | ✅ | ⬜ pending |
| 02-02-02 | 02 | 1 | RESIL-03 | T-02-02b | send_cmd catches ConnectionClosed, cleans pending_by_device | unit | in-process python check (fake websocket, D10_OK) | ✅ | ⬜ pending |
| 02-02-03 | 02 | 1 | RESIL-03 | T-02-02a | Malformed frames logged+continue; disconnect cleanup device-scoped | static+unit | grep + `uv run ruff check bridge/ && uv run mypy bridge/` | ✅ | ⬜ pending |
| 02-03-01 | 03 | 2 | HARN-01 | T-02-03c | Hello handshake live, wire log redacts token (prohibition) | integration | live bridge + `uv run harness --role chat --scenario hello-handshake` | ✅ | ⬜ pending |
| 02-03-02 | 03 | 2 | HARN-03, HARN-04 | T-02-03c | Worker canned responses match client.lua; reconnect/malformed-frame resilient | unit+integration | direct build_reply assertions + live `drop-and-reconnect` | ✅ | ⬜ pending |
| 02-03-03 | 03 | 2 | RESIL-04, RESIL-05, HARN-02 (def) | T-02-03a | Spend guard refuses without --spend; wrong-token/disallowed-player pass free | integration | live `wrong-token` (x2), `disallowed-player`; spend-guard exit check | ✅ | ⬜ pending |
| 02-04-01 | 04 | 3 | HARN-02 | — | N/A (setup) | integration | live bridge + worker harness startup | ✅ | ⬜ pending |
| 02-04-02 | 04 | 3 | HARN-02 | T-02-04a | Real API spend stays a deliberate human act | manual | N/A — checkpoint:human-action | N/A | ⬜ pending |
| 02-05-01 | 05 | 4 | HARN-02 | T-02-05a | pydantic-ai dependency verified via RESEARCH.md audit (no ASSUMED/SUS) | static | grep pins + async-def count | ✅ | ⬜ pending |
| 02-05-02 | 05 | 4 | HARN-02 | T-02-05c | build_toolset() never exposes a tool with no capable device connected | unit | in-process python check (TOOLSET_EMPTY_OK) | ✅ | ⬜ pending |
| 02-05-03 | 05 | 4 | HARN-02 | T-02-05b | handle_request signature unchanged; history committed only post-success | static+unit | grep + `uv run ruff check bridge/ && uv run mypy bridge/` | ✅ | ⬜ pending |
| 02-06-01 | 06 | 5 | HARN-02 | T-02-06a | rules.json git-ignored; loads safely with no file present | static+unit | grep .gitignore + in-process load_rules() check | ✅ | ⬜ pending |
| 02-06-02 | 06 | 5 | HARN-02 | T-02-06b | sort_chest cap-gated on list_chest+push_one_slot | static+unit | grep + in-process build_toolset() gating check | ✅ | ⬜ pending |
| 02-06-03 | 06 | 5 | HARN-02 | — | anthropic stays a direct dependency | static+unit | `uv run ruff check bridge/ && uv run mypy bridge/` + grep pyproject.toml | ✅ | ⬜ pending |
| 02-07-01 | 07 | 6 | HARN-02 | — | N/A (docs) | static | grep README.md for Harness section + scenario names + --spend | ✅ | ⬜ pending |
| 02-07-02 | 07 | 6 | HARN-02 | T-02-07b | CLAUDE.md amended; Current state untouched ahead of Phase 5 DOC-02 | static | grep CLAUDE.md + `git ls-files --error-unmatch` | ✅ | ⬜ pending |
| 02-07-03 | 07 | 6 | HARN-02 | — | N/A (setup) | integration | live bridge (swapped agent) + worker harness startup | ✅ | ⬜ pending |
| 02-07-04 | 07 | 6 | HARN-02 | T-02-07a | Second and final real API spend stays a deliberate human act | manual | N/A — checkpoint:human-action | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

None — this phase's own Wave 1 deliverable (Plan 02-03, Task 1) creates the test tool itself (the
harness). There is no pre-existing pytest/jest-style framework to bootstrap ahead of the tasks that need
it; each `<automated>` verify is either a static/grep check, a direct in-process Python assertion
against code the same task just wrote, or a live run against the real bridge the task itself starts.

*Existing infrastructure covers all phase requirements via the harness the phase builds as it goes.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Pre-swap devices-question paid run | HARN-02 | Spends a real Anthropic API call; the phase's spend guard (D-15) keeps this a deliberate human act, never something the autonomous executor triggers | Plan 02-04 Task 2 (checkpoint:human-action): operator runs `uv run harness --role chat --scenario devices-question --spend` and pastes the transcript back |
| Post-swap devices-question paid run | HARN-02 | Same spend guard; this is the phase's second and final budgeted paid call, proving the Pydantic AI swap changed nothing on the wire | Plan 02-07 Task 4 (checkpoint:human-action): same recipe, run against the fully-swapped agent |
| RESIL-05's bridge-side log line (`ignoring <user> (not allowed)`) | RESIL-05 | The harness observes only the wire protocol, not the bridge's own stdout; the harness proves "no cmd arrives" by absence, but grepping the bridge's actual log line for the exact wording is a human glance at the terminal running it | During Plan 02-03's `disallowed-player` scenario or the two-terminal recipe, the operator can optionally check the bridge terminal for the log line — not required for the automated pass |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies — confirmed by `check
      verify-failure-directions` (0 blockers, 0 warnings, 32/32 commands carry a `<fails_when>`)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify — every task above has at
      least one `<automated>` command; the two checkpoint tasks are the phase's only manual points and
      are isolated to their own single-purpose plans (02-04, 02-07), never adjacent to each other
- [x] Wave 0 covers all MISSING references — none exist; see "Wave 0 Requirements" above
- [x] No watch-mode flags
- [x] Feedback latency < 90s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — set by `/gsd-validate-phase` or the execute-phase verifier at Step 8, not by
plan-phase itself.

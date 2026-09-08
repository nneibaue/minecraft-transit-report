---
phase: 02-block-exists-and-places
plan: 02
subsystem: block-registration
tags: [fabric, datagen, docs, block-registration]

requires:
  - phase: "02-01"
    provides: "TransitChartBlock, TransitReportBlocks holder, TransitChartModelProvider, generated blockstate/model/item-model JSON, and the display-name translation line (pulled forward by 02-01, one plan ahead of this plan's own Task 1)"
provides:
  - "docs/DEV.md updated with the full Phase 2 generated-file list and the settled RESEARCH.md Assumption A1 / Open Question 1 findings"
  - "Human-confirmed D-05 visual verification: 4-direction facing, no checkerboard, correct display name"
  - "Phase 2 fully closed — all four ROADMAP Phase 2 success criteria satisfied"
affects: ["phase-03 (recipe/loot table work that makes this block survival-obtainable)", "phase-04 (renderer, which depends on the facing state this phase confirmed)"]

actuals:
  tokens: 1200
  tasks: 2
  commits: 3
  plan_head_before: 9b0582ad87092681d04ca79c1283c3e6abe223d1

tech-stack:
  added: []
  patterns:
    - "docs/DEV.md 'settled by observation' subsection pattern: transcribe a prior plan's confirmed RESEARCH.md assumptions/open-questions into the dev guide rather than re-deriving them, with a citation back to the SUMMARY that confirmed them."
    - "docs/DEV.md visual-verification subsection quotes the human's exact confirmation words rather than paraphrasing, so a later reader can tell the difference between 'Claude inferred this' and 'a person said this'."

key-files:
  created: []
  modified:
    - docs/DEV.md

key-decisions:
  - "Task 1 (add the display-name translation line) was already fully satisfied by plan 02-01, which pulled D-07's translation entry forward while building TransitChartModelProvider. Re-ran all four of Task 1's verify assertions against the current tree and all four passed with zero code changes needed; no duplicate commit was made."
  - "The worktree's gsd-dev save world (D-05's designated, reused test world) does not exist inside a fresh worktree checkout, because run/ is gitignored and git worktrees do not share working-tree content outside .git. Copied the existing world folder from the main checkout into this worktree's run/saves/ rather than let the client create a new world (which D-05 explicitly forbids) or halt on what is an infrastructure quirk, not a substantive missing prerequisite."
  - "The first ./gradlew runClient session ran fully unattended (auto-loaded gsd-dev, player fell out of the world, client shut itself down after ~2 minutes with no placement made) before the user was actually at the keyboard. Did not infer a pass/fail from that session; relaunched a second session once a live human was confirmed present, and recorded only what the user actually reported."

requirements-completed: [BLOCK-01, BLOCK-02, BLOCK-03]

coverage:
  - id: D1
    description: "Block's display-name translation entry exists and resolves to \"Transit Chart\" in the generated language file (D-01, D-07)"
    requirement: "BLOCK-02"
    verification:
      - kind: unit
        ref: "node -e language-file assertion (Task 1 verify block) — exact two-key check against src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json"
        status: pass
    human_judgment: false
  - id: D2
    description: "docs/DEV.md lists every file ./gradlew runDatagen now produces and records the settled Phase 2 data-generation findings"
    requirement: null
    verification:
      - kind: unit
        ref: "grep assertions for blockstates/transit_chart.json, models/block/transit_chart.json, models/item/transit_chart.json, ORIENTABLE_ONLY_TOP, and absence of machine path/username in docs/DEV.md"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dev client launches with this mod loaded and completes a session without a crash report"
    requirement: null
    verification:
      - kind: integration
        ref: "run/logs/latest.log grep for 'Minecraft 1.20.1' and 'Hello Fabric world!'; test ! -e run/crash-reports (both runClient sessions)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Placed block draws a real model on every face (including underside), item draws a real icon, and orients to face the player from all 4 directions with no checkerboard anywhere (BLOCK-01, BLOCK-02, BLOCK-03, D-04, D-05, ROADMAP Phase 2 criteria 1-3)"
    requirement: "BLOCK-01, BLOCK-03"
    verification:
      - kind: manual_procedural
        ref: "User placed the block from all 4 horizontal directions, checked all 6 faces of a placed block (including the underside), and read the item name in the creative tab and hotbar tooltip in a live ./gradlew runClient session against the gsd-dev world. Exact confirmation: \"yes its working as expected\"."
        status: pass
    human_judgment: true
    rationale: "D-05 makes this an explicitly visual-only check by design (no F3 readout as an automated substitute). Automated verification (log grep, generated-JSON assertions) proves the block registers and models are structurally correct but cannot prove what actually renders on screen or which way it faces — only a human watching the running game window can confirm that. Recorded here as pass because a human did exactly that and reported the result verbatim."

duration: 19min
completed: 2026-09-08
status: complete
---

# Phase 2 Plan 2: Block Exists and Places (Task 1+2) Summary

**docs/DEV.md now documents the full Phase 2 datagen output and settled findings, plus the human-confirmed D-05 visual check ("yes its working as expected" — 4-direction facing, no checkerboard, correct "Transit Chart" name); the D-07 translation line itself was already delivered by plan 02-01.**

## Performance

- **Duration:** 19 min
- **Started:** 2026-09-08T06:20:00Z (approx, worktree fast-forward)
- **Completed:** 2026-09-08T06:39:00Z
- **Tasks:** 2 (Task 1 pre-satisfied by 02-01; Task 2 completed across two `runClient` sessions)
- **Files modified:** 1 (`docs/DEV.md`)

## Accomplishments

- Confirmed, by re-running all four of Task 1's automated verify assertions, that plan 02-01 already added the D-07 display-name translation line (`block.jollyalchemy-transit-report.transit_chart` → `"Transit Chart"`) while building `TransitChartModelProvider` — the language file still has exactly two entries, `runDatagen` is clean, and the entry is tracked by git. No new commit was needed for Task 1.
- Rewrote `docs/DEV.md`'s "Running data generation" file list from the stale two-item Phase 1 list to the current five-entry list (blockstate, block model, item model, lang file, cache directory), each attributed to the provider that produces it.
- Added a "Phase 2 data-generation findings" subsection to `docs/DEV.md` transcribing 02-01's confirmed answers to RESEARCH.md Assumption A1 (Fabric auto-generates the item model when `generateItemModels` is left empty) and Open Question 1 (`createHorizontallyRotatedBlock` + `TexturedModel.ORIENTABLE_ONLY_TOP` ran clean end to end), plus the one-line rejection reasons for `createFurnace` (hardcoded `LIT` dispatch) and `TexturedModel.ORIENTABLE` (missing `BOTTOM` texture slot).
- Launched `./gradlew runClient` in the background twice, each against a freshly deleted `run/logs/latest.log`; confirmed the Minecraft 1.20.1 version line, the mod's `Hello Fabric world!` entrypoint line, and the absence of any `run/crash-reports` directory in both sessions.
- **Obtained live human confirmation of the D-05 visual check** in the second session: the user placed the block from all four horizontal directions, inspected all six faces (including the underside) for the missing-texture checkerboard, and read the item name in the creative tab and hotbar. Verbatim response: **"yes its working as expected."**

## Task Commits

1. **Task 1: Give the block its display name** — no commit. Fully satisfied by plan 02-01's prior work; all four verify assertions passed against the unmodified tree. The only artifact of running this task's verification was a `.cache/` timestamp diff from re-running `runDatagen`, which was discarded via `git checkout --` as harmless regeneration noise (documented behavior, not new content).
2. **Task 2: Confirm the block in a running dev client and record findings** — `34decca` (docs, automatable portion: file-list + findings), `5fd8376` (docs, human-confirmed D-05 result).

**Plan metadata:** this SUMMARY's own commit (made after this document).

## Files Created/Modified

- `docs/DEV.md` — generated-file list brought current (3 new entries), new "Phase 2 data-generation findings" subsection, new "Phase 2 visual verification (D-05)" subsection recording the human-confirmed result verbatim.

## Decisions Made

- Task 1 required no code change: plan 02-01 pulled D-07's translation line forward while it built the model provider (see 02-01-SUMMARY.md's Task 1 notes). Verified rather than assumed, by re-running every one of Task 1's `<verify>` assertions from this plan against the current tree.
- The `gsd-dev` reusable dev world (D-05's designated test world) is gitignored and therefore worktree-local; a fresh worktree checkout does not have it. Copied it from the main checkout's `run/saves/gsd-dev` into this worktree's `run/saves/` rather than create a new world (explicitly forbidden by D-05) or halt on an infrastructure gap that has a safe, mechanical, non-destructive fix (Rule 3 — same class of issue plan 02-01 hit with its stale branch base).
- Did not infer a result from the first, unattended `runClient` session (world auto-loaded, player fell out, client shut itself down after ~2 minutes with no placement). Relaunched a fresh session once a live human was confirmed present and recorded only their direct report, per the plan's explicit prohibition against claiming visual criteria verified on anything short of what a human actually reported seeing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Worktree branch was 2 commits deep, predating all Phase 1/2 work**
- **Found during:** Initial file reads, before Task 1 began.
- **Issue:** This plan's worktree (`worktree-agent-aa82f8d50afb1e70a`) had `HEAD` at `1948547` ("Initial template from Fabric"), identical to the stale state plan 02-01's worktree started from. Local `main` had already advanced to `9b0582a` (plan 02-01 merged, STATE.md advanced to plan 02-02). None of `TransitChartBlock`, `TransitReportBlocks`, `TransitChartModelProvider`, the generated JSON, or `docs/DEV.md`'s current content existed in the worktree as checked out.
- **Fix:** Verified `git merge-base --is-ancestor HEAD main` confirmed the worktree's `HEAD` was a strict, divergence-free ancestor of `main` (zero worktree-local commits), then ran `git merge --ff-only main` — a lossless fast-forward bringing in only commits already in the repository's object database.
- **Files affected:** none directly edited by the fix; the fast-forward brought in all pre-existing Phase 1/2 work (identical in kind to plan 02-01's own deviation #1).
- **Commit:** not a separate commit — fast-forward updated the branch pointer directly; no new commit object was created.

**2. [Rule 3 - Blocking issue] Precondition unmet: `run/saves/gsd-dev/level.dat` did not exist in this worktree**
- **Found during:** Task 2, precondition check, before launching the dev client.
- **Issue:** The plan's Task 2 precondition requires the Phase 1 `gsd-dev` reusable Creative Superflat world to exist at `run/saves/gsd-dev`. It did not exist in this worktree's `run/` folder — `run/` is gitignored, and git worktrees only share `.git`, not working-tree content, so an artifact created in the main checkout during Phase 1 verification is invisible to a fresh worktree.
- **Fix:** Confirmed the world existed, unmodified, in the main checkout's `run/saves/gsd-dev`, then copied that folder (read-only on the source, purely additive on the destination) into this worktree's `run/saves/gsd-dev`. This restores the exact same Phase-1-created world for reuse, rather than fabricating a new one (which D-05 explicitly forbids) or leaving a mechanically-fixable infrastructure gap unresolved.
- **Files affected:** `run/saves/gsd-dev/**` — gitignored runtime artifact, not tracked, not part of any commit.
- **Commit:** none — this is untracked runtime state, consistent with `run/`'s gitignore status.

**3. [Rule 3 - Blocking issue] First `runClient` session ran unattended before a human was present**
- **Found during:** Task 2, after launching the dev client the first time.
- **Issue:** The first background `./gradlew runClient` session auto-loaded `gsd-dev`, the player fell out of the world at spawn, and the client disconnected and shut down cleanly on its own after roughly two minutes — with no placement action taken and no human watching in this execution context at that point.
- **Fix:** Did not treat the clean shutdown as any kind of pass/fail signal for D-05. Deleted `run/logs/latest.log` again and relaunched `./gradlew runClient` in the background a second time once a live human was confirmed present via the coordinator, then handed the running window to them for the actual check.
- **Files affected:** none — `run/logs/latest.log` and the game session are gitignored runtime state.
- **Commit:** none directly; the eventual confirmed result is recorded in commit `5fd8376`.

None of Rules 1, 2, or 4 were triggered. No architectural decision was required.

## Known Stubs

None. D-05's visual check is now confirmed (see coverage D4); no verification gate remains open for this plan.

## Threat Flags

None. This plan's only file change (`docs/DEV.md`) is prose documentation with no new network, file-access, or trust-boundary surface, matching the plan's own threat model (all threats `accept` or `low`/`mitigate` with no `high`/`critical` entries).

## Self-Check: PASSED

- `docs/DEV.md` — FOUND, contains `blockstates/transit_chart.json`, `models/block/transit_chart.json`, `models/item/transit_chart.json`, `ORIENTABLE_ONLY_TOP`, and the user's verbatim D-05 confirmation; no machine path or username present.
- Commit `34decca` — FOUND in `git log --oneline`.
- Commit `5fd8376` — FOUND in `git log --oneline`.
- `run/logs/latest.log` (second session) — FOUND, contains the Minecraft 1.20.1 version line and `Hello Fabric world!`; `run/crash-reports` does not exist.
- `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` — FOUND, exactly two keys, `block.jollyalchemy-transit-report.transit_chart` → `Transit Chart` (pre-existing from plan 02-01, re-verified in this plan).

## Issues Encountered

- The first `runClient` session ran headlessly with no human present and shut itself down after ~2 minutes with no block placed. Resolved by relaunching a second session once a live human was confirmed present (see Deviation #3). Not a code defect.
- Standard offline-dev-client noise appeared in both log sessions (`InvalidCredentialsException: Status: 401` on Mojang auth, a Realms JWT parse failure, missing vanilla goat-horn sounds, a shader sampler warning) — all expected for a local dev environment not logged into a real Mojang account, none referencing `transitreport` or `TransitChartBlock`, and none affecting the mod.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 2 is fully closed: all four ROADMAP Phase 2 success criteria are satisfied — the block places from the creative tab named "Transit Chart" (criterion 1), orients distinguishably from all four directions (criterion 2), draws a real model on every face including the underside with a real hotbar icon (criterion 3), and no hand-written blockstate/model JSON exists anywhere in the repo (criterion 4, confirmed in 02-01).
- `docs/DEV.md` now accurately documents what `./gradlew runDatagen` produces, the settled 1.20.1 datagen findings future phases would otherwise re-derive, and the confirmed D-05 visual result.
- Phase 3 (crafting recipe, loot table, GEN-05 translations) and Phase 4 (renderer, which now has a confirmed-correct facing state to key off) can both proceed without any open verification gate from this phase.

---
*Phase: 02-block-exists-and-places*
*Completed: 2026-09-08*

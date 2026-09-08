---
phase: 02-block-exists-and-places
plan: 01
subsystem: block-registration
tags: [fabric, blockstate, datagen, block-registration]
status: complete
dependency-graph:
  requires:
    - "Phase 01: TransitReportLanguageProvider skeleton, JollyalchemyTransitReport.id() helper, configureDataGeneration{client=true}"
  provides:
    - "TransitChartBlock (extends HorizontalDirectionalBlock, 4-way FACING)"
    - "TransitReportBlocks registration holder (jollyalchemy-transit-report:transit_chart block + item)"
    - "Generated blockstate/block-model/item-model JSON for transit_chart"
  affects:
    - "src/main/java/transitreport/JollyalchemyTransitReport.java"
    - "src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java"
tech-stack:
  added: []
  patterns:
    - "Registration holder class with explicit register() called from onInitialize() (avoids Java static-init gotcha)"
    - "FabricModelProvider nested class mirroring the existing FabricLanguageProvider nested-class shape"
key-files:
  created:
    - src/main/java/transitreport/block/TransitChartBlock.java
    - src/main/java/transitreport/TransitReportBlocks.java
  modified:
    - src/main/java/transitreport/JollyalchemyTransitReport.java
    - src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
    - src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json
    - src/main/generated/assets/jollyalchemy-transit-report/models/block/transit_chart.json
    - src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json
    - src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
decisions:
  - "Worktree was based on a stale point (2 commits, pre-Phase-1) while local main had advanced to b49a168 with all Phase 1 work and Phase 2 planning docs. Verified HEAD was a strict ancestor of main (no divergent worktree commits) and fast-forwarded the worktree branch to main tip before starting Task 1 — a lossless, non-destructive operation, not a workaround."
  - "RESEARCH.md Assumption A1 CONFIRMED: leaving generateItemModels empty produced the auto-generated parented item model exactly as predicted, on the first runDatagen run."
  - "RESEARCH.md Open Question 1 CONFIRMED: createHorizontallyRotatedBlock + TexturedModel.ORIENTABLE_ONLY_TOP ran runDatagen clean end to end on the first attempt — no deviation was needed."
actuals:
  tokens: 2601
  tasks: 2
  commits: 2
  plan_head_before: b49a16834c7b756544dcce1e2de4ed82e5cefb90
metrics:
  duration: 9min
  completed: 2026-09-08
---

# Phase 2 Plan 1: Block Exists and Places (Task 1+2) Summary

Registered `TransitChartBlock` (extends `HorizontalDirectionalBlock`, 4-way facing derived from the
placing player's look), wired it into the vanilla Functional Blocks creative tab, and generated its
blockstate/block-model/item-model JSON via `createHorizontallyRotatedBlock` + `TexturedModel.ORIENTABLE_ONLY_TOP`
against borrowed vanilla furnace textures — reproducibility of that generated JSON was proven by deleting
`src/main/generated` and diffing byte-identical output after a fresh `runDatagen`.

## What Was Built

**Task 1 — end-to-end registration slice:**
- `src/main/java/transitreport/block/TransitChartBlock.java` (new): `extends HorizontalDirectionalBlock`.
  Constructor registers the default state with `FACING = Direction.NORTH`. `createBlockStateDefinition`
  adds only `FACING`. `getStateForPlacement` returns
  `defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite())` — the furnace/chest
  convention (D-04): the block's front looks back at the placing player. `rotate`/`mirror` are inherited,
  unoverridden.
- `src/main/java/transitreport/TransitReportBlocks.java` (new): holder with `public static final Block
  TRANSIT_CHART` (`strength(1.5F)`, `sound(SoundType.AMETHYST)`, no `requiresCorrectToolForDrops`/`lightLevel`/
  `noOcclusion` per D-10) and `public static final Item TRANSIT_CHART_ITEM`. `register()` calls
  `Registry.register` for both under `JollyalchemyTransitReport.id("transit_chart")`, then registers the
  `CreativeModeTabs.FUNCTIONAL_BLOCKS` item-group hook (D-06).
- `JollyalchemyTransitReport.onInitialize()`: added `TransitReportBlocks.register();` after the existing
  `LOGGER.info("Hello Fabric world!")` line (preserved, not replaced).
- `JollyalchemyTransitReportDataGenerator.java`: added a second nested `FabricModelProvider` subclass,
  `TransitChartModelProvider`, mirroring the existing `TransitReportLanguageProvider` shape. Its
  `generateBlockStateModels` calls `blockModelGenerators.createHorizontallyRotatedBlock(TRANSIT_CHART,
  TexturedModel.ORIENTABLE_ONLY_TOP.updateTexture(...))` mapping FRONT/SIDE/TOP to
  `minecraft:block/furnace_{front,side,top}`. `generateItemModels` left intentionally empty. Registered via
  `pack.addProvider(TransitChartModelProvider::new)`. Also added the D-07 translation line
  `block.jollyalchemy-transit-report.transit_chart` → `"Transit Chart"` to the existing language provider.
- Ran `./gradlew runDatagen` then `./gradlew build` — both green on the first attempt.

**Task 2 — structural proof, tracking, and reproducibility:**
- Verified (by automated `node -e` assertion, matching the plan's `<verify>` block) the blockstate has exactly
  the four `facing=` variants with distinct y-rotations 0/90/180/270, the block model parents
  `minecraft:block/orientable` with exactly the three texture keys `front`/`side`/`top` pointing at the
  vanilla furnace textures, and the item model parents `jollyalchemy-transit-report:block/transit_chart`.
- Confirmed all three generated files are tracked via `git ls-files --error-unmatch`.
- Proved reproducibility: copied the three files aside, deleted `src/main/generated` entirely, re-ran
  `./gradlew runDatagen`, and diffed each file against its saved copy — all three came back byte-identical.
  Only `src/main/generated/.cache/*` differed (a regeneration timestamp line — expected, documented in
  RESEARCH.md and 02-CONTEXT.md as harmless).
- Confirmed `git ls-files src/main/resources/assets/jollyalchemy-transit-report/{blockstates,models}` returns
  nothing — ROADMAP Phase 2 criterion 4 holds: no hand-written blockstate/model JSON exists anywhere in the
  repo.

## Exact Generated Content (recorded per plan's `<output>` requirement)

**`src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json`** (verbatim):
```json
{
  "parent": "jollyalchemy-transit-report:block/transit_chart"
}
```
**RESEARCH.md Assumption A1 — CONFIRMED.** Fabric's model provider auto-generated this parented item model
with zero code in `generateItemModels` (which was left intentionally empty, per the plan). No custom
mechanism was needed; GEN-02 is satisfied by the auto-generation path exactly as RESEARCH.md predicted.

**`src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json`** (verbatim, so
Phase 4 can read the facing-to-rotation mapping without re-deriving it):
```json
{
  "variants": {
    "facing=east": {
      "model": "jollyalchemy-transit-report:block/transit_chart",
      "y": 90
    },
    "facing=north": {
      "model": "jollyalchemy-transit-report:block/transit_chart"
    },
    "facing=south": {
      "model": "jollyalchemy-transit-report:block/transit_chart",
      "y": 180
    },
    "facing=west": {
      "model": "jollyalchemy-transit-report:block/transit_chart",
      "y": 270
    }
  }
}
```
(`facing=north` has no `y` key — an absent key means y=0, matching the plan's "usually written as an
absent `y` key" expectation.)

**`src/main/generated/assets/jollyalchemy-transit-report/models/block/transit_chart.json`** (verbatim):
```json
{
  "parent": "minecraft:block/orientable",
  "textures": {
    "front": "minecraft:block/furnace_front",
    "side": "minecraft:block/furnace_side",
    "top": "minecraft:block/furnace_top"
  }
}
```

## Open Question Resolution (RESEARCH.md Open Question 1)

**Did `runDatagen` succeed with `createHorizontallyRotatedBlock` + `ORIENTABLE_ONLY_TOP` end to end on the
first attempt?** Yes — confirmed by observation. `./gradlew runDatagen` exited 0 on the very first run
after writing `TransitChartBlock`, `TransitReportBlocks`, and `TransitChartModelProvider`, with no thrown
exception during model generation and no deviation needed. The bytecode-verified helper choice from
RESEARCH.md was correct as written.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Worktree was based on a stale commit, missing all of Phase 1's code**
- **Found during:** Initial file reads, before Task 1 began.
- **Issue:** This plan's worktree (`worktree-agent-aa5d192c938dfcf5f`) had `HEAD` at `1948547` ("Initial
  template from Fabric") — 2 commits deep, predating all of Phase 1's toolchain work (the datagen
  language provider, `docs/DEV.md`, `build.gradle`'s `configureDataGeneration` block, the `fabric.mod.json`
  rename, Mod Menu dependency, etc.) and all of Phase 2's planning docs. Local `main`, by contrast, was at
  `b49a168` with all of that work landed. The datagen entrypoint file this plan's `<read_first>` and
  `<action>` sections describe as already having `TransitReportLanguageProvider` was, in the worktree, a
  bare empty stub — this plan's Task 1 cannot be executed as written against that stale base.
- **Fix:** Verified `git merge-base --is-ancestor HEAD main` confirmed the worktree's `HEAD` was a strict,
  divergence-free ancestor of local `main` (the worktree had made zero commits of its own beyond that shared
  base). Discarded the one in-progress uncommitted edit to `JollyalchemyTransitReport.java` with
  `git checkout -- <path>` (sanctioned single-file discard), then ran `git merge --ff-only main` — a
  lossless fast-forward that only added commits already present in the repository's object database, with
  no rebase, no reset, and no risk to any other worktree's history. Re-applied the block-registration edit
  afterward against the now-correct file. Updated the plan-head-before ledger and cwd-drift sentinel to the
  new `HEAD` (`b49a168`) so Task-commit counting in this SUMMARY measures only this plan's own commits, not
  the merge.
- **Files affected:** none directly edited by the fix; the fast-forward brought in all of `.claude/CLAUDE.md`,
  `.planning/**`, `build.gradle`, `docs/DEV.md`, `src/client/.../JollyalchemyTransitReportDataGenerator.java`
  (language provider), `src/main/generated/**` (lang file + cache), and `src/main/resources/fabric.mod.json`
  — all pre-existing Phase 1 work, not new content authored by this plan.
- **Commit:** not a separate commit — the fast-forward updated the branch pointer directly; no new commit
  object was created by this fix, and the merge is visible in the worktree's branch history as the existing
  Phase 1/2 commits, not as a new merge commit (fast-forward, no merge commit).

None of Rules 1, 2, or 4 were triggered. No architectural decision was required.

## Known Stubs

None. Nothing in this plan's scope stubs data intended to flow to a later phase — the borrowed furnace
textures and empty `generateItemModels` are both explicit, intentional, documented decisions (D-03, and
RESEARCH.md's auto-generation mechanism respectively), not placeholders awaiting real content.

## Threat Flags

None. This plan's threat model (compile-time block/item registration plus build-time JSON generation, no
network/file/cross-trust-boundary input) was fully accepted at `low` severity in the plan itself; nothing
built here introduces surface beyond what was already registered there.

## Self-Check: PASSED

- `src/main/java/transitreport/block/TransitChartBlock.java` — FOUND
- `src/main/java/transitreport/TransitReportBlocks.java` — FOUND
- `src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json` — FOUND
- `src/main/generated/assets/jollyalchemy-transit-report/models/block/transit_chart.json` — FOUND
- `src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json` — FOUND
- Commit `882a962` — FOUND in `git log --oneline`
- Commit `bd6fa86` — FOUND in `git log --oneline`
- `./gradlew build` — BUILD SUCCESSFUL (re-verified after the reproducibility delete/regenerate cycle)

---
phase: 02-block-exists-and-places
verified: 2026-09-08T14:10:00Z
status: passed
score: 9/9 must-haves verified
covered_files:
  - ".planning/REQUIREMENTS.md"
  - ".planning/phases/02-block-exists-and-places/02-01-PLAN.md"
  - ".planning/phases/02-block-exists-and-places/02-01-SUMMARY.md"
  - ".planning/phases/02-block-exists-and-places/02-02-PLAN.md"
  - ".planning/phases/02-block-exists-and-places/02-02-SUMMARY.md"
  - ".planning/phases/02-block-exists-and-places/02-REVIEW.md"
  - "docs/DEV.md"
  - "src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java"
  - "src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json"
  - "src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json"
  - "src/main/generated/assets/jollyalchemy-transit-report/models/block/transit_chart.json"
  - "src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json"
  - "src/main/java/transitreport/JollyalchemyTransitReport.java"
  - "src/main/java/transitreport/TransitReportBlocks.java"
  - "src/main/java/transitreport/block/TransitChartBlock.java"
covered_digest: "v1:sha256:adc9e16d2b54c859eb46d51ee4550261e7d45c5ca340926c4c5b30597bb57802"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 2: Block Exists and Places Verification Report

**Phase Goal:** A display block exists in the game, can be taken from the creative inventory, and places itself facing the player
**Verified:** 2026-09-08T14:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Note on ROADMAP goal / User Story format

Every phase in ROADMAP.md carries `Mode: mvp`, but the Phase 2 `**Goal:**` line is written as an
outcome statement ("A display block exists...") rather than the literal `As a / I want to / so
that` User Story form the MVP-mode verification path expects. Both plans explicitly acknowledge
this in their own `<objective>` provenance notes ("this story is planner-derived from the ROADMAP
Phase 2 goal, not lifted from it... written as an outcome, not in As a/I want to/so that form").
This is a deliberate, project-wide convention (every phase in this roadmap is written the same
way), not an oversight in this phase specifically. Rather than block verification on a formatting
convention the project has knowingly and consistently chosen, this report proceeds with standard
goal-backward verification against the ROADMAP's four Success Criteria (the actual contract) and
each plan's `must_haves`. This is recorded as an informational note, not a gap.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Player finds the display block in a creative inventory group and places it in the world (ROADMAP SC1; BLOCK-01, BLOCK-02) | ✓ VERIFIED | `TransitReportBlocks.register()` hooks `ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)`; called from `onInitialize()`. Human confirmed live in `runClient`: found block in Functional Blocks tab, placed it (02-02-SUMMARY.md, verbatim: "yes its working as expected") |
| 2 | The placed block orients to whichever of the four horizontal directions the player was facing, observably different in all four cases (ROADMAP SC2; BLOCK-03, D-04) | ✓ VERIFIED | `TransitChartBlock.getStateForPlacement` returns `context.getHorizontalDirection().getOpposite()`; generated blockstate carries 4 distinct y-rotations (0/90/180/270) verified directly by reading the JSON (see Data-Flow Trace). Human confirmed all 4 placements' fronts tracked back toward the player, visibly distinct from each other |
| 3 | The placed block draws a real model (not the missing-model checkerboard), and the item draws a real icon in the hotbar (ROADMAP SC3) | ✓ VERIFIED | Block model parents `minecraft:block/orientable` with 3 real vanilla furnace textures (verified by reading generated JSON directly); item model auto-generated as a parent reference. Human confirmed no checkerboard on any face including the underside and top, and read the item name correctly in tab + hotbar tooltip |
| 4 | Blockstate, block model, and item model JSON exist under `src/main/generated`, no hand-written equivalent under `src/main/resources` (ROADMAP SC4; GEN-01, GEN-02) | ✓ VERIFIED | All three files confirmed to exist, structurally correct, and git-tracked. `git ls-files src/main/resources/.../blockstates src/main/resources/.../models` returns empty — independently re-run by this verifier, not just cited from SUMMARY |
| 5 | `TransitChartBlock` extends `HorizontalDirectionalBlock`, registers a `NORTH` default state, overrides only `createBlockStateDefinition`/`getStateForPlacement`, inherits `rotate`/`mirror` (D-08) | ✓ VERIFIED | Read source directly: no `rotate`/`mirror` override present; `registerDefaultState` sets `FACING` to `Direction.NORTH` in the constructor |
| 6 | Generated JSON is reproducible from the provider alone — deleting `src/main/generated` and re-running `runDatagen` reproduces byte-identical output | ✓ VERIFIED | Independently reproduced by this verifier: deleted `src/main/generated`, ran `./gradlew runDatagen --offline` (exit 0), diffed all 4 regenerated files against saved copies — content identical (only CRLF/LF line-ending artifacts from the `cp` step, confirmed via `git diff` showing zero uncommitted diff after checkout). Working tree restored to clean via `git checkout -- src/main/generated` |
| 7 | The creative-tab entry, hotbar item name, and placed block's name all read `Transit Chart` — never the raw key, never `Transit Display`/`Transit Report` (D-01, D-07) | ✓ VERIFIED | `en_us.json` maps `block.jollyalchemy-transit-report.transit_chart` → `"Transit Chart"` exactly, exactly 2 keys total (no Phase 3 scope leak). Human confirmed reading `Transit Chart` in both tab and hotbar |
| 8 | `./gradlew build` succeeds with this phase's code in the tree | ✓ VERIFIED | Independently re-run by this verifier: `./gradlew build --offline` → `BUILD SUCCESSFUL` |
| 9 | `docs/DEV.md` documents every file `runDatagen` now produces and the settled Phase 2 datagen findings, with no machine path/username | ✓ VERIFIED | Read `docs/DEV.md` directly: lists all 3 new generated files plus lang/cache, records A1/Open Question findings and rejected-helper reasons, records the human's verbatim visual-check confirmation; `grep` for `C:\Users`, `/c/Users`, `nneib` returns nothing |

**Score:** 9/9 truths verified (0 present-but-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/main/java/transitreport/block/TransitChartBlock.java` | 4-way horizontal facing block class | ✓ VERIFIED | Extends `HorizontalDirectionalBlock`; contains `context.getHorizontalDirection().getOpposite()`, `registerDefaultState`; no `rotate`/`mirror` override |
| `src/main/java/transitreport/TransitReportBlocks.java` | Registration holder + creative-tab hook | ✓ VERIFIED | `TRANSIT_CHART`/`TRANSIT_CHART_ITEM` fields, `register()` calling `Registry.register` twice + `ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)`; `strength(1.5F)`, `sound(SoundType.AMETHYST)`; no `requiresCorrectToolForDrops`/`lightLevel`/`noOcclusion` |
| `src/main/java/transitreport/JollyalchemyTransitReport.java` | Explicit registration call from `onInitialize()` | ✓ VERIFIED | `TransitReportBlocks.register();` present after the preserved `"Hello Fabric world!"` line |
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` | Model + language provider wiring | ✓ VERIFIED | `TransitChartModelProvider` uses `createHorizontallyRotatedBlock` + `TexturedModel.ORIENTABLE_ONLY_TOP`; registered via `pack.addProvider(TransitChartModelProvider::new)`; translation line added to the existing language provider |
| `src/main/generated/.../blockstates/transit_chart.json` | 4-variant facing dispatch | ✓ VERIFIED | Exactly `facing=north/south/east/west`, model `jollyalchemy-transit-report:block/transit_chart`, y-rotations 0/90/180/270 |
| `src/main/generated/.../models/block/transit_chart.json` | 3-slot orientable model | ✓ VERIFIED | `parent: minecraft:block/orientable`, textures = exactly `front`/`side`/`top` → vanilla furnace textures |
| `src/main/generated/.../models/item/transit_chart.json` | Item model parented to block model | ✓ VERIFIED | `{"parent": "jollyalchemy-transit-report:block/transit_chart"}` — auto-generated, `generateItemModels` intentionally empty |
| `docs/DEV.md` | Developer guide with generated-file list + findings | ✓ VERIFIED | Contains all 3 new generated paths, `ORIENTABLE_ONLY_TOP`, no machine path/username |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `JollyalchemyTransitReport.java` | `TransitReportBlocks.java` | `onInitialize()` calls `TransitReportBlocks.register()` | ✓ WIRED | Confirmed by direct read |
| `TransitReportBlocks.java` | `TransitChartBlock.java` | `TRANSIT_CHART = new TransitChartBlock(...)` | ✓ WIRED | Confirmed by direct read |
| `JollyalchemyTransitReportDataGenerator.java` | `TransitReportBlocks.java` | `createHorizontallyRotatedBlock(TransitReportBlocks.TRANSIT_CHART, ...)` | ✓ WIRED | Confirmed by direct read; cross-source-set static field reference works because the field is `public static final` |
| `blockstates/transit_chart.json` | `models/block/transit_chart.json` | every variant names `jollyalchemy-transit-report:block/transit_chart` | ✓ WIRED | Confirmed by direct read of generated JSON |
| `models/item/transit_chart.json` | `models/block/transit_chart.json` | `parent` field | ✓ WIRED | Confirmed by direct read |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| Generated blockstate | `variants` | `BlockModelGenerators.createHorizontallyRotatedBlock` run against `TransitChartBlock`'s real `FACING` state definition | Yes — re-run independently by this verifier via delete + `runDatagen`, byte-identical | ✓ FLOWING |
| Generated block model | `textures` | `TexturedModel.ORIENTABLE_ONLY_TOP.updateTexture(...)` mapping to real vanilla furnace texture paths that ship with the base game | Yes | ✓ FLOWING |
| Generated item model | `parent` | Fabric's auto-item-model mechanism, keyed off the same `TRANSIT_CHART` block instance | Yes | ✓ FLOWING |
| Generated language file | block display-name entry | `TransitReportLanguageProvider.generateTranslations`, key built via `JollyalchemyTransitReport.MOD_ID` concatenation (not hardcoded) | Yes | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Build succeeds with Phase 2 code in tree | `./gradlew build --offline` | `BUILD SUCCESSFUL in 933ms` | ✓ PASS |
| Datagen reproduces generated JSON byte-for-byte from the provider alone | delete `src/main/generated`; `./gradlew runDatagen --offline`; diff against saved copies; `git diff` after re-checkout | Exit 0, no uncommitted content diff (only CRLF/LF noise from the intermediate `cp`, resolved to zero diff against the committed HEAD) | ✓ PASS |
| No hand-written blockstate/model JSON exists under `src/main/resources` | `git ls-files src/main/resources/.../blockstates src/main/resources/.../models` | Empty output | ✓ PASS |
| Generated JSON tracked by git | `git ls-files --error-unmatch` against all 3 generated paths + lang file | Exit 0, all 4 listed | ✓ PASS |

Placement/facing/visual rendering behavior itself (block appearing correctly on screen, orientation
visibly tracking the player, no checkerboard) is explicitly out of scope for automated spot-checks
per this project's own convention (CLAUDE.md §7) — that evidence comes from the recorded human
confirmation in 02-02-SUMMARY.md instead (see Human Verification note below).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|--------------|------------|-------------|--------|----------|
| BLOCK-01 | 02-01, 02-02 | Player can place the display block in the world | ✓ SATISFIED | `getStateForPlacement` + creative-tab registration; human-confirmed placement in 4 directions |
| BLOCK-02 | 02-01, 02-02 | The display block appears as an item in a creative inventory group | ✓ SATISFIED | `ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)`; human confirmed item present, named `Transit Chart` |
| BLOCK-03 | 02-01, 02-02 | Block stores a 4-way horizontal facing state, set from placement direction | ✓ SATISFIED | `createBlockStateDefinition` adds only `FACING`; `getStateForPlacement` derives it from the placing player's look; human confirmed 4 distinguishable orientations |
| GEN-01 | 02-01 | Blockstate and block model JSON produced by data generation, not hand-written | ✓ SATISFIED | Generated files confirmed structurally correct and reproducible; zero hand-written equivalents under `src/main/resources` |
| GEN-02 | 02-01 | Item model JSON produced by data generation | ✓ SATISFIED | Item model auto-generated via Fabric's mechanism, confirmed present and correctly parented |

No orphaned requirements: REQUIREMENTS.md maps only BLOCK-01, BLOCK-02, BLOCK-03, GEN-01, GEN-02 to
Phase 2, and all five appear in at least one plan's `requirements` frontmatter.

**Documentation staleness note (informational, not a code gap):** `REQUIREMENTS.md`'s checkboxes for
BLOCK-01/02/03 and GEN-01/02 are still shown as `[ ]` unchecked, `ROADMAP.md`'s Phase 2 entry still
shows "Plans: 1/2 plans executed" and plan `02-02-PLAN.md` unchecked, and `STATE.md` still describes
Phase 2 as "Ready to execute" at 0% progress — all three tracking documents are stale relative to
the actual, fully-committed state of the codebase (both plans executed, both SUMMARYs written, code
review done, all commits present in `git log`). This is a documentation bookkeeping gap, not a
functional gap in the delivered block; it does not affect the phase goal, which the code and human
confirmation above satisfy. Recommend updating ROADMAP.md/STATE.md/REQUIREMENTS.md checkboxes before
starting Phase 3 so the next phase's context-gathering step doesn't inherit a false "not started"
signal.

### Anti-Patterns Found

None. Scanned all 4 modified/created source files
(`TransitChartBlock.java`, `TransitReportBlocks.java`, `JollyalchemyTransitReport.java`,
`JollyalchemyTransitReportDataGenerator.java`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`,
placeholder-language comments, empty-return stubs, and hardcoded-empty-value patterns — zero matches.

The code review (02-REVIEW.md) separately found 1 Warning (translation key built by string
concatenation instead of the type-safe `add(Block, String)` overload — a maintainability risk if the
registry id is ever renamed, not a functional defect) and 2 Info items (unmodified template log
line; unexplained magic number for block hardness). None are Critical/Blocker, and none block this
phase's goal.

### Human Verification Required

None outstanding. This phase's visual/placement criteria (ROADMAP SC1-3; D-05) were already put to a
human in a running dev client during plan 02-02's execution, and the SUMMARY records a specific,
direct confirmation covering exactly the criteria this phase needs verified: four-direction facing
(front tracked back toward the player, four results visibly distinct), absence of the
missing-texture checkerboard on every face including the underside and top, and the exact display
name `Transit Chart` read in both the creative tab and the hotbar tooltip. Per this verification
task's explicit instruction, that recorded confirmation is treated as valid evidence for those
must-haves rather than re-queued for human verification.

### Gaps Summary

No gaps. All 9 observable truths verified, all artifacts present/substantive/wired/data-flowing, all
key links wired, all 5 requirement IDs satisfied, zero anti-pattern blockers, and the build +
datagen-reproducibility behavioral spot-checks were independently re-run by this verifier (not just
cited from SUMMARY.md) and passed. The only finding worth acting on is the documentation-staleness
note above (ROADMAP/STATE/REQUIREMENTS checkboxes), which is a bookkeeping issue, not a functional
gap, and does not block Phase 3.

---

_Verified: 2026-09-08T14:10:00Z_
_Verifier: Claude (gsd-verifier)_

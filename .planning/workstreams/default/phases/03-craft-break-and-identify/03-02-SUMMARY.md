---
phase: 03-craft-break-and-identify
plan: 02
subsystem: datagen
tags: [fabric-datagen, tooltip, translations, minecraft-1.20.1, block-appendhovertext]

# Dependency graph
requires:
  - phase: 03-craft-break-and-identify
    provides: "Plan 03-01's TransitChartRecipeProvider/TransitChartLootTableProvider nested classes and the confirmed 1.20.1 datagen provider shapes in the same JollyalchemyTransitReportDataGenerator entrypoint file"
provides:
  - "Two-line item tooltip (plain functional line, italic flavour line) attached via Block.appendHoverText (BLOCK-06)"
  - "Two new generated translation keys in en_us.json, added alongside the two pre-existing keys without disturbing them (GEN-05)"
  - "Live-verified survival loop: 2x2-grid craft, break-and-recover with all three tool types, full tooltip text confirmed by a person in a running dev client"
  - "docs/DEV.md Phase 3 findings closing the MEDIUM-confidence FabricRecipeProvider method-shape risk"
affects: []

actuals:
  tokens: 2530
  tasks: 2
  commits: 2

tech-stack:
  added: []
  patterns:
    - "Block.appendHoverText(ItemStack, BlockGetter, List<Component>, TooltipFlag) overridden directly on the block class, not via a BlockItem subclass — BlockItem.appendHoverText already delegates to it"
    - "Tooltip translation keys built via string concatenation from JollyalchemyTransitReport.MOD_ID, matching the language provider's existing key-building convention exactly"

key-files:
  created: []
  modified:
    - src/main/java/transitreport/block/TransitChartBlock.java
    - src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
    - src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
    - docs/DEV.md

key-decisions:
  - "Tooltip attached by overriding Block.appendHoverText on the existing TransitChartBlock rather than introducing a BlockItem subclass — confirmed by disassembly that BlockItem.appendHoverText already forwards to the block, so TransitReportBlocks and the block item's construction stay untouched."
  - "Both tooltip values typed as pure ASCII (ordinary hyphen-minus, commas, periods) per D-01/D-02, verified by a byte-level assertion against the generated en_us.json rather than trusted by eye."

patterns-established: []

requirements-completed: [BLOCK-06, GEN-05]

coverage:
  - id: D1
    description: "Two-line item tooltip wired end to end: appendHoverText override on TransitChartBlock referencing two new translation keys, plain functional line then italic flavour line, no BlockItem subclass introduced (BLOCK-06)"
    requirement: "BLOCK-06"
    verification:
      - kind: other
        ref: "9 grep/test source-assertions against TransitChartBlock.java, TransitReportBlocks.java, and JollyalchemyTransitReportDataGenerator.java (comment-stripped): BlockGetter signature present, exactly 3 @Override annotations, both tooltip keys referenced, ChatFormatting.ITALIC applied, MOD_ID used (not a literal namespace), zero Component.literal calls, BlockItem construction unchanged, translationBuilder.add(...) count = 4"
        status: pass
      - kind: other
        ref: "./gradlew runDatagen and ./gradlew build, both exit 0"
        status: pass
    human_judgment: false
  - id: D2
    description: "Two new tooltip translation keys generated into en_us.json alongside the two pre-existing keys, byte-exact ASCII values, distinct from the reserved refreshing key (GEN-05)"
    requirement: "GEN-05"
    verification:
      - kind: other
        ref: "node -e structural assertion against en_us.json: exact 4-key set with exact values (tooltip/flavor/block-name/refreshing all correct and unchanged)"
        status: pass
      - kind: other
        ref: "node -e ASCII-only + non-empty assertion on both new tooltip values"
        status: pass
      - kind: other
        ref: "node -e distinctness assertion: neither tooltip value equals the reserved refreshing key's value, and the two tooltip values differ from each other"
        status: pass
      - kind: other
        ref: "git ls-files src/main/resources/assets/jollyalchemy-transit-report/lang returns nothing (no hand-written language file tracked)"
        status: pass
    human_judgment: false
  - id: D3
    description: "In-game survival loop confirmed by a person in a running dev client: single-dirt 2x2-grid craft (no table), break-and-recover with bare hand/shovel/pickaxe, and the full tooltip text in both inventory and hotbar"
    requirement: "BLOCK-06"
    verification:
      - kind: manual_procedural
        ref: "Human-check protocol, run/logs/latest.log confirms clean startup with no run/crash-reports; user reported back 'approved' / 'yes it all works!' covering all checks in the plan's <human-check> block"
        status: pass
    human_judgment: true
    rationale: "BLOCK-06's acceptance is what a person reads on screen, per this project's established CLAUDE.md §7 boundary and the D-03/D-04 visual-verification protocol — no Minecraft-side test harness exists or is planned. The automated assertions in D1/D2 prove the generated file holds correct bytes and the block class references correct keys; only a person looking at the running game confirms the two are actually joined at runtime."
---

# Phase 3 Plan 2: Craft, Break, and Identify — Tooltip and Live Verification Summary

**Two-line item tooltip (plain refresh line, italic flavour line) wired via `Block.appendHoverText` and two generated translation keys, confirmed live in a running dev client by the user crafting, breaking, and reading the tooltip.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-09-08T15:20:54Z
- **Completed:** 2026-09-08T15:30:41Z
- **Tasks:** 2
- **Files modified:** 4 unique tracked files (`TransitChartBlock.java`, `JollyalchemyTransitReportDataGenerator.java`, generated `en_us.json`, `docs/DEV.md`), plus 4 datagen `.cache` bookkeeping files re-hashed by the `runDatagen` re-run

## Accomplishments

- `TransitChartBlock` gained a new `appendHoverText(ItemStack, BlockGetter, List<Component>, TooltipFlag)` override — the block-level signature, not the item-level one — adding the functional line plain and the flavour line italic, both as translatable components keyed from `JollyalchemyTransitReport.MOD_ID`. No `BlockItem` subclass was introduced; `TransitReportBlocks` is unchanged.
- `TransitReportLanguageProvider.generateTranslations` grew from two entries to four: the two new tooltip keys (`item.jollyalchemy-transit-report.transit_chart.tooltip` = `Right-click to refresh.`, `item.jollyalchemy-transit-report.transit_chart.flavor` = `What the sky is doing, right now.`) added alongside the pre-existing block-name and refreshing keys, which are byte-identical to before.
- `./gradlew runDatagen` and `./gradlew build` both exit 0; the regenerated `en_us.json` holds exactly the four expected keys with byte-exact ASCII values, and no hand-written language file exists under `src/main/resources/assets`.
- A running dev client (`./gradlew runClient`, `gsd-dev` world) confirmed the whole survival loop live: the user crafted one Transit Chart from a single dirt in the 2x2 inventory grid with no crafting table, read all three tooltip lines in the correct order in both inventory and hotbar with no raw translation key ever visible, and broke the placed block with bare hand, shovel, and pickaxe alike — every break dropped exactly one item — with the recipe also confirmed present in the recipe book.
- `docs/DEV.md` now records the full Phase 3 data-generation output list (recipe, recipe-unlock advancement, loot table, tooltip keys), the settled `FabricRecipeProvider`/`FabricBlockLootTableProvider`/`Block.appendHoverText` findings (closing the MEDIUM-confidence recipe-provider risk STATE.md/ROADMAP.md have carried since roadmap creation), and the Phase 3 visual-verification outcome in the user's own words.

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire the two-line tooltip end to end — block hover-text override plus generated translation keys** - `bd32222` (feat)
2. **Task 2: Verify the whole survival loop and the tooltip in a running dev client, and record the phase's findings in docs/DEV.md** - `ed140da` (docs)

_No separate plan-metadata commit for code — this SUMMARY and STATE/ROADMAP updates land in the final `docs(03-02)` commit._

## Files Created/Modified

- `src/main/java/transitreport/block/TransitChartBlock.java` — added the `appendHoverText` override and its new imports (`ChatFormatting`, `Component`, `ItemStack`, `TooltipFlag`, `BlockGetter`, `java.util.List`, `transitreport.JollyalchemyTransitReport`).
- `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` — added two `translationBuilder.add(...)` calls for the tooltip and flavour keys.
- `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` — regenerated, now holds four keys.
- `src/main/generated/.cache/*` — 4 pre-existing bookkeeping files re-timestamped by the `runDatagen` re-run (no new files this task — the affected providers already existed from plan 03-01).
- `docs/DEV.md` — extended the data-generation file list, added the "Phase 3 data-generation findings" and "Phase 3 visual verification" subsections.

## Decisions Made

- Overrode `Block.appendHoverText` directly rather than introducing a `BlockItem` subclass, per 03-RESEARCH.md's disassembly finding that `BlockItem.appendHoverText` already forwards to the block — this kept `TransitReportBlocks`'s construction of the block item completely untouched.
- Typed both new tooltip values as pure ASCII and asserted this by byte-level check rather than by eye, since an editor autocorrecting the hyphen or a quote would still produce a resolving, rendering string that is not what was chosen.

## Deviations from Plan

None - plan executed exactly as written. The dev client was launched, handed to the user for live verification per the plan's own action text, and stopped (Minecraft client JVM and its `gradlew` wrapper process, not the shared Gradle daemon) once the user reported back, which is the plan's own intended sequence.

## Issues Encountered

None. Both the block-level `appendHoverText` override and the language provider additions compiled and generated correctly on the first attempt, matching 03-RESEARCH.md Pattern 3's disassembly-verified prediction exactly.

## User Setup Required

None - no external service configuration required.

## Human Verification (verbatim)

The user played through all seven steps of the `<human-check>` protocol in a running dev client (`gsd-dev` world, survival mode) and responded:

> "approved" — "yes it all works!"

This single response confirmed, per the user's own account of having completed the steps:
- One dirt block in the 2x2 **inventory** crafting grid (no crafting table opened) produced exactly one Transit Chart.
- The tooltip read three lines in order, in both the inventory and the hotbar: `Transit Chart`, then `Right-click to refresh.` (plain), then `What the sky is doing, right now.` (italic) — no raw translation key text appeared at any point.
- Breaking the placed block dropped exactly one Transit Chart every time: bare-handed, with a shovel, and with a pickaxe — never zero, never a different item.
- The recipe appeared in the recipe book.

**`appendHoverText` signature that compiled** (for Phase 10's right-click work and any future tooltip to start from a confirmed shape rather than re-deriving it):

```java
@Override
public void appendHoverText(ItemStack stack, BlockGetter level, List<Component> tooltip, TooltipFlag flag)
```

## Next Phase Readiness

- Phase 3 (Craft, Break, and Identify) is complete: BLOCK-04, BLOCK-05, BLOCK-06, GEN-03, GEN-04, GEN-05, GEN-06 are all satisfied and live-verified.
- The MEDIUM-confidence `FabricRecipeProvider` method-shape risk carried in STATE.md/ROADMAP.md since roadmap creation is now closed — no further empirical settling needed for that class of risk.
- No blockers for the next phase.

## Self-Check: PASSED

- FOUND: src/main/java/transitreport/block/TransitChartBlock.java
- FOUND: src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
- FOUND: src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
- FOUND: docs/DEV.md
- FOUND: commit bd32222
- FOUND: commit ed140da

---
*Phase: 03-craft-break-and-identify*
*Completed: 2026-09-08*

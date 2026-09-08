---
phase: 03-craft-break-and-identify
reviewed: 2026-09-08T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - docs/DEV.md
  - src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
  - src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
  - src/main/generated/data/jollyalchemy-transit-report/advancements/recipes/misc/transit_chart.json
  - src/main/generated/data/jollyalchemy-transit-report/loot_tables/blocks/transit_chart.json
  - src/main/generated/data/jollyalchemy-transit-report/recipes/transit_chart.json
  - src/main/java/transitreport/block/TransitChartBlock.java
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-09-08T00:00:00Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Reviewed the Phase 3 diff: the datagen entrypoint's new `TransitChartRecipeProvider` and
`TransitChartLootTableProvider` nested classes, the two new tooltip translation entries in
`TransitReportLanguageProvider`, the new `appendHoverText` override on `TransitChartBlock`, the
three newly generated data files (recipe, advancement, loot table), and the accompanying DEV.md
updates.

Cross-checked the generator source against its generated output: the recipe JSON's ingredient
(`minecraft:dirt`), result (`jollyalchemy-transit-report:transit_chart`), and category (`misc`)
all match `TransitChartRecipeProvider.buildRecipes`; the advancement's `has_dirt`/`has_the_recipe`
criteria are the expected `.save(exporter, id)` side effect, not hand-authored; the loot table's
single self-drop entry matches `dropSelf(TransitReportBlocks.TRANSIT_CHART)`. Cross-checked the
two new tooltip translation keys added in `TransitReportLanguageProvider`
(`item.jollyalchemy-transit-report.transit_chart.tooltip` / `.flavor`) against the exact
concatenated key strings used in `TransitChartBlock.appendHoverText` — they match, and both also
match the emitted `en_us.json`. No mismatched keys, no null-dereference risks, no unhandled edge
cases, and no security-relevant surface in this diff (no I/O, no user input, no string
interpolation into commands/paths/queries).

Confirmed via `git diff <diff_base>..HEAD` that DEV.md's Phase 3 findings section and the
`en_us.json` `text....refreshing` key predate this phase's changes (added in the earlier skeleton
language provider) and are not part of this diff, so they are out of scope here.

No Critical or Warning findings. Three Info-level maintainability notes below, all low severity
and none blocking.

## Info

### IN-01: Permanently retained commented-out recipe block

**File:** `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java:99-116`
**Issue:** `TransitChartRecipeProvider.buildRecipes` carries an 18-line commented-out
`ShapedRecipeBuilder` alternative (the "intended thematic recipe," GEN-06) alongside the active
shapeless-dirt recipe. It is well-justified by an in-code comment and documented in DEV.md, and the
comment correctly warns about the duplicate-recipe-id failure mode if both are ever left active
simultaneously — but it is still dead code shipped in the method body, which is generally a code
smell and adds noise to the one method a future reader most needs to trust at a glance.
**Fix:** If this is meant to be picked up in a near-term follow-up phase, consider tracking it as
a roadmap/backlog item instead of inline commented code, or move the placeholder recipe/asset list
into a design note (e.g. `03-RESEARCH.md`) rather than compiled-but-disabled Java. If kept inline,
no further action is required — the risk is already mitigated by the existing comment.

### IN-02: Translation key built by string concatenation with no shared constant

**File:** `src/main/java/transitreport/block/TransitChartBlock.java:52-54` and
`src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java:48-49`
**Issue:** The `item.<mod-id>.transit_chart.tooltip` and `.transit_chart.flavor` translation keys
are each independently reconstructed via string concatenation in two different files/modules (the
language provider that emits them, and the block that consumes them). Nothing at compile time
verifies the two concatenations produce the same string — a typo in either location (e.g.
`.tooltip` vs `.tool_tip`) would compile cleanly and only surface at runtime as a raw translation
key visible in the tooltip, which is exactly the failure mode the Phase 3 visual verification in
DEV.md had to manually check for ("no raw translation key ... ever visible").
**Fix:** This is idiomatic for small Fabric datagen setups and matches the project's
avoid-premature-abstraction stance, so a full constants class isn't warranted for two keys. If a
third or fourth tooltip line is added in a later phase, consider extracting the key prefix
(`"item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart."`) into a shared constant at that
point to keep the two locations from drifting.

### IN-03: `appendHoverText` override does not call `super.appendHoverText(...)`

**File:** `src/main/java/transitreport/block/TransitChartBlock.java:51`
**Issue:** The new override replaces `Block.appendHoverText` entirely rather than calling
`super.appendHoverText(stack, level, tooltip, flag)` first. `Block`'s default implementation is a
no-op in 1.20.1, so there is no current behavioral gap, but omitting the `super` call is a common
source of silently-dropped tooltip content later if `TransitChartBlock`'s hierarchy changes or if
a mixin/other mod adds hover text via the vanilla hook.
**Fix:** Low priority; consider adding `super.appendHoverText(stack, level, tooltip, flag);` as
the first line for defensive future-proofing. Not required for correctness today.

---

_Reviewed: 2026-09-08T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

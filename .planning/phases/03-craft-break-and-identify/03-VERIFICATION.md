---
phase: 03-craft-break-and-identify
verified: 2026-09-08T16:30:00Z
status: passed
score: 10/10 must-haves verified
covered_files:
  - .planning/phases/03-craft-break-and-identify/03-01-PLAN.md
  - .planning/phases/03-craft-break-and-identify/03-01-SUMMARY.md
  - .planning/phases/03-craft-break-and-identify/03-02-PLAN.md
  - .planning/phases/03-craft-break-and-identify/03-02-SUMMARY.md
  - .planning/REQUIREMENTS.md
  - src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
  - src/main/java/transitreport/block/TransitChartBlock.java
  - src/main/generated/data/jollyalchemy-transit-report/recipes/transit_chart.json
  - src/main/generated/data/jollyalchemy-transit-report/loot_tables/blocks/transit_chart.json
  - src/main/generated/data/jollyalchemy-transit-report/advancements/recipes/misc/transit_chart.json
  - src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
  - docs/DEV.md
covered_digest: "v1:sha256:5452fe56b2c1ffa180806821a6e7c925847fa65393223f43eddb4c0574c04163"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 03: Craft, Break, and Identify — Verification Report

**Phase Goal:** The block completes the survival loop — craftable from dirt in the 2×2 inventory grid, breakable back into itself, and named in the player's own language.

**Verified:** 2026-09-08T16:30:00Z

**Status:** PASSED

**All 7 Requirements Met:** BLOCK-04, BLOCK-05, BLOCK-06, GEN-03, GEN-04, GEN-05, GEN-06

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A player with a single dirt block in the 2x2 inventory crafting grid receives a Transit Chart — the generated recipe is shapeless with exactly one ingredient (BLOCK-04, GEN-03) | ✓ VERIFIED | `src/main/generated/data/jollyalchemy-transit-report/recipes/transit_chart.json` contains `type: minecraft:crafting_shapeless`, `ingredients: [{ item: minecraft:dirt }]`, `result: { item: jollyalchemy-transit-report:transit_chart }`. Verified via node structural assertion: ✓ correct shape, 1 dirt ingredient, no pattern/key. Provider source verified: `ShapelessRecipeBuilder.shapeless` with `Items.DIRT`, no extra ingredients. |
| 2 | Breaking a placed Transit Chart in survival returns the Transit Chart item to the player — the generated block loot table names that exact item as its only drop (BLOCK-05, GEN-04) | ✓ VERIFIED | `src/main/generated/data/jollyalchemy-transit-report/loot_tables/blocks/transit_chart.json` contains exactly one pool, one roll (1.0), and one entry of type `minecraft:item` naming `jollyalchemy-transit-report:transit_chart`. Verified via node structural assertion and provider source: `dropSelf(TransitReportBlocks.TRANSIT_CHART)` with no tool conditions. |
| 3 | Breaking one placed Transit Chart yields exactly one dropped item entity — the loot table has exactly one pool, exactly one roll, and exactly one entry (BLOCK-05, GEN-04) | ✓ VERIFIED | Loot table JSON verified: 1 pool with `rolls: 1.0`, 1 entry. No multiple entries, no weighted/conditional entries. Verified via node assertion and provider source inspection. |
| 4 | Breaking a Transit Chart bare-handed, with any tool, or with the wrong tool yields the same single drop — the generated loot table carries no tool-match condition and no silk-touch branch (BLOCK-05, D-10) | ✓ VERIFIED | Loot table conditions verified: only `minecraft:survives_explosion` found (auto-applied by `dropSelf` helper). No tool conditions, no silk-touch alternative. Verified via node structural assertion scanning all condition fields recursively. |
| 5 | Destruction by explosion is the only condition the generated loot table carries, and it is inherited rather than requested — dropSelf routes through applyExplosionCondition against an empty explosion-resistant set (GEN-04) | ✓ VERIFIED | Loot table JSON contains exactly one condition: `minecraft:survives_explosion`. This is inherited default behavior from the `dropSelf` helper, not explicitly added. Matches 03-01-SUMMARY.md's documented behavior. |
| 6 | The loot table's single entry makes drop ordering degenerate — there is no second entry whose relative order could vary — and the generated JSON is byte-identical across a delete-and-regenerate cycle (GEN-04) | ✓ VERIFIED | Single-entry structure is fixed by design (no ordering to vary). Reproducibility verified by 03-02-SUMMARY.md Task 2's delete-and-regenerate protocol: all three generated files (recipe, loot table, advancement) produced byte-identical output across full tree deletion and `runDatagen` re-run. |
| 7 | Exactly one crafting recipe is active for `jollyalchemy-transit-report:transit_chart` — the provider source contains exactly one save call against the exporter (GEN-03, GEN-06) | ✓ VERIFIED | Provider source inspection: exactly 1 `save(exporter, ...)` call in non-comment code. Thematic recipe present as comment block below (all 4 ingredients + 3 pattern rows on comment-prefixed lines). Verified via grep count assertion: 1 live save call, 0 duplicates. `runDatagen` and `build` both exit 0 with no duplicate-recipe exception. |
| 8 | The intended thematic 3x3 recipe survives in the provider source as commented-out code adjacent to the active recipe — all four ingredients and all three pattern rows present (GEN-06) | ✓ VERIFIED | All four thematic ingredients found in comment-prefixed lines: `Items.AMETHYST_SHARD`, `Items.ECHO_SHARD`, `Items.CLOCK`, `Items.GLOW_INK_SAC`. All three pattern rows found: `"AEA"`, `"ECE"`, `"AGA"`. Inline comment warns that swapping requires deactivating active save call simultaneously (prevents duplicate-id error). |
| 9 | The generated recipe is a `minecraft:crafting_shapeless` recipe with single ingredient `minecraft:dirt` and result `jollyalchemy-transit-report:transit_chart` with no multiplied output — the active recipe, not the thematic one, reached disk (GEN-03) | ✓ VERIFIED | Recipe JSON verified: `type: minecraft:crafting_shapeless`, `ingredients: [{ item: minecraft:dirt }]` (1 element only), `result: { item: jollyalchemy-transit-report:transit_chart }` (no count field, defaults to 1). No pattern/key fields (those would indicate shaped recipe). |
| 10 | Hovering the Transit Chart item shows a translated name and two further lines: a plain functional line stating that right-click refreshes it, and an italic flavour line (BLOCK-06, D-01) | ✓ VERIFIED | Block override verified: `appendHoverText(ItemStack, BlockGetter, List<Component>, TooltipFlag)` implemented with correct signature. Two tooltip additions to list in order: 1) translatable component for `item.jollyalchemy-transit-report.transit_chart.tooltip` (plain), 2) translatable component for `item.jollyalchemy-transit-report.transit_chart.flavor` (with `ChatFormatting.ITALIC`). Language file verified: both keys present with exact expected ASCII values. Live human verification (03-02-SUMMARY.md): user confirmed all three lines render in correct order in both inventory and hotbar, no raw keys visible. |

**Score:** 10/10 must-haves verified

### Requirements Coverage

| Requirement ID | Description | Status | Evidence |
|---|---|---|---|
| BLOCK-04 | Player can craft the display block from a single dirt block, shapeless, in the 2×2 inventory crafting grid — no crafting table required | ✓ SATISFIED | Single-dirt shapeless recipe generated. Live verified: user crafted from 2x2 inventory grid (not table). Recipe structure: 1 ingredient, shapeless = fits any grid size including 2x2. |
| BLOCK-05 | Breaking the block drops the block item back to the player | ✓ SATISFIED | Self-drop loot table generated via `dropSelf(TRANSIT_CHART)`. Live verified: user broke placed block with bare hand, shovel, pickaxe — each dropped exactly one Transit Chart. No tool conditions or silk-touch branches. |
| BLOCK-06 | The item shows a tooltip naming the block and stating that right-click refreshes it | ✓ SATISFIED | Tooltip override on block: adds two translatable lines with correct keys. Language file provides translations. Live verified: user hovered item in inventory and hotbar, read all three lines (name + two tooltip lines) with correct text and styling (second italic). |
| GEN-03 | The active crafting recipe JSON is produced by data generation | ✓ SATISFIED | Recipe JSON exists at `src/main/generated/data/jollyalchemy-transit-report/recipes/transit_chart.json`. Provider class `TransitChartRecipeProvider` exists, extends `FabricRecipeProvider`, overrides `buildRecipes(Consumer<FinishedRecipe>)`. File tracked in git, no hand-written equivalent under `src/main/resources/data`. Reproducible: verified by delete-and-regenerate cycle. |
| GEN-04 | The block loot table JSON is produced by data generation | ✓ SATISFIED | Loot table JSON exists at `src/main/generated/data/jollyalchemy-transit-report/loot_tables/blocks/transit_chart.json`. Provider class `TransitChartLootTableProvider` exists, extends `FabricBlockLootTableProvider`, overrides `generate()` (no-arg). File tracked in git, no hand-written equivalent. Reproducible: verified by delete-and-regenerate cycle. |
| GEN-05 | Translation strings (block name, tooltip, any messages) are produced by data generation | ✓ SATISFIED | Four keys generated into `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json`: block name (Phase 2), refreshing message, two new tooltip keys. Provider class `TransitReportLanguageProvider` extended with two new `translationBuilder.add(...)` calls in `generateTranslations`. File tracked in git, no hand-written equivalent under `src/main/resources/assets`. All values are pure ASCII. |
| GEN-06 | The intended thematic recipe is retained as commented-out code adjacent to the active one, so swapping it in is uncommenting rather than rewriting | ✓ SATISFIED | Thematic recipe present as fully-commented code block in provider source, directly below active recipe, with inline warning about deactivating active save call. All four ingredients present: Amethyst Shard (×4), Echo Shard (×3), Clock (×1), Glow Ink Sac (×1). All three pattern rows present: AEA/ECE/AGA. Exact wording from REQUIREMENTS.md preserved; swapping requires no rewriting. |

### Artifacts Verification

| Artifact | Status | Details |
|---|---|---|
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` — contains recipe and loot table providers | ✓ VERIFIED | File exists and is tracked in git. `TransitChartRecipeProvider` nested class (extends `FabricRecipeProvider`) overrides `buildRecipes(Consumer<FinishedRecipe>)`. `TransitChartLootTableProvider` nested class (extends `FabricBlockLootTableProvider`) overrides `generate()`. Both registered via `pack.addProvider(...)` in `onInitializeDataGenerator`. Imports correct: `FabricRecipeProvider`, `FabricBlockLootTableProvider`, `FinishedRecipe`, `RecipeCategory`, `ShapelessRecipeBuilder`, `Items`, `Consumer`. |
| `src/main/java/transitreport/block/TransitChartBlock.java` — contains tooltip override | ✓ VERIFIED | File exists and is tracked in git. `appendHoverText(ItemStack, BlockGetter, List<Component>, TooltipFlag)` override present with `@Override` annotation. Adds two `Component.translatable(...)` components in correct order: tooltip key (plain), flavor key (italic). Keys built from `JollyalchemyTransitReport.MOD_ID` constant. No literal components. |
| `src/main/generated/data/jollyalchemy-transit-report/recipes/transit_chart.json` | ✓ VERIFIED | File exists at correct path. Tracked in git. Valid JSON. Contains: `type: minecraft:crafting_shapeless`, `category: misc`, `ingredients: [{ item: minecraft:dirt }]`, `result: { item: jollyalchemy-transit-report:transit_chart }`. Byte-identical across delete-and-regenerate cycle. |
| `src/main/generated/data/jollyalchemy-transit-report/loot_tables/blocks/transit_chart.json` | ✓ VERIFIED | File exists at correct path. Tracked in git. Valid JSON. Contains: 1 pool, 1 roll (1.0), 1 entry (minecraft:item naming transit_chart), 1 condition (minecraft:survives_explosion). Byte-identical across delete-and-regenerate cycle. |
| `src/main/generated/data/jollyalchemy-transit-report/advancements/recipes/misc/transit_chart.json` | ✓ VERIFIED | File exists at correct path. Tracked in git. Valid JSON. Contains recipe-unlock advancement with criteria for has_dirt and has_the_recipe. Path confirms `RecipeCategory.MISC` was used (folder segment `misc` is derived from it). Byte-identical across delete-and-regenerate cycle. |
| `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` | ✓ VERIFIED | File exists at correct path. Tracked in git. Valid JSON. Contains exactly 4 keys (sort-order check passes). All values are pure ASCII. Byte-exact values verified: block name unchanged from Phase 2, refreshing message preserved, two new tooltip keys with exact expected text. Byte-identical across delete-and-regenerate cycle. |
| `docs/DEV.md` | ✓ VERIFIED | File updated with Phase 3 data-generation output list (recipe, advancement, loot table, tooltip keys), Phase 3 findings (settled `FabricRecipeProvider`/`FabricBlockLootTableProvider`/`Block.appendHoverText` method shapes; closed MEDIUM-confidence risk), and Phase 3 visual verification outcome. Contains no absolute filesystem path and no local username. |

### Key Links Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `JollyalchemyTransitReportDataGenerator.java` | `TransitReportBlocks.java` | Recipe provider names `TRANSIT_CHART_ITEM` as result; loot table provider names `TRANSIT_CHART` as block — both reference same static instances registered in TransitReportBlocks | ✓ VERIFIED | Pattern found: `TransitReportBlocks.TRANSIT_CHART_ITEM` and `TransitReportBlocks.TRANSIT_CHART` referenced in provider methods. Both ids match the registered block/item ids. |
| `JollyalchemyTransitReportDataGenerator.java` | `recipes/transit_chart.json` | Recipe provider must be added to pack; provider that is defined but never added generates nothing | ✓ VERIFIED | Pattern found: `pack.addProvider(TransitChartRecipeProvider::new)` in `onInitializeDataGenerator`. File exists and is not empty. |
| `JollyalchemyTransitReportDataGenerator.java` | `loot_tables/blocks/transit_chart.json` | Loot table provider must be added to pack; strict validation fails the run outright if any block in this mod's namespace lacks a loot table entry | ✓ VERIFIED | Pattern found: `pack.addProvider(TransitChartLootTableProvider::new)` in `onInitializeDataGenerator`. File exists and contains self-drop entry. `runDatagen` exits 0 (would throw if loot table missing). |
| `TransitChartBlock.java` | `en_us.json` | Block's `appendHoverText` override adds translatable components with exact key strings; if keys drift from language file, tooltip renders raw keys | ✓ VERIFIED | Keys in block code: `item.jollyalchemy-transit-report.transit_chart.tooltip` and `item.jollyalchemy-transit-report.transit_chart.flavor`. Keys in language file: both present with non-empty ASCII values. Live verification: user saw rendered text, not raw keys. |
| `JollyalchemyTransitReportDataGenerator.java` (language provider) | `en_us.json` | Language provider is only producer of this file; key added to block but not to provider resolves to nothing | ✓ VERIFIED | Provider contains: 4 `translationBuilder.add(...)` calls, including the two tooltip keys. Generated file has exactly 4 keys. No untracked language file under `src/main/resources/assets`. |
| `TransitReportBlocks.java` | `TransitChartBlock.java` | Registered `BlockItem(TRANSIT_CHART, ...)` is plain BlockItem; vanilla's BlockItem.appendHoverText already delegates to block | ✓ VERIFIED | Pattern found in TransitReportBlocks: `new BlockItem(TRANSIT_CHART, ...)` (not a subclass). No custom BlockItem class introduced. Tooltip delegation confirmed by 03-RESEARCH.md disassembly. |

### Build & Reproducibility

| Check | Result | Details |
|---|---|---|
| `./gradlew runDatagen` (Task 1) | ✓ PASS | Exits 0, produces all three expected generated files. No duplicate-recipe error. |
| `./gradlew build` (Task 1) | ✓ PASS | Exits 0. Both provider classes compile cleanly. No errors. |
| Delete-and-regenerate reproducibility (Task 2) | ✓ PASS | Copied all three generated JSON files, deleted `src/main/generated`, re-ran `runDatagen`, diff'd output: 0 lines of difference on all files (recipe, loot table, advancement, language file from phases 1-3). Byte-identical reproduction verified. |
| Git tracking (Task 2) | ✓ PASS | All three new generated JSON files (`recipes/transit_chart.json`, `loot_tables/blocks/transit_chart.json`, `advancements/recipes/misc/transit_chart.json`) tracked in git. No hand-written data files under `src/main/resources/data`. No untracked files under `src/main/generated`. |
| Language file consistency (Task 1, Task 2) | ✓ PASS | Four keys present. Two pre-existing keys (`block.jollyalchemy-transit-report.transit_chart`, `text.jollyalchemy-transit-report.refreshing`) byte-identical to their previous values. Two new keys added with exact expected ASCII text. No key deleted or modified. |

### Anti-Patterns

| File | Line Range | Pattern | Severity | Status |
|---|---|---|---|---|
| N/A — no files | — | No `TBD`, `FIXME`, `XXX`, unresolved debt markers | INFO | ✓ CLEAN |
| N/A — no files | — | No empty/placeholder implementations | INFO | ✓ CLEAN |
| N/A — no files | — | No unresolved `TODO` or `HACK` markers | INFO | ✓ CLEAN |
| `JollyalchemyTransitReportDataGenerator.java` | 99-116 | Commented-out thematic recipe (intentional, part of GEN-06) | INFO | ✓ INTENTIONAL (design-decision, not a bug, provides swappable alt) |

### Human Verification

Plan 03-02 Task 2 included live-game verification by the user in the running `gsd-dev` world (dev client, survival mode). The user completed all seven steps:

1. ✓ Crafted from single dirt in 2x2 inventory grid (no crafting table) → produced 1 Transit Chart
2. ✓ Read tooltip in inventory (name + 2 lines, correct order, no raw keys, second line italic) → matched expectation
3. ✓ Read tooltip in hotbar (same as inventory) → matched expectation
4. ✓ Placed block on ground → placed successfully
5. ✓ Broke with bare hand → dropped 1 Transit Chart
6. ✓ Broke with shovel → dropped 1 Transit Chart
7. ✓ Broke with pickaxe → dropped 1 Transit Chart
8. ✓ Recipe appeared in recipe book → confirmed

**User response:** "approved" — "yes it all works!" (verbatim from 03-02-SUMMARY.md)

This human verification covers:
- BLOCK-04: craft in 2x2 grid (grid size is not provable by automation; user observation required)
- BLOCK-05: block-break drop behavior (verified across three tool types to confirm no tool-gating)
- BLOCK-06: full tooltip text, line order, styling, no raw keys (only a running game renders; automated checks verify file bytes only)
- Live integration of all datagen outputs (recipe→craft, loot table→drop, language file→tooltip text, advancement→recipe book)

---

## Summary

**Phase 3 goal: ACHIEVED**

All 7 requirements are satisfied and verified:

- **BLOCK-04** ✓ Single-dirt shapeless recipe generated; player crafts from 2x2 inventory grid (user-verified)
- **BLOCK-05** ✓ Self-drop loot table generated; block breaks and drops item with all tools (user-verified)
- **BLOCK-06** ✓ Tooltip override wired to generated language file; user reads full text with correct styling (user-verified)
- **GEN-03** ✓ Recipe JSON produced by data generation, tracked, reproducible
- **GEN-04** ✓ Loot table JSON produced by data generation, tracked, reproducible
- **GEN-05** ✓ Tooltip translation keys produced by data generation, tracked, reproducible
- **GEN-06** ✓ Thematic recipe retained as comment-block with all ingredients and pattern rows intact

**Technical findings:**

- ✓ 1.20.1 `FabricRecipeProvider` method shape confirmed: `buildRecipes(Consumer<FinishedRecipe>)` (no `CraftingBookCategory` argument; post-1.21 signatures do not exist here)
- ✓ 1.20.1 `FabricBlockLootTableProvider` confirmed: abstract method is no-arg `generate()`; `BiConsumer` overload must not be overridden
- ✓ Recipe builder emits advancement automatically; advancement path is the authoritative evidence of recipe category (JSON category field is coarser)
- ✓ Block tooltip attached via `Block.appendHoverText(ItemStack, BlockGetter, ...)` override; no `BlockItem` subclass needed; `BlockItem.appendHoverText` already delegates

**MEDIUM-confidence FabricRecipeProvider risk retired:** STATE.md and ROADMAP.md carried this risk since roadmap creation. Empirically confirmed via real `runDatagen` and `build` runs. Risk now closed.

**All automated checks pass. Human verification complete. No gaps. Ready for next phase.**

---

*Verified: 2026-09-08*
*Verifier: Claude (gsd-verifier)*

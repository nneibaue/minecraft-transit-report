# Phase 3: Craft, Break, and Identify - Pattern Map

**Mapped:** 2026-09-08
**Files analyzed:** 2 (1 modified existing, 1 modified existing — no wholly new files; two new nested classes added to an existing file)
**Analogs found:** 2 / 2 (both in-repo, same-file precedent — this phase extends established patterns rather than introducing new file shapes)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` (add `TransitChartRecipeProvider` nested class) | config (build-time datagen provider) | batch (static JSON generation) | `TransitChartModelProvider` nested class, same file | exact — same file, same `private static final class extends Fabric*Provider` shape, same constructor-takes-`FabricDataOutput` pattern |
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` (add `TransitChartLootTableProvider` nested class) | config (build-time datagen provider) | batch (static JSON generation) | `TransitChartModelProvider` nested class, same file | exact — identical structural shape (nested provider class + `pack.addProvider` registration line) |
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` (grow `TransitReportLanguageProvider.generateTranslations`) | config (translation data) | batch | `TransitReportLanguageProvider.generateTranslations`, same file, existing 2 lines | exact — literally the same method, add 2 more `translationBuilder.add(...)` calls in the same style |
| `src/main/java/transitreport/block/TransitChartBlock.java` (add `appendHoverText` override) | model/controller (Block behavior override) | request-response (queried synchronously when UI builds a tooltip) | `TransitChartBlock.getStateForPlacement` / `createBlockStateDefinition` overrides, same file | exact — same file, same "override a `Block`/`HorizontalDirectionalBlock` method with `@Override`" convention already used twice in this class |

## Pattern Assignments

### `TransitChartRecipeProvider` (new nested class in `JollyalchemyTransitReportDataGenerator.java`)

**Analog:** `TransitChartModelProvider` (same file, lines 47-66) — establishes the "private static final class extends Fabric*Provider, private constructor taking `FabricDataOutput`, calls `super(output)`" shape this project already uses for datagen providers.

**Imports pattern** (from top of `JollyalchemyTransitReportDataGenerator.java`, lines 1-16):
```java
import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;
import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider;
// ADD: import net.fabricmc.fabric.api.datagen.v1.provider.FabricRecipeProvider;
// ADD: import net.fabricmc.fabric.api.datagen.v1.provider.FabricBlockLootTableProvider;

import net.minecraft.data.models.BlockModelGenerators;
import net.minecraft.data.models.ItemModelGenerators;
import net.minecraft.data.models.model.TextureSlot;
import net.minecraft.data.models.model.TexturedModel;
import net.minecraft.resources.ResourceLocation;
// ADD: import net.minecraft.data.recipes.FinishedRecipe;
// ADD: import net.minecraft.data.recipes.RecipeCategory;
// ADD: import net.minecraft.data.recipes.ShapelessRecipeBuilder;
// ADD: import net.minecraft.data.recipes.ShapedRecipeBuilder;  (only if/when thematic recipe is ever uncommented)
// ADD: import net.minecraft.world.item.Items;
// ADD: import java.util.function.Consumer;

import transitreport.JollyalchemyTransitReport;
import transitreport.TransitReportBlocks;
```
Note the existing file groups imports by source library (Fabric API, then `net.minecraft.*`, then project) with a blank line between groups — follow that grouping when adding new imports, don't just append alphabetically at the end.

**Core provider pattern** (RESEARCH.md Pattern 1, verified via `javap`/sources-jar read this session — copy directly):
```java
private static final class TransitChartRecipeProvider extends FabricRecipeProvider {
    private TransitChartRecipeProvider(FabricDataOutput output) {
        super(output);
    }

    @Override
    public void buildRecipes(Consumer<FinishedRecipe> exporter) {
        ShapelessRecipeBuilder.shapeless(RecipeCategory.MISC, TransitReportBlocks.TRANSIT_CHART_ITEM)
                .requires(Items.DIRT)
                .unlockedBy("has_dirt", has(Items.DIRT))
                .save(exporter, JollyalchemyTransitReport.id("transit_chart"));

        // Intended thematic recipe (GEN-06) — commented out, adjacent, ready to swap in by
        // uncommenting AND commenting out the active recipe above (same recipe id — both
        // active at once throws IllegalStateException("Duplicate recipe ...") at runDatagen).
        //
        // ShapedRecipeBuilder.shaped(RecipeCategory.MISC, TransitReportBlocks.TRANSIT_CHART_ITEM)
        //         .pattern("AEA")
        //         .pattern("ECE")
        //         .pattern("AGA")
        //         .define('A', Items.AMETHYST_SHARD)
        //         .define('E', Items.ECHO_SHARD)
        //         .define('C', Items.CLOCK)
        //         .define('G', Items.GLOW_INK_SAC)
        //         .unlockedBy("has_echo_shard", has(Items.ECHO_SHARD))
        //         .save(exporter, JollyalchemyTransitReport.id("transit_chart"));
    }
}
```

**Registration pattern** (`onInitializeDataGenerator`, existing lines 22-25 — extend directly, follow the existing two-line style):
```java
pack.addProvider(TransitReportLanguageProvider::new);
pack.addProvider(TransitChartModelProvider::new);
pack.addProvider(TransitChartRecipeProvider::new);      // ADD
pack.addProvider(TransitChartLootTableProvider::new);   // ADD
```

---

### `TransitChartLootTableProvider` (new nested class in `JollyalchemyTransitReportDataGenerator.java`)

**Analog:** same as above — `TransitChartModelProvider` structural shape.

**Core provider pattern** (RESEARCH.md Pattern 2 — copy directly; note the no-arg `generate()`, not `generate(BiConsumer)`):
```java
private static final class TransitChartLootTableProvider extends FabricBlockLootTableProvider {
    private TransitChartLootTableProvider(FabricDataOutput output) {
        super(output);
    }

    @Override
    public void generate() {
        dropSelf(TransitReportBlocks.TRANSIT_CHART);
    }
}
```

---

### `TransitReportLanguageProvider.generateTranslations` (grow existing method, `JollyalchemyTransitReportDataGenerator.java` lines 33-36)

**Analog:** the method itself — existing 2-line body, same file:
```java
@Override
public void generateTranslations(FabricLanguageProvider.TranslationBuilder translationBuilder) {
    translationBuilder.add("text." + JollyalchemyTransitReport.MOD_ID + ".refreshing", "Refreshing transit chart...");
    translationBuilder.add("block." + JollyalchemyTransitReport.MOD_ID + ".transit_chart", "Transit Chart");
}
```

**Additions** (append two more calls in the identical `"prefix." + MOD_ID + ".key"` string-concat style already used — do not switch to a different key-building convention):
```java
translationBuilder.add("item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.tooltip", "Right-click to refresh.");
translationBuilder.add("item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.flavor", "What the sky is doing, right now.");
```
Do not reuse or duplicate the existing `text....refreshing` key — that is reserved for a later phase's loading-state string (D-02's explicit note).

---

### `TransitChartBlock.appendHoverText` (new override, `src/main/java/transitreport/block/TransitChartBlock.java`)

**Analog:** the two existing overrides already in this class (`createBlockStateDefinition`, lines 26-29; `getStateForPlacement`, lines 31-34) — establishes the "plain `@Override` public method appended after the constructor, no wrapping/try-catch, single expression or short body" convention this class already follows.

**Existing imports** (lines 1-8, to extend — same grouping convention as the datagen file: `net.minecraft.*` only, alphabetized within the file's existing informal ordering):
```java
import net.minecraft.core.Direction;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
```
**New imports needed** (RESEARCH.md Pattern 3, verified):
```java
import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.level.BlockGetter;
import java.util.List;
import transitreport.JollyalchemyTransitReport;   // for MOD_ID — not currently imported in this file
```

**Core override pattern** (append after `getStateForPlacement`, same `@Override` style):
```java
@Override
public void appendHoverText(ItemStack stack, BlockGetter level, List<Component> tooltip, TooltipFlag flag) {
    tooltip.add(Component.translatable("item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.tooltip"));
    tooltip.add(Component.translatable("item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.flavor")
            .withStyle(ChatFormatting.ITALIC));
}
```

**No error handling / validation pattern applies** — this is a synchronous, pure UI-text method with no I/O, no external input, and no failure mode (matches the class's existing overrides, which are equally unguarded).

**Do NOT create a `TransitChartBlockItem extends BlockItem` subclass** — confirmed unnecessary by RESEARCH.md's bytecode disassembly of `BlockItem.appendHoverText` (it already delegates to `getBlock().appendHoverText(...)`). `TransitReportBlocks.TRANSIT_CHART_ITEM`'s construction (`new BlockItem(TRANSIT_CHART, new Item.Properties())` in `TransitReportBlocks.java` lines 27-28) stays unchanged.

---

## Shared Patterns

### Registry ID / translation-key construction
**Source:** `JollyalchemyTransitReport.id(String path)` (`src/main/java/transitreport/JollyalchemyTransitReport.java` lines 25-27) and the `"prefix." + MOD_ID + ".key"` string-concat convention used throughout `TransitReportLanguageProvider`.
**Apply to:** every new `ResourceLocation` (recipe id via `JollyalchemyTransitReport.id("transit_chart")`) and every new translation key (built as `"item." + JollyalchemyTransitReport.MOD_ID + ".transit_chart.tooltip"` etc.) — never hardcode the mod id string literally, always go through `MOD_ID`/`id(...)`.

### Nested-provider-class-per-concern in the single datagen entrypoint
**Source:** `JollyalchemyTransitReportDataGenerator.java` — `TransitReportLanguageProvider` and `TransitChartModelProvider` are both `private static final` nested classes inside the one `fabric-datagen` entrypoint class, each registered with one `pack.addProvider(...)` line in `onInitializeDataGenerator`.
**Apply to:** both `TransitChartRecipeProvider` and `TransitChartLootTableProvider` — same nesting, same visibility, same registration mechanism. Do not create separate top-level files for these providers or a second datagen entrypoint.

### Reusing registered `Block`/`Item` instances, never re-registering
**Source:** `TransitReportBlocks.TRANSIT_CHART` / `TransitReportBlocks.TRANSIT_CHART_ITEM` (`src/main/java/transitreport/TransitReportBlocks.java` lines 25-28) — the single source of truth already consumed by `TransitChartModelProvider`.
**Apply to:** the recipe provider's `.shapeless(RecipeCategory.MISC, TransitReportBlocks.TRANSIT_CHART_ITEM)` and the loot table provider's `dropSelf(TransitReportBlocks.TRANSIT_CHART)` — reference these existing static fields, never construct a new `Block`/`Item`/`BlockItem` instance in the datagen layer.

## No Analog Found

None. Every file touched this phase is a modification to one of two existing files (`JollyalchemyTransitReportDataGenerator.java`, `TransitChartBlock.java`), and each new unit of code (a nested provider class, a method override, translation-builder lines) has a directly matching same-file precedent from Phase 2. RESEARCH.md's Architecture Patterns section (Patterns 1-3) additionally ground every new API call against `javap`/sources-jar verification, so no fallback to external tutorial patterns is needed.

## Metadata

**Analog search scope:** `src/main/java/transitreport/`, `src/client/java/transitreport/client/` (the only two source roots this project has as of Phase 2; confirmed no `src/test` exists).
**Files scanned:** 3 (`JollyalchemyTransitReportDataGenerator.java`, `TransitChartBlock.java`, `TransitReportBlocks.java`) + 1 read for context only (`JollyalchemyTransitReport.java`).
**Pattern extraction date:** 2026-09-08
</content>

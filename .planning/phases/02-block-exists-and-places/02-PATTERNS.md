# Phase 2: Block Exists and Places - Pattern Map

**Mapped:** 2026-09-08
**Files analyzed:** 5 (2 new source, 1 new class, 2 modified)
**Analogs found:** 3 in-repo (partial/skeleton matches) + 3 vanilla jar analogs / 5 total

No prior Block/BlockEntity/datagen-model code exists in this repo (Phase 1 only registered the mod entrypoint and a language provider skeleton). Because of that, the in-repo analogs are **structural/skeleton matches only** (they show project conventions: package layout, `MOD_ID`/`id()` helper, datagen `Pack`/`addProvider` wiring) — the actual Block/model-provider **code shape** must come from vanilla Minecraft classes in the pinned jar, exactly as RESEARCH.md's `javap`/bytecode-verified examples already establish. This file cites those same verified examples as canonical; do not re-derive them from tutorials or Yarn-mapped sources.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/main/java/transitreport/block/TransitChartBlock.java` | model (Block subclass) | request-response (place-time state derivation) | vanilla `net.minecraft.world.level.block.AbstractFurnaceBlock` (jar) / `HorizontalDirectionalBlock` (jar) | role-match (vanilla, no in-repo Block exists) |
| `src/main/java/transitreport/TransitReportBlocks.java` | config/registration holder | CRUD (registry add) | vanilla registration idiom (no in-repo holder class exists); shape follows `JollyalchemyTransitReport.id()` convention | partial (in-repo convention + vanilla registration API) |
| `src/main/java/transitreport/JollyalchemyTransitReport.java` (modified) | entrypoint/controller | event-driven (mod init) | itself — existing `onInitialize()` | exact (same file, additive edit) |
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` (modified) | config (datagen entrypoint) | batch (build-time generation) | itself — existing `onInitializeDataGenerator` + `TransitReportLanguageProvider` nested class | exact (same file, additive edit, same nested-class idiom repeated for the model provider) |
| New `TransitChartModelProvider` (nested or sibling class in `src/client/java/transitreport/client/`) | config (datagen provider) | batch (build-time JSON generation) | `TransitReportLanguageProvider` (nested class, same file) for **shape** (constructor takes `FabricDataOutput`, single override method, registered via `pack.addProvider(...)`); vanilla `BlockModelGenerators`/`TexturedModel` (jar) for **content** | role-match (in-repo shape) + exact (vanilla API, bytecode-verified in RESEARCH.md) |

## Pattern Assignments

### `src/main/java/transitreport/block/TransitChartBlock.java` (Block subclass, request-response)

**Analog:** vanilla `net.minecraft.world.level.block.AbstractFurnaceBlock` and `HorizontalDirectionalBlock`, both in `.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-common-*/**/*.jar` (Mojang official mappings — confirmed via `javap`/`javap -c` in RESEARCH.md, not re-derived here to avoid re-reading already-verified bytecode).

There is no in-repo Block class to copy from — this is a legitimately new pattern for this codebase. Use RESEARCH.md's verified example directly:

**Core pattern** (constructor + state definition + placement):
```java
package transitreport.block;

import net.minecraft.core.Direction;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.BlockBehaviour;

public class TransitChartBlock extends HorizontalDirectionalBlock {
    public TransitChartBlock(BlockBehaviour.Properties properties) {
        super(properties);
        this.registerDefaultState(this.stateDefinition.any().setValue(FACING, Direction.NORTH));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<net.minecraft.world.level.block.Block, BlockState> builder) {
        builder.add(FACING);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        return this.defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite());
    }
}
```
Facing direction (`getHorizontalDirection().getOpposite()`, not `getNearestLookingDirection()`) is bytecode-confirmed against `AbstractFurnaceBlock.getStateForPlacement` — see RESEARCH.md Pattern 2 for the disassembly. Do not substitute a differently-named direction method without re-checking bytecode; method names in this API are misleading (see Pitfall 4 re: `BaseEntityBlock`).

**Do NOT extend** `BaseEntityBlock` this phase (D-08) — it overrides `getRenderShape()` to `INVISIBLE` by default and does not extend `HorizontalDirectionalBlock`.

---

### `src/main/java/transitreport/TransitReportBlocks.java` (registration holder, CRUD)

**Analog:** No in-repo holder class exists yet. Conventions borrowed from `src/main/java/transitreport/JollyalchemyTransitReport.java`:

**Imports/id-helper pattern** (from `JollyalchemyTransitReport.java`, lines 1-9, 25-27):
```java
package transitreport;

import net.minecraft.resources.ResourceLocation;
// ...
public static ResourceLocation id(String path) {
    return new ResourceLocation(MOD_ID, path);
}
```
Use `JollyalchemyTransitReport.id("transit_chart")` for the registry `ResourceLocation` — do not construct `ResourceLocation` inline (established convention, only one call site exists today but it is the established helper).

**Registration + creative tab pattern** (vanilla + Fabric API, bytecode/javap-verified in RESEARCH.md Pattern 1):
```java
package transitreport;

import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.CreativeModeTabs;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;

import net.fabricmc.fabric.api.itemgroup.v1.ItemGroupEvents;

import transitreport.block.TransitChartBlock;

public final class TransitReportBlocks {
    public static final Block TRANSIT_CHART = new TransitChartBlock(
            BlockBehaviour.Properties.of()
                    .strength(1.5F)
                    .sound(SoundType.AMETHYST));

    public static final Item TRANSIT_CHART_ITEM = new BlockItem(TRANSIT_CHART, new Item.Properties());

    private TransitReportBlocks() {
    }

    public static void register() {
        Registry.register(BuiltInRegistries.BLOCK, JollyalchemyTransitReport.id("transit_chart"), TRANSIT_CHART);
        Registry.register(BuiltInRegistries.ITEM, JollyalchemyTransitReport.id("transit_chart"), TRANSIT_CHART_ITEM);

        ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)
                .register(entries -> entries.accept(TRANSIT_CHART_ITEM));
    }
}
```
Note: no `requiresCorrectToolForDrops()`, no `lightLevel(...)`, no `noOcclusion()` (D-10 — deliberately not set this phase).

**Error handling:** none needed — registration either succeeds at class-load/init time or the build fails; no runtime try/catch pattern applies here (this differs from the HTTP/texture phases later, which do need explicit error handling per CLAUDE.md §3-4).

---

### `src/main/java/transitreport/JollyalchemyTransitReport.java` (modified, additive)

**Analog:** itself, lines 17-24 (existing `onInitialize()`).

**Current code:**
```java
@Override
public void onInitialize() {
	LOGGER.info("Hello Fabric world!");
}
```

**Edit pattern:** add one call, preserving the existing log line:
```java
@Override
public void onInitialize() {
	LOGGER.info("Hello Fabric world!");
	TransitReportBlocks.register();
}
```
Import: `transitreport.TransitReportBlocks` (same package — no import statement needed, since `TransitReportBlocks` lives directly in `transitreport`).

---

### `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` (modified, additive) + new `TransitChartModelProvider`

**Analog:** itself — the existing `TransitReportLanguageProvider` nested class (lines 17-28) is the exact shape to repeat for the new model provider.

**Imports pattern** (lines 1-8, existing):
```java
package transitreport.client;

import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;
import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider;

import transitreport.JollyalchemyTransitReport;
```
Add `import net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider;` and the model-generation classes below.

**Core pattern — provider registration** (lines 11-15, existing `onInitializeDataGenerator`):
```java
@Override
public void onInitializeDataGenerator(FabricDataGenerator fabricDataGenerator) {
	FabricDataGenerator.Pack pack = fabricDataGenerator.createPack();
	pack.addProvider(TransitReportLanguageProvider::new);
	pack.addProvider(TransitChartModelProvider::new);   // NEW
}
```

**Core pattern — nested provider class shape** (copy the `TransitReportLanguageProvider` structure at lines 19-28 exactly: `private static final class`, constructor taking `FabricDataOutput` calling `super(dataOutput)`, one override method):
```java
// New nested (or sibling top-level) class, same file, same idiom as TransitReportLanguageProvider
private static final class TransitChartModelProvider extends FabricModelProvider {
    private static final TexturedModel.Provider TRANSIT_CHART_TEXTURES = TexturedModel.ORIENTABLE_ONLY_TOP
            .updateTexture(mapping -> mapping
                    .put(TextureSlot.FRONT, new ResourceLocation("minecraft", "block/furnace_front"))
                    .put(TextureSlot.SIDE, new ResourceLocation("minecraft", "block/furnace_side"))
                    .put(TextureSlot.TOP, new ResourceLocation("minecraft", "block/furnace_top")));

    private TransitChartModelProvider(FabricDataOutput output) {
        super(output);
    }

    @Override
    public void generateBlockStateModels(BlockModelGenerators blockModelGenerators) {
        blockModelGenerators.createHorizontallyRotatedBlock(TransitReportBlocks.TRANSIT_CHART, TRANSIT_CHART_TEXTURES);
    }

    @Override
    public void generateItemModels(ItemModelGenerators itemModelGenerators) {
        // Intentionally empty — auto-generated parented item model (A1 in RESEARCH.md).
    }
}
```
Required additional imports for this class: `net.minecraft.data.models.BlockModelGenerators`, `net.minecraft.data.models.ItemModelGenerators`, `net.minecraft.data.models.model.TextureSlot`, `net.minecraft.data.models.model.TexturedModel`, `net.minecraft.resources.ResourceLocation`, `transitreport.TransitReportBlocks`.

**Translation edit** (D-07, one added line inside existing `generateTranslations`, lines 25-27):
```java
@Override
public void generateTranslations(FabricLanguageProvider.TranslationBuilder translationBuilder) {
	translationBuilder.add("text." + JollyalchemyTransitReport.MOD_ID + ".refreshing", "Refreshing transit chart...");
	translationBuilder.add("block." + JollyalchemyTransitReport.MOD_ID + ".transit_chart", "Transit Chart");
}
```

**Critical anti-pattern — do not use these methods** (bytecode-verified traps in RESEARCH.md, repeated here because they are the single highest-risk mistake in this file):
- `blockModelGenerators.createFurnace(...)` — hardcodes a `LIT` boolean dispatch `TransitChartBlock`'s state definition doesn't have. Use `createHorizontallyRotatedBlock(...)`.
- `TexturedModel.ORIENTABLE` — requires a 4th `BOTTOM` texture slot this project has no file for. Use `TexturedModel.ORIENTABLE_ONLY_TOP`.

## Shared Patterns

### Mod-id-scoped `ResourceLocation` construction
**Source:** `src/main/java/transitreport/JollyalchemyTransitReport.java`, lines 25-27 (`id(String path)`)
**Apply to:** `TransitReportBlocks.java` (registry ids). Do not inline `new ResourceLocation(MOD_ID, ...)` — use the helper.
```java
public static ResourceLocation id(String path) {
    return new ResourceLocation(MOD_ID, path);
}
```

### Datagen provider registration via `Pack.addProvider`
**Source:** `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java`, line 14 (`pack.addProvider(TransitReportLanguageProvider::new)`)
**Apply to:** the new `TransitChartModelProvider`, added as a second `pack.addProvider(...)` call in the same method — this is the entire "how do new datagen providers get wired in" pattern for this repo, do not invent an alternative registration mechanism.

### Explicit init-time registration (avoid static-init gotcha)
**Source:** RESEARCH.md Pitfall 3 (D-09) — no in-repo precedent exists yet since Phase 1 registered nothing; this establishes the pattern going forward.
**Apply to:** `TransitReportBlocks.register()`, called explicitly from `JollyalchemyTransitReport.onInitialize()`. Never rely on static field initialization alone to trigger `Registry.register(...)`.

### Vanilla-jar-only Block/model-generator API surface
**Source:** RESEARCH.md Architecture Patterns / Sources — `javap`-verified against `.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-common-*/**/*.jar` and Fabric API jars under `.gradle/loom-cache/remapped_mods/remapped/net/fabricmc/fabric-api/`.
**Apply to:** all classes in this phase that touch `Block`, `HorizontalDirectionalBlock`, `BlockModelGenerators`, `TexturedModel`, `ItemGroupEvents`, `FabricModelProvider`. These are Mojang-official-mapping names (per `.claude/CLAUDE.md` §2) — never substitute Yarn names (`Identifier`, `RenderLayer`, etc.) even if a tutorial or the roadmap/REQUIREMENTS.md text uses them.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `src/main/java/transitreport/block/TransitChartBlock.java` | Block subclass | request-response | No Block subclass exists anywhere in this repo yet (Phase 1 registered nothing game-content-related). Vanilla `AbstractFurnaceBlock`/`HorizontalDirectionalBlock` in the pinned jar are the only available analogs — cited above, already bytecode-verified in RESEARCH.md. |
| `TransitChartModelProvider` (content, not shape) | datagen provider | batch | No in-repo model-datagen provider exists (only the language provider). Content pattern must come from vanilla `BlockModelGenerators`/`TexturedModel`/vanilla `furnace.json` extracted from the client jar — cited above, already bytecode-verified and cross-checked against real vanilla JSON in RESEARCH.md. |

## Metadata

**Analog search scope:** `src/main/java/transitreport/`, `src/client/java/transitreport/client/`, `src/main/generated/`, `.gradle/loom-cache/minecraftMaven/**` (vanilla jar, read-only reference per RESEARCH.md's prior `javap` verification — not re-disassembled in this pass to avoid redundant work), `.gradle/loom-cache/remapped_mods/**` (Fabric API jars, same note).
**Files scanned:** 4 in-repo source files (`JollyalchemyTransitReport.java`, `JollyalchemyTransitReportDataGenerator.java`, `JollyalchemyTransitReportClient.java` [confirmed empty/unused this phase], `build.gradle`) + `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` (confirmed tracked via `git ls-files`).
**Pattern extraction date:** 2026-09-08
**Tracked-source gate:** all cited in-repo paths confirmed via prior `git ls-files` check (`src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` is tracked, not a gitignored mirror). No `.gsd/capabilities/` or other gitignored mirror paths were cited anywhere in this document.
</content>

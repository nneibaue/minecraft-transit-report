# Phase 2: Block Exists and Places - Research

**Researched:** 2026-09-08
**Domain:** Fabric 1.20.1 block/item registration, creative-tab wiring, 4-way horizontal facing, Fabric Data Generation (blockstate + block model + item model)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Display name is **"Transit Chart"** (not "Transit Display" or "Transit Report").
- **D-02:** Registry id `transit_chart`, class `TransitChartBlock`, translation key `block.jollyalchemy-transit-report.transit_chart`. This supersedes PROJECT.md's `TransitDisplayBlock` suggestion for the block only.
- **D-03:** Borrow vanilla **furnace textures** — `minecraft:block/furnace_front`, `minecraft:block/furnace_side`, `minecraft:block/furnace_top`. No PNG authored, no texture file added this phase.
- **D-04:** The **front faces the player who placed it** (furnace/chest convention) — not the piston/observer convention.
- **D-05:** **Verification is visual only.** Place four blocks from four approach directions in the running dev client; F3 blockstate readout declined as an additional check.
- **D-06:** **Vanilla Functional Blocks tab**, via Fabric API's `ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)`. No dedicated mod tab.
- **D-07:** Add the block's display-name translation **this phase**, as one added line in the existing `TransitReportLanguageProvider`. Key `block.jollyalchemy-transit-report.transit_chart` → `"Transit Chart"`.

### Claude's Discretion

- **D-08 (block entity timing — DEFER to Phase 4):** No `BlockEntity`/`BlockEntityType` this phase. `TransitChartBlock extends HorizontalDirectionalBlock`, not `BaseEntityBlock`. Landmine for Phase 4: `BaseEntityBlock.getRenderShape()` returns `RenderShape.INVISIBLE` by default and `BaseEntityBlock` does not extend `HorizontalDirectionalBlock` — Phase 4 must implement `EntityBlock` on the existing class, or override `getRenderShape()` back to `MODEL` if it switches base classes.
- **D-09 (registration structure):** A `public static final Block` field is required (not speculative) because the datagen model provider in `src/client` must reference the same instance `src/main` registers. Holder class (suggested `TransitReportBlocks`) with an explicit `register()` called from `onInitialize()` — static-field-only registration silently never fires.
- **D-10 (block properties):** `BlockBehaviour.Properties` — hardness ≈1.5F, `SoundType.AMETHYST`, no `requiresCorrectToolForDrops()`. Not set: `lightLevel` (Phase 4's render-layer concern), `noOcclusion()` (full opaque cube this phase).

### Deferred Ideas (OUT OF SCOPE)

- Real block artwork — deferred until images are updating on the block (post-Phase 7).
- Dedicated mod creative tab — revisit only if a second block is ever added.
- F3 blockstate verification as a second independent check on BLOCK-03 — worth reaching for only if Phase 4's renderer orients incorrectly.
- `.cache/` directory shipping inside the jar — cosmetic packaging nit, fix at real-distribution time.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BLOCK-01 | Player can place the display block in the world | §Architecture Patterns (registration), §Code Examples (Block/BlockItem registration) |
| BLOCK-02 | The display block appears as an item in a creative inventory group | §Code Examples (`ItemGroupEvents.modifyEntriesEvent`) |
| BLOCK-03 | The block stores a 4-way horizontal facing state, set from the direction the player faced when placing it | §Common Pitfalls (facing direction verified via bytecode), §Code Examples (`TransitChartBlock`) |
| GEN-01 | Blockstate and block model JSON are produced by Fabric Data Generation, not hand-written | §Common Pitfalls (`createFurnace` vs `createHorizontallyRotatedBlock` trap), §Code Examples (model provider) |
| GEN-02 | Item model JSON is produced by data generation | §Common Pitfalls (auto item-block model generation) |

</phase_requirements>

## Summary

Phase 2 registers `TransitChartBlock` (extends `HorizontalDirectionalBlock`) and its `BlockItem`, wires it into the vanilla Functional Blocks creative tab via Fabric API, and generates its blockstate/block-model/item-model JSON through a `FabricModelProvider`. All of the classes and method signatures below were confirmed with `javap` against the actual compiled jars this project builds against (`.gradle/loom-cache/minecraftMaven/**` for Mojang-mappings Minecraft, `.gradle/loom-cache/remapped_mods/**` for Fabric API 0.92.12+1.20.1) — not against tutorials, not against current Fabric docs, and not from training-data recall alone. Where bytecode disassembly (`javap -c`) was needed to settle an ambiguous method choice, that is called out explicitly.

The single highest-value finding this session: **`BlockModelGenerators.createFurnace(Block, TexturedModel.Provider)` is a trap for this block.** Its disassembled bytecode shows it hardcodes a `BlockStateProperties.LIT` boolean dispatch into the generated blockstate JSON. `TransitChartBlock` (extending `HorizontalDirectionalBlock`, not `AbstractFurnaceBlock`) has no `LIT` property, so calling `createFurnace` against it will very likely throw during `runDatagen` when the property-dispatch validation runs against the block's actual `StateDefinition`. The correct helper — confirmed via the identical bytecode-disassembly technique — is `createHorizontallyRotatedBlock(Block, TexturedModel.Provider)`, which generates a pure `FACING`-only dispatch with no `LIT` involvement.

The second finding, also settled by bytecode rather than by name: the *texture-mapping* provider to pair with it is **`TexturedModel.ORIENTABLE_ONLY_TOP`**, not the more obviously-named `TexturedModel.ORIENTABLE`. `TexturedModel.ORIENTABLE` requires a 4th `BOTTOM` texture slot (paired internally with `ModelTemplates.CUBE_ORIENTABLE_TOP_BOTTOM`) that furnace textures don't have and that this project has no plan to author — using it would leave the block's bottom face pointing at a nonexistent `jollyalchemy-transit-report:block/transit_chart_bottom` texture. `TexturedModel.ORIENTABLE_ONLY_TOP` requires exactly `FRONT`/`SIDE`/`TOP` (paired with `ModelTemplates.CUBE_ORIENTABLE`, the exact template vanilla's own `furnace.json` uses, confirmed by extracting that file directly from the Minecraft client jar).

**Primary recommendation:** `TransitChartBlock extends HorizontalDirectionalBlock`; `getStateForPlacement` sets `FACING` via `context.getHorizontalDirection().getOpposite()` (bytecode-confirmed to be exactly what `AbstractFurnaceBlock` itself does); register via a `TransitReportBlocks` holder with an explicit `register()` call; generate models with `blockModelGenerators.createHorizontallyRotatedBlock(block, TexturedModel.ORIENTABLE_ONLY_TOP.updateTexture(...))`; leave `generateItemModels` empty and let Fabric's model provider auto-generate the parented item model.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Block registration (`Block`, `BlockItem`) | Common (`src/main`) | — | Registry entries must exist on both logical client and server; Fabric's common source set is the shared registration point. |
| Creative tab entry (`ItemGroupEvents`) | Common (`src/main`) | — | `CreativeModeTabs.FUNCTIONAL_BLOCKS` and the item-group event fire on both sides in vanilla's registry-driven model; Fabric API's item-group event is a common-jar API (confirmed: `fabric-item-group-api-v1` ships both a `-common` and `-client` jar, and `ItemGroupEvents.modifyEntriesEvent` itself lives in the common jar). |
| 4-way facing state (`FACING` property, `getStateForPlacement`) | Common (`src/main`) | — | Blockstate is world-persisted server-authoritative data; must exist identically on both sides for a future (even if not-this-milestone) multiplayer server. |
| Blockstate/model/item-model datagen (`FabricModelProvider`) | Client (`src/client`) | — | TOOL-03 established this repo's split-source-set datagen entrypoint lives in `src/client`; `FabricModelProvider` only needs to exist at build time, never at runtime, and the project's established pattern (language provider) already lives there. |
| Translation string (`en_us.json`) | Client (`src/client`, generated into `src/main/generated`) | — | Language files are client-rendering concerns (tooltip/name display); `FabricLanguageProvider` already lives in the client-side datagen entrypoint per Phase 1's established pattern. |

## Standard Stack

No new external dependencies this phase. Every API used is already an approved dependency from Phase 1: vanilla Minecraft 1.20.1 (Mojang official mappings) and Fabric API `0.92.12+1.20.1` (pinned in `gradle.properties`, unchanged).

### Core (already-approved dependencies, no version change)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|---------------|
| Minecraft (Mojang mappings) | 1.20.1 | `Block`, `BlockItem`, `HorizontalDirectionalBlock`, `BlockBehaviour.Properties`, `BuiltInRegistries`, datagen model classes | Fixed project constraint; jar already present from Phase 1's Loom setup. `[VERIFIED: .gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-common-487d1d375f/**/minecraft-common-*.jar via javap]` |
| Fabric API | 0.92.12+1.20.1 | `ItemGroupEvents` (item-group-api-v1 4.0.14), `FabricModelProvider`/`FabricLanguageProvider` (data-generation-api-v1 12.4.0) | Pinned in `gradle.properties`; submodule jars confirmed present in `.gradle/loom-cache/remapped_mods/remapped/net/fabricmc/fabric-api/`. `[VERIFIED: unzip -l + javap against the remapped submodule jars]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `createHorizontallyRotatedBlock` | `createFurnace` | **Do not use** — hardcodes a `LIT` boolean dispatch this block's state definition doesn't have; will throw during `runDatagen`. See Common Pitfalls. |
| `TexturedModel.ORIENTABLE_ONLY_TOP` | `TexturedModel.ORIENTABLE` | **Do not use** `ORIENTABLE` — requires a 4th `BOTTOM` texture slot that doesn't exist for furnace textures (or this block); leaves the bottom face pointing at a missing texture. |
| `ItemGroupEvents.modifyEntriesEvent` | A dedicated `CreativeModeTab.Builder` registration | Rejected by D-06 — one block does not justify a dedicated tab; also more code for zero benefit given PROJECT.md's anti-premature-abstraction constraint. |

**Installation:** none — no new Gradle dependency lines needed.

**Version verification:** not applicable — no new package versions to check against a registry. All classes verified directly via `javap` against the exact jars this project already compiles against (see Sources).

## Package Legitimacy Audit

**Not applicable this phase.** No new external packages are introduced. All APIs used (`net.minecraft.*`, `net.fabricmc.fabric.api.*`) come from dependencies already vetted and pinned in Phase 1 (`minecraft_version`, `fabric_api_version` in `gradle.properties`, unchanged by this phase). The Package Legitimacy Gate protocol is skipped because there is nothing to run it against.

## Architecture Patterns

### System Architecture Diagram

```
Player right-clicks block item in hand, against a placed block face
        │
        ▼
BlockItem.useOn(UseOnContext)                      [vanilla, inherited — no override needed]
        │  wraps context as BlockPlaceContext
        ▼
TransitChartBlock.getStateForPlacement(BlockPlaceContext)   [OVERRIDE — this phase]
        │  context.getHorizontalDirection().getOpposite()
        │  → defaultBlockState().setValue(FACING, <opposite of player's look>)
        ▼
World stores BlockState{facing=N|E|S|W} at the target BlockPos
        │
        ▼ (separate, build-time path — never touches the above at runtime)
JollyalchemyTransitReportDataGenerator (src/client)
        │  pack.addProvider(TransitChartModelProvider::new)
        ▼
TransitChartModelProvider.generateBlockStateModels(BlockModelGenerators)
        │  createHorizontallyRotatedBlock(TRANSIT_CHART, ORIENTABLE_ONLY_TOP texture set)
        ▼
src/main/generated/assets/.../blockstates/transit_chart.json   (4 FACING variants, y-rotated)
src/main/generated/assets/.../models/block/transit_chart.json  (parent: minecraft:block/orientable)
src/main/generated/assets/.../models/item/transit_chart.json   (auto-generated, parents to the block model)
```

### Recommended Project Structure

```
src/main/java/transitreport/
├── JollyalchemyTransitReport.java      # existing — onInitialize() gains TransitReportBlocks.register()
├── TransitReportBlocks.java            # NEW — holder: Block + BlockItem fields, register(), creative-tab hook
└── block/
    └── TransitChartBlock.java          # NEW — extends HorizontalDirectionalBlock

src/client/java/transitreport/client/
├── JollyalchemyTransitReportClient.java          # unchanged — Phase 4's hook, untouched this phase
└── JollyalchemyTransitReportDataGenerator.java   # existing — gains one addProvider() line + new nested/sibling provider class
```

### Pattern 1: Block + BlockItem Registration (holder class, D-09)

**What:** A `public static final Block`/`Item` pair on a small holder class, registered via an explicit method called from `onInitialize()`.
**When to use:** Whenever a datagen provider in a different source set (`src/client`) needs to reference the same block instance `src/main` registers — exactly this project's split-source-set situation (TOOL-03).
**Example:**
```java
// Source: net.minecraft.core.Registry, net.minecraft.core.registries.BuiltInRegistries — verified via javap
// against .gradle/loom-cache/minecraftMaven/.../minecraft-common-*.jar
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
                    .sound(SoundType.AMETHYST)
    );

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
Call `TransitReportBlocks.register()` from `JollyalchemyTransitReport.onInitialize()` — a bare static field never runs without this, per D-09's static-initialization gotcha.

**Signatures verified:**
- `Registry.register(Registry<V>, ResourceLocation, T)` — `[VERIFIED: javap net.minecraft.core.Registry against minecraft-common-*.jar]`
- `BuiltInRegistries.BLOCK` / `BuiltInRegistries.ITEM` are `DefaultedRegistry<Block>` / `DefaultedRegistry<Item>` — `[VERIFIED: javap net.minecraft.core.registries.BuiltInRegistries]`
- `BlockBehaviour.Properties.of()`, `.strength(float)`, `.sound(SoundType)` — `[VERIFIED: javap net.minecraft.world.level.block.state.BlockBehaviour$Properties]`
- `SoundType.AMETHYST` exists — `[VERIFIED: javap net.minecraft.world.level.block.SoundType]`
- `BlockItem(Block, Item.Properties)` constructor — `[VERIFIED: javap net.minecraft.world.item.BlockItem]`
- `CreativeModeTabs.FUNCTIONAL_BLOCKS` is a `ResourceKey<CreativeModeTab>` — `[VERIFIED: javap net.minecraft.world.item.CreativeModeTabs]`
- `ItemGroupEvents.modifyEntriesEvent(ResourceKey<CreativeModeTab>)` returns `Event<ModifyEntries>`, `.register(ModifyEntries)` inherited from Fabric's `Event<T>` — `[VERIFIED: javap net.fabricmc.fabric.api.itemgroup.v1.ItemGroupEvents against fabric-item-group-api-v1-*-common.jar]`
- `FabricItemGroupEntries implements CreativeModeTab.Output`, so `.accept(ItemLike)` resolves via the default interface method — `[VERIFIED: javap net.fabricmc.fabric.api.itemgroup.v1.FabricItemGroupEntries]`

### Pattern 2: 4-Way Horizontal Facing (BLOCK-03, D-04)

**What:** `HorizontalDirectionalBlock` supplies the `FACING` property, `rotate()`, and `mirror()`. The subclass supplies `createBlockStateDefinition` and `getStateForPlacement`.
**When to use:** Any block that stores one of the 4 horizontal directions and needs vanilla-idiomatic rotate/mirror behavior for free.
**Example:**
```java
// Source: net.minecraft.world.level.block.HorizontalDirectionalBlock, AbstractFurnaceBlock —
// verified via javap AND javap -c (bytecode disassembly) against minecraft-common-*.jar
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

**Critical verified detail — the facing direction, settled by disassembly, not by reading a method name:** `HorizontalDirectionalBlock` does not override `getStateForPlacement` (it only supplies `FACING`, `rotate`, `mirror` — `[VERIFIED: javap net.minecraft.world.level.block.HorizontalDirectionalBlock]`). To confirm which of `getHorizontalDirection()` vs `getHorizontalDirection().getOpposite()` vs `getNearestLookingDirection().getOpposite()` matches D-04's "front faces the player" furnace convention, `AbstractFurnaceBlock.getStateForPlacement` was disassembled directly:

```
0: aload_0
1: invokevirtual  Method defaultBlockState:()Lnet/minecraft/world/level/block/state/BlockState;
4: getstatic      Field FACING:...DirectionProperty;
7: aload_1
8: invokevirtual  Method BlockPlaceContext.getHorizontalDirection:()Lnet/minecraft/core/Direction;
11: invokevirtual Method Direction.getOpposite:()Lnet/minecraft/core/Direction;
14: invokevirtual Method BlockState.setValue:(...)Ljava/lang/Object;
```
This is `defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite())` — exactly what the code example above does. `[VERIFIED: javap -c net.minecraft.world.level.block.AbstractFurnaceBlock against minecraft-common-*.jar, bytecode disassembly this session]`. `getHorizontalDirection()` (inherited on `BlockPlaceContext` from `UseOnContext`, confirmed via javap) returns the direction the *player* is facing when they click; its opposite is the direction the block's front should face so it looks back at the player.

`HorizontalDirectionalBlock.FACING` and `BlockStateProperties.HORIZONTAL_FACING` are the same field object — `HorizontalDirectionalBlock`'s static initializer assigns `FACING = BlockStateProperties.HORIZONTAL_FACING` — `[VERIFIED: javap -c net.minecraft.world.level.block.HorizontalDirectionalBlock, static initializer bytecode]`. Either reference works; use `FACING` since the block extends this class.

### Pattern 3: Datagen — Blockstate + Block Model (GEN-01)

**What:** A `FabricModelProvider` subclass that calls the correct `BlockModelGenerators` helper for a horizontal-facing, no-`LIT` block with a 3-texture (front/side/top) look.
**When to use:** Exactly this block's shape — 4-way facing, borrowed furnace textures, no lit/unlit variant.
**Example:**
```java
// Source: net.minecraft.data.models.BlockModelGenerators, TexturedModel, TextureSlot, TextureMapping
// — verified via javap AND javap -c (bytecode disassembly) against minecraft-common-*.jar,
// cross-checked against the real furnace.json/orientable.json extracted from the Minecraft client jar.
package transitreport.client;

import net.minecraft.data.models.BlockModelGenerators;
import net.minecraft.data.models.ItemModelGenerators;
import net.minecraft.data.models.model.TextureSlot;
import net.minecraft.data.models.model.TexturedModel;
import net.minecraft.resources.ResourceLocation;

import net.fabricmc.fabric.api.datagen.v1.FabricDataOutput;
import net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider;

import transitreport.TransitReportBlocks;

public final class TransitChartModelProvider extends FabricModelProvider {
    // ORIENTABLE_ONLY_TOP, not ORIENTABLE — see Common Pitfalls. Matches furnace's real
    // 3-texture model exactly (front/side/top, no bottom slot).
    private static final TexturedModel.Provider TRANSIT_CHART_TEXTURES = TexturedModel.ORIENTABLE_ONLY_TOP
            .updateTexture(mapping -> mapping
                    .put(TextureSlot.FRONT, new ResourceLocation("minecraft", "block/furnace_front"))
                    .put(TextureSlot.SIDE, new ResourceLocation("minecraft", "block/furnace_side"))
                    .put(TextureSlot.TOP, new ResourceLocation("minecraft", "block/furnace_top")));

    public TransitChartModelProvider(FabricDataOutput output) {
        super(output);
    }

    @Override
    public void generateBlockStateModels(BlockModelGenerators blockModelGenerators) {
        // NOT createFurnace() — see Common Pitfalls: it hardcodes a LIT dispatch this block lacks.
        blockModelGenerators.createHorizontallyRotatedBlock(TransitReportBlocks.TRANSIT_CHART, TRANSIT_CHART_TEXTURES);
    }

    @Override
    public void generateItemModels(ItemModelGenerators itemModelGenerators) {
        // Intentionally empty — the block-item's model is auto-generated as a parent reference
        // to the block model. See Common Pitfalls for the mechanism.
    }
}
```
Register it exactly like the existing language provider, in `JollyalchemyTransitReportDataGenerator.onInitializeDataGenerator`:
```java
pack.addProvider(TransitReportLanguageProvider::new);
pack.addProvider(TransitChartModelProvider::new);
```

`FabricModelProvider` constructor takes `FabricDataOutput` and requires overriding `generateBlockStateModels(BlockModelGenerators)` and `generateItemModels(ItemModelGenerators)` — `[VERIFIED: javap net.fabricmc.fabric.api.datagen.v1.provider.FabricModelProvider against fabric-data-generation-api-v1-*-common.jar]`.

### Anti-Patterns to Avoid

- **Calling `createFurnace(block, provider)` on a block without a `LIT` property:** see Common Pitfalls — bytecode-confirmed to hardcode `BlockStateProperties.LIT` into the generated blockstate dispatch.
- **Using `TexturedModel.ORIENTABLE` for a 3-texture (front/side/top) look:** requires a `BOTTOM` slot this project has no texture for.
- **Hand-writing any blockstate/model JSON under `src/main/resources`:** violates success criterion 4 outright. There are currently zero hand-written block JSON files in the repo — keep it that way; if a generated model doesn't load, fix the provider, don't hand-author a replacement.
- **Relying on static field initialization alone for registration:** `TransitReportBlocks.TRANSIT_CHART` as a bare static field is never touched unless `register()` is explicitly called from `onInitialize()` (D-09).
- **Introducing `BlockEntityType` this phase:** deferred by D-08 — `BaseEntityBlock.getRenderShape()` defaults to `INVISIBLE` and doesn't extend `HorizontalDirectionalBlock`; there is no benefit to paying that cost before Phase 4 needs it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|--------------|-----|
| 4-way facing state, rotate/mirror behavior | A custom `DirectionProperty` + hand-written `rotate`/`mirror` overrides | `HorizontalDirectionalBlock` | Supplies `FACING`, `rotate()`, `mirror()` for free; matches every vanilla furnace/chest/dispenser-family block. Hand-rolling risks subtly wrong rotate/mirror math that only surfaces when a structure block or `/setblock` with rotation is used later. |
| Item model for a block item | A hand-written `models/item/transit_chart.json` with `"parent": "jollyalchemy-transit-report:block/transit_chart"` | Leave `generateItemModels` empty; Fabric's model provider auto-generates the parented item model | This is exactly what success criterion 4 forbids (hand-written equivalent under `src/main/resources`), and the auto-generation mechanism already produces the identical parent-reference JSON under `src/main/generated`. |
| Blockstate JSON for 4 facing variants | Hand-written `blockstates/transit_chart.json` with 4 `variants` entries and y-rotations | `blockModelGenerators.createHorizontallyRotatedBlock(block, provider)` | One helper call reproduces the exact 4-entry structure (facing=north/east/south/west with y=0/90/180/270) that vanilla's own furnace blockstate has, confirmed by extracting `furnace.json` directly from the Minecraft client jar. |

**Key insight:** Every piece of JSON this phase needs (blockstate, block model, item model) has a corresponding vanilla helper method already used by a real vanilla block (the furnace) with an all-but-identical texture/facing shape. The work is choosing the *right* helper (see Common Pitfalls), not writing JSON by hand or writing a new datagen abstraction.

## Common Pitfalls

### Pitfall 1: `createFurnace()` hardcodes a `LIT` dispatch this block doesn't have

**What goes wrong:** Calling `blockModelGenerators.createFurnace(TransitReportBlocks.TRANSIT_CHART, someProvider)` in `generateBlockStateModels` throws (or silently produces a malformed blockstate — behavior not fully exercised without running it, but the property-dispatch validation path is exactly what `PropertyDispatch`/`MultiVariantGenerator` exist to enforce) because `createFurnace`'s bytecode unconditionally builds a `MultiVariantGenerator.multiVariant(block).with(createBooleanModelDispatch(BlockStateProperties.LIT, onModel, offModel)).with(createHorizontalFacingDispatch())`. `TransitChartBlock`'s state definition only has `FACING` — no `LIT`.
**Why it happens:** `createFurnace` is named after "the furnace's specific 2-state (lit/unlit) × 4-facing model" — it is not a generic "orientable cube with these 3 textures" helper, despite D-03's texture choice making it look like the obvious match.
**How to avoid:** Use `createHorizontallyRotatedBlock(Block, TexturedModel.Provider)` instead — confirmed via bytecode to build only `MultiVariantGenerator.multiVariant(block, Variant.variant().with(MODEL, modelLoc)).with(createHorizontalFacingDispatch())`, with no `LIT` involvement.
**Warning signs:** `./gradlew runDatagen` throwing during model generation, or (if it doesn't throw) a generated blockstate JSON with unexpected `lit=` keys in its variant selectors.

### Pitfall 2: `TexturedModel.ORIENTABLE` needs a texture this project doesn't have

**What goes wrong:** `TexturedModel.ORIENTABLE.get(block)` derives a `TextureMapping` via `TextureMapping.orientableCube(block)`, which fills `FRONT`, `SIDE`, `TOP`, **and `BOTTOM`** (confirmed by bytecode disassembly of `orientableCube`). Overriding only `FRONT`/`SIDE`/`TOP` via `.updateTexture(...)` leaves `BOTTOM` defaulted to `jollyalchemy-transit-report:block/transit_chart_bottom` — a file that does not exist (D-03 adds no texture files). The bottom face renders as the missing-texture checkerboard.
**Why it happens:** `TexturedModel.ORIENTABLE`'s name suggests "the standard orientable-block texture set," but it is actually paired internally with `ModelTemplates.CUBE_ORIENTABLE_TOP_BOTTOM` (4 texture slots), not the 3-slot `ModelTemplates.CUBE_ORIENTABLE` that vanilla's own furnace model actually uses.
**How to avoid:** Use `TexturedModel.ORIENTABLE_ONLY_TOP` — confirmed by bytecode to be paired with `ModelTemplates.CUBE_ORIENTABLE` (`FRONT`/`SIDE`/`TOP` only) via `TextureMapping.orientableCubeOnlyTop`, and confirmed to match vanilla's real `furnace.json` (extracted directly from the Minecraft client jar: `{"parent": "minecraft:block/orientable", "textures": {"front": ..., "side": ..., "top": ...}}` — no `bottom` key at all).
**Warning signs:** A missing-texture checkerboard visible only when looking at the underside of the placed block (easy to miss during the D-05 visual check, since the bottom face is rarely looked at directly) — this is exactly the kind of partial failure the phase's success criterion 3 is meant to catch, so verify by briefly checking the bottom face too, or by inspecting the generated block model JSON for a stray `bottom` key.

### Pitfall 3: Forgetting the explicit `register()` call (static-initialization gotcha)

**What goes wrong:** Java does not run a class's static field initializers until the class is first referenced. If `TransitReportBlocks.TRANSIT_CHART` is only ever a `public static final` field with no explicit `register()`/`initialize()` call from `onInitialize()`, the block may never actually be added to the registry — or may be added at an unpredictable time if some other code path happens to touch the class first.
**Why it happens:** This looks like it should "just work" because the field itself calls `new TransitChartBlock(...)` at declaration time — but `Registry.register(...)` is a separate statement inside `register()`, not something that runs from the field declaration alone.
**How to avoid:** D-09's holder pattern: an explicit `TransitReportBlocks.register()` method, called once from `JollyalchemyTransitReport.onInitialize()`.
**Warning signs:** The block/item silently absent from the creative tab and unplaceable, with no error logged (a missing registration doesn't throw — it just never happens).

### Pitfall 4: Reaching for `BaseEntityBlock` early

**What goes wrong:** If a future edit (in this phase or by pulling Phase 4 work forward) switches the block's superclass to `BaseEntityBlock` for its `EntityBlock`-adjacent helpers without overriding `getRenderShape()`, the block renders as fully invisible — not a checkerboard, nothing at all — because `BaseEntityBlock.getRenderShape(BlockState)` defaults to `RenderShape.INVISIBLE`. It also silently drops the inherited `FACING`/`rotate`/`mirror` behavior since `BaseEntityBlock extends Block`, not `HorizontalDirectionalBlock`.
**Why it happens:** `BaseEntityBlock` is the class most non-block-entity Fabric tutorials reach for as soon as a block has "moving parts," which invites pulling it in prematurely.
**How to avoid:** Stay on `HorizontalDirectionalBlock` this phase (D-08). If Phase 4 needs a block entity, implement the `EntityBlock` interface directly on `TransitChartBlock` rather than changing its superclass.
**Warning signs:** A perfectly-registered, perfectly-facing block that simply never appears in the world — easy to misdiagnose as a renderer bug rather than a superclass regression.

## Code Examples

See Architecture Patterns above — all three code examples (registration holder, `TransitChartBlock`, `TransitChartModelProvider`) are the verified patterns for this phase, each annotated with which specific `javap`/bytecode check grounds it.

## State of the Art

Not applicable in the usual "library X replaced library Y" sense — this phase uses only vanilla Minecraft and Fabric API classes already pinned by Phase 1. The one relevant "state of the art" fact is a *non-change*: current (post-1.21) Fabric documentation describes a `RenderPipeline`/`GpuTexture`-based model/texture registration flow that does not exist in 1.20.1. Nothing in this phase's scope (registration, facing, datagen) is affected by that shift, since it's purely a rendering-internals change — but it means any current `docs.fabricmc.net` example involving block model registration or texture pipeline should not be trusted for this project; the vanilla model-generator classes verified in this document (`BlockModelGenerators`, `TexturedModel`, `TextureMapping`, `ModelTemplates`) are unaffected by that 1.21+ change and are stable through 1.20.1.

**Deprecated/outdated:** N/A this phase.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|----------------|
| A1 | Fabric's `ModelProviderMixin` auto-generates a parented item model (`{"parent": "<ns>:block/<path>"}`) for any registered `BlockItem` that doesn't call `skipAutoItemBlock()` or otherwise register an explicit item model. Confirmed structurally (the mixin's `filterItemsForProcessingMod`/`registerItemModels` methods and the `skipAutoItemBlock`/`delegateItemModel` opt-out API exist and are consistent with this behavior), but the exact JSON shape it emits was not directly observed by running `runDatagen` in this research session. | Code Examples (Pattern 3), Don't Hand-Roll | If wrong, GEN-02 (item model produced by datagen) fails silently — the item would show a missing-model icon. Low risk: this is Fabric API's well-documented "automatic item models for block items" feature, and the opt-out method names (`skipAutoItemBlock`) only make sense if this is the default behavior. The planner should have the executor run `runDatagen` early and inspect `src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json` before relying on this further. |

**If this table is empty:** N/A — see A1 above. Every other technical claim in this document (facing direction, `createFurnace`/`createHorizontallyRotatedBlock` distinction, `ORIENTABLE`/`ORIENTABLE_ONLY_TOP` distinction, registration API shapes) was confirmed via `javap` or `javap -c` bytecode disassembly against the actual compiled jars this project builds against, or by extracting and reading the real vanilla furnace/orientable JSON assets directly from the Minecraft client jar.

## Open Questions

1. **Does `runDatagen` actually succeed with the recommended `createHorizontallyRotatedBlock` + `ORIENTABLE_ONLY_TOP` combination, end to end?**
   - What we know: Both methods' bytecode was disassembled and their required-slot contracts line up exactly (3 slots: FRONT/SIDE/TOP, matching vanilla's real furnace model).
   - What's unclear: No `runDatagen` execution happened during this research session (research is a static/read-only investigation, not an execution step).
   - Recommendation: Have the plan's first task run `./gradlew runDatagen` immediately after writing the block + provider, and inspect the three generated files (blockstate, block model, item model) before moving on to placement/facing verification. This is a fast, cheap, automated check that would catch a Pitfall-1/Pitfall-2-style regression immediately.

2. **Exact generated JSON content for the auto-item-model (A1).**
   - What we know: The mechanism exists (per `skipAutoItemBlock`/`delegateItemModel` API surface).
   - What's unclear: Whether it needs any nudging (e.g., does it require the block to have been processed via `generateBlockStateModels` in the *same* provider run, or does it work across providers) — irrelevant here since both methods are on the same `TransitChartModelProvider`, but worth confirming by inspection rather than assumption.
   - Recommendation: Same as Open Question 1 — verify by reading the generated file, not by re-deriving from bytecode.

## Environment Availability

Inherited from Phase 1 — no new external dependencies. Phase 1 (`TOOL-01`, `TOOL-02`, `TOOL-03`) already verified `./gradlew runClient` and `./gradlew runDatagen` both work end-to-end on this machine, and `docs/DEV.md` documents the dev loop. This phase adds no new tool, service, or runtime dependency — only new Java source files and generated JSON.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `./gradlew runDatagen` | GEN-01, GEN-02 verification | ✓ (Phase 1 verified) | Loom 1.17-SNAPSHOT / Fabric API 0.92.12+1.20.1 | — |
| `./gradlew runClient` | BLOCK-01, BLOCK-02, BLOCK-03 visual verification (D-05) | ✓ (Phase 1 verified, reusable `gsd-dev` world exists) | — | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None configured — no JUnit test source set exists in this repo (confirmed: no `src/test`, no test files found). |
| Config file | none |
| Quick run command | n/a — this phase's surface (`Block`/`BlockItem` registration, datagen providers) is Minecraft-API-bound code with no practical unit-test seam, matching CLAUDE.md §7's explicit boundary ("Actual OpenGL rendering output ... no practical automated way to assert this ... verify visually"). |
| Full suite command | n/a |

No JUnit test infrastructure gap is being opened by this phase — per CLAUDE.md §7, HTTP client / config / scheduler logic (Phases 5+) are where unit tests belong; block registration and datagen are exercised by generated-file assertions and a running client, not unit tests.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|--------------------|-------------|
| GEN-01 | Blockstate JSON has exactly 4 `FACING` variants (north/east/south/west), no `lit` key | automated (file assertion) | `./gradlew runDatagen && grep -c '"facing='  src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json` (expect 4) and `grep -c '"lit' src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json` (expect 0) | ❌ Wave 0 — file doesn't exist until this phase's task runs `runDatagen` |
| GEN-01 | Block model parents `minecraft:block/orientable` with `front`/`side`/`top` texture keys pointing at furnace textures | automated (file assertion) | `cat src/main/generated/assets/jollyalchemy-transit-report/models/block/transit_chart.json` — manually diff against expected content | ❌ Wave 0 |
| GEN-02 | Item model JSON exists and parents the block model | automated (file assertion) | `cat src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json` | ❌ Wave 0 |
| BLOCK-02 | Translation key resolves to "Transit Chart" | automated (file assertion) | `grep 'block.jollyalchemy-transit-report.transit_chart' src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` (expect `"Transit Chart"`) | ❌ Wave 0 |
| BLOCK-01, BLOCK-02, BLOCK-03 | Block places, appears in creative tab, orients to 4 directions, draws a real model | manual-only (visual, D-05) | Claude launches `./gradlew runClient` in background, tails log for readiness; user places the block from 4 approach directions and confirms 4 distinct front-facing results, confirms it appears in the Functional Blocks creative tab labeled "Transit Chart", confirms no missing-texture checkerboard | n/a — requires a running client, no automated substitute per CLAUDE.md §7 |

### Sampling Rate

- **Per task commit:** `./gradlew runDatagen` + the grep/cat assertions above (fast, seconds).
- **Per wave merge:** `./gradlew build` (full compile) + re-run datagen assertions.
- **Phase gate:** `./gradlew build` green, then the D-05 visual protocol in a running dev client before `/gsd-verify-work`.

### Wave 0 Gaps

- [ ] `src/main/generated/assets/jollyalchemy-transit-report/blockstates/transit_chart.json` — does not exist until the block + model provider are written and `runDatagen` is run; this is expected, not a pre-existing gap to fill before starting.
- [ ] `src/main/generated/assets/jollyalchemy-transit-report/models/block/transit_chart.json` — same.
- [ ] `src/main/generated/assets/jollyalchemy-transit-report/models/item/transit_chart.json` — same.
- No test-framework install is needed — this phase's surface has no unit-testable seam per CLAUDE.md §7's established boundary.

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | no | This phase has no authentication surface — it is client-side block/item registration and static data generation. |
| V3 Session Management | no | No session concept exists at this layer. |
| V4 Access Control | no | Placement/breaking permissions are entirely vanilla Minecraft world-permission mechanics (creative/survival, protection plugins if any); this phase adds no new permission surface. |
| V5 Input Validation | no | The only "input" this phase processes is `BlockPlaceContext` derived from the local player's own click — a trusted, vanilla-validated, in-process value, not untrusted external data. No network, no file, no user-text input is introduced. |
| V6 Cryptography | no | Not applicable — no cryptographic operation in this phase. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|-----------------------|
| N/A this phase | — | This phase's entire surface is compile-time-registered game content (block, item, generated JSON) with no network, file-parsing, or cross-trust-boundary input. The project's actual threat surface (HTTP fetch, PNG decode, config file parsing) does not begin until Phase 5 (API client) and Phase 6 (texture pipeline) — REQUIREMENTS.md's API-05/API-06/CFG-03 are the relevant future controls, not this phase's concern. |

## Sources

### Primary (HIGH confidence — direct tool verification against the exact compiled jars this project builds against)

- `javap` against `.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-common-487d1d375f/1.20.1-loom.mappings.1_20_1.layered+hash.2198-v2/*.jar` (Mojang official mappings, Minecraft 1.20.1 common classes) — `HorizontalDirectionalBlock`, `BlockPlaceContext`, `UseOnContext`, `AbstractFurnaceBlock` (including `javap -c` bytecode disassembly of `getStateForPlacement` and the static initializer), `BlockBehaviour.Properties`, `SoundType`, `BlockItem`, `Item.Properties`, `Registry`, `BuiltInRegistries`, `CreativeModeTabs`, `CreativeModeTab.Output`, `BlockModelGenerators` (including `javap -c` disassembly of `createFurnace` and `createHorizontallyRotatedBlock`), `TexturedModel` (including static-initializer disassembly), `TextureMapping` (including `orientableCube`/`orientableCubeOnlyTop` disassembly), `TextureSlot`, `ModelTemplates` (including static-initializer disassembly), `ModelLocationUtils`, `ModelProvider`, `EntityBlock`, `BaseEntityBlock`.
- `unzip -p` extraction of `assets/minecraft/models/block/furnace.json` and `assets/minecraft/blockstates/furnace.json` directly from `.gradle/loom-cache/minecraftMaven/.../minecraft-clientOnly-*.jar` (the real, shipped vanilla furnace model/blockstate — used to cross-check the `ORIENTABLE_ONLY_TOP`/`createHorizontallyRotatedBlock` recommendation against ground truth).
- `unzip -l` against `.gradle/loom-cache/minecraftMaven/.../minecraft-clientOnly-*.jar` confirming no `furnace_bottom.png` texture asset exists in vanilla — grounds the rejection of `TexturedModel.ORIENTABLE`.
- `javap` / `unzip -l` against `.gradle/loom-cache/remapped_mods/remapped/net/fabricmc/fabric-api/fabric-item-group-api-v1-c2d2b86c-common/4.0.14+1802ada577/*.jar` — `ItemGroupEvents`, `ItemGroupEvents.ModifyEntries`, `FabricItemGroupEntries`.
- `javap` / `unzip -l` against `.gradle/loom-cache/remapped_mods/remapped/net/fabricmc/fabric-api/fabric-data-generation-api-v1-c2d2b86c-common/12.4.0+238242b777/*.jar` — `FabricModelProvider`, `FabricLanguageProvider`/`TranslationBuilder`, and (via `javap -p`) the `ModelProviderMixin` structure that grounds the auto-item-model behavior (Assumption A1).
- Direct read of this repo's existing source files: `build.gradle`, `gradle.properties`, `src/main/java/transitreport/JollyalchemyTransitReport.java`, `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java`, `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java`, `src/main/resources/fabric.mod.json`, `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json`, `docs/DEV.md`, `.planning/config.json`.

### Secondary (MEDIUM confidence)

- None used — every technical claim was settled against primary sources this session, consistent with this project's established working practice (CLAUDE.md §2, PROJECT.md) of preferring resolved sources over documentation for 1.20.1 API questions.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all classes verified present in the exact pinned-version jars.
- Architecture: HIGH — registration, facing, and datagen patterns all confirmed via `javap`/bytecode disassembly, several cross-checked against real vanilla furnace JSON extracted from the client jar.
- Pitfalls: HIGH — the two most consequential pitfalls (`createFurnace`'s hidden `LIT` dispatch, `ORIENTABLE` vs `ORIENTABLE_ONLY_TOP`) were caught specifically *because* bytecode disassembly was used instead of trusting method/field names, and both are cross-verified against the real furnace model/blockstate JSON.

**Research date:** 2026-09-08
**Valid until:** Stable for the life of this Minecraft/Loom/Fabric API pin (`minecraft_version=1.20.1`, `fabric_api_version=0.92.12+1.20.1`) — re-verify only if any of those three properties change.

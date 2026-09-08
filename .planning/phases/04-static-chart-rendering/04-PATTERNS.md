# Phase 4: Static Chart Rendering - Pattern Map

**Mapped:** 2026-09-08
**Files analyzed:** 6 (1 modified, 5 new)
**Analogs found:** 4 / 6 (Phase 2 registration patterns reused; BlockEntity and Renderer have no existing analog, patterns sourced from RESEARCH.md)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/main/java/transitreport/block/TransitChartBlock.java` | block | state-management | itself (Phase 2) | exact |
| `src/main/java/transitreport/block/entity/TransitChartBlockEntity.java` | model | state-management | RESEARCH.md Pattern (no existing analog) | reference |
| `src/client/java/transitreport/client/TransitChartRenderer.java` | renderer | streaming | RESEARCH.md Pattern (no existing analog) | reference |
| `src/main/java/transitreport/TransitReportBlocks.java` | registration | initialization | itself (Phase 2) | exact |
| `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` | registration | initialization | itself (Phase 2) | exact |
| `src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png` | asset | file-I/O | standard Minecraft asset structure | reference |

## Pattern Assignments

### `src/main/java/transitreport/block/TransitChartBlock.java` (block, state-management) — MODIFY

**Analog:** Existing Phase 2 implementation (same file)

**Current implementation** (lines 1–56):
```java
package transitreport.block;

import net.minecraft.core.Direction;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.TooltipFlag;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.HorizontalDirectionalBlock;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;

public class TransitChartBlock extends HorizontalDirectionalBlock {
	public TransitChartBlock(BlockBehaviour.Properties properties) {
		super(properties);
		this.registerDefaultState(this.stateDefinition.any().setValue(FACING, Direction.NORTH));
	}

	@Override
	protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
		builder.add(FACING);
	}

	@Override
	public BlockState getStateForPlacement(BlockPlaceContext context) {
		return this.defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite());
	}
	// ... tooltip method (unchanged)
}
```

**Pattern to add - EntityBlock interface** (add to class declaration):
```java
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.EntityBlock;

public class TransitChartBlock extends HorizontalDirectionalBlock implements EntityBlock {
	// ... existing code unchanged ...
	
	// Add new method:
	@Override
	public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
		return new TransitChartBlockEntity(pos, state);
	}
}
```

**Key points:**
- Do **NOT** change base class from `HorizontalDirectionalBlock` (CONTEXT.md D-08 landmine)
- Implement `EntityBlock` interface to signal "this block has a block entity"
- `newBlockEntity()` creates and returns the block entity instance
- Import: `net.minecraft.world.level.block.entity.BlockEntity`, `net.minecraft.world.level.block.EntityBlock`
- `getRenderShape()` is already correct (defaults to `MODEL`); do not override

---

### `src/main/java/transitreport/block/entity/TransitChartBlockEntity.java` (model, state-management) — NEW

**Analog:** RESEARCH.md Pattern (Skeleton Pattern, Code Example 4), no existing codebase analog

**Imports pattern:**
```java
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.AABB;

import transitreport.TransitReportBlocks;
```

**Core BlockEntity pattern** (from RESEARCH.md, Pattern section):
```java
public class TransitChartBlockEntity extends BlockEntity {
	public TransitChartBlockEntity(BlockPos pos, BlockState blockState) {
		super(TransitReportBlockEntities.TRANSIT_CHART, pos, blockState);
	}
	
	@Override
	public AABB getRenderBoundingBox() {
		// Expand AABB to prevent culling of oversized quad (REND-03)
		// Quad is 2 blocks wide, ~3.125 blocks tall (aspect ratio from 512:800 image)
		// Bottom-anchored at y=0, centered horizontally on block
		
		double x = this.getBlockPos().getX();
		double y = this.getBlockPos().getY();
		double z = this.getBlockPos().getZ();
		
		float width = 2.0f;
		float height = 3.125f;
		float offset = 0.01f;
		
		double quadLeft = x + (1.0 - width) / 2.0;
		double quadRight = quadLeft + width;
		double quadBottom = y;
		double quadTop = y + height;
		double quadFront = z;
		double quadBack = z + offset + 0.001;
		
		return new AABB(quadLeft, quadBottom, quadFront, quadRight, quadTop, quadBack);
	}
}
```

**Key points:**
- Extends `BlockEntity`; pass the entity type to super constructor (see registration pattern below)
- Override `getRenderBoundingBox()` to prevent oversized quad from being culled (REND-03)
- AABB constructor: `new AABB(minX, minY, minZ, maxX, maxY, maxZ)` — coordinates in world space, not block-local
- Constructor takes `BlockPos` and `BlockState`; required by Minecraft

---

### `src/client/java/transitreport/client/TransitChartRenderer.java` (renderer, streaming) — NEW

**Analog:** RESEARCH.md Code Examples 1–3 (no existing codebase analog)

**Imports pattern** (from RESEARCH.md, Code Examples 1–3):
```java
import com.mojang.blaze3d.vertex.PoseStack;
import net.minecraft.client.renderer.MultiBufferSource;
import net.minecraft.client.renderer.texture.TextureAtlasSprite;
import net.minecraft.client.renderer.block.BlockRenderDispatcher;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderer;
import net.minecraft.client.renderer.blockentity.BlockEntityRendererProvider;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.LightmapTextureManager;
import net.minecraft.core.Direction;
import net.minecraft.world.level.block.state.BlockState;
import com.mojang.blaze3d.vertex.VertexConsumer;

import transitreport.JollyalchemyTransitReport;
import transitreport.block.entity.TransitChartBlockEntity;
```

**Core renderer pattern** (from RESEARCH.md Code Examples 1–3):
```java
public class TransitChartRenderer implements BlockEntityRenderer<TransitChartBlockEntity> {
	private static final ResourceLocation TEXTURE = JollyalchemyTransitReport.id("textures/block/transit_chart");
	
	// Quad dimensions (from CONTEXT.md D-05)
	private static final float BASE_WIDTH = 2.0f;
	private static final float ASPECT_RATIO = 800.0f / 512.0f;  // height / width from 512×800 image
	private static final float COMPUTED_HEIGHT = BASE_WIDTH * ASPECT_RATIO;  // ~3.125f
	private static final float Z_OFFSET = 0.01f;  // small float to avoid z-fighting
	
	@Override
	public void render(TransitChartBlockEntity blockEntity, float partialTick, PoseStack matrices, 
	                    MultiBufferSource vertexConsumers, int packedLight, int packedOverlay) {
		// 1. Get block state and facing direction
		BlockState blockState = blockEntity.getBlockState();
		Direction facing = blockState.getValue(TransitReportBlocks.TRANSIT_CHART.FACING);
		
		// 2. Bind texture and get VertexConsumer for textured surface
		VertexConsumer vertexConsumer = vertexConsumers.getBuffer(RenderType.entityCutout(TEXTURE));
		
		// 3. Save matrix state and apply transforms
		matrices.pushPose();
		
		// Translate to block center, rotate, translate back
		matrices.translate(0.5f, 0.5f, 0.5f);
		
		// Rotation per facing: 0°=NORTH, 90°=EAST, 180°=SOUTH, 270°=WEST
		float rotationDegrees = (float) ((facing.get2DDataValue() * 90) % 360);
		matrices.mulPose(Axis.YP.rotationDegrees(rotationDegrees));
		
		matrices.translate(-0.5f, -0.5f, -0.5f);
		
		// 4. Submit quad vertices (from RESEARCH.md Code Example 2)
		submitQuad(matrices, vertexConsumer, packedLight, packedOverlay);
		
		matrices.popPose();
	}
	
	private void submitQuad(PoseStack matrices, VertexConsumer vertexConsumer, int packedLight, int packedOverlay) {
		// Vertex order: counter-clockwise from front (right-hand rule)
		// Coordinates in normalized block space [0, 1]³, then transformed by PoseStack
		
		// Center quad horizontally on block face
		float x0 = (1.0f - BASE_WIDTH) / 2.0f;
		float x1 = x0 + BASE_WIDTH;
		float y0 = 0.0f;  // bottom-anchored (CONTEXT.md D-08)
		float y1 = COMPUTED_HEIGHT;
		float z = Z_OFFSET;
		
		float u0 = 0.0f, u1 = 1.0f;  // texture UV coords
		float v0 = 0.0f, v1 = 1.0f;
		
		int light = LightmapTextureManager.MAX_LIGHT_COORDINATE;  // emissive (REND-05)
		int overlay = packedOverlay;
		
		var matrix = matrices.last();
		
		// Vertex 0: top-left
		vertexConsumer
			.vertex(matrix, x0, y1, z)
			.color(255, 255, 255, 255)
			.uv(u0, v0)
			.overlayCoordinates(overlay)
			.uv2(light)
			.normal(matrix, 0.0f, 0.0f, 1.0f)
			.endVertex();
		
		// Vertex 1: top-right
		vertexConsumer
			.vertex(matrix, x1, y1, z)
			.color(255, 255, 255, 255)
			.uv(u1, v0)
			.overlayCoordinates(overlay)
			.uv2(light)
			.normal(matrix, 0.0f, 0.0f, 1.0f)
			.endVertex();
		
		// Vertex 2: bottom-right
		vertexConsumer
			.vertex(matrix, x1, y0, z)
			.color(255, 255, 255, 255)
			.uv(u1, v1)
			.overlayCoordinates(overlay)
			.uv2(light)
			.normal(matrix, 0.0f, 0.0f, 1.0f)
			.endVertex();
		
		// Vertex 3: bottom-left
		vertexConsumer
			.vertex(matrix, x0, y0, z)
			.color(255, 255, 255, 255)
			.uv(u0, v1)
			.overlayCoordinates(overlay)
			.uv2(light)
			.normal(matrix, 0.0f, 0.0f, 1.0f)
			.endVertex();
	}
	
	@Override
	public int getViewDistance() {
		return 64;  // default render distance
	}
}
```

**Key points:**
- Implements `BlockEntityRenderer<TransitChartBlockEntity>`
- `render()` called once per frame per visible block entity
- Use `LightmapTextureManager.MAX_LIGHT_COORDINATE` (15728880) for emissive rendering (REND-05)
- `matrices.pushPose()` / `popPose()` **must** be paired symmetrically (RESEARCH.md Pitfall 2)
- Vertex submission: `vertex()` → `color()` → `uv()` → `overlayCoordinates()` → `uv2()` → `normal()` → `endVertex()`
- Method is called `.uv2()` not `.light()` in 1.20.1 Mojmap (CLAUDE.md §2, RESEARCH.md Pitfall 4)
- `FACING` property inherited from `HorizontalDirectionalBlock` (Phase 2 pattern)

---

### `src/main/java/transitreport/TransitReportBlocks.java` (registration, initialization) — MODIFY

**Analog:** Existing Phase 2 implementation (same file)

**Current pattern** (lines 1–42, excerpt):
```java
package transitreport;

import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.entity.BlockEntityType;

public final class TransitReportBlocks {
	public static final Block TRANSIT_CHART = new TransitChartBlock(...);
	
	// ADD NEW FIELD:
	public static final BlockEntityType<TransitChartBlockEntity> TRANSIT_CHART = 
		BlockEntityType.Builder.of(TransitChartBlockEntity::new, TRANSIT_CHART)
			.build(null);
	
	public static void register() {
		Registry.register(BuiltInRegistries.BLOCK, JollyalchemyTransitReport.id("transit_chart"), TRANSIT_CHART);
		Registry.register(BuiltInRegistries.ITEM, JollyalchemyTransitReport.id("transit_chart"), TRANSIT_CHART_ITEM);
		
		// ADD NEW REGISTRATION:
		Registry.register(BuiltInRegistries.BLOCK_ENTITY_TYPE, 
			JollyalchemyTransitReport.id("transit_chart"), 
			TRANSIT_CHART_BLOCK_ENTITY);
		
		ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)
			.register(entries -> entries.accept(TRANSIT_CHART_ITEM));
	}
}
```

**Imports to add:**
```java
import net.minecraft.world.level.block.entity.BlockEntityType;
import transitreport.block.entity.TransitChartBlockEntity;
```

**Key points:**
- Create `BlockEntityType` field using `BlockEntityType.Builder.of(factory, ...)`
- Factory is a method reference: `TransitChartBlockEntity::new`
- Second parameter to `Builder.of()` is the block(s) this entity type is attached to
- Use existing registration pattern: `Registry.register(BuiltInRegistries.BLOCK_ENTITY_TYPE, id, type)`
- Field must be `public static final` so client-side renderer registration can access it

---

### `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` (registration, initialization) — MODIFY

**Analog:** Existing Phase 2 implementation (same file, currently empty)

**Current implementation** (lines 1–10):
```java
package transitreport.client;

import net.fabricmc.api.ClientModInitializer;

public class JollyalchemyTransitReportClient implements ClientModInitializer {
	@Override
	public void onInitializeClient() {
		// This entrypoint is suitable for setting up client-specific logic, such as rendering.
	}
}
```

**Pattern to add - Renderer registration**:
```java
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.rendering.v1.BlockEntityRenderers;

import transitreport.TransitReportBlocks;
import transitreport.client.TransitChartRenderer;

public class JollyalchemyTransitReportClient implements ClientModInitializer {
	@Override
	public void onInitializeClient() {
		BlockEntityRenderers.register(
			TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY,
			context -> new TransitChartRenderer()
		);
	}
}
```

**Key points:**
- Call `BlockEntityRenderers.register()` in `onInitializeClient()` (client-only entry point)
- First parameter: the `BlockEntityType` registered in `TransitReportBlocks`
- Second parameter: factory lambda creating the renderer instance
- Renderer factory receives `BlockEntityRendererProvider.Context` (unused in this simple pattern)
- Import: `net.fabricmc.fabric.api.client.rendering.v1.BlockEntityRenderers`

---

### `src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png` (asset, file-I/O) — NEW

**Analog:** Standard Minecraft asset directory structure (no code analog; follows convention)

**Path and resource location:**
```
File path (on disk):
  src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png

ResourceLocation (in code):
  JollyalchemyTransitReport.id("textures/block/transit_chart")
  expands to: jollyalchemy-transit-report:textures/block/transit_chart
```

**Content:**
- Copy `sample-bodygraph.png` (project root) verbatim into this location
- No modification, no overlay, no synthetic marker (CONTEXT.md D-01, D-02)
- File is 512 × 800 pixels, RGB format, no alpha channel

**Key points:**
- Asset path structure is `assets/{modid}/textures/{category}/{name}.png`
- `{category}` = `block` (signifies this is a block entity resource)
- `{name}` = `transit_chart` (matches block name for clarity)
- ResourceLocation created via `JollyalchemyTransitReport.id()` helper (Phase 2 pattern)
- Minecraft's resource system loads this automatically; no manual I/O needed

---

## Shared Patterns

### Mojang Official Mappings (All Files)
**Source:** `.claude/CLAUDE.md` §2

**Apply to:** All Java files in this phase

The codebase uses **Mojang official mappings**, not Yarn. Key class/method names (copy from Phase 2 pattern):
```java
// CORRECT (Mojmap):
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.client.renderer.blockentity.BlockEntityRenderer;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.client.renderer.LightmapTextureManager;
import com.mojang.blaze3d.vertex.PoseStack;

// WRONG (Yarn, will not compile):
// import net.minecraft.block.entity.BlockEntity;  // Mojmap is world.level.block.entity
// import net.minecraft.client.render.block.entity.BlockEntityRenderer;  // Mojmap is renderer
// import net.minecraft.client.render.RenderLayer;  // Mojmap is RenderType, and RenderLayer is unrelated
```

### Block Entity + Renderer Lifecycle
**Source:** RESEARCH.md System Architecture, CONTEXT.md D-08 landmine

**Apply to:** All integration points (Block, BlockEntity, Renderer, Registration)

Sequence:
1. **Block class** (`TransitChartBlock`) implements `EntityBlock` interface
2. `EntityBlock.newBlockEntity(BlockPos, BlockState)` → creates `TransitChartBlockEntity` instance
3. **Registration** (`TransitReportBlocks`) registers the `BlockEntityType`
4. **Client registration** (`JollyalchemyTransitReportClient`) registers the `BlockEntityRenderer`
5. Minecraft calls `Renderer.render()` every frame for each visible block entity

### Matrix Stack State Management
**Source:** RESEARCH.md Pitfalls 2, Code Example 1

**Apply to:** `TransitChartRenderer.render()`

Pattern:
```java
matrices.pushPose();    // MUST be called first
try {
	// ... transformations and vertex submission ...
} finally {
	matrices.popPose();  // MUST be called last, even on exception
}
```

**Why critical:** Matrix stack is global across all renderers; unbalanced pushPose/popPose corrupts transforms for all subsequent renderers in the same frame.

### Emissive Rendering
**Source:** RESEARCH.md Pitfalls 4, Code Example 2

**Apply to:** `TransitChartRenderer.submitQuad()`

Pattern:
```java
int light = LightmapTextureManager.MAX_LIGHT_COORDINATE;  // 15728880 (full brightness)
vertexConsumer.uv2(light);  // NOT .light() — uv2 is the lightmap in 1.20.1 Mojmap
```

**Why:** Block must be visible and readable in total darkness (REND-05). Ignores ambient `packedLight` parameter.

### Resource Location Naming
**Source:** Phase 2 pattern, RESEARCH.md Open Questions 1

**Apply to:** Texture paths, block entity type registration

Pattern:
```java
JollyalchemyTransitReport.id("textures/block/transit_chart")
// expands to: jollyalchemy-transit-report:textures/block/transit_chart

JollyalchemyTransitReport.id("transit_chart")
// for registration: jollyalchemy-transit-report:transit_chart
```

---

## No Analog Found

Files with patterns sourced entirely from RESEARCH.md (no existing codebase equivalent):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `TransitChartBlockEntity.java` | model | state-management | First block entity in this mod; no prior Phase 1–3 example |
| `TransitChartRenderer.java` | renderer | streaming | First custom renderer in this mod; no prior Phase 1–3 example |

Both are covered comprehensively in RESEARCH.md Code Examples 1–4 and Pattern sections. Planner should reference those sections when implementing.

---

## Metadata

**Analog search scope:** 
- `src/main/java/**/*.java` — common source set (Phase 2 block registration)
- `src/client/java/**/*.java` — client-only source set (Phase 2 client registration, datagen)
- `src/main/resources/assets/**` — asset directory structure (Phase 2 texture path convention)

**Files scanned:** 5 (4 Java source files, 1 data generator file)

**Pattern extraction date:** 2026-09-08

**Git-tracked sources confirmed:**
- `src/main/java/transitreport/block/TransitChartBlock.java` — tracked
- `src/main/java/transitreport/TransitReportBlocks.java` — tracked
- `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` — tracked
- `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` — tracked

---

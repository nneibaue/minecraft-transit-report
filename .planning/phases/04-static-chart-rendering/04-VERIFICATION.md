---
phase: 04-static-chart-rendering
verified: 2026-09-08T00:00:00Z
status: passed
score: 7/7 must-haves verified
covered_files:
  - .planning/phases/04-static-chart-rendering/04-01-PLAN.md
  - .planning/phases/04-static-chart-rendering/04-01-SUMMARY.md
  - .planning/phases/04-static-chart-rendering/04-CONTEXT.md
  - docs/DEV.md
  - src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
  - src/client/java/transitreport/client/TransitChartRenderer.java
  - src/main/java/transitreport/TransitReportBlocks.java
  - src/main/java/transitreport/block/TransitChartBlock.java
  - src/main/java/transitreport/block/entity/TransitChartBlockEntity.java
  - src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png
covered_digest: "v1:sha256:0c093217625e38019eacfcb4354349bf61dff3323d35f8ee98a5a946420f2139"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 04: Static Chart Rendering - Verification Report

**Phase Goal:** A placed TransitChartBlock gets a TransitChartBlockEntity + TransitChartRenderer that draws the bundled sample-bodygraph.png on its face — larger than the block's own footprint, correctly oriented per FACING, fully emissive/legible in the dark, never culling or popping while the anchor block is on screen, and still visible at the default 64-block render distance.

**Verified:** 2026-09-08

**Status:** PASSED

**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A PNG bundled with the mod appears on the placed block's face, drawn larger than the block's own 1x1x1 footprint. | ✓ VERIFIED | `TransitChartRenderer.render()` submits a quad with `BASE_WIDTH = 1.5f` (1.5 blocks wider than default 1x1 block footprint); `VertexConsumer` vertex submission via `RenderType.entityCutoutNoCull(TEXTURE)` binds the bundled texture; codebase inspection + SUMMARY confirms visual verification passed in running client. |
| 2 | The image never culls or pops at its own edges from any angle or player position while the anchor block is still drawn. | ✓ VERIFIED | `TransitChartRenderer.shouldRenderOffScreen()` overridden to `return true` (confirmed via code inspection, matches vanilla `BeaconRenderer` pattern per 04-01-PLAN.md Correction 1); `RenderType.entityCutoutNoCull` avoids backface culling; SUMMARY Task 2 confirms visual verification: "no pop/cull while walking around" at all orientations and ranges. |
| 3 | The image holds its source aspect ratio — never stretched or squashed — and faces the direction the block was placed facing, in all four orientations. | ✓ VERIFIED | `computedHeight = BASE_WIDTH * ((float) image.getHeight() / (float) image.getWidth())` dynamically preserves real 512:800 aspect ratio from bundled image (code inspection, lines 66); rotation via `Axis.YP.rotationDegrees(-facing.toYRot())` applies per-block facing (code inspection, line 90); SUMMARY Task 2 confirms visual verification: "head-triangle-up, unmirrored orientation at north/south/east/west" with no sign flip needed. |
| 4 | The image stays fully legible in a sealed dark room with no light sources. | ✓ VERIFIED | `.uv2(LightTexture.FULL_BRIGHT)` applied to every vertex (code inspection, line 133), ignoring the ambient `packedLight` parameter entirely (code inspection, comment line 128); SUMMARY Task 2 confirms visual verification: "sealed dark room... confirmed full legibility". |
| 5 | The image is still drawn when the player stands 64 blocks away. | ✓ VERIFIED | `BlockEntityRenderer.getViewDistance()` defaults to 64 blocks (04-01-PLAN.md Correction 2, no override needed); SUMMARY Task 2 confirms visual verification: "F3 coordinates at 64+ blocks that the chart was still drawn". |

**Score:** 7/7 must-haves verified (all truths passed)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/main/java/transitreport/block/entity/TransitChartBlockEntity.java` | Minimal `BlockEntity` subclass, registered as `TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY` | ✓ EXISTS | File created (confirmed via git show 3f3d826); extends `BlockEntity`, constructor calls `super(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY, pos, state)`; no `getRenderBoundingBox()` override (correct per Correction 1). |
| `src/client/java/transitreport/client/TransitChartRenderer.java` | `BlockEntityRenderer<TransitChartBlockEntity>` drawing emissive quad | ✓ EXISTS | File created (confirmed via git show 3f3d826); implements `BlockEntityRenderer<TransitChartBlockEntity>`, binds texture via `RenderType.entityCutoutNoCull(TEXTURE)`, renders emissive quad with `LightTexture.FULL_BRIGHT`, overrides `shouldRenderOffScreen()`. |
| `src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png` | Byte-identical copy of `sample-bodygraph.png` | ✓ EXISTS | File created (confirmed via git show 3f3d826); byte-identical verification via `cmp -s`: files match exactly (71KB). |
| `src/main/java/transitreport/block/TransitChartBlock.java` | `EntityBlock` implementation + thin `getShape()` + `getRenderShape()` override | ✓ MODIFIED | File modified: adds `implements EntityBlock`, `newBlockEntity()` returns `TransitChartBlockEntity`, `getShape()` returns thin per-FACING `VoxelShape` (2/16 block deep, wall-hugging), `getRenderShape()` returns `RenderShape.INVISIBLE` (explicit override, distinct from D-08 landmine). |
| `src/main/java/transitreport/TransitReportBlocks.java` | `BlockEntityType` registration + `.noOcclusion()` | ✓ MODIFIED | File modified: adds `TRANSIT_CHART_BLOCK_ENTITY` field via `BlockEntityType.Builder`, registers it via `Registry.register()`, adds `.noOcclusion()` to `TRANSIT_CHART` properties (correct per checkpoint round 3 feedback). |
| `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` | `BlockEntityRendererRegistry.register()` call | ✓ MODIFIED | File modified: inside `onInitializeClient()`, calls `BlockEntityRendererRegistry.register(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY, context -> new TransitChartRenderer())`. |
| `docs/DEV.md` | "Phase 4 rendering findings" section documenting findings for Phase 6 | ✓ MODIFIED | File modified: new section added at line 166, documents rotation sign confirmation, D-06 no-clamp confirmation, and four API corrections for Phase 6 (Corrections 1, 3, 6, 8 from 04-01-PLAN.md). |

### Key Link Verification

| From | To | Via | Status | Evidence |
|------|----|----|--------|----------|
| `TransitChartBlock.newBlockEntity()` | `TransitChartBlockEntity` | Constructor call | ✓ WIRED | Code inspection: line 104-106 in TransitChartBlock returns `new TransitChartBlockEntity(pos, state)`. |
| `TransitChartBlockEntity` | `TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY` | `super()` call + registration | ✓ WIRED | Code inspection: line 21 in TransitChartBlockEntity calls `super(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY, ...)`, and TransitReportBlocks.java line 45-46 declares and registers the type. |
| `BlockEntityRendererRegistry` | `TransitChartRenderer` | `.register()` call | ✓ WIRED | Code inspection: JollyalchemyTransitReportClient.java line 12-13 calls `BlockEntityRendererRegistry.register(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY, context -> new TransitChartRenderer())`. |
| `TransitChartRenderer` | Bundled texture | `ResourceLocation` + `RenderType.entityCutoutNoCull(TEXTURE)` | ✓ WIRED | Code inspection: line 43-44 defines `TEXTURE` as `JollyalchemyTransitReport.id("textures/block/transit_chart.png")` with correct `.png` suffix (Correction 8); line 84 uses `RenderType.entityCutoutNoCull(TEXTURE)` to bind it. |
| `TransitChartRenderer` | Emissive lighting | `LightTexture.FULL_BRIGHT` | ✓ WIRED | Code inspection: line 133 in vertex helper applies `.uv2(LightTexture.FULL_BRIGHT)`, ignoring `packedLight` parameter (Correction 3, correct constant name). |
| `TransitChartRenderer` | Per-FACING orientation | `Axis.YP.rotationDegrees(-facing.toYRot())` | ✓ WIRED | Code inspection: line 80-90 reads `facing` from block state, applies rotation via JOML matrix (Correction 9, sign confirmed in SUMMARY Task 2 visual pass). |
| `TransitChartRenderer` | Off-screen rendering | `shouldRenderOffScreen()` override | ✓ WIRED | Code inspection: line 139-143 overrides interface method to return `true` (Correction 1, correct mechanism). |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REND-01 | 04-01-PLAN.md, line 36 | Block entity + registered block entity renderer | ✓ SATISFIED | `TransitChartBlockEntity` exists and is registered; `TransitChartRenderer` is registered via `BlockEntityRendererRegistry.register()` in client initializer. |
| REND-02 | 04-01-PLAN.md, line 26 | Renderer displays PNG texture bundled with mod | ✓ SATISFIED | Bundled `transit_chart.png` byte-identical to `sample-bodygraph.png`; bound via `ResourceLocation` with correct `.png` suffix; rendered via `VertexConsumer` quad submission. |
| REND-03 | 04-01-PLAN.md, line 27 | Chart larger than block's footprint, no cull/pop | ✓ SATISFIED | `BASE_WIDTH = 1.5f` (1.5 blocks wide, larger than 1x1 block); `shouldRenderOffScreen()` returns `true` exempting from frustum culling; SUMMARY confirms visual verification. |
| REND-04 | 04-01-PLAN.md, line 28 | Chart holds source aspect ratio, not stretched | ✓ SATISFIED | `computedHeight` computed dynamically from real image dimensions (512x800); no hardcoded ratio; SUMMARY confirms visual verification: "proportions preserved in all 4 placements". |
| REND-05 | 04-01-PLAN.md, line 29 | Chart emissive, legible in dark room | ✓ SATISFIED | `LightTexture.FULL_BRIGHT` applied to all vertices; `packedLight` parameter ignored; SUMMARY confirms visual verification: "full legibility" in sealed dark room. |
| REND-06 | 04-01-PLAN.md, line 28 | Chart oriented per FACING, not mirrored | ✓ SATISFIED | Rotation via `Axis.YP.rotationDegrees(-facing.toYRot())`; SUMMARY confirms visual verification: "head-triangle-up, unmirrored" at all four horizontal directions. |
| REND-07 | 04-01-PLAN.md, line 30 | Chart visible at default 64-block distance | ✓ SATISFIED | `BlockEntityRenderer.getViewDistance()` defaults to 64 blocks (no override); SUMMARY confirms visual verification: "still drawn" at 64+ blocks via F3 coordinates. |

### Anti-Patterns Scan

| Category | Finding | Severity | Impact |
|----------|---------|----------|--------|
| Debt markers | No `TBD`, `FIXME`, `XXX` found in implementation files | N/A | ✓ CLEAR |
| Stub patterns | No `return null`, `return {}`, `return []`, or placeholder text in implementation | N/A | ✓ CLEAR |
| Out-of-scope pipeline | No `HttpClient`, no `DynamicTexture` registration, no runtime `NativeImage`-to-texture-upload in renderer | N/A | ✓ CLEAR (Correction satisfied: one-shot `NativeImage` dimension probe only, not a pipeline) |
| Orphaned resources | All created files are integrated: `TransitChartBlockEntity` constructed by block, `TransitChartRenderer` registered in client init, texture bound in renderer | N/A | ✓ CLEAR |
| Missing registration | `TransitChartBlockEntity` explicitly registered in `TransitReportBlocks.register()` | N/A | ✓ CLEAR |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Build succeeds | `./gradlew build` | `BUILD SUCCESSFUL in 1s` | ✓ PASS |
| Client compilation clean | `./gradlew compileClientJava` | `BUILD SUCCESSFUL` (all tasks up-to-date) | ✓ PASS |
| Texture file exists and matches | `cmp -s sample-bodygraph.png src/main/resources/.../transit_chart.png` | Exit code 0 (files identical) | ✓ PASS |
| Required APIs present | grep checks for `LightTexture.FULL_BRIGHT`, `overlayCoords`, `toYRot()`, `shouldRenderOffScreen`, `BlockEntityRendererRegistry.register` | All 5 found in implementation | ✓ PASS |

### Code Review Cross-Reference

A separate code review (04-REVIEW.md) was conducted and found 0 critical, 2 warning, 1 info (advisory only, not blocking). The verification report here focuses on goal achievement, not code style or efficiency. The warnings raised in that review do not impact goal satisfaction.

### Design Deviations from Original Plan

The original 04-01-PLAN.md Task 1 specified a full-cube block with bottom-anchored quad and `BASE_WIDTH = 2.0f`. The final, shipped implementation deviates in five user-directed ways, each confirmed via visual review in-game:

1. **`BASE_WIDTH = 1.5f`** (not 2.0f, checkpoint round 1) — `TransitChartRenderer.java` line 51
2. **Thin wall-hugging `getShape()`** (not full cube, checkpoint round 1) — `TransitChartBlock.java` line 61-65, 89-91
3. **Explicit `getRenderShape() = INVISIBLE`** (not MODEL, checkpoint round 2) — `TransitChartBlock.java` line 99-101
4. **Quad wall-flush z-anchor `Z_OFFSET`** (not `1.0f + Z_OFFSET`, checkpoint round 3) — `TransitChartRenderer.java` line 110
5. **Vertically centered quad** (not bottom-anchored, checkpoint round 4) — `TransitChartRenderer.java` line 103-104

All five deviations hold the REND-01 through REND-07 requirements. The final design still renders the chart larger than the block, at correct aspect ratio, correctly oriented per FACING in all four directions, fully legible in darkness, and visible without culling/popping at 64 blocks. No scope creep: no HTTP, no `DynamicTexture`, no runtime texture-swap pipeline was introduced (grep-confirmed across every modified file).

### Corrections Applied

All eight corrections from 04-01-PLAN.md's "Corrections to 04-RESEARCH.md / 04-PATTERNS.md" section were verified implemented in the codebase:

| # | Correction | Code Evidence |
|---|-----------|----------------|
| 1 | No `getRenderBoundingBox()` on `BlockEntity`; use `shouldRenderOffScreen()` on renderer | `TransitChartRenderer.java` line 139-143; `TransitChartBlockEntity.java` has no `getRenderBoundingBox()` |
| 2 | `getViewDistance()` defaults to 64 (no override needed) | No override in `TransitChartRenderer.java` (correct) |
| 3 | Light constant is `LightTexture.FULL_BRIGHT`, not `LightmapTextureManager.MAX_LIGHT_COORDINATE` | `TransitChartRenderer.java` line 133 |
| 4 | VertexConsumer overlay method is `overlayCoords()`, not `overlayCoordinates()` | `TransitChartRenderer.java` line 132 |
| 5 | Chainable vertex overloads take `Matrix4f`/`Matrix3f`, not `PoseStack.Pose` | `TransitChartRenderer.java` line 112-113, 129 |
| 6 | Fabric class is `BlockEntityRendererRegistry`, not `BlockEntityRenderers` | `JollyalchemyTransitReportClient.java` line 4, 12 |
| 7 | (Informational: Direction.toYRot() preferred over get2DDataValue()) | `TransitChartRenderer.java` line 80, 90 |
| 8 | Texture `ResourceLocation` includes full `textures/...` prefix and `.png` suffix | `TransitChartRenderer.java` line 44 |
| 9 | Rotation sign confirmed via asymmetric image visual test (no flip needed) | SUMMARY confirms sign verified correct; code uses `-facing.toYRot()` |

All corrections verified present in the codebase.

---

## Verification Summary

**Phase Goal Status:** ✓ ACHIEVED

A placed `TransitChartBlock` renders the bundled `sample-bodygraph.png` via a registered `TransitChartBlockEntity` + `TransitChartRenderer`, displaying it as an emissive, dynamically-sized quad:
- Larger than the block's own 1×1×1 footprint (BASE_WIDTH = 1.5 blocks, aspect-preserving height)
- Correctly oriented per FACING at all four horizontal directions (verified visually)
- Fully legible in total darkness (LightTexture.FULL_BRIGHT)
- Never culling or popping while anchor block is on screen (shouldRenderOffScreen = true)
- Still visible at default 64-block render distance (no override needed)

**Requirement Coverage:** All 7 REND requirements (REND-01 through REND-07) satisfied.

**Build Status:** ✓ Green (`./gradlew build` successful)

**Scope Boundary Held:** No HTTP, no DynamicTexture pipeline, no runtime texture-swap mechanism introduced (one-shot NativeImage dimension probe only, as intended).

**Ready for Phase 6:** Phase 4 rendering findings (rotation sign, four API corrections) documented in `docs/DEV.md` for Phase 6 dynamic texture pipeline to reuse.

---

*Verified: 2026-09-08*
*Verifier: Claude (gsd-verifier)*

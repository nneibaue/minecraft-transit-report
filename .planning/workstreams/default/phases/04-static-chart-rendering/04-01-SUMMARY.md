---
phase: 04-static-chart-rendering
plan: 01
subsystem: rendering
tags: [fabric, blockentityrenderer, voxelshape, minecraft-1.20.1, mojmap]

# Dependency graph
requires:
  - phase: 02-block-exists-and-places
    provides: TransitChartBlock (HorizontalDirectionalBlock with FACING), TransitReportBlocks registration holder
provides:
  - TransitChartBlockEntity + TransitChartRenderer, wired end to end to a placed TransitChartBlock
  - Bundled static chart texture (sample-bodygraph.png) under the mod's resource tree
  - Thin, wall-hugging block shape + invisible in-world render (RenderShape.INVISIBLE), replacing the Phase 2/3 full opaque cube for this block
  - Verified rotation/orientation math (Direction.toYRot()-based) and Mojmap API corrections for block-entity rendering, ready for Phase 6's dynamic texture pipeline to reuse
affects: [06-dynamic-texture-pipeline]

# Actuals (#2632)
actuals:
  tokens: 6800
  tasks: 2
  commits: 6

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "BlockEntityRenderer draws a floating textured quad bound directly via RenderType.entityCutoutNoCull(ResourceLocation), independent of the block's own model"
    - "Thin wall-mounted VoxelShape keyed by FACING, hugging the face opposite FACING, following vanilla WallBannerBlock's Map<Direction,VoxelShape> + Block.box(...) convention"
    - "RenderShape.INVISIBLE on a HorizontalDirectionalBlock (not BaseEntityBlock) to suppress a datagen'd model while keeping FACING/rotate/mirror plumbing, paired with an explicit noOcclusion() so neighbor face-culling doesn't leave a rendering hole"

key-files:
  created:
    - src/main/java/transitreport/block/entity/TransitChartBlockEntity.java
    - src/client/java/transitreport/client/TransitChartRenderer.java
    - src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png
  modified:
    - src/main/java/transitreport/block/TransitChartBlock.java
    - src/main/java/transitreport/TransitReportBlocks.java
    - src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
    - docs/DEV.md

key-decisions:
  - "BASE_WIDTH shrunk from the 04-CONTEXT.md D-05 locked 2.0f to 1.5f, aspect-preserving, per direct user visual review in-game"
  - "TransitChartBlock made a thin, wall-hugging shape (getShape()) instead of the default full 1x1x1 cube, matching vanilla WallBannerBlock's per-FACING VoxelShape pattern"
  - "TransitChartBlock.getRenderShape() explicitly overridden to RenderShape.INVISIBLE, suppressing the Phase 2/3 datagen'd cube model in-world so only the floating chart quad renders -- deliberate and distinct from 02-CONTEXT.md D-08's landmine"
  - "TransitReportBlocks.TRANSIT_CHART Properties gained .noOcclusion() so the now-thin, invisible block stops wrongly occluding its neighbor's shared face"
  - "Chart quad z-anchor moved from the far face (1.0f + Z_OFFSET) to the near/wall-side face (Z_OFFSET alone), matching where the block's thin hitbox and invisible model now sit"
  - "Chart quad vertically centered on the block's middle instead of D-08's locked bottom-anchoring, since the post-shrink computedHeight no longer risks a floor-clip at the centered position"

patterns-established:
  - "Corrections 1, 3, 6, 8 from 04-01-PLAN.md (no getRenderBoundingBox, LightTexture.FULL_BRIGHT, BlockEntityRendererRegistry, texture ResourceLocation .png suffix) verified against real compiled jars and carried into docs/DEV.md for Phase 6 reuse"
  - "BlockBehaviour's getShape(...) and getRenderShape(...) are themselves @Deprecated on this Minecraft version as Mojang's own override-marker convention, not evidence the API is going away -- confirmed via javap, matches vanilla's own WallBannerBlock"

requirements-completed: [REND-01, REND-02, REND-03, REND-04, REND-05, REND-06, REND-07]

coverage:
  - id: D1
    description: "TransitChartBlockEntity + TransitChartRenderer registered and wired to the placed TransitChartBlock (BlockEntityType, BlockEntityRendererRegistry)"
    requirement: "REND-01"
    verification:
      - kind: manual_procedural
        ref: "runClient session, checkpoint round 1-4 (this conversation) -- block places, entity/renderer construct without error, clean runClient boot log with no mixin/registration exceptions across 6 launches"
        status: pass
    human_judgment: true
    rationale: "Native Minecraft block-entity registration and renderer wiring has no automated test harness in this project (docs/DEV.md Testing section: OpenGL rendering output is verified visually, not asserted programmatically); confirmed via live runClient sessions and direct user visual review, but re-confirmation via UAT is appropriate given no pixel-diff/screenshot automation exists."
  - id: D2
    description: "Chart renders larger than the block's own footprint (BASE_WIDTH, final value 1.5 blocks wide, aspect-preserving height)"
    requirement: "REND-02"
    verification:
      - kind: manual_procedural
        ref: "checkpoint round 4 user confirmation: chart visibly larger than the 1x1x1 block footprint at the final 1.5-block anchor width"
        status: pass
    human_judgment: true
    rationale: "Visual size/scale judgment in a live 3D client; no automated screenshot comparison exists in this project."
  - id: D3
    description: "Chart never culls or pops at its own edges from any angle/distance while the anchor block is on screen (shouldRenderOffScreen override)"
    requirement: "REND-03"
    verification:
      - kind: manual_procedural
        ref: "Task 2 walkthrough (this conversation): user confirmed no pop/cull while walking around and backing away from placed blocks, including near a chunk-section boundary"
        status: pass
    human_judgment: true
    rationale: "Culling/popping behavior can only be observed by moving the camera in a live client; no automated harness for this exists in the project."
  - id: D4
    description: "Chart holds its source 512:800 aspect ratio at every orientation -- never stretched or squashed"
    requirement: "REND-04"
    verification:
      - kind: manual_procedural
        ref: "Task 2 four-orientation walkthrough (this conversation): user confirmed proportions preserved in all 4 placements at the final 1.5-block-wide size"
        status: pass
    human_judgment: true
    rationale: "Visual proportion judgment; no automated image-diff harness exists in this project."
  - id: D5
    description: "Chart stays fully legible in a sealed dark room with no light sources (LightTexture.FULL_BRIGHT)"
    requirement: "REND-05"
    verification:
      - kind: manual_procedural
        ref: "Task 2 dark-room walkthrough (this conversation): user built a sealed, light-source-free room around a placed block and confirmed full legibility"
        status: pass
    human_judgment: true
    rationale: "In-game lighting legibility can only be judged visually in a live client; no automated harness exists in this project."
  - id: D6
    description: "Chart is oriented per the block's FACING state, correctly (not mirrored) in all four horizontal directions (Correction 9 rotation sign)"
    requirement: "REND-06"
    verification:
      - kind: manual_procedural
        ref: "Task 2 four-orientation walkthrough (this conversation): user confirmed head-triangle-up, unmirrored orientation at north/south/east/west with -facing.toYRot(), no sign flip needed"
        status: pass
    human_judgment: true
    rationale: "Orientation/mirroring is a visual judgment against an asymmetric real chart image (D-02); no automated harness exists in this project."
  - id: D7
    description: "Chart is still drawn at the default 64-block block-entity render distance"
    requirement: "REND-07"
    verification:
      - kind: manual_procedural
        ref: "Task 2 walkthrough (this conversation): user confirmed via F3 coordinates at 64+ blocks that the chart was still drawn"
        status: pass
    human_judgment: true
    rationale: "Render-distance visibility can only be confirmed by standing at that distance in a live client; no automated harness exists in this project."

duration: 38min
completed: 2026-09-08
status: complete
---

# Phase 4 Plan 1: Static Chart Rendering Summary

**Placed TransitChartBlock renders the bundled sample-bodygraph.png via a BlockEntityRenderer as a thin, wall-flush, invisible-block "painting" -- vertically/horizontally centered, emissive, correctly oriented across all four facings, and never culling or popping within the default 64-block render distance.**

## Performance

- **Duration:** 38 min
- **Started:** 2026-09-08T22:05:57Z
- **Completed:** 2026-09-08T22:43:59Z
- **Tasks:** 2
- **Files modified:** 8 (3 created, 5 modified)

## Accomplishments

- `TransitChartBlockEntity` + `TransitChartRenderer` wired end to end to the existing `TransitChartBlock` (`EntityBlock`, `BlockEntityType` registration, `BlockEntityRendererRegistry` registration), rendering the bundled chart PNG as an emissive, dynamically-sized quad
- Bundled `sample-bodygraph.png` copied byte-for-byte into the mod's texture resource tree and bound directly via a Mojmap `ResourceLocation` with the required `.png` suffix
- Four rounds of checkpoint-driven visual refinement, each confirmed live in a running `runClient` session: shrunk quad size, thin wall-hugging block shape, invisible in-world block model, wall-flush quad anchoring, vertically-centered quad
- Full four-orientation + dark-room + 64-block verification pass completed by direct user observation in-game; findings recorded in `docs/DEV.md`
- Verified and documented four Mojmap API corrections (no `getRenderBoundingBox()`, `LightTexture.FULL_BRIGHT`, `BlockEntityRendererRegistry`, texture `ResourceLocation` `.png` suffix) plus a new finding (`getShape`/`getRenderShape` are themselves `@Deprecated` as Mojang's override-marker convention) for Phase 6 to reuse

## Task Commits

Each task was committed atomically, with four additional checkpoint-driven fix commits within Task 1's tracer scope:

1. **Task 1: Wire block entity + renderer end to end** - `3f3d826` (feat)
2. **Task 1 fix: Shrink chart quad + thin wall-mounted block shape** - `b5cee1a` (fix)
3. **Task 1 fix: Suppress the vanilla cube model (`getRenderShape` -> `INVISIBLE`)** - `faf8040` (fix)
4. **Task 1 fix: Flush-mount quad z-anchor + `noOcclusion()`** - `a73af79` (fix)
5. **Task 1 fix: Vertically center the quad instead of bottom-anchoring** - `51f05ca` (fix)
6. **Task 2: Record Phase 4 rendering findings in docs/DEV.md** - `f2b0f6b` (docs)

**Plan metadata:** committed separately after this SUMMARY (see final metadata commit)

## Files Created/Modified

- `src/main/java/transitreport/block/TransitChartBlock.java` - `implements EntityBlock`; adds `newBlockEntity`, a thin per-`FACING` `getShape()` (wall-hugging `VoxelShape`), and an explicit `getRenderShape() -> RenderShape.INVISIBLE`
- `src/main/java/transitreport/block/entity/TransitChartBlockEntity.java` - new; minimal `BlockEntity` subclass, registered as `TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY`
- `src/main/java/transitreport/TransitReportBlocks.java` - registers `TRANSIT_CHART_BLOCK_ENTITY`; adds `.noOcclusion()` to `TRANSIT_CHART`'s `Properties`
- `src/client/java/transitreport/client/TransitChartRenderer.java` - new; draws the bundled chart as an emissive quad (`RenderType.entityCutoutNoCull`), computes height dynamically from the real image dimensions, overrides `shouldRenderOffScreen`
- `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` - registers `TransitChartRenderer` via `BlockEntityRendererRegistry`
- `src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png` - new; byte-identical copy of `sample-bodygraph.png`
- `docs/DEV.md` - new "Phase 4 rendering findings" section: confirmed rotation sign, D-06 no-clamp confirmation, four API corrections for Phase 6, and a full summary of this round's design deviations

## Decisions Made

- All six design deviations below were explicit, user-directed decisions made after direct visual review of a running client, not autonomous choices — see Deviations from Plan.
- `getCollisionShape()` was deliberately **not** separately overridden on `TransitChartBlock`: confirmed via `javap` against `BlockBehaviour.class` that its default implementation already delegates to `getShape()` whenever the block has collision (true here, unmodified), so outline and collision stay consistent without duplicating the same box geometry in two places — matches vanilla `WallBannerBlock`'s own approach.
- `BlockEntityRendererRegistry` was kept despite being marked `@Deprecated` in the resolved `fabric-rendering-v1 3.0.10+54550fb677`: it's the API named explicitly in 04-01-PLAN.md's Correction 6 (verified present and functional on this project's classpath), it compiles and works correctly (confirmed via clean `runClient` sessions with the renderer registered and rendering), and no documented replacement was surfaced during this plan's scope. Recorded in `docs/DEV.md` so Phase 6 isn't surprised by the warning.

## Deviations from Plan

### User-directed design refinements (checkpoint rounds 1-4)

All five deviations below were requested by the user after direct visual review of the Task 1 tracer build running live in `gsd-dev`, confirmed correct through iterative in-game checkpoints (screenshots described precisely in each round's coordinator message). **These are refinements to a working implementation, not fixes to broken or defective behavior** — Task 1's original build already rendered the chart correctly (right orientation, right texture, no crash) on the very first pass; every round below is an aesthetic/UX adjustment the user asked for after seeing the actual in-world result.

**1. [User-directed, Rule 4-adjacent architectural change] Quad width shrunk from D-05's locked 2.0f to 1.5f**
- **Found during:** Checkpoint round 1 (post-Task-1 visual review)
- **Issue:** The 2.0-block-wide chart, as 04-CONTEXT.md D-05 specified, read as oversized once seen in-world
- **Fix:** `BASE_WIDTH` changed to `1.5f`; `computedHeight`'s aspect-preserving formula is unchanged, so height still shrinks proportionally — no distortion introduced
- **Files modified:** `TransitChartRenderer.java`
- **Committed in:** `b5cee1a`

**2. [User-directed, Rule 4 architectural change] Block given a thin, wall-hugging shape instead of the default full cube**
- **Found during:** Checkpoint round 1
- **Issue:** The block used the default `HorizontalDirectionalBlock` full 1x1x1 cube outline/collision, making it visibly protrude a full block's depth out from the wall behind the floating chart
- **Fix:** Added `TransitChartBlock.getShape(...)`, returning a per-`FACING` `VoxelShape` 2/16 of a block deep, hugging the face **opposite** `FACING`. Pattern and per-direction convention (thin slab on the opposite-of-FACING side) confirmed against vanilla `WallBannerBlock` via `javap` against this project's compiled `Block.class`. `getCollisionShape()` intentionally not separately overridden (see Decisions Made above)
- **Files modified:** `TransitChartBlock.java`
- **Committed in:** `b5cee1a`

**3. [User-directed, Rule 4 architectural change] Block's in-world render suppressed entirely (`RenderShape.INVISIBLE`)**
- **Found during:** Checkpoint round 2
- **Issue:** Even with the thin hitbox from round 1, the block was still a fully visible, stone-textured solid cube in the world — `getShape()`/`getCollisionShape()` only affect the collision/outline hitbox, not what block model actually renders. The default `getRenderShape() = RenderShape.MODEL` kept drawing the datagen'd Phase 2/3 cube model regardless
- **Fix:** `TransitChartBlock` now explicitly overrides `getRenderShape(BlockState)` to return `RenderShape.INVISIBLE` (confirmed via `javap` against `BlockBehaviour.class`/`RenderShape.class`). This is a second, distinct, explicit deviation from Task 1's original "do NOT add a `getRenderShape` override" instruction — that instruction guarded against 02-CONTEXT.md D-08's landmine (`BaseEntityBlock` *silently* defaulting to `INVISIBLE` as a side effect of a base-class switch). This override is intentional, added directly on the already-in-use `HorizontalDirectionalBlock` base, and is a completely different mechanism from the landmine it superficially resembles. Class javadoc updated to make the distinction explicit
- **Files modified:** `TransitChartBlock.java`
- **Committed in:** `faf8040`

**4. [User-directed bug fix + Rule 2-adjacent correctness fix] Quad re-anchored to the wall-flush face; neighbor face-culling hole fixed**
- **Found during:** Checkpoint round 3
- **Issue (a):** With the block now invisible and its thin hitbox on the near/wall-side face (opposite `FACING`), the rendered quad was still anchored to the far face (`1.0f + Z_OFFSET`) — the two ended up on opposite sides of the block, so the chart floated a full block out into the room instead of hanging flush against the wall. **Issue (b):** Breaking/replacing the block "fixed" a rendering hole in the wall block behind it, indicating the invisible block was still being treated as occluding for neighbor face-culling purposes
- **Fix (a):** Quad z-anchor changed from `1.0f + Z_OFFSET` to `Z_OFFSET` alone (measured from the near/wall-side face). Rotation logic untouched, already confirmed correct in round 1. **Fix (b):** Added `.noOcclusion()` to `TransitChartBlock`'s `Properties` in `TransitReportBlocks.java` (confirmed via `javap` against `BlockBehaviour$Properties.class`) — a stale holdover from Phase 2/3 when the block was a normal full opaque cube
- **Files modified:** `TransitChartRenderer.java`, `TransitReportBlocks.java`
- **Committed in:** `a73af79`

**5. [User-directed, Rule 4-adjacent architectural change] Quad vertically centered instead of bottom-anchored, deviating from D-08**
- **Found during:** Checkpoint round 4
- **Issue:** Even flush against the wall, the chart still read as floating too high relative to the block — D-08's bottom-anchoring arithmetic assumed the original `BASE_WIDTH = 2.0f` (~3.1 blocks tall), where centering would have clipped into the floor; after round 1 shrunk `BASE_WIDTH` to `1.5f`, `computedHeight` (~2.34 blocks) no longer risks a floor-clip at the centered position, and bottom-anchoring at this smaller size just read as "too high"
- **Fix:** `y0`/`y1` changed from bottom-anchored (`0.0f` / `computedHeight`) to vertically centered on the block's middle (`(1.0f - computedHeight) / 2.0f` / `y0 + computedHeight`), mirroring the horizontal centering already used for `x0`/`x1`
- **Files modified:** `TransitChartRenderer.java`
- **Committed in:** `51f05ca`

---

**Total deviations:** 5 user-directed design refinements, all Rule-4-adjacent architectural/behavioral changes explicitly requested and confirmed via checkpoint after direct in-game visual review (not autonomous decisions, not bug fixes to broken code).
**Impact on plan:** REND-01 through REND-07 all hold under the final, shipped design. The chart still appears larger than the block's footprint, at its real aspect ratio, oriented correctly per `FACING` in all four horizontal directions, fully legible in total darkness, and visible without popping/culling at the default 64-block render distance — the deviations changed *how* those requirements are satisfied (thin invisible block + floating quad, rather than visible cube + floating quad), not *whether* they are satisfied. No scope creep: no HTTP, no `DynamicTexture`, no runtime texture-swap pipeline was introduced (confirmed via grep across every file this plan touched).

## Issues Encountered

None beyond the deviations documented above. `./gradlew build` stayed green through every round of changes; every relaunched `runClient` session booted cleanly with no mixin/registration exceptions.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 6 (dynamic texture pipeline) can reuse: the `computedHeight`-from-real-pixel-dimensions pattern (D-05, unchanged in spirit despite the `BASE_WIDTH` value change), the four verified Mojmap API corrections, and the newly-found `getShape`/`getRenderShape` deprecation-but-correct pattern — all recorded in `docs/DEV.md`'s "Phase 4 rendering findings" section.
- Phase 6 should be aware the block's in-world identity has changed materially from what 04-CONTEXT.md originally locked in: `TransitChartBlock` is now an invisible, thin, wall-hugging block with a floating, vertically-centered, 1.5-block-wide quad — not a full visible cube with a bottom-anchored 2.0-block quad. Any Phase 6 code reasoning about the block's visual footprint should use the final shipped values, not the original plan text.
- No blockers for Phase 6. The bundled-texture rendering pipeline this phase built (renderer construction, quad geometry, emissive lighting, no-cull, per-`FACING` orientation) is the direct foundation Phase 6 will extend with runtime `NativeImage`-to-`DynamicTexture` swapping — none of that pipeline exists yet, as intended by this phase's domain boundary.

---
*Phase: 04-static-chart-rendering*
*Completed: 2026-09-08*

## Self-Check: PASSED

All 8 claimed files verified present on disk; all 6 claimed commit hashes verified present in `git log --oneline --all`.

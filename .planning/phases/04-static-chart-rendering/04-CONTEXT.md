# Phase 4: Static Chart Rendering - Context

**Gathered:** 2026-09-08
**Status:** Ready for planning

<domain>
## Phase Boundary

A placed block gets a `BlockEntity` + `BlockEntityRenderer` that draws a single bundled PNG on its face, sized and oriented correctly, larger than the block's own 1×1×1 footprint without culling or popping, unshaded/legible in total darkness, and still visible at the default 64-block render distance.

Covers REND-01 through REND-07.

**Explicitly not in this phase:** no HTTP, no dynamic texture pipeline (`NativeImage`/`DynamicTexture` decode-from-bytes), no runtime image swapping. The image is a single PNG bundled as an ordinary Minecraft resource-pack texture, loaded once. ROADMAP.md's own Notes for this phase state the reason directly: *"the point is to prove a textured quad can be drawn correctly before adding runtime texture complexity on top."*

</domain>

<decisions>
## Implementation Decisions

### Placeholder Chart Texture

- **D-01:** The bundled texture is a **real Human Design chart screenshot**, `sample-bodygraph.png` (project root, verified 512×800 PNG, RGB, no alpha channel), used **exactly as provided, unmodified** — no synthetic placeholder, no added marker or overlay.

- **D-02:** **No dedicated orientation marker is added.** The real chart already has strong natural asymmetry — a head-triangle shape pointing up, and differing gate numbers/connection colors left vs. right — which is relied on to catch upside-down or mirrored-texture bugs during the four-facing visual test (mirrors Phase 2's furnace-face asymmetry approach, 02-CONTEXT.md D-03/D-05).

- **D-03:** Chart aspect ratio is **portrait** (512 wide × 800 tall), confirmed empirically from the real file rather than assumed. This exactly matches the live Human Design API's own `width=512&height=800` query parameters (see D-04) — the bundled sample and the live endpoint produce the same shape.

### Live API — confirmed ready, deliberately not used this phase

- **D-04:** The live Human Design API endpoint is confirmed ready: `https://human-design-4u01.onrender.com/api/viz/transit?date=2026-09-08&time=06%3A06&width=512&height=800&transparent=false`. Per ROADMAP.md's Phase 4 Notes, **no HTTP call is made this phase** — Phase 4 stays fully static. This URL and its query shape (`date`, `time`, `width`, `height`, `transparent`) are recorded here so **Phase 5** (API client, CFG-01 base URL) doesn't have to rediscover them. `transparent=false` confirms the API returns opaque RGB PNGs — no alpha channel — matching `sample-bodygraph.png` exactly, which is useful confirmation for Phase 6/7's decode assumptions.

  — **Reversibility:** reversible — informational only; no code depends on this yet.

### Quad Size and Scaling

- **D-05:** The quad is **~2 blocks wide** (roughly double the block's own footprint), with **height computed dynamically from the bundled image's actual pixel dimensions** at texture-load time — width is the fixed anchor, height scales from the image's real aspect ratio (not a hardcoded ratio). For the current 512:800 image this works out to ≈2 × (800/512) ≈ 3.1 blocks tall.

  This is forward-looking on purpose: REND-04 requires the chart is never stretched/squashed, and Phase 6+ will stream arbitrary-sized PNGs from the live API (D-04) — computing from real image dimensions now avoids rebuilding this math later.

  — **Reversibility:** costly — Phase 6 will extend this exact "read dimensions, scale from a fixed anchor" code path for dynamically-fetched images; switching away from it later means touching the same site twice.

- **D-06:** **No sanity clamp/cap on quad size this phase** — deferred to Phase 6/7. Only the one known 512×800 bundled image ever renders here, so a clamp has nothing to guard against yet. Flagged for the Phase 6/7 planner to revisit once arbitrary live-API image sizes are involved.

### Floating Offset and Vertical Placement

- **D-07:** The quad floats a **small offset in front of the block's face** — on the order of a fraction of a block, just enough to avoid z-fighting against the block's own textured face. Not a large detached float.

- **D-08:** The quad is **bottom-anchored at the block's base**, not vertically centered on the block. Recorded with the arithmetic because it changed the answer: at ~2 blocks wide the chart computes to ~3.1 blocks tall (D-05); centering that height on the block's vertical midpoint (y=0.5) would put roughly 1 block of the chart **below the floor**. Bottom-anchoring at the block's base (y=0) means the chart rises entirely above ground from where the block sits — like a poster or sign standing on the ground — with nothing clipping into the floor.

### Claude's Discretion

None — all three discussed areas reached concrete decisions; no "you decide" selections were made.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope and requirements
- `.planning/PROJECT.md` — Constraints (Threading, Separation of concerns — the renderer never performs HTTP), Out of Scope ("Decorative modeling and visual polish ahead of the dynamic texture pipeline"), Intended component decomposition (`TransitDisplayRenderer`, superseded in naming by 02-CONTEXT.md D-02), Author background (new to Minecraft modding — explain Fabric/Minecraft mechanics).
- `.planning/REQUIREMENTS.md` — REND-01 through REND-07 (Rendering section). All seven map to this phase per the traceability table.
- `.planning/ROADMAP.md` — Phase 4 section: goal, 5 success criteria, and the Notes paragraph that is the direct source of this phase's no-HTTP/no-dynamic-texture boundary. Depends on Phase 2.

### Prior phase decisions
- `.planning/phases/02-block-exists-and-places/02-CONTEXT.md` — **D-02**: naming convention this phase must follow (`TransitChartBlockEntity`, `TransitChartRenderer`, matching the already-registered `TransitChartBlock`). **D-04**: facing convention — front faces the placing player (furnace/chest style); REND-06 orientation must match "the side you read from." **D-08 (critical landmine)**: `BaseEntityBlock` overrides `getRenderShape()` to `RenderShape.INVISIBLE` and does **not** extend `HorizontalDirectionalBlock`. This phase must add the block entity via the `EntityBlock` interface on the existing `TransitChartBlock` (which already extends `HorizontalDirectionalBlock`) — do **not** switch the base class to `BaseEntityBlock` without overriding `getRenderShape()` back to `MODEL`, or the block goes invisible and loses its inherited facing/rotate/mirror plumbing simultaneously. **D-10**: `noOcclusion()` was deliberately left unset in Phase 2 — "Phase 4's oversized quad may want it revisited; that is Phase 4's call, not a guess to make now."

### Project conventions — read before writing any Minecraft class name
- `.claude/CLAUDE.md` §2 — Mojang official vs. Yarn mappings table. Load-bearing entries for this phase: `BlockEntityRenderer<T>` / `BlockEntityRendererProvider<T>` (note: `Provider`, not Yarn's `Factory`), `RenderType` (never search Mojmap for "RenderLayer" meaning the pipeline type — that's an unrelated entity-overlay class, see the table's "danger" row), `PoseStack`, `MultiBufferSource`, `ResourceLocation`.
- `.claude/CLAUDE.md` §4 — Image decoding and texture types. Clarifies `NativeImage`/`DynamicTexture`/`TextureManager` for *runtime-decoded* textures (Phase 6 territory) — this phase's texture is a **bundled static resource-pack texture** referenced by `ResourceLocation`, loaded automatically by Minecraft's normal resource system, not manually decoded. Researcher should confirm the exact 1.20.1 API for binding a plain resource-pack texture inside a `BlockEntityRenderer` (likely `RenderType.entityCutout(ResourceLocation)`/`RenderType.text(ResourceLocation)`-family, not `NativeImage.read`).

### Existing source (read before modifying)
- `src/main/java/transitreport/block/TransitChartBlock.java` — current block class; extends `HorizontalDirectionalBlock`, stores `FACING`. This phase adds `EntityBlock` behavior here (see D-08 landmine above).
- `src/main/java/transitreport/TransitReportBlocks.java` — registration holder; needs a `BlockEntityType` registered alongside `TRANSIT_CHART`.
- `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` — currently an empty `onInitializeClient()`; this is where `BlockEntityRenderers.register(...)` goes.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `JollyalchemyTransitReport.MOD_ID` and the static `id(String path)` helper — use for the `BlockEntityType` registration id and the texture's `ResourceLocation`.
- `TransitReportBlocks.TRANSIT_CHART` — existing block instance; this phase's `TransitChartBlock` gains `EntityBlock` to produce a `TransitChartBlockEntity`.
- `sample-bodygraph.png` (project root) — the bundled placeholder chart texture; needs moving into the mod's asset tree under a standard Minecraft texture path (e.g. `src/main/resources/assets/jollyalchemy-transit-report/textures/...` — exact convention for a renderer-bound, non-block-model texture is a researcher/planner call).

### Established Patterns
- **Mojang official mappings**, not Yarn — `loom.officialMojangMappings()`. See CLAUDE.md §2.
- **Split source sets.** `src/main` is common (server+client), `src/client` is client-only. `BlockEntity` classes are common (`src/main`); `BlockEntityRenderer` registration is client-only (`src/client`) — same split Phase 2 used for the model provider vs. the block class.
- `HorizontalDirectionalBlock` already supplies `FACING`, `rotate`, and `mirror` (Phase 2 D-08) — this phase must not discard that by switching base classes carelessly.

### Integration Points
- `TransitChartBlock` — implement `EntityBlock`, add `newBlockEntity(BlockPos, BlockState)`.
- New: `TransitChartBlockEntity` (`src/main`, extends `BlockEntity`).
- New: `TransitChartRenderer` (`src/client`, implements `BlockEntityRenderer<TransitChartBlockEntity>`).
- New: `BlockEntityType<TransitChartBlockEntity>` registration in `TransitReportBlocks` (or an equivalent holder), invoked from `JollyalchemyTransitReport.onInitialize()`.
- `JollyalchemyTransitReportClient.onInitializeClient()` — gains `BlockEntityRenderers.register(TRANSIT_CHART_BLOCK_ENTITY, TransitChartRenderer::new)`.
- New texture resource under the mod's asset tree, containing `sample-bodygraph.png`'s bytes verbatim.

</code_context>

<specifics>
## Specific Ideas

- The user volunteered that **the live Human Design API is ready** (`https://human-design-4u01.onrender.com/api/viz/transit?...`) partway through discussing the placeholder image, and initially asked to use it directly instead of a static bundled texture. This was redirected per the scope guardrail — Phase 4 is deliberately static/no-HTTP per ROADMAP.md's own Notes — and the endpoint was captured for Phase 5 instead (D-04). This is genuinely useful project news: the external API dependency this whole project is built around is no longer purely hypothetical.
- `sample-bodygraph.png` is to be used **exactly as provided, unmodified** — no synthetic placeholder, no overlay marker (D-01, D-02).
- The user caught nothing wrong with "centered on the block" until the actual arithmetic (D-05's ~3.1-block height) was surfaced — worth noting that the vertical-anchor decision (D-08) came from Claude flagging a physical inconsistency the user hadn't run the numbers on, not from an initial preference.

</specifics>

<deferred>
## Deferred Ideas

- **Wiring the live API endpoint into the mod.** Belongs to Phase 5 (async HTTP client, CFG-01 base URL config) at the earliest, and Phase 6/7 (dynamic texture pipeline, decode) for actually rendering its response. URL and query-param shape captured in D-04 so it isn't re-discovered.
- **Quad size sanity clamp.** Deferred to Phase 6/7 once arbitrary live-API image sizes are actually possible (D-06).

### Reviewed Todos (not folded)
None — no pending todos matched this phase (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 4-Static Chart Rendering*
*Context gathered: 2026-09-08*

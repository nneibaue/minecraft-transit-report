# Research Summary: Human Design Transit Display

**Project:** Human Design Transit Display
**Domain:** Minecraft Fabric mod (1.20.1) — dynamic remote-image display on a block
**Researched:** 2026-09-07
**Confidence:** MEDIUM-HIGH

## Executive Summary

This is a presentation-layer mod for a single, craftable block that displays live Human Design transit charts fetched from an external API, refreshing once per minute and gracefully handling API outages. The research validates that the toolchain (Loom 1.17-SNAPSHOT + net.fabricmc.fabric-loom-remap + MC 1.20.1) is **working correctly as-is** and matches the current official Fabric example-mod template—no toolchain rework is needed.

The core risk is **version-specific API drift**: current Fabric documentation describes post-1.21 internals, while this project targets 1.20.1, creating a semantic trap where code that looks right fails to compile or behaves differently. The second core risk is **threading and resource-lifecycle correctness**: dynamic texture swapping must decode PNG bytes off the render thread, upload them on the render thread, and reuse a single texture object across refresh cycles to avoid unbounded GPU leaks.

The recommended approach is a client-side, fetch-per-client architecture with a single shared texture mutated on each refresh, strict thread-affinity boundaries enforced via MinecraftClient.execute(), and eight sequential build phases that separately validate rendering, HTTP, threading, and failure handling before combining them.

### Recommended Stack

The toolchain is **already correct**. Verification (not rework) is the only task: confirm runClient launches and runDatagen produces output. One residual item: fabricApi { configureDataGeneration { client = true } } is documented as 1.21.4+ addition—whether meaningful on 1.20.1 must be verified in Phase 1.

**Core technologies:**
### Expected Features

**Table stakes:** Directional wall-facing block state; oversized single-block rendering; aspect-ratio-correct chart; placeholder before first fetch; last-good-image persistence; right-click manual refresh; emissive/unshaded rendering; craftable recipe; config file; throttled logging; item tooltip.

**Differentiators (v1.x):** Actionbar feedback; author-only reload command; 6-direction placement; shift-right-click chart cycling.

### Architecture Approach

Split source sets enforce compile-time boundary. Single shared texture mutated on refresh. Strict thread boundaries: HTTP on worker thread, decode on background thread, upload on render thread only. Single MinecraftClient.execute() hop is the threading seam.

**Critical texture strategy (cross-validated):** One NativeImageBackedTexture, one fixed Identifier, mutated via setImage()/upload() on each refresh. This **largely dissolves the 'GPU leak every 60 seconds' concern**.

### Critical Pitfalls (Top 3)

**1. API Drift:** Current Fabric docs default to latest Minecraft. Block entity renderers, texture registration, render layers, datagen provider signatures all differ. **Prevention:** Run ./gradlew genSources; read decompiled 1.20.1 source.

**2. Threading Violations:** HttpClient.sendAsync() completes on worker thread. Calling NativeImage.read() and texture.upload() there is undefined behavior. **Prevention:** Decode on background thread, explicitly hop to client thread via MinecraftClient.getInstance().execute().

**3. Unbounded GPU Leak:** Allocating texture every 60 seconds forever without freeing. **Prevention:** Reuse one NativeImageBackedTexture registered once at fixed Identifier.

---

## Implications for Roadmap

Eight sequential phases plus one deferred. Key correction: async HTTP client (Phase 4) has zero dependencies on block/renderer and can build in parallel with Phase 3.

**Phase 1: Toolchain Verification** (1-2 days) — Deliverable: runClient launches; runDatagen produces output. Research needed: YES (empirical).

**Phase 2: Block Registration & Datagen** (2-3 days) — Deliverable: Craftable block, correct icon, survival drops. Research needed: YES (provider signatures).

**Phase 3: Static Texture Rendering** (2-3 days) — Deliverable: Block renders bundled PNG correctly. Research needed: NO (standard patterns).

**Phase 4: Async HTTP Client** (1-2 days, parallel to Phase 3) — Deliverable: Fetch from public URL, log response. Research needed: NO.

**Phase 5: Dynamic Texture Swapping (Local Images)** (2-3 days) — Deliverable: Texture reuse proven leak-free. Research needed: YES (lifecycle semantics).

**Phase 6: HTTP-to-Texture Wiring** (1-2 days) — Deliverable: Block renders fetched PNGs. Research needed: NO.

**Phase 7: Scheduled Refresh** (1-2 days) — Deliverable: Refreshes every ~60s, no overlaps. Research needed: NO.

**Phase 8: Reliability Hardening** (2-3 days) — Deliverable: Timeout/non-200/malformed handling with last-good persistence. Requires: Mock server. Research needed: NO.

**Phase 9: Manual Refresh** (0.5 days) — Deliverable: Right-click triggers fetch. Research needed: NO.

**Phase 10: Polish** (deferred) — Why: Presumes Phases 1-9 complete.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified via local build, jar inspection, official template |
| Features | MEDIUM-HIGH | Grounded in prior-art mods |
| Architecture | MEDIUM-HIGH | Verified against javadoc; MEDIUM where empirical test needed |
| Pitfalls | MEDIUM-HIGH | API drift verified; threading/leak patterns stable |

**Overall: MEDIUM-HIGH** — Stack verified. Architecture sound. Residual gaps are implementation-detail verifications (MEDIUM) resolving during Phases 1-3.

### Gaps to Address

- fabricApi { configureDataGeneration { client = true } } on 1.20.1: Phase 1 empirical verification.
- TextureManager.registerTexture() auto-close behavior: Phase 5 source/test verification.
- NativeImageBackedTexture ownership: Phase 5 empirical testing.
- Datagen provider constructor shapes: Individual javadoc verification.
- Whether TextureManager.registerTexture() throws vs. replaces: Phase 5 early verification.

---

## Sources

**Primary (HIGH):** Local ./gradlew build verification; jar inspection via javap; FabricMC/fabric-loom GitHub release notes; FabricMC/fabric-example-mod branch 1.20; Yarn 1.20.1 javadoc on maven.fabricmc.net; prior-art mods with public pages; PROJECT.md.

**Secondary (MEDIUM-HIGH):** Fabric Wiki tutorials; Fabric API javadoc; community knowledge on threading and lifecycle conventions.

**Tertiary (MEDIUM):** Version-drift inferences from cross-referenced API comparison; general software-engineering patterns with Minecraft manifestations.

---

*Research summary: Minecraft Fabric 1.20.1 dynamic remote-image display block*
*Researched: 2026-09-07*
*Confidence: MEDIUM-HIGH*
*Ready for roadmap planning: YES*

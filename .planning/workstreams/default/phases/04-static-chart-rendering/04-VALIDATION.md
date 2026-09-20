---
phase: "04"
slug: "static-chart-rendering"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: "2026-09-08"
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | JUnit 5 (Fabric Loader test set) — optional this phase |
| **Config file** | none — no test config exists yet |
| **Quick run command** | `./gradlew build` |
| **Full suite command** | `./gradlew build` (JUnit tests are optional/none this phase) |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./gradlew build` + manual visual check in `./gradlew runClient`
- **After every plan wave:** Run `./gradlew build`; full manual visual pass on all 7 REND requirements
- **Before `/gsd-verify-work`:** `./gradlew build` must be green; every visual requirement confirmed by eye
- **Max feedback latency:** 60 seconds (build) / a few minutes (manual client launch + visual pass)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | REND-01 | — | N/A | compile | `./gradlew build` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | REND-02 | — | N/A | visual (manual) | `./gradlew runClient` — place block, confirm bundled PNG appears, no purple/black checkerboard | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | REND-03 | — | N/A | visual (manual) | `./gradlew runClient` — rotate/back away, confirm quad never culls/pops while anchor block stays on screen | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | REND-04 | — | N/A | visual (manual) | `./gradlew runClient` — confirm image is never stretched/squashed (512:800 aspect held) | ❌ W0 | ⬜ pending |
| 04-01-05 | 01 | 1 | REND-05 | — | N/A | visual (manual) | `./gradlew runClient` — place in sealed dark room (no light sources), confirm chart stays fully legible | ❌ W0 | ⬜ pending |
| 04-01-06 | 01 | 1 | REND-06 | — | N/A | visual (manual) | `./gradlew runClient` — place facing all 4 directions, confirm chart orientation matches facing each time | ❌ W0 | ⬜ pending |
| 04-01-07 | 01 | 1 | REND-07 | — | N/A | visual (manual) | `./gradlew runClient` — back away to 64+ blocks, confirm chart still renders | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] No test framework install needed — `./gradlew build` (compile) is the only automated gate this phase; REND-02 through REND-07 are visual-only by nature (GPU rendering output, ambient light, distance culling) and have no practical automated assertion per RESEARCH.md.

*Existing infrastructure (Gradle build) covers the one automatable requirement (REND-01, via compile success). All other requirements are manual-only — see below.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PNG texture displays on block face | REND-02 | No practical automated assertion for "this pixel is the right color" / GPU render output | `./gradlew runClient`, place block, visually confirm bundled chart PNG appears (no missing-texture checkerboard) |
| Oversized quad never culls/pops at edges | REND-03 | Frustum culling behavior is a rendering/AABB interaction, not unit-testable | `./gradlew runClient`, walk around and back away from the block from multiple angles, confirm quad edges never pop in/out while the anchor block is visible |
| Chart holds source aspect ratio, correct facing | REND-04, REND-06 | Requires visual inspection of on-screen geometry across 4 placement orientations | `./gradlew runClient`, place the block facing N/S/E/W, confirm the image is never stretched/squashed and always faces the direction placed |
| Chart legible in total darkness | REND-05 | Ambient lighting interaction can only be confirmed by eye in-game | `./gradlew runClient`, build a sealed room with zero light sources, place the block inside, confirm the chart is still fully legible |
| Chart visible at 64-block render distance | REND-07 | Render-distance culling is a live client behavior | `./gradlew runClient`, place the block, walk backward to 64+ blocks, confirm the chart is still drawn |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s (build) / manual pass for visual checks
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

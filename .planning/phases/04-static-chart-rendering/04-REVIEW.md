---
phase: 04-static-chart-rendering
reviewed: 2026-09-08T23:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - src/main/java/transitreport/block/entity/TransitChartBlockEntity.java
  - src/client/java/transitreport/client/TransitChartRenderer.java
  - src/main/resources/assets/jollyalchemy-transit-report/textures/block/transit_chart.png
  - src/main/java/transitreport/block/TransitChartBlock.java
  - src/main/java/transitreport/TransitReportBlocks.java
  - src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-09-08T23:00:00Z
**Depth:** standard
**Files Reviewed:** 6 source files + 1 doc (docs/DEV.md, read for context, not separately findable for code defects) + 1 binary asset
**Status:** issues_found

## Summary

Reviewed the block/renderer wiring for the static chart-on-a-block feature, with particular focus
on the geometry left behind by four rounds of checkpoint-driven visual iteration (thin wall-hugging
`VoxelShape`, `INVISIBLE` render shape, `noOcclusion()`, and two changes to the rendered quad's
anchor point).

I independently re-derived the FACING-to-rotation-to-anchor pipeline by hand (all four horizontal
directions) and cross-checked the assumed `Direction.toYRot()` values against `javap` output of
this project's own compiled `Direction.class` (NORTH=180, SOUTH=0, WEST=90, EAST=270) rather than
trusting memory. Under that verification, `TransitChartRenderer`'s rotation/anchor math and
`TransitChartBlock.SHAPES`'s per-direction wall-hugging table are mutually consistent for all four
`FACING` values — the wall-side hitbox and the wall-flush chart quad land on the same physical face
in every orientation. I did not find a broken case here; the multiple rounds of live iteration did
not leave the core geometry wrong.

What the iteration *did* leave behind: a stale class-level Javadoc comment describing outdated
"bottom-anchored" behavior that the round-4 fix superseded, and an un-tested edge case in the
final vertical-centering choice (floor-level placement) that the code's own comment overstates as
resolved. Neither is a crash or security risk; both are geometry/documentation quality issues
worth fixing before this ships as the reference pattern Phase 6 is expected to copy.

## Warnings

### WR-01: Class-level Javadoc still says "bottom-anchored"; code centers vertically

**File:** `src/client/java/transitreport/client/TransitChartRenderer.java:28-31`

**Issue:** The class Javadoc reads:

```
 * Draws the bundled {@code sample-bodygraph.png} on the face of a placed
 * {@link TransitChartBlockEntity}, oversized relative to the block's own footprint, bottom
 * -anchored, oriented per the block's {@code FACING} state, and fully emissive (04-01-PLAN.md
 * Task 1; REND-01 through REND-07).
```

This directly contradicts the actual implementation a few lines below (`y0`/`y1`, lines 96-104),
which was changed in round 4 of the checkpoint iteration to vertically center the quad on the
block's middle — the in-line comment at line 96-102 correctly documents this and explicitly calls
out that it deviates from the locked "bottom-anchored" decision. The top-of-file Javadoc was never
updated to match. Since this file's own comments describe it as the pattern Phase 6 will "reuse
verbatim" for the live-API image pipeline, a stale summary at the top is exactly the kind of thing
a future implementer skims first and carries forward incorrectly.

**Fix:**
```java
/**
 * Draws the bundled {@code sample-bodygraph.png} on the face of a placed
 * {@link TransitChartBlockEntity}, oversized relative to the block's own footprint, vertically
 * centered on the block, oriented per the block's {@code FACING} state, and fully emissive
 * (04-01-PLAN.md Task 1; REND-01 through REND-07).
 */
```

### WR-02: Vertically-centered quad overflows ~0.67 blocks below the block's own footprint — floor-clip risk not actually eliminated

**File:** `src/client/java/transitreport/client/TransitChartRenderer.java:96-104`

**Issue:** The round-4 comment claims centering is safe because, after `BASE_WIDTH` shrank to
`1.5f`, `computedHeight` (~2.34 blocks, confirmed: `1.5 * 800/512 = 2.34375`) "no longer risks a
floor-clip at this size." Working the arithmetic: `y0 = (1.0f - 2.34375) / 2.0f ≈ -0.672`, i.e. the
quad's bottom edge sits **0.672 blocks below the block's own bottom face** (and 0.672 blocks above
its top face — the overflow didn't go away, it's just split evenly instead of concentrated at the
top). Centering only avoids a floor-clip if the block itself is not placed at or near floor level.
For a "wall-mounted display," placement directly above the floor (the single most common
wall-decoration placement — e.g. mounted at head height starting from the ground on a short wall)
will visibly clip the bottom ~0.67 blocks of the chart into whatever occupies the space below the
block. The same overstated claim is repeated in `docs/DEV.md` (lines ~248-250: "computedHeight ...
no longer risks a floor-clip at this size").

The four checkpoint rounds confirmed the look "at every orientation, distance, and lighting
condition tested" (per DEV.md's Phase 4 findings) but nothing in the SUMMARY/DEV.md record
describes testing a floor-adjacent placement specifically — the four checks described are the four
horizontal *facings*, not floor vs. mid-wall vs. ceiling *heights*.

**Fix:** Either verify (and if needed, correct the doc claim) that floor-level placement was
actually exercised, or reduce the risk directly — e.g. clamp `y0` to not go below `0.0f` (accepting
some visual imbalance, chart reads taller above the block than below) or re-introduce a
partial bottom-bias anchor rather than pure center:
```java
float y0 = Math.max(0.0f, (1.0f - computedHeight) / 2.0f);
float y1 = y0 + computedHeight;
```
At minimum, correct the comment/DEV.md claim so it doesn't assert an untested placement is safe.

## Info

### IN-01: Exception-path fallback (`DEFAULT_ASPECT`) is effectively untested and can silently drift from the real asset

**File:** `src/client/java/transitreport/client/TransitChartRenderer.java:56-73`

**Issue:** `DEFAULT_ASPECT = 800.0f / 512.0f` is a hand-maintained duplicate of the bundled PNG's
real dimensions (confirmed via `file`: the PNG is in fact 512x800 RGB, so the constant is currently
correct). It is only exercised when `NativeImage.read`/resource-open throws `IOException` — for a
bundled mod resource, this path essentially never executes in practice, so there is no automated or
manual check that would catch this constant drifting out of sync if the bundled texture is ever
swapped for a differently-proportioned image (which the Javadoc says will happen: this constructor
"is reused verbatim by Phase 6 for arbitrary live-API image sizes"). Not a bug today, but a latent
trap for whoever next replaces the asset.

**Fix:** Low priority given the phase's scope, but worth a one-line note for Phase 6: since Phase 6
introduces truly arbitrary, non-bundled image sizes, the entire premise of a fixed `DEFAULT_ASPECT`
fallback becomes wrong anyway (there is no single "correct" fallback ratio for an unknown live
image) — flag this constant for removal/replacement rather than reuse when Phase 6 picks this
pattern up.

---

_Reviewed: 2026-09-08T23:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

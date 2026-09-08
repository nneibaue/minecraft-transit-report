# Phase 4: Static Chart Rendering - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-08
**Phase:** 4-Static Chart Rendering
**Areas discussed:** Placeholder chart image, Quad size & aspect ratio, Floating offset & vertical placement

---

## Placeholder chart image

| Option | Description | Selected |
|--------|-------------|----------|
| Claude creates a synthetic placeholder | A simple generated image proves the pipeline without depending on real chart output | |
| I'll supply a real chart screenshot | User provides an actual Human Design chart PNG | ✓ |

**User's choice:** Supply a real chart screenshot.
**Notes:** User named the file `sample-bodygraph.png` and, in the same breath, volunteered that the live Human Design API endpoint is ready — see the separate live-API sub-thread below.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — add a clear orientation marker | Makes wrong-orientation bugs obvious | ✓ (initially) |
| No — content alone is enough | Rely on natural image asymmetry | |

**User's choice:** Initially "add a marker," but after Claude inspected the actual file and found it already has a head-triangle-up shape and asymmetric left/right gate numbers/colors, the user was asked again specifically about this real image and chose **no marker needed** (superseded — see below).

| Option | Description | Selected |
|--------|-------------|----------|
| Portrait (taller than wide) | Matches conventional bodygraph shape | ✓ |
| Square (1:1) | Simplest case | |
| Landscape (wider than tall) | Unusual for a bodygraph | |

**User's choice:** Portrait — confirmed empirically by the real file (512×800).

**Live API sub-thread:** User stated the live endpoint (`https://human-design-4u01.onrender.com/api/viz/transit?date=2026-09-08&time=06%3A06&width=512&height=800&transparent=false`) is ready and asked to use it instead of a static bundled texture. Claude explained ROADMAP.md's Phase 4 Notes deliberately exclude HTTP/dynamic texture this phase and proposed recording the URL for Phase 5 instead. User did not object and continued providing the static file path.

| Option | Description | Selected |
|--------|-------------|----------|
| It's in the project root | `sample-bodygraph.png` at repo root | ✓ |
| Somewhere else — I'll type the path | Free-text path | |

**User's choice:** Project root. Verified: 512×800 PNG, RGB, no alpha channel.

| Option | Description | Selected |
|--------|-------------|----------|
| Chart's natural asymmetry is enough | Use the file as-is, unmodified | ✓ |
| Still add an explicit marker | Overlay a directional label on a copy | |

**User's choice:** Chart's natural asymmetry is enough — this is the final, superseding answer to the earlier "add a marker" selection, asked again after Claude viewed the actual image.

---

## Quad size & aspect ratio

| Option | Description | Selected |
|--------|-------------|----------|
| ~2x block width, height from aspect ratio | Reads as a big "chart on the wall" | ✓ |
| ~1.5x block width (more modest) | Stays closer to normal block scale | |
| You decide | Claude picks during planning/research | |

**User's choice:** ~2x block width, height from aspect ratio.

| Option | Description | Selected |
|--------|-------------|----------|
| Computed dynamically from image dimensions | Avoids rework once Phase 6+ streams arbitrary sizes | ✓ |
| Fixed to the known 512:800 ratio | Hardcode for this phase's one image | |

**User's choice:** Computed dynamically from image dimensions.

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed width (~2 blocks), height scales | Width stays consistent block-to-block | ✓ |
| Fixed height, width scales | Height stays consistent | |

**User's choice:** Fixed width, height scales.

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Phase 6/7 | No variable input exists yet to clamp against | ✓ |
| Add a basic clamp now | Build a min/max clamp this phase | |

**User's choice:** Defer to Phase 6/7.

---

## Floating offset & vertical placement

| Option | Description | Selected |
|--------|-------------|----------|
| Small offset (~1-2 pixels / a fraction of a block) | Avoids z-fighting, still reads as mounted | ✓ |
| Flush with the block face (no offset) | Simplest math, risks z-fighting | |
| You decide | Claude picks during implementation | |

**User's choice:** Small offset.

| Option | Description | Selected |
|--------|-------------|----------|
| Centered on the block | Simplest anchor point | ✓ (initially) |
| Bottom-anchored, chart rises above the block | Sign/monitor mounted at the base | |

**User's choice:** Initially "centered on the block." Claude then surfaced the arithmetic: at ~2 blocks wide the chart computes to ~3.1 blocks tall, so centering on the block's vertical midpoint would bury roughly 1 block of the chart below the floor. Asked again with that math shown:

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom-anchor at the block's base instead | Matches the math — nothing clips into the floor | ✓ |
| Keep it centered — buried bottom is fine/intentional | Accept the partial burial | |
| Shrink the size instead so centering doesn't bury it | Revisit the ~2-block width | |

**User's choice:** Bottom-anchor at the block's base instead (supersedes the initial "centered" answer).

---

## Claude's Discretion

None — every discussed area reached a concrete, non-deferred decision.

## Deferred Ideas

- Wiring the live Human Design API endpoint (`https://human-design-4u01.onrender.com/api/viz/transit?...`) into the mod — belongs to Phase 5 (API client) and Phase 6/7 (dynamic texture pipeline). URL and query-param shape recorded in CONTEXT.md D-04.
- Quad size sanity clamp for unusual future image shapes/sizes — deferred to Phase 6/7 (CONTEXT.md D-06).

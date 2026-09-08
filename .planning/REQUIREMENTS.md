# Requirements: Human Design Transit Display

**Defined:** 2026-09-07
**Core Value:** A block placed in the world shows a current Human Design transit chart that keeps updating on its own, and never freezes or crashes Minecraft when the API misbehaves.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Toolchain

- [ ] **TOOL-01**: `./gradlew runClient` launches a working Minecraft 1.20.1 dev client with the mod loaded
- [ ] **TOOL-02**: `./gradlew runDatagen` completes and writes generated resources to `src/main/generated`
- [ ] **TOOL-03**: The `fabricApi { configureDataGeneration { client = true } }` block is confirmed either meaningful on 1.20.1 or corrected to bare `configureDataGeneration()`

### Block and Item

- [ ] **BLOCK-01**: Player can place the display block in the world
- [ ] **BLOCK-02**: The display block appears as an item in a creative inventory group
- [ ] **BLOCK-03**: The block stores a 4-way horizontal facing state, set from the direction the player faced when placing it
- [ ] **BLOCK-04**: Player can craft the display block from a single dirt block, shapeless, in the 2×2 inventory crafting grid — no crafting table required (deliberate testing recipe, see Crafting Recipe below)
- [ ] **BLOCK-05**: Breaking the block drops the block item back to the player
- [ ] **BLOCK-06**: The item shows a tooltip naming the block and stating that right-click refreshes it

### Data Generation

- [ ] **GEN-01**: Blockstate and block model JSON are produced by Fabric Data Generation, not hand-written
- [ ] **GEN-02**: Item model JSON is produced by data generation
- [ ] **GEN-03**: The active crafting recipe JSON (single dirt, shapeless) is produced by data generation
- [ ] **GEN-06**: The intended thematic recipe is retained as commented-out code in the recipe provider, adjacent to the active one, so swapping it in is uncommenting rather than rewriting
- [ ] **GEN-04**: The block loot table JSON is produced by data generation
- [ ] **GEN-05**: Translation strings (block name, tooltip, any messages) are produced by data generation

### Rendering

- [ ] **REND-01**: The block has a block entity with a registered `BlockEntityRenderer` that draws its face
- [ ] **REND-02**: The renderer displays a PNG texture bundled with the mod on the block's face
- [ ] **REND-03**: The rendered chart is larger than the block's own 1×1×1 footprint, with `getRenderBoundingBox()` overridden so the image does not cull or pop at its own edges while the anchor block is still on screen
- [ ] **REND-04**: The chart renders at a fixed aspect ratio and is never stretched or squashed
- [ ] **REND-05**: The chart renders emissive/unshaded and stays legible at any ambient light level, including a fully dark room
- [ ] **REND-06**: The rendered chart is oriented according to the block's facing state
- [ ] **REND-07**: The display remains visible out to the default 64-block block-entity render distance

### Texture Pipeline

- [ ] **TEX-01**: PNG bytes are decoded into a `NativeImage` off the render thread
- [ ] **TEX-02**: A single texture registered at one fixed `Identifier` is reused across refreshes, mutated via `setImage()` / `upload()` rather than registering a new `Identifier` per cycle
- [ ] **TEX-03**: Swapping the displayed image repeatedly over an extended run does not grow GPU texture allocation
- [ ] **TEX-04**: A bundled placeholder texture is displayed before the first successful fetch, so a freshly placed block never renders as a missing-texture checkerboard
- [ ] **TEX-05**: The displayed texture survives or is restored after a resource pack reload (F3+T)
- [ ] **TEX-06**: Texture upload occurs on the client/render thread, reached explicitly via `MinecraftClient.getInstance().execute(...)`

### API Client

- [ ] **API-01**: `TransitApiClient` fetches PNG bytes from the configured endpoint via an asynchronous HTTP GET
- [ ] **API-02**: Connect timeout and request timeout are both configured to finite values
- [ ] **API-03**: No HTTP call blocks the Minecraft main or render thread — the game stays responsive while a request is in flight
- [ ] **API-04**: Adding a second chart endpoint requires adding a method to the client, not restructuring the HTTP layer
- [ ] **API-05**: Response body size is capped so a hostile or broken endpoint cannot exhaust memory
- [ ] **API-06**: Response content type and image decodability are validated before the bytes reach the texture pipeline
- [ ] **API-07**: The renderer performs no HTTP, and the API client touches no rendering or texture state

### Refresh

- [ ] **REF-01**: The chart refreshes automatically on a configurable interval, defaulting to approximately 60 seconds
- [ ] **REF-02**: An initial fetch is requested when the display first becomes active, without waiting a full interval
- [ ] **REF-03**: No HTTP request is issued on a per-tick basis
- [ ] **REF-04**: A new request is not started while a previous request is still in flight
- [ ] **REF-05**: Right-clicking the block triggers an immediate refresh, reusing the same code path as the scheduler
- [ ] **REF-06**: A manual refresh shows brief actionbar feedback so the interaction does not feel inert during the in-flight gap

### Reliability

- [ ] **REL-01**: When a fetch fails, the last successfully displayed image remains on screen and is not replaced by a blank or error image
- [ ] **REL-02**: No API failure crashes, freezes, or stalls Minecraft
- [ ] **REL-03**: Repeated identical failures are logged with throttling or backoff, never once per tick, and never silently swallowed
- [ ] **REL-04**: Connection timeout, request timeout, non-success HTTP status, invalid image data, malformed response, unreachable API, and interrupted/cancelled requests are each handled explicitly
- [ ] **REL-05**: A failed refresh retries on the next scheduled interval rather than entering an unbounded retry loop
- [ ] **REL-06**: Pending requests and texture resources are cleaned up safely on world unload, disconnect, and client shutdown

### Configuration

- [ ] **CFG-01**: API base URL is read from a configuration file, not hardcoded
- [ ] **CFG-02**: Refresh interval is read from configuration, not a magic number in code
- [ ] **CFG-03**: A malformed or missing config file produces a usable default and a clear log line rather than a crash during initialization
- [ ] **CFG-04**: An author-only client command can reload configuration and set the base URL at runtime, without editing a file and restarting
- [ ] **CFG-05**: No API secrets or credentials are present in the mod or its configuration defaults

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Display Form

- **PROJ-01**: Projector form factor — chart projected into the air away from the anchor block rather than rendered on its face
- **PROJ-02**: Raycast targeting so the projection lands on the first solid block in its path
- **PROJ-03**: Redstone or right-click toggle for the projection
- **PROJ-04**: Visible beam or throw cue so the effect reads as a projection rather than a floating rectangle
- **PROJ-05**: Render distance handling for a projection offset from its anchor, since `getRenderDistance()` measures from the block's position and not the image's

### Placement and Interaction

- **PLACE-01**: 6-direction placement including ceiling and floor mounting
- **PLACE-02**: Shift-right-click cycling between chart types, once a second endpoint exists

### Verification Infrastructure

- **MOCK-01**: In-repo local mock HTTP server, built on the JDK's `com.sun.net.httpserver`, serving PNGs on a configurable port
- **MOCK-02**: Mock server can deliberately produce timeouts, non-200 statuses, truncated bodies, and malformed image bytes on demand
- **MOCK-03**: Every REL-04 failure mode is exercised against the mock server and observed to behave as specified

### Presentation

- **VIS-01**: Visible staleness indicator when the last good image exceeds a threshold age
- **VIS-02**: Decorative block model and visual polish
- **VIS-03**: Per-minute request timestamp alignment across clients, to remove visible refresh skew between two players at the same block

### Multiplayer

- **MP-01**: Server-authoritative transit data with client synchronization, replacing per-client fetching

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Human Design calculation in the mod | The external API is the source of truth; duplicating the math in Minecraft is the single biggest architectural mistake available here |
| Natal / birth data input and storage | The transit endpoint is parametrized by timestamp only — no personal data needed, which is what removes the config GUI and per-instance state |
| Player-supplied arbitrary URLs | The feature public-server admins cite as the reason comparable mods need whitelists and permission gating. Turns a single-purpose display into an open image proxy driven by untrusted input, for no purpose this project has |
| In-block configuration GUI | Nothing is per-block or per-player to configure. A GUI here solves a problem this project does not have |
| Mod Menu + Cloth Config integration | Two extra mod dependencies for a two-value, author-set config on a private server. Contradicts the project's dependency conservatism |
| Disk caching of fetched images | Conflicts with images-as-transient-state; adds I/O, invalidation, and disk management for bytes worthless within a minute |
| Storing PNG bytes in block entity NBT or world save | Bloats save files and chunk data for content with roughly a one-minute shelf life |
| Multi-block display structure | The oversized single-block quad achieves the same visual outcome without placement, state, and validation complexity |
| Animated GIF or video playback | The API contract is one static PNG per request; frame sequencing and codecs are wildly disproportionate to redrawing an image once a minute |
| Sound | No use case for a static chart |
| Full in-game browser (MCEF/WebDisplays pattern) | Embedding a Chromium runtime to render one PNG endpoint is the worst effort-to-value ratio surveyed, and reintroduces arbitrary URLs in their most extreme form |
| Loading spinner on periodic refreshes | A display that visibly flickers every 60 seconds reads as unstable. Placeholder before first fetch only; subsequent refreshes swap silently |
| Per-player personalized charts | Would simultaneously undo three load-bearing simplifications — no server authority, no sync protocol, no config GUI |
| Public release to Modrinth/CurseForge | Private use by the author and a few friends |
| Third-party HTTP or config libraries | `java.net.http.HttpClient` and Gson are already available; a dependency needs explicit justification |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| (Pending roadmap creation) | — | Pending |

**Coverage:**
- v1 requirements: 48 total
- Mapped to phases: 0
- Unmapped: 48 ⚠️

## Crafting Recipe

**Active recipe (v1): one dirt block.** Shapeless, single ingredient, so it fits the 2×2 inventory grid and needs no crafting table. This exists purely so that testing the display does not require gathering materials on every iteration — it is a development convenience, not a design statement, and it is expected to be replaced.

**Intended recipe, kept commented out** (GEN-06). Shaped, 3×3:

```
A E A     A = Amethyst Shard  ×4
E C E     E = Echo Shard      ×3
A G A     C = Clock           ×1
          G = Glow Ink Sac    ×1
```

Rationale, so the intent survives even if the recipe is later changed:

- **Clock at center** — the transit endpoint is parametrized by timestamp and nothing else. Time is the literal input to the chart, so it sits at the heart of the recipe.
- **Echo Shard** — Ancient City loot; fragments of something distant arriving where the player is, which is what a transit is. Also makes the block satisfyingly hard to obtain, suiting a divination instrument rather than a decoration.
- **Amethyst Shard** — crystalline geometry, and the one material in the game that audibly resonates.
- **Glow Ink Sac** — ties the recipe to REND-05's emissive, self-lit face.
- **Nine slots** — matches the nine centers of a Human Design bodygraph. Incidental, but the kind of detail worth keeping.

All four ingredients exist in Minecraft 1.20.1 (Amethyst Shard and Glow Ink Sac since 1.17, Echo Shard since 1.19).

## Verification Notes

**REL-04 verification is deferred by decision.** The local mock server was scoped out of v1 (see MOCK-01 through MOCK-03). Timeouts, non-200 statuses, truncated bodies, and malformed PNGs cannot be provoked on demand against a public image endpoint, so the handling required by REL-04 will be implemented and code-reviewed but not empirically exercised during v1. This is a known, accepted gap, recorded here so the reliability phase is not mistaken for fully verified. It closes when either the mock server is added or the real API exists and can be made to misbehave.

---
*Requirements defined: 2026-09-07*
*Last updated: 2026-09-07 after initial definition*

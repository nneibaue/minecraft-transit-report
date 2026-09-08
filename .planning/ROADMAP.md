# Roadmap: Human Design Transit Display

## Overview

The journey runs from an unmodified Fabric template to a block that hangs on a wall and quietly keeps a live Human Design transit chart current. It follows the owner's own priority chain — block exists, block can be placed, block can be rendered, chart image appears on it, chart updates — with one correction from architecture research: the async HTTP client depends on none of the block, renderer, or texture work, so it is its own parallel track branching off the toolchain check rather than waiting in line behind rendering. The two tracks join at Phase 7, which is the first moment a downloaded image lands on a placed block. Everything before that point is deliberately isolated so that when the join fails, the fault is in the hand-back between two independently-proven halves, not in either half alone. Everything after it is cadence, failure behavior, and the controls that make the thing usable without restarting the game.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

**Parallel track:** Phase 5 depends only on Phase 1 and can be built alongside Phases 2-4. See Execution Order below.

- [ ] **Phase 1: Toolchain Verification** - Confirm the dev client launches and datagen writes output; settle the `client = true` question
- [ ] **Phase 2: Block Exists and Places** - A display block obtainable in creative, placeable, storing 4-way facing, with generated models
- [ ] **Phase 3: Craft, Break, and Identify** - Shapeless dirt recipe, self-drop loot table, translated name and tooltip
- [ ] **Phase 4: Static Chart Rendering** - Block entity renderer draws an oversized, self-lit, correctly-oriented bundled image
- [ ] **Phase 5: Configuration and Async Fetch** - Config-driven base URL and interval; PNG bytes fetched off-thread and logged (parallel to 2-4)
- [ ] **Phase 6: Dynamic Texture Pipeline** - Arbitrary PNG bytes become a live, swappable, non-leaking texture on the block
- [ ] **Phase 7: Fetched Chart on the Block** - The two tracks join: a downloaded chart appears on a placed block
- [ ] **Phase 8: Scheduled Refresh** - The chart keeps itself current on a configurable cadence with no overlap or per-tick spam
- [ ] **Phase 9: Reliability Hardening** - API misbehavior degrades gracefully instead of blanking, spamming, or stalling
- [ ] **Phase 10: Manual Refresh and Runtime Control** - Right-click to refresh with actionbar feedback; client command to repoint the API live

## Phase Details

### Phase 1: Toolchain Verification
**Goal**: The development loop is proven end to end — the game launches with the mod loaded, and data generation writes files to disk
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: TOOL-01, TOOL-02, TOOL-03
**Success Criteria** (what must be TRUE):
  1. `./gradlew runClient` opens a Minecraft 1.20.1 window and the mod is listed among the loaded mods
  2. `./gradlew runDatagen` exits successfully and generated resource files are present under `src/main/generated`
  3. The `fabricApi { configureDataGeneration { client = true } }` question is settled by observation — either confirmed to do something meaningful on 1.20.1 or replaced with the bare `configureDataGeneration()` call, with the finding recorded
**Plans**: TBD

**Scope note**: This is a sanity check, not a rework phase. `./gradlew build` was already run against this repo and succeeded (exit 0, JDK 26), and the Loom 1.17 / `net.fabricmc.fabric-loom-remap` / MC 1.20.1 pairing was investigated and proved correct for obfuscated Minecraft versions. Do not budget Loom surgery. If the client launches and datagen writes files, this phase is done.

### Phase 2: Block Exists and Places
**Goal**: A display block exists in the game, can be taken from the creative inventory, and places itself facing the player
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: BLOCK-01, BLOCK-02, BLOCK-03, GEN-01, GEN-02
**Success Criteria** (what must be TRUE):
  1. Player finds the display block in a creative inventory group and places it in the world
  2. The placed block orients to whichever of the four horizontal directions the player was facing when placing it, observably different in all four cases
  3. The placed block draws a real model rather than the purple-and-black missing-model checkerboard, and the item draws a real icon in the hotbar
  4. Blockstate, block model, and item model JSON exist under `src/main/generated`, with no hand-written equivalent under `src/main/resources`
**Plans**: TBD

**Notes**: The 4-way horizontal facing state (BLOCK-03) is a hard prerequisite for Phase 4 — the renderer cannot orient its quad without it. This is why it lands here rather than with the rendering work. `BlockEntityType` registration may be introduced here as plumbing, but nothing renders from it until Phase 4.

### Phase 3: Craft, Break, and Identify
**Goal**: The block completes the survival loop — craftable, breakable back into itself, and named in the player's own language
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: BLOCK-04, BLOCK-05, BLOCK-06, GEN-03, GEN-04, GEN-05, GEN-06
**Success Criteria** (what must be TRUE):
  1. Player crafts the display block from a single dirt block in the 2x2 inventory crafting grid, with no crafting table required
  2. Breaking a placed block returns the block item to the player in survival mode
  3. Hovering the item shows a translated block name and a tooltip line stating that right-click refreshes it — no raw translation keys appear anywhere
  4. The intended thematic 3x3 recipe (Amethyst Shard x4, Echo Shard x3, Clock, Glow Ink Sac) sits commented out directly beside the active recipe, so swapping it in is uncommenting rather than rewriting
  5. Recipe, loot table, and language JSON are all data generation output, not hand-written files
**Plans**: TBD

**Notes**: The single-dirt shapeless recipe is a deliberate testing convenience so iteration never requires gathering materials — see the Crafting Recipe section of REQUIREMENTS.md. The exact 1.20.1 `FabricRecipeProvider` generation method shape was flagged MEDIUM confidence in research; verify it against `./gradlew genSources` output or `javap` against the cached jar rather than against current Fabric documentation, which describes post-1.21 provider signatures. This phase is independent of Phase 4 and the two could be built in either order.

### Phase 4: Static Chart Rendering
**Goal**: A placed block draws a large, correctly-oriented, self-lit image on its face, sourced from a texture bundled with the mod
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: REND-01, REND-02, REND-03, REND-04, REND-05, REND-06, REND-07
**Success Criteria** (what must be TRUE):
  1. A PNG bundled with the mod appears on the placed block's face, drawn larger than the block's own 1x1x1 footprint
  2. The image never culls or pops at its own edges from any angle or player position while the anchor block is still drawn
  3. The image holds its source aspect ratio — never stretched or squashed — and faces the direction the block was placed facing, in all four orientations
  4. The image stays fully legible in a sealed dark room with no light sources
  5. The image is still drawn when the player stands 64 blocks away
**Plans**: TBD

**Notes**: The oversized quad and the `getRenderBoundingBox()` override (both REND-03) belong together and must not be split across phases — a phase that ships the oversized quad without the bounding box produces a deliverable that visibly culls and pops at its own edges, which reads as broken. REND-07's 64-block distance is the same concern measured from further away. No dynamic texture, no HTTP, and no network code enters this phase; the point is to prove a textured quad can be drawn correctly before adding runtime texture complexity on top.

### Phase 5: Configuration and Async Fetch
**Goal**: The mod reads its base URL and refresh interval from a config file and fetches PNG bytes from that URL asynchronously, without ever blocking the game
**Mode:** mvp
**Depends on**: Phase 1 only — genuinely independent of Phases 2, 3, and 4, and buildable in parallel with them
**Requirements**: CFG-01, CFG-02, CFG-03, CFG-05, API-01, API-02, API-03, API-04, API-05
**Success Criteria** (what must be TRUE):
  1. A config file is written with defaults on first run; editing the base URL in it changes where the next fetch goes, and editing the interval value is picked up without a code change
  2. A deleted or malformed config file yields usable defaults plus one clear log line, and the game still initializes rather than crashing
  3. Triggering a fetch against the public changing-image URL logs an HTTP status and a byte count, and the game stays responsive with no frame hitch while the request is in flight
  4. A fetch against an unreachable host gives up within the configured connect and request timeouts instead of hanging, and an oversized response body is cut off at the configured cap rather than growing without bound
  5. Shipped config defaults contain no API secret or credential, and all requests are built through one shared path such that a second chart endpoint would be a single added method — confirmable by inspection
**Plans**: TBD

**Notes**: This is the parallel track. `TransitApiClient` has zero dependencies on the block, the renderer, or the texture pipeline, and building it alongside Phases 2-4 de-risks Phase 7 by ensuring both halves of that join are independently proven first. Nothing here touches `TextureManager`, `NativeImage`, or any GL call — this phase logs bytes and stops. `TransitConfig` stays free of client-only imports so it can live in `src/main`. Verification uses the public changing-image dummy endpoint; the real Human Design API does not exist yet.

### Phase 6: Dynamic Texture Pipeline
**Goal**: Arbitrary PNG bytes become a live texture on the block that can be swapped repeatedly at runtime without growing GPU allocation
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: TEX-01, TEX-02, TEX-03, TEX-04, TEX-05, TEX-06
**Success Criteria** (what must be TRUE):
  1. A freshly placed block draws a bundled placeholder image immediately, never a missing-texture checkerboard, before anything has been swapped in
  2. Triggering a swap from a local PNG — no network involved — visibly replaces the image on every placed block at once
  3. Swapping dozens of times in one session leaves GPU texture count and memory flat, with exactly one `Identifier` registered for the life of the session
  4. The displayed image survives an F3+T resource reload, or is visibly restored immediately after one
  5. PNG decode happens off the client thread and upload happens inside a `MinecraftClient.getInstance().execute(...)` hop, with no GL call reachable from a background thread
**Plans**: TBD

**Notes**: Still no HTTP in this phase — swaps are triggered by a keypress or debug command against a local image, which isolates the threading and lifecycle model from the network entirely. Two research findings were explicitly marked MEDIUM confidence and must be verified here as real work, not assumed: whether `TextureManager.registerTexture` at an existing `Identifier` auto-closes the previous texture, and whether `NativeImageBackedTexture.close()` closes the `NativeImage` it owns. Verify against `./gradlew genSources` output or `javap`, not against documentation. TEX-05's resource-reload survival was also inferred rather than documented for 1.20.1 — test it, and add a reload listener only if the test says one is needed.

### Phase 7: Fetched Chart on the Block
**Goal**: The image on the block comes from the API — the first join of the fetch path and the texture path
**Mode:** mvp
**Depends on**: Phase 5 and Phase 6
**Requirements**: API-06, API-07, REF-02
**Success Criteria** (what must be TRUE):
  1. Placing a block, or entering a world where one is already placed, triggers a single fetch and the downloaded image appears on the block's face without waiting out any interval
  2. A response that is not a decodable image is rejected before its bytes reach the texture pipeline, and the placeholder or previously displayed image stays put
  3. The renderer contains no HTTP call and the API client contains no texture or GL call — their only contact is one narrow hand-back entry point that takes bytes or a decoded image
**Plans**: TBD

**Notes**: This is the milestone's highest-value moment and the owner's "chart image appears on it" step. Because Phases 5 and 6 were each verified alone, a failure here localizes almost certainly to the thread hand-back rather than to either half. The hand-back entry point should be shaped so a future server-broadcast producer could call the same method without the texture manager or renderer changing — that costs nothing now and is the one multiplayer seam worth naming.

### Phase 8: Scheduled Refresh
**Goal**: The chart keeps itself current on its own, on a configurable cadence, without hammering the endpoint
**Mode:** mvp
**Depends on**: Phase 7
**Requirements**: REF-01, REF-03, REF-04
**Success Criteria** (what must be TRUE):
  1. Standing and watching a placed block, the image visibly changes roughly once a minute against the public changing-image endpoint, with no player action at all
  2. Setting the interval in config to a few seconds visibly speeds the cadence up, and setting it long visibly slows it down, without a code change
  3. Logs show one request per configured interval rather than one per tick, and a slow request never has a second request started on top of it
**Plans**: TBD

**Notes**: This is the owner's "chart updates" step and the point at which the core value is first fully demonstrable. The scheduler is a client singleton driving one shared texture — it must not iterate placed block entities and fetch once per placed block, which would silently multiply identical requests. The public changing-image endpoint is what makes this phase visually verifiable: each request returns a different picture, so cadence is observable rather than inferred.

### Phase 9: Reliability Hardening
**Goal**: API misbehavior degrades the display gracefully instead of blanking it, spamming the log, or stalling the game
**Mode:** mvp
**Depends on**: Phase 8
**Requirements**: REL-01, REL-02, REL-03, REL-04, REL-05, REL-06
**Success Criteria** (what must be TRUE):
  1. Pointing the base URL at a nonexistent host leaves the last successfully displayed chart in place — not a blank, not an error image — while the game stays fully responsive
  2. A repeatedly failing endpoint produces throttled or backed-off log output, never one line per tick and never silent swallowing
  3. After a failed refresh, the next scheduled interval retries on its own with no restart and no unbounded retry loop, and pointing the URL back at a working endpoint restores the chart on the following interval
  4. Leaving a world, disconnecting, and quitting the game each complete cleanly with no pending request or texture resource left behind and no error on the way out
  5. Every REL-04 failure mode — connect timeout, request timeout, non-success status, undecodable image bytes, truncated body, unreachable host, interrupted or cancelled request — has an explicit, individually identifiable handler that preserves the last good image and logs once. **This criterion is satisfied by code review and inspection, not by empirical observation.**
**Plans**: TBD

**Known verification gap**: Criterion 5 cannot be empirically exercised during v1, and must not be reported as if it were. The local mock HTTP server that would provoke timeouts, 500s, truncated bodies, and malformed PNGs on demand was deliberately scoped out to v2 (MOCK-01 through MOCK-03), and a public image endpoint cannot be made to misbehave to order. Criteria 1-4 are genuinely testable — an unreachable host, a bad URL, and a clean quit are all easy to produce. Criterion 5 is reviewable only. See the Verification Notes section of REQUIREMENTS.md. The gap closes when the mock server is built or the real API exists and can be made to fail on request.

### Phase 10: Manual Refresh and Runtime Control
**Goal**: The owner can force a refresh and repoint the mod at a different API without leaving the game
**Mode:** mvp
**Depends on**: Phase 9
**Requirements**: REF-05, REF-06, CFG-04
**Success Criteria** (what must be TRUE):
  1. Right-clicking a placed block fetches immediately and the chart updates, without waiting for the next scheduled interval
  2. The manual refresh shows brief actionbar feedback so the click never feels inert during the in-flight gap, and says so honestly when the fetch fails rather than silently doing nothing
  3. An author-only client command reloads configuration and sets a new base URL at runtime, and the very next refresh uses it — no file edit and no restart
  4. The manual path runs through the same fetch code as the scheduler and inherits its failure handling for free — a right-click during an in-flight request does not start a second one
**Plans**: TBD

**Notes**: This is a small phase by design, not a standalone subsystem. Manual refresh is a hook onto plumbing the scheduler already built in Phase 8; it is sized as a tail, not as new work. It lands after Phase 9 specifically so the manual path inherits the reliability handling rather than needing its own. CFG-04's command shares this phase because it solves the same problem from the other side: changing what the block shows without restarting the game, which matters most while the real API is still being built and its URL is still moving.

## Progress

**Execution Order:**

Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10

With parallelization enabled, two independent tracks exist after Phase 1:
- **Track A (display):** 2 → 3 → 4 → 6
- **Track B (data):** 5
- Tracks join at Phase 7, then run sequentially: 7 → 8 → 9 → 10

Phase 3 and Phase 4 are also independent of each other; both need only Phase 2.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Toolchain Verification | 0/TBD | Not started | - |
| 2. Block Exists and Places | 0/TBD | Not started | - |
| 3. Craft, Break, and Identify | 0/TBD | Not started | - |
| 4. Static Chart Rendering | 0/TBD | Not started | - |
| 5. Configuration and Async Fetch | 0/TBD | Not started | - |
| 6. Dynamic Texture Pipeline | 0/TBD | Not started | - |
| 7. Fetched Chart on the Block | 0/TBD | Not started | - |
| 8. Scheduled Refresh | 0/TBD | Not started | - |
| 9. Reliability Hardening | 0/TBD | Not started | - |
| 10. Manual Refresh and Runtime Control | 0/TBD | Not started | - |

## Requirement Coverage

All 52 v1 requirements map to exactly one phase. No orphans, no duplicates.

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | TOOL-01, TOOL-02, TOOL-03 | 3 |
| 2 | BLOCK-01, BLOCK-02, BLOCK-03, GEN-01, GEN-02 | 5 |
| 3 | BLOCK-04, BLOCK-05, BLOCK-06, GEN-03, GEN-04, GEN-05, GEN-06 | 7 |
| 4 | REND-01, REND-02, REND-03, REND-04, REND-05, REND-06, REND-07 | 7 |
| 5 | CFG-01, CFG-02, CFG-03, CFG-05, API-01, API-02, API-03, API-04, API-05 | 9 |
| 6 | TEX-01, TEX-02, TEX-03, TEX-04, TEX-05, TEX-06 | 6 |
| 7 | API-06, API-07, REF-02 | 3 |
| 8 | REF-01, REF-03, REF-04 | 3 |
| 9 | REL-01, REL-02, REL-03, REL-04, REL-05, REL-06 | 6 |
| 10 | REF-05, REF-06, CFG-04 | 3 |
| **Total** | | **52** |

## Version Discipline (applies to every phase)

This project targets Minecraft 1.20.1 with Mojang official mappings. Current Fabric documentation describes post-1.21 APIs, and nearly all community tutorials use Yarn mappings. Block entity renderers, `NativeImage` / `NativeImageBackedTexture` registration through `TextureManager`, render layers, and data generation provider signatures all differ meaningfully between the two.

**Working practice, established by research and verified empirically on this project:** when documentation and resolved sources disagree, the resolved sources win. Run `./gradlew genSources` and read the decompiled 1.20.1 code; use `javap` against the cached Mojang-mappings jar to settle signatures. This is the single most likely source of wasted effort in the milestone.

Phases carrying explicit MEDIUM-confidence verification work: **Phase 1** (`configureDataGeneration { client = true }` on 1.20.1), **Phase 3** (`FabricRecipeProvider` generation method shape), **Phase 6** (`registerTexture` auto-close behavior, `NativeImageBackedTexture` ownership, resource-reload survival).

---
*Roadmap created: 2026-09-07*
*Granularity: fine — 10 phases*
*Mode: mvp*

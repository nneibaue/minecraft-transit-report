# Human Design Transit Display

## What This Is

A Minecraft Java Edition mod (Fabric, 1.20.1) that adds a craftable, placeable block which renders a live Human Design transit chart on its face. The block fetches a PNG from an external Human Design API over HTTP, refreshes it roughly once a minute, and keeps showing the last good chart when the API is unreachable. Built for the author and a small group of friends on a private server.

The mod is a presentation client, not a calculation engine. All Human Design math and chart generation live in the external API.

## Core Value

A block placed in the world shows a current Human Design transit chart that keeps updating on its own, and never freezes or crashes Minecraft when the API misbehaves.

## Requirements

### Validated

- ✓ Toolchain verified end to end: the dev client launches and `runDatagen` produces output — Phase 1
- ✓ A display block exists, is craftable, and can be placed in the world — Phases 2-3
- ✓ Static Minecraft resources (models, recipe, loot table, translations) are produced by Fabric Data Generation — Phases 2-3
- ✓ The block renders an image on its face via a custom block entity renderer — Phase 4

### Active

- [ ] A dynamic texture pipeline turns arbitrary PNG bytes into a renderable texture and can swap it at runtime without leaking GPU resources
- [ ] An HTTP client fetches PNG bytes from a configurable base URL asynchronously, off the main/render thread
- [ ] Downloaded chart images appear on the placed block
- [ ] The chart refreshes on a configurable interval (default ~60 seconds)
- [ ] API failures are non-fatal: the last successful image stays on screen, errors are logged without spam, and the next scheduled refresh retries
- [ ] The player can trigger an immediate refresh by interacting with the block
- [ ] API base URL and refresh interval are configurable rather than hardcoded

### Out of Scope

- Human Design calculation logic in Minecraft — the external API is the source of truth; duplicating it in the mod is the single biggest architectural mistake available here
- Natal/birth-data input (date, time, location) and any GUI to enter it — the transit endpoint is parametrized by timestamp only, so the block entity needs no personal data and no config screen
- Multi-block physical structure — the display is one logical block; the renderer makes the chart appear larger than the block it sits on
- Storing PNG bytes in block entity NBT or the world save — images are transient runtime state, re-fetched on load
- Server-authoritative transit data with client synchronization — timestamp-only charts are identical for every player, so each client fetching independently is correct and far simpler
- API secrets or authentication credentials shipped in the mod — the endpoint is assumed safe for a client to call directly
- Public release to Modrinth/CurseForge — private use by the author and friends
- Decorative modeling and visual polish ahead of the dynamic texture pipeline — appearance work is deliberately deferred until images actually update on the block
- Local mock HTTP server (MOCK-01 through MOCK-03) — scoped out of v1 by roadmap decision; REL-04's timeout/non-200/malformed-PNG handling will be implemented and code-reviewed but not empirically exercised this milestone, since a public image endpoint cannot be provoked into misbehaving on demand (REQUIREMENTS.md, REL-04 verification note). Closes when the mock server is added or the real API can be made to fail on request.

## Context

**Repository state.** The repo is an unmodified Fabric example-mod template, one commit deep ("Initial template from Fabric"). Mod id `jollyalchemy-transit-report`, group `transitreport`, package root `transitreport`. Existing files are the template's `ExampleMixin`, `ExampleClientMixin`, the main/client/datagen entrypoints, and stock mixin configs. None of it is load-bearing.

**Toolchain — verified working.** An earlier reading of this repo treated the pairing of `loom_version=1.17-SNAPSHOT` and plugin id `net.fabricmc.fabric-loom-remap` against `minecraft_version=1.20.1` as a suspicious mismatch. It is not. Fabric Loom is a single continuously-updated tool that builds old Minecraft versions from its current release, and Loom 1.14 (Dec 2024) split the plugin id by whether the target Minecraft version is obfuscated: `net.fabricmc.fabric-loom-remap` is the correct id for obfuscated versions (≤1.21.11, which includes 1.20.1), while plain `fabric-loom` now serves 26.1+. The live official `FabricMC/fabric-example-mod` 1.20 branch uses this exact pattern today. `./gradlew build` was run against this repo and succeeded (exit 0). Toolchain work is therefore a short sanity check — confirm the dev client actually launches and `runDatagen` produces output — not a rework phase.

Two residual items, both small: the `fabricApi { configureDataGeneration { client = true } }` block is accepted at configuration time here (the build succeeds), but the `client = true` parameter is documented as a 1.21.4+ addition, so whether it does anything meaningful on 1.20.1 is worth confirming when datagen is first run. And Loom 1.17.x requires the *Gradle daemon* to run on JDK 17+ (21+ recommended) — a separate concern from the mod's own Java 17 bytecode target set by `options.release = 17`. This machine has JDK 26, so both are satisfied today.

**Version tension, acknowledged deliberately.** The author is following current Fabric documentation but has deliberately chosen to stay on 1.20.1 for its mod ecosystem. Current Fabric docs describe post-1.21 APIs. Block entity renderers, `NativeImage` / `NativeImageBackedTexture` registration through `TextureManager`, render layers, and datagen provider signatures all differ meaningfully between 1.20.1 and current. Implementation must follow the 1.20.1 APIs as they exist in the resolved dependencies and Minecraft source, not what current tutorials or documentation show. Where the two disagree, the resolved sources win. This is the most likely source of wasted effort in the project.

**API status.** The Human Design API is in progress and not yet available. Development proceeds against dummy endpoints on two levels: a public changing-image URL for zero-setup smoke testing (proves the refresh pipeline visually, since each request returns a different picture), and a small local mock server kept in the repo for deliberately producing timeouts, non-200 statuses, and malformed image bytes. The error-handling requirements cannot be verified without the second one.

**API contract.** Parametrized `GET`, returning image bytes directly with `Content-Type: image/png` — not JSON. Conceptually `GET {baseUrl}/api/transit/chart?timestamp=...`. Exact paths and parameters are supplied by configuration, and the contract may still shift while the API is built. The HTTP layer should make adding a second chart endpoint straightforward without restructuring.

**Author background.** Experienced software engineer, new to Minecraft mod development. Minecraft- and Fabric-specific concepts (block entities, renderers, registries, datagen, client vs. server environments, mixins) should be explained when they matter; general software engineering should not be.

**Intended component decomposition** (names are suggestions; idiomatic Fabric structure wins if it differs):
`TransitDisplayBlock`, `TransitDisplayBlockEntity`, `TransitDisplayRenderer`, `TransitApiClient`, `TransitTextureManager`, `TransitRefreshScheduler`, `TransitConfig`.

**Runtime pipeline:**
refresh timer → `TransitApiClient` → HTTP GET → PNG bytes → `TransitTextureManager` → Minecraft texture → `TransitDisplayRenderer` → chart displayed in world.

## Constraints

- **Tech stack**: Minecraft Java Edition 1.20.1, Fabric Loader 0.19.5, Fabric API 0.92.12+1.20.1, Java 17, Gradle + Fabric Loom, IntelliJ IDEA — deliberately chosen for the 1.20.1 mod ecosystem, and fixed for this milestone
- **Threading**: no blocking network I/O on the main or render thread — Minecraft must stay responsive while a request is in flight; completion must hand back to the correct Minecraft thread before touching texture or render state
- **Separation of concerns**: the renderer never performs HTTP; the HTTP client never manipulates rendering state; Human Design logic never enters the mod at all
- **Resource lifecycle**: dynamically created textures must be released when replaced — a texture allocated every 60 seconds and never freed is an unbounded GPU leak
- **Persistence**: no large binary blobs in block entity NBT or the world save; persist only configuration and state that genuinely must survive a reload
- **Logging**: diagnostics on failure, but no per-tick log spam from a repeatedly-failing endpoint
- **Multiplayer**: not a built feature this milestone, but the architecture must not make it unnecessarily hard later — the mod will run on a small private server
- **Dependencies**: prefer mechanisms Fabric/Minecraft already provide; a third-party library needs an explicit justification before it goes in
- **Abstraction**: this is a small mod — avoid premature abstraction and speculative extension points

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Target Minecraft 1.20.1 rather than current stable | Largest mod and modpack ecosystem; deliberate choice made with the API-divergence cost understood | — Pending |
| External API owns all Human Design calculation | Keeps the mod a thin presentation client; calculation logic in Minecraft would be duplicated, untestable, and wrong to maintain | — Pending |
| Transit endpoint parametrized by timestamp only | No natal/birth data means no persisted personal state, no config GUI, and identical output for every player | — Pending |
| Client-side fetch per client, no server authority | Timestamp-only charts are identical for all players, so per-client fetching works on a shared server without any synchronization protocol | — Pending |
| Single logical block, not a multi-block structure | The renderer can draw the chart larger than the block; multi-block adds placement, state, and validation complexity that buys nothing yet | — Pending |
| Dual dummy endpoints (public changing image + local mock) | The public URL proves refresh visually with zero setup; only a controllable local mock can produce the timeouts, 500s, and malformed PNGs the reliability requirements need | — Pending |
| Fabric Data Generation for static JSON only | Datagen is build-time resource generation; forcing runtime HTTP, texture, or refresh behavior through it would be a category error | — Pending |
| Toolchain kept as-is; verification is a sanity check | `./gradlew build` succeeds against the existing Loom 1.17 / `fabric-loom-remap` / MC 1.20.1 setup, which matches the official Fabric example mod's 1.20 branch. The earlier suspicion of a version mismatch was unfounded | ✓ Good |
| Prefer resolved sources over documentation on every API question | Verified empirically this project: `javap` against the cached 1.20.1 Mojang-mappings jar settled signatures that docs and tutorials disagreed on. `./gradlew genSources` is the tie-breaker whenever 1.20.1 and current docs conflict | ✓ Good — confirmed again in Phase 3: `FabricRecipeProvider.buildRecipes(Consumer<FinishedRecipe>)` and `FabricBlockLootTableProvider.generate()` (no-arg) settled the MEDIUM-confidence signature risk research had flagged, closing it against real `runDatagen`/`build` runs rather than current (post-1.21) Fabric docs |
| Single-dirt shapeless recipe as the shipped Phase 3 recipe, thematic 3x3 recipe kept commented-out beside it | Zero-effort testing convenience so iteration never requires gathering materials; the intended Amethyst Shard / Echo Shard / Clock / Glow Ink Sac recipe is preserved verbatim (all ingredients, all pattern rows) so swapping it in later is uncommenting, not re-deriving from REQUIREMENTS.md | ✓ Good — Phase 3 |
| `TransitChartBlock` renders fully invisible in-world (`getRenderShape()` → `RenderShape.INVISIBLE`) with a thin, wall-hugging `VoxelShape`, rather than the originally-planned full 1x1x1 cube with the chart floating in front of it | Direct in-game visual review (Phase 4 checkpoints) showed the full-cube version reading as a chunky block bolted to the wall, not a mounted picture; suppressing the vanilla model and thinning the hitbox makes only the floating chart quad visible, matching the "painting on the wall" look the author wanted | ✓ Good — Phase 4 |
| Chart quad anchored flush to the wall-side face, vertically centered on the block, and sized 1.5 blocks wide (not the original 2.0-block, bottom-anchored, far-face-anchored quad) | Four rounds of live visual iteration: the far-face anchor left the chart floating a full block off the wall once the block became invisible; bottom-anchoring read as "too high" once the quad was taller than one block; 1.5 blocks reads as a wall panel rather than an oversized poster | ✓ Good — Phase 4 |
| `noOcclusion()` added to `TransitChartBlock`'s properties | The now-thin, invisible block was still treated as a full opaque cube for neighbor face-culling, leaving a rendering hole in the wall behind it until a chunk rebuild; `noOcclusion()` fixes this at the source | ✓ Good — Phase 4 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-08 after Phase 4*

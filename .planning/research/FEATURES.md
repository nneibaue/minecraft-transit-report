# Feature Research

**Domain:** In-world image/screen display blocks for Minecraft (Fabric 1.20.1)
**Researched:** 2026-09-07
**Confidence:** MEDIUM-HIGH (grounded in named, currently-maintained prior-art mods and vanilla mechanics; some Fabric 1.20.1 API specifics have MEDIUM confidence pending hands-on verification during implementation)

## Prior Art Surveyed

| Mod / Mechanic | Platform | What it actually is | Relevance |
|---|---|---|---|
| **ImageFrame** (LOOHP) | Paper plugin, server-side | Puts arbitrary internet images on vanilla maps + item frames, spans multiple frames in a grid, auto-fits aspect ratio, supports GIFs, map markers | Closest "sizing via multi-unit grid" prior art; also the clearest example of arbitrary-URL-as-abuse-vector |
| **ImageFrameClient** (LOOHP) | Fabric/Quilt client mod | Companion client mod that replaces ImageFrame's blocky 128×128 map render with a full-color HD texture for players who have it installed | Precedent for "server sends low-fi vanilla fallback, enhanced client mod renders better" — not directly applicable (no vanilla fallback exists here) but useful precedent for texture-replacement rendering |
| **WATERFrAMES** (SrRapero720, née WATERMeDIA) | Fabric/Forge | Frames, Projectors, TVs, Big TVs; plays images *and video* from YouTube/Twitch/Drive/local files; remote-control item; per-block brightness/transparency/audio-distance settings; URL whitelist for admins | Best example of "maximalist" scope creep (video, audio, remote control) — useful as a **do-not-become-this** anti-pattern reference |
| **Modern Online Picture Frames** (CreativeMD, formerly OnlinePictureFrame) | Forge | Frame block showing a `.png`/`.jpg`/`.gif` from a URL, resizable up to 32×32 | Documented failure mode: a failed download makes the image **disappear entirely** rather than keeping the last good image — a concrete anti-pattern to avoid |
| **Projector Mod** (HashiCraft/fabric-projector-mod) | Fabric, client-side | Custom block, displays an internet image; size grows by placing additional picture blocks adjacent to each other | Confirms "place N blocks side by side" as the standard sizing mechanism competitors use — the exact multi-block pattern this project has explicitly ruled out |
| **WebDisplays** (+ MCEF) | Forge | Embeds a full Chromium browser in a placeable screen; keyboard block for typing, linking tool, screen-configurator GUI; each player gets an independent browser session | Useful negative example for interaction/config scope (full GUI, full browser) and a positive example for "each client renders independently, no sync needed" |
| **Framed Blocks** (alex5nader) | Fabric | Lets a frame block copy any *existing block's* texture (wood, stone, etc.) for decorative building | Sounds adjacent by name but is unrelated — texture-copying for building, not internet image display. Included to rule it out explicitly. |
| **Create: Display Board / Display Link** | Fabric/Forge (Create) | Multi-block-linkable text display (not images) driven by a rotating-shaft power requirement (RPM), reads data from a linked source block | Not image display, but a good analog for "refresh cadence tied to a mechanism" and for multi-block text scaling (up to 32×32) — confirms multi-block is the *conventional* scaling answer this project deliberately opts out of |
| **Vanilla map art** (maps + item frames) | Vanilla | Build a block-for-block mosaic, put a filled map (128×128px, 62-color vanilla palette) in an item frame | The baseline vanilla capability every image mod is built to exceed: static, one-time, low fidelity, no refresh. Establishes why any "just use vanilla maps" alternative was correctly rejected in favor of a custom BlockEntityRenderer. |
| **Immersive Portals** | Fabric/Forge | Live rendering of another dimension through a portal plane, no loading screen | Not an image-display mod; included only to note it does **not** apply here — it renders geometry live, not fetched raster images, and doesn't inform this feature set. |

## Feature Landscape

### Table Stakes (Players Expect These)

Missing any of these will make the block feel broken, not just unpolished.

| Feature | Why Expected | Complexity (Fabric 1.20.1) | Notes |
|---|---|---|---|
| Directional facing block state (wall-mounted, faces placement direction) | Every prior-art block that displays something on a face — item frames, paintings, ImageFrame's frames, WebDisplays screens — orients to the wall/direction the player was facing when placed. A display with no facing (or one that always shows the same static side regardless of placement) reads as a bug, not a limitation. | LOW — standard `HorizontalFacingBlock`/`Properties.HORIZONTAL_FACING` pattern, identical to furnaces/observers; set via `getPlacementState()` from `ItemPlacementContext.getPlayerFacing()` | **Dependency:** the renderer must read this state to orient the rendered quad — renderer work cannot be considered complete without it. |
| Renders larger than the block's texture without a multi-block structure | PROJECT.md already commits to this ("the renderer makes the chart appear larger than the block it sits on"). The vanilla **painting** entity is the exact existing precedent: a single placed object whose rendered geometry extends beyond a 1×1×1 bounding box, no multi-block assembly. | MEDIUM — requires pushing an oversized quad in the BlockEntityRenderer and, because the quad extends past the block's default 1×1×1 culling box, overriding the render bounding box (see Light/Rendering section) so it doesn't pop out of view at its own edges while the anchor block is still on screen | **Dependency:** requires the facing state above (quad must be oriented correctly) and a bounding-box override (see rendering section). |
| Aspect-ratio-correct fit, never stretched | ImageFrame explicitly markets "automatic image fitting... images won't be stretched" as a feature — a stretched/squashed image reads as amateurish immediately, more so here since a chart's proportions and layout are meaningful data, not decoration. | LOW — since the source is a single known API (not arbitrary user photos), the renderer can target a fixed canvas aspect ratio matching the chart image once, rather than compute aspect dynamically | Simpler than every prior-art mod's version of this problem, because they must handle arbitrary user-supplied image dimensions and we don't. |
| A defined "no image yet" state on first placement | A freshly placed block before the first fetch completes must not render as a missing-texture purple/black checkerboard — that unambiguously reads as a bug on first use. | LOW — bundle a static placeholder PNG as a mod resource, bind it as the initial texture before the first successful fetch | This is the *only* loading-state visual that is table stakes (see Refresh/Staleness below for why per-refresh loading indicators are NOT table stakes). |
| Last-known-good image persists through fetch failures | Explicit PROJECT.md requirement, and directly validated by prior-art failure: Modern Online Picture Frames/OnlinePictureFrame has a documented, reported bug where a failed download makes the image **disappear** rather than keep showing the old one — players experience that as the block "breaking." Not disappearing is the bar, not a nice-to-have. | LOW — simply don't replace the currently-bound texture unless/until a new fetch succeeds | Directly prevents the single most common real-world complaint found in prior-art issue trackers for this feature category. |
| Right-click triggers an immediate manual refresh | Explicit PROJECT.md Active requirement; also the near-universal minimum interaction across every reviewed mod that has *any* interaction model at all (WebDisplays' configurator, ImageFrame's admin commands, etc. all gate on some form of "player does something to force an update"). | LOW — interaction handler calls the same refresh code path the scheduler uses | **Dependency:** requires the API client + texture-swap pipeline to already exist; this is a UI hook onto existing plumbing, not new plumbing. |
| Craftable via a normal recipe, datagen-produced | Explicit PROJECT.md Active requirement ("craftable"); a command-spawned or creative-only block breaks the basic survival-mode convention every friend on the server will assume applies. | LOW — a standard shaped-crafting-recipe JSON, produced the same way as the rest of the block's static resources via Fabric Data Generation | No exotic recipe mechanic (smithing upgrades, advancement gating) is expected for a utility/decorative block like this — a plain crafting-table recipe is the norm (see Crafting section). |
| Legible chart face regardless of ambient light level | A dark-room test is the single rendering detail every player will notice immediately and complain about if wrong — more likely to be noticed than facing bugs or aspect issues, because "I can't read it" is an instant, obvious failure. | MEDIUM — needs an emissive/unshaded render approach for the chart quad (see Light/Rendering section); this is new territory relative to a stock BlockEntityRenderer that respects world light like any ordinary block. | Distinct from *emitting* light into the room — see Anti-Features. |
| No per-tick log spam on repeated fetch failures | Explicit PROJECT.md constraint; also the most common "this mod is badly behaved" complaint pattern for anything doing periodic network I/O in a client mod. | LOW — throttle/backoff identical consecutive failures rather than logging every attempt | Silence-on-failure is equally wrong — the requirement is throttled diagnostics, not zero diagnostics. |

### Differentiators (Worth Having, Not Essential)

| Feature | Value Proposition | Complexity | Notes |
|---|---|---|---|
| Hover tooltip on the item ("Transit Display — right-click to refresh") | Discoverability for friends who won't read documentation; low cost, real value on a shared server with multiple casual users | LOW — a translation-key tooltip line on the `BlockItem`, produced via datagen translations already planned | Genuinely worth including even though PROJECT.md doesn't list it — costs almost nothing and directly serves "a few friends" using the block without a manual. |
| Actionbar/chat feedback on manual refresh ("Refreshing…") | Without feedback, a right-click refresh feels like it might not have done anything, especially since a successful refresh should otherwise be a silent, instant swap | LOW — `player.sendMessage` on the actionbar, cleared/replaced automatically | Optional because the visual swap itself is feedback once it lands; only useful for the in-flight gap. |
| Author-only runtime config command (e.g. `/transitreport reload`, `/transitreport seturl <url>`) | Genuinely useful while the API is still being built and its contract may shift — lets the author iterate without redistributing a config file or restarting the client each time | LOW-MEDIUM — a client command registered via Fabric's command API, gated informally by "only the author runs this on their own client" (no real permission system needed for a private server) | Distinct from a general config screen — see Configuration UX; this is a developer-convenience escape hatch, not a player feature. |
| 6-direction placement (ceiling/floor mounting, not just 4 wall directions) | Matches blocks like observers/dispensers; lets a friend mount the display on a ceiling or floor if their build calls for it | LOW-MEDIUM — swap `HorizontalFacingBlock` for full `Direction`-based facing (`FacingBlock`-style, six-way) | Not table stakes: wall-mounted-only precedent (paintings, item frames, most reviewed image frame mods) is completely normal and unsurprising; this is a nice-to-have generalization. |
| Visible staleness indicator when the last-good image is older than N refresh intervals (e.g., a dimmed border or small corner marker) | Tells a player "this is not live" during an extended outage, rather than silently showing a frozen chart indefinitely | MEDIUM — needs an additional render pass/overlay and a tracked "last successful fetch" timestamp | None of the reviewed prior-art mods implement this well; it is a genuine differentiator, but explicitly lower priority than getting the base pipeline working, per PROJECT.md's decorative-polish-later stance. Worth revisiting only if real outages during actual use make "is this current?" a recurring point of confusion among friends. |

### Anti-Features (Deliberately NOT Built)

| Feature | Why It Looks Appealing | Why It's Actually Harmful Here | Alternative |
|---|---|---|---|
| Arbitrary player-supplied URLs (right-click to "set URL", as in ImageFrame/Modern Online Picture Frames/WATERFrAMES) | Feels flexible — any friend could point the block at anything | This is the specific feature public-server admins cite as the reason these mods need permission gating and URL whitelists (WATERFrAMES ships a whitelist *because of* this). It turns a single-purpose display into an open image-fetching proxy driven by untrusted player input, on a shared server, for no purpose this project has. | Base URL is author-configured only (already PROJECT.md's design); no in-world way for any player to change what URL is fetched. |
| Disk caching of downloaded images | Would survive a restart without an immediate network hit; feels like resilience | Conflicts directly with PROJECT.md's architecture ("images are transient runtime state, re-fetched on load"); adds file I/O, cache invalidation, and disk management for bytes that are worthless within a minute of being fetched anyway | In-memory last-good-texture-stays-until-replaced (already required) plus a cheap fresh fetch on load — strictly simpler and equally correct. |
| Per-player personalized charts | Feels like the "real" long-term vision of a Human Design mod | Explicitly out of scope per PROJECT.md, and for good reason: it would simultaneously undo three load-bearing simplifications — no server authority, no sync protocol, no config GUI — all of which depend on every client fetching an identical timestamp-keyed image | If personalization is ever wanted, it is a distinct future milestone with its own natal-data storage and sync design, not an incremental add to this one. |
| Animated GIF / video playback | Several competitors (WATERFrAMES, Modern Online Picture Frames, WebDisplays, Cinema Mod) treat this as a headline feature | The API contract is a single static PNG per request; GIF/video implies frame sequencing, playback state, and in WebDisplays'/WATERFrAMES' case, heavyweight native dependencies (Chromium embedding, media codecs) — wildly disproportionate to "redraw a PNG once a minute" | None needed — static image refresh already delivers "the picture changes over time" from the user's point of view. |
| Sound | Some multimedia-display mods (WATERFrAMES) bundle audio distance/volume controls | No use case exists for a static chart; pure scope creep | N/A |
| Multi-block assembly for a bigger display | This is literally how every sizing-focused competitor (ImageFrame's map grids, Projector Mod's adjacent blocks, Create's Display Board) solves "bigger than one block" | PROJECT.md already excludes this for good reason; the oversized-single-block-quad approach (vanilla painting precedent) achieves the same visual outcome without placement/state/validation complexity for a structure that buys nothing at this size | Single logical block with renderer geometry exceeding its collision box, as already planned. |
| Storing images in world save data / block entity NBT | Feels like "durable" state | Same category error as disk caching, but worse — bloats world save files and chunk data for bytes with a shelf life of about a minute | Nothing persisted beyond configuration; re-fetch on load, as already planned. |
| Full in-game browser (WebDisplays/MCEF pattern) | Maximum flexibility — could show anything, not just this one chart | The single worst effort-to-value ratio surveyed: embedding a Chromium runtime to render one PNG endpoint. Also reintroduces the arbitrary-URL problem in its most extreme form. | A purpose-built HTTP GET + PNG decode + texture bind, exactly as scoped. |
| Visible loading spinner/animation on every periodic (not first-load) refresh | Feels like helpful "it's working" feedback | A chart that visibly flickers or shows a loading state every ~60 seconds reads as an unstable/buggy display, not a polished one — the goal state is an instant, silent swap on success | Placeholder/loading state only before the very first successful fetch; every subsequent refresh is silent unless it fails (in which case: keep showing the old image, per table stakes above). |
| Right-click opens a config/settings GUI on the block itself | WebDisplays' screen-configurator makes this feel like an expected pattern for "smart" blocks | There is nothing per-block or per-player to configure — no natal data, no personalization, no per-instance URL. Building a GUI here solves a problem this project does not have. | Right-click = refresh only; any real configuration lives in the author's config file / optional reload command, not an in-world screen. |
| Mod Menu + Cloth Config in-game settings screen | Common, idiomatic Fabric pairing for "proper" mod configuration | No per-player settings exist to configure — every player sees an identical chart — and the two real config values (base URL, refresh interval) are author-set deployment concerns, not day-to-day player options. Pulling in two extra mod dependencies contradicts the project's stated dependency conservatism for a two-value config on a private few-friends server. | A plain config file (JSON/properties) the author edits by hand; optionally a client-only reload command (see Differentiators) for iteration convenience. |

## Findings By Dimension

**1. Placement and orientation.** Minimum non-broken = 4-direction horizontal wall facing, matching item frames, paintings, and every reviewed image-frame mod's wall-mount-only convention. 6-direction (ceiling/floor) placement is a legitimate later enhancement, not a v1 gap — no prior-art mod in this specific category (image display, as opposed to general decorative blocks) treats floor/ceiling mounting as expected.

**2. Display sizing.** Every competitor that scales beyond one block does it via a multi-block/multi-frame grid (ImageFrame's map grid, Projector Mod's adjacent blocks, Create's Display Board). This project has correctly ruled that out. The right single-block precedent already exists in vanilla: the painting entity renders geometry larger than its own placement footprint. Aspect-ratio handling is simpler here than for any competitor because the source image dimensions are fixed and known (one API, one chart layout) rather than arbitrary user photos — a fixed target aspect ratio, decided once, replaces the dynamic-fit logic every general-purpose image mod needs.

**3. Refresh and staleness UX.** The prior-art failure mode worth avoiding by name is Modern Online Picture Frames' documented "failed download removes the image" bug. The correct behavior — already specified in PROJECT.md — is the opposite: last-good stays until replaced. A visible loading state is table stakes exactly once (before the first successful fetch) and actively harmful if repeated on every routine refresh (reads as flicker/instability, not diligence). A staleness indicator ("this is N minutes old") is a real, currently-unaddressed gap in every mod surveyed, but is correctly deferred here per the project's decorative-polish-later stance — revisit only if actual outages make staleness a recurring point of confusion for the few friends using it.

**4. Interaction.** Right-click-to-refresh is both the PROJECT.md requirement and the near-universal minimum across prior art. Shift-right-click and full in-block GUIs (WebDisplays' configurator being the maximal example) exist to serve configuration needs — per-instance URLs, resizing, rotation — that this project's fixed, timestamp-only, single-endpoint design does not have. Shift-right-click becomes a sensible extension point only once a second chart endpoint actually exists (PROJECT.md notes this as a possibility), at which point it could cycle between chart types — not needed now.

**5. Crafting and acquisition.** Table stakes is simply "a normal shaped recipe exists," which is already an Active requirement. On ingredient thematics: vanilla's own precedent for "a device for looking at something specific" is the Spyglass (copper + amethyst shard), and Human Design's astrology-adjacent framing arguably makes amethyst a more fitting "mystical viewing" material than pure redstone circuitry, which reads more as generic vanilla "electronics." This is explicitly a decorative/thematic decision PROJECT.md has deferred, so treat it as a placeholder recommendation, not a requirement, until visual polish is in scope.

**6. Light and rendering behavior.** The most-noticed rendering issue in this category is legibility in a dark room — more visible to players than render-distance edge cases or facing bugs, because it's an instant, obvious "I can't read it." The correct fix is emissive/unshaded rendering of the chart quad, not actual light emission from the block: emitting light blurs the block's purpose (it starts getting used as a light source, interacts with mob spawning and comparators in ways a "screen" shouldn't), which nothing in prior art actually does for this reason — even WebDisplays' browser screens are legible without turning the room into a lit space. Visibility through walls is a clear anti-feature — no reviewed mod does this, and it would read as a bug, not a feature. Distance: Minecraft/Fabric block entities render out to a fixed 64-block radius by default, which is already generous for a private-server display and needs no override — the one real technical dependency is that because this block's rendered geometry exceeds its own 1×1×1 bounding box (sizing, dimension 2), the renderer must override the block entity's render bounding box so the oversized quad doesn't get culled at its own edges while the anchor block is still on-screen; this is a genuine Fabric 1.20.1 API dependency between the sizing feature and the rendering-behavior feature, not just a "nice to have."

**7. Configuration UX.** A plain config file is fully sufficient and is what PROJECT.md's requirements actually call for (base URL and refresh interval "configurable rather than hardcoded" — nothing about an in-game UI). Mod Menu + Cloth Config is a real, common Fabric convention, but it exists to serve per-player, frequently-tweaked settings — neither of which applies: there is no per-player configuration surface at all (every client sees the same chart), and the two real settings are one-time deployment choices the author makes, not options friends need exposed to them. Adding those dependencies here would be configuration infrastructure in search of a problem.

**8. Anti-features.** See table above; the throughline across every genuinely harmful candidate is the same: each one exists to solve a personalization, flexibility, or generality problem (arbitrary URLs, per-player charts, GIF/video, a full browser, an in-block GUI) that this project's fixed, timestamp-only, single-purpose design does not have. Building any of them would import complexity to solve problems that don't exist here, while eroding the specific simplifications (no server authority, no sync, no config screen, no persisted personal data) that make this project's architecture tractable in the first place.

**9. Multiplayer expectations.** PROJECT.md's "each client fetches independently, no server authority" design is validated by prior art rather than contradicted by it — WebDisplays deliberately gives each player an independent browser session for the same reason (avoids a sync protocol, keeps things simple, degrades independently per client). At "a few friends" scale, N clients each hitting the API on their own 60-second timer is a non-issue; it would only become a real design question at public-server scale, which is explicitly out of scope. Visible skew between two friends standing in front of the same block (their refresh timers started at different wall-clock moments, so they may see charts a few seconds apart) is expected and should be harmless as long as the underlying chart data doesn't visibly jump within a single refresh window — worth a downstream question of whether truncating the requested timestamp to the same wall-clock minute across all clients would cheaply reduce visible skew with zero synchronization plumbing. A client with no network access should simply sit on its own placeholder/last-good state indefinitely and never affect other players — the client-fetch architecture already guarantees this for free, since there is no shared state to corrupt. Genuinely worth naming as a strength: this project's "no sync at all" model sidesteps a whole category of multiplayer complexity that ImageFrame (map-data sync), WebDisplays (per-player session management), and WATERFrAMES (remote-control command routing) all have to solve and this project doesn't need to.

## Feature Dependencies

```
Directional facing block state
    └──required-by──> Oriented block entity renderer
                           └──required-by──> Oversized single-block display quad (sizing)
                                                  └──requires──> Custom render bounding box override
                                                                     (else quad culls/pops at its own edges)

Dynamic texture pipeline (PROJECT.md Active requirement)
    └──required-by──> Placeholder/"no image yet" texture (table stakes)
    └──required-by──> Last-known-good persistence on fetch failure (table stakes)
    └──required-by──> Emissive/unshaded rendering (legibility in the dark)

HTTP client + refresh scheduler (PROJECT.md Active requirement)
    └──required-by──> Right-click manual refresh (just a second call site into the same pipeline)
    └──enhances──> Author-only reload/seturl command (differentiator)

Second chart endpoint (not yet built; API contract may add one)
    └──enables──> Shift-right-click "cycle chart type" (differentiator, not buildable yet)

Multi-block assembly ──conflicts──> Single logical block (PROJECT.md decision)
Arbitrary player-supplied URLs ──conflicts──> Author-only fixed base URL (PROJECT.md decision)
Mod Menu + Cloth Config ──conflicts──> No per-player configuration surface exists
```

### Dependency Notes

- **Oversized display quad requires a render bounding box override:** this is the one true Fabric-1.20.1-specific technical dependency surfaced by this research. Block entities are culled based on a bounding box computed from the block's own footprint by default; a renderer that draws geometry larger than that footprint (the chosen sizing approach) will visually pop in/out at the edges of that box unless the bounding box is explicitly overridden to match the larger rendered extent. This must be handled in the same implementation pass as the sizing/rendering work, not treated as a later polish item.
- **Facing state must exist before renderer orientation is meaningful:** the renderer needs to know which face/direction to draw the oversized quad on; this is a hard ordering dependency for phase sequencing (facing block state is prerequisite work, not parallel work, to the renderer).
- **Manual refresh has no new plumbing:** because it's explicitly required to route through the same API client and texture pipeline as the scheduled refresh, it should not be planned as separate work from that core pipeline — it's a one-line interaction-handler hook once the pipeline exists.
- **Mod Menu + Cloth Config conflicts with the actual configuration need:** including them would be solving a nonexistent per-player configuration problem; they are called out explicitly as a non-dependency to prevent them being pulled in "because it's idiomatic Fabric" without re-examining whether this project needs them (it doesn't).

## MVP Definition

### Launch With (v1) — matches PROJECT.md's Active requirements plus the small set of near-zero-cost additions this research surfaced

- [ ] Directional (at minimum 4-way horizontal) facing block state — renderer cannot be correctly oriented without it
- [ ] Single-block display rendering larger than its own footprint, with a matching render-bounding-box override
- [ ] Fixed-aspect-ratio, never-stretched chart rendering
- [ ] Placeholder texture shown before the first successful fetch
- [ ] Last-known-good image persists through fetch failures (no disappearing image, no error UI)
- [ ] Right-click triggers immediate manual refresh
- [ ] Emissive/unshaded rendering so the chart is legible regardless of ambient light
- [ ] Craftable via a standard datagen-produced recipe
- [ ] Config file (not in-game screen) for base URL and refresh interval
- [ ] Throttled (not spammy, not silent) failure logging
- [ ] Item tooltip naming the block and its refresh interaction — near-zero cost, real value for friends using it without docs

### Add After Validation (v1.x)

- [ ] Author-only client command for reload/seturl, to speed up iteration against the still-in-progress API — add once the API contract has stabilized enough that manual config-file edits become the actual bottleneck
- [ ] 6-direction (ceiling/floor) placement — add if a friend's build actually wants it
- [ ] Shift-right-click chart-type cycling — add only once/if a second chart endpoint exists
- [ ] Actionbar feedback on manual refresh — add if "did that do anything" confusion actually comes up in play

### Future Consideration (v2+)

- [ ] Visible staleness indicator for extended outages — defer until real usage shows this is a recurring point of confusion, not a theoretical one
- [ ] Per-timestamp-minute request alignment across clients to reduce visible refresh skew — cheap idea, but only worth it if skew is ever actually noticed by two friends standing together
- [ ] Decorative modeling / visual polish of the block itself — explicitly deferred by PROJECT.md until the dynamic texture pipeline works end to end

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| Facing block state | HIGH | LOW | P1 |
| Oversized single-block rendering + bounding box override | HIGH | MEDIUM | P1 |
| Aspect-ratio-correct fit | HIGH | LOW | P1 |
| Placeholder before first fetch | HIGH | LOW | P1 |
| Last-known-good persistence on failure | HIGH | LOW | P1 |
| Right-click manual refresh | HIGH | LOW | P1 |
| Emissive/dark-room legibility | HIGH | MEDIUM | P1 |
| Craftable recipe via datagen | HIGH | LOW | P1 |
| Config file for URL/interval | HIGH | LOW | P1 |
| Throttled failure logging | MEDIUM | LOW | P1 |
| Item tooltip | MEDIUM | LOW | P1 |
| Author reload/seturl command | MEDIUM | LOW-MEDIUM | P2 |
| 6-direction placement | LOW | LOW-MEDIUM | P2 |
| Shift-right-click chart cycling | LOW (blocked on 2nd endpoint) | LOW | P3 |
| Staleness indicator | MEDIUM | MEDIUM | P3 |
| Refresh-skew alignment | LOW | LOW | P3 |
| Decorative modeling | MEDIUM | MEDIUM-HIGH | P3 (explicitly deferred) |

**Priority key:** P1: this milestone. P2: next milestone if it earns its way in through real use. P3: future consideration, not currently justified.

## Competitor Feature Analysis

| Feature | ImageFrame (LOOHP) | WebDisplays (Forge+MCEF) | WATERFrAMES | Our Approach |
|---|---|---|---|---|
| Sizing beyond 1 block | Multi-frame/map grid | Multi-block screen assembly | Adjacent-block placement | Single block, oversized render geometry + bounding-box override (painting-style) |
| Image source | Any player-supplied URL, admin-gated | Any URL (full browser) | Any URL, admin whitelist | One fixed, author-configured base URL; not player-editable in-world |
| Failure behavior | Not clearly documented | N/A (live browser, shows its own error page) | Not clearly documented | Explicit: keep last-known-good, never blank, throttled logging |
| Interaction | Server commands, permissions | Right-click for browser, keyboard block, configurator GUI | Remote-control item, commands | Right-click = refresh only; no GUI |
| Config surface | Server-side plugin config + commands | In-world configurator GUI per screen | In-world settings + remote item | Plain config file; no in-game screen (no Mod Menu/Cloth Config) |
| Multiplayer model | Server-authoritative (map data synced to clients) | Per-player independent browser session | Server-side state, remote sync | Per-client independent fetch, no sync at all — simplest of all four |
| Animated/video content | GIFs supported | Full video via Chromium | Video + audio via WATERMeDIA | None — static PNG only, by design |

## Sources

- [ImageFrame — GitHub](https://github.com/LOOHP/ImageFrame), [ImageFrame — Modrinth](https://modrinth.com/plugin/imageframe), [ImageFrame — SpigotMC](https://www.spigotmc.org/resources/imageframe-load-images-on-maps-item-frames-support-gifs-map-markers-survival-friendly.106031/)
- [ImageFrameClient — GitHub](https://github.com/LOOHP/ImageFrameClient)
- [WATERFrAMES — GitHub](https://github.com/SrRapero720/waterframes), [WATERFrAMES — CurseForge](https://www.curseforge.com/minecraft/mc-mods/waterframes)
- [Modern Online Picture Frames — CurseForge](https://www.curseforge.com/minecraft/mc-mods/online-picture-frame); failure-mode evidence: [OnlinePictureFrame issue #68 "Could not download image"](https://github.com/CreativeMD/OnlinePictureFrame/issues/68), [issue #62](https://github.com/CreativeMD/OnlinePictureFrame/issues/62)
- [Projector Mod — GitHub (HashiCraft/fabric-projector-mod)](https://github.com/HashiCraft/fabric-projector-mod)
- [WebDisplays — Modrinth](https://modrinth.com/mod/webdisplays), [WebDisplays overview — thespike.gg](https://www.thespike.gg/minecraft/beginners-guide/webdisplays-mod)
- [Framed Blocks (alex5nader) — GitHub](https://github.com/alex5nader/Framed)
- [Create Display Board — Create Wiki (Fandom)](https://create.fandom.com/wiki/Display_Board), [Create Display Link — Create Wiki (Fandom)](https://create.fandom.com/wiki/Display_Link)
- Vanilla map art mechanics — [Map Art Studio](https://www.minecraftmaps.com/tools/map-art-studio), general knowledge of vanilla map/item-frame mechanics (62-color palette, 128×128 grid)
- [Fabric Block Entity Renderers documentation](https://docs.fabricmc.net/develop/blocks/block-entity-renderer), [Fabric Wiki: Rendering Blocks and Items Dynamically](https://wiki.fabricmc.net/tutorial:dynamic_block_rendering) — confirms fixed 64-block default render distance for block entities, and the submit/render model relevant to bounding-box overrides
- Immersive Portals — [Modrinth](https://modrinth.com/mod/immersiveportals) (reviewed and ruled out as inapplicable prior art)
- Project constraints and explicit scope decisions — `.planning/PROJECT.md`

---
*Feature research for: In-world image/screen display block, Minecraft Fabric 1.20.1*
*Researched: 2026-09-07*

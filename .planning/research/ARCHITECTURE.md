# Architecture Research

**Domain:** Fabric mod for Minecraft 1.20.1 — block that renders a remotely-fetched PNG on its face, refreshed asynchronously
**Researched:** 2026-09-07
**Confidence:** HIGH for source-set boundaries, registration mechanics, and the render/threading model (cross-checked against Yarn 1.20.1 javadocs and Fabric API 0.9x javadocs). MEDIUM for resource-reload survival of a manually-registered texture (inferred from `TextureManager`/reload-listener design, not from an explicit 1.20.1-specific statement). All version-sensitive names are given in **Mojang official mappings** per the project's `loom.officialMojangMappings()` toolchain, since that's what will actually appear in the IDE.

---

## 1. Split Source Sets — Where Every Component Lives

### The mechanism, concretely

`loom { splitEnvironmentSourceSets() }` does not just add an annotation convention — it creates **two separate compilation units**, `src/main/java` (compiled against a "common" classpath that has the dedicated-server-safe subset of Minecraft) and `src/client/java` (compiled against `src/main` **plus** the full client classpath: `MinecraftClient`, `TextureManager`, `VertexConsumer`, `BlockEntityRendererFactories`, etc.).

This has a consequence that matters more than most tutorials emphasize: **`src/main` cannot even compile a reference to a client-only class.** It is not on that source set's classpath. Importing `net.minecraft.client.texture.TextureManager` into a class under `src/main/java` fails at `./gradlew build` with a compiler error, not a runtime crash on a dedicated server. This is strictly better than the pre-split convention (single source set + `@Environment(EnvType.CLIENT)` annotations + Loom's tiny-remapper environment stripper), where the mistake compiles fine in the IDE and only surfaces as a `NoClassDefFoundError` crash when someone actually runs a dedicated server — which is exactly the failure mode the question is worried about, and which this project's build script already defends against structurally.

**What `@Environment(EnvType.CLIENT)` is still for, given the split:** it's a documentation/tooling annotation, not the enforcement mechanism, for this project. It matters when a single class that *must* physically live in `src/main` (e.g. `TransitDisplayBlock`, because the server needs it) has an individual *method* that only makes sense client-side and must never be called from common code — e.g. Minecraft's own `Block` class annotates a couple of client-hint methods this way even though `Block` itself is a common class. This project has no such case: every genuinely client-only concern is an entire class, and those classes go in `src/client` where the split source set enforces the boundary for free. Don't reach for `@Environment` here; reach for correct source-set placement.

**fabric.mod.json entrypoints:** two objects in `entrypoints`, e.g. `"main": ["transitreport.TransitReport"]` (implements `ModInitializer`, lives in `src/main`) and `"client": ["transitreport.client.TransitReportClient"]` (implements `ClientModInitializer`, lives in `src/client`). Fabric Loader instantiates `main` on both the client and the dedicated server; it instantiates `client` **only** on a physical client, after `main`.

### Component-by-component placement

| Component | Source set | Why |
|---|---|---|
| `TransitDisplayBlock` | `src/main` | A `Block` instance must exist identically on client and dedicated server — world save, block state, placement logic, and the vanilla block registry all live on both sides. |
| `TransitDisplayBlockEntity` | `src/main` | Same reasoning: the dedicated server loads chunks and must be able to construct/tick/save this class even though it never renders it. `BlockEntity` itself is a common class. |
| `TransitConfig` | `src/main` | Pure data (base URL string, refresh-interval int) plus JSON parsing — no Minecraft client types at all. Costs nothing to keep common, and it's the cheapest seam toward a future server-side reader of the same config (see §8). |
| `TransitDisplayRenderer` (`BlockEntityRenderer<TransitDisplayBlockEntity>`) | `src/client` | Implements a client-only interface (`net.minecraft.client.render.block.entity.BlockEntityRenderer`) and touches `MatrixStack`, `VertexConsumerProvider`, `RenderLayer` — none of which exist on the dedicated-server classpath. |
| `TransitTextureManager` | `src/client` | Touches `TextureManager`, `NativeImage`, `NativeImageBackedTexture` — client-only, GPU-adjacent classes. |
| `TransitApiClient` | `src/client` | The JDK's `java.net.http.HttpClient` has zero Minecraft dependency and *could* legally live in `src/main`. Put it in `src/client` anyway for this milestone: nothing server-side drives it (client-fetch-per-client is the explicit design, per PROJECT.md), and colocating it with the scheduler and texture manager keeps the entire fetch→decode→upload pipeline inside one source set with one clear owner. See §8 for how to peel this apart cheaply later without it having been a mistake now. |
| `TransitRefreshScheduler` | `src/client` | Driven by `ClientTickEvents.END_CLIENT_TICK`, itself a client-only Fabric API class. There is no server-side reason for a refresh loop to exist in this milestone. |

**The rule of thumb for this project:** if a class's job is to *cause pixels to appear* or *fetch the bytes that will become those pixels*, it's `src/client`. If a class's job is to *exist so the world model is consistent on every machine running the mod*, it's `src/main`. Nothing in this mod needs to be duplicated across both.

---

## 2. Registration Order and Mechanics (1.20.1, Mojmap)

All registration happens through `net.minecraft.registry.Registries` (the post-1.19.3 static-registry-holder class; the old `Registry.BLOCK` etc. static fields were relocated here and this is what 1.20.1 actually uses — confirmed against Fabric API's own 1.20.x `ItemGroupEvents` javadoc, which types against `RegistryKey<ItemGroup>` resolved via `Registries.ITEM_GROUP`).

### In the `main` entrypoint (`ModInitializer.onInitialize`, `src/main`)

```java
public static final Block TRANSIT_DISPLAY = Registry.register(
    Registries.BLOCK,
    Identifier.of(MOD_ID, "transit_display"),
    new TransitDisplayBlock(AbstractBlock.Settings.create().strength(1.5f).nonOpaque())
);

public static final Item TRANSIT_DISPLAY_ITEM = Registry.register(
    Registries.ITEM,
    Identifier.of(MOD_ID, "transit_display"),
    new BlockItem(TRANSIT_DISPLAY, new Item.Settings())
);

public static final BlockEntityType<TransitDisplayBlockEntity> TRANSIT_DISPLAY_BE = Registry.register(
    Registries.BLOCK_ENTITY_TYPE,
    Identifier.of(MOD_ID, "transit_display"),
    FabricBlockEntityTypeBuilder.create(TransitDisplayBlockEntity::new, TRANSIT_DISPLAY).build()
);

ItemGroupEvents.modifyEntriesEvent(ItemGroups.FUNCTIONAL).register(entries ->
    entries.add(TRANSIT_DISPLAY_ITEM)
);
```

Notes:
- `Identifier.of(...)` is the 1.20.1-appropriate factory; the two-arg `new Identifier(ns, path)` constructor also still works in 1.20.1 (it's deprecated starting a bit later in the 1.20.x line, not in 1.20.1 itself) but `Identifier.of` is the form that ages best.
- `FabricBlockEntityTypeBuilder.create(Factory<? extends T> factory, Block... blocks)` — the `Factory` functional interface signature is `T create(BlockPos pos, BlockState state)`, matching `TransitDisplayBlockEntity`'s constructor. `.build()` with no `Type<?>` argument is correct unless you need a DataFixer type registered (you don't, for a fresh mod with no NBT schema migrations).
- `ItemGroupEvents.modifyEntriesEvent` takes a `RegistryKey<ItemGroup>`. **Confirmed for 1.20.1**: vanilla group keys live on `net.minecraft.item.ItemGroups` (e.g. `ItemGroups.FUNCTIONAL`, `ItemGroups.BUILDING_BLOCKS`). This is post-1.19.3 API shape and is unchanged through 1.20.1; it changes again later (1.20.5+ moves more of item registration to a component-based model) but that does not apply here. If a project wants its own tab instead of piggybacking a vanilla one, register a `RegistryKey<ItemGroup>` plus an `ItemGroup` instance first, then call `modifyEntriesEvent` with that key — not needed for this mod's single item.
- `BlockItem` registration must happen in `main`, not `client` — items exist in the common registry and need to exist on the dedicated server (creative inventory, `/give`, recipes).

### In the `client` entrypoint (`ClientModInitializer.onInitializeClient`, `src/client`)

```java
BlockEntityRendererFactories.register(TransitReport.TRANSIT_DISPLAY_BE, TransitDisplayRenderer::new);
```

`BlockEntityRendererFactories.register(BlockEntityType<T> type, BlockEntityRendererFactory<T> factory)` is the Fabric-preferred call and is stable across the 1.20.x line (it wraps vanilla's own render-dispatcher registration map). It must run in the client entrypoint: the class `BlockEntityRendererFactories` lives in `net.minecraft.client.render.block.entity`, a client-only package, so it is physically unreachable from `src/main` (see §1) — this constraint is enforced by the compiler, not just convention.

**Ordering dependency:** `TRANSIT_DISPLAY_BE` must exist (i.e. `main`'s `onInitialize` must have run) before `client`'s `onInitializeClient` registers a renderer for it. Fabric Loader guarantees this ordering by contract — `main` entrypoints always run before `client` entrypoints on a physical client — so no manual sequencing is needed beyond "don't move the block-entity-type registration into the client entrypoint by mistake."

---

## 3. Block Entity Renderer (1.20.1)

### Interface

```java
public interface BlockEntityRenderer<T extends BlockEntity> {
    void render(T entity, float tickDelta, MatrixStack matrices,
                VertexConsumerProvider vertexConsumers, int light, int overlay);

    default boolean rendersOutsideBoundingBox(T blockEntity) { return false; }
    default int getRenderDistance() { return 64; }
    default boolean isInRenderDistance(T blockEntity, Vec3d cameraPos) { /* default distance check */ }
}
```

Confirmed against Yarn `1.20.1+build.5`. One correction to the question's premise: 1.20.1/Fabric does **not** have a `shouldRenderOffScreen()` method on this interface — that name belongs to Forge's parallel extension (`IForgeBlockEntity`). The Fabric/Mojmap equivalent for "render me even when the game thinks I'm out of view" is `rendersOutsideBoundingBox(T)`, and the visibility/distance controls are `getRenderDistance()` (max distance in blocks before the renderer is skipped — default 64, raise it if the enlarged chart should stay visible from farther away than a normal block) and `isInRenderDistance(T, Vec3d)` (per-instance override if you want asymmetric behavior, rarely needed here).

### `getRenderBoundingBox()` and "bigger than the block"

The vanilla frustum-culling hook is `BlockEntity#getRenderBoundingBox()` (declared on `BlockEntity`, not on the renderer). Its default implementation returns a box derived from the block's own outline shape at its position — i.e., normal block-sized culling. **Because the intended chart is visually larger than a 1×1×1 block**, `TransitDisplayBlockEntity` must override this to return an expanded `Box`, e.g. `new Box(pos).expand(1.0)` (or a tighter expansion sized to the actual quad), otherwise the game will frustum-cull the block entity — and therefore never call `render()` at all — as soon as the camera looks away from the *block's* footprint even though the *chart* is still on screen. This is the single most likely "why is my texture not showing" bug in this design, and it is silent (no error, no log — the renderer method is simply never invoked), so treat overriding `getRenderBoundingBox()` as mandatory the moment the quad is made larger than the block, not optional polish.

### Drawing a textured quad

Inside `render()`:

```java
VertexConsumer buffer = vertexConsumers.getBuffer(RenderLayer.getEntityCutout(TEXTURE_ID));
MatrixStack.Entry entry = matrices.peek();
Matrix4f model = entry.getPositionMatrix();
Matrix3f normal = entry.getNormalMatrix();

buffer.vertex(model, x0, y1, z).color(255, 255, 255, 255).texture(0f, 0f)
      .overlay(overlay).light(light).normal(normal, 0f, 0f, 1f).next();
buffer.vertex(model, x1, y1, z).color(255, 255, 255, 255).texture(1f, 0f)
      .overlay(overlay).light(light).normal(normal, 0f, 0f, 1f).next();
buffer.vertex(model, x1, y0, z).color(255, 255, 255, 255).texture(1f, 1f)
      .overlay(overlay).light(light).normal(normal, 0f, 0f, 1f).next();
buffer.vertex(model, x0, y0, z).color(255, 255, 255, 255).texture(0f, 1f)
      .overlay(overlay).light(light).normal(normal, 0f, 0f, 1f).next();
```

Confirmed against `VertexConsumer` Yarn `1.20.1+build.10`: the chainable methods are `vertex(Matrix4f, float, float, float)`, `color(int,int,int,int)` (0–255 ints) or `color(float,float,float,float)`, `texture(float u, float v)`, `overlay(int)` / `overlay(int u, int v)`, `light(int)` / `light(int u, int v)`, `normal(Matrix3f, float, float, float)`, and a terminal `void next()` that must be called once per vertex after all attributes are set, in the vertex format's declared order (position → color → texture → overlay → light → normal is the order the built-in `RenderLayer`s expect; get this order right or you'll get garbage-looking or invisible geometry rather than an error).

- **Winding:** four vertices per quad, wound counter-clockwise as seen from the visible face (the order above — top-left, top-right, bottom-right, bottom-left — is CCW when viewed from +Z looking toward -Z, i.e. facing the viewer standing in front of the block). Get winding backwards and the quad culls invisible from the intended viewing side (Minecraft's render layers cull backfaces).
- **UV mapping:** straightforward 0,0 / 1,0 / 1,1 / 0,1 corner-to-corner mapping is correct for a single full-image quad; no atlas involved since this is a standalone runtime texture, not a block/item atlas sprite.
- **`light`/`overlay`:** pass through the `light`/`overlay` ints `render()` receives — don't hardcode `0xF000F0` unless you deliberately want full-bright regardless of world lighting (a legitimate choice for a "screen" that should read clearly at night, but a choice worth making explicitly rather than by accident).
- **`RenderLayer` for a runtime `Identifier`:** `RenderLayer.getEntityCutout(Identifier texture)` is the correct call — it works for any `Identifier`, whether or not the identifier resolves to an on-disk resource-pack asset, which is exactly what's needed for a texture registered purely at runtime via `TextureManager.registerTexture` (see §5). `getEntityCutout` gives you alpha-cutout transparency (useful if the chart PNG has transparent regions) with no depth-fighting weirdness; `getEntityTranslucent` is the alternative if the chart needs true alpha blending rather than cutout, at the cost of needing correct draw-order for transparency.

---

## 4. Threading Model — the correctness core

Concretely, per pipeline stage:

| Stage | Thread | API |
|---|---|---|
| Refresh tick originates | **client thread** (the single thread that also renders — Minecraft 1.20.1's client has no separate tick/render threads; "client thread" and what `RenderSystem` calls "the render thread" are the same physical thread) | `ClientTickEvents.END_CLIENT_TICK.register(client -> scheduler.tick())` |
| Scheduler decides "time to refresh," kicks off request | client thread | `TransitRefreshScheduler` calls `TransitApiClient.fetch(...)`, which returns immediately |
| HTTP request in flight | **JDK HTTP-client internal thread pool** | `HttpClient.sendAsync(request, HttpResponse.BodyHandlers.ofByteArray())` — this is genuinely async; nothing on the client thread blocks |
| Response arrives, bytes available | still the HTTP client's background thread (a `CompletableFuture` continuation runs on whatever thread completed the future unless you say otherwise) | `.thenApply(HttpResponse::body)` |
| **PNG decode** | **can and should happen off the client thread**, in the same `CompletableFuture` chain | `NativeImage.read(new ByteArrayInputStream(bytes))` — this is a pure CPU decode (STB-based), touches no GL state, and is safe to run on any thread. This directly answers the question: yes, decode off-thread before upload. |
| **Hand back to the client thread** | transition point | `MinecraftClient.getInstance().execute(() -> textureManager.applyDecoded(image))` |
| **GPU upload** | **must be the client thread** | Inside that `execute()` runnable: `texture.setImage(image)` (CPU-side swap, closes the old `NativeImage`) then `texture.upload()` (the actual glTexImage2D-equivalent call — this is the one that requires an active GL context) |
| Next frame renders | client thread | `TransitDisplayRenderer.render()` reads the now-updated texture via its stable `Identifier` |

**On `RenderSystem.recordRenderCall` / `isOnRenderThread()`:** these exist and are real 1.20.1 APIs (`com.mojang.blaze3d.systems.RenderSystem`), and either one *could* be used instead of `MinecraftClient.getInstance().execute(...)` for the hand-back step — they solve the same problem (get this code onto the thread that owns the GL context) via a slightly different queue. For this project, prefer `MinecraftClient.getInstance().execute(Runnable)`: it's the idiomatic Fabric-tutorial pattern for "run this general client-thread logic later," it works identically whether or not you're mid-frame, and it avoids introducing a second scheduling mechanism (`RenderSystem`'s call queue) for what is, in this single-threaded client, the exact same target thread. Reach for `RenderSystem.recordRenderCall` only if profiling later shows `execute()`'s queue draining too late in the frame for your needs — not expected at a once-a-minute refresh cadence.

**Why this matters concretely for the forbidden mistake:** doing `NativeImage.read(...)` or `texture.upload()` directly inside the `HttpClient.sendAsync(...).thenApply(...)` chain without the `execute()` hop means that code runs on an HTTP-client worker thread. `upload()` calling into GL from a non-GL thread is undefined behavior at best (driver-dependent crash, corrupted texture, or a silent no-op) — this is the exact bug class "no blocking network I/O on the main/render thread" in PROJECT.md is guarding against from the other direction (here the risk isn't blocking the render thread, it's touching GL from the *wrong* thread).

---

## 5. Texture Lifecycle Ownership

**One shared texture, not one per block position — this is correct, and simpler.** PROJECT.md is explicit that the transit endpoint is parametrized by timestamp only, so every placed display shows byte-for-byte the same chart at any given moment. Given that, a per-position texture would mean: N times the GPU memory, N times the HTTP requests per refresh window (unless de-duplicated some other way), and N independent "did this one fail" states to reconcile — all to display N copies of one image. A single process-wide (client singleton) texture avoids all of that: `TransitTextureManager` owns exactly one `NativeImageBackedTexture` instance, registered once under one fixed `Identifier` such as `Identifier.of(MOD_ID, "dynamic/transit_chart")`. Every `TransitDisplayBlockEntity`'s renderer references that same `Identifier`; none of them own a texture individually.

**Registration and update pattern:**
1. At client-init (or lazily on first fetch), register once: `MinecraftClient.getInstance().getTextureManager().registerTexture(TEXTURE_ID, placeholderTexture)` where `placeholderTexture` is a small `NativeImageBackedTexture` (e.g. a 1×1 or "loading" image) — this guarantees the `Identifier` always resolves to *something*, so the renderer never has to special-case "texture not registered yet."
2. On every successful refresh, **do not** re-register under a new identity. Reuse the same `AbstractTexture` object: `existing.setImage(newDecodedImage)` then `existing.upload()`. This means `TextureManager.destroyTexture(Identifier)` is **not** needed on a routine refresh at all — you're mutating the contents of one long-lived GPU texture object, not creating/destroying a new one every 60 seconds. This is the load-bearing design choice that keeps the "unbounded GPU leak" constraint in PROJECT.md trivially satisfied: there is exactly one texture object for the lifetime of the client session, period.
3. `destroyTexture(Identifier)` **is** needed at true teardown: client shutdown (not strictly required since the process is exiting anyway, but good hygiene) and — more relevantly — if the mod ever needs to fully discard and re-register the texture object itself (e.g. recovering from a corrupt state), not on every content refresh.

**Resource-pack reload (F3+T) survival:** a texture registered via `TextureManager.registerTexture(Identifier, AbstractTexture)` under a synthetic identifier that does not correspond to any resource-pack asset path is **not** wired to any `ResourceReloadListener`. F3+T (and `/reload`) only re-run registered reload listeners (block/item atlas stitching, language files, sounds, and any mod-registered `SimpleSynchronousResourceReloadListener`) — nothing walks `TextureManager`'s internal map and evicts arbitrary manually-registered entries just because a reload happened. **Practical implication: the texture survives F3+T untouched, and no reload listener is required for correctness.** (Confidence: MEDIUM — this follows directly from how `TextureManager`/the reload-listener system is documented to work, and matches long-standing community experience with runtime-registered dynamic textures in other Fabric mods, but there is no single 1.20.1-specific sentence in the docs saying "manually registered textures are reload-immune," so treat it as inferred-and-plausible rather than chapter-and-verse. If a future phase wants belt-and-suspenders behavior — e.g. also re-fetching immediately after a reload, in case a player used F3+T to intentionally force a refresh — that's a legitimate reason to add a `SimpleSynchronousResourceReloadListener` later; it is not needed for baseline correctness.)

**World unload / disconnect:** nothing block-entity-specific to clean up, because the texture isn't owned by any block entity — it's a client singleton keyed by mod session, not by world or connection. Leaving it registered across a disconnect is fine and arguably desirable (instant chart display if the player reconnects before the next refresh). If ever concerned about staleness across disconnect, the fix is "trigger a manual refresh on join," not "destroy the texture on disconnect."

**`Identifier` naming convention:** use a namespace/path pair, not a raw string — `Identifier.of(MOD_ID, "dynamic/transit_chart")`. The `dynamic/` path prefix is a convention (not enforced), signaling to anyone reading the code that this identifier does not correspond to a `resources/assets/<mod>/textures/dynamic/transit_chart.png` file on disk, unlike every other texture identifier in the mod.

---

## 6. What Persists in NBT

Given the single-shared-texture design above, walk the state that actually exists:

- The **chart image bytes/texture** are explicitly forbidden from NBT (PROJECT.md) and, per §5, live entirely in a client-side singleton (`TransitTextureManager`) that isn't even reachable from the block entity's class — so there's nothing to persist there in the first place, forbidden or not.
- The **base URL and refresh interval** live in `TransitConfig`, loaded from a config file, not NBT (see §7) — not block-entity state at all.
- **Per-block-entity state**, honestly assessed: there is none needed. Every `TransitDisplayBlockEntity` instance renders the same shared texture; there is no per-position "last successful fetch time," "last image," or "this instance's URL" to remember, because none of that varies by position. `TransitDisplayBlockEntity` does not need to override `writeNbt`/`readNbt` at all — the inherited `BlockEntity` no-op defaults are correct and sufficient. Vanilla-level defaults (position, block-entity type identifier) are all vanilla already persists for every block entity regardless.

**Is a block entity even required, versus a plain block plus a client-side singleton?** Yes, a block entity is required — not for state, but because **a per-position custom-render hook is the entire reason `BlockEntity` + `BlockEntityRenderer` exist as a vanilla mechanism.** A plain `Block` has no per-tick, per-instance rendering callback at all; the only way to draw custom dynamic geometry at a specific placed block's position, every frame, is to attach a `BlockEntityRenderer` to a `BlockEntityType`, which requires a `BlockEntity` class to exist as the render dispatcher's key. There is no lighter-weight vanilla mechanism for "draw something extra at this coordinate" than a block entity — mixing into `WorldRenderer` directly to draw at every placed instance's position without a block entity would be dramatically more invasive and fragile than just using the one built-in extension point designed for exactly this.

**Be honest about the thinness:** `TransitDisplayBlockEntity` in this design is, and should be allowed to be, close to a marker class — `extends BlockEntity`, a constructor calling `super(TRANSIT_DISPLAY_BE, pos, state)`, and the `getRenderBoundingBox()` override from §3. That's not a smell; it's the correct shape given the constraint (identical chart everywhere). What it buys, precisely: (1) a stable per-position anchor for the renderer to attach world-transform math to (`render()` receives the block entity, from which position/orientation-dependent quad placement is derived), and (2) a pre-built, zero-cost extension point if a later milestone *does* need per-position state — e.g. a per-display manual-refresh cooldown timestamp, or (in a hypothetical future with natal-chart support) a per-display parameter — at which point `writeNbt`/`readNbt` overrides slot in without restructuring anything. Don't manufacture NBT fields now to make the class "feel less empty."

---

## 7. Config Loading

**Where in the mod lifecycle:** load `TransitConfig` synchronously, early, in the `main` entrypoint's `onInitialize()`, before block/item/block-entity-type registration reads any config-dependent values (in this design, registration doesn't actually need config values — block/item construction is config-independent — so the ordering constraint is soft, but loading config first is still the conventional and least-surprising place). Because `TransitConfig` is plain JSON parsing with no Minecraft client dependency (§1), this can live in `src/main` and run identically whether the physical side is a client or a dedicated server, even though nothing server-side currently reads it — cheap consistency, no cost.

Concretely: read/write a JSON file under `FabricLoader.getInstance().getConfigDir().resolve("transitreport.json")` using whatever the project's chosen JSON library is (GSON is already a transitive Minecraft dependency, so reach for that rather than adding a config-library dependency — consistent with PROJECT.md's "prefer mechanisms Fabric/Minecraft already provide" constraint). On missing/malformed file, write and use defaults rather than failing mod init.

**Taking effect without a restart:** since `TransitRefreshScheduler` reads `TransitConfig`'s current in-memory values on every scheduling decision (rather than capturing them once at startup into local `final` fields), a changed interval takes effect on the *next* tick-based check, no restart needed — as long as the mutation path is "reload the config object's fields in place" or "swap a volatile reference to a new immutable config object," either of which is safe across the client-thread-only reads happening in the scheduler. The only case needing care: if config reload is triggered from a command or GUI (not currently in scope — no config screen per PROJECT.md's Out of Scope), that trigger must not mutate the config object from a non-client thread while the scheduler is mid-read; keeping all config reads/writes on the client thread (which they naturally are, since nothing here needs a background thread to reload a local file) sidesteps this entirely. A changed base URL takes effect the same way — the next scheduled fetch simply uses the new URL string; no cache or connection pool keyed by URL needs invalidating since `HttpClient` requests are stateless per-call.

---

## 8. Multiplayer-Ready Seams (name them, do not build them)

PROJECT.md is explicit: client-side fetch per client, no server authority, and explicitly forbids over-engineering synchronization now. The seams that keep a future server-authoritative design cheap, without building any of it:

1. **The chart-bytes boundary is already a clean interface shape, even if not formalized as a Java `interface` yet.** `TransitTextureManager` only needs "here are PNG bytes, or here is a decoded `NativeImage`" from whatever produces them — it does not need to know that a `TransitApiClient` produced them via HTTP. If a future milestone wants the server to fetch once and broadcast bytes to clients via a custom payload/packet instead of every client hitting the API independently, only the *producer* side changes (a packet-receive handler calls the same `applyDecoded(...)` entry point `TransitApiClient`'s completion currently calls) — `TransitTextureManager` and `TransitDisplayRenderer` are untouched. **Actionable now, cheaply:** give `TransitTextureManager` one clear public entry point (e.g. `applyDecodedImage(NativeImage)` or `applyPngBytes(byte[])`) that both the current HTTP-completion callback and a hypothetical future packet handler could call, rather than letting `TransitApiClient` reach directly into `TextureManager` internals. This is good separation regardless of multiplayer plans — it's the concrete form of "the renderer never does HTTP, the HTTP client never touches render state" pushed one layer further: the HTTP client shouldn't touch *texture* internals either, only a narrow "here are the new bytes" entry point.
2. **Config is already common-side (§1, §7).** If a server-authoritative design later needs the server to know the same base URL/interval (e.g. to do the fetching itself), `TransitConfig` doesn't need to move — it's already loadable from `src/main`.
3. **`TransitDisplayBlockEntity`'s near-statelessness (§6) is itself a seam, not a gap.** Because no per-position state exists yet, there is nothing to reconcile if a future design needs to add server→client synchronized state (e.g. via `BlockEntity#toInitialChunkDataNbt` / `BlockEntityUpdateS2CPacket`, the vanilla mechanism for syncing block entity NBT to nearby clients) — that hook is a well-known vanilla extension point to reach for *then*, not something to wire up speculatively now.

**Do not** build a network packet, a custom payload type, a `ChartImageSource` interface with multiple implementations, or any server-side fetch logic this milestone — none of it is needed for client-side-only fetch, and PROJECT.md flags premature abstraction here explicitly as a thing to avoid.

---

## 9. Build Order

The author's proposed sequence is sound; below is the same sequence with dependency notes and an explicit flag on which steps are not independently verifiable.

| # | Step | Depends on | Verifiable in isolation? |
|---|---|---|---|
| 1 | Verify toolchain: project builds, dev client launches at the pinned MC/Loom/Fabric-API versions | nothing | **Yes** — this is exactly why PROJECT.md calls it out as a real phase: `./gradlew build` succeeding and `./gradlew runClient` reaching the title screen is a clean, self-contained pass/fail gate, and per PROJECT.md the current `build.gradle` (modern-Loom-generator output: `splitEnvironmentSourceSets()`, `officialMojangMappings()`) paired with `gradle.properties` pinning 1.20.1/Loom `1.17-SNAPSHOT` is an *unverified combination* — do not assume it resolves. |
| 2 | Block + `BlockItem` + `BlockEntityType` registration, plus datagen (models, recipe, loot table, lang) | Step 1 | **Yes** — placing the block in-game and seeing it in the creative inventory/`ItemGroup` is directly observable without any rendering, HTTP, or texture code existing yet. |
| 3 | Static bundled texture rendering — `BlockEntityRenderer` draws a texture shipped as a normal mod asset (a resource-pack-path `Identifier`, not a runtime one) | Step 2 (needs the block entity + renderer registration plumbing from §2/§3) | **Yes** — this isolates "can I draw a textured quad at all, correctly wound, correctly UV'd, correctly culled" from every dynamic-texture and networking concern. This is the right place to nail `getRenderBoundingBox()` and quad geometry before adding runtime texture complexity on top. |
| 4 | Dynamic texture swapping with a **local** image (e.g. read a PNG from disk or mod resources, not the network) into `TransitTextureManager`, verifying swap-without-leak | Step 3 (reuses the renderer, replaces its static `Identifier` with a `TransitTextureManager`-owned one) | **Yes** — this isolates the §4/§5 threading and lifecycle model from HTTP entirely: you can prove `NativeImage.read` → `setImage` → `upload` → re-render works, and that repeated swaps don't leak, using a keypress or command to trigger a swap instead of a timer or network call. |
| 5 | Async HTTP fetch (`TransitApiClient`) against the public "changing image" dummy endpoint, **logged only** — not yet wired to the texture pipeline | Step 1 (only needs the JDK HTTP client + config; does not need the block/renderer at all) | **Yes, and should be built in parallel with steps 2–4**, not strictly after them — `TransitApiClient` has no dependency on block/renderer/texture code. Verify by logging response status/byte-length, independent of anything rendering. |
| 6 | Wire HTTP to texture: `TransitApiClient`'s completion calls into `TransitTextureManager`'s entry point (§8, seam #1) via the `MinecraftClient.execute(...)` hand-back (§4) | Steps 4 and 5 | **Yes** — this is the first step that is actually the join of two previously-independent, previously-verified pieces; if it fails, the fault is almost certainly in the thread hand-back, not in either piece alone, which is exactly why verifying 4 and 5 separately first is worth the extra step rather than skipping to this. |
| 7 | Scheduled refresh (`TransitRefreshScheduler` on `ClientTickEvents.END_CLIENT_TICK`, reading `TransitConfig`'s interval) | Step 6 | **Yes** — observable by watching the public dummy endpoint's image visibly change roughly on the configured cadence. |
| 8 | Reliability: non-fatal failure handling (timeouts, non-200s, malformed bytes → keep last good image, rate-limited logging) | Step 7, **and requires the local mock server**, not the public dummy endpoint | **Partially flagged**: per PROJECT.md, this step's pass/fail criteria genuinely cannot be verified against the public "changing image" URL, because that endpoint can't be made to time out, 500, or return malformed bytes on demand. The local mock server (already called out in PROJECT.md as existing for exactly this reason) must exist and be controllable *before* this step can be considered done, not just attempted. Treat "local mock server can simulate timeout / non-200 / malformed PNG" as a hard prerequisite check inside this step, not an assumption. |
| 9 | Manual refresh on interact (right-click triggers an out-of-band call into the same fetch path used by the scheduler) | Step 6 (reuses the wired fetch→texture path; does not need step 7 or 8 to exist first, though building it after reliability work means the manual path inherits the same failure handling for free) | **Yes** — directly observable: interact, watch for an immediate fetch/log, independent of the timer. |
| 10 | Polish (decorative modeling, visual refinement) | Everything above | **Yes**, but PROJECT.md explicitly defers this until after images update on the block — don't let polish creep earlier than step 6 actually working end-to-end. |

**Net correction to the proposed order:** step 5 (async HTTP) does not need to wait for steps 2–4 (block/renderer/texture) to exist — it has no dependency on them at all, and building it in parallel de-risks step 6 by ensuring both halves are independently proven before their first join point. The rest of the author's sequence is dependency-correct as proposed.

---

## Component Boundaries — Explicit "Must Not Talk To"

| Boundary | Allowed | Forbidden (per PROJECT.md's separation-of-concerns constraint) |
|---|---|---|
| `TransitDisplayRenderer` ↔ `TransitApiClient` | Renderer reads only `TransitTextureManager`'s current texture `Identifier`; never touches `TransitApiClient` | Renderer must never perform or trigger HTTP directly, and must never block waiting on a fetch |
| `TransitApiClient` ↔ render state | `TransitApiClient`'s only render-adjacent action is calling `MinecraftClient.getInstance().execute(...)` to hand decoded bytes to `TransitTextureManager`'s entry point | `TransitApiClient` must never call `TextureManager`, `NativeImage`, or any `RenderSystem`/GL API directly — it hands off data, it doesn't touch textures |
| `TransitRefreshScheduler` ↔ `TransitDisplayBlockEntity` | None needed — the scheduler is a client singleton driving one shared texture; it does not iterate placed block entities at all | Scheduler must not fetch once per placed block entity — that would silently reintroduce N-times-redundant HTTP calls for identical content |
| `TransitDisplayBlockEntity` ↔ `TransitTextureManager` | The renderer (not the block entity) reads the texture manager's `Identifier` at render time | The block entity itself should not hold a reference to `TransitTextureManager` or attempt to own/cache texture state — keep it thin per §6 |
| `TransitConfig` ↔ everything | Read by `main`-side registration (if ever needed) and by `TransitRefreshScheduler`/`TransitApiClient` on the client | `TransitConfig` must not import any client-only class — that's what keeps it legally placeable in `src/main` |

---

## Sources

- Yarn `1.20.1+build.5` — `BlockEntityRenderer` interface: https://maven.fabricmc.net/docs/yarn-1.20.1+build.5/net/minecraft/client/render/block/entity/BlockEntityRenderer.html (HIGH confidence — official mappings javadoc for the exact pinned version)
- Yarn `1.20.1+build.10` — `VertexConsumer`, `RenderLayer`: https://maven.fabricmc.net/docs/yarn-1.20.1+build.10/net/minecraft/client/render/VertexConsumer.html , https://maven.fabricmc.net/docs/yarn-1.20.1+build.10/net/minecraft/client/render/RenderLayer.html (HIGH confidence)
- Yarn `1.20.1+build.10` — `NativeImageBackedTexture`: https://maven.fabricmc.net/docs/yarn-1.20.1+build.10/net/minecraft/client/texture/NativeImageBackedTexture.html (HIGH confidence)
- Fabric API `0.92.x` line — `FabricBlockEntityTypeBuilder` javadoc (fetched from the adjacent 1.20.1-era release docs): https://maven.fabricmc.net/docs/fabric-api-0.92.2+1.20.1/net/fabricmc/fabric/api/object/builder/v1/block/entity/FabricBlockEntityTypeBuilder.html (HIGH confidence)
- Fabric API `ItemGroupEvents` javadoc across 1.20.x releases confirming `RegistryKey<ItemGroup>` signature: https://maven.fabricmc.net/docs/fabric-api-0.83.0+1.20/net/fabricmc/fabric/api/itemgroup/v1/ItemGroupEvents.html (HIGH confidence — signature is stable across the 1.20.x line including 1.20.1)
- Fabric Wiki — Block Entity Renderers tutorial, confirming `BlockEntityRendererFactories.register(type, factory)` call site and client-entrypoint placement: https://wiki.fabricmc.net/tutorial:blockentityrenderers (MEDIUM-HIGH confidence — wiki, not versioned javadoc, but matches the javadoc-confirmed class location)
- Fabric API `ClientTickEvents` javadoc (0.91.1+1.20.1 and neighboring releases) confirming `END_CLIENT_TICK`/`EndTick`: https://maven.fabricmc.net/docs/fabric-api-0.91.1+1.20.1/net/fabricmc/fabric/api/event/client/ClientTickCallback.html (HIGH confidence for the pinned version)
- Fabric Wiki / community notes on resource-reload-listener registration and scope (`ResourceManagerHelper#registerReloadListener`, F3+T behavior): https://wiki.fabricmc.net/tutorial:custom_resources , https://notes.highlysuspect.agency/blog/we_out_here_reloadin/ (MEDIUM confidence — general-mechanism documentation, not a 1.20.1-specific statement about manually-registered textures surviving reload; that conclusion is inferred, as flagged in §5)
- `RenderSystem`/GL-thread model (`RenderSystem.recordRenderCall`, `isOnRenderThread`) and `MinecraftClient.execute` as the standard cross-thread hand-back pattern: cross-checked against general Fabric/Yarn 1.20.1-era API surface (class exists in `com.mojang.blaze3d.systems.RenderSystem` at this version); treated as MEDIUM-HIGH confidence — the API's existence is well-established from the pinned dependency set, though no single fetched source spelled out the full hand-back idiom for this exact version in one place.
- PROJECT.md (`.planning/PROJECT.md`) — authoritative for scope, constraints, and the intended component decomposition/pipeline this research validates against.

---
*Architecture research for: Fabric 1.20.1 mod, remote-image display block*
*Researched: 2026-09-07*

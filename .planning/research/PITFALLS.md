# Pitfalls Research

**Domain:** Minecraft Java Edition mod (Fabric 1.20.1) — dynamic-image display block with async HTTP-fed texture
**Researched:** 2026-09-07
**Confidence:** MEDIUM-HIGH (version-drift and toolchain claims verified against live Fabric/Loom sources and official javadoc this session; rendering/threading mechanics reflect stable, long-unchanged Minecraft client internals cross-checked where possible and flagged where not)

This document assumes the reader is an experienced software engineer, new to Minecraft/Fabric. General software-engineering pitfalls (don't block threads, don't leak resources, validate input) are only included where the **Minecraft-specific mechanism** of the mistake matters — the "what's different here" is the point of every entry.

---

## Critical Pitfalls

### Pitfall 1: Trusting current Fabric docs/tutorials for 1.20.1 APIs

**What goes wrong:**
Current Fabric documentation (docs.fabricmc.net) defaults to the *latest* Minecraft version's tab, and most 2025-2026 tutorials/blog posts/AI training data describe post-1.21 or post-1.20.5 APIs. Code copied from these sources either fails to compile against 1.20.1's actual classes, or compiles against a *different* overload that changes behavior silently.

**Why it happens:**
Fabric's own docs site is versioned per-page but defaults to newest; search results and LLM answers skew toward whatever is currently written about, which is always the newest stable line. 1.20.1 is now several major API generations behind current Fabric.

**Verified concrete cases (this session):**

| API | 1.20.1 (verified) | Newer docs show | Symptom if you use the wrong one |
|---|---|---|---|
| `Identifier` construction | `new Identifier(ns, path)` / `new Identifier("ns:path")` — public constructor | `Identifier.of(ns, path)` — constructor made `protected`, `of()`/`ofVanilla()` are the required entry points starting **1.21** | `Identifier.of` does not exist on 1.20.1 → compile error `cannot find symbol: method of(String,String)` |
| Datagen provider constructors (recipe, block loot table) | `FabricRecipeProvider(FabricDataOutput output)`, `FabricBlockLootTableProvider(FabricDataOutput output)` — **no** registry-lookup parameter | Constructors gained `CompletableFuture<RegistryWrapper.WrapperLookup>` as a second parameter starting **1.20.5/1.20.6** | Passing/expecting the extra `CompletableFuture` param on 1.20.1 → compile error, constructor not applicable; conversely, a 1.20.1-only provider silently can't reference dynamic-registry data the way current tutorials assume |
| Datagen **tag** provider constructors | `FabricTagProvider(FabricDataOutput, RegistryKey<? extends Registry<T>>, CompletableFuture<RegistryWrapper.WrapperLookup>)` — **already** requires the registries future, even on 1.20.1 (tags reference registry keys) | Same shape, so this one *doesn't* drift — the trap is assuming ALL providers changed together in 1.20.5 when tags always needed it and recipes/loot did not | Copying a "just add the future param everywhere" migration guide onto 1.20.1 breaks recipe/loot providers that must NOT take it |
| Item group registration | `FabricItemGroup.builder()` takes **no arguments**; you must define a `RegistryKey<ItemGroup>`, call `Registry.register(Registries.ITEM_GROUP, key, FabricItemGroup.builder().displayName(...).icon(...).entries(...).build())` yourself, and use `ItemGroupEvents.modifyEntriesEvent(key)` to add items | Conceptually similar in 1.20.1 through 1.21.x, but pre-**1.19.3** tutorials (`FabricItemGroupBuilder.create(Identifier)`) are a completely different, removed API | Using the pre-1.19.3 builder API on 1.20.1 → class/method doesn't exist; calling `displayName()` is easy to forget → `NullPointerException`/crash on item group build |
| `BlockEntityRenderer.render(...)` signature | `void render(T entity, float tickDelta, MatrixStack matrices, VertexConsumerProvider vertexConsumers, int light, int overlay)` — the "classic" fixed-function signature | **Unchanged** through 1.21.8-era docs — this one is stable. The real break is the **1.21.6+ render-pipeline overhaul** (deferred rendering, `RenderPipeline`/GPU-abstraction objects replacing raw `RenderLayer.getEntityCutout(Identifier)`-style factories) | Following a 2026-dated tutorial that shows `RenderPipelines.*` or GPU-abstraction texture objects will not compile against 1.20.1's `RenderLayer`/`RenderSystem`, which still use the pre-overhaul immediate-mode-ish API |
| `NativeImageBackedTexture` constructors | `NativeImageBackedTexture(NativeImage image)` and `NativeImageBackedTexture(int width, int height, boolean useStb)` — stable across 1.19–1.21 | No material drift found for this class specifically, but tutorials pair it with drifted `Identifier`/`TextureManager` registration calls | Mixing a correct `NativeImageBackedTexture` call with an `Identifier.of(...)` call from a newer tutorial → compiles fail on the `Identifier` line, misleading you into "fixing" the texture code instead |
| `fabricApi.configureDataGeneration` DSL | For versions **below 1.21.4**: `fabricApi { configureDataGeneration() }` — no `client` property | For **1.21.4+**: `fabricApi { configureDataGeneration { client = true } }` | Per Fabric's own docs, `client = true` is a 1.21.4+ addition. Using it on 1.20.1-era Loom either no-ops or fails at Gradle configuration time with a Groovy `MissingPropertyException`/`MissingMethodException` (`Could not find property 'client'`) — **this exact block appears in this project's current `build.gradle` and must be verified/removed in Phase 1, see Pitfall 2** |

**How to avoid:**
- Treat every current-docs/tutorial snippet as a *hypothesis*, not an answer, for this project.
- Run `./gradlew genSources` once toolchain is verified, then read the **actual decompiled 1.20.1 source** (in Loom's cache / via IDE navigation into the Minecraft jar) for any class you're unsure about — this is ground truth, not documentation.
- Pin javadoc lookups to the exact resolved version: `https://maven.fabricmc.net/docs/yarn-1.20.1+build.<N>/...` and `fabric-api-0.92.x+1.20.1` — never the "latest" alias.
- When an AI assistant (including this one) or tutorial gives you Fabric code, mentally ask "does this compile against 1.20.1, or does it just look right?" — compile errors here are your friend; silent behavior differences (e.g., item group entries not registering) are the dangerous case.

**Warning signs:**
- Compile errors mentioning methods/constructors "cannot be applied to given types" on core Minecraft/Fabric classes.
- A tutorial mentions `RegistryWrapper`, `HolderLookup`, `RecipeExporter`, `Identifier.of`, or `RenderPipeline` — all are signals you're reading 1.20.5+ or 1.21.6+ material.

**Phase to address:** Every phase touching Minecraft/Fabric API surface, but front-load the check in **toolchain verification** and **block/item registration + datagen** since those two phases hit the highest concentration of drifted APIs.

---

### Pitfall 2: The `build.gradle`/`gradle.properties` combination is almost certainly *not* the mismatch it looks like — but one line in it probably is

**What goes wrong:**
On first read, `gradle.properties` pinning `minecraft_version=1.20.1` while `build.gradle` uses the plugin id `net.fabricmc.fabric-loom-remap` at `loom_version=1.17-SNAPSHOT` looks like a "current-generator output pointed at an old version" mismatch. It largely is not. Contrary to the assumption in this project's own PROJECT.md, `net.fabricmc.fabric-loom-remap` is the **correct, current plugin id for obfuscated Minecraft versions** — and 1.20.1 is obfuscated. Fabric Loom split its plugin id in **Loom 1.14** (Dec 2024): `net.fabricmc.fabric-loom` is for the *new* non-obfuscated Minecraft versions (Mojang started shipping official unobfuscated names starting with the version after 1.21.11, i.e. "26.1"), while `net.fabricmc.fabric-loom-remap` remains the plugin for every obfuscated version — **1.21.11 and everything older, including 1.20.1**. This exact `gradle.properties` (`minecraft_version=1.20.1`, `loader_version=0.19.5`, `loom_version=1.17-SNAPSHOT`, `fabric_api_version=0.92.12+1.20.1`) matches, verbatim, the current official `FabricMC/fabric-example-mod` repository's `1.20.1` branch as of this research date. Loom is largely version-independent of the *target* Minecraft version (it downloads mappings/game jars per the configured `minecraft_version`), so a current Loom release building an old target is the normal, supported path — not a mistake.

**What is genuinely a mismatch:** the `fabricApi { configureDataGeneration { client = true } }` block described for this project. Per Fabric's own current documentation, `client = true` is a property added for **1.21.4+**; for anything below that (1.20.1 included), the correct call is bare `configureDataGeneration()`. Whether leaving `client = true` in on 1.20.1-era tooling throws at Gradle-sync time or is silently accepted was not resolved with certainty this session — it must be verified empirically, first thing, in Phase 1.

**Why it happens:** the project was generated from FabricMC's own web-based template generator, which is itself under active development and can inject syntax appropriate to whichever version of its own logic was current when the properties were pinned — a known source of subtle drift even in "official" starting points.

**How to avoid:**
- Do not "fix" the plugin id — `net.fabricmc.fabric-loom-remap` is correct here. Fixing it to plain `net.fabricmc.fabric-loom` would be the actual mistake (that id is for the *unobfuscated* line, which 1.20.1 is not part of).
- As the very first action of the toolchain-verification phase, run `./gradlew build` (or just a Gradle sync) with the file as-is and read the actual failure, if any, before changing anything. If it fails specifically on `configureDataGeneration { client = true }`, remove the `{ client = true }` block and call `configureDataGeneration()` bare — that is the 1.20.1-correct form.
- Because `loom_version=1.17-SNAPSHOT` pins a **SNAPSHOT** build (not a numbered release), the exact bits Gradle resolves can change over time and are not reproducible run-to-run unless Gradle's dependency cache is left untouched. This is a real, separate risk: a clean `--refresh-dependencies` weeks later could pull a different snapshot with different behavior. Prefer pinning to the latest **numbered** Loom release once the SNAPSHOT is confirmed working, or accept and document the reproducibility trade-off.
- SNAPSHOT resolution can also fail outright with `Could not resolve net.fabricmc:fabric-loom:1.17-SNAPSHOT` if Gradle's module metadata caching (`--refresh-dependencies`) or the Fabric snapshot repository is unreachable/misconfigured — if this happens, it's a network/repository issue, not an API-compatibility one.

**Warning signs:**
- Gradle sync failure specifically citing `client` as an unknown property/method inside a `configureDataGeneration` block → confirms the `client = true` mismatch above.
- `Plugin [id: 'net.fabricmc.fabric-loom-remap'] was not found` → wrong Loom version too old to have the split (pre-1.14); bump `loom_version`.
- Dependency resolution failures mentioning `1.17-SNAPSHOT` specifically → snapshot repository/caching issue, not a version-target issue.

**Phase to address:** **toolchain verification** (first phase). Verification is not optional here — confirm with an actual `./gradlew build` before writing any mod code, and record which exact combination worked.

---

### Pitfall 3: Gradle/Java version mismatch between "what runs Gradle" and "what compiles the mod"

**What goes wrong:** Recent Fabric Loom releases (1.14+, which includes the pinned `1.17-SNAPSHOT`) require **Gradle 8.14 or 9.0**, and **Java 21 to run Gradle itself** — while the mod's own compiled bytecode still targets **Java 17** (Minecraft 1.20.1's actual runtime requirement, set via a Java toolchain block in `build.gradle`, e.g. `java { toolchain { languageVersion = JavaLanguageVersion.of(17) } }`). These are two different JDKs doing two different jobs, and conflating them is the single most common IntelliJ setup mistake for this generation of Loom.

**Why it happens:** it is not obvious that "the JVM Gradle runs on" and "the JDK toolchain the mod compiles/runs against" are independent settings; IntelliJ's Gradle import picks whatever JDK is configured as the project SDK by default, which is often the wrong one for one of the two roles.

**How to avoid:**
- Install a JDK 21 for running Gradle/IntelliJ's Gradle integration, and let Gradle's Java toolchain support auto-provision/select JDK 17 for actually compiling and running the mod (`runClient`/`runServer` launch with the toolchain JDK, not necessarily the Gradle JVM).
- In IntelliJ: Settings → Build, Execution, Deployment → Build Tools → Gradle → "Gradle JVM" must be a JDK 21 (or newer, per whatever the pinned Loom version requires) — this is separate from the project's Java language level (17), which IntelliJ picks up from the toolchain block once Gradle sync succeeds.
- Do not manually force a project-wide Java 17 SDK as the Gradle JVM to "match the mod" — that breaks Gradle/Loom itself, not the mod.

**Warning signs:**
- IntelliJ import failure or Gradle daemon startup failure with `Unsupported class file major version 65` (or similar) — classic JVM-version-too-old-for-Gradle symptom.
- Message like "This version of Gradle requires Java 21 or higher to run" during sync.
- Successful sync but `runClient` fails to launch or launches with the wrong bytecode target — check the actual JDK used to compile via `./gradlew --version` output for "JVM" vs the toolchain-selected JDK Loom logs during `compileJava`.

**Phase to address:** **toolchain verification.**

---

### Pitfall 4: `officialMojangMappings()` licensing and IDE quirks

**What goes wrong:** the project uses `loom.officialMojangMappings()` (Mojang mappings, not Yarn). Mojang's mapping license is more restrictive than Yarn's community license — fine for this private, unpublished mod, but worth being deliberate about since it's a real constraint if distribution plans ever change (out of scope here, per PROJECT.md, but worth knowing why the choice matters). Separately, Mojang mappings include full parameter names and are large; first-time resolution downloads and processes them, and IDE indexing after a mapping change (e.g., bumping `minecraft_version`) can be slow and occasionally requires an IntelliJ "Reload All Gradle Projects" plus an invalidate-caches to pick up correctly, especially after switching between Yarn and Mojang mappings mid-project (not the case here, but a known trap if it ever happens).

**How to avoid:** no action needed for a private mod beyond being aware; if this mod is ever open-sourced or redistributed, re-check Mojang's mapping license terms at that time. If IntelliJ shows stale/wrong symbol names after a version bump, do a full Gradle refresh + "Invalidate Caches and Restart" before assuming the build itself is broken.

**Warning signs:** IntelliJ autocomplete/navigation shows obfuscated or Yarn-style names instead of Mojang names after a mapping-related change → stale IDE cache, not a build failure.

**Phase to address:** **toolchain verification** (awareness only; not a blocking issue for this milestone).

---

### Pitfall 5: `gradle.properties`' configuration-cache note, and `runDatagen`/`runClient`/`runClientDatagen` confusion

**What goes wrong:** Gradle's configuration cache (a performance feature) has known incompatibilities with Loom/IntelliJ's project-import model as of this Loom generation — hence the disabling note already present in this project's `gradle.properties`. Separately, there are at least three relevant run configurations Loom can generate for a datagen-enabled project — a plain server-side `runDatagen`, and (once `configureDataGeneration` client support is correctly wired for the target version) a client-inclusive variant. Running the wrong one, or running `runClient` expecting it to also (re)generate data, are both easy mistakes — `runClient` **launches the game**, it does not run datagen; only the datagen-specific run task writes to `src/main/generated`.

**How to avoid:**
- Leave configuration cache disabled as already noted in `gradle.properties` until upgrading past whatever Loom version resolves the IntelliJ incompatibility; don't "fix" this by re-enabling it speculatively.
- After any datagen provider change, run the datagen task explicitly and re-check `src/main/generated` diffs before launching `runClient` — don't assume `runClient` regenerates anything.
- If `configureDataGeneration { client = true }` is confirmed unsupported on this Loom/version combo (Pitfall 2), client-side data generation (e.g., generating client-only resources) may need to be wired manually for 1.20.1 rather than relying on a single unified `runClientDatagen`-style task — verify which run tasks Gradle actually generates via `./gradlew tasks --group=fabric` (or similar) rather than assuming a tutorial's task name exists in this project.

**Warning signs:** `src/main/generated` not updating after a provider change and a `runClient` launch → you ran the wrong task, not a datagen bug.

**Phase to address:** **toolchain verification** (initial setup); **block/item registration + datagen** (ongoing workflow discipline).

---

### Pitfall 6: Calling render-thread-only APIs from an HTTP callback thread

**What goes wrong:** `java.net.http.HttpClient`'s async methods (`sendAsync`) complete their returned `CompletableFuture` on an internal HTTP-client worker thread (or a common `ForkJoinPool` thread), **not** the Minecraft client/render thread. Any code in a `.thenApply`/`.thenAccept` chain attached to that future — decoding bytes into a `NativeImage`, constructing/uploading a `NativeImageBackedTexture`, calling `RenderSystem.*`, or touching `MinecraftClient.getInstance()` state that's render-thread-affine — runs on the wrong thread by default.

**Why it happens:** `CompletableFuture` chaining methods without an explicit `Executor` argument (`thenApply` vs `thenApplyAsync(fn, executor)`) run the continuation on whichever thread completed the future, which for an HTTP client is never the game thread. It's easy to write code that "just works" in a quick manual test (because timing happens to line up, or the crash is silent memory corruption rather than an immediate exception) and then fails intermittently or corrupts rendering state under real conditions.

**Concrete crash/symptom signatures:**
- `RenderSystem` guards several (not all) of its entry points with `RenderSystem.assertOnRenderThread()`, which throws `IllegalStateException: RenderSystem called from wrong thread` when violated — this is the *best case*, because it fails loudly and immediately.
- `NativeImage` pixel operations and GL texture upload calls are **not** uniformly guarded the same way; off-thread misuse can instead manifest as a native-level crash (a JVM `hs_err_pid<N>.log` fatal error, or a segfault inside LWJGL/GL driver code) with no Java stack trace pointing at your mod at all — this is the dangerous case, because it looks like "Minecraft/your GPU driver crashed" rather than "my mod's threading is wrong."
- Silent corruption is also possible: a half-uploaded or torn texture (visible as garbage pixels, flickering, or a texture that "sometimes" shows the wrong image) if two threads touch the same `NativeImage`/GL state concurrently without a crash at all.

**How to avoid:**
- Do all network I/O and PNG **decoding** (`NativeImage.read(bytes)`, which is CPU-only and thread-safe on its own buffer) off the render thread — that part is fine and desirable off-thread.
- Before touching anything render-thread-affine (constructing/registering/uploading a `NativeImageBackedTexture`, calling `RenderSystem`), hop back onto the client thread explicitly: `MinecraftClient.getInstance().execute(() -> { /* texture upload here */ });`. `MinecraftClient.execute(Runnable)` queues the runnable to run on the next client tick on the correct thread — this is the standard, idiomatic hand-off point in Fabric mods.
- Never call `MinecraftClient.getInstance()` and assume the *result* is safe to store/reuse from a background thread for anything beyond reading a plain reference — treat any interaction with its mutable state as thread-affine.
- Structure the pipeline as: **[HTTP thread]** fetch bytes → decode `NativeImage` → **[client.execute hop]** → set/upload texture. Keep the hop as the single well-defined seam in the codebase (e.g., inside `TransitTextureManager`) so the threading contract is enforced in one place, not scattered across call sites.

**Phase to address:** **async HTTP client** (establish the fetch pipeline) and especially **HTTP-to-texture wiring** (this is precisely where the thread hop must be implemented correctly) — treat this as the highest-scrutiny code review point in the whole project.

---

### Pitfall 7: Blocking the client thread/tick loop on the network

**What goes wrong:** calling `.get()` or `.join()` on the HTTP `CompletableFuture` from client-thread code (e.g., inside the block entity's tick method, or inside a render call) blocks that thread until the network call resolves — potentially seconds, or forever on a hung connection with no timeout configured.

**Why it happens:** `.get()`/`.join()` are the simplest way to "just get the result," and in a quick synchronous test against a fast local endpoint it appears to work fine; the failure mode only appears under real latency or an unresponsive server.

**Concrete symptom:** Minecraft's client thread stalls completely — the game freezes, becomes unresponsive to input, and the window may report "Not Responding" to the OS. On a dedicated server, an equivalent mistake on the server thread will eventually trip the **watchdog** (`ServerHangWatchdog` — fires when a single tick exceeds a threshold, default around 60s, producing a full thread-dump crash report) even though this mod's fetch happens client-side per the architecture — the same class of bug would be catastrophic if any similar blocking call were ever made server-side.

**Additional trap — the reverse mistake:** doing PNG *decode* work (not network I/O, but CPU-bound `NativeImage.read()` on a large/complex image) directly inline on the render thread after the hop from Pitfall 6, rather than off-thread before the hop, causes a visible **frame-time stutter** exactly once per refresh cycle (a ~60-second-periodic hitch) — much subtler than a full freeze, easy to miss in casual testing, and easy to misattribute to something else since it's intermittent and short.

**How to avoid:**
- Never call `.get()`/`.join()` from client-thread code. Always use the async callback chain (`.thenApply`, `.thenAccept`, `.exceptionally`) and let results arrive asynchronously.
- Set an explicit request timeout on the `HttpClient`/`HttpRequest` (e.g., `HttpRequest.newBuilder().timeout(Duration.ofSeconds(10))`) so a hung endpoint can't stall the pipeline indefinitely even off-thread — an un-timed-out future that never completes will simply mean the display never updates, silently, forever, which is its own (milder) bug.
- Do decode (`NativeImage.read`) on the background/HTTP-callback thread, and only the final texture upload after the `client.execute()` hop — keep the render-thread portion of the pipeline as small as possible (ideally just `setImage` + `upload()`).

**Phase to address:** **async HTTP client** (timeout configuration), **HTTP-to-texture wiring** (correct placement of decode vs. upload work), **reliability hardening** (defends against slow/hung endpoints specifically).

---

### Pitfall 8: Texture/GPU resource leaks from the 60-second refresh cycle

**What goes wrong:** a texture (and the `NativeImage` backing it) allocated every refresh cycle, forever, without being freed, is an unbounded leak — of either native (off-heap) memory, GPU texture memory, or both, depending on exactly what's leaked.

**The concrete facts, verified against 1.20.1 javadoc this session:**
- `NativeImage` wraps **native, off-heap** memory and implements `AutoCloseable`; it is *not* freed by ordinary Java garbage collection in any prompt/reliable way — an un-closed `NativeImage` leaks native memory that doesn't show up in a normal Java heap profiler, making the leak easy to miss until the process's overall memory footprint (visible in Task Manager, not JVM heap stats) climbs.
- `NativeImageBackedTexture` constructors are `NativeImageBackedTexture(NativeImage image)` and `NativeImageBackedTexture(int width, int height, boolean useStb)`; it implements `AutoCloseable` and has `getImage()`, `setImage(NativeImage)`, `upload()`, and `close()`. **It takes ownership of the `NativeImage` you construct it with or later `setImage()` onto it** — its `close()` is expected to close that owned image. This is standard, well-established Minecraft client behavior (consistent across many versions), though the specific implementation detail was not re-confirmed from the current 1.20.1 decompiled source in this session — verify it directly via `genSources` before relying on it, since getting ownership wrong here is exactly the double-free/leak trap below.
- **Double-free risk:** if you manually `close()` a `NativeImage` that a `NativeImageBackedTexture` already owns (e.g., closing the image you *just* handed to `setImage()`, or closing both the texture and its image separately at cleanup time), you may double-close the same native resource. Depending on the internal implementation this either no-ops harmlessly (pointer nulled after first free) or is undefined behavior — don't rely on either outcome. **Rule: each `NativeImage` gets closed exactly once, by exactly one piece of code, and once ownership passes to a `NativeImageBackedTexture` (via constructor or `setImage`), that texture is the one responsible for closing it — not you.**
- `TextureManager.registerTexture(Identifier id, AbstractTexture texture)` stores the texture in an internal `Map<Identifier, AbstractTexture>`; `TextureManager.destroyTexture(Identifier id)` removes and closes it. `TextureManager.registerDynamicTexture(String prefix, NativeImageBackedTexture texture)` is a convenience that **generates a fresh `Identifier` each call** (from the prefix plus an internal counter) and registers it — calling this every 60 seconds therefore produces a *new* map entry, and a *new* GL texture object, every cycle. Whether re-registering at the *same* `Identifier` via plain `registerTexture` automatically destroys whatever was previously there at that id was not confirmed from javadoc alone this session (javadoc doesn't include method bodies) — this is exactly the kind of behavior to verify directly against decompiled 1.20.1 source rather than assume, since getting it wrong either way (assuming auto-cleanup that doesn't happen, or manually double-destroying) causes a bug.

**Which pattern is correct — reuse vs. fresh Identifier every cycle:**
Reuse a single `NativeImageBackedTexture` registered once at a single fixed `Identifier` for the block's entire lifetime. On each refresh: decode the new PNG into a new `NativeImage`, explicitly close the *previous* `NativeImage` you were holding (obtained via `getImage()` before replacing it, or simply tracked alongside the texture), call `setImage(newImage)`, then `upload()` on the render thread. This reuses the same GL texture object across the mod's lifetime (no new `glGenTexture`/`glDeleteTexture` churn every minute) and only ever allocates/frees the `NativeImage` pixel buffer itself each cycle — the minimum possible allocation. **Do not** call `registerDynamicTexture` (or otherwise mint a fresh `Identifier`) on every refresh — that pattern requires you to manually track and `destroyTexture()` the *previous* identifier every single cycle to avoid leaking, is strictly more error-prone, and churns GL objects for no benefit.

**Resource-pack reload (F3+T):** F3+T triggers a client resource reload through Minecraft's `ResourceReloader`/`ResourceManager` pipeline, which affects textures tied to that pipeline (block/item atlases, resource-pack-sourced textures registered as reload listeners). A texture registered manually at runtime via `TextureManager.registerTexture`/`registerDynamicTexture` — as this mod's texture will be — is **not** part of that reload pipeline and should survive F3+T untouched, since it's just an entry in `TextureManager`'s map, independent of resource-pack state. This is standard, well-established Minecraft client behavior; it was not re-verified against source this session and is worth a five-second empirical check in the dev client (press F3+T while the chart is displayed and confirm it doesn't vanish or throw) rather than taken purely on faith.

**Cleanup on world unload / disconnect / client shutdown:** `TextureManager` is a **client-level singleton** (`MinecraftClient.getInstance().getTextureManager()`), not scoped to the current world/server connection — it is not automatically cleared just because the player disconnects or the world unloads. If the block entity (or its renderer) registers a texture and the player disconnects, rejoins, or the block is broken/re-placed, without explicit cleanup the old texture's GPU memory is never freed for the lifetime of the client process. Tie texture lifecycle explicitly to the block entity's own lifecycle: destroy/close the texture when the block entity is removed (`BlockEntity.markRemoved()` override, or the block entity's own teardown hook), and consider whether `ClientPlayConnectionEvents.DISCONNECT` (Fabric API) should also trigger cleanup for any textures not tied to a specific still-loaded block entity. Full process shutdown does clean everything up (OS reclaims all memory on exit) — the leak only matters for long-running sessions with repeated block break/place or disconnect/reconnect cycles, which is exactly the private-long-running-server scenario this project targets.

**Warning signs:**
- Task Manager / OS-level process memory climbing steadily over a session with no corresponding JVM heap growth (classic native/off-heap leak signature).
- GPU memory usage (visible via `F3` debug overlay's GL info, or an external GPU monitor) climbing in lockstep with refresh cycles.
- Any exception or native crash log correlated with block break/place or reconnect cycles, suggesting a double-free.

**Phase to address:** **dynamic texture swapping** (establish the reuse pattern correctly from the start — this is much harder to retrofit than to build correctly the first time) and **reliability hardening** (verify no leak under sustained refresh-cycle soak testing).

---

### Pitfall 9: Block entity renderer — invisible or black quads

**What goes wrong (several related failure modes, all producing "nothing renders" or "renders black"):**

1. **Wrong vertex winding order → invisible from the expected side.** Most `RenderLayer` entity/block-entity layers keep GL back-face culling enabled; a quad's four vertices must be emitted in the winding order (typically counter-clockwise as viewed from the visible side) that layer expects, or the quad is culled and invisible from the front while being visible from directly behind the block — a very common first-BER bug, and the most likely explanation if "the code runs with no errors but nothing appears."
2. **Missing/wrong `light` or `overlay` value → renders solid black.** Minecraft applies lightmap-based vertex darkening; if the `light` value passed into each vertex is `0` (e.g., forgetting to forward the `light` parameter the renderer's own `render(...)` method received, and hardcoding/defaulting to 0 instead), the quad samples the darkest point of the lightmap and appears fully black regardless of the texture's actual pixel content. The `overlay` parameter should normally be a "no overlay" constant (`OverlayTexture.DEFAULT_UV` in 1.20.1) — passing an arbitrary or wrong value can tint the quad unexpectedly (e.g., the white "hurt flash" tint).
3. **Forgetting `matrices.push()`/`matrices.pop()`, or unbalancing them on an early-return path.** Every `render()` call must push the matrix stack on entry and pop it before every return path — including an early return like "no image decoded yet, render nothing." Missing the pop on even one code path corrupts the shared transform stack for every subsequently rendered block entity/entity that frame, producing visual corruption that appears to be somewhere else entirely (mis-rotated/mis-positioned unrelated entities), which is a notoriously confusing bug to trace back to this renderer.
4. **Default render-distance culling of an oversized quad.** `BlockEntity.getRenderBoundingBox()` defaults to a box matching just the block's own 1×1×1 space. Minecraft only calls a block entity renderer's `render()` at all if that bounding box intersects the camera frustum. Since this project's explicit design draws the chart *larger than the block it sits on*, the true visible extent of the quad can still be on-screen while the block's own tiny default bounding box has already left the frustum — the symptom is the chart visibly popping out of existence at certain camera angles well before it should, purely because the (too-small) culling box, not the actual quad, left view. **Fix:** override `getRenderBoundingBox()` to return a box sized to the actual maximum rendered extent, not the block's own space.
5. **`getRenderDistance()` default hides it from far away.** `BlockEntityRenderer` exposes a render-distance cutoff (with a built-in default); a display meant to be legible from across a room or outdoors at distance may need this overridden to a larger value than default — weighed against the minor performance cost of keeping a farther-away renderer active every frame it's in range.
6. **Z-fighting when the quad sits flush with the block face.** A quad drawn at exactly the same plane as the block's own face geometry (e.g., both at local `y = 1.0`) causes flickering as the GPU can't consistently resolve draw order between two coplanar surfaces. Offset the quad a small amount (a fraction of a block, e.g. 0.005) outward from the face via the matrix transform before emitting vertices — small enough to be visually imperceptible, large enough to resolve the depth ambiguity.
7. **Wrong `RenderLayer` choice.** `RenderLayer.getEntityCutout(Identifier)` (hard alpha cutoff, respects normal depth/culling — good default for a mostly-opaque PNG), `RenderLayer.getEntityTranslucent(Identifier)` (alpha-blended, needed only if the chart has genuine partial transparency; translucent geometry doesn't write depth the same way and has its own sorting quirks with other translucent draws), and cutout/cutout-style **no-cull** variants (double-sided, sidesteps the winding-order pitfall entirely at a small performance cost) are the relevant choices. For this project's flat, likely-opaque chart image on a single block face, starting with a no-cull cutout-style layer is the most forgiving choice while getting the renderer working, only moving to translucent if the chart art genuinely needs alpha blending.

**How to avoid:** build the renderer incrementally — first get *any* solid-color quad visible and correctly lit/positioned (verifies winding, light, overlay, push/pop, and layer choice), *then* swap in the dynamic texture, *then* verify the oversized-quad bounding-box override with the camera deliberately positioned so the block's own hitbox is just off-screen.

**Phase to address:** **static texture rendering** (this phase exists specifically to shake out every item in this list against a known-good, unchanging test texture, before dynamic texture swapping adds a second axis of complexity).

---

### Pitfall 10: Minecraft's tick loop turns "poll every request" into a self-inflicted DoS

**What goes wrong:**
- **Firing a request every tick instead of on an interval.** A block entity's ticker runs 20 times per second. Any HTTP call placed directly and unconditionally inside that ticker fires 20 requests/second per placed block, not once per configured interval — an easy mistake if the interval check itself is buggy or the "start a fetch" call is placed above rather than inside the interval gate.
- **Overlapping requests when a slow request outlives the interval.** If a fetch takes longer than the refresh interval (a slow or hanging endpoint) and there's no in-flight guard, the next scheduled tick fires a second, overlapping request before the first resolves — with no cap, this compounds indefinitely against a persistently slow endpoint.
- **Log spam from a persistently failing endpoint.** Logging every failed attempt at the same volume as a working request (especially with full stack traces) against an endpoint that's down for hours produces log-file growth proportional to (86400 seconds / interval) — noisy enough to bury genuinely important log lines, though at a 60-second interval this is a much smaller problem than a per-tick mistake would make it.
- **Unbounded retry/backoff.** Adding a secondary, faster retry loop on top of the normal refresh cycle (rather than letting the fixed interval itself be the retry cadence) risks hammering a struggling endpoint harder while it's already struggling.
- **Swallowed `CompletableFuture` exceptions.** A `CompletableFuture` chain with no `.exceptionally()`/`.handle()`/`.whenComplete()` silently discards any exception thrown inside a `.thenApply`/`.thenAccept` stage — the fetch just appears to "do nothing" on failure, with zero log output and no visible symptom at all other than the display never updating. This is the single easiest way to make the reliability requirements *look* satisfied in casual testing (nothing crashes!) while actually providing no failure visibility whatsoever.
- **Replacing a good image with a blank/error texture on a transient failure.** The explicit requirement is "last successful image stays on screen." A common naive implementation instead eagerly swaps in a placeholder/error texture the moment any single request fails, which visibly breaks the display on a single dropped packet or transient timeout — the fix is to only ever update the *displayed* texture on a successful decode, and treat failures as purely a logging/counting concern that leaves the current texture alone.

**How to avoid:**
- Gate the fetch trigger on an explicit elapsed-time check (e.g., comparing `world.getTime()` or `System.currentTimeMillis()` against a stored "last fetch started" timestamp), not on tick count or an assumption about tick rate.
- Track in-flight state explicitly (e.g., a reference to the current pending `CompletableFuture`, or a simple flag) and skip starting a new fetch if the previous one hasn't completed — let the *next* interval after the flag clears pick up the retry, rather than compounding overlapping requests.
- Configure an explicit request timeout (see Pitfall 7) so "in-flight forever" can't happen from a hung connection specifically.
- Log failures at a level and frequency that stays useful over hours of downtime — e.g., log the first failure clearly, and either suppress repeats of the *same* failure type or downgrade them, rather than full-volume repeated stack traces every cycle. At a 60-second interval this is a smaller problem than at tick-rate, but still worth being deliberate about.
- Rely on the normal scheduled-refresh cadence as the retry mechanism — resist adding a second, independent retry/backoff system unless a real need for faster recovery emerges.
- Always attach `.exceptionally(...)` (or `.handle(...)`/`.whenComplete(...)`) to every `CompletableFuture` chain that can fail, and always log inside it — treat a naked `.thenAccept` with no error handler as a code-review red flag every time.
- Only assign the fetched image to the block entity's "currently displayed" texture reference *after* a full, successful decode — never eagerly clear or replace it on request start or on failure.

**Phase to address:** **scheduled refresh** (interval gating, in-flight guard), **reliability hardening** (timeout, backoff-avoidance, log discipline, exception-swallowing audit, last-good-image behavior under the mock server's deliberately-broken responses).

---

### Pitfall 11: Data generation for a block whose visuals are entirely custom-rendered

**What goes wrong:** it's tempting to assume that because the block's actual chart image is drawn entirely by a custom `BlockEntityRenderer`, no model/blockstate JSON is needed at all. This is false, and skipping it produces the classic magenta-and-black checkerboard "missing texture" appearance — in **both** the inventory icon and, depending on exactly what's missing, the in-world block itself (for its base geometry, hitbox-adjacent rendering, and break particles) — even though the BER is correctly drawing the dynamic image on top.

**What is actually required, specifically for 1.20.1 datagen:**
- A **blockstate JSON** mapping the block's (likely single, if there's no meaningful state variation) blockstate to *some* base model — commonly a plain model (e.g., a simple cube using a placeholder texture, or even the game's built-in "empty"/transparent handling if truly nothing should render outside the BER — but a real model, not an absence of one, is required either way for the game to have *any* baked model to associate with the block).
- An **item model JSON** for the corresponding `BlockItem`, since the BER does not render the inventory/hand icon — that's a separate code path driven entirely by the item's model. Without it, the item shows the missing-texture icon in the inventory/hotbar/hand even if the in-world block renders perfectly via the BER.
- Both are produced via Fabric's datagen model generators (`BlockStateModelGenerator`/`ItemModelGenerator` helper methods, e.g. simple-cube or parented-item-model helpers) registered through a `FabricModelProvider` subclass, added via `pack.addProvider(...)` in the datagen entrypoint — not hand-written JSON, per this project's stated preference for datagen-produced static resources.
- The base model's texture can be a simple placeholder (it may rarely or never actually be visible if the BER's quad fully covers the block face from all realistic angles) but it must exist and be valid, or model-baking itself fails/falls back to the missing-texture model.

**Loot table:** the block must be given an explicit "drops itself" loot table via `FabricBlockLootTableProvider`/`addDrop(block)` (1.20.1 constructor: `FabricBlockLootTableProvider(FabricDataOutput output)`, no registries-future parameter needed at this version). **This is easy to miss during development** because testing typically happens in creative mode, where broken blocks never drop items via the loot table system regardless of whether one exists — the missing-loot-table bug is invisible until someone breaks the block in **survival** mode and gets nothing.

**Recipe provider:** 1.20.1's `FabricRecipeProvider` constructor takes only `FabricDataOutput` (no registries future, unlike 1.20.5+); verify the exact abstract generation method name/shape (`generate(Consumer<RecipeJsonProvider>)` in the 1.20.1 line vs. the `RecipeExporter`-based shape introduced later) against the actual resolved fabric-api sources rather than a tutorial, since this is exactly the kind of provider-shape detail that shifted across versions.

**Translations:** use `FabricLanguageProvider` (1.20.1 constructor also just `FabricDataOutput`), calling `translationBuilder.add(block, "...")`/`add(item, "...")` inside `generateTranslations` for the block and item display names — easy to forget entirely, producing a raw translation-key string (e.g. `block.transitreport.transit_display`) shown in the UI instead of a human-readable name.

**The `src/main/generated` registration trap:** running the datagen task writes output into `src/main/generated` (the directory Loom's `configureDataGeneration` DSL is responsible for wiring into the main source set's resources automatically). If datagen is ever configured manually/older-style rather than through the current DSL (e.g., following an outdated pre-DSL tutorial), that wiring must be done by hand (`sourceSets.main.resources.srcDir 'src/main/generated'` or equivalent) or the generated JSON files never make it into the mod's resources/classpath at all — a build that compiles fine but still shows every missing-texture/missing-loot-table symptom above, because the files exist on disk but aren't actually part of the mod.

**How to avoid:**
- Write the model/item-model/loot-table/recipe/lang providers as part of the same phase that registers the block and item — do not defer "just the JSON stuff" to later, since an unbaked/missing model is a **build-breaking-looking** symptom (visually) that's easy to mistake for a rendering bug in the BER phase if the two are conflated.
- Explicitly test breaking the block in **survival** mode at least once, specifically to catch the loot-table gap that creative-mode testing structurally cannot reveal.
- Confirm the `configureDataGeneration` DSL (once correctly configured per Pitfall 2) is actually wiring `src/main/generated` into the build — don't assume it, check that generated JSON files are present in the built/dev-run resources.

**Phase to address:** **block/item registration + datagen** for the model/loot/recipe/lang providers and the source-set wiring; **static texture rendering** as the phase where the missing-model symptom would otherwise be misdiagnosed as a BER bug if the datagen work were skipped or incomplete.

---

### Pitfall 12: Config lifecycle mistakes

**What goes wrong:**
- **Reading config before it's loaded.** If any code path (particularly in the client entrypoint, which under `splitEnvironmentSourceSets()` may run its own `onInitializeClient()` independent of the common `onInitialize()`) reads a config value before the config has actually been loaded/parsed from disk, it gets a default/uninitialized value silently, or a `NullPointerException` if the config holder itself hasn't been constructed yet. Load configuration once, early, in a single well-defined place (the common entrypoint, before anything else touches it), and have every other access — including the client entrypoint — go through that already-populated holder rather than each doing its own load.
- **Wrong config directory.** The correct location is `FabricLoader.getInstance().getConfigDir()` (the installation's `config/` directory) — not a path relative to the working directory or the mod's own jar location, both of which happen to "work" in a dev environment (where the working directory is predictable) but break the moment the mod is actually installed into a real Minecraft instance with a different working directory.
- **Config changes not taking effect until restart, silently.** If the refresh interval or base URL is read once into a `final` field at block-entity-construction time (or cached anywhere) rather than re-read from the live config object at the point of use (each refresh decision), a user who edits the config file and expects the next refresh to pick it up will instead see no change until a full game restart — with nothing in the mod's behavior communicating that a restart is required. Read config values fresh at each point of use (or make the config holder a mutable singleton updated in place) rather than snapshotting them into per-instance state.
- **Malformed URL crashing initialization.** If config loading eagerly constructs a `URI`/`URL` from the configured base-URL string and lets a `URISyntaxException`/`MalformedURLException` propagate uncaught out of `onInitialize()`, a simple typo in the config file can crash the entire game to the crash screen before the player ever places a block or joins a world — validate and catch at load time, falling back to a safe disabled state (with a clear log message) rather than letting a config-format error become a mod-loading crash.

**Phase to address:** **async HTTP client** (config drives the URL/interval it uses) and **reliability hardening** (live-reload behavior, malformed-input validation) — but the load-order/location basics belong wherever config is first introduced, likely alongside the HTTP client work.

---

### Pitfall 13: Security/abuse surface of a user-configurable base URL

**What goes wrong, even for a private, friends-only mod:**
- **SSRF-adjacent risk via a shared/templated config.** Each client fetches independently using its own network access — there's no server relaying one user's request on another's behalf, so this isn't classic multi-tenant SSRF. But if the config file is ever distributed/templated among the friend group (e.g., bundled with a shared resource pack or modpack config), anyone able to edit that shared file could redirect every friend's client to an arbitrary URL, including internal/LAN addresses (a router's admin page, another device on the home network) purely by having Minecraft issue a GET there.
- **Redirect-following amplifies the risk.** If the `HttpClient` is configured with `Redirect.ALWAYS` (or left at a permissive default), a compromised or malicious endpoint could 302-redirect the client to an internal address the operator never configured directly. Prefer `HttpClient.Redirect.NORMAL` (does not follow an HTTPS→HTTP downgrade) or disable redirect-following entirely for this narrow, single-purpose client, and validate the URL scheme is `http`/`https` only at config-load time.
- **Unbounded response size.** `HttpResponse.BodyHandlers.ofByteArray()` reads the entire response body into memory with no built-in cap. A broken or hostile endpoint returning an unexpectedly huge body (a misconfigured server, an infinite/very large stream, or a deliberately oversized response) can drive unbounded memory growth on the client. Check `Content-Length` where present and reject/abort oversized responses before fully buffering them, and enforce a hard maximum byte cap (e.g., a low-single-digit number of megabytes is generous for a chart PNG) regardless.
- **Content-type validation.** The API contract promises `Content-Type: image/png`; the client should check this header (and ideally the PNG magic-byte signature `89 50 4E 47 0D 0A 1A 0A`) before attempting to decode. Skipping this means an unexpected response — e.g., an HTML error page returned with a `200` status by a misbehaving reverse proxy — goes straight into image decoding and produces a confusing low-level decode failure instead of a clear, actionable "unexpected content-type" log line.
- **Decode bombs.** `NativeImage.read(bytes)` allocates memory proportional to the *dimensions the PNG header claims*, not the file's byte size — a tiny but malformed/malicious PNG advertising extreme dimensions can trigger an attempted multi-gigabyte allocation from a few-kilobyte file, risking an `OutOfMemoryError` that can crash or badly stall the client. Sanity-check decoded (or, if feasible, header-declared) image dimensions against a reasonable maximum before/around the decode call, and wrap decode in a try/catch broad enough to catch `OutOfMemoryError` as well as ordinary decode exceptions, so one bad payload can't take down the whole client.
- **No credentials in the distributed mod.** This project's own scope already excludes shipping API secrets in the mod — worth reinforcing why: a compiled mod jar is trivially decompilable by anyone who has it (any friend, or anyone who obtains a copy), so any credential embedded in source or `fabric.mod.json` should be treated as fully public the moment it's compiled in. If auth is ever added later, it belongs in the user's local, gitignored config file — never in source.

**Phase to address:** **async HTTP client** (redirect policy, size cap, content-type check, scheme validation) and **reliability hardening** (decode-bomb guarding, OOM containment) — worth deciding these defaults deliberately during initial HTTP client construction rather than retrofitting them once the "happy path" already works.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|------------------|
| Skip the request-timeout config on the `HttpClient` during early dev against the fast local mock server | Slightly less setup code | A hung real-world endpoint later blocks the fetch pipeline indefinitely with no visible symptom other than "the display just stopped updating" | Never past the async HTTP client phase — set it from the start, it costs nothing against a fast mock either |
| Register a fresh dynamic texture (`registerDynamicTexture`) every refresh instead of reusing one texture + `setImage`/`upload` | Simpler first implementation, fewer lifecycle-tracking concerns to think about | Slow, compounding GL object churn and a leak unless every prior identifier is manually tracked and destroyed each cycle | Only acceptable as a disposable first spike to prove the render pipeline works end-to-end — must be replaced before the dynamic texture swapping phase is considered done |
| Log full stack traces on every failed fetch at ERROR level | Maximum diagnostic detail | Log spam that buries real signal during any extended endpoint outage | Acceptable during initial mock-server-driven reliability testing, where outages are short and deliberate; not acceptable as the shipped behavior |
| Hardcode the chart-endpoint path/params instead of making the HTTP layer generic over "a chart endpoint" | Faster initial implementation | Directly contradicts the stated constraint that adding a second chart endpoint later shouldn't require restructuring | Acceptable only if the endpoint shape is still actively changing (per PROJECT.md, the API contract "may still shift") — revisit as soon as the contract stabilizes |
| Cache config values into `final` fields on the block entity at construction time | Simpler code, no live-object indirection | Config edits silently require a full restart to take effect, with no indication to the user that this is expected | Never — the cost of reading live config at point-of-use is negligible |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|-----------------|-------------------|
| `java.net.http.HttpClient` async fetch | Chaining `.thenApply`/`.thenAccept` with no executor and assuming continuations run on a "safe" thread | Treat every continuation as running on an arbitrary background thread by default; explicitly hop to the client thread via `MinecraftClient.getInstance().execute(...)` before touching render state |
| PNG bytes → `NativeImage` | Assuming `Content-Type: image/png` guarantees valid, well-formed image bytes | Validate content-type and magic bytes, decode inside a broad try/catch (including `OutOfMemoryError`), and sanity-check decoded dimensions before use |
| `TextureManager` runtime registration | Assuming a resource-pack reload (F3+T) or world disconnect automatically cleans up manually-registered textures | Manually tie texture lifecycle to block entity removal / connection lifecycle events; don't rely on Minecraft's resource-pack or world-session lifecycle to do it for you |
| Fabric datagen provider registration | Copying a post-1.20.5 tutorial's constructor shape (with the registries-future parameter) onto every provider type uniformly | Check each 1.20.1 provider's actual constructor individually — tag providers need the registries future even on 1.20.1, recipe/loot providers do not |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Per-tick HTTP trigger instead of interval-gated | Visible network flood in any packet monitor; server-side rate limiting/blocking if this were ever server-relayed; battery/bandwidth waste | Gate fetch start on an explicit elapsed-time check, not tick count | Immediately, at 20x the intended request rate, from the very first placed block |
| Minting a fresh GL texture object every refresh cycle | Gradual GPU memory growth; potential driver-level allocation stutter every cycle | Reuse one texture + `setImage`/`upload` | Becomes visible after enough refresh cycles accumulate (roughly proportional to session length ÷ 60s), worse with multiple placed blocks each doing it |
| Decoding PNG bytes inline on the render thread after the client-thread hop | A short, periodic (once per refresh interval) frame stutter | Do decode work before the hop, on the background/callback thread; keep the render-thread portion to `setImage`+`upload` only | Noticeable roughly whenever decode cost exceeds a frame budget — worse for larger images or slower client hardware |
| No response size cap on the HTTP body read | Unbounded memory growth against a broken/hostile endpoint | Enforce `Content-Length` checks and a hard byte cap before/while buffering | Immediately, the first time the configured endpoint (or a misconfigured mock) returns something unexpectedly large |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Following HTTP redirects unconditionally | A malicious/compromised configured endpoint can redirect the client to an internal/LAN address it wasn't explicitly pointed at | Use `HttpClient.Redirect.NORMAL` or disable redirects for this client; validate the configured URL's scheme is `http`/`https` |
| No content-type/magic-byte validation before decode | Non-image responses (error pages, misconfigured proxies) reach the image decoder, producing confusing failures instead of clear diagnostics | Check `Content-Type` header and PNG magic bytes before calling `NativeImage.read` |
| No dimension sanity check on decoded images | A malformed/malicious PNG advertising extreme dimensions can trigger a decode-bomb `OutOfMemoryError` | Cap accepted width×height before/around decode; catch `OutOfMemoryError` around the decode call |
| Embedding any future API credential in mod source or `fabric.mod.json` | Trivially recoverable by decompiling the distributed jar | Keep credentials, if ever needed, only in the user's local gitignored config file |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|------------------|
| Swapping the displayed image to a blank/error placeholder on any transient fetch failure | The display visibly "breaks" on a single dropped request even though the API is mostly fine | Only update the displayed texture on a fully successful decode; leave the last-good image in place on any failure |
| No feedback on manual refresh interaction | Player interacts with the block expecting an immediate update and can't tell whether anything happened, especially if the new image looks identical to the old one | Consider a lightweight, non-intrusive acknowledgement (e.g., a log line, or if ever revisited, a subtle in-world cue) so a manual refresh doesn't feel like a no-op |
| Config changes silently requiring a restart | User edits the interval or URL, waits a full cycle, sees no change, and reasonably concludes the config system is broken | Read config live at point-of-use (see Pitfall 12) so edits take effect on the very next refresh cycle |

## "Looks Done But Isn't" Checklist

- [ ] **Block placement and rendering:** Often missing a valid blockstate/item model even though the in-world BER visual looks complete — verify the inventory icon isn't a missing-texture checkerboard.
- [ ] **Loot table:** Often verified only in creative mode, where a missing "drops itself" loot table is invisible — verify by breaking the block in survival.
- [ ] **Error handling "looks" complete because nothing crashes:** Often the actual bug is a silently swallowed `CompletableFuture` exception — verify by pointing the config at the deliberately-broken local mock server and confirming a log line actually appears for a timeout, a non-200, and malformed image bytes, each independently.
- [ ] **Texture cleanup "looks" fine in a short test session:** Often only checked over a few refresh cycles — verify with an extended soak test (repeated refreshes over an hour+, plus repeated block break/place and disconnect/reconnect) while watching OS-level (not just JVM heap) memory.
- [ ] **The oversized quad "looks" fine from the initial test camera angle:** Often only checked from directly in front — verify from an angle where the block's own 1×1×1 hitbox is at or near the edge of the view frustum, to catch the bounding-box culling pitfall.
- [ ] **Config "looks" live because it was tested by restarting the game every time:** Often nobody explicitly tested editing config *without* restarting — verify a config edit takes effect on the next scheduled/manual refresh with the game left running.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|-----------------|
| Wrong plugin id / Loom version chosen based on a misdiagnosed "toolchain mismatch" | LOW | Revert to the verified-working combination (`net.fabricmc.fabric-loom-remap` + a working `loom_version`); re-run `./gradlew build` before making further changes |
| `configureDataGeneration { client = true }` breaking the 1.20.1 build | LOW | Remove the `{ client = true }` block, call `configureDataGeneration()` bare, re-sync |
| Texture-lifecycle leak discovered late (after dynamic swapping is already built around fresh-identifier-per-cycle) | MEDIUM | Refactor to the single-fixed-texture + `setImage`/`upload` pattern; add explicit teardown on block entity removal; soak-test again before considering it fixed |
| Discovering swallowed exceptions are hiding all fetch failures | LOW | Add `.exceptionally`/`.whenComplete` to every existing `CompletableFuture` chain; re-run the reliability test matrix against the mock server to confirm failures are now visible |
| Missing loot table discovered after significant survival-mode play has already occurred | LOW | Add the `addDrop` call, regenerate datagen output, no world-state migration needed since nothing depended on the missing drop |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|---------------|
| Version-drift APIs (Identifier, item groups, datagen constructors, render-pipeline overhaul awareness) | Toolchain verification; block/item registration + datagen | Code compiles against resolved 1.20.1 sources; spot-check against decompiled (`genSources`) source, not tutorials |
| `fabric-loom-remap` / `client = true` datagen DSL mismatch | Toolchain verification | `./gradlew build` succeeds cleanly with the as-pinned versions before any mod code is written |
| Gradle JVM vs. mod-toolchain JDK confusion | Toolchain verification | IntelliJ Gradle sync succeeds; `runClient` launches and compiles against Java 17 bytecode |
| Render/HTTP thread violations | Async HTTP client; HTTP-to-texture wiring | Manual test: trigger a fetch, confirm no `IllegalStateException`/native crash, confirm texture updates correctly and repeatedly |
| Blocking `.get()`/`.join()` on client thread | Async HTTP client; HTTP-to-texture wiring | Manual test against the mock server's deliberately slow/hanging endpoint; game must remain responsive throughout |
| Texture/GPU leaks | Dynamic texture swapping; reliability hardening | Extended soak test (repeated cycles, repeated block break/place, disconnect/reconnect) with OS-level memory monitoring |
| Invisible/black/culled BER quads | Static texture rendering | Visual test from multiple camera angles including one where the block's own hitbox nears the frustum edge |
| Tick-loop network abuse (per-tick fetch, overlapping requests, log spam, swallowed exceptions, blank-on-failure) | Scheduled refresh; reliability hardening | Mock server test matrix: timeout, non-200, malformed bytes — each must leave the last-good image on screen and produce exactly one clear log line, not zero and not a flood |
| Missing model/loot table/lang for a BER-only block | Block/item registration + datagen | Inventory icon is not missing-texture; survival-mode block break yields the item; display name is not a raw translation key |
| Config lifecycle (load order, directory, live-reload, malformed URL) | Async HTTP client; reliability hardening | Edit config without restarting and confirm the next refresh picks it up; feed a malformed URL and confirm graceful degradation, not a crash |
| SSRF-adjacent/redirect/size/content-type/decode-bomb risks | Async HTTP client; reliability hardening | Point the mock server at an oversized response, a non-image content-type, and a malformed PNG; confirm each is rejected cleanly with no OOM and no crash |

## Sources

- FabricMC/fabric-example-mod, `1.20.1` branch — `build.gradle` and `gradle.properties` (direct fetch, this session; confirms the exact plugin id/version combination is the current official template output)
- Fabric Loom GitHub releases — plugin-id split introduced in Loom 1.14 (Dec 2024); Gradle 8.14/9.0 and Java 21 requirement for that generation of Loom
- Fabric documentation (docs.fabricmc.net) — `configureDataGeneration`/`client` property version gate (1.21.4+); Loom options and Fabric API DSL pages
- maven.fabricmc.net Yarn javadoc — `Identifier` (1.20.1+build.5/8 vs. 1.21+ constructor visibility change), `BlockEntityRenderer` (1.20.1+build.5/8 render signature), `TextureManager` (1.20.1+build.8 method list), `NativeImageBackedTexture` (1.20.1+build.8 constructors/methods), `RenderLayer` (entity layer factory methods)
- maven.fabricmc.net fabric-api javadoc — `FabricRecipeProvider` (0.92.5+1.20.1: `FabricDataOutput`-only constructor), `FabricTagProvider` (0.85.0+1.20.1: constructor including `CompletableFuture<RegistryWrapper.WrapperLookup>`), `FabricBlockLootTableProvider` (0.80.3+1.20/0.82.0+1.20: `FabricDataOutput`-only constructor), `FabricDataGenerator.Pack` (`addProvider` `Factory`/`RegistryDependentFactory` overloads)
- Fabric wiki/community discussion — item group registration changes across 1.19.3 and 1.20.1; datagen provider constructor changes at 1.20.5/1.20.6 (registries-future parameter addition)
- General Minecraft/Fabric modding community knowledge (block entity rendering mechanics — vertex winding/culling, lightmap/overlay behavior, matrix stack discipline, render-distance/bounding-box culling, z-fighting, `NativeImage`/`NativeImageBackedTexture` ownership conventions, `TextureManager` runtime-registration vs. resource-pack-reload independence) — stable, long-standing Minecraft client internals not independently re-verified against 1.20.1 decompiled source this session; flagged inline wherever confidence is MEDIUM rather than HIGH, with the explicit recommendation to confirm against `genSources` output before depending on the more implementation-detail-level claims (texture/image ownership on `close()`, `registerTexture` overwrite-cleanup behavior)

---
*Pitfalls research for: Minecraft Fabric 1.20.1 dynamic-image display block mod*
*Researched: 2026-09-07*

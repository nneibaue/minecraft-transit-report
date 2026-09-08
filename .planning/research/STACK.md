# Stack Research

**Domain:** Minecraft Java Edition Fabric mod — dynamic remote-image display on a block, Minecraft 1.20.1
**Researched:** 2026-09-07
**Confidence:** HIGH overall (toolchain and rendering/mapping findings verified against this repo's actual cached Minecraft jars and a real local Gradle build; config/testing/mock-server findings are standard-practice recommendations at MEDIUM-HIGH confidence)

**Verification method note:** Where a finding says "verified locally," it means I ran `./gradlew build` in this exact repository and/or extracted classes from the actual Minecraft 1.20.1 jar (official Mojang mappings) already cached at `.gradle/loom-cache/minecraftMaven/` and inspected them with `javap`. This is stronger evidence than a web source — it is the actual artifact this project compiles against — so those findings are flagged HIGH regardless of the generic source-hierarchy tier.

---

## 0. Headline Finding — The Toolchain Discrepancy Is Not a Bug

**Verdict: `build.gradle` and `gradle.properties` as they exist in the repo right now build successfully, with zero changes required.** I ran `./gradlew build` in this repo and got `BUILD SUCCESSFUL in 21s`, producing `compileJava`, `compileClientJava`, `remapJar`, `remapSourcesJar` etc. I also confirmed `./gradlew tasks` lists a working `runDatagen` task wired up by the existing `fabricApi { configureDataGeneration { client = true } }` block.

Why this looks alarming but isn't: **Fabric Loom is a single continuously-developed tool that targets many past Minecraft versions from its current version** — you do not pin an old Loom release to build an old Minecraft version, the way you might pin an old compiler. I fetched the live `1.20` branch of the official `FabricMC/fabric-example-mod` template repository today, and it uses the exact same shape as this repo: `net.fabricmc.fabric-loom-remap` plugin id, `loom_version=1.17-SNAPSHOT`, `splitEnvironmentSourceSets()`, `mappings loom.officialMojangMappings()`. Current Loom, old Minecraft version, is literally what the Fabric team's own generator currently produces. Treat "toolchain verification" as **done**, not as a phase that needs rework — spend that budget elsewhere.

The two things actually worth doing in a first phase are cheap sanity checks, not toolchain surgery:
1. Confirm the dev machine's Gradle JVM is JDK 17 or newer (see §1.3) — separate from the Java 17 the *mod* targets.
2. Run `./gradlew runClient` once to confirm the dev client actually launches (I verified the build compiles and packages; I did not launch the full game client, since that opens a window and isn't meaningful to check from a research pass).

---

## 1. Gradle / Loom Toolchain

### 1.1 Plugin id: `net.fabricmc.fabric-loom-remap` — correct, not a typo

Confidence: **HIGH** (verified via GitHub release notes + local build)

Fabric Loom 1.14 (published December 4, 2024) split the single `fabric-loom` plugin id into two:

| Plugin id | Applies to | Notes |
|---|---|---|
| `net.fabricmc.fabric-loom-remap` | "Obfuscated" Minecraft versions — **everything up to and including 1.21.11** | This is what 1.20.1 needs. Confirmed correct for this project. |
| `net.fabricmc.fabric-loom` | "Non-obfuscated" Minecraft versions — the newer date-based releases (26.1 and later) | Not applicable to this project. Do not use. |
| `fabric-loom` (no `net.fabricmc.` prefix) | Legacy id, kept only for backward compatibility with existing obfuscated-version projects | Still works for 1.20.1 but there's no reason to prefer it over the explicit `-remap` id in a new project. |

Straight from the Loom 1.14 release notes (FabricMC/fabric-loom, GitHub): *"New plugin IDs: `net.fabricmc.fabric-loom` to be used for non-obfuscated versions, `net.fabricmc.fabric-loom-remap` to be used for obfuscated versions of Minecraft... We expect [1.21.11] to be the last obfuscated version."* 1.20.1 is obfuscated, so `-remap` is unambiguously correct.

**Do not** downgrade to an old plugin id or an old 1.20.1-era Loom version (the `1.3-SNAPSHOT` / `1.4-SNAPSHOT` line the question raised as a possibility). Those are stale suggestions from 2023-era tutorials that predate this plugin-id split. Doing so would be a regression, not a fix — you'd be trading a working, current, actively-maintained toolchain for an abandoned one, for no benefit.

### 1.2 `loom_version=1.17-SNAPSHOT` — resolves, is current

Confidence: **HIGH** (verified via maven-metadata.xml on maven.fabricmc.net + local build)

`1.17-SNAPSHOT` is a real, currently-published floating version on `https://maven.fabricmc.net/`. It resolved during my local build to `1.17.20`. Fabric's snapshot versions on their own Maven are long-lived rolling pointers (not ephemeral like typical `-SNAPSHOT` artifacts on other repos) — this is the normal, intended way Fabric projects consume Loom, and `settings.gradle` in this repo already has `maven.fabricmc.net` declared under `pluginManagement { repositories { ... } }`, so plugin resolution needs no changes.

### 1.3 Java version split: build-time JDK vs. mod's target bytecode

Confidence: **MEDIUM** (web-sourced, not independently re-verified against a second JDK in this environment — this environment already had a compatible JDK, so the build succeeding here doesn't isolate the minimum version)

This is the one genuinely non-obvious toolchain fact worth flagging: **the JDK that runs Gradle/Loom and the Java version the mod compiles to are two different numbers**, and current Fabric documentation's "1.20.1 needs Java 17" advice conflates them.

- The **mod itself** must target Java 17 bytecode, because that's what Minecraft 1.20.1 ships and requires at runtime. The repo's `options.release = 17` and `sourceCompatibility/targetCompatibility = VERSION_17` are correct and must stay as-is.
- The **Gradle daemon that builds it** needs a newer JDK than that. Loom 1.14+ requires Gradle 9.2+, and Gradle 9.x requires JDK 17+ to run its daemon at minimum, with some reports indicating current Loom (1.17.x) is tested primarily against JDK 21 build environments. In practice: make sure IntelliJ's "Gradle JVM" setting (or `org.gradle.java.home` / a `JAVA_HOME` pointing at it) is JDK 17 or newer — JDK 21 is the safe choice if you have it, since that's what the current official template's own compile target implies the Fabric team builds with.
- This project's environment had JDK 26 available and the build succeeded, so JDK 17-26 all work for running Gradle here; I did not test the floor.

Action for the roadmap: don't assume "install JDK 17 and you're done." If IntelliJ complains about the Gradle JVM, point it at whatever modern JDK is installed (17+); leave the project's own `sourceCompatibility`/`targetCompatibility`/`options.release` at 17 untouched.

### 1.4 `fabricApi { configureDataGeneration { client = true } }` — current, correct, already working

Confidence: **HIGH** (verified via official Fabric docs source + local `./gradlew tasks` showing a working `runDatagen` task)

This DSL block is provided by Loom itself (not by Fabric API's jar), and is unrelated to which Minecraft version you target — it's a build-tool feature, not a game-version feature. Per the official docs (`develop/loom/fabric-api.md` in FabricMC/fabric-docs):

```gradle
fabricApi {
  configureDataGeneration {
    // outputDirectory, defaults to src/main/generated
    // createRunConfiguration, defaults to true
    // createSourceSet, defaults to false
    // modId — required if createSourceSet = true
    // strictValidation, defaults to false
    // addToResources, defaults to true
    client = true   // compile and run datagen together with the client
  }
}
```

This is the **only** correct way to wire up datagen for this project. The older pattern the question mentions — manually declaring a `loom { runs { datagen { ... } } }` run config with a `fabric-api-datagen` entrypoint by hand — predates this DSL and would be strictly more code for the same result. **Do not hand-roll it.** The repo's `fabric.mod.json` already declares the datagen entrypoint correctly:

```json
"entrypoints": { "fabric-datagen": ["transitreport.client.JollyalchemyTransitReportDataGenerator"] }
```

and `./gradlew tasks` on this exact repo lists `runDatagen - Starts the 'datagen' run configuration`, confirming the wiring is live.

### 1.5 Known-good pairing (this repo's current values — no changes needed)

```properties
# gradle.properties — already correct, do not change
minecraft_version=1.20.1
loader_version=0.19.5
loom_version=1.17-SNAPSHOT
fabric_api_version=0.92.12+1.20.1
```

```gradle
// build.gradle — already correct, do not change
plugins {
    id 'net.fabricmc.fabric-loom-remap' version "${loom_version}"
    id 'maven-publish'
}

loom {
    splitEnvironmentSourceSets()
    mods {
        "jollyalchemy-transit-report" {
            sourceSet sourceSets.main
            sourceSet sourceSets.client
        }
    }
}

fabricApi {
    configureDataGeneration {
        client = true
    }
}

dependencies {
    minecraft "com.mojang:minecraft:${project.minecraft_version}"
    mappings loom.officialMojangMappings()
    modImplementation "net.fabricmc:fabric-loader:${project.loader_version}"
    modImplementation "net.fabricmc.fabric-api:fabric-api:${project.fabric_api_version}"
}

tasks.withType(JavaCompile).configureEach {
    it.options.release = 17
}

java {
    withSourcesJar()
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
```

`settings.gradle`'s `pluginManagement` block already includes `maven.fabricmc.net`, Maven Central, and the Gradle Plugin Portal — that's everything the above needs.

---

## 2. Mappings — Mojang Official vs. Yarn, for the Types This Project Touches

Confidence: **HIGH** for every row extracted directly from the cached 1.20.1 official-mappings jar via `javap` (marked "verified"); **MEDIUM-HIGH** for a few extremely stable, universally-documented names not re-verified this session (marked "known").

The project uses `loom.officialMojangMappings()` (Mojmap), but essentially all Fabric tutorials, StackOverflow answers, and Discord help you'll find use **Yarn**. These two mapping sets agree on some names and disagree sharply on others — the disagreements are exactly where copy-pasted tutorial code will fail to compile. Below is the translation table for every class this project's rendering pipeline needs.

| Concept | Mojang official (what you actually write) | Yarn (what tutorials show) | Note |
|---|---|---|---|
| PNG decode → in-memory image | `com.mojang.blaze3d.platform.NativeImage` | `net.minecraft.client.texture.NativeImage` | **Same class name**, different package. Verified: `NativeImage.read(byte[])`, `NativeImage.read(InputStream)`, `NativeImage.read(ByteBuffer)` all exist. |
| GPU texture wrapping a `NativeImage` | `net.minecraft.client.renderer.texture.DynamicTexture` | `net.minecraft.client.texture.NativeImageBackedTexture` | **Different names for the same class** — this is the #1 trap. Verified constructor: `DynamicTexture(NativeImage)`. Also has `DynamicTexture(int width, int height, boolean useMipmaps)`, `getPixels()`, `setPixels(NativeImage)`, `close()`. |
| Base texture type | `net.minecraft.client.renderer.texture.AbstractTexture` | `net.minecraft.client.texture.AbstractTexture` | Same simple name, different package. |
| Registers/looks up/frees textures by id | `net.minecraft.client.renderer.texture.TextureManager` | `net.minecraft.client.texture.TextureManager` | Same simple name, different package. Verified methods: `register(ResourceLocation, AbstractTexture)`, `getTexture(ResourceLocation)`, `release(ResourceLocation)`. |
| "Register this texture under this id" | `TextureManager.register(ResourceLocation, AbstractTexture)` | `TextureManager.registerTexture(Identifier, AbstractTexture)` | Method name differs: `register` vs `registerTexture`. |
| "Free this texture, stop it consuming a GPU slot" | `TextureManager.release(ResourceLocation)` | `TextureManager.destroyTexture(Identifier)` | Method name differs: `release` vs `destroyTexture`. **This is the call the resource-lifecycle constraint in PROJECT.md is about** — call it every time you replace a chart texture. |
| Resource/texture id type | `net.minecraft.resources.ResourceLocation` | `net.minecraft.util.Identifier` | Different name entirely, used everywhere as the "id" parameter type. |
| Vertex-format / blend-state pipeline for drawing a quad | `net.minecraft.client.renderer.RenderType` | `net.minecraft.client.render.RenderLayer` | **The #2 trap.** Different name entirely. Verified factory methods: `RenderType.entityCutout(ResourceLocation)` = Yarn `RenderLayer.getEntityCutout(Identifier)`; `RenderType.text(ResourceLocation)` = Yarn `RenderLayer.getText(Identifier)`. |
| **Danger:** a class Mojang itself calls "RenderLayer" | `net.minecraft.client.renderer.entity.layers.RenderLayer` | `net.minecraft.client.render.entity.feature.FeatureRenderer` | This is a *completely different, unrelated* class (entity armor/glow overlay layers), verified present in the jar at that exact path. If you search Mojmap source for "RenderLayer" expecting the render-pipeline type, you will find this one instead and get confusing, wrong results. Always use `RenderType` for pipeline/blend-state — never search for "RenderLayer" in Mojmap code. |
| Block entity renderer interface | `net.minecraft.client.renderer.blockentity.BlockEntityRenderer<T extends BlockEntity>` | `net.minecraft.client.render.block.entity.BlockEntityRenderer<T>` | Same simple name. Verified signature: `void render(T, float tickDelta, PoseStack, MultiBufferSource, int packedLight, int packedOverlay)`. |
| Block entity renderer factory | `net.minecraft.client.renderer.blockentity.BlockEntityRendererProvider<T>` (nested `.Context`) | `net.minecraft.client.render.block.entity.BlockEntityRendererFactory<T>` (nested `.Context`) | Different name (`Provider` vs `Factory`). Verified: `create(BlockEntityRendererProvider.Context)`. |
| Matrix/transform stack passed to renderers | `com.mojang.blaze3d.vertex.PoseStack` | `net.minecraft.client.util.math.MatrixStack` | Different name entirely. Verified class exists at the Mojmap path. |
| Vertex buffer allocator passed to renderers | `net.minecraft.client.renderer.MultiBufferSource` | `net.minecraft.client.render.VertexConsumerProvider` | Different name entirely. Verified class exists at the Mojmap path. |
| Client singleton | `net.minecraft.client.Minecraft` | `net.minecraft.client.MinecraftClient` | Different name, same role. Verified `static Minecraft getInstance()`. |
| "Run this on the main client thread" | `Minecraft.getInstance().execute(Runnable)` (inherited from `net.minecraft.util.thread.BlockableEventLoop`) | `MinecraftClient.getInstance().execute(Runnable)` (inherited from `net.minecraft.util.thread.MessageListener`/equivalent) | Same method name, both inherited from an event-loop base class. Verified `execute(Runnable)` exists on `BlockableEventLoop` in the common jar. **This is how you get back from an async HTTP callback thread to a thread that's allowed to touch texture/render state.** |
| Block entity base class | `net.minecraft.world.level.block.entity.BlockEntity` | `net.minecraft.block.entity.BlockEntity` | Same simple name, different package. |

**Practical guidance for the author:** when you read a Yarn-named tutorial (which will be nearly all of them), the reliable translation strategy is: (1) check this table first for the exact substitution, (2) if not here, search inside the already-downloaded, already-remapped official-mappings jar at `.gradle/loom-cache/minecraftMaven/**/minecraft-{clientOnly,common}-*.jar` with `jar tf` / `javap` — that jar **is** the ground truth for this exact project, not any tutorial. IntelliJ with the project imported will also just show you the real (Mojmap) method/class names via autocomplete once the Loom sync has run once, which is the fastest way to cross-check any tutorial snippet in practice.

---

## 3. HTTP Client

Confidence: **HIGH** for API existence/shape (JDK-guaranteed); **MEDIUM** for the classloader-safety claim (well-established but not independently stress-tested in this pass)

**Recommendation: `java.net.http.HttpClient` (JDK 17 built-in). Do not add OkHttp or Apache HttpClient.**

Rationale, directly against the project's stated constraint ("prefer mechanisms Fabric/Minecraft already provide; a third-party library needs an explicit justification"):

- `java.net.http` has been a standard, non-incubating JDK module since Java 11. Minecraft 1.20.1 requires Java 17 at runtime, so it is *guaranteed* present on every machine that can run this mod at all — no version negotiation, no shading, no relocating.
- Fabric mods run their own classes through Fabric Loader's "Knot" classloader for mixin/transform purposes, but **JDK platform classes (`java.*`, including `java.net.http.*`) are always resolved via the platform/bootstrap classloader**, not Knot. There is no known interaction between Fabric's classloading and `java.net.http`; it is ordinary JDK API usage from the mod's perspective, no different from using `java.util.concurrent` or `java.io`. I found no credible reports of Fabric-specific breakage with `HttpClient` — the tool exists precisely because it needs zero extra ceremony.
- OkHttp or Apache HttpClient would add a real dependency (with its own transitive deps, potential Log4j/SLF4J binding conflicts against Minecraft's already-present logging stack, and a `modImplementation`/shading decision) to solve a problem the JDK already solves. There is no capability this project needs (retries, connection pooling, HTTP/2, timeouts) that `HttpClient` lacks for a single simple `GET` returning bytes.

Usage shape for this project:

```java
private static final HttpClient CLIENT = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(5))
    .executor(Executors.newVirtualThreadPerTaskExecutor()) // or a small fixed pool — see note below
    .build();

HttpRequest request = HttpRequest.newBuilder(uri)
    .timeout(Duration.ofSeconds(10))   // per-request timeout, separate from connect timeout
    .GET()
    .build();

CLIENT.sendAsync(request, HttpResponse.BodyHandlers.ofByteArray())
    .thenApply(HttpResponse::body)
    .whenComplete((bytes, error) -> {
        // this callback runs on the HttpClient's executor thread — NOT the main/render thread.
        // hop back with Minecraft.getInstance().execute(() -> { ... }) before touching texture/render state.
    });
```

Key points to get right, tied directly to PROJECT.md's threading constraint:

- **Connect timeout** is set on the `HttpClient` itself (`.connectTimeout(Duration)`), applies to establishing the TCP/TLS connection.
- **Request timeout** is set per-request (`HttpRequest.Builder.timeout(Duration)`), covers the whole request/response including the connect phase — this is the one that actually bounds "the API is unreachable, don't hang forever," and is the one to test against the mock server's deliberate-timeout mode.
- **Executor**: if you don't set one, `HttpClient` defaults to an internal cached thread pool derived from `ForkJoinPool.commonPool()`. That's fine functionally but means your callback runs on a thread pool shared with the rest of the JVM (including, in principle, Minecraft's own use of the common pool for other things) — supplying your own small dedicated executor (a single-thread or 2-thread fixed pool) makes behavior easier to reason about and keeps a runaway/slow API call from starving unrelated common-pool work. Do not use `Runnable::run` (synchronous) as the executor — that would make `sendAsync` block the calling thread, defeating the point.
- **Never build the `HttpClient` on the main thread per-request.** Build one `HttpClient` once (e.g., a field on `TransitApiClient`) and reuse it — construction has non-trivial overhead and per-request instances defeat any connection reuse.
- Every callback (`.whenComplete`, `.thenApply` continuation, etc.) must marshal back to the main thread via `Minecraft.getInstance().execute(...)` before it touches `TextureManager`, `NativeImage`, or any render state. This is the actual mechanism that satisfies "no blocking network I/O on the main/render thread" *and* "completion must hand back to the correct Minecraft thread" from PROJECT.md's constraints — `HttpClient`'s async API only solves the first half; the `execute()` hop is what you write yourself for the second half.

---

## 4. Image Decoding and Texture Types (1.20.1, Official Mappings)

Confidence: **HIGH** — every signature below is copied from `javap` output against the actual jar this project compiles against.

```java
// 1. Decode PNG bytes fetched from the network
NativeImage image = NativeImage.read(byte[] pngBytes);
// com.mojang.blaze3d.platform.NativeImage
// throws IOException on malformed bytes -- this is your test target for "malformed image bytes" from the mock server

// 2. Wrap it as a GPU-backable texture
DynamicTexture texture = new DynamicTexture(image);
// net.minecraft.client.renderer.texture.DynamicTexture
// (Yarn name for this exact class: NativeImageBackedTexture)

// 3. Register it under a runtime Identifier so it can be referenced by RenderType/RenderSystem
ResourceLocation id = ResourceLocation.tryBuild("jollyalchemy-transit-report", "dynamic/chart_" + counter);
Minecraft.getInstance().getTextureManager().register(id, texture);
// TextureManager.register(ResourceLocation, AbstractTexture) — DynamicTexture extends AbstractTexture

// 4. Get a RenderType for drawing a textured quad against that id
RenderType renderType = RenderType.entityCutout(id);
// or RenderType.text(id) if you want to draw in a resource-pack-friendly quad-batching layer;
// entityCutout is the closer match for "opaque image on a surface" use cases like this one

// 5. When refreshing (swap in a new image), free the OLD texture explicitly
Minecraft.getInstance().getTextureManager().release(oldId);
// TextureManager.release(ResourceLocation) -- THIS is the GPU-leak-prevention call from PROJECT.md's
// resource-lifecycle constraint. Skipping this on every refresh cycle is the single most likely way
// to violate "a texture allocated every 60 seconds and never freed is an unbounded GPU leak."
```

Notes and version-drift flags:

- **`NativeImage.read(byte[])` exists exactly as named in 1.20.1.** There is no need to go through `InputStream` or `ByteBuffer` unless convenient — all three overloads exist, use whichever fits how the HTTP body arrives (`HttpResponse.BodyHandlers.ofByteArray()` pairs naturally with `read(byte[])`).
- **Do not reuse a single `Identifier`/`ResourceLocation` across refreshes without releasing first**, or reuse a fresh one per refresh and release the previous one — either strategy works, but the release call must happen. There's no automatic garbage collection of GPU texture handles tied to Java object lifetime; `AbstractTexture` implements `AutoCloseable` but nothing calls `close()` for you unless you call `TextureManager.release(...)` (which internally closes and forgets the registration) or `close()` directly plus manually deregistering — prefer `release()`, it does both.
- **`RenderLayer.getEntityCutout(Identifier)` from tutorials is `RenderType.entityCutout(ResourceLocation)` here** — same role, different class/method name, see §2. Anything from a post-1.20.1 tutorial calling this on a class literally named `RenderLayer` in Mojmap will not compile — that Mojmap class is unrelated (see the "danger" row in §2).
- **Datagen is unrelated to any of the above.** Datagen (block/item models, loot tables, recipes, language files) is a build-time step producing static JSON, wired via the `fabricApi { configureDataGeneration }` block from §1.4. It has no interaction with the runtime texture pipeline — don't be tempted to route dynamic image data through it (PROJECT.md already calls this out explicitly as a category error, and I'll say why for anyone reading the roadmap: datagen output is written to `src/main/generated` at build time and shipped in the jar; it structurally cannot represent bytes that don't exist until a runtime HTTP call succeeds).
- **What changed after 1.20.1, so you don't go looking for it or copy it by mistake:** newer Minecraft versions (1.21+) moved much of the render pipeline toward a `RenderPipeline`/`GpuTexture` abstraction with different registration flow, and later versions also changed how blaze3d/`NativeImage` interacts with the newer rendering backend work. None of that exists in 1.20.1. If a tutorial mentions `RenderPipeline`, `GpuTexture`, or texture registration through a "Sprite"/atlas-first API for a *non-atlas, standalone runtime texture* — that's not 1.20.1, skip it.

---

## 5. Config Library

Confidence: **HIGH** for the recommendation given this project's stated constraints (this is a judgment call informed by the project's own explicit anti-abstraction/anti-dependency constraints, not a factual claim needing external verification)

**Recommendation: hand-rolled Gson serialization to a POJO, read/written via `FabricLoader.getInstance().getConfigDir()`. Do not add Cloth Config, owo-lib, or midnightlib.**

The config surface here is exactly two values — API base URL and refresh interval seconds — with **no in-game GUI required** (PROJECT.md explicitly scopes out any config screen; the one GUI candidate it discusses is birth-data input, which is out of scope entirely, and there's no other stated need for a screen). That changes the calculus completely from "what config library do most Fabric mods use":

| Option | Verdict | Why |
|---|---|---|
| **Hand-rolled Gson + `FabricLoader.getConfigDir()`** | **Use this** | Gson is already on the classpath (Minecraft itself depends on it; no new dependency at all). `FabricLoader.getInstance().getConfigDir()` returns a `java.nio.file.Path` to the standard per-instance config folder — read a small record/POJO on mod init, fall back to defaults and write the file if it's missing or fails to parse, done. This is ~30 lines of code, matches the project's explicit "avoid premature abstraction and speculative extension points" constraint, and needs zero new Gradle dependencies. |
| Cloth Config | Don't use | Built specifically to *draw config screens* (usually surfaced through Mod Menu). This project has no config screen requirement — Cloth Config would import a whole GUI-building API to serialize two fields. Real dependency (own Maven repo, own versioning per MC version) for a capability not needed. |
| owo-lib | Don't use | Broader UI/config/networking toolkit; same mismatch as Cloth Config, plus it's a heavier, more opinionated dependency (its own registry helpers, its own screen-building DSL) than this project's two-field config needs. |
| midnightlib | Don't use | Lighter than Cloth Config but still fundamentally a GUI-config-screen library; same "no GUI needed" mismatch, still an added dependency for zero net capability gained here. |

If a future milestone actually adds an in-game settings screen (not currently planned), that's the point to revisit Cloth Config or owo-lib — not before.

---

## 6. Local Mock HTTP Server

Confidence: **HIGH** for the recommendation (straightforward tooling choice, low risk either way)

**Recommendation: `com.sun.net.httpserver.HttpServer` (JDK built-in, `com.sun.net.httpserver` module, present since Java 6, still shipped in 17+). Do not reach for Python or Node.**

Rationale:

- It's **already in the same JDK** this project requires for everything else — no second runtime to install, document, or keep in sync for anyone else who clones the repo (the project constraint is a small private mod for the author and friends; minimizing "things you need installed to run this" matters more than usual here).
- It can be written as a plain Java class with a `main()` method, run via `java -cp ... MockServer` or as a Gradle `JavaExec` task alongside `runClient`, entirely independent from the mod's own build — no risk of it accidentally ending up inside the mod jar if kept in a separate source set (e.g. `tools/mock-server` or a `test`-scoped source set, not `src/main`).
- Full control over exactly the failure modes needed: register a handler that sleeps past the client's request timeout (tests timeout handling), one that writes a non-200 status with `exchange.sendResponseHeaders(500, ...)` (tests non-200 handling), and one that writes garbage bytes with `Content-Type: image/png` (tests `NativeImage.read` failure handling) — each as a distinct path/port so tests can pick which failure to exercise.

Skeleton:

```java
HttpServer server = HttpServer.create(new InetSocketAddress(8089), 0);
server.createContext("/api/transit/chart", exchange -> {
    byte[] png = Files.readAllBytes(Path.of("fixtures/sample-chart.png"));
    exchange.getResponseHeaders().set("Content-Type", "image/png");
    exchange.sendResponseHeaders(200, png.length);
    exchange.getResponseBody().write(png);
    exchange.close();
});
server.createContext("/api/transit/chart/timeout", exchange -> {
    try { Thread.sleep(30_000); } catch (InterruptedException ignored) {}
});
server.createContext("/api/transit/chart/error", exchange -> {
    exchange.sendResponseHeaders(500, -1);
    exchange.close();
});
server.createContext("/api/transit/chart/malformed", exchange -> {
    byte[] garbage = "not a png".getBytes();
    exchange.getResponseHeaders().set("Content-Type", "image/png");
    exchange.sendResponseHeaders(200, garbage.length);
    exchange.getResponseBody().write(garbage);
    exchange.close();
});
server.start();
```

Why not Python `http.server` or a Node script: both work and are genuinely simple too, but both require a second language runtime present and correctly on `PATH` for anyone running the dev environment, purely to serve bytes over HTTP — a job the already-mandatory JDK does natively. There's no functional gap that would justify introducing a second runtime for this.

---

## 7. Testing

Confidence: **HIGH** for what's practical to test and why; **MEDIUM** for exact `fabric-loader-junit`/gametest applicability judgment (a scoping recommendation, not a verifiable fact)

**Worth testing with plain JUnit 5** (Loom's default test source set already wires this up — `compileTestJava`/`test` tasks exist in this repo's task graph, confirmed by the local build run):

- `TransitApiClient`: inject the base URL / point at the local mock server (§6) and assert behavior for 200-with-valid-PNG, non-200, and timeout cases — no Minecraft classes involved, this is ordinary Java.
- Config load/parse/default-fallback logic (§5) — pure Gson + file I/O, no Minecraft classes involved.
- `TransitRefreshScheduler`'s timing logic — if it's written against an injectable clock/`ScheduledExecutorService` rather than directly against Minecraft's tick counter, this is fully testable in isolation and should be, since "refreshes every ~60s, retries on failure, no per-tick log spam" is exactly the kind of logic that's easy to get subtly wrong and cheap to unit-test.

**`net.fabricmc:fabric-loader-junit` — skip unless something concrete forces it.** This artifact exists (confirmed on Fabric's Maven, version `0.19.5` published matching this project's pinned `loader_version`) and its purpose is running JUnit tests *inside* an environment where Fabric Loader's Mixin transforms have been applied — i.e., testing code that only behaves correctly after mixins run. This project's design (per PROJECT.md's own component list — `TransitApiClient`, `TransitTextureManager`, `TransitRefreshScheduler`, `TransitConfig` as clearly separated units) doesn't need mixins for its core logic at all; the two example mixins in the template (`ExampleMixin`, `ExampleClientMixin`) are almost certainly deletable, not something to build on. Add `fabric-loader-junit` later only if some future requirement genuinely needs mixin-aware unit tests — don't add it speculatively now.

**Fabric's GameTest framework — not worth it here.** GameTest spins up a real (dedicated or client) Minecraft instance to script and assert in-world behavior (does placing an item cause an explosion, etc.). This project's core risk surface is (a) async HTTP correctness and (b) not leaking GPU textures — neither is well-suited to GameTest's world-simulation model, and GameTest cannot meaningfully assert "a texture got freed" or "an HTTP client handled a timeout correctly." The one thing GameTest *could* nominally exercise — "does the block exist and can it be placed" — is standard vanilla block-registration behavior with essentially zero chance of silently breaking, and is more efficiently checked by just running the dev client once.

**Honestly not worth testing at all:**
- Actual OpenGL rendering output (pixel-perfect texture-on-block rendering) — no practical automated way to assert this meaningfully for a small private mod; verify visually by running the client.
- Datagen output content — covered by the build succeeding (datagen either runs and produces JSON, or the build fails) plus a one-time visual/diff check of the generated files.
- Vanilla block placement/interaction mechanics themselves (as opposed to this mod's logic layered on top) — this is Minecraft's own, extremely well-tested code path; testing it would be testing the game, not the mod.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Minecraft (via Loom, official mappings) | 1.20.1 | Target game version | Fixed project constraint; verified buildable as-is. |
| Fabric Loader | 0.19.5 | Mod loading | Pinned by project constraint; confirmed this is Fabric's current/latest loader release, not a stale pin. |
| Fabric API | 0.92.12+1.20.1 | Registry/rendering/datagen helper APIs | Pinned by project constraint; `configureDataGeneration` DSL confirmed working against it. |
| Fabric Loom | 1.17-SNAPSHOT (resolves to 1.17.20) | Gradle build plugin, remaps Minecraft/mod code between mapping namespaces | Current, actively maintained; confirmed to build MC 1.20.1 with zero modification needed. Do not downgrade. |
| Java (mod target) | 17 (`options.release = 17`) | Bytecode target / language level | Matches Minecraft 1.20.1's runtime requirement exactly (`fabric.mod.json` already declares `"java": ">=17"`). |
| Java (build-time JDK) | 17+ (21 recommended if available) | Runs Gradle/Loom itself | Separate from the line above — see §1.3. Not a language-level change to the mod. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `java.net.http.HttpClient` | JDK built-in (17+) | Async HTTP GET for chart PNGs | Always — this is the HTTP layer, no alternative needed (§3). |
| Gson | Bundled with Minecraft (no explicit dependency needed) | Config file (de)serialization | Config load/save only (§5); do not add a newer standalone Gson version, use whatever ships with Minecraft to avoid classpath duplicate-version conflicts. |
| `com.sun.net.httpserver.HttpServer` | JDK built-in | Local mock server for error-path testing | Dev/test only — never referenced from `src/main` or `src/client` (§6). |
| JUnit 5 | Whatever Loom's default test source set provides | Unit tests for non-Minecraft logic | HTTP client, config parsing, refresh-scheduler timing (§7). |
| `net.fabricmc:fabric-loader-junit` | 0.19.5 (matches `loader_version`) | Mixin-aware JUnit tests | Only if a future requirement needs to unit-test mixin-affected behavior — not needed for this project's current design (§7). |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| IntelliJ IDEA | Primary IDE (project constraint) | Ensure "Gradle JVM" is set to JDK 17+ (21 if available) — see §1.3. `.idea/` run configurations for Client/Server/Data Generation already exist in the repo. |
| Gradle Wrapper 9.5.1 | Build tool | Already correctly pinned in `gradle/wrapper/gradle-wrapper.properties`; satisfies Loom 1.17's Gradle 9.2+ requirement with headroom. |

## Installation

No new dependencies are needed beyond what's already declared. If starting from a truly blank slate, the only lines that matter are already in this repo's `build.gradle`/`gradle.properties`/`settings.gradle` (§1.5) — there is no `npm install`-equivalent step here beyond `./gradlew build` resolving the declared Gradle dependencies on first run.

If you do decide `fabric-loader-junit` becomes worth adding later:

```gradle
dependencies {
    testImplementation "net.fabricmc:fabric-loader-junit:${project.loader_version}"
}
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| `java.net.http.HttpClient` | OkHttp | If the project later needs interceptors, connection-pool tuning beyond what `HttpClient` exposes, or HTTP/2 push — none apply here. |
| Hand-rolled Gson config | Cloth Config / owo-lib / midnightlib | If a future milestone adds an in-game settings GUI (not currently planned). |
| `com.sun.net.httpserver.HttpServer` mock | WireMock or a Node/Python mock server | If test scenarios grow far beyond a handful of fixed-response paths (e.g. dynamic stateful mocking, request matching by header/body) — unlikely for this project's scope. |
| `net.fabricmc.fabric-loom-remap` (current Loom) | Pinning an old 2023-era Loom (e.g. `1.3-SNAPSHOT`) | Never, for this project — see §1.1. There is no scenario where downgrading Loom helps; it would only lose current bugfixes and Gradle-version compatibility. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|--------------|
| `net.fabricmc.fabric-loom` (no `-remap`) plugin id | This is the id for post-1.21.11 "non-obfuscated" Minecraft versions; using it against 1.20.1 will fail to configure remapping correctly. | `net.fabricmc.fabric-loom-remap`, already correctly used in this repo. |
| Any current Fabric documentation page describing `RenderPipeline`/`GpuTexture`-based texture registration, or block entity renderer patterns illustrated on the docs site's default (current) version | The public `docs.fabricmc.net` site's un-versioned pages describe post-1.21 rendering internals that do not exist in 1.20.1's `NativeImage`/`DynamicTexture`/`TextureManager`/`RenderType` model used throughout §4. | This document's §2 and §4 tables, or direct inspection of the cached jar at `.gradle/loom-cache/minecraftMaven/**/minecraft-{clientOnly,common}-*.jar`. |
| Yarn class/method names copied verbatim into code (`NativeImageBackedTexture`, `registerTexture`, `destroyTexture`, `RenderLayer.getEntityCutout`, `Identifier`) | This project uses official Mojang mappings, not Yarn — these names don't exist in this project's compiled dependency set and won't resolve. | The Mojmap equivalents in §2's table (`DynamicTexture`, `register`, `release`, `RenderType.entityCutout`, `ResourceLocation`). |
| OkHttp / Apache HttpClient / Retrofit | Adds a real dependency (plus transitive deps and potential logging-binding conflicts with Minecraft's bundled logging stack) to solve something the JDK's `java.net.http.HttpClient` already does for this project's simple GET-bytes use case. | `java.net.http.HttpClient` (§3). |
| Cloth Config / owo-lib / midnightlib for this milestone | All three exist primarily to build in-game config *screens*; this project has exactly two config values and no GUI requirement. | Hand-rolled Gson + `FabricLoader.getInstance().getConfigDir()` (§5). |
| Routing dynamic runtime image data through Fabric Data Generation | Datagen runs at build time and produces static files shipped in the jar; it structurally cannot represent bytes that don't exist until a runtime HTTP call succeeds. Already called out as a category error in PROJECT.md. | Datagen stays scoped to static resources only (models, recipe, loot table, translations); runtime images flow through `TransitApiClient` → `NativeImage` → `DynamicTexture` → `TextureManager` (§4). |
| Python `http.server` / a Node mock server script | Requires a second language runtime installed and on `PATH`, purely to serve bytes, when the JDK (already mandatory) does this natively. | `com.sun.net.httpserver.HttpServer` (§6). |

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `net.fabricmc.fabric-loom-remap:1.17-SNAPSHOT` | `minecraft_version=1.20.1`, `fabric_api_version=0.92.12+1.20.1`, Gradle 9.5.1 | Verified via successful local `./gradlew build` in this exact repo. |
| Gradle Wrapper 9.5.1 | Loom 1.17.x (requires Gradle 9.2+) | Headroom above the minimum; no action needed. |
| Build-time JDK 17-26 | Loom 1.17.x, this project's Gradle build | Verified working with JDK 26 in this environment; JDK 17+ (21 recommended) should be treated as the floor per §1.3, independent of the mod's Java 17 bytecode target. |
| `net.fabricmc:fabric-loader-junit:0.19.5` | `loader_version=0.19.5` | Matching versions confirmed available on `maven.fabricmc.net`; keep these two properties in lockstep if either changes later. |
| Cloth Config `11.1.136+fabric` | Minecraft 1.20-1.20.1 | Listed only for completeness (§5 recommends against using it this milestone); would need its own Maven repo (`maven.shedaniel.me`) declared if adopted later. |

## Sources

- Local verification (HIGH): `./gradlew build` run in this repository, 2026-09-07 — `BUILD SUCCESSFUL in 21s`; `./gradlew tasks` showing a working `runDatagen` task.
- Local verification (HIGH): `javap` inspection of classes extracted from `.gradle/loom-cache/minecraftMaven/net/minecraft/minecraft-{clientOnly,common}-*/1.20.1-loom.mappings.1_20_1.layered+hash.2198-v2/*.jar` — the actual official-mappings Minecraft 1.20.1 jar this project compiles against.
- `maven.fabricmc.net` `maven-metadata.xml` for `net.fabricmc.fabric-loom-remap` and `net.fabricmc:fabric-loader-junit` (HIGH — primary artifact registry, fetched directly).
- FabricMC/fabric-loom GitHub Releases, tags `1.14` and `1.17` (HIGH — official release notes, fetched directly via GitHub API).
- `raw.githubusercontent.com/FabricMC/fabric-example-mod` branch `1.20`, `build.gradle` and `gradle.properties` (HIGH — official Fabric template repo, fetched live today).
- `raw.githubusercontent.com/FabricMC/fabric-docs` `develop/loom/fabric-api.md` (HIGH — official docs source markdown, fetched directly, bypassing the JS-rendered site).
- WebSearch: Gradle 9 JDK compatibility requirements (MEDIUM — synthesized web answer, not independently re-verified against a JDK below 17 in this environment).
- WebSearch: Cloth Config version/compatibility, fabric-loader-junit purpose and usage (MEDIUM — standard community/official-adjacent sources, cross-checked against Fabric's own Maven metadata where possible).

---
*Stack research for: Minecraft Fabric 1.20.1 dynamic remote-image block mod*
*Researched: 2026-09-07*

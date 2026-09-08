<!-- GSD:project-start source:PROJECT.md -->

## Project

**Human Design Transit Display**

A Minecraft Java Edition mod (Fabric, 1.20.1) that adds a craftable, placeable block which renders a live Human Design transit chart on its face. The block fetches a PNG from an external Human Design API over HTTP, refreshes it roughly once a minute, and keeps showing the last good chart when the API is unreachable. Built for the author and a small group of friends on a private server.

The mod is a presentation client, not a calculation engine. All Human Design math and chart generation live in the external API.

**Core Value:** A block placed in the world shows a current Human Design transit chart that keeps updating on its own, and never freezes or crashes Minecraft when the API misbehaves.

### Constraints

- **Tech stack**: Minecraft Java Edition 1.20.1, Fabric Loader 0.19.5, Fabric API 0.92.12+1.20.1, Java 17, Gradle + Fabric Loom, IntelliJ IDEA — deliberately chosen for the 1.20.1 mod ecosystem, and fixed for this milestone
- **Threading**: no blocking network I/O on the main or render thread — Minecraft must stay responsive while a request is in flight; completion must hand back to the correct Minecraft thread before touching texture or render state
- **Separation of concerns**: the renderer never performs HTTP; the HTTP client never manipulates rendering state; Human Design logic never enters the mod at all
- **Resource lifecycle**: dynamically created textures must be released when replaced — a texture allocated every 60 seconds and never freed is an unbounded GPU leak
- **Persistence**: no large binary blobs in block entity NBT or the world save; persist only configuration and state that genuinely must survive a reload
- **Logging**: diagnostics on failure, but no per-tick log spam from a repeatedly-failing endpoint
- **Multiplayer**: not a built feature this milestone, but the architecture must not make it unnecessarily hard later — the mod will run on a small private server
- **Dependencies**: prefer mechanisms Fabric/Minecraft already provide; a third-party library needs an explicit justification before it goes in
- **Abstraction**: this is a small mod — avoid premature abstraction and speculative extension points

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## 0. Headline Finding — The Toolchain Discrepancy Is Not a Bug

## 1. Gradle / Loom Toolchain

### 1.1 Plugin id: `net.fabricmc.fabric-loom-remap` — correct, not a typo

| Plugin id | Applies to | Notes |
|---|---|---|
| `net.fabricmc.fabric-loom-remap` | "Obfuscated" Minecraft versions — **everything up to and including 1.21.11** | This is what 1.20.1 needs. Confirmed correct for this project. |
| `net.fabricmc.fabric-loom` | "Non-obfuscated" Minecraft versions — the newer date-based releases (26.1 and later) | Not applicable to this project. Do not use. |
| `fabric-loom` (no `net.fabricmc.` prefix) | Legacy id, kept only for backward compatibility with existing obfuscated-version projects | Still works for 1.20.1 but there's no reason to prefer it over the explicit `-remap` id in a new project. |

### 1.2 `loom_version=1.17-SNAPSHOT` — resolves, is current

### 1.3 Java version split: build-time JDK vs. mod's target bytecode

- The **mod itself** must target Java 17 bytecode, because that's what Minecraft 1.20.1 ships and requires at runtime. The repo's `options.release = 17` and `sourceCompatibility/targetCompatibility = VERSION_17` are correct and must stay as-is.
- The **Gradle daemon that builds it** needs a newer JDK than that. Loom 1.14+ requires Gradle 9.2+, and Gradle 9.x requires JDK 17+ to run its daemon at minimum, with some reports indicating current Loom (1.17.x) is tested primarily against JDK 21 build environments. In practice: make sure IntelliJ's "Gradle JVM" setting (or `org.gradle.java.home` / a `JAVA_HOME` pointing at it) is JDK 17 or newer — JDK 21 is the safe choice if you have it, since that's what the current official template's own compile target implies the Fabric team builds with.
- This project's environment had JDK 26 available and the build succeeded, so JDK 17-26 all work for running Gradle here; I did not test the floor.

### 1.4 `fabricApi { configureDataGeneration { client = true } }` — current, correct, already working

### 1.5 Known-good pairing (this repo's current values — no changes needed)

# gradle.properties — already correct, do not change

## 2. Mappings — Mojang Official vs. Yarn, for the Types This Project Touches

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

## 3. HTTP Client

- `java.net.http` has been a standard, non-incubating JDK module since Java 11. Minecraft 1.20.1 requires Java 17 at runtime, so it is *guaranteed* present on every machine that can run this mod at all — no version negotiation, no shading, no relocating.
- Fabric mods run their own classes through Fabric Loader's "Knot" classloader for mixin/transform purposes, but **JDK platform classes (`java.*`, including `java.net.http.*`) are always resolved via the platform/bootstrap classloader**, not Knot. There is no known interaction between Fabric's classloading and `java.net.http`; it is ordinary JDK API usage from the mod's perspective, no different from using `java.util.concurrent` or `java.io`. I found no credible reports of Fabric-specific breakage with `HttpClient` — the tool exists precisely because it needs zero extra ceremony.
- OkHttp or Apache HttpClient would add a real dependency (with its own transitive deps, potential Log4j/SLF4J binding conflicts against Minecraft's already-present logging stack, and a `modImplementation`/shading decision) to solve a problem the JDK already solves. There is no capability this project needs (retries, connection pooling, HTTP/2, timeouts) that `HttpClient` lacks for a single simple `GET` returning bytes.
- **Connect timeout** is set on the `HttpClient` itself (`.connectTimeout(Duration)`), applies to establishing the TCP/TLS connection.
- **Request timeout** is set per-request (`HttpRequest.Builder.timeout(Duration)`), covers the whole request/response including the connect phase — this is the one that actually bounds "the API is unreachable, don't hang forever," and is the one to test against the mock server's deliberate-timeout mode.
- **Executor**: if you don't set one, `HttpClient` defaults to an internal cached thread pool derived from `ForkJoinPool.commonPool()`. That's fine functionally but means your callback runs on a thread pool shared with the rest of the JVM (including, in principle, Minecraft's own use of the common pool for other things) — supplying your own small dedicated executor (a single-thread or 2-thread fixed pool) makes behavior easier to reason about and keeps a runaway/slow API call from starving unrelated common-pool work. Do not use `Runnable::run` (synchronous) as the executor — that would make `sendAsync` block the calling thread, defeating the point.
- **Never build the `HttpClient` on the main thread per-request.** Build one `HttpClient` once (e.g., a field on `TransitApiClient`) and reuse it — construction has non-trivial overhead and per-request instances defeat any connection reuse.
- Every callback (`.whenComplete`, `.thenApply` continuation, etc.) must marshal back to the main thread via `Minecraft.getInstance().execute(...)` before it touches `TextureManager`, `NativeImage`, or any render state. This is the actual mechanism that satisfies "no blocking network I/O on the main/render thread" *and* "completion must hand back to the correct Minecraft thread" from PROJECT.md's constraints — `HttpClient`'s async API only solves the first half; the `execute()` hop is what you write yourself for the second half.

## 4. Image Decoding and Texture Types (1.20.1, Official Mappings)

- **`NativeImage.read(byte[])` exists exactly as named in 1.20.1.** There is no need to go through `InputStream` or `ByteBuffer` unless convenient — all three overloads exist, use whichever fits how the HTTP body arrives (`HttpResponse.BodyHandlers.ofByteArray()` pairs naturally with `read(byte[])`).
- **Do not reuse a single `Identifier`/`ResourceLocation` across refreshes without releasing first**, or reuse a fresh one per refresh and release the previous one — either strategy works, but the release call must happen. There's no automatic garbage collection of GPU texture handles tied to Java object lifetime; `AbstractTexture` implements `AutoCloseable` but nothing calls `close()` for you unless you call `TextureManager.release(...)` (which internally closes and forgets the registration) or `close()` directly plus manually deregistering — prefer `release()`, it does both.
- **`RenderLayer.getEntityCutout(Identifier)` from tutorials is `RenderType.entityCutout(ResourceLocation)` here** — same role, different class/method name, see §2. Anything from a post-1.20.1 tutorial calling this on a class literally named `RenderLayer` in Mojmap will not compile — that Mojmap class is unrelated (see the "danger" row in §2).
- **Datagen is unrelated to any of the above.** Datagen (block/item models, loot tables, recipes, language files) is a build-time step producing static JSON, wired via the `fabricApi { configureDataGeneration }` block from §1.4. It has no interaction with the runtime texture pipeline — don't be tempted to route dynamic image data through it (PROJECT.md already calls this out explicitly as a category error, and I'll say why for anyone reading the roadmap: datagen output is written to `src/main/generated` at build time and shipped in the jar; it structurally cannot represent bytes that don't exist until a runtime HTTP call succeeds).
- **What changed after 1.20.1, so you don't go looking for it or copy it by mistake:** newer Minecraft versions (1.21+) moved much of the render pipeline toward a `RenderPipeline`/`GpuTexture` abstraction with different registration flow, and later versions also changed how blaze3d/`NativeImage` interacts with the newer rendering backend work. None of that exists in 1.20.1. If a tutorial mentions `RenderPipeline`, `GpuTexture`, or texture registration through a "Sprite"/atlas-first API for a *non-atlas, standalone runtime texture* — that's not 1.20.1, skip it.

## 5. Config Library

| Option | Verdict | Why |
|---|---|---|
| **Hand-rolled Gson + `FabricLoader.getConfigDir()`** | **Use this** | Gson is already on the classpath (Minecraft itself depends on it; no new dependency at all). `FabricLoader.getInstance().getConfigDir()` returns a `java.nio.file.Path` to the standard per-instance config folder — read a small record/POJO on mod init, fall back to defaults and write the file if it's missing or fails to parse, done. This is ~30 lines of code, matches the project's explicit "avoid premature abstraction and speculative extension points" constraint, and needs zero new Gradle dependencies. |
| Cloth Config | Don't use | Built specifically to *draw config screens* (usually surfaced through Mod Menu). This project has no config screen requirement — Cloth Config would import a whole GUI-building API to serialize two fields. Real dependency (own Maven repo, own versioning per MC version) for a capability not needed. |
| owo-lib | Don't use | Broader UI/config/networking toolkit; same mismatch as Cloth Config, plus it's a heavier, more opinionated dependency (its own registry helpers, its own screen-building DSL) than this project's two-field config needs. |
| midnightlib | Don't use | Lighter than Cloth Config but still fundamentally a GUI-config-screen library; same "no GUI needed" mismatch, still an added dependency for zero net capability gained here. |

## 6. Local Mock HTTP Server

- It's **already in the same JDK** this project requires for everything else — no second runtime to install, document, or keep in sync for anyone else who clones the repo (the project constraint is a small private mod for the author and friends; minimizing "things you need installed to run this" matters more than usual here).
- It can be written as a plain Java class with a `main()` method, run via `java -cp ... MockServer` or as a Gradle `JavaExec` task alongside `runClient`, entirely independent from the mod's own build — no risk of it accidentally ending up inside the mod jar if kept in a separate source set (e.g. `tools/mock-server` or a `test`-scoped source set, not `src/main`).
- Full control over exactly the failure modes needed: register a handler that sleeps past the client's request timeout (tests timeout handling), one that writes a non-200 status with `exchange.sendResponseHeaders(500, ...)` (tests non-200 handling), and one that writes garbage bytes with `Content-Type: image/png` (tests `NativeImage.read` failure handling) — each as a distinct path/port so tests can pick which failure to exercise.

## 7. Testing

- `TransitApiClient`: inject the base URL / point at the local mock server (§6) and assert behavior for 200-with-valid-PNG, non-200, and timeout cases — no Minecraft classes involved, this is ordinary Java.
- Config load/parse/default-fallback logic (§5) — pure Gson + file I/O, no Minecraft classes involved.
- `TransitRefreshScheduler`'s timing logic — if it's written against an injectable clock/`ScheduledExecutorService` rather than directly against Minecraft's tick counter, this is fully testable in isolation and should be, since "refreshes every ~60s, retries on failure, no per-tick log spam" is exactly the kind of logic that's easy to get subtly wrong and cheap to unit-test.
- Actual OpenGL rendering output (pixel-perfect texture-on-block rendering) — no practical automated way to assert this meaningfully for a small private mod; verify visually by running the client.
- Datagen output content — covered by the build succeeding (datagen either runs and produces JSON, or the build fails) plus a one-time visual/diff check of the generated files.
- Vanilla block placement/interaction mechanics themselves (as opposed to this mod's logic layered on top) — this is Minecraft's own, extremely well-tested code path; testing it would be testing the game, not the mod.

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

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

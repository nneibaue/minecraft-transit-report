# Phase 1: Toolchain Verification - Context

**Gathered:** 2026-09-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the development loop works end to end: the Fabric dev client launches with the mod loaded, data generation writes real files to `src/main/generated`, and the `configureDataGeneration { client = true }` question is settled by observation rather than assumption.

Covers TOOL-01, TOOL-02, TOOL-03. No block, no renderer, no HTTP, no texture work.

**Scope correction from discussion:** the roadmap frames this as a pure sanity check ("do not budget Loom surgery"). That still holds for Loom. But scouting turned up three things that make this phase slightly more than a formality — see Existing Code Insights. The phase now also includes a small amount of source change: deleting the inert example mixins, filling in real `fabric.mod.json` metadata, registering the first datagen provider so TOOL-02 can actually pass, and writing `docs/DEV.md`.

</domain>

<decisions>
## Implementation Decisions

### Verification Target

- **D-01:** All development and verification runs against the Fabric dev client (`./gradlew runClient`), not against the user's installed `.minecraft`. The dev client is a real, playable Minecraft 1.20.1 window — there was never a separate automated harness to skip. Installing a built jar into the real launcher is a distribution concern for the private server, deferred out of this phase.
- **D-02:** Do **not** reconfigure Loom to share the user's `%APPDATA%/.minecraft/assets`. Loom already holds its own complete 629 MB copy at the same asset index, so there is no download cost left to avoid — only duplicated disk. A nonstandard asset path buys nothing and risks a silently broken client (no sounds, no text) that is confusing to diagnose.

### runClient Verification Protocol

- **D-03:** Claude launches `runClient` in the background and tails the log; the user watches the Minecraft window and confirms what is on screen. Neither side alone is sufficient — Claude cannot see the window, and the log carries failure detail the window does not.
- **D-04:** Verification passes only when **both** hold: (a) the mod is listed on the in-game Mods screen, and (b) the user creates a creative superflat world and stands in it. Reaching the main menu is not enough — world load is where registries and mixins are actually exercised, and it is a distinct failure mode. The world created here is kept as the reusable dev test world for Phase 2 onward.
- **D-05:** The mod's own startup log line `"Hello Fabric world!"` (from `JollyalchemyTransitReport.onInitialize()`) is the log-side signal Claude greps for, alongside Fabric's mod-count line and any exception traces. It is corroborating evidence, not a substitute for D-04.

### JDK Risk Handling

- **D-06:** Attempt the first launch on the machine's existing JDK 26. If it fails on anything version-shaped — module access errors, LWJGL native loading, Mixin reflection into JDK internals — install Temurin JDK 21 immediately and pin it, rather than debugging Minecraft 1.20.1 on JDK 26. This is a pre-agreed hard stop, not a judgement call to be made in the moment. — **Reversibility:** reversible — pinning or unpinning a JDK is a one-line Gradle change with no dependent code.

  **Rationale for treating this as a real risk:** `./gradlew build` succeeding proves nothing here. `options.release = 17` means the JDK 26 daemon emits Java 17 bytecode without ever running Minecraft. `runClient` is the first time JDK 26 has to actually execute LWJGL natives, Mixin's bytecode manipulation, and 1.20.1 game code — all built and tested against Java 17. Running 1.20.1 on Java 21 is common; JDK 26 is considerably further out and unevidenced either way. The roadmap's "no Loom surgery" note does not cover this — it is the JVM the game runs on, not the build plugin.

### Template Cleanup

- **D-07:** Delete `ExampleMixin` and `ExampleClientMixin`, and empty the corresponding arrays in `jollyalchemy-transit-report.mixins.json` and `jollyalchemy-transit-report.client.mixins.json`. Both classes have empty method bodies — they inject into `MinecraftServer.loadLevel()` and `Minecraft.run()` and do nothing. Removing them means any future startup mixin error is unambiguously ours.
- **D-08:** `fabric.mod.json` display name becomes **"Human Design Transit Display"**, matching PROJECT.md's project title. This is deliberate: the Mods screen is the artifact this phase uses as proof, so the name shown there should match the name in the planning docs.
- **D-09:** Fill remaining `fabric.mod.json` metadata with real values — description drawn from PROJECT.md's core value, `authors: ["Nate Neibauer"]`, `contact.sources` pointing at `git@github.com:nneibaue/minecraft-transit-report.git`'s GitHub URL. Remove the placeholder `fabricmc.net` homepage rather than substituting a fake one.
- **D-10:** Leave `license: "CC0-1.0"` and the repo's `LICENSE` file untouched. They currently agree with each other, so nothing is misstated, and licensing is not a Phase 1 question. Revisit if and when distribution to the private server is set up.

### Documentation

- **D-11:** Create `docs/DEV.md` in the repo covering: how to run the dev client, how to run datagen, the JDK requirement and why it matters, and what "verified" means for this phase. This is where the build-a-jar-and-install-into-real-Minecraft walkthrough goes when the private-server milestone arrives — the user explicitly asked to have that written down. Repo-local so it survives context resets and is findable by a human, not buried in `.planning/`.

### Claude's Discretion

The user chose not to discuss two areas. Claude's calls, to be treated as decisions unless planning finds a reason against them:

- **D-12 (datagen has nothing to generate):** Register a `FabricLanguageProvider` with at least one real translation entry, and verify that `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` actually appears on disk.

  **Why a provider is in scope:** TOOL-02 requires generated resources present under `src/main/generated`. Today `onInitializeDataGenerator()` is empty, so `runDatagen` exits 0 while writing zero files — the task can pass its exit code and fail its actual criterion. TOOL-02 is unsatisfiable without registering *some* provider, so one is required by this phase's own requirement rather than borrowed from a later phase.

  **Why a language provider specifically:** it is the only provider that needs no block, item, or model to exist, so it pulls nothing forward from Phase 2. It is also not throwaway — GEN-05 (translations via datagen) is real Phase 3 work, and this is that provider's skeleton.

  Verify the 1.20.1 `FabricLanguageProvider` constructor and method shape against resolved sources (`./gradlew genSources`, or `javap` against the cached jar), **not** against current Fabric documentation — see D-14.

- **D-13 (settling `client = true`, TOOL-03):** Settle empirically, cheaply, and in this order:
  1. With the flag present, capture `./gradlew tasks --all` output for datagen-related tasks.
  2. Change to bare `configureDataGeneration()`, re-run, and diff the task list.
  3. With a provider registered (D-12), diff the actual generated output between the two forms.
  4. Record the finding in `docs/DEV.md` and in the phase SUMMARY.

  **Decision rule:** if the flag makes no observable difference on 1.20.1, drop to bare `configureDataGeneration()` — carrying a flag that does nothing is a trap for whoever reads this next. If it does make a difference, keep it and record precisely what it does.

  **Do not remove it blind.** `build.gradle` calls `splitEnvironmentSourceSets()`, and the datagen entrypoint lives in `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` — the *client* source set. `client = true` may be exactly what makes that source set visible to the datagen run. Research assumed the flag was inert-or-broken on 1.20.1; that assumption is untested against this repo's split-source-set layout. Treat "removing it breaks datagen entirely" as a live hypothesis to test, not an edge case.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope and requirements
- `.planning/PROJECT.md` — project definition, constraints, out-of-scope list, Key Decisions table. The "Toolchain — verified working" and "Version tension" paragraphs in Context are directly relevant.
- `.planning/REQUIREMENTS.md` — TOOL-01, TOOL-02, TOOL-03 definitions (lines 10-14) and the traceability table.
- `.planning/ROADMAP.md` — Phase 1 goal, three success criteria, and the "sanity check, not a rework phase" scope note.

### Toolchain research
- `.planning/research/PITFALLS.md` — Pitfall 2 (lines 31, 52, 58, 63, 110, 337, 347) is the `client = true` question in full, including the recommended empirical procedure and the note that client-side datagen may need manual wiring on 1.20.1.
- `.planning/research/STACK.md` §1.1-§1.5 — Loom plugin id rationale, `loom_version` currency, the build-time JDK vs. target bytecode split (§1.3), and the claim in §1.4 that `configureDataGeneration { client = true }` is "current, correct, already working" — note this conflicts with PITFALLS.md and is precisely what TOOL-03 exists to settle.
- `.planning/research/SUMMARY.md` — lines 18 and 82 flag the `client = true` question as Phase 1 empirical work.

### Project conventions
- `.claude/CLAUDE.md` — Mojang-official vs. Yarn mappings table (§2), which governs every class name used from Phase 4 onward. Not directly needed for Phase 1, but the "prefer resolved sources over documentation" convention it encodes applies to D-12 and D-13.

### Note on conflicting sources
`STACK.md` §1.4 and `PITFALLS.md` Pitfall 2 disagree about `client = true`. STACK.md observed that the build succeeds with the flag present; PITFALLS.md observes that Fabric documents the flag as a 1.21.4+ addition. Both can be true — configuration-time acceptance is not the same as runtime effect. **Do not resolve this by picking a document. Resolve it by observation, per D-13.**

</canonical_refs>

<code_context>
## Existing Code Insights

### Current state
The repo is an unmodified Fabric example-mod template. `git status` is clean. Nothing in `src/` is load-bearing.

### Scout findings that change this phase

- **Loom's Minecraft assets are already downloaded.** `~/.gradle/caches/fabric-loom/assets` holds 629 MB across all 256 object subdirs with index `1.20.1-5.json` — the same size and asset index as the user's `%APPDATA%/.minecraft/assets` (629 MB, index `5.json`). The expensive first-run download already happened during the research session. There is no slow first launch ahead. This is what makes D-02 a non-decision.

- **`runClient` has never completed a launch.** `run/` exists but contains only empty `datagen/` and `resources/` subdirectories — no `options.txt`, no `saves/`, no `logs/`. TOOL-01 is genuinely unverified, not merely unrecorded. This is the real unknown in the phase.

- **`runDatagen` runs and writes nothing.** `run/datagen` exists, so the task has been invoked. `src/main/generated` does not exist at all. `JollyalchemyTransitReportDataGenerator.onInitializeDataGenerator()` has an empty body — zero providers registered. TOOL-02 cannot pass as written without a provider. This is what D-12 addresses.

- **JDK 26 is the only JDK on the machine.** `JAVA_HOME` is `C:\Users\nneib\.jdks\openjdk-26.0.2.1`, it is the sole entry under `~/.jdks`, and the sole `java` on `PATH`. No JDK 17, no JDK 21, and no launcher-bundled runtime under `.minecraft/runtime`. Nothing pins a Gradle JVM in `gradle.properties`. This is what D-06 addresses.

- **The example mixins are inert.** `ExampleMixin` (injects `MinecraftServer.loadLevel()`) and `ExampleClientMixin` (injects `Minecraft.run()`) both have empty method bodies. They log nothing. The only mod startup log line is `"Hello Fabric world!"` from `JollyalchemyTransitReport.onInitialize()`.

### Reusable assets
- `JollyalchemyTransitReport.MOD_ID` and the static `id(String path)` helper returning `ResourceLocation` — already present and correct; every later phase's registration will use them.
- `JollyalchemyTransitReport.LOGGER` — SLF4J logger already named after the mod id, ready for the failure-diagnostics requirements in Phase 9.
- `JollyalchemyTransitReportClient.onInitializeClient()` — empty client entrypoint, the hook point for the Phase 4 renderer registration.

### Established patterns
- `build.gradle` calls `loom { splitEnvironmentSourceSets() }`, so `src/main` (common) and `src/client` (client-only) are separate source sets. The datagen entrypoint currently lives in the **client** set. This split is directly relevant to D-13 and, later, to keeping `TransitConfig` free of client-only imports.
- Mappings are `loom.officialMojangMappings()` — Mojang official, not Yarn. Every class name follows `.claude/CLAUDE.md` §2, not tutorial names.
- `options.release = 17` with `sourceCompatibility`/`targetCompatibility = VERSION_17`. Correct and must stay — independent of whichever JDK runs the daemon.

### Integration points
- `src/main/resources/fabric.mod.json` — entrypoints, metadata (D-08, D-09, D-10), mixin config list (D-07).
- `src/main/resources/jollyalchemy-transit-report.mixins.json` and `src/client/resources/jollyalchemy-transit-report.client.mixins.json` — mixin arrays to empty in D-07.
- `JollyalchemyTransitReportDataGenerator.onInitializeDataGenerator()` — where the D-12 provider gets registered.
- `build.gradle` `fabricApi { configureDataGeneration { ... } }` — the D-13 experiment site.

</code_context>

<specifics>
## Specific Ideas

- The user is new to Minecraft mod development and initially assumed `runClient` was something other than playing the game, asking whether verifications could be skipped in favour of testing in-game. Downstream agents should keep explaining Minecraft- and Fabric-specific mechanics (dev client vs. launcher, source sets, datagen, mixins) where they matter, per PROJECT.md's Author background note. General software engineering needs no explanation.
- The user explicitly asked to be walked through installing the mod into their real Minecraft. That walkthrough is deferred (see Deferred Ideas) but was requested — `docs/DEV.md` (D-11) is the place it lands, and it should not be forgotten.
- The user's instinct to reuse already-downloaded assets was sound; it was moot only because the download had already happened invisibly. Worth confirming disk-level facts before answering this kind of question rather than reasoning from defaults.

</specifics>

<deferred>
## Deferred Ideas

- **Path B — install the built mod into real Minecraft.** Build a jar (`./gradlew build` → `build/libs/`), install Fabric Loader 1.20.1 via the official installer, download Fabric API `0.92.12+1.20.1`, drop both jars into `%APPDATA%\.minecraft\mods\`, and launch the `fabric-loader-1.20.1` profile. Requested by the user during this discussion. Belongs to the private-server distribution milestone, not to v1 phase work. Write it into `docs/DEV.md` when that milestone arrives.
- **Licensing decision (CC0 vs. All Rights Reserved).** Surfaced while cleaning `fabric.mod.json`. Deferred by D-10 — current state is self-consistent, and this is a distribution question, not a verification question.
- **Reclaiming the duplicated 629 MB of Minecraft assets** by pointing Loom at `.minecraft/assets`. Rejected for this phase by D-02 as poor risk-for-reward. Only worth revisiting if disk pressure becomes real.

</deferred>

---

*Phase: 1-Toolchain Verification*
*Context gathered: 2026-09-07*

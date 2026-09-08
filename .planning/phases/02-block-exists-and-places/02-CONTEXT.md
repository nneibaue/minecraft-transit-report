# Phase 2: Block Exists and Places - Context

**Gathered:** 2026-09-08
**Status:** Ready for planning

<domain>
## Phase Boundary

A block is registered, appears as an item in a creative inventory group, places itself with a 4-way horizontal facing state taken from the player's direction, and draws a real generated model rather than the missing-model checkerboard. Blockstate, block model, and item model JSON all come out of data generation.

Covers BLOCK-01, BLOCK-02, BLOCK-03, GEN-01, GEN-02.

**Explicitly not in this phase:** no `BlockEntity`, no renderer, no texture pipeline, no HTTP, no crafting recipe, no loot table. The crafting recipe (BLOCK-04) and loot table (BLOCK-05) that make the block obtainable in survival are Phase 3 and already scoped — see D-04.

**One deliberate pull-forward:** the block's display-name translation string is added this phase, one line ahead of GEN-05's Phase 3 scope. See D-05.

</domain>

<decisions>
## Implementation Decisions

### Naming and Identity

- **D-01:** The block's in-game display name is **"Transit Chart"**. Chosen over "Transit Display" and "Transit Report" — the thing on the face is literally a Human Design transit chart, and that is the word the owner wants players to read.

- **D-02:** The registry id and Java class names **follow the display name**, not PROJECT.md's suggested `TransitDisplayBlock`. Registry id is `transit_chart`; the block class is `TransitChartBlock`; later phases follow the same stem (`TransitChartBlockEntity`, `TransitChartRenderer`). PROJECT.md's Intended component decomposition explicitly states "names are suggestions; idiomatic Fabric structure wins if it differs" — this is that clause being exercised, not a contradiction of it.

  The knock-on effects are the point of deciding it now: the id becomes `transit_chart.json` in every generated blockstate/model/loot-table/recipe path, and the translation key becomes `block.jollyalchemy-transit-report.transit_chart`.

  — **Reversibility:** costly — renaming after Phase 2 means regenerating every datagen JSON under a new path, changing the translation key, and breaking any block already placed in the Phase 1 dev test world (unknown-block on world load). Cheap now, annoying later.

  **Note for the planner:** PROJECT.md's component-decomposition list still says `TransitDisplayBlock`. That list is superseded by D-02 for the block itself. `TransitApiClient`, `TransitTextureManager`, `TransitRefreshScheduler`, and `TransitConfig` are untouched by this decision — they are not named after the block.

### Appearance and Facing

- **D-03:** **Borrow vanilla textures — the furnace set.** The generated model points at `minecraft:block/furnace_front`, `minecraft:block/furnace_side`, and `minecraft:block/furnace_top`. No PNG is authored and no texture file is added to the repo this phase.

  Two reasons this is the right call rather than a lazy one. First, PROJECT.md's Out of Scope list names "decorative modeling and visual polish ahead of the dynamic texture pipeline" — appearance work is deliberately deferred until images actually update on the block, so any art made now is throwaway. Second, and more practically: the furnace front's dark arched opening is what makes success criterion 2 satisfiable at all. A uniform all-sides cube stores a facing state that is invisible, which would leave criterion 2 unverifiable. The furnace set is also the exact texture family vanilla's own orientable-block model template was built around, so it is the least likely to fight the datagen helper.

  — **Reversibility:** reversible — swapping texture paths is a one-line change in the model provider plus a `runDatagen` re-run.

- **D-04:** **The front faces the player who placed it** — furnace/chest convention, `getNearestLookingDirection().getOpposite()`, not the piston/observer convention. You place it against a wall and the face looks back at you. This matches the roadmap's "a block that hangs on a wall" framing and is what Phase 4's renderer needs: REND-06 orients the chart by the facing state, so "facing" must already mean "the side you read from".

- **D-05:** **Verification is visual only.** Place four blocks, each approached from a different direction, and confirm the fronts point four different ways in the running dev client. The F3 blockstate readout was offered as a second, independent check (it separates "state stored correctly" from "model rotates correctly" — two distinct failure modes) and was declined as unnecessary.

  Phase 1's protocol still applies (01-CONTEXT.md D-03): Claude launches `runClient` in the background and tails the log; the user watches the window and confirms what is on screen. The dev world created in Phase 1 is the test world.

  **Residual risk, recorded not argued:** a blockstate JSON that forgets to rotate the model and a block that forgets to store the facing state produce visibly different results, so the visual check does catch both — but a model that rotates correctly while the stored state is subtly wrong (e.g. inverted) would look plausible and only surface in Phase 4. Low risk given D-04 uses the stock vanilla idiom.

### Creative Inventory and Naming Visibility

- **D-06:** **Vanilla Functional Blocks tab**, via Fabric API's `ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)`. No dedicated mod tab. One block does not justify standing up a tab with its own icon and translation key, and PROJECT.md's "avoid premature abstraction and speculative extension points" constraint points the same way. Functional Blocks puts it next to furnaces and lecterns — blocks that do something — which is where it belongs.

  **Clarification captured during discussion:** the user's concern was that a creative-only block would not be obtainable in survival. Creative tab placement and survival availability are independent mechanisms. Survival obtainability comes from the crafting recipe (BLOCK-04) and the loot table (BLOCK-05), both already scoped as **Phase 3**. The creative tab is a testing convenience for Phase 2 that costs nothing in survival and blocks nothing later. This is not a deferred idea — it is next phase's existing scope.

- **D-07:** **Add the block's display-name translation this phase**, as one added line in the existing `TransitReportLanguageProvider` (registered and working since Phase 1). Key `block.jollyalchemy-transit-report.transit_chart` → `"Transit Chart"`.

  This borrows one string from GEN-05's Phase 3 scope so the creative tab and hotbar read "Transit Chart" instead of a raw translation key while Phase 2's own placement-and-facing verification is being done. **Phase 3 still owns all of GEN-05** — the BLOCK-06 tooltip, any messages, and the rest of the translation set. Phase 3's success criterion 3 ("no raw translation keys appear anywhere") is unaffected; this makes it marginally easier to reach.

### Claude's Discretion

The user chose not to discuss two of the four areas offered. These are Claude's calls, to be treated as decisions unless planning finds a concrete reason against them.

- **D-08 (block entity timing — DEFER to Phase 4):** Phase 2 does **not** introduce a `BlockEntity` or `BlockEntityType`. The roadmap's Phase 2 note says one "may be introduced here as plumbing" — permissive, not required — and none of BLOCK-01, BLOCK-02, BLOCK-03, GEN-01, or GEN-02 needs one. REND-01 explicitly places the block entity in Phase 4.

  **The concrete reason not to pull it forward is a 1.20.1 trap, verified against resolved sources this session.** `javap` against the cached Mojang-mappings common jar confirms `net.minecraft.world.level.block.BaseEntityBlock` declares `public RenderShape getRenderShape(BlockState)` — on 1.20.1 that returns `RenderShape.INVISIBLE`. A block extending `BaseEntityBlock` without overriding it back to `RenderShape.MODEL` renders **nothing at all**, which is a direct hit on Phase 2's success criterion 3 ("draws a real model rather than the purple-and-black missing-model checkerboard"). Introducing the block entity now means fighting that trap this phase for zero benefit this phase.

  The same `javap` run confirms `BaseEntityBlock extends Block` — it does **not** extend `HorizontalDirectionalBlock`. So a block entity plus 4-way facing means the `FACING` property, `createBlockStateDefinition`, `getStateForPlacement`, `rotate`, and `mirror` are all hand-wired rather than inherited.

  **Therefore, this phase:** `TransitChartBlock extends HorizontalDirectionalBlock`, which supplies `FACING`, `rotate`, and `mirror` for free.

  — **Reversibility:** reversible — Phase 4 adds the block entity by implementing the `EntityBlock` interface on the existing class plus one registration line. No call-site churn.

  **Landmine to carry into Phase 4 (this is the whole reason D-08 is written at length):** when Phase 4 adds the block entity, implement `EntityBlock` on the existing `HorizontalDirectionalBlock` subclass, or — if switching to `BaseEntityBlock` for its helpers — **override `getRenderShape()` to return `RenderShape.MODEL`**. Switching to `BaseEntityBlock` blindly silently makes the block invisible and simultaneously discards the inherited facing plumbing. Both regressions land at once and will look like a renderer bug.

- **D-09 (registration structure):** A `public static final Block` field is genuinely required, not speculative — the datagen model provider lives in `src/client` and must reference the same block instance that `src/main` registers. So: a small holder class in `src/main/java/transitreport/` (suggested `TransitReportBlocks`) holding the block, its `BlockItem`, and a `register()` method called from `JollyalchemyTransitReport.onInitialize()`.

  **Static-initialization gotcha:** Java does not load a class until it is touched. The holder needs an explicitly-invoked `register()`/`initialize()` method called from `onInitialize()` — relying on static field initialization alone means registration silently never happens. Use the existing `JollyalchemyTransitReport.id(String)` helper for the `ResourceLocation`.

- **D-10 (block properties):** `BlockBehaviour.Properties` with a modest hardness (≈1.5F, bookshelf/copper territory — breakable but not instant), `SoundType.AMETHYST` for a thematic tie to the intended recipe in REQUIREMENTS.md, and **no** `requiresCorrectToolForDrops()` so Phase 3's loot table drops it with any tool.

  **Deliberately not set:** `lightLevel` — REND-05's "emissive/unshaded, legible in a dark room" is a render-layer concern the Phase 4 renderer handles, not world light emission. A block that lights up its surroundings is a different behaviour nobody asked for. Also not set: `noOcclusion()` — the model is a full opaque cube this phase and normal occlusion is correct. Phase 4's oversized quad may want it revisited; that is Phase 4's call, not a guess to make now.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope and requirements
- `.planning/PROJECT.md` — project definition and constraints. Specifically relevant: the **Out of Scope** entry deferring decorative modeling ahead of the texture pipeline (grounds D-03), the **Intended component decomposition** list in Context (superseded for the block itself by D-02), the **Abstraction** constraint (grounds D-06 and D-10), and the **Author background** note (new to Minecraft modding — keep explaining Fabric/Minecraft mechanics where they matter).
- `.planning/REQUIREMENTS.md` — BLOCK-01, BLOCK-02, BLOCK-03 (lines 18-20) and GEN-01, GEN-02 (lines 27-28). The **Crafting Recipe** section explains the amethyst/echo-shard intent behind D-10's sound choice. The traceability table confirms BLOCK-04/05/06 and GEN-03/04/05/06 are Phase 3, grounding D-06's clarification.
- `.planning/ROADMAP.md` — Phase 2 goal, four success criteria, and the Notes paragraph ("`BlockEntityType` registration may be introduced here as plumbing, but nothing renders from it until Phase 4") that D-08 answers. Phase 4's Notes and REND-01 confirm where the block entity actually belongs.

### Prior phase decisions
- `.planning/phases/01-toolchain-verification/01-CONTEXT.md` — D-01/D-03/D-04 define the `runClient` verification protocol still in force (Claude tails the log, user watches the window, the Phase 1 dev world is reused). D-12's rationale explains why `TransitReportLanguageProvider` exists and was deliberately built as the skeleton later phases grow rather than replace — that is what D-07 extends.
- `.planning/phases/01-toolchain-verification/` SUMMARY files and `docs/DEV.md` — TOOL-03's resolution: `configureDataGeneration { client = true }` is load-bearing for this repo's split-source-set datagen entrypoint. Do not remove it; removing it makes `runDatagen` fail with `ClassNotFoundException`.

### Project conventions — read before writing any Minecraft class name
- `.claude/CLAUDE.md` §2 — the **Mojang official vs. Yarn mappings** table. This project uses `loom.officialMojangMappings()`. Nearly every 1.20.1 block tutorial online uses Yarn names that will not compile here. §2 also carries the working practice that when documentation and resolved sources disagree, **the resolved sources win** — use `./gradlew genSources` or `javap` against `.gradle/loom-cache/minecraftMaven/**/minecraft-{common,clientOnly}-*.jar`.
- `docs/DEV.md` — the repo's developer guide: how to run the dev client and datagen, the JDK requirement, and the Phase 1 datagen finding.

### Note on a roadmap/CLAUDE.md naming inconsistency
`.planning/ROADMAP.md` and `.planning/REQUIREMENTS.md` use **Yarn** class names in several places (`NativeImageBackedTexture`, `MinecraftClient.getInstance()`, `Identifier`). `.claude/CLAUDE.md` §2 gives the Mojang-official equivalents this project actually compiles against (`DynamicTexture`, `Minecraft.getInstance()`, `ResourceLocation`). This does not bite Phase 2, which touches none of those types — but it will bite Phases 4, 6, and 7. **CLAUDE.md §2 is authoritative on class names; the roadmap is authoritative on scope.**

</canonical_refs>

<code_context>
## Existing Code Insights

### Scout findings that shape this phase

- **`src/main/generated` is already wired onto the main resource path — verified, not assumed.** `build/resources/main/assets/jollyalchemy-transit-report/lang/en_us.json` exists, which proves `fabricApi { configureDataGeneration }` adds the generated tree as a resource source directory and that its output is packaged and loadable at runtime. This retires the single biggest structural threat to success criterion 3: generated blockstate and model JSON will actually be found by the game rather than sitting inert on disk. **No `sourceSets.main.resources.srcDir` line needs adding to `build.gradle`.**

- **`BaseEntityBlock` overrides `getRenderShape()` and does not extend `HorizontalDirectionalBlock`** — confirmed by `javap` against the cached 1.20.1 Mojang-mappings common jar this session. This is the entire basis of D-08. See D-08 for the Phase 4 landmine.

- **There are no block textures in the repo.** `src/main/resources/assets/jollyalchemy-transit-report/icon.png` is the only image file, and it is the mod-list icon. D-03 means none needs to be added.

- **There are no hand-written block JSON files under `src/main/resources`.** Success criterion 4 ("no hand-written equivalent under `src/main/resources`") therefore needs nothing removed — it only needs nothing created. Worth stating because the natural instinct when a model does not load is to hand-write one; that would fail the criterion silently.

- **Minor cruft, not a Phase 2 problem:** `src/main/generated/.cache/` is being copied into `build/resources/main/.cache/` and therefore into the shipped jar. Harmless (a datagen hash file), but noted so nobody rediscovers it as a bug later.

### Reusable Assets
- `JollyalchemyTransitReport.MOD_ID` and the static `id(String path)` helper returning `ResourceLocation` — the registration entry points for the block, block item, and every generated resource path. Already correct; use them rather than constructing `ResourceLocation` inline.
- `JollyalchemyTransitReport.onInitialize()` — currently logs `"Hello Fabric world!"` and nothing else. This is where D-09's `TransitReportBlocks.register()` call goes.
- `JollyalchemyTransitReportDataGenerator.onInitializeDataGenerator()` — already creates a `FabricDataGenerator.Pack` and calls `pack.addProvider(TransitReportLanguageProvider::new)`. The GEN-01/GEN-02 model provider is a second `pack.addProvider(...)` line following the identical pattern.
- `TransitReportLanguageProvider` (private static nested class in the datagen entrypoint) — already has a working `generateTranslations` override with one entry. D-07 adds one line to it.
- `JollyalchemyTransitReportClient.onInitializeClient()` — still empty. **Not needed this phase.** It is Phase 4's renderer registration hook.

### Established Patterns
- **Split source sets.** `build.gradle` calls `loom { splitEnvironmentSourceSets() }`. `src/main` is common; `src/client` is client-only. The datagen entrypoint deliberately lives in `src/client`, and TOOL-03 proved `client = true` is what makes that work. **Consequence for this phase:** the model provider goes in `src/client` alongside the language provider, and it references the block from `src/main` — which is exactly why D-09's `public static final` holder field is required rather than optional.
- **Mojang official mappings**, not Yarn — `loom.officialMojangMappings()`. See CLAUDE.md §2.
- `options.release = 17` with `sourceCompatibility`/`targetCompatibility = VERSION_17`. Correct, must stay, independent of the JDK 26 daemon that runs Gradle.
- Mod Menu is present as `modLocalRuntime "com.terraformersmc:modmenu:7.2.2"` — dev-only, deliberately kept out of the shipped jar and out of `fabric.mod.json`'s `depends`. `build.gradle` carries an in-file comment warning not to remove it. Preserve it.

### Integration Points
- `src/main/java/transitreport/JollyalchemyTransitReport.java` — `onInitialize()` gains the block-registration call (D-09).
- New: `src/main/java/transitreport/TransitReportBlocks.java` (or equivalent) — the block, its `BlockItem`, and the creative-tab `ItemGroupEvents` hook (D-06, D-09).
- New: `src/main/java/transitreport/block/TransitChartBlock.java` — `extends HorizontalDirectionalBlock` (D-02, D-08).
- `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` — one added `pack.addProvider(...)` for the model provider, and one added line inside `TransitReportLanguageProvider.generateTranslations` (D-07).
- New: a `FabricModelProvider` subclass for GEN-01/GEN-02, in `src/client`, following the existing nested-provider pattern.

### Verification note for the planner
The exact 1.20.1 datagen helper for a horizontal-facing orientable block (in the `BlockModelGenerators` / `ModelTemplates` / `TexturedModel` family) should be confirmed against `./gradlew genSources` output or `javap` against the cached jar — **not** against current Fabric documentation, which describes post-1.21 provider signatures. This is the same class of risk the roadmap flags for Phase 3's `FabricRecipeProvider` shape, and the project's established working practice (CLAUDE.md §2, PROJECT.md Key Decisions) is to settle it from resolved sources.

</code_context>

<specifics>
## Specific Ideas

- The user's phrasing on the creative tab — *"option 1 sounds nice, but I ultimately want this to be also in non creative mode too. creative mode just for testing"* — is a survival-availability concern, not a creative-tab preference. It is fully answered by Phase 3's BLOCK-04 recipe and BLOCK-05 loot table. **If Phase 3 slips or gets reordered, this is the requirement the user actually cares about**; the creative tab is scaffolding they have explicitly framed as temporary.
- The display name "Transit Chart" was chosen over both "Transit Display" (PROJECT.md's own suggestion) and "Transit Report" (which matches the mod id, package root, and repo name). The user preferred the Human Design term for the thing on the face. Downstream agents should not "correct" this back toward the repo naming.
- Consistency mattered enough to the user that they extended the name choice to the registry id and class names rather than accepting a split between what players read and what the code calls it (D-02).
- Per PROJECT.md's Author background note and Phase 1's `<specifics>`: the user is an experienced software engineer but new to Minecraft mod development. Keep explaining Minecraft- and Fabric-specific mechanics where they matter — blockstates, creative tab registration, datagen providers, source sets. General software engineering needs no explanation. The creative-tab-vs-survival clarification in D-06 is an example of the kind of explanation that was genuinely useful.

</specifics>

<deferred>
## Deferred Ideas

- **Real block artwork.** D-03 borrows furnace textures. Authoring the block's actual look is deliberately deferred by PROJECT.md's Out of Scope list until images are updating on the block — realistically after Phase 7, once the thing it is displaying is real.
- **Dedicated mod creative tab.** Rejected for this phase by D-06 as unjustified for a single block. The natural trigger to revisit is a second block ever existing, which is not on the v1 roadmap.
- **F3 blockstate verification as a second independent check on BLOCK-03.** Offered and declined (D-05). Worth reaching for if Phase 4's renderer turns out to be orienting the chart wrongly — it distinguishes a bad stored state from a bad renderer in one look.
- **`.cache/` directory shipping inside the jar.** Cosmetic packaging nit found while scouting, unrelated to any v1 requirement. Fix whenever the jar is first built for real distribution to the private server.

</deferred>

---

*Phase: 2-Block Exists and Places*
*Context gathered: 2026-09-08*

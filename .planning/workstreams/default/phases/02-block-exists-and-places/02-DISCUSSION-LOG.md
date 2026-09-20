# Phase 2: Block Exists and Places - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-08
**Phase:** 2-Block Exists and Places
**Areas discussed:** Making facing visible, Creative tab placement

---

## Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Block identity & naming | Registry id and class names — permanent, becomes JSON filenames, translation keys, and every later phase's import | |
| Making facing visible | How all four orientations become observably different; borrow vanilla textures vs. author PNGs | ✓ |
| Creative tab placement | Vanilla tab vs. dedicated mod tab | ✓ |
| Block entity now or Phase 4 | Whether to pull `BlockEntityType` plumbing forward, and the `BaseEntityBlock` INVISIBLE trap that comes with it | |

**Notes:** Block identity and block-entity timing were left to Claude's discretion. Block identity partly returned later anyway — the display-name choice inside the Creative tab area made the registry-id question worth asking directly rather than deciding silently.

---

## Making facing visible

### Q1: Where do the block's textures come from this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| Borrow vanilla textures | Point the generated model at `minecraft:block/...` paths. Zero art, zero new files, facing instantly observable. PROJECT.md defers visual polish until images update on the block | ✓ |
| Author simple PNGs now | Draw 2-3 placeholder PNGs. More ownership of the look, but throwaway — Phase 4 covers the face with a rendered chart | |
| Reuse the existing icon.png | Copy the mod icon into the block texture path as the front face, vanilla for the rest | |

**User's choice:** Borrow vanilla textures

---

### Q2: Which vanilla texture set?

| Option | Description | Selected |
|--------|-------------|----------|
| Furnace | `furnace_front` / `furnace_side` / `furnace_top`. Unmistakable arched opening; the exact set vanilla's orientable-block model template was built around | ✓ |
| Observer | `observer_front` / `observer_side` / `observer_top`. Large staring eye — most visually obvious front in the game, thematically apt, but has a distinct back too | |
| Amethyst + distinct front | `amethyst_block` sides/top with a contrasting front. Ties to the intended Amethyst/Echo Shard recipe, but mixing texture families may read as incoherent | |

**User's choice:** Furnace

---

### Q3: Which way does the front point when placed?

| Option | Description | Selected |
|--------|-------------|----------|
| Toward the player | Furnace/chest convention, `getNearestLookingDirection().getOpposite()`. Place against a wall and the face looks back at you. Matches "hangs on a wall" and what Phase 4's renderer wants | ✓ |
| Away from the player | Piston/observer convention. Placing against a wall would bury the chart in the wall | |
| You decide | Claude picks and records rationale | |

**User's choice:** Toward the player

---

### Q4: How do we prove facing is observably different in all four cases?

| Option | Description | Selected |
|--------|-------------|----------|
| F3 blockstate + visual, both | Four blocks from four directions; F3 confirms `facing=` is stored (BLOCK-03), window confirms the model rotates (GEN-01). Two distinct failure modes | |
| Visual only | Four blocks from four directions, confirm four different front orientations. Faster; a correct-looking model with wrong stored state could slip into Phase 4 | ✓ |
| You decide | Claude picks the protocol | |

**User's choice:** Visual only

**Notes:** The residual risk was stated when the option was offered and accepted knowingly. Recorded in CONTEXT.md D-05 rather than dropped.

---

## Creative tab placement

### Q1: Which creative inventory group?

| Option | Description | Selected |
|--------|-------------|----------|
| Vanilla Functional Blocks | One line via `ItemGroupEvents.modifyEntriesEvent(CreativeModeTabs.FUNCTIONAL_BLOCKS)`. Zero new registration, sits next to furnaces and lecterns | ✓ |
| Dedicated mod tab | `FabricItemGroup.builder()` with its own icon and translation key. More discoverable, but speculative for a one-block mod | |
| Both | Mod tab plus injection into Functional Blocks. Duplicate creative entries are usually a nuisance | |

**User's choice (free text):** *"optgion 1 sounds nice, but I ultimately want this to be also in non creative mode too. creative mode just for testing"*

**Notes:** This is a survival-availability concern, not a creative-tab preference. Clarified during discussion that the two mechanisms are independent — survival obtainability comes from the crafting recipe (BLOCK-04) and loot table (BLOCK-05), both already scoped as Phase 3, the very next phase. The reading was reflected back to the user before continuing. Captured in CONTEXT.md D-06 and flagged in `<specifics>` as the requirement the user actually cares about if Phase 3 ever slips.

---

### Q2: Add the block-name translation now, or leave it raw until Phase 3?

| Option | Description | Selected |
|--------|-------------|----------|
| Add the name now | One line in the existing `TransitReportLanguageProvider`. Creative tab and hotbar read properly during Phase 2 verification. Phase 3 still owns the tooltip and the rest of GEN-05 | ✓ |
| Leave it raw until Phase 3 | Keeps the phase boundary clean; raw key visible in the creative menu for one phase | |
| You decide | Claude picks and records rationale | |

**User's choice:** Add the name now

---

### Q3: What should the block be called in-game?

| Option | Description | Selected |
|--------|-------------|----------|
| Transit Display | Plain and descriptive. Matches PROJECT.md's suggested `TransitDisplayBlock` and the project title | |
| Transit Report | Matches the mod id, package root `transitreport`, and repo name — the naming already in the codebase | |
| Transit Chart | Leans on the Human Design term — the thing on the face is literally a transit chart | ✓ |

**User's choice:** Transit Chart

---

### Q4: Should the registry id and Java class names follow "Transit Chart"?

Asked because the display-name choice bore directly on the Block-identity area the user had left to Claude's discretion, and the decision is costly to reverse.

| Option | Description | Selected |
|--------|-------------|----------|
| Follow the display name | Registry id `transit_chart`, class `TransitChartBlock`, later `TransitChartBlockEntity` / `TransitChartRenderer`. Diverges from PROJECT.md's suggestion, which explicitly says names are suggestions | ✓ |
| Keep PROJECT.md's names | Registry id `transit_display`, class `TransitDisplayBlock`, matching the written component decomposition. Deliberate split between what players read and what the code calls it | |
| You decide | Claude picks and records rationale | |

**User's choice:** Follow the display name

**Notes:** Consistency between the in-game name and the source mattered enough to the user to override PROJECT.md's suggested decomposition names. Recorded in CONTEXT.md D-02 with a note that this supersedes PROJECT.md for the block only — `TransitApiClient`, `TransitTextureManager`, `TransitRefreshScheduler`, and `TransitConfig` are unaffected.

---

## Claude's Discretion

Two of the four offered areas were not selected. Claude's calls, recorded as CONTEXT.md D-08 through D-10:

- **D-08 — Block entity timing:** defer entirely to Phase 4. Grounded in a `javap` check against the cached 1.20.1 Mojang-mappings jar confirming `BaseEntityBlock.getRenderShape()` (returns `INVISIBLE` on 1.20.1) and that `BaseEntityBlock` does not extend `HorizontalDirectionalBlock`. Includes an explicit landmine note for Phase 4.
- **D-09 — Registration structure:** a `TransitReportBlocks` holder class with an explicitly-invoked `register()` call from `onInitialize()`. Required rather than speculative because the `src/client` datagen provider must reference the block instance registered in `src/main`.
- **D-10 — Block properties:** ≈1.5F hardness, `SoundType.AMETHYST`, no `requiresCorrectToolForDrops()`. Deliberately not setting `lightLevel` (REND-05 is a render-layer concern, not world light) or `noOcclusion()` (Phase 4's call).

Block identity was also initially left to discretion but was substantially decided by the user in Creative-tab Q3 and Q4.

---

## Deferred Ideas

- **Real block artwork** — deferred by PROJECT.md's Out of Scope list until images are updating on the block; realistically post-Phase 7.
- **Dedicated mod creative tab** — rejected for this phase as unjustified for one block. Revisit only if a second block ever exists.
- **F3 blockstate verification as a second check on BLOCK-03** — offered and declined. Worth reaching for if Phase 4's renderer orients the chart wrongly.
- **`.cache/` directory shipping inside the jar** — cosmetic packaging nit found while scouting; unrelated to any v1 requirement. Fix when the jar is first built for real distribution.

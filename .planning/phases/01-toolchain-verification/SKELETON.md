# Walking Skeleton — Human Design Transit Display

**Phase:** 1
**Generated:** 2026-09-07

> **Translation note.** The canonical Walking Skeleton checklist is written in web-application terms —
> project scaffold, routing, one real database read/write, one real UI interaction, a dev deployment.
> This project is a Minecraft Fabric mod, and several of those elements have no honest counterpart. This
> document says so explicitly where that is the case rather than inventing a database or an HTTP route
> that does not exist in Phase 1. The skeleton element that *does* translate cleanly is the one that
> matters most here: an end-to-end path from source, through the build, into a running instance of the
> real target application, with a real artifact produced at each end.

## Capability Proven End-to-End

A developer can run one command and get a real, playable Minecraft 1.20.1 window with this mod loaded
into it and a saved world they can re-enter, and run a second command that turns provider code into
resource files on disk.

That is two thin end-to-end paths, and together they are the whole development loop every later phase
depends on:

- **Runtime path:** `src/main` + `src/client` source → Loom build → Fabric Loader → mod entrypoint runs
  inside a live game → a world loads → `run/saves/gsd-dev` exists on disk.
- **Build-time path:** datagen entrypoint → `FabricLanguageProvider` → `runDatagen` →
  `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` exists on disk, and provably
  regenerates.

## Architectural Decisions

Decisions recorded here are the ones later phases build on and should not re-litigate.

| Decision | Choice | Rationale |
|---|---|---|
| Target platform | Minecraft Java Edition 1.20.1, Fabric Loader 0.19.5, Fabric API 0.92.12+1.20.1 | Fixed project constraint; the 1.20.1 mod ecosystem is what this milestone targets |
| Build tooling | Gradle 9.5.1 wrapper + Fabric Loom `net.fabricmc.fabric-loom-remap` 1.17-SNAPSHOT | `-remap` is the correct plugin id for obfuscated Minecraft versions (everything through 1.21.11); verified building 1.20.1 in this repo |
| Mappings | `loom.officialMojangMappings()` — Mojang official, not Yarn | Already configured. Every class name in this project follows `.claude/CLAUDE.md` section 2, never tutorial/Yarn names. This is the single largest source of wasted effort available in the milestone |
| Bytecode target vs. build JDK | Mod targets Java 17 (`options.release = 17`); the Gradle daemon runs on JDK 17+ | Two independent settings. Minecraft 1.20.1 requires Java 17 at runtime; Loom 1.17 requires a newer JDK to run Gradle. The daemon JDK is machine-local and never pinned in the tracked `gradle.properties` — CI builds on ubuntu-24.04 with JDK 25 |
| Source-set layout | `loom { splitEnvironmentSourceSets() }` — `src/main` common, `src/client` client-only | Already configured. Load-bearing for later phases: the renderer and texture pipeline are client-only, while `TransitConfig` must stay free of client imports so it can live in `src/main` |
| Mod identity | id `jollyalchemy-transit-report` (never changes); display name `Human Design Transit Display` | The id is load-bearing across entrypoint references, mixin config filenames, the `assets/jollyalchemy-transit-report/` resource path, and `MOD_ID`. Only the display name is project-facing |
| Static resources | Fabric Data Generation into `src/main/generated`, tracked in git | Never hand-written. Blockstates, models, recipes, loot tables, and translations are all generated output from Phase 2 onward |
| Verification environment | The Loom dev client (`./gradlew runClient`), working directory `run/` | Never the developer's installed `%APPDATA%\.minecraft`. Installing a built jar into the real launcher is a distribution concern for the private-server milestone |
| Documentation home | `docs/DEV.md`, repo-local | Survives context resets and is findable by a human, unlike anything buried in `.planning/` |

## Stack Touched in Phase 1

- [x] **Project scaffold** — build (`build.gradle`, Gradle wrapper), mod manifest (`fabric.mod.json`), both mixin configs, and both entrypoint classes are exercised and proven to build.
- [x] **Routing** — *no honest counterpart.* A Fabric mod has no request router. The nearest structural equivalent is the `fabric.mod.json` `entrypoints` map, which dispatches `main`, `client`, and `fabric-datagen` to their classes; this phase proves the `main` and `fabric-datagen` entrypoints both actually fire.
- [ ] **Database — one real read and one real write** — *no counterpart in this project at all.* There is no database in the architecture and there never will be: images are transient state, PROJECT.md explicitly excludes disk caching and storing bytes in block-entity NBT or the world save. The closest real persistence in this phase is the game writing `run/saves/gsd-dev/level.dat` and datagen writing a tracked JSON file — both real filesystem writes, neither a database.
- [x] **UI — one interactive element wired to real code** — a human opens the in-game Mods screen and reads the mod's display name straight out of the tracked manifest, then creates and enters a world. That is the only user interface Phase 1 has; the block's own rendered face arrives in Phase 4.
- [x] **Deployment — documented local full-stack run command** — `./gradlew runClient` and `./gradlew runDatagen`, written down in `docs/DEV.md`. There is no dev *environment* to deploy to: the target is a game the author runs locally, and distribution to the private server is a later milestone.

## Out of Scope (Deferred to Later Slices)

Explicitly not in the skeleton. This list exists so later phases do not re-open Phase 1's minimalism:

- Any block, item, block entity, or registration of any kind (Phase 2).
- Any recipe, loot table, or tooltip (Phase 3).
- Any renderer, texture, render layer, or GL call (Phases 4 and 6).
- Any HTTP client, config file, or network I/O (Phase 5).
- Multiplayer, server authority, or client synchronization (deferred past v1 entirely).
- Reconfiguring Loom's asset path to share the developer's installed Minecraft assets — rejected as poor risk-for-reward; Loom already holds its own complete copy.
- Installing a built jar into the real Minecraft launcher — deferred to the private-server distribution milestone; `docs/DEV.md` reserves a heading for it.
- Licensing decisions. `CC0-1.0` in the manifest and the repo's `LICENSE` currently agree with each other, so nothing is misstated; this is a distribution question, not a verification one.

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural
decisions. Two tracks branch off Phase 1 and rejoin at Phase 7.

**Track A — display:**
- Phase 2: a player takes the block from the creative inventory and places it, facing the way they faced.
- Phase 3: a player crafts it from dirt, breaks it back into itself, and reads its translated name and tooltip.
- Phase 4: a placed block draws a large, self-lit, correctly-oriented bundled image on its face.
- Phase 6: that image can be swapped at runtime from arbitrary PNG bytes without leaking GPU textures.

**Track B — data (depends only on Phase 1):**
- Phase 5: the mod reads a base URL and interval from config and fetches PNG bytes off-thread.

**Joined:**
- Phase 7: a downloaded chart appears on a placed block — the first moment the two tracks meet.
- Phase 8: the chart keeps itself current on a configurable cadence.
- Phase 9: API misbehavior degrades gracefully instead of blanking, spamming, or stalling.
- Phase 10: right-click refreshes on demand, and a client command repoints the API without a restart.

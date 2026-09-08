# Phase 1: Toolchain Verification - Pattern Map

**Mapped:** 2026-09-07
**Files analyzed:** 8
**Analogs found:** 7 / 8

This is a template-cleanup phase, not a greenfield-feature phase. Nearly every "new" file is actually an existing template file being trimmed or filled in — so most analogs are the files themselves (before-state -> after-state), not a different file elsewhere in the tree. The one genuinely new capability (a `FabricLanguageProvider` registration) has no in-repo analog and must be built from the Fabric datagen API shape directly.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `src/main/resources/fabric.mod.json` | config | transform (edit-in-place) | itself (current template values) | exact |
| `src/main/resources/jollyalchemy-transit-report.mixins.json` | config | transform (edit-in-place) | itself | exact |
| `src/client/resources/jollyalchemy-transit-report.client.mixins.json` | config | transform (edit-in-place) | itself | exact |
| `src/main/java/transitreport/mixin/ExampleMixin.java` (delete) | middleware (mixin) | event-driven | n/a — deletion, no replacement file | exact (deletion target) |
| `src/client/java/transitreport/client/mixin/ExampleClientMixin.java` (delete) | middleware (mixin) | event-driven | n/a — deletion, no replacement file | exact (deletion target) |
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` | service (datagen entrypoint) | batch (file-I/O) | itself, plus Fabric API `FabricDataGenerator`/`FabricLanguageProvider` shape | role-match |
| `build.gradle` | config | transform (edit-in-place, D-13 experiment) | itself (`fabricApi { configureDataGeneration { ... } }` block) | exact |
| `docs/DEV.md` (new) | utility (documentation) | n/a | `README.md` (tone/audience), `.claude/CLAUDE.md` §1.3/§3/§6 (technical content to summarize) | role-match |

## Pattern Assignments

### `src/main/resources/fabric.mod.json` (config, transform)

**Analog:** itself — current committed template values (read above)

**Current state to edit (full file):**
```json
{
	"schemaVersion": 1,
	"id": "jollyalchemy-transit-report",
	"version": "${version}",
	"name": "jollyalchemy-transit-report",
	"description": "This is an example description! Tell everyone what your mod is about!",
	"authors": [
		"Me!"
	],
	"contact": {
		"homepage": "https://fabricmc.net/",
		"sources": "https://github.com/FabricMC/fabric-example-mod"
	},
	"license": "CC0-1.0",
	"icon": "assets/jollyalchemy-transit-report/icon.png",
	"environment": "*",
	"entrypoints": {
		"main": ["transitreport.JollyalchemyTransitReport"],
		"client": ["transitreport.client.JollyalchemyTransitReportClient"],
		"fabric-datagen": ["transitreport.client.JollyalchemyTransitReportDataGenerator"]
	},
	"mixins": [
		"jollyalchemy-transit-report.mixins.json",
		{ "config": "jollyalchemy-transit-report.client.mixins.json", "environment": "client" }
	],
	"depends": {
		"fabricloader": ">=0.19.5",
		"minecraft": "~1.20.1",
		"java": ">=17",
		"fabric-api": "*"
	}
}
```

**Required edits per CONTEXT.md decisions:**
- `"name"` -> `"Human Design Transit Display"` (D-08). Note: `"id"` stays `jollyalchemy-transit-report` — only the display name changes, do not touch `id`, package names, or the mixin config filenames, since those are load-bearing elsewhere (entrypoints, mixin refs, mod folder structure).
- `"description"` -> drawn from PROJECT.md's Core Value line (D-09).
- `"authors"` -> `["Nate Neibauer"]` (D-09).
- `"contact"` -> remove `"homepage"` key entirely (do not substitute a fake URL); `"sources"` -> the GitHub HTTPS URL for `git@github.com:nneibaue/minecraft-transit-report.git` (D-09).
- `"license"`, `"icon"`, `"environment"`, `"entrypoints"`, `"depends"` — leave untouched (D-10; entrypoints unaffected by this phase's other edits since the datagen provider is added inside the existing entrypoint class, not a new class).
- `"mixins"` array structure stays; only the referenced `.mixins.json` files' *contents* change (see next two files).

---

### `src/main/resources/jollyalchemy-transit-report.mixins.json` (config, transform)

**Analog:** itself

**Current state:**
```json
{
	"required": true,
	"package": "transitreport.mixin",
	"compatibilityLevel": "JAVA_17",
	"mixins": [
		"ExampleMixin"
	],
	"injectors": { "defaultRequire": 1 },
	"overwrites": { "requireAnnotations": true }
}
```

**Required edit (D-07):** empty the `"mixins"` array to `[]`. Leave every other key untouched — `package`, `compatibilityLevel`, `injectors`, `overwrites` are all still valid scaffolding for whichever mixin class lands in a later phase.

---

### `src/client/resources/jollyalchemy-transit-report.client.mixins.json` (config, transform)

**Analog:** itself

**Current state:**
```json
{
	"required": true,
	"package": "transitreport.client.mixin",
	"compatibilityLevel": "JAVA_17",
	"client": [
		"ExampleClientMixin"
	],
	"injectors": { "defaultRequire": 1 },
	"overwrites": { "requireAnnotations": true }
}
```

**Required edit (D-07):** empty the `"client"` array to `[]` (note: this file uses key `"client"`, not `"mixins"`, unlike the main-set config above — do not conflate the two key names when editing).

---

### Deletion: `src/main/java/transitreport/mixin/ExampleMixin.java` and `src/client/java/transitreport/client/mixin/ExampleClientMixin.java`

**Pattern:** straight file deletion, no replacement. Both currently have empty `@Inject` bodies (verified above — `MinecraftServer.loadLevel()` and `Minecraft.run()` respectively, both HEAD-injected, both no-ops). After deletion, also confirm the now-empty `mixin/` package directories don't need a placeholder — Java has no issue with an empty package directory being absent entirely; if the directory becomes empty, git will not track it, which is fine (no `.gitkeep` needed since nothing else lives there yet).

**Order of operations:** delete the `.java` files and empty the JSON arrays (above) together — a dangling class reference in a mixins.json with a still-existing but stale array entry, or vice versa, is exactly the ambiguous-startup-error scenario D-07 is designed to avoid.

---

### `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` (service/datagen entrypoint, batch/file-I/O)

**Analog:** itself (current empty body) — no in-repo `FabricLanguageProvider` registration exists yet to copy from; this is the "No Analog Found" case for the *provider* specifically, though the *entrypoint class* itself is being edited in place.

**Current state (full file):**
```java
package transitreport.client;

import net.fabricmc.fabric.api.datagen.v1.DataGeneratorEntrypoint;
import net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator;

public class JollyalchemyTransitReportDataGenerator implements DataGeneratorEntrypoint {
	@Override
	public void onInitializeDataGenerator(FabricDataGenerator fabricDataGenerator) {

	}
}
```

**Required addition (D-12):** register a `FabricLanguageProvider` via `fabricDataGenerator.createPack()` and `pack.addProvider(...)`, with at least one real translation entry (e.g. a lang key relevant to the mod, such as an item group or the mod name itself under `itemGroup.jollyalchemy-transit-report` or similar — exact key is a planning-time detail, not this document's call). Standard Fabric 1.20.1 datagen shape:

```java
FabricDataGenerator.Pack pack = fabricDataGenerator.createPack();
pack.addProvider(TransitReportLangProvider::new);
```

with a nested/sibling class extending `FabricLanguageProvider`, overriding `generateTranslations(RegistryWrapper.WrapperLookup, TranslationBuilder)` (constructor/method shape must be confirmed against resolved sources per D-12's instruction — `./gradlew genSources` or `javap` against the cached jar — not against current web docs, since API shape has shifted across Fabric API versions).

**No in-repo analog exists for this provider registration** — there is no other datagen provider anywhere in `src/`. Planner/executor should treat the Fabric API's own `FabricLanguageProvider` abstract class (resolved via genSources) as the source of truth for the exact constructor signature on this pinned `fabric_api_version=0.92.12+1.20.1`, rather than copying a signature from a newer-version tutorial (per `.claude/CLAUDE.md`'s general "resolve mapping/API ambiguity against resolved sources, not docs" convention referenced in D-12/D-14).

---

### `build.gradle` (config, transform — D-13 experiment site)

**Analog:** itself

**Current relevant block (lines ~26-30):**
```groovy
fabricApi {
	configureDataGeneration {
		client = true
	}
}
```

**Required procedure (D-13):** this is not a one-shot edit — it's an observe/diff/decide loop:
1. Run `./gradlew tasks --all` with the block as-is (`client = true` present), capture datagen-related task names.
2. Change to bare `configureDataGeneration()` (remove the `client = true` line, keep the empty block), re-run `./gradlew tasks --all`, diff.
3. With the D-12 language provider registered, run `runDatagen` under both configurations and diff actual output under `src/main/generated`.
4. Keep whichever form is proven necessary; if no observable difference, land on the bare `configureDataGeneration()` form (decision rule in D-13) and record the finding in `docs/DEV.md` and the phase SUMMARY — do not silently keep the flag "just in case."

**Relevant context:** `build.gradle` also calls `loom { splitEnvironmentSourceSets() }` (line ~13-14) and the datagen entrypoint class lives in the **client** source set (`src/client/java/...DataGenerator.java`) — this is the live hypothesis D-13 flags: `client = true` may be what makes the client source set's datagen entrypoint visible at all, not merely a no-op flag. Do not assume STACK.md §1.4 ("current, correct, already working") without running the actual diff — that finding is exactly what conflicts with PITFALLS.md and what this phase must settle by observation.

---

### `docs/DEV.md` (new file — utility/documentation)

**Analog:** `README.md` (repo root, for baseline tone/structure of a project doc) + `.claude/CLAUDE.md` (source of the technical content to summarize, especially §1.3 JDK split, §3 HTTP client threading model is NOT needed here but §6 mock server and the general "why JDK version matters" framing is)

No direct analog exists for a dev-workflow doc in this repo yet (README.md is currently the stock Fabric template README, not project-specific — check its current content before treating it as a strong pattern source, it likely still needs its own separate rewrite outside this phase's scope).

**Required content (D-11):**
- How to run the dev client: `./gradlew runClient`
- How to run datagen: `./gradlew runDatagen`
- The JDK requirement and why it matters: summarize `.claude/CLAUDE.md` §1.3 (build-time JDK 17+ vs. mod's Java 17 bytecode target) and the D-06 finding (JDK 26 attempted first; record whether it worked or Temurin 21 was required, per the hard-stop rule)
- What "verified" means for this phase: restate D-04's two-part criterion (mod listed on Mods screen AND user stands in a creative superflat world) as the durable definition-of-done, since this doc outlives the phase
- The `client = true` finding from the D-13 experiment (see `build.gradle` entry above) — record precisely what it does or doesn't do on this Loom/Fabric API version pairing
- A placeholder/stub section for the deferred "install into real Minecraft" walkthrough (per Deferred Ideas — do not write the full walkthrough now, but leave a heading so it isn't lost)

## Shared Patterns

### Mod ID vs. display name discipline
**Source:** `src/main/resources/fabric.mod.json` (`"id"` vs `"name"` fields)
**Apply to:** any edit touching `fabric.mod.json`
Only `"name"` (the Mods-screen display string) changes to "Human Design Transit Display" per D-08. `"id": "jollyalchemy-transit-report"` is load-bearing across entrypoint class references, mixin config filenames, the `assets/jollyalchemy-transit-report/` resource path, and `MOD_ID` in `JollyalchemyTransitReport.java` — none of those change in this phase.

### Mixin config array key naming inconsistency
**Source:** `src/main/resources/jollyalchemy-transit-report.mixins.json` (key `"mixins"`) vs. `src/client/resources/jollyalchemy-transit-report.client.mixins.json` (key `"client"`)
**Apply to:** both D-07 edits
These two files use *different* array key names for what is conceptually the same "list of mixin classes" — don't copy one file's edit onto the other verbatim; each needs its own correctly-named array emptied.

### "Resolve against sources, not docs" convention
**Source:** `.claude/CLAUDE.md` general convention (invoked explicitly by D-12, D-13, D-14)
**Apply to:** `FabricLanguageProvider` signature (D-12) and the `client = true` behavior (D-13)
Both of these are places where current public documentation is known or suspected to describe a different Fabric API version than what's pinned here (`fabric_api_version=0.92.12+1.20.1`). Resolve via `./gradlew genSources` / `javap` against the cached jar, or by empirical build/run observation — never by copying a snippet from current fabricmc.net docs.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `FabricLanguageProvider` registration inside `JollyalchemyTransitReportDataGenerator.java` | service (datagen provider) | batch/file-I/O | No datagen provider of any kind exists anywhere in this repo yet — this is the first one. Must be built from the Fabric API's `FabricLanguageProvider` abstract class shape (resolved via genSources against the pinned `fabric_api_version`), not copied from an in-repo file. |
| `docs/DEV.md` | utility/documentation | n/a | No existing project-specific dev-workflow doc in this repo; `README.md` is still the unmodified Fabric template README and is not a strong content analog, only a loose structural one. |

## Metadata

**Analog search scope:** entire repo (`git ls-files`, excluding `.planning/`) — full tracked source tree, since this phase's file count is small (8 files, all under `src/`, `build.gradle`, plus one new doc).
**Files scanned:** `build.gradle`, `gradle.properties`, `src/main/resources/fabric.mod.json`, `src/main/resources/jollyalchemy-transit-report.mixins.json`, `src/client/resources/jollyalchemy-transit-report.client.mixins.json`, `src/main/java/transitreport/JollyalchemyTransitReport.java`, `src/main/java/transitreport/mixin/ExampleMixin.java`, `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java`, `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java`, `src/client/java/transitreport/client/mixin/ExampleClientMixin.java`
**Pattern extraction date:** 2026-09-07

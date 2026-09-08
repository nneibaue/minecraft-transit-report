---
phase: 01-toolchain-verification
plan: 02
subsystem: infra
tags: [fabric, datagen, fabric-data-generation-api-v1, lang-provider, minecraft-1.20.1]

# Dependency graph
requires:
  - phase: 01-toolchain-verification (plan 01)
    provides: "A working, launchable Fabric dev client on JDK 26, and the mixin/fabric.mod.json cleanup that keeps the client startup log unambiguous"
provides:
  - "A registered FabricLanguageProvider in the datagen entrypoint, resolved against the pinned Fabric API jar rather than documentation"
  - "A tracked, provably-regenerable src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json"
  - "TOOL-02 satisfied by a file on disk, not by runDatagen's exit code alone"
  - "The text.jollyalchemy-transit-report.refreshing translation key skeleton that GEN-05 (Phase 3) and REF-06 (Phase 10) grow/consume"
affects: [01-03, "any future phase adding a datagen provider (blockstates, models, recipes, loot tables)"]

# Actuals (#2632)
actuals:
  tokens: 400
  tasks: 2
  commits: 2
plan_head_before: 0251881cd209bf0ae464104646377aaa27deae6d

# Tech tracking
tech-stack:
  added: []
  patterns: ["Datagen providers resolved against javap output from the pinned Fabric API jar in ~/.gradle/caches, never against current Fabric documentation (which describes a later API shape)"]

key-files:
  created:
    - src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
    - src/main/generated/.cache/754c0c05d3f58f02b81f8cc2acfbdb828510a84a
  modified:
    - src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java

key-decisions:
  - "No outputDirectory override was needed — runDatagen wrote directly to src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json, the exact path TOOL-02 and ROADMAP Phase 1 criterion 2 require."
  - "The datagen .cache hash file is also tracked (src/main/generated is not gitignored), since the plan directive was to commit the whole generated tree, not just the lang file."

patterns-established:
  - "Nested static provider classes inside the DataGeneratorEntrypoint class for single-purpose providers with no dedicated file, per the project's anti-premature-abstraction constraint."

requirements-completed: [TOOL-02]

coverage:
  - id: D1
    description: "A FabricLanguageProvider is registered in the datagen entrypoint, with its constructor and generateTranslations signature resolved from the pinned fabric-data-generation-api-v1 jar via javap, not from documentation."
    requirement: "TOOL-02"
    verification:
      - kind: other
        ref: "javap -classpath <pinned jar> net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider — output recorded below, matches the plan's stated shapes exactly"
        status: pass
      - kind: other
        ref: "./gradlew build exits 0 (the real signature check)"
        status: pass
    human_judgment: false
  - id: D2
    description: "./gradlew runDatagen exits 0 and writes src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json with the expected key/value, at the exact required path with no outputDirectory override needed."
    requirement: "TOOL-02"
    verification:
      - kind: other
        ref: "test -f src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json && node -e JSON key/value assertion"
        status: pass
    human_judgment: false
  - id: D3
    description: "The generated file is provably regenerable (not hand-written into the generated tree) and is tracked in git."
    requirement: "TOOL-02"
    verification:
      - kind: other
        ref: "delete-and-regenerate diff: rm -rf src/main/generated && ./gradlew runDatagen && diff -u <pre-deletion copy> <regenerated file> — zero diff hunks, byte-identical, .cache hash filename also identical"
        status: pass
      - kind: other
        ref: "git ls-files --error-unmatch src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json"
        status: pass
    human_judgment: false

duration: 12min
completed: 2026-09-08
status: complete
---

# Phase 1 Plan 2: Datagen Language Provider Summary

**Registered a `FabricLanguageProvider` (signature resolved via `javap` against the pinned Fabric API jar, not docs) and proved `./gradlew runDatagen` writes a real, tracked, byte-for-byte-regenerable `en_us.json` at the exact path TOOL-02 requires.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-09-08T07:19:00Z (approx)
- **Completed:** 2026-09-08T07:31:35Z
- **Tasks:** 2
- **Files modified:** 3 (1 source file, 2 generated files)

## Accomplishments

- `JollyalchemyTransitReportDataGenerator.onInitializeDataGenerator` now calls `fabricDataGenerator.createPack()` and registers a nested `TransitReportLanguageProvider` (extends `FabricLanguageProvider`) via `pack.addProvider(...)`.
- The provider adds exactly one translation entry: `text.jollyalchemy-transit-report.refreshing` → `Refreshing transit chart...`, keyed off `JollyalchemyTransitReport.MOD_ID` rather than a repeated literal.
- `./gradlew runDatagen` exits 0 and writes `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` directly at the required path — no `outputDirectory` override was necessary.
- Proved the file is genuinely generated output, not hand-written source: deleted `src/main/generated` entirely, re-ran `runDatagen`, and the file (plus its `.cache` hash sidecar, same filename) reappeared byte-identical.
- Both the lang file and the datagen `.cache` hash file are tracked in git (`src/main/generated` is not gitignored in this repo, confirmed by the plan's grounded fact and re-confirmed by inspecting `.gitignore`).

## `javap` Resolution (Task 1, Step 1)

Ran against `~/.gradle/caches/modules-2/files-2.1/net.fabricmc.fabric-api/fabric-data-generation-api-v1/12.4.0+238242b777/.../fabric-data-generation-api-v1-12.4.0+238242b777.jar` (the non-sources jar, matching `fabric_api_version=0.92.12+1.20.1`):

```
public abstract class net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider implements net.minecraft.class_2405 {
  protected final net.fabricmc.fabric.api.datagen.v1.FabricDataOutput dataOutput;
  protected FabricLanguageProvider(FabricDataOutput);
  protected FabricLanguageProvider(FabricDataOutput, String);
  public abstract void generateTranslations(FabricLanguageProvider$TranslationBuilder);
  public java.util.concurrent.CompletableFuture<?> method_10319(net.minecraft.class_7403);
  public java.lang.String method_10321();
}

public final class net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator$Pack extends net.minecraft.class_2403$class_7856 {
  public <T extends class_2405> T addProvider(FabricDataGenerator$Pack$Factory<T>);
  public <T extends class_2405> T addProvider(FabricDataGenerator$Pack$RegistryDependentFactory<T>);
}

public interface net.fabricmc.fabric.api.datagen.v1.FabricDataGenerator$Pack$Factory<T extends class_2405> {
  public abstract T create(FabricDataOutput);
}

public interface net.fabricmc.fabric.api.datagen.v1.provider.FabricLanguageProvider$TranslationBuilder {
  public abstract void add(String, String);
  public default void add(Item, String);
  public default void add(Block, String);
  ... (other Minecraft-type overloads not applicable here)
  public default void add(Path) throws IOException;
}
```

**Agreement with the plan's stated shapes:** full agreement, no reconciliation needed. `generateTranslations` takes exactly one parameter (`TranslationBuilder`) — no `HolderLookup.Provider` / registry-lookup parameter exists on this Fabric API version, confirming the plan's warning that the 1.21+ two-parameter shape does not apply here. Both constructors are `protected`; the one-argument `FabricDataOutput` form was used, defaulting to `en_us`. `Pack.addProvider` resolves the `Pack.Factory<T>` overload via the `TransitReportLanguageProvider::new` constructor reference. `TranslationBuilder.add(String, String)` is the overload used, as specified.

(Note: `javap` output shows intermediary/obfuscated names like `class_2405` because the raw jar predates Loom's remapping step — this is expected and does not affect the remapped, compiled code, which uses the Mojang-mapped names throughout.)

## Datagen Output Baseline (for plan 01-03)

- **Actual output directory used by `runDatagen`:** `src/main/generated/` — exactly the path TOOL-02 and ROADMAP Phase 1 criterion 2 require. `outputDirectory` was **not** set explicitly; the default from `fabricApi { configureDataGeneration { client = true } }` already resolves here.
- **Full list of files `runDatagen` wrote (this baseline, for 01-03 to diff against):**
  - `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json`
  - `src/main/generated/.cache/754c0c05d3f58f02b81f8cc2acfbdb828510a84a` (datagen's internal cache/hash-tracking file, used to detect stale output on subsequent runs)
- The log line `Caching: total files: 1, old count: 0, new count: 2, removed stale: 0, written: 1` confirms exactly one real output file was produced (the `.cache` file is Minecraft's own datagen bookkeeping, not a second content provider).
- **`client = true` observation for TOOL-03 (informational, not this plan's task):** the datagen run visibly launched a full render-thread client session (LWJGL window init, "Setting user: PlayerNNN", "Indigo" renderer registration, Mod Menu update check) before running the data generator — this is the client-side datagen harness, consistent with the client source set (where this entrypoint lives) being loaded. Plan 01-03 owns the formal client=true vs. bare configureDataGeneration() diff per D-13; this is only the incidental observation from this plan's two runs.

## Task Commits

Each task was committed atomically:

1. **Task 1: Register a language provider in the datagen entrypoint** - `db59b59` (feat)
2. **Task 2: Run data generation, prove regenerability, land tracked files** - `c7530e3` (feat)

**Plan metadata:** (this commit, following SUMMARY creation)

## Files Created/Modified

- `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` - registers `TransitReportLanguageProvider` (nested `FabricLanguageProvider`) via `createPack()`/`addProvider`
- `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` - generated translation file, tracked in git
- `src/main/generated/.cache/754c0c05d3f58f02b81f8cc2acfbdb828510a84a` - datagen's own cache/hash bookkeeping file, tracked alongside the generated tree

## Decisions Made

- Used the one-argument `FabricLanguageProvider(FabricDataOutput)` constructor (defaults to `en_us`) rather than the two-argument language-code overload, since `en_us` is exactly what's needed and matches the plan's Step 2 instruction.
- Committed the datagen `.cache` hash file alongside the lang JSON, since `src/main/generated` as a whole is not gitignored and the plan's Task 2 instruction was to `git add src/main/generated` (the whole tree), not just the lang file specifically.

## Deviations from Plan

None - plan executed exactly as written. The `javap` output matched the plan's stated shapes with zero discrepancies, and `runDatagen` wrote to the exact path expected with no `outputDirectory` correction needed.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TOOL-02 is satisfied by direct observation: a real file exists under `src/main/generated`, is tracked in git, and is proven regenerable byte-for-byte.
- Plan 01-03 (the `client = true` / TOOL-03 experiment and `docs/DEV.md`) now has a concrete baseline of what `runDatagen` produces with the flag present and a provider registered — see the "Datagen Output Baseline" section above — to diff its bare-`configureDataGeneration()` experiment against.
- No blockers for 01-03.

---

*Phase: 01-toolchain-verification*
*Completed: 2026-09-08*

## Self-Check: PASSED

- FOUND: src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
- FOUND: src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
- FOUND: .planning/phases/01-toolchain-verification/01-02-SUMMARY.md
- FOUND: commit db59b59 (Task 1)
- FOUND: commit c7530e3 (Task 2)
- FOUND: commit 774744e (SUMMARY commit)

---
phase: 01-toolchain-verification
plan: 03
subsystem: infra
tags: [fabric, loom, datagen, configureDataGeneration, gradle, minecraft-1.20.1, documentation]

# Dependency graph
requires:
  - phase: 01-toolchain-verification (plan 01)
    provides: "The JDK 26 D-06 finding and the launched dev client this doc's JDK section and 'what verified means' section record"
  - phase: 01-toolchain-verification (plan 02)
    provides: "The registered FabricLanguageProvider and the datagen output baseline (file list, .cache filename) this plan's experiment diffs against"
provides:
  - "TOOL-03 settled by observation, not by choosing between STACK.md and PITFALLS.md: client = true is load-bearing in this repo's split-source-set layout and is kept"
  - "docs/DEV.md: the repo's first project-specific developer guide, covering the dev loop, the JDK requirement, what verified means for Phase 1, the datagen finding, and a reserved heading for the deferred real-Minecraft install walkthrough"
affects: ["any future phase that runs runClient or runDatagen for verification", "the private-server distribution milestone that fills in the deferred install section"]

# Actuals (#2632)
actuals:
  tokens: 2036
  tasks: 2
  commits: 1
plan_head_before: 2f9af26

# Tech tracking
tech-stack:
  added: []
  patterns: ["docs/DEV.md as the repo-local, greppable-heading developer guide that outlives individual phases; later phases append sections rather than creating new doc files"]

key-files:
  created:
    - docs/DEV.md
  modified: []

key-decisions:
  - "TOOL-03 resolved: configureDataGeneration { client = true } is kept in build.gradle. The task list is identical with or without it, but the bare form makes runDatagen fail outright (ClassNotFoundException on the client-source-set entrypoint class) rather than merely lose functionality — this confirms the D-13 live hypothesis that the flag is what makes the client source set visible to the datagen run under splitEnvironmentSourceSets(), not an inert no-op on this Loom/Fabric API/Minecraft pairing."
  - "build.gradle ends this plan byte-identical to how it started: the experiment edited it twice (bare form, then restored) and the restore matched the original content exactly, so there is no Task-1 commit — the finding is the deliverable, not a diff."

patterns-established:
  - "Toolchain flag questions on this project are settled by a forced delete-and-regenerate diff of actual output, never by task-list comparison alone or by picking between disagreeing research documents."

requirements-completed: [TOOL-03]

coverage:
  - id: D1
    description: "The configureDataGeneration { client = true } question is settled by observation: task lists compared, generated output diffed after a forced delete-and-regenerate under both forms, and the finding (keep the flag) recorded with its reason."
    requirement: "TOOL-03"
    verification:
      - kind: other
        ref: "./gradlew tasks --all --quiet --console=plain (both forms) — identical single 'runDatagen' line; see Datagen Configuration Experiment section below for full command transcript"
        status: pass
      - kind: other
        ref: "./gradlew runDatagen after rm -rf src/main/generated (both forms) — flag-present: exit 0, file written; bare: exit 1, ClassNotFoundException, zero files written"
        status: pass
    human_judgment: false
  - id: D2
    description: "docs/DEV.md exists with all seven required headings, both dev-loop commands, the gsd-dev world name, a concrete JDK version, no machine-specific absolute path, the datagen finding stated with its justification, and is tracked in git."
    requirement: "TOOL-03"
    verification:
      - kind: other
        ref: "Task 2 <verify> block: wc -l >= 40 (142 actual), all 7 heading greps, command/gsd-dev greps, JDK-number regex, Windows-path node check, git ls-files --error-unmatch — all exit 0, see Task Commits section"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-09-08
status: complete
---

# Phase 1 Plan 3: Toolchain Verification — Datagen Flag Experiment and Dev Guide Summary

**Settled TOOL-03 by observation (`client = true` is load-bearing here, not inert, because the datagen entrypoint lives in the client source set under `splitEnvironmentSourceSets()`) and wrote `docs/DEV.md`, the repo's first project-specific developer guide.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-09-08T07:35:00Z (approx)
- **Completed:** 2026-09-08T07:57:00Z (approx)
- **Tasks:** 2
- **Files modified:** 1 (`docs/DEV.md` created; `build.gradle` round-tripped to its original content, no net diff)

## Accomplishments

- Ran the full D-13 observe/diff/decide procedure: captured the datagen-related task list with `client = true` present, captured a clean regenerated output tree, switched to the bare `configureDataGeneration()` form, re-captured both, and diffed everything against the flag-present baseline.
- Discovered the task list is byte-identical between the two forms, but the **actual output is not**: the bare form does not degrade datagen, it makes `runDatagen` fail outright with a `ClassNotFoundException` on the entrypoint class that lives in the client source set, writing zero files.
- Per D-13's decision rule, restored `client = true` since a real observable difference exists, and recorded precisely what it does: it is the reason the client source set (where the datagen entrypoint lives) is visible to the datagen run at all, given this project's `splitEnvironmentSourceSets()` layout.
- Left the working tree clean: final `runDatagen` run under the landed form reproduced the exact tracked `en_us.json` byte-for-byte; the `.cache` bookkeeping file's regeneration timestamp was reverted via `git checkout --` to keep `git status` clean on `src/main/generated`; all scratch files/directories were deleted.
- Wrote `docs/DEV.md` (142 lines) with all seven required headings: dev client, datagen, JDK requirement (recording the D-06 JDK 26 finding), what verified means for Phase 1 (D-04's two-part criterion), the datagen configuration finding above, and a reserved placeholder heading for the deferred real-Minecraft install walkthrough. No machine-specific absolute path was published.

## Datagen Configuration Experiment (Task 1 — full record)

### Step 1 & 3 — task lists, both forms

**With `client = true` present** (`./gradlew tasks --all --quiet --console=plain`, datagen-related lines only):
```
runDatagen - Starts the 'datagen' run configuration
```

**Bare `configureDataGeneration()`** (same command):
```
runDatagen - Starts the 'datagen' run configuration
```

`diff` between the two full task-list captures: **empty, exit 0** — no line added, removed, or renamed under either form.

### Step 2 & 3 — generated output, both forms

**With `client = true` present:** `rm -rf src/main/generated && ./gradlew runDatagen` exited 0. Log tail showed a full client render-thread session (LWJGL window init, `Setting user: Player686`, `Hello Fabric world!`, Indigo renderer registration) followed by:
```
[FabricDataGenHelper] Running data generator for jollyalchemy-transit-report
Starting provider: Human Design Transit Display/Language (en_us)
Human Design Transit Display/Language (en_us) finished after 4 ms
All providers took: 4 ms
Caching: total files: 1, old count: 0, new count: 2, removed stale: 0, written: 1
BUILD SUCCESSFUL in 6s
```
Files produced (matching the 01-02 baseline exactly):
- `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json`
- `src/main/generated/.cache/754c0c05d3f58f02b81f8cc2acfbdb828510a84a`

**Bare `configureDataGeneration()`:** `rm -rf src/main/generated && ./gradlew runDatagen` exited **1**. Relevant excerpt:
```
Caused by: net.fabricmc.loader.api.LanguageAdapterException: java.lang.ClassNotFoundException: transitreport.client.JollyalchemyTransitReportDataGenerator
	at net.fabricmc.loader.impl.util.DefaultLanguageAdapter.create(DefaultLanguageAdapter.java:55)
	at net.fabricmc.loader.impl.entrypoint.EntrypointStorage$NewEntry.getOrCreate(EntrypointStorage.java:124)
	at net.fabricmc.loader.impl.entrypoint.EntrypointContainerImpl.getEntrypoint(EntrypointContainerImpl.java:53)
Caused by: java.lang.ClassNotFoundException: transitreport.client.JollyalchemyTransitReportDataGenerator
	at net.fabricmc.loader.impl.launch.knot.KnotClassLoader.loadClass(KnotClassLoader.java:119)
...
> Task :runDatagen FAILED
BUILD FAILED in 9s
```
`find src/main/generated` after this run returned only the bare directory itself — **zero files written**.

`diff -r` between the flag-present generated tree and the bare-form attempt: not meaningfully computable, since the bare form produced no `assets/` or non-empty `.cache/` content to diff against at all — the comparison is "a full generated tree" vs. "nothing."

### The four observations (explicit, per the plan's acceptance criteria)

1. **Does `runDatagen` exist under the bare form?** Yes — the task itself is still registered and listed by `./gradlew tasks --all`.
2. **Did the datagen-related task list change?** No — byte-identical between both forms.
3. **Does `runDatagen` exit 0 under the bare form?** No — it exits 1 with `BUILD FAILED`.
4. **Is the generated output identical between forms?** No — the flag-present form writes the expected `en_us.json` and `.cache` file; the bare form writes nothing at all, because the run fails before any provider can execute.

### Decision (Step 4)

Per D-13's rule ("If any observable difference exists, restore the flag and record precisely what it changes. Do not split the difference"): a difference exists — and it is not subtle, it is a hard failure — so `client = true` is **restored and kept**. `build.gradle` ends this plan with exactly the content it had before this plan started; there is no committed diff to it, because the landed form is the form it already carried.

**Why the flag matters here specifically:** this repo calls `loom { splitEnvironmentSourceSets() }`, and
`JollyalchemyTransitReportDataGenerator` (the `fabric-datagen` entrypoint) lives in the **client**
source set (`src/client/java/...`). Without `client = true`, the datagen run's classpath does not
include the client source set at all, so Fabric Loader cannot even find the entrypoint class — this
is a complete failure to launch any provider, not a partial loss of some client-only content. This
confirms the specific live hypothesis flagged in D-13 and explains why STACK.md §1.4's "current,
correct, already working" observation held for a reason it did not itself state, while
PITFALLS.md Pitfall 2's documentation-drift observation is also true (Fabric's own docs place the
flag at 1.21.4+) without being the operative fact for this repo's configuration.

### Step 5 — leaving the tree consistent

Final `runDatagen` under the restored (landed) form produced `en_us.json` byte-identical to the
tracked copy (`git diff` on the lang file: empty). The `.cache` hash file's embedded regeneration
timestamp differed (expected — it records wall-clock time of the run) and was reverted with
`git checkout -- src/main/generated/.cache/754c0c05d3f58f02b81f8cc2acfbdb828510a84a` to leave
`git status --porcelain --untracked-files=all -- src/main/generated` empty. All scratch captures
(`/tmp/gsd-scratch/*`) were deleted; nothing from the experiment remains in the repository.

## Task Commits

Each task was committed atomically:

1. **Task 1: Settle the datagen configuration-flag question by observation** — no commit. The experiment ran both configuration forms and landed back on the original `client = true` content with zero net diff to `build.gradle`; the finding itself is the deliverable and is recorded in full above.
2. **Task 2: Write docs/DEV.md** - `850dc86` (docs)

**Plan metadata:** (this commit, following SUMMARY creation)

## Files Created/Modified

- `docs/DEV.md` - new repo-local developer guide: dev loop, JDK requirement, what verified means for Phase 1, the datagen configuration finding, and a reserved heading for the deferred real-Minecraft install walkthrough
- `build.gradle` - edited twice during the experiment (bare form, then restored); ends the plan byte-identical to its starting content, so it carries no commit

## Decisions Made

- **TOOL-03 resolved by observation:** `client = true` is kept. See the Datagen Configuration Experiment section above for the full observation record and reasoning.
- Chose to record the `.cache` bookkeeping file's non-deterministic regeneration timestamp explicitly in `docs/DEV.md` (rather than treating it as noise to ignore), since a future reader diffing the generated tree and seeing that file "always changed" needs to know it is expected bookkeeping, not drift.

## Deviations from Plan

None - plan executed exactly as written. The plan explicitly anticipated the possibility that removing the flag would break datagen entirely ("Treat 'removing it breaks datagen entirely' as a live hypothesis, not an edge case") and that is exactly what was observed; no auto-fix or architectural decision was required beyond following D-13's own decision rule.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TOOL-03 is satisfied by direct observation: both task lists and both generated-output attempts were captured, diffed, and the finding (keep `client = true`, because it is load-bearing for this repo's split-source-set datagen entrypoint) is recorded in this SUMMARY and in `docs/DEV.md`.
- `docs/DEV.md` now exists as the durable, repo-local record of the dev loop, the JDK requirement (D-06), what verified means for Phase 1 (D-04), and this plan's datagen finding — a developer returning to this repo does not need to re-derive or re-litigate any of it.
- The deferred real-Minecraft install walkthrough has a named, reserved heading in `docs/DEV.md` (`## Installing the mod into real Minecraft (deferred)`) so the author's explicit request is not lost; the walkthrough content itself is still deferred to the private-server distribution milestone.
- Phase 1 (Toolchain Verification) is now complete across all three plans (01-01, 01-02, 01-03): TOOL-01, TOOL-02, and TOOL-03 are all satisfied by direct observation, not assumption.
- No blockers for Phase 2.

---

*Phase: 01-toolchain-verification*
*Completed: 2026-09-08*

## Self-Check: PASSED

- FOUND: docs/DEV.md
- FOUND: configureDataGeneration in build.gradle
- FOUND: src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
- FOUND: commit 850dc86 (Task 2)

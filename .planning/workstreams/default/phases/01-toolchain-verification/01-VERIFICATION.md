---
phase: 01-toolchain-verification
verified: 2026-09-08T08:15:00Z
status: passed
score: 8/8 must-haves verified
covered_files:
  - ".gitignore"
  - ".planning/REQUIREMENTS.md"
  - ".planning/ROADMAP.md"
  - ".planning/phases/01-toolchain-verification/01-01-PLAN.md"
  - ".planning/phases/01-toolchain-verification/01-01-SUMMARY.md"
  - ".planning/phases/01-toolchain-verification/01-02-PLAN.md"
  - ".planning/phases/01-toolchain-verification/01-02-SUMMARY.md"
  - ".planning/phases/01-toolchain-verification/01-03-PLAN.md"
  - ".planning/phases/01-toolchain-verification/01-03-SUMMARY.md"
  - ".planning/phases/01-toolchain-verification/01-CONTEXT.md"
  - ".planning/phases/01-toolchain-verification/01-REVIEW.md"
  - "build.gradle"
  - "docs/DEV.md"
  - "src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java"
  - "src/client/resources/jollyalchemy-transit-report.client.mixins.json"
  - "src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json"
  - "src/main/resources/fabric.mod.json"
  - "src/main/resources/jollyalchemy-transit-report.mixins.json"
covered_digest: "v1:sha256:0f24e3d1369ad52236c5d4f3a10d0e4ce83613ef78be14cfa2537f08f7fa08d4"
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: passed
  previous_score: 8/8
  gaps_closed:
    - "CR-01 (Critical, 01-REVIEW.md): Windows Zone.Identifier sidecar files tracked in git and shipping inside the built jar — resolved in commit 0434a60"
    - "WR-01 (Warning, 01-REVIEW.md): fabric.mod.json's fabric-api dependency was unconstrained (\"*\") while gradle.properties pins an exact version — resolved in commit 0434a60"
  gaps_remaining: []
  regressions: []
---

# Phase 1: Toolchain Verification — Verification Report (Re-Verification)

**Phase Goal:** The development loop is proven end to end — the game launches with the mod loaded, and data generation writes files to disk
**Verified:** 2026-09-08T08:15:00Z
**Status:** passed
**Re-verification:** Yes — after code-review remediation (commits `0434a60`, `37d8dd8`)

## Why This Re-Verification Ran

The prior `01-VERIFICATION.md` (2026-09-08T01:15:00Z) attested `passed, 8/8` against a `covered_digest`
that predates two later commits landing real fixes for the two open findings in `01-REVIEW.md`
(CR-01 critical, WR-01 warning). Nothing in the phase's observable truths regressed — the remediation
closed the two known gaps. This report re-attests against current `HEAD` (`37d8dd8`) and independently
re-verifies both fixes rather than trusting the commit messages.

## Independent Remediation Verification

### CR-01 — Zone.Identifier sidecars (was Critical)

| Check | Command | Result |
|---|---|---|
| Tracked in git? | `git ls-files \| grep -i zone` | No output — none tracked |
| Present on disk anywhere in the tree (excluding `build/`)? | `find . -path ./build -prune -o -iname "*Zone.Identifier*" -print` | No output |
| `.gitignore` rule present? | `grep -n "Zone.Identifier" .gitignore` | `45:*Zone.Identifier*` — present |
| Shipped in the built jar? | `jar tf build/libs/jollyalchemy-transit-report-1.0.0.jar \| grep -i zone` | No output — jar's full file listing inspected, contains only real resources/classes |
| Shipped in the sources jar? | `jar tf build/libs/jollyalchemy-transit-report-1.0.0-sources.jar \| grep -i zone` | No output |
| Was the jar actually rebuilt after the fix, or stale? | `git show 0434a60 --format=%cI` (00:54:20) vs. jar file mtime (00:54:08) | Jar predates the commit by 12s — consistent with "build, verify, then commit" in the same session; not a stale pre-fix artifact |

All ten tracked `Zone.Identifier` blobs (confirmed via `git show 0434a60`) were deleted outright, not
merely untracked — the diff shows `deleted file mode 100644` for each, which is the correct fix given
the review's own finding that these were real 123-byte files, not NTFS alternate-data-streams, so
untracking alone would have left them on disk for `processResources` to pick up again. **CR-01 is fully
resolved and independently confirmed**, not merely claimed.

### WR-01 — unconstrained `fabric-api` dependency (was Warning)

| Check | Location | Result |
|---|---|---|
| Source file | `src/main/resources/fabric.mod.json` `depends.fabric-api` | `">=0.92.12"` (was `"*"`) |
| Packaged manifest inside the built jar | extracted `fabric.mod.json` from `build/libs/jollyalchemy-transit-report-1.0.0.jar` | `"fabric-api": ">=0.92.12"` — confirmed in the actual shipped artifact, not just the source tree |
| Matches the pinned build version | `gradle.properties` `fabric_api_version=0.92.12+1.20.1` | Consistent — `>=0.92.12` accepts the pinned version and follows the same constrained style as its `depends` siblings |

**WR-01 is fully resolved and independently confirmed.**

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `./gradlew runClient` opens a Minecraft 1.20.1 window and the mod is listed among the loaded mods (ROADMAP SC1, TOOL-01) | ✓ VERIFIED | `run/logs/latest.log` (gitignored runtime artifact, present on disk) line 1 carries the Minecraft 1.20.1 version line; `grep -c "Hello Fabric world"` returns 1, confirming the mod's own `onInitialize()` ran. `run/options.txt` exists (3477 bytes). `run/crash-reports` absent. This evidence predates the two remediation commits but neither commit touches anything (`fabric.mod.json` `name`/entrypoints, mixin configs) that this runtime evidence depends on — re-running the client was not required to keep this truth valid. |
| 2 | The mod is confirmed on the in-game Mods screen and a Creative Superflat world is entered (D-04, part of TOOL-01) | ✓ VERIFIED | 01-01-SUMMARY.md records the user's verbatim confirmation: "Human Design Transit Display", v1.0.0, "By Nate Neibauer". `run/saves/gsd-dev/level.dat` exists on disk (2151 bytes) — a real, saved world. |
| 3 | `./gradlew runDatagen` exits successfully and generated resource files are present under `src/main/generated` (ROADMAP SC2, TOOL-02) | ✓ VERIFIED | `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` exists on disk at current HEAD, parses as JSON, and contains `{"text.jollyalchemy-transit-report.refreshing": "Refreshing transit chart..."}`. Tracked in git (`git ls-files --error-unmatch` succeeds). |
| 4 | The `configureDataGeneration { client = true }` question is settled by observation, with the finding recorded (ROADMAP SC3, TOOL-03) | ✓ VERIFIED | `build.gradle:31-35` still carries `client = true`, unchanged by the two remediation commits. `docs/DEV.md`'s "Datagen configuration finding" section (lines 96+) and 01-03-SUMMARY.md both record the concrete experiment: with the flag, `runDatagen` succeeds; without it, it fails with `ClassNotFoundException` on the client-source-set entrypoint. |
| 5 | A reusable Creative Superflat dev world exists at `run/saves/gsd-dev` for later phases | ✓ VERIFIED | `run/saves/gsd-dev/level.dat` present on disk, confirmed directly. |
| 6 | No example/template mixin class remains tracked, so any future mixin error is unambiguously this project's own | ✓ VERIFIED | `git ls-files src/main/java/transitreport/mixin src/client/java/transitreport/client/mixin` returns empty at current HEAD. Both mixin config JSONs' arrays (`mixins`, `client`) are empty with scaffolding intact. |
| 7 | `fabric.mod.json` identifies the mod honestly with no leftover template placeholders, and its dependency block is fully constrained (extends the original criterion with the WR-01 fix) | ✓ VERIFIED | `name: "Human Design Transit Display"`, `authors: ["Nate Neibauer"]`, `contact.sources` correct, no `contact.homepage` key, `id` unchanged. `depends.fabric-api` is now `">=0.92.12"` — no longer the unconstrained `"*"` WR-01 flagged. Independently confirmed both in source and in the packaged jar manifest (see remediation table above). |
| 8 | The generated language file is genuinely regenerated output, `docs/DEV.md` durably records the dev loop/JDK/findings, and the distributed jar contains no stray provenance-marker files (extends the original criterion with the CR-01 fix) | ✓ VERIFIED | `docs/DEV.md` (142 lines) has all 7 required headings, states `JDK 26` concretely, names `gsd-dev`, contains no `C:\Users\` path, states the datagen finding with justification. `jar tf` on both built jars shows zero `Zone.Identifier` entries — independently confirmed, not taken from the commit message. |

**Score:** 8/8 truths verified (0 present-behavior-unverified)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/main/resources/fabric.mod.json` | Real mod identity, no template placeholders, constrained `depends` block | ✓ VERIFIED | Matches expected values; JSON parses; `fabric-api` now `>=0.92.12` |
| `src/main/resources/jollyalchemy-transit-report.mixins.json` | Empty `mixins` array, scaffolding intact | ✓ VERIFIED | Confirmed |
| `src/client/resources/jollyalchemy-transit-report.client.mixins.json` | Empty `client` array, scaffolding intact | ✓ VERIFIED | Confirmed |
| `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java` | Registers `FabricLanguageProvider` | ✓ VERIFIED | 27 lines; `createPack()`, `addProvider`, nested `TransitReportLanguageProvider` all present |
| `src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json` | Data-generated English translation file | ✓ VERIFIED | Content matches provider output; tracked in git |
| `build.gradle` | Settled `configureDataGeneration` form | ✓ VERIFIED | `client = true` retained, justified by the recorded experiment; unaffected by the two remediation commits |
| `docs/DEV.md` | Dev loop, JDK requirement, both findings | ✓ VERIFIED | 142 lines, all 7 headings present, no leaked local path |
| `.gitignore` | Guards against `Zone.Identifier` recurrence | ✓ VERIFIED (new since prior pass) | `*Zone.Identifier*` rule present, added in commit `0434a60` |
| `build/libs/jollyalchemy-transit-report-1.0.0.jar` | Shipped artifact free of stray sidecar files | ✓ VERIFIED | `jar tf` listing inspected directly — 16 entries, all legitimate; zero `Zone.Identifier` entries |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `fabric.mod.json` | `jollyalchemy-transit-report.mixins.json` / `.client.mixins.json` | `mixins` array names both files | WIRED | Both files still referenced |
| `fabric.mod.json` (`entrypoints.main`) | `JollyalchemyTransitReport.java` | entrypoint class reference | WIRED | Confirmed by `"Hello Fabric world!"` in the run log |
| `fabric.mod.json` (`entrypoints.fabric-datagen`) | `JollyalchemyTransitReportDataGenerator.java` | entrypoint class reference | WIRED | Confirmed by `runDatagen` output and by the negative-case `ClassNotFoundException` recorded in 01-03-SUMMARY.md |
| `JollyalchemyTransitReportDataGenerator.java` | `en_us.json` | `createPack()` → `addProvider(TransitReportLanguageProvider::new)` | WIRED | Generated file content matches the provider's `generateTranslations` body |
| `build.gradle` (`configureDataGeneration`) | generated output directory | Loom datagen run configuration | WIRED | Empirically proven load-bearing |
| `.gitignore` (`*Zone.Identifier*`) | future `git add` operations | ignore rule prevents re-tracking | WIRED | Rule present at line 45; confirmed no such files exist on disk to test against currently, but the guard is in place |
| `fabric.mod.json` `depends.fabric-api` | `gradle.properties` `fabric_api_version` | version-range consistency | WIRED | `>=0.92.12` accepts the pinned `0.92.12+1.20.1`; confirmed identical in the packaged jar manifest |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| TOOL-01 | 01-01-PLAN.md | `runClient` launches a working dev client with the mod loaded | ✓ SATISFIED | Log lines + human-confirmed Mods screen + saved world |
| TOOL-02 | 01-02-PLAN.md | `runDatagen` completes and writes generated resources to `src/main/generated` | ✓ SATISFIED | File exists, tracked, content correct, proven regenerable |
| TOOL-03 | 01-03-PLAN.md | `configureDataGeneration { client = true }` confirmed meaningful or corrected | ✓ SATISFIED | Empirically proven load-bearing; flag retained with documented reason |

`REQUIREMENTS.md` maps only TOOL-01/02/03 to Phase 1 (lines 12-14, and traceability table lines 150-152,
all marked `Complete`); all three are claimed by the three plans' frontmatter (`requirements:` field).
**No orphaned requirements.**

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | Windows `*:Zone.Identifier` NTFS-provenance sidecar blobs (CR-01) | ~~🛑 Blocker~~ **RESOLVED** | Previously affected `fabric.mod.json` and 9 other files; independently confirmed deleted from git, deleted from disk, absent from `.gitignore`-matched future adds, and absent from both built jars. No longer an anti-pattern present in the codebase. |
| — | — | `fabric.mod.json:38` unconstrained `"fabric-api": "*"` dependency (WR-01) | ~~⚠️ Warning~~ **RESOLVED** | Now `">=0.92.12"`, confirmed in source and in the packaged jar manifest. |

No debt markers (`TBD`/`FIXME`/`XXX`) or `TODO`/`HACK`/`PLACEHOLDER` found in any file this phase or its
remediation touched (`fabric.mod.json`, both mixin config JSONs, `JollyalchemyTransitReportDataGenerator.java`,
`docs/DEV.md`, `build.gradle`, `.gitignore` — all scanned directly, zero matches).

**ℹ️ Info (non-blocking, procedural):** `ROADMAP.md` marks this phase `Mode: mvp`, but its `**Goal:**`
line ("The development loop is proven end to end...") is written as an outcome statement, not in
`As a / I want to / so that` User Story form (`user-story.validate` confirms `valid: false`). All three
plans' own frontmatter flag this explicitly as planner-derived provenance, not an oversight, and note
`/gsd mvp-phase 01` is available if the canonical User Story form is wanted later. This is a roadmap
metadata/format mismatch, not a functional gap — the phase's actual deliverables (dev client launches,
datagen writes files, the toolchain flag question is settled) are all independently verified above using
standard goal-backward verification, consistent with the prior (superseded) verification pass. Not
treated as a blocker.

**ℹ️ Info (non-blocking):** `.planning/WINDOWS.md` carries one `open` ledger entry (id 1, kind
`deviation`) recording that Task 2's original Mods-screen check was unsatisfiable as written (Fabric
ships no native Mods screen) and that the user approved adding Mod Menu as a `modLocalRuntime` dev-only
dependency to resolve it. This is a recorded, user-approved deviation, not an unresolved defect — `open`
here means "not yet formally closed in the ledger," not "unaddressed." It does not block this phase's
goal; noted for completeness since `/gsd-ship` blocks on `open_count > 0` under `windows_enforce`.

### Human Verification Required

None. TOOL-01's human-observable half (Mods screen name, world creation) was already executed and
recorded verbatim during this phase's own checkpoint task, corroborated by independently-checkable
runtime artifacts. The two remediation fixes (CR-01, WR-01) are both fully machine-verifiable (git
tracking state, filesystem presence, jar contents) and were independently re-confirmed in this
re-verification pass rather than taken from the commit message.

### Gaps Summary

None remaining. Both gaps carried forward from the prior verification pass's cited `01-REVIEW.md`
findings (CR-01 critical, WR-01 warning) are closed and independently re-confirmed against current HEAD
in this re-verification: the Zone.Identifier sidecar files are gone from git, from disk, and from both
built jars, with a `.gitignore` rule in place to prevent recurrence; and `fabric.mod.json`'s
`fabric-api` dependency is now constrained to match the pinned build version, confirmed in the actual
packaged jar manifest. All three ROADMAP success criteria and all plan-level must-haves remain verified
against actual runtime artifacts, tracked files, built-jar contents, and git history — not against
SUMMARY.md or commit-message narrative alone.

---

_Verified: 2026-09-08T08:15:00Z_
_Verifier: Claude (gsd-verifier)_

---
phase: 01-toolchain-verification
plan: 01
subsystem: infra
tags: [fabric, loom, minecraft-1.20.1, mixin, fabric.mod.json, modmenu, gradle]

# Dependency graph
requires: []
provides:
  - "A real, real, launched Minecraft 1.20.1 Fabric dev client with this mod's entrypoint proven to run, on JDK 26 (no JDK 21 install needed)"
  - "fabric.mod.json carrying real project identity (name, description, author, source URL) with no template placeholders"
  - "Both mixin configs emptied and the inert ExampleMixin/ExampleClientMixin packages fully removed (including Zone.Identifier sidecars)"
  - "A reusable Creative Superflat dev world at run/saves/gsd-dev for Phase 2 onward"
  - "Mod Menu wired in as a dev-only (modLocalRuntime) dependency, since Fabric itself ships no in-game mod list"
affects: [01-02, 01-03, "any future phase that runs runClient for verification"]

# Actuals (#2632)
actuals:
  tokens: 1400
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: ["com.terraformersmc:modmenu:7.2.2 (modLocalRuntime, dev-only)"]
  patterns: ["dev-only dependencies via Loom's modLocalRuntime keep tooling out of the shipped jar and fabric.mod.json's depends block"]

key-files:
  created: []
  modified:
    - src/main/resources/fabric.mod.json
    - src/main/resources/jollyalchemy-transit-report.mixins.json
    - src/client/resources/jollyalchemy-transit-report.client.mixins.json
    - build.gradle

key-decisions:
  - "D-06 resolved: JDK 26 successfully runs the Minecraft 1.20.1 Fabric dev client end to end (LWJGL natives, Mixin, world load). Temurin 21 was never installed and is not required for this project."
  - "Approved deviation: added Mod Menu 7.2.2 via Loom's modLocalRuntime plus the Terraformers Maven repo, because Fabric ships no in-game mod list and the plan's Task 2 step 1 (confirm display name on the Mods screen) was unsatisfiable without it."
  - "Plan defect surfaced, not silently patched: Task 2 step 1 as originally written assumed a Mods screen that does not exist under vanilla Fabric. Recorded in .planning/WINDOWS.md for the verifier."

patterns-established:
  - "Dev-tooling third-party dependencies (visualization/debug aids, not runtime mod dependencies) go in via modLocalRuntime, not modImplementation, and get a comment explaining why they must stay out of the shipped jar."

requirements-completed: [TOOL-01]

coverage:
  - id: D1
    description: "Minecraft 1.20.1 Fabric dev client launches and this mod's own onInitialize() entrypoint runs inside it, on the machine's existing JDK 26 (no JDK 21 install required)."
    requirement: "TOOL-01"
    verification:
      - kind: other
        ref: "run/logs/latest.log: 'Minecraft 1.20.1' version line + 'Hello Fabric world!' mod init line, both grepped and confirmed present"
        status: pass
      - kind: other
        ref: "java -version: openjdk 26.0.2.1 (the JDK the successful launch ran on)"
        status: pass
    human_judgment: false
  - id: D2
    description: "fabric.mod.json identifies the mod honestly (Human Design Transit Display, description, author, source URL, no placeholder homepage) and that name is visually confirmed on the in-game Mods screen."
    requirement: "TOOL-01"
    verification:
      - kind: other
        ref: "node -e JSON assertion against fabric.mod.json (name/authors/contact.sources/no-homepage/id unchanged) — see Task 1 <verify>"
        status: pass
    human_judgment: true
    rationale: "The Mods-screen name is a visual GUI confirmation with no CLI/API path; the human explicitly reported seeing 'Human Design Transit Display', v1.0.0, 'By Nate Neibauer', and the correct description text."
  - id: D3
    description: "Both example mixin packages (and their tracked Zone.Identifier sidecars) are fully removed, and both mixin config JSONs are emptied but keep their scaffolding keys."
    requirement: "TOOL-01"
    verification:
      - kind: other
        ref: "git ls-files src/main/java/transitreport/mixin src/client/java/transitreport/client/mixin (empty output) + JSON array-length assertions in Task 1 <verify>"
        status: pass
    human_judgment: false
  - id: D4
    description: "A reusable Creative Superflat dev world named gsd-dev exists, was entered and stood in, and is available for Phase 2 onward."
    requirement: "TOOL-01"
    verification:
      - kind: other
        ref: "run/saves/gsd-dev/level.dat exists (2151 bytes); run/logs/latest.log shows a clean 'Saving worlds' -> 'All dimensions are saved' shutdown sequence with no crash-reports directory"
        status: pass
    human_judgment: true
    rationale: "Standing inside the world and confirming it visually is a human-observation requirement per D-04; the human confirmed the world was created, entered, and cleanly quit."

duration: 17min
completed: 2026-09-08
status: complete
---

# Phase 1 Plan 1: Toolchain Verification Tracer Summary

**Minecraft 1.20.1 Fabric dev client proven to launch and run this mod's entrypoint on JDK 26, mod identity confirmed live on the Mods screen (added via a dev-only Mod Menu dependency), and a reusable `gsd-dev` Superflat world saved for later phases.**

## Performance

- **Duration:** ~17 min across two executor sessions (one checkpoint round-trip in between)
- **Started:** 2026-09-08T07:06:03Z
- **Completed:** 2026-09-08T07:23:00Z
- **Tasks:** 2 (1 tracer + 1 checkpoint:human-action)
- **Files modified:** 4 tracked files + 2 deletions (2 example mixin classes + their Zone.Identifier sidecars)

## Accomplishments

- `fabric.mod.json` now identifies the mod as `Human Design Transit Display` with real description, author, and source URL, and no leftover template placeholder (`contact.homepage` removed outright, not replaced).
- Both mixin config JSONs (`jollyalchemy-transit-report.mixins.json`'s `mixins` array, `jollyalchemy-transit-report.client.mixins.json`'s `client` array) emptied; `ExampleMixin`/`ExampleClientMixin` and their tracked `Zone.Identifier` sidecars deleted via `git rm -r` on both packages.
- `./gradlew runClient` launched the Minecraft 1.20.1 dev client twice this plan (once for Task 1's log evidence, once after the Mod Menu deviation), on JDK 26 — `run/logs/latest.log` carries the version line and this mod's `"Hello Fabric world!"` init line both times, `run/options.txt` was written, and `run/crash-reports` never appeared.
- Fabric ships no in-game mod list, so Task 2 step 1 as originally written was unsatisfiable — the user chose, and approved, adding `com.terraformersmc:modmenu:7.2.2` as a `modLocalRuntime` (dev-runtime-only) dependency, which gave the title screen a Mods button without becoming a shipped dependency.
- Human directly confirmed on the Mods screen: `Human Design Transit Display`, version `v1.0.0`, `By Nate Neibauer`, and the correct description text — plus `Mod Menu` itself listed with a `Client` badge, corroborating it loaded as client-side dev tooling and not as this mod's dependency.
- A Creative Superflat world named exactly `gsd-dev` was created, entered, stood in, and cleanly saved (`run/saves/gsd-dev/level.dat` present, log shows a full `Saving worlds` → `All dimensions are saved` sequence, no crash report).

## Task Commits

Each task was committed atomically:

1. **Task 1: Make the mod identify as itself, drop template mixins, prove it loads in a live 1.20.1 dev client** - `87c2b20` (feat)
2. **Approved deviation (Task 2 support): add Mod Menu as dev-only dependency** - `46df129` (feat)

**Plan metadata:** commit pending (this SUMMARY commit)

_Note: Task 2 itself is a `checkpoint:human-action` — its own action (driving the game GUI, creating the world) produces only gitignored runtime artifacts under `run/`, not tracked source changes, so it carries no separate task commit beyond the deviation above._

## Files Created/Modified

- `src/main/resources/fabric.mod.json` - real name/description/authors/contact.sources; `contact.homepage` removed
- `src/main/resources/jollyalchemy-transit-report.mixins.json` - `mixins` array emptied
- `src/client/resources/jollyalchemy-transit-report.client.mixins.json` - `client` array emptied
- `src/main/java/transitreport/mixin/ExampleMixin.java` - deleted (with its `Zone.Identifier` sidecar)
- `src/client/java/transitreport/client/mixin/ExampleClientMixin.java` - deleted (with its `Zone.Identifier` sidecar)
- `build.gradle` - added Terraformers Maven repo + `modLocalRuntime "com.terraformersmc:modmenu:7.2.2"` (dev-only)

## Decisions Made

- **D-06 resolved:** the first `runClient` launch on JDK 26 succeeded cleanly — no module access error, no LWJGL native load failure, no Mixin reflection failure into JDK internals. The D-06 hard stop did **not** fire. Temurin JDK 21 was not installed and is not needed for this project. This is the phase's resolved JDK answer, to be carried into `docs/DEV.md` in plan 01-03.
- **Approved deviation — Mod Menu as dev-only dependency:** Fabric ships no built-in Mods screen (unlike Forge); the screen the user found without it was Select Resource Packs' "Fabric Mods" virtual asset bundle, which names no individual mod and cannot confirm the `name` field. The user was presented three resolutions and explicitly chose adding Mod Menu. Per `.claude/CLAUDE.md`'s "a third-party library needs an explicit justification before it goes in," the user's explicit, informed approval is that justification. The dependency is wired via `modLocalRuntime` (not `modImplementation`), so it is present only for `runClient` and never enters the shipped jar or `fabric.mod.json`'s `depends` block — confirmed by the in-game Mods screen itself showing Mod Menu with a `Client` badge.
- **Cross-plan note for 01-03:** `build.gradle` is listed in plan 01-03's `files_modified` (for the `configureDataGeneration` / D-13 experiment), not 01-01's. The `modLocalRuntime "com.terraformersmc:modmenu:7.2.2"` line and the `TerraformersMC` maven repository block added here are a deliberate, user-approved scope deviation onto that file. **Plan 01-03's executor must preserve both, not clobber them,** when it edits `build.gradle` for its own work.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 4 - Architectural/dependency, user-approved] Added Mod Menu as a dev-only dependency to make Task 2 step 1 satisfiable**
- **Found during:** Task 2 (human attempted step 1 — "there is no Mods button on the title screen")
- **Issue:** Task 2 step 1 and decision D-04 assumed Fabric ships an in-game Mods screen. It does not. `run/logs/latest.log` only ever prints the mod **id** (`jollyalchemy-transit-report`), never the display `name`, so nothing in a stock Fabric session could confirm `fabric.mod.json`'s `name` field visually. As written, this acceptance criterion was unsatisfiable — a genuine planning defect, not user error.
- **Fix:** Presented the user three resolutions; user explicitly chose adding Mod Menu. Added `com.terraformersmc:modmenu:7.2.2` via `modLocalRuntime` plus the Terraformers Maven repository in `build.gradle`. Rebuilt (`./gradlew build` exit 0) and relaunched the dev client.
- **Files modified:** `build.gradle`
- **Verification:** `./gradlew build` exited 0; `run/logs/latest.log` lists both `jollyalchemy-transit-report 1.0.0` and `modmenu 7.2.2` in the loaded-mods manifest; human visually confirmed the Mods screen shows `Human Design Transit Display`, `v1.0.0`, `By Nate Neibauer`, and the correct description, with Mod Menu itself tagged `Client` (confirming it is dev-runtime-only, not a dependency of this mod).
- **Committed in:** `46df129`

This deviation is also recorded in `.planning/WINDOWS.md` (kind: `deviation`) so it stays visible to the phase verifier as a planning defect (unsatisfiable acceptance criterion), not a silently-absorbed fix.

---

**Total deviations:** 1 auto-fixed-with-approval (1 architectural/dependency addition, explicitly approved by the user before being applied)
**Impact on plan:** Necessary to satisfy TOOL-01's human-observable Mods-screen criterion at all, given Fabric's actual capabilities. No scope creep beyond what the user approved; dependency is dev-only and does not affect the shipped mod.

## Issues Encountered

- **Task 2 step 1 as originally planned was unsatisfiable.** Fabric has no in-game mod list; the plan's `<precondition>`-free assumption that a "Mods" button exists on a stock title screen does not hold. Resolved via the approved Mod Menu deviation above. Flagged in `.planning/WINDOWS.md` as a planning defect for the verifier, per explicit user instruction, rather than treated as a silent fix.
- No other issues. The dev client launched cleanly on JDK 26 both times; the only log-level anomaly was a benign `Failed to verify authentication: Status 401` (expected for an offline/dev Minecraft session, unrelated to the mod or Mod Menu).

## User Setup Required

None - no external service configuration required. (The `user_setup` entry in the plan frontmatter for Temurin JDK 21 was conditional on the D-06 hard stop firing; it did not fire, so no action is needed there.)

## Next Phase Readiness

- TOOL-01 is satisfied by direct observation: the dev client launches on JDK 26, the mod's own entrypoint runs, the mod identifies itself correctly on the (now-visible) Mods screen, and a reusable `gsd-dev` Creative Superflat world exists under `run/saves/` for Phase 2 onward.
- `build.gradle` now carries the Mod Menu dev dependency and Terraformers repo — plan 01-03 must preserve both when it makes its own `configureDataGeneration` edits to that file.
- The unsatisfiable-precondition planning defect (Fabric has no Mods screen) is recorded in `.planning/WINDOWS.md` for the phase verifier's attention.
- No blockers for 01-02 (datagen language provider) or 01-03 (`client = true` experiment + `docs/DEV.md`).

---

*Phase: 01-toolchain-verification*
*Completed: 2026-09-08*

## Self-Check: PASSED

- FOUND: src/main/resources/fabric.mod.json
- FOUND: build.gradle
- FOUND: .planning/phases/01-toolchain-verification/01-01-SUMMARY.md
- FOUND: commit 87c2b20 (Task 1)
- FOUND: commit 46df129 (approved Mod Menu deviation)
- FOUND: commit c2d2b23 (plan metadata / SUMMARY commit)

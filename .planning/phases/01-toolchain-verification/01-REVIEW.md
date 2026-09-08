---
phase: 01-toolchain-verification
reviewed: 2026-09-08T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - build.gradle
  - src/main/resources/fabric.mod.json
  - src/main/resources/jollyalchemy-transit-report.mixins.json
  - src/client/resources/jollyalchemy-transit-report.client.mixins.json
  - src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java
  - src/main/generated/assets/jollyalchemy-transit-report/lang/en_us.json
  - docs/DEV.md
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: resolved
---

# Phase 01: Code Review Report

**Reviewed:** 2026-09-08T00:00:00Z
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

This phase is toolchain verification only, and the reviewed files are almost entirely
configuration/metadata/boilerplate (build.gradle, fabric.mod.json, two empty mixin configs, a
one-key datagen provider, its generated output, and a dev guide). There is no HTTP, rendering,
threading, or block logic yet, so most of the standard bug/security checklist (null checks,
promise handling, injection, etc.) does not apply — that was confirmed by reading each file in
full rather than assumed.

Two real, verifiable defects were found. The more serious one is not a matter of interpretation:
this repository has Windows NTFS "Zone.Identifier" metadata files committed to git as literal
tracked blobs, and I confirmed by running a full build that they get copied into
`build/resources/**` and end up as junk entries inside the actual shipped mod jar
(`build/libs/jollyalchemy-transit-report-1.0.0.jar`). Four of the seven files in this review's
scope have such a sibling committed alongside them. The second finding is a version-pinning
inconsistency between `fabric.mod.json`'s declared Fabric API dependency range and the exact
version pinned and verified elsewhere in the toolchain.

The dev-only Mod Menu dependency (`modLocalRuntime`) and `configureDataGeneration { client = true
}` were checked against the approved-deviation rationale in the task context and are scoped and
justified correctly — not re-flagged here.

## Critical Issues

### CR-01: Windows Zone.Identifier NTFS stream files are committed to git and ship inside the built mod jar

**File:** `src/main/resources/fabric.mod.json` (and companion path `src/main/resources/fabric.mod.json:Zone.Identifier`)
**Also affects (same defect, same git blob):** `src/main/resources/jollyalchemy-transit-report.mixins.json`, `src/client/resources/jollyalchemy-transit-report.client.mixins.json`, `src/client/java/transitreport/client/JollyalchemyTransitReportDataGenerator.java`, plus 6 more files elsewhere in the repo (`.github/workflows/build.yml`, both `gradle/wrapper/*`, `JollyalchemyTransitReportClient.java`, `JollyalchemyTransitReport.java`, `assets/.../icon.png`)

**Issue:** `git ls-files -s | grep -i zone.identifier` shows 10 tracked blobs literally named `<original-path>:Zone.Identifier`, all pointing at the identical git blob `44a52bdf0ce7d87487b12adbe61f038f522a9190` (the standard tiny "ZoneId=3" content Windows writes as an NTFS alternate-data-stream mark-of-the-web when a file is extracted from something downloaded via a browser). These were committed alongside the real files — almost certainly from an initial `git add` of a browser-downloaded template zip on Windows without excluding the ADS artifacts — and `.gitignore` has no rule that would catch them (`*Zone.Identifier*` is absent).

This is not cosmetic. I ran the actual build and verified the blast radius:
- `find build/resources -iname "*Zone.Identifier*"` shows they get copied straight through `processResources` into `build/resources/main` and `build/resources/client`.
- `jar tf build/libs/jollyalchemy-transit-report-1.0.0.jar | grep -i zone` returns real entries in the **shipped** jar:
  ```
  assets/jollyalchemy-transit-report/icon.png?Zone.Identifier
  fabric.mod.json?Zone.Identifier
  jollyalchemy-transit-report.client.mixins.json?Zone.Identifier
  jollyalchemy-transit-report.mixins.json?Zone.Identifier
  ```

This is the exact artifact PROJECT.md/CLAUDE.md describes distributing to friends on the private server. Shipping stray Windows provenance-marker files inside a mod jar sitting next to `fabric.mod.json` is a real defect: it leaks local build-machine metadata into a distributed artifact, bloats the jar, and signals an uncontrolled git-add hygiene gap that will keep recurring on every future commit unless fixed at the `.gitignore` level (not just cleaned up once).

**Fix:**
```bash
# 1. Remove all tracked Zone.Identifier companions (repo-wide, not just this phase's files)
git ls-files | grep -i "zone.identifier" | while IFS= read -r f; do git rm --cached "$f"; done

# 2. Prevent recurrence
cat >> .gitignore <<'EOF'

# Windows NTFS mark-of-the-web streams (accidentally git-add-able on this platform)
*Zone.Identifier*
EOF

# 3. Verify the shipped jar is clean
./gradlew clean build
jar tf build/libs/jollyalchemy-transit-report-*.jar | grep -i zone   # expect no output
```

## Warnings

### WR-01: `fabric.mod.json` declares an unconstrained Fabric API dependency while the build pins an exact, verified version

**File:** `src/main/resources/fabric.mod.json:38`
**Issue:** The `depends` block pins `fabricloader` (`>=0.19.5`), `minecraft` (`~1.20.1`), and `java` (`>=17`) to specific, verified ranges, but `"fabric-api": "*"` accepts literally any Fabric API version at load time. `gradle.properties` pins `fabric_api_version=0.92.12+1.20.1`, and this exact version is the one the toolchain research (STACK.md) and this phase's own verification treat as the known-good pairing with Loom 1.17 / Minecraft 1.20.1. A friend on the shared private server with a different Fabric API version installed will pass Fabric Loader's dependency check even though the mod was never built or verified against anything but 0.92.12+1.20.1 — this is the one dependency in the block that doesn't follow the "pin what you've verified" pattern used for every other entry right next to it.
**Fix:**
```json
"depends": {
	"fabricloader": ">=0.19.5",
	"minecraft": "~1.20.1",
	"java": ">=17",
	"fabric-api": ">=0.92.12"
}
```

---

_Reviewed: 2026-09-08T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

---

## Resolution

Both findings were fixed in commit `0434a60` after the phase verifier passed.

**CR-01 — resolved.** The review's suggested remedy (`git rm --cached` + `.gitignore`)
would have been insufficient. Inspection on disk showed these were **real 123-byte files**,
not NTFS alternate data streams — they were materialized when the project template was
copied out of WSL (`ReferrerUrl=\wsl.localhost\Ubuntu\...`). Because Gradle's
`processResources` reads the filesystem rather than the git index, untracking alone would
have left the jar contaminated. The files were therefore deleted outright, and
`*Zone.Identifier*` added to `.gitignore` to prevent recurrence. Verified by a clean
rebuild: `unzip -l` on both `jollyalchemy-transit-report-1.0.0.jar` and its `-sources`
counterpart returns no matching entries.

**WR-01 — resolved.** `"fabric-api"` changed from `"*"` to `">=0.92.12"`, matching the
pinned `fabric_api_version=0.92.12+1.20.1` in `gradle.properties` and the constrained style
of its siblings. Confirmed present in the packaged manifest inside the built jar.

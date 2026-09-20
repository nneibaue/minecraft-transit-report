---
phase: "03"
slug: "craft-break-and-identify"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: true
wave_0_complete: true
created: "2026-09-08"
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | None (JUnit not yet wired into this project — CLAUDE.md §7 scopes JUnit to TransitApiClient/config/scheduler logic in later phases). This phase's automated surface is Gradle build/datagen plus grep/node assertions against generated output. |
| **Config file** | none |
| **Quick run command** | `./gradlew runDatagen` |
| **Full suite command** | `./gradlew build` |
| **Estimated runtime** | ~30-60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./gradlew runDatagen` (regenerate and grep/node-assert the output)
- **After every plan wave:** Run `./gradlew build`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | BLOCK-04, BLOCK-05, GEN-03, GEN-04, GEN-06 | — / — | N/A | integration | `grep`-based source assertions + `./gradlew runDatagen` + `./gradlew build` | ✅ | ✅ green |
| 03-01-02 | 01 | 1 | GEN-03, GEN-04 | — / — | N/A | integration | `node -e` JSON-shape assertions + `git ls-files` tracking checks + delete/regenerate reproducibility diff | ✅ | ✅ green |
| 03-02-01 | 02 | 2 | BLOCK-06, GEN-05 | — / — | N/A | integration | `grep`-based source assertions + `./gradlew runDatagen` + `node -e` lang-file assertions + `./gradlew build` | ✅ | ✅ green |
| 03-02-02 | 02 | 2 | BLOCK-04, BLOCK-05, BLOCK-06 | — / — | N/A | manual + integration | `grep` log/docs assertions (automated portion) + human-check (see Manual-Only below) | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*None: existing Gradle build/datagen infrastructure covers all phase requirements — no new test framework was needed for this phase.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| Full survival craft → tooltip → break loop in a running dev client | BLOCK-04, BLOCK-05, BLOCK-06 | Rendered tooltip text and in-game crafting/breaking behavior are what a person reads on screen; CLAUDE.md §7 records no practical automated assertion exists for rendered output in a mod this size, and no Minecraft-side test harness exists or is planned. The automated checks in 03-02 task 1 prove the generated language file and block class reference the right keys, but only a person can confirm the two are joined correctly at runtime. | Load world `gsd-dev` (Phase 1), survival mode, craft 1 Transit Chart from 1 dirt in the 2x2 inventory grid (no table), hover to read all 3 tooltip lines in order, place and break with bare hand/shovel/pickaxe confirming a single drop each time, and confirm the recipe appears in the recipe book. **Executed and confirmed by the user during 03-02 execution ("approved" — "yes it all works!").** |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (none needed)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-09-08

---

## Validation Audit 2026-09-08

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 1 (pre-existing, deliberate — rendered gameplay/tooltip behavior, already human-verified during execution) |

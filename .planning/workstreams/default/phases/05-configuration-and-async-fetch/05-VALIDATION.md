---
phase: "05"
slug: "configuration-and-async-fetch"
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
# audit-milestone §5.5 distinguishes NOT-VALIDATED (draft) from PARTIAL (validated + nyquist_compliant: false) (#2117)
status: validated
nyquist_compliant: false
wave_0_complete: true
created: "2026-09-08"
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | JUnit 5 (org.junit.jupiter:junit-jupiter:5.10.2 + org.junit.platform:junit-platform-launcher) |
| **Config file** | `build.gradle` (`test { useJUnitPlatform() }` block, added this phase — first test source set in the repo) |
| **Quick run command** | `./gradlew test --tests "transitreport.config.TransitConfigTest" --tests "transitreport.api.SizedBodySubscriberTest"` |
| **Full suite command** | `./gradlew build` (runs `test` as part of the `check`/`build` lifecycle) |
| **Estimated runtime** | ~15-25 seconds (no live network calls in the unit suite) |

---

## Sampling Rate

- **After every task commit:** Run `./gradlew test --tests "transitreport.config.TransitConfigTest" --tests "transitreport.api.SizedBodySubscriberTest"`
- **After every plan wave:** Run `./gradlew build`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~25 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-T1 | 01 | 1 | CFG-01 | T-05-01 | Missing config file yields defaults and writes them to disk | unit | `./gradlew test --tests transitreport.config.TransitConfigTest` | ✅ | ✅ green |
| 05-01-T1 | 01 | 1 | CFG-02 | — | Valid custom config is loaded verbatim and not rewritten | unit | `./gradlew test --tests transitreport.config.TransitConfigTest` | ✅ | ✅ green |
| 05-01-T1 | 01 | 1 | CFG-03 | T-05-01 | Malformed/invalid config resets both fields to defaults and rewrites the file | unit | `./gradlew test --tests transitreport.config.TransitConfigTest` | ✅ | ✅ green |
| 05-01-T1 | 01 | 1 | API-05 | T-05-03 | Response body is capped at 5MB during streaming (onNext-time abort, not post-hoc) | unit | `./gradlew test --tests transitreport.api.SizedBodySubscriberTest` | ✅ | ✅ green |
| 05-01-T1 | 01 | 1 | API-04 | — | Exactly one `fetchChart(String, ChartCallback)` entry point exists | structural | `grep -c "public void fetchChart(" src/main/java/transitreport/api/TransitApiClient.java` (== 1) | ✅ (grep, no dedicated test file) | ✅ green |
| 05-01-T1 | 01 | 1 | API-02 | T-05-02 | Connect/request timeouts (10s/45s) are configured on the shared HttpClient/HttpRequest | structural | `grep -Fq "Duration.ofSeconds(10)"` / `grep -Fq "Duration.ofSeconds(45)"` in `TransitApiClient.java` | ✅ (grep, no dedicated test file) | ✅ green |
| 05-01-T2 | 01 | 1 | API-01, API-02 | T-05-02 | Live fetch against the real API logs status+bytes; a deliberately unreachable host fails cleanly within timeout, no hang/crash | manual_procedural | Live `./gradlew runClient` session, log inspection (see docs/DEV.md "Phase 5" section) | N/A — live verification, D-06 explicitly forbids a mock-server test harness this phase | ✅ observed (2026-09-08) |
| 05-01-T2 | 01 | 1 | API-03 | — | No frame hitch / stutter while the fetch is in flight | manual (human perception) | none — requires a human watching an active `runClient` window | N/A | ⬜ pending — see Manual-Only |
| 05-01-T1 | 01 | 1 | CFG-05 | T-05-04 | Shipped config defaults contain no API secret/key/credential | manual (code inspection) | none — plan's own acceptance criteria scope this as "confirmable by inspection" | N/A | ✅ inspected (2026-09-08) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*None — Task 1 was written TDD-first (RED commit `897154a` before GREEN commit `2831ca3`); the JUnit 5 test infrastructure itself was net-new this phase but was installed as part of Task 1, not a separate Wave 0. Existing infrastructure (once installed) covers all automatable phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|--------------------|
| No frame hitch/stutter while the startup fetch is in flight | API-03 | Felt, real-time responsiveness during an active game session cannot be asserted by a unit test or a log line; requires a human physically watching/interacting with the client window (D-07) | Run `./gradlew runClient`, wait through the ~startup window while the one-shot config-load-then-fetch call executes, and confirm no stutter or frame hitch is felt. Not yet performed this session — flagged in 05-01-SUMMARY.md coverage item D5. |
| Live fetch success/failure behavior against the real Human Design API and an unreachable host | API-01, API-02 | D-06 explicitly locks out building a mock HTTP server or fake-server test harness this phase (deferred to v2, MOCK-01..03) — only live, manual verification is in scope | Already performed 2026-09-08: confirmed `Chart fetch succeeded: status 200, <N> bytes` on a normal launch, a `Chart fetch failed: java.net.ConnectException` within ~1s against `https://this-host-does-not-exist.invalid`, and a `HttpTimeoutException` at the full 45s boundary during a Render.com cold start — all logged in `docs/DEV.md`'s Phase 5 section. |
| No API secret/credential in shipped config defaults | CFG-05 | Plan's own acceptance criteria (05-01-PLAN.md success_criteria #5) scope this as "confirmable by inspection," not an automated test — `TransitConfig`/`TransitApiClient` have no auth header, API key, or credential field to assert against | Already performed 2026-09-08: code inspection of `TransitConfig.java` and `TransitApiClient.java` confirms no credential field anywhere. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (Task 1 fully automated; Task 2's automated half is the `docs/DEV.md` "Phase 5" string check, its manual half is covered above)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (both tasks in this phase's single plan have automated components)
- [x] Wave 0 covers all MISSING references (none needed — see above)
- [x] No watch-mode flags
- [x] Feedback latency < 25s (unit suite; live `runClient` verification is separately timed by its own D-08 timeouts, not part of the fast feedback loop)
- [ ] `nyquist_compliant: true` set in frontmatter — **not set**: API-03's no-frame-hitch confirmation is still pending human observation (see Manual-Only above); everything else automatable is COVERED

**Approval:** approved 2026-09-08 (partial — one manual UAT item pending, does not block phase completion per 05-01-SUMMARY.md)

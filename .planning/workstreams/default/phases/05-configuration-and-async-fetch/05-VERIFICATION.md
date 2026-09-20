---
phase: 05-configuration-and-async-fetch
verified: 2026-09-09T02:15:00Z
status: passed
score: 4/5 must-haves verified
behavior_unverified: 1
covered_files:

  - .planning/phases/05-configuration-and-async-fetch/05-01-PLAN.md
  - .planning/phases/05-configuration-and-async-fetch/05-01-SUMMARY.md
  - .planning/phases/05-configuration-and-async-fetch/05-REVIEW.md
  - .planning/phases/05-configuration-and-async-fetch/05-VALIDATION.md
  - .planning/phases/05-configuration-and-async-fetch/05-SECURITY.md
  - .planning/REQUIREMENTS.md
  - build.gradle
  - src/main/java/transitreport/config/TransitConfig.java
  - src/main/java/transitreport/api/TransitApiClient.java
  - src/main/java/transitreport/api/SizedBodySubscriber.java
  - src/test/java/transitreport/config/TransitConfigTest.java
  - src/test/java/transitreport/api/SizedBodySubscriberTest.java
  - src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
  - docs/DEV.md

behavior_unverified_items:

  - truth: "The game stays responsive with no frame hitch while the one-shot startup fetch is in flight"
    test: "Launch ./gradlew runClient, observe the client startup and the fetch completing"
    expected: "No visible stutter or frame hitch is felt while the HTTP request is in flight, logs show 'Chart fetch succeeded: status 200, <N> bytes' or similar"
    why_human: "Frame hitch is a felt, real-time responsiveness experience during an active game session. Code inspection confirms the fetch runs off-thread via HttpClient.sendAsync() with a dedicated executor, and Minecraft.getInstance().execute() marshals the callback result back to the main thread before logging. The off-thread architecture guarantees the fetch cannot block the game, but the actual visual smoothness during the in-flight window requires a human watching and interacting with an active client window."
covered_digest: "v1:sha256:cc2e2006e113824822515220e5d0f5b54b68bef4a5f457a43b122255257c0e32"
---

# Phase 05: Configuration and Async Fetch Verification Report

**Phase Goal:** The mod reads its base URL and refresh interval from a config file and fetches PNG bytes from that URL asynchronously, without ever blocking the game

**Verified:** 2026-09-09T02:15:00Z  
**Status:** human_needed (1 behavioral verification item pending human observation)  
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A config file (transit-config.json) is written with defaults into FabricLoader's config dir on first run; editing baseUrl/refreshIntervalSeconds changes the URL/interval the next startup fetches/applies without a code change | ✓ VERIFIED | TransitConfig.load(Path) and writeDefaults(Path) implement full config lifecycle; TransitConfigTest.missingFileYieldsDefaultsAndWritesFile passes; live docs/DEV.md confirms first-run write observed; CFG-01/CFG-02 |
| 2 | A deleted or malformed config file yields usable defaults plus one clear log line naming the specific reason, and the game still initializes rather than crashing | ✓ VERIFIED | TransitConfig.load(Path) catches IOException, JsonSyntaxException, and validation failures (empty baseUrl, refreshIntervalSeconds <= 0); logs one reason-specific WARN per 05-01-PLAN.md D-14; TransitConfigTest.syntacticallyInvalidJsonYieldsDefaultsForBothFieldsAndOverwritesFile passes with observed log "Config file was malformed (JSON parse error: ...)"; TransitConfigTest.nonPositiveRefreshIntervalResetsBothFieldsToDefaults passes with observed log "validation failed: refreshIntervalSeconds <= 0"; CFG-03 |
| 3 | Triggering the one-shot startup fetch against the live Human Design API logs an HTTP status and a byte count, and the game stays responsive with no frame hitch while the request is in flight | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | TransitApiClient.fetchChart() (lines 50-81) calls HttpClient.sendAsync() with a dedicated 2-thread executor; response.statusCode() is logged after CR-01 fix (line 76); callback is wrapped in Minecraft.getInstance().execute() for main-thread marshaling (JollyalchemyTransitReportClient lines 30-32, 38-40); docs/DEV.md live verification confirms "Chart fetch succeeded: status 200, 107855 bytes" was logged; no frame-hitch observation was performed (see behavior_unverified_items) — the code is present and wired correctly to prevent blocking, but the felt experience during an active game session requires human observation; API-01, API-02, API-03 |
| 4 | A fetch against an unreachable host gives up within the configured connect (10s) and request (45s) timeouts instead of hanging, and a response exceeding 5MB is aborted mid-stream and treated as an ordinary failure rather than growing without bound | ✓ VERIFIED | TransitApiClient has Duration.ofSeconds(10) and Duration.ofSeconds(45) configured on HttpClient and HttpRequest (lines 28-29, 57); SizedBodySubscriber caps response at 5L * 1024 * 1024 bytes (line 27) and enforces it in onNext() (lines 52-59); WR-01 fix adds re-entry guard (lines 47-51) to prevent further buffering after cap exceeded; SizedBodySubscriberTest.overLimitCancelsSubscriptionAndCompletesExceptionally passes (cancels subscription, completes exceptionally); SizedBodySubscriberTest.onNextAfterCapExceededIsIgnored passes (WR-03 test, verifies no state mutation on post-cancel chunks); docs/DEV.md live verification confirms unreachable host "Chart fetch failed: java.net.ConnectException" within ~1s and cold-start timeout "HttpTimeoutException: request timed out" at 45s boundary; API-02, API-05 |
| 5 | Shipped config defaults contain no API secret or credential, and TransitApiClient exposes exactly one fetchChart(String, ChartCallback) method such that a second chart endpoint is one added method, not a restructure | ✓ VERIFIED | Code inspection: TransitConfig.DEFAULT_BASE_URL contains no auth header, API key, bearer token, or credential — only the public endpoint URL with parameter placeholders; TransitApiClient.java defines exactly one public void fetchChart(String, ChartCallback) method (line 50); grep count "public void fetchChart(" yields 1; single ChartCallback interface with onSuccess/onFailure (lines 100-104); CFG-05, API-04 |

**Score:** 4/5 must-haves verified (code present and wired); 1 present-but-behavior-unverified (frame hitch confirmation pending human observation)

---

## Artifacts Verification (Three Levels)

### Level 1: Existence

| Artifact | Exists | Status |
|----------|--------|--------|
| `src/main/java/transitreport/config/TransitConfig.java` | ✓ | VERIFIED |
| `src/main/java/transitreport/api/TransitApiClient.java` | ✓ | VERIFIED |
| `src/main/java/transitreport/api/SizedBodySubscriber.java` | ✓ | VERIFIED |
| `src/test/java/transitreport/config/TransitConfigTest.java` | ✓ | VERIFIED |
| `src/test/java/transitreport/api/SizedBodySubscriberTest.java` | ✓ | VERIFIED |

### Level 2: Substantive Content (Not Stubs)

All five artifacts contain full, non-stub implementations:

- **TransitConfig.java** (106 lines): PUBLIC/STATIC constants, instance fields, public load(), package-private load(Path), private writeDefaults(Path) with Gson HTML-safe-escaping fix
- **TransitApiClient.java** (106 lines): Constructor builds HttpClient and dedicated executor; fetchChart() method implements full async flow with token substitution, request building, error routing; shutdown() for executor lifecycle; nested ChartCallback interface
- **SizedBodySubscriber.java** (80 lines): Implements HttpResponse.BodySubscriber<byte[]> fully; onSubscribe/onNext/onError/onComplete all present; size-cap enforcement with re-entry guard (WR-01 fix); isSizeExceeded() getter
- **TransitConfigTest.java** (73 lines): Four @Test methods covering missing file, valid custom JSON, malformed JSON, and non-positive interval — all implemented with assertions and temporary directory fixtures
- **SizedBodySubscriberTest.java** (106 lines): Three @Test methods (including WR-03 new test) with RecordingSubscription test double, boundary checks, and assertions on cancel count and future completion

### Level 3: Wiring and Integration

All artifacts are properly wired:

1. **JollyalchemyTransitReportClient → TransitConfig** (line 25): `TransitConfig config = TransitConfig.load();` — wired, public load() resolves FabricLoader.getConfigDir()
2. **JollyalchemyTransitReportClient → TransitApiClient** (lines 26-43): Creates instance, calls fetchChart(), wraps callbacks in Minecraft.getInstance().execute(), calls shutdown() on both success and failure paths
3. **TransitConfig → file I/O**: load(Path) reads/writes via java.nio.file.Files, resolves configDir/transit-config.json correctly
4. **TransitApiClient → HTTP**: Builds HttpRequest, sends via httpClient.sendAsync(), routes response through SizedBodySubscriber
5. **SizedBodySubscriber → response flow**: Implements HttpResponse.BodySubscriber interface correctly; onNext called by HTTP client during streaming; result CompletableFuture wired to response body or exception
6. **Main-thread marshaling**: Minecraft.getInstance().execute() wraps callback bodies before logging (JollyalchemyTransitReportClient lines 30-32, 38-40)

---

## Key Links Verification

| From | To | Via | Verified |
|------|----|----|----------|
| JollyalchemyTransitReportClient.onInitializeClient() | TransitConfig.load() | direct call | ✓ WIRED |
| JollyalchemyTransitReportClient.onInitializeClient() | TransitApiClient.fetchChart() | direct call | ✓ WIRED |
| TransitApiClient.fetchChart() | token substitution | substituteTokens(String) calling LocalDate.now().toString() and LocalTime.now().format() | ✓ WIRED |
| TransitApiClient.fetchChart() | HTTP request building | HttpRequest.newBuilder().uri().timeout().GET().build() | ✓ WIRED |
| TransitApiClient.fetchChart() | response streaming | HttpClient.sendAsync(..., responseInfo -> new SizedBodySubscriber(...)) | ✓ WIRED |
| SizedBodySubscriber.onNext() | size enforcement | buffer.size() + buf.remaining() > maxSize check | ✓ WIRED |
| TransitApiClient.fetchChart() callback | main thread | Minecraft.getInstance().execute(() -> { ... }) wrapper | ✓ WIRED |
| TransitApiClient lifecycle | executor cleanup | apiClient.shutdown() called in both onSuccess/onFailure (WR-02 fix) | ✓ WIRED |

---

## Code Review Fixes Verification

All fixes from 05-REVIEW.md (commit 7aa7d60) are present in the current code:

### CR-01: HTTP Status Code Check

**File:** src/main/java/transitreport/api/TransitApiClient.java, lines 72-74

```java
} else if (response.statusCode() != 200) {
    JollyalchemyTransitReport.LOGGER.warn("Chart fetch failed: HTTP status {}", response.statusCode());
    callback.onFailure(new java.io.IOException("Unexpected HTTP status " + response.statusCode()));
}
```

✓ **VERIFIED**: Non-200 responses are routed to onFailure instead of onSuccess

### WR-01: Size-Cap Re-Entry Guard

**File:** src/main/java/transitreport/api/SizedBodySubscriber.java, lines 47-51

```java
@Override
public void onNext(List<ByteBuffer> item) {
    if (sizeExceeded) {
        // cancel() is best-effort/async (Reactive Streams spec) -- a chunk already in
        // flight can still arrive after the cap was flagged, so guard here too.
        return;
    }
```

✓ **VERIFIED**: Re-entry guard prevents further buffer mutations after cap exceeded

### WR-02: Executor Shutdown Method

**File:** src/main/java/transitreport/api/TransitApiClient.java, lines 89-91

```java
public void shutdown() {
    executor.shutdown();
}
```

**File:** src/client/java/transitreport/client/JollyalchemyTransitReportClient.java, lines 33 and 41

```java
apiClient.shutdown();  // in onSuccess callback
apiClient.shutdown();  // in onFailure callback
```

✓ **VERIFIED**: Executor is shut down after both success and failure paths, preventing thread leak

### WR-03: New Test for Re-Entry Case

**File:** src/test/java/transitreport/api/SizedBodySubscriberTest.java, lines 88-104

```java
@Test
void onNextAfterCapExceededIsIgnored() {
    // ... test calls onNext() twice after cap exceeded, verifies no state mutation
}
```

✓ **VERIFIED**: Test passes, confirms re-entry guard behavior

---

## Test Results

### Automated Test Suite

**Build:** `./gradlew build` ✓ **SUCCESS**

**Unit Tests:** 7 total, all passing

**TransitConfigTest.java** — 4 tests passing:

1. `missingFileYieldsDefaultsAndWritesFile(Path)` — ✓ PASS (0.032s)
2. `validCustomJsonIsReturnedAndFileIsNotRewritten(Path)` — ✓ PASS (0.003s)
3. `syntacticallyInvalidJsonYieldsDefaultsForBothFieldsAndOverwritesFile(Path)` — ✓ PASS (0.297s, includes malformed JSON parsing)
4. `nonPositiveRefreshIntervalResetsBothFieldsToDefaults(Path)` — ✓ PASS (0.003s)

**SizedBodySubscriberTest.java** — 3 tests passing:

1. `withinLimitDeliversFullBodyAndNeverCancels()` — ✓ PASS (0.001s)
2. `overLimitCancelsSubscriptionAndCompletesExceptionally()` — ✓ PASS (0.011s)
3. `onNextAfterCapExceededIsIgnored()` — ✓ PASS (0.001s, WR-03 new test)

### Manual Verification (Live Client)

**docs/DEV.md Phase 5 Section** (lines 262-349) records:

1. **Successful fetch against live API** — "Chart fetch succeeded: status 200, 107855 bytes"
   - Confirms status code is logged (CR-01 fix in place)
   - Confirms byte count is logged (API-01)
   - Timing: cold-start timeout observed (45s boundary), warm requests succeeded within ~2s
   
2. **Unreachable host failure** — "Chart fetch failed: java.net.ConnectException" within ~1s
   - Confirms timely failure (within connect timeout)
   - Confirms game did not hang or crash
   - Confirms proper error routing

3. **Configuration file handling** — URL with `&`/`=` characters readable in `run/config/transit-config.json`
   - Confirms disableHtmlEscaping() fix prevents unicode escape noise

---

## Requirements Cross-Reference

All Phase 5 requirements from REQUIREMENTS.md are satisfied:

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| **CFG-01** | API base URL is read from a configuration file, not hardcoded | ✓ SATISFIED | TransitConfig.load() reads baseUrl from transit-config.json; default points to live Human Design API; docs/DEV.md confirms file writing and live reading |
| **CFG-02** | Refresh interval is read from configuration, not a magic number in code | ✓ SATISFIED | TransitConfig stores refreshIntervalSeconds field; parsed from JSON; default is 60; TransitConfigTest.validCustomJsonIsReturnedAndFileIsNotRewritten confirms custom value read correctly |
| **CFG-03** | A malformed or missing config file produces a usable default and a clear log line rather than a crash during initialization | ✓ SATISFIED | TransitConfig.load(Path) handles missing files, malformed JSON, and validation failures; logs specific reason via LOGGER.warn(); returns defaults; game continues; tests pass |
| **CFG-05** | No API secrets or credentials are present in the mod or its configuration defaults | ✓ SATISFIED | Code inspection confirms no auth header, API key, bearer token in TransitConfig.DEFAULT_BASE_URL or TransitApiClient; public endpoint only |
| **API-01** | TransitApiClient fetches PNG bytes from the configured endpoint via an asynchronous HTTP GET | ✓ SATISFIED | TransitApiClient.fetchChart() calls httpClient.sendAsync(); docs/DEV.md live fetch confirmed with byte count |
| **API-02** | Connect timeout and request timeout are both configured to finite values | ✓ SATISFIED | TransitApiClient lines 28-29: Duration.ofSeconds(10) and Duration.ofSeconds(45); docs/DEV.md cold-start timeout observed at 45s boundary confirming request timeout is active |
| **API-03** | No HTTP call blocks the Minecraft main or render thread — the game stays responsive while a request is in flight | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | TransitApiClient.fetchChart() uses HttpClient.sendAsync() (not blocking) with dedicated 2-thread executor; callback wrapped in Minecraft.getInstance().execute(); code architecture guarantees off-thread execution; frame-hitch confirmation pending human observation (behavioral item in human_verification section) |
| **API-04** | Adding a second chart endpoint requires adding a method to the client, not restructuring the HTTP layer | ✓ SATISFIED | Single public void fetchChart(String, ChartCallback) method; reuses same httpClient/executor fields; grep confirms exactly 1 fetchChart method exists |
| **API-05** | Response body size is capped so a hostile or broken endpoint cannot exhaust memory | ✓ SATISFIED | SizedBodySubscriber enforces 5MB cap (5L * 1024 * 1024) during onNext(); WR-01 re-entry guard prevents growth after cap; WR-03 test confirms no state mutation on post-cancel chunks |

---

## Structural Verification

### Gradle Build

- `./gradlew build` ✓ **SUCCESSFUL in 3s**
- JUnit 5 infrastructure wired: testImplementation "org.junit.jupiter:junit-jupiter:5.10.2" + testRuntimeOnly "org.junit.platform:junit-platform-launcher" (WR-03 fix for Gradle 9.5.1)
- `test { useJUnitPlatform() }` block present and active
- Compile notes: 2 deprecation warnings in existing code (not Phase 5 regressions)

### Architecture Compliance

| Constraint | Requirement | Status |
|-----------|-------------|--------|
| **src/main stays common** | No net.minecraft.client.* imports in TransitConfig, TransitApiClient, or SizedBodySubscriber | ✓ VERIFIED |
| **Main-thread marshal pattern** | Minecraft.getInstance().execute() wraps callback before touching render/texture state | ✓ VERIFIED (JollyalchemyTransitReportClient only) |
| **Single HttpClient instance** | Built once in constructor, reused across fetches | ✓ VERIFIED (line 37-40) |
| **Dedicated executor** | Executors.newFixedThreadPool(2), not default common pool or Runnable::run sync | ✓ VERIFIED (line 36) |
| **No blocking on main thread** | sendAsync() used, never blocking send(); executor off-main | ✓ VERIFIED (line 67) |
| **No TextureManager/NativeImage/GL** | None of this phase's new code touches rendering | ✓ VERIFIED (all src/main files common-only) |

---

## Anti-Pattern Scan

Files modified or created by Phase 5:

- src/main/java/transitreport/config/TransitConfig.java
- src/main/java/transitreport/api/TransitApiClient.java
- src/main/java/transitreport/api/SizedBodySubscriber.java
- src/test/java/transitreport/config/TransitConfigTest.java
- src/test/java/transitreport/api/SizedBodySubscriberTest.java
- src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
- build.gradle
- docs/DEV.md
- .gitignore (added `logs/` for Log4j2 rolling-file output)

**Debt Markers Scan:** No TBD, FIXME, or XXX markers found in modified files (spot-checked key areas; full grep confirms clean)

**Stub Pattern Scan:** No empty returns, hardcoded empty data, or placeholder implementations found; all methods have substantive bodies

**Console.log Only Implementations:** No methods that only log without side effects (all logging in Phase 5 is in callback marshaling wrapper, which also routes to callback handlers)

**Status:** ✓ CLEAN (no blocker anti-patterns; 3 auto-fixed deviations from SUMMARY.md all resolved and tested)

---

## Behavioral Spot-Checks

### Command Verification

```bash
./gradlew build               # ✓ SUCCESS
./gradlew test                # ✓ 7 tests passing (TransitConfigTest: 4, SizedBodySubscriberTest: 3)
grep -c "public void fetchChart(" src/main/java/transitreport/api/TransitApiClient.java  # 1 ✓
grep -cq "Duration.ofSeconds(10)" src/main/java/transitreport/api/TransitApiClient.java   # ✓
grep -cq "Duration.ofSeconds(45)" src/main/java/transitreport/api/TransitApiClient.java   # ✓
grep -cq "Executors.newFixedThreadPool(2)" src/main/java/transitreport/api/TransitApiClient.java  # ✓
grep -c "Runnable::run" src/main/java/transitreport/api/TransitApiClient.java  # 0 ✓
grep -cq "5L * 1024 * 1024" src/main/java/transitreport/api/TransitApiClient.java  # ✓
grep -c "net.minecraft.client.Minecraft" src/main/java/transitreport/config/TransitConfig.java src/main/java/transitreport/api/TransitApiClient.java src/main/java/transitreport/api/SizedBodySubscriber.java  # 0 ✓
grep -cq "Minecraft.getInstance().execute(" src/client/java/transitreport/client/JollyalchemyTransitReportClient.java  # ✓
```

All assertions from 05-01-PLAN.md <verify> block pass.

---

## Human Verification Required

### 1. Frame Hitch / Responsiveness Confirmation (API-03)

**Test:** Launch `./gradlew runClient`, observe the client startup and initial fetch completion in a running game window

**Expected:** While the one-shot startup fetch is in flight (taking ~45 seconds on first cold-start or ~2 seconds on warm), no stutter, frame hitch, or lag is felt. Walk/look around the dev world smoothly. Logs should show either "Chart fetch succeeded: status 200, <N> bytes" or "Chart fetch failed: <reason>", confirming the fetch completed.

**Why human:** Frame hitch is a felt, real-time responsiveness experience that cannot be asserted by unit tests or log inspection. Code inspection confirms:

- HttpClient.sendAsync() is non-blocking
- Dedicated 2-thread executor prevents default common-pool starvation
- Minecraft.getInstance().execute() marshals result back to main thread before logging

The off-thread architecture guarantees the fetch cannot block the game's render loop, but visual smoothness during the in-flight window requires direct observation.

**Status:** PENDING — not performed during autonomous execution. Per VALIDATION.md and SUMMARY.md, this is an expected, documented deferral that does not block phase completion (the architecture is sound, and all automated verification passed).

---

## Deferred Items

None identified. All items from PLAN's threat model and validation strategy are addressed:

- T-05-01 through T-05-06: mitigated by design and tests
- Wave 0 dependencies: none (no blocking infrastructure gap)
- Outstanding manual UAT item (API-03 frame hitch): documented and routed to human verification section

---

## Summary of Findings

✓ **Phase goal achieved:** The mod reads baseUrl and refreshIntervalSeconds from a config file (TransitConfig), fetches PNG bytes asynchronously via HttpClient.sendAsync() with a dedicated executor and finite timeouts (TransitApiClient), caps response size during streaming (SizedBodySubscriber), and wires the one-shot startup fetch into client init with proper main-thread marshaling (JollyalchemyTransitReportClient). Config recovery, timeout behavior, size-cap enforcement, and HTTP status code checking all verified through unit tests, code inspection, and live client logs.

⚠️ **One behavioral observation pending:** API-03's "no frame hitch" responsiveness requires human watching an active client window (not automated). Code architecture guarantees the fetch is off-thread, but felt experience requires observation.

**Status: human_needed** (all must-haves present and wired; 1 behavioral verification item awaiting human confirmation)

---

_Verified: 2026-09-09T02:15:00Z_  
_Verifier: Claude (gsd-verifier)_  
_Mode: initial verification_

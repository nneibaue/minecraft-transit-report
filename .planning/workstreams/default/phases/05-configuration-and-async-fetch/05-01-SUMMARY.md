---
phase: 05-configuration-and-async-fetch
plan: 01
subsystem: api
tags: [java.net.http, gson, fabric-loader, junit5, config, async-http]

# Dependency graph
requires:
  - phase: 01-toolchain-verification
    provides: working ./gradlew build/runClient dev loop, JDK/Loom toolchain
provides:
  - "TransitConfig: Gson-backed config file (baseUrl, refreshIntervalSeconds), default-write-on-missing, full-reset-on-malformed"
  - "TransitApiClient: single-method (fetchChart) async HTTP GET client with finite connect/request timeouts and a dedicated executor"
  - "SizedBodySubscriber: streaming 5MB response-size cap enforced during onNext(), not post-hoc"
  - "One-shot D-05 startup fetch wired into JollyalchemyTransitReportClient, demonstrating the Minecraft.getInstance().execute() main-thread hand-back pattern"
  - "First JUnit 5 test infrastructure in this repo (junit-jupiter + junit-platform-launcher, useJUnitPlatform())"
affects: [07-block-renderer-http-join, 08-scheduler, 09-reliability, 10-manual-refresh-and-config-command]

actuals:
  tokens: 7735
  tasks: 2
  commits: 3

tech-stack:
  added: ["org.junit.jupiter:junit-jupiter:5.10.2", "org.junit.platform:junit-platform-launcher"]
  patterns:
    - "Package-private load(Path) delegate for Fabric-runtime-free unit testing (public load() resolves FabricLoader.getConfigDir(), delegates to load(Path))"
    - "Streaming size-cap enforcement via a custom HttpResponse.BodySubscriber, checked in onNext() against actual bytes, never a post-hoc Content-Length check"
    - "src/main stays common (no net.minecraft.client.* import); the single Minecraft.getInstance().execute() hop lives only at the src/client call site"

key-files:
  created:
    - src/main/java/transitreport/config/TransitConfig.java
    - src/main/java/transitreport/api/TransitApiClient.java
    - src/main/java/transitreport/api/SizedBodySubscriber.java
    - src/test/java/transitreport/config/TransitConfigTest.java
    - src/test/java/transitreport/api/SizedBodySubscriberTest.java
  modified:
    - build.gradle
    - src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
    - docs/DEV.md
    - .gitignore

key-decisions:
  - "Gson's default HTML-safe escaping (mangles '&'/'=' in the hand-edited baseUrl) was disabled via disableHtmlEscaping() on the defaults-writer Gson instance -- caught by TransitConfigTest before it ever reached a live config file."
  - "Added testRuntimeOnly org.junit.platform:junit-platform-launcher beyond what 05-01-PLAN.md specified -- Gradle 9.5.1's test task fails outright ('Failed to load JUnit Platform') without it."
  - "Config revert after the D-06 unreachable-host test was done by deleting run/config/transit-config.json (gitignored dev state) rather than hand-editing the URL back -- guarantees the next launch writes the exact canonical default JSON."

patterns-established:
  - "TDD RED/GREEN commits for Java: RED-phase stubs must compile (so tests fail on assertions, not compile errors) but deliberately implement nothing -- see the RED commit's TransitConfig/SizedBodySubscriber stub bodies."

requirements-completed: [CFG-01, CFG-02, CFG-03, CFG-05, API-01, API-02, API-03, API-04, API-05]

coverage:
  - id: D1
    description: "TransitConfig reads baseUrl/refreshIntervalSeconds from transit-config.json, writes defaults on first run, and recovers to full defaults (both fields) on any parse or validation failure, logging the specific reason"
    requirement: "CFG-01, CFG-02, CFG-03"
    verification:
      - kind: unit
        ref: "src/test/java/transitreport/config/TransitConfigTest.java#missingFileYieldsDefaultsAndWritesFile, #validCustomJsonIsReturnedAndFileIsNotRewritten, #syntacticallyInvalidJsonYieldsDefaultsForBothFieldsAndOverwritesFile, #nonPositiveRefreshIntervalResetsBothFieldsToDefaults"
        status: pass
      - kind: manual_procedural
        ref: "Live runClient session: run/config/transit-config.json written with defaults on first launch, readable baseUrl with '&'/'=' intact (disableHtmlEscaping fix confirmed live)"
        status: pass
    human_judgment: false
  - id: D2
    description: "SizedBodySubscriber caps response size at 5MB during streaming, aborting mid-chunk (cancel + completeExceptionally) rather than a post-hoc Content-Length check"
    requirement: "API-05"
    verification:
      - kind: unit
        ref: "src/test/java/transitreport/api/SizedBodySubscriberTest.java#withinLimitDeliversFullBodyAndNeverCancels, #overLimitCancelsSubscriptionAndCompletesExceptionally"
        status: pass
    human_judgment: false
  - id: D3
    description: "TransitApiClient exposes exactly one fetchChart(String, ChartCallback) method, built on one reused HttpClient with a dedicated 2-thread executor, 10s connect / 45s request timeouts, and substitutes {date}/{time} tokens"
    requirement: "API-01, API-02, API-03, API-04"
    verification:
      - kind: other
        ref: "grep assertions in 05-01-PLAN.md <verify> block: Duration.ofSeconds(10)/(45) present, Executors.newFixedThreadPool(2) present with zero Runnable::run, exactly one 'public void fetchChart(' method, zero net.minecraft.client.Minecraft imports in src/main"
        status: pass
      - kind: manual_procedural
        ref: "Live runClient: 'Chart fetch succeeded: status 200, 107855 bytes' against the real API; 'Chart fetch failed: java.net.ConnectException' within ~1s against a deliberately unreachable .invalid host; 'Chart fetch failed: java.net.http.HttpTimeoutException: request timed out' at the 45s boundary on a cold-started Render.com free-tier instance -- no hang, no crash in any case"
        status: pass
    human_judgment: false
  - id: D4
    description: "Shipped config defaults and TransitApiClient contain no API secret, key, or credential"
    requirement: "CFG-05"
    verification:
      - kind: other
        ref: "Code inspection of TransitConfig.java and TransitApiClient.java -- no auth header, API key, bearer token, or credential field anywhere"
        status: pass
    human_judgment: false
  - id: D5
    description: "The one-shot D-05 startup fetch is wired into JollyalchemyTransitReportClient.onInitializeClient(), and the game stays responsive (no frame hitch) while the request is in flight"
    verification:
      - kind: manual_procedural
        ref: "Log evidence confirms the fetch fires once at startup and completes/fails without hanging the client (see D3's live evidence); frame-hitch/no-stutter has NOT been confirmed by a human this session"
        status: unknown
    human_judgment: true
    rationale: "No-frame-hitch is a felt, real-time experience during an active runClient session -- Claude launched runClient and tailed the log (confirming the fetch fired and completed/failed cleanly), but the actual visual/tactile confirmation that no stutter occurred requires a human physically watching and interacting with the window, which did not happen in this autonomous session."

duration: ~40min
completed: 2026-09-08
status: complete
---

# Phase 5 Plan 1: Configuration and Async Fetch Summary

**Gson-backed TransitConfig with full-reset-on-malformed recovery, TransitApiClient's single-method async HTTP GET with a streaming 5MB cap and finite connect/request timeouts, verified live against the real Human Design API including a Render.com free-tier cold-start timeout and a clean unreachable-host failure**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-09-09T01:00:00Z (approx.)
- **Completed:** 2026-09-09T01:23:10Z
- **Tasks:** 2 completed
- **Files modified:** 9 (5 created, 4 modified)

## Accomplishments

- `TransitConfig` reads/writes `transit-config.json` via Gson, recovers to full defaults on any parse or validation failure with a reason-specific log line (CFG-01/02/03, D-11/D-12/D-13/D-14)
- `SizedBodySubscriber` enforces a 5MB response cap during streaming, aborting mid-chunk as an ordinary failure (API-05, D-09/D-10)
- `TransitApiClient` fetches PNG bytes via one reused `HttpClient`, a dedicated 2-thread executor, and exactly one `fetchChart(String, ChartCallback)` method (API-01..04, D-08)
- The D-05 one-shot startup fetch is wired into `JollyalchemyTransitReportClient`, demonstrating the `Minecraft.getInstance().execute()` main-thread hand-back this project's later phases must copy
- Live-verified against the real Human Design API: a cold-start timeout, a warm success (status 200 + byte count), and a clean `ConnectException` against a deliberately unreachable host -- all logged, none hung or crashed the client
- First JUnit 5 test infrastructure added to this repo; `TransitConfigTest` and `SizedBodySubscriberTest` cover every `behavior` case from 05-01-PLAN.md

## Task Commits

Each task was committed atomically, following the TDD RED-GREEN protocol for Task 1:

1. **Task 1 RED: failing tests for TransitConfig and SizedBodySubscriber** - `897154a` (test)
2. **Task 1 GREEN: implement TransitConfig, TransitApiClient, SizedBodySubscriber, wire D-05 fetch** - `2831ca3` (feat)
3. **Task 2: live verification findings recorded in docs/DEV.md** - `f9f4cd8` (docs)

No REFACTOR commit was needed -- the GREEN implementation was clean on the first pass (only the Gson-escaping and `logs/`-gitignore fixes were needed, both folded into the GREEN commit).

**Plan metadata:** captured in this SUMMARY.md's final commit (STATE.md/ROADMAP.md/REQUIREMENTS.md updates).

_Note: TDD tasks may have multiple commits (test to feat to refactor)._

## Files Created/Modified

- `src/main/java/transitreport/config/TransitConfig.java` - Gson-backed config POJO, load/writeDefaults, CFG-01/02/03
- `src/main/java/transitreport/api/TransitApiClient.java` - single-method async HTTP client, API-01..05
- `src/main/java/transitreport/api/SizedBodySubscriber.java` - streaming 5MB cap enforcement
- `src/test/java/transitreport/config/TransitConfigTest.java` - 4 cases covering CFG-01/02/03/D-11
- `src/test/java/transitreport/api/SizedBodySubscriberTest.java` - 2 cases covering D-09/D-10
- `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` - D-05 one-shot fetch, main-thread marshal
- `build.gradle` - JUnit 5 test source set (junit-jupiter, junit-platform-launcher, useJUnitPlatform())
- `.gitignore` - added `logs/` (Log4j2 rolling-file output, previously untracked)
- `docs/DEV.md` - new "Phase 5 configuration and async fetch findings" section

## Decisions Made

- Disabled Gson's default HTML-safe escaping (`disableHtmlEscaping()`) on the config-defaults writer -- the default would silently turn `&`/`=` in the hand-edited `baseUrl` template into unicode escape noise, defeating CFG-01's whole purpose of a human-editable file. Caught by `TransitConfigTest` before ever reaching a live file.
- Added `testRuntimeOnly "org.junit.platform:junit-platform-launcher"` beyond what 05-01-PLAN.md's action step specified -- Gradle 9.5.1 does not pull this in transitively from `junit-jupiter` alone; without it `./gradlew test` fails before running any test ("Failed to load JUnit Platform").
- Reverted the D-06 unreachable-host config edit by deleting `run/config/transit-config.json` (gitignored dev state) rather than hand-editing the URL string back -- guarantees the next launch's `TransitConfig.load()` writes back the byte-exact canonical default JSON.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Gson's default HTML-safe escaping mangled the config's URL value**
- **Found during:** Task 1 GREEN implementation, running `TransitConfigTest`
- **Issue:** `new GsonBuilder().setPrettyPrinting().create()` (no `disableHtmlEscaping()`) escapes `&`/`=`/`<`/`>`/`'` as unicode sequences by default. `TransitConfig.DEFAULT_BASE_URL` is a URL template full of `&` and `=` that a human is meant to hand-edit (D-02) -- the written file would show unreadable escape noise instead of the literal URL.
- **Fix:** Added `.disableHtmlEscaping()` to the Gson builder used in `writeDefaults(Path)`.
- **Files modified:** `src/main/java/transitreport/config/TransitConfig.java`
- **Verification:** `TransitConfigTest#syntacticallyInvalidJsonYieldsDefaultsForBothFieldsAndOverwritesFile` passes; live `run/config/transit-config.json` confirmed readable with `&`/`=` intact.
- **Committed in:** `2831ca3` (Task 1 GREEN commit)

**2. [Rule 3 - Blocking] Missing JUnit Platform launcher dependency**
- **Found during:** Task 1 RED phase, first `./gradlew test` invocation
- **Issue:** `./gradlew test` failed with "Failed to load JUnit Platform. Please ensure that all JUnit Platform dependencies are available..." before running any test -- Gradle 9.5.1 does not transitively resolve the platform launcher from `junit-jupiter` alone.
- **Fix:** Added `testRuntimeOnly "org.junit.platform:junit-platform-launcher"` to `build.gradle`.
- **Files modified:** `build.gradle`
- **Verification:** `./gradlew test` runs and reports individual test results afterward.
- **Committed in:** `897154a` (Task 1 RED commit)

**3. [Rule 3 - Blocking] Untracked `logs/` directory from Log4j2's rolling-file appender**
- **Found during:** Task 1 GREEN commit staging (`git status --short` review)
- **Issue:** Running the JUnit test JVM (which logs via `JollyalchemyTransitReport.LOGGER`/SLF4J/Log4j2) created an untracked `logs/` directory with rotated `.log.gz` files at the repo root -- not previously covered by `.gitignore`.
- **Fix:** Added `logs/` to `.gitignore`.
- **Files modified:** `.gitignore`
- **Verification:** `git status --short` shows no untracked `logs/` entries after the fix.
- **Committed in:** `2831ca3` (Task 1 GREEN commit)

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking). All necessary for correctness (Gson escaping) or for the build/repo hygiene to actually work (JUnit Platform launcher, `.gitignore`). No scope creep.

## Issues Encountered

- **First live `runClient` fetch timed out at the full 45s `REQUEST_TIMEOUT` boundary** against the real Human Design API (Render.com free tier, cold-started after idling) -- not a bug: this is exactly the scenario D-08's 45-second timeout was chosen to tolerate (30-50s observed cold-start range), and a `curl` moments later (which woke the service) returned in 2.13s. A second `runClient` launch immediately after succeeded cleanly. Documented in `docs/DEV.md`'s Phase 5 section as directly-observed confirmation of D-08's reasoning, not a defect.
- **`SizedBodySubscriberTest`'s first test hung indefinitely during RED-phase authoring** because the intentionally-incomplete RED stub's `onComplete()` never completed the result future, and the test called a bare (unbounded) `.get()`. Fixed by adding a 5-second bound (`get(5, TimeUnit.SECONDS)`) to both `.get()` calls in the test -- a broken/incomplete implementation now fails fast instead of hanging the test suite, which is itself a better test regardless of RED/GREEN phase.
- **Fetch callbacks run on `ForkJoinPool.commonPool-worker-1`, not `TransitApiClient`'s own dedicated executor** -- observed consistently across all three live `runClient` sessions. Investigated and determined to be a JDK `HttpClient` internal implementation detail (how a custom `BodySubscriber`'s own `CompletableFuture` combines with the response-received stage), not a bug: the callback still never touches the Render thread directly, and `JollyalchemyTransitReportClient` still correctly marshals through `Minecraft.getInstance().execute(...)` before logging. Documented in `docs/DEV.md` so a future phase doesn't waste time assuming the dedicated executor is broken.

## User Setup Required

None - no external service configuration required. The default `baseUrl` in `TransitConfig` already points at the live, public Human Design API with no credentials.

## Next Phase Readiness

- Both halves of the architecture (config load/recovery, async fetch with timeouts/size-cap) are proven working in total isolation from the block/renderer/texture track (Phases 2-4), as this phase was designed to demonstrate -- any Phase 7 join failure should localize to the hand-back itself.
- **Outstanding, needs a human:** the D-07 no-frame-hitch/responsiveness confirmation was not observed this session -- Claude launched `runClient` and confirmed via log tailing that the fetch fires once, completes or fails cleanly, and never hangs the client, but the felt, real-time "no stutter" experience requires a human watching an active window. A human should run `./gradlew runClient`, wait through the startup fetch, and confirm no stutter is felt, at their convenience -- this does not block Phase 5 from being considered functionally complete (all automated verification passed, and the architecture guarantees the fetch is off-thread), but it is the one checklist item this SUMMARY cannot mark as directly observed.
- Whether the D-05 one-shot startup fetch scaffolding in `JollyalchemyTransitReportClient` is deleted or left inert once Phase 8's real scheduler exists is explicitly Phase 8's decision (05-CONTEXT.md), not resolved here.
- Phase 8 (scheduler) can reuse `TransitApiClient` and `TransitConfig` as-is; Phase 7 (block/renderer join) can reuse `TransitApiClient.fetchChart` directly once ready to hand PNG bytes to the texture pipeline.

---
*Phase: 05-configuration-and-async-fetch*
*Completed: 2026-09-08*

## Self-Check: PASSED

All 7 created/modified files confirmed present on disk; all 3 commit hashes (897154a, 2831ca3, f9f4cd8) confirmed present in git history.

# Phase 5: Configuration and Async Fetch - Research

**Researched:** 2026-09-08
**Domain:** Fabric config file handling + async HTTP client + thread marshaling
**Confidence:** HIGH

## Summary

Phase 5 introduces two independent, testable components: **TransitConfig**, a Gson-backed config file handler that reads a base URL template and refresh interval from disk; and **TransitApiClient**, an async HTTP client that fetches PNG bytes without blocking the game thread. The phase depends only on Phase 1 (toolchain) and can be built in parallel with Phases 2-4. No rendering, no textures, no blocking calls — just config I/O and HTTP work. The architecture is deliberately isolated so that when Phase 7 joins this work to the texture pipeline, any failure can be pinpointed to the join, not to either half alone.

**Primary recommendation:** Use `java.net.http.HttpClient` with a dedicated `ScheduledExecutorService`, hand-rolled Gson+`FabricLoader.getConfigDir()` for config, and explicit `Minecraft.getInstance().execute(...)` callbacks to marshal async work back to the main thread before any state mutations.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Default base URL is the **real Human Design API**: `https://human-design-4u01.onrender.com` — not a placeholder or changing-image dummy endpoint. This is the live endpoint discovered and confirmed in Phase 4 context.

- **D-02:** Config stores the **full URL template, including path and query parameters**: e.g., `https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false`. Not just scheme+host; the entire request shape is user-editable.

- **D-03:** `{date}` and `{time}` are **placeholder tokens** literally in the config string. Before each fetch, `TransitApiClient` substitutes the current timestamp using simple string replacement. The exact date/time format the API expects (e.g., `2026-09-08` and `06:06` with colon URL-encoded to `%3A`) is unresolved and must be confirmed before fetch testing.

- **D-04:** Default refresh interval: **60 seconds**. Matches REQUIREMENTS.md's stated default. No scheduler exists this phase; Phase 8 builds the recurring timer. This phase just reads and stores the interval value.

- **D-05:** A **one-shot verification fetch from `onInitializeClient()`** at client startup — temporary scaffolding, not load-bearing. No debug command, no keybind, no UI. Purpose: prove the pipeline works before Phase 8 adds scheduling. May be deleted or left inert once Phase 8 exists.

- **D-06:** Failure-path verification (timeouts, oversized responses) happens by **manually editing the config file** to point at a bad host, restarting the client, observing logs, then editing back. No mock server this phase; REQUIREMENTS.md defers MOCK-01/02/03 to v2.

- **D-07:** Responsiveness verification (no frame hitch during fetch) is **visual** — same protocol as prior phases: Claude launches `runClient`, user walks around the dev world during the startup fetch, confirms no stutter.

- **D-08:** Connect timeout **10 seconds**, request timeout **45 seconds**. Deliberately generous because the live API (D-01) runs on Render.com's free tier, which cold-starts in 30-50 seconds. Tighter timeouts would misclassify slow-wake-up as unreachable.

- **D-09:** Maximum response body: **5 MB**. Defensive backstop for memory; realistic PNGs at 512×800 are well under 1 MB.

- **D-10:** On oversized response, **abort and treat as ordinary failure** — same path as any other failure (REL-01/04). Last image stays on screen (once Phase 6/7 exist), one log line, no crash. Truncate-and-attempt-decode was rejected: truncated PNGs almost never decode, so it buys nothing.

- **D-11:** Config parse/validation error? **All fields reset to defaults** — not per-field salvage. One bad value means the whole file is untrusted.

- **D-12:** On malformed-config fallback, **overwrite the bad file with fresh defaults**. Same path handles "file missing" (first run, CFG-01) and "file malformed" (CFG-03 recovery) identically.

- **D-13:** Config validation is **minimal — type/shape only**: base URL must be a non-empty string, interval must be positive. No URI well-formedness check, no min/max range clamp. Wrong URLs fail at fetch time via the ordinary failure path.

### Claude's Discretion

- **D-14:** Log message on malformed-config fallback should **include the specific reason** — e.g., "Config malformed (JSON parse error / non-positive refreshIntervalSeconds); using defaults, rewrote config.json". This was flagged for user confirmation and none was received; treat it as the recommended default unless planning finds a concrete reason against it.

- **D-03 (date/time format):** The exact format the live API expects (`date=2026-09-08&time=06%3A06` from Phase 4) needs confirming. Whether Java's `HttpRequest`/`URI` builder requires manual encoding of substituted values or handles it automatically is also unresolved.

- Gson field names, Java types (e.g., interval as `int` seconds vs. a richer type), config POJO class name/location — unconstrained implementation details. Follow CLAUDE.md §5 directly.

- Whether D-05's one-shot startup fetch is deleted or merely left inert once Phase 8's scheduler exists is Phase 8's decision, not locked here.

### Deferred Ideas (OUT OF SCOPE)

- **Debug client command or keybind for repeatable fetch triggering** — explicitly not chosen for this phase (D-05). Phase 10's CFG-04 (author-only command to reload config and repoint API at runtime) is closely related but lands later.

- **URI well-formedness or interval-range validation on config load** — explicitly rejected (D-13) in favor of minimal type-only validation. Revisit only if wrong-but-type-valid config causes real problems in practice.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CFG-01 | API base URL is read from a configuration file, not hardcoded | Hand-rolled Gson + `FabricLoader.getConfigDir()` documented in CLAUDE.md §5; config loading on mod init |
| CFG-02 | Refresh interval is read from configuration, not a magic number in code | Same config POJO holds both URL and interval; read on init, stored in `TransitConfig` |
| CFG-03 | Malformed or missing config file produces a usable default and clear log line rather than a crash | D-11/D-12 strategy: reset all fields on parse error, overwrite bad file, one log line with reason (D-14) |
| CFG-05 | No API secrets or credentials in mod or config defaults | Real API URL is public; no auth headers, keys, or tokens in config or code |
| API-01 | `TransitApiClient` fetches PNG bytes from configured endpoint via async HTTP GET | `java.net.http.HttpClient` with `sendAsync()`, custom `BodySubscriber` for size cap (D-10) |
| API-02 | Connect timeout and request timeout configured to finite values | D-08: 10s connect, 45s request, tunable `Duration` constants |
| API-03 | No HTTP call blocks main or render thread; game stays responsive during request | Dedicated executor (single/two-thread pool), callbacks marshal via `Minecraft.getInstance().execute(...)` |
| API-04 | Adding second endpoint requires adding a method, not restructuring HTTP layer | Single `fetchChart(String url, callback)` method; second endpoint calls it with different URL |
| API-05 | Response body size capped to prevent memory exhaustion | D-09/D-10: 5 MB cap, abort on overflow, custom `BodySubscriber` implementation |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Config file I/O | Common (src/main) | — | No client-only imports; config must survive potential server-side usage (multiplayer forward-compat per PROJECT.md). Read on mod init in `onInitialize()`. |
| HTTP request building + sending | Common (src/main or src/client) | — | HTTP client itself is reusable from common code (no client-only deps); decision deferred to planner whether to scope it common for multiplayer forward-compat or client-only for simplicity this phase. CLAUDE.md §7 calls it client-scoped "for this phase's purposes," suggesting client is acceptable. |
| Callback marshaling to main thread | Client (src/client) | — | `Minecraft.getInstance().execute(...)` is client-only. The fetch *initiation* can be common, but the *result callback* must be client-scoped. |
| One-shot verification fetch (D-05) | Client (src/client) | — | Temporary scaffolding in `onInitializeClient()`. Lives in `JollyalchemyTransitReportClient`. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `java.net.http.HttpClient` | JDK 17+ (built-in, no dependency) | Async HTTP GET for PNG bytes | Guaranteed present on every Java 17+ runtime; zero external dependencies (CLAUDE.md §3); no shading or JVM-internal interaction issues with Fabric's Knot classloader. Alternatives (OkHttp, Apache HttpClient) add transitive deps and logging-stack conflicts for capabilities `HttpClient` already provides (retries, pooling, HTTP/2, timeouts). |
| Gson | Bundled with Minecraft (no new dependency needed) | Config file (de)serialization | Already on classpath; avoids duplicate-version conflicts if a standalone Gson were added. CLAUDE.md §5 explicitly recommends using the bundled copy. |
| `FabricLoader.getConfigDir()` | Fabric API 0.92.12+1.20.1 (already in project) | Get per-instance config directory | Standard Fabric pattern; handles per-server and per-world config dir logic. Returns `java.nio.file.Path`. |
| `java.nio.file` (Path, Files, StandardOpenOption) | JDK 17+ (built-in) | File I/O, write defaults, read JSON | Standard JDK NIO; handles encoding, file creation, write-atomic patterns. |
| `java.time` (LocalDate, LocalTime, ZonedDateTime) | JDK 17+ (built-in) | Date/time formatting for API substitution (D-03) | Standard for formatting `{date}` and `{time}` tokens. Exact format (ISO-8601, UTC, locale-aware) unresolved; confirm against live API contract. |
| `java.util.concurrent` (ScheduledExecutorService, Executors) | JDK 17+ (built-in) | Dedicated executor for async HTTP callbacks | Prevents `HttpClient`'s default `ForkJoinPool.commonPool()` from shared-pool contention; one-thread or two-thread fixed pool is suitable. Supports `sendAsync()` callbacks. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SLF4J (via Minecraft's bundled logging stack) | 1.x (already available) | Logging fetch status, errors, config fallback reason (D-14) | Standard Fabric logging via `LoggerFactory.getLogger(MOD_ID)`. Existing example in `JollyalchemyTransitReport.java`. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `java.net.http.HttpClient` | OkHttp or Apache HttpClient | Adds Maven dependency (own versioning per MC version), transitive deps (OkHttp → okio), logging-binding conflicts with Minecraft's Log4j setup. OkHttp justified only if you need interceptors, connection-pool tuning beyond `HttpClient`'s `.connectionTimeout()`, or HTTP/2 push — none apply here. |
| Hand-rolled Gson + FabricLoader.getConfigDir() | Cloth Config / owo-lib / midnightlib | All three build in-game config *screens*; this project has two fields, no GUI requirement (PROJECT.md Out of Scope). Cloth Config adds a real Maven dependency, increases JAR size, and imports a GUI-building API for zero net capability gained this phase. |
| `FabricLoader.getConfigDir()` + explicit Path IO | A separate config library (e.g., aconfig, configurate) | Adds another Maven dependency; `FabricLoader.getConfigDir()` + `java.nio.file` + Gson is 30 lines of code and needs no new library. Hand-rolled is justified here per PROJECT.md's "avoid premature abstraction" constraint for two-field config. |

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Minecraft Game Client                        │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  JollyalchemyTransitReportClient.onInitializeClient()       │ │
│  │  (D-05: one-shot verification fetch on startup)             │ │
│  │                         │                                   │ │
│  │                         ↓                                   │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │ TransitApiClient.fetchChart(url, callback)           │  │ │
│  │  │ (D-03: substitute {date}/{time}, build URI)          │  │ │
│  │  │                         │                            │  │ │
│  │  │     (async HTTP path)  ↓                            │  │ │
│  │  │  ┌─────────────────────────────────────────────────┐ │  │ │
│  │  │  │ Dedicated Executor: HttpClient.sendAsync()      │ │  │ │
│  │  │  │ • Custom BodySubscriber (D-10: 5MB cap)        │ │  │ │
│  │  │  │ • Timeout handlers (D-08: 10s conn, 45s req)  │ │  │ │
│  │  │  │ • Status & byte count logging                  │ │  │ │
│  │  │  │    (HTTP response complete on background pool) │ │  │ │
│  │  │  └─────────────────────────────────────────────────┘ │  │ │
│  │  │                         │                            │  │ │
│  │  │           (callback returns to callback thread)     │  │ │
│  │  │                         ↓                            │  │ │
│  │  │  ┌─────────────────────────────────────────────────┐ │  │ │
│  │  │  │ Minecraft.getInstance().execute(...)            │ │  │ │
│  │  │  │ (marshal callback back to main thread)          │ │  │ │
│  │  │  └─────────────────────────────────────────────────┘ │  │ │
│  │  │                         │                            │  │ │
│  │  │     (main thread resumes)  ↓                         │  │ │
│  │  │  ┌─────────────────────────────────────────────────┐ │  │ │
│  │  │  │ Callback: Result (bytes/error) passed to        │ │  │ │
│  │  │  │ next phase's texture pipeline (Phase 6/7)      │ │  │ │
│  │  │  │ OR logged as failure (this phase stops)        │ │  │ │
│  │  │  └─────────────────────────────────────────────────┘ │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  │                                                             │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │ TransitConfig (src/main)                             │  │ │
│  │  │ • Read: FabricLoader.getConfigDir() + Gson          │  │ │
│  │  │ • On missing: write defaults (CFG-01)               │  │ │
│  │  │ • On parse error: reset all → defaults (CFG-03)     │  │ │
│  │  │ • Holds: baseUrl (D-02), refreshIntervalSeconds (D-04) │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Network (HTTP to external API)                             │ │
│  │ GET {baseUrl} (with {date}/{time} substituted)            │ │
│  │ ← 200 OK: PNG bytes, logged                               │ │
│  │ ← 5xx, timeout, unreachable: failure, logged              │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
src/
├── main/
│   └── java/transitreport/
│       ├── JollyalchemyTransitReport.java
│       ├── TransitReportBlocks.java
│       ├── config/
│       │   └── TransitConfig.java          [NEW] src/main — no client imports
│       ├── api/
│       │   └── TransitApiClient.java       [NEW] src/main or src/client per planner decision
│       └── block/
│           ├── TransitChartBlock.java
│           └── entity/
│               └── TransitChartBlockEntity.java
└── client/
    └── java/transitreport/client/
        ├── JollyalchemyTransitReportClient.java
        └── TransitChartRenderer.java
```

### Pattern 1: TransitConfig — Gson + FabricLoader.getConfigDir()

**What:** A single-responsibility POJO that handles config file lifecycle: read on mod init, write defaults if missing, reset to defaults on parse/validation error, expose typed fields (baseUrl, refreshIntervalSeconds) to the rest of the mod.

**When to use:** Whenever a Fabric mod needs to persist user-editable settings to disk without a config screen. This pattern scales up to 10-20 fields before a more sophisticated library becomes justified.

**Structure:**

```java
// Source: CLAUDE.md §5, hand-rolled Gson + FabricLoader pattern
public class TransitConfig {
    public String baseUrl = "https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false";
    public int refreshIntervalSeconds = 60;

    private static final String CONFIG_NAME = "transit-config.json";
    private static final Logger LOGGER = LoggerFactory.getLogger(JollyalchemyTransitReport.MOD_ID);

    // Load from disk, write defaults if missing/malformed
    public static TransitConfig load() {
        Path configDir = FabricLoader.getInstance().getConfigDir();
        Path configFile = configDir.resolve(CONFIG_NAME);

        // Case 1: File exists, try to parse
        if (Files.exists(configFile)) {
            try {
                String json = Files.readString(configFile);
                TransitConfig config = new Gson().fromJson(json, TransitConfig.class);
                
                // Validate (D-13: type/shape only)
                if (config.baseUrl != null && !config.baseUrl.isEmpty() 
                    && config.refreshIntervalSeconds > 0) {
                    return config;
                }
                
                // Parse succeeded but validation failed
                LOGGER.warn("Config file was malformed (validation failed); using defaults and rewriting config.json");
                return writeDefaults(configFile);
                
            } catch (IOException e) {
                LOGGER.warn("Config file I/O error; using defaults and rewriting config.json", e);
                return writeDefaults(configFile);
            } catch (JsonSyntaxException e) {
                LOGGER.warn("Config file was malformed (JSON parse error); using defaults and rewriting config.json");
                return writeDefaults(configFile);
            }
        }

        // Case 2: File missing (first run or deleted)
        return writeDefaults(configFile);
    }

    private static TransitConfig writeDefaults(Path configFile) {
        TransitConfig defaults = new TransitConfig();
        try {
            Files.createDirectories(configFile.getParent());
            Files.writeString(configFile, new GsonBuilder().setPrettyPrinting().create().toJson(defaults));
        } catch (IOException e) {
            LOGGER.error("Failed to write default config file", e);
        }
        return defaults;
    }
}
```

**Why this pattern:**
- No external dependencies beyond Gson (already bundled).
- No config screen complexity — just JSON file and POJO.
- Recovers gracefully from missing/malformed files (CFG-03).
- Follows CLAUDE.md §5's explicit recommendation for this project's scope.
- Easy to expand to more fields later without library overhead.

### Pattern 2: TransitApiClient — Dedicated Executor + HttpClient.sendAsync()

**What:** A wrapper around `java.net.http.HttpClient` that builds and sends requests asynchronously via a dedicated executor, enforces timeouts and size caps (D-08, D-09, D-10), logs results with byte count and HTTP status (success criterion 3), and hands results back to the caller via callbacks that must marshal to the main thread themselves.

**When to use:** Whenever a Fabric mod needs to fetch arbitrary data from the internet without blocking the game thread. The dedicated executor prevents thread-pool contention; custom `BodySubscriber` enforces the size cap; explicit callback marshaling (caller's responsibility) keeps render state out of the async path.

**Key constraints from CLAUDE.md §3:**
- Build the `HttpClient` **once** at mod init or client init, reuse it.
- Use a **dedicated executor** (1-2 thread fixed pool), not `Runnable::run`, not `ForkJoinPool.commonPool()`.
- **Connect timeout** (TCP/TLS handshake) set on the `HttpClient`.
- **Request timeout** (entire request/response) set per-request, and includes connect.
- **Every callback** must call `Minecraft.getInstance().execute(Runnable)` before touching shared/render state.

**Skeleton:**

```java
// Source: CLAUDE.md §3, HttpClient best practices
public class TransitApiClient {
    private static final Logger LOGGER = LoggerFactory.getLogger(JollyalchemyTransitReport.MOD_ID);
    private static final int MAX_RESPONSE_SIZE = 5 * 1024 * 1024; // 5 MB (D-09)

    private final HttpClient httpClient;
    private final ExecutorService executor;

    public TransitApiClient() {
        // Build once, reuse
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))  // D-08: connect timeout
            .build();
        
        // Dedicated executor to prevent shared-pool contention
        this.executor = Executors.newFixedThreadPool(2);
    }

    // Fetch PNG bytes asynchronously
    public void fetchChart(String baseUrl, TransitConfig config, ChartCallback callback) {
        executor.submit(() -> {
            String url = substituteTokens(baseUrl);  // D-03: {date}/{time} → actual values
            
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofSeconds(45))  // D-08: request timeout (includes connect)
                .GET()
                .build();

            httpClient.sendAsync(request, new SizedBodySubscriber(MAX_RESPONSE_SIZE, callback))
                .whenComplete((response, throwable) -> {
                    if (throwable != null) {
                        // Error path (timeout, network failure, etc.)
                        Minecraft.getInstance().execute(() -> {
                            LOGGER.warn("Fetch failed: {}", throwable.getMessage());
                            callback.onFailure(throwable);
                        });
                    } else {
                        // Success path
                        Minecraft.getInstance().execute(() -> {
                            LOGGER.info("Fetch succeeded: {} bytes, status {}", response.body().length, response.statusCode());
                            callback.onSuccess(response.body());
                        });
                    }
                });
        });
    }

    private String substituteTokens(String template) {
        // D-03: substitute {date} and {time} with current timestamp
        // Format TBD — confirm against live API (D-03 open question)
        LocalDate today = LocalDate.now(ZoneId.systemDefault());
        LocalTime now = LocalTime.now(ZoneId.systemDefault());
        return template
            .replace("{date}", today.toString())  // ISO-8601: YYYY-MM-DD
            .replace("{time}", String.format("%02d:%02d", now.getHour(), now.getMinute()));
    }

    public interface ChartCallback {
        void onSuccess(byte[] pngBytes);
        void onFailure(Throwable error);
    }
}
```

**SizedBodySubscriber** (custom, enforces D-10):

```java
// Source: CLAUDE.md §3, size cap enforcement via BodySubscriber
public class SizedBodySubscriber implements HttpResponse.BodySubscriber<byte[]> {
    private final int maxSize;
    private final ChartCallback callback;
    private final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
    private volatile Flow.Subscription subscription;

    public SizedBodySubscriber(int maxSize, ChartCallback callback) {
        this.maxSize = maxSize;
        this.callback = callback;
    }

    @Override
    public CompletionStage<byte[]> getBody() {
        return CompletableFuture.completedStage(buffer.toByteArray());
    }

    @Override
    public void onSubscribe(Flow.Subscription subscription) {
        this.subscription = subscription;
        subscription.request(Long.MAX_VALUE);  // Request all, but onNext will abort if cap hit
    }

    @Override
    public void onNext(List<ByteBuffer> item) {
        for (ByteBuffer chunk : item) {
            if (buffer.size() + chunk.remaining() > maxSize) {
                // D-10: abort as failure on size overflow
                subscription.cancel();
                return;
            }
            byte[] bytes = new byte[chunk.remaining()];
            chunk.get(bytes);
            buffer.write(bytes, 0, bytes.length);
        }
    }

    @Override
    public void onError(Throwable throwable) {
        // Network error, timeout, etc. — handled by sendAsync whenComplete
    }

    @Override
    public void onComplete() {
        // All bytes received successfully
    }
}
```

### Anti-Patterns to Avoid

- **Building HttpClient per-request:** `HttpClient` construction has non-trivial overhead and defeats connection pooling. Build once at init, reuse across all fetches. ✗ Wrong: `new HttpClient().newBuilder()...send()` in each fetch call.

- **Using `Runnable::run` as the executor:** This makes `sendAsync()` block the calling thread, defeating the entire point of async. ✗ Wrong: `.executor(Runnable::run)`.

- **Touching TextureManager or render state from an async callback without `execute()`:** This violates the threading constraint. ✗ Wrong: calling `TextureManager.register()` directly in `whenComplete()`.

- **Skipping the callback's own responsibility to marshal to the main thread:** Even if `TransitApiClient` is "generic," every caller must `.execute()` before state mutation. This phase doesn't touch state, but Phase 6/7 will.

- **Hardcoding the full URL instead of reading it from config:** Makes the mod non-configurable and locks out D-01/D-02. ✗ Wrong: `URI.create("https://api.example.com/...").` Hard-code only the default in `TransitConfig`'s constructor.

- **Per-field salvage on config parse error (D-11 violation):** If one field is corrupted, don't try to keep the other. Reset all to defaults. ✗ Wrong: parse URL successfully, interval fails, keep URL + use default interval. Correct: one error means the whole file is untrusted.

- **Allowing response size to grow unbounded (D-09 violation):** Rely on custom `BodySubscriber`, not just checking `Content-Length` header. A response can omit `Content-Length` or lie about it. ✓ Correct: abort in `onNext()` if buffer size exceeds cap.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP client and async request lifecycle | A custom HTTP wrapper; retry logic; timeouts; connection pooling | `java.net.http.HttpClient` (JDK 17+, free, guaranteed present) | HTTP protocol compliance, timeout semantics, connection reuse, and edge cases (partial reads, slow servers) are complex. The JDK implementation is field-proven and requires zero external dependencies. |
| Config file I/O and JSON serialization | A manual JSON parser or file writer; custom validation | Gson + `java.nio.file` (already available; CLAUDE.md §5) | Gson is already bundled; JSON correctness is non-trivial; file atomicity and encoding require care. Let libraries solve these. |
| Thread-to-Minecraft-thread marshaling | A custom event queue or message bus | `Minecraft.getInstance().execute(Runnable)` (CLAUDE.md §3) | Minecraft's own `BlockableEventLoop` implementation is the correct entry point. Rolling your own risks deadlocks, frame drops, or missed events. |
| Background task execution pool | A one-off `new Thread()` per request; the default `ForkJoinPool.commonPool()` | `Executors.newFixedThreadPool(2)` or similar (explicit, bounded, dedicated) | Unbounded threads leak; shared pools cause contention; one-offs are unpredictable. A small fixed pool is explicit and predictable. |
| Retry logic or exponential backoff for failed requests | Manual `for` loops or timers inside the request handler | Leave to Phase 8 (scheduler) and Phase 9 (reliability) — this phase fails once and logs. | Retry strategy belongs with scheduled refresh, not here. This phase proves the HTTP path works; reliability comes later. |

## Common Pitfalls

### Pitfall 1: Blocking on HTTP During Config Load

**What goes wrong:** Calling `httpClient.send()` (blocking) instead of `sendAsync()` during `TransitConfig.load()` or from the main thread causes the game to freeze for up to 45 seconds waiting for the network.

**Why it happens:** Developers familiar with synchronous `HttpURLConnection` or OkHttp may not realize `java.net.http` requires explicit `sendAsync()` calls and executor setup to be truly non-blocking.

**How to avoid:** Never call `.send()` on the main thread or config-load path. Fetch initiation must always be async (via `sendAsync()`) with callbacks, and callbacks must `execute()` back to the main thread explicitly.

**Warning signs:** Game freezes when the client starts; "hang" complaints during testing; timeouts measured in seconds matching D-08/D-09 values; `Minecraft.getInstance().execute()` not visible in the callback chain.

### Pitfall 2: Reusing HttpClient Incorrectly or Recreating It Per-Request

**What goes wrong:** Building a new `HttpClient` in each fetch call causes connection-pooling to fail, significantly slows requests, and wastes memory; alternatively, using a thread-unsafe shared instance (bad if `sendAsync()` is called concurrently) causes race conditions.

**Why it happens:** `HttpClient` looks like a stateless utility that should be created on-demand, but it's actually a pooled resource that should be created once.

**How to avoid:** Create the `HttpClient` once in `TransitApiClient`'s constructor or as a static field, reuse it across all calls. Thread-safe for concurrent `sendAsync()` calls.

**Warning signs:** Slow requests, especially on repeated fetches; connection refused errors after many requests (port exhaustion); memory usage growing per-request; `HttpClient` constructor called multiple times in logs or profiling.

### Pitfall 3: Wrong Timeout Scope

**What goes wrong:** Setting only connect timeout (handshake) and not request timeout (full request/response) means a slow server can hang indefinitely; conversely, a request timeout that's too short (e.g., 5 seconds) will misclassify a slow-wake-up cold-start as a timeout.

**Why it happens:** The two timeouts serve different purposes and both must be set; confusing which applies where (connect timeout applies to TCP/TLS handshake only, request timeout applies to the full request/response including connect).

**How to avoid:** Set both explicitly: `HttpClient.Builder.connectTimeout()` for TCP/TLS, `HttpRequest.Builder.timeout()` for the full request. D-08 locks both values; don't deviate without justification from latency measurements on the real API.

**Warning signs:** Requests that should fail quickly instead hang; requests that should work at startup time out; logs show requests completing after the client quit.

### Pitfall 4: Size Cap Checked Post-Hoc Instead of During Streaming

**What goes wrong:** Checking `response.getHeaders().getFirstValue("Content-Length")` and aborting before reading doesn't prevent memory exhaustion if the header is omitted, lies, or the response is chunked; you must check during the read (`BodySubscriber.onNext()`) to truly enforce a hard cap.

**Why it happens:** Headers seem like a natural place to check, and simple checks look sufficient before considering the complexity of HTTP.

**How to avoid:** Use a custom `BodySubscriber` that checks byte count in `onNext()` and calls `subscription.cancel()` if the cap is exceeded. Don't rely on headers alone; they're advisory only.

**Warning signs:** Memory usage spikes during tests; `Content-Length` header missing on successful requests; truncated or partial responses being processed; no abort observed even when a 10 MB file is requested against a 5 MB cap.

### Pitfall 5: Callback Doesn't Marshal Back to Main Thread

**What goes wrong:** Touching `TextureManager`, `NativeImage`, or any Minecraft state directly from the `sendAsync()` callback (which runs on the executor's background thread) causes race conditions, rendering corruption, or crashes.

**Why it happens:** The async callback makes it tempting to handle the result immediately; developers may not realize that mutable Minecraft state is thread-hostile and requires main-thread access.

**How to avoid:** Every callback that touches anything beyond logging must call `Minecraft.getInstance().execute(Runnable)` with the state-mutation work inside the runnable. This phase doesn't touch state (just logs), but Phase 6/7 will.

**Warning signs:** Crash stack traces mentioning `TextureManager` or `NativeImage` inside a callback; "concurrent modification" or "thread not main" exceptions; rendering glitches that disappear when the fetch completes; non-deterministic crashes tied to network latency.

### Pitfall 6: Config Validation Too Strict or Too Lenient

**What goes wrong:** Validating the URL format too strictly (e.g., requiring a specific scheme, checking path structure) bakes brittle assumptions into the code; conversely, no validation at all means typos in the config don't fail until fetch time, confusing the user. D-13 chooses the latter: minimal type-only checks, let the API reject bad URLs.

**Why it happens:** Developers want to catch user mistakes early, which is reasonable, but determining what constitutes a "valid" URL gets complicated fast (RFC 3986, percent-encoding, punycode, etc.).

**How to avoid:** Stick to D-13: baseUrl must be a non-empty string, interval must be positive. No URI parsing, no range checks beyond ">0", no semantic validation. Wrong URLs are caught at fetch time and handled by the ordinary failure path (which already has to exist for network failures anyway).

**Warning signs:** Config validation logic becoming longer than the rest of the config code; users confused about why a typo wasn't caught until fetch time; validation rules drifting from their original justification.

## Code Examples

### One-shot verification fetch (D-05 scaffold)

Verified pattern from CLAUDE.md §3 and ROADMAP.md Phase 5 notes.

```java
// Source: CLAUDE.md §3, Minecraft.getInstance().execute() marshaling pattern
public class JollyalchemyTransitReportClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        TransitConfig config = TransitConfig.load();
        TransitApiClient httpClient = new TransitApiClient();
        
        // D-05: one-shot verification fetch on client init
        httpClient.fetchChart(config.baseUrl, config, new TransitApiClient.ChartCallback() {
            @Override
            public void onSuccess(byte[] pngBytes) {
                JollyalchemyTransitReport.LOGGER.info("Startup fetch succeeded: {} bytes", pngBytes.length);
                // This phase stops here. Phase 6/7 passes bytes to texture pipeline via this callback.
            }

            @Override
            public void onFailure(Throwable error) {
                JollyalchemyTransitReport.LOGGER.warn("Startup fetch failed: {}", error.getMessage());
                // Last good image stays on screen (once Phase 6/7 exist). This phase just logs.
            }
        });
    }
}
```

### Config file format (D-02 template)

Example `~/.minecraft/config/transit-config.json`:

```json
{
  "baseUrl": "https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false",
  "refreshIntervalSeconds": 60
}
```

After substitution (D-03), the actual request URL becomes:

```
GET https://human-design-4u01.onrender.com/api/viz/transit?date=2026-09-08&time=06%3A06&width=512&height=800&transparent=false
```

(Note: `{date}` → ISO-8601 date, `{time}` → HH:MM with colon URL-encoded to %3A — confirm exact format against live API.)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Blocking HTTP (HttpURLConnection, OkHttp sync) | Async HTTP (java.net.http.HttpClient.sendAsync) | Java 11+ standard library added HttpClient | Eliminated need for separate HTTP library; async support built-in; no blocking the render/main thread required. |
| Global `ForkJoinPool.commonPool()` for async work | Dedicated `ScheduledExecutorService` | Best practice circa 2010+, enforced by Minecraft requirements | Prevents thread-pool contention; makes thread count predictable; easier to reason about resource cleanup. |
| Config stored in properties files or hand-parsed JSON | Config stored as JSON, deserialized to POJO via Gson | Gson became standard in Minecraft bundles (early 2010s) | Simpler, less error-prone, matches Minecraft's own patterns. |
| Per-request retry logic and backoff | Retry logic deferred to scheduler/reliability phase | Separation of concerns: fetch proves basic connectivity; retry belongs with recurring scheduler. | Simpler this phase; reliability concerns isolated to later phases where they belong. |

**Deprecated/outdated:**
- `HttpURLConnection` (blocking, cumbersome API, limited features) — replaced by `java.net.http.HttpClient` (async, clean API, standard library since Java 11).
- OkHttp/Retrofit as a "must-have" for Minecraft — no longer justified since `HttpClient` is guaranteed present and handles common cases (retries, timeouts, pooling, HTTP/2).
- Storing config in NBT or block entity data — anti-pattern for anything user-editable; config belongs in files outside the world save (CLAUDE.md §5, PROJECT.md Out of Scope).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `java.net.http.HttpClient` is guaranteed present on Java 17+ and does not interact with Fabric's Knot classloader in unexpected ways | Standard Stack, CLAUDE.md §3 | High — if Fabric reloads or wraps the HTTP client unexpectedly, requests could hang or fail mysteriously. Mitigated: HttpClient is a JDK platform class (not loaded via Knot); no user reports of Fabric-HttpClient conflicts. |
| A2 | Gson is bundled with Minecraft and no separate dependency is needed | Standard Stack, CLAUDE.md §5 | Medium — if a future Minecraft version stops bundling Gson or conflicts with an added version, config parsing breaks. Mitigated: Gson has been bundled for years and unlikely to be removed; avoid adding a separate Gson version. |
| A3 | `FabricLoader.getInstance().getConfigDir()` always succeeds and returns a writable path | Standard Stack, CLAUDE.md §5 | Low — FabricLoader is part of the core; if it fails, Minecraft itself cannot load. Runtime I/O failures (disk full, permission denied) are application-level errors, not a bug in the pattern. |
| A4 | The live API (D-01: `https://human-design-4u01.onrender.com`) will remain at that URL and respond to requests in the format described in Phase 4 (D-04) | Locked Decision D-01 | High — if the API URL changes or the API goes down permanently, the default config becomes useless. Mitigated: User can edit config to point at a new URL (CFG-01); default can be updated in code. This phase doesn't depend on the API being reachable, only on the HTTP client working. |
| A5 | The exact date/time format the live API expects is `YYYY-MM-DD` and `HH:MM`, with colons URL-encoded in the URL | Locked Decision D-03 | High — if the API expects a different format (e.g., Unix timestamp, ISO-8601 with seconds, custom format), fetches will fail with 400 Bad Request or a mismatched image. Mitigated: Phase 4's D-04 noted the URL format from a real fetch; confirm exact format against live API before Phase 5 testing, or leave as a Phase 5 open question. |
| A6 | A response exceeding 5 MB is assumed to be a misbehaving endpoint, not a legitimate large PNG | Locked Decision D-09 | Low — realistic charts are under 1 MB, so 5 MB is a comfortable safety margin. If a future use case generates 10 MB charts, the constant can be updated. No per-tick impact if the cap is never hit. |
| A7 | The public changing-image endpoint (mentioned in ROADMAP.md Phase 5 notes) remains operational for testing | Architecture Patterns section | Medium — if the public endpoint goes away before Phase 8 is done, the one-shot verification fetch (D-05) won't visibly change the image. Mitigated: Phase 6 introduces local texture swapping (no network); visual verification of the fetch path itself is only needed for Phase 5/7. |
| A8 | Rendering will be handled entirely by a separate code path; Phase 5 code has no dependency on or knowledge of textures, rendering, or block entities | Architecture Patterns | High — if rendering ends up in this phase's code, the separation-of-concerns constraint is violated. Mitigated: Project.md and CLAUDE.md are explicit; the planner and reviewer must enforce this. |

**If this table is empty:** [NOT APPLICABLE — see table above]

## Open Questions

1. **Date/time format for API token substitution (D-03)**
   - What we know: Phase 4 D-04 captured a real fetch with `date=2026-09-08&time=06%3A06`, suggesting ISO-8601 date and HH:MM time with colon URL-encoded.
   - What's unclear: Whether the API expects exactly this format, whether seconds or milliseconds are required, whether timezone info is needed (UTC assumed?), and whether `HttpRequest`'s URI builder auto-encodes the substituted tokens or if manual encoding is required.
   - Recommendation: Before Phase 5 implementation, call the live API with a manual `curl` or browser request with the current timestamp in the suspected format and confirm the API accepts it and returns a 200 OK with image bytes. Document the exact format string used in `TransitApiClient.substituteTokens()`.

2. **Size-cap enforcement mechanism (D-10)**
   - What we know: Custom `BodySubscriber` is required to check during streaming, not post-hoc.
   - What's unclear: The exact pattern for `CompletableFuture` error handling if the cap is hit mid-response; whether `subscription.cancel()` propagates an error to `whenComplete()` or requires a separate error callback; how to distinguish "cap exceeded" from other network failures in logs.
   - Recommendation: Implement and test locally with a mock server or a manual oversized upload (e.g., `dd if=/dev/zero bs=1M count=10 | nc localhost 8888`). Document the behavior in code comments and assertions.

3. **Executor lifecycle (cleanup on mod shutdown)**
   - What we know: A fixed-thread executor needs cleanup to avoid thread leaks.
   - What's unclear: When to call `executor.shutdown()` or `executor.shutdownNow()` and whether Minecraft provides a lifecycle hook (e.g., a client-shutdown event) to attach cleanup to.
   - Recommendation: Check Fabric's `FabricClientEvents` or similar for a client-shutdown event, or use a `ShutdownHook` if necessary. Ensure in-flight requests are canceled on shutdown (Phase 9 concern, but cleanup belongs here).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Java Runtime (JDK) | Minecraft, Gradle, mod compilation | ✓ | 17+ (project uses 26) | — |
| `java.net.http.HttpClient` (JDK built-in) | API-01, API-02, API-03 | ✓ | Available in JDK 17+ | — |
| Gson (bundled with Minecraft) | CFG-01, CFG-02, CFG-03 | ✓ | Whatever Minecraft 1.20.1 bundles | Manual `HttpRequest.BodyHandlers.ofString()` + manual JSON parsing (not recommended) |
| `FabricLoader` (already in project) | CFG-01 config directory access | ✓ | 0.19.5 | — |
| Network connectivity to live API | API-01 verification (D-05 fetch) | ✓* | N/A | Manual verification via `curl` or browser if automated fetch fails; placeholder/bundled image displayed until network is available |

*Live API reachability: D-05's one-shot fetch is network-dependent, but Phase 5 code itself is not — config load and HTTP client construction complete successfully even if the network is down. Testing and verification require network access to the live API or a mock server (v2 scope).

**Missing dependencies with no fallback:** None — all required tools are bundled or standard library.

**Missing dependencies with fallback:** Network connectivity to the live API (D-01) — Phase 5 code works locally; verification requires either the live API or a mock server (Phase 9, v2 scope).

## Validation Architecture

Test framework: JUnit 5 (available via Loom's default test source set), no framework config changes needed this phase.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CFG-01 | Config file is written with defaults on first run | Unit | `test_config_file_created_on_missing()` — call `TransitConfig.load()` with mocked `FabricLoader`, assert file written, assert defaults present | ✗ Wave 0 |
| CFG-02 | Refresh interval is read from config | Unit | `test_refresh_interval_read_from_config()` — write a config with interval=30, load, assert `config.refreshIntervalSeconds == 30` | ✗ Wave 0 |
| CFG-03 | Malformed config yields defaults + log line | Unit | `test_malformed_config_recovers()` — write invalid JSON, load, assert defaults used, assert log message contains reason (D-14) | ✗ Wave 0 |
| CFG-05 | No secrets in defaults | Code review | `TransitConfig.java` — inspect default `baseUrl` field, assert no API keys, passwords, bearer tokens visible; assert no hardcoded credentials anywhere in `TransitApiClient` | N/A — code inspection only |
| API-01 | PNG bytes fetched via async HTTP GET | Integration | `test_fetch_succeeds_against_public_endpoint()` — call `TransitApiClient.fetchChart()` against the live API (D-01), verify callback receives non-empty byte array, verify bytes are valid PNG magic number (D-05 verification) | ✗ Wave 0 |
| API-02 | Timeouts set to D-08 values | Code review | `TransitApiClient.java` — inspect `HttpClient.Builder.connectTimeout()` and `HttpRequest.Builder.timeout()`, assert Duration values match or exceed 10s and 45s respectively | N/A — code inspection only |
| API-03 | No blocking on main thread; callback marshals to main thread | Code review | `TransitApiClient.java` — inspect `fetchChart()`, assert no `.send()` (blocking), assert all `.execute()` calls inside callbacks | N/A — code inspection only |
| API-04 | Adding second endpoint requires one new method | Code review | `TransitApiClient.java` — assume a second `fetchChart(String, callback)` overload or a method like `fetchTransit(url, callback)`, verify no HTTP layer restructuring needed | N/A — code inspection only |
| API-05 | Response body capped at 5 MB | Unit | `test_oversized_response_aborted()` — mock a response that returns 6 MB of data in chunks, verify `BodySubscriber.onNext()` aborts at 5 MB, verify `CompletableFuture` completes with error, callback receives failure | ✗ Wave 0 |

### Sampling Rate

- **Per task commit:** Unit tests only (`test_config_*`, `test_oversized_*`).
- **Per wave merge:** All unit + integration tests; if D-05's one-shot fetch is included, manual visual verification via `./gradlew runClient`.
- **Phase gate:** Unit tests green + code review of API-02/03/04/05 (no integration test against live API mandated, since D-06 verification uses manual editing instead).

### Wave 0 Gaps

- [ ] `tests/java/transitreport/config/TransitConfigTest.java` — covers CFG-01, CFG-02, CFG-03 (missing, write, malformed cases)
- [ ] `tests/java/transitreport/api/TransitApiClientTest.java` — covers API-01, API-05 (size-cap enforcement, HTTP success/failure paths)
- [ ] `src/test/java` directory structure — JUnit 5 discovery setup
- [ ] `build.gradle` test dependencies — JUnit 5 explicitly declared if not already implicit via Loom
- [ ] `conftest.java` or shared test fixtures — Gson instance, test config POJO, mocked `FabricLoader` for `getConfigDir()` tests

*(Note: This phase does not introduce REL-04 failure-mode testing because D-06 explicitly defers it to manual verification. Mock server (MOCK-01/02/03) is v2 scope.)*

## Security Domain

Security enforcement is enabled (config.json absent; default is enabled).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control | Implementation |
|---------------|---------|-----------------|-----------------|
| V2 Authentication | No | — | No user authentication or login required for this phase; the transit endpoint is public and timestamp-only (no personal data). |
| V3 Session Management | No | — | No session state. Each fetch is independent. |
| V4 Access Control | No | — | No permission model; the mod runs on a private server with trusted players only. |
| V5 Input Validation | Yes | Whitelist/type-check config values, reject oversized responses | D-13: baseUrl must be non-empty string, interval must be positive. D-09/D-10: response size capped at 5 MB. Do not validate URL format (D-13) — let the API reject malformed requests. |
| V6 Cryptography | No | — | No encryption, signing, or cryptographic operations this phase. HTTPS is used (live API URL is `https://`), handled by `java.net.http` stack. |
| V7 Error Handling and Logging | Yes | Log failures without exposing secrets; no per-tick spam (REL-03) | D-14: Log malformed config reason explicitly. Log HTTP status and byte count on success (success criterion 3). Avoid per-tick logging of repeated failures; throttle or use backoff (Phase 9 concern, but logging strategy starts here). Never log the full request URL if it ever contains secrets (not applicable to this public API, but establish the pattern). |
| V8 Data Protection | Yes | Do not persist sensitive data; no large blobs in NBT | CFG-05: No API keys or credentials in config defaults. Do not store PNG bytes in the world save (PROJECT.md Out of Scope, Phase 6 concern). |
| V9 Communications Security | Yes (partial) | Use HTTPS; validate certificates | Live API URL (D-01) is `https://`, so TLS is automatic. `java.net.http.HttpClient` uses the JDK's default X.509 certificate validation. No custom certificate pinning or bypass logic this phase. |
| V10 Malicious Code | No | — | No dynamic code loading, reflection, or bytecode manipulation this phase. |
| V13 API Security | Yes | Rate limit, input validation, enforce response size | D-05's one-shot fetch is not rate-limited (no scheduler yet). D-08/D-09: timeouts and size cap prevent resource exhaustion from a misbehaving API. Phase 8 scheduler will add rate limiting (one fetch per configured interval, no concurrent requests). |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation | Implementation Notes |
|---------|--------|---------------------|----------------------|
| Malformed JSON in config file | Tampering / Denial of Service | Parse-error recovery (CFG-03) | D-11/D-12: Malformed JSON resets all fields to defaults and overwrites the bad file. No crash or infinite error loop. |
| Oversized response exhausts memory | Denial of Service | Response size cap, streaming validation | D-09/D-10: Custom `BodySubscriber` checks byte count during streaming, aborts at 5 MB. Not post-hoc length check. |
| Unreachable API hangs the game | Denial of Service | Timeout enforcement | D-08: 10s connect, 45s request. `java.net.http.HttpClient` enforces these; no custom timeout logic. |
| Man-in-the-middle (unencrypted HTTP) | Spoofing / Information Disclosure | Use HTTPS | Live API URL (D-01) is `https://`. Always use HTTPS for production endpoints. Any user-configured URL in the config is the user's responsibility (CFG-01 allows any URL; validation is intentionally minimal per D-13). |
| Config file written with overpermissive file mode | Information Disclosure | File creation with secure permissions | `java.nio.file.Files.writeString()` uses default umask (typically 0022 on Unix, 0177 on Windows). No explicit `PosixFilePermissions` set; relies on OS defaults. For a private server with trusted users, this is acceptable. For a public release, set explicit permissions (v2 consideration). |
| Repeated fetch failures spam logs, filling disk | Denial of Service | Log throttling or backoff | REL-03 explicitly requires throttling. D-05's one-shot fetch doesn't spam, but Phase 8's scheduler must not re-request on every tick if the API is down. Implement retry backoff or a "last attempt time" check (Phase 8/9 concern, but establish throttling strategy now). |
| Attacker points config at phishing endpoint | Spoofing | No built-in defense; reliance on user awareness | D-01 defaults to the real API; users can edit the config to point elsewhere. No validation of URL format or domain ownership. On a private server, users are trusted. For a public release, consider a whitelist of allowed endpoints (v2 consideration). |

### No Additional Controls Required This Phase

Input sanitization (V5) is minimal by design (D-13). Output encoding (V7) applies to log messages only; use SLF4J which handles escaping. Database security (V8) does not apply. CORS (V13) is client-side only, not applicable to a Minecraft mod. Authentication/authorization (V2/V4) are out of scope.

## Sources

### Primary (HIGH confidence)

- **CLAUDE.md §3 (HTTP Client)** - `java.net.http.HttpClient` usage patterns, executor best practices, timeout scopes, callback marshaling via `Minecraft.getInstance().execute()`. Verified in this codebase and authoritative.
- **CLAUDE.md §5 (Config Library)** - Hand-rolled Gson + `FabricLoader.getConfigDir()` pattern, why alternatives (Cloth Config, owo-lib, midnightlib) are not used. Verified rationale for this project's scope.
- **CLAUDE.md §6 (Local Mock HTTP Server)** - `com.sun.net.httpserver.HttpServer` availability and rationale (JDK built-in, no second runtime). Noted for v2 scope.
- **REQUIREMENTS.md** - CFG-01, CFG-02, CFG-03, CFG-05, API-01 through API-05 requirements and success criteria.
- **ROADMAP.md Phase 5** - Phase goal, dependencies (Phase 1 only), success criteria, scope (no rendering, no texture), verification protocol (manual config editing, visual testing, one-shot fetch at startup).
- **CONTEXT.md (Phase 5 context session)** - Locked decisions D-01 through D-14, canonical references to PROJECT.md/CLAUDE.md, code context (integration points, existing source location patterns).

### Secondary (MEDIUM confidence)

- **Official Java 17+ documentation** - `java.net.http` API surface, `java.nio.file` patterns, `java.time` formatting. Not directly consulted in this session but widely available and stable.
- **Apache HttpClient vs. OkHttp comparison matrices** (web search, dated but informative) - Justifies why `java.net.http` is sufficient and alternatives are overkill for simple GET requests.

### Tertiary (training data / LOW confidence where not verified above)

- Gson best practices for config file handling - Assumed based on training knowledge; actual implementation will verify against the bundled Minecraft Gson version.
- `ScheduledExecutorService` cleanup patterns - Assumed based on common Java practice; actual lifecycle hook in Fabric will need to be confirmed.

---

**Research completed: 2026-09-08**  
**Valid until:** 2026-09-15 (stable domain; confirm D-03 date/time format and executor lifecycle during implementation)

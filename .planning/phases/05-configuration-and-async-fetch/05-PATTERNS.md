# Phase 5: Configuration and Async Fetch - Pattern Map

**Mapped:** 2026-09-08  
**Files analyzed:** 4 files (3 new, 1 modified)  
**Analogs found:** 4/4 (all files have existing patterns in codebase)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/main/java/transitreport/config/TransitConfig.java` | config/utility | file-I/O | `src/client/java/transitreport/client/TransitChartRenderer.java` | pattern-match (I/O, exception handling) |
| `src/main/java/transitreport/api/TransitApiClient.java` | service/utility | request-response (async) | `src/main/java/transitreport/JollyalchemyTransitReport.java` | role-match (logger setup, module pattern) |
| `src/main/java/transitreport/api/SizedBodySubscriber.java` | utility | streaming | `src/client/java/transitreport/client/TransitChartRenderer.java` | pattern-match (buffer handling) |
| `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` (modify) | event-handler/client-init | request-response | `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` (existing) | exact (same file) |

## Pattern Assignments

### `src/main/java/transitreport/config/TransitConfig.java` (utility, file-I/O)

**Analog:** `src/client/java/transitreport/client/TransitChartRenderer.java` (I/O, exception handling, logger patterns)

**Logger initialization pattern** (lines 1-25 of JollyalchemyTransitReport.java):
```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class TransitConfig {
    private static final String CONFIG_NAME = "transit-config.json";
    private static final Logger LOGGER = LoggerFactory.getLogger(JollyalchemyTransitReport.MOD_ID);
```

**File I/O + exception handling pattern** (lines 62-75 of TransitChartRenderer.java):
```java
try (InputStream stream = Minecraft.getInstance().getResourceManager().open(TEXTURE)) {
    try (NativeImage image = NativeImage.read(stream)) {
        height = BASE_WIDTH * ((float) image.getHeight() / (float) image.getWidth());
    }
} catch (IOException e) {
    JollyalchemyTransitReport.LOGGER.warn(
            "Failed to read bundled transit chart texture dimensions from {}; falling back to default aspect ratio",
            TEXTURE, e);
    height = BASE_WIDTH * DEFAULT_ASPECT;
}
```

**TransitConfig.java core pattern** (derived from RESEARCH.md Pattern 1, lines 189-250):
```java
package transitreport.config;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonSyntaxException;
import net.fabricmc.loader.api.FabricLoader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import transitreport.JollyalchemyTransitReport;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

public class TransitConfig {
    public String baseUrl = "https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false";
    public int refreshIntervalSeconds = 60;

    private static final String CONFIG_NAME = "transit-config.json";
    private static final Logger LOGGER = LoggerFactory.getLogger(JollyalchemyTransitReport.MOD_ID);

    // D-11/D-12: Load from disk, write defaults if missing/malformed
    public static TransitConfig load() {
        Path configDir = FabricLoader.getInstance().getConfigDir();
        Path configFile = configDir.resolve(CONFIG_NAME);

        if (Files.exists(configFile)) {
            try {
                String json = Files.readString(configFile);
                TransitConfig config = new Gson().fromJson(json, TransitConfig.class);
                
                // D-13: minimal type/shape validation only
                if (config.baseUrl != null && !config.baseUrl.isEmpty() 
                    && config.refreshIntervalSeconds > 0) {
                    return config;
                }
                
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

---

### `src/main/java/transitreport/api/TransitApiClient.java` (service, request-response async)

**Analog:** `src/main/java/transitreport/JollyalchemyTransitReport.java` (logger initialization, module constants, entry point pattern)

**Logger and MOD_ID pattern** (lines 10-16 of JollyalchemyTransitReport.java):
```java
public class TransitApiClient {
    private static final Logger LOGGER = LoggerFactory.getLogger(JollyalchemyTransitReport.MOD_ID);
    private static final int MAX_RESPONSE_SIZE = 5 * 1024 * 1024; // 5 MB (D-09)
```

**HttpClient and executor pattern** (from RESEARCH.md Pattern 2, lines 284-292):
```java
public class TransitApiClient {
    private final HttpClient httpClient;
    private final ExecutorService executor;

    public TransitApiClient() {
        // D-08: Build once, reuse
        this.httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();
        
        // Dedicated executor to prevent shared-pool contention
        this.executor = Executors.newFixedThreadPool(2);
    }
```

**Fetch method with callback marshaling pattern** (from RESEARCH.md Pattern 2, lines 295-322):
```java
    public void fetchChart(String baseUrl, TransitConfig config, ChartCallback callback) {
        executor.submit(() -> {
            String url = substituteTokens(baseUrl);  // D-03: {date}/{time} substitution
            
            HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofSeconds(45))  // D-08: request timeout
                .GET()
                .build();

            httpClient.sendAsync(request, new SizedBodySubscriber(MAX_RESPONSE_SIZE, callback))
                .whenComplete((response, throwable) -> {
                    if (throwable != null) {
                        // Error path (timeout, network failure)
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
```

**Import block** (standard for async HTTP in Fabric):
```java
import net.fabricmc.api.Environment;
import net.fabricmc.api.EnvType;
import net.minecraft.client.Minecraft;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import transitreport.JollyalchemyTransitReport;
import transitreport.config.TransitConfig;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
```

---

### `src/main/java/transitreport/api/SizedBodySubscriber.java` (utility, streaming)

**Analog:** `src/client/java/transitreport/client/TransitChartRenderer.java` (buffer/stream handling, exception management)

**Buffer management and exception handling pattern** (lines 62-75 of TransitChartRenderer.java, adapted for streaming):
```java
package transitreport.api;

import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.Flow;

public class SizedBodySubscriber implements HttpResponse.BodySubscriber<byte[]> {
    private final int maxSize;
    private final TransitApiClient.ChartCallback callback;
    private final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
    private volatile Flow.Subscription subscription;

    public SizedBodySubscriber(int maxSize, TransitApiClient.ChartCallback callback) {
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
        subscription.request(Long.MAX_VALUE);
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
        // Handled by sendAsync whenComplete
    }

    @Override
    public void onComplete() {
        // All bytes received successfully
    }
}
```

---

### `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` (modify, event-handler)

**Existing file** (current state, lines 1-15):
```java
package transitreport.client;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.rendering.v1.BlockEntityRendererRegistry;

import transitreport.TransitReportBlocks;

public class JollyalchemyTransitReportClient implements ClientModInitializer {
    @Override
    public void onInitializeClient() {
        BlockEntityRendererRegistry.register(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY,
                context -> new TransitChartRenderer());
    }
}
```

**D-05 one-shot verification fetch pattern** (from RESEARCH.md code example, lines 489-510):
```java
@Override
public void onInitializeClient() {
    // Existing renderer registration
    BlockEntityRendererRegistry.register(TransitReportBlocks.TRANSIT_CHART_BLOCK_ENTITY,
            context -> new TransitChartRenderer());

    // D-05: one-shot verification fetch on client init
    TransitConfig config = TransitConfig.load();
    TransitApiClient httpClient = new TransitApiClient();
    
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
```

**Import additions for modified file**:
```java
import net.minecraft.client.Minecraft;
import transitreport.JollyalchemyTransitReport;
import transitreport.api.TransitApiClient;
import transitreport.config.TransitConfig;
```

---

## Shared Patterns

### Logger Setup and Naming Convention
**Source:** `src/main/java/transitreport/JollyalchemyTransitReport.java` (lines 10-16)  
**Apply to:** All config, service, and utility classes

```java
private static final Logger LOGGER = LoggerFactory.getLogger(JollyalchemyTransitReport.MOD_ID);
```

**Why:** Consistent logging across all mod code; ensures all log messages are prefixed with the mod ID for easy identification in logs.

### Exception Handling with Graceful Fallback
**Source:** `src/client/java/transitreport/client/TransitChartRenderer.java` (lines 62-75)  
**Apply to:** File I/O, config loading, and any operation with a reasonable default

```java
try (InputStream stream = ...) {
    try (NativeImage image = ...) {
        // operation
    }
} catch (IOException e) {
    LOGGER.warn("Failed to read ...; falling back to default ...", e);
    // use default/fallback
}
```

**Why:** Follows existing project pattern; provides diagnostic logging without crashing; recovers to sensible defaults.

### Package Organization for New Modules
**Source:** Existing package structure (`transitreport.client`, `transitreport.block`, `transitreport.block.entity`)  
**Apply to:** New config and API utilities

**Pattern:**
- Config utilities → `transitreport.config` (can be `src/main` for multiplayer forward-compat)
- API/HTTP utilities → `transitreport.api` (can be `src/main` or `src/client` per planner decision)

**Why:** Mirrors existing organizational pattern; keeps concerns separated and easily identifiable.

---

## No Analog Found

None. All file patterns have close existing analogs or established patterns in the codebase.

| File | Role | Data Flow | Reason | Mitigation |
|------|------|-----------|--------|-----------|
| — | — | — | — | — |

---

## Metadata

**Analog search scope:** `src/main/java/**/*.java`, `src/client/java/**/*.java`  
**Files scanned:** 8 source files  
**Pattern extraction date:** 2026-09-08  
**Tracked-source verification:** All analogs verified via `git ls-files` (not gitignored mirrors)

### Verification Checklist

- [x] `src/main/java/transitreport/JollyalchemyTransitReport.java` — logger setup (lines 10-16)
- [x] `src/client/java/transitreport/client/TransitChartRenderer.java` — I/O, exception handling (lines 62-75)
- [x] `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` — event-handler entry point (lines 1-15)
- [x] `src/main/java/transitreport/TransitReportBlocks.java` — registration pattern (reference only)

All extracted patterns come from committed, git-tracked source files (not runtime/build-generated code).

---

## Key Decisions for Implementation

### D-05 One-Shot Verification Fetch
The pattern in `JollyalchemyTransitReportClient.onInitializeClient()` shows the temporary scaffolding location. This is reversible (Phase 8 may delete or leave inert once real scheduler exists). The callback structure allows Phase 6/7 to extend the success path without restructuring the HTTP layer.

### Logger Usage Consistency
All three new classes (`TransitConfig`, `TransitApiClient`, `SizedBodySubscriber`) follow the same logger initialization pattern as the existing codebase. Error messages include the MOD_ID automatically via logger factory, reducing boilerplate.

### No Blocking I/O on Main Thread
The pattern in `TransitApiClient.fetchChart()` explicitly uses:
- `executor.submit()` to move HTTP work off the calling thread
- `Minecraft.getInstance().execute()` to marshal results back to the main thread (required before Phase 6/7 touch render state)

This satisfies the PROJECT.md threading constraint from the ground up.

---

**Pattern mapping complete. Ready for planning phase.**

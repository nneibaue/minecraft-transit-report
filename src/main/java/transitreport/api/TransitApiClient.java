package transitreport.api;

import transitreport.JollyalchemyTransitReport;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Async HTTP GET client for fetching chart PNG bytes from a configured URL template
 * (API-01..05). No {@code net.minecraft.client.*} import of any kind -- the main-thread
 * hand-back (marshaling the callback result via the client's execute hop) is the caller's
 * responsibility (see {@code JollyalchemyTransitReportClient}), not this class's.
 *
 * <p>Builds exactly one {@link HttpClient} in the constructor and reuses it for every fetch
 * (CLAUDE.md SS3 -- never construct a new {@code HttpClient} per request). Uses a dedicated
 * 2-thread executor so {@code sendAsync} never blocks the caller (no synchronous fallback).
 */
public class TransitApiClient {

    private static final long MAX_RESPONSE_SIZE_BYTES = 5L * 1024 * 1024;
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(10);
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(45);
    private static final DateTimeFormatter TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm");

    private final HttpClient httpClient;
    private final ExecutorService executor;

    public TransitApiClient() {
        this.executor = Executors.newFixedThreadPool(2);
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(CONNECT_TIMEOUT)
                .executor(executor)
                .build();
    }

    /**
     * Fetches PNG bytes from {@code urlTemplate} (after {@code {date}}/{@code {time}} token
     * substitution) via a single async GET, streamed through a size-capped
     * {@link SizedBodySubscriber}. Exactly one public fetch method exists (API-04) -- a second
     * chart endpoint would reuse this same {@link #httpClient}/{@link #executor} via an added
     * method, not a restructure.
     */
    public void fetchChart(String urlTemplate, ChartCallback callback) {
        String url;
        HttpRequest request;
        try {
            url = substituteTokens(urlTemplate);
            request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(REQUEST_TIMEOUT)
                    .GET()
                    .build();
        } catch (IllegalArgumentException e) {
            // An unreachable-format URL is caught here and routed to the ordinary failure
            // path rather than throwing out of fetchChart synchronously.
            callback.onFailure(e);
            return;
        }

        httpClient.sendAsync(request, responseInfo -> new SizedBodySubscriber(MAX_RESPONSE_SIZE_BYTES))
                .whenComplete((response, throwable) -> {
                    if (throwable != null) {
                        JollyalchemyTransitReport.LOGGER.warn("Chart fetch failed: {}", throwable.getMessage());
                        callback.onFailure(throwable);
                    } else if (response.statusCode() != 200) {
                        JollyalchemyTransitReport.LOGGER.warn("Chart fetch failed: HTTP status {}", response.statusCode());
                        callback.onFailure(new java.io.IOException("Unexpected HTTP status " + response.statusCode()));
                    } else {
                        JollyalchemyTransitReport.LOGGER.info("Chart fetch succeeded: status {}, {} bytes",
                                response.statusCode(), response.body().length);
                        callback.onSuccess(response.body());
                    }
                });
    }

    /**
     * Shuts down this client's dedicated executor. Safe to call once any in-flight
     * {@link #fetchChart(String, ChartCallback)} calls have completed; a short-lived
     * caller (e.g. a one-shot diagnostic fetch) should call this after its callback fires
     * so the two dedicated worker threads don't outlive the fetch.
     */
    public void shutdown() {
        executor.shutdown();
    }

    private String substituteTokens(String template) {
        String date = LocalDate.now().toString();
        String time = LocalTime.now().format(TIME_FORMAT);
        return template.replace("{date}", date).replace("{time}", time);
    }

    /** Callback interface for {@link #fetchChart(String, ChartCallback)} results. */
    public interface ChartCallback {
        void onSuccess(byte[] pngBytes);

        void onFailure(Throwable error);
    }
}

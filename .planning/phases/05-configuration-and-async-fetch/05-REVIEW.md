---
phase: 05-configuration-and-async-fetch
reviewed: 2026-09-08T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - src/main/java/transitreport/config/TransitConfig.java
  - src/main/java/transitreport/api/TransitApiClient.java
  - src/main/java/transitreport/api/SizedBodySubscriber.java
  - src/test/java/transitreport/config/TransitConfigTest.java
  - src/test/java/transitreport/api/SizedBodySubscriberTest.java
  - build.gradle
  - src/client/java/transitreport/client/JollyalchemyTransitReportClient.java
  - docs/DEV.md
  - .gitignore
findings:
  critical: 1
  warning: 3
  info: 1
  total: 5
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-09-08
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the Phase 5 config-load and async-fetch pipeline (`TransitConfig`, `TransitApiClient`,
`SizedBodySubscriber`), their unit tests, and the client entrypoint that wires them together.
The config load/validate/rewrite path (`TransitConfig`) is solid: every failure mode (missing
file, malformed JSON, invalid field) resets to defaults and is covered by a corresponding test,
matching D-11/D-12/D-13 as documented.

The HTTP fetch path has one real correctness gap: `TransitApiClient.fetchChart` never inspects
`HttpResponse.statusCode()` — any HTTP response (200, 404, 500, a redirect target, an HTML error
page) is routed to `callback.onSuccess(...)` as long as the TCP/TLS exchange itself didn't throw.
This directly undermines the project's stated core value ("never freezes... and keeps showing the
last good chart when the API misbehaves") because a misbehaving-but-reachable API (5xx, maintenance
page, auth wall) is currently indistinguishable from a real chart fetch at this layer. This was not
caught by any test or by the phase's own security/validation registers because no automated
coverage exists for `TransitApiClient` at all (a deliberate, documented deferral per D-06/05-VALIDATION.md,
not an oversight) — but the underlying logic gap is real regardless of test scope and is in-file,
provable from the code as written.

Two further robustness gaps were found in the streaming size-cap logic and executor lifecycle,
plus one low-severity timing nit in date/time token substitution. `.gitignore`, `build.gradle`,
and `docs/DEV.md` were reviewed and are consistent with the rest of the codebase; no issues found
in those files.

## Critical Issues

### CR-01: HTTP status code is never checked — non-2xx responses are treated as fetch success

**File:** `src/main/java/transitreport/api/TransitApiClient.java:67-77`
**Issue:** `fetchChart`'s `.whenComplete` callback branches only on `throwable != null` (a
transport-level failure — connect error, timeout, size-cap abort). It never inspects
`response.statusCode()`. A reachable server returning `404`, `500`, `503`, a login/maintenance
HTML page, or a redirect target is passed straight to `callback.onSuccess(response.body())` and
logged as `"Chart fetch succeeded"`. This is exactly the "API misbehaves" scenario the project's
core value proposition is built around, and today it is misclassified as success rather than
routed to the last-known-good fallback path that `onFailure` exists to trigger. Downstream (later
phases) this means an error page's bytes could be handed to the texture pipeline as if they were a
valid chart PNG, instead of being rejected here where the status code is already available for
free.
**Fix:**
```java
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
```

## Warnings

### WR-01: `SizedBodySubscriber.onNext` does not short-circuit once the cap has already been exceeded

**File:** `src/main/java/transitreport/api/SizedBodySubscriber.java:46-59`
**Issue:** When a chunk pushes the running total past `maxSize`, the method sets `sizeExceeded`,
completes the future exceptionally, and calls `subscription.cancel()` — but `cancel()` on a
`Flow.Subscription` is not guaranteed to take effect before the publisher delivers items already
in flight (per the Reactive Streams spec, cancellation is asynchronous/best-effort). Because
`onNext` has no `if (sizeExceeded) { return; }` guard at its top, any further `onNext` call that
arrives before the JDK's internal publisher honors the cancellation will re-evaluate
`buffer.size() + buf.remaining() > maxSize` against the *unchanged* `buffer.size()` from before
the violating chunk, and — if that next chunk happens to be small enough not to trip the check on
its own — will silently continue appending bytes to `buffer` even though the subscriber has
already reported failure. This defeats part of the purpose of an onNext-time (not post-hoc) cap:
the buffer can keep growing after the cap was already flagged as exceeded, bounded only by how
quickly the upstream honors `cancel()`.
**Fix:**
```java
@Override
public void onNext(List<ByteBuffer> item) {
    if (sizeExceeded) {
        return;
    }
    for (ByteBuffer buf : item) {
        if (buffer.size() + buf.remaining() > maxSize) {
            sizeExceeded = true;
            result.completeExceptionally(
                    new IOException("Response exceeded max size of " + maxSize + " bytes"));
            subscription.cancel();
            return;
        }
        byte[] bytes = new byte[buf.remaining()];
        buf.get(bytes);
        buffer.writeBytes(bytes);
    }
}
```

### WR-02: `TransitApiClient`'s executor is never shut down and uses non-daemon threads

**File:** `src/main/java/transitreport/api/TransitApiClient.java:35-41`; leaked instance at
`src/client/java/transitreport/client/JollyalchemyTransitReportClient.java:26`
**Issue:** `Executors.newFixedThreadPool(2)` creates two ordinary (non-daemon) worker threads with
no corresponding `shutdown()`/`close()` path anywhere in `TransitApiClient`. In
`JollyalchemyTransitReportClient.onInitializeClient()`, a `TransitApiClient` is created as a local
variable purely for one diagnostic fetch and then never referenced again — its two background
threads remain alive, idle, for the rest of the client session (until JVM exit), since nothing
ever calls `executor.shutdown()`. This is a minor resource leak today (2 threads) but the class has
no lifecycle contract at all, so every future caller (e.g., the Phase 8 recurring scheduler) either
has to remember to build exactly one long-lived instance and never call `shutdown()` either, or
inherits the same leak pattern per instance. Worth adding a `close()`/`shutdown()` method now,
before more call sites accumulate.
**Fix:** Add an explicit shutdown method and call it from any short-lived usage:
```java
public void shutdown() {
    executor.shutdown();
}
```

### WR-03: No `SizedBodySubscriber.onNext` coverage for the "already cancelled but another chunk arrives" case

**File:** `src/test/java/transitreport/api/SizedBodySubscriberTest.java`
**Issue:** Related to WR-01 — there is no test that calls `onNext` a second time after the first
call already exceeded the cap, so the regression in WR-01 (buffer growth after `sizeExceeded`)
would not be caught by the current suite even after a fix regresses.
**Fix:** Add a test that calls `onNext` twice — once over the limit, once again afterward with a
small chunk — and asserts `subscriber.getBody()` still reflects only the first failure and the
buffer is not further mutated (e.g. by asserting `cancelCount()` stays at 1 and the completed
exception is unchanged).

## Info

### IN-01: `substituteTokens` reads date and time from two separate, non-atomic clock calls

**File:** `src/main/java/transitreport/api/TransitApiClient.java:80-84`
**Issue:** `LocalDate.now()` and `LocalTime.now()` are two independent calls to the system clock.
In the sub-millisecond window where midnight rolls over between the two calls, the request would
be built with the previous day's date paired with `00:00` (or similar) time, producing a
one-refresh-cycle date/time mismatch against the transit API. Extremely low probability and
self-corrects on the next ~60s refresh, but easy to make atomic.
**Fix:**
```java
private String substituteTokens(String template) {
    java.time.LocalDateTime now = java.time.LocalDateTime.now();
    return template.replace("{date}", now.toLocalDate().toString())
                   .replace("{time}", now.format(TIME_FORMAT));
}
```

---

_Reviewed: 2026-09-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

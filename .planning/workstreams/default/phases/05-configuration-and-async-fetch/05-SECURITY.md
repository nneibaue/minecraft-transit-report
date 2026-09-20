---
phase: "05"
slug: "configuration-and-async-fetch"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-08"
---

# Phase 05 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|----------------|
| Player-editable config file → `TransitConfig` | `transit-config.json` sits on local disk under `FabricLoader`'s config dir; anyone with local filesystem write access can edit it, and its parsed content directly drives an outbound HTTP request | Config JSON (baseUrl string, refresh interval int) |
| `TransitApiClient` → external Human Design API (network) | Outbound HTTPS GET to a URL sourced from local config; the response bytes returned to the mod are untrusted network input until validated | PNG bytes (untrusted until size-capped and handed to the caller) |
| Async executor thread → Minecraft main/render thread | `TransitApiClient`'s callback result crosses a thread boundary; anything touching game/render state must marshal via `Minecraft.getInstance().execute(...)` before use | Fetch result (bytes or exception), consumed only for logging this phase |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-05-01 | Tampering | `TransitConfig.load(Path)` parsing `transit-config.json` | medium | mitigate | Any parse or validation failure resets ALL fields to defaults and overwrites the file with fresh defaults on disk (D-11/D-12); game still initializes rather than crashing (CFG-03). Verified: `TransitConfigTest` covers missing/malformed/invalid-field cases; `writeDefaults(Path)` is the single reset path for both. | closed |
| T-05-02 | Denial of Service | `TransitApiClient.fetchChart` response handling | high | mitigate | `HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10))` plus `HttpRequest.newBuilder().timeout(Duration.ofSeconds(45))` bound every fetch (D-08); `sendAsync` + a dedicated 2-thread executor keep the wait off the main/render thread. Verified: both `Duration.ofSeconds(10)`/`(45)` literals present in `TransitApiClient.java`; live `runClient` session observed a clean 45s timeout on a cold-started endpoint with no client hang/crash. | closed |
| T-05-03 | Denial of Service | `SizedBodySubscriber.onNext` streaming byte accumulation | medium | mitigate | A 5MB cap is enforced during streaming (not a post-hoc `Content-Length` check); `subscription.cancel()` + `CompletableFuture.completeExceptionally()` fire on the first chunk that would cross the cap (D-09/D-10). Verified: `SizedBodySubscriberTest` covers within-limit and over-limit cases; `sizeExceeded`/`cancel()`/`completeExceptionally` all present in `SizedBodySubscriber.java`. | closed |
| T-05-04 | Information Disclosure | `TransitConfig` default `baseUrl` / `TransitApiClient` request construction | low | mitigate | The shipped default URL is the public Human Design endpoint with no auth header, API key, bearer token, or credential anywhere in `TransitConfig` or `TransitApiClient` (D-01/CFG-05). Verified: grep for `Authorization`/`apiKey`/`api_key`/`Bearer`/`token` across both files returns no matches; confirmed by direct code inspection. | closed |
| T-05-05 | Spoofing (SSRF-shaped) | Player-editable `baseUrl` pointed at an internal/local network address | low | accept | D-13 deliberately performs no URI-well-formedness or host-allowlist validation; editing the config file already requires local filesystem write access (an attacker with that access has a broader compromise already), and PROJECT.md scopes this mod to a private server for the author and known friends, not a public-facing service. | closed (accepted risk) |
| T-05-06 | Repudiation / Information Disclosure | Fetch success/failure logging | low | mitigate | Only the HTTP status code and byte count are logged on success, only the exception message on failure — never the full response body or a full query string that could carry a future secret. This phase's fetch is one-shot (D-05), not recurring, so it cannot produce per-tick log spam. Verified: `TransitApiClient.java` logs exactly `"Chart fetch succeeded: status {}, {} bytes"` and `"Chart fetch failed: {}"` with `throwable.getMessage()` — no body, no full request URL. | closed |

*Status: open · closed · open — below {block_on} threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|--------------|------|
| R-05-01 | T-05-05 | Player-editable `baseUrl` with no host-allowlist validation is an SSRF-shaped risk in general, but this mod ships to a private server for the author and known friends (PROJECT.md scope); editing the config already requires local filesystem write access, at which point a broader compromise already exists. D-13 (locked in 05-CONTEXT.md) deliberately excludes URI-reachability validation beyond type/shape checks. | 05-CONTEXT.md (D-13), reaffirmed in 05-01-PLAN.md's threat model | 2026-09-08 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|----------------|--------|------|--------|
| 2026-09-08 | 6 | 6 | 0 | gsd-secure-phase (L1, register authored at plan time — verified directly against implementation, no auditor subagent needed per short-circuit rule) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-08

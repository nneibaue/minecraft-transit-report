# Phase 5: Configuration and Async Fetch - Context

**Gathered:** 2026-09-08
**Status:** Ready for planning

<domain>
## Phase Boundary

The mod reads a base URL and refresh interval from a Gson-backed config file (defaults written on first run, malformed file recovers to defaults), and `TransitApiClient` performs an asynchronous HTTP GET for PNG bytes from that URL — off the main/render thread, with finite connect/request timeouts and a capped response size. This is the independent "data" track: it depends only on Phase 1, has zero dependency on the block/renderer/texture work, and produces no visible in-world change. It logs an HTTP status and a byte count and stops.

Covers CFG-01, CFG-02, CFG-03, CFG-05, API-01, API-02, API-03, API-04, API-05.

**Explicitly not in this phase:** no `TextureManager`, no `NativeImage`, no GL calls of any kind, no scheduler/recurring timer (Phase 8), no block/renderer wiring (Phase 7), no manual-refresh command (Phase 10's CFG-04). The only thing that fires a fetch this phase is a temporary one-shot call at client startup, purely to prove the pipeline works — see D-04.

</domain>

<decisions>
## Implementation Decisions

### Default Config Values

- **D-01:** The shipped default base URL is the **real Human Design API**: `https://human-design-4u01.onrender.com` (discovered and confirmed live in Phase 4, recorded there as D-04). Not a placeholder, not the public changing-image dummy endpoint mentioned in ROADMAP.md's Phase 5 notes — the real API is used from the start.

- **D-02:** Config's `baseUrl`-equivalent field stores the **full URL template, including path and query parameters** — not just scheme+host. Concretely, something like:
  `https://human-design-4u01.onrender.com/api/viz/transit?date={date}&time={time}&width=512&height=800&transparent=false`

  This differs from the initially-recommended "scheme+host only" option — the user explicitly chose to keep the whole request shape in config rather than hardcoding path/query construction in `TransitApiClient`.

  — **Reversibility:** costly — API-04 ("adding a second endpoint is one added method, not a restructure") and CFG-05 ("no secrets in config defaults, confirmable by inspection") both need to be satisfied against this shape. The planner/researcher should think through what "add a second endpoint" looks like with a full-template-in-config design (e.g., a second named template field, or a method parameter selecting which stored template to use) since this is a more coupled design than a fixed-path client.

- **D-03:** `date` and `time` are **placeholder tokens inside the stored template** — `{date}` and `{time}` literally appear in the config value, and `TransitApiClient` does a plain string substitution with the current timestamp immediately before each request. `width`, `height`, and `transparent` are just ordinary literal values baked into the template string (editable by hand, but not runtime-computed by the client).

  **Open for research/planning:** the exact `date`/`time` format the live API expects (the Phase 4 D-04 URL used `date=2026-09-08&time=06%3A06` — note the URL-encoded colon in time) needs confirming, plus whether Java's `HttpRequest`/`URI` builder requires manual encoding of the substituted values or handles it automatically.

- **D-04:** Confirmed default refresh interval: **60 seconds**, matching REQUIREMENTS.md's stated default exactly. (Note: no scheduler exists yet this phase — REF-01's actual recurring-fetch behavior is Phase 8. This phase just needs to read this value from config into a typed field.)

### This-Phase Verification Trigger

- **D-05:** Since no scheduler (Phase 8) or block wiring (Phase 7) exists yet, this phase fires exactly **one fetch from `onInitializeClient()`** at client startup, logs the result, and stops. No debug command, no keybind — no throwaway UI/command scaffolding. This is temporary verification code, not a feature; it may be deleted or left inert once Phase 8's real scheduler exists (planner's call which).

  — **Reversibility:** reversible — this is test scaffolding, not load-bearing behavior any later phase depends on.

- **D-06:** Failure-path verification (success criterion 4: unreachable host, oversized response) is done **manually by temporarily editing the config file's base URL**, relaunching, observing the timeout/rejection in logs, then editing it back. No mock server (already scoped out of v1 per REQUIREMENTS.md's Out of Scope list), no unit test harness against a fake server for this phase. This is a one-time manual spot check performed during phase verification, not a repeatable automated test.

- **D-07:** Responsiveness (success criterion 3: no frame hitch while a fetch is in flight) is verified **visually** — same established protocol as Phases 1-4: Claude launches `runClient` in the background and tails the log, the user walks/looks around in the dev world during the startup fetch and confirms no stutter. No timestamp-based code-level proof added on top.

### Timeouts & Response Size Cap

- **D-08:** Connect timeout **10 seconds**, request timeout **45 seconds**. Deliberately generous because the live API (D-01) runs on Render's free tier, which is known to cold-start in 30-50 seconds after idling — a tighter timeout would misclassify the first fetch after idle as "the API is unreachable" when it's actually just slow to wake up.

  — **Reversibility:** reversible — both are simple `Duration` constants (`HttpClient.Builder.connectTimeout(...)`, `HttpRequest.Builder.timeout(...)` per CLAUDE.md §3), trivially tunable later once real-world latency is observed.

- **D-09:** Maximum response body size: **5 MB**. Comfortably above any realistic chart PNG at 512×800 (the bundled Phase 4 sample was well under 1 MB), while still bounding memory against a badly-misbehaving or wrong endpoint.

- **D-10:** When a response exceeds the size cap, `TransitApiClient` **aborts the fetch and treats it as an ordinary failure** — same handling path as any other REL-01/REL-04 failure mode: last good image stays on screen (once Phase 6/7 exist to have one), one log line, no crash. This is explicitly a defensive backstop the user does not expect to trigger in practice, since the user controls the API's own output — it is not being built to handle a case that's expected to occur regularly. Truncate-and-attempt-decode was explicitly rejected: a truncated PNG essentially never decodes successfully, so it buys nothing over aborting cleanly.

  **Note for planner/researcher:** `HttpClient`'s standard `BodyHandlers` don't enforce a size cap on their own; checking `Content-Length` alone isn't sufficient (a response can omit it or lie), so genuine enforcement likely needs a custom `BodySubscriber` that aborts once the byte count crosses the cap during streaming, not just a post-hoc length check.

### Malformed-Config Recovery Detail

- **D-11:** On any parse or validation error, **all fields reset to defaults** — not per-field salvage. One bad value in the file means the whole file is untrusted this load; every field (base URL and interval both) falls back to its default. Deliberately the simpler of the two options, consistent with PROJECT.md's "avoid premature abstraction" constraint for what is currently a two-field config.

- **D-12:** On a malformed-config fallback, the mod **overwrites the bad file on disk with a fresh default file** — the same code path handles "file missing" (CFG-01's first-run case) and "file malformed" (CFG-03's recovery case) identically: write defaults, use defaults. The next launch starts from a clean file rather than repeating the same fallback indefinitely.

- **D-13:** Validation is **minimal — type/shape checks only**, not semantic/format validation: the base-URL field must be a non-empty string, the interval field must be a positive number. No URI-well-formedness check on the URL, no min/max range clamp on the interval beyond ">0". A syntactically-fine-but-wrong URL (e.g. a typo'd domain) is not caught at config-load time — it simply fails at fetch time and is handled by the ordinary REL-04 failure path, which already has to exist anyway. This avoids inventing and justifying arbitrary bounds (e.g. "why is the minimum interval 5 seconds and not 3?").

- **D-14 (Claude's discretion):** The one required log line on a malformed-config fallback should **include the specific reason** (e.g. "Config file was malformed (JSON parse error / non-positive refreshIntervalSeconds); using defaults and rewriting config.json") rather than a generic "config invalid" message. Costs nothing extra to implement and saves a debugging step later. The user did not explicitly confirm this exact wording — flagged as Claude's discretion, not a locked decision, since the specific question about log-message detail was not completed in discussion.

### Claude's Discretion

- The D-14 log-message wording above — the question was raised but not answered; treat "include the reason" as the default unless planning finds a concrete reason against it.
- Exact Gson field names, Java types (e.g. whether interval is stored as `int` seconds or something richer), and the config POJO's class name/location are unconstrained implementation details — follow CLAUDE.md §5's "hand-rolled Gson + `FabricLoader.getConfigDir()`" guidance directly.
- Whether the one-shot startup verification fetch (D-05) is deleted or merely left inert once Phase 8's scheduler exists is left to whichever agent implements Phase 8 to decide, not locked here.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope and requirements
- `.planning/PROJECT.md` — Constraints (Threading: no blocking I/O on main/render thread; Separation of concerns: renderer never does HTTP, HTTP client never touches render state; Dependencies: prefer JDK/Fabric-provided mechanisms). Technology Stack section §3 (HTTP Client) and §5 (Config Library) lock the concrete technical choices for this phase — `java.net.http.HttpClient`, hand-rolled Gson + `FabricLoader.getConfigDir()` — these are not gray areas, they're settled research.
- `.planning/REQUIREMENTS.md` — CFG-01 through CFG-05 and API-01 through API-07 (API-06/API-07 are Phase 7, not this phase). REF-01's "~60 seconds default" grounds D-04.
- `.planning/ROADMAP.md` — Phase 5 section: goal, 5 success criteria, and the Notes paragraph establishing this as the independent parallel track with zero HTTP-response-to-texture coupling this phase.

### Prior phase decisions
- `.planning/phases/04-static-chart-rendering/04-CONTEXT.md` D-04 — the live Human Design API URL and query-parameter shape (`date`, `time`, `width`, `height`, `transparent`), confirmed live and recorded specifically so this phase wouldn't rediscover it. Directly grounds D-01/D-02/D-03 above. Also confirms `transparent=false` → opaque RGB PNG, no alpha channel, matching the bundled `sample-bodygraph.png`.

### Project conventions — read before writing any Minecraft/Java class
- `.claude/CLAUDE.md` §3 (HTTP Client) — connect timeout vs. request timeout distinction, dedicated executor (not `Runnable::run`, not left to `ForkJoinPool.commonPool()` implicitly — supply a small dedicated executor), build the `HttpClient` once and reuse it, marshal every callback back via `Minecraft.getInstance().execute(...)` before touching any shared/render state.
- `.claude/CLAUDE.md` §5 (Config Library) — why hand-rolled Gson + `FabricLoader.getConfigDir()` and not Cloth Config/owo-lib/midnightlib (no config-screen requirement).
- `.claude/CLAUDE.md` §2 — Mojang official vs. Yarn mappings table; not directly load-bearing for this phase's classes (no rendering/texture types touched), but `Minecraft.getInstance().execute(...)` (not Yarn's `MinecraftClient`) is the one entry from this table this phase actually uses.

### Existing source (read before modifying)
- `src/main/java/transitreport/JollyalchemyTransitReport.java` — main entrypoint; likely home for a `TransitConfig` load call if config needs to be available on the common (server-capable) side, per PROJECT.md's "architecture must not make multiplayer unnecessarily hard later" constraint. Config loading should stay free of client-only imports (ROADMAP.md Phase 5 Notes: "`TransitConfig` stays free of client-only imports so it can live in `src/main`").
- `src/client/java/transitreport/client/JollyalchemyTransitReportClient.java` — currently the client entrypoint; `onInitializeClient()` is where D-05's one-shot verification fetch goes, since the fetch client itself is reasonably client-scoped for this phase's purposes (no server-authoritative fetching planned per PROJECT.md's Out of Scope).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `JollyalchemyTransitReport.MOD_ID` and the static `id(String)` helper — available if any registration-style identifiers are needed (unlikely for a config/HTTP-only phase, but consistent with prior phases' pattern).
- Gson is already on the classpath transitively via Minecraft itself — no new Gradle dependency needed (CLAUDE.md §5).

### Established Patterns
- **Split source sets.** `src/main` is common (server+client-capable), `src/client` is client-only. This phase's `TransitConfig` should live in `src/main` (no client-only imports) per ROADMAP.md's explicit note, while the one-shot verification trigger (D-05) lives in `src/client`'s `onInitializeClient()`.
- Every prior phase's verification protocol: Claude launches `runClient` in the background and tails the log; the user watches the window and confirms what's on screen. This phase's D-06/D-07 continue that exact pattern rather than introducing new tooling (no mock server, no debug command).
- This project has zero existing HTTP or config code — this phase introduces both `TransitConfig` and `TransitApiClient` from scratch. No existing class shapes to match beyond what PROJECT.md's "Intended component decomposition" already names.

### Integration Points
- New: `TransitConfig` (or similar name — `src/main`), holding the base URL template string and refresh interval, backed by Gson + `FabricLoader.getInstance().getConfigDir()`, with default-write-on-missing and reset-to-defaults-on-malformed behavior (D-11/D-12/D-13).
- New: `TransitApiClient` (`src/main` or `src/client` — planner's call whether HTTP itself needs to be client-only; PROJECT.md's multiplayer constraint suggests keeping it reachable from common code long-term, but nothing this phase forces the decision), wrapping a single reused `HttpClient` instance, a dedicated executor, the timeout/size-cap logic (D-08/D-09/D-10), and the template-token substitution (D-03).
- `JollyalchemyTransitReportClient.onInitializeClient()` — gains the one-shot verification call (D-05), temporary scaffolding only.

</code_context>

<specifics>
## Specific Ideas

- The user explicitly overrode the recommended "scheme+host only" config shape in favor of storing the full URL template (including query params) in config — this is a deliberate choice to keep the entire request shape user-editable, not an oversight. Downstream agents should not "simplify" this back to a fixed-path client design without checking with the user first.
- The user's stated reasoning for the size-cap behavior ("I'm responsible on the api side for returning the right image") clarified to: abort-as-failure is fine, since they control the API and don't expect the cap to trigger in normal operation — it's a backstop, not a feature being built for an expected case.
- No mock server this phase (or ever, per REQUIREMENTS.md's v1 Out of Scope) — every verification method chosen (D-05, D-06, D-07) deliberately avoids needing one.

</specifics>

<deferred>
## Deferred Ideas

- **Debug client command or keybind for repeatable fetch triggering.** Considered and explicitly not chosen for this phase (D-05) in favor of a minimal one-shot startup fetch. Noted because Phase 10's CFG-04 (author-only client command to reload config / set base URL at runtime) is a closely related feature landing later — if a command already existed here, Phase 10 might have reused it, but the user chose to keep this phase's scaffolding minimal instead.
- **URI-well-formedness / interval-range validation on config load.** Explicitly rejected in favor of minimal type-only validation (D-13) — revisit only if a malformed-but-type-valid config value causes a real problem in practice.

### Reviewed Todos (not folded)
None — no pending todos matched this phase (`todo.match-phase` returned zero matches).

</deferred>

---

*Phase: 5-Configuration and Async Fetch*
*Context gathered: 2026-09-08*

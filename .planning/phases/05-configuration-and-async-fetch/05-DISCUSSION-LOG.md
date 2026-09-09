# Phase 5: Configuration and Async Fetch - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-08
**Phase:** 5-Configuration and Async Fetch
**Areas discussed:** Default config values, This-phase verification trigger, Timeouts & response size cap, Malformed-config recovery detail

---

## Default config values

| Option | Description | Selected |
|--------|-------------|----------|
| Real Human Design API | https://human-design-4u01.onrender.com — works out of the box, real chart | ✓ |
| Public changing-image dummy URL | ROADMAP.md's zero-setup dummy endpoint | |
| Obvious placeholder | e.g. https://example.invalid — forces explicit config | |

**User's choice:** Real Human Design API
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Scheme+host only | Client builds full path+query itself | |
| Full URL/path template in config | Config stores whole path, incl. query params | ✓ |

**User's choice:** Full URL/path template in config
**Notes:** Deliberate override of the recommended option — keeps entire request shape user-editable rather than hardcoded in the client.

| Option | Description | Selected |
|--------|-------------|----------|
| Placeholder tokens | `{date}`/`{time}` tokens in the stored template, string-replaced per request | ✓ |
| Config template + separate fixed path for date/time | Client always appends date/time itself regardless of template | |

**User's choice:** Placeholder tokens
**Notes:** Follow-up question after the URL-shape decision, to resolve how per-request-changing values fit into a stored template.

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, 60 seconds | Matches REQUIREMENTS.md's stated default | ✓ |
| Something else | Different default number | |

**User's choice:** Yes, 60 seconds
**Notes:** None.

---

## This-phase verification trigger

| Option | Description | Selected |
|--------|-------------|----------|
| One-shot fetch at client startup | onInitializeClient() fires a single fetch, logs result | ✓ |
| Temporary debug client command | `/transitreport fetch` command | |
| Keybind | Bound key fires a fetch | |

**User's choice:** One-shot fetch at client startup
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Point config at a bad host temporarily | Manual config edit + relaunch to observe timeout | ✓ |
| Unit test against a fake HttpClient/server | JUnit test with mocked response | |
| Both | Manual spot check + unit test | |

**User's choice:** Point config at a bad host temporarily
**Notes:** Consistent with REQUIREMENTS.md's decision to scope the mock server out of v1.

| Option | Description | Selected |
|--------|-------------|----------|
| Visual check while moving in-world | Same runClient/tail-log protocol as Phases 1-4 | ✓ |
| Log timestamps before/after fetch call returns | Code-level non-blocking proof | |
| Both | Log-timestamp proof + visual walk-around | |

**User's choice:** Visual check while moving in-world
**Notes:** None.

---

## Timeouts & response size cap

| Option | Description | Selected |
|--------|-------------|----------|
| Generous: 10s connect / 45s request | Covers Render free-tier cold starts | ✓ |
| Moderate: 5s connect / 15s request | Faster failure detection, risks misclassifying cold starts | |

**User's choice:** Generous: 10s connect / 45s request
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| 5 MB | Comfortably above realistic chart PNG size | ✓ |
| 1 MB | Tighter bound, closer to expected size | |
| Something else | Different cap | |

**User's choice:** 5 MB
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Abort the fetch and treat it as a failure | Same handling as any other REL-01 failure | ✓ (after clarification) |
| Truncate and attempt to decode anyway | Keep first N bytes, try decode | (initially selected, then reconsidered) |

**User's choice:** Abort and treat as failure
**Notes:** User initially selected "truncate and decode anyway" with the reasoning "I'm responsible on the api side for returning the right image." Claude flagged that this reasoning actually supports aborting (a truncated PNG essentially never decodes, so truncating buys nothing) rather than the option literally selected, and asked a clarifying follow-up. User confirmed "abort and treat as failure" is what they wanted — this is a defensive backstop, not a feature built for an expected case.

---

## Malformed-config recovery detail

| Option | Description | Selected |
|--------|-------------|----------|
| Full reset to all-defaults on any parse/validation error | Simplest, most predictable | ✓ |
| Salvage individually-valid fields | Keep valid fields, replace only broken ones | |

**User's choice:** Full reset to all-defaults
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Overwrite with defaults | Same code path as missing-file case | ✓ |
| Leave the bad file untouched, use in-memory defaults only | Preserves file contents for manual fixing | |

**User's choice:** Overwrite with defaults
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal: type checks only | Non-empty string / positive number, no format/range validation | ✓ |
| Stricter: validate URL shape and interval range | More validation code, needs justified bounds | |

**User's choice:** Minimal: type checks only
**Notes:** None.

| Option | Description | Selected |
|--------|-------------|----------|
| Include the reason | Log line names the specific parse/validation failure | (not answered) |
| Generic message only | "Config file invalid, using defaults." | (not answered) |

**User's choice:** Not answered — user declined this question mid-flow (tool-use rejection) and asked to continue.
**Notes:** Claude proceeded using discretion: log line should include the specific reason, since it costs nothing extra and aids debugging. Recorded as Claude's Discretion in CONTEXT.md (D-14), not a locked decision.

---

## Claude's Discretion

- **D-14 (CONTEXT.md):** Malformed-config log line includes the specific failure reason rather than a generic message — the underlying question was interrupted before the user answered it.
- Exact Gson field names, Java types, and config POJO class name/location — follow CLAUDE.md §5 guidance directly, no user preference expressed.
- Whether the one-shot startup verification fetch is deleted or left inert once Phase 8's scheduler exists — left to whichever agent implements Phase 8.

## Deferred Ideas

- **Debug client command or keybind for repeatable fetch triggering** — considered for the verification-trigger area, not chosen (minimal one-shot startup fetch chosen instead). Noted for awareness ahead of Phase 10's CFG-04 (author-only runtime config/URL command), which is a related but distinct feature.
- **URI-well-formedness / interval-range validation on config load** — explicitly rejected in favor of minimal type-only validation; revisit only if a real problem surfaces.

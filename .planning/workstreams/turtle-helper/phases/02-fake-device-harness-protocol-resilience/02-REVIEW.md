---
phase: 02-fake-device-harness-protocol-resilience
reviewed: 2026-09-24T00:00:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - turtle/turtle-helper/.gitignore
  - turtle/turtle-helper/CLAUDE.md
  - turtle/turtle-helper/README.md
  - turtle/turtle-helper/bridge/agent.py
  - turtle/turtle-helper/bridge/bridge.py
  - turtle/turtle-helper/bridge/lua_pattern.py
  - turtle/turtle-helper/bridge/settings.py
  - turtle/turtle-helper/harness/__init__.py
  - turtle/turtle-helper/harness/harness.py
  - turtle/turtle-helper/harness/scenarios.py
  - turtle/turtle-helper/pyproject.toml
  - turtle/turtle-helper/tests/test_agent.py
  - turtle/turtle-helper/tests/test_agent_composition.py
  - turtle/turtle-helper/tests/test_bridge_resilience.py
  - turtle/turtle-helper/tests/test_harness_scenarios.py
  - turtle/turtle-helper/turtle/client.lua
  - turtle/turtle-helper/uv.lock
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-09-24T00:00:00Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Reviewed the turtle-helper bridge (`bridge/`), the fake-device harness (`harness/`), the
device-side Lua (`turtle/client.lua`), the four TAP test modules, and the supporting
config/docs/lockfile. The resilience work this phase targeted (D-10 through D-16: pending-cid
bookkeeping, same-id reconnect replacement, malformed-frame tolerance, token-rejection logging,
history trimming, the plain-text-answer fallback) is implemented carefully and the accompanying
tests exercise the documented edge cases directly (fake sockets, scripted models, TAP assertions
with concrete expected values rather than loose truthiness checks). `uv.lock` versions match
`pyproject.toml` exactly; no drift found.

No blocker-level defects were found: no crashes, no injection vectors, no credential leakage
(hello tokens are deliberately redacted in every log line and wire-log line touched by this
phase), no unsafe deserialization (`json.loads`/`textutils.unserialiseJSON` results are always
type-checked before use). The issues below are logic/robustness gaps and a couple of quality
items — none block shipping this phase, but they are real and worth tracking.

## Warnings

### WR-01: Bridge token comparison is not constant-time

**File:** `turtle/turtle-helper/bridge/bridge.py:138`
**Issue:** The hello handshake authenticates a device with a plain `!=` string comparison:
```python
if hello.get("token") != settings.bridge_token:
```
Python's `!=` on strings short-circuits on the first mismatching byte, so response latency can
leak how many leading characters of a guessed token were correct. This is the one place in the
codebase whose surrounding comments (D-16: "the submitted token value is never interpolated into
any log line") show explicit security awareness of this exact value, which makes the plain
comparison an inconsistency rather than an oversight elsewhere. The practical risk is low for a
private LAN server, but the fix is one line and removes the class of bug entirely.
**Fix:**
```python
import hmac
...
if not hmac.compare_digest(str(hello.get("token", "")), settings.bridge_token):
```

### WR-02: `default_worker()` and the per-device composition/primitive check can disagree, misrouting commands once more than one turtle/computer is connected

**File:** `turtle/turtle-helper/bridge/bridge.py:107-112`, `turtle/turtle-helper/bridge/agent.py:402-410`, `turtle/turtle-helper/bridge/agent.py:456-488`
**Issue:** `build_toolset()` offers a device primitive if **any** connected device advertises the
matching cap (`agent.py:481-484`), and offers a composition like `sort_chest` if **any** device
satisfies the full capability set (`agent.py:485-487`, the `COMPOSITIONS` check). But when the
model calls the tool without an explicit `device`, execution falls back to
`bridge.default_worker()`:
```python
def default_worker() -> str | None:
    for d, v in devices.items():
        if v["role"] in ("turtle", "computer"):
            return d
    return None
```
`default_worker()` returns the *first* connected turtle/computer by registry insertion order,
with no regard for which device actually advertised the capability that made the tool eligible.
If device A (caps=`["status"]`) connects before device B (caps=`["list_chest","push_one_slot",
"status"]`), `build_toolset()` correctly offers `sort_chest`/`list_chest`/`push_one_slot` because
B satisfies them, but calling any of those tools without `device=...` routes to A, which will
answer with `{"ok": false, "error": "unknown tool list_chest"}` (client.lua's `session()` for a
tool it doesn't have). `sort_chest` handles that gracefully by returning the device's error, but
the tool is presented to the model as available and then fails with a confusing error instead of
either not being offered or being routed correctly. The system prompt tells the model to "pass
`device` only when there are several" (`agent.py:53-54`), so correctness for the multi-device case
depends entirely on the model remembering to disambiguate — nothing in code enforces it. Out of
scope for the current single-worker milestone, but it's a live bug that will surface the moment a
second turtle or computer is connected (e.g., during in-game testing), and there is no test
covering the "two devices, only one with the needed caps" ordering case.
**Fix:** Have `default_worker()` (or a new helper) accept an optional required-capability filter
and skip devices that don't advertise it, e.g.:
```python
def default_worker(needs: str | None = None) -> str | None:
    for d, v in devices.items():
        if v["role"] in ("turtle", "computer") and (needs is None or needs in v.get("caps", [])):
            return d
    return None
```
and have `_forward()`/`sort_chest()` pass the primitive/first-needed-cap they require.

### WR-03: Narrow exception handling around the startup model check can crash the bridge with a raw traceback

**File:** `turtle/turtle-helper/bridge/bridge.py:242-253`
**Issue:**
```python
try:
    await client.models.retrieve(settings.model)
except anthropic.AuthenticationError:
    ...
except anthropic.NotFoundError:
    ...
except anthropic.APIConnectionError as exc:
    log.warning(...)
else:
    log.info(...)
```
Only three specific Anthropic exception types are handled. Any other `anthropic.APIStatusError`
subclass (e.g., `RateLimitError`, `InternalServerError`, `PermissionDeniedError`, a transient 5xx)
propagates out of `main()` uncaught, terminating `asyncio.run(main())` with an unhandled
traceback instead of the clean, logged failure path the rest of `main()` uses consistently
elsewhere.
**Fix:** Catch the common `anthropic.APIStatusError`/`anthropic.APIError` base class as a
warn-and-continue case (mirroring the `APIConnectionError` branch), so any transient API problem
at boot degrades to "could not verify model" instead of crashing the process.

### WR-04: The harness's own top-level exception handling is narrower than its "every wait is bounded, never hangs" design goal implies

**File:** `turtle/turtle-helper/harness/harness.py:435-447`
**Issue:**
```python
try:
    await scenario(dev, args)
except SpendRefusedError as exc:
    verdict, code = f"REFUSED: {name} - {exc}", 2
except (ScenarioError, TimeoutError, ConnectionClosed, OSError) as exc:
    verdict, code = f"FAIL: {name} - {exc}", 1
finally:
    await dev.close()
```
Any exception type not in that tuple (e.g., an `AttributeError` or `AssertionError` from a bug in
a scenario, or an unexpected exception from a library call inside `FakeDevice`) escapes
`run_scenario()` uncaught, producing a raw Python traceback and a non-standard exit code instead
of the clean `PASS`/`FAIL`/`REFUSED` contract the harness's docstring and README promise ("Exit
code 0 is a pass ... 1 a failed expectation ... a scenario never hangs on a bridge that stopped
answering"). This is a robustness gap in the harness itself, not the bridge under test, but it
means a bug in a scenario produces a confusing crash rather than a diagnosable `FAIL` line.
**Fix:** Add a final `except Exception as exc:` branch mapping to `FAIL` (or a distinct `ERROR`
verdict/exit code) so any unanticipated failure still produces the one-line verdict the rest of
the harness's design promises.

## Info

### IN-01: Dead code — `client.lua`'s application-level `ping` handling is never triggered

**File:** `turtle/turtle-helper/turtle/client.lua:154-155`
**Issue:**
```lua
elseif msg and msg.type == "ping" then
  ws.send(textutils.serialiseJSON({type = "pong"}))
end
```
Nothing on the bridge side ever sends a `{"type": "ping"}` JSON message — the bridge's own
keepalive uses `websockets.asyncio.server.serve(..., ping_interval=..., ping_timeout=...)`
(`bridge/bridge.py:277-278`), which operates at the websocket *protocol* level (opcode-level
ping/pong frames), transparently handled by CC:Tweaked's `http.websocket` without ever surfacing
as an application JSON message. This branch is unreachable in the current protocol. (The same
dead branch exists in `base/chat.lua`, outside this review's scope.)
**Fix:** Remove the branch, or if a future health-check feature is planned, note that explicitly
in a comment so a future reader doesn't assume it is load-bearing today.

### IN-02: `SayArgs.text` has no minimum length, allowing a silent blank `say`

**File:** `turtle/turtle-helper/bridge/agent.py:234-238`
**Issue:**
```python
class SayArgs(BaseModel):
    """Arguments for say."""

    text: str
    to: str | None = Field(default=None, ...)
```
`text` is required but unconstrained, so a model call like `say(text="")` (or all-whitespace)
passes Pydantic validation and results in an empty/blank message being pushed to game chat via
`say_in_chat`. `handle_request`'s own end-of-run fallback explicitly guards against this
(`if not spoke and answer:` at `agent.py:565`, only speaking a non-empty stripped answer), but the
`say` tool itself has no equivalent guard for the model's own direct calls.
**Fix:** `text: str = Field(min_length=1)` (or strip-and-check in the tool body) so a blank `say`
raises a `ModelRetry` instead of reaching chat.

### IN-03: `lua_pattern`'s unsupported-negated-class-in-set restriction isn't mentioned in the module docstring

**File:** `turtle/turtle-helper/bridge/lua_pattern.py:1-10`, `turtle/turtle-helper/bridge/lua_pattern.py:118-120`
**Issue:** The module docstring enumerates the unsupported Lua features as "`%b`, `%f` and
back-references (`%1`)", but `_set()` also rejects an uppercase (negated) class inside a bracket
set, e.g. `[%A]` (`if body is not None and e.isupper(): raise LuaPatternError(...)`), which is
valid, commonly-used Lua syntax. This fails loud via `add_rule`'s `ModelRetry` (not a silent
correctness bug), but the docstring's list of exclusions is incomplete, which could mislead a
future maintainer extending this module.
**Fix:** Add a one-line docstring note next to the existing exclusion list, e.g. "and an uppercase
(negated) class inside a `[...]` set, e.g. `[%A]`, which this translation does not attempt to
expand."

---

_Reviewed: 2026-09-24T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

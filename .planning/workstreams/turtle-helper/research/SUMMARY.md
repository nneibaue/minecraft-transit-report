# Research Summary: turtle-helper v1.0 Local Round Trip

**Project:** turtle-helper — LLM-driven in-game assistant for All the Mods 9
**Domain:** Minecraft Forge 1.20.1 mod, Python async bridge, CC:Tweaked Lua scripting
**Researched:** 2026-09-19
**Confidence:** HIGH (code inspection, official mod docs, Python SDK) with MEDIUM on untested Lua integration

## Executive Summary

Turtle-helper is an LLM-driven assistant that routes chat commands from in-game Minecraft players to Claude via an external Python bridge, executing tools on CC:Tweaked turtles and computers. The v1.0 milestone proves the entire round-trip on a Windows PC with a local Forge server.

The recommended approach is minimal and deliberately constrained: Python 3.12 with `websockets`, `anthropic`, and `pytest`; no frameworks or databases; keep configuration in env vars; rely on a fake device harness for protocol testing without API spend. The architecture is sound and proven in the starter code. The main risk is Lua integration uncertainty.

**One critical decision:** Pin to `websockets <14.0` for v1.0 (pre-deprecation, stable) rather than migrating to the new API. This keeps risk low while Lua is unproven; the migration is planned as v1.1+ work after the round-trip is verified.

## Key Findings

### Recommended Stack

**Python bridge:**
- Python 3.12.10 (Windows) — already installed
- `websockets < 14.0` pinned (legacy API stable until 2030)
- `anthropic` 1.7.0 (current) — Claude API with async tool-use
- `pytest` 9.1.1 + `pytest-asyncio` 1.4.0 — tests without API spend

**Minecraft runtime:**
- CC:Tweaked 1.111.0-1.20.1 (ATM9) — Lua scripting API
- Advanced Peripherals 0.7.40r-1.20.1 (ATM9) — Chat Box peripheral
- Forge 1.20.1 — `computercraft-server.toml` must allow `127.0.0.1`

**websockets API Migration Conflict Resolution:**

STACK.md recommends migrating to `websockets.asyncio.server.serve()` on websockets 17.x (small, mechanical). PITFALLS.md recommends pinning to `websockets < 14.0` (pre-deprecation) because Lua is untested.

**Recommendation: Pin `websockets < 14.0` for v1.0.** Keep risk low. Plan migration for v1.1+ after round-trip proven. Set `websockets==13.0.1` in requirements.txt. Add startup check: `assert websockets.__version__ < '14.0'`.

### Expected Features

**Must have:** Bridge listens on `ws://127.0.0.1:8765`, devices connect/reconnect, chat event flow to Chat Box response, graceful error handling.

**Should have:** Fake device harness, protocol tests with `BRAIN=fake`, local Lua file placement dev loop, CC:Tweaked allow rule documented.

**Defer (v1.1+):** Sorting chores, production hosting, `run_lua` / `ALLOW_EVAL`.

### Architecture Approach

Brain external (Claude); devices are dumb executors. Components: bridge.py (websocket server + agent loop), harness.py (fake device for testing), client.lua (thin executor), chat.lua (event input + Chat Box output queue). Both Lua files have 5s-backoff infinite reconnect loops.

### Critical Pitfalls

1. **websockets API drift (14+ deprecates legacy)** — Pin to `websockets==13.0.1` for v1.0; plan migration for v1.1. Startup check fails fast if upgraded.

2. **Lua code untested** — Fake harness + first-run logging validates structure. Expect ~1–2 field-name corrections on Phase 5 first in-game run.

3. **Connection lifecycle** — Wrap `send_cmd()` to catch `ConnectionClosed`; test sustained ops without spurious disconnects; disable ping/pong on LAN.

## Implications for Roadmap

**Seven phases (5.1–5.7):**

5.1: Environment Setup — no research needed
5.2: Fake Brain Seam — medium research (SDK shapes)
5.3: Fake Device Harness — no research needed
5.4: Lua Setup on Server — medium research (confirm file paths on Windows ATM9)
5.5: Real In-Game Round Trip (Critical Gate) — high research (Lua never run; expect corrections)
5.6: Bridge Restart + Reconnect — no research needed
5.7: Token Rotation (Optional) — no research needed

Research Flags:
- Phase 5.4: CC:Tweaked file paths on Windows ATM9 — confirm on author's machine
- Phase 5.5: Lua integration — expect ~1–2 field-name corrections

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| **Stack** | HIGH | Verified on PyPI; CC:Tweaked/AP versions in ATM9 modlist |
| **Features** | MEDIUM–HIGH | Starter provides foundation; Lua untested, expect ~1–2 corrections |
| **Architecture** | HIGH | Extracted from starter code; data flow clear |
| **Pitfalls** | MEDIUM–HIGH | websockets deprecation official; Lua pitfalls inferred from docs |

**Overall: MEDIUM–HIGH.** Bridge is HIGH. Lua is MEDIUM (docs official, but never executed locally).

### Gaps to Address

1. CC:Tweaked file paths on Windows ATM9: Inferred from GitHub; unconfirmed locally. Validate Phase 5.4 startup.
2. Advanced Peripherals Chat Box signatures (0.7.40r): Inferred from docs; unverified in-game. Log first chat event tuple Phase 5.5.
3. textutils.serialiseJSON with nested empty tables: Starter handles top-level only. Validate all expected JSON fields present Phase 5.5.
4. CC:Tweaked websocket URL matching: Whether returned URL matches exactly as passed. Debug log Phase 5.5.
5. Ping/pong behavior on LAN: Disabled recommended; may re-enable later. Monitor reconnect spikes Phase 5.6.

## Sources

### Primary (HIGH — official docs, code inspection)
- STACK.md: websockets PyPI, anthropic SDK, CC:Tweaked official API (1.20.1), Advanced Peripherals (0.7.x)
- ARCHITECTURE.md: Starter code inspection (bridge.py, client.lua, chat.lua)
- PITFALLS.md: websockets changelog, Anthropic SDK, CC:Tweaked guide, Advanced Peripherals docs

### Secondary (MEDIUM–HIGH — community, inferred patterns)
- FEATURES.md: Fake device pattern (published LLM testing), CC:Tweaked file placement (GitHub #695, #626)
- PROJECT.md: Architecture decisions, author constraints

### Tertiary (MEDIUM — validation needed)
- Advanced Peripherals Chat Box signatures (docs-inferred, unverified in-game)
- CC:Tweaked Windows ATM9 paths (inferred; depends on launcher)
- textutils with complex nested structures (docs-inferred; untested)

---

*Research completed: 2026-09-19*
*Ready for roadmap creation: yes*

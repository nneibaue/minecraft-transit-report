# Phase 5: Real-Device Resilience & Documentation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-25
**Phase:** 05-real-device-resilience-documentation
**Areas discussed:** Device reconnect behaviour, How the two proofs run, README end-to-end pass, CLAUDE.md and model default

Discussed ahead of Phase 4 (not started); all four proposed areas were selected.

---

## Device reconnect behaviour

| Option | Description | Selected |
|--------|-------------|----------|
| Local 'offline' reply (Recommended) | chat.lua answers through its own Chat Box using the existing outbox; no bridge or model | ✓ |
| Silently dropped (current) | chat.lua forwards chat only inside a session; player gets nothing | |
| Queue and forward on reconnect | Stale requests fire later, each costs a model call | |

**User's choice:** Local 'offline' reply
**Notes:** Wording is Claude's call; must not read as a bridge answer; addressed to the player only.

| Option | Description | Selected |
|--------|-------------|----------|
| 5 s, quieter output (Recommended) | Keep 5 s; one line when unreachable, quiet while retrying, one line on reconnect | ✓ |
| Keep as is | 5 s, one line per attempt | |
| Back off toward 30 s | Fewer attempts, slower recovery, more Lua | |

**User's choice:** 5 s, quieter output

| Option | Description | Selected |
|--------|-------------|----------|
| No, keep the plain run (Recommended) | Crash drops to the prompt with the error visible; connect loop already survives network failures | ✓ |
| Yes, simple restart loop | Device comes back after a crash; a real bug becomes a crash loop | |
| Restart loop with an abort window | Most robust, most Lua to write without a local runtime | |

**User's choice:** No, keep the plain run

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add an idle check (Recommended) | ~5 min idle, bridge log shows no disconnect/reconnect; PING_* in .env is the knob | ✓ |
| No, the two proofs are enough | Ping churn would surface later as odd log lines | |

**User's choice:** Yes, add an idle check

---

## How the two proofs run

| Option | Description | Selected |
|--------|-------------|----------|
| One sitting, one checklist (Recommended) | All three checks in one operator session, one plan checkpoint | ✓ |
| One checkpoint per proof | Cleaner evidence per requirement, three round trips | |

**User's choice:** One sitting, one checklist

| Option | Description | Selected |
|--------|-------------|----------|
| Your word plus easy pastes (Recommended) | Pass/fail per check plus bridge lines if handy; verifier records as operator-observed | ✓ |
| Bridge log lines pasted for each proof | Verbatim lines required | |
| Bridge writes a log file, checked by script | Machine-checkable; adds a bridge change | |

**User's choice:** Your word plus easy pastes

| Option | Description | Selected |
|--------|-------------|----------|
| One, after the restart proof (Recommended) | Single devices question after RESIL-01 | |
| One after each of the two roadmap proofs | Two paid calls on claude-haiku-4-5 | |
| Budget three, allow a retry | Two plus one spare so the plan never has to ask again | ✓ |

**User's choice:** Budget three, allow a retry

**Notes:** Restart method (Ctrl+C then rerun) and the devices-first shape (stop bridge, reboot both, start bridge) were offered as Claude's call and accepted.

---

## README end-to-end pass

| Option | Description | Selected |
|--------|-------------|----------|
| Extend in place (Recommended) | Keep Setup > 1/2/3; add a top checklist; fill gaps; fix stale lines | ✓ |
| Restructure as a walkthrough | One numbered path, reference below; Phase 6 rewrites hosting again | |

**User's choice:** Extend in place

| Option | Description | Selected |
|--------|-------------|----------|
| Developer voice now; Phase 6 adds the admin part (Recommended) | One document for the person running the bridge and editing code | ✓ |
| Split into admin and developer sections now | 'Running it' for a non-developer, 'Developing it' for the author | |

**User's choice:** Developer voice now; Phase 6 adds the admin part

| Option | Description | Selected |
|--------|-------------|----------|
| Keep only what's proven (Recommended) | Devices question leads; sorting examples marked unproven or dropped; MODEL line fixed; Next chores points at CLAUDE.md | ✓ |
| Keep the examples, fix the stale line | Examples stay as-is | |

**User's choice:** Keep only what's proven

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, from real captured text (Recommended) | Exact device and bridge lines from Phase 4/5 runs; smoke check folds in | ✓ |
| No, recipe steps only | Expected output stays only in the smoke check | |

**User's choice:** Yes, from real captured text

---

## CLAUDE.md and model default

| Option | Description | Selected |
|--------|-------------|----------|
| Keep Sonnet 5 default, document Haiku as the cheap option (Recommended) | No code change; BRIDGE-03 stands | |
| Switch the default to Haiku 4.5 | Settings default, .env.example, README, CLAUDE.md; amends BRIDGE-03 | ✓ |
| Keep Sonnet 5 and run the in-game proofs on it | Author's .env switches to Sonnet 5 for Phase 4/5 | |

**User's choice:** Switch the default to Haiku 4.5

| Option | Description | Selected |
|--------|-------------|----------|
| 'Verified in game' block under Conventions (Recommended) | One line per fix with date and versions; Current state gets one line | ✓ |
| Fix list in 'Current state' only | Exactly what DOC-02 says; ages out of the section | |

**User's choice:** 'Verified in game' block under Conventions

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 6 first, then the undecided first chore (Recommended) | Phase 6 host setup, CHORE-01 open, then goto/refuel etc. | ✓ |
| Leave the list, just drop the finished item | Current order minus the finished item; Phase 6 not mentioned | |

**User's choice:** Phase 6 first, then the undecided first chore

---

## Claude's Discretion

- Offline-reply wording, the local prefix constant in chat.lua, and how the retry wait pulls events.
- Wording of the unreachable/connected lines in both Lua files.
- Operator checklist wording and order.
- Drop or mark the sorting examples; where the reconnect behaviour is described in the README.
- Date/version format of the Verified in game lines; PROJECT.md wording for the model change.
- Plan shape (coarse: Lua + model default + push; proof sitting; docs last).

## Deferred Ideas

- Queue-and-forward of requests typed during an outage (rejected).
- Supervisor/restart loop in startup.lua (deferred again).
- Bridge log file with machine-checked proofs (Phase 6 candidate).
- Admin/developer README split (Phase 6).
- Per-player history persistence across bridge restarts.
- Hard-kill restart variant.
- Harness scenario for the Lua-only behaviours.
- Whether answers should name device ids (Phase 4).
- Computer 1's leftover `_marker.txt` (operator cleanup).

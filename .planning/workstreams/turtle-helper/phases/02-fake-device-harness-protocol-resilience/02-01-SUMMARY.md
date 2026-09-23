---
phase: 02-fake-device-harness-protocol-resilience
plan: 01
subsystem: device-lua
tags: [cc-tweaked, lua, client.lua, primitives, pushItems, luaparse, D-07]

# Dependency graph
requires:
  - phase: 01-bridge-environment
    provides: bridge/settings split and the Phase 1 client.lua starter (tools table, session loop) this rewrite prunes
provides:
  - "turtle/turtle-helper/turtle/client.lua tracked in git for the first time, reduced to one-to-one CC:Tweaked primitives (D-07)"
  - "tools.push_one_slot(args) primitive: wraps inventory.pushItems(dest, slot, limit), returns {moved = <int>}"
  - "The post-D-07 capability list: dig, inspect, list_chest, move, push_one_slot, refuel, status, turn on a turtle; list_chest, push_one_slot, status on a plain computer (run_lua only when ALLOW_EVAL)"
affects: [02-03 fake worker canned responses, 02-06 Python sort_chest composition, 02-07 CLAUDE.md thin-Lua rule, 04 in-game round trip]

# Actuals (#2632) - estimateTokens scale (chars/4 over the realized diff), not a harness token count.
actuals:
  tokens: 1630
  tasks: 2
  commits: 1
plan_head_before: 20e1fd8c1b19a746845f6f82876f9d83bcd93691

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Thin Lua: each tools.<name> is a single CC:Tweaked call wrapper; loops and policy live on the bridge"
    - "Lua syntax gate without a Lua runtime: luaparse (npm, Lua 5.2 grammar) run from a mktemp -d scratch dir, never from the repo"

key-files:
  created: []
  modified:
    - turtle/turtle-helper/turtle/client.lua

key-decisions:
  - "push_one_slot signature is args.from / args.slot / args.dest / optional args.limit, mirroring list_chest's error style ('no inventory called <from>') so 02-03's fake worker and 02-06's composition have one shape to copy"
  - "writeFile stays in client.lua although nothing calls it after the rules.json removal, per D-07's explicit hold for a later push-script primitive; annotated with a comment rather than deleted"
  - "Task 2 was verification-only and produced no diff, so it has no commit; its evidence (LUA_PARSE_OK, structural greps) is recorded here"

patterns-established:
  - "Primitive naming: snake_case verb_object (push_one_slot) matching the existing list_chest"
  - "Removed-composition marker: the tools header comment states the thin-Lua rule so a future contributor does not re-add loops on the device"

requirements-completed: [HARN-03]

# Coverage metadata (#1602)
coverage:
  - id: D1
    description: "client.lua is tracked in git and contains only the D-07 primitive set: sort_chest/list_rules/add_rule/remove_rule/set_overflow and RULES_FILE/loadRules/saveRules/destFor are gone"
    requirement: HARN-03
    verification:
      - kind: other
        ref: "git ls-files --error-unmatch turtle/turtle-helper/turtle/client.lua"
        status: pass
      - kind: other
        ref: "grep structural verify from 02-01-PLAN Task 2 (status, list_chest, push_one_slot, move, refuel present; sort_chest, add_rule absent)"
        status: pass
    human_judgment: false
  - id: D2
    description: "tools.push_one_slot(args) wraps pushItems(dest, slot, limit) and returns {moved = n}; the file parses under Lua 5.2 grammar"
    requirement: HARN-03
    verification:
      - kind: other
        ref: "node -e luaparse.parse(client.lua, {luaVersion:'5.2'}) -> LUA_PARSE_OK"
        status: pass
      - kind: other
        ref: "grep -n 'function tools.push_one_slot(args)' + 'pushItems' + '{moved = moved}'"
        status: pass
    human_judgment: false

# Metrics
duration: 3min
completed: 2026-09-23
status: complete
---

# Phase 02 Plan 01: Lua Primitive Rewrite (D-07) Summary

**client.lua stripped to one-to-one CC:Tweaked primitives with a new `push_one_slot` wrapper over `pushItems`, tracked in git for the first time and syntax-checked under Lua 5.2 via luaparse**

## Performance

- **Duration:** 3 min
- **Started:** 2026-09-23T19:44:41Z
- **Completed:** 2026-09-23T19:47:22Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Removed every composition and rule-management piece from the device: `sort_chest`, `list_rules`, `add_rule`, `remove_rule`, `set_overflow`, the `RULES_FILE` constant, module-level `rules`/`overflow` state, `loadRules`, `saveRules`, `destFor`, and the top-level `loadRules()` call. The device no longer touches `rules.json` (closes T-02-01b).
- Added `tools.push_one_slot(args)`: wraps `peripheral.wrap(args.from).pushItems(args.dest, args.slot, args.limit)` and returns `{moved = <int>}`, erroring `no inventory called <from>` in the same style as `list_chest`. This is the one primitive Plan 02-06's Python `sort_chest` needs beyond `list_chest`.
- Updated the setup header comment (dropped the rules.json step) and the tools header comment to state the thin-Lua rule; everything else (`readFile`/`writeFile`, `TOKEN` load, `log`, `status`, `list_chest`, the `if turtle then` block, `run_lua` behind `ALLOW_EVAL`, `capabilities()`, `session()`, reconnect loop) is unchanged in shape, so the wire behaviour is identical to Phase 1 except for the capability list content.
- Locked the final primitive set with a Lua 5.2 parse and structural greps. Resulting `caps` (alphabetical, from `capabilities()`): `dig, inspect, list_chest, move, push_one_slot, refuel, status, turn` on a turtle; `list_chest, push_one_slot, status` on a plain computer; `run_lua` appears only when `ALLOW_EVAL = true`.

## Task Commits

1. **Task 1: Remove composition tools, add push_one_slot, update setup comment** - `96438fc` (feat)
2. **Task 2: Syntax-check the rewrite and lock the final primitive set** - no commit (verification-only; produced no file change, evidence below)

**Plan metadata:** see the `docs(02-01)` commit following this file.

### Task 2 evidence

- `luaparse` (Lua 5.2 grammar), installed in a `mktemp -d` scratch directory: `LUA_PARSE_OK`, exit 0. No `package.json` or `node_modules` was added to `turtle/turtle-helper/`.
- Structural verify from the plan (`status`, `list_chest`, `push_one_slot`, `move`, `refuel` present; `sort_chest`, `add_rule` absent): exit 0.
- Turtle block members by line: `move` (76), `turn` (85), `dig` (90), `inspect` (95), `refuel` (103); `run_lua` (115) inside `if ALLOW_EVAL then`.
- `readFile` (16), `writeFile` (23) present.

## Files Created/Modified

- `turtle/turtle-helper/turtle/client.lua` - device-side agent; now 171 lines of primitives only (was 227 with composition). First `git add` of this file.

## Decisions Made

- `push_one_slot` argument names are `from`, `slot`, `dest`, `limit` (the plan's spec; `limit` optional and passed through as nil to push the whole stack). Return is exactly `{moved = n}` where `n` is `pushItems`' return.
- `writeFile` is retained though currently uncalled, per D-07's explicit hold for a later push-script / load-routine primitive; a comment says why so it is not mistaken for dead code.
- Task 2 has no commit: it changed nothing on disk. Recording its evidence here rather than making an empty commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness of guidance] Updated the stale turtle-block comment**
- **Found during:** Task 1
- **Issue:** The `if turtle then` block's comment said bigger routines (`goto`, `mine_vein`...) "should get added here as Lua", which directly contradicts D-07 (composition lives on the bridge). The plan listed the turtle block as "keep unchanged", but leaving that instruction would steer the next contributor into re-adding loops on the device.
- **Fix:** Reworded the comment to "Keep these small and one-to-one; routines that chain them (goto, mine_vein...) are composed on the bridge, not written here." No code in the block changed.
- **Files modified:** turtle/turtle-helper/turtle/client.lua
- **Verification:** structural greps and luaparse pass; `git diff` shows comment-only change inside the block
- **Committed in:** 96438fc (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 guidance-correctness, comment only)
**Impact on plan:** None on behaviour; keeps the file's own comments consistent with the D-07 rule it now embodies.

## Issues Encountered

- Git printed `LF will be replaced by CRLF the next time Git touches it` on `git add` (core.autocrlf on this Windows checkout). The committed content is LF; harmless for CC:Tweaked, noted so nobody reads it as a failure.

## Known Stubs

None. `writeFile` is an intentionally retained helper (D-07), not a stub.

## Threat Flags

None. `push_one_slot` sits inside the same trust boundary as `list_chest` (bridge supplies peripheral names; bad names surface as a `pcall`-caught `error()` returned as `{ok=false, error=...}`), matching T-02-01a's accept disposition. T-02-01b (rules.json on the device) is mitigated by removal.

## Requirements

- HARN-03 is declared by this plan and by 02-03-PLAN.md. Per the shared-ID gate (#2388) it stays `Pending` until 02-03 also produces a SUMMARY; `requirements.ready-ids` reported 0/1 ready at this plan's close, so `mark-complete` was not run.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02-03 (fake worker, D-03) can mirror this exact tool set: caps above, `status` shaped like `tools.status`, and `unknown tool <name>` for anything else.
- Plan 02-06 (Python `sort_chest`) composes `list_chest` then `push_one_slot(from, slot, dest)` the way the removed Lua loop did (`moved`, `no_rule`, `destination_full` bookkeeping now belongs in Python).
- Plan 02-07 must amend `turtle/turtle-helper/CLAUDE.md`, whose Architecture section still says sorting/pathing live in Lua and whose "Current state" still lists `rules.json` on the device (D-17; untouched here by design).
- Real in-game behaviour of `push_one_slot` (argument order against a live `pushItems`) is proven in Phase 4; only syntax and structure are proven here.

## Self-Check: PASSED

- `turtle/turtle-helper/turtle/client.lua` exists on disk and is tracked (`git ls-files --error-unmatch` exit 0).
- Commit `96438fc` exists in `git log`.
- `commits: 1` measured via `git rev-list --count 20e1fd8..HEAD` at SUMMARY time; the single code change is committed, working tree clean for this file.

---
*Phase: 02-fake-device-harness-protocol-resilience*
*Completed: 2026-09-23*

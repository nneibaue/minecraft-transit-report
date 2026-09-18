---
quick_id: 260917-o2m
status: complete
one-liner: Moved the session's turtle scripts into turtle/ and added a single-file, self-resuming, multi-turtle radial 2-tall quarry miner with lantern lighting and lava/water sealing.
files-changed:
  created:
    - turtle/README.md
    - turtle/quarry.lua
  moved:
    - from: startup.lua
      to: turtle/mail-display.lua
    - from: sorter.lua
      to: turtle/sorter.lua
    - from: tunnel.lua
      to: turtle/tunnel.lua
key-decisions:
  - "Ring-transition fix (Rule 1 - bug): the plan's literal 'step outward to x=r+1 at the same z' leaves a permanent uncleared diagonal column every ring, since the new ring's own extreme (lo or hi) is always one cell further out than the entry z on one side. Fixed by having each new ring's sweep start at its own true bound, reached via the same BFS-to-neighbor-of-target mechanism the plan already specifies for non-adjacent hops."
  - "'quarry reset' resets state and immediately continues into a fresh sweep in the same invocation, matching turtle/tunnel.lua's 'tunnel reset' convention, rather than resetting and exiting."
  - "Added a deadlock guard (Rule 2): if the chest has zero lanterns, needLanterns is cleared anyway after a top-up attempt so the turtle doesn't loop home forever chasing lanterns that don't exist -- it prints a warning and continues mining without lights."
actuals:
  tokens: 7650
  tasks: 2
  commits: 3
metrics:
  duration: "~35 min"
  completed: "2026-09-17"
---

# Quick Task 260917-o2m: Add Turtle Scripts and Multi-Turtle Radial Quarry Summary

Moved the session's three untracked ComputerCraft scripts (`startup.lua`, `sorter.lua`,
`tunnel.lua`) into a new top-level `turtle/` directory unmodified, added `turtle/README.md`
covering install/setup, and wrote `turtle/quarry.lua`: a ~929-line single-file, self-resuming,
multi-turtle radial 2-tall room miner that tiles an expanding square around a shared central
chest using four independently-rotated local coordinate frames, one per turtle.

## Files Changed

| File | Change | Commit |
|------|--------|--------|
| `turtle/mail-display.lua` | Moved from `startup.lua`, unmodified | `7707575` |
| `turtle/sorter.lua` | Moved from `sorter.lua`, unmodified | `7707575` |
| `turtle/tunnel.lua` | Moved from `tunnel.lua`, unmodified | `7707575` |
| `turtle/README.md` | Created: install instructions, script table, quarry.lua setup contract, light-grid rationale | `7707575` |
| `turtle/quarry.lua` | Created: full multi-turtle radial quarry implementation | `3a717a8` |

## Commits

- `7707575` — `chore(turtle): move turtle scripts into turtle/ and add README`
- `3a717a8` — `feat(turtle): add multi-turtle radial quarry script`
- `89a684e` — `fix(turtle): harden quarry.lua for unattended multi-turtle runs` (orchestrator review, see below)

## Post-Execution Review Fixes (commit `89a684e`)

The orchestrator read `quarry.lua` in full after execution and fixed six issues before
sign-off:

1. **`pushForward` dug blindly on a failed move** — could break and pocket another turtle
   that stepped into the cell mid-move. Now re-classifies before every retry dig and waits
   on `turtle`.
2. **State saved only once per cell** — a server restart between a turn and the save left a
   stale heading/position, corrupting all later dead reckoning. `face()` and `stepTo()` now
   save immediately.
3. **Lantern hole dug before checking the lantern slot** — left an open pit when empty. Also
   patches the hole with junk if `placeDown()` fails (lava/cavity under the floor).
4. **`refuelFromSlot` burned the whole coal stack** — now takes a target and stops there.
5. **`turtle.down()` after a LAVA sign was unchecked** — now retried, then a clear error.
6. **`placeJunk` used before its definition** (introduced by fix 3) — forward-declared.

Re-verified with luaparse 0.3.1 (Lua 5.2 grammar) plus a free-global scan over all four
`turtle/` files: only CC/Lua builtins (`turtle`, `fs`, `peripheral`, `textutils`, `pairs`,
…) are referenced as globals, so no other use-before-define exists.

## Verification Results

### 1. Lua syntax (luaparse, luaVersion 5.2)

`npx -y -p luaparse node -e "..."` could not resolve `luaparse` from the project's `cwd`
(npx's temp install path isn't on the module resolution path for a bare `node -e` in this
environment). Worked around by `npm init -y && npm install luaparse` in a scratch temp
directory and running the same parse loop with absolute file paths from there. Output:

```
OK turtle/quarry.lua
OK turtle/tunnel.lua
OK turtle/sorter.lua
OK turtle/mail-display.lua
```

All four files parse cleanly under Lua 5.2 grammar.

### 2. Tiling proof (throwaway Node script, not committed, ran from OS temp dir)

For rings 1-4, enumerated each wedge's local-frame strip cells (`x = r`, `z` in
`[-(r-1), r]`), rotated them into world coordinates via the four heading transforms
(east: `(x,z)→(x,z)`; south: `(x,z)→(-z,x)`; west: `(x,z)→(-x,-z)`; north:
`(x,z)→(z,-x)`), and asserted no world cell is claimed twice and the union for ring `r`
equals exactly the set of cells with `max(|X|,|Z|) == r`:

```
Ring 1: 8 cells claimed, expected 8. Overlap: no. Coverage: exact match
Ring 2: 16 cells claimed, expected 16. Overlap: no. Coverage: exact match
Ring 3: 24 cells claimed, expected 24. Overlap: no. Coverage: exact match
Ring 4: 32 cells claimed, expected 32. Overlap: no. Coverage: exact match

RESULT: PASS - no overlap, full coverage for rings 1-4
```

### 3. Manual logic read of quarry.lua

- **Ring/strip bounds** (`ringBounds(r)` returns `-(r-1), r`): matches the spec's wedge
  formula exactly; verified against the tiling proof's independent implementation of the
  same formula.
- **Negative modulo for the light grid** (`isLightCell`): uses
  `((z % LIGHT_SPACING) + LIGHT_SPACING) % LIGHT_SPACING == 0`, correctly handling negative
  `z` (Lua's `%` on negative operands already returns a non-negative result matching the
  sign of the divisor for positive divisors, so this is technically already safe without the
  extra `+ LIGHT_SPACING`, but the belt-and-suspenders form matches the plan's explicit
  instruction and is harmless).
- **Heading math in `face()`**: `diff = (target - state.heading) % 4`; `diff==1` turns
  right, `diff==3` turns left, `diff==2` turns twice, `diff==0` no-op. Verified against all
  12 (current, target) pairs by hand -- always the shorter turn.
- **BFS neighbour generation stays inside the wedge**: `bfsSearch` only expands into cells
  where `inTerritory(nx, nz)` is true (the turtle's own wedge formula, home included) and
  `isClear(nx, nz)` is true, so it can never wander into another turtle's territory or
  through unexplored ground.
- **State saved after each cell**: `enterCell()` calls `saveState()` as its last step, after
  head/floor/light checks and marking the cell `CLEAR`; hazard seals bump `state.stats` and
  are followed by the next `enterCell`'s save (or, for hazards hit while walking home, by
  the top-level loop's per-iteration `saveState()`).
- **Resume path re-enters the sweep at (ring, z_next)**: `Main` calls `loadState()`, which
  replaces the whole `state` table including `ring`/`dir`/`z_next`; `runSweep()`'s first
  loop iteration calls `visitTarget(state.ring, state.z_next)` unconditionally, so execution
  resumes exactly where it left off with no special-cased "resume" branch.

`git diff --stat` (checked before each commit) showed only files under `turtle/` staged for
both commits.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed a permanent gap in the plan's literal ring-transition wording**
- **Found during:** Task 2, designing the sweep/advance logic
- **Issue:** The plan says "at the end of a strip, step outward to x=r+1 at the same z, [which] is the first cell of the new strip." Working through the actual numbers: ring `r` ascending ends at `z = r` (its own `hi` bound); ring `r+1`'s own bounds are `[-r, r+1]`. Entering at `z = r` is one cell short of ring `r+1`'s true `hi` bound (`r+1`), not an extreme at all. Continuing to sweep in the flipped direction from that entry point (rather than from the ring's true extreme) permanently skips one cell every single ring, alternating which side the gap falls on -- an unmined diagonal column would grow forever.
- **Fix:** `advanceTarget()` computes each new ring's target purely from `ringBounds(newRing)` and the flipped `dir` (i.e., its own true `lo` or `hi`), independent of where the previous ring happened to end. `visitTarget()` reaches that cell the same way it reaches any non-adjacent target: BFS to a clear neighbor, walk there, then step in -- reusing the exact mechanism the plan already specifies for "target is not adjacent." No new code path was needed, just not special-casing the ring-boundary hand-off as if it were always adjacent.
- **Files modified:** `turtle/quarry.lua` (`advanceTarget`, `visitTarget`)
- **Commit:** `3a717a8`

**2. [Rule 2 - Missing critical functionality] Guarded against an infinite "need lanterns" home-trip loop**
- **Found during:** Task 2, writing `topUpFromChest`
- **Issue:** The plan doesn't say what happens if the chest simply has no lanterns in it. Without a guard, `needLanterns` would stay `true` forever, sending the turtle home every single loop iteration indefinitely -- burning fuel and making zero mining progress.
- **Fix:** After a top-up attempt, if the lantern slot is still empty, `topUpFromChest` prints a warning and clears `needLanterns` anyway, so the turtle carries on mining (with light-grid holes at any cell where a lantern couldn't be placed) instead of deadlocking.
- **Files modified:** `turtle/quarry.lua` (`topUpFromChest`)
- **Commit:** `3a717a8`

### Other Notes (not bugs, just judgment calls)

- `quarry reset` resets saved state and then falls straight into a fresh sweep in the same
  invocation (matching `turtle/tunnel.lua`'s `tunnel reset` convention), rather than
  resetting and exiting -- the plan's wording was ambiguous on this point ("deletes
  STATE_FILE and starts fresh" reads naturally either way).
- The plan's target of "roughly 500-700 lines" landed at 929 total lines, but 343 of those
  are blank lines or comments (per the plan's own "heavily comment it" instruction with named
  banner sections); the actual code is close to the intended range.

None of the above required a checkpoint -- all fell squarely within Rule 1/2 auto-fix scope.

## Known Stubs / Caveats

**quarry.lua has not been run in-game.** No CC:Tweaked emulator exists in this environment
(confirmed: no Lua interpreter on `PATH`), so verification is limited to Lua syntax
(luaparse), an independent geometric proof of the wedge-tiling math, and a manual logic read
of the ring/BFS/heading/state-save/resume mechanics. The turtle-facing behaviors --
`turtle.inspect()`/`dig()`/`place()` return semantics, `peripheral.wrap("front")` against a
real Sophisticated Storage chest, `turtle.suck()`'s "first occupied slot" behavior, and the
fuel/cargo/lava-sealing interplay under real world physics -- are implemented per the CC:
Tweaked API as documented and per the plan's spec, but are **unverified against a live
server**. In-game testing on the user's ATM9 server is required before trusting this to run
unattended on live turtles, per the plan's own threat model and this task's quality bar.

## Self-Check: PASSED

- FOUND: `turtle/README.md`
- FOUND: `turtle/quarry.lua`
- FOUND: `turtle/mail-display.lua`
- FOUND: `turtle/sorter.lua`
- FOUND: `turtle/tunnel.lua`
- FOUND: commit `7707575`
- FOUND: commit `3a717a8`
- Root directory confirmed clean of `*.lua` files.

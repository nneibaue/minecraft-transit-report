---
quick_id: 260917-pze
status: complete
files_modified:
  - turtle/quarry.lua
  - turtle/README.md
commit: 1da8172
commits:
  - b9ed3ad
  - 1da8172
completed: 2026-09-17
---

# Quick Task 260917-pze: Fix quarry.lua lava handling (scan neighbours) Summary

Fixed `turtle/quarry.lua` so digging a wall block can no longer breach a hidden lava/water
lake unnoticed: the turtle now looks all the way around every newly-entered cell, re-checks
above/ahead immediately after digging, seals fluids on sight, and never re-approaches a
sealed cell.

## What Changed

All seven changes from the plan were implemented exactly as specified, in `turtle/quarry.lua`:

1. **`scanSides(arrivedFrom)`** (new, in Hazards section, after `sealBelow`) — inspects the
   three sides of a just-entered cell other than the one the turtle arrived from (or all four
   on the very first cell / a resumed session), seals any lava/water found with `placeJunk`,
   and marks the neighbour cell KEEP. Never digs — inspect and place only. Wired into
   `enterCell()` right after `handleHead()` and before `handleFloor()`; `enterCell()` gained an
   `isStart` parameter so the resume/first-cell branch in `visitTarget()` passes `true` (scan
   all four sides) while every post-`stepTo()` call passes nothing (scan three, computed from
   `state.heading` captured at the top of `enterCell()`).
2. **`handleHead()`** re-inspects above after a successful `digLoop(turtle.digUp, ...)` and
   seals if the ceiling dig exposed lava/water.
3. **`stepTo()`** re-inspects ahead after `digLoop(turtle.dig, ...)` succeeds and before
   `pushForward()`: seals and returns `false` on lava/water, loops back to wait on `"turtle"`,
   returns `false` on `"keep"`.
4. **`sealAheadHazard()`**'s post-seal sign logic no longer digs blind above the seal: it
   inspects first, only digs if the block classifies `"junk"`, re-inspects after digging, and
   seals (skipping the sign) if that exposes more lava/water instead of blindly placing a sign
   over an open hazard. The existing down-retry loop is unchanged.
5. **`isSourceFluid(data)`** (new, near `classify()`) and a small **`fluidLabel(class, data)`**
   helper distinguish "lava source" from "flowing lava" (and same for water) in every seal
   message (`scanSides`, `sealAheadHazard`, `sealAbove`, `sealBelow`), so all four seal call
   sites were updated to accept and thread through the `data` table.
6. **`markKeep()`** now has a two-line comment documenting that KEEP doubles as "walled off"
   and the sweep must never dig into a KEEP cell again. Confirmed every path that seals a
   hazard ahead already marks that cell KEEP (`stepTo()` returning `false` → `visitTarget()` →
   `markKeep`), and the new `scanSides` marks its own neighbour cells directly.
7. **README** — added a bullet under the `quarry.lua` setup section: run turtles at y >= -52
   to avoid the 1.18+ bedrock-depth lava flood level.

## Deviations from Plan

None — plan executed exactly as written. One small addition beyond the plan's literal text:
a `fluidLabel(class, data)` helper (3 lines) factoring the "lava source" / "flowing lava"
wording used at all four seal-message call sites, since the plan's item 5 already implied this
exact wording would be reused across `scanSides`, `sealAheadHazard`, `sealAbove`, and
`sealBelow`. This is a minor, in-scope reuse of an existing small-helper style already present
in the file (e.g. `isJunkName`, `findItemSlot`) and does not change behavior.

## Verification

**luaparse (Lua 5.2 grammar) over all four `turtle/*.lua` files:**

```
=== luaparse (Lua 5.2) results ===
OK: quarry.lua
OK: tunnel.lua
OK: sorter.lua
OK: mail-display.lua

Overall: PASS
```

**Free-global scan** (AST walk with `scope: true`, listing identifiers with
`isLocal === false`; only CC/Lua builtins expected):

```
=== free-global scan ===
quarry.lua: [error, fs, ipairs, math, pairs, peripheral, print, sleep, textutils, tostring, turtle, type]
tunnel.lua: [error, fs, ipairs, print, sleep, table, textutils, tonumber, turtle, type]
sorter.lua: [error, fs, pairs, peripheral, print, sleep, table, textutils, tostring, turtle, type]
mail-display.lua: [colors, error, ipairs, math, os, peripheral, sleep, string, window]
```

No unexpected free globals in any file (no missing `local`) — all identifiers listed are
recognized ComputerCraft/Lua builtins.

**`git diff --stat`:**

```
turtle/README.md  |   4 ++
turtle/quarry.lua | 191 ++++++++++++++++++++++++++++++++++++++++++++++--------
2 files changed, 167 insertions(+), 28 deletions(-)
```

Only `turtle/quarry.lua` and `turtle/README.md` changed, as required.

**Manual read checks:**
- `scanSides()` never calls a dig function — confirmed by source inspection (only
  `turtle.inspect`, `classify`, `placeJunk`, `markKeep`, `face`).
- `enterCell()` still ends with `saveState()`.
- All turning inside `scanSides()` goes through `face(h)`, which updates `state.heading` and
  saves immediately, so heading state stays correct across the neighbour scan.

## Files Changed

- `turtle/quarry.lua` — all seven changes (scan neighbours, re-check after digs, sign logic,
  source/flowing wording, KEEP comment).
- `turtle/README.md` — added the y >= -52 lava-flood-avoidance setup bullet.

## Commit

`b9ed3ad` — `fix(turtle): look around after every dig and keep lava walled off` (not pushed).

## Self-Check: PASSED

- FOUND: `turtle/quarry.lua` (modified, contains `scanSides`, `isSourceFluid`, `fluidLabel`,
  `deltaForHeading`)
- FOUND: `turtle/README.md` (modified, contains the y >= -52 bullet)
- FOUND: commit `b9ed3ad` in `git log --oneline`

## Post-Execution Additions (commit `1da8172`, orchestrator)

Reviewed `b9ed3ad` in full — all seven planned changes present and correct. Three
additions on top, driven by the user's in-game feedback during the run:

1. **Stone rim around lava (`markBuffer`).** Sealing the visible lava face was not enough:
   later rings would still mine up to the lake edge, converting the whole rim to cobble and
   opening ceilings beside a lake whose surface sits at head height. Now every unmined cell
   touching a lava/water cell becomes KEEP, so the natural stone stays as a one-block wall
   and those cells are never entered.
2. **Built blocks are never dug (`BUILT_NAME_FRAGMENTS`).** The user has a staircase down
   into the room. `cobbled_deepslate_stairs` matched the "deepslate" junk fragment and would
   have been dug. A built-things list (stairs, slabs, walls, bricks, polished/cut, placed
   cobble, planks, fences, doors, torches, lanterns, chests, barrels, signs, rails, glass,
   ladders, paths, carpet) is now checked before the junk lists.
3. **Missing floors are patched only in cells the turtle dug into (`stepTo` → `dug`,
   `handleFloor(dugIn)`).** Standing at the top of a descending staircase, the turtle sees
   air below and would have plugged the stairwell with cobble. Cells already open on arrival
   are left exactly as found.

README updated for all three plus the optional signs stack.

Re-verified with luaparse 0.3.1 (Lua 5.2) and the free-global scan: only CC/Lua builtins.
Still untested in-game — the next test run is the verification.

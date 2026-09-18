---
quick_id: 260917-s7i
status: complete
files_modified:
  - turtle/quarry.lua
  - turtle/README.md
commit: 4bef8d6
completed: 2026-09-17
---

# Quick Task 260917-s7i: Quadrant territories (pinwheel) and solo full-square layout

Executed inline by the orchestrator (user declined subagent spawns this session).

## Why

The wedge layout was geometrically correct for four turtles but a single turtle's wedge has
45° edges and, from inside the room, reads as a fan / "circle". The user asked twice for a
square.

## What changed

- **Quadrant layout (default).** Each turtle owns the quarter-plane x ≥ 1, z ≥ 0 in its own
  frame — a square with the chest at its corner — swept in L-shaped shells
  (`max(x, z+1) == r`, 2r−1 cells). Odd shells walk column-out/row-back, even shells
  row-out/column-back, so consecutive cells are always adjacent, including across shell
  boundaries. Four turtles' quadrants pinwheel around the chest.
- **Solo layout.** `startup solo` / `startup reset solo`: one turtle owns everything but the
  chest and sweeps full square rings (`max(|x|,|z|) == r`, 8r cells) from (r, −(r−1)) to
  (r, −r); the next ring starts at (r+1, −r), adjacent.
- **State** now carries `layout` and `idx` instead of `dir`/`z_next`. Old-format state files
  produce a clear "run `startup reset`" message instead of being misread. `solo` passed on a
  quadrant dig is ignored with a hint.
- Header Territory section rewritten with a shell diagram; README layout bullet.

## Verification

```
parse OK | free globals: ipairs pairs fs textutils type turtle error tostring sleep print
                         math peripheral os keys parallel
quadrant shells 1..6: partition + walking-order adjacency OK
solo shells 1..6: partition + walking-order adjacency OK
pinwheel: 4 rotated quadrants, shells 1..8: overlaps=0, gaps inside radius 7=0,
          chest untouched -> PASS
```

(The first pinwheel run reported "gaps" only on the outer rim |X|,|Z| = R — an artefact of
truncating at shell R, whose quadrant shell only reaches z = R−1; re-checked against the
inner radius R−1 as above.)

## Caveats

- Untested in-game. Existing turtles must `startup reset` (or `startup reset solo`) — the
  program refuses to reuse a wedge-era map.
- `solo` and quadrant turtles must never share a chest.

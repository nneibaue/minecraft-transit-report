---
quick_id: 260917-rei
status: complete
files_modified:
  - turtle/quarry.lua
  - turtle/README.md
commit: 1cfaa6d
completed: 2026-09-17
---

# Quick Task 260917-rei: Re-anchor at chest, Q to stop, skip side scan in open cells

Executed inline by the orchestrator (user declined subagent spawns this session).

## What changed (`turtle/quarry.lua`, `turtle/README.md`)

1. **Home re-anchor.** `findChest()` searches the 3×3 around the believed home cell with
   plain moves (never digs) — four-way look in place, then each side neighbour, then each
   diagonal — and on sighting the chest works the true position back from which side it is
   on, corrects `state.x/z`, and `goHome()` re-runs once to stand at home properly. Every
   home visit is now a position resync.
2. **Clean stop key.** `Q` in the terminal raises `stopRequested`; `runSweep()` checks it
   between cells and exits on a saved state. Implemented with `parallel.waitForAny(runSweep,
   keyWatcher)`; the watcher never returns (that would end the sweep mid-move).
3. **Side scan only when the cell was dug into.** `enterCell()` calls `scanSides()` only when
   `dugIn or isStart`. This removes the three turns per cell that made re-walking an empty
   room slow.
4. Header Usage/Memory notes; README "Stopping and updating a running turtle" section, and a
   warning that `reset` re-sweeps the whole room.

Also removed the never-executed `260917-r0a` quick-task directory (its "scan skip" item is
delivered here; its `relight` command remains unimplemented — see below).

## Verification

```
parse OK | free globals: ipairs pairs fs textutils type turtle error tostring sleep print
                         math peripheral os keys parallel
```

All CC/Lua builtins. `git diff --stat` for `1cfaa6d`: `turtle/quarry.lua`, `turtle/README.md`
only.

## Caveats / open items

- Untested in-game. The re-anchor path in particular deserves a deliberate test: stop the
  turtle with Ctrl+T mid-move once, reboot it, and watch the next home visit print
  "Re-anchored: I was off by (…)".
- The map recorded during a drifted trip is shifted by that offset; re-anchoring fixes the
  origin going forward but does not rewrite old cells. Consequence is benign (a few cells
  revisited or re-dug), and the scan skip makes revisits cheap.
- `relight` (walk cleared light-grid cells and fill in missing lanterns without `reset`) is
  still not implemented; the user has not confirmed they want it.

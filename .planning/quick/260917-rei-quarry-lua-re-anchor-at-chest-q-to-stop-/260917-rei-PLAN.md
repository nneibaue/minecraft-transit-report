---
phase: quick
quick_id: 260917-rei
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - turtle/quarry.lua
  - turtle/README.md
autonomous: true
requirements: []

estimate:
  tokens: 25000
  tasks: 1
  confidence: high
---

<objective>
Three changes to `turtle/quarry.lua` after in-game feedback: (1) re-anchor the turtle's
position at the chest when it comes home one block off; (2) a clean stop key (Q) so updating
the program never needs `Ctrl+T`; (3) skip the three-turn side scan in cells that were
already open. Executed inline by the orchestrator — the user declined subagent spawns this
session.
</objective>

<threat_model>
Same scope as the previous turtle quick tasks: a Lua script in the ComputerCraft sandbox,
fetched from this public repo's `main` via `wget`. No network I/O, no credentials. ASVS L1:
nothing applicable; no blocking findings.
</threat_model>

<context>
Observed: a turtle returned home one block off and stopped with "Expected the chest at
home". Cause: the program was killed (Ctrl+T per the README's old update procedure, or a
server restart) between a `turtle.forward()` and the state save that follows it.
</context>

<tasks>

<task id="1" name="Re-anchor at chest; Q to stop; scan skip">
<files>
turtle/quarry.lua, turtle/README.md
</files>
<action>
1. `findChest()` before `goHome()`: four-way look with `face(h)`/`inspect()` for a block
   whose name contains "chest"; if seen at heading h, true position = (0,0) − delta(h);
   correct `state.x/z`, print the offset, save. Otherwise try the 8 neighbouring offsets
   (sides first, then diagonals) with plain `turtle.forward()` moves only (never dig),
   repeating the look at each; walk back exactly the way it came when not found. `goHome()`
   calls it when the chest isn't in front, then re-runs itself once (`retried` flag) to
   stand at home properly; errors clearly if still not found.
2. `stopRequested` flag checked at the top of `runSweep()`'s loop; a `keyWatcher()` under
   `parallel.waitForAny(runSweep, keyWatcher)` sets it on `keys.q` and keeps listening
   (never returns, so it can't end the sweep mid-move).
3. `enterCell()` calls `scanSides()` only when `dugIn or isStart`.
4. Header Usage/Memory notes; README "Stopping and updating a running turtle" section.
</action>
<verify>
luaparse (Lua 5.2) OK; free globals are CC/Lua builtins only; `git diff --stat` shows only
the two files.
</verify>
<done>
Single commit with both files; verification quoted in the SUMMARY.
</done>
</task>

</tasks>

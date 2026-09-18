---
phase: quick
quick_id: 260917-pze
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
  tokens: 30000
  tasks: 1
  confidence: high
---

<objective>
Fix lava handling in `turtle/quarry.lua`. The first in-game run (ATM9 server, turtle at
bedrock depth) released lava lakes across the cleared floor: the turtle only inspects the
cell directly ahead at feet level, above, and below, so when it digs a wall block whose
*neighbouring* cells contain lava it removes the retaining wall, steps in, moves on, and the
lake pours across the room — which it then "seals" cell by cell with cobble.

Fix = look around after every dig, reseal immediately, and never dig into a walled-off lake
again. Plus a README note that mining at y ≥ -52 avoids the 1.18+ lava-flood level entirely.
</objective>

<threat_model>
Same scope as quick task 260917-o2m: a Lua script in the ComputerCraft sandbox, fetched from
this public repo's `main` via `wget`. No network I/O in the script, no credentials. ASVS L1:
nothing applicable; no blocking findings.
</threat_model>

<context>
- Current `turtle/quarry.lua` is at commit `89a684e` (see `git log -- turtle/quarry.lua`).
  Relevant functions: `classify`, `markKeep`, `stepTo`, `handleHead`, `sealAheadHazard`,
  `sealAbove`, `enterCell`, `visitTarget`, `placeJunk` (forward-declared before the Lights
  section, defined in Hazards).
- Heading convention: 0 = +x, 1 = +z, 2 = -x, 3 = -z. `face(h)` turns and saves state.
- No Lua on PATH. luaparse is installed in the session scratchpad under `luacheck/`
  (`C:/Users/nneib/AppData/Local/Temp/claude/C--Users-nneib-code-minecraft-transit-report/33fd17e0-b442-464a-af26-155e62943298/scratchpad/luacheck`
  — if that path does not exist, `npm init -y && npm install luaparse` in a fresh temp dir).
</context>

<tasks>

<task id="1" name="Look around after every dig; reseal; keep sealed cells sealed">
<files>
turtle/quarry.lua, turtle/README.md
</files>
<action>
Make exactly these changes in `turtle/quarry.lua`. Keep the file's style and comment
density. Do not restructure the sweep, BFS, chest, or state code.

1. **`scanSides()` — neighbour scan after entering a cell.**
   New local function in the Hazards section (after `sealBelow`). Signature
   `scanSides(arrivedFrom)` where `arrivedFrom` is the heading pointing back to the cell the
   turtle came from (i.e. `(state.heading + 2) % 4` at the moment of entry), or `nil` when
   unknown (first cell / after resume) — in which case scan all four.
   For each heading `h` in 0..3 except `arrivedFrom`: `face(h)`; `inspect()`; `classify()`.
   If `"lava"` or `"water"`: `placeJunk(turtle.place)`; on success increment
   `state.stats.hazards` and print one line using the source/flowing wording from item 5;
   on failure print "out of junk". In both cases `markKeep(nx, nz)` for the neighbour cell,
   where `(nx, nz)` = current cell + the unit delta for heading `h` (0→(+1,0), 1→(0,+1),
   2→(-1,0), 3→(0,-1)). Never dig anything in this scan.
   Call it from `enterCell()` right after `handleHead()` and before `handleFloor()`. To know
   `arrivedFrom`, capture `state.heading` at the top of `enterCell()` (the turtle is still
   facing its direction of travel there) and pass `(heading + 2) % 4`; pass `nil` when the
   cell is the one the turtle is already standing on at start/resume (`visitTarget`'s
   `state.x == tx and state.z == tz` branch — add an optional parameter to `enterCell` for
   this).

2. **Re-check above after digging the ceiling.** In `handleHead()`, after a successful
   `digLoop(turtle.digUp, turtle.detectUp)`, call `inspectUp()` again and `classify()`; if
   lava/water → `sealAbove(class)`.

3. **Re-check ahead after digging the feet block.** In `stepTo()`, in the junk branch, after
   `digLoop` succeeds and before `pushForward()`: `inspect()` + `classify()` again; if
   lava/water → `sealAheadHazard(class)` and `return false`. If `"turtle"` → continue the
   outer `while true` loop (it will wait). If `"keep"` → `return false`.

4. **Never dig the ceiling above a seal for the sign.** In `sealAheadHazard()`, replace the
   block after `turtle.up()` with: `inspect()`; if the block ahead classifies `"junk"` →
   `turtle.dig()` → `inspect()` again → if now lava/water → `placeJunk(turtle.place)` (print a
   line, count as hazard) and skip the sign; else place the sign. If the block ahead is
   `"air"` → place the sign. Anything else (`"keep"`, `"turtle"`, lava/water already) →
   skip the sign (seal fluids with `placeJunk(turtle.place)` first). Keep the existing
   retry-down loop unchanged.

5. **Source vs flowing.** Add `local function isSourceFluid(data) return data and data.state
   and data.state.level == 0 end` near `classify()`. Use it only in messages:
   "Sealed lava source ..." vs "Sealed flowing lava ...". Thread the `data` table into the
   seal helpers' print statements where convenient (a second optional parameter is fine);
   behaviour must not change.

6. **Sealed cells stay sealed.** Confirm every path that seals a fluid *ahead* also marks
   that target cell KEEP: `stepTo()` returning false → `visitTarget()` → `markKeep` (already
   true); the new scan marks its neighbour cells itself. Add a two-line comment above
   `markKeep()` stating that KEEP is also the "walled-off lava/water" state and that the
   sweep must never dig into a KEEP cell again.

7. **README.** Under the quarry setup bullets in `turtle/README.md`, add:
   "Run the turtles with their feet at **y ≥ -52**. In 1.18+ worlds every cave below y = -54
   is flooded with lava, so mining at bedrock depth means constant lakes. Two blocks higher
   the ores are the same and the lakes are gone."

Constraints: every new `turtle.place*()` / `dig*()` return value is checked; the new scans
inspect and place only — they never dig; the "only dig junk" whitelist rule holds
everywhere.

Verification:
- luaparse (Lua 5.2 grammar) over all four `turtle/*.lua` files, plus the free-global scan
  (walk the AST with `scope: true`, list identifiers with `isLocal === false`; only CC/Lua
  builtins such as `turtle`, `fs`, `peripheral`, `textutils`, `pairs`, `ipairs`, `math`,
  `print`, `sleep`, `error`, `type` may appear). Quote both outputs in the SUMMARY.
- Manual read: `scanSides` never calls a dig function; `enterCell` still ends with
  `saveState()`; `face()` is used for all turning so heading stays in state.
</action>
<verify>
luaparse OK for all four files; free-global list contains only builtins; `git diff --stat`
shows only `turtle/quarry.lua` and `turtle/README.md`.
</verify>
<done>
One commit `fix(turtle): look around after every dig and keep lava walled off` containing
both files, with the verification outputs quoted in the SUMMARY. Not pushed.
</done>
</task>

</tasks>

<commit_guidance>
Single commit. Message body: the root cause in two sentences, the seven changes as a list,
and the verification outputs. End with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
Do not push. Commit code only; the orchestrator commits .planning artifacts.
</commit_guidance>

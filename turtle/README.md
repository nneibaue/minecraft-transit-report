# Turtle Scripts

These are [CC: Tweaked](https://tweaked.cc/) scripts for the user's ATM9 server
(Minecraft 1.20.1, Forge). They are installed onto a turtle or computer in-game
with `wget`, not run from this repo directly.

## Install

Pull a script and save it as `startup.lua` so it auto-runs (and auto-resumes,
for the scripts that save state) whenever the turtle reboots:

```bash
wget https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/quarry.lua startup.lua
```

Note: the file must be pushed to `main` first, since `wget` reads from the raw
GitHub URL on that branch.

Run a script once without saving it as `startup.lua` (no auto-resume on reboot):

```bash
wget run https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/quarry.lua
```

Forget saved progress and start a script fresh. This makes the turtle re-sweep
the whole room (slowly, since it re-checks every cell), so only use it after the
chest or the turtle has actually been moved:

```bash
quarry reset
```

### Stopping and updating a running turtle

Press **Q** in the turtle's terminal. It finishes the current cell, saves, and
exits. Then:

```bash
rm startup.lua
```
```bash
wget https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/quarry.lua startup.lua
```
```bash
reboot
```

It reloads its map and carries on from where it stopped — no lost progress.
Avoid `Ctrl+T`: it can kill the program between a move and its save, leaving
the map one block off. (If that happens anyway, the turtle notices at its next
home visit — the chest isn't where it expected — searches the surrounding 3×3
for it, and corrects its position.)

## Scripts

| Script | Purpose |
|--------|---------|
| `quarry.lua` | Multi-turtle radial 2-tall room miner. Leaves ores standing, places lanterns on a grid, seals lava/water, resumes after reboot. |
| `tunnel.lua` | Resumable 2x2 tunnel miner with lava diversion and netherrack junction markers. |
| `sorter.lua` | Hallway chest sorter that learns chest contents as it goes. Untested. |
| `crater.lua` | Crafting turtle that discovers the chests in a room, then shuttles between them crating potatoes, wheat and corn (9 → 1 crate). Maps what each chest holds and refuels itself from coal or coal essence. |
| `bridge.lua` | Builds a Macaw's balustrade bridge outward from a start block, labels each new biome with a marker block and a sign, and returns home when it runs out of pieces. |
| `mail-display.lua` | Monitor "You've got mail" gift display. |
| `platform.lua` | Flat platform builder and carver. The platform starts at the block in front of the turtle and extends `z` forward and `x` to the right; the block the turtle starts on is not counted. At each cell it clears a 2-high walkway, digs out the existing floor and lays its own block, so it carves through hills as well as bridging air. Builds with what was in its inventory at start (slot 1 first, then 2, 3, ...), never with dug-up blocks; waits for a refill when it runs out and returns to its starting block. Needs a mining turtle. `platform 4 4`. |
| `crafter.lua` | Wish-list crafter. A stationary crafting turtle that reads wishes from the drawer on top of it, works backwards through its recipe book to what the input chest holds (iron block → ingots → nuggets, log → planks → sticks → torches → lanterns), delivers finished wishes to the output chest, and mirrors its log to a monitor. Untested. |

## `quarry.lua` setup

- One central chest (Sophisticated Storage is fine, treated as a generic
  inventory peripheral).
- One turtle per chest side, directly adjacent to the chest, facing AWAY from
  it. Up to four turtles, never two on the same side.
- **Layout.** By default each turtle mines the **wedge** in front of it: ring
  by ring, fanning out at 45°, never behind or around the chest. Four turtles'
  wedges tile the square around the chest with no gaps or overlap. Two other
  layouts can be picked by argument — `startup quadrant` (the quarter-plane
  ahead and to the right, a square with the chest at its corner; four of them
  pinwheel) and `startup solo` (one turtle takes the whole square around the
  chest; never alongside other turtles on the same chest). To switch an
  existing dig: `startup reset <layout>`.
- Turtle inventory slots:
  - `1` — lanterns
  - `2` — fuel (coal / charcoal)
  - `3` — junk blocks (cobblestone / cobbled deepslate) for sealing and floors
  - `4`-`16` — cargo
- Lock coal and lanterns into the chest's first slots so top-ups are instant —
  a turtle pulls stacks from the chest in slot order and only recognizes the
  first few it finds.
- Anything built is left alone: stairs, slabs, walls, bricks, placed cobble,
  chests, torches, rails, ladders, and so on. The turtle only digs natural
  stone, dirt, gravel, and coal/copper/iron ore. It also never plugs a hole in
  the floor of a cell that was already open when it arrived, so a staircase
  down through the room stays open.
- Optional: a stack of **signs** anywhere in cargo. Each sealed lava face gets a
  sign reading `LAVA` standing on the seal. Without signs it still seals, just
  silently.
- Lava and water are walled off on sight, and every unmined cell touching them
  becomes no-dig, so a one-block rim of natural stone is left around each lake.
- Run the turtles with their feet at **y ≥ -52**. In 1.18+ worlds every cave
  below y = -54 is flooded with lava, so mining at bedrock depth means
  constant lakes. Two blocks higher the ores are the same and the lakes are
  gone.

## `crater.lua` setup

- A **crafting turtle** (crafting table on either side). It works with an
  empty inventory, since `turtle.craft()` refuses to run unless every slot
  outside the 3×3 grid is clear, so it can't carry a coal stack. Fuel left in
  it is burned at startup; anything else it's carrying gets put away in the
  chests as it visits them (into a chest that already holds that item where
  possible, otherwise the last chest of the round).
- Lay a path of one kind of block (crystal sandstone, say) past the chests
  and put the turtle on it. Where it starts is **home**.
- **Phase 1, discovering chests.** On first run it notes the block under home
  and walks every cell it can reach that has that same block beneath it,
  within `SEARCH_RADIUS` (12) blocks, turning a full circle at each cell and
  recording every inventory beside the path (chests, Sophisticated Storage,
  barrels). Hoppers, droppers, furnaces and other turtles are skipped
  (`NOT_A_CHEST` at the top of the script). Set `FOLLOW_FLOOR = false` to let
  it roam any floor within the radius instead.
- **Phase 2, the work loop.** It visits each chest in turn, then rests at home
  for `ROUND_INTERVAL` (120) seconds and goes again. With two chests it shuttles
  back and forth. Only items named in `TARGETS` (potato, wheat, corn; matched on
  the exact name after the colon, so baked potatoes and corn seeds don't count)
  get crafted, 9 into a crate, leaving `KEEP_LOOSE` (0) behind. Whether an item
  actually has a 9-of-a-kind recipe is found out by one test craft, and the
  answer is remembered either way.
- **Buffers.** Sophisticated Storage chests can't be told to reorder
  themselves, so the turtle can only dig past as many stacks as it has free
  slots. Drop a few **barrels** in it (plain chests work too, but merge into
  doubles when side by side) and at each spot where it works it places one on
  top of itself. The storage chest then hands stacks into the barrel by slot
  and the turtle sucks them down, however deep they were. Without a buffer at
  a spot it says so once and falls back to parking.
- Crates go back into the chest they came from. If that chest refuses them
  (full, or a Sophisticated Storage memory slot setup that only takes what it
  already holds), they go into the next chest that will take them, and the
  turtle says so if nothing will.
- **Fuel.** It carries a small reserve of loose coal (`COAL_RESERVE`, 16
  pieces, charcoal counts) in its last slot for emergencies, dropping it into
  the chest it's working on while it crafts and taking it back after. Under
  `FUEL_LOW` (500) it burns coal from a chest, or crafts coal from coal essence
  or coal blocks, only as much as it takes to reach `FUEL_TARGET` (3000);
  leftover coal tops up the reserve and the rest goes back. Coal blocks are
  never burned whole or carried around. Loose coal you leave in the turtle
  becomes the reserve; coal blocks you leave in it get put away like any
  other cargo.
- **Map.** `crater map` prints the chests it knows, their coordinates relative
  to home, and their top items. A reboot resumes in place, since the turtle
  saves its position around every move. If it was killed mid-move, or the
  blocks around it don't match its map (it was carried somewhere, the room
  changed), or it can't reach a chest or home, it rediscovers the room from
  wherever it is, on its own. `crater relearn` forgets the learned recipes but
  keeps the map (say, after adding a mod that gives corn a crate, or if it
  wrongly decided something "doesn't crate"); `crater reset` forgets everything.
  When it skips a target item it says why: no recipe found earlier, or fewer
  than 9 in the chest.
- **Lock.** Once it has found the right chests, `crater lock` freezes that list
  and turns automatic re-mapping off: an unreachable chest is skipped for the
  round, and if it can't recognise where it is after a reboot it asks to be put
  back at home instead of exploring. `crater unlock` turns re-mapping back on.
- **Q** finishes the current round, returns home, and stops.

## `crafter.lua` setup

A wish-list crafter: put what you want in the drawer, dump materials in the
input chest, and finished items turn up in the output chest.

- **Build**, seen from the front: input chest, crafting turtle, output chest in
  a row; a Functional Storage drawer (an oak drawer with 1, 2 or 4 slots) on
  top of the turtle; a monitor under it (2×1 is plenty, a standard monitor is
  fine). The turtle stands **sideways, facing the input chest**, with the
  output chest behind it. That's forced: a turtle can only take items from the
  block in front of, above or below it, and above and below are taken. It
  never moves, so it needs no fuel. Advanced or not makes no difference here;
  an advanced turtle only colours its own little screen, and a standard
  monitor stays grey either way.
- **Install** as `startup.lua` with the `wget` recipe above.
- **Keep it empty.** `turtle.craft()` refuses to run with anything outside the
  3×3 grid, so the turtle carries nothing between crafts: whatever it pulls
  out of the chest goes straight back. Anything left in it at startup is put
  in the input chest.
- **Input chest** (in front): a plain chest or barrel is best, since it can be
  asked to move a stack to its first slot for the turtle to take.
  Sophisticated Storage works, but the turtle has to park the stacks in front
  of the one it wants, which is slower. Intermediates come back here between
  steps, so it needs a couple of free slots.
- **Output chest** (behind, `OUTPUT_SIDE`): finished wishes are pushed here
  from the input chest.
- **Wish list.** Every kind of item in the drawer is a wish, in slot order: the
  first slot is worked on first, the second only when the first can't progress.
  Keep at least one of each item in the drawer, since a locked-but-empty drawer
  slot reads as empty. Wish for plain items: a Sophisticated Storage chest, say,
  is not a `minecraft:chest`, and it carries data the turtle can't craft, so it
  gets "I don't know a recipe for that". If the block on top can't be read as
  an inventory, the output chest doubles as the wish list: drop one of what
  you want in it.
- **Recipes.** CC:Tweaked has no recipe lookup, so the turtle carries its own
  small book: lantern, soul lantern, torch, soul torch, stick, crafting table,
  chest, barrel, furnace, ladder, iron bars, chain, glass pane, bucket, plus
  name-based families: `X_stairs` / `X_slab` / `X_wall` from `X` (granite
  stairs from granite, oak stairs from oak planks, stone brick stairs from
  stone bricks), `X_planks` from any `X` log, wood or stem, `X_nugget` from
  `X_ingot`, `X_ingot` from `X_block` (or nine nuggets), `X_block` from nine
  `X_ingot`, and nine `X` from `X_block` (coal from coal blocks, redstone,
  diamonds; lapis, wheat, melon and bone meal are special-cased). `crafter
  recipes` prints the list. Adding one is a line in `RECIPES`.
- **Working backwards.** For each wish it looks for the ingredients in the
  input chest; whatever is missing it tries to make first, recursively, down
  to what the chest actually holds. It aims for `BATCH` (16) of a wish per
  craft so intermediates are made in useful amounts rather than one at a time.
- **Priority.** A wish that an *earlier* wish needs as an ingredient stays in
  the input chest for it: with lantern above torch on the list, torches are
  kept for lanterns. Put torch first to have them delivered instead.
- **Guessed recipes.** A family guess that isn't a real recipe (the game
  refuses the craft) is remembered in `crafter_bad.txt` on the turtle and not
  retried; `crafter forget` clears it.
- **Monitor.** Top line: the wish list. Below it, the log: what was made and
  where it went, what each stuck wish is waiting for (`lantern: waiting for
  iron nugget < iron ingot < iron block`), and full chests.
- **Untested** in-game as of this commit. The one assumption worth checking
  first: that the drawer shows up as an inventory on the turtle's top side
  (`peripheral.getType("top")` in `lua` should name the drawer). The startup
  line in the log names what it sees on each side.
- **Q** finishes the current craft, puts everything back, and stops.

## `bridge.lua` setup

- Turtle upgrades, both optional. A plain turtle builds the bridge on its
  own. An **Advanced Peripherals Environment Detector** adds the biome
  signs (without one it says so once and skips them). A **pickaxe** lets it
  dig obstacles in its path and take back the piece it places to recover
  its facing after a reboot (without one that piece is left floating above
  the bridge and it tells you where).
- Inventory (any slots, matched by name, re-scanned as needed): **bridge
  pieces** (name containing "bridge" — e.g. a Macaw's Bridges balustrade
  cobblestone bridge), **signs**, **fuel** (coal/charcoal/etc — anything
  `turtle.refuel` accepts), and optionally a **marker block**. Without one
  configured (`MARKER_MATCH`) it auto-picks the first stack that isn't a
  bridge piece, sign, or fuel, and prints which item it picked.
- **Starting.** Place the turtle on top of a `blue_skies:vitreous_moonstone`
  block, facing the direction to build, and run `bridge`. The bridge deck
  goes at the moonstone's level, starting one block out, and the turtle
  flies one block above it. Where it starts is **home**.
- **Biome signs.** Each time the biome changes (including the one it starts
  in, signed beside the moonstone) it puts a marker block beside the bridge
  at deck level with a standing sign on top, text facing the bridge: the
  biome name and how far out it is, e.g. `Dark Forest` / `128m out`. If it
  needs a marker or a sign and has none, it comes home to be restocked and
  signs that biome on the next run.
- **Coming home.** It turns back when it has no bridge pieces left, when
  its fuel would not cover the trip back, at `MAX_LENGTH`, or on Q, and
  parks on the moonstone facing out again, so a refill and another `bridge`
  is all it takes to continue. On rerun it flies out along the bridge to
  where it stopped.
- **Terrain.** Water and lava are bridged over. Solid ground at deck level
  is left in place (the bridge resumes past it); anything in the turtle's
  own path one block up is dug through, except bridge pieces, signs and the
  moonstone.
- **Reboots.** Progress is saved around every move, so a reboot (even
  mid-sign) resumes in place. Since a turtle can't feel which way it faces,
  after a mid-bridge reboot it briefly places one bridge piece above itself
  to read its facing, then takes it back. If that fails it asks to be put
  back on the moonstone facing the bridge.
- `bridge reset` forgets saved progress (run `bridge` again afterward to
  start fresh); `bridge status` prints the saved state without moving.
- **Config knobs worth knowing:** `WIDTH` (extra lanes, built to the right
  of lane 0), `MARKER_SIDE` (which side gets the biome markers),
  `REPLACE_TERRAIN` (dig existing ground under the deck instead of
  skipping it), `MAX_LENGTH` (0 = unlimited).
- **Q** finishes the current column, then heads home and stops.

### Light grid

Turtles can't read block light level directly. Since Minecraft 1.18, hostile
mobs only spawn at block light 0, and a lantern emits light 15 that falls off
by 1 per block — so placing a lantern on a 5-block grid keeps every cell in
the room at light level 10 or higher (`LIGHT_SPACING` at the top of the
script; 8 would still be safe at light 7, just dimmer). Lanterns are sunk
one block into the floor so the room stays fully passable.

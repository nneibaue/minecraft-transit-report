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
| `mail-display.lua` | Monitor "You've got mail" gift display. |

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
- Put it on the floor of the room, anywhere. Where it starts is **home**.
- **Phase 1, discovering chests.** On first run it walks every floor cell it
  can reach within `SEARCH_RADIUS` (6) blocks of home, turning a full circle
  at each cell, and records every inventory beside it (chests, Sophisticated
  Storage, barrels). Hoppers, droppers, furnaces and other turtles are
  skipped (`NOT_A_CHEST` at the top of the script). A doorway inside that
  radius gets explored too, so keep the radius smaller than the room if there
  are more chests next door.
- **Phase 2, the work loop.** It visits each chest in turn, then rests at home
  for `ROUND_INTERVAL` (120) seconds and goes again. With two chests it shuttles
  back and forth. Only items named in `TARGETS` (potato, wheat, corn; matched on
  the exact name after the colon, so baked potatoes and corn seeds don't count)
  get crafted, 9 into a crate, leaving `KEEP_LOOSE` (0) behind. Whether an item
  actually has a 9-of-a-kind recipe is found out by one test craft, and the
  answer is remembered either way.
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
  wherever it is, on its own. `crater reset` is only needed to forget learned
  recipes (say, after adding a mod that gives corn a crate).
- **Q** finishes the current round, returns home, and stops.

### Light grid

Turtles can't read block light level directly. Since Minecraft 1.18, hostile
mobs only spawn at block light 0, and a lantern emits light 15 that falls off
by 1 per block — so placing a lantern on a 5-block grid keeps every cell in
the room at light level 10 or higher (`LIGHT_SPACING` at the top of the
script; 8 would still be safe at light 7, just dimmer). Lanterns are sunk
one block into the floor so the room stays fully passable.

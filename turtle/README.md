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
| `crater.lua` | Crafting turtle that laps a chest-lined room, crates bulk food (9 → 1 crate), maps what each chest holds, and refuels itself from coal or coal essence. Untested. |
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

- A **crafting turtle** with the crafting table on its **right** (chests are
  read through the left side). Its inventory must be **empty**: `turtle.craft()`
  refuses to run unless every slot outside the 3×3 grid is clear, so the turtle
  can't carry a coal stack. Any fuel left in it is burned at startup instead.
- Chests line the walls of a roughly rectangular room (Sophisticated Storage is
  fine). Keep the one-block lane along the walls clear: the turtle turns at the
  first block in its way, so a furnace standing in the lane looks like a corner.
- Park it in an inside corner cell with the chest wall on its **left**, facing
  along that wall. It walks the ring clockwise and ends each lap back there.
- Each lap it reads every chest and, when a chest holds at least `MIN_STACKS`
  (3) full stacks of something tagged as a crop, vegetable, fruit, grain,
  berry, nut or mushroom, crafts 9 of it into a crate until only `KEEP_STACKS`
  (1) loose stack is left. Whether an item actually has a 9-of-a-kind recipe
  is found out by trying once; the result (either way) is remembered, so
  9 × 4 → 1 style recipes and non-food never get crafted by accident.
- **Fuel.** When it is low it takes coal, charcoal or coal blocks from any
  chest that has them, or crafts coal essence into coal, but only enough to
  reach `FUEL_TARGET` (3000). The essence recipe shape (hollow ring vs full
  grid) is worked out by trying and remembered. It won't leave home unless the
  fuel covers a lap or at least reaches a chest the map says has fuel.
- **Map.** `crater map` prints what it remembers about every chest (top items
  and whether it has fuel) without moving. `crater reset` forgets the map and
  the learned recipes; items moving between chests needs no reset since every
  chest is re-read each lap.
- **Q** finishes the current lap, parks at home, and stops.
- Set `CHEST_ROWS = 2` at the top of the script for walls of chests two high;
  it laps once per row.

### Light grid

Turtles can't read block light level directly. Since Minecraft 1.18, hostile
mobs only spawn at block light 0, and a lantern emits light 15 that falls off
by 1 per block — so placing a lantern on a 5-block grid keeps every cell in
the room at light level 10 or higher (`LIGHT_SPACING` at the top of the
script; 8 would still be safe at light 7, just dimmer). Lanterns are sunk
one block into the floor so the room stays fully passable.

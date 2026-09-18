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

Forget saved progress and start a script fresh:

```bash
quarry reset
```

## Scripts

| Script | Purpose |
|--------|---------|
| `quarry.lua` | Multi-turtle radial 2-tall room miner. Leaves ores standing, places lanterns on a grid, seals lava/water, resumes after reboot. |
| `tunnel.lua` | Resumable 2x2 tunnel miner with lava diversion and netherrack junction markers. |
| `sorter.lua` | Hallway chest sorter that learns chest contents as it goes. Untested. |
| `mail-display.lua` | Monitor "You've got mail" gift display. |

## `quarry.lua` setup

- One central chest (Sophisticated Storage is fine, treated as a generic
  inventory peripheral).
- One turtle per chest side, directly adjacent to the chest, facing AWAY from
  it. Up to four turtles, never two on the same side.
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

### Light grid

Turtles can't read block light level directly. Since Minecraft 1.18, hostile
mobs only spawn at block light 0, and a lantern emits light 15 that falls off
by 1 per block — so placing a lantern on a 5-block grid keeps every cell in
the room at light level 10 or higher (`LIGHT_SPACING` at the top of the
script; 8 would still be safe at light 7, just dimmer). Lanterns are sunk
one block into the floor so the room stays fully passable.

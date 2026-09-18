-- =========================================================
-- Multi-turtle radial quarry
--
--   A 2-tall room miner built for a squad of up to four turtles
--   working outward from a shared central chest. Each turtle owns
--   one quarter of an ever-expanding square and mines it forever,
--   leaving ores standing, lighting the room on a grid, and
--   sealing any lava/water it runs into. Self-resuming: rebooting
--   the turtle (or the whole server) picks the dig back up
--   exactly where it stopped.
--
-- Setup:
--   * One central chest (Sophisticated Storage is fine -- it's
--     read as a plain inventory peripheral).
--   * One turtle per chest side, directly adjacent to the chest,
--     facing AWAY from it. Up to four turtles, never two on the
--     same side -- that's what "owns one quarter" means below.
--   * Slots: 1 = lanterns, 2 = fuel (coal/charcoal), 3 = junk
--     block reserve (cobble / cobbled deepslate, for sealing and
--     floor patches), 4-16 = cargo.
--   * Lock coal and lanterns into the chest's first slots so
--     top-ups are instant -- turtle.suck() only ever pulls
--     whatever the chest considers its first stack.
--
-- Usage:
--   quarry            dig forever (or until stopped / out of fuel)
--   quarry reset       forget the saved dig and start over
--
-- Territory -- four wedges tiling an expanding square:
--
--   Each turtle works in its OWN local coordinate frame: the
--   chest is (0,0), the turtle's home cell is (1,0), +x is
--   whichever way the turtle was facing when it started (away
--   from the chest), and +z is the turtle's right. Because every
--   turtle defines its own +x/+z this way, the SAME code, with no
--   rotation logic at all, tiles the whole square around the
--   chest once all four turtles are running it.
--
--   Ring r is the strip x = r, z in [-(r-1), r] (length 2r). A
--   few rings, in one turtle's local frame (H = home, x grows to
--   the right, z grows upward):
--
--         x=1  x=2  x=3
--       +----------------
--     2 |  .    .    .
--     1 |  .    .    .
--   z=0 |  H    .    .
--    -1 |       .    .
--    -2 |            .
--       +----------------
--
--   Sweep serpentine, ring by ring: ring 1 ascends z (0 then 1),
--   ring 2 descends (2, 1, 0, -1), ring 3 ascends again, and so
--   on -- covering every cell of the wedge, forever outward.
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

local LIGHT_SPACING       = 8    -- lantern grid spacing (both axes)
local FUEL_MARGIN         = 60   -- fuel buffer added on top of any BFS trip
local MIN_LANTERNS        = 8    -- top-up target for lantern slot
local JUNK_RESERVE        = 64   -- how many junk blocks to keep in slot 3
local CHEST_RETRY_SECONDS = 30   -- wait this long before retrying a full chest
local TURTLE_WAIT_SECONDS = 10   -- wait this long for another turtle to move

local STATE_FILE = "quarry_state.txt"

local LANTERN_SLOT = 1
local FUEL_SLOT     = 2
local JUNK_SLOT      = 3
local CARGO_FIRST    = 4

-- Junk: safe to dig without a second thought, and safe to place back
-- down for sealing lava/water or patching a missing floor.
local JUNK_TAGS = {
    ["minecraft:base_stone_overworld"] = true,
    ["forge:cobblestone"]              = true,
    ["forge:stone"]                    = true,
    ["minecraft:dirt"]                 = true,
    ["forge:gravel"]                   = true,
    ["forge:sand"]                     = true,
    ["forge:sandstone"]                = true,
}

local JUNK_NAME_FRAGMENTS = {
    "tuff", "calcite", "dripstone_block", "deepslate", "cobblestone",
    "andesite", "diorite", "granite", "smooth_basalt",
}

-- Ores worth digging on sight. Everything else that carries an ore
-- tag (or an "_ore" name) is left standing -- see classify() below.
local ORE_ALLOWED_TAGS = {
    ["forge:ores/coal"]   = true,
    ["forge:ores/copper"] = true,
    ["forge:ores/iron"]   = true,
}

-- =========================================================
-- Block classification
--
-- Every inspect() result boils down to one of six things:
--   "air"    nothing there
--   "junk"   safe to dig (plain stone/dirt/gravel, or an allowed ore)
--   "keep"   leave it standing (other ores, chests, torches, bedrock,
--            anything unrecognized)
--   "turtle" another turtle -- wait, never dig, never mark KEEP
--   "lava"   a hazard to seal
--   "water"  a hazard to seal
-- =========================================================

local function classify(ok, data)
    if not ok then return "air" end

    local name = data.name or ""
    local tags = data.tags or {}

    if name:find("turtle") then return "turtle" end
    if name:find("lava") then return "lava" end
    if name:find("water") then return "water" end

    for tag in pairs(tags) do
        if JUNK_TAGS[tag] or ORE_ALLOWED_TAGS[tag] then return "junk" end
    end

    for _, frag in ipairs(JUNK_NAME_FRAGMENTS) do
        if name:find(frag) then return "junk" end
    end

    -- Any other ore (tagged forge:ores, or an "_ore" name), plus
    -- everything else not otherwise recognized: leave it be.
    return "keep"
end

-- =========================================================
-- Map & state
--
-- map["x,z"] is CLEAR, KEEP, or unset (unknown). State is saved
-- after every cell, every turn at home, and every hazard seal, so
-- a reboot resumes exactly at (ring, z_next).
-- =========================================================

local CLEAR = "CLEAR"
local KEEP  = "KEEP"

local state -- assigned by freshState()/loadState() in Main, below

local function key(x, z)
    return x .. "," .. z
end

-- Cells this turtle is allowed to path through: its own wedge
-- (x >= 1, -(x-1) <= z <= x), plus home -- which already satisfies
-- that formula, but is called out explicitly to match the spec.
local function inTerritory(x, z)
    if x == 1 and z == 0 then return true end
    return x >= 1 and z >= -(x - 1) and z <= x
end

local function isClear(x, z)
    return state.map[key(x, z)] == CLEAR
end

local function markKeep(x, z)
    state.map[key(x, z)] = KEEP
end

local function freshState()
    return {
        x = 1, z = 0, heading = 0,
        ring = 1, dir = 1, z_next = 0,
        map = {},
        stats = { cleared = 0, lights = 0, hazards = 0 },
        needLanterns = false,
    }
end

local function saveState()
    local f = fs.open(STATE_FILE, "w")
    f.write(textutils.serialize(state))
    f.close()
end

local function loadState()
    if not fs.exists(STATE_FILE) then return false end

    local f = fs.open(STATE_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()

    if type(data) == "table" and type(data.map) == "table" then
        state = data
        return true
    end

    return false
end

-- =========================================================
-- Movement
--
-- Heading is purely local: 0 = +x (the direction the turtle was
-- facing when it started, i.e. away from the chest), 1 = +z
-- (its right), 2 = -x (back toward the chest), 3 = -z (its left).
-- There is no compass/GPS involved -- "heading 0" is just
-- whichever way the turtle happened to be facing at boot.
-- =========================================================

-- Forward declaration: stepTo() needs to seal a hazard it walks
-- into, but sealing lives in the Hazards section below.
local sealAheadHazard

local function face(target)
    local diff = (target - state.heading) % 4

    if diff == 0 then return end

    if diff == 1 then
        turtle.turnRight()
    elseif diff == 2 then
        turtle.turnRight()
        turtle.turnRight()
    elseif diff == 3 then
        turtle.turnLeft()
    end

    state.heading = target

    -- Save immediately: if the server restarts between this turn and
    -- the end-of-cell save, a stale heading would silently corrupt
    -- every move the turtle makes after it reboots.
    saveState()
end

local function headingForDelta(dx, dz)
    if dx == 1 then return 0
    elseif dz == 1 then return 1
    elseif dx == -1 then return 2
    elseif dz == -1 then return 3
    end

    error("headingForDelta: not a unit step (" .. dx .. "," .. dz .. ")")
end

-- Dig until the space is clear, coping with gravel/sand that keeps
-- falling back in. Bails out after ~20 tries so a stubborn block
-- (or a chain of falling sand) doesn't loop forever.
local function digLoop(dig, detect)
    local tries = 0

    while detect() do
        tries = tries + 1
        if tries > 20 then return false end

        dig()
        sleep(0.3) -- let gravel/sand settle before checking again
    end

    return true
end

-- Push into the cell ahead, retrying past mobs or a block that
-- fell back into place after digging. Re-classifies before every
-- dig: the space was junk/air when we looked, but gravel may have
-- dropped in (dig it) or another turtle may have stepped in (wait
-- -- digging it would break and pocket the other turtle).
local function pushForward()
    for _ = 1, 20 do
        if turtle.forward() then return true end

        local ok, data = turtle.inspect()
        local class = classify(ok, data)

        if class == "turtle" then
            print("Another turtle is in the way. Waiting " ..
                  TURTLE_WAIT_SECONDS .. "s...")
            sleep(TURTLE_WAIT_SECONDS)
        elseif class == "junk" then
            turtle.dig()
            sleep(0.2)
        elseif class == "air" then
            turtle.attack()        -- a mob is standing there
            sleep(0.2)
        else
            return false           -- keep / lava / water: caller decides
        end
    end

    return false
end

-- Move one step in the given direction, classifying and handling
-- whatever is there first. Used both for stepping into a brand
-- new target cell and for walking an already-CLEAR BFS path (in
-- which case the block ahead is almost always "air", so this just
-- falls through to pushForward()).
local function stepTo(dx, dz)
    face(headingForDelta(dx, dz))

    while true do
        local ok, data = turtle.inspect()
        local class = classify(ok, data)

        if class == "turtle" then
            print("Another turtle is in the way. Waiting " ..
                  TURTLE_WAIT_SECONDS .. "s...")
            sleep(TURTLE_WAIT_SECONDS)
            -- loop back around and re-check; never dig, never KEEP
        elseif class == "lava" or class == "water" then
            sealAheadHazard(class)
            return false
        elseif class == "keep" then
            return false
        else
            if class == "junk" then
                if not digLoop(turtle.dig, turtle.detect) then
                    return false
                end
            end

            if not pushForward() then
                return false
            end

            state.x = state.x + dx
            state.z = state.z + dz
            saveState()            -- position must never lag the real turtle
            return true
        end
    end
end

-- =========================================================
-- BFS
--
-- Used both for going home and for reaching a target cell that
-- isn't directly adjacent to wherever the sweep last left off.
-- Restricted to CLEAR cells inside this turtle's own wedge (plus
-- home), so it never wanders into another turtle's territory or
-- through unexplored ground.
-- =========================================================

local NEIGHBOR_DELTAS = {
    { dx = 1, dz = 0 }, { dx = -1, dz = 0 },
    { dx = 0, dz = 1 }, { dx = 0, dz = -1 },
}

local function isAdjacent(x, z, tx, tz)
    return math.abs(x - tx) + math.abs(z - tz) == 1
end

local function shallowCopy(t)
    local copy = {}
    for i, v in ipairs(t) do copy[i] = v end
    return copy
end

-- Breadth-first search from the turtle's current cell to the
-- first cell satisfying isGoal(x, z). Returns a list of {dx, dz}
-- steps, or nil if no such cell is reachable through CLEAR
-- territory.
local function bfsSearch(isGoal)
    if isGoal(state.x, state.z) then return {} end

    local visited = { [key(state.x, state.z)] = true }
    local queue = { { x = state.x, z = state.z, path = {} } }
    local head = 1

    while head <= #queue do
        local cur = queue[head]
        head = head + 1

        for _, d in ipairs(NEIGHBOR_DELTAS) do
            local nx, nz = cur.x + d.dx, cur.z + d.dz
            local nk = key(nx, nz)

            if not visited[nk] and inTerritory(nx, nz) and isClear(nx, nz) then
                visited[nk] = true

                local npath = shallowCopy(cur.path)
                npath[#npath + 1] = { dx = d.dx, dz = d.dz }

                if isGoal(nx, nz) then return npath end

                queue[#queue + 1] = { x = nx, z = nz, path = npath }
            end
        end
    end

    return nil
end

-- =========================================================
-- Lights
--
-- Turtles can't read block light level. Since Minecraft 1.18,
-- hostile mobs only spawn at light 0, and a lantern emits 15 that
-- falls off by 1 per block -- so a lantern every LIGHT_SPACING
-- blocks keeps the whole room at light 7 or brighter. Lanterns are
-- sunk into the floor (placed down, not stood on the floor) so
-- the room stays fully passable.
-- =========================================================

-- Forward declaration: patching a failed lantern hole needs
-- placeJunk(), which is defined in the Hazards section below.
local placeJunk

local function isLightCell(x, z)
    if x % LIGHT_SPACING ~= 0 then return false end

    local zMod = ((z % LIGHT_SPACING) + LIGHT_SPACING) % LIGHT_SPACING
    return zMod == 0
end

local function maybePlaceLight(x, z)
    if not isLightCell(x, z) then return end

    local ok, data = turtle.inspectDown()
    local class = classify(ok, data)

    if class ~= "junk" then
        return -- existing light, an ore, or anything else: leave it
    end

    -- Check the lantern supply BEFORE opening the floor, so an empty
    -- slot never leaves a pit behind.
    if turtle.getItemCount(LANTERN_SLOT) == 0 then
        state.needLanterns = true
        print("Out of lanterns at (" .. x .. "," .. z .. "); will top up.")
        return
    end

    turtle.digDown()
    turtle.select(LANTERN_SLOT)

    if turtle.placeDown() then
        state.stats.lights = state.stats.lights + 1
        print("Lantern placed at (" .. x .. "," .. z .. ").")
        return
    end

    -- Lantern wouldn't sit (nothing solid under the hole, e.g. lava
    -- or a cave one block further down). Close the pit back up.
    if not placeJunk(turtle.placeDown) then
        print("Open pit at (" .. x .. "," .. z .. ") -- no lantern fit and no junk to patch.")
    end
end

-- =========================================================
-- Hazards
--
-- Lava and water get sealed with whatever junk block is at hand.
-- A missing floor gets patched the same way. Gravel/sand falling
-- into a dig is already handled by digLoop() above.
-- =========================================================

local function isJunkName(name)
    if not name then return false end

    for _, frag in ipairs(JUNK_NAME_FRAGMENTS) do
        if name:find(frag) then return true end
    end

    return false
end

local function findItemSlot(matchFn)
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and matchFn(detail.name) then return slot end
    end

    return nil
end

local function findSignSlot()
    return findItemSlot(function(name) return name:find("sign") ~= nil end)
end

-- Place a junk block via placeFn: slot 3 first, then any cargo
-- slot holding something junk-classified by name.
placeJunk = function(placeFn)
    if turtle.getItemCount(JUNK_SLOT) > 0 then
        turtle.select(JUNK_SLOT)
        if placeFn() then return true end
    end

    for slot = CARGO_FIRST, 16 do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            if detail and isJunkName(detail.name) then
                turtle.select(slot)
                if placeFn() then return true end
            end
        end
    end

    return false
end

-- Seal lava/water directly ahead, then -- lava only -- climb up
-- and post a "LAVA" sign on the wall above the seal, if one is
-- carried. This is decorative/informational, never required.
sealAheadHazard = function(class)
    if not placeJunk(turtle.place) then
        print("Couldn't seal " .. class .. " ahead of (" ..
              state.x .. "," .. state.z .. ") -- out of junk.")
        return
    end

    state.stats.hazards = state.stats.hazards + 1
    print("Sealed " .. class .. " ahead of (" .. state.x .. "," .. state.z .. ").")

    if class ~= "lava" then return end

    local signSlot = findSignSlot()
    if not signSlot then return end

    if not turtle.up() then return end

    if turtle.detect() then
        local ok, data = turtle.inspect()
        if classify(ok, data) == "junk" then
            turtle.dig()
        end
    end

    turtle.select(signSlot)
    turtle.place("LAVA")

    -- Getting back down is not optional: the map assumes the turtle
    -- lives on one y level. Retry past anything that wandered under.
    for _ = 1, 20 do
        if turtle.down() then return end
        turtle.attackDown()
        sleep(0.5)
    end

    error("Stuck one block up at (" .. state.x .. "," .. state.z ..
          ") after placing a LAVA sign. Move me down and run me again.")
end

local function sealAbove(class)
    if placeJunk(turtle.placeUp) then
        state.stats.hazards = state.stats.hazards + 1
        print("Sealed " .. class .. " above (" .. state.x .. "," .. state.z .. ").")
    else
        print("Couldn't seal " .. class .. " above (" ..
              state.x .. "," .. state.z .. ") -- out of junk.")
    end
end

local function sealBelow(class)
    if placeJunk(turtle.placeDown) then
        state.stats.hazards = state.stats.hazards + 1
        print("Sealed " .. class .. " below (" .. state.x .. "," .. state.z .. ").")
    else
        print("Couldn't seal " .. class .. " below (" ..
              state.x .. "," .. state.z .. ") -- out of junk.")
    end
end

-- Head-level (inspectUp) check once the turtle has stepped into a
-- new cell: seal lava/water, dig junk, leave everything else
-- (ores, unknown blocks, another turtle) alone.
local function handleHead()
    local ok, data = turtle.inspectUp()
    local class = classify(ok, data)

    if class == "lava" or class == "water" then
        sealAbove(class)
    elseif class == "junk" then
        if not digLoop(turtle.digUp, turtle.detectUp) then
            print("Couldn't clear the block above (" ..
                  state.x .. "," .. state.z .. "); leaving it.")
        end
    end
end

-- Floor check once the turtle has stepped into a new cell: seal
-- lava/water below, patch a missing floor. A solid floor -- junk
-- or an ore -- is left exactly as it is.
local function handleFloor()
    local ok, data = turtle.inspectDown()
    local class = classify(ok, data)

    if class == "lava" or class == "water" then
        sealBelow(class)
    elseif not ok then
        if placeJunk(turtle.placeDown) then
            state.stats.hazards = state.stats.hazards + 1
        else
            print("No floor and no junk to patch it at (" ..
                  state.x .. "," .. state.z .. ").")
        end
    end
end

-- =========================================================
-- Home & chest
-- =========================================================

local function fuelLevel()
    local f = turtle.getFuelLevel()
    if f == "unlimited" then return math.huge end
    return f
end

-- Burn fuel from one slot, one item at a time, only until the fuel
-- level reaches target -- never the whole stack.
local function refuelFromSlot(slot, target)
    local moved = false

    while turtle.getItemCount(slot) > 0 and fuelLevel() < target do
        turtle.select(slot)
        if not turtle.refuel(1) then break end
        moved = true
    end

    return moved
end

-- Prefer mined coal in cargo first, then the stocked fuel slot.
local function refuelIfNeeded(reserve)
    if fuelLevel() >= reserve then return true end

    for slot = CARGO_FIRST, 16 do
        if fuelLevel() >= reserve then break end

        local detail = turtle.getItemDetail(slot)
        if detail and (detail.name:find("coal") or detail.name:find("charcoal")) then
            refuelFromSlot(slot, reserve)
        end
    end

    if fuelLevel() < reserve then
        refuelFromSlot(FUEL_SLOT, reserve)
    end

    return fuelLevel() >= reserve
end

local function isCargoFull()
    for slot = CARGO_FIRST, 16 do
        if turtle.getItemCount(slot) == 0 then return false end
    end

    return true
end

-- Fuel needed to make it home from HERE: an actual BFS path
-- length (through cleared ground) plus a margin. Checked before
-- every cell so the turtle is never stranded out in the wedge.
local function homeReserve()
    local path = bfsSearch(function(x, z) return x == 1 and z == 0 end)
    local dist = path and #path or math.huge
    return dist + FUEL_MARGIN
end

-- A cheap straight-line (not BFS) estimate of the round trip out
-- to the cell the sweep is about to resume at and back home.
-- Used only to size the chest top-up and to decide whether it's
-- worth trying to go back out at all.
local function pendingRoundTrip()
    return 2 * (math.abs(state.ring - 1) + math.abs(state.z_next)) + FUEL_MARGIN
end

local function goHome(reason)
    print("Going home: " .. reason .. ".")

    local path = bfsSearch(function(x, z) return x == 1 and z == 0 end)
    if not path then
        error("No path home from (" .. state.x .. "," .. state.z .. "). Stuck.")
    end

    for _, step in ipairs(path) do
        if not stepTo(step.dx, step.dz) then
            error("Blocked on the way home at (" .. state.x .. "," .. state.z .. ").")
        end
    end

    face(2) -- toward the chest

    local ok, data = turtle.inspect()
    if not ok or not data.name:find("chest") then
        error("Expected the chest at home but found " ..
              (ok and data.name or "nothing") ..
              ". Stopping -- check the turtle's position.")
    end
end

local function topUpJunkReserve()
    for slot = CARGO_FIRST, 16 do
        if turtle.getItemCount(JUNK_SLOT) >= JUNK_RESERVE then break end

        local detail = turtle.getItemDetail(slot)
        if detail and isJunkName(detail.name) then
            local room = JUNK_RESERVE - turtle.getItemCount(JUNK_SLOT)
            turtle.select(slot)
            turtle.transferTo(JUNK_SLOT, math.min(room, turtle.getItemCount(slot)))
        end
    end
end

local function dropCargo()
    for slot = CARGO_FIRST, 16 do
        turtle.select(slot)

        while turtle.getItemCount(slot) > 0 do
            if not turtle.drop() then
                print("Chest full, waiting " .. CHEST_RETRY_SECONDS .. "s to retry...")
                sleep(CHEST_RETRY_SECONDS)
            end
        end
    end
end

local function depositCargo()
    topUpJunkReserve()
    dropCargo()
end

local function chestHasWanted(list)
    for _, item in pairs(list) do
        local name = item.name or ""
        if name:find("coal") or name:find("charcoal") or name:find("lantern") then
            return true
        end
    end

    return false
end

-- turtle.suck() only ever pulls the chest's first occupied slot,
-- so to find coal/charcoal or lanterns that aren't at the front,
-- pull stacks into empty cargo slots one at a time, keep what's
-- wanted, and return the rest.
local function topUpFromChest()
    local chest = peripheral.wrap("front")
    local shouldTry = true

    if chest and chest.list then
        shouldTry = chestHasWanted(chest.list())
    end

    if not shouldTry then
        print("Chest has no coal/charcoal or lanterns to pull.")
        return
    end

    local fuelTarget = pendingRoundTrip() * 2
    local pulls = 0

    while pulls < 13 do
        local lanternsOk = turtle.getItemCount(LANTERN_SLOT) >= MIN_LANTERNS
        local fuelOk = fuelLevel() >= fuelTarget or turtle.getItemCount(FUEL_SLOT) > 0
        if lanternsOk and fuelOk then break end

        local destSlot = CARGO_FIRST + pulls
        turtle.select(destSlot)
        if not turtle.suck() then break end

        pulls = pulls + 1

        local detail = turtle.getItemDetail(destSlot)
        if detail then
            if detail.name:find("lantern") then
                turtle.transferTo(LANTERN_SLOT, 64)
            elseif detail.name:find("coal") or detail.name:find("charcoal") then
                refuelFromSlot(destSlot, fuelTarget)
                if turtle.getItemCount(destSlot) > 0 then
                    turtle.transferTo(FUEL_SLOT, 64)
                end
            end
        end
    end

    -- Return anything pulled but not wanted (e.g. other cargo the
    -- chest happened to have stacked in front of the coal/lanterns).
    for slot = CARGO_FIRST, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            turtle.drop()
        end
    end

    if turtle.getItemCount(LANTERN_SLOT) > 0 then
        state.needLanterns = false
    elseif state.needLanterns then
        -- No lanterns anywhere in the chest. Don't loop home forever
        -- chasing lanterns that don't exist -- carry on without them.
        print("No lanterns available in the chest -- continuing without them.")
        state.needLanterns = false
    end

    print("Topped up: " .. pulls .. " stack(s) pulled from the chest.")
    print("Tip: lock coal and lanterns into the chest's first slots so top-ups are instant.")
end

local function serviceChest()
    depositCargo()
    topUpFromChest()
end

local function goHomeAndService(reason)
    goHome(reason)
    serviceChest()
end

-- After servicing, is there enough fuel left to go back out to
-- the cell the sweep is resuming at and return home again?
local function terminalFuelCheck()
    return fuelLevel() >= pendingRoundTrip()
end

-- =========================================================
-- Sweep
-- =========================================================

local function ringBounds(r)
    return -(r - 1), r
end

local function ringLength(r)
    return 2 * r
end

local function isFirstOfRing(ring, dir, z)
    local lo, hi = ringBounds(ring)
    return (dir == 1 and z == lo) or (dir == -1 and z == hi)
end

-- Head-level, floor, and light-grid checks for the cell the
-- turtle is now standing in, then mark it CLEAR and save.
local function enterCell(x, z)
    handleHead()
    handleFloor()
    maybePlaceLight(x, z)

    state.map[key(x, z)] = CLEAR
    state.stats.cleared = state.stats.cleared + 1
    saveState()
end

-- Get to (tx, tz) and clear it: step directly if adjacent,
-- otherwise BFS through already-CLEAR territory to a cell next
-- to the target and walk there first. If no path exists, or the
-- final step is blocked (an ore, a hazard, something stubborn),
-- mark the target KEEP and give up on it for good.
local function visitTarget(tx, tz)
    if state.x == tx and state.z == tz then
        enterCell(tx, tz)
        return true
    end

    local dx, dz = tx - state.x, tz - state.z

    if math.abs(dx) + math.abs(dz) == 1 then
        if stepTo(dx, dz) then
            enterCell(tx, tz)
            return true
        end

        markKeep(tx, tz)
        return false
    end

    local path = bfsSearch(function(x, z) return isAdjacent(x, z, tx, tz) end)

    if not path then
        markKeep(tx, tz)
        return false
    end

    for _, step in ipairs(path) do
        if not stepTo(step.dx, step.dz) then
            -- A previously-clear cell got blocked (lava breach,
            -- something placed). Give up on this target without
            -- marking it KEEP; the sweep moves on to the next cell.
            return false
        end
    end

    dx, dz = tx - state.x, tz - state.z

    if stepTo(dx, dz) then
        enterCell(tx, tz)
        return true
    end

    markKeep(tx, tz)
    return false
end

-- Advance (ring, dir, z_next) to the next target in the serpentine
-- sweep: one more step within the current ring, or -- if the ring
-- is done -- the next ring's own starting extreme, direction
-- flipped.
local function advanceTarget()
    local lo, hi = ringBounds(state.ring)

    if state.dir == 1 then
        if state.z_next < hi then
            state.z_next = state.z_next + 1
            return
        end
    else
        if state.z_next > lo then
            state.z_next = state.z_next - 1
            return
        end
    end

    state.ring = state.ring + 1
    state.dir = -state.dir

    local newLo, newHi = ringBounds(state.ring)
    state.z_next = (state.dir == 1) and newLo or newHi
end

local function runSweep()
    while true do
        local reason = nil

        if isCargoFull() then
            reason = "cargo full"
        elseif state.needLanterns then
            reason = "need lanterns"
        else
            local reserve = homeReserve()
            if not refuelIfNeeded(reserve) then
                reason = "low on fuel"
            end
        end

        if reason then
            goHomeAndService(reason)

            if not terminalFuelCheck() then
                print("Out of fuel and none in the chest. Stopping at home.")
                return
            end
        end

        if isFirstOfRing(state.ring, state.dir, state.z_next) then
            print("Ring " .. state.ring .. " (" .. ringLength(state.ring) .. " cells)")
        end

        visitTarget(state.ring, state.z_next)
        advanceTarget()
        saveState()
    end
end

-- =========================================================
-- Main
-- =========================================================

local args = { ... }

if args[1] == "reset" and fs.exists(STATE_FILE) then
    fs.delete(STATE_FILE)
    print("Forgot the old dig.")
end

if args[1] ~= "reset" and loadState() then
    print("Resuming at ring " .. state.ring .. ", " ..
          state.stats.cleared .. " cell(s) cleared so far.")
else
    state = freshState()
    saveState()
    print("Starting a new quarry.")
end

runSweep()

print("Stopped. " .. state.stats.cleared .. " cell(s) cleared, " ..
      state.stats.lights .. " light(s) placed, " ..
      state.stats.hazards .. " hazard(s) sealed.")

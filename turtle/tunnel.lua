-- =========================================================
-- 2x2 tunnel miner
--
--   Digs a 2 wide, 2 tall tunnel, torches the walls, and runs
--   back to the chest when full.
--
--   Remembers the tunnel it dug in tunnel_state.txt, so running
--   it again walks back out to the dig face and carries on.
--
--   Lava: seals it off with whatever it is carrying, drops a
--   netherrack marker in the floor, and turns down a new
--   direction.
--
-- Setup:
--   * Chest directly BEHIND the turtle
--   * Turtle facing the direction you want the tunnel
--   * Slot 1: torches
--   * Slot 2: coal
--   * Slot 3: netherrack (junction markers)
--
-- Usage:
--   tunnel           dig the default run length
--   tunnel 40        dig 40 more blocks
--   tunnel reset     forget the old tunnel and start fresh
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

local RUN_LENGTH  = 100       -- blocks to dig per run
local TORCH_EVERY = 4         -- torch spacing, in blocks
local WIDEN_SIDE  = "right"   -- which side the second column is on

local TORCH_SLOT  = 1
local FUEL_SLOT   = 2
local MARKER_SLOT = 3
local CARGO_FIRST = 4         -- mined blocks land from here up

local STATE_FILE  = "tunnel_state.txt"

-- =========================================================
-- Turning
-- =========================================================

local WALL_SIDE = (WIDEN_SIDE == "right") and "left" or "right"

local function opposite(dir)
    return dir == "left" and "right" or "left"
end

local function turn(dir)
    if dir == "left" then turtle.turnLeft() else turtle.turnRight() end
end

local function turnBack(dir)
    turn(opposite(dir))
end

local function turnAround()
    turtle.turnLeft()
    turtle.turnLeft()
end

-- =========================================================
-- The map of the tunnel
--
-- One entry per straight stretch. turn is the direction it
-- turned to start that stretch, nil for the first one.
-- =========================================================

local legs = { { len = 0 } }

local function currentLeg()
    return legs[#legs]
end

local function totalLength()
    local n = 0
    for _, leg in ipairs(legs) do n = n + leg.len end
    return n
end

local function saveState()
    local f = fs.open(STATE_FILE, "w")
    f.write(textutils.serialize({ legs = legs }))
    f.close()
end

local function loadState()
    if not fs.exists(STATE_FILE) then return false end

    local f = fs.open(STATE_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()

    if type(data) == "table" and type(data.legs) == "table" and #data.legs > 0 then
        legs = data.legs
        return true
    end

    return false
end

-- =========================================================
-- Digging and moving
-- =========================================================

local function lavaAt(inspect)
    local ok, data = inspect()
    return ok and data.name:find("lava") ~= nil
end

-- Dig until the space is clear. Handles falling gravel, and
-- gives up on bedrock instead of looping forever.
local function clear(dig, detect, inspect)
    local stubborn = 0

    while detect() do
        local ok, data = inspect()

        if ok and data.name:find("bedrock") then
            return false
        end

        if not dig() then
            stubborn = stubborn + 1
            if stubborn > 10 then return false end
        end

        sleep(0.1)          -- let gravel and sand settle
    end

    return true
end

local function clearFront() return clear(turtle.dig, turtle.detect, turtle.inspect) end
local function clearUp()    return clear(turtle.digUp, turtle.detectUp, turtle.inspectUp) end

local function push()
    for _ = 1, 20 do
        if turtle.forward() then return true end

        clearFront()
        turtle.attack()     -- something alive in the way
        sleep(0.2)
    end

    return false
end

-- Dig one block ahead and move into it.
-- Returns "ok", "lava" or "blocked".
local function stepForward()
    if lavaAt(turtle.inspect) then return "lava" end

    if not clearFront() then return "blocked" end

    -- Digging may have opened into lava
    if lavaAt(turtle.inspect) then return "lava" end

    if not push() then return "blocked" end

    return "ok"
end

local function clearAbove()
    if lavaAt(turtle.inspectUp) then return "lava" end
    clearUp()
    if lavaAt(turtle.inspectUp) then return "lava" end
    return "ok"
end

-- Walk through tunnel that is already dug
local function travel(blocks)
    for _ = 1, blocks do
        clearFront()        -- gravel may have fallen in behind us

        if not push() then
            error("Blocked inside the tunnel. Clear it and run me again.")
        end
    end
end

-- =========================================================
-- Sealing lava
--
-- Uses mined junk first, netherrack as a last resort.
-- =========================================================

local function sealWith(place)
    for slot = CARGO_FIRST, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)
            if place() then return true end
        end
    end

    if turtle.getItemCount(MARKER_SLOT) > 0 then
        turtle.select(MARKER_SLOT)
        if place() then return true end
    end

    return false
end

local function sealAround()
    if lavaAt(turtle.inspect)     then sealWith(turtle.place)     end
    if lavaAt(turtle.inspectUp)   then sealWith(turtle.placeUp)   end
    if lavaAt(turtle.inspectDown) then sealWith(turtle.placeDown) end
end

-- =========================================================
-- Torches and markers
-- =========================================================

local function blockAhead()
    local ok, data = turtle.inspect()
    if ok then return data.name end
    return nil                          -- open air
end

-- A torch needs an empty space to go into, so carve a small
-- alcove in the wall and stand the torch in that. Never digs
-- a torch that is already there.
local function placeTorch()
    if turtle.getItemCount(TORCH_SLOT) == 0 then
        print("Out of torches.")
        return
    end

    turn(WALL_SIDE)

    local name = blockAhead()

    if name and name:find("torch") then
        turnBack(WALL_SIDE)             -- already lit, leave it be
        return
    end

    if name and name:find("lava") then
        sealWith(turtle.place)
        turnBack(WALL_SIDE)
        return
    end

    if name then
        clearFront()                    -- solid wall: carve the alcove

        if lavaAt(turtle.inspect) then
            sealWith(turtle.place)
            turnBack(WALL_SIDE)
            return
        end
    end

    turtle.select(TORCH_SLOT)

    if not turtle.place() then
        print("Couldn't place a torch at " .. totalLength() .. ".")
    end

    turnBack(WALL_SIDE)
end

-- Netherrack in the floor: this is where the tunnel turns
local function markJunction()
    if turtle.getItemCount(MARKER_SLOT) == 0 then
        print("Out of netherrack, no marker left here.")
        return
    end

    if lavaAt(turtle.inspectDown) then return end

    turtle.digDown()
    turtle.select(MARKER_SLOT)
    turtle.placeDown()
end

-- =========================================================
-- Fuel and cargo
-- =========================================================

local function refuel()
    if turtle.getFuelLevel() == "unlimited" then return true end

    while turtle.getFuelLevel() < totalLength() + 40 do
        turtle.select(FUEL_SLOT)

        if not turtle.refuel(1) then
            return false
        end
    end

    return true
end

local function isFull()
    for slot = CARGO_FIRST, 16 do
        if turtle.getItemCount(slot) == 0 then return false end
    end

    return true
end

-- =========================================================
-- Walking the recorded route
-- =========================================================

-- From the chest, facing the tunnel, out to the dig face
local function walkOut()
    for _, leg in ipairs(legs) do
        if leg.turn then turn(leg.turn) end
        travel(leg.len)
    end
end

-- From the dig face back home, ending up facing the chest
local function walkHome()
    turnAround()

    for i = #legs, 1, -1 do
        travel(legs[i].len)
        if legs[i].turn then turn(opposite(legs[i].turn)) end
    end
end

local function unload()
    print("Full. Heading back " .. totalLength() .. " blocks.")

    walkHome()

    for slot = CARGO_FIRST, 16 do
        turtle.select(slot)
        turtle.drop()
    end

    turnAround()
    walkOut()

    print("Back at work.")
end

-- =========================================================
-- Lava: wall it off and pick a new direction
-- =========================================================

local function divert()
    print("Lava at " .. totalLength() .. ". Walling it off.")

    sealAround()
    markJunction()

    for _, dir in ipairs({ WIDEN_SIDE, WALL_SIDE }) do
        turn(dir)

        if lavaAt(turtle.inspect) then
            sealWith(turtle.place)
            turnBack(dir)
        else
            legs[#legs + 1] = { len = 0, turn = dir }
            saveState()
            print("Turning " .. dir .. " and carrying on.")
            return true
        end
    end

    print("Lava both ways. Going home.")
    return false
end

-- =========================================================
-- One slice of tunnel: forward one block, clearing all four
-- blocks of the 2x2, ending back in the starting column.
-- =========================================================

local function mineSlice()
    local ahead = stepForward()
    if ahead ~= "ok" then return ahead end

    currentLeg().len = currentLeg().len + 1

    if clearAbove() == "lava" then sealWith(turtle.placeUp) end
    if lavaAt(turtle.inspectDown) then sealWith(turtle.placeDown) end

    -- Step sideways for the second column
    turn(WIDEN_SIDE)
    local side = stepForward()

    if side ~= "ok" then
        if side == "lava" then sealWith(turtle.place) end
        turnBack(WIDEN_SIDE)
        return "ok"                     -- narrow slice, keep going
    end

    turnBack(WIDEN_SIDE)

    if clearAbove() == "lava" then sealWith(turtle.placeUp) end

    -- And back into the travelling column
    turn(WALL_SIDE)
    stepForward()
    turnBack(WALL_SIDE)

    return "ok"
end

-- =========================================================
-- Main
-- =========================================================

local args = { ... }
local runLength = RUN_LENGTH

if args[1] == "reset" then
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    print("Forgot the old tunnel.")
    table.remove(args, 1)
end

runLength = tonumber(args[1]) or runLength

if loadState() and totalLength() > 0 then
    print("Resuming: " .. totalLength() .. " blocks in, " .. #legs .. " stretch(es).")

    if not refuel() then
        error("Not enough fuel to walk back out. Put coal in slot " .. FUEL_SLOT .. ".")
    end

    walkOut()
    print("At the dig face.")
else
    legs = { { len = 0 } }
    saveState()
    print("Starting a new tunnel.")
end

print("Digging " .. runLength .. " more blocks.")

for slice = 1, runLength do
    if not refuel() then
        print("Out of fuel. Put coal in slot " .. FUEL_SLOT .. ".")
        break
    end

    local result = mineSlice()

    if result == "lava" then
        if not divert() then break end
    elseif result == "blocked" then
        print("Hit something I can't dig. Stopping.")
        break
    end

    saveState()

    if slice % TORCH_EVERY == 0 then
        placeTorch()
    end

    if isFull() then
        unload()
    end
end

-- Home, unload, and face the tunnel ready for next time
print("Returning to the chest.")

walkHome()

for slot = CARGO_FIRST, 16 do
    turtle.select(slot)
    turtle.drop()
end

turnAround()
turtle.select(1)
saveState()

print("Done. Tunnel is now " .. totalLength() .. " blocks, " .. #legs .. " stretch(es).")
print("Run me again to pick up where I left off.")

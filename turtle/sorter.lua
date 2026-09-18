-- =========================================================
-- Hallway sorting turtle
--
--   Learns what lives in each chest downstairs, then hauls
--   loads from the dump chest upstairs and puts them away.
--
-- Home position: bottom of the hallway, standing in the lane
-- next to the LEFT wall, facing down the hallway.
--
--   L1 L2 L3 L4      <- chests, left wall
--   .. .. .. ..      <- lane A  (turtle starts here, facing right)
--   .. .. .. ..      <- lane B
--   R1 R2 R3 R4      <- chests, right wall
--   ^
--   home
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

-- How many blocks long the hallway is (one chest slot per block)
local AISLE_LENGTH = 10

-- Path from home to sitting in front of the upstairs dump chest.
--   f = forward   b = back   u = up   d = down
--   l = turn left r = turn right
-- The way back down is this path reversed automatically.
local PATH_TO_DUMP = "b b u u u u u f"

-- Chest for anything it can't place. nil = use the first empty
-- chest it finds while scanning.
local OVERFLOW = nil

-- Slot kept for coal so fuel never gets sorted away
local FUEL_SLOT = 16

-- Break blocks that get in the way (needs a pickaxe equipped)
local DIG = false

local DB_FILE = "sorter_db.txt"

-- =========================================================
-- Movement
-- =========================================================

local function moveWith(move, dig, detect)
    for _ = 1, 20 do
        if move() then return true end

        if DIG and detect() then
            dig()
        else
            sleep(0.4)     -- probably a mob in the way
        end
    end

    error("Stuck while moving. Clear the path and reboot me.")
end

local STEPS = {
    f = function() moveWith(turtle.forward, turtle.dig, turtle.detect) end,
    u = function() moveWith(turtle.up, turtle.digUp, turtle.detectUp) end,
    d = function() moveWith(turtle.down, turtle.digDown, turtle.detectDown) end,
    b = function()
        if not turtle.back() then
            turtle.turnLeft() turtle.turnLeft()
            moveWith(turtle.forward, turtle.dig, turtle.detect)
            turtle.turnLeft() turtle.turnLeft()
        end
    end,
    l = turtle.turnLeft,
    r = turtle.turnRight,
}

local function step(s)
    STEPS[s]()
end

local function runPath(path)
    for i = 1, #path do
        local c = path:sub(i, i)
        if STEPS[c] then step(c) end
    end
end

local OPPOSITE = { f = "b", b = "f", u = "d", d = "u", l = "r", r = "l" }

local function reversePath(path)
    local out = {}

    for i = #path, 1, -1 do
        local c = path:sub(i, i)
        if OPPOSITE[c] then out[#out + 1] = OPPOSITE[c] end
    end

    return table.concat(out)
end

local function pathCost(path)
    local n = 0

    for i = 1, #path do
        local c = path:sub(i, i)
        if c == "f" or c == "b" or c == "u" or c == "d" then n = n + 1 end
    end

    return n
end

-- =========================================================
-- Fuel
-- =========================================================

local function tripCost()
    return AISLE_LENGTH * 2 + 4 + pathCost(PATH_TO_DUMP) * 2 + 10
end

local function refuel()
    if turtle.getFuelLevel() == "unlimited" then return end

    while turtle.getFuelLevel() < tripCost() * 2 do
        turtle.select(FUEL_SLOT)

        if not turtle.refuel(1) then
            print("Out of fuel. Put coal in slot " .. FUEL_SLOT .. ".")
            sleep(10)
        end
    end
end

-- =========================================================
-- Knowledge base
-- =========================================================

local db = { chests = {}, overflow = OVERFLOW }

local function saveDB()
    local f = fs.open(DB_FILE, "w")
    f.write(textutils.serialize(db))
    f.close()
end

local function loadDB()
    if not fs.exists(DB_FILE) then return false end

    local f = fs.open(DB_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()

    if type(data) == "table" and data.chests then
        db = data
        return true
    end

    return false
end

local function chestInFront()
    local p = peripheral.wrap("front")

    if p and p.list then return p end
    return nil
end

-- What does this chest hold, and what kinds of thing are they?
local function profileChest(inv)
    local profile = { names = {}, tags = {}, empty = true }
    local sampled = 0

    for slot, item in pairs(inv.list()) do
        profile.empty = false
        profile.names[item.name] = true

        -- Tags are what let it place items it has never seen before
        if sampled < 12 then
            local detail = inv.getItemDetail(slot)

            if detail and detail.tags then
                for tag in pairs(detail.tags) do
                    profile.tags[tag] = (profile.tags[tag] or 0) + 1
                end
            end

            sampled = sampled + 1
        end
    end

    return profile
end

-- Best home for an item: exact match wins, then shared tags
local function pickChest(detail)
    local best, bestScore = nil, 0

    for id, chest in pairs(db.chests) do
        local score = 0

        if chest.names[detail.name] then
            score = 1000
        end

        if detail.tags then
            for tag in pairs(detail.tags) do
                score = score + (chest.tags[tag] or 0)
            end
        end

        if score > bestScore then
            best, bestScore = id, score
        end
    end

    return best
end

-- =========================================================
-- The hallway route
--
-- visit(id) is called once per chest slot, with the turtle
-- parked and facing that chest. Ends back at home.
-- =========================================================

local function patrol(visit)
    -- Down lane A, checking the left wall
    for i = 1, AISLE_LENGTH do
        step("f")
        step("l")
        visit("L" .. i)
        step("r")
    end

    -- Cross into lane B and turn around
    step("r") step("f") step("r")

    -- Back down lane B, checking the right wall
    for i = AISLE_LENGTH, 1, -1 do
        step("l")
        visit("R" .. i)
        step("r")
        step("f")
    end

    -- Back into lane A, facing down the hallway again
    step("r") step("f") step("r")
end

-- =========================================================
-- Scan trip: learn the hallway
-- =========================================================

local function scan()
    print("Scanning the hallway...")

    db.chests = {}
    db.overflow = OVERFLOW

    patrol(function(id)
        local inv = chestInFront()

        if inv then
            local profile = profileChest(inv)
            db.chests[id] = profile

            if profile.empty and not db.overflow then
                db.overflow = id
            end

            print(id .. ": " .. (profile.empty and "empty" or "learned"))
        end
    end)

    saveDB()

    local n = 0
    for _ in pairs(db.chests) do n = n + 1 end

    print("Found " .. n .. " chests. Overflow: " .. tostring(db.overflow))
end

-- =========================================================
-- Work trip
-- =========================================================

local function collectFromDump()
    local got = false

    for slot = 1, 15 do
        if slot ~= FUEL_SLOT and turtle.getItemCount(slot) == 0 then
            turtle.select(slot)

            if turtle.suck() then
                got = true
            else
                break              -- dump chest is empty
            end
        end
    end

    return got
end

local function planLoad()
    local targets = {}

    for slot = 1, 16 do
        if slot ~= FUEL_SLOT and turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot, true)

            if detail then
                targets[slot] = pickChest(detail) or db.overflow
            end
        end
    end

    return targets
end

local function deliver(targets)
    patrol(function(id)
        local inv = chestInFront()
        if not inv then
            db.chests[id] = nil
            return
        end

        -- Drop off anything bound for this chest
        for slot = 1, 16 do
            if targets[slot] == id and turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                turtle.drop()

                -- Chest was full: send the rest to overflow
                if turtle.getItemCount(slot) > 0 then
                    targets[slot] = db.overflow
                end
            end
        end

        -- Re-learn this chest for next trip, so moving items
        -- around is all it takes to change the categories
        db.chests[id] = profileChest(inv)
    end)

    saveDB()
end

-- =========================================================
-- Main loop
-- =========================================================

local DOWN_PATH = reversePath(PATH_TO_DUMP)

if not loadDB() then
    scan()
else
    print("Loaded knowledge of the hallway.")
end

while true do
    refuel()

    runPath(PATH_TO_DUMP)
    local got = collectFromDump()
    runPath(DOWN_PATH)

    if got then
        deliver(planLoad())
    else
        print("Nothing to sort.")
        sleep(15)
    end
end

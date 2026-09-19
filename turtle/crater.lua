-- =========================================================
-- Chest crater
--
--   A crafting turtle that first finds the chests in a room,
--   then shuttles between them crafting potatoes, wheat and
--   corn into crates (9 -> 1) so the chests stop filling up.
--   It remembers the chests, what was in each one, and which
--   9-of-a-kind recipes work, and when its fuel runs low it
--   helps itself to coal -- or crafts coal essence into coal
--   -- from any chest that has some.
--
-- Setup:
--   * A crafting turtle (crafting table upgrade, either side).
--   * It works with an EMPTY inventory: turtle.craft() refuses
--     to run unless every slot outside the 3x3 grid is clear,
--     so it can't carry a coal stack around. Fuel you leave in
--     it gets burned at startup; anything else gets put away in
--     the chests (with its own kind where possible).
--   * Put it on the floor of the room. Wherever it starts is
--     "home": it explores every floor cell it can reach within
--     SEARCH_RADIUS blocks of home, on this level, and notes
--     every inventory it sees beside it (chests, Sophisticated
--     Storage, barrels...). Doorways inside that radius are
--     explored too, so keep the radius smaller than the room
--     if there's a corridor of chests next door.
--
-- Phases:
--   1. Discovering chests -- one-time walk of the room (the
--      turtle turns to look at all four sides of every cell).
--   2. Work loop -- visit each chest in turn, crate what's
--      there, rest, repeat. With two chests that's a shuttle.
--
-- Usage:
--   crater            discover chests (first run), then work forever
--   crater map        print the chests it knows, without moving
--   crater reset      forget everything; rediscover on the next run
--   Q (in the terminal) finish this round, go home, stop.
--
-- Memory: crater_db.txt on the turtle -- the room map, the
-- chest list, the turtle's own position, and the learned
-- recipes. Its position is saved around every move, so a reboot
-- resumes in place. If it was stopped mid-move, or what's around
-- it doesn't match the map (you carried it somewhere, the room
-- changed), or it can't reach a chest or home, it rediscovers
-- the room from wherever it is -- no reset needed. `reset` is
-- only for forgetting learned recipes.
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

-- Item names (the part after the colon, exactly) to crate.
-- "potato" matches minecraft:potato but not baked_potato;
-- "corn" matches croptopia:corn but not corn_seeds or popcorn.
local TARGETS = { "potato", "wheat", "corn" }

-- Leave this many loose items of each target in the chest
local KEEP_LOOSE = 0

-- How far from home (in blocks, each axis) discovery may wander
local SEARCH_RADIUS = 8

-- Seconds to rest at home between rounds
local ROUND_INTERVAL = 120

-- Fuel. FUEL_ITEMS burn as they are. CRAFT_FUEL_ITEMS get crafted
-- first and the result burned: coal essence (Mystical Agriculture)
-- into coal, and a coal block into 9 coal if the block itself
-- won't burn. Fuel is only taken from a chest when the level drops
-- under FUEL_LOW, and only enough to get back up to FUEL_TARGET.
local FUEL_ITEMS = { "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block" }
local CRAFT_FUEL_ITEMS = { "mysticalagriculture:coal_essence", "minecraft:coal_block" }
local FUEL_LOW = 500
local FUEL_TARGET = 3000

local DB_FILE = "crater_db.txt"

-- =========================================================
-- Inventory layout
--
-- turtle.craft() insists that every slot outside the 3x3 grid
-- is empty, which is why nothing lives in the turtle for long:
-- whatever it pulls out of a chest goes straight back.
-- =========================================================

local GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }   -- the crafting grid
local RESULT_SLOT = 4                          -- craft output lands here
local PARK_SLOTS = { 8, 12, 13, 14, 15, 16 }   -- chest stacks moved out of the way

-- Grid shapes to try for craftable fuel, smallest first: one coal
-- block alone gives 9 coal; Mystical Agriculture's essence recipes
-- differ between versions (hollow ring or full grid). The first
-- shape that crafts into something that burns wins and is
-- remembered.
local PATTERNS = {
    { name = "single", slots = { 1 } },
    { name = "square", slots = { 1, 2, 5, 6 } },
    { name = "ring",   slots = { 1, 2, 3, 5, 7, 9, 10, 11 } },
    { name = "full",   slots = { 1, 2, 3, 5, 6, 7, 9, 10, 11 } },
}

local function patternSlots(name)
    for _, p in ipairs(PATTERNS) do
        if p.name == name then return p.slots end
    end
    return GRID
end

local function toSet(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

-- =========================================================
-- State
-- =========================================================

-- pos               = where the turtle is: x, z and heading h
--                     (0 = the way it faced at home; right turn = +1)
-- cells["x,z"]      = "open" | "block" | "chest"
-- chests[i]         = { x, z, stand = {x, z}, face = h, items = { name = count }, fuel = bool }
-- recipes[item]     = { result = name } or false (tested, no recipe)
-- fuelRecipes[item] = { pattern, result, count, value } or false
local db = {
    pos = { x = 0, z = 0, h = 0 },
    cells = {},
    chests = {},
    recipes = {},
    fuelRecipes = {},
    discovered = false,
}

local stopRequested = false
local stats = { crates = 0 }

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

    if type(data) == "table" and data.pos and data.cells then
        db = data
        db.chests = db.chests or {}
        db.recipes = db.recipes or {}
        db.fuelRecipes = db.fuelRecipes or {}
        return true
    end

    return false
end

-- =========================================================
-- Inventory helpers
-- =========================================================

local function inventoryEmpty()
    for s = 1, 16 do
        if turtle.getItemCount(s) > 0 then return false end
    end
    return true
end

local function slotsEmptyExcept(keep)
    local ok = toSet(keep)
    for s = 1, 16 do
        if not ok[s] and turtle.getItemCount(s) > 0 then return false end
    end
    return true
end

-- Burn any fuel someone dropped into the turtle by hand
local function eatLooseFuel()
    if turtle.getFuelLevel() == "unlimited" then return end

    for s = 1, 16 do
        if turtle.getItemCount(s) > 0 then
            turtle.select(s)
            if turtle.refuel(0) then turtle.refuel() end
        end
    end
end

-- =========================================================
-- Movement, with dead reckoning
-- =========================================================

local DX = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local DZ = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }

local function key(x, z)
    return x .. "," .. z
end

local function ahead()
    return db.pos.x + DX[db.pos.h], db.pos.z + DZ[db.pos.h]
end

-- Every motion is bracketed by a "moving" flag in the save file.
-- If the program dies mid-motion (Ctrl+T, chunk unload) the flag
-- is still set at the next start, which means the saved position
-- can't be trusted and the room gets rediscovered from wherever
-- the turtle actually is.
local function turnRight()
    db.moving = true
    saveDB()
    turtle.turnRight()
    db.pos.h = (db.pos.h + 1) % 4
    db.moving = nil
    saveDB()
end

local function turnLeft()
    db.moving = true
    saveDB()
    turtle.turnLeft()
    db.pos.h = (db.pos.h + 3) % 4
    db.moving = nil
    saveDB()
end

local function face(h)
    local d = (h - db.pos.h) % 4

    if d == 1 then
        turnRight()
    elseif d == 2 then
        turnRight()
        turnRight()
    elseif d == 3 then
        turnLeft()
    end
end

local function waitForAnyFuel()
    if turtle.getFuelLevel() == "unlimited" then return end

    while turtle.getFuelLevel() < 1 do
        eatLooseFuel()

        if turtle.getFuelLevel() < 1 then
            print("Out of fuel. Put coal in any of my slots.")
            sleep(10)
        end
    end
end

-- One step forward. False if a block is in the way; waits out
-- anything that isn't a block (a mob, usually).
local function forward()
    waitForAnyFuel()
    local warned = false

    while true do
        db.moving = true
        saveDB()
        local moved = turtle.forward()

        if moved then
            local nx, nz = ahead()
            db.pos.x, db.pos.z = nx, nz
        end

        db.moving = nil
        saveDB()

        if moved then return true end
        if turtle.detect() then return false end

        if not warned then
            print("Something is in my way at (" .. db.pos.x .. "," .. db.pos.z .. "); waiting for it to move.")
            warned = true
        end

        sleep(1)
    end
end

-- =========================================================
-- Talking to the chest in front
-- =========================================================

local function chestAt(side)
    local p = peripheral.wrap(side)

    if p and p.list then return p end
    return nil
end

-- name -> count of everything in the chest. Stacks with NBT are
-- skipped: they're rarely food and suck() can't tell them apart.
-- With details, also one getItemDetail() per distinct item for
-- its stack size.
local function summarize(chest, withDetails)
    local counts, details = {}, {}

    for slot, item in pairs(chest.list()) do
        if not item.nbt then
            counts[item.name] = (counts[item.name] or 0) + item.count

            if withDetails and not details[item.name] then
                local d = chest.getItemDetail(slot)
                details[item.name] = { maxCount = (d and d.maxCount) or 64 }
            end
        end
    end

    return counts, details
end

-- How many of an item the chest in front holds right now
local function countOf(chest, name)
    local n = 0

    for _, it in pairs(chest.list()) do
        if it.name == name and not it.nbt then n = n + it.count end
    end

    return n
end

-- Move whatever stack the chest considers "first" into a spare
-- turtle slot so the next suck() can reach the stack behind it.
local function park()
    for _, s in ipairs(PARK_SLOTS) do
        if turtle.getItemCount(s) == 0 then
            turtle.select(s)
            return turtle.suck(64)
        end
    end

    return false
end

-- Put one turtle slot into the chest in front. True if it emptied.
local function dropSlot(s)
    if turtle.getItemCount(s) == 0 then return true end

    turtle.select(s)

    for _ = 1, 3 do
        turtle.drop()
        if turtle.getItemCount(s) == 0 then return true end
        sleep(0.2)
    end

    return false
end

local function unpark()
    local ok = true

    for _, s in ipairs(PARK_SLOTS) do
        if not dropSlot(s) then ok = false end
    end

    return ok
end

-- Everything in the turtle goes back into the chest in front.
local function returnAll()
    local ok = true

    for s = 1, 16 do
        if not dropSlot(s) then ok = false end
    end

    if not ok then
        print("  this chest won't take some items back; I'll try the other chests")
    end

    return ok
end

-- Pull up to `want` of `name` from the chest in front into turtle
-- slot `slot` (empty, or already holding `name`). Returns how many
-- arrived.
--
-- turtle.suck() only ever takes whatever the chest considers its
-- first stack, so the chest is shuffled until that stack is the
-- one wanted: the item is pushed into slot 1 when slot 1 is free,
-- otherwise whatever sits there is parked in the turtle and put
-- back by unpark()/returnAll() later.
local function pull(chest, name, want, slot)
    local got = 0

    while got < want do
        local list = chest.list()
        local first, src

        for s, it in pairs(list) do
            if not first or s < first then first = s end

            if it.name == name and not it.nbt and (not src or s < src) then
                src = s
            end
        end

        if not src then break end

        if first == src then
            turtle.select(slot)
            local before = turtle.getItemCount(slot)
            turtle.suck(want - got)

            local d = turtle.getItemDetail(slot)
            if d and d.name ~= name then       -- chest changed under us
                turtle.drop()
                break
            end

            local n = turtle.getItemCount(slot) - before
            if n <= 0 then break end
            got = got + n
        else
            local moved = 0

            if first > 1 then    -- slot 1 is free: bring the item forward
                local ok, n = pcall(chest.pushItems, "front", src, want - got, 1)
                if ok and type(n) == "number" then moved = n end
            end

            if moved == 0 and not park() then break end
        end
    end

    return got
end

-- Whatever is in the turtle that isn't the ingredient: the craft
-- output, with its total count and the first slot it's in.
local function findResult(ingredient)
    local rname, total, slot = nil, 0, nil

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d and d.name ~= ingredient then
            rname = rname or d.name
            slot = slot or s
            if d.name == rname then total = total + d.count end
        end
    end

    if rname then return { name = rname, count = total, slot = slot } end
    return nil
end

-- =========================================================
-- Crating
-- =========================================================

local function isTarget(name)
    local path = name:match("^[^:]+:(.+)$") or name

    for _, t in ipairs(TARGETS) do
        if path == t then return true end
    end

    return false
end

-- Try 9 of the item once and see what comes out. The answer is
-- remembered either way, so each item is only ever tested once.
local function learnCrate(chest, name)
    local loaded = true

    for _, s in ipairs(GRID) do
        if pull(chest, name, 1, s) < 1 then
            loaded = false
            break
        end
    end

    local tested, recipe = false, false

    if loaded and unpark() and slotsEmptyExcept(GRID) then
        tested = true
        turtle.select(RESULT_SLOT)
        local ok = turtle.craft(1)
        local result = findResult(name)

        if ok and result and result.count == 1 then
            recipe = { result = result.name }
            print("  learned: 9 x " .. name .. " -> " .. result.name)
        else
            print("  " .. name .. " doesn't crate; skipping it from now on")
        end
    end

    returnAll()

    if tested then
        db.recipes[name] = recipe
        saveDB()
    end

    return recipe
end

-- Crate as many 9-batches as the chest can spare. Returns crates made.
local function crate(chest, name, maxCount)
    local made = 0

    while true do
        -- Re-count every round: the test craft and earlier rounds
        -- have already taken some, and a full grid cell count that
        -- the chest can't supply would leave a cell empty and the
        -- craft would fail outright.
        local avail = countOf(chest, name)
        local batches = math.floor((avail - KEEP_LOOSE) / 9)
        if batches < 1 then break end

        local n = math.min(batches, maxCount, 64)

        for _, s in ipairs(GRID) do
            if pull(chest, name, n, s) < n then break end
        end

        local crafted = 0

        if unpark() and slotsEmptyExcept(GRID) then
            turtle.select(RESULT_SLOT)
            turtle.craft(n)            -- crafts as many as the grid allows
            local result = findResult(name)
            crafted = result and result.count or 0
        end

        returnAll()

        if crafted == 0 then break end
        made = made + crafted
    end

    return made
end

-- =========================================================
-- Fuel
-- =========================================================

local function fuelLow()
    local level = turtle.getFuelLevel()
    return level ~= "unlimited" and level < FUEL_LOW
end

local function fuelTarget()
    return math.min(FUEL_TARGET, turtle.getFuelLimit())
end

local function hasFuel(counts)
    for _, n in ipairs(FUEL_ITEMS) do
        if counts[n] then return true end
    end

    for _, n in ipairs(CRAFT_FUEL_ITEMS) do
        if counts[n] and db.fuelRecipes[n] ~= false then return true end
    end

    return false
end

-- Coal and friends: burn one to learn its value, then take just
-- enough to reach the target.
local function refuelPlain(chest, name)
    local target = fuelTarget()

    if pull(chest, name, 1, RESULT_SLOT) >= 1 then
        turtle.select(RESULT_SLOT)
        local before = turtle.getFuelLevel()
        local value = turtle.refuel(1) and (turtle.getFuelLevel() - before) or 0

        while value > 0 and turtle.getFuelLevel() < target do
            local need = math.ceil((target - turtle.getFuelLevel()) / value)

            if pull(chest, name, math.min(need, 64), RESULT_SLOT) < 1 then break end

            turtle.select(RESULT_SLOT)
            turtle.refuel()
        end
    end

    returnAll()
end

-- Work out how the essence crafts: try each grid shape with one
-- essence per cell, and keep the first whose output burns.
local function learnEssence(chest, name)
    local untested = false

    for _, p in ipairs(PATTERNS) do
        local loaded = true

        for _, s in ipairs(p.slots) do
            if pull(chest, name, 1, s) < 1 then
                loaded = false
                break
            end
        end

        if not loaded then
            -- Not enough of the item for this shape right now.
            -- Try the smaller shapes; don't record a verdict.
            returnAll()
            untested = true
        elseif unpark() and slotsEmptyExcept(p.slots) then
            turtle.select(RESULT_SLOT)

            if turtle.craft(1) then
                local result = findResult(name)

                if result then
                    turtle.select(result.slot)
                    local before = turtle.getFuelLevel()
                    local value = turtle.refuel(1) and (turtle.getFuelLevel() - before) or 0
                    if value > 0 then turtle.refuel() end     -- the rest of the test batch too
                    returnAll()

                    if value > 0 then
                        local r = { pattern = p.name, result = result.name,
                                    count = result.count, value = value }
                        db.fuelRecipes[name] = r
                        saveDB()
                        print(string.format("  learned: %d x %s (%s) -> %d x %s, %d fuel each",
                              #p.slots, name, p.name, result.count, result.name, value))
                        return r
                    end

                    print("  " .. name .. " crafts into " .. result.name .. ", which doesn't burn")
                    db.fuelRecipes[name] = false
                    saveDB()
                    return false
                end
            end
        end

        if loaded then returnAll() end
    end

    if untested then return nil end     -- some shapes couldn't be tried; ask again later

    print("  " .. name .. " doesn't craft into fuel in any shape I know")
    db.fuelRecipes[name] = false
    saveDB()
    return false
end

local function refuelEssence(chest, name, r)
    local target = fuelTarget()
    local slots = patternSlots(r.pattern)

    while turtle.getFuelLevel() < target do
        local perCraft = r.count * r.value
        local crafts = math.ceil((target - turtle.getFuelLevel()) / perCraft)
        local n = math.min(crafts, math.max(1, math.floor(64 / r.count)), 64)

        -- Never ask for more than the chest has: an empty cell in the
        -- shape would fail the whole craft instead of crafting fewer.
        n = math.min(n, math.floor(countOf(chest, name) / #slots))
        if n < 1 then break end

        local short = false

        for _, s in ipairs(slots) do
            if pull(chest, name, n, s) < n then short = true end
        end

        local burned = 0

        if unpark() and slotsEmptyExcept(slots) then
            turtle.select(RESULT_SLOT)
            turtle.craft(n)

            for s = 1, 16 do
                local d = turtle.getItemDetail(s)

                if d and d.name == r.result then
                    turtle.select(s)
                    local before = turtle.getFuelLevel()
                    turtle.refuel()
                    burned = burned + (turtle.getFuelLevel() - before)
                end
            end
        end

        returnAll()

        if burned == 0 or short then break end
    end
end

local function refuelFrom(chest, counts)
    local before = turtle.getFuelLevel()

    for _, name in ipairs(FUEL_ITEMS) do
        if counts[name] and turtle.getFuelLevel() < fuelTarget() then
            refuelPlain(chest, name)
        end
    end

    for _, name in ipairs(CRAFT_FUEL_ITEMS) do
        if counts[name] and turtle.getFuelLevel() < fuelTarget() then
            local r = db.fuelRecipes[name]
            if r == nil then r = learnEssence(chest, name) end
            if r then refuelEssence(chest, name, r) end
        end
    end

    local gained = turtle.getFuelLevel() - before

    if gained > 0 then
        print(string.format("  refueled +%d (now %d)", gained, turtle.getFuelLevel()))
    end
end

-- =========================================================
-- Phase 1: discovering chests
--
-- Depth-first walk over every open floor cell within reach. At
-- each new cell the turtle turns a full circle and classifies
-- the four neighbours: chest, block, or open. The map it builds
-- is what the work loop later navigates over.
-- =========================================================

local function lookAround()
    for _ = 1, 4 do
        local nx, nz = ahead()
        local k = key(nx, nz)

        if not db.cells[k] then
            if chestAt("front") then
                db.cells[k] = "chest"
                db.chests[#db.chests + 1] = {
                    x = nx, z = nz,
                    stand = { x = db.pos.x, z = db.pos.z },
                    face = db.pos.h,
                    items = {}, fuel = false,
                }
                print("Found a chest at (" .. nx .. "," .. nz .. ")")
            elseif turtle.detect() then
                db.cells[k] = "block"
            else
                db.cells[k] = "open"
            end
        end

        turnRight()
    end
end

local function discover()
    print("Discovering chests within " .. SEARCH_RADIUS .. " blocks...")

    -- Wherever the turtle is right now becomes home
    db.pos = { x = 0, z = 0, h = 0 }
    db.moving = nil
    db.discovered = false
    db.cells = {}
    db.chests = {}
    db.cells[key(0, 0)] = "open"

    local visited = {}

    local function dfs()
        visited[key(db.pos.x, db.pos.z)] = true
        lookAround()

        for d = 0, 3 do
            local nx, nz = db.pos.x + DX[d], db.pos.z + DZ[d]
            local k = key(nx, nz)

            if db.cells[k] == "open" and not visited[k]
               and math.abs(nx) <= SEARCH_RADIUS and math.abs(nz) <= SEARCH_RADIUS then
                face(d)

                if forward() then
                    dfs()
                    face((d + 2) % 4)

                    if not forward() then
                        error("Couldn't step back while exploring. Put me at home and run: crater reset")
                    end
                else
                    db.cells[k] = "block"      -- something's there after all
                end
            end
        end
    end

    dfs()
    face(0)

    db.discovered = true
    saveDB()

    print("Discovery done: " .. #db.chests .. " chest(s).")
end

-- =========================================================
-- Navigation over the discovered map
-- =========================================================

-- Breadth-first search over open cells; returns a list of headings.
-- `avoid` is a set of cells found blocked on this trip; it's kept
-- out of the saved map on purpose, because a step that fails when
-- the turtle isn't where it thinks it is would otherwise poison
-- the map for good.
local function pathTo(tx, tz, avoid)
    local start = key(db.pos.x, db.pos.z)
    local goal = key(tx, tz)

    if start == goal then return {} end

    local prev = { [start] = false }
    local queue = { { db.pos.x, db.pos.z } }
    local qi = 1

    while qi <= #queue do
        local cx, cz = queue[qi][1], queue[qi][2]
        qi = qi + 1

        for d = 0, 3 do
            local nx, nz = cx + DX[d], cz + DZ[d]
            local k = key(nx, nz)

            if prev[k] == nil and db.cells[k] == "open" and not avoid[k] then
                prev[k] = { key(cx, cz), d }

                if k == goal then
                    local path, cur = {}, k

                    while prev[cur] do
                        table.insert(path, 1, prev[cur][2])
                        cur = prev[cur][1]
                    end

                    return path
                end

                queue[#queue + 1] = { nx, nz }
            end
        end
    end

    return nil
end

-- Walk to a cell over the map. False if it can't get there, which
-- means either the room changed or the turtle isn't where it
-- thinks it is; the caller then rediscovers.
local function goTo(tx, tz)
    local avoid = {}

    for _ = 1, 5 do
        local path = pathTo(tx, tz, avoid)
        if not path then return false end

        local blocked = false

        for _, d in ipairs(path) do
            face(d)

            if not forward() then
                local bx, bz = ahead()
                avoid[key(bx, bz)] = true
                blocked = true
                break
            end
        end

        if not blocked then return true end
    end

    return false
end

-- After a restart: does what's around the turtle agree with the
-- map at its saved position? Only cells the map knows are compared.
local function surroundingsMatch()
    for _ = 1, 4 do
        local nx, nz = ahead()
        local expected = db.cells[key(nx, nz)]

        if expected then
            local observed = "open"
            if chestAt("front") then
                observed = "chest"
            elseif turtle.detect() then
                observed = "block"
            end

            if observed ~= expected then return false end
        end

        turnRight()
    end

    return true
end

-- =========================================================
-- Phase 2: one chest visit
-- =========================================================

-- Put away what the turtle is carrying: into this chest when the
-- chest already holds that kind of item, or all of it when
-- `anything` is set (the last chest of the round).
local function stash(chest, counts, anything)
    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d and (anything or counts[d.name]) then
            if dropSlot(s) then
                print("  put away " .. d.count .. " x " .. (d.name:gsub("^[^:]+:", "")))
            end
        end
    end
end

local function carrying()
    local parts = {}

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d then parts[#parts + 1] = d.count .. " x " .. (d.name:gsub("^[^:]+:", "")) end
    end

    return table.concat(parts, ", ")
end

-- True when done; false plus a reason when the turtle is lost.
local function visitChest(c, isLast)
    local label = "chest (" .. c.x .. "," .. c.z .. ")"

    if not goTo(c.stand.x, c.stand.z) then
        return false, "no way to " .. label
    end

    face(c.face)

    local chest = chestAt("front")

    if not chest then
        return false, label .. " isn't where I expected"
    end

    local counts, details = summarize(chest, true)
    c.items = counts
    c.fuel = hasFuel(counts)
    saveDB()

    -- Whatever it's carrying (things you left in it, crates a chest
    -- refused) gets put away before any crafting, since crafting
    -- needs every slot clear.
    if not inventoryEmpty() then
        stash(chest, counts, isLast)
        counts, details = summarize(chest, true)
    end

    if not inventoryEmpty() then
        print(label .. ": still carrying " .. carrying() .. "; I'll put it away at the next chest")
        return true
    end

    if c.fuel and fuelLow() then
        refuelFrom(chest, counts)
    end

    local names = {}
    for name in pairs(counts) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        local recipe = db.recipes[name]

        if recipe ~= false and isTarget(name) and counts[name] >= 9 + KEEP_LOOSE then
            if recipe == nil then recipe = learnCrate(chest, name) end

            if recipe then
                local made = crate(chest, name, details[name].maxCount)

                if made > 0 then
                    stats.crates = stats.crates + made
                    print(string.format("%s: %d x %s -> %d x %s",
                          label, made * 9, name, made, recipe.result))
                end
            end
        end
    end

    -- Remember what's there now, after crating and refuelling
    c.items = summarize(chest, false)
    c.fuel = hasFuel(c.items)
    saveDB()

    return true
end

-- =========================================================
-- Map printout
-- =========================================================

local function printMap()
    if #db.chests == 0 then
        print("No chests known yet. Run `crater` to discover them.")
        return
    end

    for i, c in ipairs(db.chests) do
        local names = {}
        for name in pairs(c.items) do names[#names + 1] = name end
        table.sort(names, function(a, b) return c.items[a] > c.items[b] end)

        local parts = {}
        for j = 1, math.min(#names, 4) do
            local short = (names[j]:gsub("^[^:]+:", ""))
            parts[#parts + 1] = short .. " x" .. c.items[names[j]]
        end
        if #names > 4 then parts[#parts + 1] = "+" .. (#names - 4) .. " more" end

        print(string.format("%d. (%d,%d)%s: %s", i, c.x, c.z, c.fuel and " [fuel]" or "",
              #parts > 0 and table.concat(parts, ", ") or "empty / not visited yet"))
    end

    print("Home is (0,0); I'm at (" .. db.pos.x .. "," .. db.pos.z .. ").")
end

-- =========================================================
-- Main
-- =========================================================

local args = { ... }

if args[1] == "reset" then
    if fs.exists(DB_FILE) then fs.delete(DB_FILE) end
    print("Forgot the map, the chests and the learned recipes.")
    return
end

loadDB()

if args[1] == "map" then
    printMap()
    return
end

if not turtle.craft then
    error("This turtle has no crafting table upgrade.")
end

-- Burn whatever fuel was left in the turtle. Anything else it's
-- carrying gets put away in the chests as it goes.
eatLooseFuel()

if not inventoryEmpty() then
    print("Carrying " .. carrying() .. "; I'll put it away in the chests.")
end

local function run()
    if not db.discovered then
        discover()
    elseif db.moving then
        print("I was stopped mid-move last time, so my position is unsure. Rediscovering from here.")
        discover()
    elseif not surroundingsMatch() then
        print("The room doesn't match my map from where I stand. Rediscovering from here.")
        discover()
    else
        print("Loaded " .. #db.chests .. " chest(s); I'm at (" .. db.pos.x .. "," .. db.pos.z .. ").")
    end

    while not stopRequested do
        if #db.chests == 0 then
            print("No chests within " .. SEARCH_RADIUS .. " blocks of me. Move me (or the chests) and I'll look again in a minute.")
            for _ = 1, 60 do
                if stopRequested then return end
                sleep(1)
            end
            discover()
        else
            stats.crates = 0
            local lost = nil

            for i, c in ipairs(db.chests) do
                local ok, why = visitChest(c, i == #db.chests)

                if not ok then
                    lost = why
                    break
                end
            end

            if not lost and not goTo(0, 0) then
                lost = "no way home"
            end

            if lost then
                print("I'm lost (" .. lost .. "). Rediscovering the room from here.")
                discover()
            else
                face(0)

                if not inventoryEmpty() then
                    print("No chest will take " .. carrying() .. ". Please take it out of me.")
                end

                print(string.format("Round done: %d crate(s) made, fuel %s.",
                      stats.crates, tostring(turtle.getFuelLevel())))

                if stopRequested then break end

                for _ = 1, ROUND_INTERVAL do
                    if stopRequested then break end
                    sleep(1)
                end
            end
        end
    end
end

-- Q in the terminal asks for a clean stop at the end of the round.
-- The watcher never returns on its own (that would end waitForAny
-- and kill the run mid-move); it just raises the flag.
local function keyWatcher()
    while true do
        local _, k = os.pullEvent("key")

        if k == keys.q and not stopRequested then
            stopRequested = true
            print("Q pressed -- finishing this round, then stopping at home.")
        end
    end
end

print("Press Q to stop at home after the current round.")

parallel.waitForAny(run, keyWatcher)

print("Stopped at home.")

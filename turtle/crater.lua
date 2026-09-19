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
--     to run unless every slot outside the 3x3 grid is clear.
--     The one thing it carries is a small coal reserve in slot
--     16, which it drops into the chest it's working on and
--     takes back afterwards. Loose coal you leave in it becomes
--     that reserve; anything else (coal blocks included) gets
--     put away in the chests, with its own kind where possible.
--   * Lay a path of one kind of block (crystal sandstone, say)
--     past the chests and put the turtle on it. Wherever it
--     starts is "home": it explores every cell it can reach
--     that has that same block beneath it, within SEARCH_RADIUS
--     of home, and notes every inventory it sees beside the
--     path (chests, Sophisticated Storage, barrels...). Set
--     FOLLOW_FLOOR = false to let it roam any floor instead.
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
--   crater lock       keep exactly these chests; never re-map on its own
--   crater unlock     allow re-mapping again
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

-- Stay on the floor it starts on: discovery notes the block under
-- the home cell and only walks cells with that same block beneath
-- them. Lay a path of one block type (crystal sandstone, say) to the
-- chests and put the turtle on it. Set false to roam any floor.
local FOLLOW_FLOOR = true

-- How far from home (in blocks, each axis) discovery may wander
local SEARCH_RADIUS = 12

-- Blocks that look like inventories to the turtle but aren't
-- storage. Anything whose type contains one of these is ignored.
local NOT_A_CHEST = {
    "hopper", "dropper", "dispenser", "furnace", "smoker", "brewing",
    "composter", "jukebox", "lectern", "campfire", "turtle", "computer",
}

-- Seconds to rest at home between rounds
local ROUND_INTERVAL = 120

-- Fuel. The turtle keeps a small reserve of loose coal in its last
-- slot for emergencies (COAL_RESERVE pieces; charcoal counts too)
-- and otherwise lives off its fuel level. When that drops under
-- FUEL_LOW it burns coal from a chest, or crafts coal from coal
-- essence (Mystical Agriculture) or coal blocks, but only as much
-- as it takes to get back to FUEL_TARGET. Leftover coal tops up the
-- reserve and the rest goes back in the chest. Coal blocks are
-- never burned whole and never carried around.
local FUEL_ITEMS = { "minecraft:coal", "minecraft:charcoal" }
local CRAFT_FUEL_ITEMS = { "mysticalagriculture:coal_essence", "minecraft:coal_block" }
local COAL_RESERVE = 16
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
local RESERVE_SLOT = 16                        -- the coal reserve (dropped into the chest while crafting)

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

local GRID_SET = toSet(GRID)

-- =========================================================
-- State
-- =========================================================

-- pos               = where the turtle is: x, z and heading h
--                     (0 = the way it faced at home; right turn = +1)
-- floor             = block name under home, when FOLLOW_FLOOR
-- cells["x,z"]      = "open" | "block" | "chest" | "offpath" (walkable
--                     but not on the floor block, so never used)
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

local function isReserveItem(name)
    for _, n in ipairs(FUEL_ITEMS) do
        if n == name then return true end
    end
    return false
end

-- Pieces of coal in the reserve slot (0 if something else sits there)
local function reserveCount()
    local d = turtle.getItemDetail(RESERVE_SLOT)
    if d and isReserveItem(d.name) then return d.count end
    return 0
end

-- Loose coal anywhere in the turtle moves into the reserve slot, up
-- to COAL_RESERVE. What doesn't fit stays cargo and gets put away.
local function sortReserve()
    for s = 1, 15 do
        local d = turtle.getItemDetail(s)

        if d and isReserveItem(d.name) then
            local r = turtle.getItemDetail(RESERVE_SLOT)
            local have = r and r.count or 0

            if (not r or r.name == d.name) and have < COAL_RESERVE then
                turtle.select(s)
                turtle.transferTo(RESERVE_SLOT, COAL_RESERVE - have)
            end
        end
    end
end

-- Empty apart from the coal reserve?
local function cargoEmpty()
    for s = 1, 16 do
        if turtle.getItemCount(s) > 0 and not (s == RESERVE_SLOT and reserveCount() > 0) then
            return false
        end
    end
    return true
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

-- Fuel level hit zero: burn from the reserve, a piece at a time,
-- and failing that whatever fuel someone puts in.
local function waitForAnyFuel()
    if turtle.getFuelLevel() == "unlimited" then return end

    local warned = false

    while turtle.getFuelLevel() < 1 do
        if reserveCount() > 0 then
            turtle.select(RESERVE_SLOT)
            turtle.refuel(1)
        else
            for s = 1, 16 do
                if turtle.getItemCount(s) > 0 then
                    turtle.select(s)
                    if turtle.refuel(0) then turtle.refuel(1) end
                end
                if turtle.getFuelLevel() >= 1 then break end
            end

            if turtle.getFuelLevel() < 1 then
                if not warned then
                    print("Out of fuel and out of reserve coal. Put coal in any of my slots.")
                    warned = true
                end
                sleep(10)
            end
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
    if not (p and p.list) then return nil end

    -- Hoppers, furnaces and the like are inventories too; skip them
    local kind = tostring(peripheral.getType(side) or "")
    for _, bad in ipairs(NOT_A_CHEST) do
        if kind:find(bad, 1, true) then return nil end
    end

    return p
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
-- Any empty slot will do except the ones the current job needs
-- (`protect`); parked slots are remembered so unpark() can put
-- exactly those back.
local parked = {}

local function park(protect)
    for s = 1, 16 do
        if not protect[s] and not parked[s] and turtle.getItemCount(s) == 0 then
            turtle.select(s)

            if turtle.suck(64) then
                parked[s] = true
                return true
            end

            return false
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

    for s in pairs(parked) do
        if not dropSlot(s) then ok = false end     -- stays aboard as cargo
    end

    parked = {}
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
-- arrived. `protect` is the set of turtle slots this job is filling,
-- which parking must keep clear.
--
-- turtle.suck() only ever takes whatever the chest considers its
-- first stack, so the chest is shuffled until that stack is the
-- one wanted: the item is pushed into slot 1 when slot 1 is free,
-- otherwise whatever sits there is parked in the turtle and put
-- back by unpark()/returnAll() later.
local function pull(chest, name, want, slot, protect)
    local got = 0
    local stalls = 0

    -- Every pass must visibly change something (items arrived, the
    -- wanted stack moved to slot 1, or a stack got parked); a few
    -- passes without progress and it gives up rather than spin.
    while got < want and stalls < 4 do
        local list = chest.list()
        local first, src

        for s, it in pairs(list) do
            if not first or s < first then first = s end

            if it.name == name and not it.nbt and (not src or s < src) then
                src = s
            end
        end

        if not src then break end

        local progressed = false

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
            if n > 0 then
                got = got + n
                progressed = true
            end
        else
            if first > 1 then    -- slot 1 is free: bring the item forward
                pcall(chest.pushItems, "front", src, want - got, 1)

                -- Don't trust the reply; some chests say yes and do nothing
                local now = chest.list()[1]
                if now and now.name == name then progressed = true end
            end

            if not progressed and park(protect) then progressed = true end
        end

        if progressed then
            stalls = 0
        else
            stalls = stalls + 1
        end
    end

    if got < want and stalls >= 4 then
        print("  couldn't get " .. (name:gsub("^[^:]+:", "")) .. " out of this chest; leaving it")
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
        if pull(chest, name, 1, s, GRID_SET) < 1 then
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
            if pull(chest, name, n, s, GRID_SET) < n then break end
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
    local protect = { [RESULT_SLOT] = true }

    if pull(chest, name, 1, RESULT_SLOT, protect) >= 1 then
        turtle.select(RESULT_SLOT)
        local before = turtle.getFuelLevel()
        local value = turtle.refuel(1) and (turtle.getFuelLevel() - before) or 0

        while value > 0 and turtle.getFuelLevel() < target do
            local need = math.ceil((target - turtle.getFuelLevel()) / value)

            if pull(chest, name, math.min(need, 64), RESULT_SLOT, protect) < 1 then break end

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
        local protect = toSet(p.slots)

        for _, s in ipairs(p.slots) do
            if pull(chest, name, 1, s, protect) < 1 then
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
                    returnAll()      -- the rest of the test batch goes back; the reserve top-up may take it

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
    local protect = toSet(slots)

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
            if pull(chest, name, n, s, protect) < n then short = true end
        end

        local burned = 0

        if unpark() and slotsEmptyExcept(slots) then
            turtle.select(RESULT_SLOT)
            turtle.craft(n)

            -- Burn only what's needed; the rest goes back to the chest
            for s = 1, 16 do
                local d = turtle.getItemDetail(s)

                if d and d.name == r.result and turtle.getFuelLevel() < target then
                    turtle.select(s)
                    local before = turtle.getFuelLevel()
                    turtle.refuel(math.ceil((target - before) / r.value))
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

-- Is the block under the turtle the floor it's meant to stay on?
local function onFloor()
    if not db.floor then return true end

    local ok, data = turtle.inspectDown()
    return ok and data.name == db.floor
end

local function discover()
    -- Wherever the turtle is right now becomes home
    db.pos = { x = 0, z = 0, h = 0 }
    db.moving = nil
    db.discovered = false
    db.cells = {}
    db.chests = {}
    db.cells[key(0, 0)] = "open"
    db.floor = nil

    if FOLLOW_FLOOR then
        local ok, data = turtle.inspectDown()

        if ok then
            db.floor = data.name
            print("Discovering chests along the " .. (data.name:gsub("^[^:]+:", "")) ..
                  " floor, up to " .. SEARCH_RADIUS .. " blocks out...")
        else
            print("Nothing under me to follow; discovering chests within " .. SEARCH_RADIUS .. " blocks...")
        end
    else
        print("Discovering chests within " .. SEARCH_RADIUS .. " blocks...")
    end

    local visited = {}

    local function stepBack(d)
        face((d + 2) % 4)

        if not forward() then
            error("Couldn't step back while exploring. Put me at home and run: crater reset")
        end
    end

    local function dfs()
        visited[key(db.pos.x, db.pos.z)] = true
        lookAround()

        for d = 0, 3 do
            local nx, nz = db.pos.x + DX[d], db.pos.z + DZ[d]
            local k = key(nx, nz)

            if db.cells[k] == "open" and not visited[k]
               and math.abs(nx) <= SEARCH_RADIUS and math.abs(nz) <= SEARCH_RADIUS then
                face(d)

                if not forward() then
                    db.cells[k] = "block"      -- something's there after all
                elseif not onFloor() then
                    db.cells[k] = "offpath"    -- walkable, but not our floor: stay off it
                    stepBack(d)
                else
                    dfs()
                    stepBack(d)
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
    local match = true

    -- Always a full circle, so the turtle ends up facing the way it started
    for _ = 1, 4 do
        local nx, nz = ahead()
        local expected = db.cells[key(nx, nz)]

        if expected then
            if expected == "offpath" then expected = "open" end   -- looks open from here

            local observed = "open"
            if chestAt("front") then
                observed = "chest"
            elseif turtle.detect() then
                observed = "block"
            end

            if observed ~= expected then match = false end
        end

        turnRight()
    end

    return match
end

-- =========================================================
-- Phase 2: one chest visit
-- =========================================================

-- Put away what the turtle is carrying: into this chest when the
-- chest already holds that kind of item, or all of it when
-- `anything` is set (the last chest of the round). The coal
-- reserve always goes in, since crafting needs the slot clear;
-- topUpReserve() takes it back afterwards. Returns true if
-- anything was dropped.
local function stash(chest, counts, anything)
    local dropped = false

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d then
            local reserve = (s == RESERVE_SLOT and isReserveItem(d.name))

            if reserve or anything or counts[d.name] then
                if dropSlot(s) then
                    dropped = true
                    if not reserve then
                        print("  put away " .. d.count .. " x " .. (d.name:gsub("^[^:]+:", "")))
                    end
                end
            end
        end
    end

    return dropped
end

-- Refill the reserve slot with loose coal from the chest in front
local function topUpReserve(chest)
    local r = turtle.getItemDetail(RESERVE_SLOT)
    if r and not isReserveItem(r.name) then return end     -- cargo is sitting there

    for _, name in ipairs(FUEL_ITEMS) do
        local have = r and r.count or 0
        if have >= COAL_RESERVE then break end

        if (not r or r.name == name) and countOf(chest, name) > 0 then
            pull(chest, name, COAL_RESERVE - have, RESERVE_SLOT, { [RESERVE_SLOT] = true })
            r = turtle.getItemDetail(RESERVE_SLOT)
        end
    end

    unpark()
end

-- What's aboard, apart from the coal reserve
local function carrying()
    local parts = {}

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d and not (s == RESERVE_SLOT and isReserveItem(d.name)) then
            parts[#parts + 1] = d.count .. " x " .. (d.name:gsub("^[^:]+:", ""))
        end
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

    -- Whatever it's carrying (the coal reserve, things you left in
    -- it, crates a chest refused) gets put away before any crafting,
    -- since crafting needs every slot clear.
    if stash(chest, counts, isLast) then
        counts, details = summarize(chest, true)
    end

    if not inventoryEmpty() then
        print(label .. ": still carrying " .. carrying() .. "; I'll put it away at the next chest")
        topUpReserve(chest)
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

    topUpReserve(chest)

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

    print("Home is (0,0); I'm at (" .. db.pos.x .. "," .. db.pos.z .. ")." ..
          (db.locked and " Map is locked." or ""))
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

if args[1] == "lock" then
    if not db.discovered or #db.chests == 0 then
        print("Nothing to lock yet. Let me discover the chests first.")
        return
    end

    db.locked = true
    saveDB()
    print("Locked: I'll keep using these " .. #db.chests .. " chest(s) and won't re-map on my own.")
    print("Run `crater unlock` to let me map again.")
    return
end

if args[1] == "unlock" then
    db.locked = nil
    saveDB()
    print("Unlocked: I'll re-map whenever the room stops matching.")
    return
end

if not turtle.craft then
    error("This turtle has no crafting table upgrade.")
end

-- Loose coal aboard becomes the reserve; everything else it's
-- carrying gets put away in the chests as it goes.
sortReserve()

if not cargoEmpty() then
    print("Carrying " .. carrying() .. "; I'll put it away in the chests.")
end

local function rest(seconds)
    for _ = 1, seconds do
        if stopRequested then return end
        sleep(1)
    end
end

local function run()
    if not db.discovered then
        discover()
    elseif db.locked then
        -- A locked map is never rebuilt on its own. If the turtle can't
        -- recognise where it is, it needs a hand.
        if not surroundingsMatch() then
            print("The map is locked and I don't recognise where I am.")
            print("Put me back at home (where I started mapping, facing the same way) and reboot,")
            print("or run `crater unlock` to let me re-map.")
            return
        end

        print("Loaded " .. #db.chests .. " chest(s), map locked; I'm at (" .. db.pos.x .. "," .. db.pos.z .. ").")
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
            rest(60)
            if stopRequested then return end
            discover()
        else
            stats.crates = 0
            local lost = nil

            for i, c in ipairs(db.chests) do
                local ok, why = visitChest(c, i == #db.chests)

                if not ok then
                    if db.locked then
                        print("Skipping this round: " .. why .. ".")
                    else
                        lost = why
                        break
                    end
                end
            end

            if not lost and not goTo(0, 0) then
                lost = "no way home"
            end

            if lost and db.locked then
                print("Map is locked, so I won't re-map: " .. lost .. ". Trying again in a minute.")
                rest(60)
            elseif lost then
                print("I'm lost (" .. lost .. "). Rediscovering the room from here.")
                discover()
            else
                face(0)

                if not cargoEmpty() then
                    print("No chest will take " .. carrying() .. ". Please take it out of me.")
                end

                print(string.format("Round done: %d crate(s) made, fuel %s, %d coal in reserve.",
                      stats.crates, tostring(turtle.getFuelLevel()), reserveCount()))

                if stopRequested then break end
                rest(ROUND_INTERVAL)
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

print("Stopped.")

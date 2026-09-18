-- =========================================================
-- Chest-room crater
--
--   A crafting turtle that walks the inside edge of a
--   chest-lined room, looks into every chest on its way, and
--   packs bulk food down (9 of a kind -> 1 crate) so the
--   chests stop overflowing with carrots. While it does that
--   it builds a map of which chest holds what, and when its
--   fuel runs low it helps itself: coal straight from a
--   chest, or coal essence crafted into coal, whichever the
--   map says is on the route.
--
-- Setup:
--   * A crafting turtle (crafting table upgrade). Either side
--     works; with the table on the right it can read chests
--     without turning, so laps are a little quicker.
--   * Its inventory must be EMPTY. turtle.craft() refuses to
--     run unless every slot outside the 3x3 grid is clear, so
--     it can't carry a coal stack around. Any fuel you leave
--     in it gets burned at startup instead.
--   * Chests line the walls (Sophisticated Storage is fine).
--     Keep the lane along the walls clear: it turns at the
--     first block in its way, so a furnace or crafting table
--     standing in the lane looks like a corner to it.
--   * Park it in an inside corner cell, chest wall on its
--     LEFT, facing along that wall. That's home.
--
--         C C C C C C
--         C . . . T C     T faces down the page; the right-hand
--         C . . . . C     wall is on its left. It walks the ring
--         C C C C C C     clockwise and ends up back here.
--
-- Usage:
--   crater            lap the room forever (a lap, then a rest)
--   crater map        print what it remembers, without moving
--   crater reset      forget the map and the learned recipes
--   Q (in the terminal) finish the current lap, park at home, stop.
--
-- Memory: crater_db.txt on the turtle. It holds the chest map,
-- which 9-of-a-kind recipes worked (and which didn't, so each
-- item is only ever tested once), and how essence turns into
-- fuel. Chests are re-read every lap, so moving items around
-- needs no reset -- `reset` is only for after you've changed
-- what the script should think of as food or fuel.
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

-- Rows of chests up the wall. 1 = floor level only. With 2 it
-- laps the room at floor level, goes up one, and laps again.
local CHEST_ROWS = 1

-- Seconds to rest at home between laps
local LAP_INTERVAL = 600

-- Only crate an item when a chest holds at least MIN_STACKS full
-- stacks of it ("many stacks"), and always leave KEEP_STACKS
-- stacks loose so there's still some to grab by hand.
local MIN_STACKS = 3
local KEEP_STACKS = 1

-- What counts as food. An item qualifies if any of its tags
-- starts with one of these prefixes (vanilla, Farmer's Delight
-- and Croptopia all tag their crops this way) or if it is listed
-- in ALWAYS. NEVER wins over everything. Whether 9 of it actually
-- craft into something is worked out by trying, once.
local FOOD_TAGS = {
    "forge:crops", "forge:vegetables", "forge:fruits", "forge:grain",
    "forge:berries", "forge:nuts", "forge:mushrooms",
}
local ALWAYS = {
    ["minecraft:melon_slice"] = true,
    ["minecraft:dried_kelp"] = true,
}
local NEVER = {}

-- Fuel. FUEL_ITEMS burn as they are; ESSENCE_ITEMS get crafted
-- first (Mystical Agriculture). Fuel is only taken when the turtle
-- is running low, and only enough to get back up to FUEL_TARGET.
local FUEL_ITEMS = { "minecraft:coal", "minecraft:charcoal", "minecraft:coal_block" }
local ESSENCE_ITEMS = { "mysticalagriculture:coal_essence" }
local FUEL_TARGET = 3000

-- Longest wall it will walk before deciding it is lost
local MAX_WALL = 64

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

-- Grid shapes to try for essence -> fuel, in order. Mystical
-- Agriculture's essence recipes differ between versions, so the
-- first shape that crafts into something that burns wins and is
-- remembered.
local PATTERNS = {
    { name = "ring",   slots = { 1, 2, 3, 5, 7, 9, 10, 11 } },
    { name = "full",   slots = { 1, 2, 3, 5, 6, 7, 9, 10, 11 } },
    { name = "square", slots = { 1, 2, 5, 6 } },
    { name = "single", slots = { 1 } },
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

-- recipes[item]     = { result = name } or false (tested, no recipe)
-- fuelRecipes[item] = { pattern, result, count, value } or false
-- chests[key]       = { items = { name = count }, fuel = bool, dist = moves from home }
local db = { recipes = {}, fuelRecipes = {}, chests = {}, lapMoves = nil }

local stopRequested = false
local stats = { crates = 0, fuelCrafts = 0 }

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
-- Movement
-- =========================================================

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

local function moveWith(move, detect, what)
    waitForAnyFuel()

    for _ = 1, 40 do
        if move() then return end

        if detect() then
            error("A block appeared in my way (" .. what .. "). Clear it and reboot me.")
        end

        sleep(0.5)     -- probably a mob
    end

    error("Stuck moving " .. what .. ". Clear the path and reboot me.")
end

local function forward() moveWith(turtle.forward, turtle.detect, "forward") end
local function up() moveWith(turtle.up, turtle.detectUp, "up") end
local function down() moveWith(turtle.down, turtle.detectDown, "down") end

-- =========================================================
-- Talking to the chest in front
-- =========================================================

local function chestAt(side)
    local p = peripheral.wrap(side)

    if p and p.list then return p end
    return nil
end

-- The crafting table upgrade is itself a peripheral ("workbench"),
-- so if it sits on the left it hides whatever block is there. In
-- that case the turtle has to turn to look at each chest.
local function leftIsBlocked()
    local p = peripheral.wrap("left")
    return p ~= nil and p.craft ~= nil
end

local LEFT_BLOCKED = leftIsBlocked()

-- Is there a chest on the left? Ends facing it when there is,
-- facing forward as before when there isn't.
local function faceChestOnLeft()
    if not LEFT_BLOCKED then
        if chestAt("left") then
            turtle.turnLeft()
            return true
        end
        return false
    end

    turtle.turnLeft()
    if chestAt("front") then return true end
    turtle.turnRight()
    return false
end

-- name -> count of everything in the chest. Stacks with NBT are
-- skipped: they're rarely food and suck() can't tell them apart.
-- With details, also one getItemDetail() per distinct item for
-- its tags and stack size.
local function summarize(chest, withDetails)
    local counts, details = {}, {}

    for slot, item in pairs(chest.list()) do
        if not item.nbt then
            counts[item.name] = (counts[item.name] or 0) + item.count

            if withDetails and not details[item.name] then
                local d = chest.getItemDetail(slot)
                details[item.name] = {
                    maxCount = (d and d.maxCount) or 64,
                    tags = (d and d.tags) or {},
                }
            end
        end
    end

    return counts, details
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
        print("  the chest won't take some items back; unloading them at the next chest with room")
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

-- How many of an item the chest in front holds right now
local function countOf(chest, name)
    local n = 0

    for _, it in pairs(chest.list()) do
        if it.name == name and not it.nbt then n = n + it.count end
    end

    return n
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

local function isFood(name, detail)
    if NEVER[name] then return false end
    if ALWAYS[name] then return true end

    for tag in pairs(detail.tags) do
        for _, prefix in ipairs(FOOD_TAGS) do
            if tag:sub(1, #prefix) == prefix then return true end
        end
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
        local batches = math.floor((avail - KEEP_STACKS * maxCount) / 9)
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

local function lapCost()
    return (db.lapMoves or 200) + 20
end

local function fuelLow()
    local level = turtle.getFuelLevel()
    return level ~= "unlimited" and level < 2 * lapCost()
end

local function fuelTarget()
    return math.min(FUEL_TARGET, turtle.getFuelLimit())
end

local function hasFuel(counts)
    for _, n in ipairs(FUEL_ITEMS) do
        if counts[n] then return true end
    end

    for _, n in ipairs(ESSENCE_ITEMS) do
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
    for _, p in ipairs(PATTERNS) do
        local loaded = true

        for _, s in ipairs(p.slots) do
            if pull(chest, name, 1, s) < 1 then
                loaded = false
                break
            end
        end

        if not loaded then     -- can't test right now; don't remember anything
            returnAll()
            return nil
        end

        if unpark() and slotsEmptyExcept(p.slots) then
            turtle.select(RESULT_SLOT)

            if turtle.craft(1) then
                local result = findResult(name)

                if result then
                    turtle.select(result.slot)
                    local before = turtle.getFuelLevel()
                    local value = turtle.refuel(1) and (turtle.getFuelLevel() - before) or 0
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

        returnAll()
    end

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

        if burned == 0 then break end
        stats.fuelCrafts = stats.fuelCrafts + 1
        if short then break end
    end
end

local function refuelFrom(chest, counts)
    local before = turtle.getFuelLevel()

    for _, name in ipairs(FUEL_ITEMS) do
        if counts[name] and turtle.getFuelLevel() < fuelTarget() then
            refuelPlain(chest, name)
        end
    end

    for _, name in ipairs(ESSENCE_ITEMS) do
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

-- Moves from home to the nearest chest the map says has fuel
local function nearestFuelDist()
    local best

    for _, c in pairs(db.chests) do
        if c.fuel and (not best or c.dist < best) then best = c.dist end
    end

    return best
end

-- Don't leave home unless the fuel covers a lap, or at least
-- reaches a chest that can top it up.
local function waitForLapFuel()
    if turtle.getFuelLevel() == "unlimited" then return end

    local warned = false

    while true do
        eatLooseFuel()
        local level = turtle.getFuelLevel()

        if level >= lapCost() then return end

        local reach = nearestFuelDist()

        if reach and level >= reach + 10 then
            print(string.format("Fuel %d is low; the nearest fuel chest is %d moves out, so heading there first.",
                  level, reach))
            return
        end

        if not warned then
            print(string.format("Fuel %d won't cover a lap (%d)%s. Put coal in any slot.",
                  level, lapCost(), reach and "" or " and I don't know a chest with fuel"))
            warned = true
        end

        sleep(15)
    end
end

-- =========================================================
-- One chest
-- =========================================================

local function visitChest(key, dist)
    local chest = chestAt("front")

    if not chest then
        db.chests[key] = nil
        return
    end

    local counts, details = summarize(chest, true)
    local entry = { items = counts, fuel = hasFuel(counts), dist = dist }
    db.chests[key] = entry
    saveDB()

    -- Leftovers from a chest that refused them go here instead
    if not inventoryEmpty() then returnAll() end

    if not inventoryEmpty() then
        print(key .. ": my inventory isn't clear, so no crafting here")
        return
    end

    if entry.fuel and fuelLow() then
        refuelFrom(chest, counts)
    end

    local names = {}
    for name in pairs(counts) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
        local d = details[name]
        local recipe = db.recipes[name]

        if recipe ~= false and counts[name] >= MIN_STACKS * d.maxCount and isFood(name, d) then
            if recipe == nil then recipe = learnCrate(chest, name) end

            if recipe then
                local made = crate(chest, name, d.maxCount)

                if made > 0 then
                    stats.crates = stats.crates + made
                    print(string.format("%s: %d x %s -> %d x %s",
                          key, made * 9, name, made, recipe.result))
                end
            end
        end
    end

    -- Remember what's there now, after crating and refuelling
    entry.items = summarize(chest, false)
    entry.fuel = hasFuel(entry.items)
    saveDB()
end

-- =========================================================
-- The lap
--
-- Wall on the left, walk until a block is in front, turn right,
-- four times. Every cell gets a key of row / wall / cell so the
-- map lines up lap after lap.
-- =========================================================

local function lap()
    local moves, chests = 0, 0
    local seen = {}

    for row = 1, CHEST_ROWS do
        for wall = 1, 4 do
            local cell = 0

            while true do
                cell = cell + 1
                local key = string.format("R%d W%d C%02d", row, wall, cell)
                seen[key] = true

                if faceChestOnLeft() then
                    chests = chests + 1
                    visitChest(key, moves)
                    turtle.turnRight()
                else
                    db.chests[key] = nil
                end

                if turtle.detect() then break end

                if cell >= MAX_WALL then
                    error("Walked " .. MAX_WALL .. " cells without meeting a wall. Am I in the right room?")
                end

                forward()
                moves = moves + 1
            end

            turtle.turnRight()
        end

        if row < CHEST_ROWS then
            up()
            moves = moves + 1
        end
    end

    for _ = 2, CHEST_ROWS do
        down()
        moves = moves + 1
    end

    -- Chests from a room that has since shrunk
    for key in pairs(db.chests) do
        if not seen[key] then db.chests[key] = nil end
    end

    db.lapMoves = moves
    saveDB()

    return chests
end

-- =========================================================
-- Map printout
-- =========================================================

local function printMap()
    local keys = {}
    for k in pairs(db.chests) do keys[#keys + 1] = k end
    table.sort(keys)

    if #keys == 0 then
        print("No map yet. Do a lap first.")
        return
    end

    for _, k in ipairs(keys) do
        local c = db.chests[k]
        local names = {}
        for name in pairs(c.items) do names[#names + 1] = name end
        table.sort(names, function(a, b) return c.items[a] > c.items[b] end)

        local parts = {}
        for i = 1, math.min(#names, 4) do
            local short = (names[i]:gsub("^[^:]+:", ""))
            parts[#parts + 1] = short .. " x" .. c.items[names[i]]
        end
        if #names > 4 then parts[#parts + 1] = "+" .. (#names - 4) .. " more" end

        print(k .. (c.fuel and " [fuel]" or "") .. ": " ..
              (#parts > 0 and table.concat(parts, ", ") or "empty"))
    end

    print(#keys .. " chest(s); a lap is " .. tostring(db.lapMoves) .. " moves.")
end

-- =========================================================
-- Main
-- =========================================================

local args = { ... }

if args[1] == "reset" then
    if fs.exists(DB_FILE) then fs.delete(DB_FILE) end
    print("Forgot the map and the learned recipes.")
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

-- Burn whatever fuel was left in the turtle, then insist on an
-- empty inventory: crafting needs every slot clear.
eatLooseFuel()

while not inventoryEmpty() do
    print("My inventory must be empty (crafting needs all 16 slots). Take everything out.")
    sleep(10)
    eatLooseFuel()
end

local function run()
    while not stopRequested do
        waitForLapFuel()
        stats.crates, stats.fuelCrafts = 0, 0

        print("Lap starting (fuel " .. tostring(turtle.getFuelLevel()) .. ")")
        local chests = lap()
        print(string.format("Lap done: %d chest(s), %d crate(s) made, fuel %s.",
              chests, stats.crates, tostring(turtle.getFuelLevel())))

        if chests == 0 then
            print("Found no chests. Am I parked with the chest wall directly on my LEFT?")
        end

        if stopRequested then break end

        for _ = 1, LAP_INTERVAL do
            if stopRequested then break end
            sleep(1)
        end
    end
end

-- Q in the terminal asks for a clean stop at the end of the lap.
-- The watcher never returns on its own (that would end waitForAny
-- and kill the lap mid-move); it just raises the flag.
local function keyWatcher()
    while true do
        local _, k = os.pullEvent("key")

        if k == keys.q and not stopRequested then
            stopRequested = true
            print("Q pressed -- finishing this lap, then stopping at home.")
        end
    end
end

if LEFT_BLOCKED then
    print("Crafting table is on my left, so I'll turn to look at each chest.")
end

print("Press Q to stop at home after the current lap.")

parallel.waitForAny(run, keyWatcher)

print("Stopped at home.")

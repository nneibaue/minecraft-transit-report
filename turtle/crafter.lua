-- =========================================================
-- Wish-list crafter
--
--   A crafting turtle that sits between two chests and makes
--   whatever is in the drawer on top of it out of whatever is
--   in the chest in front of it. Put a lantern in the drawer
--   and dump logs, coal and iron in the chest: it crafts planks,
--   sticks, torches and nuggets on the way to lanterns and puts
--   the lanterns in the chest behind it. Put granite stairs in
--   the drawer and granite in the chest: granite stairs. For
--   each wish it works backwards through the recipes it knows
--   until it reaches something the chest actually holds, and it
--   mirrors its log on the monitor under it.
--
-- Layout, seen from the front (the side the monitor faces):
--
--            [ drawer ]              the wish list, on top
--   [input] [ turtle ] [output]      the turtle FACES the input chest
--     [   monitor   ]                any size, underneath
--
--   The turtle stands sideways: its front is the input chest,
--   its back the output chest. That's forced -- a turtle can
--   only take items from the block in front of, above or below
--   it, and above and below are taken.
--
-- Setup:
--   * A crafting turtle (crafting table upgrade on either side).
--     Advanced or not makes no difference here: an advanced
--     turtle only colours its own little screen, and a standard
--     monitor stays grey either way. It never moves, so it needs
--     no fuel. turtle.craft() insists on an empty inventory
--     around the crafting grid, so it keeps nothing aboard: what
--     it pulls out of the chest goes straight back after each
--     craft. Don't leave things in it.
--   * Wish list: a Functional Storage drawer (an oak drawer with
--     1, 2 or 4 slots) or any other block with an inventory, on
--     top of the turtle. Each kind of item in it is a wish, in
--     slot order: the first slot is worked on first, the second
--     only when the first can't progress, and so on. Keep at
--     least one of each in the drawer -- a locked-but-empty
--     drawer slot reads as empty. If the block on top can't be
--     read as an inventory, the OUTPUT chest doubles as the wish
--     list: drop one of what you want in it.
--   * Input chest: in front of the turtle. Dump raw materials
--     here. A plain chest or barrel is best, since it can be
--     asked to move a stack to its first slot for the turtle to
--     take; a Sophisticated Storage chest works too, but the
--     turtle has to park the stacks in front of the one it wants
--     (see gather()). Intermediates come back here between
--     steps, so it needs a couple of free slots.
--   * Output chest: behind the turtle (OUTPUT_SIDE). Finished
--     wishes end up here. Intermediates (planks, sticks, nuggets,
--     torches...) stay in the input chest for the next step, and
--     so does a wish that an EARLIER wish needs as an ingredient:
--     with lantern above torch on the list, torches are kept for
--     lanterns; put torch first to have them delivered instead.
--   * Monitor: under the turtle (or on any free side), optional.
--     A standard monitor is fine, the log is plain text.
--
-- Usage:
--   crafter           run forever
--   crafter recipes   print what it knows how to make, then stop
--   crafter forget    forget the recipes it found don't exist
--   Q (in the terminal) finish the current craft and stop.
--
-- Recipes: there's no recipe lookup in CC:Tweaked, so the turtle
-- has its own small book (RECIPES / FAMILIES below): lanterns,
-- torches, sticks, chests, barrels, and name-based families --
-- X_stairs / X_slab / X_wall from X, X_planks from X logs,
-- X_nugget from X_ingot, X_ingot from X_block, X_block from nine
-- X_ingot, and nine X from X_block (coal from coal blocks). A
-- family guess that turns out not to be a real recipe
-- (turtle.craft() refuses it) is remembered in crafter_bad.txt
-- and not tried again.
-- =========================================================

if not turtle then
    print("This program must be run on a crafting turtle.")
    return
end

if not turtle.craft then
    print("I need a crafting table upgrade to craft anything.")
    return
end

-- =========================================================
-- Config
-- =========================================================

-- Where things are, from the turtle's point of view. The input
-- chest is always in front (see Setup) and the wish list on top.
local OUTPUT_SIDE = "back"
local WISH_SIDE = "top"

-- How many of a wish to aim for per craft. Higher means fewer,
-- bigger crafts and more intermediates made ahead of time (the
-- nuggets for 16 lanterns at once); never more than the chest can
-- supply anyway.
local BATCH = 16

-- Hard cap on crafting steps in one turtle.craft() call
local MAX_STEPS = 32

-- Seconds to wait when nothing can be made before looking again
local IDLE_SECONDS = 5

-- Monitor text scale (0.5 = double resolution) and how many log
-- lines to keep for it
local MONITOR_SCALE = 0.5
local LOG_KEEP = 60

-- Family recipes that turned out not to exist are remembered here
local BAD_FILE = "crafter_bad.txt"

-- =========================================================
-- Inventory layout
--
-- turtle.craft() reads the 3x3 grid in slots 1-3, 5-7, 9-11 and
-- refuses to run unless every other slot is empty. Results land
-- in the selected slot (4) and spill into whatever else is free.
-- =========================================================

local GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }   -- grid cell 1..9 -> turtle slot
local RESULT_SLOT = 4

-- Results have to fit aboard: turtle.craft() drops what doesn't
-- fit on the ground. Seven slots outside the grid, 64 each, and
-- the grid itself empties as the craft consumes it.
local RESULT_ROOM = 7 * 64

local function toSet(list)
    local set = {}
    for _, v in ipairs(list) do set[v] = true end
    return set
end

-- "minecraft:iron_nugget" -> "iron nugget"
local function short(name)
    local s = name:gsub("^[^:]+:", "")
    s = s:gsub("_", " ")
    return s
end

-- =========================================================
-- Log, mirrored on the monitor
--
-- Every line goes to the turtle's own screen and, when there's
-- a monitor on any side, to that too: a header with the wish
-- list, then the most recent lines that fit.
-- =========================================================

local mon = nil
local logLines = {}
local wishText = "(nothing yet)"
local lastMsg = {}

local function findMonitor()
    mon = peripheral.find("monitor")
    if mon then pcall(mon.setTextScale, MONITOR_SCALE) end
end

local function wrapLine(text, width)
    local rows = {}

    while #text > width do
        rows[#rows + 1] = text:sub(1, width)
        text = " " .. text:sub(width + 1)
    end

    rows[#rows + 1] = text
    return rows
end

local function redraw()
    if not mon then return end

    local ok = pcall(function()
        local w, h = mon.getSize()

        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.clear()

        -- Header: the wish list, inverted
        mon.setCursorPos(1, 1)
        mon.setBackgroundColor(colors.white)
        mon.setTextColor(colors.black)
        mon.write((" WANT: " .. wishText .. string.rep(" ", w)):sub(1, w))

        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)

        local rows = {}
        for _, line in ipairs(logLines) do
            for _, r in ipairs(wrapLine(line, w)) do rows[#rows + 1] = r end
        end

        local y = 2
        for i = math.max(1, #rows - (h - 1) + 1), #rows do
            mon.setCursorPos(1, y)
            mon.write(rows[i])
            y = y + 1
        end
    end)

    if not ok then mon = nil end     -- monitor gone; look again on the next line
end

local function log(msg)
    print(msg)

    logLines[#logLines + 1] = os.date("%H:%M ") .. msg
    while #logLines > LOG_KEEP do table.remove(logLines, 1) end

    if not mon then findMonitor() end
    redraw()
end

-- Say something only when it changes, so a stuck state doesn't
-- repeat itself every few seconds
local function logOnce(key, msg)
    if lastMsg[key] ~= msg then
        lastMsg[key] = msg
        log(msg)
    end
end

local function setWishText(text)
    if wishText ~= text then
        wishText = text
        if not mon then findMonitor() end
        redraw()
    end
end

-- =========================================================
-- Peripherals
-- =========================================================

local function invAt(side)
    if not peripheral.isPresent(side) then return nil end

    local p = peripheral.wrap(side)
    if p and p.list and p.size then return p end
    return nil
end

local function describe(side)
    local t = peripheral.getType(side)
    if t then return t end

    local ok, data
    if side == "top" then
        ok, data = turtle.inspectUp()
    elseif side == "bottom" then
        ok, data = turtle.inspectDown()
    elseif side == "front" then
        ok, data = turtle.inspect()
    end

    if ok and data then return data.name .. " (not an inventory)" end
    return "nothing"
end

-- =========================================================
-- Ingredient specs
--
-- A spec says what an ingredient may be: match(name) tells if an
-- item qualifies, names lists concrete items to try making when
-- the chest has none, and derive(chest) adds candidates worked
-- out from what the chest holds (planks from its logs).
-- =========================================================

local function exact(name)
    return {
        desc = short(name),
        names = { name },
        match = function(n) return n == name end,
    }
end

local function anyOf(desc, names)
    local set = toSet(names)
    return {
        desc = desc,
        names = names,
        match = function(n) return set[n] == true end,
    }
end

-- "minecraft:oak_log" (or stripped log, wood, stem, hyphae, bamboo
-- block) -> "minecraft:oak_planks"; nil for anything else
local function planksFrom(name)
    local ns, rest = name:match("^([^:]+):(.+)$")
    if not ns then return nil end

    rest = rest:gsub("^stripped_", "")
    local wood, kind = rest:match("^(.+)_(%a+)$")
    if not wood then return nil end

    if kind == "log" or kind == "wood" or kind == "stem" or kind == "hyphae"
       or (kind == "block" and wood == "bamboo") then
        return ns .. ":" .. wood .. "_planks"
    end

    return nil
end

local PLANKS = {
    desc = "planks (or logs)",
    match = function(n) return n:find("_planks$") ~= nil end,
    derive = function(chest)
        local out = {}
        for name in pairs(chest) do
            local p = planksFrom(name)
            if p then out[#out + 1] = p end
        end
        table.sort(out)
        return out
    end,
}

local WOODS = toSet({ "oak", "spruce", "birch", "jungle", "acacia", "dark_oak",
                      "mangrove", "cherry", "bamboo", "crimson", "warped" })

local WOOD_SLAB = {
    desc = "wood slab",
    match = function(n)
        local wood = n:match("^[^:]+:(.+)_slab$")
        return wood ~= nil and WOODS[wood] == true
    end,
    derive = function(chest)
        local out = {}
        for name in pairs(chest) do
            local ns, wood = name:match("^([^:]+):(.+)_planks$")
            if ns and WOODS[wood] then out[#out + 1] = ns .. ":" .. wood .. "_slab" end
        end
        table.sort(out)
        return out
    end,
}

local COAL = anyOf("coal", { "minecraft:coal", "minecraft:charcoal" })
local SOUL = anyOf("soul sand or soil", { "minecraft:soul_sand", "minecraft:soul_soil" })
local COBBLE = anyOf("cobblestone", { "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:blackstone" })
local STICK = exact("minecraft:stick")
local TORCH = exact("minecraft:torch")
local SOUL_TORCH = exact("minecraft:soul_torch")
local IRON_NUGGET = exact("minecraft:iron_nugget")
local IRON_INGOT = exact("minecraft:iron_ingot")
local GLASS = exact("minecraft:glass")

-- =========================================================
-- Recipe book
--
-- A recipe is the result, how many one crafting step makes, and
-- cells[1..9]: which spec sits in each cell of the 3x3 grid (row
-- by row). shaped() builds one from rows of letters like the
-- game's own recipe files; "." is an empty cell.
-- =========================================================

local function shaped(result, count, rows, key)
    local cells = {}

    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)

            if ch ~= "." and ch ~= " " then
                local spec = key[ch]
                if not spec then error("recipe " .. result .. ": no spec for '" .. ch .. "'") end
                cells[(r - 1) * 3 + c] = spec
            end
        end
    end

    return { result = result, count = count, cells = cells }
end

local RECIPES = {
    ["minecraft:lantern"] = {
        shaped("minecraft:lantern", 1, { "NNN", "NTN", "NNN" }, { N = IRON_NUGGET, T = TORCH }),
    },
    ["minecraft:soul_lantern"] = {
        shaped("minecraft:soul_lantern", 1, { "NNN", "NTN", "NNN" }, { N = IRON_NUGGET, T = SOUL_TORCH }),
    },
    ["minecraft:torch"] = {
        shaped("minecraft:torch", 4, { "C", "S" }, { C = COAL, S = STICK }),
    },
    ["minecraft:soul_torch"] = {
        shaped("minecraft:soul_torch", 4, { "C", "S", "X" }, { C = COAL, S = STICK, X = SOUL }),
    },
    ["minecraft:stick"] = {
        shaped("minecraft:stick", 4, { "P", "P" }, { P = PLANKS }),
    },
    ["minecraft:crafting_table"] = {
        shaped("minecraft:crafting_table", 1, { "PP", "PP" }, { P = PLANKS }),
    },
    ["minecraft:chest"] = {
        shaped("minecraft:chest", 1, { "PPP", "P.P", "PPP" }, { P = PLANKS }),
    },
    ["minecraft:barrel"] = {
        shaped("minecraft:barrel", 1, { "PLP", "P.P", "PLP" }, { P = PLANKS, L = WOOD_SLAB }),
    },
    ["minecraft:furnace"] = {
        shaped("minecraft:furnace", 1, { "CCC", "C.C", "CCC" }, { C = COBBLE }),
    },
    ["minecraft:ladder"] = {
        shaped("minecraft:ladder", 3, { "S.S", "SSS", "S.S" }, { S = STICK }),
    },
    ["minecraft:iron_bars"] = {
        shaped("minecraft:iron_bars", 16, { "III", "III" }, { I = IRON_INGOT }),
    },
    ["minecraft:chain"] = {
        shaped("minecraft:chain", 1, { "N", "I", "N" }, { N = IRON_NUGGET, I = IRON_INGOT }),
    },
    ["minecraft:glass_pane"] = {
        shaped("minecraft:glass_pane", 16, { "GGG", "GGG" }, { G = GLASS }),
    },
    ["minecraft:bucket"] = {
        shaped("minecraft:bucket", 1, { "I.I", ".I." }, { I = IRON_INGOT }),
    },
}

-- Name-based families: <base>_stairs from <base>, and so on. The
-- base block's name is guessed from the target's: granite_stairs
-- -> granite, stone_brick_stairs -> stone_bricks, quartz_stairs ->
-- quartz_block, oak_stairs -> oak_planks. Only guesses that are
-- actually in the chest (or can be made) are ever used.
local FAMILIES = {
    { suffix = "_stairs", count = 4, rows = { "X..", "XX.", "XXX" } },
    { suffix = "_slab", count = 6, rows = { "XXX" } },
    { suffix = "_wall", count = 6, rows = { "XXX", "XXX" } },
}

-- Storage blocks whose name isn't just the item's name plus _block
local UNPACK = {
    ["minecraft:lapis_lazuli"] = "minecraft:lapis_block",
    ["minecraft:wheat"] = "minecraft:hay_block",
    ["minecraft:melon_slice"] = "minecraft:melon",
    ["minecraft:bone_meal"] = "minecraft:bone_block",
}

local function baseSpec(ns, base)
    return anyOf(short(ns .. ":" .. base), {
        ns .. ":" .. base,
        ns .. ":" .. base .. "s",
        ns .. ":" .. base .. "_block",
        ns .. ":" .. base .. "_planks",
    })
end

local recipeCache = {}

-- Every recipe the turtle knows for making `name`, best first
local function recipesFor(name)
    if recipeCache[name] then return recipeCache[name] end

    local out = RECIPES[name]

    if not out then
        out = {}
        local ns, item = name:match("^([^:]+):(.+)$")

        if ns then
            for _, f in ipairs(FAMILIES) do
                local base = item:match("^(.+)" .. f.suffix .. "$")
                if base then
                    out[#out + 1] = shaped(name, f.count, f.rows, { X = baseSpec(ns, base) })
                end
            end

            local wood = item:match("^(.+)_planks$")
            if wood then
                local logs = {
                    desc = (wood:gsub("_", " ")) .. " logs",
                    names = {
                        ns .. ":" .. wood .. "_log", ns .. ":stripped_" .. wood .. "_log",
                        ns .. ":" .. wood .. "_wood", ns .. ":stripped_" .. wood .. "_wood",
                        ns .. ":" .. wood .. "_stem", ns .. ":stripped_" .. wood .. "_stem",
                        ns .. ":" .. wood .. "_hyphae", ns .. ":stripped_" .. wood .. "_hyphae",
                        ns .. ":" .. wood .. "_block",
                    },
                    match = function(n) return planksFrom(n) == name end,
                }
                out[#out + 1] = shaped(name, 4, { "X" }, { X = logs })
            end

            local metal = item:match("^(.+)_nugget$")
            if metal then
                out[#out + 1] = shaped(name, 9, { "X" }, { X = exact(ns .. ":" .. metal .. "_ingot") })
            end

            metal = item:match("^(.+)_ingot$")
            if metal then
                out[#out + 1] = shaped(name, 9, { "X" }, { X = exact(ns .. ":" .. metal .. "_block") })
                out[#out + 1] = shaped(name, 1, { "XXX", "XXX", "XXX" }, { X = exact(ns .. ":" .. metal .. "_nugget") })
            end

            local stuff = item:match("^(.+)_block$")
            if stuff then
                local units = anyOf((stuff:gsub("_", " ")) .. " ingots", { ns .. ":" .. stuff .. "_ingot", ns .. ":" .. stuff })
                out[#out + 1] = shaped(name, 1, { "XXX", "XXX", "XXX" }, { X = units })
            else
                -- Anything might come packed nine to a block: coal from
                -- coal blocks, redstone from redstone blocks, diamonds
                -- from diamond blocks. Tried last, after the real recipes.
                local packed = UNPACK[name] or (name .. "_block")
                out[#out + 1] = shaped(name, 9, { "X" }, { X = exact(packed) })
            end
        end
    end

    recipeCache[name] = out
    return out
end

-- The distinct specs of a recipe and the grid cells each one fills
local function layout(recipe)
    local groups, bySpec = {}, {}

    for cell = 1, 9 do
        local spec = recipe.cells[cell]

        if spec then
            local g = bySpec[spec]
            if not g then
                g = { spec = spec, cells = {} }
                bySpec[spec] = g
                groups[#groups + 1] = g
            end
            g.cells[#g.cells + 1] = cell
        end
    end

    return groups
end

-- =========================================================
-- Recipes that don't exist
--
-- A family guess (say, 9 quartz -> quartz block) is tried once;
-- when turtle.craft() refuses it, that recipe plus those exact
-- ingredients is written off for good. `crafter forget` clears it.
-- =========================================================

local bad = {}

local function loadBad()
    if not fs.exists(BAD_FILE) then return end

    local f = fs.open(BAD_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()

    if type(data) == "table" then bad = data end
end

local function saveBad()
    local f = fs.open(BAD_FILE, "w")
    f.write(textutils.serialize(bad))
    f.close()
end

local function badKey(recipe, index, picks)
    local names = {}
    for _, p in ipairs(picks) do names[#names + 1] = p.name end
    table.sort(names)
    return recipe.result .. "#" .. index .. "|" .. table.concat(names, ",")
end

-- =========================================================
-- The chest in front
-- =========================================================

local stackLimit = {}     -- item name -> max stack size, learned as seen

-- name -> count of everything in the chest. Stacks with NBT are
-- skipped: they're not craftable as themselves and suck() can't
-- tell them apart.
local function readChest(inv)
    local counts = {}

    for slot, it in pairs(inv.list()) do
        if not it.nbt then
            counts[it.name] = (counts[it.name] or 0) + it.count

            if not stackLimit[it.name] then
                local d = inv.getItemDetail(slot)
                stackLimit[it.name] = (d and d.maxCount) or 64
            end
        end
    end

    return counts
end

local function freeSlots(inv)
    local used = 0
    for _ in pairs(inv.list()) do used = used + 1 end
    return inv.size() - used
end

-- The most plentiful item in the chest that satisfies the spec
local function bestIn(spec, chest)
    local bestName, bestCount = nil, 0

    for name, count in pairs(chest) do
        if count > bestCount and spec.match(name) then
            bestName, bestCount = name, count
        end
    end

    return bestName, bestCount
end

-- Concrete items that could satisfy the spec, in the order worth
-- trying to make them: what the chest already has some of (most
-- first), then the spec's own suggestions, then anything derived
-- from the chest's contents.
local function candidatesFor(spec, chest)
    local out, seen = {}, {}

    local function add(n)
        if n and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end

    local present = {}
    for name, count in pairs(chest) do
        if spec.match(name) then present[#present + 1] = { name = name, count = count } end
    end
    table.sort(present, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    for _, p in ipairs(present) do add(p.name) end

    for _, n in ipairs(spec.names or {}) do add(n) end
    if spec.derive then
        for _, n in ipairs(spec.derive(chest)) do add(n) end
    end

    return out
end

-- Pick a concrete item for each spec of the recipe out of the chest
-- and work out how many crafting steps it supports right now.
-- nil if some spec has nothing in the chest at all.
local function plan(recipe, chest)
    local picks, steps = {}, math.huge

    for _, g in ipairs(layout(recipe)) do
        local name, count = bestIn(g.spec, chest)
        if not name then return nil, 0 end

        picks[#picks + 1] = { name = name, cells = g.cells }
        steps = math.min(steps, math.floor(count / #g.cells))
    end

    return picks, steps
end

-- =========================================================
-- Moving items between the chest and the turtle
--
-- turtle.suck() only ever takes whatever the chest considers its
-- first stack, so getting a particular item out means either
-- asking the chest to move that stack to its first slot (plain
-- chests and barrels do this; Sophisticated Storage doesn't) or
-- parking the stacks in front of it in the turtle for a moment.
-- =========================================================

local parked = {}

local function park()
    for s = 1, 16 do
        if not parked[s] and turtle.getItemCount(s) == 0 then
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
    for s in pairs(parked) do dropSlot(s) end
    parked = {}
end

-- Everything aboard goes back into the chest in front. True if
-- the turtle is empty afterwards.
local function returnAll()
    local ok = true

    for s = 1, 16 do
        if not dropSlot(s) then ok = false end
    end

    parked = {}
    return ok
end

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

-- How many of `name` the turtle holds (parked stacks don't count)
local function aboard(name)
    local n = 0

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and d.name == name and not parked[s] then n = n + d.count end
    end

    return n
end

-- A slot that can take more of `name`: one already holding it with
-- room to spare, else any empty slot.
local function slotFor(name)
    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and d.name == name and not parked[s] and turtle.getItemSpace(s) > 0 then
            return s
        end
    end

    for s = 1, 16 do
        if turtle.getItemCount(s) == 0 then return s end
    end

    return nil
end

-- Get up to `want` of `name` out of the chest in front and into the
-- turtle, into whatever slots are free. Returns how many are aboard.
--
-- Every pass must visibly change something (items arrived, the
-- wanted stack moved to slot 1, or a stack got parked); a few
-- passes without progress and it gives up rather than spin.
local function gather(inv, name, want)
    local got, stalls = 0, 0

    while got < want and stalls < 4 do
        local list = inv.list()
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
            local slot = slotFor(name)
            if not slot then break end          -- turtle is full

            turtle.select(slot)
            local before = turtle.getItemCount(slot)
            turtle.suck(math.min(want - got, turtle.getItemSpace(slot)))

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
            if first > 1 then    -- slot 1 is free: ask for the item up front
                pcall(inv.pushItems, "front", src, want - got, 1)

                local now = inv.list()[1]
                if now and now.name == name then progressed = true end
            end

            if not progressed and park() then progressed = true end
        end

        if progressed then
            stalls = 0
        else
            stalls = stalls + 1
        end
    end

    unpark()

    if got < want and stalls >= 4 then
        log("  couldn't dig " .. short(name) .. " out of the chest; a plain chest or barrel in front of me would fix this")
    end

    return aboard(name)
end

-- Spread `name` over `slots` so each holds `per`, shuffling between
-- the turtle's own slots.
local function arrange(name, slots, per)
    local set = toSet(slots)

    for _, t in ipairs(slots) do
        local need = per - turtle.getItemCount(t)

        for s = 1, 16 do
            if need <= 0 then break end

            if s ~= t then
                local d = turtle.getItemDetail(s)

                if d and d.name == name then
                    local spare = set[s] and (d.count - per) or d.count

                    if spare > 0 then
                        turtle.select(s)
                        turtle.transferTo(t, math.min(spare, need))
                        need = per - turtle.getItemCount(t)
                    end
                end
            end
        end
    end
end

-- Put `name` items that aren't in `keep` back into the chest
local function dropExtra(name, keep)
    local set = toSet(keep)

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        if d and d.name == name and not set[s] then dropSlot(s) end
    end
end

-- Whatever is aboard that isn't an ingredient: the craft output,
-- with its total count
local function findResult(ingredients)
    local rname, total = nil, 0

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d and not ingredients[d.name] then
            rname = rname or d.name
            if d.name == rname then total = total + d.count end
        end
    end

    if rname then return rname, total end
    return nil, 0
end

-- =========================================================
-- One craft
--
-- Pull the ingredients for `steps` crafting steps out of the chest,
-- lay them out on the grid, craft, and put everything (the results)
-- back into the chest. Returns what was made and how many, plus a
-- verdict: "ok", "norecipe" (everything was laid out and the game
-- refused it) or "stuck" (the chest wouldn't hand something over or
-- take it back -- not the recipe's fault). Nothing is lost either way.
-- =========================================================

local function describePicks(picks)
    local parts = {}
    for _, p in ipairs(picks) do parts[#parts + 1] = short(p.name) end
    return table.concat(parts, " + ")
end

local function craft(inv, recipe, picks, steps)
    local ingredients = {}
    for _, p in ipairs(picks) do ingredients[p.name] = true end

    for _, p in ipairs(picks) do
        local want = #p.cells * steps

        if gather(inv, p.name, want) < want then
            returnAll()
            log("  couldn't get " .. want .. " x " .. short(p.name) .. " out of the chest")
            return nil, 0, "stuck"
        end
    end

    local keep = {}
    for _, p in ipairs(picks) do
        local slots = {}
        for _, c in ipairs(p.cells) do
            slots[#slots + 1] = GRID[c]
            keep[#keep + 1] = GRID[c]
        end
        arrange(p.name, slots, steps)
    end

    for _, p in ipairs(picks) do dropExtra(p.name, keep) end

    if not slotsEmptyExcept(keep) then
        returnAll()
        logOnce("full", "The input chest is full; I can't lay out a craft. Make some room in it.")
        return nil, 0, "stuck"
    end

    turtle.select(RESULT_SLOT)
    local ok = turtle.craft(steps)
    local rname, made = findResult(ingredients)

    if not returnAll() then
        logOnce("full", "The input chest is full; I'm holding what I just made. Make some room in it.")
    end

    if ok and rname then return rname, made, "ok" end
    if ok then return nil, 0, "stuck" end       -- crafted, but the result never showed up aboard
    return nil, 0, "norecipe"
end

-- =========================================================
-- Solving: what to craft next
-- =========================================================

local wishes = {}          -- item names, in priority order
local wishIndex = {}       -- name -> position in wishes
local wishNeeds = {}       -- position -> specs reachable from that wish

local stopRequested = false
local stats = { crafts = 0 }

-- All ingredient specs reachable from `target` through the recipe
-- book, so a wish can be told apart from an ingredient another
-- wish is waiting for
local function reachableSpecs(target, chest, out, seen, depth)
    if seen[target] or depth > 6 then return end
    seen[target] = true

    for _, r in ipairs(recipesFor(target)) do
        for _, g in ipairs(layout(r)) do
            out[#out + 1] = g.spec

            for _, n in ipairs(candidatesFor(g.spec, chest)) do
                reachableSpecs(n, chest, out, seen, depth + 1)
            end
        end
    end
end

local function computeNeeds(chest)
    wishNeeds = {}

    for i, w in ipairs(wishes) do
        local out = {}
        reachableSpecs(w, chest, out, {}, 0)
        wishNeeds[i] = out
    end
end

-- The wish, earlier in the list than position `idx`, that uses
-- `name` as an ingredient -- or nil
local function higherThatNeeds(name, idx)
    for i = 1, idx - 1 do
        for _, spec in ipairs(wishNeeds[i] or {}) do
            if spec.match(name) then return wishes[i] end
        end
    end

    return nil
end

-- Finished wishes in the input chest go to the output chest, unless
-- an earlier wish needs them. Returns items moved and whether the
-- output chest refused some.
local function sweep(inv)
    local moved, stuck = 0, false

    for slot, it in pairs(inv.list()) do
        local idx = wishIndex[it.name]

        if idx and not it.nbt and not higherThatNeeds(it.name, idx) then
            local ok, n = pcall(inv.pushItems, OUTPUT_SIDE, slot)
            n = (ok and type(n) == "number") and n or 0

            moved = moved + n
            if n < it.count then stuck = true end
        end
    end

    return moved, stuck
end

-- Words for what's missing to make `name`: the first recipe's
-- unsatisfied ingredients, each followed by what *it* would need.
local function missing(name, chest, seen, depth)
    seen[name] = true

    local recipes = recipesFor(name)
    if #recipes == 0 then return short(name) end

    local parts = {}

    for _, g in ipairs(layout(recipes[1])) do
        local _, have = bestIn(g.spec, chest)

        if have < #g.cells then
            local text = g.spec.desc

            if depth < 4 then
                for _, cand in ipairs(candidatesFor(g.spec, chest)) do
                    if not seen[cand] and #recipesFor(cand) > 0 then
                        local sub = missing(cand, chest, seen, depth + 1)
                        if sub ~= "" then text = text .. " < " .. sub end
                        break
                    end
                end
            end

            parts[#parts + 1] = text
        end
    end

    return table.concat(parts, ", ")
end

-- Try to make progress on `name`: craft it if the chest has the
-- ingredients, else craft the first ingredient it lacks that it
-- knows how to make. `need` is how many are wanted. `path` holds
-- the items above this one in the recursion, to keep nugget ->
-- ingot -> nugget from chasing its tail. Returns true if anything
-- was crafted.
local function step(inv, name, need, path, depth, wish)
    if depth > 8 or stopRequested then return false end

    local chest = readChest(inv)
    local recipes = recipesFor(name)

    -- Craftable right now?
    for i, r in ipairs(recipes) do
        local picks, steps = plan(r, chest)

        if picks and steps >= 1 and not bad[badKey(r, i, picks)] then
            local n = math.min(steps, math.ceil(need / r.count), MAX_STEPS, math.floor(RESULT_ROOM / r.count))
            for _, p in ipairs(picks) do n = math.min(n, stackLimit[p.name] or 64) end

            local rname, made, verdict = craft(inv, r, picks, n)

            if verdict == "ok" then
                stats.crafts = stats.crafts + 1
                lastMsg.full = nil

                if depth == 0 then
                    local keeper = higherThatNeeds(rname, wishIndex[wish] or 1)
                    local _, stuck = sweep(inv)

                    if keeper then
                        log(made .. " x " .. short(rname) .. " (kept: " .. short(keeper) .. " needs it)")
                    elseif stuck then
                        log(made .. " x " .. short(rname) .. " -> output chest is FULL; left in the input chest")
                    else
                        log(made .. " x " .. short(rname) .. " -> output")
                    end
                else
                    log(made .. " x " .. short(rname) .. " (for " .. short(wish) .. ")")
                end

                return true
            elseif verdict == "norecipe" then
                bad[badKey(r, i, picks)] = true
                saveBad()
                log("  " .. describePicks(picks) .. " doesn't make " .. short(name) .. "; won't try that again")
            else
                return false      -- the chest got in the way; don't blame the recipe
            end
        end
    end

    -- Make a missing ingredient
    path[name] = true

    for _, r in ipairs(recipes) do
        local wantSteps = math.min(math.ceil(need / r.count), MAX_STEPS)

        for _, g in ipairs(layout(r)) do
            local _, have = bestIn(g.spec, chest)
            local needed = #g.cells * wantSteps

            if have < needed then
                for _, cand in ipairs(candidatesFor(g.spec, chest)) do
                    if not path[cand] and #recipesFor(cand) > 0 then
                        if step(inv, cand, needed - (chest[cand] or 0), path, depth + 1, wish) then
                            path[name] = nil
                            return true
                        end
                    end
                end
            end
        end
    end

    path[name] = nil
    return false
end

-- =========================================================
-- The wish list
-- =========================================================

-- Item names in slot order, each once. From the drawer on top when
-- it can be read; otherwise from the output chest.
local function readWishes(out)
    local inv = invAt(WISH_SIDE)

    if not inv then
        inv = out
        logOnce("wishsrc", "Can't read the block on top (" .. describe(WISH_SIDE) ..
                "); using what's in the output chest as the wish list.")
    else
        logOnce("wishsrc", "Wish list: the " .. short(peripheral.getType(WISH_SIDE) or "inventory") .. " on top of me.")
    end

    local slots = {}
    for slot, it in pairs(inv.list()) do
        if not it.nbt then slots[#slots + 1] = { slot = slot, name = it.name } end
    end
    table.sort(slots, function(a, b) return a.slot < b.slot end)

    local names, seen = {}, {}
    for _, s in ipairs(slots) do
        if not seen[s.name] then
            seen[s.name] = true
            names[#names + 1] = s.name
        end
    end

    return names
end

local function setWishes(names)
    local changed = #names ~= #wishes
    for i, n in ipairs(names) do
        if wishes[i] ~= n then changed = true end
    end

    wishes, wishIndex = names, {}
    for i, n in ipairs(names) do wishIndex[n] = wishIndex[n] or i end

    local parts = {}
    for _, n in ipairs(names) do parts[#parts + 1] = short(n) end
    setWishText(#parts > 0 and table.concat(parts, ", ") or "(nothing)")

    if changed and #names > 0 then
        log("Wanted: " .. table.concat(parts, ", "))
        lastMsg = { wishsrc = lastMsg.wishsrc }      -- new list, fresh explanations
    end
end

-- =========================================================
-- Main loop
-- =========================================================

local function rest(seconds)
    for _ = 1, seconds do
        if stopRequested then return end
        sleep(1)
    end
end

-- One pass: read the wish list, tidy up, try each wish in order.
-- True if something was crafted (so the next pass follows at once).
local function round()
    local inv = invAt("front")
    local out = invAt(OUTPUT_SIDE)

    if not inv or not out then
        logOnce("chests", "I need an input chest in front of me (" .. describe("front") ..
                ") and an output chest " .. OUTPUT_SIDE .. " (" .. describe(OUTPUT_SIDE) .. ").")
        return false
    end
    lastMsg.chests = nil

    if not inventoryEmpty() and not returnAll() then
        logOnce("holding", "I'm holding items the input chest won't take. Make room in it (or empty me).")
        return false
    end
    lastMsg.holding = nil

    setWishes(readWishes(out))

    if #wishes == 0 then
        logOnce("empty", "Nothing on the wish list. Put what you want made in the drawer on top of me.")
        return false
    end
    lastMsg.empty = nil

    computeNeeds(readChest(inv))

    local _, stuck = sweep(inv)
    if stuck then
        logOnce("outfull", "The output chest is full.")
    else
        lastMsg.outfull = nil
    end

    if freeSlots(inv) < 2 then
        logOnce("full", "The input chest is full; I need a couple of free slots in it to work.")
        return false
    end
    lastMsg.full = nil

    for _, w in ipairs(wishes) do
        if stopRequested then return false end

        if #recipesFor(w) == 0 then
            logOnce("why:" .. w, short(w) .. ": I don't know a recipe for that")
        elseif step(inv, w, BATCH, {}, 0, w) then
            return true
        else
            local why = missing(w, readChest(inv), {}, 0)
            logOnce("why:" .. w, short(w) .. ": waiting for " .. (why ~= "" and why or "the chest to change"))
        end
    end

    return false
end

local function run()
    log("Crafter up. Input: " .. describe("front") .. " | output: " .. describe(OUTPUT_SIDE) ..
        " | monitor: " .. (mon and "yes" or "no"))

    while not stopRequested do
        if not round() then rest(IDLE_SECONDS) end
    end
end

-- Q in the terminal asks for a clean stop between crafts. The
-- watcher never returns on its own (that would end waitForAny
-- mid-craft); it just raises the flag.
local function keyWatcher()
    while true do
        local _, k = os.pullEvent("key")

        if k == keys.q and not stopRequested then
            stopRequested = true
            print("Q pressed -- finishing this craft, then stopping.")
        end
    end
end

-- =========================================================
-- Arguments
-- =========================================================

local args = { ... }

if args[1] == "recipes" then
    local names = {}
    for name in pairs(RECIPES) do names[#names + 1] = short(name) end
    table.sort(names)

    print("Recipes: " .. table.concat(names, ", "))
    print("Families: X stairs / X slab / X wall from X; X planks from X logs;")
    print("  X nugget from X ingot; X ingot from X block or 9 X nugget; X block from 9 X ingot;")
    print("  9 X from X block (coal from coal blocks, redstone, diamonds...)")

    loadBad()
    local n = 0
    for _ in pairs(bad) do n = n + 1 end
    if n > 0 then print(n .. " guessed recipe(s) known not to exist (crafter forget to retry them)") end

    return
elseif args[1] == "forget" then
    if fs.exists(BAD_FILE) then fs.delete(BAD_FILE) end
    print("Forgot which guessed recipes don't exist.")
    return
elseif args[1] then
    print("Usage: crafter | crafter recipes | crafter forget")
    return
end

loadBad()
findMonitor()

print("Press Q to stop after the current craft.")

parallel.waitForAny(run, keyWatcher)

returnAll()
print("Stopped after " .. stats.crafts .. " craft(s).")

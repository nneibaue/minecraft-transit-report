-- =========================================================
-- Macaw's balustrade bridge builder
--
--   Builds a floating cobblestone balustrade bridge (Macaw's
--   Bridges) straight out from a starting block, one column at
--   a time. Whenever it crosses into a new biome it drops a
--   marker block and a standing sign labelling that biome
--   beside the bridge. It turns back for home on its own when
--   it runs out of bridge pieces, runs low on fuel, hits
--   MAX_LENGTH, or is asked to stop with Q -- never leaving
--   itself stranded out on the bridge.
--
-- Setup:
--   * Turtle upgrades: an Advanced Peripherals Environment
--     Detector on one side, a pickaxe on the other (clears
--     obstacles ahead and is used by the resume probe below).
--   * Inventory (any slots, matched by name, re-scanned as
--     needed): bridge pieces (name contains "bridge" -- e.g. a
--     Macaw's Bridges balustrade cobblestone bridge), signs
--     (name contains "sign"), fuel (anything turtle.refuel(0)
--     accepts), and optionally a marker block. Leave
--     MARKER_MATCH nil and it auto-picks the first stack that
--     is none of the above, and tells you what it chose.
--   * Place the turtle ON TOP of a blue_skies:vitreous_moonstone
--     block, facing the direction to build.
--
-- Usage:
--   bridge          start or resume building
--   bridge reset    forget saved progress (deletes the state
--                   file and stops; run `bridge` again to
--                   start fresh)
--   bridge status   print the saved state and exit; no moving
--   Q (in the terminal) finishes the current column, heads
--   home, and stops.
--
-- Memory: bridge_state.txt on the turtle -- distance travelled,
-- the current lane, which biome was last marked, the furthest
-- built column, the recorded home block, and the world-compass
-- facing of "out" (used to recover heading after a reboot,
-- since a turtle can't sense its own facing). Saved immediately
-- before and after every move or turn that changes position, so
-- a mid-move reboot never leaves the file inconsistent with
-- where the turtle actually is.
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

local BRIDGE_MATCH = "bridge"    -- bridge pieces: any item whose name contains this
local MARKER_MATCH = nil         -- biome marker block; nil = auto-pick (see Inventory below)
local MARKER_SIDE = "right"      -- "left" or "right" -- which side gets the biome markers
local WIDTH = 1                  -- extra lanes are built to the RIGHT of lane 0
local REPLACE_TERRAIN = false    -- dig existing terrain under the deck before placing?
local MAX_LENGTH = 0             -- 0 = unlimited blocks before turning back

local FUEL_LOW = 200
local FUEL_TARGET = 2000
local FUEL_MARGIN = 50

local STATE_FILE = "bridge_state.txt"

-- =========================================================
-- Item & block matching
--
-- Small helpers shared by movement (protecting what it must
-- never dig), inventory scanning, and column building.
-- =========================================================

-- Resolved once at startup -- see "Inventory & fuel" and "Main" below.
local MARKER_NAME = nil
local detector = nil

local function isBridgeItem(name)
    return name ~= nil and name:find(BRIDGE_MATCH, 1, true) ~= nil
end

local function isSignItem(name)
    return name ~= nil and name:find("sign", 1, true) ~= nil
end

-- A cell counts as "open" (buildable / placeable into) if there's no
-- block there at all, or it's water/lava. Anything else is solid terrain.
local function isOpenBlock(ok, data)
    if not ok then return true end
    return data.name == "minecraft:water" or data.name == "minecraft:lava"
end

-- =========================================================
-- State
-- =========================================================

local state = {
    dist = 0,          -- blocks from home along the bridge
    lane = 0,          -- current sidestep offset; 0 = the main line
    heading = "out",   -- "out" | "back" | "left" | "right", relative to start
    built = 0,          -- furthest column known finished (fast-travel on resume)
    lastBiome = nil,    -- string or nil
    homeBlock = nil,    -- block name seen under the turtle at first run
    fOut = nil,         -- world compass facing of "out" (see Resume & probe)
    placed = 0,         -- per-run counter
    signs = 0,          -- per-run counter
}

local stopRequested = false

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

    if type(data) == "table" then
        state = data
        return true
    end

    return false
end

-- =========================================================
-- Heading & movement
--
-- A turtle can't read its own facing, so `heading` tracks
-- facing RELATIVE to the direction the turtle faced when it
-- started ("out"), using the fixed ring out -> right -> back ->
-- left -> out. turnR()/turnL() save state before and after, the
-- crater.lua pattern, so a mid-turn reboot never desyncs it.
-- =========================================================

local RING = { "out", "right", "back", "left" }
local RING_INDEX = { out = 1, right = 2, back = 3, left = 4 }

local function turnR()
    saveState()
    turtle.turnRight()
    state.heading = RING[(RING_INDEX[state.heading] % 4) + 1]
    saveState()
end

local function turnL()
    saveState()
    turtle.turnLeft()
    state.heading = RING[((RING_INDEX[state.heading] - 2) % 4) + 1]
    saveState()
end

-- Turns the short way (0, 1, or 2 calls) until heading == target.
local function faceRel(target)
    while state.heading ~= target do
        local diff = (RING_INDEX[target] - RING_INDEX[state.heading]) % 4
        if diff == 3 then
            turnL()
        else
            turnR()   -- diff == 1 or 2: turnR once (twice around the loop for 2)
        end
    end
end

-- Is this block one we must never dig as part of generic obstacle
-- clearing: a bridge piece, a sign, the recorded home block, or the
-- resolved marker block?
local function isProtected(name)
    if not name then return false end
    if isBridgeItem(name) then return true end
    if isSignItem(name) then return true end
    if state.homeBlock and name == state.homeBlock then return true end
    if MARKER_NAME and name == MARKER_NAME then return true end
    return false
end

-- Dig-loop with a bedrock/stubborn give-up. Never touches digDown/digUp --
-- that's the job of placeColumnPiece's REPLACE_TERRAIN branch and the
-- resume probe's own digUp, nowhere else.
local function clearAhead()
    local stubborn = 0

    while turtle.detect() do
        local ok, data = turtle.inspect()

        if ok and isProtected(data.name) then return false end
        if ok and data.name:find("bedrock", 1, true) then return false end

        if not turtle.dig() then
            stubborn = stubborn + 1
            if stubborn > 15 then return false end
        end

        sleep(0.15)   -- let gravel/sand settle
    end

    return true
end

-- Raw single step: clear, attack mobs, move. No position bookkeeping --
-- used both by forward() below and by the marker detour, which must not
-- touch state.dist/state.lane.
local function rawStep()
    for _ = 1, 20 do
        if turtle.forward() then return true end
        if not clearAhead() then return false end
        turtle.attack()
        sleep(0.15)
    end

    return false
end

-- Rare: clear a mob out of the way above/below the marker column. Never
-- digs a block here -- only REPLACE_TERRAIN and the probe's digUp do that.
local function stepUp()
    for _ = 1, 20 do
        if turtle.up() then return true end
        turtle.attackUp()
        sleep(0.15)
    end
    return false
end

local function stepDown()
    for _ = 1, 20 do
        if turtle.down() then return true end
        turtle.attackDown()
        sleep(0.15)
    end
    return false
end

-- forward() is used for all bridge-line and lane-sidestep travel. The
-- marker detour does NOT use it -- it makes its own raw, symmetric moves.
local function forward()
    saveState()
    local ok = rawStep()

    if ok then
        if state.heading == "out" then state.dist = state.dist + 1
        elseif state.heading == "back" then state.dist = state.dist - 1
        elseif state.heading == "right" then state.lane = state.lane + 1
        elseif state.heading == "left" then state.lane = state.lane - 1
        end
    end

    saveState()
    return ok
end

-- =========================================================
-- Inventory & fuel
-- =========================================================

-- Scans slots 1-16 fresh every time -- no cached slot numbers, since
-- inventory shifts as the turtle carries and consumes items.
local function findSlot(kind)
    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d then
            if kind == "bridge" and isBridgeItem(d.name) then
                return s
            elseif kind == "sign" and isSignItem(d.name) then
                return s
            elseif kind == "marker" and MARKER_NAME and d.name == MARKER_NAME then
                return s
            elseif kind == "fuel" then
                turtle.select(s)
                if turtle.refuel(0) then return s end
            end
        end
    end

    return nil
end

-- Once, at startup: pin down what "the marker block" means for this run.
local function resolveMarker()
    if MARKER_MATCH then
        MARKER_NAME = MARKER_MATCH
        return
    end

    for s = 1, 16 do
        local d = turtle.getItemDetail(s)

        if d then
            local bridge = isBridgeItem(d.name)
            local sign = isSignItem(d.name)
            turtle.select(s)
            local fuel = turtle.refuel(0)

            if not bridge and not sign and not fuel then
                MARKER_NAME = d.name
                print("Using " .. d.name .. " as the marker block.")
                return
            end
        end
    end

    print("No marker block found in inventory -- markers/signs will report " ..
          "\"none in inventory\" until one is added; that's expected, not an error.")
end

local function refuelIfNeeded()
    if turtle.getFuelLevel() == "unlimited" then return end
    if turtle.getFuelLevel() >= FUEL_LOW then return end

    while turtle.getFuelLevel() < FUEL_TARGET do
        local slot = findSlot("fuel")
        if not slot then return end

        turtle.select(slot)
        if not turtle.refuel(1) then return end
    end
end

-- =========================================================
-- Biome markers
-- =========================================================

local function readBiome()
    if not detector then return nil end

    local ok, biome = pcall(function() return detector.getBiome() end)
    if not ok or biome == nil then return nil end

    if type(biome) == "string" then return biome end

    if type(biome) == "table" then
        return biome.name or biome.id or biome[1]
    end

    return nil
end

-- "minecraft:dark_forest" -> "Dark Forest"; "blue_skies:x_y" -> "X Y"
local function prettifyBiome(id)
    local path = id:match("^[^:]+:(.+)$") or id
    local words = {}

    for w in path:gmatch("[^_]+") do
        words[#words + 1] = w:sub(1, 1):upper() .. w:sub(2)
    end

    return table.concat(words, " ")
end

-- Greedy word-wrap into lines of at most 15 chars, capped at 4 lines. If
-- the wrapped name used 3 lines or fewer, a "<dist>m out" line is appended.
local function wrapSignText(name, dist)
    local lines = {}
    local current = ""

    for word in name:gmatch("%S+") do
        if current == "" then
            current = word
        elseif #current + 1 + #word <= 15 then
            current = current .. " " .. word
        else
            lines[#lines + 1] = current
            current = word
        end
    end

    if current ~= "" then
        lines[#lines + 1] = current
    end

    while #lines > 4 do
        table.remove(lines)
    end

    if #lines <= 3 then
        lines[#lines + 1] = dist .. "m out"
    end

    return table.concat(lines, "\n")
end

-- Runs once per column, comparing the read biome to state.lastBiome (nil
-- counts as different, so the very first column always checks). Turtle
-- starts and ends this call at deck+1 over the edge lane, facing "out" --
-- the sequence is symmetric and returns there by construction in every
-- branch (success, missing marker, missing sign, or blocked), without
-- touching state.dist/state.lane.
--
-- Returns "ok", or a reason string ("Out of marker blocks." / "Out of
-- signs.") if inventory was missing for what this biome needed.
local function checkBiomeMarker(dist)
    local biome = readBiome()

    if biome == nil then
        print("Couldn't read the biome this column; will try again next column.")
        return "ok"
    end

    if biome == state.lastBiome then
        return "ok"
    end

    local towardMarker, backFromMarker
    if MARKER_SIDE == "right" then
        towardMarker, backFromMarker = turnR, turnL
    else
        towardMarker, backFromMarker = turnL, turnR
    end

    -- 1: face the marker side.
    towardMarker()

    -- 2: one obstacle-cleared step out to the marker column.
    if not rawStep() then
        backFromMarker()
        print("Couldn't reach the marker side; will try again next column.")
        return "ok"
    end

    -- 3: marker block on the ground below.
    local groundOk, groundData = turtle.inspectDown()

    if isOpenBlock(groundOk, groundData) then
        local slot = findSlot("marker")

        if not slot then
            -- Abort short: nothing was placed and we never rose for the
            -- sign, so just reverse steps 2 and 1 back to the edge lane.
            rawStep()
            backFromMarker()
            return "Out of marker blocks."
        end

        turtle.select(slot)
        turtle.placeDown()
    end
    -- else: a solid block is already there; use it as-is, no placement.

    -- 4: rise to sign height.
    stepUp()

    -- 5: sign on top of the marker.
    local newSign = false
    local reason = nil
    local signOk = turtle.inspectDown()

    if not signOk then
        local slot = findSlot("sign")

        if not slot then
            reason = "Out of signs."
        else
            turtle.select(slot)
            turtle.placeDown(wrapSignText(prettifyBiome(biome), dist))
            newSign = true
        end
    end
    -- else: a sign is already there from a previous run; skip placing.

    -- 6-9: always return to the edge lane at deck+1, facing "out" -- a
    -- marker or sign already placed/found is left in place either way.
    turnR()
    turnR()
    rawStep()
    stepDown()
    backFromMarker()

    if reason then
        return reason
    end

    state.lastBiome = biome
    if newSign then
        state.signs = state.signs + 1
    end
    saveState()

    return "ok"
end

-- =========================================================
-- Column building
-- =========================================================

-- Capture fOut the very first time a bridge piece is successfully
-- placed anywhere in the run's lifetime -- only needs to happen once,
-- ever, across the state file's lifetime.
local function captureFOutIfNeeded()
    if state.fOut ~= nil then return end

    local ok, data = turtle.inspectDown()
    if ok and data.state and data.state.facing then
        state.fOut = data.state.facing
    end
end

-- Called once per lane, at the deck spot below the turtle. Bridge pieces
-- take their horizontal facing from the turtle's heading at placeDown()
-- time, so this is only ever called while heading == "out".
local function placeColumnPiece()
    local ok, data = turtle.inspectDown()

    if ok and isBridgeItem(data.name) then
        return   -- already built here; keeps reruns idempotent, no count
    end

    local placeable = isOpenBlock(ok, data)

    if not placeable and REPLACE_TERRAIN then
        turtle.digDown()
        placeable = true
    end

    if not placeable then
        return   -- terrain, and REPLACE_TERRAIN is off: leave it alone
    end

    local slot = findSlot("bridge")
    if not slot then
        return   -- the top-of-loop "out of pieces" check catches this next
    end

    turtle.select(slot)
    if turtle.placeDown() then
        state.placed = state.placed + 1
        captureFOutIfNeeded()
    end
end

-- One full column: lane 0, then each extra lane to the right, with the
-- biome/marker check slotted in beside whichever lane sits on
-- MARKER_SIDE (both edges collapse to lane 0 when WIDTH == 1). Returns
-- an abort reason string if the marker sequence hit missing inventory
-- anywhere, else "ok" (well, nil -- see caller).
local function buildColumn(dist)
    placeColumnPiece()

    local abortReason = nil

    if WIDTH == 1 or MARKER_SIDE == "left" then
        local r = checkBiomeMarker(dist)
        if r ~= "ok" then abortReason = r end
    end

    for lane = 1, WIDTH - 1 do
        turnR()
        forward()
        turnL()
        placeColumnPiece()

        if lane == WIDTH - 1 and MARKER_SIDE == "right" then
            local r = checkBiomeMarker(dist)
            if r ~= "ok" then abortReason = r end
        end
    end

    -- Return to lane 0.
    turnL()
    while state.lane > 0 do
        forward()
    end
    turnR()

    return abortReason
end

-- =========================================================
-- Resume & probe
-- =========================================================

local function freshState()
    state = {
        dist = 0, lane = 0, heading = "out", built = 0,
        lastBiome = nil, homeBlock = nil, fOut = nil,
        placed = 0, signs = 0,
    }

    local ok, data = turtle.inspectDown()

    if not ok then
        print("No block detected below me -- expected the vitreous moonstone. Continuing anyway.")
    else
        state.homeBlock = data.name
        if not data.name:find("moonstone", 1, true) then
            print("Warning: the block below me (" .. data.name ..
                  ") doesn't look like vitreous moonstone. Continuing anyway.")
        end
    end

    saveState()
end

-- Walks from home out to the recorded frontier, correcting `built` if the
-- world doesn't match what was saved (bridge extended or torn up by hand).
local function travelToFrontier()
    while state.dist < state.built do
        if not forward() then
            error("Blocked on the way back to the frontier. Clear the way and run me again.")
        end

        local ok, data = turtle.inspectDown()
        if isOpenBlock(ok, data) then
            state.built = state.dist
            saveState()
            break
        end
    end

    -- Keep going past the recorded frontier for as long as someone
    -- extended the bridge by hand; stop the moment it isn't a bridge piece.
    while true do
        local ok, data = turtle.inspectDown()
        if not (ok and isBridgeItem(data.name)) then break end

        if not forward() then
            error("Blocked while extending past a hand-built stretch. Clear the way and run me again.")
        end

        state.built = state.dist
        saveState()
    end
end

-- Rebooted mid-bridge: heading is unknown, since a turtle can't sense its
-- own facing. Place a bridge piece above, read its compass facing back,
-- dig it up again, and work out heading from the ring distance to fOut.
local function recoverHeading()
    if not findSlot("bridge") or state.fOut == nil then
        print("Put me back on the moonstone facing the bridge and run `bridge reset`")
        return false
    end

    turtle.select(findSlot("bridge"))
    local placed = turtle.placeUp()

    local inspectOk, inspectData = false, nil
    if placed then
        inspectOk, inspectData = turtle.inspectUp()
        turtle.digUp()   -- remove the probe piece either way
    end

    local probedFacing = inspectOk and inspectData.state and inspectData.state.facing

    local COMPASS = { north = 0, east = 1, south = 2, west = 3 }
    local HEADING_BY_DIFF = { [0] = "out", [1] = "right", [2] = "back", [3] = "left" }

    if not placed or not probedFacing or COMPASS[probedFacing] == nil then
        print("Put me back on the moonstone facing the bridge and run `bridge reset`")
        return false
    end

    local diff = (COMPASS[probedFacing] - COMPASS[state.fOut]) % 4
    state.heading = HEADING_BY_DIFF[diff]
    saveState()

    faceRel("out")

    if state.lane > 0 then
        turnL()
        while state.lane > 0 do
            forward()
        end
        turnR()
    end

    return true
end

-- Loads (or initializes) state, then gets the turtle to exactly the next
-- column that needs building. Returns false if it couldn't (and has
-- already told the user why); the caller must not build or move further.
local function startupResume()
    local hadState = loadState()
    if not hadState then
        freshState()
    end

    -- Per-run counters always reset, whether resuming or starting fresh.
    state.placed = 0
    state.signs = 0
    saveState()

    if state.dist == 0 then
        travelToFrontier()
        return true
    end

    return recoverHeading()
end

-- =========================================================
-- Going home
-- =========================================================

local function checkHome()
    if not state.homeBlock then return true end
    local ok, data = turtle.inspectDown()
    return ok and data.name == state.homeBlock
end

-- At dist == 0, homeBlock should be right underneath. If it isn't,
-- search one block either side of the assumed spot before giving up.
local function verifyHome()
    if not state.homeBlock then return end
    if checkHome() then return end

    if not rawStep() then
        error("Lost track of home. Put me back on top of " .. state.homeBlock .. " and run `bridge reset`.")
    end

    if checkHome() then
        state.dist = 0
        saveState()
        return   -- still facing "out"; this position is the corrected home
    end

    -- Still no match: go back two blocks from here (one block behind the
    -- originally assumed home) and check once more.
    turnR(); turnR()

    if not (rawStep() and rawStep()) then
        error("Lost track of home. Put me back on top of " .. state.homeBlock .. " and run `bridge reset`.")
    end

    if checkHome() then
        state.dist = 0
        saveState()
        turnR(); turnR()   -- face "out" again, the usual end-of-run convention
        return
    end

    error("Lost track of home. Put me back on top of " .. state.homeBlock .. " and run `bridge reset`.")
end

local function goHome()
    state.built = state.dist
    saveState()

    faceRel("back")

    while state.dist > 0 do
        if not forward() then
            error("Blocked on the way home. Clear the way and run me again.")
        end
    end

    faceRel("out")   -- a refill + rerun needs no repositioning

    verifyHome()

    print(string.format(
        "Placed %d piece(s) this run. Bridge is %dm long, %d sign(s) placed this run. Refill and run again.",
        state.placed, state.built, state.signs))
end

-- =========================================================
-- Main
-- =========================================================

-- Order matters: stop flag, out of pieces, length limit, fuel -- checked
-- only here, between columns, which is what lets an in-progress column
-- finish before the turtle turns back.
local function mainLoop()
    while true do
        if stopRequested then
            return
        end

        if not findSlot("bridge") then
            print("No bridge pieces left. Heading home.")
            return
        end

        if MAX_LENGTH > 0 and state.dist >= MAX_LENGTH then
            print("Reached the length limit (" .. MAX_LENGTH .. " blocks). Heading home.")
            return
        end

        refuelIfNeeded()
        local fuel = turtle.getFuelLevel()

        if fuel ~= "unlimited" and fuel < state.dist + FUEL_MARGIN then
            print("Not enough fuel to get back (have " .. fuel .. ", need " ..
                  (state.dist + FUEL_MARGIN) .. "). Heading home.")
            return
        end

        local abortReason = buildColumn(state.dist)
        if abortReason then
            print(abortReason .. " Heading home.")
            return
        end

        if not forward() then
            print("Blocked ahead and can't clear it. Heading home.")
            return
        end
    end
end

local function printStatus()
    print("dist: " .. state.dist)
    print("lane: " .. state.lane)
    print("heading: " .. state.heading)
    print("built: " .. state.built)
    print("lastBiome: " .. tostring(state.lastBiome))
    print("homeBlock: " .. tostring(state.homeBlock))
    print("fOut: " .. tostring(state.fOut))
    print("placed: " .. state.placed)
    print("signs: " .. state.signs)
end

local args = { ... }

if args[1] == "reset" then
    if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
    print("Forgot the saved bridge progress.")
    return
end

if args[1] == "status" then
    if not loadState() then
        print("No saved state yet -- never run.")
        return
    end
    printStatus()
    return
end

detector = peripheral.find("environmentDetector") or peripheral.find("environment_detector")

if not detector then
    print("No Environment Detector found. Equip an Advanced Peripherals Environment Detector on one side and try again.")
    return
end

resolveMarker()

if not startupResume() then
    return
end

local function run()
    mainLoop()
    goHome()
end

-- Q in the terminal asks for a clean stop after the current column. The
-- watcher never returns on its own (that would end waitForAny and kill
-- the run mid-move); it just raises the flag, exactly once.
local function keyWatcher()
    while true do
        local _, k = os.pullEvent("key")

        if k == keys.q and not stopRequested then
            stopRequested = true
            print("Q pressed -- finishing this column, then heading home.")
        end
    end
end

print("Press Q to stop after the current column.")

parallel.waitForAny(run, keyWatcher)

print("Stopped.")

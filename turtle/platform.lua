-- platform: build (or carve) a flat platform with a turtle
-- Usage: platform <z> <x>
--   z = how far the platform extends FORWARD (the way the turtle is facing)
--   x = how far it extends to the RIGHT
--
-- Setup: stand the turtle on the edge of the existing ground, facing the
-- direction you want the platform to go. The block the turtle starts on is
-- NOT part of the platform: the platform begins at the block directly in
-- front of it, and that column is the first one, with the rest extending to
-- the right.
--
-- At every cell it clears its own level and the block above (a 2-high
-- walkway), digs out whatever is on the floor and lays its own block there,
-- so it carves through hills as well as bridging open air. It builds with
-- whatever was in its inventory when it started (slot 1 first, then 2, 3,
-- ...); blocks it digs up along the way are NOT used as building material.
-- Needs a mining turtle (pickaxe) to dig. Comes back to its starting block
-- when done.

if not turtle then
  print("This program must be run on a turtle.")
  return
end

local args = { ... }
local sizeZ = tonumber(args[1])
local sizeX = tonumber(args[2])
if not sizeZ or not sizeX or sizeZ < 1 or sizeX < 1 then
  print("Usage: platform <z> <x>")
  return
end
sizeZ, sizeX = math.floor(sizeZ), math.floor(sizeX)

-- Position relative to the starting block: posZ = blocks forward, posX = blocks right.
-- heading: 0 = forward (start direction), 1 = right, 2 = back, 3 = left
local posZ, posX, heading = 0, 0, 0

local function turnRight()
  turtle.turnRight()
  heading = (heading + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  heading = (heading + 3) % 4
end

local function face(h)
  while heading ~= h do
    if (h - heading) % 4 == 3 then turnLeft() else turnRight() end
  end
end

-- Move forward one block, digging or attacking whatever is in the way.
local function forward()
  local tries = 0
  while true do
    local ok, err = turtle.forward()
    if ok then break end
    if err == "Out of fuel" then
      error("Out of fuel at z=" .. posZ .. " x=" .. posX, 0)
    end
    tries = tries + 1
    if tries > 30 then
      error("Stuck at z=" .. posZ .. " x=" .. posX, 0)
    end
    if turtle.detect() then
      if not turtle.dig() then sleep(0.5) end  -- can't dig it (bedrock? no pickaxe?)
    else
      turtle.attack()  -- a mob is in the way
      sleep(0.5)
    end
  end
  if heading == 0 then posZ = posZ + 1
  elseif heading == 1 then posX = posX + 1
  elseif heading == 2 then posZ = posZ - 1
  else posX = posX - 1 end
end

-- Clear the block above the turtle so the platform has 2-high headroom.
local function clearUp()
  local tries = 0
  while turtle.detectUp() and tries < 20 do
    tries = tries + 1
    if not turtle.digUp() then break end  -- can't dig it, leave it
    sleep(0.3)  -- let sand/gravel settle before checking again
  end
end

-- Building materials: whatever item types are in the inventory at start.
-- Blocks dug up during the build are never added, so junk never ends up in
-- the platform.
local buildItems = {}
local function learnItem(slot)
  local d = turtle.getItemDetail(slot)
  if d then buildItems[d.name] = true end
end

-- Select the first slot (1..16) holding a building material.
local function selectBlock()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      local d = turtle.getItemDetail(slot)
      if d and buildItems[d.name] then
        turtle.select(slot)
        return slot
      end
    end
  end
  return nil
end

-- Wait until more blocks are added. Anything added while waiting counts as
-- a building material from then on.
local function waitForBlocks()
  print("Out of blocks! Add more to the inventory to continue...")
  local before = {}
  for s = 1, 16 do before[s] = turtle.getItemCount(s) end
  repeat
    sleep(2)
    for s = 1, 16 do
      local n = turtle.getItemCount(s)
      if n > before[s] then learnItem(s) end
      before[s] = n
    end
  until selectBlock()
end

-- Do one cell of the platform: headroom above, our own block below.
local function buildCell()
  clearUp()
  local hasBlock, info = turtle.inspectDown()
  if hasBlock then
    if buildItems[info.name] then return end  -- already our material, keep it
    turtle.digDown()  -- carve out whatever is there
  end
  local fails = 0
  while true do
    local slot = selectBlock()
    if not slot then
      waitForBlocks()
      fails = 0
    elseif turtle.placeDown() then
      return
    elseif turtle.detectDown() then
      return  -- couldn't dig it out (bedrock?), leave it as the floor
    else
      turtle.attackDown()  -- a mob may be standing in the way
      fails = fails + 1
      if fails >= 5 then
        local d = turtle.getItemDetail(slot)
        print("Can't place " .. (d and d.name or "slot " .. slot) .. ", skipping it")
        if d then buildItems[d.name] = nil end
        fails = 0
      end
      sleep(0.5)
    end
  end
end

-- Fuel check: step off the start block, serpentine over the area, then the
-- worst-case trip back to the start block. Digging costs no fuel.
local function fuelNeeded()
  local build = 1 + (sizeZ - 1) * sizeX + (sizeX - 1)
  local home = sizeZ + (sizeX - 1)
  return build + home
end

local fuel = turtle.getFuelLevel()
if fuel ~= "unlimited" and fuel < fuelNeeded() then
  print("Not enough fuel: need about " .. fuelNeeded() .. ", have " .. fuel)
  return
end

local have = 0
for slot = 1, 16 do
  local n = turtle.getItemCount(slot)
  if n > 0 then
    have = have + n
    learnItem(slot)
  end
end
if have == 0 then
  print("No blocks in the inventory. Put building blocks in slot 1, 2, 3, ...")
  return
end
if have < sizeZ * sizeX then
  print("Warning: have " .. have .. " blocks, platform needs up to " .. (sizeZ * sizeX))
  print("I'll pause and wait for more when I run out.")
end

print("Building " .. sizeZ .. " forward by " .. sizeX .. " right...")

-- Step off the starting block; the platform begins at the block ahead.
forward()

-- Serpentine: out along one column, step right, back along the next column.
for col = 1, sizeX do
  for row = 1, sizeZ do
    buildCell()
    if row < sizeZ then forward() end
  end
  if col < sizeX then
    if col % 2 == 1 then
      turnRight(); forward(); turnRight()
    else
      turnLeft(); forward(); turnLeft()
    end
  end
end

-- Return to the starting block, facing the original direction.
if posX > 0 then
  face(3)
  while posX > 0 do forward() end
end
if posZ > 0 then
  face(2)
  while posZ > 0 do forward() end
end
face(0)

print("Done.")

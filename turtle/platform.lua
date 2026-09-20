-- platform: build a flat platform with a turtle
-- Usage: platform <z> <x>
--   z = how far the platform extends FORWARD (the way the turtle is facing)
--   x = how far it extends to the RIGHT
--
-- Setup: stand the turtle on the edge of the existing ground, facing the
-- direction you want the platform to go. The block the turtle starts on is
-- NOT part of the platform: the platform begins at the block directly in
-- front of it, and that column is the first one, with the rest extending to
-- the right. It lays blocks underneath itself using slot 1 first, then 2,
-- 3, ... and comes back to its starting block when done.

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

-- Move forward one block, digging/attacking anything in the way.
local function forward()
  local tries = 0
  while true do
    local ok, err = turtle.forward()
    if ok then break end
    if err == "Out of fuel" then
      error("Out of fuel at z=" .. posZ .. " x=" .. posX, 0)
    end
    if turtle.detect() then turtle.dig() else turtle.attack() end
    tries = tries + 1
    if tries > 30 then
      error("Stuck at z=" .. posZ .. " x=" .. posX, 0)
    end
    sleep(0.5)
  end
  if heading == 0 then posZ = posZ + 1
  elseif heading == 1 then posX = posX + 1
  elseif heading == 2 then posZ = posZ - 1
  else posX = posX - 1 end
end

-- Select the first non-empty slot (1..16) that hasn't been marked unusable.
local badSlot = {}
local function selectBlock()
  for slot = 1, 16 do
    if not badSlot[slot] and turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      return slot
    end
  end
  return nil
end

-- Place a block directly below the turtle.
local function placeBlock()
  if turtle.detectDown() then return end  -- already a block there, keep it
  local fails = 0
  while true do
    local slot = selectBlock()
    if not slot then
      print("Out of blocks! Add more to the inventory to continue...")
      repeat sleep(2) until selectBlock()
      fails = 0
    elseif turtle.placeDown() then
      return
    elseif turtle.detectDown() then
      return  -- something appeared underneath in the meantime
    else
      turtle.attackDown()  -- a mob may be standing in the way
      fails = fails + 1
      if fails >= 5 then
        print("Can't place the item in slot " .. slot .. ", skipping that slot")
        badSlot[slot] = true
        fails = 0
      end
      sleep(0.5)
    end
  end
end

-- Fuel check: step off the start block, serpentine over the area, then the
-- worst-case trip back to the start block.
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
for slot = 1, 16 do have = have + turtle.getItemCount(slot) end
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
    placeBlock()
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

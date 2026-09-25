-- client.lua : device-side agent for CC:Tweaked (turtle OR computer)
-- Connects to the bridge, announces itself, executes commands, reports results.
-- Runs unchanged on a turtle or a stationary Advanced Computer; turtle-only
-- tools are registered only when `turtle` exists.
--
-- Setup on the device:
--   1. the in-game installer (install.lua, see README "Setup > 2. In game")
--      writes secret.txt (the shared token) and bridge.txt (the bridge URL);
--      without bridge.txt the BRIDGE_URL default below applies
--   2. startup.lua runs this file on boot, after updating it from main

local BRIDGE_URL = "ws://127.0.0.1:8765"         -- default; bridge.txt overrides it
local DEVICE_ID  = os.getComputerLabel() or ("device-" .. os.getComputerID())
local ALLOW_EVAL = false   -- set true to let the agent run arbitrary Lua (run_lua tool)

---------------------------------------------------------------- helpers
local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end

-- Kept alongside readFile so a later push-script / load-routine primitive can
-- slot in without another rewrite (nothing on the device writes files today).
local function writeFile(path, s)
  local f = fs.open(path, "w"); f.write(s); f.close()
end

local TOKEN = readFile("secret.txt")
if not TOKEN then error("secret.txt missing: put the bridge token in it") end
TOKEN = TOKEN:gsub("%s+$", "")
local BRIDGE_FILE = readFile("bridge.txt")
if BRIDGE_FILE then BRIDGE_URL = BRIDGE_FILE:gsub("%s+$", "") end

local function log(...) print(("[%s] "):format(textutils.formatTime(os.time(), true)), ...) end

-- DEBUG on: `mkdir debug` at the device prompt, then reboot. Off: `rm debug`, then reboot.
local DEBUG = fs.exists("debug")
local function dbg(...)
  if not DEBUG then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local line = table.concat(parts, " ")
  log("DEBUG", line)
  local f = fs.open("debug.log", "a")
  if f then f.writeLine(line); f.close() end
end

---------------------------------------------------------------- tools
-- Every tool: function(args) -> table (JSON-serialisable). Errors are caught.
-- Primitives only: each tool is a one-to-one wrapper over a CC:Tweaked call.
-- Anything with a loop or a policy (sorting, rules, pathing) lives in the
-- bridge, which composes these over cmd/result.
local tools = {}

function tools.status()
  local x, y, z = gps.locate(2)
  local out = {
    id = DEVICE_ID,
    is_turtle = turtle ~= nil,
    pos = x and {x = x, y = y, z = z} or nil,
    peripherals = peripheral.getNames(),
  }
  if turtle then out.fuel = turtle.getFuelLevel() end
  return out
end

function tools.list_chest(args)
  local inv = peripheral.wrap(args.name)
  if not inv then error("no inventory called " .. tostring(args.name)) end
  local items = {}
  for slot, item in pairs(inv.list()) do
    items[#items + 1] = {slot = slot, name = item.name, count = item.count}
  end
  if #items == 0 then items = textutils.empty_json_array end
  return {name = args.name, size = inv.size(), items = items}
end

function tools.push_one_slot(args)
  -- Push one slot of `args.from` into `args.dest` over the wired network
  -- (inventory.pushItems(toName, fromSlot, limit)); the device never carries
  -- the items. `args.limit` is optional: nil pushes the whole stack.
  local src = peripheral.wrap(args.from)
  if not src then error("no inventory called " .. tostring(args.from)) end
  local moved = src.pushItems(args.dest, args.slot, args.limit)
  return {moved = moved}
end

if turtle then
  -- Movement primitives. Keep these small and one-to-one; routines that chain
  -- them (goto, mine_vein...) are composed on the bridge, not written here.
  function tools.move(args)
    local n = args.steps or 1
    local fn = ({forward = turtle.forward, back = turtle.back, up = turtle.up, down = turtle.down})[args.dir]
    if not fn then error("dir must be forward/back/up/down") end
    local done = 0
    for _ = 1, n do if fn() then done = done + 1 else break end end
    return {moved = done, requested = n}
  end

  function tools.turn(args)
    if args.dir == "left" then turtle.turnLeft() else turtle.turnRight() end
    return {ok = true}
  end

  function tools.dig(args)
    local fn = ({forward = turtle.dig, up = turtle.digUp, down = turtle.digDown})[args.dir or "forward"]
    return {dug = fn()}
  end

  function tools.inspect()
    local out = {}
    for name, fn in pairs({forward = turtle.inspect, up = turtle.inspectUp, down = turtle.inspectDown}) do
      local ok, b = fn(); out[name] = ok and b.name or "air"
    end
    return out
  end

  function tools.refuel(args)
    local before = turtle.getFuelLevel()
    for slot = 1, 16 do
      turtle.select(slot)
      if turtle.refuel(0) then turtle.refuel(args.count or 1) end
    end
    turtle.select(1)
    return {before = before, after = turtle.getFuelLevel()}
  end
end

if ALLOW_EVAL then
  function tools.run_lua(args)
    local fn, err = load(args.code, "agent", "t", setmetatable({tools = tools}, {__index = _ENV}))
    if not fn then error("compile: " .. err) end
    local ok, res = pcall(fn)
    if not ok then error("runtime: " .. tostring(res)) end
    return {result = res}
  end
end

---------------------------------------------------------------- connection loop
local function capabilities()
  local caps = {}
  for name in pairs(tools) do caps[#caps + 1] = name end
  table.sort(caps)
  return caps
end

local function session(ws)
  ws.send(textutils.serialiseJSON({
    type = "hello", id = DEVICE_ID, token = TOKEN,
    role = turtle and "turtle" or "computer", caps = capabilities(),
  }))
  log("connected as", DEVICE_ID)

  while true do
    local raw = ws.receive()
    if raw == nil then return end             -- closed
    dbg("recv: " .. raw)
    local msg = textutils.unserialiseJSON(raw)
    if msg and msg.type == "cmd" then
      local tool = tools[msg.tool]
      local reply = {type = "result", cid = msg.cid, ok = false}
      if not tool then
        reply.error = "unknown tool " .. tostring(msg.tool)
      else
        local ok, res = pcall(tool, msg.args or {})
        reply.ok = ok
        if ok then reply.data = res else reply.error = tostring(res) end
      end
      local json = textutils.serialiseJSON(reply)
      dbg("result: " .. json)
      ws.send(json)
    elseif msg and msg.type == "ping" then
      ws.send(textutils.serialiseJSON({type = "pong"}))
    end
  end
end

while true do
  local ws, err = http.websocket(BRIDGE_URL)
  if ws then
    local ok, e = pcall(session, ws)
    if not ok then log("session error:", e) end
    pcall(ws.close)
    log("disconnected, retrying in 5s")
  else
    log("connect failed:", err, "- retrying in 5s")
  end
  sleep(5)
end

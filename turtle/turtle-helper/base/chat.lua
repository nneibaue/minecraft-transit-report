-- chat.lua : ears and mouth. Runs on an Advanced Computer with a Chat Box
-- (Advanced Peripherals) attached. Forwards chat to the bridge and speaks
-- whatever the bridge tells it to. Holds no logic of its own.
--
-- Setup: the in-game installer (install.lua, see README "Setup > 2. In game")
-- writes secret.txt and bridge.txt beside this file. startup.lua runs it on boot,
-- after updating it from main. Without bridge.txt the BRIDGE_URL default below applies.

local BRIDGE_URL   = "ws://127.0.0.1:8765"      -- default; bridge.txt overrides it
local DEVICE_ID    = os.getComputerLabel() or ("device-" .. os.getComputerID())
local SEND_GAP     = 1.1     -- seconds between chat sends (Chat Box cooldown is ~1s by default)
local DEFAULT_NAME = "Robot" -- prefix shown as [Robot]

local chatBox = peripheral.find("chatBox")
if not chatBox then error("no Chat Box attached") end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close(); return s
end
local TOKEN = (readFile("secret.txt") or error("secret.txt missing")):gsub("%s+$", "")
local BRIDGE_FILE = readFile("bridge.txt")
if BRIDGE_FILE then BRIDGE_URL = BRIDGE_FILE:gsub("%s+$", "") end

local function log(...) print(("[%s] "):format(textutils.formatTime(os.time(), true)), ...) end

-- Outbound message queue, drained at SEND_GAP to respect the cooldown.
local outbox = {}
local function drainOutbox()
  while true do
    local m = table.remove(outbox, 1)
    if m then
      local ok, err
      if m.to then
        ok, err = chatBox.sendMessageToPlayer(m.text, m.to, m.prefix or DEFAULT_NAME)
      else
        ok, err = chatBox.sendMessage(m.text, m.prefix or DEFAULT_NAME)
      end
      if not ok then
        log("send failed:", err, "- requeueing")
        table.insert(outbox, 1, m)
      end
      sleep(SEND_GAP)
    else
      sleep(0.2)
    end
  end
end

local function session(ws)
  ws.send(textutils.serialiseJSON({
    type = "hello", id = DEVICE_ID, token = TOKEN, role = "chat", caps = {"say"},
  }))
  log("connected to bridge")

  while true do
    local ev = {os.pullEvent()}
    if ev[1] == "chat" then
      -- ev: "chat", username, message, uuid, isHidden
      ws.send(textutils.serialiseJSON({
        type = "event", name = "chat",
        user = ev[2], text = ev[3], uuid = ev[4], hidden = ev[5] == true,
      }))
    elseif ev[1] == "websocket_message" and ev[2] == BRIDGE_URL then
      local msg = textutils.unserialiseJSON(ev[3])
      if msg and msg.type == "cmd" and msg.tool == "say" then
        table.insert(outbox, {text = msg.args.text, to = msg.args.to, prefix = msg.args.prefix})
        ws.send(textutils.serialiseJSON({type = "result", cid = msg.cid, ok = true, data = {queued = true}}))
      elseif msg and msg.type == "cmd" then
        ws.send(textutils.serialiseJSON({type = "result", cid = msg.cid, ok = false, error = "base only supports say"}))
      elseif msg and msg.type == "ping" then
        ws.send(textutils.serialiseJSON({type = "pong"}))
      end
    elseif ev[1] == "websocket_closed" and ev[2] == BRIDGE_URL then
      return
    end
  end
end

local function connectLoop()
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
end

parallel.waitForAny(connectLoop, drainOutbox)

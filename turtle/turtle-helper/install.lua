-- install.lua : turtle-helper installer.
-- wget run https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/install.lua
-- Installs chat.lua, client.lua and startup.lua from GitHub main and writes bridge.txt and
-- secret.txt. Re-running it is the repair path: it keeps an existing secret.txt.
-- The bridge token is typed here once and is never fetched, printed or sent anywhere by
-- this script; it goes only into secret.txt.

local BASE = "https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/"
local FILES = {
  { "chat.lua", "base/chat.lua" },
  { "client.lua", "turtle/client.lua" },
  { "startup.lua", "startup.lua" },
}
local DEFAULT_URL = "ws://127.0.0.1:8765"
local OUR_STARTUP = "-- startup.lua : turtle-helper"

-- Same contract as startup.lua's fetch; duplicated because this runs from wget before any
-- file exists on the device. The downloaded body, or nil and a short reason. Writes nothing.
local function fetch(name, path)
  if not http then return nil, "http API disabled" end
  local res, err = http.get({ url = BASE .. path, binary = true, timeout = 10 })
  if not res then return nil, err or "download failed" end
  local code = res.getResponseCode()
  local body = res.readAll()
  res.close()
  if code ~= 200 then return nil, "HTTP " .. tostring(code) end
  if not body or body == "" then return nil, "empty download" end
  if body:sub(1, #name + 3) ~= "-- " .. name then return nil, "unexpected content" end
  if not load(body, "=" .. name, "t", {}) then return nil, "does not compile" end
  return body
end

local function readFile(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local h = fs.open(path, "rb"); local s = h.readAll() or ""; h.close(); return s
end

local function writeFile(path, s)
  local h = fs.open(path, "wb"); h.write(s); h.close()
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isBridgeUrl(s)
  return s:sub(1, 5) == "ws://" or s:sub(1, 6) == "wss://"
end

-- a. Say where we are and what will happen, before touching anything.
local id, label = os.getComputerID(), os.getComputerLabel()
if label then
  print("turtle-helper installer on computer " .. id .. " (" .. label .. ")")
else
  print("turtle-helper installer on computer " .. id)
end
print("It will install chat.lua, client.lua and startup.lua, then ask for the bridge token and the bridge URL.")

-- b. Never silently replace another program's startup.lua.
local oldStartup = readFile("startup.lua")
if oldStartup and oldStartup:sub(1, #OUR_STARTUP) ~= OUR_STARTUP then
  print("This computer already runs a different startup program. Installing would replace it.")
  write("Replace it? (y/n) ")
  local answer = read()
  if answer ~= "y" and answer ~= "Y" then
    print("Cancelled. Nothing was changed.")
    return
  end
end

-- c. Download everything into memory first; on any failure nothing is written.
local bodies = {}
for _, file in ipairs(FILES) do
  local name, path = file[1], file[2]
  local body, reason = fetch(name, path)
  if not body then
    printError("Could not download " .. name .. ": " .. tostring(reason)
      .. ". Nothing was changed; check the connection and run the wget line again.")
    return
  end
  bodies[name] = body
end

-- d. Bridge token (D-15): typed once, masked, kept on re-runs.
local newToken
local secretNote = "secret.txt (kept)"
local oldSecret = readFile("secret.txt")
if oldSecret and trim(oldSecret) ~= "" then
  print("Keeping the existing bridge token in secret.txt.")
else
  repeat
    write("Bridge token (typing is hidden): ")
    newToken = trim(read("*") or "")
  until newToken ~= ""
  secretNote = "secret.txt"
end

-- e. Bridge URL (D-17): Enter keeps the current value.
local current = DEFAULT_URL
local oldUrl = readFile("bridge.txt")
if oldUrl and isBridgeUrl(trim(oldUrl)) then current = trim(oldUrl) end
print("Bridge URL (press Enter to keep it):")
local url
while true do
  url = trim(read(nil, nil, nil, current) or "")
  if url == "" then url = current end
  if isBridgeUrl(url) then break end
  print("The bridge URL must start with ws:// or wss://")
end

-- f. Write. A kept secret.txt is never reopened.
for _, file in ipairs(FILES) do
  writeFile(file[1], bodies[file[1]])
end
writeFile("bridge.txt", url)
if newToken then writeFile("secret.txt", newToken) end

-- g. Report.
print("Installed on computer " .. id .. ":")
print("  chat.lua, client.lua, startup.lua, bridge.txt, " .. secretNote)
if fs.exists("startup") and not fs.isDir("startup") then
  print("Note: a program named startup also exists here and runs instead of startup.lua. Rename or delete it so turtle-helper starts on boot.")
end
print("Type reboot to start turtle-helper. After that it updates chat.lua and client.lua from GitHub on every boot.")

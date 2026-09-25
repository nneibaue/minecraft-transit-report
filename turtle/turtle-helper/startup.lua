-- startup.lua : turtle-helper boot. Updates chat.lua and client.lua from GitHub main, then runs chat or client.
-- install.lua (the in-game wget line) or `uv run deploy` puts this file on the device.
-- A computer holding _marker.txt is a deploy-managed developer device: the GitHub step is
-- skipped so a no-push deploy is not overwritten. Delete _marker.txt to return the device
-- to GitHub updates.
-- Lua changes reach devices by pushing to main and rebooting. Raw GitHub can serve the
-- previous file for a few minutes after a push.

local BASE = "https://raw.githubusercontent.com/nneibaue/minecraft-transit-report/main/turtle/turtle-helper/"
local FILES = {
  { "chat.lua", "base/chat.lua" },
  { "client.lua", "turtle/client.lua" },
}

-- The downloaded body, or nil and a short reason. Writes nothing.
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

if fs.exists("_marker.txt") then
  print("Developer device (_marker.txt, managed by uv run deploy): GitHub update skipped")
else
  for _, file in ipairs(FILES) do
    local name, path = file[1], file[2]
    local body, reason = fetch(name, path)
    if body then
      local current
      if fs.exists(name) then
        local h = fs.open(name, "rb"); current = h.readAll(); h.close()
      end
      if current == body then
        print(name .. " up to date")
      else
        local h = fs.open(name, "wb"); h.write(body); h.close()
        print("updated " .. name)
      end
    else
      print(name .. ": " .. tostring(reason) .. "; using the local copy")
    end
  end
end

if peripheral.find("chatBox") then shell.run("chat") else shell.run("client") end

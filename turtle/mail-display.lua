-- =========================================================
-- YOU'VE GOT MAIL!  (gift delivery display)
--
--   1. An envelope drops in and twinkles
--   2. The envelope opens and a card slides out
--   3. The screen flashes "OPEN THE CHEST!" with a chest and arrows
-- =========================================================

-- =========================================================
-- Config
-- =========================================================

local RECIPIENT   = "SAM"
local CHEST_BELOW = true          -- true: arrows point down, false: up
local TEXT_SCALE  = 0.5           -- 0.5 = double resolution
local BG          = colors.blue

-- =========================================================
-- Setup
-- =========================================================

local monitor = peripheral.find("monitor")

if not monitor then
    error("No monitor found!")
end

monitor.setTextScale(TEXT_SCALE)

local W, H = monitor.getSize()

-- Draw every frame off-screen, then show it all at once (no flicker)
local scr = window.create(monitor, 1, 1, W, H, false)

local function present()
    scr.setVisible(true)
    scr.setVisible(false)
end

math.randomseed(os.epoch("utc"))

-- =========================================================
-- Drawing primitives
-- =========================================================

local function fill(color)
    scr.setBackgroundColor(color)
    scr.clear()
end

local function box(x, y, w, h, color)
    if w <= 0 or h <= 0 then return end

    scr.setBackgroundColor(color)
    local row = string.rep(" ", w)

    for yy = y, y + h - 1 do
        scr.setCursorPos(x, yy)
        scr.write(row)
    end
end

local function px(x, y, color)
    box(x, y, 1, 1, color)
end

local function text(x, y, str, fg, bg)
    scr.setCursorPos(x, y)
    scr.setTextColor(fg)
    scr.setBackgroundColor(bg)
    scr.write(str)
end

local function centerText(y, str, fg, bg)
    text(math.floor((W - #str) / 2) + 1, y, str, fg, bg)
end

-- =========================================================
-- Sprites
-- =========================================================

local PALETTE = {
    K = colors.black,
    W = colors.white,
    L = colors.lightGray,
    G = colors.gray,
    R = colors.red,
    O = colors.orange,
    Y = colors.yellow,
    B = colors.brown,
}

-- Draw a pixel-art sprite. "." is transparent.
-- recolor lets a frame swap colors, e.g. { Y = colors.white }
local function sprite(rows, x, y, scale, recolor)
    scale = scale or 1

    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)

            if ch ~= "." then
                local color = (recolor and recolor[ch]) or PALETTE[ch]
                box(x + (c - 1) * scale, y + (r - 1) * scale, scale, scale, color)
            end
        end
    end
end

local HEART = {
    ".RR.RR.",
    "RRRRRRR",
    ".RRRRR.",
    "..RRR..",
    "...R...",
}

local CHEST = {
    "KKKKKKKKKKKKKK",
    "KOOOOOOOOOOOOK",
    "KOBBBBBBBBBBOK",
    "KOBBBBBBBBBBOK",
    "KKKKKKLLKKKKKK",
    "KOOOOOLLOOOOOK",
    "KOBBBBLLBBBBOK",
    "KOBBBBBBBBBBOK",
    "KOBBBBBBBBBBOK",
    "KKKKKKKKKKKKKK",
}

local ARROW = {
    "..YYY..",
    "..YYY..",
    "YYYYYYY",
    ".YYYYY.",
    "..YYY..",
    "...Y...",
}

if not CHEST_BELOW then
    local flipped = {}
    for i = #ARROW, 1, -1 do
        flipped[#flipped + 1] = ARROW[i]
    end
    ARROW = flipped
end

-- =========================================================
-- Big block letters
-- =========================================================

local FONT = {
    ["A"] = { ".#.", "#.#", "###", "#.#", "#.#" },
    ["B"] = { "##.", "#.#", "##.", "#.#", "##." },
    ["C"] = { ".##", "#..", "#..", "#..", ".##" },
    ["D"] = { "##.", "#.#", "#.#", "#.#", "##." },
    ["E"] = { "###", "#..", "##.", "#..", "###" },
    ["F"] = { "###", "#..", "##.", "#..", "#.." },
    ["G"] = { ".##", "#..", "#.#", "#.#", ".##" },
    ["H"] = { "#.#", "#.#", "###", "#.#", "#.#" },
    ["I"] = { "###", ".#.", ".#.", ".#.", "###" },
    ["K"] = { "#.#", "#.#", "##.", "#.#", "#.#" },
    ["L"] = { "#..", "#..", "#..", "#..", "###" },
    ["M"] = { "#...#", "##.##", "#.#.#", "#...#", "#...#" },
    ["N"] = { "#..#", "##.#", "#.##", "#..#", "#..#" },
    ["O"] = { ".#.", "#.#", "#.#", "#.#", ".#." },
    ["P"] = { "##.", "#.#", "##.", "#..", "#.." },
    ["R"] = { "##.", "#.#", "##.", "#.#", "#.#" },
    ["S"] = { ".##", "#..", ".#.", "..#", "##." },
    ["T"] = { "###", ".#.", ".#.", ".#.", ".#." },
    ["U"] = { "#.#", "#.#", "#.#", "#.#", "###" },
    ["V"] = { "#.#", "#.#", "#.#", "#.#", ".#." },
    ["W"] = { "#...#", "#...#", "#.#.#", "##.##", "#...#" },
    ["Y"] = { "#.#", "#.#", ".#.", ".#.", ".#." },
    ["!"] = { "#", "#", "#", ".", "#" },
    ["'"] = { "#", "#", ".", ".", "." },
    [" "] = { "..", "..", "..", "..", ".." },
}

local function bigWidth(str)
    local w = 0

    for i = 1, #str do
        local glyph = FONT[str:sub(i, i)] or FONT[" "]
        w = w + #glyph[1] + 1
    end

    return w - 1
end

local function bigFits(str)
    return bigWidth(str) <= W - 2 and H >= 20
end

local function bigText(y, str, fg, shadow)
    local function pass(dx, dy, color)
        local x = math.floor((W - bigWidth(str)) / 2) + 1 + dx

        for i = 1, #str do
            local glyph = FONT[str:sub(i, i)] or FONT[" "]

            for r = 1, 5 do
                local row = glyph[r]
                for c = 1, #row do
                    if row:sub(c, c) == "#" then
                        px(x + c - 1, y + r - 1 + dy, color)
                    end
                end
            end

            x = x + #glyph[1] + 1
        end
    end

    if shadow then pass(1, 1, shadow) end
    pass(0, 0, fg)
end

-- Big letters when they fit, plain text otherwise
local function headlineHeight(str)
    return bigFits(str) and 6 or 1
end

local function headline(y, str, fg, bg)
    if bigFits(str) then
        bigText(y, str, fg, colors.black)
    else
        centerText(y, str, fg, bg)
    end
end

-- =========================================================
-- Twinkling stars
-- =========================================================

local STAR_CHARS = { ".", "+", "*", "+" }

local function makeStars()
    local stars = {}

    for i = 1, math.floor(W * H / 60) do
        stars[i] = {
            x = math.random(1, W),
            y = math.random(1, H),
            phase = math.random(0, 3),
        }
    end

    return stars
end

local function drawStars(stars, t, bg, dim, bright)
    for _, s in ipairs(stars) do
        local p = (s.phase + t) % 4
        text(s.x, s.y, STAR_CHARS[p + 1], p == 2 and bright or dim, bg)
    end
end

-- =========================================================
-- Envelope
--   flap: "closed" | "flat" | "open"
--   cardRise: how far the card has slid out (open only)
-- =========================================================

local function drawEnvelope(x, y, w, h, flap, cardRise)
    local half  = math.floor(w / 2)
    local depth = math.max(2, math.floor(h * 0.6))

    -- Drop shadow
    box(x + 1, y + h, w, 1, colors.black)
    box(x + w, y + 1, 1, h, colors.black)

    if flap == "closed" then
        -- Sealed envelope
        box(x, y, w, h, colors.white)

        -- Lower folds
        for i = 0, half - 1 do
            local yy = y + h - 1 - math.floor(i * (h * 0.45) / half)
            px(x + i, yy, colors.lightGray)
            px(x + w - 1 - i, yy, colors.lightGray)
        end

        -- Top flap edge
        for i = 0, half - 1 do
            local yy = y + math.floor(i * depth / half)
            px(x + i, yy, colors.gray)
            px(x + w - 1 - i, yy, colors.gray)
        end

        -- Wax seal
        if w >= 14 and h >= 8 then
            sprite(HEART, x + half - 3, y + depth - 3)
        else
            px(x + half - 1, y + depth, colors.red)
            px(x + half, y + depth, colors.red)
        end

        return
    end

    -- Inside of the envelope
    box(x, y, w, h, colors.lightGray)

    if flap == "flat" then
        box(x, y, w, 1, colors.gray)
    else
        -- Flap folded up above the envelope
        for i = 0, half - 1 do
            local top = y - math.floor(i * depth / half)

            box(x + i, top, 1, y - top, colors.lightGray)
            box(x + w - 1 - i, top, 1, y - top, colors.lightGray)

            if y - top > 0 then
                px(x + i, top, colors.gray)
                px(x + w - 1 - i, top, colors.gray)
            end
        end
    end

    -- Card sliding out
    if cardRise then
        local cw, ch = w - 4, h - 2
        local cy = y + 1 - cardRise

        box(x + 2, cy, cw, ch, colors.yellow)

        local label = "\3 FOR " .. RECIPIENT .. " \3"
        if #label > cw then label = RECIPIENT end

        text(x + 2 + math.floor((cw - #label) / 2), cy + 1, label, colors.red, colors.yellow)
    end

    -- Front pocket (covers the bottom of the card)
    local pocketY = y + math.floor(h / 3)
    local pocketH = y + h - pocketY

    box(x, pocketY, w, pocketH, colors.white)

    for i = 0, half - 1 do
        local yy = y + h - 1 - math.floor(i * (pocketH - 1) / half)
        px(x + i, yy, colors.lightGray)
        px(x + w - 1 - i, yy, colors.lightGray)
    end
end

local function envelopeLayout(titleH)
    local top    = 2 + titleH + 1
    local bottom = H - 3
    local avail  = bottom - top + 1

    local ew = math.min(W - 8, 40)
    local eh = math.floor(ew / 2)

    if eh > avail then
        eh = avail
        ew = eh * 2
    end

    ew = ew - ew % 2

    local ex = math.floor((W - ew) / 2) + 1
    local ey = top + math.floor((avail - eh) / 2)

    return ex, ey, ew, eh
end

-- =========================================================
-- Scene 1: YOU'VE GOT MAIL!
-- =========================================================

local TITLE        = "YOU'VE GOT MAIL!"
local TITLE_COLORS = { colors.yellow, colors.white, colors.orange, colors.white }
local WIGGLE       = { 0, 1, 0, -1 }

local function mailScene()
    local th = headlineHeight(TITLE)
    local ex, ey, ew, eh = envelopeLayout(th)
    local stars = makeStars()
    local footer = "SPECIAL DELIVERY FOR " .. RECIPIENT

    local function frame(t, envY, dx, titleColor)
        fill(BG)
        drawStars(stars, t, BG, colors.lightBlue, colors.white)
        headline(2, TITLE, titleColor, BG)
        drawEnvelope(ex + dx, envY, ew, eh, "closed")
        centerText(H - 1, footer, colors.yellow, BG)
        present()
    end

    -- Drop in from the top with a little bounce
    local path = {}
    for yy = -eh, ey, math.max(1, math.floor(eh / 4)) do
        path[#path + 1] = yy
    end
    path[#path + 1] = ey
    path[#path + 1] = ey + 1
    path[#path + 1] = ey

    for t, yy in ipairs(path) do
        frame(t, yy, 0, colors.yellow)
        sleep(0.05)
    end

    -- Twinkle, cycle the title color, and nudge the envelope
    for t = 0, 29 do
        local dx = (t % 10 < 4) and WIGGLE[t % 10 + 1] or 0
        frame(t, ey, dx, TITLE_COLORS[t % 4 + 1])
        sleep(0.1)
    end
end

-- =========================================================
-- Scene 2: the envelope opens
-- =========================================================

local function openScene()
    local ex, ey, ew, eh = envelopeLayout(headlineHeight(TITLE))
    local stars = makeStars()
    local footer = "IT'S FOR YOU, " .. RECIPIENT .. "!"

    local frames = {
        { "closed" },
        { "flat" },
        { "open", 0 },
    }

    for rise = 1, math.floor(eh * 0.6) do
        frames[#frames + 1] = { "open", rise }
    end

    -- Hold on the last frame
    for _ = 1, 12 do
        frames[#frames + 1] = frames[#frames]
    end

    for t, f in ipairs(frames) do
        fill(BG)
        drawStars(stars, t, BG, colors.lightBlue, colors.white)
        drawEnvelope(ex, ey, ew, eh, f[1], f[2])
        centerText(H - 1, footer, colors.yellow, BG)
        present()
        sleep(t <= 3 and 0.2 or 0.08)
    end
end

-- =========================================================
-- Transition flash
-- =========================================================

local function flash()
    for _, c in ipairs({ colors.white, colors.yellow, colors.white }) do
        fill(c)
        present()
        sleep(0.06)
    end
end

-- =========================================================
-- Scene 3: OPEN THE CHEST!
-- =========================================================

local function chestScene()
    local title = "OPEN THE CHEST!"
    local th = headlineHeight(title)

    local top    = 2 + th + 1
    local bottom = H - 3
    local avail  = bottom - top + 1

    local scale = (avail >= 20 and W >= 28 + 2 * (14 + 3) + 2) and 2 or 1
    local cw, ch = 14 * scale, 10 * scale
    local cx = math.floor((W - cw) / 2) + 1
    local cy = top + math.floor((avail - ch) / 2)

    local stars = makeStars()
    local footer = "A GIFT FOR " .. RECIPIENT .. " IS INSIDE"

    for t = 0, 17 do
        local on = t % 2 == 1
        local bg = on and colors.yellow or BG
        local fg = on and BG or colors.yellow

        fill(bg)
        drawStars(stars, t, bg, fg, colors.white)
        headline(2, title, fg, bg)

        if avail >= ch then
            -- Chest with a glowing latch
            sprite(CHEST, cx, cy, scale, { L = on and colors.white or colors.yellow })

            -- Bouncing arrows on both sides
            local bounce = on and 1 or 0
            if not CHEST_BELOW then bounce = -bounce end

            local ay = cy + math.floor((ch - #ARROW * scale) / 2) + bounce
            sprite(ARROW, cx - 7 * scale - 3, ay, scale, { Y = fg })
            sprite(ARROW, cx + cw + 3, ay, scale, { Y = fg })
        end

        centerText(H - 1, footer, fg, bg)
        present()
        sleep(0.35)
    end
end

-- =========================================================
-- Main loop
-- =========================================================

while true do
    mailScene()
    openScene()
    flash()
    chestScene()
end

-------------------------------------------------------------------------------
-- Cursortrails (Turtle / 1.12, round glow trail, with config GUI)
-------------------------------------------------------------------------------

local ADDON_NAME = "Cursortrails"
local CT = CreateFrame("Frame", "CursortrailsFrame", UIParent)

-------------------------------------------------------------------------------
-- Debug helper
-------------------------------------------------------------------------------
local DEBUG_ENABLED = false  -- set true if you want spam

local function Debug(msg)
    if DEBUG_ENABLED and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ff88[Cursortrails DEBUG]|r " .. tostring(msg))
    end
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------
local trailPoints = {}
local trailDots   = {}
local dotPool     = {}

local config = {
    enabled     = false,
    maxPoints   = 40,       -- more points = smoother line
    dotSize     = 12,       -- small round glows
    trailLength = 0.9,      -- seconds until a point fully fades out
    color       = { r = 0.2, g = 0.6, b = 1.0, a = 1.0 }, -- glowing blue
    updateRate  = 0.02,
    minDistance = 0.5,      -- add points frequently for smoothness
}

-------------------------------------------------------------------------------
-- Config accessors for GUI
-------------------------------------------------------------------------------

function Cursortrails_ClearTrail()
    -- hide and recycle dots
    for i = 1, table.getn(trailDots) do
        local dot = trailDots[i]
        if dot then
            dot:Hide()
            dot:ClearAllPoints()
            dotPool[dot] = true
        end
    end

    -- wipe arrays
    trailDots = {}
    trailPoints = {}

    Debug("Trail cleared.")
end

function Cursortrails_Config_GetEnabled()
    return config.enabled and 1 or 0
end

function Cursortrails_Config_SetEnabled(val)
    config.enabled = (val == 1 or val == true)
end

function Cursortrails_Config_GetMaxPoints()
    return config.maxPoints or 40
end

function Cursortrails_Config_SetMaxPoints(v)
    v = tonumber(v) or 40
    if v < 5 then v = 5 end
    if v > 80 then v = 80 end
    config.maxPoints = v
end

function Cursortrails_Config_GetDotSize()
    return config.dotSize or 12
end

function Cursortrails_Config_SetDotSize(v)
    v = tonumber(v) or 12
    if v < 4 then v = 4 end
    if v > 32 then v = 32 end
    config.dotSize = v
end

function Cursortrails_Config_GetTrailLength()
    return config.trailLength or 0.9
end

function Cursortrails_Config_SetTrailLength(v)
    v = tonumber(v) or 0.9
    if v < 0.3 then v = 0.3 end
    if v > 3.0 then v = 3.0 end
    config.trailLength = v
end

function Cursortrails_Config_GetUpdateRate()
    return config.updateRate or 0.02
end

function Cursortrails_Config_SetUpdateRate(v)
    v = tonumber(v) or 0.02
    if v < 0.01 then v = 0.01 end
    if v > 0.05 then v = 0.05 end
    config.updateRate = v
end

function Cursortrails_Config_GetMinDistance()
    return config.minDistance or 0.5
end

function Cursortrails_Config_SetMinDistance(v)
    v = tonumber(v) or 0.5
    if v < 0.1 then v = 0.1 end
    if v > 10 then v = 10 end
    config.minDistance = v
end

local lastUpdate   = 0
local debugTickAcc = 0

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function Distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx*dx + dy*dy)
end

-------------------------------------------------------------------------------
-- Color picker helpers
-------------------------------------------------------------------------------
local Cursortrails_ColorPrev = nil

local function Cursortrails_Config_UpdateColorSwatch()
    local tex = getglobal("CursortrailsColorSwatchTexture")
    if tex then
        tex:SetVertexColor(config.color.r, config.color.g, config.color.b, config.color.a or 1.0)
    end
end

function Cursortrails_Config_SetColor(r, g, b, a)
    config.color.r = r or config.color.r
    config.color.g = g or config.color.g
    config.color.b = b or config.color.b
    config.color.a = a or config.color.a
    Cursortrails_Config_UpdateColorSwatch()
end

-- Called when color picker changes (and on opacity change)
local function Cursortrails_ColorPickerCallback()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = 1.0
    if OpacitySliderFrame and ColorPickerFrame.hasOpacity then
        a = 1 - OpacitySliderFrame:GetValue()
    end
    Cursortrails_Config_SetColor(r, g, b, a)
end

-- Called when user hits cancel in color picker
local function Cursortrails_ColorPickerCancel(prev)
    if not prev then return end
    Cursortrails_Config_SetColor(prev.r, prev.g, prev.b, prev.a)
end

function Cursortrails_OpenColorPicker()
    if not ColorPickerFrame then return end

    Cursortrails_ColorPrev = {
        r = config.color.r,
        g = config.color.g,
        b = config.color.b,
        a = config.color.a or 1.0
    }

    ColorPickerFrame.func = Cursortrails_ColorPickerCallback
    ColorPickerFrame.opacityFunc = Cursortrails_ColorPickerCallback
    ColorPickerFrame.cancelFunc = function()
        Cursortrails_ColorPickerCancel(Cursortrails_ColorPrev)
    end

    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity = 1 - (config.color.a or 1.0)
    ColorPickerFrame:SetColorRGB(config.color.r, config.color.g, config.color.b)

    ShowUIPanel(ColorPickerFrame)
end

-- Refresh all controls when the frame opens
function Cursortrails_Config_Refresh()
    if not CursortrailsConfigFrame then return end

    if CursortrailsEnableCheck then
        CursortrailsEnableCheck:SetChecked(Cursortrails_Config_GetEnabled())
    end

    if CursortrailsMaxPointsSlider then
        CursortrailsMaxPointsSlider:SetValue(Cursortrails_Config_GetMaxPoints())
    end
    if CursortrailsDotSizeSlider then
        CursortrailsDotSizeSlider:SetValue(Cursortrails_Config_GetDotSize())
    end
    if CursortrailsTrailLengthSlider then
        CursortrailsTrailLengthSlider:SetValue(Cursortrails_Config_GetTrailLength())
    end
    if CursortrailsUpdateRateSlider then
        CursortrailsUpdateRateSlider:SetValue(Cursortrails_Config_GetUpdateRate())
    end
    if CursortrailsMinDistanceSlider then
        CursortrailsMinDistanceSlider:SetValue(Cursortrails_Config_GetMinDistance())
    end

    Cursortrails_Config_UpdateColorSwatch()
end

-------------------------------------------------------------------------------
-- Dot creation (round glow texture)
-------------------------------------------------------------------------------
local function CreateTrailDot()
    local dot = CT:CreateTexture(nil, "OVERLAY")

    -- Fallback if texture missing: simple background
    if not dot:GetTexture() then
        dot:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        Debug("roundglow.tga missing, using fallback square texture.")
    end

    dot:SetBlendMode("ADD")
    dot:Hide()

    Debug("Created new dot texture.")
    return dot
end

local function GetDot()
    local dot = next(dotPool)
    if dot then
        dotPool[dot] = nil
        return dot
    end
    return CreateTrailDot()
end

local function ReleaseDot(dot)
    dot:Hide()
    dot:ClearAllPoints()
    dotPool[dot] = true
end

-- Dots positioned exactly at the cursor, like MouseHighlightCircle
local function CreateDotAtPoint(p, alpha)
    local dot = GetDot()
    dot:SetWidth(config.dotSize)
    dot:SetHeight(config.dotSize)

    dot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
    dot:SetVertexColor(config.color.r, config.color.g, config.color.b, alpha)
    dot:Show()
    return dot
end

-------------------------------------------------------------------------------
-- Main update (vanilla-style: uses arg1)
-------------------------------------------------------------------------------
local function OnUpdate()
    local elapsed = arg1  -- 1.12 style
    if not elapsed then
        return
    end

    if not config.enabled then return end

    lastUpdate = lastUpdate + elapsed
    if lastUpdate < config.updateRate then return end
    lastUpdate = 0

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    x, y = x / scale, y / scale

    local now = GetTime()

    ---------------------------------------------------------------------------
    -- 1) Decide whether to add a new point (based on movement)
    ---------------------------------------------------------------------------
    local shouldAdd = true
    local pointCount = table.getn(trailPoints)
    if pointCount > 0 then
        local last = trailPoints[1]
        if Distance(last.x, last.y, x, y) < config.minDistance then
            shouldAdd = false
        end
    end

    if shouldAdd then
        table.insert(trailPoints, 1, { x = x, y = y, time = now })
    end

    ---------------------------------------------------------------------------
    -- 2) Remove old points (age > trailLength)
    ---------------------------------------------------------------------------
    pointCount = table.getn(trailPoints)
    for i = pointCount, 1, -1 do
        if now - trailPoints[i].time > config.trailLength then
            table.remove(trailPoints, i)
        end
    end

    -- 3) Limit total number of points
    while table.getn(trailPoints) > config.maxPoints do
        table.remove(trailPoints)
    end

    ---------------------------------------------------------------------------
    -- 4) Clear old dots and rebuild from current points
    --    This happens even when the mouse is still, so they fade out in place.
    ---------------------------------------------------------------------------
    local dotCount = table.getn(trailDots)
    for i = 1, dotCount do
        ReleaseDot(trailDots[i])
    end
    trailDots = {}

    pointCount = table.getn(trailPoints)
    for i = 1, pointCount do
        local p = trailPoints[i]
        local age   = (now - p.time) / config.trailLength
        local alpha = (1 - age) * config.color.a
        if alpha > 0.05 then
            local dot = CreateDotAtPoint(p, alpha)
            table.insert(trailDots, dot)
        end
    end

    ---------------------------------------------------------------------------
    -- 5) Debug info (optional)
    ---------------------------------------------------------------------------
    debugTickAcc = debugTickAcc + elapsed
    if debugTickAcc > 0.5 then
        Debug(string.format("OnUpdate: cursor=(%.1f, %.1f), points=%d", x, y, pointCount))
        debugTickAcc = 0
    end
end

CT:SetScript("OnUpdate", OnUpdate)
CT:Show()   -- ensure OnUpdate runs

-------------------------------------------------------------------------------
-- Test helper: spawn a big dot in center with /ctr test
-------------------------------------------------------------------------------
local function SpawnTestDot()
    local dot = GetDot()
    dot:SetWidth(64)
    dot:SetHeight(64)
    dot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dot:SetVertexColor(1, 0, 0, 0.9) -- bright red
    dot:Show()
    Debug("Spawned TEST dot in screen center.")
end

-------------------------------------------------------------------------------
-- Slash commands: /cursortrails, /ctr, /ctf, /ctrdebug
-------------------------------------------------------------------------------
SLASH_CURSORTRAILS1 = "/cursortrails"
SLASH_CURSORTRAILS2 = "/ctr"
SLASH_CURSORTRAILS3 = "/ctrdebug"
SLASH_CURSORTRAILS4 = "/ctf"   -- extra alias if you like using /ctf

SlashCmdList.CURSORTRAILS = function(msg)
    msg = msg or ""
    -- trim leading spaces
    while string.sub(msg, 1, 1) == " " do
        msg = string.sub(msg, 2)
    end

    local lower = string.lower(msg)

    -- open/close config GUI
    if lower == "config" or lower == "options" or lower == "ui" then
        if CursortrailsConfigFrame then
            if CursortrailsConfigFrame:IsShown() then
                CursortrailsConfigFrame:Hide()
            else
                CursortrailsConfigFrame:Show()
            end
        else
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("Cursortrails: config frame not loaded (XML missing in TOC?).")
            end
        end
        return
    end

    if lower == "debug" then
        DEBUG_ENABLED = not DEBUG_ENABLED
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Cursortrails debug: " .. tostring(DEBUG_ENABLED))
        end
        return
    end

    if lower == "on" then
        config.enabled = true
        Debug("Enabled")
        return
    elseif lower == "off" then
        elseif lower == "off" then
        config.enabled = false
        Cursortrails_ClearTrail()
        Debug("Disabled")
        return
    elseif lower == "test" then
        SpawnTestDot()
        return
    end

    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ff88Cursortrails commands:|r")
        DEFAULT_CHAT_FRAME:AddMessage("/ctr on       - enable")
        DEFAULT_CHAT_FRAME:AddMessage("/ctr off      - disable")
        DEFAULT_CHAT_FRAME:AddMessage("/ctr test     - spawn test dot in center")
        DEFAULT_CHAT_FRAME:AddMessage("/ctr config   - open/close options window")
        DEFAULT_CHAT_FRAME:AddMessage("/ctrdebug     - toggle debug messages")
    end
end

-------------------------------------------------------------------------------
-- Simple load message
-------------------------------------------------------------------------------
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCursortrails|r loaded. Use |cff88ff88/ctr config|r for options.")
    Cursortrails_ClearTrail()
    Debug("Lua version: " .. tostring(_VERSION or "unknown"))
end

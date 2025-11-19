-------------------------------------------------------------------------------
-- Cursortrails (Turtle / 1.12, round glow trail with config + SavedVariables)
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
-- Defaults + SavedVariables hookup
-------------------------------------------------------------------------------
local defaultConfig = {
    enabled     = false,   -- default OFF
    maxPoints   = 40,
    dotSize     = 12,
    trailLength = 0.9,
    color       = { r = 0.2, g = 0.6, b = 1.0, a = 1.0 },
    updateRate  = 0.02,
    minDistance = 0.5,
}

-- runtime config table; will be pointed at SavedVariables after VARIABLES_LOADED
local config = defaultConfig

local function Cursortrails_InitConfig()
    -- SavedVariables table from TOC: ## SavedVariables: CursortrailsConfig
    if type(CursortrailsConfig) ~= "table" then
        CursortrailsConfig = {}
    end
    if type(CursortrailsConfig.color) ~= "table" then
        CursortrailsConfig.color = {}
    end

    -- merge defaults into SavedVariables (only fill nils)
    for k, v in pairs(defaultConfig) do
        if k ~= "color" then
            if CursortrailsConfig[k] == nil then
                CursortrailsConfig[k] = v
            end
        end
    end
    for ck, cv in pairs(defaultConfig.color) do
        if CursortrailsConfig.color[ck] == nil then
            CursortrailsConfig.color[ck] = cv
        end
    end

    config = CursortrailsConfig
    Debug("Cursortrails_InitConfig: config now bound to CursortrailsConfig")
end

-- ensure we hook AFTER SavedVariables are applied
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("VARIABLES_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        Cursortrails_InitConfig()
    end
end)

-------------------------------------------------------------------------------
-- Trail state
-------------------------------------------------------------------------------
local lastUpdate   = 0
local debugTickAcc = 0

local trailPoints = {}
local trailDots   = {}
local dotPool     = {}

-------------------------------------------------------------------------------
-- Trail clearing
-------------------------------------------------------------------------------
function Cursortrails_ClearTrail()
    for i = 1, table.getn(trailDots) do
        local dot = trailDots[i]
        if dot then
            dot:Hide()
            dot:ClearAllPoints()
            dotPool[dot] = true
        end
    end
    trailDots   = {}
    trailPoints = {}
    Debug("Trail cleared.")
end

-------------------------------------------------------------------------------
-- Config accessors for GUI
-------------------------------------------------------------------------------
function Cursortrails_Config_GetEnabled()
    return (config.enabled and 1) or 0
end

function Cursortrails_Config_SetEnabled(val)
    if config == nil then return end
    config.enabled = (val == 1 or val == true)
end

function Cursortrails_Config_GetMaxPoints()
    if not config then return defaultConfig.maxPoints end
    return config.maxPoints or defaultConfig.maxPoints
end

function Cursortrails_Config_SetMaxPoints(v)
    if not config then return end
    v = tonumber(v) or defaultConfig.maxPoints
    if v < 5 then v = 5 end
    if v > 80 then v = 80 end
    config.maxPoints = v
end

function Cursortrails_Config_GetDotSize()
    if not config then return defaultConfig.dotSize end
    return config.dotSize or defaultConfig.dotSize
end

function Cursortrails_Config_SetDotSize(v)
    if not config then return end
    v = tonumber(v) or defaultConfig.dotSize
    if v < 4 then v = 4 end
    if v > 32 then v = 32 end
    config.dotSize = v
end

function Cursortrails_Config_GetTrailLength()
    if not config then return defaultConfig.trailLength end
    return config.trailLength or defaultConfig.trailLength
end

function Cursortrails_Config_SetTrailLength(v)
    if not config then return end
    v = tonumber(v) or defaultConfig.trailLength
    if v < 0.3 then v = 0.3 end
    if v > 3.0 then v = 3.0 end
    config.trailLength = v
end

function Cursortrails_Config_GetUpdateRate()
    if not config then return defaultConfig.updateRate end
    return config.updateRate or defaultConfig.updateRate
end

function Cursortrails_Config_SetUpdateRate(v)
    if not config then return end
    v = tonumber(v) or defaultConfig.updateRate
    if v < 0.01 then v = 0.01 end
    if v > 0.05 then v = 0.05 end
    config.updateRate = v
end

function Cursortrails_Config_GetMinDistance()
    if not config then return defaultConfig.minDistance end
    return config.minDistance or defaultConfig.minDistance
end

function Cursortrails_Config_SetMinDistance(v)
    if not config then return end
    v = tonumber(v) or defaultConfig.minDistance
    if v < 0.1 then v = 0.1 end
    if v > 10 then v = 10 end
    config.minDistance = v
end

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
    if tex and config and config.color then
        tex:SetVertexColor(config.color.r, config.color.g, config.color.b, config.color.a or 1.0)
    end
end

function Cursortrails_Config_SetColor(r, g, b, a)
    if not config then return end
    if not config.color then
        config.color = {}
    end
    config.color.r = r or config.color.r or defaultConfig.color.r
    config.color.g = g or config.color.g or defaultConfig.color.g
    config.color.b = b or config.color.b or defaultConfig.color.b
    config.color.a = a or config.color.a or defaultConfig.color.a
    Cursortrails_Config_UpdateColorSwatch()
end

local function Cursortrails_ColorPickerCallback()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    local a = 1.0
    if OpacitySliderFrame and ColorPickerFrame.hasOpacity then
        a = 1 - OpacitySliderFrame:GetValue()
    end
    Cursortrails_Config_SetColor(r, g, b, a)
end

local function Cursortrails_ColorPickerCancel(prev)
    if not prev then return end
    Cursortrails_Config_SetColor(prev.r, prev.g, prev.b, prev.a)
end

function Cursortrails_OpenColorPicker()
    if not ColorPickerFrame then return end
    if not config then return end

    if not config.color then
        config.color = {}
        config.color.r = defaultConfig.color.r
        config.color.g = defaultConfig.color.g
        config.color.b = defaultConfig.color.b
        config.color.a = defaultConfig.color.a
    end

    Cursortrails_ColorPrev = {
        r = config.color.r,
        g = config.color.g,
        b = config.color.b,
        a = config.color.a or 1.0
    }

    ColorPickerFrame.func        = Cursortrails_ColorPickerCallback
    ColorPickerFrame.opacityFunc = Cursortrails_ColorPickerCallback
    ColorPickerFrame.cancelFunc  = function()
        Cursortrails_ColorPickerCancel(Cursortrails_ColorPrev)
    end

    ColorPickerFrame.hasOpacity = true
    ColorPickerFrame.opacity    = 1 - (config.color.a or 1.0)
    ColorPickerFrame:SetColorRGB(config.color.r, config.color.g, config.color.b)

    ShowUIPanel(ColorPickerFrame)
end

function Cursortrails_Config_Refresh()
    -- Called from XML OnShow
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

    -- if you have Interface\AddOns\Cursortrails\roundglow.tga, use this:
    dot:SetTexture("Interface\\AddOns\\Cursortrails\\roundglow.tga")

    -- Fallback if texture missing
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

local function CreateDotAtPoint(p, alpha)
    local dotSize = defaultConfig.dotSize
    if config and config.dotSize then
        dotSize = config.dotSize
    end

    local dot = GetDot()
    dot:SetWidth(dotSize)
    dot:SetHeight(dotSize)

    dot:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)

    local col = defaultConfig.color
    if config and config.color then
        col = config.color
    end

    dot:SetVertexColor(col.r, col.g, col.b, alpha)
    dot:Show()
    return dot
end

-------------------------------------------------------------------------------
-- Main update (vanilla-style: uses arg1)
-------------------------------------------------------------------------------
local function OnUpdate()
    local elapsed = arg1  -- 1.12 uses global arg1
    if not elapsed then
        return
    end

    -- If SavedVariables not bound yet, skip
    if not config then return end

    if not config.enabled then return end

    lastUpdate = lastUpdate + elapsed
    local updRate = config.updateRate or defaultConfig.updateRate
    if lastUpdate < updRate then return end
    lastUpdate = 0

    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    x, y = x / scale, y / scale

    local now = GetTime()

    -- 1) Maybe add new point
    local shouldAdd   = true
    local pointCount  = table.getn(trailPoints)
    local minDist     = config.minDistance or defaultConfig.minDistance

    if pointCount > 0 then
        local last = trailPoints[1]
        if Distance(last.x, last.y, x, y) < minDist then
            shouldAdd = false
        end
    end

    if shouldAdd then
        table.insert(trailPoints, 1, { x = x, y = y, time = now })
    end

    -- 2) Remove old points
    local tLen = config.trailLength or defaultConfig.trailLength
    pointCount = table.getn(trailPoints)
    for i = pointCount, 1, -1 do
        if now - trailPoints[i].time > tLen then
            table.remove(trailPoints, i)
        end
    end

    -- 3) Limit number of points
    local maxP = config.maxPoints or defaultConfig.maxPoints
    while table.getn(trailPoints) > maxP do
        table.remove(trailPoints)
    end

    -- 4) Rebuild dots
    local dotCount = table.getn(trailDots)
    for i = 1, dotCount do
        ReleaseDot(trailDots[i])
    end
    trailDots = {}

    pointCount = table.getn(trailPoints)
    local col = (config and config.color) or defaultConfig.color
    for i = 1, pointCount do
        local p     = trailPoints[i]
        local age   = (now - p.time) / tLen
        local alpha = (1 - age) * (col.a or defaultConfig.color.a)
        if alpha > 0.05 then
            local dot = CreateDotAtPoint(p, alpha)
            table.insert(trailDots, dot)
        end
    end

    -- 5) Debug info
    debugTickAcc = debugTickAcc + elapsed
    if debugTickAcc > 0.5 then
        Debug(string.format("OnUpdate: points=%d", pointCount))
        debugTickAcc = 0
    end
end

CT:SetScript("OnUpdate", OnUpdate)
CT:Show()

-------------------------------------------------------------------------------
-- Test helper: spawn a big dot in center with /ctr test
-------------------------------------------------------------------------------
local function SpawnTestDot()
    local dot = GetDot()
    dot:SetWidth(64)
    dot:SetHeight(64)
    dot:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dot:SetVertexColor(1, 0, 0, 0.9)
    dot:Show()
    Debug("Spawned TEST dot in screen center.")
end

-------------------------------------------------------------------------------
-- Slash commands: /cursortrails, /ctr, /ctf, /ctrdebug
-------------------------------------------------------------------------------
SLASH_CURSORTRAILS1 = "/cursortrails"
SLASH_CURSORTRAILS2 = "/ctr"
SLASH_CURSORTRAILS3 = "/ctrdebug"
SLASH_CURSORTRAILS4 = "/ctf"

SlashCmdList.CURSORTRAILS = function(msg)
    msg = msg or ""
    while string.sub(msg, 1, 1) == " " do
        msg = string.sub(msg, 2)
    end

    local lower = string.lower(msg)

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
        if config then
            config.enabled = true
            Debug("Enabled")
        end
        return
    elseif lower == "off" then
        if config then
            config.enabled = false
        end
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
        DEFAULT_CHAT_FRAME:AddMessage("/ctr off      - disable & clear")
        DEFAULT_CHAT_FRAME:AddMessage("/ctr test     - spawn test dot in center")
        DEFAULT_CHAT_FRAME:AddMessage("/ctr config   - open/close options window")
        DEFAULT_CHAT_FRAME:AddMessage("/ctrdebug     - toggle debug messages")
    end
end

-------------------------------------------------------------------------------
-- Load message
-------------------------------------------------------------------------------
if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCursortrails|r loaded. Use |cff88ff88/ctr config|r for options.")
end

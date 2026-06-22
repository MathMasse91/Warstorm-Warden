-- =====================================================
-- Warden - UI_Minimap.lua
-- Draggable minimap button.
--   Left-click  : toggle master window
--   Right-click : open Help tab
--   Drag        : orbit around minimap (angle saved in DB.minimapAngle)
-- =====================================================

local _, ns = ...

ns.UI.Minimap = ns.UI.Minimap or {}

local button
local DEFAULT_ANGLE = 225
local RADIUS        = 80

local function getAngle()
    local db = ns.Persistence and ns.Persistence.DB
    local a  = db and tonumber(db.minimapAngle)
    if type(a) ~= "number" then a = DEFAULT_ANGLE end
    return a
end

local function setAngle(a)
    local db = ns.Persistence and ns.Persistence.DB
    if db then db.minimapAngle = a end
end

local function updatePosition()
    if not button or not Minimap then return end
    local a = math.rad(getAngle())
    local x = math.cos(a) * RADIUS
    local y = math.sin(a) * RADIUS
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function onDragUpdate(self)
    local mx, my    = Minimap:GetCenter()
    local scale     = Minimap:GetEffectiveScale()
    local cx, cy    = GetCursorPosition()
    cx, cy          = cx / scale, cy / scale
    local dx, dy    = cx - mx, cy - my
    local a         = math.deg(math.atan2(dy, dx))
    if a < 0 then a = a + 360 end
    setAngle(a)
    updatePosition()
end

local function buildButton()
    button = CreateFrame("Button", "WardenMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetSize(32, 32)
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    -- TASKS.md §7.1: use the shipped 32x32 TGA full-size with no addon-drawn
    -- ring. The asset already includes its own rim; drawing the Blizzard
    -- tracking-border on top of it cropped the W glyph.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\Warden\\ImageD\\assets\\warden_minimap_32")
    icon:SetSize(32, 32)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0, 1, 0, 1) -- no cropping
    button.icon = icon

    -- Highlight
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop",  function(self) self:SetScript("OnUpdate", nil) end)

    button:SetScript("OnClick", function(_, btnKind)
        if ns.DebugF then
            ns.DebugF("minimap", "click %s (shift=%s)",
                tostring(btnKind), IsShiftKeyDown() and "Y" or "N")
        end
        if btnKind == "RightButton" then
            if ns.UI.Master then ns.UI.Master.ShowTab("Help") end
            return
        end
        if btnKind == "MiddleButton" then
            if ns.WardenSword and ns.WardenSword.Toggle then ns.WardenSword.Toggle() end
            return
        end
        -- Shift-left opens Settings scrolled to the WardenSword section.
        if btnKind == "LeftButton" and IsShiftKeyDown() then
            if ns.UI.Master then ns.UI.Master.ShowTab("Settings") end
            return
        end
        if ns.UI.Master and ns.UI.Master.Toggle then ns.UI.Master.Toggle() end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Warden", 1, 1, 1)
        GameTooltip:AddLine(ns.Colors.key .. "Left-click" .. ns.Colors.reset .. ": toggle main window", 1, 1, 1)
        GameTooltip:AddLine(ns.Colors.key .. "Shift-left" .. ns.Colors.reset .. ": open Settings", 1, 1, 1)
        GameTooltip:AddLine(ns.Colors.key .. "Middle-click" .. ns.Colors.reset .. ": toggle WardenSword HUD", 1, 1, 1)
        GameTooltip:AddLine(ns.Colors.key .. "Right-click" .. ns.Colors.reset .. ": open Help tab", 1, 1, 1)
        GameTooltip:AddLine(ns.Colors.key .. "Drag" .. ns.Colors.reset .. ": orbit the minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
end

-- Wait for SavedVariables so we can read stored angle on first load.
local loader = CreateFrame("Frame", "WardenMinimapLoader")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not button then buildButton() end
end)

-- Optional: hide the minimap button during combat when sword.hideMinimapCombat
-- is set, so it can't be mis-clicked while the HUD is the intended surface.
local combatHook = CreateFrame("Frame", "WardenMinimapCombatHook")
combatHook:RegisterEvent("PLAYER_REGEN_DISABLED")
combatHook:RegisterEvent("PLAYER_REGEN_ENABLED")
combatHook:SetScript("OnEvent", function(_, event)
    if not button then return end
    local sw = ns.Persistence and ns.Persistence.DB and ns.Persistence.DB.sword
    if not sw or not sw.hideMinimapCombat then
        if not button:IsShown() then button:Show() end
        return
    end
    if ns.DebugF then
        ns.DebugF("minimap", "combat hook: %s -> %s", event,
            event == "PLAYER_REGEN_DISABLED" and "hide" or "show")
    end
    if event == "PLAYER_REGEN_DISABLED" then button:Hide()
    else button:Show() end
end)

function ns.UI.Minimap.Refresh()
    if button then updatePosition() end
end

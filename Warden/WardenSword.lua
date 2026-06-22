-- =====================================================
-- Warden - WardenSword.lua
-- Mid-fight HUD surface. Small draggable Panel that exposes the handful
-- of Warden actions a raid commander hits while tanking. Reuses Warden's
-- existing engine; this file only builds the frame, routes clicks, and
-- persists position / lock / visibility to WardenDB.sword.
-- =====================================================

local _, ns = ...
ns.WardenSword = ns.WardenSword or {}

-- ----------------------------------------------------------
-- Density presets (width / button height). Brief specifies three sizes.
-- ----------------------------------------------------------
local DENSITIES = {
    tiny    = { w = 210, btnH = 18 },
    compact = { w = 240, btnH = 22 },
    normal  = { w = 270, btnH = 26 },
}
local HEADER_H   = 22
local STATUS_H   = 18
local PAD        = 8
local GAP        = 6

-- ----------------------------------------------------------
-- State
-- ----------------------------------------------------------
local frame          -- top-level HUD frame
local bodyWidgets = {}

-- ----------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------
local function db() return ns.Persistence and ns.Persistence.DB end
local function sw() local d = db(); return d and d.sword end

local function currentDensity()
    local s = sw()
    local key = s and s.density or "compact"
    return DENSITIES[key] or DENSITIES.compact
end

-- Pulse an action button on click (gold rim flash, 120ms).
local function pulseBtn(btn)
    if not btn or not btn.SetBackdropBorderColor then return end
    btn._pulse = 0
    btn:SetBackdropBorderColor(1.00, 0.82, 0.00, 1)
    btn:SetScript("OnUpdate", function(self, elapsed)
        self._pulse = (self._pulse or 0) + elapsed
        if self._pulse >= 0.12 then
            -- restore the token rim
            local rim = self._tokRim or { 0.23, 0.18, 0.13 }
            self:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Run an action by key with button-pulse feedback.
local function fireAction(key, btn)
    local fn = ns.WardenSword.Actions and ns.WardenSword.Actions[key]
    if not fn then return end
    fn()
    if btn then pulseBtn(btn) end
end

-- ----------------------------------------------------------
-- Frame construction
-- ----------------------------------------------------------
local function buildHeader(parent, width)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HEADER_H)
    h:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, 0)
    h:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", h, "LEFT", PAD, 0)
    title:SetText("WARDENSWORD")
    title:SetTextColor(1.00, 0.82, 0.00, 1)
    local hint = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 6, 0)
    hint:SetText("/ws")
    hint:SetTextColor(0.55, 0.50, 0.42, 1)

    -- Close X (red glyph) on the far right.
    local close = CreateFrame("Button", nil, h)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", h, "RIGHT", -PAD, 0)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x")
    cfs:SetTextColor(0.85, 0.18, 0.12, 1)
    close:SetScript("OnClick", function() ns.WardenSword.Hide() end)

    -- Lock toggle just left of close. Open/closed circle glyph.
    local lock = CreateFrame("Button", nil, h)
    lock:SetSize(16, 16)
    lock:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local lfs = lock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lfs:SetPoint("CENTER", lock, "CENTER", 0, 0)
    lock.fs = lfs
    lock:SetScript("OnClick", function() ns.WardenSword.ToggleLock() end)
    h.lockBtn = lock

    -- Divider line under the header
    local rule = h:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(0.23, 0.18, 0.13, 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT",  h, "BOTTOMLEFT",  0, 0)
    rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    return h
end

local function refreshLockButton(lockBtn)
    local s = sw()
    if not lockBtn or not lockBtn.fs then return end
    if s and s.locked then
        lockBtn.fs:SetText("*")
        lockBtn.fs:SetTextColor(1.00, 0.82, 0.00, 1)
    else
        lockBtn.fs:SetText("o")
        lockBtn.fs:SetTextColor(0.55, 0.50, 0.42, 1)
    end
end

local function buildStatusStrip(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(STATUS_H)
    local fs = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("LEFT", s, "LEFT", PAD, 0)
    fs:SetTextColor(0.72, 0.58, 0.21, 1)
    s.fs = fs
    return s
end

-- Capture the rim tokens so pulseBtn can restore them.
local function tagRim(btn, rim)
    btn._tokRim = rim
    return btn
end

local function buildMovementGrid(parent)
    local g = CreateFrame("Frame", nil, parent)

    -- Buttons are created at a placeholder size; layout() is the single
    -- source of truth for width + height + position and will re-flow them
    -- whenever the density changes.
    local summon = ns.UI.Button.red(g, "Summon", 80, 22)
    tagRim(summon, ns.Tokens.red_btn)
    summon:SetScript("OnClick", function(self) fireAction("summon", self) end)

    local follow = ns.UI.Button.stone(g, "Follow", 80, 22)
    tagRim(follow, ns.Tokens.stone_rim)
    follow:SetScript("OnClick", function(self) fireAction("follow", self) end)

    local stay = ns.UI.Button.stone(g, "Stay", 80, 22)
    tagRim(stay, ns.Tokens.stone_rim)
    stay:SetScript("OnClick", function(self) fireAction("stay", self) end)

    local flee = ns.UI.Button.warn(g, "Flee", 80, 22)
    tagRim(flee, ns.Tokens.stone_rim)
    flee:SetScript("OnClick", function(self) fireAction("flee", self) end)

    bodyWidgets.movement     = g
    bodyWidgets.movementBtns = { summon, follow, stay, flee }
    return g
end

local function buildStrategyRow(parent)
    local g = CreateFrame("Frame", nil, parent)

    local aoe = ns.UI.Button.stone(g, "AoE", 60, 22)
    tagRim(aoe, ns.Tokens.stone_rim)
    aoe:SetScript("OnClick", function(self)
        local on = fireAction("aoe", self)
        local fs = self:GetFontString()
        if fs then
            if on then fs:SetTextColor(1.00, 0.82, 0.00)
            else fs:SetTextColor(0.72, 0.58, 0.21) end
        end
    end)

    local burn = ns.UI.Button.stone(g, "Burn", 60, 22)
    tagRim(burn, ns.Tokens.stone_rim)
    burn:SetScript("OnClick", function(self)
        local on = fireAction("burn", self)
        local fs = self:GetFontString()
        if fs then
            if on then fs:SetTextColor(1.00, 0.82, 0.00)
            else fs:SetTextColor(0.72, 0.58, 0.21) end
        end
    end)

    local skull = ns.UI.Button.stone(g, "Skull", 60, 22)
    tagRim(skull, ns.Tokens.stone_rim)
    skull:SetScript("OnClick", function(self) fireAction("skull", self) end)

    bodyWidgets.strategy     = g
    bodyWidgets.strategyBtns = { aoe, burn, skull }
    return g
end

local function buildRoleMatrix(parent)
    local g = CreateFrame("Frame", nil, parent)

    local rows = { "tank", "heal", "dps" }
    local ROLE_LBL = { tank = "TANK", heal = "HEAL", dps = "DPS" }
    local rowData = {}

    for i, role in ipairs(rows) do
        local lbl = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetText(ROLE_LBL[role])
        lbl:SetTextColor(0.72, 0.58, 0.21, 1)

        local fol = ns.UI.Button.stone(g, "Follow", 60, 22)
        tagRim(fol, ns.Tokens.stone_rim)
        fol:SetScript("OnClick", function(self)
            fireAction("@" .. role .. " follow", self)
        end)

        local atk = ns.UI.Button.red(g, "Atk", 60, 22)
        tagRim(atk, ns.Tokens.red_btn)
        atk:SetScript("OnClick", function(self)
            fireAction("@" .. role .. " attack", self)
        end)

        local st = ns.UI.Button.stone(g, "Stay", 60, 22)
        tagRim(st, ns.Tokens.stone_rim)
        st:SetScript("OnClick", function(self)
            fireAction("@" .. role .. " stay", self)
        end)

        rowData[i] = { lbl = lbl, follow = fol, atk = atk, stay = st, role = role }
    end

    bodyWidgets.roles    = g
    bodyWidgets.roleRows = rowData
    return g
end

local function buildBloodlust(parent)
    local g = CreateFrame("Frame", nil, parent)
    -- Stone variant so we can recolor in RefreshBLButton to reflect state.
    local b = ns.UI.Button.stone(g, "BLOODLUST", 200, 22)
    tagRim(b, ns.Tokens.red_btn)
    b:SetScript("OnClick", function(self)
        fireAction("bl", self)
        if ns.WardenSword.RefreshBLButton then ns.WardenSword.RefreshBLButton() end
    end)
    bodyWidgets.bloodlust     = g
    bodyWidgets.bloodlustBtn  = b
    return g
end

-- Repaint the BLOODLUST button so it advertises the current db.bloodlust
-- state. Called by the 0.5s status ticker and by the BL button OnClick.
function ns.WardenSword.RefreshBLButton()
    local b = bodyWidgets.bloodlustBtn
    if not b then return end
    local d = db(); if not d then return end
    local on = d.bloodlust == true
    local fs = b:GetFontString()
    if on then
        b:SetBackdropColor(0.48, 0.10, 0.07, 1)              -- red fill
        b:SetBackdropBorderColor(0.72, 0.20, 0.12, 1)        -- red rim
        if fs then fs:SetTextColor(1.00, 0.92, 0.75, 1) end  -- warm white
        b:SetText("BLOODLUST \194\183 ON")
    else
        local STONE = ns.Tokens.stone_tile
        local RIM   = ns.Tokens.stone_rim
        b:SetBackdropColor(STONE[1], STONE[2], STONE[3], 1)
        b:SetBackdropBorderColor(RIM[1], RIM[2], RIM[3], 1)
        if fs then fs:SetTextColor(0.55, 0.50, 0.42, 1) end  -- gold_dim
        b:SetText("BLOODLUST")
    end
end

-- ----------------------------------------------------------
-- Layout
-- ----------------------------------------------------------
local function layout()
    if not frame then return end
    local dens = currentDensity()
    local width = dens.w
    local btnH = dens.btnH
    local s = sw() or { showStatus = true, showRoles = true }

    -- Compute body height first so we can SetSize the frame once, then
    -- position every child to the actual width.
    local h = HEADER_H
    if s.showStatus then h = h + STATUS_H end
    h = h + PAD
    h = h + (btnH * 2 + GAP)              -- movement
    h = h + GAP + btnH                    -- strategy
    if s.showRoles then
        h = h + GAP + (btnH * 3 + GAP * 2)
    end
    h = h + GAP + btnH                    -- bloodlust
    h = h + PAD
    frame:SetSize(width, h)

    local y = HEADER_H
    if frame.status then
        if s.showStatus then
            frame.status:ClearAllPoints()
            frame.status:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -y)
            frame.status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
            frame.status:Show()
            y = y + STATUS_H
        else
            frame.status:Hide()
        end
    end

    y = y + PAD

    local function stackContainer(g, containerH)
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, -y)
        g:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        g:SetHeight(containerH)
        y = y + containerH + GAP
    end

    local function reanchor(btn, parent, px, py)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
    end

    -- Movement 2x2 grid
    if bodyWidgets.movement and bodyWidgets.movementBtns then
        stackContainer(bodyWidgets.movement, btnH * 2 + GAP)
        local col = math.floor((width - PAD * 2 - GAP) / 2)
        local btns = bodyWidgets.movementBtns
        -- summon / follow / stay / flee = indices 1..4
        local layoutMap = {
            { 1, 1 }, { 1, 2 },  -- row 1: summon, follow
            { 2, 1 }, { 2, 2 },  -- row 2: stay,   flee
        }
        for i, b in ipairs(btns) do
            local r, c = layoutMap[i][1], layoutMap[i][2]
            b:SetSize(col, btnH)
            reanchor(b, bodyWidgets.movement,
                PAD + (c - 1) * (col + GAP),
                -((r - 1) * (btnH + GAP)))
        end
    end

    -- Strategy 3-col row
    if bodyWidgets.strategy and bodyWidgets.strategyBtns then
        stackContainer(bodyWidgets.strategy, btnH)
        local col = math.floor((width - PAD * 2 - GAP * 2) / 3)
        for i, b in ipairs(bodyWidgets.strategyBtns) do
            b:SetSize(col, btnH)
            reanchor(b, bodyWidgets.strategy, PAD + (i - 1) * (col + GAP), 0)
        end
    end

    -- Role matrix 3x3 + labels (Follow | Atk | Stay)
    if bodyWidgets.roles and bodyWidgets.roleRows then
        if s.showRoles then
            bodyWidgets.roles:Show()
            stackContainer(bodyWidgets.roles, btnH * 3 + GAP * 2)
            local labelW = 44
            local col = math.floor((width - PAD * 2 - labelW - GAP * 3) / 3)
            for i, row in ipairs(bodyWidgets.roleRows) do
                local ry = -((i - 1) * (btnH + GAP))
                row.lbl:ClearAllPoints()
                row.lbl:SetPoint("TOPLEFT", bodyWidgets.roles, "TOPLEFT", PAD, ry - 2)
                row.lbl:SetWidth(labelW)
                row.atk:SetSize(col, btnH)
                reanchor(row.atk, bodyWidgets.roles, PAD + labelW, ry)
                row.follow:SetSize(col, btnH)
                reanchor(row.follow, bodyWidgets.roles, PAD + labelW + col + GAP, ry)
                row.stay:SetSize(col, btnH)
                reanchor(row.stay, bodyWidgets.roles, PAD + labelW + (col + GAP) * 2, ry)
            end
        else
            bodyWidgets.roles:Hide()
        end
    end

    -- Bloodlust full-width
    if bodyWidgets.bloodlust and bodyWidgets.bloodlustBtn then
        stackContainer(bodyWidgets.bloodlust, btnH)
        bodyWidgets.bloodlustBtn:SetSize(width - PAD * 2, btnH)
        reanchor(bodyWidgets.bloodlustBtn, bodyWidgets.bloodlust, PAD, 0)
    end

    refreshLockButton(frame.header and frame.header.lockBtn)
end

local function applyPosition()
    if not frame then return end
    local s = sw()
    frame:ClearAllPoints()
    if s and s.pos and type(s.pos) == "table" and s.pos.point then
        frame:SetPoint(s.pos.point, UIParent, s.pos.point, s.pos.x or 0, s.pos.y or 0)
    else
        -- Default: upper-right of the screen so the HUD does not spawn
        -- inside the main /warden window (which made right-column buttons
        -- look hidden behind it on first load).
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -120)
    end
end

local function storePosition()
    if not frame then return end
    local s = sw(); if not s then return end
    local point, _, _, x, y = frame:GetPoint(1)
    if point then s.pos = { point = point, x = x, y = y } end
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "WardenSwordFrame", UIParent)
    -- HIGH strata so the HUD always paints ABOVE the main /warden window
    -- when they overlap (default position used to land inside it, which
    -- made the right-column buttons disappear behind Warden's panels).
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile     = true, tileSize = 16,
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.07, 0.05, 0.03, 1.00)     -- fully opaque
    frame:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)  -- gold_dim rim

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local s = sw()
        if s and s.locked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        storePosition()
    end)

    frame.header   = buildHeader(frame, 240)
    frame.status   = buildStatusStrip(frame)
    buildMovementGrid(frame)
    buildStrategyRow(frame)
    buildRoleMatrix(frame)
    buildBloodlust(frame)

    -- Ticker - updates status strip + BL button every 0.5s.
    frame._tick = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._tick = (self._tick or 0) + elapsed
        if self._tick < 0.5 then return end
        self._tick = 0
        ns.WardenSword.RefreshStatus()
        if ns.WardenSword.RefreshBLButton then ns.WardenSword.RefreshBLButton() end
    end)

    -- Combat hook: auto-show on combat start when the user opted in.
    -- A prior "keep shown 10s then fade" branch was unfinished (dead code);
    -- dropped. Users close the HUD manually or via /ws hide.
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(self, event)
        local s = sw(); if not s then return end
        if event == "PLAYER_REGEN_DISABLED"
           and s.autoShowCombat and not s.hidden then
            if ns.Debug then ns.Debug("sword", "auto-show on combat start") end
            self:Show()
        end
    end)

    applyPosition()
    layout()
    return frame
end

-- ----------------------------------------------------------
-- Status strip content
-- ----------------------------------------------------------
local function countBots()
    local total, t, h, d = 0, 0, 0, 0
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") then
                total = total + 1
                -- Crude role guess from class + spec data isn't available here
                -- reliably, so leave T/H/D breakdown 0 unless Engine tracks it.
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then total = total + 1 end
        end
    end
    return total, t, h, d
end

function ns.WardenSword.RefreshStatus()
    if not frame or not frame.status or not frame.status.fs then return end
    local s = sw(); if not s or not s.showStatus then return end
    local d = db(); if not d then return end
    local bots = countBots()
    local aoe = d.aoe and "ON" or "off"
    local bl  = d.bloodlust and "ON" or "off"
    local q   = (ns.Engine.QueueDepth and ns.Engine.QueueDepth()) or 0
    frame.status.fs:SetText(string.format("BOTS %d  AoE:%s  BL:%s  Q%d", bots, aoe, bl, q))
end

-- ----------------------------------------------------------
-- Public API
-- ----------------------------------------------------------
function ns.WardenSword.Frame() return frame end

function ns.WardenSword.Show()
    if ns.Debug then ns.Debug("sword", "Show") end
    if not frame then build() end
    frame:Show()
    local s = sw(); if s then s.hidden = false end
end

function ns.WardenSword.Hide()
    if ns.Debug then ns.Debug("sword", "Hide") end
    if not frame then return end
    frame:Hide()
    local s = sw(); if s then s.hidden = true end
end

function ns.WardenSword.Toggle()
    if ns.Debug then ns.Debug("sword", "Toggle") end
    if not frame then build() end
    if frame:IsShown() then ns.WardenSword.Hide() else ns.WardenSword.Show() end
end

function ns.WardenSword.SetLocked(v)
    local s = sw(); if not s then return end
    s.locked = v and true or false
    refreshLockButton(frame and frame.header and frame.header.lockBtn)
end

function ns.WardenSword.ToggleLock()
    local s = sw(); if not s then return end
    ns.WardenSword.SetLocked(not s.locked)
end

function ns.WardenSword.ResetPosition()
    local s = sw(); if s then s.pos = nil end
    applyPosition()
end

function ns.WardenSword.OpenSettings()
    if ns.UI.Master and ns.UI.Master.ShowTab then
        ns.UI.Master.ShowTab("Settings")
    end
end

function ns.WardenSword.ApplyLayout()
    if not frame then return end
    layout()
end

-- Apply the persisted opacity to the HUD. Called by the Settings slider and
-- on boot so a low-alpha value survives /reload.
function ns.WardenSword.ApplyAlpha()
    if not frame then return end
    local s = sw()
    local a = s and tonumber(s.alpha) or 1.00
    if a < 0.15 then a = 0.15 end  -- don't let the user lose the HUD entirely
    if a > 1.00 then a = 1.00 end
    frame:SetAlpha(a)
end

function ns.WardenSword.PrintHelp()
    ns.MsgInfo("WardenSword commands:")
    local rows = {
        { "/ws",              "toggle the HUD" },
        { "/ws show|hide",    "explicit show / hide" },
        { "/ws lock|unlock",  "lock or unlock position" },
        { "/ws reset",        "reset position" },
        { "/ws config",       "open Warden Settings" },
        { "/ws summon",       "summon all bots" },
        { "/ws follow|stay|flee", "group movement" },
        { "/ws aoe|burn",     "toggle strategy flags" },
        { "/ws skull",        "mark target Skull + attack" },
        { "/ws bl",           "bloodlust / heroism" },
        { "/ws @tank atk",    "role-scoped orders (@tank|@heal|@dps follow|atk|stay)" },
    }
    for _, r in ipairs(rows) do
        ns.MsgInfo(string.format("  %s%s|r  %s", ns.Colors.key, r[1], r[2]))
    end
end

-- ----------------------------------------------------------
-- Slash
-- ----------------------------------------------------------
SLASH_WARDENSWORD1 = "/ws"
SLASH_WARDENSWORD2 = "/wardensword"
SlashCmdList["WARDENSWORD"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if ns.DebugF then ns.DebugF("slash", "/ws %q", msg) end
    if msg == "" then ns.WardenSword.Toggle(); return end

    -- Direct action match (summon / follow / aoe / bl / etc).
    local action = ns.WardenSword.Actions and ns.WardenSword.Actions[msg]
    if action then action(); return end

    -- `@role action` shorthand: `/ws @tank atk` or `/ws @heal stay`.
    local role, act = msg:match("^@(%w+)%s+(%w+)$")
    if role and act then
        if act == "atk" then act = "attack" end
        local key = "@" .. role .. " " .. act
        local fn = ns.WardenSword.Actions and ns.WardenSword.Actions[key]
        if fn then fn(); return end
    end

    if msg == "lock"   then ns.WardenSword.SetLocked(true);  return end
    if msg == "unlock" then ns.WardenSword.SetLocked(false); return end
    if msg == "show"   then ns.WardenSword.Show();           return end
    if msg == "hide"   then ns.WardenSword.Hide();           return end
    if msg == "reset"  then ns.WardenSword.ResetPosition();  return end
    if msg == "config" then ns.WardenSword.OpenSettings();   return end
    if msg == "help"   then ns.WardenSword.PrintHelp();      return end

    ns.WardenSword.PrintHelp()
end

-- ----------------------------------------------------------
-- Binding glue (Bindings.xml calls a global)
-- ----------------------------------------------------------
function WARDENSWORD_Toggle()     ns.WardenSword.Toggle() end
function WARDENSWORD_ToggleLock() ns.WardenSword.ToggleLock() end
function WARDENSWORD_Run(key)
    if not key then return end
    local fn = ns.WardenSword.Actions and ns.WardenSword.Actions[key]
    if fn then fn() end
end

-- ----------------------------------------------------------
-- Binding label strings (appear in ESC -> Key Bindings)
-- ----------------------------------------------------------
BINDING_HEADER_WARDEN                 = "Warden"
BINDING_HEADER_WARDENSWORDACTIONS     = "WardenSword - Actions"
BINDING_HEADER_WARDENSWORDROLES       = "WardenSword - Role commands"

BINDING_NAME_WARDEN_TOGGLE            = "Toggle Warden window"
BINDING_NAME_WARDENSWORD_TOGGLE       = "Toggle WardenSword HUD"
BINDING_NAME_WARDENSWORD_LOCK         = "Lock / unlock WardenSword position"
BINDING_NAME_WARDENSWORD_SUMMON       = "Summon all bots"
BINDING_NAME_WARDENSWORD_FOLLOW       = "All: Follow"
BINDING_NAME_WARDENSWORD_STAY         = "All: Stay"
BINDING_NAME_WARDENSWORD_FLEE         = "All: Flee"
BINDING_NAME_WARDENSWORD_AOE          = "Toggle AoE"
BINDING_NAME_WARDENSWORD_BURN         = "Toggle Burn CDs"
BINDING_NAME_WARDENSWORD_SKULL        = "Mark Skull + attack"
BINDING_NAME_WARDENSWORD_BL           = "Bloodlust / Heroism"
BINDING_NAME_WARDENSWORD_TANK_ATK     = "Tanks: Attack"
BINDING_NAME_WARDENSWORD_TANK_STAY    = "Tanks: Stay"
BINDING_NAME_WARDENSWORD_HEAL_ATK     = "Healers: Attack"
BINDING_NAME_WARDENSWORD_HEAL_STAY    = "Healers: Stay"
BINDING_NAME_WARDENSWORD_DPS_ATK      = "DPS: Attack"
BINDING_NAME_WARDENSWORD_DPS_STAY     = "DPS: Stay"

-- ----------------------------------------------------------
-- Bootstrap
--
-- Previously listened for PLAYER_LOGIN on its own frame, which competed with
-- Persistence.lua's own PLAYER_LOGIN handler (Lua dispatch order isn't
-- defined between frames registered to the same event). On sessions where
-- the sword handler won the race, sw() returned nil and "Start locked" /
-- "Start hidden" silently did nothing.
--
-- Route through ns.Persistence.OnReady which fires exactly once AFTER the
-- DB has been populated and migrated. No race, no nil guards needed.
-- ----------------------------------------------------------
ns.Persistence.OnReady(function()
    local s = sw()
    build()
    if s then
        if s.startLocked and not s.locked then s.locked = true end
        if s.hidden then frame:Hide() else frame:Show() end
    end
    ns.WardenSword.ApplyAlpha()
end)

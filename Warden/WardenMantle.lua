-- =====================================================
-- Warden - WardenMantle.lua
-- Floating bot-management HUD card. Target a bot (or not) and drive the
-- non-target-specific bot actions from one place: Summon, Autogear, and
-- ResetBot (the "level up" / bot-init re-gear, picked by rarity tier).
-- Chrome (drag / lock / position / footer ticker / public API) clones
-- WardenSword.lua.
--
-- Invariant: this file contains ZERO direct SendChatMessage calls - every
-- outbound message routes through ns.Engine.Queue / ns.Engine.WhisperAll.
-- =====================================================

local _, ns = ...
ns.WardenMantle = ns.WardenMantle or {}

-- ----------------------------------------------------------
-- Geometry
-- ----------------------------------------------------------
local WIDTH      = 222
local HEADER_H   = 22
local PAD        = 8
local ROW_GAP    = 8
local DIV_H      = 14
local FOOTER_H   = 20
local PORTRAIT   = 30

-- ----------------------------------------------------------
-- Bot-init rarity tiers (copied from the Spec tab's "level up" control).
-- ----------------------------------------------------------
local RARITIES = { "common", "uncommon", "rare", "epic" }
local RARITY_LABEL = {
    common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic",
}
local RARITY_COLOR = {
    common   = "ffffffff", -- white
    uncommon = "ff1eff00", -- green
    rare     = "ff0070dd", -- blue
    epic     = "ffa335ee", -- purple
}
local function rarityText(r)
    return "|c" .. (RARITY_COLOR[r] or "ffffffff") .. (RARITY_LABEL[r] or r) .. "|r"
end

-- ----------------------------------------------------------
-- State
-- ----------------------------------------------------------
local frame          -- top-level HUD frame
local initRarity = "epic"

-- ----------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------
local function db() return ns.Persistence and ns.Persistence.DB end
local function mt() local d = db(); return d and d.mantle end

-- Resolve the bot to act on: the hard target when it's another player.
-- Returns name, classToken - or nil when there is no valid target.
local function resolveTarget()
    if UnitExists("target") and UnitIsPlayer("target")
       and not UnitIsUnit("target", "player") then
        local _, class = UnitClass("target")
        return UnitName("target"), class
    end
    return nil
end

-- ----------------------------------------------------------
-- Header (clone of WardenSword's, retitled)
-- ----------------------------------------------------------
local function refreshLockButton(lockBtn)
    local s = mt()
    if not lockBtn or not lockBtn.fs then return end
    if s and s.locked then
        lockBtn.fs:SetText("*")
        lockBtn.fs:SetTextColor(1.00, 0.82, 0.00, 1)
    else
        lockBtn.fs:SetText("o")
        lockBtn.fs:SetTextColor(0.55, 0.50, 0.42, 1)
    end
end

local function buildHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HEADER_H)
    h:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, 0)
    h:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", h, "LEFT", PAD, 0)
    title:SetText("WARDENMANTLE")
    title:SetTextColor(1.00, 0.82, 0.00, 1)

    local hint = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 6, 0)
    hint:SetText("/wm")
    hint:SetTextColor(0.55, 0.50, 0.42, 1)

    local close = CreateFrame("Button", nil, h)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", h, "RIGHT", -PAD, 0)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x")
    cfs:SetTextColor(0.85, 0.18, 0.12, 1)
    close:SetScript("OnClick", function() ns.WardenMantle.Hide() end)

    local lock = CreateFrame("Button", nil, h)
    lock:SetSize(16, 16)
    lock:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local lfs = lock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lfs:SetPoint("CENTER", lock, "CENTER", 0, 0)
    lock.fs = lfs
    lock:SetScript("OnClick", function() ns.WardenMantle.ToggleLock() end)
    h.lockBtn = lock

    local rule = h:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(0.23, 0.18, 0.13, 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT",  h, "BOTTOMLEFT",  0, 0)
    rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    return h
end

-- ----------------------------------------------------------
-- Body widgets (built once, repositioned each Refresh)
-- ----------------------------------------------------------
local function buildBody()
    -- Target portrait
    local p = CreateFrame("Frame", nil, frame)
    p:SetSize(PORTRAIT, PORTRAIT)
    p:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    p:SetBackdropColor(0.11, 0.08, 0.05, 1)
    p:SetBackdropBorderColor(ns.Tokens.gold_rim[1], ns.Tokens.gold_rim[2], ns.Tokens.gold_rim[3], 1)
    local ptex = p:CreateTexture(nil, "ARTWORK")
    ptex:SetPoint("TOPLEFT",     p, "TOPLEFT",      1, -1)
    ptex:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1,  1)
    p.tex = ptex
    frame.portrait = p

    local nameLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLbl:SetJustifyH("LEFT")
    frame.nameLbl = nameLbl

    local subLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subLbl:SetJustifyH("LEFT")
    subLbl:SetTextColor(0.45, 0.38, 0.28, 1)
    frame.subLbl = subLbl

    -- "No Target" muted state
    local noTarget = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noTarget:SetText("No Target")
    noTarget:SetTextColor(0.45, 0.38, 0.28, 1)
    frame.noTarget = noTarget

    -- Action row: Summon (group) + Autogear (PARTY). Both are global bot
    -- actions, so they show in every target state.
    local summonBtn = ns.UI.Button.stone(frame, "Summon", 60, 18)
    summonBtn:SetScript("OnClick", function()
        if ns.Engine and ns.Engine.WhisperAll then ns.Engine.WhisperAll("summon") end
        ns.MsgInfo("Sent `summon`.")
    end)
    frame.summonBtn = summonBtn

    -- Autogear moves into the action row (the spot vacated by the old Level
    -- whisper button).
    local ag = ns.UI.Button.gold(frame, "Autogear", 60, 18)
    ag:SetScript("OnClick", function()
        ns.Engine.Queue("autogear", "PARTY")
        ns.MsgInfo("Sent `autogear` -> PARTY.")
    end)
    frame.autogear = ag

    -- BOT INIT section (replaces the removed spec-swap tiles). The rarity
    -- dropdown picks the gear tier; ResetBot re-rolls every bot's gear via
    -- `.warstormbot bot init=<rarity>` on the command channel - the same
    -- "level up" logic the Spec tab exposes, routed through Engine.Queue so
    -- the no-direct-SendChatMessage invariant holds.
    local biLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    biLbl:SetText("BOT INIT")
    biLbl:SetTextColor(1.00, 0.82, 0.00, 1)
    frame.biLbl = biLbl

    local rarityDrop = CreateFrame("Frame", "WardenMantleRarityDrop", frame, "UIDropDownMenuTemplate")
    ns.UI.Dropdown.style(rarityDrop, 96)
    UIDropDownMenu_Initialize(rarityDrop, function()
        for _, r in ipairs(RARITIES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = rarityText(r)
            info.value = r
            info.func  = function(self)
                initRarity = self.value
                UIDropDownMenu_SetText(rarityDrop, rarityText(self.value))
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(rarityDrop, rarityText(initRarity))
    frame.rarityDrop = rarityDrop

    local resetBtn = ns.UI.Button.gold(frame, "ResetBot", 90, 20)
    resetBtn:SetScript("OnClick", function()
        local chan = (db() and db().commandChannel) or "SAY"
        local rarity = initRarity or "epic"
        ns.Engine.Queue(".warstormbot bot init=" .. rarity, chan)
        ns.MsgInfo(string.format("Sent `.warstormbot bot init=%s` (%s).", rarity, chan))
    end)
    frame.resetBtn = resetBtn

    -- Footer strip
    local foot = CreateFrame("Frame", nil, frame)
    foot:SetHeight(FOOTER_H)
    foot:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    foot:SetBackdropColor(0.07, 0.05, 0.03, 1)
    foot:SetBackdropBorderColor(0.18, 0.14, 0.10, 1)
    local lf = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lf:SetPoint("LEFT", foot, "LEFT", 6, 0)
    lf:SetText("bot |cffffd100init|r -> reset gear")
    lf:SetTextColor(0.61, 0.55, 0.40, 1)
    local rf = foot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rf:SetPoint("RIGHT", foot, "RIGHT", -6, 0)
    rf:SetTextColor(0.61, 0.55, 0.40, 1)
    foot.qfs = rf
    frame.footer = foot
end

local function refreshFooterQueue()
    if frame and frame.footer and frame.footer.qfs then
        local q = (ns.Engine.QueueDepth and ns.Engine.QueueDepth()) or 0
        frame.footer.qfs:SetText(string.format("q |cffffd100%d|r", q))
    end
end

-- ----------------------------------------------------------
-- Refresh: resolve target, (re)lay out body, size the frame.
-- ----------------------------------------------------------
local function Refresh()
    if not frame then return end

    local name, class = resolveTarget()

    local p, nameLbl, subLbl = frame.portrait, frame.nameLbl, frame.subLbl
    local y = HEADER_H + 6

    -- Target line
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    nameLbl:ClearAllPoints()
    nameLbl:SetPoint("TOPLEFT", p, "TOPRIGHT", 8, -1)
    nameLbl:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    subLbl:ClearAllPoints()
    subLbl:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -2)

    if name and class then
        frame.noTarget:Hide()
        SetPortraitTexture(p.tex, "target")
        nameLbl:SetText(ns.ColorClass(class, name))
        nameLbl:Show()
        subLbl:SetText(string.format("%s \194\183 LVL %d",
            (ns.Data.CLASS_LABEL[class] or class):upper(), UnitLevel("target") or 0))
        subLbl:Show()
    else
        p.tex:SetTexture(nil)
        nameLbl:Hide(); subLbl:Hide()
        frame.noTarget:ClearAllPoints()
        frame.noTarget:SetPoint("LEFT", p, "RIGHT", 8, 0)
        frame.noTarget:Show()
    end
    y = y + PORTRAIT + ROW_GAP

    -- Action row: Summon (left) + Autogear (right), half-width each.
    local contentW = WIDTH - PAD * 2
    local bw = math.floor((contentW - 6) / 2)
    frame.summonBtn:ClearAllPoints()
    frame.summonBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
    frame.summonBtn:SetSize(bw, 18)
    frame.summonBtn:Show()
    frame.autogear:ClearAllPoints()
    frame.autogear:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + bw + 6, -y)
    frame.autogear:SetSize(bw, 18)
    frame.autogear:Show()
    y = y + 18 + ROW_GAP

    -- BOT INIT label
    frame.biLbl:ClearAllPoints()
    frame.biLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y - 2)
    frame.biLbl:Show()
    y = y + DIV_H

    -- Rarity dropdown (left) + ResetBot (right). UIDropDownMenuTemplate carries
    -- a ~16px left inset, so nudge x to line its text up with PAD.
    frame.rarityDrop:ClearAllPoints()
    frame.rarityDrop:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 14, -y + 2)
    frame.rarityDrop:Show()
    frame.resetBtn:ClearAllPoints()
    frame.resetBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y - 4)
    frame.resetBtn:Show()
    y = y + 26 + ROW_GAP

    -- Footer
    frame.footer:ClearAllPoints()
    frame.footer:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, -y)
    frame.footer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
    y = y + FOOTER_H + PAD

    frame:SetSize(WIDTH, y)
    refreshFooterQueue()
    refreshLockButton(frame.header and frame.header.lockBtn)
end
ns.WardenMantle.Refresh = Refresh

-- ----------------------------------------------------------
-- Position
-- ----------------------------------------------------------
local function applyPosition()
    if not frame then return end
    local s = mt()
    frame:ClearAllPoints()
    if s and s.pos and type(s.pos) == "table" and s.pos.point then
        frame:SetPoint(s.pos.point, UIParent, s.pos.point, s.pos.x or 0, s.pos.y or 0)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -120)
    end
end

local function storePosition()
    if not frame then return end
    local s = mt(); if not s then return end
    local point, _, _, x, y = frame:GetPoint(1)
    if point then s.pos = { point = point, x = x, y = y } end
end

-- ----------------------------------------------------------
-- Frame construction
-- ----------------------------------------------------------
local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "WardenMantleFrame", UIParent)
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
    frame:SetBackdropColor(0.07, 0.05, 0.03, 1.00)
    frame:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local s = mt()
        if s and s.locked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        storePosition()
    end)

    frame.header = buildHeader(frame)
    buildBody()

    -- Footer ticker - refresh queue depth twice a second.
    frame._tick = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._tick = (self._tick or 0) + elapsed
        if self._tick < 0.5 then return end
        self._tick = 0
        refreshFooterQueue()
    end)

    -- Re-render when the target changes.
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function() Refresh() end)

    applyPosition()
    Refresh()
    return frame
end

-- ----------------------------------------------------------
-- Public API (mirror WardenSword)
-- ----------------------------------------------------------
function ns.WardenMantle.Frame() return frame end

function ns.WardenMantle.Show()
    if not frame then build() end
    frame:Show()
    local s = mt(); if s then s.hidden = false end
    Refresh()
end

function ns.WardenMantle.Hide()
    if not frame then return end
    frame:Hide()
    local s = mt(); if s then s.hidden = true end
end

function ns.WardenMantle.Toggle()
    if not frame then build() end
    if frame:IsShown() then ns.WardenMantle.Hide() else ns.WardenMantle.Show() end
end

function ns.WardenMantle.SetLocked(v)
    local s = mt(); if not s then return end
    s.locked = v and true or false
    refreshLockButton(frame and frame.header and frame.header.lockBtn)
end

function ns.WardenMantle.ToggleLock()
    local s = mt(); if not s then return end
    ns.WardenMantle.SetLocked(not s.locked)
end

function ns.WardenMantle.ResetPosition()
    local s = mt(); if s then s.pos = nil end
    applyPosition()
end

function ns.WardenMantle.PrintHelp()
    ns.MsgInfo("WardenMantle commands:")
    local rows = {
        { "/wm",            "toggle the bot-management HUD" },
        { "/wm show|hide",  "explicit show / hide" },
        { "/wm lock|unlock","lock or unlock position" },
        { "/wm reset",      "reset position" },
    }
    for _, r in ipairs(rows) do
        ns.MsgInfo(string.format("  %s%s|r  %s", ns.Colors.key, r[1], r[2]))
    end
end

-- ----------------------------------------------------------
-- Slash
-- ----------------------------------------------------------
SLASH_WARDENMANTLE1 = "/wm"
SLASH_WARDENMANTLE2 = "/wardenmantle"
SlashCmdList["WARDENMANTLE"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if msg == ""        then ns.WardenMantle.Toggle();        return end
    if msg == "show"    then ns.WardenMantle.Show();          return end
    if msg == "hide"    then ns.WardenMantle.Hide();          return end
    if msg == "lock"    then ns.WardenMantle.SetLocked(true);  return end
    if msg == "unlock"  then ns.WardenMantle.SetLocked(false); return end
    if msg == "reset"   then ns.WardenMantle.ResetPosition(); return end
    ns.WardenMantle.PrintHelp()
end

-- ----------------------------------------------------------
-- Binding glue (Bindings.xml calls these globals)
-- ----------------------------------------------------------
function WARDENMANTLE_Toggle()     ns.WardenMantle.Toggle() end
function WARDENMANTLE_ToggleLock() ns.WardenMantle.ToggleLock() end

BINDING_HEADER_WARDENMANTLE      = "WardenMantle"
BINDING_NAME_WARDENMANTLE_TOGGLE = "Toggle WardenMantle HUD"
BINDING_NAME_WARDENMANTLE_LOCK   = "Lock / unlock WardenMantle position"

-- ----------------------------------------------------------
-- Bootstrap (mirror WardenSword - run after DB is ready)
-- ----------------------------------------------------------
ns.Persistence.OnReady(function()
    local s = mt()
    build()
    if s and s.hidden then frame:Hide() else frame:Show() end
end)

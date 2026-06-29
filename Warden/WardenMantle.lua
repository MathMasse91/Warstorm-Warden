-- =====================================================
-- Warden - WardenMantle.lua
-- Floating spec-swap HUD card (successor to feysSpecManager). Target a bot
-- and click a spec tile to whisper "talents spec <spec>" through the throttled
-- Engine.Queue; the swap is recorded by GUID so a Comp-tab Re-Spec re-applies
-- it after a retarget. The spec manager is the core of this HUD.
--
-- Alongside the spec tiles it also carries the global bot actions: Summon,
-- Autogear, and a BOT INIT rarity dropdown + ResetBot button that re-rolls the
-- targeted/all bots' gear via `.warstormbot bot init=<rarity>`. Chrome (drag /
-- lock / position / footer ticker / public API) clones WardenSword.lua.
--
-- Invariant: this file contains ZERO direct SendChatMessage calls - every
-- outbound message routes through ns.Engine.Queue / ns.Engine.WhisperAll /
-- SPEC_EXEC.
-- =====================================================

local _, ns = ...
ns.WardenMantle = ns.WardenMantle or {}

-- ----------------------------------------------------------
-- Geometry
-- ----------------------------------------------------------
local WIDTH      = 222
local HEADER_H   = 22
local PAD        = 8
local TILE_GAP   = 6
local CAP_H      = 12
local ROW_GAP    = 8
local DIV_H      = 16
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
local tilePool = {}  -- reusable spec-tile buttons
local tileCursor = 0
local initRarity = "epic"

-- ----------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------
local function db() return ns.Persistence and ns.Persistence.DB end
local function mt() local d = db(); return d and d.mantle end

-- Resolve the bot to act on: the hard target when it's another player.
-- Returns name, classToken, guid - or nil when there is no valid target.
local function resolveTarget()
    if UnitExists("target") and UnitIsPlayer("target")
       and not UnitIsUnit("target", "player") then
        local _, class = UnitClass("target")
        return UnitName("target"), class, UnitGUID("target")
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
-- Spec tile pool
-- ----------------------------------------------------------
local function createTile()
    local b = CreateFrame("Button", nil, frame)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp")
    b:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    b:SetBackdropColor(0.04, 0.03, 0.02, 1)
    b:SetBackdropBorderColor(ns.Tokens.gold_rim[1], ns.Tokens.gold_rim[2], ns.Tokens.gold_rim[3], 1)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     b, "TOPLEFT",      1, -1)
    tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1,  1)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim default icon border
    b.tex = tex

    local code = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    code:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.code = code

    local cap = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cap:SetPoint("TOP", b, "BOTTOM", 0, -2)
    cap:SetTextColor(0.80, 0.72, 0.54, 1)
    b.cap = cap

    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1.00, 0.82, 0.00, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(ns.Tokens.gold_rim[1], ns.Tokens.gold_rim[2], ns.Tokens.gold_rim[3], 1)
    end)
    return b
end

local function nextTile()
    tileCursor = tileCursor + 1
    local t = tilePool[tileCursor]
    if not t then t = createTile(); tilePool[tileCursor] = t end
    return t
end

local function hideUnusedTiles()
    for i = tileCursor + 1, #tilePool do
        if tilePool[i] then tilePool[i]:Hide() end
    end
end

-- Lay out one PvE/PvP row of spec tiles; return the y just below the row.
local function layoutSpecRow(entries, class, modeLabel, topY)
    local n = #entries
    if n == 0 then return topY end
    local contentW = WIDTH - PAD * 2
    -- Small square tiles: at least 50% smaller than a row-filling tile, capped
    -- at 30px, and centered so the row doesn't look sparse.
    local fullW = math.floor((contentW - (n - 1) * TILE_GAP) / n)
    local tileW = math.min(30, math.max(18, math.floor(fullW * 0.5)))
    local tileH = tileW
    local total  = n * tileW + (n - 1) * TILE_GAP
    local startX = PAD + math.max(0, math.floor((contentW - total) / 2))
    local icons = ns.Data.SPEC_ICONS[class]
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]

    for i, e in ipairs(entries) do
        local t = nextTile()
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (tileW + TILE_GAP), -topY)
        t:SetSize(tileW, tileH)

        local icon = icons and icons[e.base]
        if icon then
            t.tex:SetTexture(icon)
            t.tex:Show()
            t.code:Hide()
            t:SetBackdropColor(0.04, 0.03, 0.02, 1)
        else
            t.tex:Hide()
            t.code:SetText(ns.Data.SpecLabel(e.base))
            t.code:Show()
            if cc then
                t:SetBackdropColor(cc.r * 0.40, cc.g * 0.40, cc.b * 0.40, 1)
                t.code:SetTextColor(cc.r, cc.g, cc.b, 1)
            else
                t:SetBackdropColor(0.18, 0.14, 0.10, 1)
                t.code:SetTextColor(1, 1, 1, 1)
            end
        end

        t.cap:SetText(ns.Data.SpecCaption(e.base))
        ns.UI.Tooltip.Attach(t, ns.Data.SpecCaption(e.base) .. " (" .. modeLabel .. ")",
            "Whisper talents spec to " .. (resolveTarget() or "target") .. ".", "ANCHOR_TOP")

        local spec = e.spec
        t:SetScript("OnClick", function()
            local name, curClass, guid = resolveTarget()
            if not name then
                ns.MsgErr("Target a bot first.")
                return
            end
            if curClass ~= class then
                ns.MsgWarn("That target isn't a " .. class .. " - retarget to use this tile.")
                return
            end
            local tbl = ns.Data.SPEC_EXEC[class]
            local fn  = tbl and tbl[spec]
            if not fn then
                ns.MsgWarn("No execution defined for " .. class .. " - " .. spec)
                return
            end
            fn(name)  -- enqueues the WHISPER through Engine.Queue (A-bridge)

            if guid and ns.Engine and ns.Engine.state and ns.Engine.state.assignedSpecs then
                local prev = ns.Engine.state.assignedSpecs[guid] or {}
                ns.Engine.state.assignedSpecs[guid] = {
                    name       = name,
                    spec       = spec,
                    classToken = class,
                    opt1       = prev.opt1,
                    opt2       = prev.opt2,
                }
            end
            ns.MsgInfo(string.format("Sent `talents spec %s` -> %s.",
                spec, ns.ColorClass(class, name)))
        end)
        t:Show()
    end
    return topY + tileH + CAP_H
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

    -- PvE / PvP divider labels
    local function divLabel(text)
        local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetText(text)
        l:SetTextColor(1.00, 0.82, 0.00, 1)
        return l
    end
    frame.pveLbl = divLabel("PvE")
    frame.pvpLbl = divLabel("PvP")

    -- Action row: Summon (group) + Autogear (PARTY). Both are global bot
    -- actions, so they show in every target state.
    local summonBtn = ns.UI.Button.stone(frame, "Summon", 60, 18)
    summonBtn:SetScript("OnClick", function()
        if ns.Engine and ns.Engine.WhisperAll then ns.Engine.WhisperAll("summon") end
        ns.MsgInfo("Sent `summon`.")
    end)
    frame.summonBtn = summonBtn

    local ag = ns.UI.Button.gold(frame, "Autogear", 60, 18)
    ag:SetScript("OnClick", function()
        ns.Engine.Queue("autogear", "PARTY")
        ns.MsgInfo("Sent `autogear` -> PARTY.")
    end)
    frame.autogear = ag

    -- BOT INIT section: rarity dropdown + ResetBot. ResetBot re-rolls bot gear
    -- via `.warstormbot bot init=<rarity>` on the command channel - routed
    -- through Engine.Queue so the no-direct-SendChatMessage invariant holds.
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
    lf:SetText("whisper |cffffd100talents spec|r")
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
    tileCursor = 0

    local name, class = resolveTarget()
    local rows = class and ns.Data.MantleRows(class) or nil

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

    if rows then
        frame.noTarget:Hide()
        SetPortraitTexture(p.tex, "target")
        nameLbl:SetText(ns.ColorClass(class, name or "?"))
        nameLbl:Show()
        subLbl:SetText(string.format("%s \194\183 %d SPECS",
            (ns.Data.CLASS_LABEL[class] or class):upper(), #rows.pve + #rows.pvp))
        subLbl:Show()
    else
        p.tex:SetTexture(nil)
        nameLbl:Hide(); subLbl:Hide()
        frame.noTarget:ClearAllPoints()
        frame.noTarget:SetPoint("LEFT", p, "RIGHT", 8, 0)
        frame.noTarget:Show()
    end
    y = y + PORTRAIT + ROW_GAP

    -- Action row: Summon (left) + Autogear (right), half-width each. Global
    -- actions, shown in both target states.
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

    -- Spec manager (the core): PvE + PvP tile rows when the target is a known
    -- bot class. Hidden when there's no valid target.
    if rows then
        frame.pveLbl:ClearAllPoints()
        frame.pveLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y - 2)
        frame.pveLbl:Show()
        y = y + DIV_H
        y = layoutSpecRow(rows.pve, class, "PvE", y)
        y = y + ROW_GAP

        frame.pvpLbl:ClearAllPoints()
        frame.pvpLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y - 2)
        frame.pvpLbl:Show()
        y = y + DIV_H
        y = layoutSpecRow(rows.pvp, class, "PvP", y)
        y = y + ROW_GAP
    else
        frame.pveLbl:Hide(); frame.pvpLbl:Hide()
    end

    -- BOT INIT label (always shown - global gear re-roll).
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

    hideUnusedTiles()
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

    -- Re-render rows when the target changes.
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
        { "/wm",            "toggle the spec-swap HUD" },
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

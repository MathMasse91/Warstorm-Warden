-- =====================================================
-- Warden - WardenMantle.lua
-- Floating spec-swap HUD card (successor to feysSpecManager). Target a bot
-- and click a spec tile to whisper "talents spec <spec>" through the throttled
-- Engine.Queue; the swap is recorded by GUID so a Comp-tab Re-Spec re-applies
-- it after a retarget. The spec manager is the core of this HUD.
--
-- Alongside the spec tiles it also carries the global bot actions: Summon
-- (whispers `summon` straight to the targeted bot, un-throttled so it fires
-- instantly), Autogear, and a rarity dropdown + compact RB button that re-rolls
-- the targeted/all bots' gear via `.warstormbot bot init=<rarity>`. Chrome
-- (drag / lock / position / public API) clones WardenSword.lua.
--
-- Invariant: this file contains ZERO direct SendChatMessage calls - every
-- outbound message routes through ns.Engine.Queue / ns.Engine.WhisperAll /
-- ns.Engine.WhisperNow / SPEC_EXEC.
-- =====================================================

local _, ns = ...
ns.WardenMantle = ns.WardenMantle or {}

-- ----------------------------------------------------------
-- Geometry
-- ----------------------------------------------------------
local WIDTH      = 206
local HEADER_H   = 22
local PAD        = 8
local TILE_GAP   = 6
local CAP_H      = 12
local ROW_GAP    = 6
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
    title:SetText("WARDEN MANTLE")
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

-- Room reserved at the left of a spec row for its inline PvE/PvP label.
local LABEL_GUTTER = 28

-- Lay out one PvE/PvP row of spec tiles with its label on the SAME line (in the
-- left gutter, vertically centered on the tiles). Returns the y below the row.
local function layoutSpecRow(entries, class, modeLabel, topY, label)
    local n = #entries
    if n == 0 then
        if label then label:Hide() end
        return topY
    end
    -- Usable width for the tile row = frame minus BOTH side pads minus the
    -- label gutter. (The missing right pad is what pushed the druid's 4th icon
    -- and its "Balance" caption out past the right border.)
    local contentW = WIDTH - PAD * 2 - LABEL_GUTTER
    -- Fixed 30px icons regardless of spec count: druids have 4 PvE specs, and
    -- scaling the tile down by count made those icons tiny with captions piled
    -- on top of each other. Only shrink if a row genuinely can't fit at 30px.
    local tileW = 30
    if n * tileW + (n - 1) * TILE_GAP > contentW then
        tileW = math.max(18, math.floor((contentW - (n - 1) * TILE_GAP) / n))
    end
    local tileH = tileW
    -- Spread the gap so captions ("Balance", "Resto"...) don't collide, but cap
    -- it low: a large gap pushes the last tile (and its overhanging caption)
    -- rightward, back out of the frame. 10px is enough to separate captions.
    local gap = TILE_GAP
    if n > 1 then
        gap = math.min(10, math.max(TILE_GAP, math.floor((contentW - n * tileW) / (n - 1))))
    end
    local startX = PAD + LABEL_GUTTER
    local icons = ns.Data.SPEC_ICONS[class]
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]

    if label then
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(topY + math.floor((tileH - 12) / 2)))
        label:Show()
    end

    for i, e in ipairs(entries) do
        local t = nextTile()
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + (i - 1) * (tileW + gap), -topY)
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
            fn(name, true)  -- immediate=true: un-throttled whisper (no WM button throttles)

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

    -- Action row: Summon + Autogear (PARTY). Autogear is a global bot action;
    -- Summon is directed - it whispers `summon` straight to the targeted bot
    -- (that is the one you want pulled to you), not the party channel.
    local summonBtn = ns.UI.Button.stone(frame, "Summon", 60, 18)
    summonBtn:SetScript("OnClick", function()
        local name, class = resolveTarget()
        if not name then
            ns.MsgErr("Target a bot first.")
            return
        end
        ns.Engine.WhisperNow(name, "summon")
        ns.MsgInfo(string.format("Whispered `summon` -> %s.", ns.ColorClass(class, name)))
    end)
    frame.summonBtn = summonBtn

    local ag = ns.UI.Button.gold(frame, "Autogear", 60, 18)
    ag:SetScript("OnClick", function()
        ns.Engine.Queue("autogear", "PARTY")
        ns.MsgInfo("Sent `autogear` -> PARTY.")
    end)
    frame.autogear = ag

    -- Bot-gear re-roll: rarity dropdown + compact RB button. RB re-rolls bot
    -- gear via `.warstormbot bot init=<rarity>` on the command channel - routed
    -- through Engine.Queue so the no-direct-SendChatMessage invariant holds.
    -- The label is dropped (the rarity + RB tooltip carry the meaning).
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

    -- Compact "RB" button (was "ResetBot"): label stays tiny to shrink the
    -- card's footprint; the full meaning shows in a hover tooltip.
    local resetBtn = ns.UI.Button.gold(frame, "RB", 30, 20)
    resetBtn:SetScript("OnClick", function()
        local chan = (db() and db().commandChannel) or "SAY"
        local rarity = initRarity or "epic"
        ns.Engine.Queue(".warstormbot bot init=" .. rarity, chan)
        ns.MsgInfo(string.format("Sent `.warstormbot bot init=%s` (%s).", rarity, chan))
    end)
    ns.UI.Tooltip.Attach(resetBtn, "Reset Bot gear",
        "Re-rolls the targeted / all bots' gear at the selected rarity (.warstormbot bot init).",
        "ANCHOR_TOP")
    frame.resetBtn = resetBtn
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
        y = layoutSpecRow(rows.pve, class, "PvE", y, frame.pveLbl)
        y = y + ROW_GAP
        y = layoutSpecRow(rows.pvp, class, "PvP", y, frame.pvpLbl)
        y = y + ROW_GAP
    else
        frame.pveLbl:Hide(); frame.pvpLbl:Hide()
    end

    -- Gear re-roll row: rarity dropdown (left) + compact RB (right after it).
    -- UIDropDownMenuTemplate carries a ~16px left inset, so nudge x to line its
    -- text up with PAD; RB anchors to the dropdown's right edge (negative x to
    -- absorb the template's right chrome) so the pair reads as one control.
    frame.rarityDrop:ClearAllPoints()
    frame.rarityDrop:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 14, -y + 2)
    frame.rarityDrop:Show()
    frame.resetBtn:ClearAllPoints()
    frame.resetBtn:SetPoint("LEFT", frame.rarityDrop, "RIGHT", -6, 3)
    frame.resetBtn:Show()
    y = y + 24 + PAD

    hideUnusedTiles()
    frame:SetSize(WIDTH, y)
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

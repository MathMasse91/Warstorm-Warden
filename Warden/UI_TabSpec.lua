-- =====================================================
-- Warden - UI_TabSpec.lua
-- Direction I rebuild, faithful to wireframes.html V1:
--   Target card:  60x60 portrait + 22px gold-rim level badge overlay
--                 [class-colored name] [- Class - Faction] mono
--                 "whisper talents spec <name> -> applies + tracks by GUID" mono
--                 < prev target - history  - spacer - autogear -> PARTY - buffs -> RAID
--   Specs panel (header + "N available" meta):
--                 4-col grid of tiles
--                 Each tile: class-colored name, "pve - hint" subtitle,
--                            22x22 icon slot (top-right)
--                 Recommended tile = gold inner border + "* talent preview"
-- =====================================================

local _, ns = ...
ns.UI.Tabs      = ns.UI.Tabs      or {}
ns.UI.Tabs.Spec = ns.UI.Tabs.Spec or {}

-- ----------------------------------------------------------
-- Spec subtitle hints: "pve - burst" style categorization
-- ----------------------------------------------------------
local SPEC_HINT = {
    WARRIOR = {
        ["prot pve"] = "pve - tank",  ["arms pve"] = "pve - burst",    ["fury pve"] = "pve - sustained",
        ["prot pvp"] = "pvp - tank",  ["arms pvp"] = "pvp - burst",    ["fury pvp"] = "pvp - burst",
    },
    PALADIN = {
        ["prot pve"] = "pve - tank",  ["holy pve"] = "pve - heal",     ["ret pve"]  = "pve - sustained",
        ["prot pvp"] = "pvp - tank",  ["holy pvp"] = "pvp - heal",     ["ret pvp"]  = "pvp - burst",
    },
    HUNTER = {
        ["bm pve"] = "pve - pet",     ["mm pve"] = "pve - burst",      ["surv pve"] = "pve - sustained",
        ["bm pvp"] = "pvp - pet",     ["mm pvp"] = "pvp - burst",      ["surv pvp"] = "pvp - cc",
    },
    ROGUE = {
        ["as pve"] = "pve - sustained", ["combat pve"] = "pve - sustained", ["subtlety pve"] = "pve - burst",
        ["as pvp"] = "pvp - burst",     ["combat pvp"] = "pvp - burst",     ["subtlety pvp"] = "pvp - burst",
    },
    PRIEST = {
        ["holy pve"] = "pve - heal",  ["disc pve"] = "pve - heal",     ["shadow pve"] = "pve - dps",
        ["holy pvp"] = "pvp - heal",  ["disc pvp"] = "pvp - heal",     ["shadow pvp"] = "pvp - dps",
    },
    SHAMAN = {
        ["resto pve"] = "pve - heal", ["ele pve"]  = "pve - burst",    ["enh pve"]   = "pve - melee",
        ["resto pvp"] = "pvp - heal", ["ele pvp"]  = "pvp - burst",    ["enh pvp"]   = "pvp - melee",
    },
    MAGE = {
        ["arcane pve"] = "pve - burst",     ["fire pve"] = "pve - sustained",  ["frost pve"] = "pve - sustained",
        ["frostfire pve"] = "pve - ffb",    ["arcane pvp"] = "pvp - burst",    ["fire pvp"] = "pvp - burst",
        ["frost pvp"] = "pvp - cc",
    },
    WARLOCK = {
        ["affli pve"] = "pve - sustained", ["demo pve"] = "pve - sustained", ["destro pve"] = "pve - burst",
        ["affli pvp"] = "pvp - sustained", ["demo pvp"] = "pvp - tank",      ["destro pvp"] = "pvp - burst",
    },
    DRUID = {
        ["bear pve"] = "pve - tank",  ["cat pve"]  = "pve - melee",    ["resto pve"] = "pve - heal",
        ["balance pve"] = "pve - dps",
        ["cat pvp"]  = "pvp - melee", ["resto pvp"] = "pvp - heal",    ["balance pvp"] = "pvp - dps",
    },
    DEATHKNIGHT = {
        ["blood pve"] = "pve - tank", ["frost pve"] = "pve - dps",     ["unholy pve"] = "pve - dps",
        ["da blood pve"] = "pve - dual aura",
        ["blood pvp"] = "pvp - melee",["frost pvp"] = "pvp - dps",     ["unholy pvp"] = "pvp - dps",
    },
}

local function specHint(classToken, spec)
    local t = SPEC_HINT[classToken]
    return (t and t[spec]) or "pve"
end

-- ----------------------------------------------------------
-- Module state
-- ----------------------------------------------------------
local tabState = {
    pane         = nil,
    tiles        = {},
    targetEvents = nil,
    history      = {},  -- ring buffer of last 6 player names seen as target
    historyMax   = 6,
}

-- ----------------------------------------------------------
-- Target history (targeting the same player twice doesn't duplicate)
-- ----------------------------------------------------------
local function pushHistory(name)
    if not name or name == "" then return end
    for i, n in ipairs(tabState.history) do
        if n == name then table.remove(tabState.history, i); break end
    end
    table.insert(tabState.history, 1, name)
    while #tabState.history > tabState.historyMax do
        table.remove(tabState.history)
    end
    -- Re-bind secure macrotext on history rows so clicks target the right name.
    if tabState.refreshHistoryPopup then
        tabState.refreshHistoryPopup()
    end
end

-- ----------------------------------------------------------
-- Target card refresh
-- ----------------------------------------------------------
local function refreshTargetCard()
    local s = tabState
    if not s.nameLbl then return end

    if UnitExists("target") and UnitIsPlayer("target") then
        local name        = UnitName("target") or "?"
        local _, classTok = UnitClass("target")
        local level       = UnitLevel("target") or 0
        local className   = (classTok and ns.Data.CLASS_LABEL and ns.Data.CLASS_LABEL[classTok]) or classTok or "?"
        local faction     = UnitFactionGroup("target") or ""

        SetPortraitTexture(s.portrait, "target")
        s.portraitBorder:Show()
        s.levelBadge:Show()
        s.levelText:SetText(tostring(level))

        s.nameLbl:SetText(ns.ColorClass(classTok or "", name))
        s.metaLbl:SetText(string.format("- %s - %s",
            ns.ColorClass(classTok or "", className),
            faction ~= "" and faction or "Unknown"))
        s.hintLbl:SetText("whisper |cffffd100talents spec <name>|r -> applies + tracks by GUID")

        pushHistory(name)
    else
        s.portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
        s.portraitBorder:Hide()
        s.levelBadge:Hide()
        s.nameLbl:SetText("|cff808080no target|r")
        s.metaLbl:SetText("")
        s.hintLbl:SetText("target a player to see spec tiles")
    end
end

-- ----------------------------------------------------------
-- Spec tiles
-- ----------------------------------------------------------
local function clearTiles()
    for _, t in ipairs(tabState.tiles) do t:Hide() end
    if tabState.placeholders then
        for _, p in ipairs(tabState.placeholders) do p:Hide() end
    end
end

-- Which spec should the gold rim mark for this class? Returns
-- (specName, source) where source is "assigned" (target has a live
-- entry in ns.Engine.state.assignedSpecs) or "default" (no assignment
-- yet; falling back to the class's PvE default so a fresh target still
-- gets a sensible "suggested" highlight on first view).
local function highlightedSpecFor(classToken)
    if UnitExists("target") and UnitIsPlayer("target") then
        local guid = UnitGUID("target")
        local tbl  = guid
            and ns.Engine and ns.Engine.state
            and ns.Engine.state.assignedSpecs
            and ns.Engine.state.assignedSpecs[guid]
        if tbl and tbl.spec then return tbl.spec, "assigned" end
    end
    return ns.Data.DEFAULT_SPEC_PVE and ns.Data.DEFAULT_SPEC_PVE[classToken], "default"
end

local function rebuildTilesFor(classToken)
    clearTiles()
    local panel = tabState.specsPanel
    if not panel then return end
    local content = panel.content

    local specs = ns.Data.CLASS_SPECS[classToken]
    if not specs or #specs == 0 then
        tabState.emptyLbl:SetText(classToken
            and ("No spec data for class " .. classToken .. ".")
            or  "Target a player to see spec tiles.")
        tabState.emptyLbl:Show()
        if tabState.countLbl then tabState.countLbl:SetText("") end
        return
    end
    tabState.emptyLbl:Hide()

    if tabState.countLbl then
        tabState.countLbl:SetText(string.format("%d available", #specs))
    end

    local recommended, recSource = highlightedSpecFor(classToken)

    local cols       = 4
    local gap        = 8
    local panelW     = content:GetWidth()
    local tileW      = math.floor((panelW - (cols - 1) * gap) / cols)
    local tileH      = 54
    local startY     = -4

    for i, specName in ipairs(specs) do
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        local tile = tabState.tiles[i]
        if not tile then
            tile = CreateFrame("Button", nil, content)
            tile:EnableMouse(true)
            tile:RegisterForClicks("LeftButtonUp")
            tile:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })

            local name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            name:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -8)
            tile.nameLbl = name

            local sub = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
            tile.subLbl = sub

            -- 22x22 icon slot (top-right corner)
            local iconSlot = CreateFrame("Frame", nil, tile)
            iconSlot:SetSize(22, 22)
            iconSlot:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -6, -6)
            iconSlot:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            iconSlot:SetBackdropColor(0.04, 0.03, 0.02, 1)
            iconSlot:SetBackdropBorderColor(0.23, 0.18, 0.13, 1)
            tile.iconSlot = iconSlot

            -- "* talent preview" hint (shown on recommended tile only).
            -- Review asked for a larger / brighter label than GameFontDisableSmall
            -- so the "recommended" mark is readable at a glance.
            local recLbl = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            recLbl:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -6, 5)
            recLbl:SetTextColor(1, 0.82, 0)
            recLbl:Hide()
            tile.recLbl = recLbl

            -- PATCH_NOTES §16a: hover changes RIM (not fill) so tile identity
            -- stays consistent, and OnLeave restores gold rim for selected
            -- tiles vs stone rim for non-selected.
            tile:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(0.35, 0.29, 0.19, 1) -- stone-rim-hi
            end)
            tile:SetScript("OnLeave", function(self)
                if self._isRec then
                    self:SetBackdropBorderColor(0.66, 0.54, 0.30, 1) -- gold-rim
                else
                    self:SetBackdropBorderColor(0.23, 0.18, 0.13, 1) -- stone-rim
                end
            end)
            tabState.tiles[i] = tile
        end

        tile:SetSize(tileW, tileH)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", content, "TOPLEFT",
            col * (tileW + gap), startY - row * (tileH + 8))

        tile.nameLbl:SetText(ns.ColorClass(classToken, specName))
        tile.subLbl:SetText(specHint(classToken, specName))

        local isRec = (recommended == specName)
        tile._isRec = isRec
        if isRec then
            tile:SetBackdropColor(0.10, 0.08, 0.05, 1)
            tile:SetBackdropBorderColor(0.66, 0.54, 0.30, 1) -- gold-rim
            tile.recLbl:SetText(recSource == "assigned" and "* current" or "* default")
            tile.recLbl:Show()
        else
            tile:SetBackdropColor(0.10, 0.08, 0.05, 1)
            tile:SetBackdropBorderColor(0.23, 0.18, 0.13, 1) -- stone-rim
            tile.recLbl:Hide()
        end

        tile:SetScript("OnClick", function()
            if not (UnitExists("target") and UnitIsPlayer("target")) then
                ns.MsgErr("Target a player first.")
                return
            end
            local targetName  = UnitName("target")
            local targetGUID  = UnitGUID("target")
            local _, curClass = UnitClass("target")
            if curClass ~= classToken then
                ns.MsgWarn("Target changed class - retarget and try again.")
                return
            end

            local tbl = ns.Data.SPEC_EXEC[classToken]
            local fn  = tbl and tbl[specName]
            if not fn then
                ns.MsgWarn("No execution defined for " .. classToken .. " - " .. specName)
                return
            end
            fn()

            if targetGUID and ns.Engine and ns.Engine.state and ns.Engine.state.assignedSpecs then
                local prev = ns.Engine.state.assignedSpecs[targetGUID] or {}
                ns.Engine.state.assignedSpecs[targetGUID] = {
                    name       = targetName,
                    spec       = specName,
                    classToken = classToken,
                    opt1       = prev.opt1,
                    opt2       = prev.opt2,
                }
            end
            ns.MsgInfo(string.format("Sent `talents spec %s` -> %s.",
                specName, ns.ColorClass(classToken, targetName)))

            -- BUG: the gold rim used to stay on the class's PvE default even
            -- after the user clicked a different tile, because `recommended`
            -- was computed once from static data and never re-read. Now that
            -- highlightedSpecFor() consults the live assignedSpecs table,
            -- rebuilding the tiles here makes the highlight follow the click.
            rebuildTilesFor(classToken)
        end)
        tile:Show()
    end

    -- PATCH_NOTES §16b: pad the 4-col grid up to 8 tiles with "- empty"
    -- dashed placeholders so orphan specs (e.g. Mage's 4 PvE) don't sit
    -- alone on row 1 column 4 with no row 2 continuation.
    tabState.placeholders = tabState.placeholders or {}
    for i = #specs + 1, 8 do
        local phIdx = i - #specs
        local ph = tabState.placeholders[phIdx]
        if not ph then
            ph = CreateFrame("Frame", nil, content)
            ph:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            ph:SetBackdropColor(0.06, 0.05, 0.03, 0.6)
            ph:SetBackdropBorderColor(0.18, 0.14, 0.10, 1)
            ph.lbl = ph:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            ph.lbl:SetPoint("CENTER", ph, "CENTER", 0, 0)
            ph.lbl:SetText("- empty -")
            ph.lbl:SetTextColor(0.42, 0.36, 0.27, 1)
            tabState.placeholders[phIdx] = ph
        end
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        ph:SetSize(tileW, tileH)
        ph:ClearAllPoints()
        ph:SetPoint("TOPLEFT", content, "TOPLEFT",
            col * (tileW + gap), startY - row * (tileH + 8))
        ph:Show()
    end
    -- Hide placeholders beyond 8-spec count
    for i = math.max(1, 8 - #specs + 1), #(tabState.placeholders or {}) do
        if tabState.placeholders[i] then tabState.placeholders[i]:Hide() end
    end
end

local function refreshForTarget()
    local pane = tabState.pane
    if not pane or not pane:IsShown() then return end
    if ns.DebugF then
        local hasT = UnitExists("target") and UnitIsPlayer("target")
        ns.DebugF("spec", "refreshForTarget: target=%s",
            hasT and (UnitName("target") or "?") or "(none)")
    end
    refreshTargetCard()
    if UnitExists("target") and UnitIsPlayer("target") then
        local _, classToken = UnitClass("target")
        if classToken and ns.Data.CLASS_SPECS[classToken] then
            rebuildTilesFor(classToken)
        else
            clearTiles()
            tabState.emptyLbl:SetText("No spec data for this target's class.")
            tabState.emptyLbl:Show()
            if tabState.countLbl then tabState.countLbl:SetText("") end
        end
    else
        clearTiles()
        tabState.emptyLbl:SetText("Target a player to see spec tiles.")
        tabState.emptyLbl:Show()
        if tabState.countLbl then tabState.countLbl:SetText("") end
    end
end

-- ----------------------------------------------------------
-- BuildInto
-- ----------------------------------------------------------
function ns.UI.Tabs.Spec.BuildInto(pane)
    tabState.pane = pane
    local paneW = pane:GetWidth()
    local paneH = pane:GetHeight()

    -- ============================================================
    -- Target card
    -- ============================================================
    local cardH = 100
    local cardPanel = ns.UI.Panel.Create(pane, paneW - 16, cardH, "Target")
    cardPanel:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -4)
    tabState.cardPanel = cardPanel

    -- Portrait 60x60 with 1px frame
    local portrait = cardPanel.content:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(60, 60)
    portrait:SetPoint("TOPLEFT", cardPanel.content, "TOPLEFT", 4, -4)
    portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
    tabState.portrait = portrait

    local portraitBorder = CreateFrame("Frame", nil, cardPanel.content)
    portraitBorder:SetPoint("TOPLEFT",     portrait, "TOPLEFT",     -1, 1)
    portraitBorder:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT",  1, -1)
    portraitBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    -- Rim bumped from #7a6642 to #a88a4c so target card reads as gold-bordered
    -- per the spec-review P2 note.
    portraitBorder:SetBackdropBorderColor(0.66, 0.54, 0.30, 1)
    tabState.portraitBorder = portraitBorder

    -- Level badge: 22px square with fully opaque dark-brown fill + gold rim.
    -- BUG-03: previously alpha = 1 but the darker outer portrait border
    -- bled through visually (render order). Bump frame level so the badge
    -- draws unambiguously above `portraitBorder`, and switch bg to the
    -- warmer panel-theme brown so it reads as a solid badge.
    local badge = CreateFrame("Frame", nil, cardPanel.content)
    badge:SetSize(22, 22)
    badge:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 8, -6)
    badge:SetFrameStrata(cardPanel:GetFrameStrata())
    badge:SetFrameLevel((portraitBorder:GetFrameLevel() or 0) + 4)
    badge:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    badge:SetBackdropColor(0.10, 0.06, 0.02, 1) -- fully opaque dark brown
    badge:SetBackdropBorderColor(0.72, 0.58, 0.21, 1) -- gold-dim
    badge:Hide()
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("CENTER", badge, "CENTER", 0, 0)
    badgeText:SetTextColor(1, 0.82, 0)
    tabState.levelBadge = badge
    tabState.levelText  = badgeText

    -- "target" label (small muted)
    local targetHdr = cardPanel.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    targetHdr:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 14, -2)
    targetHdr:SetText("TARGET")
    targetHdr:SetTextColor(0.72, 0.58, 0.21, 1)

    local nameLbl = cardPanel.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameLbl:SetPoint("TOPLEFT", targetHdr, "BOTTOMLEFT", 0, -2)
    nameLbl:SetText("|cff808080no target|r")
    tabState.nameLbl = nameLbl

    local metaLbl = cardPanel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    metaLbl:SetPoint("LEFT", nameLbl, "RIGHT", 8, -1)
    metaLbl:SetTextColor(0.61, 0.55, 0.40)
    tabState.metaLbl = metaLbl

    local hintLbl = cardPanel.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintLbl:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -4)
    hintLbl:SetText("target a player to see spec tiles")
    tabState.hintLbl = hintLbl

    -- Action row: prev target - history - spacer - autogear - buffs
    -- BUG-02: the `< prev target` button and the per-entry history items
    -- all call a protected Blizzard API (`/target <name>`). Doing that from
    -- an insecure OnClick is tainted and trips the "Warden has been blocked
    -- from an action only available to the Blizzard UI" popup. Use
    -- SecureActionButtonTemplate buttons so the client treats the /target
    -- call as secure. Attribute updates are skipped while in combat so
    -- clicking one during a pull doesn't try to mutate secure state.
    local actionY = -72

    local TOK = ns.Tokens
    local function makeSecureStoneBtn(parent, label, w, h)
        local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
        b:SetSize(w or 80, h or 20)
        b:EnableMouse(true)
        b:RegisterForClicks("AnyUp")
        b:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        b:SetBackdropColor(TOK.stone_tile[1], TOK.stone_tile[2], TOK.stone_tile[3], 1)
        b:SetBackdropBorderColor(TOK.stone_rim[1], TOK.stone_rim[2], TOK.stone_rim[3], 1)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(label or "")
        fs:SetTextColor(TOK.gold_dim[1], TOK.gold_dim[2], TOK.gold_dim[3], 1)
        b:SetFontString(fs)
        local hi = b:CreateTexture(nil, "HIGHLIGHT")
        hi:SetTexture("Interface\\Buttons\\WHITE8x8")
        hi:SetAllPoints(b)
        hi:SetBlendMode("ADD")
        hi:SetVertexColor(1, 1, 1, 0.1)
        b:SetHighlightTexture(hi)
        return b
    end

    local function inCombat()
        return InCombatLockdown and InCombatLockdown()
    end

    -- `< prev target` - SecureActionButton invoking `/targetlasttarget`.
    -- The macrotext is static so no attribute mutation is ever required
    -- after creation.
    -- UI tweak: anchor the action row BELOW the Target panel (in the gap
    -- between the two brown blocks) instead of inside it. cardPanel stays
    -- fixed; SPECS_GAP is widened below to give the row breathing room.
    local prevBtn = makeSecureStoneBtn(cardPanel, "< prev target", 100, 20)
    prevBtn:SetPoint("TOPLEFT", cardPanel, "BOTTOMLEFT", 4, -6)
    prevBtn:SetAttribute("type", "macro")
    prevBtn:SetAttribute("macrotext", "/targetlasttarget")

    -- History popup: click the "history" button to toggle a small floating
    -- panel containing up to 6 secure buttons. Each button is a
    -- SecureActionButton whose macrotext is pre-assigned to `/target <name>`
    -- out of combat; clicking fires the protected call through the secure
    -- path (no taint).
    local histBtn = ns.UI.Button.stone(cardPanel, "history v", 78, 20)
    histBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    tabState.histBtn = histBtn

    local histPop = CreateFrame("Frame", "WardenSpecHistoryPopup", cardPanel)
    histPop:SetSize(140, 10)
    histPop:SetPoint("TOPLEFT", histBtn, "BOTTOMLEFT", 0, -2)
    histPop:SetFrameStrata("DIALOG")
    histPop:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    histPop:SetBackdropColor(0.10, 0.06, 0.02, 1)
    histPop:SetBackdropBorderColor(TOK.gold_dim[1], TOK.gold_dim[2], TOK.gold_dim[3], 1)
    histPop:Hide()
    tabState.histPop = histPop

    local POPUP_ROWS = 6
    tabState.histPopRows = {}
    for i = 1, POPUP_ROWS do
        local row = makeSecureStoneBtn(histPop, "", 128, 18)
        row:SetPoint("TOPLEFT", histPop, "TOPLEFT", 6, -4 - (i - 1) * 20)
        row:SetAttribute("type", "macro")
        row:SetScript("PostClick", function() histPop:Hide() end)
        tabState.histPopRows[i] = row
    end

    local function refreshHistoryPopup()
        if inCombat() then
            -- Secure attributes are locked in combat. Hide popup so the
            -- user can't try to click a stale entry.
            histPop:Hide()
            return
        end
        local hist = tabState.history or {}
        local n = math.min(#hist, POPUP_ROWS)
        for i = 1, POPUP_ROWS do
            local row = tabState.histPopRows[i]
            if i <= n then
                local nm = hist[i]
                row:SetAttribute("macrotext", "/target " .. nm)
                if row:GetFontString() then row:GetFontString():SetText(nm) end
                row:Show()
            else
                -- Clear macrotext so clicks do nothing if stale.
                row:SetAttribute("macrotext", "")
                row:Hide()
            end
        end
        histPop:SetHeight(8 + math.max(1, n) * 20)
        if n == 0 then
            local r = tabState.histPopRows[1]
            if r:GetFontString() then r:GetFontString():SetText("|cff808080(empty)|r") end
            r:Show()
            -- Don't let a click fire when empty.
            r:SetAttribute("macrotext", "")
        end
    end

    histBtn:SetScript("OnClick", function()
        if histPop:IsShown() then
            histPop:Hide()
            return
        end
        refreshHistoryPopup()
        histPop:Show()
    end)

    -- Close popup when clicking elsewhere on the pane.
    histPop:SetScript("OnLeave", function(self)
        -- Delayed hide so a child-button click registers first.
        self:SetScript("OnUpdate", function(s, e)
            s._t = (s._t or 0) + (e or 0)
            if s._t > 0.15 then s._t = 0; s:SetScript("OnUpdate", nil); s:Hide() end
        end)
    end)
    histPop:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", nil); self._t = 0
    end)

    -- Combat transitions: hide popup on REGEN_DISABLED, refresh on REGEN_ENABLED.
    local combatWatch = CreateFrame("Frame", nil, cardPanel)
    combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatch:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            histPop:Hide()
        elseif event == "PLAYER_REGEN_ENABLED" and histPop:IsShown() then
            refreshHistoryPopup()
        end
    end)

    tabState.refreshHistoryPopup = refreshHistoryPopup

    -- Autogear / Buffs (right side) - anchored below cardPanel like the pair
    -- on the left, so all four buttons sit on the same baseline in the gap.
    local buffsBtn = ns.UI.Button.stone(cardPanel, "buffs -> RAID", 110, 20)
    buffsBtn:SetPoint("TOPRIGHT", cardPanel, "BOTTOMRIGHT", -4, -6)
    buffsBtn:SetScript("OnClick", function()
        SendChatMessage("nc +worldbuff", ns.Channel())
        ns.MsgInfo("Broadcast `nc +worldbuff` to " .. ns.Channel() .. ".")
    end)

    local autogearBtn = ns.UI.Button.stone(cardPanel, "autogear -> PARTY", 130, 20)
    autogearBtn:SetPoint("RIGHT", buffsBtn, "LEFT", -4, 0)
    autogearBtn:SetScript("OnClick", function()
        SendChatMessage("autogear", "PARTY")
        ns.MsgInfo("Broadcast `autogear` to PARTY.")
    end)

    -- ============================================================
    -- Specs grid panel
    -- ============================================================
    -- UI-01: the action row (< prev target / history / autogear / buffs)
    -- is now anchored BELOW cardPanel, so SPECS_GAP has to hold 6px top
    -- margin + 20px button + 6px bottom margin = 32px. Previously 16px
    -- when the buttons lived inside cardPanel.content.
    local SPECS_GAP = 32
    local specsH = paneH - cardH - (SPECS_GAP + 10)
    local specsPanel = ns.UI.Panel.Create(pane, paneW - 16, specsH, "Specs")
    specsPanel:SetPoint("TOPLEFT", cardPanel, "BOTTOMLEFT", 0, -SPECS_GAP)
    tabState.specsPanel = specsPanel

    -- "N available" meta in panel header
    local countLbl = specsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countLbl:SetPoint("TOPRIGHT", specsPanel, "TOPRIGHT", -6, -4)
    countLbl:SetTextColor(0.61, 0.55, 0.40)
    tabState.countLbl = countLbl

    local emptyLbl = specsPanel.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLbl:SetPoint("CENTER", specsPanel.content, "CENTER", 0, 0)
    emptyLbl:SetText("Target a player to see spec tiles.")
    tabState.emptyLbl = emptyLbl

    -- ============================================================
    -- Event wiring
    -- ============================================================
    if not tabState.targetEvents then
        tabState.targetEvents = CreateFrame("Frame", nil, pane)
        tabState.targetEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        tabState.targetEvents:SetScript("OnEvent", refreshForTarget)
    end

    refreshForTarget()
end

function ns.UI.Tabs.Spec.OnShow(pane)
    refreshForTarget()
end

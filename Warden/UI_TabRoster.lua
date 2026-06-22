-- =====================================================
-- Warden - UI_TabRoster.lua
-- Direction I rebuild, faithful to wireframes.html V1:
--   Filter row:  [filter label] [All ] [search...] [Refresh]
--   Panel (3 grouped sections):
--     Tanks <count>                     (Cinzel gold uppercase + count pill)
--       [chk][av 20x20][nm line 1 (class-colored)/nm line 2 mono "Class - spec pve"]
--       [spec ]  [3 dots: stone=present red=missing]  [R sq button]
--     Healers <count>
--     DPS <count>
--   Bottom: [R Re-Spec All Tracked] [R Re-Spec Selected]  [N selected mono]
-- =====================================================

local _, ns = ...
ns.UI.Tabs        = ns.UI.Tabs        or {}
ns.UI.Tabs.Roster = ns.UI.Tabs.Roster or {}

-- ----------------------------------------------------------
-- Module state
-- ----------------------------------------------------------
local frame
local scroll, content
local rows        = {}
local headers     = {}
local ROW_COUNTER = 0
local ROW_HEIGHT  = 24
local ROW_SPACING = 2
local SECTION_GAP = 6
local HEADER_H    = 20
local built       = false

local filterState = { role = "all", query = "" }
local selectedCount = 0
local colorClass = ns.ColorClass

-- ----------------------------------------------------------
-- Role inference
-- ----------------------------------------------------------
local TANK_SPECS = {
    WARRIOR     = { ["prot pve"] = true, ["prot pvp"] = true },
    PALADIN     = { ["prot pve"] = true, ["prot pvp"] = true },
    DRUID       = { ["bear pve"] = true, ["bear pvp"] = true },
    -- WotLK 3.3.5a post-3.2: Blood is the dedicated tank tree; Frost and
    -- Unholy are DPS (dual-wield / 2H). Only Blood variants classify as
    -- tank here. "da blood pve" (double-aura blood) is also a tank spec.
    DEATHKNIGHT = { ["blood pve"] = true, ["da blood pve"] = true,
                    ["blood pvp"] = true },
}
local HEAL_SPECS = {
    PRIEST  = { ["holy pve"]  = true, ["disc pve"]  = true, ["holy pvp"]  = true, ["disc pvp"]  = true },
    PALADIN = { ["holy pve"]  = true, ["holy pvp"]  = true },
    SHAMAN  = { ["resto pve"] = true, ["resto pvp"] = true },
    DRUID   = { ["resto pve"] = true, ["resto pvp"] = true },
}

-- Melee DPS specs. Anything that's a non-tank, non-heal spec on a melee
-- class falls in here; everything else (Hunter, Mage, Warlock, Shadow
-- Priest, Ele Sham, Boomkin) falls through to "ranged".
local MELEE_DPS_SPECS = {
    WARRIOR     = { ["arms pve"] = true, ["fury pve"] = true,
                    ["arms pvp"] = true, ["fury pvp"] = true },
    PALADIN     = { ["ret pve"]  = true, ["ret pvp"]  = true },
    ROGUE       = { ["as pve"]   = true, ["combat pve"] = true, ["subtlety pve"] = true,
                    ["as pvp"]   = true, ["combat pvp"] = true, ["subtlety pvp"] = true },
    SHAMAN      = { ["enh pve"]  = true, ["enh pvp"]  = true },
    DRUID       = { ["cat pve"]  = true, ["cat pvp"]  = true },
    DEATHKNIGHT = { ["frost pve"]  = true, ["unholy pve"]  = true,
                    ["frost pvp"]  = true, ["unholy pvp"]  = true },
}

local function inferRole(classToken, spec)
    if not classToken or not spec then return "ranged" end
    if TANK_SPECS[classToken]      and TANK_SPECS[classToken][spec]      then return "tank"   end
    if HEAL_SPECS[classToken]      and HEAL_SPECS[classToken][spec]      then return "heal"   end
    if MELEE_DPS_SPECS[classToken] and MELEE_DPS_SPECS[classToken][spec] then return "melee"  end
    return "ranged"
end

-- Fallback spec for an untracked raid member (no GUID -> assignedSpecs
-- entry yet). Players themselves never get an assignedSpec because Build
-- skips [P] slots, so every real human falls through here. CLASS_SPECS[1]
-- is the wrong default for hybrid classes - the table happens to list
-- tank/heal first for Warrior/Paladin/DK/Druid/Shaman/Priest, which
-- would parade a Cat druid into the TANKS section as "bear pve". Skip
-- tank+heal entries and pick the first DPS spec instead. Result per
-- class: WAR -> arms, PAL -> ret, DK -> frost, SHAM -> ele, DRU -> cat,
-- PRI -> shadow; pure-DPS classes keep their existing first entry.
local function fallbackSpec(classToken)
    local specs = ns.Data.CLASS_SPECS[classToken] or {}
    for _, sp in ipairs(specs) do
        local isTank = TANK_SPECS[classToken] and TANK_SPECS[classToken][sp]
        local isHeal = HEAL_SPECS[classToken] and HEAL_SPECS[classToken][sp]
        if not isTank and not isHeal then return sp end
    end
    return specs[1] or "-"
end

-- ----------------------------------------------------------
-- Per-class "provides" scan (TASKS.md §3.1). Each class yields 0..N chips
-- describing the buffs it can itself deliver to the raid; chip ON = the
-- buff is currently active on this member. No 3-dot "paladin / shaman /
-- warrior" signal per row any more - that never made sense for priests
-- or mages.
-- ----------------------------------------------------------
local PROVIDES_BY_CLASS = {
    PALADIN = {
        { label = "KNG", patterns = { "Blessing of Kings" } },
        { label = "MGT", patterns = { "Blessing of Might" } },
        { label = "WIS", patterns = { "Blessing of Wisdom" } },
        { label = "SAN", patterns = { "Blessing of Sanctuary" } },
    },
    SHAMAN = {
        { label = "SoE", patterns = { "Strength of Earth" } },
        { label = "WF",  patterns = { "Windfury Totem" } },
        { label = "FT",  patterns = { "Flametongue Totem" } },
        { label = "MS",  patterns = { "Mana Spring" } },
    },
    WARRIOR = {
        { label = "BS", patterns = { "Battle Shout" } },
        { label = "CS", patterns = { "Commanding Shout" } },
    },
    DEATHKNIGHT = {
        { label = "HoW", patterns = { "Horn of Winter" } },
    },
    HUNTER = {
        { label = "ASP", patterns = { "Aspect of " } },
    },
    DRUID = {
        { label = "MoW", patterns = { "Mark of the Wild", "Gift of the Wild" } },
    },
    -- Priest / Mage / Warlock / Rogue deliberately left empty (§3.1).
}

-- UX-01: the chips now reflect what buffs this slot's class is ASSIGNED
-- to cast in the current comp (from Engine.state.assignedSpecs[guid]),
-- not what buffs are currently on the unit. Planning view, not live
-- status view.
-- Shared splitSet implementation lives in Data.lua now.
local splitSetLocal = ns.Data.SplitSet

-- Map a chip label to whether the slot's assigned opt1/opt2 cover it.
local function chipIsAssigned(classToken, label, opt1Set, opt2Set)
    if classToken == "PALADIN" then
        local key = ({ KNG = "kings", MGT = "might", WIS = "wisdom", SAN = "sanctuary" })[label]
        return key ~= nil and (opt1Set[key] or opt2Set[key]) or false
    elseif classToken == "WARRIOR" then
        local key = ({ BS = "battle", CS = "commanding" })[label]
        return key ~= nil and (opt1Set[key] or opt2Set[key]) or false
    elseif classToken == "HUNTER" then
        return label == "ASP" and (opt1Set["aotw"] or opt2Set["aotw"]) or false
    elseif classToken == "SHAMAN" then
        -- Shaman opt1 is a totem SET name (melee / caster / healing / ...).
        -- Map each chip to the sets that include that totem.
        local set = (next(opt1Set))
        if label == "SoE" then return set == "melee" end
        if label == "WF"  then return set == "melee" end
        if label == "FT"  then return set == "melee" or set == "caster" end
        if label == "MS"  then return set == "caster" or set == "healing" end
        return false
    end
    -- Druid MoW + DK HoW aren't strat toggles in the bot layer today; we
    -- display the chip but leave it muted.
    return false
end

local function scanProvides(unit, classToken, guid)
    local defs = PROVIDES_BY_CLASS[classToken or ""]
    if not defs then return {} end
    local out = {}

    local tracked = guid and ns.Engine.state.assignedSpecs
        and ns.Engine.state.assignedSpecs[guid]
    local opt1Set = splitSetLocal(tracked and tracked.opt1)
    local opt2Set = splitSetLocal(tracked and tracked.opt2)

    for _, def in ipairs(defs) do
        out[#out + 1] = {
            label = def.label,
            on    = chipIsAssigned(classToken, def.label, opt1Set, opt2Set) and true or false,
        }
    end
    return out
end

-- ----------------------------------------------------------
-- Raid / party unit enumeration
-- ----------------------------------------------------------
local function iterRaidUnits()
    local list = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do list[#list + 1] = "raid" .. i end
    else
        list[#list + 1] = "player"
        for i = 1, GetNumPartyMembers() do list[#list + 1] = "party" .. i end
    end
    return list
end

local function whisperSpec(name, spec, classToken, opt1, opt2)
    if not name or not spec or spec == "" or spec == "-" then return end
    ns.Engine.PushWhisper({
        name = name, spec = spec, classToken = classToken, opt1 = opt1, opt2 = opt2,
    })
end

-- Shared class-icon atlas lives in Data.lua (ns.Data.CLASS_ICON).
local CLASS_ICON = ns.Data.CLASS_ICON

-- ----------------------------------------------------------
-- Selected count refresh (called from checkbox clicks)
-- ----------------------------------------------------------
local function refreshSelectedCount()
    selectedCount = 0
    for _, r in ipairs(rows) do
        if r.frame and r.frame:IsShown() and r.cb:GetChecked() then
            selectedCount = selectedCount + 1
        end
    end
    if frame and frame.selCountLbl then
        frame.selCountLbl:SetText(selectedCount .. " selected")
    end
end

-- ----------------------------------------------------------
-- Row widget - wireframe grid: 14 - 22 - 1.2fr - 1fr - 70 - 28
-- We approximate with fixed pixel anchors tuned for a 676-wide content area.
-- ----------------------------------------------------------
local function createRowWidget()
    ROW_COUNTER = ROW_COUNTER + 1
    local rowName = "WardenRosterRow" .. ROW_COUNTER
    local f = CreateFrame("Frame", rowName, content)
    f:SetHeight(ROW_HEIGHT)

    -- FEATURE-02: [P] flag toggle at left edge. Persists the "is human
    -- player" decision by character name via WardenDB.playerFlags so
    -- subsequent Re-Spec / auto-spec / whisper flows skip this slot.
    local pBtn = ns.UI.Button.stone(f, "P", 20, 18)
    pBtn:SetPoint("LEFT", f, "LEFT", 0, 0)
    local pFs = pBtn:GetFontString()
    if pFs then pFs:SetTextColor(0.45, 0.38, 0.28, 1) end

    local cb = CreateFrame("CheckButton", rowName .. "Cb", f, "InterfaceOptionsCheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", pBtn, "RIGHT", 4, 0)
    cb:SetScript("OnClick", refreshSelectedCount)

    -- Class avatar (20x20 cropped from Classes-Circles atlas)
    local av = f:CreateTexture(nil, "ARTWORK")
    av:SetSize(20, 20)
    av:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    av:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")

    -- Two-line name block
    local nmTop = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nmTop:SetPoint("TOPLEFT", av, "TOPRIGHT", 6, 0)
    nmTop:SetWidth(160)
    nmTop:SetJustifyH("LEFT")

    local nmBot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nmBot:SetPoint("TOPLEFT", nmTop, "BOTTOMLEFT", 0, -1)
    nmBot:SetWidth(160)
    nmBot:SetJustifyH("LEFT")

    -- Spec dropdown
    local specDrop = CreateFrame("Frame", rowName .. "Spec", f, "UIDropDownMenuTemplate")
    specDrop:SetPoint("LEFT", nmTop, "RIGHT", 20, -2)
    ns.UI.Dropdown.style(specDrop, 120)

    -- TASKS.md §3.0 / §3.1: per-row "provides" chip holder. 0..4 labeled
    -- chips describing buffs THIS member's class can contribute. Chips are
    -- rebuilt on each row refresh in `rebuild()` based on row.classToken.
    -- UX-01 step 4: tooltip clarifies that chip highlight is the PLAN
    -- (what the comp assigned), not the live buff status on the unit.
    local chipHolder = CreateFrame("Frame", nil, f)
    chipHolder:EnableMouse(true)
    chipHolder:SetSize(160, 14)
    chipHolder:SetPoint("LEFT", specDrop, "RIGHT", 14, 0)
    chipHolder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Comp-assigned buffs", 1, 1, 1)
        GameTooltip:AddLine(
            "Gold = this member is assigned to cast the buff in the current comp. "
            .. "Muted = not assigned. Reflects planning state, not live buff status.",
            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    chipHolder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- PATCH_NOTES §12a: full "Re-Spec" label on the row button, 58x18.
    local respecBtn = ns.UI.Button.stone(f, "Re-Spec", 58, 18)
    respecBtn:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    -- Per-row subgroup control (FEATURE: live raid reorder). Stone button
    -- showing "G<n>"; click opens a dropdown with G1..G8 that fires
    -- SetRaidSubgroup on the row's raid index. Hidden in party (no
    -- subgroups exist there) and disabled when the player lacks raid
    -- leader / assistant rights.
    local groupBtn = ns.UI.Button.stone(f, "G-", 30, 18)
    groupBtn:SetPoint("RIGHT", respecBtn, "LEFT", -4, 0)
    local groupDrop = CreateFrame("Frame", rowName .. "GroupDrop", f, "UIDropDownMenuTemplate")
    groupDrop:Hide()

    return {
        frame = f, cb = cb, av = av, pBtn = pBtn,
        nmTop = nmTop, nmBot = nmBot,
        specDrop = specDrop, chipHolder = chipHolder, chips = {},
        respecBtn = respecBtn,
        groupBtn = groupBtn, groupDrop = groupDrop,
    }
end

local function populateSpecDropdown(row)
    UIDropDownMenu_Initialize(row.specDrop, function()
        local specs = ns.Data.CLASS_SPECS[row.classToken] or {}
        for _, specName in ipairs(specs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = colorClass(row.classToken, specName)
            info.value = specName
            info.func  = function(self)
                row.spec = self.value
                UIDropDownMenu_SetText(row.specDrop, colorClass(row.classToken, self.value))
                if row.guid then
                    local prev = ns.Engine.state.assignedSpecs[row.guid] or {}
                    ns.Engine.state.assignedSpecs[row.guid] = {
                        name = row.name, spec = self.value, classToken = row.classToken,
                        opt1 = prev.opt1, opt2 = prev.opt2,
                    }
                end
                local prev = ns.Engine.state.assignedSpecs[row.guid] or {}
                whisperSpec(row.name, self.value, row.classToken, prev.opt1, prev.opt2)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(row.specDrop, colorClass(row.classToken, row.spec or "-"))
end

-- ----------------------------------------------------------
-- Rebuild
-- ----------------------------------------------------------
local function rowPassesFilter(role, name)
    -- "dps" is a meta-filter: matches both melee AND ranged so users can
    -- still see all DPS in one shot without picking sub-categories.
    if filterState.role ~= "all" then
        if filterState.role == "dps" then
            if role ~= "melee" and role ~= "ranged" then return false end
        elseif filterState.role ~= role then
            return false
        end
    end
    if filterState.query ~= "" then
        if not string.find(string.lower(name or ""), filterState.query, 1, true) then
            return false
        end
    end
    return true
end

local function rebuild()
    if not frame or not frame:IsShown() then return end

    local units = iterRaidUnits()
    if ns.DebugF then
        ns.DebugF("roster", "rebuild: %d units (rows pool=%d)", #units, #rows)
    end
    while #rows < #units do rows[#rows + 1] = createRowWidget() end

    -- BUG-#1: rows pool is reused across rebuilds. When the group shrinks
    -- (leaving raid/party), the outer `for idx, unit in ipairs(units)`
    -- below only touches rows 1..#units, so rows beyond that kept their
    -- old `_visible=true` from the previous larger roster and stayed
    -- painted on screen. Reset every row's visibility + stale identifiers
    -- up front so the only rows that can end up shown are ones explicitly
    -- re-marked visible by the loop below.
    for i = 1, #rows do
        local r = rows[i]
        r._visible = false
        r._unitId  = nil
        r.name     = nil
        r.guid     = nil
    end

    local groups = { tank = {}, heal = {}, melee = {}, ranged = {} }
    for idx, unit in ipairs(units) do
        local row = rows[idx]
        row._unitId = unit
        if UnitExists(unit) and UnitIsPlayer(unit) then
            row.name         = UnitName(unit) or "?"
            row.guid         = UnitGUID(unit)
            local _, cls     = UnitClass(unit)
            row.classToken   = cls or ""

            local tracked = row.guid and ns.Engine.state.assignedSpecs[row.guid]
            if tracked and tracked.spec then
                row.spec = tracked.spec
            else
                row.spec = fallbackSpec(row.classToken)
            end
            row.role = inferRole(row.classToken, row.spec)

            row._provides = scanProvides(unit, row.classToken, row.guid)

            row._visible = rowPassesFilter(row.role, row.name)
            if row._visible then table.insert(groups[row.role], row) end
        else
            row._visible = false
        end
    end

    -- Layout with section headers
    local y = -2
    local totalCounts = { tank = 0, heal = 0, melee = 0, ranged = 0 }
    for role in pairs(groups) do totalCounts[role] = #groups[role] end

    local ROLE_ORDER = { "tank", "heal", "melee", "ranged" }
    local ROLE_TITLE = { tank = "TANKS", heal = "HEALERS",
                         melee = "MELEE DPS", ranged = "RANGED DPS" }

    for _, role in ipairs(ROLE_ORDER) do
        local list = groups[role]
        local h = headers[role]
        if not h then
            h = {}
            -- Section label (Cinzel gold uppercase)
            h.lbl = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h.lbl:SetTextColor(1, 0.82, 0)
            -- Count pill - a small framed FontString
            h.pill = CreateFrame("Frame", nil, content)
            h.pill:SetSize(28, 14)
            h.pill:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            h.pill:SetBackdropColor(0.04, 0.03, 0.02, 1)
            h.pill:SetBackdropBorderColor(0.23, 0.18, 0.13, 1)
            h.pillText = h.pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            h.pillText:SetPoint("CENTER", h.pill, "CENTER", 0, 0)
            -- PATCH_NOTES §12d: per-section empty-state placeholder shown
            -- when the section has 0 tracked members.
            h.emptyLbl = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            h.emptyLbl:SetTextColor(0.42, 0.36, 0.27, 1)
            h.emptyLbl:Hide()
            headers[role] = h
        end

        -- Render section header even when empty so users can see which
        -- groups exist and why they're empty.
        h.lbl:ClearAllPoints()
        h.lbl:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
        h.lbl:SetText(ROLE_TITLE[role])
        h.lbl:Show()
        h.pill:ClearAllPoints()
        h.pill:SetPoint("LEFT", h.lbl, "RIGHT", 8, 0)
        h.pillText:SetText(tostring(#list))
        h.pill:Show()
        y = y - HEADER_H

        if #list == 0 then
            h.emptyLbl:ClearAllPoints()
            h.emptyLbl:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 2)
            h.emptyLbl:SetText("no " .. string.lower(ROLE_TITLE[role])
                .. " tracked - whisper one via Spec tab to begin")
            h.emptyLbl:Show()
            y = y - 16 - SECTION_GAP
        else
            h.emptyLbl:Hide()

            for _, row in ipairs(list) do
                -- Name block: top line = class-colored name (+ mono "(you)")
                local suffix = UnitIsUnit(row._unitId, "player") and " |cff808080(you)|r" or ""
                row.nmTop:SetText(colorClass(row.classToken, row.name) .. suffix)
                -- Bottom line = "Class - spec" muted
                local classLabel = ns.Data.CLASS_LABEL and ns.Data.CLASS_LABEL[row.classToken] or row.classToken
                row.nmBot:SetText(string.format("%s - %s", classLabel, row.spec or "-"))

                -- Avatar (class circle)
                local tc = CLASS_ICON[row.classToken]
                if tc then row.av:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end

                populateSpecDropdown(row)

                -- TASKS.md §3.1: render per-class "provides" chips dynamically.
                -- Chips get rebuilt (hidden+repositioned) on each refresh so
                -- switching classes via the spec dropdown updates them.
                for _, chip in ipairs(row.chips) do chip:Hide() end
                local provides = row._provides or {}
                if #provides == 0 then
                    row.chipHolder:Hide()
                else
                    row.chipHolder:Show()
                    for i, p in ipairs(provides) do
                        local chip = row.chips[i]
                        if not chip then
                            chip = ns.UI.Chip.provide(row.chipHolder, p.label, p.on)
                            row.chips[i] = chip
                        else
                            -- Update existing chip's on-state + label in place.
                            if p.on then
                                chip:SetBackdropColor(0.22, 0.17, 0.08, 1)
                                chip:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)
                                chip.label:SetTextColor(1.00, 0.82, 0.00, 1)
                            else
                                chip:SetBackdropColor(0.08, 0.06, 0.04, 1)
                                chip:SetBackdropBorderColor(0.30, 0.24, 0.18, 1)
                                chip.label:SetTextColor(0.45, 0.38, 0.28, 1)
                            end
                            chip.label:SetText(p.label)
                        end
                        chip:ClearAllPoints()
                        chip:SetPoint("LEFT", row.chipHolder, "LEFT", (i - 1) * 40, 0)
                        chip:Show()
                    end
                end

                -- FEATURE-02: toggle the per-name human-player flag.
                local isFlagged = ns.Persistence and ns.Persistence.IsPlayerName
                    and ns.Persistence.IsPlayerName(row.name) or false
                row.pBtn:SetScript("OnClick", function()
                    if not row.name or row.name == "" then return end
                    local cur = ns.Persistence.IsPlayerName(row.name)
                    ns.Persistence.SetPlayerName(row.name, not cur)
                    ns.MsgInfo(string.format("%s: player flag %s",
                        row.name, cur and "OFF" or "ON"))
                    rebuild()
                end)
                local pfs = row.pBtn:GetFontString()
                if isFlagged then
                    if pfs then pfs:SetTextColor(1.00, 0.82, 0.00, 1) end
                    row.pBtn:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)
                else
                    if pfs then pfs:SetTextColor(0.45, 0.38, 0.28, 1) end
                    row.pBtn:SetBackdropBorderColor(0.23, 0.18, 0.13, 1)
                end

                -- Per-row subgroup control. In raid: show G<n> and let
                -- the user move this member to any G1..G8 via dropdown.
                -- In party: hide entirely (no subgroups exist). Without
                -- raid-leader / officer rights, SetRaidSubgroup silently
                -- fails - we still display the current group, but disable
                -- the click so it doesn't look interactive.
                local inRaid       = GetNumRaidMembers and GetNumRaidMembers() > 0
                local raidIdx      = nil
                local currentGroup = nil
                if inRaid then
                    for i = 1, GetNumRaidMembers() do
                        if UnitIsUnit("raid" .. i, row._unitId) then
                            raidIdx = i; break
                        end
                    end
                    if raidIdx then
                        local _, _, sg = GetRaidRosterInfo(raidIdx)
                        currentGroup = sg
                    end
                end

                if inRaid and raidIdx then
                    row.groupBtn:Show()
                    row.groupBtn:SetText("G" .. (currentGroup or "-"))
                    local canMove = (IsRaidLeader and IsRaidLeader() == 1)
                                 or (IsRaidOfficer and IsRaidOfficer() == 1)
                    if canMove then
                        row.groupBtn:Enable(); row.groupBtn:SetAlpha(1)
                        row.groupBtn:SetScript("OnClick", function(self)
                            UIDropDownMenu_Initialize(row.groupDrop, function()
                                for g = 1, 8 do
                                    local info = UIDropDownMenu_CreateInfo()
                                    info.text         = "Group " .. g
                                    info.notCheckable = true
                                    info.disabled     = (g == currentGroup) and 1 or nil
                                    info.func         = function()
                                        if SetRaidSubgroup then
                                            local ok, err = pcall(SetRaidSubgroup, raidIdx, g)
                                            if ok then
                                                ns.MsgInfo(string.format(
                                                    "Moved %s to G%d.", row.name or "?", g))
                                            else
                                                ns.MsgWarn("Move failed: " .. tostring(err))
                                            end
                                        end
                                        CloseDropDownMenus()
                                    end
                                    UIDropDownMenu_AddButton(info)
                                end
                            end, "MENU")
                            ToggleDropDownMenu(1, nil, row.groupDrop, self, 0, 0)
                        end)
                    else
                        row.groupBtn:Disable(); row.groupBtn:SetAlpha(0.5)
                        row.groupBtn:SetScript("OnClick", nil)
                    end
                else
                    row.groupBtn:Hide()
                end

                -- Re-spec square button
                row.respecBtn:SetScript("OnClick", function()
                    if ns.DebugF then
                        ns.DebugF("respec", "row click: %s -> %s (combat=%s)",
                            tostring(row.name), tostring(row.spec),
                            (InCombatLockdown and InCombatLockdown()) and "Y" or "N")
                    end
                    if ns.Persistence.IsPlayerName(row.name) then
                        ns.MsgWarn(row.name .. " is flagged as a human player - skipping.")
                        return
                    end
                    local prev = row.guid and ns.Engine.state.assignedSpecs[row.guid] or {}
                    whisperSpec(row.name, row.spec, row.classToken, prev.opt1, prev.opt2)
                    if row.guid then
                        ns.Engine.state.assignedSpecs[row.guid] = {
                            name = row.name, spec = row.spec, classToken = row.classToken,
                            opt1 = prev.opt1, opt2 = prev.opt2,
                        }
                    end
                end)
                -- Disable Re-Spec on the player's own row AND on anyone
                -- flagged as a human player (FEATURE-02). Dimmed alpha makes
                -- the "not applicable here" affordance visible at a glance.
                if UnitIsUnit(row._unitId, "player") or isFlagged then
                    row.respecBtn:Disable()
                    row.respecBtn:SetAlpha(0.5)
                else
                    row.respecBtn:Enable()
                    row.respecBtn:SetAlpha(1)
                end

                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT",  content, "TOPLEFT",  12, y)
                row.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y)
                row.frame:Show()
                y = y - (ROW_HEIGHT + ROW_SPACING)
            end
            y = y - SECTION_GAP
        end
    end

    for i = 1, #rows do
        if not rows[i]._visible then rows[i].frame:Hide() end
    end

    content:SetHeight(math.max(10, -y + 6))

    if frame.headerCount then
        local tot = totalCounts.tank + totalCounts.heal
                  + totalCounts.melee + totalCounts.ranged
        frame.headerCount:SetText(string.format("roster - %d raid member%s",
            tot, tot == 1 and "" or "s"))
    end

    refreshSelectedCount()
end

-- ----------------------------------------------------------
-- BuildInto
-- ----------------------------------------------------------
function ns.UI.Tabs.Roster.BuildInto(pane)
    if built then return end
    built = true
    frame = pane

    -- Subtitle-style header (matches wireframe "roster - 24 raid members")
    local count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("TOP", frame, "TOP", 0, -8)
    count:SetText("roster - 0 raid members")
    frame.headerCount = count

    -- Filter row
    local filterLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    filterLbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -26)
    filterLbl:SetText("FILTER")
    filterLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    local filterDrop = CreateFrame("Frame", "WardenRosterFilterDrop", frame, "UIDropDownMenuTemplate")
    filterDrop:SetPoint("LEFT", filterLbl, "RIGHT", -6, -2)
    ns.UI.Dropdown.style(filterDrop, 100)
    local FILTER_OPTS = {
        { key = "all",    label = "All"        },
        { key = "tank",   label = "Tanks"      },
        { key = "heal",   label = "Healers"    },
        { key = "dps",    label = "DPS (all)"  },
        { key = "melee",  label = "Melee DPS"  },
        { key = "ranged", label = "Ranged DPS" },
    }
    UIDropDownMenu_Initialize(filterDrop, function()
        for _, o in ipairs(FILTER_OPTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = o.label, o.key
            info.func = function()
                filterState.role = o.key
                UIDropDownMenu_SetText(filterDrop, o.label)
                rebuild()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(filterDrop, "All")

    local searchBox = CreateFrame("EditBox", "WardenRosterSearch", frame, "InputBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("LEFT", filterDrop, "RIGHT", -4, 2)
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetScript("OnTextChanged", function(self)
        filterState.query = string.lower(self:GetText() or "")
        rebuild()
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local refreshBtn = ns.UI.Button.stone(frame, "Refresh", 70, 22)
    refreshBtn:SetPoint("LEFT", searchBox, "RIGHT", 8, -2)
    refreshBtn:SetScript("OnClick", rebuild)

    -- Scroll area
    scroll = CreateFrame("ScrollFrame", "WardenRosterScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     frame, "TOPLEFT",     12, -54)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 48)

    content = CreateFrame("Frame", "WardenRosterContent", scroll)
    content:SetSize(680, 10)
    scroll:SetScrollChild(content)

    -- Bottom action bar (PATCH_NOTES §12b: dropped the leading "R " prefix).
    local respecAllBtn = ns.UI.Button.stone(frame, "Re-Spec All Tracked", 150, 22)
    respecAllBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 14)
    respecAllBtn:SetScript("OnClick", function()
        if ns.Debug then ns.Debug("respec", "Re-Spec All Tracked clicked") end
        -- FEATURE-02: skip rows flagged as human players.
        local n, skipped = 0, 0
        for _, r in ipairs(rows) do
            if r.frame:IsShown() and r.name and r.spec and r.guid
               and not UnitIsUnit("player", r.name) then
                if ns.Persistence.IsPlayerName(r.name) then
                    skipped = skipped + 1
                else
                    local prev = ns.Engine.state.assignedSpecs[r.guid] or {}
                    whisperSpec(r.name, r.spec, r.classToken, prev.opt1, prev.opt2)
                    n = n + 1
                end
            end
        end
        ns.MsgInfo(string.format("Roster: re-whispered %d members%s.",
            n, skipped > 0 and (" (" .. skipped .. " skipped - flagged as player)") or ""))
    end)

    local respecSelBtn = ns.UI.Button.stone(frame, "Re-Spec Selected", 140, 22)
    respecSelBtn:SetPoint("LEFT", respecAllBtn, "RIGHT", 8, 0)
    respecSelBtn:SetScript("OnClick", function()
        if ns.Debug then ns.Debug("respec", "Re-Spec Selected clicked") end
        local n, skipped = 0, 0
        for _, r in ipairs(rows) do
            if r.frame:IsShown() and r.cb:GetChecked() and r.name and r.spec
               and r.guid and not UnitIsUnit("player", r.name) then
                if ns.Persistence.IsPlayerName(r.name) then
                    skipped = skipped + 1
                else
                    local prev = ns.Engine.state.assignedSpecs[r.guid] or {}
                    whisperSpec(r.name, r.spec, r.classToken, prev.opt1, prev.opt2)
                    n = n + 1
                end
            end
        end
        ns.MsgInfo(string.format("Roster: re-whispered %d selected%s.",
            n, skipped > 0 and (" (" .. skipped .. " skipped - flagged as player)") or ""))
    end)

    -- "N selected" counter, right-aligned mono (matches wireframe)
    local selLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    selLbl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 20)
    selLbl:SetText("0 selected")
    frame.selCountLbl = selLbl

    -- Throttled aura-change refresh (UNIT_AURA fires very often)
    local dirty = false
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_AURA")
    frame:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_AURA" then
            if unit and (string.find(unit, "^raid") or string.find(unit, "^party") or unit == "player") then
                dirty = true
            end
        else
            rebuild(); dirty = false
        end
    end)

    frame._auraAccum = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not dirty then return end
        self._auraAccum = (self._auraAccum or 0) + elapsed
        if self._auraAccum < 0.5 then return end
        self._auraAccum = 0
        dirty = false
        rebuild()
    end)

    frame:SetScript("OnShow", rebuild)
end

function ns.UI.Tabs.Roster.OnShow(pane)
    if not built then return end
    rebuild()
end

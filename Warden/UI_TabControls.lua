-- =====================================================
-- Warden - UI_TabControls.lua
-- Direction I rebuild, faithful to wireframes.html V1:
--   Movement   - 3x2 grid, top row LG (Summon primary-red, Follow, Stay),
--                bottom row normal (Free, Release, Drink)
--   Strategy   - 3 inline groups (aoe / burn cd / face), XS button pairs
--   Marks & formation - single panel single row: Skull - Moon - disperse  -
--                       form  - set - check
--   Role commands - 5x4 matrix with glyphs (Atk Stay -> Flee), shift-click flashes
--   Danger zone - red header, Smart ReSpec / Reset AI / Hard ReSpec (warn) /
--                 Cleanup (warn) in one row
--   Summon by class - bottom panel, 2x5 grid of class-colored buttons; each
--                spawns one bot of that class via `.warstormbot bot addclass`
-- =====================================================

local _, ns = ...
ns.UI.Tabs          = ns.UI.Tabs          or {}
ns.UI.Tabs.Controls = ns.UI.Tabs.Controls or {}

-- ----------------------------------------------------------
-- Data
-- ----------------------------------------------------------
local ROLES        = { "tank", "heal", "dps", "melee", "ranged" }
local ROLE_LABELS  = { tank = "Tank", heal = "Healer", dps = "DPS", melee = "Melee", ranged = "Ranged" }
local ROLE_ACTIONS = { "attack", "stay", "follow", "flee" }
local ACTION_LABEL = { attack = "Attack", stay = "Stay", follow = "Follow", flee = "Flee" }
-- Wireframe V1 had Unicode glyphs (Atk Stay -> Flee) but the default 3.3.5 FrizQT
-- font renders them as "?" boxes. Use ASCII labels instead.
local ACTION_GLYPH = { attack = "Atk", stay = "Stay", follow = "Fol", flee = "Flee" }

local FORMATIONS      = { "shield", "chaos", "circle", "line", "melee", "near", "queue", "arrow" }
local FORMATION_LABEL = {
    shield = "Shield", chaos = "Chaos", circle = "Circle", line = "Line",
    melee  = "Melee",  near  = "Near",  queue  = "Queue",  arrow = "Arrow",
}

local SMART_SPECS = {
    WARRIOR     = { "prot", "arms", "fury" },
    PALADIN     = { "prot", "holy", "ret" },
    HUNTER      = { "bm", "mm", "surv" },
    ROGUE       = { "as", "combat", "subtlety" },
    PRIEST      = { "holy", "disc", "shadow" },
    SHAMAN      = { "resto", "ele", "enh" },
    MAGE        = { "arcane", "fire", "frost" },
    WARLOCK     = { "affli", "demo", "destro" },
    DRUID       = { "bear", "cat", "resto", "balance" },
    DEATHKNIGHT = { "blood", "frost", "unholy" },
}

-- Disperse preset distances (wireframe shows 10y default)
local DISPERSE_VALUES = { 5, 7, 10, 15, 20 }

-- ----------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------
local function send(msg, channel)
    local chan = channel or ns.Channel()
    if ns.DebugF then ns.DebugF("controls", "send %q -> %s", tostring(msg), tostring(chan)) end
    SendChatMessage(msg, chan)
end

local addTooltip = ns.UI.Tooltip.Attach

-- "kbd"-style hint tag: small gold-bordered label inside a panel header
local function addKbdHint(panel, text)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -4)
    fs:SetText(text)
    fs:SetTextColor(0.72, 0.58, 0.21, 1)
    return fs
end

-- Panel header right-side meta text (small, muted mono)
local function addPanelMeta(panel, text)
    local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -4)
    fs:SetText(text)
    fs:SetTextColor(0.61, 0.55, 0.40)
    return fs
end

-- ----------------------------------------------------------
-- BuildInto
-- ----------------------------------------------------------
function ns.UI.Tabs.Controls.BuildInto(pane)
    local paneW, paneH = pane:GetWidth(), pane:GetHeight()

    -- Column layout: single column stack of full-width panels (matches V1).
    -- Panel heights tuned so everything fits in the 526-tall pane.
    --   Movement   82   (3x2 grid, top row .lg 30px, bottom row 22px)
    --   Strategy   66   (1 row of label + 2 xs buttons x 3 groups)
    --   Marks      54   (1 row of 6 controls - shrunk to make room)
    --   Role       170  (header row + 5 role rows, square glyph cells)
    --   Danger     54   (1 row of 4 buttons  - shrunk to make room)
    --   ClassSum   66   (2x5 class buttons, bottom panel per user request)
    --   5 gaps of 6 = 30, initial offset 4
    -- Total: 82+66+54+170+54+66 + 30 + 4 = 526 ≤ 526 - fits exactly.
    local pw     = paneW - 16
    local y      = -4
    local gap    = 6
    local function nextY(h) local old = y; y = y - h - gap; return old end

    -- ============================================================
    -- Movement
    -- ============================================================
    local moveH = 82
    local moveP = ns.UI.Panel.Create(pane, pw, moveH, "Movement")
    moveP:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, nextY(moveH))

    -- 3 columns x 2 rows. Each cell spans (pw - 16) / 3 wide.
    local cellW = math.floor((pw - 20 - 2 * 6) / 3)
    local topH, botH = 30, 22
    local rowY1 = -4
    local rowY2 = rowY1 - topH - 5
    local MOVE_TOP = {
        { "Summon",  "summon",  "Summon all bots to you.",      primary = true },
        { "Follow",  "follow",  "All bots follow you." },
        { "Stay",    "stay",    "All bots hold position." },
    }
    local MOVE_BOT = {
        { "Free",    "free",    "Release from strict follow." },
        { "Release", "release", "Free bots from current target." },
        { "Drink",   "drink",   "All bots drink to restore mana." },
    }
    for i, c in ipairs(MOVE_TOP) do
        local b = c.primary
            and ns.UI.Button.red(moveP.content,   c[1], cellW, topH)
            or  ns.UI.Button.stone(moveP.content, c[1], cellW, topH)
        b:SetPoint("TOPLEFT", moveP.content, "TOPLEFT",
            4 + (i - 1) * (cellW + 6), rowY1)
        b:SetScript("OnClick", function() send(c[2]) end)
        addTooltip(b, c[1], c[3])
    end
    for i, c in ipairs(MOVE_BOT) do
        local b = ns.UI.Button.stone(moveP.content, c[1], cellW, botH)
        b:SetPoint("TOPLEFT", moveP.content, "TOPLEFT",
            4 + (i - 1) * (cellW + 6), rowY2)
        b:SetScript("OnClick", function() send(c[2]) end)
        addTooltip(b, c[1], c[3])
    end

    -- ============================================================
    -- Strategy
    -- ============================================================
    local stratH = 66
    local stratP = ns.UI.Panel.Create(pane, pw, stratH, "Strategy")
    stratP:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, nextY(stratH))
    addPanelMeta(stratP, "co commands")

    -- Three inline groups. Each group = small uppercase label + 2 .xs buttons.
    local groups = {
        { label = "aoe",     on = { "ON",    "co +aoe,-assist,-focus,?" }, off = { "off",       "co -aoe,+assist,+focus,?" } },
        { label = "burn cd", on = { "burn",  "co +boost,?" },              off = { "stop",      "co -boost,?" }               },
        { label = "face",    on = { "behind","co +behind,?" },             off = { "no flank",  "co -behind,?" }              },
    }
    local groupW = math.floor((pw - 20) / 3)
    for i, g in ipairs(groups) do
        local x = 4 + (i - 1) * groupW
        local lbl = stratP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("TOPLEFT", stratP.content, "TOPLEFT", x, -2)
        lbl:SetText(string.upper(g.label))
        lbl:SetTextColor(0.72, 0.58, 0.21, 1)

        local onBtn  = ns.UI.Button.stone(stratP.content, g.on[1],  64, 20)
        onBtn:SetPoint("TOPLEFT", stratP.content, "TOPLEFT", x, -18)
        onBtn:SetScript("OnClick", function() send(g.on[2]); ns.MsgInfo(g.on[2]) end)

        local offBtn = ns.UI.Button.stone(stratP.content, g.off[1], 64, 20)
        offBtn:SetPoint("TOPLEFT", stratP.content, "TOPLEFT", x + 68, -18)
        offBtn:SetScript("OnClick", function() send(g.off[2]); ns.MsgInfo(g.off[2]) end)
    end

    -- ============================================================
    -- Marks & formation (PATCH_NOTES §6: BL toggle lives in the master
    -- footer now, not here). Tightened to 54 to make room for the
    -- new Summon-by-class panel above.
    -- ============================================================
    local marksH = 54
    local marksP = ns.UI.Panel.Create(pane, pw, marksH, "Marks & formation")
    marksP:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, nextY(marksH))

    -- Skull button with raid-target icon (atlas index 8 = skull)
    local skullBtn = ns.UI.Button.stone(marksP.content, "Skull (attack)", 120, 22)
    skullBtn:SetPoint("TOPLEFT", marksP.content, "TOPLEFT", 4, -6)
    skullBtn:SetScript("OnClick", function()
        send("rti skull"); send("attack rti target")
        ns.MsgInfo("Skull RTI + attack.")
    end)
    local skullTex = marksP.content:CreateTexture(nil, "OVERLAY")
    skullTex:SetSize(14, 14)
    skullTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    skullTex:SetTexCoord(0.75, 1, 0.25, 0.5) -- skull
    skullTex:SetPoint("LEFT", skullBtn, "LEFT", 4, 0)

    local moonBtn = ns.UI.Button.stone(marksP.content, "Moon (CC)", 120, 22)
    moonBtn:SetPoint("LEFT", skullBtn, "RIGHT", 6, 0)
    moonBtn:SetScript("OnClick", function()
        send("rti cc moon"); ns.MsgInfo("Moon CC.")
    end)
    local moonTex = marksP.content:CreateTexture(nil, "OVERLAY")
    moonTex:SetSize(14, 14)
    moonTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    moonTex:SetTexCoord(0, 0.25, 0.25, 0.5) -- moon
    moonTex:SetPoint("LEFT", moonBtn, "LEFT", 4, 0)

    -- Disperse dropdown
    local dispLbl = marksP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dispLbl:SetPoint("LEFT", moonBtn, "RIGHT", 16, 0)
    dispLbl:SetText("DISPERSE")
    dispLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    local dispDrop = CreateFrame("Frame", "WardenDisperseDrop", marksP.content, "UIDropDownMenuTemplate")
    dispDrop:SetPoint("LEFT", dispLbl, "RIGHT", -6, -2)
    ns.UI.Dropdown.style(dispDrop, 80)
    local function refreshDispText()
        local d = (ns.Persistence.DB and tonumber(ns.Persistence.DB.disperseDist)) or 10
        UIDropDownMenu_SetText(dispDrop, d .. "y")
    end
    UIDropDownMenu_Initialize(dispDrop, function()
        do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable = "disable", 1
            info.func = function()
                send("disperse disable"); ns.MsgWarn("Disperse disabled.")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info)
        end
        for _, v in ipairs(DISPERSE_VALUES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = v .. "y", v
            info.func = function(self)
                if ns.Persistence.DB then ns.Persistence.DB.disperseDist = self.value end
                send("disperse set " .. self.value)
                ns.MsgInfo(string.format("Disperse %dy.", self.value))
                refreshDispText()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    refreshDispText()

    -- Formation dropdown + Set + Check
    local formLbl = marksP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    formLbl:SetPoint("LEFT", dispDrop, "RIGHT", 2, 2)
    formLbl:SetText("FORM")
    formLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    local formState = { cur = "shield" }
    local formDrop = CreateFrame("Frame", "WardenFormDrop", marksP.content, "UIDropDownMenuTemplate")
    formDrop:SetPoint("LEFT", formLbl, "RIGHT", -6, -2)
    ns.UI.Dropdown.style(formDrop, 95)
    UIDropDownMenu_Initialize(formDrop, function()
        for _, f in ipairs(FORMATIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = FORMATION_LABEL[f] or f, f
            info.func = function(self)
                formState.cur = self.value
                UIDropDownMenu_SetText(formDrop, FORMATION_LABEL[self.value] or self.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(formDrop, FORMATION_LABEL[formState.cur])

    local setBtn = ns.UI.Button.stone(marksP.content, "set", 40, 20)
    setBtn:SetPoint("LEFT", formDrop, "RIGHT", -2, 2)
    setBtn:SetScript("OnClick", function()
        send("formation " .. formState.cur)
        ns.MsgInfo("Formation: " .. (FORMATION_LABEL[formState.cur] or formState.cur))
    end)
    -- Match "set" width so the two buttons read as a pair; the label still
    -- fits at 44px (GameFontNormalSmall renders "check" in ~32px).
    local chkBtn = ns.UI.Button.stone(marksP.content, "check", 44, 20)
    chkBtn:SetPoint("LEFT", setBtn, "RIGHT", 4, 0)
    chkBtn:SetScript("OnClick", function() send("formation") end)

    -- BL toggle moved to master footer per PATCH_NOTES §6 (global state
    -- belongs in the persistent status bar, not tucked into Marks &
    -- formation where it overlapped the "check" button).

    -- ============================================================
    -- Role commands - 5x4 matrix with glyphs
    -- ============================================================
    local roleH = 170
    local roleP = ns.UI.Panel.Create(pane, pw, roleH, "Role commands")
    roleP:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, nextY(roleH))
    addPanelMeta(roleP, "5 x 4 matrix - shift-click to flash")

    -- Matrix layout: 64px label + 4 equal-width glyph cells
    local labelW   = 64
    local rowContentW = pw - 16 - labelW - 8
    local cellGap  = 3
    local mCellW   = math.floor((rowContentW - 3 * cellGap) / 4)
    local mCellH   = 22
    local headerY  = -2

    -- Column headers
    for ai, act in ipairs(ROLE_ACTIONS) do
        local fs = roleP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", roleP.content, "TOPLEFT",
            labelW + 8 + (ai - 1) * (mCellW + cellGap) + mCellW / 2 - 12, headerY)
        fs:SetText(ACTION_LABEL[act])
        fs:SetTextColor(0.72, 0.58, 0.21, 1)
    end

    -- TASKS.md §1.1: Atk only red. Stay/Fol/Flee stone with colored labels.
    local ACTION_TEXT_COLOR = {
        stay   = { 1.00, 0.72, 0.12 }, -- amber
        follow = { 1.00, 0.82, 0.00 }, -- gold
        flee   = { 0.88, 0.29, 0.23 }, -- ink-red
    }

    for ri, role in ipairs(ROLES) do
        local rowY  = -18 - (ri - 1) * (mCellH + 4)
        local lbl   = roleP.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", roleP.content, "TOPLEFT", 4, rowY - 2)
        lbl:SetText(ROLE_LABELS[role])

        for ai, action in ipairs(ROLE_ACTIONS) do
            local x   = labelW + 8 + (ai - 1) * (mCellW + cellGap)
            local cmd = "@" .. role .. " " .. action
            local b
            if action == "attack" then
                b = ns.UI.Button.red(roleP.content, ACTION_GLYPH[action] or "?",
                                      mCellW, mCellH)
            else
                b = ns.UI.Button.stone(roleP.content, ACTION_GLYPH[action] or "?",
                                        mCellW, mCellH)
                local c = ACTION_TEXT_COLOR[action]
                local fs = b:GetFontString()
                if fs and c then fs:SetTextColor(c[1], c[2], c[3]) end
            end
            b:SetPoint("TOPLEFT", roleP.content, "TOPLEFT", x, rowY)
            b:RegisterForClicks("LeftButtonUp")
            b:SetScript("OnClick", function() send(cmd) end)
            addTooltip(b, ACTION_LABEL[action] .. " " .. ROLE_LABELS[role],
                "Sends `" .. cmd .. "` to " .. ns.Channel() .. ".")
        end
    end

    -- ============================================================
    -- Danger zone (red header)
    -- ============================================================
    local dangerH = 54
    local dangerP = ns.UI.Panel.Create(pane, pw, dangerH, "Danger zone")
    dangerP:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, nextY(dangerH))
    if dangerP.header then dangerP.header:SetTextColor(0.88, 0.29, 0.23) end
    addPanelMeta(dangerP, "StaticPopup confirm")

    local smartDrop = CreateFrame("Frame", "WardenSmartRespecDrop", dangerP.content, "UIDropDownMenuTemplate")
    smartDrop:Hide()

    local dangerW = math.floor((pw - 20 - 3 * 6) / 4)
    local dangerY = -6

    -- TASKS.md §1.3: Smart ReSpec stays stone (safe, calm look). Bump label
    -- weight via GameFontNormal so it doesn't disappear next to the red and
    -- warn siblings.
    local smartBtn = ns.UI.Button.stone(dangerP.content, "Smart ReSpec", dangerW, 22)
    if smartBtn:GetFontString() then
        smartBtn:GetFontString():SetFontObject("GameFontNormal")
    end
    smartBtn:SetPoint("TOPLEFT", dangerP.content, "TOPLEFT", 4, dangerY)
    smartBtn:SetScript("OnClick", function(self)
        -- Target OR mouseover a bot (shared resolver from UI_TabSpec) so you
        -- don't have to hard-target the unit you want to re-spec.
        local unit, targetName, classTok = ns.ResolveBotUnit and ns.ResolveBotUnit()
        if not unit then
            ns.MsgErr("Target or mouseover a bot first.")
            return
        end
        local targetGUID = UnitGUID(unit)
        local specs      = SMART_SPECS[classTok or ""]
        if not specs then
            ns.MsgWarn("No specs defined for class " .. tostring(classTok) .. ".")
            return
        end
        UIDropDownMenu_Initialize(smartDrop, function()
            local h = UIDropDownMenu_CreateInfo()
            h.isTitle, h.notCheckable = true, true
            h.text = ns.ColorClass(classTok, targetName)
            UIDropDownMenu_AddButton(h)
            for _, s in ipairs(specs) do
                local e = UIDropDownMenu_CreateInfo()
                e.text, e.notCheckable = s:sub(1, 1):upper() .. s:sub(2) .. " (PvE)", true
                e.func = function()
                    SendChatMessage("talents spec " .. s .. " pve", "WHISPER", nil, targetName)
                    ns.MsgInfo(string.format("Sent `talents spec %s pve` to %s.", s, targetName))
                    if ns.Engine and ns.Engine.state and targetGUID then
                        ns.Engine.state.assignedSpecs[targetGUID] = {
                            name = targetName, spec = s, classToken = classTok,
                        }
                    end
                end
                UIDropDownMenu_AddButton(e)
            end
        end, "MENU")
        ToggleDropDownMenu(1, nil, smartDrop, self, 0, 0)
    end)

    -- TASKS.md §1.3 overrides PATCH_NOTES §7: Reset AI = red, not warn.
    local resetAIBtn = ns.UI.Button.red(dangerP.content, "Reset AI", dangerW, 22)
    resetAIBtn:SetPoint("TOPLEFT", dangerP.content, "TOPLEFT", 4 + dangerW + 6, dangerY)
    resetAIBtn:SetScript("OnClick", function()
        send("reset botAI"); ns.MsgWarn("Sent `reset botAI`.")
    end)

    local hardBtn = ns.UI.Button.warn(dangerP.content, "Hard ReSpec", dangerW, 22, "WARDEN_CONFIRM_HARD_RESPEC")
    hardBtn:SetPoint("TOPLEFT", dangerP.content, "TOPLEFT", 4 + 2 * (dangerW + 6), dangerY)

    local cleanupBtn = ns.UI.Button.warn(dangerP.content, "Cleanup", dangerW, 22, "WARDEN_CONFIRM_CLEANUP")
    cleanupBtn:SetPoint("TOPLEFT", dangerP.content, "TOPLEFT", 4 + 3 * (dangerW + 6), dangerY)

    -- ============================================================
    -- Summon by class - bottom panel. 2x5 grid of class-colored buttons.
    -- Each click sends `.warstormbot bot addclass <class>` via the bot
    -- command channel (SAY by default), mirroring how the Comp Build
    -- pipeline spawns individual bots. Kept intentionally simple: no
    -- queue, no spec whisper - just one bot per click.
    -- Visual: stone button + class-colored 10px swatch on the left +
    -- class-colored label (matches the chip tray aesthetic).
    -- ============================================================
    local classH = 66
    local classP = ns.UI.Panel.Create(pane, pw, classH, "Summon by class")
    classP:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, nextY(classH))
    addPanelMeta(classP, "adds one bot per click")

    local CLASS_ROWS = {
        { "WARRIOR", "PALADIN", "HUNTER",  "ROGUE", "PRIEST"      },
        { "SHAMAN",  "MAGE",    "WARLOCK", "DRUID", "DEATHKNIGHT" },
    }
    local cCellGap = 4
    local cCellW   = math.floor((pw - 20 - 4 * cCellGap) / 5)
    local cCellH   = 18
    local cRowGap  = 4

    local function sendAddClass(cmdToken, label)
        local db   = ns.Persistence and ns.Persistence.DB
        local chan = (db and db.commandChannel) or "SAY"
        SendChatMessage(".warstormbot bot addclass " .. cmdToken, chan)
        ns.MsgInfo("Summoned 1 " .. label .. " (" .. chan .. ").")
    end

    for ri, row in ipairs(CLASS_ROWS) do
        local rowY = -2 - (ri - 1) * (cCellH + cRowGap)
        for ci, classToken in ipairs(row) do
            local label   = ns.Data.CLASS_LABEL[classToken] or classToken
            local cmdTok  = ns.Data.CLASS_CMD[classToken]   or string.lower(classToken)
            local b       = ns.UI.Button.stone(classP.content, label, cCellW, cCellH)
            b:SetPoint("TOPLEFT", classP.content, "TOPLEFT",
                4 + (ci - 1) * (cCellW + cCellGap), rowY)

            -- Class-colored swatch on the left of the button.
            local sw = b:CreateTexture(nil, "OVERLAY")
            sw:SetTexture("Interface\\Buttons\\WHITE8x8")
            sw:SetSize(10, 10)
            sw:SetPoint("LEFT", b, "LEFT", 6, 0)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
            if cc then
                sw:SetVertexColor(cc.r or 1, cc.g or 1, cc.b or 1, 1)
            end

            -- Nudge label right so it clears the swatch, and tint to class color.
            local fs = b:GetFontString()
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", sw, "RIGHT", 4, 0)
                fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
                fs:SetJustifyH("LEFT")
                if cc then fs:SetTextColor(cc.r or 1, cc.g or 1, cc.b or 1) end
            end

            b:SetScript("OnClick", function() sendAddClass(cmdTok, label) end)
            addTooltip(b, "Summon " .. label,
                "Sends `.warstormbot bot addclass " .. cmdTok ..
                "` to spawn one " .. label .. " bot.")
        end
    end
end

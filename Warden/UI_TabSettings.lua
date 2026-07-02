-- =====================================================
-- Warden - UI_TabSettings.lua
-- Panels for Global settings (scale slider) / Session stats / Maintenance /
-- About. UI-03: Density toggle removed - layout is locked to Roomy values.
-- Exposes ns.UI.Tabs.Settings.BuildInto(pane).
-- =====================================================

local _, ns = ...
ns.UI.Tabs          = ns.UI.Tabs          or {}
ns.UI.Tabs.Settings = ns.UI.Tabs.Settings or {}

local built = false

function ns.UI.Tabs.Settings.BuildInto(pane)
    -- Idempotency guard: a 2nd call would recreate every ScrollFrame/panel/
    -- checkbox (clobbering named globals) and stack a duplicate OnUpdate.
    if built then return end

    local db = ns.Persistence.DB
    if not db then return end
    built = true  -- only latch once we've committed to building (db present)

    local paneW, paneH = pane:GetWidth(), pane:GetHeight()

    -- Total panel heights exceed pane so we host everything inside a
    -- ScrollFrame. Bottom offset 32 clears the master footer so the
    -- scrollbar track doesn't graze "BL ON / Esc close".
    local scroll = CreateFrame("ScrollFrame", "WardenSettingsScroll", pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     pane, "TOPLEFT",      0,  -4)
    scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -24, 32)

    -- Thin scrollbar treatment matching Help tab (§6.9 there).
    local sb = _G["WardenSettingsScrollScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT",    scroll, "TOPRIGHT", 2, 0)
        sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
        sb:SetWidth(8)
    end

    local content = CreateFrame("Frame", "WardenSettingsContent", scroll)
    local contentW = paneW - 32
    content:SetSize(contentW, 10)
    scroll:SetScrollChild(content)

    -- ============================================================
    -- Panel 1 - Global settings
    -- ============================================================
    local globalP = ns.UI.Panel.Create(content, contentW - 16, 130, "Global settings")
    globalP:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -4)

    -- Thin adapter over ns.UI.Check.Make so existing call-sites keep the
    -- same (parent, label, x, y, dbKey, tip) shape.
    local function mkCheck(parent, label, x, y, dbKey, tip)
        local cb = ns.UI.Check.Make(parent, "WardenSetting_" .. dbKey,
            label, db, dbKey, { tip = tip })
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return cb
    end

    mkCheck(globalP.content, "Auto-spec newly joined bots", 4, -2, "autoSpec",
        "When a bot joins during a Build, Warden whispers them their planned spec automatically.")
    mkCheck(globalP.content, "Auto-match group type to comp size", 4, -28, "autoRaidDuringBuild",
        "Build-time group adjustment. If the comp needs more than 5 members, party is promoted to raid. If the comp fits in 5 and you're already in a raid with <=5 members, the raid is collapsed back to party. Requires leader rights and is skipped in combat. Run Cleanup first if a stale >5 raid is blocking the party collapse.")

    -- Window size dropdown (replaces the mousewheel zoom). Four presets
    -- map to the masterScale values that used to live on the slider.
    local SIZE_PRESETS = {
        { label = "Small",  scale = 0.80 },
        { label = "Medium", scale = 1.00 },
        { label = "Large",  scale = 1.20 },
        { label = "XL",     scale = 1.40 },
    }
    local function labelForScale(s)
        local closest, best = SIZE_PRESETS[2].label, math.huge
        for _, p in ipairs(SIZE_PRESETS) do
            local d = math.abs((tonumber(s) or 1.0) - p.scale)
            if d < best then best, closest = d, p.label end
        end
        return closest
    end

    local sizeLbl = globalP.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLbl:SetPoint("TOPLEFT", globalP.content, "TOPLEFT", 4, -56)
    sizeLbl:SetText("Window size")

    local sizeDrop = CreateFrame("Frame", "WardenSizeDrop", globalP.content, "UIDropDownMenuTemplate")
    sizeDrop:SetPoint("TOPLEFT", sizeLbl, "BOTTOMLEFT", -16, -4)
    ns.UI.Dropdown.style(sizeDrop, 120)
    UIDropDownMenu_Initialize(sizeDrop, function()
        for _, p in ipairs(SIZE_PRESETS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = p.label, p.scale
            info.func = function(self)
                db.masterScale = self.value
                UIDropDownMenu_SetText(sizeDrop, p.label)
                if ns.UI.Master and ns.UI.Master.Frame() then
                    ns.UI.Master.Frame():SetScale(self.value)
                end
                ns.MsgInfo(string.format("Window size: %s (%.2f).", p.label, self.value))
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(sizeDrop, labelForScale(db.masterScale))

    -- ============================================================
    -- Panel 1b - Bot whisper filter. Master opt-in + one checkbox per bot
    -- line so the user picks exactly which get hidden. Off by default. Only
    -- whispers from senders OUTSIDE your group are hidden for the invite
    -- lines; the "own bot" lines (Equipping / Staying) are hidden regardless.
    -- ============================================================
    db.whisperFilters = db.whisperFilters or {}
    if ns.WhisperBlocker and ns.WhisperBlocker.SeedDefaults then
        ns.WhisperBlocker.SeedDefaults()
    end

    local whisperP = ns.UI.Panel.Create(content, contentW - 16, 236, "Bot whisper filter")
    whisperP:SetPoint("TOPLEFT", globalP, "BOTTOMLEFT", 0, -6)

    -- Everything below the master switch (warning note, "LINES TO HIDE"
    -- label, and the per-line checkboxes) is only meaningful once the filter
    -- is on, so it is shown/hidden as a block by syncWhisperLines().
    local whisperKids = {}
    local function syncWhisperLines()
        local on = db.whisperFilter == true
        for _, w in ipairs(whisperKids) do
            if on then w:Show() else w:Hide() end
        end
    end

    ns.UI.Check.Make(whisperP.content, "WardenSetting_whisperFilter",
        "Block bot noise whispers", db, "whisperFilter",
        { tip = "Master switch. Hides the whispers WarStorm playerbots spam - walk-by \"invite me\" lines and your own bots' \"Equipping\"/\"Staying\" acks. Real players are never touched; a bot must be a bot, and the invite lines only apply to senders outside your group.",
          onToggle = syncWhisperLines })
        :SetPoint("TOPLEFT", whisperP.content, "TOPLEFT", 4, -2)

    local whispWarn = whisperP.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whispWarn:SetPoint("TOPLEFT", whisperP.content, "TOPLEFT",  6, -26)
    whispWarn:SetPoint("RIGHT",   whisperP.content, "RIGHT",   -6,   0)
    whispWarn:SetJustifyH("LEFT")
    whispWarn:SetWordWrap(true)
    whispWarn:SetText("|cffffaa00Note:|r a real player could in theory whisper one of these exact lines. Untick any line below to keep it visible. Party/raid members are never affected by the invite lines.")
    whispWarn:SetTextColor(0.85, 0.72, 0.4, 1)
    table.insert(whisperKids, whispWarn)

    local linesLbl = whisperP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    linesLbl:SetPoint("TOPLEFT", whisperP.content, "TOPLEFT", 4, -64)
    linesLbl:SetText("LINES TO HIDE")
    linesLbl:SetTextColor(0.72, 0.58, 0.21, 1)
    table.insert(whisperKids, linesLbl)

    local wy = -82
    for _, p in ipairs(ns.WhisperBlocker and ns.WhisperBlocker.PATTERNS or {}) do
        local cb = ns.UI.Check.Make(whisperP.content, "WardenSetting_wf_" .. p.key,
            p.label, db.whisperFilters, p.key, { echo = false })
        cb:SetPoint("TOPLEFT", whisperP.content, "TOPLEFT", 8, wy)
        table.insert(whisperKids, cb)
        wy = wy - 22
    end

    syncWhisperLines()  -- apply initial visibility from the saved setting

    -- ============================================================
    -- Panel 2 - Session stats (PATCH_NOTES §13a: 3-col grid instead of a
    -- single cluttered line).
    -- ============================================================
    local statsP = ns.UI.Panel.Create(content, contentW - 16, 70, "Session stats")
    statsP:SetPoint("TOPLEFT", whisperP, "BOTTOMLEFT", 0, -6)

    local STAT_DEFS = {
        { "Spawned",       "spawned" },
        { "Spec'd",        "specd"   },
        { "Pending",       "pending" },
        { "Tracked GUIDs", "tracked" },
        { "Send queue",    "sendQ"   },
        { "Whisper queue", "whispQ"  },
    }
    local statFS = {}
    for i, def in ipairs(STAT_DEFS) do
        local col = ((i - 1) % 3)
        local row = math.floor((i - 1) / 3)
        local fs = statsP.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", statsP.content, "TOPLEFT",
            4 + col * 170, -4 - row * 18)
        statFS[def[2]] = { fs = fs, label = def[1] }
    end

    local function refreshStats()
        local s = ns.Engine and ns.Engine.state
        if not s then return end
        local pending = 0
        for _, q in pairs(s.specQueue or {}) do pending = pending + #q end
        local tracked = 0
        for _ in pairs(s.assignedSpecs or {}) do tracked = tracked + 1 end
        local vals = {
            spawned = s.counters and s.counters.spawned or 0,
            specd   = s.counters and s.counters.specd   or 0,
            pending = pending,
            tracked = tracked,
            sendQ   = #(s.sendQueue    or {}),
            whispQ  = #(s.whisperQueue or {}),
        }
        for k, entry in pairs(statFS) do
            entry.fs:SetText(entry.label .. ": |cffffd100" .. (vals[k] or 0) .. "|r")
        end
    end

    pane._statsAccum = 0
    pane:SetScript("OnUpdate", function(self, elapsed)
        -- Skip polling while the Settings tab is hidden (self is the pane).
        if not self:IsVisible() then return end   -- skip while tab/window is hidden
        self._statsAccum = (self._statsAccum or 0) + elapsed
        if self._statsAccum < 0.5 then return end
        self._statsAccum = 0
        refreshStats()
    end)
    refreshStats()

    -- ============================================================
    -- Panel 2b - WardenSword (mid-fight HUD). Brief §7.
    -- ============================================================
    local sw = db.sword or {}
    db.sword = sw

    local swordP = ns.UI.Panel.Create(content, contentW - 16, 180, "WardenSword")
    swordP:SetPoint("TOPLEFT", statsP, "BOTTOMLEFT", 0, -6)

    -- Same thin adapter on ns.UI.Check.Make, driving the sword sub-table.
    local function mkSwordCheck(label, x, y, key, hook, tip)
        local opts = { tip = tip, echo = false }
        if hook and hook ~= "nil" and ns.WardenSword and ns.WardenSword[hook] then
            opts.onToggle = function() ns.WardenSword[hook]() end
        end
        local cb = ns.UI.Check.Make(swordP.content,
            "WardenSwordSetting_" .. key, label, sw, key, opts)
        cb:SetPoint("TOPLEFT", swordP.content, "TOPLEFT", x, y)
        return cb
    end

    mkSwordCheck("Auto-show in combat",      4,  -2, "autoShowCombat", "ApplyLayout",
        "Pop the HUD open automatically when combat starts.")
    mkSwordCheck("Show role commands row", 220, -2, "showRoles",      "ApplyLayout",
        "TANK / HEAL / DPS rows for quick attack / stay orders.")
    mkSwordCheck("Show status strip",        4, -26, "showStatus",     "ApplyLayout",
        "Live row under the header with BOTS / AoE / BL / Queue.")
    mkSwordCheck("Start locked",           220, -26, "startLocked",    "nil",
        "Apply the lock at login so accidental drags don't happen mid-fight.")
    mkSwordCheck("Hide Warden minimap button in combat", 4, -50, "hideMinimapCombat", "nil",
        "Hides the main minimap button when combat starts so it can't be mis-clicked.")

    -- Density dropdown
    local densLbl = swordP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    densLbl:SetPoint("TOPLEFT", swordP.content, "TOPLEFT", 4, -80)
    densLbl:SetText("DENSITY")
    densLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    local densDrop = CreateFrame("Frame", "WardenSwordDensityDrop", swordP.content, "UIDropDownMenuTemplate")
    densDrop:SetPoint("TOPLEFT", densLbl, "BOTTOMLEFT", -16, -2)
    ns.UI.Dropdown.style(densDrop, 110)
    local DENS_LABELS = { tiny = "Tiny", compact = "Compact", normal = "Normal" }
    UIDropDownMenu_Initialize(densDrop, function()
        for _, k in ipairs({ "tiny", "compact", "normal" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = DENS_LABELS[k], k
            info.func = function(self)
                sw.density = self.value
                UIDropDownMenu_SetText(densDrop, DENS_LABELS[self.value])
                if ns.WardenSword and ns.WardenSword.ApplyLayout then
                    ns.WardenSword.ApplyLayout()
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(densDrop, DENS_LABELS[sw.density] or DENS_LABELS.compact)

    -- Tone dropdown removed per user request (was a cosmetic placeholder
    -- with no actual color-palette wiring yet). Density alone drives HUD
    -- sizing; tone can come back later if we ship real palettes.

    -- Transparency slider (0.15 to 1.00). Applies live via SetAlpha on the
    -- HUD frame so the user can dial in the perfect blend with the game UI.
    local alphaLbl = swordP.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    alphaLbl:SetPoint("TOPLEFT", swordP.content, "TOPLEFT", 140, -80)
    alphaLbl:SetText("TRANSPARENCY")
    alphaLbl:SetTextColor(0.72, 0.58, 0.21, 1)

    local alphaSlider = CreateFrame("Slider", "WardenSwordAlphaSlider",
                                     swordP.content, "OptionsSliderTemplate")
    alphaSlider:SetWidth(160)
    alphaSlider:SetPoint("TOPLEFT", alphaLbl, "BOTTOMLEFT", 0, -10)
    alphaSlider:SetMinMaxValues(0.15, 1.00)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetValue(tonumber(sw.alpha) or 1.00)
    _G[alphaSlider:GetName() .. "Low"]:SetText("15%")
    _G[alphaSlider:GetName() .. "High"]:SetText("100%")
    local alphaVal = _G[alphaSlider:GetName() .. "Text"]
    alphaVal:SetText(string.format("%d%%", math.floor((tonumber(sw.alpha) or 1.00) * 100 + 0.5)))
    alphaSlider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v * 20 + 0.5) / 20      -- snap to 0.05
        sw.alpha = v
        alphaVal:SetText(string.format("%d%%", math.floor(v * 100 + 0.5)))
        if ns.WardenSword and ns.WardenSword.ApplyAlpha then
            ns.WardenSword.ApplyAlpha()
        end
    end)

    -- Action buttons
    local resetHud = ns.UI.Button.stone(swordP.content, "Reset HUD position", 160, 20)
    resetHud:SetPoint("TOPLEFT", swordP.content, "TOPLEFT", 4, -130)
    resetHud:SetScript("OnClick", function()
        if ns.WardenSword and ns.WardenSword.ResetPosition then
            ns.WardenSword.ResetPosition()
            ns.MsgInfo("WardenSword position reset.")
        end
    end)

    -- ============================================================
    -- Panel 3 - Maintenance
    -- ============================================================
    local maintP = ns.UI.Panel.Create(content, contentW - 16, 96, "Maintenance")
    maintP:SetPoint("TOPLEFT", swordP, "BOTTOMLEFT", 0, -6)

    local resetMinimap = ns.UI.Button.stone(maintP.content, "Reset minimap button", 180, 22)
    resetMinimap:SetPoint("TOPLEFT", maintP.content, "TOPLEFT", 4, -4)
    resetMinimap:SetScript("OnClick", function()
        db.minimapAngle = 225
        if ns.UI.Minimap and ns.UI.Minimap.Refresh then ns.UI.Minimap.Refresh() end
        ns.MsgInfo("Minimap button position reset.")
    end)

    local resetTracking = ns.UI.Button.stone(maintP.content, "Clear GUID tracking", 180, 22)
    resetTracking:SetPoint("TOPLEFT", maintP.content, "TOPLEFT", 190, -4)
    resetTracking:SetScript("OnClick", function()
        if ns.Engine and ns.Engine.ClearTracking then
            ns.Engine.ClearTracking()
            ns.MsgInfo("GUID tracking cleared. Re-Spec will now fall back to FIFO.")
        end
    end)

    -- Clear player flags: wipes the [P] table except your own character.
    -- Useful when the list has grown stale from recruits that have left.
    local clearFlags = ns.UI.Button.stone(maintP.content, "Clear player flags", 180, 22)
    clearFlags:SetPoint("TOPLEFT", maintP.content, "TOPLEFT", 4, -32)
    clearFlags:SetScript("OnClick", function()
        if ns.Persistence and ns.Persistence.ClearAllPlayerFlags then
            local n = ns.Persistence.ClearAllPlayerFlags()
            ns.MsgInfo(string.format(
                "Cleared %d player flag(s). Your own character is still protected.", n))
        end
    end)

    -- Re-seed any default raid presets that have been deleted. Never
    -- overwrites existing entries, so user edits are preserved.
    local restorePresets = ns.UI.Button.stone(maintP.content, "Restore default presets", 180, 22)
    restorePresets:SetPoint("TOPLEFT", maintP.content, "TOPLEFT", 190, -32)
    restorePresets:SetScript("OnClick", function()
        if ns.Persistence and ns.Persistence.RestoreDefaultPresets then
            local n = ns.Persistence.RestoreDefaultPresets()
            if n > 0 then
                ns.MsgInfo(string.format("Restored %d default preset(s).", n))
            else
                ns.MsgInfo("All default presets are already present.")
            end
        end
    end)

    -- ============================================================
    -- Panel 4 - About (PATCH_NOTES §13b: moved out of a floating footer
    -- that kept clipping on the right into its own panel so the credits
    -- get room to wrap cleanly).
    -- ============================================================
    -- UI-04: give the About panel enough height for the full credits line
    -- to wrap cleanly (previously the "OptimalRaidCompo..." tail was cut
    -- off). Heights tuned for the default 0.80 scale FrizQT line height.
    local aboutP = ns.UI.Panel.Create(content, contentW - 16, 80, "About")
    aboutP:SetPoint("TOPLEFT", maintP, "BOTTOMLEFT", 0, -6)

    local aboutTxt = aboutP.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    aboutTxt:SetPoint("TOPLEFT",     aboutP.content, "TOPLEFT",      4, -4)
    aboutTxt:SetPoint("BOTTOMRIGHT", aboutP.content, "BOTTOMRIGHT", -4,  4)
    aboutTxt:SetJustifyH("LEFT")
    aboutTxt:SetJustifyV("TOP")
    aboutTxt:SetWordWrap(true)
    aboutTxt:SetNonSpaceWrap(false)
    aboutTxt:SetText(
        "|cffe6d5a8Warden v" .. (GetAddOnMetadata("Warden", "Version") or "?") .. "|r\n"
        .. "Forked from WSSM (Patchs & Valleriaa). Merges "
        .. "WarstormBotManager (Moroes), WBM Lite and "
        .. "OptimalRaidComposer (both by Runshouse)."
    )

    -- Final scroll-child height: sum of panel heights + 6 px gaps + 4 px top
    -- margin + 8 px bottom padding. Keep in sync if panel heights change.
    content:SetHeight(4 + 130 + 6 + 236 + 6 + 70 + 6 + 180 + 6 + 96 + 6 + 80 + 8)
end

function ns.UI.Tabs.Settings.OnShow(pane)
    local db = ns.Persistence.DB
    if not db then return end
    local a = _G["WardenSetting_autoSpec"]
    if a then a:SetChecked(db.autoSpec == true) end
    local b = _G["WardenSetting_autoRaidDuringBuild"]
    if b then b:SetChecked(db.autoRaidDuringBuild == true) end
    local w = _G["WardenSetting_whisperFilter"]
    if w then w:SetChecked(db.whisperFilter == true) end
end

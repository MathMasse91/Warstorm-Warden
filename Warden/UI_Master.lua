-- =====================================================
-- Warden - UI_Master.lua
-- Single master frame with 6 bottom tabs (Spec / Controls / Comp / Roster /
-- Settings / Help). Uses Blizzard's CharacterFrameTabButtonTemplate +
-- PanelTemplates_SetTab for tab switching.
-- Each tab's content lives in UI_Tab<Name>.lua and exposes BuildInto(pane).
-- =====================================================

local _, ns = ...

ns.UI.Master = ns.UI.Master or {}

local MASTER_W, MASTER_H = 760, 600
local CONTENT_MARGIN_T   = 44  -- below title
local CONTENT_MARGIN_B   = 30  -- PATCH_NOTES §3: tabs now tuck flush (was 38)
local CONTENT_MARGIN_X   = 16
local FOOTER_H           = 22

local TAB_DEFS = {
    { key = "Spec",     label = "Spec"     },
    { key = "Controls", label = "Controls" },
    { key = "Comp",     label = "Bot Comp" },
    { key = "Roster",   label = "Roster"   },
    -- { key = "BoP",      label = "BoP"      },  -- disabled in v1.0.0
    { key = "Settings", label = "Settings" },
    { key = "Help",     label = "Help"     },
}

local frame
local panes   = {}   -- pane frames indexed 1..N
local tabBtns = {}   -- tab button frames
local built   = {}   -- [index] = true when pane BuildInto was called

-- ----------------------------------------------------------
-- Tab selection
-- ----------------------------------------------------------
local function showTab(index)
    if not panes[index] then return end

    if ns.DebugF then
        ns.DebugF("master", "showTab %d (%s) built=%s",
            index, TAB_DEFS[index] and TAB_DEFS[index].key or "?",
            built[index] and "Y" or "N")
    end

    for i, p in ipairs(panes) do
        if i == index then p:Show() else p:Hide() end
    end

    -- Lazy build BEFORE SetTab so the pane content is visible even if
    -- Blizzard's tab-highlight code errors on some clients. Use xpcall with
    -- debugstack so BuildInto failures surface a real traceback instead of
    -- a truncated string (pcall gives you no stack frame on 3.3.5a).
    local key = TAB_DEFS[index].key
    if not built[index] then
        built[index] = true
        local tab = ns.UI.Tabs[key]
        if tab and tab.BuildInto then
            local ok, err = xpcall(function() tab.BuildInto(panes[index]) end, function(e)
                return tostring(e) .. "\n" .. (debugstack and debugstack(2) or "")
            end)
            if not ok then
                local msg = panes[index]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                msg:SetPoint("TOPLEFT", 8, -8)
                msg:SetWidth(panes[index]:GetWidth() - 16)
                msg:SetJustifyH("LEFT")
                msg:SetText("|cffff0000[BuildInto " .. key .. " failed]|r\n" .. tostring(err))
                if ns.LogError then ns.LogError("BuildInto " .. key .. ": " .. tostring(err)) end
            end
        else
            local msg = panes[index]:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            msg:SetPoint("CENTER", 0, 0)
            msg:SetText("|cffff0000Tab `" .. key .. "` has no BuildInto(pane) exported.|r")
        end
    end

    -- Tab highlight - guarded so a failure here doesn't blank the pane.
    if PanelTemplates_SetTab then
        pcall(PanelTemplates_SetTab, frame, index)
    end

    local tab = ns.UI.Tabs[key]
    if tab and tab.OnShow then pcall(tab.OnShow, panes[index]) end

    if ns.Persistence.DB then ns.Persistence.DB.activeTab = index end

    -- Black-page detector. The user-reported "page devient noir" bug is
    -- the frame staying visible but the active pane looking empty (just
    -- the dark backdrop). That happens when no child FRAME of the pane
    -- is visible - e.g., BuildInto ran partially and left no widgets, or
    -- an OnShow errored and hid everything. Count visible child frames
    -- right after the show sequence and force-log the anomaly so the
    -- next repro lands in WardenLog without the user having to
    -- pre-enable any debug category.
    local activePane = panes[index]
    if activePane and activePane:IsShown() then
        local visibleChildren = 0
        local totalChildren   = 0
        for _, kid in ipairs({ activePane:GetChildren() }) do
            totalChildren = totalChildren + 1
            if kid:IsShown() then visibleChildren = visibleChildren + 1 end
        end
        if totalChildren > 0 and visibleChildren == 0 then
            local inC = (InCombatLockdown and InCombatLockdown()) and "Y" or "N"
            local msg = string.format(
                "black-page: tab=%d(%s) combat=%s built=%s children=%d/0 visible",
                index, key or "?", inC, tostring(built[index]), totalChildren)
            if ns.LogError then ns.LogError(msg) end
        elseif totalChildren == 0 and built[index] then
            local msg = string.format(
                "black-page: tab=%d(%s) pane has ZERO child frames despite built=true",
                index, key or "?")
            if ns.LogError then ns.LogError(msg) end
        end
    end
end

-- ----------------------------------------------------------
-- Frame build
-- ----------------------------------------------------------
local function buildFrame()
    frame = CreateFrame("Frame", "WardenMainFrame", UIParent)
    frame:SetSize(MASTER_W, MASTER_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    -- Real fix for the "grouping" issue:
    --
    -- Problem: with strata=MEDIUM and the Blizzard DialogBox-Background
    -- texture, pieces of the game UI (default party member frames, raid
    -- frames, some HUD widgets) were painting through the Warden frame -
    -- most visibly inside the footer strip, which had NO opaque backdrop
    -- of its own. The result looked like Warden and those widgets were
    -- stacked in random z-order.
    --
    -- Fix: (1) raise the frame to HIGH strata so it sits above Blizzard's
    -- default HUD, (2) paint a fully opaque solid texture inside the frame
    -- BEHIND the DialogBox chrome so there are no transparent gaps left
    -- where foreign UI can leak in, (3) give the footer its own solid bg
    -- (see below).
    frame:SetFrameStrata("HIGH")

    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    frame:SetBackdropColor(0, 0, 0, 1)

    -- Solid opaque fill covering the entire interior. WHITE8x8 + vertex
    -- color, drawn at BACKGROUND layer so it sits under all chrome and
    -- children. This is what actually stops the party-frame bleed-through.
    local frameBg = frame:CreateTexture(nil, "BACKGROUND")
    frameBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    frameBg:SetVertexColor(0.055, 0.04, 0.02, 1.0)
    frameBg:SetPoint("TOPLEFT",     frame, "TOPLEFT",      3,  -3)
    frameBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3,   3)

    -- Title - upgraded to gold-Cinzel feel per Direction I.
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("WARDEN")
    title:SetTextColor(1, 0.82, 0) -- Blizzard header gold
    frame.title = title

    -- Subtitle (muted tone, mono-feel). PATCH_NOTES §15: middle dot
    -- separator instead of hyphen - "\194\183" is UTF-8 U+00B7 which FrizQT
    -- renders (Latin-1 supplement block).
    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -1)
    sub:SetText("raid commander \194\183 v" .. (GetAddOnMetadata("Warden", "Version") or "?"))
    sub:SetTextColor(0.61, 0.55, 0.40) -- gold-dim
    frame.subLabel = sub

    -- Close X - P2 review asked for an 8px left offset so it clears the gold
    -- corner ornament on the DialogBox border.
    local closeX = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeX:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    closeX:SetScript("OnClick", function()
        ns.UI.Master._RequestHide("X click")
        if ns.UI.Help and ns.UI.Help.frame and ns.UI.Help.frame:IsShown() then
            ns.UI.Help.frame:Hide()
        end
    end)

    -- Bind ESC-close
    tinsert(UISpecialFrames, "WardenMainFrame")

    -- Content area (shared parent for all panes)
    local paneW = MASTER_W - CONTENT_MARGIN_X * 2
    local paneH = MASTER_H - CONTENT_MARGIN_T - CONTENT_MARGIN_B

    for i, def in ipairs(TAB_DEFS) do
        local pane = CreateFrame("Frame", "WardenPane_" .. def.key, frame)
        pane:SetSize(paneW, paneH)
        pane:SetPoint("TOPLEFT", frame, "TOPLEFT",
            CONTENT_MARGIN_X, -CONTENT_MARGIN_T)
        -- Fully opaque pane background. The previous 0.94 alpha left a 6%
        -- bleed-through window that made the Warden content look like it
        -- shared z-order with the game's party frames (see grouping fix).
        local bg = pane:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetVertexColor(0.10, 0.08, 0.05, 1.00)
        bg:SetAllPoints(pane)
        pane:Hide()
        panes[i] = pane
    end

    -- ------------------------------------------------------
    -- Persistent status footer (Direction I)
    -- Lives inside the frame, above the tab strip that hangs below. Shows
    -- LIVE dot + current target + queue depth + tracked count + BL state +
    -- hotkey hint. Refreshes on roster/target events + 0.5s ticker.
    -- ------------------------------------------------------
    local footer = CreateFrame("Frame", "WardenFooter", frame)
    footer:SetHeight(FOOTER_H)
    footer:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  12, 10)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)

    -- Solid opaque footer bg. Without this the footer was transparent and
    -- Blizzard's party / raid member frames (which sit at MEDIUM strata)
    -- were painting through the strip between the stats text and the BL
    -- pill. Painting a solid stone-colored texture at BACKGROUND under the
    -- 1px top rule stops the bleed-through entirely.
    local footerBg = footer:CreateTexture(nil, "BACKGROUND")
    footerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    footerBg:SetVertexColor(0.07, 0.05, 0.03, 1.0)
    footerBg:SetAllPoints(footer)

    local topBorder = footer:CreateTexture(nil, "ARTWORK")
    topBorder:SetTexture("Interface\\Buttons\\WHITE8x8")
    topBorder:SetVertexColor(0.23, 0.18, 0.13, 1)
    topBorder:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
    topBorder:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(1)

    local dot = footer:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    dot:SetSize(8, 8)
    dot:SetVertexColor(0.18, 0.80, 0.25, 1)
    dot:SetPoint("LEFT", footer, "LEFT", 4, -1)

    local targetLbl = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    targetLbl:SetPoint("LEFT", dot, "RIGHT", 6, 0)
    targetLbl:SetText("|cff808080no target|r")

    local statsLbl = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statsLbl:SetPoint("LEFT", targetLbl, "RIGHT", 18, 0)
    statsLbl:SetText("q 0  tracked 0  BL OFF")

    local hintLbl = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintLbl:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
    hintLbl:SetText("Esc close  -  /warden")

    -- TASKS.md §8.2: BL mini-pill 54x16. Stone bg (reuses our stone button
    -- texture so it matches the rest of the addon), label color swaps
    -- amber (OFF) / green (ON).
    local blBtn = ns.UI.Button.stone(footer, "BL OFF", 54, 16)
    blBtn:SetPoint("RIGHT", hintLbl, "LEFT", -10, 0)
    local function refreshBLBtn()
        local on = ns.Persistence.DB and ns.Persistence.DB.bloodlust == true
        blBtn:SetText(on and "BL ON" or "BL OFF")
        local fs = blBtn:GetFontString()
        if fs then
            if on then fs:SetTextColor(0.18, 0.80, 0.25)    -- green when ON
            else fs:SetTextColor(1.00, 0.60, 0.00) end       -- amber when OFF
        end
    end
    refreshBLBtn()
    blBtn:SetScript("OnClick", function()
        local db = ns.Persistence.DB
        if not db then return end
        db.bloodlust = not (db.bloodlust == true)

        -- See Engine.Bloodlust() for the protocol rationale: the bot uses
        -- `ss +/-<spellId>` (spell exclude list) rather than an `nc +bloodlust`
        -- strategy flag, which doesn't exist. 2825 = Bloodlust (Horde);
        -- 32182 = Heroism (Alliance). Pick the one that matches the player's
        -- faction so same-faction shamans get the right command.
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        local spellId = (faction == "Alliance") and 32182 or 2825
        local cmd     = db.bloodlust and ("ss -" .. spellId) or ("ss +" .. spellId)

        local n = ns.WhisperClass and ns.WhisperClass("SHAMAN", cmd) or 0
        if n == 0 then
            ns.MsgWarn("No shaman bots found - BL had no target.")
        else
            ns.MsgInfo(string.format("Bloodlust %s - whispered %d shaman(s).",
                db.bloodlust and "ON" or "OFF", n))
        end
        refreshBLBtn()
    end)
    blBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetText("Bloodlust / Heroism", 1, 1, 1)
        GameTooltip:AddLine("Whispers `ss +/-2825` (Horde) or `ss +/-32182` (Alliance) to every shaman in group - toggles their spell-exclude list so they will or will not cast Lust/Heroism.",
            0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    blBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.footer = { frame = footer, dot = dot, target = targetLbl,
                     stats = statsLbl, blBtn = blBtn, refreshBL = refreshBLBtn }

    local function refreshFooter()
        if UnitExists("target") and UnitIsPlayer("target") then
            local name = UnitName("target") or "?"
            local _, classTok = UnitClass("target")
            targetLbl:SetText(ns.ColorClass(classTok or "", name))
        else
            targetLbl:SetText("|cff808080no target|r")
        end

        local qDepth = (ns.Engine.QueueDepth and ns.Engine.QueueDepth()) or 0
        local tracked = 0
        if ns.Engine.state and ns.Engine.state.assignedSpecs then
            for _ in pairs(ns.Engine.state.assignedSpecs) do tracked = tracked + 1 end
        end
        -- TASKS.md §8.1: bullet-separated "q 0 \194\183 tracked 3".
        statsLbl:SetText(string.format("q %d \194\183 tracked %d", qDepth, tracked))
        refreshBLBtn()
    end

    footer:RegisterEvent("PLAYER_TARGET_CHANGED")
    footer:RegisterEvent("RAID_ROSTER_UPDATE")
    footer:RegisterEvent("PARTY_MEMBERS_CHANGED")
    footer:RegisterEvent("PLAYER_ENTERING_WORLD")
    footer:SetScript("OnEvent", refreshFooter)

    footer._accum = 0
    footer:SetScript("OnUpdate", function(self, elapsed)
        self._accum = (self._accum or 0) + elapsed
        if self._accum < 0.5 then return end
        self._accum = 0
        refreshFooter()
    end)
    refreshFooter()

    -- Tab bar (bottom of frame). PanelTemplates_SetTab expects tabs named
    -- <frameName>Tab<i>, so we MUST name them "WardenMainFrameTab1" etc.
    --
    -- On this WarStorm client, CharacterFrameTabButtonTemplate's OnLoad does
    -- NOT set tab.cursorOffset / tab.deselectedTextX, so every internal call
    -- to PanelTemplates_TabResize / UpdateTabs errors with "attempt to perform
    -- arithmetic on field 'cursorOffset' (a nil value)" and eventually causes
    -- a C stack overflow. Explicitly seed those numeric fields BEFORE any
    -- template call touches them, and wrap the template calls in pcall.
    for i, def in ipairs(TAB_DEFS) do
        local btn = CreateFrame("Button", "WardenMainFrameTab" .. i, frame, "CharacterFrameTabButtonTemplate")
        btn:SetID(i)
        btn:SetText(def.label)
        btn.cursorOffset    = 0
        btn.deselectedTextX = 0
        btn.selectedTextX   = 0
        btn.textureSize     = 0
        if PanelTemplates_TabResize then
            pcall(PanelTemplates_TabResize, btn, 0)
        end
        -- PATCH_NOTES §3: anchor first tab at BOTTOMLEFT (30, 2) so tab body
        -- overlaps the frame bottom edge by 2px, mimicking CharacterFrame.
        if i == 1 then
            btn:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 30, 2)
        else
            btn:SetPoint("LEFT", tabBtns[i - 1], "RIGHT", -16, 0)
        end
        btn:SetScript("OnClick", function() showTab(i) end)
        tabBtns[i] = btn
    end

    PanelTemplates_SetNumTabs(frame, #TAB_DEFS)

    -- Apply saved scale
    if ns.Persistence.DB and type(ns.Persistence.DB.masterScale) == "number" then
        frame:SetScale(ns.Persistence.DB.masterScale)
    end

    frame:Hide()
end

-- ----------------------------------------------------------
-- Public API
-- ----------------------------------------------------------
local function openAtLastTab()
    if not frame then
        if ns.Debug then ns.Debug("master", "buildFrame (first open)") end
        buildFrame()
    end
    frame:Show()
    local db  = ns.Persistence.DB
    local tab = (db and type(db.activeTab) == "number" and db.activeTab) or 1
    if tab < 1 or tab > #TAB_DEFS then tab = 1 end
    if ns.DebugF then
        ns.DebugF("master", "openAtLastTab: tab=%d shownAfterShow=%s",
            tab, frame:IsShown() and "Y" or "N")
    end
    showTab(tab)
end

function ns.UI.Master.Show() openAtLastTab() end

-- =====================================================================
-- "Hide is protected in combat" workaround.
--
-- On WarStorm 3.3.5a, after a variable amount of combat time (~45 s
-- reported by the user), frame:Hide() on WardenMainFrame starts silently
-- no-op'ing even though the frame isn't secure by any API we call. We
-- can't stop Blizzard from protecting it, but we CAN:
--   1. Gather every piece of state we can on first failure so we can
--      figure out WHY it's protected.
--   2. Fall back to alpha+mouse-disabled so the user at least gets an
--      invisible, click-through frame until combat ends.
--   3. Queue a real Hide() for PLAYER_REGEN_ENABLED so the frame
--      properly collapses once combat allows it.
-- =====================================================================
local pendingHideAtRegen = false

local function dumpFrameState(ctx)
    if not frame then return end
    local parts = {
        "ctx=" .. tostring(ctx),
        "combat=" .. tostring(InCombatLockdown and InCombatLockdown()),
        "shown=" .. tostring(frame:IsShown()),
        "visible=" .. tostring(frame:IsVisible()),
        "alpha=" .. tostring(frame:GetAlpha()),
        "strata=" .. tostring(frame:GetFrameStrata()),
        "level=" .. tostring(frame:GetFrameLevel()),
        "mouse=" .. tostring(frame:IsMouseEnabled()),
        "protected=" .. tostring(frame.IsProtected and frame:IsProtected() or "n/a"),
        "forbidden=" .. tostring(frame.IsForbidden and frame:IsForbidden() or "n/a"),
    }
    return table.concat(parts, " ")
end

-- Remember the original anchor so we can restore it after an
-- off-screen move. Captured lazily the first time we have to move.
local savedPoint

local function captureAnchor()
    if savedPoint or not frame then return end
    -- Most recent anchor (frame.StartMoving may have added others).
    local p, rel, relP, x, y = frame:GetPoint(1)
    if p then savedPoint = { p, rel, relP, x, y } end
end

local function restoreAnchor()
    if not frame or not savedPoint then return end
    frame:ClearAllPoints()
    frame:SetPoint(savedPoint[1], savedPoint[2] or UIParent,
        savedPoint[3], savedPoint[4] or 0, savedPoint[5] or 0)
end

-- Try to actually hide, or force-hide via off-screen displacement when
-- Blizzard refuses the real Hide in combat.
local function tryHide(reason)
    if not frame or not frame:IsShown() then return true end

    frame:Hide()
    if not frame:IsShown() then return true end

    -- Hide was refused. Persist diagnostic state to the log but stay
    -- silent in chat. /wardenlog tail 5 surfaces these entries.
    local dumpedState = dumpFrameState(reason)
    if ns.LogError then
        ns.LogError(reason .. ": frame:Hide() refused. " .. dumpedState)
    end

    -- The user wants an actual close, not a click-through: move the
    -- frame far off-screen, drop its alpha, and kill mouse. Visually
    -- equivalent to Hide(), and preserved through combat because
    -- SetPoint / SetAlpha / EnableMouse aren't combat-protected on
    -- plain frames even when Hide is. tryShow() undoes all three.
    captureAnchor()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 5000, -5000)
    frame:SetAlpha(0)
    frame:EnableMouse(false)
    pendingHideAtRegen = true
    return false
end

local function tryShow(reason)
    -- First-ever show of the session: the frame hasn't been built yet.
    -- Route through openAtLastTab() which builds the frame + applies
    -- the last active tab. Returning false here (previous behavior)
    -- caused the first left-click on the minimap button to silently
    -- no-op on a fresh WoW session: Toggle() -> tryShow -> bail. A
    -- right-click worked because ShowTab("Help") -> Show() ->
    -- openAtLastTab() builds the frame as a side effect, after which
    -- every subsequent left-click found `frame` non-nil and worked.
    if not frame then
        openAtLastTab()
        return true
    end
    pendingHideAtRegen = false
    -- Undo an off-screen / soft-hide before re-showing.
    if savedPoint then
        restoreAnchor()
        savedPoint = nil
    end
    frame:SetAlpha(1)
    frame:EnableMouse(true)
    if not frame:IsShown() then
        openAtLastTab()
    end
    if ns.DebugF then ns.DebugF("master", "tryShow ok (%s)", reason) end
    return true
end

-- One-shot combat-end handler that collapses a soft-hidden frame to a
-- real Hide() when the player leaves combat.
local _regenHook = CreateFrame("Frame", "WardenMasterRegenHook")
_regenHook:RegisterEvent("PLAYER_REGEN_ENABLED")
_regenHook:SetScript("OnEvent", function()
    if pendingHideAtRegen and frame then
        pendingHideAtRegen = false
        -- Restore visuals / position BEFORE hiding so the next open
        -- starts from a clean state (in-place anchor, normal alpha,
        -- mouse enabled).
        if savedPoint then
            restoreAnchor()
            savedPoint = nil
        end
        frame:SetAlpha(1)
        frame:EnableMouse(true)
        frame:Hide()
        if ns.DebugF then
            ns.DebugF("combat", "PLAYER_REGEN_ENABLED: deferred Hide applied, shown=%s",
                frame:IsShown() and "Y" or "N")
        end
    end
end)

-- Internal hooks used by the X button / minimap / slash commands so we
-- only have one place to evolve the hide-in-combat workaround.
function ns.UI.Master._RequestHide(reason)
    return tryHide(reason or "RequestHide")
end

function ns.UI.Master._RequestShow(reason)
    return tryShow(reason or "RequestShow")
end

function ns.UI.Master.Toggle()
    local inC         = (InCombatLockdown and InCombatLockdown()) and "Y" or "N"
    local shownBefore = (frame and frame:IsShown() and frame:GetAlpha() > 0) and "Y" or "N"
    if ns.DebugF then
        ns.DebugF("master", "Toggle: combat=%s frame=%s shownBefore=%s",
            inC, frame and "Y" or "N", shownBefore)
    end

    if frame and frame:IsShown() and frame:GetAlpha() > 0 then
        tryHide("Toggle")
    else
        tryShow("Toggle")
    end

    if ns.DebugF then
        ns.DebugF("master", "Toggle done: shown=%s visible=%s alpha=%s",
            tostring(frame and frame:IsShown()),
            tostring(frame and frame:IsVisible()),
            tostring(frame and frame:GetAlpha()))
    end
end

function ns.UI.Master.Hide()
    if frame then tryHide("Master.Hide") end
end

function ns.UI.Master.IsShown()
    return frame and frame:IsShown()
end

function ns.UI.Master.ShowTab(key)
    for i, def in ipairs(TAB_DEFS) do
        if def.key == key then
            ns.UI.Master.Show()
            showTab(i)
            return
        end
    end
end

function ns.UI.Master.Frame() return frame end
function ns.UI.Master.GetPane(key)
    for i, def in ipairs(TAB_DEFS) do
        if def.key == key then return panes[i] end
    end
end

-- Global wrappers for Bindings.xml
function WARDEN_Toggle() ns.UI.Master.Toggle() end
function WARDEN_ShowTab(key) ns.UI.Master.ShowTab(key) end


-- =====================================================
-- Warden - Shield.lua
-- WardenShield: discovery + capture HUD. User selects a bot in-game,
-- clicks `los` or `spells` in the HUD, the addon whispers the command,
-- captures whispers from that bot for `db.shield.captureSec` seconds,
-- and renders each captured line as a clickable row that fires the
-- corresponding follow-up (`u <payload>` or `cast <payload>`).
--
-- Spec: docs/specs/2026-04-26-wardenshield-design.md
-- Redesign: docs/Warden Design Doc.html (May 2026)
-- =====================================================

local _, ns = ...
ns.Shield = ns.Shield or {}

-- ----------------------------------------------------------
-- Tunables (frame chrome). Conditional rows (banner, cast-on chip,
-- filter editbox) are show/hidden by the layout pass — the frame
-- height stays fixed so dragging the HUD doesn't make it jump on every
-- mode flip.
-- ----------------------------------------------------------
local FRAME_W         = 260
local HEADER_H        = 22
local BANNER_H        = 16    -- armed banner under header (conditional)
local TARGET_H        = 32    -- 2 lines: name+pick / locked-state
local ACTION_H        = 22
local MODE_H          = 22    -- segmented control, full-width
local CAST_ON_H       = 22    -- chip caston (conditional)
local FILTER_H        = 18    -- editbox filtre (conditional, >FILTER_THRESHOLD items)
local STATUS_H        = 16    -- idle fallback (replaced by banner when armed)
local LIST_H          = 200   -- baseline; layout pass adjusts to fill
local ROW_H           = 18
local SECTION_HDR_H   = 14
local FOOTER_H        = 22
local PAD             = 8
local GAP             = 6
local MAX_LINES       = 200      -- spec §12: cap to prevent runaway accumulation
local FILTER_THRESHOLD = 20      -- show filter editbox only above this many items

-- ----------------------------------------------------------
-- Module state. `state.shieldDB` is set during build() to point at the
-- persisted sub-table; everything else is runtime-only.
-- ----------------------------------------------------------
local state = {
    frame        = nil,
    shieldDB     = nil,
    target       = nil,         -- frozen target name for the active capture
    targetClass  = nil,         -- classToken for class-colored display
    mode         = nil,         -- "los" | "spells" | nil
    captureUntil = 0,           -- GetTime() deadline; 0 = idle
    lines        = {},          -- { { raw, payload, ts, from, mode }, ... }
    rowFrames    = {},          -- pool of clickable list rows
    losBtn       = nil,
    spellsBtn    = nil,
    clearBtn     = nil,
    pickBtn      = nil,
    targetLbl    = nil,         -- top line of target row (class-colored name)
    targetSub    = nil,         -- bottom line (LIVE / LOCKED indicator)
    statusLbl    = nil,         -- idle status strip (hidden when banner shown)
    statusRow    = nil,
    statusBlip   = nil,         -- 6×6 gray dot shown in idle status row
    scrollFrame  = nil,
    scrollChild  = nil,
    listenerArmed = false,
    -- Action mode dispatcher. The segmented control sets state.actionMode;
    -- clickLine() reads it to choose the right command verb.
    actionMode    = "cast",     -- "cast" | "caston" | "selfcast" | "ban" | "unban"
    castOnTarget  = nil,
    castOnClass   = nil,
    castOnChip    = nil,        -- conditional row (caston only)
    -- Filter (conditional editbox)
    filter        = "",
    filterBox     = nil,
    filterRow     = nil,
    -- Armed banner replaces the status strip when capture is live.
    bannerArmed   = nil,
    -- Segmented widget replaces the old 5-button mode row.
    segMode       = nil,
    -- View toggle: capture list vs persisted exclusions.
    viewExclusions  = false,
    exclusionsBtn   = nil,
    hideGray        = false,
    hideGrayBtn     = nil,
    -- Computed each refresh
    bannedSet     = {},
    multiBot      = false,
}

-- ----------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------
local function db()       return ns.Persistence and ns.Persistence.DB end
local function shieldDB() local d = db(); return d and d.shield end

local function trim(s)
    s = s or ""
    s = s:gsub("^%s+", ""); s = s:gsub("%s+$", "")
    return s
end

-- Strip the WoW item-link wrapper so a bracketed-but-linked label still
-- yields a clean payload. Example:
--   "|cffffffff|Hitem:1234::::::::|h[Twilight Portal]|h|r"  ->  "Twilight Portal"
-- For non-linked text, returns the input unchanged minus surrounding spaces.
local function stripItemLinks(s)
    if type(s) ~= "string" then return s end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|H[^|]+|h", "")
    s = s:gsub("|h", "")
    s = s:gsub("|r", "")
    return s
end

local function extractPayload(text)
    if type(text) ~= "string" or text == "" then return "" end
    local clean = stripItemLinks(text)
    local bracket = clean:match("%[([^%]]+)%]")
    if bracket and bracket ~= "" then return bracket end
    return trim(clean)
end

local function extractSpellId(raw)
    if type(raw) ~= "string" then return nil end
    local id = raw:match("|Hspell:(%d+)|h")
    return id and tonumber(id) or nil
end

local function extractObjectId(raw)
    if type(raw) ~= "string" then return nil end
    local entry = raw:match("|Hfound:%d+:(%d+):|h")
    return entry and tonumber(entry) or nil
end

local function extractRank(raw)
    if type(raw) ~= "string" then return nil end
    return raw:match("|c(%x%x%x%x%x%x%x%x)%a+|r%s*$")
end

local function isSeparator(payload)
    if type(payload) ~= "string" then return false end
    return payload:match("^===") ~= nil or payload:match("^%-%-%-") ~= nil
end

-- Convert a captured-line `mode` ("los" | "spells") to a section label.
-- The old impl filtered "=== Spells ===" separator lines outright; the redesign
-- builds sections from line.mode instead so it doesn't depend on the bot's
-- exact whisper formatting.
local function sectionLabel(mode)
    if mode == "spells" then return "Spells" end
    if mode == "los"    then return "Game objects" end
    return "Other"
end

local TOK = ns.Tokens or {}
local STONE_RIM = TOK.stone_rim or { 0.23, 0.18, 0.13 }
local STONE_TILE= TOK.stone_tile or { 0.16, 0.13, 0.09 }
local STONE_DARK= TOK.stone_dark or { 0.06, 0.04, 0.03 }
local GOLD_RIM  = TOK.gold_rim  or { 0.66, 0.54, 0.30 }
local GOLD      = TOK.gold      or { 1.00, 0.82, 0.00 }
local GOLD_DIM  = TOK.gold_dim  or { 0.72, 0.58, 0.21 }
local INK_RED   = TOK.ink_red   or { 0.88, 0.29, 0.23 }
local AMBER     = TOK.amber     or { 1.00, 0.60, 0.00 }
local TEXT_WARM = TOK.text_warm or { 1.00, 0.92, 0.75 }

-- Forward declarations. `ensureRow` references `rowOnClick`, but the
-- click handler references `clickLine`. Same pattern as UI_TabComp.lua.
local clickLine, rowOnClick, refreshList, refreshAll, layout
local refreshTargetLine, refreshActionMode, refreshStatus, refreshBanner

-- ----------------------------------------------------------
-- UI build
-- ----------------------------------------------------------
local function buildHeader(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(HEADER_H)
    h:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, 0)
    h:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", h, "LEFT", PAD, 0)
    title:SetText("WARDENSHIELD")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local hint = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 6, 0)
    hint:SetText("/wsh")
    hint:SetTextColor(0.55, 0.50, 0.42, 1)

    local close = CreateFrame("Button", nil, h)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", h, "RIGHT", -PAD, 0)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x")
    cfs:SetTextColor(0.85, 0.18, 0.12, 1)
    close:SetScript("OnClick", function() ns.Shield.Hide() end)

    local lock = CreateFrame("Button", nil, h)
    lock:SetSize(16, 16)
    lock:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local lfs = lock:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lfs:SetPoint("CENTER", lock, "CENTER", 0, 0)
    lock.fs = lfs
    lock:SetScript("OnClick", function() ns.Shield.ToggleLock() end)
    h.lockBtn = lock

    local rule = h:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT",  h, "BOTTOMLEFT",  0, 0)
    rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    return h
end

local function refreshLockGlyph()
    local h = state.frame and state.frame.header
    if not h or not h.lockBtn or not h.lockBtn.fs then return end
    local s = shieldDB()
    if s and s.locked then
        h.lockBtn.fs:SetText("*")
        h.lockBtn.fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    else
        h.lockBtn.fs:SetText("o")
        h.lockBtn.fs:SetTextColor(0.55, 0.50, 0.42, 1)
    end
end

refreshTargetLine = function()
    if not state.targetLbl then return end
    local locked = state.target and state.target ~= ""
    if locked then
        local cls = state.targetClass or ""
        local nameColored = ns.ColorClass(cls, state.target)
        local clsLabel = ""
        if cls ~= "" then
            local pretty = (cls:sub(1, 1) .. cls:sub(2):lower())
            clsLabel = "  |cff808080" .. pretty .. "|r"
        end
        state.targetLbl:SetText(nameColored .. clsLabel)
        if state.targetSub then
            state.targetSub:SetText("\194\183 LOCKED")
            state.targetSub:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        end
    elseif UnitExists("target") and UnitIsPlayer("target") then
        local name = UnitName("target") or "?"
        local _, classTok = UnitClass("target")
        local nameColored = ns.ColorClass(classTok or "", name)
        state.targetLbl:SetText(nameColored .. "  |cff808080live|r")
        if state.targetSub then
            state.targetSub:SetText("CLICK [PICK] TO LOCK")
            state.targetSub:SetTextColor(0.45, 0.40, 0.32, 1)
        end
    else
        state.targetLbl:SetText("|cff808080no target|r")
        if state.targetSub then
            state.targetSub:SetText("TARGET A BOT, THEN CLICK PICK")
            state.targetSub:SetTextColor(0.45, 0.40, 0.32, 1)
        end
    end
end

local function refreshModeRims()
    local active = (state.captureUntil > 0 and state.captureUntil > GetTime())
    local function paint(btn, on)
        if not btn or not btn.SetBackdropBorderColor then return end
        local rim   = on and GOLD_RIM or STONE_RIM
        local label = on and GOLD or GOLD_DIM
        btn:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
        local fs = btn.GetFontString and btn:GetFontString()
        if fs then fs:SetTextColor(label[1], label[2], label[3], 1) end
    end
    paint(state.losBtn,    active and state.mode == "los")
    paint(state.spellsBtn, active and state.mode == "spells")
end

-- Repaint the segmented control + manage caston chip / hide-gray disabled.
refreshActionMode = function()
    if state.segMode and state.segMode.SetActive then
        state.segMode:SetActive(state.actionMode)
    end
    -- Caston chip visibility tied to actionMode
    if state.castOnChip then
        if state.actionMode == "caston" then
            if state.castOnTarget and state.castOnTarget ~= "" then
                -- Solid: gold rim + faint gold fill + class-colored name
                state.castOnChip:SetBackdropColor(0.18, 0.13, 0.04, 1)
                state.castOnChip:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
                local cls = state.castOnClass or ""
                state.castOnChip._lblPrefix:SetText("CAST ON")
                state.castOnChip._lblPrefix:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
                state.castOnChip._lblName:SetText(ns.ColorClass(cls, state.castOnTarget))
                state.castOnChip._lblName:Show()
                state.castOnChip._lblHint:Hide()
            else
                -- Dashed (we simulate with stone backdrop + gold_rim dim fill)
                state.castOnChip:SetBackdropColor(0.10, 0.08, 0.04, 1)
                state.castOnChip:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
                state.castOnChip._lblPrefix:SetText("")
                state.castOnChip._lblName:Hide()
                state.castOnChip._lblHint:SetText("click a unit frame to set cast target")
                state.castOnChip._lblHint:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
                state.castOnChip._lblHint:Show()
            end
            state.castOnChip:Show()
        else
            state.castOnChip:Hide()
        end
    end
    -- hide-gray is bypassed in ban/unban modes (QA §3). Dim the button to signal.
    if state.hideGrayBtn then
        local lbl = state.hideGrayBtn:GetFontString()
        local bypassed = (state.actionMode == "ban" or state.actionMode == "unban")
        if bypassed then
            state.hideGrayBtn:EnableMouse(false)
            if lbl then lbl:SetTextColor(GOLD_DIM[1] * 0.4, GOLD_DIM[2] * 0.4, GOLD_DIM[3] * 0.4, 1) end
        else
            state.hideGrayBtn:EnableMouse(true)
            if lbl then
                if state.hideGray then
                    lbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
                else
                    lbl:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
                end
            end
        end
    end
end

-- Idle status row is hidden when capture is live (the banner takes over).
refreshStatus = function()
    if not state.statusLbl then return end
    local n = #state.lines
    local capturing = (state.captureUntil > 0 and state.captureUntil > GetTime())
    if capturing then
        state.statusLbl:Hide()
        if state.statusBlip then state.statusBlip:Hide() end
    else
        state.statusLbl:Show()
        if state.statusBlip then state.statusBlip:Show() end
        state.statusLbl:SetText(string.format("idle \194\183 %d line%s",
            n, n == 1 and "" or "s"))
        state.statusLbl:SetTextColor(0.61, 0.55, 0.40, 1)
        if state.statusBlip then
            state.statusBlip:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
        end
    end
    refreshModeRims()
end

refreshBanner = function()
    if not state.bannerArmed then return end
    local capturing = (state.captureUntil > 0 and state.captureUntil > GetTime())
    if capturing then
        local left = state.captureUntil - GetTime()
        if left < 0 then left = 0 end
        local n = #state.lines
        state.bannerArmed:SetVariant("amber")
        state.bannerArmed:SetText("LISTENING",
            string.format("%.1fs \194\183 %d line%s", left, n, n == 1 and "" or "s"))
        state.bannerArmed:SetPulse(true)
        state.bannerArmed:Show()
    else
        state.bannerArmed:SetPulse(false)
        state.bannerArmed:Hide()
    end
end

-- Build / reuse a clickable row. Each row can render as one of three kinds:
--   "section" : non-clickable header, with a hairline rule to its right
--   "line"    : capture line (clickable; pulses on click)
--   "excl"    : exclusion entry in the viewExclusions panel (click to unban)
local function ensureRow(idx, parent)
    local row = state.rowFrames[idx]
    if row then return row end
    row = CreateFrame("Button", "WardenShieldRow" .. idx, parent)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.10, 0.08, 0.05, 1)
    row:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)

    -- Red 6×6 dot drawn left of the text to signal a banned spell.
    local dot = row:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\Buttons\\WHITE8x8")
    dot:SetSize(6, 6)
    dot:SetPoint("LEFT", row, "LEFT", 6, 0)
    dot:SetVertexColor(INK_RED[1], INK_RED[2], INK_RED[3], 1)
    dot:Hide()
    row.dot = dot

    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT",  row, "LEFT",   6, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    row.fs = fs

    -- Bot tag (only shown when state.multiBot)
    local botTag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    botTag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    botTag:SetJustifyH("RIGHT")
    botTag:Hide()
    row.botTag = botTag

    -- Section header rule: a hair-line gold-rim rule that fills the row to
    -- the right of the section label. Hidden for line / excl kinds.
    local secRule = row:CreateTexture(nil, "OVERLAY")
    secRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    secRule:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
    secRule:SetHeight(1)
    secRule:Hide()
    row.secRule = secRule

    -- Section count label (small muted N on the right of section row).
    local secCount = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    secCount:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    secCount:SetJustifyH("RIGHT")
    secCount:Hide()
    row.secCount = secCount

    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetTexture("Interface\\Buttons\\WHITE8x8")
    hi:SetAllPoints(row)
    hi:SetBlendMode("ADD")
    hi:SetVertexColor(1, 1, 1, 0.10)
    row:SetHighlightTexture(hi)

    -- Pulse animation
    row._pulse = 0
    row.pulse = function(self)
        self._pulse = 0
        self:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
        self:SetScript("OnUpdate", function(s, elapsed)
            s._pulse = (s._pulse or 0) + elapsed
            if s._pulse >= 0.12 then
                s:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
                s:SetScript("OnUpdate", nil)
            end
        end)
    end
    row:SetScript("OnClick", rowOnClick)

    state.rowFrames[idx] = row
    return row
end

local function trackExclusion(id, name)
    if not id then return end
    local s = shieldDB(); if not s then return end
    s.exclusions = s.exclusions or {}
    for _, e in ipairs(s.exclusions) do
        if e.id == id then return end
    end
    table.insert(s.exclusions, { id = id, name = name or "?" })
end

local function untrackExclusion(id)
    if not id then return end
    local s = shieldDB(); if not s or type(s.exclusions) ~= "table" then return end
    for i, e in ipairs(s.exclusions) do
        if e.id == id then table.remove(s.exclusions, i); return end
    end
end

local function clickExclusion(item, idx)
    if not state.target or state.target == "" then
        ns.MsgWarn("No target locked - click [pick] first.")
        return
    end
    if ns.Persistence and ns.Persistence.IsPlayerName
       and ns.Persistence.IsPlayerName(state.target) then
        ns.MsgWarn(state.target .. " is flagged as a human player - skipping.")
        return
    end
    SendChatMessage("ss -" .. item.id, "WHISPER", nil, state.target)
    untrackExclusion(item.id)
    ns.MsgInfo(string.format("Removed `%s` (id %d) from %s's exclusions.",
        item.name or "?", item.id or 0, state.target))
    if ns.DebugF then
        ns.DebugF("shield", "unban id=%d name=%q", item.id or 0, item.name or "?")
    end
    if state.exclusionsBtn then
        local lbl = state.exclusionsBtn:GetFontString()
        local s = shieldDB(); local n = (s and s.exclusions) and #s.exclusions or 0
        if lbl then lbl:SetText("exclusions \194\183 " .. n) end
    end
    refreshList()
end

clickLine = function(idx)
    local item = state.displayItems and state.displayItems[idx]
    if not item or item.kind ~= "line" then return end
    local line = item.line
    if not line then return end
    local target = line.from or state.target
    if not target or target == "" then
        ns.MsgErr("No bot recorded for this line.")
        return
    end
    if ns.Persistence and ns.Persistence.IsPlayerName
       and ns.Persistence.IsPlayerName(target) then
        ns.MsgWarn(target .. " is flagged as a human player - skipping.")
        return
    end
    local mode = line.mode or state.mode
    if not mode then
        ns.MsgWarn("No active mode - click `los` or `spells` first.")
        return
    end

    local payload = line.payload or trim(line.raw)
    if payload == "" then
        ns.MsgWarn("Empty payload - line had no usable text.")
        return
    end

    local actionMode = state.actionMode or "cast"
    local cmd
    if actionMode == "cast" then
        if mode == "los" then
            cmd = "u [" .. payload .. "]"
        elseif mode == "spells" then
            cmd = "cast " .. payload
        end
    elseif actionMode == "caston" then
        if mode ~= "spells" then
            ns.MsgWarn("`on Y` only applies to spells - switch to a spells line.")
            return
        end
        if not state.castOnTarget or state.castOnTarget == "" then
            ns.MsgWarn("Click a unit frame first to set the cast target.")
            return
        end
        cmd = "cast " .. payload .. " on " .. state.castOnTarget
    elseif actionMode == "ban" then
        local id = extractSpellId(line.raw or "")
        if not id then
            ns.MsgWarn("No spell ID in this line - ban needs a spell link.")
            return
        end
        cmd = "ss +" .. id
        trackExclusion(id, payload)
    elseif actionMode == "unban" then
        local id = extractSpellId(line.raw or "")
        if not id then
            ns.MsgWarn("No spell ID in this line - unban needs a spell link.")
            return
        end
        cmd = "ss -" .. id
        untrackExclusion(id)
    elseif actionMode == "selfcast" then
        if mode ~= "spells" then
            ns.MsgWarn("`on me` only applies to spells - switch to a spells line.")
            return
        end
        local me = UnitName("player")
        if not me or me == "" then
            ns.MsgWarn("Could not resolve player name.")
            return
        end
        cmd = "cast " .. payload .. " on " .. me
    end

    if not cmd then
        ns.MsgWarn("Mode `" .. actionMode .. "` does not apply to this line.")
        return
    end

    SendChatMessage(cmd, "WHISPER", nil, target)
    ns.MsgInfo(string.format("Sent `%s` to %s.", cmd, target))
    if ns.DebugF then
        ns.DebugF("shield", "click idx=%d action=%s mode=%s payload=%q -> %s",
            idx, actionMode, tostring(mode), payload, target)
    end

    if actionMode == "ban" or actionMode == "unban" then
        local s = shieldDB()
        local n = (s and s.exclusions) and #s.exclusions or 0
        if state.exclusionsBtn then
            local lbl = state.exclusionsBtn:GetFontString()
            if lbl then lbl:SetText("exclusions \194\183 " .. n) end
        end
        refreshList()
    end

    local row = state.rowFrames[idx]
    if row and row.pulse then row:pulse() end
end

rowOnClick = function(self)
    local idx = self.lineIdx
    local item = state.displayItems and state.displayItems[idx]
    if not item then return end
    if item.kind == "excl" then
        clickExclusion(item, idx)
    elseif item.kind == "line" then
        clickLine(idx)
    end
    -- Section rows are not clickable.
end

-- Build state.displayItems = list of items to render. Each item is one of:
--   { kind = "section", label, count }
--   { kind = "line",    line, banned, multiBot, spellId }
--   { kind = "excl",    id, name }
local function buildDisplayItems()
    local items = {}
    if state.viewExclusions then
        local s = shieldDB()
        if s and type(s.exclusions) == "table" then
            for _, e in ipairs(s.exclusions) do
                table.insert(items, { kind = "excl", id = e.id, name = e.name })
            end
        end
        return items
    end

    -- Precompute banned set for O(1) per-line lookup.
    local banned = {}
    local s = shieldDB()
    if s and type(s.exclusions) == "table" then
        for _, e in ipairs(s.exclusions) do
            if e.id then banned[e.id] = true end
        end
    end
    state.bannedSet = banned

    -- Multi-bot detection
    local seenFrom = {}
    for _, line in ipairs(state.lines) do
        if line.from and line.from ~= "" then seenFrom[line.from] = true end
    end
    local distinctBots = 0
    for _ in pairs(seenFrom) do distinctBots = distinctBots + 1 end
    state.multiBot = distinctBots > 1

    local bypassHideGray = (state.actionMode == "ban" or state.actionMode == "unban")
    local filter = (state.filter and state.filter ~= "") and state.filter:lower() or nil

    -- Filter pass — drop separator lines, hide-gray, filter text mismatch.
    local kept = {}
    for _, line in ipairs(state.lines) do
        local payload = line.payload or ""
        if payload ~= "" and not isSeparator(payload) then
            local skip = false
            if state.hideGray and not bypassHideGray then
                local rank = extractRank(line.raw or "")
                if rank == "808080" then skip = true end
            end
            if not skip and filter then
                if not payload:lower():find(filter, 1, true) then skip = true end
            end
            if not skip then
                table.insert(kept, line)
            end
        end
    end

    -- Group by section (line.mode), preserve first-seen order, sort alpha within.
    local groups = {}
    local order  = {}
    for _, line in ipairs(kept) do
        local secKey = line.mode or "other"
        if not groups[secKey] then
            groups[secKey] = {}
            table.insert(order, secKey)
        end
        table.insert(groups[secKey], line)
    end
    for _, lines in pairs(groups) do
        table.sort(lines, function(a, b)
            return ((a.payload or ""):lower()) < ((b.payload or ""):lower())
        end)
    end

    for _, secKey in ipairs(order) do
        local glines = groups[secKey]
        table.insert(items, {
            kind  = "section",
            label = sectionLabel(secKey),
            count = #glines,
        })
        for _, line in ipairs(glines) do
            local spellId = extractSpellId(line.raw or "")
            table.insert(items, {
                kind     = "line",
                line     = line,
                banned   = (spellId and banned[spellId]) and true or false,
                multiBot = state.multiBot,
                spellId  = spellId,
            })
        end
    end

    return items
end

-- Layout the row pool. Each row's height is set per-render based on its kind.
refreshList = function()
    local parent = state.scrollChild
    if not parent then return end
    state.displayItems = buildDisplayItems()
    local items = state.displayItems
    local y = -2
    local rendered = 0
    for i, item in ipairs(items) do
        local row = ensureRow(i, parent)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   2, y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, y)
        row:SetScript("OnUpdate", nil)
        row:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
        row.dot:Hide()
        row.botTag:Hide()
        row.secRule:Hide()
        row.secCount:Hide()
        row.fs:ClearAllPoints()
        row.fs:SetPoint("LEFT",  row, "LEFT",   6, 0)
        row.fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)

        if item.kind == "section" then
            row:SetHeight(SECTION_HDR_H)
            row:SetBackdropColor(0, 0, 0, 0)
            row:SetBackdropBorderColor(0, 0, 0, 0)
            row:EnableMouse(false)
            -- fs grows to text width (anchor LEFT only) so secRule can fill the gap
            row.fs:ClearAllPoints()
            row.fs:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.fs:SetText(string.upper(item.label or "?"))
            row.fs:SetTextColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
            row.fs:SetJustifyH("LEFT")
            -- Hairline rule between section label and the count
            row.secRule:ClearAllPoints()
            row.secRule:SetPoint("LEFT",  row.fs, "RIGHT", 6, 0)
            row.secRule:SetPoint("RIGHT", row, "RIGHT", -32, 0)
            row.secRule:SetHeight(1)
            row.secRule:Show()
            row.secCount:SetText(tostring(item.count or 0))
            row.secCount:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
            row.secCount:Show()
            row.lineIdx = i
            row:Show()
            y = y - (SECTION_HDR_H + 2)
            rendered = rendered + 1

        elseif item.kind == "excl" then
            row:SetHeight(ROW_H)
            row:SetBackdropColor(0.10, 0.08, 0.05, 1)
            row:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
            row:EnableMouse(true)
            row.dot:Show()
            row.fs:ClearAllPoints()
            row.fs:SetPoint("LEFT",  row, "LEFT",  16, 0)
            row.fs:SetPoint("RIGHT", row, "RIGHT", -52, 0)
            row.fs:SetText(item.name or "?")
            row.fs:SetTextColor(INK_RED[1], INK_RED[2], INK_RED[3], 1)
            row.botTag:SetText(string.format("id %d", item.id or 0))
            row.botTag:SetTextColor(0.45, 0.40, 0.32, 1)
            row.botTag:Show()
            row.lineIdx = i
            row:Show()
            y = y - (ROW_H + 2)
            rendered = rendered + 1

        else  -- "line"
            row:SetHeight(ROW_H)
            row:SetBackdropColor(0.10, 0.08, 0.05, 1)
            row:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
            row:EnableMouse(true)
            local line = item.line
            local raw = line.raw or ""
            -- Pre-compute fs RIGHT anchor: shorter when multiBot tag is visible
            local leftPad  = item.banned and 16 or 6
            local rightPad = (item.multiBot and line.from) and -64 or -6
            row.fs:ClearAllPoints()
            row.fs:SetPoint("LEFT",  row, "LEFT",  leftPad, 0)
            row.fs:SetPoint("RIGHT", row, "RIGHT", rightPad, 0)
            if item.banned then
                row.dot:Show()
                local payload = line.payload or trim(raw)
                row.fs:SetText("|cff6a4a45" .. payload .. "|r")
                row.fs:SetTextColor(0.42, 0.29, 0.27, 1)
            else
                row.fs:SetText(raw)
                row.fs:SetTextColor(TEXT_WARM[1], TEXT_WARM[2], TEXT_WARM[3], 1)
            end
            if item.multiBot and line.from then
                row.botTag:SetText(line.from)
                row.botTag:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
                row.botTag:Show()
            end
            row.lineIdx = i
            row:Show()
            y = y - (ROW_H + 2)
            rendered = rendered + 1
        end
    end
    -- Hide unused pool rows
    for i = rendered + 1, #state.rowFrames do
        local r = state.rowFrames[i]
        if r then r:Hide() end
    end
    parent:SetHeight(math.max(LIST_H, -y + 4))

    -- Sync the exclusions counter button (cheap, keeps footer fresh).
    if state.exclusionsBtn then
        local lbl = state.exclusionsBtn:GetFontString()
        local s = shieldDB()
        local n = (s and s.exclusions) and #s.exclusions or 0
        if lbl then lbl:SetText("exclusions \194\183 " .. n) end
    end

    -- Conditional filter row visibility — only show when we have enough
    -- items that filtering helps.
    if state.filterRow then
        if (rendered > FILTER_THRESHOLD) or (state.filter and state.filter ~= "") then
            state.filterRow:Show()
        else
            state.filterRow:Hide()
        end
    end

    refreshStatus()
    refreshBanner()
    if layout then layout() end
end

refreshAll = function()
    refreshTargetLine()
    refreshActionMode()
    refreshList()
    refreshLockGlyph()
end

-- ----------------------------------------------------------
-- Whisper capture
-- ----------------------------------------------------------
local listenerFrame
local function ensureListener()
    if state.listenerArmed then return end
    if not listenerFrame then
        listenerFrame = CreateFrame("Frame", "WardenShieldListener")
    end
    listenerFrame:RegisterEvent("CHAT_MSG_WHISPER")
    listenerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    listenerFrame:SetScript("OnEvent", function(_, event, text, sender)
        if event == "PLAYER_TARGET_CHANGED" then
            if state.actionMode ~= "caston" then return end
            if not UnitExists("target") then return end
            local name = UnitName("target")
            if not name or name == "" then return end
            local _, cls = UnitClass("target")
            state.castOnTarget = name
            state.castOnClass  = cls
            refreshActionMode()
            if ns.DebugF then
                ns.DebugF("shield", "caston target captured: %s", name)
            end
            return
        end
        if event ~= "CHAT_MSG_WHISPER" then return end
        if state.captureUntil == 0 or GetTime() > state.captureUntil then return end
        if not state.target or sender ~= state.target then
            if ns.DebugF then
                ns.DebugF("shield", "whisper drop: from=%q expected=%q",
                    tostring(sender), tostring(state.target))
            end
            return
        end
        if #state.lines >= MAX_LINES then
            table.remove(state.lines, 1)
        end
        table.insert(state.lines, {
            raw     = text or "",
            payload = extractPayload(text),
            ts      = GetTime(),
            from    = state.target,
            mode    = state.mode,
        })
        if ns.DebugF then
            ns.DebugF("shield", "whisper kept: from=%s len=%d payload=%q",
                sender, #(text or ""), tostring(state.lines[#state.lines].payload))
        end
        refreshList()
    end)
    state.listenerArmed = true
end

-- 0.2 s ticker that just repaints the countdown banner. Self-disarms when
-- the capture window closes; re-armed by startCapture().
local countdownFrame
local function armCountdown()
    if not countdownFrame then
        countdownFrame = CreateFrame("Frame", "WardenShieldCountdown")
    end
    countdownFrame._accum = 0
    countdownFrame:SetScript("OnUpdate", function(self, elapsed)
        self._accum = (self._accum or 0) + elapsed
        if self._accum < 0.2 then return end
        self._accum = 0
        if state.captureUntil == 0 or GetTime() > state.captureUntil then
            state.captureUntil = 0
            self:SetScript("OnUpdate", nil)
            if ns.DebugF then
                ns.DebugF("shield", "capture closed (%d lines)", #state.lines)
            end
            refreshStatus()
            refreshBanner()
            return
        end
        refreshBanner()
    end)
end

local function snapshotTarget()
    if not (UnitExists("target") and UnitIsPlayer("target")) then
        ns.MsgErr("Target a player/bot first.")
        return nil
    end
    if UnitIsUnit("target", "player") then
        ns.MsgErr("Can't run discovery on yourself.")
        return nil
    end
    local name = UnitName("target")
    if not name or name == "" then
        ns.MsgErr("Target has no resolvable name.")
        return nil
    end
    if ns.Persistence and ns.Persistence.IsPlayerName
       and ns.Persistence.IsPlayerName(name) then
        ns.MsgWarn(name .. " is flagged as a human player - skipping.")
        return nil
    end
    local _, classTok = UnitClass("target")
    return name, classTok
end

local function startCapture(mode)
    local name, classTok = state.target, state.targetClass
    if not name or name == "" then
        name, classTok = snapshotTarget()
        if not name then return end
    elseif ns.Persistence and ns.Persistence.IsPlayerName
           and ns.Persistence.IsPlayerName(name) then
        ns.MsgWarn(name .. " is flagged as a human player - skipping.")
        return
    end

    local sec = (shieldDB() and tonumber(shieldDB().captureSec)) or 5
    if sec < 1 then sec = 1 end
    if sec > 60 then sec = 60 end

    state.target       = name
    state.targetClass  = classTok
    state.mode         = mode
    state.captureUntil = GetTime() + sec
    -- New capture wipes the filter so old text doesn't hide all the new lines.
    if state.filterBox then
        state.filterBox:SetText("")
    end
    state.filter = ""
    wipe(state.lines)
    if ns.DebugF then
        ns.DebugF("shield", "snapshot target=%s class=%s mode=%s deadline=+%.1fs",
            name, tostring(classTok), tostring(mode), sec)
    end

    ensureListener()
    armCountdown()
    SendChatMessage(mode, "WHISPER", nil, name)
    ns.MsgInfo(string.format("`%s` -> %s (listening %ds)", mode, name, sec))
    refreshAll()
end

-- ----------------------------------------------------------
-- Frame build
-- ----------------------------------------------------------
local function applyPosition()
    if not state.frame then return end
    local s = shieldDB()
    state.frame:ClearAllPoints()
    if s and s.pos and type(s.pos) == "table" and s.pos.point then
        state.frame:SetPoint(s.pos.point, UIParent, s.pos.point,
            s.pos.x or 0, s.pos.y or 0)
    else
        state.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -380)
    end
end

local function storePosition()
    if not state.frame then return end
    local s = shieldDB(); if not s then return end
    local point, _, _, x, y = state.frame:GetPoint(1)
    if point then s.pos = { point = point, x = x, y = y } end
end

-- Layout pass: re-anchor the action row, mode row, conditional widgets, and
-- list so the frame collapses around hidden widgets. Called every refreshList.
layout = function()
    local f = state.frame
    if not f then return end

    -- Top stack: header, banner (if shown), target, action, mode
    local y = HEADER_H
    if state.bannerArmed and state.bannerArmed:IsShown() then
        state.bannerArmed:ClearAllPoints()
        state.bannerArmed:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
        state.bannerArmed:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        y = y + BANNER_H
    end

    if state._targetRow then
        state._targetRow:ClearAllPoints()
        state._targetRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
        state._targetRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        y = y + TARGET_H
    end
    if state._targetRule then
        state._targetRule:ClearAllPoints()
        state._targetRule:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -y)
        state._targetRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
        state._targetRule:SetHeight(1)
        y = y + 2
    end
    if state._actRow then
        state._actRow:ClearAllPoints()
        state._actRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y - 2)
        state._actRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y - 2)
        y = y + ACTION_H + 2
    end
    if state.segMode then
        state.segMode:ClearAllPoints()
        state.segMode:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -(y + 4))
        state.segMode:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 4))
        state.segMode:SetHeight(MODE_H)
        if state.segMode._layout then state.segMode._layout() end
        y = y + MODE_H + 4
    end

    -- Cast-on chip (conditional)
    if state.castOnChip and state.castOnChip:IsShown() then
        state.castOnChip:ClearAllPoints()
        state.castOnChip:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -(y + 4))
        state.castOnChip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 4))
        state.castOnChip:SetHeight(CAST_ON_H - 4)
        y = y + CAST_ON_H
    end

    -- Filter row (conditional)
    if state.filterRow and state.filterRow:IsShown() then
        state.filterRow:ClearAllPoints()
        state.filterRow:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -(y + 4))
        state.filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 4))
        state.filterRow:SetHeight(FILTER_H)
        y = y + FILTER_H + 4
    end

    -- Status row when banner is hidden
    if state.statusRow then
        if state.bannerArmed and state.bannerArmed:IsShown() then
            state.statusRow:Hide()
        else
            state.statusRow:Show()
            state.statusRow:ClearAllPoints()
            state.statusRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -(y + 2))
            state.statusRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(y + 2))
            y = y + STATUS_H + 2
        end
    end

    -- Scroll frame fills remaining space above the footer
    if state.scrollFrame then
        state.scrollFrame:ClearAllPoints()
        state.scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT", PAD, -(y + 2))
        state.scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 12), FOOTER_H + PAD + 2)
    end
end

local function build()
    if state.frame then return state.frame end
    state.shieldDB = shieldDB()

    -- Fixed height computed assuming the maximum stack (banner + cast-on +
    -- filter all visible). Conditional widgets collapse via layout() but the
    -- frame keeps its shape so dragging doesn't make it jump.
    local maxH = HEADER_H + BANNER_H + TARGET_H + 2 + ACTION_H + 4 + MODE_H + 4
               + CAST_ON_H + FILTER_H + 4 + LIST_H + FOOTER_H + PAD * 2 + 8

    local f = CreateFrame("Frame", "WardenShieldFrame", UIParent)
    f:SetSize(FRAME_W, maxH)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile     = true, tileSize = 16,
        edgeSize = 1,
    })
    f:SetBackdropColor(STONE_DARK[1], STONE_DARK[2], STONE_DARK[3], 1.00)
    f:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local s = shieldDB()
        if s and s.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        storePosition()
    end)

    f.header = buildHeader(f)
    state.frame = f

    -- Armed banner (conditional, sits under the header)
    local banner = ns.UI.Banner.Create(f, "amber")
    banner:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -HEADER_H)
    banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)
    banner:Hide()
    state.bannerArmed = banner

    -- Target anchor row (2 lines, 32px)
    local targetRow = CreateFrame("Frame", nil, f)
    targetRow:SetHeight(TARGET_H)
    state._targetRow = targetRow

    local tlbl = targetRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tlbl:SetPoint("TOPLEFT", targetRow, "TOPLEFT", PAD, -3)
    tlbl:SetWidth(FRAME_W - PAD * 2 - 56)
    tlbl:SetJustifyH("LEFT")
    tlbl:SetText("|cff808080no target|r")
    state.targetLbl = tlbl

    local tsub = targetRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tsub:SetPoint("TOPLEFT", tlbl, "BOTTOMLEFT", 0, -1)
    tsub:SetWidth(FRAME_W - PAD * 2 - 56)
    tsub:SetJustifyH("LEFT")
    tsub:SetText("TARGET A BOT, THEN CLICK PICK")
    tsub:SetTextColor(0.45, 0.40, 0.32, 1)
    state.targetSub = tsub

    local pick = ns.UI.Button.stone(targetRow, "pick", 48, 18)
    pick:SetPoint("RIGHT", targetRow, "RIGHT", -PAD, 0)
    pick:SetScript("OnClick", function()
        local n, c = snapshotTarget()
        if n then
            state.target      = n
            state.targetClass = c
            ns.MsgInfo("Target locked to " .. n .. ".")
            if ns.DebugF then ns.DebugF("shield", "pick: target=%s", n) end
        end
        refreshTargetLine()
    end)
    state.pickBtn = pick
    ns.UI.Tooltip.Attach(pick, "Pick target",
        "Snapshot UnitName('target') as the bot Shield will whisper to. Click `los` or `spells` afterward to fire a discovery command.",
        "ANCHOR_TOP")

    -- Thin gold-dim rule under target row (visual divider between anchor + actions)
    local targetRule = f:CreateTexture(nil, "ARTWORK")
    targetRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    targetRule:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
    state._targetRule = targetRule

    -- Action row: [los] [spells] ...  [clear]
    local actRow = CreateFrame("Frame", nil, f)
    actRow:SetHeight(ACTION_H)
    state._actRow = actRow

    local btnW = 76
    local los = ns.UI.Button.stone(actRow, "los", btnW, ACTION_H)
    los:SetPoint("LEFT", actRow, "LEFT", PAD, 0)
    los:SetScript("OnClick", function() startCapture("los") end)
    state.losBtn = los
    ns.UI.Tooltip.Attach(los, "los",
        "Whisper `los` to the targeted bot to list nearby objects. Captures the bot's reply for ~5s; click any line to send `u [object]`.",
        "ANCHOR_TOP")

    local spells = ns.UI.Button.stone(actRow, "spells", btnW, ACTION_H)
    spells:SetPoint("LEFT", los, "RIGHT", GAP, 0)
    spells:SetScript("OnClick", function() startCapture("spells") end)
    state.spellsBtn = spells
    ns.UI.Tooltip.Attach(spells, "spells",
        "Whisper `spells` to the targeted bot to list its spells. Captures the bot's reply for ~5s; click any line to send `cast <spell>`.",
        "ANCHOR_TOP")

    local clear = ns.UI.Button.stone(actRow, "clear", 56, ACTION_H)
    clear:SetPoint("RIGHT", actRow, "RIGHT", -PAD, 0)
    clear:SetScript("OnClick", function() ns.Shield.Clear() end)
    state.clearBtn = clear
    ns.UI.Tooltip.Attach(clear, "clear",
        "Wipe the captured list and stop listening. The target stays locked.",
        "ANCHOR_TOP")

    -- Segmented mode control (replaces the 5-button row)
    local segItems = {
        { key = "cast",     label = "cast",
          tooltip = { "Cast",
            "Click any captured spell line to whisper `cast <name>` to its bot. los lines stay `u [obj]`." } },
        { key = "caston",   label = "on Y",
          tooltip = { "Cast on Y",
            "Click any unit frame (raid, party, target) to capture that name as the cast target. Then click a spell line to send `cast <spell> on <name>`." } },
        { key = "selfcast", label = "on me",
          tooltip = { "Cast on me",
            "Click a spell line to whisper `cast <spell> on <YourName>` — lance le sort sur toi-meme." } },
        { key = "ban",      label = "ban",
          tooltip = { "Ban",
            "Click a spell line to whisper `ss +<id>` and add it to the bot's exclude list. hide-gray is bypassed in this mode so you can ban spells the bot can't currently cast." } },
        { key = "unban",    label = "unban",
          tooltip = { "Unban",
            "Click a spell line (or open the exclusions view) to whisper `ss -<id>` and remove it from the bot's exclude list." } },
    }
    local seg = ns.UI.Segmented.Create(f, segItems, function(key)
        state.actionMode = key
        if key ~= "caston" then
            state.castOnTarget = nil
            state.castOnClass  = nil
        end
        refreshActionMode()
        refreshList()
        if ns.DebugF then ns.DebugF("shield", "actionMode=%s", key) end
    end)
    seg:SetActive("cast")
    state.segMode = seg

    -- Cast-on chip (conditional, caston only)
    local chip = CreateFrame("Frame", nil, f)
    chip:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    chip:SetBackdropColor(0.10, 0.08, 0.04, 1)
    chip:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
    chip:EnableMouse(true)
    chip:Hide()
    state.castOnChip = chip

    local chipPrefix = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chipPrefix:SetPoint("LEFT", chip, "LEFT", 10, 0)
    chipPrefix:SetText("")
    chipPrefix:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    chip._lblPrefix = chipPrefix

    local chipName = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chipName:SetPoint("LEFT", chipPrefix, "RIGHT", 8, 0)
    chipName:SetJustifyH("LEFT")
    chipName:Hide()
    chip._lblName = chipName

    local chipHint = chip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    chipHint:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chipHint:SetText("click a unit frame to set cast target")
    chipHint:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
    chip._lblHint = chipHint

    chip:SetScript("OnMouseDown", function()
        -- Click the chip itself to drop the captured target (UX bonus).
        if state.castOnTarget then
            state.castOnTarget = nil
            state.castOnClass  = nil
            refreshActionMode()
        end
    end)
    ns.UI.Tooltip.Attach(chip, "Cast target",
        "Captured cast target for the `on Y` mode. Click any unit frame to set; click this chip to clear.",
        "ANCHOR_TOP")

    -- Filter row (conditional, > FILTER_THRESHOLD items)
    local filterRow = CreateFrame("Frame", nil, f)
    filterRow:Hide()
    state.filterRow = filterRow

    filterRow:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    filterRow:SetBackdropColor(0.04, 0.03, 0.02, 1)
    filterRow:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)

    local filterLbl = filterRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    filterLbl:SetPoint("LEFT", filterRow, "LEFT", 8, 0)
    filterLbl:SetText("filter")

    local filterBox = CreateFrame("EditBox", "WardenShieldFilter", filterRow)
    filterBox:SetPoint("LEFT", filterLbl, "RIGHT", 6, 0)
    filterBox:SetPoint("RIGHT", filterRow, "RIGHT", -6, 0)
    filterBox:SetHeight(FILTER_H - 2)
    filterBox:SetAutoFocus(false)
    filterBox:SetMaxLetters(64)
    filterBox:SetFontObject("GameFontHighlightSmall")
    filterBox:SetTextInsets(2, 2, 0, 0)
    filterBox:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
    filterBox:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
    filterBox:SetScript("OnTextChanged",   function(s)
        state.filter = s:GetText() or ""
        refreshList()
    end)
    state.filterBox = filterBox

    -- Status strip (only shown when not capturing)
    local statusRow = CreateFrame("Frame", nil, f)
    statusRow:SetHeight(STATUS_H)
    state.statusRow = statusRow

    local statusBlip = statusRow:CreateTexture(nil, "ARTWORK")
    statusBlip:SetTexture("Interface\\Buttons\\WHITE8x8")
    statusBlip:SetSize(6, 6)
    statusBlip:SetPoint("LEFT", statusRow, "LEFT", PAD, 0)
    statusBlip:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
    state.statusBlip = statusBlip

    local slbl = statusRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    slbl:SetPoint("LEFT", statusBlip, "RIGHT", 6, 0)
    slbl:SetText("idle")
    state.statusLbl = slbl

    -- Footer row (uniform 22px now)
    local footerRow = CreateFrame("Frame", nil, f)
    footerRow:SetHeight(FOOTER_H)
    footerRow:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, PAD)
    footerRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, PAD)

    local hideGray = ns.UI.Button.stone(footerRow, "hide gray", 64, FOOTER_H)
    hideGray:SetPoint("LEFT", footerRow, "LEFT", PAD, 0)
    hideGray:SetScript("OnClick", function()
        state.hideGray = not state.hideGray
        if state.hideGray then
            hideGray:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
            local lbl = hideGray:GetFontString()
            if lbl then lbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        else
            hideGray:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
            local lbl = hideGray:GetFontString()
            if lbl then lbl:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1) end
        end
        refreshList()
    end)
    state.hideGrayBtn = hideGray
    ns.UI.Tooltip.Attach(hideGray, "Hide gray spells",
        "Filter out spells whose rank suffix is gray (the bot can't currently use them - level/talent gated). Bypassed in ban / unban modes.",
        "ANCHOR_TOP")

    local viewExcl = ns.UI.Button.stone(footerRow, "exclusions \194\183 0", 100, FOOTER_H)
    viewExcl:SetPoint("LEFT", hideGray, "RIGHT", 4, 0)
    viewExcl:SetScript("OnClick", function()
        state.viewExclusions = not state.viewExclusions
        if state.viewExclusions then
            viewExcl:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
            local lbl = viewExcl:GetFontString()
            if lbl then lbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        else
            viewExcl:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
            local lbl = viewExcl:GetFontString()
            if lbl then lbl:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1) end
        end
        refreshList()
    end)
    state.exclusionsBtn = viewExcl
    ns.UI.Tooltip.Attach(viewExcl, "View / hide exclusions",
        "Toggle the scroll list between captured whispers and the persisted exclusions list. Click an exclusion row to whisper `ss -<id>` and remove it.",
        "ANCHOR_TOP")

    local resetAll = ns.UI.Button.warn(footerRow, "reset all", 64, FOOTER_H)
    resetAll:SetPoint("RIGHT", footerRow, "RIGHT", -PAD, 0)
    resetAll:SetScript("OnClick", function()
        if not state.target or state.target == "" then
            ns.MsgWarn("No target locked - click [pick] first.")
            return
        end
        SendChatMessage("ss reset", "WHISPER", nil, state.target)
        local s = shieldDB()
        if s then s.exclusions = {} end
        ns.MsgInfo("Sent `ss reset` to " .. state.target .. ". Local exclusions wiped.")
        refreshList()
    end)
    ns.UI.Tooltip.Attach(resetAll, "Reset all exclusions",
        "Whisper `ss reset` to the locked bot, clearing its exclude-spells list. Also wipes our local mirror in WardenDB.shield.exclusions.",
        "ANCHOR_TOP")

    -- Scroll frame (anchored dynamically by layout())
    local sf = CreateFrame("ScrollFrame", "WardenShieldScroll", f, "UIPanelScrollFrameTemplate")
    state.scrollFrame = sf

    local sb = _G["WardenShieldScrollScrollBar"]
    if sb then
        -- 3.3.5a doesn't expose .ScrollUpButton/.ScrollDownButton as fields;
        -- the templated children only exist as globals with the full name.
        local upBtn   = sb.ScrollUpButton   or _G["WardenShieldScrollScrollBarScrollUpButton"]
        local downBtn = sb.ScrollDownButton or _G["WardenShieldScrollScrollBarScrollDownButton"]
        if upBtn   then upBtn:Hide()   end
        if downBtn then downBtn:Hide() end
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT", 2, 0)
        sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 0)
        sb:SetWidth(8)
    end

    local child = CreateFrame("Frame", "WardenShieldScrollChild", sf)
    child:SetSize(FRAME_W - PAD * 2 - 18, LIST_H)
    sf:SetScrollChild(child)
    state.scrollChild = child

    -- 0.5s ticker keeps the live target label fresh.
    f._heartbeat = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self._heartbeat = (self._heartbeat or 0) + elapsed
        if self._heartbeat < 0.5 then return end
        self._heartbeat = 0
        refreshTargetLine()
    end)

    applyPosition()
    refreshAll()
    return f
end

-- ----------------------------------------------------------
-- Public API
-- ----------------------------------------------------------
function ns.Shield.Frame() return state.frame end

function ns.Shield.Show()
    if not state.frame then build() end
    state.frame:Show()
    local s = shieldDB(); if s then s.hidden = false end
    if ns.Debug then ns.Debug("shield", "Show") end
end

function ns.Shield.Hide()
    if not state.frame then return end
    state.frame:Hide()
    local s = shieldDB(); if s then s.hidden = true end
    if ns.Debug then ns.Debug("shield", "Hide") end
end

function ns.Shield.Toggle()
    if not state.frame then build() end
    if state.frame:IsShown() then ns.Shield.Hide() else ns.Shield.Show() end
end

function ns.Shield.SetLocked(v)
    local s = shieldDB(); if not s then return end
    s.locked = v and true or false
    refreshLockGlyph()
end

function ns.Shield.ToggleLock()
    local s = shieldDB(); if not s then return end
    ns.Shield.SetLocked(not s.locked)
end

function ns.Shield.ResetPosition()
    local s = shieldDB(); if s then s.pos = nil end
    applyPosition()
end

function ns.Shield.Clear()
    state.mode         = nil
    state.captureUntil = 0
    state.target       = nil
    state.targetClass  = nil
    state.castOnTarget = nil
    state.castOnClass  = nil
    state.filter       = ""
    if state.filterBox then state.filterBox:SetText("") end
    wipe(state.lines)
    refreshAll()
    ns.MsgInfo("Shield: list cleared (target unlocked).")
    if ns.Debug then ns.Debug("shield", "Clear (full reset)") end
end

function ns.Shield.PrintHelp()
    ns.MsgInfo("WardenShield commands:")
    local rows = {
        { "/wsh",            "toggle the HUD" },
        { "/wsh show|hide",  "explicit show / hide" },
        { "/wsh lock|unlock","lock or unlock position" },
        { "/wsh reset",      "reset position" },
        { "/wsh clear",      "wipe captured list" },
        { "/wsh los",        "send `los` to the current target" },
        { "/wsh spells",     "send `spells` to the current target" },
        { "/wsh help",       "this list" },
    }
    for _, r in ipairs(rows) do
        ns.MsgInfo(string.format("  %s%s|r  %s", ns.Colors.key, r[1], r[2]))
    end
end

-- ----------------------------------------------------------
-- Slash
-- ----------------------------------------------------------
SLASH_WARDENSHIELD1 = "/wsh"
SLASH_WARDENSHIELD2 = "/wardenshield"
SlashCmdList["WARDENSHIELD"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if ns.DebugF then ns.DebugF("slash", "/wsh %q", msg) end
    if msg == ""        then ns.Shield.Toggle();        return end
    if msg == "show"    then ns.Shield.Show();          return end
    if msg == "hide"    then ns.Shield.Hide();          return end
    if msg == "toggle"  then ns.Shield.Toggle();        return end
    if msg == "lock"    then ns.Shield.SetLocked(true); return end
    if msg == "unlock"  then ns.Shield.SetLocked(false);return end
    if msg == "reset"   then ns.Shield.ResetPosition(); return end
    if msg == "clear"   then ns.Shield.Clear();         return end
    if msg == "los"     then startCapture("los");       return end
    if msg == "spells"  then startCapture("spells");    return end
    if msg == "help"    then ns.Shield.PrintHelp();     return end
    ns.Shield.PrintHelp()
end

-- ----------------------------------------------------------
-- Bindings glue
-- ----------------------------------------------------------
function WARDENSHIELD_Toggle() ns.Shield.Toggle() end

BINDING_HEADER_WARDENSHIELD      = "WardenShield"
BINDING_NAME_WARDENSHIELD_TOGGLE = "Toggle WardenShield HUD"

-- ----------------------------------------------------------
-- Bootstrap
-- ----------------------------------------------------------
ns.Persistence.OnReady(function()
    build()
    local s = shieldDB()
    if s and s.hidden then state.frame:Hide() else state.frame:Show() end
    ensureListener()
    if ns.DebugF then
        ns.DebugF("shield", "ready: hidden=%s locked=%s",
            s and tostring(s.hidden) or "?", s and tostring(s.locked) or "?")
    end
end)

-- =====================================================
-- Warden - Core.lua
-- Master command center for Warstorm 3.3.5a.
-- =====================================================

local addonName, ns = ...

-- Shim retail-only globals some 3rd-party libs (e.g. Scrap) reference, so
-- we don't crash every dropdown opened while Warden is loaded.
if type(_G.TextureLoadingGroupMixin) ~= "table" then
    _G.TextureLoadingGroupMixin = {
        RemoveTexture = function(e, k)
            if e and type(e.textures) == "table" and k ~= nil then
                e.textures[k] = nil
            end
        end,
    }
end

-- Shared namespace
ns.Data        = ns.Data        or {}
ns.Persistence = ns.Persistence or {}
ns.Engine      = ns.Engine      or {}
ns.UI          = ns.UI          or {}
ns.UI.Tabs     = ns.UI.Tabs     or {}

-- Chat color codes. Only the entries below have live call sites; previous
-- schema had `header`/`cyan` that nothing referenced.
ns.Colors = {
    key    = "|cff88ff88",
    info   = "|cff00ff00",
    warn   = "|cffffaa00",
    err    = "|cffff0000",
    reset  = "|r",
}

-- ----------------------------------------------------------
-- Class color helpers
-- ----------------------------------------------------------
function ns.ClassColorHex(classToken)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if not c then return "ffffff" end
    return string.format("%02x%02x%02x",
        math.floor((c.r or 1) * 255 + 0.5),
        math.floor((c.g or 1) * 255 + 0.5),
        math.floor((c.b or 1) * 255 + 0.5))
end

function ns.ColorClass(classToken, text)
    return "|cff" .. ns.ClassColorHex(classToken) .. (text or "") .. "|r"
end

-- ----------------------------------------------------------
-- Chat helpers
-- ----------------------------------------------------------
local function prefix(color, body)
    return color .. "[Warden]" .. ns.Colors.reset .. " " .. body
end

function ns.MsgInfo(body) DEFAULT_CHAT_FRAME:AddMessage(prefix(ns.Colors.info, body)) end
function ns.MsgWarn(body) DEFAULT_CHAT_FRAME:AddMessage(prefix(ns.Colors.warn, body)) end
function ns.MsgErr(body)  DEFAULT_CHAT_FRAME:AddMessage(prefix(ns.Colors.err,  body)) end

function ns.Channel()
    -- Honor DB override, clamped to the two channels the bot parser accepts.
    local db = ns.Persistence and ns.Persistence.DB
    local override = db and db.commandChannel
    if override == "RAID" or override == "PARTY" then return override end
    return (GetNumRaidMembers() > 0) and "RAID" or "PARTY"
end

-- Broadcast one chat message to the current RAID/PARTY (or SAY when solo).
-- Every caller in the addon should use this instead of raw SendChatMessage,
-- so a future throttling/routing change only touches one site.
function ns.Broadcast(msg)
    if not msg or msg == "" then return end
    SendChatMessage(msg, ns.Channel())
end

-- All targeting now routes through SecureActionButton macrotext (/target),
-- so an insecure helper no longer has a use case - removed.

-- Whisper `cmd` to every raid/party member matching `classToken`.
-- Used for per-class strategy toggles (e.g. `nc -bloodlust` only to shamans)
-- because the generic RAID/PARTY broadcast doesn't reliably flip the strategy.
function ns.WhisperClass(classToken, cmd)
    local units = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumPartyMembers() do units[#units + 1] = "party" .. i end
    end
    local count = 0
    for _, u in ipairs(units) do
        if UnitExists(u) and UnitIsPlayer(u) and not UnitIsUnit(u, "player") then
            local _, cls = UnitClass(u)
            if cls == classToken then
                local name = UnitName(u)
                if name then
                    SendChatMessage(cmd, "WHISPER", nil, name)
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- ----------------------------------------------------------
-- UI style helpers (Direction I "refined stone frame" vocabulary)
-- ----------------------------------------------------------
ns.UI.Button = ns.UI.Button or {}
ns.UI.Panel  = ns.UI.Panel  or {}

local _btnCounter = 0
local function _nextBtnName()
    _btnCounter = _btnCounter + 1
    return "WardenBtn" .. _btnCounter
end

-- =====================================================================
-- v2.1 token palette (locked - see design-handoff/README.md).
-- Hex helper keeps every color definition readable at the call site.
-- =====================================================================
local function _hex(h)
    return
        tonumber(string.sub(h, 1, 2), 16) / 255,
        tonumber(string.sub(h, 3, 4), 16) / 255,
        tonumber(string.sub(h, 5, 6), 16) / 255
end

ns.Tokens = {
    stone_dark = { _hex("0e0b08") },
    stone_mid  = { _hex("1a140d") },
    stone_tile = { _hex("2a2016") },
    stone_rim  = { _hex("3a2f22") },
    gold       = { _hex("ffd100") },
    gold_dim   = { _hex("b89536") },
    gold_rim   = { _hex("a88a4c") },
    red_btn    = { _hex("7a1a15") },
    red_btn_hi = { _hex("b92b22") },
    ink_red    = { _hex("e04a3a") },
    green      = { _hex("2ecc40") },
    amber      = { _hex("ff9a00") },
    text_warm  = { _hex("ffebbf") }, -- off-white for red-btn labels
}

-- =====================================================================
-- Button factory rewrite (v2.1): abandon UIPanelButtonTemplate entirely
-- because its built-in red-brown slice textures bled through every vertex
-- tint we tried. Instead we build plain Buttons with a custom backdrop,
-- paint the bg / rim / label from the token palette, and wire our own
-- hover + Enable/Disable state so all existing call sites keep working.
--
-- Three tiers visible to users:
--   stone  = neutral default         (stone-tile bg, stone-rim edge, gold-dim text)
--   gold   = emphasis / toggle-on    (stone-tile bg, gold-rim edge, gold text)
--   red    = primary commitment      (red-btn bg, red-btn edge, warm-white text)
-- Plus a warn specialization:
--   warn   = destructive + StaticPopup (stone-tile bg, stone-rim edge, ink-red text)
-- =====================================================================
local function _makeBtn(parent, text, w, h, opts)
    local b = CreateFrame("Button", _nextBtnName(), parent)
    b:SetSize(w or 80, h or 22)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp")

    b:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local bg, rim, lbl = opts.bg, opts.rim, opts.label
    b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    b:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)

    local fs = b:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormalSmall")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText(text or "")
    fs:SetTextColor(lbl[1], lbl[2], lbl[3], 1)
    b:SetFontString(fs)

    -- Hover effect via SetHighlightTexture so callers can still install
    -- their own OnEnter/OnLeave scripts (addTooltip, etc) without clobbering
    -- our visual state. ADD-blend white overlay at low alpha lifts the bg
    -- and rim by roughly the same amount our token palette specifies.
    local hi = b:CreateTexture(nil, "HIGHLIGHT")
    hi:SetTexture("Interface\\Buttons\\WHITE8x8")
    hi:SetAllPoints(b)
    hi:SetBlendMode("ADD")
    hi:SetVertexColor(1, 1, 1, opts.hoverAlpha or 0.10)
    b:SetHighlightTexture(hi)

    b._tokLbl  = lbl
    b._enabled = true

    -- Preserve Enable / Disable / IsEnabled semantics for callers that
    -- disable the button (Roster "you" row, summary Build on empty grid).
    b.Enable = function(self)
        self._enabled = true
        self:EnableMouse(true)
        local l = self._tokLbl
        local t = self:GetFontString()
        if t then t:SetTextColor(l[1], l[2], l[3], 1) end
        self:SetAlpha(1)
    end
    b.Disable = function(self)
        self._enabled = false
        self:EnableMouse(false)
        local l = self._tokLbl
        local t = self:GetFontString()
        if t then t:SetTextColor(l[1] * 0.4, l[2] * 0.4, l[3] * 0.4, 1) end
        self:SetAlpha(0.7)
    end
    b.IsEnabled = function(self) return self._enabled end

    return b
end

local TOK = ns.Tokens

-- Stone = neutral default (Follow/Stay/save/load/Refresh/dropdowns/etc).
function ns.UI.Button.stone(parent, text, w, h)
    return _makeBtn(parent, text, w, h, {
        bg = TOK.stone_tile, rim = TOK.stone_rim, label = TOK.gold_dim,
        hoverAlpha = 0.08,
    })
end

-- Red = primary commitment (Summon, Build, Reset AI, Atk in role matrix).
function ns.UI.Button.red(parent, text, w, h)
    return _makeBtn(parent, text, w, h, {
        bg = TOK.red_btn, rim = TOK.red_btn, label = TOK.text_warm,
        hoverAlpha = 0.18,
    })
end

-- Gold = emphasis / toggle-on (active grid/table toggle, etc).
function ns.UI.Button.gold(parent, text, w, h)
    return _makeBtn(parent, text, w, h, {
        bg = TOK.stone_tile, rim = TOK.gold_rim, label = TOK.gold,
        hoverAlpha = 0.10,
    })
end

-- Warn = destructive (Cleanup, Hard ReSpec) with optional StaticPopup confirm.
function ns.UI.Button.warn(parent, text, w, h, popupKey)
    local b = _makeBtn(parent, text, w, h, {
        bg = TOK.stone_tile, rim = TOK.stone_rim, label = TOK.ink_red,
        hoverAlpha = 0.08,
    })
    if popupKey then
        b:SetScript("OnClick", function() StaticPopup_Show(popupKey) end)
    end
    return b
end

-- =====================================================================
-- Dropdown styling (v6 - nuclear rewrite).
--
-- Round-5 history: we spent four iterations trying to hide Blizzard's
-- Left/Middle/Right chrome and overlay our own dark-brown backdrop with a
-- custom chevron. Every variation worked in flat containers (Controls tab)
-- but failed in nested ScrollFrame children (Slot Detail, Roster rows) -
-- either the overlay covered the Text FontString, the arrow disappeared,
-- or the template's internal re-anchoring (done by UIDropDownMenu_SetText)
-- undid our layout work silently.
--
-- Round 6 strategy: stop fighting the template. Leave the native chrome
-- VISIBLE and the native Text / arrow anchors UNTOUCHED. Just TINT the
-- chrome textures (gold_dim rim, stone middle) and recolor the Text to
-- bright gold. This keeps the template's layout 100% intact, so it works
-- everywhere - Controls tab, Slot Detail inside a ScrollFrame, and Roster
-- rows - without depth-specific quirks.
-- =====================================================================
ns.UI.Dropdown = ns.UI.Dropdown or {}
function ns.UI.Dropdown.style(drop, width)
    local name = drop:GetName()
    if width and UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(drop, math.max(40, width))
    end
    if not name then return drop end

    -- If a previous call created a sibling backdrop, nuke it - the new
    -- approach doesn't use one, and a leftover bg from the old code path
    -- would still paint over the template.
    if drop._wardenBg then
        drop._wardenBg:Hide()
        drop._wardenBg:ClearAllPoints()
        drop._wardenBg = nil
    end

    local STONE = ns.Tokens.stone_tile
    local RIM   = ns.Tokens.gold_dim
    local GOLD  = ns.Tokens.gold

    -- Re-show and tint the native chrome (was hidden by v5).
    local mid = _G[name .. "Middle"]
    if mid then
        mid:Show(); mid:SetAlpha(1)
        mid:SetVertexColor(STONE[1] * 1.3, STONE[2] * 1.3, STONE[3] * 1.3, 1)
    end
    for _, suffix in ipairs({ "Left", "Right" }) do
        local tex = _G[name .. suffix]
        if tex then
            tex:Show(); tex:SetAlpha(1)
            tex:SetVertexColor(RIM[1], RIM[2], RIM[3], 1)
        end
    end

    -- Arrow button - keep native textures + layout. Just tint them so the
    -- chevron reads as gold over our stone middle.
    local arrow = _G[name .. "Button"]
    if arrow then
        for _, fn in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
            local t = arrow[fn] and arrow[fn](arrow)
            if t then t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end
        end
    end

    -- Selected-value label - leave anchors alone (the template resets them
    -- on every UIDropDownMenu_SetText call anyway). Just bump to bright gold.
    local txt = _G[name .. "Text"]
    if txt then
        txt:SetTextColor(1.00, 0.82, 0.00, 1)
    end

    return drop
end

-- =====================================================================
-- Stone backdrop helper. The { bgFile=WHITE8x8, edgeFile=WHITE8x8,
-- edgeSize=1 } recipe was open-coded 20+ times across tabs. One call site
-- now.
-- =====================================================================
ns.UI.Panel = ns.UI.Panel or {}
function ns.UI.Panel.ApplyStoneBackdrop(frame, bgTok, rimTok, bgAlpha)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    bgTok  = bgTok  or ns.Tokens.stone_tile
    rimTok = rimTok or ns.Tokens.stone_rim
    frame:SetBackdropColor(bgTok[1], bgTok[2], bgTok[3], bgAlpha or 1)
    frame:SetBackdropBorderColor(rimTok[1], rimTok[2], rimTok[3], 1)
end

-- =====================================================================
-- Tooltip attach helper. Collapses the 7+ hand-rolled copies of
-- OnEnter=>SetOwner+SetText+AddLine+Show / OnLeave=>Hide across tabs.
-- =====================================================================
ns.UI.Tooltip = ns.UI.Tooltip or {}
function ns.UI.Tooltip.Attach(frame, title, body, anchor)
    if not frame or not title then return end
    anchor = anchor or "ANCHOR_RIGHT"
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor)
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetText(title, 1, 1, 1)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- =====================================================================
-- Shared checkbox factory. Used by Settings tab and WardenSword settings.
-- Single source of truth for checkbox look + OnShow state sync + tooltip.
-- =====================================================================
ns.UI.Check = ns.UI.Check or {}
function ns.UI.Check.Make(parent, globalName, label, dbTable, key, opts)
    opts = opts or {}
    local cb = CreateFrame("CheckButton", globalName, parent,
                           "InterfaceOptionsCheckButtonTemplate")
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb:SetScript("OnShow", function(self)
        self:SetChecked(dbTable and dbTable[key] == true)
    end)
    cb:SetChecked(dbTable and dbTable[key] == true)
    cb:SetScript("OnClick", function(self)
        if dbTable then dbTable[key] = self:GetChecked() and true or false end
        if ns.DebugF then
            ns.DebugF("settings", "%s -> %s",
                tostring(label), (dbTable and dbTable[key]) and "ON" or "OFF")
        end
        if opts.onToggle then opts.onToggle(dbTable and dbTable[key] or false) end
        if opts.echo ~= false then
            ns.MsgInfo(label .. ": " .. ((dbTable and dbTable[key]) and "ON" or "OFF"))
        end
    end)
    if opts.tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetFrameStrata("TOOLTIP")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(opts.tip, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

-- TASKS.md §3.0: labeled "provides" chip. 36x14 rounded stone with 1 px
-- gold rim when ON, muted rim when OFF. Shares the exact stone-button
-- color tokens so dropdown / chip / Re-Spec button all feel like one family.
ns.UI.Chip = ns.UI.Chip or {}
function ns.UI.Chip.provide(parent, label, on)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(36, 14)
    c:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    if on then
        c:SetBackdropColor(0.22, 0.17, 0.08, 1)
        c:SetBackdropBorderColor(0.72, 0.58, 0.21, 1)
    else
        c:SetBackdropColor(0.08, 0.06, 0.04, 1)
        c:SetBackdropBorderColor(0.30, 0.24, 0.18, 1)
    end
    local t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("CENTER", c, "CENTER", 0, 0)
    t:SetText(label)
    if on then
        t:SetTextColor(1.00, 0.82, 0.00, 1)
    else
        t:SetTextColor(0.45, 0.38, 0.28, 1)
    end
    c.label = t
    return c
end

-- Dark stone inset panel with gold uppercase header. Returns a Frame whose
-- `.content` child should host the caller's widgets.
function ns.UI.Panel.Create(parent, w, h, headerText)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(w, h)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.10, 0.08, 0.05, 0.85)
    frame:SetBackdropBorderColor(0.23, 0.18, 0.13, 1)

    if headerText and headerText ~= "" then
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -4)
        header:SetText(string.upper(headerText))
        header:SetTextColor(1, 0.82, 0) -- gold
        frame.header = header

        -- TASKS.md §5.2: hair-line gold-dim rule under the header so every
        -- panel gets a consistent section divider for rhythm.
        local rule = frame:CreateTexture(nil, "ARTWORK")
        rule:SetTexture("Interface\\Buttons\\WHITE8x8")
        rule:SetVertexColor(0.72, 0.58, 0.21, 0.35)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
        rule:SetPoint("RIGHT",   frame,  "RIGHT",     -8, 0)
        frame.headerRule = rule
    end

    local content = CreateFrame("Frame", nil, frame)
    local topInset = (headerText and headerText ~= "") and 20 or 6
    content:SetPoint("TOPLEFT",     frame, "TOPLEFT",      6, -topInset)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6,  6)
    frame.content = content

    return frame
end

-- ----------------------------------------------------------
-- Static popups
-- ----------------------------------------------------------
StaticPopupDialogs["WARDEN_CONFIRM_CLEANUP"] = {
    text         = "Remove ALL bots from the raid?\n(sends .warstormbot bot remove *)",
    button1      = YES, button2 = NO, timeout = 0,
    whileDead    = true, hideOnEscape = true,
    OnAccept     = function()
        SendChatMessage(".warstormbot bot remove *", "SAY")
        ns.MsgWarn("Cleanup: removed all bots.")
    end,
}

StaticPopupDialogs["WARDEN_CONFIRM_HARD_RESPEC"] = {
    text         = "HARD ReSpec all bots to default epic?\n(sends .warstormbot bot init=epic)",
    button1      = YES, button2 = NO, timeout = 0,
    whileDead    = true, hideOnEscape = true,
    OnAccept     = function()
        SendChatMessage(".warstormbot bot init=epic", "SAY")
        ns.MsgWarn("Hard ReSpec: sent `.warstormbot bot init=epic`.")
    end,
}

-- ----------------------------------------------------------
-- Load banner
-- ----------------------------------------------------------
ns.CoreFrame = CreateFrame("Frame", "WardenCoreFrame")
ns.CoreFrame:RegisterEvent("PLAYER_LOGIN")
ns.CoreFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.MsgInfo("v" .. (GetAddOnMetadata(addonName, "Version") or "?")
            .. " loaded. `/warden` or minimap button to open.")
    end
end)

-- ----------------------------------------------------------
-- Slash commands - /warden (primary), /wden (short)
--
-- To trace why /warden stops working in combat, enable the debug
-- categories that fire here:
--   /wardenlog debug slash on
--   /wardenlog debug master on
-- Each step echoes to chat + is persisted to WardenLog.
-- ----------------------------------------------------------
local function toggleMaster()
    local inC  = (InCombatLockdown and InCombatLockdown()) and "Y" or "N"
    local f    = ns.UI.Master and ns.UI.Master.Frame and ns.UI.Master.Frame()
    local shn  = (f and f:IsShown()) and "Y" or "N"
    if ns.DebugF then
        ns.DebugF("slash", "/warden: combat=%s frame=%s shown=%s",
            inC, f and "Y" or "N", shn)
    end

    if ns.UI.Master and ns.UI.Master.Toggle then
        local ok, err = pcall(ns.UI.Master.Toggle)
        if not ok then
            -- Always surface this even when debug is off: a raw Toggle() error
            -- is rare enough that it's worth seeing unconditionally.
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Warden]|r Toggle() errored: "
                .. tostring(err))
            if ns.LogError then ns.LogError("Toggle() errored: " .. tostring(err)) end
        end
    end
end

SLASH_WARDEN1 = "/warden"
SLASH_WARDEN2 = "/wden"
SlashCmdList["WARDEN"] = toggleMaster

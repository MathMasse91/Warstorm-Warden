-- =====================================================
-- Warden - Pocket.lua
-- WardenPocket (/wp): WTS buy-offer aggregator.
--   1. User drops an item in the slot or types its link, clicks [WTS].
--   2. Addon broadcasts "wts [item]" to channel 1 (General).
--   3. Bot whispers are parsed for "Xg Ys Zc" price tokens.
--   4. After INVITE_DELAY (silence debounce), maxOffers cap, or maxWait
--      timeout — whichever comes first — the highest bidder is invited.
--   5. When trade opens, the trade banner DOCKS into the Pocket frame
--      (or floats below center when Pocket is hidden) and lets the user
--      pick a qty multiplier, whisper the total, and accept the trade.
-- =====================================================

local _, ns = ...
ns.Pocket = ns.Pocket or {}

-- ----------------------------------------------------------
-- Tunables
-- ----------------------------------------------------------
local FRAME_W         = 280
local HEADER_H        = 22
local BANNER_H        = 16        -- conditional (armed / invited / trade open)
local SLOT_SIZE       = 32        -- was 22, bigger drop target
local INPUT_H         = 48        -- item slot + name + WTS button (PART2 §3.1)
local AUTO_H          = 24        -- "auto-invite at X offers or Ys" phrase
local AUTOTRADE_H     = 20        -- "auto-trade on proximity" checkbox row
local LIST_H          = 168       -- baseline; layout adjusts
local OFFER_TOP_H     = 28        -- #1 offer (gold rail)
local OFFER_SECOND_H  = 22        -- #2 offer
local OFFER_H         = 18        -- #3+ offers
local FOOTER_H        = 22
local PAD             = 8
local INVITE_DELAY    = 2.0       -- seconds of silence before auto-invite fires
local TRADE_PANEL_H   = 110       -- size of the docked trade UI

-- ----------------------------------------------------------
-- Module state
-- ----------------------------------------------------------
local state = {
    frame           = nil,
    armed           = false,
    item            = "",
    offers          = {},      -- { name, copper, display }
    lastWhisperTime = 0,
    armedTime       = 0,
    invited         = nil,
    bestOffer       = nil,
    rowFrames       = {},
    -- Widgets
    banner          = nil,     -- ns.UI.Banner.Create
    statusLbl       = nil,     -- footer phase summary
    inputRow        = nil,
    inputRule       = nil,
    autoRow         = nil,
    maxOffersBox    = nil,
    maxWaitBox      = nil,
    inputBox        = nil,
    slotIcon        = nil,
    itemNameLbl     = nil,
    wtsBtn          = nil,
    clearBtn        = nil,
    stopBtn         = nil,
    scrollFrame     = nil,
    listChild       = nil,
    emptyHint       = nil,
    tradePanel      = nil,
    tradeDocked     = false,
    tradeOpen       = false,
    -- Tunables (user-editable)
    maxOffers       = 20,
    maxWait         = 30,
    -- Proximity auto-trade
    autoTradeRow    = nil,
    autoTradeRow2   = nil,
    autoTradeCb     = nil,
    fullAutoCb      = nil,
    autoTradeFired  = false,   -- "once per invite" guard, reset on clear/WTS/TRADE_CLOSED
}

local tradeFloat   -- floating fallback when frame is hidden
local pocketListener

-- Convenience accessor; pocket subtable is created in Persistence.lua schema.
local function pocketDB()
    return ns.Persistence and ns.Persistence.DB and ns.Persistence.DB.pocket or nil
end

-- ----------------------------------------------------------
-- Price helpers
-- ----------------------------------------------------------
local function parseCopper(msg)
    if type(msg) ~= "string" then return nil end
    local g = tonumber(msg:match("(%d+)g")) or 0
    local s = tonumber(msg:match("(%d+)s")) or 0
    local c = tonumber(msg:match("(%d+)c")) or 0
    if g == 0 and s == 0 and c == 0 then return nil end
    return g * 10000 + s * 100 + c
end

-- Spaced format for display labels: "12g 21s 23c"
local function formatCopper(copper)
    if not copper or copper <= 0 then return "0g" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 then parts[#parts + 1] = c .. "c" end
    return #parts > 0 and table.concat(parts, " ") or "0g"
end

-- Compact format for whisper messages: "12g21s23c"
local function formatCopperCompact(copper)
    if not copper or copper <= 0 then return "0g" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then out = out .. g .. "g" end
    if s > 0 then out = out .. s .. "s" end
    if c > 0 then out = out .. c .. "c" end
    return out ~= "" and out or "0g"
end

-- ----------------------------------------------------------
-- Sorted offers (descending by copper value)
-- ----------------------------------------------------------
local function sortedOffers()
    local out = {}
    for _, o in ipairs(state.offers) do out[#out + 1] = o end
    table.sort(out, function(a, b) return a.copper > b.copper end)
    return out
end

local TOK = ns.Tokens or {}
local STONE_DARK= TOK.stone_dark or { 0.06, 0.04, 0.03 }
local STONE_MID = TOK.stone_mid  or { 0.10, 0.08, 0.05 }
local STONE_TILE= TOK.stone_tile or { 0.16, 0.13, 0.09 }
local STONE_RIM = TOK.stone_rim  or { 0.23, 0.18, 0.13 }
local GOLD      = TOK.gold       or { 1.00, 0.82, 0.00 }
local GOLD_DIM  = TOK.gold_dim   or { 0.72, 0.58, 0.21 }
local GOLD_RIM  = TOK.gold_rim   or { 0.66, 0.54, 0.30 }
local AMBER     = TOK.amber      or { 1.00, 0.60, 0.00 }
local GREEN     = TOK.green      or { 0.18, 0.80, 0.25 }
local INK_RED   = TOK.ink_red    or { 0.88, 0.29, 0.23 }
local TEXT_WARM = TOK.text_warm  or { 1.00, 0.92, 0.75 }

-- Forward declarations
local refreshBanner, refreshList, refreshAuto, refreshAll, layout, refreshWTSBtn
local dockTradePanel, undockTradePanel
local showTradeFloat, hideTradeFloat
local findInvitedUnit   -- used by refreshFooter (earlier) before its real defn

-- ----------------------------------------------------------
-- Offer row pool. Each row's height + visual is set per-render based on its
-- rank (#1 = top, #2 = second, #3+ = rest). Rows are pure render — no clicks.
-- ----------------------------------------------------------
local function ensureRow(idx, parent)
    local row = state.rowFrames[idx]
    if row then return row end
    row = CreateFrame("Frame", nil, parent)

    -- Top-tier gold rail accent (drawn as a 2px texture on the left).
    local rail = row:CreateTexture(nil, "BACKGROUND")
    rail:SetTexture("Interface\\Buttons\\WHITE8x8")
    rail:SetWidth(2)
    rail:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    rail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    rail:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    rail:Hide()
    row.rail = rail

    -- Soft gold fill behind the top row (decays toward right).
    local fill = row:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetAllPoints(row)
    fill:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.07)
    fill:Hide()
    row.fill = fill

    local crown = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    crown:SetPoint("LEFT", row, "LEFT", 8, 0)
    crown:SetWidth(10)
    crown:SetText("\194\183")
    crown:SetJustifyH("CENTER")
    row.crown = crown

    local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLbl:SetPoint("LEFT",  crown, "RIGHT", 4, 0)
    nameLbl:SetJustifyH("LEFT")
    row.nameLbl = nameLbl

    local priceLbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priceLbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    priceLbl:SetJustifyH("RIGHT")
    row.priceLbl = priceLbl

    state.rowFrames[idx] = row
    return row
end

local function styleRow(row, rank, offer)
    if rank == 1 then
        row:SetHeight(OFFER_TOP_H)
        row.rail:Show()
        row.fill:Show()
        row.crown:SetText("\226\152\133")  -- ★
        row.crown:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        row.nameLbl:SetFontObject("GameFontNormal")
        row.priceLbl:SetFontObject("GameFontNormal")
        row.nameLbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        row.priceLbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    elseif rank == 2 then
        row:SetHeight(OFFER_SECOND_H)
        row.rail:Hide()
        row.fill:Hide()
        row.crown:SetText("\194\183")
        row.crown:SetTextColor(0.55, 0.50, 0.42, 1)
        row.nameLbl:SetFontObject("GameFontNormalSmall")
        row.priceLbl:SetFontObject("GameFontNormalSmall")
        row.nameLbl:SetTextColor(TEXT_WARM[1], TEXT_WARM[2], TEXT_WARM[3], 1)
        row.priceLbl:SetTextColor(TEXT_WARM[1], TEXT_WARM[2], TEXT_WARM[3], 1)
    else
        row:SetHeight(OFFER_H)
        row.rail:Hide()
        row.fill:Hide()
        row.crown:SetText("\194\183")
        row.crown:SetTextColor(0.45, 0.40, 0.32, 1)
        row.nameLbl:SetFontObject("GameFontNormalSmall")
        row.priceLbl:SetFontObject("GameFontNormalSmall")
        row.nameLbl:SetTextColor(0.62, 0.58, 0.48, 1)
        row.priceLbl:SetTextColor(0.62, 0.58, 0.48, 1)
    end
    row.nameLbl:SetText(offer.name or "?")
    row.priceLbl:SetText(offer.display or "0g")
end

refreshList = function()
    local child = state.listChild
    if not child then return end
    local sorted = sortedOffers()
    local n = #sorted

    -- Empty hint (only visible when no offers AND we've not yet broadcast).
    if state.emptyHint then
        if n == 0 then
            state.emptyHint:Show()
        else
            state.emptyHint:Hide()
        end
    end

    -- Layout rows top-down with cumulative heights
    local y = -2
    for i, o in ipairs(sorted) do
        local row = ensureRow(i, child)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  child, "TOPLEFT",   2, y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", -2, y)
        styleRow(row, i, o)
        row:Show()
        y = y - row:GetHeight() - 1
    end
    -- Hide overflow rows
    for i = n + 1, #state.rowFrames do
        local r = state.rowFrames[i]
        if r then r:Hide() end
    end
    child:SetHeight(math.max(LIST_H, -y + 4))
    refreshBanner()
end

-- ----------------------------------------------------------
-- Banner state (amber listening / green invited / green trade open)
-- ----------------------------------------------------------
refreshBanner = function()
    if not state.banner then return end
    if state.tradeOpen then
        state.banner:SetVariant("green")
        state.banner:SetPulse(false)
        local name = state.invited or (state.bestOffer and state.bestOffer.name) or "?"
        state.banner:SetText("TRADE OPEN", name)
        state.banner:Show()
    elseif state.invited then
        state.banner:SetVariant("green")
        state.banner:SetPulse(false)
        local price = state.bestOffer and state.bestOffer.display or "?"
        state.banner:SetText("INVITED " .. (state.invited or "?"), price)
        state.banner:Show()
    elseif state.armed then
        state.banner:SetVariant("amber")
        state.banner:SetPulse(true)
        local n = #state.offers
        local secLeft
        if state.maxWait > 0 and state.armedTime > 0 then
            local lr = state.maxWait - (GetTime() - state.armedTime)
            if lr < 0 then lr = 0 end
            secLeft = lr
        end
        local rightTxt
        if secLeft then
            rightTxt = string.format("%.0fs \194\183 %d offer%s", secLeft, n, n == 1 and "" or "s")
        else
            rightTxt = string.format("%d offer%s", n, n == 1 and "" or "s")
        end
        state.banner:SetText("LISTENING", rightTxt)
        state.banner:Show()
    else
        state.banner:SetPulse(false)
        state.banner:Hide()
    end
    if layout then layout() end
end

-- Footer phase summary: short italicized line ("5/20 offers \183 auto-invite in 22s").
local function refreshFooter()
    -- Footer "open trade" button: visible only once the invited bidder has
    -- actually joined the party (findInvitedUnit returns non-nil) AND no
    -- trade window is open. Showing it earlier (just because we sent an
    -- invite) is misleading — clicking would just fail until the bot is
    -- groupable.
    if state.footerOpenTradeBtn then
        local inParty = state.invited and findInvitedUnit() ~= nil
        if inParty and not state.tradeOpen then
            state.footerOpenTradeBtn:Show()
        else
            state.footerOpenTradeBtn:Hide()
        end
    end
    if not state.statusLbl then return end
    local n = #state.offers
    if state.tradeOpen then
        state.statusLbl:SetText("close trade to return")
        state.statusLbl:SetTextColor(0.55, 0.50, 0.42, 1)
    elseif state.invited then
        state.statusLbl:SetText("trade window opens, banner docks below")
        state.statusLbl:SetTextColor(0.55, 0.50, 0.42, 1)
    elseif state.armed then
        local cap = state.maxOffers > 0 and tostring(state.maxOffers) or "\226\136\158"
        local txt = string.format("%d/%s offer%s", n, cap, n == 1 and "" or "s")
        if state.maxWait > 0 and state.armedTime > 0 then
            local lr = state.maxWait - (GetTime() - state.armedTime)
            if lr < 0 then lr = 0 end
            txt = txt .. string.format(" \194\183 auto-invite in %.0fs", lr)
        end
        state.statusLbl:SetText(txt)
        state.statusLbl:SetTextColor(GOLD_DIM[1], GOLD_DIM[2], GOLD_DIM[3], 1)
    else
        if n > 0 then
            local best = sortedOffers()[1]
            state.statusLbl:SetText(string.format("%d offer%s \194\183 best %s",
                n, n == 1 and "" or "s", best.display))
            state.statusLbl:SetTextColor(0.55, 0.50, 0.42, 1)
        else
            state.statusLbl:SetText("")
        end
    end
end

-- ----------------------------------------------------------
-- Trade panel (docked) — built once, shown when TRADE_SHOW fires while
-- the Pocket frame is visible. Floats (centered) otherwise.
-- ----------------------------------------------------------
local function buildTradePanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    p:SetBackdropColor(STONE_MID[1], STONE_MID[2], STONE_MID[3], 1)
    p:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
    p:Hide()

    local hdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdr:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -6)
    hdr:SetText("|cffa88a4cSET PRICE FOR TRADE|r")

    -- Row: [qty] × <unit> = <total>
    local exprRow = CreateFrame("Frame", nil, p)
    exprRow:SetHeight(26)
    exprRow:SetPoint("TOPLEFT",  p, "TOPLEFT",  8, -22)
    exprRow:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -22)
    exprRow:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    exprRow:SetBackdropColor(STONE_DARK[1], STONE_DARK[2], STONE_DARK[3], 1)
    exprRow:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)

    local qtyBox = CreateFrame("EditBox", "WardenPocketQtyBox", exprRow, "InputBoxTemplate")
    qtyBox:SetSize(34, 18)
    qtyBox:SetPoint("LEFT", exprRow, "LEFT", 12, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetNumeric(true)
    qtyBox:SetMaxLetters(4)
    qtyBox:SetText("1")
    qtyBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    qtyBox:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
    p.qtyBox = qtyBox

    local timesLbl = exprRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timesLbl:SetPoint("LEFT", qtyBox, "RIGHT", 6, 0)
    timesLbl:SetText("|cff888888\195\151|r")

    local unitLbl = exprRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unitLbl:SetPoint("LEFT", timesLbl, "RIGHT", 4, 0)
    unitLbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    p.unitLbl = unitLbl

    local eqLbl = exprRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eqLbl:SetPoint("LEFT", unitLbl, "RIGHT", 6, 0)
    eqLbl:SetText("|cff888888=|r")

    local totalLbl = exprRow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    totalLbl:SetPoint("RIGHT", exprRow, "RIGHT", -10, 0)
    totalLbl:SetJustifyH("RIGHT")
    totalLbl:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    p.totalLbl = totalLbl

    local function recompute()
        if not state.bestOffer then return end
        local qty = math.max(1, tonumber(qtyBox:GetText()) or 1)
        local total = state.bestOffer.copper * qty
        p._copper = total
        totalLbl:SetText(formatCopper(total))
    end
    qtyBox:SetScript("OnTextChanged", recompute)
    p.recompute = recompute

    -- Resolve the trade partner. Priority:
    --   1. The currently-open trade window's NPC unit (most authoritative).
    --   2. state.invited (the player we just InviteUnit'd).
    --   3. state.bestOffer.name (any remaining offer state).
    --   4. sortedOffers()[1].name (rebuild from offers).
    -- Returning nil means "we have nothing to act on" — buttons no-op.
    local function resolveTarget()
        local npc = UnitName and UnitName("NPC")
        if npc and npc ~= "" and npc ~= UNKNOWN then return npc end
        if state.invited and state.invited ~= "" then return state.invited end
        if state.bestOffer and state.bestOffer.name then return state.bestOffer.name end
        local s = sortedOffers()
        if s[1] then return s[1].name end
        return nil
    end

    -- Action buttons. 3-in-a-row layout: whisper (56) + trade (48) + accept (60).
    --
    -- Strict 1-for-1 user spec:
    --   #1 "whisper" : whisper the total to the bot.
    --   #2 "trade"   : send InitiateTrade to the bot. When the bot accepts
    --                  (TRADE_SHOW), auto-place the item AND whisper the price.
    --                  The auto-place/auto-whisper side-effect is gated by
    --                  state.tradeAutoFlow set here, consumed on TRADE_SHOW.
    --   #3 "accept"  : secure-click on TradeFrameAcceptButton (only way to
    --                  call protected AcceptTrade() from an addon in 3.3.5).
    local TOK = ns.Tokens

    -- "whisper" button (#1)
    local whisper = ns.UI.Button.stone(p, "whisper", 56, 22)
    whisper:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 8, 8)
    whisper:SetScript("OnClick", function()
        local target = resolveTarget()
        if not target then
            ns.MsgWarn("Pocket: no trade target known.")
            return
        end
        local total = p._copper or (state.bestOffer and state.bestOffer.copper) or 0
        if total <= 0 then
            ns.MsgWarn("Pocket: no price to whisper.")
            return
        end
        local msg = formatCopperCompact(total)
        SendChatMessage(msg, "WHISPER", nil, target)
        ns.MsgInfo(string.format("Pocket: whispered %q to %s", msg, target))
    end)

    -- "trade" button (#2). Disabled by default: this panel only shows while
    -- a trade window is already open, so re-clicking "trade" would call
    -- InitiateTrade and trigger WoW's "you are already trading" error.
    -- The footer "open trade" button (visible only when bot in party AND
    -- trade NOT open) handles the actual trade-request kickoff.
    local tradeBtn = ns.UI.Button.stone(p, "trade", 48, 22)
    tradeBtn:SetPoint("LEFT", whisper, "RIGHT", 4, 0)
    tradeBtn:SetScript("OnClick", function()
        local target = resolveTarget()
        if not target then
            ns.MsgWarn("Pocket: no trade target known.")
            return
        end
        if type(InitiateTrade) == "function" then
            state.tradeAutoFlow = true   -- consumed on next TRADE_SHOW
            InitiateTrade(target)
            ns.MsgInfo(string.format("Pocket: trade request sent to %s...", target))
        end
    end)
    tradeBtn:Disable()
    p.tradeBtn = tradeBtn

    -- "accept" button (#3): SecureActionButtonTemplate because AcceptTrade()
    -- is protected and can only be called from a hardware click context.
    -- Named frames are never GC'd in WoW, so we create ONE secure button per
    -- panel slot (docked vs. float) and cache it on the namespace, reusing it
    -- across panel rebuilds instead of minting a fresh global name each call.
    -- The slot key is derived from whether we're building the docked panel
    -- (parented under the Pocket frame) or the float; both get a stable name.
    local btnName = (parent == state.frame)
        and "WardenPocketAcceptBtn" or "WardenPocketAcceptBtnFloat"
    local whisperAccept = _G[btnName]
    if not whisperAccept then
        whisperAccept = CreateFrame("Button", btnName, p, "SecureActionButtonTemplate")
        whisperAccept:EnableMouse(true)
        whisperAccept:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        whisperAccept:SetBackdropColor(TOK.stone_tile[1], TOK.stone_tile[2], TOK.stone_tile[3], 1)
        whisperAccept:SetBackdropBorderColor(TOK.gold_rim[1], TOK.gold_rim[2], TOK.gold_rim[3], 1)
        local accLbl = whisperAccept:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        accLbl:SetPoint("CENTER", whisperAccept, "CENTER", 0, 0)
        accLbl:SetText("accept")
        accLbl:SetTextColor(TOK.gold[1], TOK.gold[2], TOK.gold[3], 1)
        whisperAccept:SetFontString(accLbl)
        local accHi = whisperAccept:CreateTexture(nil, "HIGHLIGHT")
        accHi:SetTexture("Interface\\Buttons\\WHITE8x8")
        accHi:SetAllPoints(whisperAccept)
        accHi:SetBlendMode("ADD")
        accHi:SetVertexColor(1, 1, 1, 0.10)
        whisperAccept:SetHighlightTexture(accHi)

        -- Macro-based secure dispatch: WoW's /click chat slash is allowed to
        -- click protected buttons (TradeFrameAcceptButton -> AcceptTrade) when
        -- run from a SecureActionButton's macrotext attribute. This is the
        -- standard 3.3.5 pattern for invoking protected functions from addons.
        whisperAccept:SetAttribute("type", "macro")
        whisperAccept:SetAttribute("macrotext", "/click TradeFrameAcceptButton")
        -- Also register all buttons to ensure any modifier-combo click reaches
        -- the secure dispatch (some 3.3.5 builds require explicit registration).
        whisperAccept:RegisterForClicks("AnyUp", "AnyDown")
    end
    -- Reparent + reposition on every (re)build so the cached button attaches
    -- to the current panel instance.
    whisperAccept:SetParent(p)
    whisperAccept:SetSize(60, 22)
    whisperAccept:ClearAllPoints()
    whisperAccept:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 8)
    p.whisperAccept = whisperAccept

    -- /click resolves TradeFrameAcceptButton at click time, so no runtime
    -- arming needed.

    return p
end

local function refreshTradePanel()
    if not state.tradePanel then return end
    local p = state.tradePanel
    if state.bestOffer then
        p.unitLbl:SetText(state.bestOffer.display .. " /unit")
        p.qtyBox:SetText("1")
        p._copper = state.bestOffer.copper
        p.totalLbl:SetText(state.bestOffer.display)
    else
        -- Manual trade with no recorded offer: leave price blank, qty=1.
        p.unitLbl:SetText("(no price)")
        p.qtyBox:SetText("1")
        p._copper = 0
        p.totalLbl:SetText("-")
    end
end

dockTradePanel = function()
    if not state.tradePanel then return end
    state.tradeDocked = true
    refreshTradePanel()
    if state.scrollFrame   then state.scrollFrame:Hide()   end
    if state.autoRow       then state.autoRow:Hide()       end
    if state.autoTradeRow  then state.autoTradeRow:Hide()  end
    if state.autoTradeRow2 then state.autoTradeRow2:Hide() end
    state.tradePanel:Show()
    if layout then layout() end
end

undockTradePanel = function()
    state.tradeDocked = false
    if state.tradePanel    then state.tradePanel:Hide()    end
    if state.scrollFrame   then state.scrollFrame:Show()   end
    if state.autoRow       then state.autoRow:Show()       end
    if state.autoTradeRow  then state.autoTradeRow:Show()  end
    if state.autoTradeRow2 then state.autoTradeRow2:Show() end
    if layout then layout() end
end

-- Floating fallback when Pocket frame is hidden — same widget, free anchor.
showTradeFloat = function()
    if not tradeFloat then
        local f = CreateFrame("Frame", "WardenPocketTradeFloat", UIParent)
        f:SetSize(280, TRADE_PANEL_H + 28)
        f:SetFrameStrata("HIGH")
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(s) s:StartMoving() end)
        f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(STONE_DARK[1], STONE_DARK[2], STONE_DARK[3], 0.95)
        f:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)

        local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
        hdr:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
        f._hdr = hdr

        local panel = buildTradePanel(f)
        panel:Show()
        panel:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -22)
        panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        f._panel = panel
        tradeFloat = f
    end
    if state.bestOffer then
        tradeFloat._hdr:SetText("Best: " .. state.bestOffer.name .. " \194\183 " .. state.bestOffer.display)
        tradeFloat._panel.unitLbl:SetText(state.bestOffer.display .. " /unit")
        tradeFloat._panel.qtyBox:SetText("1")
        tradeFloat._panel._copper = state.bestOffer.copper
        tradeFloat._panel.totalLbl:SetText(state.bestOffer.display)
    else
        local who = state.invited or (UnitName and UnitName("NPC")) or "?"
        tradeFloat._hdr:SetText("Trade: " .. who)
        tradeFloat._panel.unitLbl:SetText("(no price)")
        tradeFloat._panel.qtyBox:SetText("1")
        tradeFloat._panel._copper = 0
        tradeFloat._panel.totalLbl:SetText("-")
    end
    tradeFloat:Show()
end

hideTradeFloat = function()
    if tradeFloat then tradeFloat:Hide() end
end

-- ----------------------------------------------------------
-- Auto-invite
-- ----------------------------------------------------------
local function fireInvite()
    if not state.armed or #state.offers == 0 then return end
    local sorted    = sortedOffers()
    state.bestOffer = sorted[1]
    state.invited   = sorted[1].name
    state.armed     = false
    state.autoTradeFired = false   -- new invite => arm proximity auto-trade
    InviteUnit(state.bestOffer.name)
    ns.MsgInfo(string.format("Pocket: invited %s (best offer: %s)",
        state.bestOffer.name, state.bestOffer.display))
    refreshList()
    refreshFooter()
    refreshBanner()
    refreshWTSBtn()
end

-- Strip "-Realm" so cross-realm whisper senders match party-roster names
-- (which are bare on 3.3.5 unless connected-realm pools are configured).
local function bareName(n)
    if type(n) ~= "string" then return n end
    local b = n:match("^([^%-]+)")
    return b or n
end

-- ----------------------------------------------------------
-- Auto-place helpers. Scan bags for stacks of state.item (matched by
-- itemId), then place them onto the player's trade slots via
-- PickupContainerItem + ClickTradeButton. Up to 6 slots (the 7th slot is
-- the "will not be traded" slot in 3.3.5).
-- ----------------------------------------------------------
local TRADE_PLAYER_SLOTS = 6

-- Returns an array {{bag, slot, count}, ...} for every stack of `link`.
local function findAllItemStacks(link)
    if type(link) ~= "string" then
        return {}
    end
    local wantId = link:match("|Hitem:(%d+)")
    if not wantId then
        return {}
    end
    local results = {}
    for bag = 0, 4 do
        local n = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local l = GetContainerItemLink and GetContainerItemLink(bag, slot)
            if l then
                local id = l:match("|Hitem:(%d+)")
                if id == wantId then
                    local _, count = GetContainerItemInfo(bag, slot)
                    -- Defensive: count must be a positive number; some
                    -- clients report nil/0 for stacks-of-1.
                    if type(count) ~= "number" or count < 1 then count = 1 end
                    results[#results + 1] = { bag = bag, slot = slot, count = count }
                end
            end
        end
    end
    return results
end

local function totalItemCount(link)
    local total = 0
    for _, e in ipairs(findAllItemStacks(link)) do total = total + e.count end
    return total
end

-- Place a single stack on trade slot 1. Returns true if placement was
-- attempted.
local function autoPlaceItemOnTrade()
    if not state.item or state.item == "" then return false end
    if type(GetTradePlayerItemLink) == "function" and GetTradePlayerItemLink(1) then
        return false  -- slot 1 already filled
    end
    local stacks = findAllItemStacks(state.item)
    if #stacks == 0 then
        ns.MsgWarn("Pocket: item not found in bags (auto-place skipped).")
        return false
    end
    local s = stacks[1]
    if type(ClearCursor) == "function" then ClearCursor() end
    if type(PickupContainerItem) == "function" then
        PickupContainerItem(s.bag, s.slot)
    end
    if type(ClickTradeButton) == "function" then
        ClickTradeButton(1)
    end
    return true
end

-- Place ALL stacks (up to 6 slots) onto the trade window. Returns the
-- total item count actually placed (sum of stack counts placed).
local function autoPlaceAllStacks()
    if not state.item or state.item == "" then
        return 0, 0
    end
    local stacks = findAllItemStacks(state.item)
    if #stacks == 0 then
        ns.MsgWarn("Pocket: item not found in bags (auto-place skipped).")
        return 0, 0
    end
    local placedCount = 0
    local placedSlots = 0
    for i, s in ipairs(stacks) do
        if i > TRADE_PLAYER_SLOTS then
            break
        end
        -- Skip slots already filled (user may have manually placed items).
        local already = type(GetTradePlayerItemLink) == "function"
                        and GetTradePlayerItemLink(i) or nil
        if not already then
            if type(ClearCursor) == "function" then ClearCursor() end
            if type(PickupContainerItem) == "function" then
                PickupContainerItem(s.bag, s.slot)
            end
            if type(ClickTradeButton) == "function" then
                ClickTradeButton(i)
            end
            placedCount = placedCount + s.count
            placedSlots = placedSlots + 1
        end
    end
    if #stacks > TRADE_PLAYER_SLOTS then
        ns.MsgWarn(string.format("Pocket: %d stacks in bag but only 6 trade slots — %d stack(s) left behind.",
            #stacks, #stacks - TRADE_PLAYER_SLOTS))
    end
    return placedCount, placedSlots
end

-- Find the party unit ID ("party1".."party4") whose UnitName matches the
-- invited bidder. Returns nil if the bidder hasn't accepted the invite yet
-- (or already left). Comparison is realm-stripped on both sides.
-- (Assignment instead of `local function` so the forward-declared local
-- at file top — used by refreshFooter — is populated, not shadowed.)
findInvitedUnit = function()
    if not state.invited then return nil end
    local want = bareName(state.invited)
    for i = 1, 4 do
        local id = "party" .. i
        local n  = UnitName and UnitName(id)
        if n and bareName(n) == want then return id end
    end
    return nil
end

-- Called from the OnUpdate ticker. Fires InitiateTrade exactly once per
-- invite when:
--   - the toggle is ON,
--   - we have an invited bidder,
--   - the bidder is in our party,
--   - the bidder is within trade range (CheckInteractDistance range 2),
--   - no trade is already open.
local function tickAutoTrade()
    if state.autoTradeFired then return end
    if state.tradeOpen then return end
    local db = pocketDB()
    if not (db and db.autoTrade) then return end
    if not state.invited then return end
    local unit = findInvitedUnit()
    if not unit then return end
    if type(CheckInteractDistance) ~= "function" then return end
    if not CheckInteractDistance(unit, 2) then return end
    state.autoTradeFired = true
    if type(InitiateTrade) == "function" then
        state.tradeAutoFlow = true   -- same flow as clicking "trade" button
        InitiateTrade(unit)
        ns.MsgInfo(string.format("Pocket: auto-trade with %s (in range).", state.invited))
    end
end

-- ----------------------------------------------------------
-- Persistent event listener + auto-invite debounce ticker
-- ----------------------------------------------------------
local function ensureListener()
    if pocketListener then return end
    pocketListener = CreateFrame("Frame", "WardenPocketListener")

    pocketListener._tick = 0
    pocketListener:SetScript("OnUpdate", function(self, elapsed)
        self._tick = (self._tick or 0) + elapsed
        if self._tick < 0.25 then return end
        self._tick = 0
        -- Proximity auto-trade runs every tick — independent of armed state
        -- because it fires AFTER fireInvite has set state.invited.
        tickAutoTrade()
        -- Banner countdown stays smooth (independent of invite triggers).
        if state.armed then refreshBanner(); refreshFooter() end
        if not state.armed or #state.offers == 0 then return end
        local now = GetTime()
        if state.maxWait > 0 and state.armedTime > 0 and now - state.armedTime >= state.maxWait then
            fireInvite(); return
        end
        if state.lastWhisperTime > 0 and now - state.lastWhisperTime >= INVITE_DELAY then
            fireInvite()
        end
    end)

    pocketListener:RegisterEvent("CHAT_MSG_WHISPER")
    pocketListener:RegisterEvent("TRADE_SHOW")
    pocketListener:RegisterEvent("TRADE_CLOSED")
    pocketListener:RegisterEvent("PARTY_MEMBERS_CHANGED")
    pocketListener:SetScript("OnEvent", function(_, event, text, sender)
        if event == "PARTY_MEMBERS_CHANGED" then
            -- Bot may have just accepted the invite. Refresh the footer
            -- so the "open trade" button appears now that findInvitedUnit
            -- can resolve to a party slot. tickAutoTrade is the source of
            -- truth for auto-trade — it'll catch up on the next 0.25s tick.
            if refreshFooter then refreshFooter() end
            return
        end
        if event == "TRADE_SHOW" then
            state.tradeOpen = true
            if state.frame and state.frame:IsShown() then
                dockTradePanel()
            else
                showTradeFloat()
            end
            -- If the trade was kicked off from our "trade" button (or from
            -- auto-proximity), auto-place the item AND whisper the price.
            if state.tradeAutoFlow then
                state.tradeAutoFlow = false
                local db = pocketDB()
                local fullAuto = db and db.fullAuto == true
                local unitPrice = state.bestOffer and state.bestOffer.copper or 0
                local target    = state.invited
                local count     = 1

                if fullAuto then
                    -- Place every stack we have (up to 6 trade slots) and
                    -- whisper the total = unitPrice * total item count.
                    local placedCount, placedSlots = autoPlaceAllStacks()
                    if placedSlots > 0 then
                        ns.MsgInfo(string.format("Pocket: auto-placed %d stack(s) totalling %d item(s).",
                            placedSlots, placedCount))
                    end
                    count = math.max(1, placedCount)
                else
                    if autoPlaceItemOnTrade() then
                        ns.MsgInfo("Pocket: item auto-placed on trade.")
                    end
                end

                if target and unitPrice > 0 then
                    local totalCopper = unitPrice * count
                    local msg = formatCopperCompact(totalCopper)
                    SendChatMessage(msg, "WHISPER", nil, target)
                    if count > 1 then
                        ns.MsgInfo(string.format("Pocket: whispered %q to %s (%d \195\151 %s).",
                            msg, target, count, formatCopperCompact(unitPrice)))
                    else
                        ns.MsgInfo(string.format("Pocket: whispered %q to %s", msg, target))
                    end
                end
            end
            refreshBanner()
            refreshFooter()
            return
        end
        if event == "TRADE_CLOSED" then
            state.tradeOpen     = false
            state.tradeAutoFlow = false
            -- Trade done (or cancelled) — allow another auto-trade attempt
            -- only after a new invite. Without this reset, a cancelled trade
            -- would never re-trigger.
            state.autoTradeFired = true
            undockTradePanel()
            hideTradeFloat()
            refreshBanner()
            refreshFooter()
            return
        end
        -- CHAT_MSG_WHISPER — only while armed
        if not state.armed then return end
        local copper = parseCopper(text)
        if not copper then return end
        for _, o in ipairs(state.offers) do
            if o.name == sender then
                if copper > o.copper then
                    o.copper  = copper
                    o.display = formatCopper(copper)
                end
                state.lastWhisperTime = GetTime()
                refreshList()
                refreshFooter()
                return
            end
        end
        table.insert(state.offers, {
            name    = sender,
            copper  = copper,
            display = formatCopper(copper),
        })
        state.lastWhisperTime = GetTime()
        if state.maxOffers > 0 and #state.offers >= state.maxOffers then
            fireInvite()
        else
            refreshList()
            refreshFooter()
        end
    end)
end

refreshWTSBtn = function()
    if not state.wtsBtn then return end
    local hasLink = state.item and state.item:find("|H") ~= nil
    if hasLink then state.wtsBtn:Enable() else state.wtsBtn:Disable() end
end

-- ----------------------------------------------------------
-- WTS broadcast + session reset
-- ----------------------------------------------------------
local function sendWTS()
    local item = state.item
    if not item or item == "" then
        ns.MsgWarn("Pocket: drop an item onto the slot first.")
        return
    end
    if not item:find("|H") then
        ns.MsgWarn("Pocket: drag an item from your bag onto the slot (or shift-click it).")
        return
    end
    wipe(state.offers)
    state.invited         = nil
    state.bestOffer       = nil
    state.lastWhisperTime = 0
    state.armedTime       = GetTime()
    state.autoTradeFired  = false
    for _, row in ipairs(state.rowFrames) do row:Hide() end
    state.armed = true
    ensureListener()
    refreshList()
    refreshBanner()
    refreshFooter()
    local displayName = item:match("|h%[(.-)%]|h") or item
    SendChatMessage("wts " .. item, "CHANNEL", nil, 1)
    ns.MsgInfo(string.format("Pocket: listening for offers on [%s]...", displayName))
end

-- ----------------------------------------------------------
-- Item slot capture (drag, click-with-item-on-cursor, shift-click into EditBox)
-- ----------------------------------------------------------
local function switchToFilledState()
    if state.inputBox then state.inputBox:ClearFocus() end
    if state.subLbl then state.subLbl:SetText("BROADCAST TO /1") end
    if state.itemNameLbl then
        state.itemNameLbl:SetFontObject("GameFontNormal")
        state.itemNameLbl:SetTextColor(TEXT_WARM[1], TEXT_WARM[2], TEXT_WARM[3], 1)
    end
end

local function switchToEmptyState()
    if state.inputBox then state.inputBox:SetText("") end
    if state.itemNameLbl then
        -- Smaller font so the long hint fits the ~160px center area.
        state.itemNameLbl:SetFontObject("GameFontDisableSmall")
        state.itemNameLbl:SetText("drop item or shift-click from bag")
        state.itemNameLbl:SetTextColor(0.45, 0.40, 0.32, 1)
    end
    if state.slotIcon then state.slotIcon:Hide() end
    local slot = _G["WardenPocketItemSlot"]
    if slot and slot._plus then slot._plus:Show() end
    if state.subLbl then state.subLbl:SetText("CHANNEL 1 / GENERAL") end
    state.item = ""
    refreshWTSBtn()
end

local function captureItemFromCursor()
    local t, id = GetCursorInfo()
    if t ~= "item" then return false end
    local _, link, _, _, _, _, _, _, _, tex = GetItemInfo(id)
    if not link then return false end
    state.item = link
    if state.slotIcon and tex then
        state.slotIcon:SetTexture(tex)
        state.slotIcon:SetAlpha(1)
        state.slotIcon:Show()
    end
    local name = link:match("|h%[(.-)%]|h") or link
    if state.itemNameLbl then
        state.itemNameLbl:SetText(name)
    end
    if state.inputBox then state.inputBox:SetText(link) end
    local slot = _G["WardenPocketItemSlot"]
    if slot and slot._plus then slot._plus:Hide() end
    switchToFilledState()
    ClearCursor()
    refreshWTSBtn()
    return true
end

-- Apply visual updates (icon, name label) for a link. Does NOT touch
-- state.inputBox — callers decide whether the link came from typing
-- (no SetText recursion) or from drag/click (SetText explicitly).
local function applyLinkVisuals(link)
    local name = link:match("|h%[(.-)%]|h") or link
    if state.itemNameLbl then
        state.itemNameLbl:SetText(name)
    end
    local itemId = link:match("|Hitem:(%d+)")
    if itemId then
        local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(tonumber(itemId))
        if state.slotIcon and tex then
            state.slotIcon:SetTexture(tex)
            state.slotIcon:SetAlpha(1)
            state.slotIcon:Show()
        end
    end
    -- Hide the "+" placeholder once a real item is set on the slot.
    local slot = _G["WardenPocketItemSlot"]
    if slot and slot._plus then slot._plus:Hide() end
end

local function setItemFromLink(link)
    state.item = link
    applyLinkVisuals(link)
    if state.inputBox and state.inputBox:GetText() ~= link then
        state.inputBox:SetText(link)
    end
    refreshWTSBtn()
end

-- ----------------------------------------------------------
-- Frame build
-- ----------------------------------------------------------
layout = function()
    local f = state.frame
    if not f then return end

    local y = HEADER_H

    if state.banner and state.banner:IsShown() then
        state.banner:ClearAllPoints()
        state.banner:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
        state.banner:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        y = y + BANNER_H
    end

    if state.inputRow then
        state.inputRow:ClearAllPoints()
        state.inputRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -(y + 2))
        state.inputRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(y + 2))
        state.inputRow:SetHeight(INPUT_H)
        y = y + INPUT_H + 4
    end
    if state.inputRule then
        state.inputRule:ClearAllPoints()
        state.inputRule:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -y)
        state.inputRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
        y = y + 3
    end

    if state.tradeDocked then
        if state.tradePanel then
            -- Fill the available vertical space (replaces the scroll list).
            state.tradePanel:ClearAllPoints()
            state.tradePanel:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, -(y + 4))
            state.tradePanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOTER_H + PAD + 2)
        end
    else
        if state.autoRow then
            state.autoRow:ClearAllPoints()
            state.autoRow:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -(y + 2))
            state.autoRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 2))
            state.autoRow:SetHeight(AUTO_H)
            y = y + AUTO_H + 2
        end
        if state.autoTradeRow then
            state.autoTradeRow:ClearAllPoints()
            state.autoTradeRow:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -(y + 2))
            state.autoTradeRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 2))
            state.autoTradeRow:SetHeight(AUTOTRADE_H)
            y = y + AUTOTRADE_H + 2
        end
        if state.autoTradeRow2 then
            state.autoTradeRow2:ClearAllPoints()
            state.autoTradeRow2:SetPoint("TOPLEFT",  f, "TOPLEFT",   PAD, -(y + 2))
            state.autoTradeRow2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 2))
            state.autoTradeRow2:SetHeight(AUTOTRADE_H)
            y = y + AUTOTRADE_H + 2
        end
        if state.scrollFrame then
            state.scrollFrame:ClearAllPoints()
            state.scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     PAD, -(y + 2))
            state.scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, FOOTER_H + PAD + 2)
        end
    end
end

local function build()
    if state.frame then return state.frame end

    local maxH = HEADER_H + BANNER_H + INPUT_H + 4 + 3 + AUTO_H + 2
               + AUTOTRADE_H + 2 + AUTOTRADE_H + 2
               + LIST_H + FOOTER_H + PAD * 2 + 8

    local f = CreateFrame("Frame", "WardenPocketFrame", UIParent)
    f:SetSize(FRAME_W, maxH)
    f:SetFrameStrata("MEDIUM")
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 80)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(STONE_DARK[1], STONE_DARK[2], STONE_DARK[3], 0.97)
    f:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
    state.frame = f

    -- Header
    local headerRow = CreateFrame("Frame", nil, f)
    headerRow:SetHeight(HEADER_H)
    headerRow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    headerRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)

    local title = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", headerRow, "LEFT", PAD, 0)
    title:SetText("WARDEN POCKET")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)

    local hint = headerRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 6, 0)
    hint:SetText("/wp")
    hint:SetTextColor(0.55, 0.50, 0.42, 1)

    local close = CreateFrame("Button", nil, headerRow)
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", headerRow, "RIGHT", -PAD, 0)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x")
    cfs:SetTextColor(0.85, 0.18, 0.12, 1)
    close:SetScript("OnClick", function() ns.Pocket.Hide() end)

    local hRule = headerRow:CreateTexture(nil, "ARTWORK")
    hRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    hRule:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
    hRule:SetHeight(1)
    hRule:SetPoint("BOTTOMLEFT",  headerRow, "BOTTOMLEFT",  0, 0)
    hRule:SetPoint("BOTTOMRIGHT", headerRow, "BOTTOMRIGHT", 0, 0)

    -- Banner (conditional)
    local banner = ns.UI.Banner.Create(f, "amber")
    banner:Hide()
    state.banner = banner

    -- Input row: [slot 32×32] [name lbl OR editbox] [WTS button]
    local inputRow = CreateFrame("Frame", nil, f)
    inputRow:SetHeight(INPUT_H)
    state.inputRow = inputRow

    local slotBtn = CreateFrame("Button", "WardenPocketItemSlot", inputRow)
    slotBtn:SetSize(SLOT_SIZE, SLOT_SIZE)
    slotBtn:SetPoint("LEFT", inputRow, "LEFT", PAD, 0)
    slotBtn:EnableMouse(true)
    slotBtn:RegisterForDrag("LeftButton")
    slotBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    slotBtn:SetBackdropColor(0, 0, 0, 0.8)
    slotBtn:SetBackdropBorderColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)

    local slotIcon = slotBtn:CreateTexture(nil, "ARTWORK")
    slotIcon:SetPoint("TOPLEFT",     slotBtn, "TOPLEFT",     1, -1)
    slotIcon:SetPoint("BOTTOMRIGHT", slotBtn, "BOTTOMRIGHT", -1, 1)
    slotIcon:Hide()  -- empty state shows only the "+" placeholder
    state.slotIcon = slotIcon

    -- Placeholder "+" overlay (visible when empty)
    local slotPlus = slotBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    slotPlus:SetPoint("CENTER", slotBtn, "CENTER", 0, 0)
    slotPlus:SetText("+")
    slotPlus:SetTextColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 0.6)
    slotBtn._plus = slotPlus

    slotBtn:SetScript("OnReceiveDrag", function()
        if captureItemFromCursor() then slotPlus:Hide(); slotIcon:Show() end
    end)
    slotBtn:SetScript("OnClick", function()
        if captureItemFromCursor() then slotPlus:Hide(); slotIcon:Show() end
    end)
    ns.UI.Tooltip.Attach(slotBtn, "Item slot",
        "Drag an item from your bag here, click while holding an item, or shift-click an item in your bag with the input field focused.",
        "ANCHOR_TOP")

    -- WTS button (right side)
    local wtsW = 56
    local wtsBtn = ns.UI.Button.red(inputRow, "WTS", wtsW, SLOT_SIZE)
    wtsBtn:SetPoint("RIGHT", inputRow, "RIGHT", -PAD, 0)
    wtsBtn:SetScript("OnClick", sendWTS)
    state.wtsBtn = wtsBtn

    -- Center area: editbox (when empty) OR item name label (when filled), plus
    -- a sub-line ("CHANNEL 1 / GENERAL" idle, "BROADCAST TO /1" once filled).
    local center = CreateFrame("Frame", nil, inputRow)
    center:SetPoint("LEFT",  slotBtn, "RIGHT", 8, 0)
    center:SetPoint("RIGHT", wtsBtn,  "LEFT", -8, 0)
    center:SetHeight(SLOT_SIZE)

    -- EditBox stays present (focusable for shift-click from bag), but its
    -- backdrop/text are invisible. The visible UI is the two labels below
    -- (itemNameLbl as title, subLbl as subtitle) — same layout in BOTH
    -- empty and filled states, matching the filled-state look from the
    -- screenshot.
    local inputBox = CreateFrame("EditBox", "WardenPocketInput", center)
    inputBox:SetAllPoints(center)
    inputBox:SetAutoFocus(false)
    inputBox:SetMaxLetters(256)
    inputBox:SetFontObject("GameFontHighlightSmall")
    inputBox:SetTextInsets(0, 0, 0, 0)
    inputBox:SetTextColor(0, 0, 0, 0)  -- typed chars are invisible

    -- itemNameLbl: parented to inputBox so it draws ABOVE the editbox's
    -- (empty) frame. Shows the placeholder hint when empty (small font),
    -- item name when filled (normal font, see switchToFilledState).
    local itemNameLbl = inputBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemNameLbl:SetPoint("TOPLEFT",  inputBox, "TOPLEFT",  0, -2)
    itemNameLbl:SetPoint("TOPRIGHT", inputBox, "TOPRIGHT", 0, -2)
    itemNameLbl:SetJustifyH("LEFT")
    itemNameLbl:SetWordWrap(false)
    itemNameLbl:SetText("drop item or shift-click from bag")
    itemNameLbl:SetTextColor(0.45, 0.40, 0.32, 1)
    state.itemNameLbl = itemNameLbl

    local subLbl = inputBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subLbl:SetPoint("BOTTOMLEFT",  inputBox, "BOTTOMLEFT",  1, 3)
    subLbl:SetPoint("BOTTOMRIGHT", inputBox, "BOTTOMRIGHT", 0, 3)
    subLbl:SetJustifyH("LEFT")
    subLbl:SetWordWrap(false)
    subLbl:SetText("CHANNEL 1 / GENERAL")
    subLbl:SetTextColor(0.45, 0.40, 0.32, 1)
    state.subLbl = subLbl

    -- Placeholder kept for legacy code paths; visible hint now lives in
    -- itemNameLbl.
    local placeholder = inputBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:Hide()
    inputBox._placeholder = placeholder

    inputBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    inputBox:SetScript("OnEnterPressed", function(s)
        local t = s:GetText() or ""
        if t:find("|H") then setItemFromLink(t) else state.item = t end
        sendWTS()
        s:ClearFocus()
    end)
    inputBox:SetScript("OnTextChanged", function(s)
        local text = s:GetText() or ""
        state.item = text
        if text:find("|H") then
            -- Visual-only update — calling setItemFromLink would loop via SetText.
            applyLinkVisuals(text)
            s:ClearFocus()
            switchToFilledState()
        end
        refreshWTSBtn()
    end)
    state.inputBox = inputBox

    local inputRule = f:CreateTexture(nil, "ARTWORK")
    inputRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    inputRule:SetVertexColor(STONE_RIM[1], STONE_RIM[2], STONE_RIM[3], 1)
    inputRule:SetHeight(1)
    state.inputRule = inputRule

    -- Auto-invite phrase row (italic + inline editboxes)
    local autoRow = CreateFrame("Frame", nil, f)
    autoRow:SetHeight(AUTO_H)
    state.autoRow = autoRow

    local pre = autoRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pre:SetPoint("LEFT", autoRow, "LEFT", 2, 0)
    pre:SetText("Auto-invite after")
    pre:SetTextColor(0.55, 0.50, 0.42, 1)

    -- Pull persisted defaults if available (DB is initialized on ADDON_LOADED
    -- and we run on PLAYER_LOGIN, so this is normally safe).
    do
        local pdb = pocketDB()
        if pdb then
            if type(pdb.maxOffers) == "number" then state.maxOffers = pdb.maxOffers end
            if type(pdb.maxWait)   == "number" then state.maxWait   = pdb.maxWait   end
        end
    end

    local maxBox = CreateFrame("EditBox", "WardenPocketTopBox", autoRow, "InputBoxTemplate")
    maxBox:SetSize(28, 16)
    maxBox:SetPoint("LEFT", pre, "RIGHT", 6, 0)
    maxBox:SetAutoFocus(false)
    maxBox:SetNumeric(true)
    maxBox:SetMaxLetters(3)
    maxBox:SetText(tostring(state.maxOffers))
    maxBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    maxBox:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
    maxBox:SetScript("OnTextChanged",   function(s)
        state.maxOffers = math.max(0, tonumber(s:GetText()) or 0)
        local pdb = pocketDB()
        if pdb then pdb.maxOffers = state.maxOffers end
        refreshFooter()
    end)
    state.maxOffersBox = maxBox

    local mid1 = autoRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mid1:SetPoint("LEFT", maxBox, "RIGHT", 4, 0)
    mid1:SetText("offers or")
    mid1:SetTextColor(0.55, 0.50, 0.42, 1)

    local waitBox = CreateFrame("EditBox", "WardenPocketWaitBox", autoRow, "InputBoxTemplate")
    waitBox:SetSize(28, 16)
    waitBox:SetPoint("LEFT", mid1, "RIGHT", 6, 0)
    waitBox:SetAutoFocus(false)
    waitBox:SetNumeric(true)
    waitBox:SetMaxLetters(3)
    waitBox:SetText(tostring(state.maxWait))
    waitBox:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    waitBox:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
    waitBox:SetScript("OnTextChanged",   function(s)
        state.maxWait = math.max(0, tonumber(s:GetText()) or 0)
        local pdb = pocketDB()
        if pdb then pdb.maxWait = state.maxWait end
        refreshFooter()
    end)
    state.maxWaitBox = waitBox

    local tail = autoRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tail:SetPoint("LEFT", waitBox, "RIGHT", 4, 0)
    tail:SetText("s")
    tail:SetTextColor(0.55, 0.50, 0.42, 1)

    -- Toggle row: two side-by-side checkboxes (auto-trade on proximity,
    -- fully-auto stack handling). They share AUTOTRADE_H so the frame
    -- height stays constant.
    local autoTradeRow = CreateFrame("Frame", nil, f)
    autoTradeRow:SetHeight(AUTOTRADE_H)
    state.autoTradeRow = autoTradeRow

    local db = pocketDB() or { autoTrade = true, fullAuto = false }

    local cb = ns.UI.Check.Make(autoTradeRow, "WardenPocketAutoTradeCb",
        "auto-trade on proximity", db, "autoTrade", {
            echo = false,
            tip  = "When ON: as soon as the invited bidder joins the party "
                .. "and is in trade range (~11y), open a trade request "
                .. "automatically. Fires once per invite.",
        })
    cb:SetPoint("LEFT", autoTradeRow, "LEFT", PAD - 4, 0)
    cb:SetSize(18, 18)
    local cbText = _G[cb:GetName() .. "Text"]
    if cbText then
        cbText:SetFontObject("GameFontDisableSmall")
        cbText:SetTextColor(0.55, 0.50, 0.42, 1)
        cbText:ClearAllPoints()
        cbText:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    end
    state.autoTradeCb = cb

    -- Second row for the "fully auto (stacks)" toggle — own frame so it
    -- gets its own line under the proximity checkbox (the label would
    -- overflow the panel if put inline).
    local autoTradeRow2 = CreateFrame("Frame", nil, f)
    autoTradeRow2:SetHeight(AUTOTRADE_H)
    state.autoTradeRow2 = autoTradeRow2

    local cb2 = ns.UI.Check.Make(autoTradeRow2, "WardenPocketFullAutoCb",
        "fully auto (sell all stacks)", db, "fullAuto", {
            echo = false,
            tip  = "When ON: on every trade open, place ALL stacks of the "
                .. "WTS item on the trade window (up to 6 slots) AND whisper "
                .. "the price multiplied by total item count. Final accept "
                .. "still requires clicking 'accept' (WoW protected function).",
        })
    cb2:SetPoint("LEFT", autoTradeRow2, "LEFT", PAD - 4, 0)
    cb2:SetSize(18, 18)
    local cb2Text = _G[cb2:GetName() .. "Text"]
    if cb2Text then
        cb2Text:SetFontObject("GameFontDisableSmall")
        cb2Text:SetTextColor(0.55, 0.50, 0.42, 1)
        cb2Text:ClearAllPoints()
        cb2Text:SetPoint("LEFT", cb2, "RIGHT", 2, 1)
    end
    state.fullAutoCb = cb2

    -- Scroll list
    local sf = CreateFrame("ScrollFrame", "WardenPocketScroll", f)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * OFFER_H * 3)))
    end)
    state.scrollFrame = sf

    local child = CreateFrame("Frame", "WardenPocketScrollChild", sf)
    child:SetSize(FRAME_W - PAD * 2, LIST_H)
    sf:SetScrollChild(child)
    state.listChild = child

    -- Empty hint inside the list area
    local empty = CreateFrame("Frame", nil, child)
    empty:SetAllPoints(child)
    local emptyT = empty:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyT:SetPoint("CENTER", empty, "CENTER", 0, 16)
    emptyT:SetText("NO OFFERS YET")
    emptyT:SetTextColor(0.45, 0.40, 0.32, 1)
    local emptySub = empty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptySub:SetPoint("CENTER", empty, "CENTER", 0, -4)
    emptySub:SetWidth(FRAME_W - PAD * 4)
    emptySub:SetJustifyH("CENTER")
    emptySub:SetText("drop an item above and hit WTS to broadcast a buy request to channel 1")
    emptySub:SetTextColor(0.40, 0.35, 0.28, 1)
    state.emptyHint = empty

    -- Trade panel (built but hidden until TRADE_SHOW docks it)
    state.tradePanel = buildTradePanel(f)

    -- Footer
    local footerRow = CreateFrame("Frame", nil, f)
    footerRow:SetHeight(FOOTER_H)
    footerRow:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, PAD)
    footerRow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, PAD)

    local clearBtn = ns.UI.Button.stone(footerRow, "clear", 56, FOOTER_H)
    clearBtn:SetPoint("LEFT", footerRow, "LEFT", PAD, 0)
    clearBtn:SetScript("OnClick", function()
        if state.invited then
            UninviteUnit(state.invited)
            ns.MsgInfo(string.format("Pocket: kicked %s.", state.invited))
        end
        wipe(state.offers)
        state.invited         = nil
        state.bestOffer       = nil
        state.lastWhisperTime = 0
        state.armedTime       = 0
        state.armed           = false
        state.autoTradeFired  = true   -- nothing to auto-trade with
        for _, row in ipairs(state.rowFrames) do row:Hide() end
        switchToEmptyState()           -- reset the item slot too
        refreshList()
        refreshFooter()
        refreshBanner()
    end)
    state.clearBtn = clearBtn

    local stopBtn = ns.UI.Button.stone(footerRow, "stop", 56, FOOTER_H)
    stopBtn:SetPoint("RIGHT", footerRow, "RIGHT", -PAD, 0)
    stopBtn:SetScript("OnClick", function()
        if state.armed then
            state.armed = false
            ns.MsgInfo("Pocket: stopped.")
            refreshBanner()
            refreshFooter()
        end
    end)
    state.stopBtn = stopBtn

    -- "open trade" lives in the footer (NOT in the docked trade panel where
    -- it was useless — a trade is already open by definition there).
    -- Visible only when we have an invited bidder AND no trade is currently
    -- open. Position is dynamic (refreshFooter re-anchors statusLbl).
    local footerOpenTrade = ns.UI.Button.gold(footerRow, "open trade", 80, FOOTER_H)
    footerOpenTrade:SetPoint("LEFT", clearBtn, "RIGHT", 6, 0)
    footerOpenTrade:Hide()
    footerOpenTrade:SetScript("OnClick", function()
        if not state.invited then return end
        local unit = findInvitedUnit()
        local target = unit or state.invited
        if type(InitiateTrade) == "function" then
            state.tradeAutoFlow = true   -- same auto-place + whisper on TRADE_SHOW as #2
            InitiateTrade(target)
            ns.MsgInfo(string.format("Pocket: opening trade with %s...", state.invited))
        end
    end)
    state.footerOpenTradeBtn = footerOpenTrade

    local statusLbl = footerRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusLbl:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    statusLbl:SetPoint("RIGHT", stopBtn, "LEFT", -8, 0)
    statusLbl:SetJustifyH("LEFT")
    state.statusLbl = statusLbl

    refreshWTSBtn()
    refreshFooter()
    refreshBanner()
    refreshList()
    layout()

    f:Hide()
    return f
end

-- ----------------------------------------------------------
-- Public API
-- ----------------------------------------------------------
refreshAll = function()
    refreshBanner()
    refreshList()
    refreshFooter()
    refreshWTSBtn()
end

function ns.Pocket.Show()
    if not state.frame then build() end
    state.frame:Show()
    -- If trade is currently open, dock the trade UI (with or without bestOffer).
    if state.tradeOpen then
        hideTradeFloat()
        dockTradePanel()
    end
    refreshAll()
end

function ns.Pocket.Hide()
    if state.frame then state.frame:Hide() end
    -- If trade was open while docked, switch to the floating fallback so the
    -- user can still complete the trade after hiding the HUD.
    if state.tradeOpen then
        undockTradePanel()
        showTradeFloat()
    end
end

function ns.Pocket.Toggle()
    if not state.frame then build() end
    if state.frame:IsShown() then ns.Pocket.Hide() else ns.Pocket.Show() end
end

-- ----------------------------------------------------------
-- Slash command
-- ----------------------------------------------------------
SLASH_WARDENPOCKET1 = "/wp"
SLASH_WARDENPOCKET2 = "/wardenpocket"
SlashCmdList["WARDENPOCKET"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lower = msg:lower()
    if lower == "hide" then ns.Pocket.Hide(); return end
    if lower == "show" then ns.Pocket.Show(); return end
    ns.Pocket.Toggle()
    if msg ~= "" and state.inputBox then
        state.inputBox:SetText(msg)
        state.item = msg
        refreshWTSBtn()
    end
end

-- Build the frame on PLAYER_LOGIN so the first /wp call doesn't pay the build
-- cost (which was the original "needs two tries to open" symptom). Also
-- start the event listener immediately so TRADE_SHOW / auto-trade work even
-- before the first WTS click.
local bootstrap = CreateFrame("Frame", "WardenPocketBootstrap")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not state.frame then build() end
    if type(ensureListener) == "function" then ensureListener() end

    -- Bag right-click hook: Ctrl+RightClick on a bag item, while the
    -- Pocket frame is visible, captures the item into the slot. The plain
    -- right-click (equip/use) and other modifier combos are untouched.
    if type(hooksecurefunc) == "function" then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(btn, button)
            if button ~= "RightButton" then return end
            if not IsControlKeyDown() then return end
            if not state.frame or not state.frame:IsShown() then return end
            local bag  = btn:GetParent() and btn:GetParent():GetID()
            local slot = btn:GetID()
            if not (bag and slot) then return end
            local link = GetContainerItemLink(bag, slot)
            if not link then return end
            setItemFromLink(link)
            ns.MsgInfo(string.format("Pocket: selected %s via Ctrl+RightClick.",
                link:match("|h%[(.-)%]|h") or link))
        end)
    end
end)

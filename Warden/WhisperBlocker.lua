-- =====================================================
-- Warden - WhisperBlocker.lua
-- Suppresses the noise whispers WarStorm playerbots fire at you, WITHOUT
-- hiding whispers from real players.
--
-- Two flavours of bot noise, handled differently:
--   1. Walk-by INVITE lines ("Invite me to your group first", ...) come from
--      bots NOT in your group. These are gated by the not-in-group check so a
--      grouped bot or a real player is never touched.
--   2. Action-ACK lines ("Equipping [item]", "Staying") come from YOUR OWN
--      bots, which ARE in your party/raid. These carry anySender=true so the
--      group check is bypassed - otherwise they'd never be filtered.
--
-- Gate: db.whisperFilter (master toggle in Settings). Off by default.
-- Each individual line can also be toggled via db.whisperFilters[<key>]
-- (default on) so the user picks exactly which lines get hidden.
--
-- Hooks Blizzard's chat pipeline via ChatFrame_AddMessageEventFilter, the
-- supported, non-taint way to drop a CHAT_MSG_WHISPER before it renders.
-- The filter is strictly nil-safe: it must never itself raise (see the
-- ChatFrame_OnEvent format-nil crashes that malformed bot chat can cause).
-- =====================================================

local _, ns = ...
ns.WhisperBlocker = ns.WhisperBlocker or {}

-- ----------------------------------------------------------
-- Bot whisper patterns.
-- Lua string.find patterns, matched case-insensitively against the whisper
-- body. Fields:
--   key       stable id, used as the db.whisperFilters[] toggle key + the
--             checkbox global name suffix in Settings.
--   label     human text shown next to the Settings checkbox.
--   pattern   Lua pattern tested against msg:lower().
--   anySender when true, the line is hidden even if the sender is in your
--             party/raid (used for your own bots' action acks). When absent,
--             only out-of-group senders are filtered.
--
-- Exact in-game text (WarStorm playerbots):
--   "Invite me to your group first"
--   "I am in a full group. Will do it later"
--   "I am in a group with <player>. You can ask him for invite"
--   "Equipping <item link>"                         (bot gear swaps)
--   "Staying"                                        (bot stay ack)
--   "Following"                                      (bot follow ack)
--
-- Notes on the trickier two:
--   * askinvite: the player name and him/her pronoun change every time, so we
--     bridge the stable anchors "i am in a group with" and "for invite" with a
--     lazy `.-` wildcard.
--   * equipping: the item is a real item hyperlink, so we anchor on the link
--     escape "|hitem" (lowercased) after the word so a player merely typing
--     "equipping soon" is never caught.
--   * staying / following: these words appear inside plenty of normal
--     sentences, so each is a WHOLE-MESSAGE match only ("^...$", trailing
--     punctuation ok), never a substring.
-- ----------------------------------------------------------
local BOT_WHISPER_PATTERNS = {
    { key = "invite",    label = "\"Invite me to your group first\"",
      pattern = "invite me to your group" },
    { key = "fullgroup", label = "\"I am in a full group. Will do it later\"",
      pattern = "in a full group%. will do it later" },
    { key = "askinvite", label = "\"...you can ask <player> for invite\"",
      pattern = "i am in a group with .- for invite" },
    { key = "equipping", label = "\"Equipping [item]\"  (your bots' gear swaps)",
      pattern = "equipping.-|hitem", anySender = true },
    { key = "staying",   label = "\"Staying\"  (whole message only)",
      pattern = "^%s*staying[%s%p]*$", anySender = true },
    { key = "following", label = "\"Following\"  (whole message only)",
      pattern = "^%s*following[%s%p]*$", anySender = true },
}

-- Exposed so UI_TabSettings can build one checkbox per line without
-- duplicating the key/label list.
ns.WhisperBlocker.PATTERNS = BOT_WHISPER_PATTERNS

-- Seed a default-on toggle for every pattern the first time we see the DB.
-- Runs on Install (post-login), so db.whisperFilters is populated before the
-- Settings tab is ever opened. New patterns added in a later version get
-- their default-on entry the next time this runs.
function ns.WhisperBlocker.SeedDefaults()
    local db = ns.Persistence and ns.Persistence.DB
    if not db then return end
    db.whisperFilters = db.whisperFilters or {}
    for _, p in ipairs(BOT_WHISPER_PATTERNS) do
        if db.whisperFilters[p.key] == nil then
            db.whisperFilters[p.key] = true
        end
    end
end

-- ----------------------------------------------------------
-- Group membership: is `name` currently in my party/raid?
-- Built fresh per-call from the live roster (cheap; groups are <=40).
-- Names from CHAT_MSG_WHISPER may carry a "-Realm" suffix on some cores, so
-- we compare on the bare name.
-- ----------------------------------------------------------
local function bareName(name)
    if type(name) ~= "string" then return nil end
    local n = name:match("^([^-]+)") or name
    return n:lower()
end

local function isInMyGroup(sender)
    local want = bareName(sender)
    if not want then return false end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local u = UnitName("raid" .. i)
            if u and u:lower() == want then return true end
        end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local u = UnitName("party" .. i)
            if u and u:lower() == want then return true end
        end
    end
    return false
end

-- Returns the matching pattern entry (so the caller can read anySender), or
-- nil. Skips any pattern the user has toggled off; a missing db/table means
-- everything defaults on.
local function matchedPattern(msg)
    if type(msg) ~= "string" or msg == "" then return nil end
    local db    = ns.Persistence and ns.Persistence.DB
    local flags = db and db.whisperFilters
    local body  = msg:lower()
    for _, p in ipairs(BOT_WHISPER_PATTERNS) do
        local enabled = (not flags) or flags[p.key] ~= false
        if enabled and body:find(p.pattern) then return p end
    end
    return nil
end

-- ----------------------------------------------------------
-- The filter. Return true to SUPPRESS the whisper, false/nil to keep it.
-- Signature in 3.3.5a: (self, event, message, author, ...)
-- ----------------------------------------------------------
local function whisperFilter(_, _, message, author)
    local db = ns.Persistence and ns.Persistence.DB
    if not (db and db.whisperFilter) then return false end   -- feature off
    local p = matchedPattern(message)
    if not p then return false end                           -- no line matched
    -- Walk-by invite lines: only hide out-of-group senders (grouped bot / real
    -- player passes). Action-ack lines (anySender) come from your own grouped
    -- bots, so they must be hidden regardless of group membership.
    if not p.anySender and isInMyGroup(author) then return false end

    ns.WhisperBlocker._blocked = (ns.WhisperBlocker._blocked or 0) + 1
    if ns.DebugF then
        ns.DebugF("whisper", "blocked bot whisper (%s) from %s: %s",
            p.key, tostring(author), tostring(message))
    end
    return true
end

-- ----------------------------------------------------------
-- Registration. Idempotent so /reload doesn't stack filters. The filter
-- itself is always installed; the db.whisperFilter gate lives inside it, so
-- toggling the setting takes effect live with no re-register needed.
-- ----------------------------------------------------------
local installed = false
function ns.WhisperBlocker.Install()
    ns.WhisperBlocker.SeedDefaults()
    if installed then return end
    if type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", whisperFilter)
    installed = true
end

if ns.Persistence and ns.Persistence.OnReady then
    ns.Persistence.OnReady(function() ns.WhisperBlocker.Install() end)
else
    ns.WhisperBlocker.Install()
end

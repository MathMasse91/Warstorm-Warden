-- =====================================================
-- Warden - WhisperBlocker.lua
-- Suppresses the "I'm available to be invited" style whispers that WarStorm
-- playerbots fire at you when you walk past them, WITHOUT hiding whispers
-- from real players or from bots already in your group.
--
-- Gate: db.whisperFilter (toggle in Settings). Off by default.
--
-- Strategy (per user decision): TARGETED match.
--   suppress IFF  sender is NOT in your current party/raid
--             AND message text matches a known bot-invite pattern.
-- A real player whispering you always passes. A bot already grouped passes.
--
-- Hooks Blizzard's chat pipeline via ChatFrame_AddMessageEventFilter, the
-- supported, non-taint way to drop a CHAT_MSG_WHISPER before it renders.
-- The filter is strictly nil-safe: it must never itself raise (see the
-- ChatFrame_OnEvent format-nil crashes that malformed bot chat can cause).
-- =====================================================

local _, ns = ...
ns.WhisperBlocker = ns.WhisperBlocker or {}

-- ----------------------------------------------------------
-- Bot-invite patterns.
-- Lua string.find patterns, matched case-insensitively against the whisper
-- body. Kept as ANCHOR-FREE substrings so minor server wording changes
-- (punctuation, a trailing name) still match.
--
-- Exact in-game text (WarStorm playerbot walk-by whispers):
--   "Invite me to your group first"
--   "I am in a full group. Will do it later"
-- We match the stable distinctive cores so trailing/leading word or
-- punctuation variation still catches them.
-- ----------------------------------------------------------
local BOT_INVITE_PATTERNS = {
    "invite me to your group",
    "in a full group%. will do it later",
}

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

local function matchesBotInvite(msg)
    if type(msg) ~= "string" or msg == "" then return false end
    local body = msg:lower()
    for _, pat in ipairs(BOT_INVITE_PATTERNS) do
        if body:find(pat) then return true end
    end
    return false
end

-- ----------------------------------------------------------
-- The filter. Return true to SUPPRESS the whisper, false/nil to keep it.
-- Signature in 3.3.5a: (self, event, message, author, ...)
-- ----------------------------------------------------------
local function whisperFilter(_, _, message, author)
    local db = ns.Persistence and ns.Persistence.DB
    if not (db and db.whisperFilter) then return false end   -- feature off
    if not matchesBotInvite(message) then return false end   -- not a bot invite
    if isInMyGroup(author) then return false end             -- grouped bot/player: keep

    ns.WhisperBlocker._blocked = (ns.WhisperBlocker._blocked or 0) + 1
    if ns.DebugF then
        ns.DebugF("whisper", "blocked bot-invite whisper from %s: %s",
            tostring(author), tostring(message))
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

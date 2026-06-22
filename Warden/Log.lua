-- =====================================================
-- Warden - Log.lua
-- Debug logger persisted to SavedVariables. Toggleable.
-- SV file: WTF/Account/<ACCT>/SavedVariables/Warden.lua
--   WardenLog        = { "HH:MM:SS [LEVEL] msg", ... } (max 500)
--   WardenLogEnabled = boolean   (default false - global verbose INFO switch)
--   WardenDebug      = table     (per-feature debug toggles)
--
-- Two tiers:
--   (a) Global INFO trace: ns.Log / ns.LogF  (controlled by WardenLogEnabled)
--       Legacy - fires across the whole addon when turned on.
--   (b) Per-feature DEBUG trace: ns.Debug / ns.DebugF  (controlled by
--       WardenDebug[category]). Each category fires independently so you
--       can trace ONE subsystem without drowning in noise, and the trace
--       echoes to the chat frame in real time for live observation.
--
-- Slash - log viewer:
--   /wardenlog                  -> show last 20 (or report OFF)
--   /wardenlog on               -> enable global INFO logging (persists)
--   /wardenlog off              -> disable global INFO logging
--   /wardenlog status           -> show global + per-category state
--   /wardenlog all              -> show all entries
--   /wardenlog tail N           -> show last N entries
--   /wardenlog clear            -> wipe log
--
-- Slash - per-feature debug toggles:
--   /wardenlog debug            -> show current toggle state
--   /wardenlog debug help       -> list all known categories
--   /wardenlog debug <cat> on   -> enable trace for one category
--   /wardenlog debug <cat> off  -> disable trace for one category
--   /wardenlog debug all on     -> enable every category
--   /wardenlog debug all off    -> disable every category
--   /wardenlog debug reset      -> clear all toggles to off
-- =====================================================

local _, ns = ...

WardenLog        = WardenLog or {}
if WardenLogEnabled == nil then WardenLogEnabled = false end
WardenDebug      = WardenDebug or {}

local MAX_ENTRIES = 500

local function isEnabled() return WardenLogEnabled == true end

local function push(level, msg)
    -- ERROR always persists (for post-mortem). DEBUG is gated upstream by
    -- catEnabled() in ns.Debug; once it reaches here, write it. Everything
    -- else follows the global WardenLogEnabled switch.
    if level ~= "ERROR" and level ~= "DEBUG" and not isEnabled() then return end
    WardenLog = WardenLog or {}
    local ts = date and date("%H:%M:%S") or tostring(GetTime())
    table.insert(WardenLog, string.format("%s [%s] %s", ts, level or "INFO", tostring(msg)))
    local overflow = #WardenLog - MAX_ENTRIES
    if overflow > 0 then
        for i = 1, overflow do table.remove(WardenLog, 1) end
    end
end

function ns.Log(msg)       push("INFO",  msg) end
function ns.LogWarn(msg)   push("WARN",  msg) end
function ns.LogError(msg)  push("ERROR", msg) end
function ns.LogF(fmt, ...)
    if not isEnabled() then return end
    local ok, str = pcall(string.format, fmt, ...)
    push("INFO", ok and str or ("[LogF format err] " .. tostring(fmt)))
end
function ns.LogIsEnabled() return isEnabled() end

-- =====================================================
-- Per-feature debug trace.
--
-- Known categories (keep the list here in sync with the actual ns.Debug
-- callsites sprinkled through the codebase so /wardenlog debug help is
-- accurate).
-- =====================================================
ns.DebugCats = {
    "master",   -- UI_Master: Toggle / Show / Hide / X / tab switch
    "slash",    -- Slash command entries (/warden, /ws, /wardenlog, etc)
    "respec",   -- Roster tab per-row + bulk Re-Spec
    "whisper",  -- Engine whisper queue push + drain
    "build",    -- Engine StartBuild / Build done
    "roster",   -- Roster rebuild triggers
    "spec",     -- Spec tab target card / tile interactions
    "sword",    -- WardenSword HUD show / hide / actions
    "combat",   -- PLAYER_REGEN_DISABLED / ENABLED transitions
    "minimap",  -- Minimap button click routing
    "persist",  -- Persistence load / save / migrate
    "comp",     -- UI_TabComp save / load / build
    "controls", -- UI_TabControls send() sites
    "settings", -- UI_TabSettings toggle changes
}

local function catEnabled(cat)
    if not WardenDebug then return false end
    if WardenDebug.all == true then return true end
    return WardenDebug[cat] == true
end

-- Emits to BOTH the persisted log AND the chat frame. The chat echo is
-- the whole point: it lets you watch behavior unfold in real time without
-- alt-tabbing out to read the SV file.
function ns.Debug(cat, msg)
    if not catEnabled(cat) then return end
    local text = tostring(msg)
    push("DEBUG", "[" .. tostring(cat) .. "] " .. text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[Warden/" .. tostring(cat) .. "]|r " .. text)
    end
end

function ns.DebugF(cat, fmt, ...)
    if not catEnabled(cat) then return end
    local ok, str = pcall(string.format, fmt, ...)
    ns.Debug(cat, ok and str or ("[DebugF fmt err] " .. tostring(fmt)))
end

function ns.DebugIsOn(cat) return catEnabled(cat) end

-- =====================================================
-- Combat trace (helps any bug that's combat-triggered). This is wired
-- unconditionally at load time; it only emits when the "combat" debug
-- category is on, so it costs nothing in production.
-- =====================================================
local combatWatch = CreateFrame("Frame", "WardenLogCombatWatch")
combatWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatch:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        ns.Debug("combat", "enter combat")
    else
        ns.Debug("combat", "leave combat")
    end
end)

-- Chain error handler so we don't clobber BugGrabber / Swatter
local prevHandler = geterrorhandler and geterrorhandler() or nil
if type(seterrorhandler) == "function" then
    seterrorhandler(function(err)
        push("ERROR", tostring(err))
        if type(prevHandler) == "function" then return prevHandler(err) end
    end)
end

-- =====================================================
-- /wardenlog slash
-- =====================================================
local function isKnownCat(name)
    if name == "all" then return true end
    for _, c in ipairs(ns.DebugCats) do
        if c == name then return true end
    end
    return false
end

local function handleDebugSubcommand(rest)
    rest = rest or ""
    local sub, val = rest:match("^(%S*)%s*(%S*)$")
    sub = (sub or ""):lower()
    val = (val or ""):lower()

    -- status dump
    if sub == "" then
        ns.MsgInfo("Debug toggles:")
        local anyOn = false
        for _, c in ipairs(ns.DebugCats) do
            local on = WardenDebug[c] == true
            if on then anyOn = true end
            ns.MsgInfo(string.format("  %s: %s", c, on and "|cff88ff88ON|r" or "off"))
        end
        if WardenDebug.all then
            ns.MsgInfo("  |cff88ff88all=ON (overrides individual toggles)|r")
        end
        if not anyOn and not WardenDebug.all then
            ns.MsgInfo("  (nothing enabled - /wardenlog debug help to see usage)")
        end
        return
    end

    if sub == "help" or sub == "list" then
        ns.MsgInfo("Usage: /wardenlog debug <cat> on|off")
        ns.MsgInfo("Categories: " .. table.concat(ns.DebugCats, ", "))
        ns.MsgInfo("Shortcut:   /wardenlog debug all on|off")
        ns.MsgInfo("            /wardenlog debug reset")
        return
    end

    if sub == "reset" then
        for k in pairs(WardenDebug) do WardenDebug[k] = nil end
        ns.MsgInfo("Debug toggles cleared.")
        return
    end

    if not isKnownCat(sub) then
        ns.MsgWarn("Unknown category: " .. sub
            .. "   (/wardenlog debug help for list)")
        return
    end

    if val ~= "on" and val ~= "off" then
        ns.MsgWarn("Expected `on` or `off` after category.")
        return
    end

    WardenDebug[sub] = (val == "on") or nil  -- nil-out on off so the SV stays tidy
    if val == "on" then WardenDebug[sub] = true else WardenDebug[sub] = nil end
    ns.MsgInfo(string.format("debug %s: %s", sub, val:upper()))
end

SLASH_WARDENLOG1 = "/wardenlog"
SlashCmdList["WARDENLOG"] = function(args)
    args = tostring(args or "")
    local cmd, rest = args:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "on" then
        WardenLogEnabled = true
        ns.MsgInfo("Global logging ENABLED.")
        return
    end
    if cmd == "off" then
        WardenLogEnabled = false
        ns.MsgWarn("Global logging DISABLED (errors still captured).")
        return
    end
    if cmd == "status" then
        ns.MsgInfo(string.format("Global logging: %s  |  Entries: %d",
            isEnabled() and "ON" or "OFF", #(WardenLog or {})))
        local onCats = {}
        for _, c in ipairs(ns.DebugCats) do
            if WardenDebug[c] == true then table.insert(onCats, c) end
        end
        if WardenDebug.all then
            ns.MsgInfo("Debug: all=ON")
        elseif #onCats > 0 then
            ns.MsgInfo("Debug cats ON: " .. table.concat(onCats, ", "))
        else
            ns.MsgInfo("Debug cats: (none)")
        end
        return
    end
    if cmd == "clear" then
        WardenLog = {}
        ns.MsgInfo("Log cleared.")
        return
    end
    if cmd == "debug" then
        handleDebugSubcommand(rest)
        return
    end

    local log  = WardenLog or {}
    local n    = #log
    local show = 20
    if cmd == "all" then show = n
    elseif cmd == "tail" then show = tonumber(rest) or 20 end
    if show > n then show = n end
    if n == 0 then
        ns.MsgWarn("Log empty (logging is " .. (isEnabled() and "ON" or "OFF") .. ").")
        return
    end
    ns.MsgInfo(string.format("Log (%d/%d, global=%s):",
        show, n, isEnabled() and "ON" or "OFF"))
    for i = n - show + 1, n do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. log[i])
    end
end

push("INFO", "Warden Log.lua loaded")

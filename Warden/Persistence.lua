-- =====================================================
-- Warden - Persistence.lua
-- SavedVariables: WardenDB. Single lifecycle frame, idempotent schema.
-- =====================================================

local _, ns = ...

ns.Persistence.DB = nil

-- Keys copied from the runtime DB into WardenDB at logout. Runtime-only
-- fields (interval, commandChannel, addPattern) are intentionally absent
-- so a future default change propagates to existing users.
local COMMIT_SCALARS = {
    "version", "migratedFromV2", "presetsVersion",
    "lastComp", "autoRaidDuringBuild", "autoSpec",
    "bloodlust", "aoe", "burn",
    "disperseDist", "minimapAngle", "masterScale", "activeTab",
    "helpLastChapter", "whisperFilter",
}

-- Subtables preserved whole; always written so freshly-added keys survive.
local COMMIT_SUBTABLES = { "comps", "playerFlags", "sword", "shield", "pocket", "mantle", "whisperFilters" }

-- ----------------------------------------------------------
-- Schema init (idempotent)
-- ----------------------------------------------------------
local function initDB()
    WardenDB = WardenDB or {}
    local db = WardenDB

    if type(db.version)              ~= "number"  then db.version = 3 end
    if type(db.migratedFromV2)       ~= "boolean" then db.migratedFromV2 = false end
    if type(db.presetsVersion)       ~= "number"  then db.presetsVersion = 0 end
    if type(db.comps)                ~= "table"   then db.comps = {} end
    -- Drop the older boolean flag from schema v1; replaced by presetsVersion.
    if db.presetsSeeded ~= nil then db.presetsSeeded = nil end
    if type(db.lastComp)             ~= "string"  then db.lastComp = "" end
    if type(db.autoRaidDuringBuild)  ~= "boolean" then db.autoRaidDuringBuild = true end
    if type(db.autoSpec)             ~= "boolean" then db.autoSpec = true end
    if type(db.bloodlust)            ~= "boolean" then db.bloodlust = false end
    -- Strategy toggles the sword HUD status strip reads. Must persist or
    -- every /reload wipes them.
    if type(db.aoe)                  ~= "boolean" then db.aoe = false end
    if type(db.burn)                 ~= "boolean" then db.burn = false end
    if type(db.disperseDist)         ~= "number"  then db.disperseDist = 5 end
    if type(db.minimapAngle)         ~= "number"  then db.minimapAngle = 225 end
    if type(db.masterScale)          ~= "number"  then db.masterScale = 1.0 end
    if type(db.activeTab)            ~= "number"  then db.activeTab = 1 end
    if type(db.helpLastChapter)      ~= "string"  then db.helpLastChapter = "intro" end
    -- WhisperBlocker: suppress bot invite whispers from senders outside your
    -- group. Off by default; opt-in from Settings because pattern matching on
    -- whisper text can theoretically catch an unwanted real whisper.
    if type(db.whisperFilter)        ~= "boolean" then db.whisperFilter = false end
    -- Per-line toggles for the WhisperBlocker. The table exists here; the
    -- individual default-on keys are seeded by ns.WhisperBlocker.SeedDefaults()
    -- (keys live with the patterns, not here) once the DB is ready.
    if type(db.whisperFilters)       ~= "table"   then db.whisperFilters = {} end
    if type(db.playerFlags)          ~= "table"   then db.playerFlags = {} end

    -- WardenSword (mid-fight HUD) persisted state.
    if type(db.sword) ~= "table" then db.sword = {} end
    local sw = db.sword
    if type(sw.pos)                ~= "table"   then sw.pos                = nil end
    if type(sw.locked)             ~= "boolean" then sw.locked             = false end
    if type(sw.hidden)             ~= "boolean" then sw.hidden             = false end
    if type(sw.autoShowCombat)     ~= "boolean" then sw.autoShowCombat     = true end
    if type(sw.showStatus)         ~= "boolean" then sw.showStatus         = true end
    if type(sw.showRoles)          ~= "boolean" then sw.showRoles          = true end
    if type(sw.startLocked)        ~= "boolean" then sw.startLocked        = false end
    if type(sw.density)            ~= "string"  then sw.density            = "compact" end
    if type(sw.hideMinimapCombat)  ~= "boolean" then sw.hideMinimapCombat  = false end
    if type(sw.alpha)              ~= "number"  then sw.alpha              = 1.00 end

    -- WardenShield (discovery-command HUD) persisted state. Additive to the
    -- schema; existing users get defaults applied on next login.
    if type(db.shield) ~= "table" then db.shield = {} end
    local sh = db.shield
    if type(sh.pos)        ~= "table"   then sh.pos        = nil   end
    if type(sh.locked)     ~= "boolean" then sh.locked     = false end
    if type(sh.hidden)     ~= "boolean" then sh.hidden     = false end
    if type(sh.captureSec) ~= "number"  then sh.captureSec = 5     end
    if type(sh.exclusions) ~= "table"   then sh.exclusions = {}    end

    -- WardenMantle (/wm spec-swap HUD) persisted state. Hidden until the
    -- user opens it with /wm, then position + lock persist across /reload.
    if type(db.mantle) ~= "table" then db.mantle = {} end
    local mt = db.mantle
    if type(mt.pos)    ~= "table"   then mt.pos    = nil  end
    if type(mt.locked) ~= "boolean" then mt.locked = false end
    if type(mt.hidden) ~= "boolean" then mt.hidden = true end

    -- WardenPocket (/wp WTS aggregator) persisted state.
    if type(db.pocket) ~= "table" then db.pocket = {} end
    local pk = db.pocket
    if type(pk.autoTrade) ~= "boolean" then pk.autoTrade = true  end
    if type(pk.fullAuto)  ~= "boolean" then pk.fullAuto  = false end
    if type(pk.maxOffers) ~= "number"  then pk.maxOffers = 20    end
    if type(pk.maxWait)   ~= "number"  then pk.maxWait   = 30    end

    -- Drop stale keys from prior schema versions.
    if db.density ~= nil then db.density = nil end
    if db.sword and db.sword.tone ~= nil then db.sword.tone = nil end

    -- Runtime-only defaults (not committed, never persisted).
    db.interval       = 0.90
    db.commandChannel = "SAY"
    db.addPattern     = ".warstormbot bot addclass %s"

    return db
end

-- ----------------------------------------------------------
-- Default preset seeding / migration. `db.presetsVersion` tracks which
-- schema of built-in presets is currently seeded:
--   0 = never seeded (fresh install, or pre-schema DB)
--   1 = old count-based presets (8 entries)
--   2 = positional presets with curly-apostrophe "Onyxia's" names
--   3 = same set but with ASCII apostrophe (FrizQT-safe)
--   4 = refreshed layouts per user hand-off (Onyxia 10 rebuilt, ToC/Ruby
--       hunter mm, 25-man split into MM / SURV variants)
--   5 = same 11 presets, slots reordered tank → melee → ranged → heal
--       (then alphabetical by class). Clusters tanks into G1 and healers
--       into the last group when laid out column-major.
-- Each migration step owns its own purge list (Data.LEGACY_PRESET_NAMES_Vn).
-- A user already at v3 crosses only the v3→v4 gap, so only the v3 preset
-- content gets replaced. After purging, we seed any default missing from
-- db.comps.
-- ----------------------------------------------------------
local function migrateDefaultPresets(db)
    local target  = tonumber(ns.Data.PRESETS_VERSION) or 0
    local current = db.presetsVersion or 0
    if current >= target then return 0, 0 end

    local purged = 0
    local lastWasPurged = false
    local function purgeList(list)
        for _, name in ipairs(list or {}) do
            if db.comps[name] ~= nil then
                db.comps[name] = nil
                purged = purged + 1
                if db.lastComp == name then lastWasPurged = true end
            end
        end
    end
    if current < 2 then purgeList(ns.Data.LEGACY_PRESET_NAMES_V1) end
    if current < 3 then purgeList(ns.Data.LEGACY_PRESET_NAMES_V2) end
    if current < 4 then purgeList(ns.Data.LEGACY_PRESET_NAMES_V3) end
    if current < 5 then purgeList(ns.Data.LEGACY_PRESET_NAMES_V4) end
    if lastWasPurged then db.lastComp = "" end

    local seeded = 0
    for _, name in ipairs(ns.Data.DEFAULT_PRESET_NAMES or {}) do
        if type(db.comps[name]) ~= "table" then
            local comp = ns.Data.BuildDefaultPresetComp(name)
            if comp then
                db.comps[name] = comp
                seeded = seeded + 1
            end
        end
    end
    db.presetsVersion = target
    return seeded, purged
end

-- Re-seed any missing default presets (user-invoked, e.g., "Restore default
-- presets" in Settings). Does NOT overwrite existing entries; a user who
-- edited "Ulduar 25" keeps their edits. Returns the count re-added.
function ns.Persistence.RestoreDefaultPresets()
    local db = ns.Persistence.DB
    if not db then return 0 end
    db.comps = db.comps or {}
    local added = 0
    for _, name in ipairs(ns.Data.DEFAULT_PRESET_NAMES or {}) do
        if type(db.comps[name]) ~= "table" then
            local comp = ns.Data.BuildDefaultPresetComp(name)
            if comp then
                db.comps[name] = comp
                added = added + 1
            end
        end
    end
    return added
end

-- ----------------------------------------------------------
-- Migrations
-- ----------------------------------------------------------
local function migrateFromV2(db)
    if db.migratedFromV2 then return end
    local src = _G.WarstormSpecManagerDB
    if type(src) ~= "table" then
        db.migratedFromV2 = true
        return
    end

    local defaults = ns.Data.DEFAULT_SPEC_PVE
    local order    = ns.Data.CLASS_ORDER
    local migratedCount = 0
    if type(src.comps) == "table" then
        for name, oldComp in pairs(src.comps) do
            if type(oldComp) == "table" and type(db.comps[name]) ~= "table" then
                local rows = {}
                for _, classToken in ipairs(order) do
                    local count = tonumber(oldComp[classToken]) or 0
                    if count > 0 then
                        table.insert(rows, {
                            classToken = classToken,
                            spec       = defaults[classToken],
                            count      = count,
                        })
                    end
                end
                db.comps[name] = { rows = rows }
                migratedCount = migratedCount + 1
            end
        end
    end
    if type(src.lastComp) == "string" and src.lastComp ~= "" and db.lastComp == "" then
        db.lastComp = src.lastComp
    end
    db.migratedFromV2 = true
    if migratedCount > 0 then
        ns.MsgInfo(string.format("Migrated %d comp(s) from WarstormSpecManager.", migratedCount))
    end
end

-- ----------------------------------------------------------
-- Ready callbacks: run after initDB (either on PLAYER_LOGIN or, if the
-- event already fired before the caller registered, on the next frame).
-- Eliminates the ADDON_LOADED/PLAYER_LOGIN race by giving every late
-- initializer a single rendezvous point.
-- ----------------------------------------------------------
local readyCbs   = {}
local isReady    = false
function ns.Persistence.OnReady(cb)
    if type(cb) ~= "function" then return end
    if isReady then cb() else table.insert(readyCbs, cb) end
end

-- ----------------------------------------------------------
-- Lifecycle (single frame, no double-writer race)
-- ----------------------------------------------------------
local life = CreateFrame("Frame", "WardenPersistenceLifecycle")
life:RegisterEvent("PLAYER_LOGIN")
life:RegisterEvent("PLAYER_LOGOUT")
life:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ns.Persistence.DB = initDB()
        migrateFromV2(ns.Persistence.DB)
        migrateDefaultPresets(ns.Persistence.DB)
        -- Auto-flag the current character as a human player.
        local me = UnitName and UnitName("player")
        if me and ns.Persistence.DB.playerFlags[me] == nil then
            ns.Persistence.DB.playerFlags[me] = true
        end
        isReady = true
        if ns.DebugF then
            ns.DebugF("persist", "PLAYER_LOGIN: DB initialized (%d ready callbacks)",
                #readyCbs)
        end
        for _, cb in ipairs(readyCbs) do pcall(cb) end
        readyCbs = {}
    elseif event == "PLAYER_LOGOUT" then
        local src = ns.Persistence.DB
        if not src then return end
        if ns.Debug then ns.Debug("persist", "PLAYER_LOGOUT: committing DB") end
        WardenDB = WardenDB or {}
        for _, k in ipairs(COMMIT_SCALARS) do
            if src[k] ~= nil then WardenDB[k] = src[k] end
        end
        for _, k in ipairs(COMMIT_SUBTABLES) do
            WardenDB[k] = src[k] or {}
        end
        WardenDB.density = nil
    end
end)

function ns.Persistence.Get() return ns.Persistence.DB end

-- ----------------------------------------------------------
-- Human-player flag helpers.
-- ----------------------------------------------------------
function ns.Persistence.IsPlayerName(name)
    if not name or name == "" then return false end
    local db = ns.Persistence.DB
    return (db and db.playerFlags and db.playerFlags[name] == true) or false
end

function ns.Persistence.SetPlayerName(name, flag)
    if not name or name == "" then return end
    local db = ns.Persistence.DB
    if not db then return end
    db.playerFlags = db.playerFlags or {}
    if flag then db.playerFlags[name] = true
    else db.playerFlags[name] = nil end
end

function ns.Persistence.ClearAllPlayerFlags()
    local db = ns.Persistence.DB
    if not db then return 0 end
    local n = 0
    for _ in pairs(db.playerFlags or {}) do n = n + 1 end
    db.playerFlags = {}
    -- Re-flag self so auto-behavior still protects the user.
    local me = UnitName and UnitName("player")
    if me then db.playerFlags[me] = true end
    return n
end

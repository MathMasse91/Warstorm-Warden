-- =====================================================
-- Warden - Data.lua
-- Class specs, strategy codes, raid presets, options per class+spec.
-- =====================================================

local _, ns = ...

-- ----------------------------------------------------------
-- Class enumeration (canonical order - used by UI and engine)
-- ----------------------------------------------------------
ns.Data.CLASS_ORDER = {
    "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST",
    "SHAMAN","MAGE","WARLOCK","DRUID","DEATHKNIGHT",
}

ns.Data.CLASS_LABEL = {
    WARRIOR="Warrior", PALADIN="Paladin", HUNTER="Hunter", ROGUE="Rogue", PRIEST="Priest",
    SHAMAN="Shaman", MAGE="Mage", WARLOCK="Warlock", DRUID="Druid", DEATHKNIGHT="DK",
}

ns.Data.CLASS_CMD = {
    WARRIOR="warrior", PALADIN="paladin", HUNTER="hunter", ROGUE="rogue", PRIEST="priest",
    SHAMAN="shaman", MAGE="mage", WARLOCK="warlock", DRUID="druid", DEATHKNIGHT="dk",
}

-- ----------------------------------------------------------
-- Specs per class (UI button labels + dropdown entries)
-- Key must match SPEC_EXEC key exactly.
-- ----------------------------------------------------------
ns.Data.CLASS_SPECS = {
    PALADIN     = { "prot pve","ret pve","holy pve","prot pvp","ret pvp","holy pvp" },
    WARRIOR     = { "prot pve","arms pve","fury pve","prot pvp","arms pvp","fury pvp" },
    DEATHKNIGHT = { "blood pve","frost pve","unholy pve","da blood pve","blood pvp","frost pvp","unholy pvp" },
    SHAMAN      = { "resto pve","ele pve","enh pve","resto pvp","ele pvp","enh pvp" },
    HUNTER      = { "bm pve","mm pve","surv pve","bm pvp","mm pvp","surv pvp" },
    DRUID       = { "bear pve","resto pve","cat pve","balance pve","resto pvp","cat pvp","balance pvp" },
    ROGUE       = { "as pve","combat pve","subtlety pve","as pvp","combat pvp","subtlety pvp" },
    PRIEST      = { "holy pve","disc pve","shadow pve","holy pvp","disc pvp","shadow pvp" },
    MAGE        = { "arcane pve","frost pve","fire pve","frostfire pve","arcane pvp","frost pvp","fire pvp" },
    WARLOCK     = { "affli pve","demo pve","destro pve","affli pvp","demo pvp","destro pvp" },
}

-- ----------------------------------------------------------
-- Default meta PvE spec per class (used by migration and presets)
-- ----------------------------------------------------------
ns.Data.DEFAULT_SPEC_PVE = {
    WARRIOR     = "prot pve",
    PALADIN     = "holy pve",
    DEATHKNIGHT = "blood pve",
    SHAMAN      = "resto pve",
    HUNTER      = "surv pve",
    DRUID       = "resto pve",
    ROGUE       = "combat pve",
    PRIEST      = "disc pve",
    MAGE        = "fire pve",
    WARLOCK     = "destro pve",
}

-- ----------------------------------------------------------
-- Spec execution - whispers "talents spec <name>" to the current target.
-- Called from UI_Main spec buttons. Special-case: "da blood pve" expands
-- to "double aura blood pve" for the server bot command.
-- ----------------------------------------------------------
local function whisperSpec(specServerName)
    SendChatMessage("talents spec " .. specServerName, "WHISPER", nil, UnitName("target"))
end

local function mkSpec(serverName)
    return function() whisperSpec(serverName) end
end

ns.Data.SPEC_EXEC = {
    WARRIOR = {
        ["prot pve"]  = mkSpec("prot pve"),
        ["arms pve"]  = mkSpec("arms pve"),
        ["fury pve"]  = mkSpec("fury pve"),
        ["prot pvp"]  = mkSpec("prot pvp"),
        ["arms pvp"]  = mkSpec("arms pvp"),
        ["fury pvp"]  = mkSpec("fury pvp"),
    },
    PALADIN = {
        ["prot pve"]  = mkSpec("prot pve"),
        ["holy pve"]  = mkSpec("holy pve"),
        ["ret pve"]   = mkSpec("ret pve"),
        ["prot pvp"]  = mkSpec("prot pvp"),
        ["holy pvp"]  = mkSpec("holy pvp"),
        ["ret pvp"]   = mkSpec("ret pvp"),
    },
    DEATHKNIGHT = {
        ["blood pve"]     = mkSpec("blood pve"),
        ["frost pve"]     = mkSpec("frost pve"),
        ["unholy pve"]    = mkSpec("unholy pve"),
        ["da blood pve"]  = mkSpec("double aura blood pve"),
        ["blood pvp"]     = mkSpec("blood pvp"),
        ["frost pvp"]     = mkSpec("frost pvp"),
        ["unholy pvp"]    = mkSpec("unholy pvp"),
    },
    SHAMAN = {
        ["resto pve"] = mkSpec("resto pve"),
        ["ele pve"]   = mkSpec("ele pve"),
        ["enh pve"]   = mkSpec("enh pve"),
        ["resto pvp"] = mkSpec("resto pvp"),
        ["ele pvp"]   = mkSpec("ele pvp"),
        ["enh pvp"]   = mkSpec("enh pvp"),
    },
    HUNTER = {
        ["bm pve"]   = mkSpec("bm pve"),
        ["mm pve"]   = mkSpec("mm pve"),
        ["surv pve"] = mkSpec("surv pve"),
        ["bm pvp"]   = mkSpec("bm pvp"),
        ["mm pvp"]   = mkSpec("mm pvp"),
        ["surv pvp"] = mkSpec("surv pvp"),
    },
    DRUID = {
        ["bear pve"]    = mkSpec("bear pve"),
        ["resto pve"]   = mkSpec("resto pve"),
        ["cat pve"]     = mkSpec("cat pve"),
        ["balance pve"] = mkSpec("balance pve"),
        ["resto pvp"]   = mkSpec("resto pvp"),
        ["cat pvp"]     = mkSpec("cat pvp"),
        ["balance pvp"] = mkSpec("balance pvp"),
    },
    ROGUE = {
        ["subtlety pve"] = mkSpec("subtlety pve"),
        ["combat pve"]   = mkSpec("combat pve"),
        ["as pve"]       = mkSpec("as pve"),
        ["subtlety pvp"] = mkSpec("subtlety pvp"),
        ["combat pvp"]   = mkSpec("combat pvp"),
        ["as pvp"]       = mkSpec("as pvp"),
    },
    PRIEST = {
        ["holy pve"]    = mkSpec("holy pve"),
        ["disc pve"]    = mkSpec("disc pve"),
        ["shadow pve"]  = mkSpec("shadow pve"),
        ["holy pvp"]    = mkSpec("holy pvp"),
        ["disc pvp"]    = mkSpec("disc pvp"),
        ["shadow pvp"]  = mkSpec("shadow pvp"),
    },
    MAGE = {
        ["frost pve"]     = mkSpec("frost pve"),
        ["fire pve"]      = mkSpec("fire pve"),
        ["arcane pve"]    = mkSpec("arcane pve"),
        ["frostfire pve"] = mkSpec("frostfire pve"),
        ["frost pvp"]     = mkSpec("frost pvp"),
        ["fire pvp"]      = mkSpec("fire pvp"),
        ["arcane pvp"]    = mkSpec("arcane pvp"),
    },
    WARLOCK = {
        ["affli pve"]  = mkSpec("affli pve"),
        ["demo pve"]   = mkSpec("demo pve"),
        ["destro pve"] = mkSpec("destro pve"),
        ["affli pvp"]  = mkSpec("affli pvp"),
        ["demo pvp"]   = mkSpec("demo pvp"),
        ["destro pvp"] = mkSpec("destro pvp"),
    },
}

-- ----------------------------------------------------------
-- mod-playerbots strategy codes (discovered from OptimalRaidComp's STRAT_MAP).
-- Sent to a bot via whisper `nc +<code>` AFTER the spec whisper.
-- Paladin Blessings + Auras + Warrior Shouts + Priest/Shaman buffs all share
-- this flat table. Shaman totem sets are sent as `nc totems <set>` instead.
-- ----------------------------------------------------------
ns.Data.STRAT_CODE = {
    -- Paladin Blessings
    ["kings"]         = "+bstats",
    ["might"]         = "+bdps",
    ["wisdom"]        = "+bmana",
    ["sanctuary"]     = "+bhealth",
    -- Paladin Auras (and resistances shared with Priest shadow res)
    ["devotion"]      = "+barmor",
    ["retribution"]   = "+baoe",
    ["concentration"] = "+bcast",
    ["crusader"]      = "+bspeed",
    ["fire res"]      = "+rfire",
    ["frost res"]     = "+rfrost",
    ["shadow res"]    = "+rshadow",
    -- Warrior Shouts
    ["battle"]        = "+bdps",
    ["commanding"]    = "+bhealth",
    -- Hunter Aspects (toggle: DPS aspect is default; pick aotw for raid nature res)
    ["aotw"]          = "+rnature",
}

-- Shaman totem sets - not a strategy toggle; sent as `nc totems <set>`.
ns.Data.TOTEM_SETS = {
    "melee", "caster", "healing", "fire res", "frost res", "nature res",
}

ns.Data.TOTEM_TOOLTIPS = {
    ["melee"]      = "Earth: Strength of Earth\nFire: Flametongue / Magma\nWater: Healing Stream\nAir: Windfury",
    ["caster"]     = "Earth: Stoneskin\nFire: Totem of Wrath / Flametongue\nWater: Mana Spring\nAir: Wrath of Air",
    ["healing"]    = "Earth: Stoneskin\nFire: Flametongue\nWater: Mana Tide / Spring\nAir: Wrath of Air",
    ["fire res"]   = "Overrides Fire totem with Fire Resistance Totem.",
    ["frost res"]  = "Overrides Fire totem with Frost Resistance Totem.",
    ["nature res"] = "Overrides Air totem with Nature Resistance Totem.",
}

-- Returns (opt1List, opt2List, isShamanTotems) for a given class + spec.
-- Non-applicable classes return (nil, nil). opt1 = blessing/shout; opt2 = aura/res.
-- Shaman uses opt1 for totem sets (not a strategy code).
function ns.Data.GetOptionsForClassSpec(classToken, spec)
    if classToken == "PALADIN" then
        local opt1 = { "kings", "might", "wisdom" }
        if spec and string.find(spec, "prot", 1, true) then
            table.insert(opt1, "sanctuary")
        end
        local opt2 = { "devotion", "retribution", "concentration", "crusader",
                       "fire res", "frost res", "shadow res" }
        return opt1, opt2, false
    elseif classToken == "SHAMAN" then
        return ns.Data.TOTEM_SETS, nil, true
    elseif classToken == "WARRIOR" then
        return { "battle", "commanding" }, nil, false
    elseif classToken == "HUNTER" then
        -- opt1 = aspect override. "(none)" = keep DPS aspect (Hawk/Dragonhawk).
        -- "aotw" switches to Aspect of the Wild (+nature res, raid buff).
        return { "aotw" }, nil, false
    elseif classToken == "PRIEST" then
        -- Priest only has Prayer of Shadow Protection in 3.3.5 - no fire/frost.
        return nil, { "shadow res" }, false
    end
    return nil, nil, false
end

-- Parse a CSV like "kings,might,wisdom" into a string array. "(none)", nil,
-- and empty string all return an empty array.
function ns.Data.CsvToArray(s)
    local out = {}
    if type(s) == "string" and s ~= "" and s ~= "(none)" then
        for tok in s:gmatch("[^,]+") do
            tok = tok:match("^%s*(.-)%s*$")
            if tok ~= "" then table.insert(out, tok) end
        end
    end
    return out
end

-- Rotate pick: for a row of count N with opt1 = "kings,might,wisdom",
-- bot i (1-based) gets arr[((i-1) % #arr) + 1]. nil if arr is empty.
function ns.Data.PickRotated(arr, idx)
    if type(arr) ~= "table" or #arr == 0 then return nil end
    return arr[((idx - 1) % #arr) + 1]
end

-- Righteous Fury spell ID (3.3.5a). Protection paladins need it to hold
-- threat; Ret/Holy must not have it or they'll pull aggro. We control it
-- the same way as Bloodlust: via the bot's spell exclude list. `ss +<id>`
-- adds to the exclude list (bot won't cast); `ss -<id>` removes it (bot
-- will cast). The old `nc +/-rf` wording assumed a playerbots strategy
-- flag that doesn't exist on this realm.
local RIGHTEOUS_FURY_ID = 25780

-- Build the chat commands to whisper after a spec command. Returns an array.
-- For Shaman: opt1 is a totem set, so emits `nc totems <set>`.
-- For others:  opt1/opt2 are blessing/aura keys in STRAT_CODE.
-- Paladin extra: prot gets `ss -25780` (include Righteous Fury so the
-- tank can generate threat), ret/holy get `ss +25780` (exclude it so the
-- dps/healer doesn't pull aggro).
function ns.Data.BuildStratCommands(classToken, opt1, opt2, spec)
    local cmds = {}
    if classToken == "SHAMAN" then
        if opt1 and opt1 ~= "" and opt1 ~= "(none)" then
            table.insert(cmds, "nc totems " .. opt1)
        end
    else
        if opt1 and opt1 ~= "" and opt1 ~= "(none)" then
            local code = ns.Data.STRAT_CODE[opt1]
            if code then table.insert(cmds, "nc " .. code) end
        end
        if opt2 and opt2 ~= "" and opt2 ~= "(none)" then
            local code = ns.Data.STRAT_CODE[opt2]
            if code then table.insert(cmds, "nc " .. code) end
        end
    end

    if classToken == "PALADIN" and type(spec) == "string" then
        if string.find(spec, "prot", 1, true) then
            -- Prot: remove RF from the exclude list so they actually cast it
            table.insert(cmds, "ss -" .. RIGHTEOUS_FURY_ID)
        else
            -- Ret/Holy: add RF to the exclude list so they never cast it
            table.insert(cmds, "ss +" .. RIGHTEOUS_FURY_ID)
        end
    end
    return cmds
end

-- ----------------------------------------------------------
-- Raid presets (slotsByIdx format — positional, carries blessings/totems/
-- auras/resists per slot). Presets are grouped so common layouts can share
-- a template table; BuildDefaultPresetComp deep-copies when materializing
-- so every seeded comp is independent in the DB.
-- ----------------------------------------------------------
local function slot(classToken, spec, opt1, opt2)
    return {
        classToken = classToken,
        spec       = spec,
        opt1       = opt1 or "(none)",
        opt2       = opt2 or "(none)",
        isPlayer   = false,
    }
end

-- Onyxia 10: no Shaman / no Druid — tight melee-heavy comp with Warrior
-- fury for shout coverage. Frost DK (not blood) for stacked cleave; Paladin
-- ret covers blessing + melee damage; Hunter mm for burst + AotW raid buff.
-- Slot order is role-grouped: tank → melee → ranged → heal, alphabetical
-- by class within each role. With column-major 5-row groups that puts the
-- single tank + four melee in G1, then ranged + healers spilling into G2.
local LAYOUT_10_ONYXIA = {
    [1]  = slot("PALADIN",     "prot pve",   "sanctuary", "devotion"),
    [2]  = slot("DEATHKNIGHT", "frost pve"),
    [3]  = slot("PALADIN",     "ret pve",    "might",     "retribution"),
    [4]  = slot("ROGUE",       "combat pve"),
    [5]  = slot("WARRIOR",     "fury pve",   "battle"),
    [6]  = slot("HUNTER",      "mm pve",     "aotw"),
    [7]  = slot("MAGE",        "fire pve"),
    [8]  = slot("WARLOCK",     "demo pve"),
    [9]  = slot("PALADIN",     "holy pve",   "kings",     "concentration"),
    [10] = slot("PRIEST",      "disc pve",   nil,         "shadow res"),
}

-- Ulduar 10: unique (Druid resto + Shaman resto + Warlock DESTRO for
-- Curse-of-Elements synergy on heavy-magic boss fights). Role-grouped:
-- two tanks open G1, single melee + three ranged finish G1, the four
-- healers tail into G2.
local LAYOUT_10_ULDUAR = {
    [1]  = slot("DEATHKNIGHT", "blood pve"),
    [2]  = slot("PALADIN",     "prot pve",   "sanctuary", "devotion"),
    [3]  = slot("PALADIN",     "ret pve",    "might",     "retribution"),
    [4]  = slot("HUNTER",      "surv pve",   "aotw"),
    [5]  = slot("MAGE",        "fire pve"),
    [6]  = slot("WARLOCK",     "destro pve"),
    [7]  = slot("DRUID",       "resto pve"),
    [8]  = slot("PALADIN",     "holy pve",   "kings",     "concentration"),
    [9]  = slot("PRIEST",      "disc pve",   nil,         "shadow res"),
    [10] = slot("SHAMAN",      "resto pve",  "healing"),
}

-- 10-man "mm-hunter" layout — shared by Trial of the Crusader 10 and
-- Ruby Sanctum 10 (single-target focused; Hunter mm for steady sustained
-- damage with AotW providing raid nature res). Role-grouped: tanks +
-- melee fill G1, ranged + healers fill G2.
local LAYOUT_10_MM = {
    [1]  = slot("DEATHKNIGHT", "blood pve"),
    [2]  = slot("PALADIN",     "prot pve",   "sanctuary", "devotion"),
    [3]  = slot("PALADIN",     "ret pve",    "might",     "retribution"),
    [4]  = slot("ROGUE",       "combat pve"),
    [5]  = slot("HUNTER",      "mm pve",     "aotw"),
    [6]  = slot("MAGE",        "fire pve"),
    [7]  = slot("WARLOCK",     "demo pve"),
    [8]  = slot("PALADIN",     "holy pve",   "kings",     "concentration"),
    [9]  = slot("PRIEST",      "disc pve",   nil,         "shadow res"),
    [10] = slot("SHAMAN",      "resto pve",  "healing"),
}

-- ICC 10: survival hunter (better AoE trash, consistent uptime on Lich King).
-- Same role-grouped layout as the MM template, but the Hunter is surv.
local LAYOUT_10_ICC = {
    [1]  = slot("DEATHKNIGHT", "blood pve"),
    [2]  = slot("PALADIN",     "prot pve",   "sanctuary", "devotion"),
    [3]  = slot("PALADIN",     "ret pve",    "might",     "retribution"),
    [4]  = slot("ROGUE",       "combat pve"),
    [5]  = slot("HUNTER",      "surv pve",   "aotw"),
    [6]  = slot("MAGE",        "fire pve"),
    [7]  = slot("WARLOCK",     "demo pve"),
    [8]  = slot("PALADIN",     "holy pve",   "kings",     "concentration"),
    [9]  = slot("PRIEST",      "disc pve",   nil,         "shadow res"),
    [10] = slot("SHAMAN",      "resto pve",  "healing"),
}

-- 25-man layouts differ only in which Hunter carries Aspect of the Wild
-- (mm in the MM variant, surv in the SURV variant). Everything else is
-- shared. Role-grouped column-major layout: G1 = 4 tanks + 1 melee, G2 =
-- the rest of melee, G3-G4 = ranged, G5 = healers.
-- MM variant: Onyxia 25, Trial of the Crusader 25, Ruby Sanctum 25.
local LAYOUT_25_MM = {
    -- Tanks (G1 slot 1-4)
    [1]  = slot("DEATHKNIGHT", "blood pve"),
    [2]  = slot("DRUID",       "bear pve"),
    [3]  = slot("PALADIN",     "prot pve",  "sanctuary", "devotion"),
    [4]  = slot("PALADIN",     "prot pve",  "sanctuary", "devotion"),
    -- Melee (G1 slot 5, G2 slot 6-11)
    [5]  = slot("DEATHKNIGHT", "frost pve"),
    [6]  = slot("PALADIN",     "ret pve",   "might",     "retribution"),
    [7]  = slot("ROGUE",       "combat pve"),
    [8]  = slot("ROGUE",       "combat pve"),
    [9]  = slot("SHAMAN",      "enh pve",   "melee"),
    [10] = slot("WARRIOR",     "fury pve",  "battle"),
    [11] = slot("WARRIOR",     "arms pve",  "commanding"),
    -- Ranged (G3 slot 12-15, G4 slot 16-20)
    [12] = slot("DRUID",       "balance pve"),
    [13] = slot("HUNTER",      "mm pve",    "aotw"),
    [14] = slot("HUNTER",      "surv pve"),
    [15] = slot("MAGE",        "fire pve"),
    [16] = slot("MAGE",        "fire pve"),
    [17] = slot("PRIEST",      "shadow pve"),
    [18] = slot("SHAMAN",      "ele pve",   "caster"),
    [19] = slot("WARLOCK",     "demo pve"),
    [20] = slot("WARLOCK",     "affli pve"),
    -- Healers (G5 slot 21-25)
    [21] = slot("DRUID",       "resto pve"),
    [22] = slot("PALADIN",     "holy pve",  "kings",     "concentration"),
    [23] = slot("PRIEST",      "disc pve",  nil,         "shadow res"),
    [24] = slot("PRIEST",      "holy pve"),
    [25] = slot("SHAMAN",      "resto pve", "healing"),
}

-- SURV variant: Ulduar 25 and Icecrown Citadel 25 (AoE + nature-res-heavy
-- content — surv hunter provides the aura, mm stays secondary). Same
-- role-grouped layout as the MM variant; only the Hunter aura assignment
-- differs (surv carries aotw, mm has none).
local LAYOUT_25_SURV = {
    -- Tanks (G1 slot 1-4)
    [1]  = slot("DEATHKNIGHT", "blood pve"),
    [2]  = slot("DRUID",       "bear pve"),
    [3]  = slot("PALADIN",     "prot pve",  "sanctuary", "devotion"),
    [4]  = slot("PALADIN",     "prot pve",  "sanctuary", "devotion"),
    -- Melee (G1 slot 5, G2 slot 6-11)
    [5]  = slot("DEATHKNIGHT", "frost pve"),
    [6]  = slot("PALADIN",     "ret pve",   "might",     "retribution"),
    [7]  = slot("ROGUE",       "combat pve"),
    [8]  = slot("ROGUE",       "combat pve"),
    [9]  = slot("SHAMAN",      "enh pve",   "melee"),
    [10] = slot("WARRIOR",     "fury pve",  "battle"),
    [11] = slot("WARRIOR",     "arms pve",  "commanding"),
    -- Ranged (G3 slot 12-15, G4 slot 16-20)
    [12] = slot("DRUID",       "balance pve"),
    [13] = slot("HUNTER",      "surv pve",  "aotw"),
    [14] = slot("HUNTER",      "mm pve"),
    [15] = slot("MAGE",        "fire pve"),
    [16] = slot("MAGE",        "fire pve"),
    [17] = slot("PRIEST",      "shadow pve"),
    [18] = slot("SHAMAN",      "ele pve",   "caster"),
    [19] = slot("WARLOCK",     "demo pve"),
    [20] = slot("WARLOCK",     "affli pve"),
    -- Healers (G5 slot 21-25)
    [21] = slot("DRUID",       "resto pve"),
    [22] = slot("PALADIN",     "holy pve",  "kings",     "concentration"),
    [23] = slot("PRIEST",      "disc pve",  nil,         "shadow res"),
    [24] = slot("PRIEST",      "holy pve"),
    [25] = slot("SHAMAN",      "resto pve", "healing"),
}

-- 5-man layout. Role-grouped: tank → melee → ranged → heal, alphabetical
-- by class within each role.
local LAYOUT_5 = {
    [1] = slot("PALADIN", "prot pve",  "sanctuary", "devotion"),
    [2] = slot("ROGUE",   "combat pve"),
    [3] = slot("HUNTER",  "surv pve",  "aotw"),
    [4] = slot("MAGE",    "fire pve"),
    [5] = slot("DRUID",   "resto pve"),
}

ns.Data.RAID_PRESETS = {
    -- 5-man
    ["5man"]                      = { size = 5,  slotsByIdx = LAYOUT_5 },

    -- 10-man
    ["Onyxia's Lair 10"]                  = { size = 10, slotsByIdx = LAYOUT_10_ONYXIA },
    ["Ulduar 10"]                         = { size = 10, slotsByIdx = LAYOUT_10_ULDUAR },
    ["Trial of the Crusader 10"]          = { size = 10, slotsByIdx = LAYOUT_10_MM     },
    ["Icecrown Citadel 10"]               = { size = 10, slotsByIdx = LAYOUT_10_ICC    },
    ["Ruby Sanctum 10"]                   = { size = 10, slotsByIdx = LAYOUT_10_MM     },

    -- 25-man
    ["Onyxia's Lair 25"]                  = { size = 25, slotsByIdx = LAYOUT_25_MM   },
    ["Ulduar 25"]                         = { size = 25, slotsByIdx = LAYOUT_25_SURV },
    ["Trial of the Crusader 25"]          = { size = 25, slotsByIdx = LAYOUT_25_MM   },
    ["Icecrown Citadel 25"]               = { size = 25, slotsByIdx = LAYOUT_25_SURV },
    ["Ruby Sanctum 25"]                   = { size = 25, slotsByIdx = LAYOUT_25_MM   },
}

-- Bump whenever the set of default preset NAMES changes or their layout
-- materially changes. Persistence compares this to db.presetsVersion to
-- decide whether a migration sweep is required (legacy purge + reseed).
--   v1 = count-based Naxx/Ulduar/ToC/ICC × 10/25 (8 entries)
--   v2 = positional 11-preset set, but with curly-apostrophe "Onyxia's"
--        names that WoW 3.3.5a FrizQT does not render correctly
--   v3 = same 11 presets but with ASCII apostrophe in "Onyxia's Lair"
--   v4 = refreshed layouts: Onyxia 10 rebuilt (Warrior+Pal ret+Hunter mm),
--        ToC/Ruby 10 use mm hunter, ICC 10 stays surv, Ulduar 10 swaps
--        priest/druid slot order. 25-man split into MM variant (Onyxia /
--        ToC / Ruby) and SURV variant (Ulduar / ICC).
--   v5 = same 11 presets but every slot list is reordered tank → melee →
--        ranged → heal (then alphabetical by class). With column-major
--        5-row groups this clusters tanks into G1, healers into the
--        last group, melee/ranged in between.
ns.Data.PRESETS_VERSION = 5

-- Names to purge when crossing a specific version boundary. Persistence
-- applies only the lists for gaps the user actually traverses, so someone
-- already at v2 keeps their edits to "Ulduar 25" etc. when moving to v3.
--
-- v1 → v2: old count-based Naxx/Ulduar/ToC/ICC 10/25 (same names carried
-- the old layout; purge so the positional v2 layout takes over).
ns.Data.LEGACY_PRESET_NAMES_V1 = {
    "Naxxramas 10", "Naxxramas 25",
    "Ulduar 10", "Ulduar 25",
    "Trial of the Crusader 10", "Trial of the Crusader 25",
    "Icecrown Citadel 10", "Icecrown Citadel 25",
}
-- v2 → v3: curly-apostrophe Onyxia names rendered as garbage in WoW's
-- FrizQT font. Replaced by ASCII-apostrophe variants; old ones purged.
ns.Data.LEGACY_PRESET_NAMES_V2 = {
    "Onyxia\xE2\x80\x99s Lair 10",
    "Onyxia\xE2\x80\x99s Lair 25",
}
-- v3 → v4: all 11 default presets get content refreshes (layouts, specs,
-- variants). Names are unchanged but content differs — purge the stale
-- v3 entries so the v4 seed replaces them. Users who edited these at v3
-- will lose their edits: this was explicit user intent when handing off
-- the new preset strings ("voici les nouvelle version").
ns.Data.LEGACY_PRESET_NAMES_V3 = {
    "5man",
    "Onyxia's Lair 10", "Ulduar 10", "Trial of the Crusader 10",
    "Icecrown Citadel 10", "Ruby Sanctum 10",
    "Onyxia's Lair 25", "Ulduar 25", "Trial of the Crusader 25",
    "Icecrown Citadel 25", "Ruby Sanctum 25",
}
-- v4 → v5: same 11 names, but slot order is now role-grouped
-- (tank → melee → ranged → heal, alphabetical by class within role).
-- Purge so the new ordering replaces any stale v4 entries.
ns.Data.LEGACY_PRESET_NAMES_V4 = {
    "5man",
    "Onyxia's Lair 10", "Ulduar 10", "Trial of the Crusader 10",
    "Icecrown Citadel 10", "Ruby Sanctum 10",
    "Onyxia's Lair 25", "Ulduar 25", "Trial of the Crusader 25",
    "Icecrown Citadel 25", "Ruby Sanctum 25",
}

-- Canonical preset name order — used by the Persistence seed step and by the
-- Settings "Restore default presets" action. Explicit list so order is stable
-- regardless of pairs() iteration.
ns.Data.DEFAULT_PRESET_NAMES = {
    "5man",
    "Onyxia's Lair 10",
    "Ulduar 10",
    "Trial of the Crusader 10",
    "Icecrown Citadel 10",
    "Ruby Sanctum 10",
    "Onyxia's Lair 25",
    "Ulduar 25",
    "Trial of the Crusader 25",
    "Icecrown Citadel 25",
    "Ruby Sanctum 25",
}

-- Return a fresh deep-copy of a default preset in the saved-comp format.
-- Deep-copies the slotsByIdx so mutations in the DB don't leak back into
-- the shared template. Also reconstructs `rows` (count-based) for legacy
-- coverage/summary scans that still iterate rows.
-- Returns nil if the name isn't a built-in preset.
function ns.Data.BuildDefaultPresetComp(name)
    local tmpl = ns.Data.RAID_PRESETS and ns.Data.RAID_PRESETS[name]
    if type(tmpl) ~= "table" or type(tmpl.slotsByIdx) ~= "table" then return nil end
    local size = tonumber(tmpl.size) or tonumber(tostring(name):match("(%d+)%s*$")) or 25
    local byIdx, rows = {}, {}
    for i = 1, size do
        local r = tmpl.slotsByIdx[i]
        if r then
            byIdx[i] = {
                classToken = r.classToken,
                spec       = r.spec,
                opt1       = r.opt1 or "(none)",
                opt2       = r.opt2 or "(none)",
                isPlayer   = r.isPlayer and true or false,
            }
            table.insert(rows, {
                classToken = r.classToken,
                spec       = r.spec,
                count      = 1,
                opt1       = r.opt1 or "(none)",
                opt2       = r.opt2 or "(none)",
                isPlayer   = false,
            })
        end
    end
    return { rows = rows, slotsByIdx = byIdx, size = size }
end

-- ----------------------------------------------------------
-- Shared helpers
-- ----------------------------------------------------------

-- Turn a CSV like "kings,might" into a set { kings=true, might=true }. An
-- input of "(none)", empty string, or nil returns an empty set. Used by
-- Comp (coverage scan) and Roster (provides-chip state). Previously
-- duplicated as `splitSet` in UI_TabComp.lua and `splitSetLocal` in
-- UI_TabRoster.lua.
function ns.Data.SplitSet(s)
    local set = {}
    if type(s) ~= "string" or s == "" or s == "(none)" then return set end
    for tok in s:gmatch("[^,]+") do
        tok = tok:match("^%s*(.-)%s*$")
        if tok ~= "" then set[tok] = true end
    end
    return set
end

-- UI-Classes-Circles atlas texcoords, keyed by classToken. Used by the
-- Comp tab slot widget and the Roster row avatar. One table, two call
-- sites; previously duplicated.
ns.Data.CLASS_ICON = {
    WARRIOR     = { 0,    0.25, 0,    0.25 },
    MAGE        = { 0.25, 0.5,  0,    0.25 },
    ROGUE       = { 0.5,  0.75, 0,    0.25 },
    DRUID       = { 0.75, 1,    0,    0.25 },
    HUNTER      = { 0,    0.25, 0.25, 0.5  },
    SHAMAN      = { 0.25, 0.5,  0.25, 0.5  },
    PRIEST      = { 0.5,  0.75, 0.25, 0.5  },
    WARLOCK     = { 0.75, 1,    0.25, 0.5  },
    PALADIN     = { 0,    0.25, 0.5,  0.75 },
    DEATHKNIGHT = { 0.25, 0.5,  0.5,  0.75 },
}

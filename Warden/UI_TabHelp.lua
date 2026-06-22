-- =====================================================
-- Warden - UI_TabHelp.lua
-- TASKS.md §6 full rework: two-column reference card with masthead,
-- hair-rule section dividers, typographic hierarchy, word-wrapped
-- descriptions, and shortcut chips. User-voice copy, no (V1)/(V4) tags.
-- =====================================================

local _, ns = ...
ns.UI.Tabs      = ns.UI.Tabs      or {}
ns.UI.Tabs.Help = ns.UI.Tabs.Help or {}

-- §6.12 - inline "keycap"-style marker for shortcut strings. Renders as a
-- bright warm-gold `[F]` so keys pop against the description prose.
local function kbd(t) return "|cffffebbf[" .. t .. "]|r" end

local SECTIONS = {
    {
        title = "Navigation",
        items = {
            { "Tabs",             "Six tabs along the bottom edge - click or press " .. kbd("1") .. "-" .. kbd("6") .. "." },
            { "X",                "Close the window (" .. kbd("ESC") .. " works too)." },
            { "Window size",      "Pick a preset (Small / Medium / Large / XL) in Settings. Mousewheel zoom was removed." },
            { "Status footer",    "The persistent bar on every tab shows LIVE dot, current target, queue depth, tracked members, BL state, and slash-command hint. Updates on roster/target events and every 0.5s." },
            { "Minimap button",   "Left-click toggles the window. " .. kbd("Shift-left") .. " opens Settings. " .. kbd("Middle") .. " toggles the WardenSword HUD. Right-click opens Help. Drag to orbit." },
            { "Slash commands",   kbd("/warden") .. " / " .. kbd("/wden") .. " toggles the main window. " .. kbd("/ws") .. " toggles the WardenSword HUD." },
        },
    },
    {
        title = "Spec tab",
        items = {
            { "Target card",     "Shows who you're targeting - portrait, level, class, and faction. The hint line beneath is the raw whisper Warden will send when you click a spec tile." },
            { "Prev target",     kbd("< prev target") .. " is a secure button that runs /targetlasttarget - it never trips Blizzard's protected-action taint warning." },
            { "History popup",   "Click " .. kbd("history v") .. " to reveal the last six targets as secure buttons. Click an entry to re-target. The popup auto-hides when you enter combat; secure buttons don't rebind mid-combat." },
            { "Autogear / Buffs", "The right side of the target card broadcasts `autogear` to PARTY or `nc +worldbuff` to RAID." },
            { "N available",     "Meta in the Specs panel header shows how many specs the target's class exposes." },
            { "Spec tiles",      "Four-column grid of specs available to the target's class. Each tile shows a class-colored name and a `pve - role` subtitle. The recommended PvE spec gets a gold border and the `talent preview` hint." },
            { "Click a tile",    "Sends the talent whisper and remembers this bot by GUID so Re-Spec re-applies after a reconnect." },
        },
    },
    {
        title = "Controls tab",
        items = {
            { "Movement",        "Summon, Follow, Stay, Free, Release, Drink. Top row is the hot path - Summon is the primary." },
            { "Strategy",        "AoE on/off, burn cooldowns, face-behind vs no-flank. Three inline groups, two buttons each." },
            { "Marks & formation", "Skull and Moon mark+attack/CC, disperse distance dropdown, formation dropdown with set/check." },
            { "Role commands",   "Per-role commands in a 5x4 matrix. Atk is the primary launch; Stay/Fol/Flee are safe stone buttons with amber/gold/red text. Shift-click flashes the affected row." },
            { "BL toggle",       "The " .. kbd("BL") .. " pill on the master footer toggles Bloodlust/Heroism. Green = ON; amber = OFF. Clicking whispers " .. kbd("ss +/-2825") .. " (Horde shamans) or " .. kbd("ss +/-32182") .. " (Alliance shamans) to toggle the bot's spell-exclude list for Lust/Heroism." },
            { "Danger zone",     "Irreversible actions. Smart ReSpec is safe (targeted retry). Reset AI, Hard ReSpec, and Cleanup all ask for confirmation before running." },
            { "Summon by class", "Bottom panel - 2x5 grid of class-colored buttons. One click sends " .. kbd(".warstormbot bot addclass <class>") .. " to spawn a single bot of that class - same command the Comp Build pipeline uses, just one at a time from the Controls tab." },
        },
    },
    {
        title = "WardenSword (mid-fight HUD)",
        items = {
            { "What it is",      "A small, draggable floating panel that surfaces the handful of Warden actions you hit while tanking a pull - summon / move / aoe / burn / bloodlust / role orders - without opening the main window." },
            { "Open / close",    kbd("/ws") .. " toggles. " .. kbd("Middle-click") .. " the minimap button works too. " .. kbd("x") .. " on the header hides it; reopen with the same slash." },
            { "Lock / unlock",   "The " .. kbd("o") .. " circle on the header toggles drag-lock. Locked = no accidental drags while tanking. State persists across /reload." },
            { "Auto-show",       "By default the HUD auto-opens on combat start. Turn off under Settings -> WardenSword -> Auto-show in combat." },
            { "Movement",        "2x2 grid: Summon / Follow (all bots) / Stay / Flee. Top-left is the hot path." },
            { "Strategy",        "AoE toggle, Burn cooldowns toggle, Skull (mark target + attack)." },
            { "Role matrix",     "Optional 3x3 grid - TANK / HEAL / DPS rows, each with Atk / Follow / Stay. Routes through " .. kbd("@tank") .. " / " .. kbd("@heal") .. " / " .. kbd("@dps") .. " scoping so you can split the raid on demand." },
            { "Bloodlust",       "Full-width button at the bottom. Turns red when ON. Whispers " .. kbd("ss +/-2825") .. " (Horde) or " .. kbd("ss +/-32182") .. " (Alliance) to every shaman in group - toggles the spell exclude list so they will or will not cast Lust/Heroism." },
            { "Feedback",        "Each click briefly flashes the button's gold rim - no popup, so the HUD stays out of your way mid-pull." },
            { "Settings",        "Settings tab has a WARDENSWORD panel: auto-show, status strip, roles row, start locked, hide-minimap-in-combat, density, transparency slider, and Reset HUD position." },
            { "Player guard",    "Every WardenSword action routes through the same engine helpers as the main tabs, so characters flagged " .. kbd("[P]") .. " in Roster / Bot Comp are skipped automatically." },
            { kbd("/ws"),         "Toggle the HUD." },
            { kbd("/ws <action>"), "Direct fire: " .. kbd("summon") .. " / " .. kbd("follow") .. " / " .. kbd("stay") .. " / " .. kbd("flee") .. " / " .. kbd("aoe") .. " / " .. kbd("burn") .. " / " .. kbd("skull") .. " / " .. kbd("bl") .. "." },
            { kbd("/ws @role act"), "Role-scoped: " .. kbd("@tank follow|atk|stay") .. ", " .. kbd("@heal follow|atk|stay") .. ", " .. kbd("@dps follow|atk|stay") .. "." },
            { kbd("/ws lock|unlock|reset"), "Position management for the HUD." },
            { kbd("/ws config"),  "Open Warden Settings (WardenSword panel)." },
            { kbd("/ws help"),    "Print the full command reference in chat." },
        },
    },
    {
        title = "Bot Comp tab",
        items = {
            { "What is a comp",  "A planned raid roster: class + spec + buff assignments per slot. Saved locally under a name you pick and shareable as a single paste-string." },
            { "Sizes",           "Pick raid size - the grid adapts from 5 through 40. Columns are groups (G1 to Gn); rows are positions within a group." },
            { "Grid slot",       "Each slot shows a 14px class circle icon, class-colored name, and spec. Empty slots show `+`. Click to select; right-click to remove." },
            { "Chip tray",       "Ten class chips. " .. kbd("Click") .. " adds one to the next empty slot. " .. kbd("Shift-click") .. " prompts for N copies. " .. kbd("Drag") .. " a chip onto a slot to drop it there (overwrites the existing slot)." },
            { "Sidebar",         "Slot detail (top), coverage (middle), summary + Build (bottom), FILE row. Scrolls inside the fixed panel height." },
            { "Slot detail",     "CLASS / SPEC / BLESSING-TOTEM / AURA-RESIST dropdowns set the whispered talent + `nc +X` strategies. " .. kbd("move") .. " shifts to next empty slot. " .. kbd("duplicate") .. " copies the slot. " .. kbd("remove") .. " clears it. " .. kbd("[P]") .. " toggles the human-player flag." },
            { "Player auto-move", "At Build time, if any slot is flagged " .. kbd("[P]") .. " and you're in a raid with assistant/leader rights, Warden calls " .. kbd("SetRaidSubgroup") .. " to move you into that slot's group before spawning any bots. Fixes the 'caster group drifts to G2 because the player is stuck in G1' problem - just drop the " .. kbd("[P]") .. " slot in the column you want to be in." },
            { "Coverage",        "Scannable status of key raid buffs. " .. kbd("[+]") .. " (green) = covered by at least one filled slot. " .. kbd("[!]") .. " (amber) = nobody in the comp is assigned to provide it. Kings / Might / Wisdom / Sanct / Melee / Caster / Tank / Frost / Fire / Shadow / Nature all get a pill." },
            { "Filled counter",  "The `N / max` in the summary is the filled count. The Build button enables as soon as at least one slot has a class." },
            { "Build",           "Primary CTA. Spawns `.warstormbot bot addclass` for each non-player slot and whispers the planned spec/strats as each bot joins. Slots flagged as players are skipped." },
            { "save / load / delete", kbd("save") .. " stores the current comp (name + size + slot positions + isPlayer flags) to a local preset slot. " .. kbd("load") .. " restores it by name. " .. kbd("delete") .. " removes the saved comp named in the COMP box (confirmation required). All comps — including the default raid presets — live in WardenDB.comps and are fully editable. Use Settings -> Maintenance -> Restore default presets to re-seed any defaults you've deleted." },
            { "import / export", kbd("export") .. " produces a portable " .. kbd("WRDN2:") .. " string that carries the full comp (name, size, slot positions, isPlayer, blessings). " .. kbd("import") .. " accepts the same string. " .. kbd("WRDN1:") .. " strings from older versions still parse (loose slot order, no player flags)." },
            { "clear / cleanup", kbd("clear") .. " empties the grid locally (no server command). " .. kbd("cleanup") .. " sends `.warstormbot bot remove *` to despawn every bot in the raid (confirmation popup)." },
            { "Presets dropdown", "Lists every saved comp grouped by raid size. 11 default raid presets (5-man + Onyxia / Ulduar / ToC / ICC / Ruby Sanctum 10 & 25) are seeded on first use and behave like any other saved comp — fully editable and deletable. Picking one loads the grid; your typed comp name is replaced." },
        },
    },
    {
        title = "Roster tab",
        items = {
            { "Filter",          "All / Tanks / Healers / DPS dropdown, plus a name search and Refresh." },
            { "Sections",        "Rows group under TANKS / HEALERS / DPS headers, each with a count pill. Role is inferred from the tracked spec." },
            { "Row layout",      kbd("[P]") .. " | checkbox | class avatar | two-line name block (class-colored name + `Class - spec`) | spec dropdown | provides chips | Re-Spec button." },
            { "Player flag [P]", "Click the per-row " .. kbd("[P]") .. " to mark that character as a human player (NOT a bot). Flag persists by name in WardenDB.playerFlags. Flagged members are skipped by Re-Spec, Re-Spec All/Selected, auto-spec-on-join, and build whispers. Your own character is auto-flagged on first login." },
            { "Provides chips",  "Per-class buff abbreviations (KNG / MGT / WIS / SAN / SoE / WF / FT / MS / BS / CS / ASP). Gold = THIS slot is assigned to cast that buff in the current comp. Muted = not assigned. Priests, mages, warlocks, and rogues show no chips." },
            { "Re-Spec",         "The row button re-whispers the selected spec to the bot. Disabled for your own row and for any row flagged " .. kbd("[P]") .. "." },
            { "Bottom bar",      kbd("Re-Spec All Tracked") .. " re-whispers every tracked raid member. " .. kbd("Re-Spec Selected") .. " only fires on rows with the checkbox ticked. Both skip flagged players." },
        },
    },
    {
        title = "Settings tab",
        items = {
            { "Auto-spec",       "When a bot joins during a Build, whisper their planned spec automatically." },
            { "Party -> Raid",   "Promote the party to a raid when a Build reaches five or more bots." },
            { "Window size",     "Small (0.80) / Medium (1.00) / Large (1.20) / XL (1.40) dropdown. Applies live." },
            { "WardenSword",     "Dedicated panel with HUD checkboxes (auto-show, status, roles, start locked, hide minimap in combat), density dropdown, transparency slider, and Reset HUD position." },
            { "Session stats",   "Spawned / Spec'd / Pending / Tracked / Send queue / Whisper queue. Refreshes every 0.5s." },
            { "Reset minimap",   "Snaps the minimap button back to its default 225-degree position." },
            { "Clear GUID tracking", "Wipes assignedSpecs. Re-Spec then falls back to FIFO." },
            { "Restore default presets", "Re-seeds any of the 11 built-in raid presets that have been deleted. Never overwrites a preset you've edited." },
        },
    },
    {
        title = "Auto-behavior",
        items = {
            { "Paladin RF",      "Righteous Fury (spell 25780) is controlled via the bot's spell-exclude list. Prot paladins get " .. kbd("ss -25780") .. " (include RF so they can tank); Ret and Holy get " .. kbd("ss +25780") .. " (exclude RF so they don't pull aggro). Fires automatically after every Paladin spec whisper." },
            { "Buff limits",     "Each Paladin casts one blessing, each Shaman one totem set, each Hunter one aspect. Over-selection shows a warning chip." },
            { "GUID tracking",   "Each bot's spec plus opt1 / opt2 are remembered by GUID. Re-Spec re-applies exactly after a server drop." },
            { "Whisper cadence", "Warden whispers specs every 0.35s. Bot spawns stay paced at 0.70s." },
            { "Bloodlust",       "Whispered directly to each shaman via the spell-exclude list: " .. kbd("ss -2825") .. " to let a Horde shaman cast Bloodlust, " .. kbd("ss +2825") .. " to block it (same with " .. kbd("32182") .. " for Alliance Heroism). Warden picks the faction automatically. The OFF default protects pulls that don't want lust." },
            { "Player guard",    "Every automated whisper / summon checks the per-name player flag and skips flagged characters. The player guard prevents Warden from touching real raiders' specs when you run it alongside humans." },
            { "Empty slot guard", "Build / Re-Spec iterate slots with explicit nil checks, so a single empty slot in the middle of the grid no longer halts the entire summon loop." },
        },
    },
    {
        title = "Slash commands",
        items = {
            { kbd("/warden"),    "Toggle the main window." },
            { kbd("/wden"),      "Shorter alias for " .. kbd("/warden") .. "." },
            { kbd("/ws"),        "Toggle the WardenSword mid-fight HUD." },
            { kbd("/wardensword"), "Longer alias for " .. kbd("/ws") .. "." },
            { kbd("/wardenlog"), "Log viewer + debug toggles. See the next section for every subcommand." },
        },
    },
    {
        title = "Debug & logging",
        items = {
            { "Two-tier model",
              "Warden has two independent loggers. The " .. kbd("global INFO") .. " trace is a single on/off switch that drains verbose prints from the whole addon into SavedVariables. The " .. kbd("per-feature DEBUG") .. " trace lets you flip one subsystem at a time - each category echoes to the chat frame live AND persists to the same log, so you can watch behavior unfold mid-pull without alt-tabbing out. ERRORS are always captured regardless of either switch." },
            { "Log viewer",
              kbd("/wardenlog") .. " prints the last 20 entries. " .. kbd("tail N") .. " shows the last N, " .. kbd("all") .. " shows the whole log, " .. kbd("clear") .. " wipes it, " .. kbd("status") .. " reports on/off state + entry count + which debug categories are active." },
            { kbd("/wardenlog on"),
              "Enable the GLOBAL verbose logger. Warden will start writing INFO/WARN entries covering whisper traffic, build lifecycle, and engine state to " .. kbd("WardenLog") .. " in SavedVariables. OFF by default for production." },
            { kbd("/wardenlog off"),
              "Disable the global verbose logger. Errors are still captured." },
            { kbd("/wardenlog status"),
              "Dump current state: global on/off, entry count, and the list of debug categories currently ON." },
            { kbd("/wardenlog clear"),
              "Wipe " .. kbd("WardenLog") .. " entirely (both INFO and DEBUG entries)." },
            { kbd("/wardenlog tail N"),
              "Print the last N log entries in your chat frame (without clearing them)." },
            { kbd("/wardenlog all"),
              "Print the entire log in your chat frame." },
            { kbd("/wardenlog debug"),
              "Show the current per-category toggles with ON/OFF state for each." },
            { kbd("/wardenlog debug help"),
              "List every known debug category + usage examples." },
            { kbd("/wardenlog debug <cat> on"),
              "Turn on trace for one category. Categories: " ..
              kbd("master") .. " (window Toggle/Show/Hide/X/tab switch), " ..
              kbd("slash") .. " (slash-command entries), " ..
              kbd("respec") .. " (per-row + bulk Re-Spec clicks), " ..
              kbd("whisper") .. " (whisper queue push + drain), " ..
              kbd("build") .. " (StartBuild + plan dump incl. isPlayer flags), " ..
              kbd("roster") .. " (roster rebuild triggers), " ..
              kbd("spec") .. " (Spec-tab target changes), " ..
              kbd("sword") .. " (WardenSword Show/Hide/Toggle + auto-show), " ..
              kbd("combat") .. " (PLAYER_REGEN_DISABLED/ENABLED transitions), " ..
              kbd("minimap") .. " (minimap click routing + combat-hide), " ..
              kbd("persist") .. " (DB load/save on login/logout), " ..
              kbd("comp") .. " (comp Build/save/load), " ..
              kbd("controls") .. " (every send() in Controls tab), " ..
              kbd("settings") .. " (every checkbox toggle)." },
            { kbd("/wardenlog debug <cat> off"),
              "Turn off trace for one category. Alias: " .. kbd("reset") .. " below." },
            { kbd("/wardenlog debug all on"),
              "Firehose: enable every category simultaneously. Useful when you don't know which subsystem is misbehaving. Expect heavy chat spam." },
            { kbd("/wardenlog debug all off"),
              "Disable every category (equivalent to " .. kbd("reset") .. ")." },
            { kbd("/wardenlog debug reset"),
              "Clear every toggle to off at once - tidy way to leave the log alone for production." },
            { "Chat echo format",
              "When a debug category fires, you see " .. kbd("[Warden/<cat>]") .. " in light blue in the default chat frame, plus the same line persisted to " .. kbd("WardenLog") .. " with a " .. kbd("[DEBUG]") .. " level tag." },
            { "Reading the log file",
              "Toggles and entries live in " .. kbd("WTF/Account/<acct>/SavedVariables/Warden.lua") .. ". Look for " .. kbd("WardenDebug") .. " (toggle table), " .. kbd("WardenLog") .. " (entries), and " .. kbd("WardenLogEnabled") .. " (global switch)." },
            { "Typical workflow",
              "Pick the category closest to the misbehavior, turn it on, reproduce once, " .. kbd("/wardenlog tail 30") .. " to eyeball the trace, fix (or share with maintainer), " .. kbd("/wardenlog debug reset") .. " when done." },
        },
    },
}

-- TASKS.md §6.3 column constants.
local PAD_L, PAD_R = 14, 18
local KEY_W        = 160
local GUTTER       = 14

function ns.UI.Tabs.Help.BuildInto(pane)
    local scroll = CreateFrame("ScrollFrame", "WardenHelpScroll", pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     pane, "TOPLEFT",      8,  -8)
    -- Previous bottom offset of 8 left the scrollbar track grazing the
    -- master footer. Bump to 32 so the track ends comfortably above the
    -- "no target / BL ON / Esc close" strip.
    scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -28, 32)

    -- §6.9 thin scrollbar: hide the arrow chrome, narrow the track.
    local sb = _G["WardenHelpScrollScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT",    scroll, "TOPRIGHT", 2, 0)
        sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
        sb:SetWidth(8)
    end

    local content = CreateFrame("Frame", "WardenHelpContent", scroll)
    local contentW = pane:GetWidth() - 40
    content:SetSize(contentW, 10)
    scroll:SetScrollChild(content)

    local descW = contentW - PAD_L - PAD_R - KEY_W - GUTTER

    -- Shared font object factory (§6.4).
    local function setTermFont(fs)
        fs:SetFontObject("GameFontNormal")
        fs:SetTextColor(0.79, 0.63, 0.29, 1) -- warm gold
    end
    local function setDescFont(fs)
        fs:SetFontObject("GameFontHighlightSmall")
        fs:SetTextColor(0.85, 0.80, 0.69, 1) -- parchment
    end
    local function setSectionFont(fs)
        fs:SetFontObject("GameFontNormalLarge")
        fs:SetTextColor(1.00, 0.82, 0.00, 1) -- gold
    end

    local y = 0

    -- §6.10 masthead
    local h1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L, y)
    h1:SetText("WARDEN")
    h1:SetTextColor(1.00, 0.82, 0.00, 1)
    y = y - 28

    local h2 = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h2:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L, y)
    h2:SetText("raid commander \194\183 v" .. (GetAddOnMetadata("Warden", "Version") or "?"))
    h2:SetTextColor(0.61, 0.55, 0.40, 1)
    y = y - 16

    local mastheadRule = content:CreateTexture(nil, "ARTWORK")
    mastheadRule:SetTexture("Interface\\Buttons\\WHITE8x8")
    mastheadRule:SetVertexColor(0.72, 0.58, 0.21, 0.50)
    mastheadRule:SetHeight(1)
    mastheadRule:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD_L, y)
    mastheadRule:SetPoint("RIGHT",    content, "RIGHT",   -PAD_R, 0)
    y = y - 10

    local sectionIdx = 0
    for _, section in ipairs(SECTIONS) do
        sectionIdx = sectionIdx + 1
        -- §6.5: 16px gap before sections after the first.
        if sectionIdx > 1 then y = y - 10 end

        local h = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        h:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L, y)
        setSectionFont(h)
        h:SetText(section.title)
        y = y - (h:GetStringHeight() + 4)

        local rule = content:CreateTexture(nil, "ARTWORK")
        rule:SetTexture("Interface\\Buttons\\WHITE8x8")
        rule:SetVertexColor(0.72, 0.58, 0.21, 0.35)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L, y)
        rule:SetPoint("RIGHT",   content, "RIGHT", -PAD_R, 0)
        y = y - 8

        local rowIdx = 0
        for _, item in ipairs(section.items) do
            rowIdx = rowIdx + 1

            -- §6.6 alternating row fill (subtle).
            local rowTopY = y

            local key = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            key:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L, y)
            key:SetWidth(KEY_W)
            key:SetJustifyH("LEFT")
            setTermFont(key)
            key:SetText(item[1])

            local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_L + KEY_W + GUTTER, y)
            desc:SetWidth(descW)
            desc:SetJustifyH("LEFT")
            desc:SetWordWrap(true)
            desc:SetNonSpaceWrap(false)
            setDescFont(desc)
            desc:SetText(item[2])
            desc:SetHeight(desc:GetStringHeight())

            local rowH = math.max(key:GetStringHeight(), desc:GetStringHeight(), 14) + 6

            if (rowIdx % 2) == 0 then
                local shade = content:CreateTexture(nil, "BACKGROUND")
                shade:SetTexture("Interface\\Buttons\\WHITE8x8")
                shade:SetVertexColor(0.09, 0.07, 0.05, 0.45)
                shade:SetPoint("TOPLEFT",     content, "TOPLEFT",  PAD_L - 4, rowTopY + 1)
                shade:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -PAD_R + 4, rowTopY - rowH)
            end

            y = y - rowH
        end
    end

    content:SetHeight(math.max(10, -y + 8))
end

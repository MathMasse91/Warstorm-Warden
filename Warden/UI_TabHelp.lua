-- =====================================================
-- Warden - UI_TabHelp.lua
-- v2 rework, May 2026: two-pane chapter rail + scoped reader.
-- =====================================================

local _, ns = ...
ns.UI.Tabs      = ns.UI.Tabs      or {}
ns.UI.Tabs.Help = ns.UI.Tabs.Help or {}

-- §3.1 inline markup: chapter text uses |kbd[X]| / |ck[...]| / |em[...]|
-- markers, rendered by ns.UI.RichText.Format.

-- §3.2 tunables
local RAIL_W            = 180
local READER_PAD_TOP    = 22
local READER_PAD_SIDE   = 28
local READER_PAD_BOT    = 18
local CHAP_H            = 22
local GROUP_H           = 26
local SCROLLBAR_W       = 8  -- matches Settings / Shield; 4px was hard to grab
local SCROLLBAR_PAD     = 12 -- bar sits 2px right of the scroll frame; 12 keeps its 8px inside the pane
local DEFAULT_CHAPTER   = "intro"

-- §3.3 CHAPTERS data. id is stable; group seeds the rail divider; eyebrow
-- prints above the H1 inside the reader.
local CHAPTERS = {
    -- Source: HELP_CONTENT_REVISED.md (2026-11-11). TODO: Free / Release rows in
    -- chapter "controls" are unverified in game - see UI_TabControls.lua tooltips.
    -- ---- START HERE ------------------------------------------------------
    {
        id = "intro", group = "START HERE", title = "What is Warden?",
        eyebrow = "Chapter 01 \194\183 Start here",
        body = {
            { kind = "lede",  text = "Warden is a control panel for your WarStorm bots. You click buttons; Warden types the bot commands and whispers for you." },
            { kind = "p",     text = "Without Warden, running a bot raid means typing a command for every bot: one to spawn it, one to give it a spec, one to gear it, and more during each fight. Warden does all of that from one window and three small floating panels." },
            { kind = "h2",    text = "What you can do with it" },
            { kind = "bullets", items = {
                "Plan a raid on a grid, then spawn all the bots with one button.",
                "Give any bot a spec by clicking a picture of that spec.",
                "Order the raid during a fight: summon, follow, stay, attack, AoE, Bloodlust.",
                "See who is in your raid, by role, and fix a bot that has the wrong spec.",
                "Save a raid setup and share it with a friend as one line of text.",
            }},
            { kind = "h2",    text = "The four parts" },
            { kind = "table", rows = {
                { "Main window", "Six tabs. Open it with |ck[/warden]|. Used before and between fights." },
                { "WardenSword", "Small combat panel with the orders you need mid-fight. |ck[/ws]|" },
                { "WardenMantle", "Small card to change a bot's spec. Target a bot, click a spec. |ck[/wm]|" },
                { "WardenShield", "Shows a bot's spells as a list you can click. |ck[/wsh]|" },
            }},
            { kind = "h2",    text = "The usual order" },
            { kind = "steps", items = {
                "|em[Plan]| \226\128\148 pick or build a comp in the Bot Comp tab.",
                "|em[Spawn]| \226\128\148 press |kbd[Build]| or |kbd[Create]|. The bots join and get their specs.",
                "|em[Fight]| \226\128\148 close the window and command the raid from WardenSword.",
                "|em[Adjust]| \226\128\148 change a spec or swap a bot when a pull shows what was missing.",
            }},
            { kind = "p",     text = "New here? Read |em[Your First Raid]| next. It takes two minutes." },
            { kind = "p",     text = "Warden only works on the WarStorm server. It needs WarStorm's bot commands." },
        },
    },
    {
        id = "first-raid", group = "START HERE", title = "Your First Raid",
        eyebrow = "Chapter 02 \194\183 Start here",
        body = {
            { kind = "lede",  text = "From nothing to a full, specced, buffed raid in six clicks." },
            { kind = "h2",    text = "Before you start" },
            { kind = "bullets", items = {
                "Be alone, or be the leader of your group. Warden cannot spawn bots into a group led by someone else.",
                "Stand somewhere safe and out of combat.",
            }},
            { kind = "h2",    text = "Step by step" },
            { kind = "steps", items = {
                "Type |ck[/warden]| in chat. The main window opens.",
                "Click the |kbd[Bot Comp]| tab at the bottom of the window.",
                "Open the |kbd[presets]| dropdown at the top and pick a raid, for example |em[Icecrown Citadel 25]|. The grid fills with classes.",
                "Find the slot that matches your own class. Click it, then click |kbd[[P] off]| in the Slot Detail panel so it reads |kbd[[P] on]|. This tells Warden \"a real player sits here, do not spawn a bot\".",
                "Press |kbd[Create]| at the bottom right and confirm.",
                "Wait. Watch the |em[Queue / Pending]| numbers at the bottom left count down to zero.",
            }},
            { kind = "h2",    text = "What Create does while you wait" },
            { kind = "steps", items = {
                "Removes every bot you already have.",
                "Spawns the comp, one bot at a time.",
                "Whispers each bot its spec, then |ck[autogear]|, then its buffs and strategies.",
                "Turns Bloodlust / Heroism off so no shaman wastes it.",
                "Casts Fortitude, Gift of the Wild, and Spirit. Puts a soulstone on you. Applies world buffs.",
            }},
            { kind = "p",     text = "When chat shows |em[Create: buffs sent. Done.]| the raid is ready. A 25-man takes about one minute." },
            { kind = "h2",    text = "Build or Create?" },
            { kind = "table", rows = {
                { "Build", "Spawns the bots and gives each one its spec. Keeps bots you already have. Use it to top up a group." },
                { "Create", "Starts clean: removes all bots first, then spawns, specs, gears, and buffs. Use it for a fresh raid." },
                { "Stop Build", "Cancels a Build or Create that is still running. Bots already spawned stay." },
            }},
            { kind = "h2",    text = "Now go fight" },
            { kind = "p",     text = "Close the window with |kbd[Esc]|. Type |ck[/ws]| to open WardenSword. Target a boss and click |kbd[Skull]| to send the raid in. Click |kbd[Bloodlust]| when you want it." },
        },
    },
    {
        id = "nav", group = "START HERE", title = "Getting Around",
        eyebrow = "Chapter 03 \194\183 Start here",
        body = {
            { kind = "lede",  text = "Four ways to reach everything: the tabs, the minimap button, slash commands, and key bindings." },
            { kind = "h2",    text = "The six tabs" },
            { kind = "table", rows = {
                { "Spec", "Give the bot you are targeting a spec." },
                { "Controls", "Every raid order, plus the dangerous resets." },
                { "Bot Comp", "Plan a raid and spawn it." },
                { "Roster", "See who is in the raid and re-apply specs." },
                { "Settings", "Options, whisper filter, maintenance." },
                { "Help", "This guide." },
            }},
            { kind = "p",     text = "Drag the window by any empty area to move it. Press |kbd[Esc]| or the X to close it. You cannot switch to or from the Spec tab while in combat \226\128\148 the game blocks it." },
            { kind = "h2",    text = "Minimap button" },
            { kind = "table", rows = {
                { "Left-click", "Open or close the main window." },
                { "Shift + Left-click", "Open Settings." },
                { "Right-click", "Open this Help tab." },
                { "Middle-click", "Open or close WardenSword." },
                { "Shift + Middle-click", "Open or close WardenShield." },
                { "Ctrl + Middle-click", "Open or close WardenMantle." },
                { "Drag", "Move the button around the minimap." },
            }},
            { kind = "h2",    text = "Most-used commands" },
            { kind = "table", rows = {
                { "/warden", "Open or close the main window. |ck[/wden]| also works." },
                { "/ws", "Open or close WardenSword." },
                { "/wm", "Open or close WardenMantle." },
                { "/wsh", "Open or close WardenShield." },
            }},
            { kind = "p",     text = "The full list is in the |em[Slash Commands]| chapter." },
            { kind = "h2",    text = "The footer bar" },
            { kind = "p",     text = "The bar at the bottom of the main window is always visible. From left to right:" },
            { kind = "bullets", items = {
                "Your current target, in its class color.",
                "|ck[q N]| \226\128\148 messages still waiting to be sent. Zero means Warden is idle.",
                "|ck[tracked N]| \226\128\148 bots whose spec Warden remembers.",
                "The |kbd[BL]| button \226\128\148 turns Bloodlust / Heroism on or off for every shaman bot.",
            }},
            { kind = "h2",    text = "Window size" },
            { kind = "p",     text = "Too small or too big? Go to Settings \226\134\146 Window size and pick Small, Medium, Large, or XL. It changes at once." },
            { kind = "h2",    text = "Tooltips" },
            { kind = "p",     text = "Hover almost any button to see what it does and the exact command it sends." },
        },
    },
    {
        id = "glossary", group = "START HERE", title = "Words to Know",
        eyebrow = "Chapter 04 \194\183 Start here",
        body = {
            { kind = "lede",  text = "Short definitions of the words this guide uses." },
            { kind = "table", rows = {
                { "Bot", "A character played by the server. You spawn it, it joins your group, it obeys your orders." },
                { "Comp", "A raid plan: which class and spec goes in which slot. Short for composition." },
                { "Slot", "One square on the Bot Comp grid. One slot = one raid member." },
                { "Preset", "A comp that is already saved. Warden ships with eleven." },
                { "P flag", "Marks a real human player. Warden never spawns, specs, or whispers anything flagged |kbd[P]|." },
                { "Spec", "A talent build, such as Holy or Protection." },
                { "Re-Spec", "Send a bot its spec again. Fixes a bot that came back with the wrong talents." },
                { "Tracked", "Warden remembers which spec it gave this bot, so Re-Spec knows what to send." },
                { "GUID", "The unique ID the game gives every character. Warden tracks bots by GUID, not by name." },
                { "Queue", "Messages waiting to be sent. Warden spaces them out so the server does not mute you." },
                { "Strategy", "A behavior switch on a bot, for example \"use AoE\" or \"cast Blessing of Kings\"." },
                { "Exclusion", "A spell a bot is forbidden to cast. Used for Bloodlust control." },
                { "HUD", "A small floating panel that stays on screen while you play." },
                { "Autogear", "A bot command that equips the best gear for the bot's current spec." },
            }},
        },
    },
    -- ---- RAID FLOW -------------------------------------------------------
    {
        id = "comp", group = "RAID FLOW", title = "Bot Comp",
        eyebrow = "Chapter 05 \194\183 Raid flow",
        body = {
            { kind = "lede",  text = "Plan a raid on a grid, then spawn it. A comp is the plan: one class and spec per slot." },
            { kind = "h2",    text = "Screen layout" },
            { kind = "bullets", items = {
                "Top row: the comp name box, the |kbd[presets]| dropdown, and the size buttons.",
                "Left: the raid grid, with the class chips under it.",
                "Right: Slot Detail (edit the selected slot) and Coverage (which raid buffs you have).",
                "Bottom: the FILE buttons, then |kbd[Build]|, |kbd[Create]|, and |kbd[Stop Build]|.",
            }},
            { kind = "h2",    text = "Pick a size" },
            { kind = "p",     text = "Click |kbd[5]|, |kbd[10]|, |kbd[25]|, or |kbd[40]|. The grid redraws. Each column is one raid group (G1, G2, ...); each row is a place in that group." },
            { kind = "h2",    text = "Start from a preset" },
            { kind = "p",     text = "Open the |kbd[presets]| dropdown. Saved comps are listed by size. Click one to load it. If the grid already has slots, Warden asks before replacing them." },
            { kind = "p",     text = "Warden ships with eleven presets: one 5-man, plus 10 and 25 versions of Onyxia, Ulduar, Trial of the Crusader, Icecrown Citadel, and Ruby Sanctum. They are normal saved comps \226\128\148 you can edit or delete them." },
            { kind = "h2",    text = "Add classes by hand" },
            { kind = "table", rows = {
                { "Click a class chip", "Adds that class to the next empty slot." },
                { "Shift + click a chip", "Asks how many, then adds that many." },
                { "Drag a chip to a slot", "Puts that class in that exact slot. Replaces what was there." },
            }},
            { kind = "h2",    text = "Edit the grid" },
            { kind = "table", rows = {
                { "Click a slot", "Selects it. Its details show on the right." },
                { "Right-click a slot", "Empties it." },
                { "Drag a slot to another", "Moves it. If the other slot is filled, the two swap." },
                { "Drag a slot off the grid", "Empties it." },
            }},
            { kind = "h2",    text = "Slot Detail" },
            { kind = "p",     text = "Select a slot to edit it:" },
            { kind = "bullets", items = {
                "|kbd[CHANGE CLASS]| and |kbd[SPEC]| \226\128\148 what the bot will be.",
                "|kbd[BLESSING / TOTEM]| and |kbd[AURA / RESIST]| \226\128\148 which raid buff this bot is in charge of. Only shown for classes that have one.",
                "|kbd[Move]| \226\128\148 shift the slot to the next empty place after it.",
                "|kbd[Duplicate]| \226\128\148 copy the slot into the first empty place.",
                "|kbd[Remove]| \226\128\148 empty the slot.",
                "|kbd[[P] off / on]| \226\128\148 mark the slot as a real player.",
            }},
            { kind = "h2",    text = "The P slot" },
            { kind = "p",     text = "Turn |kbd[P]| on for every slot a human will fill, including your own. Warden never spawns a bot for a P slot." },
            { kind = "p",     text = "Bonus: if you lead the raid, Build moves you into the group of your P slot. Your bots then land in the right groups around you." },
            { kind = "h2",    text = "Coverage" },
            { kind = "p",     text = "A panel of 15 raid-buff tiles. Green means at least one slot provides that buff. Dim red means nobody does. Check it before you build." },
            { kind = "table", rows = {
                { "Kings / Might / Wisdom", "Paladin blessings." },
                { "Sanct.", "Blessing of Sanctuary (paladin)." },
                { "Devot. / Retrib.", "Devotion Aura, Retribution Aura (paladin)." },
                { "ShadRes / FireRes / FrostRes", "Resistance auras and totems." },
                { "B.Shout / Command", "Battle Shout, Commanding Shout (warrior)." },
                { "MoW", "Mark of the Wild (druid)." },
                { "Windf. / ManaSpr", "Windfury and Mana Spring totems (shaman)." },
                { "AotW", "Aspect of the Wild (hunter)." },
            }},
            { kind = "p",     text = "A red tile is a hint, not an error. To fix one, select a slot of the right class and pick the buff in Slot Detail." },
            { kind = "p",     text = "The counter under it shows filled slots, for example |em[24 / 25]|." },
            { kind = "h2",    text = "Build" },
            { kind = "p",     text = "Spawns one bot for every slot that is not a P slot, then whispers each bot its spec and buffs as it joins. Bots already in your group stay. If you are already in a group, Warden asks before it starts." },
            { kind = "h2",    text = "Create" },
            { kind = "p",     text = "The one-click raid. It asks first, because it removes every bot you have. Then it spawns the comp, specs and autogears each bot, turns Bloodlust off, casts the group buffs, puts a soulstone on you, and applies world buffs. If one bot never joins, the others are still set up." },
            { kind = "p",     text = "Create order and buff ideas by Feryll/Huntriss [DGEN]." },
            { kind = "h2",    text = "Stop Build and the status line" },
            { kind = "p",     text = "|kbd[Stop Build]| cancels a Build or Create in progress. Bots that already joined stay in the group." },
            { kind = "p",     text = "The line at the bottom left shows progress. |em[Queue]| is commands still to send. |em[Pending]| is bots still waiting for their spec. Both at zero means the build is finished." },
            { kind = "h2",    text = "To Chat" },
            { kind = "p",     text = "Posts the comp as readable text so your group can see the plan. Click |kbd[To Chat]|, pick a channel (Raid, Party, Guild, Officer, Say, Yell, Battleground). Example: |ck[Warden Comp [ICC] (24/25): Priest: 2 Disc - ...]|. Your P slot is left out. Long comps are split over several lines." },
            { kind = "h2",    text = "The FILE buttons" },
            { kind = "table", rows = {
                { "Save", "Saves the grid under the name in the COMP box. Asks before overwriting." },
                { "Load", "Loads the comp whose name is in the COMP box." },
                { "Rename", "Gives a saved comp a new name." },
                { "Delete", "Deletes the saved comp named in the COMP box. Asks first." },
                { "Export", "Shows a |ck[WRDN2:]| text string of the comp. Copy it and send it to a friend." },
                { "Import", "Paste a |ck[WRDN2:]| string to load someone else's comp. Old |ck[WRDN1:]| strings still work." },
                { "Clear", "Empties the grid. Does not touch your bots or your saved comps." },
                { "Resync", "Moves the bots already in your raid into the groups shown on the grid." },
                { "Cleanup", "Removes every bot from your group. Asks first." },
            }},
            { kind = "p",     text = "Deleted a default preset by mistake? Settings \226\134\146 Maintenance \226\134\146 |kbd[Restore default presets]| brings it back." },
            { kind = "h2",    text = "Resync in detail" },
            { kind = "p",     text = "Use it when the raid is built but the groups are a mess. Warden matches each filled slot to a raid member of the same class and moves that member to the slot's group. Your P slot moves you. You must be in a raid and be leader or assistant. Flagged human players are not moved." },
        },
    },
    {
        id = "spec", group = "RAID FLOW", title = "Spec",
        eyebrow = "Chapter 06 \194\183 Raid flow",
        body = {
            { kind = "lede",  text = "Change one bot's spec. Target the bot, click a spec tile." },
            { kind = "h2",    text = "How to use it" },
            { kind = "steps", items = {
                "Target a bot (or just hold your mouse over it).",
                "The top card shows its portrait, level, name, and class.",
                "Click one of the spec tiles below.",
            }},
            { kind = "p",     text = "Warden whispers |ck[talents spec <name>]| to the bot, then |ck[autogear]| so its gear matches the new spec. It also remembers the choice, so Re-Spec can send it again later." },
            { kind = "h2",    text = "Reading the tiles" },
            { kind = "bullets", items = {
                "Each tile shows the spec name in class color and a short role note, such as |em[pve - tank]| or |em[pvp - heal]|.",
                "A tile marked |em[* current]| is the spec Warden last gave this bot.",
                "A tile marked |em[* default]| is the recommended PvE spec for a bot Warden has not specced yet.",
            }},
            { kind = "h2",    text = "Getting your target back" },
            { kind = "p",     text = "Clicking around can drop your target. Two buttons sit under the target card:" },
            { kind = "bullets", items = {
                "|kbd[< prev target]| \226\128\148 re-targets your last target. Works in combat.",
                "|kbd[History]| \226\128\148 lists your last six player targets. Click a name to target it. Not available in combat.",
            }},
            { kind = "h2",    text = "Group buttons" },
            { kind = "bullets", items = {
                "|kbd[Autogear]| \226\128\148 every bot in your group equips its best gear.",
                "|kbd[World Buffs]| \226\128\148 every bot in your group gets world buffs.",
            }},
            { kind = "h2",    text = "Limits" },
            { kind = "bullets", items = {
                "A tile only works on a bot of that class. Target a paladin to use paladin tiles.",
                "A character flagged |kbd[P]| is never specced. Warden says so in chat.",
                "You cannot open or leave the Spec tab during combat. Use WardenMantle (|ck[/wm]|) for spec changes in a fight.",
            }},
        },
    },
    {
        id = "roster", group = "RAID FLOW", title = "Roster & Re-Spec",
        eyebrow = "Chapter 07 \194\183 Raid flow",
        body = {
            { kind = "lede",  text = "A live list of everyone in your raid, grouped into Tanks, Healers, and DPS. Use it to check specs and repair bots." },
            { kind = "h2",    text = "When to use it" },
            { kind = "bullets", items = {
                "A bot disconnected and came back with the wrong talents.",
                "You want to change several bots' specs without targeting each one.",
                "A friend joined and you must protect them from bot commands.",
                "A bot is in the wrong raid group.",
            }},
            { kind = "h2",    text = "Find a member" },
            { kind = "p",     text = "The |kbd[FILTER]| dropdown narrows the list: All, Tanks, Healers, DPS (all), Melee DPS, Ranged DPS. Type in the search box to find a name. |kbd[Refresh]| rebuilds the list." },
            { kind = "h2",    text = "What a row shows" },
            { kind = "p",     text = "From left to right:" },
            { kind = "bullets", items = {
                "|kbd[P]| \226\128\148 the real-player flag. Click to turn it on or off.",
                "Checkbox \226\128\148 tick it to include the row in |kbd[Re-Spec Selected]|.",
                "Class icon, name, and current class and spec.",
                "Spec dropdown \226\128\148 pick a different spec for this member.",
                "Buff chips \226\128\148 the raid buffs this class can bring.",
                "|kbd[G1]| ... |kbd[G8]| \226\128\148 the member's raid group. Click to move them.",
                "|kbd[Re-Spec]| \226\128\148 send this member its spec again.",
            }},
            { kind = "h2",    text = "The P flag" },
            { kind = "p",     text = "Click |kbd[P]| on a row to say \"this is a human, not a bot\". Warden then skips that name everywhere: Build, Re-Spec, bulk Re-Spec, and auto-spec. The flag is saved by name and survives logout. Your own character is flagged for you." },
            { kind = "p",     text = "Always flag friends who join your raid. Otherwise Warden may whisper them bot commands." },
            { kind = "h2",    text = "Buff chips" },
            { kind = "p",     text = "Short codes for raid buffs: KNG (Kings), MGT (Might), WIS (Wisdom), SAN (Sanctuary), SoE (Strength of Earth), WF (Windfury), FT (Flametongue), MS (Mana Spring), BS (Battle Shout), CS (Commanding Shout), ASP (Aspect of the Wild)." },
            { kind = "bullets", items = {
                "Gold chip \226\128\148 the comp assigns this buff to this member.",
                "Dim chip \226\128\148 the member could cast it but is not assigned.",
            }},
            { kind = "p",     text = "Chips show the plan, not what is active right now. Priests, mages, warlocks, and rogues have no chips." },
            { kind = "h2",    text = "Re-Spec" },
            { kind = "p",     text = "The row's |kbd[Re-Spec]| button whispers the spec shown in the dropdown, plus the bot's buffs and strategies. It is off for your own row and for P rows." },
            { kind = "table", rows = {
                { "Re-Spec All Tracked", "Re-sends the spec to every bot Warden remembers." },
                { "Re-Spec Selected", "Re-sends only to rows with the checkbox ticked. The counter shows how many." },
            }},
            { kind = "p",     text = "Both skip human players. Whispers go out one at a time, so a 25-man takes a few seconds." },
            { kind = "h2",    text = "Move a bot to another group" },
            { kind = "p",     text = "Click the |kbd[G]| button on a row and pick a group. You must be raid leader or assistant." },
        },
    },
    {
        id = "controls", group = "RAID FLOW", title = "Controls",
        eyebrow = "Chapter 08 \194\183 Raid flow",
        body = {
            { kind = "lede",  text = "Every order you can give the raid, in one tab. One click sends the order to all your bots through group chat." },
            { kind = "p",     text = "Bots only hear these orders if they are in your party or raid." },
            { kind = "h2",    text = "Movement" },
            { kind = "table", rows = {
                { "Summon", "Teleports all bots to you." },
                { "Follow", "All bots follow you." },
                { "Stay", "All bots stop and hold their position." },
                { "Free", "Releases bots from strict follow." },
                { "Release", "Frees bots from their current target." },
                { "Drink", "All bots drink to restore mana." },
            }},
            { kind = "h2",    text = "Strategy" },
            { kind = "table", rows = {
                { "AoE On / Off", "On: bots use area damage on packs. Off: bots focus one target." },
                { "Burn / Stop", "Burn: bots use their big cooldowns. Stop: bots save them." },
                { "Behind / No Flank", "Behind: melee bots move behind the target. No Flank: they stay where they are." },
            }},
            { kind = "p",     text = "The lit button shows the current setting." },
            { kind = "h2",    text = "Marks and formation" },
            { kind = "bullets", items = {
                "|kbd[Skull (attack)]| \226\128\148 marks your target with a skull and sends the bots to attack it.",
                "|kbd[Moon (CC)]| \226\128\148 tells bots to crowd-control the target marked with a moon.",
                "|kbd[DISPERSE]| \226\128\148 how far apart bots stand: 5, 7, 10, 15, or 20 yards, or |em[disable]|. Use it on fights with splash damage.",
                "|kbd[FORM]| \226\128\148 the raid's formation: Shield, Chaos, Circle, Line, Melee, Near, Queue, or Arrow. Pick one, then click |kbd[Set]|. |kbd[Check]| asks the bots which one is active.",
            }},
            { kind = "h2",    text = "Role commands" },
            { kind = "p",     text = "A 5 \195\151 4 grid. Rows are roles: Tank, Healer, DPS, Melee, Ranged. Columns are orders: |kbd[Atk]|, |kbd[Stay]|, |kbd[Fol]| (follow), |kbd[Flee]|." },
            { kind = "p",     text = "Use it to split the raid. Example: |kbd[Tank \226\134\146 Atk]| to pull, wait for threat, then |kbd[DPS \226\134\146 Atk]|. Or |kbd[Ranged \226\134\146 Stay]| to park casters before a fight." },
            { kind = "h2",    text = "Bloodlust" },
            { kind = "p",     text = "The |kbd[BL]| button is on the footer bar of the main window, not in this tab. |kbd[BL OFF]| means shamans will not cast Bloodlust / Heroism. Click it to switch to |kbd[BL ON]| when you want it used. It starts OFF so it is never wasted on trash." },
            { kind = "h2",    text = "Danger zone" },
            { kind = "table", rows = {
                { "Smart ReSpec", "Target a bot, click, pick a spec from the list. Changes that one bot. Safe." },
                { "Reset AI", "Puts every bot's strategies back to default. Asks first." },
                { "Hard ReSpec", "Re-rolls the gear of ALL bots. Every bot also gets a random spec. Asks first. Always run Roster \226\134\146 Re-Spec All Tracked afterwards." },
                { "Cleanup", "Removes every bot from your group. Asks first." },
            }},
            { kind = "h2",    text = "Add bot by class" },
            { kind = "p",     text = "Ten class buttons at the bottom. One click spawns one bot of that class. Good for questing, replacing one dungeon member, or testing. The new bot has no spec yet \226\128\148 give it one in the Spec tab or WardenMantle." },
        },
    },
    -- ---- MODULES ---------------------------------------------------------
    {
        id = "sword", group = "MODULES", title = "WardenSword",
        eyebrow = "Chapter 09 \194\183 Modules",
        body = {
            { kind = "lede",  text = "The combat panel. A small floating box with the orders you need during a fight, so the main window can stay closed." },
            { kind = "h2",    text = "Open and close" },
            { kind = "p",     text = "Type |ck[/ws]|, or middle-click the minimap button, or use a key binding. The X on the panel closes it." },
            { kind = "p",     text = "WardenSword never opens by itself. It starts closed after every login and |ck[/reload]|, and it does not pop up when combat starts." },
            { kind = "h2",    text = "Move and lock" },
            { kind = "p",     text = "Drag the panel by its header. Click the circle on the header to lock it in place, so you cannot drag it by accident in a fight. Position and lock are remembered." },
            { kind = "h2",    text = "The buttons" },
            { kind = "table", rows = {
                { "Summon", "Teleports all bots to you." },
                { "Follow", "All bots follow you." },
                { "Stay", "All bots hold position." },
                { "Flee", "All bots run away." },
                { "AoE", "Switches area damage on or off. Gold label = on." },
                { "Burn", "Switches big cooldowns on or off. Gold label = on." },
                { "Skull", "Marks your target with a skull and sends the bots to attack." },
                { "Bloodlust", "Allows or forbids Bloodlust / Heroism for every shaman bot. Shows |em[Bloodlust \194\183 ON]| when allowed." },
            }},
            { kind = "h2",    text = "Role rows" },
            { kind = "p",     text = "Three rows \226\128\148 TANK, HEAL, DPS \226\128\148 each with |kbd[Atk]|, |kbd[Follow]|, |kbd[Stay]|. They order one role only. Example: TANK |kbd[Atk]| to pull, then DPS |kbd[Atk]| a few seconds later." },
            { kind = "p",     text = "The rows can be hidden in Settings to make the panel smaller." },
            { kind = "h2",    text = "Status line" },
            { kind = "p",     text = "Under the header: |ck[BOTS]| (how many bots), |ck[AoE]| and |ck[BL]| (on or off), |ck[Q]| (messages waiting). Can be hidden in Settings." },
            { kind = "h2",    text = "Make it yours" },
            { kind = "p",     text = "Settings tab \226\134\146 WardenSword panel:" },
            { kind = "bullets", items = {
                "Show or hide the status line and the role rows.",
                "Start locked at login.",
                "Hide the minimap button during combat.",
                "Density: Tiny, Compact, or Normal.",
                "Transparency: 15% to 100%.",
                "|kbd[Reset HUD position]| if the panel is off screen.",
            }},
            { kind = "h2",    text = "Use it without clicking" },
            { kind = "p",     text = "Every button has a slash command and a key binding. Put them in macros or bind them to keys." },
            { kind = "table", rows = {
                { "/ws", "Open or close the panel." },
                { "/ws show / hide", "Open or close, explicitly." },
                { "/ws summon", "Same as the Summon button. Also: |ck[follow]|, |ck[stay]|, |ck[flee]|, |ck[aoe]|, |ck[burn]|, |ck[skull]|, |ck[bl]|." },
                { "/ws @tank atk", "Role order. Roles: |ck[@tank]|, |ck[@heal]|, |ck[@dps]|. Orders: |ck[atk]|, |ck[follow]|, |ck[stay]|." },
                { "/ws lock / unlock", "Lock or unlock the position." },
                { "/ws reset", "Put the panel back in its default place." },
                { "/ws config", "Open the Settings tab." },
                { "/ws help", "Print this list in chat." },
            }},
            { kind = "h2",    text = "Real players are safe" },
            { kind = "p",     text = "Characters flagged |kbd[P]| are never whispered by WardenSword." },
        },
    },
    {
        id = "mantle", group = "MODULES", title = "WardenMantle",
        eyebrow = "Chapter 10 \194\183 Modules",
        body = {
            { kind = "lede",  text = "The spec-swap card. Target a bot, click a spec icon, done. Works in combat. Successor to feysSpecManager." },
            { kind = "h2",    text = "Open and close" },
            { kind = "p",     text = "Type |ck[/wm]|, or Ctrl + middle-click the minimap button. The X closes it. It is hidden until you open it the first time; after that Warden remembers whether it was open." },
            { kind = "h2",    text = "Change a spec" },
            { kind = "steps", items = {
                "Target a bot. The card shows its portrait, name, and class.",
                "Click an icon in the |kbd[PvE]| row or the |kbd[PvP]| row.",
            }},
            { kind = "p",     text = "Warden whispers |ck[talents spec <name>]| and then |ck[autogear]| to that bot at once. The choice is remembered, so Re-Spec can send it again later." },
            { kind = "p",     text = "Hover an icon to see the spec name. With no bot targeted the card shows |em[No Target]| and the icons hide." },
            { kind = "h2",    text = "The two buttons" },
            { kind = "table", rows = {
                { "Summon", "Teleports only the targeted bot to you. (Controls \226\134\146 Summon calls all of them.)" },
                { "Autogear", "Every bot in your group equips its best gear." },
            }},
            { kind = "h2",    text = "Move and lock" },
            { kind = "p",     text = "Drag by the header. The circle on the header locks the position. Both are remembered." },
            { kind = "h2",    text = "Good to know" },
            { kind = "bullets", items = {
                "You cannot spec yourself or a character flagged |kbd[P]|.",
                "Mantle sends its whispers instantly, with no queue delay, because you act on one bot at a time.",
                "Icons only work on the class they belong to. Retarget and the card updates.",
            }},
            { kind = "h2",    text = "Commands" },
            { kind = "table", rows = {
                { "/wm", "Open or close the card." },
                { "/wm show / hide", "Open or close, explicitly." },
                { "/wm lock / unlock", "Lock or unlock the position." },
                { "/wm reset", "Put the card back in its default place." },
            }},
        },
    },
    {
        id = "shield", group = "MODULES", title = "WardenShield",
        eyebrow = "Chapter 11 \194\183 Modules",
        body = {
            { kind = "lede",  text = "Shows what a bot can do as a list you can click. Ask a bot for its spells, then click a spell to make the bot cast it \226\128\148 or to forbid it." },
            { kind = "h2",    text = "What it is for" },
            { kind = "bullets", items = {
                "Make one bot cast one spell, on its target, on you, or on someone else.",
                "Forbid a bot from using a spell (ban), or allow it again (unban).",
                "See the objects near a bot and make the bot use one.",
            }},
            { kind = "h2",    text = "Open and close" },
            { kind = "p",     text = "Type |ck[/wsh]|, or Shift + middle-click the minimap button. The X closes it. The circle on the header locks the position." },
            { kind = "h2",    text = "Basic use" },
            { kind = "steps", items = {
                "Target a bot.",
                "Click |kbd[Pick]|. The bot's name locks in at the top with |em[LOCKED]| next to it.",
                "Click |kbd[spells]|. Warden whispers the bot and listens for about five seconds. The button glows gold while listening.",
                "The bot's spells appear as a list.",
                "Choose a mode (see below), then click a spell.",
            }},
            { kind = "p",     text = "Once a bot is locked you can target something else. Shield keeps talking to the locked bot." },
            { kind = "h2",    text = "los and spells" },
            { kind = "table", rows = {
                { "spells", "Lists the bot's spells." },
                { "los", "Lists objects the bot can see nearby. Click one to make the bot use it." },
                { "Clear", "Empties the list and unlocks the bot." },
            }},
            { kind = "h2",    text = "Modes \226\128\148 what a click does" },
            { kind = "table", rows = {
                { "cast", "The bot casts the spell on its own target." },
                { "on Y", "The bot casts the spell on a unit you choose." },
                { "on me", "The bot casts the spell on you." },
                { "ban", "The bot is forbidden to cast this spell." },
                { "unban", "The bot may cast this spell again." },
            }},
            { kind = "h2",    text = "Choosing a target for \"on Y\"" },
            { kind = "p",     text = "In |kbd[on Y]| mode a chip appears. A dashed gold border means it is waiting: click any unit frame (party, raid, target) to set the target. The chip turns solid and shows the name. Click the chip to clear it." },
            { kind = "h2",    text = "Banned spells" },
            { kind = "p",     text = "A banned spell shows a red dot and dim text. Click it in |kbd[unban]| mode to allow it again." },
            { kind = "bullets", items = {
                "|kbd[Exclusions \194\183 N]| at the bottom lists every spell you have banned. Click a row to unban it.",
                "|kbd[Reset All]| removes every ban on the locked bot.",
                "|kbd[Hide Gray]| hides spells the bot cannot use yet. It is ignored in ban and unban modes so you can always see everything.",
            }},
            { kind = "h2",    text = "Long lists" },
            { kind = "p",     text = "With more than 20 lines a filter box appears. Type part of a name to narrow the list." },
            { kind = "h2",    text = "Several bots" },
            { kind = "p",     text = "If you list spells from several bots one after another, each line shows a small tag with the bot's name. A click always goes to the bot that owns the line." },
            { kind = "h2",    text = "Commands" },
            { kind = "table", rows = {
                { "/wsh", "Open or close the panel." },
                { "/wsh show / hide", "Open or close, explicitly." },
                { "/wsh lock / unlock", "Lock or unlock the position." },
                { "/wsh reset", "Put the panel back in its default place." },
                { "/wsh spells", "List the spells of the targeted or locked bot." },
                { "/wsh los", "List the objects near the targeted or locked bot." },
                { "/wsh clear", "Empty the list and unlock the bot." },
                { "/wsh help", "Print this list in chat." },
            }},
        },
    },
    -- ---- REFERENCE -------------------------------------------------------
    {
        id = "settings", group = "REFERENCE", title = "Settings",
        eyebrow = "Chapter 12 \194\183 Reference",
        body = {
            { kind = "lede",  text = "All options, top to bottom, as they appear in the Settings tab." },
            { kind = "h2",    text = "Global settings" },
            { kind = "table", rows = {
                { "Auto-spec newly joined bots", "On: a bot that joins during a Build gets its planned spec automatically. Leave it on." },
                { "Auto-match group type to comp size", "On: Build turns your party into a raid when the comp needs more than 5. It turns a raid of 5 or fewer back into a party for a 5-man comp. You must be leader." },
                { "Window size", "Small (80%), Medium (100%), Large (120%), XL (140%)." },
            }},
            { kind = "h2",    text = "Bot whisper filter" },
            { kind = "p",     text = "Bots send a lot of whispers. This filter hides them so you can see real messages. It is off by default." },
            { kind = "p",     text = "Tick |kbd[Block bot noise whispers]| to turn it on. Then tick or untick each line under |em[LINES TO HIDE]|:" },
            { kind = "bullets", items = {
                "\"Invite me to your group first\"",
                "\"I am in a full group. Will do it later\"",
                "\"...you can ask <player> for invite\"",
                "\"Equipping [item]\"",
                "\"Staying\"",
                "\"Following\"",
                "\"Using [item] (N available) on self\"",
                "\"Picking <spec>\"",
                "\"You are too low level: N/80\"",
            }},
            { kind = "p",     text = "Whispers from real players still get through. The invite lines are only hidden when the sender is not in your group. If a friend could really whisper you one of these exact lines, untick that line." },
            { kind = "h2",    text = "Session stats" },
            { kind = "table", rows = {
                { "Spawned", "Bots spawned by the last Build." },
                { "Spec'd", "Bots that received a spec in the last Build." },
                { "Pending", "Bots still waiting for a spec." },
                { "Tracked GUIDs", "Bots whose spec Warden remembers." },
                { "Send queue", "Spawn commands waiting to be sent." },
                { "Whisper queue", "Whispers waiting to be sent." },
            }},
            { kind = "h2",    text = "WardenSword" },
            { kind = "p",     text = "Options for the combat panel: show status strip, show role commands row, start locked, hide the minimap button in combat, density, transparency, and |kbd[Reset HUD position]|. See the WardenSword chapter." },
            { kind = "h2",    text = "Maintenance" },
            { kind = "table", rows = {
                { "Reset minimap button", "Puts the minimap button back in its default place." },
                { "Clear GUID tracking", "Makes Warden forget every bot's spec. Use it if Re-Spec keeps sending old specs. Asks first." },
                { "Clear player flags", "Removes every |kbd[P]| flag except your own. Asks first." },
                { "Restore default presets", "Brings back any of the eleven built-in comps you deleted. Never overwrites one you edited." },
            }},
            { kind = "h2",    text = "About" },
            { kind = "p",     text = "Shows the version and credits." },
        },
    },
    {
        id = "auto", group = "REFERENCE", title = "What Warden Does for You",
        eyebrow = "Chapter 13 \194\183 Reference",
        body = {
            { kind = "lede",  text = "Things Warden handles in the background, so you know what to expect." },
            { kind = "h2",    text = "It never touches real players" },
            { kind = "p",     text = "Before any whisper, spec, or move, Warden checks the |kbd[P]| flag. A flagged name is skipped. Your own character is always protected." },
            { kind = "h2",    text = "It paces its messages" },
            { kind = "p",     text = "The server mutes you if you whisper too fast. So during Build, Create, and bulk Re-Spec, Warden sends one bot spawn every 0.9 seconds and one whisper every 0.45 seconds. This is why a big raid takes about a minute. The |ck[q]| number in the footer shows what is still waiting." },
            { kind = "p",     text = "Single clicks \226\128\148 a WardenMantle icon, a Controls button \226\128\148 go out at once." },
            { kind = "h2",    text = "It remembers each bot's spec" },
            { kind = "p",     text = "Warden stores the spec and buff choices for every bot by its unique ID. If a bot reconnects or you retarget, Re-Spec sends exactly the same setup again." },
            { kind = "h2",    text = "It waits for slow bots, then moves on" },
            { kind = "p",     text = "If a bot has not joined about 8 seconds after its spawn command, Warden warns you and continues with the next one. If nothing more happens for 30 seconds the build ends, and the bots that did join are still set up." },
            { kind = "h2",    text = "It converts party and raid" },
            { kind = "p",     text = "When a comp needs more than five members, Build turns your party into a raid. You must be leader and out of combat. Turn this off in Settings if you do not want it." },
            { kind = "h2",    text = "It puts you in the right group" },
            { kind = "p",     text = "If the comp has a P slot and you lead the raid, Build moves you to that slot's group." },
            { kind = "h2",    text = "It keeps Bloodlust off until you say so" },
            { kind = "p",     text = "Bloodlust / Heroism starts forbidden for every shaman bot, so it is not wasted. The |kbd[BL]| button allows it. Warden picks Bloodlust or Heroism from your faction." },
            { kind = "h2",    text = "It handles paladin Righteous Fury" },
            { kind = "p",     text = "After a paladin gets a spec, Warden allows Righteous Fury for Protection and forbids it for Holy and Retribution. Tanks hold threat; the others do not pull it." },
            { kind = "h2",    text = "One buff per buffer" },
            { kind = "p",     text = "Each paladin casts one blessing, each shaman one totem set, each hunter one aspect. You choose which in the Bot Comp slot details." },
        },
    },
    {
        id = "keys", group = "REFERENCE", title = "Key Bindings",
        eyebrow = "Chapter 14 \194\183 Reference",
        body = {
            { kind = "lede",  text = "Bind Warden actions to keys so you can command the raid without clicking." },
            { kind = "h2",    text = "How to set a key" },
            { kind = "steps", items = {
                "Press |kbd[Esc]|, then click |kbd[Key Bindings]|.",
                "Scroll down to the Warden sections.",
                "Click an action, press the key you want, then click |kbd[Okay]|.",
            }},
            { kind = "h2",    text = "Warden" },
            { kind = "bullets", items = {
                "Toggle Warden window",
                "Open Spec tab \194\183 Open Controls tab \194\183 Open Bot Comp tab",
                "Open Roster tab \194\183 Open Settings tab \194\183 Open Help tab",
                "RTSC: enable point-and-click \194\183 save position 1 \194\183 go to position 1",
            }},
            { kind = "p",     text = "RTSC lets you send bots to a spot on the ground. Enable it, save a position, then send the bots there with the third key." },
            { kind = "h2",    text = "WardenSword - Actions" },
            { kind = "bullets", items = {
                "Toggle WardenSword HUD",
                "Lock / unlock WardenSword position",
                "Summon all bots \194\183 All: Follow \194\183 All: Stay \194\183 All: Flee",
                "Toggle AoE \194\183 Toggle Burn CDs",
                "Mark Skull + attack",
                "Bloodlust / Heroism",
            }},
            { kind = "h2",    text = "WardenSword - Role commands" },
            { kind = "bullets", items = {
                "Tanks: Attack \194\183 Tanks: Stay",
                "Healers: Attack \194\183 Healers: Stay",
                "DPS: Attack \194\183 DPS: Stay",
            }},
            { kind = "h2",    text = "WardenMantle and WardenShield" },
            { kind = "bullets", items = {
                "Toggle WardenMantle HUD",
                "Lock / unlock WardenMantle position",
                "Toggle WardenShield HUD",
            }},
            { kind = "h2",    text = "Legacy entries" },
            { kind = "p",     text = "Five entries marked |em[(legacy)]| remain for players who bound them in an older version. New users should bind the WardenSword entries instead." },
            { kind = "h2",    text = "Suggested setup" },
            { kind = "p",     text = "Bind |em[Summon all bots]|, |em[Mark Skull + attack]|, |em[All: Stay]|, and |em[Bloodlust / Heroism]|. Those four cover most fights." },
        },
    },
    {
        id = "slash", group = "REFERENCE", title = "Slash Commands",
        eyebrow = "Chapter 15 \194\183 Reference",
        body = {
            { kind = "lede",  text = "Every Warden command in one place." },
            { kind = "h2",    text = "Main window" },
            { kind = "table", rows = {
                { "/warden", "Open or close the main window." },
                { "/wden", "Same as |ck[/warden]|." },
            }},
            { kind = "h2",    text = "WardenSword" },
            { kind = "table", rows = {
                { "/ws", "Open or close the combat panel. |ck[/wardensword]| also works." },
                { "/ws show / hide", "Open or close, explicitly." },
                { "/ws summon", "Summon all bots." },
                { "/ws follow / stay / flee", "Movement order for all bots." },
                { "/ws aoe", "Switch AoE on or off." },
                { "/ws burn", "Switch burn cooldowns on or off." },
                { "/ws skull", "Mark target with skull and attack." },
                { "/ws bl", "Allow or forbid Bloodlust / Heroism." },
                { "/ws @tank atk", "Order one role. Roles: |ck[@tank]|, |ck[@heal]|, |ck[@dps]|. Orders: |ck[atk]|, |ck[follow]|, |ck[stay]|." },
                { "/ws lock / unlock", "Lock or unlock the position." },
                { "/ws reset", "Reset the position." },
                { "/ws config", "Open the Settings tab." },
                { "/ws help", "Print the WardenSword commands in chat." },
            }},
            { kind = "h2",    text = "WardenMantle" },
            { kind = "table", rows = {
                { "/wm", "Open or close the spec card. |ck[/wardenmantle]| also works." },
                { "/wm show / hide", "Open or close, explicitly." },
                { "/wm lock / unlock", "Lock or unlock the position." },
                { "/wm reset", "Reset the position." },
            }},
            { kind = "h2",    text = "WardenShield" },
            { kind = "table", rows = {
                { "/wsh", "Open or close the spell panel. |ck[/wardenshield]| also works." },
                { "/wsh show / hide", "Open or close, explicitly." },
                { "/wsh spells", "List the bot's spells." },
                { "/wsh los", "List objects near the bot." },
                { "/wsh clear", "Empty the list and unlock the bot." },
                { "/wsh lock / unlock", "Lock or unlock the position." },
                { "/wsh reset", "Reset the position." },
                { "/wsh help", "Print the WardenShield commands in chat." },
            }},
            { kind = "h2",    text = "Log" },
            { kind = "table", rows = {
                { "/wardenlog", "Print the last 20 log lines. See the Debug chapter for the rest." },
            }},
            { kind = "h2",    text = "Macro example" },
            { kind = "p",     text = "One button to pull: |ck[/ws skull]| on the first line, |ck[/ws burn]| on the second." },
        },
    },
    {
        id = "trouble", group = "REFERENCE", title = "Troubleshooting",
        eyebrow = "Chapter 16 \194\183 Reference",
        body = {
            { kind = "lede",  text = "Something is not working? Find the problem below." },
            { kind = "h2",    text = "Bots do not spawn when I press Build" },
            { kind = "bullets", items = {
                "You must be alone or the group leader.",
                "The grid must have at least one slot that is not a P slot.",
                "Watch chat: Warden prints a warning for each bot that failed to join.",
                "Press |kbd[Stop Build]|, wait a few seconds, and try again.",
            }},
            { kind = "h2",    text = "Bots ignore my orders" },
            { kind = "bullets", items = {
                "Bots only hear orders if they are in your party or raid.",
                "In a raid, orders go to raid chat; in a party, to party chat. Bots outside the group hear nothing.",
                "Try Controls \226\134\146 |kbd[Reset AI]| if one bot is stuck.",
            }},
            { kind = "h2",    text = "A bot has the wrong spec" },
            { kind = "p",     text = "Open the Roster tab and click |kbd[Re-Spec]| on its row. Or target it and click the right icon in WardenMantle (|ck[/wm]|)." },
            { kind = "h2",    text = "Many bots have the wrong spec" },
            { kind = "p",     text = "Roster tab \226\134\146 |kbd[Re-Spec All Tracked]|. Hard ReSpec always causes this: it gives every bot a random spec. A server restart can too." },
            { kind = "h2",    text = "Re-Spec sends an old spec" },
            { kind = "p",     text = "Warden remembers the last spec it gave. Give the bot the spec you want from the Spec tab or WardenMantle \226\128\148 that replaces the memory. To wipe all memory: Settings \226\134\146 Maintenance \226\134\146 |kbd[Clear GUID tracking]|." },
            { kind = "h2",    text = "\"Target a bot first\"" },
            { kind = "p",     text = "Nothing is targeted, or you are targeting yourself or an NPC. Click a bot in your group." },
            { kind = "h2",    text = "\"... is flagged as a human player\"" },
            { kind = "p",     text = "That name has the |kbd[P]| flag, so Warden will not touch it. If it really is a bot, open the Roster tab and click its |kbd[P]| to remove the flag." },
            { kind = "h2",    text = "Shamans do not cast Bloodlust" },
            { kind = "p",     text = "Bloodlust starts off. Click |kbd[BL]| in the footer or |kbd[Bloodlust]| on WardenSword. If chat says |em[No shaman bots found]|, there is no shaman in your group." },
            { kind = "h2",    text = "I cannot open the Spec tab" },
            { kind = "p",     text = "You are in combat. The game blocks that tab during a fight. Use WardenMantle (|ck[/wm]|) instead." },
            { kind = "h2",    text = "\"Resync: need raid leader or officer rights\"" },
            { kind = "p",     text = "Only the raid leader or an assistant can move members between groups. The same is true for the |kbd[G]| button in the Roster tab." },
            { kind = "h2",    text = "The server muted me" },
            { kind = "p",     text = "Too many whispers too fast. Wait for the mute to end. Avoid pressing |kbd[Re-Spec All Tracked]| several times in a row \226\128\148 one press is enough; watch the |ck[q]| number fall to zero." },
            { kind = "h2",    text = "A panel is off screen" },
            { kind = "bullets", items = {
                "WardenSword: |ck[/ws reset]|",
                "WardenMantle: |ck[/wm reset]|",
                "WardenShield: |ck[/wsh reset]|",
                "Minimap button: Settings \226\134\146 Maintenance \226\134\146 |kbd[Reset minimap button]|",
            }},
            { kind = "h2",    text = "My chat is full of bot whispers" },
            { kind = "p",     text = "Settings \226\134\146 Bot whisper filter \226\134\146 tick |kbd[Block bot noise whispers]|." },
            { kind = "h2",    text = "I deleted a default preset" },
            { kind = "p",     text = "Settings \226\134\146 Maintenance \226\134\146 |kbd[Restore default presets]|." },
            { kind = "h2",    text = "Still stuck" },
            { kind = "p",     text = "Type |ck[/reload]|. Your comps, flags, and settings are kept. If the problem stays, see the |em[Debug & Logging]| chapter and send the log with your bug report." },
        },
    },
    {
        id = "debug", group = "REFERENCE", title = "Debug & Logging",
        eyebrow = "Chapter 17 \194\183 Reference \194\183 Advanced",
        body = {
            { kind = "lede",  text = "Tools for finding a bug or writing a bug report. You do not need this chapter for normal play." },
            { kind = "h2",    text = "How logging works" },
            { kind = "p",     text = "Warden keeps the last 500 log lines. Errors are always recorded. Two switches add more detail:" },
            { kind = "bullets", items = {
                "The |em[global log]| \226\128\148 one on/off switch. Records general activity from the whole addon.",
                "|em[Debug categories]| \226\128\148 one switch per feature. A category that is on prints to your chat live and is saved in the log.",
            }},
            { kind = "h2",    text = "Report a bug in five steps" },
            { kind = "steps", items = {
                "Pick the category closest to the problem (list below).",
                "Turn it on: |ck[/wardenlog debug <category> on]|",
                "Do the thing that goes wrong, once.",
                "Read the result: |ck[/wardenlog tail 30]|",
                "Turn it off: |ck[/wardenlog debug reset]|",
            }},
            { kind = "h2",    text = "Log commands" },
            { kind = "table", rows = {
                { "/wardenlog", "Print the last 20 lines." },
                { "/wardenlog tail N", "Print the last N lines." },
                { "/wardenlog all", "Print the whole log." },
                { "/wardenlog status", "Show whether logging is on, the line count, and active categories." },
                { "/wardenlog on", "Turn the global log on." },
                { "/wardenlog off", "Turn the global log off. Errors are still recorded." },
                { "/wardenlog clear", "Erase the log." },
            }},
            { kind = "h2",    text = "Debug commands" },
            { kind = "table", rows = {
                { "/wardenlog debug", "Show which categories are on." },
                { "/wardenlog debug help", "List all categories." },
                { "/wardenlog debug <cat> on", "Turn one category on." },
                { "/wardenlog debug <cat> off", "Turn one category off." },
                { "/wardenlog debug all on", "Turn everything on. Expect a lot of chat lines." },
                { "/wardenlog debug all off", "Turn everything off." },
                { "/wardenlog debug reset", "Clear all debug switches." },
            }},
            { kind = "h2",    text = "Categories" },
            { kind = "table", rows = {
                { "master", "Main window: open, close, tab changes." },
                { "slash", "Slash commands." },
                { "build", "Build and Create: the plan and each step." },
                { "comp", "Bot Comp tab: save, load, build, resync." },
                { "whisper", "The whisper queue." },
                { "respec", "Re-Spec in the Roster tab." },
                { "roster", "Roster list refreshes." },
                { "spec", "Spec tab: target and tile clicks." },
                { "controls", "Every order sent from the Controls tab." },
                { "sword", "WardenSword: show, hide, actions." },
                { "shield", "WardenShield: listening and captured lines." },
                { "combat", "Entering and leaving combat." },
                { "minimap", "Minimap button clicks." },
                { "persist", "Loading and saving your settings." },
                { "settings", "Settings tab changes." },
            }},
            { kind = "h2",    text = "What a debug line looks like" },
            { kind = "p",     text = "In chat, debug lines start with |em[Warden/<category>]| in light blue. In the log they carry a |em[DEBUG]| tag and a time stamp." },
            { kind = "h2",    text = "Where the log is saved" },
            { kind = "p",     text = "The file is |ck[WTF/Account/<account>/SavedVariables/Warden.lua]|. It is written when you log out or |ck[/reload]|. Inside: |ck[WardenLog]| (the lines), |ck[WardenDebug]| (category switches), |ck[WardenLogEnabled]| (global switch)." },
        },
    },
}

-- =====================================================================
-- §3.4 renderers
-- Each takes (content, y, node) and returns the new y.
--
-- Region pooling: WoW never garbage-collects a created FontString/Texture/
-- Frame, so the old approach of CreateFontString-per-render leaked a fresh
-- set of regions on every chapter click for the whole session. Instead we
-- keep one pool per region "kind" and REUSE regions across SetChapter calls.
-- SetChapter resets every pool's cursor before rendering (poolReset), each
-- renderer acquire()s regions in order (creating one only if the pool has no
-- free slot at that cursor), and after rendering any pooled regions the new
-- chapter didn't use are hidden (poolHideUnused). Visible output is identical.
-- =====================================================================
local T = ns.Tokens

-- kind -> { list = { region, ... }, cursor = <count used this render> }
local _pools = {}

-- Rewind every pool so the next render reuses regions from the start.
local function poolReset()
    for _, p in pairs(_pools) do p.cursor = 0 end
end

-- Return the next free region of `kind`, creating it via factory() only if the
-- pool doesn't already have one at this cursor position. Caller re-anchors and
-- re-configures it, so we clear points and show it here.
local function acquire(kind, factory)
    local p = _pools[kind]
    if not p then p = { list = {}, cursor = 0 }; _pools[kind] = p end
    p.cursor = p.cursor + 1
    local r = p.list[p.cursor]
    if not r then
        r = factory()
        p.list[p.cursor] = r
    end
    r:ClearAllPoints()
    r:Show()
    return r
end

-- Hide any pooled regions left over past each pool's cursor (i.e. created for a
-- busier chapter but unused by the current one).
local function poolHideUnused()
    for _, p in pairs(_pools) do
        for i = p.cursor + 1, #p.list do
            p.list[i]:Hide()
            p.list[i]:ClearAllPoints()
        end
    end
end

local function readerInnerW(content)
    local w = content:GetWidth()
    if not w or w <= 0 then return 500 end
    return w
end

local function renderLede(content, y, node)
    local w = readerInnerW(content) - READER_PAD_SIDE * 2 - 10
    local fs = acquire("lede.fs", function()
        return content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    end)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE + 10, y)
    fs:SetWidth(math.max(50, w))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
    fs:SetText(ns.UI.RichText.Format(node.text or ""))
    fs:SetTextColor(0.851, 0.804, 0.690, 1) -- parchment
    local h = math.max(14, fs:GetStringHeight())
    fs:SetHeight(h)

    local rule = acquire("lede.rule", function()
        return content:CreateTexture(nil, "ARTWORK")
    end)
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 0.9)
    rule:SetWidth(2)
    rule:SetPoint("TOPLEFT",    content, "TOPLEFT", READER_PAD_SIDE, y)
    rule:SetPoint("BOTTOMLEFT", content, "TOPLEFT", READER_PAD_SIDE, y - h)

    return y - h - 14
end

local function renderH2(content, y, node)
    y = y - 16
    local fs = acquire("h2.fs", function()
        return content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE + 12, y)
    fs:SetWidth(readerInnerW(content) - READER_PAD_SIDE * 2 - 12)
    fs:SetJustifyH("LEFT")
    fs:SetText(node.text or "")
    fs:SetTextColor(T.text_warm[1], T.text_warm[2], T.text_warm[3], 1)
    local h = fs:GetStringHeight()
    fs:SetHeight(h)

    local pip = acquire("h2.pip", function()
        return content:CreateTexture(nil, "ARTWORK")
    end)
    pip:SetTexture("Interface\\Buttons\\WHITE8x8")
    pip:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 1)
    pip:SetSize(4, 4)
    pip:SetPoint("LEFT", fs, "LEFT", -8, 0)

    return y - h - 6
end

local function renderP(content, y, node)
    local w = readerInnerW(content) - READER_PAD_SIDE * 2
    local fs = acquire("p.fs", function()
        return content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    end)
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
    fs:SetWidth(math.max(50, w))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
    fs:SetText(ns.UI.RichText.Format(node.text or ""))
    fs:SetHeight(fs:GetStringHeight())
    return y - fs:GetStringHeight() - 10
end

local function renderSteps(content, y, node)
    local items = node.items or {}
    local textX  = READER_PAD_SIDE + 32
    local textW  = readerInnerW(content) - READER_PAD_SIDE * 2 - 32

    for i, txt in ipairs(items) do
        local rowTop = y

        -- The number badge lives as a child FontString on the pooled pad frame
        -- (pad.num), so it is reused whenever the pad is reused.
        local pad = acquire("steps.pad", function()
            local f = CreateFrame("Frame", nil, content)
            f:SetBackdrop(ns.UI.FLAT_BACKDROP)
            f.num = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.num:SetPoint("CENTER", f, "CENTER", 0, 0)
            return f
        end)
        pad:SetSize(20, 20)
        pad:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, rowTop - 1)
        pad:SetBackdropColor(T.stone_tile[1], T.stone_tile[2], T.stone_tile[3], 1)
        pad:SetBackdropBorderColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)

        local n = pad.num
        n:SetText(tostring(i))
        n:SetTextColor(T.gold[1], T.gold[2], T.gold[3], 1)

        local fs = acquire("steps.fs", function()
            return content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        end)
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", textX, rowTop)
        fs:SetWidth(math.max(50, textW))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
        fs:SetText(ns.UI.RichText.Format(txt or ""))
        local h = math.max(20, fs:GetStringHeight())
        fs:SetHeight(h)

        y = rowTop - h - 8
    end
    return y - 6
end

local function renderBullets(content, y, node)
    local items = node.items or {}
    local textX  = READER_PAD_SIDE + 16
    local textW  = readerInnerW(content) - READER_PAD_SIDE * 2 - 16

    for _, txt in ipairs(items) do
        local rowTop = y

        local fs = acquire("bullets.fs", function()
            return content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        end)
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", textX, rowTop)
        fs:SetWidth(math.max(50, textW))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
        fs:SetText(ns.UI.RichText.Format(txt or ""))
        local h = math.max(14, fs:GetStringHeight())
        fs:SetHeight(h)

        local dot = acquire("bullets.dot", function()
            return content:CreateTexture(nil, "ARTWORK")
        end)
        dot:SetTexture("Interface\\Buttons\\WHITE8x8")
        dot:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
        dot:SetSize(4, 1)
        dot:SetPoint("LEFT", fs, "LEFT", -12, 4)

        y = rowTop - h - 3
    end
    return y - 11
end

local function renderCmd(content, y, node)
    local outerW = readerInnerW(content) - READER_PAD_SIDE * 2
    -- The accent bar and body text are child regions of the pooled frame
    -- (frame.accent / frame.textfs), so they are reused whenever it is.
    local frame = acquire("cmd.frame", function()
        local f = CreateFrame("Frame", nil, content)
        f:SetBackdrop(ns.UI.FLAT_BACKDROP)
        f.accent = f:CreateTexture(nil, "ARTWORK")
        f.accent:SetTexture("Interface\\Buttons\\WHITE8x8")
        f.accent:SetWidth(2)
        f.accent:SetPoint("TOPLEFT",    f, "TOPLEFT",    0, 0)
        f.accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)

        f.textfs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.textfs:SetPoint("TOPLEFT",     f, "TOPLEFT",      12, -8)
        f.textfs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  -8, 8)
        f.textfs:SetJustifyH("LEFT"); f.textfs:SetJustifyV("TOP")
        f.textfs:SetWordWrap(true); f.textfs:SetNonSpaceWrap(false)
        return f
    end)
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
    frame:SetWidth(math.max(50, outerW))
    frame:SetBackdropColor(T.stone_mid[1], T.stone_mid[2], T.stone_mid[3], 1)
    frame:SetBackdropBorderColor(T.stone_rim[1], T.stone_rim[2], T.stone_rim[3], 1)

    local accent = frame.accent
    accent:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)

    local fs = frame.textfs
    fs:SetText(ns.UI.RichText.Format(node.text or ""))
    fs:SetTextColor(T.text_warm[1], T.text_warm[2], T.text_warm[3], 1)

    local h = math.max(22, fs:GetStringHeight() + 16)
    frame:SetHeight(h)
    return y - h - 14
end

local function renderTable(content, y, node)
    local rows  = node.rows or {}
    local innerW = readerInnerW(content) - READER_PAD_SIDE * 2
    local leftW  = math.floor(innerW * 0.36)
    local gutter = 14
    local rightW = innerW - leftW - gutter

    for _, row in ipairs(rows) do
        local rowTop = y
        local cmd, desc = row[1] or "", row[2] or ""

        local L = acquire("table.L", function()
            return content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        end)
        L:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, rowTop)
        L:SetWidth(leftW)
        L:SetJustifyH("LEFT")
        L:SetWordWrap(true); L:SetNonSpaceWrap(false)
        L:SetText("|cffffd100" .. cmd .. "|r")

        local R = acquire("table.R", function()
            return content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        end)
        R:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE + leftW + gutter, rowTop)
        R:SetWidth(rightW)
        R:SetJustifyH("LEFT")
        R:SetWordWrap(true); R:SetNonSpaceWrap(false)
        R:SetText(ns.UI.RichText.Format(desc))

        local h = math.max(L:GetStringHeight(), R:GetStringHeight()) + 6

        local rule = acquire("table.rule", function()
            return content:CreateTexture(nil, "ARTWORK")
        end)
        rule:SetTexture("Interface\\Buttons\\WHITE8x8")
        rule:SetVertexColor(T.stone_rim[1], T.stone_rim[2], T.stone_rim[3], 0.4)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE,         rowTop - h + 1)
        rule:SetPoint("RIGHT",   content, "RIGHT",   -READER_PAD_SIDE,        0)

        y = rowTop - h
    end
    return y - 14
end

local DISPATCH = {
    lede    = renderLede,
    h2      = renderH2,
    p       = renderP,
    steps   = renderSteps,
    bullets = renderBullets,
    cmd     = renderCmd,
    table   = renderTable,
}

-- =====================================================================
-- §3.5 rail builder + §3.6 reader/SetChapter
-- =====================================================================
local _readerContent, _readerScroll
local _rowFrames

local function buildRail(parent)
    local rail = CreateFrame("Frame", "WardenHelpRail", parent)
    rail:SetWidth(RAIL_W)
    rail:SetPoint("TOPLEFT",    parent, "TOPLEFT",    0, 0)
    rail:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)

    local bg = rail:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(T.stone_mid[1], T.stone_mid[2], T.stone_mid[3], 1)
    bg:SetAllPoints()

    local border = rail:CreateTexture(nil, "BORDER")
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(T.stone_rim[1], T.stone_rim[2], T.stone_rim[3], 1)
    border:SetWidth(1)
    border:SetPoint("TOPRIGHT",    rail, "TOPRIGHT",    0, 0)
    border:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)

    local eye = rail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eye:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -12)
    eye:SetText("CONTENTS")
    eye:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)

    local sf = CreateFrame("ScrollFrame", "WardenHelpRailScroll", rail, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     rail, "TOPLEFT",      6, -32)
    sf:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -6,   8)

    ns.UI.ThinScrollbar(sf, 6)

    local list = CreateFrame("Frame", nil, sf)
    list:SetSize(RAIL_W - 14, 10)
    sf:SetScrollChild(list)

    local rowFrames = {}
    local y = 0
    local currentGroup = nil
    for i, ch in ipairs(CHAPTERS) do
        if ch.group ~= currentGroup then
            currentGroup = ch.group
            local gh = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            gh:SetPoint("TOPLEFT", list, "TOPLEFT", 8, y - 8)
            gh:SetText(ch.group)
            gh:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
            y = y - GROUP_H
        end

        local row = CreateFrame("Frame", nil, list)
        row:SetSize(RAIL_W - 14, CHAP_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
        row:EnableMouse(true)
        row.id = ch.id
        rowFrames[ch.id] = row

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.bg:SetVertexColor(T.stone_tile[1], T.stone_tile[2], T.stone_tile[3], 1)
        row.bg:SetAllPoints()
        row.bg:Hide()

        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.accent:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 1)
        row.accent:SetWidth(2)
        row.accent:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.accent:Hide()

        row.ix = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.ix:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.ix:SetWidth(16); row.ix:SetJustifyH("RIGHT")
        row.ix:SetText(string.format("%02d", i))
        row.ix:SetTextColor(T.stone_rim[1], T.stone_rim[2], T.stone_rim[3], 1)

        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.title:SetPoint("LEFT", row.ix, "RIGHT", 8, 0)
        row.title:SetWidth(RAIL_W - 14 - 32 - 8)
        row.title:SetJustifyH("LEFT")
        row.title:SetText(ch.title)
        row.title:SetTextColor(T.gold_dim[1], T.gold_dim[2], T.gold_dim[3], 1)

        row:SetScript("OnEnter", function(s)
            if not s._active then
                s.title:SetTextColor(T.text_warm[1], T.text_warm[2], T.text_warm[3], 1)
            end
        end)
        row:SetScript("OnLeave", function(s)
            if not s._active then
                s.title:SetTextColor(T.gold_dim[1], T.gold_dim[2], T.gold_dim[3], 1)
            end
        end)
        row:SetScript("OnMouseUp", function(s, btn)
            if btn == "LeftButton" then ns.UI.Tabs.Help.SetChapter(s.id) end
        end)

        y = y - CHAP_H
    end

    list:SetHeight(math.max(10, -y + 8))
    return rail, rowFrames
end

local function buildReader(parent)
    local reader = CreateFrame("Frame", "WardenHelpReader", parent)
    reader:SetPoint("TOPLEFT",     parent, "TOPLEFT",      RAIL_W, 0)
    reader:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",  0,      0)

    local bg = reader:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(T.stone_dark[1], T.stone_dark[2], T.stone_dark[3], 1)
    bg:SetAllPoints()

    local sf = CreateFrame("ScrollFrame", "WardenHelpReaderScroll", reader, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     reader, "TOPLEFT",      0,                0)
    sf:SetPoint("BOTTOMRIGHT", reader, "BOTTOMRIGHT", -SCROLLBAR_PAD,    0)

    ns.UI.ThinScrollbar(sf, SCROLLBAR_W)

    local content = CreateFrame("Frame", nil, sf)
    -- Width follows the reader at build time; resized again if the parent
    -- pane is laid out after BuildInto.
    local rw = (parent:GetWidth() or 720) - RAIL_W - SCROLLBAR_PAD - SCROLLBAR_W
    content:SetSize(math.max(120, rw), 10)
    sf:SetScrollChild(content)

    -- If the pane's width changes after BuildInto (e.g., Window-size dropdown),
    -- reflow the content width on the next OnSizeChanged event. HookScript
    -- cannot be un-hooked, so guard with a flag: if BuildInto ever runs twice
    -- the handler would otherwise stack.
    if not parent._helpHooked then
        parent._helpHooked = true
        parent:HookScript("OnSizeChanged", function(_, w)
            if not w or w <= 0 then return end
            local nw = w - RAIL_W - SCROLLBAR_PAD - SCROLLBAR_W
            if nw > 0 then content:SetWidth(nw) end
        end)
    end

    _readerContent, _readerScroll = content, sf
    return reader
end

function ns.UI.Tabs.Help.SetChapter(id)
    if not _readerContent then return end

    local ch
    for _, c in ipairs(CHAPTERS) do
        if c.id == id then ch = c; break end
    end
    if not ch then return end

    -- Rewind every region pool so this render reuses regions instead of
    -- creating new ones. The masthead regions below are pooled too.
    poolReset()

    local content = _readerContent
    local y = -READER_PAD_TOP

    local eye = acquire("head.eye", function()
        return content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    end)
    eye:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
    eye:SetText(ch.eyebrow or "")
    eye:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
    y = y - 14

    local h1 = acquire("head.h1", function()
        return content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    end)
    h1:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
    h1:SetText(ch.title)
    h1:SetTextColor(T.gold[1], T.gold[2], T.gold[3], 1)
    y = y - 30

    -- Masthead sub-line only on the intro chapter (per spec §4.3). Pooled like
    -- the rest; poolHideUnused hides it on chapters that don't render it.
    if ch.id == "intro" then
        local sub = acquire("head.sub", function()
            return content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        end)
        sub:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
        sub:SetText("raid commander \194\183 WarStormBot UI \194\183 v" ..
            (GetAddOnMetadata("Warden", "Version") or "?"))
        sub:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
        y = y - 16
    end

    local rule = acquire("head.rule", function()
        return content:CreateTexture(nil, "ARTWORK")
    end)
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
    rule:SetPoint("RIGHT",   content, "RIGHT",   -READER_PAD_SIDE, 0)
    y = y - 14

    for _, node in ipairs(ch.body or {}) do
        local fn = DISPATCH[node.kind]
        if fn then y = fn(_readerContent, y, node) end
    end

    -- Hide any pooled regions the previous (busier) chapter used but this one
    -- didn't, so leftovers never render on top of the new chapter.
    poolHideUnused()

    _readerContent:SetHeight(math.max(10, -y + READER_PAD_BOT))
    if _readerScroll then _readerScroll:SetVerticalScroll(0) end

    if _rowFrames then
        for rid, row in pairs(_rowFrames) do
            local on = (rid == id)
            row._active = on
            if on then row.bg:Show()     else row.bg:Hide()     end
            if on then row.accent:Show() else row.accent:Hide() end
            if on then
                row.title:SetTextColor(T.gold[1], T.gold[2], T.gold[3], 1)
                row.ix:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
            else
                row.title:SetTextColor(T.gold_dim[1], T.gold_dim[2], T.gold_dim[3], 1)
                row.ix:SetTextColor(T.stone_rim[1], T.stone_rim[2], T.stone_rim[3], 1)
            end
        end
    end

    if WardenDB then WardenDB.helpLastChapter = id end
    if ns.Persistence and ns.Persistence.DB then
        ns.Persistence.DB.helpLastChapter = id
    end
end

function ns.UI.Tabs.Help.BuildInto(pane)
    local rail, rowFrames = buildRail(pane)
    _rowFrames = rowFrames
    buildReader(pane)

    local db = (ns.Persistence and ns.Persistence.DB) or WardenDB
    local startId = (db and db.helpLastChapter) or DEFAULT_CHAPTER
    local found
    for _, c in ipairs(CHAPTERS) do
        if c.id == startId then found = true; break end
    end
    if not found then startId = DEFAULT_CHAPTER end

    ns.UI.Tabs.Help.SetChapter(startId)
end

-- =====================================================
-- Warden - UI_TabHelp.lua
-- v2 rework, May 2026: two-pane chapter rail + scoped reader.
-- =====================================================

local _, ns = ...
ns.UI.Tabs      = ns.UI.Tabs      or {}
ns.UI.Tabs.Help = ns.UI.Tabs.Help or {}

-- §3.1 inline helpers. Authoring shortcuts; rendering goes through
-- ns.UI.RichText.Format so |kbd[X]| / |ck[...]| / |em[...]| inline markers
-- work too.
local function kbd(t) return "|cffffd100[" .. t .. "]|r" end
local function ck(t)  return "|cffffebbf"  .. t .. "|r" end
local function em(t)  return "|cffd9cdb0"  .. t .. "|r" end

-- §3.2 tunables
local RAIL_W            = 180
local READER_PAD_TOP    = 22
local READER_PAD_SIDE   = 28
local READER_PAD_BOT    = 18
local CHAP_H            = 22
local GROUP_H           = 26
local SCROLLBAR_W       = 4
local SCROLLBAR_PAD     = 8
local DEFAULT_CHAPTER   = "intro"

-- §3.3 CHAPTERS data. id is stable; group seeds the rail divider; eyebrow
-- prints above the H1 inside the reader.
local CHAPTERS = {
    -- ---- START HERE ---------------------------------------------------
    {
        id = "intro", group = "START HERE", title = "What is Warden?",
        eyebrow = "Chapter 01 \194\183 Start here",
        body = {
            { kind = "lede", text = "Warden is the in-game UI for WarStormBot. It replaces hundreds of dot-commands and whispers with a visual interface to assemble, spec, command, and trade with your bots." },
            { kind = "p",    text = "Instead of memorising commands or whispering every action by hand, Warden gives you four workflows in one window:" },
            { kind = "bullets", items = {
                "Build raid compositions from presets or a class chip tray.",
                "Summon and spec bots in one click.",
                "Command the raid mid-fight from a floating HUD.",
                "Automate WTS sales to buyer bots.",
            }},
            { kind = "h2",   text = "The four-phase flow" },
            { kind = "p",    text = "Every Warden session goes through the same loop: |em[build]| a comp, |em[spawn]| the bots, |em[command]| them during combat, |em[refine]| the setup when the pull tells you what was missing." },
            { kind = "p",    text = "Everything else in Warden \226\128\148 Settings, Re-Spec, the satellite modules \226\128\148 builds on top of that loop." },
        },
    },
    {
        id = "first-raid", group = "START HERE", title = "Your First Raid",
        eyebrow = "Chapter 02 \194\183 Start here",
        body = {
            { kind = "lede", text = "A typical Warden session goes through four phases \226\128\148 build, spawn, command, refine. This walkthrough takes you end-to-end in under two minutes." },
            { kind = "h2",   text = "The four-step flow" },
            { kind = "steps", items = {
                "Type |ck[/warden]| in chat to open the main window.",
                "Click the |kbd[Bot Comp]| tab at the bottom.",
                "Pick a preset from the dropdown \226\128\148 or build your own from the chip tray.",
                "Press |kbd[Build]|. Warden spawns every non-player slot and whispers each spec.",
            }},
            { kind = "h2",   text = "What happens during Build" },
            { kind = "p",    text = "Bots spawn one every 0.9s \226\128\148 fast enough to be ready before you finish summoning your party, slow enough to never trip Blizzard's command throttle. As each bot joins, Warden whispers its planned spec on a 0.45s cadence. Any slot flagged |kbd[P]| is skipped: that's where you (or another human) will sit." },
            { kind = "h2",   text = "Commanding mid-fight" },
            { kind = "p",    text = "Open WardenSword with |ck[/ws]| for a small floating HUD that surfaces the actions you'll need during a pull \226\128\148 Summon, Stay, AoE, Burn, Bloodlust, role orders. The main window stays closed." },
        },
    },
    {
        id = "nav", group = "START HERE", title = "Navigation",
        eyebrow = "Chapter 03 \194\183 Start here",
        body = {
            { kind = "lede", text = "Warden's main window has six tabs along the bottom edge \226\128\148 click or press |kbd[1]|\226\128\147|kbd[6]|. Everything else is reachable from one of three places: the minimap button, the slash commands, or the persistent footer." },
            { kind = "h2",   text = "Minimap button" },
            { kind = "bullets", items = {
                "|kbd[Left-click]| toggles the main window.",
                "|kbd[Shift-left]| opens Settings.",
                "|kbd[Middle-click]| toggles the WardenSword HUD.",
                "|kbd[Shift+Middle]| toggles WardenShield (|ck[/wsh]|).",
                "|kbd[Ctrl+Middle]| toggles WardenPocket (|ck[/wp]|).",
                "|kbd[Right-click]| opens this Help tab.",
                "Drag to orbit the minimap.",
            }},
            { kind = "h2",   text = "Slash commands" },
            { kind = "table", rows = {
                { "/warden",  "Toggle the main window." },
                { "/wden",    "Short alias for |ck[/warden]|." },
                { "/ws",      "Toggle the WardenSword HUD." },
                { "/wsh",     "Toggle WardenShield." },
                { "/wp",      "Toggle WardenPocket." },
                { "/wardenlog", "Open log viewer and debug toggles." },
            }},
            { kind = "h2",   text = "Status footer" },
            { kind = "p",    text = "The bar visible at the bottom of every tab shows live raid state \226\128\148 current target, queue depth, tracked bots, Bloodlust on/off, plus a slash-command hint. Updates on roster/target events and every 0.5s." },
            { kind = "h2",   text = "Window size" },
            { kind = "p",    text = "Pick Small / Medium / Large / XL in Settings \226\134\146 Window size. Applies live. Mousewheel zoom is intentionally not bound." },
        },
    },

    -- ---- RAID FLOW ----------------------------------------------------
    {
        id = "comp", group = "RAID FLOW", title = "Bot Comp",
        eyebrow = "Chapter 04 \194\183 Raid flow",
        body = {
            { kind = "lede", text = "A comp is a planned raid roster \226\128\148 class + spec + buff assignments per slot. Saved locally under a name you pick and shareable as a single paste-string." },
            { kind = "h2",   text = "Sizes and grid" },
            { kind = "p",    text = "Pick a raid size; the grid adapts from 5 through 40. Columns are groups (G1 to Gn); rows are positions within a group. Each slot shows a 14px class circle, class-coloured name, and spec. Empty slots show |kbd[+]|. Click to select; right-click to remove." },
            { kind = "h2",   text = "Chip tray" },
            { kind = "p",    text = "Ten class chips along the side. |kbd[Click]| adds one to the next empty slot. |kbd[Shift-click]| prompts for N copies. |kbd[Drag]| a chip onto a slot to drop it there (overwrites the existing slot)." },
            { kind = "h2",   text = "Slot detail" },
            { kind = "p",    text = "CLASS / SPEC / BLESSING-TOTEM / AURA-RESIST dropdowns set the whispered talent + |ck[nc +X]| strategies. |kbd[move]| shifts to the next empty slot. |kbd[duplicate]| copies the slot. |kbd[remove]| clears it. |kbd[P]| toggles the human-player flag." },
            { kind = "h2",   text = "Player slots and [P]" },
            { kind = "p",    text = "Any slot flagged |kbd[P]| is never summoned, re-spec'd, or modified by automated systems. At Build time, if the comp has a |kbd[P]| slot and you have raid assistant/leader rights, Warden calls |ck[SetRaidSubgroup]| to move you into that slot's group before spawning bots \226\128\148 fixes the 'caster group drifts to G2 because the player is stuck in G1' problem." },
            { kind = "h2",   text = "Coverage" },
            { kind = "p",    text = "Scannable status of key raid buffs. |kbd[+]| (green) = covered by at least one filled slot. |kbd[!]| (amber) = nobody is assigned to provide it. Kings / Might / Wisdom / Sanct / Melee / Caster / Tank / Frost / Fire / Shadow / Nature each get a pill." },
            { kind = "h2",   text = "Build" },
            { kind = "p",    text = "Primary CTA. Spawns |ck[.warstormbot bot addclass]| for each non-player slot and whispers the planned spec + strategies as each bot joins. Bot spawning is paced to avoid command flooding. Warden remembers bot assignments by GUID so Re-Spec can restore the correct setup after reconnects." },
            { kind = "h2",   text = "Save, load, delete" },
            { kind = "p",    text = "|kbd[save]| stores the current comp (name + size + slot positions + isPlayer flags). |kbd[load]| restores it by name. |kbd[delete]| removes the comp named in the COMP box (confirmation required). All comps \226\128\148 including the default raid presets \226\128\148 live in |ck[WardenDB.comps]| and are fully editable. Use Settings \226\134\146 Maintenance \226\134\146 Restore default presets to re-seed any defaults you've deleted." },
            { kind = "h2",   text = "Import and export" },
            { kind = "p",    text = "|kbd[export]| produces a portable |ck[WRDN2:]| string that carries the full comp (name, size, slot positions, isPlayer, blessings). |kbd[import]| accepts the same string. |ck[WRDN1:]| strings from older versions still parse (loose slot order, no player flags)." },
            { kind = "h2",   text = "Clear and cleanup" },
            { kind = "p",    text = "|kbd[clear]| empties the grid locally (no server command). |kbd[cleanup]| sends |ck[.warstormbot bot remove *]| to despawn every bot in the raid (confirmation popup)." },
            { kind = "h2",   text = "Presets" },
            { kind = "p",    text = "Eleven default raid presets (5-man + Onyxia / Ulduar / ToC / ICC / Ruby Sanctum 10 & 25) are seeded on first use and behave like any other saved comp \226\128\148 fully editable and deletable. Picking one loads the grid; your typed comp name is replaced." },
            { kind = "h2",   text = "Speccing a bot" },
            { kind = "p",    text = "The Spec tab shows the targeted bot's portrait, level, class, and faction. Four-column grid of specs; each tile shows a class-coloured name and a |em[pve - role]| subtitle. The recommended PvE spec gets a gold border. Click a tile to whisper the talent; Warden remembers the bot by GUID so Re-Spec re-applies after a reconnect." },
            { kind = "h2",   text = "Target history" },
            { kind = "p",    text = "|kbd[< prev target]| is a secure button that runs |ck[/targetlasttarget]| \226\128\148 it never trips Blizzard's protected-action taint warning. Click |kbd[history v]| to reveal the last six targets as secure buttons; click an entry to re-target. The popup auto-hides on combat entry." },
            { kind = "h2",   text = "Quick raid buffs" },
            { kind = "p",    text = "The right side of the target card broadcasts |ck[autogear]| to PARTY or |ck[nc +worldbuff]| to RAID." },
        },
    },
    {
        id = "roster", group = "RAID FLOW", title = "Roster & Re-Spec",
        eyebrow = "Chapter 05 \194\183 Raid flow",
        body = {
            { kind = "lede", text = "Live overview of every tracked raid member. Bots are grouped by role (Tanks / Healers / DPS); each row shows class, spec, buff coverage, and a Re-Spec button." },
            { kind = "h2",   text = "Filter" },
            { kind = "p",    text = "All / Tanks / Healers / DPS dropdown, plus a name search and |kbd[Refresh]|." },
            { kind = "h2",   text = "Row layout" },
            { kind = "p",    text = "|kbd[P]| | checkbox | class avatar | two-line name block (class-coloured name + |em[Class - spec]|) | spec dropdown | provides chips | Re-Spec button." },
            { kind = "h2",   text = "Player flag [P]" },
            { kind = "p",    text = "Click the per-row |kbd[P]| to mark that character as a human (NOT a bot). Flag persists by name in |ck[WardenDB.playerFlags]|. Flagged members are skipped by Re-Spec, bulk Re-Spec, auto-spec-on-join, and Build whispers. Your own character is auto-flagged on first login." },
            { kind = "h2",   text = "Provides chips" },
            { kind = "p",    text = "Per-class buff abbreviations (KNG / MGT / WIS / SAN / SoE / WF / FT / MS / BS / CS / ASP). Gold = THIS slot is assigned to cast that buff in the current comp. Muted = not assigned. Priests, mages, warlocks, and rogues show no chips." },
            { kind = "h2",   text = "Re-Spec" },
            { kind = "p",    text = "The per-row button re-whispers the selected spec to the bot. Useful when a bot reconnects, a spec was changed manually, or a raid setup drifts. Disabled for your own row and for any row flagged |kbd[P]|." },
            { kind = "h2",   text = "Bulk actions" },
            { kind = "p",    text = "|kbd[Re-Spec All Tracked]| re-whispers every tracked raid member. |kbd[Re-Spec Selected]| only fires on rows with the checkbox ticked. Both skip flagged players." },
            { kind = "h2",   text = "Auto-Spec on Build" },
            { kind = "p",    text = "When enabled in Settings, bots spawned during a Build are automatically assigned their planned spec. This removes the need to manually configure every bot after summoning." },
        },
    },
    {
        id = "controls", group = "RAID FLOW", title = "Controls",
        eyebrow = "Chapter 06 \194\183 Raid flow",
        body = {
            { kind = "lede", text = "The primary command center for raid behaviour. Most actions broadcast instantly through whispers to the bots." },
            { kind = "h2",   text = "Movement" },
            { kind = "p",    text = "Summon, Follow, Stay, Free, Release, Drink. Top row is the hot path \226\128\148 Summon is the primary." },
            { kind = "h2",   text = "Strategy" },
            { kind = "p",    text = "AoE on/off, burn cooldowns, face-behind vs no-flank. Three inline groups, two buttons each." },
            { kind = "h2",   text = "Marks and formation" },
            { kind = "p",    text = "Skull and Moon mark+attack/CC, disperse-distance dropdown, formation dropdown with set/check." },
            { kind = "h2",   text = "Role commands" },
            { kind = "p",    text = "Per-role commands in a 5\194\1574 matrix. |kbd[Atk]| is the primary launch; |kbd[Stay]| / |kbd[Fol]| / |kbd[Flee]| are safe stone buttons with amber/gold/red text. Shift-click flashes the affected row." },
            { kind = "h2",   text = "Bloodlust toggle" },
            { kind = "p",    text = "The |kbd[BL]| pill on the master footer toggles Bloodlust/Heroism. Green = ON; amber = OFF. Clicking whispers |ck[ss +/-2825]| (Horde shamans) or |ck[ss +/-32182]| (Alliance shamans) to toggle each shaman's spell-exclude list. Default state is OFF to protect pulls that don't want lust." },
            { kind = "h2",   text = "Danger zone" },
            { kind = "p",    text = "Irreversible actions. Smart ReSpec is safe (targeted retry). Reset AI, Hard ReSpec, and Cleanup all ask for confirmation before running." },
            { kind = "h2",   text = "Summon by class" },
            { kind = "p",    text = "Bottom panel \226\128\148 2\194\1575 grid of class-coloured buttons. One click sends |ck[.warstormbot bot addclass <class>]| to spawn a single bot. Useful for questing, dungeon replacements, small-group PvE, and fast testing." },
        },
    },

    -- ---- MODULES ------------------------------------------------------
    {
        id = "sword", group = "MODULES", title = "WardenSword",
        eyebrow = "Chapter 07 \194\183 Modules",
        body = {
            { kind = "lede", text = "A small, draggable floating panel for the person commanding the bot raid during combat. Surfaces the actions you hit most often mid-fight so you don't need to reopen the main window between pulls." },
            { kind = "h2",   text = "Open and close" },
            { kind = "p",    text = "|ck[/ws]| toggles. |kbd[Middle-click]| on the minimap button works too. |kbd[x]| on the header hides it; reopen with the same slash." },
            { kind = "h2",   text = "Lock and unlock" },
            { kind = "p",    text = "The |kbd[o]| circle on the header toggles drag-lock. Locked = no accidental drags mid-pull. State persists across |ck[/reload]|." },
            { kind = "h2",   text = "Auto-show" },
            { kind = "p",    text = "By default the HUD auto-opens on combat start. Turn off under Settings \226\134\146 WardenSword \226\134\146 Auto-show in combat." },
            { kind = "h2",   text = "Movement" },
            { kind = "p",    text = "2\194\1572 grid: Summon / Follow (all bots) / Stay / Flee. Top-left is the hot path." },
            { kind = "h2",   text = "Strategy" },
            { kind = "p",    text = "AoE toggle, Burn cooldowns toggle, Skull (mark target + attack)." },
            { kind = "h2",   text = "Role matrix" },
            { kind = "p",    text = "Optional 3\194\1573 grid \226\128\148 TANK / HEAL / DPS rows, each with Atk / Follow / Stay. Routes through |ck[@tank]| / |ck[@heal]| / |ck[@dps]| scoping so you can split the raid on demand." },
            { kind = "h2",   text = "Bloodlust" },
            { kind = "p",    text = "Full-width button at the bottom. Turns red when ON. Whispers |ck[ss +/-2825]| (Horde) or |ck[ss +/-32182]| (Alliance) to every shaman in group." },
            { kind = "h2",   text = "Settings" },
            { kind = "p",    text = "Settings tab has a WARDENSWORD panel: auto-show, status strip, roles row, start locked, hide-minimap-in-combat, density, transparency slider, and Reset HUD position." },
            { kind = "h2",   text = "Player guard" },
            { kind = "p",    text = "Every WardenSword action routes through the same engine helpers as the main tabs, so characters flagged |kbd[P]| in Roster / Bot Comp are skipped automatically." },
            { kind = "h2",   text = "Commands" },
            { kind = "table", rows = {
                { "/ws",                "Toggle the HUD." },
                { "/ws <action>",       "Direct fire: |ck[summon]| / |ck[follow]| / |ck[stay]| / |ck[flee]| / |ck[aoe]| / |ck[burn]| / |ck[skull]| / |ck[bl]|." },
                { "/ws @role act",      "Role-scoped: |ck[@tank follow/atk/stay]|, |ck[@heal ...]|, |ck[@dps ...]|." },
                { "/ws lock / unlock",  "Drag-lock toggle." },
                { "/ws reset",          "Reset HUD position." },
                { "/ws config",         "Open Warden Settings (WardenSword panel)." },
                { "/ws help",           "Print the full command reference in chat." },
            }},
        },
    },
    {
        id = "shield", group = "MODULES", title = "WardenShield",
        eyebrow = "Chapter 08 \194\183 Modules",
        body = {
            { kind = "lede", text = "Turns a bot's spellbook and surroundings into a clickable list. Instead of memorising spell names, IDs, or exclusion commands, discover and interact with everything visually." },
            { kind = "h2",   text = "What it does" },
            { kind = "bullets", items = {
                "Show nearby objects via |ck[los]|.",
                "Show a bot's available spells via |ck[spells]|.",
                "Cast discovered spells, on yourself, or on another target.",
                "Ban or unban spells from the exclusion list.",
            }},
            { kind = "h2",   text = "Open and close" },
            { kind = "p",    text = "|ck[/wsh]| toggles. The header |kbd[o]| glyph locks/unlocks position. |kbd[x]| closes. State persists across |ck[/reload]|." },
            { kind = "h2",   text = "Target anchor and locking" },
            { kind = "p",    text = "Top band shows the live target in dim type. Click |kbd[pick]| to freeze it (class-coloured name + |kbd[LOCKED]| indicator). Future |ck[los]| / |ck[spells]| whispers go to the locked bot even if you retarget in-game. Useful when managing support bots during raids." },
            { kind = "h2",   text = "Action row" },
            { kind = "p",    text = "|kbd[los]| lists nearby objects, |kbd[spells]| lists the bot's spells. |kbd[clear]| wipes the captured list and unlocks the target. The active button flashes gold while the capture window is open (~5s by default)." },
            { kind = "h2",   text = "Mode (segmented)" },
            { kind = "p",    text = "Five mutually-exclusive modes set what clicking a row does: |kbd[cast]| (whisper the spell/object), |kbd[on Y]| (cast on a captured unit), |kbd[on me]| (cast on yourself), |kbd[ban]| / |kbd[unban]| (toggle the bot's exclude list)." },
            { kind = "h2",   text = "Cast-on chip" },
            { kind = "p",    text = "Visible only in |kbd[on Y]| mode. Dashed gold = waiting for a target; click any unit frame to capture the name and the chip turns solid. Click the chip itself to drop the captured target." },
            { kind = "h2",   text = "Exclusion management" },
            { kind = "p",    text = "Instead of typing raw |ck[ss +2825]| / |ck[ss -2825]|, view the spell list, see which are currently banned (red dot, dimmed text), and click to toggle. Especially useful for Bloodlust control, AI cleanup, and preventing unwanted spell usage." },
            { kind = "h2",   text = "Filter" },
            { kind = "p",    text = "When a capture has more than 20 items, a text filter appears above the list. Case-insensitive substring match on the payload. Wipes on |kbd[clear]| and on every new |ck[los]| / |ck[spells]|." },
            { kind = "h2",   text = "Footer" },
            { kind = "p",    text = "|kbd[hide gray]| filters out spells the bot can't currently cast \226\128\148 auto-bypassed in |kbd[ban]| / |kbd[unban]| modes. |kbd[exclusions: N]| toggles a view that lists every persisted exclusion (click a row to unban). |kbd[reset all]| whispers |ck[ss reset]| to the locked bot and wipes the local mirror." },
            { kind = "h2",   text = "Multi-bot" },
            { kind = "p",    text = "If you capture from several different bots in a row, each row gets a small gold-dim tag on the right showing which bot produced it. Click dispatches to that bot, not the currently-locked target." },
            { kind = "h2",   text = "Commands" },
            { kind = "table", rows = {
                { "/wsh",                "Toggle the HUD." },
                { "/wsh show / hide",    "Explicit visibility." },
                { "/wsh lock / unlock",  "Drag-lock toggle." },
                { "/wsh reset",    "Reset HUD position." },
                { "/wsh clear",    "Wipe captured list." },
                { "/wsh los",      "Fire |ck[los]| immediately on the targeted (or locked) bot." },
                { "/wsh spells",   "Fire |ck[spells]| immediately on the targeted (or locked) bot." },
                { "/wsh help",     "Print the full command reference in chat." },
            }},
        },
    },
    {
        id = "pocket", group = "MODULES", title = "WardenPocket",
        eyebrow = "Chapter 09 \194\183 Modules",
        body = {
            { kind = "lede", text = "Automates WTS sales to bot buyers. Drop an item, click WTS, Pocket handles broadcast, listen, rank, invite, trade-request, item placement, and price whisper. Final |ck[AcceptTrade()]| is a protected WoW function and still requires one click." },

            { kind = "h2",   text = "Open and close" },
            { kind = "p",    text = "|ck[/wp]| toggles. |kbd[Ctrl+Middle-click]| on the minimap button is the keyboard-free equivalent. |kbd[x]| in the header hides. |ck[/wp <text>]| toggles and pre-fills the input field." },

            { kind = "h2",   text = "Item slot" },
            { kind = "p",    text = "32\194\15732 drop target. Four ways to fill it:" },
            { kind = "bullets", items = {
                "Drag an item from your bag.",
                "Click while holding an item on the cursor.",
                "Shift-click a bag item with the slot's input field focused.",
                "|kbd[Ctrl+Right-click]| any bag item while Pocket is open \226\128\148 captures that item into the slot. Plain right-click (equip / use) is unchanged.",
            }},
            { kind = "p",    text = "Empty slot shows a gold-dim |kbd[+]| placeholder with the hint |em[drop item or shift-click from bag]|; filled slot shows the actual item icon and name." },

            { kind = "h2",   text = "WTS button" },
            { kind = "p",    text = "Broadcasts |ck[wts <item link>]| to channel 1 (General). Disabled until a real |ck[|H...]| item link is in the slot. Each click resets offers / timers and re-arms listening." },

            { kind = "h2",   text = "Auto-invite rule" },
            { kind = "p",    text = "Editable phrase row: |em[Auto-invite after N offers or Ns]|. Whichever cap fires first triggers the invite. Set either to |kbd[0]| to disable that cap. A third trigger \226\128\148 2s of whisper silence \226\128\148 fires regardless. Both fields are |kbd[persisted]| across sessions in |ck[WardenDB.pocket]|." },

            { kind = "h2",   text = "Toggles" },
            { kind = "bullets", items = {
                "|kbd[auto-trade on proximity]| \226\128\148 once the invited bot joins the party AND is within trade range (~11y), Pocket automatically sends an |ck[InitiateTrade()]| request. Fires once per invite. Persisted.",
                "|kbd[fully auto (sell all stacks)]| \226\128\148 on every trade open, places ALL stacks of the WTS item across trade slots 1-6 AND whispers the price multiplied by total item count. Persisted. Final accept still requires a click.",
            }},

            { kind = "h2",   text = "Offer rows" },
            { kind = "p",    text = "Sorted descending by price. |kbd[#1]| gets a 28px row with a gold rail accent + star icon. |kbd[#2]| is a slightly smaller semi-bold row. |kbd[#3+]| are 18px muted rows. The hierarchy lets you read the top bidder at a glance even on a 20-offer screen." },

            { kind = "h2",   text = "Banner states" },
            { kind = "p",    text = "A conditional strip under the header signals the active phase: |kbd[amber LISTENING]| (pulsing blip + countdown / offer count), |kbd[green INVITED]| (bidder + price), |kbd[green TRADE OPEN]| (bot name)." },

            { kind = "h2",   text = "Trade window (docked panel)" },
            { kind = "p",    text = "When |ck[TRADE_SHOW]| fires while Pocket is visible, the trade UI docks inside the frame with three buttons:" },
            { kind = "bullets", items = {
                "|kbd[whisper]| \226\128\148 whisper the total price (|ck[Xg Ys Zc]|) to the trade partner.",
                "|kbd[trade]| \226\128\148 disabled while inside an open trade (would just trigger 'you are already trading'). Active variant lives in the footer (see below).",
                "|kbd[accept]| \226\128\148 |ck[SecureActionButton]| that securely clicks |ck[TradeFrameAcceptButton]|. This is the only way to invoke the protected |ck[AcceptTrade()]| function from an addon in 3.3.5. Requires one user click.",
            }},
            { kind = "p",    text = "If Pocket is hidden when the trade opens, the same panel floats centered as a fallback." },

            { kind = "h2",   text = "Footer" },
            { kind = "bullets", items = {
                "|kbd[clear]| \226\128\148 kicks the invited bot (if any), wipes offers, resets the item slot, and disarms.",
                "|kbd[open trade]| \226\128\148 appears |em[only]| once the invited bot has actually joined the party AND no trade is open. Sends |ck[InitiateTrade()]| and sets the auto-flow flag so the item is placed + price whispered on |ck[TRADE_SHOW]|.",
                "|kbd[stop]| \226\128\148 disarms listening without wiping the offer list.",
                "Middle of the strip shows a live phase summary (e.g. |kbd[5/20 offers \194\183 auto-invite in 22s]|).",
            }},

            { kind = "h2",   text = "Trade auto-flow on TRADE_SHOW" },
            { kind = "p",    text = "Triggered when the trade was opened via the |kbd[trade]| panel button, the |kbd[open trade]| footer button, or auto-trade-on-proximity. The addon: (1) auto-places the item (one stack, or all stacks if fully-auto is ON), (2) whispers the total price (unit price \195\151 count), (3) arms the secure accept button. You only click |kbd[accept]| once the bot has placed its gold." },

            { kind = "h2",   text = "Empty state" },
            { kind = "p",    text = "When idle with no offers the list area shows a |kbd[NO OFFERS YET]| hint with a one-liner reminder of what to do. Disappears as soon as the first whisper lands." },

            { kind = "h2",   text = "Commands and shortcuts" },
            { kind = "table", rows = {
                { "/wp",                 "Toggle the HUD." },
                { "/wp show / hide",     "Explicit visibility." },
                { "/wp <text>",          "Toggle and pre-fill the input field." },
                { "Ctrl+Right-click",    "On any bag item while WP is open \226\128\148 captures it into the slot." },
                { "Ctrl+Middle-click",   "On the minimap button \226\128\148 toggle WardenPocket." },
            }},
        },
    },

    -- ---- REFERENCE ----------------------------------------------------
    {
        id = "settings", group = "REFERENCE", title = "Settings",
        eyebrow = "Chapter 10 \194\183 Reference",
        body = {
            { kind = "lede", text = "Global Warden behaviour. Three groups: general options, WardenSword HUD-specific panel, and maintenance tools." },
            { kind = "h2",   text = "General" },
            { kind = "bullets", items = {
                "Auto-Spec on Build \226\128\148 whisper planned spec when a bot joins.",
                "Party \226\134\146 Raid auto-conversion when a Build reaches five or more bots.",
                "Window size: Small (0.80) / Medium (1.00) / Large (1.20) / XL (1.40). Applies live.",
                "Session stats: Spawned / Spec'd / Pending / Tracked / Send queue / Whisper queue. Refreshes every 0.5s.",
            }},
            { kind = "h2",   text = "WardenSword panel" },
            { kind = "p",    text = "Dedicated panel with HUD checkboxes (auto-show, status strip, roles row, start locked, hide minimap in combat), density dropdown, transparency slider, and Reset HUD position." },
            { kind = "h2",   text = "Maintenance" },
            { kind = "bullets", items = {
                "|kbd[Reset minimap]| \226\128\148 snaps the minimap button back to its default 225-degree position.",
                "|kbd[Clear GUID tracking]| \226\128\148 wipes |ck[assignedSpecs]|. Re-Spec then falls back to FIFO.",
                "|kbd[Restore default presets]| \226\128\148 re-seeds any of the 11 built-in raid presets that have been deleted. Never overwrites a preset you've edited.",
            }},
        },
    },
    {
        id = "auto", group = "REFERENCE", title = "Auto-behaviors",
        eyebrow = "Chapter 11 \194\183 Reference",
        body = {
            { kind = "lede", text = "Several automated systems reduce manual bot management. Every one of them respects the |kbd[P]| player flag so humans are never modified." },
            { kind = "h2",   text = "Paladin Righteous Fury" },
            { kind = "p",    text = "Righteous Fury (spell 25780) is controlled via the bot's spell-exclude list. Prot paladins get |ck[ss -25780]| (include RF so they can tank); Ret and Holy get |ck[ss +25780]| (exclude RF so they don't pull aggro). Fires automatically after every Paladin spec whisper." },
            { kind = "h2",   text = "Buff limits" },
            { kind = "p",    text = "Each Paladin casts one blessing, each Shaman one totem set, each Hunter one aspect. Over-selection shows a warning chip in the Bot Comp coverage strip." },
            { kind = "h2",   text = "GUID tracking" },
            { kind = "p",    text = "Each bot's spec plus opt1 / opt2 are remembered by GUID. Re-Spec re-applies exactly after a server drop." },
            { kind = "h2",   text = "Whisper cadence" },
            { kind = "p",    text = "Warden whispers specs every 0.45s. Bot spawns stay paced at 0.90s. Both gaps protect against Blizzard's command throttle." },
            { kind = "h2",   text = "Bloodlust default" },
            { kind = "p",    text = "Whispered directly to each shaman via the spell-exclude list: |ck[ss -2825]| to let a Horde shaman cast Bloodlust, |ck[ss +2825]| to block it (same with |ck[32182]| for Alliance Heroism). Warden picks the faction automatically. The OFF default protects pulls that don't want lust." },
            { kind = "h2",   text = "Player guard" },
            { kind = "p",    text = "Every automated whisper / summon checks the per-name player flag and skips flagged characters. Prevents Warden from touching real raiders' specs when run alongside humans." },
            { kind = "h2",   text = "Empty slot guard" },
            { kind = "p",    text = "Build / Re-Spec iterate slots with explicit nil checks, so a single empty slot in the middle of the grid no longer halts the entire summon loop." },
        },
    },
    {
        id = "slash", group = "REFERENCE", title = "Slash commands",
        eyebrow = "Chapter 12 \194\183 Reference",
        body = {
            { kind = "lede", text = "Every Warden slash command in one place. Aliases are listed; pick whichever you find easier to type mid-fight." },
            { kind = "table", rows = {
                { "/warden",        "Toggle the main Warden window." },
                { "/wden",          "Short alias for |ck[/warden]|." },
                { "/ws",            "Toggle the WardenSword mid-fight HUD." },
                { "/wardensword",   "Long alias for |ck[/ws]|." },
                { "/wsh",           "Toggle the WardenShield discovery HUD." },
                { "/wardenshield",  "Long alias for |ck[/wsh]|." },
                { "/wp",            "Toggle the WardenPocket WTS aggregator." },
                { "/wardenpocket",  "Long alias for |ck[/wp]|." },
                { "/wardenlog",     "Log viewer + debug toggles. See the Debug chapter." },
            }},
        },
    },
    {
        id = "debug", group = "REFERENCE", title = "Debug & logging",
        eyebrow = "Chapter 13 \194\183 Reference \194\183 Advanced",
        body = {
            { kind = "lede", text = "Advanced troubleshooting tools. Recommended only when diagnosing issues or reporting bugs." },
            { kind = "h2",   text = "Two-tier model" },
            { kind = "p",    text = "Warden has two independent loggers. The |kbd[global INFO]| trace is a single on/off switch that drains verbose prints from the whole addon into SavedVariables. The |kbd[per-feature DEBUG]| trace lets you flip one subsystem at a time \226\128\148 each category echoes to the chat frame live AND persists to the same log. ERRORS are always captured regardless of either switch." },
            { kind = "h2",   text = "Typical workflow" },
            { kind = "steps", items = {
                "Pick the debug category closest to the misbehaviour.",
                "Turn it on with |ck[/wardenlog debug <cat> on]|.",
                "Reproduce the problem once.",
                "Read recent entries with |ck[/wardenlog tail 30]|.",
                "Disable with |ck[/wardenlog debug reset]| when done.",
            }},
            { kind = "h2",   text = "Log viewer commands" },
            { kind = "table", rows = {
                { "/wardenlog",         "Print the last 20 entries." },
                { "/wardenlog tail N",  "Print the last N entries without clearing them." },
                { "/wardenlog all",     "Print the entire log in chat." },
                { "/wardenlog clear",   "Wipe |ck[WardenLog]| entirely (INFO + DEBUG entries)." },
                { "/wardenlog status",  "Global on/off, entry count, debug categories active." },
                { "/wardenlog on",      "Enable the GLOBAL verbose logger." },
                { "/wardenlog off",     "Disable the global verbose logger. Errors are still captured." },
            }},
            { kind = "h2",   text = "Debug categories" },
            { kind = "table", rows = {
                { "/wardenlog debug",            "Show per-category ON/OFF state." },
                { "/wardenlog debug help",       "List every known category with usage examples." },
                { "/wardenlog debug <cat> on",   "Turn on trace for one category." },
                { "/wardenlog debug <cat> off",  "Turn off trace for one category." },
                { "/wardenlog debug all on",     "Firehose \226\128\148 every category at once. Expect heavy chat spam." },
                { "/wardenlog debug all off",    "Disable every category." },
                { "/wardenlog debug reset",      "Tidy way to leave the log clean for production." },
            }},
            { kind = "p",    text = "Categories: |ck[master]| (window toggle / tab switch), |ck[slash]| (slash entries), |ck[respec]| (per-row + bulk Re-Spec), |ck[whisper]| (queue push + drain), |ck[build]| (StartBuild + plan dump), |ck[roster]| (rebuild triggers), |ck[spec]| (Spec tab target changes), |ck[sword]| (WardenSword Show/Hide + auto-show), |ck[combat]| (PLAYER_REGEN transitions), |ck[minimap]| (click routing + combat-hide), |ck[persist]| (DB load/save), |ck[comp]| (Build/save/load), |ck[controls]| (every send() in Controls tab), |ck[settings]| (checkbox toggles)." },
            { kind = "h2",   text = "Chat echo format" },
            { kind = "p",    text = "When a debug category fires, you see |em[Warden/<cat>]| in light blue in the default chat frame, plus the same line persisted to |ck[WardenLog]| with a |em[DEBUG]| level tag." },
            { kind = "h2",   text = "Reading the log file" },
            { kind = "p",    text = "Toggles and entries live in |ck[WTF/Account/<acct>/SavedVariables/Warden.lua]|. Look for |ck[WardenDebug]| (toggle table), |ck[WardenLog]| (entries), and |ck[WardenLogEnabled]| (global switch)." },
        },
    },
}

-- =====================================================================
-- §3.4 renderers
-- Each takes (content, y, node) and returns the new y. Created Regions
-- must be appended to content._spawned so SetChapter can wipe them on the
-- next switch.
-- =====================================================================
local T = ns.Tokens

local function track(content, region)
    content._spawned = content._spawned or {}
    table.insert(content._spawned, region)
    return region
end

local function readerInnerW(content)
    local w = content:GetWidth()
    if not w or w <= 0 then return 500 end
    return w
end

local function renderLede(content, y, node)
    local w = readerInnerW(content) - READER_PAD_SIDE * 2 - 10
    local fs = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE + 10, y)
    fs:SetWidth(math.max(50, w))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
    fs:SetText(ns.UI.RichText.Format(node.text or ""))
    fs:SetTextColor(0.851, 0.804, 0.690, 1) -- parchment
    local h = math.max(14, fs:GetStringHeight())
    fs:SetHeight(h)

    local rule = track(content, content:CreateTexture(nil, "ARTWORK"))
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 0.9)
    rule:SetWidth(2)
    rule:SetPoint("TOPLEFT",    content, "TOPLEFT", READER_PAD_SIDE, y)
    rule:SetPoint("BOTTOMLEFT", content, "TOPLEFT", READER_PAD_SIDE, y - h)

    return y - h - 14
end

local function renderH2(content, y, node)
    y = y - 16
    local fs = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE + 12, y)
    fs:SetWidth(readerInnerW(content) - READER_PAD_SIDE * 2 - 12)
    fs:SetJustifyH("LEFT")
    fs:SetText(node.text or "")
    fs:SetTextColor(T.text_warm[1], T.text_warm[2], T.text_warm[3], 1)
    local h = fs:GetStringHeight()
    fs:SetHeight(h)

    local pip = track(content, content:CreateTexture(nil, "ARTWORK"))
    pip:SetTexture("Interface\\Buttons\\WHITE8x8")
    pip:SetVertexColor(T.gold[1], T.gold[2], T.gold[3], 1)
    pip:SetSize(4, 4)
    pip:SetPoint("LEFT", fs, "LEFT", -8, 0)

    return y - h - 6
end

local function renderP(content, y, node)
    local w = readerInnerW(content) - READER_PAD_SIDE * 2
    local fs = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
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

        local pad = track(content, CreateFrame("Frame", nil, content))
        pad:SetSize(20, 20)
        pad:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, rowTop - 1)
        pad:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        pad:SetBackdropColor(T.stone_tile[1], T.stone_tile[2], T.stone_tile[3], 1)
        pad:SetBackdropBorderColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)

        local n = pad:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        n:SetPoint("CENTER", pad, "CENTER", 0, 0)
        n:SetText(tostring(i))
        n:SetTextColor(T.gold[1], T.gold[2], T.gold[3], 1)

        local fs = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
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

        local fs = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", textX, rowTop)
        fs:SetWidth(math.max(50, textW))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
        fs:SetText(ns.UI.RichText.Format(txt or ""))
        local h = math.max(14, fs:GetStringHeight())
        fs:SetHeight(h)

        local dot = track(content, content:CreateTexture(nil, "ARTWORK"))
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
    local frame  = track(content, CreateFrame("Frame", nil, content))
    frame:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, y)
    frame:SetWidth(math.max(50, outerW))
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(T.stone_mid[1], T.stone_mid[2], T.stone_mid[3], 1)
    frame:SetBackdropBorderColor(T.stone_rim[1], T.stone_rim[2], T.stone_rim[3], 1)

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8x8")
    accent:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT",     frame, "TOPLEFT",      12, -8)
    fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  -8, 8)
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetWordWrap(true); fs:SetNonSpaceWrap(false)
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

        local L = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
        L:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE, rowTop)
        L:SetWidth(leftW)
        L:SetJustifyH("LEFT")
        L:SetWordWrap(true); L:SetNonSpaceWrap(false)
        L:SetText("|cffffd100" .. cmd .. "|r")

        local R = track(content, content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        R:SetPoint("TOPLEFT", content, "TOPLEFT", READER_PAD_SIDE + leftW + gutter, rowTop)
        R:SetWidth(rightW)
        R:SetJustifyH("LEFT")
        R:SetWordWrap(true); R:SetNonSpaceWrap(false)
        R:SetText(ns.UI.RichText.Format(desc))

        local h = math.max(L:GetStringHeight(), R:GetStringHeight()) + 6

        local rule = track(content, content:CreateTexture(nil, "ARTWORK"))
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

    local sb = _G["WardenHelpRailScrollScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT", 2, 0)
        sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 0)
        sb:SetWidth(6)
    end

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

    local sb = _G["WardenHelpReaderScrollScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT",    sf, "TOPRIGHT", 2, 0)
        sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 0)
        sb:SetWidth(SCROLLBAR_W)
    end

    local content = CreateFrame("Frame", nil, sf)
    -- Width follows the reader at build time; resized again if the parent
    -- pane is laid out after BuildInto.
    local rw = (parent:GetWidth() or 720) - RAIL_W - SCROLLBAR_PAD - SCROLLBAR_W
    content:SetSize(math.max(120, rw), 10)
    sf:SetScrollChild(content)

    -- If the pane's width changes after BuildInto (e.g., Window-size dropdown),
    -- reflow the content width on the next OnSizeChanged event.
    parent:HookScript("OnSizeChanged", function(_, w)
        if not w or w <= 0 then return end
        local nw = w - RAIL_W - SCROLLBAR_PAD - SCROLLBAR_W
        if nw > 0 then content:SetWidth(nw) end
    end)

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

    if _readerContent._spawned then
        for _, r in ipairs(_readerContent._spawned) do
            r:Hide()
            r:ClearAllPoints()
        end
    end
    _readerContent._spawned = {}

    local y = -READER_PAD_TOP

    local eye = _readerContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eye:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
    eye:SetText(ch.eyebrow or "")
    eye:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
    table.insert(_readerContent._spawned, eye)
    y = y - 14

    local h1 = _readerContent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    h1:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
    h1:SetText(ch.title)
    h1:SetTextColor(T.gold[1], T.gold[2], T.gold[3], 1)
    table.insert(_readerContent._spawned, h1)
    y = y - 30

    -- Masthead sub-line only on the intro chapter (per spec §4.3).
    if ch.id == "intro" then
        local sub = _readerContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
        sub:SetText("raid commander \194\183 WarStormBot UI \194\183 v" ..
            (GetAddOnMetadata("Warden", "Version") or "?"))
        sub:SetTextColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 1)
        table.insert(_readerContent._spawned, sub)
        y = y - 16
    end

    local rule = _readerContent:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(T.gold_rim[1], T.gold_rim[2], T.gold_rim[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
    rule:SetPoint("RIGHT",   _readerContent, "RIGHT",   -READER_PAD_SIDE, 0)
    table.insert(_readerContent._spawned, rule)
    y = y - 14

    for _, node in ipairs(ch.body or {}) do
        local fn = DISPATCH[node.kind]
        if fn then y = fn(_readerContent, y, node) end
    end

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

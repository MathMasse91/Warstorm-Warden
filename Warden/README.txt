================================================================
  WARDEN - Raid Commander for WoW 3.3.5a (WotLK) / WarStorm
================================================================

Version : 1.0.0
Target  : World of Warcraft 3.3.5a (WotLK private server)
Server  : WarStorm (mod-playerbots enabled)
Author  : UnrealTruth
Credits : Forked from WSSM (Patchs & Valleriaa); merges
          WarstormBotManager (Moroes) and both WBM Lite and
          OptimalRaidComposer (by Runshouse).

----------------------------------------------------------------
  WHAT IT IS
----------------------------------------------------------------

Warden is a single-window raid commander for servers that expose
mod-playerbots. It replaces the WSSM / WBM / OptimalRaidComposer
workflow with one tabbed UI, one SavedVariables table, and one
whisper-queue engine that throttles every outgoing command so you
never trip the server anti-spam threshold.

On top of the main window, Warden ships **WardenSword** - a small
draggable mid-fight HUD (/ws) that exposes the handful of actions
a raid lead hits on a pull without having to open the full window.

----------------------------------------------------------------
  FEATURES
----------------------------------------------------------------

Main window (/warden or /wden):

  Spec tab       - Shows the current target, last six targets,
                   and a spec grid per class. Clicking a tile
                   whispers the talent string and remembers the
                   bot by GUID so Re-Spec re-applies after a
                   reconnect. Prev-target + history use
                   SecureActionButton so they never trip taint.

  Controls tab   - Movement (Summon / Follow / Stay / Free /
                   Release / Drink), Strategy toggles (AoE /
                   Burn CD / Face-behind), Marks & formation
                   (Skull + attack, Moon for CC, disperse, 8
                   formations), 5x4 role matrix (Tank / Heal /
                   DPS / Melee / Ranged x Atk / Stay / Follow /
                   Flee), a Danger zone with Smart ReSpec,
                   Reset AI, Hard ReSpec, and Cleanup, and a
                   Summon-by-class panel at the bottom: 2x5
                   class-colored buttons that each spawn one
                   bot of that class with a single click.

  Bot Comp tab   - Raid composition editor. Pick a size (5 /
                   10 / 25 / 40), drag class chips onto slots,
                   assign spec + blessing + aura per slot. Save
                   to a local preset or export the whole thing
                   as a portable WRDN2 string to share. [P] flag
                   marks a slot as a real human - Build + Re-Spec
                   skip those slots.

  Roster tab     - Live raid roster with filter (All / Tanks /
                   Healers / DPS), name search, per-row [P]
                   toggle, and provides-chips that show which
                   assigned buffs each bot is covering. Re-Spec
                   All Tracked and Re-Spec Selected sit at the
                   bottom and both skip flagged players.

  Settings tab   - Global settings (auto-spec, party-to-raid
                   convert, window size dropdown), live session
                   stats, WardenSword HUD options (auto-show,
                   density, transparency slider, reset position,
                   open keybinds), Maintenance (reset minimap
                   button, clear GUID tracking, clear player
                   flags), and About.

  Help tab       - Full in-game reference card covering every
                   tab, slash command, and keybinding.

WardenSword HUD (/ws):

  - Movement 2x2:   Summon (red) / Follow / Stay / Flee
  - Strategy row:   AoE / Burn / Skull (mark + attack)
  - Role matrix:    TANK / HEAL / DPS x Atk / Stay
  - BLOODLUST full-width, colour reflects ON/OFF state
  - Status strip:   BOTS / AoE / BL / queue depth live
  - Draggable, lockable, transparent (15%-100%), density
    Tiny / Compact / Normal

Under the hood:

  - One whisper + send queue, rate-limited via DB.interval.
  - Player-flag guard (ns.Persistence.IsPlayerName) on every
    automated summon / whisper / Re-Spec so real raiders are
    never touched.
  - GUID identity map so a bot's spec is re-applied exactly
    after a reconnect.
  - SavedVariables migration from WSSM so existing comps come
    over on first login.
  - Single PLAYER_LOGOUT handler (no race), idempotent schema,
    auto-flag of the logged-in character.

----------------------------------------------------------------
  INSTALLATION
----------------------------------------------------------------

1. Close the game completely.

2. Locate your WoW 3.3.5a client install folder. On WarStorm
   that's typically:

     C:\Users\<you>\Desktop\WarStorm\
     or wherever you extracted the client.

3. Copy the entire "Warden" folder into:

     <WoW>\Interface\AddOns\Warden\

   After the copy the folder should look like:

     Interface\AddOns\Warden\
       Warden.toc
       Bindings.xml
       Core.lua
       Data.lua
       Engine.lua
       Log.lua
       Persistence.lua
       WardenSword.lua
       WardenSword_Actions.lua
       UI_Master.lua
       UI_Tab*.lua (Spec / Controls / Comp / Roster / Settings / Help)
       UI_Minimap.lua
       ImageD\assets\warden_minimap_32.tga

4. Launch the game and log in.

5. At the character select screen, make sure "Load out-of-date
   AddOns" is enabled (top-right AddOns button).

6. In-game, type  /warden  or  /wden  to open the main window,
   or  /ws  to open the HUD.

----------------------------------------------------------------
  FIRST LAUNCH CHECKLIST
----------------------------------------------------------------

- Minimap button appears at 225-degree angle (bottom-left of
  minimap). Drag it anywhere around the minimap ring.
- Your own character is auto-flagged as a human player so none
  of the automation touches you.
- If you had a WarstormSpecManager (WSSM) profile, your saved
  comps auto-migrate into the Bot Comp tab on first login.

----------------------------------------------------------------
  SLASH COMMANDS
----------------------------------------------------------------

Main window:

  /warden              Toggle the main window.
  /wden                Same (alias).

Logging:

  /wardenlog on        Enable INFO/WARN logging to
                       SavedVariables (errors always captured).
  /wardenlog off       Disable INFO/WARN logging.
  /wardenlog status    Show ON/OFF state and entry count.
  /wardenlog tail N    Print the last N entries in chat.
  /wardenlog all       Print the whole log.
  /wardenlog clear     Wipe the log.

WardenSword HUD:

  /ws                  Toggle the HUD.
  /ws show | hide      Explicit show / hide.
  /ws lock | unlock    Lock or unlock position.
  /ws reset            Reset HUD position.
  /ws config           Jump to Settings > WardenSword.
  /ws help             Print the full command list in chat.

  Direct actions:
    /ws summon   /ws follow  /ws stay    /ws flee
    /ws aoe      /ws burn    /ws skull   /ws bl
    /ws @tank atk | stay
    /ws @heal atk | stay
    /ws @dps  atk | stay

----------------------------------------------------------------
  KEYBINDS
----------------------------------------------------------------

Open ESC > Key Bindings > "Warden" category. The following
actions are bindable:

  Warden:
    Toggle Warden window, tab shortcuts (Spec / Controls /
    Comp / Roster), Summon, Follow, Stay, Tank Attack, Flee,
    RTSC On / Save / Go.

  WardenSword - Actions:
    Toggle HUD, Lock / Unlock, Summon, Follow, Stay, Flee,
    AoE toggle, Burn CDs toggle, Skull mark + attack, BL.

  WardenSword - Role commands:
    Tanks Attack / Stay, Healers Attack / Stay, DPS Attack / Stay.

All bindings route through the same throttled Engine queue the
HUD uses, so hammering a hotkey won't trigger a server-side
mute.

----------------------------------------------------------------
  MINIMAP BUTTON
----------------------------------------------------------------

  Left-click      Toggle main window.
  Shift-left      Open Settings tab.
  Middle-click    Toggle WardenSword HUD.
  Right-click     Open Help tab.
  Drag            Orbit around the minimap ring. Position is
                  saved per-character.

----------------------------------------------------------------
  TROUBLESHOOTING
----------------------------------------------------------------

- "Load out-of-date AddOns" is OFF: enable it at character
  select. Warden targets Interface version 30300 and many
  private-server launchers disable old addons by default.

- No minimap button: type  /warden  to open the main window,
  go to Settings > Maintenance > "Reset minimap button".

- Lost all saved comps after /reload: should not happen on 1.0
  (single PLAYER_LOGOUT handler). If it does, file an issue
  with `/wardenlog tail 50` output attached.

- Bots never get spec'd after a party-to-raid conversion: the
  convert call is gated on InCombatLockdown so if combat was
  active at Build time the raid stayed as a party. Leave
  combat, press Build again.

- Server says "you are being ignored" during a Re-Spec: the
  whisper interval is 0.45s by default. On extremely busy
  realms raise DB.interval via:
    /run WardenDB.interval = 0.60; ReloadUI()

----------------------------------------------------------------
  DATA / SAVEDVARIABLES
----------------------------------------------------------------

Warden persists to WardenDB (one table for all of Warden's
state). The logging subsystem uses WardenLog / WardenLogEnabled.

Under no circumstances does Warden touch, read, or forward any
other addon's SavedVariables or your account data.

----------------------------------------------------------------
  LICENSE / CREDITS
----------------------------------------------------------------

Forked from WSSM (Patchs & Valleriaa). Absorbs parts of
WarstormBotManager (Moroes) and both WBM Lite and
OptimalRaidComposer (by Runshouse). Maintained for WarStorm
by UnrealTruth.

No warranty. Private-server use only. WoW is owned by Blizzard
Entertainment; this addon is not affiliated with Blizzard.

--
Signed: UnrealTruth

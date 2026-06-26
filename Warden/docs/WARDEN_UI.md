# Warden — Main Window & WardenSword HUD
> UI reference for redesign. All code refs point to files in the addon root.

---

## 1. Main Window (`UI_Master.lua`)

**Frame name:** `WardenMainFrame`  
**Size:** 760 × 600  
**Strata:** HIGH  
**Slash:** `/warden` (toggle)  
**Keybinding:** `WARDEN_TOGGLE` → `BINDING_NAME_WARDEN_TOGGLE` (`UI_Master.lua:646`)

### 1.1 Chrome

| Element | Description | Code ref |
|---------|-------------|----------|
| Title | "WARDEN" gold uppercase (`GameFontNormalLarge`) | `UI_Master.lua:165` |
| Subtitle | "raid commander · vX.Y.Z" muted gold-dim | `UI_Master.lua:174` |
| Close X | `UIPanelCloseButton`, top-right, 8px from corner | `UI_Master.lua:182` |
| ESC close | `UISpecialFrames` registration | `UI_Master.lua:192` |
| Draggable | `RegisterForDrag("LeftButton")`, `ClampedToScreen` | `UI_Master.lua:127` |
| Background | `UI-DialogBox-Background` + solid opaque fill 0.055/0.04/0.02 | `UI_Master.lua:155` |
| Scale | Saved as `db.masterScale`, 4 presets (0.80 / 1.00 / 1.20 / 1.40) | `UI_Master.lua:379` |

### 1.2 Footer Strip (persistent)

Lives at bottom of the main frame, always visible regardless of active tab.

| Element | Description | Code ref |
|---------|-------------|----------|
| Green dot | 8×8 live indicator | `UI_Master.lua:243` |
| Target label | Live `UnitName("target")`, class-colored | `UI_Master.lua:248` |
| Stats label | "q N · tracked N" (queue depth + bots tracked by Engine) | `UI_Master.lua:251` |
| BL pill | 54×16 stone button, amber "BL OFF" / green "BL ON" | `UI_Master.lua:263` |
| Hint label | "Esc close  -  /warden" | `UI_Master.lua:256` |
| Refresh events | `PLAYER_TARGET_CHANGED`, `RAID_ROSTER_UPDATE`, `PARTY_MEMBERS_CHANGED`, `PLAYER_ENTERING_WORLD` + 0.5 s ticker | `UI_Master.lua:330` |

**BL pill behavior:** clicking whispers `ss +/-2825` (BL) or `ss +/-32182` (Heroism) to every shaman in group via `ns.WhisperClass`. `UI_Master.lua:286`

### 1.3 Tab Bar

6 tabs, Blizzard `CharacterFrameTabButtonTemplate`. First tab anchored at `BOTTOMLEFT +30, +2` so it slightly overlaps the frame bottom edge (mimics CharacterFrame style). `UI_Master.lua:354`

| # | Key | Label |
|---|-----|-------|
| 1 | `Spec` | Spec |
| 2 | `Controls` | Controls |
| 3 | `Comp` | Bot Comp |
| 4 | `Roster` | Roster |
| 5 | `Settings` | Settings |
| 6 | `Help` | Help |

Active tab persisted as `db.activeTab`. Lazy-built on first click. `UI_Master.lua:55`

### 1.4 Hide-in-combat workaround

When `frame:Hide()` is refused in combat (known WarStorm 3.3.5a behaviour), the frame is displaced off-screen (TOPLEFT +5000, -5000), alpha set to 0, mouse disabled. A `PLAYER_REGEN_ENABLED` hook collapses it properly when combat ends. `UI_Master.lua:460`

---

## 2. Tab — Spec (`UI_TabSpec.lua`)

### 2.1 Target Card (top section)
| Element | Description |
|---------|-------------|
| Portrait | 60×60 `SetPortraitTexture` for current target |
| Level badge | 22px gold-rim overlay on portrait corner |
| Name | Class-colored via `ns.ColorClass` |
| Subtitle | "- Class - Faction" muted mono |
| History nav | `< prev` / `next >` buttons cycling previously-targeted bots |
| Action buttons | `autogear → PARTY`, `buffs → RAID` |

### 2.2 Specs Grid
- 4-column tile grid, all specs available for the targeted class
- Each tile: class-colored spec name + `"pve - hint"` subtitle + 22×22 icon slot (top-right)
- Recommended tile: gold inner border + `"* talent preview"` text
- Clicking a tile whispers `"talents spec <specKey>"` to target
- `SPEC_HINT` table maps every class/spec to a category string (`"pve - burst"`, `"pve - tank"`, etc.) — `UI_TabSpec.lua:22`

---

## 3. Tab — Controls (`UI_TabControls.lua`)

### 3.1 Movement (3×2 grid)
| Button | Style | Action |
|--------|-------|--------|
| Summon | Red (primary) | Summon all bots |
| Follow | Stone | All follow |
| Stay | Stone | All stay |
| Free | Stone | Free movement |
| Release | Stone | Release bots |
| Drink | Stone | All drink |

### 3.2 Strategy Row
3 inline groups:

| Group | Buttons | Behavior |
|-------|---------|----------|
| AoE | Toggle pair ON/OFF | Broadcasts AoE flag |
| Burn CDs | Toggle pair ON/OFF | Broadcasts burn-cooldowns flag |
| Face | Single | Bot turns to face target |

### 3.3 Marks & Formation
Single panel, single row:

`[Skull]  [Moon]  [Disperse: 5y ▼]  [Formation ▼]  [Set]  [Check]`

- Disperse distance: presets `{ 5, 7, 10, 15, 20 }` yards — `UI_TabControls.lua:51`
- Formation list: Shield / Chaos / Circle / Line / Melee / Near / Queue / Arrow — `UI_TabControls.lua:31`

### 3.4 Role Commands Matrix (5 × 4)
Rows: `tank | heal | dps | melee | ranged`  
Cols: `Attack | Stay | Follow | Flee`  
Each cell: small stone button. Shift-click flashes gold rim. — `UI_TabControls.lua:26`

### 3.5 Danger Zone (red header)
| Button | Style | Confirmation |
|--------|-------|-------------|
| Smart ReSpec | Stone | No |
| Reset AI | Stone | No |
| Hard ReSpec | Warn | Yes (dialog) |
| Cleanup | Warn | Yes (dialog) |

### 3.6 Summon by Class (bottom panel)
2×5 grid of class-colored buttons. Each fires `.warstormbot bot addclass <CLASS>` via `db.addPattern`. — `UI_TabControls.lua:14`

Classes: Warrior / Paladin / Hunter / Rogue / Priest / Shaman / Mage / Warlock / Druid / Death Knight

---

## 4. Tab — Bot Comp (`UI_TabComp.lua`)

### 4.1 Header Bar
`[comp name input]  [Presets ▼]  [Size ▼]  ·····  [Grid view]  [Table view]`

- Comp name: free text, Enter to save
- Presets dropdown: lists all `db.comps` keys
- Size selector: 5 / 10 / 25 / 40 (controls grid column count)

### 4.2 Raid Grid (left panel)
- Groups × 5 slots (5-man = 1×5, 10 = 2×5, 25 = 5×5, 40 = 8×5)
- Each slot: class chip (icon + class token) drag-drop target
- Group headers: auto-labeled by role cluster (G1 tanks, G2 healers, etc.)

### 4.3 Tray (below grid)
`DRAG →  [chip][chip]...[chip]   shift - N`

Drag chips from class pool into grid slots. Shift-click to pick quantity N.

### 4.4 Slot Detail Panel (right, gold border)
Appears when a slot is selected:

| Section | Content |
|---------|---------|
| Slot header | "Slot - G1 pos 1" |
| Class + spec tags | Dropdown selectors |
| Blessings | Auto-assigned paladin blessings |
| Aura / resist | Suggested aura |
| Actions | `[move]  [dup]  [remove]` |

### 4.5 Coverage Panel
Visual OK/missing indicators per buff type (Kings, Might, etc.) derived from the current comp's class list.

### 4.6 Summary Panel
```
filled 24 / 25
[Save]  [Load]  [Clear]  [Cleanup]
```

### 4.7 Bottom Strip
`[Re-Spec]  [Stop]  [Buffs]  [BL]  ☐ Auto-spec`

- Re-Spec: triggers `Engine.Build()` sequence
- Auto-spec checkbox: mirrors `db.autoSpec` — `UI_TabComp.lua` + `Persistence.lua:37`

### 4.8 Saved Comp Schema
```lua
db.comps[name] = {
    rows = {
        { classToken, spec, count },   -- e.g. { "WARRIOR", "prot pve", 2 }
        ...
    },
    size = 5 | 10 | 25 | 40,
}
```
Stored in `WardenDB.comps`. — `Persistence.lua:32`

---

## 5. Tab — Roster (`UI_TabRoster.lua`)

### 5.1 Filter Row
`[Filter: All ▼]  [search box]  [Refresh]`

- Role filter: All / Tank / Healer / DPS
- Search: live-filters by name (case-insensitive)

### 5.2 Bot List (3 sections)

Sections: **Tanks**, **Healers**, **DPS** — each with a gold uppercase label + count pill.

Per-row layout:
```
[☐]  [avatar 20×20]  [class-colored name]        [· · ·]  [R]
                       [Class - spec pve mono]    [spec tag]
```

| Element | Description |
|---------|-------------|
| Checkbox | Multi-select for batch Re-Spec |
| Avatar | Class icon |
| Name line 1 | Class-colored character name |
| Name line 2 | "Class - spec pve" muted mono |
| Spec tag | Current assigned spec button |
| 3 dots | Presence indicators (stone = present, red = missing) |
| R button | Individual Re-Spec |

Row height: 24px, spacing: 2px — `UI_TabRoster.lua:28`

### 5.3 Bottom Bar
`[R Re-Spec All Tracked]  [R Re-Spec Selected]  N selected`

Role inference — `UI_TabRoster.lua:39`:
- Tanks: Warrior/Paladin/Druid prot, DK blood specs
- Healers: Priest holy/disc, Paladin holy, Shaman/Druid resto
- Melee DPS / Ranged DPS: everything else

---

## 6. Tab — Settings (`UI_TabSettings.lua`)

Full scrollable panel. Four sub-panels:

### Panel 1 — Global settings
| Setting | Type | DB key |
|---------|------|--------|
| Auto-spec newly joined bots | Checkbox | `db.autoSpec` |
| Auto-match group type to comp size | Checkbox | `db.autoRaidDuringBuild` |
| Window size | Dropdown (Small/Medium/Large/XL) | `db.masterScale` → 0.80/1.00/1.20/1.40 |

### Panel 2 — WardenSword settings
(See §7.3 below — density, alpha, show status, show roles, start locked, hide minimap in combat)

### Panel 3 — Session / Maintenance
- Restore default presets button → `ns.Persistence.RestoreDefaultPresets()` (`Persistence.lua:142`)
- Clear all player flags

### Panel 4 — About
Version info, credits.

---

## 7. WardenSword HUD (`WardenSword.lua`)

Small draggable mid-fight command panel. Always on top (HIGH strata, level 100).

**Frame name:** `WardenSwordFrame`  
**Slash:** `/ws`  
**Keybinding:** `WARDENSWORD_TOGGLE`

### 7.1 Header
`WARDENSWORD  /ws  [o lock]  [x close]`

| Element | Detail |
|---------|--------|
| Title | Gold uppercase |
| Hint | "/ws" muted |
| Lock glyph | `o` (unlocked, muted) / `*` (locked, gold) — `WardenSword.lua:118` |
| Close | Red `x` glyph |
| Rule | 1px stone-rim divider under header |

### 7.2 Status Strip (optional)
`BOTS N  AoE:on/off  BL:on/off  QN`

- Updated every 0.5 s by OnUpdate ticker — `WardenSword.lua:504`
- Can be hidden via `db.sword.showStatus` — `WardenSword.lua:305`

### 7.3 Density Presets

| Key | Width | Button height |
|-----|-------|--------------|
| `tiny` | 210 | 18 |
| `compact` | 240 | 22 |
| `normal` | 270 | 26 |

`db.sword.density` — `WardenSword.lua:15`

### 7.4 Movement Grid (2×2)

| | Col 1 | Col 2 |
|-|-------|-------|
| Row 1 | **Summon** (red) | Follow |
| Row 2 | Stay | **Flee** (warn) |

Each button pulses gold rim for 120 ms on click. — `WardenSword.lua:44`

### 7.5 Strategy Row (3 columns)
`[AoE]  [Burn]  [Skull]`

- AoE / Burn: toggles — label turns gold when ON, dim when OFF
- Skull: marks target Skull + whispers attack command

### 7.6 Role Matrix (3 rows × 3 columns, optional)
```
TANK  [Atk]  [Follow]  [Stay]
HEAL  [Atk]  [Follow]  [Stay]
DPS   [Atk]  [Follow]  [Stay]
```
Hidden via `db.sword.showRoles`. — `WardenSword.lua:296`

### 7.7 Bloodlust Button (full-width)
- Stone/dim when OFF: label `BLOODLUST`
- Red fill / warm-white text when ON: label `BLOODLUST · ON`
- Whispers `ss -2825` (enable) or `ss +2825` (disable) to all shamans
- `ns.WardenSword.RefreshBLButton()` — `WardenSword.lua:258`

### 7.8 Persisted State (`db.sword`)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `pos` | table | nil | `{ point, x, y }` |
| `locked` | bool | false | Prevents drag |
| `hidden` | bool | false | Visibility on login |
| `autoShowCombat` | bool | true | Auto-shows on `PLAYER_REGEN_DISABLED` |
| `showStatus` | bool | true | Show/hide status strip |
| `showRoles` | bool | true | Show/hide role matrix |
| `startLocked` | bool | false | Lock on each login |
| `density` | string | "compact" | tiny / compact / normal |
| `hideMinimapCombat` | bool | false | Hide minimap icon in combat |
| `alpha` | number | 1.00 | Frame opacity (min 0.15) |

`Persistence.lua:51`

### 7.9 Slash Commands
```
/ws               toggle
/ws show|hide     explicit visibility
/ws lock|unlock   position lock
/ws reset         reset position
/ws config        open Warden Settings tab
/ws summon        summon all bots
/ws follow|stay|flee  group movement
/ws aoe|burn      toggle strategy flags
/ws skull         mark skull + attack
/ws bl            bloodlust / heroism
/ws @tank atk     role-scoped order
```

### 7.10 Keybindings
All bindings defined in `WardenSword.lua:646`:
- Toggle, Lock, Summon, Follow, Stay, Flee, AoE, Burn, Skull, BL
- Per-role: Tank/Heal/DPS × Attack/Stay

---

## 8. Minimap Button (`UI_Minimap.lua`)

- Round icon, draggable along minimap ring
- Left-click: toggle main window
- Right-click: show Help tab directly
- Angle persisted as `db.minimapAngle` (default 225°)
- Can hide in combat when `db.sword.hideMinimapCombat` is true

---

## 9. Color & Style Tokens (`Core.lua` — `ns.Tokens`)

| Token | RGBA | Usage |
|-------|------|-------|
| `stone_dark` | 0.07, 0.05, 0.03 | Frame backgrounds |
| `stone_mid` | ~0.13, 0.10, 0.06 | Panel fills |
| `stone_tile` | ~0.18, 0.14, 0.09 | Button bg |
| `stone_rim` | 0.23, 0.18, 0.13 | Button borders |
| `gold_rim` | 0.66, 0.54, 0.30 | Active/selected borders |
| `gold_text` | 1.00, 0.82, 0.00 | Titles, highlighted labels |
| `gold_dim` | 0.72, 0.58, 0.21 | Muted gold |
| `red_btn` | 0.48, 0.10, 0.07 | Danger / Summon buttons |

Button helpers: `ns.UI.Button.stone()`, `.gold()`, `.red()`, `.warn()`

---

## 10. Saved Variables

```lua
WardenDB = {
    version          = 3,
    activeTab        = 1,
    masterScale      = 1.0,
    minimapAngle     = 225,
    autoSpec         = true,
    autoRaidDuringBuild = true,
    bloodlust        = false,
    aoe              = false,
    burn             = false,
    disperseDist     = 5,
    lastComp         = "",
    comps            = { ... },
    playerFlags      = { [name] = true },   -- human player whitelist
    sword            = { ... },             -- WardenSword persisted state
    shield           = { ... },             -- WardenShield persisted state
}
```
`Persistence.lua:26`

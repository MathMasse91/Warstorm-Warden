# WardenShield — Feature List + UI Design Brief

**Status**: POC functional, end-to-end verified in-game (2026-04-28).
**Module**: `Shield.lua` (~870 lines, ~45 KB), persisted via `db.shield` in `WardenDB`.
**Slash**: `/wsh` (alias `/wardenshield`).
**Sibling module**: `WardenSword.lua` (mid-fight HUD) — same visual token palette, same compact density.

This document captures everything WardenShield does today plus the visual contract the redesigner must preserve (or knowingly diverge from). It is the single source of truth for handing off to a UI-focused workstream.

---

## 1. Purpose

WardenShield is a floating HUD that drives mod-playerbots **discovery commands** (`los`, `spells`) end-to-end without leaving the game UI. The flow:

1. The user selects a bot in-game.
2. WardenShield whispers `los` or `spells` to that bot.
3. The bot whispers back a multi-line list (objects nearby / spells known).
4. WardenShield captures those whispers, renders each line as a clickable row.
5. Clicking a row fires the appropriate follow-up command — `u [object]`, `cast <spell>`, `cast <spell> on <player>`, `ss +<id>` (ban), or `ss -<id>` (unban) — depending on the active **action mode**.

It is the discovery counterpart to WardenSword (which handles roster-level commanding). The two HUDs read as siblings.

---

## 2. Feature inventory

### 2.1 Capture flow

- **`[los]` button**: snapshots `UnitName("target")` if no target locked; whispers `los` to that bot; opens a capture window for `db.shield.captureSec` seconds (default 5, clamped 1–60).
- **`[spells]` button**: same, but whispers `spells`.
- **Sticky target lock**: once a target is locked, subsequent `[los]/[spells]` clicks reuse that lock and do not re-snapshot the live UnitName. The user must click `[pick]` to refresh the lock.
- **`[pick]` button**: explicitly re-snapshot `UnitName("target")` and update the lock label.
- **Player-flag protection**: the target must not be in `WardenDB.playerFlags`. Re-checked at click time so flagging mid-capture aborts subsequent sends.
- **Idle vs listening**: outside the capture window, incoming whispers are dropped silently. Inside, they're appended to `state.lines` (cap 200, FIFO).
- **`[clear]` button**: wipes `state.lines` and resets `state.captureUntil = 0`. Target lock is preserved.

### 2.2 Action modes

Four modes, mutually exclusive, displayed as a horizontal switcher row. The active mode is painted with `gold_rim`; inactive with `stone_rim`.

| Mode  | Label   | Action on row click                                       |
|-------|---------|-----------------------------------------------------------|
| cast  | `cast`  | `cast <spell>` (spells line) or `u [<object>]` (los line) |
| caston| `on Y`  | `cast <spell> on <Y>` where `<Y>` is the captured target  |
| ban   | `ban`   | `ss +<spellID>` + appends `{id, name}` to local exclusions |
| unban | `unban` | `ss -<spellID>` + removes `{id, name}` from local exclusions |

Default mode on session start: `cast`.

### 2.3 Cast-on target capture

- While `state.actionMode == "caston"`, the addon listens to `PLAYER_TARGET_CHANGED`. On every fire, it captures `UnitName("target")` into `state.castOnTarget` (no validation — could be self, party, raid, or arbitrary friendly).
- The mode row shows `on <Name>` (gold) once a target is captured, or `click a frame` (dim gold) before the first capture.
- Switching mode away from `caston` clears `state.castOnTarget` so the next entry forces a fresh capture.
- This is **not persisted** — cast-on target lives only for the current session.

### 2.4 Exclusions panel (ban/unban management)

- `WardenDB.shield.exclusions` is an array of `{ id = <spellID>, name = <spellName> }`. Survives `/reload` and logout.
- **Ban click**: appends an entry (idempotent — same ID is not duplicated). Whisper sent: `ss +<id>`.
- **Unban click**: removes the entry. Whisper sent: `ss -<id>`.
- **`[exclusions: N]` toggle button** in the footer:
  - Off (stone rim): scroll list shows captured whispers.
  - On (gold rim): scroll list shows persisted exclusions. Each row reads `[banned] <name>  (id <ID>)` in red. Click any row to unban that entry.
- **`[reset]` button**: whispers `ss reset` to the locked target and wipes `WardenDB.shield.exclusions` locally. Requires a locked target.

### 2.5 List filters

- **Separator filter** (always on): lines whose payload starts with `===` or `---` are hidden. These are bot section headers (`=== Spells ===`, `--- Game objects ---`, etc.) — noise for the user.
- **Empty payload filter** (always on): lines with empty payload are hidden.
- **`[hide gray]` toggle** (footer, off by default): hides spells whose rank suffix color is `cff808080` (gray = bot can't currently use the spell, level/talent gated).

### 2.6 Persistence

`WardenDB.shield` schema (initialized in `Persistence.lua`):

```lua
{
  pos        = { point = "CENTER", x = 0, y = 0 },  -- frame anchor
  locked     = false,                                -- drag locked
  hidden     = false,                                -- last visibility
  captureSec = 5,                                    -- capture window seconds
  exclusions = { { id = 25898, name = "Greater Blessing of Kings" }, ... },
}
```

`db.shield.lastCaptures` was used for whisper-format diagnostic capture during development; that path has been removed but old data may still exist in users' SavedVariables. Safe to ignore.

### 2.7 Slash command surface

- `/wsh` (no arg) → `Toggle()`
- `/wsh show` / `/wsh hide` / `/wsh toggle`
- `/wsh lock` / `/wsh unlock`
- `/wsh reset` → reset frame anchor to CENTER 0,0
- `/wsh clear` → wipe captured list (same as `[clear]` button)
- `/wsh help` → print command list
- `/wardenshield <args>` → identical alias

### 2.8 Keybinding (Bindings.xml)

- `WARDENSHIELD_TOGGLE` (header `WARDENSHIELD`) → `WARDENSHIELD_Toggle()` global → `ns.Shield.Toggle()`.

User can bind it via the in-game Key Bindings UI under category "WardenShield".

### 2.9 Debug logging

All informational events route through `ns.DebugF("shield", fmt, ...)`. Visible only when:

1. `WardenDebug.shield = true` (per-cat opt-in)
2. OR `WardenDebug.all = true` (global opt-in)

Events logged: capture state changes, whisper accepts/drops with reason, click index/mode/payload/target, action mode switches, cast-on target captures, ban/unban operations.

### 2.10 Bot whisper format support (parsed by helpers)

Five regex helpers extract the structured pieces of mod-playerbots whispers:

| Helper             | Extracts                | Pattern                     |
|--------------------|-------------------------|------------------------------|
| `extractPayload`   | bracketed text or trim  | `%[([^%]]+)%]`               |
| `extractSpellId`   | numeric spell ID        | `|Hspell:(%d+)|h`            |
| `extractObjectId`  | numeric object entry ID | `|Hfound:%d+:(%d+):|h`       |
| `extractRank`      | trailing color hex      | `|c(%x%x%x%x%x%x%x%x)%a+|r%s*$` |
| `isSeparator`      | `^===` or `^---`        | (boolean)                   |

Observed bot whisper formats (from in-game capture):

```
|cffffffff|Hspell:25898|h[Greater Blessing of Kings]|h|r -  |cff808080gray|r
|cffffffff|Hitem:30816:0:0:0:0:0:0:0|h[Spice Bread]|h|r: <reagents>... -  |cffffff00yellow|r
|cFFFFFF00|Hfound:17370386994093359803:192602:|h[Brazier]|h|r
=== Spells ===
--- Game objects ---
```

Rank colors observed:
- `cff808080` (gray) = bot cannot currently cast (level/talent/spec gated)
- `cffffff00` (yellow) = bot can cast right now
- Other colors expected (orange/green/red) but not yet verified in-game.

---

## 3. UI inventory (current visual contract)

### 3.1 Frame chrome

- **Total size**: 260w × ~370h pixels.
- **Strata**: HIGH, frame level 100.
- **Backdrop**:
  - bg: `Interface\\DialogFrame\\UI-DialogBox-Background` (dark stone, tiled 16px)
  - border: 1px white-tile, vertex-colored to gold-rim `(0.72, 0.58, 0.21)`.
  - bg overlay color: `(0.07, 0.05, 0.03, 1.00)` (very dark stone).
- **Drag**: `LeftButton`, blocked when `db.shield.locked == true`.
- **Position**: persisted on drag stop.
- **Heartbeat OnUpdate** (0.5s): refreshes the live target label so it doesn't lag the user's actual target change.

### 3.2 Layout (top to bottom)

```
+----------------------------------------------+ ← frame edge gold-rim 1px
| HEADER ......................................| 22h
| ---------------------------------------------| 1px stone-rim rule
| TARGET row ...................................| 22h
| ACTION row ([los] [spells]   ... [clear]) ...| 22h
| MODE row ([cast][on Y][ban][unban] on <Y>) ..| 22h
| (separator rule 1px stone-rim) ..............| (inside STATUS row)
| STATUS strip (idle · N lines)................| 16h
| ......                                        |
| SCROLL LIST (200h, thin scrollbar 8px right) | 200h
|   > <captured raw>                            |
|   > <captured raw>                            |
|   ...                                         |
| FOOTER ([hide gray] [exclusions: N] [reset]).| 18h
+----------------------------------------------+
```

Vertical spacing: `PAD=8` between top edge and first row, `GAP=6` between rows, `PAD=8` between footer and bottom edge.

### 3.3 Header (22h)

- Left:
  - `WARDENSHIELD` — `GameFontNormal`, color `(1.00, 0.82, 0.00)` (gold).
  - `/wsh` — `GameFontDisableSmall`, color `(0.55, 0.50, 0.42)` (gold-dim), inline 6px right of title.
- Right (16x16 buttons, no chrome, just glyphs):
  - **Lock toggle** (`*` when locked, `o` when unlocked). Glyph color tracks state: gold for locked, gold-dim for unlocked.
  - **Close** (`x`, red `(0.85, 0.18, 0.12)`).
- Bottom rule: 1px white-tile, stone-rim color, full-width.

### 3.4 TARGET row (22h)

- Left fontstring: `GameFontHighlightSmall`, content depends on state:
  - `LOCKED: <name>` (class-colored) when `state.target` is set.
  - `LIVE: <name>` (class-colored) when no lock but target exists and is a player.
  - `|cff808080TARGET: no target|r` (gray) otherwise.
- Right: `[pick]` button — stone style, 48w × 18h.

### 3.5 ACTION row (22h)

- Left, in order: `[los]` (76w), `[spells]` (76w). 6px gap between them.
- Right: `[clear]` (56w).
- All stone-style, 22h.
- `[los]` and `[spells]` rims pulse to gold-rim while the capture window is active and the mode matches (so the user can see at a glance which discovery is being captured right now).

### 3.6 MODE row (22h)  — **NEW**

- Left, in order: `[cast]` `[on Y]` `[ban]` `[unban]` — 50w each, 4px gap.
- Right of buttons: `castOnLbl` (`GameFontDisableSmall`):
  - In `caston` mode + target captured: `on <Name>`, gold color.
  - In `caston` mode + no target yet: `click a frame`, gold-dim color.
  - In any other mode: hidden.
- Active mode button: rim painted with `gold_rim`. Inactive: `stone_rim`.

### 3.7 STATUS strip (16h)

- 1px white-tile rule pinned to the bottom of the strip, `PAD` inset on both sides, stone-rim color.
- Single fontstring left-aligned, `GameFontDisableSmall`:
  - `idle · N lines` (gold-dim) when not capturing.
  - `listening Ns · N lines` (gold) during capture, with countdown updating every tick.
- Note: the `·` is U+00B7 middle dot (`\194\183` in UTF-8 byte sequence).

### 3.8 Scroll list (200h)

- ScrollFrame using `UIPanelScrollFrameTemplate`.
- Scrollbar:
  - Up/down arrows hidden.
  - Width 8px, anchored 2px right of the scrollframe.
- Each row (`ROW_H = 18`):
  - Backdrop: bg `(0.10, 0.08, 0.05)`, edge `stone_rim` 1px.
  - Highlight: white-tile ADD-blend, alpha 0.10.
  - Single fontstring `GameFontHighlightSmall`, 6px insets left/right, justify left, no word-wrap.
  - **Captured-line row**: text `> <line.raw>`, color `(0.85, 0.80, 0.69)` (warm-stone).
  - **Exclusion row** (when `state.viewExclusions == true`): text `[banned] <name>  (id <ID>)`, color `(0.85, 0.18, 0.12)` (red).
  - Click animation: rim flashes `gold_rim` for 120ms then returns to `stone_rim`.

### 3.9 FOOTER row (18h) — **NEW**

- Left: `[hide gray]` (60w). Toggle. Active rim = gold, inactive = stone.
- Middle: `[exclusions: N]` (96w). Toggle. Active rim = gold (panel showing exclusions), inactive = stone (panel showing captures). Label live-updates on ban/unban.
- Right: `[reset]` (56w). Click sends `ss reset` to locked target and wipes local exclusions.

### 3.10 Color token palette

All colors come from `ns.Tokens` (see `Core.lua`). Designer should respect these tokens for consistency across the addon's other tabs.

| Token        | RGB                       | Used for                                |
|--------------|---------------------------|------------------------------------------|
| `stone_dark` | `(0.07, 0.05, 0.03)`     | Frame deep bg                            |
| `stone_mid`  | `(0.10, 0.08, 0.05)`     | Row bg                                   |
| `stone_tile` | `(0.18, 0.13, 0.09)`     | Stone button bg                          |
| `stone_rim`  | `(0.23, 0.18, 0.13)`     | Idle row rim, separator rules, inactive button rim |
| `gold`       | `(1.00, 0.82, 0.00)`     | Title text, LOCKED/LIVE accent, capture-active status |
| `gold_dim`   | `(0.55, 0.50, 0.42)`     | Hint text, disabled labels, idle status text |
| `gold_rim`   | `(0.66, 0.54, 0.30)`     | Active mode button rim, click-pulse rim, frame border |
| `red_btn`    | `(0.50, 0.10, 0.05)`     | (reserved for warn buttons; unused in Shield) |
| `ink_red`    | `(0.85, 0.18, 0.12)`     | Close glyph, exclusion-row text          |
| `text_warm`  | `(0.85, 0.80, 0.69)`     | Captured-line text                       |

### 3.11 Tooltips

Every interactive element (buttons, toggles) calls `ns.UI.Tooltip.Attach(widget, title, body, anchor)` with `ANCHOR_TOP`. Tooltip body uses 2-3 sentences of plain prose.

---

## 4. Open UX questions for the redesigner

These are decisions WardenShield's current implementation makes implicitly that a designer should explicitly review.

1. **Target picker for `caston`**: today, any `PLAYER_TARGET_CHANGED` while in `caston` mode captures the new target — including the user accidentally tab-targeting. Should this be tightened to "click on a UnitFrame" specifically? The current event-based capture is universal but indiscriminate.

2. **Visual feedback for ban**: today, clicking a row in `ban` mode pulses gold and adds the entry to the persisted list, but the captured-list view doesn't visibly mark which spells are already banned. The user must toggle `[exclusions: N]` to see the mirror. Should banned rows in the captured list be visually marked (struck-through, dim, red dot)?

3. **`hide gray` semantics**: gray rank means "bot can't cast right now" — but the user might still want to ban these. Today, `[hide gray]` hides them everywhere including when in `ban` mode. Should it be mode-aware?

4. **Scrolling**: 200h list × 18h row = ~10 visible rows. A spells whisper is 50–100+ entries. Vertical scrolling works but is slow. Should there be a search/filter input field above the list?

5. **Multi-bot support**: today, the captured list mixes whispers from any bot if `state.target` was unlocked between captures. Each line stores `from` so the click sends to the right bot, but the user can't tell at a glance which bot a row came from. Should rows show a bot-name prefix?

6. **Frame compactness**: total frame is now ~370h, up from ~316h pre-MODE/FOOTER rows. Does the redesign want to compact this (e.g., merge MODE row into ACTION row, or merge FOOTER into STATUS row)?

7. **Cast-on label location**: today, "on <Name>" sits inline next to the unban button. Cluttered when bot names are long. Should it be a separate row or a tooltip overlay?

8. **Section headers in capture list**: separators (`=== Spells ===`, etc.) are hidden today. Should they be rendered as styled section headers instead of skipped, so the user can scroll-to-section?

---

## 5. File layout (so designer can locate things)

```
Warden/
├── Shield.lua                             ← module under design
├── Bindings.xml                           ← keybinding XML (Ui-wrapper format)
├── Persistence.lua                        ← db.shield init (line 64–72)
├── Core.lua                               ← ns.Tokens, ns.UI.Button.{stone,gold,red,warn}, ns.UI.Tooltip
├── Log.lua                                ← ns.DebugF (logs only when shield cat enabled)
├── docs/specs/
│   ├── 2026-04-26-wardenshield-design.md  ← original POC spec
│   └── 2026-04-28-wardenshield-feature-list.md ← this file
├── PLAYERBOT_COMMANDS.md                  ← server-side commands reference
└── Warden.toc                             ← Shield.lua at line 19
```

Test harness lives outside the addon at `/home/mmasson/warden/` (Lua 5.1.5 standalone, 11 suites, 294 cases). It tests the pure-logic helpers (`extractPayload`, `extractSpellId`, etc.) and the Shield state machine. Visual layout / frame templates are NOT tested — those changes need manual `/reload` verification.

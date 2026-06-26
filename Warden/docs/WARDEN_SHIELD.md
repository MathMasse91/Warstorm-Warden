# WardenShield — Discovery & Capture HUD
> UI reference for redesign. All code refs point to `Shield.lua` unless noted.

**Slash:** `/wsh`  
**Frame name:** `WardenShieldFrame`  
**Keybinding:** `WARDENSHIELD_TOGGLE`  
**Spec doc:** `docs/specs/2026-04-26-wardenshield-design.md`

---

## 1. Purpose

WardenShield is a floating command panel for bot discovery. The user targets a bot, clicks `[los]` or `[spells]`, the addon whispers the command and captures the bot's whisper reply for a configurable duration. Each captured line is rendered as a clickable row. Clicking a row fires the appropriate follow-up command depending on the active **action mode**.

---

## 2. Frame Layout

```
┌─────────────────────────────────────┐  ← HEADER (22px)
│ WARDENSHIELD  /wsh    [o] [x]       │
├─────────────────────────────────────┤  ← TARGET ROW (22px)
│ LIVE: Botname (class-colored)  [pick]│
├─────────────────────────────────────┤  ← ACTION ROW (22px)
│ [los]   [spells]           [clear]  │
├─────────────────────────────────────┤  ← MODE ROW (22px)
│ [cast] [on Y] [on me] [ban] [unban] │  on Y: Targetname
├─────────────────────────────────────┤  ← STATUS STRIP (16px)
│ listening 3s · 12 lines             │
├─────────────────────────────────────┤
│ ▼ Clickable list (scrollable)       │  ← LIST (200px default)
│   > [Spell Link]                    │
│   > [Object]                        │
│   ...                               │
├─────────────────────────────────────┤  ← FOOTER (18px)
│ [hide gray]  [exclusions: N]  [reset]│
└─────────────────────────────────────┘
```

**Frame dimensions:** 260 px wide, height computed from row heights + gaps.  
**Strata:** HIGH (level 100) — always above main Warden window.  
**Background:** `UI-DialogBox-Background` tiled + fully opaque fill 0.07/0.05/0.03.  
**Border:** 1px gold rim `0.72, 0.58, 0.21`.

---

## 3. Header Row (`buildHeader`)

`Shield.lua:148`

| Element | Detail |
|---------|--------|
| Title | "WARDENSHIELD" gold (`GameFontNormal`) |
| Hint | "/wsh" muted gold-dim |
| Lock glyph | `o` (unlocked, muted) / `*` (locked, gold) — toggled by `ns.Shield.ToggleLock()` |
| Close `x` | Red glyph — calls `ns.Shield.Hide()` |
| Bottom rule | 1px stone-rim divider |

Lock prevents drag-to-move. Persisted as `db.shield.locked`. `Shield.lua:191`

---

## 4. Target Row

`Shield.lua:796`

| Element | Detail |
|---------|--------|
| Target label | Two-tier: **LOCKED: Name** (class-colored) when a target is set, or **LIVE: Name** from `UnitName("target")`, or "`TARGET: no target`" muted |
| `[pick]` button | Snapshots `UnitName("target")` → sets `state.target` + `state.targetClass`. Does NOT send a discovery command. |

A 0.5 s heartbeat (`OnUpdate`) keeps the label fresh when the user switches targets. `Shield.lua:1010`

**Player flag guard:** If the picked name is in `db.playerFlags`, pick is rejected with a warning. `Shield.lua:676`

---

## 5. Action Row (discovery commands)

`Shield.lua:829`

| Button | Width | Behavior |
|--------|-------|----------|
| `[los]` | 76px stone | Calls `startCapture("los")` — whispers "los" to locked bot, opens capture window |
| `[spells]` | 76px stone | Calls `startCapture("spells")` — whispers "spells" to locked bot |
| `[clear]` | 56px stone | `ns.Shield.Clear()` — wipes list, unlocks target, stops capture |

**Active capture visual:** The active button's border flashes gold (`GOLD_RIM`) while capture window is open. Returns to stone when expired. `Shield.lua:220`

### `startCapture(mode)` flow (`Shield.lua:699`)
1. Uses locked `state.target` if set; otherwise calls `snapshotTarget()` from live UnitName
2. Rejects human-flagged targets
3. Sets `state.captureUntil = GetTime() + captureSec` (1–60 s, from `db.shield.captureSec`, default 5)
4. Wipes `state.lines`
5. Arms listener + countdown ticker
6. Whispers `mode` to target
7. Calls `refreshAll()`

---

## 6. Mode Row (action dispatch)

`Shield.lua:863`

Five buttons that set `state.actionMode`. The active button has a gold border.

| Button | Key | Click behavior on a list row |
|--------|-----|------------------------------|
| `cast` | `"cast"` | los line → `u [payload]`; spells line → `cast payload` |
| `on Y` | `"caston"` | Captures next `PLAYER_TARGET_CHANGED` as cast target; sends `cast payload on Name` |
| `on me` | `"selfcast"` | Sends `cast payload on <PlayerName>` |
| `ban` | `"ban"` | Extracts spell ID from line → `ss +<id>`, adds to `db.shield.exclusions` |
| `unban` | `"unban"` | Extracts spell ID → `ss -<id>`, removes from exclusions |

**Cast-on label:** When `actionMode == "caston"` and a target was captured, a muted label to the right of `[unban]` shows "on Targetname" (gold) or "click a frame" (gray). `Shield.lua:903`

**`clickLine(idx)` dispatch** — `Shield.lua:373`:
- Resolves line through `state.displayItems` (filtered/sorted list) so separator + hide-gray filtering can't desync indices
- Sends to `line.from` (the bot that produced the line), not the current `state.target`
- Re-checks player flag at click time

---

## 7. Status Strip

`Shield.lua:258`

| State | Text | Color |
|-------|------|-------|
| Capturing | `listening Ns · M lines` | Gold |
| Idle | `idle · M lines` | Muted gold-dim |

Countdown updated every 0.2 s by a dedicated `countdownFrame` ticker. `Shield.lua:654`

---

## 8. Captured Lines List (scrollable)

`Shield.lua:538`

### Row Pool
- Rows are built lazily via `ensureRow(idx, parent)` and reused between refreshes — `Shield.lua:276`
- Each row: `Button` with backdrop, `FontString` (left-anchored, no word wrap), highlight texture
- `ROW_H = 18px`, 2px gap between rows

### Row States
| State | Border | Text color |
|-------|--------|------------|
| Normal | Stone rim | `0.85, 0.80, 0.69` |
| Click pulse | Gold rim → stone (120 ms animation) | — |
| Exclusion view | — | Red `0.85, 0.18, 0.12` |

### Content per row
- Normal: `> raw whisper text` (preserves WoW item/spell links for coloring)
- Exclusion view: `[banned] SpellName  (id N)`

### Filtering (`buildDisplayItems` — `Shield.lua:505`)

**Hide gray filter:** When `state.hideGray` is true, lines whose last color code is `808080` (gray rank suffix = bot can't use this spell) are excluded.

**Sort:** Alphabetical by `line.payload` (case-insensitive).

**Separator lines** (`===` or `---` prefix) are always filtered out.

**Cap:** Max 200 lines (`MAX_LINES`). Oldest line dropped when limit is hit. `Shield.lua:629`

### Scroll
`UIPanelScrollFrameTemplate` with thin scrollbar (8px, no arrow buttons). `Shield.lua:986`

---

## 9. Footer Row

`Shield.lua:929`

| Button | Behavior |
|--------|----------|
| `[hide gray]` | Toggle `state.hideGray`; border turns gold when active; calls `refreshList()` |
| `[exclusions: N]` | Toggle between captured list view and persisted exclusions view; counter stays live |
| `[reset]` | Whispers `ss reset` to locked bot; wipes `db.shield.exclusions` locally |

---

## 10. Exclusions Panel (alternate list view)

When `state.viewExclusions` is true, the scroll list renders `db.shield.exclusions` instead of `state.lines`.

Each row shows `[banned] SpellName  (id N)`. Clicking a row calls `clickExclusion()`:
1. Whispers `ss -<id>` to the locked bot
2. Removes entry from `db.shield.exclusions`
3. Refreshes counter + list

`Shield.lua:347`

---

## 11. Whisper Capture Logic (`listenerFrame` — `Shield.lua:597`)

Single dedicated `CHAT_MSG_WHISPER` listener frame (separate from any master frame).

**Conditions to accept a whisper:**
1. `state.captureUntil > 0` and `GetTime() <= state.captureUntil`
2. `sender == state.target`

Each accepted line stored as:
```lua
{
    raw     = text,              -- full raw whisper string (with WoW link codes)
    payload = extractPayload(text),  -- first [Bracketed] segment or trimmed text
    ts      = GetTime(),
    from    = state.target,      -- bot name at capture time
    mode    = state.mode,        -- "los" | "spells"
}
```
`Shield.lua:631`

**`extractPayload(text)` — `Shield.lua:95`:**
1. Strip WoW color/link codes
2. Return first `[Bracketed]` segment if present
3. Otherwise return trimmed plain text

**`extractSpellId(raw)` — `Shield.lua:107`:** Parses `|Hspell:N|h` for ban/unban.  
**`extractObjectId(raw)` — `Shield.lua:113`:** Parses `|Hfound:...:N:|h` for los entries.

Also registers `PLAYER_TARGET_CHANGED` for `caston` mode target capture. `Shield.lua:607`

---

## 12. Persisted State (`db.shield`)

`Persistence.lua:66`

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `pos` | table | nil | `{ point, x, y }` anchor |
| `locked` | bool | false | Prevents drag |
| `hidden` | bool | false | Visibility on login |
| `captureSec` | number | 5 | Capture window duration (1–60 s) |
| `exclusions` | table | `{}` | `[{ id, name }, ...]` persisted banned spells |

---

## 13. Public API

`Shield.lua:1026`

```lua
ns.Shield.Show()
ns.Shield.Hide()
ns.Shield.Toggle()
ns.Shield.SetLocked(bool)
ns.Shield.ToggleLock()
ns.Shield.ResetPosition()
ns.Shield.Clear()           -- wipe list, unlock target
ns.Shield.PrintHelp()
ns.Shield.Frame()           -- returns raw frame
```

---

## 14. Slash Commands

```
/wsh               toggle
/wsh show|hide     explicit visibility
/wsh toggle        same as bare /wsh
/wsh lock|unlock   position lock
/wsh reset         reset position to default (TOPRIGHT -40, -380)
/wsh clear         wipe captured list + unlock target
/wsh los           fire `los` discovery immediately
/wsh spells        fire `spells` discovery immediately
/wsh help          print command list
```

---

## 15. Bootstrap

Routes through `ns.Persistence.OnReady` so `db.shield` is guaranteed populated before reading `hidden`/`locked`. Listener is armed immediately (even before first `/wsh los`) so `PLAYER_TARGET_CHANGED` works for caston without a prior capture. `Shield.lua:1127`

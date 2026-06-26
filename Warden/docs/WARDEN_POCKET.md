# WardenPocket — WTS Offer Aggregator
> UI reference for redesign. All code refs point to `Pocket.lua` unless noted.

**Slash:** `/wp`  
**Frame name:** `WardenPocketFrame`

---

## 1. Purpose

WardenPocket automates WTS auctions against bot buyers. The user drops an item into the slot, clicks `[WTS]`, and the addon:
1. Broadcasts `"wts <item link>"` to channel 1 (General)
2. Listens for whispered price offers (`Xg Ys Zc` format)
3. Tracks offers in a ranked list (highest first)
4. Auto-invites the highest bidder after a silence timeout or when configurable caps are reached

When the trade window opens a floating **Trade Banner** lets the user set quantity and whisper a compact total price.

---

## 2. Frame Layout

```
┌─────────────────────────────────────────┐  ← HEADER (22px)
│ Warden Pocket                      [x]  │
├─────────────────────────────────────────┤  ← INPUT ROW (22px)
│ Item: [□ slot] [──── EditBox ────] [WTS]│
├─────────────────────────────────────────┤  ← STATUS (18px)
│ Listening... — best: 12g 21s            │
├─────────────────────────────────────────┤
│ BotName                        12g 21s  │  ← LIST (180px)
│ BotName2                        9g 5s   │    scrollable
│ ...                                      │
├─────────────────────────────────────────┤  ← FOOTER (22px)
│ [Clear]  Top:[20] Wait:[30]s    [Stop]  │
└─────────────────────────────────────────┘
```

**Frame dimensions:** 280 px wide, height computed from section heights.  
**Strata:** MEDIUM  
**Background:** solid stone-dark 0.07/0.05/0.03 (from `ns.Tokens.stone_dark`).  
**Border:** stone-rim 1px.

---

## 3. Header

`Pocket.lua:408`

| Element | Detail |
|---------|--------|
| Title | "Warden Pocket" gold (`|cffffd100`) |
| Close `[x]` | `UIPanelCloseButton` 18×18, calls `ns.Pocket.Hide()` |

Draggable via `RegisterForDrag("LeftButton")`. Starts hidden — `f:Hide()` at end of `build()`. `Pocket.lua:583`

---

## 4. Input Row

`Pocket.lua:420`

### 4.1 `Item:` label
Muted gray, `|cff888888Item:|r`. Fixed left edge.

### 4.2 Item Slot (`WardenPocketItemSlot`)

`Pocket.lua:427`

22×22 button (square, same height as `INPUT_H`). Accepts items three ways:

| Method | Mechanism |
|--------|-----------|
| **Drag from bag** | `OnReceiveDrag` → `GetCursorInfo()` returns `"item", id` → `GetItemInfo(id)` → stores link |
| **Click slot with item on cursor** | `OnClick` → same `GetCursorInfo()` flow |
| **Shift-click bag item** with EditBox focused | WoW built-in — inserts item link directly into EditBox; `OnTextChanged` detects `|Hitem:N` and updates icon |

Visual states:
- **Empty:** question-mark icon (`INV_Misc_QuestionMark`), alpha 0.3
- **Filled:** actual item texture from `GetItemInfo`, alpha 1.0

Background: solid black at 0.5 alpha. `slotCapture()` calls `ClearCursor()` after capture. `Pocket.lua:446`

### 4.3 EditBox (`WardenPocketInput`)

`Pocket.lua:462`

- Width fills gap between slot and `[WTS]` button
- `SetAutoFocus(false)` — won't steal focus
- `SetMaxLetters(256)` — handles full WoW item link strings
- `OnEnterPressed` → `sendWTS()` + `ClearFocus()`
- `OnTextChanged` → parses `|Hitem:N` to update slot icon

Plain text is accepted by the EditBox but **blocked at send time** — only item hyperlinks containing `|H` are transmitted. `Pocket.lua:364`

### 4.4 `[WTS]` Button

`Pocket.lua:484`

- Style: `ns.UI.Button.red`, 50px wide
- Calls `sendWTS()`

**`sendWTS()` flow** (`Pocket.lua:358`):
1. Validate `state.item` is non-empty
2. Require `|H` in string (real hyperlink) — otherwise warn and return
3. Reset session state: wipe offers, nil invited/bestOffer, reset timers
4. Set `state.armed = true`
5. Call `ensureListener()`
6. `SendChatMessage("wts " .. item, "CHANNEL", nil, 1)` — sends clickable link to channel 1
7. Log info: "Pocket: listening for offers on [ItemName]..."

---

## 5. Status Label

`Pocket.lua:491`

Single `FontString`, full width, left-justified. Updates via `refreshStatus()`.

| State | Text | Color |
|-------|------|-------|
| Idle, no offers | "Idle" | Muted gray |
| Idle, has offers | "N offers — best: Xg Ys" | Muted gray |
| Armed, no offers | "Listening..." | Amber `ffffaa00` |
| Armed, has offers | "N offers — best: Xg Ys" | Amber |
| Invited | "Invited BotName (Xg Ys)" | Green `00ff00` |

---

## 6. Offer List (scrollable)

`Pocket.lua:500`

**ScrollFrame** (`WardenPocketScroll`), 180px tall, with mousewheel scroll (3 rows per tick).  
**ScrollChild** (`WardenPocketScrollChild`) grows dynamically with offer count.

### Row layout
`ROW_H = 18px`

```
[BotName ···················] [12g 21s]
```

- Name: left-aligned, 170px wide (`GameFontNormalSmall`)
- Price: right-aligned
- Top row (highest bidder): gold color `|cffffd100`
- Other rows: default color

### Row pool
Rows are lazily created and reused. Even-index rows get a subtle stripe overlay (white 4% alpha). `Pocket.lua:156`

### Sorting
Descending by copper value. `sortedOffers()` — `Pocket.lua:94`

---

## 7. Footer Strip

`Pocket.lua:517`

### 7.1 `[Clear]` button
Stone, 60px. `Pocket.lua:518`

**Behavior:**
1. If `state.invited` is set → `UninviteUnit(state.invited)` (kicks bot from party)
2. Wipe all offers
3. Reset `invited`, `bestOffer`, timers, `armed`
4. Hide all list rows
5. Call `refreshStatus()`

### 7.2 `Top: [N]` field
Label + numeric EditBox (28px wide, max 3 chars). Sets `state.maxOffers`.

- `0` = unlimited
- Default: `20`

When `#state.offers >= state.maxOffers` (and maxOffers > 0), `fireInvite()` is called immediately. `Pocket.lua:347`

### 7.3 `Wait: [N]s` field
Same pattern. Sets `state.maxWait` (seconds from WTS broadcast).

- `0` = unlimited
- Default: `30`

Hard cap enforced by OnUpdate ticker. `Pocket.lua:311`

### 7.4 `[Stop]` button
Stone, 60px. Sets `state.armed = false` without clearing offers. `Pocket.lua:573`

---

## 8. Auto-invite Logic

### Three triggers (all call `fireInvite()`)

| Trigger | Condition | Code ref |
|---------|-----------|----------|
| **Silence debounce** | No new whisper for `INVITE_DELAY` (2.0 s) since last whisper | `Pocket.lua:314` |
| **Max offers** | `#state.offers >= state.maxOffers` | `Pocket.lua:347` |
| **Max wait** | `GetTime() - state.armedTime >= state.maxWait` | `Pocket.lua:311` |

### `fireInvite()` (`Pocket.lua:282`)
1. Guard: `state.armed` and at least 1 offer
2. Sort offers descending
3. Set `state.bestOffer` + `state.invited` to top entry
4. Set `state.armed = false`
5. `InviteUnit(state.bestOffer.name)`
6. Log info
7. `refreshList()`

### OnUpdate ticker (`pocketListener` — `Pocket.lua:305`)
Runs every 0.25 s, polls:
- maxWait cap first
- then silence debounce

Checks maxWait first so it always fires on time even if whispers keep arriving.

---

## 9. Event Listener (`pocketListener` — `Pocket.lua:297`)

Built lazily on first `[WTS]` click via `ensureListener()`. Persists for the session.

Registered events:
- `CHAT_MSG_WHISPER` — price capture
- `TRADE_SHOW` — show Trade Banner
- `TRADE_CLOSED` — hide Trade Banner

### Whisper parsing (`parseCopper` — `Pocket.lua:56`)
Accepts format: `Xg Ys Zc` (any subset). Returns total copper or nil if no price tokens found.

```
"12g 21s 23c"  →  123223 copper
"5g"           →  50000 copper
"50s"          →  5000 copper
```

### Offer update logic (`Pocket.lua:330`)
1. If sender already has an offer: update only if new copper > old copper
2. Otherwise: insert new offer
3. Update `state.lastWhisperTime`
4. Check maxOffers cap

---

## 10. Trade Banner

`Pocket.lua:200`

Floating overlay that appears when `TRADE_SHOW` fires and `state.bestOffer` is set. Hidden on `TRADE_CLOSED`.

**Frame name:** `WardenPocketTradeBanner`  
**Size:** 270 × 56  
**Strata:** HIGH  
**Default position:** CENTER -150 (below screen center)  
**Movable:** yes (drag)

```
┌───────────────────────────────────────┐
│ Best: BotName — 12g 21s / unit        │   ← info row
│ Qty: [1_] = |12g 21s|  [Whisper]      │   ← qty row
└───────────────────────────────────────┘
```

| Element | Detail |
|---------|--------|
| Info label | "Best: Name — Xg Ys/unit" (gray label, gold values) |
| Qty EditBox | `WardenPocketQtyBox`, numeric, max 4 chars, default "1" |
| Total label | Gold — `qty × bestOffer.copper` formatted as "Xg Ys Zc" |
| `[Whisper]` button | Gold style, 68px — sends `formatCopperCompact(total)` as WHISPER to winner |

**Total updates** live as qty changes (`OnTextChanged`). `Pocket.lua:185`

**Compact whisper format** (`formatCopperCompact` — `Pocket.lua:79`): no spaces — `"12g21s23c"` — matching bot payment-detection format.

---

## 11. Price Formatting

Two format functions:

| Function | Output example | Usage |
|----------|---------------|-------|
| `formatCopper(copper)` | `"12g 21s 23c"` | Display labels in list + status |
| `formatCopperCompact(copper)` | `"12g21s23c"` | Whisper to bot (compact, no spaces) |

`Pocket.lua:66` / `Pocket.lua:79`

---

## 12. Module State

`Pocket.lua:32`

| Key | Type | Description |
|-----|------|-------------|
| `frame` | Frame | Main HUD frame |
| `armed` | bool | Listening for offers |
| `item` | string | Current item link (or empty) |
| `offers` | table | `[{ name, copper, display }, ...]` |
| `lastWhisperTime` | number | `GetTime()` of last price whisper |
| `armedTime` | number | `GetTime()` when WTS was sent |
| `invited` | string | Name of invited bot (or nil) |
| `bestOffer` | table | `{ name, copper, display }` |
| `rowFrames` | table | Pool of list row frames |
| `statusLbl` | FontString | Status label reference |
| `listChild` | Frame | ScrollChild frame reference |
| `inputBox` | EditBox | Item name/link EditBox |
| `slotIcon` | Texture | Item slot icon texture |
| `maxOffers` | number | Cap (default 20, 0 = unlimited) |
| `maxWait` | number | Timeout in seconds (default 30, 0 = unlimited) |

State is **session-only** — not persisted to `WardenDB`.

---

## 13. Public API

`Pocket.lua:590`

```lua
ns.Pocket.Show()
ns.Pocket.Hide()
ns.Pocket.Toggle()
```

---

## 14. Slash Commands

```
/wp               toggle HUD
/wp show          explicit show
/wp hide          explicit hide
/wp ItemName      toggle + pre-fill item text in EditBox
/wardenpocket     alias for /wp
```

Pre-fill only inserts plain text into the EditBox — user still needs to drag the actual item for the hyperlink. `Pocket.lua:609`

---

## 15. Tunables (top of file)

`Pocket.lua:19`

| Constant | Value | Description |
|----------|-------|-------------|
| `FRAME_W` | 280 | HUD width |
| `HEADER_H` | 22 | Header height |
| `INPUT_H` | 22 | Input row height (also item slot size) |
| `STATUS_H` | 18 | Status label height |
| `LIST_H` | 180 | Offer list visible height |
| `ROW_H` | 18 | Per-row height in list |
| `FOOTER_H` | 22 | Footer strip height |
| `PAD` | 8 | Horizontal padding |
| `INVITE_DELAY` | 2.0 s | Silence debounce before auto-invite |

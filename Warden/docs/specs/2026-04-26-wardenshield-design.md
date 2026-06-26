# WardenShield — POC Design

**Date:** 2026-04-26
**Status:** Approved (brainstorm) — pending implementation
**Owner:** UnrealTruth
**Companion module:** WardenSword (parallel pattern)

---

## 1. Goal

Add a small floating HUD module called **WardenShield** to Warden. It lets a raid leader send a "discovery" command to a single targeted bot, capture the bot's whispered response, and surface each line as a clickable entry that fires the corresponding follow-up command.

The POC supports two command pairs:

| Discovery whisper | Follow-up whisper (sent on click) |
|---|---|
| `los` | `u <payload>` (use object) |
| `spells` | `cast <payload>` (cast spell) |

`payload` = the `[Bracketed Name]` extracted from a line if present, otherwise the whole trimmed line.

## 2. Non-goals (POC)

- Trainer / pet / tame / RTSC / RTI / `do attack` commands. They live in `PLAYERBOT_COMMANDS.md`; we may add them in a follow-up phase once parsing patterns are validated against real bot output.
- `cast <spell> on <target>` form (3-arg cast). Click sends `cast <spell>` to the same bot; user can extend later.
- Multi-bot fan-out. One target at a time.
- Persistence of captured lines across `/reload`. Capture is ephemeral.
- Any change to the existing main Warden window or WardenSword.

## 3. Architecture

### 3.1 Files touched

```
Warden/
├── Shield.lua           ← NEW (~400 lines)
├── Warden.toc           ← MODIFIED (one new entry)
└── Bindings.xml         ← MODIFIED (optional binding for /wsh toggle)
```

No new namespace tier — everything lives under `ns.Shield = {...}`, parallel to `ns.WardenSword`.

### 3.2 Reused infrastructure

WardenShield piggybacks on existing helpers; we add no new abstractions:

- `ns.UI.Button.{stone,red,gold,warn}` — buttons
- `ns.UI.Panel.Create` / `ApplyStoneBackdrop` — frame chrome
- `ns.UI.Tooltip.Attach` — hover tooltips
- `ns.UI.Dropdown.style` — only if a settings dropdown is added later
- `ns.Tokens` — color palette
- `ns.Persistence.OnReady(cb)` — single rendezvous after DB init (avoids the same `PLAYER_LOGIN` race that WardenSword's bootstrap fix solves)
- `ns.Persistence.IsPlayerName(name)` — guards against acting on flagged human players
- `ns.MsgInfo / MsgWarn / MsgErr` — chat output
- `ns.ColorClass(classToken, text)` — class-colored target name
- `ns.DebugF("shield", ...)` (new debug category, see §6)

### 3.3 Bootstrap

Same pattern as `WardenSword.lua`:

```lua
ns.Persistence.OnReady(function()
    build()
    if state.shieldDB and state.shieldDB.hidden then frame:Hide() else frame:Show() end
end)
```

This avoids a `PLAYER_LOGIN` handler racing with `Persistence.lua` — see the comment block in `WardenSword.lua` near line 670 for the precedent.

## 4. Persisted state

A new sub-table `WardenDB.shield`, initialized in `Persistence.lua`'s `initDB()` alongside `db.sword`:

```lua
db.shield = {
    pos        = nil | { point, x, y },  -- restored by applyPosition()
    locked     = false,                  -- drag-lock toggle
    hidden     = false,                  -- last-known visibility
    captureSec = 5,                      -- capture window duration
}
```

`Persistence.lua` adds `"shield"` to the `COMMIT_SUBTABLES` list so the table is committed at logout, and its keys are seeded with sensible defaults in `initDB`. (Schema version does **not** need to bump — adding a brand-new sub-table is an additive change tolerated by the existing `if type(...) ~= "table"` guards.)

## 5. Runtime state (module-local, not persisted)

```lua
local state = {
    frame        = nil,        -- top-level HUD frame (built lazily)
    shieldDB     = nil,        -- shortcut to ns.Persistence.DB.shield
    target       = nil,        -- frozen target name for the active capture session
    targetClass  = nil,        -- classToken for class-colored display
    mode         = nil,        -- "los" | "spells" | nil
    captureUntil = 0,          -- GetTime() deadline; 0 = idle
    lines        = {},         -- { { raw = "...", payload = "...", ts = number }, ... }
    rowFrames    = {},         -- pool of clickable row frames (reused across refreshes)
}
```

## 6. UI layout

ASCII reference (drawn at `compact` density-equivalent, ~250 px wide × ~330 px tall):

```
+- WARDENSHIELD ---------- /wsh   o  x +
|                                      |
| TARGET: Patchs (Mage)         [pick] |
|                                      |
| +----------+  +----------+  +-----+  |
| |   los    |  |  spells  |  |clear|  |
| +----------+  +----------+  +-----+  |
|                                      |
| -- listening 4s -- 12 lines -------- |
| +--------------------------------+   |
| | > [Twilight Portal]           ^|   |
| | > [Mailbox]                    |   |
| | > Door (locked)                |   |
| | > [Treasure Chest]             |   |
| | ...                           v|   |
| +--------------------------------+   |
|                                      |
| click line -> u <payload>            |
|            or cast <payload>         |
+--------------------------------------+
```

### 6.1 Components

| Component | Notes |
|---|---|
| **Header** | Same widget pattern as `WardenSword.buildHeader` — title `WARDENSHIELD`, slash hint `/wsh`, lock toggle (`o`/`*`), close `x`. Drag handle for `frame`. |
| **Target row** | `FontString` showing `UnitName("target")` colorized by class via `ns.ColorClass`, or `|cff808080no target|r` muted. Right-aligned `[pick]` `ns.UI.Button.stone`. |
| **Mode buttons** | `los` and `spells` `ns.UI.Button.stone`. While `state.mode` matches **and** `state.captureUntil > GetTime()`, the rim flips to `ns.Tokens.gold_rim` (canonical emphasis rim used by `ns.UI.Button.gold`). When the capture window closes, both rims return to `ns.Tokens.stone_rim`. |
| **`[clear]` button** | Wipes `state.lines` + `state.mode` and disables capture early. Stone variant. |
| **Status strip** | Single muted FontString. While capturing: `listening Ns — N lines` (countdown updates every 0.2 s). Idle: `idle — N lines`. |
| **Scroll area** | `UIPanelScrollFrameTemplate`. Child holds row buttons stacked vertically. Each row is `ns.UI.Button.stone` width-100% × 18 px, label = `"> " .. line.raw`. Click sends follow-up. |

### 6.2 Visual rules

- HUD background: `Interface\\DialogFrame\\UI-DialogBox-Background` tile 16, `WHITE8x8` 1 px gold-dim rim. Same as `WardenSword`.
- Frame strata `HIGH`, frame level 100 — sits above the main `/warden` window if they overlap.
- All anchors absolute (no template anchors that re-flow on chrome retint).
- Rebuild list rows via a small object pool (`state.rowFrames`) to avoid leaking frames each refresh.

## 7. Event flow

```
[user] picks a target in-game (UnitName("target") = "Patchs")
[user] clicks [los]
   |
   v
1. snapshotTarget()
     guards:
       - UnitExists("target") + UnitIsPlayer("target")    else: MsgErr("target a player first")
       - not UnitIsUnit("target", "player")               else: MsgErr("can't run on yourself")
       - not ns.Persistence.IsPlayerName(name)            else: MsgWarn("target is flagged [P]")
   |
   v
2. SendChatMessage("los", "WHISPER", nil, target)
   |
   v
3. state.target = target ; state.targetClass = classToken
   state.mode = "los"
   state.captureUntil = GetTime() + state.shieldDB.captureSec
   wipe(state.lines)
   refreshUI()
   ensureWhisperListener()  -- idempotent; registers CHAT_MSG_WHISPER once
   armCountdown()           -- OnUpdate, 0.2 s tick
   |
   v
4. CHAT_MSG_WHISPER fires
   handler(arg1=text, arg2=sender, ...):
     if state.captureUntil == 0                           -> ignore (idle)
     if GetTime() > state.captureUntil                    -> ignore (window closed)
     if sender ~= state.target                            -> ignore (foreign whisper)
     payload = extractPayload(text)
     append { raw=text, payload=payload, ts=GetTime() } to state.lines
     refreshList()
   |
   v
5. countdown ticker hits 0
     state.captureUntil = 0
     refreshStatus()  -- "listening" -> "idle"
     (event handler stays registered; the captureUntil gate filters everything out)
   |
   v
[user] clicks one of the captured lines
   guards:
     - state.target still set
     - not ns.Persistence.IsPlayerName(state.target)  (re-check; flag could have been added since)
   action:
     if state.mode == "los"    -> SendChatMessage("u "    .. line.payload, "WHISPER", nil, state.target)
     if state.mode == "spells" -> SendChatMessage("cast " .. line.payload, "WHISPER", nil, state.target)
   feedback:
     pulse the row's rim gold for 120 ms (reusing pulseBtn-style animation)
     MsgInfo printed in chat with what was sent
```

### 7.1 Payload extraction

```
extractPayload(text):
    -- Prefer the first [Bracketed] segment, which matches WoW item links + the
    -- los/spells output convention seen in Mod-Playerbots docs.
    bracket = text:match("%[([^%]]+)%]")
    if bracket then return bracket end
    -- Fallback: trimmed full line.
    return Trim(text)
```

The whisper sent uses `"u [..]"` form when bracketed (preserving WoW's item-link parser) and `"u text"` otherwise. We store the original `raw` for display so the user always sees what the bot actually sent.

### 7.2 Re-click behavior

| User action | Effect |
|---|---|
| Re-click `[los]` while capturing `los` | Resets: `wipe lines`, restarts 5 s countdown, re-sends `los` whisper |
| Click `[spells]` while capturing `los` | Same: `mode = "spells"`, wipe + restart, sends `spells` |
| `[pick]` mid-capture | Snapshots the new `UnitName("target")` into `state.target`; future incoming whispers from the **old** target are ignored (sender filter). Does not re-send a discovery command — user clicks `[los]`/`[spells]` again |
| `[clear]` | `wipe(lines)`, `mode=nil`, `captureUntil=0` |
| Click a captured line after countdown ended | Still works — the captured `lines` are independent of the capture window |
| Window closed (`x`) | Hides the frame, sets `db.shield.hidden = true`. State persists in memory but the user can't act on it until reopen |

## 8. Slash commands

Pattern copied from `/ws`:

| Slash | Action |
|---|---|
| `/wsh` | Toggle |
| `/wsh show` / `/wsh hide` / `/wsh toggle` | Explicit |
| `/wsh lock` / `/wsh unlock` | Drag lock |
| `/wsh reset` | Reset position to default upper-right |
| `/wsh clear` | Same as `[clear]` button |
| `/wsh help` | Print command list |
| `/wsh los` | If a valid target exists: behaves like clicking `[los]` |
| `/wsh spells` | If a valid target exists: behaves like clicking `[spells]` |

Defaults if no token recognized: print help.

## 9. Bindings

One optional binding header `WARDENSHIELD` with one entry `WARDENSHIELD_TOGGLE`, calling a global `WARDENSHIELD_Toggle()`. Mirrors `WardenSword`'s pattern. Keep it minimal for the POC.

## 10. Logging / debug

Add `"shield"` to `ns.DebugCats` in `Log.lua`. Trace points:

- `shield: build()` once
- `shield: snapshot target=%s class=%s mode=%s deadline=+%.1fs`
- `shield: whisper from=%s len=%d kept=Y/N reason=...`
- `shield: line click idx=%d mode=%s payload=%q`
- `shield: capture window closed (%d lines)`

Toggle via `/wardenlog debug shield on`. Errors always logged.

## 11. Player-flag guards

The same `ns.Persistence.IsPlayerName` check that protects `Engine.PushWhisper`, `processUnit`, and the Roster Re-Spec buttons applies here:

- Refuse the discovery command if `IsPlayerName(targetName)` (silently? or with `MsgWarn`?). **Decision: `MsgWarn`** — an explicit refusal is friendlier than a silent no-op for an interactive feature.
- Re-check at follow-up click time, in case the user flagged the character mid-capture.

## 12. Edge cases

| Case | Handling |
|---|---|
| `UnitName("target")` returns `nil` | `MsgErr("Target a player first.")` — no command sent |
| Target is the player themselves | `MsgErr("Can't run /los on yourself.")` |
| Target is an NPC (not `UnitIsPlayer`) | `MsgErr("Target must be a player/bot.")` |
| Target zones out mid-capture | Whispers stop arriving; countdown closes naturally; lines stay clickable; follow-up may fail server-side (we just send and let the bot ignore) |
| Bot sends 0 whispers (silence) | Status shows `idle — 0 lines` after countdown |
| Bot sends > 100 lines | Cap `state.lines` at 200; drop the head if exceeded. POC concern only — `los` typically returns ≤ 30 lines |
| User changes target while capturing | Sender filter still pinned to the old `state.target`; new whispers from the new target are ignored until `[pick]` or new discovery click |
| Two simultaneous bots whisper | Only the captured-target's whispers reach the list. Others go to the default chat as usual |
| `UnitClass("target")` is nil at snapshot | Skip class color; show name only |

## 13. Testing plan

Manual, in-game:

1. **Bootstrap** — `/wsh` opens frame, position persists across `/reload`.
2. **Lock/drag** — toggle lock, verify drag is suppressed when locked.
3. **No target** — click `los` with no target → error message, no whisper sent (verify with `/wardenlog debug shield on`).
4. **Self target** — target self → click `los` → error.
5. **Bot target — los** — target a bot, click `los`, verify:
   - `los` whisper visible in chat (or in WoW's whisper history)
   - whispers arrive within 5 s and populate the list
   - clicking a line sends `u [Whatever]` to that bot
6. **Bot target — spells** — same flow with `spells` / `cast`.
7. **Re-click discovery** — verify list resets.
8. **`[clear]`** — verify lines wipe, mode resets.
9. **`[P]`-flagged target** — flag a bot in Roster, retry `los` → warning, no whisper.
10. **Cross-bot whisper** — target bot A, click `los`, while capture window is open, have bot B whisper unrelated text → verify bot B's whisper does NOT appear in the list.

Automated tests are out of scope for this POC (the addon has no test harness today).

## 14. Risks & open questions

| Risk | Mitigation |
|---|---|
| Real `los` / `spells` whisper format unknown | We capture brute. Once the user runs the POC and pastes a real sample, we can refine `extractPayload` |
| 5 s window too short for large lists | Make `captureSec` configurable in Settings tab in a follow-up; the persisted DB key already supports it |
| `CHAT_MSG_WHISPER` doesn't fire for own-bot whispers on some private servers | If observed, fall back to `CHAT_MSG_WHISPER_INFORM` or scrape `DEFAULT_CHAT_FRAME` history. Defer until reproduced |
| `SendChatMessage("cast Healing Wave")` — multi-word spells | The bot accepts space-delimited names; no quoting needed per `PLAYERBOT_COMMANDS.md`. We pass the payload as-is |

## 15. Out-of-scope / follow-ups

- Settings tab integration (toggle for `captureSec`, auto-show on combat, `hideMinimapCombat`-style controls)
- Trainer / pet / tame / RTSC / RTI command surfaces
- `cast <spell> on <player>` form
- Multi-bot fan-out
- Persisted history of captured lines
- Help-tab section documenting WardenShield (add once UI shape stabilizes)

---

## Appendix A — Implementation outline (informational)

```lua
-- Shield.lua skeleton (informational — actual impl in plan)
local _, ns = ...
ns.Shield = ns.Shield or {}

local state = { ... }  -- §5
local function build() ... end
local function refreshUI() ... end
local function refreshStatus() ... end
local function refreshList() ... end
local function snapshotTarget() ... end
local function startCapture(mode) ... end
local function onWhisper(text, sender) ... end
local function clickLine(idx) ... end

-- Public API
function ns.Shield.Toggle() end
function ns.Shield.Show() end
function ns.Shield.Hide() end
function ns.Shield.Clear() end
function ns.Shield.SetLocked(v) end

-- Bootstrap
ns.Persistence.OnReady(function() build() ... end)

-- Slash
SLASH_WARDENSHIELD1 = "/wsh"
SlashCmdList["WARDENSHIELD"] = function(msg) ... end

-- Bindings glue
function WARDENSHIELD_Toggle() ns.Shield.Toggle() end
BINDING_HEADER_WARDENSHIELD = "WardenShield"
BINDING_NAME_WARDENSHIELD_TOGGLE = "Toggle WardenShield HUD"
```

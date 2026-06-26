# Warden Help Tab — Spec d'implémentation pour Claude Code

**Cible** : `UI_TabHelp.lua` (refonte intégrale) + ajouts dans `Core.lua` + un champ dans `Persistence.lua`.
**Hors périmètre** : `UI_Master.lua`, masthead/status footer partagés, tous les autres tabs, `WardenSword.lua`, `Shield.lua`, `Pocket.lua`, slash commands, keybindings.
**Référence visuelle** : `Warden Help Tab Design Doc.html`.

Ce document est un plan d'exécution séquentiel. Chaque phase est ordonnée et testable individuellement.

---

## 0. Règles globales

- **Ne touche pas** : `UI_Master.lua`, `Engine.lua`, `WardenSword.lua`, `Shield.lua`, `Pocket.lua`, `Data.lua`, `Bindings.xml`, `Warden.toc`.
- **Conserve** : la signature publique `ns.UI.Tabs.Help.BuildInto(pane)` — un seul argument, pas de retour. Conserve aussi la fonction `kbd()` locale au fichier ; on l'étend, on ne la supprime pas.
- **Tokens** : pas de nouvelle couleur. Utilise uniquement `ns.Tokens.{stone_dark, stone_mid, stone_tile, stone_rim, gold, gold_dim, gold_rim, amber, green, ink_red, text_warm}`. La couleur "parchment" (#d9cdb0) du body est obtenue via `GameFontHighlightSmall:GetTextColor()` — ne hardcode pas.
- **Boutons** : il n'y a pas de bouton secure dans le Help tab. Les rows de chapitres sont des `Frame`s avec un `SetScript("OnMouseUp", ...)` et un `EnableMouse(true)`. Pas d'`UIPanelButtonTemplate`.
- **Style de code** : copie le ton de l'existant `UI_TabHelp.lua` — commentaires en anglais court, `local function` pour les helpers internes, forward declarations quand un renderer en appelle un autre.
- **Pas de network call**. Aucun whisper, aucun event subscribe en plus de ceux du parent pane.
- **Idempotence** : `BuildInto(pane)` ne sera appelé qu'une fois (au premier `OnShow` du tab). Mais `SetChapter(id)` sera appelé plusieurs fois — il doit nettoyer les fontstrings précédents avant d'en créer de nouveaux.

---

## Phase 1 — `Core.lua` : helper `RichText`

Ajoute en fin de fichier, après les helpers existants, une nouvelle primitive pour parser les inline markers du contenu Help.

### 1.1 `ns.UI.RichText.Format(str)` → string

Parse les trois markers du contenu Help et retourne une chaîne avec les escapes Blizzard équivalents. **Renvoie une string** — pas une FontString. C'est au caller d'attacher la string à une FontString via `:SetText()`.

```lua
-- ns.UI.RichText.Format(s) -> string
--
-- Replaces three inline markers with WoW chat-color/markup escapes:
--   |kbd[F]|         -> golden keycap: "|cffffd100[F]|r"
--   |ck[/warden]|    -> warm-mono code:  "|cffffebbf/warden|r"
--   |em[the moment]| -> italic-ish dim:  "|cffd9cdb0the moment|r"  (no real italic in 3.3.5 fontstrings)
--
-- Markers do not nest. Escape a literal "|kbd[" by writing "||kbd[".
-- Unknown markers are left verbatim (no crash on typos).
```

Implémentation :

```lua
local function _esc(color, body) return "|cff" .. color .. body .. "|r" end

local _MARK_COLORS = {
    kbd = "ffd100",  -- ns.Tokens.gold
    ck  = "ffebbf",  -- ns.Tokens.text_warm
    em  = "d9cdb0",  -- parchment
}

function ns.UI.RichText.Format(s)
    if type(s) ~= "string" then return "" end
    -- Protect doubled pipes first (||kbd -> placeholder)
    s = s:gsub("||", "\1")
    s = s:gsub("|(%w+)%[([^%]]*)%]|", function(tag, body)
        local c = _MARK_COLORS[tag]
        if not c then return "|" .. tag .. "[" .. body .. "]|" end
        return _esc(c, body)
    end)
    s = s:gsub("\1", "|")
    return s
end
```

**Tests manuels** : `/run print(ns.UI.RichText.Format("Press |kbd[F]| then type |ck[/warden]|"))` doit afficher le `[F]` en doré dans le chat frame et `/warden` en warm.

### 1.2 (optionnel) `ns.UI.HairRule`

Si pas encore extrait, factorise le pattern récurrent dans le projet. Sinon, ignore cette étape.

```lua
-- ns.UI.HairRule(parent, alpha) -> Texture
--   Returns a 1px-tall WHITE8x8 texture, vertex-colored gold_rim at given alpha.
--   Caller anchors it.
function ns.UI.HairRule(parent, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    local r, g, b = unpack(ns.Tokens.rgb.gold_rim)  -- or hardcode 0.66, 0.54, 0.30
    t:SetVertexColor(r, g, b, alpha or 0.5)
    t:SetHeight(1)
    return t
end
```

---

## Phase 2 — `Persistence.lua` : nouveau champ persistant

Ajoute un seul champ dans le schema `WardenDB` :

```lua
-- In the defaults table where other UI prefs live (lookup the existing
-- WardenDB.ui or WardenDB.help block):
WardenDB.helpLastChapter = WardenDB.helpLastChapter or "intro"
```

Si `WardenDB` n'a pas encore de section dédiée aux préférences UI, **ne crée pas de sous-table**. Le champ vit au top level pour rester compat avec le pattern existant.

---

## Phase 3 — `UI_TabHelp.lua` : refonte intégrale

Travaille en place dans `UI_TabHelp.lua`. Ne crée pas de nouveau fichier. La structure cible :

```
-- =====================================================
-- Warden - UI_TabHelp.lua
-- v2 rework: two-pane chapter rail + scoped reader.
-- =====================================================

local _, ns = ...
ns.UI.Tabs      = ns.UI.Tabs      or {}
ns.UI.Tabs.Help = ns.UI.Tabs.Help or {}

-- §3.1 inline helpers (kbd, ck, em wrappers)
-- §3.2 CHAPTERS data (the big table)
-- §3.3 layout tunables
-- §3.4 renderers per node kind
-- §3.5 rail builder
-- §3.6 reader builder
-- §3.7 BuildInto(pane) entry point
```

### 3.1 Inline helpers

Garde la fonction `kbd(t)` existante (gold keycap escape). Ajoute deux compagnons :

```lua
local function kbd(t) return "|cffffd100[" .. t .. "]|r" end
local function ck(t)  return "|cffffebbf"  .. t .. "|r" end
local function em(t)  return "|cffd9cdb0"  .. t .. "|r" end
```

Ces helpers servent **uniquement à la rédaction de la data table `CHAPTERS`** (raccourci syntaxique). Le rendu réel passe par `ns.UI.RichText.Format` au moment du `:SetText()`.

### 3.2 Tunables

Place en haut du fichier, après les requires :

```lua
local PANE_W            = 720
local PANE_H            = 480
local RAIL_W            = 180
local READER_PAD_TOP    = 22
local READER_PAD_SIDE   = 28
local READER_PAD_BOT    = 18
local CHAP_H            = 22
local GROUP_H           = 26
local SCROLLBAR_W       = 4
local SCROLLBAR_PAD     = 8
local DEFAULT_CHAPTER   = "intro"
```

### 3.3 `CHAPTERS` data table

Remplace le `SECTIONS` actuel par :

```lua
local CHAPTERS = {
    -- START HERE -----------------------------------------------------
    {
        id = "intro", group = "START HERE", title = "What is Warden?",
        eyebrow = "Chapter 01 · Start here",
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
            { kind = "p",    text = "Everything else in Warden — Settings, Re-Spec, the satellite modules — builds on top of that loop." },
        },
    },
    {
        id = "first-raid", group = "START HERE", title = "Your First Raid",
        eyebrow = "Chapter 02 · Start here",
        body = {
            { kind = "lede", text = "A typical Warden session goes through four phases — build, spawn, command, refine. This walkthrough takes you end-to-end in under two minutes." },
            { kind = "h2",   text = "The four-step flow" },
            { kind = "steps", items = {
                "Type |ck[/warden]| in chat to open the main window.",
                "Click the |kbd[Bot Comp]| tab at the bottom.",
                "Pick a preset from the dropdown — or build your own from the chip tray.",
                "Press |kbd[Build]|. Warden spawns every non-player slot and whispers each spec.",
            }},
            { kind = "h2",   text = "What happens during Build" },
            { kind = "p",    text = "Bots spawn one every 0.9s — fast enough to be ready before you finish summoning your party, slow enough to never trip Blizzard's command throttle. As each bot joins, Warden whispers its planned spec on a 0.45s cadence. Any slot flagged |kbd[P]| is skipped: that's where you (or another human) will sit." },
            { kind = "h2",   text = "Commanding mid-fight" },
            { kind = "p",    text = "Open WardenSword with |ck[/ws]| for a small floating HUD that surfaces the actions you'll need during a pull — Summon, Stay, AoE, Burn, Bloodlust, role orders. The main window stays closed." },
        },
    },
    {
        id = "nav", group = "START HERE", title = "Navigation",
        eyebrow = "Chapter 03 · Start here",
        body = {
            { kind = "lede", text = "Warden's main window has six tabs along the bottom edge — click or press |kbd[1]|–|kbd[6]|. Everything else is reachable from one of three places: the minimap button, the slash commands, or the persistent footer." },
            { kind = "h2",   text = "Minimap button" },
            { kind = "bullets", items = {
                "|kbd[Left-click]| toggles the main window.",
                "|kbd[Shift-left]| opens Settings.",
                "|kbd[Middle-click]| toggles the WardenSword HUD.",
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
            }},
            { kind = "h2",   text = "Status footer" },
            { kind = "p",    text = "The bar visible at the bottom of every tab shows live raid state — current target, queue depth, tracked bots, Bloodlust on/off, plus a slash-command hint. Updates on roster/target events and every 0.5s." },
            { kind = "h2",   text = "Window size" },
            { kind = "p",    text = "Pick Small / Medium / Large / XL in Settings → Window size. Applies live. Mousewheel zoom is intentionally not bound." },
        },
    },

    -- RAID FLOW ------------------------------------------------------
    { id = "comp",     group = "RAID FLOW", title = "Bot Comp",          eyebrow = "Chapter 04 · Raid flow",
      body = { --[[ ... migrate the 13 rows of the existing "Bot Comp tab" SECTIONS entry into lede + h2/p clusters here. See §3.8 for the migration table. ]] }, },
    { id = "roster",   group = "RAID FLOW", title = "Roster & Re-Spec",  eyebrow = "Chapter 05 · Raid flow", body = {} },
    { id = "controls", group = "RAID FLOW", title = "Controls",          eyebrow = "Chapter 06 · Raid flow", body = {} },

    -- MODULES --------------------------------------------------------
    { id = "sword",  group = "MODULES", title = "WardenSword",  eyebrow = "Chapter 07 · Modules", body = {} },
    { id = "shield", group = "MODULES", title = "WardenShield", eyebrow = "Chapter 08 · Modules", body = {} },
    { id = "pocket", group = "MODULES", title = "WardenPocket", eyebrow = "Chapter 09 · Modules", body = {} },

    -- REFERENCE ------------------------------------------------------
    { id = "settings", group = "REFERENCE", title = "Settings",         eyebrow = "Chapter 10 · Reference", body = {} },
    { id = "auto",     group = "REFERENCE", title = "Auto-behaviors",   eyebrow = "Chapter 11 · Reference", body = {} },
    { id = "slash",    group = "REFERENCE", title = "Slash commands",   eyebrow = "Chapter 12 · Reference", body = {} },
    { id = "debug",    group = "REFERENCE", title = "Debug & logging",  eyebrow = "Chapter 13 · Reference · Advanced", body = {} },
}
```

**Tu dois remplir tous les `body = {}` vides** en migrant le contenu actuel ligne à ligne. Voir §3.8 pour le mapping.

### 3.4 Renderers par node kind

Sept renderers. Chacun prend `(content, y, node)` et retourne le nouveau `y` (négatif, descend depuis le top du content frame).

```lua
-- All renderers receive:
--   content : the inner Frame (child of ScrollFrame), where fontstrings are anchored
--   y       : current vertical cursor (negative, top-down)
--   node    : the AST node from CHAPTERS[i].body[j]
-- They return the new y after laying out the node + its bottom margin.

local function renderLede(content, y, node)   --[[ ... ]]   end
local function renderH2(content, y, node)     --[[ ... ]]   end
local function renderP(content, y, node)      --[[ ... ]]   end
local function renderSteps(content, y, node)  --[[ ... ]]   end
local function renderBullets(content, y, node)--[[ ... ]]   end
local function renderCmd(content, y, node)    --[[ ... ]]   end
local function renderTable(content, y, node)  --[[ ... ]]   end

local DISPATCH = {
    lede    = renderLede,
    h2      = renderH2,
    p       = renderP,
    steps   = renderSteps,
    bullets = renderBullets,
    cmd     = renderCmd,
    table   = renderTable,
}
```

#### renderLede

- FontString `GameFontHighlight`, parchment color, italic-ish via the `em` color escape if needed.
- Width = `READER_W - 2 * READER_PAD_SIDE - 10` (extra left for the rule).
- Left anchor at `READER_PAD_SIDE + 10` from content TOPLEFT.
- Draw a 2px-wide vertical Texture pinned TOPLEFT (`READER_PAD_SIDE`, y) to its height, vertex-colored `gold_rim`.
- Bottom margin: 14px.

#### renderH2

- FontString `GameFontNormal`, color `text_warm` (use `text_warm` rgb, not gold).
- 4×4 Texture (WHITE8x8) anchored 8px to its LEFT, vertex `gold` — the pip.
- Bottom margin: 6px. Top margin: 16px (so adjacent h2s get spaced).

#### renderP

- FontString `GameFontHighlightSmall` (parchment).
- Width = `READER_W - 2 * READER_PAD_SIDE`.
- `:SetWordWrap(true)`, `:SetNonSpaceWrap(false)`, `:SetJustifyH("LEFT")`.
- After `:SetText(ns.UI.RichText.Format(node.text))`, call `:SetHeight(:GetStringHeight())`.
- Bottom margin: 10px.

#### renderSteps

For each `item` in `node.items`:

- A 20×20 Frame anchored at `(READER_PAD_SIDE, y)`. Set its backdrop to `WHITE8x8` solid `stone_tile`, with a 1px `gold_rim` edge (use the existing helper or replicate inline).
- A FontString inside, centered, `GameFontNormal`, text `tostring(i)`, color `gold`.
- A FontString to the RIGHT of the pastille (offset +32 from `READER_PAD_SIDE`), width `READER_W - READER_PAD_SIDE * 2 - 32`, `GameFontHighlightSmall` parchment, text wrapped.
- Row height = `max(20, fs:GetStringHeight()) + 8`.
- Bottom margin (whole list): 14px.

#### renderBullets

- For each `item`, a FontString at offset `+16` from `READER_PAD_SIDE`, width `READER_W - READER_PAD_SIDE * 2 - 16`.
- A 4×1 Texture pinned 4px from left, vertex `gold_rim`, vertically centered on the first line.
- Per-row bottom margin 3px. List bottom margin 14px.

#### renderCmd

- Container Frame, full content width minus side padding, backdrop `stone_mid` + 1px edge `stone_rim`, 2px LEFTBORDER `gold_rim` (separate Texture).
- FontString `GameFontNormalSmall`, color `text_warm`, monospace-feeling via `NumberFont_Outline_Med`? No — Blizzard 3.3.5 doesn't have a real monospace font object. Use `GameFontNormalSmall` and accept that mono looks like proportional; the box + accent is what reads as "code".
- Padding 8/12 inside.
- Bottom margin: 14px.

#### renderTable

For each `{cmd, desc}` row in `node.rows`:

- Two FontStrings on the same y:
  - Left: `GameFontNormalSmall`, color `gold`, anchored at `READER_PAD_SIDE`, width = 36% of inner width. Mono feel via `:SetText("|cffffd100" .. cmd .. "|r")` — no font change needed.
  - Right: `GameFontHighlightSmall`, parchment, anchored 14px right of the left col, width = remaining.
  - Apply `ns.UI.RichText.Format` to the right one.
- Row height = `max(left:GetStringHeight(), right:GetStringHeight()) + 6`.
- A 1px hair-rule `stone_rim` 0.4 alpha below each row.
- Bottom margin (whole table): 14px.

### 3.5 Rail builder

```lua
local function buildRail(parent)
    local rail = CreateFrame("Frame", "WardenHelpRail", parent)
    rail:SetSize(RAIL_W, PANE_H - 2)  -- 2 for top/bottom border
    rail:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    -- bg fill
    local bg = rail:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(unpack(ns.Tokens.rgb.stone_mid)) -- or hardcoded 0.10, 0.08, 0.05
    bg:SetAllPoints()

    -- right border
    local border = rail:CreateTexture(nil, "BORDER")
    border:SetTexture("Interface\\Buttons\\WHITE8x8")
    border:SetVertexColor(0.23, 0.18, 0.13, 1) -- stone_rim
    border:SetWidth(1)
    border:SetPoint("TOPRIGHT", rail, "TOPRIGHT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 0)

    -- eyebrow
    local eye = rail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eye:SetPoint("TOPLEFT", rail, "TOPLEFT", 14, -12)
    eye:SetText("CONTENTS")
    eye:SetTextColor(0.66, 0.54, 0.30, 1) -- gold_rim

    -- chapters scrollframe (inside the rail)
    local sf = CreateFrame("ScrollFrame", "WardenHelpRailScroll", rail, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", rail, "TOPLEFT", 6, -32)
    sf:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -6, 8)

    -- hide arrow chrome, narrow track (same trick as the current Help scrollbar)
    local sb = _G["WardenHelpRailScrollScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetWidth(6)
    end

    local list = CreateFrame("Frame", nil, sf)
    list:SetSize(RAIL_W - 14, 10)
    sf:SetScrollChild(list)

    -- materialize CHAPTERS
    local y = 0
    local currentGroup = nil
    local rowFrames = {}
    for i, ch in ipairs(CHAPTERS) do
        if ch.group ~= currentGroup then
            currentGroup = ch.group
            local gh = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            gh:SetPoint("TOPLEFT", list, "TOPLEFT", 8, y - 8)
            gh:SetText(ch.group)
            gh:SetTextColor(0.66, 0.54, 0.30, 1)
            y = y - GROUP_H
        end

        local row = CreateFrame("Frame", nil, list)
        row:SetSize(RAIL_W - 14, CHAP_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, y)
        row:EnableMouse(true)
        row.id = ch.id
        rowFrames[ch.id] = row

        -- bg (hidden until active/hover)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.bg:SetVertexColor(0.16, 0.13, 0.09, 1) -- stone_tile
        row.bg:SetAllPoints()
        row.bg:Hide()

        -- left accent (hidden until active)
        row.accent = row:CreateTexture(nil, "ARTWORK")
        row.accent:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.accent:SetVertexColor(1.00, 0.82, 0.00, 1) -- gold
        row.accent:SetWidth(2)
        row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.accent:Hide()

        -- ix number
        row.ix = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.ix:SetPoint("LEFT", row, "LEFT", 10, 0)
        row.ix:SetWidth(16); row.ix:SetJustifyH("RIGHT")
        row.ix:SetText(string.format("%02d", i - _groupOffsetFor(ch.group)))  -- §3.5.1
        row.ix:SetTextColor(0.23, 0.18, 0.13, 1)  -- stone_rim — almost invisible until active

        -- title
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.title:SetPoint("LEFT", row.ix, "RIGHT", 8, 0)
        row.title:SetWidth(RAIL_W - 14 - 32 - 8)
        row.title:SetJustifyH("LEFT")
        row.title:SetText(ch.title)
        row.title:SetTextColor(0.72, 0.58, 0.21, 1) -- gold_dim

        row:SetScript("OnEnter", function(s) if not s._active then s.title:SetTextColor(1.0, 0.92, 0.75, 1) end end)
        row:SetScript("OnLeave", function(s) if not s._active then s.title:SetTextColor(0.72, 0.58, 0.21, 1) end end)
        row:SetScript("OnMouseUp", function(s, btn)
            if btn == "LeftButton" then ns.UI.Tabs.Help.SetChapter(s.id) end
        end)

        y = y - CHAP_H
    end

    list:SetHeight(math.max(10, -y + 8))
    rail._rowFrames = rowFrames

    return rail, rowFrames
end
```

#### 3.5.1 `_groupOffsetFor`

The ix numbers are **global 01..13**, not per-group. So actually drop `_groupOffsetFor` and just use `i` as the index. The "01..03 under START HERE, 04..06 under RAID FLOW, ..." pattern emerges naturally because chapters are ordered globally.

Replace the `string.format` line with:

```lua
row.ix:SetText(string.format("%02d", i))
```

### 3.6 Reader builder + `SetChapter(id)`

```lua
local _reader, _readerContent, _readerScroll
local _rowFrames -- captured from buildRail

local function buildReader(parent)
    local reader = CreateFrame("Frame", "WardenHelpReader", parent)
    reader:SetSize(PANE_W - RAIL_W, PANE_H - 2)
    reader:SetPoint("TOPLEFT", parent, "TOPLEFT", RAIL_W, 0)

    -- bg (slightly darker than rail, matches stone_dark)
    local bg = reader:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.055, 0.043, 0.031, 1) -- stone_dark
    bg:SetAllPoints()

    local sf = CreateFrame("ScrollFrame", "WardenHelpReaderScroll", reader, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", reader, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", reader, "BOTTOMRIGHT", -SCROLLBAR_PAD, 0)

    local sb = _G["WardenHelpReaderScrollScrollBar"]
    if sb then
        if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
        if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end
        sb:SetWidth(4)
    end

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(PANE_W - RAIL_W - SCROLLBAR_PAD - SCROLLBAR_W, 10)
    sf:SetScrollChild(content)

    _reader, _readerContent, _readerScroll = reader, content, sf
    return reader
end

function ns.UI.Tabs.Help.SetChapter(id)
    local ch
    for _, c in ipairs(CHAPTERS) do if c.id == id then ch = c break end end
    if not ch then return end

    -- 1. wipe content : every Region created so far in _readerContent goes back to pool
    --    Lua 3.3.5 doesn't have a region pool by default — we keep a per-build table
    --    of created regions and Hide() + ClearAllPoints them. Cheaper than recreating
    --    is fine because chapter switches are user-paced.
    if _readerContent._spawned then
        for _, r in ipairs(_readerContent._spawned) do
            r:Hide(); r:ClearAllPoints()
        end
    end
    _readerContent._spawned = {}

    -- 2. render header (eyebrow + h1 + gold rule)
    local y = -READER_PAD_TOP

    local eye = _readerContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    eye:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
    eye:SetText(ch.eyebrow or "")
    eye:SetTextColor(0.66, 0.54, 0.30, 1)
    table.insert(_readerContent._spawned, eye)
    y = y - 14

    local h1 = _readerContent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    h1:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
    h1:SetText(ch.title)
    h1:SetTextColor(1.00, 0.82, 0.00, 1)
    table.insert(_readerContent._spawned, h1)
    y = y - 28

    local rule = _readerContent:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8x8")
    rule:SetVertexColor(0.66, 0.54, 0.30, 0.5)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", _readerContent, "TOPLEFT", READER_PAD_SIDE, y)
    rule:SetPoint("RIGHT", _readerContent, "RIGHT", -READER_PAD_SIDE, 0)
    table.insert(_readerContent._spawned, rule)
    y = y - 14

    -- 3. dispatch each body node
    for _, node in ipairs(ch.body or {}) do
        local fn = DISPATCH[node.kind]
        if fn then y = fn(_readerContent, y, node) end
        -- unknown kinds silently skipped — robustness over crash
    end

    _readerContent:SetHeight(math.max(10, -y + READER_PAD_BOT))
    _readerScroll:SetVerticalScroll(0) -- always reset to top on chapter switch

    -- 4. repaint rail rows
    for rid, row in pairs(_rowFrames) do
        local on = (rid == id)
        row._active = on
        row.bg:SetShown(on)
        row.accent:SetShown(on)
        row.title:SetTextColor(on and 1.00 or 0.72, on and 0.82 or 0.58, on and 0.00 or 0.21, 1)
        row.ix:SetTextColor(on and 0.66 or 0.23, on and 0.54 or 0.18, on and 0.30 or 0.13, 1)
    end

    -- 5. persist
    if WardenDB then WardenDB.helpLastChapter = id end
end
```

### 3.7 `BuildInto(pane)`

Réécriture complète. Signature inchangée.

```lua
function ns.UI.Tabs.Help.BuildInto(pane)
    pane:SetSize(PANE_W, PANE_H)  -- if the pane is sized by caller, skip this
    local rail, rowFrames = buildRail(pane)
    _rowFrames = rowFrames
    buildReader(pane)

    -- restore last visited chapter, fallback to default
    local startId = (WardenDB and WardenDB.helpLastChapter) or DEFAULT_CHAPTER
    -- sanity check : the id must exist in CHAPTERS
    local found
    for _, c in ipairs(CHAPTERS) do if c.id == startId then found = true break end end
    if not found then startId = DEFAULT_CHAPTER end

    ns.UI.Tabs.Help.SetChapter(startId)
end
```

### 3.8 Migration du contenu actuel → AST

Reprends chaque entry de l'ancien `SECTIONS[i].items[j] = {term, desc}` et redistribue-la dans le chapitre cible. Règles d'or :

- Une row dont le `term` est **une commande** (commence par `[/`) → entry dans une `table` node du chapitre `slash` ou du chapitre concerné (ex : la table de commandes `/ws` va dans le chapitre `sword`, pas dans `slash`).
- Une row dont le `term` est **un nom de widget ou de feature** (ex : "Player flag [P]", "Coverage", "Build") → une h2 + p séquence à l'intérieur du chapitre cible.
- Quand 2-3 rows consécutives décrivent la même feature (ex : Build, then `save/load/delete`, then `import/export`, then `clear/cleanup`) → garde un seul h2 ("Saving and sharing") et fusionne les desc en 2-3 paragraphes.
- Quand une desc contient une énumération (« Movement / Strategy / Marks ») → casse-la en `bullets` ou en plusieurs h2.

#### Mapping détaillé

| Source `SECTIONS` entry         | Destination chapitre | Forme cible |
|---|---|---|
| Navigation (les 6 rows)         | `nav`     | lede + 3 h2 (Minimap / Slash / Footer) + bullets/table |
| Spec tab (7 rows)               | éclaté    | "Target card", "Prev target", "Spec tiles", "Click a tile" → chapitre `comp` h2 "Speccing a bot". "History popup" → `comp` h2 "Target history". "Autogear / Buffs" → `comp` h2 "Quick raid buffs". |
| Controls tab (7 rows)           | `controls`| lede + 1 h2 par groupe (Movement, Strategy, Marks, Role commands, BL toggle, Danger zone, Summon by class) |
| WardenSword (14 rows)           | `sword`   | lede + h2 "Open/close", "Movement", "Strategy", "Role matrix", "Bloodlust", "Settings" + table de slash commands `/ws *` |
| Bot Comp (13 rows)              | `comp`    | lede + h2 "What is a comp", "Sizes & grid", "Chip tray", "Slot detail", "Player slots & [P]", "Coverage", "Build", "Save / load / delete", "Import / export", "Presets" |
| Roster (7 rows)                 | `roster`  | lede + h2 "Filter", "Row layout", "Player flag [P]", "Provides chips", "Re-Spec", "Bulk actions" |
| Settings (8 rows)               | `settings`| lede + h2 "General", "WardenSword panel", "Session stats", "Maintenance" |
| Auto-behavior (6 rows)          | `auto`    | lede + h2 "Paladin Righteous Fury", "Buff limits", "GUID tracking", "Whisper cadence", "Bloodlust default", "Player guard" |
| Slash commands (5 rows)         | `slash`   | lede + 1 single `table` node |
| Debug & logging (16 rows)       | `debug`   | lede + h2 "Two-tier model", "Typical workflow" (steps), "Log viewer commands" (table), "Debug categories" (table), "Reading the log file" (p), "Chat echo format" (p) |

#### Contenus nouveaux à rédiger (pas dans `SECTIONS` actuel)

- `intro` chapter : le lede + bullets + h2 "four-phase flow" + 2 p. Voir §3.3 pour le texte exact.
- `first-raid` chapter : voir §3.3.
- `shield` chapter : extrais le texte du brouillon ChatGPT fourni avec le projet (sections "WardenShield — Spell Discovery & Interaction"). Adapte au format AST.
- `pocket` chapter : extrais le texte du brouillon ChatGPT (sections "WardenPocket — Automated WTS Trading"). Adapte.

---

## Phase 4 — Tests manuels

Après chaque sous-phase, `/reload` puis valide :

### 4.1 Après Phase 1 (RichText)
- `/run print(ns.UI.RichText.Format("Hit |kbd[F]| then |ck[/warden]|"))` affiche le `[F]` en jaune gold et `/warden` en warm cream.

### 4.2 Après Phase 3 (rendu)
1. Ouvre `/warden`, va sur Help. Vérifie :
   - Rail à gauche, 13 rows + 4 group heads.
   - Reader à droite affiche `01 What is Warden` par défaut.
2. Clic sur `02 Your First Raid` dans le rail → reader switch, scroll-to-top, rail row `02` passe en gold + bg stone_tile + accent gauche.
3. `/reload`. Le tab Help s'ouvre toujours sur `02 Your First Raid` (persist OK).
4. Va sur `13 Debug & logging`. Vérifie que la `table` de commandes affiche bien command gold mono à gauche, desc parchment à droite, hair-rule entre les rows.
5. Va sur un chapitre long (e.g. `comp` après migration). Vérifie que le scroll vertical du reader fonctionne ; le rail reste statique.
6. Survol d'une row du rail non-active → titre passe en `text_warm`. Quitte → revient en `gold_dim`.
7. Clic milieu/droit sur une row du rail → no-op (pas de crash).

### 4.3 Régression
- Les 5 autres tabs (Spec, Controls, Comp, Roster, Settings) doivent être inchangés.
- La masthead `WARDEN raid commander · v…` était dans l'ancien Help tab ; elle disparait avec la refonte — c'est attendu. Si tu veux la garder, place-la dans le reader uniquement pour le chapitre `intro` (h2 + version line).
- La status footer (`no target · BL OFF · Esc to close`) doit rester intacte sur le tab Help.

---

## Phase 5 — Cleanup

- Supprime la table `SECTIONS` et les constantes `PAD_L`, `PAD_R`, `KEY_W`, `GUTTER` du fichier — devenues mortes.
- Supprime les `setTermFont`, `setDescFont`, `setSectionFont` locaux — devenus morts.
- Garde un commentaire `-- v2 rework, May 2026` en tête de fichier.

---

## Annexe A — Couleurs RGB (si `ns.Tokens.rgb` n'existe pas)

Si le projet n'expose pas déjà les tokens en triplets RGB normalisés, ajoute-les dans `Core.lua` au moment de la phase 1 :

```lua
ns.Tokens.rgb = ns.Tokens.rgb or {
    stone_dark = { 0.055, 0.043, 0.031 },
    stone_mid  = { 0.102, 0.078, 0.051 },
    stone_tile = { 0.165, 0.125, 0.086 },
    stone_rim  = { 0.227, 0.184, 0.133 },
    gold       = { 1.000, 0.820, 0.000 },
    gold_dim   = { 0.722, 0.584, 0.212 },
    gold_rim   = { 0.659, 0.541, 0.298 },
    amber      = { 1.000, 0.604, 0.000 },
    green      = { 0.180, 0.800, 0.251 },
    ink_red    = { 0.878, 0.290, 0.227 },
    text_warm  = { 1.000, 0.922, 0.749 },
    parchment  = { 0.851, 0.804, 0.690 },
}
```

---

## Annexe B — Estimation effort

| Phase | LOC estimé | Effort |
|---|---|---|
| 1. RichText | ~30 | 15 min |
| 2. Persistence | ~3 | 2 min |
| 3.1–3.2 setup + CHAPTERS scaffolding | ~50 | 20 min |
| 3.3 fill CHAPTERS bodies (migration) | ~400 | 90 min — gros morceau |
| 3.4 renderers | ~180 | 45 min |
| 3.5–3.7 rail + reader + SetChapter | ~150 | 45 min |
| 4. tests | — | 30 min |
| 5. cleanup | ~−40 | 5 min |
| **Total** | **~770 LOC net** | **~4h** |

Le fichier final pèse ~600 lignes (+ ~270 LOC contenu CHAPTERS) contre 325 actuellement. La majorité du delta est de la donnée (les body AST), pas du code.

---

## Annexe C — Décisions explicites

| Question | Décision |
|---|---|
| H3 dans le contenu ? | Non — flatten au montage. Deux niveaux max (H1 chapitre, H2 sous-section). |
| Search bar dans le rail ? | Non en v1. Le rail tient en hauteur, pas de scroll fastidieux. À reconsidérer si on dépasse 20 chapitres. |
| Bookmark ou "back" ? | Non. Le dernier chapitre est persistant, ce qui couvre 80 % du besoin. |
| Police monospace pour les commandes ? | Non — Blizzard 3.3.5 n'expose pas de monospace propre dans les FontStrings sans CreateFont custom. On utilise le color escape gold pour faire passer la commande pour du code. |
| Keybindings Up/Down dans le rail ? | Plus tard. Pas en v1 — risque de conflit avec d'autres tabs. |
| Scroll wheel sur le rail vs reader ? | Chacun a son ScrollFrame. La souris au-dessus du rail scroll le rail, au-dessus du reader scroll le reader. Comportement Blizzard par défaut, rien à coder. |
| Animation transition entre chapitres ? | Aucune. Switch instantané. |

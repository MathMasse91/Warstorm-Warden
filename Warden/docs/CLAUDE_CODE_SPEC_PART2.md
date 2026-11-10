# Warden Shield — Spec d'implémentation (Part 2)

**Suite de** : `CLAUDE_CODE_SPEC.md`
**Référence visuelle** : `Warden Design Doc.html`

Ce document continue à partir de la phase 2.4. Les règles globales de la part 1 s'appliquent toujours (pas de nouveaux tokens, pas de nouvelles tiers de boutons, conservation de l'API publique et du schéma `WardenDB.shield`).

---

## Phase 2 (suite) — `Shield.lua` : refonte

### 2.4 Layout reconstruction — ordre du `build()`

Réécris la fonction `build()` pour empiler les rangées dans cet ordre exact, du haut vers le bas :

```
[ HEADER         ] 22
[ BANNER ARMED   ] 16  -- conditionnel (state.captureUntil > GetTime())
[ TARGET ANCHOR  ] 32  -- nom + pick / locked-state ou hint
[ RULE 1px       ]  1
[ ACTION ROW     ] 22  -- los / spells / clear
[ MODE SEGMENTED ] 22  -- ns.UI.Segmented
[ CAST-ON CHIP   ] 22  -- conditionnel (state.actionMode == "caston")
[ FILTER EDITBOX ] 18  -- conditionnel (#displayItems > FILTER_THRESHOLD)
[ LIST           ] variable
[ FOOTER         ] 22
```

Le total varie de **~338 px (idle, no caston, no filter)** à **~378 px (armed + caston + filter visible)**.

**Méthode** : ne calcule plus la hauteur du frame une fois pour toutes en haut de `build()`. Tu introduis une fonction `relayout()` qui :
1. Place chaque rangée par `SetPoint(TOPLEFT, prevRow, BOTTOMLEFT, 0, -gap)` avec `gap=0` pour banner/rule, `gap=GAP` ailleurs.
2. Cache (`row:Hide()`) les rangées conditionnelles si leur condition est fausse.
3. Recalcule `f:SetHeight(...)` en sommant uniquement les rangées visibles.
4. Le scroll list (`scrollFrame`) prend la hauteur restante : `LIST_H_dynamic = f:GetHeight() - sumOfFixedRows`.

`relayout()` est appelée :
- une fois en fin de `build()`,
- à chaque changement de `actionMode` (peut afficher/cacher cast-on chip),
- à chaque `refreshList()` après calcul de `#state.displayItems` (peut afficher/cacher filter row),
- à `startCapture()` / fin de countdown (banner apparaît/disparaît).

### 2.5 Header — inchangé

Garde `buildHeader()` tel quel. Aucune modification.

### 2.6 Armed banner

Juste sous le header, ajoute :

```lua
state.bannerArmed = ns.UI.Banner.Create(f, "amber")
state.bannerArmed:SetPoint("TOPLEFT",  f.header, "BOTTOMLEFT",  0, 0)
state.bannerArmed:SetPoint("TOPRIGHT", f.header, "BOTTOMRIGHT", 0, 0)
state.bannerArmed:Hide()  -- masqué par défaut
```

Dans `refreshStatus()` (qui devient principalement responsable du banner ET du status idle text) :

```lua
local capturing = (state.captureUntil > 0 and state.captureUntil > GetTime())
if capturing then
    local left = state.captureUntil - GetTime()
    state.bannerArmed:SetText("LISTENING",
        string.format("%.1fs \194\183 %d line%s", left, #state.lines, #state.lines == 1 and "" or "s"))
    state.bannerArmed:SetPulse(true)
    state.bannerArmed:Show()
    -- masque le status idle (la banner remplace l'info)
    if state.statusLbl then state.statusLbl:Hide() end
else
    state.bannerArmed:Hide()
    if state.statusLbl then
        state.statusLbl:Show()
        state.statusLbl:SetText(string.format("idle \194\183 %d line%s",
            #state.lines, #state.lines == 1 and "" or "s"))
    end
end
```

Le `STATUS_H` reste pour le idle state mais devient invisible quand capturing — c'est la banner qui rend l'info.

### 2.7 Target anchor (TARGET_H = 32)

La rangée target passe à 2 lignes :

```
+- 32 -------------------------------+
| <Name in class color, 13px bold>  [pick] |
| ◉ locked   ou   target a bot, ... |
+------------------------------------+
```

Ligne 1 (gauche) :
- `FontString` `GameFontNormal` (~13 px), `SetTextColor` via `ns.ColorClass(classToken, name)` si target locked, sinon `text_warm`. Si pas de target : texte muet `no target` color `gold_dim`.
- `[pick]` button `ns.UI.Button.stone` 48×18, anchoré à droite.

Ligne 2 (gauche, sous ligne 1) :
- `FontString` `GameFontDisableSmall`, color :
  - **locked** : gold (`◉ locked`, tracking 0.10em uppercase)
  - **live target visible** : gold_dim (`LIVE — click pick to lock`)
  - **no target** : muted gray (`target a bot, then click pick`)

Refresh logique dans `refreshTargetLine()` :

```lua
local function refreshTargetLine()
    -- ligne 1
    if state.target and state.target ~= "" then
        state.targetLbl:SetText(ns.ColorClass(state.targetClass or "", state.target))
        state.subtargetLbl:SetText("LIVE — click pick to lock")  -- jamais visible si locked
        state.lockStateLbl:SetText("◉ LOCKED")
        state.lockStateLbl:SetTextColor(unpack(ns.Tokens.gold))
        state.subtargetLbl:Hide()
        state.lockStateLbl:Show()
    elseif UnitExists("target") and UnitIsPlayer("target") then
        local name = UnitName("target") or "?"
        local _, classTok = UnitClass("target")
        state.targetLbl:SetText(ns.ColorClass(classTok or "", name))
        state.subtargetLbl:SetText("live — click pick to lock")
        state.subtargetLbl:Show()
        state.lockStateLbl:Hide()
    else
        state.targetLbl:SetText("|cff706552no target|r")
        state.subtargetLbl:SetText("target a bot, then click pick")
        state.subtargetLbl:Show()
        state.lockStateLbl:Hide()
    end
end
```

### 2.8 Action row

Inchangée fonctionnellement. Une seule modification : le bouton actif `[los]` ou `[spells]` (celui qui matche `state.mode` pendant capture) passe son rim `gold_rim` ET son label color `gold` (pas seulement le rim — le contraste 1px ne suffit pas).

Dans `refreshModeRims()` :

```lua
local function paint(btn, on)
    if not btn or not btn.SetBackdropBorderColor then return end
    local rim   = on and GOLD_RIM or STONE_RIM
    local label = on and ns.Tokens.gold or ns.Tokens.gold_dim
    btn:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
    if btn._tokLbl then
        local fs = btn:GetFontString()
        if fs then fs:SetTextColor(label[1], label[2], label[3], 1) end
    end
end
```

### 2.9 Mode segmented control

Remplace les 5 boutons et `state.modeButtons` par :

```lua
local items = {
    { key="cast",     label="cast",  tooltip={"Cast",     "Click any captured spell line to whisper `cast <name>`. los lines stay `u [obj]`."} },
    { key="caston",   label="on Y",  tooltip={"Cast on Y","Click a unit frame to capture the cast target, then click a spell line."} },
    { key="selfcast", label="on me", tooltip={"Cast on me","Click a spell line to whisper `cast <spell> on <YourName>`."} },
    { key="ban",      label="ban",   tooltip={"Ban",      "Click a spell line to whisper `ss +<id>` and add it to the exclude list."} },
    { key="unban",    label="unban", tooltip={"Unban",    "Click a spell line to whisper `ss -<id>` and remove from exclude list."} },
}
state.segMode = ns.UI.Segmented.Create(modeRow, items, function(key)
    state.actionMode = key
    if key ~= "caston" then state.castOnTarget = nil end
    refreshActionMode()
    relayout()  -- caston chip peut apparaître/disparaître
    if ns.DebugF then ns.DebugF("shield", "actionMode=%s", key) end
end)
state.segMode:SetActive("cast")
state.segMode:SetPoint("TOPLEFT",  modeRow, "TOPLEFT",  PAD, 0)
state.segMode:SetPoint("TOPRIGHT", modeRow, "TOPRIGHT", -PAD, 0)
```

`refreshActionMode()` se réduit à : `state.segMode:SetActive(state.actionMode)`.

### 2.10 Cast-on chip (nouvelle rangée)

Une rangée dédiée 22 px qui n'apparaît que si `state.actionMode == "caston"`.

```lua
-- Container
state.castOnChip = CreateFrame("Frame", nil, f)
state.castOnChip:SetHeight(CAST_ON_H)
state.castOnChip:Hide()

-- Backdrop dynamique : dashed quand vide, plein quand peuplé
state.castOnChip:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
})

-- FontString : "click a unit frame to set cast target" / "CAST ON <Name>"
state.castOnChipLbl = state.castOnChip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
state.castOnChipLbl:SetPoint("CENTER", state.castOnChip, "CENTER", 0, 0)
```

Refresh dans `refreshActionMode()` après `SetActive` :

```lua
if state.actionMode == "caston" then
    state.castOnChip:Show()
    if state.castOnTarget and state.castOnTarget ~= "" then
        -- peuplé
        state.castOnChip:SetBackdropColor(0.10, 0.08, 0.04, 0.4)
        state.castOnChip:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 1)
        local _, c = UnitClass(state.castOnTarget)  -- best-effort, peut être nil
        state.castOnChipLbl:SetText(string.format("|cffb89536CAST ON|r  %s",
            ns.ColorClass(c or "", state.castOnTarget)))
    else
        -- vide → instruction
        state.castOnChip:SetBackdropColor(0, 0, 0, 0)
        state.castOnChip:SetBackdropBorderColor(GOLD_RIM[1], GOLD_RIM[2], GOLD_RIM[3], 0.6)
        state.castOnChipLbl:SetText("|cffb89536click a unit frame to set cast target|r")
    end
else
    state.castOnChip:Hide()
end
```

Click sur le chip lui-même : reset `state.castOnTarget = nil` + `refreshActionMode()`. Implémente via `state.castOnChip:EnableMouse(true)` + `SetScript("OnMouseUp", ...)`.

### 2.11 Filter editbox (conditionnel)

Rangée 18 px qui n'apparaît que si `#state.displayItems > FILTER_THRESHOLD`.

```lua
state.filterRow = CreateFrame("Frame", nil, f)
state.filterRow:SetHeight(FILTER_H)
state.filterRow:Hide()

local fb = CreateFrame("EditBox", "WardenShieldFilter", state.filterRow, "InputBoxTemplate")
fb:SetPoint("LEFT",  state.filterRow, "LEFT",  PAD + 10, 0)  -- 10 = compense le bord InputBox
fb:SetPoint("RIGHT", state.filterRow, "RIGHT", -PAD, 0)
fb:SetHeight(16)
fb:SetAutoFocus(false)
fb:SetMaxLetters(40)
fb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
fb:SetScript("OnEnterPressed",  function(s) s:ClearFocus() end)
fb:SetScript("OnTextChanged",   function(s)
    state.filter = (s:GetText() or ""):lower()
    refreshList()
end)
state.filterBox = fb

-- Placeholder muted "filter"  -- via une FontString secondaire visible quand vide
local ph = state.filterRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ph:SetPoint("LEFT", fb, "LEFT", 4, 0)
ph:SetText("filter")
state.filterPlaceholder = ph
fb:HookScript("OnTextChanged", function(s)
    if s:GetText() == "" then ph:Show() else ph:Hide() end
end)
fb:HookScript("OnEditFocusGained", function() ph:Hide() end)
fb:HookScript("OnEditFocusLost",   function(s) if s:GetText() == "" then ph:Show() end end)
```

Wipe : `state.filter = ""` dans `ns.Shield.Clear()` et au switch entre los/spells (`startCapture`).

### 2.12 List — `buildDisplayItems` réécriture

Le retour devient une liste mixte avec 3 `kind` :

```lua
-- item shapes:
-- { kind = "section", label = "Spells", count = 28 }
-- { kind = "line",    line = <ref to state.lines entry>, banned = bool, fromTag = nil|"Patchs" }
-- { kind = "excl",    id = 25898, name = "Greater Blessing of Kings" }
```

Logique de build :

```lua
local function buildDisplayItems()
    local items = {}

    -- 1) Vue exclusions : ne renvoie que des items "excl", non triés autrement
    if state.viewExclusions then
        local s = shieldDB()
        if s and type(s.exclusions) == "table" then
            for _, e in ipairs(s.exclusions) do
                if state.filter == "" or (e.name or ""):lower():find(state.filter, 1, true) then
                    table.insert(items, { kind = "excl", id = e.id, name = e.name })
                end
            end
        end
        return items
    end

    -- 2) Pré-calculs : set des spells bannis, détection multi-bot
    state.bannedSet = {}
    do
        local s = shieldDB()
        if s and type(s.exclusions) == "table" then
            for _, e in ipairs(s.exclusions) do state.bannedSet[e.id] = true end
        end
    end
    local fromCount = {}
    for _, l in ipairs(state.lines) do fromCount[l.from or "?"] = true end
    local distinct = 0; for _ in pairs(fromCount) do distinct = distinct + 1 end
    state.multiBot = distinct > 1

    -- 3) Filter pass : copie state.lines vers liste filtrée + bucket par mode
    local buckets = { spells = {}, los = {}, other = {} }
    for _, line in ipairs(state.lines) do
        local payload = line.payload or ""
        if payload ~= "" and not isSeparator(payload) then
            local skip = false
            -- hide gray : mode-aware (Q3 du brief)
            if state.hideGray
               and state.actionMode ~= "ban" and state.actionMode ~= "unban" then
                local rank = extractRank(line.raw or "")
                if rank == "808080" then skip = true end
            end
            -- filter texte
            if not skip and state.filter ~= "" then
                if not payload:lower():find(state.filter, 1, true) then skip = true end
            end
            if not skip then
                local mode = line.mode or "other"
                local bucket = buckets[mode] or buckets.other
                table.insert(bucket, {
                    kind   = "line",
                    line   = line,
                    banned = state.bannedSet[extractSpellId(line.raw or "") or -1] or false,
                    fromTag = state.multiBot and line.from or nil,
                })
            end
        end
    end

    -- 4) Sort alpha intra-bucket
    local function sortLines(t)
        table.sort(t, function(a, b)
            return (a.line.payload or ""):lower() < (b.line.payload or ""):lower()
        end)
    end
    sortLines(buckets.spells); sortLines(buckets.los); sortLines(buckets.other)

    -- 5) Concat avec section headers
    local order = { {key="spells", label="Spells"}, {key="los", label="Game objects"}, {key="other", label="Other"} }
    for _, s in ipairs(order) do
        local b = buckets[s.key]
        if #b > 0 then
            table.insert(items, { kind = "section", label = s.label, count = #b })
            for _, it in ipairs(b) do table.insert(items, it) end
        end
    end

    return items
end
```

### 2.13 List — `refreshList` rendering branche par `kind`

```lua
local function refreshList()
    local parent = state.scrollChild
    if not parent then return end
    state.displayItems = buildDisplayItems()
    local items = state.displayItems
    local y = -2
    for i = 1, math.max(#items, #state.rowFrames) do
        local item = items[i]
        local row  = state.rowFrames[i]
        if item then
            row = row or ensureRow(i, parent)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   2, y)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, y)

            if item.kind == "section" then
                renderSection(row, item)
                y = y - (SECTION_HDR_H + 2)
            elseif item.kind == "excl" then
                renderExclusion(row, item)
                y = y - (ROW_H + 2)
            else
                renderLine(row, item)
                y = y - (ROW_H + 2)
            end
            row.lineIdx = i
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    parent:SetHeight(math.max(LIST_H, -y + 4))
    refreshStatus()
    refreshExclusionsCounter()
    relayout()  -- peut faire apparaître/disparaître le filter
end
```

Sous-helpers à ajouter :

- `renderSection(row, item)` : la row devient non-cliquable visuellement (rim transparent), text = `item.label` uppercase tracked, gauche, color `gold_rim`. Compte à droite, color `gold_dim`. Hauteur `SECTION_HDR_H` (override via row:SetHeight).
- `renderLine(row, item)` :
  - `item.banned` true → text strike-through simulé en préfixant `|cff6a4a45` + ajout d'une petite Texture rouge 6×6 ronde à gauche du label (anchor LEFT, +1px). Pour le strike-through 3.3.5 ne supporte pas natively : on utilise une `Texture` 1px line `WHITE8x8` horizontale centrée verticalement sur le label, alpha 0.6, color `ink_red`. Stocke-la sur `row.strikeTex` et toggle `Show/Hide` par item.
  - sinon text normal `> <line.raw>` color `text_warm`.
  - `item.fromTag` (multi-bot) → petit tag à droite 9 px font, `gold_dim`, format `· <BotName>`.
- `renderExclusion(row, item)` : inchangé par rapport à l'existant (`[banned] <name>  (id <ID>)` en rouge).

### 2.14 Footer

Trois éléments avec spacing serré, hauteur 22 :

```
[ ▤ hide gray ]  [ exclusions · N ]                           [ reset all ]
```

- `[ ▤ ]` : icon-only stone button 22×22, gold quand `state.hideGray` true. Tooltip `Hide gray spells`.
- `[ exclusions · N ]` : stone button width=auto (~96), gold quand `state.viewExclusions`.
- `[ reset all ]` : stone button 64, color `ink_red` quand `#exclusions > 0` (visuellement destructive), color `gold_dim` quand vide (disabled-ish). Click toujours actif si target locked.

Conditionne `reset all` : si `#exclusions == 0` ET pas de target locked, fait `:Disable()` (helper `ns.UI.Button` doit déjà le supporter — sinon SetEnabled false + alpha 0.4).

### 2.15 Listener — petite addition

Quand un whisper arrive ET `#state.displayItems` était <= `FILTER_THRESHOLD` avant ET passe au-dessus après, le filter row doit apparaître. C'est déjà couvert par `relayout()` appelée depuis `refreshList()` ; vérifie que `refreshList()` est bien appelée après chaque whisper accepté (c'est le cas dans `listenerFrame:SetScript("OnEvent", ...)`).

### 2.16 `Clear()` — wipe le filter aussi

```lua
function ns.Shield.Clear()
    state.mode         = nil
    state.captureUntil = 0
    state.target       = nil
    state.targetClass  = nil
    state.filter       = ""              -- NEW
    if state.filterBox then state.filterBox:SetText("") end
    wipe(state.lines)
    refreshAll()
    relayout()
    ns.MsgInfo("Shield: list cleared (target unlocked).")
end
```

### 2.17 Test scénarios manuels Shield

Après `/reload`, vérifie séquentiellement :

1. **Idle vide** : frame ~338 px de haut. Pas de banner. Pas de cast-on chip. Pas de filter row. Footer `reset all` en gold_dim (inactif).
2. **Target a bot, ne pas pick** : ligne TARGET montre nom class-colored, sous-ligne "live — click pick to lock". Hauteur frame inchangée.
3. **Pick** : sous-ligne devient "◉ LOCKED" en gold. Pas d'autre changement.
4. **Click [los]** : banner amber apparaît, pulse, countdown live. Frame grandit de 16 px. Status idle masqué.
5. **Whispers arrivent** : section header "Game objects" + items apparaissent. Banner countdown se met à jour.
6. **Click [spells] (re-discovery)** : banner se réarme, list wipe, filter reset.
7. **40+ items reçus** : filter row apparaît sous mode-row. Frame grandit de 18 px de plus.
8. **Tape "heal" dans filter** : list réduit. Filter row reste visible (le compte total reste > threshold).
9. **Mode "on Y"** : cast-on chip apparaît (dashed gold), texte instruction. Frame +22 px.
10. **Click sur un unit frame raid** : chip passe en plein, montre "CAST ON  Name". Click sur le chip lui-même : retour à dashed vide.
11. **Mode "ban", click un sort** : whisper `ss +<id>` envoyé, row passe en strike-through avec point rouge. Compteur exclusions footer s'incrémente.
12. **Click [exclusions: N]** : list switche en vue exclusions, bouton passe en gold, footer reset all passe en `ink_red`.
13. **Reset position** : `/wsh reset` ramène en haut-droit défaut.

---

## Phase 4 — Tests & QA

### 4.1 Tests automatisés existants

Le harness `/home/mmasson/warden/` couvre les pure-logic helpers :
- `extractPayload`, `extractSpellId`, `extractObjectId`, `extractRank`, `isSeparator` (Shield)

**Aucune** de ces fonctions ne change. Lance le harness pour confirmer non-régression :

```bash
cd /home/mmasson/warden && lua run_tests.lua
```

Attendu : 294 cases pass, comme avant.

### 4.2 Tests à ajouter (optionnel mais recommandé)

Si tu ajoutes des tests, vise les transformations qui restent pure-logic :

- `buildDisplayItems(state)` : feed state.lines + actionMode + filter + hideGray + viewExclusions, assert sur la structure retournée (kinds, ordre, banned flags, fromTag). Couvre :
  - section headers présents si bucket non vide
  - section headers absents si bucket vide
  - sort alpha intra-bucket
  - filter texte case-insensitive substring
  - hide gray bypass en mode ban/unban
  - multi-bot fromTag décoré uniquement si distinct > 1
  - exclusion view ignore les buckets

Ne crée pas de tests sur les widgets — le harness n'a pas de mock WoW frame complet.

### 4.3 Tests manuels final pass

Avant de marquer la refonte comme terminée :

- `/reload` 3 fois consécutifs pour confirmer que le frame se reconstruit proprement (pas de leak de Textures, pas de doubles event handlers).
- Lance Shield et Sword simultanément, vérifie qu'ils ne se chevauchent pas en position défaut.
- Toggle `/wsh lock` puis drag : drag doit être refusé.
- `/wsh reset` ramène Shield à TOPRIGHT -40 -380.

### 4.4 Debug


```
/wardenlog on
/run WardenDebug = WardenDebug or {}; WardenDebug.shield = true
```

Si quelque chose bug, dump :

```
/wardenlog tail 50
```

---

## Phase 5 — Checklist finale avant commit

- [ ] `Core.lua` : 2 nouveaux helpers (`Banner.Create`, `Segmented.Create`) ajoutés sans toucher au reste
- [ ] `Shield.lua` : `state.modeButtons` supprimé, `state.castOnLbl` supprimé, `state.segMode` ajouté, `state.castOnChip` ajouté, `state.filterBox` ajouté, `state.bannerArmed` ajouté
- [ ] `Shield.lua` : `buildDisplayItems` retourne items mixtes (section/line/excl)
- [ ] `Shield.lua` : `refreshList` branche par `kind`
- [ ] `Shield.lua` : `relayout()` appelée à chaque changement structurel
- [ ] `Shield.lua` : `ns.Shield.Clear()` wipe `state.filter`
- [ ] Slash commands inchangés (`/wsh` testé)
- [ ] Keybindings inchangés (`WARDENSHIELD_TOGGLE` testé)
- [ ] Schema `WardenDB.shield` inchangé
- [ ] Tests harness `/home/mmasson/warden/` passent toujours (294/294)
- [ ] `/reload` triple sans warning / error dans `/wardenlog tail`

---

## Notes de style

- Conserve la convention existante : variables locales en `camelCase`, fonctions module-locales en `camelCase`, API publique en `PascalCase` (`ns.Shield.Show`).
- Garde les commentaires en anglais. Le ton actuel de Shield.lua est descriptif et un peu didactique — préserve-le.
- N'ajoute pas de dépendances. Tout doit fonctionner avec l'API WoW 3.3.5a + les helpers existants `ns.*`.
- Les `wipe()` sur tables existantes plutôt que `state.x = {}` (préserve les refs).
- Forward declarations à la WoW 3.3.5a : `local foo; foo = function(...) end` quand nécessaire — pattern déjà utilisé pour `clickLine` / `rowOnClick`.

FIN.

# Warden Shield & Pocket — Spec d'implémentation pour Claude Code

**Cible** : `Warden/Shield.lua` et `Warden/Pocket.lua` (+ ajouts dans `Core.lua`).
**Hors périmètre** : `UI_Master.lua`, `WardenSword.lua`, slash commands, keybindings, schémas `WardenDB`.
**Référence visuelle** : `Warden Design Doc.html`.

Ce document est un plan d'exécution. Il liste les modifications dans l'ordre, fichier par fichier, avec les signatures exactes attendues. Suis-le séquentiellement.

---

## 0. Règles globales

- **Ne touche pas** : `UI_Master.lua`, `WardenSword.lua`, `Engine.lua`, `Persistence.lua` (sauf si explicitement listé), `Bindings.xml`, `Warden.toc`.
- **Conserve** : tous les slash commands (`/wsh`, `/wp`), tous les keybindings (`WARDENSHIELD_TOGGLE`), tout le schéma `WardenDB.shield` et l'API publique (`ns.Shield.Show/Hide/Toggle/Clear/...`, `ns.Pocket.Show/Hide/Toggle`).
- **Tokens** : aucune nouvelle couleur. Utilise `ns.Tokens.{stone_dark, stone_mid, stone_tile, stone_rim, gold, gold_dim, gold_rim, red_btn, ink_red, amber, green, text_warm}` uniquement.
- **Boutons** : utilise `ns.UI.Button.{stone, gold, red, warn}` — pas de nouvelle tier.
- **Style de code** : copie le ton de l'existant Shield.lua (commentaires en anglais, `local function` partout, forward declarations quand nécessaire).
- **Tests manuels** : après chaque phase, `/reload` in-game et valide le scénario listé. Le test harness `/home/mmasson/warden/` ne couvre que les pure-logic helpers — les changements visuels demandent un check oeil.

---

## Phase 1 — `Core.lua` : nouvelles primitives partagées

Ajoute en fin de fichier (après les buttons factories existantes), deux nouveaux helpers réutilisables par Shield et Pocket.

### 1.1 `ns.UI.Banner.Create(parent, variant)`

Banner conditionnelle qui s'affiche sous le header pour signaler un état actif. Variants : `"amber"` (Shield armed / Pocket listening), `"green"` (Pocket invited / trade open), `"red"` (réservé futur).

```lua
-- ns.UI.Banner.Create(parent, variant) -> frame
--   frame:SetVariant("amber"|"green"|"red")  -- repaint
--   frame:SetText(leftText, rightText)        -- both strings; rightText optional
--   frame:SetPulse(on)                        -- bool — toggle pulse animation
--   frame.blip   = <Texture>  -- 6x6 dot
--   frame.lblL   = <FontString> left  (uppercase tracked label)
--   frame.lblR   = <FontString> right (free-form, gold)
--
-- Dimensions: height 16px, full width of parent.
-- Anchor by caller; the helper just sizes and paints.
```

Internals :
- Backdrop : `WHITE8x8` bg + edge, `edgeSize = 0`, bottom border 1px via une Texture séparée pinned BOTTOMLEFT→BOTTOMRIGHT (couleur variant rim, alpha 0.4).
- Background : un gradient simulé via deux Textures empilées (`SetGradient` n'existe pas en 3.3.5, donc deux solid layers : top alpha 0.22, bottom alpha 0.06 du `variant_color`).
- Couleurs par variant :
  - `amber` : `ns.Tokens.amber` (#ff9a00)
  - `green` : `ns.Tokens.green` (#2ecc40)
  - `red` : `ns.Tokens.ink_red` (#e04a3a)
- `blip` : 6x6 texture WHITE8x8 + `SetVertexColor(variant)`, OnUpdate pulse 0→1→0 sur 1.4s via sin wave.
- `lblL` : `GameFontNormalSmall`, gauche, padding 10px, color = variant.
- `lblR` : `GameFontNormalSmall`, droite, padding 10px, color = gold.

### 1.2 `ns.UI.Segmented.Create(parent, items, onChange)`

Segmented control unifié (5 options max). Pour la mode-row de Shield.

```lua
-- ns.UI.Segmented.Create(parent, items, onChange) -> frame
--   items = { {key="cast", label="cast", tooltip={"Cast","Click..."}},
--             {key="caston", label="on Y", tooltip={"Cast on Y","..."}},
--             ... }
--   onChange(key) called when user clicks an option
--
--   frame:SetActive(key)         -- repaint; no onChange call
--   frame:GetActive() -> key
--   frame:SetDisabled(key, bool) -- gray out a single option
--
-- Dimensions: height 22px, full width of parent (divides equally).
```

Internals :
- Un frame container avec backdrop `WHITE8x8` bg `stone_mid`, edge `stone_rim` 1px.
- Pour chaque item, un sub-Button stretched proportionnellement, séparé du suivant par une 1px Texture `stone_rim`.
- Active option : background passe à `stone_tile`, edge intérieur `gold_rim` 1px (via inset overlay Texture), text color `gold`.
- Inactive : text `gold_dim`, hover ADD-blend blanc 0.10 (réutilise pattern `_makeBtn`).
- Tooltip : `ns.UI.Tooltip.Attach` sur chaque option si `item.tooltip` fourni.

---

## Phase 2 — `Shield.lua` : refonte

Travaille en place dans `Shield.lua`. Ne crée pas de nouveau fichier.

### 2.1 Tunables (haut du fichier)

Remplace le bloc de tunables actuel par :

```lua
local FRAME_W       = 260
local HEADER_H      = 22
local BANNER_H      = 16   -- NEW : armed banner under header (conditionnel)
local TARGET_H      = 32   -- WAS 22 : 2 lignes (name+pick / locked-state)
local ACTION_H      = 22
local MODE_H        = 22
local CAST_ON_H     = 22   -- NEW : chip caston, conditionnel
local FILTER_H      = 18   -- NEW : editbox filtre, conditionnel (>20 items)
local STATUS_H      = 16   -- garde-le pour fallback idle ; remplacé par banner en armed
local LIST_H        = 200  -- baseline ; le frame s'ajuste dynamiquement
local ROW_H         = 18
local SECTION_HDR_H = 14   -- NEW : section header dans la liste
local FOOTER_H      = 22   -- WAS 18
local PAD           = 8
local GAP           = 6
local MAX_LINES     = 200
local FILTER_THRESHOLD = 20  -- NEW : nb items minimum pour afficher le filtre
```

### 2.2 Nouveaux runtime state fields

Dans le bloc `local state = { ... }`, ajoute :

```lua
filter        = "",      -- texte filtre courant (lowercase)
filterBox     = nil,     -- EditBox widget (créé à la volée)
filterRow     = nil,     -- container row pour show/hide
bannerArmed   = nil,     -- ns.UI.Banner.Create result
segMode       = nil,     -- ns.UI.Segmented.Create result
castOnChip    = nil,     -- nouvelle rangée chip caston (remplace castOnLbl inline)
bannedSet     = {},      -- {[spellId]=true} précalculé à chaque refreshList
multiBot      = false,   -- détecté à chaque buildDisplayItems
```

Garde `castOnLbl` pour compat mais ne l'utilise plus — il sera nil après refonte. Tu peux le supprimer du state.

### 2.3 Bouton et state cleanup

- Le `castOnLbl` créé dans le code actuel à la ligne ~880 (inline next to `unbanBtn`) doit être **supprimé**. Le nouveau cast-on chip est une rangée séparée.
- Les 5 boutons de la mode-row (cast/caston/selfcast/ban/unban créés via `makeModeBtn`) sont **supprimés** et remplacés par un seul `ns.UI.Segmented.Create`.

Continue en lisant la phase 2.4 dans le fichier `CLAUDE_CODE_SPEC_PART2.md`.

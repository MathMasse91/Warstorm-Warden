# Warden

**All-in-one raid commander for WoW 3.3.5a (WotLK) / WarStorm playerbots.**
Specs, bots, comp, roster & raid controls — all in one tabbed window, plus combat HUDs and a throttled whisper queue.

<!-- BANNER: drop a wide screenshot/logo here once available
![Warden](docs/images/banner.png)
-->

---

## How this started

This wasn't planned at all.

I was just running raids with **WSSM** (Patchs / Valleriaa) for specs and **WarstormBotManager** (Moroes) for spawning and control. Solid setup — used it for a while.

At some point I thought: *"I've got a fancy Claude Code license from work… let's push WSSM a bit further."* So I started building what was basically **WSSM Extended** — improving flow, making things quicker, nothing huge at first.

Then, right when I was about to post it, I saw what **Runshouse** did with **OptimalRaidComposer + WBM Lite** 😅 — and it was clear this could go way further than what I was about to drop.

So instead of posting, I went back in and doubled down. More ideas, more polish, and honestly a stupid amount of tokens later… it turned into something much bigger.

That's how **Warden v1.0.0** happened. 👍

> If you want to fork it and take it further — go for it. That's pretty much how this whole thing started anyway.

---

## ✨ Features

### 🧭 Main Window — `/warden` (6 tabs)

**Spec**

![Spec tab](docs/images/spec-tab.webp)

- Click target → click spec → done
- Target history popup
- Auto gear / worldbuff buttons
- Recommended PvE spec highlight
- GUID tracking → reconnect = instant reapply

**Controls**

![Controls tab](docs/images/controls-tab.webp)

- Movement: Follow / Stay / Flee
- Strategy: AoE / Burn CD / Facing
- Marks + formation
- 5×4 role matrix (atk / stay / follow / flee)

**Danger Zone**
- Smart ReSpec
- Reset AI
- Hard ReSpec
- Cleanup (with confirmation)

**Extra**
- Quick summon by class buttons

**Bot Comp**

![Bot Comp tab](docs/images/bot-comp.webp)

- Visual raid grid (5 / 10 / 25 / 40)
- Drag & drop setup
- Per slot: spec / blessings / totems / auras / resist
- Live buff coverage (see what's missing instantly)
- `[P]` flag = real player (never touched)

**Roster**
- Live raid grouped: Tank / Healer / DPS
- Buff provider indicators per class
- ReSpec all or selected
- `[P]` toggle per row

**Settings**
- Auto behaviors
- Window sizes
- HUD config
- Maintenance tools (GUID, flags, presets)

**Help**
- Full in-game reference

### ⚔️ HUD — `/ws`

![HUD](docs/images/hud.webp)

- Summon / Follow / Stay / Flee (2×2)
- Strategy row (AoE / Burn / Skull)
- Role matrix (Tank / Heal / DPS × actions)
- Full-width **BLOODLUST** (turns red when active)
- Draggable / lockable
- Auto show in combat
- Density presets + transparency

### 📋 Presets

- 11 built-in comps (Onyxia → ICC, 5 to 25 man)
- Fully editable / deletable
- Default presets can be restored anytime

### 🔄 Import / Export

- `WRDN2` strings
- Share full comps via Discord / in-game
- Lossless

### ⚙️ Under the hood

- Throttled whisper + spawn queue (no spam issues)
- GUID-based spec persistence
- Real player protection everywhere
- Auto party → raid
- Saves through reload / relog

---

## 📦 Installation

1. **Close the game completely.**
2. Copy the entire **`Warden`** folder into your client:
   ```
   <WoW>\Interface\AddOns\Warden\
   ```
3. Launch the game and log in.
4. At the character-select screen, enable **"Load out-of-date AddOns"** (top-right AddOns button) — Warden targets Interface `30300` and most private-server launchers disable old addons by default.
5. In-game, type `/warden` (or `/wden`) to open the main window, or `/ws` for the HUD.

> Built for **WoW 3.3.5a (WotLK)** on **WarStorm** (mod-playerbots enabled).

### First launch checklist
- A minimap button appears at the bottom-left of the minimap ring — drag it anywhere around the ring.
- Your own character is **auto-flagged as a human player**, so none of the automation ever touches you.
- If you had a **WSSM** profile, your saved comps auto-migrate into the **Bot Comp** tab on first login.

## 🎮 Slash commands

**Main window**

| Command  | What it does            |
|----------|-------------------------|
| `/warden`| Toggle the main window  |
| `/wden`  | Same (alias)            |

**WardenSword HUD**

| Command          | What it does                    |
|------------------|---------------------------------|
| `/ws`            | Toggle the HUD                  |
| `/ws show \| hide` | Explicit show / hide          |
| `/ws lock \| unlock` | Lock or unlock position     |
| `/ws reset`      | Reset HUD position              |
| `/ws config`     | Jump to Settings → WardenSword  |
| `/ws help`       | Print the full command list     |

Direct HUD actions: `/ws summon · follow · stay · flee · aoe · burn · skull · bl`, plus role commands `/ws @tank|@heal|@dps atk|stay`.

**Logging**

| Command              | What it does                         |
|----------------------|--------------------------------------|
| `/wardenlog on\|off` | Toggle INFO/WARN logging (errors always captured) |
| `/wardenlog status`  | Show ON/OFF state and entry count    |
| `/wardenlog tail N`  | Print the last N entries             |
| `/wardenlog all`     | Print the whole log                  |
| `/wardenlog clear`   | Wipe the log                         |

## ⌨️ Keybinds

Bindable under **ESC → Key Bindings → "Warden"**: toggle window, tab shortcuts, Summon / Follow / Stay / Tank-Attack / Flee, plus the full **WardenSword** action and role-command set (AoE, Burn CDs, Skull, BL, Tanks/Healers/DPS Attack/Stay). Every binding routes through the same throttled Engine queue, so hammering a hotkey never triggers a server-side mute.

## 🖱️ Minimap button

| Action        | Result                    |
|---------------|---------------------------|
| Left-click    | Toggle main window        |
| Shift-left    | Open Settings tab         |
| Middle-click  | Toggle WardenSword HUD     |
| Right-click   | Open Help tab             |
| Drag          | Orbit the minimap ring (saved per-character) |

## 🛠️ Troubleshooting

- **Addon doesn't load** → enable *"Load out-of-date AddOns"* at character select (Interface `30300`).
- **No minimap button** → `/warden` → Settings → Maintenance → *Reset minimap button*.
- **Bots never get spec'd after a party→raid convert** → the convert is gated on combat lockdown; leave combat and press **Build** again.
- **Server says "you are being ignored" during a Re-Spec** → raise the whisper interval: `/run WardenDB.interval = 0.60; ReloadUI()` (default `0.45s`).

> Warden persists everything to a single `WardenDB` table (logging uses `WardenLog` / `WardenLogEnabled`). It never reads or touches any other addon's SavedVariables or your account data.

---

## 🙏 Credits

Forked from **WSSM** (Patchs & Valleriaa), and merges ideas/code from:
- **WarstormBotManager** — Moroes
- **WBM Lite** & **OptimalRaidComposer** — Runshouse

Huge thanks to all of them — Warden stands on their work.

---

## 🐛 Feedback

If something feels off or breaks, just send what you were doing + any error message and I'll take a look. 👍

<!-- This README and the original announcement were written with AI — I'm massively dyslexic, and it helps me get things out without spending hours rewriting everything. -->

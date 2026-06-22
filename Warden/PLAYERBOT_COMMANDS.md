# Playerbot Commands Reference

Reference for `mod-playerbots` commands used on the WarStorm 3.3.5a server.

---

## How to Make Bots Use Objects

1. Type (in party or whisper):

   ```
   los
   ```

   The bots will show all nearby objects.

2. Find the object you want in the list.
   *(Example: `Twilight Portal`)*

3. **Shift + Click** the object name to insert its link into chat.

4. Tell the bots to use it:

   ```
   u [Object Link]
   ```

5. Example:

   ```
   u [Twilight Portal]
   ```

   The bots will run to the object and interact with it.

---

## Playerbot Spell Commands

| Command | Description |
|---|---|
| `spells` | Show the bot's spells |
| `cast [spell_name]` | Whisper a bot to cast a spell |
| `cast [spell_name] on [PlayerName]` | Whisper a bot to cast a spell on a specified player |
| `ss +[spell id]` | Add a spell to the exclude-spells list |
| `ss -[spell id]` | Remove a spell from the exclude-spells list |
| `ss reset` | Remove **all** spells from the exclude-spells list |
| `trainer` | Show what the bot can learn from the selected trainer |
| `trainer learn` | Learn from the selected trainer |

---

## Party / Raid Target Selection

**RTSC** is a system that enables players to save locations for specified bots using the `aedm` spell, which is given when the `rtsc` command is used. `aedm` lets you point and click a location that can later be used via the commands below.

**RTI** is a system that enables players to focus bots on specified targets using standard WoW target icons.

| Command | Description |
|---|---|
| `rtsc` | Toggles on RTSC and gives the player the `aedm` spell (appears in the General category) |
| `rtsc cancel` | Toggles off RTSC and removes the `aedm` spell from the spellbook |
| `rtsc save [#]` | While RTSC is enabled, saves a location as the specified number when the player uses the `aedm` spell |
| `rtsc unsave [#]` | Clears the saved location |
| `rtsc go [#]` | Commands bots to go to the saved location. Can be whispered to individual bots or used in party/raid chat (e.g. `@Tank rtsc go 5`) |
| `[name/group] rtsc toggle` | Toggles the ability to point-and-click to save a location for specified bots. Specify by group or class (e.g. `@druid rtsc toggle` or `@group1 rtsc toggle`) |
| `rtsc go save` | Commands bots to move back to the saved RTSC position |
| `rti <icon>` | Sets the target icon for the bot to prioritize. Icons: `skull`, `cross`, `circle`, `star`, `square`, `triangle`, `diamond`, `moon` |
| `attack rti target` | Commands bots to attack their RTI target |
| `rti cc <icon>` | Sets a specific icon as the CC target (default is `moon`) |

---

## General Pet Commands

| Command | Description |
|---|---|
| `pet aggressive` | Change pet stance to aggressive |
| `pet passive` | Change pet stance to passive |
| `pet defensive` | Change pet stance to defensive |
| `pet stance` | Display current pet stance |
| `pet attack` | Pet attacks the selected target |
| `pet follow` | Pet follows its master |
| `pet stay` | Pet stays in place |

---

## Hunter Tame Commands

| Command | Description |
|---|---|
| `tame` | Show tame help |
| `tame name "name"` | Summon a tameable pet by name |
| `tame id "id"` | Summon a tameable pet by database creature ID |
| `tame family` | Show tame family help |
| `tame family "family"` | Randomly summon a tameable pet of the given family |
| `tame rename "new name"` | Rename the current pet and refresh its name in the client UI |

---

## Override Commands

You can override everything and instruct the bot to do something specific:

| Command | Description |
|---|---|
| `do attack` | Attack target |
| `do attack my target` | Attack my target |
| `do loot` | Loot target *(currently non-functional)* |
| `do add all loot` | Check every corpse and game object for loot *(currently non-functional)* |

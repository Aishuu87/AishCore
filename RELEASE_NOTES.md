# AishCore

## [v4.4.2](https://github.com/Aishuu87/AishCore/tree/v4.4.2) (2026-10-14)

- Full patch notes are now published with each release (4.4 notes included below)

## [v4.4.1](https://github.com/Aishuu87/AishCore/tree/v4.4.1) (2026-10-14)

- Updated for WoW 12.1.5 (Interface 120105)

## [v4.4](https://github.com/Aishuu87/AishCore/tree/v4.4) (2026-10-14)

### Modules
- On the Modules page, every AishCore element reveals its position and hitbox.
- Hovering an element shows its name at its top left corner
- Right-clicking an element now opens its own settings section (not just the module page)
- Hovering an element's name in the Modules window highlights it on screen
- The Location and AFK Screen modules are now in the EXTRAS section

### Central Circle
- New rendering engine for the resource arc: slightly lighter (barely noticeable, but still), and above all much smoother and fluid when values change!
- Secondary resource arcs get the same improvement, and some buffs can finally be shown as radial (Mana Tea, Consecration, Ironfur and more).
- The Central Circle is now animated while the settings panel is open
- External orbs too
- Runes are no exception, and now recharge radially.
- Arc settings renamed to be easier to understand.
- Arc settings are much finer and 1000 times more precise (literally)
- The secondary resource arc gets all the new settings too
- FIX: some secondary resource circles were not previewed while the settings panel was open
- New color settings for the Central Circle (background, main text and resource arc)
- [Forever] New secondary resource text for Hunter ammunition
  - "Normal / Warning / Critical" thresholds let you set several quantity levels, each with its own color
  - Low thresholds cannot go above high thresholds, and vice versa
  - If the Normal and Critical thresholds are equal, the Warning threshold is ignored
- [Forever] New auto-attack swing timer
  - Shown as a simple bar or as an arc
  - Both are configured separately (color, position, size, fill direction, etc.)
  - Melee and ranged attacks are both supported

### Out-of-Combat Circles
- Settings panels reorganized
- Several fill modes for each circle
- Both circles get the same radial improvements as the Central Circle
- Unit frames now hide while you edit the Out-of-Combat Circles settings
- The Out-of-Combat Circles are now animated

### Well Fed Circle
- New section in Out-of-Combat Circles > Well Fed Circle
- A fully configurable circle shows up while you eat or drink
- If the food can give a buff, the circle changes color and an animation tells you when Well Fed is applied
- The bonus stats given by the buff can be shown right next to the buff icon

### Priority Bar
- New feature that also highlights procs and important buffs on your spells. Handy for tanks and healers who have no real "rotation"
- These highlights can be styled separately from the rotation assistant ones
- An option enables these highlights only in Healer and Tank specs
- [Forever] Unlearned spells are no longer shown in the Priority Bar, but can still be configured

### XP Bar
- Hovering your level shows what the next level brings: health, resource, stats, and the new abilities from your class trainer.
- Hold SHIFT while hovering your level to see the XP from quests ready to turn in
- [Forever] Hold ALT while hovering your level to see the abilities you can train (unlocked but not learned)
- [Forever] Abilities to train and upcoming abilities also include Pet (Hunter) and Demon (Warlock) abilities
- [Forever] All upcoming abilities and their cost up to level 60 are now known by the addon.
- Stat gains can't be known in advance: we need data from a full level 1 to 60 journey for each class. If you'd like to help gather it and improve the addon, contact Aishuu on Discord!

### Stealth Mode
- New optional setting in Themed Colors for Rogues and Druids: when checked, a new color scheme applies while the player is stealthed.
- New "Stealth Mode" module in the EXTRAS section. It sets up a vignette that darkens the screen while you blend into the shadows. It should adapt to ultra wide resolutions, but I have no way to test it!

### Themed Colors
- Slight changes to pet health bar colors (Hunter and Warlock)
- 2 new "Conditions: Stealth" color sets for Druid and Rogue

### Unit Frames
- New settings to change the health bar colors (background and fill)
- Second texture selector for the background (it only applied to the bar foreground before)
- New option to show the target's level
- Just like the Top Target bar, the target level changes color with its difficulty
- New option to show the player's first and last name when hovering their bar
- Smooth show / hide animation for the player cast bar
- 3 new spark settings (the tip of the cast bar): texture (line, dot, spark, star), color and size

### [Forever] Pet Happiness
- New pet happiness indicator. It turns Green, Yellow or Red when the pet is Happy, Content or Unhappy
- New alert (can be turned off) when your pet is Unhappy (in the Missing buffs module)
- Hovering the pet frame reveals its level and loyalty rank

### Menu Bar
- New "Menu Bar" module (EXTRAS).
- This Menu Bar is fully customizable.
- Add, reorder and remove shortcuts right in the AishCore editor
- Some shortcuts like Professions, Talents or Volume have extra features with click + key combinations.
- For example, the Professions shortcut:
  - Left click: professions window, as before.
  - Shift + click: profession 1.
  - Ctrl + click: profession 2.
  - Alt + click: Cooking.
  - Shift + Ctrl + click: Fishing.
  - Ctrl + Alt + click: Archaeology.
- Colors can follow the Themed Colors of your specialization.

### QOL
- New option to open the tracking menu by right-clicking the minimap
- New option to show herb and ore icons instead of the usual gold dot

### Misc & Fixes
- The AishCore / AishUI logo is 30% bigger (no, you're not crazy)
- [Forever] The family name is now shown on the AFK Screen
- [Forever] FIX: the "Summon pet" alert could show even though no pet had been tamed
- [Forever] FIX: orb animations could fail to show when leaving Stealth
- FIX: the XP Bar level badge could stay stuck on the previous level.
- FIX: cinematics during character creation made both AishCore reload alerts show up at once
- FIX: the click tolerance zone on unit frames is now disabled in some cases to avoid getting stuck: Vehicle, Pet Battle, Possession, Override bar (mini games, etc.)
- FIX: the Rogue Subtlety spec was wrongly named in French
- FIX: "Logos" 3D animation combos could not be right-clicked to copy / paste animations
- FIX: the XP bar texture was slightly enlarged to fill the full screen width
- FIX: opening a dropdown (e.g. font selection) near a window edge no longer cuts the menu
- FIX: aura tracking in Icon List mode now displays correctly with the "Dual icon" layout
- FIX: Icon List icons are no longer stretched
- FIX: aura tracking bars used the base class color, ignoring Themed Colors
- FIX: some buff tracking icon texts could cause missing font errors
- New Glow settings for every aura tracking display "Mode", to customize each mode separately.
- The bar previews in the Dynamic Bars section stay pinned at the top of the window, so you can easily see your changes

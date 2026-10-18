# AishCore

## [v4.5](https://github.com/Aishuu87/AishCore/tree/v4.5) (2026-10-18)

- New general optimization pass on the addon, about 30-35% faster

### Settings panel
- Subtle textured backgrounds in the settings panel, with a parchment-style border
- New Minimize button: clicking it collapses the panel
- New icons flagging every new category, and every new section inside another module
- The new feature icons can be hidden or shown by clicking the text to the right of the logo
  - New features cover the last 2 major patches (the current version and the one before it). Minor patches (e.g. 4.2.2) are not counted
  - New features stop being new after a month. "Hide new features" is then turned on automatically
  - Clicking "Show new features" brings back the new features of the last 2 versions at any time
- Scrolling in a window now moves smoothly instead of abruptly jumping up or down
- Clicking a page title expands/collapses all its sections at once
- Double-clicking a section expands/collapses all the other sections at once too

### Central Circle
- [Forever] Dual-wield support for the auto-attack Swing Timer
- [Forever] New option to track ranged auto-attacks only
- [Forever] New option to ignore the off-hand and track only the main-hand weapon when dual-wielding
- [Forever] In "Bar" mode, Left/Right fills create a second bar, while Mirror fills send the main hand and off-hand to either side of a single bar
- New option to show a dragon decoration (Elite Dragons) when the target is elite, rare, rare elite or a world boss

### XP Bar
- The "Next Level" info now uses the XP Bar colors
- Holding SHIFT also shows your active quests and the XP they give (Retail only)
- On Retail, the next level shows the next 6 unlockable spells, with their level
- [Forever] New abilities show a "+" icon, while upgrades of abilities you already know show a "^" chevron
- [Forever] Polearms training at level 20 added for the relevant classes
- [Forever] Shows the city where you can find the Weapon Masters to learn your weapon skills
- New Level Up notification:
  - It shows your stat gains
  - It shows the newly unlocked abilities
  - Its display can be adjusted in the AishCore options
  - An option waits for the end of combat before showing it

### Unit Frames
- New, more complete visibility system
  - The "Options per role" option sets different conditions depending on the spec you play
  - New visibility conditions: "Friendly target / Attackable target", "In a group", "In an instance"
  - When "Always" is checked, only "Hide when mounted" / "Hide in rest areas" can still decide whether the health bars are shown
  - This visibility system will be adapted to other modules in a future update

### Missing buffs
- New "General" category:
  - If you carry sharpening stones or oils, an alert offers to apply one to your weapon
  - If you carry food that gives a buff, an alert offers to eat it
  - If you carry flasks, an alert can also be shown
- New "Talent Points & Heritage" category: when you have points to spend, clicking the alert opens the matching panel
- New "Bags Full" alert, warning when your bags are full or almost full. A threshold sets when it shows up
- New "Find Herbs/Minerals" alert when your character has the profession but no gathering tracking active
- Sections and alerts reorganized
- Crusader Aura is suggested while mounted, even with "Ignore while mounted" on
- In combat with no aura, or with Crusader Aura, Concentration Aura and Devotion Aura are suggested (clicks are disabled in combat: you can't just click their icon)

### Movement Buffs
- This new module shows your movement and speed buffs as simple bars
- It can be shown independently from the regular "Auras to Track"
- [Forever] The Tauren racial "Plainsrunning" is supported too

### Dynamic Bars
- [Forever] FIX: sharpening stones were not detected correctly
- New whitelist to add specific items that escaped the Dynamic Bars detection or don't fit any category
- New "Teleports" category
- New "Scrolls" category
- New "Gadgets" category

### QoL
- New checkbox to easily turn on quest auto turn-in
- New option to hide the red error messages in the middle of the screen (Not enough mana, You can't do that yet, etc.)
- New option to reveal the fog of war (undiscovered areas) on your map
- New option to set a target as your focus with Ctrl + click

### 3D Animations
- New "Random" option that plays one of the listed FX at random when the spell / aura triggers

### Fixes & Misc
- Many auras reclassified into their proper Buff/Debuff/Totem category
- Scrollbar added to dropdown menus (fonts, textures, etc.)
- New options to set the Cast Bar text color
- Drinks are now supported by the Well Fed Circle
- Herb and ore icons on the minimap optimized: the feature no longer uses any performance when neither tracking is active
- [Forever] The Menu Bar did not open the First Aid page correctly with Ctrl+Alt+click on the Professions icon
- Previews in menus now use a background image
- Element placement is now pixel perfect, and small objects render much sharper
- [Forever] The Outlaw spec has been renamed "Combat"
- [Forever] Fire and Frost specs correctly show mana in the Central Circle
- [Forever] Removed the Warrior "Ignore Pain" secondary resource circle, which doesn't exist in this version of the game
- FIX: secondary professions are named correctly in the tooltip of the Menu Bar Professions button
- FIX: heal prediction no longer worked with the new fill types of the Out-of-Combat Health Circle
- FIX: heal prediction was not shown in the Out-of-Combat Health Circle with a radial fill
- [Forever] FIX: the Cast Bar correctly shows "Opening" instead of "Opening - No text"
- FIX: custom textures (SharedMedia_MyMedia) were not picked up
- FIX: the bandage cooldown keeps showing correctly when entering combat

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

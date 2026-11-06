# AishCore

## [v4.6.8](https://github.com/Aishuu87/AishCore/tree/v4.6.8) (2026-11-06)

### Fixes
- Missing buffs: the alert now hides once the buff or elixir is applied (it stayed shown when bags were nearly full)

## [v4.6.7](https://github.com/Aishuu87/AishCore/tree/v4.6.7) (2026-11-06)

### Dynamic Bars
- Dynamic bars hidden in combat now show on mouseover

### Menu Bar
- Added the Appearances option
- Added the Pet Journal option
- Added the Toy Box option
- Added the Group Finder option
- Added shortcuts on the Collections icon:
  - Shift + click: mounts
  - Ctrl + click: pets
  - Alt + click: Toy Box
  - Ctrl + Alt + click: Appearances
- Added the Equipment Manager option. Shortcuts let you switch from one set to another

### Missing buffs
- The Elixirs alert now stays shown while other elixirs can still be used. A new option, "One elixir is enough", hides the alert as soon as at least one elixir is applied

### Fixes
- [Forever] Missing buffs: the missing Elixir alert no longer shows when a stronger buff is already active

## [v4.6.6](https://github.com/Aishuu87/AishCore/tree/v4.6.6) (2026-11-06)

### Fixes
- Gamepad: the wider merchant window is now disabled in gamepad mode (it caused the SetPreferredGamepadInteractTarget blocked action error)
- [Forever] Resource Circle: leaving and re-entering a Druid form during combat now updates the circle and the mana text

## [v4.6.5](https://github.com/Aishuu87/AishCore/tree/v4.6.5) (2026-11-06)

### Cast Bars
- Added a "Hide Blizzard cast bar" option (player bar, on by default)

### Missing buffs
- Added a "One elixir is enough" option

### Fixes
- Gamepad: fixed the blocked action error (SetPreferredGamepadInteractTarget) that forced reloads
- Simplified Chinese: the AishUI setup window and several texts showed squares instead of characters
- [Forever] Resource Circle: shapeshifting in combat now updates the resource (rage / energy / mana)
- [Forever] Resource Circle: Cat Form now shows combo points

## [v4.6.4](https://github.com/Aishuu87/AishCore/tree/v4.6.4) (2026-11-05)

### Resource Circle
- [Druid] Added an option to show your mana as the secondary resource text in Cat / Bear Form

### Missing buffs
- After 15 s, a hint reminds you that right-click hides the alert

### Fixes
- [Forever] Missing buffs: no longer suggests a buff the server would refuse because a more powerful spell is already active (scroll, campfire bonus...)
- [Forever] Resource Circle: Bear / Cat Form showed mana instead of rage / energy

## [v4.6.3](https://github.com/Aishuu87/AishCore/tree/v4.6.3) (2026-11-05)

### Movement Buffs
- Added a customizable Stack text for buffs with stacks

### QoL
- Added an option to hide the Totem Bar or reveal it on hover

### Fixes
- [Forever] The Rotation Button Module is now disabled
- [Forever] FIX: blocked action error (SpellStopCasting) when opening AishCore from the WoW options
- [Forever] Mulgore: Bloodhoof Village was not considered a safe zone
- [Forever] FIX: the Platynator integration no longer worked (font change)
- [Forever] FIX: not all weapon skills were displayed

## [v4.6.2](https://github.com/Aishuu87/AishCore/tree/v4.6.2) (2026-11-05)

- Rotation Button Module and Priority Bar: mouse button keybinds now use a short form (Ctrl + Mouse Button 4 shows CM4)
- [Forever] The Rotation Button Module is disabled
- FIX: blocked action error (SpellStopCasting) when opening AishCore from the WoW options

## [v4.6](https://github.com/Aishuu87/AishCore/tree/v4.6) (2026-11-04)

### Settings panel
- New button to enable/disable each module, right next to the page title
- When a module is disabled, the rest of its page is inactive and grayed out
- The Modules page can now enable/disable QoL settings
- Profiles can now export/import/copy the features recently added to AishCore, and they are organized the same way as the Modules page
- Improved sliders: easier to handle, in your current spec's theme color, and better aligned with the other settings
- Slider min/max values are only shown while you use the slider
- While the settings panel is minimized, elements are no longer interactive, so you can better see how they behave outside the settings
- Many changes to page structures: settings elements have more consistent sizes, are grouped by feature, and were renamed to make more sense

### General
- Added Simplified Chinese localization (zhCN)

### [Forever] Camping HUD
- New Camping module
- A diamond appears when you are near a campfire
- Left-clicking the diamond makes you sit down
- Right-clicking unpacks your camp gear and shows shortcuts for the 5 professions and up to 6 camp objects ready to be added to the site
- Quickly hovering the objects placed around the fire "scans" the buffs they will grant after 1 minute spent sitting
- Buffs are shown above the diamond (up to 10), and hovering their icons shows their details
- A loading bar fills around the diamond. Once full (1 minute), a summary of the buffs you earned is shown above the diamond

### Missing buffs
- Missing buff alerts are no longer offered in safe zones, like villages or small towns. If the village is hostile to your faction, the alerts are still shown
- Missing buff alerts now show the quality of the suggested consumables
- Missing buff alerts can be hidden with a right-click until the next zone or condition refresh
- New options to separate the missing aura alerts for Paladins (some players don't want the Crusader Aura alerts, for example)
- Added Elixir reminders to Missing buffs
- [Forever] Missing buff alerts for poisons now work correctly
- [Forever] New threshold for how long before expiring you are reminded to refresh your poisons
- [Forever] New alert with a threshold, warning you when your poison stock is about to run out
- When several consumable alert icons are shown, each icon gets the same animation set in 3D Animations
- Food buff animations are centered when several consumables are offered to click
- Missing buff alerts no longer remind you to reapply consumable buffs early: they wait until their enhancements have fully expired
- Hunter: the alert now correctly offers "REVIVE PET" when the pet is dead, including after an interrupted resurrection or the player's death
- Hunter: the pet alert can be clicked in combat (Revive and Call)
- Warlock: the pet alert can be clicked in combat, with a choice of demon

### Unit Frames
- The Unit Frames page has been completely rebuilt:
  - A preview box lets you see the bar
  - Each bar has its own settings
  - Right-clicking an element directly opens its settings section
  - Previews of the Central Circle, Priority Bar and Cast Bars (target and player) can be toggled
- New Layout option with 3 choices:
  - Free: position the bar independently
  - Parenting: link its position to another bar. Moving one moves the other, as a single group
  - Symmetry: link bars together and move them symmetrically, with the mirror axis at the center of the screen
- New settings for:
  - Bar background color
  - HP frame: shape (round, diamond, square), color, position, anchor
  - Decorative Shapes: shape (round, diamond, square, chevrons, and combinations of several), anchor (left/right/both sides), quantity
  - The player name can be "Always shown"
- New shadow option under the unit name, with adjustable size and opacity
- New Fill direction option (left to right, right to left, top to bottom, bottom to top)
- New Box width setting, to set a maximum displayed length for the unit name

### Cast Bars
- The Cast Bar: Player and Cast Bar: Target modules are now grouped in the same "Cast Bars" category
- This new page has a preview, and a selector switches between the settings of each bar
- Added Cast Bar: Focus
- New anchor and position options for the spell name and the cast time
- Right-clicking an element goes directly to its section
- The preview now cycles through 3 spells to show the different colors and channel displays: Fireball / Frostbolt / Drain Life
- Cast bars are now delayed when you get hit (pushback)
- New options to show and adjust the spell icon on cast bars (player and target)

### XP Bar
- Reorganized the XP Bar settings page
- Many new XP Bar settings (size, orientation, layout, etc.)
- New Rested XP display

### Priority Bar
- New Preview section at the top of the page
  - Clicking a slot lists all the spells assigned to it, and lets you add a new spell (green "+")
  - Drag and drop a spell to move it to another slot, or to change its priority within the slot
  - Dragging a spell outside a slot removes it from the Priority Bar
  - Right-clicking a spell shows 3 options: change the glow color (left), remove the spell (right), set the spell as "Stealth" (top, Rogues and Druids only)
- New option to set a spell as "Stealth"
- A spell set as "Stealth" is only shown while stealthed. A small purple marker in the top left corner of the icon flags it

### Stealth Mode
- New Visibility options for the player health, target health, Central Circle and Priority Bar while in Stealth Mode
- Example configuration:
  - The player health bar shows as soon as you are outside a rest area/village
  - The target health bar always shows when you are stealthed (and have a target)
  - The Central Circle shows when you are in a group, in an instance, in a PvP zone or any other contested zone
  - The Priority Bar shows as soon as your target can be attacked

### Central Circle
- New display for the options and settings of the 2 circles
- Right-clicking an element of the circles opens its settings
- New option to flip the Elite Dragon

### Out-of-Combat Circles
- New display for the options and settings of the 2 circles
- Left-clicking one of the circles opens its settings
- Right-clicking an element of a circle opens its settings
- The Well Fed Circle now has its own dedicated section, with a preview built into the page

### Cooldowns Appearance
- The "Essential CDs" and "Utility CDs" modules are now grouped in this new category
- Reworked settings page with a preview of the CDs
- Right-clicking an element goes directly to its section

### Addon Compartment
- New customizable Addon Compartment
- Many settings to change the size, the icon layout (list, grid) and the minimap anchor
- An addon list lets you exclude some addons or mark them as favorites
- The Favorites list can then be set up independently from the main list

### QoL
- New option: double right-click to cast your fishing rod ([Forever]), or Ctrl + double right-click on Retail
- New options to change the font of Baganator sections and categories (Extras > Integration)

### Menu Bar
- The Hearthstone button now shows your Hearthstone's destination
- The Hearthstone button shows the remaining cooldown when your Hearthstone is not available

### Fixes
- Added an AishCore logo in the Addon list
- FIX: Thunder Focus Tea was not tracked correctly
- FIX: Tigereye Brew removed from buff tracking (the aura is a passive and its bar stayed on screen permanently)
- FIX: Some feasts were not covered by the Well Fed Circle (Harandar Celebration, Royal Roast, etc.)
- FIX: When disabled, the player cast bar could still show up on an interrupted cast
- FIX: When disabled, unit frames could still get in the way of clicks as if they were still interactive
- FIX: The cast bar now correctly shows the delay when you get hit while casting
- FIX: The sharpening stone alert only shows if you have a bladed weapon equipped
- FIX: The clock text could appear offset on the Menu Bar
- FIX: The Top Target HP text could have the wrong font when the character loaded
- FIX: The EllesmereUI profile and module setup runs correctly again after a new AishUI installation
- [Forever] FIX: Sharpening stones were not offered to Rogues. They are now, until they learn Poisons
- [Forever] FIX: Tin veins did not show their icon on the minimap
- [Forever] FIX: Added Form of the Moonstalker to the effects that trigger Stealth Mode
- [Forever] FIX: Retribution Aura is now offered in Missing buffs on Forever
- FIX: Lua error when the Location module was disabled
- FIX: The buyback icon could show on top of the repair icons
- FIX: Buyback pages did not show sold items
- FIX: The customizable Priority Bar no longer shows when opening the spellbook in combat
- FIX: Some spells could not be dragged from the spellbook to the Priority Bar (Apex talent in particular)
- FIX: The Priority Bar could stay interactive even when hidden
- FIX: Combo points around the out-of-combat circle were displayed erratically
- FIX: Some conditions when leaving stealth could cause a position bug on the player health bar

## [v4.5.1](https://github.com/Aishuu87/AishCore/tree/v4.5.1) (2026-10-18)

- [Forever] FIX: Lua error from MemTrace.lua ("attempt to index a secret string value")

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

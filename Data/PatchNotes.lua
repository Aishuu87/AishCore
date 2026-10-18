-- Data/PatchNotes.lua : notes de version affichees dans la page "Patch Notes" du GUI (UI/PatchNotesPage.lua).
-- Plus recente en premier. Chaque ligne : { t = texte, k = "h" (titre de section) | "li" (puce), lvl = 1/2 }.
-- Champ optionnel `link = { page = "idDePage", section = "CLE_LOCALE_DU_HEADER" }` : rend la ligne cliquable.
-- Champ optionnel `fr` : texte affiche sur un client frFR (sinon `t`). Titres : leur `link` passe par l'icone a droite.
-- Sans `link`, les noms de modules connus (ns.PatchNoteLinks plus bas) sont detectes automatiquement.
local addonName, ns = ...

ns.PatchNotes = {
  {
    version = "4.5", date = "2026-10-18",
    lines = {
      { k = "h", t = "General", fr = "Général" },
      { k = "li", lvl = 1, t = "New general optimization pass on the addon, about 30-35% faster", fr = "Nouvelle passe d'optimisation générale sur l'addon, avec un gain d'environ 30-35%" },

      { k = "h", t = "Settings panel", fr = "Panneau de réglages" },
      { k = "li", lvl = 1, t = "Subtle textured backgrounds in the settings panel, with a parchment-style border", fr = "Ajout d'arrière-plans texturés subtils dans le panneau de réglage et d'un contour effet parchemin" },
      { k = "li", lvl = 1, t = "New Minimize button: clicking it collapses the panel", fr = "Ajout d'un bouton de Réduction de fenêtre. Le cliquer minimise le panneau." },
      { k = "li", lvl = 1, t = "New icons flagging every new category, and every new section inside another module", fr = "Ajout d'icônes pour notifier chaque nouvelle catégorie ou chaque nouvelle section à l'intérieur d'un autre module" },
      { k = "li", lvl = 1, t = "The new feature icons can be hidden or shown by clicking the text to the right of the logo", fr = "Les icônes de nouveautés peuvent être cachées ou affichées en cliquant sur le texte à droite du logo" },
      { k = "li", lvl = 2, t = "New features cover the last 2 major patches (the current version and the one before it). Minor patches (e.g. 4.2.2) are not counted", fr = "Les nouveautés contiennent les 2 derniers patchs majeurs (la version actuelle et celle juste avant elle). Les patchs mineurs (ex : 4.2.2) ne sont pas comptés" },
      { k = "li", lvl = 2, t = "New features stop being new after a month. \"Hide new features\" is then turned on automatically", fr = "Les nouveautés cessent de l'être au bout d'un mois. À ce moment-là, le bouton « Cacher les nouveautés » s'active automatiquement" },
      { k = "li", lvl = 2, t = "Clicking \"Show new features\" brings back the new features of the last 2 versions at any time", fr = "Cliquer sur « Montrer les nouveautés » permet tout de même de réafficher les nouveautés des 2 dernières versions, à tout moment" },
      { k = "li", lvl = 1, t = "Scrolling in a window now moves smoothly instead of abruptly jumping up or down", fr = "Scroller dans une fenêtre se fait avec un mouvement fluide plutôt que de brusquement faire monter/descendre la page" },
      { k = "li", lvl = 1, t = "Clicking a page title expands/collapses all its sections at once", fr = "Cliquer sur le titre d'une page permet de déplier/replier toutes les sections d'un coup" },
      { k = "li", lvl = 1, t = "Double-clicking a section expands/collapses all the other sections at once too", fr = "Double cliquer sur une section permet de déplier/replier toutes les autres sections d'un coup également" },

      { k = "h", link = { page = "resourceCircle" }, t = "Central Circle", fr = "Cercle Central" },
      { k = "li", lvl = 1, t = "[Forever] Dual-wield support for the auto-attack Swing Timer", fr = "[Forever] Ajout du support de l'ambidextrie pour le Délai d'auto-attaque" },
      { k = "li", lvl = 1, t = "[Forever] New option to track ranged auto-attacks only", fr = "[Forever] Ajout d'une option pour ne suivre l'auto-attaque qu'à distance" },
      { k = "li", lvl = 1, t = "[Forever] New option to ignore the off-hand and track only the main-hand weapon when dual-wielding", fr = "[Forever] Ajout d'une option pour ignorer la main gauche et ne suivre que l'arme principale en ambidextrie" },
      { k = "li", lvl = 1, t = "[Forever] In \"Bar\" mode, Left/Right fills create a second bar, while Mirror fills send the main hand and off-hand to either side of a single bar", fr = "[Forever] En mode « Barre », une 2e barre est créée pour les remplissages Gauche/Droite, tandis que les remplissages Miroir font partir la main gauche et droite de part et d'autre d'une unique barre" },
      { k = "li", lvl = 1, t = "New option to show a dragon decoration (Elite Dragons) when the target is elite, rare, rare elite or a world boss", fr = "Ajout d'une option pour afficher une décoration de dragon lorsque la cible est élite, rare, rare élite ou world boss" },

      { k = "h", link = { page = "xpBar" }, t = "XP Bar", fr = "Barre d'XP" },
      { k = "li", lvl = 1, t = "The \"Next Level\" info now uses the XP Bar colors", fr = "L'affichage des infos « Prochain Niveau » prend les couleurs de la barre d'XP" },
      { k = "li", lvl = 1, t = "Holding SHIFT also shows your active quests and the XP they give (Retail only)", fr = "Maintenir MAJ permet également d'afficher les quêtes en cours et l'équivalent en XP de ce qu'elles offrent (Retail seulement)" },
      { k = "li", lvl = 1, t = "On Retail, the next level shows the next 6 unlockable spells, with their level", fr = "Sur Retail, le prochain niveau affiche les 6 prochains sorts déblocables, ainsi que leur niveau" },
      { k = "li", lvl = 1, t = "[Forever] New abilities show a \"+\" icon, while upgrades of abilities you already know show a \"^\" chevron", fr = "[Forever] Les compétences nouvelles affichent une icône « + », alors que les améliorations de compétences déjà apprises ont un chevron « ^ »" },
      { k = "li", lvl = 1, t = "[Forever] Polearms training at level 20 added for the relevant classes", fr = "[Forever] Ajout de l'apprentissage des Armes d'hast au niveau 20 pour les classes concernées" },
      { k = "li", lvl = 1, t = "[Forever] Shows the city where you can find the Weapon Masters to learn your weapon skills", fr = "[Forever] Ajout de la ville dans laquelle vous pouvez trouver les Maîtres d'armes pour apprendre vos compétences d'armes" },
      { k = "li", lvl = 1, t = "New Level Up notification:", fr = "Ajout d'une notification à la montée de niveau :" },
      { k = "li", lvl = 2, t = "It shows your stat gains", fr = "Elle affiche les gains de statistiques" },
      { k = "li", lvl = 2, t = "It shows the newly unlocked abilities", fr = "Elle affiche les nouvelles compétences débloquées" },
      { k = "li", lvl = 2, t = "Its display can be adjusted in the AishCore options", fr = "L'affichage est réglable dans les options d'AishCore" },
      { k = "li", lvl = 2, t = "An option waits for the end of combat before showing it", fr = "Une option permet d'attendre la fin du combat avant d'afficher la notification" },

      { k = "h", link = { page = "unitBars" }, t = "Unit Frames", fr = "Cadres d'unités" },
      { k = "li", lvl = 1, t = "New, more complete visibility system", fr = "Ajout d'un nouveau système plus complet de visibilité" },
      { k = "li", lvl = 2, t = "The \"Options per role\" option sets different conditions depending on the spec you play", fr = "L'option « Options par rôle » permet de définir des conditions différentes suivant la spé que vous jouez" },
      { k = "li", lvl = 2, t = "New visibility conditions: \"Friendly target / Attackable target\", \"In a group\", \"In an instance\"", fr = "Les conditions de visibilité « Cible alliée / Cible attaquable », « En groupe », « En instance » ont été ajoutées" },
      { k = "li", lvl = 2, t = "When \"Always\" is checked, only \"Hide when mounted\" / \"Hide in rest areas\" can still decide whether the health bars are shown", fr = "Lorsque l'option « Toujours » est cochée, seules les conditions « Cacher en monture / zone de repos » peuvent prendre le pas sur la visibilité ou non des barres de vie" },
      { k = "li", lvl = 2, t = "This visibility system will be adapted to other modules in a future update", fr = "Ce système de visibilité sera adapté pour d'autres modules dans une future mise à jour" },

      { k = "h", link = { page = "aurasMissingBuffs" }, t = "Missing buffs", fr = "Buffs manquants" },
      { k = "li", lvl = 1, t = "New \"General\" category:", fr = "Ajout d'une catégorie « Général » :" },
      { k = "li", lvl = 2, t = "If you carry sharpening stones or oils, an alert offers to apply one to your weapon", fr = "Si le joueur possède des pierres à aiguiser ou des huiles dans ses sacs, une alerte s'affiche pour proposer d'en appliquer sur son arme" },
      { k = "li", lvl = 2, t = "If you carry food that gives a buff, an alert offers to eat it", fr = "Si le joueur possède de la nourriture capable de donner des buffs, une alerte s'affiche alors pour en consommer" },
      { k = "li", lvl = 2, t = "If you carry flasks, an alert can also be shown", fr = "Si le joueur possède des flacons à appliquer, une alerte peut aussi s'afficher" },
      { k = "li", lvl = 1, t = "New \"Talent Points & Heritage\" category: when you have points to spend, clicking the alert opens the matching panel", fr = "Ajout d'une catégorie « Points de talents & Héritage » : si le joueur a des points à dépenser, un clic sur l'alerte ouvre alors le panneau correspondant" },
      { k = "li", lvl = 1, t = "New \"Bags Full\" alert, warning when your bags are full or almost full. A threshold sets when it shows up", fr = "Ajout d'une alerte Sacs pleins, qui avertit lorsque les sacs sont pleins ou presque pleins. Un seuil permet de définir le moment du rappel" },
      { k = "li", lvl = 1, t = "New \"Find Herbs/Minerals\" alert when your character has the profession but no gathering tracking active", fr = "Ajout d'une alerte Découverte herbes/minerais lorsque votre personnage a la compétence mais qu'il n'a plus de pistage activé" },
      { k = "li", lvl = 1, t = "Sections and alerts reorganized", fr = "Réorganisation des sections et des alertes" },
      { k = "li", lvl = 1, t = "Crusader Aura is suggested while mounted, even with \"Ignore while mounted\" on", fr = "L'Aura de Croisé est proposée en alerte lorsque le joueur est en monture, même si l'option « Ignorer si monté » est active" },
      { k = "li", lvl = 1, t = "In combat with no aura, or with Crusader Aura, Concentration Aura and Devotion Aura are suggested (clicks are disabled in combat: you can't just click their icon)", fr = "Lorsque le joueur est en combat avec aucune aura, ou en Aura de Croisé, les auras de Concentration et de Dévotion sont proposées (les clics sont désactivés en combat, vous ne pourrez pas simplement cliquer sur leur icône)" },

      { k = "h", link = { page = "movementBuffs" }, t = "Movement Buffs", fr = "Buffs de déplacement" },
      { k = "li", lvl = 1, t = "This new module shows your movement and speed buffs as simple bars", fr = "Ce nouveau module permet d'afficher très simplement les buffs de déplacement et de vitesse sous forme de barres" },
      { k = "li", lvl = 1, t = "It can be shown independently from the regular \"Auras to Track\"", fr = "Ce système peut s'afficher indépendamment des « Auras à tracker » classiques" },
      { k = "li", lvl = 1, t = "[Forever] The Tauren racial \"Plainsrunning\" is supported too", fr = "[Forever] Le racial Tauren « Course dans les plaines » est également supporté" },

      { k = "h", link = { page = "extraBars" }, t = "Dynamic Bars", fr = "Barres dynamiques" },
      { k = "li", lvl = 1, t = "[Forever] FIX: sharpening stones were not detected correctly", fr = "[Forever] FIX : les pierres à aiguiser n'étaient pas détectées correctement" },
      { k = "li", lvl = 1, t = "New whitelist to add specific items that escaped the Dynamic Bars detection or don't fit any category", fr = "Ajout d'une whitelist afin d'ajouter des items spécifiques qui auraient échappé à la détection des barres dynamiques ou qui ne conviendraient à aucune catégorie" },
      { k = "li", lvl = 1, t = "New \"Teleports\" category", fr = "Ajout de la catégorie Téléportations" },
      { k = "li", lvl = 1, t = "New \"Scrolls\" category", fr = "Ajout de la catégorie Parchemins" },
      { k = "li", lvl = 1, t = "New \"Gadgets\" category", fr = "Ajout de la catégorie Gadgets" },

      { k = "h", link = { page = "comfortQoL" }, t = "QoL", fr = "QoL" },
      { k = "li", lvl = 1, t = "New checkbox to easily turn on quest auto turn-in", fr = "Ajout d'un carré à cocher pour facilement activer le rendu automatique des quêtes" },
      { k = "li", lvl = 1, t = "New option to hide the red error messages in the middle of the screen (Not enough mana, You can't do that yet, etc.)", fr = "Ajout d'une fonctionnalité pour cacher les erreurs rouges du milieu d'écran (Pas assez de mana, Vous ne pouvez pas faire ça en ce moment, etc.)" },
      { k = "li", lvl = 1, t = "New option to reveal the fog of war (undiscovered areas) on your map", fr = "Ajout d'une fonctionnalité pour afficher le brouillard de guerre (zones pas encore découvertes) sur votre carte" },
      { k = "li", lvl = 1, t = "New option to set a target as your focus with Ctrl + click", fr = "Ajout d'une option permettant de passer une cible en focalisation à l'aide d'un Ctrl + clic" },

      { k = "h", link = { page = "spellEffects" }, t = "3D Animations", fr = "Animations 3D" },
      { k = "li", lvl = 1, t = "New \"Random\" option that plays one of the listed FX at random when the spell / aura triggers", fr = "Ajout d'une option « Au hasard » pour lire un des FX de la liste au moment du déclenchement du sort / de l'aura de manière aléatoire" },

      { k = "h", t = "Fixes & Misc", fr = "Correctifs & Divers" },
      { k = "li", lvl = 1, t = "Many auras reclassified into their proper Buff/Debuff/Totem category", fr = "Reclassement de nombreuses auras dans leur bonne catégorie Buff/Debuff/Totem" },
      { k = "li", lvl = 1, t = "Scrollbar added to dropdown menus (fonts, textures, etc.)", fr = "Ajout d'une barre de scroll dans les menus déroulants (polices, textures, etc.)" },
      { k = "li", lvl = 1, t = "New options to set the Cast Bar text color", fr = "Ajout d'options pour régler la couleur du texte de la barre de cast" },
      { k = "li", lvl = 1, t = "Drinks are now supported by the Well Fed Circle", fr = "Les boissons sont maintenant supportées par l'affichage « Cercle Bien Nourri »" },
      { k = "li", lvl = 1, t = "Herb and ore icons on the minimap optimized: the feature no longer uses any performance when neither tracking is active", fr = "Optimisation de la fonctionnalité des icônes d'herbes/minerais sur la minimap. Elle n'utilise plus aucune performance lorsqu'aucun des 2 pistages n'est actif" },
      { k = "li", lvl = 1, t = "[Forever] The Menu Bar did not open the First Aid page correctly with Ctrl+Alt+click on the Professions icon", fr = "[Forever] La barre de menu n'affichait pas correctement la page de Premiers Soins avec Ctrl+Alt+clic sur l'icône Métiers" },
      { k = "li", lvl = 1, t = "Previews in menus now use a background image", fr = "Les aperçus dans les menus utilisent maintenant une image de fond" },
      { k = "li", lvl = 1, t = "Element placement is now pixel perfect, and small objects render much sharper", fr = "Le placement des éléments est désormais « pixel perfect » et le rendu des petits objets est beaucoup plus net" },
      { k = "li", lvl = 1, t = "[Forever] The Outlaw spec has been renamed \"Combat\"", fr = "[Forever] La spé Hors-la-loi a été renommée « Combat »" },
      { k = "li", lvl = 1, t = "[Forever] Fire and Frost specs correctly show mana in the Central Circle", fr = "[Forever] Les spés Feu et Givre affichent correctement la mana dans le cercle central" },
      { k = "li", lvl = 1, t = "[Forever] Removed the Warrior \"Ignore Pain\" secondary resource circle, which doesn't exist in this version of the game", fr = "[Forever] Retrait du cercle de ressource secondaire du guerrier « Dur au mal », qui n'existe pas sur cette version du jeu" },
      { k = "li", lvl = 1, t = "FIX: secondary professions are named correctly in the tooltip of the Menu Bar Professions button", fr = "FIX : les métiers secondaires sont correctement nommés dans l'infobulle du bouton Métiers de la barre de menu" },
      { k = "li", lvl = 1, t = "FIX: heal prediction no longer worked with the new fill types of the Out-of-Combat Health Circle", fr = "FIX : le soin prévisionnel ne fonctionnait plus avec les nouveaux types de remplissage du Cercle de vie hors combat" },
      { k = "li", lvl = 1, t = "FIX: heal prediction was not shown in the Out-of-Combat Health Circle with a radial fill", fr = "FIX : les soins prévisionnels ne s'affichaient pas dans le Cercle de vie hors combat en remplissage radial" },
      { k = "li", lvl = 1, t = "[Forever] FIX: the Cast Bar correctly shows \"Opening\" instead of \"Opening - No text\"", fr = "[Forever] FIX : la barre de cast affiche correctement « Ouverture » au lieu de « Opening - No text »" },
      { k = "li", lvl = 1, t = "FIX: custom textures (SharedMedia_MyMedia) were not picked up", fr = "FIX : ajout des textures custom qui n'étaient pas prises en compte (SharedMedia_MyMedia)" },
      { k = "li", lvl = 1, t = "FIX: the bandage cooldown keeps showing correctly when entering combat", fr = "FIX : le cooldown des bandages continue de s'afficher correctement en entrant en combat" },
    },
  },
  {
    version = "4.4", date = "2026-10-14",
    lines = {
      { k = "h", link = { page = "modulesOverview" }, t = "Modules", fr = "Modules" },
      { k = "li", lvl = 1, t = "On the Modules page, every AishCore element reveals its position and hitbox.", fr = "Sur la page Modules, tous les éléments de l'AishCore révèlent leurs emplacements et leurs hitbox." },
      { k = "li", lvl = 1, t = "Hovering an element shows its name at its top left corner", fr = "Au passage de la souris, leur nom s'affiche en haut à gauche" },
      { k = "li", lvl = 1, t = "Right-clicking an element now opens its own settings section (not just the module page)", fr = "Clic droit sur un élément emmène directement à sa section de réglages (et plus seulement sur la page du module)" },
      { k = "li", lvl = 1, t = "Hovering an element's name in the Modules window highlights it on screen", fr = "Passer la souris sur le nom des éléments dans la fenêtre Modules les met en surbrillance" },
      { k = "li", lvl = 1, t = "The Location and AFK Screen modules are now in the EXTRAS section", fr = "Les modules Localisation et Ecran AFK sont maintenant dans la section EXTRAS" },

      { k = "h", link = { page = "resourceCircle" }, t = "Central Circle", fr = "Cercle Central" },
      { k = "li", lvl = 1, t = "New rendering engine for the resource arc: slightly lighter (barely noticeable, but still), and above all much smoother and fluid when values change!", fr = "Changement de moteur pour l'affichage de l'arc de ressource. Celui-ci sera un peu moins gourmand (presque imperceptible, mais quand même), et surtout beaucoup plus lisse et fluide lors des changements de valeurs !" },
      { k = "li", lvl = 1, t = "Secondary resource arcs get the same improvement, and some buffs can finally be shown as radial (Mana Tea, Consecration, Ironfur and more).", fr = "Les arcs de ressources secondaires bénéficient également de cette amélioration, et certains buffs peuvent enfin s'afficher en radial (Thé de mana, Consécration, Dur au mal, Fragments du vide, Report, Fer-poil)." },
      { k = "li", lvl = 1, t = "The Central Circle is now animated while the settings panel is open", fr = "Le cercle central est maintenant animé lorsque le panneau de réglage est ouvert" },
      { k = "li", lvl = 1, t = "External orbs too", fr = "Les orbes externes aussi" },
      { k = "li", lvl = 1, t = "Runes are no exception, and now recharge radially.", fr = "Les runes n'y échappent pas non plus, et se rechargeront de manière radiale." },
      { k = "li", lvl = 1, t = "Arc settings renamed to be easier to understand.", fr = "Renommage des différents réglages de l'arc, plus compréhensibles." },
      { k = "li", lvl = 1, t = "Arc settings are much finer and 1000 times more precise (literally)", fr = "Les réglages de l'arc sont beaucoup plus fins et 1000 fois plus précis (littéralement)" },
      { k = "li", lvl = 1, t = "The secondary resource arc gets all the new settings too", fr = "L'arc de ressource secondaire bénéficie également de tous les nouveaux réglages" },
      { k = "li", lvl = 1, t = "FIX: some secondary resource circles were not previewed while the settings panel was open", fr = "FIX : Certains cercles de ressources secondaires ne s'affichaient pas en aperçu lorsque le panneau de réglages était ouvert" },
      { k = "li", lvl = 1, t = "New color settings for the Central Circle (background, main text and resource arc)", fr = "Ajout de réglages supplémentaires pour les couleurs du cercle central (Arrière plan, Texte principal et Arc de ressource)" },
      { k = "li", lvl = 1, t = "[Forever] New secondary resource text for Hunter ammunition", fr = "[Forever] Ajout du texte de ressource secondaire pour les munitions du Chasseur" },
      { k = "li", lvl = 2, t = "\"Normal / Warning / Critical\" thresholds let you set several quantity levels, each with its own color", fr = "Des seuils \"Normaux / Alerte / Critiques\" permettent de régler différents niveaux de quantité et définir des couleurs différentes" },
      { k = "li", lvl = 2, t = "Low thresholds cannot go above high thresholds, and vice versa", fr = "Les seuils bas ne peuvent pas dépasser les seuils hauts, et inversement" },
      { k = "li", lvl = 2, t = "If the Normal and Critical thresholds are equal, the Warning threshold is ignored", fr = "Si le seuil Normal et Critique sont égaux, le seuil Alerte n'est pas pris en compte" },
      { k = "li", lvl = 1, t = "[Forever] New auto-attack swing timer", fr = "[Forever] Ajout d'un affichage du Délai d'Auto attaque" },
      { k = "li", lvl = 2, t = "Shown as a simple bar or as an arc", fr = "Cet affichage peut prendre la forme d'une barre simple ou d'un arc" },
      { k = "li", lvl = 2, t = "Both are configured separately (color, position, size, fill direction, etc.)", fr = "Les 2 sont réglables indépendamment (couleur, position, taille, sens de remplissage, etc)" },
      { k = "li", lvl = 2, t = "Melee and ranged attacks are both supported", fr = "Ces affichages supportent les attaques au corps à corps et à distance" },

      { k = "h", link = { page = "outOfCombat" }, t = "Out-of-Combat Circles", fr = "Cercles Hors-combat" },
      { k = "li", lvl = 1, t = "Settings panels reorganized", fr = "Réorganisation des panneaux de réglages" },
      { k = "li", lvl = 1, t = "Several fill modes for each circle", fr = "Ajout de plusieurs modes de remplissage pour chaque cercle" },
      { k = "li", lvl = 1, t = "Both circles get the same radial improvements as the Central Circle", fr = "Les 2 cercles profitent des mêmes améliorations du système radial que pour le cercle central" },
      { k = "li", lvl = 1, t = "Unit frames now hide while you edit the Out-of-Combat Circles settings", fr = "Dans les réglages des Cercles hors-combat, les cadres d'unités se cachent désormais" },
      { k = "li", lvl = 1, t = "The Out-of-Combat Circles are now animated", fr = "Les Cercles hors-combat sont maintenant animés" },

      { k = "h", link = { page = "outOfCombat", section = "SETTINGS_SEC_WELLFED" }, t = "Well Fed Circle", fr = "Cercle Bien Nourri" },
      { k = "li", lvl = 1, t = "New section in Out-of-Combat Circles > Well Fed Circle", fr = "Ajout d'une nouvelle section dans \"Cercles Hors-Combat\" > Cercle Bien Nourri" },
      { k = "li", lvl = 1, t = "A fully configurable circle shows up while you eat or drink", fr = "Un cercle entièrement configurable s'affichera lorsque vous consommerez une boisson ou de la nourriture" },
      { k = "li", lvl = 1, t = "If the food can give a buff, the circle changes color and an animation tells you when Well Fed is applied", fr = "Si jamais l'aliment est capable d'offrir un buff, le cercle changera de couleur et une animation apparaîtra pour vous signifier l'application du buff Bien Nourri" },
      { k = "li", lvl = 1, t = "The bonus stats given by the buff can be shown right next to the buff icon", fr = "Les gains de stats bonus offerts par le buff peuvent être affichés directement avec l'icône du buff" },

      { k = "h", link = { page = "priorityBar" }, t = "Priority Bar", fr = "Barre de rotation" },
      { k = "li", lvl = 1, t = "New feature that also highlights procs and important buffs on your spells. Handy for tanks and healers who have no real \"rotation\"", fr = "Ajout d'une nouvelle fonctionnalité permettant d'afficher également les surbrillances de procs et de buffs importants sur vos sorts. Pratique pour les tanks et les healers qui n'ont pas de véritables \"rotations\"" },
      { k = "li", lvl = 1, t = "These highlights can be styled separately from the rotation assistant ones", fr = "Ces surbrillances peuvent être réglées différemment de celles de l'assistance à la rotation" },
      { k = "li", lvl = 1, t = "An option enables these highlights only in Healer and Tank specs", fr = "Une option permet d'activer ces surbrillances seulement en spé Heal et Tank" },
      { k = "li", lvl = 1, t = "[Forever] Unlearned spells are no longer shown in the Priority Bar, but can still be configured", fr = "[Forever] Les sorts non appris ne s'afficheront plus dans la barre de rotation, mais peuvent quand même y être configurés." },

      { k = "h", link = { page = "xpBar" }, t = "XP Bar", fr = "Barre d'XP" },
      { k = "li", lvl = 1, t = "Hovering your level shows what the next level brings: health, resource, stats, and the new abilities from your class trainer.", fr = "Ajout des gains du prochain niveau au passage de la souris sur le niveau. Les gains comportent les points de vie, points de ressources, les stats, et les nouvelles compétences chez l'entraineur de votre classe." },
      { k = "li", lvl = 1, t = "Hold SHIFT while hovering your level to see the XP from quests ready to turn in", fr = "Ajout des gains d'XP des Quêtes à rendre au passage de la souris sur le niveau, en maintenant la touche MAJ enfoncée" },
      { k = "li", lvl = 1, t = "[Forever] Hold ALT while hovering your level to see the abilities you can train (unlocked but not learned)", fr = "[Forever] Ajout des Compétences à entraîner (débloquées mais non-apprises) au passage de la souris sur le niveau, en maintenant la touche ALT enfoncée" },
      { k = "li", lvl = 1, t = "[Forever] Abilities to train and upcoming abilities also include Pet (Hunter) and Demon (Warlock) abilities", fr = "[Forever] Les compétences à entraîner et les prochaines compétences débloquées comprennent également les compétences de Familiers (Chasseur) et de Démons (Démoniste)" },
      { k = "li", lvl = 1, t = "[Forever] All upcoming abilities and their cost up to level 60 are now known by the addon.", fr = "[Forever] Toutes les informations de prochaines compétences et leur prix respectif jusqu'au niveau 60 ont été appris par l'addon." },
      { k = "li", lvl = 1, t = "Stat gains can't be known in advance: we need data from a full level 1 to 60 journey for each class. If you'd like to help gather it and improve the addon, contact Aishuu on Discord!", fr = "Le gain de stats ne peut être connu à l'avance. Il nous faudra les données sur un périple entier de niveau 1 à 60, pour chaque classe. Si vous souhaitez participer à obtenir ces données pour améliorer l'addon, contactez Aishuu sur Discord !" },

      { k = "h", link = { page = "stealthMode" }, t = "Stealth Mode", fr = "Mode furtivité" },
      { k = "li", lvl = 1, t = "New optional setting in Themed Colors for Rogues and Druids: when checked, a new color scheme applies while the player is stealthed.", fr = "Ajout d'une option désactivable dans le module Couleurs Thématiques pour les classes Voleur et Druide. En cochant cette option, un nouveau schéma coloré s'appliquera lorsque le joueur sera camouflé.", link = { page = "colors" } },
      { k = "li", lvl = 1, t = "New \"Stealth Mode\" module in the EXTRAS section. It sets up a vignette that darkens the screen while you blend into the shadows. It should adapt to ultra wide resolutions, but I have no way to test it!", fr = "Ajout d'un module \"Mode Furtif\" dans la section Extras. Celui-ci permet de régler l'affichage d'un vignettage pour assombrir l'écran lorsque vous vous fondez dans les ombres. Cela devrait s'adapter aux résolutions ultra wide, mais je n'ai pas moyen de le tester !" },

      { k = "h", link = { page = "colors" }, t = "Themed Colors", fr = "Couleurs Thématiques" },
      { k = "li", lvl = 1, t = "Slight changes to pet health bar colors (Hunter and Warlock)", fr = "Modifications légères sur la couleur des barres de vie des familiers (Chasseur et Démoniste)" },
      { k = "li", lvl = 1, t = "2 new \"Conditions: Stealth\" color sets for Druid and Rogue", fr = "Ajout de 2 sets de couleurs \"Conditions : Furtivité\" pour le Druide et le Voleur" },

      { k = "h", link = { page = "unitBars" }, t = "Unit Frames", fr = "Cadres d'unités" },
      { k = "li", lvl = 1, t = "New settings to change the health bar colors (background and fill)", fr = "Ajout de réglages supplémentaires pour changer la couleur des barres de vie (Arrière plan et Couleur de remplissage)" },
      { k = "li", lvl = 1, t = "Second texture selector for the background (it only applied to the bar foreground before)", fr = "Ajout d'un deuxième sélecteur de textures pour l'arrière plan (ne concernait que le premier plan de la barre, auparavant)" },
      { k = "li", lvl = 1, t = "New option to show the target's level", fr = "Ajout d'une option pour afficher le niveau de la cible" },
      { k = "li", lvl = 1, t = "Just like the Top Target bar, the target level changes color with its difficulty", fr = "Tout comme la TopTarget, le niveau de la cible change de couleur suivant sa difficulté" },
      { k = "li", lvl = 1, t = "New option to show the player's first and last name when hovering their bar", fr = "Ajout d'une option pour afficher le prénom et le nom du joueur au survol de la souris sur sa barre" },
      { k = "li", lvl = 1, t = "Smooth show / hide animation for the player cast bar", fr = "Ajout d'une animation fluide à l'apparition / disparition de la barre de cast du joueur", link = { page = "castBar" } },
      { k = "li", lvl = 1, t = "3 new spark settings (the tip of the cast bar): texture (line, dot, spark, star), color and size", fr = "Ajout de 3 réglages de l'étincelle (l'extrémité de la barre de cast) : texture (ligne, point, étincelle, étoile), couleur, et taille", link = { page = "castBar" } },

      { k = "h", link = { page = "unitBars" }, t = "[Forever] Pet Happiness", fr = "[Forever] Satisfaction du Familier" },
      { k = "li", lvl = 1, t = "New pet happiness indicator. It turns Green, Yellow or Red when the pet is Happy, Content or Unhappy", fr = "Ajout d'un indicateur de Satisfaction de familier. Il devient Vert, Jaune ou Rouge suivant s'il est Heureux, Neutre ou Mécontent" },
      { k = "li", lvl = 1, t = "New alert (can be turned off) when your pet is Unhappy (in the Missing buffs module)", fr = "Ajout d'une alerte (désactivable) en cas de Mécontentement du familier (dans le module Buffs Manquants)", link = { page = "aurasMissingBuffs" } },
      { k = "li", lvl = 1, t = "Hovering the pet frame reveals its level and loyalty rank", fr = "Passer la souris sur le cadre du Familier révèle son niveau ainsi que son rang de Loyauté" },

      { k = "h", link = { page = "menuBar" }, t = "Menu Bar", fr = "Barre de menu" },
      { k = "li", lvl = 1, t = "New \"Menu Bar\" module (EXTRAS).", fr = "Création d'un nouveau module \"Barre de menu\" (Extras)." },
      { k = "li", lvl = 1, t = "This Menu Bar is fully customizable.", fr = "Cette Barre de menu est entièrement customisable." },
      { k = "li", lvl = 1, t = "Add, reorder and remove shortcuts right in the AishCore editor", fr = "Ajouter, réorganiser, supprimer des raccourcis directement avec l'éditeur AishCore" },
      { k = "li", lvl = 1, t = "Some shortcuts like Professions, Talents or Volume have extra features with click + key combinations.", fr = "Certains raccourcis comme les Métiers, les Talents ou encore le Volume ont des fonctionnalités supplémentaires avec des combinaisons de clic + touches clavier." },
      { k = "li", lvl = 1, t = "For example, the Professions shortcut:", fr = "Exemple, le raccourci Métiers :" },
      { k = "li", lvl = 2, t = "Left click: professions window, as before.", fr = "Clic gauche : panneau des métiers, comme avant." },
      { k = "li", lvl = 2, t = "Shift + click: profession 1.", fr = "Maj + clic : métier 1." },
      { k = "li", lvl = 2, t = "Ctrl + click: profession 2.", fr = "Ctrl + clic : métier 2." },
      { k = "li", lvl = 2, t = "Alt + click: Cooking.", fr = "Alt + clic : Cuisine." },
      { k = "li", lvl = 2, t = "Shift + Ctrl + click: Fishing.", fr = "Maj + Ctrl + clic : Pêche." },
      { k = "li", lvl = 2, t = "Ctrl + Alt + click: Archaeology.", fr = "Ctrl + Alt + clic : Archéologie." },
      { k = "li", lvl = 1, t = "Colors can follow the Themed Colors of your specialization.", fr = "Les couleurs peuvent reprendre les couleurs thématiques de votre spécialisation." },

      { k = "h", link = { page = "comfortQoL" }, t = "QOL", fr = "QOL" },
      { k = "li", lvl = 1, t = "New option to open the tracking menu by right-clicking the minimap", fr = "Ajout d'une option pour ouvrir le menu de pistage au clic droit sur la minimap" },
      { k = "li", lvl = 1, t = "New option to show herb and ore icons instead of the usual gold dot", fr = "[Forever]: Ajout d'une option pour afficher les icônes des plantes et des minerais au lieu du point doré habituel" },

      { k = "h", t = "Misc & Fixes", fr = "Divers & Correctifs" },
      { k = "li", lvl = 1, t = "The AishCore / AishUI logo is 30% bigger (no, you're not crazy)", fr = "La taille du logo AishCore / AishUI a été augmentée de 30% (non, vous n'êtes pas fou)" },
      { k = "li", lvl = 1, t = "[Forever] The family name is now shown on the AFK Screen", fr = "[Forever] Ajout du nom de famille dans l'écran AFK" },
      { k = "li", lvl = 1, t = "[Forever] FIX: the \"Summon pet\" alert could show even though no pet had been tamed", fr = "[Forever] FIX : L'alerte \"Invoquer un familier\" pouvait s'afficher alors même qu'aucun familier n'avait été apprivoisé", link = { page = "aurasMissingBuffs" } },
      { k = "li", lvl = 1, t = "[Forever] FIX: orb animations could fail to show when leaving Stealth", fr = "[Forever] FIX : Les animations des orbes pouvaient ne pas s'afficher en sortie de Camouflage", link = { page = "spellEffects" } },
      { k = "li", lvl = 1, t = "FIX: the XP Bar level badge could stay stuck on the previous level.", fr = "FIX : Le badge de niveau de la barre d'XP pouvait rester bloqué sur le niveau précédent." },
      { k = "li", lvl = 1, t = "FIX: cinematics during character creation made both AishCore reload alerts show up at once", fr = "FIX : Les cinématiques lors de la création de personnage causaient l'apparition des 2 alertes de rechargement de l'AishCore en même temps" },
      { k = "li", lvl = 1, t = "FIX: the click tolerance zone on unit frames is now disabled in some cases to avoid getting stuck: Vehicle, Pet Battle, Possession, Override bar (mini games, etc.)", fr = "FIX : La zone de tolérance du clic sur les cadres d'unités est maintenant désactivée dans certains cas, pour éviter les blocages. Désactivé en Véhicule, Combat de mascottes, Possession, Barre de remplacement (mini jeux, etc)" },
      { k = "li", lvl = 1, t = "FIX: the Rogue Subtlety spec was wrongly named in French", fr = "FIX : La spé Finesse du Voleur était nommée \"Subtilité\" par erreur." },
      { k = "li", lvl = 1, t = "FIX: \"Logos\" 3D animation combos could not be right-clicked to copy / paste animations", fr = "FIX : Les combos d'animations 3D \"Logos\" ne pouvaient pas recevoir de clic droit pour copier/coller les animations facilement", link = { page = "spellEffects" } },
      { k = "li", lvl = 1, t = "FIX: the XP bar texture was slightly enlarged to fill the full screen width", fr = "FIX : la texture de la barre d'expérience a été légèrement augmentée pour remplir totalement la largeur de l'écran" },
      { k = "li", lvl = 1, t = "FIX: opening a dropdown (e.g. font selection) near a window edge no longer cuts the menu", fr = "FIX : Ouvrir un menu déroulant (ex: Sélection de police) près d'un bord de fenêtre ne tronquera plus le menu" },
      { k = "li", lvl = 1, t = "FIX: aura tracking in Icon List mode now displays correctly with the \"Dual icon\" layout", fr = "FIX : Les suivis d'auras en Mode : Liste d'icônes s'affichent désormais correctement en mode \"double icône\"", link = { page = "aurasIconlist" } },
      { k = "li", lvl = 1, t = "FIX: Icon List icons are no longer stretched", fr = "FIX : Les icônes du Mode : Liste d'icônes ne seront plus déformées", link = { page = "aurasIconlist" } },
      { k = "li", lvl = 1, t = "FIX: aura tracking bars used the base class color, ignoring Themed Colors", fr = "FIX : La couleur des barres de suivis des auras prenait la couleur de base de la classe, sans tenir compte des Couleurs thématiques", link = { page = "aurasTracked" } },
      { k = "li", lvl = 1, t = "FIX: some buff tracking icon texts could cause missing font errors", fr = "FIX : Certains textes des icônes de Suivi de buffs pouvaient causer des erreurs de Polices introuvables" },
      { k = "li", lvl = 1, t = "New Glow settings for every aura tracking display \"Mode\", to customize each mode separately.", fr = "Ajout d'une option de réglage de Glow pour tous les \"Modes\" d'affichage de suivi d'auras, permettant de customiser séparément chaque mode.", link = { page = "aurasIconlist" } },
      { k = "li", lvl = 1, t = "The bar previews in the Dynamic Bars section stay pinned at the top of the window, so you can easily see your changes", fr = "Les aperçus des barres dans la section Barres dynamiques restent épinglés en haut de la fenêtre pour facilement apercevoir les changements effectués", link = { page = "extraBars" } },
    },
  },
  {
    version = "4.3", date = "2026-10-09",
    lines = {
      { k = "h", t = "Settings panel" },
      { k = "li", lvl = 1, t = "New smooth animations in the settings panel:" },
      { k = "li", lvl = 2, t = "sidebar sections and groups fold and unfold with a slide" },
      { k = "li", lvl = 2, t = "modules slide slightly to the right on hover" },
      { k = "li", lvl = 2, t = "backgrounds and colors fade in" },
      { k = "li", lvl = 2, t = "pages open with a fade" },
      { k = "li", lvl = 1, t = "All sidebar groups can now be collapsed, including the one holding the open page" },
      { k = "li", lvl = 1, t = "\"Group Number\" is now a collapsible section of the Integration page" },
      { k = "li", lvl = 1, t = "\"Cursor in combat\" is now a collapsible section of the QoL page" },
      { k = "li", lvl = 1, t = "The Rotation Button Module is placed right below the Priority Bar" },
      { k = "li", lvl = 1, t = "Smooth animation for the XP Bar when hovering the character level" },
      { k = "li", lvl = 1, t = "Another big optimization pass to further reduce the addon's memory impact" },
      { k = "h", t = "Modules page" },
      { k = "li", lvl = 1, t = "Right-click a module to open its settings, and unfold its section when there is one" },
      { k = "li", lvl = 1, t = "The module name changes color on hover" },
      { k = "li", lvl = 1, t = "\"Animations\" in the modules list are shortened to \"Anims\": \"Spell Anims\", \"Aura Anims\", \"Out-of-Combat Health Circle Anims\"..." },
      { k = "h", t = "Priority Bar" },
      { k = "li", lvl = 1, t = "Spells on cooldown no longer \"blink\" as if they were available and keep showing their cooldown" },
      { k = "li", lvl = 1, t = "Out-of-range spell icons get a nicer tint" },
      { k = "li", lvl = 1, t = "Highlighted spells stay desaturated when they lack the resource to be cast" },
      { k = "li", lvl = 1, t = "Opening the spellbook lets you drag and drop spells directly into the Priority Bar slots" },
      { k = "li", lvl = 1, t = "Dragging a spell out of the bar removes it" },
      { k = "li", lvl = 1, t = "Spells are now clickable in combat, with a limitation:" },
      { k = "li", lvl = 2, t = "Left click: casts the first spell of the slot" },
      { k = "li", lvl = 2, t = "Right click: casts the 2nd spell of the slot" },
      { k = "li", lvl = 2, t = "Middle click: casts the 3rd spell of the slot" },
      { k = "li", lvl = 1, t = "The keybind reminder is also shown in the tooltips (hold ALT)" },
      { k = "li", lvl = 1, t = "The Priority Bar comes to the foreground when the spellbook is open and shows a text and a shadow for better readability" },
      { k = "h", t = "Missing buffs" },
      { k = "li", lvl = 1, t = "When several spells can fix the same alert (weapon enchants, auras, poisons, pets, demons...), one clickable icon per choice is shown, side by side and centered" },
      { k = "li", lvl = 1, t = "Each icon casts its own spell" },
      { k = "li", lvl = 1, t = "The missing pet alert now also shows in combat and lets you resummon the pet by clicking it" },
      { k = "li", lvl = 1, t = "New alert when the pet is on Passive: clicking it sets the pet back to Assist" },
      { k = "li", lvl = 1, t = "Pet alerts do not show while mounted, nor out of combat unless you have an attackable target" },
      { k = "li", lvl = 1, t = "New alert for a missing Healthstone, only shown in instances out of combat, with an attackable target" },
      { k = "li", lvl = 1, t = "New alert for a missing Soulstone, only shown in instances out of combat, with an attackable target" },
      { k = "li", lvl = 1, t = "Forever: new list resolved by spell name, so it is valid at every rank and in every language. Alerts only show when the spell is known" },
      { k = "li", lvl = 1, t = "Forever: added Forever-specific reminders (Aspects, Trueshot Aura, Inner Fire, Thorns, Omen of Clarity, armors, Blessings, optional reminders, ammunition, soul shards) with adjustable thresholds" },
      { k = "li", lvl = 1, t = "Forever: removed Burning Rush and the Warlock section" },
      { k = "li", lvl = 1, t = "Forever: fixed weapon enchant and poison detection" },
      { k = "h", t = "QoL" },
      { k = "li", lvl = 1, t = "Graphics rendering options are now tied to the PC/account instead of the profile, so a shared profile does not carry them (disabled by default for others)" },
      { k = "li", lvl = 1, t = "The option to hide Horizon Suite when RestedXP is active also hides the Blizzard quest tracker" },
      { k = "li", lvl = 1, t = "New /aishuiswitch command to switch from the ElvUI version to EllesmereUI (and back)" },
      { k = "li", lvl = 1, t = "5 new options to push the graphics further:" },
      { k = "li", lvl = 2, t = "Object distance (lodObjectFadeScale 200)" },
      { k = "li", lvl = 2, t = "Distant objects (lodObjectCullSize 8)" },
      { k = "li", lvl = 2, t = "Distant terrain (terrainLodDist 1000)" },
      { k = "li", lvl = 2, t = "Reflections (reflectionMode 3)" },
      { k = "li", lvl = 2, t = "Weather density (weatherDensity 3)" },
      { k = "h", t = "Themed Colors" },
      { k = "li", lvl = 1, t = "Right-click a spec name to set it as the default spec of its class (crown icon). It is used when no spec can be determined (no spec, talent point, or tied trees on Forever). The last invested point no longer breaks ties (e.g. a 2/2/0 build)" },
      { k = "li", lvl = 1, t = "Low-level characters on Retail now use the default spec" },
      { k = "li", lvl = 1, t = "Forever: spec changes (first talent point, respec) now apply without a /reload" },
      { k = "li", lvl = 1, t = "Forever: removed Evoker, Demon Hunter, Monk and Death Knight from Themed Colors" },
      { k = "h", t = "Dynamic Bars" },
      { k = "li", lvl = 1, t = "Added equipped Trinkets to the tracked items" },
      { k = "li", lvl = 1, t = "Each Dynamic Bar now has a new \"Anchor (growth)\" option" },
      { k = "h", t = "Fixes" },
      { k = "li", lvl = 1, t = "While on a mount that can carry passengers, the click/hover tolerance zone on the health bar is disabled, making it easy to click mount NPCs" },
      { k = "li", lvl = 1, t = "FIX: the buttons of the reload window after installation no longer showed their text" },
      { k = "li", lvl = 1, t = "FIX: the font and outline of the info texts now update live on the XP Bar, without a /reload" },
      { k = "li", lvl = 1, t = "FIX: the resource text font of the Central Circle and the Resource Circle (Out of Combat) was not displayed with the right font in some cases" },
      { k = "li", lvl = 1, t = "The \"Trinkets\" module was removed (now handled through Dynamic Bars)" },
      { k = "li", lvl = 1, t = "The Character Sheet module has been disabled. It will come back prettier and stronger in a future version!" },
    },
  },
  {
    version = "4.2.3", date = "2026-10-07",
    lines = {
      { k = "li", lvl = 1, t = "\"Extra Bars\" have been renamed \"Dynamic Bars\"" },
      { k = "li", lvl = 1, t = "New option in Dynamic Bars: show the bandage cooldown directly on the icon (tied to the \"Recently Bandaged\" debuff)" },
      { k = "li", lvl = 1, t = "New Dynamic Bars visibility option: \"Injured or in combat\". Perfect for a health potion and bandage bar!" },
      { k = "li", lvl = 1, t = "New option \"Ignore Blizzard Rotation Assistant\" for the Priority Bar, to stop following the highlighted suggestions" },
      { k = "li", lvl = 1, t = "Sharper buff / debuff timer text on nameplates (Platynator integration), with new outline styles: Shadow, Thin + shadow, Thick + shadow" },
      { k = "li", lvl = 1, t = "New \"EXTRAS\" section containing:" },
      { k = "li", lvl = 2, t = "Command shortcuts: /cdm, /edit and /rl to open the Cooldown Manager, Edit Mode and reload the UI" },
      { k = "li", lvl = 2, t = "Option to automatically disable Horizon Suite while RestedXP is active" },
      { k = "li", lvl = 2, t = "Graphics rendering options" },
      { k = "li", lvl = 2, t = "Option to enlarge the merchant window (several pages at once, EllesmereUI skin supported)" },
      { k = "li", lvl = 1, t = "\"3D Animations\" is now a main sidebar section; \"Integration\" moved under EXTRAS" },
      { k = "li", lvl = 1, t = "Options tooltips now appear next to the cursor" },
      { k = "li", lvl = 1, t = "Forever: the Warlock secondary resource text now shows Soul Shards" },
      { k = "li", lvl = 1, t = "FIX: the pet name was sometimes \"Unknown\"" },
      { k = "li", lvl = 1, t = "FIX: Lua error related to the XP Bar font" },
      { k = "li", lvl = 1, t = "FIX: Platynator font could revert until a /reload" },
      { k = "li", lvl = 1, t = "FIX (Forever): the GCD was displayed and desaturated icons on the Priority Bar as if it were a real cooldown" },
      { k = "li", lvl = 1, t = "FIX (Forever): blocked action error on Totems in combat" },
    },
  },
  {
    version = "4.2.2", date = "2026-10-06",
    lines = {
      { k = "li", lvl = 1, t = "Fix: internal development files were mistakenly bundled in the release package" },
    },
  },
  {
    version = "4.2.1", date = "2026-10-06",
    lines = {
      { k = "li", lvl = 1, t = "Fix: Priority Bar and Rotation Button Module didn't show the keybind when the spell was bound through a macro" },
      { k = "li", lvl = 1, t = "Fix: the AishUI welcome popup and the Cooldown Manager prompt could overlap when both triggered on the same login" },
      { k = "li", lvl = 1, t = "Fix: EllesmereUI module auto-setup could silently fail to apply the right modules on first login, especially after a reinstall" },
      { k = "li", lvl = 1, t = "Added /aishsetup command to manually re-run the EllesmereUI/Platynator/ElvUI auto-setup if needed" },
    },
  },
  {
    version = "4.2", date = "2026-10-05",
    lines = {
      { k = "li", lvl = 1, t = "Installer now lets you choose between an ElvUI or EllesmereUI version of the interface; the choice affects which files get installed and the first setup steps on your next login" },
      { k = "li", lvl = 1, t = "AishCore automatically enables the EllesmereUI modules it needs" },
      { k = "li", lvl = 1, t = "AishCore automatically applies the ElvUI and Platynator profiles on your character's first login -- no more manual setup" },
      { k = "li", lvl = 1, t = "AishCore also imports the AishUI profile into Edit Mode" },
      { k = "li", lvl = 1, t = "Fix: every display mode had lost its Position X setting" },
      { k = "li", lvl = 1, t = "Fix: errors caused by missing fonts when using the EllesmereUI version" },
      { k = "h", t = "4.2" },
      { k = "li", lvl = 1, t = "The installer now warns when you try to install an AishUI version that isn't compatible with the selected WoW client" },
      { k = "li", lvl = 1, t = "Removed the CDMLoader addon dependency, replaced by an equivalent built into AishCore" },
      { k = "li", lvl = 1, t = "Memory optimizations and rare leak fixes -- footprint down from ~50MB to ~15MB" },
      { k = "li", lvl = 1, t = "New Cooldown Manager module: configure CDM spells without touching Auras to Track, and never run /cdm load again -- a configured profile is applied automatically on login and spec change" },
      { k = "li", lvl = 1, t = "Essential CDs and Utility CDs icons can now be spaced out" },
      { k = "li", lvl = 1, t = "Group Number now works correctly with EllesmereUI raid frames" },
      { k = "li", lvl = 1, t = "Profiles overhauled and optimized: import/export per module or module group" },
      { k = "li", lvl = 1, t = "SavedVariables fully optimized, cutting load times -- a full profile export used to weigh up to 6MB, now around 1.2MB" },
      { k = "li", lvl = 1, t = "Fix: crashes could occur on profile import/export" },
      { k = "li", lvl = 1, t = "AishCore can now hide Blizzard unit frames (Unit Frames > Health Bars)" },
      { k = "li", lvl = 1, t = "New Extra Bars module: dynamic, fully customizable action bars driven by keywords" },
      { k = "li", lvl = 1, t = "New Integration module:" },
      { k = "li", lvl = 2, t = "Player buffs zone opacity moved here; also works with EllesmereUI's buff bars" },
      { k = "li", lvl = 2, t = "Baganator fonts: change Baganator's font on EllesmereUI (disabled on ElvUI, which already overrides it)" },
      { k = "li", lvl = 2, t = "Platynator fonts: change the font used for the target level and buff/debuff timers" },
      { k = "li", lvl = 1, t = "Fix: the \"CHANGE STANCE\" alert no longer shows on characters unable to change stance" },
    },
  },
}

-- Detection automatique des liens : premier terme trouve dans la ligne (insensible a la casse ; les plus
-- longs d'abord pour que "target cast bar" passe avant "cast bar"). page = id de page du GUI, section =
-- cle de locale de l'en-tete a deplier (optionnel). Termes anglais (notes publiees) et francais.
ns.PatchNoteLinks = {
  { match = "barre d'incantation de la cible", page = "targetCastBar" },
  { match = "out-of-combat resource circle", page = "outOfCombat", section = "SETTINGS_SEC_OCRC" },
  { match = "out-of-combat health circle", page = "outOfCombat", section = "SETTINGS_SEC_HEALTH_CIRCLE" },
  { match = "rotation button module", page = "rotationHelper" },
  { match = "barre d'incantation", page = "castBar" },
  { match = "cercle de ressource", page = "resourceCircle" },
  { match = "cercle bien nourri", page = "outOfCombat", section = "SETTINGS_SEC_WELLFED" },
  { match = "bouton de rotation", page = "rotationHelper" },
  { match = "barre de rotation", page = "priorityBar" },
  { match = "auras de la cible", page = "targetAuras" },
  { match = "barres dynamiques", page = "extraBars" },
  { match = "cooldown manager", page = "cdmEssential" },
  { match = "well fed circle", page = "outOfCombat", section = "SETTINGS_SEC_WELLFED" },
  { match = "target cast bar", page = "targetCastBar" },
  { match = "buffs manquants", page = "aurasMissingBuffs" },
  { match = "resource circle", page = "resourceCircle" },
  { match = "auras à tracker", page = "aurasTracked" },
  { match = "auras to track", page = "aurasTracked" },
  { match = "health circle", page = "outOfCombat", section = "SETTINGS_SEC_HEALTH_CIRCLE" },
  { match = "cercle de vie", page = "outOfCombat", section = "SETTINGS_SEC_HEALTH_CIRCLE" },
  { match = "cadres d'unit", page = "unitBars" },
  { match = "themed colors", page = "colors" },
  { match = "barre de menu", page = "menuBar" },
  { match = "vol dynamique", page = "skyriding" },
  { match = "animations 3d", page = "spellEffects" },
  { match = "priority bar", page = "priorityBar" },
  { match = "missing buff", page = "aurasMissingBuffs" },
  { match = "modules page", page = "modulesOverview" },
  { match = "page modules", page = "modulesOverview" },
  { match = "target auras", page = "targetAuras" },
  { match = "dynamic bars", page = "extraBars" },
  { match = "stealth mode", page = "stealthMode" },
  { match = "localisation", page = "location" },
  { match = "couleurs th", page = "colors" },
  { match = "mode furtif", page = "stealthMode" },
  { match = "spell anims", page = "spellEffects" },
  { match = "barre d'xp", page = "xpBar" },
  { match = "unit frame", page = "unitBars" },
  { match = "extra bars", page = "extraBars" },
  { match = "afk screen", page = "afkMode" },
  { match = "cdm layout", page = "cdmLayout" },
  { match = "liste d'ic", page = "aurasIconlist" },
  { match = "skyriding", page = "skyriding" },
  { match = "icon list", page = "aurasIconlist" },
  { match = "cast bar", page = "castBar" },
  { match = "menu bar", page = "menuBar" },
  { match = "afk mode", page = "afkMode" },
  { match = "cran afk", page = "afkMode" },
  { match = "profiles", page = "profiles" },
  { match = "location", page = "location" },
  { match = "3d anim", page = "spellEffects" },
  { match = "profils", page = "profiles" },
  { match = "xp bar", page = "xpBar" },
  { match = "totem", page = "aurasTotems" },
}

-- Nouveautes par version MAJEURE (4.4, 4.5...), la plus recente en premier : icone "Bonus-Objective-Star"
-- devant leur categorie (barre laterale) et leur en-tete de section ; "worldquest-Capstone" devant les
-- categories qui contiennent une nouvelle section (containers). Seules les 2 premieres entrees comptent
-- (version actuelle + precedente). Une mineure (4.4.1...) AJOUTE ses nouveautes a l'entree de sa majeure.
-- Une nouvelle majeure s'insere en tete. Masquees d'office 30 jours apres la date de la 1re entree dans
-- ns.PatchNotes (cf. ns.NewBadgesShown).
ns.NewByVersion = {
  {
    version = "4.5",
    categories = { movementBuffs = true },
    containers = { resourceCircle = true, xpBar = true, aurasMissingBuffs = true, extraBars = true, comfortQoL = true },
    headers = {
      "SETTINGS_CAT_MOVEMENT_BUFFS", "SETTINGS_RC_ELITE_HEADER", "XP_TOAST_HEADER", "MISSINGBUFFS_SEC_ALERTS",
      "EXTRABARS_SEC_WHITELIST", "SETTINGS_COMFORT_AUTO_TURNIN", "SETTINGS_MAPREVEAL_TITLE",
    },
  },
  {
    version = "4.4",
    categories = { stealthMode = true, menuBar = true, patchNotes = true },
    containers = { outOfCombat = true, priorityBar = true, resourceCircle = true, comfortQoL = true },
    headers = {
      "SETTINGS_CAT_STEALTH_MODE", "SETTINGS_CAT_MENU_BAR", "SETTINGS_CAT_PATCH_NOTES",
      "SETTINGS_SEC_WELLFED", "SETTINGS_SEC_GLOW_PROCS", "SETTINGS_SEC_SWING", "SETTINGS_MMN_TITLE",
    },
  },
  {
    version = "4.3",
    categories = {},
    containers = { comfortQoL = true },
    headers = { "SETTINGS_COMFORT_SEC_INTERFACE" },
  },
}

-- Fusion des 2 dernieres majeures, lue par la barre laterale et les en-tetes
ns.NewInPatch = { categories = {}, containers = {}, headers = {} }
for i = 1, math.min(2, #ns.NewByVersion) do
  local v = ns.NewByVersion[i]
  for k in pairs(v.categories or {}) do ns.NewInPatch.categories[k] = true end
  for k in pairs(v.containers or {}) do ns.NewInPatch.containers[k] = true end
  for _, h in ipairs(v.headers or {}) do table.insert(ns.NewInPatch.headers, h) end
end

-- Les en-tetes ne connaissent que leur texte : comparaison sur le libelle localise, en majuscules.
local newHeaderTexts
function ns.IsNewHeader(text)
  if type(text) ~= "string" then return false end
  if not newHeaderTexts then
    newHeaderTexts = {}
    for _, key in ipairs(ns.NewInPatch.headers) do
      local s = ns.L and ns.L[key]
      if s then newHeaderTexts[s:upper()] = true end
    end
  end
  return newHeaderTexts[text:upper()] == true
end

-- nil si l'atlas manque sur ce client (rien n'est alors affiche).
-- size = hauteur ; la largeur suit les proportions de l'atlas.
-- contains : categorie qui contient une nouveaute (icone distincte).
local NEW_ATLAS, CONTAINS_ATLAS = "Bonus-Objective-Star", "worldquest-Capstone"
function ns.CreateNewBadge(parent, size, contains)
  local atlas = contains and CONTAINS_ATLAS or NEW_ATLAS
  local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
  if not info then return nil end
  local tex = parent:CreateTexture(nil, "OVERLAY")
  tex:SetAtlas(atlas)
  local ratio = (info.width and info.height and info.height > 0) and (info.width / info.height) or 1
  tex:SetSize(size * ratio, size)
  return tex
end

-- Bouton "Cacher / Montrer les nouveautes" (sous le numero de version du GUI) :
-- choix du compte Battle.net, jamais du profil : garde dans AishaddonDB._device[<hash du BattleTag>]
-- (ns.GetDeviceSettings, Modules/Comfort.lua). Un pack livre avec ma SavedVariable ne le transmet donc
-- pas aux joueurs. Le choix vaut pour la majeure en cours : la suivante repart sur la regle des 30 jours.
local badges = {}
local AUTO_HIDE_DAYS = 30

local function CurrentMajor()
  return ns.NewByVersion[1] and ns.NewByVersion[1].version
end

-- Date de sortie de la majeure en cours (champ date de ns.PatchNotes), en secondes ; nil si inconnue
local function ReleaseTime()
  local cur = CurrentMajor()
  for _, e in ipairs(ns.PatchNotes or {}) do
    if e.version == cur and e.date then
      local y, m, d = e.date:match("^(%d+)-(%d+)-(%d+)$")
      if y then return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) end
    end
  end
end

local function Device()
  local d = ns.GetDeviceSettings and ns.GetDeviceSettings()
  if not d then return nil end
  -- Anciens emplacements (racine de AishaddonDB, puis booleen sans version) : repris une fois puis retires
  local old = d.hideNewBadges
  if AishaddonDB and AishaddonDB._hideNewBadges ~= nil then
    old = AishaddonDB._hideNewBadges
    AishaddonDB._hideNewBadges = nil
  end
  if old ~= nil then
    d.newBadges = { version = CurrentMajor(), shown = not old }
    d.hideNewBadges = nil
  end
  return d
end

function ns.NewBadgesShown()
  local d = Device()
  local choice = d and d.newBadges
  if choice and choice.version == CurrentMajor() then return choice.shown end
  local t = ReleaseTime()
  if not t then return true end
  return (time() - t) < AUTO_HIDE_DAYS * 86400
end

-- onToggle(shown) : recale le porteur (libelle, point) ; applique tout de suite l'etat courant.
function ns.RegisterNewBadge(tex, onToggle)
  local entry = { tex = tex, onToggle = onToggle }
  badges[#badges + 1] = entry
  local shown = ns.NewBadgesShown()
  tex:SetShown(shown)
  if onToggle then onToggle(shown) end
end

function ns.SetNewBadgesShown(shown)
  local d = Device()
  if d then d.newBadges = { version = CurrentMajor(), shown = shown and true or false } end
  for _, e in ipairs(badges) do
    e.tex:SetShown(shown)
    if e.onToggle then e.onToggle(shown) end
  end
end

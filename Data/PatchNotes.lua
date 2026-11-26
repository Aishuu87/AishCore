-- Data/PatchNotes.lua : notes de version affichees dans la page "Patch Notes" du GUI (UI/PatchNotesPage.lua).
-- Plus recente en premier. Chaque ligne : { t = texte, k = "h" (titre de section) | "li" (puce), lvl = 1/2 }.
-- Champ optionnel `link = { page = "idDePage", section = "CLE_LOCALE_DU_HEADER" }` : rend la ligne cliquable.
-- `link = false` : pas de detection automatique sur cette puce.
-- Champ optionnel `fr` : texte affiche sur un client frFR (sinon `t`). Titres : leur `link` passe par l'icone a droite.
-- Sans `link`, les noms de modules connus (ns.PatchNoteLinks plus bas) sont detectes automatiquement.
local addonName, ns = ...

ns.PatchNotes = {
  {
    version = "4.8.2", date = "2026-11-26",
    lines = {
      { k = "h", link = { page = "actionBars" }, t = "Action Bars", fr = "Barres d’action" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "FIX: The new paging could make the Priority Bar keybindings jump in some cases", fr = "FIX : La nouvelle pagination pouvait faire sauter les raccourcis de la Barre de rotation dans certains cas." },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "FIX: Bar 1 now correctly switches to Prowl for Druids in Cat Form", fr = "FIX : La barre 1 basculera maintenant correctement en mode “Rôder” pour les Druides en forme de Félin." },
      { k = "h", link = { page = "aurasMissingBuffs" }, t = "Missing buffs", fr = "Buffs manquants" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "FIX: Sharpening stones are now always suggested, even when poison is applied to your weapons", fr = "FIX : Les pierres à aiguiser seront toujours proposées même si du poison est appliqué sur les armes." },
    },
  },
  {
    version = "4.8.1", date = "2026-11-25",
    lines = {
      { k = "h", link = { page = "actionBars" }, t = "Action Bars", fr = "Barres d’actions" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "FIX: Some textures were larger than the icon itself (trinket activation, highlight while assigning keybindings, new spell, etc.)", fr = "FIX : Certaines textures étaient plus larges que l’icone elle-même (activation de trinket, illumination lors de l’assignation de raccourcis, nouveau sort, etc)" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "FIX: Some texts could stay white even with the Themed Colors option enabled", fr = "FIX : Certains textes pouvaient rester en blanc même si l’option Couleurs Thématiques était activée" },
    },
  },
  {
    version = "4.8", date = "2026-11-25",
    lines = {
      { k = "h", t = "General", fr = "Général" },
      { k = "li", lvl = 1, link = false, t = "New! Clickable module outlines are now more subtle, use their Themed Colors and light up on hover. A reminder tells you that a right-click opens the settings of the selected element", fr = "Nouveau ! Les silhouettes cliquables des modules sont maintenant plus discrètes, s'affichent avec leurs couleurs thématiques, et s'illuminent quand on passe la souris dessus. Un rappel indique qu'un clic droit permet d'accéder aux réglages de l'élément sélectionné" },
      { k = "li", lvl = 1, link = false, t = "When an element is unlocked, you can now click it and move it with the arrow keys. SHIFT+Arrows moves it 10 px at a time. (Coming soon: a real, more complete Unlock Mode)", fr = "Lorsqu'un élément est déverrouillé, il est maintenant possible de cliquer dessus pour le déplacer à l'aide des flèches directionnelles. MAJ+Flèches permet de le déplacer de 10 px en 10 px. (À venir : un vrai Mode Déverrouillage plus complet)" },
      { k = "li", lvl = 1, link = false, t = "The \"New\" badges now show on the left of the module list, so the module names stay vertically aligned", fr = "Les badges « Nouveautés » s'affichent à gauche de la liste des modules pour que leurs noms restent bien alignés verticalement" },
      { k = "li", lvl = 1, link = false, t = "New! New \"Fx\" icons give direct access to the options to add, edit or delete the animations linked to auras or missing buffs", fr = "Nouveau ! De nouvelles icônes « Fx » permettent d'accéder directement aux options pour ajouter/modifier/supprimer les animations liées aux auras, ou buffs manquants" },
      { k = "li", lvl = 1, link = false, t = "New! Clickable sections give quick access to the options to add, edit or delete the animations linked to their modules (Out-of-Combat Health Circle, Well Fed Circle, Camping, Central Circle)", fr = "Nouveau ! Des sections cliquables permettent d'atteindre facilement les options pour ajouter/modifier/supprimer les animations liées aux modules correspondants (Cercle de vie hors combat, Cercle Bien Nourri, Campement, Cercle Central)" },
      { k = "li", lvl = 1, link = false, t = "Minor patch notes (vX.X.X) are now merged into the next major patch notes (vX.X). E.g. v4.6.1, v4.6.2 and v4.6.3 are merged into v4.7, and removed from the list once v4.7 is released", fr = "Les patch notes des versions mineures (vX.X.X) sont intégrées dans les patch notes majeures (vX.X) qui leur succèdent. Ex : v4.6.1, v4.6.2, v4.6.3 sont intégrées dans v4.7, et donc retirées de la liste une fois la v4.7 publiée" },

      { k = "h", link = { page = "actionBars" }, t = "Action Bars (New!)", fr = "Barres d'actions (Nouveau !)" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "Created the Action Bars module, in the Combat category", fr = "Création du module de Barres d'actions, dans la catégorie Combat" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "It covers the 8 Blizzard action bars and their paging (stances, forms, Skyriding)", fr = "Celui-ci comprend les 8 barres d'actions Blizzard, leur pagination (postures, formes, Vol dynamique)" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "The bars can also use the Themed Colors of your spec or stance", fr = "Les barres peuvent également prendre les couleurs thématiques de votre spé ou de votre posture" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "Display fades can be set up easily", fr = "Les fondus d'affichage peuvent être réglés simplement" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "A hover tolerance can also be added around the bars", fr = "Une tolérance au survol peut également être ajoutée autour des barres" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "Glows can be customized, with as many choices as for the Priority Bar", fr = "Les lueurs peuvent être modifiées et le choix est aussi étendu que pour la barre de rotation" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "Also handles the Totem, Stance and Pet bars", fr = "Gère également les barres de Totems, de Posture et de Familier" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "The Totem bar opens its flyouts by simply hovering the arrows, with a light animation", fr = "La barre de Totems affiche ses tiroirs avec un simple passage de la souris sur les flèches, et ils s'affichent avec une animation légère" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "The Visibility & opacity section offers 3 modes for a simpler setup:", fr = "La section Visibilité propose 3 modes pour une configuration simplifiée :" },
      { k = "li", lvl = 2, link = { page = "actionBars" }, t = "Normal mode: shows the bars at full opacity when you are injured, in combat, have a target, are on a flying mount or hover them. The \"idle\" opacity can be adjusted", fr = "Mode Normal : affiche les barres en pleine opacité lorsque vous êtes blessé, en combat, en train de cibler, en monture volante ou au survol de la souris. L'opacité « au repos » peut être réglée" },
      { k = "li", lvl = 2, link = { page = "actionBars" }, t = "Discreet mode: only shows the bars on mouseover", fr = "Mode Discret : affiche les barres seulement au survol de la souris" },
      { k = "li", lvl = 2, link = { page = "actionBars" }, t = "Advanced mode: a new conditions section opens and lets you choose how the bars behave", fr = "Mode Avancé : une nouvelle section de conditions s'ouvre et vous laisse choisir comment les barres se comportent" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "Bars can be gathered into Groups to create \"super bars\":", fr = "Les barres peuvent être réunies en Groupes, pour créer des « super barres » :" },
      { k = "li", lvl = 2, link = { page = "actionBars" }, t = "The visibility of all the bars of a group is linked. E.g. hovering one bar shows the other bars of the group at the same time", fr = "La visibilité de toutes les barres du groupe est liée. Ex : passer la souris sur une barre affichera les autres barres du groupe en même temps" },
      { k = "li", lvl = 2, link = { page = "actionBars" }, t = "Settings changed on one bar of the group apply to all the other bars (font, colors, etc.)", fr = "Les réglages d'une barre du groupe s'appliquent à toutes les autres barres (police, couleurs, etc.)" },
      { k = "li", lvl = 2, link = { page = "actionBars" }, t = "Groups can be renamed", fr = "Les groupes peuvent être renommés" },

      { k = "h", link = { page = "colors" }, t = "Themed Colors", fr = "Couleurs Thématiques" },
      { k = "li", lvl = 1, link = { page = "colors" }, t = "New option for Druids: \"Form Mode\" colors the interface based on your shapeshift form rather than your specialization", fr = "Nouvelle option pour les Druides : « Mode Formes » permet de colorer thématiquement suivant les formes adoptées plutôt que les spécialisations" },

      { k = "h", link = { page = "comfortQoL" }, t = "QoL", fr = "QoL" },
      { k = "li", lvl = 1, link = { page = "visibility" }, t = "New! Added an option to set the opacity of party and raid frames out of combat (Party and raid frames opacity)", fr = "Nouveau ! Ajout d'une option pour régler l'opacité des cadres de groupe et de raid hors combat" },
      { k = "li", lvl = 1, link = { page = "visibility" }, t = "FIX: The buff bar did not show again on hover when its out-of-combat opacity was set to 0", fr = "FIX : La barre de buffs ne se réaffichait pas au survol si l'opacité hors combat était réglée sur 0" },
      { k = "li", lvl = 1, link = { page = "comfortRender" }, t = "New! Added the Distant terrain, Distant buildings, Horizon distance, Shadow resolution, Water ripples and Sun shafts options", fr = "Nouveau ! Ajout des options de Terrain lointain, Bâtiments lointains, Distance de l'horizon, Résolution des ombres, Remous de l'eau, et Rayons de soleil" },
      { k = "li", lvl = 1, link = { page = "comfortRender" }, t = "Added sliders for the Graphics rendering options", fr = "Ajout de curseurs de réglages pour les options du Rendu Graphique" },
      { k = "li", lvl = 1, link = { page = "actionBars" }, t = "The Totem bar is now handled in the Action Bars", fr = "La barre de Totems est maintenant gérée dans les Barres d'actions" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "New! Right-clicking a crafting reagent in your bags opens the matching profession and automatically filters the recipes craftable with that item (Right-click reagents in bags)", fr = "Nouveau ! Clic droit sur un objet de craft dans les sacs ouvre le panneau du métier correspondant et applique un filtre automatique de recettes fabricables avec cet objet" },
      { k = "li", lvl = 1, link = { page = "castBars" }, t = "New! New option (on by default) to show the total duration of a crafting queue (Total Craft Time). The bar still fills item by item", fr = "Nouveau ! Nouvelle option (activée par défaut) pour afficher la durée totale d'une file d'attente de fabrication. La barre se remplit toujours pour chaque objet, à l'unité" },

      { k = "h", link = { page = "taxiMode" }, t = "Taxi Mode", fr = "Mode Taxi" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "FIX: Early landings at later stops now work correctly", fr = "FIX : Les arrêts prématurés à des étapes ultérieures se font maintenant correctement" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Flight durations have been reworked and should be calculated more accurately. If a flight doesn't have the right duration the first time, the addon should \"learn\" it for the next trips", fr = "Révision des durées de trajets qui devraient être mieux calculées. Si un trajet n'a pas la bonne durée la première fois, l'addon devrait « l'apprendre » pour les prochains voyages" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "FIX: Pets shown in the party frames should now also hide during the flight", fr = "FIX : Les familiers affichés dans le groupe devraient eux aussi se cacher durant le vol" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "An option switches the Elapsed time to remaining time (Show remaining time). The remaining time also adapts to early landings at stops when needed", fr = "Une option permet de basculer le Temps écoulé en « Temps restant ». Le Temps restant s'adapte aussi aux arrêts prématurés aux étapes, au besoin" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "FIX: Group invites and the ready check window now stay visible in Taxi Mode", fr = "FIX : Les invitations de groupe et fenêtres d'Appel resteront visibles en Mode Taxi" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "[Forever] FIX: \"Rives Claires\" is now capitalized", fr = "[Forever] FIX : « Rives Claires » s'écrit maintenant avec une majuscule" },

      { k = "h", link = { page = "xpBar" }, t = "XP Bar", fr = "Barre d'XP" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "FIX: The Mail, Plate Mail, Parry, Dual Wield and Lockpicking skills could stay listed in the skills to buy even when the player already knew them", fr = "FIX : Les compétences de Mailles, Armure en plaques, Parade, Ambidextrie et Crochetage pouvaient rester affichées dans les compétences à acheter même si elles étaient déjà connues du joueur" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "Hover information now stays displayed a little longer after the cursor leaves", fr = "Les informations au survol s'afficheront un peu plus longtemps après avoir quitté le survol" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "[Forever] Rogue: Mutilate is no longer listed in the \"next skills\" outside the Assassination spec", fr = "[Forever] Voleur : Estropier ne fera plus partie des « prochaines compétences » en dehors de la spé Assassinat" },

      { k = "h", link = { page = "wellFed" }, t = "Well Fed Circle", fr = "Cercle bien nourri" },
      { k = "li", lvl = 1, link = { page = "wellFed" }, t = "When the player eats and drinks at the same time, a second small circle shows the drink's duration", fr = "Lorsque le joueur mange et boit en même temps, un deuxième petit cercle s'affiche pour afficher la durée de la boisson" },

      { k = "h", link = { page = "resourceCircle" }, t = "Central Circle", fr = "Cercle central" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "[Forever] Shaman: Added support for Water Shield (Charges)", fr = "[Forever] Chaman : Ajout du support du Bouclier d'eau (Charges)" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "Hovering the mana text now shows the player's exact mana value", fr = "Passer la souris sur le texte de mana affichera désormais la valeur exacte de la mana du joueur" },

      { k = "h", link = { page = "unitBars" }, t = "Unit Frames", fr = "Cadres d'unités" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New! The Top Target and Target Auras are now gathered in the same \"Health Bars\" module, and share the same settings interface", fr = "Nouveau ! La TopTarget et les Auras Cibles sont maintenant réunies dans le même module « Barres de vie » et profitent de la même interface de réglage" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "FIX: The Top Target resource bar was no longer working", fr = "FIX : La barre de ressource de la TopTarget n'était plus fonctionnelle" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "Added options to show the unit's Resource Bar", fr = "Ajout d'options pour afficher la barre de ressource de l'unité" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "Target Auras (Top Target) can now be moved by drag and drop (while the settings panel is open)", fr = "Les auras cibles (TopTarget) peuvent désormais être déplacées en cliqué/déposé (quand le panneau de réglage est ouvert)" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "The X and Y position sliders of Target Auras now accept much larger values", fr = "Les glissières de position X et Y des auras cibles peuvent maintenant accepter des valeurs beaucoup plus grandes" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New! Added a new customizable icon for units in PvP mode (PvP Mode)", fr = "Nouveau ! Ajout d'une nouvelle icône réglable pour les unités en mode JcJ" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "Added a customizable option for the Top Target PvP marker", fr = "Ajout d'une option réglable pour le marqueur JcJ de la TopTarget" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "An option lets you swap the decorative shapes for the icon in PvP mode (Replace decorative shapes in PvP mode)", fr = "Une option permet d'alterner les formes décoratives avec l'icône en mode JcJ" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New! Added a new option to show a glow when the player can dispel the debuff (Highlight dispellable debuffs)", fr = "Nouveau ! Ajout d'une nouvelle option pour afficher une lueur si le joueur peut dissiper le débuff" },
      { k = "li", lvl = 1, link = { page = "outOfCombat" }, t = "The Glow also shows on the player's and pet's Out-of-Combat Health Circles", fr = "La Lueur s'affiche également pour les cercles de vie hors combat du joueur et du familier" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "FIX: The glow should no longer show on neutral and enemy targets", fr = "FIX : La lueur ne devrait plus s'afficher pour les cibles neutres et ennemies" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "The level on the target, focus, target of target and Top Target health bars now uses the same colors as Platynator:", fr = "Les niveaux des barres de vie de la cible, focus, cible de la cible, et TopTarget s'affichent avec les mêmes couleurs que Platynator :" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Gray: the target no longer grants experience", fr = "Gris : si la cible ne rapporte plus d'expérience" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Green: the target is 3 to 8 levels below you", fr = "Vert : si la cible est entre -3 et -8 niveaux" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Yellow: -2 to +2", fr = "Jaune : de -2 à +2" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Orange: +3 and +4", fr = "Orange : +3 et +4" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Red: +5 and ??", fr = "Rouge : +5 et ??" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New options in the Health Bars (and Top Target) color the level, the name and the bar by difficulty", fr = "De nouvelles options dans les barres de vie (et TopTarget) permettent de colorer le niveau, le nom, et la barre suivant la difficulté" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New options in the Health Bars (and Top Target) color the level, the name and the bar by reaction (hostile, friendly, neutral)", fr = "De nouvelles options dans les barres de vie (et TopTarget) permettent de colorer le niveau, le nom, et la barre suivant la réaction (hostile, allié, neutre)" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "Reaction and difficulty colors can be customized", fr = "Les couleurs des réactions et de la difficulté peuvent être modifiées" },

      { k = "h", link = { page = "priorityBar" }, t = "Priority Bar", fr = "Barre de rotation" },
      { k = "li", lvl = 1, link = { page = "priorityBar" }, t = "FIX: Victory Rush stays grayed out in the Priority Bar until the Victorious buff is active", fr = "FIX : Ivresse de la victoire reste grisée dans la Barre de Rotation tant que le buff Élan victorieux n'est pas actif" },

      { k = "h", link = { page = "spellEffects" }, t = "3D Animations", fr = "Animations 3D" },
      { k = "li", lvl = 1, link = { page = "spellEffects" }, t = "Deleting a custom tag is now much easier: the cross on the right of the tag deletes it, after a confirmation message", fr = "Il est maintenant bien plus simple de supprimer un Tag personnalisé : la croix à droite du tag permet de le supprimer, et un message de confirmation s'affiche" },
      { k = "li", lvl = 1, link = { page = "spellEffects" }, t = "Right-clicking an asset in the library lets you add it to a new tag", fr = "En faisant un clic droit sur un asset de la bibliothèque, l'asset peut être ajouté à un nouveau tag" },

      { k = "h", link = { page = "extraBars" }, t = "Dynamic Bars", fr = "Barres dynamiques" },
      { k = "li", lvl = 1, link = { page = "extraBars" }, t = "Added the other usable equipment to the \"Trinkets\" category. Some armor pieces work the same way (helm, etc.)", fr = "Ajout des autres équipements utilisables dans la catégorie « Bijoux ». Certaines pièces d'armure fonctionnent de la même façon (heaume, etc.)" },
      { k = "li", lvl = 1, link = { page = "extraBars" }, t = "[Forever] FIX: The Greater Healthstone was not recognized", fr = "[Forever] FIX : La pierre de soins supérieure n'était pas reconnue" },
      { k = "li", lvl = 1, link = { page = "extraBars" }, t = "[Retail] FIX: Better detection of Profession knowledge items (thanks TheDooft!)", fr = "[Retail] FIX : Meilleure détection des objets de Connaissances de Profession (merci TheDooft !)" },

      { k = "h", link = { page = "campfire" }, t = "Camping HUD", fr = "Campement HUD" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "New! Added tracking of the time needed to get the Well Rested buffs (Sleeping Bag)", fr = "Nouveau ! Ajout du suivi de la durée nécessaire à l'obtention des buffs Bien reposé (Sac de couchage)" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "This tracking is shown as a green bar on the Camping HUD", fr = "Le suivi est représenté par une barre verte sur le Camping HUD" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "The Sleeping Bag bar can show at the same time as the time needed to gain the camp buffs", fr = "La barre de sac de couchage peut s'afficher en même temps que la durée nécessaire aux gains de buffs de campement" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "Well Rested stacks show at the bottom of the diamond by default", fr = "Les stacks du buff Bien reposé s'affichent en bas du losange par défaut" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "[Forever] FIX: Some cases where the Sleeping Bag HUD did not start (some villages)", fr = "[Forever] FIX : Certains cas où le HUD du sac de couchage ne se lançait pas (certains villages)" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "[Forever] Added the Campfire Kit to the list of camping items", fr = "[Forever] Ajout du Kit de Feu de Camp à la liste des objets de campement" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "[Forever] FIX: Higher items that can replace lower ones (Tanning Rack > Camp Tent) now show their real names in the buff tooltips", fr = "[Forever] FIX : Les objets supérieurs capables de remplacer les objets inférieurs (Râtelier de Tannage > Tente de camp) affichent leurs véritables noms dans le survol des buffs" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "[Forever] FIX: Sleeping Bag detection is now much more reliable (Blizzard added a \"buff\" for this specific condition)", fr = "[Forever] FIX : La détection du sac de couchage est beaucoup plus robuste (Blizzard a ajouté un « buff » pour cette condition spécifiquement)" },

      { k = "h", link = { page = "fishing" }, t = "Fishing (New!)", fr = "Pêche (Nouveau !)" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "New \"Fishing\" page in the HUD category", fr = "Création d'une nouvelle page « Pêche » dans la catégorie HUD" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "When a fishing pole is equipped, only the Well Rested (Sleeping Bag) alert is offered", fr = "Quand une canne à pêche est équipée, seule l'alerte de Bien reposé (Sac de couchage) est proposée" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "Fishing accessories are offered in the Missing buffs alerts. A dedicated column enables or disables specific lures", fr = "Les accessoires de pêche sont proposés dans les Alertes de buffs manquants. Une colonne spéciale permet d'activer ou désactiver certains appâts" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "FIX: Missing buffs alerts also offered fishing gear that cannot be used at your current Fishing skill", fr = "FIX : Les alertes de buffs manquants affichaient également l'équipement de pêche inutilisable au niveau de compétence de pêche actuel" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "The \"Double right-click: fish\" option moved to the new Fishing section", fr = "L'option du double clic droit pour lancer la canne à pêche a été déplacée dans la nouvelle section Pêche" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "An option lowers music and ambience volumes while fishing. Volume returns to normal after an adjustable fade duration", fr = "Une option permet de baisser le volume de la musique et des sons d'ambiance pendant la pêche. Le volume revient à la normale après une durée réglable de fondu sonore" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "Added an option to set a shortcut key to cast your line and reel it in (Cast / reel in shortcut)", fr = "Ajout d'une option pour définir une touche raccourcie pour Lancer la ligne et Relever l'hameçon" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "Added an option to enable background sound while fishing. Once you stop fishing, background sound goes back to its original behavior", fr = "Ajout d'une option pour activer le son en arrière-plan pendant la pêche. Une fois la pêche terminée, le son en arrière-plan reprend son comportement initial" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "An adjustable bubble shows the lure duration, and hovering it shows the lure's information", fr = "Une bulle réglable permet d'afficher la durée des appâts, et le survol affiche les informations de cet appât" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "The bubble also shows your Fishing skill and the total of the applied bonuses", fr = "La bulle permet également d'afficher la compétence de Pêche et le total des bonus appliqués" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "The bubble can float like a fishing bobber", fr = "La bulle peut être animée comme un flotteur" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "The buff bubble shows when you have usable lures in your bags, with a \"+\" inside", fr = "La bulle de buff s'affiche si le joueur possède des appâts équipables dans le sac, avec un « + » en son sein" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "Hovering the buff bubble shows every available and usable lure in your bags, including the one already applied, so you can refresh the buff", fr = "Passer la souris sur la bulle de buff affiche tous les appâts disponibles et utilisables dans les sacs, y compris ceux déjà appliqués afin de pouvoir rafraîchir le buff" },
      { k = "li", lvl = 1, link = { page = "fishing" }, t = "When you start moving, a round button re-equips the weapons you had before the fishing pole", fr = "Au moment de se déplacer, un bouton circulaire permet de reprendre les armes qui étaient équipées avant la canne à pêche" },

      { k = "h", link = { page = "aurasTracked" }, t = "Auras to Track", fr = "Suivis d'auras" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "A tracked aura without a duration now shows a full bar instead of an empty one", fr = "Lorsqu'une aura sans durée est suivie, celle-ci affiche une barre totalement pleine plutôt que vide" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "Circle Bars now show at the same time as the Central Circle. Previously, they only showed in combat", fr = "Les Barres de cercle s'affichent en même temps que le Cercle Central. Auparavant, elles ne s'affichaient qu'en combat" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Retail] Rogue: Circle Bars shifted when using Shadow Dance", fr = "[Retail] Voleur : Les barres de cercle se décalaient à l'utilisation de Danse de l'ombre" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "[Forever] Shaman: Added support for Strength of Earth Totem (Rank 4)", fr = "[Forever] Chaman : Ajout du support pour le Totem de Force (Rang 4)" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Forever] Warlock: Demonic Brand is now treated as a debuff, and its tracking should work properly", fr = "[Forever] Démoniste : La Marque Démoniaque est maintenant considérée comme un debuff, et son suivi devrait fonctionner correctement" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Forever] Mage: Arcane Blast is now treated as a debuff, and its tracking should work properly", fr = "[Forever] Mage : La Déflagration des Arcanes est maintenant considérée comme un debuff, et son suivi devrait fonctionner correctement" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "Hunter: Aspects can now be tracked correctly", fr = "Chasseur : Les aspects peuvent maintenant être suivis correctement" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "[Forever] Hunter: Added tracking for Summon Hawk (treated as a Totem)", fr = "[Forever] Chasseur : Ajout du suivi d'Invocation de faucon (considéré comme un Totem)" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "[Forever] Hunter: Summon Hawk correctly shows several bars when several hawks are summoned (thanks Lex!)", fr = "[Forever] Chasseur : L'Invocation du Faucon affiche correctement plusieurs barres s'il y a plusieurs faucons invoqués (merci Lex !)" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "Reworked the look of totems: position, bar height, timer", fr = "Rework du look des totems : position, hauteur de barre, timer" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "[Forever] Shaman: All totems are now colored", fr = "[Forever] Chaman : Colorisation de tous les totems" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "[Forever] Shaman: Totems without a cooldown have been removed from the utility CDs (shown at the bottom of the screen, normally meant for spells on cooldown)", fr = "[Forever] Chaman : Les totems sans CD ont été retirés des CDs utilitaires (affichage en bas de l'écran, dédié normalement à la visualisation des sorts en recharge)" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "A new technique finally shows whether the player is in range of their totems, in combat too. Out-of-range totems are desaturated. In instances, the distance to your totems still cannot always be known", fr = "Une nouvelle technique permet enfin d'indiquer si le joueur est à portée de ses totems ou non, valable en combat. Les totems hors de portée sont désaturés. En instance, il n'est toujours pas possible de connaître l'éloignement de ses totems" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "Hovering the icons or bars of tracked auras shows them at 100% opacity", fr = "Passer la souris sur les icônes ou barres des auras trackées les affiche à 100% d'opacité" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "Totem bars are now \"pixel perfect\" (all the same size, and display correctly even when very thin)", fr = "Les barres des totems sont maintenant « pixel perfect » (toutes de la même taille, et s'affichent correctement même très fines)" },

      { k = "h", link = { page = "aurasMissingBuffs" }, t = "Missing buffs", fr = "Buffs manquants" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "The Sleeping Bag alert now shows first, and even shows in rested areas when the \"Ignore in rested areas\" option is enabled", fr = "L'alerte du Sac de couchage s'affiche en priorité, et s'affiche même en zone de repos lorsque l'option « Ignorer en zone de repos » est activée" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "The Sleeping Bag alert no longer shows when your Sleeping Bag is on cooldown and you are not in a group (to borrow one)", fr = "L'alerte du Sac de couchage ne se montre plus si votre Sac de couchage est en recharge et que vous n'êtes pas dans un groupe (pour en emprunter un)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Retail] FIX: The Soulstone alert no longer shows while the spell is on cooldown", fr = "[Retail] FIX : L'alerte Pierre d'âme ne s'affiche plus pendant que le sort est en recharge" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] Added the Soul Link alert. It only shows when you have a demon summoned", fr = "[Forever] Ajout de l'alerte pour Lien Spirituel. Celle-ci ne s'affiche que si vous avez un démon invoqué" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] Added an independent duration threshold for the following buffs:", fr = "[Forever] Ajout de seuils de durée indépendants pour les buffs suivants :" },
      { k = "li", lvl = 2, link = { page = "aurasMissingBuffs" }, t = "Well Rested", fr = "Bien reposé" },
      { k = "li", lvl = 2, link = { page = "aurasMissingBuffs" }, t = "Thorns (Druid)", fr = "Épines (Druide)" },
      { k = "li", lvl = 2, link = { page = "aurasMissingBuffs" }, t = "Inner Fire (Priest)", fr = "Feu intérieur (Prêtre)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] Shaman: Added Water Shield to the missing buff alerts", fr = "[Forever] Chaman : Ajout du Bouclier d'eau dans les alertes de buffs manquants" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Right-clicking to hide an alert now only hides the first alert, the next ones show one after another", fr = "Clic droit pour masquer l'alerte masque seulement la première alerte, les suivantes s'affichent à la suite" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Water Breathing and Swim Speed elixirs are now only suggested while the player is swimming", fr = "Les Élixirs de respiration aquatique et d'augmentation de vitesse de nage sont proposés seulement lorsque le joueur est en train de nager" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Cat's Eye elixirs (stealth detection) are no longer suggested as regular elixirs", fr = "Les Élixirs d'Œil de Chat (détection du camouflage) ne sont plus proposés comme des Élixirs classiques" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Noggenfogger Elixir is no longer suggested by the Missing buffs alerts", fr = "L'Élixir de Noggenfogger n'est plus proposé par les alertes de buffs manquants" },

      { k = "h", t = "Fixes", fr = "Correctifs" },
      { k = "li", lvl = 1, link = { page = "priorityBar" }, t = "FIX: Revenge, Overpower, Riposte, Counterattack and Mongoose Bite showed as available in the Priority Bar even though the spells did not meet their usability conditions", fr = "FIX : Revanche, Fulgurance, Riposte, Contre-attaque, Morsure de la mangouste s'affichaient comme disponibles dans la barre de rotation alors même que les sorts manquaient leurs conditions pour être utilisables" },
      { k = "li", lvl = 1, link = false, t = "FIX: Some disabled modules could block mouse clicks even when hidden", fr = "FIX : Certains modules désactivés pouvaient bloquer les clics de la souris même cachés" },
      { k = "li", lvl = 1, link = false, t = "FIX: Errors related to some tooltip reading conditions when leaving combat", fr = "FIX : Erreurs liées à certaines conditions de lecture d'infobulles en sortie de combat" },
      { k = "li", lvl = 1, link = false, t = "FIX: The tracking menu now opens on the minimap, even when the minimap has been moved", fr = "FIX : Le menu des pistages s'ouvre sur la minimap, même si celle-ci a été déplacée" },
      { k = "li", lvl = 1, link = false, t = "FIX: Performance optimization when shapeshifting (Druid) and entering Stealth (Rogue), which could sometimes cause slowdowns", fr = "FIX : Optimisation des performances lors du morphing (Druide) et de l'entrée en Furtivité (Voleur), qui pouvaient parfois causer des ralentissements" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "[Forever] Shaman: Water Shield / Lightning Shield charges now show correctly during the first fight after a UI reload", fr = "[Forever] Chaman : Les charges de bouclier d'eau/foudre s'affichent correctement lors du premier combat après un rechargement de l'interface" },
      { k = "li", lvl = 1, link = false, t = "Optimized the minimap tooltips, which could cause slowdowns when hovering repeatedly", fr = "Optimisation des infobulles de la minicarte, qui pouvaient causer des ralentissements lors de passages répétés de la souris" },
      { k = "li", lvl = 1, link = { page = "addonCompartment" }, t = "Support for Questie, which added dozens of fake entries to the Addon Compartment", fr = "Support de Questie qui ajoutait des dizaines de fausses entrées dans le compartiment d'addons" },
    },
  },
  {
    version = "4.7", date = "2026-11-13",
    lines = {
      { k = "h", t = "General", fr = "Général" },
      { k = "li", lvl = 1, link = false, t = "The /aishsetup command gives a bit more information in the chat", fr = "La commande /aishsetup donne un peu plus d'informations dans le tchat" },
      { k = "li", lvl = 1, link = false, t = "New! The search bar shows several suggestions as you type", fr = "Nouveau ! La barre de recherche affiche plusieurs suggestions au fur et à mesure de la frappe" },
      { k = "li", lvl = 1, link = false, t = "Clicking a suggestion takes you to the exact section of the settings, and highlights the searched term", fr = "Cliquer sur une des suggestions emmène vers la section exacte des réglages, et met en surbrillance le terme recherché" },

      { k = "h", link = { page = "colors" }, t = "Themed Colors", fr = "Couleurs Thématiques" },
      { k = "li", lvl = 1, link = { page = "colors" }, t = "New! A \"Stance Mode\" option is now available for Warriors. It colors the interface based on your stance, rather than your character's specialization", fr = "Nouveau ! Une option « Mode Posture » est maintenant disponible pour les Guerriers. Celle-ci permet de colorer l'interface suivant la posture, plutôt que la spécialisation du personnage" },

      { k = "h", link = { page = "comfortQoL" }, t = "QoL", fr = "QoL" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "New! Added 2 checkboxes on the map: Quests to turn in and Quests in progress. These options show your quests on every map level, without having to track them, whatever the zoom level. Normally, your quests only show their pin at zoom level 3", fr = "Nouveau ! Ajout de 2 options à cocher sur la carte : Quêtes à rendre et Quêtes en cours. Ces options permettent d'afficher sur tous les niveaux de cartes vos quêtes, sans devoir les suivre, et peu importe le niveau de zoom. En temps normal, vos quêtes n'affichent leur « pastille » qu'au niveau 3 de zoom" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "New! Added a new option to show when new spell ranks are available (New spell ranks). Clicking the arrow icon automatically updates the lower rank on your action bars", fr = "Nouveau ! Ajout d'une nouvelle option pour indiquer la présence de nouveaux rangs de sorts. En cliquant sur l'icône de flèche, le sort mettra à jour automatiquement le rang inférieur de votre barre d'actions" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "Blizzard no longer allows placing resource icons on the minimap", fr = "Blizzard ne permet plus de placer les icônes des ressources sur la minimap" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "Replacing the old feature that showed the icons on the gold dots, the icons now appear in the tooltips", fr = "En remplacement de l'ancienne fonctionnalité qui permettait d'avoir les icônes sur les points dorés, les icônes s'affichent dans les infobulles" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "Added an option to hide the Totem Bar or reveal it on hover", fr = "Ajout d'une option pour masquer la Barre de Totems ou la révéler au survol" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "The Blizzard raid manager panel can now be hidden (still available on hover). (Extras > QoL > Interface)", fr = "Le « Panneau de raid » Blizzard est maintenant dissimulable (toujours disponible au survol). (Extras > QoL > Interface)" },
      { k = "li", lvl = 1, link = { page = "visibility" }, t = "Bars 4, 5 and 9 can now behave like bars 1, 2 and 3 in \"Show Bars\" profiles. (Extras > Integration > EllesmereUI Action Bars)", fr = "Les barres 4, 5 et 9 peuvent avoir les mêmes comportements que les barres 1, 2 et 3 en profils « Barres montrées ». (Extras > Intégration > Barres d'action EllesmereUI)" },
      { k = "li", lvl = 1, link = { page = "visibility" }, t = "The pet bar can now behave like bars 1, 2 and 3 in \"Show Bars\" profiles. (Extras > Integration > EllesmereUI Action Bars)", fr = "La barre du familier peut avoir les mêmes comportements que les barres 1, 2 et 3 en profils « Barres montrées ». (Extras > Intégration > Barres d'action EllesmereUI)" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "New! When a profession recipe needs a crafted reagent, that reagent now has a small arrow (Craftable reagents). Hover it to see the reagents it needs. Right-click opens its recipe in the profession window", fr = "Nouveau ! Lorsqu'une recette de métier nécessite un composant fabriqué, celui-ci possède maintenant une petite flèche. Passer la souris dessus révèle les composants nécessaires à cet objet. Un clic droit emmène directement à sa recette dans le panneau du métier" },

      { k = "h", link = { page = "taxiMode" }, t = "Taxi Mode (New!)", fr = "Mode Taxi (Nouveau !)" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Shows the flight duration", fr = "Affiche la durée du trajet" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Shows the departure name and its zone, the intermediate stops, and the destination and its zone", fr = "Affiche le nom du départ et sa zone, les étapes intermédiaires et l'arrivée et sa zone" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Under each stop, the estimated arrival time", fr = "Sous chaque étape, le temps d'arrivée estimé" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Each stop can be clicked to land there (also works with later stops, not only the next one)", fr = "Chaque étape peut être cliquée afin de descendre à son arrêt (fonctionne également avec les futurs arrêts, pas seulement le prochain)" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "The duration text only shows from 8 sec (to avoid overlapping texts)", fr = "Le texte de durée ne s'affichera qu'à partir de 8 sec (pour éviter les superpositions de texte)" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "A small sound can be played when arriving at destination", fr = "Un petit son peut être joué à l'arrivée à destination" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Also works on Midnight", fr = "Fonctionne également sur Midnight" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Added many color settings. Every element can use the Themed Colors", fr = "Ajout de nombreux réglages de couleurs. Tous les éléments peuvent reprendre les couleurs thématiques" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Added a glow setting for the current position, with a pulse animation", fr = "Ajout d'un réglage de lueur de position actuelle, et d'une animation pulse de celle-ci" },
      { k = "li", lvl = 1, link = { page = "taxiMode" }, t = "Flight durations have been adjusted and take the Frequent Flyer Heritage talent into account (20% faster flights)", fr = "Les durées de voyage ont été ajustées et tiennent compte du talent Héritage Vols Fréquents (trajets 20% plus rapides)" },

      { k = "h", link = { page = "xpBar" }, t = "XP Bar", fr = "Barre d'XP" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "Holding SHIFT, the XP Bar now shows the total XP granted by all the quests in your quest log", fr = "En appuyant sur MAJ, la barre d'XP affichera maintenant le total d'XP octroyé par l'ensemble des quêtes du journal" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "The AishCore XP Bar now stays shown while talking to an NPC (on top of the DialogueUI skin)", fr = "La barre d'XP d'AishCore s'affichera même pendant le dialogue avec un PNJ (par dessus l'habillage DialogueUI)" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "[Forever] Shaman: Reincarnation no longer shows in the skills to train, even once unlocked", fr = "[Forever] Chaman : La Réincarnation ne s'affichera plus dans les compétences à entraîner même une fois débloquée" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "[Forever] FIX: Not all weapon skills were displayed", fr = "[Forever] FIX : Les compétences d'armes ne s'affichaient pas toutes" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "Adjusted the textures and the level position of the XP Bar when it is aligned to the left or right edge", fr = "Ajustement des textures et de la position du niveau pour la Barre d'XP lorsque celle-ci est alignée sur les bords gauche ou droite" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "FIX: The XP Bar info text was shown too low on new AishCore profiles", fr = "FIX : Le texte d'infos de la barre d'XP s'affichait trop bas sur les nouveaux profils AishCore" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "FIX: The level in the XP Bar could stop showing in some conditions", fr = "FIX : Le niveau dans la barre d'XP pouvait ne plus s'afficher dans certaines conditions" },

      { k = "h", link = { page = "resourceCircle" }, t = "Central Circle", fr = "Cercle central" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "The orbs now move so they are no longer covered by the Elite decoration when it is shown", fr = "Les orbes se déplaceront pour ne plus être obstruées par la décoration Elite si cette dernière s'affiche" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "Orbs already placed at the bottom of the circle stay there", fr = "Si les orbes sont déjà placées en bas du cercle, elles y resteront" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "Shaman: added the Secondary Resource text for Lightning Shield and Water Shield charges", fr = "Chaman : Ajout du texte de ressource secondaire pour les charges de Bouclier de foudre et de Bouclier d'eau" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "New! Added a Mana Regen section", fr = "Nouveau ! Ajout d'une section Régénération de mana" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "This section tracks the 5-second rule (shows the 5 seconds needed after a spell before mana regeneration starts), and can also show the regeneration state (active or not)", fr = "Cette section permet de suivre la Règle des 5 secondes (visualise les 5 secondes nécessaires après un sort pour commencer la régénération de mana), et permet également d'afficher l'état de la régénération (active ou non)" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "The 5-second rule can be shown with a simple bar, an arc, or with the decorative dots at the bottom of the circle", fr = "La règle des 5 secondes peut être visualisée avec une barre simple, un arc de cercle, ou avec les Points décoratifs en bas du cercle" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "2 modes are available for the decorative dots: 2 steps or 4 steps", fr = "2 modes sont disponibles pour les points décoratifs : 2 temps ou 4 temps" },
      { k = "li", lvl = 2, link = { page = "resourceCircle" }, t = "In 2 steps, 2 dots show at 2.5 s, then the 2 others at 5 s", fr = "En 2 temps, on affiche 2 points à 2,5 s, puis 2 autres à 5 s" },
      { k = "li", lvl = 2, link = { page = "resourceCircle" }, t = "In 4 steps, 1 dot shows every second", fr = "En 4 temps, on affiche 1 point toutes les secondes" },
      { k = "li", lvl = 2, link = { page = "resourceCircle" }, t = "In both cases, when all the dots are shown, you are regenerating", fr = "Dans les deux cas, si tous les points sont présents, alors cela veut dire qu'on est en train de régénérer" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "Active regeneration can be shown with a glow, or with a simple dot", fr = "La régénération active peut être visualisée avec une lueur, ou bien un simple point" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "A Pulse animation can be enabled for the active regeneration glows", fr = "Une animation « pulse » peut être activée pour les lueurs de la régénération active" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "[Forever] Druid: Rage did not show in Bear Form", fr = "[Forever] Druide : La rage ne s'affichait pas en étant en forme d'ours" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "[Forever] Druid: Mana can be shown in the secondary resource circle in Bear or Cat Form", fr = "[Forever] Druide : La mana peut s'afficher dans le cercle de ressource secondaire en forme d'ours ou de félin" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "[Forever] Druid: the Central Circle now follows shapeshifts in combat (caster, cat, bear): rage, energy or mana", fr = "[Forever] Druide : le cercle central suit maintenant les changements de forme en combat (humain, félin, ours) : rage, énergie ou mana" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "[Forever] Druid: combo points show in Cat Form", fr = "[Forever] Druide : les points de combo s'affichent en forme de félin" },

      { k = "h", link = { page = "unitBars" }, t = "Unit Frames", fr = "Cadres d'unités" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "Reaction colors (Hostile, Neutral, Friendly) can now be customized (General tab)", fr = "Les couleurs de réactions sont maintenant personnalisables (Onglet Général)" },
      { k = "li", lvl = 1, link = { page = "topTargetBar" }, t = "Added an option to the Top Target to show health as a percentage rather than a value", fr = "Ajout d'une option pour la TopTarget pour afficher la vie en pourcentage plutôt qu'en valeur" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "FIX: The option to show the level on the health bar was grayed out", fr = "FIX : L'option pour afficher le niveau sur la barre de vie était grisée" },

      { k = "h", link = { page = "outOfCombat" }, t = "Out-of-Combat Circles", fr = "Cercles Hors-Combat" },
      { k = "li", lvl = 1, link = { page = "outOfCombat" }, t = "Added an out-of-combat health circle for the pet (Pet Health Circle), with its own settings", fr = "Ajout d'un cercle de vie hors combat pour le familier, réglable indépendamment" },

      { k = "h", link = { page = "campfire" }, t = "Camping HUD", fr = "Campement HUD" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "Added the Cozy Sleeping Bag to the camp items", fr = "Ajout du Sac de couchage douillet dans les objets de campement" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "Added the Pouch of Violet Dust to the camp items", fr = "Ajout de la Bourse de Poussière Pourpre dans les objets de campement" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "Camp items now show a cooldown swipe on their icon while on cooldown", fr = "Les objets de campement affichent bien un balayage sur l'icône s'ils sont en recharge" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "FIX: Food could wrongly show among the camp items", fr = "FIX : La nourriture ne pourra plus apparaître par erreur dans les objets de campement" },
      { k = "li", lvl = 1, link = { page = "campfire" }, t = "FIX: The Camping HUD no longer shows when you are dead", fr = "FIX : Le camping HUD ne se montre plus quand vous êtes mort" },

      { k = "h", link = { page = "castBars" }, t = "Cast Bars", fr = "Barres de cast" },
      { k = "li", lvl = 1, link = { page = "castBars" }, t = "New \"Hide Blizzard cast bar\" option on the player bar, on by default. It hides the original Blizzard cast bar", fr = "Nouvelle option « Masquer la barre d'incantation Blizzard », sur la barre du joueur. Cochée par défaut. Elle cache la barre Blizzard d'origine" },

      { k = "h", link = { page = "extraBars" }, t = "Dynamic Bars", fr = "Barres dynamiques" },
      { k = "li", lvl = 1, link = { page = "extraBars" }, t = "Dynamic bars hidden in combat now show on mouseover", fr = "Les barres dynamiques cachées en combat sont maintenant visibles au survol" },
      { k = "li", lvl = 1, link = { page = "extraBars" }, t = "FIX: Locked chests no longer show in the Dynamic Bars as Openable items", fr = "FIX : Les coffres verrouillés ne s'afficheront plus dans les barres Dynamiques en tant qu'Objets ouvrables" },

      { k = "h", link = { page = "menuBar" }, t = "Menu Bar", fr = "Barre de menu" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Added the Appearances option", fr = "Ajout de l'option Apparences" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Added the Pet Journal option", fr = "Ajout de l'option Codex de Mascottes" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Added the Toy Box option", fr = "Ajout de l'option Coffre à jouets" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Added the Group Finder option", fr = "Ajout de l'option Recherche de groupe" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Added shortcuts on the Collections icon:", fr = "Ajout de raccourcis sur l'icône Collection :" },
      { k = "li", lvl = 2, link = { page = "menuBar" }, t = "Shift + click: mounts", fr = "Maj + clic : montures" },
      { k = "li", lvl = 2, link = { page = "menuBar" }, t = "Ctrl + click: pets", fr = "Ctrl + clic : mascottes" },
      { k = "li", lvl = 2, link = { page = "menuBar" }, t = "Alt + click: Toy Box", fr = "Alt + clic : coffre à jouets" },
      { k = "li", lvl = 2, link = { page = "menuBar" }, t = "Ctrl + Alt + click: Appearances", fr = "Ctrl + Alt + clic : apparences" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Added the Equipment Manager option. Shortcuts let you switch from one set to another", fr = "Ajout de l'option Gestionnaire d'équipement. Des raccourcis permettent de passer d'un set à un autre" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "FIX: Equipment can now be changed in combat (weapon slots only)", fr = "FIX : Les équipements peuvent maintenant être changés en combat (seulement les emplacements d'armes)" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Shaman: Astral Recall shows on hover of the Hearthstone icon while holding SHIFT, and can be cast with a click", fr = "Chaman : Le rappel astral est visible au survol de l'icône de Pierre de Foyer, en maintenant Maj, et peut être lancé avec un clic" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "Astral Recall also works on Midnight", fr = "Le rappel astral fonctionne également sur Midnight" },

      { k = "h", link = { page = "aurasMissingBuffs" }, t = "Missing buffs", fr = "Buffs manquants" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "The Elixirs alert now stays shown while other elixirs can still be used. A new option (\"One elixir is enough\") hides the alert as soon as at least one elixir is applied", fr = "La notification des Elixirs restera affichée si d'autres Elixirs peuvent être utilisés. Une nouvelle option a été créée pour cacher l'alerte dès qu'au moins un seul élixir a été appliqué" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "After 15 sec, the alert reminds you that it can be hidden with a right-click", fr = "Au bout de 15 sec d'affichage, l'alerte rappellera qu'elle peut être cachée avec un clic droit" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "New option to hide buff reminders in Travel Form or Ghost Wolf (Ignore in Travel Form / Ghost Wolf)", fr = "Ajout d'une nouvelle option pour cacher les rappels de buffs en Forme de Voyage ou Loup Fantôme" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Added the Well Rested alert. It is suggested for refresh like a regular spell buff (controlled by the threshold)", fr = "Ajout de l'alerte pour le buff Bien Reposé. Celui-ci sera proposé au rafraîchissement comme un buff de sort classique (contrôlable avec le seuil)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Talent Points and Heritage Points alerts are now suggested even in Ghost Wolf / Travel Form", fr = "Les alertes des points de talents et points d'héritage seront proposées même en forme de loup / voyage" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Battle Shout has been removed from the available alerts (not working for now)", fr = "Cri de guerre est retiré des alertes possibles (non fonctionnel pour le moment)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Consumables now have their own section", fr = "Les consommables ont maintenant leur section dédiée" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Consumable alerts have a new option to only enable them in instances (raids / dungeons / BGs)", fr = "Les alertes de consommables disposent d'une nouvelle option pour ne les activer qu'en instance (raids/donjons/BGs)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "FIX: Water Breathing elixirs are no longer treated as regular elixirs, and are only suggested while underwater", fr = "FIX : Les Elixirs de respiration aquatique ne seront plus considérés comme des élixirs classiques, et ne seront proposés que lorsque vous serez sous l'eau" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] FIX: Sharpening Stones are suggested again for Rogues who have unlocked their poison skills", fr = "[Forever] FIX : les Pierres à aiguiser seront de nouveau proposées pour les Voleurs qui ont débloqué leurs compétences de poisons" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] FIX: Talent Points and Heritage Points alerts now show even in rest areas", fr = "[Forever] FIX : les alertes de points de Talents et points d'Héritage à dépenser s'afficheront même en zone de repos" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] Missing buffs alerts no longer show when a stronger buff is already applied (campfire, scroll, etc.)", fr = "[Forever] Les alertes de buffs manquants ne s'afficheront plus lorsqu'un buff plus puissant est déjà appliqué (campement, parchemin, etc)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] FIX: The Heritage Points alert could sometimes show for no reason", fr = "[Forever] FIX : L'alerte des Points d'Héritage à dépenser pouvait parfois s'afficher sans raison" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] Druid: Omen of Clarity is no longer part of the Missing buffs alerts", fr = "[Forever] Druide : L'augure de clarté ne fera plus partie des alertes de Buffs Manquants" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "FIX: Some Missing buffs alerts stayed shown in Battlegrounds", fr = "FIX : Certaines alertes de Buffs manquants restaient affichées en Champs de bataille" },

      { k = "h", link = { page = "movementBuffs" }, t = "Movement Buffs", fr = "Buffs de déplacement" },
      { k = "li", lvl = 1, link = { page = "movementBuffs" }, t = "Added a customizable text for buffs with stacks", fr = "Ajout d'un texte réglable pour les buffs avec stacks" },

      { k = "h", t = "Fixes", fr = "Correctifs" },
      { k = "li", lvl = 1, t = "[Forever] Reversed fill direction of the pet and player health bars", fr = "[Forever] Inversions du sens de remplissage de la barre de vie du familier et du joueur" },
      { k = "li", lvl = 1, t = "[Forever] Addon Compartment settings", fr = "[Forever] Configuration du compartiment d'addons" },
      { k = "li", lvl = 1, t = "[Forever] Font settings for the level-up gains", fr = "[Forever] Configuration des polices sur le gain de niveau" },
      { k = "li", lvl = 1, t = "[Forever] Slight offset of the Priority Bar, which was not perfectly aligned (1px, literally unplayable!)", fr = "[Forever] Léger décalage de la barre de rotation qui n'était pas parfaitement alignée (1px, littéralement injouable !)" },
      { k = "li", lvl = 1, t = "The slider values of elements being moved (in Unlock mode) now update during the move", fr = "Les valeurs des glissières des éléments en train d'être déplacés (en mode Déverrouillage) se mettent à jour en même temps que le déplacement" },
      { k = "li", lvl = 1, t = "Mouse button keybinds shown on the Priority Bar and the Rotation Button Module now read \"MX\" rather than \"Mouse Button X\"", fr = "Les raccourcis clavier des boutons de souris affichés sur la barre et le bouton de rotation s'affichent « MX » plutôt que « Bouton de souris X »" },
      { k = "li", lvl = 1, t = "FIX: The Priority Bar edit mode now closes when entering combat with the spellbook open", fr = "FIX : Le mode Edition de la barre de rotation se fermera lorsqu'on entre en combat avec le grimoire ouvert" },
      { k = "li", lvl = 1, t = "[Forever] The Rotation Button Module is now disabled on Forever", fr = "[Forever] Le bouton de rotation est maintenant désactivé sur Forever" },
      { k = "li", lvl = 1, t = "[Forever] FIX: blocked action error (SpellStopCasting) when opening AishCore from the WoW options", fr = "[Forever] FIX : erreur d'action bloquée (SpellStopCasting) à l'ouverture d'AishCore depuis les options de WoW" },
      { k = "li", lvl = 1, t = "[Forever] Mulgore: Bloodhoof Village was not considered a safe zone, it now is", fr = "[Forever] Mulgore : Sabot-de-sang n'était pas considérée comme une zone safe, c'en est une" },
      { k = "li", lvl = 1, t = "[Forever] FIX: The Platynator integration no longer worked (font change)", fr = "[Forever] FIX : L'intégration avec Platynator ne fonctionnait plus (changement de police)" },
      { k = "li", lvl = 1, link = false, t = "[Forever] Gamepad: fixed the SetPreferredGamepadInteractTarget error that forced gamepad players to reload the UI regularly. In gamepad mode:", fr = "[Forever] Manette : corrige l'erreur SetPreferredGamepadInteractTarget qui obligeait les joueurs manette à recharger l'interface régulièrement. En mode manette :" },
      { k = "li", lvl = 2, t = "the AFK Screen no longer closes windows nor hides the interface the same way", fr = "le Mode AFK ne ferme plus les fenêtres et ne cache plus l'interface de la même façon" },
      { k = "li", lvl = 2, t = "the Menu Bar and the \"Bags full\" alert open windows through the Blizzard buttons", fr = "la Barre de menu et l'alerte « Sacs pleins » ouvrent les fenêtres via les boutons Blizzard" },
      { k = "li", lvl = 1, link = false, t = "Simplified Chinese: the AishUI setup window and several other texts showed squares. They now use a font that has the Chinese characters", fr = "Chinois simplifié : la fenêtre de configuration AishUI et plusieurs autres textes s'affichaient en carrés. Ils utilisent maintenant une police qui a les caractères chinois" },
      { k = "li", lvl = 1, link = false, t = "FIX: Quest icons on the map no longer disappear when clicked", fr = "FIX : Les icônes de quête sur la map ne disparaissent plus en cliquant dessus" },
      { k = "li", lvl = 1, t = "Added an \"Unlock\" button in the Well Fed Circle preview", fr = "Ajout d'un bouton « Déverrouiller » dans l'aperçu du Cercle Bien Nourri" },
      { k = "li", lvl = 1, t = "The Well Fed Circle shows a preview when its settings page is open", fr = "Le Cercle Bien Nourri affiche un aperçu quand sa page des réglages est ouverte" },
      { k = "li", lvl = 1, t = "FIX: The Well Fed Circle can be moved again", fr = "FIX : Le Cercle Bien Nourri est de nouveau déplaçable" },
      { k = "li", lvl = 1, t = "FIX: The Cooldown Manager notification could stay shown even after a UI reload and/or after clicking \"Don't ask for this spec\"", fr = "FIX : La notification du Gestionnaire de CD pouvait rester affichée même après un rechargement de l'interface et/ou après avoir cliqué sur « Ne plus demander »" },
      { k = "li", lvl = 1, t = "[Forever] FIX: 3D animations appeared very dark in instances", fr = "[Forever] FIX : Les animations 3D apparaissaient très sombres en instance" },
      { k = "li", lvl = 1, link = { page = "spellEffects" }, t = "FIX: Creating and editing Tags in the Model Library showed the windows in the background", fr = "FIX : La création et l'édition des Tags dans la Bibliothèque d'animations affichait les fenêtres en arrière-plan" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Forever] FIX: Many auras were not tracked in combat", fr = "[Forever] FIX : Grand nombre des auras n'avaient pas leurs trackings fonctionnels en combat" },
      { k = "li", lvl = 1, link = { page = "aurasTotems" }, t = "FIX: The aura list could contain unrelated spells in the Totems section", fr = "FIX : La liste des auras pouvait contenir des sorts parasites dans la section Totem" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Forever] FIX: Debuffs could no longer be tracked correctly (especially those from spells without a cooldown, such as Immolate or Corruption)", fr = "[Forever] FIX : Les debuffs ne pouvaient plus être suivis correctement (notamment ceux provenant de sorts sans cooldown, comme Immolation ou Corruption)" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Forever] FIX: Debuff tracking could sometimes fail to show on pull in the Circle Bars and Free Bars", fr = "[Forever] FIX : Les suivis de debuffs pouvaient parfois ne pas s'afficher au pull dans les barres de cercles et barres libres" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "[Forever] FIX: Potential errors in debuff tracking (not sure, hard to test)", fr = "[Forever] FIX : Des erreurs potentielles sur les suivis des debuffs (pas sûr, dur de tester)" },
    },
  },
  {
    version = "4.6", date = "2026-11-04",
    lines = {
      { k = "h", t = "Settings panel", fr = "Panneau de réglages" },
      { k = "li", lvl = 1, t = "New button to enable/disable each module, right next to the page title", fr = "Ajout d'un bouton pour activer/désactiver chaque module, directement à côté du titre de la page" },
      { k = "li", lvl = 1, t = "When a module is disabled, the rest of its page is inactive and grayed out", fr = "Lorsqu'un module est désactivé, le reste de la page est inactif et grisé" },
      { k = "li", lvl = 1, link = { page = "modulesOverview" }, t = "The Modules page can now enable/disable QoL settings", fr = "Les Modules peuvent maintenant activer/désactiver les réglages QoL" },
      { k = "li", lvl = 1, link = { page = "profiles" }, t = "Profiles can now export/import/copy the features recently added to AishCore, and they are organized the same way as the Modules page", fr = "Les profils peuvent maintenant exporter/importer/copier les fonctionnalités récemment ajoutées dans AishCore, et leur organisation est la même que dans la page Modules" },
      { k = "li", lvl = 1, t = "Improved sliders: easier to handle, in your current spec's theme color, and better aligned with the other settings", fr = "Amélioration des réglages « Glissières » pour qu'ils soient plus facilement manipulables, dans le thème coloré de la spé actuelle, et qu'ils s'alignent mieux avec les autres réglages" },
      { k = "li", lvl = 1, t = "Slider min/max values are only shown while you use the slider", fr = "Les valeurs butoirs des Glissières ne seront visibles que lors de la manipulation" },
      { k = "li", lvl = 1, t = "While the settings panel is minimized, elements are no longer interactive, so you can better see how they behave outside the settings", fr = "Lorsque le Panneau de réglage est minimisé, les éléments ne sont plus interactifs, pour permettre de mieux visualiser leur comportement en dehors des réglages" },
      { k = "li", lvl = 1, t = "Many changes to page structures: settings elements have more consistent sizes, are grouped by feature, and were renamed to make more sense", fr = "Très nombreuses modifications sur les structures de pages, visant à harmoniser la taille des différents éléments de réglages, les regrouper par fonctionnalité, et les renommer pour leur donner plus de sens" },

      { k = "h", t = "General", fr = "Général" },
      { k = "li", lvl = 1, link = false, t = "Added Simplified Chinese localization (zhCN)", fr = "Ajout de la localisation Chinoise (zhCN)" },

      { k = "h", link = { page = "campfire" }, t = "[Forever] Camping HUD", fr = "[Forever] Camping HUD" },
      { k = "li", lvl = 1, t = "New Camping module", fr = "Création d'un nouveau module de Campement" },
      { k = "li", lvl = 1, t = "A diamond appears when you are near a campfire", fr = "Un losange s'affiche lorsque vous sentez un feu de camp proche" },
      { k = "li", lvl = 1, t = "Left-clicking the diamond makes you sit down", fr = "Un clic gauche sur le losange permet de s'assoir" },
      { k = "li", lvl = 1, t = "Right-clicking unpacks your camp gear and shows shortcuts for the 5 professions and up to 6 camp objects ready to be added to the site", fr = "Un clic droit permet de déballer son équipement de camp, et affiche des raccourcis pour les 5 métiers et jusqu'à 6 objets de camp prêts à être ajouter au site" },
      { k = "li", lvl = 1, t = "Quickly hovering the objects placed around the fire \"scans\" the buffs they will grant after 1 minute spent sitting", fr = "Passer rapidement la souris sur les objets posé autour du feu permet de « scanner » les buffs que ceux-ci offriront après 1 minute passée assis" },
      { k = "li", lvl = 1, t = "Buffs are shown above the diamond (up to 10), and hovering their icons shows their details", fr = "Les buffs s'affichent au dessus du losange (jusqu'à 10 maximum), et passer la souris sur leurs icônes affichent les détails sur ces buffs" },
      { k = "li", lvl = 1, t = "A loading bar fills around the diamond. Once full (1 minute), a summary of the buffs you earned is shown above the diamond", fr = "Une barre de chargement se remplit tout autour du losange, et une fois pleine (1 minute), un récapitulatif des buffs obtenus se montrent au dessus du losange" },

      { k = "h", link = { page = "aurasMissingBuffs" }, t = "Missing buffs", fr = "Buffs Manquants" },
      { k = "li", lvl = 1, t = "Missing buff alerts are no longer offered in safe zones, like villages or small towns. If the village is hostile to your faction, the alerts are still shown", fr = "Les alertes de buffs manquants ne seront plus proposés dans les « Zones safe », comme les villages ou les petites villes. Si la zone est un village mais hostile à votre faction, les alertes seront quand même présentes" },
      { k = "li", lvl = 1, t = "Missing buff alerts now show the quality of the suggested consumables", fr = "Les alertes de buffs manquants affichent maintenant la qualité des consommables proposés" },
      { k = "li", lvl = 1, t = "Missing buff alerts can be hidden with a right-click until the next zone or condition refresh", fr = "Les alertes de buffs manquants peuvent être cachées avec un clic droit jusqu'à la prochaine zone ou rafraichissement de conditions" },
      { k = "li", lvl = 1, t = "New options to separate the missing aura alerts for Paladins (some players don't want the Crusader Aura alerts, for example)", fr = "Ajout d'options pour dissocier les alertes d'absence d'auras pour le paladin (certains joueurs ne souhaitent pas avoir les alertes des auras de croisé, par exemple)" },
      { k = "li", lvl = 1, t = "Added Elixir reminders to Missing buffs", fr = "Ajout des rappels des Elixirs dans les Buffs Manquants" },
      { k = "li", lvl = 1, t = "[Forever] Missing buff alerts for poisons now work correctly", fr = "[Forever] Les alertes de buffs manquants pour les poisons fonctionnent maintenant correctement" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] New threshold for how long before expiring you are reminded to refresh your poisons", fr = "[Forever] Ajout d'un seuil pour la durée à laquelle rappeler de rafraichir les poisons" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] New alert with a threshold, warning you when your poison stock is about to run out", fr = "[Forever] Ajout d'une nouvelle alerte avec un seuil permettant de notifier quand le stock de poison est bientôt écoulé" },
      { k = "li", lvl = 1, t = "When several consumable alert icons are shown, each icon gets the same animation set in 3D Animations", fr = "Si plusieurs icones sont présentes pour des alertes de buffs manquants de consommables, alors chaque icone recevra la même animation définie dans Animations 3D" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Food buff animations are centered when several consumables are offered to click", fr = "Les animations de buff de nourriture seront centrées quand plusieurs choix de consommables seront proposés à cliquer" },
      { k = "li", lvl = 1, t = "Missing buff alerts no longer remind you to reapply consumable buffs early: they wait until their enhancements have fully expired", fr = "Les alertes de buffs manquants ne rappelleront plus la réapplication des buffs de consommables en avance, elles attendront que leurs améliorations soient totalement expirées" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Hunter: the alert now correctly offers \"REVIVE PET\" when the pet is dead, including after an interrupted resurrection or the player's death", fr = "Chasseur : l'alerte propose bien « RESSUSCITER FAMILIER » quand le familier est mort, y compris après une résurrection interrompue ou la mort du joueur" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Hunter: the pet alert can be clicked in combat (Revive and Call)", fr = "Chasseur : l'alerte familier est cliquable en combat (Ressusciter et Appeler)" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "Warlock: the pet alert can be clicked in combat, with a choice of demon", fr = "Démoniste : l'alerte familier est cliquable en combat, avec le choix du démon" },

      { k = "h", link = { page = "unitBars" }, t = "Unit Frames", fr = "Cadres d'unités" },
      { k = "li", lvl = 1, t = "The Unit Frames page has been completely rebuilt:", fr = "L'entièreté de la page Cadres d'unités a été totalement refaite :" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "A preview box lets you see the bar", fr = "Un encadré d'aperçu permet de visualiser la barre" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Each bar has its own settings", fr = "Chaque barre est réglable séparément" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Right-clicking an element directly opens its settings section", fr = "Clic droit sur un élément permet d'ouvrir directement la section des réglages correspondant" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Previews of the Central Circle, Priority Bar and Cast Bars (target and player) can be toggled", fr = "Les aperçus du cercle central, de la barre de rotation et des barres de cast (cible et joueur) sont activables/désactivables" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New Layout option with 3 choices:", fr = "Ajout d'une option de Disposition avec 3 choix :" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Free: position the bar independently", fr = "Libre : permet de positionner la barre indépendamment" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Parenting: link its position to another bar. Moving one moves the other, as a single group", fr = "Parenté : permet de lier la position à une autre barre. Déplacer l'une déplacera l'autre comme un seul et même groupe" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Symmetry: link bars together and move them symmetrically, with the mirror axis at the center of the screen", fr = "Symétrie : permet de relier des barres ensemble et de les déplacer via une symétrie. L'axe du miroir se trouvant au centre de l'écran" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New settings for:", fr = "Ajout de nouveaux réglages pour :" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Bar background color", fr = "La couleur de fond de la barre" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "HP frame: shape (round, diamond, square), color, position, anchor", fr = "Cadre des HP : Forme (Rond, losange, carré), couleur, position, ancrage" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "Decorative Shapes: shape (round, diamond, square, chevrons, and combinations of several), anchor (left/right/both sides), quantity", fr = "Formes décoratives : Forme (Rond, Losange, Carré, Chevrons, et combinaisons de plusieurs d'entre eux), ancrage (à gauche/droite/des 2 cotés), Quantité" },
      { k = "li", lvl = 2, link = { page = "unitBars" }, t = "The player name can be \"Always shown\"", fr = "Le nom du joueur peut être « Toujours Affiché »" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New shadow option under the unit name, with adjustable size and opacity", fr = "Ajout d'une option d'ombre sous le nom de l'unité. Celle ci est réglable en taille et en opacité" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New Fill direction option (left to right, right to left, top to bottom, bottom to top)", fr = "Ajout d'une option de sens de remplissage de la barre (gauche à droite, droite à gauche, haut en bas et bas en haut)" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "New Box width setting, to set a maximum displayed length for the unit name", fr = "Ajout d'un réglage de Largeur de la boîte, pour fixer une longueur maximale affichable au nom de l'unité" },

      { k = "h", link = { page = "castBars" }, t = "Cast Bars", fr = "Barres de cast" },
      { k = "li", lvl = 1, t = "The Cast Bar: Player and Cast Bar: Target modules are now grouped in the same \"Cast Bars\" category", fr = "Les Modules Barre de Cast : Joueur et Barre de Cast : Cible sont maintenant regroupés dans la même catégorie « Barres de Cast »" },
      { k = "li", lvl = 1, link = { page = "castBars" }, t = "This new page has a preview, and a selector switches between the settings of each bar", fr = "Cette nouvelle page dispose d'un aperçu. Un sélecteur permet de passer des réglages d'une barre à une autre" },
      { k = "li", lvl = 1, t = "Added Cast Bar: Focus", fr = "Ajout de la Barre de Cast de la Focalisation" },
      { k = "li", lvl = 1, link = { page = "castBars" }, t = "New anchor and position options for the spell name and the cast time", fr = "Ajout d'options d'ancrages et de positionnement pour le Nom du sort et pour le Temps d'incantation" },
      { k = "li", lvl = 1, link = { page = "castBars" }, t = "Right-clicking an element goes directly to its section", fr = "Clic droit sur un élément emmène directement à la section correspondante" },
      { k = "li", lvl = 1, link = { page = "castBars" }, t = "The preview now cycles through 3 spells to show the different colors and channel displays: Fireball / Frostbolt / Drain Life", fr = "L'aperçu cycle maintenant sur 3 sorts pour visualiser les couleurs et les affichages différents des canalisations : Boule de Feu / Trait de Givre / Drain de vie" },
      { k = "li", lvl = 1, t = "Cast bars are now delayed when you get hit (pushback)", fr = "Les barres d'incantations seront retardées lorsqu'on se fait frapper (pushback)" },
      { k = "li", lvl = 1, t = "New options to show and adjust the spell icon on cast bars (player and target)", fr = "Ajout d'options pour afficher et régler l'icone du sort sur les barres de cast (joueur et cible)" },

      { k = "h", link = { page = "xpBar" }, t = "XP Bar", fr = "Barre d'XP" },
      { k = "li", lvl = 1, t = "Reorganized the XP Bar settings page", fr = "Réorganisation de la page de réglages de la barre d'XP" },
      { k = "li", lvl = 1, t = "Many new XP Bar settings (size, orientation, layout, etc.)", fr = "Ajout de nombreux réglages de la barre d'XP (taille, orientation, disposition, etc)" },
      { k = "li", lvl = 1, link = { page = "xpBar" }, t = "New Rested XP display", fr = "Ajout d'une visualisation de l'XP Reposé" },

      { k = "h", link = { page = "priorityBar" }, t = "Priority Bar", fr = "Barre de rotation" },
      { k = "li", lvl = 1, link = { page = "priorityBar" }, t = "New Preview section at the top of the page", fr = "Ajout d'une section d'Aperçu en haut de la page" },
      { k = "li", lvl = 2, link = { page = "priorityBar" }, t = "Clicking a slot lists all the spells assigned to it, and lets you add a new spell (green \"+\")", fr = "Cliquer sur un emplacement déroule tous les sorts attribués à cet endroit, et permet aussi d'ajouter un nouveau sort (« + » vert)" },
      { k = "li", lvl = 2, link = { page = "priorityBar" }, t = "Drag and drop a spell to move it to another slot, or to change its priority within the slot", fr = "Glisser / déposer un sort permet de le déplacer d'un emplacement à un autre, ou de changer sa priorité au sein même de l'emplacement" },
      { k = "li", lvl = 2, link = { page = "priorityBar" }, t = "Dragging a spell outside a slot removes it from the Priority Bar", fr = "Glisser un sort en dehors d'un emplacement le supprime de la barre de rotation" },
      { k = "li", lvl = 2, link = { page = "priorityBar" }, t = "Right-clicking a spell shows 3 options: change the glow color (left), remove the spell (right), set the spell as \"Stealth\" (top, Rogues and Druids only)", fr = "En faisant un clic droit sur un sort, 3 options s'affichent : changer la couleur du glow (gauche), supprimer le sort (droite), définir le sort comme « Camouflage » (en haut, uniquement pour les Voleurs et les Druides)" },
      { k = "li", lvl = 1, link = { page = "priorityBar" }, t = "New option to set a spell as \"Stealth\"", fr = "Ajout d'une option pour définir un sort « Camouflage »" },
      { k = "li", lvl = 1, link = { page = "priorityBar" }, t = "A spell set as \"Stealth\" is only shown while stealthed. A small purple marker in the top left corner of the icon flags it", fr = "Lorsqu'un sort est configuré en « Camouflage », celui-ci ne se montrera qu'en mode Furtif. Un petit détrompeur violet dans le coin supérieur gauche de l'icone indique le mode Camouflage" },

      { k = "h", link = { page = "stealthMode" }, t = "Stealth Mode", fr = "Mode furtif" },
      { k = "li", lvl = 1, link = { page = "stealthMode" }, t = "New Visibility options for the player health, target health, Central Circle and Priority Bar while in Stealth Mode", fr = "Ajout d'options de Visibilité pour gérer les affichages de la Vie du joueur, de la cible, du Cercle central et de la Barre de Rotation, lors du Mode furtif" },
      { k = "li", lvl = 1, link = { page = "stealthMode" }, t = "Example configuration:", fr = "Exemple de configuration :" },
      { k = "li", lvl = 2, link = { page = "stealthMode" }, t = "The player health bar shows as soon as you are outside a rest area/village", fr = "La barre de vie du joueur s'affichera dès que vous n'êtes pas en zone de repos/village" },
      { k = "li", lvl = 2, link = { page = "stealthMode" }, t = "The target health bar always shows when you are stealthed (and have a target)", fr = "La barre de vie de la cible s'affichera toujours dès que vous êtes camouflé (et que vous ciblez quelque chose)" },
      { k = "li", lvl = 2, link = { page = "stealthMode" }, t = "The Central Circle shows when you are in a group, in an instance, in a PvP zone or any other contested zone", fr = "Le cercle central lorsque vous serez en groupe, en instance, en zone PvP ou toute autre zone contestée" },
      { k = "li", lvl = 2, link = { page = "stealthMode" }, t = "The Priority Bar shows as soon as your target can be attacked", fr = "La barre de rotation dès que votre cible peut être attaquée" },

      { k = "h", link = { page = "resourceCircle" }, t = "Central Circle", fr = "Cercle Central" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "New display for the options and settings of the 2 circles", fr = "Nouvel affichage des options et des réglages des 2 cercles" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "Right-clicking an element of the circles opens its settings", fr = "Clic droit sur un des éléments du cercles ouvre les réglages correspondants" },
      { k = "li", lvl = 1, link = { page = "resourceCircle" }, t = "New option to flip the Elite Dragon", fr = "Ajout d'une option pour afficher le Dragon Elite dans l'autre sens" },

      { k = "h", link = { page = "outOfCombat" }, t = "Out-of-Combat Circles", fr = "Cercles Hors-Combat" },
      { k = "li", lvl = 1, link = { page = "outOfCombat" }, t = "New display for the options and settings of the 2 circles", fr = "Nouvel affichage des options et des réglages des 2 cercles" },
      { k = "li", lvl = 1, link = { page = "outOfCombat" }, t = "Left-clicking one of the circles opens its settings", fr = "Clic gauche sur un des cercles permet de régler celui-ci" },
      { k = "li", lvl = 1, link = { page = "outOfCombat" }, t = "Right-clicking an element of a circle opens its settings", fr = "Clic droit sur un des éléments du cercle ouvre les réglages correspondants" },
      { k = "li", lvl = 1, t = "The Well Fed Circle now has its own dedicated section, with a preview built into the page", fr = "Le Cercle bien nourri a maintenant sa propre section dédiée, et également un aperçu intégré à la page" },

      { k = "h", link = { page = "cdmAppearance" }, t = "Cooldowns Appearance", fr = "Apparence des CDs" },
      { k = "li", lvl = 1, link = { page = "cdmAppearance" }, t = "The \"Essential CDs\" and \"Utility CDs\" modules are now grouped in this new category", fr = "Les modules « CDs Essentiels » et « CDs Utilitaires » sont maintenant regroupés sous cette nouvelle catégorie" },
      { k = "li", lvl = 1, link = { page = "cdmAppearance" }, t = "Reworked settings page with a preview of the CDs", fr = "Rework de la page des réglages avec un aperçu des CDs" },
      { k = "li", lvl = 1, link = { page = "cdmAppearance" }, t = "Right-clicking an element goes directly to its section", fr = "Un clic droit sur un élément emmène directement vers la section de réglages correspondante" },

      { k = "h", link = { page = "addonCompartment" }, t = "Addon Compartment", fr = "Compartiment d'addons" },
      { k = "li", lvl = 1, t = "New customizable Addon Compartment", fr = "Ajout d'un Compartiment d'addons personnalisable" },
      { k = "li", lvl = 1, link = { page = "addonCompartment" }, t = "Many settings to change the size, the icon layout (list, grid) and the minimap anchor", fr = "De nombreux réglages permettent de modifier la taille, disposition des icônes (liste, grille), et ancrage à la minimap" },
      { k = "li", lvl = 1, link = { page = "addonCompartment" }, t = "An addon list lets you exclude some addons or mark them as favorites", fr = "Une liste des addons permet d'exclure certains addons ou d'en mettre en favoris" },
      { k = "li", lvl = 1, link = { page = "addonCompartment" }, t = "The Favorites list can then be set up independently from the main list", fr = "La liste de Favoris peut ensuite être réglée indépendamment de la liste principale" },

      { k = "h", link = { page = "comfortQoL" }, t = "QoL", fr = "QoL" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "New option: double right-click to cast your fishing rod ([Forever]), or Ctrl + double right-click on Retail", fr = "Ajout d'une option : Double clic pour lancer canne à pêche (Forever) ou ctrl + double clic sur Retail" },
      { k = "li", lvl = 1, link = { page = "visibility" }, t = "New options to change the font of Baganator sections and categories (Extras > Integration)", fr = "Ajout d'options pour changer la police des sections et des catégories de Baganator (Extras > Intégrations)" },

      { k = "h", link = { page = "menuBar" }, t = "Menu Bar", fr = "Barre de menu" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "The Hearthstone button now shows your Hearthstone's destination", fr = "Le bouton de pierre de foyer indique maintenant la destination de la Pierre de foyer" },
      { k = "li", lvl = 1, link = { page = "menuBar" }, t = "The Hearthstone button shows the remaining cooldown when your Hearthstone is not available", fr = "Le bouton de Pierre de foyer montre le temps de recharge restant si la Pierre de Foyer n'est pas disponible" },

      { k = "h", t = "Fixes", fr = "Correctifs" },
      { k = "li", lvl = 1, link = false, t = "Added an AishCore logo in the Addon list", fr = "Ajout d'un logo pour l'AishCore dans la liste des Addons" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "FIX: Thunder Focus Tea was not tracked correctly", fr = "FIX : Le thé de concentration foudroyante n'était pas tracké correctement" },
      { k = "li", lvl = 1, link = { page = "aurasTracked" }, t = "FIX: Tigereye Brew removed from buff tracking (the aura is a passive and its bar stayed on screen permanently)", fr = "FIX : L'infusion oeil de tigre est retirée des trackings de buff (l'aura est un passif et sa barre restait affichée constamment)" },
      { k = "li", lvl = 1, t = "FIX: Some feasts were not covered by the Well Fed Circle (Harandar Celebration, Royal Roast, etc.)", fr = "FIX : Certains festins n'étaient pas couverts par le cercle Bien nourri (Festin d'harandar, Roti royal, etc…)" },
      { k = "li", lvl = 1, t = "FIX: When disabled, the player cast bar could still show up on an interrupted cast", fr = "FIX : Lorsque la barre de cast du joueur est désactivée, elle pouvait quand même s'apercevoir en cas d'incantation interrompue" },
      { k = "li", lvl = 1, t = "FIX: When disabled, unit frames could still get in the way of clicks as if they were still interactive", fr = "FIX : Lorsque les cadres d'unités sont désactivés, ils pouvaient quand même gêner le clic comme s'ils étaient encore interactifs" },
      { k = "li", lvl = 1, t = "FIX: The cast bar now correctly shows the delay when you get hit while casting", fr = "FIX : La barre de cast affiche maintenant correctement le délai lorsque vous êtes frappé pendant votre incantation" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "FIX: The sharpening stone alert only shows if you have a bladed weapon equipped", fr = "FIX : L'alerte de pierre à aiguiser ne s'affichera que si vous êtes équipé d'une arme tranchante" },
      { k = "li", lvl = 1, t = "FIX: The clock text could appear offset on the Menu Bar", fr = "FIX : Le texte d'horloge pouvait apparaître décalé sur la barre de menu" },
      { k = "li", lvl = 1, t = "FIX: The Top Target HP text could have the wrong font when the character loaded", fr = "FIX : Le texte d'HP de la TopTarget pouvait ne pas avoir la bonne police au chargement du personnage" },
      { k = "li", lvl = 1, link = false, t = "FIX: The EllesmereUI profile and module setup runs correctly again after a new AishUI installation", fr = "FIX : Le setup d'application des profils et des modules d'EllesmereUI se refera correctement après une nouvelle installation de l'AishUI" },
      { k = "li", lvl = 1, link = { page = "aurasMissingBuffs" }, t = "[Forever] FIX: Sharpening stones were not offered to Rogues. They are now, until they learn Poisons", fr = "[Forever] FIX : Les pierres à aiguiser n'étaient pas proposées pour le Voleur. Elles le seront jusqu'à ce qu'il apprenne l'utilisation des Poisons" },
      { k = "li", lvl = 1, link = { page = "comfortQoL" }, t = "[Forever] FIX: Tin veins did not show their icon on the minimap", fr = "[Forever] FIX : les filons d'étain n'affichaient pas leur icone sur la minimap" },
      { k = "li", lvl = 1, t = "[Forever] FIX: Added Form of the Moonstalker to the effects that trigger Stealth Mode", fr = "[Forever] FIX : ajout de la Forme de Traquelune aux effets déclenchant le Mode Furtif" },
      { k = "li", lvl = 1, t = "[Forever] FIX: Retribution Aura is now offered in Missing buffs on Forever", fr = "[Forever] FIX : Aura de vindicte est maintenant proposée dans les buffs manquants sur Forever" },
      { k = "li", lvl = 1, t = "FIX: Lua error when the Location module was disabled", fr = "FIX : erreur LUA lorsque le module de Localisation était désactivé" },
      { k = "li", lvl = 1, link = false, t = "FIX: The buyback icon could show on top of the repair icons", fr = "FIX : l'icone de rachat s'affichait par dessus les icones de réparation dans certains cas" },
      { k = "li", lvl = 1, link = false, t = "FIX: Buyback pages did not show sold items", fr = "FIX : Les pages de rachat n'affichaient pas les objets vendus" },
      { k = "li", lvl = 1, t = "FIX: The customizable Priority Bar no longer shows when opening the spellbook in combat", fr = "FIX : La barre de rotation customisable ne s'affiche plus lorsqu'on ouvre le grimoire en combat" },
      { k = "li", lvl = 1, t = "FIX: Some spells could not be dragged from the spellbook to the Priority Bar (Apex talent in particular)", fr = "FIX : Certains sorts n'étaient pas glissables dans la barre de rotation depuis le grimoire (Talent Apex notamment)" },
      { k = "li", lvl = 1, t = "FIX: The Priority Bar could stay interactive even when hidden", fr = "FIX : La barre de rotation pouvait rester interactive même si celle ci était cachée" },
      { k = "li", lvl = 1, link = { page = "outOfCombat" }, t = "FIX: Combo points around the out-of-combat circle were displayed erratically", fr = "FIX : Les points de combo s'affichant autour du cercle hors combat s'affichaient de manière chaotique" },
      { k = "li", lvl = 1, link = { page = "unitBars" }, t = "FIX: Some conditions when leaving stealth could cause a position bug on the player health bar", fr = "FIX : Certaines conditions en sortie de furtivité provoquaient parfois un bug de position de la barre de vie du joueur" },
    },
  },
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

      { k = "h", link = { page = "wellFed" }, t = "Well Fed Circle", fr = "Cercle Bien Nourri" },
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
      { k = "li", lvl = 1, t = "Smooth show / hide animation for the player cast bar", fr = "Ajout d'une animation fluide à l'apparition / disparition de la barre de cast du joueur", link = { page = "castBars" } },
      { k = "li", lvl = 1, t = "3 new spark settings (the tip of the cast bar): texture (line, dot, spark, star), color and size", fr = "Ajout de 3 réglages de l'étincelle (l'extrémité de la barre de cast) : texture (ligne, point, étincelle, étoile), couleur, et taille", link = { page = "castBars" } },

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
  { match = "barre d'incantation de la cible", page = "castBars" },
  { match = "out-of-combat resource circle", page = "outOfCombat", section = "SETTINGS_SEC_OCRC" },
  { match = "out-of-combat health circle", page = "outOfCombat", section = "SETTINGS_SEC_HEALTH_CIRCLE" },
  { match = "rotation button module", page = "rotationHelper" },
  { match = "compartiment d'addons", page = "addonCompartment" },
  { match = "out-of-combat circle", page = "outOfCombat" },
  { match = "cooldowns appearance", page = "cdmAppearance" },
  { match = "buffs de déplacement", page = "movementBuffs" },
  { match = "barre d'incantation", page = "castBars" },
  { match = "cercle de ressource", page = "resourceCircle" },
  { match = "cercles hors-combat", page = "outOfCombat" },
  { match = "cercle bien nourri", page = "wellFed" },
  { match = "bouton de rotation", page = "rotationHelper" },
  { match = "barre de rotation", page = "priorityBar" },
  { match = "auras de la cible", page = "targetAuras" },
  { match = "barres dynamiques", page = "extraBars" },
  { match = "addon compartment", page = "addonCompartment" },
  { match = "apparence des cds", page = "cdmAppearance" },
  { match = "cooldown manager", page = "cdmLayout" },
  { match = "well fed circle", page = "wellFed" },
  { match = "target cast bar", page = "castBars" },
  { match = "buffs manquants", page = "aurasMissingBuffs" },
  { match = "resource circle", page = "resourceCircle" },
  { match = "auras à tracker", page = "aurasTracked" },
  { match = "auras to track", page = "aurasTracked" },
  { match = "barres de cast", page = "castBars" },
  { match = "cercle central", page = "resourceCircle" },
  { match = "central circle", page = "resourceCircle" },
  { match = "movement buffs", page = "movementBuffs" },
  { match = "health circle", page = "outOfCombat", section = "SETTINGS_SEC_HEALTH_CIRCLE" },
  { match = "cercle de vie", page = "outOfCombat", section = "SETTINGS_SEC_HEALTH_CIRCLE" },
  { match = "cadres d'unit", page = "unitBars" },
  { match = "themed colors", page = "colors" },
  { match = "barre de menu", page = "menuBar" },
  { match = "vol dynamique", page = "skyriding" },
  { match = "animations 3d", page = "spellEffects" },
  { match = "barre de cast", page = "castBars" },
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
  { match = "bien nourri", page = "wellFed" },
  { match = "barre d'xp", page = "xpBar" },
  { match = "unit frame", page = "unitBars" },
  { match = "extra bars", page = "extraBars" },
  { match = "afk screen", page = "afkMode" },
  { match = "cdm layout", page = "cdmLayout" },
  { match = "liste d'ic", page = "aurasIconlist" },
  { match = "top target", page = "topTargetBar" },
  { match = "skyriding", page = "skyriding" },
  { match = "icon list", page = "aurasIconlist" },
  { match = "cast bars", page = "castBars" },
  { match = "campement", page = "campfire" },
  { match = "toptarget", page = "topTargetBar" },
  { match = "cast bar", page = "castBars" },
  { match = "menu bar", page = "menuBar" },
  { match = "afk mode", page = "afkMode" },
  { match = "cran afk", page = "afkMode" },
  { match = "profiles", page = "profiles" },
  { match = "location", page = "location" },
  { match = "3d anim", page = "spellEffects" },
  { match = "profils", page = "profiles" },
  { match = "camping", page = "campfire" },
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
    version = "4.8",
    categories = { actionBars = true, fishing = true },
    containers = { unitBars = true, visibility = true },
    headers = {
      "SETTINGS_CAT_ACTION_BARS", "SETTINGS_CAT_FISHING",
      "UNITBARS_SEC_PVP", "UNITBARS_SEC_DISPEL", "SETTINGS_SEC_VIS_GROUP_FRAMES",
    },
  },
  {
    version = "4.6",
    categories = { castBars = true, campfire = true, cdmAppearance = true, addonCompartment = true, taxiMode = true },
    containers = { unitBars = true, xpBar = true, comfortQoL = true, visibility = true, movementBuffs = true, outOfCombat = true },
    headers = {
      "SETTINGS_CAT_CAST_BARS", "SETTINGS_CAT_CAMPFIRE", "SETTINGS_CAT_TAXI_MODE", "SETTINGS_CAT_CDM_APPEARANCE", "SETTINGS_CAT_ADDON_COMPARTMENT",
      "UNITBARS_SEC_FILL", "UNITBARS_SEC_DOTS", "SETTINGS_SEC_XP_RESTED", "ADDONFONTS_SEC_BAGANATOR",
      "SETTINGS_MVB_SEC_STACKS",
      "SETTINGS_SEC_MANA_REGEN", "SETTINGS_COMFORT_SEC_PROFESSIONS",
    },
  },
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

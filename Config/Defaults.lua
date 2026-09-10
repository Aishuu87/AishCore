-- Config/Defaults.lua : Valeurs par défaut et thèmes par spécialisation
local addonName, ns = ...

ns.Defaults = {
  -- Cercle de ressource (mana)
  resourceCircle = {
    enabled = true,
    size = 80,
    bgSize = 88,
    arcSize = 64,
    arcOffsetX = 27,
    arcOffsetY = 5,
    fontSize = 14,
    font = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    x = 0,
    y = 0,
    anchor = "CENTER",
    textColor = { 0, 176/255, 255/255, 1 },
    dotColors = {
      { 0.8, 0, 0.8 },
      { 1, 0.2, 0.8 },
      { 1, 0.2, 0.6 },
      { 1, 0.2, 0.8 },
      { 0.8, 0, 0.8 },
    },
    dotSizes = { 3, 5, 9, 5, 3 },
    dotPositions = {
      { -19, 8 }, { -11, 3 }, { 0, 0 }, { 11, 3 }, { 19, 8 },
    },
    -- Cercles secondaires (runes DK, combo points, etc.)
    secondaryDotsRotation = 90,  -- angle central en degres (90 = au dessus)
    secondaryDotsSpread = 24,    -- ecartement en degres entre chaque dot
    secondaryDotsSize = 0.16,    -- taille relative au cercle principal
    secondaryDotsRadius = 0.62,  -- distance relative au cercle principal
    secondaryDotsReversed = false, -- ordre inversé (gauche→droite)
    -- Glow de fond (Circle_Smooth2, derriere le bg, couleur de spec via Colors.Get("glow"))
    glowEnabled = true,
    glowSize    = 1.0,    -- multiplicateur de taille par rapport a bgLarge (1.0 = meme taille)
    glowOpacity = 0.85,   -- opacite (0 = invisible, 1 = opaque)
    -- Arc circulaire (circle_piecrop) + overlay masque centre
    arcSizeRatio = 1.0,  -- taille de l'arc par rapport a cfg.size
    overlayRatio = 0.75, -- taille de l'overlay par rapport a l'arc (0.0 - 0.99)
    -- [EXPERIMENTAL] Remplissage radial (horaire, depuis midi) au lieu du
    -- remplissage vertical bas->haut. Bascule via /rcradial. Voir ResourceCircle.lua.
    radialFillTest = false,
    -- Arc secondaire de stagger (Moine Brasseur)
    staggerArcRatio     = 0.72,  -- taille relative a arcPx (doit tenir dans le trou de l'overlay)
    staggerOverlayRatio = 0.76,  -- overlay interne du cercle de stagger
    staggerShowPercent  = false, -- afficher le % de stagger sous le texte de ressource
    -- Arc de durée dans le cercle central (spés tank)
    consecrationArcEnabled = true,  -- Pala Prot (specID 66) : Consécration
    ignorePainArcEnabled   = true,  -- Guerrier Prot (specID 73) : Dur au mal
    dndArcEnabled          = true,  -- DK Sang (specID 250) : sort 188290
    manaTeaArcEnabled      = true,  -- Moine Mistweaver (specID 270) : Thé de Mana
    -- Devourer (specID 1480) : opt-in, feature neuve pas encore confirmee en jeu
    devourerArcEnabled     = false,
    -- Evoker Augmentation (specID 1473) : idem, opt-in par defaut
    ebonyPowerArcEnabled   = false,
    durationArcRatio        = 0.72, -- taille de l'arc de durée (identique au stagger par défaut)
    durationArcOverlayRatio = 0.76, -- épaisseur (overlay intérieur)
    durationArcColorR = nil,  -- nil = couleur par défaut du spec
    durationArcColorG = nil,
    durationArcColorB = nil,
    -- Contenu de l'arc de durée pour Guerrier Prot (specID 73) : false (défaut) =
    -- décompte le temps restant ; true = rempli selon le nombre de stacks de
    -- Dur au Mal (approximation de l'absorption restante, cf. CenterArc.lua)
    ignorePainArcAbsorb = false,
    -- Texte de ressource secondaire (Bone Shield, Soul Fragments, Dévoreur…)
    secResTextSize    = 11,  -- taille police
    secResTextOffsetX =  0,  -- décalage horizontal par rapport au texte de ressource
    secResTextOffsetY = -2,  -- décalage vertical (négatif = vers le bas)
    secResFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    secResDecoStyle   = "dash", -- cf. ns.SEC_RES_DECO_STYLES dans ResourceCircle.lua
    secResDecoSpacing = 4,      -- espace (px) entre le texte et chaque déco
    secResDecoFont    = nil,    -- nil = reprend secResFont
    -- Abrège les grands nombres de la ressource secondaire (ex: absorb Dur au Mal :
    -- 12345 -> "12.3k") via AbbreviateNumbers. false = nombre brut.
    secResAbsorbAbbreviate = false,
    -- Globes de Puissance Sacrée en spé Protection / Vindicte
    holyPowerAllSpecs = false,
    -- Globes d'Essence en spé Dévastation / Augmentation
    essenceAllSpecs = false,
    -- Mode de visibilite : "always" | "target" | "combat" (default)
    visibilityMode = "combat",
  },

  -- Cercle de vie
  healthCircle = {
    enabled = true,
    size = 40,
    bgSize = 44,
    arcSize = 32,
    arcOffsetX = 13,
    arcOffsetY = 2,
    fontSize = 9,
    font = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    x = 200,
    y = 100,
    anchor = "BOTTOMLEFT_OFFSET",  -- spécial : calculé depuis BOTTOMLEFT + offset %
    anchorPctX = 0.22,
    anchorPctY = 0.28,
    barColor = { 0.2, 0.9, 0.2, 1 },
    textColor = { 0.3, 0.9, 0.3, 1 },
    dotColors = {
      { 0.1, 0.5, 0.1 },
      { 0.2, 0.7, 0.2 },
      { 0.3, 0.9, 0.3 },
      { 0.2, 0.7, 0.2 },
      { 0.1, 0.5, 0.1 },
    },
    dotSizes = { 0.4, 3, 7, 3, 0.4 },
    dotPositions = {
      { -9, 1 }, { -5, 1 }, { 0, 0 }, { 5, 1 }, { 9, 1 },
    },
    hideDelay = 2.5,  -- secondes sans changement de vie avant de considérer full
    -- Arc circulaire (circle_piecrop) + overlay masque centre
    arcSizeRatio = 1.0,  -- taille de l'arc par rapport a cfg.size
    overlayRatio = 0.75, -- taille de l'overlay par rapport a l'arc (0.0 - 0.99)
    -- Mode de visibilite : "always" | "important" (default)
    visibilityMode = "important",
    -- Pouls battement de coeur OOC
    heartbeatPulse = true,
  },

  -- Cercle de ressource hors combat (meme logique que resourceCircle, visible seulement hors combat)
  outOfCombatResourceCircle = {
    enabled = true,
    size = 40,
    fontSize = 9,
    font = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    -- Position : meme systeme que healthCircle (pct depuis BOTTOMLEFT + offset pixel)
    -- Par defaut : directement au-dessus du cercle de vie (meme ancre %, decalage Y = rayon HC + rayon OCRC + gap)
    anchorPctX = 0.22,
    anchorPctY = 0.28,
    x = 0,
    y = 44,   -- 44px vers le haut : rayon HC(20) + rayon OCRC(20) + ecart(4)
    -- Cercles secondaires (combo points, etc. — pas de runes DK)
    secondaryDotsRotation = 90,
    secondaryDotsSpread   = 24,
    secondaryDotsSize     = 0.16,
    secondaryDotsRadius   = 0.62,
    secondaryDotsReversed = false, -- ordre inversé (gauche→droite)
    -- Arc circulaire (circle_piecrop) + overlay masque centre
    arcSizeRatio = 1.0,  -- taille de l'arc par rapport a cfg.size (0.5 - 1.0)
    overlayRatio = 0.75, -- taille de l'overlay par rapport a l'arc (0.0 - 0.99)
    -- [EXPERIMENTAL] Remplissage radial (comme resourceCircle) au lieu du vertical.
    radialFillTest = false,
    -- Globes de Puissance Sacrée en spé Protection / Vindicte (hors combat)
    holyPowerAllSpecs = false,
    -- Globes d'Essence en spé Dévastation / Augmentation (hors combat)
    essenceAllSpecs = false,
    -- Mode de visibilite : "always" | "important" (default)
    visibilityMode = "important",
    -- Glow de fond
    glowEnabled = true,
    glowSize    = 0.7,   -- plus petit que le RC principal (taille relative a bgLarge)
    glowOpacity = 0.7,
  },

  -- Barre d'experience (visible lors d'un gain XP ou au survol du coin bas-gauche)
  xpBar = {
    enabled = true,
    repEnabled     = true,        -- affiche la réputation au niveau max
    companionXP    = true,         -- affiche l'XP du compagnon de gouffre si en gouffre
    repDisplayMode = "tracked",   -- "tracked" | "lastGained"
    restIndicator  = true,        -- affiche l'animation de zone de repos (modèle 3D)
    restX          = 20,           -- offset X depuis BOTTOMLEFT de l'écran
    restY          = 20,           -- offset Y depuis BOTTOMLEFT de l'écran
    restScale      = 1.0,          -- échelle du modèle
    -- Badge de niveau (grunge bg) - modifiable via Mode Edition
    levelBg = { x = -20, y = -6.5, w = 87, h = 54, rot = 175 },
    -- Tooltip infos XP (grunge bg)
    tooltipFrame = {
      x = 46, y = 1.5, w = 175, h = 48,
      bgRot = 14, bgW = 244, bgH = 97, bgOffX = -100, bgOffY = 37,
    },
    fontLevel = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    levelOutlineStyle = "OUTLINE",
  },

  -- Fiche de personnage enrichie : agrandissement + fond derriere le modele,
  -- recoloration ilvl/enchant + gemmes/durabilite/alertes, indicateur de transmog.
  characterArmory = {
    enabled = true,

    -- zoneWidth = delta ajoute entre les 2 colonnes d'equipement (translate, pas resize)
    layoutEnabled = true,
    zoneWidth   = 0,    -- ecart AJOUTE entre les 2 colonnes d'equipement (0 = disposition Blizzard par defaut)
    -- 444 = hauteur "expanded" native Blizzard, slider resserre autour de cette valeur
    frameHeight = 444,
    modelScale  = 1.0,
    hideCorners = true, -- masque les coins de fond par defaut de Blizzard

    showWarning = true, -- SLE : toggle unique "Affiche l'icone d'avertissement"

    -- Niveau d'objet
    ilvl = {
      colorType = "QUALITY", -- "NONE" | "QUALITY" | "GRADIENT" (vs ilvl moyen equipe)
      xOffset = 0, yOffset = 0,
      font = nil, fontSize = 12, fontStyle = "OUTLINE", -- font nil = ns.Media.fontGui
    },

    -- Niveau d'objet GLOBAL (texte agrege natif Blizzard, distinct du ilvl par objet ci-dessus)
    globalIlvl = {
      enabled = false,
      font = nil, fontSize = 14, fontStyle = "OUTLINE", -- font/fontStyle nil = valeurs natives Blizzard
      color = nil, -- nil = couleur native Blizzard
      useSpecColor = false, -- force Couleurs > Cercle de Puissance a la place de "color"
    },

    -- Chaine d'enchantement
    enchant = {
      showReal = true, -- texte "reel" (avec icone de qualite crafting) via scan tooltip, au lieu du texte court de Blizzard
      iconOnly = false, -- si showReal : masque le nom de l'enchant, garde uniquement l'icone de qualite
      font = nil, fontSize = 12, fontStyle = "OUTLINE",
      xOffset = 0, yOffset = 0,
    },

    -- Base de gemme
    gem = {
      size = 14, xOffset = 0, yOffset = 0,
      showTooltips = true, -- pas de toggle chez SLE (tooltip toujours actif) ; garde d'AishCore
    },

    -- Transmogrification
    transmog = {
      enableArrow = true,  -- icone cliquable sur le slot
      enableGlow  = true,
      glowStyleIdx = 2,    -- index dans ns.GLOW_DEFS (1 = "Aucun" = pas de glow)
      glowOffset  = 1,
      glowColor   = { 1, 0.82, 0, 0.8 },
      iconSize    = 14,
    },

    -- Degrade : quad teinte derriere l'icone, distinct de la couleur du texte ilvl
    gradient = {
      enable = true,
      color = { 0.41, 0.83, 1 },
      quality = false,          -- true = couleur de rarete de l'objet au lieu de `color`
      setArmor = false, setArmorColor = { 0, 1, 0 },
      warningColor    = { 1, 0.2, 0.2 }, -- teinte du quad quand une alerte est active sur le slot
      warningBarColor = { 1, 0.2, 0.2 }, -- couleur de la barre d'alerte elle-meme
    },

    -- Durabilite
    durability = {
      display = "Always", -- "Always" | "DamagedOnly" | "Hide"
      font = nil, fontSize = 10, fontStyle = "OUTLINE",
      xOffset = 0, yOffset = 0,
      warnPct = 30, -- en dessous de ce %, le texte de durabilite passe en rouge
    },

    -- Fond (derriere le modele 3D)
    background = {
      selectedBG = "Space", -- HIDE | CUSTOM | CLASS | Arena-bliz | Space | TheEmpire | Castle | Alliance-text | Horde-text
      customTexture = "",
    },
  },

  -- Effets 3D de spells (Animations)
  spellEffects = {
    enabled = true,
    -- Décorations "Orbes" (globes autour du cercle de ressource selon l'état
    -- de la ressource de classe : combo points, runes, essence...) : flag
    -- indépendant de `enabled` ci-dessus (qui couvre aussi les animations
    -- d'impact de sort) pour permettre de couper l'un sans l'autre depuis la
    -- page "Modules". Lu par GetValidOrbKeys() dans SpellEffects.lua.
    orbsEnabled = true,
    modelSize = 200,
    -- Ancien format compat (sera ignoré si combos existe)
    spells = {},  -- vide par défaut ; les anciens IDs (8004, 17364) ont été retirés
    -- Nouveau format : combos sort → liste d'animations
    -- combos[spellID] = {
    --   { modelID=123, duration=0.8, z=0, x=0, y=0, rotation=0,
    --     scale=1, alpha=1, delay=0, anchorX=0, anchorY=0, strata="BACKGROUND" },
    --   ...
    -- }
    combos = {},
    orbCombos = {},
    oocCombos = {},
  },

  -- Assistant de rotation : icone du sort highlighte, miroir du highlight Blizzard
  rotationHelper = {
    enabled = true,
    iconSize = 40,
    anchor = "TOP",
    x = 0,
    y = -220,
    -- Glow : meme systeme que priorityBar (LOOP_GLOW_TYPES). 2="Pulse" (texture fixe,
    -- toujours presente) car les types flipbook atlas ne sont pas garantis sur tous les clients.
    loopGlowIndex = 2,
    glowColor = { 1, 0.85, 0, 0.8 },
    glowSize = 4,
    useSpecGlowColor = false,  -- si true, utilise la couleur Glow du module Couleurs (spec active)
    -- Visibilite : memes reglages que priorityBar
    visibilityMode = "combat",
    alwaysInInstance = false,
    ignoreWhileResting = false,  -- zone de repos : meme logique que MissingBuffs.lua, opt-in
  },

  -- Priority Bar : 4 icones fixes (2 gauche + 2 droite du cercle de ressource)
  priorityBar = {
    enabled = true,
    iconSize = 34,
    iconSpacing = 6,       -- espace entre les 2 icones d'un meme cote
    sideOffset = 170,      -- distance du bord externe de chaque cote depuis le centre de l'ecran
    _sideOffsetV2 = true,  -- marqueur : sideOffset utilise le format V2 (ancre bord externe)
    verticalOffset = 0,    -- decalage vertical global
    -- Cooldown swipe
    showCooldownSwipe = true,
    -- Bordure
    showBorder = true,
    borderStyle = "solid",     -- "solid", "glow", "shadow"
    borderSize = 2,
    borderColor = { 0.15, 0.15, 0.15, 0.9 },
    -- Charges
    showCharges = true,
    chargePosition = "BOTTOMRIGHT",
    chargeOffsetX  = 0,
    chargeOffsetY  = 0,
    chargeFontSize = 12,
    chargeColor = { 1, 1, 1, 1 },
    -- Texte de cooldown
    showCooldownText = false,
    cooldownFontSize = 14,
    cooldownTextColor = { 1, 1, 1, 1 },
    -- Desaturation
    desaturateOnCooldown = true,
    -- Masquer les sorts non appris
    hideUnlearned = true,
    -- Glow
    glowType = "pulse",        -- LEGACY (migration) — ignored if loopGlowIndex is set
    loopGlowIndex = 2,        -- index dans LOOP_GLOW_TYPES (1 = Aucun, 2 = Pulse)
    _loopGlowTypeMigrated = true,  -- flag migration: "Aucun" inséré en index 1 (shift +1)
    procStartIndex = 1,       -- index dans PROC_START_TYPES (1 = Aucun)
    glowColor = { 1, 0.85, 0, 0.8 },
    glowSize = 4,
    useSpecGlowColor = false,  -- si true, utilise la couleur Glow du module Couleurs (spec active)
    spellColors = {},          -- [spellID] = {r, g, b, a} : couleur de glow individuelle par sort
    -- Mode de visibilite : "always" | "target" | "combat" (default)
    visibilityMode = "combat",
    -- Slots par specialisation (specID → N slots selon le layout)
    slotsBySpec = {},
    -- Layout par specialisation (specID → layout ID string, e.g. "2x2")
    layoutBySpec = {},
    -- Tooltip au survol des icones de buff/debuff (module Auras) : par defaut
    -- toujours visible. Si true, en combat le tooltip n'apparait que tant
    -- qu'ALT est maintenu (evite de saturer l'ecran de tooltips en plein
    -- combat) ; hors combat, il reste toujours visible au survol.
    tooltipAltCombatOnly = false,
  },

  -- Cooldown Manager Essentiels / Utilitaires : personnalisation des viewers natifs Blizzard
  -- (meme forme pour cdmEssential / cdmUtility, valeurs independantes)
  cdmEssential = {
    enabled = false,  -- opt-in : evite un changement de comportement surprise a l'install
    -- Layout / grille
    growUp = true, growRight = false,
    gridLayoutType = 3,      -- 1=centre / 2=standard / 3=standard (garde l'espace vide)
    hideWhenInactive = 1,    -- 1=jamais masquer / 2=sauf aura / 3=sauf CD/aura/charges
    strideOverride = 0,      -- 0=stride natif Blizzard / N=force N icones par ligne (evite le retour a la ligne)
    useItemSize = false, itemSize = 40,
    -- Couleurs par etat (icone)
    useNormalColor = false, normalColor = { 1, 1, 1, 1 },             normalDesaturate = false,
    useCdColor     = false, cdColor     = { 0.6, 0.6, 0.6, 1 },       cdDesaturate     = true,
    useGcdColor    = false, gcdColor    = { 0.8, 0.8, 0.8, 1 },       gcdDesaturate    = false,
    useOorColor    = false, oorColor    = { 0.64, 0.15, 0.15, 1 },    oorDesaturate    = false,
    useOomColor    = false, oomColor    = { 0.5, 0.5, 1.0, 1 },       oomDesaturate    = false,
    useNouseColor  = false, nouseColor  = { 0.4, 0.4, 0.4, 1 },       nouseDesaturate  = true,
    useAuraColor   = false, auraColor   = { 0.3, 0.8, 0.0, 1 },       auraDesaturate   = false,
    -- Bordure / backdrop
    useBackdrop = false, backdropSize = 1, backdropColor = { 0, 0, 0, 1 },
    useBackdropAuraColor = false, backdropAuraColor = { 0.3, 0.8, 0.0, 1 },
    useBackdropPandemicColor = false, backdropPandemicColor = { 0.8, 0.3, 0.0, 1 },
    -- Cooldown swipe
    useCooldownColor = false, cooldownColor = { 0, 0, 0, 0.5 },
    useCooldownAuraColor = false, cooldownAuraColor = { 0, 0, 0, 0.5 },
    reverseSwipe = false, auraReverseSwipe = false,
    removeGCDSwipe = false, auraRemoveSwipe = false,
    -- Pandemie
    removePandemic = false,
    -- Decompte (Cooldown:GetCountdownFontString())
    useCooldownFontColor = false, cooldownFontColor = { 1, 1, 1, 1 },
    cooldownFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    useCooldownFontSize = false, cooldownFontSize = 17,
    cooldownPoint = "CENTER", cooldownOffsetX = 0, cooldownOffsetY = 0,
    -- Stacks (child.Applications -- compteur de stacks d'aura)
    useStacksColor = false, stacksColor = { 1, 1, 1, 1 },
    stacksFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    useStacksFontSize = false, stacksFontSize = 16,
    stacksPoint = "BOTTOMRIGHT", stacksOffsetX = 0, stacksOffsetY = 0,
    -- Charges (child.ChargeCount -- compteur de charges de sort)
    useChargesColor = false, chargesColor = { 1, 1, 1, 1 },
    chargesFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    useChargesFontSize = false, chargesFontSize = 16,
    chargesPoint = "BOTTOMRIGHT", chargesOffsetX = 0, chargesOffsetY = 0,
    showCountdownNumbersForCharges = true,
    -- Masque d'icone (1..5, atlas Blizzard uniquement)
    iconMaskIndex = 1,
    -- Fondu (fading) : opacite selon combat / cible / incantation / survol
    useFading = false, fadeAlpha = 0.35,
    fadeInCombat = false, fadeOnTarget = false, fadeOnCasting = false, fadeOnHover = true,
  },
  cdmUtility = {
    enabled = false,
    growUp = true, growRight = false,
    gridLayoutType = 3,
    hideWhenInactive = 1,
    strideOverride = 0,
    useItemSize = false, itemSize = 40,
    useNormalColor = false, normalColor = { 1, 1, 1, 1 },             normalDesaturate = false,
    useCdColor     = false, cdColor     = { 0.6, 0.6, 0.6, 1 },       cdDesaturate     = true,
    useGcdColor    = false, gcdColor    = { 0.8, 0.8, 0.8, 1 },       gcdDesaturate    = false,
    useOorColor    = false, oorColor    = { 0.64, 0.15, 0.15, 1 },    oorDesaturate    = false,
    useOomColor    = false, oomColor    = { 0.5, 0.5, 1.0, 1 },       oomDesaturate    = false,
    useNouseColor  = false, nouseColor  = { 0.4, 0.4, 0.4, 1 },       nouseDesaturate  = true,
    useAuraColor   = false, auraColor   = { 0.3, 0.8, 0.0, 1 },       auraDesaturate   = false,
    useBackdrop = false, backdropSize = 1, backdropColor = { 0, 0, 0, 1 },
    useBackdropAuraColor = false, backdropAuraColor = { 0.3, 0.8, 0.0, 1 },
    useBackdropPandemicColor = false, backdropPandemicColor = { 0.8, 0.3, 0.0, 1 },
    useCooldownColor = false, cooldownColor = { 0, 0, 0, 0.5 },
    useCooldownAuraColor = false, cooldownAuraColor = { 0, 0, 0, 0.5 },
    reverseSwipe = false, auraReverseSwipe = false,
    removeGCDSwipe = false, auraRemoveSwipe = false,
    removePandemic = false,
    useCooldownFontColor = false, cooldownFontColor = { 1, 1, 1, 1 },
    cooldownFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    useCooldownFontSize = false, cooldownFontSize = 17,
    cooldownPoint = "CENTER", cooldownOffsetX = 0, cooldownOffsetY = 0,
    useStacksColor = false, stacksColor = { 1, 1, 1, 1 },
    stacksFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    useStacksFontSize = false, stacksFontSize = 16,
    stacksPoint = "BOTTOMRIGHT", stacksOffsetX = 0, stacksOffsetY = 0,
    useChargesColor = false, chargesColor = { 1, 1, 1, 1 },
    chargesFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    useChargesFontSize = false, chargesFontSize = 16,
    chargesPoint = "BOTTOMRIGHT", chargesOffsetX = 0, chargesOffsetY = 0,
    showCountdownNumbersForCharges = true,
    iconMaskIndex = 1,
    useFading = false, fadeAlpha = 0.35,
    fadeInCombat = false, fadeOnTarget = false, fadeOnCasting = false, fadeOnHover = true,
  },

  -- Visibilite : opacite d'elements tiers (ElvUI...) ajustee via SetAlpha (pas de lockdown combat)
  visibility = {
    -- Zone de buffs ElvUI (ElvuiPlayerBuffs)
    elvuiBuffsEnabled       = true,
    elvuiBuffsOocAlpha      = 0.2,  -- opacite hors combat
    elvuiBuffsCombatAlpha   = 1.0,  -- opacite en combat
    elvuiBuffsHoverReveal   = true, -- survol = 100% temporairement
  },

  -- Barre de cast joueur
  castBar = {
    enabled       = true,
    locked        = false,
    width         = 260,
    height        = 3,
    x             = 0,
    y             = -120,
    nameSize      = 12,
    nameOffX      = 0,
    nameOffY      = 9,
    nameJustify   = "CENTER",
    timerSize     = 8,
    timerOffX     = 1,
    timerOffY     = 2,
    timerJustify  = "RIGHT",
    colorBySchool = false,
    barColor      = { 0.471, 0.392, 0.271, 1 },
    font          = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    nameOutlineStyle = "OUTLINE",
    timerFont     = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    timerOutlineStyle = "OUTLINE",
  },

  -- Barre de cast cible
  targetCastBar = {
    enabled       = true,
    locked        = false,
    width         = 260,
    height        = 3,
    x             = 260,
    y             = -120,
    showIcon      = true,
    nameSize      = 12,
    nameOffX      = 0,
    nameOffY      = 9,
    nameJustify   = "CENTER",
    timerSize     = 8,
    timerOffX     = 1,
    timerOffY     = 2,
    timerJustify  = "RIGHT",
    font          = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    nameOutlineStyle = "OUTLINE",
    timerFont     = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    timerOutlineStyle = "OUTLINE",
    colorInterruptible    = { 0, 0.78, 0.78, 1 },        -- turquoise
    colorImportant        = { 0.855, 0.239, 1, 1 },       -- #DA3DFF
    colorNotInterruptible = { 0.765, 0.294, 0.290, 1 },   -- #C34B4A
    colorChanneling       = { 0.506, 0.788, 0.243, 1 },   -- #81C93E
  },

  -- Barres de vie par unité (Player, Target, Focus, Pet, TargetTarget)
  unitBars = {
    enabled          = true,
    locked           = false,
    reversed         = false,
    hideOutOfCombat  = false,  -- legacy, remplace par visibilityMode
    -- Mode de visibilite : "always" | "target" | "combat" (default)
    visibilityMode   = "combat",
    showAbsorb       = true,   -- afficher la barre de bouclier (absorb) en bleu sur les barres de vie
    absorbColor      = { 0, 1, 0.918, 1 },  -- couleur de la barre d'absorb (#00FFEA par défaut)
    absorbReversed   = false,               -- true = absorb à gauche (miroir), false = à droite (défaut)
    showDots         = true,   -- afficher les 3 petits ronds sur le côté des barres
    dotSize          = 9,
    dotRatio         = 0,      -- 0=proportionnel, 100=tous identiques
    dotGap           = 3,
    textSize         = 8,
    font             = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    hpOutlineStyle   = "OUTLINE",
    hpDisplayMode    = "pct",  -- "pct" = pourcentage 0-100, "value" = valeur abreviee
    nameSize         = 14,
    nameFont         = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    nameOutlineStyle = "OUTLINE",
    useTankHeight    = false,
    tankHeight       = 8,
    bgColor = { 0.0549, 0.0549, 0.0549, 1 },  -- #0e0e0e
    bars = {
      player = {
        enabled = true, width = 200, height = 4,
        x = -260, y = -120,
        fillColor = { 0.78, 0.61, 0.44, 1 },
        nameOffX = 0, nameOffY = 2,
      },
      target = {
        enabled = true, width = 200, height = 4,
        x = 260, y = -120,
        fillColor = { 0.72, 0.59, 0.39, 1 },
        nameOffX = 0, nameOffY = 2,
      },
      focus = {
        enabled = true, width = 200, height = 4,
        x = -260, y = -145,
        fillColor = { 0.71, 0.60, 0.49, 1 },
        nameOffX = 0, nameOffY = 2,
      },
      pet = {
        enabled = true, width = 143, height = 4,
        x = -260, y = -100,
        fillColor = { 0.71, 0.60, 0.49, 1 },
        nameOffX = 0, nameOffY = 2,
      },
      targettarget = {
        enabled = true, width = 80,  height = 4,
        x = 260, y = -145,
        fillColor = { 0.41, 0.41, 0.41, 1 },
        nameOffX = 0, nameOffY = 2,
      },
    },
  },

  -- Numero de sous-groupe de raid (1-8), overlay RAID uniquement (jamais solo/groupe simple)
  groupNumber = {
    enabled = true,
    badgeSize = 28,
    badgePosition = "TOP",  -- ancrage sur le conteneur de groupe ElvUI (mode multi-vignettes)
    badgeX = -260, badgeY = -95, -- pres de la barre "player" par defaut
    badgeColor = { 0, 0, 0, 0.85 },
    font = nil, -- nil = ns.Media.font
    textSize = 16,
    textOutlineStyle = "OUTLINE",
    textColor = { 1, 1, 1, 1 },
    textOffsetX = 0, textOffsetY = 0,
  },

  -- Curseur en combat, cf. Modules/BigCursor.lua. cursorSize est un INDEX
  -- Blizzard (pas un facteur d'echelle continu), valeurs valides 1-4
  -- (CooldownFrameSize[-1..4] = 64,64,96,128,192,256px -- 2 = taille par defaut).
  bigCursor = {
    enabled = true,
    cursorSize = 2,
  },

  -- Barre de cible détaillée (haut d'écran) + cible de la cible
  topTargetBar = {
    enabled = true,
    -- Position du conteneur target (ancre WorldFrame TOP, 0 = bord physique)
    x   = 0,    y   = 0,
    -- Fond noir (taille indépendante du conteneur)
    bgW  = 530,  bgH  = 35,   bgOX  = 0,    bgOY  = 0,
    -- Barre de vie target (offset relatif au conteneur)
    barW  = 525,  barH  = 2,    barOX  = 0,    barOY  = -22,
    -- Texte nom/niveau (offset relatif au conteneur)
    nameOX = 0,   nameOY = -5,
    -- Texte HP (ancre + offset relatifs à la barre de vie)
    hpAnchor = "LEFT",  hpOX = 5,  hpOY = -19,  hpFontSize = 10,
    nameFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    hpFont   = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
    -- Position du conteneur targettarget
    ttx = 0,    tty = -75,
    -- Fond noir targettarget
    ttBgW = 125,  ttBgH = 24,  ttBgOX = 0,  ttBgOY = 0,
    -- Barre de vie targettarget (offset relatif au conteneur)
    ttBarW = 124,  ttBarH = 1.7,  ttBarOX = 0,   ttBarOY = -10.161,
    -- Texte nom targettarget
    ttNameOX = 0,  ttNameOY = 0.860,
    -- Cible de la cible : afficher ou non
    showTargetOfTarget = true,
    -- Barre de ressource (énergie / mana / rage…) sous la barre de vie
    showPowerBar = false,
  },

  -- Buffs / Debuffs de la cible (sous la TopTargetBar)
  targetAuras = {
    enabled       = true,
    offsetX       = 0,
    offsetY       = -4,
    -- Sous-table Buffs
    buffs = {
      maxAuras       = 16,
      iconSize       = 26,
      iconSpacing    = 2,
      numRows        = 1,
      rowSpacing     = 2,
      growUpward     = false,   -- false = vers le bas, true = vers le haut
      rowWidth       = 530,
      growDirection   = "RIGHT",
      sortMode       = "playerFirst",
      offsetX        = 0,
      offsetY        = 0,
      -- Bordure
      showBorder     = true,
      borderSize     = 1,
      borderColor    = { 1, 1, 1, 0.15 },
      -- Cooldown swipe
      showSwipe      = true,
      reverseSwipe   = false,
      -- Police durée (position du countdown natif C++)
      durationFont     = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
      durationFontSize = 9,
      durationColor    = { 1, 1, 1, 1 },
      durationAnchor   = "CENTER",   -- CENTER, TOP, BOTTOM, TOPLEFT, BOTTOMRIGHT…
      durationOffX     = 0,
      durationOffY     = 0,
      -- Police stacks
      countFont        = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Bold.ttf",
      countFontSize    = 10,
      countOutlineStyle = "OUTLINE",
      countColor       = { 1, 1, 1, 1 },
      countAnchor      = "BOTTOMRIGHT",
      countRelPoint    = "BOTTOMRIGHT",
      countOffX        = -1,
      countOffY        = 1,
    },
    -- Sous-table Debuffs
    debuffs = {
      onlyPlayer     = false,   -- true = n'afficher que les debuffs du joueur
      maxAuras       = 16,
      iconSize       = 26,
      iconSpacing    = 2,
      numRows        = 1,
      rowSpacing     = 2,
      growUpward     = false,   -- false = vers le bas, true = vers le haut
      rowWidth       = 530,
      growDirection   = "RIGHT",
      sortMode       = "playerFirst",
      reverseSort    = false,
      offsetX        = 0,
      offsetY        = -2,
      -- Bordure (debuffs : couleur par type de dispel par défaut)
      showBorder     = true,
      borderSize     = 1,
      borderColor    = { 0.80, 0, 0, 1 },
      -- Cooldown swipe
      showSwipe      = true,
      reverseSwipe   = false,
      -- Police durée (position du countdown natif C++)
      durationFont     = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
      durationFontSize = 9,
      durationColor    = { 1, 1, 1, 1 },
      durationAnchor   = "CENTER",   -- CENTER, TOP, BOTTOM, TOPLEFT, BOTTOMRIGHT…
      durationOffX     = 0,
      durationOffY     = 0,
      -- Police stacks
      countFont        = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Bold.ttf",
      countFontSize    = 10,
      countOutlineStyle = "OUTLINE",
      countColor       = { 1, 1, 1, 1 },
      countAnchor      = "BOTTOMRIGHT",
      countRelPoint    = "BOTTOMRIGHT",
      countOffX        = -1,
      countOffY        = 1,
    },
  },

  -- Module Skyriding (port du WeakAura [SKYRIDING] - FIXE)
  skyriding = {
    enabled              = false,
    hideAtLanding        = false, -- masque le HUD lorsque la vitesse est nulle
    -- Modules à masquer pendant le Skyriding (toggles individuels)
    hideResourceCircle   = true,  -- cercle de ressource (combat)
    hideHealthCircle     = true,  -- cercle de vie (hors combat)
    hideOOCResourceCircle= true,  -- cercle de ressource (hors combat)
    hideUnitBars         = true,  -- barres d'unités
    hidePriorityBar      = true,  -- barre de priorité
    hideRotationHelper   = true,  -- aide à la rotation
    colorMode     = "custom", -- "custom" | "spec" | "mount"
    colorNoGlow   = { 0.45, 0.45, 0.45, 1 },       -- couleur sans buff (mode custom)
    colorGlow     = { 0, 0.8824, 0.5373, 1 },       -- couleur avec buff (mode custom)
    orbSize       = 19,   -- taille des orbes extérieurs (charges de vigueur)
    orbRadius     = 65,   -- rayon absolu des orbes (px, distance au centre)
    orbStartAngle = 210,  -- angle de départ du premier orbe (degrés)
    orbSpacing    = 24,   -- espacement angulaire entre les orbes (degrés)
    dotSize       = 3,    -- taille des points Second Souffle (px)
    dotOffsetX    = 0,    -- décalage X des points par rapport au centre
    dotOffsetY    = -12,  -- décalage Y des points par rapport au centre
    x             = 0,    -- offset horizontal depuis BOTTOM de UIParent
    y             = 250,  -- offset vertical depuis BOTTOM de UIParent
    scale         = 0.8,  -- échelle globale
    bgSize        = 120,  -- cercle de fond
    speedSize     = 110,  -- cercle de vitesse (pie-chart)
    mask1Size     = 102,  -- masque 1 (couvre le centre du speed)
    ascentSize    = 98,   -- cercle d'ascension (pie-chart)
    mask2Size     = 85,   -- masque 2 (couvre le centre de l'ascension)
    textSize      = 14,   -- taille police vitesse
    font          = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
  },

  -- Mode AFK : ecran plein ecran affiche quand le joueur passe AFK, remplace l'ecran natif.
  -- "elements" : config par item (texte/blason), anchor = point standard sur l'ECRAN ENTIER.
  afkMode = {
    enabled = true,

    -- Panneaux haut/bas + animation d'entree
    animType          = "slideIn", -- "none" | "slideIn" | "slideSide"
    animTime          = 0.3,       -- secondes (0 = pas d'animation)
    animBounce        = true,
    panelTopHeight    = 60,
    panelBottomHeight = 100,
    panelBgColor      = { 0, 0, 0, 0.85 },

    -- Modele 3D du joueur
    modelEnabled  = true,
    modelAnim     = "wave", -- wave | dance | salute | talk | shy | roar | lean | random
    modelDistance = 4.5,
    modelRotation = 0,
    modelXOffset  = -60,  -- decalage du support du modele (coin bas-droit du panneau bas)
    modelYOffset  = 0,

    timerCountdown = false, -- false = chrono qui monte, true = compte a rebours (deconnexion 30 min)
    tipThrottle    = 12,    -- secondes entre 2 astuces

    -- Couleur d'accent (date, ":" de l'heure, chevrons de guilde...) — pas
    -- un "element" (pas de position/taille propre, juste une teinte reutilisee
    -- a plusieurs endroits). useThemeColors=true l'ignore et reutilise la
    -- couleur "texte de puissance" (Colors.Get("powertext")) de la spe active.
    accentColor    = { 0, 0.667, 1, 1 }, -- bleu clair par defaut (= 00AAFF)
    useThemeColors = false,
    themeColorKey  = "powertext", -- quel element du module Couleurs utiliser quand useThemeColors=true

    -- Divers
    cameraSpin     = true,
    chatShow       = true,
    exitOnKeypress = true,

    -- Elements individuels (textes + blasons/logos). useSpecColor/specColorKey : pioche la
    -- couleur dans le module Couleurs (ELEMENT_KEYS) au lieu d'une couleur fixe.
    elements = {
      timer       = { enable = true, font = nil, size = 20, color = {1,1,1,1},       anchor = "TOP",         x = 0,   y = -8,  outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" },
      playerName  = { enable = true, font = nil, size = 16, color = {1,1,1,1},       anchor = "BOTTOMLEFT",  x = 12,  y = 60,  outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" },
      playerClass = { enable = true, font = nil, size = 13, color = {1,1,1,1},       anchor = "BOTTOMLEFT",  x = 12,  y = 44,  outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" },
      playerLevel = { enable = true, font = nil, size = 13, color = {1,1,1,1},       anchor = "BOTTOMLEFT",  x = 12,  y = 28,  outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" },
      guild       = { enable = true, font = nil, size = 12, color = {0.7,0.7,0.7,1}, anchor = "BOTTOMLEFT",  x = 12,  y = 12,  outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" },
      date        = { enable = true, font = nil, size = 12, color = {1,1,1,1},       anchor = "TOPRIGHT",    x = -12, y = -8,  format = "dayMonth", outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" }, -- "dayMonth" ("28 Aout, Vendredi") | "monthDay" ("Aout 28, Vendredi")
      time        = { enable = true, font = nil, size = 12, color = {1,1,1,1},       anchor = "TOPRIGHT",    x = -12, y = -24, outlineStyle = "OUTLINE", useSpecColor = false, specColorKey = "powercircle" },
      tips        = { enable = true, font = nil, size = 11, color = {1,1,1,1},       anchor = "BOTTOM",      x = 0,   y = 8,   lineWidth = 500, useSpecColor = false, specColorKey = "powercircle" }, -- largeur de retour a la ligne (ScrollingMessageFrame)

      crestClass    = { enable = true,  style = "sltheme",  anchor = "BOTTOMRIGHT", x = -220, y = 8, width = 40, height = 40 },
      crestFaction  = { enable = true,  style = "blizzard", anchor = "BOTTOMRIGHT", x = -176, y = 8, width = 40, height = 40 },
      logoFaction   = { enable = false, style = "blizzard", anchor = "BOTTOMLEFT",  x = 12,   y = 8, width = 64, height = 64 },
      crestRace     = { enable = true,  style = "blizzard", anchor = "BOTTOMRIGHT", x = -132, y = 8, width = 40, height = 40 },
      logoExpansion = { enable = true,  style = "auto",     anchor = "TOPLEFT",     x = 12,   y = -8, width = 96, height = 32 },
      aishLogo      = { enable = false,                     anchor = "TOPRIGHT",    x = -12,  y = -44, width = 48, height = 48 }, -- texture fixe, pas de "style"
    },
  },

  -- Thèmes par spécialisation (specID)
  themes = {
    -- Shaman Enhancement (263)
    [263] = {
      resourceCircle = {
        textColor = { 0, 176/255, 255/255, 1 },
        dotColors = {
          { 0.8, 0, 0.8 }, { 1, 0.2, 0.8 }, { 1, 0.2, 0.6 }, { 1, 0.2, 0.8 }, { 0.8, 0, 0.8 },
        },
      },
    },
    -- Shaman Elemental (262)
    [262] = {
      resourceCircle = {
        textColor = { 1, 0.4, 0, 1 },
        dotColors = {
          { 1, 0.3, 0 }, { 1, 0.5, 0.1 }, { 1, 0.6, 0.2 }, { 1, 0.5, 0.1 }, { 1, 0.3, 0 },
        },
      },
    },
    -- Shaman Restoration (264)
    [264] = {
      resourceCircle = {
        textColor = { 0.2, 0.9, 0.4, 1 },
        dotColors = {
          { 0.1, 0.6, 0.3 }, { 0.2, 0.8, 0.4 }, { 0.3, 0.9, 0.5 }, { 0.2, 0.8, 0.4 }, { 0.1, 0.6, 0.3 },
        },
      },
    },
  },

  -- Couleurs par spécialisation (overrides utilisateur)
  colors = {
    useClassDefaults = true,
    overrides = {},
  },

  -- Bouton de minimap
  minimapButton = {
    angle = 225,   -- position angulaire en degrés autour de la minimap
    hidden = false,
  },

  -- Etat de la page "Modules" : categoryOff = categories desactivees en bloc,
  -- snapshot = etat individuel sauvegarde pour restaurer au lieu de tout remettre ON
  modulesPanel = {
    categoryOff = {},
    snapshot = {},
  },
}

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
    -- Arc secondaire de stagger (Moine Brasseur)
    staggerArcRatio     = 0.72,  -- taille relative a arcPx (doit tenir dans le trou de l'overlay)
    staggerOverlayRatio = 0.76,  -- overlay interne du cercle de stagger
    staggerShowPercent  = false, -- afficher le % de stagger sous le texte de ressource
    -- Arc de durée dans le cercle central (spés tank)
    consecrationArcEnabled = true,  -- Pala Prot (specID 66) : Consécration
    ignorePainArcEnabled   = true,  -- Guerrier Prot (specID 73) : Dur au mal
    dndArcEnabled          = true,  -- DK Sang (specID 250) : sort 188290
    durationArcRatio        = 0.72, -- taille de l'arc de durée (identique au stagger par défaut)
    durationArcOverlayRatio = 0.76, -- épaisseur (overlay intérieur)
    durationArcColorR = nil,  -- nil = couleur par défaut du spec
    durationArcColorG = nil,
    durationArcColorB = nil,
    -- Texte de ressource secondaire (Bone Shield, Soul Fragments, Dévoreur…)
    secResTextSize    = 11,  -- taille police
    secResTextOffsetX =  0,  -- décalage horizontal par rapport au texte de ressource
    secResTextOffsetY = -2,  -- décalage vertical (négatif = vers le bas)
    secResFont = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
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
  },

  -- Effets 3D de spells (Animations)
  spellEffects = {
    enabled = true,
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

  -- Assistant de rotation : icones des sorts highlightes
  rotationHelper = {
    enabled = false,
    iconSize = 40,
    iconSpacing = 4,
    maxIcons = 8,
    anchor = "TOP",
    x = 0,
    y = -220,
    growDirection = "RIGHT",  -- RIGHT ou LEFT
  },

  -- Priority Slots : 4 icones fixes autour du cercle de ressource
  -- Chaque slot contient une liste de spellIDs ordonnes par priorite
  -- Le sort highlight prend la priorite d'affichage, sinon le premier est affiche
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
    timerFont     = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
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
    timerFont     = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
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
    hpDisplayMode    = "pct",  -- "pct" = pourcentage 0-100, "value" = valeur abreviee
    nameSize         = 14,
    nameFont         = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf",
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
}

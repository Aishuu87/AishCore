-- Data/GuiLayout.lua : disposition des sections du GUI reglee en mode disposition (/aishlayout, UI/LayoutEditor.lua),
-- reportee depuis "Exporter". Page -> cle de locale du titre de section -> colonnes, rangees (colonne -> widget :
-- "dbKey.subKey", "type:libelle" ou separateur "__div:N") et libelles renommes (par langue, repli anglais) ;
-- __sections : sections ajoutees, __titles : titres renommes. Une disposition enregistree en jeu passe devant.
-- Barres du CDM : identifiants de la barre Essentiels, valables aussi pour Utilitaires ; texte secondaire du cercle
-- central : identifiants sans la spe (cf. WidgetId). Widgets sans cle DB : identifies par leur libelle francais,
-- disposition ignoree dans une autre langue (la section garde celle de la page).
local addonName, ns = ...

ns.GUI_LAYOUT = {
  cdmAppearance = {
    ["SETTINGS_SEC_CDM_BORDER"] = { cols = 5, rows = {
      { [1] = "cdmEssential.useBackdrop" },
      { [1] = "cdmEssential.backdropSize", [2] = "cdmEssential.backdropColor" },
      { [1] = "cdmEssential.useBackdropAuraColor", [3] = "cdmEssential.backdropAuraColor" },
      { [1] = "cdmEssential.useBackdropPandemicColor", [3] = "cdmEssential.backdropPandemicColor" },
    } },
    ["SETTINGS_SEC_CDM_CHARGES"] = { cols = 4, rows = {
      { [1] = "cdmEssential.chargesFont", [2] = "cdmEssential.useChargesFontSize", [3] = "cdmEssential.chargesFontSize" },
      { [2] = "cdmEssential.useChargesColor", [3] = "cdmEssential.chargesColor" },
      { [1] = "cdmEssential.chargesPoint", [2] = "cdmEssential.chargesOffsetX", [3] = "cdmEssential.chargesOffsetY" },
      { [1] = "cdmEssential.showCountdownNumbersForCharges" },
    }, labels = {
      ["cdmEssential.chargesColor"] = { frFR = "Couleur", enUS = "Color" },
      ["cdmEssential.useChargesColor"] = { frFR = "Couleur personnalisée", enUS = "Custom color" },
      ["cdmEssential.useChargesFontSize"] = { frFR = "Taille personnalisée", enUS = "Custom size" },
    } },
    ["SETTINGS_SEC_CDM_COLORS"] = { cols = 4, rows = {
      { [1] = "cdmEssential.iconMaskIndex" },
    } },
    ["SETTINGS_SEC_CDM_COOLDOWN_FONT"] = { cols = 4, rows = {
      { [1] = "cdmEssential.cooldownFont", [2] = "cdmEssential.useCooldownFontSize", [3] = "cdmEssential.cooldownFontSize" },
      { [2] = "cdmEssential.useCooldownFontColor", [3] = "cdmEssential.cooldownFontColor" },
      { [1] = "cdmEssential.cooldownPoint", [2] = "cdmEssential.cooldownOffsetX", [3] = "cdmEssential.cooldownOffsetY" },
    }, labels = {
      ["cdmEssential.cooldownFontColor"] = { frFR = "Couleur", enUS = "Color" },
      ["cdmEssential.useCooldownFontColor"] = { frFR = "Couleur personnalisée", enUS = "Custom color" },
      ["cdmEssential.useCooldownFontSize"] = { frFR = "Taille personnalisée", enUS = "Custom size" },
    } },
    ["SETTINGS_SEC_CDM_FADING"] = { cols = 5, rows = {
      { [1] = "cdmEssential.useFading", [2] = "cdmEssential.fadeAlpha" },
      { [1] = "cdmEssential.fadeOnHover" },
      { [1] = "cdmEssential.fadeInCombat" },
      { [1] = "cdmEssential.fadeOnTarget" },
      { [1] = "cdmEssential.fadeOnCasting" },
    }, labels = {
      ["cdmEssential.fadeOnHover"] = { frFR = "Au survol", enUS = "On mouseover" },
    } },
    ["SETTINGS_SEC_CDM_LAYOUT"] = { cols = 4, rows = {
      { [1] = "cdmEssential.gridLayoutType", [2] = "cdmEssential.growRight", [3] = "cdmEssential.growUp" },
      { [1] = "cdmEssential.hideWhenInactive", [2] = "cdmEssential.strideOverride" },
      { [1] = "cdmEssential.useItemSize", [2] = "cdmEssential.itemSize" },
      { [1] = "cdmEssential.useIconSpacing", [2] = "cdmEssential.iconSpacing" },
    } },
    ["SETTINGS_SEC_CDM_PANDEMIC"] = { cols = 4, rows = {
      { [1] = "cdmEssential.removePandemic" },
    }, labels = {
      ["cdmEssential.removePandemic"] = { frFR = "Masquer l'animation de flash de pandémie", enUS = "Hide the pandemic flash animation" },
    } },
    ["SETTINGS_SEC_CDM_POSITION"] = { cols = 4, rows = {
      { [1] = "cdmEssential.linkToPlayerBar" },
      { [1] = "cdmEssential.linkSide", [2] = "cdmEssential.linkGap", [3] = "cdmEssential.linkOffset" },
    } },
    ["SETTINGS_SEC_CDM_STACKS_FONT"] = { cols = 4, rows = {
      { [1] = "cdmEssential.stacksFont", [2] = "cdmEssential.useStacksFontSize", [3] = "cdmEssential.stacksFontSize" },
      { [2] = "cdmEssential.useStacksColor", [3] = "cdmEssential.stacksColor" },
      { [1] = "cdmEssential.stacksPoint", [2] = "cdmEssential.stacksOffsetX", [3] = "cdmEssential.stacksOffsetY" },
    }, labels = {
      ["cdmEssential.stacksColor"] = { frFR = "Couleur", enUS = "Color" },
      ["cdmEssential.useStacksColor"] = { frFR = "Couleur personnalisée", enUS = "Custom color" },
      ["cdmEssential.useStacksFontSize"] = { frFR = "Taille personnalisée", enUS = "Custom size" },
    } },
    ["SETTINGS_SEC_CDM_SWIPE"] = { cols = 5, rows = {
      { [1] = "cdmEssential.useCooldownColor", [3] = "cdmEssential.cooldownColor" },
      { [1] = "cdmEssential.useCooldownAuraColor", [3] = "cdmEssential.cooldownAuraColor" },
      { [1] = "__div:1" },
      { [1] = "cdmEssential.reverseSwipe", [3] = "cdmEssential.removeGCDSwipe" },
      { [1] = "cdmEssential.auraReverseSwipe", [3] = "cdmEssential.auraRemoveSwipe" },
    } },
  },
  comfortQoL = {
    ["SETTINGS_COMFORT_AUTO_TURNIN"] = { cols = 4, rows = {
      { [1] = "comfort.questTurnInBox", [2] = "comfort.questTurnInSize" },
    } },
    ["SETTINGS_COMFORT_SEC_INTERFACE"] = { cols = 5, rows = {
      { [1] = "comfort.merchantExtend", [3] = "comfort.merchantPages" },
      { [1] = "comfort.horizonOffWithRXP" },
      { [1] = "comfort.hideErrors" },
      { [1] = "comfort.spellIDTooltip", [3] = "comfort.spellIDModifier" },
    } },
    ["SETTINGS_COMFORT_SEC_SHORTCUTS"] = { cols = 5, rows = {
      { [1] = "comfort.shortcuts", [3] = "comfort.ctrlFocus" },
      { [1] = "comfort.minimapTracking", [3] = "comfort.doubleClickFish" },
    } },
    ["SETTINGS_MAPREVEAL_TITLE"] = { cols = 6, rows = {
      { [1] = "comfort.mapReveal" },
      { [1] = "comfort.mapRevealColored", [2] = "comfort.mapRevealColor" },
    } },
    ["SETTINGS_MOD_BIG_CURSOR"] = { cols = 4, rows = {
      { [1] = "bigCursor.enabled" },
      { [1] = "bigCursor.cursorSize" },
    } },
  },
  outOfCombat = {
    __titles = {
      ["SETTINGS_SEC_HC_SIZE_POS"] = { frFR = "TAILLE & POSITION", enUS = "Size & Position" },
      ["SETTINGS_SEC_HC_VISIBILITY"] = { frFR = "VISIBILITÉ", enUS = "Visibility" },
      ["SETTINGS_SEC_HP_TEXT"] = { frFR = "TEXTE DE LA VIE", enUS = "Health Text" },
      ["SETTINGS_SEC_OCRC_SIZE_POS"] = { frFR = "TAILLE & POSITION", enUS = "Size & Position" },
      ["SETTINGS_SEC_OCRC_VISIBILITY"] = { frFR = "VISIBILITÉ", enUS = "Visibility" },
    },
    ["SETTINGS_SEC_BG_GLOW_OOC"] = { cols = 4, rows = {
      { [1] = "outOfCombatResourceCircle.glowEnabled" },
      { [1] = "outOfCombatResourceCircle.glowSize", [2] = "outOfCombatResourceCircle.glowOpacity" },
    }, labels = {
      ["outOfCombatResourceCircle.glowEnabled"] = { frFR = "Activer la lueur du cercle", enUS = "Enable circle glow" },
      ["outOfCombatResourceCircle.glowOpacity"] = { frFR = "Opacité", enUS = "Opacity" },
      ["outOfCombatResourceCircle.glowSize"] = { frFR = "Taille", enUS = "Size" },
    } },
    ["SETTINGS_SEC_HC_SIZE_POS"] = { cols = 4, rows = {
      { [1] = "healthCircle.size", [2] = "healthCircle.arcSizeRatio", [3] = "healthCircle.arcThickness" },
      { [1] = "healthCircle.arcStartAngle", [2] = "healthCircle.arcEndAngle" },
      { [1] = "healthCircle.arcFillMode", [2] = "healthCircle.arcFillInverted" },
    }, labels = {
      ["healthCircle.arcSizeRatio"] = { frFR = "Rayon de l'arc", enUS = "Arc radius" },
    } },
    ["SETTINGS_SEC_HC_VISIBILITY"] = { cols = 4, rows = {
      { [1] = "check:$SETTINGS_VIS_ALWAYS" },
      { [1] = "check:$SETTINGS_VIS_IMPORTANT" },
      { [1] = "healthCircle.alwaysInInstance" },
      { [1] = "__div:1" },
      { [1] = "healthCircle.clickable" },
      { [1] = "healthCircle.heartbeatPulse" },
    } },
    ["SETTINGS_SEC_OCRC_SIZE_POS"] = { cols = 4, rows = {
      { [1] = "outOfCombatResourceCircle.size", [2] = "outOfCombatResourceCircle.arcSizeRatio", [3] = "outOfCombatResourceCircle.arcThickness" },
      { [1] = "outOfCombatResourceCircle.arcStartAngle", [2] = "outOfCombatResourceCircle.arcEndAngle" },
      { [1] = "outOfCombatResourceCircle.arcFillMode", [2] = "outOfCombatResourceCircle.arcFillInverted", [4] = "button:$SETTINGS_OCRC_RESET_POSITION" },
    }, labels = {
      ["outOfCombatResourceCircle.arcSizeRatio"] = { frFR = "Rayon de l'arc", enUS = "Arc radius" },
    } },
  },
  priorityBar = {
    ["SETTINGS_SEC_BORDER"] = { cols = 5, rows = {
      { [1] = "priorityBar.showBorder" },
      { [1] = "priorityBar.borderStyle", [2] = "priorityBar.borderSize", [3] = "priorityBar.borderColor" },
    } },
    ["SETTINGS_SEC_COOLDOWN"] = { cols = 5, rows = {
      { [1] = "priorityBar.showCooldownText" },
      { [1] = "priorityBar.showCooldownSwipe" },
      { [1] = "priorityBar.cooldownFont", [2] = "priorityBar.cooldownFontSize", [3] = "priorityBar.cooldownTextColor" },
    } },
    ["SETTINGS_SEC_GLOW"] = { cols = 5, rows = {
      { [1] = "priorityBar.loopGlowIndex", [2] = "priorityBar.procStartIndex" },
      { [1] = "priorityBar.glowSize", [2] = "priorityBar.glowColor", [3] = "priorityBar.useSpecGlowColor" },
    }, labels = {
      ["priorityBar.glowColor"] = { frFR = "Couleur", enUS = "Color" },
      ["priorityBar.glowSize"] = { frFR = "Taille", enUS = "Size" },
      ["priorityBar.loopGlowIndex"] = { frFR = "Type de lueur", enUS = "Glow type" },
      ["priorityBar.procStartIndex"] = { frFR = "Animation d'affichage", enUS = "Show animation" },
      ["priorityBar.useSpecGlowColor"] = { frFR = "Couleurs thématiques", enUS = "Themed colors" },
    } },
    ["SETTINGS_SEC_GLOW_PROCS"] = { cols = 5, rows = {
      { [1] = "priorityBar.procGlowEnabled" },
      { [1] = "priorityBar.procGlowRoleOnly" },
      { [1] = "__div:3" },
      { [1] = "priorityBar.procGlowLoopIndex", [2] = "priorityBar.procGlowStartIndex" },
      { [1] = "priorityBar.procGlowSize", [2] = "priorityBar.procGlowColor", [3] = "priorityBar.procGlowUseSpecColor" },
    }, labels = {
      ["priorityBar.procGlowColor"] = { frFR = "Couleur", enUS = "Color" },
      ["priorityBar.procGlowLoopIndex"] = { frFR = "Type de lueur", enUS = "Glow type" },
      ["priorityBar.procGlowRoleOnly"] = { frFR = "Seulement en rôle Soigneur & Tank", enUS = "Healer & Tank role only" },
      ["priorityBar.procGlowSize"] = { frFR = "Taille", enUS = "Size" },
      ["priorityBar.procGlowStartIndex"] = { frFR = "Animation d'affichage", enUS = "Show animation" },
      ["priorityBar.procGlowUseSpecColor"] = { frFR = "Couleurs thématiques", enUS = "Themed colors" },
    } },
    ["SETTINGS_SEC_KEYBIND"] = { cols = 5, rows = {
      { [1] = "priorityBar.showKeybind" },
      { [1] = "priorityBar.keybindFont", [2] = "priorityBar.keybindFontSize", [3] = "priorityBar.keybindColor" },
      { [1] = "priorityBar.keybindPosition", [2] = "priorityBar.keybindOffsetX", [3] = "priorityBar.keybindOffsetY" },
    } },
    ["SETTINGS_SEC_SIZE_POSITION"] = { cols = 5, rows = {
      { [1] = "priorityBar.iconSize", [2] = "priorityBar.iconSpacing", [3] = "priorityBar.sideOffset", [4] = "priorityBar.verticalOffset", [5] = "priorityBar.verticalOffsetTank" },
    }, labels = {
      ["priorityBar.iconSize"] = { frFR = "Taille des icônes", enUS = "Icon size" },
      ["priorityBar.sideOffset"] = { frFR = "Décalage Horizontal", enUS = "Horizontal offset" },
      ["priorityBar.verticalOffset"] = { frFR = "Décalage vertical", enUS = "Vertical offset" },
    } },
    ["SETTINGS_SEC_SPELL_CHARGES"] = { cols = 5, rows = {
      { [1] = "priorityBar.showCharges" },
      { [1] = "priorityBar.chargeFont", [2] = "priorityBar.chargeFontSize", [3] = "priorityBar.chargeColor" },
      { [1] = "priorityBar.chargePosition", [2] = "priorityBar.chargeOffsetX", [3] = "priorityBar.chargeOffsetY" },
    } },
    ["SETTINGS_SEC_VISIBILITY"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_VIS_ALWAYS" },
      { [1] = "check:$SETTINGS_VIS_TARGET" },
      { [1] = "check:$SETTINGS_VIS_COMBAT" },
      { [1] = "priorityBar.alwaysInInstance" },
      { [1] = "__div:1" },
      { [1] = "priorityBar.desaturateOnCooldown" },
      { [1] = "priorityBar.outOfRangeTint", [2] = "priorityBar.outOfRangeColor", [3] = "priorityBar.outOfRangeUseTheme" },
      { [1] = "__div:2" },
      { [1] = "priorityBar.hideUnlearned" },
      { [1] = "priorityBar.tooltipAltCombatOnly" },
    } },
  },
  resourceCircle = {
    ["SETTINGS_SEC_BG_GLOW"] = { cols = 5, rows = {
      { [1] = "resourceCircle.glowEnabled" },
      { [1] = "resourceCircle.glowSize", [2] = "resourceCircle.glowOpacity" },
    } },
    ["SETTINGS_SEC_MAIN_RES"] = { cols = 5, rows = {
      { [1] = "resourceCircle.font", [2] = "resourceCircle.fontSize", [3] = "resourceCircle.textBackdropSize" },
      { [1] = "resourceCircle.textThemedColors", [2] = "resourceCircle.textColor" },
    } },
    ["SETTINGS_SEC_SECONDARY_RES_TEXT"] = { cols = 5, rows = {
      { [1] = "resourceCircle.secResFont", [2] = "resourceCircle.secResTextSize", [3] = "resourceCircle.secResTextOffsetX", [4] = "resourceCircle.secResTextOffsetY" },
      { [1] = "__div:1" },
      { [1] = "resourceCircle.secResDecoStyle", [2] = "resourceCircle.secResDecoFont", [3] = "resourceCircle.secResDecoSpacing", [4] = "resourceCircle.secResColor" },
    } },
    ["SETTINGS_SEC_SIZE_POSITION"] = { cols = 5, rows = {
      { [1] = "resourceCircle.size", [2] = "resourceCircle.arcSizeRatio", [3] = "resourceCircle.arcThickness" },
      { [1] = "resourceCircle.arcStartAngle", [2] = "resourceCircle.arcEndAngle", [3] = "resourceCircle.arcFillMode" },
      { [1] = "resourceCircle.bgColor", [2] = "resourceCircle.arcColor", [3] = "resourceCircle.themedColors" },
      { [1] = "resourceCircle.x", [2] = "resourceCircle.y" },
    } },
    ["SETTINGS_SEC_VISIBILITY"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_VIS_ALWAYS" },
      { [1] = "check:$SETTINGS_VIS_TARGET" },
      { [1] = "check:$SETTINGS_VIS_COMBAT" },
      { [1] = "resourceCircle.alwaysInInstance" },
    } },
  },
  rotationHelper = {
    ["SETTINGS_SEC_GLOW"] = { cols = 5, rows = {
      { [1] = "rotationHelper.loopGlowIndex", [2] = "rotationHelper.glowSize", [3] = "rotationHelper.glowColor", [4] = "rotationHelper.useSpecGlowColor" },
    }, labels = {
      ["rotationHelper.glowColor"] = { frFR = "Couleur", enUS = "Color" },
      ["rotationHelper.glowSize"] = { frFR = "Taille", enUS = "Size" },
      ["rotationHelper.loopGlowIndex"] = { frFR = "Type de lueur", enUS = "Glow type" },
      ["rotationHelper.useSpecGlowColor"] = { frFR = "Couleurs thématiques", enUS = "Themed colors" },
    } },
    ["SETTINGS_SEC_KEYBIND"] = { cols = 5, rows = {
      { [1] = "rotationHelper.showKeybind" },
      { [1] = "rotationHelper.keybindPosition", [2] = "rotationHelper.keybindOffsetX", [3] = "rotationHelper.keybindOffsetY" },
      { [1] = "rotationHelper.keybindFont", [2] = "rotationHelper.keybindFontSize", [3] = "rotationHelper.keybindColor" },
    } },
    ["SETTINGS_SEC_SIZE_POSITION"] = { cols = 5, rows = {
      { [1] = "rotationHelper.iconSize", [2] = "rotationHelper.x", [3] = "rotationHelper.y" },
    } },
  },
  castBars = {
    ["CASTBARS_SEC_NAME"] = { cols = 4, rows = {
      { [1] = "dropdown:$SETTINGS_FONT@$CASTBARS_SEC_NAME", [2] = "slider:$SETTINGS_FONT_SIZE@$CASTBARS_SEC_NAME", [3] = "dropdown:$SETTINGS_TEXT_OUTLINE@$CASTBARS_SEC_NAME" },
      { [1] = "dropdown:$UNITBARS_ANCHOR@$CASTBARS_SEC_NAME", [2] = "align:?@$CASTBARS_SEC_NAME", [3] = "slider:$SETTINGS_OFFSET_X@$CASTBARS_SEC_NAME", [4] = "slider:$SETTINGS_OFFSET_Y@$CASTBARS_SEC_NAME" },
      { [1] = "color:$SETTINGS_CB_TEXT_COLOR@$CASTBARS_SEC_NAME", [2] = "check:$CASTBARS_THEMED@$CASTBARS_SEC_NAME", [3] = "check:$CASTBARS_SCHOOL@$CASTBARS_SEC_NAME" },
    } },
    ["SETTINGS_SEC_SIZE_POSITION"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_WIDTH@$SETTINGS_SEC_SIZE_POSITION", [2] = "slider:$SETTINGS_HEIGHT@$SETTINGS_SEC_SIZE_POSITION", [3] = "slider:$SETTINGS_OFFSET_X@$SETTINGS_SEC_SIZE_POSITION", [4] = "slider:$SETTINGS_OFFSET_Y@$SETTINGS_SEC_SIZE_POSITION" },
    } },
    ["UNITBARS_SEC_FILL"] = { cols = 5, rows = {
      { [1] = "dropdown:$SETTINGS_BAR_TEXTURE@$UNITBARS_SEC_FILL", [2] = "align:?@$UNITBARS_SEC_FILL" },
      { [1] = "color:$SETTINGS_TCB_COLOR_INTERRUPTIBLE@$UNITBARS_SEC_FILL", [2] = "color:$SETTINGS_TCB_COLOR_NOT_INTERRUPTIBLE@$UNITBARS_SEC_FILL" },
      { [1] = "color:$SETTINGS_TCB_COLOR_IMPORTANT@$UNITBARS_SEC_FILL", [2] = "color:$SETTINGS_TCB_COLOR_CHANNELING@$UNITBARS_SEC_FILL" },
    } },
  },
  extraBars = {
    ["EXTRABARS_SEC_BACKGROUND"] = { cols = 5, rows = {
      { [1] = "check:$EXTRABARS_BG_SHOW" },
      { [1] = "dropdown:$EXTRABARS_BG_TEXTURE", [2] = "color:$EXTRABARS_BG_COLOR", [3] = "slider:$EXTRABARS_BG_EDGE", [4] = "slider:$EXTRABARS_BG_PAD_X", [5] = "slider:$EXTRABARS_BG_PAD_Y" },
      { [1] = "__div:1" },
      { [1] = "slider:$EXTRABARS_BG_BORDER_SIZE", [2] = "color:$EXTRABARS_BG_BORDER_COLOR" },
    } },
    ["EXTRABARS_SEC_COOLDOWN"] = { cols = 5, rows = {
      { [1] = "check:$EXTRABARS_COOLDOWN_NUMBERS" },
      { [1] = "check:$EXTRABARS_BANDAGE_CD" },
      { [1] = "dropdown:$SETTINGS_FONT#2", [2] = "slider:$SETTINGS_FONT_SIZE#2", [3] = "slider:$EXTRABARS_SWIPE_ALPHA", [4] = "color:$SETTINGS_TEXT_COLOR#2" },
    }, labels = {
      ["check:$EXTRABARS_BANDAGE_CD"] = { frFR = "Temps de recharge des bandages", enUS = "Bandage cooldowns" },
      ["check:$EXTRABARS_COOLDOWN_NUMBERS"] = { frFR = "Afficher les temps de recharge", enUS = "Show cooldown timers" },
    } },
    ["EXTRABARS_SEC_ICONS"] = { cols = 5, rows = {
      { [1] = "check:$EXTRABARS_BORDER", [2] = "check:$EXTRABARS_ICON_ZOOM" },
      { [1] = "color:$EXTRABARS_BORDER_COLOR" },
    } },
    ["EXTRABARS_SEC_KEYBINDS"] = { cols = 5, rows = {
      { [1] = "check:$EXTRABARS_SHOW_KEYBINDS" },
      { [1] = "dropdown:$SETTINGS_FONT#3", [2] = "slider:$SETTINGS_FONT_SIZE#3", [3] = "dropdown:$SETTINGS_TEXT_OUTLINE#2", [4] = "color:$SETTINGS_TEXT_COLOR#3" },
      { [1] = "dropdown:$EXTRABARS_TEXT_POSITION#2", [2] = "slider:$EXTRABARS_OFFSET_X#2", [3] = "slider:$EXTRABARS_OFFSET_Y#2" },
    } },
    ["EXTRABARS_SEC_LAYOUT"] = { cols = 5, rows = {
      { [1] = "slider:$EXTRABARS_MAX_BUTTONS", [2] = "slider:$EXTRABARS_PER_ROW", [3] = "dropdown:$EXTRABARS_ANCHOR", [4] = "dropdown:$EXTRABARS_START_CORNER", [5] = "check:$EXTRABARS_VERTICAL" },
      { [1] = "slider:$EXTRABARS_BUTTON_WIDTH", [2] = "slider:$EXTRABARS_BUTTON_HEIGHT", [3] = "slider:$EXTRABARS_SPACING" },
    } },
    ["EXTRABARS_SEC_STACKS"] = { cols = 5, rows = {
      { [1] = "check:$EXTRABARS_SHOW_STACKS" },
      { [1] = "dropdown:$SETTINGS_FONT", [2] = "slider:$SETTINGS_FONT_SIZE", [3] = "dropdown:$SETTINGS_TEXT_OUTLINE", [4] = "color:$SETTINGS_TEXT_COLOR" },
      { [1] = "dropdown:$EXTRABARS_TEXT_POSITION", [2] = "slider:$EXTRABARS_OFFSET_X", [3] = "slider:$EXTRABARS_OFFSET_Y" },
    } },
    ["SETTINGS_SEC_VISIBILITY"] = { cols = 5, rows = {
      { [1] = "dropdown:$EXTRABARS_VISIBILITY", [2] = "slider:$SETTINGS_OPACITY" },
      { [1] = "check:$EXTRABARS_MOUSEOVER", [2] = "slider:$EXTRABARS_MOUSEOVER_ALPHA" },
    } },
  },
  skyriding = {
    __sections = { { id = "__sec:1", after = "SETTINGS_SEC_SR_CIRCLE_SIZES" } },
    __titles = {
      ["SETTINGS_SEC_POSITION_SCALE"] = { frFR = "Taille & Position", enUS = "Size & Position" },
      ["SETTINGS_SEC_SR_CIRCLE_SIZES"] = { frFR = "Réglages des arcs", enUS = "Arc Settings" },
      ["SETTINGS_SEC_SR_SECOND_WIND"] = { frFR = "SECOND SOUFFLE", enUS = "Second Wind" },
      ["SETTINGS_SEC_SR_SPEED_TEXT"] = { frFR = "TEXTE DE VITESSE", enUS = "Speed Text" },
      ["__sec:1"] = { frFR = "ORBES (Charges)", enUS = "Orbs (Charges)" },
    },
    ["SETTINGS_SEC_COLORS"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_SR_COLOR_SPEC", [2] = "check:$SETTINGS_SR_COLOR_MOUNT", [3] = "check:$SETTINGS_SR_COLOR_CUSTOM" },
      { [3] = "color:$SETTINGS_SR_COLOR_NO_BUFF" },
      { [3] = "color:$SETTINGS_SR_COLOR_WITH_BUFF" },
    }, labels = {
      ["check:$SETTINGS_SR_COLOR_CUSTOM"] = { frFR = "Couleurs personnalisées", enUS = "Custom colors" },
      ["check:$SETTINGS_SR_COLOR_MOUNT"] = { frFR = "Couleurs de la monture", enUS = "Mount colors" },
      ["check:$SETTINGS_SR_COLOR_SPEC"] = { frFR = "Couleurs thématiques", enUS = "Themed colors" },
    } },
    ["SETTINGS_SEC_POSITION_SCALE"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_SR_GLOBAL_SCALE", [2] = "slider:$SETTINGS_OFFSET_X", [3] = "slider:$SETTINGS_OFFSET_Y" },
    } },
    ["SETTINGS_SEC_SR_CIRCLE_SIZES"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_SR_BG", [2] = "slider:$SETTINGS_SR_SPEED_CIRCLE", [3] = "slider:$SETTINGS_SR_MASK_1" },
      { [1] = "slider:$SETTINGS_SR_ASCENT_CIRCLE", [2] = "slider:$SETTINGS_SR_MASK_2" },
    }, labels = {
      ["slider:$SETTINGS_SR_ASCENT_CIRCLE"] = { frFR = "Rayon de l'arc d'Ascension", enUS = "Ascension arc radius" },
      ["slider:$SETTINGS_SR_BG"] = { frFR = "Taille du fond", enUS = "Background size" },
      ["slider:$SETTINGS_SR_MASK_1"] = { frFR = "Epaisseur de l'arc de vitesse", enUS = "Speed arc thickness" },
      ["slider:$SETTINGS_SR_MASK_2"] = { frFR = "Epaisseur de l'arc d'Ascension", enUS = "Ascension arc thickness" },
      ["slider:$SETTINGS_SR_SPEED_CIRCLE"] = { frFR = "Rayon de l'arc de vitesse", enUS = "Speed arc radius" },
    } },
    ["SETTINGS_SEC_SR_HIDE_DURING_FLIGHT"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_SR_HIDE_RC", [3] = "check:$SETTINGS_SR_HIDE_UB" },
      { [1] = "check:$SETTINGS_SR_HIDE_HC", [3] = "check:$SETTINGS_SEC_PRIORITY_BAR" },
      { [1] = "check:$SETTINGS_SR_HIDE_OCRC", [3] = "check:$SETTINGS_CAT_ROTATION_HELPER" },
    }, labels = {
      ["check:$SETTINGS_SR_HIDE_RC"] = { frFR = "Cercle central", enUS = "Central Circle" },
      ["check:$SETTINGS_SR_HIDE_UB"] = { frFR = "Barres de vie", enUS = "Unit Bars" },
    } },
    ["SETTINGS_SEC_SR_SECOND_WIND"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_SR_DOT_SIZE", [2] = "slider:$SETTINGS_OFFSET_X#2", [3] = "slider:$SETTINGS_OFFSET_Y#2" },
    }, labels = {
      ["slider:$SETTINGS_SR_DOT_SIZE"] = { frFR = "Taille des points", enUS = "Dot size" },
    } },
    ["SETTINGS_SEC_SR_SPEED_TEXT"] = { cols = 5, rows = {
      { [1] = "dropdown:$SETTINGS_SR_SPEED_FONT", [2] = "slider:$SETTINGS_FONT_SIZE" },
    }, labels = {
      ["dropdown:$SETTINGS_SR_SPEED_FONT"] = { frFR = "Police", enUS = "Font" },
    } },
    ["__sec:1"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_SR_ORB_SIZE", [2] = "slider:$SETTINGS_SR_ORB_RADIUS", [3] = "slider:$SETTINGS_SR_ORB_SPACING", [4] = "slider:$SETTINGS_SR_ORB_START_ANGLE" },
    }, labels = {
      ["slider:$SETTINGS_SR_ORB_RADIUS"] = { frFR = "Rayon de l'arc", enUS = "Arc radius" },
      ["slider:$SETTINGS_SR_ORB_SIZE"] = { frFR = "Taille", enUS = "Size" },
      ["slider:$SETTINGS_SR_ORB_SPACING"] = { frFR = "Espacement", enUS = "Spacing" },
      ["slider:$SETTINGS_SR_ORB_START_ANGLE"] = { frFR = "Angle de départ", enUS = "Start angle" },
    } },
  },
  topTargetBar = {
    ["SETTINGS_SEC_TOT_BLACK_BG"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_AFK_ELEMENT_WIDTH#3", [2] = "slider:$SETTINGS_AFK_ELEMENT_HEIGHT#3", [3] = "slider:$SETTINGS_OFFSET_X#7", [4] = "slider:$SETTINGS_OFFSET_Y#7" },
    } },
    ["SETTINGS_SEC_TOT_COLORED_BAR"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_AFK_ELEMENT_WIDTH#4", [2] = "slider:$SETTINGS_AFK_ELEMENT_HEIGHT#4", [3] = "slider:$SETTINGS_OFFSET_X#8", [4] = "slider:$SETTINGS_OFFSET_Y#8" },
    } },
    ["SETTINGS_SEC_TOT_CONTAINER"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_OFFSET_X#6", [2] = "slider:$SETTINGS_OFFSET_Y#6" },
    } },
    ["SETTINGS_SEC_TOT_NAME_TEXT"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_OFFSET_X#9", [2] = "slider:$SETTINGS_OFFSET_Y#9" },
    } },
    ["SETTINGS_SEC_TTB_BLACK_BG"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_AFK_ELEMENT_WIDTH", [2] = "slider:$SETTINGS_AFK_ELEMENT_HEIGHT", [3] = "slider:$SETTINGS_OFFSET_X#2", [4] = "slider:$SETTINGS_OFFSET_Y#2" },
    } },
    ["SETTINGS_SEC_TTB_COLORED_BAR"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_AFK_ELEMENT_WIDTH#2", [2] = "slider:$SETTINGS_AFK_ELEMENT_HEIGHT#2", [3] = "slider:$SETTINGS_OFFSET_X#3", [4] = "slider:$SETTINGS_OFFSET_Y#3", [5] = "topTargetBar.barTexture" },
    } },
    ["SETTINGS_SEC_TTB_CONTAINER"] = { cols = 5, rows = {
      { [1] = "slider:$SETTINGS_OFFSET_X", [2] = "slider:$SETTINGS_OFFSET_Y" },
    } },
    ["SETTINGS_SEC_TTB_HP_TEXT"] = { cols = 5, rows = {
      { [1] = "topTargetBar.hpFont", [2] = "slider:$SETTINGS_OFFSET_X#5", [3] = "slider:$SETTINGS_OFFSET_Y#5" },
      { [1] = "slider:$SETTINGS_FONT_SIZE", [2] = "align:?" },
    } },
    ["SETTINGS_SEC_TTB_NAME_TEXT"] = { cols = 5, rows = {
      { [1] = "topTargetBar.nameFont", [2] = "slider:$SETTINGS_OFFSET_X#4", [3] = "slider:$SETTINGS_OFFSET_Y#4" },
    } },
  },
  wellFed = {
    ["SETTINGS_SEC_SIZE_POSITION"] = { cols = 4, rows = {
      { [1] = "wellFedCircle.locked" },
      { [1] = "wellFedCircle.size", [2] = "wellFedCircle.arcSizeRatio", [3] = "wellFedCircle.arcThickness" },
      { [1] = "wellFedCircle.arcStartAngle", [2] = "wellFedCircle.arcEndAngle" },
      { [1] = "wellFedCircle.arcFillMode", [2] = "wellFedCircle.arcFillInverted", [4] = "button:$SETTINGS_WF_RESET_POSITION" },
    }, labels = {
      ["wellFedCircle.arcSizeRatio"] = { frFR = "Rayon de l'arc", enUS = "Arc radius" },
    } },
    ["SETTINGS_SEC_WF_COLOR_ICON"] = { cols = 4, rows = {
      { [1] = "wellFedCircle.eatingColor", [2] = "wellFedCircle.fedColor" },
      { [1] = "wellFedCircle.showFoodIcon", [2] = "wellFedCircle.foodIconScale" },
    } },
    ["SETTINGS_SEC_WF_GAIN"] = { cols = 5, rows = {
      { [1] = "wellFedCircle.plusDuration" },
      { [1] = "__div:2" },
      { [1] = "wellFedCircle.showPlus" },
      { [1] = "wellFedCircle.plusIconSize", [2] = "wellFedCircle.plusX", [3] = "wellFedCircle.plusY" },
      { [1] = "__div:1" },
      { [1] = "wellFedCircle.showStats", [2] = "wellFedCircle.statsShort" },
      { [1] = "wellFedCircle.statsSize", [2] = "wellFedCircle.statsFont", [3] = "wellFedCircle.statsOutline", [4] = "wellFedCircle.statsColor" },
      { [1] = "wellFedCircle.plusSize", [2] = "wellFedCircle.plusFont", [3] = "wellFedCircle.plusOutline" },
    } },
  },
  xpBar = {
    ["SETTINGS_SEC_XP_NEXTLEVEL"] = { cols = 5, rows = {
      { [1] = "xpBar.nextLevelPreview" },
      { [1] = "xpBar.questsAlwaysShown" },
      { [1] = "slider:$SETTINGS_XP_NL_SCALE" },
    } },
    ["SETTINGS_SEC_XP_REST"] = { cols = 5, rows = {
      { [1] = "xpBar.restIndicator", [3] = "button:$SETTINGS_XP_REST_TEST" },
      { [1] = "slider:$SETTINGS_XP_REST_SCALE", [2] = "slider:$SETTINGS_XP_REST_X", [3] = "slider:$SETTINGS_XP_REST_Y" },
    } },
    ["SETTINGS_SEC_XP_RESTED"] = { cols = 5, rows = {
      { [1] = "xpBar.restedColor", [2] = "xpBar.restedUseThemeColors", [3] = "xpBar.restedAlpha" },
    } },
    ["SETTINGS_SEC_XP_SETTINGS"] = { cols = 5, rows = {
      { [1] = "dropdown:$SETTINGS_XP_POSITION", [2] = "dropdown:$SETTINGS_XP_FILL" },
      { [1] = "__div:1" },
      { [1] = "xpBar.fontLevel", [2] = "slider:$SETTINGS_XP_LEVEL_SIZE" },
      { [1] = "__div:2" },
      { [1] = "xpBar.fontInfo", [2] = "slider:$SETTINGS_XP_INFO_SIZE" },
      { [1] = "__div:3" },
    } },
    ["XP_TOAST_HEADER"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_CAMPFIRE_ENABLE", [3] = "check:$XP_TOAST_WAIT_COMBAT" },
      { [1] = "button:$XP_TOAST_REPLAY", [2] = "check:$XP_TOAST_PREVIEW_SPELLS", [4] = "button:$XP_TOAST_TEST" },
      { [1] = "slider:$XP_TOAST_DURATION", [2] = "slider:$XP_TOAST_SCALE", [3] = "slider:$XP_TOAST_BG_SCALE", [4] = "slider:$XP_TOAST_BG_ALPHA" },
      { [1] = "slider:$SETTINGS_POSITION_X", [2] = "slider:$SETTINGS_POSITION_Y" },
      { [1] = "__div:4" },
      { [1] = "dropdown:$XP_TOAST_TITLE_FONT", [2] = "slider:$XP_TOAST_TITLE_SCALE", [3] = "color:$XP_TOAST_TITLE_COLOR" },
      { [1] = "__div:5" },
      { [1] = "dropdown:$XP_TOAST_STATS_FONT", [2] = "slider:$XP_TOAST_FONT_SCALE", [4] = "dropdown:$XP_TOAST_SPELL_FONT", [5] = "slider:$XP_TOAST_SPELL_SCALE" },
    } },
  },
  visibility = {
    ["ADDONFONTS_SEC_BAGANATOR"] = { cols = 5, rows = {
      { [1] = "addonFonts.bagItemEnabled" },
      { [2] = "addonFonts.bagItemFont", [3] = "addonFonts.bagItemSize", [4] = "addonFonts.bagItemOutline" },
      { [1] = "addonFonts.bagLabelEnabled" },
      { [2] = "addonFonts.bagLabelFont", [3] = "addonFonts.bagLabelSize", [4] = "addonFonts.bagLabelOutline" },
      { [1] = "addonFonts.bagSectionEnabled" },
      { [2] = "addonFonts.bagSectionFont", [3] = "addonFonts.bagSectionSize", [4] = "addonFonts.bagSectionOutline" },
    }, labels = {
      ["addonFonts.bagItemEnabled"] = { frFR = "Personnaliser les textes des icônes d'objets", enUS = "Customize item icon texts" },
      ["addonFonts.bagLabelEnabled"] = { frFR = "Personnaliser les noms des catégories", enUS = "Customize category names" },
      ["addonFonts.bagSectionEnabled"] = { frFR = "Personnaliser les en-têtes de sections", enUS = "Customize section headers" },
    } },
    ["ADDONFONTS_SEC_PLATYNATOR"] = { cols = 5, rows = {
      { [1] = "addonFonts.platAuraEnabled" },
      { [2] = "addonFonts.platAuraFont", [3] = "addonFonts.platAuraSize", [4] = "addonFonts.platAuraOutline" },
      { [1] = "addonFonts.platLevelEnabled" },
      { [2] = "addonFonts.platLevelFont", [3] = "addonFonts.platLevelSize", [4] = "addonFonts.platLevelOutline" },
    }, labels = {
      ["addonFonts.platAuraEnabled"] = { frFR = "Personnaliser les timers des buffs et debuffs", enUS = "Customize buff and debuff timers" },
      ["addonFonts.platLevelEnabled"] = { frFR = "Personnaliser le niveau", enUS = "Customize level" },
    } },
    ["SETTINGS_SEC_GROUP_NUMBER"] = { cols = 5, rows = {
      { [1] = "groupNumber.enabled" },
      { [1] = "subheader:$SETTINGS_SEC_GN_BADGE" },
      { [1] = "groupNumber.badgeSize", [2] = "groupNumber.badgeColor" },
      { [1] = "groupNumber.badgePosition", [2] = "groupNumber.badgeX", [3] = "groupNumber.badgeY" },
      { [1] = "subheader:$SETTINGS_SEC_GN_NUMBER" },
      { [1] = "groupNumber.font", [2] = "groupNumber.textSize", [3] = "groupNumber.textOutlineStyle", [4] = "groupNumber.textColor" },
      { [2] = "groupNumber.textOffsetX", [3] = "groupNumber.textOffsetY" },
    } },
    ["SETTINGS_SEC_VISIBILITY_ELVUI_BUFFS"] = { cols = 5, rows = {
      { [1] = "visibility.elvuiBuffsEnabled" },
      { [2] = "visibility.elvuiBuffsOocAlpha", [3] = "visibility.elvuiBuffsCombatAlpha", [4] = "visibility.elvuiBuffsHoverReveal" },
    } },
    ["SETTINGS_SEC_VIS_EUI_BARS"] = { cols = 5, rows = {
      { [1] = "visibility.euiBarsEnabled" },
      { [1] = "visibility.euiBarsAlpha" },
    } },
  },
  addonCompartment = {
    __titles = {
      ["ADDONCOMP_SEC_FAVORITES"] = { frFR = "FAVORIS", enUS = "Favorites" },
      ["ADDONCOMP_SEC_SUPPORTED"] = { frFR = "ADDONS SUIVIS", enUS = "Tracked Addons" },
    },
    ["ADDONCOMP_SEC_BUTTON"] = { cols = 5, rows = {
      { [1] = "dropdown:$EXTRABARS_BG_TEXTURE", [2] = "color:$EXTRABARS_BG_COLOR" },
      { [1] = "__div:2" },
      { [1] = "slider:$EXTRABARS_BG_BORDER_SIZE", [2] = "color:$EXTRABARS_BG_BORDER_COLOR" },
      { [1] = "__div:1" },
      { [1] = "dropdown:$SETTINGS_FONT", [2] = "slider:$SETTINGS_FONT_SIZE", [3] = "dropdown:$SETTINGS_TEXT_OUTLINE", [4] = "color:$SETTINGS_TEXT_COLOR", [5] = "check:$MENUBAR_THEMED" },
    } },
    ["ADDONCOMP_SEC_FAVORITES"] = { cols = 5, rows = {
      { [1] = "dropdown:$ADDONCOMP_ANCHOR#2", [2] = "slider:$ADDONCOMP_FAV_COLUMNS", [3] = "slider:$ADDONCOMP_FAV_ROWS", [4] = "slider:$SETTINGS_OFFSET_X#2", [5] = "slider:$SETTINGS_OFFSET_Y#2" },
      { [1] = "__div:6" },
      { [1] = "slider:$ADDONCOMP_ICON_SIZE#2", [2] = "slider:$ADDONCOMP_SPACING#2", [3] = "slider:$ADDONCOMP_FAV_ALPHA", [4] = "slider:$ADDONCOMP_FAV_HOVER_ALPHA" },
      { [1] = "__div:7" },
      { [1] = "dropdown:$ADDONCOMP_FAV_ICON_BG", [2] = "slider:$ADDONCOMP_FAV_ICON_PAD", [3] = "color:$EXTRABARS_BG_COLOR#4" },
      { [1] = "__div:8" },
      { [1] = "slider:$EXTRABARS_BG_BORDER_SIZE#4", [2] = "color:$EXTRABARS_BG_BORDER_COLOR#4" },
      { [1] = "subheader:$ADDONCOMP_SEC_FAV_BG" },
      { [1] = "dropdown:$ADDONCOMP_FAV_GRID_BG", [2] = "slider:$EXTRABARS_BG_PAD_X#2", [3] = "slider:$EXTRABARS_BG_PAD_Y#2", [4] = "slider:$EXTRABARS_BG_EDGE#2", [5] = "color:$EXTRABARS_BG_COLOR#3" },
      { [1] = "__div:9" },
      { [1] = "slider:$EXTRABARS_BG_BORDER_SIZE#3", [2] = "color:$EXTRABARS_BG_BORDER_COLOR#3" },
    } },
    ["ADDONCOMP_SEC_LIST"] = { cols = 5, rows = {
      { [1] = "check:$ADDONCOMP_ANIMATE" },
      { [1] = "dropdown:$ADDONCOMP_OPEN_MODE", [2] = "dropdown:$ADDONCOMP_LAYOUT", [3] = "dropdown:$ADDONCOMP_DIRECTION" },
      { [1] = "slider:$ADDONCOMP_GAP", [2] = "slider:$ADDONCOMP_LIST_COLUMNS", [3] = "slider:$ADDONCOMP_COLUMNS" },
      { [1] = "__div:3" },
      { [1] = "slider:$ADDONCOMP_ICON_SIZE", [2] = "slider:$ADDONCOMP_SPACING" },
      { [1] = "__div:4" },
      { [1] = "dropdown:$ADDONCOMP_LIST_FONT", [2] = "slider:$ADDONCOMP_LIST_FONT_SIZE", [3] = "color:$ADDONCOMP_LIST_COLOR", [4] = "color:$MENUBAR_HOVER_COLOR", [5] = "check:$MENUBAR_THEMED#2" },
    } },
    ["ADDONCOMP_SEC_POSITION"] = { cols = 5, rows = {
      { [1] = "dropdown:$ADDONCOMP_ANCHOR", [2] = "slider:$ADDONCOMP_BTN_SIZE", [3] = "slider:$SETTINGS_OFFSET_X", [4] = "slider:$SETTINGS_OFFSET_Y" },
    } },
    ["EXTRABARS_SEC_BACKGROUND"] = { cols = 5, rows = {
      { [1] = "dropdown:$EXTRABARS_BG_TEXTURE#2", [2] = "color:$EXTRABARS_BG_COLOR#2", [3] = "slider:$EXTRABARS_BG_PAD_X", [4] = "slider:$EXTRABARS_BG_PAD_Y", [5] = "slider:$EXTRABARS_BG_EDGE" },
      { [1] = "__div:5" },
      { [1] = "slider:$EXTRABARS_BG_BORDER_SIZE#2", [2] = "color:$EXTRABARS_BG_BORDER_COLOR#2" },
    } },
  },
  menuBar = {
    ["EXTRABARS_SEC_BACKGROUND"] = { cols = 5, rows = {
      { [1] = "check:$EXTRABARS_BG_SHOW" },
      { [1] = "dropdown:$EXTRABARS_BG_TEXTURE", [2] = "color:$EXTRABARS_BG_COLOR", [3] = "slider:$EXTRABARS_BG_PAD_X", [4] = "slider:$EXTRABARS_BG_PAD_Y", [5] = "slider:$EXTRABARS_BG_EDGE" },
      { [1] = "__div:2" },
      { [1] = "slider:$EXTRABARS_BG_BORDER_SIZE", [2] = "color:$EXTRABARS_BG_BORDER_COLOR" },
    } },
    ["MENUBAR_SEC_CLOCK"] = { cols = 5, rows = {
      { [1] = "check:$MENUBAR_CLOCK_ENABLE" },
      { [1] = "__div:3" },
      { [1] = "dropdown:$MENUBAR_CLOCK_POS", [2] = "check:$MENUBAR_CLOCK_24H", [3] = "check:$MENUBAR_CLOCK_SERVER", [4] = "check:$MENUBAR_CLOCK_BLINK" },
      { [1] = "__div:4" },
      { [1] = "dropdown:$SETTINGS_FONT", [2] = "slider:$SETTINGS_FONT_SIZE", [3] = "dropdown:$SETTINGS_TEXT_OUTLINE", [4] = "color:$SETTINGS_TEXT_COLOR", [5] = "check:$MENUBAR_THEMED#3" },
    } },
    ["MENUBAR_SEC_COLORS"] = { cols = 5, rows = {
      { [1] = "check:$MENUBAR_DESATURATE", [2] = "color:$MENUBAR_ICON_COLOR", [3] = "check:$MENUBAR_THEMED" },
      { [1] = "__div:1" },
      { [1] = "check:$MENUBAR_HOVER", [2] = "color:$MENUBAR_HOVER_COLOR", [3] = "check:$MENUBAR_THEMED#2" },
      { [1] = "check:$MENUBAR_HOVER_GROW" },
    } },
    ["MENUBAR_SEC_GENERAL"] = { cols = 5, rows = {
      { [1] = "check:$MENUBAR_TOOLTIP" },
      { [1] = "slider:$MENUBAR_ICON_SIZE", [2] = "slider:$EXTRABARS_SPACING" },
    } },
    ["SETTINGS_SEC_VISIBILITY"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_LOC_HIDE_COMBAT", [2] = "slider:$SETTINGS_OPACITY" },
      { [1] = "check:$EXTRABARS_MOUSEOVER", [2] = "slider:$EXTRABARS_MOUSEOVER_ALPHA" },
    } },
  },
  afkMode = {
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:aishLogo"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [1] = "afkElement.anchor", [2] = "afkElement.width", [3] = "afkElement.height", [4] = "afkElement.x", [5] = "afkElement.y" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:crestFaction"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [1] = "afkElement.anchor", [2] = "afkElement.width", [3] = "afkElement.height", [4] = "afkElement.x", [5] = "afkElement.y" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:crestRace"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [1] = "afkElement.anchor", [2] = "afkElement.width", [3] = "afkElement.height", [4] = "afkElement.x", [5] = "afkElement.y" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:date"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size", [4] = "afkElement.outlineStyle" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
      { [3] = "afkElement.format" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:guild"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size", [4] = "afkElement.outlineStyle" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:logoExpansion"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [1] = "afkElement.anchor", [2] = "afkElement.width", [3] = "afkElement.height", [4] = "afkElement.x", [5] = "afkElement.y" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:logoFaction"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [1] = "afkElement.anchor", [2] = "afkElement.width", [3] = "afkElement.height", [4] = "afkElement.x", [5] = "afkElement.y" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:playerClass"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size", [4] = "afkElement.outlineStyle" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:playerLevel"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size", [4] = "afkElement.outlineStyle" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:playerName"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size", [4] = "afkElement.outlineStyle" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:time"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size", [4] = "afkElement.outlineStyle" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:timer"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.outlineStyle", [4] = "afkElement.size" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
    }, labels = {
      ["afkElement.useSpecColor"] = { frFR = "Couleurs thématiques", enUS = "Themed colors" },
    } },
    ["SETTINGS_SEC_AFK_ELEMENT_DETAILS:tips"] = { cols = 5, rows = {
      { [1] = "__div:4" },
      { [2] = "afkElement.anchor", [3] = "afkElement.x", [4] = "afkElement.y" },
      { [2] = "afkElement.font", [3] = "afkElement.size" },
      { [2] = "afkElement.color", [3] = "afkElement.useSpecColor", [4] = "afkElement.specColorKey" },
      { [2] = "afkElement.lineWidth", [3] = "afkMode.tipThrottle" },
    } },
    ["SETTINGS_SEC_AFK_GRAPHICS"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_AFK_CREST_RACE", [2] = "check:$SETTINGS_AFK_LOGO_EXPANSION" },
      { [1] = "check:$SETTINGS_AFK_CREST_FACTION", [2] = "check:$SETTINGS_AFK_LOGO_AISHUI" },
      { [1] = "check:$SETTINGS_AFK_LOGO_FACTION" },
    } },
    ["SETTINGS_SEC_AFK_MISC"] = { cols = 5, rows = {
      { [1] = "afkMode.cameraSpin" },
      { [1] = "afkMode.exitOnKeypress" },
      { [1] = "__div:3" },
      { [1] = "afkMode.chatShow" },
      { [1] = "afkMode.chatFont", [2] = "afkMode.chatSize" },
      { [1] = "__div:2" },
      { [1] = "afkMode.accentColor", [2] = "afkMode.useThemeColors", [3] = "afkMode.themeColorKey" },
    }, labels = {
      ["afkMode.useThemeColors"] = { frFR = "Couleurs thématiques", enUS = "Themed colors" },
    } },
    ["SETTINGS_SEC_AFK_MODEL"] = { cols = 5, rows = {
      { [1] = "afkMode.modelEnabled" },
      { [1] = "afkMode.modelAnim", [2] = "afkMode.modelDistance", [3] = "afkMode.modelXOffset", [4] = "afkMode.modelYOffset", [5] = "afkMode.modelRotation" },
    } },
    ["SETTINGS_SEC_AFK_PANELS"] = { cols = 5, rows = {
      { [1] = "afkMode.panelTopHeight", [2] = "afkMode.panelBottomHeight", [3] = "afkMode.panelBgColor" },
      { [1] = "__div:1" },
      { [1] = "afkMode.animType", [2] = "afkMode.animTime", [3] = "afkMode.animBounce" },
    } },
    ["SETTINGS_SEC_AFK_TEXTS"] = { cols = 5, rows = {
      { [1] = "check:$SETTINGS_AFK_SHOW_NAME", [2] = "check:$SETTINGS_AFK_SHOW_TIME", [3] = "afkMode.timerCountdown" },
      { [1] = "check:$SETTINGS_AFK_SHOW_CLASS", [2] = "check:$SETTINGS_AFK_SHOW_DATE", [3] = "check:$SETTINGS_AFK_SHOW_TIMER" },
      { [1] = "check:$SETTINGS_AFK_SHOW_LEVEL", [2] = "check:$SETTINGS_AFK_SHOW_TIPS" },
      { [1] = "check:$SETTINGS_AFK_SHOW_GUILD" },
    } },
  },
  location = {
    ["SETTINGS_SEC_LOC_TEXT"] = { cols = 5, rows = {
      { [1] = "location.font", [2] = "location.fontSize", [3] = "location.textOutlineStyle", [4] = "location.width", [5] = "location.shadow" },
      { [1] = "location.textColor", [2] = "location.useZoneColor" },
      { [1] = "align:?" },
    } },
    ["SETTINGS_SEC_POSITION"] = { cols = 5, rows = {
      { [1] = "location.locked", [2] = "location.x", [3] = "location.y" },
    } },
    ["SETTINGS_SEC_VISIBILITY"] = { cols = 5, rows = {
      { [1] = "location.hideInCombat", [2] = "location.alpha" },
      { [1] = "location.mouseover", [2] = "location.hoverAlpha" },
      { [1] = "location.showZone" },
    } },
  },
  campfire = {
    __titles = {
      ["SETTINGS_CAMPFIRE_SEC_POPUP"] = { frFR = "GAIN DES BUFFS", enUS = "Buff Gain" },
    },
    ["SETTINGS_BUFFS"] = { cols = 5, rows = {
      { [1] = "campfire.tipFont", [2] = "campfire.tipFontSize", [3] = "campfire.tipOutline", [4] = "campfire.tipNameColor" },
      { [2] = "campfire.buffSize", [3] = "campfire.tipOffset", [4] = "campfire.tipStatColor" },
    } },
    ["SETTINGS_CAMPFIRE_SEC_BAR"] = { cols = 5, rows = {
      { [1] = "campfire.barSize", [2] = "campfire.barTexture", [3] = "campfire.barColor", [4] = "campfire.barAnim", [5] = "button:$SETTINGS_CAMPFIRE_RESET" },
      { [1] = "__div:1" },
      { [1] = "campfire.barSparkSize", [2] = "campfire.barSpark", [3] = "campfire.barSparkColor", [4] = "campfire.barSparkAnim" },
    } },
    ["SETTINGS_CAMPFIRE_SEC_ITEMS"] = { cols = 5, rows = {
      { [2] = "campfire.itemWidth", [3] = "campfire.itemHeight", [4] = "campfire.itemGap" },
      { [2] = "campfire.itemCountFont", [3] = "campfire.itemCountSize", [4] = "campfire.itemCountColor" },
      { [2] = "campfire.itemCountPoint", [3] = "campfire.itemCountX", [4] = "campfire.itemCountY" },
      { [2] = "campfire.itemBorder", [3] = "campfire.itemBorderColor", [4] = "campfire.itemCountOutline" },
    } },
    ["SETTINGS_CAMPFIRE_SEC_POPUP"] = { cols = 5, rows = {
      { [1] = "campfire.buffFont", [2] = "campfire.buffFontSize", [3] = "campfire.buffColor", [4] = "campfire.buffOutline" },
      { [1] = "campfire.sumX", [2] = "campfire.sumY" },
    } },
    ["SETTINGS_CAMPFIRE_SEC_TIMER"] = { cols = 5, rows = {
      { [1] = "campfire.timerFont", [2] = "campfire.timerSize", [3] = "campfire.timerColor", [4] = "campfire.timerOutline" },
      { [1] = "campfire.timerX", [2] = "campfire.timerY" },
    } },
  },
}

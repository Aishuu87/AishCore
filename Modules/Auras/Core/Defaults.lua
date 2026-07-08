-- AishUIAura/Core/Defaults.lua
-- SPEC_MAP + valeurs par défaut structurées par render
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.SPEC_MAP = {
    [102]={class="DRUID",spec="BALANCE"},[103]={class="DRUID",spec="FERAL"},
    [104]={class="DRUID",spec="GUARDIAN"},[105]={class="DRUID",spec="RESTO"},
    [71]={class="WARRIOR",spec="ARMS"},[72]={class="WARRIOR",spec="FURY"},
    [73]={class="WARRIOR",spec="PROTECTION"},
    [259]={class="ROGUE",spec="ASSASSINATION"},[260]={class="ROGUE",spec="OUTLAW"},
    [261]={class="ROGUE",spec="SUBTLETY"},
    [250]={class="DEATHKNIGHT",spec="BLOOD"},[251]={class="DEATHKNIGHT",spec="FROST"},
    [252]={class="DEATHKNIGHT",spec="UNHOLY"},
    [253]={class="HUNTER",spec="BEASTMASTERY"},[254]={class="HUNTER",spec="MARKSMANSHIP"},
    [255]={class="HUNTER",spec="SURVIVAL"},
    [62]={class="MAGE",spec="ARCANE"},[63]={class="MAGE",spec="FIRE"},
    [64]={class="MAGE",spec="FROST"},
    [65]={class="PALADIN",spec="HOLY"},[66]={class="PALADIN",spec="PROTECTION"},
    [70]={class="PALADIN",spec="RETRIBUTION"},
    [265]={class="WARLOCK",spec="AFFLICTION"},[266]={class="WARLOCK",spec="DEMONOLOGY"},
    [267]={class="WARLOCK",spec="DESTRUCTION"},
    [256]={class="PRIEST",spec="DISCIPLINE"},[257]={class="PRIEST",spec="HOLY"},
    [258]={class="PRIEST",spec="SHADOW"},
    [262]={class="SHAMAN",spec="ELEMENTAL"},[263]={class="SHAMAN",spec="ENHANCEMENT"},
    [264]={class="SHAMAN",spec="RESTORATION"},
    [268]={class="MONK",spec="BREWMASTER"},[269]={class="MONK",spec="WINDWALKER"},
    [270]={class="MONK",spec="MISTWEAVER"},
    [577]={class="DEMONHUNTER",spec="HAVOC"},[581]={class="DEMONHUNTER",spec="VENGEANCE"},
    [1480]={class="DEMONHUNTER",spec="DEVOURER"},
    [1467]={class="EVOKER",spec="DEVASTATION"},[1468]={class="EVOKER",spec="PRESERVATION"},
    [1473]={class="EVOKER",spec="AUGMENTATION"},
}

ns.Defaults = {
    addonVersion = "0.0.0", enabled = true, useSpellColors = true,
    hideCDMBuffFrames = true, useNativeCDM = false,
    iconlistEnabled = true, circlebarsEnabled = true, iconsEnabled = true,
    freebarsEnabled = true,
    equipmentEnabled = true, effectsEnabled = false,
    -- Auto-désactivation des effets 3D en raid (goulot GPU potentiel).
    -- Si true : dès l'entrée en raid, les modèles 3D sont masqués. Sortir du raid
    -- les réactive automatiquement. Laisse l'utilisateur contrôler.
    effects3DAutoDisableInRaid = false,

    iconlist = {
        layout="center_mirror", x=0, y=-290, growth="DOWN", maxBars=8,
        barW=80, barH=2, iconW=25, iconH=25, gap=12, pairGap=6, rowGap=3,
        texture="aish_grad3", alpha=1.0, iconAlpha=1.0, barAlpha=1.0, barAlphaWith3D=1.0, gradientEnabled=false, gradientR2=nil, gradientG2=nil, gradientB2=nil,
        barBgR=0, barBgG=0, barBgB=0, barBgAlpha=0,
        fadeIC=1.0, fadeOOC=0.4, fadeDelayIC=0, fadeDelayOOC=0, fadeDuration=0.35,
        iconBorder="square", desatOverride=nil, glowEnabled=true,
        glowOverrideIdx=nil, glowOverrideR=nil, glowOverrideG=nil, glowOverrideB=nil, glowOverrideScale=nil, glowOverrideAlpha=nil,
        swipeEnabled=false,
        sparkEnabled=true, sparkW=17, sparkH=6, sparkAlpha=1.0, sparkOffY=0, sparkGradient=false, sparkGradR2=nil, sparkGradG2=nil, sparkGradB2=nil, sparkTexture="atlas:honorsystem-bar-spark", sparkLayer="front",
        sparkColorR=nil, sparkColorG=nil, sparkColorB=nil,
        timerIconEnabled=false, timerFont="Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat.ttf",
        timerSize=12,
        timerColorR=1, timerColorG=1, timerColorB=1,
        timerIconOffX=0, timerIconOffY=0,
        stackEnabled=true, stackFont=nil, stackPos="BOTTOMRIGHT", stackOffX=0, stackOffY=0, stackSize=10, stackColorR=1, stackColorG=1, stackColorB=1,
        chargesEnabled=true, chargesFont=nil, chargesPos="TOPLEFT", chargesOffX=0, chargesOffY=0, chargesSize=10, chargesColorR=0.4, chargesColorG=0.7, chargesColorB=1.0,
        -- Couleurs d'urgence : curve native Blizzard qui teinte la bar selon le % restant
        urgencyEnabled=true,
        urgencyMediumR=1.0, urgencyMediumG=0.5, urgencyMediumB=0.0,    -- 20% restant = orange
        urgencyCriticalR=1.0, urgencyCriticalG=0.15, urgencyCriticalB=0.05, -- 0% restant = rouge
        -- ANIMATION D'APPARITION : reproduit la WA d'origine (Tiger Fury / RtB / Totems)
        --   - scale horizontal 0→barW + alpha 0→1 sur 1s avec easeOutIn strength 5
        -- ON par defaut (comme dans la WA originale).
        popEnabled=true, popDuration=1.0, popEaseStrength=5, popAlphaFade=true,
        iconAnimStyle="standard", iconAnimDuration=0.4, iconAnimOut=true,
    },
    circlebars = {
        layout="side_large", x=-502, y=0, growth="DOWN", maxBars=8,
        barW=147, barH=4, iconW=28, iconH=19, gap=3, rowGap=1,
        texture="aish_grad3", alpha=1.0, iconAlpha=1.0, barAlpha=1.0, barAlphaWith3D=1.0, gradientEnabled=false, gradientR2=nil, gradientG2=nil, gradientB2=nil,
        fadeIC=1.0, fadeOOC=0.4, fadeDelayIC=0, fadeDelayOOC=0, fadeDuration=0.35,
        iconBorder="square", desatOverride=nil, glowEnabled=true,
        glowOverrideIdx=nil, glowOverrideR=nil, glowOverrideG=nil, glowOverrideB=nil, glowOverrideScale=nil,
        iconPos="RIGHT", reverse=true,
        barBgR=0, barBgG=0, barBgB=0, barBgAlpha=0,
        barColorR=nil, barColorG=nil, barColorB=nil,
        swipeEnabled=false, bannerGrowth="RIGHT",
        sparkEnabled=true, sparkW=17, sparkH=6, sparkAlpha=1.0, sparkOffY=0, sparkGradient=false, sparkGradR2=nil, sparkGradG2=nil, sparkGradB2=nil, sparkTexture="atlas:honorsystem-bar-spark", sparkLayer="front",
        sparkColorR=nil, sparkColorG=nil, sparkColorB=nil,
        timerIconEnabled=false, timerFont="Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat.ttf",
        timerSize=11,
        timerColorR=1, timerColorG=1, timerColorB=1,
        timerIconOffX=0, timerIconOffY=0,
        stackEnabled=true, stackPos="BOTTOMRIGHT", stackOffX=0, stackOffY=0, stackSize=10, stackColorR=1, stackColorG=1, stackColorB=1,
        chargesEnabled=true, chargesFont=nil, chargesPos="TOPLEFT", chargesOffX=0, chargesOffY=0, chargesSize=10, chargesColorR=0.4, chargesColorG=0.7, chargesColorB=1.0,
        -- Couleurs d'urgence : curve native Blizzard qui teinte la bar selon le % restant
        urgencyEnabled=true,
        urgencyMediumR=1.0, urgencyMediumG=0.5, urgencyMediumB=0.0,
        urgencyCriticalR=1.0, urgencyCriticalG=0.15, urgencyCriticalB=0.05,
        -- ANIMATION D'APPARITION : reproduit la WA d'origine (Fiend & Rifts / Totems)
        --   - scale horizontal 0→barW + alpha 0→1 sur 1s avec easeOutIn strength 5
        -- ON par defaut. Pour la disposition Vanguard (icone+barre simple), le sens
        -- de deploiement suit la position de l'icone (cf. CreateVanguardRow).
        popEnabled=true, popDuration=1.0, popEaseStrength=5, popAlphaFade=true,
        iconAnimStyle="standard", iconAnimDuration=0.4, iconAnimOut=true,
    },
    icons = {
        layout="portrait_small", x=-199, y=-247, growth="LEFT", maxBars=4,
        barW=26, barH=3, iconW=26, iconH=26, gap=4, rowGap=2,
        texture="aish_grad3", alpha=1.0, iconAlpha=1.0, barAlpha=1.0, barAlphaWith3D=1.0, gradientEnabled=false, gradientR2=nil, gradientG2=nil, gradientB2=nil,
        fadeIC=1.0, fadeOOC=0.3, fadeDelayIC=0, fadeDelayOOC=0, fadeDuration=0.35,
        iconBorder="square", desatOverride=nil, glowEnabled=true, glowOverrideIdx=nil, glowOverrideR=nil, glowOverrideG=nil, glowOverrideB=nil, glowOverrideScale=nil,
        showBarUnderIcon=true, barUnderHeight=3, barPosition="BOTTOM", barReverseFill=false, swipeEnabled=false, barBgR=0, barBgG=0, barBgB=0, barBgAlpha=0,
        sparkEnabled=true, sparkW=12, sparkH=5, sparkAlpha=1.0, sparkOffY=0, sparkGradient=false, sparkGradR2=nil, sparkGradG2=nil, sparkGradB2=nil, sparkTexture="atlas:honorsystem-bar-spark", sparkLayer="front",
        sparkColorR=nil, sparkColorG=nil, sparkColorB=nil,
        timerIconEnabled=false, timerFont="Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat.ttf",
        timerSize=10,
        timerColorR=1, timerColorG=1, timerColorB=1,
        timerIconOffX=0, timerIconOffY=0,
        stackEnabled=true, stackPos="BOTTOMRIGHT", stackOffX=0, stackOffY=0, stackSize=10, stackColorR=1, stackColorG=1, stackColorB=1,
        chargesEnabled=true, chargesFont=nil, chargesPos="TOPLEFT", chargesOffX=0, chargesOffY=0, chargesSize=10, chargesColorR=0.4, chargesColorG=0.7, chargesColorB=1.0,
        -- Couleurs d'urgence : curve native Blizzard qui teinte la bar selon le % restant
        urgencyEnabled=true,
        urgencyMediumR=1.0, urgencyMediumG=0.5, urgencyMediumB=0.0,
        urgencyCriticalR=1.0, urgencyCriticalG=0.15, urgencyCriticalB=0.05,
    },
    freebars = {
        -- Layout "Buff autour du cercle" : 2 barres miroir sans icone,
        -- positionnees a l'emplacement standard du Resource Circle d'Aishaddon.
        -- L'utilisateur peut deplacer via Alt+clic gauche sur les barres.
        --
        -- NOTE : ce render n'a ni icone, ni glow, ni stacks, ni charges.
        -- Les champs correspondants (iconW/H, glow*, stack*, charges*, etc.)
        -- ne figurent PAS dans cette table. S'ils sont reintroduits plus tard, ajouter
        -- aussi les sections correspondantes dans UI/Menus/Render.lua (cf. SECTIONS_BY_RENDER).
        layout="resource_circle", x=0, y=-218, maxBars=8,
        -- Duree (texte centre sur la row, dans l'espace entre les 2 barres miroir).
        -- Reutilise les memes cles que timerIcon (iconlist/circlebars/icons) pour
        -- beneficier du meme code de rendu (UpdateTimersForRender / UpdRow).
        timerIconEnabled=false, timerFont="Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat.ttf",
        timerSize=11, timerColorR=1, timerColorG=1, timerColorB=1,
        timerIconOffX=0, timerIconOffY=0, timerDecimals=1,
        -- Note : pas de champ 'growth' (placement auto-alterne haut/bas geré par Buffs.lua)
        -- combatOnly : les barres sont cachees hors combat (UpdateRenderFade target=0).
        combatOnly=true,
        -- v281 : barH passe de 2 a 3 (un poil plus epais, plus lisible).
        -- gap passe de 44 a 50 (espacement par defaut plus aere).
        -- Ajustables via les sliders du menu Buffs.
        barW=45, barH=3, gap=50, rowGap=6,
        -- Barre (couleur & texture)
        texture="aish_grad3", alpha=1.0, barAlpha=1.0, barAlphaWith3D=1.0,
        gradientEnabled=false, gradientR2=nil, gradientG2=nil, gradientB2=nil,
        barBgR=0, barBgG=0, barBgB=0, barBgAlpha=0,
        -- Opacite & fade
        fadeIC=1.0, fadeOOC=0.4, fadeDelayIC=0, fadeDelayOOC=0, fadeDuration=0.35,
        -- Etincelle (spark) : 17x6 = valeur majoritaire des WA originales
        sparkEnabled=true, sparkW=17, sparkH=6, sparkAlpha=1.0, sparkOffY=0,
        sparkGradient=false, sparkGradR2=nil, sparkGradG2=nil, sparkGradB2=nil,
        sparkTexture="atlas:honorsystem-bar-spark", sparkLayer="front",
        sparkColorR=nil, sparkColorG=nil, sparkColorB=nil,
        -- Couleurs d'urgence (curve native Blizzard, teinte la barre selon le % restant)
        urgencyEnabled=true,
        urgencyMediumR=1.0, urgencyMediumG=0.5, urgencyMediumB=0.0,
        urgencyCriticalR=1.0, urgencyCriticalG=0.15, urgencyCriticalB=0.05,
        -- DEGRADE PAR SORT (specifique a Buffs) : table indexee par spellID,
        -- chaque entree = {r1, g1, b1, r2, g2, b2} avec couleur debut + couleur fin.
        -- Si un sort a une entree, son gradient custom override tout (couleur render,
        -- gradient render, couleur globale). Si aucune entree pour le sort,
        -- comportement standard (cf. ApplyBarColor priorite 2/3).
        spellGradients = {},
        -- ANIMATION D'APPARITION (specifique a Buffs) : effet "pop" quand un buff
        -- apparait. Reproduit l'animation de la WA Tiger Fury d'origine :
        --   - scale horizontal : largeur 0 → barW depuis le centre vers l'exterieur
        --   - alpha fade-in : 0 → 1 en parallele du scale
        --   - easing easeOutIn : lent debut, vif milieu, lent fin
        popEnabled=true,           -- on/off de l'animation
        popDuration=1.0,           -- duree en secondes (slider 0.1-2.5, pas 0.05)
        popEaseStrength=5,         -- intensite easeOutIn (slider 1-12, pas 1)
        popAlphaFade=true,         -- fade-in alpha en parallele (sinon scale seul)
    },
    equipment = {
        layout="grid_fixed", combatOnly=true,
        groupX=-200, groupY=-184, groupGrowth="RIGHT", groupGap=4,
        groupW=31, groupH=24, groupAlpha=1.0,
        borderStyle="square", borderWidth=1,
        borderColor={0.055, 0.055, 0.055, 1},
    },
}

ns.SlotDefaults = {
    enabled=false, x=0, y=-184, w=31, h=24,
    alpha=1.0, bgAlpha=0.85, combatOnly=nil,
    glowEnabled=true, glowIdx=2, glowAlpha=0.7, glowColor=nil,
    desat=false, glowScale=1.0,
}

ns.SpellDefaults = {
    enabled=false, priority=99,
    destinations = { iconlist=false, circlebars=false, icons=false, freebars=false },
    color=nil, glowColor=nil, glow=false, glowIdx=2, glowAlpha=0.7,
    desat=false, procGlowIdx=1, procGlowScale=1.0,
    -- 3D models (0 = off)
    barModelID=0, barModelA=0.5, barModelRot=0,
    barModelX=0, barModelY=0, barModelZ=0, barModelS=1.0,
    barModelMode="front", barModelL="back",
    -- 2D Fill (mode "Remplissage" pattern texturePath vide = off)
    barFillTex="", barFillAlpha=0.7,
    barFillTintR=1, barFillTintG=1, barFillTintB=1,
    barFillScroll=0, barFillLayer="front",
    iconModelID=0, iconModelA=0.5, iconModelRot=0,
    iconModelX=0, iconModelY=0, iconModelZ=0, iconModelS=1.0, iconModelL="back",
    sparkModelID=0, sparkModelA=0.7, sparkModelRot=0,
    sparkModelX=0, sparkModelY=0, sparkModelZ=0, sparkModelS=0.5, sparkModelL="front",
}

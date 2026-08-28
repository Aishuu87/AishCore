-- AishUIAura/Core/Config.lua
-- SOURCE UNIQUE pour TOUS les noms, thème, listes, constantes
-- Police système = WoW NATIF. SharedMedia = dropdown uniquement.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.ADDON_VERSION = "0.0.0"

-- Partage des utilitaires du namespace parent (définis dans Core.lua d'Aishaddon)
ns.DeepCopy     = ns.DeepCopy     or _addon.DeepCopy
ns.MergeDefaults = ns.MergeDefaults or _addon.MergeDefaults
ns.FONT_LIST    = ns.FONT_LIST    or _addon.FONT_LIST
ns.GetFontList  = ns.GetFontList  or _addon.GetFontList

------------------------------------------------------------------------
-- SAFE FONT  (essaie le path, fallback FRIZQT si échec)
------------------------------------------------------------------------
local SAFE_FONT = "Fonts\\FRIZQT__.TTF"

-- Wrapper sécurisé pour SetFont (JAMAIS de crash)
function ns.ApplyFont(fontString, path, size, flags)
    path = path or SAFE_FONT
    size = size or 11
    local ok = pcall(function()
        fontString:SetFont(path, size, flags or "")
    end)
    if not ok then
        fontString:SetFont(SAFE_FONT, size, flags or "")
    end
end

------------------------------------------------------------------------
-- MEDIA PATHS  (WoW natif UNIQUEMENT — jamais SharedMedia en dur)
------------------------------------------------------------------------
ns.Media = {
    font      = SAFE_FONT,  -- Friz Quadrata
    sparkTex  = "Interface\\CastingBar\\UI-CastingBar-Spark",
    fallbackBar = "Interface\\TargetingFrame\\UI-StatusBar",
}

------------------------------------------------------------------------
-- LAYOUT NAMES
------------------------------------------------------------------------

-- Noms des dispositions en français (labels UI).
-- Les clés internes (center_mirror, side_large, etc.) restent en anglais-descriptif
-- pour la compatibilité Lua et la lisibilité du code.
ns.LAYOUT_NAMES = {
    CENTER_MIRROR        = "Icône centrée",
    RESOURCE_CIRCLE = "Buff autour du cercle",
    CENTER_DUAL    = "Double icône",
    SIDE_LARGE     = "Grande barre",
    SIDE_COMPACT   = "Barre compacte",
    SIDE_BANNER    = "Bannière latérale",
    PORTRAIT_SMALL = "Bannière",
    GRID_FIXED     = "Grille fixe",
    GRID_FREE      = "Grille libre",
}

ns.LAYOUT_ICONS = {
    CENTER_MIRROR        = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_aegis",
    RESOURCE_CIRCLE = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_resourcecircle",
    CENTER_DUAL    = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_berserk",
    SIDE_LARGE     = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_vanguard",
    SIDE_COMPACT   = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_sparte",
    SIDE_BANNER    = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_banner",
    PORTRAIT_SMALL = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_fury",
    GRID_FIXED     = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_shieldwall",
    GRID_FREE      = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_ronin",
}

-- Versions INACTIVE (grisées N&B) — utilisées quand la disposition n'est pas active
ns.LAYOUT_ICONS_INACTIVE = {
    CENTER_MIRROR        = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_aegis_inactive",
    RESOURCE_CIRCLE = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_resourcecircle_inactive",
    CENTER_DUAL    = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_berserk_inactive",
    SIDE_LARGE     = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_vanguard_inactive",
    SIDE_COMPACT   = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_sparte_inactive",
    SIDE_BANNER    = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_banner_inactive",
    PORTRAIT_SMALL = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_fury_inactive",
    GRID_FIXED     = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_shieldwall_inactive",
    GRID_FREE      = "Interface\\AddOns\\Aishaddon\\Media\\textures\\layout_ronin_inactive",
}

ns.LAYOUT_ICON_FALLBACKS = {
    CENTER_MIRROR        = "ability_paladin_shieldofvengeance",
    RESOURCE_CIRCLE = "ability_paladin_shieldofvengeance",
    CENTER_DUAL    = "ability_druid_berserk",
    SIDE_LARGE     = "ability_warrior_charge",
    SIDE_COMPACT   = "ability_warrior_shieldwall",
    SIDE_BANNER    = "ability_warrior_rallyingcry",
    PORTRAIT_SMALL = "ability_druid_tigersroar",
    GRID_FIXED     = "inv_shield_06",
    GRID_FREE      = "ability_rogue_sprint",
}

------------------------------------------------------------------------
-- DESTINATION BADGES  [L][C][I][B]
-- L = Liste d'icônes | C = Barres de cercle | I = Icones | B = Barres libres
------------------------------------------------------------------------
ns.DEST_BADGES = {
    L = { key = "iconlist",   label = "L" },
    C = { key = "freebars",   label = "C" },
    I = { key = "icons",      label = "I" },
    B = { key = "circlebars", label = "B" },
}

------------------------------------------------------------------------
-- THEME — AISHUI BLACK & GOLD
-- Pure dark surfaces, clean off-white text. Class color reserved for
-- active states only. Gold tone reserved for ornamental dots/spines.
------------------------------------------------------------------------
ns.THEME = {
    -- Surfaces (noir quasi pur avec une légère teinte chaude)
    bg            = { 0.030, 0.030, 0.035, 0.97 },
    cardBg        = { 0.060, 0.060, 0.065, 1.00 },

    -- Borders & dividers (very dark grey, almost invisible)
    border        = { 0.180, 0.180, 0.195, 0.65 },
    separator     = { 0.260, 0.260, 0.280, 0.40 },

    -- Text (clean off-white hierarchy)
    textNormal    = { 0.92, 0.92, 0.93 },
    textBright    = { 0.98, 0.96, 0.90 },
    textHighlight = { 1.00, 1.00, 1.00 },
    textDisabled  = { 0.40, 0.40, 0.42 },
    textDim       = { 0.58, 0.58, 0.62 },

    -- Accent (overwritten by ClassColors.lua avec ns.THEME.gold)
    accent        = { 0.92, 0.92, 0.93 },     -- placeholder

    -- AISHUI signature gold (used on ornaments — dots, spines, hairlines)
    gold          = { 0.78, 0.62, 0.30 },

    -- Form controls
    checkboxOn    = { 0.92, 0.92, 0.93 },     -- gets class color
    checkboxOff   = { 0.180, 0.180, 0.195 },
    sliderTrack   = { 0.180, 0.180, 0.195 },
    rowHover      = { 1, 1, 1, 0.04 },
}

------------------------------------------------------------------------
-- GLOW DEFINITIONS  (1 Aucun + 67 boucle + 34 proc = 102 total)
------------------------------------------------------------------------
ns.GLOW_DEFS = {
    { name = "Aucun" },
    -- BOUCLE (2-36)
    { name = "Pulse", useAlphaPulse = true, texture = "Interface\\SpellActivationOverlay\\IconAlert",
      texCoord = {0.00781250,0.50781250,0.27734375,0.52734375}, blendMode = "ADD",
      fromAlpha = 0.3, toAlpha = 0.7, duration = 0.8 },
    { name = "Modern Glow",       atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook" },
    { name = "Assist Blue",       atlas = "RotationHelper-ProcLoopBlue-Flipbook" },
    { name = "Assist Ants",       atlas = "RotationHelper_Ants_Flipbook" },
    { name = "Assist White",      texture = "Interface/AddOns/Aishaddon/Media/Glows/flipbook2.tga" },
    { name = "Assist Rainbow",    texture = "Interface/AddOns/Aishaddon/Media/Glows/ABE_flipbook_rainbow.png",
      rows=6, columns=10, frames=60, duration=0.9, frameW=80, frameH=80, scale=1.05 },
    { name = "Classic Glow",      texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows=5, columns=5, frames=25, duration=0.3, frameW=48, frameH=48, scale=0.85 },
    { name = "ABE Classic-like",  texture = "Interface/AddOns/Aishaddon/Media/Glows/AB_ClassicLike_Glow.tga",
      rows=6, columns=5, frames=30, duration=0.5, frameW=100, frameH=100, scale=1 },
    { name = "GCD",               atlas = "UI-CooldownManager-Alert-Flipbook",
      rows=11, columns=2, frames=22, duration=1.0, scale=0.7 },
    { name = "Essence",           atlas = "UF-Essence-Flipbook-FX-Circ",
      rows=3, columns=10, frames=30, duration=1.0, scale=1.2 },
    { name = "Frost",             atlas = "perks-frost-FX",
      rows=3, columns=5, frames=15, duration=0.7, scale=0.9 },
    { name = "Star Burst",        atlas = "UI-HUD-ActionBar-GCD-Flipbook",
      rows=6, columns=5, frames=27, duration=0.7, scale=0.9 },
    { name = "Empowered Green",   atlas = "UI-HUD-ActionBar-Empowered-Loop-Green",
      rows=6, columns=5, frames=30, duration=1.2, scale=1.0 },
    { name = "Empowered Gold",    atlas = "UI-HUD-ActionBar-Empowered-Loop-Gold",
      rows=6, columns=5, frames=30, duration=1.2, scale=1.0 },
    { name = "Proc Gold",         atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",
      rows=6, columns=5, frames=30, duration=1.0, scale=1.0 },
    { name = "Rage Glow",         atlas = "UI-HUD-ActionBar-Rage-Glow-Flipbook",
      rows=6, columns=5, frames=30, duration=1.0, scale=1.1 },
    { name = "Shadow Pulse",      useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.2, toAlpha=0.6, duration=1.2 },
    { name = "Nature Pulse",      useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.25, toAlpha=0.65, duration=1.0 },
    { name = "Arcane Shimmer",    useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.15, toAlpha=0.55, duration=0.6 },
    { name = "Fire Flicker",      useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.35, toAlpha=0.8, duration=0.4 },
    { name = "Frost Slow",        useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.2, toAlpha=0.5, duration=1.6 },
    { name = "Blood Pulse",       useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.3, toAlpha=0.75, duration=0.9 },
    { name = "Void Breath",       useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.1, toAlpha=0.4, duration=2.0 },
    { name = "Lightning Fast",    useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.4, toAlpha=0.9, duration=0.3 },
    { name = "Dragon Breath",     useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.3, toAlpha=0.85, duration=0.5 },
    { name = "Cosmic Glow",       useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.15, toAlpha=0.6, duration=1.8 },
    { name = "Subtle Glow",       useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.05, toAlpha=0.25, duration=1.5 },
    { name = "Strong Pulse",      useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.5, toAlpha=1.0, duration=0.6 },
    { name = "Alert Flash",       useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=1.0, duration=0.2 },
    { name = "Zen Glow",          useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.15, toAlpha=0.45, duration=3.0 },
    { name = "Feral Rage",        useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.35, toAlpha=0.9, duration=0.35 },
    { name = "Warden Shield",     useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.2, toAlpha=0.55, duration=1.3 },
    { name = "Twilight Fade",     useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.1, toAlpha=0.5, duration=1.1 },
    { name = "Berserker Fury",    useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.4, toAlpha=0.95, duration=0.25 },
    { name = "Gentle Wave",       useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.1, toAlpha=0.35, duration=2.5 },
    { name = "Empowered Pulse",   useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.2, toAlpha=0.7, duration=0.7 },
    { name = "Holy Glow",         useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.2, toAlpha=0.65, duration=1.4 },
    -- Atlas Blizzard (UF-RogueCP, UF-DruidCP, etc.)
    { name = "Rogue CP Blue",     atlas="UF-RogueCP-Slash-Blue", rows=3, columns=6, frames=18, duration=0.7, scale=1.3 },
    { name = "Rogue CP Red",      atlas="UF-RogueCP-Slash-Red", rows=3, columns=6, frames=18, duration=0.7, scale=1.3 },
    { name = "Druid CP Red",      atlas="UF-DruidCP-Slash", rows=3, columns=8, frames=24, duration=0.7, scale=1.3 },
    { name = "Chi Wind",          atlas="UF-Chi-WindFX", rows=3, columns=6, frames=18, duration=0.7, scale=1.3 },
    { name = "Vigor",             atlas="dragonriding_sgvigor_burst_flipbook", rows=4, columns=4, frames=16, duration=1.0, scale=1.2 },
    { name = "Vigor 2",           atlas="dragonriding_sgvigor_decor_flipbook_left", rows=2, columns=4, frames=8, duration=0.7, scale=0.8 },
    { name = "FX Eye",            atlas="groupfinder-eye-flipbook-foundfx", rows=5, columns=15, frames=75, duration=1.0, scale=1.0 },
    { name = "Arrow",             atlas="Ping_Marker_FlipBook_OnMyWay", rows=4, columns=6, frames=24, duration=1.0, scale=0.7 },
    { name = "Soul",              atlas="UF-SoulShards-Flipbook-Soul", rows=3, columns=7, frames=21, duration=1.2, scale=0.9 },
    -- Textures ABE copiees localement dans Media/Glows/ (portage figé,
    -- ne dependent plus de l'addon externe ActionBarsEnhanced installe)
    { name = "ABE Assist White",  texture="Interface/AddOns/Aishaddon/Media/Glows/flipbook2.tga" },
    { name = "ABE Rainbow",       texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_flipbook_rainbow.png",
      rows=6, columns=10, frames=60, duration=0.9, frameW=80, frameH=80, scale=1.05 },
    { name = "ABE Classic-like",  texture="Interface/AddOns/Aishaddon/Media/Glows/AB_ClassicLike_Glow.tga",
      rows=6, columns=5, frames=30, duration=0.5, frameW=100, frameH=100, scale=1 },
    { name = "ABE Star 1",        texture="Interface/AddOns/Aishaddon/Media/Glows/stars_new2.tga",
      rows=6, columns=5, frames=30, duration=0.5, frameW=100, frameH=100, scale=0.9 },
    { name = "ABE Star 2",        texture="Interface/AddOns/Aishaddon/Media/Glows/stars_new.tga",
      rows=6, columns=5, frames=30, duration=0.5, frameW=100, frameH=100, scale=0.9 },
    { name = "ABE Star Rainbow",  texture="Interface/AddOns/Aishaddon/Media/Glows/stars_rainbow_new.tga",
      rows=6, columns=5, frames=30, duration=0.5, frameW=100, frameH=100, scale=0.9 },
    { name = "ABE Lines",         texture="Interface/AddOns/Aishaddon/Media/Glows/AB_Lines.tga",
      rows=6, columns=4, frames=24, duration=1.0, frameW=50, frameH=50, scale=0.85 },
    { name = "ABE Lines Pixel",   texture="Interface/AddOns/Aishaddon/Media/Glows/AB_Lines_Pixel.tga",
      rows=6, columns=2, frames=12, duration=0.35, frameW=50, frameH=50, scale=0.85 },
    { name = "ABE Leaves",        texture="Interface/AddOns/Aishaddon/Media/Glows/AB_Leaves.tga",
      rows=6, columns=5, frames=30, duration=1.0, frameW=50, frameH=50, scale=0.85 },
    { name = "ABE Void",          texture="Interface/AddOns/Aishaddon/Media/Glows/AB_Void.tga",
      rows=6, columns=5, frames=30, duration=1.0, frameW=50, frameH=50, scale=0.85 },
    { name = "ABE Garg",          texture="Interface/AddOns/Aishaddon/Media/Glows/AB_Garg.tga",
      rows=6, columns=5, frames=30, duration=1.0, frameW=100, frameH=100, scale=0.85 },
    { name = "ABE Energy",        texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_Energy.tga",
      rows=6, columns=5, frames=30, duration=0.5, frameW=72, frameH=72, scale=0.85 },
    { name = "ABE Fire",          texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_Fire.tga",
      rows=6, columns=5, frames=30, duration=1.0, frameW=72, frameH=72, scale=0.9 },
    { name = "ABE Fire2",         texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_Fire2.tga",
      rows=6, columns=5, frames=30, duration=1.0, frameW=80, frameH=80, scale=0.9 },
    { name = "ABE Antorus",       texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_Antorus.tga",
      rows=6, columns=5, frames=30, duration=0.9, frameW=100, frameH=100, scale=0.85 },
    { name = "ABE Lightning",     texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_Lightning.tga",
      rows=6, columns=5, frames=30, duration=1.2, frameW=100, frameH=100, scale=0.85 },
    { name = "ABE Zereth Square", texture="Interface/AddOns/Aishaddon/Media/Glows/proc_4.tga",
      rows=6, columns=5, frames=30, duration=1.2, frameW=100, frameH=100, scale=1.01 },
    { name = "ABE Pulse",         texture="Interface/AddOns/Aishaddon/Media/Glows/pulse_01.tga",
      rows=6, columns=5, frames=30, duration=1.0, frameW=100, frameH=100, scale=0.95 },
    { name = "ABE Square Pixel",  texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_Square_PixelLike.png",
      rows=6, columns=5, frames=30, duration=0.35, frameW=100, frameH=100, scale=0.82 },
    { name = "ABE Arc Raiders",   texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_ArcRaiders.png",
      rows=10, columns=6, frames=60, duration=1, frameW=100, frameH=100, scale=1 },
    { name = "GCD 2",             texture="Interface/AddOns/Aishaddon/Media/Glows/GCD_2.tga",
      rows=6, columns=2, frames=12, duration=0.5, frameW=47, frameH=47, scale=0.7 },
    -- PROC START (entry animations)
    { name = "Proc: Blizzard",    isProcStart=true, atlas="UI-HUD-ActionBar-Proc-Start-Flipbook" },
    { name = "Proc: Blue",        isProcStart=true, atlas="RotationHelper-ProcStartBlue-Flipbook-2x" },
    { name = "Proc: Short",       isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ProcStartYellow.tga",
      rows=3, columns=6, frames=18, duration=0.5, scale=1.0 },
    { name = "Proc: Shorter",     isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ProcStartYellow_Shorter.tga",
      rows=2, columns=5, frames=10, duration=0.35, scale=1.0 },
    { name = "Proc: Blue Short",  isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ProcStartBlue.tga",
      rows=3, columns=6, frames=18, duration=0.5, scale=1.0 },
    { name = "Proc: Blue Shorter",isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ProcStartBlue_Shorter.tga",
      rows=2, columns=5, frames=10, duration=0.35, scale=1.0 },
    { name = "Proc: White Short", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ProcStartWhite.tga",
      rows=3, columns=6, frames=18, duration=0.5, scale=1.0 },
    { name = "Proc: White Shorter",isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ProcStartWhite_Shorter.tga",
      rows=2, columns=5, frames=10, duration=0.35, scale=1.0 },
    { name = "Proc: Rainbow",     isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_ProcRainbow_Short.png",
      rows=3, columns=6, frames=18, duration=0.5, scale=1.0 },
    { name = "Proc: Rainbow Shorter", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ABE_ProcRainbow_Shorter.png",
      rows=2, columns=5, frames=10, duration=0.35, scale=1.0 },
    { name = "Proc: Classic-like", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/ClassicLike_Flipbook.tga",
      rows=4, columns=3, frames=12, duration=0.25, frameW=80, frameH=80, scale=0.9 },
    { name = "Proc: ABE Burst Square", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/burst_square.tga",
      rows=6, columns=5, frames=30, duration=0.33, frameW=100, frameH=100, scale=0.38 },
    { name = "Proc: ABE Burst Rune", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/burst_2.tga",
      rows=6, columns=5, frames=30, duration=0.33, frameW=100, frameH=100, scale=0.38 },
    { name = "Proc: ABE Burst Rune 2", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/burst_3.tga",
      rows=6, columns=5, frames=30, duration=0.33, frameW=100, frameH=100, scale=0.38 },
    { name = "Proc: ABE Burst Zereth", isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/burst_4.tga",
      rows=6, columns=5, frames=30, duration=0.33, frameW=100, frameH=100, scale=0.42 },
    { name = "Proc: ABE Ring",     isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/burst_5.tga",
      rows=6, columns=5, frames=30, duration=0.7, frameW=100, frameH=100, scale=0.38 },
    { name = "Proc: ABE Ring 2",   isProcStart=true, texture="Interface/AddOns/Aishaddon/Media/Glows/burst_6.tga",
      rows=6, columns=5, frames=30, duration=0.4, frameW=100, frameH=100, scale=0.38 },
    { name = "Proc: Flash In",    isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=1.0, duration=0.15 },
    { name = "Proc: Grow In",     isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.8, duration=0.2 },
    { name = "Proc: Burst",       isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=1.0, duration=0.1 },
    { name = "Proc: Spiral In",   isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.9, duration=0.3 },
    { name = "Proc: Slam",        isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=1.0, duration=0.08 },
    { name = "Proc: Fade Up",     isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.7, duration=0.25 },
    { name = "Proc: Pulse Once",  isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.6, duration=0.4 },
    { name = "Proc: Electric",    isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=1.0, duration=0.12 },
    { name = "Proc: Divine",      isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.85, duration=0.35 },
    { name = "Proc: Shadow Rise", isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.7, duration=0.5 },
    { name = "Proc: Nature Bloom",isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.75, duration=0.45 },
    { name = "Proc: Ice Snap",    isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.9, duration=0.07 },
    { name = "Proc: Blood Surge", isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=1.0, duration=0.18 },
    { name = "Proc: Arcane Pop",  isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.8, duration=0.22 },
    { name = "Proc: Void Emerge", isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.65, duration=0.6 },
    { name = "Proc: Dragonfire",  isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.95, duration=0.15 },
    { name = "Proc: Starfall",    isProcStart=true, useAlphaPulse=true, texture="Interface\\SpellActivationOverlay\\IconAlert",
      texCoord={0.00781250,0.50781250,0.27734375,0.52734375}, blendMode="ADD", fromAlpha=0.0, toAlpha=0.85, duration=0.28 },
}

------------------------------------------------------------------------
-- BAR TEXTURES  (~45)
------------------------------------------------------------------------
ns.BAR_TEXTURES = {
    { value = "aish_grad",   text = "Aish Gradient",     path = "Interface\\AddOns\\Aishaddon\\Media\\Statusbars\\aish_gradient" },
    { value = "aish_grad2",  text = "Aish Gradient 2",   path = "Interface\\AddOns\\Aishaddon\\Media\\Statusbars\\aish_gradient2" },
    { value = "aish_grad3",  text = "Aish Gradient 3",   path = "Interface\\AddOns\\Aishaddon\\Media\\Statusbars\\aish_gradient3" },
    { value = "aish_fx",     text = "Aish Effect",       path = "Interface\\AddOns\\Aishaddon\\Media\\Statusbars\\aish_effect" },
    { value = "aish_fx2",    text = "Aish Effect 2",     path = "Interface\\AddOns\\Aishaddon\\Media\\Statusbars\\aish_effect2" },
    { value = "toxiui",     text = "ToxiUI Clean",     path = "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\ToxiUI-clean.tga", lsm = "ToxiUI-clean" },
    { value = "birg00",     text = "Birg00",            lsm = "Birg00" },
    { value = "charcoal",   text = "Charcoal",          lsm = "Charcoal" },
    { value = "elvui",      text = "ElvUI Norm1",       lsm = "ElvUI Norm1" },
    { value = "samw00",     text = "Samw00",            lsm = "Samw00" },
    { value = "flat",       text = "Flat (WoW)",        path = "Interface\\Buttons\\WHITE8X8" },
    { value = "statusbar",  text = "StatusBar (WoW)",   path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { value = "aluminium",  text = "Aluminium",         lsm = "Aluminium" },
    { value = "armory",     text = "Armory",            lsm = "Armory" },
    { value = "blizzard",   text = "Blizzard",          path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { value = "cloud",      text = "Cloud",             lsm = "Cloud" },
    { value = "comet",      text = "Comet",             lsm = "Comet" },
    { value = "dabs",       text = "Dabs",              lsm = "Dabs" },
    { value = "darkbottom", text = "DarkBottom",        lsm = "DarkBottom" },
    { value = "diagonal",   text = "Diagonal",          lsm = "Diagonal" },
    { value = "elv_gloss",  text = "ElvUI Gloss",       lsm = "ElvUI Gloss" },
    { value = "elv_melli",  text = "ElvUI Melli",       lsm = "ElvUI Melli" },
    { value = "falcon",     text = "Falcon",            lsm = "Falcon" },
    { value = "glaze",      text = "Glaze",             lsm = "Glaze" },
    { value = "gloss",      text = "Gloss",             lsm = "Gloss" },
    { value = "gradient",   text = "Gradient",          lsm = "Gradient" },
    { value = "litestep",   text = "LiteStep",          lsm = "LiteStep" },
    { value = "lyfe",       text = "Lyfe",              lsm = "Lyfe" },
    { value = "melli",      text = "Melli",             lsm = "Melli" },
    { value = "minimalist", text = "Minimalist",        lsm = "Minimalist" },
    { value = "normtex",    text = "NormTex",           lsm = "normTex" },
    { value = "otravi",     text = "Otravi",            lsm = "Otravi" },
    { value = "outline",    text = "Outline",           lsm = "Outline" },
    { value = "perl",       text = "Perl",              lsm = "Perl" },
    { value = "rain",       text = "Rain",              lsm = "Rain" },
    { value = "round",      text = "Round",             lsm = "Round" },
    { value = "ruben",      text = "Ruben",             lsm = "Ruben" },
    { value = "skullflower",text = "Skullflower",       lsm = "Skullflower" },
    { value = "smooth",     text = "Smooth",            lsm = "Smooth" },
    { value = "smooth_v2",  text = "Smooth v2",         lsm = "Smooth v2" },
    { value = "steel",      text = "Steel",             lsm = "Steel" },
    { value = "striped",    text = "Striped",           lsm = "Striped" },
    { value = "tube",       text = "Tube",              lsm = "Tube" },
    { value = "water",      text = "Water",             lsm = "Water" },
    { value = "wglass",     text = "WGlass",            lsm = "WGlass" },
    { value = "wisps",      text = "Wisps",             lsm = "Wisps" },
}

------------------------------------------------------------------------
-- CASCADE URGENCY (2 niveaux en SECONDES)
------------------------------------------------------------------------
ns.URGENCY = { MEDIUM = 5, CRITICAL = 2 }

------------------------------------------------------------------------
-- RESOLVE TEXTURE VIA LSM
------------------------------------------------------------------------
function ns.ResolveLSMTexture(entry)
    if entry.lsm then
        local ok, LSM = pcall(function()
            return LibStub and LibStub("LibSharedMedia-3.0", true)
        end)
        if ok and LSM then
            local p = LSM:Fetch("statusbar", entry.lsm)
            if p then return p end
        end
    end
    return entry.path or ns.Media.fallbackBar
end

function ns.ResolveBarTexFromKey(texKey)
    if texKey then
        for _, e in ipairs(ns.BAR_TEXTURES) do
            if e.value == texKey then return ns.ResolveLSMTexture(e) end
        end
    end
    local def = ns.BAR_TEXTURES[1]
    return def and ns.ResolveLSMTexture(def) or ns.Media.fallbackBar
end

------------------------------------------------------------------------
-- UTILITY
------------------------------------------------------------------------
function ns.DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = ns.DeepCopy(v) end
    return copy
end

function ns.MergeDefaults(saved, defaults)
    if type(defaults) ~= "table" then return saved end
    if type(saved) ~= "table" then return ns.DeepCopy(defaults) end
    for k, v in pairs(defaults) do
        if saved[k] == nil then saved[k] = ns.DeepCopy(v)
        elseif type(v) == "table" and type(saved[k]) == "table" then
            ns.MergeDefaults(saved[k], v)
        end
    end
    return saved
end

------------------------------------------------------------------------
-- RENDER REGISTRY
------------------------------------------------------------------------
ns.RenderRegistry = {}
function ns.RegisterRender(id, renderTable)
    ns.RenderRegistry[id] = renderTable
end

------------------------------------------------------------------------
-- TOOLTIP au survol des icônes buff/debuff (Debuffs/Cooldowns/Procs).
-- Partagé entre les 3 renders pour éviter de dupliquer la logique 3 fois.
-- Option dédiée aux auras (ns.db.tooltipAltCombatOnly, section Tactics du
-- menu Auras) — INDÉPENDANTE de l'équivalent priorityBar.tooltipAltCombatOnly
-- utilisé par la barre de priorité (les deux réglages étaient partagés à
-- l'origine, séparés sur demande pour pouvoir les activer/désactiver
-- indépendamment). En combat, le tooltip n'apparaît que tant qu'ALT est
-- maintenu (évite de saturer l'écran de tooltips en plein combat). Hors
-- combat, le tooltip s'affiche normalement au survol. MODIFIER_STATE_CHANGED
-- + PLAYER_REGEN_DISABLED/ENABLED permettent de montrer/cacher le tooltip EN
-- TEMPS RÉEL pendant qu'on survole une icône (appuyer/relâcher ALT sans
-- bouger la souris doit réagir immédiatement).
------------------------------------------------------------------------
-- GameTooltip:SetUnitAura(unit, index, filter) attend un INDEX de position
-- dans la liste d'auras, pas un auraInstanceID (d'où un tooltip vide : l'API
-- cherchait la Nième aura au lieu de l'aura ciblée). Les instanceID ont leurs
-- propres méthodes dédiées — même pattern déjà utilisé et fonctionnel dans
-- Modules/TargetAuras.lua (Aura_OnEnter).
local function _SetUnitAuraTooltip(unit, instID, filter)
    if filter == "HELPFUL" then
        GameTooltip:SetUnitBuffByAuraInstanceID(unit, instID)
    else
        GameTooltip:SetUnitDebuffByAuraInstanceID(unit, instID)
    end
end

local function ShouldShowAuraTooltip()
    if not (ns.db and ns.db.tooltipAltCombatOnly) then return true end
    if not UnitAffectingCombat("player") then return true end
    return IsAltKeyDown()
end

local _ttDebug = false
local function _ttp(msg) if _ttDebug then DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCTT]|r " .. tostring(msg)) end end

local hoveredAuraIcon
local function RefreshAuraTooltip()
    if not hoveredAuraIcon or GameTooltip:IsForbidden() then return end
    if not ShouldShowAuraTooltip() then
        _ttp("RefreshAuraTooltip: ShouldShowAuraTooltip=false -> Hide()")
        GameTooltip:Hide()
        return
    end
    GameTooltip:SetOwner(hoveredAuraIcon, "ANCHOR_BOTTOMRIGHT", 5, -5)
    _ttp(string.format("RefreshAuraTooltip: unit=%s auraInstanceID=%s spellID=%s",
        tostring(hoveredAuraIcon.unit), tostring(hoveredAuraIcon.auraInstanceID), tostring(hoveredAuraIcon.spellID)))
    local gotAura = false
    if hoveredAuraIcon.unit and hoveredAuraIcon.auraInstanceID then
        local ok = pcall(_SetUnitAuraTooltip, hoveredAuraIcon.unit, hoveredAuraIcon.auraInstanceID,
            hoveredAuraIcon.unit == "player" and "HELPFUL" or "HARMFUL")
        gotAura = ok and GameTooltip:NumLines() > 0
    end
    if not gotAura and hoveredAuraIcon.spellID then
        -- Pas d'aura active (proc "prêt" sans buff en cours) OU auraInstanceID
        -- périmé (aura déjà retombée entre le dernier scan et le survol) : on
        -- retombe sur le tooltip de sort générique plutôt que de laisser un
        -- tooltip vide (SetOwner+Show sans contenu, quasi invisible à l'écran).
        pcall(GameTooltip.SetSpellByID, GameTooltip, hoveredAuraIcon.spellID)
    end
    GameTooltip:Show()
    _ttp("RefreshAuraTooltip: NumLines=" .. tostring(GameTooltip:NumLines()))
end

function ns.AuraIconOnEnter(self)
    local w, h = self:GetSize()
    _ttp(string.format("OnEnter appelé. Forbidden=%s IsVisible=%s size=%sx%s unit=%s auraInstanceID=%s spellID=%s",
        tostring(GameTooltip:IsForbidden()), tostring(self:IsVisible()), tostring(w), tostring(h),
        tostring(self.unit), tostring(self.auraInstanceID), tostring(self.spellID)))
    if GameTooltip:IsForbidden() or not self:IsVisible() then return end
    hoveredAuraIcon = self
    RefreshAuraTooltip()
    _ttp("Après RefreshAuraTooltip : GameTooltip:IsShown()=" .. tostring(GameTooltip:IsShown()))
end

function ns.AuraIconOnLeave(self)
    _ttp("OnLeave appelé.")
    if hoveredAuraIcon == self then hoveredAuraIcon = nil end
    if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local _tooltipWatcher = CreateFrame("Frame")
_tooltipWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
_tooltipWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
_tooltipWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
_tooltipWatcher:SetScript("OnEvent", RefreshAuraTooltip)

SLASH_RCTTDEBUG1 = "/rctt"
SlashCmdList["RCTTDEBUG"] = function()
    _ttDebug = not _ttDebug
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCTT]|r debug tooltip = " .. tostring(_ttDebug))
end

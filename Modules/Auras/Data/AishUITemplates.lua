-- AishUIAura/Data/AishUITemplates.lua
-- 25 presets uniques de barres animees avec noms thematiques.
-- Chaque preset definit des dimensions (bar + spark). Les couleurs
-- ne sont JAMAIS imposees par les presets : AishUIAura gere les
-- couleurs separement par sort.
-- Pas de filtre par classe : l'utilisateur parcourt la liste par style visuel.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

ns.AishUISparkTextures = {
    honor = "atlas:honorsystem-bar-spark",
    encounter = "atlas:GarrMission_EncounterBar-Spark",
}

ns.AishUITemplates = {
    {
        name = L["AURASDATA_TEMPLATE_GOLDEN_THREAD"],
        w = 40, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_SHADOW_THREAD"],
        w = 40, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_SCARLET_CLAW"],
        w = 50, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_DEMONIC_WEAVE"],
        w = 50, h = 3.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_OPENING_STATUE"],
        w = 50, h = 3.5,
        spark_type = "honor",
        spark_w = 150, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_GARNET_VEIN"],
        w = 50, h = 4.0,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_HEAVY_EMBER"],
        w = 50, h = 12.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_TIGER_RIBBON"],
        w = 55, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_SERPENTINE_RIBBON"],
        w = 55, h = 2.0,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_DOUBLE_FILAMENT"],
        w = 55, h = 3.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 11,
    },
    {
        name = L["AURASDATA_TEMPLATE_INCARNATION_TRIM"],
        w = 55, h = 3.0,
        spark_type = "honor",
        spark_w = 20, spark_h = 11,
    },
    {
        name = L["AURASDATA_TEMPLATE_JADE_TRIM"],
        w = 55, h = 4.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_CLASSIC_VEIN"],
        w = 80, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_AFFLICTION_VEIN"],
        w = 80, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_LUCKY_VEIL"],
        w = 80, h = 2.0,
        spark_type = "honor",
        spark_w = 46, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_ARCANE_FRESCO"],
        w = 125, h = 3.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_BLUE_RAMPART"],
        w = 147, h = 4.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_SOBER_RAMPART"],
        w = 147, h = 4.5,
        spark_type = "honor",
        spark_w = 10, spark_h = 10,
    },
    {
        name = L["AURASDATA_TEMPLATE_FRAGILE_WAVE"],
        w = 198, h = 1.5,
        spark_type = "encounter",
        spark_w = 5, spark_h = 8,
    },
    {
        name = L["AURASDATA_TEMPLATE_PROTECTIVE_WAVE"],
        w = 198, h = 2.5,
        spark_type = "encounter",
        spark_w = 5, spark_h = 8,
    },
    {
        name = L["AURASDATA_TEMPLATE_FROST_WAVE"],
        w = 198, h = 2.5,
        spark_type = "encounter",
        spark_w = 17, spark_h = 8,
    },
    {
        name = L["AURASDATA_TEMPLATE_FELINE_TRAIL"],
        w = 244, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_TAUT_THREAD"],
        w = 322, h = 1.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_SIGHT_ARC"],
        w = 359, h = 4.0,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = L["AURASDATA_TEMPLATE_ARCANE_FRESCO_2"],
        w = 361, h = 4.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
}

-- Helper : applique un preset. Ne touche JAMAIS aux couleurs.
function ns.ApplyAishUITemplate(renderKey, preset)
    if not ns.db or not ns.db[renderKey] or not preset then return end
    local cfg = ns.db[renderKey]
    cfg.barW = preset.w
    cfg.barH = preset.h
    if preset.spark_w and preset.spark_w > 0 and preset.spark_h and preset.spark_h > 0 then
        cfg.sparkW = preset.spark_w
        cfg.sparkH = preset.spark_h
        cfg.sparkEnabled = true
        local tex = ns.AishUISparkTextures and ns.AishUISparkTextures[preset.spark_type]
        if tex then cfg.sparkTexture = tex end
    else
        cfg.sparkEnabled = false
    end
    if ns.RebuildDisplay then pcall(ns.RebuildDisplay) end
end
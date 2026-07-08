-- AishUIAura/Data/AishUITemplates.lua
-- 25 presets uniques de barres animees avec noms thematiques.
-- Chaque preset definit des dimensions (bar + spark). Les couleurs
-- ne sont JAMAIS imposees par les presets : AishUIAura gere les
-- couleurs separement par sort.
-- Pas de filtre par classe : l'utilisateur parcourt la liste par style visuel.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.AishUISparkTextures = {
    honor = "atlas:honorsystem-bar-spark",
    encounter = "atlas:GarrMission_EncounterBar-Spark",
}

ns.AishUITemplates = {
    {
        name = "Filet dore",
        w = 40, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = "Filet d'ombre",
        w = 40, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = "Griffe ecarlate",
        w = 50, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = "Trame demoniaque",
        w = 50, h = 3.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 10,
    },
    {
        name = "Statue ouvrante",
        w = 50, h = 3.5,
        spark_type = "honor",
        spark_w = 150, spark_h = 10,
    },
    {
        name = "Veine grenat",
        w = 50, h = 4.0,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = "Braise lourde",
        w = 50, h = 12.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = "Ruban du tigre",
        w = 55, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = "Ruban serpentin",
        w = 55, h = 2.0,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = "Filament double",
        w = 55, h = 3.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 11,
    },
    {
        name = "Lisere d'incarnation",
        w = 55, h = 3.0,
        spark_type = "honor",
        spark_w = 20, spark_h = 11,
    },
    {
        name = "Lisere jade",
        w = 55, h = 4.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = "Veine classique",
        w = 80, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = "Veine afflic",
        w = 80, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 10,
    },
    {
        name = "Voile de chance",
        w = 80, h = 2.0,
        spark_type = "honor",
        spark_w = 46, spark_h = 6,
    },
    {
        name = "Fresque arcane",
        w = 125, h = 3.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 10,
    },
    {
        name = "Rempart bleu",
        w = 147, h = 4.5,
        spark_type = "honor",
        spark_w = 18, spark_h = 10,
    },
    {
        name = "Rempart sobre",
        w = 147, h = 4.5,
        spark_type = "honor",
        spark_w = 10, spark_h = 10,
    },
    {
        name = "Onde fragile",
        w = 198, h = 1.5,
        spark_type = "encounter",
        spark_w = 5, spark_h = 8,
    },
    {
        name = "Onde proctective",
        w = 198, h = 2.5,
        spark_type = "encounter",
        spark_w = 5, spark_h = 8,
    },
    {
        name = "Onde de gel",
        w = 198, h = 2.5,
        spark_type = "encounter",
        spark_w = 17, spark_h = 8,
    },
    {
        name = "Traînee feline",
        w = 244, h = 2.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = "Fil tendu",
        w = 322, h = 1.0,
        spark_type = "honor",
        spark_w = 17, spark_h = 6,
    },
    {
        name = "Arc de mire",
        w = 359, h = 4.0,
        spark_type = "honor",
        spark_w = 18, spark_h = 6,
    },
    {
        name = "Fresque arcanique",
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
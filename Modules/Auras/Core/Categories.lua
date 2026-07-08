-- AishUIAura/Core/Categories.lua
-- ============================================================================
-- Structure hiérarchique du panneau unifié (préparation fusion AishUI).
--
-- 7 catégories × 24 sections.
--
-- Chaque section a :
--   • id       : identifiant unique stable (ne pas changer — sert aux SavedVariables)
--   • label    : nom affiché en FR
--   • source   : "AishUIAura" | "Aishaddon" | "mixed"
--   • builder  : nom de la fonction ns.SettingsPanel.BuildXxxMenu à appeler
--                (ou nil si section non encore branchée)
--   • tooltip  : (optionnel) texte de l'info-bulle "?"
--
-- Note : les "builder" pointant vers des menus Aishaddon sont nil pour l'instant,
-- un placeholder "À venir" sera affiché à la place.
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

ns.CATEGORIES = {
    ----------------------------------------------------------------------------
    -- 1. JOUEUR — tout ce qui parle du joueur
    ----------------------------------------------------------------------------
    {
        id = "joueur",
        label = L["AURASDATA_CAT_PLAYER"],
        sections = {
            { id = "unitBars",       label = L["AURASDATA_SEC_UNITBARS_LABEL"],        source = "Aishaddon",
              desc = L["AURASDATA_SEC_UNITBARS_DESC"] },
            { id = "castBar",        label = L["AURASDATA_SEC_CASTBAR_LABEL"], source = "Aishaddon",
              desc = L["AURASDATA_SEC_CASTBAR_DESC"] },
            { id = "resourceCircle", label = L["AURASDATA_LABEL_RESOURCE_CIRCLE"],    source = "Aishaddon",
              desc = L["AURASDATA_SEC_RESOURCECIRCLE_DESC"] },
            { id = "healthCircle",   label = L["AURASDATA_LABEL_RECOVERY_CIRCLE"],        source = "Aishaddon",
              desc = L["AURASDATA_SEC_HEALTHCIRCLE_DESC"] },
        },
    },

    ----------------------------------------------------------------------------
    -- 2. CIBLE — tout ce qui parle de la cible
    ----------------------------------------------------------------------------
    {
        id = "cible",
        label = L["AURASDATA_CAT_TARGET"],
        sections = {
            { id = "topTargetBar",  label = L["AURASDATA_SEC_TOPTARGETBAR_LABEL"],         source = "Aishaddon",
              desc = L["AURASDATA_SEC_TOPTARGETBAR_DESC"] },
            { id = "targetCastBar", label = L["AURASDATA_SEC_TARGETCASTBAR_LABEL"], source = "Aishaddon",
              desc = L["AURASDATA_SEC_TARGETCASTBAR_DESC"] },
        },
    },

    ----------------------------------------------------------------------------
    -- 3. MES SORTS — containers visuels AishUIAura
    ----------------------------------------------------------------------------
    {
        id = "mesSorts",
        label = L["AURASDATA_CAT_MY_SPELLS"],
        sections = {
            { id = "spellsTracked",  label = L["AURASDATA_LABEL_SPELLS_TRACKED"],        source = "AishUIAura",
              builder = "BuildTacticsMenu",
              desc = L["AURASDATA_SEC_SPELLSTRACKED_DESC"] },
            { id = "debuffs",   label = L["AURASDATA_SEC_DEBUFFS_LABEL"],   source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "iconlist",
              desc = L["AURASDATA_SEC_DEBUFFS_DESC"],
              tooltip = L["AURASDATA_SEC_DEBUFFS_TOOLTIP"] },
            { id = "buffs",     label = L["AURASDATA_SEC_BUFFS_LABEL"],     source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "freebars",
              desc = L["AURASDATA_SEC_BUFFS_DESC"],
              tooltip = L["AURASDATA_SEC_BUFFS_TOOLTIP"] },
            { id = "procs",     label = L["AURASDATA_SEC_PROCS_LABEL"],     source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "icons",
              desc = L["AURASDATA_SEC_PROCS_DESC"],
              tooltip = L["AURASDATA_SEC_PROCS_TOOLTIP"] },
            { id = "cooldowns", label = L["AURASDATA_SEC_COOLDOWNS_LABEL"], source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "circlebars",
              desc = L["AURASDATA_SEC_COOLDOWNS_DESC"],
              tooltip = L["AURASDATA_SEC_COOLDOWNS_TOOLTIP"] },
            { id = "trinkets",  label = L["AURASDATA_SEC_TRINKETS_LABEL"],  source = "AishUIAura",
              builder = "BuildEquipmentMenu",
              desc = L["AURASDATA_SEC_TRINKETS_DESC"],
              tooltip = L["AURASDATA_SEC_TRINKETS_TOOLTIP"] },
        },
    },

    ----------------------------------------------------------------------------
    -- 4. ROTATION — aide à la décision
    ----------------------------------------------------------------------------
    {
        id = "rotation",
        label = L["AURASDATA_CAT_ROTATION"],
        sections = {
            { id = "priorityBar",    label = L["AURASDATA_SEC_PRIORITYBAR_LABEL"], source = "Aishaddon",
              desc = L["AURASDATA_SEC_PRIORITYBAR_DESC"],
              tooltip = L["AURASDATA_SEC_PRIORITYBAR_TOOLTIP"] },
            { id = "rotationHelper", label = L["AURASDATA_SEC_ROTATIONHELPER_LABEL"],     source = "Aishaddon",
              desc = L["AURASDATA_SEC_ROTATIONHELPER_DESC"] },
        },
    },

    ----------------------------------------------------------------------------
    -- 5. Anims 3D — animations 3D
    ----------------------------------------------------------------------------
    {
        id = "effets3D",
        label = L["AURASDATA_CAT_3D_ANIMS"],
        sections = {
            { id = "fxOnAura",     label = L["AURASDATA_SEC_FXONAURA_LABEL"],              source = "AishUIAura",
              builder = "BuildEffectsMenu",
              desc = L["AURASDATA_SEC_FXONAURA_DESC"] },
            { id = "fxOnResource", label = L["AURASDATA_LABEL_RESOURCE_CIRCLE"], source = "Aishaddon",
              desc = L["AURASDATA_SEC_FXONRESOURCE_DESC"] },
            { id = "fxOnSecRes",   label = L["AURASDATA_SEC_FXONSECRES_LABEL"], source = "Aishaddon",
              desc = L["AURASDATA_SEC_FXONSECRES_TEXT"],
              tooltip = L["AURASDATA_SEC_FXONSECRES_TEXT"] },
            { id = "fxOnRecup",    label = L["AURASDATA_LABEL_RECOVERY_CIRCLE"],     source = "Aishaddon",
              desc = L["AURASDATA_SEC_FXONRECUP_TEXT"],
              tooltip = L["AURASDATA_SEC_FXONRECUP_TEXT"] },
        },
    },

    ----------------------------------------------------------------------------
    -- 6. MONDE — exploration et progression
    ----------------------------------------------------------------------------
    {
        id = "horsCombat",
        label = L["AURASDATA_CAT_WORLD"],
        sections = {
            { id = "xpBar",     label = L["AURASDATA_SEC_XPBAR_LABEL"], source = "Aishaddon",
              desc = L["AURASDATA_SEC_XPBAR_DESC"] },
            { id = "skyriding", label = L["AURASDATA_SEC_SKYRIDING_LABEL"],          source = "Aishaddon",
              desc = L["AURASDATA_SEC_SKYRIDING_DESC"] },
        },
    },

    ----------------------------------------------------------------------------
    -- 7. GÉNÉRAL — config globale
    ----------------------------------------------------------------------------
    {
        id = "general",
        label = L["AURASDATA_CAT_GENERAL"],
        sections = {
            { id = "colors",   label = L["AURASDATA_SEC_COLORS_LABEL"], source = "mixed",
              desc = L["AURASDATA_SEC_COLORS_DESC"] },
            { id = "preview",  label = L["AURASDATA_SEC_PREVIEW_LABEL"],           source = "AishUIAura",
              builder = "BuildPreviewMenu",
              desc = L["AURASDATA_SEC_PREVIEW_DESC"] },
            { id = "profiles", label = L["AURASDATA_SEC_PROFILES_LABEL"],          source = "mixed",
              builder = "BuildProfilesMenu",
              desc = L["AURASDATA_SEC_PROFILES_DESC"] },
        },
    },
}

-- Helper : retourne la catégorie par son id
function ns.GetCategory(id)
    for _, cat in ipairs(ns.CATEGORIES) do
        if cat.id == id then return cat end
    end
    return nil
end

-- Helper : retourne la section par (catId, sectionId)
function ns.GetSection(catId, sectionId)
    local cat = ns.GetCategory(catId)
    if not cat then return nil end
    for _, sec in ipairs(cat.sections) do
        if sec.id == sectionId then return sec end
    end
    return nil
end

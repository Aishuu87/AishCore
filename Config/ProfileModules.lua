-- Config/ProfileModules.lua : arbre des éléments de profil exportables / importables / copiables /
-- réinitialisables séparément (cf. docs/PLAN_OPTIMISATION_MEMOIRE.md § 6). Même découpage que la page
-- "Modules" du GUI : section > élément > sous-élément. Ajouter une fonctionnalité = déclarer ici ses
-- chemins de données.
local addonName, ns = ...

-- Nœud :
--   id, label (clé de locale), children (sous-nœuds)
--   core  : chemins dans AishaddonDB._profiles[p]     auras : chemins dans AishUIAuraDB.profiles[p]
--           "a.b.c"                       = valeur remplacée entièrement
--           { path = "a", except = {...} } = table remplacée sauf les sous-clés listées (portées par
--                                            d'autres nœuds, ex. unitBars sans ses barres)
--   apply : modules ns.Modules.* à réappliquer après import / copie sur le profil actif
--   misc  : true = toute clé de profil qu'aucun autre nœud ne déclare (filet de sécurité)
-- Section (1er niveau) : panel = catégorie de la page "Modules" (modulesPanel.categoryOff)
ns.ProfileTree = {
  { id = "combat", label = "SETTINGS_GROUP_COMBAT", panel = "combat", children = {
    { id = "resourceCircle", label = "SETTINGS_SEC_RESOURCE_CIRCLE", core = { "resourceCircle" }, apply = { "ResourceCircle" } },
    { id = "priorityBar", label = "SETTINGS_SEC_PRIORITY_BAR", core = { "priorityBar", "prioritySlots" }, apply = { "PriorityBar" } },
    { id = "cdmEssential", label = "SETTINGS_CAT_CDM_ESSENTIAL", core = { "cdmEssential" }, apply = { "CooldownManagerEnhanced" } },
    { id = "cdmUtility", label = "SETTINGS_CAT_CDM_UTILITY", core = { "cdmUtility" }, apply = { "CooldownManagerEnhanced" } },
    { id = "cdmLayout", label = "SETTINGS_CAT_CDM_LAYOUT", core = { "cdmLayout" } },
    { id = "bigCursor", label = "SETTINGS_MOD_BIG_CURSOR", core = { "bigCursor" }, apply = { "BigCursor" } },
    { id = "rotationHelper", label = "SETTINGS_CAT_ROTATION_HELPER", core = { "rotationHelper" }, apply = { "RotationHelper" } },
  } },
  { id = "unitFrames", label = "SETTINGS_GROUP_UNIT_FRAMES", panel = "unitFrames", children = {
    { id = "unitBars", label = "SETTINGS_CAT_HEALTH_BARS", core = { { path = "unitBars", except = { "bars" } } },
      apply = { "UnitBars" }, children = {
        { id = "unitBars.player", label = "SETTINGS_UNIT_PLAYER", core = { "unitBars.bars.player" }, apply = { "UnitBars" } },
        { id = "unitBars.target", label = "SETTINGS_UNIT_TARGET", core = { "unitBars.bars.target" }, apply = { "UnitBars" } },
        { id = "unitBars.focus", label = "SETTINGS_UNIT_FOCUS", core = { "unitBars.bars.focus" }, apply = { "UnitBars" } },
        { id = "unitBars.pet", label = "SETTINGS_UNIT_PET", core = { "unitBars.bars.pet" }, apply = { "UnitBars" } },
        { id = "unitBars.targettarget", label = "SETTINGS_UNIT_TARGET_OF_TARGET", core = { "unitBars.bars.targettarget" }, apply = { "UnitBars" } },
      } },
    { id = "castBar", label = "SETTINGS_SEC_CAST_BAR", core = { "castBar" }, apply = { "CastBar" } },
    { id = "targetCastBar", label = "SETTINGS_CAT_TARGET_CAST", core = { "targetCastBar" }, apply = { "TargetCastBar" } },
    { id = "topTargetBar", label = "SETTINGS_CAT_TOP_TARGET", core = { "topTargetBar" }, apply = { "TopTargetBar" }, children = {
        { id = "targetAuras", label = "SETTINGS_CAT_TARGET_AURAS", core = { "targetAuras" }, apply = { "TargetAuras" } },
      } },
    { id = "groupNumber", label = "SETTINGS_SEC_GROUP_NUMBER", core = { "groupNumber" }, apply = { "GroupNumber" } },
  } },
  { id = "hud", label = "SETTINGS_GROUP_WORLD", panel = "world", children = {
    { id = "healthCircle", label = "SETTINGS_MOD_HEALTH_CIRCLE", core = { "healthCircle" }, apply = { "HealthCircle" } },
    { id = "outOfCombatResourceCircle", label = "SETTINGS_SEC_OCRC", core = { "outOfCombatResourceCircle" }, apply = { "OutOfCombatResourceCircle" } },
    { id = "xpBar", label = "SETTINGS_CAT_XP_BAR", core = { "xpBar" }, apply = { "XPBar" } },
    { id = "skyriding", label = "SETTINGS_CAT_SKYRIDING", core = { "skyriding" }, apply = { "Skyriding" } },
    { id = "location", label = "SETTINGS_CAT_LOCATION", core = { "location" }, apply = { "Location" } },
    { id = "extraBars", label = "SETTINGS_CAT_EXTRA_BARS", core = { "extraBars" }, apply = { "ExtraBars" } },
    { id = "afkMode", label = "SETTINGS_CAT_AFK_MODE", core = { "afkMode" }, apply = { "AFKMode" } },
    { id = "characterArmory", label = "SETTINGS_CAT_CHARACTER_ARMORY", core = { "characterArmory" }, apply = { "CharacterArmory" } },
    { id = "visibility", label = "SETTINGS_CAT_VISIBILITY", core = { "visibility", "addonFonts" }, apply = { "Visibility", "AddonFonts" } },
  } },
  { id = "aurasProcs", label = "SETTINGS_GROUP_AURAS_PROCS", panel = "auras", children = {
    { id = "aurasTracking", label = "SETTINGS_MOD_AURAS_TRACKING",
      auras = { "discoveredSpells", "defaultGlowBySpec", "defaultGlowIdx", "defaultGlowColorR", "defaultGlowColorG",
                "defaultGlowColorB", "defaultGlowAlpha", "defaultGlowScale", "defaultProcGlowIdx", "useNativeCDM",
                "useSpellColors", "hideCDMBuffFrames", "tooltipAltCombatOnly", "enabled",
                "effectsEnabled", "effects3DAutoDisableInRaid" },
      children = {
        { id = "aurasIconlist", label = "SETTINGS_CAT_ICON_LIST", auras = { "iconlist", "iconlistEnabled" } },
        { id = "aurasFreebars", label = "SETTINGS_CAT_CIRCLE_BARS", auras = { "freebars", "freebarsEnabled" } },
        { id = "aurasIcons", label = "SETTINGS_CAT_ICONS", auras = { "icons", "iconsEnabled" } },
        { id = "aurasCirclebars", label = "SETTINGS_CAT_FREE_BARS", auras = { "circlebars", "circlebarsEnabled" } },
        { id = "aurasTotems", label = "SETTINGS_CAT_TOTEMS", auras = { "totems", "totemsEnabled" } },
      } },
    { id = "aurasTrinkets", label = "SETTINGS_CAT_TRINKETS", auras = { "equipment", "equipmentSlots", "equipmentEnabled" } },
    { id = "aurasMissingBuffs", label = "AURASDATA_SEC_MISSINGBUFFS_LABEL", auras = { "missingBuffs" } },
  } },
  -- Section porteuse de données : réglages communs de spellEffects (activation globale, taille des
  -- modèles, coupure raid / groupe), chaque type d'animation étant un élément à part.
  { id = "animations", label = "SETTINGS_GROUP_ANIMATIONS", panel = "animations", apply = { "SpellEffects" },
    core = { { path = "spellEffects", except = {
      "oocCombos", "oocEnabled", "combos", "combosMeta", "combosAliases", "manualSpells", "spells", "spellsEnabled",
      "auraCombos", "auraCombosMissing", "aurasEnabled", "missingBuffsCombos", "missingBuffsEnabled",
      "logoCombos", "logosEnabled", "orbCombos", "orbGlobeColors", "orbsEnabled" } } },
    children = {
      { id = "modelLibrary", label = "PROFILE_MODULE_MODEL_LIBRARY",
        core = { "modelCustomTags", "modelTagKeywords", "modelTagColors", "modelTagUserDefined" } },
      { id = "animOoc", label = "PROFILE_ITEM_ANIM_OOC", core = { "spellEffects.oocCombos", "spellEffects.oocEnabled" }, apply = { "SpellEffects" } },
      { id = "animSpells", label = "PROFILE_ITEM_ANIM_SPELLS",
        core = { "spellEffects.combos", "spellEffects.combosMeta", "spellEffects.combosAliases", "spellEffects.manualSpells",
                 "spellEffects.spells", "spellEffects.spellsEnabled" }, apply = { "SpellEffects" } },
      { id = "animAuras", label = "PROFILE_ITEM_ANIM_AURAS",
        core = { "spellEffects.auraCombos", "spellEffects.auraCombosMissing", "spellEffects.aurasEnabled" }, apply = { "SpellEffects" } },
      { id = "animMissingBuffs", label = "PROFILE_ITEM_ANIM_MISSING",
        core = { "spellEffects.missingBuffsCombos", "spellEffects.missingBuffsEnabled" }, apply = { "SpellEffects" } },
      { id = "animLogos", label = "PROFILE_ITEM_ANIM_LOGOS", core = { "spellEffects.logoCombos", "spellEffects.logosEnabled" }, apply = { "SpellEffects" } },
      { id = "animOrbs", label = "PROFILE_ITEM_ANIM_ORBS",
        core = { "spellEffects.orbCombos", "spellEffects.orbGlobeColors", "spellEffects.orbsEnabled" }, apply = { "SpellEffects" } },
    } },
  { id = "global", label = "SETTINGS_GROUP_GLOBAL", children = {
    { id = "colors", label = "SETTINGS_CAT_COLORS", core = { "colors", "themes", "specDefaults" }, apply = { "Colors" } },
    { id = "misc", label = "PROFILE_MODULE_MISC", misc = true },
  } },
}

-- Jamais exporté ni copié : réglages propres à l'installation. Les clés "_*" (flags de migration)
-- sont exclues d'office.
ns.ProfileTreeExcluded = {
  -- cdmBySpec / cdmAutoApply : ancienne feature retirée, ignorée dans les anciennes chaînes
  core  = { minimapButton = true, modulesPanel = true, cdmBySpec = true, cdmAutoApply = true },
  auras = { addonVersion = true },
}

-- Index : byId[id] = nœud ; order = nœuds dans l'ordre de l'arbre ; section[id] = section du nœud ;
-- covered[store][cléDePremierNiveau] = true si un nœud la déclare (le reste va dans "misc").
local index
local function TopKey(entry)
  local p = type(entry) == "table" and entry.path or entry
  return (p:match("^[^.]+"))
end

function ns.GetProfileTreeIndex()
  if index then return index end
  index = { byId = {}, order = {}, section = {}, parent = {}, covered = { core = {}, auras = {} } }
  local function Walk(nodes, section, parent, depth)
    for _, n in ipairs(nodes) do
      -- Cles toujours couvertes, meme pour un module indisponible sur ce client : sinon ses
      -- donnees retomberaient dans "Autres reglages".
      for _, store in ipairs({ "core", "auras" }) do
        for _, e in ipairs(n[store] or {}) do index.covered[store][TopKey(e)] = true end
      end
      if ns.IsModuleAvailable(n.id) then
        n.depth = depth
        index.byId[n.id] = n
        index.order[#index.order + 1] = n
        index.section[n.id] = section or n
        index.parent[n.id] = parent
        if n.children then Walk(n.children, section or n, n, depth + 1) end
      end
    end
  end
  Walk(ns.ProfileTree, nil, nil, 0)
  return index
end

-- Nœud porteur de données (exportable), par opposition aux sections
function ns.IsProfileDataNode(n)
  return n.core ~= nil or n.auras ~= nil or n.misc == true
end

-- Clé de premier niveau non déclarée par l'arbre (va dans "misc") ?
function ns.IsProfileMiscKey(store, key)
  if type(key) ~= "string" or key:sub(1, 1) == "_" then return false end
  if ns.ProfileTreeExcluded[store][key] then return false end
  return not ns.GetProfileTreeIndex().covered[store][key]
end

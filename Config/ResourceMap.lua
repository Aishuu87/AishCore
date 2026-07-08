-- Config/ResourceMap.lua : Detection de la ressource primaire par classe/specialisation
-- Inspire du fonctionnement de SenseiClassResourceBar (PrimaryResourceBar.lua)
local addonName, ns = ...

---------------------------------------------------------------------------
-- Ressource primaire par classe
-- Classes simples : Enum.PowerType directement
-- Classes avec variation par spec : table { [specID] = Enum.PowerType }
---------------------------------------------------------------------------
local classPrimaryResource = {
  DEATHKNIGHT = Enum.PowerType.RunicPower,
  DEMONHUNTER = Enum.PowerType.Fury,
  EVOKER = {
    [1467] = Enum.PowerType.Essence,  -- Devastation
    [1468] = Enum.PowerType.Mana,     -- Preservation
    [1473] = Enum.PowerType.Essence,  -- Augmentation
  },
  HUNTER      = Enum.PowerType.Focus,
  MAGE        = Enum.PowerType.Mana,
  PALADIN = {
    [65]  = Enum.PowerType.Mana,       -- Holy
    [66]  = Enum.PowerType.HolyPower,  -- Protection
    [70]  = Enum.PowerType.HolyPower,  -- Retribution
  },
  ROGUE       = Enum.PowerType.Energy,
  WARLOCK     = Enum.PowerType.SoulShards,
  WARRIOR     = Enum.PowerType.Rage,
  -- Classes avec variation par specialisation
  MONK = {
    [268] = Enum.PowerType.Energy,    -- Brewmaster
    [269] = Enum.PowerType.Energy,    -- Windwalker
    [270] = Enum.PowerType.Mana,      -- Mistweaver
  },
  PRIEST = {
    [256] = Enum.PowerType.Mana,      -- Discipline
    [257] = Enum.PowerType.Mana,      -- Holy
    [258] = Enum.PowerType.Insanity,  -- Shadow
  },
  SHAMAN = {
    [262] = Enum.PowerType.Maelstrom, -- Elemental
    [263] = "MAELSTROM_WEAPON",       -- Enhancement (buff 344179, stacks 0-10)
    [264] = Enum.PowerType.Mana,      -- Restoration
  },
}

---------------------------------------------------------------------------
-- Druide : la ressource depend de la forme (GetShapeshiftFormID)
-- Construit au premier appel quand les constantes Blizzard sont dispo
---------------------------------------------------------------------------
local druidFormResources

local function BuildDruidTable()
  druidFormResources = {
    -- Forme caster (pas de shapeshift, formID = nil → on utilise la cle 0)
    [0] = {
      [102] = Enum.PowerType.LunarPower,  -- Balance
      [103] = Enum.PowerType.Mana,        -- Feral (en caster)
      [104] = Enum.PowerType.Mana,        -- Guardian (en caster)
      [105] = Enum.PowerType.Mana,        -- Restoration
    },
  }
  -- Formes shapeshiftees (constantes Blizzard globales)
  if DRUID_BEAR_FORM       then druidFormResources[DRUID_BEAR_FORM]      = Enum.PowerType.Rage end
  if DRUID_CAT_FORM        then druidFormResources[DRUID_CAT_FORM]       = Enum.PowerType.Energy end
  if DRUID_TREE_FORM       then druidFormResources[DRUID_TREE_FORM]      = Enum.PowerType.Mana end
  if DRUID_TRAVEL_FORM     then druidFormResources[DRUID_TRAVEL_FORM]    = Enum.PowerType.Mana end
  if DRUID_ACQUATIC_FORM   then druidFormResources[DRUID_ACQUATIC_FORM]  = Enum.PowerType.Mana end
  if DRUID_FLIGHT_FORM     then druidFormResources[DRUID_FLIGHT_FORM]    = Enum.PowerType.Mana end
  if DRUID_MOONKIN_FORM_1  then druidFormResources[DRUID_MOONKIN_FORM_1] = Enum.PowerType.LunarPower end
  if DRUID_MOONKIN_FORM_2  then druidFormResources[DRUID_MOONKIN_FORM_2] = Enum.PowerType.LunarPower end
  -- Treant Form (Tome of the Wilds, pas de constante Blizzard)
  druidFormResources[36] = Enum.PowerType.Mana
end

---------------------------------------------------------------------------
-- Utilitaire : recup le specID courant
---------------------------------------------------------------------------
local function GetCurrentSpecID()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  if not getSpec then return nil end
  local spec = getSpec()
  if not spec or not getInfo then return nil end
  local specID = getInfo(spec)
  return specID
end

---------------------------------------------------------------------------
-- Ressources speciales trackees par aura (buff/debuff)
-- Cle = identifiant string, valeur = { spellID, maxStacks }
---------------------------------------------------------------------------
ns.AuraResources = {
  MAELSTROM_WEAPON = { spellID = 344179, maxStacks = 10 },
  ICICLES          = { spellID = 205473, maxStacks = 5 },
}

-- Cache des stacks d'aura
ns.AuraStacks = {}     -- key -> number (0-N)
ns.AuraText   = {}     -- key -> string ("0"-"N")
ns.AuraPct    = {}     -- key -> number (0-100) pour l'arc

-- Lookup inverse spellID -> key, et instanceID -> key (pour tracked auras)
local spellToKey = {}
for key, def in pairs(ns.AuraResources) do
  spellToKey[def.spellID] = key
end
local trackedInstances = {}  -- auraInstanceID -> key

local pctMap = { [0]=0,[1]=10,[2]=20,[3]=30,[4]=40,[5]=50,[6]=60,[7]=70,[8]=80,[9]=90,[10]=100 }

local function SetAuraStacks(key, stacks)
  ns.AuraStacks[key] = stacks
  ns.AuraText[key]   = tostring(stacks)
  ns.AuraPct[key]    = pctMap[stacks] or 100
end

-- Scan initial (hors combat, utilise l'API classique)
function ns.ScanAuraStacks()
  for key, def in pairs(ns.AuraResources) do
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, def.spellID)
    if ok and auraData then
      local stacks = auraData.applications or 0
      if stacks == 0 then stacks = 1 end
      SetAuraStacks(key, stacks)
      -- Tracker l'instanceID pour les updates futures
      if auraData.auraInstanceID then
        trackedInstances[auraData.auraInstanceID] = key
      end
    else
      SetAuraStacks(key, 0)
    end
  end
end

-- Traite le payload de UNIT_AURA (pas d'appel API, donnees directes)
function ns.HandleUnitAura(updateInfo)
  if not updateInfo then return false end
  local changed = false

  -- Full update : re-scan complet
  if updateInfo.isFullUpdate then
    ns.ScanAuraStacks()
    return true
  end

  -- Nouvelles auras ajoutees (donnees completes dans le payload)
  if updateInfo.addedAuras then
    for _, aura in ipairs(updateInfo.addedAuras) do
      -- Certains champs d'aura sont marques "secret" par Blizzard
      -- pcall sur tout le bloc pour eviter les erreurs d'acces
      local ok, key, stacks, instID = pcall(function()
        local sid = aura.spellId
        if not sid or type(sid) ~= "number" then return nil end
        local k = spellToKey[sid]
        if not k then return nil end
        local s = aura.applications or 0
        if s == 0 then s = 1 end
        return k, s, aura.auraInstanceID
      end)
      if ok and key then
        SetAuraStacks(key, stacks)
        if instID then
          trackedInstances[instID] = key
        end
        changed = true
      end
    end
  end

  -- Auras mises a jour (stacks change)
  if updateInfo.updatedAuraInstanceIDs then
    for _, instanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
      local key = trackedInstances[instanceID]
      if key then
        -- Essayer de lire les donnees mises a jour
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceID)
        if ok and aura then
          local stacks = aura.applications or 0
          if stacks == 0 then stacks = 1 end
          SetAuraStacks(key, stacks)
        end
        changed = true
      end
    end
  end

  -- Auras retirees
  if updateInfo.removedAuraInstanceIDs then
    for _, instanceID in ipairs(updateInfo.removedAuraInstanceIDs) do
      local key = trackedInstances[instanceID]
      if key then
        SetAuraStacks(key, 0)
        trackedInstances[instanceID] = nil
        changed = true
      end
    end
  end

  return changed
end

---------------------------------------------------------------------------
-- API publique : detecte la ressource primaire du joueur
-- Retourne un Enum.PowerType ou un string pour les ressources aura
---------------------------------------------------------------------------
function ns.GetPlayerResource()
  local _, playerClass = UnitClass("player")
  if not playerClass then return Enum.PowerType.Mana end

  -- Druide : traitement special par forme
  if playerClass == "DRUID" then
    if not druidFormResources then BuildDruidTable() end
    local formID = GetShapeshiftFormID()
    local resource = druidFormResources[formID or 0]
    if type(resource) == "table" then
      -- Table par specID (forme caster)
      local specID = GetCurrentSpecID()
      return (specID and resource[specID]) or Enum.PowerType.Mana
    end
    return resource or Enum.PowerType.Mana
  end

  -- Autres classes
  local resource = classPrimaryResource[playerClass]
  if type(resource) == "table" then
    -- Table par specID
    local specID = GetCurrentSpecID()
    return (specID and resource[specID]) or Enum.PowerType.Mana
  end
  return resource or Enum.PowerType.Mana
end

---------------------------------------------------------------------------
-- Couleurs par type de ressource
-- Utilisees pour colorer les arcs, le texte et les dots du cercle
---------------------------------------------------------------------------
ns.ResourceTypeColors = {
  [Enum.PowerType.Mana] = {
    bar  = { 0, 0.55, 1, 1 },
    text = { 0, 0.69, 1, 1 },
    dots = {
      { 0, 0.40, 0.70 },
      { 0, 0.55, 0.85 },
      { 0, 0.69, 1.00 },
      { 0, 0.55, 0.85 },
      { 0, 0.40, 0.70 },
    },
  },
  [Enum.PowerType.Rage] = {
    bar  = { 0.9, 0.1, 0.1, 1 },
    text = { 1, 0.2, 0.2, 1 },
    dots = {
      { 0.60, 0.00, 0.00 },
      { 0.80, 0.10, 0.05 },
      { 1.00, 0.20, 0.10 },
      { 0.80, 0.10, 0.05 },
      { 0.60, 0.00, 0.00 },
    },
  },
  [Enum.PowerType.Focus] = {
    bar  = { 0.9, 0.45, 0.2, 1 },
    text = { 1, 0.5, 0.25, 1 },
    dots = {
      { 0.70, 0.30, 0.10 },
      { 0.85, 0.40, 0.15 },
      { 1.00, 0.50, 0.25 },
      { 0.85, 0.40, 0.15 },
      { 0.70, 0.30, 0.10 },
    },
  },
  [Enum.PowerType.Energy] = {
    bar  = { 0.9, 0.9, 0, 1 },
    text = { 1, 1, 0, 1 },
    dots = {
      { 0.70, 0.70, 0.00 },
      { 0.85, 0.85, 0.00 },
      { 1.00, 1.00, 0.00 },
      { 0.85, 0.85, 0.00 },
      { 0.70, 0.70, 0.00 },
    },
  },
  [Enum.PowerType.RunicPower] = {
    bar  = { 0, 0.7, 0.9, 1 },
    text = { 0, 0.82, 1, 1 },
    dots = {
      { 0.00, 0.50, 0.70 },
      { 0.00, 0.65, 0.85 },
      { 0.00, 0.82, 1.00 },
      { 0.00, 0.65, 0.85 },
      { 0.00, 0.50, 0.70 },
    },
  },
  [Enum.PowerType.Fury] = {
    bar  = { 0.7, 0.2, 0.9, 1 },
    text = { 0.79, 0.26, 0.99, 1 },
    dots = {
      { 0.50, 0.10, 0.70 },
      { 0.65, 0.18, 0.85 },
      { 0.79, 0.26, 0.99 },
      { 0.65, 0.18, 0.85 },
      { 0.50, 0.10, 0.70 },
    },
  },
  [Enum.PowerType.Insanity] = {
    bar  = { 0.5, 0.1, 0.8, 1 },
    text = { 0.6, 0.15, 0.9, 1 },
    dots = {
      { 0.35, 0.05, 0.55 },
      { 0.47, 0.10, 0.72 },
      { 0.60, 0.15, 0.90 },
      { 0.47, 0.10, 0.72 },
      { 0.35, 0.05, 0.55 },
    },
  },
  [Enum.PowerType.Maelstrom] = {
    bar  = { 0, 0.4, 0.9, 1 },
    text = { 0, 0.5, 1, 1 },
    dots = {
      { 0.00, 0.30, 0.70 },
      { 0.00, 0.40, 0.85 },
      { 0.00, 0.50, 1.00 },
      { 0.00, 0.40, 0.85 },
      { 0.00, 0.30, 0.70 },
    },
  },
  [Enum.PowerType.LunarPower] = {
    bar  = { 0.25, 0.45, 0.85, 1 },
    text = { 0.3, 0.52, 0.9, 1 },
    dots = {
      { 0.15, 0.30, 0.60 },
      { 0.22, 0.41, 0.75 },
      { 0.30, 0.52, 0.90 },
      { 0.22, 0.41, 0.75 },
      { 0.15, 0.30, 0.60 },
    },
  },
  -- Ressources speciales (string keys)
  MAELSTROM_WEAPON = {
    bar  = { 0, 0.5, 1, 1 },
    text = { 0, 0.6, 1, 1 },
    dots = {
      { 0.00, 0.35, 0.70 },
      { 0.00, 0.45, 0.85 },
      { 0.00, 0.60, 1.00 },
      { 0.00, 0.45, 0.85 },
      { 0.00, 0.35, 0.70 },
    },
  },
  ICICLES = {
    bar  = { 0.5, 0.8, 1, 1 },
    text = { 0.6, 0.88, 1, 1 },
    dots = {
      { 0.30, 0.55, 0.75 },
      { 0.40, 0.68, 0.88 },
      { 0.60, 0.88, 1.00 },
      { 0.40, 0.68, 0.88 },
      { 0.30, 0.55, 0.75 },
    },
  },
  [Enum.PowerType.Essence] = {
    bar  = { 0.24, 0.74, 0.78, 1 },
    text = { 0.3, 0.85, 0.9, 1 },
    dots = {
      { 0.15, 0.50, 0.55 },
      { 0.20, 0.65, 0.70 },
      { 0.30, 0.85, 0.90 },
      { 0.20, 0.65, 0.70 },
      { 0.15, 0.50, 0.55 },
    },
  },
  [Enum.PowerType.SoulShards] = {
    bar  = { 0.53, 0.24, 0.78, 1 },
    text = { 0.65, 0.3, 0.9, 1 },
    dots = {
      { 0.35, 0.12, 0.50 },
      { 0.47, 0.20, 0.65 },
      { 0.65, 0.30, 0.90 },
      { 0.47, 0.20, 0.65 },
      { 0.35, 0.12, 0.50 },
    },
  },
  [Enum.PowerType.HolyPower] = {
    bar  = { 0.95, 0.85, 0.3, 1 },
    text = { 1, 0.9, 0.4, 1 },
    dots = {
      { 0.70, 0.60, 0.15 },
      { 0.85, 0.75, 0.25 },
      { 1.00, 0.90, 0.40 },
      { 0.85, 0.75, 0.25 },
      { 0.70, 0.60, 0.15 },
    },
  },
}

-- Fallback si le powerType n'a pas de couleur definie
local fallbackColors = {
  bar  = { 0.8, 0.8, 0.8, 1 },
  text = { 0.9, 0.9, 0.9, 1 },
  dots = {
    { 0.5, 0.5, 0.5 },
    { 0.65, 0.65, 0.65 },
    { 0.8, 0.8, 0.8 },
    { 0.65, 0.65, 0.65 },
    { 0.5, 0.5, 0.5 },
  },
}

function ns.GetResourceColors(powerType)
  return ns.ResourceTypeColors[powerType] or fallbackColors
end

---------------------------------------------------------------------------
-- PowerTypes qui affichent la valeur brute au lieu du %
-- fmt      = format string pour l'affichage
-- maxValue = si present, on derive la valeur depuis le pourcentage (evite secret numbers)
--            sinon on formate UnitPower directement (pas d'arithmetique)
---------------------------------------------------------------------------
ns.RawDisplayResources = {
  [Enum.PowerType.Insanity]   = { fmt = "%d" },  -- valeur brute (100 ou 150 selon talent)
  [Enum.PowerType.Essence]    = { fmt = "%d" },
  [Enum.PowerType.SoulShards] = { fmt = "%.1f", maxValue = 5 },
  [Enum.PowerType.HolyPower]  = { fmt = "%d" },
  [Enum.PowerType.Rage]       = { fmt = "%d" },
  [Enum.PowerType.Energy]     = { fmt = "%d" },
  [Enum.PowerType.Fury]       = { fmt = "%d" },
  [Enum.PowerType.Maelstrom]  = { fmt = "%d" },
  [Enum.PowerType.LunarPower] = { fmt = "%d" },
}

---------------------------------------------------------------------------
-- Ressources secondaires affichées sous le texte du cercle de ressource.
-- Clé = specID, valeur = { spellID, label, color, maxStacks }
-- Trackées via C_UnitAuras.GetPlayerAuraBySpellID (aura buff).
---------------------------------------------------------------------------
ns.SecondaryResourceDefs = {
  -- Death Knight Blood (spec 250) : Bone Shield (aura stackable)
  [250] = { spellID  = 195181, color = { 0.75, 0.88, 1.00, 1 }, maxStacks = 10 },
  -- Demon Hunter Vengeance (spec 581) : Soul Fragments via UnitPower (powerType 7)
  [581] = { powerType = 7,     color = { 0.70, 0.30, 1.00, 1 }, maxStacks = 5  },
  -- Demon Hunter Devourer (spec 1480, hero spec 12.0) : stacks de l'aura 1225789
  -- altSpellID = fragments de vide (1227702) affichés sous Métamorphose du vide
  [1480] = { spellID = 1225789, useStacks = true, altSpellID = 1227702 },
}

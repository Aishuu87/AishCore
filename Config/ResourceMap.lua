-- Config/ResourceMap.lua : Detection de la ressource primaire par classe/specialisation
-- Inspire du fonctionnement de SenseiClassResourceBar (PrimaryResourceBar.lua)
local addonName, ns = ...

-- Ressource primaire par classe (table { [specID] = ... } si variation par spec)
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

-- Druide : la ressource depend de la forme (GetShapeshiftFormID), construit au 1er appel
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

-- Utilitaire : recup le specID courant
local function GetCurrentSpecID()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  if not getSpec then return nil end
  local spec = getSpec()
  if not spec or not getInfo then return nil end
  local specID = getInfo(spec)
  return specID
end

-- Ressources speciales trackees par aura : cle = identifiant string, valeur = { spellID, maxStacks }
ns.AuraResources = {
  MAELSTROM_WEAPON = { spellID = 344179, maxStacks = 10 },
  ICICLES          = { spellID = 205473, maxStacks = 5 },
}

-- Cache des stacks d'aura
ns.AuraStacks = {}     -- key -> number (0-N)
ns.AuraText   = {}     -- key -> string ("0"-"N")
ns.AuraPct    = {}     -- key -> number (0-100) pour l'arc

local pctMap = { [0]=0,[1]=10,[2]=20,[3]=30,[4]=40,[5]=50,[6]=60,[7]=70,[8]=80,[9]=90,[10]=100 }
local HAS_ISSECRET = (type(issecretvalue) == "function")

local function SetAuraStacks(key, stacks)
  ns.AuraStacks[key] = stacks
  ns.AuraText[key]   = tostring(stacks)
  ns.AuraPct[key]    = pctMap[stacks] or 100
end

-- LECTURE DES STACKS (Secret Values, patch 12.1+) : le payload UNIT_AURA et les AuraData
-- (GetPlayerAuraBySpellID etc) sont désormais toujours secrets, illisibles directement.
-- On utilise le pattern "show but don't know" : le CDM donne le spellID en clair via le
-- hook SetAuraInstanceInfo, et GetAuraApplicationDisplayCount lit le compte affichable
-- sans exposer la donnée secrète.
-- Tier 1 : CDM (cdmData cle par spellID -> lookup O(1)). tonumber() car
-- GetAuraApplicationDisplayCount peut renvoyer une string formatee (ex: "10+").
local function GetCDMStackCount(spellID)
  local cdmPlayer = ns.Auras and ns.Auras.cdmData and ns.Auras.cdmData.player
  local cdmEntry = cdmPlayer and cdmPlayer[spellID]
  if not (cdmEntry and cdmEntry.instID) then return nil end
  local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
  if ok and disp ~= nil then return tonumber(disp) end
  return nil
end

-- Tier 2 : GetPlayerAuraBySpellID -- lookup direct par spellID (spellID est un paramètre
-- d'entrée, pas une valeur à lire puis comparer, donc pas de plantage secret comme avec
-- GetAuraDataByIndex + comparaison manuelle qui échouait toujours en combat).
local function GetPlayerAuraStackCount(spellID)
  local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
  if not ok or not auraData then return nil end
  local okApp, app = pcall(function() return auraData.applications end)
  if okApp and app ~= nil and not (HAS_ISSECRET and issecretvalue(app)) and tonumber(app) then
    return tonumber(app)
  end
  -- Fallback : applications illisible (secret en combat) -> compte affichable via l'instanceID
  local okInst, instID = pcall(function() return auraData.auraInstanceID end)
  if okInst and instID then
    local okDisp, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, instID, 1, 999)
    if okDisp and disp ~= nil and tonumber(disp) then return tonumber(disp) end
  end
  return 1  -- aura confirmee presente (auraData non-nil), compte illisible : au moins 1
end

-- Scan complet : stacks de toutes les ressources trackees via le CDM, repli sur GetPlayerAuraBySpellID
function ns.ScanAuraStacks()
  for key, def in pairs(ns.AuraResources) do
    local disp = GetCDMStackCount(def.spellID) or GetPlayerAuraStackCount(def.spellID)
    SetAuraStacks(key, disp or 0)
  end
end

-- UNIT_AURA : payload illisible (cf. ci-dessus), on redeclenche juste un scan CDM
function ns.HandleUnitAura(updateInfo)
  ns.ScanAuraStacks()
  return true
end

-- API publique : detecte la ressource primaire du joueur (Enum.PowerType ou string pour aura)
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

-- Couleurs par type de ressource (arcs, texte, dots du cercle)
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

-- PowerTypes qui affichent la valeur brute au lieu du % (maxValue = derive du % pour eviter les secret numbers)
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

-- Ressources secondaires affichées sous le texte du cercle. Clé = specID,
-- valeur = { spellID, label, color, maxStacks }. Trackées via GetPlayerAuraBySpellID.
ns.SecondaryResourceDefs = {
  -- Death Knight Blood (250) : Bone Shield (aura stackable)
  [250] = { spellID  = 195181, useStacks = true, color = { 0.75, 0.88, 1.00, 1 }, maxStacks = 10 },
  -- Demon Hunter Vengeance (581) : Soul Fragments. spellID=203981 n'est pas une aura a stacks
  -- classique (introuvable via GetPlayerAuraBySpellID) -- castCountSpellID (Spirit Bomb, 247454)
  -- sert de repli, son compteur de charges reflete le nombre de fragments.
  [581] = { spellID = 203981, useStacks = true, castCountSpellID = 247454,
            color = { 0.70, 0.30, 1.00, 1 }, maxStacks = 5 },
  -- Demon Hunter Devourer (1480) : stacks de l'aura 1225789, altSpellID = fragments de vide (1227702)
  [1480] = { spellID = 1225789, useStacks = true, altSpellID = 1227702, maxStacks = 50 },
  -- Warrior Protection (73) : Dur Au Mal (190456), montant d'absorption restant
  [73] = { spellID = 190456, useAbsorb = true, color = { 0.78, 0.25, 0.25, 1 } },
  -- Monk Mistweaver (270) : Thé de Mana (115867) introuvable en combat -- castCountSpellID
  -- (115294, sort activable) sert de repli via ApplyCastCountToText
  [270] = { spellID = 115867, useStacks = true, castCountSpellID = 115294,
            color = { 0.25, 0.85, 0.55, 1 }, maxStacks = 20 },
  -- Mage Givre (64) : debuff de la CIBLE (useTargetDebuff bascule sur ApplyTargetStacksToText)
  [64] = { spellID = 1221389, useTargetDebuff = true, color = { 0.55, 0.85, 1.00, 1 } },
  -- Warlock Démonologie (266) : stacks de Cœur Démoniaque (264173, buff joueur stackable)
  [266] = { spellID = 264173, useStacks = true, color = { 0.53, 0.53, 0.93, 1 } },
}

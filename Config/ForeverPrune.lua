-- Config/ForeverPrune.lua : Forever n'a ni Chevalier de la mort, ni Chasseur de demons, ni Moine, ni
-- Evocateur. On retire leurs donnees des profils (couleurs, barre de rotation, cercle de ressource, listes
-- d'auras...) et des templates charges en memoire, pour alleger les SavedVariables et les copies de profil.
-- Idempotent : rejoue a chaque connexion, ne touche que les classes absentes. Sans effet sur Retail.
local addonName, ns = ...
if not ns.IsForever then return end

local ABSENT_CLASS = { DEATHKNIGHT = true, DEMONHUNTER = true, MONK = true, EVOKER = true }
local ABSENT_SPEC = {
  [250] = true, [251] = true, [252] = true,      -- Chevalier de la mort
  [577] = true, [581] = true, [1480] = true,     -- Chasseur de demons
  [268] = true, [269] = true, [270] = true,      -- Moine
  [1467] = true, [1468] = true, [1473] = true,   -- Evocateur
}

-- Table dont les cles sont "CLASSE_..." : retire celles des classes absentes
local function PruneClassPrefixed(t)
  if type(t) ~= "table" then return end
  for k in pairs(t) do
    if type(k) == "string" then
      local cls = k:match("^(.-)_")
      if cls and ABSENT_CLASS[cls] then t[k] = nil end
    end
  end
end

-- Sorts / auras retail inexistants sur Forever : un ID que le client ne connait pas (pas de nom) ne vaut rien.
-- Garde-fou : sans API ou si un sort de reference (Boule de feu, 133) n'est pas resolu, on ne touche a rien.
local function SpellKnownToClient(id)
  local ok, name = pcall(C_Spell.GetSpellName, id)
  return ok and name ~= nil
end
local function CanPruneSpells()
  return C_Spell and C_Spell.GetSpellName and SpellKnownToClient(133)
end

local function FilterIDList(list)
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do
    local id = list[i]
    if type(id) == "number" and not SpellKnownToClient(id) then table.remove(list, i) end
  end
end

-- Barre de rotation : slotsBySpec[cle] = { [nomSlot] = { spellIDs = {...} } } (ou ancien format tableau)
local function PruneRotationSpells(pb)
  local t = pb.slotsBySpec
  if type(t) ~= "table" then return end
  for _, perSpec in pairs(t) do
    if type(perSpec) == "table" then
      for _, slot in pairs(perSpec) do
        if type(slot) == "table" then FilterIDList(slot.spellIDs) end
      end
    end
  end
end

-- Auras a tracker : discoveredSpells[cle][spellID] = info
local function PruneDiscovered(ds)
  if type(ds) ~= "table" then return end
  for _, specSpells in pairs(ds) do
    if type(specSpells) == "table" then
      for sid in pairs(specSpells) do
        if type(sid) == "number" and not SpellKnownToClient(sid) then specSpells[sid] = nil end
      end
    end
  end
end

-- Un profil AishCore ou Auras (table de reglages), ou un template
local function PruneProfile(p)
  if type(p) ~= "table" then return end
  -- Couleurs thematiques : cles de classe en minuscules
  local col = p.colors
  if type(col) == "table" then
    for _, name in ipairs({ "overrides", "defaultSpec" }) do
      local t = col[name]
      if type(t) == "table" then
        for cls in pairs(ABSENT_CLASS) do t[cls:lower()] = nil end
      end
    end
  end
  -- Barre de rotation : tables par specID
  local pb = p.priorityBar
  if type(pb) == "table" then
    for _, name in ipairs({ "slotsBySpec", "layoutBySpec" }) do
      local t = pb[name]
      if type(t) == "table" then
        for id in pairs(ABSENT_SPEC) do t[id] = nil end
      end
    end
  end
  -- Cercle de ressource : reglages par spe "secRes_<specID>_<cle>"
  local rc = p.resourceCircle
  if type(rc) == "table" then
    for k in pairs(rc) do
      if type(k) == "string" then
        local id = k:match("^secRes_(%d+)_")
        if id and ABSENT_SPEC[tonumber(id)] then rc[k] = nil end
      end
    end
  end
  -- Auras : listes et glow par defaut, cles "CLASSE_SPE"
  PruneClassPrefixed(p.discoveredSpells)
  PruneClassPrefixed(p.defaultGlowBySpec)
  if CanPruneSpells() then
    if type(p.priorityBar) == "table" then PruneRotationSpells(p.priorityBar) end
    PruneDiscovered(p.discoveredSpells)
  end
end
ns.PruneAbsentClassData = PruneProfile

-- Template charge en memoire (copie a chaque creation de profil)
PruneProfile(ns.ProfileTemplate)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  -- Profils AishCore sauvegardes
  if AishaddonDB and type(AishaddonDB._profiles) == "table" then
    for _, prof in pairs(AishaddonDB._profiles) do PruneProfile(prof) end
  end
  -- Auras : profils, registre de decouvertes du compte, template, table des specs
  if AishUIAuraDB then
    if type(AishUIAuraDB.profiles) == "table" then
      for _, prof in pairs(AishUIAuraDB.profiles) do PruneProfile(prof) end
    end
    PruneClassPrefixed(AishUIAuraDB.discovery)
    -- Liste partagee du compte (ns.db), hors profils
    if CanPruneSpells() then PruneDiscovered(AishUIAuraDB.discoveredSpells) end
  end
  local A = ns.Auras
  if A then
    PruneProfile(A.ProfileTemplate)
    if type(A.SPEC_MAP) == "table" then
      for id, m in pairs(A.SPEC_MAP) do
        if type(m) == "table" and ABSENT_CLASS[m.class] then A.SPEC_MAP[id] = nil end
      end
    end
  end
end)

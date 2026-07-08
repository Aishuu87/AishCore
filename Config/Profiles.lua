---------------------------------------------------------------------------
-- Config/Profiles.lua
-- Système de profils Aishaddon :
--   • Profils nommés multiples (CRUD complet)
--   • Liaison par personnage optionnelle
--   • Sérialisation texte (export / import / partage Patreon)
--   • Zero breaking-change : ns.DB pointe toujours sur le profil actif
---------------------------------------------------------------------------
local addonName, ns = ...
local L = ns.L

ns.Profiles = {}
local P = ns.Profiles

---------------------------------------------------------------------------
-- Helpers internes
---------------------------------------------------------------------------

local function CharKey()
  local name  = UnitName("player")  or "Unknown"
  local realm = GetRealmName()       or "Unknown"
  return name .. "-" .. realm
end

local function SafeApply(mod, label)
  if mod and mod.ApplySettings then
    local ok, err = pcall(mod.ApplySettings)
    if not ok then
      print(string.format(L["PROFILE_APPLY_SETTINGS_ERROR"], label, tostring(err)))
    end
  end
end

local function ApplyAllSettings()
  local M = ns.Modules
  SafeApply(M.ResourceCircle,            "ResourceCircle")
  SafeApply(M.HealthCircle,              "HealthCircle")
  SafeApply(M.OutOfCombatResourceCircle, "OutOfCombatResourceCircle")
  SafeApply(M.RotationHelper,            "RotationHelper")
  SafeApply(M.PriorityBar,               "PriorityBar")
  SafeApply(M.XPBar,                     "XPBar")
  SafeApply(M.UnitBars,                  "UnitBars")
  SafeApply(M.CastBar,                   "CastBar")
  SafeApply(M.TopTargetBar,              "TopTargetBar")
  SafeApply(M.Skyriding,                 "Skyriding")
  SafeApply(M.Colors,                    "Colors")
end

---------------------------------------------------------------------------
-- Sérialisation (table Lua → chaîne texte)
-- Produit un constructeur de table pur (nombres, chaînes, booléens, tables).
-- L'import utilise load() dans un environnement vide pour sécuriser la lecture.
---------------------------------------------------------------------------

local function Serialize(val, depth)
  depth = depth or 0
  local t = type(val)
  if t == "number" then
    -- Garde NaN/inf contre les configs corrompues
    if val ~= val or val == math.huge or val == -math.huge then return "0" end
    -- Utilise le format %.10g pour minimiser la perte de précision flottante
    return string.format("%.10g", val)
  elseif t == "boolean" then
    return tostring(val)
  elseif t == "string" then
    return string.format("%q", val)
  elseif t == "table" then
    if depth > 24 then return "{}" end
    local parts = {}
    -- Partie array (indices 1..n contigus)
    local maxn = 0
    for k in pairs(val) do
      if type(k) == "number" and k == math.floor(k) and k >= 1 then
        if k > maxn then maxn = k end
      end
    end
    -- Vérifier la contigüité
    local isArray = true
    for i = 1, maxn do
      if val[i] == nil then isArray = false; break end
    end
    if isArray then
      for i = 1, maxn do
        parts[#parts + 1] = Serialize(val[i], depth + 1)
      end
    else
      maxn = 0
    end
    -- Hash part
    for k, v in pairs(val) do
      local skip = isArray and type(k) == "number" and k == math.floor(k) and k >= 1 and k <= maxn
      if not skip then
        if type(k) == "string" then
          if k:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
            parts[#parts + 1] = k .. "=" .. Serialize(v, depth + 1)
          else
            parts[#parts + 1] = "[" .. string.format("%q", k) .. "]=" .. Serialize(v, depth + 1)
          end
        elseif type(k) == "number" then
          parts[#parts + 1] = "[" .. tostring(k) .. "]=" .. Serialize(v, depth + 1)
        end
        -- clés de type function, userdata, thread → ignorées silencieusement
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

local function Deserialize(str)
  if type(str) ~= "string" then return nil, L["PROFILE_DESERIALIZE_NOT_STRING"] end
  -- loadstring() : API Lua 5.1 disponible dans WoW (load() 4-args non garanti)
  local fn, err = loadstring("return " .. str, "aishaddon_profile_import")
  if not fn then return nil, tostring(err) end
  local ok, result = pcall(fn)
  if not ok then return nil, tostring(result) end
  if type(result) ~= "table" then return nil, L["PROFILE_DESERIALIZE_NOT_TABLE"] end
  return result
end

---------------------------------------------------------------------------
-- VERSION marker dans les exports
---------------------------------------------------------------------------
local EXPORT_PREFIX = "AISHADDON_PROFILE_V1:"

---------------------------------------------------------------------------
-- InitDB — appelé par LoadDatabase() dans Aishaddon.lua
-- Remplace l'ancien code « ns.DB = ns.MergeDefaults(AishaddonDB, ns.Defaults) »
---------------------------------------------------------------------------
function P.InitDB()
  AishaddonDB = AishaddonDB or {}
  local root = AishaddonDB

  --------------------------------------------------------------------------
  -- Migration : ancien format plat → format à profils
  --------------------------------------------------------------------------
  if not root._profiles then
    local legacy = {}
    -- Récupère toutes les clés de config (non-underscore)
    for k, v in pairs(root) do
      if type(k) == "string" and not k:find("^_") then
        legacy[k] = v
      end
    end
    -- Efface les clés de config du niveau racine
    for k in pairs(legacy) do root[k] = nil end

    root._profiles      = { ["Default"] = legacy }
    root._globalProfile = "Default"
    root._charProfiles  = {}
    root._version       = 1
  end

  --------------------------------------------------------------------------
  -- Garantir l'existence du profil "Default"
  --------------------------------------------------------------------------
  if not root._profiles["Default"] then
    root._profiles["Default"] = {}
  end

  --------------------------------------------------------------------------
  -- Déterminer le profil actif
  --------------------------------------------------------------------------
  local charKey    = CharKey()
  local activeName = (root._charProfiles and root._charProfiles[charKey])
                  or root._globalProfile
                  or "Default"

  -- Fallback si le profil n'existe plus
  if not root._profiles[activeName] then
    activeName = "Default"
    if root._charProfiles and root._charProfiles[charKey] then
      root._charProfiles[charKey] = nil
    end
    root._globalProfile = "Default"
  end

  --------------------------------------------------------------------------
  -- Migration v2 : normaliser tous les profils créés avant les nouvelles
  -- valeurs par défaut (useClassDefaults=true, slotsBySpec vide).
  -- MergeDefaults ne touche pas les clés déjà présentes, donc on corrige
  -- explicitement les profils dont les overrides sont encore vides et qui
  -- ont useClassDefaults=false (état "avant changement de Defaults").
  -- Gardé par _migratedV2 pour ne s'exécuter qu'une seule fois.
  --------------------------------------------------------------------------
  if not root._migratedV2 then
  for _, prof in pairs(root._profiles) do
    -- Colors : si pas d'overrides (table vide ou absente) → forcer mode classe
    local col = prof.colors
    if col then
      local ovEmpty = true
      if type(col.overrides) == "table" then
        for _ in pairs(col.overrides) do ovEmpty = false; break end
      end
      if ovEmpty and col.useClassDefaults == false then
        col.useClassDefaults = true
      end
    end
    -- PriorityBar : migration sideOffset V2 (ancre bord externe au lieu du centre).
    -- Formule : new = old + iconSpacing/2 + iconSize/2
    local pb = prof.priorityBar
    if pb and type(pb.sideOffset) == "number" and not pb._sideOffsetV2 then
      local size    = type(pb.iconSize)    == "number" and pb.iconSize    or 34
      local spacing = type(pb.iconSpacing) == "number" and pb.iconSpacing or 6
      pb.sideOffset = math.floor(pb.sideOffset + spacing / 2 + size / 2 + 0.5)
      pb._sideOffsetV2 = true
    end
    -- PriorityBar : migration loopGlowIndex après insertion de "Aucun" à l'index 1.
    -- Avant ce changement il n'existait pas d'index "Aucun" : tous les index
    -- stockés doivent être décalés de +1 (sauf si la migration a déjà eu lieu).
    if pb and pb.loopGlowIndex and not pb._loopGlowTypeMigrated then
      if type(pb.loopGlowIndex) == "number" then
        pb.loopGlowIndex = pb.loopGlowIndex + 1
      end
      pb._loopGlowTypeMigrated = true
    end
    -- SpellEffects : retirer les deux spells résiduels des anciens Defaults
    -- (8004 = Afflux de soins, 17364 = Coup éclair) qui ont été copiés dans
    -- tous les profils créés avant ce nettoyage.
    local se = prof.spellEffects
    if se and type(se.spells) == "table" then
      se.spells[8004]  = nil
      se.spells[17364] = nil
    end
  end
  root._migratedV2 = true
  end -- if not root._migratedV2

  --------------------------------------------------------------------------
  -- Pointer ns.DB sur le profil actif (merge defaults)
  --------------------------------------------------------------------------
  root._profiles[activeName] = ns.MergeDefaults(root._profiles[activeName], ns.Defaults)
  ns.DB                 = root._profiles[activeName]
  ns._activeProfileName = activeName
  ns._charKey           = charKey
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------

--- Retourne la liste triée des noms de profils.
function P.List()
  local names = {}
  for k in pairs(AishaddonDB._profiles) do
    names[#names + 1] = k
  end
  table.sort(names)
  return names
end

--- Nom du profil actif.
function P.GetActive()
  return ns._activeProfileName or "Default"
end

--- Retourne le nom du profil lié au personnage courant (ou nil).
function P.GetCharBinding()
  local root = AishaddonDB
  return root._charProfiles and root._charProfiles[ns._charKey or ""]
end

--- Active un profil (global + applique les settings).
function P.SetActive(name)
  local root = AishaddonDB
  if not root._profiles[name] then return false, string.format(L["PROFILE_NOT_FOUND_NAMED"], tostring(name)) end

  root._profiles[name] = ns.MergeDefaults(root._profiles[name], ns.Defaults)
  ns.DB                 = root._profiles[name]
  ns._activeProfileName = name
  root._globalProfile   = name

  -- Mettre à jour la liaison per-char si elle pointait sur l'ancien profil
  if root._charProfiles and root._charProfiles[ns._charKey or ""] then
    root._charProfiles[ns._charKey] = name
  end

  ApplyAllSettings()
  ns.CallbackRegistry:Trigger("PROFILE_CHANGED", name)
  -- Broadcast différé : garantit que les couleurs sont bien appliquées APRES
  -- que tous les callbacks PROFILE_CHANGED ont fini (notamment le rebuild GUI
  -- qui peut remélanger ns.DB via MergeDefaults).
  C_Timer.After(0, function()
    local CLR = ns.Modules and ns.Modules.Colors
    if CLR and CLR.Broadcast then CLR.Broadcast() end
  end)
  return true
end

--- Lie ce personnage à un profil spécifique.
function P.SetCharProfile(name)
  local root = AishaddonDB
  if not root._profiles[name] then return false, L["PROFILE_NOT_FOUND"] end
  root._charProfiles = root._charProfiles or {}
  root._charProfiles[ns._charKey or ""] = name
  P.SetActive(name)
  return true
end

--- Retire la liaison per-char du personnage courant (retombe sur _globalProfile).
function P.ClearCharProfile()
  local root = AishaddonDB
  root._charProfiles = root._charProfiles or {}
  root._charProfiles[ns._charKey or ""] = nil
  P.SetActive(root._globalProfile or "Default")
end

--- Crée un nouveau profil.
---   copyFrom : nom du profil source (nil = copie des Defaults)
function P.Create(name, copyFrom)
  if type(name) ~= "string" then return false, L["PROFILE_NAME_INVALID"] end
  name = name:match("^%s*(.-)%s*$")
  if name == "" then return false, L["PROFILE_NAME_EMPTY"] end

  local root = AishaddonDB
  if root._profiles[name] then return false, string.format(L["PROFILE_ALREADY_EXISTS_NAMED"], name) end

  if copyFrom and root._profiles[copyFrom] then
    root._profiles[name] = ns.DeepCopy(root._profiles[copyFrom])
  else
    -- Partir du template de référence (profil neutre pré-configuré), puis combler
    -- toute clé absente avec ns.Defaults (nouvelles options ajoutées après la création
    -- du template).
    local base = ns.ProfileTemplate and ns.DeepCopy(ns.ProfileTemplate) or {}
    root._profiles[name] = ns.MergeDefaults(base, ns.Defaults)
  end

  ns.CallbackRegistry:Trigger("PROFILE_LIST_CHANGED")
  return true
end

--- Supprime un profil (impossible si c'est le dernier ou le profil actif).
function P.Delete(name)
  local root = AishaddonDB
  if not root._profiles[name] then return false, L["PROFILE_NOT_FOUND"] end

  local count = 0
  for _ in pairs(root._profiles) do count = count + 1 end
  if count <= 1 then return false, L["PROFILE_CANNOT_DELETE_LAST"] end

  if name == (ns._activeProfileName or "Default") then
    return false, L["PROFILE_CANNOT_DELETE_ACTIVE"]
  end

  root._profiles[name] = nil
  -- Nettoyer les liaisons per-char qui pointaient dessus
  if root._charProfiles then
    for charK, pName in pairs(root._charProfiles) do
      if pName == name then root._charProfiles[charK] = nil end
    end
  end
  if root._globalProfile == name then root._globalProfile = "Default" end

  ns.CallbackRegistry:Trigger("PROFILE_LIST_CHANGED")
  return true
end

--- Renomme un profil.
function P.Rename(oldName, newName)
  if type(newName) ~= "string" then return false, L["PROFILE_NAME_INVALID"] end
  newName = newName:match("^%s*(.-)%s*$")
  if newName == "" then return false, L["PROFILE_NAME_EMPTY"] end

  local root = AishaddonDB
  if not root._profiles[oldName] then return false, L["PROFILE_NOT_FOUND"] end
  if root._profiles[newName]     then return false, L["PROFILE_NAME_ALREADY_EXISTS"] end

  root._profiles[newName] = root._profiles[oldName]
  root._profiles[oldName] = nil

  if root._globalProfile == oldName then root._globalProfile = newName end
  if root._charProfiles then
    for charK, pName in pairs(root._charProfiles) do
      if pName == oldName then root._charProfiles[charK] = newName end
    end
  end
  if ns._activeProfileName == oldName then
    ns._activeProfileName = newName
    ns.DB = root._profiles[newName]
  end

  ns.CallbackRegistry:Trigger("PROFILE_LIST_CHANGED")
  return true
end

--- Réinitialise un profil aux valeurs par défaut (même logique que Create).
function P.Reset(name)
  local root = AishaddonDB
  if not root._profiles[name] then return false, L["PROFILE_NOT_FOUND"] end

  local base = ns.ProfileTemplate and ns.DeepCopy(ns.ProfileTemplate) or {}
  root._profiles[name] = ns.MergeDefaults(base, ns.Defaults)
  if name == (ns._activeProfileName or "Default") then
    ns.DB = root._profiles[name]
    ApplyAllSettings()
  end

  ns.CallbackRegistry:Trigger("PROFILE_LIST_CHANGED")
  return true
end

--- Exporte un profil en chaîne texte (prefix + Lua table literal).
function P.Export(name)
  local root = AishaddonDB
  local data = root._profiles[name]
  if not data then return nil, L["PROFILE_NOT_FOUND"] end
  return EXPORT_PREFIX .. Serialize(data)
end

--- Importe un profil depuis une chaîne texte exportée.
---   str     : chaîne issue de Export()
---   newName : nom à donner au nouveau profil
function P.Import(str, newName)
  if type(str) ~= "string" then return false, L["PROFILE_STRING_INVALID"] end

  -- Tolérance aux espaces/retours à la ligne en début/fin
  str = str:match("^%s*(.-)%s*$")

  local payload = str:match("^" .. EXPORT_PREFIX .. "(.+)$")
  if not payload then
    return false, string.format(L["PROFILE_IMPORT_FORMAT_UNRECOGNIZED"], EXPORT_PREFIX)
  end

  if type(newName) ~= "string" then return false, L["PROFILE_DEST_NAME_INVALID"] end
  newName = newName:match("^%s*(.-)%s*$")
  if newName == "" then return false, L["PROFILE_DEST_NAME_EMPTY"] end

  local root = AishaddonDB
  if root._profiles[newName] then
    return false, string.format(L["PROFILE_ALREADY_EXISTS_NAMED"], newName)
  end

  local data, err = Deserialize(payload)
  if not data then return false, string.format(L["PROFILE_IMPORT_READ_ERROR"], tostring(err)) end

  -- Merge defaults pour combler les clés manquantes
  root._profiles[newName] = ns.MergeDefaults(data, ns.Defaults)

  ns.CallbackRegistry:Trigger("PROFILE_LIST_CHANGED")
  return true
end

---------------------------------------------------------------------------
-- CopyFrom — écrase le profil actif avec une copie du profil source
---------------------------------------------------------------------------
function P.CopyFrom(sourceName)
  local root = AishaddonDB
  if not root._profiles[sourceName] then return false, L["PROFILE_SOURCE_NOT_FOUND"] end
  local active = ns._activeProfileName or "Default"
  if sourceName == active then return false, L["PROFILE_SOURCE_DEST_IDENTICAL"] end

  root._profiles[active] = ns.MergeDefaults(ns.DeepCopy(root._profiles[sourceName]), ns.Defaults)
  ns.DB = root._profiles[active]
  ApplyAllSettings()
  ns.CallbackRegistry:Trigger("PROFILE_CHANGED", active)
  return true
end

---------------------------------------------------------------------------
-- Profils de spécialisation  (stockés dans AishaddonDB._specProfiles)
-- Structure : { enabled = bool, [specID] = profileName, ... }
---------------------------------------------------------------------------
function P.GetSpecProfilesEnabled()
  local sp = AishaddonDB._specProfiles
  return sp ~= nil and sp.enabled == true
end

function P.SetSpecProfilesEnabled(val)
  AishaddonDB._specProfiles = AishaddonDB._specProfiles or {}
  AishaddonDB._specProfiles.enabled = val and true or false
end

function P.GetSpecProfile(specID)
  local sp = AishaddonDB._specProfiles
  return sp and sp[specID]
end

function P.SetSpecProfile(specID, profileName)
  AishaddonDB._specProfiles = AishaddonDB._specProfiles or {}
  AishaddonDB._specProfiles[specID] = profileName
end

---------------------------------------------------------------------------
-- Basculement automatique lors d'un changement de spécialisation
---------------------------------------------------------------------------
local function ApplySpecProfile()
  if not P.GetSpecProfilesEnabled() then return end
  local specIndex = GetSpecialization()
  if not specIndex then return end
  local specID = GetSpecializationInfo(specIndex)
  if not specID then return end
  local targetProfile = P.GetSpecProfile(specID)
  if targetProfile and targetProfile ~= P.GetActive() then
    local root = AishaddonDB
    if root._profiles[targetProfile] then
      P.SetActive(targetProfile)
    end
  end
end
P.ApplySpecProfile = ApplySpecProfile

local specEventFrame = CreateFrame("Frame")
specEventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
specEventFrame:RegisterEvent("PLAYER_LOGIN")
specEventFrame:SetScript("OnEvent", function(_, event)
  ApplySpecProfile()
  ns.CallbackRegistry:Trigger("SPEC_CHANGED")
end)

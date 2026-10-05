-- Config/Profiles.lua : profils nommés (CRUD), liaison par personnage, export/import texte
local addonName, ns = ...
local L = ns.L

ns.Profiles = {}
local P = ns.Profiles

-- Helpers internes

-- Profils du module Auras (AishUIAuraDB, cf. Modules/Auras/Core/Profiles.lua) : liés par NOM au profil
-- AishCore, chaque opération ci-dessous est répercutée dessus. nil tant que le module n'est pas chargé.
local function AurasProfiles()
  return ns.Auras and ns.Auras.Profiles
end

local function CharKey()
  local name  = UnitName("player")  or "Unknown"
  local realm = GetRealmName()       or "Unknown"
  return name .. "-" .. realm
end

-- Polices fournies par un addon absent mais aussi livrées par un autre : un profil créé sous ElvUI
-- pointe vers la copie de WindTools, absente chez qui utilise Ellesmere. On redirige seulement si le
-- dossier d'origine manque (un addon désactivé garde ses fichiers lisibles) et que la cible existe.
local FONT_ALIASES = {
  { from = "Interface\\AddOns\\ElvUI_WindTools\\Media\\Fonts\\Montserrat.ttf", fromAddon = "ElvUI_WindTools",
    to   = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-Bold.ttf", toAddon   = "SharedMedia_MyMedia" },
}

function ns.RemapFontAliases(tbl)
  if type(tbl) ~= "table" or not (C_AddOns and C_AddOns.DoesAddOnExist) then return end
  local map
  for _, a in ipairs(FONT_ALIASES) do
    if not C_AddOns.DoesAddOnExist(a.fromAddon) and C_AddOns.DoesAddOnExist(a.toAddon) then
      map = map or {}
      map[a.from:lower()] = a.to
    end
  end
  if not map then return end
  local seen = {}
  local function Walk(t)
    if seen[t] then return end
    seen[t] = true
    for k, v in pairs(t) do
      if type(v) == "table" then Walk(v)
      elseif type(v) == "string" and map[v:lower()] then t[k] = map[v:lower()] end
    end
  end
  Walk(tbl)
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

-- Sérialisation (table Lua → chaîne texte). L'import utilise load() en environnement vide.

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
  local fn, err = loadstring("return " .. str, "aishcore_profile_import")
  if not fn then return nil, tostring(err) end
  local ok, result = pcall(fn)
  if not ok then return nil, tostring(result) end
  if type(result) ~= "table" then return nil, L["PROFILE_DESERIALIZE_NOT_TABLE"] end
  return result
end

-- VERSION marker dans les exports
local EXPORT_PREFIX = "AISHCORE_PROFILE_V1:"
local LEGACY_EXPORT_PREFIX = "AISHADDON_PROFILE_V1:" -- compat imports faits avant le renommage AishCore

-- InitDB — appelé par LoadDatabase() dans AishCore.lua
function P.InitDB()
  AishaddonDB = AishaddonDB or {}
  local root = AishaddonDB

  -- Migration : ancien format plat → format à profils
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

    root._profiles      = {}
    -- Installation neuve : `legacy` est vide (aucune SavedVariable a migrer). On ne cree PAS
    -- "Default" ici, sinon le bloc suivant trouverait une table -- vide, mais truthy -- et
    -- n'appliquerait jamais le template de reference.
    if next(legacy) then root._profiles["Default"] = legacy end
    root._globalProfile = "Default"
    root._charProfiles  = {}
    root._version       = 1
  end

  -- Garantir l'existence du profil "Default".
  -- Tout premier lancement : on part du template de reference, comme P.Create()/P.Reset(). Une table
  -- vide ne tombait que sur ns.Defaults (via le MergeDefaults plus bas), donc l'installation neuve
  -- n'heritait d'aucun des reglages du profil de reference -- exactement ce que le template existe
  -- pour eviter. MergeDefaults comble ensuite les cles absentes. Le test porte sur le CONTENU :
  -- un "Default" vide laisse par l'ancien chemin de migration est rattrape au prochain login.
  local defaultProfile = root._profiles["Default"]
  if type(defaultProfile) ~= "table" or next(defaultProfile) == nil then
    root._profiles["Default"] = ns.ProfileTemplate and ns.DeepCopy(ns.ProfileTemplate) or {}
  end

  -- Déterminer le profil actif
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

  -- Migration v2 : normalise les profils créés avant les nouvelles valeurs par défaut
  -- (useClassDefaults=true, slotsBySpec vide). One-shot via _migratedV2.
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
    -- PriorityBar : migration sideOffset V2 (ancre bord externe), new = old + iconSpacing/2 + iconSize/2
    local pb = prof.priorityBar
    if pb and type(pb.sideOffset) == "number" and not pb._sideOffsetV2 then
      local size    = type(pb.iconSize)    == "number" and pb.iconSize    or 34
      local spacing = type(pb.iconSpacing) == "number" and pb.iconSpacing or 6
      pb.sideOffset = math.floor(pb.sideOffset + spacing / 2 + size / 2 + 0.5)
      pb._sideOffsetV2 = true
    end
    -- PriorityBar : migration loopGlowIndex après insertion de "Aucun" à l'index 1 (décalage +1)
    if pb and pb.loopGlowIndex and not pb._loopGlowTypeMigrated then
      if type(pb.loopGlowIndex) == "number" then
        pb.loopGlowIndex = pb.loopGlowIndex + 1
      end
      pb._loopGlowTypeMigrated = true
    end
    -- SpellEffects : retirer les 2 spells résiduels des anciens Defaults (8004, 17364)
    local se = prof.spellEffects
    if se and type(se.spells) == "table" then
      se.spells[8004]  = nil
      se.spells[17364] = nil
    end
    -- AFK : l'ecran AFK n'utilise plus que les textures Blizzard. Le choix de style a disparu du
    -- panneau, donc un profil reste sur "sltheme"/"releaf-flat" n'aurait plus aucun moyen d'en
    -- sortir. On force "blizzard", en laissant "auto" tranquille pour le logo d'extension (ce
    -- n'est pas un jeu de textures tiers mais la resolution automatique par extension).
    -- crestClass est supprime : cette categorie n'a jamais eu de variante Blizzard.
    local afk = prof.afkMode
    if afk and type(afk.elements) == "table" then
      afk.elements.crestClass = nil
      for _, elem in pairs(afk.elements) do
        if type(elem) == "table" and (elem.style == "sltheme" or elem.style == "releaf-flat") then
          elem.style = "blizzard"
        end
      end
    end
  end
  root._migratedV2 = true
  end -- if not root._migratedV2

  -- Pointer ns.DB sur le profil actif (merge defaults)
  root._profiles[activeName] = ns.MergeDefaults(root._profiles[activeName], ns.Defaults)

  -- Polices introuvables : un profil cree quand une media pack (SharedMedia_MyMedia...)
  -- etait installee garde son chemin en dur. Si l'utilisateur desinstalle la media pack,
  -- SetFont() leve une erreur et interrompt la creation du frame en plein milieu
  -- (d'ou les "attempt to index field 'text' (a nil value)" en cascade). On rabat toute
  -- police non chargeable sur la police du jeu, dans TOUS les profils : le switch de profil
  -- ne doit pas ressusciter le probleme.
  if ns.SanitizeFontPaths then
    for _, prof in pairs(root._profiles) do
      ns.RemapFontAliases(prof)
      ns.SanitizeFontPaths(prof)
    end
  end
  -- Ancienne feature "CDM par spé" (remplacée par l'intégration CDM Loader, Modules/AishUISetup.lua)
  for _, prof in pairs(root._profiles) do
    prof.cdmBySpec, prof.cdmAutoApply = nil, nil
  end

  -- Purge retroactive des entrees VIDES de spellEffects.auraCombos (ancien bug de creation
  -- au simple clic dans SettingsPanel, deja corrige). One-shot PAR PROFIL.
  do
      local prof = root._profiles[activeName]
      if not prof._auraCombosCleanupV1 then
          if prof.spellEffects and prof.spellEffects.auraCombos then
              for auraID, combo in pairs(prof.spellEffects.auraCombos) do
                  if not (combo and #combo > 0) then
                      prof.spellEffects.auraCombos[auraID] = nil
                  end
              end
          end
          prof._auraCombosCleanupV1 = true
      end
  end

  ns.DB                 = root._profiles[activeName]
  ns._activeProfileName = activeName
  ns._charKey           = charKey
end

-- API publique

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

  local AP = AurasProfiles()
  if AP then AP:SetActive(name) end

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
-- Profil neuf : le Cooldown Manager de Blizzard, lui, ne se reinitialise pas tout seul -- il garde
-- la derniere disposition appliquee sur le personnage (souvent celle du pack AishUI). Ce drapeau
-- fait partir chaque spe du build "Defaut" (cf. Modules/CDMLayout.lua), pour que l'addon propose de
-- remettre le CDM tel que Blizzard le livre au lieu d'heriter d'une config sans rapport.
local function MarkCDMDefault(prof)
  if type(prof) ~= "table" then return end
  prof.cdmLayout = prof.cdmLayout or {}
  prof.cdmLayout.specs = {}
  prof.cdmLayout.defaultBuild = true
end

function P.Create(name, copyFrom)
  if type(name) ~= "string" then return false, L["PROFILE_NAME_INVALID"] end
  name = name:match("^%s*(.-)%s*$")
  if name == "" then return false, L["PROFILE_NAME_EMPTY"] end

  local root = AishaddonDB
  if root._profiles[name] then return false, string.format(L["PROFILE_ALREADY_EXISTS_NAMED"], name) end

  if copyFrom and root._profiles[copyFrom] then
    root._profiles[name] = ns.DeepCopy(root._profiles[copyFrom])
    local AP = AurasProfiles()
    if AP then AP:Copy(copyFrom, name) end
  else
    -- Partir du template de référence, combler les clés absentes avec ns.Defaults
    local base = ns.ProfileTemplate and ns.DeepCopy(ns.ProfileTemplate) or {}
    root._profiles[name] = ns.MergeDefaults(base, ns.Defaults)
    MarkCDMDefault(root._profiles[name])
    local AP = AurasProfiles()
    if AP then AP:Reset(name) end
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
  local AP = AurasProfiles()
  if AP then AP:Delete(name) end
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
  local AP = AurasProfiles()
  if AP then AP:Rename(oldName, newName) end

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
  MarkCDMDefault(root._profiles[name])
  local AP = AurasProfiles()
  if AP then AP:Reset(name) end
  if name == (ns._activeProfileName or "Default") then
    ns.DB = root._profiles[name]
    if AP then AP:SetActive(name) end
    ApplyAllSettings()
  end

  ns.CallbackRegistry:Trigger("PROFILE_LIST_CHANGED")
  return true
end

-- Export / import par éléments (arbre : Config/ProfileModules.lua). Chaîne = préfixe + LibSerialize +
-- LibDeflate + EncodeForPrint. Charge utile :
--   { v = 3, addon, date, items = { [idNœud] = true }, core = {...}, auras = {...} }
-- core / auras ne contiennent que les chemins des éléments exportés. Les formats V1 (texte Lua brut)
-- et V2 (par modules) restent lisibles à l'import, convertis en V3.
local EXPORT_PREFIX_V3 = "AISHCORE_PROFILE_V3:"
local EXPORT_PREFIX_V2 = "AISHCORE_PROFILE_V2:"
-- Niveau 9 : ~4x plus lent que 5 pour ~3 % de gain, sensible à chaque régénération de la fenêtre
local DEFLATE_LEVEL = 5

local function GetCodec()
  if not LibStub then return nil end
  local LS = LibStub("LibSerialize", true)
  local LD = LibStub("LibDeflate", true)
  if LS and LD then return LS, LD end
end

-- Chemins "a.b.c"
local function PathGet(t, path)
  for key in path:gmatch("[^.]+") do
    if type(t) ~= "table" then return nil end
    t = t[key]
  end
  return t
end

local function PathSet(t, path, value)
  local parent, last = t, nil
  for key in path:gmatch("[^.]+") do
    if last then
      if type(parent[last]) ~= "table" then
        if value == nil then return end
        parent[last] = {}
      end
      parent = parent[last]
    end
    last = key
  end
  parent[last] = value
end

local function EntryPath(e) return type(e) == "table" and e.path or e end

-- Copie une entrée de src vers dst. replace : dst perd d'abord ce que l'entrée couvre (import) ;
-- sans replace, simple ajout (construction de la charge utile, plusieurs nœuds se partagent unitBars).
local function CopyEntry(src, dst, e, replace)
  local path = EntryPath(e)
  local v = PathGet(src, path)
  if type(e) ~= "table" or not e.except then
    if v ~= nil or replace then PathSet(dst, path, ns.DeepCopy(v)) end
    return
  end
  local skip = {}
  for _, k in ipairs(e.except) do skip[k] = true end
  local d = PathGet(dst, path)
  if type(d) ~= "table" then
    if v == nil and not replace then return end
    d = {}
    PathSet(dst, path, d)
  end
  if replace then
    for k in pairs(d) do if not skip[k] then d[k] = nil end end
  end
  if type(v) == "table" then
    for k, x in pairs(v) do if not skip[k] then d[k] = ns.DeepCopy(x) end end
  end
end

-- Entrées d'un nœud pour un magasin ("core" / "auras"). misc : clés non déclarées présentes dans
-- au moins une des tables fournies.
local function NodeEntries(node, store, ...)
  if not node.misc then return node[store] or {} end
  local list, seen = {}, {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if type(t) == "table" then
      for k in pairs(t) do
        if not seen[k] and ns.IsProfileMiscKey(store, k) then seen[k] = true; list[#list + 1] = k end
      end
    end
  end
  return list
end

local function SelectedDataNodes(ids)
  local idx, out = ns.GetProfileTreeIndex(), {}
  for _, id in ipairs(ids) do
    local n = idx.byId[id]
    if n and ns.IsProfileDataNode(n) then out[#out + 1] = n end
  end
  return out
end

-- Tous les nœuds porteurs de données, dans l'ordre de l'arbre
function P.AllItemIds()
  local ids = {}
  for _, n in ipairs(ns.GetProfileTreeIndex().order) do
    if ns.IsProfileDataNode(n) then ids[#ids + 1] = n.id end
  end
  return ids
end

-- Table brute du profil Auras (complétée si actif) ; nil si le module Auras est absent
local function AurasTable(name)
  local AP = AurasProfiles()
  return AP and AP.GetProfileTable and AP:GetProfileTable(name)
end

-- [id] = true pour chaque élément dont le profil contient au moins une donnée (les autres sont grisés
-- dans les fenêtres d'export / copie, ex. "Autres réglages" quand toutes les clés sont déclarées).
function P.ProfileItemAvailability(name)
  local core = AishaddonDB._profiles[name]
  local avail = {}
  if not core then return avail end
  local auras = AurasTable(name)
  for _, n in ipairs(ns.GetProfileTreeIndex().order) do
    if ns.IsProfileDataNode(n) then
      for _, e in ipairs(NodeEntries(n, "core", core)) do
        if PathGet(core, EntryPath(e)) ~= nil then avail[n.id] = true end
      end
      if auras and not avail[n.id] then
        for _, e in ipairs(NodeEntries(n, "auras", auras)) do
          if PathGet(auras, EntryPath(e)) ~= nil then avail[n.id] = true end
        end
      end
    end
  end
  return avail
end

-- ids : nœuds à exporter (nil = tous). Retourne la charge utile V3.
function P.BuildItemsPayload(name, ids)
  local core = AishaddonDB._profiles[name]
  if not core then return nil, L["PROFILE_NOT_FOUND"] end
  local auras = AurasTable(name)
  local payload = { v = 3, items = {}, core = {}, auras = {} }
  for _, n in ipairs(SelectedDataNodes(ids or P.AllItemIds())) do
    payload.items[n.id] = true
    for _, e in ipairs(NodeEntries(n, "core", core)) do CopyEntry(core, payload.core, e) end
    if auras then
      for _, e in ipairs(NodeEntries(n, "auras", auras)) do CopyEntry(auras, payload.auras, e) end
    end
  end
  -- Sorts Auras : seuls les sorts personnalisés voyagent (cf. ns.Auras.IsSpellCustomized),
  -- l'importeur recrée les autres depuis ses propres découvertes.
  if payload.auras.discoveredSpells and ns.Auras and ns.Auras.DropUncustomizedSpells then
    ns.Auras.DropUncustomizedSpells(payload.auras.discoveredSpells)
  end
  payload.addon = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
  payload.date = date("%Y-%m-%d")
  return payload
end

function P.EncodePayload(payload)
  local LS, LD = GetCodec()
  if not LS then return nil, "LibSerialize / LibDeflate" end
  local ok, out = pcall(function()
    return EXPORT_PREFIX_V3 .. LD:EncodeForPrint(LD:CompressDeflate(LS:Serialize(payload), { level = DEFLATE_LEVEL }))
  end)
  if not ok then return nil, tostring(out) end
  return out
end

function P.ExportItems(name, ids)
  local payload, err = P.BuildItemsPayload(name, ids)
  if not payload then return nil, err end
  return P.EncodePayload(payload)
end

--- Exporte un profil complet.
function P.Export(name)
  return P.ExportItems(name)
end

-- Ancien format → V3 : tous les nœuds dont une donnée est présente
local function ToV3(core, auras)
  local payload = { v = 3, items = {}, core = type(core) == "table" and core or {},
                    auras = type(auras) == "table" and auras or {} }
  for _, n in ipairs(ns.GetProfileTreeIndex().order) do
    if ns.IsProfileDataNode(n) then
      for _, store in ipairs({ "core", "auras" }) do
        for _, e in ipairs(NodeEntries(n, store, payload[store])) do
          if PathGet(payload[store], EntryPath(e)) ~= nil then payload.items[n.id] = true end
        end
      end
    end
  end
  return payload
end

--- Décode une chaîne d'export (V3, ou V1 / V2 convertis). Retourne payload | nil, err.
function P.DecodeExport(str)
  if type(str) ~= "string" then return nil, L["PROFILE_STRING_INVALID"] end
  -- Tolérance aux espaces/retours à la ligne en début/fin
  str = str:match("^%s*(.-)%s*$")

  local body = str:match("^" .. EXPORT_PREFIX_V3 .. "(.+)$")
  local isV2 = false
  if not body then
    body = str:match("^" .. EXPORT_PREFIX_V2 .. "(.+)$")
    isV2 = body ~= nil
  end
  if body then
    local LS, LD = GetCodec()
    if not LS then return nil, string.format(L["PROFILE_IMPORT_READ_ERROR"], "LibSerialize / LibDeflate") end
    local decoded = LD:DecodeForPrint(body)
    local raw = decoded and LD:DecompressDeflate(decoded)
    if not raw then return nil, string.format(L["PROFILE_IMPORT_READ_ERROR"], "LibDeflate") end
    local ok, payload = LS:Deserialize(raw)
    if not ok or type(payload) ~= "table" then
      return nil, string.format(L["PROFILE_IMPORT_FORMAT_UNRECOGNIZED"], EXPORT_PREFIX_V3)
    end
    if isV2 then
      if type(payload.modules) ~= "table" then
        return nil, string.format(L["PROFILE_IMPORT_FORMAT_UNRECOGNIZED"], EXPORT_PREFIX_V3)
      end
      local core = {}
      for id, mod in pairs(payload.modules) do
        if id ~= "auras" and type(mod) == "table" then
          for k, v in pairs(mod) do core[k] = v end
        end
      end
      local v3 = ToV3(core, payload.modules.auras)
      v3.addon, v3.date = payload.addon, payload.date
      return v3
    end
    if payload.v ~= 3 or type(payload.items) ~= "table" then
      return nil, string.format(L["PROFILE_IMPORT_FORMAT_UNRECOGNIZED"], EXPORT_PREFIX_V3)
    end
    payload.core = type(payload.core) == "table" and payload.core or {}
    payload.auras = type(payload.auras) == "table" and payload.auras or {}
    return payload
  end

  local v1 = str:match("^" .. EXPORT_PREFIX .. "(.+)$")
    or str:match("^" .. LEGACY_EXPORT_PREFIX .. "(.+)$")
  if not v1 then
    return nil, string.format(L["PROFILE_IMPORT_FORMAT_UNRECOGNIZED"], EXPORT_PREFIX_V3)
  end
  local data, err = Deserialize(v1)
  if not data then return nil, string.format(L["PROFILE_IMPORT_READ_ERROR"], tostring(err)) end
  local auras = data._auras
  data._auras = nil
  return ToV3(data, auras)
end

-- Version "a.b.c" -> comparable ; true si la chaîne vient d'une version plus récente que l'addon.
local function VersionParts(v)
  local t = {}
  for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end
function P.IsPayloadNewer(payload)
  local mine = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
  if not (payload and payload.addon and mine) then return false end
  local a, b = VersionParts(payload.addon), VersionParts(mine)
  for i = 1, math.max(#a, #b) do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

-- Ids des éléments présents dans une charge utile, dans l'ordre de l'arbre.
function P.PayloadItemIds(payload)
  local ids = {}
  local items = payload and payload.items or {}
  for _, n in ipairs(ns.GetProfileTreeIndex().order) do
    if items[n.id] then ids[#ids + 1] = n.id end
  end
  return ids
end

-- Valeurs de référence d'un profil neuf (template puis défauts), pour la réinitialisation
local function ReferenceCore()
  local base = ns.ProfileTemplate and ns.DeepCopy(ns.ProfileTemplate) or {}
  return ns.MergeDefaults(base, ns.Defaults)
end
local function ReferenceAuras()
  local A = ns.Auras
  if not A then return {} end
  local base = A.ProfileTemplate and ns.DeepCopy(A.ProfileTemplate) or {}
  return A.MergeDefaults and A.MergeDefaults(base, A.Defaults) or base
end

--- Écrit des éléments dans un profil existant. Chaque chemin d'un élément est remplacé entièrement
--- (pas de fusion champ par champ) ; un élément absent de la charge utile repart des valeurs de
--- référence (template puis défauts) : c'est aussi la réinitialisation.
---   ids : éléments à appliquer (nil = tous ceux de la charge utile)
function P.ApplyItems(payload, target, ids)
  local root = AishaddonDB
  local prof = root._profiles[target]
  if not prof then return false, L["PROFILE_NOT_FOUND"] end
  payload = payload or { items = {}, core = {}, auras = {} }
  local items = payload.items or {}
  local nodes = SelectedDataNodes(ids or P.PayloadItemIds(payload))
  local AP = AurasProfiles()
  local idx = ns.GetProfileTreeIndex()
  local refCore, refAuras, newAuras
  local applyMods, panels = {}, {}

  for _, n in ipairs(nodes) do
    local fromPayload = items[n.id] == true
    local srcCore = fromPayload and payload.core or nil
    if not srcCore then refCore = refCore or ReferenceCore(); srcCore = refCore end
    for _, e in ipairs(NodeEntries(n, "core", srcCore, prof)) do CopyEntry(srcCore, prof, e, true) end

    if AP and (n.auras or n.misc) then
      if not newAuras then
        local cur = AurasTable(target)
        newAuras = cur and ns.DeepCopy(cur) or {}
      end
      local srcAuras = fromPayload and payload.auras or nil
      if not srcAuras then refAuras = refAuras or ReferenceAuras(); srcAuras = refAuras end
      for _, e in ipairs(NodeEntries(n, "auras", srcAuras, newAuras)) do CopyEntry(srcAuras, newAuras, e, true) end
    end

    for _, m in ipairs(n.apply or {}) do applyMods[m] = true end
    local section = idx.section[n.id]
    if section and section.panel then panels[section.panel] = true end
  end

  -- Le statut actif/inactif voyage avec l'élément : une catégorie coupée en bloc sur la page
  -- "Modules" ne doit pas laisser l'élément importé masqué.
  local mp = prof.modulesPanel
  if mp and mp.categoryOff then
    for panel in pairs(panels) do mp.categoryOff[panel] = nil end
  end

  ns.MergeDefaults(prof, ns.Defaults)
  -- Réglages venus d'un autre setup : polices éventuellement absentes ici. Cf. InitDB.
  ns.RemapFontAliases(prof)
  if ns.SanitizeFontPaths then ns.SanitizeFontPaths(prof) end
  if newAuras then AP:SetProfileData(target, newAuras) end

  if target == P.GetActive() then
    ns.DB = prof
    if newAuras then AP:SetActive(target) end
    for m in pairs(applyMods) do SafeApply(ns.Modules[m], m) end
    ns.CallbackRegistry:Trigger("PROFILE_CHANGED", target)
  end
  return true
end

--- Copie des éléments d'un profil vers un autre (sans sérialisation).
function P.CopyItems(srcName, dstName, ids)
  if srcName == dstName then return false, L["PROFILE_SOURCE_DEST_IDENTICAL"] end
  local payload, err = P.BuildItemsPayload(srcName, ids)
  if not payload then return false, err end
  return P.ApplyItems(payload, dstName, ids)
end

--- Remet des éléments d'un profil à leurs valeurs de référence.
function P.ResetItems(name, ids)
  return P.ApplyItems(nil, name, ids)
end

--- Importe un profil depuis une chaîne texte exportée.
---   str     : chaîne issue de Export()
---   newName : nom à donner au nouveau profil
---   ids     : éléments à importer (nil = tous ceux de la chaîne) ; les autres partent du template
function P.Import(str, newName, ids)
  local payload, decodeErr = P.DecodeExport(str)
  if not payload then return false, decodeErr end

  if type(newName) ~= "string" then return false, L["PROFILE_DEST_NAME_INVALID"] end
  newName = newName:match("^%s*(.-)%s*$")
  if newName == "" then return false, L["PROFILE_DEST_NAME_EMPTY"] end

  local root = AishaddonDB
  if root._profiles[newName] then
    return false, string.format(L["PROFILE_ALREADY_EXISTS_NAMED"], newName)
  end

  local ok, err = P.Create(newName)
  if not ok then return false, err end
  return P.ApplyItems(payload, newName, ids)
end

-- CopyFrom — écrase le profil actif avec une copie du profil source
function P.CopyFrom(sourceName)
  local root = AishaddonDB
  if not root._profiles[sourceName] then return false, L["PROFILE_SOURCE_NOT_FOUND"] end
  local active = ns._activeProfileName or "Default"
  if sourceName == active then return false, L["PROFILE_SOURCE_DEST_IDENTICAL"] end

  root._profiles[active] = ns.MergeDefaults(ns.DeepCopy(root._profiles[sourceName]), ns.Defaults)
  ns.DB = root._profiles[active]
  local AP = AurasProfiles()
  if AP and AP:Copy(sourceName, active) then AP:SetActive(active) end
  ApplyAllSettings()
  ns.CallbackRegistry:Trigger("PROFILE_CHANGED", active)
  return true
end

-- Profils de spécialisation (AishaddonDB._specProfiles = { enabled, [specID] = profileName })
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

-- Basculement automatique lors d'un changement de spécialisation
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
-- Forever : la "spe" est la branche de talents la plus investie (cf. Core.lua), elle change
-- donc a chaque point depense. Pas en Retail : TRAIT_CONFIG_UPDATED y suit chaque retouche de
-- talents et relancerait le changement de spe a tort.
if ns.IsForever then
  specEventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
  specEventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
  specEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
end
specEventFrame:SetScript("OnEvent", function()
  -- Spe deduite mise en cache : la purger d'abord, sinon on relirait la valeur d'avant le point.
  if ns.InvalidateSpecCache then ns.InvalidateSpecCache() end
  ApplySpecProfile()
  ns.CallbackRegistry:Trigger("SPEC_CHANGED")
end)

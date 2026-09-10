-- Modules/SpellEffects.lua : Animations 3D déclenchées par les sorts
-- Système complet :
--   • Combos : 1 sort → N animations (chacune avec delay, position, rotation, scale)
--   • Pool de PlayerModel frames réutilisables
--   • Ancrage au cercle de ressource central (AishCoreRingBar)
--   • Preview depuis le panneau Settings
local addonName, ns = ...

local SpellEffects = {}
ns.Modules.SpellEffects = SpellEffects

-- Helper nom de sort (C_Spell.GetSpellName est la seule API propre en TWW)
local function GetSpellName(spellID)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and name then return name end
  end
  local ok2, name2 = pcall(GetSpellInfo, spellID)
  return ok2 and name2 or nil
end

local MAX_POOL     = 8         -- modèles simultanés max
local DEFAULT_DUR  = 0.8       -- durée par défaut (sec)
local DEFAULT_FADE = 0.25      -- durée de fadeout (sec)
local RING_FRAME   = "AishCoreRingBar"

-- Pool de PlayerModel frames
local pool       = {}   -- { frame, inUse, timer }
local poolSize   = 0

local function GetAnchor()
  return _G[RING_FRAME] or UIParent
end

--- Vrai si les toggles "Desactiver en Raid/Groupe" bloquent les animations reelles (jamais les previews GUI).
local function AnimationsBlockedByGroupState()
  local cfg = ns.GetCfg("spellEffects")
  if not cfg then return false end
  local inRaid = IsInRaid and IsInRaid()
  if cfg.disableAnimsInRaid and inRaid then return true end
  if cfg.disableAnimsInGroup and not inRaid and IsInGroup and IsInGroup() then return true end
  return false
end

local function AcquireModel()
  for i = 1, poolSize do
    if not pool[i].inUse then
      pool[i].inUse = true
      return pool[i]
    end
  end
  if poolSize >= MAX_POOL then return nil end
  poolSize = poolSize + 1
  local f = CreateFrame("PlayerModel", "AishCoreFxPool" .. poolSize, UIParent)
  f:SetSize(200, 200)
  f:SetKeepModelOnHide(true)
  f:Hide()
  local entry = { frame = f, inUse = true, timer = nil, fadeTicker = nil }
  pool[poolSize] = entry
  return entry
end

local function ReleaseModel(entry)
  if not entry then return end
  if entry.timer then entry.timer:Cancel(); entry.timer = nil end
  if entry.fadeTicker then entry.fadeTicker:Cancel(); entry.fadeTicker = nil end
  entry.frame:Hide()
  entry.frame:SetAlpha(1)
  entry.inUse = false
end

-- Base 500x500 pour "Buffs manquants" (vs 200x200 ailleurs) : partagee par ApplyAnimConfig
-- et les tickers de refresh live, pour eviter un retrecissement brutal au 1er tick.
local function GetBaseSizeForAnchor(anchor)
  local anchorName = anchor and anchor.GetName and anchor:GetName() or ""
  return (anchorName == "AishCoreMissingBuffFrame") and 500 or 200
end

-- overrideAnchor = parent (visibilite hierarchique) ; pointAnchor optionnel = reference de position pour SetPoint.
local function ApplyAnimConfig(f, anim, overrideAnchor, pointAnchor)
  local anchor = overrideAnchor or GetAnchor()
  local pAnchor = pointAnchor or anchor

  f:SetParent(anchor)
  f:ClearAllPoints()
  f:SetPoint("CENTER", pAnchor, "CENTER", anim.anchorX or 0, anim.anchorY or 0)

  local strata = anim.strata or "BACKGROUND"
  -- Profil visuel (taille/strate) derive de pAnchor (reference de position), pas du parent.
  local anchorName = pAnchor.GetName and pAnchor:GetName() or ""
  local isOoc = (anchorName == "AishCoreHealthRing")
  local isOrb = anchorName:find("^AishCoreSecDot") or anchorName:find("^AishCoreOCSecDot")
  local isMissingBuff = (anchorName == "AishCoreMissingBuffFrame")

  local baseSize = GetBaseSizeForAnchor(pAnchor)
  local sz = (anim.scale or 1) * baseSize
  f:SetSize(sz, sz)

  if isMissingBuff then
    -- Icone d'alerte "Buffs manquants" : mêmes 3 niveaux (fond/moyen/premier plan), relatifs à l'icône.
    if strata == "FOREGROUND" then
      f:SetFrameStrata("HIGH")
      f:SetFrameLevel(anchor:GetFrameLevel() + 10)
    elseif strata == "HIGH" or strata == "MEDIUM" then
      f:SetFrameStrata("HIGH")
      f:SetFrameLevel(anchor:GetFrameLevel() + 1)
    else
      f:SetFrameStrata("BACKGROUND")
    end
  elseif isOrb then
    -- Globes externes : 2 niveaux seulement
    if strata == "FOREGROUND" then
      f:SetFrameStrata(anchor:GetFrameStrata())
      f:SetFrameLevel(anchor:GetFrameLevel() + 3)
    else
      f:SetFrameStrata(anchor:GetFrameStrata())
      f:SetFrameLevel(math.max(1, anchor:GetFrameLevel() - 1))
    end
  elseif isOoc then
    -- Cercle de vie OOC : 3 niveaux
    if strata == "FOREGROUND" then
      f:SetFrameStrata("MEDIUM")
      f:SetFrameLevel(anchor:GetFrameLevel() + 10)
    elseif strata == "HIGH" or strata == "MEDIUM" then
      -- Moyen plan : entre l'overlay et le textFrame du health ring
      local tf = ns.healthRingTextFrame
      local targetLevel = tf and (tf:GetFrameLevel() - 1) or (anchor:GetFrameLevel() + 4)
      f:SetFrameStrata(anchor:GetFrameStrata())
      f:SetFrameLevel(targetLevel)
    else
      f:SetFrameStrata("BACKGROUND")
    end
  else
    -- Sorts configurés (cercle de ressource combat)
    if strata == "FOREGROUND" then
      f:SetFrameStrata("HIGH")
    elseif strata == "HIGH" or strata == "MEDIUM" then
      local tf = ns.ringBarTextFrame
      local targetLevel = tf and (tf:GetFrameLevel() - 1) or (anchor:GetFrameLevel() + 4)
      f:SetFrameStrata("MEDIUM")
      f:SetFrameLevel(targetLevel)
    else
      f:SetFrameStrata("BACKGROUND")
    end
  end

  f:ClearModel()
  local okModel, errModel = pcall(function() f:SetModel(tonumber(anim.modelID)) end)
  if SpellEffects._debugAll then
    local P = "|cff00ffff[SE-DEBUG]|r "
    print(P .. "  -> SetModel(" .. tostring(anim.modelID) .. ") ok=" .. tostring(okModel)
      .. " err=" .. tostring(errModel)
      .. " GetModel=" .. tostring(f.GetModel and f:GetModel()))
  end

  -- Positionnement 3D (old API — Z, X, Y comme WeakAuras)
  pcall(function() f:SetPosition(anim.z or 0, anim.x or 0, anim.y or 0) end)

  -- Rotation (degrés → radians)
  pcall(function() f:SetFacing(math.rad(anim.rotation or 0)) end)

  f:SetAlpha(anim.alpha or 1)
end

-- onSpawn(entry, anchor) optionnel : notifie l'appelant (utilisé par PreviewComboLoop pour le refresh live).
local function PlaySingleAnim(anim, overrideAnchor, onSpawn)
  local entry = AcquireModel()
  if not entry then return end

  local f = entry.frame
  ApplyAnimConfig(f, anim, overrideAnchor)
  f:Show()
  if onSpawn then onSpawn(entry, overrideAnchor) end

  local duration = anim.duration or DEFAULT_DUR
  local fadeTime = math.min(DEFAULT_FADE, duration * 0.4)

  entry.timer = C_Timer.After(math.max(0.01, duration - fadeTime), function()
    entry.timer = nil
    local startAlpha = f:GetAlpha()
    local elapsed = 0
    local interval = 0.016
    entry.fadeTicker = C_Timer.NewTicker(interval, function(ticker)
      elapsed = elapsed + interval
      local pct = math.min(1, elapsed / fadeTime)
      f:SetAlpha(startAlpha * (1 - pct))
      if pct >= 1 then
        ticker:Cancel()
        entry.fadeTicker = nil
        ReleaseModel(entry)
      end
    end)
  end)
end

-- Jouer un combo (N animations avec delays)
local function PlayCombo(combo, overrideAnchor, onSpawn)
  if not combo or #combo == 0 then return end
  for _, anim in ipairs(combo) do
    if anim.enabled ~= false then
      local delay = anim.delay or 0
      if delay > 0 then
        C_Timer.After(delay, function() PlaySingleAnim(anim, overrideAnchor, onSpawn and function(entry, anchor) onSpawn(anim, entry, anchor) end) end)
      else
        PlaySingleAnim(anim, overrideAnchor, onSpawn and function(entry, anchor) onSpawn(anim, entry, anchor) end)
      end
    end
  end
end

-- API publique

--- Résout le spellID configuré pour un cast (alias, ID direct, ou fallback par nom si talent/override).
local function ResolveComboSpellID(spellID, combos)
  if not combos then return nil end
  -- 1) Vérifier les alias explicites en priorité (peut pointer vers un autre entry même si spellID existe directement)
  local cfg = ns.GetCfg("spellEffects")
  if cfg and cfg.combosAliases then
    local configuredID = cfg.combosAliases[spellID]
    if configuredID and combos[configuredID] then
      return configuredID
    end
  end
  -- 2) Match direct
  if combos[spellID] then return spellID end
  -- 3) Fallback par nom, seulement si variante/override du sort configuré (évite les faux positifs)
  local name = GetSpellName(spellID)
  if not name then return nil end
  for configID in pairs(combos) do
    if configID ~= spellID and GetSpellName(configID) == name then
      -- Vérifier que c'est un override réel (talent qui remplace le sort)
      if C_Spell and C_Spell.GetOverrideSpell then
        local ok, override = pcall(C_Spell.GetOverrideSpell, configID)
        if ok and override == spellID then
          return configID
        end
      end
    end
  end
  return nil
end

--- Joue les animations "onhit" configurées pour un spellID.
function SpellEffects.Play(spellID)
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return end
  if AnimationsBlockedByGroupState() then return end

  -- Nouveau format : combos (filtre per-anim trigger)
  local combos = cfg.combos
  local resolvedID = ResolveComboSpellID(spellID, combos)

  if SpellEffects._debugNext or SpellEffects._debugAll then
    if SpellEffects._debugNext then SpellEffects._debugNext = false end
    local P = "|cff00ffff[SE-DEBUG]|r "
    local aliasesDB = cfg.combosAliases or {}
    local aliasTarget = aliasesDB[spellID]
    print(P .. "Play(" .. tostring(spellID) .. ") nom=" .. (GetSpellName(spellID) or "?"))
    print(P .. "combos[" .. spellID .. "]= " .. tostring(combos[spellID] ~= nil))
    print(P .. "aliases[" .. spellID .. "]= " .. tostring(aliasTarget) .. (aliasTarget and (" -> combos[" .. aliasTarget .. "]= " .. tostring(combos[aliasTarget] ~= nil) .. ")") or ""))
    print(P .. "resolvedID= " .. tostring(resolvedID) .. (resolvedID and (" (" .. (GetSpellName(resolvedID) or "?") .. ")") or ""))
    if resolvedID and combos[resolvedID] then
      local combo = combos[resolvedID]
      for idx, a in ipairs(combo) do
        local trig = a.trigger or "onhit"
        local en = a.enabled ~= false
        print(P .. string.format("  anim #%d: trigger=%s enabled=%s model=%s", idx, trig, tostring(en), tostring(a.modelID or 0)))
      end
    end
  end

  if resolvedID then
    local combo = combos[resolvedID]
    -- Extraire seulement les anims "onhit" (ou sans trigger = compat)
    local onhitAnims = {}
    for _, a in ipairs(combo) do
      if (a.trigger or "onhit") == "onhit" and a.enabled ~= false then
        onhitAnims[#onhitAnims + 1] = a
      end
    end
    if #onhitAnims > 0 then PlayCombo(onhitAnims) end
    return
  end

  -- Compat ancien format (cfg.spells)
  if cfg.spells and cfg.spells[spellID] then
    local old = cfg.spells[spellID]
    PlaySingleAnim({
      modelID  = old.modelID,
      duration = old.duration or DEFAULT_DUR,
      z = 0, x = 0, y = 0, rotation = 0, scale = 1, alpha = 1,
      strata = "BACKGROUND", anchorX = 0, anchorY = 0,
    })
  end
end

-- Casting animations : jouées pendant le cast/channel d'un sort
local castingEntries   = {}   -- pool entries en cours pour un cast
local castingTicker    = nil  -- auto-stop timer
local castingSpellID   = nil  -- pour détecter le même channel
local castingGen       = 0    -- compteur de génération (incrémenté à chaque PlayCasting)

-- Evoker empower : SUCCEEDED fire au début du cast, le onhit est donc différé à EMPOWER_STOP.
local empowerSpellID       = nil   -- spellID du sort augmenté en cours
local empowerPendingOnhit  = nil   -- timer handle pour le onhit différé

--- Joue les animations "casting" d'un combo pendant toute la durée du cast.
--- isChannel : true si appelé depuis CHANNEL_START (garde les anims en place si WoW re-fire START).
local function PlayCasting(spellID, castDuration, isChannel)
  if SpellEffects._debugNext or SpellEffects._debugAll then
    if SpellEffects._debugNext then SpellEffects._debugNext = false end
    local P = "|cff00ffff[SE-DEBUG]|r "
    print(P .. "PlayCasting(" .. tostring(spellID) .. ") nom=" .. (GetSpellName(spellID) or "?") .. " dur=" .. tostring(castDuration) .. " isChannel=" .. tostring(isChannel))
    local cfg = ns.GetCfg("spellEffects")
    if cfg and cfg.combos then
      local rid = ResolveComboSpellID(spellID, cfg.combos)
      print(P .. "resolvedID=" .. tostring(rid))
      if rid and cfg.combos[rid] then
        local nCast = 0
        for _, a in ipairs(cfg.combos[rid]) do
          if a.trigger == "casting" and a.enabled ~= false then nCast = nCast + 1 end
        end
        print(P .. "casting anims trouvées: " .. nCast)
      end
    end
  end

  -- Même channel déjà animé : juste MAJ le timer, PAS de StopCasting.
  if isChannel and castingSpellID == spellID and #castingEntries > 0 then
    -- Incrémenter la génération pour invalider tout timer STOP en attente
    castingGen = castingGen + 1
    if castingTicker then
      if type(castingTicker) == "table" and castingTicker.Cancel then
        castingTicker:Cancel()
      end
      castingTicker = nil
    end
    if castDuration and castDuration > 0 then
      local g = castingGen
      castingTicker = C_Timer.After(castDuration, function()
        if castingGen ~= g then return end
        StopCasting()
      end)
    end
    return
  end

  -- Sauvegarder les anciens modèles AVANT d'en spawner de nouveaux.
  local oldEntries = {}
  for i, entry in ipairs(castingEntries) do
    oldEntries[i] = entry
  end
  wipe(castingEntries)

  -- Annuler le timer précédent
  if castingTicker then
    if type(castingTicker) == "table" and castingTicker.Cancel then
      castingTicker:Cancel()
    end
    castingTicker = nil
  end

  castingSpellID = spellID
  castingGen = castingGen + 1

  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then
    for _, entry in ipairs(oldEntries) do ReleaseModel(entry) end
    return
  end
  local combos = cfg.combos
  local resolvedID = ResolveComboSpellID(spellID, combos)
  -- Fallback par nom : les canalisations utilisent souvent un spellID différent (ex: Penance 47758 vs 47540).
  if not resolvedID then
    local castName = GetSpellName(spellID)
    if castName then
      for configID in pairs(combos) do
        if type(configID) == "number" and GetSpellName(configID) == castName then
          resolvedID = configID
          break
        end
      end
    end
  end
  if not resolvedID then
    for _, entry in ipairs(oldEntries) do ReleaseModel(entry) end
    return
  end
  local combo = combos[resolvedID]

  -- Extraire seulement les anims "casting"
  local castAnims = {}
  for _, a in ipairs(combo) do
    if a.trigger == "casting" and a.enabled ~= false then castAnims[#castAnims + 1] = a end
  end
  if #castAnims == 0 then
    for _, entry in ipairs(oldEntries) do ReleaseModel(entry) end
    return
  end

  -- Spawn les nouveaux modèles (sur des frames DIFFÉRENTS des anciens)
  for _, anim in ipairs(castAnims) do
    local delay = anim.delay or 0
    local function spawn()
      local entry = AcquireModel()
      if not entry then return end
      ApplyAnimConfig(entry.frame, anim)
      entry.frame:Show()
      castingEntries[#castingEntries + 1] = entry
    end
    if delay > 0 then
      C_Timer.After(delay, spawn)
    else
      spawn()
    end
  end

  -- Maintenant relâcher les anciens
  for _, entry in ipairs(oldEntries) do
    ReleaseModel(entry)
  end

  -- Auto-stop after cast duration
  if castDuration and castDuration > 0 then
    local g = castingGen
    castingTicker = C_Timer.After(castDuration, function()
      if castingGen ~= g then return end
      StopCasting()
    end)
  end
end

--- Stoppe les animations de casting en cours.
function StopCasting()
  castingSpellID = nil
  if castingTicker then
    if type(castingTicker) == "table" and castingTicker.Cancel then
      castingTicker:Cancel()
    end
    castingTicker = nil
  end
  for _, entry in ipairs(castingEntries) do
    ReleaseModel(entry)
  end
  wipe(castingEntries)
end

SpellEffects.PlayCasting = PlayCasting
SpellEffects.StopCasting = StopCasting

--- Prévisualise une animation unique (depuis le panneau Settings).
function SpellEffects.Preview(anim)
  if not anim or not anim.modelID then return end
  local a = {}
  for k, v in pairs(anim) do a[k] = v end
  a.duration = a.duration or 2.0
  PlaySingleAnim(a)
end

--- Prévisualise un combo entier.
function SpellEffects.PreviewCombo(combo)
  if not combo then return end
  PlayCombo(combo)
end

-- Déclarée ici (avant StopAll) : partage le pool, mais protégée du nettoyage (aura active hors combat).
local sustainedAuraEntries = {}  -- [auraID] = { entry, ... }
-- Miroir pour "Buffs manquants" (Modules/Auras/Core/MissingBuffs.lua), même protection.
local sustainedMissingBuffEntries = {}  -- [spellID] = { entry, ... }
-- Miroir pour Ruée Ardente, déclaré ici pour être visible depuis StopAll.
local sustainedBurningRushEntries = {}  -- [spellID] = { entry, ... }

--- Stoppe toutes les animations en cours (protège les combos d'auras actifs, ancrés sur UIParent).
function SpellEffects.StopAll()
  StopCasting()
  SpellEffects.StopAllSustained()
  local protectedAura = {}
  for _, entries in pairs(sustainedAuraEntries) do
    for _, entry in ipairs(entries) do protectedAura[entry] = true end
  end
  for _, entries in pairs(sustainedMissingBuffEntries) do
    for _, entry in ipairs(entries) do protectedAura[entry] = true end
  end
  for _, entries in pairs(sustainedBurningRushEntries) do
    for _, entry in ipairs(entries) do protectedAura[entry] = true end
  end
  for i = 1, poolSize do
    if not protectedAura[pool[i]] then
      ReleaseModel(pool[i])
    end
  end
end

-- Animations soutenues : démarrées/arrêtées explicitement (procs, buffs…)
local sustainedEntries = {}  -- [spellID] = { entry, ... }

--- Démarre une animation soutenue pour spellID (reste visible jusqu'à StopSustained).
function SpellEffects.StartSustained(spellID)
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return end
  if AnimationsBlockedByGroupState() then return end
  local combos = cfg.combos
  local resolvedID = ResolveComboSpellID(spellID, combos)
  if not resolvedID then return end

  -- Arrêter toute instance précédente pour ce spellID
  SpellEffects.StopSustained(spellID)

  local entries = {}
  sustainedEntries[spellID] = entries

  for _, anim in ipairs(combos[resolvedID]) do
    if (anim.trigger or "onhit") == "onhit" and anim.enabled ~= false then
      local function spawn()
        local entry = AcquireModel()
        if not entry then return end
        ApplyAnimConfig(entry.frame, anim)
        entry.frame:Show()
        -- Pas de timer : reste affiché indéfiniment
        entries[#entries + 1] = entry
      end
      local delay = anim.delay or 0
      if delay > 0 then
        C_Timer.After(delay, spawn)
      else
        spawn()
      end
    end
  end
end

--- Arrête immédiatement l'animation soutenue d'un spellID.
function SpellEffects.StopSustained(spellID)
  local entries = sustainedEntries[spellID]
  if entries then
    for _, entry in ipairs(entries) do
      ReleaseModel(entry)
    end
    sustainedEntries[spellID] = nil
  end
end

--- Arrête toutes les animations soutenues en cours.
function SpellEffects.StopAllSustained()
  for spellID in pairs(sustainedEntries) do
    SpellEffects.StopSustained(spellID)
  end
end

-- Animations soutenues déclenchées par une aura (joueur ou cible) : tournent tant que l'aura est présente.

--- Démarre l'animation soutenue associée à l'apparition d'une aura.
function SpellEffects.StartAuraSustained(auraID)
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return end
  if AnimationsBlockedByGroupState() then return end
  local combo = cfg.auraCombos and cfg.auraCombos[auraID]
  if not combo then return end

  -- Arrêter toute instance précédente pour cette aura
  SpellEffects.StopAuraSustained(auraID)

  local entries = {}
  sustainedAuraEntries[auraID] = entries

  for _, anim in ipairs(combo) do
    if anim.enabled ~= false then
      local function spawn(attempt)
        attempt = attempt or 1
        -- Si StopAuraSustained a entre-temps remplacé/vidé 'entries' (aura
        -- disparue, nouvelle transition...), cette tentative est obsolète.
        if sustainedAuraEntries[auraID] ~= entries then return end

        local entry = AcquireModel()
        if SpellEffects._debugAll then
          local P = "|cff00ffff[SE-DEBUG]|r "
          print(P .. "StartAuraSustained auraID=" .. tostring(auraID)
            .. " modelID=" .. tostring(anim.modelID)
            .. " entry=" .. tostring(entry ~= nil)
            .. " attempt=" .. tostring(attempt))
        end
        if not entry then
          -- Pool saturé : retente plus tard plutôt que d'abandonner l'anim soutenue.
          if attempt < 20 then
            C_Timer.After(0.25, function() spawn(attempt + 1) end)
          end
          return
        end
        ApplyAnimConfig(entry.frame, anim)
        entry.frame:Show()
        if SpellEffects._debugAll then
          local P = "|cff00ffff[SE-DEBUG]|r "
          local f = entry.frame
          local cx, cy = f:GetCenter()
          print(P .. "  -> frame=" .. tostring(f:GetName())
            .. " shown=" .. tostring(f:IsShown())
            .. " visible=" .. tostring(f:IsVisible())
            .. " strata=" .. tostring(f:GetFrameStrata())
            .. " level=" .. tostring(f:GetFrameLevel())
            .. " alpha=" .. string.format("%.2f", f:GetAlpha())
            .. " size=" .. string.format("%.0f", (select(1, f:GetSize())))
            .. " center=" .. tostring(cx and string.format("%.0f,%.0f", cx, cy) or "nil")
            .. " anchorX=" .. tostring(anim.anchorX) .. " anchorY=" .. tostring(anim.anchorY)
            .. " scale=" .. tostring(anim.scale) .. " animAlpha=" .. tostring(anim.alpha)
            .. " strataCfg=" .. tostring(anim.strata)
            .. " | z=" .. tostring(anim.z) .. " x=" .. tostring(anim.x) .. " y=" .. tostring(anim.y)
            .. " rot=" .. tostring(anim.rotation) .. " dur=" .. tostring(anim.duration)
            .. " trigger=" .. tostring(anim.trigger) .. " enabled=" .. tostring(anim.enabled))
        end
        -- Pas de timer : reste affiché tant que l'aura est active
        entries[#entries + 1] = entry
      end
      local delay = anim.delay or 0
      if delay > 0 then
        C_Timer.After(delay, spawn)
      else
        spawn()
      end
    end
  end
end

--- Arrête immédiatement l'animation soutenue d'une aura.
function SpellEffects.StopAuraSustained(auraID)
  local entries = sustainedAuraEntries[auraID]
  if entries then
    for _, entry in ipairs(entries) do
      ReleaseModel(entry)
    end
    sustainedAuraEntries[auraID] = nil
  end
end

--- Arrête toutes les animations soutenues d'auras en cours.
function SpellEffects.StopAllAuraSustained()
  for auraID in pairs(sustainedAuraEntries) do
    SpellEffects.StopAuraSustained(auraID)
  end
end

-- Animations soutenues du module "Buffs manquants" : miroir de StartAuraSustained mais sans scan
-- d'aura (présence lue depuis MissingBuffs), ancré sur AishCoreMissingBuffFrame (l'icône d'alerte).

--- Démarre l'animation soutenue associée à l'affichage d'un spellID par le
--- module "Buffs manquants".
function SpellEffects.StartMissingBuffSustained(spellID)
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return end
  if AnimationsBlockedByGroupState() then return end
  local combo = cfg.missingBuffsCombos and cfg.missingBuffsCombos[spellID]
  if not combo then return end

  SpellEffects.StopMissingBuffSustained(spellID)

  local entries = {}
  sustainedMissingBuffEntries[spellID] = entries
  local anchor = _G["AishCoreMissingBuffFrame"] or UIParent

  for _, anim in ipairs(combo) do
    if anim.enabled ~= false then
      local function spawn(attempt)
        attempt = attempt or 1
        if sustainedMissingBuffEntries[spellID] ~= entries then return end
        local entry = AcquireModel()
        if not entry then
          if attempt < 20 then
            C_Timer.After(0.25, function() spawn(attempt + 1) end)
          end
          return
        end
        ApplyAnimConfig(entry.frame, anim, anchor)
        entry.frame:Show()
        entries[#entries + 1] = entry
      end
      local delay = anim.delay or 0
      if delay > 0 then
        C_Timer.After(delay, spawn)
      else
        spawn()
      end
    end
  end
end

--- Arrête immédiatement l'animation soutenue d'un spellID "buff manquant".
function SpellEffects.StopMissingBuffSustained(spellID)
  local entries = sustainedMissingBuffEntries[spellID]
  if entries then
    for _, entry in ipairs(entries) do
      ReleaseModel(entry)
    end
    sustainedMissingBuffEntries[spellID] = nil
  end
end

--- Arrête toutes les animations soutenues "buff manquant" en cours.
function SpellEffects.StopAllMissingBuffSustained()
  for spellID in pairs(sustainedMissingBuffEntries) do
    SpellEffects.StopMissingBuffSustained(spellID)
  end
end

-- Ruée Ardente : comme StartMissingBuffSustained mais parenté sur UIParent (jamais caché), AishCoreMissingBuffFrame sert juste de repère de position
function SpellEffects.StartBurningRushSustained(spellID)
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return end
  if AnimationsBlockedByGroupState() then return end
  local combo = cfg.missingBuffsCombos and cfg.missingBuffsCombos[spellID]
  if not combo then return end

  SpellEffects.StopBurningRushSustained(spellID)

  local entries = {}
  sustainedBurningRushEntries[spellID] = entries
  local posRef = _G["AishCoreMissingBuffFrame"] or UIParent

  for _, anim in ipairs(combo) do
    if anim.enabled ~= false then
      local function spawn(attempt)
        attempt = attempt or 1
        if sustainedBurningRushEntries[spellID] ~= entries then return end
        local entry = AcquireModel()
        if not entry then
          if attempt < 20 then
            C_Timer.After(0.25, function() spawn(attempt + 1) end)
          end
          return
        end
        ApplyAnimConfig(entry.frame, anim, UIParent, posRef)
        entry.frame:Show()
        entries[#entries + 1] = entry
      end
      local delay = anim.delay or 0
      if delay > 0 then
        C_Timer.After(delay, spawn)
      else
        spawn()
      end
    end
  end
end

--- Arrête immédiatement l'animation soutenue de Ruée Ardente.
function SpellEffects.StopBurningRushSustained(spellID)
  local entries = sustainedBurningRushEntries[spellID]
  if entries then
    for _, entry in ipairs(entries) do
      ReleaseModel(entry)
    end
    sustainedBurningRushEntries[spellID] = nil
  end
end

-- Preview en boucle (pour le panneau settings)
local loopEntries    = {}    -- { {entry, anchor}, ... } pour multi-orb
local loopTicker     = nil   -- ticker lent : relance le modèle à chaque cycle
local loopUpdateTick = nil   -- ticker rapide : applique position/scale/alpha en continu
local loopAnim       = nil   -- référence directe vers la table anim du DB
local loopElapsed    = 0     -- temps écoulé dans le cycle courant
local loopLastModelID = nil  -- pour détecter un changement de modèle

--- Démarre un preview en boucle d'une animation.
--- `anim` est une **référence** vers la table du DB — les sliders la modifient directement.
--- `overrideAnchors` : frame unique OU table de frames pour multi-anchor (orbs).
function SpellEffects.PreviewLoop(anim, overrideAnchors)
  SpellEffects.StopPreview()
  if not anim or not anim.modelID or anim.modelID == 0 then return end

  -- Normaliser en table d'ancres
  local anchors
  if type(overrideAnchors) == "table" and overrideAnchors[1] then
    anchors = overrideAnchors
  elseif overrideAnchors then
    anchors = { overrideAnchors }  -- frame unique
  else
    anchors = { false }  -- placeholder : nil → pas d'ancre override
  end

  -- Créer un modèle de preview par ancre
  for _, anchor in ipairs(anchors) do
    local entry = AcquireModel()
    if not entry then break end
    local f = entry.frame
    local realAnchor = anchor or nil
    ApplyAnimConfig(f, anim, realAnchor)
    f:Show()
    loopEntries[#loopEntries + 1] = { entry = entry, anchor = realAnchor }
  end
  if #loopEntries == 0 then return end

  loopAnim = anim
  loopElapsed = 0
  loopLastModelID = tonumber(anim.modelID)

  -- Ticker rapide (~30 fps) : ré-applique TOUTES les propriétés en continu
  loopUpdateTick = C_Timer.NewTicker(0.033, function()
    if #loopEntries == 0 or not loopAnim then return end
    local a = loopAnim

    -- Détecter changement de modèle → recharger sur toutes les copies
    local mid = tonumber(a.modelID) or 0
    local modelChanged = (mid ~= loopLastModelID)
    if modelChanged then
      loopLastModelID = mid
      loopElapsed = 0
    end

    for _, le in ipairs(loopEntries) do
      local ef = le.entry.frame
      local anchor = le.anchor or GetAnchor()

      if modelChanged then
        ef:ClearModel()
        pcall(function() ef:SetModel(mid) end)
      end

      -- Position / Rotation
      pcall(function() ef:SetPosition(a.z or 0, a.x or 0, a.y or 0) end)
      pcall(function() ef:SetFacing(math.rad(a.rotation or 0)) end)

      -- Scale
      local sz = (a.scale or 1) * GetBaseSizeForAnchor(anchor)
      ef:SetSize(sz, sz)

      -- Alpha
      ef:SetAlpha(a.alpha or 1)

      -- Anchor
      ef:ClearAllPoints()
      ef:SetPoint("CENTER", anchor, "CENTER", a.anchorX or 0, a.anchorY or 0)

      -- Strata (même logique que ApplyAnimConfig — détection par anchor)
      local strata = a.strata or "BACKGROUND"
      local anchorName = anchor.GetName and anchor:GetName() or ""
      local isOoc = (anchorName == "AishCoreHealthRing")
      local isOrb = anchorName:find("^AishCoreSecDot") or anchorName:find("^AishCoreOCSecDot")

      if isOrb then
        if strata == "FOREGROUND" then
          ef:SetFrameStrata(anchor:GetFrameStrata())
          ef:SetFrameLevel(anchor:GetFrameLevel() + 3)
        else
          ef:SetFrameStrata(anchor:GetFrameStrata())
          ef:SetFrameLevel(math.max(1, anchor:GetFrameLevel() - 1))
        end
      elseif isOoc then
        if strata == "FOREGROUND" then
          ef:SetFrameStrata("MEDIUM")
          ef:SetFrameLevel(anchor:GetFrameLevel() + 10)
        elseif strata == "HIGH" or strata == "MEDIUM" then
          local tf = ns.healthRingTextFrame
          local targetLevel = tf and (tf:GetFrameLevel() - 1) or (anchor:GetFrameLevel() + 4)
          ef:SetFrameStrata(anchor:GetFrameStrata())
          ef:SetFrameLevel(targetLevel)
        else
          ef:SetFrameStrata("BACKGROUND")
        end
      else
        if strata == "FOREGROUND" then
          ef:SetFrameStrata("HIGH")
        elseif strata == "MEDIUM" or strata == "HIGH" then
          local tf = ns.ringBarTextFrame
          local targetLevel = tf and (tf:GetFrameLevel() - 1) or (anchor:GetFrameLevel() + 4)
          ef:SetFrameStrata("MEDIUM")
          ef:SetFrameLevel(targetLevel)
        else
          ef:SetFrameStrata("BACKGROUND")
        end
      end
    end

    -- Cycle : relancer les modèles quand duration est atteinte
    loopElapsed = loopElapsed + 0.033
    local dur = math.max(0.1, a.duration or DEFAULT_DUR)
    if loopElapsed >= dur then
      loopElapsed = 0
      for _, le in ipairs(loopEntries) do
        le.entry.frame:ClearModel()
        pcall(function() le.entry.frame:SetModel(mid) end)
      end
    end
  end)
end

--- Stoppe le preview en boucle.
function SpellEffects.StopPreview()
  if loopTicker then loopTicker:Cancel(); loopTicker = nil end
  if loopUpdateTick then loopUpdateTick:Cancel(); loopUpdateTick = nil end
  for _, le in ipairs(loopEntries) do
    ReleaseModel(le.entry)
  end
  wipe(loopEntries)
  loopAnim = nil
  loopElapsed = 0
  loopLastModelID = nil
end

--- Retourne true si un preview loop est actif.
function SpellEffects.IsPreviewLooping()
  return #loopEntries > 0
end

-- Preview Combo en boucle
local comboLoopTicker     = nil   -- ticker qui relance le combo
local comboLoopUpdateTick = nil   -- ticker rapide : reapplique position/scale/alpha en continu
local comboLoopCombo      = nil   -- référence vers le combo DB
local comboLoopAnchor     = nil   -- ancre alternative
local comboLoopLiveEntries = {}   -- { {anim=, entry=, anchor=}, ... } modeles actuellement affiches

--- Démarre un preview combo en boucle.
--- overrideAnchors : frame unique, table de frames, ou nil.
function SpellEffects.PreviewComboLoop(combo, overrideAnchors)
  SpellEffects.StopComboPreview()
  if not combo or #combo == 0 then return end
  comboLoopCombo = combo

  -- Normaliser en table d'ancres
  local anchors
  if type(overrideAnchors) == "table" and overrideAnchors[1] then
    anchors = overrideAnchors
  elseif overrideAnchors then
    anchors = { overrideAnchors }
  else
    anchors = { false }
  end
  comboLoopAnchor = anchors

  local function onSpawn(anim, entry, anchor)
    comboLoopLiveEntries[#comboLoopLiveEntries + 1] = { anim = anim, entry = entry, anchor = anchor }
  end

  -- Jouer une première fois sur toutes les ancres
  for _, anchor in ipairs(anchors) do
    PlayCombo(combo, anchor or nil, onSpawn)
  end

  -- Calculer la durée totale du combo (max delay + duration)
  local function CalcTotalDur()
    local total = 0
    for _, a in ipairs(combo) do
      local d = (a.delay or 0) + (a.duration or DEFAULT_DUR)
      if d > total then total = d end
    end
    return math.max(0.5, total)
  end

  -- Ticker qui relance le combo à chaque cycle
  local totalDur = CalcTotalDur()
  comboLoopTicker = C_Timer.NewTicker(totalDur, function()
    if not comboLoopCombo then return end
    local newDur = CalcTotalDur()
    for _, anchor in ipairs(anchors) do
      PlayCombo(comboLoopCombo, anchor or nil, onSpawn)
    end
    if math.abs(newDur - totalDur) > 0.05 then
      totalDur = newDur
      if comboLoopTicker then comboLoopTicker:Cancel() end
      comboLoopTicker = C_Timer.NewTicker(totalDur, function()
        if not comboLoopCombo then return end
        for _, anchor in ipairs(anchors) do
          PlayCombo(comboLoopCombo, anchor or nil, onSpawn)
        end
      end)
    end
  end)

  -- Ticker rapide (~15 fps) : réapplique position/rotation/échelle/alpha en direct sur les modèles
  -- déjà affichés, sans rappeler SetModel, pour que les sliders soient visibles avant le prochain cycle.
  comboLoopUpdateTick = C_Timer.NewTicker(0.066, function()
    for i = #comboLoopLiveEntries, 1, -1 do
      local le = comboLoopLiveEntries[i]
      if not le.entry.inUse then
        table.remove(comboLoopLiveEntries, i)
      else
        local ef = le.entry.frame
        local a = le.anim
        local anchor = le.anchor or GetAnchor()
        pcall(function() ef:SetPosition(a.z or 0, a.x or 0, a.y or 0) end)
        pcall(function() ef:SetFacing(math.rad(a.rotation or 0)) end)
        local sz = (a.scale or 1) * GetBaseSizeForAnchor(anchor)
        ef:SetSize(sz, sz)
        ef:SetAlpha(a.alpha or 1)
        ef:ClearAllPoints()
        ef:SetPoint("CENTER", anchor, "CENTER", a.anchorX or 0, a.anchorY or 0)
      end
    end
  end)
end

--- Stoppe le preview combo en boucle.
function SpellEffects.StopComboPreview()
  if comboLoopTicker then comboLoopTicker:Cancel(); comboLoopTicker = nil end
  if comboLoopUpdateTick then comboLoopUpdateTick:Cancel(); comboLoopUpdateTick = nil end
  wipe(comboLoopLiveEntries)
  comboLoopCombo = nil
  comboLoopAnchor = nil
  -- Libérer tous les modèles en cours
  for i = 1, poolSize do
    if pool[i].inUse then ReleaseModel(pool[i]) end
  end
end

--- Retourne true si un preview combo loop est actif.
function SpellEffects.IsComboPreviewLooping()
  return comboLoopCombo ~= nil
end

--- Retourne l'ancre utilisée (pour le panneau settings).
function SpellEffects.GetAnchor()
  return GetAnchor()
end

--- Joue un combo sur un frame alternatif (globes externes, cercle OOC, etc.).
function SpellEffects.PlayOnAnchor(combo, anchorFrame)
  if not combo or #combo == 0 or not anchorFrame then return end
  PlayCombo(combo, anchorFrame)
end

--- Retourne le frame du cercle de vie OOC.
function SpellEffects.GetOocAnchor()
  return _G["AishCoreHealthRing"]
end

--- Retourne le frame d'un globe externe par index.
function SpellEffects.GetSecDotAnchor(idx)
  return _G["AishCoreSecDot" .. (idx or 1)]
end

--- Applique les settings.
function SpellEffects.ApplySettings()
  -- Coupure immédiate si le toggle Raid/Groupe bloque désormais les animations réelles.
  if AnimationsBlockedByGroupState() then
    SpellEffects.StopAll()
  end
  SpellEffects.RefreshDecorations()
end

-- Animations décoratives soutenues (OOC cercle, globes externes) : tournent tant que l'ancre est visible.
local decoPool     = {}   -- { frame, inUse, tag }
local decoPoolSize = 0
local MAX_DECO     = 24

-- Forward-declare pour le guard dans StartOocDeco / StartOrbDeco
local decoPreviewEntries = {}   -- { { entry, anim, anchor, lastModelID }, ... }
local decoPreviewTicker  = nil
local guiSuppressDeco    = false -- true quand le panneau Animations 3D est ouvert

--- Active/désactive la suppression des décos réelles (panneau GUI ouvert).
function SpellEffects.SetGuiMode(on)
  guiSuppressDeco = (on == true)
  if guiSuppressDeco then
    SpellEffects.StopAllDeco()
  else
    SpellEffects.RefreshDecorations()
  end
end

-- Mapping clé d'orbe → type de pouvoir (pour logique « max »)
local KEY_TO_POWER = {
  combo     = Enum.PowerType.ComboPoints,
  holypower = Enum.PowerType.HolyPower,
  chi       = Enum.PowerType.Chi,
}
-- Mapping spé DK → racine de clé rune active (les 3 types sont configurés
-- séparément mais seul celui de la spé courante doit s'afficher)
local _DK_SPEC_RUNE = {
  [250] = "rune_blood",
  [251] = "rune_frost",
  [252] = "rune_unholy",
}
local _lastAtMax    = {}    -- [root] = bool
local _lastStealth  = false -- dernier état stealth connu (falback UNIT_POWER_FREQUENT)

--- Extrait la racine d'une clé d'orbe qualifiée ("combo_max_ROGUE" → "combo").
--- Gère aussi les variantes de spé : "essence_spec1_EVOKER" → "essence".
local function OrbRootKey(qualifiedKey, cls)
  local base = qualifiedKey:sub(1, -(#cls + 2))   -- strip "_CLASS"
  return base:gsub("_max", ""):gsub("_stealth", ""):gsub("_spec%d+", "")
end

--- Vérifie si le joueur est au max de la ressource liée à cette racine.
local function IsAtMaxPower(root)
  local pt = KEY_TO_POWER[root]
  if not pt then return false end
  local cur = UnitPower("player", pt)
  local mx  = UnitPowerMax("player", pt)
  return mx > 0 and cur >= mx
end

local function AcquireDecoModel(tag)
  -- Chercher un modèle libre avec le même tag ou inutilisé
  for i = 1, decoPoolSize do
    if not decoPool[i].inUse then
      decoPool[i].inUse = true
      decoPool[i].tag = tag
      return decoPool[i]
    end
  end
  if decoPoolSize >= MAX_DECO then return nil end
  decoPoolSize = decoPoolSize + 1
  local f = CreateFrame("PlayerModel", "AishCoreDecoPool" .. decoPoolSize, UIParent)
  f:SetSize(200, 200)
  f:SetKeepModelOnHide(true)
  f:Hide()
  local entry = { frame = f, inUse = true, tag = tag, ticker = nil, fadeTicker = nil }
  decoPool[decoPoolSize] = entry
  return entry
end

local function ReleaseDecoModel(entry)
  if not entry then return end
  if entry.ticker then entry.ticker:Cancel(); entry.ticker = nil end
  if entry.fadeTicker then entry.fadeTicker:Cancel(); entry.fadeTicker = nil end
  entry.frame:Hide()
  entry.frame:SetAlpha(1)
  entry.inUse = false
  entry.tag = nil
  entry.anim = nil
  entry.anchor = nil
end

local function ReleaseDecoByTag(tag)
  for i = 1, decoPoolSize do
    if decoPool[i].inUse and decoPool[i].tag == tag then
      ReleaseDecoModel(decoPool[i])
    end
  end
end

--- Joue un combo en boucle décorative sur un anchor donné.
--- Chaque anim du combo tourne en boucle indépendamment.
--- tag : identifiant unique pour pouvoir stopper ces décos plus tard.
local function StartDecoLoop(combo, anchor, tag)
  if not combo or #combo == 0 or not anchor then return end
  for _, anim in ipairs(combo) do
    if anim.enabled ~= false and anim.modelID and anim.modelID ~= 0 then
      local entry = AcquireDecoModel(tag)
      if not entry then return end
      entry.anim = anim       -- référence pour le GUI refresh
      entry.anchor = anchor   -- ancre pour le GUI refresh
      local f = entry.frame
      ApplyAnimConfig(f, anim, anchor)
      f:Show()
      -- Pas de boucle forcée : le modèle 3D loop nativement s'il est conçu pour
    end
  end
end

-- État des décorations actives
local decoOocActive = false   -- déco OOC en cours
local decoOrbActive = false   -- déco orbes en cours
local _lastOrbDotSnapshot  = 0
local _lastRuneReadyStates = {}  -- [i] = bool, état prêt de chaque rune DK
local _lastEssenceBurst    = false -- dernier état Essence Burst Evoker
local _lastOrbValidKeySnap = ""   -- empreinte des clés actives (détecte arcane_charges→_full, etc.)
local _orbRefreshTicker = nil

--- Retourne true si la clé d'orbe est de type rune DK.
local function IsRuneKey(key)
  return key:find("^rune_") ~= nil
end

--- Retourne true si la liste contient au moins une clé de type rune.
local function HasAnyRuneKey(validKeys)
  for _, k in ipairs(validKeys) do
    if IsRuneKey(k) then return true end
  end
  return false
end

--- Retourne true si la rune i est prête (non en CD).
local function IsRuneReady(i)
  local ok, _, _, ready = pcall(GetRuneCooldown, i)
  return ok and ready == true
end

--- Migration unique : déplace les anciennes clés non qualifiées vers les clés par classe.
local _oocMigrated = false
local function MigrateOocLegacyKeys()
  if _oocMigrated then return end
  _oocMigrated = true
  local cfg = ns.GetCfg("spellEffects")
  if not cfg then return end
  local oocCombos = cfg.oocCombos
  if not oocCombos then return end
  local _, cls = UnitClass("player")
  cls = cls or ""

  -- "global" → "global_CLASS"
  if oocCombos["global"] and #oocCombos["global"] > 0 then
    local newKey = "global_" .. cls
    if not oocCombos[newKey] or #oocCombos[newKey] == 0 then
      oocCombos[newKey] = oocCombos["global"]
    end
    oocCombos["global"] = nil
  end

  -- "spec_N" → "spec_CLASS_N"
  for i = 1, 5 do
    local old = "spec_" .. i
    if oocCombos[old] and #oocCombos[old] > 0 then
      local newKey = "spec_" .. cls .. "_" .. i
      if not oocCombos[newKey] or #oocCombos[newKey] == 0 then
        oocCombos[newKey] = oocCombos[old]
      end
      oocCombos[old] = nil
    end
  end
end

--- Résout le combo OOC à utiliser : spé courante puis fallback "global" (par classe).
local function ResolveOocCombo()
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return nil end
  local oocCombos = cfg.oocCombos
  if not oocCombos then return nil end
  local _, cls = UnitClass("player")
  cls = cls or ""
  -- Chercher combo pour la spé active (clé qualifiée par classe)
  local specIdx = GetSpecialization and GetSpecialization()
  if specIdx then
    local specKey = "spec_" .. cls .. "_" .. specIdx
    local combo = oocCombos[specKey]
    if combo and #combo > 0 then return combo end
  end
  -- Fallback : global de la classe
  local globalKey = "global_" .. cls
  local global = oocCombos[globalKey]
  if global and #global > 0 then return global end
  return nil
end

--- Démarre les décorations OOC sur le cercle de vie.
function SpellEffects.StartOocDeco()
  if decoOocActive then return end
  if guiSuppressDeco or #decoPreviewEntries > 0 then return end
  if AnimationsBlockedByGroupState() then return end
  local combo = ResolveOocCombo()
  if not combo then return end
  local anchor = _G["AishCoreHealthRing"]
  if not anchor then return end
  decoOocActive = true
  StartDecoLoop(combo, anchor, "ooc")
end

--- Stoppe les décorations OOC.
function SpellEffects.StopOocDeco()
  if not decoOocActive then return end
  decoOocActive = false
  ReleaseDecoByTag("ooc")
end

--- Synchronise le fade des décorations OOC avec l'animation du cercle de vie (HealthCircle.AnimateVisibility).
function SpellEffects.AnimateOocDeco(shouldShow, duration)
  for i = 1, decoPoolSize do
    local entry = decoPool[i]
    if entry.inUse and entry.tag == "ooc" then
      if entry.fadeTicker then entry.fadeTicker:Cancel(); entry.fadeTicker = nil end
      local f = entry.frame
      local targetAlpha = shouldShow and (entry.anim and (entry.anim.alpha or 1) or 1) or 0
      if shouldShow then f:SetAlpha(0) end   -- repartir de 0 pour un fade-in propre
      local startAlpha = f:GetAlpha()
      local elapsed = 0
      local interval = 0.016
      entry.fadeTicker = C_Timer.NewTicker(interval, function(ticker)
        elapsed = elapsed + interval
        local pct = math.min(1, elapsed / duration)
        local ea  = 1 - (1 - pct) ^ 3   -- même easing cubique que AnimateStagger
        f:SetAlpha(startAlpha + (targetAlpha - startAlpha) * ea)
        if pct >= 1 then
          ticker:Cancel()
          entry.fadeTicker = nil
        end
      end)
    end
  end
end

--- Comptage de secDots visibles pour détecter les changements.
local function GetVisibleDotCount()
  local n = 0
  for i = 1, 10 do
    local dot = _G["AishCoreSecDot" .. i] or _G["AishCoreOCSecDot" .. i]
    if dot and dot:IsShown() then n = n + 1 end
  end
  return n
end

--- Détecte stealth et états similaires de façon robuste.
--- Utilise IsStealthed() ET l'index de la barre bonus (Rogue : barre stealth active).
local function IsInStealth()
  if IsStealthed and IsStealthed() then return true end
  -- La barre bonus change quand le rogue passe en stealth/shadow dance
  local bi = GetBonusBarIndex and GetBonusBarIndex()
  if bi and bi ~= 0 then
    local _, cls = UnitClass("player")
    if cls == "ROGUE" then return true end
  end
  return false
end

--- Calcule les clés d'orbes valides pour l'état actuel (classe, stealth, max).
--- Factorisé pour être utilisé par StartOrbDeco ET par le ticker différentiel.
local function GetValidOrbKeys()
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.orbCombos then return {}, nil end
  if cfg.orbsEnabled == false then return {}, nil end
  local orbCombos = cfg.orbCombos
  local _, cls = UnitClass("player")
  cls = cls or ""
  local stealthed = IsInStealth()
  local validKeys = {}
  for key, combo in pairs(orbCombos) do
    if key:sub(-(#cls + 1)) == "_" .. cls and combo and #combo > 0 then
      local base      = key:sub(1, -(#cls + 2))          -- ex. "combo", "combo_max", "combo_stealth"
      local isStealth = (base:find("stealth") ~= nil)
      local root      = OrbRootKey(key, cls)              -- ex. "combo"
      local isMaxKey  = (base:find("_max") ~= nil)

      local include = true

      -- Règle stealth : une seule variante active à la fois
      if isStealth and not stealthed then
        include = false  -- clé stealth ignorée hors stealth
      elseif not isStealth and stealthed then
        -- clé normale masquée si une variante stealth équivalente existe
        local stealthEq = base .. "_stealth_" .. cls
        if orbCombos[stealthEq] and #orbCombos[stealthEq] > 0 then
          include = false
        end
      end

      -- Règle max : une seule variante active à la fois
      if include then
        local pt = KEY_TO_POWER[root]
        if pt then
          local atMax = IsAtMaxPower(root)
          _lastAtMax[root] = atMax
          if isMaxKey then
            if not atMax then include = false end
          else
            local maxEq = isStealth and (root .. "_max_stealth_" .. cls)
                                     or (base .. "_max_" .. cls)
            if atMax and orbCombos[maxEq] and #orbCombos[maxEq] > 0 then
              include = false
            end
          end
        end
      end

      -- Règle runes DK : n'activer que la clé de la spé courante
      if include and cls == "DEATHKNIGHT" and root:find("^rune_") then
        local specIdx = GetSpecialization and GetSpecialization()
        local specID  = specIdx and select(1, GetSpecializationInfo(specIdx)) or nil
        local specRune = _DK_SPEC_RUNE[specID]
        if specRune ~= root then include = false end
      end

      -- Règles Evoker : essence_burst seulement si le proc est actif ; variantes de spé prioritaires sur la clé globale.
      if include and cls == "EVOKER" then
        local RC = ns.Modules and ns.Modules.ResourceCircle
        local burstActive = RC and RC.IsEssenceBurstActive and RC.IsEssenceBurstActive()
        local specIdx = GetSpecialization and GetSpecialization()
        local burstGlobalKey = "essence_burst_" .. cls
        local burstSpecKey   = specIdx and ("essence_burst_spec" .. specIdx .. "_" .. cls)
        local burstConfigured = (orbCombos[burstGlobalKey] and #orbCombos[burstGlobalKey] > 0)
                             or (burstSpecKey and orbCombos[burstSpecKey] and #orbCombos[burstSpecKey] > 0)
        if base:find("_spec%d+$") then
          -- Clé de variante de spé : n'inclure que si elle correspond à la spé active
          local keySpecIdx = tonumber(base:match("_spec(%d+)$"))
          if keySpecIdx ~= specIdx then include = false end
        else
          -- Clé globale : exclure si une variante de spé pour la spé active existe
          if specIdx then
            local specVarKey = base .. "_spec" .. specIdx .. "_" .. cls
            if orbCombos[specVarKey] and #orbCombos[specVarKey] > 0 then
              include = false
            end
          end
        end
        if include then
          if root == "essence_burst" then
            -- N'afficher que si le proc est actif
            if not burstActive then include = false end
          elseif root == "essence" then
            -- Masquer les globes d'essence normaux si burst est configuré ET actif
            if burstConfigured and burstActive then include = false end
          end
        end
      end

      -- Règles Mage Arcane : arcane_charges_full uniquement si 4/4 ;
      -- masquer arcane_charges de base si _full est configuré ET à max
      if include and cls == "MAGE" then
        local ac    = UnitPower("player", Enum.PowerType.ArcaneCharges or 16)
        local acMax = UnitPowerMax("player", Enum.PowerType.ArcaneCharges or 16)
        local atFull = acMax > 0 and ac >= acMax
        local fullKey = "arcane_charges_full_" .. cls
        local fullConfigured = orbCombos[fullKey] and #orbCombos[fullKey] > 0
        if root == "arcane_charges_full" then
          -- N'afficher que si charges = 4/4
          if not atFull then include = false end
        elseif root == "arcane_charges" then
          -- Masquer si _full est configuré ET les charges sont pleines
          if fullConfigured and atFull then include = false end
        end
      end

      -- Warlock Demonologie : orbes Coeur demoniaque désactivées (lecture des charges peu fiable en combat).
      if include and cls == "WARLOCK" and (root == "demonic_core" or root == "demonic_core_max") then
        include = false
      end

      if include then validKeys[#validKeys + 1] = key end
    end
  end
  return validKeys, orbCombos
end

--- Ajoute des modèles pour les dots visibles qui n'en ont pas encore.
--- Appelé sans stop/restart pour éviter le clignotement.
local function OrbDecoAddNewDots()
  if not decoOrbActive then return end
  local animated = {}
  for i = 1, decoPoolSize do
    local e = decoPool[i]
    if e.inUse and e.tag then
      local idx = tonumber(e.tag:match("_dot(%d+)$"))
      if idx then animated[idx] = true end
    end
  end
  local validKeys, orbCombos = GetValidOrbKeys()
  if not orbCombos then return end
  for i = 1, 10 do
    local dot = _G["AishCoreSecDot" .. i] or _G["AishCoreOCSecDot" .. i]
    if dot and dot:IsShown() and not animated[i] then
      for _, key in ipairs(validKeys) do
        if not IsRuneKey(key) or IsRuneReady(i) then
          StartDecoLoop(orbCombos[key], dot, "orb_" .. key .. "_dot" .. i)
        end
      end
    end
  end
end

--- Forward-declare StartOrbDeco (utilisé par le ticker).
local _startOrbDecoRef

--- Ticker différentiel : ajoute/retire les décos des dots qui ont changé d'état.
--- Pas de stop/restart global → pas de clignotement sur chaque nouveau globe.
local function StartOrbRefreshTicker()
  if _orbRefreshTicker then return end
  _lastOrbDotSnapshot = GetVisibleDotCount()
  _orbRefreshTicker = C_Timer.NewTicker(0.25, function()
    if not decoOrbActive then
      if _orbRefreshTicker then _orbRefreshTicker:Cancel(); _orbRefreshTicker = nil end
      return
    end
    local validKeys, orbCombos = GetValidOrbKeys()
    if not orbCombos then return end
    local hasRunes = HasAnyRuneKey(validKeys)

    local cur = GetVisibleDotCount()
    local dotCountChanged = (cur ~= _lastOrbDotSnapshot)
    if dotCountChanged then _lastOrbDotSnapshot = cur end

    -- Retrouver quels dots sont déjà animés
    local animated = {}
    for i = 1, decoPoolSize do
      local e = decoPool[i]
      if e.inUse and e.tag then
        local idx = tonumber(e.tag:match("_dot(%d+)$"))
        if idx then animated[idx] = true end
      end
    end

    -- Gestion dots apparaissant / disparaissant (count changed)
    if dotCountChanged then
      for i = 1, 10 do
        local dot = _G["AishCoreSecDot" .. i] or _G["AishCoreOCSecDot" .. i]
        local visible = dot and dot:IsShown()
        if visible and not animated[i] then
          for _, key in ipairs(validKeys) do
            if not IsRuneKey(key) or IsRuneReady(i) then
              StartDecoLoop(orbCombos[key], dot, "orb_" .. key .. "_dot" .. i)
            end
          end
          if hasRunes then _lastRuneReadyStates[i] = IsRuneReady(i) end
        elseif not visible and animated[i] then
          for j = 1, decoPoolSize do
            local e = decoPool[j]
            if e.inUse and e.tag and tonumber(e.tag:match("_dot(%d+)$")) == i then
              ReleaseDecoModel(e)
            end
          end
        end
      end
    end

    -- Gestion état rune (prête ↔ en CD) même si le nombre de dots n'a pas changé
    if hasRunes then
      for i = 1, 6 do
        local ready = IsRuneReady(i)
        if ready ~= _lastRuneReadyStates[i] then
          _lastRuneReadyStates[i] = ready
          local dot = _G["AishCoreSecDot" .. i] or _G["AishCoreOCSecDot" .. i]
          if dot and dot:IsShown() then
            if ready then
              -- Rune rechargée : démarrer l'animation sur ce dot
              for _, key in ipairs(validKeys) do
                if IsRuneKey(key) then
                  StartDecoLoop(orbCombos[key], dot, "orb_" .. key .. "_dot" .. i)
                end
              end
            else
              -- Rune en CD : retirer les animations de rune sur ce dot uniquement
              for j = 1, decoPoolSize do
                local e = decoPool[j]
                if e.inUse and e.tag
                   and tonumber(e.tag:match("_dot(%d+)$")) == i
                   and e.tag:find("^orb_rune_") then
                  ReleaseDecoModel(e)
                end
              end
            end
          end
        end
      end
    end
    -- Gestion changement de l'ensemble des clés actives : couvre Essence Burst Evoker,
    -- Charges Arcaniques (arcane_charges ↔ arcane_charges_full), et tout futur cas _max/_full.
    do
      table.sort(validKeys)
      local snapStr = table.concat(validKeys, "|")
      if snapStr ~= _lastOrbValidKeySnap then
        _lastOrbValidKeySnap = snapStr
        -- Synchroniser _lastEssenceBurst pour éviter un déclenchement redondant
        local RC2 = ns.Modules and ns.Modules.ResourceCircle
        _lastEssenceBurst = RC2 and RC2.IsEssenceBurstActive and RC2.IsEssenceBurstActive() or false
        SpellEffects.StopOrbDeco()
        if _startOrbDecoRef then _startOrbDecoRef() end
        return  -- le nouveau ticker prend le relais
      end
    end
  end)
end

--- Démarre les décorations sur les globes externes (combo points, runes, etc.).
--- Duplique chaque combo sur CHAQUE secDot visible individuellement.
--- Les clés orbCombos sont qualifiées par classe : "combo_ROGUE", "rune_frost_DEATHKNIGHT", etc.
function SpellEffects.StartOrbDeco()
  if decoOrbActive then return end
  if guiSuppressDeco or #decoPreviewEntries > 0 then return end
  local cfg = ns.GetCfg("spellEffects")
  if not cfg or not cfg.enabled then return end
  if AnimationsBlockedByGroupState() then return end
  local validKeys, orbCombos = GetValidOrbKeys()
  if not orbCombos or #validKeys == 0 then return end
  decoOrbActive = true
  for i = 1, 10 do
    local dot = _G["AishCoreSecDot" .. i] or _G["AishCoreOCSecDot" .. i]
    if dot and dot:IsShown() then
      for _, key in ipairs(validKeys) do
        -- Pour les runes DK : n'animer que si la rune est prête
        if not IsRuneKey(key) or IsRuneReady(i) then
          StartDecoLoop(orbCombos[key], dot, "orb_" .. key .. "_dot" .. i)
        end
      end
    end
  end
  -- Initialiser le snapshot d'état des runes
  for i = 1, 6 do _lastRuneReadyStates[i] = IsRuneReady(i) end
  -- Initialiser le snapshot Essence Burst
  do
    local RC2 = ns.Modules and ns.Modules.ResourceCircle
    _lastEssenceBurst = RC2 and RC2.IsEssenceBurstActive and RC2.IsEssenceBurstActive() or false
  end
  -- Initialiser la snapshot des clés actives (pour le ticker différentiel)
  do
    local snap = {unpack(validKeys)}
    table.sort(snap)
    _lastOrbValidKeySnap = table.concat(snap, "|")
  end
  StartOrbRefreshTicker()
  -- Appliquer la couleur de globe de la première clé active qui en a une
  local RC = ns.Modules.ResourceCircle
  if RC and RC.SetSecDotColorOverride then
    local globeColors = cfg.orbGlobeColors
    local oc = nil
    if globeColors then
      for _, key in ipairs(validKeys) do
        if globeColors[key] then oc = globeColors[key]; break end
      end
    end
    if oc then
      RC.SetSecDotColorOverride(oc[1], oc[2], oc[3])
    else
      RC.ClearSecDotColorOverride()
    end
  end
end
_startOrbDecoRef = SpellEffects.StartOrbDeco

--- Stoppe les décorations orbes.
function SpellEffects.StopOrbDeco()
  if not decoOrbActive then return end
  decoOrbActive = false
  if _orbRefreshTicker then _orbRefreshTicker:Cancel(); _orbRefreshTicker = nil end
  for i = 1, decoPoolSize do
    if decoPool[i].inUse and decoPool[i].tag and decoPool[i].tag:find("^orb_") then
      ReleaseDecoModel(decoPool[i])
    end
  end
  -- Restaurer la couleur des globes
  local RC = ns.Modules.ResourceCircle
  if RC and RC.ClearSecDotColorOverride then RC.ClearSecDotColorOverride() end
end

--- Stoppe toutes les décorations.
function SpellEffects.StopAllDeco()
  SpellEffects.StopOocDeco()
  SpellEffects.StopOrbDeco()
end

--- Rafraîchit les décorations (stop + restart si frames visibles).
function SpellEffects.RefreshDecorations()
  SpellEffects.StopAllDeco()
  -- OOC
  local oocRing = _G["AishCoreHealthRing"]
  if oocRing and oocRing:IsShown() then
    SpellEffects.StartOocDeco()
  end
  -- Orbes : relancer si au moins un secDot est visible
  if GetVisibleDotCount() > 0 then
    SpellEffects.StartOrbDeco()
  end
end

-- Deco Preview : modèles persistants 30 fps pour la preview OOC/Orbes du panneau Settings.

--- Démarre une preview décorative persistante.
--- combo : table d'animations ; overrideAnchors : frame, table de frames, ou nil.
function SpellEffects.StartDecoPreview(combo, overrideAnchors)
  SpellEffects.StopDecoPreview()
  SpellEffects.StopAllDeco()  -- arrête les décos réelles pour éviter les doublons
  if not combo or #combo == 0 then return end

  -- Normaliser en table d'ancres
  local anchors
  if type(overrideAnchors) == "table" and overrideAnchors[1] then
    anchors = overrideAnchors
  elseif overrideAnchors then
    anchors = { overrideAnchors }
  else
    anchors = { false }
  end

  -- Créer un modèle par anim × ancre
  for _, anim in ipairs(combo) do
    if anim.enabled ~= false and anim.modelID and anim.modelID ~= 0 then
      for _, anchor in ipairs(anchors) do
        local entry = AcquireDecoModel("deco_preview")
        if not entry then break end
        local realAnchor = anchor or nil
        entry.anim = anim
        entry.anchor = realAnchor
        ApplyAnimConfig(entry.frame, anim, realAnchor)
        entry.frame:Show()
        decoPreviewEntries[#decoPreviewEntries + 1] = {
          entry = entry,
          anim = anim,
          anchor = realAnchor,
          lastModelID = tonumber(anim.modelID),
        }
      end
    end
  end

  if #decoPreviewEntries == 0 then return end

  -- Ticker 30 fps : applique les propriétés en continu (sliders en temps réel)
  decoPreviewTicker = C_Timer.NewTicker(0.033, function()
    if #decoPreviewEntries == 0 then return end
    for _, de in ipairs(decoPreviewEntries) do
      local ef = de.entry.frame
      local a  = de.anim
      local anchor = de.anchor or GetAnchor()

      -- Changement de modèle
      local mid = tonumber(a.modelID) or 0
      if mid ~= de.lastModelID then
        de.lastModelID = mid
        ef:ClearModel()
        pcall(function() ef:SetModel(mid) end)
      end

      -- Position / Rotation
      pcall(function() ef:SetPosition(a.z or 0, a.x or 0, a.y or 0) end)
      pcall(function() ef:SetFacing(math.rad(a.rotation or 0)) end)

      -- Scale
      local sz = (a.scale or 1) * GetBaseSizeForAnchor(anchor)
      ef:SetSize(sz, sz)

      -- Alpha
      ef:SetAlpha(a.alpha or 1)

      -- Anchor
      ef:ClearAllPoints()
      ef:SetPoint("CENTER", anchor, "CENTER", a.anchorX or 0, a.anchorY or 0)

      -- Strata
      local strata = a.strata or "BACKGROUND"
      local anchorName = anchor.GetName and anchor:GetName() or ""
      local isOoc = (anchorName == "AishCoreHealthRing")
      local isOrb = anchorName:find("^AishCoreSecDot") or anchorName:find("^AishCoreOCSecDot")

      if isOrb then
        if strata == "FOREGROUND" then
          ef:SetFrameStrata(anchor:GetFrameStrata())
          ef:SetFrameLevel(anchor:GetFrameLevel() + 3)
        else
          ef:SetFrameStrata(anchor:GetFrameStrata())
          ef:SetFrameLevel(math.max(1, anchor:GetFrameLevel() - 1))
        end
      elseif isOoc then
        if strata == "FOREGROUND" then
          ef:SetFrameStrata("MEDIUM")
          ef:SetFrameLevel(anchor:GetFrameLevel() + 10)
        elseif strata == "HIGH" or strata == "MEDIUM" then
          local tf = ns.healthRingTextFrame
          local targetLevel = tf and (tf:GetFrameLevel() - 1) or (anchor:GetFrameLevel() + 4)
          ef:SetFrameStrata(anchor:GetFrameStrata())
          ef:SetFrameLevel(targetLevel)
        else
          ef:SetFrameStrata("BACKGROUND")
        end
      else
        if strata == "FOREGROUND" then
          ef:SetFrameStrata("HIGH")
        elseif strata == "MEDIUM" or strata == "HIGH" then
          local tf = ns.ringBarTextFrame
          local targetLevel = tf and (tf:GetFrameLevel() - 1) or (anchor:GetFrameLevel() + 4)
          ef:SetFrameStrata("MEDIUM")
          ef:SetFrameLevel(targetLevel)
        else
          ef:SetFrameStrata("BACKGROUND")
        end
      end
    end
  end)
end

--- Stoppe la preview décorative et relance les décorations réelles.
function SpellEffects.StopDecoPreview()
  if decoPreviewTicker then decoPreviewTicker:Cancel(); decoPreviewTicker = nil end
  for _, de in ipairs(decoPreviewEntries) do
    ReleaseDecoModel(de.entry)
  end
  wipe(decoPreviewEntries)
end

--- Retourne true si une preview décorative est active.
function SpellEffects.IsDecoPreviewActive()
  return #decoPreviewEntries > 0
end

-- Boucle GUI (conservée pour compat — alias vers deco preview)
function SpellEffects.StartGuiLoop() end
function SpellEffects.StopGuiLoop() end

-- Détection de présence d'aura (combos "Auras") : joueur pour les buffs, cible pour les debuffs.
local _auraPresence = {}  -- [auraID] = true si actuellement présente
local _missingBuffActive = {}  -- [spellID] = true si actuellement affiché par le module "Buffs manquants"

--- Source → unité trackée. Un source non renseigné est traité comme buff joueur (cohérent avec RefreshAuraList).
local function AuraSourceIsPlayerBuff(source)
  return source ~= "debuff" and source ~= "equipment"
end

--- Présence d'une aura : croise plusieurs sources (hook CDM, ApplyStacksTo, caches...), aucune n'étant fiable seule.

-- Sentinelle native désactivée (SENTINEL_ENABLED=false) : Blizzard n'appelle jamais Show/Hide sur ces boutons ici (cause non identifiée) ; code gardé si ça change un jour.
local SENTINEL_ENABLED = false

local sentinelContainers = {}    -- [unit] = AuraContainer natif
local sentinelButtons = {}       -- [unit][spellID] = auraButton natif
local sentinelGroupCreated = {}  -- [unit][spellID] = true des qu'un groupe dedie existe
local sentinelPresence = {}      -- [unit][spellID] = true/false, alimenté uniquement par les hooks Show/Hide

local function EnsureSentinelContainer(unit)
  if not SENTINEL_ENABLED then return nil end
  if sentinelContainers[unit] then return sentinelContainers[unit] end
  -- Réutilise le conteneur de la destination "Icons" pour unit="player" plutôt que d'en créer un nouveau.
  if unit == "player" and ns.Auras and ns.Auras.GetIconsNativeContainer then
    local shared = ns.Auras.GetIconsNativeContainer()
    if shared then
      sentinelContainers[unit] = shared
      return shared
    end
  end
  if InCombatLockdown and InCombatLockdown() then return nil end
  local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  if not ok or not result then return nil end
  sentinelContainers[unit] = result
  result:SetSize(8, 8)
  result:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  pcall(result.SetEnabled, result, true)
  pcall(result.SetUnit, result, unit)
  result:Show()
  -- Flow layout requis même pour un groupe dédié à 1 spellID sans besoin visuel.
  pcall(result.SetFlowLayoutAnchorPoint, result, "TOP")
  pcall(result.SetFlowLayoutAxis, result, 1)
  pcall(result.SetFlowLayoutGrowthDirection, result, 1, -1)
  pcall(result.SetFlowLayoutMaximumLineSize, result, 900)
  return result
end

local function EnsureSentinelGroup(unit, spellID)
  sentinelGroupCreated[unit] = sentinelGroupCreated[unit] or {}
  if sentinelGroupCreated[unit][spellID] then return end
  local c = EnsureSentinelContainer(unit)
  if not c then return end
  local groupKey = "aishSentinel_" .. unit .. "_" .. tostring(spellID)
  local filterStr = (unit == "player") and "HELPFUL" or "HARMFUL"
  local okAdd = pcall(function()
    c:AddAuraGroup(groupKey, filterStr, {
      maxFrameCount = 1,
      candidateFilters = { includeSpellIDs = { [spellID] = true } },
      -- layout requis pour que plusieurs groupes dédiés cohabitent sur le même conteneur.
      layout = { elementSpacing = 0, lineSpacing = 0, elementWidth = 1, elementHeight = 1, layoutIndex = 1 },
      initializeFrame = function(auraButton)
        local okCheck, canAccess = pcall(function()
          return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
        end)
        if not (okCheck and canAccess) then return end
        pcall(auraButton.SetSize, auraButton, 1, 1)
        -- SetIcon minimal (transparent) : requis par toutes les destinations natives.
        pcall(function()
          local icon = auraButton:CreateTexture(nil, "ARTWORK")
          icon:SetAllPoints(auraButton)
          icon:SetAlpha(0)
          auraButton:SetIcon(icon)
        end)
        sentinelButtons[unit] = sentinelButtons[unit] or {}
        sentinelButtons[unit][spellID] = auraButton
        sentinelPresence[unit] = sentinelPresence[unit] or {}
        -- btn:IsShown() lève une erreur "secret value" une fois lié à une vraie aura : on hooke les
        -- MÉTHODES Show/Hide (HookScript sur OnShow/OnHide est bloqué pour la même raison) sans rien lire.
        pcall(hooksecurefunc, auraButton, "Show", function()
          sentinelPresence[unit][spellID] = true
          if SpellEffects._debugAll then
            print(string.format("|cff00ffff[SE-DEBUG]|r sentinel SHOW unit=%s spellID=%d (%s) inCombat=%s",
              unit, spellID, tostring(GetSpellName(spellID)), tostring(InCombatLockdown and InCombatLockdown())))
          end
        end)
        pcall(hooksecurefunc, auraButton, "Hide", function()
          sentinelPresence[unit][spellID] = false
          if SpellEffects._debugAll then
            print(string.format("|cff00ffff[SE-DEBUG]|r sentinel HIDE unit=%s spellID=%d (%s) inCombat=%s",
              unit, spellID, tostring(GetSpellName(spellID)), tostring(InCombatLockdown and InCombatLockdown())))
          end
        end)
        -- Pas d'état initial forcé : sentinelPresence reste nil jusqu'au premier Show/Hide réellement observé.
      end,
    })
  end)
  if okAdd then
    sentinelGroupCreated[unit][spellID] = true
  end
end

-- true/false = réponse de la sentinelle native ; nil = pas encore disponible (l'appelant retombe sur les tiers Lua).
local function IsAuraActiveViaSentinel(unit, spellID)
  EnsureSentinelGroup(unit, spellID)
  if not (sentinelGroupCreated[unit] and sentinelGroupCreated[unit][spellID]) then return nil end
  return sentinelPresence[unit] and sentinelPresence[unit][spellID]
end

-- dbg (optionnel) : tier qui a répondu true, pour /sedebugcombos. Sentinelle native en premier, puis chaîne Lua de repli.
local function IsAuraActiveViaCDM(unit, spellID, dbg)
  local sentinel = IsAuraActiveViaSentinel(unit, spellID)
  if sentinel ~= nil then
    if dbg then dbg.tier = sentinel and "sentinel-true" or "sentinel-false" end
    return sentinel
  end
  -- TIER "itemFrame Buffs" : lisible en combat (contrairement aux auraButton, bloqués par le taint),
  -- seul canal fiable pour une aura sans durée ni stacks (ex: Ruée Ardente).
  if unit == "player" and ns.Auras and ns.Auras.IsCDMBuffFramePresent then
    local framePresent = ns.Auras.IsCDMBuffFramePresent(spellID)
    if framePresent ~= nil then
      if dbg then dbg.tier = framePresent and "cdmBuffFrame-true" or "cdmBuffFrame-false" end
      return framePresent
    end
  end
  -- TIER "instance pure" : combat-safe et indépendant des stacks/durée, seul canal pour un buff
  -- "simple présence" pin sans durée ni stacks réels. Consulté pour les deux unités.
  if ns.Auras and ns.Auras.IsCDMAuraInstancePresent then
    local instPresent = ns.Auras.IsCDMAuraInstancePresent(unit, spellID)
    if instPresent ~= nil then
      if dbg then dbg.tier = instPresent and "cdmInstance-true" or "cdmInstance-false" end
      return instPresent
    end
  end
  local cdmU = ns.Auras and ns.Auras.cdmData and ns.Auras.cdmData[unit]
  local entry = cdmU and cdmU[spellID]
  if not entry then if dbg then dbg.tier = "no-cdm-entry" end; return false end
  if unit == "player" then
    -- Tier 1 : présence directe, peu importe le stack count (capte les auras de simple présence
    -- que le tier 2 rejetterait à tort, ex: Main Brûlante/215785).
    local okDirect, auraDirect = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if okDirect and auraDirect ~= nil then if dbg then dbg.tier = "direct" end; return true end

    -- Tier 2 : ApplyStacksTo, capte les cas où le tier 1 échoue mais une vraie lecture de stacks réussit.
    local RC = ns.Modules and ns.Modules.ResourceCircle
    if RC and RC.ApplyStacksTo then
      local found = false
      pcall(RC.ApplyStacksTo, function() found = true; return true end, spellID)
      if found then if dbg then dbg.tier = "applystacksto" end; return true end
    end

    -- Tier 3 : cache "dernière donnée confirmée" (Scan.lua), seulement peuplé si suivi dans "Auras à tracker".
    local cached = ns.Auras and ns.Auras._lastKnownAura and ns.Auras._lastKnownAura.player and ns.Auras._lastKnownAura.player[spellID]
    if cached then if dbg then dbg.tier = "lastKnownAura" end; return true end

    -- Tier 4 : canal clone SWIPE, event-driven dès qu'un viewer CDM affiche ce spellID.
    if ns.Auras and ns.Auras.IsCDMAuraSwipePresent and ns.Auras.IsCDMAuraSwipePresent(spellID) then
      if dbg then dbg.tier = "cdmSwipePresent" end; return true
    end

    -- Tier 5 : canal clone BAR (durée/swipe sur un viewer "Barres" spécifiquement pin).
    if ns.Auras and ns.Auras.IsCDMAuraBarPresent and ns.Auras.IsCDMAuraBarPresent(spellID) then
      if dbg then dbg.tier = "cdmBarPresent" end; return true
    end
    if dbg then dbg.tier = "none" end
    return false
  end
  if dbg then dbg.tier = "non-player-unit" end
  return true
end
-- Exposée pour MissingBuffs.lua (Ruée Ardente) : même résolveur multi-tiers que ScanAuraCombos.
SpellEffects.IsAuraActiveViaCDM = IsAuraActiveViaCDM

--- Scanne tous les combos d'auras configurés et démarre/arrête les
--- animations soutenues sur transition de présence (apparition/disparition).
local function ScanAuraCombos()
  local cfg = ns.GetCfg("spellEffects")
  local auraCombos = cfg and cfg.enabled and cfg.auraCombos
  if not auraCombos then
    for auraID in pairs(_auraPresence) do
      _auraPresence[auraID] = nil
      SpellEffects.StopAuraSustained(auraID)
    end
    return
  end

  local specSpells = ns.Auras and ns.Auras.GetSpecSpells and ns.Auras.GetSpecSpells()
  for auraID, combo in pairs(auraCombos) do
    if type(auraID) == "number" and combo and #combo > 0 then
      local info = specSpells and specSpells[auraID]
      -- Ne pas forcer un source manquant à "debuff" (cf. AuraSourceIsPlayerBuff).
      local source = info and info.source
      local present
      if AuraSourceIsPlayerBuff(source) then
        present = IsAuraActiveViaCDM("player", auraID)
      else
        present = UnitExists("target") and IsAuraActiveViaCDM("target", auraID)
      end
      if SpellEffects._debugAll then
        local P = "|cff00ffff[SE-DEBUG]|r "
        print(P .. "ScanAuraCombos auraID=" .. tostring(auraID)
          .. " name=" .. tostring(GetSpellName(auraID))
          .. " source=" .. tostring(source)
          .. " present=" .. tostring(present)
          .. " wasPresent=" .. tostring(_auraPresence[auraID] or false)
          .. " #combo=" .. tostring(#combo))
      end
      if present and not _auraPresence[auraID] then
        _auraPresence[auraID] = true
        SpellEffects.StartAuraSustained(auraID)
      elseif not present and _auraPresence[auraID] then
        _auraPresence[auraID] = nil
        SpellEffects.StopAuraSustained(auraID)
      end
    end
  end

  -- Nettoyer les entrées dont le combo a disparu/été vidé entre-temps
  for auraID in pairs(_auraPresence) do
    local combo = auraCombos[auraID]
    if not (combo and #combo > 0) then
      _auraPresence[auraID] = nil
      SpellEffects.StopAuraSustained(auraID)
    end
  end
end

--- Scanne les combos "Buffs manquants" : présence lue directement depuis MissingBuffs, pas de scan d'aura.
local function ScanMissingBuffCombos()
  local cfg = ns.GetCfg("spellEffects")
  local missingBuffsCombos = cfg and cfg.enabled and cfg.missingBuffsCombos
  -- Ruee Ardente : cas spécial piloté par IsBurningRushActive (jamais d'icône d'alerte pour ce spellID).
  local burningRushID = ns.Auras and ns.Auras.MISSING_WARLOCK_BURNING_RUSH
  if not missingBuffsCombos then
    for spellID in pairs(_missingBuffActive) do
      _missingBuffActive[spellID] = nil
      if burningRushID and spellID == burningRushID then SpellEffects.StopBurningRushSustained(spellID)
      else SpellEffects.StopMissingBuffSustained(spellID) end
    end
    return
  end

  local MB = ns.Auras and ns.Auras.MissingBuffs
  local currentSpellID = MB and MB.GetCurrentAlertSpell and MB.GetCurrentAlertSpell()

  for spellID, combo in pairs(missingBuffsCombos) do
    if type(spellID) == "number" and combo and #combo > 0 then
      local isBurningRush = burningRushID and spellID == burningRushID
      local active
      if isBurningRush then
        active = MB and MB.IsBurningRushActive and MB.IsBurningRushActive() or false
      else
        active = (currentSpellID == spellID)
      end
      if active and not _missingBuffActive[spellID] then
        _missingBuffActive[spellID] = true
        if isBurningRush then SpellEffects.StartBurningRushSustained(spellID)
        else SpellEffects.StartMissingBuffSustained(spellID) end
      elseif not active and _missingBuffActive[spellID] then
        _missingBuffActive[spellID] = nil
        if isBurningRush then SpellEffects.StopBurningRushSustained(spellID)
        else SpellEffects.StopMissingBuffSustained(spellID) end
      end
    end
  end

  for spellID in pairs(_missingBuffActive) do
    local combo = missingBuffsCombos[spellID]
    if not (combo and #combo > 0) then
      _missingBuffActive[spellID] = nil
      if burningRushID and spellID == burningRushID then SpellEffects.StopBurningRushSustained(spellID)
      else SpellEffects.StopMissingBuffSustained(spellID) end
    end
  end
end
-- Exposée pour MissingBuffs.lua : permet un scan immédiat sur changement, sans attendre le ticker de 2s.
SpellEffects.ScanMissingBuffCombos = ScanMissingBuffCombos

-- /sedebugcombos : snapshot instantané de toute la chaîne (sans limite de temps, contrairement à /sedebug all).
function SpellEffects.DebugDumpAuraCombos()
  local P = "|cff00ffff[SE-DEBUG]|r "
  local cfg = ns.GetCfg("spellEffects")
  print(P .. string.format("cfg present=%s enabled=%s", tostring(cfg ~= nil), tostring(cfg and cfg.enabled)))
  local auraCombos = cfg and cfg.auraCombos
  if not auraCombos then
    print(P .. "|cffff4444cfg.auraCombos est nil/absent -- aucun combo d'aura configure, ou config non chargee.|r")
    return
  end
  local n = 0
  for _ in pairs(auraCombos) do n = n + 1 end
  print(P .. string.format("cfg.auraCombos : %d entree(s)", n))
  if n == 0 then
    print(P .. "|cffff4444Aucune entree dans auraCombos -- rien a scanner.|r")
    return
  end

  local specSpells = ns.Auras and ns.Auras.GetSpecSpells and ns.Auras.GetSpecSpells()
  print(P .. string.format("ns.Auras.GetSpecSpells() disponible=%s", tostring(specSpells ~= nil)))

  for auraID, combo in pairs(auraCombos) do
    print(P .. string.format("--- auraID=%s (%s) ---", tostring(auraID), tostring(GetSpellName(auraID))))
    if type(auraID) ~= "number" then
      print(P .. "  |cffff4444auraID n'est PAS un nombre -- ignore par ScanAuraCombos.|r")
    elseif not (combo and #combo > 0) then
      print(P .. "  |cffff4444combo vide ou absent -- ignore par ScanAuraCombos.|r")
    else
      local info = specSpells and specSpells[auraID]
      print(P .. string.format("  info (discoveredSpells) present=%s source=%s", tostring(info ~= nil), tostring(info and info.source)))
      local source = info and info.source
      local isBuff = AuraSourceIsPlayerBuff(source)
      local checkUnit = isBuff and "player" or "target"
      print(P .. string.format("  AuraSourceIsPlayerBuff=%s -> unite verifiee=%s", tostring(isBuff), checkUnit))
      if checkUnit == "target" and not UnitExists("target") then
        print(P .. "  |cffff4444pas de cible actuelle -- present sera force a false.|r")
      end
      local cdmU = ns.Auras and ns.Auras.cdmData and ns.Auras.cdmData[checkUnit]
      local entry = cdmU and cdmU[auraID]
      print(P .. string.format("  ns.Auras.cdmData[%s][%s] present=%s%s", checkUnit, tostring(auraID), tostring(entry ~= nil),
        entry and string.format(" (instID=%s)", tostring(entry.instID)) or ""))
      if checkUnit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, auraID)
        print(P .. string.format("  GetPlayerAuraBySpellID(%s) : pcall_ok=%s trouve=%s", tostring(auraID), tostring(ok), tostring(ok and aura ~= nil)))
      end
      print(P .. string.format("  Sentinelle native [%s] : groupe cree=%s bouton existe=%s presence(via hooks Show/Hide)=%s",
        checkUnit,
        tostring(sentinelGroupCreated[checkUnit] and sentinelGroupCreated[checkUnit][auraID] == true),
        tostring(sentinelButtons[checkUnit] and sentinelButtons[checkUnit][auraID] ~= nil),
        tostring(sentinelPresence[checkUnit] and sentinelPresence[checkUnit][auraID])))
      local dbg = {}
      local present = (checkUnit == "target" and not UnitExists("target")) and false or IsAuraActiveViaCDM(checkUnit, auraID, dbg)
      print(P .. string.format("  => present (live, maintenant)=%s tier=%s | _auraPresence (cache)=%s | anim soutenue active=%s",
        tostring(present), tostring(dbg.tier), tostring(_auraPresence[auraID] or false), tostring(sustainedAuraEntries[auraID] ~= nil)))
      if ns.Auras and ns.Auras.IsCDMAuraSwipePresent then
        print(P .. string.format("  IsCDMAuraSwipePresent(%s)=%s | IsCDMAuraBarPresent=%s",
          tostring(auraID), tostring(ns.Auras.IsCDMAuraSwipePresent(auraID)),
          tostring(ns.Auras.IsCDMAuraBarPresent and ns.Auras.IsCDMAuraBarPresent(auraID))))
      end
    end
  end
end

SLASH_SEDEBUGCOMBOS1 = "/sedebugcombos"
SlashCmdList["SEDEBUGCOMBOS"] = function() SpellEffects.DebugDumpAuraCombos() end

-- /sepincombos : épingle rétroactivement au CDM natif les combos "Auras" créés avant l'auto-épinglage.
-- À lancer une fois après mise à jour, hors combat (suivi d'un reload si des sorts ont été épinglés).
SLASH_SEPINCOMBOS1 = "/sepincombos"
SlashCmdList["SEPINCOMBOS"] = function()
  local P = "|cff00ffff[SE-DEBUG]|r "
  local Auras = ns.Auras
  if not (Auras and Auras.PinAuraToCDM) then
    print(P .. "ns.Auras.PinAuraToCDM indisponible.")
    return
  end
  local cfg = ns.GetCfg("spellEffects")
  local auraCombos = cfg and cfg.auraCombos
  -- Ruée Ardente : vit dans missingBuffsCombos mais dépend du même pin CDM que les combos "Auras".
  local burningRushID = ns.Auras and ns.Auras.MISSING_WARLOCK_BURNING_RUSH
  local brCombo = burningRushID and cfg and cfg.missingBuffsCombos
                  and cfg.missingBuffsCombos[burningRushID]
  local hasBR = brCombo and #brCombo > 0
  if not auraCombos and not hasBR then
    print(P .. "Aucun combo d'aura configure.")
    return
  end
  local pinned, failed = 0, 0
  local function PinOne(spellID)
    local ok, msg = Auras.PinAuraToCDM(spellID, true)
    if not ok then ok, msg = Auras.PinAuraToCDM(spellID, false) end
    if ok then
      pinned = pinned + 1
      print(P .. string.format("  epingle : %s (%d)", tostring(GetSpellName(spellID)), spellID))
    else
      failed = failed + 1
      print(P .. string.format("  echec : %s (%d) -- %s", tostring(GetSpellName(spellID)), spellID, tostring(msg)))
    end
  end
  for auraID, combo in pairs(auraCombos or {}) do
    if type(auraID) == "number" and combo and #combo > 0 then
      PinOne(auraID)
    end
  end
  if hasBR then PinOne(burningRushID) end
  print(P .. string.format("Termine : %d epingle(s), %d echec(s)/deja bon.", pinned, failed))
  if pinned > 0 then
    -- Immédiat (pas différé) : chaque épinglage réussi tainte le CDM natif jusqu'au reload.
    if Auras.PromptCDMReloadIfPending then Auras.PromptCDMReloadIfPending() end
  end
end

-- /sedebugbuffs : liste tous les buffs actifs sur le joueur (nom + vrai spellId), pour vérifier
-- qu'un spellID configuré correspond bien à l'aura réelle (certains sorts castent un ID différent).
SLASH_SEDEBUGBUFFS1 = "/sedebugbuffs"
SlashCmdList["SEDEBUGBUFFS"] = function()
  local P = "|cff00ffff[SE-DEBUG]|r "
  if not (AuraUtil and AuraUtil.ForEachAura) then
    print(P .. "AuraUtil.ForEachAura indisponible.")
    return
  end
  print(P .. "Buffs (HELPFUL) actuellement actifs sur le joueur :")
  local count = 0
  local ok, err = pcall(AuraUtil.ForEachAura, "player", "HELPFUL", nil, function(aura)
    if not aura then return false end
    local sid = aura.spellId
    local name = aura.name
    if sid ~= nil and not issecretvalue(sid) then
      count = count + 1
      local sidOk, sidStr = pcall(string.format, "%d", sid)
      print(P .. string.format("  %s (spellId=%s)", tostring(name), sidOk and sidStr or "?"))
    else
      count = count + 1
      print(P .. "  (aura secrete/illisible)")
    end
    return false
  end, true)
  if not ok then
    print(P .. "  |cffff4444SCAN ECHOUE : " .. tostring(err) .. "|r")
  elseif count == 0 then
    print(P .. "  aucun buff trouve (scan reussi, 0 resultat).")
  end
end

local _initialized = false

function SpellEffects.Init()
  if _initialized then return end
  _initialized = true
  MigrateOocLegacyKeys()

  -- Crée le conteneur sentinelle dès que possible, hors combat (échoue silencieusement en combat ;
  -- PLAYER_REGEN_ENABLED ci-dessous rattrape un reload en plein pull).
  EnsureSentinelContainer("player")
  EnsureSentinelContainer("target")
  do
    local sentinelRetryFrame = CreateFrame("Frame")
    sentinelRetryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    sentinelRetryFrame:SetScript("OnEvent", function()
      EnsureSentinelContainer("player")
      EnsureSentinelContainer("target")
    end)
  end

  local evFrame = CreateFrame("Frame")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
  evFrame:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")

  evFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID, ...)
    if SpellEffects._debugAll then
      local P = "|cff00ffff[SE-DEBUG]|r "
      print(P .. "EVENT: " .. event .. " spellID=" .. tostring(spellID) .. " (" .. (GetSpellName(spellID) or "?") .. ")")
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      -- Empower : SUCCEEDED fire au début du cast, on diffère d'un frame pour laisser EMPOWER_START poser empowerSpellID et skip le onhit ici.
      local sid = spellID
      C_Timer.After(0, function()
        if empowerSpellID == sid then return end
        SpellEffects.Play(sid)
      end)

    elseif event == "UNIT_SPELLCAST_START" then
      local castDur
      local name, _, _, startTimeMS, endTimeMS = UnitCastingInfo("player")
      if startTimeMS and endTimeMS then
        castDur = (endTimeMS - startTimeMS) / 1000
      else
        castDur = 3
      end
      PlayCasting(spellID, castDur, false)

    elseif event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
      local castDur
      local name, _, _, startTimeMS, endTimeMS = UnitChannelInfo("player")
      if startTimeMS and endTimeMS then
        castDur = (endTimeMS - startTimeMS) / 1000
      else
        castDur = 5
      end
      if event == "UNIT_SPELLCAST_EMPOWER_START" then
        empowerSpellID = spellID
      end
      PlayCasting(spellID, castDur, true)

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
      -- Annuler le onhit différé d'un empower interrompu
      if empowerPendingOnhit then
        empowerPendingOnhit:Cancel()
        empowerPendingOnhit = nil
      end
      empowerSpellID = nil
      if #castingEntries > 0 then
        StopCasting()
      end

    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
      -- L'empower est terminé : jouer le onhit après un court délai
      -- pour laisser INTERRUPTED annuler si c'était un cancel.
      local sid = empowerSpellID
      empowerSpellID = nil
      if sid then
        empowerPendingOnhit = C_Timer.NewTimer(0.1, function()
          empowerPendingOnhit = nil
          SpellEffects.Play(sid)
        end)
      end
      -- Stopper les animations casting (même logique que les autres stops)
      if #castingEntries > 0 then
        local gen = castingGen
        C_Timer.After(0.25, function()
          if castingGen ~= gen then return end
          if #castingEntries == 0 then return end
          if UnitChannelInfo("player") then return end
          if UnitCastingInfo("player") then return end
          StopCasting()
        end)
      end

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_FAILED" then
      if #castingEntries > 0 then
        local gen = castingGen
        C_Timer.After(0.25, function()
          if castingGen ~= gen then return end
          if #castingEntries == 0 then return end
          if UnitChannelInfo("player") then return end
          if UnitCastingInfo("player") then return end
          StopCasting()
        end)
      end
    end
  end)

  -- Hook sur le masquage du cercle : stopper toutes les animations 3D.
  C_Timer.After(0, function()
    local ring = _G[RING_FRAME]
    if ring then
      ring:HookScript("OnHide", function()
        SpellEffects.StopAll()
        SpellEffects.StopOrbDeco()
      end)
      ring:HookScript("OnShow", function()
        SpellEffects.StartOrbDeco()
      end)
    end

    -- Hook OOC cercle de vie : décorations soutenues
    local oocRing = _G["AishCoreHealthRing"]
    if oocRing then
      oocRing:HookScript("OnShow", function()
        SpellEffects.StartOocDeco()
      end)
      oocRing:HookScript("OnHide", function()
        SpellEffects.StopOocDeco()
      end)
    end
  end)

  -- Changement de spé : rafraîchir les décorations (OOC combo peut changer)
  local specFrame = CreateFrame("Frame")
  specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  specFrame:RegisterEvent("UPDATE_STEALTH")
  specFrame:SetScript("OnEvent", function()
    -- 0.2 s de délai : laisse IsStealthed() et GetBonusBarIndex() se stabiliser
    C_Timer.After(0.2, function()
      SpellEffects.RefreshDecorations()
    end)
  end)

  -- Changement de puissance : rafraîchir les décors orbes si l'état « max » change
  local powerFrame = CreateFrame("Frame")
  powerFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  powerFrame:SetScript("OnEvent", function()
    if not decoOrbActive then return end
    local changed = false
    -- Vérifier le changement d'état stealth (rattrapage Shadow Dance / Subterfuge)
    local nowStealth = IsInStealth()
    if nowStealth ~= _lastStealth then
      _lastStealth = nowStealth
      changed = true
    end
    for root, pt in pairs(KEY_TO_POWER) do
      local atMax = IsAtMaxPower(root)
      if _lastAtMax[root] ~= atMax then
        _lastAtMax[root] = atMax
        changed = true
      end
    end
    if changed then
      -- L'état max a changé : relancer complet (changement de variante d'animation)
      SpellEffects.StopOrbDeco()
      SpellEffects.StartOrbDeco()
    else
      -- Pas de traversée de seuil max : ajouter seulement les nouveaux dots
      -- (un nouveau globe peut être apparu sans changer la variante d'animation)
      C_Timer.After(0.05, OrbDecoAddNewDots)
    end
  end)

  -- Détection des combos d'auras : présence sur le joueur (buffs) ou la
  -- cible (debuffs), démarrage/arrêt des animations soutenues sur transition.
  local auraFrame = CreateFrame("Frame")
  -- RegisterUnitEvent ne supporte que 2 unités PAR appel et chaque appel
  -- remplace la liste précédente pour cet event : il faut les passer ensemble.
  auraFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")
  auraFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  auraFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_TARGET_CHANGED" then
      -- Changement de cible : oublier l'état des auras suivies sur la cible
      -- pour forcer un re-scan propre (arrêt si la nouvelle cible ne l'a pas).
      local cfg = ns.GetCfg("spellEffects")
      local auraCombos = cfg and cfg.auraCombos
      local specSpells = ns.Auras and ns.Auras.GetSpecSpells and ns.Auras.GetSpecSpells()
      if auraCombos then
        for auraID in pairs(_auraPresence) do
          local info = specSpells and specSpells[auraID]
          -- Meme correction que ScanAuraCombos -- ne pas forcer un source
          -- manquant a "debuff".
          local source = info and info.source
          if not AuraSourceIsPlayerBuff(source) then
            _auraPresence[auraID] = nil
            SpellEffects.StopAuraSustained(auraID)
          end
        end
      end
    end
    ScanAuraCombos()
  end)

  -- Filet de sécurité : UNIT_AURA ne se déclenche qu'au changement, un poll périodique garantit le démarrage sinon.
  C_Timer.NewTicker(2, ScanAuraCombos)
  -- Buffs manquants : présence lue via MissingBuffs.GetCurrentAlertSpell(), poll périodique suffit (pas de UNIT_AURA).
  C_Timer.NewTicker(2, ScanMissingBuffCombos)

  -- Coupe les anims en cours si le toggle Raid/Groupe s'active ; pas de symétrique nécessaire au retrait du groupe.
  local groupGateFrame = CreateFrame("Frame")
  groupGateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
  groupGateFrame:SetScript("OnEvent", function()
    if AnimationsBlockedByGroupState() then
      SpellEffects.StopAll()
    end
  end)

  -- /sedebug : active le mode trace pour le PROCHAIN cast détecté
  SLASH_SEDEBUG1 = "/sedebug"
  SlashCmdList["SEDEBUG"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "all" then
      -- Mode trace continue pendant 10 secondes : log TOUS les Play()
      SpellEffects._debugAll = true
      print("|cff00ffff[SE-DEBUG]|r Mode ALL activé — tous les Play() seront tracés pendant 10s.")
      C_Timer.After(10, function()
        SpellEffects._debugAll = false
        print("|cff00ffff[SE-DEBUG]|r Mode ALL terminé.")
      end)
    else
      SpellEffects._debugNext = true
      print("|cff00ffff[SE-DEBUG]|r Mode trace activé — lance ton sort, les infos s'afficheront au prochain cast.")
      print("|cff00ffff[SE-DEBUG]|r Tip: |cffffff00/sedebug all|r pour tracer TOUS les casts pendant 10s.")
    end
  end
end

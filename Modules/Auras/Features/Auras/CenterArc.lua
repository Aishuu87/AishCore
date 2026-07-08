-- CenterArc.lua : arc de durée dans le cercle central
--
-- Deux chemins selon le type de sort :
--
--  isTotem = false (DK Sang 250, Warrior Prot 73) :
--    CDM scan → SetCenterArcEntry(durObj) → SetTimerDuration 60fps natif Blizzard
--    Fallback hors combat : UNIT_AURA + GetPlayerAuraBySpellID → SetCenterArcValue ticker
--
--  isTotem = true (Pala Prot 66, Consécration) :
--    GetTotemInfo(slot) donne startTime (lisible même en combat) mais duration peut
--    être une secret value en combat (protection anti-sniping Blizzard). Pattern
--    repris d'ElvUI (TotemTracker.lua) : dans ce cas, GetTotemDuration(slot) renvoie
--    un objet de durée opaque exploitable par SetTimerDuration SANS jamais lire la
--    valeur secrète — même mécanisme "show but don't know" que le chemin CDM non-totem.
--    Déclencheurs : PLAYER_TOTEM_UPDATE (événement dédié Blizzard) et
--    UNIT_SPELLCAST_SUCCEEDED (immédiat au cast, sans attendre l'event totem).
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

-- TWW 12.0 : GetSpellName global supprimé, remplacé par C_Spell.GetSpellName.
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo

local CENTER_ARC_SPELLS = {
    -- castSpellID : sort à écouter en UNIT_SPELLCAST_SUCCEEDED pour le déclenchement immédiat
    [66]  = { spellID = 188370, isTotem = true,  castSpellID = 26573,
              color = {1.00, 0.88, 0.10}, cfgKey = "consecrationArcEnabled" },
    [73]  = { spellID = 190456, isTotem = false, color = {0.78, 0.25, 0.25}, cfgKey = "ignorePainArcEnabled"   },
    [250] = { spellID = 188290, isTotem = false, color = {0.20, 0.78, 0.35}, cfgKey = "dndArcEnabled"          },
}

local activeInfo      = nil
local fallTicker      = nil
local fallExpiry      = 0
local fallMaxDur      = 0
local _arcFirstMissTime = nil
local _ARC_MISS_GRACE   = 0.5

local function GetRC()
    return _addon and _addon.Modules and _addon.Modules.ResourceCircle
end

local function IsEnabled()
    if not activeInfo then return false end
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    return not cfg or cfg[activeInfo.cfgKey] ~= false
end

local function GetArcColor()
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    if cfg and cfg.durationArcColorR then
        return {cfg.durationArcColorR, cfg.durationArcColorG or 1, cfg.durationArcColorB or 1}
    end
    return activeInfo and activeInfo.color or nil
end

local function StopFallback()
    if fallTicker then fallTicker:Cancel(); fallTicker = nil end
    fallExpiry = 0; fallMaxDur = 0
end

local function PushNil()
    local RC = GetRC()
    if RC and RC.SetCenterArcEntry then pcall(RC.SetCenterArcEntry, nil) end
end

local function FallbackTick()
    if fallExpiry == 0 then StopFallback(); PushNil(); return end
    local now = GetTime()
    local rem = fallExpiry - now
    if rem <= 0 then StopFallback(); PushNil(); return end
    local fraction = fallMaxDur > 0 and (rem / fallMaxDur) or 1
    local RC = GetRC()
    if RC and RC.SetCenterArcValue then
        pcall(RC.SetCenterArcValue, math.max(0, math.min(1, fraction)), GetArcColor())
    end
end

-- Scanne les slots de totem (Pala Prot : Consécration occupe le seul slot actif) et
-- retourne le durObj combat-safe (pattern ElvUI TotemTracker) :
--   - startTime est lisible même en combat → sert juste à confirmer la présence.
--     ATTENTION : ne jamais faire d'arithmétique dessus (ex. startTime*1000) —
--     ça peut planter silencieusement si c'est une secret value dans certains cas.
--   - GetTotemDuration(slot) renvoie l'objet de durée, secret ou non, que
--     SetTimerDuration sait consommer sans qu'on ait besoin de le lire.
-- IMPORTANT : ne jamais tester "have" (1er retour de GetTotemInfo) dans une
-- condition : c'est une secret value en combat, et l'utiliser dans un "and"/"if"
-- fait planter silencieusement la fonction appelante (avalée par pcall).
function ns.FindActiveTotemDurObj()
    if not (GetTotemInfo and GetTotemDuration) then return nil end
    for slot = 1, 4 do
        local ok, _, _, startTime = pcall(GetTotemInfo, slot)
        if ok and startTime then
            local okD, durObj = pcall(GetTotemDuration, slot)
            if okD and durObj then return durObj end
        end
    end
    return nil
end

-- Cache de l'état totem, mis à jour UNIQUEMENT par les events fiables
-- (PLAYER_TOTEM_UPDATE / UNIT_SPELLCAST_SUCCEEDED / spec change), jamais par un
-- re-scan à chaque appel. Nécessaire car GetTotemInfo ne reste "actif" que
-- pendant une fenêtre courte après le cast — bien plus courte que la durée
-- visuelle réelle du buff. Si on interrogeait GetTotemInfo à chaque
-- Scan:Run() (très fréquent), l'entrée synthétique disparaîtrait presque
-- aussitôt après le cast alors que le buff est encore actif. L'arc n'a pas ce
-- problème : une fois le durObj donné à SetTimerDuration, Blizzard anime seul,
-- sans besoin de reconfirmer l'état à chaque frame.
-- instID généré via un compteur Lua pur (jamais d'arithmétique sur startTime/duration) :
-- incrémenté seulement quand durObj change (tostring, comme _lastArcDurRef côté ResourceCircle).
local _totemCache        = nil  -- { durObj, instID, spellID } ou nil
local _lastTotemDurObjRef = nil
local _totemInstCounter   = 0

local function ScanTotemArc()
    if not activeInfo or not activeInfo.isTotem then _totemCache = nil; _lastTotemDurObjRef = nil; return end
    local durObj = ns.FindActiveTotemDurObj()
    if durObj then
        local ref = tostring(durObj)
        if ref ~= _lastTotemDurObjRef then
            _lastTotemDurObjRef = ref
            _totemInstCounter = _totemInstCounter + 1
        end
        _totemCache = { durObj = durObj, instID = -_totemInstCounter, spellID = activeInfo.spellID }
    else
        _lastTotemDurObjRef = nil
        _totemCache = nil
    end
    if not IsEnabled() then return end
    local RC = GetRC()
    if not (RC and RC.SetCenterArcEntry) then return end
    if durObj then
        StopFallback()
        pcall(RC.SetCenterArcEntry, { durObj = durObj, spellColor = GetArcColor() })
    else
        pcall(RC.SetCenterArcEntry, nil)
    end
end

-- Entrée synthétique pour le pipeline d'auras (icônes/barres/liste) : Blizzard
-- n'expose jamais ce buff-totem via SetAuraInstanceInfo (confirmé par debug),
-- donc CollectFromCDM ne le voit jamais. On construit une entrée compatible
-- (instID/durObj/stacks/unit/spellID), injectée par Scan.lua avant le filtrage
-- par destination — elle suit ensuite exactement le même whitelist/priorité
-- que n'importe quel autre sort configuré par l'utilisateur. Lit le cache
-- (voir _totemCache ci-dessus), ne re-scanne jamais GetTotemInfo elle-même.
function ns.GetTotemSyntheticEntry()
    if not (activeInfo and activeInfo.isTotem) then return nil end
    if not _totemCache then return nil end
    return {
        instID  = _totemCache.instID,
        durObj  = _totemCache.durObj,
        stacks  = 0,
        unit    = "player",
        spellID = _totemCache.spellID,
    }
end

-- Auto-configure destinations.centerArc pour le sort du spec courant.
-- Chemin totem (isTotem) exclu : son buff n'est pas suivi par le scan CDM générique
-- (Consécration passe par GetTotemInfo/ScanTotemArc, pas par le pipeline d'auras).
function ns.AutoConfigCenterArc()
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    for _, info in pairs(spells) do
        if info.destinations then info.destinations.centerArc = false end
    end
    if not activeInfo or not IsEnabled() or activeInfo.isTotem then return end
    local si = spells[activeInfo.spellID]
    if not si then
        local name = GetSpellName and GetSpellName(activeInfo.spellID) or tostring(activeInfo.spellID)
        si = ns.DeepCopy and ns.DeepCopy(ns.SpellDefaults) or {
            enabled = false, destinations = {iconlist=false,circlebars=false,icons=false,freebars=false,centerArc=false}
        }
        si.name = name; si.source = "buff"; si.priority = activeInfo.spellID
        spells[activeInfo.spellID] = si
    end
    if not si.destinations then si.destinations = {iconlist=false,circlebars=false,icons=false,freebars=false,centerArc=false} end
    si.destinations.centerArc = true
    si.enabled = true
end

-- Chemin principal CDM (sorts non-totem)
local CenterArc = {}

function CenterArc:Init()
    ns.renderFrames.centerArc = { active = true }
end

function CenterArc:Update(auras)
    if not activeInfo or not IsEnabled() or activeInfo.isTotem then return end
    if ns.db and ns.db.useNativeCDM then return end
    local RC = GetRC()
    if not (RC and RC.SetCenterArcEntry) then return end
    if auras and #auras > 0 then
        _arcFirstMissTime = nil
        StopFallback()
        local e = auras[1]
        if e then
            e = { durObj = e.durObj, auraInstanceID = e.auraInstanceID, spellColor = GetArcColor() }
        end
        pcall(RC.SetCenterArcEntry, e)
    else
        local now = GetTime()
        if not _arcFirstMissTime then _arcFirstMissTime = now end
        if (now - _arcFirstMissTime) >= _ARC_MISS_GRACE then
            _arcFirstMissTime = nil
            if fallExpiry == 0 then
                pcall(RC.SetCenterArcEntry, nil)
            end
        end
    end
end

ns.RenderRegistry = ns.RenderRegistry or {}
ns.RenderRegistry["centerArc"] = CenterArc

------------------------------------------------------------------------
-- EVENTS
------------------------------------------------------------------------
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("UNIT_AURA")
evtFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
evtFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local function OnCenterArcEvent(_, event, arg1, arg2, arg3)

    ---------- SPEC CHANGE / ENTERING WORLD ----------
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        StopFallback(); PushNil(); _arcFirstMissTime = nil
        local specID = ns._specID
        if not specID and GetSpecialization and GetSpecializationInfo then
            local idx = GetSpecialization()
            if idx and idx > 0 then
                local ok, sid = pcall(GetSpecializationInfo, idx)
                if ok then specID = sid end
            end
        end
        activeInfo = CENTER_ARC_SPELLS[specID or 0]
        if ns.AutoConfigCenterArc then
            pcall(ns.AutoConfigCenterArc)
            if ns.BuildWhitelist then pcall(ns.BuildWhitelist) end
        end
        if activeInfo and activeInfo.isTotem then pcall(ScanTotemArc) end

    ---------- PLAYER_TOTEM_UPDATE : déclencheur dédié Blizzard (start/stop totem) ----------
    elseif event == "PLAYER_TOTEM_UPDATE" then
        if not activeInfo or not activeInfo.isTotem then return end
        pcall(ScanTotemArc)
        -- Rescan du pipeline d'auras (icônes/barres) : le buff-totem n'est jamais vu
        -- par le scan CDM générique, donc UNIT_AURA peut le sauter (rien dans
        -- ns.cdmData à matcher). PLAYER_TOTEM_UPDATE est l'event fiable pour ça.
        if ns.ScanAuras then pcall(ns.ScanAuras) end

    ---------- UNIT_AURA (chemin non-totem uniquement) ----------
    elseif event == "UNIT_AURA" and arg1 == "player" then
        if not activeInfo or not IsEnabled() or activeInfo.isTotem then return end

        local data = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
                     and C_UnitAuras.GetPlayerAuraBySpellID(activeInfo.spellID)
        if data and data.expirationTime and data.expirationTime > GetTime() then
            StopFallback()
            fallExpiry  = data.expirationTime
            fallMaxDur  = data.duration or 0
            if fallMaxDur == 0 then fallMaxDur = data.expirationTime - GetTime() end
            local RC = GetRC()
            if RC and RC.SetCenterArcValue then
                local frac = (data.expirationTime - GetTime()) / fallMaxDur
                pcall(RC.SetCenterArcValue, math.max(0, math.min(1, frac)), activeInfo.color)
            end
            fallTicker = C_Timer.NewTicker(0.016, FallbackTick)
        elseif fallExpiry > 0 and GetTime() >= fallExpiry then
            StopFallback(); PushNil()
        end

    ---------- UNIT_SPELLCAST_SUCCEEDED : déclencheur immédiat du chemin totem ----------
    -- arg1 = unitID, arg2 = castGUID, arg3 = spellID
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        if not activeInfo or not activeInfo.isTotem then return end
        if not IsEnabled() then return end
        if not activeInfo.castSpellID or arg3 ~= activeInfo.castSpellID then return end
        pcall(ScanTotemArc)
        if ns.ScanAuras then pcall(ns.ScanAuras) end
    end
end

evtFrame:SetScript("OnEvent", function(...)
    pcall(OnCenterArcEvent, ...)
end)

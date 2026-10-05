-- CenterArc.lua : arc de duree dans le cercle central
-- Non-totem (DK Sang 250, Warrior Prot 73) : CDM -> SetCenterArcEntry(durObj), fallback UNIT_AURA hors combat
-- Totem (Pala Prot 66, Consecration) : GetTotemDuration (pattern ElvUI, jamais lire la valeur secrete)
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

-- TWW 12.0 : GetSpellName global supprimé, remplacé par C_Spell.GetSpellName.
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo

-- castSpellID = trigger UNIT_SPELLCAST_SUCCEEDED ; supportsAbsorbMode = arc alternatif par absorption ;
-- useCDMBar = duration via canal clone-bar (CDMHooks.lua), sort a epingler sur le viewer "Barres".
-- altMode + altModeCfgKey = 2e mode propose a l'utilisateur par une case a cocher
-- ("absorb" ou "stacks") ; sans eux l'arc reste toujours en duree. CDM
local CENTER_ARC_SPELLS = {
    [66]  = { spellID = 188370, isTotem = true,  castSpellID = 26573,
              color = {1.00, 0.88, 0.10}, cfgKey = "consecrationArcEnabled" },
    [73]  = { spellID = 190456, isTotem = false, color = {0.78, 0.25, 0.25}, cfgKey = "ignorePainArcEnabled",
              supportsAbsorbMode = true, useCDMBar = true,
              altMode = "absorb", altModeCfgKey = "ignorePainArcAbsorb" },
    -- Fer-poil (Druide Gardien) : meme schema que Dur au mal, mais le mode alternatif
    -- remplit selon les stacks (5 = plein) plutot que selon une absorption.
    [104] = { spellID = 192081, isTotem = false, color = {0.85, 0.65, 0.30}, cfgKey = "ironfurArcEnabled",
              useCDMBar = true, maxStacks = 5,
              altMode = "stacks", altModeCfgKey = "ironfurArcStacks" },
    [250] = { spellID = 188290, isTotem = false, color = {0.20, 0.78, 0.35}, cfgKey = "dndArcEnabled",
              useCDMBar = true },
    -- Mana Tea (Mistweaver) : useStackMode via castCountSpellID (sort activable, le buff seul n'est pas trackable)
    [270] = { spellID = 115867, castCountSpellID = 115294, isTotem = false,
              color = {0.25, 0.85, 0.55}, cfgKey = "manaTeaArcEnabled",
              useStackMode = true, maxStacks = 20 },
    -- DH Devourer : altSpellID = fragments de vide sous Metamorphose, meme paire que ResourceMap.lua
    [1480] = { spellID = 1225789, altSpellID = 1227702, isTotem = false,
               color = {0.70, 0.30, 1.00}, cfgKey = "devourerArcEnabled",
               useStackMode = true, maxStacks = 50 },
    [1473] = { spellID = 395296, isTotem = false, color = {0.93, 0.64, 0.30},
               cfgKey = "ebonyPowerArcEnabled", useCDMBar = true },
    -- Pas d'entree [581] (DH Vengeance) : texte de ressource secondaire seulement, pas d'arc dedie
}

local activeInfo      = nil
-- specID resolu au moment du choix d'activeInfo (reglages par spec), plutot que _addon._specID qui peut etre perime
local activeSpecID    = nil
local fallTicker      = nil
local fallExpiry      = 0
local fallMaxDur      = 0
local _arcFirstMissTime = nil
local _ARC_MISS_GRACE   = 0.5

-- Mode "absorb" (Dur Au Mal) : ticker dedie, independant du chemin CDM/durObj normal
local absorbTicker      = nil
local _absorbWasPresent = false

-- Mode "stacks" (The de Mana) : ticker dedie, independant du chemin CDM/durObj normal
local stackModeTicker = nil

local function GetRC()
    return _addon and _addon.Modules and _addon.Modules.ResourceCircle
end

local function IsEnabled()
    if not activeInfo then return false end
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    return not cfg or cfg[activeInfo.cfgKey] ~= false
end

-- "duration" (defaut), "absorb" ou "stacks". Le mode alternatif et la cle qui le
-- declenche sont portes par l'entree de spec (altMode / altModeCfgKey) : rien n'est
-- cable en dur sur un sort particulier.
local function GetArcMode()
    if not (activeInfo and activeInfo.altMode and activeInfo.altModeCfgKey) then return "duration" end
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    return (cfg and cfg[activeInfo.altModeCfgKey]) and activeInfo.altMode or "duration"
end

-- Le mode "stacks" peut venir de l'entree elle-meme (The de Mana, Devoreur : toujours en
-- stacks) OU de la bascule utilisateur (Fer-poil).
local function IsStackMode()
    return (activeInfo and activeInfo.useStackMode) or GetArcMode() == "stacks"
end

local function GetArcColor()
    local r = _addon.GetSecResCfg and _addon.GetSecResCfg("durationArcColorR", activeSpecID)
    if r then
        return {r, _addon.GetSecResCfg("durationArcColorG", activeSpecID) or 1, _addon.GetSecResCfg("durationArcColorB", activeSpecID) or 1}
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

local function StopAbsorbTicker()
    if absorbTicker then absorbTicker:Cancel(); absorbTicker = nil end
    _absorbWasPresent = false
end

local function StopStackModeTicker()
    if stackModeTicker then stackModeTicker:Cancel(); stackModeTicker = nil end
end

-- Mode "cdmbar" : canal event-driven, juste (des)abonnement du proxy ResourceCircle au spellID courant
local _cdmBarActiveSpellID = nil
local function StopCDMBarMode()
    if _cdmBarActiveSpellID and ns.UnsubscribeCDMAuraBar then
        ns.UnsubscribeCDMAuraBar(_cdmBarActiveSpellID, "centerArc")
    end
    _cdmBarActiveSpellID = nil
end
local function StartCDMBarMode()
    if not (activeInfo and activeInfo.useCDMBar and activeInfo.spellID) then return end
    if GetArcMode() ~= "duration" then return end
    local RC = GetRC()
    if not (RC and RC.centerArcBarProxy and ns.SubscribeCDMAuraBar) then return end
    StopCDMBarMode()
    _cdmBarActiveSpellID = activeInfo.spellID
    if RC.SetCenterArcColor then pcall(RC.SetCenterArcColor, GetArcColor()) end
    ns.SubscribeCDMAuraBar(activeInfo.spellID, "centerArc", RC.centerArcBarProxy)
end

-- Teste val == 0 sans planter si val est une secret value
local function IsConfirmedZeroLocal(val)
    if val == nil then return false end
    local ok, isZero = pcall(function() return val == 0 end)
    return ok and isZero == true
end

-- Presence reelle de l'aura (cdmData n'est jamais nettoye, une entree peut rester apres expiration)
local function IsAuraPresent(spellID)
    if ns.IsCDMAuraSwipePresent and ns.IsCDMAuraSwipePresent(spellID) then return true end
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    return ok and auraData ~= nil
end

-- Variante de IsAuraPresent qui renvoie le compte de stacks. nil = absent, jamais 0 (valeur brute possiblement secrete)
local function GetCDMStackCount(spellID)
    local cdmPlayer = ns.cdmData and ns.cdmData.player
    local cdmEntry = cdmPlayer and cdmPlayer[spellID]
    if not (cdmEntry and cdmEntry.instID) then return nil end
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if ok and disp ~= nil then return disp end
    return nil
end

-- Plafond d'absorption de Dur Au Mal, lu depuis la description du sort (pas secrete, contrairement a AuraData.points)
-- On prend le dernier nombre du texte (cumul max), mis en cache quelques secondes
local _maxAbsorbCache     = nil
local _maxAbsorbCacheTime = 0
local MAX_ABSORB_REFRESH  = 2 -- secondes : re-parse pour suivre les changements de stats

local function GetIgnorePainMaxAbsorb()
    local now = GetTime()
    if _maxAbsorbCache and (now - _maxAbsorbCacheTime) < MAX_ABSORB_REFRESH then
        return _maxAbsorbCache
    end
    local getDesc = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    if not getDesc then return _maxAbsorbCache end
    local ok, desc = pcall(getDesc, 190456)
    if ok and type(desc) == "string" then
        local last = nil
        for numStr in desc:gmatch("%d+") do last = numStr end
        local n = last and tonumber(last)
        if n and n > 0 then
            _maxAbsorbCache = n
            _maxAbsorbCacheTime = now
        end
    end
    return _maxAbsorbCache
end

-- Mode "absorb" : remplit l'arc selon l'absorption restante (secret value possible, jamais d'arithmetique, passe brut a SetCenterArcFill)
local function AbsorbTick()
    if not (activeInfo and activeInfo.supportsAbsorbMode) then StopAbsorbTicker(); return end
    if GetArcMode() ~= "absorb" then return end
    if not IsEnabled() then return end
    local RC = GetRC()
    if not (RC and RC.SetCenterArcFill and RC.SetCenterArcEntry) then return end

    if not IsAuraPresent(activeInfo.spellID) then
        if _absorbWasPresent then
            pcall(RC.SetCenterArcEntry, nil)
            _absorbWasPresent = false
        end
        return
    end
    _absorbWasPresent = true

    local maxAbsorb = GetIgnorePainMaxAbsorb()
    if not maxAbsorb or maxAbsorb <= 0 then return end
    local fn = UnitAbsorb or UnitGetTotalAbsorbs
    if not fn then return end
    local okAb, absorb = pcall(fn, "player")
    if not okAb or absorb == nil then return end
    pcall(RC.SetCenterArcFill, absorb, maxAbsorb, GetArcColor())
end

-- Mode "stacks" : remplit l'arc selon un nombre de stacks. Source castCountSpellID (sort activable)
-- ou altSpellID/spellID via RC.ApplyStacksToCenterArc (CDM + fallbacks). count potentiellement secret,
-- jamais compare, passe brut aux sinks combat-safe.
local function StackModeTick()
    if not (activeInfo and IsStackMode()) then
        StopStackModeTicker(); return
    end
    if not IsEnabled() then return end
    local RC = GetRC()
    if not (RC and RC.SetCenterArcFill and RC.SetCenterArcEntry) then return end

    if activeInfo.castCountSpellID then
        if not (C_Spell and C_Spell.GetSpellCastCount) then return end
        local ok, count = pcall(C_Spell.GetSpellCastCount, activeInfo.castCountSpellID)
        if not ok or count == nil or IsConfirmedZeroLocal(count) then
            pcall(RC.SetCenterArcEntry, nil)
            return
        end
        pcall(RC.SetCenterArcFill, count, activeInfo.maxStacks or 1, GetArcColor())
        return
    end

    if not RC.ApplyStacksToCenterArc then
        pcall(RC.SetCenterArcEntry, nil)
        return
    end
    local applied = false
    if activeInfo.altSpellID then
        applied = RC.ApplyStacksToCenterArc(activeInfo.altSpellID, activeInfo.maxStacks or 1, GetArcColor())
    end
    if not applied and activeInfo.spellID then
        applied = RC.ApplyStacksToCenterArc(activeInfo.spellID, activeInfo.maxStacks or 1, GetArcColor())
    end
    if not applied then
        pcall(RC.SetCenterArcEntry, nil)
    end
end

local function FallbackTick()
    -- Bascule vers un mode alternatif si le reglage a change entre-temps : on cede la
    -- main a AbsorbTick / StackModeTick, proprietaires de bar.durationArc dans ce cas.
    if GetArcMode() ~= "duration" then StopFallback(); return end
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

-- Scanne les slots de totem et retourne le durObj combat-safe (pattern ElvUI TotemTracker)
-- Ne jamais tester "have" (1er retour GetTotemInfo) ni faire d'arithmetique sur startTime : secret value en combat
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

-- Cache totem, mis a jour uniquement par les events fiables (GetTotemInfo ne reste "actif" que brievement apres le cast)
-- instID = compteur Lua pur, incremente seulement quand durObj change (jamais d'arithmetique sur startTime/duration)
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

-- Entree synthetique pour le pipeline d'auras : le buff-totem n'est jamais expose via SetAuraInstanceInfo,
-- donc CollectFromCDM ne le voit pas. Injectee par Scan.lua, suit le whitelist/priorite normal. Lit _totemCache.
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

-- Auto-configure destinations.centerArc pour le sort du spec courant (chemin totem exclu, hors pipeline CDM)
function ns.AutoConfigCenterArc()
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    for _, info in pairs(spells) do
        local dest = rawget(info, "destinations")  -- rawget : ne pas creer destinations sur chaque sort (ns.SPELL_MT)
        if dest then dest.centerArc = false end
    end
    if not activeInfo or not IsEnabled() or activeInfo.isTotem then return end
    local si = spells[activeInfo.spellID]
    if not si then
        local name = GetSpellName and GetSpellName(activeInfo.spellID) or tostring(activeInfo.spellID)
        si = ns.DeepCopy and ns.DeepCopy(ns.SpellDefaults) or {
            enabled = false, destinations = {iconlist=false,circlebars=false,icons=false,freebars=false,totems=false,centerArc=false}
        }
        si.name = name; si.source = "buff"; si.priority = activeInfo.spellID
        spells[activeInfo.spellID] = si
    end
    if not si.destinations then si.destinations = {iconlist=false,circlebars=false,icons=false,freebars=false,totems=false,centerArc=false} end
    si.destinations.centerArc = true
    si.enabled = true
end

--- Meme principe que AutoConfigCenterArc, pour le sort suivi par la barre de duree de
--- la ressource secondaire (cote ResourceCircle, donc namespace parent). Sans ca le sort
--- n'a aucune destination active, n'entre jamais dans le scan, et son durObj n'existe
--- nulle part -- c'etait le cas de Bouclier d'os, non tracke par ailleurs.
function ns.AutoConfigSecResDurBar()
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    for _, info in pairs(spells) do
        local dest = rawget(info, "destinations")  -- rawget : ne pas creer destinations sur chaque sort (ns.SPELL_MT)
        if dest then dest.secResDurBar = false end
    end
    local getID = _addon and _addon.GetSecResDurBarSpellID
    local sid = getID and getID()
    if not sid then return end
    local si = spells[sid]
    if not si then
        local name = GetSpellName and GetSpellName(sid) or tostring(sid)
        si = ns.DeepCopy and ns.DeepCopy(ns.SpellDefaults) or { enabled = false, destinations = {} }
        si.name = name; si.source = "buff"; si.priority = sid
        spells[sid] = si
    end
    si.destinations = si.destinations or {}
    si.destinations.secResDurBar = true
    si.enabled = true
end

-- Chemin principal CDM (sorts non-totem)
local CenterArc = {}

function CenterArc:Init()
    ns.renderFrames.centerArc = { active = true }
end

function CenterArc:Update(auras)
    if not activeInfo or not IsEnabled() or activeInfo.isTotem then return end
    -- Hors mode duree, bar.durationArc appartient a AbsorbTick / StackModeTick.
    if IsStackMode() or GetArcMode() ~= "duration" then return end
    if activeInfo.useCDMBar then return end  -- canal clone-bar event-driven possède bar.durationArc dans ce mode
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

-- Events
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("UNIT_AURA")
evtFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
evtFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

-- Resout activeInfo + (re)demarre les tickers. Appelable depuis l'event handler ET ns.ResyncCenterArc
-- (toggle checkbox dans le panneau d'options, cf. SettingsPanel.lua).
local function ResolveActiveArc()
    StopFallback(); PushNil(); _arcFirstMissTime = nil
    StopAbsorbTicker()
    StopStackModeTicker()
    StopCDMBarMode()
    -- Resolution fraiche en priorite : _addon._specID (PAS ns._specID, jamais rempli) peut etre perime
    local specID = nil
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx and idx > 0 then
            local ok, sid = pcall(GetSpecializationInfo, idx)
            if ok and sid and sid > 0 then specID = sid end
        end
    end
    if not specID then specID = _addon._specID end
    activeSpecID = specID
    activeInfo = CENTER_ARC_SPELLS[specID or 0]
    if ns.AutoConfigCenterArc then
        pcall(ns.AutoConfigCenterArc)
        if ns.BuildWhitelist then pcall(ns.BuildWhitelist) end
    end
    if activeInfo and activeInfo.isTotem then pcall(ScanTotemArc) end
    if activeInfo and activeInfo.supportsAbsorbMode then
        absorbTicker = C_Timer.NewTicker(0.1, AbsorbTick)
    end
    if activeInfo and IsStackMode() then
        stackModeTicker = C_Timer.NewTicker(0.1, StackModeTick)
    end
    StartCDMBarMode()
end
ns.ResyncCenterArc = ResolveActiveArc

local function OnCenterArcEvent(_, event, arg1, arg2, arg3)

    -- Spec change / entering world
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        ResolveActiveArc()

    -- PLAYER_TOTEM_UPDATE : declencheur dedie Blizzard (start/stop totem)
    elseif event == "PLAYER_TOTEM_UPDATE" then
        if not activeInfo or not activeInfo.isTotem then return end
        pcall(ScanTotemArc)
        -- Rescan pipeline d'auras : le buff-totem n'est jamais vu par le scan CDM, UNIT_AURA peut le sauter
        if ns.ScanAuras then pcall(ns.ScanAuras) end

    -- UNIT_AURA (chemin non-totem uniquement)
    elseif event == "UNIT_AURA" and arg1 == "player" then
        if not activeInfo or not IsEnabled() or activeInfo.isTotem then return end
        -- Hors mode duree, StackModeTick / AbsorbTick gerent l'arc.
        if IsStackMode() or GetArcMode() ~= "duration" then return end
        -- Le canal clone-bar a la priorite, mais seulement s'il alimente REELLEMENT.
        -- Avant, `useCDMBar` coupait le repli sans condition : un sort absent du viewer
        -- "Barres" de la CDM n'avait alors plus aucune source et l'arc restait vide.
        if activeInfo.useCDMBar and ns.IsCDMAuraBarPresent
           and ns.IsCDMAuraBarPresent(activeInfo.spellID) then return end

        local data = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
                     and C_UnitAuras.GetPlayerAuraBySpellID(activeInfo.spellID)
        -- AuraData peut etre totalement secrete : pcall autour du calcul, echec propre plutot que de planter le ticker
        local ok = pcall(function()
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
        end)
        if not ok then StopFallback() end

    -- UNIT_SPELLCAST_SUCCEEDED : declencheur immediat du chemin totem (arg1=unitID, arg2=castGUID, arg3=spellID)
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

-- Debug : /rcarc, etat complet de l'arc secondaire
SLASH_RCARC1 = "/rcarc"
SlashCmdList["RCARC"] = function()
    local P = "|cff33aaff[RCArc]|r "
    local function p(s) print(P .. s) end
    p(string.format("activeSpecID=%s", tostring(activeSpecID)))
    if not activeInfo then
        p("activeInfo = nil (pas d'entree CENTER_ARC_SPELLS pour cette spe)")
        return
    end
    p(string.format("activeInfo: spellID=%s altSpellID=%s castCountSpellID=%s useStackMode=%s maxStacks=%s cfgKey=%s isTotem=%s useCDMBar=%s supportsAbsorbMode=%s",
        tostring(activeInfo.spellID), tostring(activeInfo.altSpellID), tostring(activeInfo.castCountSpellID),
        tostring(activeInfo.useStackMode), tostring(activeInfo.maxStacks), tostring(activeInfo.cfgKey), tostring(activeInfo.isTotem),
        tostring(activeInfo.useCDMBar), tostring(activeInfo.supportsAbsorbMode)))
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    p(string.format("IsEnabled()=%s  cfg[%s]=%s  tickers: absorb=%s stackMode=%s fallback=%s",
        tostring(IsEnabled()), tostring(activeInfo.cfgKey), tostring(cfg and cfg[activeInfo.cfgKey]),
        tostring(absorbTicker ~= nil), tostring(stackModeTicker ~= nil), tostring(fallTicker ~= nil)))

    -- Etat de l'arc lu AVANT toute sonde : ApplyStacksToCenterArc ci-dessous ECRIT
    -- dans bar.durationArc, donc le lire apres donnerait l'etat laisse par la sonde
    -- et non l'etat reel du mode courant.
    local RC0 = GetRC()
    if RC0 and RC0._debug_GetDurationArc then
        local arc0 = RC0._debug_GetDurationArc()
        if arc0 then
            local okV0, val0 = pcall(arc0.GetValue, arc0)
            local okMM0, mn0, mx0 = pcall(arc0.GetMinMaxValues, arc0)
            p(string.format("bar.durationArc AVANT sonde: IsShown=%s Alpha=%.2f val=%s min=%s max=%s",
                tostring(arc0:IsShown()), arc0:GetAlpha(),
                okV0 and tostring(val0) or "?", okMM0 and tostring(mn0) or "?", okMM0 and tostring(mx0) or "?"))
        end
    end
    p(string.format("GetArcMode()=%s  ignorePainArcAbsorb=%s  _cdmBarActiveSpellID=%s  IsCDMAuraBarPresent(spellID)=%s",
        tostring(GetArcMode()), tostring(cfg and cfg.ignorePainArcAbsorb), tostring(_cdmBarActiveSpellID),
        tostring(activeInfo.spellID and ns.IsCDMAuraBarPresent and ns.IsCDMAuraBarPresent(activeInfo.spellID))))
    -- En mode absorb, _cdmBarActiveSpellID DOIT etre nil : sinon le canal clone-bar
    -- pilote encore l'arc en duree et ecrase les SetCenterArcFill d'AbsorbTick.
    if GetArcMode() == "absorb" and _cdmBarActiveSpellID then
        p("|cffff5555ANOMALIE|r : mode absorb mais canal clone-bar (duree) toujours abonne -> l'arc suivra la duree")
    end

    -- Mode absorb : le plafond vient du parsing de la description du sort. S'il est
    -- absurde (nil, ou tres petit face a l'absorption courante), l'arc reste vide ou
    -- colle a 100% -- c'est ici qu'il faut regarder en premier.
    if activeInfo.supportsAbsorbMode then
        local fn = UnitAbsorb or UnitGetTotalAbsorbs
        local okAb, absorb = pcall(fn or function() end, "player")
        p(string.format("absorb: max parse=%s  valeur courante=%s  aura presente=%s",
            tostring(GetIgnorePainMaxAbsorb()),
            okAb and tostring(absorb) or "<illisible>",
            tostring(IsAuraPresent(activeInfo.spellID))))
    end

    -- GetCDMStackCount = diagnostic CDM seul ; ApplyStacksToCenterArc = vraie chaine utilisee par StackModeTick.
    -- La sonde n'a de sens QUE pour les specs a stacks : ailleurs (Dur au mal...) maxStacks
    -- est nil, donc elle appelait SetMinMaxValues(0, 1) sur l'arc -- elle cassait l'etat
    -- qu'elle etait censee observer, et l'arc sautait a 100% jusqu'au tick suivant.
    local RC = GetRC()
    local probeStacks = IsStackMode() and activeInfo.maxStacks
    if not probeStacks then
        p("sonde ApplyStacksToCenterArc ignoree (spe sans mode stacks : elle ecraserait l'arc)")
    end
    if probeStacks and activeInfo.altSpellID then
        local c = GetCDMStackCount(activeInfo.altSpellID)
        p(string.format("GetCDMStackCount(altSpellID=%d) = %s", activeInfo.altSpellID, tostring(c)))
        if RC and RC.ApplyStacksToCenterArc then
            local dbg = {}
            local applied = RC.ApplyStacksToCenterArc(activeInfo.altSpellID, activeInfo.maxStacks or 1, GetArcColor(), dbg)
            p(string.format("  ApplyStacksToCenterArc(altSpellID) = %s  path=%s", tostring(applied), tostring(dbg.path)))
        end
    end
    if activeInfo.spellID then
        local c = GetCDMStackCount(activeInfo.spellID)
        p(string.format("GetCDMStackCount(spellID=%d) = %s", activeInfo.spellID, tostring(c)))
        if probeStacks and RC and RC.ApplyStacksToCenterArc then
            local dbg = {}
            local applied = RC.ApplyStacksToCenterArc(activeInfo.spellID, activeInfo.maxStacks or 1, GetArcColor(), dbg)
            p(string.format("  ApplyStacksToCenterArc(spellID) = %s  path=%s", tostring(applied), tostring(dbg.path)))
        end
    end

    p(string.format("GetRC() present=%s  SetCenterArcFill=%s  SetCenterArcEntry=%s  ApplyStacksToCenterArc=%s",
        tostring(RC ~= nil), tostring(RC and RC.SetCenterArcFill ~= nil), tostring(RC and RC.SetCenterArcEntry ~= nil),
        tostring(RC and RC.ApplyStacksToCenterArc ~= nil)))
    if RC and RC._debug_GetDurationArc then
        local arc, arcFrame = RC._debug_GetDurationArc()
        if arc then
            local okV, val = pcall(arc.GetValue, arc)
            local okMM, mn, mx = pcall(arc.GetMinMaxValues, arc)
            p(string.format("bar.durationArc: IsShown=%s Alpha=%.2f GetValue ok=%s val=%s GetMinMax ok=%s min=%s max=%s",
                tostring(arc:IsShown()), arc:GetAlpha(), tostring(okV), tostring(val), tostring(okMM), tostring(mn), tostring(mx)))
        else
            p("bar.durationArc introuvable (bar pas encore cree ?)")
        end
    end
end

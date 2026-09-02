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
    -- supportsAbsorbMode : le sort a un montant d'absorption trackable comme
    -- remplissage d'arc alternatif (cf. cfg.ignorePainArcAbsorb)
    -- useCDMBar : mode "duration" alimenté par le canal clone-bar (CDMHooks.lua,
    -- StatusBar:SetValue -- réellement combat-safe, contrairement au chemin
    -- CDM/durObj par défaut) -- nécessite que l'utilisateur épingle le sort sur
    -- le viewer "Barres" (BuffBarCooldownViewer) du Cooldown Manager Blizzard.
    [66]  = { spellID = 188370, isTotem = true,  castSpellID = 26573,
              color = {1.00, 0.88, 0.10}, cfgKey = "consecrationArcEnabled" },
    [73]  = { spellID = 190456, isTotem = false, color = {0.78, 0.25, 0.25}, cfgKey = "ignorePainArcEnabled",
              supportsAbsorbMode = true, useCDMBar = true },
    -- useCDMBar (2026-08-16) : meme resolution que Dur Au Mal (73) -- confirme
    -- en jeu via /rcarc que le chemin CDM/durObj par defaut laissait
    -- bar.durationArc a IsShown=false en combat (UNIT_AURA fallback mort
    -- depuis 12.1, AuraData toujours secrete) alors que
    -- IsCDMAuraBarPresent(188290)=true -- le canal clone-bar (event-driven,
    -- jamais de lecture de valeur secrete) etait deja alimente et inutilise.
    [250] = { spellID = 188290, isTotem = false, color = {0.20, 0.78, 0.35}, cfgKey = "dndArcEnabled",
              useCDMBar = true },
    -- Monk Mistweaver : Thé de Mana. useStackMode = remplissage selon un nombre
    -- de stacks (pas une durée ni une absorption) -- lu via castCountSpellID
    -- (115294, le sort ACTIVABLE) au lieu du buff (115867), qui n'est ni suivi
    -- par le CDM Blizzard ni trouvable via GetPlayerAuraBySpellID (confirmé en
    -- jeu, cf. ResourceMap.lua/ResourceCircle.lua). isTotem=false pour cet
    -- entry n'est pas utilisé : useStackMode court-circuite tout le chemin
    -- CDM/duration avant qu'isTotem soit consulté.
    [270] = { spellID = 115867, castCountSpellID = 115294, isTotem = false,
              color = {0.25, 0.85, 0.55}, cfgKey = "manaTeaArcEnabled",
              useStackMode = true, maxStacks = 20 },
    -- Demon Hunter Devourer (spec 1480, hero spec 12.0) : Fragments (1225789),
    -- altSpellID = fragments de vide (1227702) sous Métamorphose du vide --
    -- même paire spellID/altSpellID que ResourceMap.lua (texte de ressource
    -- secondaire), lue ici via GetCDMStackCount au lieu de castCountSpellID
    -- (pas de sort activable dédié pour ce compteur, contrairement au Thé de
    -- Mana -- StackModeTick essaye altSpellID puis spellID quand
    -- castCountSpellID est absent, cf. plus bas).
    [1480] = { spellID = 1225789, altSpellID = 1227702, isTotem = false,
               color = {0.70, 0.30, 1.00}, cfgKey = "devourerArcEnabled",
               useStackMode = true, maxStacks = 50 },
    -- Pas d'entrée [581] (DH Vengeance / Fragments d'âme) : l'utilisateur ne
    -- veut QUE le texte de ressource secondaire (ResourceMap.lua/
    -- SecondaryResourceDefs[581]), pas d'arc dédié pour ce spec.
}

local activeInfo      = nil
-- specID resolu au moment ou activeInfo est choisi (cf. handler
-- PLAYER_SPECIALIZATION_CHANGED plus bas) : utilise pour les reglages par
-- spec (ns.GetSecResCfg) plutot que le global _addon._specID, qui peut ne
-- pas encore etre a jour a cet instant precis (CONFIRME EN JEU dans
-- ResourceCircle.lua sur ce meme probleme : sans specID explicite, la
-- couleur/taille perso restait "collee" a la mauvaise spec jusqu'a ce qu'on
-- retouche un slider dans le panneau d'options, qui la corrigeait par
-- coincidence de timing).
local activeSpecID    = nil
local fallTicker      = nil
local fallExpiry      = 0
local fallMaxDur      = 0
local _arcFirstMissTime = nil
local _ARC_MISS_GRACE   = 0.5

-- Mode "absorb" (Dur Au Mal) : ticker dédié, indépendant du chemin CDM/durObj
-- normal (cf. AbsorbTick plus bas).
local absorbTicker      = nil
local _absorbWasPresent = false

-- Mode "stacks" (Thé de Mana) : ticker dédié, indépendant du chemin CDM/durObj
-- normal (cf. StackModeTick plus bas).
local stackModeTicker = nil

local function GetRC()
    return _addon and _addon.Modules and _addon.Modules.ResourceCircle
end

local function IsEnabled()
    if not activeInfo then return false end
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    return not cfg or cfg[activeInfo.cfgKey] ~= false
end

-- "duration" (défaut) ou "absorb" — seul activeInfo.supportsAbsorbMode (Dur Au
-- Mal) peut basculer sur "absorb", les autres restent toujours en "duration".
local function GetArcMode()
    if not (activeInfo and activeInfo.supportsAbsorbMode) then return "duration" end
    local cfg = _addon.GetCfg and _addon.GetCfg("resourceCircle")
    return (cfg and cfg.ignorePainArcAbsorb) and "absorb" or "duration"
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

-- Mode "cdmbar" (cf. CDMHooks.lua "ABONNEMENTS CLONE BAR") : pas de ticker,
-- canal event-driven -- juste (dés)abonnement du proxy ResourceCircle au
-- spellID courant.
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

-- Teste val == 0 sans jamais planter si val est une secret value (même
-- helper que IsConfirmedZero dans ResourceCircle.lua/PriorityBar.lua).
local function IsConfirmedZeroLocal(val)
    if val == nil then return false end
    local ok, isZero = pcall(function() return val == 0 end)
    return ok and isZero == true
end

-- Présence RÉELLE de l'aura spellID sur le joueur. On ne peut PAS se fier à
-- la simple présence d'une entrée cdmData : cdmData n'est JAMAIS nettoyé
-- (cf. commentaire détaillé dans ResourceCircle.lua), une entrée Dur Au Mal
-- reste donc indéfiniment même une fois le buff expiré.
--
-- BUG CORRIGÉ : la validation utilisait GetAuraApplicationDisplayCount sur
-- l'instID du hook CDM (cdmEntry.instID), inutilisable pour TOUT lookup --
-- échouait donc systématiquement en combat (mode absorb de Dur Au Mal jamais rempli). On
-- utilise à la place IsCDMAuraSwipePresent (CDMHooks.lua, event-driven,
-- alimenté par le même swipe CDM que la durée), avec GetPlayerAuraBySpellID
-- en repli hors combat / juste après l'application du buff.
local function IsAuraPresent(spellID)
    if ns.IsCDMAuraSwipePresent and ns.IsCDMAuraSwipePresent(spellID) then return true end
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    return ok and auraData ~= nil
end

-- Variante de IsAuraPresent qui renvoie le COMPTE de stacks (pas juste sa
-- présence) : même sink combat-safe (GetAuraApplicationDisplayCount sur
-- l'instID trouvé dans cdmData), même logique que ApplyStacksToText dans
-- ResourceCircle.lua, mais sans ses fallbacks GetPlayerAuraBySpellID/enum
-- HELPFUL -- inutiles ici pour une aura moderne déjà confirmée bien suivie
-- par le CDM (cf. secResText, qui fonctionne pour ce même spellID). nil =
-- absent/périmé, jamais 0 : la valeur brute peut être secrète en combat,
-- jamais comparée, seulement transmise telle quelle à SetCenterArcFill.
local function GetCDMStackCount(spellID)
    local cdmPlayer = ns.cdmData and ns.cdmData.player
    local cdmEntry = cdmPlayer and cdmPlayer[spellID]
    if not (cdmEntry and cdmEntry.instID) then return nil end
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if ok and disp ~= nil then return disp end
    return nil
end

-- Plafond d'absorption de Dur Au Mal (cumul max de dégâts ignorés, dépend des
-- stats du joueur). Lu depuis le texte de description du sort plutôt que
-- depuis les données d'aura en combat : ce texte n'est PAS une valeur secrète
-- (donnée de sort statique, déjà lisible dans le grimoire même en combat),
-- contrairement à AuraData.points (cf. ApplyAbsorbToText dans ResourceCircle.lua).
-- On prend le DERNIER nombre du texte : Blizzard y indique d'abord
-- l'absorption d'une utilisation simple, puis le cumul max ("...jusqu'à un
-- total de N points de dégâts ignorés") en dernier, quelle que soit la langue.
-- Caché quelques secondes pour éviter de re-parser le texte à chaque tick.
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

-- Mode "absorb" : remplit l'arc selon le montant d'absorption restant de Dur
-- Au Mal plutôt que le temps restant. `absorb` (UnitGetTotalAbsorbs/UnitAbsorb)
-- est potentiellement un secret number en combat : AUCUNE arithmétique dessus
-- — on fixe juste les bornes (maxAbsorb, un number normal issu du texte de
-- sort) et on passe absorb BRUT à SetCenterArcFill, qui calcule le
-- remplissage côté C (même pattern que UpdateAbsorb dans UnitBars.lua). Tourne
-- en continu tant que la spec active supporte ce mode ; no-op interne si
-- GetArcMode() ~= "absorb", pour ne jamais avoir besoin de resynchroniser ce
-- ticker avec le toggle du panneau d'options.
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

-- Mode "stacks" : remplit l'arc selon un nombre de stacks plutôt qu'une durée
-- ou une absorption. Deux sources possibles selon la spec (cf. ResourceCircle.lua/
-- UpdateSecondaryResource, même ordre de priorité pour rester cohérent avec le
-- texte de ressource secondaire qui utilise déjà l'une ou l'autre) :
--   1) castCountSpellID (Thé de Mana, Moine Mistweaver) : C_Spell.GetSpellCastCount
--      sur le sort ACTIVABLE (115294) -- le buff lui-même (115867) n'est ni suivi
--      par le CDM Blizzard ni trouvable via GetPlayerAuraBySpellID (confirmé en jeu).
--   2) altSpellID puis spellID (Fragments de vide/normaux, DH Dévoreur) : aura
--      stackable, via RC.ApplyStacksToCenterArc -- CDM + fallbacks (identique à
--      ApplyStacksToText dans ResourceCircle.lua, cf. son commentaire). CONFIRMÉ
--      EN JEU : une 1ère version ici ne cherchait QUE dans cdmData (via
--      GetCDMStackCount, gardée plus haut pour /rcarc), et l'arc du Dévoreur
--      restait vide alors que le texte (qui, lui, a toujours eu les fallbacks)
--      s'affichait correctement pour le même spellID -- la vraie donnée n'était
--      trouvable QUE par un fallback pour cette aura, jamais via cdmData seul.
-- `count` potentiellement secret en combat dans les deux cas : AUCUNE
-- arithmétique/comparaison dessus, passé BRUT à SetCenterArcFill/
-- ApplyStacksToCenterArc (sink combat-safe, même pattern que AbsorbTick ci-dessus).
local function StackModeTick()
    if not (activeInfo and activeInfo.useStackMode) then
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
    -- Bascule vers le mode "absorb" pendant que ce ticker tournait encore (rare,
    -- juste après un changement de réglage) : on cède la main à AbsorbTick.
    if GetArcMode() == "absorb" then StopFallback(); return end
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
    if activeInfo.useStackMode then return end  -- StackModeTick possède bar.durationArc dans ce mode
    if GetArcMode() == "absorb" then return end  -- AbsorbTick possède bar.durationArc dans ce mode
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

------------------------------------------------------------------------
-- EVENTS
------------------------------------------------------------------------
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("UNIT_AURA")
evtFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
evtFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

-- Résout activeInfo fraîchement + (re)démarre les tickers associés. Factorisé
-- pour être appelable depuis 2 endroits : l'event handler (spec change/login)
-- ET ns.ResyncCenterArc (rappelé quand l'utilisateur toggle une checkbox
-- d'arc dans le panneau d'options, cf. SettingsPanel.lua) -- sans ce 2e point
-- d'entrée, activer le toggle d'une spe dont activeInfo ne s'était jamais
-- résolu correctement (ex: race au login/reload, cf. bug ns._specID corrigé
-- ci-dessous) ne relançait jamais la resolution/les tickers : seul un VRAI
-- changement de spe le faisait, jamais un simple clic sur la checkbox.
local function ResolveActiveArc()
    StopFallback(); PushNil(); _arcFirstMissTime = nil
    StopAbsorbTicker()
    StopStackModeTicker()
    StopCDMBarMode()
    -- Résolution FRAÎCHE en priorité (comme DetectSecondaryResource dans
    -- ResourceCircle.lua) : _addon._specID (cache global, PAS ns._specID --
    -- ns ici = _addon.Auras, un namespace différent où _specID n'est jamais
    -- rempli ; confirmé en lisant le code, cette 2e forme était un bug muet)
    -- peut ne pas encore être à jour à cet instant précis -- confirmé en jeu
    -- comme cause d'une personnalisation par spec qui ne s'appliquait qu'après
    -- avoir retouché un slider dans le panneau d'options.
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
    -- DESACTIVE (2026-08-12) : AuraTextRelay.lua (systeme AuraContainer natif
    -- Blizzard) -- candidateFilters ne filtre jamais correctement en jeu,
    -- cf. commentaire detaille dans Whitelist.lua:BuildWhitelist. Le fallback
    -- cdmData/GetAuraApplicationDisplayCount ci-dessous (IsAuraPresent/
    -- GetCDMStackCount) reste actif tel quel -- fonctionne hors combat et
    -- pour Maelstrom Weapon (deja lisible via ResourceMap.lua par ailleurs).
    -- if activeInfo and ns.EnsureAuraTextOverlay then
    --     if activeInfo.spellID then ns.EnsureAuraTextOverlay("player", activeInfo.spellID) end
    --     if activeInfo.altSpellID then ns.EnsureAuraTextOverlay("player", activeInfo.altSpellID) end
    -- end
    if ns.AutoConfigCenterArc then
        pcall(ns.AutoConfigCenterArc)
        if ns.BuildWhitelist then pcall(ns.BuildWhitelist) end
    end
    if activeInfo and activeInfo.isTotem then pcall(ScanTotemArc) end
    if activeInfo and activeInfo.supportsAbsorbMode then
        absorbTicker = C_Timer.NewTicker(0.1, AbsorbTick)
    end
    if activeInfo and activeInfo.useStackMode then
        stackModeTicker = C_Timer.NewTicker(0.1, StackModeTick)
    end
    StartCDMBarMode()
end
ns.ResyncCenterArc = ResolveActiveArc

local function OnCenterArcEvent(_, event, arg1, arg2, arg3)

    ---------- SPEC CHANGE / ENTERING WORLD ----------
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        ResolveActiveArc()

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
        if activeInfo.useStackMode then return end  -- StackModeTick gère ce mode
        if GetArcMode() == "absorb" then return end  -- AbsorbTick gère ce mode
        if activeInfo.useCDMBar then return end  -- canal clone-bar event-driven gère ce mode

        local data = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
                     and C_UnitAuras.GetPlayerAuraBySpellID(activeInfo.spellID)
        -- Patch 12.1 (2026-08-11) : les AuraData renvoyees par C_UnitAuras sont
        -- desormais TOUJOURS totalement secretes (plus seulement en combat).
        -- expirationTime/duration ne peuvent donc plus etre lus en arithmetique
        -- ou compares directement -- pcall autour de tout le calcul : s'il
        -- echoue (valeurs secretes), ce fallback hors-CDM n'a plus de moyen
        -- de produire une fraction numerique pour un arc dessine a la main
        -- (contrairement a un StatusBar natif, qui peut consommer un durObj
        -- opaque sans le lire). On echoue donc proprement plutot que de
        -- planter le ticker 60fps.
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

------------------------------------------------------------------------
-- DEBUG : /rcarc — état complet de l'arc secondaire (ex-"arc de durée")
------------------------------------------------------------------------
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
    p(string.format("IsEnabled()=%s  cfg[%s]=%s  stackModeTicker actif=%s",
        tostring(IsEnabled()), tostring(activeInfo.cfgKey), tostring(cfg and cfg[activeInfo.cfgKey]), tostring(stackModeTicker ~= nil)))
    p(string.format("GetArcMode()=%s  ignorePainArcAbsorb=%s  _cdmBarActiveSpellID=%s  IsCDMAuraBarPresent(spellID)=%s",
        tostring(GetArcMode()), tostring(cfg and cfg.ignorePainArcAbsorb), tostring(_cdmBarActiveSpellID),
        tostring(activeInfo.spellID and ns.IsCDMAuraBarPresent and ns.IsCDMAuraBarPresent(activeInfo.spellID))))

    -- GetCDMStackCount = tier CDM seul (diagnostic rapide) ; RC.ApplyStacksToCenterArc
    -- (avec dbg) = la VRAIE chaine utilisee par StackModeTick (CDM + fallbacks 1/2,
    -- identique a ApplyStacksToText/le texte) -- c'est CE 2e resultat qui compte,
    -- le 1er peut mentir (confirme en jeu : CDM seul echouait, un fallback reussissait).
    local RC = GetRC()
    if activeInfo.altSpellID then
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
        if RC and RC.ApplyStacksToCenterArc then
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

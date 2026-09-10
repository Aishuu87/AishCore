-- AishUIAura/Core/Scan.lua
-- Scanner d'auras CDM-only (Midnight 12.0+). Source unique de verite : ns.cdmData[unit][spellID] =
-- { spellId, name, instID }, maintenu par CDMHooks.lua via SetAuraInstanceInfo des 4 viewers Blizzard.
-- Cle = spellID (pas auraInstanceID, potentiellement secret et donc inutilisable comme cle de table) ;
-- instID reste stocke comme valeur (usage cle/comparaison interdit s'il est secret).
-- CDM exclusivement : combat-safe (spellID toujours clean), pas de slot recycle, pas de cache obsolete,
-- couvre toutes les classes.
-- Pipeline : ns.cdmData -> Scan:CollectAuras/CollectPlayerBuffs -> _allScratch -> Scan:FilterAllDests
-- (split debuffs/cooldowns/procs/buffs + tri) -> ns.auraData -> renders.

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.Scan = {}
local Scan = ns.Scan

local pcall, type, ipairs, pairs, tinsert, wipe = pcall, type, ipairs, pairs, table.insert, wipe
local UnitExists = UnitExists
local HAS_ISSECRET = (type(issecretvalue) == "function")

-- API Blizzard
local GetAuraDuration              = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount

-- Accesseurs combat-safe (pattern "show but don't know")

-- Lecture safe du spellID depuis une AuraData brute, avec protection issecret. Seul fallback pour une
-- aura non identifiee (cdmData etant cle par spellID, il ne peut plus servir a deviner un spellID inconnu).
function ns.SafeSpellID(aura, unit)
    if not aura then return nil end
    local v = aura.spellId
    if v == nil then return nil end
    if HAS_ISSECRET and issecretvalue(v) then return nil end
    if type(v) == "number" then return v end
    return nil
end

-- Lecture safe des stacks. Combat-aware : GetAuraApplicationDisplayCount peut
-- retourner secret en combat sur sort CDM. On verifie issecret avant comparaison.
function ns.SafeStacks(aura, unit, instID)
    local stacks = 0
    -- Tentative 1 : aura.applications direct
    pcall(function()
        if aura.applications and not (HAS_ISSECRET and issecretvalue(aura.applications)) then
            stacks = aura.applications
        end
    end)
    -- Tentative 2 : GetAuraApplicationDisplayCount(auraInstanceID, min, max), souvent dispo meme quand
    -- applications est secret. Pas de parametre "unit" malgre la doc generale de cette API.
    if stacks == 0 and instID and GetAuraApplicationDisplayCount then
        pcall(function()
            local c = GetAuraApplicationDisplayCount(instID, 1, 999)
            if c ~= nil and not (HAS_ISSECRET and issecretvalue(c)) and tonumber(c) and tonumber(c) > 0 then
                stacks = tonumber(c)
            end
        end)
    end
    return stacks
end

-- L'auraInstanceID du hook CDM est refuse par toutes les API qui en dependent (GetAuraDataByAuraInstanceID,
-- GetAuraApplicationDisplayCount, GetAuraDuration) : cdmData ne sert qu'a lister les spellID actifs, la
-- donnee reelle vient de GetPlayerAuraBySpellID (joueur, echoue pour totems/enchant d'arme) ou en repli
-- de GetAuraDataByIndex matche par nom (plus fiable que spellID ici).
local function FindAuraInList(unit, filter, spellID, name)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 40 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        -- ok=false signifie que CETTE position est secrete, pas que la liste est finie (Blizzard leve
        -- "Auras cannot be accessed when secret" par position). Un break ici raterait toutes les auras
        -- lisibles situees apres la 1ere secrete. Seule une fin CONFIRMEE (ok=true, d=nil) arrete la boucle.
        if ok and not d then break end
        if ok and d then
            if name then
                local okN, isN = pcall(function() return d.name == name end)
                if okN and isN then return d end
            end
            local okS, isS = pcall(function() return d.spellId == spellID end)
            if okS and isS then return d end
        end
        -- ok=false : aura secrète à cette position, on continue vers la suivante.
    end
    return nil
end

-- En combat, C_UnitAuras refuse toutes les auras a duree limitee (GetPlayerAuraBySpellID et
-- GetAuraDataByIndex) : utilisable seulement hors combat, ou pour une ressource persistante sans minuteur
-- (ex. Maelstrom Weapon via applications). En combat, voir ns.cdmAuraSwipePresence / ns.SubscribeCDMAuraSwipe
-- (CDMHooks.lua), canal event-driven alimente par le CDM lui-meme, independant de C_UnitAuras.
local function GetAuraDataForSpell(unit, spellID, name)
    if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and auraData then return auraData end
    end
    local filter = (unit == "player") and "HELPFUL" or "HARMFUL"
    return FindAuraInList(unit, filter, spellID, name)
end

-- Cache "derniere donnee connue" (presence + stacks) : aucun canal CDM (swipe/bar/instID) ne s'est revele
-- fiable en combat pour certains sorts (Precurseur du Vide, Fragments d'ame). En cas d'echec de lecture en
-- combat on reutilise la derniere entree confirmee plutot que "absent"/"0 stacks", jusqu'a la prochaine
-- lecture reussie ou une disparition confirmee explicitement par le CDM. Ne concerne pas la duree (barres).
ns._lastKnownAura = ns._lastKnownAura or { player = {}, target = {} }

-- [spellID] = true des qu'un vrai signal positif a ete observe sur swipe/bar CDM. Necessaire car pour
-- certains sorts, cdmAuraBarPresence vaut en permanence false (jamais de vrai timestamp) : sans cette
-- garde, "== false" serait pris a tort pour une confirmation de disparition des le premier scan.
local everConfirmedByCDM = { player = {}, target = {} }

local function MakeEntry(unit, spellID, cdmName)
    if not spellID then return nil end
    local swipePresent = (ns.IsCDMAuraSwipePresent and ns.IsCDMAuraSwipePresent(spellID))
                       or (ns.IsCDMAuraBarPresent and ns.IsCDMAuraBarPresent(spellID))
    if swipePresent then everConfirmedByCDM[unit][spellID] = true end
    local cache = ns._lastKnownAura[unit]

    -- Hooks OnShow/OnHide sur AuraContainer natif rejetes par Blizzard ("blocked by secret aspects",
    -- contrairement a hooksecurefunc pour le CDM, cf. AuraTrackerContainer.lua) : le cache ci-dessous
    -- reste la seule approximation disponible.
    local auraData = GetAuraDataForSpell(unit, spellID, cdmName)

    if not auraData then
        local cached = cache[spellID]
        if cached then
            -- Hors combat, un nil de GetAuraDataForSpell signifie vraiment "aura disparue". En combat, ce
            -- nil est indetermine (lecture bloquee) : on garde le cache sauf disparition confirmee par le
            -- CDM (swipe/bar passe a false sur un spellID ou ce canal a deja fonctionne, cf. everConfirmedByCDM).
            if not ns._inCombat then
                cache[spellID] = nil
            else
                local swipeGone = everConfirmedByCDM[unit][spellID]
                               and ns.cdmAuraSwipePresence and ns.cdmAuraSwipePresence[spellID] == false
                local barGone   = everConfirmedByCDM[unit][spellID]
                               and ns.cdmAuraBarPresence and ns.cdmAuraBarPresence[spellID] == false
                if swipeGone or barGone then
                    cache[spellID] = nil
                else
                    return cached
                end
            end
        end
        -- Rien en cache : seul le CDM peut encore confirmer une presence brute, et uniquement en combat
        -- (hors combat, l'absence de auraData est deja la reponse definitive).
        if not swipePresent or not ns._inCombat then return nil end
    end

    local okInst, instID = pcall(function() return auraData and auraData.auraInstanceID end)
    instID = okInst and instID or nil
    local durObj
    if instID then
        local okDur, d = pcall(GetAuraDuration, unit, instID)
        durObj = okDur and d or nil
    end
    -- Repli direct duration/expirationTime : GetAuraDuration echoue silencieusement pour certaines auras
    -- pourtant lisibles autrement (ex. Glacons/205473). issecretvalue() verifie dans le meme pcall que le calcul.
    local directStart, directDuration
    if not durObj and auraData then
        local okCalc, start, dur = pcall(function()
            local d, e = auraData.duration, auraData.expirationTime
            if d == nil or e == nil then return nil, nil end
            if HAS_ISSECRET and (issecretvalue(d) or issecretvalue(e)) then return nil, nil end
            return e - d, d
        end)
        if okCalc and start ~= nil then directStart, directDuration = start, dur end
    end

    local entry = {
        aura     = auraData,
        durObj   = durObj,
        directStart    = directStart,
        directDuration = directDuration,
        instID   = instID,
        spellID  = spellID,
        stacks   = ns.SafeStacks(auraData, unit, instID),
        unit     = unit,
        name     = cdmName,
        -- Sans durObj ni directStart/directDuration, les renders doivent piloter leur Cooldown via
        -- ns.SubscribeCDMAuraSwipe plutot que d'attendre une donnee qui ne viendra jamais en combat.
        useCDMSwipe = swipePresent and not durObj and not directStart,
    }
    -- Ne memorise que les entrees issues d'une lecture directe reussie, jamais celles construites via le
    -- seul repli swipePresent (presence/stacks non exploitables), pour ne pas ecraser une bonne donnee en cache.
    if auraData then cache[spellID] = entry end
    return entry
end

-- /aishdebug auratrace <spellID> : dump pas-a-pas de tout ce que MakeEntry voit pour ce sort (2 unites,
-- sans filtre whitelist), pour comprendre pourquoi une aura n'apparait pas en combat.
function ns.DebugTraceAura(spellID)
    local P = function(s) print("|cff33aaff[AuraTrace]|r " .. s) end
    if not spellID then P("usage : /aishdebug auratrace <spellID>"); return end
    P(string.format("spellID=%d  ns._inCombat=%s", spellID, tostring(ns._inCombat)))

    for _, unit in ipairs({"player", "target"}) do
        local cdmDataU = ns.cdmData and ns.cdmData[unit]
        local cdmEntry = cdmDataU and cdmDataU[spellID]
        P(string.format("-- unit=%s -- cdmData present=%s%s", unit, tostring(cdmEntry ~= nil),
            cdmEntry and string.format(" (name=%s instID=%s)", tostring(cdmEntry.name), tostring(cdmEntry.instID)) or ""))
        -- Canal "presence pure" (SetAuraInstanceInfo) : valeur brute et ce que le tier en fait reellement.
        -- Hors du `if cdmEntry` car ce canal peut repondre pour des sorts dont cdmData ne dit rien d'utile.
        do
            local raw = ns.cdmAuraInstancePresence and ns.cdmAuraInstancePresence[unit]
                        and ns.cdmAuraInstancePresence[unit][spellID]
            local eff = ns.IsCDMAuraInstancePresent and ns.IsCDMAuraInstancePresent(unit, spellID)
            P(string.format("   instancePresence brute=%s | tier autoritaire=%s",
                tostring(raw), tostring(eff)))
        end
        if cdmEntry then
            local swipeOk = ns.IsCDMAuraSwipePresent and ns.IsCDMAuraSwipePresent(spellID)
            local barOk   = ns.IsCDMAuraBarPresent and ns.IsCDMAuraBarPresent(spellID)
            P(string.format("   swipePresent=%s  barPresent=%s", tostring(swipeOk), tostring(barOk)))
            -- Distingue timestamp jamais vu (nil) de vu-mais-perime (age > seuil).
            local swipeT = ns.cdmAuraSwipePresence and ns.cdmAuraSwipePresence[spellID]
            local barT   = ns.cdmAuraBarPresence and ns.cdmAuraBarPresence[spellID]
            P(string.format("   swipeTimestamp=%s%s  barTimestamp=%s%s",
                tostring(swipeT),
                (type(swipeT) == "number") and string.format(" (age=%.1fs)", GetTime() - swipeT) or "",
                tostring(barT),
                (type(barT) == "number") and string.format(" (age=%.1fs)", GetTime() - barT) or ""))

            -- Etat du cache "derniere donnee connue", utilise pour la presence/stacks quand la lecture directe echoue.
            local cached = ns._lastKnownAura and ns._lastKnownAura[unit] and ns._lastKnownAura[unit][spellID]
            P(string.format("   cache derniere donnee connue : present=%s%s",
                tostring(cached ~= nil),
                cached and string.format(" (stacks=%s)", tostring(cached.stacks)) or ""))

            local okData, auraData = pcall(GetAuraDataForSpell, unit, spellID, cdmEntry.name)
            P(string.format("   GetAuraDataForSpell : pcall_ok=%s result_nil=%s", tostring(okData), tostring(auraData == nil)))
            if okData and auraData then
                -- Comparer une valeur potentiellement secrete hors pcall dedie planterait silencieusement le print.
                local okCalc, nilD, secD, nilE, secE = pcall(function()
                    local d, e = auraData.duration, auraData.expirationTime
                    local isNilD, isNilE = (d == nil), (e == nil)
                    local isSecD = (not isNilD) and HAS_ISSECRET and issecretvalue(d)
                    local isSecE = (not isNilE) and HAS_ISSECRET and issecretvalue(e)
                    return isNilD, isSecD, isNilE, isSecE
                end)
                if okCalc then
                    P(string.format("   duration: is_nil=%s is_secret=%s | expirationTime: is_nil=%s is_secret=%s",
                        tostring(nilD), tostring(secD), tostring(nilE), tostring(secE)))
                else
                    P("   duration/expirationTime : lecture/comparaison a echoue (pcall ko)")
                end
                local okInst, instID = pcall(function() return auraData.auraInstanceID end)
                instID = okInst and instID or nil
                if instID then
                    local okDur, durObj = pcall(GetAuraDuration, unit, instID)
                    P(string.format("   GetAuraDuration : pcall_ok=%s durObj_nil=%s", tostring(okDur), tostring(not durObj)))
                end
            end

            local entry = MakeEntry(unit, spellID, cdmEntry.name)
            P(string.format("   => MakeEntry renverrait : %s", entry and "UNE ENTREE (devrait s'afficher)" or "nil (INVISIBLE)"))
        end
    end
end

-- Collecte : itere sur ns.cdmData[unit] (cle = spellID) uniquement.
-- Scratch reutilisee entre les 2 appels de CollectFromCDM par scan (target puis player) : sans risque, le
-- premier appel est entierement consomme avant que le second ne demarre.
local _collectScratch = {}

local function CollectFromCDM(unit)
    wipe(_collectScratch)
    local all = _collectScratch
    local cdmDataU = ns.cdmData and ns.cdmData[unit]
    if not cdmDataU then return all end

    local anyWL = ns.anyWhitelist
    for spellID, cdmEntry in pairs(cdmDataU) do
        local keep = (not anyWL) or (anyWL[spellID] == true)
        if keep then
            local entry = MakeEntry(unit, spellID, cdmEntry.name)
            if entry then tinsert(all, entry) end
        end
    end
    return all
end

function Scan:CollectAuras(unit)        return CollectFromCDM(unit) end
function Scan:CollectPlayerBuffs()      return CollectFromCDM("player") end

function ns.IsInWhitelist(wl, sid)
    if not wl or sid == nil then return false end
    return wl[sid] ~= nil
end

-- Construction d'une output entry : extrait les metadonnees du sort (couleurs, modeles 3D...) et construit
-- la table finale envoyee aux renders. Pool d'entries reutilisables sans risque (contrairement a MakeEntry) :
-- ns.auraData[dest] est integralement remplace a chaque scan, personne n'en garde de reference entre 2 ticks.
local _entryPools = { iconlist = {}, circlebars = {}, icons = {}, freebars = {}, centerArc = {} }

local function _BuildOutputEntry(e, sid, si, dest, poolIdx)
    -- Champs FX3D : utilise GetFlatFieldsByDest pour supporter le per-render override.
    -- Lit s.fx3d[dest][tab] avec fallback s.fx3d["all"][tab] si dest n'a rien.
    local fx
    if ns.SpellFX and ns.SpellFX.GetFlatFieldsByDest then
        fx = ns.SpellFX:GetFlatFieldsByDest(sid, dest)
    end
    local pool = poolIdx and _entryPools[dest]
    local t = (pool and pool[poolIdx]) or {}
    if pool then pool[poolIdx] = t end

    t.auraInstanceID = e.instID
    t.aura           = e.aura
    t.durObj         = e.durObj
    t.directStart    = e.directStart
    t.directDuration = e.directDuration
    t.useCDMSwipe    = e.useCDMSwipe
    t.spellID        = sid
    t.stacks         = e.stacks
    t.unit           = e.unit
    t.spellColor     = si and si.color
    t.glowColor      = si and si.glowColor
    t.spellGlow      = si and si.glow or false
    t.glowIdx        = si and si.glowIdx or 1
    t.glowAlpha      = si and si.glowAlpha or 0.7
    t.glowScale      = si and si.glowScale or 1.0
    t.desat          = si and si.desat or false
    t.procGlowIdx    = si and si.procGlowIdx or 1
    t.procGlowScale  = si and si.procGlowScale or 1.0
    -- Modeles 3D barre (per-render via fx, fallback si.barXxx)
    t.barModelID     = fx and fx.barModelID    or (si and si.barModelID or 0)
    t.barModelA      = fx and fx.barModelA     or (si and si.barModelA or 0.5)
    t.barModelRot    = fx and fx.barModelRot   or (si and si.barModelRot or 0)
    t.barModelX      = fx and fx.barModelX     or (si and si.barModelX or 0)
    t.barModelY      = fx and fx.barModelY     or (si and si.barModelY or 0)
    t.barModelZ      = fx and fx.barModelZ     or (si and si.barModelZ or 0)
    t.barModelS      = fx and fx.barModelS     or (si and si.barModelS or 1.0)
    t.barModelMode   = fx and fx.barModelMode  or (si and si.barModelMode or "bg")
    t.barModelL      = fx and fx.barModelL     or (si and si.barModelL or "back")
    t.barFxW         = fx and fx.barFxW        or (si and si.barFxW or 0)
    t.barFxH         = fx and fx.barFxH        or (si and si.barFxH or 0)
    -- 2D Fill (mode "Remplissage" pattern LinearProgressTexture)
    t.barFillTex     = fx and fx.barFillTex    or (si and si.barFillTex or "")
    t.barFillAlpha   = fx and fx.barFillAlpha  or (si and si.barFillAlpha or 0.7)
    t.barFillTintR   = fx and fx.barFillTintR  or (si and si.barFillTintR or 1)
    t.barFillTintG   = fx and fx.barFillTintG  or (si and si.barFillTintG or 1)
    t.barFillTintB   = fx and fx.barFillTintB  or (si and si.barFillTintB or 1)
    t.barFillScroll  = fx and fx.barFillScroll or (si and si.barFillScroll or 0)
    t.barFillLayer   = fx and fx.barFillLayer  or (si and si.barFillLayer or "front")
    t.barOverlayTex  = fx and fx.barOverlayTex   or (si and si.barOverlayTex or "")
    t.barOverlayA    = fx and fx.barOverlayA     or (si and si.barOverlayA or 0.3)
    t.barOverlaySpeed = fx and fx.barOverlaySpeed or (si and si.barOverlaySpeed or 0.5)
    -- Modeles 3D icone
    t.iconModelID    = fx and fx.iconModelID  or (si and si.iconModelID or 0)
    t.iconModelA     = fx and fx.iconModelA   or (si and si.iconModelA or 0.5)
    t.iconModelX     = fx and fx.iconModelX   or (si and si.iconModelX or 0)
    t.iconModelY     = fx and fx.iconModelY   or (si and si.iconModelY or 0)
    t.iconModelZ     = fx and fx.iconModelZ   or (si and si.iconModelZ or 0)
    t.iconModelRot   = fx and fx.iconModelRot or (si and si.iconModelRot or 0)
    t.iconModelS     = fx and fx.iconModelS   or (si and si.iconModelS or 1.0)
    t.iconModelL     = fx and fx.iconModelL   or (si and si.iconModelL or "back")
    t.iconFxW        = fx and fx.iconFxW      or (si and si.iconFxW or 0)
    t.iconFxH        = fx and fx.iconFxH      or (si and si.iconFxH or 0)
    t.iconPosX       = fx and fx.iconPosX     or (si and si.iconPosX or 0)
    t.iconPosY       = fx and fx.iconPosY     or (si and si.iconPosY or 0)
    -- Modeles 3D spark
    t.sparkModelID   = fx and fx.sparkModelID  or (si and si.sparkModelID or 0)
    t.sparkModelA    = fx and fx.sparkModelA   or (si and si.sparkModelA or 0.7)
    t.sparkModelRot  = fx and fx.sparkModelRot or (si and si.sparkModelRot or 0)
    t.sparkModelX    = fx and fx.sparkModelX   or (si and si.sparkModelX or 0)
    t.sparkModelY    = fx and fx.sparkModelY   or (si and si.sparkModelY or 0)
    t.sparkModelZ    = fx and fx.sparkModelZ   or (si and si.sparkModelZ or 0)
    t.sparkModelS    = fx and fx.sparkModelS   or (si and si.sparkModelS or 0.5)
    t.sparkModelL    = fx and fx.sparkModelL   or (si and si.sparkModelL or "front")
    t.sparkFxW       = fx and fx.sparkFxW      or (si and si.sparkFxW or 0)
    t.sparkFxH       = fx and fx.sparkFxH      or (si and si.sparkFxH or 0)
    t.sparkPosX      = fx and fx.sparkPosX     or (si and si.sparkPosX or 0)
    t.sparkPosY      = fx and fx.sparkPosY     or (si and si.sparkPosY or 0)
    return t
end

-- Scratch tables de dispatch, reutilisees a chaque appel (perf combat) : purement transitoires,
-- consommees dans ce meme appel, donc sans risque a wipe()+reutiliser plutot que reallouer.
local _bySpellD, _bySpellC, _bySpellP, _bySpellB, _bySpellR = {}, {}, {}, {}, {}

-- Filtrage par destination (split debuffs/cooldowns/procs/buffs + tri). Une aura peut appartenir a
-- plusieurs destinations. Pas de dedup par expiry : avec le CDM source, jamais deux entries pour le meme spellID.
function Scan:FilterAllDests(allAuras)
    local wlD = ns.whitelistByDest and ns.whitelistByDest.iconlist
    local wlC = ns.whitelistByDest and ns.whitelistByDest.circlebars
    local wlP = ns.whitelistByDest and ns.whitelistByDest.icons
    local wlB = ns.whitelistByDest and ns.whitelistByDest.freebars
    local wlR = ns.whitelistByDest and ns.whitelistByDest.centerArc
    local orD = ns.slotOrderByDest and ns.slotOrderByDest.iconlist
    local orC = ns.slotOrderByDest and ns.slotOrderByDest.circlebars
    local orP = ns.slotOrderByDest and ns.slotOrderByDest.icons
    local orB = ns.slotOrderByDest and ns.slotOrderByDest.freebars
    local orR = ns.slotOrderByDest and ns.slotOrderByDest.centerArc

    local hasD = wlD and orD and #orD > 0
    local hasC = wlC and orC and #orC > 0
    local hasP = wlP and orP and #orP > 0
    local hasB = wlB and orB and #orB > 0
    local hasR = wlR and orR and #orR > 0
    if not (hasD or hasC or hasP or hasB or hasR) then return {}, {}, {}, {}, {} end

    -- Dispatch par destination : 1 entry CDM = 1 entry par destination ou elle matche
    wipe(_bySpellD); wipe(_bySpellC); wipe(_bySpellP); wipe(_bySpellB); wipe(_bySpellR)
    local bySpellD, bySpellC, bySpellP, bySpellB, bySpellR = _bySpellD, _bySpellC, _bySpellP, _bySpellB, _bySpellR
    for _, e in ipairs(allAuras) do
        local sid = e.spellID
        if sid then
            if hasD and wlD[sid] then bySpellD[sid] = e end
            if hasC and wlC[sid] then bySpellC[sid] = e end
            if hasP and wlP[sid] then bySpellP[sid] = e end
            if hasB and wlB[sid] then bySpellB[sid] = e end
            if hasR and wlR[sid] then bySpellR[sid] = e end
        end
    end

    -- Tri par ordre de priorite (orderByDest) et construction des outputs.
    -- idx : position dans CE tableau de sortie pour CE scan --
    -- sert de cle au pool d'entries reutilisables (cf. _BuildOutputEntry).
    local spells = ns.GetSpecSpells()
    local sA, fA, iA, bA, rA = {}, {}, {}, {}, {}
    if hasD then local idx=0; for _, sid in ipairs(orD) do local e = bySpellD[sid]; if e then idx=idx+1; tinsert(sA, _BuildOutputEntry(e, sid, spells and spells[sid], "iconlist", idx))   end end end
    if hasC then local idx=0; for _, sid in ipairs(orC) do local e = bySpellC[sid]; if e then idx=idx+1; tinsert(fA, _BuildOutputEntry(e, sid, spells and spells[sid], "circlebars", idx)) end end end
    if hasP then local idx=0; for _, sid in ipairs(orP) do local e = bySpellP[sid]; if e then idx=idx+1; tinsert(iA, _BuildOutputEntry(e, sid, spells and spells[sid], "icons", idx))      end end end
    if hasB then local idx=0; for _, sid in ipairs(orB) do local e = bySpellB[sid]; if e then idx=idx+1; tinsert(bA, _BuildOutputEntry(e, sid, spells and spells[sid], "freebars", idx))   end end end
    if hasR then local idx=0; for _, sid in ipairs(orR) do local e = bySpellR[sid]; if e then idx=idx+1; tinsert(rA, _BuildOutputEntry(e, sid, spells and spells[sid], "centerArc", idx))  end end end

    return sA, fA, iA, bA, rA
end

-- Preview live (menus Liste d'icones / Barres de cercle / Icones / Barres libres) : pendant qu'un de ces
-- menus est ouvert, ns._previewBars == true et ns._previewMode contient la dest concernee. Scan:Run
-- remplace alors le contenu de cette dest par PREVIEW_COUNT fausses entrees "_isPreview" pour visualiser
-- taille/position/couleurs en direct, meme sans aura reelle active (et en masquant volontairement les
-- vraies auras le temps de l'edition). Source des icones : en priorite les sorts reellement configures
-- (ns.slotOrderByDest[dest]) pour une preview fidele, complete par des icones generiques sinon. Chaque
-- entree porte _isPreview = true, detecte par Animation.lua pour animer la barre en boucle 12s sans durObj.
local PREVIEW_COUNT = 3
local PREVIEW_FALLBACK_ICONS = {
    "Interface\\Icons\\Spell_Holy_HolyBolt",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
    "Interface\\Icons\\Spell_Fire_Fireball02",
}
-- Stacks fictifs 0/3/2 pour qu'une ou deux icones de preview montrent le compteur (cf. ApplyStackCharges
-- dans Debuffs.lua, qui lit entry.stacks directement pour les entrees _isPreview).
local PREVIEW_STACKS = {0, 3, 2}

-- noFallback : n'affiche que les sorts reellement assignes a cette dest (pas d'icones generiques de
-- remplissage). Utilise par le menu "Auras a tracker" pour previsualiser fidelement l'etat de la liste.
local function BuildPreviewEntries(dest, noFallback)
    local out = {}
    local spells = ns.GetSpecSpells()
    local order = ns.slotOrderByDest and ns.slotOrderByDest[dest]
    for i = 1, PREVIEW_COUNT do
        local realSID = order and order[i]
        if noFallback and not realSID then break end
        local si = realSID and spells and spells[realSID]
        -- spellIDs magiques 900001-900003 : reserves aux fake bars, ne
        -- correspondent a aucun vrai sort, et passent le filtre whitelist
        -- (cf. checks "spellID > 900000" dans Debuffs/Cooldowns/Procs).
        local sid = realSID or (900000 + i)
        local fakeE = {
            instID = -(900000 + i),
            stacks = PREVIEW_STACKS[i] or 0,
            unit   = "player",
        }
        local entry = _BuildOutputEntry(fakeE, sid, si, dest)
        entry._isPreview = true
        if realSID then
            local ok, tex = pcall(C_Spell.GetSpellTexture, realSID)
            entry._previewIcon = (ok and tex) or PREVIEW_FALLBACK_ICONS[i] or PREVIEW_FALLBACK_ICONS[1]
        else
            entry._previewIcon = PREVIEW_FALLBACK_ICONS[i] or PREVIEW_FALLBACK_ICONS[1]
        end
        tinsert(out, entry)
    end
    return out
end

-- Run : point d'entree principal du scan. Recycle des tables scratch pour eviter le GC pressure en combat.
local _allScratch = {}
local _auraDataScratch = { iconlist = {}, freebars = {}, circlebars = {}, icons = {}, centerArc = {} }

function Scan:Run()
    if not ns._whitelistBuilt then ns.BuildWhitelist() end
    pcall(function()
        wipe(_allScratch)
        if UnitExists("target") then
            for _, e in ipairs(Scan:CollectAuras("target")) do tinsert(_allScratch, e) end
        end
        for _, e in ipairs(Scan:CollectPlayerBuffs()) do tinsert(_allScratch, e) end

        -- Entrée synthétique pour les sorts-totem (ex. Consécration Pala Prot) :
        -- Blizzard n'expose jamais leur buff via SetAuraInstanceInfo, donc
        -- CollectFromCDM ne les voit jamais. Cf. CenterArc.lua:GetTotemSyntheticEntry.
        if ns.GetTotemSyntheticEntry then
            local ok, e = pcall(ns.GetTotemSyntheticEntry)
            if ok and e then tinsert(_allScratch, e) end
        end

        local sA, fA, iA, bA, rA = Scan:FilterAllDests(_allScratch)

        -- Mode preview (fake bars) : remplace le contenu de la dest active par
        -- des fausses entrees pour visualisation en direct (cf. BuildPreviewEntries).
        local pvMode = ns._previewMode  -- nil | "all" | "iconlist" | "circlebars" | "icons" | "freebars"
        if ns._previewBars and pvMode then
            local nf = ns._previewNoFallback
            if pvMode == "all" or pvMode == "iconlist"   then sA = BuildPreviewEntries("iconlist", nf)   end
            if pvMode == "all" or pvMode == "circlebars" then fA = BuildPreviewEntries("circlebars", nf) end
            if pvMode == "all" or pvMode == "icons"      then iA = BuildPreviewEntries("icons", nf)      end
            if pvMode == "all" or pvMode == "freebars"   then bA = BuildPreviewEntries("freebars", nf)   end
        end

        _auraDataScratch.iconlist   = sA
        _auraDataScratch.circlebars = fA
        _auraDataScratch.icons      = iA
        _auraDataScratch.freebars   = bA
        _auraDataScratch.centerArc  = rA
        ns.auraData = _auraDataScratch

        -- Compteur pour idle mode des drivers d'animation
        ns._activeAuraCount = #sA + #fA + #iA + #bA + #rA
        if ns._activeAuraCount > 0 then
            if ns.WakeTimerDriver then ns.WakeTimerDriver() end
            if ns.WakeAnimDriver  then ns.WakeAnimDriver()  end
        end

        -- Dispatch vers les renders
        for id, render in pairs(ns.RenderRegistry) do
            if render.Update then pcall(render.Update, render, ns.auraData[id] or {}) end
        end
    end)
end

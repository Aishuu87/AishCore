-- AishUIAura/Core/Scan.lua
--
-- Scanner d'auras CDM-only (Midnight 12.0+).
--
-- ARCHITECTURE :
--   Source unique de verite = ns.cdmData[unit][spellID] = { spellId, name, instID }
--   maintenu par CDMHooks.lua via les hooks SetAuraInstanceInfo des 4 viewers
--   Blizzard (Essential, Utility, BuffIcon, BuffBar).
--
--   Cle = spellID (PAS auraInstanceID) : depuis Secret Values (12.0+), un
--   auraInstanceID peut etre secret et ne peut alors plus servir de cle de
--   table (crash "cannot be indexed with secret keys"), alors que spellID
--   reste TOUJOURS clean sur ce hook (Blizzard le donne en clair via
--   frame.cooldownInfo.spellID, un champ CDM interne distinct des AuraData
--   secretisables). instID reste indispensable pour GetAuraDuration/
--   GetAuraApplicationDisplayCount, mais stocke comme VALEUR de table -- ce
--   qui reste toujours autorise, secret ou non, seul son usage comme CLE ou
--   dans une comparaison (==) est interdit.
--
-- POURQUOI CDM EXCLUSIVEMENT :
--   - Combat-safe : Blizzard nous donne le spellID en clair (pas de taint)
--   - Pas de slot recycle (bug observe sur GetAuraSlots ou Numbing partage inst=8 avec Rupture)
--   - Pas de cache obsolete (tout est event-driven)
--   - Marche pour toutes les classes (les 4 viewers couvrent tout)
--
-- PIPELINE :
--   ns.cdmData -> Scan:CollectAuras / CollectPlayerBuffs -> _allScratch
--             -> Scan:FilterAllDests (split par debuffs/cooldowns/procs/buffs + tri)
--             -> ns.auraData -> renders
------------------------------------------------------------------------

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.Scan = {}
local Scan = ns.Scan

local pcall, type, ipairs, pairs, tinsert, wipe = pcall, type, ipairs, pairs, table.insert, wipe
local UnitExists = UnitExists
local HAS_ISSECRET = (type(issecretvalue) == "function")

-- API Blizzard
local GetAuraDuration              = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount

------------------------------------------------------------------------
-- ACCESSEURS COMBAT-SAFE (pattern "show but don't know")
------------------------------------------------------------------------

-- Lecture safe du spellID depuis une AuraData brute (aura.spellId, avec
-- protection issecret). cdmData est desormais cle par spellID (voir plus
-- haut) donc ne peut plus servir a "deviner" un spellID a partir d'un
-- auraInstanceID inconnu -- ce cas (aura non identifiee) retombe sur ce
-- seul fallback, comme avant.
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
    -- Tentative 2 : API display count (souvent dispo meme quand applications est secret).
    -- Signature : GetAuraApplicationDisplayCount(auraInstanceID, min, max)
    -- -- PAS de parametre "unit" (contrairement a ce que suggere la documentation
    -- generale de cette API). Un appel avec "unit" en argument #1 leve "bad argument #1" des que
    -- l'instID n'est pas secret (masque sinon par l'erreur de taint sur un instID secret).
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

------------------------------------------------------------------------
-- RÉCUPÉRATION DE L'AURADATA POUR UN SPELLID CONNU
--
-- IMPORTANT (patch 12.1) : L'auraInstanceID fourni par le
-- hook CDM (cdmAura.auraInstanceID dans SetAuraInstanceInfo, CDMHooks.lua)
-- est refusé par TOUTES les API qui en dépendent -- pas seulement
-- GetAuraDataByAuraInstanceID, mais AUSSI GetAuraApplicationDisplayCount et
-- GetAuraDuration, qui étaient supposées "blessed"/sûres avec un secret.
-- Les trois lèvent la même exception ("Auras cannot be accessed when secret
-- while tainted by 'AishCore'"). cdmData ne peut donc plus servir QUE de
-- liste "quels spellID sont actifs actuellement" (les clés, toujours
-- propres) -- toute donnée doit être re-obtenue par un canal INDÉPENDANT du
-- hook CDM.
--
-- DEUX repêchages nécessaires :
--  1) GetPlayerAuraBySpellID(spellID) marche pour le joueur ET renvoie des
--     données intégralement propres -- mais ÉCHOUE (renvoie nil, sans
--     erreur) pour une partie des sorts pourtant actifs et visibles dans le
--     CDM (ex: totems élémentaires, enchant d'arme). Le spellID que le hook
--     CDM expose (frame.cooldownInfo.spellID, potentiellement un ID de
--     variante/rang lié) ne correspond alors pas au spellID réel de
--     l'AuraData appliquée.
--  2) Dans ce cas on retombe sur une énumération (GetAuraDataByIndex) et on
--     matche par NOM plutôt que par spellID -- le nom (cdmEntry.name, déjà
--     lu proprement par CDMHooks.lua) correspond même quand l'ID diffère.
--     La comparaison spellId reste tentée en second (repli historique),
--     protégée par pcall (peut échouer si spellId est secret).
------------------------------------------------------------------------
local function FindAuraInList(unit, filter, spellID, name)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 40 do
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        -- IMPORTANT : ok=false à un index donné signifie que
        -- CETTE aura précise (celle à cette position) est secrète -- pas que la
        -- liste est terminée. Blizzard lève "Auras cannot be accessed when
        -- secret" pour cette position sans que les positions SUIVANTES soient
        -- forcément concernées. Un `break` ici arrêterait l'énumération dès la
        -- 1ère aura secrète rencontrée (souvent en position #1), ratant TOUTES
        -- les auras lisibles situées après (l'énumération s'arrêtant
        -- systématiquement à l'index #1 en combat). Seule une fin de
        -- liste CONFIRMÉE (ok=true, d=nil) doit arrêter la boucle.
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

-- En combat, TOUTES les auras à durée limitée
-- sont refusées par C_UnitAuras (GetPlayerAuraBySpellID ET GetAuraDataByIndex,
-- sans exception, toutes positions confondues) -- cette fonction ne renvoie
-- donc quelque chose d'utilisable QUE hors combat, ou pour une ressource
-- persistante sans minuteur (ex: Maelstrom Weapon, lu via applications).
-- Pour la vivacité/le swipe EN combat, voir ns.cdmAuraSwipePresence /
-- ns.SubscribeCDMAuraSwipe (CDMHooks.lua) -- canal event-driven alimenté par
-- le CDM lui-même (code Blizzard non tainté), indépendant de C_UnitAuras.
local function GetAuraDataForSpell(unit, spellID, name)
    if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and auraData then return auraData end
    end
    local filter = (unit == "player") and "HELPFUL" or "HARMFUL"
    return FindAuraInList(unit, filter, spellID, name)
end

------------------------------------------------------------------------
-- CACHE "DERNIÈRE DONNÉE CONNUE" (présence + stacks). Après plusieurs
-- tentatives de re-confirmer activement la présence/les stacks en combat via
-- divers canaux CDM (swipe/bar/GetAuraApplicationDisplayCount sur l'instID),
-- toutes se sont révélées non-fiables en combat pour certains sorts
-- (Précurseur du Vide, Fragments d'âme -- /aishdebug auratrace), quelle que
-- soit la méthode. Plutôt que de continuer à chercher un signal de reconfirmation
-- combat-safe qui n'existe pas pour ces sorts, on adopte le principe qui
-- fonctionnait avant le passage au CDM pour la durée : la lecture directe
-- (GetAuraDataForSpell) reste la SEULE source de vérité pour la présence et
-- les stacks -- mais quand elle échoue (typiquement en combat), on NE
-- RÉINITIALISE PAS l'état à "absent"/"0 stacks" : on réutilise la DERNIÈRE
-- entrée confirmée par une lecture directe réussie, telle quelle, jusqu'à
-- ce qu'une nouvelle lecture directe réussisse (fin de combat, ou tout
-- moment où C_UnitAuras redevient lisible) ou que le CDM confirme
-- explicitement le contraire (frame.Cooldown Clear() ou hi=0 après une
-- vraie plage positive -- cf. swipePresent/barPresent ci-dessous, qui
-- restent utilisés comme signal d'ABSENCE, pas de présence).
--
-- La DURÉE (barres) reste entièrement gérée par le CDM (durObj/
-- directDuration/useCDMSwipe plus bas) -- ce cache ne concerne QUE la
-- présence et les stacks, pas les champs de durée.
ns._lastKnownAura = ns._lastKnownAura or { player = {}, target = {} }

-- [spellID] = true des qu'un VRAI signal positif (timestamp actif, pas juste
-- "pas encore perime") a ete observe sur le swipe OU la bar CDM pour ce
-- spellID. Necessaire pour la garde d'invalidation du cache ci-dessous :
-- pour Precurseur du Vide/Fragments d'ame, ns.cdmAuraBarPresence[spellID]
-- vaut EN PERMANENCE false (jamais un vrai timestamp -- Blizzard n'envoie
-- que hi=0 pour ce type de sort, cf. CDMHooks.lua) -- sans cette garde,
-- "== false" y serait interprete a tort comme une confirmation de
-- disparition a CHAQUE scan, videant le cache avant meme qu'il ait pu
-- servir (l'aura redeviendrait invisible en combat malgre le cache).
local everConfirmedByCDM = { player = {}, target = {} }

------------------------------------------------------------------------
-- CRÉATION D'ENTRÉE
------------------------------------------------------------------------
local function MakeEntry(unit, spellID, cdmName)
    if not spellID then return nil end
    local swipePresent = (ns.IsCDMAuraSwipePresent and ns.IsCDMAuraSwipePresent(spellID))
                       or (ns.IsCDMAuraBarPresent and ns.IsCDMAuraBarPresent(spellID))
    if swipePresent then everConfirmedByCDM[unit][spellID] = true end
    local cache = ns._lastKnownAura[unit]

    -- NOTE : une tentative de presence combat-safe via AuraContainer natif
    -- (hooks OnShow/OnHide poses depuis initializeFrame) a ete tentee et
    -- abandonnee : Blizzard rejette explicitement
    -- auraButton:HookScript("OnShow"/"OnHide", ...) avec "blocked by secret
    -- aspects", contrairement au pattern hooksecurefunc qui fonctionne pour
    -- le CDM (CDMHooks.lua). Restriction plateforme, pas contournable par du
    -- code -- cf. AuraTrackerContainer.lua pour le detail complet. Le cache
    -- ci-dessous reste donc la seule approximation disponible pour la
    -- presence.
    local auraData = GetAuraDataForSpell(unit, spellID, cdmName)

    if not auraData then
        local cached = cache[spellID]
        if cached then
            -- Hors combat, GetAuraDataForSpell EST fiable (c'est justement
            -- l'hypothese de base de tout ce cache) -- un resultat nil hors
            -- combat signifie donc VRAIMENT "l'aura a disparu", pas juste
            -- "pas encore relu". Vider le cache UNIQUEMENT sur un signal CDM
            -- explicite (jamais declenche pour ces sorts, cf.
            -- everConfirmedByCDM) laisserait l'icone affichee indefiniment
            -- meme hors combat, avec le dernier stacks connu (y compris un
            -- badge "0" figé). En combat en revanche, ce nil est indetermine
            -- (lecture bloquee) -- on continue a faire confiance au cache
            -- dans ce cas.
            if not ns._inCombat then
                cache[spellID] = nil
            else
                -- Invalide quand meme le cache si le CDM confirme
                -- EXPLICITEMENT une disparition (Clear() reel sur le
                -- Cooldown, ou hi=0 sur la Bar apres une vraie plage
                -- positive -- cf. HookCDMCooldownChild/HookCDMBarChild,
                -- CDMHooks.lua) : signal fiable UNIQUEMENT pour un spellID
                -- dont on a deja vu ce canal fonctionner (cf.
                -- everConfirmedByCDM ci-dessus) -- sinon son "false"
                -- permanent n'a jamais rien confirmé du tout.
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
        -- Jamais lu directement avec succès pour ce spellID cette session (ou
        -- cache invalidé ci-dessus) : seul le CDM peut encore confirmer une
        -- présence brute (sans stacks ni durée exploitables) -- UNIQUEMENT en
        -- combat (hors combat, l'absence de auraData est déjà la réponse
        -- définitive, cf. ci-dessus -- ne pas laisser un swipe/bar périmé la
        -- contredire).
        if not swipePresent or not ns._inCombat then return nil end
    end

    local okInst, instID = pcall(function() return auraData and auraData.auraInstanceID end)
    instID = okInst and instID or nil
    local durObj
    if instID then
        local okDur, d = pcall(GetAuraDuration, unit, instID)
        durObj = okDur and d or nil
    end
    -- Repli direct duration/expirationTime (pas durObj) : GetAuraDuration
    -- échoue silencieusement (ok=true, val=nil) pour certaines auras
    -- pourtant lisibles autrement (ex: Glaçons/205473). auraData.duration/
    -- expirationTime se sont montrés NON secrets pour ce type d'aura (ressource perso).
    -- Arithmétique protégée par pcall : si secrète, échoue proprement et on
    -- retombe sur le relais CDM (useCDMSwipe) plus bas -- SetCooldown lui
    -- accepte une valeur secrète brute sans problème une fois calculée.
    -- IMPORTANT (régression confirmée en jeu) : ne JAMAIS soustraire des
    -- valeurs dont on n'a pas explicitement vérifié via issecretvalue()
    -- qu'elles sont non secrètes -- ça a cassé tout MakeEntry (stacks
    -- compris) la première fois. On vérifie donc AVANT tout calcul, dans le
    -- même pcall que la lecture, plutôt que d'espérer que l'arithmétique
    -- échoue proprement toute seule.
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
        -- Pas de durObj NI de directStart/directDuration (combat, aura sans
        -- expirationTime lisible) : les renders doivent piloter leur widget
        -- Cooldown via ns.SubscribeCDMAuraSwipe(spellID, key, cd) plutôt que
        -- d'attendre une donnée qui ne viendra jamais en combat pour ce sort.
        useCDMSwipe = swipePresent and not durObj and not directStart,
    }
    -- Ne memorise QUE les entrees issues d'une lecture directe reussie
    -- (auraData non nil) -- pas celles construites uniquement via le repli
    -- swipePresent (presence/stacks non exploitables), qui ne doivent jamais
    -- ecraser une derniere bonne donnee deja en cache.
    if auraData then cache[spellID] = entry end
    return entry
end

------------------------------------------------------------------------
-- DIAGNOSTIC : /aishdebug auratrace <spellID> -- dump pas-a-pas de tout ce
-- que MakeEntry voit pour ce spellID (les 2 unites), sans filtre whitelist.
-- Sert a comprendre POURQUOI une aura n'apparait pas en combat : quel(s)
-- signal(aux) de presence sont a true/false, ce que GetAuraDataForSpell
-- renvoie exactement (succes/echec/nil), et l'etat du cache "derniere
-- donnee connue" (ns._lastKnownAura) pour ce sort.
------------------------------------------------------------------------
function ns.DebugTraceAura(spellID)
    local P = function(s) print("|cff33aaff[AuraTrace]|r " .. s) end
    if not spellID then P("usage : /aishdebug auratrace <spellID>"); return end
    P(string.format("spellID=%d  ns._inCombat=%s", spellID, tostring(ns._inCombat)))

    for _, unit in ipairs({"player", "target"}) do
        local cdmDataU = ns.cdmData and ns.cdmData[unit]
        local cdmEntry = cdmDataU and cdmDataU[spellID]
        P(string.format("-- unit=%s -- cdmData present=%s%s", unit, tostring(cdmEntry ~= nil),
            cdmEntry and string.format(" (name=%s instID=%s)", tostring(cdmEntry.name), tostring(cdmEntry.instID)) or ""))
        if cdmEntry then
            local swipeOk = ns.IsCDMAuraSwipePresent and ns.IsCDMAuraSwipePresent(spellID)
            local barOk   = ns.IsCDMAuraBarPresent and ns.IsCDMAuraBarPresent(spellID)
            P(string.format("   swipePresent=%s  barPresent=%s", tostring(swipeOk), tostring(barOk)))
            -- Detail brut : timestamp jamais vu (nil) vs vu-mais-perime (age > seuil) --
            -- distingue "Blizzard n'appelle jamais SetCooldown/SetValue pour ce sort"
            -- de "il appelle, mais pas assez souvent pour le seuil de peremption actuel".
            local swipeT = ns.cdmAuraSwipePresence and ns.cdmAuraSwipePresence[spellID]
            local barT   = ns.cdmAuraBarPresence and ns.cdmAuraBarPresence[spellID]
            P(string.format("   swipeTimestamp=%s%s  barTimestamp=%s%s",
                tostring(swipeT),
                (type(swipeT) == "number") and string.format(" (age=%.1fs)", GetTime() - swipeT) or "",
                tostring(barT),
                (type(barT) == "number") and string.format(" (age=%.1fs)", GetTime() - barT) or ""))

            -- Etat du cache "derniere donnee connue" (ns._lastKnownAura) : LE
            -- mecanisme reellement utilise desormais pour la presence/stacks
            -- quand la lecture directe echoue (cf. MakeEntry).
            local cached = ns._lastKnownAura and ns._lastKnownAura[unit] and ns._lastKnownAura[unit][spellID]
            P(string.format("   cache derniere donnee connue : present=%s%s",
                tostring(cached ~= nil),
                cached and string.format(" (stacks=%s)", tostring(cached.stacks)) or ""))

            local okData, auraData = pcall(GetAuraDataForSpell, unit, spellID, cdmEntry.name)
            P(string.format("   GetAuraDataForSpell : pcall_ok=%s result_nil=%s", tostring(okData), tostring(auraData == nil)))
            if okData and auraData then
                -- ATTENTION : comparer une valeur potentiellement secrete (d == nil)
                -- HORS d'un pcall dedie peut planter silencieusement tout le print --
                -- lecture ET comparaison protegees ENSEMBLE, un seul pcall.
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

------------------------------------------------------------------------
-- COLLECTE — itere sur ns.cdmData[unit] (cle = spellID) uniquement
------------------------------------------------------------------------
-- Scratch reutilisee entre les 2 appels de CollectFromCDM par scan ("target"
-- puis "player", cf. Scan:Run) -- sans risque : le premier appel est
-- entierement consomme (copie dans _allScratch via tinsert) AVANT que le
-- second ne demarre, jamais les deux vivants simultanement.
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

------------------------------------------------------------------------
-- IsInWhitelist (helper hoiste)
------------------------------------------------------------------------
function ns.IsInWhitelist(wl, sid)
    if not wl or sid == nil then return false end
    return wl[sid] ~= nil
end

------------------------------------------------------------------------
-- CONSTRUCTION D'UNE OUTPUT ENTRY
-- Extrait les metadonnees du sort (couleurs, modeles 3D, etc.) et construit
-- la table finale envoyee aux renders.
------------------------------------------------------------------------
-- POOL D'ENTRIES REUTILISABLES (checkup memoire/perf combat) :
-- _BuildOutputEntry etait appelee une fois PAR AURA TRACKEE PAR DESTINATION
-- ET PAR SCAN, allouant a chaque fois une table fraiche de ~50 champs -- en
-- combat, avec plusieurs scans par seconde (cf. CDMHooks.lua), ca fait
-- beaucoup de garbage genere pour rien. SANS RISQUE de reutiliser le meme
-- objet table d'un scan a l'autre ICI (contrairement a MakeEntry plus haut,
-- dont le resultat EST mis en cache longue duree -- surtout pas touche) :
-- personne ne conserve de reference longue duree vers CES entries --
-- ns.auraData[dest] est integralement remplace a chaque scan (Scan:Run), et
-- Animation.lua relit toujours ns.auraData[dest] a la volee a chaque tick,
-- jamais de reference gardee entre 2 ticks. Un pool PAR DESTINATION, indexe
-- par position dans le tableau de sortie de cette destination pour ce scan,
-- suffit -- les slots au-dela du nombre d'auras de ce scan restent
-- simplement inutilises (pas liberes, cout negligeable, jamais retournes).
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

-- Scratch tables de dispatch, reutilisees a chaque appel (perf
-- combat) -- purement transitoires (construites puis integralement
-- consommees DANS ce meme appel, jamais retournees ni conservees), donc
-- sans aucun risque a wipe()+reutiliser plutot que reallouer 5 tables a
-- chaque scan.
local _bySpellD, _bySpellC, _bySpellP, _bySpellB, _bySpellR = {}, {}, {}, {}, {}

------------------------------------------------------------------------
-- FILTRAGE PAR DESTINATION (split debuffs/cooldowns/procs/buffs + tri)
--
-- Une aura peut appartenir a plusieurs destinations (si l'utilisateur l'a
-- coche dans plusieurs categories dans "Sorts a tracker").
-- Pas de dedup par expiry : avec le CDM source, il n'y a JAMAIS deux entries
-- pour le meme spellID (chaque aura est unique cote Blizzard).
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- PREVIEW LIVE (menus Liste d'icones / Barres de cercle / Icones / Barres
-- libres)
--
-- Pendant qu'un de ces menus est ouvert, ns._previewBars == true et
-- ns._previewMode contient la dest concernee ("iconlist"/"circlebars"/
-- "icons"/"freebars", ou "all"). Scan:Run REMPLACE alors le contenu de
-- cette dest par PREVIEW_COUNT fausses entrees "_isPreview" pour que
-- l'utilisateur visualise taille/position/couleurs en direct — meme si
-- aucune vraie aura n'est active, et meme si une vraie aura l'est (on
-- remplace volontairement : cacher les vraies auras pendant l'edition
-- du menu n'est pas genant).
--
-- Source des icones : en priorite les sorts reellement configures par
-- l'utilisateur pour cette dest (ns.slotOrderByDest[dest], dans l'ordre
-- de priorite) -> preview "fidele" avec les vraies couleurs/glow/FX.
-- S'il en manque, on complete avec des icones generiques (pas de couleur
-- specifique -> fallback ns.barColor / couleur de classe).
--
-- Chaque entree porte le flag _isPreview = true, detecte par
-- Animation.lua pour animer la barre en boucle 12s sans durObj reel.
------------------------------------------------------------------------
local PREVIEW_COUNT = 3
local PREVIEW_FALLBACK_ICONS = {
    "Interface\\Icons\\Spell_Holy_HolyBolt",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
    "Interface\\Icons\\Spell_Fire_Fireball02",
}
-- Stacks fictifs : 0/3/2 pour qu'une ou deux icones de preview montrent
-- le compteur de stacks (cf. ApplyStackCharges dans Debuffs.lua qui lit
-- entry.stacks directement pour les entrees _isPreview).
local PREVIEW_STACKS = {0, 3, 2}

-- noFallback : n'affiche que les sorts reellement coches/assignes a cette
-- dest (pas d'icones generiques de remplissage). Utilise par le menu "Auras
-- a tracker" (Tactics.lua) pour previsualiser fidelement l'etat de la liste,
-- contrairement aux menus de rendu par emplacement qui remplissent toujours
-- a PREVIEW_COUNT pour donner un aperçu meme sans sort assigne.
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

------------------------------------------------------------------------
-- RUN — point d'entree principal du scan
-- Recycle des tables scratch pour eviter le GC pressure en combat.
------------------------------------------------------------------------
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

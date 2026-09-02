-- AishUIAura/Core/Events.lua
-- Dispatcher d'events Blizzard : ADDON_LOADED, PLAYER_*, UNIT_AURA, etc.
-- Déclenche l'init, les rebuilds, scans, fades et re-hooks CDM selon les events.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local wipe, pcall = wipe, pcall
local CreateFrame, C_Timer, InCombatLockdown = CreateFrame, C_Timer, InCombatLockdown
local ipairs, pairs = ipairs, pairs

-- Compteur de refresh par auraInstanceID. Incrémenté par UNIT_AURA.updatedAuraInstanceIDs
-- quand le payload n'est PAS secret (cf. guard issecretvalue(info.isFullUpdate) dans le
-- handler UNIT_AURA plus bas -- depuis le patch 12.1, ce payload peut lui-même devenir
-- intégralement secret, y compris isFullUpdate).
-- Utilisé par GetAuraKey pour forcer le relancement de SetTimerDuration au recast,
-- sans JAMAIS lire les valeurs potentiellement secret des auras.
ns._refreshCounter = ns._refreshCounter or {}

------------------------------------------------------------------------
-- IDLE WIPE : purge des caches après inactivité prolongée hors combat.
--
-- Objectif : en fin de session longue (raid de 3h, quête prolongée), les caches
-- internes peuvent accumuler des entrées orphelines (instIDs d'auras vues sur
-- d'anciennes cibles, refreshCounters obsolètes). Ces caches sont auto-cleanés
-- par scan, mais seulement pour les instIDs vus récemment. Les orphelins y
-- restent potentiellement des heures.
--
-- Solution : timer qui se déclenche 5 min après la fin du dernier combat. Si
-- l'user est toujours hors combat à ce moment → wipe des caches + collectgarbage.
-- Si l'user re-rentre en combat avant → on annule le timer (pas de wipe pendant
-- l'action).
------------------------------------------------------------------------
local IDLE_WIPE_DELAY = 300  -- 5 minutes
local idleWipeTimer = nil

local function CancelIdleWipe()
    if idleWipeTimer then idleWipeTimer:Cancel(); idleWipeTimer = nil end
end

local function ScheduleIdleWipe()
    CancelIdleWipe()
    idleWipeTimer = C_Timer.NewTimer(IDLE_WIPE_DELAY, function()
        idleWipeTimer = nil
        -- Double-check : si l'user est re-rentré en combat entre-temps, skip.
        if ns._inCombat then return end
        -- Wipe les caches volumineux qui ont pu accumuler des orphelins.
        if ns._refreshCounter then wipe(ns._refreshCounter) end
        if ns.cdmData then
            if ns.cdmData.target then wipe(ns.cdmData.target) end
            if ns.cdmData.player then wipe(ns.cdmData.player) end
        end
        -- Force GC Lua : libère les tables déréférencées.
        collectgarbage("collect")
        -- Rescan léger pour repeupler les auras actuellement visibles (sinon
        -- la prochaine barre qui change devra tout recalculer).
        if ns.ScanAuras then pcall(ns.ScanAuras) end
    end)
end

------------------------------------------------------------------------
-- DEBOUNCE HELPERS HOIST : utilisés par UNIT_AURA, SPELL_UPDATE_CHARGES,
-- UNIT_SPELLCAST_SUCCEEDED, PLAYER_REGEN_DISABLED, PLAYER_TARGET_CHANGED.
--
-- Ces fonctions sont passées à C_Timer.After en remplacement de closures
-- inline. Gain : zéro allocation de closure à chaque event (UNIT_AURA peut
-- firer 10+ fois par seconde en raid). Fonctions minuscules → coût nul.
------------------------------------------------------------------------
local function _TargetScanDebounced()
    ns._targetScanPending = false
    pcall(ns.ScanAuras)
end
local function _PlayerScanDebounced()
    ns._playerScanPending = false
    pcall(ns.ScanAuras)
end
local function _ChargesScanDebounced()
    ns._chargesScanPending = false
    pcall(ns.ScanAuras)
end
local function _ScanAurasSafe()
    pcall(ns.ScanAuras)
end
local function _InitCombatScans()
    -- Rebuild + rescan au début du combat (plusieurs retries rapprochés pour
    -- attraper les DOTs appliqués juste avant/pendant l'entrée en combat).
    pcall(ns.BuildWhitelist)
    pcall(ns.InitCDMHooks)
    pcall(ns.ScanAuras)
end

------------------------------------------------------------------------
-- SCAN ADAPTATIF PLAYER_TARGET_CHANGED
--
-- Ancien système : 7 C_Timer.After en série (0.03, 0.06, 0.1, 0.15, 0.22, 0.3, 0.5)
-- → 7 scans TOUS exécutés, même si le premier a déjà trouvé les auras.
--
-- Nouveau système : on programme la série mais on annule les timers restants dès
-- qu'un scan retourne _activeAuraCount > 0 (= on a trouvé les DOTs). Dans le cas
-- commun (Blizzard répond en <50ms), on ne fait que 1-2 scans au lieu de 7.
--
-- En pire cas (Blizzard lent), on fait quand même les 7 scans → filet de sécurité
-- identique. En cas favorable (90%+ des tab targets), on économise 5-6 scans.
--
-- ATTENTION — POURQUOI ON WIPE cdmData.target À CHAQUE TAB TARGET :
-- Ne PAS céder à la tentation de garder cdmData.target persistant entre cibles
-- (comme ElvUI). Les auraInstanceID peuvent être réutilisés par Blizzard entre
-- cibles différentes, et un cache persistant introduit des FAUX POSITIFS :
-- on affiche un Rip sur mob B alors qu'il a juste une aura avec le même instID
-- que notre ancien Rip sur mob A. ElvUI accepte ce bug car ils n'ont pas de
-- whitelist stricte. Nous, avec une whitelist, ça se voit direct → sorts
-- fantômes affichés. Le wipe + retries = prix à payer pour la CORRECTION.
-- Le délai de 30-50ms au tab target est VOLONTAIRE : il laisse GetAuraSlots
-- retourner les données authoritatives fraîches de la nouvelle cible.
------------------------------------------------------------------------
local _targetRetryTimers = {}
local _targetRetryGen = 0  -- génération : incrémentée à chaque nouveau tab target

local function _CancelTargetRetries()
    for i = 1, #_targetRetryTimers do
        if _targetRetryTimers[i] then _targetRetryTimers[i]:Cancel() end
        _targetRetryTimers[i] = nil
    end
end

-- Callback d'un retry : scan, check si on a trouvé, si oui cancel le reste.
local function _TargetRetryScan(gen)
    -- Si un autre tab target est passé entre-temps, ce retry est obsolète.
    if gen ~= _targetRetryGen then return end
    pcall(ns.ScanAuras)
    -- Si on a trouvé au moins une aura, cancel les retries restants + reset le flag
    -- (plus besoin d'attendre l'UNIT_AURA fast-path, c'est trouvé).
    if (ns._activeAuraCount or 0) > 0 then
        _CancelTargetRetries()
        ns._awaitingTargetFullUpdate = false
    end
end

------------------------------------------------------------------------
-- EVENTS (dispatcher principal)
------------------------------------------------------------------------
local ef = CreateFrame("Frame")
ef:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        pcall(function() ns.InitDB() end)
        pcall(function() ns.InitAllRenders() end)
        pcall(function() if ns.MissingBuffs then ns.MissingBuffs.Init() end end)

        -- Note : l'aplatissement de la bibliothèque de modèles 3D (~19 MB) a été
        -- déplacé en lazy-load. Il est désormais déclenché par ns.EnsureModelPaths()
        -- à la première ouverture du ModelPicker. Économie : ~25 MB de RAM au démarrage
        -- si l'utilisateur n'ouvre jamais le picker dans sa session.

        C_Timer.After(0.5, function()
            ns.Try("InitCDMHooks@0.5s", ns.InitCDMHooks)
            ns.Try("ScanCDMViewers@0.5s", ns.ScanCDMViewers)
            pcall(ns.RefreshCDMMask)
        end)
        C_Timer.After(2.0, function()
            ns.Try("InitCDMHooks@2.0s", ns.InitCDMHooks)
            ns.Try("ScanCDMViewers@2.0s", ns.ScanCDMViewers)
            pcall(ns.RefreshCDMMask)
        end)
        C_Timer.After(0.3, function()
            if ns.AutoConfigCenterArc then pcall(ns.AutoConfigCenterArc) end
            ns.BuildWhitelist()
            if ns.db and ns.db.enabled then pcall(function() ns.InitAllRenders() end) end
            ns.ScanAuras(); ns._inCombat = InCombatLockdown(); ns.UpdateAllFades()
            pcall(function() if ns.Profiles then ns.Profiles.ApplySpecProfile() end end)
            C_Timer.After(2, function() pcall(function() if ns.Providers then ns.Providers:Init() end end) end)
            -- INIT FLAG (pattern ArcUI) : empêche l'affichage des bars pendant la phase
            -- de chargement/reload. Les Update() early-return tant que ce flag est false.
            -- Activé ici, après ScanAuras initial, pour garantir que toutes les données
            -- sont prêtes avant le premier rendu visible. Évite le flash de bars vides
            -- ou mal configurées au /reload.
            C_Timer.After(0.5, function() ns._initComplete = true; ns.ScanAuras() end)
        end)
        print("|cff00b0ffAishCore|r [Auras] v" .. ns.ADDON_VERSION .. " — |cffffcc00/aa|r ou |cffffcc00/aishaura|r")

    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
        ns._inCombat = InCombatLockdown(); ns._whitelistBuilt = false
        wipe(ns.cdmData.target); wipe(ns.cdmData.player)
        -- Changement de zone/spec = changement de contexte complet : les auras
        -- de l'ancien contexte n'existent plus (pas de continuité). On wipe aussi
        -- les caches par-instID qui pointent vers des auras mortes.
        if ns._refreshCounter then wipe(ns._refreshCounter) end
        -- Annule le wipe idle programmé (on vient de changer de zone, le contexte
        -- est déjà neuf, pas besoin de re-wipe dans 5 min).
        CancelIdleWipe()
        -- Réévalue la suspension des effets 3D (auto-disable en raid si option activée)
        if ns.RefreshEffectsSuspension then pcall(ns.RefreshEffectsSuspension) end
        -- Cleanup des sorts découverts : retire uniquement les items War Gear
        pcall(function()
            local spells = ns.GetSpecSpells()
            if spells then
                local toRemove = {}
                local wgIDs, wgNames = {}, {}
                if ns.Providers and ns.Providers.GetAllSlots then
                    for _,slot in ipairs(ns.Providers:GetAllSlots()) do
                        if slot.spellID then wgIDs[slot.spellID] = true end
                        if slot.itemID then wgIDs[slot.itemID] = true end
                        local sn = ns.Providers.GetSlotName and ns.Providers:GetSlotName(slot)
                        if sn then wgNames[sn:lower()] = true end
                    end
                end
                for sid, si in pairs(spells) do
                    local remove = false
                    if si.source == "equipment" then remove = true end
                    if wgIDs[sid] then remove = true end
                    if si.name and wgNames[si.name:lower()] then remove = true end
                    if remove then toRemove[#toRemove + 1] = sid end
                end
                for _, sid in ipairs(toRemove) do spells[sid] = nil end
            end
        end)
        -- Pré-sync de tous les effets 3D (garantit que les champs flat sont prêts avant combat)
        ns.Try("PreSync3D", function()
            local spells = ns.GetSpecSpells()
            if spells and ns.SpellFX then
                for sid, si in pairs(spells) do
                    if si.fx3d then
                        pcall(function() ns.SpellFX:SyncToSpell(sid) end)
                    end
                end
            end
        end)
        if ns.AutoConfigCenterArc then pcall(ns.AutoConfigCenterArc) end
        ns.BuildWhitelist(); ns.ScanAuras(); ns.UpdateAllFades()
        for _, d in ipairs({0.5, 1.5, 3.0}) do
            C_Timer.After(d, function()
                ns.Try("StartupRetry@"..d.."s", function()
                    ns.BuildWhitelist()
                    ns.Try("InitCDMHooks@retry"..d.."s", ns.InitCDMHooks)
                    ns.Try("ScanCDMViewers@retry"..d.."s", ns.ScanCDMViewers)
                    ns.ScanAuras()
                end)
            end)
        end
        -- Ré-exécute le cleanup WG après init de Providers (délai 3s)
        C_Timer.After(3.5, function()
            pcall(function()
                local spells = ns.GetSpecSpells()
                if spells and ns.Providers and ns.Providers.GetAllSlots then
                    local wgIDs, wgNames = {}, {}
                    for _,slot in ipairs(ns.Providers:GetAllSlots()) do
                        if slot.spellID then wgIDs[slot.spellID] = true end
                        if slot.itemID then wgIDs[slot.itemID] = true end
                        local sn = ns.Providers.GetSlotName and ns.Providers:GetSlotName(slot)
                        if sn then wgNames[sn:lower()] = true end
                    end
                    local toRemove = {}
                    for sid, si in pairs(spells) do
                        if wgIDs[sid] or (si.name and wgNames[si.name:lower()]) then
                            toRemove[#toRemove + 1] = sid
                        end
                    end
                    for _, sid in ipairs(toRemove) do spells[sid] = nil end
                    if #toRemove > 0 then ns.BuildWhitelist(); ns.ScanAuras() end
                end
            end)
        end)

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- WIPE IMMÉDIAT de cdmData.target : les données de l'ancienne cible peuvent
        -- contenir des mappings auraInstanceID→spellID qui correspondent à une autre
        -- cible. Si la nouvelle cible a des auras avec des instID qui étaient dans le
        -- cache, on utiliserait les mauvais spellIDs. Wipe propre pour partir sain.
        wipe(ns.cdmData.target)

        -- Wipe le refreshCounter : les instID de l'ancienne cible sont obsolètes.
        -- Si la nouvelle cible a un instID recyclé, on veut repartir du compteur 0
        -- pour que GetAuraKey génère une nouvelle clé et que SetTimerDuration soit
        -- relancé avec le durObj de la nouvelle cible.
        wipe(ns._refreshCounter)

        -- Timestamp du tab target. Sert à distinguer les UNIT_AURA.updated dans
        -- les 300ms qui suivent (= confirmations Blizzard de l'état initial, PAS
        -- de vrais refreshs) des updated ultérieurs (= vrais recasts).
        -- Sans ce filtre, le refreshCounter passait de 0 à 1 juste après le tab,
        -- l'auraKey changeait, SetTimerDuration était relancé avec interpolation
        -- Smooth → délai visuel perçu de 200ms après le tab.
        ns._lastTargetChangeTime = GetTime()

        -- STRATEGIE ANTI-CLIGNOTEMENT :
        -- Le scan classique fait Renders:Update({}) quand aucune aura n'est trouvée,
        -- ce qui CACHE toutes les barres immédiatement. Si 15ms plus tard le CDM fire
        -- avec les auras de la nouvelle cible, les barres réapparaissent → flash
        -- visuel sur 1 frame.
        --
        -- PEEK : on lit GetAuraSlots SANS faire de scan complet. Si on voit déjà des
        -- auras Blizzard a déjà peuplé → on scan normal. Si vide → on ne touche PAS
        -- aux renders et on attend le hook CDM SetAuraInstanceInfo qui trigger un
        -- scan dès que Blizzard pousse les données.
        --
        -- Résultat : pas de "flash" entre les DOTs de l'ancienne cible et ceux de
        -- la nouvelle. Soit update immédiat (si auras déjà visibles), soit update
        -- après 10-20ms (via CDM) sans passage intermédiaire par un état vide.
        _targetRetryGen = _targetRetryGen + 1
        _CancelTargetRetries()
        local gen = _targetRetryGen

        -- Peek rapide : est-ce que Blizzard a déjà peuplé des auras HARMFUL sur target ?
        local hasAurasAlready = false
        if C_UnitAuras and C_UnitAuras.GetAuraSlots and UnitExists("target") then
            pcall(function()
                local slots = { C_UnitAuras.GetAuraSlots("target", "HARMFUL") }
                if #slots > 1 then hasAurasAlready = true end
            end)
        end

        if hasAurasAlready then
            -- Blizzard est déjà prêt : scan complet synchrone, barres update direct
            ns.ScanAuras()
            ns._awaitingTargetFullUpdate = false
        else
            -- Blizzard pas encore prêt : on NE touche PAS aux renders (les anciennes
            -- barres restent visibles 1 frame max). On flag et on programme retries.
            ns._awaitingTargetFullUpdate = true
            -- Retry 1 à 15ms : si UNIT_AURA/CDM n'a toujours rien fait d'ici là,
            -- on force un scan (qui cachera les barres orphelines si vraiment vide).
            for i, d in ipairs({0.015, 0.04, 0.08, 0.15, 0.25, 0.4}) do
                _targetRetryTimers[i] = C_Timer.NewTimer(d, function() _TargetRetryScan(gen) end)
            end
        end

    elseif event == "UNIT_AURA" then
        -- arg2 = updateInfo (structure UnitAuraUpdateInfo depuis Dragonflight 10.0).
        -- Contient : isFullUpdate, addedAuras[], updatedAuraInstanceIDs[], removedAuraInstanceIDs[].
        -- On utilise AuraUtil.ShouldSkipAuraUpdate pour early-exit quand AUCUNE des auras
        -- touchées n'est dans notre whitelist. Gain massif en raid avec beaucoup d'auras
        -- système (sceaux de raid, bénédictions, debuffs passifs) qui polluent la cible.
        local info = arg2
        local anyWL = ns.anyWhitelist

        -- Secret Values (patch 12.1+, 2026-08-11) : depuis ce patch, TOUT le
        -- payload UNIT_AURA (isFullUpdate inclus -- un simple booleen) devient
        -- secret des que des auras concernees sont secretes -- meme un `if
        -- info.isFullUpdate` plante desormais (crash reproduit en jeu le
        -- 2026-08-12, cf. Config/ResourceMap.lua qui avait le meme pattern).
        -- issecretvalue() est la seule facon sure de sonder ce champ AVANT de
        -- le tester. Si le payload est secret, on ne peut plus se fier a
        -- AUCUN de ses sous-champs (addedAuras/updatedAuraInstanceIDs/
        -- removedAuraInstanceIDs peuvent etre des "secret table" -- meme les
        -- iterer avec ipairs planterait). On saute alors directement le
        -- refresh counter + l'optimisation ShouldSkipAuraUpdate et on
        -- retombe sur le meme debounce que le chemin normal, juste sans
        -- pouvoir skip -- moins optimal, mais jamais un crash.
        if info and issecretvalue and issecretvalue(info.isFullUpdate) then
            if arg1 == "target" and ns._awaitingTargetFullUpdate then
                ns._awaitingTargetFullUpdate = false
                _CancelTargetRetries()
                pcall(ns.ScanAuras)
                return
            end
            if arg1 == "target" then
                if not ns._targetScanPending then
                    ns._targetScanPending = true
                    C_Timer.After(0.05, _TargetScanDebounced)
                end
            elseif arg1 == "player" and not ns._playerScanPending then
                ns._playerScanPending = true
                C_Timer.After(0.1, _PlayerScanDebounced)
            end
            return
        end

        -- REFRESH COUNTER : Blizzard fire UNIT_AURA avec updatedAuraInstanceIDs au recast
        -- d'un DOT. On incrémente un compteur par instID. GetAuraKey utilise ce compteur
        -- pour changer la clé d'aura → SetTimerDuration est relancé avec le durObj frais.
        -- A ce stade le payload est confirmé NON secret (guard ci-dessus, sorti sinon) --
        -- avant le patch 12.1 on pensait ce payload "100% non-secret" par nature, ce qui
        -- s'est révélé faux (isFullUpdate/les listes d'IDs peuvent être secrets ensemble).
        --
        -- EXCEPTION TAB TARGET : dans les 300ms suivant un PLAYER_TARGET_CHANGED, Blizzard
        -- fire des UNIT_AURA.updated pour CONFIRMER l'état initial des auras sur la nouvelle
        -- cible. Ce ne sont PAS des vrais recasts utilisateur. Si on les compte, le auraKey
        -- change après l'affichage initial → SetTimerDuration relancé avec interpolation
        -- Smooth → délai visuel parasite après le tab (c'est exactement le délai perçu).
        -- On skip l'incrément pour arg1 == "target" dans cette fenêtre.
        if info then
            -- TRACE : voir chaque aura qui arrive

            local now = GetTime()
            local isPostTargetChange = arg1 == "target" and ns._lastTargetChangeTime
                and (now - ns._lastTargetChangeTime) < 0.3
            if info.updatedAuraInstanceIDs and not isPostTargetChange then
                for _, instID in ipairs(info.updatedAuraInstanceIDs) do
                    ns._refreshCounter[instID] = (ns._refreshCounter[instID] or 0) + 1
                end
            end
            if info.removedAuraInstanceIDs then
                for _, instID in ipairs(info.removedAuraInstanceIDs) do
                    ns._refreshCounter[instID] = nil
                end
            end
            if info.isFullUpdate then
                wipe(ns._refreshCounter)
            end
        end

        -- Predicate pour ShouldSkipAuraUpdate : retourne true si l'aura EST pertinente
        -- (on veut NE PAS skip l'event). Blizzard inverse la convention : le helper
        -- ShouldSkipAuraUpdate retourne true si on peut skip (= aucune aura pertinente).
        local function isRelevant(aura)
            if not anyWL then return true end  -- pas de whitelist : on traite tout
            local sid = ns.SafeSpellID(aura)
            if not sid then return true end  -- illisible : on garde par sécurité
            return anyWL[sid] == true
        end

        -- Cas trivial : pas d'updateInfo (event leger ou client incompatible) → scan complet
        -- Cas isFullUpdate : Blizzard nous dit de tout rescanner
        -- Cas incrémental : on exploite ShouldSkipAuraUpdate
        local shouldSkip = false
        if info and not info.isFullUpdate then
            -- L'helper Blizzard vérifie addedAuras[] et updatedAuraInstanceIDs[]
            if AuraUtil and AuraUtil.ShouldSkipAuraUpdate then
                local ok, result = pcall(AuraUtil.ShouldSkipAuraUpdate, info, isRelevant)
                if ok then shouldSkip = result end
            end
            -- Ex-double-check "aura whitelistée retirée/refresh" via cdmU[instID] :
            -- supprimé. cdmData est désormais clé par spellID (pas par instID,
            -- cf. CDMHooks.lua, Secret Values 12.0+) donc ce lookup direct par
            -- instID n'a plus de sens, et le reconstruire nécessiterait de
            -- comparer des instID potentiellement secrets (== interdit). On
            -- fait désormais confiance à AuraUtil.ShouldSkipAuraUpdate +
            -- isRelevant (qui reçoit déjà les auras fraîches, y compris pour
            -- addedAuras/updatedAuraInstanceIDs) comme seul filtre.
        end

        if shouldSkip then return end  -- Zero-cost exit : aucune aura whitelistée touchée

        -- FAST PATH POST-TAB-TARGET : si on attend l'update initial de la nouvelle
        -- cible (ns._awaitingTargetFullUpdate set par PLAYER_TARGET_CHANGED quand
        -- le scan immédiat est revenu vide), alors cet UNIT_AURA target est le
        -- SIGNAL ATTENDU : Blizzard vient de peupler C_UnitAuras. On scan IMMÉDIATEMENT
        -- sans passer par le debounce 50ms → latence tab target divisée par ~3.
        -- On accepte aussi les events incrémentaux (sans isFullUpdate) car certains
        -- modes Blizzard fire direct les addedAuras sans isFullUpdate au target change.
        if arg1 == "target" and ns._awaitingTargetFullUpdate then
            ns._awaitingTargetFullUpdate = false
            _CancelTargetRetries()  -- le scan qui vient va trouver, pas besoin des retries
            pcall(ns.ScanAuras)
            return
        end

        -- Debounce (idem avant) : sous AoE ou multi-dot, UNIT_AURA arrive en rafale
        -- (5-10 events en quelques ms). On throttle à 50ms pour la target aussi.
        if arg1 == "target" then
            if not ns._targetScanPending then
                ns._targetScanPending = true
                C_Timer.After(0.05, _TargetScanDebounced)
            end
        elseif arg1 == "player" and not ns._playerScanPending then
            ns._playerScanPending = true
            C_Timer.After(0.1, _PlayerScanDebounced)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        ns._inCombat = false
        -- Rattrape un InitAllRenders() saute pendant le combat (ex. reload
        -- pendant un pull) : cf. le guard InCombatLockdown dans
        -- ns.InitAllRenders (Init.lua), qui pose ce flag au lieu de laisser
        -- chaque render planter sur un SetPropagateMouseClicks protege.
        if ns._pendingRenderInit then
            ns._pendingRenderInit = false
            pcall(ns.InitAllRenders)
        end
        ns.BuildWhitelist(); ns.ScanAuras(); ns.UpdateAllFades()
        -- Fin de combat : programme un wipe idle 5 min plus tard pour nettoyer
        -- les caches si l'user reste inactif. Annulé si re-combat avant.
        ScheduleIdleWipe()
        -- Rattrape les relais de stacks (AuraTextRelay.lua) qui n'ont pas pu
        -- se créer pendant le combat (BuildWhitelist ci-dessus les retente déjà,
        -- mais un flush explicite couvre aussi les cas où BuildWhitelist n'a
        -- rien de nouveau à traiter).
        if ns.FlushPendingAuraTextOverlays then ns.FlushPendingAuraTextOverlays() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        ns._inCombat = true; ns.UpdateAllFades()
        -- Entrée combat : annule le wipe idle programmé (on va avoir besoin des caches).
        CancelIdleWipe()
        for _, d in ipairs({0.3, 0.8}) do C_Timer.After(d, _ScanAurasSafe) end

    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        ns.BuildWhitelist()
        for _, d in ipairs({0.1, 0.3, 0.8}) do C_Timer.After(d, _ScanAurasSafe) end

    elseif (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 == "player" then
        wipe(ns.cdmData.target)
        C_Timer.After(0.3, _InitCombatScans)

    elseif event == "SPELL_UPDATE_CHARGES" then
        -- Les charges de sort changent (ex: Ice Barrier, Blink, Shimmer)
        -- Throttle à 100ms pour éviter le spam si plusieurs events consécutifs
        if not ns._chargesScanPending then
            ns._chargesScanPending = true
            C_Timer.After(0.1, _ChargesScanDebounced)
        end
    end
end)

-- Enregistrement direct des events (pas de pcall : RegisterEvent est une API publique,
-- et un appel via pcall peut déclencher ADDON_ACTION_FORBIDDEN sur certaines versions)
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ef:RegisterEvent("PLAYER_TARGET_CHANGED")
ef:RegisterEvent("UNIT_AURA")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")
ef:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
ef:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ef:RegisterEvent("UNIT_ENTERED_VEHICLE")
ef:RegisterEvent("UNIT_EXITED_VEHICLE")
ef:RegisterEvent("SPELL_UPDATE_CHARGES")
-- Note : COMBAT_LOG_EVENT_UNFILTERED retiré car il déclenche ADDON_ACTION_FORBIDDEN
-- sur Midnight 12.0. UNIT_AURA + les rescans différés couvrent déjà le cas du
-- rafraîchissement après SPELL_AURA_REMOVED.

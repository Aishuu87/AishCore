-- AishUIAura/Core/LearnedDurations.lua
-- ============================================================
-- MODULE : Apprentissage des durees d'auras (combat-safe Midnight)
-- ============================================================
-- Pattern "durees apprises en temps reel" decouvert par Yoah le 1 mai 2026.
-- Voir doc complete dans le projet (LearnedDurations_Pattern.md).
--
-- Probleme resolu :
--   En combat sur sorts CDM Midnight 12.0, toutes les valeurs liees au
--   timer d'aura sont secret values. SetViewInsets refuse les secret
--   values en argument. Donc impossible de driver une animation 3D
--   synchronisee au vrai timer d'aura.
--
-- Solution :
--   On ne LIT pas le timer Blizzard (impossible, secret). On l'OBSERVE
--   en boite noire via GetTime() qui est clean :
--     T0    = GetTime() a l'apparition de l'aura
--     T_end = GetTime() a sa disparition
--     duree = T_end - T0  -> clean, stockable, reutilisable
--
--   Au cycle suivant, on connait la duree -> pct clean utilisable
--   pour SetViewInsets en combat sans crash.
--
-- API publique :
--   ns.LearnedDurations.StartLearning(instID, spellID, name)
--   ns.LearnedDurations.ResetLearningTimer(instID, spellID, name)  -- refresh
--   ns.LearnedDurations.StopLearning(instID)
--   ns.LearnedDurations.GetCleanPercent(instID) -> number|nil
--   ns.LearnedDurations.HasDuration(spellID) -> bool
--   ns.LearnedDurations.GetDuration(spellID) -> number|nil
--   ns.LearnedDurations.OnAuraAppeared(instID, spellID, name, isRefresh)
--   ns.LearnedDurations.OnAuraDisappeared(instID)
--
-- Limites :
--   - 1er cast d'un sort jamais vu : pas de duree -> mode fallback
--   - Refresh : timer reset mais duree apprise conservee (pas de Pandemic
--     pollution)
--   - Aura dispel/cleanse : duree filtrée si hors plage [3, 120]s
-- ============================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.LearnedDurations = ns.LearnedDurations or {}
local LD = ns.LearnedDurations

local HAS_ISSECRET = (type(issecretvalue) == "function")

-- DB : storage par character (declare dans le .toc en SavedVariablesPerCharacter)
-- Initialisee dans le hook PLAYER_LOGIN d'Init.lua (ou au 1er acces ici)
local function GetDB()
    AishUILearnDB = AishUILearnDB or { learnedDurations = {}, verbose = false }
    AishUILearnDB.learnedDurations = AishUILearnDB.learnedDurations or {}
    return AishUILearnDB
end

-- ============================================================
-- CONFIGURATION
-- ============================================================
local LEARN_MIN_DURATION = 3      -- duree minimale acceptee (filtre dispel)
local LEARN_MAX_DURATION = 120    -- duree maximale acceptee (filtre buffs longs)

-- ============================================================
-- ETAT INTERNE
-- ============================================================
local _learning = {}  -- [instID] = { startTime, spellID, name }

local function vlog(...)
    local DB = GetDB()
    if not DB.verbose then return end
    print("|cffaaaaff[LearnedDur]|r", ...)
end

-- ============================================================
-- API PUBLIQUE
-- ============================================================

-- Demarre l'apprentissage pour une aura.
-- Appele a l'apparition de l'aura (1er cast).
function LD.StartLearning(instID, spellID, name)
    if not instID or not spellID then return end
    if _learning[instID] then return end  -- deja en cours
    -- Defense en profondeur : si name est secret value, on retombe sur le spellID
    -- (le caller devrait deja filtrer mais on protege)
    local cleanName = name
    if cleanName and HAS_ISSECRET and issecretvalue(cleanName) then
        cleanName = nil
    end
    _learning[instID] = {
        startTime = GetTime(),
        spellID = spellID,
        name = cleanName or tostring(spellID),
    }
    vlog(string.format("Start learning instID=%s sid=%s (%s)",
        tostring(instID), tostring(spellID), tostring(cleanName)))
end

-- Reset le timer local pour une aura existante.
-- Appele sur un refresh : on garde la duree apprise du cycle precedent
-- (sinon les refreshs Pandemic ecraseraient la duree nominale).
function LD.ResetLearningTimer(instID, spellID, name)
    if not instID or not spellID then return end
    if _learning[instID] then
        _learning[instID].startTime = GetTime()
        _learning[instID].spellID = spellID
        _learning[instID].name = name or _learning[instID].name
        vlog(string.format("Reset timer instID=%s sid=%s",
            tostring(instID), tostring(spellID)))
    else
        -- Pas en cours d'apprentissage : on demarre
        LD.StartLearning(instID, spellID, name)
    end
end

-- Finalise l'apprentissage et stocke la duree si valide.
-- Appele a la disparition de l'aura.
function LD.StopLearning(instID)
    if not instID then return end
    local data = _learning[instID]
    if not data then return end

    local actualDuration = GetTime() - data.startTime
    if actualDuration >= LEARN_MIN_DURATION and actualDuration <= LEARN_MAX_DURATION then
        local DB = GetDB()
        local previous = DB.learnedDurations[data.spellID]
        DB.learnedDurations[data.spellID] = {
            duration = actualDuration,
            name = data.name,
        }
        vlog(string.format("Learned sid=%s (%s) : %.2fs (was %s)",
            tostring(data.spellID), tostring(data.name), actualDuration,
            previous and string.format("%.2fs", previous.duration) or "nil"))
    else
        vlog(string.format("Skip learning sid=%s : %.2fs (out of range [%d-%d])",
            tostring(data.spellID), actualDuration,
            LEARN_MIN_DURATION, LEARN_MAX_DURATION))
    end
    _learning[instID] = nil
end

-- Renvoie un pourcentage CLEAN (1.0 = aura full, 0.0 = aura expiree)
-- ou nil si la duree n'a pas encore ete apprise pour ce sort.
-- Cette valeur est utilisable directement pour driver SetViewInsets en combat.
function LD.GetCleanPercent(instID)
    if not instID then return nil end
    local data = _learning[instID]
    if not data then return nil end

    local DB = GetDB()
    local entry = DB.learnedDurations[data.spellID]
    if not entry or not entry.duration or entry.duration <= 0 then return nil end

    local elapsed = GetTime() - data.startTime
    local pct = 1 - (elapsed / entry.duration)
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    return pct
end

-- Verifie si on a une duree apprise pour un spellID.
function LD.HasDuration(spellID)
    if not spellID then return false end
    local DB = GetDB()
    local entry = DB.learnedDurations[spellID]
    return entry ~= nil and entry.duration ~= nil and entry.duration > 0
end

-- Recupere la duree apprise pour un spellID, ou nil.
function LD.GetDuration(spellID)
    if not spellID then return nil end
    local DB = GetDB()
    local entry = DB.learnedDurations[spellID]
    return entry and entry.duration or nil
end

-- ============================================================
-- HELPERS DE HAUT NIVEAU pour les renders
-- ============================================================
-- Ces helpers sont appeles par les renders (Debuffs, Cooldowns...) qui
-- savent deja gerer le cycle de vie des auras.

-- Appele quand une aura apparait OU est refresh.
-- isRefresh = true si l'auraInstanceID etait deja vue au scan precedent.
-- IMPORTANT : isRefresh=true ne signifie PAS qu'il y a eu un vrai refresh.
-- Cela peut juste signifier que l'aura est toujours active (scan continu).
-- Pour eviter les Reset spurious a chaque scan :
--   - Si pas en cours d'apprentissage : StartLearning (1er scan apres apparition)
--   - Si deja en cours d'apprentissage : ne RIEN faire (le timer continue
--     naturellement). Le seul vrai cas de Reset serait detectable via
--     C_UnitAuras.UNIT_AURA updatedAuraInstanceIDs, mais c'est gere par
--     l'event handler externe.
function LD.OnAuraAppeared(instID, spellID, name, isRefresh)
    if not instID or not spellID then return end
    -- Si pas encore en apprentissage : start
    if not _learning[instID] then
        LD.StartLearning(instID, spellID, name)
    end
    -- Si deja en apprentissage : ne rien faire (l'aura est toujours active,
    -- le scan continu n'est PAS un refresh).
    -- Pour declencher un vrai Reset (refresh detecte par UNIT_AURA), appeler
    -- ResetLearningTimer directement.
end

-- Appele quand une aura disparait (defer hide ou unit change).
function LD.OnAuraDisappeared(instID)
    LD.StopLearning(instID)
end

-- Cleanup global (target change, full reset, etc.)
function LD.WipeLearning()
    wipe(_learning)
end

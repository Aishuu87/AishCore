-- AishUIAura/Core/LearnedDurations.lua
-- Apprentissage des durees d'auras (combat-safe Midnight) : les timers CDM sont des secret values
-- illisibles en combat, donc on observe T0/T_end via GetTime() pour deduire la duree et la reutiliser.
-- Limites : pas de duree au 1er cast (fallback), refresh garde la duree apprise, duree filtree hors [3,120]s.

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.LearnedDurations = ns.LearnedDurations or {}
local LD = ns.LearnedDurations

local HAS_ISSECRET = (type(issecretvalue) == "function")

-- DB par personnage, initialisee au login (Init.lua) ou au 1er acces ici
local function GetDB()
    AishUILearnDB = AishUILearnDB or { learnedDurations = {}, verbose = false }
    AishUILearnDB.learnedDurations = AishUILearnDB.learnedDurations or {}
    return AishUILearnDB
end

local LEARN_MIN_DURATION = 3      -- duree minimale acceptee (filtre dispel)
local LEARN_MAX_DURATION = 120    -- duree maximale acceptee (filtre buffs longs)

local _learning = {}  -- [instID] = { startTime, spellID, name }

local function vlog(...)
    local DB = GetDB()
    if not DB.verbose then return end
    print("|cffaaaaff[LearnedDur]|r", ...)
end

-- Demarre l'apprentissage pour une aura (appele a l'apparition, 1er cast).
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

-- Reset le timer sur un refresh, en gardant la duree apprise (evite l'ecrasement par le Pandemic).
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

-- Finalise l'apprentissage et stocke la duree si valide (appele a la disparition de l'aura).
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

-- Renvoie un pourcentage clean (1.0 = full, 0.0 = expiree) utilisable pour SetViewInsets, ou nil si duree inconnue.
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

-- Helpers de haut niveau pour les renders (Debuffs, Cooldowns...).

-- Appele quand une aura apparait ou est vue au scan (isRefresh ne veut pas dire vrai refresh Pandemic ;
-- pour ca, appeler ResetLearningTimer directement depuis l'event handler UNIT_AURA).
function LD.OnAuraAppeared(instID, spellID, name, isRefresh)
    if not instID or not spellID then return end
    if not _learning[instID] then
        LD.StartLearning(instID, spellID, name)
    end
end

-- Appele quand une aura disparait (defer hide ou unit change).
function LD.OnAuraDisappeared(instID)
    LD.StopLearning(instID)
end

-- Cleanup global (target change, full reset, etc.)
function LD.WipeLearning()
    wipe(_learning)
end

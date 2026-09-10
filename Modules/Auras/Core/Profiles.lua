-- AishUIAura/Core/Profiles.lua
-- Gestion des profils : CRUD multi-profils, export/import via LibSerialize + LibDeflate.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.Profiles = {}
local Prof = ns.Profiles

local EXPORT_HEADER = "AISHA1"  -- header for validation on import

local function GetLibs()
    local LS, LD
    pcall(function()
        LS = LibStub and LibStub("LibSerialize", true)
        LD = LibStub and LibStub("LibDeflate", true)
    end)
    return LS, LD
end

function Prof:HasLibs()
    local LS, LD = GetLibs()
    return (LS ~= nil) and (LD ~= nil)
end

function Prof:InitDB()
    if not AishUIAuraDB then AishUIAuraDB = {} end
    local raw = AishUIAuraDB
    if not raw.profiles then raw.profiles = {} end
    if not raw.activeProfile then raw.activeProfile = "Default" end
    if not raw.profiles[raw.activeProfile] then raw.profiles[raw.activeProfile] = ns.DeepCopy(ns.Defaults) end
    local profile = raw.profiles[raw.activeProfile]
    ns.MergeDefaults(profile, ns.Defaults)
    if not raw.discoveredSpells then raw.discoveredSpells = {} end
    profile.discoveredSpells = raw.discoveredSpells
    return profile
end

function Prof:GetList()
    local db = AishUIAuraDB; if not db or not db.profiles then return {"Default"} end
    local list = {}; for n in pairs(db.profiles) do table.insert(list, n) end
    table.sort(list); return list
end

function Prof:GetActive() return AishUIAuraDB and AishUIAuraDB.activeProfile or "Default" end

function Prof:SetActive(name)
    local db = AishUIAuraDB; if not db or not db.profiles or not db.profiles[name] then return false end
    db.activeProfile = name; local p = db.profiles[name]
    ns.MergeDefaults(p, ns.Defaults); p.discoveredSpells = db.discoveredSpells; ns.db = p
    pcall(function() ns.BuildWhitelist(); ns.RebuildDisplay(); ns.UpdateAllFades() end)
    return true
end

function Prof:Create(name)
    local db = AishUIAuraDB; if not db then return false end
    if not db.profiles then db.profiles = {} end
    if db.profiles[name] then return false end
    db.profiles[name] = ns.DeepCopy(ns.Defaults); return true
end

function Prof:Delete(name)
    local db = AishUIAuraDB; if not db or not db.profiles or name == "Default" then return false end
    db.profiles[name] = nil; if db.activeProfile == name then Prof:SetActive("Default") end; return true
end

-- Export : profil -> string (LibSerialize + LibDeflate + header)
function Prof:Export(name)
    local db = AishUIAuraDB; if not db or not db.profiles then return nil, "Pas de profils" end
    local pName = name or db.activeProfile
    local p = db.profiles[pName]; if not p then return nil, "Profil '"..tostring(pName).."' introuvable" end

    local LS, LD = GetLibs()
    if not LS or not LD then return nil, "LibSerialize ou LibDeflate manquant" end

    -- Build export payload
    local data = ns.DeepCopy(p)
    data.discoveredSpells = ns.DeepCopy(db.discoveredSpells)
    data._exportVersion = 1
    data._exportName = pName
    data._exportDate = date("%Y-%m-%d %H:%M")

    local encoded
    pcall(function()
        local serialized = LS:Serialize(data)
        local compressed = LD:CompressDeflate(serialized)
        encoded = EXPORT_HEADER .. LD:EncodeForPrint(compressed)
    end)
    if encoded then return encoded, nil
    else return nil, "Erreur serialisation" end
end

-- Import : string -> profil (valide le header + l'integrite des donnees)
function Prof:Import(encoded, targetName, overwrite)
    if not encoded or encoded == "" then return false, "String vide" end

    -- Strip whitespace
    encoded = encoded:match("^%s*(.-)%s*$") or encoded

    -- Validate header
    local header = encoded:sub(1, #EXPORT_HEADER)
    if header ~= EXPORT_HEADER then return false, "Format invalide (header manquant)" end
    local payload = encoded:sub(#EXPORT_HEADER + 1)

    local LS, LD = GetLibs()
    if not LS or not LD then return false, "LibSerialize ou LibDeflate manquant" end

    -- Decode
    local data, decErr
    pcall(function()
        local decoded = LD:DecodeForPrint(payload)
        if not decoded then decErr = "DecodeForPrint echoue"; return end
        local decompressed = LD:DecompressDeflate(decoded)
        if not decompressed then decErr = "DecompressDeflate echoue"; return end
        local success, result = LS:Deserialize(decompressed)
        if not success then decErr = "Deserialize echoue"; return end
        data = result
    end)
    if not data then return false, "Decodage echoue: "..(decErr or "donnees corrompues") end

    -- Validate data structure
    if type(data) ~= "table" then return false, "Donnees invalides (pas une table)" end

    local db = AishUIAuraDB; if not db then return false, "DB non initialisee" end
    if not db.profiles then db.profiles = {} end

    -- Determine target name
    local tgt = targetName
    if not tgt or tgt == "" then
        tgt = data._exportName or "Imported"
    end

    -- Overwrite check
    if db.profiles[tgt] and not overwrite then
        return false, "Le profil '"..tgt.."' existe deja"
    end

    -- Merge discovered spells (additive)
    if data.discoveredSpells then
        if not db.discoveredSpells then db.discoveredSpells = {} end
        for sk, sp in pairs(data.discoveredSpells) do
            if type(sp) == "table" then
                if not db.discoveredSpells[sk] then db.discoveredSpells[sk] = sp
                else for sid, info in pairs(sp) do if not db.discoveredSpells[sk][sid] then db.discoveredSpells[sk][sid] = info end end end
            end
        end
        -- Normalise les cles spec pre-migration vers le format actuel (cf. ns.MigrateSpecKeys, Init.lua)
        if ns.MigrateSpecKeys then pcall(ns.MigrateSpecKeys, db) end
    end

    -- Clean export metadata before saving
    data.discoveredSpells = nil
    data._exportVersion = nil
    data._exportName = nil
    data._exportDate = nil

    -- Save profile
    db.profiles[tgt] = data
    ns.MergeDefaults(data, ns.Defaults)
    return true, tgt
end

-- Auto-switch par specialisation
function Prof.ApplySpecProfile() pcall(function() ns.BuildWhitelist(); ns.ScanAuras() end) end

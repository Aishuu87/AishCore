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

-- Les profils Auras (reglages Auras, reglages par aura, Missing Buffs, useNativeCDM...) sont LIES au
-- profil AishCore actif (Config/Profiles.lua) : meme nom, bascule avec lui (liaison perso/spe comprise).
--
-- Separation compte / profil :
--   - COMPTE (AishUIAuraDB.discovery[specKey][spellID] = { name, source, linkedSpellIDs }) : les auras
--     decouvertes et leur classement buff/debuff/totem. Immuable d'un profil a l'autre : tout profil,
--     meme cree vide, embarque toutes les auras connues. Reclassements/suppressions manuels idem
--     (AishUIAuraDB.adminOverrides, cf. ns.GetAdminOverrides dans Init.lua).
--   - PROFIL (profiles[name].discoveredSpells[specKey][spellID]) : tout le reste (destinations, couleur,
--     glow, priorite, modeles...). Les consommateurs lisent toujours ns.db.discoveredSpells : le
--     registre compte y est reverse (PullDiscovery) a chaque activation/creation de profil, et le profil
--     actif alimente le registre (PushDiscovery) avant chaque bascule et a la deconnexion.
local function LinkedName()
    return _addon._activeProfileName or "Default"
end

-- Profil -> registre compte. keepExisting : n'ajoute que les auras inconnues sans toucher au
-- classement deja enregistre (import d'un profil venu d'ailleurs).
local function PushDiscovery(raw, profile, keepExisting)
    local lists = type(profile) == "table" and profile.discoveredSpells
    if type(lists) ~= "table" then return end
    raw.discovery = raw.discovery or {}
    for specKey, spells in pairs(lists) do
        if type(spells) == "table" then
            local reg = raw.discovery[specKey]
            for sid, info in pairs(spells) do
                -- "equipment" : entrees War Gear transitoires (Effects.lua), purgees a chaque login
                if type(info) == "table" and info.source and info.source ~= "equipment" then
                    if not reg then reg = {}; raw.discovery[specKey] = reg end
                    local d = reg[sid]
                    local isNew = (d == nil)
                    if isNew then d = {}; reg[sid] = d end
                    if isNew or not keepExisting then
                        d.source = info.source
                        d.name = info.name
                        if type(info.linkedSpellIDs) == "table" then d.linkedSpellIDs = ns.DeepCopy(info.linkedSpellIDs) end
                    end
                end
            end
        end
    end
end

-- Registre compte -> profil : cree les auras manquantes (reglages par defaut), impose le classement et
-- retire celles oubliees du registre (purge War Gear, "Vider sorts decouverts"). Sans risque de perte :
-- le profil actif est toujours pousse (PushActive) avant qu'un autre profil soit tire.
local TOTEM_CLEARED_DESTINATIONS = { "iconlist", "circlebars", "freebars", "icons" }
local function PullDiscovery(raw, profile)
    if type(profile.discoveredSpells) ~= "table" then profile.discoveredSpells = {} end
    if type(raw.discovery) ~= "table" then return end
    local lists = profile.discoveredSpells
    for specKey, spells in pairs(lists) do
        if type(spells) == "table" then
            local reg = raw.discovery[specKey]
            for sid, info in pairs(spells) do
                if type(info) == "table" and info.source and info.source ~= "equipment"
                   and not (reg and reg[sid]) then
                    spells[sid] = nil
                end
            end
        end
    end
    for specKey, reg in pairs(raw.discovery) do
        if type(reg) == "table" then
            local spells = lists[specKey]
            if type(spells) ~= "table" then spells = {}; lists[specKey] = spells end
            for sid, d in pairs(reg) do
                local info = spells[sid]
                if type(info) ~= "table" then
                    info = ns.DeepCopy(ns.SpellDefaults)
                    info.priority = sid
                    local bc = ns.barColor or { 1, 1, 1 }
                    info.color = { bc[1], bc[2], bc[3] }
                    info._colorDefault = true -- recoloree par ns.RollDefaultSpecColors, comme une vraie decouverte
                    spells[sid] = info
                elseif d.source == "totem" and info.source ~= "totem" and type(info.destinations) == "table" then
                    -- Meme nettoyage que Totems.lua a la reclassification (sinon barres fantomes)
                    for _, k in ipairs(TOTEM_CLEARED_DESTINATIONS) do info.destinations[k] = false end
                end
                info.source = d.source or info.source
                if d.name then info.name = d.name end
                if type(d.linkedSpellIDs) == "table" then info.linkedSpellIDs = ns.DeepCopy(d.linkedSpellIDs) end
            end
        end
    end
end

-- Ne pousse que si ns.db est bien le profil actif (pas pendant l'init, avant que ns.db soit pose)
local function PushActive(raw)
    local p = raw and raw.profiles and raw.profiles[raw.activeProfile]
    if p and p == ns.db then PushDiscovery(raw, p) end
end

local function EnsureProfile(raw, name)
    raw.profiles = raw.profiles or {}
    local p = raw.profiles[name]
    -- Profil neuf : on part du template de reference (Core/ProfileTemplate.lua), comme le
    -- fait Config/Profiles.lua cote AishCore. Le MergeDefaults ci-dessous comble ensuite
    -- toute cle absente du template.
    if type(p) ~= "table" then p = ns.DeepCopy(ns.ProfileTemplate or ns.Defaults); raw.profiles[name] = p end
    ns.MergeDefaults(p, ns.Defaults)
    PullDiscovery(raw, p)
    return p
end

-- Migration one-shot vers le registre compte : union des listes de tous les profils (le profil actif
-- en dernier, son classement l'emporte), idem pour les surcharges admin, retirees des profils.
local function MigrateToDiscoveryRegistry(raw, activeName)
    raw.discovery = raw.discovery or {}
    raw.adminOverrides = raw.adminOverrides or {}
    local ordered = {}
    for name, prof in pairs(raw.profiles or {}) do
        if type(prof) == "table" and name ~= activeName then ordered[#ordered + 1] = prof end
    end
    local active = raw.profiles and raw.profiles[activeName]
    if type(active) == "table" then ordered[#ordered + 1] = active end
    for _, prof in ipairs(ordered) do
        PushDiscovery(raw, prof)
        if type(prof.adminOverrides) == "table" then
            for sid, o in pairs(prof.adminOverrides) do
                if type(o) == "table" then
                    local dst = raw.adminOverrides[sid] or {}
                    if o.source ~= nil then dst.source = o.source end
                    if o.deleted ~= nil then dst.deleted = o.deleted end
                    raw.adminOverrides[sid] = dst
                end
            end
        end
        prof.adminOverrides = nil
    end
end

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function() pcall(PushActive, AishUIAuraDB) end)

-- Migration one-shot vers les profils lies : chaque profil Auras existant recoit sa propre copie de
-- l'ancienne liste partagee, et chaque profil AishCore sans equivalent Auras herite d'une copie du
-- profil Auras jusqu'ici actif -- personne ne perd ses reglages actuels au passage.
local function MigrateToLinkedProfiles(raw)
    raw.profiles = raw.profiles or {}
    local shared = type(raw.discoveredSpells) == "table" and raw.discoveredSpells or {}
    for _, prof in pairs(raw.profiles) do
        if type(prof) == "table" then prof.discoveredSpells = ns.DeepCopy(shared) end
    end
    local source = raw.profiles[raw.activeProfile or "Default"] or raw.profiles["Default"]
    local coreProfiles = AishaddonDB and AishaddonDB._profiles
    if type(source) == "table" and type(coreProfiles) == "table" then
        for name in pairs(coreProfiles) do
            if not raw.profiles[name] then raw.profiles[name] = ns.DeepCopy(source) end
        end
    end
    raw.discoveredSpells = nil
end

function Prof:InitDB()
    if not AishUIAuraDB then AishUIAuraDB = {} end
    local raw = AishUIAuraDB
    if not raw._profilesLinkedV1 then
        MigrateToLinkedProfiles(raw)
        raw._profilesLinkedV1 = true
    end
    raw.discoveredSpells = nil -- plus jamais lue (cf. MigrateToLinkedProfiles)
    if not raw._discoveryRegistryV1 then
        MigrateToDiscoveryRegistry(raw, LinkedName())
        raw._discoveryRegistryV1 = true
    end
    raw.activeProfile = LinkedName()
    -- Polices pointant vers une media pack desinstallee : SetFont() leverait une erreur
    -- et couperait la creation du frame en plein milieu. Rabat sur la police du jeu.
    if ns.SanitizeFontPaths and type(raw.profiles) == "table" then
        for _, prof in pairs(raw.profiles) do ns.SanitizeFontPaths(prof) end
    end
    return EnsureProfile(raw, raw.activeProfile)
end

function Prof:GetList()
    local db = AishUIAuraDB; if not db or not db.profiles then return {"Default"} end
    local list = {}; for n in pairs(db.profiles) do table.insert(list, n) end
    table.sort(list); return list
end

function Prof:GetActive() return AishUIAuraDB and AishUIAuraDB.activeProfile or "Default" end

-- Appelee par Config/Profiles.lua (P.SetActive/Rename/CopyFrom/Reset) : cree le profil a la volee
-- s'il n'existe pas encore (profil AishCore cree sans copie = reglages Auras par defaut).
function Prof:SetActive(name)
    local db = AishUIAuraDB; if not db or not name then return false end
    PushActive(db)
    db.activeProfile = name
    ns.db = EnsureProfile(db, name)
    ns._whitelistBuilt = false
    -- Les Init() des renders ne nettoient leur ancien conteneur que s'ils sont actives dans le NOUVEAU
    -- profil : un render desactive (ou useNativeCDM / enabled=false) gardait l'affichage de l'ancien.
    for _, rf in pairs(ns.renderFrames or {}) do
        if rf and rf.container then
            if rf.rows then for _, r in ipairs(rf.rows) do pcall(r.Hide, r) end end
            pcall(rf.container.Hide, rf.container)
        end
    end
    if ns.InvalidateSpellNameCache then ns.InvalidateSpellNameCache() end
    pcall(function() ns.BuildWhitelist(); ns.RebuildDisplay(); ns.UpdateAllFades() end)
    pcall(ns.RefreshCDMMask)
    if ns.MissingBuffs and ns.MissingBuffs.OnProfileChanged then pcall(ns.MissingBuffs.OnProfileChanged) end
    return true
end

function Prof:Create(name)
    local db = AishUIAuraDB; if not db then return false end
    if not db.profiles then db.profiles = {} end
    if db.profiles[name] then return false end
    PushActive(db)
    EnsureProfile(db, name); return true
end

-- Profil actif (lie a AishCore) : jamais supprime d'ici, il faut passer par les profils AishCore.
function Prof:Delete(name)
    local db = AishUIAuraDB; if not db or not db.profiles or name == "Default" then return false end
    if name == db.activeProfile then return false end
    db.profiles[name] = nil; return true
end

-- Miroirs des operations de Config/Profiles.lua
function Prof:Copy(srcName, dstName)
    local db = AishUIAuraDB; if not db or not db.profiles then return false end
    local src = db.profiles[srcName]; if type(src) ~= "table" then return false end
    PushActive(db)
    db.profiles[dstName] = ns.DeepCopy(src)
    EnsureProfile(db, dstName); return true
end

function Prof:Rename(oldName, newName)
    local db = AishUIAuraDB; if not db or not db.profiles then return false end
    -- newName n'existe pas cote AishCore (verifie par P.Rename) : un profil Auras orphelin du meme nom est ecrase
    if db.profiles[oldName] then
        db.profiles[newName] = db.profiles[oldName]
        db.profiles[oldName] = nil
    end
    if db.activeProfile == oldName then db.activeProfile = newName end
    return true
end

function Prof:Reset(name)
    local db = AishUIAuraDB; if not db then return false end
    db.profiles = db.profiles or {}
    PushActive(db)
    db.profiles[name] = nil
    EnsureProfile(db, name); return true
end

-- Purge War Gear (Events.lua) : retire aussi du registre compte, sinon PullDiscovery les recreerait
function Prof:ForgetDiscovered(specKey, spellIDs)
    local reg = AishUIAuraDB and AishUIAuraDB.discovery and specKey and AishUIAuraDB.discovery[specKey]
    if not reg then return end
    for _, sid in ipairs(spellIDs) do reg[sid] = nil end
end

-- Export/import de profil AishCore : donnees Auras embarquees dans la meme chaine
function Prof:GetProfileData(name)
    local db = AishUIAuraDB
    if not (db and db.profiles and type(db.profiles[name]) == "table") then return nil end
    PushActive(db)
    return ns.DeepCopy(EnsureProfile(db, name))
end

function Prof:SetProfileData(name, data)
    local db = AishUIAuraDB; if not db or type(data) ~= "table" then return false end
    db.profiles = db.profiles or {}
    PushActive(db)
    db.profiles[name] = data
    -- Donnees importees d'un autre setup : cf. InitDB.
    if ns.SanitizeFontPaths then ns.SanitizeFontPaths(data) end
    if ns.MigrateSpecKeys then pcall(ns.MigrateSpecKeys, data) end
    PushDiscovery(db, data, true)
    EnsureProfile(db, name); return true
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

    -- Clean export metadata before saving
    if type(data.discoveredSpells) ~= "table" then data.discoveredSpells = {} end
    -- Normalise les cles spec pre-migration vers le format actuel (cf. ns.MigrateSpecKeys, Init.lua)
    if ns.MigrateSpecKeys then pcall(ns.MigrateSpecKeys, data) end
    PushActive(db)
    PushDiscovery(db, data, true)
    data._exportVersion = nil
    data._exportName = nil
    data._exportDate = nil

    -- Save profile
    db.profiles[tgt] = data
    if tgt == db.activeProfile then Prof:SetActive(tgt) else EnsureProfile(db, tgt) end
    return true, tgt
end

-- Auto-switch par specialisation
function Prof.ApplySpecProfile() pcall(function() ns.BuildWhitelist(); ns.ScanAuras() end) end

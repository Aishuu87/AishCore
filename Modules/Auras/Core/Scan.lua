-- AishUIAura/Core/Scan.lua
--
-- Scanner d'auras CDM-only (Midnight 12.0+).
--
-- ARCHITECTURE :
--   Source unique de verite = ns.cdmData[unit][instID] = { spellId, name }
--   maintenu par CDMHooks.lua via les hooks SetAuraInstanceInfo des 4 viewers
--   Blizzard (Essential, Utility, BuffIcon, BuffBar).
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
local GetAuraDataByAuraInstanceID  = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount

------------------------------------------------------------------------
-- ACCESSEURS COMBAT-SAFE (pattern "show but don't know")
------------------------------------------------------------------------

-- Lecture safe du spellID via CDM (priorite) ou fallback aura.spellId.
-- Combat-safe : on lit cdmData[unit][instID].spellId qui est TOUJOURS clean
-- (Blizzard nous le donne via le hook SetAuraInstanceInfo).
-- Fallback aura.spellId pour les rares cas hors-CDM (avec issecret check).
function ns.SafeSpellID(aura, unit)
    if not aura then return nil end
    local instID = aura.auraInstanceID
    -- Priorite : CDM (clean, event-driven)
    if instID and unit and ns.cdmData and ns.cdmData[unit] then
        local c = ns.cdmData[unit][instID]
        if c and c.spellId then return c.spellId end
    end
    -- Fallback : aura.spellId direct (avec protection issecret)
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
    -- Tentative 2 : API display count (souvent dispo meme quand applications est secret)
    if stacks == 0 and unit and instID and GetAuraApplicationDisplayCount then
        pcall(function()
            local c = GetAuraApplicationDisplayCount(unit, instID)
            if c ~= nil and not (HAS_ISSECRET and issecretvalue(c)) and c > 0 then
                stacks = c
            end
        end)
    end
    return stacks
end

------------------------------------------------------------------------
-- CRÉATION D'ENTRÉE
--
-- CDM-only : si instID n'est pas dans ns.cdmData[unit], on retourne nil.
-- Pour les durees, on stocke uniquement durObj (pattern "show but don't know").
-- L'animation lit le durObj elle-meme via Animation.lua (combat-safe).
------------------------------------------------------------------------
local function MakeEntry(aura, unit)
    local instID = aura.auraInstanceID
    if not instID then return nil end

    -- Source de verite : le CDM
    local spellID
    if ns.cdmData and ns.cdmData[unit] then
        local c = ns.cdmData[unit][instID]
        if c then spellID = c.spellId end
    end
    if not spellID then return nil end

    return {
        aura     = aura,
        durObj   = GetAuraDuration and GetAuraDuration(unit, instID) or nil,
        instID   = instID,
        spellID  = spellID,
        stacks   = ns.SafeStacks(aura, unit, instID),
        unit     = unit,
    }
end

------------------------------------------------------------------------
-- COLLECTE — itere sur ns.cdmData[unit] uniquement
------------------------------------------------------------------------
local function CollectFromCDM(unit)
    local all = {}
    local cdmDataU = ns.cdmData and ns.cdmData[unit]
    if not cdmDataU then return all end

    local anyWL = ns.anyWhitelist
    for instID, cdmEntry in pairs(cdmDataU) do
        local sid = cdmEntry.spellId
        local keep = (not anyWL) or (sid and anyWL[sid] == true)
        if keep then
            -- Recupere l'aura Blizzard pour stacks/durObj.
            -- Si Blizzard ne nous l'a pas (encore) propagee, on skip pour eviter
            -- les icones "?" dans le render. L'aura sera affichee au scan suivant.
            local aura
            if GetAuraDataByAuraInstanceID then
                pcall(function()
                    aura = GetAuraDataByAuraInstanceID(unit, instID)
                end)
            end
            if aura then
                local entry = MakeEntry(aura, unit)
                if entry then tinsert(all, entry) end
            end
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
local function _BuildOutputEntry(e, sid, si, dest)
    -- Champs FX3D : utilise GetFlatFieldsByDest pour supporter le per-render override.
    -- Lit s.fx3d[dest][tab] avec fallback s.fx3d["all"][tab] si dest n'a rien.
    local fx
    if ns.SpellFX and ns.SpellFX.GetFlatFieldsByDest then
        fx = ns.SpellFX:GetFlatFieldsByDest(sid, dest)
    end
    return {
        auraInstanceID = e.instID,
        aura           = e.aura,
        durObj         = e.durObj,
        spellID        = sid,
        stacks         = e.stacks,
        unit           = e.unit,
        spellColor     = si and si.color,
        glowColor      = si and si.glowColor,
        spellGlow      = si and si.glow or false,
        glowIdx        = si and si.glowIdx or 1,
        glowAlpha      = si and si.glowAlpha or 0.7,
        glowScale      = si and si.glowScale or 1.0,
        desat          = si and si.desat or false,
        procGlowIdx    = si and si.procGlowIdx or 1,
        procGlowScale  = si and si.procGlowScale or 1.0,
        -- Modeles 3D barre (per-render via fx, fallback si.barXxx)
        barModelID     = fx and fx.barModelID    or (si and si.barModelID or 0),
        barModelA      = fx and fx.barModelA     or (si and si.barModelA or 0.5),
        barModelRot    = fx and fx.barModelRot   or (si and si.barModelRot or 0),
        barModelX      = fx and fx.barModelX     or (si and si.barModelX or 0),
        barModelY      = fx and fx.barModelY     or (si and si.barModelY or 0),
        barModelZ      = fx and fx.barModelZ     or (si and si.barModelZ or 0),
        barModelS      = fx and fx.barModelS     or (si and si.barModelS or 1.0),
        barModelMode   = fx and fx.barModelMode  or (si and si.barModelMode or "bg"),
        barModelL      = fx and fx.barModelL     or (si and si.barModelL or "back"),
        barFxW         = fx and fx.barFxW        or (si and si.barFxW or 0),
        barFxH         = fx and fx.barFxH        or (si and si.barFxH or 0),
        -- 2D Fill (mode "Remplissage" pattern LinearProgressTexture)
        barFillTex     = fx and fx.barFillTex    or (si and si.barFillTex or ""),
        barFillAlpha   = fx and fx.barFillAlpha  or (si and si.barFillAlpha or 0.7),
        barFillTintR   = fx and fx.barFillTintR  or (si and si.barFillTintR or 1),
        barFillTintG   = fx and fx.barFillTintG  or (si and si.barFillTintG or 1),
        barFillTintB   = fx and fx.barFillTintB  or (si and si.barFillTintB or 1),
        barFillScroll  = fx and fx.barFillScroll or (si and si.barFillScroll or 0),
        barFillLayer   = fx and fx.barFillLayer  or (si and si.barFillLayer or "front"),
        barOverlayTex  = fx and fx.barOverlayTex   or (si and si.barOverlayTex or ""),
        barOverlayA    = fx and fx.barOverlayA     or (si and si.barOverlayA or 0.3),
        barOverlaySpeed = fx and fx.barOverlaySpeed or (si and si.barOverlaySpeed or 0.5),
        -- Modeles 3D icone
        iconModelID    = fx and fx.iconModelID  or (si and si.iconModelID or 0),
        iconModelA     = fx and fx.iconModelA   or (si and si.iconModelA or 0.5),
        iconModelX     = fx and fx.iconModelX   or (si and si.iconModelX or 0),
        iconModelY     = fx and fx.iconModelY   or (si and si.iconModelY or 0),
        iconModelZ     = fx and fx.iconModelZ   or (si and si.iconModelZ or 0),
        iconModelRot   = fx and fx.iconModelRot or (si and si.iconModelRot or 0),
        iconModelS     = fx and fx.iconModelS   or (si and si.iconModelS or 1.0),
        iconModelL     = fx and fx.iconModelL   or (si and si.iconModelL or "back"),
        iconFxW        = fx and fx.iconFxW      or (si and si.iconFxW or 0),
        iconFxH        = fx and fx.iconFxH      or (si and si.iconFxH or 0),
        iconPosX       = fx and fx.iconPosX     or (si and si.iconPosX or 0),
        iconPosY       = fx and fx.iconPosY     or (si and si.iconPosY or 0),
        -- Modeles 3D spark
        sparkModelID   = fx and fx.sparkModelID  or (si and si.sparkModelID or 0),
        sparkModelA    = fx and fx.sparkModelA   or (si and si.sparkModelA or 0.7),
        sparkModelRot  = fx and fx.sparkModelRot or (si and si.sparkModelRot or 0),
        sparkModelX    = fx and fx.sparkModelX   or (si and si.sparkModelX or 0),
        sparkModelY    = fx and fx.sparkModelY   or (si and si.sparkModelY or 0),
        sparkModelZ    = fx and fx.sparkModelZ   or (si and si.sparkModelZ or 0),
        sparkModelS    = fx and fx.sparkModelS   or (si and si.sparkModelS or 0.5),
        sparkModelL    = fx and fx.sparkModelL   or (si and si.sparkModelL or "front"),
        sparkFxW       = fx and fx.sparkFxW      or (si and si.sparkFxW or 0),
        sparkFxH       = fx and fx.sparkFxH      or (si and si.sparkFxH or 0),
        sparkPosX      = fx and fx.sparkPosX     or (si and si.sparkPosX or 0),
        sparkPosY      = fx and fx.sparkPosY     or (si and si.sparkPosY or 0),
    }
end

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
    local bySpellD, bySpellC, bySpellP, bySpellB, bySpellR = {}, {}, {}, {}, {}
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

    -- Tri par ordre de priorite (orderByDest) et construction des outputs
    local spells = ns.GetSpecSpells()
    local sA, fA, iA, bA, rA = {}, {}, {}, {}, {}
    if hasD then for _, sid in ipairs(orD) do local e = bySpellD[sid]; if e then tinsert(sA, _BuildOutputEntry(e, sid, spells and spells[sid], "iconlist"))   end end end
    if hasC then for _, sid in ipairs(orC) do local e = bySpellC[sid]; if e then tinsert(fA, _BuildOutputEntry(e, sid, spells and spells[sid], "circlebars")) end end end
    if hasP then for _, sid in ipairs(orP) do local e = bySpellP[sid]; if e then tinsert(iA, _BuildOutputEntry(e, sid, spells and spells[sid], "icons"))      end end end
    if hasB then for _, sid in ipairs(orB) do local e = bySpellB[sid]; if e then tinsert(bA, _BuildOutputEntry(e, sid, spells and spells[sid], "freebars"))   end end end
    if hasR then for _, sid in ipairs(orR) do local e = bySpellR[sid]; if e then tinsert(rA, _BuildOutputEntry(e, sid, spells and spells[sid], "centerArc"))  end end end

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

local function BuildPreviewEntries(dest)
    local out = {}
    local spells = ns.GetSpecSpells()
    local order = ns.slotOrderByDest and ns.slotOrderByDest[dest]
    for i = 1, PREVIEW_COUNT do
        local realSID = order and order[i]
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
            if pvMode == "all" or pvMode == "iconlist"   then sA = BuildPreviewEntries("iconlist")   end
            if pvMode == "all" or pvMode == "circlebars" then fA = BuildPreviewEntries("circlebars") end
            if pvMode == "all" or pvMode == "icons"      then iA = BuildPreviewEntries("icons")      end
            if pvMode == "all" or pvMode == "freebars"   then bA = BuildPreviewEntries("freebars")   end
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

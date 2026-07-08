-- AishUIAura/Core/Whitelist.lua
-- Constructeur de whitelist : filtre les sorts découverts par destination
-- (debuffs/cooldowns/procs/equipment) et met en cache le set actif pour accès rapide
-- dans les boucles chaudes du scan.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local tinsert, tsort = table.insert, table.sort
local pcall = pcall

------------------------------------------------------------------------
-- WHITELIST (multi-destination : debuffs/cooldowns/procs)
------------------------------------------------------------------------
function ns.BuildWhitelist()
    -- Auto-configure le sort du cercle central avant chaque rebuild
    if ns.AutoConfigCenterArc then pcall(ns.AutoConfigCenterArc) end
    local spells = ns.GetSpecSpells()
    if not spells then
        ns.activeWhitelist = nil; ns.whitelistByDest = nil; ns.slotOrderByDest = nil
        ns.anyWhitelist = nil
        return
    end
    ns._whitelistBuilt = true

    -- SANITY CHECK : détecte les spellIDs invalides (orphelins de patch ou DB stale).
    -- Un spellID est considéré invalide si GetSpellInfo retourne nil.
    -- On ne les supprime PAS de la DB (l'user peut y tenir), mais on les filtre
    -- de la whitelist active pour éviter les "icônes fantômes" et les erreurs
    -- à répétition dans Scan/Events.
    for id, info in pairs(spells) do
        if info.enabled then
            local ok, valid = pcall(function()
                local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                return tex ~= nil
            end)
            if ok and not valid then
                info._invalid = true  -- flag, pas de suppression
            else
                info._invalid = nil  -- reset si revenu valide (patch restauré)
            end
        end
    end

    local wl = {}
    for id, info in pairs(spells) do
        if info.enabled and not info._invalid then wl[id] = info end
    end
    ns.activeWhitelist = next(wl) and wl or nil

    -- Whitelists par destination
    local byDest = {iconlist={}, freebars={}, circlebars={}, icons={}, centerArc={}}
    local orderByDest = {iconlist={}, freebars={}, circlebars={}, icons={}, centerArc={}}
    -- Union plate de TOUTES les destinations : utilisée comme early-filter dans
    -- CollectAuras. Si un spellID n'est dans aucune destination, on skip
    -- l'allocation de MakeEntry + ses pcalls coûteux. Gain proportionnel au
    -- ratio (auras totales / auras whitelistées) qui en raid peut atteindre 10:1.
    local any = {}
    for id, info in pairs(spells) do
        if info.enabled and not info._invalid and info.destinations then
            for dest, active in pairs(info.destinations) do
                if active and byDest[dest] then
                    byDest[dest][id] = info
                    any[id] = true
                end
            end
        end
    end
    for dest, destWl in pairs(byDest) do
        local ids = {}
        for id in pairs(destWl) do tinsert(ids, id) end
        tsort(ids, function(a, b)
            local pa = destWl[a] and destWl[a].priority or 99
            local pb = destWl[b] and destWl[b].priority or 99
            if pa ~= pb then return pa < pb end; return a < b
        end)
        orderByDest[dest] = ids
    end
    ns.whitelistByDest = byDest; ns.slotOrderByDest = orderByDest
    ns.anyWhitelist = next(any) and any or nil

    -- TRACE : etat de la whitelist apres build

    -- Ré-évalue le masking CDM sur toutes les frames hookées (SetAlpha UNIQUEMENT)
    if ns.RefreshCDMMask then ns.RefreshCDMMask() end
end


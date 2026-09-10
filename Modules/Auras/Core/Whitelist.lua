-- AishUIAura/Core/Whitelist.lua
-- Filtre les sorts decouverts par destination (debuffs/cooldowns/procs/equipment), cache le set actif.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local tinsert, tsort = table.insert, table.sort
local pcall = pcall

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

    -- REGROUPEMENT PAR NOM ("verrouillage par nom") : certains
    -- buffs changent de spellID selon un seuil (ex: Precurseur du Vide --
    -- 1256301 a 1-2 stacks, 1256302 a 3+ stacks). La variante "haute" n'est
    -- pas cherchable manuellement dans "Auras a tracker" (pas un sort du
    -- grimoire) -- elle n'apparait dans discoveredSpells qu'une fois
    -- auto-decouverte par CDMHooks.lua (AutoDiscoverSpell), destinations
    -- toutes a false par defaut. L'API native AddAuraGroup ne supporte QUE
    -- includeSpellIDs (aucun matching par nom cote Blizzard) -- il faut donc
    -- unir manuellement les spellIDs homonymes cote addon avant de les
    -- passer en candidateFilters.
    --
    -- Plutot que d'obliger l'utilisateur a retrouver et cocher chaque
    -- variante separement, on l'inclut automatiquement dans la whitelist
    -- des qu'UNE AUTRE entree partageant EXACTEMENT le meme nom
    -- (info.name) est cochee pour une destination donnee -- LECTURE SEULE :
    -- ne modifie jamais info.enabled/info.destinations persiste (l'etat des
    -- cases a cocher du GUI reste inchange, seul l'EFFET sur la whitelist
    -- active est fusionne). Si la variante n'a encore jamais ete
    -- auto-decouverte (jamais vue en jeu), rien a fusionner tant qu'elle
    -- n'existe pas dans discoveredSpells -- limitation inherente, pas de
    -- moyen combat-safe de deviner un spellID jamais observe.
    --
    -- BUG CORRIGE (confirme en jeu) : regrouper par NOM SEUL fusionnait
    -- aussi des sorts totalement SANS RAPPORT qui partagent juste le meme
    -- libelle generique (ex: un debuff de donjon nomme pareil qu'une
    -- capacite du joueur deja cochee pour Barres de cercle/Totems) -- le
    -- debuff ennemi heritait alors des destinations de l'autre et
    -- apparaissait dans des barres ou il n'a jamais ete assigne, avec
    -- exactement la meme duree (meme instance d'aura reelle, juste vue par
    -- 2 entrees dont les destinations viennent d'etre fusionnees). Cle
    -- composite (nom + source) : les vraies variantes de seuil (Precurseur
    -- du Vide et consorts) partagent TOUJOURS le meme source ("debuff" des
    -- deux cotes, "buff" des deux cotes, etc.) -- un debuff ennemi et une
    -- capacite du joueur, jamais.
    local nameGroups = {}
    for id, info in pairs(spells) do
        if info.name and not info._invalid then
            local key = info.name .. "\0" .. tostring(info.source)
            local g = nameGroups[key]
            if not g then g = {}; nameGroups[key] = g end
            tinsert(g, id)
        end
    end
    local linkedDest = {}         -- [spellID] = destinations heritees d'un homonyme/lien coche
    local linkedFallbackInfo = {} -- [spellID] = info de l'ANCRE, pour un ID lie jamais decouvert independamment
    for _, ids in pairs(nameGroups) do
        if #ids > 1 then
            local merged
            for _, id in ipairs(ids) do
                local info = spells[id]
                if info.enabled and info.destinations then
                    for dest, active in pairs(info.destinations) do
                        if active then
                            merged = merged or {}
                            merged[dest] = true
                        end
                    end
                end
            end
            if merged then
                for _, id in ipairs(ids) do linkedDest[id] = merged end
            end
        end
    end

    -- Repli linkedSpellIDs (donnee Blizzard brute, cf. CDMHooks.lua) : le
    -- scan CDM normalise TOUJOURS vers linkedSpellIDs[1] avant d'appeler
    -- AutoDiscoverSpell -- la variante "haute" (ex: Precurseur du Vide a 3+
    -- stacks, spellID different) n'obtient donc SOUVENT JAMAIS sa propre
    -- entree independante dans discoveredSpells, meme apres l'avoir vecue
    -- en jeu -- le regroupement par nom ci-dessus ne peut alors rien
    -- fusionner (rien a trouver). On reutilise directement l'entree ANCRE
    -- (meme couleur/priorite/reglages) pour chaque ID lie tant qu'aucune
    -- entree separee n'existe pour lui -- plus fiable que le nom pour ce
    -- cas precis, garde les deux mecanismes en parallele (defense en
    -- profondeur, aucun des deux ne depend de l'autre).
    for id, info in pairs(spells) do
        if info.enabled and not info._invalid and type(info.linkedSpellIDs) == "table" and info.destinations then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                if linkedID ~= id then
                    local ld = linkedDest[linkedID]
                    if not ld then ld = {}; linkedDest[linkedID] = ld end
                    for dest, active in pairs(info.destinations) do
                        if active then ld[dest] = true end
                    end
                    if not spells[linkedID] then linkedFallbackInfo[linkedID] = info end
                end
            end
        end
    end

    local wl = {}
    for id, info in pairs(spells) do
        if (info.enabled or linkedDest[id]) and not info._invalid and not info._adminDeleted then wl[id] = info end
    end
    for id, info in pairs(linkedFallbackInfo) do
        if not info._adminDeleted then wl[id] = info end
    end
    ns.activeWhitelist = next(wl) and wl or nil

    -- Whitelists par destination
    local byDest = {iconlist={}, freebars={}, circlebars={}, icons={}, centerArc={}, totems={}}
    local orderByDest = {iconlist={}, freebars={}, circlebars={}, icons={}, centerArc={}, totems={}}
    -- Union plate de TOUTES les destinations : utilisée comme early-filter dans
    -- CollectAuras. Si un spellID n'est dans aucune destination, on skip
    -- l'allocation de MakeEntry + ses pcalls coûteux. Gain proportionnel au
    -- ratio (auras totales / auras whitelistées) qui en raid peut atteindre 10:1.
    -- Mode admin ("Auras a tracker") : un sort marque "supprime" (croix, cf.
    -- Tactics.lua) reste dans discoveredSpells (annulable) mais ne doit plus
    -- JAMAIS rendre quoi que ce soit tant qu'il l'est -- exclu ici comme les
    -- entrees _invalid.
    local any = {}
    for id, info in pairs(spells) do
        if not info._invalid and not info._adminDeleted and info.destinations then
            if info.enabled then
                for dest, active in pairs(info.destinations) do
                    if active and byDest[dest] then
                        byDest[dest][id] = info
                        any[id] = true
                    end
                end
            end
            local ld = linkedDest[id]
            if ld then
                for dest, active in pairs(ld) do
                    if active and byDest[dest] then
                        byDest[dest][id] = info
                        any[id] = true
                    end
                end
            end
        end
    end
    for id, info in pairs(linkedFallbackInfo) do
        local ld = linkedDest[id]
        if ld and info.destinations and not info._adminDeleted then
            for dest, active in pairs(ld) do
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

    -- Auto-epinglage CDM DESACTIVE : les 4 destinations de rendu
    -- (icons/circlebars/freebars/iconlist) sont desormais 100% natives
    -- (AddAuraGroup + SetUnit("player"), cf. AuraTrackerContainer.lua) --
    -- plus aucune ne depend de ns.cdmData/du pin CDM pour la presence, la
    -- duree ou les stacks. Ce force-pin (SyncCDMPins) ne servait plus qu'a
    -- forcer un reload inutile a chaque fermeture du GUI (popup "X aura(s)
    -- epinglee(s)") sans aucun benefice visuel restant. NOTE : ns.SyncCDMPins() reste utilisee
    -- ailleurs (Config/Profiles.lua ApplyCDMForSpec, pour rattraper la
    -- whitelist apres restauration d'un snapshot CDM de spec) -- feature
    -- separee et deliberee, volontairement non touchee ici. Consequence
    -- acceptee : un spellID JAMAIS observe en jeu (jamais auto-decouvert
    -- par CDMHooks.lua, qui necessite une frame CDM live pour ce sort) ne
    -- peut plus etre auto-decouvert seulement par ce chemin -- reste
    -- decouvert normalement des qu'il apparait sur un viewer CDM
    -- (Essentiel/Utilitaire, ou Ameliorations si Blizzard le suit deja par
    -- defaut), simplement plus force par cet addon.
    --
    -- TRACE : etat de la whitelist apres build

    -- Ré-évalue le masking CDM sur toutes les frames hookées (SetAlpha UNIQUEMENT)
    if ns.RefreshCDMMask then ns.RefreshCDMMask() end

    -- AuraTrackerContainer.lua (systeme AuraContainer/AuraButton natif
    -- Blizzard) : cree un AddAuraSlot fixe par spellID whitelist --
    -- ApplyNativeAuraBindings
    -- (Debuffs.lua/Cooldowns.lua/Procs.lua, deja cable) branche
    -- SetDurationCooldown/SetApplicationCount sur les widgets AishCore
    -- existants des que le slot est disponible. Idempotent, hors combat
    -- uniquement (cf. AuraTrackerContainer.lua pour le detail).
    --
    -- AuraTextRelay.lua reste desactive : probleme different et toujours
    -- valide (FontString "forbidden" en lecture).
    if ns.EnsureAuraTrackerContainer then pcall(ns.EnsureAuraTrackerContainer) end

    -- Grille native pour la destination "icons" (Procs.lua) : icone/cooldown/
    -- stacks REELLEMENT pilotes par Blizzard (enfants directs de l'auraButton,
    -- pas de repli Lua sur la presence) -- cf. AuraTrackerContainer.lua pour
    -- le detail. RepositionIconsNativeGrid doit tourner a CHAQUE rebuild
    -- (pas seulement a la creation de nouveaux slots) : l'ordre de priorite
    -- (ns.slotOrderByDest.icons) peut changer sans qu'aucun nouveau slot ne
    -- soit necessaire.
    if ns.EnsureIconsNativeGrid then pcall(ns.EnsureIconsNativeGrid) end
    if ns.RepositionIconsNativeGrid then pcall(ns.RepositionIconsNativeGrid) end

    -- TEST/PROTOTYPE : meme grille native, mais SetUnit("target")+"HARMFUL"
    -- pour les sorts info.source=="debuff" -- cf. AuraTrackerContainer.lua,
    -- section "GRILLE NATIVE FLOW CIBLE". Rangee separee, empilee sous la
    -- rangee joueur ci-dessus.
    if ns.EnsureIconsNativeGridTarget then pcall(ns.EnsureIconsNativeGridTarget) end
    if ns.RepositionIconsNativeGridTarget then pcall(ns.RepositionIconsNativeGridTarget) end

    -- Grille MANUELLE pour la destination dediee "Totems" (Core/Totems.lua) --
    -- pas d'AddAuraGroup possible (un totem n'est pas une vraie aura), meme
    -- disposition/reglages que "Free Bars" (icone+barre, cf. Defaults.lua).
    if ns.EnsureTotemsGrid then pcall(ns.EnsureTotemsGrid) end
    if ns.RepositionTotemsGrid then pcall(ns.RepositionTotemsGrid) end

    -- Grille native pour la destination GUI "Circle Bars" (Buffs.lua, cle
    -- interne freebars) : meme methodologie que "icons". Barres de duree
    -- combat-safe SANS pin CDM, aucune icone (SetDurationBar seul).
    if ns.EnsureCircleBarsNativeGrid then pcall(ns.EnsureCircleBarsNativeGrid) end
    if ns.RepositionCircleBarsNativeGrid then pcall(ns.RepositionCircleBarsNativeGrid) end

    if ns.EnsureCircleBarsNativeGridTarget then pcall(ns.EnsureCircleBarsNativeGridTarget) end
    if ns.RepositionCircleBarsNativeGridTarget then pcall(ns.RepositionCircleBarsNativeGridTarget) end

    -- Grille native pour la destination GUI "Free Bars" (Cooldowns.lua, cle
    -- interne circlebars) : meme methodologie. Icone+cooldown+stacks+glow+
    -- barre(s) de duree combat-safe SANS pin CDM.
    if ns.EnsureFreeBarsNativeGrid then pcall(ns.EnsureFreeBarsNativeGrid) end
    if ns.RepositionFreeBarsNativeGrid then pcall(ns.RepositionFreeBarsNativeGrid) end

    if ns.EnsureFreeBarsNativeGridTarget then pcall(ns.EnsureFreeBarsNativeGridTarget) end
    if ns.RepositionFreeBarsNativeGridTarget then pcall(ns.RepositionFreeBarsNativeGridTarget) end

    -- Grille native pour la destination GUI "Liste d'icones" (Debuffs.lua,
    -- cle interne iconlist) : meme methodologie. Icone+cooldown+stacks+glow+
    -- barre(s) de duree combat-safe SANS pin CDM.
    if ns.EnsureIconListNativeGrid then pcall(ns.EnsureIconListNativeGrid) end
    if ns.RepositionIconListNativeGrid then pcall(ns.RepositionIconListNativeGrid) end

    if ns.EnsureIconListNativeGridTarget then pcall(ns.EnsureIconListNativeGridTarget) end
    if ns.RepositionIconListNativeGridTarget then pcall(ns.RepositionIconListNativeGridTarget) end
end


-- AishUIAura/Core/AuraTrackerContainer.lua
--
-- Rendu combat-safe des auras trackees via le systeme natif Blizzard
-- AuraContainer (patch 12.1+, "Secret Values") : pour chacune des 4
-- destinations (Icons, Circle Bars, Free Bars, Icon List), un AuraContainer
-- persistant heberge un AddAuraGroup dedie par spellID trace, dont
-- l'auraButton pilote nativement icone/cooldown de duree/stacks/barre de
-- duree via SetIcon/SetDurationCooldown/SetApplicationCount/SetDurationBar
-- -- sans jamais exposer de valeur secrete a Lua.
--
-- Contraintes API a connaitre avant de retoucher ce fichier :
--   - Le champ de filtrage exact est `includeSpellIDs`.
--   - Un AuraButton natif (et tout enfant qu'on y cree) devient "forbidden"
--     -- meme en LECTURE -- des que l'aura associee devient secrete
--     (combat/instance/PvP). Toute creation/liaison doit donc se faire UNE
--     SEULE FOIS dans initializeFrame, jamais retouchee ensuite (seules les
--     proprietes de STYLE -- couleur, texture, glow -- restent modifiables
--     hors contexte secret, cf. ApplyXxxButtonStyle plus bas).
--   - Blizzard ne positionne jamais le bouton natif seul : il faut l'ancrer
--     nous-memes (SetPoint/SetAllPoints) dans initializeFrame.
--   - SetEnabled(true) + Show() + UpdateAllAuras() sur le CONTENEUR (pas le
--     bouton) sont necessaires apres creation des groupes ; SetEnabled doit
--     preceder SetUnit.
--   - La presence combat-safe (Show/Hide) ne peut pas etre suivie via
--     HookScript("OnShow"/"OnHide", ...) sur un AuraButton natif -- Blizzard
--     bloque explicitement l'assignation de script handler des qu'une aura
--     secrete peut lui etre liee. ns._lastKnownAura (Scan.lua) reste donc la
--     source de verite pour la presence.
--   - Un AddAuraGroup ne peut jamais etre supprime une fois cree -- un
--     spellID de-trace se neutralise via SetAuraGroupCandidateFilters sur un
--     spellID bidon (jamais {}, qui signifie "aucune restriction" et fait
--     matcher toutes les auras).
--   - Creer un AuraContainer EN COMBAT plante le jeu : la creation doit
--     rester unique, hors combat (login/reload), jamais recreee
--     dynamiquement.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local nativeButtons = { player = {} }  -- [unit] = { [spellID] = button natif }
local shadowBars    = { player = {} }  -- [unit] = { [spellID] = StatusBar } -- inutilise pour l'instant (aucun binding SetDurationBar tente ici)

-- Toujours exposees (call sites existants dans Debuffs.lua/Cooldowns.lua/
-- Procs.lua/Animation.lua les appellent deja avec un garde "if nativeBtn
-- then" -- renvoyer nil est sans danger, ces chemins retombent proprement
-- sur les canaux CDM deja fonctionnels tant qu'un slot n'existe pas encore
-- pour ce spellID, cf. commentaire ApplyNativeAuraBindings/Debuffs.lua).
function ns.GetNativeAuraButton(unit, spellID)
    local t = nativeButtons[unit]
    return t and t[spellID]
end

function ns.GetNativeShadowBar(unit, spellID)
    local t = shadowBars[unit]
    return t and t[spellID]
end

------------------------------------------------------------------------
-- Conteneur AuraContainer persistant, un AddAuraSlot fixe par spellID de
-- la whitelist active (joueur uniquement -- pas d'equivalent combat-safe
-- pour la cible). Chaque slot expose son auraButton natif via
-- ns.GetNativeAuraButton, que ApplyNativeAuraBindings (Debuffs.lua/
-- Cooldowns.lua/Procs.lua, DEJA cable et appele a chaque scan) utilise pour
-- brancher SetDurationCooldown/SetApplicationCount sur le Cooldown/FontString
-- DEJA existants de la ligne AishCore -- aucune modification necessaire
-- cote rendu, uniquement la production ici.
--
-- Ce systeme ne pilote PAS la presence/le Show-Hide des lignes AishCore
-- (ns._lastKnownAura, Scan.lua, reste la source de verite pour ca) --
-- uniquement la fiabilite combat-safe du texte de stacks et de l'anneau de
-- cooldown de duree pour une ligne DEJA affichee.
------------------------------------------------------------------------
local container
local slotKeyBySpell = {}  -- [spellID] = "aishNativeN" -- evite de recreer un slot deja existant
local slotCounter = 0

-- PRESENCE COMBAT-SAFE PAR HOOK OnShow/OnHide : TENTE ET ABANDONNE.
-- La creation d'icone/cooldown/stacks (SetIcon/SetDurationCooldown/
-- SetApplicationCount) reussit integralement, MAIS
-- auraButton:HookScript("OnShow"/"OnHide", ...) echoue systematiquement
-- avec une erreur EXPLICITE et catchable :
--   "Button:HookScript(): Cannot assign script handler for 'onshow'
--    (blocked by secret aspects)"
-- Blizzard bloque donc DELIBEREMENT l'attache d'un script OnShow/OnHide sur
-- un AuraButton des qu'il peut porter des auras secretes -- contrairement au
-- pattern hooksecurefunc qui fonctionne pour les Cooldown-enfants du CDM
-- (CDMHooks.lua), HookScript n'est PAS une echappatoire ici. Aucun
-- contournement de code possible -- restriction plateforme confirmee, pas un
-- bug de cette implementation. La presence combat-safe pour un spellID qui
-- n'a JAMAIS ete vu hors combat reste donc non-resolue : ns._lastKnownAura
-- (Scan.lua) -- qui exige une lecture directe reussie hors combat au moins
-- une fois -- demeure la meilleure approximation disponible.

local function EnsureContainer()
    if container then return container end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then return nil end
    container = result
    -- Jamais visible pour l'utilisateur (alpha=0) -- AishCore garde son
    -- propre rendu/layout. A L'ECRAN (pas hors-cadre) et taille normale :
    -- un conteneur/bouton hors-cadre ou de taille degeneree 1x1 empeche
    -- Blizzard d'assigner correctement l'aura. SetEnabled AVANT SetUnit.
    container:SetSize(64, 64)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    container:SetAlpha(0)
    pcall(container.SetEnabled, container, true)
    pcall(container.SetUnit, container, "player")
    container:Show()
    return container
end

-- Cree (si pas deja fait) un slot fixe pour spellID. Ne fait RIEN si le
-- slot existe deja (idempotent, safe a appeler a chaque rebuild de whitelist).
-- Sert UNIQUEMENT au forwarding icone/duree/stacks (ApplyNativeAuraBindings,
-- Debuffs.lua/Cooldowns.lua/Procs.lua) sur une ligne DEJA affichee -- pas a
-- la presence elle-meme (cf. bloc de commentaires ci-dessus).
local function EnsureSlotForSpell(spellID)
    if slotKeyBySpell[spellID] then return end
    local c = EnsureContainer()
    if not c then return end

    slotCounter = slotCounter + 1
    local key = "aishNative" .. slotCounter
    slotKeyBySpell[spellID] = key

    pcall(function()
        c:AddAuraSlot(key, "HELPFUL", {
            candidateFilters = { includeSpellIDs = {} },
            initializeFrame = function(auraButton)
                local okCheck, canAccess = pcall(function()
                    return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
                end)
                if not (okCheck and canAccess) then return end
                -- Tout doit se faire ICI, une seule fois (l'auraButton et tout
                -- enfant cree dessus deviennent "forbidden" -- meme en
                -- lecture -- des que l'aura devient secrete). L'icone/l'ancrage
                -- ici ne sont JAMAIS affiches -- seule la fonction de forwarding (SetDurationCooldown/
                -- SetApplicationCount, rebranches par ApplyNativeAuraBindings sur
                -- les vrais widgets de la ligne AishCore) compte.
                pcall(function()
                    local icon = auraButton:CreateTexture(nil, "ARTWORK")
                    icon:SetAllPoints(auraButton)
                    auraButton:SetIcon(icon)
                    -- Taille normale (pas degeneree) : confirme necessaire en
                    -- jeu, cf. commentaire EnsureContainer plus haut.
                    auraButton:SetSize(32, 32)
                    auraButton:ClearAllPoints()
                    auraButton:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
                end)
                nativeButtons.player[spellID] = auraButton
            end,
        })
        c:SetAuraSlotCandidateFilters(key, { includeSpellIDs = { [spellID] = true } })
        if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
    end)
end

-- ETALEMENT : creer plusieurs slots dans la MEME frame ne pose pas de
-- probleme en soi -- ce comportement est garde par prudence/coherence,
-- cout marginal.
local pendingSlotQueue = {}
local slotQueueTimer = nil
local SLOT_STAGGER_DELAY = 0.2

local function ProcessSlotQueue()
    slotQueueTimer = nil
    local spellID = table.remove(pendingSlotQueue, 1)
    if spellID then
        EnsureSlotForSpell(spellID)
        if #pendingSlotQueue > 0 then
            slotQueueTimer = C_Timer.After(SLOT_STAGGER_DELAY, ProcessSlotQueue)
        end
    end
end

function ns.EnsureAuraTrackerContainer()
    if InCombatLockdown and InCombatLockdown() then return end
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    for spellID, info in pairs(spells) do
        if info.enabled and not info._invalid and not slotKeyBySpell[spellID] then
            -- Evite les doublons dans la file si BuildWhitelist est rappele
            -- avant que la file precedente ait fini de s'ecouler.
            local alreadyQueued = false
            for _, queued in ipairs(pendingSlotQueue) do
                if queued == spellID then alreadyQueued = true; break end
            end
            if not alreadyQueued then
                pendingSlotQueue[#pendingSlotQueue + 1] = spellID
            end
        end
    end
    if not slotQueueTimer and #pendingSlotQueue > 0 then
        slotQueueTimer = C_Timer.After(SLOT_STAGGER_DELAY, ProcessSlotQueue)
    end
end

------------------------------------------------------------------------
-- TEST ISOLE : /aishdebug testcontainer <spellID>
--
-- Valide en jeu, en isolation totale (aucune interaction avec le pipeline
-- Debuffs.lua/Scan.lua existant), si le systeme natif AuraContainer peut
-- reellement piloter icone + stacks + duree pour un spellID donne, avant
-- d'investir dans le raccordement complet au rendu.
--
-- Recette :
--   - AddAuraSlot (pas AddAuraGroup, un seul spellID = un seul bouton fixe)
--   - candidateFilters = {includeSpellIDs = {}} passe des la creation, puis
--     SetAuraSlotCandidateFilters(key, {includeSpellIDs=REAL}) ensuite
--   - initializeFrame : cree ICI, UNE SEULE FOIS, icone/cooldown/fontstring
--     a nous, bindes via SetIcon/SetDurationCooldown/SetApplicationCount --
--     jamais retouches en dehors de ce callback (AuraButton devient
--     "forbidden", meme en lecture, des que secret)
--
-- SECURITE : ne cree le conteneur qu'UNE SEULE FOIS, hors combat (refuse en
-- combat). Ne recree jamais dynamiquement -- creer un AuraContainer en
-- combat plante le jeu.
------------------------------------------------------------------------
local testContainer, testSlotKey = nil, "aishTestSlot"

function ns.DebugTestNativeContainer(spellIDs)
    local P = function(s) print("|cff33aaff[TestContainer]|r " .. s) end
    -- Accepte un spellID unique (retro-compat) ou une liste -- plusieurs IDs
    -- ensemble sert a tester l'hypothese "chaine de sorts par palier" (ex.
    -- Precurseur du Vide : 3 spellID distincts observes en jeu, peut-etre 3
    -- rangs d'un meme concept plutot qu'un seul spellID avec applications
    -- croissant) -- un seul spellID inclus dans candidateFilters ferait
    -- disparaitre l'icone des que le palier change vers un AUTRE spellID,
    -- meme si le buff reste actif sous une autre forme.
    if type(spellIDs) == "number" then spellIDs = { spellIDs } end
    if not spellIDs or #spellIDs == 0 then P("usage : /aishdebug testcontainer <spellID> [spellID2] [spellID3] ..."); return end
    if InCombatLockdown and InCombatLockdown() then
        P("|cffff4444refuse en combat (creation AuraContainer interdite en combat)|r")
        return
    end
    if not CreateFrame then P("|cffff4444CreateFrame indisponible ?|r"); return end

    if not testContainer then
        local okCreate, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not okCreate or not result then
            P("|cffff4444echec CreateFrame AuraContainer (template indisponible sur ce client ?) : " .. tostring(result) .. "|r")
            return
        end
        testContainer = result
        testContainer:SetSize(64, 64)
        testContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        testContainer:SetFrameStrata("TOOLTIP")

        local okSlot, errSlot = pcall(function()
            testContainer:AddAuraSlot(testSlotKey, "HELPFUL", {
                candidateFilters = { includeSpellIDs = {} },
                initializeFrame = function(auraButton)
                    if not (auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()) then
                        P("|cffff4444initializeFrame : CanBeAccessedInContext=false, abandon|r")
                        return
                    end
                    local durBar
                    local okInit, errInit = pcall(function()
                        local icon = auraButton:CreateTexture(nil, "ARTWORK")
                        icon:SetAllPoints(auraButton)
                        auraButton:SetIcon(icon)

                        local cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                        cd:SetAllPoints(auraButton)
                        auraButton:SetDurationCooldown(cd)

                        local countFS = auraButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
                        countFS:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", -2, 2)
                        auraButton:SetApplicationCount(countFS, {})

                        auraButton:ClearAllPoints()
                        auraButton:SetPoint("CENTER", testContainer, "CENTER", 0, 0)
                        auraButton:SetSize(64, 64)

                        -- BARRE DE DUREE : testee ici en isolation (AddAuraSlot,
                        -- comme le reste de cet outil) avant d'envisager de la
                        -- cabler dans le vrai rendu "icons" -- cf. section
                        -- diagnostics ci-dessous pour lire le resultat en jeu.
                        durBar = CreateFrame("StatusBar", nil, testContainer)
                        durBar:SetSize(64, 8)
                        durBar:SetPoint("TOP", auraButton, "BOTTOM", 0, -4)
                        durBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        durBar:SetStatusBarColor(0.2, 0.8, 1)
                        local durBg = durBar:CreateTexture(nil, "BACKGROUND")
                        durBg:SetAllPoints(); durBg:SetColorTexture(0.05, 0.05, 0.05, 1)
                        auraButton:SetDurationBar(durBar)
                    end)
                    P(string.format("initializeFrame : ok=%s%s", tostring(okInit), okInit and " -- widgets crees et bindes" or (" err=" .. tostring(errInit))))
                    if durBar then
                        C_Timer.After(1.5, function()
                            local okState, w2, h2 = pcall(function() return durBar:GetSize() end)
                            local okMinMax, mn, mx = pcall(function() return durBar:GetMinMaxValues() end)
                            local okVal, val = pcall(function() return durBar:GetValue() end)
                            P(string.format("|cffffcc00[Barre de duree]|r IsVisible=%s taille=%s minmax=%s valeur=%s",
                                tostring(durBar:IsVisible()),
                                okState and string.format("%.0fx%.0f", w2, h2) or "?",
                                okMinMax and string.format("%s-%s", tostring(mn), tostring(mx)) or "?",
                                okVal and tostring(val) or "?"))
                        end)
                    end
                end,
            })
        end)
        P(string.format("AddAuraSlot : ok=%s%s", tostring(okSlot), okSlot and "" or (" err=" .. tostring(errSlot))))

        local okEnable, errEnable = pcall(testContainer.SetEnabled, testContainer, true)
        local okUnit, errUnit = pcall(testContainer.SetUnit, testContainer, "player")
        testContainer:Show()
        P(string.format("SetEnabled : ok=%s%s  |  SetUnit(player) : ok=%s%s",
            tostring(okEnable), okEnable and "" or (" err=" .. tostring(errEnable)),
            tostring(okUnit), okUnit and "" or (" err=" .. tostring(errUnit))))
        P("Conteneur cree et affiche au centre de l'ecran (150px au-dessus du centre, cadre TOOLTIP).")
    end

    local includeSpellIDs = {}
    for _, sid in ipairs(spellIDs) do includeSpellIDs[sid] = true end
    local ok, err = pcall(testContainer.SetAuraSlotCandidateFilters, testContainer, testSlotKey, { includeSpellIDs = includeSpellIDs })
    P(string.format("SetAuraSlotCandidateFilters({%s}) : ok=%s%s", table.concat(spellIDs, ","), tostring(ok), ok and "" or (" err=" .. tostring(err))))

    if testContainer.UpdateAllAuras then
        local okUpd, errUpd = pcall(testContainer.UpdateAllAuras, testContainer)
        P(string.format("UpdateAllAuras : ok=%s%s", tostring(okUpd), okUpd and "" or (" err=" .. tostring(errUpd))))
    end

    P("=> Observe le cadre au centre de l'ecran (au-dessus du perso) : icone apparait/disparait avec le buff (hors ET en combat) ? Nombre de stacks visible/juste ? Anneau de cooldown anime si le sort a une duree ?")
end

------------------------------------------------------------------------
-- TEST ISOLE : /aishdebug testbar <spellID>
--
-- Prepare la migration de la destination "Circle Bars" (Buffs.lua, cle
-- interne freebars -- PAS a confondre avec "circlebars"/Cooldowns.lua, qui
-- est en fait la destination GUI "Free Bars") : contrairement a "Icons", ses
-- lignes sont a POSITION FIXE (rang N = toujours le sort N de la
-- whitelist), pas un flow qui se recompacte -- et elle n'a AUCUNE icone,
-- juste des StatusBar.
--
-- Deux inconnues testees ici EN ISOLATION avant tout code reel :
--   1) AddAuraGroup fonctionne-t-il SANS jamais appeler
--      SetFlowLayoutAnchorPoint/Axis/GrowthDirection/MaximumLineSize, avec
--      un positionnement 100% manuel (SetPoint) dans initializeFrame ?
--   2) SetDurationBar fonctionne-t-il sur un auraButton SANS icone/cooldown/
--      stacks du tout (juste une StatusBar) ?
------------------------------------------------------------------------
local testBarContainer, testBarGroupKey = nil, "aishTestBarGroup"

function ns.DebugTestBarOnlyGroup(spellIDs)
    local P = function(s) print("|cff33aaff[TestBarGroup]|r " .. s) end
    if type(spellIDs) == "number" then spellIDs = { spellIDs } end
    if not spellIDs or #spellIDs == 0 then P("usage : /aishdebug testbar <spellID> [spellID2] ..."); return end
    if InCombatLockdown and InCombatLockdown() then
        P("|cffff4444refuse en combat (creation AuraContainer interdite en combat)|r")
        return
    end
    if not CreateFrame then P("|cffff4444CreateFrame indisponible ?|r"); return end

    if not testBarContainer then
        local okCreate, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not okCreate or not result then
            P("|cffff4444echec CreateFrame AuraContainer : " .. tostring(result) .. "|r")
            return
        end
        testBarContainer = result
        testBarContainer:SetSize(200, 20)
        testBarContainer:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        testBarContainer:SetFrameStrata("TOOLTIP")

        -- ORDRE : SetEnabled/SetUnit/Show AVANT AddAuraGroup, pas apres --
        -- c'est l'ordre utilise par le rendu "icons" qui fonctionne
        -- reellement (EnsureIconsFlowContainer les pose avant que
        -- EnsureIconsNativeGrid n'appelle AddAuraGroup). L'ordre inverse
        -- (AddAuraGroup d'abord) est une cause possible de "barre jamais
        -- alimentee" independamment de l'icone/du flow layout.
        local okEnable, errEnable = pcall(testBarContainer.SetEnabled, testBarContainer, true)
        local okUnit, errUnit = pcall(testBarContainer.SetUnit, testBarContainer, "player")
        testBarContainer:Show()
        P(string.format("SetEnabled : ok=%s%s  |  SetUnit(player) : ok=%s%s",
            tostring(okEnable), okEnable and "" or (" err=" .. tostring(errEnable)),
            tostring(okUnit), okUnit and "" or (" err=" .. tostring(errUnit))))

        local includeSpellIDs = {}
        for _, sid in ipairs(spellIDs) do includeSpellIDs[sid] = true end

        local okAdd, errAdd = pcall(function()
            testBarContainer:AddAuraGroup(testBarGroupKey, "HELPFUL", {
                maxFrameCount = 1,
                candidateFilters = { includeSpellIDs = includeSpellIDs },
                -- PAS de champ "layout" ici, volontairement : on verifie si
                -- AddAuraGroup fonctionne sans jamais configurer de flow.
                initializeFrame = function(auraButton)
                    if not (auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()) then
                        P("|cffff4444initializeFrame : CanBeAccessedInContext=false, abandon|r")
                        return
                    end
                    local barL, barR
                    local okInit, errInit = pcall(function()
                        -- Circle Bars a besoin de DEUX barres miroir (barL/
                        -- barR) montrant la MEME duree -- SetDurationBar
                        -- n'accepte peut-etre qu'UNE seule cible. Test : on
                        -- l'appelle deux fois, sur deux StatusBar distinctes,
                        -- pour voir si Blizzard alimente les DEUX ou seulement
                        -- la derniere appelee.
                        auraButton:SetSize(200, 20)
                        auraButton:ClearAllPoints()
                        auraButton:SetPoint("CENTER", testBarContainer, "CENTER", 0, 0)

                        barL = CreateFrame("StatusBar", nil, auraButton)
                        barL:SetPoint("TOPLEFT", auraButton, "TOPLEFT", 0, 0)
                        barL:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOM", -2, 0)
                        barL:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        barL:SetStatusBarColor(0.2, 0.8, 1)
                        barL:SetReverseFill(true)
                        local bgL = barL:CreateTexture(nil, "BACKGROUND"); bgL:SetAllPoints(); bgL:SetColorTexture(0.05, 0.05, 0.05, 1)

                        barR = CreateFrame("StatusBar", nil, auraButton)
                        barR:SetPoint("TOPRIGHT", auraButton, "TOPRIGHT", 0, 0)
                        barR:SetPoint("BOTTOMLEFT", auraButton, "BOTTOM", 2, 0)
                        barR:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        barR:SetStatusBarColor(1, 0.6, 0.1)
                        local bgR = barR:CreateTexture(nil, "BACKGROUND"); bgR:SetAllPoints(); bgR:SetColorTexture(0.05, 0.05, 0.05, 1)

                        -- barL : sans option (comportement par defaut --
                        -- remplit avec le temps ecoule).
                        auraButton:SetDurationBar(barL)
                        -- barR : direction=RemainingTime est la seule vraie
                        -- API de reversal, confirmee marcher en jeu.
                        auraButton:SetDurationBar(barR, { direction = Enum.StatusBarTimerDirection.RemainingTime })
                    end)
                    P(string.format("initializeFrame (2 StatusBar, SetDurationBar appele 2x) : ok=%s%s", tostring(okInit), okInit and "" or (" err=" .. tostring(errInit))))
                end,
            })
        end)
        P(string.format("AddAuraGroup (maxFrameCount=1, SANS flow layout) : ok=%s%s", tostring(okAdd), okAdd and "" or (" err=" .. tostring(errAdd))))
        P("Conteneur cree (150px SOUS le centre, cadre TOOLTIP) -- barre SEULE, sans icone.")
    else
        local includeSpellIDs = {}
        for _, sid in ipairs(spellIDs) do includeSpellIDs[sid] = true end
        local ok, err = pcall(testBarContainer.SetAuraGroupCandidateFilters, testBarContainer, testBarGroupKey, { includeSpellIDs = includeSpellIDs })
        P(string.format("SetAuraGroupCandidateFilters({%s}) : ok=%s%s", table.concat(spellIDs, ","), tostring(ok), ok and "" or (" err=" .. tostring(err))))
    end

    if testBarContainer.UpdateAllAuras then
        local okUpd, errUpd = pcall(testBarContainer.UpdateAllAuras, testBarContainer)
        P(string.format("UpdateAllAuras : ok=%s%s", tostring(okUpd), okUpd and "" or (" err=" .. tostring(errUpd))))
    end

    P("=> Observe 150px SOUS le centre de l'ecran : la BLEUE (gauche, sans option) se remplit -- l'ORANGE (droite, direction=RemainingTime) doit se VIDER.")
end

------------------------------------------------------------------------
-- TEST ISOLE : /aishdebug testmulti <spellID1> <spellID2>
--
-- Prepare la reponse a "2 buffs actifs en meme temps => toutes les barres
-- Circle Bars disparaissent, et reapparaissent seulement quand on retombe a
-- 1 buff actif" -- teste EN ISOLATION, sans aucune des complexites propres
-- a Circle Bars (taille de conteneur, layout, strata, 2 StatusBar miroir
-- par bouton...), si un AddAuraGroup avec maxFrameCount=3 peut ne serait-ce
-- QUE positionner/afficher 2 candidats DIFFERENTS simultanement. Si ce test
-- isole reproduit aussi le bug, c'est une limitation Blizzard/plateforme
-- generale (potentiellement partagee avec "icons", jamais testee avec 2
-- sorts traques simultanement actifs) -- pas specifique a Circle Bars.
------------------------------------------------------------------------
local testMultiContainer, testMultiGroupKey = nil, "aishTestMultiGroup"

function ns.DebugTestMultiGroup(spellIDs)
    local P = function(s) print("|cff33aaff[TestMulti]|r " .. s) end
    if not spellIDs or #spellIDs < 2 then P("usage : /aishdebug testmulti <spellID1> <spellID2> [spellID3...] -- au moins 2 sorts DIFFERENTS que tu peux activer en meme temps"); return end
    if InCombatLockdown and InCombatLockdown() then
        P("|cffff4444refuse en combat (creation AuraContainer interdite en combat)|r")
        return
    end

    if not testMultiContainer then
        local okCreate, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not okCreate or not result then
            P("|cffff4444echec CreateFrame AuraContainer : " .. tostring(result) .. "|r")
            return
        end
        testMultiContainer = result
        -- Assez grand pour contenir large les 3 marqueurs sans jamais
        -- soupconner un probleme de taille de conteneur (deja ecarte pour
        -- Circle Bars mais on l'ecarte ICI aussi, definitivement).
        testMultiContainer:SetSize(700, 700)
        testMultiContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        testMultiContainer:SetFrameStrata("TOOLTIP")

        local okEnable, errEnable = pcall(testMultiContainer.SetEnabled, testMultiContainer, true)
        local okUnit, errUnit = pcall(testMultiContainer.SetUnit, testMultiContainer, "player")
        testMultiContainer:Show()
        P(string.format("SetEnabled : ok=%s%s | SetUnit(player) : ok=%s%s",
            tostring(okEnable), okEnable and "" or (" err=" .. tostring(errEnable)),
            tostring(okUnit), okUnit and "" or (" err=" .. tostring(errUnit))))

        local includeSpellIDs = {}
        for _, sid in ipairs(spellIDs) do includeSpellIDs[sid] = true end
        local slotCounter = 0
        local colors = { {1,0.2,0.2}, {0.2,1,0.2}, {0.2,0.5,1} }
        local positions = { {-250,0}, {0,0}, {250,0} }  -- tres ecartes, aucune ambiguite visuelle

        local okAdd, errAdd = pcall(function()
            testMultiContainer:AddAuraGroup(testMultiGroupKey, "HELPFUL", {
                maxFrameCount = 8,  -- aligne sur Circle Bars (8)
                candidateFilters = { includeSpellIDs = includeSpellIDs },
                layout = { elementSpacing = 10, lineSpacing = 10, elementWidth = 150, elementHeight = 150, layoutIndex = 1 },
                initializeFrame = function(auraButton)
                    if not (auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()) then
                        P("|cffff4444initializeFrame : CanBeAccessedInContext=false, abandon|r")
                        return
                    end
                    local okInit, errInit = pcall(function()
                        slotCounter = slotCounter + 1
                        local idx = slotCounter
                        local col = colors[idx] or {1,1,1}

                        -- PAS de SetPoint manuel -- laisse Blizzard positionner
                        -- via le flow layout configure juste apres AddAuraGroup
                        -- (SetFlowLayout*), comme Circle Bars.
                        auraButton:SetSize(150, 150)

                        local bg = auraButton:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(); bg:SetColorTexture(col[1], col[2], col[3], 0.5)

                        local label = auraButton:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
                        label:SetPoint("CENTER")
                        label:SetText("#" .. tostring(idx))

                        -- DEUX StatusBar liees via SetDurationBar (comme
                        -- Circle Bars, barL+barR) au lieu d'une seule -- teste
                        -- si lier 2 barres PAR bouton, combine a PLUSIEURS
                        -- boutons actifs simultanement, casse le groupe entier
                        -- (contrairement a 1 seule barre/bouton, confirme
                        -- fonctionner ci-dessus).
                        local barTop = CreateFrame("StatusBar", nil, auraButton)
                        barTop:SetPoint("BOTTOMLEFT", 10, 35); barTop:SetPoint("BOTTOMRIGHT", -10, 35); barTop:SetHeight(20)
                        barTop:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        barTop:SetStatusBarColor(1,1,1)
                        local barBottom = CreateFrame("StatusBar", nil, auraButton)
                        barBottom:SetPoint("BOTTOMLEFT", 10, 10); barBottom:SetPoint("BOTTOMRIGHT", -10, 10); barBottom:SetHeight(20)
                        barBottom:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                        barBottom:SetStatusBarColor(0.3,0.8,1)
                        local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }
                        local okBarTop, errBarTop = pcall(auraButton.SetDurationBar, auraButton, barTop, durOpts)
                        local okBarBottom, errBarBottom = pcall(auraButton.SetDurationBar, auraButton, barBottom, durOpts)
                        if not okBarTop then P(string.format("|cffff4444SetDurationBar(barTop) #%d a echoue -- err=%s|r", idx, tostring(errBarTop))) end
                        if not okBarBottom then P(string.format("|cffff4444SetDurationBar(barBottom) #%d a echoue -- err=%s|r", idx, tostring(errBarBottom))) end
                    end)
                    P(string.format("initializeFrame #%d : ok=%s%s", slotCounter, tostring(okInit), okInit and "" or (" err=" .. tostring(errInit))))
                end,
            })
        end)
        P(string.format("AddAuraGroup (maxFrameCount=8) : ok=%s%s", tostring(okAdd), okAdd and "" or (" err=" .. tostring(errAdd))))

        -- FLOW LAYOUT REEL : meme fix que Circle Bars -- laisser Blizzard
        -- positionner via SetFlowLayout* au lieu d'un SetPoint manuel qui
        -- entrait en conflit avec le flow (le champ "layout" ci-dessus force
        -- son activation).
        local okA, errA = pcall(testMultiContainer.SetFlowLayoutAnchorPoint, testMultiContainer, "TOP")
        local okX, errX = pcall(testMultiContainer.SetFlowLayoutAxis, testMultiContainer, 1)
        local okG, errG = pcall(testMultiContainer.SetFlowLayoutGrowthDirection, testMultiContainer, 1, -1)
        local okM, errM = pcall(testMultiContainer.SetFlowLayoutMaximumLineSize, testMultiContainer, 900)
        P(string.format("SetFlowLayout* : anchor=%s axis=%s growth=%s maxline=%s",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
        P("Conteneur cree AU CENTRE DE L'ECRAN (700x700, cadre TOOLTIP) -- jusqu'a 3 pastilles de couleur numerotees #1/#2/#3, positionnees par Blizzard (flow vertical), CHACUNE avec 2 barres (blanche + bleue) comme Circle Bars.")
    else
        local includeSpellIDs = {}
        for _, sid in ipairs(spellIDs) do includeSpellIDs[sid] = true end
        local ok, err = pcall(testMultiContainer.SetAuraGroupCandidateFilters, testMultiContainer, testMultiGroupKey, { includeSpellIDs = includeSpellIDs })
        P(string.format("SetAuraGroupCandidateFilters({%s}) : ok=%s%s", table.concat(spellIDs, ","), tostring(ok), ok and "" or (" err=" .. tostring(err))))
    end

    if testMultiContainer.UpdateAllAuras then
        local okUpd, errUpd = pcall(testMultiContainer.UpdateAllAuras, testMultiContainer)
        P(string.format("UpdateAllAuras : ok=%s%s", tostring(okUpd), okUpd and "" or (" err=" .. tostring(errUpd))))
    end

    P("=> Active les 2+ sorts UN PAR UN au centre de l'ecran : chacun fait-il apparaitre une NOUVELLE pastille numerotee (#1 puis #2...), ou est-ce que TOUT disparait des que le 2e devient actif ?")
end

------------------------------------------------------------------------
-- TEST ISOLE : /aishdebug testpercolor <spellID1> <spellID2>
--
-- Question : peut-on colorer barre/glow PAR SORT avec le systeme natif ?
-- Aujourd'hui NON -- chaque destination utilise UN SEUL AddAuraGroup
-- partage, avec un pool de boutons REUTILISES dynamiquement (le meme
-- bouton physique peut afficher le Sort A maintenant puis le Sort B dans
-- 5 secondes) -- le style est pose UNE FOIS a la creation du pool
-- (initializeFrame), jamais retouche ensuite (retoucher un widget deja lie
-- a une vraie aura casse les bindings, confirme en jeu plus tot dans cette
-- session).
--
-- Piste a valider : UN AddAuraGroup DEDIE PAR SORT (maxFrameCount=1,
-- candidateFilters={includeSpellIDs={UN SEUL spellID}}) au lieu d'un
-- groupe partage -- chaque bouton serait alors fixe pour un sort donne,
-- son style pourrait etre lu une fois depuis la config PAR SORT
-- (discoveredSpells[key][spellID].color, comme l'ancien pipeline Laverage).
-- Inconnues a lever : plusieurs AddAuraGroup sur le MEME conteneur
-- coexistent-ils proprement ? Partagent-ils le meme flow layout sans se
-- superposer (meme SetFlowLayout* appele une seule fois sur le conteneur,
-- comme testmulti) ?
------------------------------------------------------------------------
local testPerSpellContainer
local testPerSpellGroupsAdded = {}

function ns.DebugTestPerSpellGroup(spellIDs)
    local P = function(s) print("|cff33aaff[TestPerSpell]|r " .. s) end
    if not spellIDs or #spellIDs < 2 then
        P("usage : /aishdebug testpercolor <spellID1> <spellID2> [spellID3...] -- au moins 2 sorts DIFFERENTS que tu peux activer en meme temps")
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        P("|cffff4444refuse en combat (creation AuraContainer interdite en combat)|r")
        return
    end

    if not testPerSpellContainer then
        local okCreate, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not okCreate or not result then
            P("|cffff4444echec CreateFrame AuraContainer : " .. tostring(result) .. "|r")
            return
        end
        testPerSpellContainer = result
        testPerSpellContainer:SetSize(700, 700)
        testPerSpellContainer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        testPerSpellContainer:SetFrameStrata("TOOLTIP")

        local okEnable, errEnable = pcall(testPerSpellContainer.SetEnabled, testPerSpellContainer, true)
        local okUnit, errUnit = pcall(testPerSpellContainer.SetUnit, testPerSpellContainer, "player")
        testPerSpellContainer:Show()
        P(string.format("SetEnabled : ok=%s%s | SetUnit(player) : ok=%s%s",
            tostring(okEnable), okEnable and "" or (" err=" .. tostring(errEnable)),
            tostring(okUnit), okUnit and "" or (" err=" .. tostring(errUnit))))

        -- Flow layout pose UNE SEULE FOIS sur le conteneur (partage par
        -- TOUS les groupes qui seront ajoutes dessus) -- exactement comme
        -- testmulti, mais ici on va tester si PLUSIEURS AddAuraGroup
        -- distincts peuvent cohabiter dans ce meme flow.
        local okA, errA = pcall(testPerSpellContainer.SetFlowLayoutAnchorPoint, testPerSpellContainer, "TOP")
        local okX, errX = pcall(testPerSpellContainer.SetFlowLayoutAxis, testPerSpellContainer, 1)
        local okG, errG = pcall(testPerSpellContainer.SetFlowLayoutGrowthDirection, testPerSpellContainer, 1, -1)
        local okM, errM = pcall(testPerSpellContainer.SetFlowLayoutMaximumLineSize, testPerSpellContainer, 900)
        P(string.format("SetFlowLayout* (conteneur, une seule fois) : anchor=%s axis=%s growth=%s maxline=%s",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    -- Couleurs FIXES PAR SORT (pas par index de slot de pool comme
    -- testmulti) -- c'est exactement ce qu'on valide : un lien permanent
    -- spellID -> style, pas un style partage/recycle par tout le pool.
    local COLORS = { {1,0.2,0.2}, {0.2,1,0.2}, {0.2,0.5,1}, {1,1,0.2} }

    for idx, sid in ipairs(spellIDs) do
        if not testPerSpellGroupsAdded[sid] then
            local groupKey = "aishTestPerSpell_" .. tostring(sid)
            local col = COLORS[idx] or {1, 1, 1}
            local okAdd, errAdd = pcall(function()
                testPerSpellContainer:AddAuraGroup(groupKey, "HELPFUL", {
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = { [sid] = true } },
                    layout = { elementSpacing = 10, lineSpacing = 10, elementWidth = 150, elementHeight = 150, layoutIndex = 1 },
                    initializeFrame = function(auraButton)
                        if not (auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()) then
                            P(string.format("|cffff4444initializeFrame (sort %d) : CanBeAccessedInContext=false, abandon|r", sid))
                            return
                        end
                        local okInit, errInit = pcall(function()
                            auraButton:SetSize(150, 150)
                            local bg = auraButton:CreateTexture(nil, "BACKGROUND")
                            bg:SetAllPoints(); bg:SetColorTexture(col[1], col[2], col[3], 0.5)
                            local label = auraButton:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
                            label:SetPoint("CENTER"); label:SetText(tostring(sid))
                            local bar = CreateFrame("StatusBar", nil, auraButton)
                            bar:SetPoint("BOTTOMLEFT", 10, 10); bar:SetPoint("BOTTOMRIGHT", -10, 10); bar:SetHeight(20)
                            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
                            bar:SetStatusBarColor(col[1], col[2], col[3])
                            local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }
                            local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                            if not okBar then P(string.format("|cffff4444SetDurationBar (sort %d) a echoue -- err=%s|r", sid, tostring(errBar))) end
                        end)
                        P(string.format("initializeFrame (sort %d, groupe dedie) : ok=%s%s", sid, tostring(okInit), okInit and "" or (" err=" .. tostring(errInit))))
                    end,
                })
            end)
            P(string.format("AddAuraGroup DEDIE (spellID=%d, maxFrameCount=1, couleur fixe {%.1f,%.1f,%.1f}) : ok=%s%s",
                sid, col[1], col[2], col[3], tostring(okAdd), okAdd and "" or (" err=" .. tostring(errAdd))))
            testPerSpellGroupsAdded[sid] = true
        end
    end

    if testPerSpellContainer.UpdateAllAuras then
        local okUpd, errUpd = pcall(testPerSpellContainer.UpdateAllAuras, testPerSpellContainer)
        P(string.format("UpdateAllAuras : ok=%s%s", tostring(okUpd), okUpd and "" or (" err=" .. tostring(errUpd))))
    end

    P("=> Active chaque sort UN PAR UN puis EN MEME TEMPS : chacun doit apparaitre dans SA PROPRE couleur fixe (celle de son groupe dedie), meme quand plusieurs sont actifs simultanement. Si tout disparait, se melange, ou qu'un seul groupe reste visible, plusieurs AddAuraGroup sur un meme conteneur/flow ne cohabitent pas proprement.")
end

------------------------------------------------------------------------
-- COULEUR/GLOW PAR SORT -- helpers PARTAGES par les 3
-- destinations icone+barre (Icons/Free Bars/Icon List -- pas Circle Bars,
-- qui a son propre CBApplySpellColor avec support degrade, cf. plus bas).
-- Declares ICI (avant TOUTE section qui les utilise, y compris "icons"
-- juste en dessous) : ce sont des `local function`, invisibles depuis du
-- code ecrit plus haut dans le fichier en Lua (portee lexicale) meme si ce
-- code s'execute plus tard a l'exécution -- doivent donc precéder la
-- premiere section appelante dans le FICHIER, pas juste dans le temps.
------------------------------------------------------------------------

-- Couleur de barre PAR SORT : meme priorite que l'ancien ns.ApplyBarColor
-- (moins l'etape degrade, specifique a Circle Bars) :
--   1) couleur uniforme explicite du render (cfg.barColorR)
--   2) ns.db.useSpellColors + si.color (couleur par sort, "Auras a tracker")
--   3) repli ns.barColor
local function SpellBarColorRGB(cfg, si)
    if cfg.barColorR ~= nil then
        return cfg.barColorR, cfg.barColorG or ns.barColor[2], cfg.barColorB or ns.barColor[3]
    end
    if ns.db and ns.db.useSpellColors and si and si.color then
        return si.color[1], si.color[2], si.color[3]
    end
    return ns.barColor[1], ns.barColor[2], ns.barColor[3]
end

-- Glow PAR SORT : l'override uniforme du render (glowOverrideIdx>1, deja
-- existant dans le GUI) reste PRIORITAIRE sur tout -- sinon on retombe sur
-- le glow propre au sort (si.glow+si.glowIdx>1, "Auras a tracker"), sinon
-- aucun glow. Remplace l'ancien comportement qui affichait un glow
-- UNIFORME (idx=2 par defaut) pour TOUS les sorts des que glowEnabled
-- n'etait pas explicitement false, independamment du reglage par sort --
-- desormais fidele a l'ancien pipeline Lua (ApplyAura: hasGlow =
-- aura.spellGlow and glIdx and glIdx > 1).
local function ApplySpellGlow(glowAnchor, cfg, si, w, h)
    if not (glowAnchor and ns.ShowGlow and cfg.glowEnabled ~= false) then return end
    -- Override render : "Auras a tracker" reste la SEULE source de verite
    -- pour le glow -- desactive via `false and` (jamais supprime) pour
    -- qu'une valeur deja stockee en DB (glowOverrideIdx) ne force plus rien
    -- silencieusement, meme sans passer par le GUI (cf. Render.lua).
    if false and cfg.glowOverrideIdx and cfg.glowOverrideIdx > 1 then
        local color = cfg.glowOverrideR ~= nil
            and { cfg.glowOverrideR, cfg.glowOverrideG or 0.5, cfg.glowOverrideB or 0.5 }
            or nil
        pcall(ns.ShowGlow, glowAnchor, cfg.glowOverrideIdx, color, cfg.glowOverrideAlpha, cfg.glowOverrideScale, w, h)
    elseif si and si.glow and si.glowIdx and si.glowIdx > 1 then
        -- Meme chaine de repli que l'apercu du picker (Tactics.lua
        -- RefreshGlowPreview: "info.glowColor or info.color or ns.barColor")
        -- -- sans le repli sur si.color, un sort dont le glow est active mais
        -- dont la couleur de glow n'a jamais ete touchee manuellement (cas
        -- courant : on s'attend a ce que le glow reprenne la couleur deja
        -- choisie pour la barre) retombait directement sur ns.barColor
        -- (couleur de classe generique), ignorant la couleur par sort
        -- configuree.
        local color = si.glowColor or si.color
        pcall(ns.ShowGlow, glowAnchor, si.glowIdx, color, si.glowAlpha, si.glowScale, w, h)
    end
end

-- TEXTE DE DUREE PERSONNALISE -- style + repositionne le texte de
-- countdown NATIF (Blizzard) d'un widget
-- Cooldown, cf. ns._StyleCountdownFS (Debuffs.lua) pour la technique complete
-- (jamais de lecture de valeur secrete -- on ne retouche que les proprietes
-- visuelles du FontString natif, jamais la VALEUR, remplie cote C++).
-- relFrame : l'icone pour icons/Free Bars/Liste d'icones, le conteneur de
-- barre (auraButton) pour Circle Bars (freebars, pas d'icone).
local function ApplyNativeCountdownStyle(cd, cfg, relFrame)
    if not (cd and ns._StyleCountdownFS) then return end
    local pos = cfg.timerPos or "CENTER"
    pcall(ns._StyleCountdownFS, cd, cfg.timerFont or ns.Media.font, cfg.timerSize or 12,
        cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
        pos, relFrame, pos, cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
end

-- ANIMATION D'ENTREE DU GLOW ("Proc: White Short" etc) --
-- ns.PlayProcStart (Debuffs.lua) est un flourish JOUE UNE FOIS quand une
-- aura passe d'inactive a active (distinct du glow en boucle continue
-- ci-dessus, cfg.procGlowIdx/glowColor(ou color)/procGlowScale, memes
-- reglages "Auras a tracker" que le glow).
--
-- PIEGE : `auraButton:HookScript("OnShow", ...)` echoue avec "Cannot assign
-- script handler for 'onshow' (blocked by secret aspects)" -- comme beaucoup
-- d'operations sur un widget natif une fois lie a une aura secrete,
-- assigner un script handler est bloque. Sans pcall, cette erreur remonte a
-- travers le pcall englobant d'initializeFrame et fait echouer TOUTE la
-- creation du bouton pour ce sort (icone/glow/barres deja crees avec succes
-- jetes silencieusement).
--
-- REPLI : jouer le flourish UNE SEULE FOIS, en meme temps que le glow,
-- directement dans initializeFrame -- qui n'est de toute facon appelee
-- qu'UNE SEULE FOIS par bouton pour toute la session (pool maxFrameCount=1).
-- Limitation acceptee : ne rejoue pas a chaque reapparition future du buff
-- (contrairement a l'ancien pipeline qui le detectait a chaque scan) --
-- mais c'est le seul declenchement possible avec ce systeme, faute d'un
-- evenement observable non bloque.
-- Pools de boutons natifs des 3 destinations avec icone/glow (icons/Free
-- Bars/Icon List) -- forward-declares ici (normalement peuplees/re-remplies
-- plus bas dans ce fichier, section par destination) pour etre visibles par
-- ProcGlowTick ci-dessous, defini AVANT ces sections. Circle Bars (freebars,
-- pas d'icone) exclue : pas de glow possible sur cette destination.
local iconsFlowButtons, freeBarsFlowButtons, iconListFlowButtons = {}, {}, {}

-- Etat de presence par spellID (partage avec le ticker de retrigger
-- ci-dessous) : seede ici (a la creation du bouton) pour eviter un double
-- flourish si le ticker tombe juste apres sur son tout premier tick avec
-- l'aura deja active.
local _procGlowWasPresent = {}

local function PlayProcStartOnce(glowAnchor, si, spellID)
    if not (ns.PlayProcStart and glowAnchor and si and si.procGlowIdx and si.procGlowIdx > 1) then return end
    local color = si.glowColor or si.color
    pcall(ns.PlayProcStart, glowAnchor, si.procGlowIdx, color, si.procGlowScale)
    if spellID then _procGlowWasPresent[spellID] = true end
end

-- RETRIGGER DU FLOURISH A CHAQUE (RE)APPARITION DE L'AURA : PlayProcStartOnce
-- ci-dessus ne joue le flourish QU'A LA CREATION du bouton (initializeFrame,
-- appele une seule fois par bouton pour toute la session, cf. commentaire
-- au-dessus) -- jamais aux reapparitions suivantes du buff/proc, faute d'un
-- evenement OnShow exploitable : `auraButton:HookScript("OnShow", ...)` est
-- bloque ("blocked by secret aspects") des qu'un widget natif est lie a une
-- aura secrete, meme sur un enfant (glowAnchor).
--
-- SOLUTION : ticker leger et totalement DECOUPLE du widget natif -- suit la
-- presence de chaque spellID via ns.IsCDMAuraSwipePresent (CDMHooks.lua,
-- event-driven, jamais de lecture de valeur secrete -- deja utilise ailleurs
-- cette session pour ce meme genre de detection de transition 0->1, ex.
-- StartSecResPop dans ResourceCircle.lua). Sur une transition false->true,
-- rejoue le flourish sur TOUS les boutons dedies a ce spellID, dans TOUTES
-- les destinations qui le trackent simultanement (icons/Free Bars/Icon
-- List -- Circle Bars exclue, pas d'icone/glow sur cette destination).
local function ProcGlowScanPool(pool, spellID, si)
    for _, btn in ipairs(pool) do
        if btn._aishSpellID == spellID then
            pcall(PlayProcStartOnce, btn._aishGlowAnchor or btn, si, spellID)
        end
    end
end

local function ProcGlowTick()
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells or not ns.IsCDMAuraSwipePresent then return end
    for spellID, si in pairs(spells) do
        if si.procGlowIdx and si.procGlowIdx > 1 then
            local present = ns.IsCDMAuraSwipePresent(spellID)
            if present and not _procGlowWasPresent[spellID] then
                ProcGlowScanPool(iconsFlowButtons, spellID, si)
                ProcGlowScanPool(freeBarsFlowButtons, spellID, si)
                ProcGlowScanPool(iconListFlowButtons, spellID, si)
            end
            _procGlowWasPresent[spellID] = present
        end
    end
end
C_Timer.NewTicker(0.2, ProcGlowTick)

-- SPARK NATIF : contrairement au glow (widget separe qu'on pilote
-- nous-memes), le spark doit suivre le bord MOBILE d'une StatusBar dont le
-- remplissage est entierement pilote par Blizzard en interne (via
-- SetDurationBar, valeur secrete) -- aucune lecture Lua possible de "ou en
-- est le remplissage actuellement".
--
-- SOLUTION : ancrer le CENTRE de la texture du spark sur le bord
-- (LEFT/RIGHT) de bar:GetStatusBarTexture() -- LA TEXTURE DE REMPLISSAGE
-- ELLE-MEME, pas la StatusBar -- UNE SEULE FOIS, jamais dans un OnUpdate.
-- Le systeme d'ancrage de l'UI reevalue cet ancrage a CHAQUE FRAME contre
-- l'etendue LIVE de la region ciblee (redimensionnee cote C++ par Blizzard,
-- meme pour une valeur secrete) : le spark suit donc le remplissage sans
-- qu'aucune valeur ne transite par notre code Lua. C'est la meme recette
-- que le template CDM natif de Blizzard (Pip=UI-HUD-CoolDownManager-Bar-Pip,
-- ancre une fois dans OnLoad).
--
-- tipEdge ("LEFT" ou "RIGHT") : le cote OU SE TROUVE le bord mobile de
-- CETTE barre precise -- oppose au cote d'origine du remplissage, donc
-- determine par le SetReverseFill() de CETTE barre (reverse=true => bord
-- mobile a GAUCHE, reverse=false => bord mobile a DROITE). A fournir par
-- l'appelant, qui connait deja ce reglage pour chaque barre creee.
--
-- matchBarRGB ({r,g,b}, optionnel) : couleur DEJA RESOLUE de la barre
-- elle-meme (per-spell/gradient/etc, calculee par l'appelant via
-- CBApplySpellColor/SpellBarColorRGB) -- utilisee si cfg.sparkSameAsBar
-- est actif ("Meme couleur que la barre", menu Etincelle), prioritaire sur
-- sparkColorR/G/B.
-- Couleur/gradient du spark, factorisee car reappliquee a la fois a la
-- creation (MakeNativeBarSpark) et au refresh (ApplyIconsFlowButtonStyle) --
-- la texture du spark n'est JAMAIS liee a une donnee secrete (contrairement
-- a la StatusBar qu'il habille), donc la retoucher a chaque refresh est
-- toujours sans risque, meme apres SetDurationBar sur la barre parente.
local function ApplyNativeBarSparkColor(s, cfg, matchBarRGB)
    local sameAsBar = cfg.sparkSameAsBar and matchBarRGB
    local r, g, b = ns.sparkColor[1], ns.sparkColor[2], ns.sparkColor[3]
    local userOverride = (not sameAsBar) and cfg.sparkColorR ~= nil
    if sameAsBar then r, g, b = matchBarRGB[1], matchBarRGB[2], matchBarRGB[3]
    elseif userOverride then r, g, b = cfg.sparkColorR, cfg.sparkColorG or 0.5, cfg.sparkColorB or 0.5 end
    pcall(function() s:SetDesaturated((sameAsBar or userOverride or cfg.sparkGradient) and true or false) end)
    if cfg.sparkGradient then
        s:SetVertexColor(1, 1, 1, cfg.sparkAlpha or 0.9)
        pcall(function()
            s:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(cfg.sparkGradR2 or r*0.2, cfg.sparkGradG2 or g*0.2, cfg.sparkGradB2 or b*0.2, 1))
        end)
    else
        s:SetVertexColor(r, g, b, cfg.sparkAlpha or 0.9)
    end
end

local function MakeNativeBarSpark(bar, cfg, tipEdge, matchBarRGB)
    if not cfg.sparkEnabled then return nil end
    local s = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    local st = cfg.sparkTexture
    if st and st:find("^atlas:") then
        pcall(function() s:SetAtlas(st:sub(7)) end)
    elseif st and st ~= "" then
        pcall(function() s:SetTexture(ns.ResolveBarTexFromKey(st)) end)
    else
        s:SetTexture(ns.Media.sparkTex)
    end
    s:SetSize(cfg.sparkW or 17, cfg.sparkH or 6)
    s:SetBlendMode("ADD")
    ApplyNativeBarSparkColor(s, cfg, matchBarRGB)
    local okAnchor = pcall(function()
        local fillTex = bar:GetStatusBarTexture()
        s:ClearAllPoints()
        s:SetPoint("CENTER", fillTex, tipEdge, 0, cfg.sparkOffY or 0)
    end)
    return okAnchor and s or nil
end

------------------------------------------------------------------------
-- GRILLE NATIVE "FLOW" POUR LA DESTINATION "icons" (Procs.lua)
--
-- Remplace un ancien systeme a DEUX rendus paralleles (Procs.lua manuel +
-- filet de secours ici) qui se superposaient de facon persistante (deux
-- compteurs de position independants). SetDurationCooldown fonctionne aussi
-- pour des auras sans duree lisible autrement -- il n'y a donc plus aucune
-- raison de garder un rendu Procs.lua distinct pour cette destination.
--
-- PRINCIPE : UN SEUL AddAuraGroup, partage par TOUS les sorts de la
-- destination "icons", avec le layout FLOW natif Blizzard
-- (SetFlowLayoutAnchorPoint/GrowthDirection/MaximumLineSize -- meme API que
-- CooldownManager). Blizzard anime lui-meme le compactage (icones qui
-- glissent quand un sort apparait/disparait) cote C++ -- structurellement
-- le SEUL moyen d'obtenir ce comportement, puisque Lua ne peut pas observer
-- quels boutons fixes sont actifs pour les compacter a la main
-- (HookScript/lecture bloques sur un AuraButton secret).
--
-- LIMITATION ACCEPTEE : un AddAuraGroup reutilise ses boutons entre
-- differents sorts au fil du temps -- il n'existe aucun setter beni
-- "SetGlow" que Blizzard rafraichirait pour nous comme
-- SetIcon/SetDurationCooldown/SetApplicationCount. Le glow ne peut donc pas
-- etre personnalise PAR SORT : un seul style (cfg.glowOverrideIdx/
-- R/G/B/Scale/Alpha, deja existant comme reglage "override") s'applique de
-- facon uniforme, statique, des qu'une icone est affichee.
------------------------------------------------------------------------
local iconsFlowContainer
local iconsFlowGroupAdded = false
iconsFlowButtons = {}   -- liste des auraButton natifs deja crees (pour re-appliquer un style plus tard) -- forward-declaree plus haut (ProcGlowTick)
-- [spellID] = true des qu'un AddAuraGroup DEDIE a ete cree pour ce sort
-- (couleur de barre + glow par sort, meme mecanique que les 3 autres
-- destinations). Chaque auraButton memorise aussi son propre spellID
-- (auraButton._aishSpellID) pour qu'ApplyIconsFlowButtonStyle (rappelee a
-- chaque refresh GUI, contrairement aux 3 autres destinations) puisse
-- retrouver sa config par-sort a chaque passage, pas seulement a la
-- creation.
local iconsPerSpellGroups = {}

-- Print de secours : n'affiche que les echecs reels (creation ratee, API
-- rejetee, etc.) -- pas de trace de fonctionnement normal, pour ne pas
-- polluer le chat a chaque /reload. Diagnostic complet a la demande via
-- /aishdebug iconsflow (cf. ns.DebugDumpIconsFlow).
local function DBG(s) print("|cff33aaff[IconsFlow]|r " .. tostring(s)) end

-- Retourne le conteneur natif de la destination "icons" (peut etre nil s'il
-- n'a jamais ete cree). Utilise par Animation.lua (ns.UpdateRenderFade) pour
-- rediriger le fade combat/hors-combat sur le VRAI conteneur affiche a
-- l'ecran -- ns.renderFrames.icons.container pointe vers l'ancien conteneur
-- manuel de Procs.lua (Inst:Init), definitivement cache (alpha=0), donc plus
-- jamais le bon cadre a fader.
function ns.GetIconsNativeContainer()
    return iconsFlowContainer
end

local function EnsureIconsFlowContainer()
    if iconsFlowContainer then return iconsFlowContainer end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        DBG(string.format("|cffff4444EnsureIconsFlowContainer: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    iconsFlowContainer = result
    iconsFlowContainer:SetSize(8, 8)  -- redimensionne par le layout flow lui-meme, valeur de securite seulement
    local okEn, errEn = pcall(iconsFlowContainer.SetEnabled, iconsFlowContainer, true)
    local okUn, errUn = pcall(iconsFlowContainer.SetUnit, iconsFlowContainer, "player")
    if not okEn or not okUn then
        DBG(string.format("|cffff4444SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    iconsFlowContainer:Show()

    -- DEPLACEMENT : Alt+clic gauche, meme pattern que tous les autres
    -- renders (cf. Procs.lua avant sa reecriture, Debuffs.lua, Cooldowns.lua,
    -- Buffs.lua). Le conteneur AuraContainer LUI-MEME n'est jamais
    -- "forbidden" (seuls les
    -- AuraButton enfants le deviennent quand une aura secrete leur est
    -- assignee) -- SetPoint/StartMoving dessus restent surs en toutes
    -- circonstances. Ancrage PAR BORD selon growth (cf.
    -- RepositionIconsNativeGrid) -- necessite donc la meme compensation par
    -- direction de croissance que Circle Bars/Free Bars/Icon List (cf.
    -- OnMouseUp ci-dessous).
    iconsFlowContainer:SetMovable(true)
    iconsFlowContainer:SetClampedToScreen(true)
    if _addon.EnableMouseOnlyOnAlt then _addon.EnableMouseOnlyOnAlt(iconsFlowContainer) end
    iconsFlowContainer:SetPropagateMouseClicks(true)
    local dragLbl = iconsFlowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragLbl:SetPoint("BOTTOM", iconsFlowContainer, "TOP", 0, 4)
    dragLbl:SetText("|cffffcc00" .. (_addon.L and _addon.L["AURASFEAT_ALT_DRAG_HINT"] or "") .. "|r")
    dragLbl:Hide()
    iconsFlowContainer:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            s:SetPropagateMouseClicks(false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    iconsFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Une fois ce conteneur natif lie (via un de ses boutons enfants) a
        -- une VRAIE aura secrete, GetCenter()/GetSize() sur LE CONTENEUR
        -- LUI-MEME peuvent aussi renvoyer des valeurs secretes -- taint qui
        -- se propage au-dela des boutons individuels ("attempt to perform
        -- arithmetic on ... a secret number value" au relachement du drag
        -- Alt+clic). pcall autour de TOUT le calcul : si secret, impossible
        -- de toute facon de sauvegarder la position cette fois (aucun moyen
        -- de lire une valeur secrete, meme pour la stocker telle quelle) --
        -- abandon silencieux plutot que crash.
        if cx and cy and ns.db and ns.db.icons then
            pcall(function()
                local w, h = s:GetSize()
                local gr = ns.db.icons.growth or "LEFT"
                local saveX = cx * sc - sx
                local saveY = cy * sc - sy
                -- Compense le decalage centre->bord selon l'ancre utilisee au
                -- restore (SetPoint TOP/BOTTOM/LEFT/RIGHT, cf.
                -- RepositionIconsNativeGrid) -- meme calcul que Circle Bars/
                -- Free Bars/Icon List.
                if gr == "DOWN" then saveY = saveY + h * sc / 2
                elseif gr == "UP" then saveY = saveY - h * sc / 2
                elseif gr == "LEFT" then saveX = saveX + w * sc / 2
                elseif gr == "RIGHT" then saveX = saveX - w * sc / 2
                end
                ns.db.icons.x = saveX
                ns.db.icons.y = saveY
            end)
        end
    end)
    return iconsFlowContainer
end

-- Applique le style COURANT (ns.db.icons) a un auraButton DEJA cree, sans
-- jamais recreer ses enfants (icon/border/cd/stackFS) -- uniquement retoucher
-- leurs proprietes. Appelee UNE FOIS a la creation (dans initializeFrame) ET
-- a chaque changement de reglage GUI via ns.RefreshIconsNativeGridStyle : un
-- auraButton HORS combat/HORS contexte secret reste normalement accessible en
-- MODIFICATION (seule la CREATION doit rester unique dans initializeFrame) --
-- necessaire puisqu'un AddAuraGroup ne rappelle initializeFrame qu'une seule
-- fois par bouton cree, jamais a chaque changement de reglage (sinon les
-- sliders/checkbox restent sans effet : taille icone, glow, swipe, texte de
-- duree ne seraient appliques qu'a la toute premiere creation du pool).
local function ApplyIconsFlowButtonStyle(auraButton)
    local liveCfg = ns.db and ns.db.icons or ns.Defaults.icons
    local okCheck, canAccess = pcall(function()
        return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
    end)
    if not (okCheck and canAccess) then return end
    local okStyle, errStyle = pcall(function()
        local liveIw, liveIh = liveCfg.iconW or 26, liveCfg.iconH or 26
        auraButton:SetSize(liveIw, liveIh)

        if auraButton._aishStackFS then
            local st = auraButton._aishStackFS
            ns.ApplyFont(st, liveCfg.stackFont or ns.Media.font, liveCfg.stackSize or 10, "OUTLINE")
            st:ClearAllPoints()
            st:SetPoint(liveCfg.stackPos or "BOTTOMRIGHT", auraButton, liveCfg.stackPos or "BOTTOMRIGHT", liveCfg.stackOffX or 0, liveCfg.stackOffY or 0)
            st:SetTextColor(liveCfg.stackColorR or 1, liveCfg.stackColorG or 1, liveCfg.stackColorB or 1)
        end

        if auraButton._aishCD then
            local cd = auraButton._aishCD
            -- Swipe cooldown : checkbox "Swipe cooldown" (section DIMENSIONS),
            -- meme reglage/comportement que les autres destinations.
            cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
            cd:SetDrawEdge(liveCfg.swipeEnabled == true)
            -- Texte de duree : delegue au compteur NATIF du widget Cooldown
            -- (le meme mecanisme que sur les boutons d'action Blizzard),
            -- JAMAIS calcule par nous -- seul moyen d'afficher un chiffre de
            -- duree ici sans jamais lire la valeur secrete d'expiration
            -- (GetAuraDuration/instID CDM sont bloques meme hors combat sur
            -- ce type de bouton). Blizzard remplit ce texte cote C++ des que
            -- SetDurationCooldown est lie -- police/taille/couleur/position
            -- restent personnalisables via ApplyNativeCountdownStyle, qui ne
            -- retouche que les proprietes visuelles du FontString natif,
            -- jamais la valeur.
            cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
            if liveCfg.timerIconEnabled then
                ApplyNativeCountdownStyle(cd, liveCfg, auraButton)
            end
        end

        -- Config PAR SORT : chaque bouton est dedie a
        -- UN SEUL spellID (auraButton._aishSpellID, pose a la creation) --
        -- permet une couleur de barre/glow fixes par sort, cf. helpers
        -- SpellBarColorRGB/ApplySpellGlow (section Free Bars).
        local liveSpells = ns.GetSpecSpells()
        local liveSi = auraButton._aishSpellID and liveSpells and liveSpells[auraButton._aishSpellID]

        if auraButton._aishDurBar then
            local bar = auraButton._aishDurBar
            -- JAMAIS SetStatusBarTexture/SetReverseFill ici : bar est deja liee
            -- a une donnee de duree secrete via SetDurationBar (creation), et
            -- retoucher texture/reverse-fill APRES ce lien a deja ete identifie
            -- comme a risque ailleurs dans ce fichier (cf. commentaire
            -- ApplyCircleBarsButtonStyle/RefreshCircleBarsNativeGridStyle) --
            -- le SetStatusBarTexture ici faisait echouer tout le bloc pcall
            -- englobant, empechant silencieusement
            -- le glow (ApplySpellGlow, plus bas) de jamais se reappliquer aux
            -- boutons deja crees. SetStatusBarColor seul reste confirme sans
            -- risque (meme source).
            local cR, cG, cB = SpellBarColorRGB(liveCfg, liveSi)
            bar:SetStatusBarColor(cR, cG, cB)
            -- SPARK : texture propre a l'addon, jamais secrete -- toujours
            -- sur de la retoucher (couleur/sparkSameAsBar/gradient) a chaque
            -- refresh, contrairement a la barre elle-meme.
            if auraButton._aishSpark then
                pcall(ApplyNativeBarSparkColor, auraButton._aishSpark, liveCfg, {cR, cG, cB})
            end
        end

        if ns.HideGlow then pcall(ns.HideGlow, auraButton) end
        -- liveIw/liveIh explicites : ib:GetSize() sur CE bouton peut
        -- renvoyer une valeur SECRETE une fois lie a une vraie aura
        -- (confirme en jeu -- "attempt to perform arithmetic on ... a
        -- secret number value"), meme si le bouton reste accessible par
        -- ailleurs. On connait deja la taille (SetSize juste au-dessus).
        local okGlow, errGlow = pcall(ApplySpellGlow, auraButton, liveCfg, liveSi, liveIw, liveIh)
        if not okGlow then
            DBG(string.format("|cffff4444ApplyIconsFlowButtonStyle: ApplySpellGlow a echoue -- err=%s|r", tostring(errGlow)))
        end
    end)
    if not okStyle then
        DBG(string.format("|cffff4444ApplyIconsFlowButtonStyle: bloc principal a echoue -- err=%s|r", tostring(errStyle)))
    end
end

-- A appeler depuis le GUI (Render.lua) a chaque changement de reglage qui
-- affecte l'apparence des icones de la destination "icons" -- taille, glow,
-- swipe, texte de duree, stacks. Hors combat uniquement par prudence (les
-- boutons deviennent "forbidden", meme en lecture, des qu'une aura secrete
-- leur est assignee) ; en pratique le GUI n'est de toute facon jamais ouvert
-- en combat.
function ns.RefreshIconsNativeGridStyle()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, btn in ipairs(iconsFlowButtons) do
        ApplyIconsFlowButtonStyle(btn)
    end
end

-- Traduit ns.db.icons.growth (LEFT/RIGHT/UP/DOWN, meme semantique que
-- l'ancien systeme Procs.lua) vers les parametres natifs SetFlowLayout*.
-- LEFT/RIGHT (horizontal) valides en jeu ; UP/DOWN (vertical) moins teste
-- sur ce type de conteneur.
local function GrowthToFlowParams(growth)
    if growth == "RIGHT" then return "TOPLEFT", 1, -1, true
    elseif growth == "UP" then return "BOTTOMLEFT", 1, 1, false
    elseif growth == "DOWN" then return "TOPLEFT", 1, -1, false
    else return "TOPRIGHT", -1, -1, true end -- LEFT (defaut)
end

-- SetFlowLayoutAxis n'accepte PAS la chaine "HORIZONTAL"/"VERTICAL" (rejetee
-- en jeu avec "layoutAxis must be valid") -- la forme numerique fonctionne
-- pour l'axe horizontal (0). L'axe vertical (1)
-- suit la meme numerotation mais n'a jamais ete exerce en jeu (aucun preset
-- "icons" par defaut ne l'utilise) -- on garde donc les autres formes
-- candidates en repli silencieux au cas ou, sans spammer le chat tant que la
-- premiere (confirmee) fonctionne.
local axisWorkingIdx = nil
local AXIS_CANDIDATES = {
    { label = "number 0/1", get = function(isH) return isH and 0 or 1 end },
    { label = "Enum.FlowLayoutAxis.Horizontal/.Vertical", get = function(isH)
        return Enum and Enum.FlowLayoutAxis and (isH and Enum.FlowLayoutAxis.Horizontal or Enum.FlowLayoutAxis.Vertical)
    end },
    { label = "string Horizontal/Vertical", get = function(isH) return isH and "Horizontal" or "Vertical" end },
    { label = "string HORIZONTAL/VERTICAL", get = function(isH) return isH and "HORIZONTAL" or "VERTICAL" end },
    { label = "number 1/2", get = function(isH) return isH and 1 or 2 end },
}
local function SetFlowAxisSmart(c, isH)
    if axisWorkingIdx then
        local cand = AXIS_CANDIDATES[axisWorkingIdx]
        local v = cand.get(isH)
        if v ~= nil then
            local ok, err = pcall(c.SetFlowLayoutAxis, c, v)
            if ok then return true end
            DBG(string.format("|cffff4444SetFlowAxisSmart: la valeur precedemment valide [%s] echoue maintenant -- err=%s|r", cand.label, tostring(err)))
        end
    end
    local attempts = {}
    for i, cand in ipairs(AXIS_CANDIDATES) do
        local v = cand.get(isH)
        if v ~= nil then
            local ok, err = pcall(c.SetFlowLayoutAxis, c, v)
            if ok then axisWorkingIdx = i; return true end
            attempts[#attempts + 1] = string.format("[%s]=%s (%s)", cand.label, tostring(v), tostring(err))
        end
    end
    DBG(string.format("|cffff4444SetFlowAxisSmart: toutes les formes candidates ont echoue -- %s|r", table.concat(attempts, " | ")))
    return false
end

------------------------------------------------------------------------
-- MASQUAGE CONTEXTUEL : ne jamais montrer les 4 destinations natives quand
-- le personnage est en vehicule/taxi/combat de mascotte/cutscene -- ces
-- contextes sont exactement ceux ou le bug "buff hors whitelist affiche
-- partout" a ete rapporte. Verifications directes via API Blizzard
-- propres (jamais de valeur secrete, jamais besoin d'introspecter les
-- boutons AddAuraGroup) :
--   - UnitHasVehicleUI("player") : vehicule avec barre d'action dediee.
--   - UnitOnTaxi("player") : trajet en taxi/vol automatique.
--   - C_PetBattles.IsInBattle() : combat de mascotte.
--   - CinematicFrame/MovieFrame IsShown() : cutscene en cours.
--   - _addon.skyridingActive : deja maintenu par Modules/Skyriding.lua (son
--     propre HUD detecte deja precisement le decollage/atterrissage skyriding
--     -- pas besoin de redevine un signal, on reutilise le sien). ATTENTION :
--     ce fichier utilise "ns" pour _addon (namespace racine), PAS _addon.Auras
--     comme ici -- d'ou la reference explicite a _addon, pas ns.
-- Chaque appel est protege par pcall (une API absente/restreinte ne doit
-- jamais faire planter tout le reste de la fonction).
------------------------------------------------------------------------
function ns.IsAuraHidingContext()
    local ok, hide = pcall(function()
        if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
        if UnitOnTaxi and UnitOnTaxi("player") then return true end
        if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return true end
        if CinematicFrame and CinematicFrame:IsShown() then return true end
        if MovieFrame and MovieFrame:IsShown() then return true end
        if _addon.skyridingActive then return true end
        return false
    end)
    return ok and hide or false
end

-- Repositionne/redimensionne le CONTENEUR (jamais forbidden, simple Frame
-- AishCore) selon ns.db.icons -- x/y/growth/iconW/iconH/rowGap, memes
-- reglages que l'ancien rendu Procs.lua. Le flow layout natif s'occupe
-- ensuite seul du placement/compactage/animation de chaque icone a
-- l'interieur. A appeler a chaque rebuild de whitelist ET a chaque
-- changement de reglage de grille (meme nom qu'avant : aucun appelant a
-- changer, cf. Whitelist.lua).
function ns.RepositionIconsNativeGrid()
    local c = EnsureIconsFlowContainer()
    if not c then return end
    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    local visible = (cfg.iconsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    c:ClearAllPoints()
    -- ANCRAGE PAR BORD (evite que les icones "bougent des 2 cotes" quand le
    -- nombre d'icones actives change) -- le conteneur se redimensionne
    -- dynamiquement pour coller au flow (cf.
    -- EnsureIconsFlowContainer: SetSize(8,8), juste une valeur de securite).
    -- Un ancrage CENTER (utilise jusqu'ici, seul cas de toute la migration
    -- a NE PAS suivre le pattern des 3 autres destinations) fait donc
    -- deriver LES DEUX bords a chaque redimensionnement -- le bord cense
    -- rester fixe (celui du cote de l'ancre du flow, cf.
    -- GrowthToFlowParams) doit etre le point d'ancrage du CONTENEUR
    -- lui-meme, exactement comme Circle Bars/Free Bars/Icon List.
    local growth0 = cfg.growth or "LEFT"
    local x0, y0 = cfg.x or -199, cfg.y or -247
    if growth0 == "UP" then c:SetPoint("BOTTOM", UIParent, "CENTER", x0, y0)
    elseif growth0 == "DOWN" then c:SetPoint("TOP", UIParent, "CENTER", x0, y0)
    elseif growth0 == "RIGHT" then c:SetPoint("LEFT", UIParent, "CENTER", x0, y0)
    else c:SetPoint("RIGHT", UIParent, "CENTER", x0, y0) end -- LEFT (defaut)

    -- IMPORTANT : tout ce qui suit doit rester individuellement pcall-protege
    -- (chaque appel separement, pas la fonction entiere globalement) -- un
    -- appel non protege ICI (avant les SetFlowLayout*) ferait planter
    -- (silencieusement, avale par le pcall de l'appelant dans Whitelist.lua)
    -- TOUTE la suite de la fonction -- anchor/axis/growth/maxline ne
    -- seraient plus jamais appliques => plus une seule icone ne s'afficherait,
    -- sans le moindre message d'erreur. D'ou la regle stricte : le
    -- positionnement/layout FLOW passe TOUJOURS en premier et ne doit jamais
    -- pouvoir etre court-circuite par un ajout ulterieur (fade, style, etc.).
    local growth = cfg.growth or "LEFT"
    local anchorPoint, hDir, vDir, isH = GrowthToFlowParams(growth)
    local ok1, err1 = pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
    local ok2, err2 = SetFlowAxisSmart(c, isH), "voir DBG au-dessus"
    local ok3, err3 = pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)

    local iw, ih = cfg.iconW or 26, cfg.iconH or 26
    local rg = cfg.rowGap or 2
    local order = ns.slotOrderByDest and ns.slotOrderByDest.icons
    local count = math.max(order and #order or 0, 1)
    local itemSize = isH and iw or ih
    -- Ligne unique volontairement surdimensionnee : jamais de retour a la
    -- ligne, tout tient sur un seul axe de flow (comme l'ancien rendu).
    local ok4, err4 = pcall(c.SetFlowLayoutMaximumLineSize, c, (itemSize + rg) * count + rg)

    if not (ok1 and ok2 and ok3 and ok4) then
        DBG(string.format("|cffff4444RepositionIconsNativeGrid: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            ok1 and "ok" or tostring(err1), ok2 and "ok" or tostring(err2), ok3 and "ok" or tostring(err3), ok4 and "ok" or tostring(err4)))
    end

    -- Alpha : SetAlpha direct, jamais via un appel qui pourrait lui-meme
    -- echouer (cf. avertissement ci-dessus) -- pcall par prudence quand meme,
    -- pour ne jamais laisser une erreur ici avaler le reste de la fonction.
    pcall(function()
        if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
            if ns.UpdateRenderFade then ns.UpdateRenderFade("icons") else c:SetAlpha(1) end
        else
            c:SetAlpha(0)
        end
    end)

    -- Ré-applique le style (taille/glow/swipe/texte de duree/stacks) a tous
    -- les boutons deja crees -- cf. ApplyIconsFlowButtonStyle : un AddAuraGroup
    -- ne rappelle initializeFrame qu'une fois par bouton, jamais a chaque
    -- changement de reglage. pcall par la meme prudence.
    pcall(function() if ns.RefreshIconsNativeGridStyle then ns.RefreshIconsNativeGridStyle() end end)
end

-- Cree (une seule fois) ou met a jour le groupe natif partage par tous les
-- sorts de la destination "icons" (info.destinations.icons == true).
-- Appelee depuis Whitelist.lua/BuildWhitelist (meme nom qu'avant : aucun
-- appelant a changer). Cible UNIQUEMENT les auras du joueur -- pas
-- d'equivalent combat-safe pour la cible.
function ns.EnsureIconsNativeGrid()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureIconsFlowContainer()
    if not c then
        DBG("|cffff4444EnsureIconsNativeGrid: pas de conteneur|r")
        return
    end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.icons
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    local iw, ih = cfg.iconW or 26, cfg.iconH or 26
    local rg = cfg.rowGap or 2
    -- Reserve la place de la barre de duree (si activee) dans le slot du
    -- flow layout -- necessaire meme en croissance horizontale (ou les icones
    -- ne s'empilent jamais verticalement entre elles, donc pas de risque de
    -- chevauchement) pour que le conteneur (auto-dimensionne par le flow) ne
    -- rogne pas la barre qui depasse sous/sur l'icone.
    local elementH = ih
    if cfg.showBarUnderIcon then elementH = ih + (cfg.rowGap or 2) + (cfg.barUnderHeight or 3) end
    local spells = ns.GetSpecSpells()

    -- Pas de cap ici (contrairement a Circle Bars/Free Bars/Icon List) :
    -- "icons" n'a jamais eu de reglage utilisateur "maxBars" -- tous les
    -- sorts traques obtiennent chacun leur groupe dedie.
    local currentSet = {}
    for _, spellID in ipairs(order) do
        currentSet[spellID] = true
        if not iconsPerSpellGroups[spellID] then
            local groupKey = "aishIconsFlow_" .. tostring(spellID)
            local okAdd, errAdd = pcall(function()
                c:AddAuraGroup(groupKey, "HELPFUL", {
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = { [spellID] = true } },
                    initializeFrame = function(auraButton)
                        local okCheck, canAccess = pcall(function()
                            return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
                        end)
                        if not (okCheck and canAccess) then return end
                        local okBuild, errBuild = pcall(function()
                            local liveCfgAtCreate = ns.db and ns.db.icons or ns.Defaults.icons
                            auraButton._aishSpellID = spellID
                            local icon = auraButton:CreateTexture(nil, "ARTWORK")
                            icon:SetAllPoints(auraButton)
                            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                            -- NE PAS remplir icon:SetTexture() nous-memes :
                            -- Blizzard remplit l'image en interne des que
                            -- SetIcon() est associe a un vrai candidat (confirme
                            -- en jeu -- forcer nous-memes n'apportait rien).
                            auraButton:SetIcon(icon)

                            -- Bordure sous l'icone (BACKGROUND < ARTWORK, jamais
                            -- au-dessus) : OVERLAY est toujours au-dessus
                            -- d'ARTWORK quel que soit le sous-niveau, un
                            -- remplissage opaque en OVERLAY masquait totalement
                            -- l'icone (bug "carres noirs" confirme en jeu).
                            local border = auraButton:CreateTexture(nil, "BACKGROUND")
                            border:SetPoint("TOPLEFT", auraButton, "TOPLEFT", -1, 1)
                            border:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", 1, -1)
                            border:SetColorTexture(14/255, 14/255, 14/255, 1)

                            local cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                            cd:SetAllPoints(auraButton)
                            cd:SetReverse(true)
                            auraButton:SetDurationCooldown(cd)
                            auraButton._aishCD = cd

                            local stackFS = auraButton:CreateFontString(nil, "OVERLAY", nil, 7)
                            -- Le font DOIT etre pose ICI, avant SetApplicationCount --
                            -- Blizzard touche le texte immediatement/synchroniquement
                            -- des l'appel (SetText en interne pour l'etat initial),
                            -- et un FontString cree avec un 3e argument nil n'a AUCUN
                            -- font tant qu'on ne lui en assigne pas un explicitement.
                            ns.ApplyFont(stackFS, liveCfgAtCreate.stackFont or ns.Media.font, liveCfgAtCreate.stackSize or 10, "OUTLINE")
                            stackFS:SetJustifyH("RIGHT")
                            auraButton:SetApplicationCount(stackFS, {})
                            auraButton._aishStackFS = stackFS

                            -- BARRE DE DUREE -- couleur PAR SORT.
                            if liveCfgAtCreate.showBarUnderIcon then
                                local barH = liveCfgAtCreate.barUnderHeight or 3
                                local gp = liveCfgAtCreate.rowGap or 2
                                -- durBar est un ENFANT DIRECT de auraButton (pas de
                                -- Frame "barWrap" intercalee) -- Free Bars/Circle
                                -- Bars/Liste d'icones parentent toutes leur(s)
                                -- StatusBar directement sur auraButton, et leur spark
                                -- s'affiche correctement de cette maniere. Le fond
                                -- (durBg) est un enfant direct de durBar lui-meme.
                                local durBar = CreateFrame("StatusBar", nil, auraButton)
                                durBar:SetSize(liveCfgAtCreate.iconW or 26, barH)
                                if (liveCfgAtCreate.barPosition or "BOTTOM") == "TOP" then
                                    durBar:SetPoint("BOTTOM", auraButton, "TOP", 0, gp)
                                else
                                    durBar:SetPoint("TOP", auraButton, "BOTTOM", 0, -gp)
                                end
                                durBar:SetStatusBarTexture(ns.ResolveBarTexFromKey(liveCfgAtCreate.texture))
                                durBar:SetReverseFill(liveCfgAtCreate.barReverseFill == true)
                                local cR, cG, cB = SpellBarColorRGB(liveCfgAtCreate, spells and spells[spellID])
                                durBar:SetStatusBarColor(cR, cG, cB)
                                local durBg = durBar:CreateTexture(nil, "BACKGROUND")
                                durBg:SetAllPoints()
                                durBg:SetColorTexture(liveCfgAtCreate.barBgR or 0, liveCfgAtCreate.barBgG or 0, liveCfgAtCreate.barBgB or 0, liveCfgAtCreate.barBgAlpha or 0)
                                -- direction=RemainingTime : sans cette option,
                                -- la barre se REMPLIT au lieu de se VIDER.
                                local okDurBar, errDurBar = pcall(auraButton.SetDurationBar, auraButton, durBar,
                                    { direction = Enum.StatusBarTimerDirection.RemainingTime })
                                if not okDurBar then
                                    DBG(string.format("|cffff4444initializeFrame (sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errDurBar)))
                                end
                                auraButton._aishDurBar = durBar
                                -- SPARK : bord mobile oppose au cote d'origine
                                -- du remplissage (cf. MakeNativeBarSpark).
                                auraButton._aishSpark = MakeNativeBarSpark(durBar, liveCfgAtCreate,
                                    (liveCfgAtCreate.barReverseFill == true) and "LEFT" or "RIGHT", {cR, cG, cB})
                            end

                            iconsFlowButtons[#iconsFlowButtons + 1] = auraButton
                        end)
                        if not okBuild then
                            DBG(string.format("|cffff4444initializeFrame (sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                        end
                        -- Taille/glow/swipe/texte de duree/stacks : appliques via
                        -- la meme fonction que ns.RefreshIconsNativeGridStyle, cf.
                        -- commentaire au-dessus de ApplyIconsFlowButtonStyle.
                        ApplyIconsFlowButtonStyle(auraButton)
                        -- Animation d'entree du glow ("Proc: White Short"
                        -- etc) : jouee UNE SEULE FOIS ici (pas dans
                        -- ApplyIconsFlowButtonStyle, rappelee a chaque
                        -- refresh GUI -- rejouerait le flourish a chaque
                        -- reglage change).
                        do
                            local spells = ns.GetSpecSpells()
                            PlayProcStartOnce(auraButton, spells and spells[spellID], spellID)
                        end
                    end,
                    layout = {
                        elementSpacing = rg,
                        lineSpacing = rg,
                        elementWidth = iw,
                        elementHeight = elementH,
                        layoutIndex = 1,
                    },
                })
            end)
            if not okAdd then
                DBG(string.format("|cffff4444AddAuraGroup DEDIE (sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
            end
            iconsPerSpellGroups[spellID] = true
            iconsFlowGroupAdded = true
            if c.UpdateAllAuras then
                local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                if not okUpd then DBG(string.format("|cffff4444UpdateAllAuras (sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
            end
        else
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis
            -- re-trace depuis (spec change, recap, whitelist re-evaluee en
            -- transition de zone/cutscene) -- sinon il resterait bloque sur
            -- le filtre "poison" pose ci-dessous.
            pcall(c.SetAuraGroupCandidateFilters, c, "aishIconsFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques depuis la derniere fois : leur groupe dedie existe
    -- toujours (impossible a supprimer) donc on le neutralise avec un filtre
    -- SUR UN SPELLID BIDON (jamais {} -- un candidateFilters.includeSpellIDs
    -- VIDE n'est PAS "aucun sort autorise" mais "aucune restriction" cote
    -- Blizzard -- le groupe se met alors a matcher TOUTES les auras du
    -- joueur, whitelist ou pas). C'etait la cause des
    -- "auras aleatoires hors whitelist" observees en cutscene : la moindre
    -- re-evaluation de whitelist qui de-traque transitoirement un sort
    -- ouvrait ce groupe en grand jusqu'au prochain /reload.
    for spellID in pairs(iconsPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishIconsFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

-- DUMP complet de l'etat actuel : /aishdebug iconsflow. Rejoue aussi les
-- appels SetFlowLayout* pour voir immediatement s'ils echouent.
function ns.DebugDumpIconsFlow()
    DBG("=== DUMP etat icons flow ===")
    DBG(string.format("InCombatLockdown=%s", tostring(InCombatLockdown and InCombatLockdown())))
    DBG(string.format("conteneur existe=%s", tostring(iconsFlowContainer ~= nil)))
    if iconsFlowContainer then
        local c = iconsFlowContainer
        local okPt, p1, p2, p3, p4, p5 = pcall(c.GetPoint, c, 1)
        DBG(string.format("IsShown=%s Alpha=%.2f Taille=%.0fx%.0f Point=%s",
            tostring(c:IsShown()), c:GetAlpha(), c:GetWidth(), c:GetHeight(),
            okPt and string.format("%s,%s,%s,%s,%s", tostring(p1), tostring(p2), tostring(p3), tostring(p4), tostring(p5)) or "?"))

        local cfg = ns.db and ns.db.icons or ns.Defaults.icons
        local growth = cfg.growth or "LEFT"
        local anchorPoint, hDir, vDir, isH = GrowthToFlowParams(growth)
        local ok1, err1 = pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
        local ok2, err2 = SetFlowAxisSmart(c, isH), "voir essais ci-dessus si echec"
        local ok3, err3 = pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
        DBG(string.format("Rejeu SetFlowLayout* : anchor=%s axis=%s growth=%s",
            ok1 and "ok" or ("|cffff4444ERR:"..tostring(err1).."|r"),
            ok2 and "ok" or ("|cffff4444ERR:"..tostring(err2).."|r"),
            ok3 and "ok" or ("|cffff4444ERR:"..tostring(err3).."|r")))
    end
    DBG(string.format("groupAdded=%s boutonsTraces=%d", tostring(iconsFlowGroupAdded), #iconsFlowButtons))
    local order = ns.slotOrderByDest and ns.slotOrderByDest.icons
    DBG(string.format("ns.slotOrderByDest.icons: %d sort(s)", order and #order or 0))
    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    DBG(string.format("useNativeCDM=%s iconsEnabled=%s x=%s y=%s growth=%s",
        tostring(ns.db and ns.db.useNativeCDM), tostring(cfg.iconsEnabled), tostring(cfg.x), tostring(cfg.y), tostring(cfg.growth)))
    for i, btn in ipairs(iconsFlowButtons) do
        local okCA, canAccess = pcall(function() return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext() end)
        local okShown, shown = pcall(function() return btn:IsShown() end)
        DBG(string.format("  bouton #%d (sort %s) : CanBeAccessedInContext ok=%s val=%s | IsShown ok=%s val=%s",
            i, tostring(btn._aishSpellID), tostring(okCA), tostring(canAccess), tostring(okShown), tostring(shown)))
        -- DIAGNOSTIC SPARK : etat complet du spark de ce bouton --
        -- existe-t-il, est-il visible/dimensionne, ou l'ancrage a-t-il echoue
        -- silencieusement a la creation (MakeNativeBarSpark renvoie nil dans
        -- ce cas -- _aishSpark resterait nil).
        if not btn._aishDurBar then
            DBG("      durBar=absent (showBarUnderIcon desactive ou bloc initializeFrame en echec)")
        else
            local okFT, fillTex = pcall(btn._aishDurBar.GetStatusBarTexture, btn._aishDurBar)
            DBG(string.format("      durBar: IsShown=%s GetStatusBarTexture ok=%s val=%s",
                tostring(select(2, pcall(btn._aishDurBar.IsShown, btn._aishDurBar))), tostring(okFT), tostring(fillTex)))
        end
        if not btn._aishSpark then
            DBG("      _aishSpark=nil (MakeNativeBarSpark a echoue OU sparkEnabled=false au moment de la creation)")
        else
            local s = btn._aishSpark
            local okSh, shownS = pcall(s.IsShown, s)
            local okA, alphaS = pcall(s.GetAlpha, s)
            local okSz, wS, hS = pcall(s.GetSize, s)
            local okPt, p1, p2, p3, p4, p5 = pcall(s.GetPoint, s, 1)
            local okVC, r, g, b, a = pcall(s.GetVertexColor, s)
            DBG(string.format("      _aishSpark existe : IsShown=%s Alpha=%s Taille=%sx%s VertexColor=%s,%s,%s,%s Point=%s",
                okSh and tostring(shownS) or "ERR", okA and tostring(alphaS) or "ERR",
                okSz and tostring(wS) or "ERR", okSz and tostring(hS) or "ERR",
                okVC and tostring(r) or "ERR", okVC and tostring(g) or "?", okVC and tostring(b) or "?", okVC and tostring(a) or "?",
                okPt and string.format("%s,%s,%s,%s,%s", tostring(p1), tostring(p2), tostring(p3), tostring(p4), tostring(p5)) or "AUCUN (anchor jamais pose)"))
        end
    end
    DBG("=== fin dump ===")
end

------------------------------------------------------------------------
-- Print de secours dedie a cette section : prefixe different de DBG (icons)
-- pour eviter la confusion -- un dump Circle Bars s'affichait etiquete
-- "[IconsFlow]" faute de prefixe propre.
local function CBDBG(s) print("|cff33aaff[CircleBarsFlow]|r " .. tostring(s)) end

------------------------------------------------------------------------
-- GRILLE NATIVE POUR "CIRCLE BARS" (Buffs.lua, cle interne freebars --
-- ATTENTION : l'onglet GUI "Circle Bars" est backe par Buffs.lua/freebars,
-- PAS par Cooldowns.lua/circlebars, qui est en fait l'onglet GUI
-- "Free Bars") -- meme methodologie que "icons".
--
-- Contrairement a "icons", ce rendu N'A PAS d'icone -- deux StatusBar
-- miroir (gauche/droite) par ligne, montrant la MEME duree. Confirme en jeu
-- via /aishdebug testbar avant d'ecrire ce code :
--   - SetDurationBar fonctionne SANS icone/cooldown/stacks du tout.
--   - SetDurationBar peut etre appele DEUX FOIS sur le meme auraButton (une
--     fois par StatusBar) -- les DEUX se remplissent en meme temps, avec
--     les memes vraies donnees.
--   - AUCUN appel SetFlowLayout* necessaire (positionnement 100% manuel via
--     SetPoint fixe dans initializeFrame), MAIS le champ "layout" doit quand
--     meme etre FOURNI a AddAuraGroup (meme jamais exploite pour du flow) --
--     confirme en jeu que son absence totale empechait plusieurs candidats
--     simultanes de s'afficher a la fois (2 buffs actifs = un seul set de
--     barres visible, malgre 8 boutons dispos dans le pool). SetEnabled/
--     SetUnit/Show doivent rester AVANT AddAuraGroup (cf. section "icons").
--   - Le foreground grandit avec le temps ecoule par defaut -- RESOLU (pas
--     une limitation) via `SetDurationBar(bar, {direction =
--     Enum.StatusBarTimerDirection.RemainingTime})`. SetReverseFill seul ne
--     fait que l'effet miroir gauche/droite, ne suffisait pas.
--
-- COMPACTAGE : contrairement au systeme Lua precedent (Buffs.lua:Update,
-- ordre = auras[i] apres tri priorite), un AddAuraGroup partage ne permet
-- QUE le compactage NATIF -- Blizzard decide en interne quel membre du pool
-- affiche quel sort, aucun ordre de priorite garanti. Comportement accepte :
-- l'ordre d'affichage n'a jamais eu de priorite garantie, c'est la premiere
-- barre arrivee qui prend la premiere rangee. Chaque bouton du pool
-- recoit une position ECRAN fixe (rang N, alternance haut/bas comme
-- Buffs.lua:CreateBuffRow) UNE SEULE FOIS a sa creation -- Blizzard decide
-- ensuite librement quel sort occupe quel bouton/rang au fil du temps.
------------------------------------------------------------------------
local circleBarsFlowContainer
local circleBarsFlowGroupAdded = false
local circleBarsFlowButtons = {}
local circleBarsSlotCounter = 0  -- attribue un rang fixe a chaque bouton du pool, une seule fois, a la creation
-- [spellID] = true des qu'un AddAuraGroup DEDIE a ete cree pour ce sort
-- ("couleur par sort") : remplace un ancien groupe UNIQUE partage par toute
-- la destination -- cf. commentaire complet sur
-- EnsureCircleBarsNativeGrid plus bas. Un groupe ne peut pas etre supprime
-- une fois cree (contrainte native), seulement vide via
-- SetAuraGroupCandidateFilters({includeSpellIDs={}}) si le sort est
-- decoche plus tard.
local circleBarsPerSpellGroups = {}

-- Colorisation de barre avec degrade (SetGradient sur StatusBarTexture) --
-- copie minimale de _SetBarGradient/_ResetBarGradient (Core/Init.lua,
-- locales a ce fichier) : pas exposees sur ns, plus simple de dupliquer ces
-- 2 lignes que d'exporter pour un seul appelant.
local function CBSetGradient(tex, r, g, b, gr, gg, gb)
    if tex.SetGradient then
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(gr, gg, gb, 1))
    end
end
local function CBResetGradient(tex)
    if tex.SetGradient then
        tex:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
    end
end

-- Applique la couleur/degrade d'une barre EN TENANT COMPTE du sort qui lui
-- est dedie -- meme priorite que l'ancien pipeline Lua (ns.ApplyBarColor,
-- Core/Init.lua) :
--   1) cfg.spellGradients[spellID] (menu "Couleur par sort", freebars
--      UNIQUEMENT) -- couleur fixe OU degrade, prioritaire sur tout.
--   2) cfg.barColorR explicite (couleur uniforme du render).
--   3) ns.db.useSpellColors + si.color (couleur generale par sort, stockee
--      sur l'entree decouverte -- meme source que les autres destinations).
--   4) repli ns.barColor.
-- Le degrade uniforme du render (cfg.gradientEnabled) ne s'applique QUE si
-- aucun override par sort n'est actif (meme court-circuit que l'original).
-- Appele UNE SEULE FOIS a la creation du bouton (initializeFrame) -- pas de
-- re-application par scan, le native se charge de tout le reste.
local function CBApplySpellColor(bar, cfg, spellID, si)
    local sg = cfg.spellGradients and cfg.spellGradients[spellID]
    if sg then
        local r1, g1, b1 = sg[1] or 1, sg[2] or 1, sg[3] or 1
        if sg[7] == true then
            local r2, g2, b2 = sg[4] or r1*0.3, sg[5] or g1*0.3, sg[6] or b1*0.3
            bar:SetStatusBarColor(1, 1, 1, 1)
            local tex = bar:GetStatusBarTexture()
            if tex then pcall(CBSetGradient, tex, r1, g1, b1, r2, g2, b2) end
        else
            local tex = bar:GetStatusBarTexture()
            if tex then pcall(CBResetGradient, tex) end
            bar:SetStatusBarColor(r1, g1, b1)
        end
        return r1, g1, b1
    end

    local r, g, b = ns.barColor[1], ns.barColor[2], ns.barColor[3]
    if cfg.barColorR ~= nil then r, g, b = cfg.barColorR, cfg.barColorG or g, cfg.barColorB or b
    elseif ns.db and ns.db.useSpellColors and si and si.color then
        r, g, b = si.color[1], si.color[2], si.color[3]
    end

    if cfg.gradientEnabled then
        local gr = cfg.gradientR2 or r*0.3
        local gg = cfg.gradientG2 or g*0.3
        local gb = cfg.gradientB2 or b*0.3
        bar:SetStatusBarColor(1, 1, 1, 1)
        local tex = bar:GetStatusBarTexture()
        if tex then pcall(CBSetGradient, tex, r, g, b, gr, gg, gb) end
    else
        local tex = bar:GetStatusBarTexture()
        if tex then pcall(CBResetGradient, tex) end
        bar:SetStatusBarColor(r, g, b)
    end
    return r, g, b
end

function ns.GetCircleBarsNativeContainer()
    return circleBarsFlowContainer
end

local function EnsureCircleBarsFlowContainer()
    if circleBarsFlowContainer then return circleBarsFlowContainer end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        CBDBG(string.format("|cffff4444EnsureCircleBarsFlowContainer: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    circleBarsFlowContainer = result

    -- POSITION/TAILLE REELLES ICI, AVANT tout le reste -- PAS un simple
    -- SetSize(8,8) provisoire retouche plus tard par
    -- RepositionCircleBarsNativeGrid. SetPoint/SetSize doivent TOUJOURS etre
    -- appeles AVANT AddAuraGroup et le premier UpdateAllAuras -- sinon le
    -- tout premier UpdateAllAuras s'execute sur un conteneur sans aucun
    -- ancrage, cause du bug "2 buffs actifs = tout disparait, retour a 1
    -- seul buff = reapparait".
    local cfg0 = ns.db and ns.db.freebars or ns.Defaults.freebars
    local maxBars0 = cfg0.maxBars or 8
    local bw0, bh0, gp0, rg0 = cfg0.barW or 45, cfg0.barH or 3, cfg0.gap or 50, cfg0.rowGap or 6
    circleBarsFlowContainer:SetSize(bw0 * 2 + gp0 * 2, maxBars0 * (bh0 + rg0))
    circleBarsFlowContainer:SetPoint("CENTER", UIParent, "CENTER", cfg0.x or 0, cfg0.y or -218)
    -- STRATA : l'ancien conteneur Buffs.lua etait explicitement en
    -- BACKGROUND (sous le reste de l'UI, sous le Resource Circle) -- sans ce
    -- reglage, un AuraContainer natif prend la strata par defaut (MEDIUM,
    -- au-dessus), ce qui entre en conflit visuel avec l'overlay du Resource
    -- Circle des que plusieurs rangees se chevauchent.
    circleBarsFlowContainer:SetFrameStrata("BACKGROUND")
    -- ORDRE CRITIQUE : SetEnabled/SetUnit/Show AVANT tout AddAuraGroup,
    -- jamais apres -- l'ordre inverse laisse les barres jamais alimentees.
    local okEn, errEn = pcall(circleBarsFlowContainer.SetEnabled, circleBarsFlowContainer, true)
    local okUn, errUn = pcall(circleBarsFlowContainer.SetUnit, circleBarsFlowContainer, "player")
    if not okEn or not okUn then
        CBDBG(string.format("|cffff4444EnsureCircleBarsFlowContainer: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    circleBarsFlowContainer:Show()

    -- DEPLACEMENT : Alt+clic gauche, meme pattern que partout ailleurs
    -- (remplace le drag de l'ancien conteneur Buffs.lua, desormais mort).
    circleBarsFlowContainer:SetMovable(true)
    circleBarsFlowContainer:SetClampedToScreen(true)
    if _addon.EnableMouseOnlyOnAlt then _addon.EnableMouseOnlyOnAlt(circleBarsFlowContainer) end
    circleBarsFlowContainer:SetPropagateMouseClicks(true)
    local dragLbl = circleBarsFlowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragLbl:SetPoint("BOTTOM", circleBarsFlowContainer, "TOP", 0, 4)
    dragLbl:SetText("|cffffcc00" .. (_addon.L and _addon.L["AURASFEAT_ALT_DRAG_HINT"] or "") .. "|r")
    dragLbl:Hide()
    circleBarsFlowContainer:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            s:SetPropagateMouseClicks(false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    circleBarsFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Cf. commentaire equivalent sur le conteneur "icons" -- GetCenter()
        -- peut renvoyer secret une fois ce conteneur lie a une vraie aura.
        -- pcall : abandon silencieux du placement plutot que planter.
        if cx and cy and ns.db and ns.db.freebars then
            pcall(function()
                ns.db.freebars.x = cx*sc - sx
                ns.db.freebars.y = cy*sc - sy
            end)
        end
    end)
    return circleBarsFlowContainer
end

-- Applique le style courant (taille/texture/couleur/fond) a une paire de
-- barres deja creee. Meme logique que ApplyIconsFlowButtonStyle : appelee
-- une fois a la creation ET a chaque changement de reglage GUI via
-- ns.RefreshCircleBarsNativeGridStyle. La POSITION VERTICALE de la ligne
-- (yOff, rang fixe) n'est PAS retouchee ici -- elle ne peut etre recalculee
-- qu'a la prochaine creation de pool (meme limitation acceptee que la
-- resize live imparfaite d'"icons").
local function ApplyCircleBarsButtonStyle(auraButton)
    local liveCfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local okCheck, canAccess = pcall(function()
        return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
    end)
    if not (okCheck and canAccess) then return end
    local okStyle, errStyle = pcall(function()
        local bw, bh, gp = liveCfg.barW or 45, liveCfg.barH or 3, liveCfg.gap or 50
        auraButton:SetSize(bw * 2 + gp * 2, bh)

        local tex = ns.ResolveBarTexFromKey(liveCfg.texture)
        local cR, cG, cB = liveCfg.barColorR or ns.barColor[1], liveCfg.barColorG or ns.barColor[2], liveCfg.barColorB or ns.barColor[3]
        local bgR = type(liveCfg.barBgR) == "number" and liveCfg.barBgR or 0
        local bgG = type(liveCfg.barBgG) == "number" and liveCfg.barBgG or 0
        local bgB = type(liveCfg.barBgB) == "number" and liveCfg.barBgB or 0
        local bgA = type(liveCfg.barBgAlpha) == "number" and liveCfg.barBgAlpha or 0

        if auraButton._aishBarL then
            local bar = auraButton._aishBarL
            bar:SetSize(bw, bh)
            bar:ClearAllPoints()
            bar:SetPoint("RIGHT", auraButton, "CENTER", -gp, 0)
            bar:SetStatusBarTexture(tex)
            bar:SetStatusBarColor(cR, cG, cB)
            if auraButton._aishBgL then auraButton._aishBgL:SetColorTexture(bgR, bgG, bgB, bgA) end
        end
        if auraButton._aishBarR then
            local bar = auraButton._aishBarR
            bar:SetSize(bw, bh)
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", auraButton, "CENTER", gp, 0)
            bar:SetStatusBarTexture(tex)
            bar:SetStatusBarColor(cR, cG, cB)
            if auraButton._aishBgR then auraButton._aishBgR:SetColorTexture(bgR, bgG, bgB, bgA) end
        end
    end)
    if not okStyle then
        CBDBG(string.format("|cffff4444ApplyCircleBarsButtonStyle: bloc principal a echoue -- err=%s|r", tostring(errStyle)))
    end
end

-- A appeler depuis le GUI (Render.lua) a chaque changement de reglage qui
-- affecte l'apparence de Circle Bars.
--
-- VOLONTAIREMENT PLUS ETROIT que ApplyCircleBarsButtonStyle ci-dessus :
-- retoucher une StatusBar liee via SetDurationBar est suspecte de casser
-- son binding, meme si la vraie cause du bug "2 buffs actifs = tout
-- disparait" etait en fait un SetPoint manuel entrant en conflit avec le
-- flow layout (cf. RepositionCircleBarsNativeGrid, deja corrige). Cette
-- fonction-ci ne touche QUE SetStatusBarColor/SetGradient (jamais
-- SetPoint/SetSize/SetStatusBarTexture) -- risque residuel minimal, mais a
-- surveiller specifiquement avec 2+ buffs actifs simultanement.
function ns.RefreshCircleBarsNativeGridStyle()
    if InCombatLockdown and InCombatLockdown() then return end
    local liveCfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local spells = ns.GetSpecSpells()
    for _, btn in ipairs(circleBarsFlowButtons) do
        local okCheck, canAccess = pcall(function()
            return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext()
        end)
        if okCheck and canAccess then
            local si = btn._aishSpellID and spells and spells[btn._aishSpellID]
            if btn._aishBarL then
                local okL, rL, gL, bL = pcall(CBApplySpellColor, btn._aishBarL, liveCfg, btn._aishSpellID, si)
                -- SPARK : texture propre a l'addon, jamais secrete --
                -- toujours sur de la retoucher, contrairement a la barre.
                if btn._aishSparkL and okL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {rL, gL, bL}) end
            end
            if btn._aishBarR then
                local okR, rR, gR, bR = pcall(CBApplySpellColor, btn._aishBarR, liveCfg, btn._aishSpellID, si)
                if btn._aishSparkR and okR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {rR, gR, bR}) end
            end
            -- TEXTE DE DUREE : widget Cooldown dedie (jamais de swipe/edge),
            -- texte natif -- jamais de risque a le restyler ici (pas la
            -- barre, pas de secret).
            if btn._aishTimerCD then
                pcall(btn._aishTimerCD.SetHideCountdownNumbers, btn._aishTimerCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishTimerCD, liveCfg, btn)
                end
            end
        end
    end
end

-- Repositionne le CONTENEUR (jamais forbidden) selon ns.db.freebars.x/y, et
-- rafraichit alpha (combat/hors-combat, cf. cfg.combatOnly) + style.
function ns.RepositionCircleBarsNativeGrid()
    local c = EnsureCircleBarsFlowContainer()
    if not c then return end
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars

    local maxBars = cfg.maxBars or 8
    local bw, bh, gp, rg = cfg.barW or 45, cfg.barH or 3, cfg.gap or 50, cfg.rowGap or 6
    local rowW = bw * 2 + gp * 2
    pcall(c.SetSize, c, rowW, maxBars * (bh + rg))

    c:ClearAllPoints()
    c:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or -218)

    -- FLOW LAYOUT REEL : contrairement a un premier essai (positionnement
    -- 100% manuel via SetPoint dans initializeFrame), Blizzard gere le
    -- placement, comme "icons" -- un SetPoint manuel entre en conflit avec
    -- le flow (rendu obligatoire des que le champ "layout" est fourni a
    -- AddAuraGroup) et fait s'ecraser 2 candidats simultanes sur la meme
    -- position. Axe VERTICAL (0=horizontal confirme fonctionner, 1=vertical
    -- par deduction/symetrie -- jamais isole teste), empile vers le BAS
    -- depuis le haut du conteneur -- ordre d'affichage non garanti.
    local okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, "TOP")
    local okX, errX = pcall(c.SetFlowLayoutAxis, c, 1)
    local okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, 1, -1)
    local okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, maxBars * (bh + rg) + rg)
    if not (okA and okX and okG and okM) then
        CBDBG(string.format("|cffff4444RepositionCircleBarsNativeGrid: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    -- freebars a un VRAI toggle utilisateur (contrairement a icons dont
    -- "iconsEnabled" n'existe pas en pratique) -- le respecter ici, comme
    -- useNativeCDM (skin natif Blizzard choisi a la place de ce rendu).
    local visible = (ns.db == nil or ns.db.freebarsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)

    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        pcall(function()
            if ns.UpdateRenderFade then ns.UpdateRenderFade("freebars") end
        end)
    else
        c:SetAlpha(0)
    end
    pcall(function() if ns.RefreshCircleBarsNativeGridStyle then ns.RefreshCircleBarsNativeGridStyle() end end)
end

-- Compteur de cap "par BUFF, pas par spellID" : une variation de tier d'un
-- buff multi-spellID (ex: Jet d'osselets Hors-la-loi, 4 spellID pour 1 seul
-- buff conceptuel via linkedSpellIDs, cf. Whitelist.lua) pouvait ne
-- s'afficher que sur certaines destinations et pas d'autres. Cause : la
-- boucle de creation de groupes dediee
-- coupait a `if i > maxBars then break end`, qui compte CHAQUE variante de
-- spellID separement -- si le sort "ancre" tombait pile a la limite du
-- cap, ses 3 variantes suivantes (meme priorite, triees juste apres dans
-- `order`, cf. tsort de Whitelist.lua) tombaient hors cap et n'obtenaient
-- jamais leur AddAuraGroup, meme si `dansWhitelist=true` pour elles (confirme
-- via /aishdebug spell). Toutes les variantes d'un meme buff partagent le
-- MEME objet `info` (linkedFallbackInfo reutilise l'ancre) -- on s'en sert
-- ici comme cle d'identite pour ne compter qu'UNE fois vers le cap tout un
-- groupe de variantes liees, quel que soit combien de spellID il comporte.
-- `wl` = ns.whitelistByDest[dest] (table spellID -> info) ; retourne true
-- si ce spellID doit encore etre traite (sous le cap OU variante deja
-- comptee), false s'il faut arreter la boucle (cap atteint, sort inedit).
local function AllowNextCapSlot(wl, spellID, maxBars, seenInfo, state)
    local info = wl and wl[spellID]
    if info and seenInfo[info] then
        return true -- variante d'un buff deja compte : jamais bloquee par le cap
    end
    if state.count >= maxBars then
        return false
    end
    state.count = state.count + 1
    if info then seenInfo[info] = true end
    return true
end

-- Cree (une seule fois par sort) UN AddAuraGroup DEDIE par spellID de la
-- destination "Circle Bars" (info.destinations.freebars == true), au lieu
-- d'un groupe UNIQUE partage par toute la destination. Appelee depuis
-- Whitelist.lua/BuildWhitelist. Joueur uniquement.
--
-- POURQUOI ("couleur par sort") : un groupe PARTAGE reutilise dynamiquement
-- le meme pool de boutons pour N'IMPORTE LEQUEL des sorts traques --
-- impossible de fixer une couleur/glow PAR SORT puisque le meme bouton
-- physique peut afficher le Sort A maintenant puis le Sort B dans 5
-- secondes, et retoucher un widget deja lie a une vraie aura casse les
-- bindings. Un groupe DEDIE (maxFrameCount=1, candidateFilters=
-- {includeSpellIDs={UN SEUL spellID}}) fixe DEFINITIVEMENT quel sort peut
-- occuper ce bouton -- son style peut alors etre lu UNE FOIS depuis la
-- config PROPRE a ce sort. Plusieurs AddAuraGroup cohabitent proprement sur
-- le meme conteneur/flow, chacun gardant sa couleur (cf.
-- /aishdebug testpercolor).
function ns.EnsureCircleBarsNativeGrid()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureCircleBarsFlowContainer()
    if not c then
        CBDBG("|cffff4444EnsureCircleBarsNativeGrid: pas de conteneur|r")
        return
    end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.freebars
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local maxBars = cfg.maxBars or 8
    local bw, bh, gp, rg = cfg.barW or 45, cfg.barH or 3, cfg.gap or 50, cfg.rowGap or 6
    local rowStep = bh + rg
    local spells = ns.GetSpecSpells()

    -- Cape a maxBars BUFFS (pas spellID, cf. AllowNextCapSlot) : evite un
    -- nombre de groupes non borne si l'utilisateur traque beaucoup de
    -- sorts pour cette destination -- meme intention que l'ancien
    -- maxFrameCount=maxBars (un cap sur le nombre de rangs simultanes),
    -- juste applique a la CREATION des groupes plutot qu'au partage d'un
    -- pool.
    local wl = ns.whitelistByDest and ns.whitelistByDest.freebars
    local seenInfo, capState = {}, { count = 0 }
    local currentSet = {}
    for i, spellID in ipairs(order) do
        if not AllowNextCapSlot(wl, spellID, maxBars, seenInfo, capState) then break end
        currentSet[spellID] = true
        if not circleBarsPerSpellGroups[spellID] then
            local groupKey = "aishCircleBarsFlow_" .. tostring(spellID)
            local si = spells and spells[spellID]
            local okAdd, errAdd = pcall(function()
                c:AddAuraGroup(groupKey, "HELPFUL", {
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = { [spellID] = true } },
                    -- Champ "layout" partage par TOUS les groupes de ce
                    -- conteneur (meme geometrie que l'ancien groupe unique)
                    -- -- necessaire pour activer plusieurs membres/groupes
                    -- simultanement, cf. lecon Icons/Circle Bars.
                    layout = {
                        elementSpacing = rowStep,
                        lineSpacing = rowStep,
                        elementWidth = bw * 2 + gp * 2,
                        elementHeight = bh,
                        layoutIndex = 1,
                    },
                    initializeFrame = function(auraButton)
                        local okCheck, canAccess = pcall(function()
                            return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
                        end)
                        if not (okCheck and canAccess) then return end
                        local okBuild, errBuild = pcall(function()
                            local liveCfg = ns.db and ns.db.freebars or ns.Defaults.freebars
                            local lbw, lbh, lgp = liveCfg.barW or 45, liveCfg.barH or 3, liveCfg.gap or 50
                            local liveSpells = ns.GetSpecSpells()
                            local liveSi = liveSpells and liveSpells[spellID]
                            auraButton._aishSpellID = spellID
                            circleBarsSlotCounter = circleBarsSlotCounter + 1
                            auraButton:SetSize(lbw * 2 + lgp * 2, lbh)

                            local tex = ns.ResolveBarTexFromKey(liveCfg.texture)
                            local bgR = liveCfg.barBgR or 0; local bgG = liveCfg.barBgG or 0
                            local bgB = liveCfg.barBgB or 0; local bgA = liveCfg.barBgAlpha or 0

                            -- Barre GAUCHE : grandit vers la gauche (ReverseFill).
                            local barL = CreateFrame("StatusBar", nil, auraButton)
                            barL:SetSize(lbw, lbh)
                            barL:SetPoint("RIGHT", auraButton, "CENTER", -lgp, 0)
                            barL:SetStatusBarTexture(tex)
                            barL:SetReverseFill(true)
                            local barLR, barLG, barLB = CBApplySpellColor(barL, liveCfg, spellID, liveSi)
                            local bgL = barL:CreateTexture(nil, "BACKGROUND")
                            bgL:SetAllPoints(); bgL:SetColorTexture(bgR, bgG, bgB, bgA)
                            auraButton._aishBarL = barL
                            auraButton._aishBgL = bgL

                            -- Barre DROITE : grandit vers la droite.
                            local barR = CreateFrame("StatusBar", nil, auraButton)
                            barR:SetSize(lbw, lbh)
                            barR:SetPoint("LEFT", auraButton, "CENTER", lgp, 0)
                            barR:SetStatusBarTexture(tex)
                            local barRR, barRG, barRB = CBApplySpellColor(barR, liveCfg, spellID, liveSi)
                            local bgR2 = barR:CreateTexture(nil, "BACKGROUND")
                            bgR2:SetAllPoints(); bgR2:SetColorTexture(bgR, bgG, bgB, bgA)
                            auraButton._aishBarR = barR
                            auraButton._aishBgR = bgR2

                            -- direction=RemainingTime : sans cette option, la
                            -- barre se REMPLIT au lieu de se VIDER (cf. lecon
                            -- session precedente).
                            local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }
                            local okBarL, errBarL = pcall(auraButton.SetDurationBar, auraButton, barL, durOpts)
                            local okBarR, errBarR = pcall(auraButton.SetDurationBar, auraButton, barR, durOpts)
                            if not okBarL then CBDBG(string.format("|cffff4444initializeFrame (Circle Bars, sort %d): SetDurationBar(barL) a echoue -- err=%s|r", spellID, tostring(errBarL))) end
                            if not okBarR then CBDBG(string.format("|cffff4444initializeFrame (Circle Bars, sort %d): SetDurationBar(barR) a echoue -- err=%s|r", spellID, tostring(errBarR))) end

                            -- SPARK : barL grandit vers la gauche (reverse=true)
                            -- -- son bord MOBILE est a GAUCHE. barR grandit
                            -- vers la droite -- bord mobile a DROITE.
                            auraButton._aishSparkL = MakeNativeBarSpark(barL, liveCfg, "LEFT", {barLR, barLG, barLB})
                            auraButton._aishSparkR = MakeNativeBarSpark(barR, liveCfg, "RIGHT", {barRR, barRG, barRB})

                            -- TEXTE DE DUREE : pas d'icone ici, donc pas de widget
                            -- Cooldown existant -- on en cree un DEDIE, purement
                            -- pour heberger le texte de countdown natif Blizzard
                            -- (jamais de swipe/edge visible). SetDurationCooldown
                            -- est un slot de liaison INDEPENDANT de SetDurationBar
                            -- (deja utilise 2x juste au-dessus, barL+barR) -- les 3
                            -- peuvent coexister sur le meme auraButton (meme
                            -- recette que icons, qui lie CD+bar simultanement).
                            -- Position relative au CONTENEUR DE BARRE (auraButton),
                            -- pas a une icone -- cf. ns._StyleCountdownFS.
                            -- SetAllPoints(auraButton) plutot qu'une taille fixe
                            -- 1x1 : meme convention que cd:SetAllPoints(icon) sur
                            -- les 3 autres destinations -- une taille degeneree
                            -- pourrait empecher Blizzard de creer/peupler
                            -- correctement le FontString interne du countdown.
                            local timerCD = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                            timerCD:SetAllPoints(auraButton)
                            timerCD:SetDrawSwipe(false); timerCD:SetDrawEdge(false); timerCD:SetDrawBling(false)
                            timerCD:EnableMouse(false)
                            local okTimerCD, errTimerCD = pcall(auraButton.SetDurationCooldown, auraButton, timerCD)
                            if not okTimerCD then
                                CBDBG(string.format("|cffff4444initializeFrame (Circle Bars, sort %d): SetDurationCooldown(timerCD) a echoue -- err=%s|r", spellID, tostring(errTimerCD)))
                            end
                            timerCD:SetHideCountdownNumbers(not liveCfg.timerIconEnabled)
                            auraButton._aishTimerCD = timerCD
                            if liveCfg.timerIconEnabled then
                                pcall(ApplyNativeCountdownStyle, timerCD, liveCfg, auraButton)
                            end

                            circleBarsFlowButtons[#circleBarsFlowButtons + 1] = auraButton
                        end)
                        if not okBuild then
                            CBDBG(string.format("|cffff4444initializeFrame (Circle Bars, sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                        end
                        -- PAS de re-style ici apres coup (meme lecon que
                        -- l'ancien groupe partage) -- tout se fait UNE FOIS.
                    end,
                })
            end)
            if not okAdd then
                CBDBG(string.format("|cffff4444AddAuraGroup DEDIE (Circle Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
            end
            circleBarsPerSpellGroups[spellID] = true
            circleBarsFlowGroupAdded = true
            if c.UpdateAllAuras then
                local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                if not okUpd then CBDBG(string.format("|cffff4444UpdateAllAuras (Circle Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
            end
        else
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis
            -- re-trace depuis (cf. commentaire equivalent Icons plus haut).
            pcall(c.SetAuraGroupCandidateFilters, c, "aishCircleBarsFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts DE-traques depuis la derniere fois (decoches dans "Auras a
    -- tracker" ou passes au-dela du cap maxBars) : leur groupe dedie existe
    -- toujours (impossible a supprimer) donc on le neutralise avec un
    -- spellID bidon (jamais {} -- un candidateFilters.includeSpellIDs VIDE
    -- signifie "aucune restriction" cote Blizzard, pas "rien n'est autorise"
    -- -- cf. commentaire equivalent Icons plus haut).
    for spellID in pairs(circleBarsPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishCircleBarsFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

-- DUMP complet de l'etat actuel : /aishdebug circlebarsflow.
-- Montre combien de boutons ont reellement ete crees dans le pool et a
-- quelle position chacun est fige, pour determiner si Blizzard cree bien un
-- bouton PAR buff simultane ou reutilise le meme.
function ns.DebugDumpCircleBarsFlow()
    CBDBG("=== DUMP etat Circle Bars flow ===")
    CBDBG(string.format("InCombatLockdown=%s", tostring(InCombatLockdown and InCombatLockdown())))
    CBDBG(string.format("conteneur existe=%s groupAdded=%s slotCounter=%d boutonsTraces=%d",
        tostring(circleBarsFlowContainer ~= nil), tostring(circleBarsFlowGroupAdded), circleBarsSlotCounter, #circleBarsFlowButtons))
    if circleBarsFlowContainer then
        local c = circleBarsFlowContainer
        CBDBG(string.format("IsShown=%s Alpha=%.2f Strata=%s", tostring(c:IsShown()), c:GetAlpha(), tostring(c:GetFrameStrata())))
    end
    local order = ns.slotOrderByDest and ns.slotOrderByDest.freebars
    CBDBG(string.format("ns.slotOrderByDest.freebars: %d sort(s)", order and #order or 0))
    for i, btn in ipairs(circleBarsFlowButtons) do
        local okCA, canAccess = pcall(function() return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext() end)
        local okPt, p1, p2, p3, p4, p5 = pcall(btn.GetPoint, btn, 1)
        CBDBG(string.format("  bouton #%d : CanBeAccessedInContext ok=%s val=%s | point=%s",
            i, tostring(okCA), tostring(canAccess),
            okPt and string.format("%s,%s,%s,%s,%s", tostring(p1), tostring(p2), tostring(p3), tostring(p4), tostring(p5)) or "?"))
    end
    CBDBG("=== fin dump ===")
end

------------------------------------------------------------------------
-- WATCHER : /aishdebug circlebarswatch -- diagnostic pour l'hypothese
-- "Blizzard ne re-scanne les candidats du groupe QUE quand on appelle
-- UpdateAllAuras explicitement, pas automatiquement des qu'une nouvelle
-- aura correspondante apparait" (symptome : un 2e buff qui apparait apres
-- le 1er ne s'affiche jamais tant que le 1er ne s'eteint pas). Force
-- UpdateAllAuras toutes les 0.5s pendant qu'il tourne et log tout
-- changement d'etat par bouton.
------------------------------------------------------------------------
local circleBarsWatchTicker
local circleBarsWatchLastState = {}

function ns.DebugCircleBarsWatchToggle()
    local P = function(s) print("|cff33aaff[CircleBarsWatch]|r " .. tostring(s)) end
    if circleBarsWatchTicker then
        circleBarsWatchTicker:Cancel()
        circleBarsWatchTicker = nil
        P("ARRETE.")
        return
    end
    if not circleBarsFlowContainer then
        P("|cffff4444pas de conteneur Circle Bars -- rien a surveiller (whitelist vide ou pas encore construite ?)|r")
        return
    end
    wipe(circleBarsWatchLastState)
    P(string.format("DEMARRE -- force UpdateAllAuras toutes les 0.5s et log les changements sur %d bouton(s). /aishdebug circlebarswatch pour arreter.", #circleBarsFlowButtons))
    circleBarsWatchTicker = C_Timer.NewTicker(0.5, function()
        local c = circleBarsFlowContainer
        if not c then return end
        local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
        if not okUpd then
            P(string.format("|cffff4444UpdateAllAuras a echoue -- err=%s|r", tostring(errUpd)))
            return
        end
        for i, btn in ipairs(circleBarsFlowButtons) do
            -- IMPORTANT : btn:IsShown() peut renvoyer une valeur SECRETE des
            -- qu'une vraie aura est liee -- meme la comparer (~=) plante avec
            -- "attempt to compare ... a secret value". CanBeAccessedInContext(),
            -- lui, renvoie toujours un booleen normal -- on s'appuie
            -- uniquement dessus ici, IsShown() est evite.
            local okCA, canAccess = pcall(function() return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext() end)
            local key = string.format("ca=%s/%s", tostring(okCA), tostring(canAccess))
            if circleBarsWatchLastState[i] ~= key then
                P(string.format("bouton #%d : %s", i, key))
                circleBarsWatchLastState[i] = key
            end
        end
    end)
end

------------------------------------------------------------------------
-- GRILLE NATIVE POUR "FREE BARS" (Cooldowns.lua, cle interne circlebars --
-- ATTENTION : l'onglet GUI "Free Bars" est backe par Cooldowns.lua/circlebars,
-- PAS par Buffs.lua/freebars qui est en fait l'onglet GUI "Circle Bars") --
-- methodologie deja eprouvee sur Icons (Procs.lua) et Circle Bars (Buffs.lua).
--
-- Recette confirmee en jeu sur les 2 destinations precedentes, appliquee
-- ici directement (pas de re-decouverte iterative) :
--   - AddAuraGroup (jamais AddAuraSlot) pour SetDurationBar.
--   - SetEnabled/SetUnit/Show sur le conteneur AVANT AddAuraGroup.
--   - Le champ "layout" DOIT etre fourni (meme non exploite pour du flow
--     manuel) pour activer plusieurs membres simultanes du pool.
--   - Blizzard DOIT gerer 100% du positionnement via SetFlowLayout* -- un
--     SetPoint manuel sur l'auraButton entre en conflit avec le flow et
--     fait s'ecraser plusieurs candidats simultanes sur la meme position
--     (cause du bug "2 buffs => tout disparait" sur Circle Bars).
--   - SetDurationBar(bar, {direction = Enum.StatusBarTimerDirection.RemainingTime})
--     pour un remplissage qui VIDE au lieu de REMPLIR.
--   - FontString liee via SetApplicationCount : poser le font AVANT le
--     binding, sinon "Font not set" fait echouer tout le groupe.
--   - Ne JAMAIS retoucher un widget deja lie (SetPoint/texture/couleur)
--     apres sa creation dans initializeFrame -- tout se fait UNE FOIS.
--
-- CAS CIBLE (debuffs sur la cible) : explicitement DIFFERE -- ce rendu ne
-- trace QUE unit="player". La whitelist "circlebars" n'a pas de distinction player/
-- cible par sort (un meme spellID peut apparaitre sur les deux selon le
-- contexte) -- le filtre SetUnit("player") du conteneur natif exclut
-- naturellement tout ce qui n'est actuellement present QUE sur la cible,
-- sans avoir besoin de pre-filtrer la whitelist cote Lua.
--
-- 3 DISPOSITIONS (cfg.layout, cf. Cooldowns.lua Create*Row) :
--   - "side_large" (Vanguard) : icone + 1 barre a cote (iconPos LEFT/RIGHT).
--   - "side_compact" (Sparte) : icone centree + 2 barres miroir autour.
--   - "side_banner" (Banner) : icone au-dessus + 1 barre en-dessous.
-- cfg.hideIcon : mode "barres seules", pas d'icone du tout.
--
-- COULEUR/GLOW PAR SORT : meme recette que Circle Bars -- groupe natif
-- DEDIE par sort (maxFrameCount=1) au lieu d'un groupe partage, confirme
-- cohabiter proprement (/aishdebug testpercolor).
-- SpellBarColorRGB/ApplySpellGlow (utilises ci-dessous) sont declares plus
-- HAUT dans le fichier, juste avant la section "icons" -- portee lexicale
-- Lua oblige (doivent preceder la premiere section appelante dans le
-- fichier). Pas de degrade par sort pour Free Bars/Icon List/Icons --
-- specifique a Circle Bars dans l'ancien pipeline (cf. CBApplySpellColor).
------------------------------------------------------------------------
local freeBarsFlowContainer
local freeBarsFlowGroupAdded = false
freeBarsFlowButtons = {} -- forward-declaree plus haut (ProcGlowTick)
-- [spellID] = true des qu'un AddAuraGroup DEDIE a ete cree pour ce sort
-- (couleur/glow par sort, meme mecanique que circleBarsPerSpellGroups).
local freeBarsPerSpellGroups = {}

local function FBDBG(s) print("|cff33aaff[FreeBarsFlow]|r " .. tostring(s)) end

function ns.GetFreeBarsNativeContainer()
    return freeBarsFlowContainer
end

local function EnsureFreeBarsFlowContainer()
    if freeBarsFlowContainer then return freeBarsFlowContainer end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        FBDBG(string.format("|cffff4444EnsureFreeBarsFlowContainer: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    freeBarsFlowContainer = result

    -- Position/taille reelles ICI, avant tout le reste (meme lecon que
    -- Circle Bars) -- pas un placeholder retouche plus tard.
    local cfg0 = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local maxBars0 = cfg0.maxBars or 8
    local iw0 = cfg0.hideIcon and 0 or (cfg0.iconW or 28)
    local gp0 = cfg0.hideIcon and 0 or (cfg0.gap or 3)
    local bw0, bh0, ih0, rg0 = cfg0.barW or 147, cfg0.barH or 4, cfg0.iconH or 19, cfg0.rowGap or 1
    local layout0 = cfg0.layout or "side_large"
    local rowW0, rowH0
    if layout0 == "side_compact" then rowW0 = bw0*2+iw0+gp0*2; rowH0 = ih0
    elseif layout0 == "side_banner" then rowW0 = (cfg0.hideIcon and bw0 or iw0); rowH0 = ih0 + gp0 + bh0
    else rowW0 = iw0 + gp0 + bw0; rowH0 = ih0 end
    local growth0 = cfg0.growth or "DOWN"
    local isH0 = (growth0 == "LEFT" or growth0 == "RIGHT")
    if isH0 then freeBarsFlowContainer:SetSize(maxBars0 * (rowW0 + rg0), rowH0)
    else freeBarsFlowContainer:SetSize(rowW0, maxBars0 * (rowH0 + rg0)) end
    local x0, y0 = cfg0.x or -502, cfg0.y or 0
    if growth0 == "UP" then freeBarsFlowContainer:SetPoint("BOTTOM", UIParent, "CENTER", x0, y0)
    elseif growth0 == "LEFT" then freeBarsFlowContainer:SetPoint("RIGHT", UIParent, "CENTER", x0, y0)
    elseif growth0 == "RIGHT" then freeBarsFlowContainer:SetPoint("LEFT", UIParent, "CENTER", x0, y0)
    else freeBarsFlowContainer:SetPoint("TOP", UIParent, "CENTER", x0, y0) end

    -- Strata MEDIUM : meme reglage que l'ancien conteneur Cooldowns.lua.
    freeBarsFlowContainer:SetFrameStrata("MEDIUM")

    local okEn, errEn = pcall(freeBarsFlowContainer.SetEnabled, freeBarsFlowContainer, true)
    local okUn, errUn = pcall(freeBarsFlowContainer.SetUnit, freeBarsFlowContainer, "player")
    if not okEn or not okUn then
        FBDBG(string.format("|cffff4444EnsureFreeBarsFlowContainer: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    freeBarsFlowContainer:Show()

    -- Deplacement : Alt+clic gauche, meme pattern que partout ailleurs.
    freeBarsFlowContainer:SetMovable(true)
    freeBarsFlowContainer:SetClampedToScreen(true)
    if _addon.EnableMouseOnlyOnAlt then _addon.EnableMouseOnlyOnAlt(freeBarsFlowContainer) end
    freeBarsFlowContainer:SetPropagateMouseClicks(true)
    local dragLbl = freeBarsFlowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragLbl:SetPoint("BOTTOM", freeBarsFlowContainer, "TOP", 0, 4)
    dragLbl:SetText("|cffffcc00" .. (_addon.L and _addon.L["AURASFEAT_ALT_DRAG_HINT"] or "") .. "|r")
    dragLbl:Hide()
    freeBarsFlowContainer:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            s:SetPropagateMouseClicks(false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    freeBarsFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Cf. commentaire equivalent sur le conteneur "icons" -- GetCenter()
        -- peut renvoyer secret une fois ce conteneur lie a une vraie aura.
        -- pcall : abandon silencieux du placement plutot que planter.
        if cx and cy and ns.db and ns.db.circlebars then
            pcall(function()
                ns.db.circlebars.x = cx*sc - sx
                ns.db.circlebars.y = cy*sc - sy
            end)
        end
    end)
    return freeBarsFlowContainer
end

-- Repositionne le conteneur + reconfigure le flow layout selon cfg.growth
-- (contrairement a Circle Bars, la croissance est reglable par
-- l'utilisateur ici -- reutilise GrowthToFlowParams, meme mapping que
-- "icons"). Rafraichit aussi alpha (combat/hors-combat).
function ns.RepositionFreeBarsNativeGrid()
    local c = EnsureFreeBarsFlowContainer()
    if not c then return end
    local cfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars

    local maxBars = cfg.maxBars or 8
    local iw = cfg.hideIcon and 0 or (cfg.iconW or 28)
    local gp = cfg.hideIcon and 0 or (cfg.gap or 3)
    local bw, bh, ih, rg = cfg.barW or 147, cfg.barH or 4, cfg.iconH or 19, cfg.rowGap or 1
    local layout = cfg.layout or "side_large"
    local rowW, rowH
    if layout == "side_compact" then rowW = bw*2+iw+gp*2; rowH = ih
    elseif layout == "side_banner" then rowW = (cfg.hideIcon and bw or iw); rowH = ih + gp + bh
    else rowW = iw + gp + bw; rowH = ih end
    local growth = cfg.growth or "DOWN"
    local isH = (growth == "LEFT" or growth == "RIGHT")

    if isH then pcall(c.SetSize, c, maxBars * (rowW + rg), rowH)
    else pcall(c.SetSize, c, rowW, maxBars * (rowH + rg)) end

    c:ClearAllPoints()
    local x, y = cfg.x or -502, cfg.y or 0
    if growth == "UP" then c:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then c:SetPoint("RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then c:SetPoint("LEFT", UIParent, "CENTER", x, y)
    else c:SetPoint("TOP", UIParent, "CENTER", x, y) end

    local anchorPoint, hDir, vDir, isHFlow = GrowthToFlowParams(growth)
    local okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
    local okX, errX = pcall(c.SetFlowLayoutAxis, c, isHFlow and 0 or 1)
    local okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
    local itemSize = isH and rowW or rowH
    local okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, (itemSize + rg) * maxBars + rg)
    if not (okA and okX and okG and okM) then
        FBDBG(string.format("|cffff4444RepositionFreeBarsNativeGrid: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    local visible = (ns.db == nil or ns.db.circlebarsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)

    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        pcall(function() if ns.UpdateRenderFade then ns.UpdateRenderFade("circlebars") end end)
    else
        c:SetAlpha(0)
    end
    pcall(function() if ns.RefreshFreeBarsNativeGridStyle then ns.RefreshFreeBarsNativeGridStyle() end end)
end

-- A appeler depuis le GUI a chaque changement de couleur/glow -- ne touche
-- QUE SetStatusBarColor/SetGradient et le glow (widget separe, jamais lie
-- via SetDurationBar) -- jamais SetPoint/SetSize/SetStatusBarTexture sur
-- les StatusBar. Cf. commentaire equivalent sur
-- ns.RefreshCircleBarsNativeGridStyle pour le detail du risque residuel.
function ns.RefreshFreeBarsNativeGridStyle()
    if InCombatLockdown and InCombatLockdown() then return end
    local liveCfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local spells = ns.GetSpecSpells()
    local iw = liveCfg.hideIcon and 0 or (liveCfg.iconW or 28)
    local ih = liveCfg.iconH or 19
    for _, btn in ipairs(freeBarsFlowButtons) do
        local okCheck, canAccess = pcall(function()
            return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext()
        end)
        if okCheck and canAccess then
            local si = btn._aishSpellID and spells and spells[btn._aishSpellID]
            local cR, cG, cB = SpellBarColorRGB(liveCfg, si)
            if btn._aishBarL then pcall(btn._aishBarL.SetStatusBarColor, btn._aishBarL, cR, cG, cB) end
            if btn._aishBarR then pcall(btn._aishBarR.SetStatusBarColor, btn._aishBarR, cR, cG, cB) end
            if btn._aishBar then pcall(btn._aishBar.SetStatusBarColor, btn._aishBar, cR, cG, cB) end
            -- SPARK : texture propre a l'addon, jamais secrete -- toujours
            -- sur de la retoucher, contrairement a la barre.
            if btn._aishSparkL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {cR, cG, cB}) end
            if btn._aishSparkR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {cR, cG, cB}) end
            if btn._aishSpark then pcall(ApplyNativeBarSparkColor, btn._aishSpark, liveCfg, {cR, cG, cB}) end
            if btn._aishGlowAnchor then
                if ns.HideGlow then pcall(ns.HideGlow, btn._aishGlowAnchor) end
                pcall(ApplySpellGlow, btn._aishGlowAnchor, liveCfg, si, iw, ih)
            end
            -- TEXTE DE DUREE : btn._aishCD couvre deja exactement les memes
            -- bornes que l'icone (cd:SetAllPoints(icon) a la creation) -- sert
            -- directement de relFrame, pas besoin d'une reference icone a part.
            if btn._aishCD then
                pcall(btn._aishCD.SetHideCountdownNumbers, btn._aishCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishCD, liveCfg, btn._aishCD)
                end
            end
        end
    end
end

-- Cree (une seule fois PAR SORT) un AddAuraGroup DEDIE pour chaque spellID
-- de la destination "Free Bars", au lieu d'un groupe UNIQUE partage --
-- permet une couleur/glow FIXE par sort (cf. commentaire en tete de
-- section). Appelee depuis Whitelist.lua/BuildWhitelist.
function ns.EnsureFreeBarsNativeGrid()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureFreeBarsFlowContainer()
    if not c then
        FBDBG("|cffff4444EnsureFreeBarsNativeGrid: pas de conteneur|r")
        return
    end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.circlebars
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local maxBars = cfg.maxBars or 8
    local iw = cfg.hideIcon and 0 or (cfg.iconW or 28)
    local gp = cfg.hideIcon and 0 or (cfg.gap or 3)
    local bw, bh, ih, rg = cfg.barW or 147, cfg.barH or 4, cfg.iconH or 19, cfg.rowGap or 1
    local layout = cfg.layout or "side_large"
    local rowW, rowH
    if layout == "side_compact" then rowW = bw*2+iw+gp*2; rowH = ih
    elseif layout == "side_banner" then rowW = (cfg.hideIcon and bw or iw); rowH = ih + gp + bh
    else rowW = iw + gp + bw; rowH = ih end
    local spells = ns.GetSpecSpells()

    -- Cape a maxBars BUFFS (pas spellID, cf. AllowNextCapSlot) : evite un
    -- nombre de groupes non borne, meme intention que l'ancien
    -- maxFrameCount=maxBars.
    local wl = ns.whitelistByDest and ns.whitelistByDest.circlebars
    local seenInfo, capState = {}, { count = 0 }
    local currentSet = {}
    for i, spellID in ipairs(order) do
        if not AllowNextCapSlot(wl, spellID, maxBars, seenInfo, capState) then break end
        currentSet[spellID] = true
        if not freeBarsPerSpellGroups[spellID] then
            local groupKey = "aishFreeBarsFlow_" .. tostring(spellID)
            local si = spells and spells[spellID]
            local okAdd, errAdd = pcall(function()
                c:AddAuraGroup(groupKey, "HELPFUL", {
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = { [spellID] = true } },
                    layout = { elementSpacing = rg, lineSpacing = rg, elementWidth = rowW, elementHeight = rowH, layoutIndex = 1 },
                    initializeFrame = function(auraButton)
                        local okCheck, canAccess = pcall(function()
                            return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
                        end)
                        if not (okCheck and canAccess) then return end
                        local okBuild, errBuild = pcall(function()
                            local liveCfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
                            local liveSpells = ns.GetSpecSpells()
                            local liveSi = liveSpells and liveSpells[spellID]
                            auraButton._aishSpellID = spellID
                            auraButton:SetSize(rowW, rowH)

                            -- ICONE (sauf mode "barres seules")
                            local icon, cd, stackFS
                            if not liveCfg.hideIcon then
                                icon = auraButton:CreateTexture(nil, "ARTWORK")
                                if layout == "side_banner" then
                                    icon:SetSize(iw, ih)
                                    icon:SetPoint("TOP", auraButton, "TOP", 0, 0)
                                elseif layout == "side_compact" then
                                    icon:SetSize(iw, ih)
                                    icon:SetPoint("CENTER", auraButton, "CENTER", 0, 0)
                                else -- side_large (Vanguard)
                                    icon:SetSize(iw, ih)
                                    if (liveCfg.iconPos or "RIGHT") == "RIGHT" then
                                        icon:SetPoint("RIGHT", auraButton, "RIGHT", 0, 0)
                                    else
                                        icon:SetPoint("LEFT", auraButton, "LEFT", 0, 0)
                                    end
                                end
                                -- Crop conscient du ratio (meme recette que
                                -- EnsureIconListNativeGrid) : sans ca, un slot
                                -- icone non-carre (iw ~= ih) etirait l'image de
                                -- facon visible -- on retaille la portion
                                -- echantillonnee du COTE LE PLUS LONG pour que
                                -- la zone source ait le meme ratio que le slot.
                                do
                                    local TC = 0.07
                                    local usable = 1 - 2 * TC
                                    if iw > ih then
                                        local vSpan = (ih / iw) * usable
                                        icon:SetTexCoord(TC, 1 - TC, 0.5 - vSpan * 0.5, 0.5 + vSpan * 0.5)
                                    elseif ih > iw then
                                        local uSpan = (iw / ih) * usable
                                        icon:SetTexCoord(0.5 - uSpan * 0.5, 0.5 + uSpan * 0.5, TC, 1 - TC)
                                    else
                                        icon:SetTexCoord(TC, 1 - TC, TC, 1 - TC)
                                    end
                                end
                                auraButton:SetIcon(icon)

                                local border = auraButton:CreateTexture(nil, "BACKGROUND")
                                border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
                                border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
                                border:SetColorTexture(14/255, 14/255, 14/255, 1)

                                -- Frame dediee, calee sur l'icone (pas sur
                                -- auraButton -- qui englobe icone+barre) :
                                -- sert d'ancre au glow pour qu'il n'entoure
                                -- QUE l'icone.
                                local glowAnchor = CreateFrame("Frame", nil, auraButton)
                                glowAnchor:SetAllPoints(icon)
                                auraButton._aishGlowAnchor = glowAnchor

                                cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                                cd:SetAllPoints(icon)
                                cd:SetReverse(true)
                                auraButton:SetDurationCooldown(cd)
                                auraButton._aishCD = cd

                                stackFS = auraButton:CreateFontString(nil, "OVERLAY", nil, 7)
                                -- Font AVANT SetApplicationCount -- sinon "Font not
                                -- set" fait echouer tout le groupe (cf. lecon
                                -- Icons/Circle Bars).
                                ns.ApplyFont(stackFS, liveCfg.stackFont or ns.Media.font, liveCfg.stackSize or 10, "OUTLINE")
                                stackFS:SetPoint(liveCfg.stackPos or "BOTTOMRIGHT", icon, liveCfg.stackPos or "BOTTOMRIGHT", liveCfg.stackOffX or 0, liveCfg.stackOffY or 0)
                                stackFS:SetJustifyH("RIGHT")
                                stackFS:SetTextColor(liveCfg.stackColorR or 1, liveCfg.stackColorG or 1, liveCfg.stackColorB or 1)
                                auraButton:SetApplicationCount(stackFS, {})
                                auraButton._aishStackFS = stackFS
                            end

                            -- BARRE(S) DE DUREE -- couleur PAR SORT.
                            local barTex = ns.ResolveBarTexFromKey(liveCfg.texture)
                            local barCR, barCG, barCB = SpellBarColorRGB(liveCfg, liveSi)
                            local bgR = liveCfg.barBgR or 0; local bgG = liveCfg.barBgG or 0
                            local bgB = liveCfg.barBgB or 0; local bgA = liveCfg.barBgAlpha or 0
                            local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }

                            local function MakeNativeBar(anchorFrom, relTo, relPoint, offX, offY, rev)
                                local bar = CreateFrame("StatusBar", nil, auraButton)
                                bar:SetSize(bw, bh)
                                bar:SetPoint(anchorFrom, relTo, relPoint, offX, offY)
                                bar:SetStatusBarTexture(barTex)
                                bar:SetStatusBarColor(barCR, barCG, barCB)
                                if rev then bar:SetReverseFill(true) end
                                local bg = bar:CreateTexture(nil, "BACKGROUND")
                                bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                                if not okBar then FBDBG(string.format("|cffff4444initializeFrame (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                -- SPARK : bord mobile oppose au cote d'origine
                                -- du remplissage (cf. MakeNativeBarSpark). La
                                -- reference est stockee pour pouvoir le
                                -- recolorer plus tard.
                                local spark = MakeNativeBarSpark(bar, liveCfg, rev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                                return bar, spark
                            end

                            if layout == "side_compact" then
                                -- Sparte : icone centree, 2 barres miroir.
                                local anchorRef = liveCfg.hideIcon and auraButton or icon
                                local relPointL = liveCfg.hideIcon and "CENTER" or "LEFT"
                                local relPointR = liveCfg.hideIcon and "CENTER" or "RIGHT"
                                auraButton._aishBarL, auraButton._aishSparkL = MakeNativeBar("RIGHT", anchorRef, relPointL, -gp, 0, true)
                                auraButton._aishBarR, auraButton._aishSparkR = MakeNativeBar("LEFT", anchorRef, relPointR, gp, 0, false)
                            elseif layout == "side_banner" then
                                -- Banner : icone au-dessus (ou rien si hideIcon), barre en-dessous.
                                local bannerBarW = liveCfg.hideIcon and bw or iw
                                local bar = CreateFrame("StatusBar", nil, auraButton)
                                bar:SetSize(bannerBarW, bh)
                                if liveCfg.hideIcon then
                                    bar:SetPoint("TOP", auraButton, "TOP", 0, 0)
                                else
                                    bar:SetPoint("TOP", icon, "BOTTOM", 0, -gp)
                                end
                                bar:SetStatusBarTexture(barTex)
                                bar:SetStatusBarColor(barCR, barCG, barCB)
                                local isRev = liveCfg.reverse == true
                                bar:SetReverseFill(isRev)
                                local bg = bar:CreateTexture(nil, "BACKGROUND")
                                bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                                if not okBar then FBDBG(string.format("|cffff4444initializeFrame (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                auraButton._aishBar = bar
                                auraButton._aishSpark = MakeNativeBarSpark(bar, liveCfg, isRev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                            else
                                -- Vanguard : icone + 1 barre a cote.
                                local iconR = (liveCfg.iconPos or "RIGHT") == "RIGHT"
                                local bar = CreateFrame("StatusBar", nil, auraButton)
                                bar:SetSize(bw, bh)
                                if liveCfg.hideIcon then
                                    bar:SetPoint(iconR and "RIGHT" or "LEFT", auraButton, iconR and "RIGHT" or "LEFT", 0, 0)
                                elseif iconR then
                                    bar:SetPoint("RIGHT", icon, "LEFT", -gp, 0)
                                else
                                    bar:SetPoint("LEFT", icon, "RIGHT", gp, 0)
                                end
                                bar:SetStatusBarTexture(barTex)
                                bar:SetStatusBarColor(barCR, barCG, barCB)
                                local isRev = liveCfg.reverse == true
                                bar:SetReverseFill(isRev)
                                local bg = bar:CreateTexture(nil, "BACKGROUND")
                                bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                                if not okBar then FBDBG(string.format("|cffff4444initializeFrame (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                auraButton._aishBar = bar
                                auraButton._aishSpark = MakeNativeBarSpark(bar, liveCfg, isRev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                            end

                            -- SWIPE + TEXTE DE DUREE NATIF (meme mecanisme que
                            -- Icons -- Blizzard remplit le chiffre cote C++,
                            -- mais police/taille/couleur/position restylables
                            -- via ApplyNativeCountdownStyle, cf. plus haut).
                            if cd then
                                cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
                                cd:SetDrawEdge(liveCfg.swipeEnabled == true)
                                cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
                                if liveCfg.timerIconEnabled then
                                    ApplyNativeCountdownStyle(cd, liveCfg, icon or auraButton)
                                end
                            end

                            -- GLOW PAR SORT (override du render prioritaire,
                            -- sinon glow propre au sort) -- cf. ApplySpellGlow.
                            if icon then
                                ApplySpellGlow(auraButton._aishGlowAnchor, liveCfg, liveSi, iw, ih)
                                -- Animation d'entree ("Proc: White Short" etc),
                                -- jouee UNE SEULE FOIS.
                                PlayProcStartOnce(auraButton._aishGlowAnchor, liveSi, spellID)
                            end

                            freeBarsFlowButtons[#freeBarsFlowButtons + 1] = auraButton
                        end)
                        if not okBuild then
                            FBDBG(string.format("|cffff4444initializeFrame (Free Bars, sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                        end
                    end,
                })
            end)
            if not okAdd then
                FBDBG(string.format("|cffff4444AddAuraGroup DEDIE (Free Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
            end
            freeBarsPerSpellGroups[spellID] = true
            freeBarsFlowGroupAdded = true
            if c.UpdateAllAuras then
                local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                if not okUpd then FBDBG(string.format("|cffff4444UpdateAllAuras (Free Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
            end
        else
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis
            -- re-trace depuis (cf. commentaire equivalent Icons plus haut).
            pcall(c.SetAuraGroupCandidateFilters, c, "aishFreeBarsFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques depuis la derniere fois : leur groupe dedie existe
    -- toujours (impossible a supprimer) donc on le neutralise avec un
    -- spellID bidon (jamais {} -- un candidateFilters.includeSpellIDs VIDE
    -- signifie "aucune restriction" cote Blizzard, pas "rien n'est autorise"
    -- -- cf. commentaire equivalent Icons plus haut).
    for spellID in pairs(freeBarsPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishFreeBarsFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

------------------------------------------------------------------------
-- ICON LIST (GUI "Liste d'icones", Debuffs.lua, cle interne iconlist) :
-- meme methodologie que Icons/Circle Bars/Free Bars. 2 dispositions
-- (cfg.layout, cf. Debuffs.lua Create*Row) :
--   - "center_mirror" (Aegis, defaut) : icone centree + 2 barres miroir
--     autour (meme geometrie que Free Bars "side_compact").
--   - "center_dual" (Berserk) : paires icone+barre de part et d'autre d'un
--     espace central, plusieurs paires empilees. Chaque auraButton natif
--     represente UNE MOITIE (icone+1 barre) -- le flow layout les groupe 2
--     par 2 (axe horizontal fixe, elementSpacing=pairGap, maximumLineSize
--     cale sur exactement 2 elements) et empile les paires verticalement
--     (lineSpacing=rowGap). Le cote gauche/droit de chaque moitie est fixe
--     a la CREATION du bouton dans le pool (compteur local, jamais
--     reevalue ensuite) -- stable car Blizzard cree les membres du pool
--     dans un ordre sequentiel fixe, meme mecanique de "slot stable" deja
--     utilisee pour Circle Bars/Free Bars.
--
-- CAS CIBLE : explicitement DIFFERE, meme raisonnement que Free Bars --
-- SetUnit("player") exclut naturellement tout ce qui n'est present QUE
-- sur la cible.
--
-- SIMPLIFICATIONS ACCEPTEES (coherentes avec Icons/Free Bars) :
--   - Pas de texte de charges (C_Spell.GetSpellCharges) : necessiterait un
--     canal de refresh periodique independant, le spellID lie a un bouton
--     natif n'etant pas lisible de facon fiable en combat -- deja
--     silencieusement absent sur Icons/Free Bars, meme limitation ici
--     plutot que d'introduire un nouveau mecanisme non teste.
--   - "center_dual" + growth LEFT/RIGHT : l'empilement des paires reste
--     VERTICAL (comme DOWN) -- l'axe horizontal est deja utilise pour la
--     paire elle-meme, un flow 2D avec axe primaire configurable n'est pas
--     supporte par cette API. Cas rare, DOWN est la valeur par defaut.
--   - Changement de disposition (layout) a chaud : necessite un /reload
--     (le champ "layout" d'AddAuraGroup est fige a la creation), meme
--     limitation que Free Bars (3 dispositions).
------------------------------------------------------------------------
local iconListFlowContainer
local iconListFlowGroupAdded = false
iconListFlowButtons = {} -- forward-declaree plus haut (ProcGlowTick)
local iconListDualCounter = 0
-- [spellID] = true des qu'un AddAuraGroup DEDIE a ete cree pour ce sort
-- (couleur/glow par sort, meme mecanique que circleBarsPerSpellGroups).
-- Bonus : le compteur gauche/droite (center_dual) devient DETERMINISTE --
-- les groupes sont crees dans l'ordre de priorite (ns.slotOrderByDest),
-- donc le 1er sort traque est toujours a gauche, le 2e a droite, etc.
-- (avant : dependait de quel sort devenait actif en premier).
local iconListPerSpellGroups = {}

local function ILDBG(s) print("|cff33aaff[IconListFlow]|r " .. tostring(s)) end

function ns.GetIconListNativeContainer()
    return iconListFlowContainer
end

-- Geometrie partagee entre EnsureIconListFlowContainer/RepositionIconListNativeGrid/
-- EnsureIconListNativeGrid : evite la duplication des formules. Retourne
-- toujours 12 valeurs, les 2 dernieres variant selon layout :
--   center_dual   : ..., halfW, numPairs
--   center_mirror : ..., rowW,  rowH (rowH == ih)
local function IconListGeom(cfg)
    local bw, bh, iw, ih, gp, pg, rg = cfg.barW or 80, cfg.barH or 2, cfg.iconW or 25, cfg.iconH or 25,
        cfg.gap or 12, cfg.pairGap or 6, cfg.rowGap or 3
    local layout = cfg.layout or "center_mirror"
    local isDual = (layout == "center_dual")
    local maxBars = cfg.maxBars or 8
    if isDual then
        local halfW = iw + gp + bw
        local numPairs = math.ceil(maxBars / 2)
        return bw, bh, iw, ih, gp, pg, rg, layout, isDual, maxBars, halfW, numPairs
    else
        local rowW = bw * 2 + iw + gp * 2
        return bw, bh, iw, ih, gp, pg, rg, layout, isDual, maxBars, rowW, ih
    end
end

local function EnsureIconListFlowContainer()
    if iconListFlowContainer then return iconListFlowContainer end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        ILDBG(string.format("|cffff4444EnsureIconListFlowContainer: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    iconListFlowContainer = result

    local cfg0 = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local bw0, bh0, iw0, ih0, gp0, pg0, rg0, layout0, isDual0, maxBars0, a0, b0 = IconListGeom(cfg0)
    local growth0 = cfg0.growth or "DOWN"
    if isDual0 then
        iconListFlowContainer:SetSize(a0 * 2 + pg0, b0 * (ih0 + rg0))
    else
        local isH0 = (growth0 == "LEFT" or growth0 == "RIGHT")
        if isH0 then iconListFlowContainer:SetSize(maxBars0 * (a0 + rg0), b0)
        else iconListFlowContainer:SetSize(a0, maxBars0 * (b0 + rg0)) end
    end
    local x0, y0 = cfg0.x or 0, cfg0.y or -290
    if growth0 == "UP" then iconListFlowContainer:SetPoint("BOTTOM", UIParent, "CENTER", x0, y0)
    elseif growth0 == "LEFT" then iconListFlowContainer:SetPoint("RIGHT", UIParent, "CENTER", x0, y0)
    elseif growth0 == "RIGHT" then iconListFlowContainer:SetPoint("LEFT", UIParent, "CENTER", x0, y0)
    else iconListFlowContainer:SetPoint("TOP", UIParent, "CENTER", x0, y0) end

    iconListFlowContainer:SetFrameStrata("BACKGROUND")

    local okEn, errEn = pcall(iconListFlowContainer.SetEnabled, iconListFlowContainer, true)
    local okUn, errUn = pcall(iconListFlowContainer.SetUnit, iconListFlowContainer, "player")
    if not okEn or not okUn then
        ILDBG(string.format("|cffff4444EnsureIconListFlowContainer: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    iconListFlowContainer:Show()

    iconListFlowContainer:SetMovable(true)
    iconListFlowContainer:SetClampedToScreen(true)
    if _addon.EnableMouseOnlyOnAlt then _addon.EnableMouseOnlyOnAlt(iconListFlowContainer) end
    iconListFlowContainer:SetPropagateMouseClicks(true)
    local dragLbl = iconListFlowContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragLbl:SetPoint("BOTTOM", iconListFlowContainer, "TOP", 0, 4)
    dragLbl:SetText("|cffffcc00" .. (_addon.L and _addon.L["AURASFEAT_ALT_DRAG_HINT"] or "") .. "|r")
    dragLbl:Hide()
    iconListFlowContainer:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            s:SetPropagateMouseClicks(false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    iconListFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Cf. commentaire equivalent sur le conteneur "icons" -- GetCenter()
        -- peut renvoyer secret une fois ce conteneur lie a une vraie aura.
        -- pcall : abandon silencieux du placement plutot que planter.
        if cx and cy and ns.db and ns.db.iconlist then
            pcall(function()
                ns.db.iconlist.x = cx*sc - sx
                ns.db.iconlist.y = cy*sc - sy
            end)
        end
    end)
    return iconListFlowContainer
end

-- Repositionne le conteneur + reconfigure le flow layout selon
-- cfg.layout/growth. Rafraichit aussi alpha (combat/hors-combat).
function ns.RepositionIconListNativeGrid()
    local c = EnsureIconListFlowContainer()
    if not c then return end
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local bw, bh, iw, ih, gp, pg, rg, layout, isDual, maxBars, a, b = IconListGeom(cfg)
    local growth = cfg.growth or "DOWN"

    if isDual then
        pcall(c.SetSize, c, a * 2 + pg, b * (ih + rg))
    else
        local isH = (growth == "LEFT" or growth == "RIGHT")
        if isH then pcall(c.SetSize, c, maxBars * (a + rg), b)
        else pcall(c.SetSize, c, a, maxBars * (b + rg)) end
    end

    c:ClearAllPoints()
    local x, y = cfg.x or 0, cfg.y or -290
    if growth == "UP" then c:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then c:SetPoint("RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then c:SetPoint("LEFT", UIParent, "CENTER", x, y)
    else c:SetPoint("TOP", UIParent, "CENTER", x, y) end

    local okA, okX, okG, okM, errA, errX, errG, errM
    if isDual then
        -- Paires horizontales fixes (axe 0), empilement vertical des paires
        -- (LEFT/RIGHT traites comme DOWN -- cf. limitation documentee plus haut).
        if growth == "UP" then
            okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, "BOTTOMLEFT")
            okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, 1, 1)
        else
            okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, "TOPLEFT")
            okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, 1, -1)
        end
        okX, errX = pcall(c.SetFlowLayoutAxis, c, 0)
        okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, a * 2 + pg + 2)
    else
        local anchorPoint, hDir, vDir, isHFlow = GrowthToFlowParams(growth)
        okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
        okX, errX = pcall(c.SetFlowLayoutAxis, c, isHFlow and 0 or 1)
        okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
        local itemSize = isHFlow and a or b
        okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, (itemSize + rg) * maxBars + rg)
    end
    if not (okA and okX and okG and okM) then
        ILDBG(string.format("|cffff4444RepositionIconListNativeGrid: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    local visible = (ns.db == nil or ns.db.iconlistEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        pcall(function() if ns.UpdateRenderFade then ns.UpdateRenderFade("iconlist") end end)
    else
        c:SetAlpha(0)
    end
    pcall(function() if ns.RefreshIconListNativeGridStyle then ns.RefreshIconListNativeGridStyle() end end)
end

-- A appeler depuis le GUI a chaque changement de couleur/glow -- ne touche
-- QUE SetStatusBarColor et le glow (widget separe, jamais lie via
-- SetDurationBar) -- jamais SetPoint/SetSize/SetStatusBarTexture. Cf.
-- commentaire equivalent sur ns.RefreshCircleBarsNativeGridStyle.
function ns.RefreshIconListNativeGridStyle()
    if InCombatLockdown and InCombatLockdown() then return end
    local liveCfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local spells = ns.GetSpecSpells()
    local bw, bh, iw, ih = IconListGeom(liveCfg)
    for _, btn in ipairs(iconListFlowButtons) do
        local okCheck, canAccess = pcall(function()
            return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext()
        end)
        if okCheck and canAccess then
            local si = btn._aishSpellID and spells and spells[btn._aishSpellID]
            local cR, cG, cB = SpellBarColorRGB(liveCfg, si)
            if btn._aishBarL then pcall(btn._aishBarL.SetStatusBarColor, btn._aishBarL, cR, cG, cB) end
            if btn._aishBarR then pcall(btn._aishBarR.SetStatusBarColor, btn._aishBarR, cR, cG, cB) end
            if btn._aishBar then pcall(btn._aishBar.SetStatusBarColor, btn._aishBar, cR, cG, cB) end
            -- SPARK : texture propre a l'addon, jamais secrete -- toujours
            -- sur de la retoucher, contrairement a la barre.
            if btn._aishSparkL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {cR, cG, cB}) end
            if btn._aishSparkR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {cR, cG, cB}) end
            if btn._aishSpark then pcall(ApplyNativeBarSparkColor, btn._aishSpark, liveCfg, {cR, cG, cB}) end
            if btn._aishGlowAnchor then
                if ns.HideGlow then pcall(ns.HideGlow, btn._aishGlowAnchor) end
                pcall(ApplySpellGlow, btn._aishGlowAnchor, liveCfg, si, iw, ih)
            end
            -- TEXTE DE DUREE : meme recette que Free Bars, cd:SetAllPoints(icon)
            -- a la creation -> sert directement de relFrame.
            if btn._aishCD then
                pcall(btn._aishCD.SetHideCountdownNumbers, btn._aishCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishCD, liveCfg, btn._aishCD)
                end
            end
        end
    end
end

-- Cree (une seule fois PAR SORT) un AddAuraGroup DEDIE pour chaque spellID
-- de la destination "Liste d'icones", au lieu d'un groupe UNIQUE partage --
-- permet une couleur/glow FIXE par sort. Appelee depuis
-- Whitelist.lua/BuildWhitelist.
function ns.EnsureIconListNativeGrid()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureIconListFlowContainer()
    if not c then
        ILDBG("|cffff4444EnsureIconListNativeGrid: pas de conteneur|r")
        return
    end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.iconlist
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local bw, bh, iw, ih, gp, pg, rg, layout, isDual, maxBars, a, b = IconListGeom(cfg)
    local elemW, elemH = a, ih
    -- Cape (nombre de GROUPES, pas de barres-slots) : en mode "center_dual"
    -- (Berserk), chaque groupe ne represente qu'UNE MOITIE de paire -- le
    -- cap total reste 2*numPairs, comme avant.
    local groupCap = isDual and (2 * b) or maxBars
    local spells = ns.GetSpecSpells()

    -- Cape a groupCap BUFFS (pas spellID, cf. AllowNextCapSlot) : une
    -- variante de tier d'un meme buff (linkedSpellIDs) ne doit consommer
    -- qu'UNE place, jamais une par spellID.
    local wl = ns.whitelistByDest and ns.whitelistByDest.iconlist
    local seenInfo, capState = {}, { count = 0 }
    local currentSet = {}
    for i, spellID in ipairs(order) do
        if not AllowNextCapSlot(wl, spellID, groupCap, seenInfo, capState) then break end
        currentSet[spellID] = true
        if not iconListPerSpellGroups[spellID] then
            local groupKey = "aishIconListFlow_" .. tostring(spellID)
            local si = spells and spells[spellID]
            local okAdd, errAdd = pcall(function()
                c:AddAuraGroup(groupKey, "HELPFUL", {
                    maxFrameCount = 1,
                    candidateFilters = { includeSpellIDs = { [spellID] = true } },
                    layout = { elementSpacing = (isDual and pg or rg), lineSpacing = rg, elementWidth = elemW, elementHeight = elemH, layoutIndex = 1 },
                    initializeFrame = function(auraButton)
                        local okCheck, canAccess = pcall(function()
                            return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
                        end)
                        if not (okCheck and canAccess) then return end
                        local okBuild, errBuild = pcall(function()
                            local liveCfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
                            local liveSpells = ns.GetSpecSpells()
                            local liveSi = liveSpells and liveSpells[spellID]
                            auraButton._aishSpellID = spellID
                            local lbw, lbh, liw, lih, lgp, lpg, lrg, llayout, lisDual = IconListGeom(liveCfg)
                            auraButton:SetSize(elemW, elemH)

                            local isLeft = true
                            if lisDual then
                                iconListDualCounter = iconListDualCounter + 1
                                isLeft = (iconListDualCounter % 2 == 1)
                            end

                            -- ICONE
                            local icon = auraButton:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(liw, lih)
                            if lisDual then
                                icon:SetPoint(isLeft and "RIGHT" or "LEFT", auraButton, isLeft and "RIGHT" or "LEFT", 0, 0)
                            else
                                icon:SetPoint("CENTER", auraButton, "CENTER", 0, 0)
                            end
                            -- Crop conscient du ratio (meme recette que Cooldowns.lua::
                            -- MakeIcon, "Free Bars") : sans ca, un slot icone non-carre
                            -- (liw ~= lih) etirait l'image de facon visible -- on retaille
                            -- la portion echantillonnee du COTE LE PLUS LONG pour que la
                            -- zone source ait le meme ratio que le slot de destination.
                            do
                                local TC = 0.07
                                local usable = 1 - 2 * TC
                                if liw > lih then
                                    local vSpan = (lih / liw) * usable
                                    icon:SetTexCoord(TC, 1 - TC, 0.5 - vSpan * 0.5, 0.5 + vSpan * 0.5)
                                elseif lih > liw then
                                    local uSpan = (liw / lih) * usable
                                    icon:SetTexCoord(0.5 - uSpan * 0.5, 0.5 + uSpan * 0.5, TC, 1 - TC)
                                else
                                    icon:SetTexCoord(TC, 1 - TC, TC, 1 - TC)
                                end
                            end
                            auraButton:SetIcon(icon)

                            local border = auraButton:CreateTexture(nil, "BACKGROUND")
                            border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
                            border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
                            border:SetColorTexture(14/255, 14/255, 14/255, 1)

                            -- Frame dediee pour le glow (cf. lecon Free Bars) :
                            -- calee sur l'icone, jamais sur auraButton (icone+barre).
                            local glowAnchor = CreateFrame("Frame", nil, auraButton)
                            glowAnchor:SetAllPoints(icon)
                            auraButton._aishGlowAnchor = glowAnchor

                            local cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                            cd:SetAllPoints(icon)
                            cd:SetReverse(true)
                            auraButton:SetDurationCooldown(cd)
                            auraButton._aishCD = cd

                            local stackFS = auraButton:CreateFontString(nil, "OVERLAY", nil, 7)
                            -- Font AVANT SetApplicationCount (lecon Icons/Circle Bars/Free Bars).
                            ns.ApplyFont(stackFS, liveCfg.stackFont or ns.Media.font, liveCfg.stackSize or 10, "OUTLINE")
                            stackFS:SetPoint(liveCfg.stackPos or "BOTTOMRIGHT", icon, liveCfg.stackPos or "BOTTOMRIGHT", liveCfg.stackOffX or 0, liveCfg.stackOffY or 0)
                            stackFS:SetJustifyH("RIGHT")
                            stackFS:SetTextColor(liveCfg.stackColorR or 1, liveCfg.stackColorG or 1, liveCfg.stackColorB or 1)
                            auraButton:SetApplicationCount(stackFS, {})
                            auraButton._aishStackFS = stackFS

                            -- BARRE(S) DE DUREE -- couleur PAR SORT.
                            local barTex = ns.ResolveBarTexFromKey(liveCfg.texture)
                            local barCR, barCG, barCB = SpellBarColorRGB(liveCfg, liveSi)
                            local bgR = liveCfg.barBgR or 0; local bgG = liveCfg.barBgG or 0
                            local bgB = liveCfg.barBgB or 0; local bgA = liveCfg.barBgAlpha or 0
                            local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }

                            local function MakeNativeBar(anchorFrom, relTo, relPoint, offX, offY, rev)
                                local bar = CreateFrame("StatusBar", nil, auraButton)
                                bar:SetSize(lbw, lbh)
                                bar:SetPoint(anchorFrom, relTo, relPoint, offX, offY)
                                bar:SetStatusBarTexture(barTex)
                                bar:SetStatusBarColor(barCR, barCG, barCB)
                                if rev then bar:SetReverseFill(true) end
                                local bg = bar:CreateTexture(nil, "BACKGROUND")
                                bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                                if not okBar then ILDBG(string.format("|cffff4444initializeFrame (Icon List, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                -- SPARK : bord mobile oppose au cote d'origine
                                -- du remplissage (cf. MakeNativeBarSpark). La
                                -- reference est stockee pour pouvoir le
                                -- recolorer plus tard.
                                local spark = MakeNativeBarSpark(bar, liveCfg, rev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                                return bar, spark
                            end

                            if lisDual then
                                -- Berserk : 1 barre du cote EXTERIEUR de l'icone
                                -- (loin du centre de la paire).
                                if isLeft then
                                    auraButton._aishBar, auraButton._aishSpark = MakeNativeBar("RIGHT", icon, "LEFT", -lgp, 0, true)
                                else
                                    auraButton._aishBar, auraButton._aishSpark = MakeNativeBar("LEFT", icon, "RIGHT", lgp, 0, false)
                                end
                            else
                                -- Aegis : icone centree, 2 barres miroir.
                                auraButton._aishBarL, auraButton._aishSparkL = MakeNativeBar("RIGHT", icon, "LEFT", -lgp, 0, true)
                                auraButton._aishBarR, auraButton._aishSparkR = MakeNativeBar("LEFT", icon, "RIGHT", lgp, 0, false)
                            end

                            -- SWIPE + TEXTE DE DUREE NATIF (police/taille/couleur/
                            -- position restylables via ApplyNativeCountdownStyle).
                            cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
                            cd:SetDrawEdge(liveCfg.swipeEnabled == true)
                            cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
                            if liveCfg.timerIconEnabled then
                                ApplyNativeCountdownStyle(cd, liveCfg, icon)
                            end

                            -- GLOW PAR SORT.
                            ApplySpellGlow(auraButton._aishGlowAnchor, liveCfg, liveSi, liw, lih)
                            -- Animation d'entree ("Proc: White Short" etc),
                            -- jouee UNE SEULE FOIS.
                            PlayProcStartOnce(auraButton._aishGlowAnchor, liveSi, spellID)

                            iconListFlowButtons[#iconListFlowButtons + 1] = auraButton
                        end)
                        if not okBuild then
                            ILDBG(string.format("|cffff4444initializeFrame (Icon List, sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                        end
                    end,
                })
            end)
            if not okAdd then
                ILDBG(string.format("|cffff4444AddAuraGroup DEDIE (Icon List, sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
            end
            iconListPerSpellGroups[spellID] = true
            iconListFlowGroupAdded = true
            if c.UpdateAllAuras then
                local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                if not okUpd then ILDBG(string.format("|cffff4444UpdateAllAuras (Icon List, sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
            end
        else
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis
            -- re-trace depuis (cf. commentaire equivalent Icons plus haut).
            pcall(c.SetAuraGroupCandidateFilters, c, "aishIconListFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques depuis la derniere fois : leur groupe dedie existe
    -- toujours (impossible a supprimer) donc on le neutralise avec un
    -- spellID bidon (jamais {} -- un candidateFilters.includeSpellIDs VIDE
    -- signifie "aucune restriction" cote Blizzard, pas "rien n'est autorise"
    -- -- cf. commentaire equivalent Icons plus haut).
    for spellID in pairs(iconListPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishIconListFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

------------------------------------------------------------------------
-- /aishdebug groups -- diagnostic de l'usage memoire des groupes natifs :
-- chacune des 4 destinations natives cree un AddAuraGroup DEDIE par
-- spellID la premiere fois qu'il est traque, avec toute une arborescence
-- de widgets (icone/bordure/Cooldown+FontString natif/StatusBar(s)/fond/
-- spark/stack/charges/AnimationGroups de glow) -- CONTRAINTE NATIVE
-- Blizzard : un groupe ne peut JAMAIS etre supprime une fois cree (cf.
-- commentaires "impossible a supprimer" ci-dessus, x4). Chaque spellID
-- DIFFERENT traque au moins une fois dans une destination pendant la
-- session laisse donc une arborescence de widgets alloues EN PERMANENCE
-- jusqu'au prochain /reload, meme si le sort est ensuite decoche. Dump ce
-- compteur pour verifier si l'usage memoire eleve vient d'une accumulation
-- de groupes lors de tests/iterations repetees sur beaucoup de sorts
-- differents (plutot que d'une vraie fuite qui grossirait sans jamais
-- refleter un nombre de sorts reellement testes).
function ns.DebugDumpGroupCounts()
    local function CountKeys(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
    print("|cff00ccffAishCore Debug|r === Groupes AddAuraGroup dedies (jamais supprimables) ===")
    print(string.format("  Icones       : %d groupe(s) crees | %d bouton(s) dans le pool", CountKeys(iconsPerSpellGroups), #iconsFlowButtons))
    print(string.format("  Circle Bars  : %d groupe(s) crees | %d bouton(s) dans le pool", CountKeys(circleBarsPerSpellGroups), #circleBarsFlowButtons))
    print(string.format("  Free Bars    : %d groupe(s) crees | %d bouton(s) dans le pool", CountKeys(freeBarsPerSpellGroups), #freeBarsFlowButtons))
    print(string.format("  Liste icones : %d groupe(s) crees | %d bouton(s) dans le pool", CountKeys(iconListPerSpellGroups), #iconListFlowButtons))
    local total = CountKeys(iconsPerSpellGroups) + CountKeys(circleBarsPerSpellGroups) + CountKeys(freeBarsPerSpellGroups) + CountKeys(iconListPerSpellGroups)
    print(string.format("  |cffffcc00TOTAL : %d groupes dedies alloues cette session (jamais liberes avant /reload)|r", total))
end

------------------------------------------------------------------------
-- /aishdebug spell <id1> [id2] ... -- diagnostic cible pour un buff
-- multi-tier (ex: Jet d'osselets Hors-la-loi, 4 spellID pour 1 seul buff
-- conceptuel) : pour chaque spellID donne, montre s'il est connu dans
-- ns.GetSpecSpells() (enabled/destinations/linkedSpellIDs), s'il figure
-- dans l'ordre whitelist de chaque destination (slotOrderByDest), et si
-- un AddAuraGroup dedie a deja ete cree pour lui dans chacune des 4
-- destinations natives (Xxx PerSpellGroups). Un spellID present dans
-- slotOrderByDest mais SANS groupe dedie cree = jamais rencontre en jeu
-- pour cette destination depuis le dernier /reload (le groupe se cree a
-- la premiere apparition, cf. EnsureXxxNativeGrid).
------------------------------------------------------------------------
function ns.DebugDumpSpellTracking(...)
    local ids = { ... }
    if #ids == 0 then
        print("|cff00ccffAishCore Debug|r Usage: /aishdebug spell <spellID> [spellID2] ...")
        return
    end
    local spells = ns.GetSpecSpells()
    local destGroups = {
        icons      = iconsPerSpellGroups,
        circlebars = freeBarsPerSpellGroups,   -- GUI "Free Bars"
        freebars   = circleBarsPerSpellGroups, -- GUI "Circle Bars"
        iconlist   = iconListPerSpellGroups,
    }
    for _, spellID in ipairs(ids) do
        spellID = tonumber(spellID)
        if spellID then
            print(string.format("|cff00ccffAishCore Debug|r === spellID %d (%s) ===",
                spellID, GetSpellName and (GetSpellName(spellID) or "?") or "?"))
            local info = spells and spells[spellID]
            if not info then
                print("  |cffff4444Absent de ns.GetSpecSpells() (jamais decouvert / hors spec active)|r")
            else
                local dests = {}
                if info.destinations then
                    for dest, active in pairs(info.destinations) do
                        if active then dests[#dests + 1] = dest end
                    end
                end
                local linked = "aucun"
                if type(info.linkedSpellIDs) == "table" then
                    linked = table.concat(info.linkedSpellIDs, ", ")
                end
                print(string.format("  enabled=%s  destinations=[%s]  linkedSpellIDs=[%s]",
                    tostring(info.enabled), table.concat(dests, ", "), linked))
            end
            for _, dest in ipairs({ "icons", "circlebars", "freebars", "iconlist" }) do
                local order = ns.slotOrderByDest and ns.slotOrderByDest[dest]
                local inOrder = false
                if order then for _, id in ipairs(order) do if id == spellID then inOrder = true break end end end
                local hasGroup = destGroups[dest][spellID] and true or false
                print(string.format("    %-10s dansWhitelist=%-5s  groupeDedieCree=%-5s",
                    dest, tostring(inOrder), tostring(hasGroup)))
            end
        end
    end
end

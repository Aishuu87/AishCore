-- AishUIAura/Core/AuraTrackerContainer.lua
--
-- Rendu combat-safe des auras trackees via le systeme natif Blizzard AuraContainer (patch 12.1+,
-- "Secret Values") : pour chacune des 4 destinations (Icons, Circle Bars, Free Bars, Icon List), un
-- AuraContainer persistant heberge un AddAuraGroup dedie par spellID trace, dont l'auraButton pilote
-- nativement icone/cooldown/stacks/barre de duree via SetIcon/SetDurationCooldown/SetApplicationCount/
-- SetDurationBar -- sans jamais exposer de valeur secrete a Lua.
--
-- Contraintes API a connaitre avant de retoucher ce fichier :
--   - Le champ de filtrage exact est `includeSpellIDs`.
--   - Un AuraButton natif (et tout enfant cree dessus) devient "forbidden" -- meme en LECTURE -- des
--     que l'aura associee devient secrete (combat/instance/PvP). Toute creation/liaison doit donc se
--     faire UNE SEULE FOIS dans initializeFrame (seules les proprietes de STYLE restent modifiables
--     hors contexte secret, cf. ApplyXxxButtonStyle plus bas).
--   - Blizzard ne positionne jamais le bouton natif seul : ancrage manuel (SetPoint/SetAllPoints) requis.
--   - SetEnabled(true) + Show() + UpdateAllAuras() sur le CONTENEUR (pas le bouton) sont necessaires
--     apres creation des groupes ; SetEnabled doit preceder SetUnit.
--   - La presence combat-safe ne peut pas etre suivie via HookScript("OnShow"/"OnHide") sur un
--     AuraButton natif (bloque des qu'une aura secrete peut lui etre liee) : ns._lastKnownAura
--     (Scan.lua) reste la source de verite pour la presence.
--   - Un AddAuraGroup ne peut jamais etre supprime une fois cree -- un spellID de-trace se neutralise
--     via SetAuraGroupCandidateFilters sur un spellID bidon (jamais {}, qui matche tout).
--   - Creer un AuraContainer EN COMBAT plante le jeu : creation unique, hors combat, jamais recreee.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local nativeButtons = { player = {} }  -- [unit] = { [spellID] = button natif }
local shadowBars    = { player = {} }  -- [unit] = { [spellID] = StatusBar } -- inutilise pour l'instant (aucun binding SetDurationBar tente ici)

-- Toujours exposees ; les call sites (Debuffs.lua/Cooldowns.lua/Procs.lua/Animation.lua) gardent deja
-- "if nativeBtn then" -- renvoyer nil retombe proprement sur les canaux CDM tant qu'un slot n'existe
-- pas encore pour ce spellID.
function ns.GetNativeAuraButton(unit, spellID)
    local t = nativeButtons[unit]
    return t and t[spellID]
end

function ns.GetNativeShadowBar(unit, spellID)
    local t = shadowBars[unit]
    return t and t[spellID]
end

-- SetPropagateMouseClicks sur un de ces conteneurs peut etre bloque en ADDON_ACTION_BLOCKED des lors
-- qu'un Alt+glisser demarre hors combat mais se termine (OnMouseUp) apres une entree en combat entre-
-- temps. pcall evite l'erreur visible ; si le blocage empechait de REACTIVER la propagation (allow=true),
-- on retente au premier PLAYER_REGEN_ENABLED, sinon le conteneur resterait bloque pour le reste de la
-- session (plus aucun clic ne traverserait).
local function SafeSetPropagateMouseClicks(f, allow)
    local ok = pcall(f.SetPropagateMouseClicks, f, allow)
    if ok or not allow then return end
    local retryFrame = CreateFrame("Frame")
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    retryFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pcall(f.SetPropagateMouseClicks, f, true)
    end)
end

-- Conteneur AuraContainer persistant, un AddAuraSlot fixe par spellID de la whitelist active (joueur
-- uniquement). Chaque slot expose son auraButton natif via ns.GetNativeAuraButton, que
-- ApplyNativeAuraBindings (Debuffs.lua/Cooldowns.lua/Procs.lua) utilise pour brancher
-- SetDurationCooldown/SetApplicationCount sur le Cooldown/FontString deja existants de la ligne
-- AishCore. Ce systeme ne pilote PAS la presence/Show-Hide (ns._lastKnownAura, Scan.lua, reste la
-- source de verite) -- uniquement la fiabilite combat-safe des stacks et du cooldown de duree pour
-- une ligne deja affichee.
local container
local slotKeyBySpell = {}  -- [spellID] = "aishNativeN" -- evite de recreer un slot deja existant
local slotCounter = 0

-- PRESENCE COMBAT-SAFE PAR HOOK OnShow/OnHide : TENTE ET ABANDONNE. Icone/cooldown/stacks se creent
-- sans probleme, mais auraButton:HookScript("OnShow"/"OnHide") echoue toujours ("blocked by secret
-- aspects") des que l'aura peut devenir secrete -- restriction plateforme confirmee, pas contournable
-- (contrairement au hooksecurefunc qui marche pour le CDM, cf. CDMHooks.lua). hooksecurefunc sur les
-- methodes Show/Hide ne marche pas non plus : Blizzard pilote la visibilite cote C. Ce fichier affiche
-- donc l'aura sans jamais SAVOIR en Lua qu'elle est presente ; ns._lastKnownAura (Scan.lua) reste la
-- meilleure approximation, et le CDM natif (ns.PinAuraToCDM) le seul canal combat-safe fiable.

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

-- TEST ISOLE : /aishdebug testcontainer <spellID> -- valide en jeu, sans toucher au pipeline
-- Debuffs.lua/Scan.lua, que AuraContainer peut piloter icone+stacks+duree pour un spellID avant
-- d'investir dans le raccordement complet. AddAuraSlot (un spellID = un bouton fixe), candidateFilters
-- vide puis rempli via SetAuraSlotCandidateFilters, initializeFrame cree tout UNE SEULE FOIS (l'AuraButton
-- devient "forbidden" des que secret). Conteneur cree une seule fois, hors combat uniquement.
local testContainer, testSlotKey = nil, "aishTestSlot"

function ns.DebugTestNativeContainer(spellIDs)
    local P = function(s) print("|cff33aaff[TestContainer]|r " .. s) end
    -- Accepte un spellID unique ou une liste -- plusieurs IDs sert a tester l'hypothese "chaine de
    -- sorts par palier" (ex. Precurseur du Vide : plusieurs spellID, peut-etre des rangs d'un meme
    -- concept), ou un seul spellID ferait disparaitre l'icone au changement de palier.
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

                        -- Barre de duree testee ici en isolation avant de la cabler dans le rendu "icons".
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

-- TEST ISOLE : /aishdebug testbar <spellID> -- prepare la migration de "Circle Bars" (Buffs.lua, cle
-- interne freebars, a ne pas confondre avec "circlebars"/Cooldowns.lua = "Free Bars") : lignes a
-- POSITION FIXE (pas de flow layout comme Icons), aucune icone, juste des StatusBar. Deux inconnues
-- testees ici : AddAuraGroup fonctionne-t-il sans jamais appeler les API de flow layout, avec un
-- positionnement 100% manuel ? Et SetDurationBar fonctionne-t-il sans icone/cooldown/stacks du tout ?
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

        -- Ordre important : SetEnabled/SetUnit/Show AVANT AddAuraGroup (ordre du rendu "icons" qui
        -- fonctionne) -- l'inverse est une cause possible de "barre jamais alimentee".
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
                        -- Circle Bars a besoin de deux barres miroir (meme duree) -- test si
                        -- SetDurationBar alimente les DEUX cibles ou seulement la derniere appelee.
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

-- TEST ISOLE : /aishdebug testmulti <spellID1> <spellID2> -- prepare la reponse a "2 buffs actifs en
-- meme temps => toutes les barres Circle Bars disparaissent". Teste en isolation, sans les complexites
-- propres a Circle Bars, si un AddAuraGroup avec maxFrameCount=3 peut afficher 2 candidats simultanement.
-- Si le bug se reproduit ici, c'est une limitation Blizzard generale, pas specifique a Circle Bars.
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

                        -- PAS de SetPoint manuel -- laisse Blizzard positionner via SetFlowLayout* (comme Circle Bars).
                        auraButton:SetSize(150, 150)

                        local bg = auraButton:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(); bg:SetColorTexture(col[1], col[2], col[3], 0.5)

                        local label = auraButton:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
                        label:SetPoint("CENTER")
                        label:SetText("#" .. tostring(idx))

                        -- Deux StatusBar via SetDurationBar (comme Circle Bars barL+barR) : teste si
                        -- 2 barres/bouton combine a plusieurs boutons actifs casse le groupe entier.
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

        -- Meme fix que Circle Bars : laisser Blizzard positionner via SetFlowLayout* (le champ
        -- "layout" ci-dessus force son activation) plutot qu'un SetPoint manuel en conflit avec le flow.
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

-- TEST ISOLE : /aishdebug testpercolor <spellID1> <spellID2> -- peut-on colorer barre/glow PAR SORT ?
-- Aujourd'hui NON : chaque destination utilise un seul AddAuraGroup partage avec un pool de boutons
-- reutilises dynamiquement, le style etant pose une seule fois a la creation (retoucher un widget deja
-- lie casse les bindings). Piste : un AddAuraGroup DEDIE PAR SORT (maxFrameCount=1, un seul spellID en
-- filtre) fixerait un bouton par sort et permettrait de lire son style depuis la config par sort.
-- Inconnues : plusieurs AddAuraGroup sur le meme conteneur coexistent-ils et partagent-ils le flow layout ?
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

-- Couleur/glow PAR SORT -- helpers partages par Icons/Free Bars/Icon List (pas Circle Bars, qui a son
-- propre CBApplySpellColor avec support degrade). Declares ici, avant toute section qui les utilise :
-- portee lexicale Lua, doivent preceder la premiere section appelante dans le fichier.

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

-- Glow PAR SORT : l'override uniforme du render (glowOverrideIdx>1) reste prioritaire, sinon repli sur
-- le glow propre au sort (si.glow+si.glowIdx>1, "Auras a tracker"), sinon aucun glow -- fidele a
-- l'ancien pipeline Lua (hasGlow = aura.spellGlow and glIdx and glIdx > 1).
local function ApplySpellGlow(glowAnchor, cfg, si, w, h)
    if not (glowAnchor and ns.ShowGlow and cfg.glowEnabled ~= false) then return end
    -- Override render desactive via `false and` (jamais supprime) : "Auras a tracker" reste la seule
    -- source de verite pour le glow, meme si glowOverrideIdx est deja stocke en DB (cf. Render.lua).
    if false and cfg.glowOverrideIdx and cfg.glowOverrideIdx > 1 then
        local color = cfg.glowOverrideR ~= nil
            and { cfg.glowOverrideR, cfg.glowOverrideG or 0.5, cfg.glowOverrideB or 0.5 }
            or nil
        pcall(ns.ShowGlow, glowAnchor, cfg.glowOverrideIdx, color, cfg.glowOverrideAlpha, cfg.glowOverrideScale, w, h)
    elseif si and si.glow and si.glowIdx and si.glowIdx > 1 then
        -- Meme chaine de repli que l'apercu du picker (Tactics.lua) : sans le repli sur si.color, un
        -- glow active sans couleur explicite retombait sur ns.barColor au lieu de la couleur du sort.
        local color = si.glowColor or si.color
        pcall(ns.ShowGlow, glowAnchor, si.glowIdx, color, si.glowAlpha, si.glowScale, w, h)
    end
end

-- Texte de duree personnalise : style + repositionne le countdown NATIF d'un Cooldown (cf.
-- ns._StyleCountdownFS, Debuffs.lua) -- on ne retouche que le style du FontString, jamais sa valeur
-- (remplie cote C++). relFrame : l'icone pour Icons/Free Bars/Icon List, le conteneur de barre pour
-- Circle Bars (pas d'icone).
local function ApplyNativeCountdownStyle(cd, cfg, relFrame)
    if not (cd and ns._StyleCountdownFS) then return end
    local pos = cfg.timerPos or "CENTER"
    pcall(ns._StyleCountdownFS, cd, cfg.timerFont or ns.Media.font, cfg.timerSize or 12,
        cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
        pos, relFrame, pos, cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
end

-- Animation d'entree du glow ("Proc: White Short" etc) : ns.PlayProcStart (Debuffs.lua) est un
-- flourish joue une fois quand une aura passe d'inactive a active (distinct du glow en boucle continue,
-- memes reglages "Auras a tracker"). Piege : `auraButton:HookScript("OnShow", ...)` est bloque
-- ("blocked by secret aspects") des qu'un widget natif est lie a une aura secrete, et sans pcall cette
-- erreur ferait echouer toute la creation du bouton. Repli : jouer le flourish une seule fois,
-- directement dans initializeFrame (appele une seule fois par bouton) -- ne rejoue pas aux
-- reapparitions suivantes du buff, faute d'evenement observable non bloque.
-- Pools de boutons natifs Icons/Free Bars/Icon List, forward-declares pour etre visibles par
-- ProcGlowTick ci-dessous. Circle Bars exclue (pas d'icone, pas de glow possible).
local iconsFlowButtons, freeBarsFlowButtons, iconListFlowButtons = {}, {}, {}

-- Etat de presence par spellID, seede a la creation du bouton pour eviter un double flourish si le
-- ticker tombe juste apres sur son premier tick avec l'aura deja active.
local _procGlowWasPresent = {}

local function PlayProcStartOnce(glowAnchor, si, spellID)
    if not (ns.PlayProcStart and glowAnchor and si and si.procGlowIdx and si.procGlowIdx > 1) then return end
    local color = si.glowColor or si.color
    pcall(ns.PlayProcStart, glowAnchor, si.procGlowIdx, color, si.procGlowScale)
    if spellID then _procGlowWasPresent[spellID] = true end
end

-- Retrigger du flourish a chaque (re)apparition de l'aura : PlayProcStartOnce ne joue qu'a la creation
-- du bouton, jamais aux reapparitions suivantes, faute d'evenement OnShow exploitable (bloque comme
-- ci-dessus). Solution : ticker leger decouple du widget natif, suit la presence de chaque spellID via
-- ns.IsCDMAuraSwipePresent (CDMHooks.lua, event-driven, jamais de lecture de valeur secrete). Sur une
-- transition false->true, rejoue le flourish sur tous les boutons dedies dans toutes les destinations
-- qui trackent ce spellID (Circle Bars exclue, pas d'icone/glow).
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

-- Spark natif : contrairement au glow, le spark doit suivre le bord mobile d'une StatusBar dont le
-- remplissage est pilote par Blizzard en interne (SetDurationBar, valeur secrete, illisible en Lua).
-- Solution : ancrer le centre de la texture du spark sur le bord (LEFT/RIGHT) de
-- bar:GetStatusBarTexture() -- la texture de remplissage elle-meme -- une seule fois, jamais en
-- OnUpdate. L'ancrage se reevalue chaque frame contre l'etendue live de la region (redimensionnee
-- cote C++), donc le spark suit le remplissage sans qu'aucune valeur ne transite par notre Lua -- meme
-- recette que le Pip natif du CDM (ancre une fois dans OnLoad).
-- tipEdge ("LEFT"/"RIGHT") : cote ou se trouve le bord mobile de cette barre, determine par son
-- SetReverseFill (reverse=true => mobile a gauche), a fournir par l'appelant.
-- matchBarRGB : couleur deja resolue de la barre (utilisee si cfg.sparkSameAsBar, prioritaire sur
-- sparkColorR/G/B). La texture du spark n'est jamais liee a une donnee secrete (contrairement a la
-- StatusBar), donc la retoucher a chaque refresh est toujours sans risque.
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

-- Grille native "flow" pour la destination "icons" (Procs.lua). Remplace un ancien systeme a deux
-- rendus paralleles qui se superposaient (Procs.lua manuel + filet de secours) : SetDurationCooldown
-- couvre aussi les auras sans duree lisible autrement.
-- Principe : un seul AddAuraGroup partage par tous les sorts, avec le layout FLOW natif Blizzard
-- (meme API que CooldownManager) -- Blizzard anime le compactage cote C++, seul moyen d'obtenir ce
-- comportement puisque Lua ne peut pas observer quels boutons secrets sont actifs.
-- Limitation acceptee : un AddAuraGroup reutilise ses boutons entre sorts, sans setter "SetGlow" natif
-- -- le glow ne peut donc pas etre personnalise par sort, un seul style (override) s'applique partout.
local iconsFlowContainer
local iconsFlowGroupAdded = false
iconsFlowButtons = {}   -- liste des auraButton natifs deja crees (pour re-appliquer un style plus tard) -- forward-declaree plus haut (ProcGlowTick)
-- [spellID] = true des qu'un AddAuraGroup dedie a ete cree pour ce sort (couleur/glow par sort).
-- Chaque auraButton memorise aussi son spellID (._aishSpellID) pour qu'ApplyIconsFlowButtonStyle
-- retrouve sa config a chaque refresh GUI, pas seulement a la creation.
local iconsPerSpellGroups = {}

-- Presence via les boutons natifs : impossible. auraButton:IsShown() est lisible hors combat mais la
-- valeur est secrete, et l'objet devient interdit des l'entree en combat. Le seul canal combat-safe
-- reste le CDM (CDMHooks.lua), sort epingle et viewer active en Edit Mode (masque par alpha).

-- Print de secours : n'affiche que les echecs reels, pas de trace de fonctionnement normal (pollution
-- du chat a chaque /reload). Diagnostic complet a la demande via /aishdebug iconsflow.
local function DBG(s) print("|cff33aaff[IconsFlow]|r " .. tostring(s)) end

-- Conteneur natif "icons" (peut etre nil). Utilise par Animation.lua (ns.UpdateRenderFade) pour
-- rediriger le fade combat/hors-combat sur le VRAI conteneur affiche : ns.renderFrames.icons.container
-- pointe vers l'ancien conteneur manuel de Procs.lua, definitivement cache (alpha=0).
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

    -- Deplacement Alt+clic gauche, meme pattern que les autres renders. Le conteneur AuraContainer
    -- lui-meme n'est jamais "forbidden" (seuls les AuraButton enfants le deviennent) -- SetPoint/
    -- StartMoving dessus restent surs. Ancrage par bord selon growth : meme compensation par direction
    -- de croissance que Circle Bars/Free Bars/Icon List (cf. OnMouseUp ci-dessous).
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
            SafeSetPropagateMouseClicks(s, false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    iconsFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        SafeSetPropagateMouseClicks(s, true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Une fois ce conteneur lie a une vraie aura secrete via un bouton enfant, GetCenter()/GetSize()
        -- sur le conteneur peuvent aussi renvoyer des valeurs secretes (taint propage). pcall autour du
        -- calcul : si secret, abandon silencieux (impossible de sauvegarder cette fois) plutot que crash.
        if cx and cy and ns.db and ns.db.icons then
            pcall(function()
                local w, h = s:GetSize()
                local gr = ns.db.icons.growth or "LEFT"
                local saveX = cx * sc - sx
                local saveY = cy * sc - sy
                -- Compense le decalage centre->bord selon l'ancre utilisee au restore -- meme calcul
                -- que Circle Bars/Free Bars/Icon List.
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

-- Applique le style courant (ns.db.icons) a un auraButton deja cree, sans jamais recreer ses enfants --
-- uniquement retoucher leurs proprietes. Appelee a la creation ET a chaque changement de reglage GUI
-- (ns.RefreshIconsNativeGridStyle) : un AddAuraGroup ne rappelle initializeFrame qu'une seule fois par
-- bouton, donc sans ce refresh les sliders/checkbox (taille, glow, swipe, duree) resteraient sans effet.
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
            -- Swipe cooldown : meme reglage/comportement que les autres destinations.
            cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
            cd:SetDrawEdge(liveCfg.swipeEnabled == true)
            -- Texte de duree delegue au compteur natif du widget Cooldown, jamais calcule par nous --
            -- seul moyen d'afficher la duree sans lire la valeur secrete d'expiration (GetAuraDuration/
            -- instID CDM bloques meme hors combat ici). Blizzard remplit le texte cote C++ des que
            -- SetDurationCooldown est lie ; ApplyNativeCountdownStyle ne retouche que le style.
            cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
            if liveCfg.timerIconEnabled then
                ApplyNativeCountdownStyle(cd, liveCfg, auraButton)
            end
        end

        -- Config par sort : chaque bouton est dedie a un seul spellID (._aishSpellID, pose a la
        -- creation), ce qui permet une couleur de barre/glow fixes par sort (SpellBarColorRGB/ApplySpellGlow).
        local liveSpells = ns.GetSpecSpells()
        local liveSi = auraButton._aishSpellID and liveSpells and liveSpells[auraButton._aishSpellID]

        if auraButton._aishDurBar then
            local bar = auraButton._aishDurBar
            -- Jamais SetStatusBarTexture/SetReverseFill ici : bar est deja liee a une duree secrete via
            -- SetDurationBar, et y toucher apres coup fait echouer tout le pcall englobant (empechant
            -- silencieusement le glow de se reappliquer). SetStatusBarColor seul reste sans risque.
            local cR, cG, cB = SpellBarColorRGB(liveCfg, liveSi)
            bar:SetStatusBarColor(cR, cG, cB)
            -- Spark : texture propre a l'addon, jamais secrete, toujours sure a retoucher.
            if auraButton._aishSpark then
                pcall(ApplyNativeBarSparkColor, auraButton._aishSpark, liveCfg, {cR, cG, cB})
            end
        end

        if ns.HideGlow then pcall(ns.HideGlow, auraButton) end
        -- liveIw/liveIh explicites : auraButton:GetSize() peut renvoyer une valeur secrete une fois
        -- lie a une vraie aura ; on connait deja la taille (SetSize juste au-dessus).
        local okGlow, errGlow = pcall(ApplySpellGlow, auraButton, liveCfg, liveSi, liveIw, liveIh)
        if not okGlow then
            DBG(string.format("|cffff4444ApplyIconsFlowButtonStyle: ApplySpellGlow a echoue -- err=%s|r", tostring(errGlow)))
        end
    end)
    if not okStyle then
        DBG(string.format("|cffff4444ApplyIconsFlowButtonStyle: bloc principal a echoue -- err=%s|r", tostring(errStyle)))
    end
end

-- A appeler depuis le GUI a chaque changement de reglage affectant l'apparence des icones "icons".
-- Hors combat uniquement par prudence (les boutons deviennent "forbidden" des qu'une aura secrete leur
-- est assignee) ; en pratique le GUI n'est jamais ouvert en combat.
function ns.RefreshIconsNativeGridStyle()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, btn in ipairs(iconsFlowButtons) do
        ApplyIconsFlowButtonStyle(btn)
    end
end

-- Traduit ns.db.icons.growth (LEFT/RIGHT/UP/DOWN, meme semantique que l'ancien Procs.lua) vers les
-- parametres natifs SetFlowLayout*. LEFT/RIGHT valides en jeu ; UP/DOWN moins teste.
local function GrowthToFlowParams(growth)
    if growth == "RIGHT" then return "TOPLEFT", 1, -1, true
    elseif growth == "UP" then return "BOTTOMLEFT", 1, 1, false
    elseif growth == "DOWN" then return "TOPLEFT", 1, -1, false
    else return "TOPRIGHT", -1, -1, true end -- LEFT (defaut)
end

-- SetFlowLayoutAxis n'accepte pas la chaine "HORIZONTAL"/"VERTICAL" (rejetee : "layoutAxis must be
-- valid") -- la forme numerique fonctionne pour l'axe horizontal (0) ; l'axe vertical (1) suit la meme
-- numerotation mais n'a jamais ete exerce en jeu. Formes candidates gardees en repli silencieux.
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

-- Masquage contextuel : ne jamais montrer les 4 destinations natives en vehicule/taxi/combat de
-- mascotte/cutscene -- ces contextes sont ceux ou le bug "buff hors whitelist affiche partout" a ete
-- rapporte. Verifications API Blizzard propres, chacune protegee par pcall. _addon.skyridingActive
-- (namespace racine, pas ns) reutilise le signal deja maintenu par Modules/Skyriding.lua.
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
    -- Ancrage PAR BORD (evite que les icones "bougent des 2 cotes" au changement du nombre d'icones
    -- actives) : le conteneur se redimensionne dynamiquement pour coller au flow, donc le bord cense
    -- rester fixe (cote de l'ancre du flow) doit etre le point d'ancrage du conteneur lui-meme --
    -- exactement comme Circle Bars/Free Bars/Icon List (un ancrage CENTER ferait deriver les 2 bords).
    local growth0 = cfg.growth or "LEFT"
    local x0, y0 = cfg.x or -199, cfg.y or -247
    if growth0 == "UP" then c:SetPoint("BOTTOM", UIParent, "CENTER", x0, y0)
    elseif growth0 == "DOWN" then c:SetPoint("TOP", UIParent, "CENTER", x0, y0)
    elseif growth0 == "RIGHT" then c:SetPoint("LEFT", UIParent, "CENTER", x0, y0)
    else c:SetPoint("RIGHT", UIParent, "CENTER", x0, y0) end -- LEFT (defaut)

    -- Tout ce qui suit doit rester individuellement pcall-protege (pas la fonction entiere) : un appel
    -- non protege avant les SetFlowLayout* ferait planter silencieusement toute la suite (plus aucune
    -- icone affichee, sans message d'erreur). Le layout flow passe donc toujours en premier.
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
    -- Ligne unique volontairement surdimensionnee : jamais de retour a la ligne, tout tient sur un
    -- seul axe de flow (comme l'ancien rendu).
    local ok4, err4 = pcall(c.SetFlowLayoutMaximumLineSize, c, (itemSize + rg) * count + rg)

    if not (ok1 and ok2 and ok3 and ok4) then
        DBG(string.format("|cffff4444RepositionIconsNativeGrid: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            ok1 and "ok" or tostring(err1), ok2 and "ok" or tostring(err2), ok3 and "ok" or tostring(err3), ok4 and "ok" or tostring(err4)))
    end

    -- pcall par prudence, pour ne jamais laisser une erreur ici avaler le reste de la fonction.
    pcall(function()
        if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
            if ns.UpdateRenderFade then ns.UpdateRenderFade("icons") else c:SetAlpha(1) end
        else
            c:SetAlpha(0)
        end
    end)

    -- Re-applique le style a tous les boutons deja crees (cf. ApplyIconsFlowButtonStyle).
    pcall(function() if ns.RefreshIconsNativeGridStyle then ns.RefreshIconsNativeGridStyle() end end)
end

-- Cree (une seule fois) ou met a jour le groupe natif partage par tous les sorts de la destination
-- "icons". Appelee depuis Whitelist.lua/BuildWhitelist. Cible uniquement les auras du joueur.
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
    -- Reserve la place de la barre de duree (si activee) dans le slot du flow layout, sinon le
    -- conteneur (auto-dimensionne) rogne la barre qui depasse sous/sur l'icone.
    local elementH = ih
    if cfg.showBarUnderIcon then elementH = ih + (cfg.rowGap or 2) + (cfg.barUnderHeight or 3) end
    local spells = ns.GetSpecSpells()

    -- Pas de cap ici (contrairement a Circle Bars/Free Bars/Icon List) : "icons" n'a jamais eu de
    -- reglage "maxBars", tous les sorts traques obtiennent chacun leur groupe dedie.
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
                            -- NE PAS remplir icon:SetTexture() nous-memes : Blizzard remplit l'image en
                            -- interne des que SetIcon() est associe a un vrai candidat.
                            auraButton:SetIcon(icon)

                            -- Bordure sous l'icone (BACKGROUND < ARTWORK) : un remplissage opaque en
                            -- OVERLAY masquait totalement l'icone (bug "carres noirs" confirme en jeu).
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
                            -- Le font DOIT etre pose avant SetApplicationCount : Blizzard touche le
                            -- texte synchroniquement des l'appel, et un FontString sans 3e argument n'a
                            -- aucun font tant qu'on ne lui en assigne pas un.
                            ns.ApplyFont(stackFS, liveCfgAtCreate.stackFont or ns.Media.font, liveCfgAtCreate.stackSize or 10, "OUTLINE")
                            stackFS:SetJustifyH("RIGHT")
                            auraButton:SetApplicationCount(stackFS, {})
                            auraButton._aishStackFS = stackFS

                            -- Barre de duree, couleur par sort.
                            if liveCfgAtCreate.showBarUnderIcon then
                                local barH = liveCfgAtCreate.barUnderHeight or 3
                                local gp = liveCfgAtCreate.rowGap or 2
                                -- durBar est un enfant direct de auraButton (comme Free Bars/Circle
                                -- Bars/Liste d'icones) : necessaire pour que le spark s'affiche correctement.
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
                                -- direction=RemainingTime : sans cette option, la barre se remplit au lieu de se vider.
                                local okDurBar, errDurBar = pcall(auraButton.SetDurationBar, auraButton, durBar,
                                    { direction = Enum.StatusBarTimerDirection.RemainingTime })
                                if not okDurBar then
                                    DBG(string.format("|cffff4444initializeFrame (sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errDurBar)))
                                end
                                auraButton._aishDurBar = durBar
                                -- Spark : bord mobile oppose au cote d'origine du remplissage.
                                auraButton._aishSpark = MakeNativeBarSpark(durBar, liveCfgAtCreate,
                                    (liveCfgAtCreate.barReverseFill == true) and "LEFT" or "RIGHT", {cR, cG, cB})
                            end

                            iconsFlowButtons[#iconsFlowButtons + 1] = auraButton
                        end)
                        if not okBuild then
                            DBG(string.format("|cffff4444initializeFrame (sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                        end
                        -- Taille/glow/swipe/texte de duree/stacks : appliques via ApplyIconsFlowButtonStyle.
                        ApplyIconsFlowButtonStyle(auraButton)
                        -- Animation d'entree du glow jouee une seule fois ici (pas dans
                        -- ApplyIconsFlowButtonStyle, qui rejouerait le flourish a chaque refresh GUI).
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
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis re-trace depuis (spec
            -- change, transition de zone/cutscene) -- sinon il resterait bloque sur le filtre "poison".
            pcall(c.SetAuraGroupCandidateFilters, c, "aishIconsFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques : leur groupe dedie existe toujours (impossible a supprimer) donc on le
    -- neutralise avec un filtre sur un spellID bidon -- jamais {}, qui signifie "aucune restriction"
    -- cote Blizzard et ferait matcher TOUTES les auras du joueur (cause des "auras aleatoires hors
    -- whitelist" observees en cutscene).
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

-- Grille native "flow" cible pour la destination "icons" (debuffs cible). Miroir exact de la grille
-- joueur, mais SetUnit("target") + filtre "HARMFUL" -- seule technique combat-safe pour un debuff cible
-- (meme recette que TargetAuras.lua). Ne route que les sorts info.source == "debuff" ; les buffs joueur
-- restent geres par le conteneur ci-dessus, inchange. Conteneur independant (un AuraContainer n'a qu'un
-- seul SetUnit) positionne juste sous la rangee joueur -- les deux flows ne se compactent pas ensemble.
local iconsFlowContainerTarget
local iconsFlowButtonsTarget = {}
local iconsPerSpellGroupsTarget = {}

function ns.GetIconsNativeContainerTarget()
    return iconsFlowContainerTarget
end

local function EnsureIconsFlowContainerTarget()
    if iconsFlowContainerTarget then return iconsFlowContainerTarget end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        DBG(string.format("|cffff4444EnsureIconsFlowContainerTarget: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    iconsFlowContainerTarget = result
    iconsFlowContainerTarget:SetSize(8, 8)
    local okEn, errEn = pcall(iconsFlowContainerTarget.SetEnabled, iconsFlowContainerTarget, true)
    local okUn, errUn = pcall(iconsFlowContainerTarget.SetUnit, iconsFlowContainerTarget, "target")
    if not okEn or not okUn then
        DBG(string.format("|cffff4444EnsureIconsFlowContainerTarget: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    iconsFlowContainerTarget:Show()
    return iconsFlowContainerTarget
end

-- Meme style que ApplyIconsFlowButtonStyle (joueur), factoree separement pour ne jamais toucher aux
-- widgets/variables du pool joueur.
local function ApplyIconsFlowButtonStyleTarget(auraButton)
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
            cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
            cd:SetDrawEdge(liveCfg.swipeEnabled == true)
            cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
            if liveCfg.timerIconEnabled then
                ApplyNativeCountdownStyle(cd, liveCfg, auraButton)
            end
        end

        local liveSpells = ns.GetSpecSpells()
        local liveSi = auraButton._aishSpellID and liveSpells and liveSpells[auraButton._aishSpellID]

        if auraButton._aishDurBar then
            local bar = auraButton._aishDurBar
            local cR, cG, cB = SpellBarColorRGB(liveCfg, liveSi)
            bar:SetStatusBarColor(cR, cG, cB)
            if auraButton._aishSpark then
                pcall(ApplyNativeBarSparkColor, auraButton._aishSpark, liveCfg, {cR, cG, cB})
            end
        end

        if ns.HideGlow then pcall(ns.HideGlow, auraButton) end
        local okGlow, errGlow = pcall(ApplySpellGlow, auraButton, liveCfg, liveSi, liveIw, liveIh)
        if not okGlow then
            DBG(string.format("|cffff4444ApplyIconsFlowButtonStyleTarget: ApplySpellGlow a echoue -- err=%s|r", tostring(errGlow)))
        end
    end)
    if not okStyle then
        DBG(string.format("|cffff4444ApplyIconsFlowButtonStyleTarget: bloc principal a echoue -- err=%s|r", tostring(errStyle)))
    end
end

function ns.RefreshIconsNativeGridStyleTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, btn in ipairs(iconsFlowButtonsTarget) do
        ApplyIconsFlowButtonStyleTarget(btn)
    end
end

-- Repositionne le conteneur cible juste sous le conteneur joueur (meme geometrie/flow, decale d'une
-- hauteur de ligne) -- appelee depuis Whitelist.lua juste apres ns.RepositionIconsNativeGrid (joueur).
function ns.RepositionIconsNativeGridTarget()
    local c = iconsFlowContainerTarget or EnsureIconsFlowContainerTarget()
    if not c then return end
    local cPlayer = iconsFlowContainer
    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    local growth = cfg.growth or "LEFT"
    local anchorPoint, hDir, vDir, isH = GrowthToFlowParams(growth)

    c:ClearAllPoints()
    local iw, ih = cfg.iconW or 26, cfg.iconH or 26
    local rg = cfg.rowGap or 2
    -- Empile la rangee cible SOUS la rangee joueur (ou a sa position
    -- habituelle decalee si le conteneur joueur n'existe pas encore).
    if cPlayer then
        if growth == "UP" then
            c:SetPoint("BOTTOM", cPlayer, "TOP", 0, rg)
        else
            c:SetPoint("TOP", cPlayer, "BOTTOM", 0, -rg)
        end
    else
        local x0, y0 = cfg.x or -199, cfg.y or -247
        c:SetPoint(anchorPoint == "TOPRIGHT" and "RIGHT" or "LEFT", UIParent, "CENTER", x0, y0 - (ih + rg))
    end

    local ok1, err1 = pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
    local ok2 = SetFlowAxisSmart(c, isH)
    local ok3, err3 = pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
    local order = ns.slotOrderByDest and ns.slotOrderByDest.icons
    local count = math.max(order and #order or 0, 1)
    local itemSize = isH and iw or ih
    local ok4, err4 = pcall(c.SetFlowLayoutMaximumLineSize, c, (itemSize + rg) * count + rg)
    if not (ok1 and ok2 and ok3 and ok4) then
        DBG(string.format("|cffff4444RepositionIconsNativeGridTarget: SetFlowLayout* a echoue -- anchor=%s growth=%s maxline=%s|r",
            ok1 and "ok" or tostring(err1), ok3 and "ok" or tostring(err3), ok4 and "ok" or tostring(err4)))
    end

    local visible = (cfg.iconsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    pcall(function()
        if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
            c:SetAlpha(1)
        else
            c:SetAlpha(0)
        end
    end)
    pcall(ns.RefreshIconsNativeGridStyleTarget)
end

-- Cree (une seule fois par sort) le groupe natif dedie pour chaque debuff
-- cible de la destination "icons" (info.source == "debuff"). Appelee depuis
-- Whitelist.lua juste apres ns.EnsureIconsNativeGrid (joueur).
function ns.EnsureIconsNativeGridTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureIconsFlowContainerTarget()
    if not c then return end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.icons
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    local iw, ih = cfg.iconW or 26, cfg.iconH or 26
    local rg = cfg.rowGap or 2
    local elementH = ih
    if cfg.showBarUnderIcon then elementH = ih + (cfg.rowGap or 2) + (cfg.barUnderHeight or 3) end
    local spells = ns.GetSpecSpells()

    local currentSet = {}
    for _, spellID in ipairs(order) do
        local info = spells and spells[spellID]
        if info and info.source == "debuff" then
            currentSet[spellID] = true
            if not iconsPerSpellGroupsTarget[spellID] then
                local groupKey = "aishIconsFlowTarget_" .. tostring(spellID)
                local okAdd, errAdd = pcall(function()
                    c:AddAuraGroup(groupKey, "HARMFUL|PLAYER", {
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
                                auraButton:SetIcon(icon)

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
                                ns.ApplyFont(stackFS, liveCfgAtCreate.stackFont or ns.Media.font, liveCfgAtCreate.stackSize or 10, "OUTLINE")
                                stackFS:SetJustifyH("RIGHT")
                                auraButton:SetApplicationCount(stackFS, {})
                                auraButton._aishStackFS = stackFS

                                if liveCfgAtCreate.showBarUnderIcon then
                                    local barH = liveCfgAtCreate.barUnderHeight or 3
                                    local gp = liveCfgAtCreate.rowGap or 2
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
                                    local okDurBar, errDurBar = pcall(auraButton.SetDurationBar, auraButton, durBar,
                                        { direction = Enum.StatusBarTimerDirection.RemainingTime })
                                    if not okDurBar then
                                        DBG(string.format("|cffff4444initializeFrame cible (sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errDurBar)))
                                    end
                                    auraButton._aishDurBar = durBar
                                    auraButton._aishSpark = MakeNativeBarSpark(durBar, liveCfgAtCreate,
                                        (liveCfgAtCreate.barReverseFill == true) and "LEFT" or "RIGHT", {cR, cG, cB})
                                end

                                iconsFlowButtonsTarget[#iconsFlowButtonsTarget + 1] = auraButton
                            end)
                            if not okBuild then
                                DBG(string.format("|cffff4444initializeFrame cible (sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                            end
                            ApplyIconsFlowButtonStyleTarget(auraButton)
                            do
                                local liveSpells2 = ns.GetSpecSpells()
                                PlayProcStartOnce(auraButton, liveSpells2 and liveSpells2[spellID], spellID)
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
                    DBG(string.format("|cffff4444AddAuraGroup DEDIE cible (sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
                end
                iconsPerSpellGroupsTarget[spellID] = true
                if c.UpdateAllAuras then
                    local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                    if not okUpd then DBG(string.format("|cffff4444UpdateAllAuras cible (sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
                end
            else
                pcall(c.SetAuraGroupCandidateFilters, c, "aishIconsFlowTarget_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
            end
        end
    end

    for spellID in pairs(iconsPerSpellGroupsTarget) do
        if not currentSet[spellID] then
            local groupKey = "aishIconsFlowTarget_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

-- Rafraichit le conteneur cible quand la cible change -- Blizzard ne relie
-- pas forcement l'affichage tout seul sans un coup de pouce (meme
-- precaution que TargetAuras.lua::OnEvent sur PLAYER_TARGET_CHANGED).
local iconsTargetChangeFrame = CreateFrame("Frame")
iconsTargetChangeFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
iconsTargetChangeFrame:SetScript("OnEvent", function()
    if iconsFlowContainerTarget and iconsFlowContainerTarget.UpdateAllAuras then
        pcall(iconsFlowContainerTarget.UpdateAllAuras, iconsFlowContainerTarget)
    end
end)

-- Print de secours dedie a cette section, prefixe distinct de DBG (icons) pour eviter la confusion.
local function CBDBG(s) print("|cff33aaff[CircleBarsFlow]|r " .. tostring(s)) end

-- Grille native pour "Circle Bars" (Buffs.lua, cle interne freebars -- l'onglet GUI "Circle Bars" est
-- backe par Buffs.lua/freebars, PAS par Cooldowns.lua/circlebars qui est en fait "Free Bars"). Meme
-- methodologie que "icons", mais sans icone : deux StatusBar miroir (gauche/droite) par ligne montrant
-- la meme duree. Confirme en jeu via /aishdebug testbar avant d'ecrire ce code : SetDurationBar
-- fonctionne sans icone/cooldown/stacks et peut etre appele 2x sur le meme bouton (les deux se
-- remplissent) ; aucun SetFlowLayout* necessaire mais le champ "layout" doit quand meme etre fourni a
-- AddAuraGroup (son absence empechait plusieurs candidats simultanes de s'afficher) ; SetEnabled/
-- SetUnit/Show doivent rester avant AddAuraGroup ; le foreground qui grandit par defaut se resout via
-- direction=RemainingTime (SetReverseFill seul ne suffit pas).
-- Compactage : un AddAuraGroup partage ne permet que le compactage natif, Blizzard decide en interne
-- quel membre du pool affiche quel sort, sans ordre de priorite garanti -- comportement accepte. Chaque
-- bouton recoit une position ecran fixe (rang N, alternance haut/bas) une seule fois a la creation.
local circleBarsFlowContainer
local circleBarsFlowGroupAdded = false
local circleBarsFlowButtons = {}
local circleBarsSlotCounter = 0  -- attribue un rang fixe a chaque bouton du pool, une seule fois, a la creation
-- [spellID] = true des qu'un AddAuraGroup dedie a ete cree pour ce sort ("couleur par sort"), remplace
-- un ancien groupe unique partage (cf. EnsureCircleBarsNativeGrid plus bas). Un groupe ne peut pas etre
-- supprime une fois cree, seulement vide via candidateFilters={includeSpellIDs={}} si decoche plus tard.
local circleBarsPerSpellGroups = {}

-- Colorisation avec degrade : copie minimale de _SetBarGradient/_ResetBarGradient (Core/Init.lua), pas
-- exposees sur ns, plus simple de dupliquer ces 2 lignes que d'exporter pour un seul appelant.
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

-- Applique la couleur/degrade d'une barre en tenant compte du sort dedie -- meme priorite que l'ancien
-- pipeline Lua (ns.ApplyBarColor) : 1) cfg.spellGradients[spellID] (freebars uniquement, prioritaire),
-- 2) cfg.barColorR explicite, 3) ns.db.useSpellColors + si.color, 4) repli ns.barColor. Le degrade
-- uniforme du render ne s'applique que si aucun override par sort n'est actif. Appele une seule fois a
-- la creation du bouton, pas de re-application par scan.
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

    -- Position/taille reelles ici, avant tout le reste (pas un SetSize provisoire) : SetPoint/SetSize
    -- doivent toujours preceder AddAuraGroup et le premier UpdateAllAuras, sinon celui-ci s'execute sur
    -- un conteneur sans ancrage (cause du bug "2 buffs actifs = tout disparait").
    local cfg0 = ns.db and ns.db.freebars or ns.Defaults.freebars
    local maxBars0 = cfg0.maxBars or 8
    local bw0, bh0, gp0, rg0 = cfg0.barW or 45, cfg0.barH or 3, cfg0.gap or 50, cfg0.rowGap or 6
    circleBarsFlowContainer:SetSize(bw0 * 2 + gp0 * 2, maxBars0 * (bh0 + rg0))
    circleBarsFlowContainer:SetPoint("CENTER", UIParent, "CENTER", cfg0.x or 0, cfg0.y or -218)
    -- Strata BACKGROUND (comme l'ancien conteneur Buffs.lua) : sinon un AuraContainer natif prend la
    -- strata par defaut (MEDIUM), en conflit visuel avec l'overlay du Resource Circle.
    circleBarsFlowContainer:SetFrameStrata("BACKGROUND")
    -- Ordre critique : SetEnabled/SetUnit/Show avant tout AddAuraGroup, sinon les barres ne sont jamais alimentees.
    local okEn, errEn = pcall(circleBarsFlowContainer.SetEnabled, circleBarsFlowContainer, true)
    local okUn, errUn = pcall(circleBarsFlowContainer.SetUnit, circleBarsFlowContainer, "player")
    if not okEn or not okUn then
        CBDBG(string.format("|cffff4444EnsureCircleBarsFlowContainer: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    circleBarsFlowContainer:Show()

    -- Deplacement Alt+clic gauche, meme pattern que partout ailleurs.
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
            SafeSetPropagateMouseClicks(s, false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    circleBarsFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        SafeSetPropagateMouseClicks(s, true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Cf. commentaire equivalent sur "icons" -- GetCenter() peut renvoyer secret une fois lie a
        -- une vraie aura ; pcall : abandon silencieux plutot que planter.
        if cx and cy and ns.db and ns.db.freebars then
            pcall(function()
                ns.db.freebars.x = cx*sc - sx
                ns.db.freebars.y = cy*sc - sy
            end)
        end
    end)
    return circleBarsFlowContainer
end

-- Applique le style courant a une paire de barres deja creee. Meme logique que ApplyIconsFlowButtonStyle
-- : appelee a la creation ET a chaque refresh GUI. La position verticale de la ligne (rang fixe) n'est
-- pas retouchee ici -- recalculee uniquement a la prochaine creation de pool.
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

-- A appeler depuis le GUI a chaque changement de reglage affectant l'apparence de Circle Bars.
-- Volontairement plus etroit que ApplyCircleBarsButtonStyle : ne touche que SetStatusBarColor/
-- SetGradient (jamais SetPoint/SetSize/SetStatusBarTexture), retoucher une StatusBar liee via
-- SetDurationBar etant suspecte de casser son binding.
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
                -- Spark : texture propre a l'addon, jamais secrete, toujours sure a retoucher.
                if btn._aishSparkL and okL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {rL, gL, bL}) end
            end
            if btn._aishBarR then
                local okR, rR, gR, bR = pcall(CBApplySpellColor, btn._aishBarR, liveCfg, btn._aishSpellID, si)
                if btn._aishSparkR and okR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {rR, gR, bR}) end
            end
            -- Texte de duree : widget Cooldown dedie, texte natif, jamais de risque a le restyler.
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

    -- Flow layout reel (comme "icons") : un SetPoint manuel entrerait en conflit avec le flow (rendu
    -- obligatoire des que "layout" est fourni a AddAuraGroup) et ferait s'ecraser 2 candidats sur la
    -- meme position. Axe vertical (1, par symetrie avec l'axe horizontal 0 confirme fonctionner),
    -- empile vers le bas depuis le haut du conteneur -- ordre d'affichage non garanti.
    local okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, "TOP")
    local okX, errX = pcall(c.SetFlowLayoutAxis, c, 1)
    local okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, 1, -1)
    local okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, maxBars * (bh + rg) + rg)
    if not (okA and okX and okG and okM) then
        CBDBG(string.format("|cffff4444RepositionCircleBarsNativeGrid: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    -- freebars a un vrai toggle utilisateur (contrairement a icons) -- le respecter, comme useNativeCDM.
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

-- Compteur de cap "par BUFF, pas par spellID" : une variation de tier d'un buff multi-spellID (ex: Jet
-- d'osselets Hors-la-loi, 4 spellID via linkedSpellIDs) pouvait ne s'afficher que sur certaines
-- destinations, car la boucle de creation coupait a `i > maxBars` en comptant chaque variante
-- separement -- si le sort "ancre" tombait pile a la limite, ses variantes suivantes tombaient hors cap
-- malgre `dansWhitelist=true`. Toutes les variantes partagent le meme objet `info` (linkedFallbackInfo) :
-- on s'en sert comme cle d'identite pour ne compter qu'une fois tout un groupe de variantes liees.
-- `wl` = ns.whitelistByDest[dest] ; retourne true si le spellID doit encore etre traite, false si le
-- cap est atteint.
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

-- Cree (une seule fois par sort) un AddAuraGroup dedie par spellID de "Circle Bars", au lieu d'un
-- groupe unique partage. Appelee depuis Whitelist.lua/BuildWhitelist, joueur uniquement.
-- Pourquoi ("couleur par sort") : un groupe partage reutilise le meme pool de boutons pour n'importe
-- quel sort trace -- impossible de fixer une couleur/glow par sort puisque le meme bouton physique
-- peut afficher le Sort A puis le Sort B, et retoucher un widget deja lie casse les bindings. Un groupe
-- dedie (maxFrameCount=1, un seul spellID en filtre) fixe definitivement quel sort occupe ce bouton.
-- Plusieurs AddAuraGroup cohabitent proprement sur le meme conteneur/flow (cf. /aishdebug testpercolor).
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

                            -- direction=RemainingTime : sans cette option, la barre se remplit au lieu de se vider.
                            local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }
                            local okBarL, errBarL = pcall(auraButton.SetDurationBar, auraButton, barL, durOpts)
                            local okBarR, errBarR = pcall(auraButton.SetDurationBar, auraButton, barR, durOpts)
                            if not okBarL then CBDBG(string.format("|cffff4444initializeFrame (Circle Bars, sort %d): SetDurationBar(barL) a echoue -- err=%s|r", spellID, tostring(errBarL))) end
                            if not okBarR then CBDBG(string.format("|cffff4444initializeFrame (Circle Bars, sort %d): SetDurationBar(barR) a echoue -- err=%s|r", spellID, tostring(errBarR))) end

                            -- Spark : barL grandit vers la gauche (bord mobile a gauche), barR vers la droite.
                            auraButton._aishSparkL = MakeNativeBarSpark(barL, liveCfg, "LEFT", {barLR, barLG, barLB})
                            auraButton._aishSparkR = MakeNativeBarSpark(barR, liveCfg, "RIGHT", {barRR, barRG, barRB})

                            -- Texte de duree : pas d'icone ici donc pas de Cooldown existant, on en cree
                            -- un dedie pour heberger le countdown natif (SetDurationCooldown est un slot
                            -- independant de SetDurationBar, les 3 coexistent sur le meme auraButton).
                            -- SetAllPoints(auraButton) plutot qu'une taille fixe : une taille degeneree
                            -- pourrait empecher Blizzard de peupler le FontString interne du countdown.
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
                        -- Pas de re-style ici apres coup -- tout se fait une seule fois.
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
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis re-trace (cf. Icons plus haut).
            pcall(c.SetAuraGroupCandidateFilters, c, "aishCircleBarsFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques : meme neutralisation par spellID bidon que Icons plus haut (jamais {}).
    for spellID in pairs(circleBarsPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishCircleBarsFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

-- DUMP complet de l'etat actuel : /aishdebug circlebarsflow. Montre combien de boutons ont ete crees
-- et a quelle position chacun est fige, pour determiner si Blizzard cree un bouton par buff simultane.
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

-- WATCHER : /aishdebug circlebarswatch -- diagnostic pour l'hypothese "Blizzard ne re-scanne les
-- candidats que sur UpdateAllAuras explicite, pas automatiquement" (symptome : un 2e buff n'apparait
-- jamais tant que le 1er ne s'eteint pas). Force UpdateAllAuras toutes les 0.5s et log les changements.
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
            -- btn:IsShown() peut renvoyer une valeur secrete une fois lie ; meme la comparer plante.
            -- CanBeAccessedInContext() renvoie toujours un booleen normal, on s'appuie uniquement dessus.
            local okCA, canAccess = pcall(function() return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext() end)
            local key = string.format("ca=%s/%s", tostring(okCA), tostring(canAccess))
            if circleBarsWatchLastState[i] ~= key then
                P(string.format("bouton #%d : %s", i, key))
                circleBarsWatchLastState[i] = key
            end
        end
    end)
end

-- Grille native cible pour "Circle Bars" (Buffs.lua/freebars, debuffs cible). Meme principe que le
-- miroir cible de "icons" : conteneur separe avec SetUnit("target")+filtre "HARMFUL", ne route que les
-- sorts info.source=="debuff". Empile sous le conteneur joueur (pas de drag independant).
local circleBarsFlowContainerTarget
local circleBarsFlowButtonsTarget = {}
local circleBarsPerSpellGroupsTarget = {}

function ns.GetCircleBarsNativeContainerTarget()
    return circleBarsFlowContainerTarget
end

local function EnsureCircleBarsFlowContainerTarget()
    if circleBarsFlowContainerTarget then return circleBarsFlowContainerTarget end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        CBDBG(string.format("|cffff4444EnsureCircleBarsFlowContainerTarget: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    circleBarsFlowContainerTarget = result

    local cfg0 = ns.db and ns.db.freebars or ns.Defaults.freebars
    local maxBars0 = cfg0.maxBars or 8
    local bw0, bh0, gp0, rg0 = cfg0.barW or 45, cfg0.barH or 3, cfg0.gap or 50, cfg0.rowGap or 6
    circleBarsFlowContainerTarget:SetSize(bw0 * 2 + gp0 * 2, maxBars0 * (bh0 + rg0))
    circleBarsFlowContainerTarget:SetFrameStrata("BACKGROUND")
    -- Position reelle ici, avant AddAuraGroup/UpdateAllAuras (meme regle que le conteneur joueur) --
    -- ancre sous le conteneur joueur s'il existe deja, sinon position de repli.
    if circleBarsFlowContainer then
        circleBarsFlowContainerTarget:SetPoint("TOP", circleBarsFlowContainer, "BOTTOM", 0, -rg0)
    else
        circleBarsFlowContainerTarget:SetPoint("CENTER", UIParent, "CENTER", cfg0.x or 0, (cfg0.y or -218) - maxBars0 * (bh0 + rg0))
    end

    local okEn, errEn = pcall(circleBarsFlowContainerTarget.SetEnabled, circleBarsFlowContainerTarget, true)
    local okUn, errUn = pcall(circleBarsFlowContainerTarget.SetUnit, circleBarsFlowContainerTarget, "target")
    if not okEn or not okUn then
        CBDBG(string.format("|cffff4444EnsureCircleBarsFlowContainerTarget: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    circleBarsFlowContainerTarget:Show()
    return circleBarsFlowContainerTarget
end

local function ApplyCircleBarsButtonStyleTarget(auraButton)
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
        CBDBG(string.format("|cffff4444ApplyCircleBarsButtonStyleTarget: bloc principal a echoue -- err=%s|r", tostring(errStyle)))
    end
end

function ns.RefreshCircleBarsNativeGridStyleTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local liveCfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local spells = ns.GetSpecSpells()
    for _, btn in ipairs(circleBarsFlowButtonsTarget) do
        local okCheck, canAccess = pcall(function()
            return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext()
        end)
        if okCheck and canAccess then
            local si = btn._aishSpellID and spells and spells[btn._aishSpellID]
            if btn._aishBarL then
                local okL, rL, gL, bL = pcall(CBApplySpellColor, btn._aishBarL, liveCfg, btn._aishSpellID, si)
                if btn._aishSparkL and okL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {rL, gL, bL}) end
            end
            if btn._aishBarR then
                local okR, rR, gR, bR = pcall(CBApplySpellColor, btn._aishBarR, liveCfg, btn._aishSpellID, si)
                if btn._aishSparkR and okR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {rR, gR, bR}) end
            end
            if btn._aishTimerCD then
                pcall(btn._aishTimerCD.SetHideCountdownNumbers, btn._aishTimerCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishTimerCD, liveCfg, btn)
                end
            end
        end
    end
end

function ns.RepositionCircleBarsNativeGridTarget()
    local c = circleBarsFlowContainerTarget or EnsureCircleBarsFlowContainerTarget()
    if not c then return end
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars

    local maxBars = cfg.maxBars or 8
    local bw, bh, gp, rg = cfg.barW or 45, cfg.barH or 3, cfg.gap or 50, cfg.rowGap or 6
    local rowW = bw * 2 + gp * 2
    pcall(c.SetSize, c, rowW, maxBars * (bh + rg))

    c:ClearAllPoints()
    if circleBarsFlowContainer then
        c:SetPoint("TOP", circleBarsFlowContainer, "BOTTOM", 0, -rg)
    else
        c:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, (cfg.y or -218) - maxBars * (bh + rg))
    end

    local okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, "TOP")
    local okX, errX = pcall(c.SetFlowLayoutAxis, c, 1)
    local okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, 1, -1)
    local okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, maxBars * (bh + rg) + rg)
    if not (okA and okX and okG and okM) then
        CBDBG(string.format("|cffff4444RepositionCircleBarsNativeGridTarget: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    local visible = (ns.db == nil or ns.db.freebarsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        c:SetAlpha(1)
    else
        c:SetAlpha(0)
    end
    pcall(ns.RefreshCircleBarsNativeGridStyleTarget)
end

-- Cree (une seule fois par sort) un AddAuraGroup dedie par debuff cible de "Circle Bars",
-- SetUnit("target")+"HARMFUL". Appelee depuis Whitelist.lua juste apres ns.EnsureCircleBarsNativeGrid.
function ns.EnsureCircleBarsNativeGridTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureCircleBarsFlowContainerTarget()
    if not c then return end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.freebars
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local maxBars = cfg.maxBars or 8
    local bw, bh, gp, rg = cfg.barW or 45, cfg.barH or 3, cfg.gap or 50, cfg.rowGap or 6
    local rowStep = bh + rg
    local spells = ns.GetSpecSpells()

    local wl = ns.whitelistByDest and ns.whitelistByDest.freebars
    local seenInfo, capState = {}, { count = 0 }
    local currentSet = {}
    for _, spellID in ipairs(order) do
        local info = spells and spells[spellID]
        if info and info.source == "debuff" then
            if not AllowNextCapSlot(wl, spellID, maxBars, seenInfo, capState) then break end
            currentSet[spellID] = true
            if not circleBarsPerSpellGroupsTarget[spellID] then
                local groupKey = "aishCircleBarsFlowTarget_" .. tostring(spellID)
                local okAdd, errAdd = pcall(function()
                    c:AddAuraGroup(groupKey, "HARMFUL|PLAYER", {
                        maxFrameCount = 1,
                        candidateFilters = { includeSpellIDs = { [spellID] = true } },
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
                                auraButton:SetSize(lbw * 2 + lgp * 2, lbh)

                                local tex = ns.ResolveBarTexFromKey(liveCfg.texture)
                                local bgR = liveCfg.barBgR or 0; local bgG = liveCfg.barBgG or 0
                                local bgB = liveCfg.barBgB or 0; local bgA = liveCfg.barBgAlpha or 0

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

                                local barR = CreateFrame("StatusBar", nil, auraButton)
                                barR:SetSize(lbw, lbh)
                                barR:SetPoint("LEFT", auraButton, "CENTER", lgp, 0)
                                barR:SetStatusBarTexture(tex)
                                local barRR, barRG, barRB = CBApplySpellColor(barR, liveCfg, spellID, liveSi)
                                local bgR2 = barR:CreateTexture(nil, "BACKGROUND")
                                bgR2:SetAllPoints(); bgR2:SetColorTexture(bgR, bgG, bgB, bgA)
                                auraButton._aishBarR = barR
                                auraButton._aishBgR = bgR2

                                local durOpts = { direction = Enum.StatusBarTimerDirection.RemainingTime }
                                local okBarL, errBarL = pcall(auraButton.SetDurationBar, auraButton, barL, durOpts)
                                local okBarR, errBarR = pcall(auraButton.SetDurationBar, auraButton, barR, durOpts)
                                if not okBarL then CBDBG(string.format("|cffff4444initializeFrame cible (Circle Bars, sort %d): SetDurationBar(barL) a echoue -- err=%s|r", spellID, tostring(errBarL))) end
                                if not okBarR then CBDBG(string.format("|cffff4444initializeFrame cible (Circle Bars, sort %d): SetDurationBar(barR) a echoue -- err=%s|r", spellID, tostring(errBarR))) end

                                auraButton._aishSparkL = MakeNativeBarSpark(barL, liveCfg, "LEFT", {barLR, barLG, barLB})
                                auraButton._aishSparkR = MakeNativeBarSpark(barR, liveCfg, "RIGHT", {barRR, barRG, barRB})

                                local timerCD = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                                timerCD:SetAllPoints(auraButton)
                                timerCD:SetDrawSwipe(false); timerCD:SetDrawEdge(false); timerCD:SetDrawBling(false)
                                timerCD:EnableMouse(false)
                                local okTimerCD, errTimerCD = pcall(auraButton.SetDurationCooldown, auraButton, timerCD)
                                if not okTimerCD then
                                    CBDBG(string.format("|cffff4444initializeFrame cible (Circle Bars, sort %d): SetDurationCooldown(timerCD) a echoue -- err=%s|r", spellID, tostring(errTimerCD)))
                                end
                                timerCD:SetHideCountdownNumbers(not liveCfg.timerIconEnabled)
                                auraButton._aishTimerCD = timerCD
                                if liveCfg.timerIconEnabled then
                                    pcall(ApplyNativeCountdownStyle, timerCD, liveCfg, auraButton)
                                end

                                circleBarsFlowButtonsTarget[#circleBarsFlowButtonsTarget + 1] = auraButton
                            end)
                            if not okBuild then
                                CBDBG(string.format("|cffff4444initializeFrame cible (Circle Bars, sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                            end
                        end,
                    })
                end)
                if not okAdd then
                    CBDBG(string.format("|cffff4444AddAuraGroup DEDIE cible (Circle Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
                end
                circleBarsPerSpellGroupsTarget[spellID] = true
                if c.UpdateAllAuras then
                    local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                    if not okUpd then CBDBG(string.format("|cffff4444UpdateAllAuras cible (Circle Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
                end
            else
                pcall(c.SetAuraGroupCandidateFilters, c, "aishCircleBarsFlowTarget_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
            end
        end
    end

    for spellID in pairs(circleBarsPerSpellGroupsTarget) do
        if not currentSet[spellID] then
            local groupKey = "aishCircleBarsFlowTarget_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

local circleBarsTargetChangeFrame = CreateFrame("Frame")
circleBarsTargetChangeFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
circleBarsTargetChangeFrame:SetScript("OnEvent", function()
    if circleBarsFlowContainerTarget and circleBarsFlowContainerTarget.UpdateAllAuras then
        pcall(circleBarsFlowContainerTarget.UpdateAllAuras, circleBarsFlowContainerTarget)
    end
end)

-- Grille native pour "Free Bars" (Cooldowns.lua, cle interne circlebars -- l'onglet GUI "Free Bars" est
-- backe par Cooldowns.lua/circlebars, PAS Buffs.lua/freebars qui est "Circle Bars"). Meme methodologie
-- deja eprouvee sur Icons et Circle Bars : AddAuraGroup (jamais AddAuraSlot), SetEnabled/SetUnit/Show
-- avant AddAuraGroup, le champ "layout" doit etre fourni pour activer plusieurs membres du pool
-- simultanement, Blizzard doit gerer 100% du positionnement via SetFlowLayout* (un SetPoint manuel
-- entre en conflit et ecrase plusieurs candidats sur la meme position), direction=RemainingTime pour
-- vider au lieu de remplir, le font doit preceder SetApplicationCount, jamais retoucher un widget deja
-- lie apres sa creation.
-- Cas cible : explicitement differe, ce rendu ne trace que unit="player" -- le filtre SetUnit("player")
-- exclut naturellement ce qui n'est present que sur la cible, sans pre-filtrage Lua.
-- 3 dispositions (cfg.layout) : "side_large" (icone + 1 barre a cote), "side_compact" (icone centree +
-- 2 barres miroir), "side_banner" (icone au-dessus + 1 barre en-dessous). cfg.hideIcon : barres seules.
-- Couleur/glow par sort : meme recette que Circle Bars (groupe dedie par sort). SpellBarColorRGB/
-- ApplySpellGlow sont declares plus haut (portee lexicale Lua). Pas de degrade par sort ici,
-- specifique a Circle Bars (cf. CBApplySpellColor).
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
            SafeSetPropagateMouseClicks(s, false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    freeBarsFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        SafeSetPropagateMouseClicks(s, true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Cf. commentaire equivalent sur "icons" -- GetCenter() peut renvoyer secret une fois lie a
        -- une vraie aura ; pcall : abandon silencieux plutot que planter.
        if cx and cy and ns.db and ns.db.circlebars then
            pcall(function()
                ns.db.circlebars.x = cx*sc - sx
                ns.db.circlebars.y = cy*sc - sy
            end)
        end
    end)
    return freeBarsFlowContainer
end

-- Repositionne le conteneur + reconfigure le flow layout selon cfg.growth (contrairement a Circle
-- Bars, reglable par l'utilisateur ici -- reutilise GrowthToFlowParams). Rafraichit aussi l'alpha.
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

-- A appeler depuis le GUI a chaque changement de couleur/glow -- ne touche que SetStatusBarColor/
-- SetGradient et le glow, jamais SetPoint/SetSize/SetStatusBarTexture (cf. RefreshCircleBarsNativeGridStyle).
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
            -- Spark : texture propre a l'addon, jamais secrete, toujours sure a retoucher.
            if btn._aishSparkL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {cR, cG, cB}) end
            if btn._aishSparkR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {cR, cG, cB}) end
            if btn._aishSpark then pcall(ApplyNativeBarSparkColor, btn._aishSpark, liveCfg, {cR, cG, cB}) end
            if btn._aishGlowAnchor then
                if ns.HideGlow then pcall(ns.HideGlow, btn._aishGlowAnchor) end
                pcall(ApplySpellGlow, btn._aishGlowAnchor, liveCfg, si, iw, ih)
            end
            -- btn._aishCD couvre deja les memes bornes que l'icone (cd:SetAllPoints(icon)), sert
            -- directement de relFrame.
            if btn._aishCD then
                pcall(btn._aishCD.SetHideCountdownNumbers, btn._aishCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishCD, liveCfg, btn._aishCD)
                end
            end
        end
    end
end

-- Cree (une seule fois par sort) un AddAuraGroup dedie pour chaque spellID de "Free Bars", au lieu
-- d'un groupe unique partage -- permet une couleur/glow fixe par sort. Appelee depuis Whitelist.lua.
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

    -- Cape a maxBars buffs (pas spellID, cf. AllowNextCapSlot) : evite un nombre de groupes non borne.
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
                                -- Crop conscient du ratio (meme recette que EnsureIconListNativeGrid) :
                                -- sans ca, un slot non-carre (iw ~= ih) etirait l'image visiblement.
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
                                -- Font avant SetApplicationCount, sinon "Font not set" fait echouer tout le groupe.
                                ns.ApplyFont(stackFS, liveCfg.stackFont or ns.Media.font, liveCfg.stackSize or 10, "OUTLINE")
                                stackFS:SetPoint(liveCfg.stackPos or "BOTTOMRIGHT", icon, liveCfg.stackPos or "BOTTOMRIGHT", liveCfg.stackOffX or 0, liveCfg.stackOffY or 0)
                                stackFS:SetJustifyH("RIGHT")
                                stackFS:SetTextColor(liveCfg.stackColorR or 1, liveCfg.stackColorG or 1, liveCfg.stackColorB or 1)
                                auraButton:SetApplicationCount(stackFS, {})
                                auraButton._aishStackFS = stackFS
                            end

                            -- Barre(s) de duree, couleur par sort.
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
                                -- Spark : bord mobile oppose au cote d'origine du remplissage ; la
                                -- reference est stockee pour pouvoir le recolorer plus tard.
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
                                -- Vanguard : icone + 1 barre a cote. liveCfg.iconPos change le cote de
                                -- la barre, le sens de remplissage en decoule toujours automatiquement
                                -- pour que la barre se vide en direction de l'icone.
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
                                local isRev = iconR
                                bar:SetReverseFill(isRev)
                                local bg = bar:CreateTexture(nil, "BACKGROUND")
                                bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                                if not okBar then FBDBG(string.format("|cffff4444initializeFrame (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                auraButton._aishBar = bar
                                auraButton._aishSpark = MakeNativeBarSpark(bar, liveCfg, isRev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                            end

                            -- Swipe + texte de duree natif (meme mecanisme que Icons).
                            if cd then
                                cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
                                cd:SetDrawEdge(liveCfg.swipeEnabled == true)
                                cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
                                if liveCfg.timerIconEnabled then
                                    ApplyNativeCountdownStyle(cd, liveCfg, icon or auraButton)
                                end
                            end

                            -- Glow par sort (cf. ApplySpellGlow).
                            if icon then
                                ApplySpellGlow(auraButton._aishGlowAnchor, liveCfg, liveSi, iw, ih)
                                -- Animation d'entree, jouee une seule fois.
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
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis re-trace (cf. Icons plus haut).
            pcall(c.SetAuraGroupCandidateFilters, c, "aishFreeBarsFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques : meme neutralisation par spellID bidon que Icons plus haut (jamais {}).
    for spellID in pairs(freeBarsPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishFreeBarsFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

-- Grille native cible pour "Free Bars" (Cooldowns.lua/circlebars, debuffs cible) -- meme principe que
-- les miroirs cible de Icons/Circle Bars : conteneur separe SetUnit("target")+"HARMFUL", ne route que
-- les sorts info.source=="debuff". Empile sous le conteneur joueur (pas de drag independant).
local freeBarsFlowContainerTarget
local freeBarsFlowButtonsTarget = {}
local freeBarsPerSpellGroupsTarget = {}

function ns.GetFreeBarsNativeContainerTarget()
    return freeBarsFlowContainerTarget
end

local function EnsureFreeBarsFlowContainerTarget()
    if freeBarsFlowContainerTarget then return freeBarsFlowContainerTarget end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        FBDBG(string.format("|cffff4444EnsureFreeBarsFlowContainerTarget: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    freeBarsFlowContainerTarget = result

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
    if isH0 then freeBarsFlowContainerTarget:SetSize(maxBars0 * (rowW0 + rg0), rowH0)
    else freeBarsFlowContainerTarget:SetSize(rowW0, maxBars0 * (rowH0 + rg0)) end
    freeBarsFlowContainerTarget:SetFrameStrata("MEDIUM")

    -- Position reelle ici, avant AddAuraGroup/UpdateAllAuras (meme regle que le conteneur joueur) --
    -- ancre sous/a cote du conteneur joueur selon la direction de croissance, sinon position de repli.
    if freeBarsFlowContainer then
        if growth0 == "UP" then freeBarsFlowContainerTarget:SetPoint("BOTTOM", freeBarsFlowContainer, "TOP", 0, rg0)
        elseif growth0 == "LEFT" then freeBarsFlowContainerTarget:SetPoint("RIGHT", freeBarsFlowContainer, "LEFT", -rg0, 0)
        elseif growth0 == "RIGHT" then freeBarsFlowContainerTarget:SetPoint("LEFT", freeBarsFlowContainer, "RIGHT", rg0, 0)
        else freeBarsFlowContainerTarget:SetPoint("TOP", freeBarsFlowContainer, "BOTTOM", 0, -rg0) end
    else
        local x0, y0 = cfg0.x or -502, cfg0.y or 0
        if growth0 == "UP" then freeBarsFlowContainerTarget:SetPoint("BOTTOM", UIParent, "CENTER", x0, y0 + maxBars0 * (rowH0 + rg0))
        elseif growth0 == "LEFT" then freeBarsFlowContainerTarget:SetPoint("RIGHT", UIParent, "CENTER", x0 - maxBars0 * (rowW0 + rg0), y0)
        elseif growth0 == "RIGHT" then freeBarsFlowContainerTarget:SetPoint("LEFT", UIParent, "CENTER", x0 + maxBars0 * (rowW0 + rg0), y0)
        else freeBarsFlowContainerTarget:SetPoint("TOP", UIParent, "CENTER", x0, y0 - maxBars0 * (rowH0 + rg0)) end
    end

    local okEn, errEn = pcall(freeBarsFlowContainerTarget.SetEnabled, freeBarsFlowContainerTarget, true)
    local okUn, errUn = pcall(freeBarsFlowContainerTarget.SetUnit, freeBarsFlowContainerTarget, "target")
    if not okEn or not okUn then
        FBDBG(string.format("|cffff4444EnsureFreeBarsFlowContainerTarget: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    freeBarsFlowContainerTarget:Show()
    return freeBarsFlowContainerTarget
end

function ns.RefreshFreeBarsNativeGridStyleTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local liveCfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local spells = ns.GetSpecSpells()
    local iw = liveCfg.hideIcon and 0 or (liveCfg.iconW or 28)
    local ih = liveCfg.iconH or 19
    for _, btn in ipairs(freeBarsFlowButtonsTarget) do
        local okCheck, canAccess = pcall(function()
            return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext()
        end)
        if okCheck and canAccess then
            local si = btn._aishSpellID and spells and spells[btn._aishSpellID]
            local cR, cG, cB = SpellBarColorRGB(liveCfg, si)
            if btn._aishBarL then pcall(btn._aishBarL.SetStatusBarColor, btn._aishBarL, cR, cG, cB) end
            if btn._aishBarR then pcall(btn._aishBarR.SetStatusBarColor, btn._aishBarR, cR, cG, cB) end
            if btn._aishBar then pcall(btn._aishBar.SetStatusBarColor, btn._aishBar, cR, cG, cB) end
            if btn._aishSparkL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {cR, cG, cB}) end
            if btn._aishSparkR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {cR, cG, cB}) end
            if btn._aishSpark then pcall(ApplyNativeBarSparkColor, btn._aishSpark, liveCfg, {cR, cG, cB}) end
            if btn._aishGlowAnchor then
                if ns.HideGlow then pcall(ns.HideGlow, btn._aishGlowAnchor) end
                pcall(ApplySpellGlow, btn._aishGlowAnchor, liveCfg, si, iw, ih)
            end
            if btn._aishCD then
                pcall(btn._aishCD.SetHideCountdownNumbers, btn._aishCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishCD, liveCfg, btn._aishCD)
                end
            end
        end
    end
end

function ns.RepositionFreeBarsNativeGridTarget()
    local c = freeBarsFlowContainerTarget or EnsureFreeBarsFlowContainerTarget()
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
    if freeBarsFlowContainer then
        if growth == "UP" then c:SetPoint("BOTTOM", freeBarsFlowContainer, "TOP", 0, rg)
        elseif growth == "LEFT" then c:SetPoint("RIGHT", freeBarsFlowContainer, "LEFT", -rg, 0)
        elseif growth == "RIGHT" then c:SetPoint("LEFT", freeBarsFlowContainer, "RIGHT", rg, 0)
        else c:SetPoint("TOP", freeBarsFlowContainer, "BOTTOM", 0, -rg) end
    else
        local x, y = cfg.x or -502, cfg.y or 0
        if growth == "UP" then c:SetPoint("BOTTOM", UIParent, "CENTER", x, y + maxBars * (rowH + rg))
        elseif growth == "LEFT" then c:SetPoint("RIGHT", UIParent, "CENTER", x - maxBars * (rowW + rg), y)
        elseif growth == "RIGHT" then c:SetPoint("LEFT", UIParent, "CENTER", x + maxBars * (rowW + rg), y)
        else c:SetPoint("TOP", UIParent, "CENTER", x, y - maxBars * (rowH + rg)) end
    end

    local anchorPoint, hDir, vDir, isHFlow = GrowthToFlowParams(growth)
    local okA, errA = pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
    local okX, errX = pcall(c.SetFlowLayoutAxis, c, isHFlow and 0 or 1)
    local okG, errG = pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
    local itemSize = isH and rowW or rowH
    local okM, errM = pcall(c.SetFlowLayoutMaximumLineSize, c, (itemSize + rg) * maxBars + rg)
    if not (okA and okX and okG and okM) then
        FBDBG(string.format("|cffff4444RepositionFreeBarsNativeGridTarget: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    local visible = (ns.db == nil or ns.db.circlebarsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        c:SetAlpha(1)
    else
        c:SetAlpha(0)
    end
    pcall(ns.RefreshFreeBarsNativeGridStyleTarget)
end

-- Cree (une seule fois par sort) un AddAuraGroup dedie par debuff cible de "Free Bars",
-- SetUnit("target")+"HARMFUL". Appelee depuis Whitelist.lua juste apres ns.EnsureFreeBarsNativeGrid.
function ns.EnsureFreeBarsNativeGridTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureFreeBarsFlowContainerTarget()
    if not c then return end

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

    local wl = ns.whitelistByDest and ns.whitelistByDest.circlebars
    local seenInfo, capState = {}, { count = 0 }
    local currentSet = {}
    for _, spellID in ipairs(order) do
        local info = spells and spells[spellID]
        if info and info.source == "debuff" then
            if not AllowNextCapSlot(wl, spellID, maxBars, seenInfo, capState) then break end
            currentSet[spellID] = true
            if not freeBarsPerSpellGroupsTarget[spellID] then
                local groupKey = "aishFreeBarsFlowTarget_" .. tostring(spellID)
                local si = spells and spells[spellID]
                local okAdd, errAdd = pcall(function()
                    c:AddAuraGroup(groupKey, "HARMFUL|PLAYER", {
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

                                local icon, cd, stackFS
                                if not liveCfg.hideIcon then
                                    icon = auraButton:CreateTexture(nil, "ARTWORK")
                                    if layout == "side_banner" then
                                        icon:SetSize(iw, ih)
                                        icon:SetPoint("TOP", auraButton, "TOP", 0, 0)
                                    elseif layout == "side_compact" then
                                        icon:SetSize(iw, ih)
                                        icon:SetPoint("CENTER", auraButton, "CENTER", 0, 0)
                                    else
                                        icon:SetSize(iw, ih)
                                        if (liveCfg.iconPos or "RIGHT") == "RIGHT" then
                                            icon:SetPoint("RIGHT", auraButton, "RIGHT", 0, 0)
                                        else
                                            icon:SetPoint("LEFT", auraButton, "LEFT", 0, 0)
                                        end
                                    end
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

                                    local glowAnchor = CreateFrame("Frame", nil, auraButton)
                                    glowAnchor:SetAllPoints(icon)
                                    auraButton._aishGlowAnchor = glowAnchor

                                    cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                                    cd:SetAllPoints(icon)
                                    cd:SetReverse(true)
                                    auraButton:SetDurationCooldown(cd)
                                    auraButton._aishCD = cd

                                    stackFS = auraButton:CreateFontString(nil, "OVERLAY", nil, 7)
                                    ns.ApplyFont(stackFS, liveCfg.stackFont or ns.Media.font, liveCfg.stackSize or 10, "OUTLINE")
                                    stackFS:SetPoint(liveCfg.stackPos or "BOTTOMRIGHT", icon, liveCfg.stackPos or "BOTTOMRIGHT", liveCfg.stackOffX or 0, liveCfg.stackOffY or 0)
                                    stackFS:SetJustifyH("RIGHT")
                                    stackFS:SetTextColor(liveCfg.stackColorR or 1, liveCfg.stackColorG or 1, liveCfg.stackColorB or 1)
                                    auraButton:SetApplicationCount(stackFS, {})
                                    auraButton._aishStackFS = stackFS
                                end

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
                                    if not okBar then FBDBG(string.format("|cffff4444initializeFrame cible (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                    local spark = MakeNativeBarSpark(bar, liveCfg, rev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                                    return bar, spark
                                end

                                if layout == "side_compact" then
                                    local anchorRef = liveCfg.hideIcon and auraButton or icon
                                    local relPointL = liveCfg.hideIcon and "CENTER" or "LEFT"
                                    local relPointR = liveCfg.hideIcon and "CENTER" or "RIGHT"
                                    auraButton._aishBarL, auraButton._aishSparkL = MakeNativeBar("RIGHT", anchorRef, relPointL, -gp, 0, true)
                                    auraButton._aishBarR, auraButton._aishSparkR = MakeNativeBar("LEFT", anchorRef, relPointR, gp, 0, false)
                                elseif layout == "side_banner" then
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
                                    if not okBar then FBDBG(string.format("|cffff4444initializeFrame cible (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                    auraButton._aishBar = bar
                                    auraButton._aishSpark = MakeNativeBarSpark(bar, liveCfg, isRev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                                else
                                    -- Vanguard : cf. bloc jumeau plus haut, sens de remplissage
                                    -- toujours derive de iconPos.
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
                                    local isRev = iconR
                                    bar:SetReverseFill(isRev)
                                    local bg = bar:CreateTexture(nil, "BACKGROUND")
                                    bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
                                    local okBar, errBar = pcall(auraButton.SetDurationBar, auraButton, bar, durOpts)
                                    if not okBar then FBDBG(string.format("|cffff4444initializeFrame cible (Free Bars, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                    auraButton._aishBar = bar
                                    auraButton._aishSpark = MakeNativeBarSpark(bar, liveCfg, isRev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                                end

                                if cd then
                                    cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
                                    cd:SetDrawEdge(liveCfg.swipeEnabled == true)
                                    cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
                                    if liveCfg.timerIconEnabled then
                                        ApplyNativeCountdownStyle(cd, liveCfg, icon or auraButton)
                                    end
                                end

                                if icon then
                                    ApplySpellGlow(auraButton._aishGlowAnchor, liveCfg, liveSi, iw, ih)
                                    PlayProcStartOnce(auraButton._aishGlowAnchor, liveSi, spellID)
                                end

                                freeBarsFlowButtonsTarget[#freeBarsFlowButtonsTarget + 1] = auraButton
                            end)
                            if not okBuild then
                                FBDBG(string.format("|cffff4444initializeFrame cible (Free Bars, sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                            end
                        end,
                    })
                end)
                if not okAdd then
                    FBDBG(string.format("|cffff4444AddAuraGroup DEDIE cible (Free Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
                end
                freeBarsPerSpellGroupsTarget[spellID] = true
                if c.UpdateAllAuras then
                    local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                    if not okUpd then FBDBG(string.format("|cffff4444UpdateAllAuras cible (Free Bars, sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
                end
            else
                pcall(c.SetAuraGroupCandidateFilters, c, "aishFreeBarsFlowTarget_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
            end
        end
    end

    for spellID in pairs(freeBarsPerSpellGroupsTarget) do
        if not currentSet[spellID] then
            local groupKey = "aishFreeBarsFlowTarget_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

local freeBarsTargetChangeFrame = CreateFrame("Frame")
freeBarsTargetChangeFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
freeBarsTargetChangeFrame:SetScript("OnEvent", function()
    if freeBarsFlowContainerTarget and freeBarsFlowContainerTarget.UpdateAllAuras then
        pcall(freeBarsFlowContainerTarget.UpdateAllAuras, freeBarsFlowContainerTarget)
    end
end)

-- Icon List (GUI "Liste d'icones", Debuffs.lua, cle interne iconlist) : meme methodologie que
-- Icons/Circle Bars/Free Bars. 2 dispositions (cfg.layout) : "center_mirror" (Aegis, defaut) : icone
-- centree + 2 barres miroir (meme geometrie que Free Bars "side_compact") ; "center_dual" (Berserk) :
-- paires icone+barre de part et d'autre d'un espace central, plusieurs paires empilees. Chaque
-- auraButton represente une moitie, le flow layout les groupe 2 par 2 (axe horizontal fixe) et empile
-- les paires verticalement. Le cote gauche/droit de chaque moitie est fixe a la creation (compteur
-- local), stable car Blizzard cree les membres du pool dans un ordre sequentiel fixe.
-- Cas cible explicitement differe (SetUnit("player") exclut naturellement ce qui n'est que sur la cible).
-- Simplifications acceptees : pas de texte de charges (necessiterait un refresh periodique independant,
-- deja absent sur Icons/Free Bars) ; "center_dual" + growth LEFT/RIGHT reste empile verticalement
-- (l'axe horizontal est deja pris par la paire) ; changement de disposition a chaud necessite un
-- /reload (le champ "layout" est fige a la creation), meme limitation que Free Bars.
local iconListFlowContainer
local iconListFlowGroupAdded = false
iconListFlowButtons = {} -- forward-declaree plus haut (ProcGlowTick)
local iconListDualCounter = 0
-- [spellID] = true des qu'un AddAuraGroup dedie a ete cree (couleur/glow par sort, meme mecanique que
-- circleBarsPerSpellGroups). Bonus : le compteur gauche/droite (center_dual) devient deterministe,
-- les groupes etant crees dans l'ordre de priorite.
local iconListPerSpellGroups = {}

local function ILDBG(s) print("|cff33aaff[IconListFlow]|r " .. tostring(s)) end

function ns.GetIconListNativeContainer()
    return iconListFlowContainer
end

-- Geometrie partagee entre EnsureIconListFlowContainer/RepositionIconListNativeGrid/
-- EnsureIconListNativeGrid, evite la duplication des formules. Retourne toujours 12 valeurs, les 2
-- dernieres variant selon layout : center_dual = halfW, numPairs ; center_mirror = rowW, rowH.
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
            SafeSetPropagateMouseClicks(s, false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    iconListFlowContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        SafeSetPropagateMouseClicks(s, true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        -- Cf. commentaire equivalent sur "icons" -- GetCenter() peut renvoyer secret une fois lie a
        -- une vraie aura ; pcall : abandon silencieux plutot que planter.
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
        -- Paires horizontales fixes (axe 0), empilement vertical (LEFT/RIGHT traites comme DOWN).
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
            -- Spark : texture propre a l'addon, jamais secrete, toujours sure a retoucher.
            if btn._aishSparkL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {cR, cG, cB}) end
            if btn._aishSparkR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {cR, cG, cB}) end
            if btn._aishSpark then pcall(ApplyNativeBarSparkColor, btn._aishSpark, liveCfg, {cR, cG, cB}) end
            if btn._aishGlowAnchor then
                if ns.HideGlow then pcall(ns.HideGlow, btn._aishGlowAnchor) end
                pcall(ApplySpellGlow, btn._aishGlowAnchor, liveCfg, si, iw, ih)
            end
            -- Meme recette que Free Bars : cd:SetAllPoints(icon) a la creation sert directement de relFrame.
            if btn._aishCD then
                pcall(btn._aishCD.SetHideCountdownNumbers, btn._aishCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishCD, liveCfg, btn._aishCD)
                end
            end
        end
    end
end

-- Cree (une seule fois par sort) un AddAuraGroup dedie pour chaque spellID de "Liste d'icones", au
-- lieu d'un groupe unique partage -- permet une couleur/glow fixe par sort.
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
    -- Cape en nombre de groupes : en mode "center_dual" (Berserk), chaque groupe ne represente qu'une
    -- moitie de paire, le cap total reste 2*numPairs.
    local groupCap = isDual and (2 * b) or maxBars
    local spells = ns.GetSpecSpells()

    -- Cape a groupCap buffs (pas spellID) : une variante de tier (linkedSpellIDs) ne consomme qu'une place.
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

                            -- Icone
                            local icon = auraButton:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(liw, lih)
                            if lisDual then
                                icon:SetPoint(isLeft and "RIGHT" or "LEFT", auraButton, isLeft and "RIGHT" or "LEFT", 0, 0)
                            else
                                icon:SetPoint("CENTER", auraButton, "CENTER", 0, 0)
                            end
                            -- Crop conscient du ratio (meme recette que Free Bars) : sans ca, un slot
                            -- non-carre (liw ~= lih) etirait l'image visiblement.
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

                            -- Frame dediee pour le glow, calee sur l'icone (jamais sur auraButton).
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

                            -- Barre(s) de duree, couleur par sort.
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
                                -- Spark : bord mobile oppose au cote d'origine du remplissage ; la
                                -- reference est stockee pour pouvoir le recolorer plus tard.
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

                            -- Swipe + texte de duree natif.
                            cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
                            cd:SetDrawEdge(liveCfg.swipeEnabled == true)
                            cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
                            if liveCfg.timerIconEnabled then
                                ApplyNativeCountdownStyle(cd, liveCfg, icon)
                            end

                            -- Glow par sort.
                            ApplySpellGlow(auraButton._aishGlowAnchor, liveCfg, liveSi, liw, lih)
                            -- Animation d'entree, jouee une seule fois.
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
            -- Restaure le filtre correct si ce groupe avait ete de-trace puis re-trace (cf. Icons plus haut).
            pcall(c.SetAuraGroupCandidateFilters, c, "aishIconListFlow_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
        end
    end

    -- Sorts de-traques : meme neutralisation par spellID bidon que Icons plus haut (jamais {}).
    for spellID in pairs(iconListPerSpellGroups) do
        if not currentSet[spellID] then
            local groupKey = "aishIconListFlow_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

-- Grille native cible pour "Liste d'icones" (Debuffs.lua/iconlist, debuffs cible) -- meme principe que
-- les 3 miroirs cible ci-dessus : conteneur separe SetUnit("target")+"HARMFUL", ne route que les sorts
-- info.source=="debuff". Empile sous le conteneur joueur. Compteur gauche/droite (center_dual/Berserk)
-- independant du compteur joueur -- deux sequences qui n'ont pas a s'accorder entre elles.
local iconListFlowContainerTarget
local iconListFlowButtonsTarget = {}
local iconListPerSpellGroupsTarget = {}
local iconListDualCounterTarget = 0

function ns.GetIconListNativeContainerTarget()
    return iconListFlowContainerTarget
end

local function EnsureIconListFlowContainerTarget()
    if iconListFlowContainerTarget then return iconListFlowContainerTarget end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, result = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not result then
        ILDBG(string.format("|cffff4444EnsureIconListFlowContainerTarget: CreateFrame AuraContainer a echoue -- ok=%s result=%s|r", tostring(ok), tostring(result)))
        return nil
    end
    iconListFlowContainerTarget = result

    local cfg0 = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local bw0, bh0, iw0, ih0, gp0, pg0, rg0, layout0, isDual0, maxBars0, a0, b0 = IconListGeom(cfg0)
    local growth0 = cfg0.growth or "DOWN"
    if isDual0 then
        iconListFlowContainerTarget:SetSize(a0 * 2 + pg0, b0 * (ih0 + rg0))
    else
        local isH0 = (growth0 == "LEFT" or growth0 == "RIGHT")
        if isH0 then iconListFlowContainerTarget:SetSize(maxBars0 * (a0 + rg0), b0)
        else iconListFlowContainerTarget:SetSize(a0, maxBars0 * (b0 + rg0)) end
    end
    iconListFlowContainerTarget:SetFrameStrata("BACKGROUND")

    -- Position reelle ici, avant AddAuraGroup/UpdateAllAuras -- ancre sous/a cote du conteneur joueur
    -- selon la direction de croissance, sinon position de repli.
    if iconListFlowContainer then
        if growth0 == "UP" then iconListFlowContainerTarget:SetPoint("BOTTOM", iconListFlowContainer, "TOP", 0, rg0)
        elseif growth0 == "LEFT" then iconListFlowContainerTarget:SetPoint("RIGHT", iconListFlowContainer, "LEFT", -rg0, 0)
        elseif growth0 == "RIGHT" then iconListFlowContainerTarget:SetPoint("LEFT", iconListFlowContainer, "RIGHT", rg0, 0)
        else iconListFlowContainerTarget:SetPoint("TOP", iconListFlowContainer, "BOTTOM", 0, -rg0) end
    else
        local x0, y0 = cfg0.x or 0, cfg0.y or -290
        local fallbackH0 = isDual0 and (b0 * (ih0 + rg0)) or ((growth0 == "LEFT" or growth0 == "RIGHT") and bh0 or (maxBars0 * (b0 + rg0)))
        if growth0 == "UP" then iconListFlowContainerTarget:SetPoint("BOTTOM", UIParent, "CENTER", x0, y0 + fallbackH0)
        elseif growth0 == "LEFT" then iconListFlowContainerTarget:SetPoint("RIGHT", UIParent, "CENTER", x0 - fallbackH0, y0)
        elseif growth0 == "RIGHT" then iconListFlowContainerTarget:SetPoint("LEFT", UIParent, "CENTER", x0 + fallbackH0, y0)
        else iconListFlowContainerTarget:SetPoint("TOP", UIParent, "CENTER", x0, y0 - fallbackH0) end
    end

    local okEn, errEn = pcall(iconListFlowContainerTarget.SetEnabled, iconListFlowContainerTarget, true)
    local okUn, errUn = pcall(iconListFlowContainerTarget.SetUnit, iconListFlowContainerTarget, "target")
    if not okEn or not okUn then
        ILDBG(string.format("|cffff4444EnsureIconListFlowContainerTarget: SetEnabled ok=%s%s | SetUnit ok=%s%s|r",
            tostring(okEn), okEn and "" or (" err="..tostring(errEn)),
            tostring(okUn), okUn and "" or (" err="..tostring(errUn))))
    end
    iconListFlowContainerTarget:Show()
    return iconListFlowContainerTarget
end

function ns.RefreshIconListNativeGridStyleTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local liveCfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local spells = ns.GetSpecSpells()
    local bw, bh, iw, ih = IconListGeom(liveCfg)
    for _, btn in ipairs(iconListFlowButtonsTarget) do
        local okCheck, canAccess = pcall(function()
            return btn.CanBeAccessedInContext and btn:CanBeAccessedInContext()
        end)
        if okCheck and canAccess then
            local si = btn._aishSpellID and spells and spells[btn._aishSpellID]
            local cR, cG, cB = SpellBarColorRGB(liveCfg, si)
            if btn._aishBarL then pcall(btn._aishBarL.SetStatusBarColor, btn._aishBarL, cR, cG, cB) end
            if btn._aishBarR then pcall(btn._aishBarR.SetStatusBarColor, btn._aishBarR, cR, cG, cB) end
            if btn._aishBar then pcall(btn._aishBar.SetStatusBarColor, btn._aishBar, cR, cG, cB) end
            if btn._aishSparkL then pcall(ApplyNativeBarSparkColor, btn._aishSparkL, liveCfg, {cR, cG, cB}) end
            if btn._aishSparkR then pcall(ApplyNativeBarSparkColor, btn._aishSparkR, liveCfg, {cR, cG, cB}) end
            if btn._aishSpark then pcall(ApplyNativeBarSparkColor, btn._aishSpark, liveCfg, {cR, cG, cB}) end
            if btn._aishGlowAnchor then
                if ns.HideGlow then pcall(ns.HideGlow, btn._aishGlowAnchor) end
                pcall(ApplySpellGlow, btn._aishGlowAnchor, liveCfg, si, iw, ih)
            end
            if btn._aishCD then
                pcall(btn._aishCD.SetHideCountdownNumbers, btn._aishCD, not liveCfg.timerIconEnabled)
                if liveCfg.timerIconEnabled then
                    ApplyNativeCountdownStyle(btn._aishCD, liveCfg, btn._aishCD)
                end
            end
        end
    end
end

function ns.RepositionIconListNativeGridTarget()
    local c = iconListFlowContainerTarget or EnsureIconListFlowContainerTarget()
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
    if iconListFlowContainer then
        if growth == "UP" then c:SetPoint("BOTTOM", iconListFlowContainer, "TOP", 0, rg)
        elseif growth == "LEFT" then c:SetPoint("RIGHT", iconListFlowContainer, "LEFT", -rg, 0)
        elseif growth == "RIGHT" then c:SetPoint("LEFT", iconListFlowContainer, "RIGHT", rg, 0)
        else c:SetPoint("TOP", iconListFlowContainer, "BOTTOM", 0, -rg) end
    else
        local x, y = cfg.x or 0, cfg.y or -290
        local fallbackH = isDual and (b * (ih + rg)) or ((growth == "LEFT" or growth == "RIGHT") and bh or (maxBars * (b + rg)))
        if growth == "UP" then c:SetPoint("BOTTOM", UIParent, "CENTER", x, y + fallbackH)
        elseif growth == "LEFT" then c:SetPoint("RIGHT", UIParent, "CENTER", x - fallbackH, y)
        elseif growth == "RIGHT" then c:SetPoint("LEFT", UIParent, "CENTER", x + fallbackH, y)
        else c:SetPoint("TOP", UIParent, "CENTER", x, y - fallbackH) end
    end

    local okA, okX, okG, okM, errA, errX, errG, errM
    if isDual then
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
        ILDBG(string.format("|cffff4444RepositionIconListNativeGridTarget: SetFlowLayout* a echoue -- anchor=%s axis=%s growth=%s maxline=%s|r",
            okA and "ok" or tostring(errA), okX and "ok" or tostring(errX), okG and "ok" or tostring(errG), okM and "ok" or tostring(errM)))
    end

    local visible = (ns.db == nil or ns.db.iconlistEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        c:SetAlpha(1)
    else
        c:SetAlpha(0)
    end
    pcall(ns.RefreshIconListNativeGridStyleTarget)
end

-- Cree (une seule fois par sort) un AddAuraGroup dedie par debuff cible de "Liste d'icones",
-- SetUnit("target")+"HARMFUL". Appelee depuis Whitelist.lua juste apres ns.EnsureIconListNativeGrid.
function ns.EnsureIconListNativeGridTarget()
    if InCombatLockdown and InCombatLockdown() then return end
    local c = EnsureIconListFlowContainerTarget()
    if not c then return end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.iconlist
    if not order or #order == 0 then return end

    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local bw, bh, iw, ih, gp, pg, rg, layout, isDual, maxBars, a, b = IconListGeom(cfg)
    local elemW, elemH = a, ih
    local groupCap = isDual and (2 * b) or maxBars
    local spells = ns.GetSpecSpells()

    local wl = ns.whitelistByDest and ns.whitelistByDest.iconlist
    local seenInfo, capState = {}, { count = 0 }
    local currentSet = {}
    for _, spellID in ipairs(order) do
        local info = spells and spells[spellID]
        if info and info.source == "debuff" then
            if not AllowNextCapSlot(wl, spellID, groupCap, seenInfo, capState) then break end
            currentSet[spellID] = true
            if not iconListPerSpellGroupsTarget[spellID] then
                local groupKey = "aishIconListFlowTarget_" .. tostring(spellID)
                local si = spells and spells[spellID]
                local okAdd, errAdd = pcall(function()
                    -- "HARMFUL|PLAYER" (pas juste "HARMFUL") : filtre standard Blizzard restreignant
                    -- aux auras dont le joueur est la source (cf. TargetAuras.lua "onlyPlayer"). Sans
                    -- ca, candidateFilters seul etait insuffisant : un debuff ennemi etranger pouvait
                    -- se lier au slot (bug "debuff parasite dans Liste d'icones").
                    c:AddAuraGroup(groupKey, "HARMFUL|PLAYER", {
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
                                    iconListDualCounterTarget = iconListDualCounterTarget + 1
                                    isLeft = (iconListDualCounterTarget % 2 == 1)
                                end

                                local icon = auraButton:CreateTexture(nil, "ARTWORK")
                                auraButton._aishIcon = icon  -- ref pour /aishdebug iconlistrows (comparer texture reelle vs spellID attendu)
                                icon:SetSize(liw, lih)
                                if lisDual then
                                    icon:SetPoint(isLeft and "RIGHT" or "LEFT", auraButton, isLeft and "RIGHT" or "LEFT", 0, 0)
                                else
                                    icon:SetPoint("CENTER", auraButton, "CENTER", 0, 0)
                                end
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

                                local glowAnchor = CreateFrame("Frame", nil, auraButton)
                                glowAnchor:SetAllPoints(icon)
                                auraButton._aishGlowAnchor = glowAnchor

                                local cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
                                cd:SetAllPoints(icon)
                                cd:SetReverse(true)
                                auraButton:SetDurationCooldown(cd)
                                auraButton._aishCD = cd

                                local stackFS = auraButton:CreateFontString(nil, "OVERLAY", nil, 7)
                                ns.ApplyFont(stackFS, liveCfg.stackFont or ns.Media.font, liveCfg.stackSize or 10, "OUTLINE")
                                stackFS:SetPoint(liveCfg.stackPos or "BOTTOMRIGHT", icon, liveCfg.stackPos or "BOTTOMRIGHT", liveCfg.stackOffX or 0, liveCfg.stackOffY or 0)
                                stackFS:SetJustifyH("RIGHT")
                                stackFS:SetTextColor(liveCfg.stackColorR or 1, liveCfg.stackColorG or 1, liveCfg.stackColorB or 1)
                                auraButton:SetApplicationCount(stackFS, {})
                                auraButton._aishStackFS = stackFS

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
                                    if not okBar then ILDBG(string.format("|cffff4444initializeFrame cible (Icon List, sort %d): SetDurationBar a echoue -- err=%s|r", spellID, tostring(errBar))) end
                                    local spark = MakeNativeBarSpark(bar, liveCfg, rev and "LEFT" or "RIGHT", {barCR, barCG, barCB})
                                    return bar, spark
                                end

                                if lisDual then
                                    if isLeft then
                                        auraButton._aishBar, auraButton._aishSpark = MakeNativeBar("RIGHT", icon, "LEFT", -lgp, 0, true)
                                    else
                                        auraButton._aishBar, auraButton._aishSpark = MakeNativeBar("LEFT", icon, "RIGHT", lgp, 0, false)
                                    end
                                else
                                    auraButton._aishBarL, auraButton._aishSparkL = MakeNativeBar("RIGHT", icon, "LEFT", -lgp, 0, true)
                                    auraButton._aishBarR, auraButton._aishSparkR = MakeNativeBar("LEFT", icon, "RIGHT", lgp, 0, false)
                                end

                                cd:SetDrawSwipe(liveCfg.swipeEnabled == true)
                                cd:SetDrawEdge(liveCfg.swipeEnabled == true)
                                cd:SetHideCountdownNumbers(liveCfg.timerIconEnabled ~= true)
                                if liveCfg.timerIconEnabled then
                                    ApplyNativeCountdownStyle(cd, liveCfg, icon)
                                end

                                ApplySpellGlow(auraButton._aishGlowAnchor, liveCfg, liveSi, liw, lih)
                                PlayProcStartOnce(auraButton._aishGlowAnchor, liveSi, spellID)

                                iconListFlowButtonsTarget[#iconListFlowButtonsTarget + 1] = auraButton
                            end)
                            if not okBuild then
                                ILDBG(string.format("|cffff4444initializeFrame cible (Icon List, sort %d): creation des widgets a echoue -- err=%s|r", spellID, tostring(errBuild)))
                            end
                        end,
                    })
                end)
                if not okAdd then
                    ILDBG(string.format("|cffff4444AddAuraGroup DEDIE cible (Icon List, sort %d) a echoue -- err=%s|r", spellID, tostring(errAdd)))
                end
                iconListPerSpellGroupsTarget[spellID] = true
                if c.UpdateAllAuras then
                    local okUpd, errUpd = pcall(c.UpdateAllAuras, c)
                    if not okUpd then ILDBG(string.format("|cffff4444UpdateAllAuras cible (Icon List, sort %d) a echoue -- err=%s|r", spellID, tostring(errUpd))) end
                end
            else
                pcall(c.SetAuraGroupCandidateFilters, c, "aishIconListFlowTarget_" .. tostring(spellID), { includeSpellIDs = { [spellID] = true } })
            end
        end
    end

    for spellID in pairs(iconListPerSpellGroupsTarget) do
        if not currentSet[spellID] then
            local groupKey = "aishIconListFlowTarget_" .. tostring(spellID)
            pcall(c.SetAuraGroupCandidateFilters, c, groupKey, { includeSpellIDs = { [0] = true } })
        end
    end
end

local iconListTargetChangeFrame = CreateFrame("Frame")
iconListTargetChangeFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
iconListTargetChangeFrame:SetScript("OnEvent", function()
    if iconListFlowContainerTarget and iconListFlowContainerTarget.UpdateAllAuras then
        pcall(iconListFlowContainerTarget.UpdateAllAuras, iconListFlowContainerTarget)
    end
end)


-- /aishdebug groups -- diagnostic de l'usage memoire des groupes natifs : chacune des 4 destinations
-- cree un AddAuraGroup dedie par spellID la premiere fois qu'il est traque, avec toute une
-- arborescence de widgets -- contrainte native Blizzard, un groupe ne peut jamais etre supprime.
-- Chaque spellID traque au moins une fois laisse donc des widgets alloues en permanence jusqu'au
-- prochain /reload, meme decoche ensuite. Dump ce compteur pour distinguer une accumulation normale
-- (tests repetes sur beaucoup de sorts) d'une vraie fuite.
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

-- /aishdebug iconlistrows -- dump direct du pool de boutons Liste d'icones (joueur ET cible), spellID
-- assigne, visibilite et nom du sort. Contrairement a /aishdebug spell <id> (qui demande de deviner le
-- spellID), ceci liste tout ce qui existe reellement -- utile pour reperer un spellID inattendu.
function ns.DebugDumpIconListRows()
    local P = function(s) print("|cff00ccffAishCore Debug|r " .. s) end
    P("=== Liste d'icones -- boutons reellement crees (pool joueur + cible) ===")
    local totalCount, mismatchCount = 0, 0
    local function DumpPool(label, pool)
        if not pool or #pool == 0 then
            P(string.format("  %s : aucun bouton cree", label))
            return
        end
        for i, btn in ipairs(pool) do
            local sid = btn and btn._aishSpellID
            local okShown, shown = pcall(function() return btn:IsShown() end)
            local name = sid and GetSpellName and GetSpellName(sid) or "?"
            local spells = ns.GetSpecSpells()
            local inWL = sid and spells and spells[sid] and spells[sid].destinations and spells[sid].destinations.iconlist and true or false
            -- Compare la texture reellement peinte (icon:GetTexture(), objet Texture simple, pas
            -- soumis aux memes restrictions "forbidden" que l'auraButton) a celle attendue pour ce
            -- spellID : si les fileID different, Blizzard peint autre chose que prevu pour ce slot.
            local texActual, texExpected = "?", "?"
            if btn and btn._aishIcon then
                local okTex, t = pcall(function() return btn._aishIcon:GetTexture() end)
                texActual = okTex and tostring(t) or "err"
            end
            if sid and C_Spell and C_Spell.GetSpellTexture then
                local okTex2, t2 = pcall(C_Spell.GetSpellTexture, sid)
                texExpected = okTex2 and tostring(t2) or "err"
            end
            local texMismatch = (texActual ~= "?" and texExpected ~= "?" and texActual ~= texExpected)
            totalCount = totalCount + 1
            if texMismatch then
                mismatchCount = mismatchCount + 1
                P(string.format("  %s[%d] spellID=%s (%s) | IsShown=%s | dansWhitelist(iconlist)=%s | texture=%s attendu=%s |cffff4444<<< MISMATCH|r",
                    label, i, tostring(sid), tostring(name), okShown and tostring(shown) or "err", tostring(inWL),
                    texActual, texExpected))
            end
        end
    end
    DumpPool("joueur", iconListFlowButtons)
    DumpPool("cible ", iconListFlowButtonsTarget)
    P(string.format("=== %d/%d boutons ont une texture peinte differente de celle attendue pour leur spellID assigne ===",
        mismatchCount, totalCount))
    if mismatchCount == 0 then
        P("Aucun mismatch texture -- si un debuff etranger reste visible malgre ca, relance avec l'ancienne version detaillee (pas de mismatch != rien d'anormal, juste ce signal-la est propre).")
    end
end

-- /aishdebug spell <id1> [id2] ... -- diagnostic cible pour un buff multi-tier (ex: Jet d'osselets
-- Hors-la-loi, 4 spellID pour 1 seul buff conceptuel) : montre si chaque spellID est connu dans
-- ns.GetSpecSpells(), figure dans l'ordre whitelist de chaque destination, et a deja un AddAuraGroup
-- dedie cree. Present dans slotOrderByDest sans groupe cree = jamais rencontre en jeu depuis le
-- dernier /reload (le groupe se cree a la premiere apparition).
function ns.DebugDumpSpellTracking(...)
    local ids = { ... }
    if #ids == 0 then
        print("|cff00ccffAishCore Debug|r Usage: /aishdebug spell <spellID> [spellID2] ...")
        return
    end
    local spells = ns.GetSpecSpells()
    -- Chaque destination a 2 tables de groupes dedies distinctes (joueur HELPFUL, cible HARMFUL) --
    -- ce diagnostic ignorait les tables cote cible, un groupe fantome y ressortait a tort comme
    -- groupeDedieCree=false alors qu'il peut continuer d'afficher un debuff hors whitelist actuelle.
    local destGroups = {
        icons      = iconsPerSpellGroups,
        circlebars = freeBarsPerSpellGroups,   -- GUI "Free Bars"
        freebars   = circleBarsPerSpellGroups, -- GUI "Circle Bars"
        iconlist   = iconListPerSpellGroups,
    }
    local destGroupsTarget = {
        icons      = iconsPerSpellGroupsTarget,
        circlebars = freeBarsPerSpellGroupsTarget,
        freebars   = circleBarsPerSpellGroupsTarget,
        iconlist   = iconListPerSpellGroupsTarget,
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
                local hasGroupPlayer = destGroups[dest][spellID] and true or false
                local hasGroupTarget = destGroupsTarget[dest][spellID] and true or false
                print(string.format("    %-10s dansWhitelist=%-5s  groupeDedieCree(joueur)=%-5s  groupeDedieCree(cible)=%-5s",
                    dest, tostring(inOrder), tostring(hasGroupPlayer), tostring(hasGroupTarget)))
            end
        end
    end
end

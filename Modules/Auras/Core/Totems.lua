-- AishUIAura/Core/Totems.lua
-- Categorie "Totems" : sorts qui posent un totem/effet au sol persistant (Chaman, Consecration...).
-- Blizzard gere ces effets via GetTotemInfo/GetTotemDuration (4 slots), invisible au pipeline CDM/aura classique.
-- Decouverte : correle UNIT_SPELLCAST_SUCCEEDED (spellID) avec PLAYER_TOTEM_UPDATE (slot), jamais de comparaison
-- de valeur GetTotemInfo/GetTotemDuration (non fiable, cf. historique plus bas).
-- Rendu manuel (frames normales pilotees par notre scan) car pas de vraie aura Blizzard a matcher via AddAuraGroup ;
-- combat-safe via SetCooldownFromDurationObject/SetTimerDuration qui consomment le durObj sans le reveler.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
local pcall, tostring, ipairs, pairs, wipe = pcall, tostring, ipairs, pairs, wipe

local MAX_TOTEM_SLOTS = 4

local function SafeSpellName(spellID)
    local ok, name = pcall(GetSpellName, spellID)
    if ok and name and not (issecretvalue and issecretvalue(name)) then return name end
    return nil
end

-- [slot] = spellID lie a ce slot par le dernier cast confirme.
local slotSpellID = {}

-- Scan des slots de totem a partir des liens slot->spellID etablis.
-- [spellID] = { durObj=..., slot=..., instID=... } pour les totems actifs, reconstruit a chaque scan.
local activeTotems = {}
-- Compteur d'instance Lua pur, incremente uniquement quand le durObj d'un slot change.
local _totemInstCounter = 0
local _lastDurObjRefBySlot = {}

-- Cle par spellID (pas par slot) : si 2 slots sont lies au meme sort, seul le dernier scanne gagne l'affichage
-- (distinguer par slot cree plus de faux positifs qu'il n'aide, l'identification par nom/valeur n'est pas fiable).
local function RescanActiveTotems()
    wipe(activeTotems)
    if not GetTotemDuration then return end
    for slot = 1, MAX_TOTEM_SLOTS do
        local spellID = slotSpellID[slot]
        if spellID then
            local ok, durObj = pcall(GetTotemDuration, slot)
            if ok and durObj then
                local ref = tostring(durObj)
                if _lastDurObjRefBySlot[slot] ~= ref then
                    _lastDurObjRefBySlot[slot] = ref
                    _totemInstCounter = _totemInstCounter + 1
                end
                activeTotems[spellID] = { durObj = durObj, slot = slot, instID = -_totemInstCounter }
            else
                -- Plus de duree lisible : le totem est retombe, on libere le lien pour ce slot.
                slotSpellID[slot] = nil
                _lastDurObjRefBySlot[slot] = nil
            end
        end
    end
end

-- Decouverte + liaison slot<->spellID : comparer les valeurs GetTotemInfo/GetTotemDuration (objet frais a
-- chaque appel, ou comparaison de chaines rejetee) s'est revele non fiable en jeu, quelle que soit la methode.
-- Solution : correler PLAYER_TOTEM_UPDATE(slot) (argument d'evenement fiable) avec le dernier
-- UNIT_SPELLCAST_SUCCEEDED (spellID fiable). Limite acceptee : un cast secondaire automatique tres frequent
-- (ex. talent qui recast un autre sort a chaque pose) peut voler la liaison ; non distinguable, cas rare ignore.
local function RegisterTotemSpell(spellID, name)
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells or spells[spellID] then return end
    local defaults = ns.DeepCopy(ns.SpellDefaults)
    defaults.name = name or SafeSpellName(spellID) or tostring(spellID)
    local bc = ns.barColor or {1, 1, 1}
    defaults.color = { bc[1], bc[2], bc[3] }
    defaults._colorDefault = false
    defaults.priority = spellID
    defaults.source = "totem"
    defaults.destinations = { iconlist = false, circlebars = false, icons = false, freebars = false, totems = false }
    spells[spellID] = defaults
    if ns.BuildWhitelist then pcall(ns.BuildWhitelist) end
end

-- File FIFO des sorts candidats recemment lances (pas encore confirmes comme totem), consommee par
-- PLAYER_TOTEM_UPDATE dans l'ordre de cast -- une case unique se ferait ecraser en cas de pose rapprochee.
local pendingCastQueue = {} -- { {spellID=..., time=...}, ... }, plus ancien en tete
local PENDING_WINDOW = 1.0 -- secondes

-- Appelee a chaque cast reussi du joueur, filtre tot les sorts deja classes debuff/equipment.
local function OnPlayerCastSucceeded(spellID)
    if not spellID then return end
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    local existing = spells[spellID]
    if existing and (existing.source == "debuff" or existing.source == "equipment") then return end
    pendingCastQueue[#pendingCastQueue + 1] = { spellID = spellID, time = GetTime() }
    if #pendingCastQueue > 8 then table.remove(pendingCastQueue, 1) end
end

-- Appelee sur PLAYER_TOTEM_UPDATE(slot), qui se declenche pour la pose ET le retrait/expiration ;
-- un test de presence pure (startTime truthy) filtre les retraits pour ne lier que les poses reelles.
local function OnTotemSlotChanged(slot)
    if not (slot and GetTotemInfo) then return end
    local okInfo, have, name, startTime = pcall(GetTotemInfo, slot)
    if not (okInfo and startTime) then return end -- retrait/expiration, pas une pose : rien a lier

    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end

    -- Purge les candidats perimes en tete de file (plus vieux que la
    -- fenetre), puis consomme le PLUS ANCIEN candidat restant (FIFO).
    local now = GetTime()
    while pendingCastQueue[1] and (now - pendingCastQueue[1].time) > PENDING_WINDOW do
        table.remove(pendingCastQueue, 1)
    end
    if not pendingCastQueue[1] then return end
    local spellID = table.remove(pendingCastQueue, 1).spellID
    slotSpellID[slot] = spellID
    local info = spells[spellID]
    if info then
        if info.source ~= "totem" then
            info.source = "totem"
            -- Desactive les 4 autres destinations : sinon elles restent actives (invisibles/indecochables
            -- dans l'UI reclassifiee "T") et rendent des barres fantomes en plus de la barre totem attendue.
            if info.destinations then
                info.destinations.iconlist = false
                info.destinations.circlebars = false
                info.destinations.freebars = false
                info.destinations.icons = false
            end
            if ns.BuildWhitelist then pcall(ns.BuildWhitelist) end
        end
    else
        RegisterTotemSpell(spellID)
    end
end

-- Rendu manuel, destination dediee "Totems" (5e destination, reglages/look copies de "Free Bars").
-- Pas d'AddAuraGroup possible (aucune vraie aura Blizzard) -- frames normales pilotees par RescanActiveTotems.
-- Simplifications vs Free Bars natif : pas de spark mobile, pas de degrade/couleurs d'urgence/stacks/pop anim
-- (reglages visibles dans le panneau pour coherence UI mais sans effet ici). Un widget par spellID : si 2 slots
-- sont lies au meme sort, ils partagent le meme widget (pas de 2e instance affichee).
local totemsContainer
local totemWidgets = {} -- [spellID] = frame

-- Preview live (menu "Totems" et page "Auras a tracker") : "totems" ne passe jamais par Scan:Run/BuildPreviewEntries
-- (rendu 100% manuel), donc geree ici a la main pour ne pas laisser ces pages vides hors combat.
-- ns._previewMode=="totems" : PREVIEW_COUNT widgets, vrais sorts coches completes par des ids factices.
-- ns._previewMode=="all" + _previewNoFallback : seuls les sorts reellement coches previsualisent.
-- IDs magiques 900001-900003 (convention partagee avec Scan.lua) : jamais de collision avec un vrai spellID.
local PREVIEW_COUNT = 3
local PREVIEW_IDS = { 900001, 900002, 900003 }
local PREVIEW_ICONS = {
    "Interface\\Icons\\Spell_Fire_SearingTotem",
    "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    "Interface\\Icons\\Spell_Nature_ManaRegenTotem",
}

local function IsTotemsPreviewActive()
    return ns._previewBars == true and (ns._previewMode == "totems" or ns._previewMode == "all")
end

-- spellID reel prioritaire (vraies couleurs/icone), complete par un id factice sauf en mode "fidele" (noFallback).
local function BuildTotemsPreviewOrder()
    local out = {}
    local realOrder = ns.slotOrderByDest and ns.slotOrderByDest.totems
    local noFallback = ns._previewNoFallback
    for i = 1, PREVIEW_COUNT do
        local realSID = realOrder and realOrder[i]
        if noFallback and not realSID then break end
        out[i] = realSID or PREVIEW_IDS[i]
    end
    return out
end

-- Boucle d'animation de la preview (icone + barres), pilotee a la main puisqu'il n'y a pas de durObj a boucler.
-- Cooldown:SetCooldown anime le swipe/decompte seul ; les barres sont recalculees a chaque tick (pas d'auto-anim).
-- Le ticker s'auto-arrete des que la preview n'est plus active.
local PREVIEW_CYCLE = 8
local previewTicker

local function EnsurePreviewTicker()
    if previewTicker then return end
    previewTicker = CreateFrame("Frame")
    local acc = 0
    previewTicker:SetScript("OnUpdate", function(self, elapsed)
        if not IsTotemsPreviewActive() then
            self:SetScript("OnUpdate", nil)
            previewTicker = nil
            return
        end
        acc = acc + elapsed
        if acc < 0.05 then return end -- ~20fps, meme cadence que le driver d'anim generique
        acc = 0
        local now = GetTime()
        for _, f in pairs(totemWidgets) do
            if f:IsShown() then
                if not f._previewStart or (now - f._previewStart) >= PREVIEW_CYCLE then
                    f._previewStart = now
                    if f.cd then pcall(f.cd.SetCooldown, f.cd, now, PREVIEW_CYCLE) end
                end
                local pct = 1 - ((now - f._previewStart) / PREVIEW_CYCLE)
                if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
                local function SetBarPct(bar)
                    if not bar then return end
                    pcall(bar.SetMinMaxValues, bar, 0, 1)
                    pcall(bar.SetValue, bar, pct)
                end
                SetBarPct(f.bar); SetBarPct(f.barL); SetBarPct(f.barR)
            end
        end
    end)
end

local function TDBG(s) print("|cff33aaff[TotemsFlow]|r " .. tostring(s)) end

-- Reactive la propagation au prochain retour hors combat si SetPropagateMouseClicks(true) echoue en combat.
local function TotemsSafeSetPropagateMouseClicks(f, allow)
    local ok = pcall(f.SetPropagateMouseClicks, f, allow)
    if ok or not allow then return end
    local retryFrame = CreateFrame("Frame")
    retryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    retryFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pcall(f.SetPropagateMouseClicks, f, true)
    end)
end

local function EnsureTotemsContainer()
    if totemsContainer then return totemsContainer end
    totemsContainer = CreateFrame("Frame", nil, UIParent)
    totemsContainer:SetSize(8, 8)
    -- BUG CORRIGE (confirme en jeu) : jamais de SetFrameStrata ici, contraiement
    -- a TOUS les autres containers equivalents (iconlist/circlebars/icons via
    -- AuraTrackerContainer.lua, tous en "BACKGROUND") -- ce container restait
    -- donc a la strate par defaut de Blizzard ("MEDIUM"), au-dessus de la
    -- barre de familier/action bars a cet endroit. Meme quand aucun widget
    -- totem n'est visible, un survol dans cette zone pouvait donc intercepter
    -- la souris (tooltip fantome) et bloquer le clic sur ce qu'il y a en
    -- dessous.
    totemsContainer:SetFrameStrata("BACKGROUND")
    totemsContainer:Show()

    -- Enregistre aupres du mecanisme de fade GENERIQUE existant
    -- (ns.UpdateRenderFade("totems") retombera sur ce container via
    -- ns.renderFrames.totems.container -- meme "ancien" mecanisme manuel
    -- toujours fonctionnel derriere iconlist/freebars/circlebars/icons avant
    -- leur migration vers des groupes AddAuraGroup natifs, cf.
    -- Modules/Auras/Core/Animation.lua).
    ns.renderFrames = ns.renderFrames or {}
    ns.renderFrames.totems = { container = totemsContainer }

    -- Deplacement : Alt+clic gauche, meme pattern que Free Bars/Icons/etc.
    totemsContainer:SetMovable(true)
    totemsContainer:SetClampedToScreen(true)
    if _addon.EnableMouseOnlyOnAlt then _addon.EnableMouseOnlyOnAlt(totemsContainer) end
    -- Contrairement aux autres conteneurs (crees a l'init/reload, rarement en
    -- combat), celui-ci est cree paresseusement au 1er evenement totem recu,
    -- qui tombe tres souvent EN COMBAT (un chaman pose ses totems en combat).
    -- SetPropagateMouseClicks est protege -> pcall + retry via la fonction
    -- ci-dessus (confirme en jeu : ADDON_ACTION_BLOCKED sur ce SetPropagateMouseClicks).
    TotemsSafeSetPropagateMouseClicks(totemsContainer, true)
    local dragLbl = totemsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragLbl:SetPoint("BOTTOM", totemsContainer, "TOP", 0, 4)
    dragLbl:SetText("|cffffcc00" .. (_addon.L and _addon.L["AURASFEAT_ALT_DRAG_HINT"] or "") .. "|r")
    dragLbl:Hide()
    totemsContainer:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            TotemsSafeSetPropagateMouseClicks(s, false)
            s:StartMoving(); dragLbl:Show()
        end
    end)
    totemsContainer:SetScript("OnMouseUp", function(s)
        s._aishDragging = false; s:StopMovingOrSizing()
        TotemsSafeSetPropagateMouseClicks(s, true)
        dragLbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        if cx and cy and ns.db and ns.db.totems then
            pcall(function()
                ns.db.totems.x = cx*sc - sx
                ns.db.totems.y = cy*sc - sy
            end)
        end
    end)
    return totemsContainer
end

-- Dimensions widget/conteneur : meme formule que Free Bars pour un look identique.
local function GetTotemsDims(cfg)
    local maxBars = cfg.maxBars or 8
    local iw = cfg.hideIcon and 0 or (cfg.iconW or 28)
    local gp = cfg.hideIcon and 0 or (cfg.gap or 3)
    local bw, bh, ih, rg = cfg.barW or 147, cfg.barH or 4, cfg.iconH or 19, cfg.rowGap or 1
    local layout = cfg.layout or "side_large"
    local rowW, rowH
    if layout == "side_compact" then rowW = bw*2+iw+gp*2; rowH = ih
    elseif layout == "side_banner" then rowW = (cfg.hideIcon and bw or iw); rowH = ih + gp + bh
    else rowW = iw + gp + bw; rowH = ih end
    return maxBars, iw, gp, bw, bh, ih, rg, layout, rowW, rowH
end

-- Meme ordre de priorite que ResolveBarColor (Init.lua) : couleur explicite du render, puis couleur
-- par sort si ns.db.useSpellColors, puis couleur de classe globale.
local function TotemBarColorRGB(cfg, si)
    local bc = ns.barColor or {1, 1, 1}
    if cfg and cfg.barColorR ~= nil then
        return cfg.barColorR, cfg.barColorG or bc[2], cfg.barColorB or bc[3]
    end
    if ns.db and ns.db.useSpellColors and si and si.color then
        return si.color[1], si.color[2], si.color[3]
    end
    return bc[1], bc[2], bc[3]
end

-- Police/taille/couleur/position du texte de decompte natif, via la meme fonction partagee (ns._StyleCountdownFS).
local function StyleTotemTimerText(f, cfg)
    if not (f.cd and cfg.timerIconEnabled and ns._StyleCountdownFS) then return end
    local pos = cfg.timerPos or "CENTER"
    pcall(ns._StyleCountdownFS, f.cd, cfg.timerFont or ns.Media.font, cfg.timerSize or 12,
        cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
        pos, f.icon or f.cd, pos, cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
end

-- Glow par sort : override du render (cfg.glowOverride*) prioritaire, sinon glow propre au sort.
local function ApplyTotemGlow(glowAnchor, cfg, info, iw, ih)
    if ns.HideGlow then pcall(ns.HideGlow, glowAnchor) end
    if cfg.glowEnabled == false then return end
    local idx = cfg.glowOverrideIdx or (info and info.glowIdx)
    if not (idx and idx > 1) then return end
    local color = (cfg.glowOverrideR and { cfg.glowOverrideR, cfg.glowOverrideG, cfg.glowOverrideB })
        or (info and info.glowColor) or (info and info.color)
    local alpha = cfg.glowOverrideAlpha or (info and info.glowAlpha)
    local scale = cfg.glowOverrideScale or (info and info.glowScale)
    if ns.ShowGlow then pcall(ns.ShowGlow, glowAnchor, idx, color, alpha, scale, iw, ih) end
end

-- Construit un widget COMPLET (icone + barre(s)) pour spellID selon la
-- disposition courante -- meme geometrie que initializeFrame de
-- EnsureFreeBarsNativeGrid (side_large "Vanguard" / side_compact "Sparte" /
-- side_banner "Banner"), mais en frames manuelles (pas d'AuraContainer).
local function BuildTotemWidget(spellID, cfg, layout, rowW, rowH, iw, ih, gp, bw, bh)
    local cont = EnsureTotemsContainer()
    local f = CreateFrame("Frame", nil, cont)
    f:SetSize(rowW, rowH)
    f:Hide()

    local icon
    if not cfg.hideIcon then
        icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iw, ih)
        if layout == "side_banner" then
            icon:SetPoint("TOP", f, "TOP", 0, 0)
        elseif layout == "side_compact" then
            icon:SetPoint("CENTER", f, "CENTER", 0, 0)
        else
            if (cfg.iconPos or "RIGHT") == "RIGHT" then
                icon:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            else
                icon:SetPoint("LEFT", f, "LEFT", 0, 0)
            end
        end
        local okTex, tex = pcall(C_Spell.GetSpellTexture, spellID)
        icon:SetTexture((okTex and tex) or 134400)
        -- Crop conscient du ratio, meme recette que les grilles natives.
        do
            local tcv = 0.07
            local usable = 1 - 2 * tcv
            if iw > ih then
                local vSpan = (ih / iw) * usable
                icon:SetTexCoord(tcv, 1 - tcv, 0.5 - vSpan * 0.5, 0.5 + vSpan * 0.5)
            elseif ih > iw then
                local uSpan = (iw / ih) * usable
                icon:SetTexCoord(0.5 - uSpan * 0.5, 0.5 + uSpan * 0.5, tcv, 1 - tcv)
            else
                icon:SetTexCoord(tcv, 1 - tcv, tcv, 1 - tcv)
            end
        end
        local border = f:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        border:SetColorTexture(14/255, 14/255, 14/255, 1)
        f.icon = icon

        local glowAnchor = CreateFrame("Frame", nil, f)
        glowAnchor:SetAllPoints(icon)
        f.glowAnchor = glowAnchor

        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetReverse(true)
        cd:SetDrawSwipe(cfg.swipeEnabled == true)
        cd:SetDrawEdge(cfg.swipeEnabled == true)
        cd:SetHideCountdownNumbers(cfg.timerIconEnabled ~= true)
        f.cd = cd
    end

    local barTex = ns.ResolveBarTexFromKey(cfg.texture)
    local bgR, bgG, bgB, bgA = cfg.barBgR or 0, cfg.barBgG or 0, cfg.barBgB or 0, cfg.barBgAlpha or 0

    local function MakeBar(w, h, point, relTo, relPoint, ox, oy, rev)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetSize(w, h)
        bar:SetPoint(point, relTo, relPoint, ox, oy)
        bar:SetStatusBarTexture(barTex)
        if rev then bar:SetReverseFill(true) end
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(bgR, bgG, bgB, bgA)
        return bar
    end

    if layout == "side_compact" then
        -- Sparte : icone centree, 2 barres miroir.
        local anchorRef = cfg.hideIcon and f or icon
        local relL = cfg.hideIcon and "CENTER" or "LEFT"
        local relR = cfg.hideIcon and "CENTER" or "RIGHT"
        f.barL = MakeBar(bw, bh, "RIGHT", anchorRef, relL, -gp, 0, true)
        f.barR = MakeBar(bw, bh, "LEFT", anchorRef, relR, gp, 0, false)
    elseif layout == "side_banner" then
        -- Banner : icone au-dessus (ou rien si hideIcon), barre en-dessous.
        local bannerW = cfg.hideIcon and bw or iw
        if cfg.hideIcon then
            f.bar = MakeBar(bannerW, bh, "TOP", f, "TOP", 0, 0, cfg.reverse == true)
        else
            f.bar = MakeBar(bannerW, bh, "TOP", icon, "BOTTOM", 0, -gp, cfg.reverse == true)
        end
    else
        -- Vanguard : icone + 1 barre a cote. "Miroir" (cfg.iconPos) change le
        -- cote de la barre par rapport a l'icone -- le sens de remplissage
        -- (rev) EN DECOULE TOUJOURS automatiquement (jamais un reglage libre
        -- ici) pour que la barre se vide en direction de l'icone quel que
        -- soit le cote choisi : icone a DROITE (barre a gauche) -> rev=true
        -- (la barre se retracte vers la droite/l'icone) ; icone a GAUCHE
        -- (barre a droite) -> rev=false (la barre se retracte vers la
        -- gauche/l'icone).
        local iconR = (cfg.iconPos or "RIGHT") == "RIGHT"
        if cfg.hideIcon then
            f.bar = MakeBar(bw, bh, iconR and "RIGHT" or "LEFT", f, iconR and "RIGHT" or "LEFT", 0, 0, iconR)
        elseif iconR then
            f.bar = MakeBar(bw, bh, "RIGHT", icon, "LEFT", -gp, 0, iconR)
        else
            f.bar = MakeBar(bw, bh, "LEFT", icon, "RIGHT", gp, 0, iconR)
        end
    end

    return f
end

-- Detruit et reconstruit tous les widgets, uniquement sur changement structurel (pas sur le tick frequent
-- de PLAYER_TOTEM_UPDATE, cf. ns.RefreshTotemsGrid qui ne fait que montrer/cacher des widgets existants).
local function RebuildTotemWidgets()
    for _, f in pairs(totemWidgets) do
        f:Hide()
        f:SetParent(nil)
    end
    wipe(totemWidgets)

    local cfg = ns.db and ns.db.totems or ns.Defaults.totems
    local _, iw, gp, bw, bh, ih, _, layout, rowW, rowH = GetTotemsDims(cfg)

    -- Preview : cf. BuildTotemsPreviewOrder (vrais sorts-totem coches en
    -- priorite, completes par des icones factices thematiques sauf en mode
    -- "fidele" de la page "Auras a tracker").
    if IsTotemsPreviewActive() then
        for i, sid in ipairs(BuildTotemsPreviewOrder()) do
            local f = BuildTotemWidget(sid, cfg, layout, rowW, rowH, iw, ih, gp, bw, bh)
            local isFake = sid >= PREVIEW_IDS[1]
            if isFake and f.icon then f.icon:SetTexture(PREVIEW_ICONS[i] or PREVIEW_ICONS[1]) end
            totemWidgets[sid] = f
        end
        return
    end

    local order = ns.slotOrderByDest and ns.slotOrderByDest.totems
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not (order and spells) then return end

    for _, spellID in ipairs(order) do
        local info = spells[spellID]
        if info and info.source == "totem" then
            totemWidgets[spellID] = BuildTotemWidget(spellID, cfg, layout, rowW, rowH, iw, ih, gp, bw, bh)
        end
    end
end

-- Repositionne le conteneur (taille/point d'ancrage selon cfg.growth, meme
-- mapping que RepositionFreeBarsNativeGrid) -- PAS de flow Blizzard ici
-- (aucun conteneur "AuraContainer"), le packing des widgets visibles est
-- manuel, cf. RefreshTotemsGridBody ci-dessous.
local function PositionTotemsContainer(cont, cfg)
    local maxBars, _, _, _, _, _, rg, _, rowW, rowH = GetTotemsDims(cfg)
    local growth = cfg.growth or "DOWN"
    local isH = (growth == "LEFT" or growth == "RIGHT")
    if isH then pcall(cont.SetSize, cont, maxBars * (rowW + rg), rowH)
    else pcall(cont.SetSize, cont, rowW, maxBars * (rowH + rg)) end

    cont:ClearAllPoints()
    local x, y = cfg.x or -502, cfg.y or -120
    if growth == "UP" then cont:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then cont:SetPoint("RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then cont:SetPoint("LEFT", UIParent, "CENTER", x, y)
    else cont:SetPoint("TOP", UIParent, "CENTER", x, y) end
end

-- Corps de ns.RefreshTotemsGrid, isole pour l'englober dans un seul pcall avec erreur visible (sinon
-- une erreur silencieuse laisse le conteneur sans aucun widget affiche).
local function RefreshTotemsGridBody()
    local cont = EnsureTotemsContainer()
    local cfg = ns.db and ns.db.totems or ns.Defaults.totems
    local isPreview = IsTotemsPreviewActive()

    local order, spells
    if isPreview then
        order = BuildTotemsPreviewOrder()
        spells = ns.GetSpecSpells and ns.GetSpecSpells()
    else
        order = ns.slotOrderByDest and ns.slotOrderByDest.totems
        spells = ns.GetSpecSpells and ns.GetSpecSpells()
        if not (order and spells) then
            for _, f in pairs(totemWidgets) do f:Hide() end
            return
        end
    end

    local maxBars, iw, _, _, _, _, rg, _, rowW, rowH = GetTotemsDims(cfg)
    local growth = cfg.growth or "DOWN"
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local step = isH and (rowW + rg) or (rowH + rg)

    local visibleIdx = 0
    for _, spellID in ipairs(order) do
        local isFake = isPreview and spellID >= PREVIEW_IDS[1]
        local info = (not isFake) and spells and spells[spellID] or nil
        local f = totemWidgets[spellID]
        local active = isPreview or (activeTotems[spellID] ~= nil)
        if (isPreview or (info and info.source == "totem")) and f then
            if active and visibleIdx < maxBars then
                visibleIdx = visibleIdx + 1
                local offset = (visibleIdx - 1) * step
                f:ClearAllPoints()
                if growth == "UP" then f:SetPoint("BOTTOMLEFT", cont, "BOTTOMLEFT", 0, offset)
                elseif growth == "LEFT" then f:SetPoint("TOPRIGHT", cont, "TOPRIGHT", -offset, 0)
                elseif growth == "RIGHT" then f:SetPoint("TOPLEFT", cont, "TOPLEFT", offset, 0)
                else f:SetPoint("TOPLEFT", cont, "TOPLEFT", 0, -offset) end

                local r, g, b = TotemBarColorRGB(cfg, info)
                if f.bar then pcall(f.bar.SetStatusBarColor, f.bar, r, g, b) end
                if f.barL then pcall(f.barL.SetStatusBarColor, f.barL, r, g, b) end
                if f.barR then pcall(f.barR.SetStatusBarColor, f.barR, r, g, b) end

                -- Preview : pas de vrai durObj disponible (aucun totem
                -- reellement pose) -- EnsurePreviewTicker() prend le relais
                -- (icone+barres animees en boucle, cf. sa doc) pour que
                -- l'utilisateur voie un rendu vivant, pas fige.
                if isPreview then
                    EnsurePreviewTicker()
                else
                    local activeEntry = activeTotems[spellID]
                    if f.cd then pcall(f.cd.SetCooldownFromDurationObject, f.cd, activeEntry.durObj) end
                    local function SetBarDuration(bar)
                        if not bar then return end
                        pcall(bar.SetMinMaxValues, bar, 0, 1)
                        pcall(bar.SetTimerDuration, bar, activeEntry.durObj,
                            Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate,
                            Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime)
                    end
                    SetBarDuration(f.bar); SetBarDuration(f.barL); SetBarDuration(f.barR)
                end

                if f.glowAnchor then ApplyTotemGlow(f.glowAnchor, cfg, info, iw, cfg.iconH or 19) end
                StyleTotemTimerText(f, cfg)
                f:Show()
            else
                f:Hide()
                if f.glowAnchor and ns.HideGlow then pcall(ns.HideGlow, f.glowAnchor) end
            end
        end
    end

    local visible = (cfg.totemsEnabled ~= false) and not (ns.db and ns.db.useNativeCDM)
    if visible and not (ns.IsAuraHidingContext and ns.IsAuraHidingContext()) then
        pcall(function() if ns.UpdateRenderFade then ns.UpdateRenderFade("totems") end end)
    else
        cont:SetAlpha(0)
    end
end

-- Rafraichissement LEGER (montrer/cacher/repositionner/reappliquer
-- duree+couleur+glow sur des widgets DEJA CONSTRUITS) -- appele a chaque
-- evenement totem (frequent), ne recree jamais la structure des widgets.
function ns.RefreshTotemsGrid()
    local ok, err = pcall(RefreshTotemsGridBody)
    if not ok then
        TDBG("|cffff4444RefreshTotemsGrid a echoue -- err=" .. tostring(err) .. "|r")
    end
end

-- Rafraichissement structurel (position/taille du conteneur + reconstruction complete des widgets),
-- appele depuis BuildWhitelist et depuis chaque reglage du panneau Render.lua.
function ns.RepositionTotemsGrid()
    local cont = EnsureTotemsContainer()
    local cfg = ns.db and ns.db.totems or ns.Defaults.totems
    local okPos, errPos = pcall(PositionTotemsContainer, cont, cfg)
    if not okPos then TDBG("|cffff4444RepositionTotemsGrid: positionnement du conteneur a echoue -- err=" .. tostring(errPos) .. "|r") end
    local okBuild, errBuild = pcall(RebuildTotemWidgets)
    if not okBuild then TDBG("|cffff4444RepositionTotemsGrid: reconstruction des widgets a echoue -- err=" .. tostring(errBuild) .. "|r") end
    RescanActiveTotems()
    ns.RefreshTotemsGrid()
end

-- Alias de ns.RepositionTotemsGrid, garde pour coherence de nommage avec les 4 autres destinations.
function ns.EnsureTotemsGrid()
    ns.RepositionTotemsGrid()
end

-- Evenements
local totemEventFrame = CreateFrame("Frame")
totemEventFrame:RegisterEvent("PLAYER_TOTEM_UPDATE")
totemEventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
totemEventFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1=unit, arg2=castGUID, arg3=spellID.
        if arg1 == "player" and arg3 then OnPlayerCastSucceeded(arg3) end
    elseif event == "PLAYER_TOTEM_UPDATE" then
        -- arg1=slot (numero de slot totem qui vient de changer, jamais secret).
        pcall(OnTotemSlotChanged, arg1)
    end
    RescanActiveTotems()
    pcall(ns.RefreshTotemsGrid)
end)

-- /aishdebug totem : dump de l'etat totems (sorts traques, slots, activeTotems, widgets).
function ns.DebugDumpTotems()
    local P = function(s) print("|cff33aaff[Totems]|r " .. tostring(s)) end
    -- Force un rescan live avant de dumper, sinon activeTotems reflete seulement le dernier evenement recu.
    pcall(RescanActiveTotems)
    P("=== Sorts traques (source==\"totem\") ===")
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then
        P("|cffff4444ns.GetSpecSpells() indisponible|r")
    else
        local n = 0
        for spellID, info in pairs(spells) do
            if info.source == "totem" then
                n = n + 1
                local name = SafeSpellName(spellID) or "?"
                P(string.format("  %d (%s) enabled=%s destinations.totems=%s priority=%s",
                    spellID, name, tostring(info.enabled),
                    tostring(info.destinations and info.destinations.totems), tostring(info.priority)))
            end
        end
        if n == 0 then P("  (aucun)") end
    end

    P("=== ns.slotOrderByDest.totems ===")
    local order = ns.slotOrderByDest and ns.slotOrderByDest.totems
    if not order then
        P("|cffff4444nil (whitelist pas encore construite ?)|r")
    else
        P(string.format("  %d sort(s) au total : %s", #order, table.concat(order, ", ")))
    end

    P(string.format("=== File de candidats en attente (fenetre=%.1fs) ===", PENDING_WINDOW))
    if #pendingCastQueue == 0 then
        P("  (vide)")
    else
        for i, c in ipairs(pendingCastQueue) do
            P(string.format("  #%d spellID=%d (%s) age=%.1fs", i, c.spellID, SafeSpellName(c.spellID) or "?", GetTime() - c.time))
        end
    end

    P("=== Scan brut des 4 slots (GetTotemInfo, informatif -- name/icon/duree PAS utilises pour l'identification, cf. en-tete de fichier) ===")
    if not (GetTotemInfo and GetTotemDuration) then
        P("|cffff4444GetTotemInfo/GetTotemDuration indisponibles sur ce client|r")
    else
        for slot = 1, MAX_TOTEM_SLOTS do
            local ok, have, name, startTime = pcall(GetTotemInfo, slot)
            local okD, durObj = pcall(GetTotemDuration, slot)
            P(string.format("  slot %d : pcall_ok=%s name=%s startTime_present=%s durObj_present=%s lie_a_spellID=%s",
                slot, tostring(ok), tostring(name), tostring(startTime ~= nil), tostring(okD and durObj ~= nil), tostring(slotSpellID[slot])))
        end
    end

    P("=== activeTotems (cache interne, rescan le plus recent, cle par SPELLID) ===")
    local n2 = 0
    for spellID, e in pairs(activeTotems) do
        n2 = n2 + 1
        P(string.format("  spellID=%d slot=%s instID=%s", spellID, tostring(e.slot), tostring(e.instID)))
    end
    if n2 == 0 then P("  (aucun totem actif detecte)") end

    P("=== Conteneur / widgets ===")
    if not totemsContainer then
        P("|cffff4444conteneur jamais cree|r")
    else
        local okPt, p1, p2, p3, p4, p5 = pcall(totemsContainer.GetPoint, totemsContainer, 1)
        P(string.format("  conteneur : IsShown=%s Alpha=%.2f Point=%s",
            tostring(totemsContainer:IsShown()), totemsContainer:GetAlpha(),
            okPt and string.format("%s,%s,%s,%s,%s", tostring(p1), tostring(p2), tostring(p3), tostring(p4), tostring(p5)) or "?"))
    end
    local nw = 0
    for spellID, w in pairs(totemWidgets) do
        nw = nw + 1
        local okPt, p1, p2, p3, p4, p5 = pcall(w.GetPoint, w, 1)
        P(string.format("  widget spellID=%d : IsShown=%s Point=%s",
            spellID, tostring(w:IsShown()),
            okPt and string.format("%s,%s,%s,%s,%s", tostring(p1), tostring(p2), tostring(p3), tostring(p4), tostring(p5)) or "AUCUN"))
    end
    if nw == 0 then P("  (aucun widget cree)") end
    P("=== fin dump ===")
end

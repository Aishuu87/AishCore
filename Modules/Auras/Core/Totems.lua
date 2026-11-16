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

-- Pixel perfect, comme Free Bars (Features/Auras/Buffs.lua) : tailles et ancrages alignes sur la grille
-- pixel, sinon une barre de 2-4 px s'affiche plus ou moins epaisse selon sa position a l'ecran.
local function PSize(r, w, h)
    if PixelUtil and PixelUtil.SetSize then PixelUtil.SetSize(r, w, h) else r:SetSize(w, h) end
end
local function PPoint(r, point, rel, relPoint, x, y, minX, minY)
    if PixelUtil and PixelUtil.SetPoint then PixelUtil.SetPoint(r, point, rel, relPoint, x, y, minX, minY)
    else r:SetPoint(point, rel, relPoint, x, y) end
end

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
local _placedAtBySlot = {} -- GetTime() de la pose (delai de grace de la portee, cf. TotemInRange)
local UpdateTotemsRange -- defini plus bas (desaturation hors de portee)
local LearnTotemBuff    -- idem (apprentissage du buff pose par le totem)
local RANGE_GRACE = 2.5

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
                activeTotems[spellID] = { durObj = durObj, slot = slot, instID = -_totemInstCounter, placedAt = _placedAtBySlot[slot] }
            else
                -- Plus de duree lisible : le totem est retombe, on libere le lien pour ce slot.
                slotSpellID[slot] = nil
                _lastDurObjRefBySlot[slot] = nil
                _placedAtBySlot[slot] = nil
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
    local defaults = ns.NewSpellEntry()
    defaults.name = name or SafeSpellName(spellID) or tostring(spellID)
    ns.ApplyAutoColor(defaults, AishUIAuraDB and AishUIAuraDB.activeProfile, spellID)
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
-- Poses pas encore liees : l'ordre UNIT_SPELLCAST_SUCCEEDED / PLAYER_TOTEM_UPDATE n'est pas garanti.
-- Pose recue avant le cast -> file vide, le totem restait invisible. Elle attend ici le cast qui suit.
local pendingPoses = {} -- [slot] = { name = nom lisible ou nil, time = ... }

local function IsSecret(v) return issecretvalue and issecretvalue(v) end

-- spellID de cast change (patch, talent qui remplace le sort) : le nouvel ID etait enregistre comme un
-- sort neuf, non coche -> totem invisible. On le ramene a l'entree totem cochee de meme nom.
local function ResolveTotemID(spellID, spells)
    local info = spells[spellID]
    if info and info.source == "totem" and info.destinations and info.destinations.totems then return spellID end
    local name = SafeSpellName(spellID)
    if not name then return spellID end
    for sid, si in pairs(spells) do
        if sid ~= spellID and si.source == "totem" and si.destinations and si.destinations.totems
           and SafeSpellName(sid) == name then
            return sid
        end
    end
    return spellID
end

-- Index dans pendingCastQueue du candidat correspondant a la pose (nil si aucun). Nom lisible : le totem
-- porte le nom du sort, parfois suivi d'un rang ; sans correspondance, aucun lien -- sinon un Eclair lance
-- juste avant le totem etait classe "totem". Nom secret (Retail, en combat) : rien ne distingue le totem
-- d'un Choc lance juste avant, on ne lie qu'un sort DEJA classe totem.
local function FindCandidate(name, spells)
    if name then
        local lname = name:lower()
        for i, c in ipairs(pendingCastQueue) do
            local sn = SafeSpellName(c.spellID)
            local lsn = sn and sn:lower()
            if lsn and lsn ~= "" and (lname:find(lsn, 1, true) or lsn:find(lname, 1, true)) then
                return i
            end
        end
    else
        for i, c in ipairs(pendingCastQueue) do
            local known = spells[ResolveTotemID(c.spellID, spells)]
            if known and known.source == "totem" then return i end
        end
    end
end

local function PurgeStale(now)
    while pendingCastQueue[1] and (now - pendingCastQueue[1].time) > PENDING_WINDOW do
        table.remove(pendingCastQueue, 1)
    end
    for slot, p in pairs(pendingPoses) do
        if (now - p.time) > PENDING_WINDOW then pendingPoses[slot] = nil end
    end
end

local function BindSlot(slot, spellID, spells)
    spellID = ResolveTotemID(spellID, spells)
    pendingPoses[slot] = nil
    slotSpellID[slot] = spellID
    -- Date de pose (delai de grace de la portee) : ici seulement, sur une pose confirmee. GetTotemDuration
    -- renvoie un objet neuf a chaque appel, le dater au rescan relancait la grace a chaque evenement.
    _placedAtBySlot[slot] = GetTime()
    C_Timer.After(RANGE_GRACE + 0.1, function() if UpdateTotemsRange then UpdateTotemsRange() end end)
    if LearnTotemBuff then pcall(LearnTotemBuff, spellID) end
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

-- Lie les poses en attente aux casts presents dans la file (pose la plus ancienne d'abord).
local function MatchPendingPoses(spells)
    local slots = {}
    for slot in pairs(pendingPoses) do slots[#slots + 1] = slot end
    table.sort(slots, function(a, b) return pendingPoses[a].time < pendingPoses[b].time end)
    for _, slot in ipairs(slots) do
        local pick = FindCandidate(pendingPoses[slot].name, spells)
        if pick then BindSlot(slot, table.remove(pendingCastQueue, pick).spellID, spells) end
    end
end

-- Appelee a chaque cast reussi du joueur, filtre tot les sorts deja classes debuff/equipment.
local function OnPlayerCastSucceeded(spellID)
    if not spellID then return end
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    local existing = spells[spellID]
    if existing and (existing.source == "debuff" or existing.source == "equipment") then return end
    pendingCastQueue[#pendingCastQueue + 1] = { spellID = spellID, time = GetTime() }
    if #pendingCastQueue > 8 then table.remove(pendingCastQueue, 1) end
    PurgeStale(GetTime())
    if next(pendingPoses) then MatchPendingPoses(spells) end
end

-- Appelee sur PLAYER_TOTEM_UPDATE(slot), qui se declenche pour la pose ET le retrait/expiration ;
-- un test de presence pure (startTime truthy) filtre les retraits pour ne lier que les poses reelles.
local function OnTotemSlotChanged(slot)
    if not (slot and GetTotemInfo) then return end
    local okInfo, have, name, startTime = pcall(GetTotemInfo, slot)
    if not okInfo then return end
    -- Retrait/expiration, pas une pose : rien a lier. Slot vide = haveTotem false ET startTime 0 --
    -- or 0 est VRAI en Lua : tester startTime seul liait le dernier sort lance (Attaque, Boisson,
    -- potion...) a chaque disparition de totem.
    if have ~= nil and not IsSecret(have) and not have then pendingPoses[slot] = nil; return end
    if not startTime then pendingPoses[slot] = nil; return end
    if not IsSecret(startTime) and type(startTime) == "number" and startTime <= 0 then pendingPoses[slot] = nil; return end

    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end

    local now = GetTime()
    PurgeStale(now)
    local readable = type(name) == "string" and not IsSecret(name) and name ~= "" and name or nil
    local pick = FindCandidate(readable, spells)
    if pick then
        BindSlot(slot, table.remove(pendingCastQueue, pick).spellID, spells)
    else
        -- Cast pas encore recu : la pose attend (cf. pendingPoses).
        pendingPoses[slot] = { name = readable, time = now }
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
    -- pcall n'empeche pas ADDON_ACTION_BLOCKED : ne pas appeler du tout en combat
    local ok = not InCombatLockdown() and pcall(f.SetPropagateMouseClicks, f, allow)
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

-- Hors de portee : un totem qui pose un buff sur le joueur (Data/TotemBuffs.lua) est hors de portee quand
-- ce buff manque. Sans buff connu, ou auras illisibles (BG/arene), le totem reste en couleur.
-- Delai de grace apres la pose : le premier pulse du totem n'a pas encore pose le buff.
local GetPlayerAuraBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

local GetAuraDataBySpellName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex

-- APPRENTISSAGE : la table generee (Data/TotemBuffs.lua) ne connait pas tous les buffs. Ex. Forever : Windfury /
-- Grounding Totem posent un buff SANS spellID (rien dans les donnees, introuvable par ID). A chaque pose hors combat,
-- les buffs du joueur sont compares avant / apres : un buff apparu qui ressemble au totem (meme icone, ou nom contenu
-- l'un dans l'autre) lui est associe par son NOM (et son ID s'il en a un), memorise pour le compte :
-- AishUIAuraDB.totemBuffsLearned[totem] = { names = { [nom] = true }, ids = { [id] = true } }.
local function LearnedDB()
    if not AishUIAuraDB then return nil end
    AishUIAuraDB.totemBuffsLearned = AishUIAuraDB.totemBuffsLearned or {}
    return AishUIAuraDB.totemBuffsLearned
end

-- Buffs suivis pour un totem : { ids = {...}, names = {...} } (table generee + appris), memorise
local _buffsCache = {}
local function BuffsFor(spellID)
    local c = _buffsCache[spellID]
    if c ~= nil then return c or nil end
    local ids, names, seenId, seenName = {}, {}, {}, {}
    local function addId(id) if id and not seenId[id] then seenId[id] = true; ids[#ids + 1] = id end end
    local function addName(n) if type(n) == "string" and n ~= "" and not seenName[n] then seenName[n] = true; names[#names + 1] = n end end
    local db = LearnedDB()
    local learned = db and db[spellID]
    if type(learned) == "table" then
        for id in pairs(learned.ids or {}) do addId(id) end
        for n in pairs(learned.names or {}) do addName(n) end
    end
    local static = _addon.TotemBuffs and _addon.TotemBuffs[spellID]
    if static then
        for _, id in ipairs(static) do addId(id) end
        addName(SafeSpellName(static[1]))
    end
    local res = (#ids > 0 or #names > 0) and { ids = ids, names = names } or false
    _buffsCache[spellID] = res
    return res or nil
end

-- Buffs du joueur : liste de { sid, icon, name }, chaque champ secret remplace par nil (un buff sans spellID
-- peut avoir un ID secret meme hors combat). nil si AUCUN nom n'est lisible (combat).
local function SnapshotBuffs()
    if not GetAuraDataByIndex then return nil end
    local list, anyName = {}, false
    for i = 1, 60 do
        local ok, a = pcall(GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a or IsSecret(a) then break end
        local sid, icon, name = a.spellId, a.icon, a.name
        if IsSecret(sid) or sid == 0 then sid = nil end
        if IsSecret(icon) then icon = nil end
        if IsSecret(name) then name = nil else anyName = true end
        list[#list + 1] = { sid = sid, icon = icon, name = name }
    end
    if #list > 0 and not anyName then return nil end
    return list
end

-- /aishdebug totembuffs : buffs du joueur tels que lus ici (champs secrets signales)
function ns.DebugTotemPlayerBuffs()
    local P = function(s) print("|cff33aaff[TotemBuffs]|r " .. tostring(s)) end
    P(string.format("combat=%s secretAuras=%s", tostring(InCombatLockdown()),
        tostring(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())))
    for i = 1, 60 do
        local ok, a = pcall(GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then P("#" .. i .. " erreur : " .. tostring(a)); break end
        if not a then break end
        if IsSecret(a) then P("#" .. i .. " aura secrete"); break end
        local function v(x) if IsSecret(x) then return "SECRET" end return tostring(x) end
        P(string.format("#%d nom=%s id=%s icone=%s source=%s", i, v(a.name), v(a.spellId), v(a.icon), v(a.sourceUnit)))
    end
    local db = AishUIAuraDB and AishUIAuraDB.totemBuffsLearned
    P("appris :")
    for tid, e in pairs(db or {}) do
        local names = {}
        for n in pairs(type(e) == "table" and e.names or {}) do names[#names + 1] = n end
        P(string.format("  %s (%d) -> %s", SafeSpellName(tid) or "?", tid, table.concat(names, ", ")))
    end
end

local function LooksLikeTotem(totemID, buff)
    local okT, tex = pcall(C_Spell.GetSpellTexture, totemID)
    if okT and tex and buff.icon and tex == buff.icon then return true end
    local tn = SafeSpellName(totemID)
    if not (tn and type(buff.name) == "string" and buff.name ~= "") then return false end
    local a, b = tn:lower(), buff.name:lower()
    return a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

LearnTotemBuff = function(totemID)
    if InCombatLockdown() then return end
    -- Pas de comparaison avant / apres : le buff peut etre pose des l'apparition du totem, ou deja la
    -- (totem repose a portee de l'ancien). La ressemblance (icone / nom) suffit a l'associer.
    local function Check()
        local after = SnapshotBuffs()
        local db = after and LearnedDB()
        if not db then return end
        for _, buff in ipairs(after) do
            local n = buff.name
            if type(n) == "string" and n ~= "" and LooksLikeTotem(totemID, buff) then
                local e = db[totemID]
                if type(e) ~= "table" then e = {}; db[totemID] = e end
                e.names = e.names or {}; e.ids = e.ids or {}
                if not e.names[n] or (buff.sid and not e.ids[buff.sid]) then
                    e.names[n] = true
                    if buff.sid then e.ids[buff.sid] = true end
                    _buffsCache[totemID] = nil
                    if ns._totemRangeTrace then
                        print(string.format("|cff33aaff[TotemRange]|r appris : %s -> buff \"%s\" (ID %s)",
                            SafeSpellName(totemID) or tostring(totemID), n, tostring(buff.sid)))
                    end
                end
            end
        end
        if UpdateTotemsRange then UpdateTotemsRange() end
    end
    C_Timer.After(1.2, Check)
    C_Timer.After(2.4, Check)
end

-- Presence du buff, trois recherches : par ID (GetPlayerAuraBySpellID, fiable en combat), par nom de sort
-- (GetAuraDataBySpellName), puis parcours des buffs par nom (seule voie pour un buff sans spellID, impossible
-- quand les noms sont secrets en combat). true / false, ou nil = illisible (l'appelant garde l'etat precedent).
local function TotemBuffPresent(buffs)
    local idReadable = false
    for _, id in ipairs(buffs.ids) do
        local ok, aura = pcall(GetPlayerAuraBySpellID, id)
        if ok and not IsSecret(aura) then
            idReadable = true
            if aura then return true end
        end
    end
    if GetAuraDataBySpellName then
        for _, n in ipairs(buffs.names) do
            local ok, aura = pcall(GetAuraDataBySpellName, "player", n, "HELPFUL")
            if ok and aura and not IsSecret(aura) then return true end
        end
    end
    local list = SnapshotBuffs()
    if not list then
        -- Noms secrets (combat) : seule la recherche par ID tranche, et seulement si le buff a un ID connu
        -- (un buff appris sans spellID n'est alors pas lisible)
        if idReadable and #buffs.ids > 0 then return false end
        return nil
    end
    local blind = false   -- un buff au nom illisible pourrait etre le bon
    for _, b in ipairs(list) do
        if not b.name then blind = true end
        for _, n in ipairs(buffs.names) do
            if b.name == n then return true end
        end
        if b.sid then
            for _, id in ipairs(buffs.ids) do if b.sid == id then return true end end
        end
    end
    if blind and not (idReadable and #buffs.ids > 0) then return nil end
    return false
end

-- Champ de bataille / arene : auras du joueur secretes, les recherches ci-dessus ne repondent plus
local function SelfAurasBlind()
    local inInst, instType = IsInInstance()
    if not (inInst and (instType == "pvp" or instType == "arena")) then return false end
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false
end

-- Le totem reapplique son buff a chaque pulse (~2 s) : en combat le buff parait absent un court instant
-- a chaque pulse. Hors de portee seulement apres OUT_OF_RANGE_DELAY s d'absence continue.
local OUT_OF_RANGE_DELAY = 3
local _lastSeenBySlot = {}
local _recheckPending = false

local function TotemInRange(spellID, entry, cfg)
    if cfg and cfg.desatOutOfRange == false then return true end
    local buffs = BuffsFor(spellID)
    if not buffs then return true end
    local now = GetTime()
    if entry and entry.placedAt and (now - entry.placedAt) < RANGE_GRACE then return true end
    if SelfAurasBlind() then return true end
    -- Jamais de test en combat (buffs illisibles ou peu fiables) : couleur
    if InCombatLockdown() or UnitAffectingCombat("player") then return true end
    local slot = entry and entry.slot
    local present = TotemBuffPresent(buffs)
    if present == nil then return true end   -- illisible : couleur
    local result
    if present then
        if slot then _lastSeenBySlot[slot] = now end
        result = true
    else
        local seen = slot and _lastSeenBySlot[slot]
        if seen and seen >= ((entry and entry.placedAt) or 0) and (now - seen) < OUT_OF_RANGE_DELAY then
            -- Absence encore trop courte : reevaluer a l'echeance (aucun UNIT_AURA ne viendra forcement)
            if not _recheckPending then
                _recheckPending = true
                C_Timer.After(OUT_OF_RANGE_DELAY - (now - seen) + 0.05, function()
                    _recheckPending = false
                    if UpdateTotemsRange then UpdateTotemsRange() end
                end)
            end
            result = true
        else
            result = false
        end
    end
    return result
end

-- /aishdebug totemrange : trace de chaque bascule de portee, avec le detail des recherches de buff
local function TraceRange(spellID, inRange)
    if not ns._totemRangeTrace then return end
    local buffs = BuffsFor(spellID) or { ids = {}, names = {} }
    local byId = {}
    for _, id in ipairs(buffs.ids) do
        local ok, a = pcall(GetPlayerAuraBySpellID, id)
        if not ok then byId[#byId + 1] = id .. "=err"
        elseif IsSecret(a) then byId[#byId + 1] = id .. "=secret"
        elseif a then byId[#byId + 1] = id .. "=OUI" end
    end
    local list = SnapshotBuffs()
    local byScan = list and "non" or "illisible"
    if list then
        for _, b in ipairs(list) do
            for _, n in ipairs(buffs.names) do if b.name == n then byScan = "OUI" end end
        end
    end
    print(string.format("|cff33aaff[TotemRange]|r %.1f %s -> %s | combat=%s secretAuras=%s | parID={%s} noms={%s} parcours=%s",
        GetTime(), SafeSpellName(spellID) or tostring(spellID), inRange and "|cff00ff00couleur|r" or "|cffff4444gris|r",
        tostring(InCombatLockdown()),
        tostring(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()),
        table.concat(byId, ","), table.concat(buffs.names, ","), byScan))
end

local function ApplyTotemRange(f, inRange)
    if f._inRange == inRange and f._rgbApplied == f._rgb then return end
    f._inRange, f._rgbApplied = inRange, f._rgb
    if f.icon then f.icon:SetDesaturated(not inRange) end
    local c = f._rgb or { 1, 1, 1 }
    local r, g, b = c[1], c[2], c[3]
    if not inRange then
        local l = (r * 0.3 + g * 0.59 + b * 0.11) * 0.6
        r, g, b = l, l, l
    end
    if f.bar then pcall(f.bar.SetStatusBarColor, f.bar, r, g, b) end
    if f.barL then pcall(f.barL.SetStatusBarColor, f.barL, r, g, b) end
    if f.barR then pcall(f.barR.SetStatusBarColor, f.barR, r, g, b) end
end

-- Glow par sort, type et taille eventuellement remplaces par la section "Glow" du mode (cf. ns.ModeGlow).
local function ApplyTotemGlow(glowAnchor, cfg, info, iw, ih)
    if ns.HideGlow then pcall(ns.HideGlow, glowAnchor) end
    if cfg.glowEnabled == false then return end
    if not (info and info.glowIdx and info.glowIdx > 1) then return end
    local idx, scale, color, alpha = ns.ModeGlow(cfg, info.glowIdx, info.glowScale, info.glowColor or info.color, info.glowAlpha, info._glowCustom == true)
    if ns.ShowGlow then pcall(ns.ShowGlow, glowAnchor, idx, color, alpha, scale, iw, ih) end
end

-- Construit un widget COMPLET (icone + barre(s)) pour spellID selon la
-- disposition courante -- meme geometrie que initializeFrame de
-- EnsureFreeBarsNativeGrid (side_large "Vanguard" / side_compact "Sparte" /
-- side_banner "Banner"), mais en frames manuelles (pas d'AuraContainer).
local function BuildTotemWidget(spellID, cfg, layout, rowW, rowH, iw, ih, gp, bw, bh)
    local cont = EnsureTotemsContainer()
    local f = CreateFrame("Frame", nil, cont)
    PSize(f, rowW, rowH)
    f:Hide()

    local icon
    if not cfg.hideIcon then
        icon = f:CreateTexture(nil, "ARTWORK")
        PSize(icon, iw, ih)
        if layout == "side_banner" then
            PPoint(icon, "TOP", f, "TOP", 0, 0)
        elseif layout == "side_compact" then
            PPoint(icon, "CENTER", f, "CENTER", 0, 0)
        else
            if (cfg.iconPos or "RIGHT") == "RIGHT" then
                PPoint(icon, "RIGHT", f, "RIGHT", 0, 0)
            else
                PPoint(icon, "LEFT", f, "LEFT", 0, 0)
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
        -- Bordure d'au moins 1 pixel physique quelle que soit l'echelle de l'UI.
        PPoint(border, "TOPLEFT", icon, "TOPLEFT", -1, 1, 1, 1)
        PPoint(border, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1, 1, 1)
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
        PSize(bar, w, h)
        PPoint(bar, point, relTo, relPoint, ox, oy)
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
    if isH then pcall(PSize, cont, maxBars * (rowW + rg), rowH)
    else pcall(PSize, cont, rowW, maxBars * (rowH + rg)) end

    cont:ClearAllPoints()
    local x, y = cfg.x or -502, cfg.y or -120
    if growth == "UP" then PPoint(cont, "BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then PPoint(cont, "RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then PPoint(cont, "LEFT", UIParent, "CENTER", x, y)
    else PPoint(cont, "TOP", UIParent, "CENTER", x, y) end
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
                if growth == "UP" then PPoint(f, "BOTTOMLEFT", cont, "BOTTOMLEFT", 0, offset)
                elseif growth == "LEFT" then PPoint(f, "TOPRIGHT", cont, "TOPRIGHT", -offset, 0)
                elseif growth == "RIGHT" then PPoint(f, "TOPLEFT", cont, "TOPLEFT", offset, 0)
                else PPoint(f, "TOPLEFT", cont, "TOPLEFT", 0, -offset) end

                f._rgb = { TotemBarColorRGB(cfg, info) }
                local inRange = isPreview or TotemInRange(spellID, activeTotems[spellID], cfg)
                if not isPreview and f._inRange ~= inRange then TraceRange(spellID, inRange) end
                ApplyTotemRange(f, inRange)

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
        -- Conteneur masque par Hide() ailleurs (changement de profil, cf. Profiles.lua / Init.lua) : seul
        -- ce rendu manuel ne le reaffichait jamais, les totems restaient invisibles jusqu'au /reload.
        if not cont:IsShown() then cont:Show() end
        pcall(function() if ns.UpdateRenderFade then ns.UpdateRenderFade("totems") end end)
    else
        cont:SetAlpha(0)
    end
end

-- Reevalue seulement la portee des totems affiches (UNIT_AURA du joueur, fin du delai de grace).
UpdateTotemsRange = function()
    if IsTotemsPreviewActive() then return end
    local cfg = ns.db and ns.db.totems or ns.Defaults.totems
    for spellID, entry in pairs(activeTotems) do
        local f = totemWidgets[spellID]
        if f and f:IsShown() then
            local inRange = TotemInRange(spellID, entry, cfg)
            if f._inRange ~= inRange then TraceRange(spellID, inRange) end
            ApplyTotemRange(f, inRange)
        end
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

-- Fin d'un contexte qui masque les auras (taxi, vehicule, vol dynamique) ou ecran de chargement : le
-- conteneur passe a alpha 0 dans ce contexte, il n'etait reevalue qu'au prochain evenement totem.
local function RefreshAfterContext()
    if not totemsContainer then return end
    RescanActiveTotems()
    pcall(ns.RefreshTotemsGrid)
end
local totemCtxFrame = CreateFrame("Frame")
totemCtxFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
totemCtxFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
totemCtxFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
totemCtxFrame:SetScript("OnEvent", function()
    RefreshAfterContext()
    C_Timer.After(1, RefreshAfterContext)   -- UnitOnTaxi pas encore a jour au moment de l'evenement
end)
if _addon.CallbackRegistry then _addon.CallbackRegistry:Register("SKYRIDING_CHANGED", RefreshAfterContext) end

-- Buffs du joueur : portee des totems (desaturation hors de portee)
local totemRangeFrame = CreateFrame("Frame")
totemRangeFrame:RegisterUnitEvent("UNIT_AURA", "player")
totemRangeFrame:RegisterEvent("PLAYER_REGEN_DISABLED")   -- entree en combat : totems rendus en couleur
totemRangeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")    -- sortie : le test reprend
totemRangeFrame:SetScript("OnEvent", function()
    if next(activeTotems) then pcall(UpdateTotemsRange) end
end)

-- NETTOYAGE UNIQUE : l'ancienne liaison (slot vide pris pour une pose, candidat le plus ancien) a
-- classe "totem" des sorts et objets sans rapport (Attaque, Boisson, Eclair, potions...). On retire du
-- registre compte et de tous les profils les entrees "totem" cochees nulle part : les vrais totems
-- reviennent seuls a la prochaine pose, avec la liaison corrigee. V2 : repasse apres le correctif du nom
-- secret (combat), qui liait encore le premier sort lance (Choc, Vague de soins...).
local function PurgeBogusTotems()
    local raw = AishUIAuraDB
    if type(raw) ~= "table" or raw.totemPurgeV2 or type(raw.discovery) ~= "table" then return end
    raw.totemPurgeV2 = true
    local profiles = type(raw.profiles) == "table" and raw.profiles or {}
    local removed = 0
    for specKey, reg in pairs(raw.discovery) do
        if type(reg) == "table" then
            for sid, d in pairs(reg) do
                if type(d) == "table" and d.source == "totem" then
                    local keep = false
                    for _, p in pairs(profiles) do
                        local list = type(p) == "table" and type(p.discoveredSpells) == "table" and p.discoveredSpells[specKey]
                        local info = type(list) == "table" and list[sid]
                        if type(info) == "table" and info.enabled then keep = true; break end
                    end
                    if not keep then
                        reg[sid] = nil
                        for _, p in pairs(profiles) do
                            local list = type(p) == "table" and type(p.discoveredSpells) == "table" and p.discoveredSpells[specKey]
                            if type(list) == "table" then list[sid] = nil end
                        end
                        removed = removed + 1
                    end
                end
            end
        end
    end
    if removed > 0 and ns._whitelistBuilt and ns.BuildWhitelist then pcall(ns.BuildWhitelist) end
end

local purgeFrame = CreateFrame("Frame")
purgeFrame:RegisterEvent("PLAYER_LOGIN")
purgeFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    pcall(PurgeBogusTotems)
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
        local buffs = BuffsFor(spellID)
        if buffs then
            local f = totemWidgets[spellID]
            P(string.format("    portee : ids={%s} noms={%s} present=%s inRange=%s widget=%s shown=%s desat=%s combat=%s",
                table.concat(buffs.ids, ","), table.concat(buffs.names, ","), tostring(TotemBuffPresent(buffs)),
                tostring(TotemInRange(spellID, e, ns.db and ns.db.totems)), tostring(f ~= nil),
                tostring(f and f:IsShown()), tostring(f and f.icon and f.icon:IsDesaturated()),
                tostring(InCombatLockdown())))
        else
            P("    portee : aucun buff connu pour ce totem (jamais grise)")
        end
    end
    if n2 == 0 then P("  (aucun totem actif detecte)") end

    P(string.format("=== Contexte : masquage=%s taxi=%s vol=%s apercu=%s/%s UIParent=%s/%.2f useNativeCDM=%s totemsEnabled=%s ===",
        tostring(ns.IsAuraHidingContext and ns.IsAuraHidingContext()), tostring(UnitOnTaxi("player")),
        tostring(_addon.skyridingActive), tostring(ns._previewBars), tostring(ns._previewMode),
        tostring(UIParent:IsShown()), UIParent:GetAlpha(), tostring(ns.db and ns.db.useNativeCDM),
        tostring(ns.db and ns.db.totems and ns.db.totems.totemsEnabled)))
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

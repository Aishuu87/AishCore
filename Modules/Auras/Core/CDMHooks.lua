-- AishUIAura/Core/CDMHooks.lua
-- Hooks du Cooldown Manager de Blizzard : parse les spell IDs, hooke les frames
-- BuffIcon/BuffBar, applique le masking (SetAlpha(0) uniquement — JAMAIS
-- SetScale, ce qui tue le CDM au 2ème combat)
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local tinsert = table.insert
local pcall, hooksecurefunc = pcall, hooksecurefunc

-- API : C_Spell.GetSpellName en Midnight 12.0+, GetSpellInfo en fallback
-- (le bug v265 etait que cette variable n'etait pas declaree localement,
-- donc GetSpellName etait nil et le name retombait toujours sur tostring(spellID))
local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo

------------------------------------------------------------------------
-- HOOKS CDM (pattern motor, namespace ns, masking : SetAlpha(0) UNIQUEMENT)
------------------------------------------------------------------------
local cdmData = { player = {}, target = {} }
ns.cdmData = cdmData
local cdmHooked = false
local hookedFrames, maskableFrames, frameSource, buffFrameAlwaysMask = {}, {}, {}, {}

-- Données CD event-driven : alimentées par les hooks SetCooldown/Clear sur les
-- Cooldown-enfants des frames CDM. Plus fiable que le polling IsShown() de
-- ScanCooldownViewer (PriorityBar) : mis à jour exactement quand Blizzard
-- démarre ou arrête un CD, sans lag de polling et sans faux-négatifs dus aux
-- animations de transition.
-- Structure : cdmCDData[spellID] = { cdStart, cdDuration, onCD }
-- cdStart/cdDuration : valeurs brutes passées à SetCooldown (secondes propres)
-- onCD : true dès SetCooldown, false dès Clear()
local cdmCDData = {}
ns.cdmCDData = cdmCDData

-- GetCDMFrameSpellID doit être défini AVANT HookCDMCooldownChild : c'est une
-- variable locale, donc doit être en scope au moment où HookCDMCooldownChild
-- est compilé (sinon Lua la traite comme un global = nil au moment de l'appel).
local function GetCDMFrameSpellID(frame)
    if not frame.cooldownInfo or not frame.cooldownID then return nil end
    local info = frame.cooldownInfo
    local ret = info.spellID
    if info.linkedSpellIDs and info.linkedSpellIDs[1] then ret = info.linkedSpellIDs[1] end
    return ret
end

-- Variante scan-only : priorité complète (overrideTooltipSpellID > linkedSpellID >
-- linkedSpellIDs[1] > overrideSpellID > spellID). Pas de garde cooldownID car
-- certains viewers initialisent cooldownInfo avant cooldownID.
local function GetScanSpellID(frame)
    if not frame then return nil end
    local info = frame.cooldownInfo
    if not info then return nil end
    local lids = info.linkedSpellIDs
    local sid = (type(lids) == "table" and lids[1])
             or info.overrideTooltipSpellID or info.linkedSpellID
             or info.overrideSpellID or info.spellID
    if type(sid) ~= "number" or sid <= 0 then return nil end
    return sid
end

local hookedCooldownChildren  = {}
-- [cdFrame] = { spellID, cdStart, cdDuration } : tracking par frame pour le
-- matching dans Clear(). Permet de distinguer la frame GCD (duration≤1.5)
-- de la frame du vrai CD (duration>1.5) qui ont le même spellID.
local hookedCooldownFrameData = {}

-- Hooke le frame Cooldown enfant d'une frame CDM pour capturer les données CD
-- de façon event-driven. Appelé depuis HookCDMFrame si frame.Cooldown existe.
--
-- Trois garde-fous par rapport à la version naïve :
--  1) Filtre GCD : seuls les CDs > 1.5s sont stockés dans cdmCDData.
--     Le GCD (≤1.5s) est tracké par frame mais n'écrase jamais un vrai CD.
--  2) Tracking par frame : hookedCooldownFrameData[cdFrame] mémorise les
--     paramètres du dernier SetCooldown de CETTE frame.
--  3) Clear avec matching : Clear() ne vide cdmCDData[spellID].onCD que si
--     le version counter correspond — évite qu'un Clear() de la frame GCD
--     vide l'entrée du vrai CD stockée pour le même spellID.
-- start/duration passés à SetCooldown sont des "secret numbers" TWW : toute
-- comparaison (>, ==, <) depuis du code tainté échoue, même après tonumber().
-- Solution : utiliser parentFrame.isOnGCD (booléen, lisible depuis du code
-- tainté) pour filtrer le GCD, et un compteur de version (entier Lua pur)
-- pour le matching dans Clear() — aucune comparaison de secret numbers.
local cdFrameVersion = {}  -- [cdFrame] = dernier numéro de version SetCooldown

-- Abonnements "clone swipe" : quand le CDM appelle SetCooldown/Clear sur une
-- frame pour le spellID X, on passe-forward les arguments (secret numbers inclus)
-- directement à chaque frame abonnée, sans jamais les lire ni les comparer.
-- Structure : cdmCooldownSubscribers[spellID][key] = { cooldown=frame, slot=frame }
-- • key     : table servant d'identifiant unique (généralement la slot-frame PB).
-- • cooldown: le Cooldown widget cible (slot.cooldown du PriorityBar).
-- • slot    : la slot-frame PriorityBar, pour mettre à jour _onCooldown/_swipeSpellName.
local cdmCooldownSubscribers = {}

-- S'abonner au clone du CDM swipe pour un spellID.
-- key          : identifiant unique de l'abonné (ex. slot-frame PriorityBar).
-- cdFrame      : Cooldown widget de l'icône PriorityBar à piloter.
-- slotRef      : slot-frame PriorityBar (pour _onCooldown/_swipeSpellName).
-- forDisplayID : spellID affiché dans le slot au moment de l'abonnement.
--                Guard : on ne forward que si slot.currentSpellID == forDisplayID
--                (évite qu'un sort caché du même slot déclenche le swipe du sort affiché).
function ns.SubscribeCDMCooldown(spellID, key, cdFrame, slotRef, forDisplayID)
    if not spellID or not key or not cdFrame then return end
    if not cdmCooldownSubscribers[spellID] then
        cdmCooldownSubscribers[spellID] = {}
    end
    cdmCooldownSubscribers[spellID][key] = { cooldown = cdFrame, slot = slotRef, forDisplayID = forDisplayID }
end

-- Se désabonner.
function ns.UnsubscribeCDMCooldown(spellID, key)
    if not spellID or not key then return end
    local subs = cdmCooldownSubscribers[spellID]
    if subs then
        subs[key] = nil
        -- Nettoyer la table si vide pour éviter les fuites mémoire.
        if not next(subs) then cdmCooldownSubscribers[spellID] = nil end
    end
end

local function HookCDMCooldownChild(cdFrame, parentFrame)
    if not cdFrame or hookedCooldownChildren[cdFrame] then return end
    hookedCooldownChildren[cdFrame] = true
    pcall(function()
        hooksecurefunc(cdFrame, "SetCooldown", function(self, start, duration)
            local spellID = GetCDMFrameSpellID(parentFrame)
            if not spellID then return end
            -- Incrémenter le version counter (entier Lua pur, safe à comparer).
            local ver = (cdFrameVersion[cdFrame] or 0) + 1
            cdFrameVersion[cdFrame] = ver
            -- Tracker par frame pour le matching dans Clear().
            hookedCooldownFrameData[cdFrame] = { spellID=spellID, version=ver }
            -- Filtrer le GCD : wasSetFromCooldown + not isOnGCD.
            -- isOnGCD est le booléen natif CDM prévu pour ce filtre (lisible en tainté).
            -- wasSetFromCooldown seul était insuffisant (vrai sur certaines frames GCD).
            if parentFrame.wasSetFromCooldown and not parentFrame.isOnGCD then
                cdmCDData[spellID] = { version=ver, onCD=true }
                    local subs = cdmCooldownSubscribers[spellID]
                    if subs then
                        -- Filtrer les GCDs : ne forwarder QUE si on peut confirmer
                        -- duration > 1.5s (vrai CD). Si la comparaison échoue (secret
                        -- number en TWW, pcall=false) ou si duration ≤ 1.5s → ne pas
                        -- forwarder. UpdateSlotExtras prend le relais via polling
                        -- (SetCooldownFromDurationObject, ~150ms de délai, imperceptible
                        -- sur des CDs de 8s+). Évite les swipes GCD pour les sorts à
                        -- charges dont les frames ont parfois isOnGCD=false en TWW.
                        local okDur, isLong = pcall(function() return duration > 1.5 end)
                        local forwardSwipe  = okDur and isLong
                        for _, sub in pairs(subs) do
                            if sub.cooldown and sub.slot
                               and sub.slot.currentSpellID == sub.forDisplayID
                               and forwardSwipe then
                                pcall(sub.cooldown.Show, sub.cooldown)
                                pcall(sub.cooldown.SetCooldown, sub.cooldown, start, duration)
                                local name = GetSpellName(sub.slot.currentSpellID)
                                sub.slot._swipeSpellName = name
                                sub.slot._onCooldown     = true
                            end
                        end
                    end
            end
        end)
    end)
    pcall(function()
        hooksecurefunc(cdFrame, "Clear", function(self)
            local frameData = hookedCooldownFrameData[cdFrame]
            if not frameData then return end
            -- Ne vider que si la version correspond : un Clear() d'une frame GCD
            -- (version différente) ne vide pas l'entrée du vrai CD.
            local entry = cdmCDData[frameData.spellID]
            if entry and entry.version == frameData.version then
                entry.onCD = false
                -- Clone Clear vers les abonnés (même guard forDisplayID).
                local subs = cdmCooldownSubscribers[frameData.spellID]
                if subs then
                    for _, sub in pairs(subs) do
                        if sub.cooldown and sub.slot
                           and sub.slot.currentSpellID == sub.forDisplayID then
                            pcall(sub.cooldown.Clear, sub.cooldown)
                            sub.slot._onCooldown     = false
                            sub.slot._swipeSpellName = nil
                        end
                    end
                end
            end
            hookedCooldownFrameData[cdFrame] = nil
        end)
    end)
end

-- Décide s'il faut masquer : si l'utilisateur préfère le CDM natif, ne rien masquer.
-- Sinon, force le masking pour BuffIcon/BuffBar quand l'option globale est activée,
-- ou retombe sur le masking basé sur la whitelist (comportement Utility).
local function ShouldMaskFrame(frame, spellID)
    if ns.db and ns.db.useNativeCDM then return false end
    if buffFrameAlwaysMask[frame] and ns.db and ns.db.hideCDMBuffFrames then
        return true
    end
    return ns.activeWhitelist and ns.IsInWhitelist(ns.activeWhitelist, spellID) or false
end

-- MASKING CDM : SetAlpha(0) uniquement — JAMAIS SetScale (tue le CDM au 2ème combat)
local function MaskCDMFrame(frame, shouldMask)
    pcall(function()
        if shouldMask then
            frame:SetAlpha(0)
        else
            if frame:GetAlpha() < 0.1 then
                frame:SetAlpha(1)
            end
        end
    end)
end

-- Scratch table pour le check War Gear dans AutoDiscoverSpell.
-- Réutilisée entre appels : évite d'allouer une table à chaque SetAuraInstanceInfo.
local _wgNamesScratch = {}

-- Retourne une couleur tirée au hasard parmi les couleurs thématiques de la spé
-- courante (Colors.ELEMENT_KEYS). Chaque nouvelle aura découverte reçoit ainsi
-- une couleur distincte plutôt que la même couleur de classe pour toutes.
-- Fallback sur ns.barColor si le module Colors n'est pas disponible.
local function GetRandomSpecColor()
    local Colors = _addon and _addon.Modules and _addon.Modules.Colors
    if Colors and Colors.ELEMENT_KEYS and #Colors.ELEMENT_KEYS > 0 and Colors.Get then
        local key = Colors.ELEMENT_KEYS[math.random(#Colors.ELEMENT_KEYS)]
        local c = Colors.Get(key)
        if c and c[1] then return { c[1], c[2], c[3] } end
    end
    local bc = ns.barColor
    return { bc[1], bc[2], bc[3] }
end

-- Auto-découverte hoistée : appelée par chaque SetAuraInstanceInfo pour un sort
-- inconnu. Skip si déjà dans spells, skip si déjà War Gear (par spellID/itemID/nom).
-- Hoist pour éviter la closure pcall à chaque hit CDM (très fréquent en combat).
local function AutoDiscoverSpell(spellID, name, unit, frame)
    local spells = ns.GetSpecSpells()
    if not spells then
        return
    end
    if spells[spellID] then
        -- Sort deja dans la liste : on log juste son etat (enabled, destinations)
        return
    end
    -- Skip War Gear
    if ns.Providers and ns.Providers.GetAllSlots then
        wipe(_wgNamesScratch)
        for _,slot in ipairs(ns.Providers:GetAllSlots()) do
            if (slot.spellID == spellID) or (slot.itemID == spellID) then
                return
            end
            local sn = ns.Providers.GetSlotName and ns.Providers:GetSlotName(slot)
            if sn then _wgNamesScratch[sn:lower()] = true end
        end
        if name and _wgNamesScratch[name:lower()] then
            return
        end
    end
    -- frameSource[frame] fait autorité (positionné par HookCDMFrame selon le viewer :
    -- "debuff" pour Essential/Utility, "enhancement" pour BuffIcon/BuffBar).
    -- Fallback : unit == "target" → "debuff", sinon "buff".
    local src = frameSource[frame]
               or ((unit == "target") and "debuff" or "buff")
    local defaults = ns.DeepCopy(ns.SpellDefaults)
    defaults.name = name
    defaults.color = GetRandomSpecColor()
    defaults._colorDefault = false  -- couleur thématique appliquée, ne plus retoucher
    defaults.priority = spellID
    defaults.source = src
    -- Destinations : toutes inactives à la découverte.
    -- L'utilisateur choisit librement la position (L/C/I/B) depuis Auras à tracker.
    defaults.destinations = { iconlist=false, circlebars=false, icons=false, freebars=false }
    spells[spellID] = defaults
end

------------------------------------------------------------------------
-- MIGRATION DES COULEURS PAR DÉFAUT
--
-- Parcourt les auras existantes et remplace leur couleur si elle n'a
-- jamais été définie manuellement.
--
-- Trois états du flag _colorDefault :
--   nil   → ancien sort (pré-flag) : on compare à ns.barColor pour décider
--   true  → explicitement marqué "à rouler" (cas théorique, non utilisé pour l'instant)
--   false → déjà roulé ou défini manuellement : on ne touche plus jamais
------------------------------------------------------------------------
function ns.RollDefaultSpecColors()
    local spells = ns.GetSpecSpells()
    if not spells then return end
    local bc = ns.barColor
    if not bc then return end

    for _, info in pairs(spells) do
        local cd = info._colorDefault
        local isDefault = false

        if cd == true then
            -- Flag explicite "à rouler"
            isDefault = true
        elseif cd == nil then
            -- Ancien sort sans flag : défaut si la couleur est exactement ns.barColor
            local c = info.color
            if c then
                isDefault = math.abs((c[1] or 0) - bc[1]) < 0.001
                        and math.abs((c[2] or 0) - bc[2]) < 0.001
                        and math.abs((c[3] or 0) - bc[3]) < 0.001
            end
        end
        -- cd == false → jamais retoucher (roulé ou défini manuellement)

        if isDefault then
            info.color = GetRandomSpecColor()
            info._colorDefault = false  -- verrouillé : plus jamais retoucher
        end
    end
end

local function HookCDMFrame(frame, canMask, source, alwaysMask)
    if not frame or not frame.SetAuraInstanceInfo or hookedFrames[frame] then return end
    hookedFrames[frame] = true
    if canMask then maskableFrames[frame] = true end
    if alwaysMask then buffFrameAlwaysMask[frame] = true end
    if source then frameSource[frame] = source end

    hooksecurefunc(frame, "SetAuraInstanceInfo", function(self, cdmAura)
        local spellID = GetCDMFrameSpellID(self)
        if not spellID then return end
        local instID = cdmAura and cdmAura.auraInstanceID
        if not instID then return end
        local unit = self.auraDataUnit
        if not unit or not cdmData[unit] then return end

        local existing = cdmData[unit][instID]
        if existing and existing.spellId == spellID then
            -- Same aura, same spellID : juste re-appliquer le masking et sortir.
            if maskableFrames[self] then
                MaskCDMFrame(self, ShouldMaskFrame(self, spellID))
            end
            return
        end

        local name = GetSpellName and GetSpellName(spellID) or tostring(spellID)
        cdmData[unit][instID] = { spellId = spellID, name = name }

        -- TRACE : nouvelle aura CDM detectee

        -- Auto-découverte : tous les viewers CDM.
        -- SetAuraInstanceInfo est déclenché uniquement quand Blizzard affecte une
        -- vraie aura (avec auraInstanceID) — c'est déjà le filtre correct.
        if name then pcall(AutoDiscoverSpell, spellID, name, unit, self) end

        -- Applique le masking (basé sur la whitelist OU forcé pour BuffIcon/BuffBar)
        if maskableFrames[self] then
            MaskCDMFrame(self, ShouldMaskFrame(self, spellID))
        end

        -- SCAN IMMÉDIAT : Blizzard vient de nous signaler une nouvelle aura via
        -- SetAuraInstanceInfo sur la CDM frame. C'est le moment LE PLUS tôt où les
        -- données sont disponibles — AVANT même que UNIT_AURA soit dispatché au Lua.
        --
        -- COALESCE SANS TIMER : si plusieurs SetAuraInstanceInfo sont appelés dans
        -- le même frame Blizzard (ex: 5 DOTs sur la cible qu'on vient de tab), on
        -- coalesce via GetTime() qui est IDENTIQUE pour toutes les exécutions du
        -- même frame. Au second appel, lastScanTime == GetTime() → skip.
        -- Avantage sur C_Timer.After(0) : pas d'attente du frame suivant (~16ms),
        -- scan exécuté SYNCHRONE dans le frame courant.
        local now = GetTime()
        if now ~= ns._cdmLastScanTime then
            ns._cdmLastScanTime = now
            pcall(ns.ScanAuras)
        end
    end)

    -- Hook le Cooldown enfant pour le tracking event-driven des CD.
    -- Plus fiable que le polling ScanCooldownViewer/IsShown : les valeurs
    -- cdStart/cdDuration sont exactement celles que Blizzard a calculées,
    -- et onCD devient true/false instantanément sans lag de polling.
    if frame.Cooldown then
        HookCDMCooldownChild(frame.Cooldown, frame)
    end
end

function ns.InitCDMHooks()
    if cdmHooked then return end
    local viewers = {}
    pcall(function()
        if EssentialCooldownViewer  then tinsert(viewers, {v=EssentialCooldownViewer,  mask=false, src="debuff",      alwaysMask=false}) end
        if UtilityCooldownViewer    then tinsert(viewers, {v=UtilityCooldownViewer,    mask=true,  src="debuff",      alwaysMask=false}) end
        if BuffIconCooldownViewer   then tinsert(viewers, {v=BuffIconCooldownViewer,   mask=true,  src="enhancement", alwaysMask=true})  end
        if BuffBarCooldownViewer    then tinsert(viewers, {v=BuffBarCooldownViewer,    mask=true,  src="enhancement", alwaysMask=true})  end
    end)
    if #viewers == 0 then return end
    for _, info in ipairs(viewers) do
        pcall(function()
            hooksecurefunc(info.v, "OnAcquireItemFrame", function(_, frame)
                HookCDMFrame(frame, info.mask, info.src, info.alwaysMask)
            end)
            for _, f in pairs({ info.v:GetChildren() }) do
                HookCDMFrame(f, info.mask, info.src, info.alwaysMask)
            end
        end)
    end
    cdmHooked = true
end

-- Ré-applique le masking sur toutes les frames hookées (appelé après changement
-- d'option ou reconstruction de whitelist)
function ns.RefreshCDMMask()
    pcall(function()
        local forceOn = ns.db and ns.db.hideCDMBuffFrames
        for frame in pairs(maskableFrames) do
            pcall(function()
                local sid = GetCDMFrameSpellID(frame)
                -- Skip les frames vides sauf si force-masked (BuffIcon/BuffBar avec option activée)
                if not sid and not (buffFrameAlwaysMask[frame] and forceOn) then return end
                MaskCDMFrame(frame, ShouldMaskFrame(frame, sid))
            end)
        end
    end)
end

------------------------------------------------------------------------
-- SCAN PROACTIF DES VIEWERS CDM
--
-- Découvre immédiatement tous les sorts que le CDM est configuré à tracker
-- pour la spec courante, sans attendre qu'ils apparaissent en combat.
-- Appelé à PLAYER_ENTERING_WORLD, PLAYER_SPECIALIZATION_CHANGED, et
-- après InitCDMHooks (via les timers de retry dans Events.lua).
--
-- 3 méthodes complémentaires (ordre du plus précis au plus large) :
--
--  1) C_CooldownViewer.GetCooldownViewerCategorySet :
--     API officielle, retourne tous les cooldownIDs d'une catégorie (même
--     inactifs). Couvre TrackedBuff (BuffIconViewer) et TrackedBar
--     (BuffBarViewer). Source player/enhancement.
--
--  2) Itération directe des frames de chaque viewer :
--     GetChildren + layoutChildren + itemFramePool:EnumerateActive().
--     Couvre EssentialViewer / UtilityViewer (debuffs target) et les
--     frames actives des buff viewers. Source déduite du viewer.
--
--  3) CooldownViewerSettings DataProvider (cooldownInfoByID) :
--     Liste exhaustive de TOUS les sorts trackés par le CDM, même ceux
--     que les méthodes 1-2 n'ont pas vu (inactifs, hors catégorie API).
--     Source "player" par défaut — les debuffs seront reclassifiés via
--     SetAuraInstanceInfo dès qu'ils apparaissent en combat.
--     Skip si le sort a déjà été découvert par les méthodes 1-2.
------------------------------------------------------------------------
-- Retourne true si instID indique une aura active sur le frame.
-- Logique TWW : les frames CD-only ont auraInstanceID = nil.
-- Les frames avec une vraie aura ont auraInstanceID soit clean (number > 0)
-- soit secret value (TWW protège les IDs en combat). Dans les deux cas
-- non-nil = aura présente. Une secret value NE doit PAS être rejetée —
-- c'est exactement l'inverse de ce qu'on voulait : secret = aura réelle.
local function IsValidAuraInstanceID(instID)
    if instID == nil then return false end
    -- Secret value → aura réelle (les frames sans aura ont nil, pas une secret value)
    if type(issecretvalue) == "function" then
        local ok, isSecret = pcall(issecretvalue, instID)
        if ok and isSecret then return true end
    end
    -- Valeur clean : doit être un number > 0
    return type(instID) == "number" and instID > 0
end

function ns.ScanCDMViewers()
    -- SOURCE PRINCIPALE : liste statique CDM via GetCooldownViewerCategorySet.
    -- Le CDM maintient une liste de toutes les auras trackées pour la spec courante.
    -- TrackedBuff = onglet "Améliorations" icônes (BuffIconCooldownViewer)
    -- TrackedBar  = onglet "Améliorations" barres (BuffBarCooldownViewer)
    -- Cette liste existe hors combat, elle ne dépend pas d'auras actives.
    -- Elle est la source faisant autorité pour la spec — c'est ce qu'on veut.
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
       and Enum and Enum.CooldownViewerCategory then
        local function ScanCategory(cat, unit)
            if not cat then return end
            pcall(function()
                local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
                if type(ids) ~= "table" then return end
                for _, cooldownID in ipairs(ids) do
                    pcall(function()
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo
                                     and C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                        if not info then return end
                        local lids = info.linkedSpellIDs
                        local sid = (type(lids) == "table" and lids[1])
                                    or info.overrideTooltipSpellID or info.linkedSpellID
                                    or info.overrideSpellID or info.spellID
                        if type(sid) ~= "number" or sid <= 0 then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, unit, nil) end
                    end)
                end
            end)
        end
        ScanCategory(Enum.CooldownViewerCategory.TrackedBuff, "player")
        ScanCategory(Enum.CooldownViewerCategory.TrackedBar,  "player")
    end

    -- FALLBACK : frames actives dans les viewers si l'API catégorie n'est pas disponible.
    -- Filtre auraInstanceID pour ne prendre que les vraies auras (pas les frames CD-only).
    local viewerDefs = {
        { v = EssentialCooldownViewer,  unit = "target" },
        { v = UtilityCooldownViewer,    unit = "target" },
        { v = BuffIconCooldownViewer,   unit = "player" },
        { v = BuffBarCooldownViewer,    unit = "player" },
    }
    for _, def in ipairs(viewerDefs) do
        local viewer = def.v
        if viewer then
            -- GetChildren standard
            pcall(function()
                for _, frame in pairs({ viewer:GetChildren() }) do
                    pcall(function()
                        if not IsValidAuraInstanceID(frame.auraInstanceID) then return end
                        local sid = GetScanSpellID(frame)
                        if not sid then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, def.unit, frame) end
                    end)
                end
            end)
            -- layoutChildren
            pcall(function()
                local lc = viewer.layoutChildren
                if type(lc) ~= "table" then return end
                for _, frame in pairs(lc) do
                    pcall(function()
                        if type(frame) ~= "table" then return end
                        if not IsValidAuraInstanceID(frame.auraInstanceID) then return end
                        local sid = GetScanSpellID(frame)
                        if not sid then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, def.unit, frame) end
                    end)
                end
            end)
            -- itemFramePool:EnumerateActive
            pcall(function()
                local pool = viewer.itemFramePool
                if not (pool and pool.EnumerateActive) then return end
                for itemFrame in pool:EnumerateActive() do
                    pcall(function()
                        if not IsValidAuraInstanceID(itemFrame.auraInstanceID) then return end
                        local sid
                        if itemFrame.GetBaseSpellID then
                            local ok, s = pcall(itemFrame.GetBaseSpellID, itemFrame)
                            if ok and type(s) == "number" and s > 0 then sid = s end
                        end
                        if not sid then sid = GetScanSpellID(itemFrame) end
                        if not sid then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, def.unit, itemFrame) end
                    end)
                end
            end)
        end
    end
    -- Méthode 3 (cooldownInfoByID) supprimée : trop large, inclut les sorts/CDs
    -- sans distinction. La découverte se fait via SetAuraInstanceInfo (hook réactif)
    -- et les méthodes 1-2 ci-dessus pour les auras déjà actives.

    -- Migration one-shot : applique les couleurs thématiques aux auras dont la
    -- couleur n'a jamais été définie manuellement (couleur = défaut de classe).
    if ns.RollDefaultSpecColors then
        pcall(ns.RollDefaultSpecColors)
    end
end

-- Stub : sera remplacé par une liste codée en dur par spec/classe.
function ns.ReclassifyExistingSpells() end


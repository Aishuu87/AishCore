-- AishUIAura/Core/CDMHooks.lua
-- Hooks du Cooldown Manager Blizzard : parse les spell IDs, hooke BuffIcon/BuffBar, masking
-- via SetAlpha(0) uniquement (jamais SetScale, qui tue le CDM au 2e combat).
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

local tinsert = table.insert
local pcall, hooksecurefunc = pcall, hooksecurefunc

local GetSpellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo

-- Hooks CDM (pattern motor, namespace ns, masking SetAlpha(0) uniquement)
local cdmData = { player = {}, target = {} }
ns.cdmData = cdmData
local cdmHooked = false

-- Presence pure [unit][spellID], alimentee uniquement par le hook SetAuraInstanceInfo, jamais purgee.
-- Necessaire pour les buffs sans vraie duree/stacks (ex. Rapidite de la nature/378081) ou toute la chaine
-- de detection habituelle (stacks, swipe de cooldown) echoue en combat : SetAuraInstanceInfo reste le
-- seul signal fiable de liaison/deliaison d'une instance d'aura a l'icone dans ce cas.
local cdmAuraInstancePresence = { player = {}, target = {} }
ns.cdmAuraInstancePresence = cdmAuraInstancePresence

-- true/false = presence confirmee par SetAuraInstanceInfo ; nil = jamais observe pour ce spellID/unit.
-- Ne s'efface jamais seul (sauf demarrage de CD, uniquement pour les sorts sans swipe de duree, meme
-- garde que HookCDMCooldownChild plus bas) pour ne pas court-circuiter la chaine cdmData/swipe existante.
-- Valeur = nombre (GetTime() du dernier "vu") ou false (jamais vu, a distinguer de nil pour un `~= nil` fiable).
local function HasEverConfirmedPresence(t, spellID)
    return type(t[spellID]) == "number"
end

-- Ce tier n'a aucune expiration propre, donc restreint a une liste explicite de sorts "banked" confirmes
-- (dure jusqu'au prochain cast, CD demarre a la consommation du buff, jamais au cast) pour eviter qu'une
-- simple course au demarrage le rende autoritaire a tort sur un sort normal.
local BANKED_BUFF_SPELLS = { [378081] = true }  -- Rapidite de la nature

function ns.IsCDMAuraInstancePresent(unit, spellID)
    if not BANKED_BUFF_SPELLS[spellID] then return nil end
    -- Garde supplementaire (ceinture-bretelles) : ne jamais prendre la main
    -- si un canal barre/swipe a deja confirme une vraie presence pour ce
    -- spellID, meme s'il est dans la liste ci-dessus.
    if HasEverConfirmedPresence(ns.cdmAuraSwipePresence, spellID) then return nil end
    if HasEverConfirmedPresence(ns.cdmAuraBarPresence, spellID) then return nil end
    local u = cdmAuraInstancePresence[unit]
    return u and u[spellID]
end
local hookedFrames, maskableFrames, frameSource, buffFrameAlwaysMask = {}, {}, {}, {}

-- Donnees CD event-driven, alimentees par les hooks SetCooldown/Clear (plus fiable que le polling IsShown
-- de PriorityBar.ScanCooldownViewer). cdmCDData[spellID] = { cdStart, cdDuration, onCD } : onCD passe a
-- true a SetCooldown, false a Clear().
local cdmCDData = {}
ns.cdmCDData = cdmCDData

-- Donnees de charges event-driven, via un hook SetText sur itemFrame.ChargeCount.Current (meme widget que
-- PriorityBar lit par polling, mais capture via GetText() au moment exact de l'ecriture, sans lag).
-- cdmChargeData[spellID] = texte brut FontString (jamais un nombre, comparer via tonumber/pcall).
-- Additif uniquement : PriorityBar garde son fallback poll+estimation (kill-switch CDM_CHARGE_HOOK_ENABLED).
local cdmChargeData = {}
ns.cdmChargeData = cdmChargeData

-- Doit etre defini avant HookCDMCooldownChild (variable locale, doit etre en scope a la compilation).
local function GetCDMFrameSpellID(frame)
    if not frame.cooldownInfo or not frame.cooldownID then return nil end
    local info = frame.cooldownInfo
    local ret = info.spellID
    if info.linkedSpellIDs and info.linkedSpellIDs[1] then ret = info.linkedSpellIDs[1] end
    return ret
end

-- Variante scan-only : priorite overrideTooltipSpellID > linkedSpellID > linkedSpellIDs[1] > overrideSpellID
-- > spellID, sans garde cooldownID. 2e retour (lids) : linkedSpellIDs brute, pour regrouper les variantes
-- de rang/stacks d'un meme buff (AutoDiscoverSpell, Whitelist.lua).
local function GetScanSpellID(frame)
    if not frame then return nil end
    local info = frame.cooldownInfo
    if not info then return nil end
    local lids = info.linkedSpellIDs
    local sid = (type(lids) == "table" and lids[1])
             or info.overrideTooltipSpellID or info.linkedSpellID
             or info.overrideSpellID or info.spellID
    if type(sid) ~= "number" or sid <= 0 then return nil end
    return sid, lids
end

local hookedCooldownChildren  = {}
-- [cdFrame] = { spellID, cdStart, cdDuration }, pour distinguer la frame GCD (duration<=1.5) du vrai CD
-- (duration>1.5) qui partagent le meme spellID lors du matching dans Clear().
local hookedCooldownFrameData = {}

-- Hooke le Cooldown enfant d'une frame CDM pour capturer les donnees CD event-driven. Filtre le GCD
-- (seuls les CDs > 1.5s vont dans cdmCDData) et matche Clear() par version pour ne pas vider le vrai CD
-- via un Clear() du GCD. start/duration sont des secret numbers (comparaison impossible meme via tonumber),
-- donc on utilise parentFrame.isOnGCD (booleen lisible) pour le filtre GCD et un compteur de version
-- (entier Lua pur) pour le matching, sans jamais comparer de secret numbers.
local cdFrameVersion = {}  -- [cdFrame] = dernier numéro de version SetCooldown

-- Abonnements "clone swipe" : quand le CDM appelle SetCooldown/Clear pour le spellID X, on retransmet les
-- arguments (secret numbers inclus) a chaque frame abonnee, sans jamais les lire/comparer.
-- cdmCooldownSubscribers[spellID][key] = { cooldown=frame Cooldown cible, slot=slot-frame PriorityBar }.
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

-- Abonnements "clone swipe" generiques pour la duree des auras (distinct de cdmCooldownSubscribers,
-- reserve aux cooldowns de sort). C_UnitAuras refuse l'acces aux auras a duree limitee en combat, mais le
-- CDM (code Blizzard non tainte) continue d'appeler Cooldown:SetCooldown sur ses propres frames -- on
-- retransmet ces valeurs (secretes ou pas) sans jamais les lire/comparer ("show but don't know").
-- Sert aussi de source de vivacite : un SetCooldown recu = aura presente, un Clear() = aura disparue.
-- ns.cdmAuraSwipePresence stocke un timestamp (pas un bool) car les frames CDM sont recyclees par Blizzard
-- sans garantie de Clear() explicite ; IsCDMAuraSwipePresent traite donc une entree trop vieille comme perimee.
-- Le seuil de peremption doit rester large : Blizzard n'appelle SetCooldown qu'au demarrage/refresh (le
-- widget anime le swipe seul ensuite), un seuil court ferait disparaitre a tort des auras encore actives.
local cdmAuraSwipeSubscribers = {}  -- [spellID][key] = cdFrame (widget Cooldown abonné)
ns.cdmAuraSwipePresence = ns.cdmAuraSwipePresence or {}  -- [spellID] = GetTime() du dernier SetCooldown vu, ou false apres un Clear()
local CDM_AURA_SWIPE_STALE_AFTER = 900  -- 15 min : filet de securite uniquement, pas une detection normale
-- Seuil bien plus court pour le canal bar (BuffBarCooldownViewer) : Blizzard rappelle SetMinMaxValues/SetValue
-- toutes les 1-2s pour une aura active (pas d'equivalent Clear(), signal d'expiration hi=0 pas systematique).
local CDM_AURA_BAR_STALE_AFTER = 5

-- true si le CDM a confirmé cette aura active récemment (ni explicitement
-- Clear()-ée, ni périmée faute de refresh récent).
function ns.IsCDMAuraSwipePresent(spellID)
    local t = ns.cdmAuraSwipePresence[spellID]
    if not t then return false end
    return (GetTime() - t) < CDM_AURA_SWIPE_STALE_AFTER
end

-- S'abonner au clone du swipe CDM pour une aura (buff/debuff), par spellID.
-- key     : identifiant unique de l'abonné (généralement l'icône/row elle-même).
-- cdFrame : widget Cooldown à piloter (ex: row.iconCD).
function ns.SubscribeCDMAuraSwipe(spellID, key, cdFrame)
    if not spellID or not key or not cdFrame then return end
    if not cdmAuraSwipeSubscribers[spellID] then
        cdmAuraSwipeSubscribers[spellID] = {}
    end
    cdmAuraSwipeSubscribers[spellID][key] = cdFrame
end

function ns.UnsubscribeCDMAuraSwipe(spellID, key)
    if not spellID or not key then return end
    local subs = cdmAuraSwipeSubscribers[spellID]
    if subs then
        subs[key] = nil
        if not next(subs) then cdmAuraSwipeSubscribers[spellID] = nil end
    end
end

-- Abonnements "clone bar" pour la duree (StatusBar, pas Cooldown) : Cooldown:SetCooldown() rejette toute
-- valeur secrete venant de code addon, mais StatusBar:SetValue()/SetMinMaxValues() l'acceptent (meme sink
-- que ResourceCircle pour l'absorb). BuffBarCooldownViewer (viewer "Barres") construit son remplissage avec
-- une vraie StatusBar (frame.Bar) contrairement aux autres viewers (Cooldown) : on clone ses appels
-- SetMinMaxValues/SetValue vers un widget a nous. Ne fonctionne que pour un sort epingle sur ce viewer.
local cdmAuraBarSubscribers = {}  -- [spellID][key] = statusBarLike (SetMinMaxValues/SetValue/Show)
ns.cdmAuraBarPresence = ns.cdmAuraBarPresence or {}  -- [spellID] = GetTime() du dernier SetValue vu

function ns.IsCDMAuraBarPresent(spellID)
    local t = ns.cdmAuraBarPresence[spellID]
    if not t then return false end
    return (GetTime() - t) < CDM_AURA_BAR_STALE_AFTER
end

function ns.SubscribeCDMAuraBar(spellID, key, statusBarLike)
    if not spellID or not key or not statusBarLike then return end
    if not cdmAuraBarSubscribers[spellID] then
        cdmAuraBarSubscribers[spellID] = {}
    end
    cdmAuraBarSubscribers[spellID][key] = statusBarLike
end

function ns.UnsubscribeCDMAuraBar(spellID, key)
    if not spellID or not key then return end
    local subs = cdmAuraBarSubscribers[spellID]
    if subs then
        subs[key] = nil
        if not next(subs) then cdmAuraBarSubscribers[spellID] = nil end
    end
end

-- Abonnements "clone stack" pour les compteurs d'applications : meme principe show-but-don't-know que le
-- clone swipe, applique a cdmAura.applications (retransmis a un FontString via SetText, jamais lu/compare).
-- Pour les auras du joueur, Debuffs.lua utilise plutot ResourceCircle.ApplyStacksTo (peut confirmer un 0
-- franc) ; ce canal reste la seule source pour les auras de la cible (pas d'equivalent cote cible).
local cdmAuraStackSubscribers = {}  -- [spellID][key] = FontString abonne
-- Derniere valeur vue par spellID, alimentee a chaque SetAuraInstanceInfo (avec ou sans abonne) pour
-- rattraper un abonnement qui arrive juste apres le scan qui a fait apparaitre l'aura.
local cdmAuraLastApplications = {}  -- [spellID] = derniere valeur applications vue

-- applications est toujours secrete en combat : comparer meme tostring(applications) plante si non pcall
-- separement de la conversion. Comme aucune comparaison ne peut confirmer un 0 en combat, on affiche par
-- defaut des la 1ere aura vue et on ne cache durablement que les spellID confirmes "jamais > 1" hors combat
-- (ns.MarkStackNotCapable), leve des qu'une confirmation > 1 arrive (ns.MarkStackCapable) -- fail-open, pour
-- ne pas bloquer indefiniment le badge d'une aura qui n'existe qu'en combat (debuff de boss, proc de tank).
ns.stackCapableSpells    = ns.stackCapableSpells    or {}  -- [spellID] = true, confirme >1 au moins une fois
ns.stackNotCapableSpells = ns.stackNotCapableSpells or {}  -- [spellID] = true, confirme jamais >1 hors combat

function ns.MarkStackCapable(spellID)
    if not spellID then return end
    ns.stackCapableSpells[spellID] = true
    ns.stackNotCapableSpells[spellID] = nil
end

function ns.MarkStackNotCapable(spellID)
    if spellID and not ns.stackCapableSpells[spellID] then
        ns.stackNotCapableSpells[spellID] = true
    end
end

local function PushStackApplications(spellID, fontString, applications)
    if applications == nil or ns.stackNotCapableSpells[spellID] then
        pcall(fontString.Hide, fontString)
        return
    end
    local okStr, str = pcall(tostring, applications)
    local hideIt = false
    if okStr then
        local okCmp, isZeroOrOne = pcall(function() return str == "0" or str == "1" end)
        hideIt = okCmp and isZeroOrOne
    end
    if hideIt then
        pcall(fontString.Hide, fontString)
    else
        pcall(fontString.SetText, fontString, applications)
        pcall(fontString.Show, fontString)
    end
end

function ns.SubscribeCDMAuraStack(spellID, key, fontString)
    if not spellID or not key or not fontString then return end
    if not cdmAuraStackSubscribers[spellID] then
        cdmAuraStackSubscribers[spellID] = {}
    end
    cdmAuraStackSubscribers[spellID][key] = fontString
    -- Rattrapage : pousse immediatement la derniere valeur connue si on en a une.
    if cdmAuraLastApplications[spellID] ~= nil then
        PushStackApplications(spellID, fontString, cdmAuraLastApplications[spellID])
    end
end

function ns.UnsubscribeCDMAuraStack(spellID, key)
    if not spellID or not key then return end
    local subs = cdmAuraStackSubscribers[spellID]
    if subs then
        subs[key] = nil
        if not next(subs) then cdmAuraStackSubscribers[spellID] = nil end
    end
end

-- Canal "clone durObj" (SetCooldownFromDurationObject) tente pour animer les barres en combat, abandonne :
-- Blizzard n'appelle jamais cette fonction sur les Cooldown-enfants CDM pour la duree des buffs (uniquement
-- SetCooldown a deux nombres). Voir Animation.lua pour la piste retenue (lecture du texte de decompte natif).

-- Journal diagnostique des N derniers SetCooldown vus, avant le filtre wasSetFromCooldown/isOnGCD, consultable via /aacdm.
local cdmSetCooldownLog = {}
ns._cdmSetCooldownLog = cdmSetCooldownLog
local CDM_LOG_MAX = 30

-- Journal opt-in par spellID (ns._cdmWatchSpells[spellID]=true), plus long (200 entrees) pour survivre au
-- bruit des autres sorts en combat qui viderait sinon le journal global avant lecture. Capture aussi
-- Clear() et les charges pour reconstituer la sequence complete d'un sort.
ns._cdmWatchSpells = ns._cdmWatchSpells or {}
ns._cdmWatchLog = ns._cdmWatchLog or {}
local CDM_WATCH_LOG_MAX = 200

local function HookCDMCooldownChild(cdFrame, parentFrame)
    if not cdFrame or hookedCooldownChildren[cdFrame] then return end
    hookedCooldownChildren[cdFrame] = true
    pcall(function()
        hooksecurefunc(cdFrame, "SetCooldown", function(self, start, duration)
            local spellID = GetCDMFrameSpellID(parentFrame)
            if not spellID then return end
            -- Dernier duration brut vu par spellID (valeur jamais comparee), pour diagnostiquer via
            -- tostring() si le filtre forwardSwipe (duration>1.5, plus bas) bloque un swipe attendu.
            ns._cdmLastDuration = ns._cdmLastDuration or {}
            ns._cdmLastDuration[spellID] = duration
            local okDurLog, isLongLog = pcall(function() return type(duration) == "number" and duration > 1.5 end)
            tinsert(cdmSetCooldownLog, 1, {
                spellID = spellID,
                wasSetFromCooldown = parentFrame.wasSetFromCooldown and true or false,
                isOnGCD = parentFrame.isOnGCD and true or false,
                durOk = okDurLog, isLong = okDurLog and isLongLog or nil,
                t = GetTime(),
            })
            for i = #cdmSetCooldownLog, CDM_LOG_MAX + 1, -1 do cdmSetCooldownLog[i] = nil end
            if ns._cdmWatchSpells[spellID] then
                local wl = ns._cdmWatchLog[spellID]
                if not wl then wl = {}; ns._cdmWatchLog[spellID] = wl end
                local okStr, durStr = pcall(tostring, duration)
                tinsert(wl, 1, {
                    kind = "SetCooldown",
                    wasSetFromCooldown = parentFrame.wasSetFromCooldown and true or false,
                    isOnGCD = parentFrame.isOnGCD and true or false,
                    durOk = okDurLog, isLong = okDurLog and isLongLog or nil,
                    durStr = okStr and durStr or "?",
                    t = GetTime(),
                })
                for i = #wl, CDM_WATCH_LOG_MAX + 1, -1 do wl[i] = nil end
            end
            -- Incrémenter le version counter (entier Lua pur, safe à comparer).
            local ver = (cdFrameVersion[cdFrame] or 0) + 1
            cdFrameVersion[cdFrame] = ver
            -- Tracker par frame pour le matching dans Clear().
            hookedCooldownFrameData[cdFrame] = { spellID=spellID, version=ver, wasSetFromCooldown=parentFrame.wasSetFromCooldown }

            -- Canal generique aura-swipe : aucun filtre wasSetFromCooldown/isOnGCD ici, il exclurait les mises a jour
            -- de duree de buff (wasSetFromCooldown=false). Cooldown:SetCooldown rejette toute valeur secrete
            -- venant de code addon meme en pur sink, donc ce canal ne peut jamais forwarder une duree
            -- reellement secrete en combat (seule voie combat-safe restante : AuraButton:SetDurationCooldown,
            -- appele par Blizzard lui-meme, cf. AuraTrackerContainer.lua). Reste utile hors combat seulement.
            -- La presence ne se rafraichit que sur une vraie mise a jour de duree d'aura (wasSetFromCooldown=
            -- false), pas sur une recharge de capacite (meme spellID, deux concepts differents) : sinon une
            -- capacite dont le CD dure plus longtemps que son buff (Rage du Berserker, Mur Protecteur) reste
            -- affichee "presente" bien apres la fin reelle du buff.
            if not parentFrame.wasSetFromCooldown then
                ns.cdmAuraSwipePresence[spellID] = GetTime()
            end
            local auraSubs = cdmAuraSwipeSubscribers[spellID]
            if auraSubs then
                for _, cd in pairs(auraSubs) do
                    pcall(cd.Show, cd)
                    pcall(cd.SetCooldown, cd, start, duration)
                end
            end
            -- Filtre GCD via isOnGCD (booleen natif lisible en tainte) : wasSetFromCooldown seul est
            -- insuffisant, vrai sur certaines frames GCD aussi.
            if parentFrame.wasSetFromCooldown and not parentFrame.isOnGCD then
                cdmCDData[spellID] = { version=ver, onCD=true }
                -- Signal de fin pour un buff "banked" (378081, cf. ns.IsCDMAuraInstancePresent) : si ce
                -- spellID n'a jamais eu de swipe de duree observe, le demarrage du CD de la capacite prouve
                -- que le buff vient d'etre consomme (son CD ne demarre qu'a la perte du buff). Restreint a
                -- ce cas pour ne pas couper l'anim d'un sort dont le CD demarre au cast normalement.
                -- Meme garde double canal (swipe+barre) que ns.IsCDMAuraInstancePresent : un sort suivi via
                -- le canal barre gere deja sa fin correctement, pas besoin de le forcer ici.
                if BANKED_BUFF_SPELLS[spellID]
                    and (not HasEverConfirmedPresence(ns.cdmAuraSwipePresence, spellID))
                    and (not HasEverConfirmedPresence(ns.cdmAuraBarPresence, spellID))
                    and ns.cdmAuraInstancePresence.player then
                    ns.cdmAuraInstancePresence.player[spellID] = false
                end
                    local subs = cdmCooldownSubscribers[spellID]
                    if subs then
                        -- Ne forwarder que si duration > 1.5s confirme (vrai CD) : evite les swipes GCD pour
                        -- les sorts a charges dont isOnGCD est parfois faux ; UpdateSlotExtras prend le relais.
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
    -- SetCooldownFromDurationObject : log diagnostique uniquement (/aacdm), jamais appelee pour les buffs sur ces frames.
    pcall(function()
        if cdFrame.SetCooldownFromDurationObject then
            hooksecurefunc(cdFrame, "SetCooldownFromDurationObject", function(self, durObj)
                local spellID = GetCDMFrameSpellID(parentFrame)
                if not spellID then return end
                tinsert(cdmSetCooldownLog, 1, {
                    spellID = spellID,
                    wasSetFromCooldown = "DUROBJ",
                    isOnGCD = parentFrame.isOnGCD and true or false,
                    t = GetTime(),
                })
                for i = #cdmSetCooldownLog, CDM_LOG_MAX + 1, -1 do cdmSetCooldownLog[i] = nil end
            end)
        end
    end)
    pcall(function()
        hooksecurefunc(cdFrame, "Clear", function(self)
            local frameData = hookedCooldownFrameData[cdFrame]
            if not frameData then return end
            if ns._cdmWatchSpells[frameData.spellID] then
                local wl = ns._cdmWatchLog[frameData.spellID]
                if not wl then wl = {}; ns._cdmWatchLog[frameData.spellID] = wl end
                tinsert(wl, 1, {
                    kind = "Clear",
                    wasSetFromCooldown = frameData.wasSetFromCooldown and true or false,
                    t = GetTime(),
                })
                for i = #wl, CDM_WATCH_LOG_MAX + 1, -1 do wl[i] = nil end
            end
            -- Canal generique aura-swipe : Clear() = aura disparue. Meme filtre que SetCooldown : n'efface
            -- que si cette frame trackait une duree d'aura, sinon une capacite revenue de CD avant la fin
            -- de son buff (traque via une autre frame) effacerait a tort la presence de ce buff actif.
            if not frameData.wasSetFromCooldown then
                ns.cdmAuraSwipePresence[frameData.spellID] = false
            end
            local auraSubs = cdmAuraSwipeSubscribers[frameData.spellID]
            if auraSubs then
                for _, cd in pairs(auraSubs) do
                    pcall(cd.Clear, cd)
                end
            end
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

-- Auto-decouverte hoistee : appelee par chaque SetAuraInstanceInfo pour un sort inconnu (skip si deja
-- dans spells ou deja War Gear). Hoist pour eviter la closure pcall a chaque hit CDM.
-- linkedSpellIDs (optionnel) : sid est toujours normalise a linkedSpellIDs[1] avant l'appel (ex: Precurseur
-- du Vide 1256301/1256302, meme case CDM selon le seuil de stacks) ; on stocke la liste complete sur
-- l'entree pour que Whitelist.lua inclue toutes les variantes des qu'une seule est cochee.
local function AutoDiscoverSpell(spellID, name, unit, frame, linkedSpellIDs)
    local spells = ns.GetSpecSpells()
    if not spells then
        return
    end
    local hasLinks = type(linkedSpellIDs) == "table" and #linkedSpellIDs > 1
    if spells[spellID] then
        -- Sort deja dans la liste : on rafraichit juste linkedSpellIDs si on
        -- vient d'en apprendre (peut ne pas etre dispo au tout premier scan).
        if hasLinks then spells[spellID].linkedSpellIDs = linkedSpellIDs end
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
    if hasLinks then defaults.linkedSpellIDs = linkedSpellIDs end
    -- Destinations : toutes inactives à la découverte.
    -- L'utilisateur choisit librement la position (L/C/I/B/T) depuis Auras à tracker.
    defaults.destinations = { iconlist=false, circlebars=false, icons=false, freebars=false, totems=false }
    spells[spellID] = defaults
end

-- Migration des couleurs par defaut : remplace la couleur des auras existantes si jamais definie manuellement.
-- Flag _colorDefault : nil = ancien sort (compare a ns.barColor), true = a rouler, false = ne plus toucher.
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

-- Hooke le StatusBar enfant (frame.Bar) de BuffBarCooldownViewer, comme HookCDMCooldownChild pour
-- frame.Cooldown mais via un sink (StatusBar:SetValue) qui accepte les valeurs secretes d'un addon.
local hookedBarChildren = {}
local function HookCDMBarChild(barFrame, parentFrame)
    if not barFrame or hookedBarChildren[barFrame] then return end
    hookedBarChildren[barFrame] = true
    pcall(function()
        hooksecurefunc(barFrame, "SetMinMaxValues", function(self, lo, hi)
            local spellID = GetCDMFrameSpellID(parentFrame)
            if not spellID then return end
            -- Blizzard envoie hi=0 en clair au moment precis ou le buff expire : effacer la presence dans
            -- ce cas plutot que la rafraichir, sinon un buff expire reste "present" jusqu'a 15 min.
            -- Gater ce hi=0 derriere "a deja eu une plage positive" casserait le masquage de la majorite
            -- des auras en Barres (l'hypothese "hi>0 observe au moins une fois" est fausse en pratique) ;
            -- le fix pour les auras sans signal hi>0 fiable vit cote Scan.lua (ns._lastKnownAura).
            local okZero, isZero = pcall(function() return hi == 0 end)
            if okZero and isZero then
                ns.cdmAuraBarPresence[spellID] = false
            else
                ns.cdmAuraBarPresence[spellID] = GetTime()
            end
            local subs = cdmAuraBarSubscribers[spellID]
            if subs then
                for _, statusBarLike in pairs(subs) do
                    pcall(statusBarLike.SetMinMaxValues, statusBarLike, lo, hi)
                end
            end
        end)
    end)
    pcall(function()
        hooksecurefunc(barFrame, "SetValue", function(self, value)
            local spellID = GetCDMFrameSpellID(parentFrame)
            if not spellID then return end
            local subs = cdmAuraBarSubscribers[spellID]
            if subs then
                for _, statusBarLike in pairs(subs) do
                    pcall(statusBarLike.Show, statusBarLike)
                    pcall(statusBarLike.SetValue, statusBarLike, value)
                end
            end
        end)
    end)
end

-- Hooke ChargeCount.Current pour capturer le texte de charges event-driven, meme lecture (GetText) que
-- ScanCooldownViewer par polling, juste avancee au lieu d'attendre le prochain tick a 0.15s.
local hookedChargeCountChildren = {}
local function HookCDMChargeCountChild(fs, parentFrame)
    if not fs or hookedChargeCountChildren[fs] then return end
    hookedChargeCountChildren[fs] = true
    pcall(function()
        hooksecurefunc(fs, "SetText", function(self)
            local spellID = GetCDMFrameSpellID(parentFrame)
            if not spellID then return end
            local ok, txt = pcall(self.GetText, self)
            if ok then
                cdmChargeData[spellID] = txt
                if ns._cdmWatchSpells[spellID] then
                    local wl = ns._cdmWatchLog[spellID]
                    if not wl then wl = {}; ns._cdmWatchLog[spellID] = wl end
                    tinsert(wl, 1, { kind = "Charge", text = txt, t = GetTime() })
                    for i = #wl, CDM_WATCH_LOG_MAX + 1, -1 do wl[i] = nil end
                end
            end
        end)
    end)
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
        -- Presence pure (voir declaration ci-dessus) : enregistree AVANT tout
        -- doit capter aussi bien la liaison (instID present) que la deliaison (cdmAura/instID nil).
        -- self.auraDataUnit reste lisible meme quand cdmAura est nil (propriete de la frame, pas de l'aura).
        do
            local puUnit = self.auraDataUnit
            if puUnit then
                cdmAuraInstancePresence[puUnit] = cdmAuraInstancePresence[puUnit] or {}
                cdmAuraInstancePresence[puUnit][spellID] = (instID ~= nil)
            end
        end
        if not instID then return end
        local unit = self.auraDataUnit
        if not unit or not cdmData[unit] then return end

        -- Cle = spellID, pas instID : un auraInstanceID peut etre secret (indexable seulement comme valeur,
        -- pas comme cle de table). spellID reste toujours clean sur ce hook. Pas de dedup ici (comparer deux
        -- instID secrets planterait aussi) ; AutoDiscoverSpell et MaskCDMFrame sont deja idempotents.
        local name = GetSpellName and GetSpellName(spellID) or tostring(spellID)
        cdmData[unit][spellID] = { spellId = spellID, name = name, instID = instID }

        -- Clone stack : retransmet cdmAura.applications tel quel aux FontStrings abonnees, jamais lu nous-memes.
        -- Cache mis a jour inconditionnellement pour rattraper un abonnement qui arrive juste apres cet appel.
        if cdmAura then
            cdmAuraLastApplications[spellID] = cdmAura.applications
            local stackSubs = cdmAuraStackSubscribers[spellID]
            if stackSubs then
                for _, fs in pairs(stackSubs) do
                    PushStackApplications(spellID, fs, cdmAura.applications)
                end
            end
        end

        -- Auto-decouverte : tous les viewers CDM, filtree par SetAuraInstanceInfo (vraie aura uniquement).
        if name then pcall(AutoDiscoverSpell, spellID, name, unit, self, self.cooldownInfo and self.cooldownInfo.linkedSpellIDs) end

        -- Auto-correction : InitCDMHooks etiquette tout sort Essentiel/Utilitaire comme "debuff", faux pour
        -- les sorts qui s'octroient un buff a eux-memes (Rapidite de la nature...). Ce hook ne se declenche
        -- que sur une vraie instance d'aura : si unit=="player" pour un sort marque "debuff", on corrige.
        if unit == "player" then
            local spells = ns.GetSpecSpells()
            local info = spells and spells[spellID]
            if info and info.source == "debuff" then
                info.source = "buff"
            end
        end

        -- Applique le masking (basé sur la whitelist OU forcé pour BuffIcon/BuffBar)
        if maskableFrames[self] then
            MaskCDMFrame(self, ShouldMaskFrame(self, spellID))
        end

        -- Scan immediat : SetAuraInstanceInfo est le moment le plus tot ou les donnees sont disponibles,
        -- avant meme que UNIT_AURA soit dispatche. Coalesce sans timer via GetTime() (identique pour tous
        -- les appels du meme frame Blizzard) : au 2e appel du meme frame, skip. Plus rapide qu'un
        -- C_Timer.After(0) (pas d'attente du frame suivant), execute de facon synchrone.
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
    -- frame.Bar : uniquement présent sur les items de BuffBarCooldownViewer
    -- (viewer "Barres") -- cf. HookCDMBarChild pour le pourquoi (StatusBar,
    -- pas Cooldown, seul sink secret-safe pour un addon).
    if frame.Bar then
        HookCDMBarChild(frame.Bar, frame)
    end
    -- frame.ChargeCount.Current : FontString de charges sur Essential/Utility
    -- CooldownViewer (cf. HookCDMChargeCountChild plus haut).
    if frame.ChargeCount and frame.ChargeCount.Current then
        HookCDMChargeCountChild(frame.ChargeCount.Current, frame)
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

--- Etat des hooks CDM, pour les diagnostics externes (Debug.lua) : le pin
--- d'un sort ne sert a rien si le viewer qui doit l'afficher ne construit
--- jamais d'itemFrame (viewer desactive en Edit Mode) -- aucun
--- SetAuraInstanceInfo n'est alors emis et cdmData reste vide malgre un pin
--- parfaitement valide.

-- Presence par l'etat d'affichage des itemFrames "Buffs" du CDM : le seul canal combat-safe pour une
-- aura sans duree ni stacks, une fois GetPlayerAuraBySpellID/swipe/bar/cdmAuraInstancePresence tous en echec
-- (aucun d'eux ne redescend a la fin du buff). Les itemFrames BuffIcon/BuffBar, elles, ne s'affichent que
-- tant que le buff est actif et leur IsShown() reste lisible en combat (ni protegees ni secretes).
-- Restreint a BuffIcon/BuffBar via buffFrameAlwaysMask : sur Essentiel/Utilitaire l'icone reste affichee
-- en permanence (sort juste en recharge), donc IsShown ne prouve rien. nil = sort non epingle sur ce viewer.
-- Prerequis : sort epingle en TrackedBuff/TrackedBar ET viewer correspondant actif en Edit Mode.
local cdmBuffPresenceMemo, cdmBuffPresenceAt = {}, {}
-- TTL court car appele par combo a chaque scan (rafale d'UNIT_AURA en combat), balayage ~40 frames sinon trivial.
local CDM_BUFF_PRESENCE_TTL = 0.05

function ns.IsCDMBuffFramePresent(spellID)
    local at = cdmBuffPresenceAt[spellID]
    if at and (GetTime() - at) < CDM_BUFF_PRESENCE_TTL then
        return cdmBuffPresenceMemo[spellID]
    end
    local result
    for frame in pairs(hookedFrames) do
        if buffFrameAlwaysMask[frame] then
            local sid = GetCDMFrameSpellID(frame)
            if not sid then
                local okI, s = pcall(function()
                    local ci = frame.cooldownInfo
                    return ci and ci.spellID
                end)
                sid = okI and s or nil
            end
            if sid == spellID then
                local okSh, sh = pcall(function()
                    if frame:IsShown() then return true end
                    return false
                end)
                if okSh then
                    if sh then result = true; break end
                    result = false
                end
            end
        end
    end
    cdmBuffPresenceMemo[spellID] = result
    cdmBuffPresenceAt[spellID] = GetTime()
    return result
end

-- Diagnostic : /aacdm — dump l'etat complet de la chaine CDM -> cdmData ->
-- whitelist, pour identifier ou la chaine casse sans avoir a deviner.
SLASH_AACDM1 = "/aacdm"
SlashCmdList["AACDM"] = function()
    local P = "|cff33aaff[AACDM]|r "
    local function p(s) print(P .. s) end

    p(string.format("cdmHooked=%s  hookedFrames=%d  maskableFrames=%d",
        tostring(cdmHooked), (function() local n=0 for _ in pairs(hookedFrames) do n=n+1 end return n end)(),
        (function() local n=0 for _ in pairs(maskableFrames) do n=n+1 end return n end)()))
    p(string.format("Viewers Blizzard presents : Essential=%s Utility=%s BuffIcon=%s BuffBar=%s",
        tostring(EssentialCooldownViewer ~= nil), tostring(UtilityCooldownViewer ~= nil),
        tostring(BuffIconCooldownViewer ~= nil), tostring(BuffBarCooldownViewer ~= nil)))

    for _, unit in ipairs({"player", "target"}) do
        local u = cdmData[unit]
        local n, list = 0, {}
        if u then
            for spellID, entry in pairs(u) do
                n = n + 1
                if n <= 15 then tinsert(list, string.format("%d(%s)", spellID, tostring(entry.name))) end
            end
        end
        p(string.format("cdmData.%s : %d entree(s)%s", unit, n,
            n > 0 and (" -> " .. table.concat(list, ", ")) or ""))

        -- Replique manuellement CollectFromCDM (Scan.lua) entree par entree,
        -- pour voir EXACTEMENT laquelle des 2 etapes (keep / GetAuraDataByAuraInstanceID)
        -- fait disparaitre l'aura.
        if u then
            for spellID, entry in pairs(u) do
                local keep = (not ns.anyWhitelist) or (ns.anyWhitelist[spellID] == true)
                local dispOk, disp = false, nil
                if entry.instID and C_UnitAuras.GetAuraApplicationDisplayCount then
                    dispOk, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, entry.instID, 1, 999)
                end
                local durOk, dur = false, nil
                if entry.instID and C_UnitAuras.GetAuraDuration then
                    durOk, dur = pcall(C_UnitAuras.GetAuraDuration, unit, entry.instID)
                end
                local pabsOk, pabs = false, nil
                if unit == "player" and C_UnitAuras.GetPlayerAuraBySpellID then
                    pabsOk, pabs = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
                end
                p(string.format("  [%s] spellID=%d instID=%s keep=%s  DisplayCount: ok=%s val=%s  Duration: ok=%s val=%s  GetPlayerAuraBySpellID: ok=%s found=%s",
                    unit, spellID, tostring(entry.instID), tostring(keep),
                    tostring(dispOk), dispOk and tostring(disp) or tostring(disp),
                    tostring(durOk), durOk and tostring(dur ~= nil) or tostring(dur),
                    tostring(pabsOk), tostring(pabsOk and pabs ~= nil)))
            end
        end
    end

    -- Enumeration BRUTE (positionnelle, via C_UnitAuras.GetAuraDataByIndex) sans
    -- AUCUNE comparaison -- juste issecretvalue() par champ, pour voir ce qui
    -- est reellement lisible en combat sur les auras du joueur.
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        p("Enumeration brute HELPFUL (player), champ par champ :")
        local function fieldInfo(v)
            local isSecret = issecretvalue and issecretvalue(v)
            return string.format("%s(secret=%s)", tostring(v), tostring(isSecret))
        end
        for i = 1, 20 do
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if ok and not d then
                p(string.format("  #%d : fin de liste confirmee", i))
                break
            elseif not ok then
                p(string.format("  #%d : SECRETE a cette position (pas fin de liste, on continue)", i))
            else
                p(string.format("  #%d name=%s spellId=%s icon=%s applications=%s expirationTime=%s auraInstanceID=%s",
                    i, fieldInfo(d.name), fieldInfo(d.spellId), fieldInfo(d.icon),
                    fieldInfo(d.applications), fieldInfo(d.expirationTime), fieldInfo(d.auraInstanceID)))
            end
        end
    end

    p(string.format("Journal SetCooldown (CDM, %d entrees, plus recent en premier) :", #ns._cdmSetCooldownLog))
    for _, e in ipairs(ns._cdmSetCooldownLog) do
        p(string.format("  spellID=%d wasSetFromCooldown=%s isOnGCD=%s durOk=%s isLong(>1.5s)=%s il y a %.1fs",
            e.spellID, tostring(e.wasSetFromCooldown), tostring(e.isOnGCD),
            tostring(e.durOk), tostring(e.isLong), GetTime() - e.t))
    end

    p(string.format("_whitelistBuilt=%s  anyWhitelist présent=%s",
        tostring(ns._whitelistBuilt), tostring(ns.anyWhitelist ~= nil)))
    if ns.anyWhitelist then
        local spells = ns.GetSpecSpells and ns.GetSpecSpells()
        local names = {}
        for sid in pairs(ns.anyWhitelist) do
            local info = spells and spells[sid]
            tinsert(names, string.format("%d(%s)", sid, info and info.name or "?"))
        end
        p(string.format("anyWhitelist (%d) : %s", #names, table.concat(names, ", ")))
    end

    -- Ressources aura (Maelstrom Weapon / Icicles) : chaine ResourceMap.lua
    if _addon.AuraResources then
        for key, def in pairs(_addon.AuraResources) do
            local cdmEntry = cdmData.player and cdmData.player[def.spellID]
            p(string.format("AuraResources.%s (spellID=%d) : cdmData=%s  AuraStacks=%s  AuraText=%s",
                key, def.spellID, tostring(cdmEntry ~= nil and cdmEntry.instID),
                tostring(_addon.AuraStacks and _addon.AuraStacks[key]),
                tostring(_addon.AuraText and _addon.AuraText[key])))
            -- Sonde BRUTE : bypass toute notre logique, appelle l'API Blizzard
            -- directement pour voir EXACTEMENT ce qu'elle renvoie a l'instant T.
            local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, def.spellID)
            if not ok then
                p("  -> GetPlayerAuraBySpellID a leve une erreur (pcall ok=false)")
            elseif not auraData then
                p("  -> GetPlayerAuraBySpellID a renvoye nil (Blizzard dit : aura absente)")
            else
                local okApp, app = pcall(function() return auraData.applications end)
                local okInst, inst = pcall(function() return auraData.auraInstanceID end)
                p(string.format("  -> GetPlayerAuraBySpellID OK : applications=%s (issecret=%s)  auraInstanceID=%s (issecret=%s)",
                    tostring(okApp and app), tostring(okApp and issecretvalue and issecretvalue(app)),
                    tostring(okInst and inst), tostring(okInst and issecretvalue and issecretvalue(inst))))
            end
        end
    end

    -- Trace pas-a-pas du pipeline Scan : CollectPlayerBuffs/CollectAuras ->
    -- FilterAllDests, pour voir exactement ou une aura connue de cdmData
    -- disparait avant d'atteindre les renders.
    if ns.Scan then
        local playerAuras = ns.Scan:CollectPlayerBuffs()
        p(string.format("Scan:CollectPlayerBuffs() : %d entree(s)%s", #playerAuras,
            #playerAuras > 0 and (" -> spellIDs: " .. table.concat((function()
                local t = {} for _, e in ipairs(playerAuras) do tinsert(t, tostring(e.spellID)) end return t
            end)(), ", ")) or ""))

        local targetAuras = {}
        if UnitExists("target") then targetAuras = ns.Scan:CollectAuras("target") end
        p(string.format("Scan:CollectAuras('target') : %d entree(s)%s", #targetAuras,
            #targetAuras > 0 and (" -> spellIDs: " .. table.concat((function()
                local t = {} for _, e in ipairs(targetAuras) do tinsert(t, tostring(e.spellID)) end return t
            end)(), ", ")) or ""))

        local allIn = {}
        for _, e in ipairs(targetAuras) do tinsert(allIn, e) end
        for _, e in ipairs(playerAuras) do tinsert(allIn, e) end
        local sA, fA, iA, bA, rA = ns.Scan:FilterAllDests(allIn)
        p(string.format("FilterAllDests -> iconlist=%d circlebars=%d icons=%d freebars=%d centerArc=%d",
            #sA, #fA, #iA, #bA, #rA))

        p(string.format("whitelistByDest presents : iconlist=%s circlebars=%s icons=%s freebars=%s centerArc=%s",
            tostring(ns.whitelistByDest and ns.whitelistByDest.iconlist ~= nil),
            tostring(ns.whitelistByDest and ns.whitelistByDest.circlebars ~= nil),
            tostring(ns.whitelistByDest and ns.whitelistByDest.icons ~= nil),
            tostring(ns.whitelistByDest and ns.whitelistByDest.freebars ~= nil),
            tostring(ns.whitelistByDest and ns.whitelistByDest.centerArc ~= nil)))
        p(string.format("slotOrderByDest counts : iconlist=%s circlebars=%s icons=%s freebars=%s centerArc=%s",
            tostring(ns.slotOrderByDest and ns.slotOrderByDest.iconlist and #ns.slotOrderByDest.iconlist),
            tostring(ns.slotOrderByDest and ns.slotOrderByDest.circlebars and #ns.slotOrderByDest.circlebars),
            tostring(ns.slotOrderByDest and ns.slotOrderByDest.icons and #ns.slotOrderByDest.icons),
            tostring(ns.slotOrderByDest and ns.slotOrderByDest.freebars and #ns.slotOrderByDest.freebars),
            tostring(ns.slotOrderByDest and ns.slotOrderByDest.centerArc and #ns.slotOrderByDest.centerArc)))

        p(string.format("db.enabled=%s  db.useNativeCDM=%s  ns.auraData present=%s",
            tostring(ns.db and ns.db.enabled), tostring(ns.db and ns.db.useNativeCDM),
            tostring(ns.auraData ~= nil)))
        if ns.auraData then
            for _, dest in ipairs({"iconlist","circlebars","icons","freebars","centerArc"}) do
                local list = ns.auraData[dest]
                p(string.format("  ns.auraData.%s = %d entree(s)", dest, list and #list or 0))
            end
        end
    end
end

-- Diagnostic : /aacbar — dump la structure (enfants + régions) des items
-- actuellement affichés sur BuffBarCooldownViewer, et l'état du canal
-- clone-bar (spellID, présence, abonnés) pour un spellID donné.
-- Usage : /aacbar [spellID]
SLASH_AACBAR1 = "/aacbar"
SlashCmdList["AACBAR"] = function(msg)
    local P = "|cff33aaff[AACBAR]|r "
    local function p(s) print(P .. s) end
    local wantSpellID = tonumber((msg or ""):match("%d+"))

    if not BuffBarCooldownViewer then
        p("BuffBarCooldownViewer introuvable.")
        return
    end

    local function dumpRegion(prefix, region)
        if not region then return end
        local ok, objType = pcall(region.GetObjectType, region)
        p(string.format("%s type=%s SetValue=%s SetCooldown=%s SetMinMaxValues=%s",
            prefix, ok and objType or "?", tostring(region.SetValue ~= nil),
            tostring(region.SetCooldown ~= nil), tostring(region.SetMinMaxValues ~= nil)))
    end

    local found = 0
    for _, frame in pairs({ BuffBarCooldownViewer:GetChildren() }) do
        if frame.IsShown and frame:IsShown() and frame.cooldownInfo then
            local spellID = GetCDMFrameSpellID(frame)
            found = found + 1
            p(string.format("--- Item actif : spellID=%s ---", tostring(spellID)))
            dumpRegion("  frame.Cooldown", frame.Cooldown)
            dumpRegion("  frame.Bar", frame.Bar)
            if spellID then
                local subs = cdmAuraBarSubscribers[spellID]
                local n = 0
                if subs then for _ in pairs(subs) do n = n + 1 end end
                p(string.format("  canal clone-bar : present=%s abonnes=%d",
                    tostring(ns.IsCDMAuraBarPresent(spellID)), n))
            end
        end
    end
    if found == 0 then
        p("Aucun item actif trouve sur BuffBarCooldownViewer (verifie qu'un sort y est bien epingle et actif via Edit Mode).")
    end
    if wantSpellID then
        local subs = cdmAuraBarSubscribers[wantSpellID]
        local n = 0
        if subs then for _ in pairs(subs) do n = n + 1 end end
        p(string.format("spellID=%d : present=%s abonnes=%d", wantSpellID, tostring(ns.IsCDMAuraBarPresent(wantSpellID)), n))
    end
end

-- Seul BuffBarCooldownViewer construit ses items avec une vraie StatusBar ; Essential/Utility/BuffIcon sont
-- tous structurellement Cooldown-only. La contrainte "epingler sur Barres" pour une duree combat-safe
-- vient donc de Blizzard (un seul des 4 viewers a le bon widget), pas d'une limite de notre cote.

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

-- Scan proactif des viewers CDM : decouvre tous les sorts que le CDM tracke pour la spec courante sans
-- attendre le combat (PLAYER_ENTERING_WORLD, PLAYER_SPECIALIZATION_CHANGED, apres InitCDMHooks).
-- 3 methodes complementaires, du plus precis au plus large : (1) C_CooldownViewer.GetCooldownViewerCategorySet
-- couvre TrackedBuff/TrackedBar meme inactifs ; (2) iteration directe des frames de chaque viewer couvre
-- Essential/Utility (debuffs) et les frames actives des buff viewers ; (3) CooldownViewerSettings DataProvider
-- liste exhaustivement tout le reste (source "player" par defaut, reclassifie a l'apparition en combat).
-- Retourne true si instID indique une aura active : non-nil = presente, y compris une secret value
-- (TWW protege les IDs en combat mais ne les met jamais a nil pour une frame CD-only).
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
    -- Source principale : liste statique CDM (existe hors combat, autoritaire pour la spec).
    -- TrackedBuff = icones (BuffIconCooldownViewer), TrackedBar = barres (BuffBarCooldownViewer).
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
                        if name then pcall(AutoDiscoverSpell, sid, name, unit, nil, lids) end
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
                        local sid, lids = GetScanSpellID(frame)
                        if not sid then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, def.unit, frame, lids) end
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
                        local sid, lids = GetScanSpellID(frame)
                        if not sid then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, def.unit, frame, lids) end
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
                        local sid, lids
                        if itemFrame.GetBaseSpellID then
                            local ok, s = pcall(itemFrame.GetBaseSpellID, itemFrame)
                            if ok and type(s) == "number" and s > 0 then sid = s end
                        end
                        if not sid then sid, lids = GetScanSpellID(itemFrame) end
                        if not sid then return end
                        local name = GetSpellName and GetSpellName(sid)
                        if name then pcall(AutoDiscoverSpell, sid, name, def.unit, itemFrame, lids) end
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

-- Auto-epinglage CDM (experimental) : ce pipeline exige qu'un sort soit epingle manuellement dans le
-- Cooldown Manager natif (Edit Mode), sinon aucune frame/icone/barre. Epingler 40 specs a la main n'est pas
-- praticable, donc on appelle le mixin interne NON documente de CooldownViewerSettings (pas l'API publique
-- en lecture seule) -- risque de casse a un futur patch.
-- SetCooldownToCategory tainte tout Blizzard_CooldownViewer quelle que soit la variante d'appel (crash
-- ADDON_ACTION_BLOCKED au prochain combat). Mitigation : ReloadUI() immediatement apres toute mutation
-- reussie, avant tout combat dans cette session, pour repartir d'une VM propre (seul SaveLayouts traverse
-- le reload). NE PAS retirer ce ReloadUI() sans un moyen equivalent de garantir une VM propre avant combat.
-- Sequence (cf. SetSpellCDMCategory + SaveCDMLayoutMinimal) : (1) trouver le cooldownID via
-- GetCooldownViewerCategorySet(cat, includeDisabled=true) pour aussi voir les sorts pas encore epingles ;
-- (2) SetCooldownToCategory(id, cat) ; (3) GetLayoutManager():SaveLayouts() sans passer par
-- RefreshLayout()/SaveCurrentLayout() (le wrapper panneau qui propage le taint plus largement).
-- Coupe-circuit : PinAuraToCDM/SyncCDMPins renvoient ceci et ne touchent
-- JAMAIS SetCooldownToCategory tant que cette chaine n'est pas vide.
local CDM_PIN_DISABLED_REASON = ""

-- UNIQUEMENT les 2 categories AURAS (Ameliorations : Icones + Barres).
-- Essential/Utility = temps de recharge de SORTS (ce que le joueur lance),
-- pas des auras -- jamais touches par l'auto-epinglage : on ne veut pas
-- reclassifier un cooldown de sort en aura, meme si son spellID matche
-- par coincidence celui d'une entree whitelist.
local CDM_PIN_CATEGORIES = {
    Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff,
    Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar,
}

-- Lookup rapide "categorie autorisee", utilise comme verrou sur info.category (classification statique
-- de Blizzard, jamais affectee par un SetCooldownToCategory anterieur) pour confirmer qu'un cooldownID
-- est structurellement une aura, meme si quelqu'un l'a deja bascule ailleurs par erreur.
local AURA_CATEGORY_SET = {}
for _, cat in ipairs(CDM_PIN_CATEGORIES) do
    if cat then AURA_CATEGORY_SET[cat] = true end
end

-- Retrouve le cooldownID Blizzard pour spellID (epingle ou non), en parcourant uniquement les categories
-- auras. Nil si Blizzard ne connait pas ce sort comme aura pour la spec active. Verifie aussi info.category
-- (classement reel de ce cooldownID precis, jamais Essential/Utility) car certaines auras partagent leur
-- spellID avec le sort qui les applique -- ignore un cooldownID qui est en realite un cooldown de sort.
local function FindCooldownIDForSpell(spellID)
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
            and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
        return nil
    end
    for _, cat in ipairs(CDM_PIN_CATEGORIES) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
        if ok and type(ids) == "table" then
            for _, cooldownID in ipairs(ids) do
                local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if okInfo and info and AURA_CATEGORY_SET[info.category] then
                    local lids = info.linkedSpellIDs
                    local sid = (type(lids) == "table" and lids[1])
                                or info.overrideTooltipSpellID or info.linkedSpellID
                                or info.overrideSpellID or info.spellID
                    if sid == spellID then return cooldownID end
                end
            end
        end
    end
    return nil
end

-- Coeur de la mutation, sans RefreshLayout/SaveCurrentLayout (couteux, applique une seule fois a la fin
-- d'un lot par SyncCDMPins plutot qu'a chaque sort). Retourne (success, message).
local function SetSpellCDMCategory(spellID, asBar)
    if CDM_PIN_DISABLED_REASON ~= "" then return false, CDM_PIN_DISABLED_REASON end
    if not spellID then return false, "spellID manquant" end
    if not (Enum.CooldownViewerCategory and Enum.CooldownLayoutStatus
            and CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then
        return false, "API CooldownViewerSettings indisponible (patch ?)"
    end

    local cooldownID = FindCooldownIDForSpell(spellID)
    if not cooldownID then
        return false, "sort inconnu du CDM pour cette spec (jamais vu cote client ?)"
    end

    local targetCategory = (asBar ~= false) and Enum.CooldownViewerCategory.TrackedBar
                                              or Enum.CooldownViewerCategory.TrackedBuff

    local okProvider, dataProvider = pcall(CooldownViewerSettings.GetDataProvider, CooldownViewerSettings)
    if not okProvider or not dataProvider then
        return false, "GetDataProvider indisponible"
    end

    local okSet, status = pcall(dataProvider.SetCooldownToCategory, dataProvider, cooldownID, targetCategory)
    if not okSet then
        return false, "SetCooldownToCategory a plante (API changee ?)"
    end
    if status ~= Enum.CooldownLayoutStatus.Success then
        return false, "refuse par Blizzard (status=" .. tostring(status) .. ", ce sort n'accepte peut-etre pas ce type d'affichage)"
    end

    return true, "epingle (cooldownID=" .. tostring(cooldownID) .. ")", dataProvider
end

-- Persiste au plus bas niveau (SaveLayouts, jamais RefreshLayout/SaveCurrentLayout, inutile vu le
-- ReloadUI() force juste apres par les appelants).
local function SaveCDMLayoutMinimal(dataProvider)
    local okLM, layoutManager = pcall(dataProvider.GetLayoutManager, dataProvider)
    if okLM and layoutManager then
        pcall(layoutManager.SaveLayouts, layoutManager)
    end
end

-- Popup de confirmation : pas de ReloadUI() automatique (surprendrait l'utilisateur en pleine action),
-- on propose un reload et l'utilisateur choisit le moment.
StaticPopupDialogs["AISH_CDM_RELOAD"] = {
    text = L["CDM_RELOAD_PROMPT"],
    button1 = RELOADUI,
    button2 = L["CDM_RELOAD_LATER"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Compteur de sorts epingles depuis le dernier reload, pas encore acquitte par une reponse au popup
-- (permet de re-proposer plus tard sans perdre le compte si l'utilisateur a clique "Plus tard").
local pendingCDMReloadCount = 0

-- Historique des appels a MarkCDMReloadPending, pour identifier la source d'un popup inattendu (/aishdebug cdmreload).
ns._cdmReloadMarkLog = ns._cdmReloadMarkLog or {}

function ns.MarkCDMReloadPending(count)
    pendingCDMReloadCount = pendingCDMReloadCount + (count or 1)
    local src = debugstack and debugstack(2, 1, 0) or "?"
    table.insert(ns._cdmReloadMarkLog, 1, { count = count or 1, total = pendingCDMReloadCount, src = src, t = GetTime() })
    for i = #ns._cdmReloadMarkLog, 11, -1 do ns._cdmReloadMarkLog[i] = nil end
end

function ns.GetCDMReloadPendingCount()
    return pendingCDMReloadCount
end

-- Compte au dernier affichage du popup. pendingCDMReloadCount ne redescend jamais a zero seul (design :
-- ne pas perdre le compte si "Plus tard" est clique), donc sans ce garde le popup reviendrait a chaque
-- fermeture du GUI meme sans nouveau sort epingle. On ne re-affiche que si le compte a reellement augmente.
local lastPromptedCDMReloadCount = 0

-- Affiche le popup si quelque chose est en attente et pas deja visible. Seul un ReloadUI() effectif
-- (ou un reload manuel, cf. redeclaration au chargement du fichier) remet pendingCDMReloadCount a zero.
function ns.PromptCDMReloadIfPending()
    if pendingCDMReloadCount <= 0 then return end
    if pendingCDMReloadCount <= lastPromptedCDMReloadCount then return end
    if StaticPopup_Visible and StaticPopup_Visible("AISH_CDM_RELOAD") then return end
    lastPromptedCDMReloadCount = pendingCDMReloadCount
    StaticPopup_Show("AISH_CDM_RELOAD", pendingCDMReloadCount)
end

-- Epingle spellID dans le viewer "Barres" (TrackedBar) ou "Icones" (TrackedBuff) si asBar=false.
-- Marque juste un reload comme necessaire en cas de succes ; l'appelant decide quand proposer le popup.
function ns.PinAuraToCDM(spellID, asBar)
    if CDM_PIN_DISABLED_REASON ~= "" then return false, CDM_PIN_DISABLED_REASON end
    if InCombatLockdown and InCombatLockdown() then
        return false, "refuse en combat (modification Edit Mode)"
    end
    local ok, msg, dataProvider = SetSpellCDMCategory(spellID, asBar)
    if ok then
        SaveCDMLayoutMinimal(dataProvider)
        ns.MarkCDMReloadPending(1)
    end
    return ok, msg
end

-- Ensemble des spellID deja suivis en Barres (TrackedBar, actifs seulement), pour ne pas retoucher un sort
-- deja au bon endroit. N'epargne pas un sort suivi en Icones/Essentiel/Utilitaire : seul TrackedBar accepte
-- le forward de valeurs secretes en combat, un sort suivi ailleurs doit donc etre bascule en Barres aussi.
local function GetAlreadyBarTrackedSpellSet()
    local set = {}
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
            and C_CooldownViewer.GetCooldownViewerCooldownInfo and Enum.CooldownViewerCategory) then
        return set
    end
    local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, Enum.CooldownViewerCategory.TrackedBar, false)
    if ok and type(ids) == "table" then
        for _, cooldownID in ipairs(ids) do
            local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
            if okInfo and info then
                local lids = info.linkedSpellIDs
                local sid = (type(lids) == "table" and lids[1])
                            or info.overrideTooltipSpellID or info.linkedSpellID
                            or info.overrideSpellID or info.spellID
                if type(sid) == "number" then set[sid] = true end
            end
        end
    end
    return set
end

-- Sorts pour lesquels SetCooldownToCategory a reussi cette session : GetAlreadyBarTrackedSpellSet()
-- interroge l'etat live du CDM, qui ne reflete l'assignation qu'apres le /reload propose par le popup.
-- Sans ce cache, chaque rebuild de whitelist avant ce reload repinnerait (idempotent mais "succes") et
-- redeclencherait le popup sans cesse. Session-only : se re-decouvre au prochain reload.
local pinnedThisSession = {}

-- Parcourt la whitelist de la spec active et epingle en Barres tout spellID actif pas deja en Barres cote
-- CDM natif (meme deja suivi en Icones, cf. GetAlreadyBarTrackedSpellSet). Ne touche jamais Essential/
-- Utility. Marque un reload comme necessaire si au moins un sort a ete epingle.
function ns.SyncCDMPins()
    if CDM_PIN_DISABLED_REASON ~= "" then return false, CDM_PIN_DISABLED_REASON end
    if InCombatLockdown and InCombatLockdown() then
        return false, "refuse en combat (modification Edit Mode)"
    end
    if not ns.GetSpecSpells then
        return false, "ns.GetSpecSpells introuvable"
    end
    local spells = ns.GetSpecSpells()
    if not spells then
        return false, "aucune whitelist pour cette spec"
    end

    local alreadyBarTracked = GetAlreadyBarTrackedSpellSet()
    local pinned, skipped, failures = 0, 0, {}
    local lastDataProvider
    for id, info in pairs(spells) do
        if info.enabled and not info._invalid and not alreadyBarTracked[id] and not pinnedThisSession[id] then
            local ok, msg, dataProvider = SetSpellCDMCategory(id, true)
            if not ok then
                -- Repli Icones : un refus en Barres survient typiquement pour un sort sans duree/minuteur
                -- (rien a animer sur une StatusBar) ; sans ce repli le sort serait invisible du pipeline
                -- AishCore (100% CDM-only) quel que soit le mode d'affichage choisi.
                local ok2, msg2, dataProvider2 = SetSpellCDMCategory(id, false)
                if ok2 then
                    ok, msg, dataProvider = ok2, msg2, dataProvider2
                end
            end
            if ok then
                pinned = pinned + 1
                lastDataProvider = dataProvider
                pinnedThisSession[id] = true
            else
                skipped = skipped + 1
                failures[#failures + 1] = tostring(id) .. ": " .. tostring(msg)
            end
        end
    end

    -- Une seule sauvegarde pour tout le lot, pas une par sort.
    if pinned > 0 and lastDataProvider then
        SaveCDMLayoutMinimal(lastDataProvider)
        ns.MarkCDMReloadPending(pinned)
    end

    return true, pinned, skipped, failures
end


-- AishUIAura/Core/CDMHooks.lua
-- Hooks du Cooldown Manager de Blizzard : parse les spell IDs, hooke les frames
-- BuffIcon/BuffBar, applique le masking (SetAlpha(0) uniquement — JAMAIS
-- SetScale, ce qui tue le CDM au 2ème combat)
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

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

-- PRESENCE PURE : [unit][spellID] = true/false, alimentee EXCLUSIVEMENT par
-- le hook SetAuraInstanceInfo ci-dessous (jamais purgee comme cdmData, jamais
-- dependante d'un mecanisme de stacks ou d'un swipe de duree comme
-- cdmAuraSwipePresence/cdmData). Necessaire pour Rapidite de la nature/378081 :
-- un buff sans VRAIE duree (dure "jusqu'au prochain cast") ni stacks, pour
-- lequel la chaine de detection habituelle echoue simultanement en combat
-- (GetAuraApplicationDisplayCount->nil, GetPlayerAuraBySpellID->nil,
-- enumeration HELPFUL -> d.spellId secret des qu'en combat) -- et pour lequel
-- Cooldown:SetCooldown n'est jamais appele (rien a animer sans duree), donc
-- cdmAuraSwipePresence (CDMHooks.lua tiers 4/5) ne se peuple jamais non plus.
-- SetAuraInstanceInfo, lui, se declenche des que Blizzard lie/delie une VRAIE
-- instance d'aura a l'icone -- avec ou sans duree/stacks, c'est le seul
-- signal de ce type qui existe pour ce cas.
local cdmAuraInstancePresence = { player = {}, target = {} }
ns.cdmAuraInstancePresence = cdmAuraInstancePresence

-- true/false = presence confirmee par SetAuraInstanceInfo ; nil = jamais
-- observe pour ce spellID sur cet unit (spell jamais assigne a une icone
-- CDM Essentiel/Utilitaire, ou pas encore).
--
-- Ce tier ne s'efface jamais tout seul : seul un demarrage de CD le fait, et
-- uniquement pour les sorts sans swipe (cf. plus bas). Le rendre autoritaire
-- pour un sort qui a par ailleurs un vrai swipe de duree (cdmAuraSwipePresence
-- non-nil) le bloquerait a "true" pour toujours des la 1ere activation,
-- court-circuitant l'ancienne chaine cdmData/swipe qui gere deja correctement
-- la fin de ces sorts. Restreint donc aux sorts qui n'ont aucun autre signal
-- de duree -- exactement le meme garde que celui applique cote effacement
-- (HookCDMCooldownChild, plus bas dans ce fichier).
-- La valeur est un nombre (GetTime() du dernier "vu" reel) ou `false` (jamais
-- vu de VRAIE presence sur ce canal -- nil au depart, ou false pose par un
-- Clear() qui n'a jamais ete precede d'un vrai signal). Un simple `~= nil`
-- sur cdmAuraSwipePresence/cdmAuraBarPresence traiterait ce `false` de depart
-- comme "canal fiable ici" et bloquerait ce tier a tort.
local function HasEverConfirmedPresence(t, spellID)
    return type(t[spellID]) == "number"
end

-- Meme avec le garde double-canal ci-dessus, ce tier n'a aucune expiration
-- propre -- pour un sort qui n'est PAS "banked" (le CD demarre normalement au
-- cast, pas a la perte du buff), une simple course au demarrage
-- (SetAuraInstanceInfo arrive avant le tout premier SetValue du canal barre,
-- sur un /reload frais) suffit a le rendre autoritaire, et rien ne le repasse
-- jamais a false ensuite si ce sort n'a pas la mecanique "CD demarre a la
-- consommation du buff". Restreint donc a une liste explicite de sorts
-- "banked" confirmes (dure "jusqu'au prochain cast", CD demarre a la
-- consommation, jamais au cast).
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

-- Données de CHARGES event-driven : alimentées par un hook SetText
-- sur itemFrame.ChargeCount.Current (FontString), le même widget que
-- PriorityBar.ScanCooldownViewer lit déjà par polling toutes les 0.15s via
-- GetText(). Ici on capture la même valeur (via GetText() dans le hook, PAS
-- en lisant l'argument SetText -- même prudence que le reste du fichier) mais
-- au moment exact où Blizzard l'écrit, sans lag de poll ni trou si l'itemFrame
-- n'était pas actif au tick de scan. Structure : cdmChargeData[spellID] = "2"
-- (texte brut du FontString Blizzard, jamais un nombre -- comparaison sûre
-- uniquement via tonumber/pcall côté consommateur).
-- Additif uniquement : ne remplace aucun mécanisme existant, PriorityBar garde
-- son fallback poll+estimation intact (kill-switch CDM_CHARGE_HOOK_ENABLED).
local cdmChargeData = {}
ns.cdmChargeData = cdmChargeData

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
-- 2e valeur de retour (lids) : la table linkedSpellIDs brute, si presente --
-- utilisee par AutoDiscoverSpell pour regrouper les variantes de rang/stacks
-- d'un meme buff (ex: Precurseur du Vide 1256301/1256302, cf. Whitelist.lua).
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

------------------------------------------------------------------------
-- ABONNEMENTS "CLONE SWIPE" GÉNÉRIQUES POUR LA DURÉE DES AURAS
--
-- Distinct de cdmCooldownSubscribers ci-dessus (réservé aux cooldowns de
-- sort, wasSetFromCooldown=true+!isOnGCD, utilisé par PriorityBar.lua).
-- Confirmé en jeu (patch 12.1) : C_UnitAuras (GetPlayerAuraBySpellID,
-- GetAuraDataByIndex, GetAuraDuration, GetAuraApplicationDisplayCount...)
-- refuse systématiquement l'accès aux auras à durée limitée pendant le
-- combat, quelle que soit la méthode utilisée -- AUCUNE de ces API ne peut
-- donc alimenter notre pipeline en combat. Mais le CDM (code Blizzard non
-- tainté) continue d'appeler Cooldown:SetCooldown(start, duration) sur ses
-- propres frames pour AFFICHER ces mêmes auras -- avec wasSetFromCooldown=
-- false pour les mises à jour de durée de buff (confirmé en jeu : les mêmes
-- spellID que nos auras trackées apparaissent dans ce flux). En hooksecurefunc,
-- on REÇOIT ces arguments (secrets ou non, peu importe) et on peut les
-- RETRANSMETTRE tels quels à un widget Cooldown à nous -- jamais les lire,
-- jamais les comparer, donc jamais soumis à la restriction "secret". C'est
-- le même mécanisme "show but don't know" déjà éprouvé par
-- cdmCooldownSubscribers, juste sans le filtre wasSetFromCooldown/isOnGCD
-- (qui exclurait justement les buffs qu'on veut capter ici).
--
-- Ce canal sert AUSSI de source de vivacité : Blizzard n'affiche un item
-- CDM que si l'aura est réellement active, donc un SetCooldown reçu ici
-- signifie "cette aura est présente MAINTENANT" et un Clear() signifie
-- "elle vient de disparaître" -- sans jamais interroger C_UnitAuras.
--
-- ns.cdmAuraSwipePresence[spellID] stocke un TIMESTAMP (GetTime()), pas un
-- simple booléen : les frames CDM sont recyclées/pooled par Blizzard, et
-- rien ne garantit qu'un Clear() explicite soit toujours appelé sur
-- l'ancien spellID avant que la frame ne soit réaffectée à un autre buff
-- (confirmé en jeu : un flag booléen restait bloqué à "présent" pour une
-- aura déjà expirée -- bug observé sur le mode Barres Libres). En exposant
-- un timestamp, ns.IsCDMAuraSwipePresent() ci-dessous peut considérer une
-- entrée comme périmée si elle n'a pas été rafraîchie récemment, sans
-- dépendre uniquement du Clear() -- auto-réparateur.
--
-- ATTENTION (confirmé en jeu) : Blizzard n'appelle PAS SetCooldown en
-- continu pour une aura toujours active -- un seul appel au démarrage/
-- refresh suffit, le widget anime le swipe ensuite tout seul côté C++. Un
-- seuil de péremption trop court (essayé : 3s) fait donc disparaître à
-- tort des auras encore actives depuis plus longtemps que ce seuil, qui
-- réapparaissent seulement au refresh suivant -- clignotement aléatoire
-- observé en jeu. Le seuil ne doit servir QUE de filet de sécurité contre
-- une frame orpheline (jamais Clear()-ée), pas comme mécanisme normal de
-- détection de fin de vie -- d'où une valeur large.
------------------------------------------------------------------------
local cdmAuraSwipeSubscribers = {}  -- [spellID][key] = cdFrame (widget Cooldown abonné)
ns.cdmAuraSwipePresence = ns.cdmAuraSwipePresence or {}  -- [spellID] = GetTime() du dernier SetCooldown vu, ou false apres un Clear()
local CDM_AURA_SWIPE_STALE_AFTER = 900  -- 15 min : filet de securite uniquement, pas une detection normale
-- Seuil beaucoup plus court pour le canal BAR (BuffBarCooldownViewer) :
-- contrairement au Cooldown/swipe (un seul SetCooldown au demarrage, anime
-- ensuite cote C++ SANS rappel Lua -- d'ou le seuil large ci-dessus, deja
-- ajuste apres un essai a 3s qui masquait a tort des auras encore actives),
-- Blizzard rappelle SetMinMaxValues/SetValue sur la StatusBar toutes les
-- 1-2s pour une aura reellement active (confirme en jeu, /aacbar). Le bar
-- n'a pas d'equivalent Clear() -- son seul signal d'expiration est hi=0
-- (non-secret a cet instant, cf. HookCDMBarChild), qui n'est apparemment pas
-- systematiquement envoye pour tous les types de buffs (confirme en jeu :
-- Mur Protecteur restait "present" -- via ce canal -- bien apres sa vraie
-- fin, capacite associee a wasSetFromCooldown=true donc filtree du canal
-- swipe). Un seuil court ici est sur : une aura active recoit des rappels
-- frequents, un delai de peremption de quelques secondes ne peut donc pas la
-- faire disparaitre a tort (contrairement au Cooldown/swipe).
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

------------------------------------------------------------------------
-- ABONNEMENTS "CLONE BAR" POUR LA DURÉE (StatusBar, PAS Cooldown)
--
-- Cooldown:SetCooldown() rejette
-- catégoriquement toute valeur secrète venant de code addon ("Secret values
-- are only allowed during untainted execution for this argument") -- le
-- canal clone-swipe ci-dessus ne peut donc JAMAIS relayer une vraie durée en
-- combat, quelle que soit la méthode (voir commentaire détaillé plus bas sur
-- HookCDMCooldownChild). MAIS StatusBar:SetValue()/SetMinMaxValues()
-- ACCEPTENT un forward secret venant d'un addon (confirmé par la doc
-- officielle ET empiriquement : pcall ok=true en combat) -- c'est exactement
-- le sink déjà utilisé avec succès par ResourceCircle.SetCenterArcFill/
-- UpdateSecondaryResource pour l'absorb de Dur Au Mal.
--
-- BuffBarCooldownViewer (viewer "Barres" de l'Edit Mode, distinct de
-- BuffIconCooldownViewer) construit son remplissage avec une VRAIE StatusBar
-- (frame.Bar) -- alors que TOUS les autres viewers (Essential/Utility/
-- BuffIcon) utilisent un Cooldown (frame.Cooldown). On clone donc les appels
-- SetMinMaxValues(lo, hi)/SetValue(value) que Blizzard fait sur frame.Bar
-- vers un widget StatusBar à nous, exactement comme le clone-swipe le fait
-- pour un Cooldown -- sauf que celui-ci, lui, fonctionne réellement en
-- combat.
--
-- CONTRAINTE : ne fonctionne que pour un sort épinglé sur le viewer "Barres"
-- du Cooldown Manager Blizzard (Edit Mode) -- BuffBarCooldownViewer ne
-- construit une frame.Bar que pour les items qu'il affiche réellement.
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- ABONNEMENTS "CLONE STACK" POUR LES COMPTEURS D'APPLICATIONS (STACKS)
--
-- Meme principe que cdmAuraSwipeSubscribers ci-dessus, applique aux stacks
-- plutot qu'a la duree. SetAuraInstanceInfo(self, cdmAura) recoit cdmAura
-- (l'AuraData que Blizzard vient d'assigner a cette frame CDM), potentiellement
-- secrete en combat. cdmAura.applications est le champ standard AuraData pour
-- le compteur de stacks. On le RETRANSMET tel quel a un FontString a nous via
-- SetText -- jamais lu, jamais compare -- exactement le meme mecanisme "show
-- but don't know" que le clone swipe de duree. SetText accepte une valeur
-- secrete brute sans la reveler a notre code (meme sink que SetCooldown).
--
-- Pour les auras du JOUEUR, Debuffs.lua/ApplyStackCharges utilise desormais
-- ResourceCircle.ApplyStacksTo (CDM + GetPlayerAuraBySpellID + enumeration,
-- avec IsConfirmedZero) plutot que ce canal -- capable de confirmer un 0/1
-- et de cacher franchement, ce que ce forward brut ne peut jamais faire
-- (voir plus bas : la comparaison, meme sur tostring(applications), plante
-- systematiquement en combat). Ce canal reste la SEULE source pour les
-- auras de la CIBLE (pas d'equivalent GetPlayerAuraBySpellID cote cible).
------------------------------------------------------------------------
local cdmAuraStackSubscribers = {}  -- [spellID][key] = FontString abonne
-- Derniere valeur vue par spellID (VALEUR de table, secrete ou non -- jamais
-- comparee ni lue, juste retransmise). Alimentee sur CHAQUE SetAuraInstanceInfo,
-- avec ou sans abonne : permet de rattraper un abonnement qui arrive juste
-- APRES le SetAuraInstanceInfo qui a declenche le scan (cas frequent : ce
-- meme SetAuraInstanceInfo est ce qui a fait apparaitre l'aura et declenche
-- ApplyCDMStackSwipe/ApplyAura -- sans ce cache, le tout premier abonnement
-- raterait le forward et resterait vide jusqu'au refresh CDM suivant).
local cdmAuraLastApplications = {}  -- [spellID] = derniere valeur applications vue

-- applications est TOUJOURS secrete en combat
-- (meme quand la valeur reelle est 0) -- une comparaison numerique directe
-- (applications <= 1) echoue systematiquement ("attempt to compare a secret
-- number value"). tostring(applications) REUSSIT et permet d'afficher "0" en
-- clair via print/SetText (sink de lecture/affichage legal) -- MAIS la chaine
-- resultante RESTE ELLE-MEME secrete : la comparer avec == (meme "str == '0'")
-- plante EXACTEMENT pareil ("attempt to compare a secret string value") si ce
-- n'est pas protege par un pcall SEPARE. Comparer `str == "0"` en dehors d'un
-- pcall plante silencieusement (erreur Lua masquee, WoW ne l'affiche pas par
-- defaut) sur CHAQUE appel, empechant meme la branche SetText/Show (plus bas)
-- de s'executer. Il faut pcall la CONVERSION *et* la COMPARAISON separement.
-- AUTO-APPRENTISSAGE : contrairement a la duree, aucune comparaison sur
-- "applications" (brut OU sa representation texte) ne peut JAMAIS confirmer
-- un 0 en combat. Pour les sorts SANS vrai mecanisme de stacks (Mur
-- Protecteur, Rage du Berserker...), ce canal affichait donc parfois un "0"
-- faute de pouvoir savoir.
-- Approche retenue (fail-open + apprentissage negatif) : affiche par defaut
-- des la 1ere aura vue (comme le clone swipe de duree), et ne cache
-- durablement QUE les spellID explicitement confirmes "jamais > 1" HORS
-- COMBAT (ns.MarkStackNotCapable, cf. ApplyStackCharges dans Debuffs.lua) --
-- une confirmation hors combat reflete un etat stabilise (pas "pas encore
-- monte en stacks"), contrairement a une lecture propre en plein combat qui
-- pourrait juste tomber pile au moment de l'application initiale. Toute
-- confirmation ulterieure > 1 (ns.MarkStackCapable) leve immediatement ce
-- verdict negatif, donc une aura mal classee se corrige d'elle-meme des
-- qu'elle stack reellement. Une approche fail-closed (n'afficher que les
-- spellID deja confirmes >1) a ete ecartee : une vraie aura a stacks qui
-- n'existe QU'en combat (debuff de boss, proc de tank...) n'a alors jamais
-- l'occasion d'etre confirmee, et son badge reste cache pour toujours.
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

-- NOTE : un canal "clone durObj" (SetCooldownFromDurationObject ->
-- StatusBar:SetTimerDuration) a ete tente ici pour animer les barres de
-- duree en combat, puis abandonne : Blizzard n'appelle JAMAIS
-- SetCooldownFromDurationObject sur les Cooldown-enfants CDM pour la duree
-- des buffs (uniquement SetCooldown avec deux nombres). Voir Animation.lua
-- pour la piste retenue a la place (lecture du texte de decompte natif,
-- lisible meme secret, cf. /aishdebug cdmbuff).

-- DIAGNOSTIC TEMPORAIRE : journal des N derniers SetCooldown vus sur les
-- Cooldown-enfants CDM, AVANT le filtre wasSetFromCooldown/isOnGCD -- pour
-- verifier si ce hook capture AUSSI les swipes de duree de buff (pas
-- seulement les cooldowns de sort), condition necessaire pour etendre
-- SubscribeCDMCooldown au pipeline d'auras generique. Consultable via /aacdm.
local cdmSetCooldownLog = {}
ns._cdmSetCooldownLog = cdmSetCooldownLog
local CDM_LOG_MAX = 30

-- Journal PAR SPELLID, opt-in via ns._cdmWatchSpells[spellID]=true,
-- non partage avec cdmSetCooldownLog ci-dessus -- en combat, ce log global de
-- 30 entrees (TOUS sorts confondus) se fait vider en 1-2s par le bruit des
-- autres sorts trackes, ce qui evince l'evenement qui nous interesse avant
-- qu'on ait pu le lire via /aacdm ou /aatotemtest debug. Un journal dedie par
-- spellID watche (plus long, 200 entrees) survit au bruit des autres sorts.
-- Capture aussi Clear() et les changements de texte de charges (pas juste
-- SetCooldown) pour reconstituer la sequence complete d'un sort a charges.
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
            -- Diagnostic additif : dernier duration BRUT vu par spellID,
            -- stocke comme VALEUR (jamais compare/utilise en cle) -- toujours sûr,
            -- secret ou non. Sert uniquement a /aatotemtest debug et outils similaires
            -- pour verifier via tostring() si le filtre forwardSwipe (duration>1.5,
            -- plus bas) est la raison d'un swipe qui ne se declenche jamais.
            ns._cdmLastDuration = ns._cdmLastDuration or {}
            ns._cdmLastDuration[spellID] = duration
            -- Log diagnostique (avant tout filtre) -- voir commentaire au-dessus.
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

            -- Canal générique aura-swipe (voir bloc de commentaires plus haut) :
            -- AUCUN filtre wasSetFromCooldown/isOnGCD ici -- c'est justement ce
            -- filtre qui excluait les mises à jour de durée de buff
            -- (wasSetFromCooldown=false pour ces cas). Présence + swipe
            -- forwardés tels quels, jamais lus.
            -- Cooldown:SetCooldown(start, duration) REJETTE une valeur secrete des qu'elle
            -- transite par du code addon (tainted), meme en pur "sink" sans jamais
            -- la lire -- erreur "Secret values are only allowed during untainted
            -- execution for this argument." Seul le CODE BLIZZARD LUI-MEME
            -- (untainted) peut passer une valeur secrete a SetCooldown -- ce canal
            -- ne peut donc JAMAIS forwarder une duree reellement secrete (en
            -- combat) vers un widget Cooldown a nous, quelle que soit la methode.
            -- Reste utile hors combat / pour les valeurs non-secretes uniquement.
            -- Seule voie restante pour une duree combat-safe : le binding natif
            -- AuraButton:SetDurationCooldown (Blizzard appelle SetCooldown
            -- lui-meme, en code non-tainted) -- cf. AuraTrackerContainer.lua.
            --
            -- La presence ne doit se rafraichir QUE sur une vraie mise a jour de
            -- DUREE D'AURA (wasSetFromCooldown=false), PAS sur une recharge de
            -- CAPACITE (wasSetFromCooldown=true) -- meme spellID, meme hook,
            -- mais deux concepts differents chez Blizzard (l'aptitude ET le
            -- buff qu'elle accorde partagent le spellID). Sans ce filtre, une
            -- capacite dont le cooldown dure plus longtemps que son buff (ex:
            -- Rage du Berserker, Mur Protecteur) garde l'icone/la ligne
            -- "presente" pendant TOUTE la recharge -- bien apres la fin reelle
            -- du buff (icone ET barre de duree restant affichees, barre figee
            -- au minimum).
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
            -- Filtrer le GCD : wasSetFromCooldown + not isOnGCD.
            -- isOnGCD est le booléen natif CDM prévu pour ce filtre (lisible en tainté).
            -- wasSetFromCooldown seul était insuffisant (vrai sur certaines frames GCD).
            if parentFrame.wasSetFromCooldown and not parentFrame.isOnGCD then
                cdmCDData[spellID] = { version=ver, onCD=true }
                -- SIGNAL DE FIN pour un buff "banked" (cf. Rapidite de la
                -- nature/378081, ns.IsCDMAuraInstancePresent) : ce spellID n'a
                -- JAMAIS eu de swipe de DUREE D'AURA observe
                -- (ns.cdmAuraSwipePresence reste nil, jamais alimente par le
                -- filtre wasSetFromCooldown=false ci-dessus) -- dans ce cas
                -- PRECIS uniquement, le demarrage du CD de la capacite est la
                -- preuve que le buff banked vient d'etre consomme (le CD de ce
                -- type de sort ne demarre qu'a la perte du buff). Restreint a
                -- ce cas pour ne jamais couper prematurement l'anim d'un sort
                -- dont le CD demarre au cast alors que son buff a une vraie
                -- duree restante (les deux concepts redeviendraient alors
                -- independants, cf. commentaire wasSetFromCooldown plus haut).
                -- Meme garde double canal que ns.IsCDMAuraInstancePresent
                -- (swipe ET barre) -- un sort suivi via le canal BARRE
                -- (Vague de lave/Totem de flux tempetueux) n'a jamais de
                -- swipe mais gere deja correctement sa fin via ce canal-la ;
                -- le forcer a false ici serait une seconde source d'ecriture
                -- concurrente et inutile.
                if BANKED_BUFF_SPELLS[spellID]
                    and (not HasEverConfirmedPresence(ns.cdmAuraSwipePresence, spellID))
                    and (not HasEverConfirmedPresence(ns.cdmAuraBarPresence, spellID))
                    and ns.cdmAuraInstancePresence.player then
                    ns.cdmAuraInstancePresence.player[spellID] = false
                end
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
    -- SetCooldownFromDurationObject : 2e methode que Blizzard peut utiliser sur
    -- un widget Cooldown. Log diagnostique uniquement (verifiable via /aacdm) --
    -- elle n'est JAMAIS appelee pour la duree des buffs sur ces frames (voir
    -- note plus haut) : on ne construit plus de mecanisme de forward dessus.
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
            -- Canal générique aura-swipe : Clear() = l'aura vient de disparaître.
            -- Meme filtre que le SetCooldown ci-dessus : n'efface
            -- la presence QUE si cette frame trackait une duree d'aura
            -- (wasSetFromCooldown=false), pas une recharge de capacite -- sinon
            -- une capacite qui revient de cooldown AVANT que son buff (traque
            -- via une autre frame/viewer) ne finisse effacerait a tort la
            -- presence de ce buff encore actif.
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

-- Auto-découverte hoistée : appelée par chaque SetAuraInstanceInfo pour un sort
-- inconnu. Skip si déjà dans spells, skip si déjà War Gear (par spellID/itemID/nom).
-- Hoist pour éviter la closure pcall à chaque hit CDM (très fréquent en combat).
--
-- linkedSpellIDs (optionnel) : liste brute Blizzard des spellIDs
-- que le CDM regroupe sous UNE MEME identite (ex: Precurseur du Vide --
-- 1256301 a 1-2 stacks, 1256302 a 3+ -- meme "case" CDM, spellID different
-- selon le seuil). GetScanSpellID normalise TOUJOURS sid=linkedSpellIDs[1]
-- avant d'appeler cette fonction -- la variante "haute" n'est donc JAMAIS
-- decouverte comme entree separee si on ne fait rien de plus : on stocke
-- ici la liste complete sur l'entree (memes destinations/priorite), pour
-- que Whitelist.lua puisse inclure toutes les variantes dans la whitelist
-- native des qu'UNE seule (l'identite/l'ancre) est cochee.
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

-- Hooke le frame StatusBar enfant (frame.Bar) d'un item de BuffBarCooldownViewer
-- pour capturer/relayer sa durée de façon event-driven, comme HookCDMCooldownChild
-- le fait pour frame.Cooldown -- mais via un sink (StatusBar:SetValue) qui
-- accepte réellement les valeurs secrètes venant d'un addon (cf. bloc de
-- commentaires "ABONNEMENTS CLONE BAR" plus haut).
local hookedBarChildren = {}
local function HookCDMBarChild(barFrame, parentFrame)
    if not barFrame or hookedBarChildren[barFrame] then return end
    hookedBarChildren[barFrame] = true
    pcall(function()
        hooksecurefunc(barFrame, "SetMinMaxValues", function(self, lo, hi)
            local spellID = GetCDMFrameSpellID(parentFrame)
            if not spellID then return end
            -- Blizzard envoie hi=0 en CLAIR au moment precis ou le buff expire
            -- (confirme en jeu) : EFFACER la presence dans ce cas, pas la
            -- rafraichir -- sinon un buff expire restait "present" jusqu'a
            -- 15 min (CDM_AURA_SWIPE_STALE_AFTER), empechant l'icone/la barre
            -- de se cacher a la fin de son timer.
            --
            -- Gater ce hi=0 derriere "a deja eu une plage positive" (pour les
            -- auras sans vrai signal hi>0, ex. Precurseur du Vide) casse le
            -- masquage normal de la majorite des autres auras en Barres --
            -- l'hypothese "hi>0 observe au moins une fois pour une aura
            -- normale" est fausse en pratique. Le fix pour les auras dont ce
            -- canal ne se declenche jamais fiablement vit cote Scan.lua
            -- (ns._lastKnownAura, cache de derniere donnee connue par lecture
            -- directe), isole par spellID, sans toucher a cette semantique
            -- hi=0 partagee.
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

-- Hooke le FontString ChargeCount.Current d'un item Essential/Utility
-- CooldownViewer pour capturer le texte de charges de façon event-driven.
-- Même lecture (GetText, jamais l'argument SetText) que ScanCooldownViewer
-- fait déjà par polling -- ce hook ne fait qu'avancer le moment de la lecture
-- au lieu d'attendre le prochain tick à 0.15s.
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
        -- "return" precoce -- doit capter aussi bien la liaison (instID
        -- present) que la deliaison (cdmAura/instID nil, si Blizzard rappelle
        -- bien ce setter a la perte de l'aura -- hypothese testee en jeu).
        -- self.auraDataUnit reste lisible meme quand cdmAura est nil (propriete
        -- de la FRAME/du slot, pas de l'aura elle-meme).
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

        -- Cle = spellID, PAS instID (Secret Values, 12.0+) : un auraInstanceID
        -- peut etre secret et ne peut alors plus servir de cle de table
        -- ("cannot be indexed with secret keys"). spellID reste TOUJOURS
        -- clean sur ce hook (donne en clair par Blizzard via cooldownInfo).
        -- instID reste indispensable pour GetAuraDuration/
        -- GetAuraApplicationDisplayCount ailleurs dans le pipeline, mais
        -- stocke ici comme VALEUR de table -- toujours autorise, secret ou
        -- non, contrairement a un usage en cle ou en comparaison (==).
        -- Pas de dedup "meme aura, rien a faire" ici : comparer deux instID
        -- potentiellement secrets planterait aussi ; AutoDiscoverSpell et
        -- MaskCDMFrame sont deja idempotents, donc on peut se permettre de
        -- toujours reecrire/reappliquer sans cout reel.
        local name = GetSpellName and GetSpellName(spellID) or tostring(spellID)
        cdmData[unit][spellID] = { spellId = spellID, name = name, instID = instID }

        -- Clone stack (voir bloc de commentaires "ABONNEMENTS CLONE STACK"
        -- plus haut) : retransmet cdmAura.applications tel quel aux
        -- FontStrings abonnes pour ce spellID, sans jamais le lire nous-memes.
        -- Cache mis a jour inconditionnellement (meme sans abonne actuel) pour
        -- rattraper un abonnement qui arriverait juste apres cet appel.
        if cdmAura then
            cdmAuraLastApplications[spellID] = cdmAura.applications
            local stackSubs = cdmAuraStackSubscribers[spellID]
            if stackSubs then
                for _, fs in pairs(stackSubs) do
                    PushStackApplications(spellID, fs, cdmAura.applications)
                end
            end
        end

        -- TRACE : nouvelle aura CDM detectee

        -- Auto-découverte : tous les viewers CDM.
        -- SetAuraInstanceInfo est déclenché uniquement quand Blizzard affecte une
        -- vraie aura (avec auraInstanceID) — c'est déjà le filtre correct.
        if name then pcall(AutoDiscoverSpell, spellID, name, unit, self, self.cooldownInfo and self.cooldownInfo.linkedSpellIDs) end

        -- AUTO-CORRECTION : InitCDMHooks etiquette TOUT sort decouvert via
        -- Essentiel/Utilitaire comme source="debuff" (heuristique correcte
        -- pour la majorite des capacites offensives/CC, mais fausse pour
        -- celles qui s'octroient un buff a elles-memes -- Rapidite de la
        -- nature, Furie sanguinaire...). Ce hook precis ne se declenche QUE
        -- quand Blizzard lie l'icone CDM a
        -- une VRAIE instance d'aura sur `unit` -- si cet unit est "player" pour
        -- un sort deja marque "debuff", c'est la preuve directe que ce sort
        -- s'applique bien au joueur (pas a une cible) : on corrige silencieusement,
        -- sans liste figee de spellID a maintenir a la main.
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

-- Seul BuffBarCooldownViewer
-- construit ses items avec une vraie StatusBar (frame.Bar) -- Essential,
-- Utility ET BuffIcon sont TOUS structurellement Cooldown-only (aucune
-- StatusBar nulle part, même caché, même avec un item réellement actif
-- dessus, ex: Dur Au Mal actif sur Utility = pur Cooldown). La contrainte
-- "épingler sur Barres" pour une durée combat-safe n'est donc pas
-- contournable : c'est Blizzard qui n'a bâti qu'UN SEUL de ses 4 viewers
-- avec le bon type de widget, pas une limite de notre côté.

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

------------------------------------------------------------------------
-- AUTO-ÉPINGLAGE CDM (EXPÉRIMENTAL)
--
-- Contexte (le besoin est réel) : la quasi-totalité de ce pipeline (durée
-- combat-safe, stacks) dépend de Blizzard assignant réellement une frame CDM
-- au spellID -- ce qui n'arrive QUE si le sort a été épinglé manuellement
-- dans le Cooldown Manager natif (Edit Mode). Sans ça : aucune icône, aucune
-- barre, rien. Épingler manuellement 40 spés à la main n'est pas praticable.
--
-- Ceci appelle du code UI Blizzard NON-DOCUMENTÉ (pas le namespace public
-- C_CooldownViewer, qui est lecture seule -- cf. commentaire ScanCDMViewers
-- plus haut) : le mixin interne de CooldownViewerSettings.lua/
-- CooldownViewerSettingsDataProvider.lua/CooldownViewerSettingsLayoutManager.lua
-- -- risque de casse à un futur patch puisque non documenté officiellement.
--
-- SetCooldownToCategory (la mutation elle-même) tainte l'exécution partagée
-- de tout Blizzard_CooldownViewer, quelle que soit la variante d'appel --
-- même un write minimal sans RefreshLayout()/SaveCurrentLayout() finit par
-- provoquer un crash ADDON_ACTION_BLOCKED ailleurs dans notre propre code dès
-- que le joueur entre en combat. Il n'existe pas de variante "propre" de cet
-- appel.
--
-- Mitigation retenue : accepter que le taint est inévitable, mais le
-- confiner en forçant un ReloadUI() immédiatement après toute mutation
-- réussie -- avant que le joueur ait la moindre chance d'entrer en combat
-- dans CETTE session. Le taint vit dans la VM Lua courante ; un reload en
-- démarre une toute neuve, 100% propre (seul l'état SAUVEGARDÉ --
-- SavedVariables, via SaveLayouts -- traverse le reload, pas le taint
-- lui-même). Ne PAS retirer ce ReloadUI() sans reproduire un moyen
-- équivalent de garantir un retour à une VM propre avant tout combat.
--
-- Séquence d'appels (cf. SetSpellCDMCategory + SaveCDMLayoutMinimal) :
--   1) Trouver le cooldownID Blizzard du spellID (lecture pure, 100% API
--      publique déjà utilisée ailleurs dans ce fichier -- ScanCDMViewers) :
--      C_CooldownViewer.GetCooldownViewerCategorySet(cat, true) avec
--      includeDisabled=true retourne AUSSI les sorts pas encore épinglés
--      (catégorie "Hidden*" en interne), pas seulement les actifs.
--   2) CooldownViewerSettings:GetDataProvider():SetCooldownToCategory(id, cat)
--      -- la mutation elle-même.
--   3) dataProvider:GetLayoutManager():SaveLayouts() -- persistance minimale,
--      SANS passer par CooldownViewerSettings:RefreshLayout()/SaveCurrentLayout()
--      (le wrapper panneau de réglages, qui propage le taint plus largement).
------------------------------------------------------------------------
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

-- Lookup rapide "categorie autorisee" -- utilise comme VERROU cote info.category
-- (cf. FindCooldownIDForSpell) : le champ .category renvoye par
-- GetCooldownViewerCooldownInfo est la classification DEFAUT/statique cote
-- Blizzard (CheckBuildDisplayData la stocke elle-meme comme "default a ne pas
-- ecraser", cf. CooldownViewerSettingsDataProvider.lua) -- jamais affectee par
-- un SetCooldownToCategory anterieur (notre ou celui de l'utilisateur), donc
-- fiable comme signal "ce cooldownID est structurellement une AURA" meme si
-- quelqu'un l'a deja bascule ailleurs par erreur.
local AURA_CATEGORY_SET = {}
for _, cat in ipairs(CDM_PIN_CATEGORIES) do
    if cat then AURA_CATEGORY_SET[cat] = true end
end

-- Retrouve le cooldownID Blizzard correspondant a spellID, epingle ou non
-- (includeDisabled=true), en parcourant UNIQUEMENT les categories auras
-- (cf. CDM_PIN_CATEGORIES). Renvoie nil si Blizzard ne connait pas ce sort
-- en tant qu'AURA pour la spec active (sort non trackable comme aura --
-- p.ex. un pur cooldown de sort -- ou pas encore decouvert cote client).
--
-- VERROU (le taint peut se propager jusqu'a casser l'affichage des charges
-- d'un AUTRE sort, Utility viewer) : certaines auras partagent leur spellID
-- avec le SORT qui les applique (linkedSpellIDs peut grouper les deux sous
-- une identite commune).
-- Meme en ne scannant QUE TrackedBuff/TrackedBar, on verifie ICI en plus que
-- info.category (le VRAI classement par defaut de ce cooldownID precis, pas
-- juste "trouve en cherchant dans ces categories") est bien une categorie
-- aura -- jamais Essential/Utility/EquipSlot*/SpecAgnostic*. Un cooldownID
-- dont l'identite reelle est un cooldown de sort est ignore, meme s'il
-- apparait par ailleurs lie au meme spellID.
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

-- Coeur de la mutation, SANS RefreshLayout/SaveCurrentLayout (couteux --
-- appele isolement par PinAuraToCDM, mais UNE SEULE FOIS a la fin d'un
-- lot par SyncCDMPins plutot qu'a chaque sort). Retourne (success, message).
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

-- Persiste au plus bas niveau possible (layoutManager:SaveLayouts(), jamais
-- CooldownViewerSettings:RefreshLayout()/SaveCurrentLayout() -- inutile de
-- toute facon vu le ReloadUI() force juste apres par les appelants).
local function SaveCDMLayoutMinimal(dataProvider)
    local okLM, layoutManager = pcall(dataProvider.GetLayoutManager, dataProvider)
    if okLM and layoutManager then
        pcall(layoutManager.SaveLayouts, layoutManager)
    end
end

-- Popup de confirmation (meme pattern que AISD_CONFIRM_DELETE_TAG dans
-- SettingsPanel.lua) -- PAS de ReloadUI() automatique : un reload force
-- surprend l'utilisateur en pleine action (ferme les fenetres ouvertes,
-- interrompt un raid loot etc.). On propose un reload, comme la plupart des
-- addons apres un changement qui en necessite un -- l'utilisateur choisit le
-- moment.
StaticPopupDialogs["AISH_CDM_RELOAD"] = {
    text = L["CDM_RELOAD_PROMPT"],
    button1 = RELOADUI,
    button2 = L["CDM_RELOAD_LATER"],
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Compteur de sorts epingles depuis le dernier reload, pas encore "acquittes"
-- par une reponse au popup -- permet de re-proposer plus tard (fermeture du
-- GUI des auras trackees, cf. Init.lua) sans perdre le compte si l'utilisateur
-- a clique "Plus tard".
local pendingCDMReloadCount = 0

-- Historique des appels a MarkCDMReloadPending (qui, quand, combien), pour
-- identifier la source exacte d'un popup de reload inattendu -- cf.
-- /aishdebug cdmreload (Debug.lua).
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

-- Nombre de sorts en attente la DERNIERE FOIS que le popup a ete montre
-- (accepte OU decline via "Plus tard"). pendingCDMReloadCount ne redescend
-- JAMAIS a zero tant qu'aucun reload effectif n'a eu lieu (par design, cf.
-- commentaire ci-dessus -- ne pas perdre le compte si l'utilisateur clique
-- "Plus tard"). Mais PromptCDMReloadIfPending est appelee a CHAQUE fermeture
-- du GUI (SettingsPanel.lua, MainFrame OnHide) -- sans ce garde, le popup
-- reviendrait a CHAQUE fermeture, meme sans le moindre nouveau sort epingle
-- depuis la derniere fois qu'il a ete montre. On ne re-affiche donc que si
-- le compte a REELLEMENT augmente depuis le dernier affichage.
local lastPromptedCDMReloadCount = 0

-- Affiche le popup s'il y a quelque chose en attente ET qu'il n'est pas deja
-- visible (evite d'empiler plusieurs popups identiques). N'affecte PAS
-- pendingCDMReloadCount ici -- seul un ReloadUI() effectif (OnAccept) ou un
-- reload manuel de l'utilisateur remet le compteur a zero (au prochain login,
-- cf. redeclaration locale a chaque chargement de fichier).
function ns.PromptCDMReloadIfPending()
    if pendingCDMReloadCount <= 0 then return end
    if pendingCDMReloadCount <= lastPromptedCDMReloadCount then return end
    if StaticPopup_Visible and StaticPopup_Visible("AISH_CDM_RELOAD") then return end
    lastPromptedCDMReloadCount = pendingCDMReloadCount
    StaticPopup_Show("AISH_CDM_RELOAD", pendingCDMReloadCount)
end

-- Epingle spellID dans le viewer "Barres" (BuffBarCooldownViewer, category
-- TrackedBar) -- ou "Icones" (BuffIconCooldownViewer, TrackedBuff) si
-- asBar=false. Retourne (success, statusMessage) -- jamais d'erreur non
-- protegee : chaque appel Blizzard est en pcall, toute forme inattendue de
-- retour (API changee a un patch) echoue proprement sans planter l'addon.
-- Marque juste un reload comme necessaire (ns.MarkCDMReloadPending) en cas
-- de succes -- ne montre PAS le popup lui-meme : c'est a l'appelant de
-- decider QUAND le proposer (immediatement pour un usage debug isole, a la
-- fermeture du GUI pour l'auto-pin, cf. ns.PromptCDMReloadIfPending).
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

-- Ensemble des spellID deja suivis EN BARRES (TrackedBar precisement,
-- includeDisabled=false -- donc actifs seulement). Sert a ne pas retoucher
-- un sort deja au bon endroit -- mais PAS a epargner un sort suivi en
-- Icones/Essentiel/Utilitaire (TrackedBuff/Essential/Utility) : seul
-- TrackedBar utilise une vraie StatusBar cote Blizzard (accepte le forward
-- de valeurs secretes en combat, cf. commentaire "ABONNEMENTS CLONE BAR"
-- plus haut) -- un sort suivi ailleurs reste donc tout aussi inutilisable
-- pour AishCore qu'un sort pas suivi du tout, et doit etre bascule en
-- Barres lui aussi (Fragments d'ame restait par exemple coince en
-- "Ameliorations suivies" tant que ce garde-fou incluait TrackedBuff).
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

-- Sorts pour lesquels SetCooldownToCategory a REUSSI cette session (Barres
-- OU repli Icones). Necessaire car GetAlreadyBarTrackedSpellSet() interroge
-- l'etat LIVE du CDM (GetCooldownViewerCategorySet) -- qui ne reflete
-- l'assignation qu'APRES le /reload propose par le popup (cf. commentaire
-- CDM_PIN_DISABLED_REASON plus haut : la mutation est ecrite/sauvegardee
-- immediatement, mais le viewer en cours de session ne la voit pas tant
-- qu'une VM propre n'a pas redemarre). Sans ce cache, tant que l'utilisateur
-- n'a pas clique sur "Recharger", chaque rebuild de whitelist (ouverture du
-- menu Auras a tracker, changement de couleur/glow/destination -- pas
-- seulement l'activation d'un nouveau sort) retrouverait ces sorts "pas
-- encore en Barres" cote live, les repinnerait (idempotent cote Blizzard
-- mais quand meme "succes"), et remarquerait donc un reload comme
-- necessaire -- d'ou un popup qui reviendrait sans cesse meme sans aucun
-- changement utilisateur.
-- Session-only (pas persiste) : se re-decouvre au prochain /reload, moment
-- ou GetAlreadyBarTrackedSpellSet reflete enfin l'etat reel et prend le relai.
local pinnedThisSession = {}

-- Parcourt toute la whitelist AishCore de la spec active (ns.GetSpecSpells,
-- memes sorts que ceux affiches en jeu) et epingle en "Barres" (TrackedBar)
-- tout spellID active pas DEJA en Barres cote CDM natif -- y compris s'il
-- est deja suivi en Icones (TrackedBuff) : cf. GetAlreadyBarTrackedSpellSet,
-- seul TrackedBar convient vraiment pour AishCore. Ne touche JAMAIS
-- Essential/Utility (temps de recharge de sorts, pas des auras) :
-- FindCooldownIDForSpell ne les scanne meme pas, cf. CDM_PIN_CATEGORIES.
-- Marque un reload comme necessaire (ns.MarkCDMReloadPending) si au moins un
-- sort a ete epingle -- l'appelant decide quand proposer le popup (cf.
-- ns.PromptCDMReloadIfPending). Seule garantie contre le taint documente
-- plus haut (CDM_PIN_DISABLED_REASON).
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
                -- Repli Icones (TrackedBuff) : un refus Blizzard en Barres survient
                -- typiquement pour un sort sans duree/minuteur (StatusBar Barres n'a
                -- rien a animer) -- sans ce repli, ce sort ne serait JAMAIS assigne a
                -- AUCUNE categorie CDM, et donc invisible du pipeline AishCore
                -- (100% CDM-only, cf. Scan.lua) quel que soit le mode d'affichage
                -- choisi cote AishCore (Liste/Cercle/Icones/Barres).
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


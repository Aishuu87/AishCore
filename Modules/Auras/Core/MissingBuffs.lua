-- AishUIAura/Core/MissingBuffs.lua
-- Moteur "Buffs manquants" : detecte les buffs/stances/enchants attendus qui
-- sont absents et affiche une alerte pour le sort correspondant.
--
-- LIMITE CONNUE : la lecture des auras d'une unite AUTRE que le joueur
-- (party/raid) via AuraUtil.ForEachAura est protegee par pcall mais a de
-- fortes chances d'echouer silencieusement en pratique -- cf.
-- Modules/TargetAuras.lua:3-15 (meme mecanisme casse sur "target") : les
-- payloads d'aura sont systematiquement secrets depuis le patch 12.1, plus
-- seulement en combat. La detection SUR SOI (stances/auras/attunements,
-- familiers, poisons, buff de classe manquant sur soi, enchants d'arme) est
-- fiable (C_UnitAuras.GetPlayerAuraBySpellID, deja utilise partout ailleurs
-- dans l'addon). Aucune erreur ne remonte si la detection sur les allies
-- echoue -- elle degrade juste vers "rien detecte" pour cette cible.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local MissingBuffs = {}
ns.MissingBuffs = MissingBuffs

------------------------------------------------------------------------
-- UPVALUES
------------------------------------------------------------------------
local pcall, pairs, ipairs, select = pcall, pairs, ipairs, select
local GetTime, UnitClass = GetTime, UnitClass
local UnitExists, UnitIsUnit, UnitIsConnected, UnitIsDeadOrGhost, UnitIsDead = UnitExists, UnitIsUnit, UnitIsConnected, UnitIsDeadOrGhost, UnitIsDead
local UnitCanAssist, UnitCanAttack, UnitGroupRolesAssigned = UnitCanAssist, UnitCanAttack, UnitGroupRolesAssigned
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local InCombatLockdown, IsMounted, IsResting = InCombatLockdown, IsMounted, IsResting
local C_Timer = C_Timer
local _issecretvalue = issecretvalue

local function IsSecret(v) return _issecretvalue and _issecretvalue(v) or false end

-- Rappel "bientot expire" : malgre le fait que le payload d'aura soit
-- generalement secret depuis le patch 12.1, une lecture d'expirationTime
-- reste possible par moments. La bonne approche n'est donc PAS de supposer
-- "toujours secret"/"safe hors combat", mais de verifier ETAT PAR ETAT via
-- C_Secrets.ShouldAurasBeSecret() + issecretvalue() sur chaque champ lu, et
-- de degrader silencieusement (return nil, pas d'erreur) des que ce n'est
-- pas lisible a cet instant -- le rappel n'apparait alors que quand la
-- lecture est reellement possible.
local C_Secrets = C_Secrets
local function AurasAreSecret()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false
end

-- Renvoie expirationTime (nombre GetTime()-compatible) ou nil si illisible/
-- secret/absent/sans vraie duree (buff permanent, expirationTime==0).
local function SafeAuraExpiration(aura)
    if not aura or IsSecret(aura) then return nil end
    local v = aura.expirationTime
    if type(v) ~= "number" or IsSecret(v) then return nil end
    if v == 0 then return nil end -- pas de vraie duree (buff permanent)
    return v
end

------------------------------------------------------------------------
-- Config
------------------------------------------------------------------------
local function Cfg()
    return (ns.db and ns.db.missingBuffs) or {}
end
MissingBuffs.Cfg = Cfg

------------------------------------------------------------------------
-- Apprentissage
------------------------------------------------------------------------
local function IsEntryLearned(entry)
    local checkId = entry.spellbookId or entry.spellId
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then
        return entry.learned == true
    end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, checkId)
    if not ok then return entry.learned == true end
    if known and entry.excludeIfKnown then
        for _, exId in ipairs(entry.excludeIfKnown) do
            local ok2, known2 = pcall(C_SpellBook.IsSpellKnown, exId)
            if ok2 and known2 then return false end
        end
    end
    return known == true
end

------------------------------------------------------------------------
-- Lecture d'aura SUR SOI (fiable -- contrairement a un instanceID capture via
-- un hook CDM, GetPlayerAuraBySpellID reste utilisable ici)
------------------------------------------------------------------------
local function GetSelfAura(spellId)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if ok and aura then return aura end
    return nil
end
MissingBuffs.GetSelfAura = GetSelfAura

local function SelfHasBuff(entry)
    if GetSelfAura(entry.spellId) then return true end
    if entry.extraBuffSpellIds then
        for _, sid in ipairs(entry.extraBuffSpellIds) do
            if GetSelfAura(sid) then return true end
        end
    end
    if entry.mutuallyExclusiveWith then
        for _, sid in ipairs(entry.mutuallyExclusiveWith) do
            if GetSelfAura(sid) then return true end
        end
    end
    return false
end

-- true = ce buff est present sur SOI mais expire dans <= threshold secondes ;
-- false = present avec assez de marge (ou sans vraie duree/illisible) ;
-- l'appelant ne doit consulter cette fonction QUE si le buff est deja
-- confirme present par ailleurs (SelfHasBuff/AnyoneMissingBuff) -- ici on ne
-- reverifie que la duree, jamais la presence elle-meme.
local function GetSelfBuffExpiringSoon(entry, threshold)
    if entry.ignoreDuration then return false end
    if type(threshold) ~= "number" or threshold <= 0 then return false end
    if entry.weaponEnchantSlot then
        if not GetWeaponEnchantInfo then return false end
        local ok, hasMain, mainExpireMS, _, hasOff, offExpireMS = pcall(GetWeaponEnchantInfo)
        if not ok then return false end
        local expireMS
        if entry.weaponEnchantSlot == "main" then
            if hasMain ~= true then return false end
            expireMS = mainExpireMS
        else
            if hasOff ~= true then return false end
            expireMS = offExpireMS
        end
        if type(expireMS) ~= "number" or IsSecret(expireMS) then return false end
        return expireMS <= (threshold * 1000)
    end
    if AurasAreSecret() then return false end
    -- Meme ordre de priorite que SelfHasBuff : le premier spellId REELLEMENT
    -- present (nil = absent, on continue) determine la reponse.
    local function checkOne(spellId)
        local aura = GetSelfAura(spellId)
        if not aura then return nil end
        local exp = SafeAuraExpiration(aura)
        if not exp then return false end -- present mais sans vraie duree
        local remain = exp - GetTime()
        return remain > 0 and remain <= threshold
    end
    local r = checkOne(entry.spellId)
    if r ~= nil then return r end
    if entry.extraBuffSpellIds then
        for _, sid in ipairs(entry.extraBuffSpellIds) do
            r = checkOne(sid)
            if r ~= nil then return r end
        end
    end
    if entry.mutuallyExclusiveWith then
        for _, sid in ipairs(entry.mutuallyExclusiveWith) do
            r = checkOne(sid)
            if r ~= nil then return r end
        end
    end
    return false
end
MissingBuffs.GetSelfBuffExpiringSoon = GetSelfBuffExpiringSoon

local function SelfHasWeaponEnchant(entry)
    if not GetWeaponEnchantInfo then return true end
    local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
    if not ok then return true end
    if entry.weaponEnchantSlot == "main" then return hasMain == true end
    if entry.weaponEnchantSlot == "off" then return hasOff == true end
    return true
end

------------------------------------------------------------------------
-- Lecture d'aura sur un ALLIE -- best-effort, cf. bandeau de tete de fichier.
-- Repli "spell activation overlay" natif Blizzard en priorite quand
-- l'entree le supporte (Beacon of Light/Faith) : glow deja calcule cote C++,
-- immunise au taint (meme principe que le rendu natif AddAuraGroup).
------------------------------------------------------------------------
local function CheckSpellOverlayMissing(entry)
    if not entry.spellOverlayCompatible then return nil end
    if not (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) then return nil end
    local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, entry.spellId)
    if not ok then return nil end
    return overlayed == true -- true = Blizzard signale qu'il faut relancer -> "manquant" quelque part
end

local function UnitHasBuffRaw(unit, entry)
    -- Les payloads d'aura d'un ALLIE sont secrets en quasi-permanence depuis
    -- le patch 12.1 (pas seulement en combat, cf. AurasAreSecret et le
    -- bandeau de tete de fichier) : ForEachAura ne peut alors JAMAIS lire un
    -- spellId, meme si l'allie a reellement le buff -- la boucle ci-dessous
    -- retournerait TOUJOURS "found=false". Sans ce garde-fou, ca faisait
    -- croire "manquant" en PERMANENCE en donjon/raid (confirme en jeu :
    -- alerte "1/5" qui boucle en M+ alors que tout le groupe est buffe).
    -- Repli cote sur : etat illisible -> on suppose le buff present plutot
    -- que de spammer un faux "manquant" pour toujours -- ne concerne QUE la
    -- detection sur les allies (SelfHasBuff, sur soi, reste fiable via
    -- C_UnitAuras.GetPlayerAuraBySpellID, cf. bandeau de tete de fichier).
    if AurasAreSecret() then return true end
    if not (AuraUtil and AuraUtil.ForEachAura) then return false end
    local lookup = { [entry.spellId] = true }
    if entry.extraBuffSpellIds then for _, id in ipairs(entry.extraBuffSpellIds) do lookup[id] = true end end
    if entry.mutuallyExclusiveWith then for _, id in ipairs(entry.mutuallyExclusiveWith) do lookup[id] = true end end
    local found = false
    pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, function(aura)
        if not aura then return false end
        local sid = aura.spellId
        -- issecretvalue() DOIT etre le tout premier test, avant TOUTE
        -- comparaison (meme `== nil`) -- une comparaison sur une valeur
        -- secrete peut planter/propager le taint, ce qui a fini par bloquer
        -- un appel protege plus loin (Hide() sur le frame d'alerte, en
        -- combat -- confirme en jeu, ADDON_ACTION_BLOCKED).
        if IsSecret(sid) then return false end
        if sid == nil then return false end
        if not lookup[sid] then return false end
        -- requireOwnCast : ne compte que NOTRE instance du buff, pas celle
        -- d'un autre joueur de meme classe/role (ex. Bouclier de terre --
        -- plusieurs chamans peuvent chacun placer le leur sur une cible
        -- differente, ce n'est pas un buff "un seul par raid" malgre
        -- onlyOnePerGroup ici cote UI). sourceUnit absent/secret -> on ne
        -- suppose PAS que c'est le notre (repli "toujours manquant" plutot
        -- que de cacher a tort le rappel).
        if entry.requireOwnCast then
            local src = aura.sourceUnit
            if IsSecret(src) then return false end
            if src == nil or not UnitIsUnit(src, "player") then return false end
        end
        found = true
        return true
    end, true)
    return found
end

local function UnitHasBuff(unit, entry)
    if unit == "player" then return SelfHasBuff(entry) end
    local overlayMissing = CheckSpellOverlayMissing(entry)
    if overlayMissing ~= nil then return not overlayMissing end
    return UnitHasBuffRaw(unit, entry)
end

------------------------------------------------------------------------
-- Unites du groupe
------------------------------------------------------------------------
local function GetGroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
    end
    return units
end

local function IsValidAllyUnit(unit)
    if not UnitExists(unit) then return false end
    if UnitIsUnit(unit, "player") then return false end
    if not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if not UnitCanAssist("player", unit) then return false end
    return true
end

-- issecretvalue() DOIT etre le tout premier test, avant TOUTE comparaison
-- (meme `v ~= nil` ou `v == true`) -- une comparaison sur une valeur secrete
-- peut elle-meme planter/propager le secret ("attempt to perform boolean
-- test on ... a secret boolean value").
local function NormalizeRangeFlag(v)
    if IsSecret(v) then return nil end
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

local function PassesRangeCheck(unit, entry)
    if entry.ignoreRangeCheck then return true end

    -- spellbookId (quand present) est LE sort reellement castable/connu --
    -- cf. IsEntryLearned ci-dessus, meme repli. entry.spellId n'est parfois
    -- que l'ID de l'aura trackee (rang different/non connu directement) :
    -- interroger IsSpellInRange dessus peut echouer silencieusement et faire
    -- tomber en repli ferme (jamais "a portee") meme quand l'allie l'est
    -- reellement (confirme en jeu : Bouclier de terre 2/2 jamais propose
    -- malgre des allies a portee et non-buffes).
    local checkId = entry.spellbookId or entry.spellId

    if C_Spell and C_Spell.IsSpellInRange then
        local ok, raw = pcall(C_Spell.IsSpellInRange, checkId, unit)
        if ok then
            local flag = NormalizeRangeFlag(raw)
            if flag ~= nil then return flag end
        end
    end

    if UnitInRange then
        local ok, rawInRange, rawChecked = pcall(UnitInRange, unit)
        if ok then
            local flag = NormalizeRangeFlag(rawInRange)
            if flag ~= nil then return flag end
            if NormalizeRangeFlag(rawChecked) == true then return false end
        end
    end

    -- Indetermine des deux cotes : repli ferme (pas a portee) plutot
    -- qu'ouvert -- l'ancien repli "true par defaut" affichait l'icone meme
    -- seul dans son coin des qu'un sort ne renvoyait jamais de resultat net.
    return false
end

-- Compte combien d'unites A PORTEE ont deja le buff, sur le total d'unites
-- A PORTEE qui devraient l'avoir (soi + allies valides passant le meme
-- filtre que la detection normale) -- pour l'affichage "10/14" a la
-- Clickable Raid Buff, uniquement sur les entrees marquees showRaidCount
-- (les "vrais" buffs de raid un-par-personne : Cri de guerre, Benediction
-- du Bronze, Marque de la nature sauvage, Intellect sublime, Fortitude,
-- Fureur des cieux -- pas les buffs a instance unique type Benediction/
-- Bouclier de terre, ou le compte n'aurait pas de sens).
local function CountBuffCoverage(entry)
    local have, total = 0, 0
    total = total + 1
    if UnitHasBuff("player", entry) then have = have + 1 end
    for _, unit in ipairs(GetGroupUnits()) do
        if IsValidAllyUnit(unit) and PassesRangeCheck(unit, entry) then
            total = total + 1
            if UnitHasBuff(unit, entry) then have = have + 1 end
        end
    end
    return have, total
end

------------------------------------------------------------------------
-- Buff de classe manquant (soi puis allies), variantes onlyOnePerGroup /
-- requiresHealerInGroup / weaponEnchantSlot
------------------------------------------------------------------------
local function AnyoneMissingBuff(entry)
    if entry.weaponEnchantSlot then
        if SelfHasWeaponEnchant(entry) then return false end
        return true, "player"
    end

    if entry.onlyOnePerGroup then
        if not entry.ignoreSelf and UnitHasBuff("player", entry) then return false end
        local units = GetGroupUnits()
        -- ignoreSelf = ce buff ne peut jamais compter sur soi (ex: "buffer un
        -- allie") : seul en groupe/raid, il n'y a personne a buffer -> pas
        -- "manquant". Sans ce garde-fou, la boucle vide ci-dessous tombait
        -- toujours sur `return true` (confirme en jeu, Chaman "Buffer un allie"
        -- affiche hors groupe).
        if entry.ignoreSelf and #units == 0 then return false end
        local anyoneInRange = false
        for _, unit in ipairs(units) do
            -- PAS de PassesRangeCheck ici : on verifie si le buff est DEJA
            -- applique quelque part dans le groupe, pas si on peut agir
            -- maintenant -- le buff reste actif meme si la cible s'eloigne
            -- ensuite. Avec le fail-closed de PassesRangeCheck (portee
            -- indeterminee -> false), l'exiger ici faisait croire "encore
            -- manquant" alors que tout le monde etait deja couvert (confirme
            -- en jeu : Bouclier de terre 2/2 mais "Buffer un allie" restait
            -- affiche).
            if IsValidAllyUnit(unit) and UnitHasBuff(unit, entry) then
                return false
            end
            if IsValidAllyUnit(unit) and PassesRangeCheck(unit, entry) then
                anyoneInRange = true
            end
        end
        -- ignoreSelf : le rappel cible forcement un allie (clic -> cible) --
        -- si personne n'est a portee pour le recevoir, rien n'est actionnable
        -- maintenant, donc pas d'icone "Buffer un allie" plutot que l'afficher
        -- en permanence des qu'on est seul dans son coin (confirme en jeu).
        if entry.ignoreSelf and not anyoneInRange then return false end
        return true, "player"
    end

    if not entry.ignoreSelf and not UnitHasBuff("player", entry) then
        return true, "player"
    end
    if not entry.onlySelf then
        for _, unit in ipairs(GetGroupUnits()) do
            if IsValidAllyUnit(unit) and PassesRangeCheck(unit, entry) and not UnitHasBuff(unit, entry) then
                return true, unit
            end
        end
    end
    return false
end

local function HealerMissingBuff(entry)
    for _, unit in ipairs(GetGroupUnits()) do
        if IsValidAllyUnit(unit) and UnitGroupRolesAssigned(unit) == "HEALER"
           and PassesRangeCheck(unit, entry) and not UnitHasBuff(unit, entry) then
            return true, unit
        end
    end
    if UnitGroupRolesAssigned("player") == "HEALER" and not UnitHasBuff("player", entry) then
        return true, "player"
    end
    return false
end

------------------------------------------------------------------------
-- Groupe mutuellement exclusif (stances/auras/attunements/poisons/pets)
------------------------------------------------------------------------
local function PickDefaultOption(list, overrideSpellId)
    if overrideSpellId then
        for _, opt in ipairs(list) do if opt.spellId == overrideSpellId then return opt end end
    end
    for _, opt in ipairs(list) do if opt.default then return opt end end
    return list[1]
end

local function ExclusiveGroupMissing(list, overrideSpellId)
    for _, opt in ipairs(list) do
        if GetSelfAura(opt.spellId) then return false end
    end
    return true, PickDefaultOption(list, overrideSpellId)
end

local function CheckRoguePoisons()
    local cfg = Cfg()
    if not cfg.ignoreNonlethalPoisons then
        local missing, opt = ExclusiveGroupMissing(ns.MISSING_ROGUE_POISONS.nonlethal, cfg.overrideNonlethalPoison)
        if missing then return true, opt, "APPLY_NONLETHAL" end
    end
    if not cfg.ignoreLethalPoisons then
        local missing, opt = ExclusiveGroupMissing(ns.MISSING_ROGUE_POISONS.lethal, cfg.overrideLethalPoison)
        if missing then return true, opt, "APPLY_LETHAL" end
    end
    return false
end

-- Grimoire de sacrifice (108503, Demoniste) : sacrifie DELIBEREMENT le
-- familier contre le buff 196099 --
local GRIMOIRE_OF_SACRIFICE_BUFF = 196099
local function HasSacrificedPetForGrimoire()
    return GetSelfAura(GRIMOIRE_OF_SACRIFICE_BUFF) ~= nil
end

local function CheckPetMissing(class)
    local cfg = Cfg()
    if UnitExists("pet") then
        if class == "HUNTER" and UnitIsDead("pet") then
            return true, { spellId = ns.MISSING_HUNTER_PET_DEAD }, "REVIVE_PET"
        end
        return false
    end
    if class == "WARLOCK" and HasSacrificedPetForGrimoire() then
        return false
    end
    local list = (class == "HUNTER") and ns.MISSING_HUNTER_ALL_PETS or ns.MISSING_WARLOCK_ALL_PETS
    local overrideId = (class == "HUNTER") and cfg.overrideHunterPet or cfg.overrideWarlockPet
    return true, PickDefaultOption(list, overrideId), "SUMMON_PET"
end

------------------------------------------------------------------------
-- Applicabilite d'une entree (spe / combat / ignoree par l'utilisateur)
------------------------------------------------------------------------
local function EntryApplies(entry)
    if entry.specIds then
        local specID = _addon._specID
        if not specID then return false end
        local ok = false
        for _, sid in ipairs(entry.specIds) do if sid == specID then ok = true; break end end
        if not ok then return false end
    end
    local cfg = Cfg()
    if entry.settingsId and cfg.ignoredSettingsIds and cfg.ignoredSettingsIds[entry.settingsId] then
        return false
    end
    if InCombatLockdown() then
        -- Les buffs de raid "10/14" scannent TOUT le groupe/raid (souvent
        -- reparti en plusieurs sous-groupes) -- ce scan devient peu fiable en
        -- combat (visibilite des auras entre sous-groupes, valeurs secretes),
        -- pouvant figer une alerte en boucle tout un combat alors que tout le
        -- monde est deja buffe. Verrouillage absolu, ignore meme le reglage
        -- "Afficher en combat" -- ces buffs ne s'appliquent de toute façon
        -- plus une fois le combat lance.
        if entry.showRaidCount then return false end
        if not (entry.showInCombat or (entry.whitelist and cfg.showBuffsInCombat)) then
            return false
        end
    end
    return true
end

------------------------------------------------------------------------
-- Affichage : icone + texte, deplacable, bouton securise cliquable
------------------------------------------------------------------------
local ICON_SIZE = 64
local NO_MASK_TEXTURE = "Interface\\Buttons\\WHITE8x8" -- blanc opaque = pas de decoupe visible
local frame, iconTex, textFS, borderTex, maskTex
local textContainer -- frame porteur de textFS + slugFS, cf. commentaire ci-dessous
local textAnimGroups -- { pulse=, bounce=, blink= } -- cf. BuildTextAnimGroups
local vanishAnimGroup -- glissement + fondu joue avant le Hide() reel, cf. BuildVanishAnimGroup
local appearAnimGroup -- glissement + fondu joue au Show(), cf. BuildAppearAnimGroup
local slugFS -- 8 FontStrings d'ombre "SLUG" en anneau derriere textFS, cf. BuildSlugShadow
local currentAlertSpell

-- IMPORTANT : un AnimationGroup cree DIRECTEMENT sur une region (FontString)
-- n'anime QUE cette region precise -- ça ne se propage PAS a une autre
-- region simplement ancree dessus via SetPoint (contrairement a un FRAME,
-- ou la transformation descend sur tout ce qu'il contient : c'est pour ça
-- que icone+texte suivent bien ensemble pendant vanish/appear, animes sur
-- `frame`). Confirme en jeu : l'ombre SLUG ne suivait pas le rebond du texte
-- tant qu'elle etait juste ancree sur textFS. D'ou `textContainer` : un
-- frame qui porte textFS ET son anneau SLUG comme ses PROPRES regions --
-- les animations pulse/bounce/blink jouent sur CE frame, donc cascadent
-- automatiquement a tout ce qu'il contient. L'anneau lui-meme (creation,
-- style, texte) est gere par les helpers partages ns.CreateSlugRing /
-- ns.ApplyTextOutlineStyle / ns.SetSlugRingText (Core.lua) -- memes qui
-- servent maintenant a tous les autres textes personnalisables de l'addon.

local function BuildClickInfo(entry, targetUnit)
    local clickId = entry.clickableId or entry.spellId
    local spellName
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, clickId)
        if ok then spellName = n end
    end
    return { spellName = spellName, useTarget = entry.clickingUsesTarget and targetUnit and targetUnit ~= "player" }
end

--- Ligne de macro "/cast" pour UNE entree -- meme resolution de nom que
--- BuildClickInfo, mais formatee directement en texte de macro pour pouvoir
--- etre concatenee avec d'autres lignes (cf. chainage buffs de classe ci-dessous).
local function BuildCastLine(entry, targetUnit)
    local info = BuildClickInfo(entry, targetUnit)
    if not info.spellName then return nil end
    if info.useTarget then
        return "/cast [@target,help,nodead,exists][@player] " .. info.spellName
    end
    return "/cast " .. info.spellName
end

--- Construit les 3 groupes d'animation du texte (pulse/bounce/blink), une
--- seule fois. Un groupe SEPARE par style (plutot que 3 animations dans un
--- seul groupe, qui joueraient toutes en meme temps) : chacun ne contient
--- QUE les animations qui lui correspondent.
--- IMPORTANT : chaque style utilise 2 segments explicites (aller puis
--- retour, SetOrder 1/2) avec SetLooping("REPEAT"), PAS une seule animation
--- avec SetLooping("BOUNCE") -- ce dernier a un bug connu du moteur
--- (un "snap"/saut visible a chaque limite de boucle, confirme en jeu sur le
--- rebond). Le pattern aller-retour explicite est la technique standard pour
--- eviter ce souci.
local function BuildTextAnimGroups()
    local pulseGroup = textContainer:CreateAnimationGroup()
    local pulseOut = pulseGroup:CreateAnimation("Scale")
    pulseOut:SetScale(1.3, 1.3)
    pulseOut:SetDuration(0.45)
    pulseOut:SetSmoothing("IN_OUT")
    pulseOut:SetOrigin("CENTER", 0, 0)
    pulseOut:SetOrder(1)
    local pulseBack = pulseGroup:CreateAnimation("Scale")
    pulseBack:SetScale(1 / 1.3, 1 / 1.3)
    pulseBack:SetDuration(0.45)
    pulseBack:SetSmoothing("IN_OUT")
    pulseBack:SetOrigin("CENTER", 0, 0)
    pulseBack:SetOrder(2)
    pulseGroup:SetLooping("REPEAT")

    local bounceGroup = textContainer:CreateAnimationGroup()
    local bounceOut = bounceGroup:CreateAnimation("Translation")
    bounceOut:SetOffset(0, 6)
    bounceOut:SetDuration(0.3)
    bounceOut:SetSmoothing("OUT")
    bounceOut:SetOrder(1)
    local bounceBack = bounceGroup:CreateAnimation("Translation")
    bounceBack:SetOffset(0, -6)
    bounceBack:SetDuration(0.3)
    bounceBack:SetSmoothing("IN")
    bounceBack:SetOrder(2)
    bounceGroup:SetLooping("REPEAT")

    local blinkGroup = textContainer:CreateAnimationGroup()
    local blinkOut = blinkGroup:CreateAnimation("Alpha")
    blinkOut:SetFromAlpha(1)
    blinkOut:SetToAlpha(0.1)
    blinkOut:SetDuration(0.4)
    blinkOut:SetOrder(1)
    local blinkBack = blinkGroup:CreateAnimation("Alpha")
    blinkBack:SetFromAlpha(0.1)
    blinkBack:SetToAlpha(1)
    blinkBack:SetDuration(0.4)
    blinkBack:SetOrder(2)
    blinkGroup:SetLooping("REPEAT")

    textAnimGroups = { pulse = pulseGroup, bounce = bounceGroup, blink = blinkGroup }
end

--- Demarre/arrete chaque groupe independamment selon son propre toggle --
--- combinables (ex: rebond + clignotement en meme temps), chaque style vit
--- sur son propre groupe d'animation depuis BuildTextAnimGroups.
--- Definie ICI (avant BuildVanishAnimGroup/BuildAppearAnimGroup) car ces
--- dernieres l'appellent depuis leur OnFinished -- une locale n'est visible
--- qu'apres sa propre definition en Lua.
--- Garde-fou centralise : jamais de (re)demarrage pendant qu'une anim
--- d'entree/sortie tourne (2 Translation simultanees parent+enfant se
--- perturbent, cf. BuildAppearAnimGroup) -- couvre TOUS les appelants, y
--- compris RefreshAppearance() qui tourne des le tout premier EnsureFrame(),
--- donc AVANT que l'anim d'apparition n'ait demarre (confirme en jeu : au
--- /reload avec un buff deja manquant, le texte derivait des le 1er affichage).
local function ApplyTextAnimations(cfg)
    if not textAnimGroups then return end
    -- Si le frame n'est meme pas affiche (ex: tout premier RefreshAppearance()
    -- depuis EnsureFrame(), appele AVANT que ShowAlert() ne joue le slide-in
    -- d'entree) : rien a demarrer, ShowAlert/appearAnimGroup s'en chargera au
    -- bon moment. Sans ce garde-fou, le bounce demarrait au tout premier
    -- /reload avec un buff deja manquant, EN MEME TEMPS que l'anim d'entree.
    if not frame:IsShown() then return end
    if (vanishAnimGroup and vanishAnimGroup:IsPlaying()) or (appearAnimGroup and appearAnimGroup:IsPlaying()) then
        return
    end
    local wanted = {
        pulse  = cfg.textAnimPulse  and true or false,
        bounce = cfg.textAnimBounce and true or false,
        blink  = cfg.textAnimBlink  and true or false,
    }
    for k, g in pairs(textAnimGroups) do
        if wanted[k] then
            if not g:IsPlaying() then g:Play() end
        else
            -- Finish() (pas Stop()) : chaque boucle est authoree en 2 segments
            -- qui s'annulent (net zero -- aller +6/+1.3x/alpha-bas, puis retour
            -- exact). Stop() fige le rendu EN PLEIN MILIEU d'un segment (ex:
            -- a mi-course du rebond vers le haut) et CE point devient la base
            -- du prochain Play() -- d'ou une derive qui ne s'arretait jamais
            -- (confirme en jeu : le texte "manquant" montait en continu).
            -- Finish() saute directement a l'etat final defini (net zero).
            g:Finish()
        end
    end
end

--- Reancre `frame` sur son point reel (celui pose par SetPoint, jamais
--- modifie par les Translation) -- une Translation ne laisse PAS le rendu
--- revenir tout seul au point d'ancrage une fois l'anim terminee, elle garde
--- le dernier delta applique comme nouvelle base pour la PROCHAINE anim.
--- Sans ce recalage, vanish+appear enchaines a chaque cycle accumulaient le
--- delta d'un cycle sur l'autre (confirme en jeu : le texte "manquant"
--- montait de plus en plus a chaque disparition/reapparition).
local function ResetFramePosition()
    -- ClearAllPoints/SetPoint sur `frame` (SecureActionButtonTemplate) est une
    -- action PROTEGEE en combat -- l'appeler declenchait ADDON_ACTION_BLOCKED
    -- a chaque HideAlert() en plein combat, plantant la fonction en cours de
    -- route (confirme en jeu : l'alerte restait bloquee/rejouait en boucle
    -- tout le combat). Sans danger de sauter ce recalage purement cosmetique
    -- en combat : la position ne derive de toute façon que si une anim est
    -- interrompue en plein vol, un cas rarissime.
    if InCombatLockdown() then return end
    local point, relTo, relPoint, x, y = frame:GetPoint(1)
    if point then
        frame:ClearAllPoints()
        frame:SetPoint(point, relTo, relPoint, x, y)
    end
end

--- Anime la disparition de l'icone+texte (glissement vers le bas + fondu)
--- quand l'alerte se resout (buff applique/conditions changees), au lieu
--- d'un Hide() sec -- joue sur `frame` entier (icone+texte suivent ensemble,
--- puisque textFS est ancre sur iconTex qui est enfant de frame). Meme
--- pattern 2-segments que les animations de texte : ici un seul segment
--- suffit puisqu'on ne boucle pas (SetLooping par defaut = "NONE"), le
--- OnFinished fait le vrai Hide() + reinitialise l'alpha pour le prochain
--- affichage.
local function BuildVanishAnimGroup()
    local group = frame:CreateAnimationGroup()
    local slide = group:CreateAnimation("Translation")
    slide:SetOffset(0, -24)
    slide:SetDuration(0.3)
    slide:SetSmoothing("IN")
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.3)
    fade:SetSmoothing("IN")
    group:SetScript("OnPlay", ResetFramePosition)
    group:SetScript("OnFinished", function()
        -- frame:Hide() sur ce frame securise (SecureActionButtonTemplate) est
        -- une action PROTEGEE en combat -- confirme en jeu (ADDON_ACTION_BLOCKED
        -- a chaque fin de vanish tombant pendant un combat, ex. buff qui
        -- revient juste apres HideAlert()). On saute Hide()/SetAlpha/reposition
        -- si on est encore en combat : le frame reste affiche mais invisible
        -- (alpha deja a 0 par le fade qui vient de jouer, donc sans impact
        -- visuel) -- le nettoyage differe se fait au PLAYER_REGEN_ENABLED
        -- suivant (cf. eventFrame:OnEvent plus bas).
        if InCombatLockdown() then return end
        frame:Hide()
        frame:SetAlpha(1)
        ResetFramePosition()
    end)
    return group
end

--- Anime l'apparition de l'icone+texte (glissement depuis le bas + fondu),
--- symetrique de BuildVanishAnimGroup. Un Translation ne peut animer QUE
--- depuis le delta courant (0) vers le delta vise -- donc pour un slide-in
--- "depuis en dessous vers le point de repos", le 1er segment (duree quasi
--- nulle) decale d'abord le rendu de -24 (invisible, instantane), puis le
--- 2e segment (visible, 0.3s) ramene ce delta a 0 -- le vrai point d'ancrage
--- du frame n'est jamais touche, seul le rendu est deplace le temps de
--- l'anim (meme logique non destructive que le vanish).
local function BuildAppearAnimGroup()
    local group = frame:CreateAnimationGroup()
    local preShift = group:CreateAnimation("Translation")
    preShift:SetOffset(0, -24)
    preShift:SetDuration(0.01)
    preShift:SetOrder(1)
    local slide = group:CreateAnimation("Translation")
    slide:SetOffset(0, 24)
    slide:SetDuration(0.3)
    slide:SetSmoothing("OUT")
    slide:SetOrder(2)
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.3)
    fade:SetSmoothing("OUT")
    fade:SetOrder(2)
    group:SetScript("OnPlay", ResetFramePosition)
    group:SetScript("OnFinished", function()
        ResetFramePosition()
        -- Ne relance le rebond/pulse/clignotement du texte qu'UNE FOIS le
        -- slide-in fini, jamais en meme temps que lui (cf. commentaire dans
        -- ShowAlert) -- sinon 2 Translation simultanees (parent+enfant) se
        -- perturbent et le texte derive en continu.
        ApplyTextAnimations(Cfg())
    end)
    return group
end

--- Reapplique EN DIRECT tous les reglages d'apparence (taille icone, masque,
--- bordure, police/taille/couleur/position du texte, animation du texte) --
--- appelee une fois a la creation du frame, puis a chaque changement depuis
--- le panneau de reglages (cf. UI/Menus/MissingBuffs.lua).
function MissingBuffs.RefreshAppearance()
    if not frame then return end
    local cfg = Cfg()

    local iSize = cfg.iconSize or ICON_SIZE
    frame:SetSize(iSize, iSize + 20)
    iconTex:SetSize(iSize, iSize)

    local maskOpt = ns.MISSING_BUFF_ICON_MASKS[cfg.iconMaskIndex] or ns.MISSING_BUFF_ICON_MASKS[1]
    pcall(function()
        if maskOpt.atlas then
            maskTex:SetAtlas(maskOpt.atlas, false)
        elseif maskOpt.texture then
            maskTex:SetTexture(maskOpt.texture)
        else
            maskTex:SetTexture(NO_MASK_TEXTURE)
        end
    end)

    local bt = cfg.borderThickness or 2
    borderTex:ClearAllPoints()
    borderTex:SetPoint("TOPLEFT", iconTex, -bt, bt)
    borderTex:SetPoint("BOTTOMRIGHT", iconTex, bt, -bt)
    borderTex:SetColorTexture(unpack(cfg.borderColor or { 1, 0.15, 0.15, 0.9 }))
    borderTex:SetShown(cfg.borderEnabled ~= false)

    ns.ApplyTextOutlineStyle(textFS, slugFS, cfg.textFont or ns.Media.font, cfg.textSize or 12, cfg.textOutlineStyle)
    textFS:SetTextColor(unpack(cfg.textColor or { 1, 0.9, 0.3 }))
    -- L'offset utilisateur se pose sur le CONTENEUR, pas sur textFS lui-meme
    -- (qui reste ancre fixe en son centre) -- cf. commentaire EnsureFrame.
    textContainer:ClearAllPoints()
    textContainer:SetPoint("TOP", iconTex, "BOTTOM", cfg.textOffsetX or 0, cfg.textOffsetY or -2)

    -- L'anneau SLUG suit le masquage global du texte (hideText), en plus de
    -- son propre on/off gere par ApplyTextOutlineStyle ci-dessus.
    if slugFS and cfg.hideText then
        for _, fs in ipairs(slugFS) do fs:Hide() end
    end

    ApplyTextAnimations(cfg)
end

local function EnsureFrame()
    if frame then return frame end
    -- Le frame EST le bouton securise (SecureActionButtonTemplate) : drag et clic
    -- doivent vivre sur le MEME frame, jamais sur deux frames superposes (l'ancien
    -- design avec un frame de drag EnableMouse(true) par-dessus un bouton enfant
    -- se battait pour le hit-test au clic -- cf. PriorityBar.lua:CreateSlotFrame,
    -- seul pattern drag+clic confirme fonctionnel dans cet addon).
    frame = CreateFrame("Button", "AishCoreMissingBuffFrame", UIParent, "SecureActionButtonTemplate")
    frame:SetSize(ICON_SIZE, ICON_SIZE + 20)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForClicks("AnyUp", "AnyDown")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(s)
        if not Cfg().locked then s:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local point, _, relPoint, x, y = s:GetPoint()
        local cfg = Cfg()
        if cfg then cfg.framePoint = { point, relPoint, x, y } end
    end)

    iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(ICON_SIZE, ICON_SIZE)
    iconTex:SetPoint("TOP", frame, "TOP", 0, 0)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Masque de forme (cercle/hexagone/feather...) : toujours un mask
    -- texture present, juste neutre (blanc opaque = pas de decoupe) quand
    -- l'utilisateur choisit "Par defaut" -- evite de creer/detruire le
    -- mask dynamiquement a chaque changement de reglage.
    maskTex = frame:CreateMaskTexture(nil, "OVERLAY")
    maskTex:SetAllPoints(iconTex)
    maskTex:SetTexture(NO_MASK_TEXTURE)
    iconTex:AddMaskTexture(maskTex)

    borderTex = frame:CreateTexture(nil, "BACKGROUND")
    borderTex:SetPoint("TOPLEFT", iconTex, -2, 2)
    borderTex:SetPoint("BOTTOMRIGHT", iconTex, 2, -2)
    borderTex:SetColorTexture(1, 0.15, 0.15, 0.9)

    -- Conteneur du texte : porte textFS + les 8 slugFS comme SES PROPRES
    -- regions (pas celles de `frame` directement) -- necessaire pour que les
    -- animations pulse/bounce/blink (jouees sur CE frame, cf. BuildTextAnimGroups)
    -- cascadent a toutes ces regions. Position (offsets utilisateur) geree
    -- via ce frame dans RefreshAppearance ; textFS/slugFS gardent des ancrages
    -- FIXES en son centre, jamais retouches ensuite.
    textContainer = CreateFrame("Frame", nil, frame)
    textContainer:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
    textContainer:SetSize(1, 1)

    textFS = textContainer:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(textFS, ns.Media.font, 12, "OUTLINE")
    textFS:SetPoint("CENTER", textContainer, "CENTER", 0, 0)
    textFS:SetTextColor(1, 0.9, 0.3)

    -- Ombre "SLUG" (helper partage, cf. Core.lua) : anneau de regions du
    -- MEME conteneur -- cascade donc avec lui a chaque animation.
    slugFS = ns.CreateSlugRing(textContainer, textFS)

    BuildTextAnimGroups()
    vanishAnimGroup = BuildVanishAnimGroup()
    appearAnimGroup = BuildAppearAnimGroup()

    frame:Hide()
    MissingBuffs.RefreshAppearance()
    return frame
end

-- Notifie immediatement Modules/SpellEffects.lua (combos "Buffs manquants",
-- ancres sur AishCoreMissingBuffFrame) du changement d'etat de l'icone --
-- sans ça, l'animation attendait jusqu'a 2s (ticker de secours cote
-- SpellEffects) avant de demarrer/s'arreter, meme quand l'icone changeait
-- instantanement. pcall : SpellEffects peut etre absent/pas encore charge.
local function NotifySpellEffects()
    local SE = _addon.Modules and _addon.Modules.SpellEffects
    if SE and SE.ScanMissingBuffCombos then pcall(SE.ScanMissingBuffCombos) end
end

function MissingBuffs.HideAlert()
    if not frame then return end
    currentAlertSpell = nil
    if not frame:IsShown() then NotifySpellEffects(); return end

    if InCombatLockdown() then
        -- Coupure NETTE, sans animation, des qu'on sait qu'on est en combat --
        -- pas de vanishAnimGroup:Play() ici. Si ShowAlert() vient de tourner
        -- juste avant que le combat ne demarre (appearAnimGroup encore en
        -- cours, slide-in/fade-in de 0.3s), lancer vanishAnimGroup EN PLUS
        -- fait tourner 2 AnimationGroups en meme temps sur le MEME frame
        -- (l'un pousse l'alpha vers 1, l'autre vers 0) -- et comme le vrai
        -- Hide() final est de toute facon differe en combat (action protegee
        -- sur ce SecureActionButtonTemplate), rien ne vient jamais trancher :
        -- le frame reste coince visible tout le combat (confirme en jeu,
        -- alerte "manquant"/"X/Y" figee des l'entree en combat quand un buff
        -- manquait juste avant le pull). Stop les deux anims et force alpha=0
        -- directement, sans course possible.
        if appearAnimGroup and appearAnimGroup:IsPlaying() then appearAnimGroup:Stop() end
        if vanishAnimGroup and vanishAnimGroup:IsPlaying() then vanishAnimGroup:Stop() end
        if textAnimGroups then
            for _, g in pairs(textAnimGroups) do g:Finish() end
        end
        frame:SetAlpha(0)
        NotifySpellEffects()
        return
    end

    -- frame:GetAlpha() > 0.01 : si un HideAlert() precedent (pendant un combat
    -- desormais termine) a deja coupe l'alpha a 0 ci-dessus sans passer par
    -- vanishAnimGroup, on ne veut pas rejouer l'anim de disparition depuis
    -- SetFromAlpha(1) -- ca provoquerait un flash 0->1->0 inutile.
    if vanishAnimGroup and not vanishAnimGroup:IsPlaying() and frame:GetAlpha() > 0.01 then
        -- Stoppe les boucles pulse/bounce/blink du texte AVANT de jouer la
        -- disparition : sinon leur propre Translation/Alpha en cours se
        -- combine avec celle du vanish (et se fait couper en plein cycle par
        -- le Hide() final), ce qui produisait un saut/saccade visible au
        -- 2e passage (confirme en jeu : le texte partait vers le haut au lieu
        -- de suivre le glissement vers le bas).
        if textAnimGroups then
            for _, g in pairs(textAnimGroups) do g:Finish() end
        end
        vanishAnimGroup:Play()
    end
    NotifySpellEffects()
end

-- Debug : n'imprime qu'UNE fois par combat si ShowAlert() est quand meme
-- appele en combat malgre les gardefous en amont (CheckForMissings,
-- RequestCheck, SetPreview) -- ne devrait normalement jamais se produire ;
-- si ca s'affiche, c'est la preuve d'un appelant non repertorie a traquer.
local warnedShowAlertInCombat = false

function MissingBuffs.ShowAlert(spellId, text, clickInfo)
    -- Dernier rempart : quel que soit le chemin d'appel, aucun affichage
    -- reel en combat. Les gardefous en amont devraient deja avoir coupe
    -- court avant d'arriver ici -- celui-ci ferme la porte a tout appelant
    -- non repertorie qui court-circuiterait CheckForMissings/RequestCheck/
    -- SetPreview (confirme en jeu : "manquant" fige en plein combat malgre
    -- ces gardefous, cause exacte non identifiee).
    if InCombatLockdown() then
        if not warnedShowAlertInCombat then
            warnedShowAlertInCombat = true
            print(string.format(
                "|cffff4444[AishCore]|r ShowAlert() appele en combat (spellId=%s, text=%s) -- bloque. Signale ce message si tu le vois.",
                tostring(spellId), tostring(text)))
        end
        MissingBuffs.HideAlert()
        return
    end
    local cfg = Cfg()
    EnsureFrame()
    -- Ne joue le slide-in que pour une VRAIE reapparition (frame cache) --
    -- pas a chaque simple rafraichissement d'icone/texte pendant qu'elle est
    -- deja affichee (ce qui rejouerait le glissement en boucle inutilement).
    local wasHidden = not frame:IsShown()
    local resumedFromVanish = false
    if vanishAnimGroup and vanishAnimGroup:IsPlaying() then
        vanishAnimGroup:Stop()
        frame:SetAlpha(1)
        resumedFromVanish = true
    end
    -- Uniquement sur une vraie transition (frame cachee, ou vanish annule en
    -- cours de route) -- ShowAlert() est appelee tres frequemment tant que le
    -- buff reste manquant (chaque scan), et rappeler ApplyTextAnimations a
    -- CHAQUE appel forcait un Finish() repete sur les styles desactives
    -- (pulse/blink) sur la MEME region (textFS) que le bounce actif, ce qui
    -- perturbait son etat en cours.
    -- Si le vanish a ete annule en cours de route (le buff est revenu manquant
    -- avant la fin de l'anim de sortie) : aucune anim d'entree ne va jouer
    -- (le frame etait deja affiche), donc on relance tout de suite.
    -- Si en revanche c'est une VRAIE reapparition (frame cache -> le slide-in
    -- va jouer), on NE relance PAS ici : le bounce tournerait EN MEME TEMPS
    -- que le glissement d'entree (2 Translation simultanees, parent+enfant)
    -- et se derangeaient mutuellement -- confirme en jeu (retire le bounce
    -- pendant l'anim d'entree/sortie = plus de derive). Cf. appearAnimGroup
    -- OnFinished (BuildAppearAnimGroup) qui relance le texte une fois le
    -- slide-in termine.
    if resumedFromVanish then
        ApplyTextAnimations(cfg)
    end
    -- ClearAllPoints/SetPoint sur ce frame securise = action protegee en
    -- combat -- si le tout premier ShowAlert() de la session tombe pile en
    -- combat (reload/login pendant un pull), on saute le positionnement
    -- sans marquer _positioned : retente au prochain appel hors combat au
    -- lieu de planter.
    if not frame._positioned and not InCombatLockdown() then
        local p = cfg.framePoint
        if p then
            frame:ClearAllPoints()
            frame:SetPoint(p[1] or "CENTER", UIParent, p[2] or p[1] or "CENTER", p[3] or 0, p[4] or 250)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
        end
        frame._positioned = true
    end

    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, spellId)
        if ok then tex = t end
    end
    iconTex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
    textFS:SetShown(not cfg.hideText)
    textFS:SetText(text or "")
    if slugFS then
        local slugOn = (cfg.textOutlineStyle == "SLUG")
        for _, fs in ipairs(slugFS) do fs:SetShown(slugOn and not cfg.hideText) end
    end

    -- Attributs securises (type/spell/macrotext) : modifiables seulement hors combat
    -- (SetAttribute sur un SecureActionButtonTemplate est bloque en combat). Si on
    -- est en combat, on laisse simplement les attributs deja poses -- exactement
    -- comme une barre d'action classique, le clic reste actif sur le dernier sort connu.
    if not InCombatLockdown() then
        if cfg.makeIconClickable and clickInfo and clickInfo.castMacro then
            -- Macro combinee (plusieurs lignes /cast, une par buff de classe
            -- actuellement manquant) : la plupart de ces sorts (enchants d'arme,
            -- Bouclier de foudre, Skyfury...) ne partagent pas le GCD entre eux,
            -- donc un seul clic les applique tous a la suite. Celles qui
            -- partagent le GCD attendront simplement le prochain clic, sans
            -- erreur ni effet de bord.
            pcall(function()
                frame:SetAttribute("type", "macro")
                frame:SetAttribute("macrotext", clickInfo.castMacro)
            end)
        elseif cfg.makeIconClickable and clickInfo and clickInfo.spellName then
            pcall(function()
                if clickInfo.useTarget then
                    frame:SetAttribute("type", "macro")
                    frame:SetAttribute("macrotext",
                        "/cast [@target,help,nodead,exists][@player] " .. clickInfo.spellName)
                else
                    frame:SetAttribute("type", "spell")
                    frame:SetAttribute("spell", clickInfo.spellName)
                end
            end)
        else
            pcall(function() frame:SetAttribute("type", nil) end)
        end
    end

    currentAlertSpell = spellId
    frame:Show()
    if wasHidden and appearAnimGroup then
        appearAnimGroup:Stop()
        appearAnimGroup:Play()
    end
    NotifySpellEffects()
end

--- Retourne le spellId actuellement affiche par l'alerte (nil si masquee).
function MissingBuffs.GetCurrentAlertSpell()
    return currentAlertSpell
end

------------------------------------------------------------------------
-- Preview (menu de reglages) : force l'affichage d'un spell representatif
-- de la classe, en ignorant les vraies conditions -- meme principe que
-- CastBar.SetPreview. previewMode bloque CheckForMissings() tant qu'actif
-- pour que les vrais events (UNIT_AURA...) n'ecrasent pas l'aperçu.
------------------------------------------------------------------------
local previewMode = false

--- `spellId` (optionnel) : force l'apercu sur CE sort precis plutot que le
--- premier de la classe -- utilise par le picker "Animations 3D > Buffs
--- manquants" (UI/SettingsPanel.lua) pour que l'icone+texte affiches
--- correspondent REELLEMENT au sort selectionne pour configurer son combo
--- (avant ce fix, l'apercu montrait toujours le meme sort peu importe la
--- selection, rendant le reglage des animations pour les autres sorts
--- impossible : ScanMissingBuffCombos ne demarre un combo QUE si
--- GetCurrentAlertSpell() correspond exactement au spellID configure).
function MissingBuffs.SetPreview(on, spellId)
    -- Jamais d'apercu force en combat : ShowAlert() ci-dessous ignorerait
    -- sinon le gardefou combat de CheckForMissings (previewMode=true bloque
    -- toute reevaluation), figeant potentiellement l'alerte pour le reste
    -- du combat si le panneau de reglages a ete quitte sans desactiver
    -- l'apercu.
    if on and InCombatLockdown() then return end
    previewMode = on and true or false
    if on then
        local entry
        local resolvedId = spellId
        if not resolvedId then
            local class = _addon._playerClass or select(2, UnitClass("player"))
            local list = class and ns.MISSING_CLASS_BUFFS[class]
            entry = list and list[1]
            resolvedId = entry and entry.spellId
        end
        MissingBuffs.ShowAlert(resolvedId, ns.MISSING_TEXT.MISSING,
            entry and BuildClickInfo(entry, "player"))
    else
        MissingBuffs.HideAlert()
        MissingBuffs.RequestCheck()
    end
end

------------------------------------------------------------------------
-- Orchestration principale : ordre de priorite fixe
-- (stance/aura/attunement de soi -> poisons -> familier -> buff de classe)
------------------------------------------------------------------------
function MissingBuffs.CheckForMissings()
    -- Gardefou dur : rien n'est evalue ni affiche en combat, point final --
    -- PASSE AVANT MEME previewMode. Un apercu (Animations 3D, Settings
    -- Panel) laisse a tort actif (previewMode coince a true, cf. le
    -- "/aishbuffdebug reset" plus bas prevu pour ce cas precis) bloquait
    -- TOUTE reevaluation, y compris ce garde-fou combat lui-meme s'il
    -- passait apres -- l'alerte figee restait alors affichee indefiniment,
    -- combat ou pas, avec un texte/sort qui n'a plus rien a voir avec l'etat
    -- reel (confirme en jeu : "manquant" sur un buff pourtant deja pose).
    -- On force donc aussi la sortie du mode apercu ici : le combat gagne
    -- toujours, quoi qu'il arrive.
    if InCombatLockdown() then
        if previewMode then previewMode = false end
        MissingBuffs.HideAlert()
        return
    end
    if previewMode then return end
    -- Les flags fins showInCombat/showBuffsInCombat plus bas dans cette
    -- fonction ne concernent que la boucle whitelist -- ils ne protegent pas
    -- tout le reste (stance/aura, poisons, familier, buff de classe...) qui
    -- peut continuer a tourner et parfois deconner en combat (lecture
    -- d'aura allie secrete, taint, etc.) pour un affichage qui de toute
    -- facon ne sert a rien en plein combat -- deja coupe court ci-dessus.
    local cfg = Cfg()
    if not cfg.enabled then MissingBuffs.HideAlert(); return end
    if UnitIsDeadOrGhost("player") then MissingBuffs.HideAlert(); return end
    if cfg.ignoreBuffsWhileMounted and IsMounted and IsMounted() then MissingBuffs.HideAlert(); return end
    if cfg.ignoreWhileResting and IsResting and IsResting() then
        -- Exception : une cible attaquable selectionnee en zone
        -- de repos (mannequin d'entrainement, ennemi egare en ville...) reste
        -- un signal utile de "je vais bientot me battre" -- ne pas cacher le
        -- rappel dans ce cas precis. Verifie EXPLICITEMENT hors combat (pas
        -- suppose implicite par IsResting) : si jamais les deux flags se
        -- chevauchent brievement (transition), on prefere le comportement
        -- normal "manquant" plutot qu'un affichage en plein combat en zone
        -- de repos, cas non prevu par le reste du module.
        local targetingAttackable = (not InCombatLockdown())
            and UnitExists("target")
            and not UnitIsDeadOrGhost("target")
            and UnitCanAttack and UnitCanAttack("player", "target")
        if not targetingAttackable then
            MissingBuffs.HideAlert(); return
        end
    end

    local class = _addon._playerClass or select(2, UnitClass("player"))
    if not class then MissingBuffs.HideAlert(); return end

    -- 1) Stance / aura / attunement / forme (priorite max, soi uniquement)
    if class == "WARRIOR" and not cfg.ignoreWarriorStances then
        local missing, opt = ExclusiveGroupMissing(ns.MISSING_WARRIOR_STANCES, cfg.overrideWarriorStance)
        if missing then
            MissingBuffs.ShowAlert(opt.spellId, ns.MISSING_TEXT.USE_STANCE, BuildClickInfo(opt, "player")); return
        end
    elseif class == "PALADIN" and not cfg.ignorePaladinAuras then
        local missing, opt = ExclusiveGroupMissing(ns.MISSING_PALADIN_AURAS, cfg.overridePaladinAura)
        if missing then
            MissingBuffs.ShowAlert(opt.spellId, ns.MISSING_TEXT.USE_AURA, BuildClickInfo(opt, "player")); return
        end
    elseif class == "EVOKER" and _addon._specID == ns.MISSING_AUGMENTATION_EVOKER_SPEC and not cfg.ignoreEvokerAttunements then
        local missing, opt = ExclusiveGroupMissing(ns.MISSING_EVOKER_ATTUNEMENTS, cfg.overrideEvokerAttunement)
        if missing then
            MissingBuffs.ShowAlert(opt.spellId, ns.MISSING_TEXT.USE_ATTUNEMENT, BuildClickInfo(opt, "player")); return
        end
    elseif class == "DRUID" and _addon._specID == ns.MISSING_BALANCE_DRUID_SPEC then
        local e = ns.MISSING_BALANCE_MOONKIN
        if IsEntryLearned(e) and not GetSelfAura(e.spellId) then
            MissingBuffs.ShowAlert(e.spellId, ns.MISSING_TEXT.USE_STANCE, BuildClickInfo(e, "player")); return
        end
    elseif class == "PRIEST" and _addon._specID == ns.MISSING_SHADOW_PRIEST_SPEC then
        local e = ns.MISSING_SHADOW_FORM
        if IsEntryLearned(e) and not SelfHasBuff(e) then
            MissingBuffs.ShowAlert(e.spellId, ns.MISSING_TEXT.USE_STANCE, BuildClickInfo(e, "player")); return
        end
    end

    -- 2) Poisons Voleur (soi uniquement)
    if class == "ROGUE" then
        local missing, opt, textKey = CheckRoguePoisons()
        if missing then
            MissingBuffs.ShowAlert(opt.spellId, ns.MISSING_TEXT[textKey], BuildClickInfo(opt, "player")); return
        end
    end

    -- 3) Familier (Chasseur / Demoniste, soi uniquement)
    if class == "HUNTER" and not cfg.ignoreHunterPets then
        local missing, e, textKey = CheckPetMissing("HUNTER")
        if missing then
            MissingBuffs.ShowAlert(e.spellId, ns.MISSING_TEXT[textKey], BuildClickInfo(e, "player")); return
        end
    elseif class == "WARLOCK" and not cfg.ignoreWarlockPets then
        local missing, e, textKey = CheckPetMissing("WARLOCK")
        if missing then
            MissingBuffs.ShowAlert(e.spellId, ns.MISSING_TEXT[textKey], BuildClickInfo(e, "player")); return
        end
    end

    -- 4) Buff de classe manquant (soi puis allies -- cf. limite en tete de fichier)
    -- On affiche le PREMIER trouve (icone/texte, priorite inchangee) mais on
    -- CHAINE tous les autres actuellement manquants dans la meme macro : la
    -- plupart de ces sorts (enchants d'arme, Bouclier de foudre, Skyfury...)
    -- ne partagent pas le GCD entre eux, donc un seul clic les applique tous
    -- a la suite (meme reflexe que le rebuff manuel classique). Ceux qui
    -- partagent le GCD attendront simplement le clic suivant -- une ligne
    -- /cast qui n'aboutit pas ne casse rien.
    local list = ns.MISSING_CLASS_BUFFS[class]
    if list then
        local primaryEntry, primaryText
        local castLines = {}
        -- Rappel "bientot expire" : priorite STRICTEMENT plus
        -- basse qu'un vrai manquant -- un buff totalement absent reste plus
        -- urgent qu'un buff encore actif mais bientot fini. On retient le
        -- PREMIER candidat expirant trouve pendant la meme boucle, utilise
        -- seulement si aucun primaryEntry (manquant) n'a ete trouve.
        local expiringEntry
        -- cfg.expiringSoonThreshold est en MINUTES (reglage GUI) -- converti
        -- en secondes ici, seule unite comprise par GetSelfBuffExpiringSoon.
        local expiringThreshold = cfg.expiringSoonEnabled and cfg.expiringSoonThreshold and (cfg.expiringSoonThreshold * 60)
        for _, entry in ipairs(list) do
            if IsEntryLearned(entry) and EntryApplies(entry) then
                local missing, unit
                if entry.requiresHealerInGroup then
                    missing, unit = HealerMissingBuff(entry)
                else
                    missing, unit = AnyoneMissingBuff(entry)
                end
                if missing then
                    if not primaryEntry then
                        primaryEntry = entry
                        if entry.showRaidCount and (IsInRaid() or IsInGroup()) then
                            -- Affichage "10/14" (a la Clickable Raid Buff) : combien
                            -- de monde a deja le buff, sur le total applicable a
                            -- portee -- plus parlant qu'un simple "Manquant" pour
                            -- un vrai buff de raid un-par-personne.
                            local have, total = CountBuffCoverage(entry)
                            primaryText = string.format("%d/%d", have, total)
                        else
                            primaryText = ns.MISSING_TEXT[entry.text or "MISSING"]
                        end
                    end
                    local line = BuildCastLine(entry, unit)
                    if line then castLines[#castLines + 1] = line end
                elseif expiringThreshold and not expiringEntry and not primaryEntry then
                    if GetSelfBuffExpiringSoon(entry, expiringThreshold) then
                        expiringEntry = entry
                    end
                end
            end
        end
        if primaryEntry then
            MissingBuffs.ShowAlert(primaryEntry.spellId, primaryText, { castMacro = table.concat(castLines, "\n") })
            return
        end
        if expiringEntry then
            local line = BuildCastLine(expiringEntry, "player")
            MissingBuffs.ShowAlert(expiringEntry.spellId, ns.MISSING_TEXT.EXPIRING_SOON,
                { castMacro = line or "" })
            return
        end
    end

    MissingBuffs.HideAlert()
end

------------------------------------------------------------------------
-- Debounce + evenements (meme principe que MCB.CHECK_THROTTLE : un seul
-- rescan differe si des evenements arrivent en rafale)
------------------------------------------------------------------------
local lastCheckTime = 0
local scanScheduled = false

-- Periode de grace apres PLAYER_ENTERING_WORLD : au teleport d'entree en M+
-- (pas d'ecran de chargement classique, juste une coupure courte), le cache
-- d'auras du joueur n'est pas garanti repeuple des le premier UNIT_AURA/
-- GROUP_ROSTER_UPDATE qui suit -- ces evenements arrivent en rafale et
-- chacun redeclenche RequestCheck. Sans ce garde-fou, un des rescans de la
-- rafale tombe pile pendant la fenetre ou GetPlayerAuraBySpellID ne voit pas
-- encore un buff pourtant bien present -> fausse alerte "manquant" qui
-- clignote/spam le temps que l'etat se stabilise (confirme en jeu : lancement
-- de cle M+ alors que tous les buffs etaient deja poses).
local ENTER_WORLD_GRACE = 1.5
local enterWorldGraceUntil = 0

local function DoCheck()
    scanScheduled = false
    lastCheckTime = GetTime()
    pcall(MissingBuffs.CheckForMissings)
end

function MissingBuffs.RequestCheck()
    local cfg = Cfg()
    if not cfg.enabled then MissingBuffs.HideAlert(); return end
    -- Meme gardefou qu'en tete de CheckForMissings, mais ici AVANT toute
    -- planification : coupe le flot d'evenements combat (UNIT_AURA en
    -- rafale, etc.) qui redeclencherait un DoCheck differe pour rien tant
    -- qu'on est en combat -- plus de "boucle dans le vide".
    if InCombatLockdown() then scanScheduled = false; MissingBuffs.HideAlert(); return end
    local now = GetTime()
    if now < enterWorldGraceUntil then
        if not scanScheduled then
            scanScheduled = true
            C_Timer.After(enterWorldGraceUntil - now, DoCheck)
        end
        return
    end
    local throttle = cfg.debounceThrottle or 0.25
    local elapsed = now - lastCheckTime
    if elapsed >= throttle then
        DoCheck()
    elseif not scanScheduled then
        scanScheduled = true
        C_Timer.After(throttle - elapsed, DoCheck)
    end
end

local eventFrame = CreateFrame("Frame")
local GROUP_EVENTS = {
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "UNIT_AURA",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "UNIT_CONNECTION", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED",
    "UNIT_PET", "UNIT_INVENTORY_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    -- Necessaire pour l'exception "cible attaquable en zone de
    -- repos" (cf. CheckForMissings) : sans cet evenement, cibler/decibler un
    -- mannequin d'entrainement en ville ne redeclenchait aucun rescan.
    "PLAYER_TARGET_CHANGED",
}

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" and frame and frame:IsShown()
       and vanishAnimGroup and not vanishAnimGroup:IsPlaying() and frame:GetAlpha() <= 0.01 then
        -- Rattrape un vanish dont le Hide() final a ete saute pendant le
        -- combat (cf. BuildVanishAnimGroup:OnFinished) : le frame etait reste
        -- affiche-mais-invisible (alpha 0) en attendant la fin du combat.
        frame:Hide()
        frame:SetAlpha(1)
        ResetFramePosition()
    end
    if event == "PLAYER_ENTERING_WORLD" then
        enterWorldGraceUntil = GetTime() + ENTER_WORLD_GRACE
    end
    if event == "UNIT_AURA" then
        if unit and unit ~= "player" and not unit:match("^party") and not unit:match("^raid") then return end
    elseif (event == "UNIT_PET" or event == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then
        return
    end
    MissingBuffs.RequestCheck()
end)

function MissingBuffs.Init()
    for _, event in ipairs(GROUP_EVENTS) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    -- Rescan des le cast termine (pas seulement au UNIT_AURA qui suit) : rend
    -- l'enchainement clic -> sort suivant manquant plus reactif. Le GCD
    -- empeche de tout recast en un seul clic (limite de l'API, pas un choix
    -- d'implementation), mais on avance vite au buff suivant a chaque clic.
    pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    MissingBuffs.RequestCheck()

    -- Rappel "bientot expire" : contrairement au reste du
    -- module, purement event-driven (UNIT_AURA...), le franchissement du
    -- seuil de duree n'est PAS un evenement -- rien ne re-declenche
    -- naturellement un scan pile au bon moment. Ticker leger (2s), inoffensif
    -- quand la fonctionnalite est desactivee (RequestCheck/CheckForMissings
    -- sortent immediatement dans ce cas).
    C_Timer.NewTicker(2, function()
        local cfg = Cfg()
        if cfg.enabled and cfg.expiringSoonEnabled then
            MissingBuffs.RequestCheck()
        end
    end)
end

------------------------------------------------------------------------
-- Helper reglages : (des)ignorer une entree par settingsId
------------------------------------------------------------------------
function MissingBuffs.SetIgnored(settingsId, ignored)
    local cfg = Cfg()
    if not (cfg and settingsId) then return end
    cfg.ignoredSettingsIds = cfg.ignoredSettingsIds or {}
    cfg.ignoredSettingsIds[settingsId] = ignored or nil
    MissingBuffs.RequestCheck()
end

function MissingBuffs.IsIgnored(settingsId)
    local cfg = Cfg()
    return cfg and cfg.ignoredSettingsIds and cfg.ignoredSettingsIds[settingsId] == true
end

------------------------------------------------------------------------
-- Liste plate des spellIds que ce module peut effectivement afficher pour
-- la classe courante (buffs de classe + postures/auras/accords + familiers
-- + poisons selon la classe) -- utilisee par Animations 3D pour restreindre
-- le picker de sorts d'un combo au perimetre reel du module (cf. UI/SettingsPanel.lua).
------------------------------------------------------------------------
function MissingBuffs.GetTriggerSpells()
    local class = _addon._playerClass or select(2, UnitClass("player"))
    if not class then return {} end
    local out, seen = {}, {}
    local function add(id)
        if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
    end

    local list = ns.MISSING_CLASS_BUFFS[class]
    if list then for _, e in ipairs(list) do add(e.spellId) end end

    if class == "WARRIOR" then
        for _, o in ipairs(ns.MISSING_WARRIOR_STANCES) do add(o.spellId) end
    elseif class == "PALADIN" then
        for _, o in ipairs(ns.MISSING_PALADIN_AURAS) do add(o.spellId) end
    elseif class == "EVOKER" then
        for _, o in ipairs(ns.MISSING_EVOKER_ATTUNEMENTS) do add(o.spellId) end
    elseif class == "DRUID" then
        add(ns.MISSING_BALANCE_MOONKIN.spellId)
    elseif class == "PRIEST" then
        add(ns.MISSING_SHADOW_FORM.spellId)
    elseif class == "HUNTER" then
        add(ns.MISSING_HUNTER_PET_DEAD)
        for _, o in ipairs(ns.MISSING_HUNTER_ALL_PETS) do add(o.spellId) end
    elseif class == "WARLOCK" then
        for _, o in ipairs(ns.MISSING_WARLOCK_ALL_PETS) do add(o.spellId) end
    elseif class == "ROGUE" then
        for _, o in ipairs(ns.MISSING_ROGUE_POISONS.nonlethal) do add(o.spellId) end
        for _, o in ipairs(ns.MISSING_ROGUE_POISONS.lethal) do add(o.spellId) end
    end

    return out
end

------------------------------------------------------------------------
-- Debug : /aishbuffdebug [spellId] liste chaque unite du groupe avec le
-- detail du check de portee (UnitInRange vs C_Spell.IsSpellInRange) et la
-- presence du buff -- pour diagnostiquer pourquoi un allie manquant
-- n'apparait pas (suspicion : UnitInRange peu fiable en PARTY, contrairement
-- au RAID).
------------------------------------------------------------------------
SLASH_AISHBUFFDEBUG1 = "/aishbuffdebug"
SlashCmdList["AISHBUFFDEBUG"] = function(msg)
    -- "/aishbuffdebug reset" : force previewMode a false + relance un vrai
    -- scan -- au cas ou l'apercu force (Animations 3D) serait reste bloque
    -- actif (previewMode true empeche TOUTE detection reelle, meme le
    -- self-check le plus basique).
    if msg == "reset" then
        MissingBuffs.SetPreview(false)
        MissingBuffs.RequestCheck()
        print("|cff00ff00[AishCore]|r previewMode force a false, RequestCheck relance.")
        return
    end

    local spellId = tonumber(msg) or 462854 -- Fureur des cieux par defaut
    local entry = { spellId = spellId }
    print(string.format("|cff00ff00[AishCore]|r Debug buff manquant spellId=%d", spellId))
    print(string.format("  IsInRaid=%s IsInGroup=%s previewMode=%s", tostring(IsInRaid()), tostring(IsInGroup()), tostring(previewMode)))

    local function DumpUnit(unit)
        local exists = UnitExists(unit)
        if not exists then return end
        local valid = IsValidAllyUnit(unit)
        local uiOk, uiInRange, uiChecked = pcall(UnitInRange, unit)
        local spOk, spInRange
        if C_Spell and C_Spell.IsSpellInRange then
            spOk, spInRange = pcall(C_Spell.IsSpellInRange, spellId, unit)
        end
        local ciOk, ciNear = pcall(CheckInteractDistance, unit, 1)
        local passes = PassesRangeCheck(unit, entry)
        local hasBuff = valid and UnitHasBuff(unit, entry) or nil
        print(string.format(
            "  %s : exists=%s valid=%s | UnitInRange ok=%s inRange=%s checked=%s | IsSpellInRange ok=%s inRange=%s | CheckInteractDistance ok=%s near=%s | PassesRangeCheck=%s | UnitHasBuff=%s",
            unit, tostring(exists), tostring(valid),
            tostring(uiOk), tostring(uiInRange), tostring(uiChecked),
            tostring(spOk), tostring(spInRange),
            tostring(ciOk), tostring(ciNear),
            tostring(passes), tostring(hasBuff)))
    end

    local ok, err = pcall(function()
        DumpUnit("player")
        for _, unit in ipairs(GetGroupUnits()) do
            DumpUnit(unit)
        end
    end)
    if not ok then
        print("|cffff4444[AishCore]|r Erreur pendant le debug : " .. tostring(err))
    end
end

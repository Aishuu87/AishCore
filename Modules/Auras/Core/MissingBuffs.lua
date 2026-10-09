-- AishUIAura/Core/MissingBuffs.lua
-- Moteur "Buffs manquants" : detecte les buffs/stances/enchants attendus qui
-- sont absents et affiche une alerte pour le sort correspondant.
--
-- LIMITE CONNUE : la lecture des auras d'un allie (party/raid) via AuraUtil.ForEachAura echoue
-- souvent en silence -- payloads d'aura secrets depuis le patch 12.1, plus seulement en combat
-- (cf. Modules/TargetAuras.lua:3-15). La detection SUR SOI reste fiable (GetPlayerAuraBySpellID).
-- Aucune erreur ne remonte si la detection sur les allies echoue, ca degrade vers "rien detecte".
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local MissingBuffs = {}
ns.MissingBuffs = MissingBuffs

-- UPVALUES
local pcall, pairs, ipairs, select = pcall, pairs, ipairs, select
local GetTime, UnitClass = GetTime, UnitClass
local UnitExists, UnitIsUnit, UnitIsConnected, UnitIsDeadOrGhost, UnitIsDead = UnitExists, UnitIsUnit, UnitIsConnected, UnitIsDeadOrGhost, UnitIsDead
local UnitCanAssist, UnitCanAttack, UnitGroupRolesAssigned = UnitCanAssist, UnitCanAttack, UnitGroupRolesAssigned
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local InCombatLockdown, IsMounted, IsResting = InCombatLockdown, IsMounted, IsResting
local C_Timer = C_Timer
local _issecretvalue = issecretvalue

local function IsSecret(v) return _issecretvalue and _issecretvalue(v) or false end

-- Rappel "bientot expire" : le payload d'aura est generalement secret depuis le 12.1 mais pas
-- toujours -- on verifie ETAT PAR ETAT via C_Secrets.ShouldAurasBeSecret()/issecretvalue() sur
-- chaque champ lu et on degrade silencieusement (nil) si illisible a cet instant.
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

-- Config
local function Cfg()
    return (ns.db and ns.db.missingBuffs) or {}
end
MissingBuffs.Cfg = Cfg

-- FOREVER : entrees resolues par NOM (cf. bloc Forever de MissingBuffsData.lua).
-- Une entree portant "casts" n'est jamais liee a un spellID : le rang connu change le spellID, et
-- ces IDs different de Retail. Aura reconnue par "names", sort lance choisi dans "casts".
local function KnownSpellByName(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and info.spellID then return info.spellID, info.name end
    end
    if GetSpellInfo then
        local ok, n, _, _, _, _, _, id = pcall(GetSpellInfo, name)
        if ok and n and id then return id, n end
    end
    return nil
end

-- Liste de noms/spellIDs -> liste de NOMS localises : un nombre est un spellID dont on lit le nom dans
-- la langue du client, une chaine est gardee telle quelle. Mise en cache seulement si tout a resolu.
local _expanded = setmetatable({}, { __mode = "k" })
local function ExpandNames(list)
    local cached = _expanded[list]
    if cached then return cached end
    local out, complete = {}, true
    for _, v in ipairs(list) do
        if type(v) == "number" then
            local n
            if C_Spell and C_Spell.GetSpellName then
                local ok, r = pcall(C_Spell.GetSpellName, v)
                if ok then n = r end
            end
            if not n and GetSpellInfo then
                local ok, r = pcall(GetSpellInfo, v)
                if ok then n = r end
            end
            if n then out[#out + 1] = n else complete = false end
        else
            out[#out + 1] = v
        end
    end
    _expanded[list] = out -- la base de sorts est statique : un ID absent le restera
    return out
end

-- Remplit entry.spellId / _castName avec le premier sort de "casts" reellement connu (tous rangs).
local function ForeverResolve(entry)
    for _, castName in ipairs(ExpandNames(entry.casts)) do
        local id, n = KnownSpellByName(castName)
        if id then
            entry.spellId, entry._castName = id, n
            return true
        end
    end
    entry.spellId, entry._castName = nil, nil
    return false
end

-- Premiere aura benefique de "unit" dont le nom est dans "names" (tous rangs). Renvoie une table
-- { name, expirationTime, sourceUnit } ou nil. ownOnly : ne compte que nos propres instances.
local _nameLookups = setmetatable({}, { __mode = "k" })
local function FindAuraByNames(unit, names, ownOnly)
    names = names and ExpandNames(names)
    if not names or #names == 0 then return nil end
    local lookup = _nameLookups[names]
    if not lookup then
        lookup = {}
        for _, n in ipairs(names) do lookup[n] = true end
        _nameLookups[names] = lookup
    end
    for i = 1, 60 do
        local name, expiration, source
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok or not a then break end
            name, expiration, source = a.name, a.expirationTime, a.sourceUnit
        elseif UnitBuff then
            local ok, n, _, _, _, _, exp, src = pcall(UnitBuff, unit, i)
            if not ok or not n then break end
            name, expiration, source = n, exp, src
        else
            break
        end
        if name and not IsSecret(name) and lookup[name] then
            local mine = true
            if ownOnly then
                mine = source ~= nil and not IsSecret(source) and UnitIsUnit(source, "player")
            end
            if mine then return { name = name, expirationTime = expiration, sourceUnit = source } end
        end
    end
    return nil
end

-- Entrees "kind" (Forever) : objet des sacs ("item") ou munitions equipees ("ammo") sous un seuil.
-- Renvoie manquant, quantite restante.
local function ItemEntryMissing(entry)
    local cfg = Cfg()
    local min = (entry.kind == "item" and cfg.shardsThreshold)
        or (entry.kind == "ammo" and cfg.ammoThreshold) or entry.min or 1
    if entry.kind == "item" then
        local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(entry.item))
            or (GetItemCount and GetItemCount(entry.item)) or 0
        return n < min, n
    elseif entry.kind == "ammo" then
        local ok, slot = pcall(GetInventorySlotInfo, "AmmoSlot")
        if not ok or type(slot) ~= "number" or not GetInventoryItemCount then return false, 0 end
        -- pas d'arme a distance equipee : pas de rappel
        if not GetInventoryItemLink("player", 18) then return false, 0 end
        local n = GetInventoryItemCount("player", slot) or 0
        return n < min, n
    end
    return false, 0
end

-- Une arme (pas un bouclier) est-elle equipee dans cet emplacement ?
local function WeaponInSlot(slot)
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if not id then return false end
    local classID
    if C_Item and C_Item.GetItemInfoInstant then
        classID = select(6, C_Item.GetItemInfoInstant(id))
    end
    if classID == nil then return true end -- inconnu : on suppose une arme
    return classID == 2
end

-- Etat de l'enchantement temporaire d'une arme : renvoie has (true/false, nil = illisible) et le temps
-- restant en ms (ou nil). Forever : GetWeaponEnchantInfo renvoie toujours false pour les imbues et poisons
-- de ce client ; l'API C_Item.GetWeaponEnchantInfo (liste d'enchantements, les permanents exclus) les voit.
-- Retail : comportement d'origine (GetWeaponEnchantInfo).
local ENCHANT_PERMANENT = (Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Permanent) or 1
local function WeaponEnchantState(hand)
    if _addon.IsForever and C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot then
        local ws = hand == "off" and Enum.WeaponSlot.OffHand or Enum.WeaponSlot.MainHand
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
        if ok and type(list) == "table" then
            local has, exp = false, nil
            for _, e in pairs(list) do
                if type(e) == "table" then
                    local h, kind = e.hasEnchant, e.enchantType
                    if IsSecret(h) then return nil end
                    if h and (IsSecret(kind) or kind ~= ENCHANT_PERMANENT) then
                        has = true
                        local t = e.timeLeft
                        if type(t) == "number" and not IsSecret(t) and t > 0 then exp = math.max(exp or 0, t) end
                    end
                end
            end
            return has, exp
        end
    end
    if not GetWeaponEnchantInfo then return nil end
    local ok, hasMain, mainExp, _, _, hasOff, offExp = pcall(GetWeaponEnchantInfo)
    if not ok then return nil end
    local has, exp = hasMain, mainExp
    if hand == "off" then has, exp = hasOff, offExp end
    if IsSecret(has) then return nil end
    if type(exp) ~= "number" or IsSecret(exp) then exp = nil end
    return has == true, exp
end

-- Apprentissage
local function IsEntryLearned(entry)
    if entry.casts then return ForeverResolve(entry) end
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

-- Lecture d'aura SUR SOI (fiable -- contrairement a un instanceID capture via un hook CDM,
-- GetPlayerAuraBySpellID reste utilisable ici)
local function GetSelfAura(spellId)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellId)
    if ok and aura then return aura end
    return nil
end
MissingBuffs.GetSelfAura = GetSelfAura

local function SelfHasBuff(entry)
    if entry.names then return FindAuraByNames("player", entry.names) ~= nil end
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

-- true = present sur SOI mais expire dans <= threshold secondes ; false = marge suffisante (ou
-- sans vraie duree/illisible). A n'appeler que si le buff est deja confirme present par ailleurs
-- (SelfHasBuff/AnyoneMissingBuff) -- ici on ne reverifie que la duree, jamais la presence.
local function GetSelfBuffExpiringSoon(entry, threshold)
    if entry.ignoreDuration then return false end
    if type(threshold) ~= "number" or threshold <= 0 then return false end
    if entry.weaponEnchantSlot then
        local has, expireMS = WeaponEnchantState(entry.weaponEnchantSlot)
        if has ~= true then return false end
        if type(expireMS) ~= "number" or IsSecret(expireMS) then return false end
        return expireMS <= (threshold * 1000)
    end
    if AurasAreSecret() then return false end
    if entry.names then
        local aura = FindAuraByNames("player", entry.names)
        local exp = aura and SafeAuraExpiration(aura)
        if not exp then return false end
        local remain = exp - GetTime()
        return remain > 0 and remain <= threshold
    end
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
    -- Forever : rien a enchanter sans arme dans l'emplacement (main gauche vide ou bouclier)
    if entry.needsWeaponSlot and not WeaponInSlot(entry.needsWeaponSlot) then return true end
    if entry.weaponEnchantSlot ~= "main" and entry.weaponEnchantSlot ~= "off" then return true end
    local has = WeaponEnchantState(entry.weaponEnchantSlot)
    if has == nil then return true end -- illisible : on ne declenche pas une fausse alerte
    return has
end

-- Lecture d'aura sur un ALLIE -- best-effort, cf. bandeau de tete de fichier. Repli "spell
-- activation overlay" natif Blizzard en priorite quand l'entree le supporte (Beacon of
-- Light/Faith) : glow deja calcule cote C++, immunise au taint (meme principe que AddAuraGroup).
local function CheckSpellOverlayMissing(entry)
    if not entry.spellOverlayCompatible then return nil end
    if not (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) then return nil end
    local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, entry.spellId)
    if not ok then return nil end
    return overlayed == true -- true = Blizzard signale qu'il faut relancer -> "manquant" quelque part
end

local function UnitHasBuffRaw(unit, entry)
    -- Payloads d'aura d'un ALLIE quasi-toujours secrets depuis le 12.1 : ForEachAura ne peut
    -- alors jamais lire de spellId, donc on suppose le buff present plutot que de spammer un
    -- faux "manquant" (confirme en jeu : alerte "1/5" en boucle en M+ avec tout le groupe buffe).
    if AurasAreSecret() then return true end
    if entry.names then
        return FindAuraByNames(unit, entry.names, entry.requireOwnCast) ~= nil
    end
    if not (AuraUtil and AuraUtil.ForEachAura) then return false end
    local lookup = { [entry.spellId] = true }
    if entry.extraBuffSpellIds then for _, id in ipairs(entry.extraBuffSpellIds) do lookup[id] = true end end
    if entry.mutuallyExclusiveWith then for _, id in ipairs(entry.mutuallyExclusiveWith) do lookup[id] = true end end
    local found = false
    -- BUG CORRIGE (alerte "1/2" en Delve avec un allie PNJ visiblement buffe alors que
    -- AurasAreSecret() valait false) : la secrecy des payloads d'aura peut rester GRANULAIRE
    -- (certains champs/auras illisibles) meme quand le flag global dit "lisible". Si on croise
    -- au moins une aura au spellId secret pendant le scan, on ne peut pas garantir que le buff
    -- cherche n'est pas derriere -- on degrade vers "suppose present" plutot que "manquant".
    local sawSecretAura = false
    pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, function(aura)
        if not aura then return false end
        local sid = aura.spellId
        -- issecretvalue() doit etre le tout premier test, avant toute comparaison : comparer une
        -- valeur secrete peut propager le taint (a deja bloque un Hide() protege en combat, ADDON_ACTION_BLOCKED).
        if IsSecret(sid) then sawSecretAura = true; return false end
        if sid == nil then return false end
        if not lookup[sid] then return false end
        -- requireOwnCast : ne compte que NOTRE instance (ex. Bouclier de terre, chaque chaman
        -- pose le sien sur une cible differente). sourceUnit absent/secret -> pas suppose "le notre".
        if entry.requireOwnCast then
            local src = aura.sourceUnit
            if IsSecret(src) then return false end
            if src == nil or not UnitIsUnit(src, "player") then return false end
        end
        found = true
        return true
    end, true)
    if found then return true end
    if sawSecretAura then return true end
    return false
end

local function UnitHasBuff(unit, entry)
    if unit == "player" then return SelfHasBuff(entry) end
    local overlayMissing = CheckSpellOverlayMissing(entry)
    if overlayMissing ~= nil then return not overlayMissing end
    return UnitHasBuffRaw(unit, entry)
end

-- Unites du groupe
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

    -- spellbookId (quand present) est LE sort reellement castable/connu (cf. IsEntryLearned) --
    -- entry.spellId n'est parfois que l'ID de l'aura trackee, et interroger IsSpellInRange dessus
    -- peut echouer silencieusement et faire tomber en repli ferme meme quand l'allie est a portee.
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

-- Compte combien d'unites a portee ont deja le buff sur le total qui devrait l'avoir (soi +
-- allies valides), pour l'affichage "10/14" -- uniquement sur les entrees showRaidCount (les
-- "vrais" buffs de raid un-par-personne, pas les buffs a instance unique type Benediction).
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

-- Buff de classe manquant (soi puis allies), variantes onlyOnePerGroup / requiresHealerInGroup / weaponEnchantSlot
local function AnyoneMissingBuff(entry)
    if entry.weaponEnchantSlot then
        if SelfHasWeaponEnchant(entry) then return false end
        return true, "player"
    end

    if entry.onlyOnePerGroup then
        if not entry.ignoreSelf and UnitHasBuff("player", entry) then return false end
        local units = GetGroupUnits()
        -- ignoreSelf = ce buff ne compte jamais sur soi (ex. "buffer un allie") : seul en
        -- groupe/raid, personne a buffer -> pas "manquant" (evite la boucle vide -> true toujours).
        if entry.ignoreSelf and #units == 0 then return false end
        local anyoneInRange = false
        for _, unit in ipairs(units) do
            -- Pas de PassesRangeCheck ici : on verifie si le buff est DEJA applique quelque part,
            -- pas si on peut agir maintenant -- sinon le fail-closed de PassesRangeCheck faisait
            -- croire "encore manquant" alors que tout le monde etait deja couvert.
            if IsValidAllyUnit(unit) and UnitHasBuff(unit, entry) then
                return false
            end
            if IsValidAllyUnit(unit) and PassesRangeCheck(unit, entry) then
                anyoneInRange = true
            end
        end
        -- ignoreSelf cible forcement un allie (clic -> cible) : si personne n'est a portee, rien
        -- n'est actionnable -> pas d'icone plutot que l'afficher en permanence seul dans son coin.
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

-- ═══ Choix multiples : une icone cliquable par proposition ═══════════════════════════════
-- Une "choice" = { key, spellId, spellName, useTarget, macro, icon }
--   key      identifiant stable des combos Animations 3D : spellID Retail, ou spellID de rang 1 sur Forever
--   spellId  spellID reel (icone, portee)
--   spellName / useTarget / macro : ce que fait le clic
local function SpellNameById(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and n then return n end
    end
    return nil
end

-- Propositions d'UNE entree : Forever = un choix par sort de "casts" reellement connu (doublons
-- ID/nom fusionnes) ; Retail = un seul choix (le sort de l'entree).
local function ChoicesFromEntry(entry, targetUnit)
    local out = {}
    if entry.kind then
        out[1] = { icon = entry.icon }
        return out
    end
    local useTarget = (entry.clickingUsesTarget and targetUnit and targetUnit ~= "player") and true or false
    if entry.casts then
        local seen = {}
        for _, v in ipairs(entry.casts) do
            local key, name
            if type(v) == "number" then key = v; name = SpellNameById(v) else name = v end
            if name then
                local id, castName = KnownSpellByName(name)
                if id and not seen[id] then
                    seen[id] = true
                    out[#out + 1] = { key = key or id, spellId = id, spellName = castName, useTarget = useTarget }
                end
            end
        end
    elseif entry.spellId then
        out[1] = { key = entry.spellId, spellId = entry.spellId,
                   spellName = SpellNameById(entry.clickableId or entry.spellId), useTarget = useTarget }
    end
    return out
end

-- Groupe de choix equivalents (stances, auras, accords, poisons, familiers, demons) : toutes les
-- options apprises et non ignorees, dans l'ordre de la liste.
local function GroupChoices(list)
    local out = {}
    for _, opt in ipairs(list) do
        if not (opt.settingsId and MissingBuffs.IsIgnored(opt.settingsId)) and IsEntryLearned(opt) then
            for _, c in ipairs(ChoicesFromEntry(opt, "player")) do out[#out + 1] = c end
        end
    end
    return out
end

-- Groupe mutuellement exclusif : rien a alerter si UNE des options est deja active, sinon toutes
-- les options lancables en propositions. nil = pas d'alerte.
local function ExclusiveGroupAlert(list)
    for _, opt in ipairs(list) do
        if opt.names then
            if FindAuraByNames("player", opt.names) then return nil end
        elseif GetSelfAura(opt.spellId) then
            return nil
        end
    end
    local choices = GroupChoices(list)
    if #choices == 0 then return nil end
    return choices
end

-- Forever : poison = enchantement d'arme, un seul par arme (pas de groupe letal/non-letal).
-- Renvoie (choix, cle de texte) ou nil.
local function CheckRoguePoisonsForever()
    local cfg = Cfg()
    if cfg.ignoreLethalPoisons and cfg.ignoreNonlethalPoisons then return nil end
    local choices = GroupChoices(ns.MISSING_ROGUE_POISONS.forever)
    if #choices == 0 then return nil end -- aucun poison connu
    if WeaponInSlot(16) and WeaponEnchantState("main") == false then return choices, "APPLY_LETHAL" end
    if WeaponInSlot(17) and WeaponEnchantState("off") == false then return choices, "APPLY_LETHAL" end
    return nil
end

local function CheckRoguePoisons()
    if _addon.IsForever then return CheckRoguePoisonsForever() end
    local cfg = Cfg()
    if not cfg.ignoreNonlethalPoisons then
        local choices = ExclusiveGroupAlert(ns.MISSING_ROGUE_POISONS.nonlethal)
        if choices then return choices, "APPLY_NONLETHAL" end
    end
    if not cfg.ignoreLethalPoisons then
        local choices = ExclusiveGroupAlert(ns.MISSING_ROGUE_POISONS.lethal)
        if choices then return choices, "APPLY_LETHAL" end
    end
    return nil
end

-- Grimoire de sacrifice (108503, Demoniste) : sacrifie DELIBEREMENT le
-- familier contre le buff 196099 --
local GRIMOIRE_OF_SACRIFICE_BUFF = 196099
local function HasSacrificedPetForGrimoire()
    if ns.MISSING_WARLOCK_SACRIFICE_NAMES then
        return FindAuraByNames("player", ns.MISSING_WARLOCK_SACRIFICE_NAMES) ~= nil
    end
    return GetSelfAura(GRIMOIRE_OF_SACRIFICE_BUFF) ~= nil
end

-- Loup solitaire (466867, Chasseur Precision) : talent qui permet de jouer
-- DELIBEREMENT sans familier -- ne jamais rappeler "familier manquant" si actif.
local HUNTER_LONE_WOLF_TALENT = 466867
local function HasHunterLoneWolfTalent()
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return false end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, HUNTER_LONE_WOLF_TALENT)
    return ok and known == true
end

-- Renvoie (choix, cle de texte) ou nil : familier a ressusciter, ou tous les familiers/demons invocables.
local function CheckPetMissing(class)
    if class == "HUNTER" and HasHunterLoneWolfTalent() then
        return nil
    end
    if UnitExists("pet") then
        if class == "HUNTER" and UnitIsDead("pet") then
            local revive = ns.MISSING_HUNTER_REVIVE_ENTRY or { spellId = ns.MISSING_HUNTER_PET_DEAD }
            if revive.casts and not IsEntryLearned(revive) then return nil end
            local choices = ChoicesFromEntry(revive, "player")
            if #choices > 0 then return choices, "REVIVE_PET" end
        end
        return nil
    end
    if class == "WARLOCK" and HasSacrificedPetForGrimoire() then
        return nil
    end
    local list = (class == "HUNTER") and ns.MISSING_HUNTER_ALL_PETS or ns.MISSING_WARLOCK_ALL_PETS
    local choices = GroupChoices(list)
    if #choices == 0 then return nil end -- aucun familier invocable (bas niveau)
    return choices, "SUMMON_PET"
end

-- Applicabilite d'une entree (spe / combat / ignoree par l'utilisateur)
local function EntryApplies(entry)
    if entry.specIds then
        local specID = _addon._specID
        if not specID then return false end
        local ok = false
        for _, sid in ipairs(entry.specIds) do if sid == specID then ok = true; break end end
        if not ok then return false end
    end
    local cfg = Cfg()
    if entry.settingsId and MissingBuffs.IsIgnored(entry.settingsId) then
        return false
    end
    if InCombatLockdown() then
        -- Les buffs de raid "10/14" scannent tout le groupe/raid, peu fiable en combat
        -- (visibilite des auras entre sous-groupes, valeurs secretes) -- verrouillage absolu,
        -- ignore meme "Afficher en combat".
        if entry.showRaidCount then return false end
        if not (entry.showInCombat or (entry.whitelist and cfg.showBuffsInCombat)) then
            return false
        end
    end
    return true
end

-- Affichage : icone + texte, deplacable, bouton securise cliquable
local ICON_SIZE = 64
local NO_MASK_TEXTURE = "Interface\\Buttons\\WHITE8x8" -- blanc opaque = pas de decoupe visible
local frame, iconTex, textFS, borderTex, maskTex
local textContainer -- frame porteur de textFS + slugFS, cf. commentaire ci-dessous
local textAnimGroups -- { pulse=, bounce=, blink= } -- cf. BuildTextAnimGroups
local vanishAnimGroup -- glissement + fondu joue avant le Hide() reel, cf. BuildVanishAnimGroup
local appearAnimGroup -- glissement + fondu joue au Show(), cf. BuildAppearAnimGroup
local slugFS -- 8 FontStrings d'ombre "SLUG" en anneau derriere textFS, cf. BuildSlugShadow
local currentAlertSpell
local slots = {}              -- icones cliquables (une par proposition), enfants de `frame`
local currentAlertKeys = {}   -- cle de combo -> icone affichee
local activeSlotCount = 1
local currentSig              -- signature des cles affichees (re-ancrage des combos)

-- IMPORTANT : un AnimationGroup cree directement sur une region (FontString) n'anime que cette
-- region -- ça ne se propage pas a une region juste ancree dessus via SetPoint (contrairement a
-- un FRAME, ou la transformation descend sur tout son contenu). D'ou `textContainer` : un frame
-- qui porte textFS ET son anneau SLUG comme ses propres regions, pour que pulse/bounce/blink
-- cascadent aux deux. Anneau gere par les helpers partages ns.CreateSlugRing / ns.ApplyTextOutlineStyle / ns.SetSlugRingText (Core.lua).

local function BuildClickInfo(entry, targetUnit)
    local clickId = entry.clickableId or entry.spellId
    local spellName = entry._castName
    if not spellName and C_Spell and C_Spell.GetSpellName then
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

--- Construit les 3 groupes d'animation du texte (pulse/bounce/blink), une seule fois -- un groupe
--- separe par style pour qu'ils ne jouent pas tous ensemble. Chaque style utilise 2 segments
--- explicites (aller/retour, SetOrder 1/2) + SetLooping("REPEAT") plutot que SetLooping("BOUNCE"),
--- qui a un bug moteur connu (snap visible a chaque limite de boucle).
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

--- Demarre/arrete chaque groupe independamment selon son propre toggle (combinables, ex. rebond
--- + clignotement en meme temps). Definie ici (avant BuildVanishAnimGroup/BuildAppearAnimGroup)
--- car ces dernieres l'appellent depuis leur OnFinished. Garde-fou centralise : jamais de
--- (re)demarrage pendant qu'une anim d'entree/sortie tourne (2 Translation simultanees
--- parent+enfant se perturbent) -- couvre aussi RefreshAppearance() au tout premier EnsureFrame().
local function ApplyTextAnimations(cfg)
    if not textAnimGroups then return end
    -- Frame pas encore affiche (1er RefreshAppearance() avant que ShowAlert() ne joue le
    -- slide-in) : rien a demarrer, ShowAlert/appearAnimGroup s'en chargera au bon moment.
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
            -- Finish() (pas Stop()) : chaque boucle est authoree en 2 segments qui s'annulent
            -- (net zero). Stop() fige le rendu en plein milieu d'un segment, qui devient la base
            -- du prochain Play() -- d'ou une derive qui ne s'arretait jamais. Finish() saute
            -- directement a l'etat final (net zero).
            g:Finish()
        end
    end
end

--- Reancre `frame` sur son point reel (pose par SetPoint) -- une Translation ne revient pas
--- toute seule au point d'ancrage a la fin, elle garde le dernier delta comme base pour la
--- prochaine anim. Sans ce recalage, vanish+appear enchaines accumulaient le delta d'un cycle
--- sur l'autre (le texte "manquant" montait de plus en plus a chaque cycle).
local function ResetFramePosition()
    -- ClearAllPoints/SetPoint sur `frame` (SecureActionButtonTemplate) est protege en combat --
    -- declenchait ADDON_ACTION_BLOCKED a chaque HideAlert() en combat. Sans danger de sauter ce
    -- recalage cosmetique en combat : la position ne derive que si une anim est interrompue en plein vol.
    if InCombatLockdown() then return end
    local point, relTo, relPoint, x, y = frame:GetPoint(1)
    if point then
        frame:ClearAllPoints()
        frame:SetPoint(point, relTo, relPoint, x, y)
    end
end

--- Anime la disparition de l'icone+texte (glissement vers le bas + fondu) quand l'alerte se
--- resout, au lieu d'un Hide() sec -- joue sur `frame` entier (icone+texte suivent ensemble,
--- textFS etant ancre sur iconTex, enfant de frame). Un seul segment suffit (pas de loop),
--- OnFinished fait le vrai Hide() + reinitialise l'alpha pour le prochain affichage.
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
        -- frame:Hide() sur ce frame securise (SecureActionButtonTemplate) est protege en combat
        -- (ADDON_ACTION_BLOCKED). On saute Hide()/SetAlpha/reposition en combat : le frame reste
        -- affiche mais invisible (alpha deja a 0) -- le nettoyage differe au PLAYER_REGEN_ENABLED suivant.
        if InCombatLockdown() then frame:SetAlpha(0); return end
        frame:Hide()
        frame:SetAlpha(1)
        ResetFramePosition()
    end)
    return group
end

--- Anime l'apparition (glissement depuis le bas + fondu), symetrique de BuildVanishAnimGroup. Un
--- Translation ne peut animer que depuis le delta courant (0) vers le delta vise -- donc le 1er
--- segment (duree quasi nulle) decale d'abord le rendu de -24 (invisible), puis le 2e (0.3s)
--- ramene ce delta a 0 : le point d'ancrage reel n'est jamais touche.
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
        -- Ne relance le rebond/pulse/clignotement qu'une fois le slide-in fini, jamais en meme
        -- temps -- sinon 2 Translation simultanees (parent+enfant) se perturbent et le texte derive.
        ApplyTextAnimations(Cfg())
    end)
    return group
end

--- Une icone de proposition : bouton securise (clic = son propre sort), enfant de `frame` qui reste le
--- repere de position / glisser-deposer et le porteur des animations d'entree/sortie.
local function EnsureSlot(i)
    if slots[i] then return slots[i] end
    local sl = CreateFrame("Button", "AishCoreMissingBuffSlot" .. i, frame, "SecureActionButtonTemplate")
    sl:SetFrameLevel(frame:GetFrameLevel() + 2)
    sl:EnableMouse(true)
    sl:RegisterForClicks("AnyUp", "AnyDown")
    sl:RegisterForDrag("LeftButton")
    sl:SetScript("OnDragStart", function()
        if not Cfg().locked then frame:StartMoving() end
    end)
    sl:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local point, _, relPoint, x, y = frame:GetPoint()
        local cfg = Cfg()
        if cfg then cfg.framePoint = { point, relPoint, x, y } end
    end)
    sl.icon = sl:CreateTexture(nil, "ARTWORK")
    sl.icon:SetAllPoints()
    sl.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    sl.mask = sl:CreateMaskTexture(nil, "OVERLAY")
    sl.mask:SetAllPoints(sl.icon)
    sl.mask:SetTexture(NO_MASK_TEXTURE)
    sl.icon:AddMaskTexture(sl.mask)
    sl.border = sl:CreateTexture(nil, "BACKGROUND")
    sl:SetScript("OnEnter", function(self)
        if not self._spellId then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        pcall(GameTooltip.SetSpellByID, GameTooltip, self._spellId)
        GameTooltip:Show()
    end)
    sl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slots[i] = sl
    return sl
end

local function ApplySlotAppearance(sl, cfg)
    local maskOpt = ns.MISSING_BUFF_ICON_MASKS[cfg.iconMaskIndex] or ns.MISSING_BUFF_ICON_MASKS[1]
    pcall(function()
        if maskOpt.atlas then
            sl.mask:SetAtlas(maskOpt.atlas, false)
        elseif maskOpt.texture then
            sl.mask:SetTexture(maskOpt.texture)
        else
            sl.mask:SetTexture(NO_MASK_TEXTURE)
        end
    end)
    local bt = cfg.borderThickness or 2
    sl.border:ClearAllPoints()
    sl.border:SetPoint("TOPLEFT", sl.icon, -bt, bt)
    sl.border:SetPoint("BOTTOMRIGHT", sl.icon, bt, -bt)
    sl.border:SetColorTexture(unpack(cfg.borderColor or { 1, 0.15, 0.15, 0.9 }))
    sl.border:SetShown(cfg.borderEnabled ~= false)
end

--- Dispose n icones cote a cote, centrees sur `frame` (la 2e de 3 reste a la position d'une icone
--- seule), legerement espacees pour eviter les faux clics. Hors combat uniquement (frames securises).
local function LayoutSlots(n)
    n = math.max(1, n or 1)
    local cfg = Cfg()
    local iSize = cfg.iconSize or ICON_SIZE
    local gap = math.max(6, math.floor(iSize * 0.15))
    frame:SetSize(n * iSize + (n - 1) * gap, iSize + 20)
    for i = 1, n do
        local sl = EnsureSlot(i)
        sl:SetSize(iSize, iSize)
        sl:ClearAllPoints()
        sl:SetPoint("TOP", frame, "TOP", (i - (n + 1) / 2) * (iSize + gap), 0)
        sl:Show()
    end
    for i = n + 1, #slots do slots[i]:Hide() end
    activeSlotCount = n
end

--- Reapplique EN DIRECT tous les reglages d'apparence (taille icone, masque,
--- bordure, police/taille/couleur/position du texte, animation du texte) --
--- appelee une fois a la creation du frame, puis a chaque changement depuis
--- le panneau de reglages (cf. UI/Menus/MissingBuffs.lua).
function MissingBuffs.RefreshAppearance()
    if not frame then return end
    local cfg = Cfg()

    -- iconTex n'est plus qu'une ancre invisible (texte centre sous la rangee d'icones) ; les icones
    -- visibles et cliquables sont les slots.
    local iSize = cfg.iconSize or ICON_SIZE
    iconTex:SetSize(iSize, iSize)
    iconTex:SetAlpha(0)
    borderTex:Hide()
    if not InCombatLockdown() then LayoutSlots(activeSlotCount) end
    for _, sl in ipairs(slots) do ApplySlotAppearance(sl, cfg) end

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
    -- Le frame EST le bouton securise (SecureActionButtonTemplate) : drag et clic doivent vivre
    -- sur le MEME frame (un frame de drag separe par-dessus se bat pour le hit-test au clic --
    -- cf. PriorityBar.lua:CreateSlotFrame, seul pattern drag+clic confirme fonctionnel ici).
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

    -- Conteneur du texte : porte textFS + les 8 slugFS comme ses propres regions (pas celles de
    -- `frame` directement), pour que pulse/bounce/blink (BuildTextAnimGroups) cascadent a tout.
    -- Position (offsets utilisateur) geree via ce frame dans RefreshAppearance ; textFS/slugFS
    -- gardent des ancrages fixes en son centre.
    textContainer = CreateFrame("Frame", nil, frame)
    textContainer:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
    textContainer:SetSize(1, 1)
    -- Au-dessus des icones de proposition (slots, niveau frame+2) : sinon un decalage du texte vers
    -- le haut passait derriere elles.
    textContainer:SetFrameLevel(frame:GetFrameLevel() + 10)

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

-- Positionne le frame une seule fois (cf. frame._positioned) -- extrait de ShowAlert pour etre
-- reutilisable par SyncBurningRush, qui ne passe jamais par ShowAlert mais a quand meme besoin
-- d'un frame ancre a une position valide (sinon son combo retombe sur UIParent 0,0).
-- ClearAllPoints/SetPoint est protege en combat : si le tout premier appel tombe en combat
-- (reload/login pendant un pull), on saute sans marquer _positioned, on retente au prochain appel.
local function PositionFrameIfNeeded()
    if not frame or frame._positioned or InCombatLockdown() then return end
    local cfg = Cfg()
    local p = cfg.framePoint
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1] or "CENTER", UIParent, p[2] or p[1] or "CENTER", p[3] or 0, p[4] or 250)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
    end
    frame._positioned = true
end

-- Notifie immediatement Modules/SpellEffects.lua (combos "Buffs manquants") du changement d'etat
-- de l'icone -- sans ça, l'animation attendait jusqu'a 2s (ticker de secours). pcall : SpellEffects
-- peut etre absent/pas encore charge.
local function NotifySpellEffects()
    local SE = _addon.Modules and _addon.Modules.SpellEffects
    if SE and SE.ScanMissingBuffCombos then pcall(SE.ScanMissingBuffCombos) end
end

-- "Ruee Ardente" (Demoniste) : cas "buff manquant" INVERSE -- contrairement a ns.MISSING_CLASS_BUFFS
-- (alerte tant qu'absent), celui-ci alerte tant que le buff EST present (facile d'oublier de le
-- retirer). Jamais d'icone/texte, seul le combo configure se declenche, et volontairement jamais
-- gate par InCombatLockdown/cible/zone de repos -- demande utilisateur explicite, d'ou un event frame dedie.
-- Presence : meme chaine que les combos "Auras a tracker" (IsAuraActiveViaCDM pris tel quel). Repli
-- GetSelfAura uniquement pour "no-cdm-entry" : peut seulement AJOUTER une presence, jamais la maintenir.
function MissingBuffs.IsBurningRushActive()
    local cfg = Cfg()
    if not cfg.enabled or not cfg.burningRushAlert then return false end
    local class = _addon._playerClass or select(2, UnitClass("player"))
    if class ~= "WARLOCK" then return false end

    local SE = _addon.Modules and _addon.Modules.SpellEffects
    if SE and SE.IsAuraActiveViaCDM then
        local dbg = {}
        local ok, active = pcall(SE.IsAuraActiveViaCDM, "player", ns.MISSING_WARLOCK_BURNING_RUSH, dbg)
        if ok and dbg.tier and dbg.tier ~= "no-cdm-entry" then
            return active and true or false
        end
    end

    -- Le CDM ne connait pas encore ce sort (jamais lie a une icone cette
    -- session) : lecture directe, fiable hors combat, nil en combat -- et un
    -- nil vaut ici "absent", pas "on garde l'ancienne valeur".
    local aura = GetSelfAura(ns.MISSING_WARLOCK_BURNING_RUSH)
    return aura ~= nil
end

local burningRushWasActive = false
--- Recalcule l'etat et notifie SpellEffects uniquement sur transition (evite un rescan combo a
--- chaque UNIT_AURA sans rapport). Expose pour que le toggle du panneau de reglages force une
--- resync immediate au lieu d'attendre le prochain UNIT_AURA.
function MissingBuffs.SyncBurningRush()
    local active = MissingBuffs.IsBurningRushActive()
    if active ~= burningRushWasActive then
        burningRushWasActive = active
        -- Le combo s'ancre sur AishCoreMissingBuffFrame, qui n'existe/n'est positionne qu'apres
        -- un premier ShowAlert() classique -- or ce sort ne passe jamais par ShowAlert. Sans
        -- forcer sa creation+position ici, StartMissingBuffSustained retomberait sur UIParent
        -- (mauvaise position/echelle) faute de frame pret. Le frame reste cache dans les deux cas.
        if active then EnsureFrame(); PositionFrameIfNeeded() end
        NotifySpellEffects()
    end
end

-- UNIT_AURA (self) + PLAYER_ENTERING_WORLD : redeclenche SyncBurningRush a chaque changement
-- d'aura sur soi, en plus du ticker de secours 2s cote SpellEffects.lua. UNIT_SPELLCAST_SUCCEEDED :
-- resync supplementaire au moment ou le buff est applique (l'UNIT_AURA peut arriver avant que le
-- CDM ait lie l'icone). PLAYER_REGEN_ENABLED/DISABLED : la source autoritaire change a chaque
-- bascule de combat (canal CDM en combat, lecture directe hors combat), donc resync immediate.
do
    local burningRushFrame = CreateFrame("Frame")
    burningRushFrame:RegisterEvent("UNIT_AURA")
    burningRushFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    burningRushFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    burningRushFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    pcall(burningRushFrame.RegisterUnitEvent, burningRushFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    -- Re-sync DIFFERE apres chaque event : rien ne garantit que le CDM ait deja propage le
    -- changement (SetAuraInstanceInfo) au moment ou UNIT_AURA nous parvient. Un seul timer en
    -- vol a la fois (brPending) : UNIT_AURA peut arriver en rafale.
    --
    -- Preparation de l'ancre, hors combat et sans attendre le buff : le combo s'ancre sur un
    -- SecureActionButtonTemplate dont le positionnement est protege, impossible en combat. Sans
    -- preparation prealable, un /reload suivi d'un combat laisse ce frame sans SetPoint. Prepare
    -- a chaque occasion hors combat, independamment de la presence du buff ; le frame reste cache.
    local function PrepareAnchorIfPossible()
        if InCombatLockdown() then return end
        local cfg = Cfg()
        if not cfg.enabled or not cfg.burningRushAlert then return end
        local class = _addon._playerClass or select(2, UnitClass("player"))
        if class ~= "WARLOCK" then return end
        EnsureFrame()
        PositionFrameIfNeeded()
    end
    -- Expose pour le panneau de reglages : cocher l'option puis entrer en combat avant le
    -- prochain PLAYER_ENTERING_WORLD/REGEN_ENABLED laisserait sinon l'ancre non preparee.
    MissingBuffs.PrepareBurningRushAnchor = PrepareAnchorIfPossible

    local brPending = false
    burningRushFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and unit ~= "player" then return end
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            PrepareAnchorIfPossible()
        end
        MissingBuffs.SyncBurningRush()
        if not brPending then
            brPending = true
            C_Timer.After(0.5, function()
                brPending = false
                MissingBuffs.SyncBurningRush()
            end)
        end
    end)
end

function MissingBuffs.HideAlert()
    if not frame then return end
    currentAlertSpell = nil
    wipe(currentAlertKeys)
    currentSig = nil
    if not frame:IsShown() then NotifySpellEffects(); return end

    if InCombatLockdown() then
        -- Sortie animee comme hors combat : seuls Hide()/SetPoint/attributs du frame securise sont
        -- proteges, pas les animations. L'anim d'entree encore en cours est stoppee d'abord (sinon 2
        -- AnimationGroups pousseraient l'alpha en sens inverse) ; le Hide() final est saute en combat
        -- (cf. BuildVanishAnimGroup:OnFinished) et rattrape au PLAYER_REGEN_ENABLED.
        if appearAnimGroup and appearAnimGroup:IsPlaying() then appearAnimGroup:Stop() end
        if textAnimGroups then
            for _, g in pairs(textAnimGroups) do g:Finish() end
        end
        if vanishAnimGroup and not vanishAnimGroup:IsPlaying() then
            if frame:GetAlpha() > 0.01 then vanishAnimGroup:Play() else frame:SetAlpha(0) end
        end
        NotifySpellEffects()
        return
    end

    -- GetAlpha() > 0.01 : si un HideAlert() precedent (combat desormais termine) a deja coupe
    -- l'alpha a 0 sans passer par vanishAnimGroup, on evite de rejouer l'anim depuis
    -- SetFromAlpha(1), ce qui provoquerait un flash 0->1->0.
    if vanishAnimGroup and not vanishAnimGroup:IsPlaying() and frame:GetAlpha() > 0.01 then
        -- Stoppe les boucles pulse/bounce/blink AVANT la disparition : sinon leur propre
        -- Translation/Alpha en cours se combine avec le vanish et produit un saut visible.
        if textAnimGroups then
            for _, g in pairs(textAnimGroups) do g:Finish() end
        end
        vanishAnimGroup:Play()
    end
    NotifySpellEffects()
end

-- Debug : n'imprime qu'une fois par combat si ShowAlert() est quand meme appele en combat malgre
-- les gardefous en amont (CheckForMissings, RequestCheck, SetPreview) -- ne devrait jamais arriver.
local warnedShowAlertInCombat = false

function MissingBuffs.ShowAlertChoices(choices, text)
    -- Dernier rempart : aucun affichage reel en combat, quel que soit le chemin d'appel -- ferme
    -- la porte a tout appelant non repertorie qui court-circuiterait les gardefous en amont.
    if InCombatLockdown() then
        if not warnedShowAlertInCombat then
            warnedShowAlertInCombat = true
            print(string.format(
                "|cffff4444[AishCore]|r ShowAlert() appele en combat (text=%s) -- bloque. Signale ce message si tu le vois.",
                tostring(text)))
        end
        MissingBuffs.HideAlert()
        return
    end
    if not choices or #choices == 0 then MissingBuffs.HideAlert(); return end
    local cfg = Cfg()
    EnsureFrame()
    -- Ne joue le slide-in que pour une VRAIE reapparition (frame cache), pas a chaque simple
    -- rafraichissement pendant qu'elle est deja affichee.
    local wasHidden = not frame:IsShown()
    local resumedFromVanish = false
    if vanishAnimGroup and vanishAnimGroup:IsPlaying() then
        vanishAnimGroup:Stop()
        frame:SetAlpha(1)
        resumedFromVanish = true
    end
    -- Relance ApplyTextAnimations uniquement sur une vraie transition (ShowAlert tourne a chaque
    -- scan, rappeler ici a chaque fois perturberait l'etat du bounce en cours). Si le vanish a
    -- ete annule en route, le frame etait deja affiche donc on relance tout de suite ; si c'est
    -- une vraie reapparition (slide-in a venir), on NE relance PAS ici -- le bounce se
    -- derangerait avec le glissement d'entree (cf. appearAnimGroup OnFinished, qui relance apres le slide-in).
    if resumedFromVanish then
        ApplyTextAnimations(cfg)
    end
    PositionFrameIfNeeded()

    -- Une icone par proposition, centrees ; texte unique dessous
    local n = #choices
    LayoutSlots(n)
    wipe(currentAlertKeys)
    local keys = {}
    for i, c in ipairs(choices) do
        local sl = slots[i]
        local tex = c.icon
        if not tex and c.spellId and C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, c.spellId)
            if ok then tex = t end
        end
        sl.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        sl._spellId = c.spellId
        ApplySlotAppearance(sl, cfg)
        -- Attributs securises (type/spell/macrotext) : hors combat seulement, garanti plus haut.
        pcall(function()
            if cfg.makeIconClickable and c.macro and c.macro ~= "" then
                sl:SetAttribute("type", "macro")
                sl:SetAttribute("macrotext", c.macro)
            elseif cfg.makeIconClickable and c.spellName then
                if c.useTarget then
                    sl:SetAttribute("type", "macro")
                    sl:SetAttribute("macrotext", "/cast [@target,help,nodead,exists][@player] " .. c.spellName)
                else
                    sl:SetAttribute("type", "spell")
                    sl:SetAttribute("spell", c.spellName)
                end
            else
                sl:SetAttribute("type", nil)
            end
        end)
        if c.key then
            currentAlertKeys[c.key] = sl
            keys[#keys + 1] = tostring(c.key)
        end
    end
    textFS:SetShown(not cfg.hideText)
    textFS:SetText(text or "")
    if slugFS then
        local slugOn = (cfg.textOutlineStyle == "SLUG")
        for _, fs in ipairs(slugFS) do fs:SetShown(slugOn and not cfg.hideText) end
    end

    currentAlertSpell = choices[1].key
    -- Les combos sont ancres sur l'icone de LEUR sort : si la rangee change (nombre ou ordre), on
    -- les relance pour qu'ils suivent leur icone.
    local sig = table.concat(keys, ",")
    if sig ~= currentSig then
        currentSig = sig
        local SE = _addon.Modules and _addon.Modules.SpellEffects
        if SE and SE.ResetMissingBuffCombos then pcall(SE.ResetMissingBuffCombos) end
    end
    frame:Show()
    if wasHidden and appearAnimGroup then
        appearAnimGroup:Stop()
        appearAnimGroup:Play()
    end
    NotifySpellEffects()
end

--- Compat : alerte a une seule icone (apercu des reglages, appels historiques).
function MissingBuffs.ShowAlert(spellId, text, clickInfo)
    local c = { key = spellId, spellId = spellId }
    if clickInfo then
        c.spellName, c.useTarget, c.macro, c.icon =
            clickInfo.spellName, clickInfo.useTarget, clickInfo.castMacro, clickInfo.icon
    end
    MissingBuffs.ShowAlertChoices({ c }, text)
end

--- Retourne le spellId actuellement affiche par l'alerte (nil si masquee).
function MissingBuffs.GetCurrentAlertSpell()
    return currentAlertSpell
end

--- Toutes les cles de combo actuellement affichees (une par icone) : table cle -> icone.
function MissingBuffs.GetCurrentAlertSpells()
    return currentAlertKeys
end

--- Icone qui affiche cette cle (ancre des combos Animations 3D), ou le frame global par defaut.
function MissingBuffs.GetSlotForSpell(key)
    return currentAlertKeys[key] or frame
end

-- Preview (menu de reglages) : force l'affichage d'un spell representatif de la classe, en
-- ignorant les vraies conditions -- meme principe que CastBar.SetPreview. previewMode bloque
-- CheckForMissings() tant qu'actif pour que les vrais events n'ecrasent pas l'apercu.
local previewMode = false

--- `spellId` (optionnel) : force l'apercu sur CE sort precis plutot que le premier de la classe --
--- utilise par le picker "Animations 3D > Buffs manquants" pour que l'icone+texte affiches
--- correspondent au sort selectionne (ScanMissingBuffCombos ne demarre un combo que si
--- GetCurrentAlertSpell() correspond exactement au spellID configure).
function MissingBuffs.SetPreview(on, spellId)
    -- Jamais d'apercu force en combat : sinon previewMode=true bloque toute reevaluation dans
    -- CheckForMissings, figeant potentiellement l'alerte pour le reste du combat.
    if on and InCombatLockdown() then return end
    previewMode = on and true or false
    if on then
        local entry
        local resolvedId = spellId
        if resolvedId == ns.MISSING_PET_PASSIVE_KEY then
            MissingBuffs.ShowAlertChoices({ { key = resolvedId, icon = ns.MISSING_PET_PASSIVE_ICON } },
                ns.MISSING_TEXT.PET_PASSIVE)
            return
        end
        if not resolvedId then
            local class = _addon._playerClass or select(2, UnitClass("player"))
            local list = class and ns.MISSING_CLASS_BUFFS[class]
            entry = list and list[1]
            if entry and entry.casts then IsEntryLearned(entry) end
            resolvedId = entry and entry.spellId
        end
        MissingBuffs.ShowAlert(resolvedId, ns.MISSING_TEXT.MISSING,
            entry and BuildClickInfo(entry, "player"))
    else
        MissingBuffs.HideAlert()
        MissingBuffs.RequestCheck()
    end
end

-- Alerte familier EN COMBAT : le frame principal est un bouton securise (SetPoint/Show/attributs refuses en
-- combat). Deux cas :
--  * l'alerte du familier manquant etait DEJA affichee a l'entree en combat : on la laisse telle quelle (cliquable,
--    animations 3D et texte inchanges) ;
--  * elle apparait en plein combat (familier mort, renvoye, passif...) : copie purement visuelle (frame non
--    securise, non cliquable) ancree au meme point, avec les memes animations d'entree / sortie.
-- La detection n'utilise que UnitExists / UnitIsDead / GetPetActionInfo, aucune valeur secrete.
local combatFrame, combatIcons, combatText, combatVanish, combatAppear
local combatTextBox, combatTextAnims
local combatSig

-- Memes styles que le texte de l'alerte normale (pulse / rebond / clignotement), sur le conteneur du texte de la copie
local function BuildCombatTextAnims(box)
    local pulse = box:CreateAnimationGroup()
    local po = pulse:CreateAnimation("Scale")
    po:SetScale(1.3, 1.3); po:SetDuration(0.45); po:SetSmoothing("IN_OUT"); po:SetOrigin("CENTER", 0, 0); po:SetOrder(1)
    local pb = pulse:CreateAnimation("Scale")
    pb:SetScale(1 / 1.3, 1 / 1.3); pb:SetDuration(0.45); pb:SetSmoothing("IN_OUT"); pb:SetOrigin("CENTER", 0, 0); pb:SetOrder(2)
    pulse:SetLooping("REPEAT")
    local bounce = box:CreateAnimationGroup()
    local bo = bounce:CreateAnimation("Translation")
    bo:SetOffset(0, 6); bo:SetDuration(0.3); bo:SetSmoothing("OUT"); bo:SetOrder(1)
    local bb = bounce:CreateAnimation("Translation")
    bb:SetOffset(0, -6); bb:SetDuration(0.3); bb:SetSmoothing("IN"); bb:SetOrder(2)
    bounce:SetLooping("REPEAT")
    local blink = box:CreateAnimationGroup()
    local lo = blink:CreateAnimation("Alpha")
    lo:SetFromAlpha(1); lo:SetToAlpha(0.1); lo:SetDuration(0.4); lo:SetOrder(1)
    local lb = blink:CreateAnimation("Alpha")
    lb:SetFromAlpha(0.1); lb:SetToAlpha(1); lb:SetDuration(0.4); lb:SetOrder(2)
    blink:SetLooping("REPEAT")
    return { pulse = pulse, bounce = bounce, blink = blink }
end

local function ApplyCombatTextAnims(cfg)
    if not combatTextAnims then return end
    -- jamais pendant l'animation d'entree / sortie (2 Translation parent + enfant se perturbent)
    if combatAppear:IsPlaying() or combatVanish:IsPlaying() then return end
    local wanted = { pulse = cfg.textAnimPulse, bounce = cfg.textAnimBounce, blink = cfg.textAnimBlink }
    for k, g in pairs(combatTextAnims) do
        if wanted[k] then
            if not g:IsPlaying() then g:Play() end
        else
            g:Finish()
        end
    end
end

local function StopCombatTextAnims()
    if combatTextAnims then for _, g in pairs(combatTextAnims) do g:Finish() end end
end

local function EnsureCombatFrame()
    if combatFrame then return combatFrame end
    combatFrame = CreateFrame("Frame", nil, UIParent)
    combatFrame:SetFrameStrata("HIGH")
    combatFrame:EnableMouse(false)
    combatFrame:Hide()
    combatIcons = {}
    combatTextBox = CreateFrame("Frame", nil, combatFrame)
    combatTextBox:SetSize(1, 1)
    combatText = combatTextBox:CreateFontString(nil, "OVERLAY")
    combatText:SetPoint("CENTER", combatTextBox, "CENTER", 0, 0)
    combatTextAnims = BuildCombatTextAnims(combatTextBox)
    -- Sortie : glissement vers le bas + fondu (comme l'alerte normale)
    combatVanish = combatFrame:CreateAnimationGroup()
    local vs = combatVanish:CreateAnimation("Translation")
    vs:SetOffset(0, -24); vs:SetDuration(0.3); vs:SetSmoothing("IN")
    local vf = combatVanish:CreateAnimation("Alpha")
    vf:SetFromAlpha(1); vf:SetToAlpha(0); vf:SetDuration(0.3); vf:SetSmoothing("IN")
    combatVanish:SetScript("OnFinished", function()
        StopCombatTextAnims()
        combatFrame:Hide()
        combatFrame:SetAlpha(1)
    end)
    -- Entree : glissement depuis le bas + fondu
    combatAppear = combatFrame:CreateAnimationGroup()
    local ap = combatAppear:CreateAnimation("Translation")
    ap:SetOffset(0, -24); ap:SetDuration(0.01); ap:SetOrder(1)
    local as = combatAppear:CreateAnimation("Translation")
    as:SetOffset(0, 24); as:SetDuration(0.3); as:SetSmoothing("OUT"); as:SetOrder(2)
    local af = combatAppear:CreateAnimation("Alpha")
    af:SetFromAlpha(0); af:SetToAlpha(1); af:SetDuration(0.3); af:SetSmoothing("OUT"); af:SetOrder(2)
    combatAppear:SetScript("OnFinished", function() ApplyCombatTextAnims(Cfg()) end)
    return combatFrame
end

function MissingBuffs.HideCombatPet()
    if combatSig then
        -- L'alerte de substitution ne porte plus : on retire aussi ses cles (combos Animations 3D)
        combatSig = nil
        currentAlertSpell = nil
        wipe(currentAlertKeys)
        currentSig = nil
        NotifySpellEffects()
    end
    if combatFrame and combatFrame:IsShown() and not combatVanish:IsPlaying() then
        if combatAppear:IsPlaying() then combatAppear:Stop() end
        StopCombatTextAnims()
        combatVanish:Play()
    end
end

local function ShowCombatPet(choices, text, sig)
    if not frame then EnsureFrame() end
    local cfg = Cfg()
    local cf = EnsureCombatFrame()
    local iSize = cfg.iconSize or ICON_SIZE
    local gap = math.max(6, math.floor(iSize * 0.15))
    local n = #choices
    cf:ClearAllPoints()
    cf:SetSize(n * iSize + (n - 1) * gap, iSize + 20)
    -- Position du profil, lue directement (comme PositionFrameIfNeeded) : ancrer sur le frame principal le
    -- plaçait en haut de l'ecran quand celui-ci n'avait pas encore ete positionne (jamais affiche hors combat).
    local fp = cfg.framePoint
    if fp then
        cf:SetPoint(fp[1] or "CENTER", UIParent, fp[2] or fp[1] or "CENTER", fp[3] or 0, fp[4] or 250)
    else
        cf:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
    end
    local bt = cfg.borderThickness or 2
    for i = 1, n do
        local ic = combatIcons[i]
        if not ic then
            ic = { border = cf:CreateTexture(nil, "BACKGROUND"), tex = cf:CreateTexture(nil, "ARTWORK") }
            ic.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            ic.mask = cf:CreateMaskTexture(nil, "OVERLAY")
            ic.mask:SetAllPoints(ic.tex)
            ic.mask:SetTexture(NO_MASK_TEXTURE)
            ic.tex:AddMaskTexture(ic.mask)
            combatIcons[i] = ic
        end
        local c = choices[i]
        local tex = c.icon
        if not tex and c.spellId and C_Spell and C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, c.spellId)
            if ok then tex = t end
        end
        ic.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        ic.tex:SetSize(iSize, iSize)
        ic.tex:ClearAllPoints()
        ic.tex:SetPoint("TOP", cf, "TOP", (i - (n + 1) / 2) * (iSize + gap), 0)
        ic.tex:Show()
        ic.border:ClearAllPoints()
        ic.border:SetPoint("TOPLEFT", ic.tex, -bt, bt)
        ic.border:SetPoint("BOTTOMRIGHT", ic.tex, bt, -bt)
        ic.border:SetColorTexture(unpack(cfg.borderColor or { 1, 0.15, 0.15, 0.9 }))
        ic.border:SetShown(cfg.borderEnabled ~= false)
        -- Meme forme d'icone que l'alerte normale
        local maskOpt = ns.MISSING_BUFF_ICON_MASKS[cfg.iconMaskIndex] or ns.MISSING_BUFF_ICON_MASKS[1]
        pcall(function()
            if maskOpt.atlas then ic.mask:SetAtlas(maskOpt.atlas, false)
            elseif maskOpt.texture then ic.mask:SetTexture(maskOpt.texture)
            else ic.mask:SetTexture(NO_MASK_TEXTURE) end
        end)
    end
    for i = n + 1, #combatIcons do combatIcons[i].tex:Hide(); combatIcons[i].border:Hide() end
    ns.ApplyFont(combatText, cfg.textFont or ns.Media.font, cfg.textSize or 12, "OUTLINE")
    combatText:SetTextColor(unpack(cfg.textColor or { 1, 0.9, 0.3 }))
    combatTextBox:ClearAllPoints()
    combatTextBox:SetPoint("TOP", cf, "TOP", cfg.textOffsetX or 0, -(iSize + 2) + (cfg.textOffsetY or -2) + 2)
    combatText:SetText(text or "")
    combatText:SetShown(not cfg.hideText)

    local wasHidden = not cf:IsShown()
    if combatVanish:IsPlaying() then combatVanish:Stop(); cf:SetAlpha(1); wasHidden = false end
    cf:Show()
    if wasHidden then combatAppear:Stop(); combatAppear:Play() else ApplyCombatTextAnims(cfg) end

    -- Cles exposees aux combos Animations 3D : ancrees sur la copie visuelle
    if combatSig ~= sig then
        combatSig = sig
        wipe(currentAlertKeys)
        for _, c in ipairs(choices) do if c.key then currentAlertKeys[c.key] = cf end end
        currentAlertSpell = choices[1].key
        currentSig = sig
        local SE = _addon.Modules and _addon.Modules.SpellEffects
        if SE and SE.ResetMissingBuffCombos then pcall(SE.ResetMissingBuffCombos) end
        NotifySpellEffects()
    end
end

-- Familier vivant en mode Passif ? (bouton Passif de la barre du familier actif)
local function PetIsPassive()
    if not (UnitExists("pet") and not UnitIsDead("pet") and GetPetActionInfo) then return false end
    for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
        local ok, name, _, isToken, isActive = pcall(GetPetActionInfo, i)
        if ok and isToken and name == "PET_MODE_PASSIVE" and isActive == true then return true end
    end
    return false
end
local PASSIVE_ICON = ns.MISSING_PET_PASSIVE_ICON

-- Appelee en combat (evenements + ticker). Renvoie true si une alerte familier est en place (le
-- frame principal ne doit alors pas etre masque).
function MissingBuffs.CheckPetInCombat()
    local cfg = Cfg()
    local class = _addon._playerClass or select(2, UnitClass("player"))
    local ignored = (class == "HUNTER" and cfg.ignoreHunterPets) or (class == "WARLOCK" and cfg.ignoreWarlockPets)
    if not cfg.enabled or ignored or (class ~= "HUNTER" and class ~= "WARLOCK")
       or UnitIsDeadOrGhost("player") or (cfg.ignoreBuffsWhileMounted and IsMounted and IsMounted())
       or (IsMounted and IsMounted())
       or (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()) then
        MissingBuffs.HideCombatPet(); return false
    end
    local choices, text
    local ok, ch, tk = pcall(CheckPetMissing, class)
    if ok and ch and #ch > 0 then
        choices = ch
        text = ns.MISSING_TEXT[tk]
    elseif PetIsPassive() then
        choices = { { key = ns.MISSING_PET_PASSIVE_KEY, icon = PASSIVE_ICON } }
        text = ns.MISSING_TEXT.PET_PASSIVE
    end
    if not choices then MissingBuffs.HideCombatPet(); return false end

    local keys = {}
    for i, c in ipairs(choices) do keys[i] = tostring(c.key) end
    local sig = table.concat(keys, ",")
    -- Alerte reelle deja affichee pour ces memes propositions : on n'y touche pas
    if frame and not combatSig and frame:IsShown() and frame:GetAlpha() > 0.01 and currentSig == sig then
        if combatFrame and combatFrame:IsShown() then combatFrame:Hide() end
        return true
    end
    -- Une autre alerte reelle visible (buff manquant...) est coupee avant la copie
    if frame and frame:IsShown() and frame:GetAlpha() > 0.01 and not combatSig then
        MissingBuffs.HideAlert()
    end
    pcall(ShowCombatPet, choices, text, sig)
    return true
end

-- Pierres du Demoniste (Retail) : pierre de soins en sac, pierre d'ame posee sur quelqu'un.
local HEALTHSTONE_ITEMS = { 5512, 224464 }  -- Healthstone, Demonic Healthstone
local SPELL_CREATE_HEALTHSTONE = 6201
local SPELL_SOULSTONE = 20707
-- Aura de pierre d'ame sur n'importe qui du groupe (soi inclus), sans exigence de portee
local SOULSTONE_ENTRY = { spellId = SPELL_SOULSTONE, onlyOnePerGroup = true, playerCanHaveMultiples = true,
                          ignoreRangeCheck = true, ignoreDuration = true }

local function IsKnownSpell(id)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return false end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
    return ok and known == true
end

-- Contexte d'affichage des alertes de pierres : hors combat, en instance OU avec une cible attaquable
local function StoneAlertContext()
    if InCombatLockdown() then return false end
    if IsInInstance() then return true end
    return UnitExists("target") and not UnitIsDeadOrGhost("target")
        and UnitCanAttack("player", "target") and true or false
end

-- Renvoie (choix, texte) ou nil
local function CheckWarlockStones(cfg)
    if _addon.IsForever or not StoneAlertContext() then return nil end

    if not cfg.ignoreSoulstoneAlert and IsKnownSpell(SPELL_SOULSTONE) and AnyoneMissingBuff(SOULSTONE_ENTRY) then
        return { { key = SPELL_SOULSTONE, spellId = SPELL_SOULSTONE,
                   spellName = SpellNameById(SPELL_SOULSTONE), useTarget = true } },
            ns.MISSING_TEXT.NO_SOULSTONE
    end

    if not cfg.ignoreHealthstoneAlert and IsKnownSpell(SPELL_CREATE_HEALTHSTONE) then
        local count = 0
        for _, id in ipairs(HEALTHSTONE_ITEMS) do
            count = count + ((C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or 0)
        end
        if count == 0 then
            return { { key = SPELL_CREATE_HEALTHSTONE, spellId = SPELL_CREATE_HEALTHSTONE,
                       spellName = SpellNameById(SPELL_CREATE_HEALTHSTONE) } },
                ns.MISSING_TEXT.NO_HEALTHSTONE
        end
    end
    return nil
end

local fallRecheck = false

-- Orchestration principale : ordre de priorite fixe (stance/aura/attunement de soi -> poisons ->
-- familier -> buff de classe)
function MissingBuffs.CheckForMissings()
    -- Gardefou dur : rien n'est evalue ni affiche en combat, passe avant meme previewMode -- un
    -- apercu laisse a tort actif (previewMode coince a true) bloquerait toute reevaluation, y
    -- compris ce garde-fou s'il passait apres, figeant l'alerte indefiniment. On force donc aussi
    -- la sortie du mode apercu ici.
    if InCombatLockdown() then
        if previewMode then previewMode = false end
        if not MissingBuffs.CheckPetInCombat() then MissingBuffs.HideAlert() end
        return
    end
    MissingBuffs.HideCombatPet()
    if previewMode then return end
    -- Cle Mythique+ active : payloads d'aura secrets (anti-triche), meme la lecture sur soi peut
    -- rater un buff pourtant actif. Plutot que fiabiliser la lecture secrete (fragile), on coupe
    -- simplement le module pendant la cle -- on est cense arriver deja buffe avant le compte a rebours.
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        MissingBuffs.HideAlert(); return
    end
    -- Les flags showInCombat/showBuffsInCombat plus bas ne concernent que la boucle whitelist --
    -- deja coupe court ci-dessus pour tout le reste, qui ne sert de toute facon a rien en combat.
    local cfg = Cfg()
    if not cfg.enabled then MissingBuffs.HideAlert(); return end
    if UnitIsDeadOrGhost("player") then MissingBuffs.HideAlert(); return end
    -- Forme de voyage Druide (783) : IsMounted() renvoie false dessus alors qu'elle sert au meme
    -- usage (deplacement rapide) -- traitee comme une monture pour ce toggle.
    if cfg.ignoreBuffsWhileMounted and ((IsMounted and IsMounted()) or GetSelfAura(783)) then
        MissingBuffs.HideAlert(); return
    end
    if cfg.ignoreWhileResting and IsResting and IsResting() then
        -- Exception : une cible attaquable selectionnee en zone de repos reste un signal utile
        -- de "je vais bientot me battre". Verifie explicitement hors combat, pas suppose
        -- implicite par IsResting.
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

    -- En chute (souvent juste apres une descente de monture) : le familier n'est pas encore revenu,
    -- aucune nouvelle alerte tant qu'on n'a pas touche le sol. Une alerte deja affichee reste en
    -- l'etat ; pas d'evenement a l'atterrissage, d'ou le rescan differe.
    if IsFalling and IsFalling() then
        if not fallRecheck then
            fallRecheck = true
            C_Timer.After(0.3, function() fallRecheck = false; MissingBuffs.RequestCheck() end)
        end
        return
    end

    -- 1) Stance / aura / attunement / forme (priorite max, soi uniquement). Toutes les options
    -- apprises sont proposees (une icone chacune).
    if class == "WARRIOR" and not cfg.ignoreWarriorStances then
        local choices = ExclusiveGroupAlert(ns.MISSING_WARRIOR_STANCES)
        if choices then MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT.USE_STANCE); return end
    elseif class == "PALADIN" and not cfg.ignorePaladinAuras then
        local choices = ExclusiveGroupAlert(ns.MISSING_PALADIN_AURAS)
        if choices then MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT.USE_AURA); return end
    elseif class == "EVOKER" and _addon._specID == ns.MISSING_AUGMENTATION_EVOKER_SPEC and not cfg.ignoreEvokerAttunements then
        local choices = ExclusiveGroupAlert(ns.MISSING_EVOKER_ATTUNEMENTS)
        if choices then MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT.USE_ATTUNEMENT); return end
    elseif class == "DRUID" and _addon._specID == ns.MISSING_BALANCE_DRUID_SPEC and not cfg.ignoreDruidForms then
        local e = ns.MISSING_BALANCE_MOONKIN
        if IsEntryLearned(e) and not GetSelfAura(e.spellId) then
            MissingBuffs.ShowAlertChoices(ChoicesFromEntry(e, "player"), ns.MISSING_TEXT.USE_STANCE); return
        end
    elseif class == "PRIEST" and _addon._specID == ns.MISSING_SHADOW_PRIEST_SPEC then
        local e = ns.MISSING_SHADOW_FORM
        if IsEntryLearned(e) and not SelfHasBuff(e) then
            MissingBuffs.ShowAlertChoices(ChoicesFromEntry(e, "player"), ns.MISSING_TEXT.USE_STANCE); return
        end
    end

    -- 2) Poisons Voleur (soi uniquement) : tous les poisons connus en propositions
    if class == "ROGUE" then
        local choices, textKey = CheckRoguePoisons()
        if choices then MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT[textKey]); return end
    end

    -- 3) Familier (Chasseur / Demoniste, soi uniquement) : tous les familiers / demons invocables
    -- En monture (skyriding compris) : pas d'alerte familier, il n'est pas invoque et ne reapparait pas a l'atterrissage
    local flying = IsMounted and IsMounted()
    if flying then
        -- rien
    elseif class == "HUNTER" and not cfg.ignoreHunterPets then
        local choices, textKey = CheckPetMissing("HUNTER")
        if choices then MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT[textKey]); return end
    elseif class == "WARLOCK" and not cfg.ignoreWarlockPets then
        local choices, textKey = CheckPetMissing("WARLOCK")
        if choices then MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT[textKey]); return end
    end

    -- 3b) Familier en Passif avec une cible attaquable : clic = mode Assistance (hors combat : bouton
    -- securise normal ; l'alerte reste en place et cliquable a l'entree en combat)
    if not flying and ((class == "HUNTER" and not cfg.ignoreHunterPets) or (class == "WARLOCK" and not cfg.ignoreWarlockPets)) then
        if PetIsPassive() and UnitExists("target") and not UnitIsDeadOrGhost("target")
           and UnitCanAttack("player", "target") then
            MissingBuffs.ShowAlertChoices({ { key = ns.MISSING_PET_PASSIVE_KEY, icon = PASSIVE_ICON, macro = "/petassist" } },
                ns.MISSING_TEXT.PET_PASSIVE)
            return
        end
    end

    -- 3c) Pierre de soins / pierre d'ame (Demoniste)
    if class == "WARLOCK" then
        local choices, text = CheckWarlockStones(cfg)
        if choices then MissingBuffs.ShowAlertChoices(choices, text); return end
    end

    -- 4) Buff de classe manquant (soi puis allies -- cf. limite en tete de fichier)
    -- On affiche le PREMIER trouve (texte, priorite inchangee). Une entree a plusieurs sorts connus
    -- (Forever : enchantements, armures, Aspects...) et les enchantements d'arme equivalents de la meme
    -- arme (Retail) donnent une icone par proposition. Sinon, on CHAINE tous les autres buffs
    -- actuellement manquants dans la meme macro : la plupart de ces sorts ne partagent pas le GCD,
    -- un seul clic les applique tous a la suite ; ceux qui le partagent attendront le clic suivant.
    local list = ns.MISSING_CLASS_BUFFS[class]
    if list then
        local primaryEntry, primaryText, primaryUnit
        local castLines = {}
        local weaponMissing = {}   -- [slot] = entrees d'enchantement d'arme manquantes de cet emplacement
        -- Rappel "bientot expire" : priorite strictement plus basse qu'un vrai manquant. On
        -- retient le premier candidat expirant trouve, utilise seulement si aucun primaryEntry.
        local expiringEntry
        -- cfg.expiringSoonThreshold est en minutes (reglage GUI), converti ici en secondes.
        local expiringThreshold = cfg.expiringSoonEnabled and cfg.expiringSoonThreshold and (cfg.expiringSoonThreshold * 60)
        for _, entry in ipairs(list) do
            if (entry.kind or IsEntryLearned(entry)) and EntryApplies(entry) then
                local missing, unit, itemCount
                if entry.kind then
                    missing, itemCount = ItemEntryMissing(entry)
                    unit = "player"
                elseif entry.requiresHealerInGroup then
                    missing, unit = HealerMissingBuff(entry)
                else
                    missing, unit = AnyoneMissingBuff(entry)
                end
                if missing then
                    if entry.weaponEnchantSlot then
                        local w = weaponMissing[entry.weaponEnchantSlot] or {}
                        weaponMissing[entry.weaponEnchantSlot] = w
                        w[#w + 1] = entry
                    end
                    if not primaryEntry then
                        primaryEntry, primaryUnit = entry, unit
                        if entry.kind then
                            primaryText = string.format("%s (%d)", ns.MISSING_TEXT[entry.text] or "", itemCount or 0)
                        elseif entry.showRaidCount and (IsInRaid() or IsInGroup()) then
                            -- Affichage "10/14" : combien de monde a deja le buff sur le total
                            -- applicable a portee -- plus parlant qu'un simple "Manquant".
                            local have, total = CountBuffCoverage(entry)
                            primaryText = string.format("%d/%d", have, total)
                        else
                            primaryText = ns.MISSING_TEXT[entry.text or "MISSING"]
                        end
                    end
                    local line = (not entry.kind) and BuildCastLine(entry, unit) or nil
                    if line then castLines[#castLines + 1] = line end
                elseif expiringThreshold and not expiringEntry and not primaryEntry then
                    if GetSelfBuffExpiringSoon(entry, expiringThreshold) then
                        expiringEntry = entry
                    end
                end
            end
        end
        if primaryEntry then
            local choices
            local sameHand = primaryEntry.weaponEnchantSlot and weaponMissing[primaryEntry.weaponEnchantSlot]
            if sameHand then
                choices = {}
                local seenKey = {}
                for _, we in ipairs(sameHand) do
                    for _, c in ipairs(ChoicesFromEntry(we, "player")) do
                        if not seenKey[c.key] then seenKey[c.key] = true; choices[#choices + 1] = c end
                    end
                end
            else
                choices = ChoicesFromEntry(primaryEntry, primaryUnit)
                -- Une seule icone : le clic enchaine tous les buffs manquants (macro), comme avant
                if #choices == 1 and not primaryEntry.kind and #castLines > 0 then
                    choices[1].macro = table.concat(castLines, "\n")
                end
            end
            if #choices > 0 then
                MissingBuffs.ShowAlertChoices(choices, primaryText)
                return
            end
        end
        if expiringEntry then
            local choices = ChoicesFromEntry(expiringEntry, "player")
            if #choices > 0 then
                MissingBuffs.ShowAlertChoices(choices, ns.MISSING_TEXT.EXPIRING_SOON)
                return
            end
        end
    end

    MissingBuffs.HideAlert()
end

-- Debounce + evenements (meme principe que MCB.CHECK_THROTTLE : un seul rescan differe si des
-- evenements arrivent en rafale)
local lastCheckTime = 0
local scanScheduled = false

-- Periode de grace apres PLAYER_ENTERING_WORLD : au teleport d'entree en M+, le cache d'auras
-- n'est pas garanti repeuple des le premier UNIT_AURA/GROUP_ROSTER_UPDATE qui suit (rafale
-- d'evenements) -- sans ce garde-fou, un rescan tombe pendant la fenetre ou GetPlayerAuraBySpellID
-- ne voit pas encore un buff pourtant present, d'ou une fausse alerte qui clignote/spam.
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
    -- Meme gardefou qu'en tete de CheckForMissings, mais ici avant toute planification : coupe
    -- le flot d'evenements combat qui redeclencherait un DoCheck differe pour rien.
    if InCombatLockdown() then
        scanScheduled = false
        if not MissingBuffs.CheckPetInCombat() then MissingBuffs.HideAlert() end
        return
    end
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
    "UNIT_PET", "UNIT_INVENTORY_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PET_BAR_UPDATE",
    -- Necessaire pour l'exception "cible attaquable en zone de repos" (cf. CheckForMissings) :
    -- sans cet evenement, cibler/decibler un mannequin d'entrainement ne redeclenchait aucun rescan.
    "PLAYER_TARGET_CHANGED",
    -- Coupure/reprise du module pendant une cle M+ : le DEBUT passe par PLAYER_ENTERING_WORLD,
    -- mais la FIN n'a pas d'ecran de chargement -- sans cet evenement le module restait coupe
    -- jusqu'au prochain UNIT_AURA/GROUP_ROSTER_UPDATE fortuit.
    "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
}

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" and frame and frame:IsShown()
       and vanishAnimGroup and not vanishAnimGroup:IsPlaying() and frame:GetAlpha() <= 0.01 then
        -- Rattrape un vanish dont le Hide() final a ete saute en combat (cf.
        -- BuildVanishAnimGroup:OnFinished) : le frame restait affiche-mais-invisible.
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

    -- Familier en combat : la mort / le renvoi du familier ne declenche pas toujours d'evenement exploitable
    local wasFlying = false
    C_Timer.NewTicker(1, function()
        if InCombatLockdown() and Cfg().enabled then MissingBuffs.CheckPetInCombat() end
        -- Mise en selle / descente : on relance l'evaluation du familier
        local fl = IsMounted and IsMounted() or false
        if fl ~= wasFlying then
            wasFlying = fl
            if not InCombatLockdown() then MissingBuffs.RequestCheck() end
        end
    end)

    -- Rappel "bientot expire" : contrairement au reste du module (event-driven), le franchissement
    -- du seuil de duree n'est pas un evenement -- ticker leger (2s), inoffensif si desactive.
    C_Timer.NewTicker(2, function()
        local cfg = Cfg()
        if cfg.enabled and cfg.expiringSoonEnabled then
            MissingBuffs.RequestCheck()
        end
    end)
end

-- Changement de profil (cf. Core/Profiles.lua Prof:SetActive) : Cfg() pointe deja sur le nouveau
-- profil, on reapplique position, apparence et etat de l'alerte.
function MissingBuffs.OnProfileChanged()
    if frame and not InCombatLockdown() then
        frame._positioned = false
        PositionFrameIfNeeded()
    end
    MissingBuffs.RefreshAppearance()
    MissingBuffs.RequestCheck()
end

-- Helper reglages : (des)ignorer une entree par settingsId
function MissingBuffs.SetIgnored(settingsId, ignored)
    local cfg = Cfg()
    if not (cfg and settingsId) then return end
    -- Rappel optionnel (Forever, decoche par defaut) : "ignore" = non coche, on stocke donc l'inverse
    if ns.MISSING_OPTIN_IDS and ns.MISSING_OPTIN_IDS[settingsId] then
        cfg.optInSettingsIds = cfg.optInSettingsIds or {}
        cfg.optInSettingsIds[settingsId] = (not ignored) or nil
    else
        cfg.ignoredSettingsIds = cfg.ignoredSettingsIds or {}
        cfg.ignoredSettingsIds[settingsId] = ignored or nil
    end
    MissingBuffs.RequestCheck()
end

function MissingBuffs.IsIgnored(settingsId)
    local cfg = Cfg()
    if ns.MISSING_OPTIN_IDS and ns.MISSING_OPTIN_IDS[settingsId] then
        return not (cfg and cfg.optInSettingsIds and cfg.optInSettingsIds[settingsId])
    end
    return cfg and cfg.ignoredSettingsIds and cfg.ignoredSettingsIds[settingsId] == true
end

-- Liste plate des spellIds que ce module peut effectivement afficher pour la classe courante
-- (buffs de classe + postures/auras/accords + familiers + poisons) -- utilisee par Animations 3D
-- pour restreindre le picker de sorts d'un combo au perimetre reel du module.
function MissingBuffs.GetTriggerSpells()
    local class = _addon._playerClass or select(2, UnitClass("player"))
    if not class then return {} end
    local out, seen = {}, {}
    local function add(id)
        if id and not seen[id] then seen[id] = true; out[#out + 1] = id end
    end

    -- Forever : les entrees portent "casts" (cles = spellIDs de rang 1, un par sort distinct) ;
    -- Retail : un spellId par entree.
    local seenName = {}
    local function addEntry(e)
        if e.casts then
            for _, v in ipairs(e.casts) do
                if type(v) == "number" then
                    local n = SpellNameById(v)
                    if n and not seenName[n] then seenName[n] = true; add(v) end
                end
            end
        else
            add(e.spellId)
        end
    end
    local list = ns.MISSING_CLASS_BUFFS[class]
    if list then for _, e in ipairs(list) do addEntry(e) end end

    if class == "WARRIOR" then
        for _, o in ipairs(ns.MISSING_WARRIOR_STANCES) do addEntry(o) end
    elseif class == "PALADIN" then
        for _, o in ipairs(ns.MISSING_PALADIN_AURAS) do addEntry(o) end
    elseif class == "EVOKER" then
        for _, o in ipairs(ns.MISSING_EVOKER_ATTUNEMENTS) do add(o.spellId) end
    elseif class == "DRUID" then
        add(ns.MISSING_BALANCE_MOONKIN.spellId)
    elseif class == "PRIEST" then
        add(ns.MISSING_SHADOW_FORM.spellId)
    elseif class == "HUNTER" then
        add(ns.MISSING_HUNTER_PET_DEAD)
        add(ns.MISSING_PET_PASSIVE_KEY)
        for _, o in ipairs(ns.MISSING_HUNTER_ALL_PETS) do addEntry(o) end
        if ns.MISSING_HUNTER_REVIVE_ENTRY then addEntry(ns.MISSING_HUNTER_REVIVE_ENTRY) end
    elseif class == "WARLOCK" then
        for _, o in ipairs(ns.MISSING_WARLOCK_ALL_PETS) do addEntry(o) end
        -- Presence dans le picker de combo uniquement -- cf. IsBurningRushActive,
        -- jamais ajoute a ns.MISSING_CLASS_BUFFS (pas de detection "absent").
        if not _addon.IsForever then
            add(ns.MISSING_WARLOCK_BURNING_RUSH)
            add(SPELL_CREATE_HEALTHSTONE)
            add(SPELL_SOULSTONE)
        end
        add(ns.MISSING_PET_PASSIVE_KEY)
    elseif class == "ROGUE" then
        for _, o in ipairs(ns.MISSING_ROGUE_POISONS.nonlethal) do addEntry(o) end
        for _, o in ipairs(ns.MISSING_ROGUE_POISONS.lethal) do addEntry(o) end
        for _, o in ipairs(ns.MISSING_ROGUE_POISONS.forever or {}) do addEntry(o) end
    end

    return out
end

-- Debug : /aishbuffdebug [spellId] liste chaque unite du groupe avec le detail du check de portee
-- (UnitInRange vs C_Spell.IsSpellInRange) et la presence du buff -- pour diagnostiquer pourquoi un
-- allie manquant n'apparait pas (suspicion : UnitInRange peu fiable en PARTY, contrairement au RAID).
SLASH_AISHBUFFDEBUG1 = "/aishbuffdebug"
SlashCmdList["AISHBUFFDEBUG"] = function(msg)
    -- "/aishbuffdebug reset" : force previewMode a false + relance un vrai scan, au cas ou
    -- l'apercu force (Animations 3D) serait reste bloque actif.
    if msg == "reset" then
        MissingBuffs.SetPreview(false)
        MissingBuffs.RequestCheck()
        print("|cff00ff00[AishCore]|r previewMode force a false, RequestCheck relance.")
        return
    end

    local spellId = tonumber(msg) or 462854 -- Fureur des cieux par defaut
    local entry = { spellId = spellId }
    print(string.format("|cff00ff00[AishCore]|r Debug buff manquant spellId=%d", spellId))
    print(string.format("  IsInRaid=%s IsInGroup=%s previewMode=%s AurasAreSecret=%s",
        tostring(IsInRaid()), tostring(IsInGroup()), tostring(previewMode), tostring(AurasAreSecret())))

    -- Dump brut des auras HELPFUL de l'unite (spellId ou "SECRET"/"nil") : pour voir si le sort
    -- cherche est vraiment absent, ou juste cache derriere une valeur secrete.
    local function DumpAuras(unit)
        if not (AuraUtil and AuraUtil.ForEachAura) then return "AuraUtil indisponible" end
        local parts, n = {}, 0
        pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, function(aura)
            n = n + 1
            if not aura then parts[#parts+1] = "nil"; return false end
            local sid = aura.spellId
            if IsSecret(sid) then parts[#parts+1] = "SECRET"
            elseif sid == nil then parts[#parts+1] = "nil"
            else parts[#parts+1] = tostring(sid) end
            return false
        end, true)
        if n == 0 then return "(aucune aura HELPFUL)" end
        return string.format("%d auras : %s", n, table.concat(parts, ", "))
    end

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
        local hasBuff
        -- IsValidAllyUnit exclut toujours "player" par construction (filtre "allie") -- cas
        -- particulier pour que la ligne player reflete le vrai check d'AnyoneMissingBuff().
        if unit == "player" or valid then hasBuff = UnitHasBuff(unit, entry) else hasBuff = "n/a (valid=false)" end
        print(string.format(
            "  %s : exists=%s valid=%s | UnitInRange ok=%s inRange=%s checked=%s | IsSpellInRange ok=%s inRange=%s | CheckInteractDistance ok=%s near=%s | PassesRangeCheck=%s | UnitHasBuff=%s",
            unit, tostring(exists), tostring(valid),
            tostring(uiOk), tostring(uiInRange), tostring(uiChecked),
            tostring(spOk), tostring(spInRange),
            tostring(ciOk), tostring(ciNear),
            tostring(passes), tostring(hasBuff)))
        print("    " .. DumpAuras(unit))
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

-- Forever : /aishbuffs affiche, pour la classe courante, chaque rappel avec les noms de sort
-- deduits des spellIDs (langue du client), le sort connu retenu et l'etat de l'aura sur soi.
-- Sert a verifier que les IDs de MissingBuffsData.lua correspondent bien a ce client.
if _addon.IsForever then
    SLASH_AISHBUFFS1 = "/aishbuffs"
    SlashCmdList["AISHBUFFS"] = function()
        local P = "|cff00ff00[AishCore buffs]|r "
        local class = _addon._playerClass or select(2, UnitClass("player"))
        local function names(list)
            if not list or #list == 0 then return "-" end
            local out = {}
            for _, v in ipairs(list) do
                if type(v) == "number" then
                    local n = ExpandNames({ v })[1]
                    out[#out + 1] = n and (n .. "(" .. v .. ")") or ("?" .. v)
                end
            end
            return #out > 0 and table.concat(out, ", ") or "-"
        end
        local function line(label, e)
            local known = e.casts and IsEntryLearned(e) or false
            local active = e.names and FindAuraByNames("player", e.names) and "oui" or "non"
            -- casts vide (aura reconnue seulement) : on montre les noms d'aura attendus
            local shown = (e.casts and #e.casts == 0) and ("aura attendue: " .. names(e.names)) or names(e.casts)
            print(P .. string.format("%s | sorts: %s | connu: %s (%s) | aura sur soi: %s",
                label, shown, tostring(known), tostring(e._castName), active))
        end
        print(P .. "classe=" .. tostring(class) .. " spe=" .. tostring(_addon._specID))
        for _, e in ipairs(ns.MISSING_CLASS_BUFFS[class] or {}) do
            if e.kind then
                local missing, n = ItemEntryMissing(e)
                print(P .. string.format("%s | quantite=%s seuil=%s manquant=%s", e.displayName or e.kind, tostring(n), tostring(e.min), tostring(missing)))
            else
                line(e.displayName or "?", e)
            end
        end
        if class == "PALADIN" then for _, e in ipairs(ns.MISSING_PALADIN_AURAS) do line("aura", e) end end
        if class == "PRIEST" then line("Shadowform", ns.MISSING_SHADOW_FORM) end
        if class == "HUNTER" then
            line("Call Pet", ns.MISSING_HUNTER_ALL_PETS[1]); line("Revive Pet", ns.MISSING_HUNTER_REVIVE_ENTRY)
        end
        if class == "WARLOCK" then for _, e in ipairs(ns.MISSING_WARLOCK_ALL_PETS) do line("demon", e) end end
        if class == "ROGUE" then for _, e in ipairs(ns.MISSING_ROGUE_POISONS.forever) do line("poison", e) end end
        if GetWeaponEnchantInfo then
            local ok, a, b, c, d, e, f, g, h = pcall(GetWeaponEnchantInfo)
            print(P .. "GetWeaponEnchantInfo: ok=" .. tostring(ok) .. " -> " .. tostring(a) .. ", " .. tostring(b) ..
                  ", " .. tostring(c) .. ", " .. tostring(d) .. ", " .. tostring(e) .. ", " .. tostring(f) ..
                  ", " .. tostring(g) .. ", " .. tostring(h))
            print(P .. "arme main droite: " .. tostring(GetInventoryItemID and GetInventoryItemID("player", 16)) ..
                  " main gauche: " .. tostring(GetInventoryItemID and GetInventoryItemID("player", 17)))
        else
            print(P .. "GetWeaponEnchantInfo: ABSENT sur ce client")
        end
        do
            local hm, em = WeaponEnchantState("main")
            local ho, eo = WeaponEnchantState("off")
            print(P .. string.format("etat enchantement (C_Item) : main=%s (%s ms) off=%s (%s ms) | C_Item.GetWeaponEnchantInfo=%s",
                tostring(hm), tostring(em), tostring(ho), tostring(eo), tostring(C_Item and C_Item.GetWeaponEnchantInfo ~= nil)))
        end
        -- Auras actuelles du joueur : pour comparer les noms reels a ceux attendus
        local have = {}
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not a then break end
            if a.name and not IsSecret(a.name) then have[#have + 1] = a.name end
        end
        print(P .. "auras actuelles: " .. (#have > 0 and table.concat(have, ", ") or "(aucune)"))
    end
end

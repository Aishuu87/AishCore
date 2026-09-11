-- AishUIAura/Core/MissingBuffsData.lua
-- Donnees "Buffs manquants" : table de reference des buffs de classe/groupe a detecter, variantes et conditions.
-- Table de donnees pure, aucune dependance Ace3/LibEditMode/LibDualSpec.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

-- Libelles affiches sous l'icone d'alerte (cf. MissingBuffs.lua)
ns.MISSING_TEXT = {
    MISSING          = "MANQUANT",
    WRONG            = "INCORRECT",
    USE_STANCE       = "CHANGER DE POSTURE",
    USE_AURA         = "CHANGER D'AURA",
    USE_ATTUNEMENT   = "CHANGER D'HARMONISATION",
    SUMMON_PET       = "INVOQUER FAMILIER",
    REVIVE_PET       = "RESSUSCITER FAMILIER",
    APPLY_LETHAL     = "APPLIQUER POISON",
    APPLY_NONLETHAL  = "APPLIQUER POISON",
    REAPPLY          = "RÉAPPLIQUER",
    -- Affiche quand un buff suivi est encore actif mais approche de sa fin (cf. GetSelfBuffExpiringSoon).
    EXPIRING_SOON    = "RAFRAICHIR",
    BUFF_ALLY        = "BUFFER UN ALLIÉ",
    USE_FLASK        = "BOIRE UN FLACON",
    EAT_FOOD         = "MANGER",
    USE_WEAPON_BUFF  = "ENCHANTER L'ARME",
}

-- Masques de forme pour l'icone d'alerte (cf. UI/Menus/MissingBuffs.lua, MissingBuffs.lua:RefreshAppearance).
-- value=1 "Defaut" = pas de masque ; les autres utilisent un atlas Blizzard ou notre texture degrade "feather".
ns.MISSING_BUFF_ICON_MASKS = {
    { value = 1, text = "Par defaut (carre)" },
    { value = 2, text = "Cercle", atlas = "CircleMaskScalable" },
    { value = 3, text = "Hexagone", atlas = "CovenantSanctum-Renown-Hexagon-Mask" },
    { value = 4, text = "Adouci (feather)", texture = "Interface\\AddOns\\AishCore\\Media\\UI\\IconFeatherMask.png" },
    { value = 5, text = "Feather grunge", texture = "Interface\\AddOns\\AishCore\\Media\\UI\\IconGrungeMask.png" },
}

-- Buffs de classe : le sort que le joueur peut fournir au groupe/raid.
-- Champs :
--   spellId               spellID de l'aura a detecter
--   spellbookId            spellID a verifier via IsSpellKnown si different de spellId
--   clickableId             spellID a lancer au clic si different de spellId
--   settingsId              identifiant stable pour la liste "ignorer" (UI)
--   learned                 true = sort de base (verifie via IsSpellKnown)
--   whitelist                true = exempte du secret en combat (lecture self directe)
--   showInCombat             true = reste verifie/affiche meme en combat
--   onlySelf                 ne verifie jamais les autres, uniquement soi
--   ignoreSelf                ne verifie jamais soi, uniquement les alliés
--   ignoreRangeCheck          pas de verification de portee sur les alliés
--   overrideIgnoreAllies      reste verifie sur les alliés meme si "ignorer alliés" global
--   onlyOnePerGroup           une seule instance suffit n'importe ou dans le groupe
--   playerCanHaveMultiples    variante ci-dessus : le joueur peut l'avoir posee sur plusieurs cibles
--   clickingUsesTarget        le clic lance sur la cible plutot que sur soi
--   extraBuffSpellIds         spellIDs alternatifs qui comptent comme "buff present"
--   mutuallyExclusiveWith     spellIDs qui, si presents (poses par le joueur), valident aussi celui-ci
--   excludeIfKnown            si un de ces spellIDs est connu, cette entree est consideree non apprise
--   requiresHealerInGroup     ne verifie que si un healer du groupe n'a pas le buff
--   weaponEnchantSlot         "main"/"off" : verifie via GetWeaponEnchantInfo, pas un scan d'aura
--   specIds                   restreint la verification a ces specID
--   ignoreDuration            ignore la notification "duree bientot expiree"
--   text                      cle de ns.MISSING_TEXT affichee
--   default                   marque le choix par defaut dans un groupe exclusif (stance/aura/...)
--   showRaidCount             affiche "10/14" (couverture allies a portee) au lieu du texte, reserve aux
--                             vrais buffs de raid un-par-personne, pas aux buffs a instance unique
ns.MISSING_CLASS_BUFFS = {
    DRUID = {
        -- extraBuffSpellIds 432661 : variante appliquee sur un allie PNJ
        -- (compagnon de Delve/donjon suivi type Valeera) plutot que 1126 --
        -- confirme en jeu via /aishbuffdebug 1126 (dump brut des auras de
        -- party1 : 1252003, 432661 -- jamais 1126 -- alors que le joueur,
        -- lui, a bien 1126 dans ses propres auras).
        { spellId = 1126,   settingsId = 31, learned = true, whitelist = true, showRaidCount = true, text = "MISSING",
          extraBuffSpellIds = { 432661 } },
        { spellId = 474750, settingsId = 34, onlyOnePerGroup = true, ignoreSelf = true,
          overrideIgnoreAllies = true, playerCanHaveMultiples = true, clickingUsesTarget = true,
          text = "BUFF_ALLY" },
    },
    EVOKER = {
        { spellId = 381748, spellbookId = 364342, settingsId = 2, whitelist = true, ignoreRangeCheck = true,
          showRaidCount = true, text = "MISSING",
          extraBuffSpellIds = { 381732, 381741, 381746, 381749, 381750, 381751, 381752, 381753, 381754,
                                 381756, 381757, 381758, 442744, 432658, 432652, 432655 } },
        { spellId = 369459, settingsId = 3, whitelist = true, clickingUsesTarget = true,
          overrideIgnoreAllies = true, ignoreSelf = true, requiresHealerInGroup = true, text = "BUFF_ALLY" },
        { spellId = 412710, settingsId = 4, clickingUsesTarget = true, onlyOnePerGroup = true,
          specIds = { 1473 }, text = "MISSING" },
    },
    MAGE = {
        -- extraBuffSpellIds 432778 : meme cas que l'Harmonie du Bosquet du druide (1126/432661) --
        -- l'Intelligence arcanique posee sur un allie porte un spellID different de celui qu'on voit
        -- sur soi, et l'alerte "MANQUANT" se declenchait donc a tort alors que le buff etait bien la.
        { spellId = 1459,   settingsId = 5, learned = true, whitelist = true, showRaidCount = true, text = "MISSING",
          extraBuffSpellIds = { 432778 } },
        { spellId = 210126, spellbookId = 205022, clickableId = 1459, settingsId = 6,
          onlySelf = true, text = "MISSING" },
    },
    PALADIN = {
        { spellId = 53563, settingsId = 7, excludeIfKnown = { 200025 }, onlyOnePerGroup = true,
          playerCanHaveMultiples = true, clickingUsesTarget = true, mutuallyExclusiveWith = { 156910 },
          ignoreDuration = true, spellOverlayCompatible = true, text = "MISSING" },
        { spellId = 156910, settingsId = 8, onlyOnePerGroup = true, playerCanHaveMultiples = true,
          clickingUsesTarget = true, mutuallyExclusiveWith = { 53563 }, ignoreDuration = true,
          spellOverlayCompatible = true, spellOverlayNeedsParty = true, text = "MISSING" },
        { spellId = 433550, spellbookId = 433568, settingsId = 9, onlySelf = true, text = "MISSING" },
        { spellId = 433584, spellbookId = 433583, settingsId = 10, onlySelf = true, text = "MISSING" },
    },
    PRIEST = {
        { spellId = 21562, settingsId = 12, learned = true, whitelist = true, showRaidCount = true, text = "MISSING" },
    },
    SHAMAN = {
        { spellId = 462854, settingsId = 13, whitelist = true, learned = true, showRaidCount = true, text = "MISSING" },
        { spellId = 192106, settingsId = 14, onlySelf = true, specIds = { 263, 262 }, text = "MISSING" },
        { spellId = 52127,  settingsId = 15, onlySelf = true, specIds = { 264 }, text = "MISSING" },
        { spellId = 383648, spellbookId = 383010, clickableId = 974, settingsId = 16,
          onlySelf = true, text = "MISSING" },
        -- requireOwnCast : Bouclier de terre n'est PAS un buff "un seul par
        -- raid" malgre onlyOnePerGroup ci-dessous (qui sert juste a n'afficher
        -- qu'UN SEUL rappel a la fois, pas plusieurs) -- chaque chaman place
        -- le sien sur une cible potentiellement differente. Sans ce flag, le
        -- rappel se cachait a tort des qu'UN AUTRE chaman avait pose le sien
        -- sur quelqu'un, meme si le notre n'etait sur personne.
        { spellId = 383648, spellbookId = 974, settingsId = 17, clickingUsesTarget = true,
          ignoreSelf = true, onlyOnePerGroup = true, playerCanHaveMultiples = true,
          requireOwnCast = true, extraBuffSpellIds = { 974 }, text = "BUFF_ALLY" },
        { spellId = 318038, settingsId = 18, weaponEnchantSlot = "main", specIds = { 262 }, text = "USE_WEAPON_BUFF" },
        { spellId = 462757, settingsId = 19, weaponEnchantSlot = "off",  specIds = { 262 }, text = "USE_WEAPON_BUFF" },
        { spellId = 33757,  settingsId = 20, weaponEnchantSlot = "main", text = "USE_WEAPON_BUFF" },
        { spellId = 318038, settingsId = 21, weaponEnchantSlot = "off",  specIds = { 263 }, text = "USE_WEAPON_BUFF" },
        { spellId = 382021, settingsId = 22, weaponEnchantSlot = "main", text = "USE_WEAPON_BUFF" },
        { spellId = 457481, settingsId = 23, weaponEnchantSlot = "off",  text = "USE_WEAPON_BUFF" },
    },
    WARLOCK = {
        { spellId = 196099, spellbookId = 108503, settingsId = 35, onlySelf = true, ignoreDuration = true,
          specIds = { 265, 267 }, text = "MISSING" },
    },
    WARRIOR = {
        { spellId = 6673, settingsId = 24, learned = true, whitelist = true, ignoreRangeCheck = true,
          showRaidCount = true, text = "MISSING" },
    },
    -- ROGUE : poisons geres a part (ns.MISSING_POISONS), pas un buff de groupe.
}

-- Entrees speciales "shapeshift" (chemin prioritaire, ignoreAsBuff=true, verifiees en premier)
ns.MISSING_BALANCE_MOONKIN = { spellId = 24858, ignoreAsBuff = true, onlySelf = true, specIds = { 102 }, text = "USE_STANCE" }
ns.MISSING_SHADOW_FORM     = { spellId = 232698, ignoreAsBuff = true, ignoreDuration = true, onlySelf = true,
                                specIds = { 258 }, extraBuffSpellIds = { 194249 }, text = "USE_STANCE" }

-- Groupes mutuellement exclusifs (soi uniquement) : stances/auras/attunements. `default` = choix suppose.
ns.MISSING_WARRIOR_STANCES = {
    { spellId = 386164, name = "Battle",     text = "USE_STANCE" },
    { spellId = 386196, name = "Berserker",  text = "USE_STANCE" },
    { spellId = 386208, name = "Defensive",  text = "USE_STANCE", default = true },
}

ns.MISSING_CRUSADER_AURA = 32223
ns.MISSING_PALADIN_AURAS = {
    { spellId = 465,    name = "Devotion",      text = "USE_AURA", default = true },
    { spellId = 317920, name = "Concentration", text = "USE_AURA" },
    { spellId = 32223,  name = "Crusader",      text = "USE_AURA" },
    { spellId = 210323, name = "Vengeance",     text = "USE_AURA" },
}

ns.MISSING_EVOKER_ATTUNEMENTS = {
    { spellId = 403264, name = "Black",  text = "USE_ATTUNEMENT", default = true },
    { spellId = 403265, name = "Bronze", text = "USE_ATTUNEMENT" },
}

-- Familiers (Chasseur/Demoniste) : verification "presence + vivant" (soi uniquement)
ns.MISSING_HUNTER_PET_MISSING = 883  -- Call Pet 1
ns.MISSING_HUNTER_PET_DEAD    = 982
ns.MISSING_HUNTER_ALL_PETS = {
    { spellId = 883,   name = "Pet 1", default = true },
    { spellId = 83242, name = "Pet 2" },
    { spellId = 83243, name = "Pet 3" },
    { spellId = 83244, name = "Pet 4" },
    { spellId = 83245, name = "Pet 5" },
}

ns.MISSING_WARLOCK_PET = 688 -- Imp
ns.MISSING_WARLOCK_ALL_PETS = {
    { spellId = 688,    name = "Imp",        default = true },
    { spellId = 697,    name = "Voidwalker" },
    { spellId = 691,    name = "Felhunter" },
    { spellId = 366222, name = "Sayaad" },
    { spellId = 30146,  name = "Felguard" },
}

ns.MISSING_UNHOLY_GHOUL_MISSING  = 46584
ns.MISSING_FROST_ELEMENTAL_MISSING = 31687

-- Ruee ardente (Demoniste) : cas "buff manquant" inverse (buff qu'on oublie parfois de retirer, pas un
-- qu'on cherche a avoir). N'apparait pas dans ns.MISSING_CLASS_BUFFS, sert de spellID de reference partage
-- entre MissingBuffs.lua (IsBurningRushActive) et SpellEffects.lua (ScanMissingBuffCombos).
ns.MISSING_WARLOCK_BURNING_RUSH = 111400

-- Poisons voleur : lethal/non-lethal, un des deux groupes doit etre actif (soi uniquement).
ns.MISSING_ROGUE_POISONS = {
    nonlethal = {
        { spellId = 381637, settingsId = 25, name = "Atrophic" },
        { spellId = 5761,   settingsId = 27, name = "Numbing" },
        { spellId = 3408,   settingsId = 26, name = "Crippling", default = true },
    },
    lethal = {
        { spellId = 381664, settingsId = 28, name = "Amplifying" },
        { spellId = 2823,   settingsId = 30, name = "Deadly" },
        { spellId = 315584, settingsId = 29, name = "Instant", default = true },
        { spellId = 8679,   settingsId = 32, name = "Wound" },
    },
}
-- Talents qui changent le poison "par defaut" detecte automatiquement.
ns.MISSING_ROGUE_DRAGON_TEMPERED_SPELL   = 381801  -- deux poisons de meme letalite actifs en meme temps
ns.MISSING_ROGUE_IMPROVED_WOUND_SPELL    = 319066  -- bascule le lethal par defaut vers Wound

-- Spec -> classe mapping additionnel, pour les cas particuliers non couverts par `specIds` simple.
ns.MISSING_UNHOLY_DK_SPEC          = 252
ns.MISSING_AUGMENTATION_EVOKER_SPEC = 1473
ns.MISSING_BALANCE_DRUID_SPEC      = 102
ns.MISSING_SHADOW_PRIEST_SPEC      = 258
ns.MISSING_MARKSMANSHIP_HUNTER_SPEC = 254

-- Zones/difficultes (reserve pour reglages fins par zone/difficulte)
ns.MISSING_DUNGEON_DIFFICULTIES = { [1] = "normal", [2] = "heroic", [23] = "mythic", [8] = "mythicplus" }
ns.MISSING_RAID_DIFFICULTIES    = { [14] = "normal", [15] = "heroic", [16] = "mythic", [17] = "lfr" }

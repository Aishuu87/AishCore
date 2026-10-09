-- AishUIAura/Core/MissingBuffsData.lua
-- Donnees "Buffs manquants" : table de reference des buffs de classe/groupe a detecter, variantes et conditions.
-- Table de donnees pure, aucune dependance Ace3/LibEditMode/LibDualSpec.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

-- Libelles affiches sous l'icone d'alerte (cf. MissingBuffs.lua).
-- Lecture PARESSEUSE dans ns.L : cette table de donnees est construite au chargement, mais
-- /aish locale reconstruit ns.L en place plus tard -- un copier-coller des libelles ici figerait
-- l'alerte dans la langue de depart (bug : texte francais sur un client anglais).
local ALERT_TEXT_KEYS = {
    MISSING          = "MISSINGBUFFS_ALERT_MISSING",
    WRONG            = "MISSINGBUFFS_ALERT_WRONG",
    USE_STANCE       = "MISSINGBUFFS_ALERT_USE_STANCE",
    USE_AURA         = "MISSINGBUFFS_ALERT_USE_AURA",
    USE_ATTUNEMENT   = "MISSINGBUFFS_ALERT_USE_ATTUNEMENT",
    SUMMON_PET       = "MISSINGBUFFS_ALERT_SUMMON_PET",
    PET_PASSIVE      = "MISSINGBUFFS_ALERT_PET_PASSIVE",
    REVIVE_PET       = "MISSINGBUFFS_ALERT_REVIVE_PET",
    APPLY_LETHAL     = "MISSINGBUFFS_ALERT_APPLY_LETHAL",
    APPLY_NONLETHAL  = "MISSINGBUFFS_ALERT_APPLY_NONLETHAL",
    REAPPLY          = "MISSINGBUFFS_ALERT_REAPPLY",
    -- Affiche quand un buff suivi est encore actif mais approche de sa fin (cf. GetSelfBuffExpiringSoon).
    EXPIRING_SOON    = "MISSINGBUFFS_ALERT_EXPIRING_SOON",
    BUFF_ALLY        = "MISSINGBUFFS_ALERT_BUFF_ALLY",
    USE_FLASK        = "MISSINGBUFFS_ALERT_USE_FLASK",
    EAT_FOOD         = "MISSINGBUFFS_ALERT_EAT_FOOD",
    USE_WEAPON_BUFF  = "MISSINGBUFFS_ALERT_USE_WEAPON_BUFF",
    LOW_AMMO         = "MISSINGBUFFS_ALERT_LOW_AMMO",
    LOW_SHARDS       = "MISSINGBUFFS_ALERT_LOW_SHARDS",
    NO_HEALTHSTONE   = "MISSINGBUFFS_ALERT_NO_HEALTHSTONE",
    NO_SOULSTONE     = "MISSINGBUFFS_ALERT_NO_SOULSTONE",
}
ns.MISSING_TEXT = setmetatable({}, {
    __index = function(_, key)
        local locKey = ALERT_TEXT_KEYS[key]
        return locKey and L[locKey] or nil
    end,
})

-- Masques de forme pour l'icone d'alerte (cf. UI/Menus/MissingBuffs.lua, MissingBuffs.lua:RefreshAppearance).
-- value=1 "Defaut" = pas de masque ; les autres utilisent un atlas Blizzard ou notre texture degrade "feather".
-- Libelles lus au chargement (les locales sont chargees avant ce fichier, cf. AishCore.toc) :
-- ce menu deroulant n'est construit qu'une fois, il ne se retraduirait pas a chaud de toute facon.
ns.MISSING_BUFF_ICON_MASKS = {
    { value = 1, text = L["MISSINGBUFFS_MASK_DEFAULT"] or "Par defaut (carre)" },
    { value = 2, text = L["MISSINGBUFFS_MASK_CIRCLE"] or "Cercle", atlas = "CircleMaskScalable" },
    { value = 3, text = L["MISSINGBUFFS_MASK_HEXAGON"] or "Hexagone", atlas = "CovenantSanctum-Renown-Hexagon-Mask" },
    { value = 4, text = L["MISSINGBUFFS_MASK_FEATHER"] or "Adouci (feather)", texture = "Interface\\AddOns\\AishCore\\Media\\UI\\IconFeatherMask.png" },
    { value = 5, text = L["MISSINGBUFFS_MASK_GRUNGE"] or "Feather grunge", texture = "Interface\\AddOns\\AishCore\\Media\\UI\\IconGrungeMask.png" },
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

-- Alerte "familier en Passif" : pas de sort associe, cle de combo fictive (cf. PSEUDO_SPELLS_3D dans SettingsPanel.lua)
ns.MISSING_PET_PASSIVE_KEY = 9000010
ns.MISSING_PET_PASSIVE_ICON = "Interface\\Icons\\Ability_Seal"

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

-- ═══ FOREVER : liste reduite, resolue par NOM ═══════════════════════════════════════════════
-- Ne garde que les buffs communs a Retail et au rappel de reference de Forever (Buff Reminder
-- Forever). Les spellIDs different d'un client a l'autre ET d'un rang a l'autre : chaque entree
-- se reconnait par le NOM de l'aura (`names`, tous rangs et variantes de groupe) et se lance par
-- le NOM du sort (`casts`, par ordre de preference). L'alerte n'apparait que si un des `casts`
-- est dans le grimoire (cf. MissingBuffs.lua : IsEntryLearned / ForeverResolve) ; spellId est
-- alors rempli dynamiquement avec le rang connu, pour l'icone et le clic.
-- Garde aussi les rappels propres a Forever de Buff Reminder Forever (Aspects, Trueshot Aura, Inner Fire,
-- Epines, Presence de clarte, armures de mage/demoniste, munitions, fragments d'ame).
-- Retire (retail seul) : postures de guerrier, forme de sélénien, Symbiose, Familier arcanique,
-- Faveurs, Benedictions, accords, etc.
if _addon.IsForever then
    local I = "Interface\\Icons\\"
    -- Chaque sort est donne par son spellID de rang 1 (le NOM localise en est deduit a l'execution, donc
    -- valable dans toutes les langues) suivi de son nom anglais (repli si l'ID est inconnu du client).
    ns.MISSING_CLASS_BUFFS = {
        DRUID = {
            { settingsId = 31, names = { 1126, "Mark of the Wild", 21849, "Gift of the Wild" },
              casts = { 1126, "Mark of the Wild" },
              displayName = "Mark of the Wild", icon = I .. "Spell_Nature_Regeneration",
              showRaidCount = true, text = "MISSING" },
            { settingsId = 101, onlySelf = true, names = { 467, "Thorns" }, casts = { 467, "Thorns" },
              displayName = "Thorns", icon = I .. "Spell_Nature_Thorns", text = "MISSING" },
            { settingsId = 102, onlySelf = true, names = { 16864, "Omen of Clarity" },
              casts = { 16864, "Omen of Clarity" },
              displayName = "Omen of Clarity", icon = I .. "Spell_Nature_CrystalBall", text = "MISSING" },
        },
        EVOKER = {},
        MAGE = {
            { settingsId = 5, names = { 1459, "Arcane Intellect", 23028, "Arcane Brilliance" },
              casts = { 1459, "Arcane Intellect" },
              displayName = "Arcane Intellect", icon = I .. "Spell_Holy_MagicalSentry",
              showRaidCount = true, text = "MISSING" },
            { settingsId = 103, onlySelf = true,
              names = { 6117, "Mage Armor", 7302, "Ice Armor", 168, "Frost Armor", 30482, "Molten Armor" },
              casts = { 30482, "Molten Armor", 6117, "Mage Armor", 7302, "Ice Armor", 168, "Frost Armor" },
              displayName = "Mage / Ice / Frost Armor", icon = I .. "Spell_Frost_FrostArmor02", text = "MISSING" },
            { settingsId = 117, optIn = true, onlySelf = true,
              names = { 604, "Dampen Magic", 1008, "Amplify Magic" }, casts = { 604, "Dampen Magic", 1008, "Amplify Magic" },
              displayName = "Dampen / Amplify Magic", icon = I .. "Spell_Nature_AbolishMagic", text = "MISSING" },
        },
        PALADIN = {
            -- Benediction (n'importe laquelle) sur soi : propose Rois, puissance, sagesse dans cet ordre
            { settingsId = 113, onlySelf = true,
              names = { 19740, "Blessing of Might", 19742, "Blessing of Wisdom", 20217, "Blessing of Kings",
                        1038, "Blessing of Salvation", 19977, "Blessing of Light", 20911, "Blessing of Sanctuary",
                        25782, "Greater Blessing of Might", 25894, "Greater Blessing of Wisdom",
                        25898, "Greater Blessing of Kings", 25895, "Greater Blessing of Salvation",
                        25890, "Greater Blessing of Light", 25899, "Greater Blessing of Sanctuary" },
              casts = { 20217, "Blessing of Kings", 19740, "Blessing of Might", 19742, "Blessing of Wisdom" },
              displayName = "Blessing", icon = I .. "Spell_Holy_FistOfJustice", text = "MISSING" },
            -- Optionnel (decoche par defaut) : tank
            { settingsId = 114, optIn = true, onlySelf = true, names = { 25780, "Righteous Fury" },
              casts = { 25780, "Righteous Fury" },
              displayName = "Righteous Fury", icon = I .. "Spell_Holy_SealOfFury", text = "MISSING" },
        },
        PRIEST = {
            { settingsId = 12, names = { 1243, "Power Word: Fortitude", 21562, "Prayer of Fortitude" },
              casts = { 1243, "Power Word: Fortitude" }, displayName = "Power Word: Fortitude",
              icon = I .. "Spell_Holy_WordFortitude", showRaidCount = true, text = "MISSING" },
            { settingsId = 104, onlySelf = true, names = { 588, "Inner Fire" }, casts = { 588, "Inner Fire" },
              displayName = "Inner Fire", icon = I .. "Spell_Holy_InnerFire", text = "MISSING" },
            -- Optionnels (decoches par defaut)
            { settingsId = 115, optIn = true, onlySelf = true,
              names = { 14752, "Divine Spirit", 27681, "Prayer of Spirit" }, casts = { 14752, "Divine Spirit" },
              displayName = "Divine Spirit", icon = I .. "Spell_Holy_DivineSpirit", text = "MISSING" },
            { settingsId = 116, optIn = true, onlySelf = true,
              names = { 976, "Shadow Protection", 27683, "Prayer of Shadow Protection" },
              casts = { 976, "Shadow Protection" },
              displayName = "Shadow Protection", icon = I .. "Spell_Shadow_AntiShadow", text = "MISSING" },
        },
        SHAMAN = {
            { settingsId = 14, specIds = { 262, 263 }, onlySelf = true,
              names = { 324, "Lightning Shield", 24398, 52127, 33736, "Water Shield" }, casts = { 324, "Lightning Shield" },
              displayName = "Lightning Shield", icon = I .. "Spell_Nature_LightningShield", text = "MISSING" },
            { settingsId = 15, specIds = { 264 }, onlySelf = true,
              names = { 24398, 52127, 33736, "Water Shield", 324, "Lightning Shield" }, casts = { 24398, 52127, 33736, "Water Shield" },
              displayName = "Water Shield", icon = I .. "Ability_Shaman_WaterShield", text = "MISSING" },
            { settingsId = 17, names = { 974, "Earth Shield" }, casts = { 974, "Earth Shield" },
              displayName = "Earth Shield", icon = I .. "Spell_Nature_SkinofEarth",
              clickingUsesTarget = true, ignoreSelf = true, onlyOnePerGroup = true,
              playerCanHaveMultiples = true, requireOwnCast = true, text = "BUFF_ALLY" },
            -- Pas de main gauche pour le chaman Forever : un seul enchantement, en main droite. Sort lance
            -- = le premier connu de cette liste (Rockbiter 8018/8017, Frostbrand 8033), sans condition de spe.
            { settingsId = 20, weaponEnchantSlot = "main", needsWeaponSlot = 16,
              casts = { 8232, "Windfury Weapon", 8024, "Flametongue Weapon", 8033, "Frostbrand Weapon",
                        8018, 8017, "Rockbiter Weapon" },
              displayName = "Weapon imbue", icon = I .. "Spell_Nature_Cyclone", text = "USE_WEAPON_BUFF" },
        },
        WARLOCK = {
            { settingsId = 105, onlySelf = true,
              names = { 28176, "Fel Armor", 706, "Demon Armor", 687, "Demon Skin" },
              casts = { 28176, "Fel Armor", 706, "Demon Armor", 687, "Demon Skin" },
              displayName = "Demon Armor / Skin", icon = I .. "Spell_Shadow_RagingScream", text = "MISSING" },
            -- Fragments d'ame : objet des sacs (6265), alerte sous le seuil
            { settingsId = 106, kind = "item", item = 6265, min = 3, text = "LOW_SHARDS",
              displayName = "Soul Shards", icon = I .. "INV_Misc_Gem_Amethyst_02" },
        },
        HUNTER = {
            { settingsId = 107, onlySelf = true,
              names = { 13165, "Aspect of the Hawk", "Aspect of the Eagle", 13163, "Aspect of the Monkey",
                        5118, "Aspect of the Cheetah", 13159, "Aspect of the Pack", 20043, "Aspect of the Wild",
                        13161, "Aspect of the Beast", 34074, "Aspect of the Viper",
                        61846, "Aspect of the Dragonhawk" },
              casts = { 61846, "Aspect of the Dragonhawk", 13165, "Aspect of the Hawk", "Aspect of the Eagle",
                        13163, "Aspect of the Monkey", 34074, "Aspect of the Viper", 20043, "Aspect of the Wild",
                        5118, "Aspect of the Cheetah", 13159, "Aspect of the Pack", 13161, "Aspect of the Beast" },
              displayName = "Aspect", icon = I .. "Spell_Nature_RavenForm", text = "MISSING" },
            { settingsId = 108, onlySelf = true, names = { 19506, "Trueshot Aura" }, casts = { 19506, "Trueshot Aura" },
              displayName = "Trueshot Aura", icon = I .. "Ability_TrueShot", text = "MISSING" },
            -- Munitions : stack equipe dans l'emplacement de munitions, alerte sous le seuil
            { settingsId = 109, kind = "ammo", min = 200, text = "LOW_AMMO",
              displayName = "Ammo", icon = I .. "INV_Ammo_Arrow_02" },
        },
        WARRIOR = {
            { settingsId = 24, names = { 6673, "Battle Shout", 469, "Commanding Shout" }, casts = { 6673, "Battle Shout" },
              displayName = "Battle Shout", icon = I .. "Ability_Warrior_BattleShout",
              ignoreRangeCheck = true, showRaidCount = true, text = "MISSING" },
        },
    }

    -- Forme (soi) : seule Ombre est commune aux deux listes.
    ns.MISSING_BALANCE_MOONKIN = { casts = {}, names = {} }
    ns.MISSING_SHADOW_FORM = { names = { 15473, "Shadowform" }, casts = { 15473, "Shadowform" }, ignoreDuration = true,
                               onlySelf = true, text = "USE_STANCE" }

    -- Rappels decoches par defaut : ne s'appliquent que si le joueur les coche (cf. MissingBuffs.IsIgnored)
    ns.MISSING_OPTIN_IDS = { [114] = true, [115] = true, [116] = true, [117] = true }

    ns.MISSING_WARRIOR_STANCES = {}
    ns.MISSING_EVOKER_ATTUNEMENTS = {}

    -- Auras de paladin : seules Devotion/Concentration/Crusader sont proposees au lancement ; les
    -- autres comptent seulement comme "une aura est active" (casts vide = jamais proposees).
    ns.MISSING_PALADIN_AURAS = {
        { settingsId = 110, icon = I .. "Spell_Holy_DevotionAura", names = { 465, "Devotion Aura" },       casts = { 465, "Devotion Aura" },       default = true, text = "USE_AURA" },
        { settingsId = 111, icon = I .. "Spell_Holy_MindSooth", names = { 19746, "Concentration Aura" }, casts = { 19746, "Concentration Aura" }, text = "USE_AURA" },
        { names = { 7294, "Retribution Aura" },        casts = {} },
        { names = { 20218, "Sanctity Aura" },          casts = {} },
        { names = { 19876, "Shadow Resistance Aura" }, casts = {} },
        { names = { 19888, "Frost Resistance Aura" },  casts = {} },
        { names = { 19891, "Fire Resistance Aura" },   casts = {} },
    }

    ns.MISSING_HUNTER_REVIVE_ENTRY = { casts = { 982, "Revive Pet" } }
    ns.MISSING_HUNTER_ALL_PETS = {
        { casts = { 883, "Call Pet" }, default = true },
    }

    ns.MISSING_WARLOCK_ALL_PETS = {
        { casts = { 688, "Summon Imp" },        default = true },
        { casts = { 697, "Summon Voidwalker" } },
        { casts = { 712, "Summon Succubus" } },
        { casts = { 691, "Summon Felhunter" } },
        { casts = { 30146, "Summon Felguard" } },
    }
    -- Sacrifice du demon (buffs qui remplacent le familier) : pas d'alerte "familier manquant".
    ns.MISSING_WARLOCK_SACRIFICE_NAMES = { 18791, "Touch of Shadow", 18789, "Burning Wish",
                                           18790, "Fel Stamina", 18792, "Fel Energy" }

    -- Poisons : sur ce client ce sont des enchantements d'arme (pas des auras), un par arme.
    ns.MISSING_ROGUE_POISONS = {
        nonlethal = {}, lethal = {},
        forever = {
            { casts = { 8681, "Instant Poison" }, default = true },
            { casts = { 2823, "Deadly Poison" } },
            { casts = { 13218, "Wound Poison" } },
            { casts = { 3408, "Crippling Poison" } },
            { casts = { 5761, "Mind-numbing Poison" } },
        },
    }
end

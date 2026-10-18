-- AishUIAura/Core/SpellClassificationOverrides.lua
-- Corrections de classification (info.source) codees en dur, pour les sorts que la decouverte auto classe mal.
-- Applique par ns.ApplyAdminOverrides (Init.lua), prioritaire sur la classification auto-decouverte.
-- deleted=true : sort sans vraie aura suivable, masque en mode normal (visible/annulable via /aishadmin), cf. Tactics.lua.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.SpellClassificationOverrides = {
    [118]     = { source = "debuff" }, -- Metamorphose
    [122]     = { source = "debuff" }, -- Nova de givre
    [408]     = { source = "debuff" }, -- Aiguillon perfide
    [453]     = { source = "debuff" }, -- Apaisement
    [686]     = { deleted = true }, -- Trait de l'ombre
    [702]     = { source = "debuff" }, -- Malediction de faiblesse
    [703]     = { source = "debuff" }, -- Garrot
    [980]     = { source = "debuff" }, -- Agonie
    [1064]    = { deleted = true }, -- Salve de guerison
    [1513]    = { source = "debuff" }, -- Effrayer une bete
    [1776]    = { source = "debuff" }, -- Suriner
    [1833]    = { source = "debuff" }, -- Coup bas
    [1943]    = { source = "debuff" }, -- Rupture
    [2094]    = { source = "debuff" }, -- Cecite
    [2484]    = { source = "totem" }, -- Totem de lien terrestre
    [2645]    = { source = "buff" }, -- Loup fantome
    [2818]    = { source = "debuff" }, -- Poison mortel
    [3355]    = { source = "debuff" }, -- Piege givrant
    [3409]    = { source = "debuff" }, -- Poison affaiblissant
    [5116]    = { source = "debuff" }, -- Trait de choc
    [5394]    = { source = "totem" }, -- Totem guerisseur
    [5484]    = { source = "debuff" }, -- Hurlement de terreur
    [5760]    = { source = "debuff" }, -- Poison ankylosant
    [8122]    = { source = "debuff" }, -- Cri psychique
    [8143]    = { source = "totem" }, -- Totem de seisme
    [8178]    = { source = "totem" }, -- Totem de glebe
    [8680]    = { source = "debuff" }, -- Poison douloureux
    [8936]    = { source = "buff" }, -- Retablissement
    [12654]   = { source = "debuff" }, -- Enflammer
    [15487]   = { source = "debuff" }, -- Silence
    [19434]   = { deleted = true }, -- Visee
    [20271]   = { source = "debuff" }, -- Jugement
    [26573]   = { source = "totem" }, -- Consecration
    [27243]   = { source = "debuff" }, -- Graine de Corruption
    [31589]   = { source = "debuff" }, -- Lenteur
    [31661]   = { source = "debuff" }, -- Souffle du dragon
    [32645]   = { source = "debuff" }, -- Envenimer
    [33786]   = { source = "debuff" }, -- Cyclone
    [34914]   = { source = "debuff" }, -- Toucher vampirique
    [42650]   = { source = "totem" }, -- Armee des morts
    [47541]   = { source = "buff" }, -- Voile mortel
    [48181]   = { source = "debuff" }, -- Hanter
    [49206]   = { source = "totem" }, -- Invocation d'une gargouille
    [51485]   = { source = "totem" }, -- Totem de poigne de terre
    [51505]   = { deleted = true }, -- Explosion de lave
    [53563]   = { source = "buff" }, -- Guide de lumiere
    [57994]   = { deleted = true }, -- Cisaille de vent
    [61391]   = { source = "debuff" }, -- Typhon
    [73920]   = { source = "totem" }, -- Pluie guerisseuse
    [77472]   = { deleted = true }, -- Vague de soins
    [77505]   = { source = "debuff" }, -- Seisme
    [77575]   = { source = "debuff" }, -- Poussee de fievre
    [79206]   = { source = "buff" }, -- Grace du marcheur des esprits
    [81281]   = { source = "debuff" }, -- Croissance fongique
    [82691]   = { source = "debuff" }, -- Anneau de givre
    [98008]   = { source = "totem" }, -- Totem de lien d'esprit
    [102359]  = { source = "debuff" }, -- Enchevetrement de masse
    [105174]  = { deleted = true }, -- Main de Gul'dan
    [108271]  = { source = "buff" }, -- Transfert astral
    [108280]  = { source = "totem" }, -- Totem de maree de soins
    [108287]  = { deleted = true }, -- Projection totemique
    [111685]  = { source = "totem" }, -- Invocation : infernal
    [114050]  = { source = "buff" }, -- Ascendance
    [115175]  = { source = "buff" }, -- Brume apaisante
    [115294]  = { source = "buff" }, -- The de mana
    [116849]  = { source = "buff" }, -- Cocon de vie
    [117405]  = { source = "debuff" }, -- Tir de lien
    [117526]  = { source = "debuff" }, -- Tir de lien
    [118905]  = { source = "totem" }, -- Totem condensateur
    [123040]  = { source = "totem" }, -- Torve-esprit
    [124682]  = { source = "buff" }, -- Brume enveloppante
    [135299]  = { source = "debuff" }, -- Piege de goudron
    [155158]  = { source = "debuff" }, -- Brulure meteorique
    [155625]  = { source = "debuff" }, -- Eclat lunaire
    [157299]  = { source = "totem" }, -- Elementaire de tempete
    [157997]  = { source = "debuff" }, -- Nova de glace
    [179057]  = { source = "debuff" }, -- Nova du chaos
    [188196]  = { deleted = true }, -- Eclair
    [188443]  = { deleted = true }, -- Chaine d'eclairs
    [188592]  = { source = "totem" }, -- Elementaire de feu
    [188616]  = { source = "totem" }, -- Elementaire de terre
    [190784]  = { source = "buff" }, -- Palefroi divin
    [192058]  = { source = "totem" }, -- Totem condensateur
    [192063]  = { deleted = true }, -- Bourrasque
    [192077]  = { source = "totem" }, -- Totem de bouffee de vent
    [193332]  = { source = "totem" }, -- Appel des traqueffrois
    [195645]  = { source = "debuff" }, -- Coupure d'ailes
    [198034]  = { source = "debuff" }, -- Marteau divin
    [199824]  = { source = "debuff" }, -- Demon psychique
    [200174]  = { source = "totem" }, -- Torve-esprit
    [204066]  = { source = "debuff" }, -- Rayon lunaire
    [204330]  = { source = "totem" }, -- Totem de courroux
    [204331]  = { source = "totem" }, -- Totem de replique
    [204336]  = { source = "totem" }, -- Totem de glebe
    [204490]  = { source = "debuff" }, -- Sigil de silence
    [204598]  = { source = "debuff" }, -- Sigil de feu
    [204843]  = { source = "debuff" }, -- Sigil de chaines
    [205180]  = { source = "totem" }, -- Invocation de Regard-noir
    [205708]  = { source = "debuff" }, -- Transi
    [207407]  = { source = "debuff" }, -- Dechirement d'ame
    [207685]  = { source = "debuff" }, -- Sigil de supplice
    [207777]  = { source = "debuff" }, -- Demantelement
    [209749]  = { source = "debuff" }, -- Essaim de lucioles
    [210824]  = { source = "debuff" }, -- Toucher des magi
    [215406]  = { source = "debuff" }, -- Malade
    [217200]  = { source = "debuff" }, -- Tir acere
    [232559]  = { source = "debuff" }, -- Epines
    [247456]  = { source = "debuff" }, -- Fragilite
    [256148]  = { source = "debuff" }, -- Fil de fer
    [257284]  = { source = "debuff" }, -- Marque du chasseur
    [264130]  = { deleted = true }, -- Siphon de puissance
    [264178]  = { deleted = true }, -- Trait demoniaque
    [268877]  = { source = "buff" }, -- Enchainement bestial
    [269576]  = { source = "debuff" }, -- Maitre tireur
    [315341]  = { source = "debuff" }, -- Entre les deux yeux
    [321538]  = { source = "debuff" }, -- Effusion de sang
    [325153]  = { source = "debuff" }, -- Tonneau explosif
    [335467]  = { source = "debuff" }, -- Mot de l'ombre : Folie
    [354896]  = { source = "debuff" }, -- Venin rampant
    [355580]  = { source = "totem" }, -- Totem de champ statique
    [355689]  = { source = "debuff" }, -- Glissement de terrain
    [356608]  = { source = "debuff" }, -- Danse mortelle
    [357209]  = { source = "debuff" }, -- Souffle de feu
    [360194]  = { source = "debuff" }, -- Marque letale
    [360806]  = { source = "debuff" }, -- Somnambulisme
    [370898]  = { source = "debuff" }, -- Froid envahissant
    [370969]  = { source = "debuff" }, -- La traque
    [372048]  = { source = "debuff" }, -- Rugissement oppressant
    [372245]  = { source = "debuff" }, -- Terreur des cieux
    [378080]  = { source = "debuff" }, -- Affaiblissement
    [378081]  = { source = "buff" }, -- Rapidite de la nature
    [383013]  = { source = "totem" }, -- Totem de purification du poison
    [383121]  = { source = "debuff" }, -- Metamorphose de masse
    [383414]  = { source = "debuff" }, -- Poison amplifiant
    [383843]  = { source = "debuff" }, -- Resolution du croise
    [384352]  = { source = "buff" }, -- Vents funestes
    [385627]  = { source = "debuff" }, -- Plaie des rois
    [386770]  = { source = "debuff" }, -- Froid glacial
    [389823]  = { source = "debuff" }, -- Eclat de glace
    [389831]  = { source = "debuff" }, -- Eclat de glace
    [390181]  = { source = "debuff" }, -- Balafre d'ame
    [390612]  = { source = "debuff" }, -- Bombe de givre
    [391191]  = { source = "debuff" }, -- Blessure brulante
    [392388]  = { source = "debuff" }, -- Poison atrophiant
    [392401]  = { source = "debuff" }, -- Garrot ameliore
    [394095]  = { source = "debuff" }, -- Plaie des rois
    [394119]  = { source = "debuff" }, -- Matraque
    [403516]  = { source = "debuff" }, -- Diviser pour mieux regner
    [406971]  = { source = "debuff" }, -- Rugissement oppressant
    [408544]  = { source = "debuff" }, -- Heurt sismique
    [421976]  = { source = "debuff" }, -- Eclaboussures caustiques
    [426593]  = { source = "debuff" }, -- Morsure de Gueuletripe
    [428737]  = { source = "totem" }, -- Harmonie du Bosquet
    [430589]  = { source = "buff" }, -- Exposition atmospherique
    [431620]  = { source = "debuff" }, -- Soulevement
    [432502]  = { source = "debuff" }, -- Arme sacree
    [434424]  = { source = "buff" }, -- Ame divisee
    [434473]  = { source = "debuff" }, -- Bombardements
    [439531]  = { source = "debuff" }, -- Lianes sanguinaires
    [441201]  = { source = "debuff" }, -- Presence menacante
    [441224]  = { source = "debuff" }, -- Trouble
    [442396]  = { source = "debuff" }, -- Entraves des tenebres
    [442624]  = { source = "debuff" }, -- Marque du saccageur
    [442804]  = { source = "debuff" }, -- Malediction des Satyres
    [443591]  = { source = "buff" }, -- Unite interne
    [444995]  = { source = "totem" }, -- Totem deferlant
    [450193]  = { source = "totem" }, -- Faille entropique
    [450763]  = { source = "buff" }, -- Aspect de l'harmonie
    [451210]  = { source = "debuff" }, -- Plus d'echappatoire
    [451235]  = { source = "totem" }, -- Ame en peine du Vide
    [453268]  = { source = "debuff" }, -- Destruction controlee
    [453848]  = { source = "buff" }, -- Impulsion electrique
    [455122]  = { source = "debuff" }, -- Lances de pergelisol
    [457129]  = { source = "debuff" }, -- Marque de necrotraqueur
    [458128]  = { source = "buff" }, -- Faux purulente
    [458169]  = { source = "debuff" }, -- Hyperpyrexie
    [459808]  = { source = "debuff" }, -- Fleche gemissante
    [460697]  = { source = "totem" }, -- Totem de courroux
    [467718]  = { deleted = true }, -- Fleches sinistres
    [467745]  = { source = "debuff" }, -- Dague de l'ombre
    [1221389] = { source = "debuff" }, -- Gel
    [1222865] = { source = "debuff" }, -- Pointe glaciaire !
    [1233448] = { source = "buff" }, -- Sombre transformation
    [1241521] = { source = "buff" }, -- Faucheur d'ame
    [1246032] = { source = "debuff" }, -- Potentiel explosif
    [1246832] = { source = "debuff" }, -- Glacons
    [1247378] = { source = "debuff" }, -- Putrefier
    [1253138] = { source = "debuff" }, -- Attaque !
    [1253171] = { source = "debuff" }, -- Bombe de feu de brousse
    [1253601] = { source = "debuff" }, -- Marque de sentinelle
    [1253836] = { source = "debuff" }, -- Armes sanctifiees
    [1256667] = { source = "debuff" }, -- Catastrophe
    [1258134] = { source = "debuff" }, -- Toucher de l'archimage
    [1258508] = { source = "debuff" }, -- Intimidation
    [1258862] = { source = "buff" }, -- Froid cryogenique
    [1259790] = { source = "debuff" }, -- Affliction instable
    [1260251] = { source = "debuff" }, -- Condamnation a mort
    [1262887] = { source = "debuff" }, -- Enflammer
    [1263768] = { deleted = true }, -- Benediction par la Lumiere
    [1264521] = { source = "debuff" }, -- Decouverte des faiblesses
    [1267016] = { source = "totem" }, -- Totem de flux tempetueux
    [1267089] = { source = "totem" }, -- Totem de flux tempetueux
    [1268673] = { source = "debuff" }, -- Pieds froids
    [1270065] = { source = "buff" }, -- Ronces vicieuses
    [1270828] = { source = "debuff" }, -- Vol de sort
    [1271748] = { source = "debuff" }, -- Chancre de faiblesse
    [1271802] = { source = "debuff" }, -- Chancre des langages
    [1280172] = { source = "totem" }, -- Ombrefiel
    [1280213] = { source = "debuff" }, -- Croissance fongique
    [1292919] = { source = "debuff" }, -- Coalescence
    [1294745] = { source = "buff" }, -- Vent inflexible du roi
    [1295942] = { source = "debuff" }, -- Trait prismatique !
    [1301410] = { source = "debuff" }, -- Brulure
    [1302139] = { source = "debuff" }, -- Sceau de represailles
    [1307531] = { deleted = true }, -- Saignee
    [1307888] = { source = "totem" }, -- Pluie guerisseuse
}

-- Forever seulement (classement fait en mode admin sur Forever). Applique apres la table commune ci-dessus,
-- jamais sur Retail : plusieurs sorts de paladin Retail y sont masques, ce qui serait faux sur Retail.
ns.SpellClassificationOverridesForever = {
    [99]      = { source = "debuff" }, -- Rugissement demoralisant
    [143]     = { source = "debuff" }, -- Boule de feu
    [205]     = { source = "debuff" }, -- Eclair de givre
    [339]     = { source = "debuff" }, -- Sarments
    [370]     = { deleted = true }, -- Expiation
    [548]     = { deleted = true }, -- Eclair
    [603]     = { source = "debuff" }, -- Plaie funeste
    [707]     = { source = "debuff" }, -- Immolation
    [770]     = { source = "debuff" }, -- Lucioles
    [772]     = { source = "debuff" }, -- Pourfendre
    [865]     = { source = "debuff" }, -- Nova de givre
    [1079]    = { source = "debuff" }, -- Dechirure
    [1130]    = { source = "debuff" }, -- Marque du chasseur
    [1160]    = { source = "debuff" }, -- Cri demoralisant
    [1725]    = { source = "debuff" }, -- Distraction
    [1822]    = { source = "debuff" }, -- Griffure
    [2637]    = { source = "debuff" }, -- Hibernation
    [2908]    = { source = "debuff" }, -- Apaiser les animaux
    [2944]    = { source = "debuff" }, -- Peste devorante
    [2974]    = { source = "debuff" }, -- Coupure d'ailes
    [3043]    = { source = "debuff" }, -- Piqure de scorpide
    [5209]    = { source = "debuff" }, -- Rugissement provocateur
    [5246]    = { source = "debuff" }, -- Cri d'intimidation
    [5570]    = { source = "debuff" }, -- Essaim d'insectes
    [5782]    = { source = "debuff" }, -- Peur
    [6136]    = { source = "debuff" }, -- Transi
    [6343]    = { source = "debuff" }, -- Coup de tonnerre
    [6788]    = { source = "debuff" }, -- Ame affaiblie
    [6795]    = { source = "debuff" }, -- Grondement
    [7386]    = { source = "debuff" }, -- Fracasser armure
    [7402]    = { source = "debuff" }, -- Coup railleur
    [8053]    = { source = "debuff" }, -- Horion de flammes
    [8056]    = { source = "debuff" }, -- Horion de givre
    [8092]    = { deleted = true }, -- Attaque mentale
    [8179]    = { source = "totem" }, -- Totem de Glebe (passif)
    [8492]    = { source = "debuff" }, -- Cone de froid
    [8512]    = { source = "totem" }, -- Totem Furie-des-vents
    [8639]    = { source = "debuff" }, -- Rupture
    [8921]    = { source = "debuff" }, -- Eclat lunaire
    [9005]    = { source = "debuff" }, -- Traquenard
    [9484]    = { deleted = true }, -- Entraves des morts-vivants
    [10428]   = { source = "totem" }, -- Totem de Griffes de pierre
    [10495]   = { source = "totem" }, -- Totem Fontaine de mana
    [10894]   = { source = "debuff" }, -- Mot de l'ombre : Douleur
    [11198]   = { source = "debuff" }, -- Exposer l'armure
    [12355]   = { source = "debuff" }, -- Impact
    [12494]   = { source = "debuff" }, -- Morsure du givre
    [12505]   = { source = "debuff" }, -- Explosion pyrotechnique
    [13018]   = { source = "debuff" }, -- Vague explosive
    [13553]   = { source = "debuff" }, -- Morsure de serpent
    [13797]   = { source = "debuff" }, -- Piege d'immolation
    [14280]   = { source = "debuff" }, -- Morsure de vipere
    [15257]   = { source = "debuff" }, -- Tissage de l'ombre
    [15286]   = { source = "debuff" }, -- Etreinte vampirique
    [15326]   = { source = "debuff" }, -- Aveuglement
    [16387]   = { source = "totem" }, -- Totem Langue de feu
    [16511]   = { source = "debuff" }, -- Hemorragie
    [16922]   = { source = "debuff" }, -- Feu stellaire etourdissant
    [17364]   = { source = "buff" }, -- Courroux naturel
    [17928]   = { source = "debuff" }, -- Hurlement de terreur
    [18119]   = { source = "debuff" }, -- Consequences
    [18223]   = { source = "debuff" }, -- Malediction de fatigue
    [19185]   = { source = "debuff" }, -- Piege
    [20184]   = { source = "debuff" }, -- Jugement de justice
    [20185]   = { source = "debuff" }, -- Jugement de lumiere
    [20186]   = { source = "debuff" }, -- Jugement de sagesse
    [21183]   = { source = "debuff" }, -- Jugement du Croise
    [21553]   = { source = "debuff" }, -- Frappe mortelle
    [23694]   = { source = "debuff" }, -- Brise-genou ameliore
    [31935]   = { deleted = true }, -- Bouclier du vengeur
    [53600]   = { deleted = true }, -- Bouclier du vertueux
    [156910]  = { deleted = true }, -- Guide de foi
    [190456]  = { deleted = true }, -- Dur au mal
    [275779]  = { deleted = true }, -- Jugement
    [383346]  = { deleted = true }, -- Expurgation
    [412538]  = { source = "debuff" }, -- Enflammer
    [412609]  = { source = "debuff" }, -- Blessure profonde
    [431380]  = { deleted = true }, -- Aubastre
    [431752]  = { deleted = true }, -- Volonte de l'aube
    [432502]  = { source = "debuff", deleted = true }, -- Arme sacree
    [432629]  = { deleted = true }, -- Verdict unanime
    [440667]  = { source = "debuff" }, -- Justification
    [469882]  = { deleted = true }, -- Feu d'affinage
    [1235826] = { source = "debuff" }, -- Lacerer
    [1237312] = { source = "debuff" }, -- Eclair de givrefeu
    [1238289] = { source = "debuff" }, -- Lien terrestre
    [1241413] = { deleted = true }, -- Marteau de courroux
    [1260251] = { source = "debuff", deleted = true }, -- Condamnation a mort
    [1277038] = { deleted = true }, -- Arbitrage
    [1277455] = { source = "debuff" }, -- Eclair deconcertant
    [1310703] = { source = "debuff" }, -- Toxine
    [1320379] = { source = "debuff" }, -- Metamorphose
    [1324401] = { source = "debuff" }, -- Contresort  Silence
    [1324415] = { source = "debuff" }, -- Entraves des Morts-vivants
    [1324427] = { source = "debuff" }, -- Silence
    [1324459] = { source = "debuff" }, -- Voile mortel
    [1324462] = { source = "debuff" }, -- Bannir
    [1324473] = { source = "debuff" }, -- Plaie de tumulte
    [1324474] = { source = "debuff" }, -- Aiguillon perfide
    [1324477] = { source = "debuff" }, -- Cecite
    [1324481] = { source = "debuff" }, -- Suriner
    [1324482] = { source = "debuff" }, -- Assommer
    [1324485] = { source = "debuff" }, -- Silence  Coup de pied
    [1324487] = { source = "debuff" }, -- Sonner
    [1324494] = { source = "debuff" }, -- Intimidation
    [1324499] = { source = "debuff" }, -- Fleche de dispersion
    [1324500] = { source = "debuff" }, -- Piege givrant
    [1324506] = { source = "debuff" }, -- Effrayer une bete
    [1324511] = { source = "debuff" }, -- Trait de choc ameliore
    [1324513] = { source = "debuff" }, -- Marteau de la justice
    [1324538] = { source = "debuff" }, -- Repentir
    [1324543] = { source = "debuff" }, -- Renvoi des Morts-vivants
    [1324558] = { source = "debuff" }, -- Desarmement
    [1326053] = { source = "debuff" }, -- Frost Blast
}

-- Auras que le joueur lance sur SON familier mais qui lui appartiennent (buff perso). Aucun viewer
-- CDM ne les liste cote joueur -- l'aura vit sur le pet -- elles ne seraient donc ni auto-decouvertes
-- ni scannees. Declarees ici, elles sont enregistrees pour la spec voulue (source "buff", categorie
-- Buffs) par CDMHooks, et Scan lit leur duree/leurs stacks sur l'unite indiquee.
-- specKey : cle ns.GetSpecKey() ("CLASSE_SPE", cf. Defaults.lua::SPEC_MAP), nil = toutes les specs.
ns.PetAuraSpells = {
    [1233448] = { unit = "pet", specKey = "DEATHKNIGHT_UNHOLY" }, -- Sombre transformation
}

function ns.GetPetAuraUnit(spellID)
    local def = spellID and ns.PetAuraSpells and ns.PetAuraSpells[spellID]
    return def and def.unit or nil
end

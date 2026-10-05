# Plan : optimisation mémoire, exports, import/export par modules

État mesuré le 2026-10-02 sur le compte d'Aishuu (retail, version 4.0.9 + travaux en cours).

## Avancement (2026-10-04)

Codé, compilé (Lua 5.1) et testé hors jeu sur une copie de la SV. **Reste à tester en jeu.**

- **Étape 1 faite** — sorts creux :
  - `Modules/Auras/Core/Defaults.lua` : `ns.SPELL_MT` (`__index` vers `ns.SpellDefaults`, sous-table
    `destinations` copiée dans l'entrée au 1er accès), `ns.NewSpellEntry()`, `ns.HydrateSpellLists`.
  - `Profiles.lua` : `EnsureProfile` compacte (scalaires) + pose la métatable ; `PLAYER_LOGOUT`
    compacte tous les profils, `destinations` tout-false compris. Création d'entrées via
    `ns.NewSpellEntry` (PullDiscovery, CDMHooks, Totems).
  - `_glowCustom` n'est jamais retiré (nil = « sort ancien » pour la migration d'`InitDB`).
  - Lectures sur tous les sorts passées en `rawget(info, "destinations")` (CenterArc,
    MigrateRenderKeys) pour ne pas recréer les tables.
  - Mesure : `discoveredSpells` 4,29 Mo → 1,07 Mo (sérialisation compacte), 190 340 champs relus
    identiques.
  - Doublons racine tranchés : la racine d'`AishUIAuraDB` est un reliquat, plus jamais lu.
    Purge one-shot `_rootPurgeV1` (racine + anciennes clés `flow/instinct/sense/wargear*` et
    `buffs/debuffs/procs/cooldowns` dans les profils). `InitDB` n'y écrit plus les défauts.
  - Non fait : suppression pure des sorts jamais activés (gain faible une fois creux).
- **Étape 2 faite** — `Config/ProfileModules.lua` (registre, module `misc` de repli pour toute
  clé non déclarée) ; `P.BuildModulePayload`, `P.ExportModules`, `P.DecodeExport` (V1 converti),
  `P.Export` = V2 tous modules ; `P.Import` lit V1 et V2. Libs embarquées dans `Libs/` (LibStub,
  LibDeflate v3, LibSerialize v6) : elles n'étaient fournies que par d'autres addons.
  Mesure : export du profil Default ≈ 130 Ko (731 sorts personnalisés sur 4 034).
- **Mesuré en jeu** : SavedVariable 5,7 Mo → 2 Mo (soit ~15 Mo → ~6 Mo de tables en RAM).
- **Données compactes** (remplace le LoadOnDemand `AishCore_Data`, sans nouvel addon ni changement
  d'installeur) :
  - `Libs/SpellSchools.lua` : enregistrements base 64 triés + recherche dichotomique derrière une
    métatable (`ns.SpellGradients[id]` / `ns.SpellSchools[id]` inchangés). 6,3 Mo → 0,56 Mo.
  - `Data/ModelPaths.lua` : une ligne `fileId nom` par modèle dans une seule chaîne ;
    `ns.GetModelName`, `ns.BuildModelList` (décodé à l'ouverture du picker, libéré à `OnHide`).
    3,3 Mo d'arbre + ~1,5 Mo aplati résident → 0,33 Mo. `generate_model_paths.py` produit ce format.
  - Code mort retiré : `ns.EnsureModelPaths` / `ReleaseModelPaths` (Auras), aplatissement au login.
- **Étape 3 faite** — `Data/SearchIndex.lua` (généré par `generate_search_index.py`, à relancer
  après ajout d'options) : clés de locale par page ; la recherche ne construit plus aucune page.
- **Étape 7 faite (refondue)** — granularité fine, calquée sur la page "Modules" :
  - `Config/ProfileModules.lua` : `ns.ProfileTree` (section > élément > sous-élément). Chaque nœud
    déclare des chemins (`"unitBars.bars.pet"`, ou `{ path = "spellEffects", except = {...} }`) dans
    le profil AishCore (`core`) ou Auras (`auras`), + `apply`. Nœud `misc` = clés non déclarées.
  - `Config/Profiles.lua` : `P.BuildItemsPayload`, `P.ExportItems`, `P.DecodeExport` (V1 / V2
    convertis), `P.ApplyItems` (remplace chaque chemin ; absent = réinitialisation template/défauts),
    `P.CopyItems`, `P.ResetItems`, `P.Import(str, nom, ids)`. Format `AISHCORE_PROFILE_V3:` =
    `{ v=3, addon, date, items, core, auras }` (seuls les chemins exportés). Compression niveau 5
    (niveau 9 : ~4x plus lent pour ~3 %).
  - `UI/ProfileModulesUI.lua` : 3 fenêtres en style AishCore (strate FULLSCREEN_DIALOG), arbre sur
    3 colonnes avec cases tri-état, régénération de l'export différée (0,35 s après le dernier clic).
  - Section **Animations 3D** (export + page Modules) : réglages communs de `spellEffects` portés par
    la section ; éléments Bibliothèque de modèles, OOC, Sorts, Auras, Buffs manquants, Logos, Globes
    externes. Interrupteurs par type ajoutés (`spellEffects.oocEnabled`, `spellsEnabled`, `aurasEnabled`,
    `missingBuffsEnabled`, `logosEnabled`, + `orbsEnabled` existant), vérifiés dans Modules/SpellEffects.lua.
  - Éléments sans donnée dans le profil source grisés (`P.ProfileItemAvailability`).
  - Mesuré : export du seul familier ≈ 240 caractères ; export complet ≈ 130 Ko.
- **Fuite des pages du GUI** : toute invalidation (`LiveApply` → page Modules, `PROFILE_CHANGED` →
  toutes les pages, changement de spé) jetait la page et la reconstruisait ; WoW ne libère jamais
  une frame. `SW.ReleasePage` coupe désormais scripts, événements et callbacks (relevés par
  `SW.TrackCallbacks` pendant le build). Les frames elles-mêmes restent (inévitable).
- **Profils Auras élagués** : un profil ne stocke plus que ses sorts personnalisés
  (`ns.IsSpellCustomized` / `ns.DropUncustomizedSpells`, Auras/Core/Defaults.lua). Les autres sont
  recréés depuis le registre du compte (`discovery`) à l'activation (`PullDiscovery`, profil actif
  seulement). Élagage : profils inactifs à l'init et à la bascule, tous les profils à la déconnexion,
  export. Couleur auto = `ns.AutoColorKey(profil, spellID)` (hash → clé de Themed Colors) : stable,
  différente par profil, sans stockage. Mesuré : `AishUIAuraDB` ≈ 0,75 Mo sérialisé (3 profils).
  Limite : couleur choisie à la main sur un sort jamais activé non conservée ; renommer un profil
  change les couleurs auto de ses sorts non personnalisés.
- **Locales** : une seule table `ns.L` (socle enUS + langue du client écrite par-dessus) ;
  `frFR.lua` s'arrête d'emblée sur un autre client. `/aish locale` (Locales/Debug.lua) supprimé.
- **Diagnostic** : `/aish mem` (Debug.lua) — mémoire après GC, poids des grosses tables, Mo alloués
  par construction de page.
- **Écartés** :
  - LoadOnDemand `AishCore_Options` : le code du GUI compilé ne pèse que ~1,4 Mo (mesuré), pour un
    chantier à risque élevé.
  - `spellEffects.combos` sans défauts : lectures brutes (`c.delay`, `anim.alpha`…) sans repli,
    ~100 Ko de SV seulement.
- **Reste** : identifier les 112 Mo du GUI avec `/aish mem` (pages les plus lourdes, pages
  reconstruites plusieurs fois).

Deux passes :
- **Passe A — optimisation** (étapes 1 à 5) : réduire la SavedVariable, réparer les exports,
  alléger la RAM.
- **Passe B — modules** (étape 6) : import / export / copie par module entre profils.

La passe A doit **préparer** la passe B : le format d'export V2 de l'étape 2 est conçu dès le
départ autour du registre de modules de l'étape 6 (cf. § 6.1), pour ne pas refaire le format
deux fois.

---

## 1. Constat

La mémoire affichée en jeu (`GetAddOnMemoryUsage`) est de la **mémoire Lua** : tables, chaînes,
closures. Les textures (`Media/`, 55 Mo sur disque) n'y sont **pas** comptées.

| Élément | Taille | Chargé quand |
| --- | --- | --- |
| SavedVariable `WTF/.../SavedVariables/AishCore.lua` | **6,0 Mo** texte | toujours |
| ↳ `AishUIAuraDB.profiles.*.discoveredSpells` | **4,9 Mo** | toujours |
| ↳ `AishaddonDB._profiles` (2 profils) | 0,62 Mo | toujours |
| ↳↳ dont `spellEffects` (combos d'animations) | 0,46 Mo | toujours |
| ↳ `AishUIAuraDB.discovery` | 0,15 Mo | toujours |
| `Libs/SpellSchools.lua` | 2,5 Mo source | toujours |
| `Data/ModelPaths.lua` (9 700 modèles) | 1,3 Mo source | toujours |
| `UI/SettingsPanel.lua` + menus Auras + widgets | ~1 Mo de code | toujours |
| Locales `enUS` + `frFR` | 0,2 Mo | toujours, les deux |

Ordre de grandeur : 6 Mo de texte en SavedVariable donnent 15 à 25 Mo de tables Lua.
**La SavedVariable est la cause n°1.**

### `discoveredSpells`

- 4 034 sorts répartis sur 80 clés de spé (2 profils), dont **617 activés**.
- Chaque sort stocke ~60 champs, presque tous à leur valeur par défaut
  (`barModelX = 0`, `sparkModelZ = 0`, `barFillTex = ""`, `desat = false`…), y compris les
  sorts désactivés.
- Écrit par `Modules/Auras/Core/Init.lua` (~l.244 : création de l'entrée à la découverte).

### Exports

- Export de profil AishCore : `P.Export` (`Config/Profiles.lua`, ~l.497). Il embarque le
  profil Auras complet (`_auras`, donc `discoveredSpells`) et le sérialise **en texte brut
  non compressé** (`Serialize` maison en `%q`). Résultat : une chaîne de plusieurs Mo, qui
  fige ou fait planter le jeu dans une EditBox.
- L'export Auras (`Modules/Auras/Core/Profiles.lua`, `Prof:Export`) utilise déjà
  `LibSerialize` + `LibDeflate` + `EncodeForPrint` : c'est le bon modèle.

### Doublons dans `AishUIAuraDB`

La racine d'`AishUIAuraDB` contient des clés qui existent aussi dans chaque profil
(`iconlist`, `icons`, `freebars`, `circlebars`, `totems`, `missingBuffs`, `*Enabled`,
`defaultGlow*`, `useNativeCDM`…). À vérifier : laquelle est la source de vérité (`ns.db`
pointe-t-il sur la racine ou sur le profil actif ?). Si la racine est un reliquat d'avant les
profils, la purger dans la migration de l'étape 1 ; sinon, documenter le rôle de chacune.
Indispensable avant l'étape 6 : on ne peut pas copier un module sans savoir où il vit.

---

## 2. Questions annexes

### Model picker
- `Data/ModelPaths.lua` est dans le `.toc` : l'arbre complet est chargé **à chaque login**,
  puis aplati au `PLAYER_ENTERING_WORLD` en `ns._modelFlat` (9 700 petites tables gardées
  toute la session, ~1 à 2 Mo), l'arbre est libéré et un `collectgarbage` est forcé.
- Le pic au login est plus gros que le résidu, et le résidu ne sert que si on ouvre le picker.
- Code mort : `ns.EnsureModelPaths` (`Modules/Auras/Core/Init.lua` ~l.61) tente de charger
  un sous-addon `AishUIAuraModels` qui n'existe plus (héritage de la fusion AishUIAura).
- Piste : sortir `ModelPaths.lua` dans un addon LoadOnDemand (étape 4), chargé à l'ouverture
  du picker, libéré à la fermeture (`ns.ReleaseModelPaths` existe déjà). Gain modéré, effort
  faible.

### Animations (SpellEffects, combos, glows)
- Les **textures** de glow (`Media/Glows`, 31 Mo disque) ne coûtent rien tant qu'elles ne
  sont pas affichées, et ne comptent pas dans la mémoire Lua.
- Les **réglages** : `spellEffects.combos` = 0,37 Mo, du vrai contenu utilisateur, assez
  compact. ~30 % de gain possible en ne stockant pas les valeurs par défaut
  (`rotation = 0`, `delay = 0`, `alpha = 1`, `anchorY = 0`…). Secondaire.
- Le **code** d'animation crée des tables / closures à chaque tick (`ns.AnimateStagger`,
  tickers à 0,016 s) : pas une fuite, mais le compteur monte entre deux passages du GC.
  À regarder en dernier.

### Couleurs thématiques
- `specDefaults` 22 Ko + `colors` 4 Ko, `Modules/Colors.lua` 13 Ko. **Négligeable.**

---

## 3. Passe A — optimisation, par ordre d'impact

### Étape 1 — `discoveredSpells` : ne stocker que les différences (gain principal)

1. Définir un modèle de sort par défaut unique (les ~60 champs et leurs valeurs).
2. À la lecture, poser une métatable `__index` sur chaque entrée vers ce modèle : le code
   qui lit `si.barModelX` continue de marcher sans modification.
3. Migration one-shot (flag de version dans `AishUIAuraDB`, ex. `_sparseSpellsV1`) :
   - supprimer de chaque sort les champs égaux au défaut ;
   - sorts **jamais activés ni personnalisés** : réduire à l'entrée minimale (nom, source,
     priorité) ou supprimer, ils seront redécouverts au besoin ;
   - ne jamais toucher aux sorts activés ou personnalisés ;
   - en profiter pour régler les doublons racine / profil (§ 1).
4. À la création d'un sort découvert, n'écrire que l'entrée minimale.
5. Piège des tables imbriquées (`color`, `destinations`) : une métatable ne protège pas
   l'écriture dans une sous-table partagée. Les sous-tables doivent être propres à chaque
   sort (copiées à la première écriture), jamais celles du modèle.
6. Les métatables ne survivent pas à la sauvegarde : WoW n'écrit que les champs bruts, ce
   qui est exactement le but. Les reposer à chaque chargement (et après import / copie).

Estimation : 4,9 Mo → quelques centaines de Ko. SavedVariable divisée par ~8 à 10.

### Étape 2 — Export compressé, format V2 (déjà découpé en modules)

1. Nouveau format `AISHCORE_PROFILE_V2:` = `LibSerialize` + `LibDeflate` + `EncodeForPrint`.
   Garder la lecture du V1 pour la compatibilité.
2. **Charge utile structurée par modules dès maintenant** (cf. § 6.2), même si l'interface
   de choix des modules n'arrive qu'à l'étape 6 : en passe A, on exporte simplement tous
   les modules.
3. Exclure : caches de découverte (`discovery`), sorts non personnalisés, flags de
   migration (`_*V1`), données de session, réglages propres à l'installation (cf. § 6.1).
4. Les libs sont présentes via le module Auras : vérifier qu'elles sont chargées avant
   `Config/Profiles.lua`, ou les récupérer à l'appel via `LibStub`.

Estimation : chaîne 20 à 50 fois plus courte.

### Étape 3 — Recherche du GUI

La recherche construit **toutes** les pages pour indexer leur texte (`GetCategorySearchText`
dans `UI/SettingsPanel.lua`), et elles restent en cache toute la session. Remplacer par un
index de mots-clés statique par catégorie (libellés des sections + mots-clés), sans
construire les pages.

### Étape 4 — Découpage en addons LoadOnDemand (gros chantier)

Découper n'économise que si les morceaux ne sont **pas tous chargés**. Le gain vient du
LoadOnDemand.

- **`AishCore_Options`** : `UI/SettingsPanel.lua`, menus Auras (`Modules/Auras/UI/**`),
  widgets, chaînes propres aux options. Chargé à `/aish`, au bouton minimap, ou par le
  survol GUI → section (`UI/ModuleHoverOverlay.lua`). Même modèle qu'`EllesmereUIOptions`
  ou `ElvUI_Options`.
- **`AishCore_Data`** : `Libs/SpellSchools.lua` (cast bars colorées par école) et
  `Data/ModelPaths.lua` (picker). Chargé au premier besoin.
- Points durs :
  - tout ce que le cœur appelle dans le GUI passe par une vérification « options chargées ? » ;
  - les fonctions de preview / drag appelées par les modules (`SetPreview`,
    `SetDraggable`…) restent dans le cœur ;
  - `SpellSchools` est consulté en combat par la cast bar : charger `AishCore_Data` au login
    si l'option « couleur par école » est active, sinon jamais ;
  - les SavedVariables restent dans `AishCore` (pas de migration de données) ;
  - l'installeur / packager AishUI doit copier les nouveaux dossiers ;
  - le registre de modules (§ 6.1) reste dans le **cœur** : l'import par code doit marcher
    sans ouvrir le GUI.

### Étape 5 — Divers

- Locales : ne garder que `enUS` + la langue du client (libérer l'autre table).
- `spellEffects.combos` : ne pas stocker les valeurs par défaut.
- Supprimer le code mort `AishUIAuraModels` dans `ns.EnsureModelPaths`.

---

## 4. Passe B — import / export / copie par modules (étape 6)

### 6.1 Registre de modules (source de vérité unique)

Un fichier du cœur, ex. `Config/ProfileModules.lua`, déclare chaque module **une seule fois**.
Export, import, copie entre profils et « réinitialiser ce module » lisent tous ce registre.
Ajouter une fonctionnalité = ajouter ses clés ici.

Découpage proposé, aligné sur les groupes du GUI (`SIDEBAR_GROUPS`,
`UI/SettingsPanel.lua` ~l.12549). Libellés : reprendre les clés de `Locales/enUS.lua`
existantes (`SETTINGS_GROUP_*`), pas de nouvelles traductions libres.

| Module | Libellé (clé de locale) | Clés de `AishaddonDB._profiles[p]` | Clés de `AishUIAuraDB.profiles[p]` |
| --- | --- | --- | --- |
| `unitFrames` | `SETTINGS_GROUP_UNIT_FRAMES` | `unitBars`, `castBar`, `targetCastBar`, `topTargetBar`, `targetAuras`, `groupNumber` | — |
| `combat` | `SETTINGS_GROUP_COMBAT` | `resourceCircle` (dont taille / position / couleurs des orbes : `dotSizes`, `dotPositions`, `dotColors`), `priorityBar`, `prioritySlots`, `cdmEssential`, `cdmUtility`, `cdmBySpec`, `bigCursor`, `rotationHelper` | — |
| `hud` | `SETTINGS_GROUP_WORLD` | `healthCircle`, `outOfCombatResourceCircle`, `xpBar`, `skyriding`, `location`, `afkMode`, `visibility`, `characterArmory` | — |
| `colors` | `SETTINGS_CAT_COLORS` | `colors`, `themes`, `specDefaults` | — |
| `auras` | `SETTINGS_GROUP_AURAS_PROCS` | — | tout le profil Auras **sauf** caches (`discovery`) |
| `animations` | `SETTINGS_SEC_3D_ANIMATIONS` | `spellEffects` **entier** (dont `orbCombos` / `orbsEnabled` = animations posées sur les orbes) | — |
| `modelLibrary` | à créer | `modelCustomTags`, `modelTagKeywords`, `modelTagColors`, `modelTagUserDefined` | — |

Jamais exporté ni copié (propre à l'installation ou technique) : `minimapButton`,
`modulesPanel`, flags `_*V1`, `_editModeLayout`, `_ellesmereSetup`, `_charProfiles`,
`_specProfiles`, `_globalProfile`.

Décisions (validées par Aishuu le 2026-10-04) :
- **Orbes** : taille / position / couleurs (`resourceCircle`) → `combat` ; animations 3D des
  orbes (`spellEffects.orbCombos`, `orbsEnabled`) → `animations`. `spellEffects` va donc
  entier dans `animations` : le registre n'a besoin que de clés de premier niveau.
- **`modelLibrary`** : module à part (nouvelle clé de locale à créer).
- **Statut actif/inactif** : voyage avec le module (`enabled` fait partie du réglage).
  `modulesPanel` reste exclu ; à l'import d'un module, retirer sa catégorie de
  `modulesPanel.categoryOff` sur la cible, sinon il reste masqué.

Forme du registre :

```lua
ns.ProfileModules = {
  { id = "unitFrames", label = "SETTINGS_GROUP_UNIT_FRAMES",
    core  = { "unitBars", "castBar", "targetCastBar", "topTargetBar", "targetAuras", "groupNumber" },
    apply = { "UnitBars", "CastBar", "TargetCastBar", "TopTargetBar", "TargetAuras", "GroupNumber" } },
  { id = "animations", label = "SETTINGS_SEC_3D_ANIMATIONS",
    core  = { "spellEffects" },
    apply = { "SpellEffects" } },
  { id = "auras", label = "SETTINGS_GROUP_AURAS_PROCS",
    auras = "*", aurasExclude = { "discovery" }, apply = "Auras" },
  ...
}
```

`apply` = modules à réappliquer après import / copie (`ApplySettings`, cf. `SafeApply` dans
`Config/Profiles.lua`).

### 6.2 Format d'export V2

```lua
{
  v       = 2,
  addon   = "4.x.y",          -- version qui a exporté
  date    = "2026-10-02",
  modules = {
    unitFrames = { unitBars = {...}, castBar = {...}, ... },
    auras      = { ... },     -- déjà au format "différences seulement" (étape 1)
    ...
  },
}
```

- Un module absent de `modules` n'est pas dans l'export : l'import ne le touche pas.
- À l'import, pour chaque module, chaque clé est **remplacée entièrement** (pas de fusion
  champ par champ), puis `MergeDefaults` complète les clés manquantes. Pas de mélange
  incohérent entre ancien et nouveau réglage.
- Les données par spé (`cdmBySpec`, `prioritySlots`, `specDefaults`, `discoveredSpells`)
  voyagent entières. Option future : « seulement ma classe », pour alléger un export
  partagé à un ami de la même classe.

### 6.3 Interface

**Export**
- Fenêtre d'export : liste de cases à cocher, une par module (toutes cochées par défaut),
  plus « tout ». La chaîne se régénère à chaque changement, avec sa taille affichée.

**Import**
- On colle la chaîne, on clique « Analyser ».
- Affichage : version source, date, et la liste des modules **présents** dans la chaîne,
  à cocher (les absents grisés).
- Cible : « nouveau profil » (nom à saisir) ou « profil existant » (dropdown).
- Avertissement si un module coché va écraser un réglage existant.

**Copie entre profils**
- Dans la page Profils : « Copier depuis » (profil source), cases des modules, profil cible
  = actif par défaut.
- Implémentation : même fonction que l'import, avec la charge utile construite directement
  depuis le profil source (pas de sérialisation).
- Bonus quasi gratuit : bouton « Réinitialiser ce module » (charge utile vide → défauts).

### 6.4 Fonctions (cœur, utilisables sans GUI)

```
P.BuildModulePayload(profileName, moduleIds) -> table
P.ExportModules(profileName, moduleIds)      -> string V2
P.DecodeExport(str)                          -> payload | nil, err   (V1 converti en V2)
P.ApplyModules(payload, targetProfile, moduleIds)
P.CopyModules(srcProfile, dstProfile, moduleIds)
P.ResetModules(profileName, moduleIds)
```

Après `ApplyModules` sur le profil actif :
1. réappliquer les modules listés dans `apply` ;
2. invalider les pages du GUI concernées (`MainFrame.InvalidateCategory`) ;
3. reposer les métatables de l'étape 1 sur les sorts importés.

Sur un profil inactif : écriture seule, rien à réappliquer.

### 6.5 Pièges

- **Profils liés par nom** : un profil AishCore et son profil Auras portent le même nom
  (`AurasProfiles()`, `Config/Profiles.lua`). Copier vers un profil cible doit créer le
  profil Auras s'il manque.
- **Références croisées** : `animations.missingBuffsCombos` vise des sorts de
  `auras.missingBuffs`. Importer l'un sans l'autre doit rester sans erreur (ignorer une
  référence orpheline), pas nécessairement fonctionnel.
- **Positions** : les modules embarquent les positions à l'écran. Un export d'un écran 4K
  importé en 1080p peut placer des éléments hors écran. Option : « ignorer les positions »
  (liste de clés de position par module dans le registre).
- **Version** : refuser proprement un export d'une version plus récente que l'addon
  installé (champ `addon`), ou au minimum avertir.

---

## 5. Protocole de test

À faire sur le PC de test, **jamais directement sur la SavedVariable de référence**.

1. Sauvegarder `WTF/Account/<COMPTE>/SavedVariables/AishCore.lua` (copie datée).
2. Avant chaque étape, relever :
   - la taille du fichier `AishCore.lua` ;
   - la mémoire Lua : `/run UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("AishCore"))`
     juste après login, puis après ouverture du GUI.
3. Étape 1 :
   - login → `/reload` → logout : vérifier la taille de la SavedVariable ;
   - ouvrir chaque mode Auras, vérifier que les sorts activés gardent couleur, glow,
     modèles 3D, destinations ;
   - changer de spé, vérifier les sorts de l'autre spé ;
   - découvrir un nouveau sort, vérifier qu'il apparaît et qu'on peut le personnaliser ;
   - restaurer la copie, relancer : la migration doit repasser proprement.
4. Étape 2 :
   - exporter, mesurer la longueur de la chaîne, l'importer dans un nouveau profil, comparer ;
   - importer un ancien export V1 : doit toujours fonctionner.
5. Étape 4 : tester sans jamais ouvrir le GUI (mémoire au login), puis avec ouverture,
   survol GUI → section, bouton minimap, `/aish`, changement de profil GUI fermé.
6. Étape 6 :
   - exporter chaque module seul, l'importer dans un profil vierge : seul ce module change ;
   - copier `colors` d'un profil à l'autre, profil cible actif puis inactif ;
   - importer `animations` sans `auras` : aucune erreur Lua ;
   - « Réinitialiser ce module » sur `unitFrames` : retour aux défauts, le reste intact.
7. Vérifier aussi la Beta Forever (`_classic_beta_`), qui partage ce code.

---

## 6. Ordre d'exécution

| # | Étape | Prérequis | Risque |
| --- | --- | --- | --- |
| 1 | `discoveredSpells` en différences + migration + doublons racine | copie de la SV | moyen (données utilisateur) |
| 2 | Registre de modules (§ 6.1) + export V2 compressé (tous modules) | 1 | faible |
| 3 | Index de recherche statique | — | faible |
| 4 | Locales, combos sans défauts, code mort | — | faible |
| 5 | LoadOnDemand `AishCore_Data` (SpellSchools, ModelPaths) | — | moyen |
| 6 | LoadOnDemand `AishCore_Options` (GUI) | 3 | élevé (gros chantier) |
| 7 | Interface import / export / copie par modules | 2 | moyen |

Les étapes 1, 2 et 7 sont à faire dans cet ordre. Les autres sont indépendantes.

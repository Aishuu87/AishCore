# Plan — un seul AishCore pour Retail et Forever

Note interne. Objectif : arrêter de maintenir deux copies qui divergent, sans perdre ce qui est
propre à Forever.

## Constat (5 octobre 2026)

- La copie `_classic_beta_` est restée en **4.0.9** : aucun travail fait depuis ne l'a atteinte.
- Ce n'est **pas** une vraie branche Classic. Comparée au commit 4.0.9, elle ne contient presque
  que du travail Retail en cours à l'époque (déjà présent dans `_retail_` aujourd'hui), plus :
  - **Skyriding retiré** (fichier absent du `.toc`, appels supprimés dans `AishCore.lua`,
    `Categories.lua`, `Debug.lua`) ;
  - quelques ajouts faits **directement dans Forever** et absents de Retail :
    `spellEffects.modelLight` (+ `/aish selight`), `SetResourceText` dans `ResourceCircle.lua`
    (texte reposé seulement s'il change).
- Le `.toc` Forever déclare `## Interface: 120100, 16001` : un même dossier peut déjà être chargé
  par les deux clients.

Conclusion : environ 95 % du code est identique. Les différences se gèrent dans le code, pas en
maintenant deux copies.

## Principe : une seule source, Forever en miroir

```
_retail_/.../AishCore   (dépôt git, SEULE source modifiée)
        │  robocopy /MIR (comme OSTinato)
        ▼
_classic_beta_/.../AishCore   (copie, jamais éditée à la main)
```

Les différences de comportement passent par des **tests à l'exécution**, pas par des fichiers
différents.

## Étape 1 — Rapatrier ce qui n'existe que dans Forever

Fusion 3 voies une fois pour toutes (base = commit 4.0.9, « nous » = Retail actuel, « eux » =
Forever), fichier par fichier, avec `git merge-file`. On garde :

- `modelLight` et `/aish selight` (SpellEffects) ;
- l'optimisation `SetResourceText` ;
- tout autre ajout Forever que la fusion fait remonter (liste des conflits relue avec Aishuu).

Les retraits de Skyriding ne sont **pas** recopiés : ils deviennent la règle de l'étape 2.

## Étape 2 — Détection du client et registre des modules

Dans `Core.lua` :

```lua
-- Identité du client. À valider en jeu sur Forever : /dump GetBuildInfo(), WOW_PROJECT_ID
ns.CLIENT = (select(4, GetBuildInfo()) < 20000) and "forever" or "retail"
ns.IsForever = ns.CLIENT == "forever"
```

**Préférer la détection de fonctionnalité** quand elle existe (`C_CooldownViewer`,
`C_PlayerInfo.GetGlidingInfo`, `CooldownViewerSettings`…) : elle reste juste si Blizzard ajoute
ou retire une API d'un client. `ns.IsForever` ne sert que quand aucune API ne tranche.

Chaque module déclare sa disponibilité dans une table unique (`Config/Availability.lua`) :

```lua
ns.MODULE_AVAILABILITY = {
  skyriding  = function() return not ns.IsForever end,
  cdmLayout  = function() return CooldownViewerSettings ~= nil end,
  cdmEssential = function() return CooldownViewerSettings ~= nil end,
  -- absent de la table = disponible partout
}
function ns.IsModuleAvailable(id) ... end
```

Un module indisponible est filtré à **tous** les endroits qui énumèrent les modules :

- démarrage (`SafeCall(... "Create")` dans `AishCore.lua`) : on ne crée rien ;
- page Modules, sidebar et `CATEGORIES` du `SettingsPanel` : l'entrée disparaît ;
- recherche du GUI (`Data/SearchIndex.lua`) : résultats filtrés à l'affichage ;
- arbre de profils (`ns.ProfileTree`) : la case est grisée, les données sont quand même
  conservées à l'import (un profil Retail importé sur Forever puis réexporté ne perd rien) ;
- overlay de survol, catégories des Auras (`Categories.lua`).

Le fichier du module reste chargé par le `.toc` mais sort tout de suite :
`if not ns.IsModuleAvailable("skyriding") then return end` en tête de `Create`.

## Étape 3 — Différences de comportement

Pour un module qui marche « un peu différemment », une branche locale, documentée sur place :

```lua
-- Forever : pas de <API>, on retombe sur <solution>.
if ns.IsForever then ... else ... end
```

Règle : si un module accumule plus de 3 ou 4 branches de ce genre, on sort la partie spécifique
dans un petit fichier `Modules/<Module>_Forever.lua` chargé par les deux clients et qui ne
s'active que sur Forever. Jamais de copie complète d'un module.

## Étape 4 — Synchro et publication

- **Synchro locale** : `robocopy /MIR` de Retail vers `_classic_beta_` après chaque modif, en
  excluant `.git`, `docs`, `__pycache__`, `*.py`, `CLAUDE.md`. Même convention que OSTinato,
  ajoutée au `CLAUDE.md` pour que ce soit systématique.
- **Un seul `.toc`** avec `## Interface: 120100, 16001` (+ `AishUISetupCharDB` dans
  `SavedVariablesPerCharacter`, déjà le cas en Retail). Le packager BigWigs publie le même zip
  pour les deux versions de jeu ; CurseForge reçoit les deux game versions.
- Pack AishUI Forever (packager) : il copie déjà `AishCore` depuis `_classic_beta_` →
  il récupère automatiquement la version synchronisée.

## Étape 5 — Garde-fous

- `/aish client` (Debug) : affiche le client détecté et la liste des modules désactivés.
- Avant chaque publication : vérifier en jeu sur Forever le `/reload` sans erreur et la page
  Modules (modules indisponibles absents).
- Les erreurs « API inconnue » sur Forever indiquent un module oublié dans
  `MODULE_AVAILABILITY` : on l'y ajoute plutôt que de bricoler un `if` local.

## Cas des Auras : séparer la source, pas le module

Le module Auras (« Auras à tracker », icônes, barres, totems…) se découpe en deux couches :

- **source** : d'où viennent les auras et leurs durées. En Retail, les hooks du Cooldown Manager
  (`CDMHooks.lua`) et les spellIDs Retail ; sur Forever, le scan `UNIT_AURA` et les spellIDs
  à rangs du client.
- **rendu + UI + profils** : affichage, animations, menus, listes par spé. Commun.

Plutôt que deux modules complets, on garde un seul module avec **deux fournisseurs de données**
interchangeables (`Modules/Auras/Sources/Retail.lua`, `Sources/Forever.lua`), choisis au
chargement. Si une partie du rendu diverge vraiment, elle peut aussi avoir sa variante, mais
seulement cette partie. À cadrer quand on attaquera le module (étape 3).

## Avancement

- **Étape 1 — fait (5 octobre 2026)**, fusion 3 voies appliquée dans Retail :
  - `Core.lua` : shim de spé Forever (spé déduite des branches de talents, `/aishspec`)
    exécuté **uniquement si `ns.IsForever`** (réassigner ces globals en Retail les taint) ;
    `ns.CLIENT` / `ns.IsForever` ; `ns.DedupeSpellRanks` (rangs de sorts).
  - `ResourceMap.lua` : tables Retail intactes, overrides Forever (mana partout sauf voleur,
    guerrier, druide selon forme ; pas de ressources secondaires).
  - `OutOfCombatResourceCircle.lua` : mana pour toutes les spés sur Forever seulement.
  - `PriorityBar.lua` : remontée au rang le plus haut + dédoublonnage, Forever seulement.
  - `SpellEffects.lua` : éclairage / brouillard des modèles, défaut `none` en Retail,
    `off` / `far0` sur Forever ; rang du même sort reconnu sur Forever seulement.
  - `SettingsPanel.lua` : `[ext]` et combos orphelins en mode admin (commun) ; combo druide
    Gardien et regroupement des rangs Forever seulement.
  - `Profiles.lua` : événements de talents + invalidation du cache de spé, Forever seulement.
  - `Init.lua`, `Presets.lua`, `Location.lua`, `ResourceCircle.lua`, `Tactics.lua`,
    `AishUISetup.lua` : repris tels quels (neutres en Retail).
  - Non repris : retraits de Skyriding (→ étape 2), textes de l'ancien CDM par spé.
- **Étape 2 — fait (5 octobre 2026)** :
  - `Core.lua` : `ns.CLIENT`, `ns.IsForever` (build 1.60.x = interface 16001, `< 20000`),
    `MODULE_RULES`, `ns.IsModuleAvailable`, `ns.PruneUnavailable`.
  - Règles actuelles : Skyriding absent de Forever ; `cdmLayout` / `cdmEssential` / `cdmUtility`
    seulement si `C_CooldownViewer` existe (Forever a un CDM, comportement encore à vérifier).
  - Filtrage : `Skyriding.lua` ne s'enregistre pas, `SafeCall` l'ignore sans erreur, page Modules,
    `CATEGORIES`, sidebar (donc recherche), arbre de profils (nœud masqué mais clés couvertes),
    catégories d'Auras.
- **Étape 4 — synchro en place** : copie Forever remplacée par le miroir Retail (règle robocopy
  dans `CLAUDE.md`). Ancienne copie sauvegardée :
  `AISH UI\Backup Auto\AishCore_Forever_4.0.9_avant_unification.zip`.
- **Reste** : validation en jeu sur Forever (`/aishspec`, page Modules, `/reload` sans erreur),
  puis étape 3 au fil des modules (Auras en premier).

## Ordre de travail proposé

1. Fusion 3 voies (étape 1), revue des conflits avec Aishuu.
2. Détection + registre + filtrage partout (étape 2), Skyriding comme premier cas.
3. Validation en jeu sur Forever : `/dump GetBuildInfo()` pour fixer la détection, puis tour
   des modules pour remplir `MODULE_AVAILABILITY` (CDM, Extra Barres, cadres Blizzard…).
4. Synchro robocopy + règle dans `CLAUDE.md` ; suppression de la copie divergente.

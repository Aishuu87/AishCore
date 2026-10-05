# Consignes de travail — AishCore

Instructions permanentes d'Aishuu. Elles priment sur les comportements par défaut du harness.

## Langue et ton

- Répondre **en français**. Les termes techniques (frame, texture, spell ID, commit, tag…) restent en anglais, mais les phrases sont en FR.
- Commentaires **courts et concis**. Pas de pavés, pas de récapitulatifs interminables.
- Si une explication longue est vraiment utile, l'écrire dans un `.md` du dépôt (contexte pour une session future) plutôt que dans la réponse.

## Confiance dans le diagnostic d'Aishuu

- Il connaît son addon. Quand il affirme « le problème vient du mode d'affichage : Icônes », c'est **certain à 100 %** : chercher la cause à cet endroit, ne pas remettre en doute ni proposer d'autres pistes « au cas où ».
- Il fait **toujours un `/reload` avant de tester**. Ne jamais le lui rappeler ni supposer que la manip a été oubliée.

## Aucune référence à Claude

Nulle part : messages de commit, tags annotés, patch notes, descriptions de release, noms de fichiers, commentaires de code, README, CHANGELOG.

- Pas de `Co-Authored-By: Claude ...`.
- Pas de « 🤖 Generated with Claude Code » dans les PR ou les releases.
- L'addon est publié sous le seul nom d'Aishuu sur CurseForge.

## Patch notes

Deux choses distinctes :

**Mes notes de travail** — je peux tenir mes propres patch notes librement au fil des sessions (récap des changements, notes techniques). Aucune autorisation à demander.

**Les patch notes publiées** (tag annoté, release GitHub, CurseForge) — ce ne sont **jamais** les miennes. Au moment de publier une version, demander à Aishuu s'il veut inclure ses propres patch notes, et utiliser les siennes. Ne rien publier de rédigé par moi sans qu'il l'ait validé.

Style du dépôt : **tout ce qui est publié est en anglais** — sujet de commit (`Fix ..., bump to X.Y.Z`)
comme corps du tag annoté, sous forme de puces courtes. CurseForge est international.

Quand Aishuu fournit ses notes en français, les traduire, en reprenant les **libellés officiels
de `Locales/enUS.lua`** plutôt que des traductions libres : les joueurs doivent retrouver exactement
les noms affichés dans les options. Ex. « Barre de rotation » → *Priority Bar*, « Bouton de rotation » →
*Rotation Button Module*, « Couleurs Thématiques » → *Themed Colors*.

Les échanges en session restent en français (cf. section Langue et ton).

## « Publie cette version » / « Push cette nouvelle version »

Ces deux phrases signifient : **publier sur GitHub pour déclencher la validation CurseForge**. Aishuu a déjà validé de son côté que la version est OK — ne pas redemander confirmation du contenu.

Procédure :

1. Bumper `## Version:` dans le `.toc` (et toute constante de version dans le code) si ce n'est pas déjà fait.
2. Commit sur `main` (sujet anglais, `bump to X.Y.Z`).
3. **Demander ses patch notes** (cf. section ci-dessus), puis tag annoté `vX.Y.Z` avec ce message.
4. `git push origin main --follow-tags`.

Le push du tag déclenche `.github/workflows/release.yml` → `BigWigsMods/packager` → upload CurseForge via `CF_API_KEY`. Remote : `https://github.com/Aishuu87/AishCore.git`.

## Installeur et packager — copie dans Backup Auto

Après **toute modification** de l'installeur (`AishUIInstaller`) ou du packager
(`AishUIPackager`), recompiler en **Release** et déposer le binaire à jour dans
`H:\JEUX\World of Warcraft\AISH UI\Backup Auto` :

| Projet | Nom du fichier dans Backup Auto |
| --- | --- |
| `AishUIInstaller` | `INSTALLER AishUI.exe` |
| `AishUIPackager` | `AishUIPackager.exe` |

Systématique, sans rien demander. La copie précédente est renommée en `.bak` avant
l'écrasement (convention déjà en place dans le dossier).

Build : projets **.NET Framework 4.7.2** (WinForms), donc `dotnet build` ne convient pas.
MSBuild se trouve ici : `F:\Visual Studio\MSBuild\Current\Bin\MSBuild.exe`.
Le dépôt de l'installeur n'est **pas sous git** : sauvegarder les fichiers touchés avant
de les modifier.

## Lua

- `lupa` (Lua 5.1) est installé : **compiler chaque fichier modifié avant de livrer**.
- Vérifier aussi la limite des **200 locales** par chunk.
- **Chemins de police / textures** : dans la source Lua il faut un double antislash (`"Fonts\\2002.TTF"`). Un seul antislash fait lire `\200` comme un escape décimal (caractère 200) et produit un chemin mort. Relire la valeur écrite dans le fichier après coup, les outils d'édition peuvent avaler un niveau d'échappement.

## Fichiers générés — à régénérer moi-même, sans qu'Aishuu le demande

| Fichier | Script | Quand le relancer |
| --- | --- | --- |
| `Data/SearchIndex.lua` | `python generate_search_index.py` | **Après toute modif qui ajoute, retire ou renomme un texte d'option** dans `UI/SettingsPanel.lua` ou `Modules/Auras/UI/Menus/*.lua` (nouveau `L["..."]` dans une page, nouvelle page dans `CATEGORIES`). Sinon la recherche du GUI ne trouve pas la nouvelle option. Une nouvelle page dont le texte vient d'une table hors de sa fonction `Build.*` : l'ajouter à `EXTRA_BLOCKS` dans le script ; une page construite dans un fichier à part (ex. `UI/CDMLayoutPage.lua`) : l'ajouter à `EXTERNAL_PAGES`. |
| `Config/ProfileTemplate.lua` + `Modules/Auras/Core/ProfileTemplate.lua` | `python generate_profile_template.py` | **Apres chaque mise a jour du profil de reference "Empty Template" en jeu** (faire un `/reload` avant, pour que le profil soit ecrit dans les SavedVariables). Ces deux fichiers servent de configuration de depart a tout nouveau profil et au tout premier lancement. Ne jamais les editer a la main. |
| `Data/ModelPaths.lua` | `python generate_model_paths.py` | Seulement pour **mettre à jour la liste des modèles 3D** (nouveau patch WoW avec de nouveaux modèles). Télécharge la listfile communautaire. Inutile après une modif de code. |

Les deux scripts sont dans `.gitignore` : ils restent en local, seuls les `.lua` générés sont versionnés.
Compiler le fichier généré après coup (cf. section Lua).

## Version Forever (`_classic_beta_`) — un seul code, en miroir

Le dossier Retail est la **seule source**. La copie `_classic_beta_\Interface\AddOns\AishCore`
n'est jamais éditée à la main : après **toute modification** d'AishCore, la resynchroniser,
sans rien demander :

```
robocopy "H:\JEUX\World of Warcraft\_retail_\Interface\AddOns\AishCore" "H:\JEUX\World of Warcraft\_classic_beta_\Interface\AddOns\AishCore" /MIR /XD .git .github docs __pycache__ /XF *.py CLAUDE.md AishCore.toc.bak .gitignore
```

Différences de client dans le code, jamais par fichiers séparés (cf. `docs/PLAN_MULTI_CLIENT.md`) :
- `ns.IsModuleAvailable(id)` / `MODULE_RULES` (`Core.lua`) : module absent d'un client ;
  préférer la détection d'API au nom du client ;
- `ns.IsForever` : branche locale, commentée, quand aucune API ne tranche ;
- ne **jamais** réassigner une fonction globale de WoW hors d'un `if ns.IsForever` (taint en Retail).

## Polices

Tout **nouveau champ texte** ajouté doit utiliser la police **2002** par défaut.

Raison : garantir que les nouveaux profils ne dépendent pas d'une police absente chez l'utilisateur (2002 est embarquée dans le client WoW).

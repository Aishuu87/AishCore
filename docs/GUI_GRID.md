# Grille de colonnes du GUI

## Moteur (`NewLayout`, `UI/SettingsPanel.lua`)

- 4 colonnes sur la largeur du conteneur, 12 px d'écart (`GRID_N`, `GRID_GAP`).
- Les widgets standards portent `_gridKind` (posé dans `UI/SharedWidgets.lua`) : `slider`, `dropdown`, `color`, `align`, `check`.
- `ctx:Add(w)` : un slider, menu déroulant ou couleur seul sur sa ligne prend une colonne.
- `ctx:AddRow` / `AddRowCentered` : la rangée n'est alignée que si tous ses widgets ont un `_gridKind`.
  - slider / menu / couleur : 1 colonne, largeur forcée.
  - case à cocher / rangée d'alignement : le nombre de colonnes que demande leur largeur.
  - Plus de 4 colonnes au total : tout à 1 colonne ; toujours trop : placement libre (comme avant).
  - Les positions x sont gardées dans l'item du flux (`xs`) et rejouées au pli / dépli.
- Rangée avec un widget fait main (bouton, cadre perso) : placement libre, inchangé.
- `ctx.noGrid = true` : page qui gère sa propre grille (`UI/UnitBarsPage.lua`, colonnes par section via `Cols` / `Span`).

## Widgets

- Slider : gabarit d'un menu déroulant (libellé 18 px, ligne de 22 px : piste + bornes en petit + champ à droite). Ses éléments suivent `SetWidth`. Curseur `Media/UI/SliderThumb.tga` (16 px), couleur « Décorations B ».
- Menu déroulant : `OnSizeChanged` recale le bouton et la liste.
- Rangée d'alignement : libellé 18 + bouton 22 (même hauteur qu'un menu).
- Les Modes (`Modules/Auras/UI/SharedWidgets.lua`) délèguent leurs widgets au GUI principal : mêmes sliders. Leurs menus se placent à la main (2 colonnes `ox` / `ox + slW + gap`), hors moteur.

## Survol

`SW.HoverGlow(fontString, on)` : texte en couleur « Lueur » (`SW.GlowColor()`), couleur d'origine rendue à la sortie sauf si le propriétaire l'a changée entre-temps (sélection). Utilisé par les en-têtes repliables, les listes des Animations 3D, du CDM et des auras suivies.

## Cases maîtresses de section

`SetupSectionMasters` (appelé par `ctx:Finalize`) : si le premier widget d'une section est une case dont la clé DB (`_subKey`, posée par `BindCheckbox`) commence par `show` / `enable` ou finit par `Enabled` / `Enable`, la décocher grise et rend inerte le reste de la section (`SW.SetGrayReason(w, "master", on)`).
- `w._freeOfMaster = true` : widget indépendant de la case (ex. cooldown swipe sous « Afficher le cooldown »).
- `cb._noMaster = true` : case qui n'est pas maîtresse.
- `ctx.noGrid` / `ctx.noMasters` : page qui gère ses grisages elle-même (Barres de vie).
- `SW.SetGrayReason` cumule les raisons (`"master"`, `"spec"` pour « Utiliser la couleur de la spé » via `Build.LinkSpecColor`).

## Titre de groupe

`header._isGroupTitle = true` + `SW.MakeSectionTitle(header)` : second titre dans une page (ex. « Cercle de Ressource »), jamais replié avec la section qui le précède (`ctx:Add` coupe la section courante).

## Mode disposition (`/aishlayout`, `UI/LayoutEditor.lua`)

- Pages du moteur seulement (pas `noGrid`, page « propre » au sens de `Finalize`). Widgets deplacables : `_gridKind` slider / dropdown / color / check / align, dans des items `widget` ou `row` entierement standards.
- `LE.Apply` (debut de `Finalize`) : par section (cle `header._baseText`), si une disposition est enregistree (`AishaddonDB._guiLayout[catId][section] = { cols, rows }`) ou en mode disposition, les rangees deplacables sont remplacees par une grille de N colonnes (1 a 6) placee a la 1re rangee deplacable ; les espacements entre elles sont retires.
- Identifiant d'un widget : `dbKey.subKey` (Bind*), sinon `type:libelle`, doublons `#n`.
- `LE.After` (fin de `Finalize`) en mode disposition : sections depliees, calque inerte, glisser-deposer (case occupee = echange, quart haut d'une case occupee = insertion d'une rangee au-dessus, sous la derniere rangee = nouvelle rangee), +/- colonnes et R (reinitialiser) sur l'en-tete. Bandeau : Exporter / Reinitialiser la page / Quitter.
- But : Aishuu reorganise, exporte, et la disposition est reportee dans le code des pages (puis l'entree enregistree effacee).
- Cle de section = cle de locale du titre (recherche inverse dans `L`, toutes les cles candidates essayees), donc identique en FR / EN. Boutons d'action (`_leKind = "button"`) et separateurs (`__div:N`, ajoutes par « — » sur l'en-tete, clic droit pour retirer) sont deplacables.
- Priorite : disposition enregistree en jeu > `Data/GuiLayout.lua` (disposition reportee dans le code depuis l'export) > rangees de la page. Apres report d'un export dans `Data/GuiLayout.lua`, Aishuu fait « Reinitialiser la page » pour effacer sa copie enregistree.
- Widgets en pool par page : une disposition peut lister un widget d'une autre section (le premier qui le liste le garde) ; une section qui perd ou recoit un widget est recomposee. Sections ajoutees : `__sections = { { id = "__sec:N", after = cleSection } }` dans la page (enregistree ou `Data/GuiLayout.lua`), titre dans `_guiTitles`. Bouton S+ (ajouter), X (supprimer, ses widgets reviennent a leur section).
- Sidebar : `AishaddonDB._guiSidebar = { [indexGroupe] = { catIds } }`, applique au debut de `BuildSidebar` (groupes `single` intacts) ; glisser-deposer des pages en mode disposition (OnDragStart / OnDragStop des boutons). « Reinitialiser la sidebar » : effet apres /reload.
- `Data/GuiLayout.lua`, widgets sans cle DB : notes `type:$CLE` (cle de locale du libelle) et `@$CLE` (section d'origine, pages `noGrid`), traduits en jeu par `TranslateId` dans la langue du client : meme disposition en FR / EN. Report d'un export : script de conversion texte -> cle (cle choisie parmi les homonymes : celle presente dans le fichier de la page), `$` ajoute ; homonymes de sections corriges a la main (SEC_FIX).

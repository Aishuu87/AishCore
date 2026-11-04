# Barres de vie — réglages par barre

Refonte d'octobre 2026 (page GUI calquée sur les Barres dynamiques).

## Données

- **Communs** (racine de `unitBars`) : `enabled`, `locked`, `hideBlizz*`, `reversed`, `themedColors` / `barColor` /
  `bgColor`, `useTankHeight` / `tankHeight`, bouclier (`showAbsorb`, `absorbReversed`, `absorbColor`), soins
  (`showHealPrediction`, `healPredColor`), visibilité (`visRules`, `visRulesRole`, `roleVisibility`, `hoverTolerance`).
- **Par barre** (`unitBars.bars.<clé>`, défauts : `UnitBarDefaults` dans `Config/Defaults.lua`, lecture : `UnitBars.BV`).
  Position (`layout` free/mirror/parent, `mirrorOf` = barre de référence des deux liens, `relX/relY` en parenté), nom (`showName`, `showLevel`, police, `nameAnchor` 9 points,
  `nameJustify`, ombre), texte de vie (`hpShow`, police, `hpAnchor`, cadre `hpBoxW/H`, `hpBg`, `hpMode`), remplissage
  (`bgTexture`, `barTexture`, `fillDir` LTR/RTL/BTT/TTB), formes (`dotShape`, `dotCount` 1-5, `dotSide`, `dotSpacing`…).
- **Migration** : `EnsurePerBar` (UnitBars.lua) recopie une fois les anciens réglages communs dans chaque barre
  (drapeau `perBarSettings`), à la création et à chaque `ApplySettings` (changement de profil). Les anciennes clés
  globales restent dans les défauts comme source de cette migration.

## Rendu

- `LayoutBar(frame, preview)` fait toute la mise en page (géométrie, remplissage, formes, textes, couleurs) ; il sert
  aux barres en jeu et à l'aperçu du GUI (`UnitBars.CreatePreview` / `StylePreview`).
- Ancrage des textes (`OuterPoint`) : le point choisi est sur la barre ; l'élément se place à l'extérieur (au-dessus,
  en dessous, à côté ; dedans pour CENTER). La justification du nom fixe son bord horizontal.
- Liens : `BarPos` (symétrie = centres de barre en miroir autour de l'axe vertical de l'écran, bords bas alignés ;
  parenté = référence + relX/relY). `SetBarPos` fait l'inverse (une barre en symétrie déplace sa référence). Pendant
  un glisser, `dragDriver` enregistre la position à chaque image et replace les autres barres : les barres liées suivent.
- Positions = centre horizontal + bord bas de la **barre** (pas du cadre, qui grandit avec les points décoratifs) ;
  anciennes positions de cadre converties une fois (`EnsureBarAnchor`, drapeau `barAnchorPos`).
- Toutes les barres sont ancrées sur UIParent (le familier ne suit plus les animations de la barre du joueur).
- Page : grille de colonnes par section (`Row(n, ...)`, sliders `grid`, `CreateAlignRow(..., fill)`).

## Page (`UI/UnitBarsPage.lua`)

Titre + interrupteur du module, sélecteur + interrupteur de barre et aperçu sont épinglés (`ctx:PinnedTitle`,
`ns.SettingsPin`). Clic droit sur un élément de l'aperçu : `MainFrame:OpenSection`.

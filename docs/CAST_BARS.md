# Barres de cast

## Modules

- Joueur : `Modules/CastBar.lua` (`castBar`) — écoles de magie, couleur de spé, ticks, animations.
- Cible et focus : `Modules/TargetCastBar.lua`, une seule source. `NewUnitCastBar(UNIT, CFG_KEY, FRAME_NAME, CHANGED_EVENT)` crée une instance par unité :
  - `ns.Modules.TargetCastBar` → `targetCastBar`, `AishCoreTargetCastBar`, `PLAYER_TARGET_CHANGED` ;
  - `ns.Modules.FocusCastBar` → `focusCastBar`, `AishCoreFocusCastBar`, `PLAYER_FOCUS_CHANGED`.
- Réglages communs ajoutés : `fillDir` (`LTR` / `RTL`, `SetReverseFill` + étincelle au bord du remplissage), `sparkTexture` (`none` en plus, défaut `none` pour cible / focus), `sparkSize`, `sparkColor`, `nameColor` / `timerColor` (cible / focus). Joueur : `timerColor` facultatif (sinon couleur du nom).
- Textures d'étincelle partagées : `CastBar.SPARK_TEXTURES`, `CastBar.SPARK_KEYS`.

## Page du GUI (`UI/CastBarsPage.lua`, catégorie `castBars`)

- Remplace les pages `castBar` et `targetCastBar` (redirigées, `categoryRedirect` ; `SelectCategory` présélectionne la barre).
- Barre sélectionnée : `ns._castBarsSelected` (`player` / `target` / `focus`). Changer de barre reconstruit la page (`ns.InvalidateSettingsPage("castBars")`) : les couleurs diffèrent entre le joueur et cible / focus.
- Aperçu : rendu propre au GUI (barre fictive à 60 %), zones survolables → `OpenSection("castBars", …, true)` ; fond → Taille & Position.
- Grille propre (`ctx.noGrid`), grisages via `SW.SetGrayReason` (icône, contour, étincelle, couleurs de spé).
- Survol à l'écran : `ModuleHoverOverlay` (3 entrées, `onGo` → sélection), `ns.CastBarsPageRefresh`.

## Textes (nom du sort, temps d'incantation)

`TextPoints(anchor, justify)` (dupliquée dans `CastBar.lua`, `TargetCastBar.lua` et la page) : ancrage 9 points sur la barre (`nameAnchor` / `timerAnchor`) + alignement (`nameJustify` / `timerJustify`), le bord du texte choisi par l'alignement est posé sur l'ancre (haut / bas : texte à l'extérieur). Sans ancre enregistrée : déduite de l'ancien alignement (`TOPLEFT` / `TOP` / `TOPRIGHT`), donc rendu inchangé. Les textes sont à leur taille naturelle (`SetWidth(0)`), plus de boîte de la largeur de la barre.

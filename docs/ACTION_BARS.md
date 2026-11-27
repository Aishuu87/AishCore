# Barres d'action

Module `Modules/ActionBars.lua`, page `UI/ActionBarsPage.lua` (groupe Combat). Désactivé par défaut.

## Principe

On **ne crée pas de boutons**. Les boutons de Blizzard (`ActionButton1-12`, `MultiBarBottomLeftButton`,
`MultiBarBottomRightButton`, `MultiBarRightButton`, `MultiBarLeftButton`, `MultiBar5-7Button`, `PetActionButton`,
`StanceButton`) sont repris dans nos barres `SecureHandlerStateTemplate` (`AishCoreActionBar_<clé>`).

Pourquoi : créés par le jeu, ils restent non taintés. Leur code gère seul les recharges secrètes de Midnight, procs,
portée, charges, raccourcis (`ACTIONBUTTONn` etc. visent toujours ces boutons), Quick Keybind, glisser-déposer.
EllesmereUI crée ses propres boutons et doit tout réécrire (~20 000 lignes) pour contourner le taint.

Règles à tenir :
- écriture sur un bouton Blizzard : snippet sécurisé (`Execute`, `_onstate-*`) ou `SetAttributeNoHandler` ;
  jamais de champ Lua posé sur le bouton, jamais de méthode réassignée (seulement `hooksecurefunc`) ;
- habillage par bouton gardé dans la table locale `skins` (clé faible), pas sur le bouton ;
- placement / parent / taille / state drivers : hors combat, sinon `pendingLayout` → `PLAYER_REGEN_ENABLED`.

## Pages d'action

- Barres 2-8 : `actionpage` fixe (6, 5, 3, 4, 13, 14, 15) posé sur la barre et chaque bouton via `Execute`.
- Barre 1 : state driver `page` (`AB.PagingConditions` : override, véhicule / possession, forme temporaire,
  vol dynamique 11, bonusbar 1-4 → 7-10 (druide en Rôder : 8), barres 2-6, sinon 1). `_onstate-page` pose `actionpage` sur chaque bouton :
  leur `OnAttributeChanged` relit l'action, en sécurisé.
- **Pagination** (barres 1-8, désactivée par défaut) : `pageEnabled`, `pageShift` / `pageCtrl` / `pageAlt` = clé de la
  barre affichée tant que le modificateur est maintenu (réglages propres à la barre, `LOCAL_PROPS`, non copiés).
  `AB.ApplyPaging` (hors combat, appelé par `LayoutBar`) : barres fixes → driver `[mod:shift] p; … ; <page fixe>` ;
  barre 1 → `[mod:…]` insérés après véhicule / possession / vol dynamique, avant les formes. Barre 1 cible = page 1.
  Raccourcis automatiques (`AB.ApplyPagingBinds`, hors combat, au `LayoutAll` et à `UPDATE_BINDINGS`) : chaque touche
  sans modificateur d'un bouton reçoit `MOD-touche` en override binding (cadre `AishCoreActionBarsPagingBinds`) vers la
  même commande. Signature comparée avant d'écrire : `SetOverrideBinding` relance `UPDATE_BINDINGS`.

## Barres Blizzard

`MainActionBar` reste « affichée » (transitions véhicule / barre de remplacement de Blizzard), alpha 0 et inerte.
Les autres (`MultiBar*`, `MainMenuBar`, `StanceBar`, `PetActionBar`) sont reparentées à un cadre caché, **sans
toucher à leurs événements** (elles tiennent à jour familier et postures). Blizzard qui replace / reparente /
redimensionne un bouton (Edit Mode, nombre d'icônes) déclenche les hooks `SetPoint` / `SetParent` / `SetScale` →
`QueueLayout`. Boutons au-delà du nombre choisi : reparentés au cadre caché. Désactiver le module demande un /reload.

Première activation (`_captured`) : position, nombre d'icônes, lignes, espacement et taille relevés sur les barres
Blizzard (`Capture`).

## Visibilité et opacité

- Modes (`visMode`) : **Normal** (montrée en combat, grimoire ouvert, blessé = `HealthCircle.IsPlayerInjured`, vol
  dynamique, avec une cible, au survol ; sinon « opacité quand cachée »), **Discret** (survol seulement) : opacité
  seule, le driver reste « show ». **Avancé** : règles ci-dessous. Réglages existants passés en Avancé (`MigrateVisMode`).
  Section Avancé du GUI masquée hors de ce mode (`ctx:HideIf`, relu par `ctx:Relayout`).
- Règles cumulables (`RuleShow`, cases des Barres de vie + En combat, Si blessé) : Toujours, Au survol, cible alliée /
  attaquable, groupe, instance ; « Cacher » (monture, zone de repos) ignorés en combat. Hors combat, `FaderTick` repose
  le state driver `visibility` (`AB.VisCondition`) quand le résultat change : barre vraiment masquée. Entrée en combat
  (`PLAYER_REGEN_DISABLED`) : driver figé, montré si une règle peut changer en combat ; l'opacité suit ensuite.
  Toujours dans le driver : combat de mascottes, véhicule, vol dynamique, `[nopet]`. Postures sans forme : cachée.
  Anciens réglages (`vis`, `mouseover`, fondu commun) convertis une fois (`MigrateVis`).
- Opacité (`SetAlpha`, permis en combat) : `FaderTick` (20 Hz + lissage par image). « Opacité » si une règle est
  remplie ou au survol, sinon « Opacité hors survol » (barres « Au survol ») ou 0.
  Survol par rectangle + tolérance, délai de sortie, menu volant (`SpellFlyout`) ouvert = survolé.
  Glisser un sort : barres pleines et emplacements vides visibles (`RefreshSlots`, textures seulement).
- Barres déverrouillées ou page du GUI ouverte (`SetGuiForce`, interrupteur « Afficher les barres » de l'aperçu) :
  barres affichées, opacité pleine (désactivé par défaut). Déverrouillées : cadres de déplacement (`movers`).

## Groupes de barres

`db.groups[id] = { name, settings }`, `bars[key].group = id`. `AB.BV` lit les réglages du groupe, sauf `LOCAL_PROPS`
(position, disposition, activation) ; `AB.SetBV` écrit au même endroit (la page passe toujours par lui). Nouveau
groupe : réglages repris de la barre. Sortie ou suppression : la barre garde une copie des réglages du groupe.

## Barre des totems (Forever, chaman)

- `MultiCastActionBarFrame` est repris **entier** : `SetParent` vers notre barre sécurisée, rien d'autre sur lui (jamais `SetAlpha` / `Show` / `Hide`, cf. `Comfort.lua` : ses boutons seraient marqués et leurs recharges secrètes lèveraient des erreurs).
- Grille : invocation, emplacements actifs (`numActiveSlots`), rappel (`TotemList`, ceux que Blizzard affiche). Les `MultiCastActionButton1-12` (3 pages) restent ancrés à leur emplacement par Blizzard.
- Habillage : les emplacements prennent leur fond (`background`) comme icône ; les totems n'ont pas de contour propre (`noBord`), celui de l'emplacement en tient lieu. `overlayTex` (contour coloré par élément) masqué.
- Le menu de choix (`MultiCastFlyoutFrame`) ouvert compte comme un survol.
- `AB.OwnsTotemBar()` : les options de la barre de totems de Comfort s'effacent dès que les Barres d'action l'ont reprise.

## Habillage

`AB.StyleButton(b, key, w, h)` sert aux vrais boutons et à l'aperçu (`AB.CreatePreview` / `AB.StylePreview`, boutons
factices) : art Blizzard à alpha 0, masque d'icône Blizzard retiré, contour = texture pleine (ou forme) sous l'icône
insetée, formes par masque (cercle, losange, grunge, plume), survol / clic / actif repeints, textes reparentés sur un
cadre au-dessus du balayage. Hooks : `UpdateButtonArt` (Blizzard remet son art), `UpdateHotkeys` (raccourcis abrégés),
portée (`UpdateRangeIndicator` / `ActionButton_UpdateRangeIndicator`, valeurs secrètes ignorées).

Fond de barre : textures du Compartiment d'addons (`ExtraBars.StyleBackground` pour la découpe en 9, sinon image
étirée), dont les fonds grunge. « Varier les textures » (`texVariation`) : boutons = 4 rotations (`ROT`, SetRotation)
selon le rang du bouton (contour, masque, survol / clic / actif, emplacements). Pas de SetTexCoord à 8 valeurs sur le
masque de l'icône : il l'efface (cases vides). Fond : orientation (`ORIENT`, 8 valeurs) selon le rang de la barre (symétries `bgFlipH` / `bgFlipV` pour la découpe en 9). Le balayage de recharge garde la forme droite.

Procs : glow d'AishCore (`ns.Auras.ShowGlow`) à la place de l'alerte Blizzard et de la surbrillance de l'aide à la
rotation (`AssistedCombatManager.SetAssistedHighlightFrameShown`), animation d'entrée (`ns.Auras.PlayProcStart`).

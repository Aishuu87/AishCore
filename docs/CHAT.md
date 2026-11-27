# Tchat (`Modules/Chat.lua`, `UI/ChatPage.lua`)

Section GUI **Interface** (id interne `unitFrames` conservé : état replié de la page Modules, colonnes de l'arbre
de profils, installeur). Clé de profil : `chat` (défauts dans `Config/Defaults.lua`).

## Principe

Les ChatFrames de Blizzard restent le **moteur sécurisé** (événements, liens, whispers, secret values). On les
habille et on anime leurs lignes, on ne les remplace pas.

- Fond « Panneau » : `ExtraBars.StyleBackground` (texture `solid`) sur un cadre à nous, enfant du ChatFrame ; son
  alpha suit la ligne la plus visible hors survol (le panneau disparaît avec le texte).
- Couche des lignes (`UpdateLines`, chaque image) : cadre à nous sous le `FontStringContainer`. Pour chaque
  `cf.visibleLines[k]` : ombre en dégradé (style « Ombre derrière les lignes », à la Glass : bord gauche `bgEdge`,
  fondu sur la moitié droite) et heure dans une colonne à gauche du ChatFrame. Alpha recopié de la ligne (fondu natif).
  Heure : `cf.historyBuffer:GetEntryAtIndex(scrollOffset + k).timestamp` (base `GetTime`, index 1 = plus récent),
  jamais le message. La poussée joue la même translation sur cette couche.
- Onglets au survol : alpha tenu chaque image (Blizzard le repose), révélés par le survol de toute fenêtre du dock.
- Onglets (apparence) : police / taille des onglets de Blizzard (`TabFont`, posée par `StyleTab`), couleur du texte
  tenue chaque image (`ColorBlizzardTab` : actif, inactif, chuchotement, nouveaux messages = `tab.glow` affiché).
- Onglets verticaux (`tabLayout = "vertical"`) : barre à nous à gauche du dock, boutons `SecureActionButtonTemplate`
  (`type = "click"`, `clickbutton` = onglet de Blizzard). Onglets du dock cachés (alpha 0, souris coupée) mais
  cliqués par Blizzard lui-même : sélection, menu du clic droit, clignotement restent natifs, aucun `FCF_*`.
  Boutons protégés : créés / placés hors combat (`LayoutVBar`, revu chaque seconde et à PLAYER_REGEN_ENABLED).
  Boutons carrés : pictogramme (`TAB_ICONS` : Général, Combat, Groupe, Battle.net) ou 2 premières lettres du nom
  (`Initials`, chuchotement / onglet perso ; nom secret ou jeton |K : pictogramme). Clics : `RegisterForClicks("AnyUp",
  "AnyDown")` + `useOnKeyDown = false` (depuis 10.0, inscrit au seul AnyUp, un bouton sécurisé ne réagit pas).
  Forme « Texte » possible (`tabVStyle`). Visuel sur un cadre enfant **non protégé** (`b.vis`) : il glisse depuis le
  bord de l'écran en cascade au survol (`V_DUR` / `V_STAGGER`), même en combat ; le bouton sécurisé ne bouge pas.
  Alerte : `st.unread` (message reçu par une fenêtre non affichée, hors Général, via le hook AddMessage), `tab.alerting`
  (lecture) ou lueur de l'onglet → bordure pulsée + lueur et repère sur un cadre fixe (`glowF`), visibles barre cachée.
  Position : décalages `tabVX` / `tabVY`, strata au-dessus de celle du tchat. Chuchotement Battle.net : initiales du
  BattleTag (`BNet_GetBNetIDAccount(cf.chatTarget)` → `C_BattleNet.GetAccountInfoByID`), le nom réel étant protégé.
  Décalage X : dépend de `st.geo.ext` (colonne des heures), connu après le premier `LayoutRows` → `CheckVBar`
  replace la barre quand ce débord change (sinon mauvais décalage au `/reload`).
- Historique de saisie (flèches haut / bas, sans option) : navigation à nous (`HookScript` OnArrowPressed, la native ne
  répond pas), `SetAltArrowKeyMode(false)` reposé à chaque
  `OnEditFocusGained`. Lignes envoyées gardées dans `AishaddonDB.chatHistory` (50, compte). Liste d'autocomplétion
  ouverte : flèches laissées à elle. Capture par `HookScript` OnTextChanged / OnEnterPressed (aucun hook de méthode).
- Couleurs : chuchotement joueur (`tabColorWhisper`, rose) et Battle.net (`tabColorBN`, bleu) distincts, y compris pour
  la lueur d'alerte (`AlertColor`). Réponse envoyée (AddMessage avec l'id de `WHISPER_INFORM` / `BN_WHISPER_INFORM`,
  5e argument) : alerte de l'onglet arrêtée (`st.unread` effacé, `st.ackAlert` ignore l'alerte de Blizzard en cours).
- Onglet actif (forme icônes) : pas de changement de couleur ; contour + halo qui respire (`UI-ActionButton-Border`,
  mode ADD, ~4 s) dans la couleur « Onglet actif » (`ActiveColor`).
- Fond de la barre verticale : cadre à part sous les boutons, texture des Extra Barres (`tabVBarBg`, dont grunge),
  fondu avec l'arrivée des onglets ; opacité du fond des boutons `tabVBtnAlpha`.
- « Seulement au survol » par zone : onglets visibles à l'approche de leur zone (`NearFrame`, tolérance 40 px : barre
  verticale ou `GENERAL_CHAT_DOCK`), horodatage à l'approche de sa colonne (`NearLeftColumn`), délai `hoverHold`.
- Arrivée d'une ligne : en fin d'animation Alpha, WoW remet l'alpha d'avant l'animation (celui de l'ancienne ligne
  du bas, 0 si elle avait fondu) et Blizzard ne le repose pas → `OnFinished` remet 1.
- Animations : `hooksecurefunc(cf, "AddMessage")` → translation de `cf.FontStringContainer` (poussée douce) et
  translation + alpha de `cf.visibleLines[1]` (arrivée de la ligne), jouées **à l'envers** (`Play(true)`).
  Ne lit jamais le message.
- Fondu ligne par ligne : **fait par le module**. Fondu du widget coupé en permanence (`SetFading(false)`, posé une
  fois) : le lui rendre relançait son fondu (tout revenait à 100 % puis refondait). Alpha de chaque ligne =
  max(fondu recalculé depuis `entry.timestamp` avec `fadeAfter` / `fadeDuration`, survol en fondu 0,3 s / 0,9 s) ;
  ligne à 0 cachée (`Hide`, liens non cliquables), réaffichée par nous. Posé chaque image (`UpdateLines`) et juste
  après chaque `RefreshDisplay` (hook `HoldAlphas`, sinon une image en pleine opacité).
- Ombre par ligne : `SetAlpha` n'agit pas sur un dégradé → alpha intégré aux couleurs du dégradé (`SetGrad`).
- Masquage des boutons / barre de défilement : alpha 0 tenu par un surveillant (OnUpdate) + souris coupée.
- Messages épurés : `ChatFrameUtil.AddMessageEventFilter` (repli `ChatFrame_AddMessageEventFilter`), posés / retirés
  par `Chat.UpdateFilters` (module actif **et hors instance**, revu à chaque PLAYER_ENTERING_WORLD / ZONE_CHANGED_NEW_AREA). Gabarits
  globaux de Blizzard (`LOOT_ITEM_SELF`...) compilés en motifs (`Compile`, gère `%1$s`), donc indépendants de la langue.
- Zones : notices `YOU_CHANGED / YOU_JOINED / YOU_LEFT` des canaux de zone (`zoneChannelID ~= 0`) masquées,
  ligne « Ancienne > Nouvelle » écrite sur `ZONE_CHANGED_NEW_AREA` (et changement de zone par écran de chargement).

## Règles anti-taint (Midnight) — ne pas assouplir

Mesurées par d'autres addons de chat sur 12.x :

- **Jamais** de champ écrit sur un ChatFrame, un onglet ou un cadre de saisie (état par frame : table `S`).
- **Jamais** de fonction remplacée (`cf.AddMessage = ...`) ni de hook sur `FCF_*` : un champ comme `isLocked`
  écrit sous taint casse ensuite le menu des onglets et l'ouverture des fenêtres de whisper.
- **Jamais** d'appel `FCF_*` à chaud. Seule exception : `FCF_OpenNewWindow` pour l'onglet Groupe, suivi d'un
  `/reload` (Blizzard reconstruit alors la fenêtre en contexte sécurisé). D'où l'absence d'onglets créés / fermés /
  sélectionnés automatiquement : les whispers en onglet passent par la CVar native `whisperMode`.
- Pas de reparentage des widgets de Blizzard : alpha, texture vide (`SetTexture(nil)`), souris coupée.
- Méthodes du widget (SetFont, SetFading, ScrollToBottom, GetMessageInfo...) : élevées par Blizzard, sûres.
- Textes secrets : `ns.IsSecret` avant toute lecture ; un filtre laisse passer un message secret tel quel.
- **Filtres d'événements = taint** (constaté par Glass Forever, `Modules/TextProcessing.lua`) : le code de chat de
  Blizzard qui suit un filtre d'addon compte comme celui de l'addon, et garde des valeurs par type de message pour la
  session ; en instance (messages secrets) il échoue ensuite, erreur imputée à l'addon. Donc : jamais de filtre posé au
  chargement, jamais hors module actif, retirés en instance, et **aucun filtre sur les canaux des joueurs** (dire,
  groupe, raid, whispers, canaux) : d'où l'abandon des liens web cliquables.
- Recharger après `FCF_OpenNewWindow` : Glass utilise un `SecureActionButtonTemplate` (macro `/reload`) dont le
  PreClick crée l'onglet, même clic ; un popup `ReloadUI()` reste admis (Glass s'en sert aussi).
- Pas d'ouverture de `ChatConfigFrame` depuis l'addon (sa config serait contaminée).

## Retour arrière

Les textures vidées (fond, onglets, saisie) ne reviennent qu'au `/reload` : popup `AISHCORE_CHAT_RELOAD` à la
désactivation du module, des onglets épurés, du cadre de saisie, ou au passage au fond « Blizzard ».

## Pistes V2

Architecture de Glass Forever (MIT, `_forever_\Interface\AddOns\Glass`, lisible) : le ChatFrame reste le moteur
mais est masqué ; `SecureHook(cf, "AddMessage")` recopie chaque ligne dans ses propres FontStrings (le texte secret
s'affiche tel quel), toute réécriture (canaux courts, liens web, horodatage) se fait **à l'affichage** sur la copie,
sans filtre. Clics : `OnHyperlinkClick` → `pcall(SetItemRef, link, text, button, chatFrame)` (sans le ChatFrame pour un
clic droit). Whispers dans ses propres fenêtres (onglets whisper créés par addon = contaminés). Ce serait la voie pour
les noms de canaux raccourcis, les liens web et le nettoyage du butin en instance.


- Onglets virtuels (Groupe / whisper automatiques) : notre propre ScrollingMessageFrame nourri par le hook
  AddMessage, filtré par `chatTypeID` (5e argument) ; problème : les clics sur les noms de joueur depuis un cadre
  à nous sont insécurisés (whisper bloqué en instance).
- Noms de canaux courts : faits **à l'affichage** (`Shorten`, dans `UpdateLines`) : le texte de la FontString
  visible est réécrit par `SetText` après Blizzard, refait quand il le repose. Chaînes `CHAT_*_GET` lues (libellé
  entre crochets), jamais modifiées ; aucun filtre. Texte secret (instance) : noms longs.

## Aperçu du GUI

`Chat.CreatePreview` : faux tchat à nous (aucun cadre de Blizzard), messages en boucle (gabarits `CHAT_*_GET` +
`Chat.Examples`) avec les réglages du profil. Pleine opacité, sauf en mode « Tester le survol » : fondu des lignes
(délais plafonnés à 4 s + 2 s) et effets de survol, mêmes courbes que le vrai tchat (`HOVER_IN` / `HOVER_OUT`, `Smooth`).

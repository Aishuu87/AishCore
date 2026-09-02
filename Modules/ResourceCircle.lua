-- Modules/ResourceCircle.lua : Cercle de ressource primaire (dynamique par classe/spec)
local addonName, ns = ...
local L = ns.L

local ResourceCircle = {}
ns.Modules.ResourceCircle = ResourceCircle

-- Styles de décoration autour du texte de ressource secondaire ("- N -", "[ N ]"...).
-- key = valeur stockée via ns.GetSecResCfg("secResDecoStyle") (reglage par spec,
-- cf. Core.lua) ; left/right = texte littéral de chaque côté (jamais
-- concaténé au N lui-même, cf. SetSecResShown plus bas).
ns.SEC_RES_DECO_STYLES = {
  { key = "none",         left = "",     right = ""    },
  { key = "dash",         left = "-",    right = "-"   },
  { key = "bullet",       left = "•",    right = "•"   },
  { key = "slash",        left = "/",    right = "/"   },
  { key = "slash2",       left = "//",   right = "//"  },
  { key = "bslash",       left = "\\",   right = "\\"  },
  { key = "bslash2",      left = "\\\\", right = "\\\\" },
  { key = "pipe",         left = "|",    right = "|"   },
  { key = "ddash",        left = "--",   right = "--"  },
  { key = "underscore",   left = "_",    right = "_"   },
  { key = "dunderscore",  left = "__",   right = "__"  },
  { key = "equal",        left = "=",    right = "="   },
  { key = "tilde",        left = "~",    right = "~"   },
  { key = "hash",         left = "#",    right = "#"   },
  { key = "quote",        left = "\"",   right = "\""  },
  { key = "apostrophe",   left = "'",    right = "'"   },
  { key = "brackets",     left = "[",    right = "]"   },
  { key = "braces",       left = "{",    right = "}"   },
  { key = "parens",       left = "(",    right = ")"   },
}
local SEC_RES_DECO_BY_KEY = {}
for _, d in ipairs(ns.SEC_RES_DECO_STYLES) do SEC_RES_DECO_BY_KEY[d.key] = d end
local function GetSecResDeco(styleKey)
  return SEC_RES_DECO_BY_KEY[styleKey] or SEC_RES_DECO_BY_KEY.dash
end

-- Références locales
local bar = nil
local animationTicker = nil
local moveTicker = nil
local _rcAnimElems = {}   -- pré-alloué dans Create(), slots 11-12 mis à jour conditionnellement
local lastVisibilityState = nil
local previewMode = false
local lastResourceType = nil  -- dernier type de ressource detecte
local secDots = {}   -- secondary dot frames (runes, combo points, etc.)
local secDotCount = 0  -- nombre de secondary dots actifs
local secUpdateTicker = nil  -- ticker pour le fill progressif
local secDotType = nil  -- "RUNES", "COMBO", nil
local _secDotColorOverride = nil  -- {r, g, b} imposé par SpellEffects, ou nil

-- Animation slide des secondary dots (même esthétique que les orbes Skyriding)
local SEC_DOT_TEX     = "Interface\\AddOns\\AishCore\\Media\\Skyriding\\Circle_Smooth"
local SEC_SLIDE_SPEED = 9.0    -- vitesse de slide (units/s)
local SEC_SLIDE_SCALE = 1.55   -- facteur de départ (× plus loin du centre)
local secDotAnims     = {}     -- [i] = { progress, target }
local secAnimFrame    = nil    -- frame dédié à l'animation slide des sec dots

-- Affiche/masque le texte de ressource secondaire ET ses tirets décoratifs
-- ensemble ("- N -"). Les tirets sont des FontStrings séparées, statiques
-- (texte littéral "-", jamais touchées), ancrées aux bords GAUCHE/DROITE de
-- secResText — elles suivent donc automatiquement sa largeur, qui varie
-- selon le nombre affiché. On ne peut PAS construire "- N -" comme une seule
-- chaîne quand N vient d'une valeur secrète (concat/format interdits sur une
-- valeur secrète, cf. commentaire détaillé sur ApplyStacksToText plus bas) :
-- séparer visuellement le "N" (seul contenu de secResText) des tirets (texte
-- fixe, jamais secret) contourne le problème proprement.
local function SetSecResShown(shown)
  if not bar then return end
  if bar.secResText  then bar.secResText:SetShown(shown)  end
  if bar.secResDashL then bar.secResDashL:SetShown(shown) end
  if bar.secResDashR then bar.secResDashR:SetShown(shown) end
end

-- Applique le style de déco (secResDecoStyle) et l'espacement (secResDecoSpacing)
-- courants aux 2 FontStrings de déco -- valeurs par spec (ns.GetSecResCfg).
-- Appelé à la création ET depuis ApplySettings (changement live via le GUI).
-- specID optionnel : passé explicitement par RefreshSecResSpecGeometry (specID
-- fraîchement résolu, cf. DetectSecondaryResource) pour ne jamais dépendre du
-- global ns._specID au cas où il ne serait pas encore à jour à cet instant.
local function RefreshSecResDeco(specID)
  if not bar or not bar.secResDashL or not bar.secResDashR or not bar.secResText then return end
  local deco = GetSecResDeco(ns.GetSecResCfg("secResDecoStyle", specID))
  local spacing = ns.GetSecResCfg("secResDecoSpacing", specID) or 4
  bar.secResDashL:SetText(deco.left)
  bar.secResDashR:SetText(deco.right)
  bar.secResDashL:ClearAllPoints()
  bar.secResDashL:SetPoint("RIGHT", bar.secResText, "LEFT", -spacing, 0)
  bar.secResDashR:ClearAllPoints()
  bar.secResDashR:SetPoint("LEFT", bar.secResText, "RIGHT", spacing, 0)
end

---------------------------------------------------------------------------
-- [CONTROLE ANIMATIONS] Durées/délais/courbes d'apparition-disparition du
-- cercle central (entrée/sortie de combat). Point d'entrée unique : tout
-- réglage de timing se fait ici, pas besoin d'aller fouiller dans
-- AnimateVisibility / AnimateArcOverlay plus bas.
--   show = IN  (entrée en combat, le cercle apparaît)
--   hide = OUT (sortie de combat, le cercle disparaît)
--   duration : temps (s) de l'animation propre à l'élément (fade + scale)
--   delay    : temps (s) avant que l'élément commence à s'animer, compté
--              depuis l'entrée/sortie de combat
--   ease     : famille de courbe — "Linear" | "Sine" | "Quad" | "Cubic" |
--              "Quart" | "Quint" | "Expo" | "Circ" (cf. ns.Easing dans Core.lua)
--   easeType : "In" | "Out" | "InOut"
--   slideX/slideY : décalage (px) duquel l'élément part (show) / vers lequel
--              il va (hide), EN PLUS de sa position actuelle. 0 = pas de slide.
--   scaleX/scaleY : échelle de départ (show) / d'arrivée (hide), ex: 0.5 =
--              l'élément part/arrive à 50% de sa taille normale. Les deux
--              valeurs peuvent différer (déformation X/Y indépendante) —
--              WoW n'a pas d'échelle X/Y native, donc si scaleX ~= scaleY
--              l'élément est animé via sa largeur/hauteur (SetSize) plutôt
--              que via SetScale (uniforme, plus rapide, utilisé quand
--              scaleX == scaleY).
--   opacity  : alpha de DÉPART pour show, alpha de FIN pour hide — 0 =
--              totalement transparent, 1 = totalement opaque (défaut 0).
--              L'AUTRE extrémité vaut toujours 1 (pleinement visible) :
--              show va de `opacity` à 1, hide va de 1 à `opacity`. Mettre
--              opacity=1 sur un show supprime son fondu d'entrée (déjà
--              opaque dès la 1ère frame) ; pareil pour opacity=1 sur un
--              hide (pas de fondu de sortie, reste opaque jusqu'au Hide()
--              final).
-- arc/arcOverlay sont un cas particulier : ils ont `scale` (un seul nombre,
-- pas scaleX/scaleY). Leur taille est un calcul pie-crop précis lié au
-- rayon du cercle (ratio largeur:hauteur figé) — une déformation X/Y
-- indépendante casserait ce ratio et donc le crop, donc seul un facteur
-- UNIFORME est exposé ici. Ce facteur est appliqué via SetSize (pas
-- SetScale — cf. commentaire détaillé dans AnimateArcOverlay), donc "arc"
-- grossit/rétrécit de façon garantie depuis SON PROPRE ancrage (BOTTOM, cf.
-- Create()/ApplySettings) : voulu, à l'entrée en combat le cercle doit
-- avoir l'air de pousser depuis le bas, pas depuis son centre visuel.
-- arcOverlay applique son scale/slide à la texture bar.overlay (ancrée
-- CENTER) plutôt qu'à sa frame bar.overlayFrame (ancrée via SetAllPoints,
-- sans pivot exploitable).
-- Ce sont par ailleurs deux éléments 100% indépendants l'un de l'autre
-- (chacun son duration/delay/ease/easeType/slide/scale) : par défaut
-- l'overlay reste juste réglé pour finir en dernier (masquer le trou) à
-- l'apparition et disparaître en dernier à la sortie, mais rien ne les
-- synchronise plus structurellement — change l'un sans toucher l'autre si
-- besoin (au risque de laisser le trou central transparaître pendant la
-- transition si mal réglé).
---------------------------------------------------------------------------
local CIRCLE_ANIM = {
  background = { -- bgGlow
    show = { duration = 0.3,  delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, scaleX = 2.5, scaleY = 2.5, opacity = 1 },
    hide = { duration = 0.3,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 0, scaleX = 0.5, scaleY = 0, opacity = 0 },
  },
  backgroundSlow = { -- bgLarge (traîne légèrement derrière "background", cf. delay)
    show = { duration = 0.2,  delay = 0.050, ease = "Quint", easeType = "Out", slideX = 0, slideY = -20, scaleX = 0.5, scaleY = 0.5, opacity = 1 },
    hide = { duration = 0.2,  delay = 0.050, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, scaleX = 0.5, scaleY = 0.5, opacity = 0 },
  },
  arc = { -- arc radial/vertical (vertical ou radial selon radialFillTest)
    show = { duration = 0.8, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = -20, opacity = 1, scale = 0.5 },
    hide = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  arcOverlay = { -- masque du centre de l'arc — 100% indépendant de "arc" (délai/durée/ease/scale)
    show = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, opacity = 1, scale = 1 },
    hide = { duration = 0.4, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  textBackdrop = { -- petit cache sombre sous le texte (même transformations que arcOverlay)
    show = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, scaleX = 1,   scaleY = 1,   opacity = 1 },
    hide = { duration = 0.4, delay = 0.000, ease = "Quint", easeType = "In",  slideX = 0, slideY = -20, scaleX = 0.5, scaleY = 0.5, opacity = 0 },
  },
  text = {
    show = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "Out", slideX = 0, slideY = -10, scaleX = 1, scaleY = 1, opacity = 1 },
    hide = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 1, scaleY = 1, opacity = 0 },
  },
  secResText = { -- texte de ressource secondaire (Bone Shield, Soul Fragments...)
    show = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "Out", slideX = 0, slideY = -10, scaleX = 1, scaleY = 1, opacity = 1 },
    -- slideY négatif : contrairement au groupe "text", ce texte sort par le BAS
    -- (home.y + slideY < home.y) plutôt que par le haut à la disparition.
    hide = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, scaleX = 1, scaleY = 1, opacity = 0 },
  },
  dotCenter = { -- dot3
    show = { duration = 0.5,  delay = 0.00, ease = "Quint", easeType = "Out", slideX = 0, slideY = 15, scaleX = 0.8, scaleY = 3.2, opacity = 1 },
    hide = { duration = 0.5,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 0.6, scaleY = 2.1, opacity = 0 },
  },
  dotMid = { -- dot2 / dot4
    show = { duration = 1,  delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 15, scaleX = 0.8, scaleY = 3.8, opacity = 1 },
    hide = { duration = 0.4,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 0.6, scaleY = 2.1, opacity = 0 },
  },
  dotOuter = { -- dot1 / dot5
    show = { duration = 1.5,  delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 15, scaleX = 0.8, scaleY = 3.8, opacity = 1 },
    hide = { duration = 0.3,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 0.6, scaleY = 2.1, opacity = 0 },
  },
}

-- Mappe chaque slot de _rcAnimElems à son groupe CIRCLE_ANIM (nil = pas de
-- groupe, ex: slots 4/5 arc/overlay animés séparément par AnimateArcOverlay).
local _RC_ANIM_GROUP = {
  [1] = "background", [2] = "backgroundSlow", [3] = "text",
  [6] = "dotCenter", [7] = "dotMid", [8] = "dotMid",
  [9] = "dotOuter", [10] = "dotOuter",
  -- 11/12 (staggerArc/staggerOverlayFrame) : plus de groupe ici, cf. slots
  -- 4/5 -- animés par AnimateArcOverlay avec EXACTEMENT la même spec
  -- (CIRCLE_ANIM.arc/arcOverlay) que l'arc principal.
  [13] = "textBackdrop",
  [14] = "secResText",
}

-- Géométrie de repos ("home") des éléments animés, mémorisée au moment où
-- ON LA FIXE nous-mêmes (Create()/ApplySettings) via RecordHome(), plutôt
-- que relue plus tard depuis la frame via GetPoint/GetSize. Indispensable
-- pour un slide/scale fiable EN COMBAT : WoW peut renvoyer des "secret
-- values" sur GetPoint/GetSize selon le contexte, qui bloquent alors TOUTE
-- opération Lua dessus — y compris le détaintage (tonumber(tostring())
-- ne fonctionne que hors combat, cf. PriorityBar.lua:SecretToNumber). En
-- revanche les valeurs qu'on calcule et fixe nous-mêmes (à partir de
-- cfg.size etc., jamais des données de combat) ne sont jamais secrètes,
-- donc les mémoriser au lieu de les relire élimine le problème à la racine.
local _elemHome = {}
local function RecordHome(element, point, relTo, relPoint, x, y, w, h)
  _elemHome[element] = { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y, w = w, h = h }
end

-- Ressource secondaire (texte sous le cercle : Bone Shield, Soul Fragments, etc.)
local secResDef        = nil   -- définition active (ou nil)
local secResUpdateTicker = nil -- ticker de mise à jour
-- spellID(s) actuellement abonnés au canal clone-stack (CDMHooks.lua,
-- ns.SubscribeCDMAuraStack) pour bar.secResText -- mémorisé pour pouvoir se
-- désabonner proprement au changement de spec (cf. _secResStackSubIDs plus bas).
local _secResStackSubIDs = nil
local FONT_BOLD_ITALIC = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-BoldItalic.ttf"

-- Essence Burst (Evoker Preservation) : proc détecté via spell overlay
-- Sorts qui s'allument quand Essence Burst est actif
local ESSENCE_BURST_SPELLS = { [364343]=true, [355913]=true, [356995]=true }  -- Echo, Emerald Blossom, Disintegrate
local essenceBurstGlowing  = {}   -- [spellID] = true si overlay actif en ce moment
local essenceBurstActive   = false -- dérivé de essenceBurstGlowing

-- Fire Mage : Heating Up (1) et Hot Streak (2)
-- Deux événements distincts :
--   SPELL_ACTIVATION_OVERLAY_SHOW/HIDE  -> overlay écran = Heating Up actif
--   SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE sur Pyroblast/Flamestrike -> Hot Streak actif
local FIRE_PYRO_SPELLS  = { [11366]=true, [2120]=true }  -- Pyroblast, Flamestrike
local fireOverlayActive = false  -- overlay écran présent
local firePyroGlowing   = false  -- glow Pyroblast/Flamestrike actif
local fireProcLevel     = 0      -- 0/1/2 dérivé

-- Arc de stagger (Moine Brasseur specID 268)
local staggerActive         = false

-- Warlock Demonologie : Demonic Core (buff 264173, stacks 0-2)
-- Fallback : glow sur Incantation de la Foudre Démoniaque / Demonbolt (264178)
local demonicCoreStacks        = 0
local demonicCoreOverlayActive = false
local DEMONBOLT_SPELL_ID       = 264178

-- Enhancement Shaman Maelstrom Weapon pseudo-spells (specID 263)
-- 0=aucun, 1=≥5 stacks, 2=≥8 stacks, 3=10 stacks
local mwStackLevel = 0
local staggerUpdateTicker   = nil
local STAGGER_ARC_RATIO     = 0.72   -- taille relative à arcPx (s'inscrit dans le trou de l'overlay)
local STAGGER_OVERLAY_RATIO = 0.76   -- overlay interne du cercle de stagger
local STAGGER_LIGHT    = { 0.52, 1.00, 0.52 }  -- < 30%  : vert
local STAGGER_MODERATE = { 1.00, 0.69, 0.00 }  -- 30-60% : orange
local STAGGER_HEAVY    = { 1.00, 0.15, 0.15 }  -- >= 60% : rouge

-- Arc de durée dans le cercle central : piloté par CenterArc.lua (module autonome)
local DURATION_ARC_RATIO     = 0.72
local DURATION_ARC_OVL_RATIO = 0.76

-- Crop constant for circle_piecrop.tga (texture pre-croppee, bas transparent supprime)
local ARC_CROP_H = 0.88

-- [EXPERIMENTAL] Remplissage radial : jauge en arc de 280° (trou de 80° en
-- bas, centré sur 6h), 1 quartier (RadialWedge.tga) par %.
local RADIAL_FRAG_COUNT = 100
local RADIAL_ARC_SPAN_DEG  = 280   -- 360 - 80 (trou en bas)
local RADIAL_ARC_START_DEG = 220   -- bearing (0=midi, horaire) où commence le 0%

-- [EXPERIMENTAL] Recalcule taille/position/rotation des 100 quartiers
-- radiaux à partir de la config courante (cfg.size, arcSizeRatio,
-- overlayRatio). Appelée à la création ET depuis ApplySettings (sinon les
-- quartiers restent figés à leur géométrie de création quand on modifie les
-- sliders du GUI, ce qui a été observé en jeu : l'overlay grandit mais les
-- quartiers ne suivent pas, jusqu'à parfois être entièrement recouverts).
local function LayoutRadialFrags()
  if not bar or not bar.radialFrags then return end
  local cfg = ns.GetCfg("resourceCircle")
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  -- Les quartiers sont TOUJOURS dessinés en taille max (quasi du centre
  -- jusqu'au bord), exactement comme l'arc vertical à 100% de valeur.
  -- C'est `bar.overlay` (cercle noir, cfg.overlayRatio, déjà réactif aux
  -- sliders via ApplySettings) qui masque le centre par-dessus — pas une
  -- variation de la taille des quartiers eux-mêmes. Ça évite aussi que les
  -- quartiers rétrécissent (et deviennent plus "hachurés"/pixelisés) quand
  -- l'anneau visible se réduit : ils restent toujours au rendu le plus net.
  local fragInnerR = (arcPx / 2) * 0.05  -- quasi le centre (jamais 0 pile, évite une taille nulle)
  local fragOuterR = (arcPx / 2) * 0.98
  local fragMidR   = (fragInnerR + fragOuterR) / 2
  -- Surdimensionnement (x1.2) pour un chevauchement généreux entre quartiers
  -- voisins : chaque bord anti-aliasé est ainsi recouvert par la couleur
  -- pleine du voisin plutôt que de laisser transparaître un micro-espace ou
  -- un liseré de fond.
  local fragSize = (fragOuterR - fragInnerR) * 1.2
  for k = 0, RADIAL_FRAG_COUNT - 1 do
    local frag = bar.radialFrags[k + 1]
    if frag then
      frag:SetSize(fragSize, fragSize)
      local angleDeg = RADIAL_ARC_START_DEG + (k * RADIAL_ARC_SPAN_DEG / RADIAL_FRAG_COUNT)
      local angle = angleDeg * math.pi / 180
      local fx = fragMidR * math.sin(angle)
      local fy = fragMidR * math.cos(angle)
      frag:ClearAllPoints()
      frag:SetPoint("CENTER", bar, "CENTER", fx, fy)
      -- Pivote la texture (pas le frame) pour pointer radialement à l'angle
      -- de départ de ce quartier. Signe négatif car SetRotation tourne en
      -- anti-horaire pour un angle positif, alors que notre convention de
      -- bearing est horaire.
      local tex = frag:GetStatusBarTexture()
      if tex then tex:SetRotation(-angle) end
    end
  end
end

-- Verifie si les elements doivent etre visibles (en combat uniquement)
function ResourceCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideResourceCircle ~= false then return false end
  local cfg = ns.GetCfg("resourceCircle")
  if cfg.enabled == false then return false end
  -- "Toujours actif en instance" : ignore les transitions combat tant qu'on
  -- est en donjon/raid (ns.inInstance, cf. Core.lua) -- ne s'applique jamais
  -- hors instance, ou le mode de visibilite normal reprend la main.
  if cfg.alwaysInInstance and ns.inInstance then return true end
  local vMode = cfg.visibilityMode or "combat"
  if vMode == "always" then return true end
  if vMode == "target" then return UnitExists("target") end
  -- "combat"
  if UnitAffectingCombat("player") then return true end
  return false
end

-- Applique les settings en live (taille, police, etc.)
function ResourceCircle.ApplySettings()
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")

  -- Gerer l'activation/desactivation en live
  if cfg.enabled == false then
    if animationTicker then animationTicker:Cancel(); animationTicker = nil end
    if moveTicker then moveTicker:Cancel(); moveTicker = nil end
    bar:Hide()
    lastVisibilityState = nil
    return
  end
  -- Forcer un re-check de visibilite (le module vient peut-etre d'etre reactive)
  lastVisibilityState = nil

  local size   = cfg.size
  local bgSize = size * 1.1
  bar:SetSize(size, size)
  bar.bgLarge:SetSize(bgSize, bgSize)
  bar.bgLarge:ClearAllPoints()
  bar.bgLarge:SetPoint("BOTTOM", bar, "CENTER", 0, -bgSize / 2)
  RecordHome(bar.bgLarge, "BOTTOM", bar, "CENTER", 0, -bgSize / 2, bgSize, bgSize)
  -- Repositionner la frame (la position peut avoir changé via un autre profil)
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
  -- Glow
  if bar.bgGlow then
    local glowEnabled = cfg.glowEnabled ~= false
    local glowPixelSize = math.floor(bgSize * (cfg.glowSize or 1.0) + 0.5)
    bar.bgGlow:SetSize(glowPixelSize, glowPixelSize)
    bar.bgGlow:ClearAllPoints()
    bar.bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.bgGlow:SetAlpha(cfg.glowOpacity or 0.85)
    if glowEnabled then bar.bgGlow:Show() else bar.bgGlow:Hide() end
    RecordHome(bar.bgGlow, "CENTER", bar, "CENTER", 0, 0, glowPixelSize, glowPixelSize)
  end
  local arcPx     = size * (cfg.arcSizeRatio or 1.0)
  local overlayPx = arcPx * (cfg.overlayRatio or 0.75)
  bar.arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  bar.arc:ClearAllPoints()
  bar.arc:SetPoint("BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H)
  RecordHome(bar.arc, "BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H, arcPx, arcPx * ARC_CROP_H)
  -- radialFillFrame (mode radial [EXPERIMENTAL]) est ancré via SetAllPoints(bar),
  -- pas d'ancrage exploitable pour slide/scale — non couvert ici (comme avant).
  if bar.overlay then
    if overlayPx >= 2 then
      bar.overlay:SetSize(overlayPx, overlayPx)
      bar.overlay:Show()
      if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    else
      bar.overlay:Hide()
    end
    bar.overlay:ClearAllPoints()
    bar.overlay:SetPoint("BOTTOM", bar, "CENTER", 0, -overlayPx / 2)
    RecordHome(bar.overlay, "BOTTOM", bar, "CENTER", 0, -overlayPx / 2, overlayPx, overlayPx)
  end
  -- [EXPERIMENTAL] Recaler les 100 quartiers radiaux (taille/position
  -- dépendent de arcPx et overlayRatio, comme l'overlay ci-dessus).
  LayoutRadialFrags()
  -- Ré-appliquer la valeur de démo (72%) après le recalage : redimensionner
  -- une StatusBar ne réapplique pas automatiquement son crop, et
  -- ResourceCircle.Update() s'auto-désactive pendant l'aperçu (previewMode)
  -- pour ne pas écraser la valeur forcée par SetPreview — sans ce rappel,
  -- les quartiers restent "vides" dès qu'un slider change dans le GUI.
  if previewMode and bar.radialFrags then
    for _, frag in ipairs(bar.radialFrags) do
      pcall(ns.SmoothSetValue, frag, 72)
    end
  end
  -- Redimensionner l'arc de stagger quand les settings changent
  if bar.staggerArc then
    local stagArcPx = arcPx * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
    bar.staggerArc:SetSize(stagArcPx, stagArcPx * ARC_CROP_H)
    bar.staggerArc:ClearAllPoints()
    bar.staggerArc:SetPoint("TOP", bar, "CENTER", 0, stagArcPx / 2)
    RecordHome(bar.staggerArc, "TOP", bar, "CENTER", 0, stagArcPx / 2, stagArcPx, stagArcPx * ARC_CROP_H)
    if bar.staggerOverlay then
      local stagOvPx = stagArcPx * (cfg.staggerOverlayRatio or STAGGER_OVERLAY_RATIO)
      if stagOvPx >= 2 then bar.staggerOverlay:SetSize(stagOvPx, stagOvPx) end
    end
  end
  bar.text:SetFont(cfg.font or ns.Media.font, cfg.fontSize)
  -- Geometrie dependante de la spec (arc de duree + texte de ressource
  -- secondaire) : extraite dans une fonction dediee (cf. plus bas) pour
  -- pouvoir etre rappelee depuis DetectSecondaryResource SANS toucher au
  -- reste d'ApplySettings (position/taille du cercle, glow, dots, stagger,
  -- lastVisibilityState...).
  -- specID résolu FRAÎCHEMENT ici (comme DetectSecondaryResource), plutôt que
  -- de laisser RefreshSecResSpecGeometry retomber sur le global ns._specID :
  -- au login, ApplySettings() est appelé juste après Create() dans la même
  -- passe PLAYER_ENTERING_WORLD, AVANT que CachePlayerSpec() n'ait rempli
  -- ns._specID (elle tourne plus tard dans la même fonction, cf. AishCore.lua).
  -- Sans ce paramètre explicite, ce second appel relisait les réglages sous la
  -- mauvaise clé (générique, pas "secRes_<specID>_...") et écrasait la bonne
  -- géométrie que Create()->DetectSecondaryResource venait d'appliquer -- d'où
  -- le bug CONFIRMÉ EN JEU : la personnalisation par spec restait invisible au
  -- login/reload jusqu'à ce qu'on retouche un slider du GUI (qui ré-appelle
  -- ApplySettings() une fois ns._specID enfin résolu).
  local specID = nil
  if GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local ok, sid = pcall(GetSpecializationInfo, idx)
      if ok and sid and sid > 0 then specID = sid end
    end
  end
  ResourceCircle.RefreshSecResSpecGeometry(specID)
  -- Redimensionner les dots proportionnellement
  local baseSize = ns.Defaults.resourceCircle.size
  local scale = size / baseSize
  -- dotSizes et dotPositions viennent toujours des defaults (pas modifiables via GUI)
  local dotSizes = ns.Defaults.resourceCircle.dotSizes
  local dotPositions = ns.Defaults.resourceCircle.dotPositions
  for i = 1, 5 do
    local dot = bar["dot" .. i]
    if dot then
      dot:SetSize(dotSizes[i] * scale, dotSizes[i] * scale)
      dot:ClearAllPoints()
      dot:SetPoint("BOTTOM", bar, "BOTTOM", dotPositions[i][1] * scale, dotPositions[i][2] * scale)
      RecordHome(dot, "BOTTOM", bar, "BOTTOM", dotPositions[i][1] * scale, dotPositions[i][2] * scale,
        dotSizes[i] * scale, dotSizes[i] * scale)
    end
  end
  -- Appliquer les couleurs de la ressource active
  ResourceCircle.UpdateResourceColors()
  -- Re-detecter les secondary dots (option allSpecs, spec change)
  ResourceCircle.DetectSecondaryDots()
  -- Repositionner les secondary dots (runes, combo points)
  ResourceCircle.LayoutSecDots()

  -- [EXPERIMENTAL] Synchroniser l'affichage vertical/radial avec
  -- cfg.radialFillTest (ex : la case à cocher du GUI ne fait que changer la
  -- config — c'est cet appel qui bascule réellement l'élément visible).
  ResourceCircle.ApplyRadialMode()

  -- Forcer la visibilite apres changement de settings
  if previewMode then
    ResourceCircle.SetPreview(true)
  else
    ResourceCircle.UpdateVisibility()
  end
end

-- Met a jour les couleurs (arcs, texte, dots) selon la ressource primaire du joueur
function ResourceCircle.UpdateResourceColors()
  if not bar then return end
  local powerType = ns.GetPlayerResource()
  local colors    = ns.GetResourceColors(powerType)
  local CLR       = ns.Modules.Colors

  -- Colors.Get() prend priorité sur les couleurs de ressource (thème par spé)
  local arcC  = (CLR and CLR.Get("powercircle")) or colors.bar
  local textC = (CLR and CLR.Get("powertext"))   or colors.text
  -- Outer dots (indices 1,2,4,5) → powerdotsa ; central (3) → powerdotsb
  local dotsA = (CLR and CLR.Get("powerdotsa"))  or colors.bar
  local dotsB = (CLR and CLR.Get("powerdotsb"))  or colors.bar
  -- dot 3 = gros central → powerdotsA ; dots 1,2,4,5 = petits → powerdotsB
  local DOT_C = { dotsB, dotsB, dotsA, dotsB, dotsB }

  -- Glow color (couleur de spec)
  if bar.bgGlow then
    local glowC = (CLR and CLR.Get("glow")) or {1, 1, 1, 1}
    bar.bgGlow:SetVertexColor(glowC[1], glowC[2], glowC[3], 1)
  end
  -- Arc
  if bar.arc then bar.arc:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1) end
  -- [EXPERIMENTAL] Fragments radiaux : même couleur que l'arc vertical,
  -- synchronisée pour que le toggle /rcradial ne montre jamais une couleur périmée.
  if bar.radialFrags then
    for _, frag in ipairs(bar.radialFrags) do
      frag:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1)
    end
  end
  -- Texte
  bar.text:SetTextColor(textC[1], textC[2], textC[3], textC[4] or 1)
  -- Dots
  for i = 1, 5 do
    local dot = bar["dot" .. i]
    if dot then
      local c = DOT_C[i]
      dot:SetVertexColor(c[1], c[2], c[3], 1)
    end
  end
  lastResourceType = powerType
end

-- Appele quand le type de ressource change (spec, forme druide)
-- Retourne true si la ressource a effectivement change
function ResourceCircle.OnResourceChanged()
  if not bar then return false end
  local powerType = ns.GetPlayerResource()
  if powerType == lastResourceType then return false end
  ResourceCircle.UpdateResourceColors()
  ResourceCircle.Update()
  -- Re-detecter les secondary dots (druide forme chat <-> caster)
  ResourceCircle.DetectSecondaryDots()
  -- Re-detecter la ressource secondaire (changement de spec/forme)
  ResourceCircle.DetectSecondaryResource()
  -- Re-detecter l'arc de stagger (changement de spec)
  ResourceCircle.DetectStagger()
  -- Utilise le cache (mis a jour au login + PLAYER_SPECIALIZATION_CHANGED)
  local playerClass2 = ns._playerClass or ""
  local specID2      = ns._specID
  local SE_rc = ns.Modules and ns.Modules.SpellEffects
  -- Reset état Fire Mage si on n'est plus Mage Feu
  if not (playerClass2 == "MAGE" and specID2 == 63) then
    fireOverlayActive = false
    firePyroGlowing   = false
    if fireProcLevel ~= 0 then
      fireProcLevel = 0
      if SE_rc and SE_rc.StopSustained then
        SE_rc.StopSustained(9000001)
        SE_rc.StopSustained(9000002)
      end
    end
  end
  -- Reset Essence Burst si on n'est plus Evoker Preservation
  if not (playerClass2 == "EVOKER" and specID2 == 1468) then
    if essenceBurstActive then
      essenceBurstActive = false
      for k in pairs(essenceBurstGlowing) do essenceBurstGlowing[k] = nil end
      if SE_rc and SE_rc.StopSustained then SE_rc.StopSustained(9000003) end
    end
  end
  -- Reset Maelstrom Weapon si on n'est plus Shaman Enhancement
  if not (playerClass2 == "SHAMAN" and specID2 == 263) then
    if mwStackLevel ~= 0 then
      mwStackLevel = 0
      if SE_rc and SE_rc.StopSustained then
        SE_rc.StopSustained(9000004)
        SE_rc.StopSustained(9000005)
        SE_rc.StopSustained(9000006)
      end
    end
  end
  -- Reset Demonic Core si on n'est plus Warlock Démonologie
  if not (playerClass2 == "WARLOCK" and specID2 == 265) then
    demonicCoreStacks        = 0
    demonicCoreOverlayActive = false
  end
  return true
end

-- Création de la StatusBar circulaire avec 2 arcs
function ResourceCircle.Create(parent)
  if bar then return bar end
  local cfg = ns.GetCfg("resourceCircle")

  bar = CreateFrame("Frame", "AishCoreRingBar", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetPoint("CENTER", parent, "CENTER", cfg.x, cfg.y)

  -- Glow de fond (DERRIERE bgLarge, sublevel -1)
  local bgGlow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  ns.SetSmoothTexture(bgGlow, "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga")
  bgGlow:SetBlendMode("ADD")
  bgGlow:SetDesaturated(true)
  local glowPixelSize = math.floor((cfg.size * 1.1) * (cfg.glowSize or 1.0) + 0.5)
  bgGlow:SetSize(glowPixelSize, glowPixelSize)
  bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgGlow:SetAlpha(cfg.glowOpacity or 0.85)
  if cfg.glowEnabled == false then bgGlow:Hide() end
  bar.bgGlow = bgGlow
  RecordHome(bgGlow, "CENTER", bar, "CENTER", 0, 0, glowPixelSize, glowPixelSize)

  -- Grand fond opaque
  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  ns.SetSmoothTexture(bgLarge, ns.Media.circle)
  bgLarge:SetSize(cfg.bgSize, cfg.bgSize)
  bgLarge:SetPoint("BOTTOM", bar, "CENTER", 0, -cfg.bgSize / 2)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge
  RecordHome(bgLarge, "BOTTOM", bar, "CENTER", 0, -cfg.bgSize / 2, cfg.bgSize, cfg.bgSize)

  -- Arc (remplissage bas -> haut, texture circulaire pre-croppee)
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  local arc = CreateFrame("StatusBar", "AishCoreRingBarArc", bar)
  arc:SetFrameLevel(bar:GetFrameLevel() + 1)
  arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  arc:SetPoint("BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H)
  ns.SetSmoothStatusBarTexture(arc, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  arc:SetOrientation("VERTICAL")
  arc:SetMinMaxValues(0, 100)
  arc:SetValue(0)
  arc:Show()
  bar.arc = arc
  RecordHome(arc, "BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H, arcPx, arcPx * ARC_CROP_H)

  -- Overlay sombre : masque le centre pour simuler un arc en anneau
  local overlayPx = arcPx * (cfg.overlayRatio or 0.75)
  local overlayFrame = CreateFrame("Frame", nil, bar)
  -- +101 (et non +1) : réserve un niveau distinct à chacun des 100 quartiers
  -- radiaux (cf. plus bas) sans qu'aucun ne dépasse l'overlay, qui doit
  -- toujours rester au-dessus pour masquer le trou central des deux modes.
  overlayFrame:SetFrameLevel(arc:GetFrameLevel() + 101)
  overlayFrame:SetAllPoints(bar)
  local overlay = overlayFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(overlay, ns.Media.circle)
  if overlayPx >= 2 then overlay:SetSize(overlayPx, overlayPx) else overlay:Hide() end
  overlay:SetPoint("BOTTOM", bar, "CENTER", 0, -overlayPx / 2)
  overlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.overlay = overlay
  bar.overlayFrame = overlayFrame
  RecordHome(overlay, "BOTTOM", bar, "CENTER", 0, -overlayPx / 2, overlayPx, overlayPx)

  ---------------------------------------------------------------------------
  -- [EXPERIMENTAL] Remplissage radial (comme avant Midnight) : jauge en arc
  -- de 280° (trou de 80° en bas, centré sur 6h), remplie par 100 "quartiers"
  -- (1 par %), chacun une StatusBar indépendante avec sa propre plage MinMax
  -- (ex : quartier #5 = plage 5-6 sur 100). On pousse le MÊME pct
  -- (potentiellement secret) dans TOUS les quartiers via ns.SmoothSetValue —
  -- exactement le même sink déjà utilisé par `arc` (StatusBar:SetValue), qui
  -- accepte les secret numbers nativement. Le moteur fait tout le clamping
  -- par quartier en interne : AUCUNE arithmétique/comparaison Lua sur pct
  -- n'est nécessaire. Les bornes MinMax sont calculées une seule fois à la
  -- création à partir de l'index k (jamais secret) — donc 100% sûr même en
  -- combat.
  -- Forme : chaque quartier utilise Media/UI/RadialWedge.tga, une vraie part
  -- de tarte (2.8° = 280°/100) dessinée par l'utilisateur — pointe en bas du
  -- fichier, bord GAUCHE aligné sur la verticale médiane (donc le quartier
  -- s'étend sur 2.8° vers la DROITE de cette référence, pas symétrique).
  -- Taille/position/rotation sont calculées par LayoutRadialFrags() (pas ici
  -- en dur) pour rester rafraîchissables depuis ApplySettings().
  -- Activé/désactivé via cfg.radialFillTest (défaut false = comportement
  -- actuel inchangé). Toggle live : /rcradial.
  ---------------------------------------------------------------------------
  local radialFillFrame = CreateFrame("Frame", nil, bar)
  radialFillFrame:SetFrameLevel(arc:GetFrameLevel())
  radialFillFrame:SetAllPoints(bar)
  local radialFrags = {}
  for k = 0, RADIAL_FRAG_COUNT - 1 do
    local frag = CreateFrame("StatusBar", nil, radialFillFrame)
    -- Niveau explicite et croissant : évite un ordre d'empilement instable
    -- entre les 100 quartiers (frères de même niveau sinon), source probable
    -- de l'aspect "texturé"/haché aux jointures observé en jeu.
    frag:SetFrameLevel(radialFillFrame:GetFrameLevel() + 1 + k)
    frag:SetStatusBarTexture("Interface\\AddOns\\AishCore\\Media\\UI\\RadialWedge.tga")
    frag:SetOrientation("VERTICAL")
    local lo = (k / RADIAL_FRAG_COUNT) * 100
    local hi = ((k + 1) / RADIAL_FRAG_COUNT) * 100
    frag:SetMinMaxValues(lo, hi)
    frag:SetValue(lo)
    radialFrags[k + 1] = frag
  end
  bar.radialFillFrame = radialFillFrame
  bar.radialFrags      = radialFrags
  bar.RADIAL_FRAG_COUNT = RADIAL_FRAG_COUNT
  LayoutRadialFrags()

  -- Arc de stagger (Moine Brasseur) : s'inscrit dans le trou laissé par l'overlay principal
  local staggerFrame = CreateFrame("Frame", nil, bar)
  staggerFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  staggerFrame:SetAllPoints(bar)

  local staggerArcPx = arcPx * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
  local staggerArc = CreateFrame("StatusBar", nil, staggerFrame)
  staggerArc:SetFrameLevel(staggerFrame:GetFrameLevel())
  staggerArc:SetSize(staggerArcPx, staggerArcPx * ARC_CROP_H)
  staggerArc:SetPoint("TOP", bar, "CENTER", 0, staggerArcPx / 2)
  ns.SetSmoothStatusBarTexture(staggerArc, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  staggerArc:SetOrientation("VERTICAL")
  staggerArc:SetMinMaxValues(0, 100)
  staggerArc:SetValue(0)
  staggerArc:SetStatusBarColor(STAGGER_LIGHT[1], STAGGER_LIGHT[2], STAGGER_LIGHT[3], 1)
  staggerArc:Hide()
  bar.staggerArc   = staggerArc
  bar.staggerFrame = staggerFrame
  RecordHome(staggerArc, "TOP", bar, "CENTER", 0, staggerArcPx / 2, staggerArcPx, staggerArcPx * ARC_CROP_H)

  local staggerOverlayFrame = CreateFrame("Frame", nil, bar)
  staggerOverlayFrame:SetFrameLevel(staggerFrame:GetFrameLevel() + 1)
  staggerOverlayFrame:SetAllPoints(bar)
  local staggerOverlay = staggerOverlayFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(staggerOverlay, ns.Media.circle)
  local staggerOverlayPx = staggerArcPx * (cfg.staggerOverlayRatio or STAGGER_OVERLAY_RATIO)
  if staggerOverlayPx >= 2 then staggerOverlay:SetSize(staggerOverlayPx, staggerOverlayPx) end
  staggerOverlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  staggerOverlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  staggerOverlayFrame:Hide()
  bar.staggerOverlay      = staggerOverlay
  bar.staggerOverlayFrame = staggerOverlayFrame

  -- Arc de durée (Pala Prot / Guerrier Prot / DK Sang) : parallèle au stagger, mutuellement exclusif
  -- Arc de durée (même approche que stagger : StatusBar + circle_piecrop.tga)
  local durationArcPx = arcPx * (ns.GetSecResCfg("durationArcRatio") or DURATION_ARC_RATIO)
  local durationArcFrame = CreateFrame("Frame", nil, bar)
  durationArcFrame:SetFrameLevel(staggerFrame:GetFrameLevel())
  durationArcFrame:SetAllPoints(bar)
  local durationArcBar = CreateFrame("StatusBar", nil, durationArcFrame)
  durationArcBar:SetFrameLevel(durationArcFrame:GetFrameLevel())
  durationArcBar:SetSize(durationArcPx, durationArcPx * ARC_CROP_H)
  durationArcBar:SetPoint("TOP", bar, "CENTER", 0, durationArcPx / 2)
  ns.SetSmoothStatusBarTexture(durationArcBar, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  durationArcBar:SetOrientation("VERTICAL")
  durationArcBar:SetMinMaxValues(0, 1)
  durationArcBar:SetValue(0)
  durationArcBar:Hide()
  bar.durationArc      = durationArcBar
  bar.durationArcFrame = durationArcFrame

  local durationOvlFrame = CreateFrame("Frame", nil, bar)
  durationOvlFrame:SetFrameLevel(staggerOverlayFrame:GetFrameLevel())
  durationOvlFrame:SetAllPoints(bar)
  local durationOvl = durationOvlFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(durationOvl, ns.Media.circle)
  local durationOvlPx = durationArcPx * (ns.GetSecResCfg("durationArcOverlayRatio") or DURATION_ARC_OVL_RATIO)
  if durationOvlPx >= 2 then durationOvl:SetSize(durationOvlPx, durationOvlPx) end
  durationOvl:SetPoint("CENTER", bar, "CENTER", 0, 0)
  durationOvl:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  durationOvlFrame:Hide()
  bar.durationOvlFrame = durationOvlFrame
  bar.durationOvl      = durationOvl

  -- Texte + dots sur un frame superieur a staggerOverlayFrame (sinon cachés derrière)
  local textFrame = CreateFrame("Frame", nil, bar)
  textFrame:SetFrameLevel(staggerOverlayFrame:GetFrameLevel() + 1)
  textFrame:SetAllPoints(bar)

  -- 5 petits cercles colorés en bas (sur textFrame pour passer au-dessus de l'overlay)
  local initDotSizes = ns.Defaults.resourceCircle.dotSizes
  local initDotPositions = ns.Defaults.resourceCircle.dotPositions
  for i = 1, 5 do
    local dot = textFrame:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(ns.Media.circle)
    dot:SetSize(initDotSizes[i], initDotSizes[i])
    dot:SetPoint("BOTTOM", bar, "BOTTOM", initDotPositions[i][1], initDotPositions[i][2])
    dot:SetVertexColor(cfg.dotColors[i][1], cfg.dotColors[i][2], cfg.dotColors[i][3], 1)
    bar["dot" .. i] = dot
    RecordHome(dot, "BOTTOM", bar, "BOTTOM", initDotPositions[i][1], initDotPositions[i][2], initDotSizes[i], initDotSizes[i])
  end

  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(ns.Media.font, cfg.fontSize)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  text:SetTextColor(unpack(cfg.textColor))
  bar.text = text
  RecordHome(text, "CENTER", bar, "CENTER", 0, 0)
  bar.textFrame = textFrame
  ns.ringBarTextFrame = textFrame  -- exposé pour SpellEffects (frame level de référence)

  -- Texte de ressource secondaire (Bone Shield, Soul Fragments, etc.)
  -- Affiché sous le texte de puissance (bar.text), sur un frame UIParent.
  local secResFrame = CreateFrame("Frame", nil, UIParent)
  secResFrame:SetSize(120, 18)
  secResFrame:SetFrameLevel(textFrame:GetFrameLevel() + 1)
  secResFrame:SetPoint("TOP", text, "BOTTOM", 0, -2)
  bar.secResFrame = secResFrame

  local secResText = secResFrame:CreateFontString(nil, "OVERLAY")
  secResText:SetFont(FONT_BOLD_ITALIC, 11, "")
  secResText:SetPoint("CENTER", secResFrame, "CENTER", 0, 0)
  secResText:SetTextColor(1, 1, 1, 1)
  secResText:SetText("")
  secResText:Hide()
  bar.secResText = secResText

  -- Déco "- N -" (style/espacement configurables, cf. RefreshSecResDeco) :
  -- FontStrings séparées (texte fixe, jamais secret), ancrées aux bords de
  -- secResText pour suivre sa largeur variable. Voir SetSecResShown en tête
  -- de fichier pour le pourquoi de cette séparation.
  local secResDashL = secResFrame:CreateFontString(nil, "OVERLAY")
  secResDashL:SetFont(FONT_BOLD_ITALIC, 11, "")
  secResDashL:SetTextColor(1, 1, 1, 1)
  secResDashL:Hide()
  bar.secResDashL = secResDashL

  local secResDashR = secResFrame:CreateFontString(nil, "OVERLAY")
  secResDashR:SetFont(FONT_BOLD_ITALIC, 11, "")
  secResDashR:SetTextColor(1, 1, 1, 1)
  secResDashR:Hide()
  bar.secResDashR = secResDashR
  RefreshSecResDeco()

  -- Fond sombre sous le power text pour lisibilité (masqué pour Brasseur qui a son propre overlay)
  local textBackdrop = textFrame:CreateTexture(nil, "BACKGROUND")
  textBackdrop:SetTexture(ns.Media.circle)
  textBackdrop:SetSize(35, 35)
  textBackdrop:SetPoint("CENTER", bar, "CENTER", 0, 0)
  textBackdrop:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.textBackdrop = textBackdrop
  RecordHome(textBackdrop, "CENTER", bar, "CENTER", 0, 0, 35, 35)

  bar:Show()
  _G.AishCoreRingBar = bar

  -- Detecter le type de secondary dots selon la classe/forme
  ResourceCircle.DetectSecondaryDots()
  -- Detecter la ressource secondaire (Bone Shield, Soul Fragments…)
  ResourceCircle.DetectSecondaryResource()
  -- Detecter l'arc de stagger (Moine Brasseur)
  ResourceCircle.DetectStagger()
  -- Démarrer le frame d'animation slide des secondary dots
  ResourceCircle.CreateSecAnimFrame()

  -- Frame dédié au tracking Essence Burst + Fire Mage procs via spell overlay glow
  local overlayEvtFrame = CreateFrame("Frame")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
  overlayEvtFrame:SetScript("OnEvent", function(_, event, spellID)
    local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or (event == "SPELL_ACTIVATION_OVERLAY_SHOW")
    local isGlow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or (event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

    -- Essence Burst (Evoker Preservation) : glow sur sorts spécifiques
    if isGlow and ESSENCE_BURST_SPELLS[spellID] then
      if isShow then essenceBurstGlowing[spellID] = true
      else            essenceBurstGlowing[spellID] = nil end
      local any = false
      for _ in pairs(essenceBurstGlowing) do any = true break end
      local prevActive = essenceBurstActive
      essenceBurstActive = any
      -- Animer le combo SpellEffects uniquement pour Preservation (specID 1468)
      if essenceBurstActive ~= prevActive then
        local _, ebClass = UnitClass("player")
        if ebClass == "EVOKER" then
          local ebSpecIdx = GetSpecialization and GetSpecialization() or nil
          local ebSpecID = ebSpecIdx and (GetSpecializationInfo and GetSpecializationInfo(ebSpecIdx)) or nil
          if ebSpecID == 1468 then
            local SE_eb = ns.Modules and ns.Modules.SpellEffects
            if SE_eb then
              if essenceBurstActive then
                if SE_eb.StartSustained then SE_eb.StartSustained(9000003) end
              else
                if SE_eb.StopSustained then SE_eb.StopSustained(9000003) end
              end
            end
          end
        end
      end
    end

    -- Fire Mage (spec 2 = Fire uniquement)
    local _, playerClass = UnitClass("player")
    if playerClass == "MAGE" and GetSpecialization() == 2 then
      if not isGlow then
        -- SPELL_ACTIVATION_OVERLAY_SHOW/HIDE : overlay écran = Heating Up
        fireOverlayActive = isShow
      elseif FIRE_PYRO_SPELLS[spellID] then
        -- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE sur Pyroblast/Flamestrike = Hot Streak
        firePyroGlowing = isShow
      end
      local newLevel = firePyroGlowing and 2 or (fireOverlayActive and 1 or 0)
      if newLevel ~= fireProcLevel then
        local prevLevel = fireProcLevel
        fireProcLevel = newLevel
        if bar and bar.text then bar.text:SetText(tostring(fireProcLevel)) end
        -- Démarrer/arrêter l'animation soutenue SpellEffects selon l'état
        local SE = ns.Modules and ns.Modules.SpellEffects
        if SE then
          if newLevel == 0 then
            -- Aucun proc : tout éteindre immédiatement
            if SE.StopSustained then SE.StopSustained(9000001) end
            if SE.StopSustained then SE.StopSustained(9000002) end
          elseif newLevel == 1 then
            -- Heating Up actif : éteindre Hot Streak, allumer Heating Up
            if SE.StopSustained  then SE.StopSustained(9000002)  end
            if SE.StartSustained then SE.StartSustained(9000001) end
          elseif newLevel == 2 then
            -- Hot Streak actif : éteindre Heating Up, allumer Hot Streak
            if SE.StopSustained  then SE.StopSustained(9000001)  end
            if SE.StartSustained then SE.StartSustained(9000002) end
          end
        end
      end
    end

    -- Warlock Démonologie : Demonic Core → glow sur Demonbolt (264178)
    local _, wlClass = UnitClass("player")
    if isGlow and spellID == DEMONBOLT_SPELL_ID and wlClass == "WARLOCK" then
      local wlSpecIdx = GetSpecialization and GetSpecialization() or nil
      local wlSpecID  = wlSpecIdx and (GetSpecializationInfo and GetSpecializationInfo(wlSpecIdx)) or nil
      if wlSpecID == 265 then
        demonicCoreOverlayActive = isShow
      end
    end
  end)

  -- Pré-allouer la table d'éléments pour AnimateVisibility (11 slots fixes + 2 staggerArc conditionnels).
  -- Les frame-refs sont stables après Create(). Les slots 11-12 ont element=nil par défaut.
  -- delay/duration ne sont PAS fixés ici : AnimateVisibility() les recalcule
  -- à chaque appel depuis CIRCLE_ANIM, selon la direction (show/hide, cf.
  -- _RC_ANIM_GROUP tout en haut du fichier).
  do
    _rcAnimElems[1]  = { element = bar.bgGlow  }
    _rcAnimElems[2]  = { element = bar.bgLarge }
    _rcAnimElems[3]  = { element = bar.text    }
    -- Slots 4 et 5 (arc, overlayFrame) : plus animés ici, cf. AnimateArcOverlay
    -- (timing dédié, découplé du stagger générique, cf. CIRCLE_ANIM.arc/arcOverlay).
    _rcAnimElems[4]  = { element = nil }
    _rcAnimElems[5]  = { element = nil }
    _rcAnimElems[6]  = { element = bar.dot3 }
    _rcAnimElems[7]  = { element = bar.dot2 }
    _rcAnimElems[8]  = { element = bar.dot4 }
    _rcAnimElems[9]  = { element = bar.dot1 }
    _rcAnimElems[10] = { element = bar.dot5 }
    -- Slots 11 et 12 (staggerArc, staggerOverlayFrame) : plus animés ici non
    -- plus, cf. slots 4/5 -- AnimateArcOverlay les anime désormais avec la
    -- même spec que l'arc principal.
    _rcAnimElems[11] = { element = nil }
    _rcAnimElems[12] = { element = nil }
    _rcAnimElems[13] = { element = bar.textBackdrop }
    _rcAnimElems[14] = { element = nil }  -- secResFrame (conditionnel : seulement si secResDef existe)
  end

  ResourceCircle.ApplyRadialMode()

  return bar
end

---------------------------------------------------------------------------
-- [EXPERIMENTAL] Bascule entre le remplissage vertical (arc, actuel/défaut)
-- et le remplissage radial (chapelet de fragments dans radialFillFrame).
-- Les fragments sont enfants de radialFillFrame : Show/Hide du wrapper
-- suffit, pas besoin de boucler dessus (héritage de visibilité WoW standard).
-- Le reste (couleurs, overlay du trou central, dots, texte) est partagé et
-- inchangé. Appelé au Create() et par /rcradial pour un test à chaud.
function ResourceCircle.ApplyRadialMode()
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")
  local radial = cfg.radialFillTest == true
  -- SetAlpha(1)/SetScale(1) sur l'élément qui DEVIENT actif : sans ça, s'il
  -- a été laissé au milieu d'une transition interrompue (ex: changement de
  -- mode pendant une anim de combat), il resterait bloqué à cette
  -- alpha/scale intermédiaire — invisible ou à moitié rétréci — au lieu de
  -- repartir d'un état propre.
  if bar.arc then
    if radial then bar.arc:Hide() else bar.arc:SetAlpha(1); bar.arc:SetScale(1); bar.arc:Show() end
  end
  if bar.radialFillFrame then
    if radial then bar.radialFillFrame:SetAlpha(1); bar.radialFillFrame:SetScale(1); bar.radialFillFrame:Show() else bar.radialFillFrame:Hide() end
  end
  -- Forcer un refresh immédiat pour éviter un flash à l'ancienne valeur.
  pcall(ResourceCircle.Update)
end

-- [EXPERIMENTAL] Applique pct (0-100) à l'arc actif (vertical ou radial).
-- Radial : on repousse le MÊME pct (potentiellement secret) dans chaque
-- quartier via le sink déjà éprouvé ns.SmoothSetValue (StatusBar:SetValue).
-- Chaque quartier a sa propre plage MinMax fixée à la création (cf. Create),
-- donc le moteur affiche automatiquement : quartiers avant pct → pleins,
-- quartier courant → partiellement rempli, quartiers après → vides. Aucune
-- arithmétique/comparaison Lua sur pct n'est nécessaire ici.
-- (Un essai de balayage étalé dans le temps a été tenté puis abandonné :
-- ApplyArcValue peut être appelé très fréquemment en combat, et chaque
-- appel annulait/relançait le balayage précédent — s'il arrive plus vite
-- que la durée du balayage, celui-ci n'atteint jamais les quartiers de fin
-- de plage, d'où un remplissage bloqué à une petite portion de l'arc.)
local function ApplyArcValue(pct)
  local cfg = ns.GetCfg("resourceCircle")
  if cfg.radialFillTest and bar.radialFrags then
    for _, frag in ipairs(bar.radialFrags) do
      pcall(ns.SmoothSetValue, frag, pct)
    end
  else
    pcall(ns.SmoothSetValue, bar.arc, pct)
  end
end

---------------------------------------------------------------------------
-- [EXPERIMENTAL] Anime l'arc actif (vertical ou radial) et l'overlay qui
-- masque son centre, INDÉPENDAMMENT du système de stagger générique
-- (_rcAnimElems) — ce couple a des exigences de timing différentes des
-- autres éléments (dots, texte, glow...) et se marchait dessus quand tout
-- passait par le même système.
--
-- Arc et overlay sont animés en parallèle mais 100% indépendamment l'un de
-- l'autre : chacun a son propre duration/delay/ease/easeType/slide/opacity
-- (cf. CIRCLE_ANIM.arc / CIRCLE_ANIM.arcOverlay tout en haut du fichier), et
-- chacun se termine (Hide, reset de position) sur SON PROPRE timing plutôt
-- que d'attendre l'autre. Par défaut ils restent réglés pour que l'overlay
-- finisse en dernier à l'apparition et disparaisse en dernier à la sortie
-- (pour ne jamais laisser transparaître le trou central de l'arc pendant
-- la transition), mais rien ne les synchronise plus structurellement —
-- change l'un sans toucher l'autre si besoin.
---------------------------------------------------------------------------
-- Un ticker par "paire" arc+overlay animée (main = bar.arc/bar.overlayFrame,
-- stagger = bar.staggerArc/bar.staggerOverlayFrame) : les deux peuvent tourner
-- en parallèle (entrée en combat d'un Brasseur), donc pas un seul ticker partagé.
local _arcOverlayTickers = { main = nil, stagger = nil }
-- Anime UNE paire arc+overlay avec la spec CIRCLE_ANIM.arc/arcOverlay --
-- factorisé pour que l'arc de stagger (staggerArc/staggerOverlayFrame,
-- structurellement identique à bar.arc/bar.overlayFrame : même StatusBar
-- piecrop + même texture overlay) reçoive EXACTEMENT la même animation que
-- l'arc principal plutôt qu'une copie de réglages qui pourrait diverger.
local function AnimateArcOverlayPair(key, shouldShow, arcEl, overlayEl, overlayVisualEl)
  if not arcEl or not overlayEl then return end
  if _arcOverlayTickers[key] then _arcOverlayTickers[key]:Cancel(); _arcOverlayTickers[key] = nil end

  local arcSpec     = shouldShow and CIRCLE_ANIM.arc.show        or CIRCLE_ANIM.arc.hide
  local overlaySpec = shouldShow and CIRCLE_ANIM.arcOverlay.show or CIRCLE_ANIM.arcOverlay.hide

  -- opacity = alpha de DÉPART pour show / de FIN pour hide (l'autre bout
  -- vaut toujours 1) — cf. doc de ns.AnimateStagger dans Core.lua, même
  -- convention ici.
  local arcOpacity, overlayOpacity = arcSpec.opacity or 0, overlaySpec.opacity or 0
  local arcStartAlpha, arcEndAlpha         = shouldShow and arcOpacity or 1,     shouldShow and 1 or arcOpacity
  local overlayStartAlpha, overlayEndAlpha = shouldShow and overlayOpacity or 1, shouldShow and 1 or overlayOpacity

  -- Capture la position/taille "home" sur l'ancrage RÉEL de l'élément (ex:
  -- BOTTOM pour l'arc) — jamais mise en cache entre appels (même
  -- raisonnement que dans ns.AnimateStagger).
  --
  -- Le scale ici passe par SetSize, PAS SetScale : SetScale grossit un
  -- élément depuis un pivot qui s'est avéré (test en jeu) ne pas être le
  -- point d'ancrage réel, ce qui rendait tout effet "grossit depuis le bas"
  -- impossible à obtenir de façon fiable. SetSize, lui, grossit TOUJOURS
  -- de façon garantie depuis le point d'ancrage (c'est la définition même
  -- d'un ancrage : ce point ne bouge jamais, seuls les bords non-ancrés se
  -- déplacent quand la taille change) — exactement le mécanisme qui fait
  -- déjà fonctionner les dots (dont scaleX ≠ scaleY bascule ns.AnimateStagger
  -- sur SetSize). Le facteur reste uniforme (même `scale` en X et Y), donc
  -- le ratio largeur:hauteur du crop pie-crop de l'arc (ARC_CROP_H) est
  -- préservé quel que soit le scale appliqué.
  -- Position (slide) et taille (scale) sont capturées et guardées SÉPARÉMENT :
  -- GetPoint/GetSize peuvent chacun renvoyer des "secret values" (protection
  -- anti-taint TWW/11.x) INDÉPENDAMMENT l'un de l'autre selon le contexte,
  -- et le scale (SetSize) n'a besoin d'AUCUNE donnée de position pour
  -- fonctionner — coupler les deux ferait perdre le scale à chaque fois que
  -- la position est secrète, même sans aucun slide demandé.
  -- Utilise la géométrie pré-calculée (cf. RecordHome/_elemHome plus haut
  -- dans le fichier) si disponible : fiable même en combat, contrairement à
  -- GetPoint/GetSize qui peuvent renvoyer des "secret values" à ce moment-là.
  local function captureHome(element)
    if not element then return nil end
    local cached = _elemHome[element]
    if cached then return cached end
    -- Filet de sécurité si jamais l'élément n'a pas de géométrie enregistrée.
    local home = {}
    local point, relTo, relPoint, x, y = element:GetPoint(1)
    if point and not ns.IsSecret(point) and not ns.IsSecret(x) and not ns.IsSecret(y) then
      home.point, home.relTo, home.relPoint, home.x, home.y = point, relTo, relPoint, x, y
    end
    local w, h = element:GetSize()
    if not ns.IsSecret(w) and not ns.IsSecret(h) then
      home.w, home.h = w, h
    end
    if not home.point and not home.w then return nil end
    return home
  end
  -- Redimensionner une StatusBar (arc, staggerArc, durationArc...) NE
  -- réapplique PAS automatiquement le crop de sa texture : le SetSize
  -- change bien la frame (vérifié via GetSize), mais le rendu du
  -- texture-crop reste figé jusqu'au prochain SetValue(). ET un simple
  -- element:SetValue(element:GetValue()) direct ne suffit PAS : tout le
  -- reste de l'addon pousse les valeurs via ns.SmoothSetValue, qui appelle
  -- SetValue(value, StatusBarInterpolation.ExponentialEaseOut) — cette
  -- StatusBar est donc en permanence sous interpolation NATIVE Blizzard, et
  -- un SetValue "nu" (sans le paramètre d'interpolation) se fait
  -- vraisemblablement ignorer/écraser par cette interpolation C++ en cours.
  -- On réutilise donc directement ns.SmoothSetValue au lieu de réinventer
  -- notre propre SetValue : passthrough sûr même si la valeur est secrète
  -- en combat (ns.SmoothSetValue fait déjà tout en pcall côté C).
  -- Textures (bar.overlay) n'ont pas ce problème : elles n'ont pas GetValue.
  local function RefreshCrop(element)
    if element.GetValue and element.SetValue then
      ns.SmoothSetValue(element, element:GetValue())
    end
  end
  -- useGlobalScale : StatusBar (arc) utilise SetScale (facteur unique,
  -- transform purement visuelle, ne touche jamais au crop interne de la
  -- StatusBar — contourne le souci de redraw) plutôt que SetSize (déforme
  -- réellement la frame, ce qui marche bien pour une Texture comme
  -- bar.overlay mais pas pour une StatusBar au crop personnalisé). Le
  -- pivot de SetScale n'est PAS garanti être l'ancrage BOTTOM (contrairement
  -- à SetSize) — accepté pour l'instant, l'essentiel est que ça s'anime.
  local function applyTransform(element, home, slideX, slideY, p, scale, useGlobalScale)
    if not home then return end
    if home.point then
      local fromX = shouldShow and (home.x + slideX) or home.x
      local toX   = shouldShow and home.x or (home.x + slideX)
      local fromY = shouldShow and (home.y + slideY) or home.y
      local toY   = shouldShow and home.y or (home.y + slideY)
      element:ClearAllPoints()
      element:SetPoint(home.point, home.relTo, home.relPoint,
        fromX + (toX - fromX) * p, fromY + (toY - fromY) * p)
    end
    if useGlobalScale then
      element:SetScale(scale)
    elseif home.w then
      element:SetSize(home.w * scale, home.h * scale)
      RefreshCrop(element)
    end
    -- Memorise le DERNIER scale reellement applique (cf. commentaire sur
    -- arcStartScale/overlayStartScale plus haut) : permet a une animation
    -- interrompue de repartir d'ou elle en etait, pas d'un point de depart
    -- fixe, meme si la precedente n'a jamais atteint resetTransform.
    element._aishAnimScale = scale
  end
  local function resetTransform(element, home, useGlobalScale)
    if not home then return end
    if home.point then
      element:ClearAllPoints()
      element:SetPoint(home.point, home.relTo, home.relPoint, home.x, home.y)
    end
    if useGlobalScale then
      element:SetScale(1)
    elseif home.w then
      element:SetSize(home.w, home.h)
      RefreshCrop(element)
    end
    -- nil (pas 1) : une animation qui va au bout de son cycle (show OU hide)
    -- doit laisser le PROCHAIN cycle repartir du point de depart canonique
    -- (petit pour un show, cf. arcStartScale/overlayStartScale) -- sinon
    -- l'effet "pop in" depuis un petit scale serait perdu apres le tout
    -- premier cycle complet (hide ramene le widget a scale=1 avant de le
    -- Hide(), un show qui suivrait sans interruption partirait alors a tort
    -- de 1 au lieu de arcScale/overlayScale). nil = "pas d'etat interrompu
    -- a reprendre", le fallback canonique s'applique normalement.
    element._aishAnimScale = nil
  end

  local arcSlideX, arcSlideY = arcSpec.slideX or 0, arcSpec.slideY or 0
  local ovlSlideX, ovlSlideY = overlaySpec.slideX or 0, overlaySpec.slideY or 0
  local arcScale     = arcSpec.scale or 1
  local overlayScale = overlaySpec.scale or 1
  local arcStartScale, arcEndScale         = shouldShow and arcScale or 1,     shouldShow and 1 or arcScale
  local overlayStartScale, overlayEndScale = shouldShow and overlayScale or 1, shouldShow and 1 or overlayScale
  -- BUG CORRIGE (2026-08-20, "overlay trop petit apres montrer/cacher
  -- rapide", ex: entrees/sorties de combat successives ou meme Skyriding
  -- HUD qui appelle AnimateVisibility/AnimateArcOverlay) : le point de
  -- depart etait TOUJOURS le point canonique (arcScale/overlayScale, ex:
  -- 0.7) pour ce sens d'animation, jamais l'etat REEL de l'element. Si une
  -- animation "show" est coupee avant d'atteindre son scale final (1) --
  -- typique d'un nouveau show/hide qui arrive avant la fin -- la nouvelle
  -- animation repartait quand meme du point canonique PETIT au lieu de la
  -- ou l'element en etait vraiment : plusieurs interruptions rapprochees
  -- empechent alors l'element d'atteindre 1 (grandeur normale), le
  -- laissant visuellement bloque petit indefiniment. On repart maintenant
  -- du dernier scale REELLEMENT applique (_aishAnimScale, memorise par
  -- applyTransform/resetTransform ci-dessus) quand connu -- l'animation
  -- continue naturellement d'ou elle en etait au lieu de sauter en arriere.
  if arcEl and arcEl._aishAnimScale then arcStartScale = arcEl._aishAnimScale end
  if overlayVisualEl and overlayVisualEl._aishAnimScale then overlayStartScale = overlayVisualEl._aishAnimScale end

  local needArcTransform     = arcSlideX ~= 0 or arcSlideY ~= 0 or arcScale ~= 1
  local needOverlayTransform = ovlSlideX ~= 0 or ovlSlideY ~= 0 or overlayScale ~= 1
  local arcHome     = needArcTransform and captureHome(arcEl) or nil
  local overlayHome = needOverlayTransform and captureHome(overlayVisualEl) or nil

  arcEl:Show(); arcEl:SetAlpha(arcStartAlpha)
  if overlayVisualEl then overlayVisualEl:Show() end
  overlayEl:Show(); overlayEl:SetAlpha(overlayStartAlpha); overlayEl:SetScale(1)

  -- BUG CORRIGE (2026-08-20, "overlay noir mal superpose apres un
  -- entree/sortie de combat rapide") : contrairement a l'alpha (remis a
  -- arcStartAlpha/overlayStartAlpha IMMEDIATEMENT ci-dessus), la position/
  -- taille (applyTransform) n'etait appliquee que DANS le ticker, au
  -- premier tick ou elapsed>=0 (donc apres arcSpec.delay/overlaySpec.delay).
  -- Si cette animation est elle-meme interrompue (nouvel appel qui annule
  -- le ticker, cf. debut de fonction) avant ce premier tick -- typique d'un
  -- entree/sortie de combat rapproche qui redeclenche coup sur coup -- la
  -- position/taille reste bloquee a l'etat laisse par l'animation
  -- PRECEDENTE, jamais reinitialisee au point de depart correct de celle-
  -- ci. Applique ici en p=0, tout de suite, comme pour l'alpha -- l'element
  -- part TOUJOURS d'une geometrie connue et correcte, meme si cette
  -- animation est elle-meme coupee avant son premier tick.
  if arcHome then
    applyTransform(arcEl, arcHome, arcSlideX, arcSlideY, 0, arcStartScale, true)
  end
  if overlayHome then
    applyTransform(overlayVisualEl, overlayHome, ovlSlideX, ovlSlideY, 0, overlayStartScale)
  end

  local now = GetTime()
  local arcStart, overlayStart = now + arcSpec.delay, now + overlaySpec.delay
  local arcDone, overlayDone = false, false

  _arcOverlayTickers[key] = C_Timer.NewTicker(0.016, function()
    local tick = GetTime()

    if not arcDone then
      local elapsed = tick - arcStart
      if elapsed >= 0 then
        local p = ns.Ease(arcSpec.ease, arcSpec.easeType, math.min(elapsed / arcSpec.duration, 1))
        arcEl:SetAlpha(arcStartAlpha + (arcEndAlpha - arcStartAlpha) * p)
        if arcHome then
          applyTransform(arcEl, arcHome, arcSlideX, arcSlideY, p, arcStartScale + (arcEndScale - arcStartScale) * p, true)
        end
        if elapsed >= arcSpec.duration then
          arcEl:SetAlpha(arcEndAlpha)
          resetTransform(arcEl, arcHome, true)
          if not shouldShow then arcEl:Hide() end
          arcDone = true
        end
      end
    end

    if not overlayDone then
      local elapsed = tick - overlayStart
      if elapsed >= 0 then
        local p = ns.Ease(overlaySpec.ease, overlaySpec.easeType, math.min(elapsed / overlaySpec.duration, 1))
        overlayEl:SetAlpha(overlayStartAlpha + (overlayEndAlpha - overlayStartAlpha) * p)
        if overlayHome then
          applyTransform(overlayVisualEl, overlayHome, ovlSlideX, ovlSlideY, p, overlayStartScale + (overlayEndScale - overlayStartScale) * p)
        end
        if elapsed >= overlaySpec.duration then
          overlayEl:SetAlpha(overlayEndAlpha)
          resetTransform(overlayVisualEl, overlayHome)
          if not shouldShow then
            overlayEl:Hide()
            if overlayVisualEl then overlayVisualEl:Hide() end
          end
          overlayDone = true
        end
      end
    end

    if arcDone and overlayDone then
      _arcOverlayTickers[key]:Cancel()
      _arcOverlayTickers[key] = nil
    end
  end)
end

-- Anime l'arc actif (vertical ou radial) + son overlay, ET -- si le stagger
-- Brasseur est actif -- l'arc de stagger avec la même spec (cf.
-- AnimateArcOverlayPair). Point d'entrée public inchangé.
local function AnimateArcOverlay(shouldShow)
  if not bar then return end

  local cfg = ns.GetCfg("resourceCircle")
  local radial = cfg.radialFillTest == true
  local arcEl      = radial and bar.radialFillFrame or bar.arc
  local otherArcEl = radial and bar.arc or bar.radialFillFrame
  if otherArcEl then otherArcEl:Hide() end

  -- Le slide (et le scale) de l'overlay principal s'appliquent à la TEXTURE
  -- bar.overlay (le disque visible, ancré CENTER) plutôt qu'à bar.overlayFrame
  -- (le wrapper, ancré via SetAllPoints -- pas de pivot exploitable).
  AnimateArcOverlayPair("main", shouldShow, arcEl, bar.overlayFrame, bar.overlay)

  -- Arc de stagger (Moine Brasseur) : structurellement identique à l'arc
  -- principal (staggerArc ~ bar.arc, staggerOverlayFrame ~ bar.overlayFrame,
  -- staggerOverlay ~ bar.overlay), donc EXACTEMENT la même animation.
  if bar.staggerArc and bar.staggerOverlayFrame then
    if staggerActive then
      AnimateArcOverlayPair("stagger", shouldShow, bar.staggerArc, bar.staggerOverlayFrame, bar.staggerOverlay)
    elseif _arcOverlayTickers.stagger then
      _arcOverlayTickers.stagger:Cancel(); _arcOverlayTickers.stagger = nil
      bar.staggerArc:Hide()
      bar.staggerOverlayFrame:Hide()
    end
  end
end

-- Animation pour l'apparition/disparition avec stagger et scale
function ResourceCircle.AnimateVisibility(shouldShow)
  if animationTicker then
    animationTicker:Cancel()
    animationTicker = nil
  end
  if not bar then return end

  local cfg = ns.GetCfg("resourceCircle")
  local duration = 0.4
  local staggerInterval = 0.05
  local startTime = GetTime()
  local targetAlpha = shouldShow and 1 or 0

  -- Mettre à jour les slots conditionnels (mutation en place, pas d'allocation)
  _rcAnimElems[14].element = (secResDef and bar.secResFrame)             or nil
  -- Les secondary dots ont leur propre animation slide (secAnimFrame) : exclus du stagger principal
  -- staggerArc/staggerOverlayFrame : exclus aussi, cf. AnimateArcOverlay

  -- Recalculer le timing/la courbe/le mouvement de chaque slot depuis
  -- CIRCLE_ANIM selon la direction (show = entrée en combat, hide =
  -- sortie) : IN et OUT peuvent avoir des réglages complètement différents.
  for i, group in pairs(_RC_ANIM_GROUP) do
    local spec = shouldShow and CIRCLE_ANIM[group].show or CIRCLE_ANIM[group].hide
    local slot = _rcAnimElems[i]
    slot.delay    = spec.delay
    slot.duration = spec.duration
    slot.ease     = spec.ease
    slot.easeType = spec.easeType
    slot.slideX   = spec.slideX
    slot.slideY   = spec.slideY
    slot.scaleX   = spec.scaleX
    slot.scaleY   = spec.scaleY
    slot.opacity  = spec.opacity
    -- Géométrie de repos pré-calculée (cf. RecordHome) plutôt que relue via
    -- GetPoint/GetSize par ns.AnimateStagger : fiable même en combat (cf.
    -- commentaire détaillé sur _elemHome plus haut dans le fichier).
    local home = slot.element and _elemHome[slot.element]
    if home then
      slot.homePoint, slot.homeRelTo, slot.homeRelPoint = home.point, home.relTo, home.relPoint
      slot.homeX, slot.homeY = home.x, home.y
      slot.homeW, slot.homeH = home.w, home.h
    else
      slot.homePoint = nil
    end
  end

  -- Utiliser l'animation partagée
  animationTicker = ns.AnimateStagger(_rcAnimElems, shouldShow, duration, staggerInterval, function()
    if previewMode then return end
    if not shouldShow then
      bar:Hide()
      -- (arc / radialFillFrame / overlay : masqués par AnimateArcOverlay,
      -- sur son propre timing — pas ici, pour ne pas les couper en avance.)
      bar.bgLarge:Hide()
      bar.text:Hide()
      if bar.textBackdrop then bar.textBackdrop:Hide() end
      for i = 1, 5 do
        if bar["dot" .. i] then bar["dot" .. i]:Hide() end
      end
      -- Forcer le slide-out immédiat des secondary dots
      for i = 1, secDotCount do
        if secDotAnims[i] then secDotAnims[i].target = 0 end
      end
      -- Stopper toutes les animations 3D (Play en cours + soutenues + pool)
      local SE = ns.Modules and ns.Modules.SpellEffects
      if SE and SE.StopAll then SE.StopAll() end
    end
  end)

  -- Animation du mouvement Y pour le frame parent
  if moveTicker then moveTicker:Cancel() end
  moveTicker = C_Timer.NewTicker(0.016, function()
    local elapsed = GetTime() - startTime
    local frameProgress = math.min(elapsed / duration, 1)
    local easeProgress = 1 - (1 - frameProgress) ^ 3

    local startOffsetY = shouldShow and -20 or 0
    local endOffsetY = shouldShow and 0 or -20
    local currentOffsetY = startOffsetY + (endOffsetY - startOffsetY) * easeProgress

    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y + currentOffsetY)

    if elapsed >= duration + staggerInterval * 5 then
      moveTicker:Cancel()
      bar:ClearAllPoints()
      bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    end
  end)
end

-- Mode preview : force l'affichage du cercle pour le settings panel
function ResourceCircle.SetPreview(on)
  previewMode = on
  if not bar then return end

  -- Annuler toute animation en cours
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end
  if moveTicker then moveTicker:Cancel(); moveTicker = nil end

  if on then
    lastVisibilityState = nil
    -- Forcer l'affichage de tous les elements
    bar:Show()
    bar:SetAlpha(1)
    bar:SetScale(1)
    local cfgPrev = ns.GetCfg("resourceCircle")
    if bar.bgGlow then
      if cfgPrev.glowEnabled ~= false then
        bar.bgGlow:Show()
        bar.bgGlow:SetAlpha(cfgPrev.glowOpacity or 0.85)
        bar.bgGlow:SetScale(1)  -- remet l'echelle si l'animation avait ete coupée
      else
        bar.bgGlow:Hide()
      end
    end
    local elements = { bar.bgLarge, bar.text, bar.arc }
    for i = 1, 5 do elements[#elements+1] = bar["dot" .. i] end
    for _, el in ipairs(elements) do
      if el then
        el:Show()
        el:SetAlpha(1)
        if el.SetScale then el:SetScale(1) end
      end
    end
    -- Sec dots : forcer progress=1 pour aperçu immédiat
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if secDotAnims[i] then secDotAnims[i].progress = 1; secDotAnims[i].target = 1 end
        f:Show()
        f:SetAlpha(1)
        if f.SetScale then f:SetScale(1) end
        if f._homeX then
          f:ClearAllPoints()
          f:SetPoint("CENTER", bar, "CENTER", f._homeX, f._homeY)
        end
      end
    end
    if bar.overlay then bar.overlay:Show(); bar.overlay:SetAlpha(1) end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    if bar.textBackdrop then bar.textBackdrop:Show(); bar.textBackdrop:SetAlpha(1) end
    -- Texte de ressource secondaire : visible en preview (valeur factice) SEULEMENT
    -- si la spé actuelle a une définition (DK Sang / DH Vengeance / DH Dévoreur…).
    -- IMPORTANT : reset explicite d'alpha/position — si un pop-out (StartSecResPopOut,
    -- transition combat 1+ -> 0 stack) a été interrompu (reload/combat qui se termine
    -- pendant le fondu), secResFrame peut rester figé à alpha 0 : Show() seul ne suffit
    -- pas à le rendre visible, d'où l'aperçu invisible malgré le texte bien défini.
    if bar.secResFrame and bar.secResText then
      if secResDef then
        bar.secResText:SetText("8")
        SetSecResShown(true)
        bar.secResFrame:SetAlpha(1)
        local home = _elemHome[bar.secResFrame]
        if home then
          bar.secResFrame:ClearAllPoints()
          bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint, home.x, home.y)
        end
        bar.secResFrame:Show()
      else
        SetSecResShown(false)
        bar.secResFrame:Hide()
      end
    end
    -- [EXPERIMENTAL] Respecter le mode radial en preview aussi : sinon l'arc
    -- vertical réapparaîtrait par-dessus le disque radial pendant le test.
    local cfgRadial = ns.GetCfg("resourceCircle")
    if cfgRadial.radialFillTest and bar.radialFillFrame then
      bar.arc:Hide()
      bar.radialFillFrame:Show(); bar.radialFillFrame:SetAlpha(1)
    elseif bar.radialFillFrame then
      bar.radialFillFrame:Hide()
    end
    -- Valeur fictive pour visualiser
    ApplyArcValue(72)
    bar.text:SetText("72")
  else
    lastVisibilityState = nil
    ResourceCircle.Update()
    ResourceCircle.UpdateVisibility()
  end
end

-- Rend le cercle deplacable par drag (pour le mode settings)
function ResourceCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      -- Calculer le nouvel offset depuis CENTER de UIParent
      local cx, cy = self:GetCenter()
      local ucx, ucy = UIParent:GetCenter()
      local newX = math.floor(cx - ucx + 0.5)
      local newY = math.floor(cy - ucy + 0.5)
      -- Sauvegarder en DB
      if not ns.DB then ns.DB = {} end
      if not ns.DB.resourceCircle then ns.DB.resourceCircle = {} end
      ns.DB.resourceCircle.x = newX
      ns.DB.resourceCircle.y = newY
      -- Repositionner proprement
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "CENTER", newX, newY)
    end)
    -- Bordure visuelle "deplacable"
    if not bar._dragBorder then
      local border = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      border:SetAllPoints(bar)
      border:SetColorTexture(1, 1, 1, 0.15)
      bar._dragBorder = border
    end
    bar._dragBorder:Show()
    -- Tooltip au survol
    bar:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["RESOURCE_DRAG_TOOLTIP"])
      GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  else
    bar:SetMovable(false)
    bar:EnableMouse(false)
    bar:RegisterForDrag()
    bar:SetScript("OnDragStart", nil)
    bar:SetScript("OnDragStop", nil)
    bar:SetScript("OnEnter", nil)
    bar:SetScript("OnLeave", nil)
    if bar._dragBorder then bar._dragBorder:Hide() end
  end
end

-- Met à jour la visibilité
function ResourceCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = ResourceCircle.ShouldShow()
  if lastVisibilityState == shouldShow then return end
  lastVisibilityState = shouldShow

  if shouldShow then
    bar:Show()
    -- [EXPERIMENTAL] L'arc (vertical ou radial) et l'overlay ont leur propre
    -- animation dédiée (timing/easing différents des autres éléments) :
    -- voir AnimateArcOverlay.
    AnimateArcOverlay(true)
    bar.bgLarge:Show(); bar.bgLarge:SetAlpha(0)
    local cfg2 = ns.GetCfg("resourceCircle")
    if bar.bgGlow and cfg2.glowEnabled ~= false then bar.bgGlow:Show(); bar.bgGlow:SetAlpha(0) end
    bar.text:Show(); bar.text:SetAlpha(0)
    for i = 1, 5 do
      if bar["dot" .. i] then bar["dot" .. i]:Show(); bar["dot" .. i]:SetAlpha(0) end
    end
    if bar.textBackdrop then bar.textBackdrop:Show(); bar.textBackdrop:SetAlpha(0) end
    -- Les sec dots réinitialisent leur progress pour recréer le slide-in
    for i = 1, secDotCount do
      if secDotAnims[i] then
        secDotAnims[i].progress = 0
        secDotAnims[i].target = 0
      end
    end
    -- Montrer le frame de ressource secondaire s'il y a une définition active
    -- (SetAlpha(0) : laisse AnimateVisibility faire le fade+slide-in, cf. CIRCLE_ANIM.secResText)
    if bar.secResFrame and secResDef then bar.secResFrame:Show(); bar.secResFrame:SetAlpha(0) end
    -- Arc de stagger : Show()/alpha déjà gérés par AnimateArcOverlay (ci-dessus,
    -- même spec que l'arc principal) quand staggerActive -- juste rafraîchir
    -- sa valeur/couleur ici.
    if staggerActive and bar.staggerArc then
      ResourceCircle.UpdateStagger()
    end
    -- Relancer les animations soutenues si un proc est toujours actif
    local SE_show = ns.Modules and ns.Modules.SpellEffects
    if SE_show and SE_show.StartSustained then
      local _, playerClassShow = UnitClass("player")
      local specShow = GetSpecialization and GetSpecialization() or nil
      local specIDShow = specShow and (GetSpecializationInfo and GetSpecializationInfo(specShow)) or nil
      -- Mage Feu
      if playerClassShow == "MAGE" and specIDShow == 63 then
        if fireProcLevel == 1 then SE_show.StartSustained(9000001) end
        if fireProcLevel == 2 then SE_show.StartSustained(9000002) end
      end
      -- Evoker Preservation : Essence Burst
      if playerClassShow == "EVOKER" and specIDShow == 1468 then
        if essenceBurstActive then SE_show.StartSustained(9000003) end
      end
      -- Shaman Enhancement : Maelstrom Weapon
      if playerClassShow == "SHAMAN" and specIDShow == 263 then
        if mwStackLevel == 1 then SE_show.StartSustained(9000004)
        elseif mwStackLevel == 2 then SE_show.StartSustained(9000005)
        elseif mwStackLevel == 3 then SE_show.StartSustained(9000006) end
      end
    end
    ResourceCircle.AnimateVisibility(true)
  else
    -- Déclencher le slide-out des sec dots
    for i = 1, secDotCount do
      if secDotAnims[i] then secDotAnims[i].target = 0 end
    end
    -- Le frame de ressource secondaire se cache via le fondu animé
    -- (CIRCLE_ANIM.secResText + _rcAnimElems[14]), pas de Hide() immédiat ici :
    -- ça laisserait AnimateVisibility(false) animer sa disparition, puis
    -- bar:Hide() (fin d'anim) le cache de toute façon avec le reste.
    -- Arc de stagger : pas de Hide() immédiat ici non plus, même raison que
    -- pour le frame de ressource secondaire ci-dessus -- AnimateArcOverlay(false)
    -- l'anime puis le cache sur SON PROPRE timing (même spec que l'arc principal).
    -- Stopper les animations 3D soutenues immédiatement
    local SE = ns.Modules and ns.Modules.SpellEffects
    if SE and SE.StopAllSustained then SE.StopAllSustained() end
    -- [EXPERIMENTAL] cf. AnimateArcOverlay : timing dédié pour que l'overlay
    -- reste plus opaque que l'arc pendant toute la disparition.
    AnimateArcOverlay(false)
    ResourceCircle.AnimateVisibility(false)
  end
end

-- Forward-déclaré : la vraie définition vit plus bas (~ligne 2464, après ce
-- fichier définit ApplyStacksTo/ApplyStacksToText pour le texte de ressource
-- secondaire) -- Update() ci-dessous en a besoin pour Mage Givre (Frost),
-- donc on le rend visible ici sans dupliquer la logique combat-safe
-- (CDM -> fallback1 -> fallback2, cf. commentaire complet sur ApplyStacksTo).
local ApplyStacksToText

-- Met a jour la valeur et le texte selon la ressource primaire detectee
function ResourceCircle.Update()
  if not bar or not bar.text then return end
  if previewMode then return end
  if not bar:IsShown() then return end  -- rien a mettre a jour si le cercle est cache

  local resource = ns.GetPlayerResource()
  local pct
  local displayText

  -- Ressource aura (string key, ex: MAELSTROM_WEAPON, ICICLES)
  if type(resource) == "string" then
    if ns.AuraResources[resource] then
      -- Filet de securite : si le buff n'existe plus, forcer le cache a 0
      local def = ns.AuraResources[resource]
      local auraData = C_UnitAuras.GetPlayerAuraBySpellID(def.spellID)
      if not auraData and (ns.AuraStacks[resource] or 0) > 0 then
        ns.AuraStacks[resource] = 0
        ns.AuraText[resource]   = "0"
        ns.AuraPct[resource]    = 0
      end
      pct = ns.AuraPct[resource] or 0
      displayText = ns.AuraText[resource] or "0"
      -- Maelstrom Weapon pseudo-spells (Enhancement Shaman specID 263)
      if resource == "MAELSTROM_WEAPON" and ns._playerClass == "SHAMAN" and ns._specID == 263 then
        local stacks = ns.AuraStacks["MAELSTROM_WEAPON"] or 0
        local newMwLevel = (stacks >= 10) and 3 or (stacks >= 8) and 2 or (stacks >= 5) and 1 or 0
        if newMwLevel ~= mwStackLevel then
          mwStackLevel = newMwLevel
          local SE_mw = ns.Modules and ns.Modules.SpellEffects
          if SE_mw then
            if SE_mw.StopSustained then
              SE_mw.StopSustained(9000004)
              SE_mw.StopSustained(9000005)
              SE_mw.StopSustained(9000006)
            end
            if newMwLevel == 1 and SE_mw.StartSustained then SE_mw.StartSustained(9000004)
            elseif newMwLevel == 2 and SE_mw.StartSustained then SE_mw.StartSustained(9000005)
            elseif newMwLevel == 3 and SE_mw.StartSustained then SE_mw.StartSustained(9000006) end
          end
        end
      end
    end
  else
    -- Ressource standard (Enum.PowerType)
    local ok, val = pcall(UnitPowerPercent, "player", resource, true, CurveConstants.ScaleTo100)
    if ok then
      pct = val
      -- Affichage brut pour certaines ressources (Essence, SoulShards, etc.)
      local rawDef = ns.RawDisplayResources and ns.RawDisplayResources[resource]
      if rawDef then
        if rawDef.maxValue then
          -- Deriver la valeur decimale depuis le pourcentage (evite secret numbers)
          displayText = string.format(rawDef.fmt, pct * rawDef.maxValue / 100)
        else
          -- Formater directement sans arithmetique sur le secret number
          local ok2, text = pcall(string.format, rawDef.fmt, UnitPower("player", resource))
          displayText = ok2 and text or string.format("%.0f", pct)
        end
      else
        displayText = string.format("%.0f", pct)
      end
    end
  end

  if pct == nil then
    ApplyArcValue(0)
    bar.text:SetText("-")
    return
  end

  -- Fire Mage (spec 63) : afficher directement 0/1/2 au lieu de la mana
  -- Utilise le cache ns._playerClass / ns._specIndex (mis a jour au login + spec change)
  if ns._playerClass == "MAGE" and ns._specIndex == 2 then  -- spec 2 = Fire
    displayText = tostring(fireProcLevel)
  end

  ApplyArcValue(pct)

  -- Mage Givre (specID 64) : le texte principal affiche les stacks de Glaçons
  -- (205473) au lieu de la mana -- l'arc reste sur pct (mana), inchangé
  -- (ApplyArcValue(pct) juste au-dessus). Utilise directement ns.AuraText.ICICLES
  -- (ResourceMap.lua/ScanAuraStacks, rafraîchi à CHAQUE UNIT_AURA avant que
  -- RC.Update() ne s'exécute, cf. AishCore.lua) plutôt que ApplyStacksToText :
  -- CONFIRMÉ EN JEU que ApplyStacksToText échouait pour 205473 alors que
  -- ns.AuraText.ICICLES était déjà correctement à "5" au même instant --
  -- son 1er repli (GetAuraApplicationDisplayCount sur l'auraInstanceID) rend
  -- ok=true val=nil pour cette aura précise, contrairement à applications
  -- (lu directement par GetPlayerAuraStackCount) qui, lui, fonctionne.
  if ns._playerClass == "MAGE" and ns._specID == 64 then
    local txt = ns.AuraText and ns.AuraText.ICICLES
    pcall(bar.text.SetText, bar.text, txt or "0")
  else
    pcall(bar.text.SetText, bar.text, displayText)
  end
end

-- Reset l'état de visibilité (pour les changements de config)
function ResourceCircle.ResetVisibility()
  lastVisibilityState = nil
end

---------------------------------------------------------------------------
-- Secondary Dots : cercles secondaires (DK runes, Combo Points, etc.)
---------------------------------------------------------------------------

-- Couleurs par type et spec
local SEC_COLORS = {
  -- DK Runes par spec
  RUNES = {
    [250] = { 0.9, 0.1, 0.1 },  -- Blood : rouge
    [251] = { 0.3, 0.7, 1.0 },  -- Frost : bleu
    [252] = { 0.3, 0.9, 0.1 },  -- Unholy : vert
    default = { 0, 0.7, 0.9 },
  },
  -- Combo Points Rogue
  COMBO_ROGUE = {
    default = { 1.0, 0.8, 0.0 },  -- jaune doré
    full    = { 1.0, 0.2, 0.0 },  -- rouge-orange quand max
  },
  -- Combo Points Druide (Félin)
  COMBO_DRUID = {
    default = { 1.0, 0.55, 0.0 },  -- orange ambré (couleur druide)
    full    = { 1.0, 0.15, 0.0 },  -- rouge-orangé quand max
  },
  -- Chi (Moine Windwalker)
  CHI = {
    default = { 0.0, 0.9, 0.6 },  -- turquoise jade
    full    = { 1.0, 1.0, 1.0 },  -- blanc quand max
  },
  -- Holy Power (Paladin Sacré)
  HOLY_POWER = {
    default = { 1.0, 0.82, 0.0 },  -- or sacré
    full    = { 1.0, 1.00, 0.6 },  -- or brillant quand max (remplacé par dotsA à l'affichage)
  },
  ESSENCE = {
    default = { 0.16, 0.82, 0.65 },  -- vert-émeraude (Preservation Evoker)
    full    = { 0.45, 1.00, 0.80 },  -- vert brillant quand max
    burst   = { 1.00, 1.00, 1.00 },  -- blanc : Essence Burst proc (369299)
  },
  -- Arcane Charges (Mage Arcane)
  ARCANE_CHARGES = {
    default = { 0.55, 0.25, 0.90 },  -- violet arcanique
    full    = { 0.65, 0.35, 1.00 },  -- violet brillant quand 4/4
  },
  -- Coeur Démoniaque (Warlock Démonologie, specID 265)
  DEMONIC_CORE = {
    default = { 0.55, 0.22, 0.85 },  -- violet infernal
    full    = { 0.80, 0.45, 1.00 },  -- violet brillant quand 2/2
  },
}
local SEC_DIM = 0.25  -- alpha quand vide/en cd

-- Detecte le type de secondary dots selon la classe/forme
function ResourceCircle.DetectSecondaryDots()
  local _, playerClass = UnitClass("player")
  local newType = nil
  local newCount = 0

  if playerClass == "DEATHKNIGHT" then
    newType = "RUNES"
    newCount = 6
  elseif playerClass == "ROGUE" then
    newType = "COMBO_ROGUE"
    local maxCP = UnitPowerMax("player", Enum.PowerType.ComboPoints)
    newCount = (maxCP and maxCP > 0) and maxCP or 5
  elseif playerClass == "DRUID" then
    local formID = GetShapeshiftFormID()
    if formID == DRUID_CAT_FORM then
      newType = "COMBO_DRUID"
      local maxCP = UnitPowerMax("player", Enum.PowerType.ComboPoints)
      newCount = (maxCP and maxCP > 0) and maxCP or 5
    end
  elseif playerClass == "MONK" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    if specID == 269 then  -- Windwalker
      newType = "CHI"
      local maxChi = UnitPowerMax("player", Enum.PowerType.Chi)
      newCount = (maxChi and maxChi > 0) and maxChi or 5
    end
  elseif playerClass == "PALADIN" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    local cfg = ns.GetCfg("resourceCircle")
    local holyPowerAllSpecs = cfg and cfg.holyPowerAllSpecs
    if specID == 65 or (holyPowerAllSpecs and (specID == 66 or specID == 70)) then
      newType = "HOLY_POWER"
      local maxHP = UnitPowerMax("player", Enum.PowerType.HolyPower)
      newCount = (maxHP and maxHP > 0) and maxHP or 5
    end
  elseif playerClass == "EVOKER" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    local cfg = ns.GetCfg("resourceCircle")
    local essenceAllSpecs = cfg and cfg.essenceAllSpecs
    if specID == 1468 or (essenceAllSpecs and (specID == 1473 or specID == 1467)) then
      newType = "ESSENCE"
      local maxEss = UnitPowerMax("player", Enum.PowerType.Essence)
      newCount = (maxEss and maxEss > 0) and maxEss or 6
    end
  elseif playerClass == "MAGE" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    if specID == 62 then  -- Arcane
      newType = "ARCANE_CHARGES"
      newCount = 4
    end
  elseif playerClass == "WARLOCK" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    if specID == 265 then  -- Demonology
      newType  = "DEMONIC_CORE"
      newCount = 4
    end
  end

  -- Si le type/count n'a pas change, ne rien faire
  if newType == secDotType and newCount == secDotCount then return end

  -- Nettoyer l'ancien ticker
  if secUpdateTicker then secUpdateTicker:Cancel(); secUpdateTicker = nil end

  -- Cacher les anciens dots en surplus et réinitialiser leur anim
  for i = 1, #secDots do
    if secDots[i] then
      secDots[i]:Hide()
      secDots[i]:SetAlpha(0)
      if secDotAnims[i] then
        secDotAnims[i].progress = 0
        secDotAnims[i].target   = 0
      end
    end
  end

  secDotType = newType
  secDotCount = newCount

  if not secDotType or secDotCount == 0 then return end

  -- Creer ou recycler les frames (réinitialise l'état d'animation)
  ResourceCircle.EnsureSecDotFrames(secDotCount)
  -- Positionner
  ResourceCircle.LayoutSecDots()
  -- Couleurs
  ResourceCircle.UpdateSecDotColors()
  -- Ticker pour le fill + ciblage des animations
  secUpdateTicker = C_Timer.NewTicker(0.016, function()
    ResourceCircle.UpdateSecDots()
  end)
end

-- Cree les frames secondary dot si necessaire (recycler)
function ResourceCircle.EnsureSecDotFrames(count)
  if not bar then return end
  for i = 1, count do
    if not secDots[i] then
      local f = CreateFrame("Frame", "AishCoreSecDot" .. i, bar)
      -- Doit etre au-dessus de overlayFrame : meme niveau que textFrame
      if bar.textFrame then f:SetFrameLevel(bar.textFrame:GetFrameLevel()) end
      -- Fond sombre
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetTexture(SEC_DOT_TEX)
      bg:SetAllPoints()
      bg:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
      f.bg = bg
      -- Fill (même texture Circle_Smooth que le Skyriding)
      local fill = f:CreateTexture(nil, "ARTWORK")
      fill:SetTexture(SEC_DOT_TEX)
      fill:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
      f.fill = fill
      -- Bordure subtile
      local border = f:CreateTexture(nil, "OVERLAY")
      border:SetTexture(SEC_DOT_TEX)
      border:SetAllPoints()
      border:SetVertexColor(0.3, 0.3, 0.3, 0.3)
      f.border = border
      f.fillPct = 0
      f._homeX = 0
      f._homeY = 0
      secDots[i] = f
    end
    -- Initialiser / réinitialiser l'état d'animation
    secDotAnims[i] = secDotAnims[i] or {}
    secDotAnims[i].progress = 0
    secDotAnims[i].target   = 0
    -- Masquer pour que le slide-in parte de zéro
    secDots[i]:SetAlpha(0)
    secDots[i]:Hide()
  end
end

-- Positionne les secondary dots en arc autour du cercle
function ResourceCircle.LayoutSecDots()
  if not bar or secDotCount == 0 then return end
  local cfg = ns.GetCfg("resourceCircle")
  local size = cfg.size
  -- Lecture avec fallback per-dotType → global (Feature 5)
  local pfx = secDotType and ("secondaryDots_" .. secDotType .. "_") or ""
  local function pv(k, fallback) local v = pfx ~= "" and cfg[pfx..k] or nil; return v ~= nil and v or cfg[fallback] end
  local dotSize    = size * (pv("size",     "secondaryDotsSize")     or 0.16)
  local radius     = size * (pv("radius",   "secondaryDotsRadius")   or 0.62)
  local centerAngle =       (pv("rotation", "secondaryDotsRotation") or 90)
  local spread     =         pv("spread",   "secondaryDotsSpread")   or 24
  local revKey     = pfx ~= "" and cfg[pfx.."reversed"]
  local reversed   = revKey ~= nil and revKey or cfg.secondaryDotsReversed

  for i = 1, secDotCount do
    local f = secDots[i]
    if f then
      -- Calculer l'angle : centre +/- spread (inversé si option active)
      local idx = reversed and (secDotCount + 1 - i) or i
      local offset = (idx - (secDotCount + 1) / 2) * spread
      local angle = math.rad(centerAngle + offset)
      local rx = math.cos(angle) * radius
      local ry = math.sin(angle) * radius

      -- Mémoriser la position "home" pour l'animation slide
      f._homeX = rx
      f._homeY = ry

      f:SetSize(dotSize, dotSize)
      f:ClearAllPoints()
      f:SetPoint("CENTER", bar, "CENTER", rx, ry)
      f.fill:SetSize(dotSize, dotSize)
    end
  end
end

-- Met a jour les couleurs des secondary dots
function ResourceCircle.UpdateSecDotColors()
  if secDotCount == 0 then return end
  local color
  if secDotType == "RUNES" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    color = SEC_COLORS.RUNES[specID] or SEC_COLORS.RUNES.default
  elseif secDotType == "COMBO_ROGUE" then
    color = SEC_COLORS.COMBO_ROGUE.default
  elseif secDotType == "COMBO_DRUID" then
    color = SEC_COLORS.COMBO_DRUID.default
  elseif secDotType == "CHI" then
    color = SEC_COLORS.CHI.default
  elseif secDotType == "HOLY_POWER" then
    color = SEC_COLORS.HOLY_POWER.default
  elseif secDotType == "ESSENCE" then
    color = SEC_COLORS.ESSENCE.default
  elseif secDotType == "ARCANE_CHARGES" then
    color = SEC_COLORS.ARCANE_CHARGES.default
  elseif secDotType == "DEMONIC_CORE" then
    color = SEC_COLORS.DEMONIC_CORE.default
  else
    color = { 1, 1, 1 }
  end
  -- Override couleur globes (SpellEffects peut imposer une couleur par condition)
  local activeColor = _secDotColorOverride or color
  for i = 1, secDotCount do
    local f = secDots[i]
    if f and f.fill then
      f.fill:SetVertexColor(activeColor[1], activeColor[2], activeColor[3], 1)
      f._baseColor = color
    end
  end
end

--- Override la couleur des globes secondaires (imposé par SpellEffects selon la condition active).
--- Appeler avec nil pour retirer l'override.
function ResourceCircle.SetSecDotColorOverride(r, g, b)
  _secDotColorOverride = (r and { r, g, b }) or nil
  ResourceCircle.UpdateSecDotColors()
end

function ResourceCircle.ClearSecDotColorOverride()
  _secDotColorOverride = nil
  ResourceCircle.UpdateSecDotColors()
end

--- Retourne true si le proc Essence Burst est actif (Evoker Preservation).
function ResourceCircle.IsEssenceBurstActive()
  return essenceBurstActive == true
end

--- Retourne le nombre de Coeurs Démoniaques actifs (Warlock Démonologie, 0-2).
function ResourceCircle.GetDemonicCoreStacks()
  return demonicCoreStacks
end

-- Met a jour le fill des secondary dots (et les cibles d'animation slide)
function ResourceCircle.UpdateSecDots()
  if secDotCount == 0 then return end
  if previewMode then return end -- ne pas écraser les valeurs forcées par SetPreview
  -- Ne pas piloter les cibles quand le cercle est en cours de disparition
  local circleVisible = (lastVisibilityState == true)

  if secDotType == "RUNES" then
    local now = GetTime()
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        local start, duration, runeReady = GetRuneCooldown(i)
        local pct
        if runeReady then
          pct = 1
        elseif start and duration and duration > 0 then
          pct = math.min((now - start) / duration, 1)
        else
          pct = 1
        end
        -- Les runes sont toujours "présentes" (slide-in dès que la case existe)
        if circleVisible then oa.target = 1 end
        local fullSize = f:GetHeight()
        if fullSize > 0 then
          f.fill:SetHeight(math.max(fullSize * pct, 0.01))
        end
        f.fill:SetAlpha(pct >= 1 and 1 or (SEC_DIM + (1 - SEC_DIM) * pct))
      end
    end

  elseif secDotType == "COMBO_ROGUE" or secDotType == "COMBO_DRUID" then
    local ok, cp = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if not ok then cp = 0 end
    local maxCP = secDotCount
    local palette = SEC_COLORS[secDotType]
    local comboColor = _secDotColorOverride or palette.default
    local fullColor  = _secDotColorOverride or palette.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= cp then
          -- Slide-in : piloter la cible de l'animation
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if cp >= maxCP then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(comboColor[1], comboColor[2], comboColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end

  elseif secDotType == "CHI" then
    local ok, chi = pcall(UnitPower, "player", Enum.PowerType.Chi)
    if not ok then chi = 0 end
    local maxChi = secDotCount
    local chiColor  = _secDotColorOverride or SEC_COLORS.CHI.default
    local fullColor = _secDotColorOverride or SEC_COLORS.CHI.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= chi then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if chi >= maxChi then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(chiColor[1], chiColor[2], chiColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end

  elseif secDotType == "HOLY_POWER" then
    local ok, hp = pcall(UnitPower, "player", Enum.PowerType.HolyPower)
    if not ok then hp = 0 end
    local maxHP = secDotCount
    local CLR = ns.Modules.Colors
    local defaultColor = _secDotColorOverride or SEC_COLORS.HOLY_POWER.default
    local dotsA = _secDotColorOverride or (CLR and CLR.Get("powerdotsa")) or SEC_COLORS.HOLY_POWER.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= hp then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if hp >= maxHP then
            f.fill:SetVertexColor(dotsA[1], dotsA[2], dotsA[3], 1)
          else
            f.fill:SetVertexColor(defaultColor[1], defaultColor[2], defaultColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end

  elseif secDotType == "ESSENCE" then
    local ok, ess = pcall(UnitPower, "player", Enum.PowerType.Essence)
    if not ok then ess = 0 end
    local maxEss = secDotCount
    local defaultColor = _secDotColorOverride or SEC_COLORS.ESSENCE.default
    local fullColor    = _secDotColorOverride or SEC_COLORS.ESSENCE.full
    local CLR = ns.Modules.Colors
    local burstColor = _secDotColorOverride or (CLR and CLR.Get("powertext")) or SEC_COLORS.ESSENCE.burst
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= ess then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if essenceBurstActive then
            f.fill:SetVertexColor(burstColor[1], burstColor[2], burstColor[3], 1)
          elseif ess >= maxEss then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defaultColor[1], defaultColor[2], defaultColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end
  elseif secDotType == "ARCANE_CHARGES" then
    local ok, ac = pcall(UnitPower, "player", Enum.PowerType.ArcaneCharges)
    if not ok then ac = 0 end
    local maxAC     = secDotCount
    local defColor  = _secDotColorOverride or SEC_COLORS.ARCANE_CHARGES.default
    local fullColor = _secDotColorOverride or SEC_COLORS.ARCANE_CHARGES.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= ac then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if ac >= maxAC then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end
  elseif secDotType == "DEMONIC_CORE" then
    -- Priorité : stacks du buff 264173 ; fallback : glow Demonbolt si buff indisponible
    local stacks = 0
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 264173)
    if ok and auraData then
      stacks = (auraData.applications or 0)
      if stacks == 0 then stacks = 1 end  -- aura présente = au moins 1 charge
    elseif demonicCoreOverlayActive then
      stacks = 1
    end
    demonicCoreStacks = stacks
    local defColor  = _secDotColorOverride or SEC_COLORS.DEMONIC_CORE.default
    local fullColor = _secDotColorOverride or SEC_COLORS.DEMONIC_CORE.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= stacks then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if stacks >= secDotCount then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end
  end
end

-- Alias pour compatibilite
function ResourceCircle.UpdateRuneColors()
  ResourceCircle.UpdateSecDotColors()
end

---------------------------------------------------------------------------
-- Ressource secondaire : texte sous le cercle (Bone Shield, Soul Fragments…)
---------------------------------------------------------------------------

-- Couleurs par défaut de l'arc de durée central (cf. CENTER_ARC_SPELLS dans
-- CenterArc.lua et _arcSpec dans SettingsPanel.lua — dupliqué ici volontairement,
-- même convention que ces deux fichiers, pour éviter un couplage cross-module).
local ARC_DEFAULT_COLORS = {
  [66]  = { 1.00, 0.88, 0.10 },  -- Paladin Prot : Consécration
  [73]  = { 0.78, 0.25, 0.25 },  -- Guerrier Prot : Dur au mal
  [250] = { 0.20, 0.78, 0.35 },  -- DK Sang : Death's Due (188290)
}

-- Couleur courante de l'arc de durée pour une spec donnée : priorité à
-- l'override utilisateur (color picker, cf. SettingsPanel.lua), sinon couleur
-- par défaut de la spec. Utilisé pour aligner la couleur du texte de ressource
-- secondaire sur celle de l'arc quand les deux représentent la même ressource
-- (ex: Dur au mal, texte + arc).
local function GetDurationArcColor(specID)
  local r = ns.GetSecResCfg("durationArcColorR", specID)
  if r then
    return { r, ns.GetSecResCfg("durationArcColorG", specID) or 1, ns.GetSecResCfg("durationArcColorB", specID) or 1, 1 }
  end
  return ARC_DEFAULT_COLORS[specID]
end

-- Réapplique UNIQUEMENT la géométrie dépendante de la spec active (taille de
-- l'arc de durée, taille/police/déco/offset du texte de ressource secondaire
-- -- cf. ns.GetSecResCfg dans Core.lua) : volontairement séparée
-- d'ApplySettings() (qui touche bien plus : position/taille du cercle, glow,
-- dots, stagger, ET réinitialise lastVisibilityState) pour ne JAMAIS
-- interférer avec la visibilité combat/hors-combat du cercle. Appelée à la
-- fois par ApplySettings() (changement via un slider du panneau d'options) et
-- par DetectSecondaryResource (login + changement de spec) -- sans ce second
-- appel, la personnalisation d'une spec restait "collée" à la géométrie de la
-- toute première spec détectée (avant que ns._specID soit résolu) jusqu'à ce
-- qu'on retouche manuellement un slider (confirmé en jeu).
-- specID optionnel : si omis, retombe sur ns._specID (cf. ns.GetSecResCfg dans
-- Core.lua) -- mais DetectSecondaryResource passe TOUJOURS son specID
-- fraîchement résolu (via GetSpecializationInfo, pas le cache global) pour
-- garantir que la géométrie lue correspond bien à la spec dont le secResDef
-- vient d'être choisi, même si ns._specID n'a pas encore été mis à jour à cet
-- instant précis (CONFIRMÉ EN JEU : sans ce paramètre explicite, les réglages
-- perso restaient invisibles car lus sous la mauvaise clé de spec).
function ResourceCircle.RefreshSecResSpecGeometry(specID)
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)

  if bar.durationArc then
    local durArcPx = arcPx * (ns.GetSecResCfg("durationArcRatio", specID) or DURATION_ARC_RATIO)
    bar.durationArc:SetSize(durArcPx, durArcPx * ARC_CROP_H)
    bar.durationArc:ClearAllPoints()
    bar.durationArc:SetPoint("TOP", bar, "CENTER", 0, durArcPx / 2)
    if bar.durationOvl then
      local durOvPx = durArcPx * (ns.GetSecResCfg("durationArcOverlayRatio", specID) or DURATION_ARC_OVL_RATIO)
      if durOvPx >= 2 then bar.durationOvl:SetSize(durOvPx, durOvPx) end
    end
  end

  local secResTextSize = ns.GetSecResCfg("secResTextSize", specID) or 11
  if bar.secResText then
    bar.secResText:SetFont(ns.GetSecResCfg("secResFont", specID) or FONT_BOLD_ITALIC, secResTextSize, "")
    -- Police de la déco : indépendante (secResDecoFont), reprend secResFont si non définie.
    local decoFont = ns.GetSecResCfg("secResDecoFont", specID) or ns.GetSecResCfg("secResFont", specID) or FONT_BOLD_ITALIC
    if bar.secResDashL then bar.secResDashL:SetFont(decoFont, secResTextSize, "") end
    if bar.secResDashR then bar.secResDashR:SetFont(decoFont, secResTextSize, "") end
  end
  if bar.secResFrame and bar.text then
    local secResOffX = ns.GetSecResCfg("secResTextOffsetX", specID) or 0
    local secResOffY = ns.GetSecResCfg("secResTextOffsetY", specID) or -2
    bar.secResFrame:ClearAllPoints()
    bar.secResFrame:SetPoint("TOP", bar.text, "BOTTOM", secResOffX, secResOffY)
    RecordHome(bar.secResFrame, "TOP", bar.text, "BOTTOM", secResOffX, secResOffY, 120, 18)
  end
  RefreshSecResDeco(specID)
end

-- Détecte la ressource secondaire selon la spec active et démarre le ticker
function ResourceCircle.DetectSecondaryResource()
  if not bar then return end

  -- Arrêter l'ancien ticker
  if secResUpdateTicker then secResUpdateTicker:Cancel(); secResUpdateTicker = nil end
  secResDef = nil

  -- Désabonner l'ancien canal clone-stack (spec précédente) avant d'en choisir
  -- un nouveau -- sinon un vieux spellID resterait abonné indéfiniment.
  if _secResStackSubIDs and ns.Auras and ns.Auras.UnsubscribeCDMAuraStack then
    for _, sid in ipairs(_secResStackSubIDs) do
      ns.Auras.UnsubscribeCDMAuraStack(sid, "resourceCircleSecRes")
    end
  end
  _secResStackSubIDs = nil

  -- Cacher le texte de ressource secondaire
  SetSecResShown(false)

  if not ns.SecondaryResourceDefs then return end

  -- Résoudre le specID courant
  local specID = nil
  if GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local ok, sid = pcall(GetSpecializationInfo, idx)
      if ok and sid and sid > 0 then specID = sid end
    end
  end
  if not specID then return end

  local def = ns.SecondaryResourceDefs[specID]
  if not def then return end

  secResDef = def

  -- Abonner bar.secResText au canal clone-stack (CDMHooks.lua) pour les
  -- ressources à stacks : même mécanisme event-driven/combat-safe que les
  -- stacks d'icônes (Debuffs.lua/ApplyStackCharges), qui retransmet
  -- cdmAura.applications tel quel dès que le CDM voit l'aura -- CONFIRMÉ EN
  -- JEU (2026-08-16, /rcsecres) : Bouclier d'os (195181) a un instID CDM
  -- valide, mais GetAuraApplicationDisplayCount dessus lève "tainted by
  -- AishCore", ET GetPlayerAuraBySpellID renvoie hasAura=false -- les 3 tiers
  -- de ApplyStacksToText échouent tous en combat, alors que le canal clone
  -- swipe/stack (déjà éprouvé pour Dur Au Mal) reste alimenté. On abonne à la
  -- fois spellID et altSpellID (si défini) : le texte reçu est appliqué tel
  -- quel par PushStackApplications, sans jamais transiter par notre code.
  if def.useStacks and def.spellID and ns.Auras and ns.Auras.SubscribeCDMAuraStack then
    _secResStackSubIDs = { def.spellID }
    ns.Auras.SubscribeCDMAuraStack(def.spellID, "resourceCircleSecRes", bar.secResText)
    if def.altSpellID then
      _secResStackSubIDs[#_secResStackSubIDs + 1] = def.altSpellID
      ns.Auras.SubscribeCDMAuraStack(def.altSpellID, "resourceCircleSecRes", bar.secResText)
    end
    -- Empeche le blacklistage croise par le tracker d'auras generique
    -- (Modules/Auras/Features/Auras/Debuffs.lua, ApplyStackCharges) : SI ce
    -- meme spellID est AUSSI dans la liste des auras trackees par l'utilisateur
    -- (ex: Fragments d'ame/de vide ajoutes a une liste d'icones), son scan
    -- normal hors combat trouve TOUJOURS stacks=0 pour ces spellID (leur vrai
    -- effet est "Set Action Button Spell Count", pas une aura lisible via
    -- GetPlayerAuraBySpellID/enumeration -- cf. commentaire ResourceMap.lua) et
    -- appelle ns.MarkStackNotCapable(spellID), qui bloque ensuite
    -- PushStackApplications EN PERMANENCE (CDMHooks.lua) -- meme canal que
    -- celui utilise ici pour bar.secResText. Correspond au bug rapporte :
    -- Fragments d'ame (Vengeance) et Fragments de vide (Devoreur) ne
    -- s'affichaient plus du tout (mais l'arc, CenterArc.lua, canal
    -- independant, restait fonctionnel) -- symptome exactement coherent avec
    -- ce blacklistage croise si ces sorts sont aussi trackes comme icones. On
    -- marque donc ces spellID "stack capable" nous-memes des l'init :
    -- ns.MarkStackCapable efface aussi tout blacklistage deja pose.
    if ns.Auras.MarkStackCapable then
      ns.Auras.MarkStackCapable(def.spellID)
      if def.altSpellID then ns.Auras.MarkStackCapable(def.altSpellID) end
    end
  end

  -- Appliquer la couleur du texte secondaire :
  -- si la ressource est celle trackée par l'arc de durée central (ex: absorb de
  -- Dur au mal), on aligne sur la couleur de cet arc plutôt que def.color, pour
  -- que texte et arc restent visuellement cohérents (même donnée affichée deux
  -- fois). Sinon : def.color (ex: Soul Fragments), sinon couleur powerdotsb.
  if bar.secResText then
    local CLR = ns.Modules.Colors
    local c = (def.useAbsorb and GetDurationArcColor(specID)) or def.color or (CLR and CLR.Get("powerdotsb"))
    if c then
      bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
  end

  -- Démarrer le ticker de mise à jour (0.1s suffit pour ce type de ressource)
  secResUpdateTicker = C_Timer.NewTicker(0.1, function()
    ResourceCircle.UpdateSecondaryResource()
  end)

  -- Réapplique la géométrie dépendante de la spec (cf. RefreshSecResSpecGeometry
  -- plus haut) SANS passer par ApplySettings() au complet : celle-ci
  -- réinitialiserait lastVisibilityState et perturberait la visibilité
  -- combat/hors-combat du cercle (confirmé en jeu). specID (fraîchement résolu
  -- ci-dessus, PAS ns._specID) passé explicitement : garantit qu'on lit la
  -- config de la MÊME spec que celle dont on vient de choisir secResDef.
  ResourceCircle.RefreshSecResSpecGeometry(specID)
end

-- GetPlayerAuraBySpellID() s'est avéré peu fiable pour certaines auras (renvoie
-- nil par intermittence alors que l'aura est bien active — cf. rapport en jeu).
-- Le système de tracking d'auras de l'addon a déjà résolu exactement ce problème
-- en passant en CDM-only (cf. le gros commentaire en tête de
-- Modules/Auras/Core/Scan.lua) : ns.Auras.cdmData est la SOURCE UNIQUE DE VÉRITÉ,
-- alimentée directement par les hooks Blizzard SetAuraInstanceInfo — combat-safe
-- et toujours à jour. On réutilise cette même source plutôt que de réinventer
-- une détection.
-- La signature réelle est GetAuraApplicationDisplayCount(instID, min, max) --
-- SANS paramètre "unit" (confirmé en jeu, patch 12.1 : un appel avec "unit"
-- en argument #1 lève "bad argument #1", masqué avant par l'erreur de taint
-- dès que instID est lui-même secret). ns.Auras.SafeStacks et tous les sites
-- de ce fichier ont été corrigés en conséquence.
--
-- IMPORTANT (confirmé en jeu) : la valeur renvoyée par GetAuraApplicationDisplayCount
-- peut elle-même être secrète en combat pour un sort CDM (SafeStacks le vérifie
-- déjà via issecretvalue). tostring()/le débogueur Blizzard peuvent l'afficher
-- ("4"), mais tonumber() dessus renvoie nil silencieusement, et même
-- FontString:SetFormattedText("- %d -", valeur_secrète) échoue (testé en jeu) :
-- ce n'est donc PAS un sink reconnu par Blizzard pour ce type de valeur.
--
-- Correction : même la comparaison (candidat par candidat, technique
-- CleanInt/SecretToNumber de PriorityBar.lua) ne permet PAS de "deviner" une
-- valeur secrète — cette technique sert seulement à DÉTECTER qu'une valeur
-- est secrète (la comparaison plante alors pour CHAQUE candidat) et à
-- abandonner proprement, jamais à en extraire le nombre réel.
--
-- La bonne approche est celle déjà utilisée — avec succès — par le badge de
-- stack sur l'icône (_SetStackText dans Debuffs.lua) : passer la valeur
-- BRUTE, telle quelle, en SEUL argument de FontString:SetText, sans aucune
-- opération dessus (pas de concat, pas de format, pas de comparaison) — le
-- vrai pattern "show but don't know". On perd juste la décoration "- N -"
-- (impossible à construire sur une valeur secrète), le nombre s'affiche seul.
-- IMPORTANT (confirmé en jeu) : cdmData n'est JAMAIS nettoyé (aucune suppression
-- d'entrée nulle part dans CDMHooks.lua) — les instanceID d'auras disparues
-- restent indéfiniment. Après un 2e combat, il existe donc PLUSIEURS entrées
-- pour le même spellID (l'ancienne instance, invalide, + la nouvelle). Il ne
-- faut donc jamais s'arrêter sur la première correspondance trouvée : on
-- continue d'essayer les autres tant qu'aucune n'a réellement fonctionné.
-- Pop (fade + slide) sur bar.secResFrame quand on passe de 0 à 1+ stack EN
-- COMBAT (pas seulement à l'entrée en combat, cf. CIRCLE_ANIM.secResText plus
-- haut qui gère déjà l'entrée/sortie de combat elle-même). Détecté via
-- `applied` (un simple booléen : "ApplyStacksToText a trouvé une valeur
-- affichable"), jamais via la vraie valeur des stacks — donc aucun souci de
-- valeur secrète ici, juste un changement d'état plain Lua.
-- Durée dédiée (indépendante de CIRCLE_ANIM.secResText.show.duration, qui reste
-- utilisée telle quelle pour l'animation d'entrée/sortie de combat) : ce pop
-- se déclenche bien plus souvent (à chaque transition 0->1+ stack en combat),
-- donc réglable séparément sans toucher à l'entrée en combat.
local SEC_RES_POP_DURATION = 0.3
local _secResWasApplied = false
local _secResPopTicker  = nil
local function StartSecResPop()
  if not bar or not bar.secResFrame then return end
  if _secResPopTicker then _secResPopTicker:Cancel(); _secResPopTicker = nil end
  local spec  = CIRCLE_ANIM.secResText.show
  local home  = _elemHome[bar.secResFrame]
  local start = GetTime()
  bar.secResFrame:SetAlpha(0)
  _secResPopTicker = C_Timer.NewTicker(0.016, function()
    local t = math.min((GetTime() - start) / SEC_RES_POP_DURATION, 1)
    local eased = ns.Ease(spec.ease, spec.easeType, t)
    bar.secResFrame:SetAlpha(eased)
    if home then
      bar.secResFrame:ClearAllPoints()
      bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint,
        home.x, home.y + (spec.slideY or 0) * (1 - eased))
    end
    if t >= 1 then
      _secResPopTicker:Cancel(); _secResPopTicker = nil
    end
  end)
end

-- Symétrique de StartSecResPop : transition 1+ -> 0 stack en combat. Fade+slide
-- vers l'état "hide" (cf. CIRCLE_ANIM.secResText.hide), puis cache réellement
-- le texte/déco (SetSecResShown(false)) une fois le fondu terminé — pas avant,
-- sinon il n'y aurait rien à voir disparaître.
local function StartSecResPopOut()
  if not bar or not bar.secResFrame then return end
  if _secResPopTicker then _secResPopTicker:Cancel(); _secResPopTicker = nil end
  local spec  = CIRCLE_ANIM.secResText.hide
  local home  = _elemHome[bar.secResFrame]
  local start = GetTime()
  _secResPopTicker = C_Timer.NewTicker(0.016, function()
    local t = math.min((GetTime() - start) / SEC_RES_POP_DURATION, 1)
    local eased = ns.Ease(spec.ease, spec.easeType, t)
    bar.secResFrame:SetAlpha(1 - eased)
    if home then
      bar.secResFrame:ClearAllPoints()
      bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint,
        home.x, home.y + (spec.slideY or 0) * eased)
    end
    if t >= 1 then
      _secResPopTicker:Cancel(); _secResPopTicker = nil
      SetSecResShown(false)
      -- Remettre à l'état de repos pour que le prochain pop-in reparte propre.
      bar.secResFrame:SetAlpha(1)
      if home then
        bar.secResFrame:ClearAllPoints()
        bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint, home.x, home.y)
      end
    end
  end)
end

-- Teste val == 0 sans jamais planter si val est une secret value (comparaison
-- directe interdite en combat sur ce type de valeur). Si la comparaison
-- échoue (secret), on ne peut pas savoir -> on considère "pas confirmé zéro"
-- et on affiche quand même (comportement sûr par défaut). Même helper que
-- ApplyStackToText dans PriorityBar.lua.
local function IsConfirmedZero(val)
  if val == nil then return false end
  local ok, isZero = pcall(function() return val == 0 end)
  return ok and isZero == true
end

-- IMPORTANT : certaines "ressources secondaires" ne sont PAS de vraies auras
-- stackables, ou ne sont pas trouvables par tous les moyens Blizzard. Quatre
-- chemins possibles, essayés dans l'ordre :
--   1) Vraie aura stackable, vue par le CDM Blizzard (Bone Shield/Soul
--      Fragments) -> ns.Auras.cdmData (combat-safe).
--   2) GetPlayerAuraBySpellID -- rapide, mais CONFIRMÉ EN JEU peu fiable pour
--      certaines auras (renvoie nil alors que l'aura est bien active avec des
--      stacks > 0 -- cas vérifié pour Thé de Mana/115867). On tente quand
--      même en premier (coût nul), l'énumération ci-dessous rattrape l'échec.
--   3) Énumération complète des auras HELPFUL du joueur via
--      C_UnitAuras.GetAuraDataByIndex -- CONFIRMÉ EN JEU comme étant la seule
--      méthode qui trouve effectivement Thé de Mana avec son vrai compte de
--      stacks (2), là où cdmData et GetPlayerAuraBySpellID échouaient tous
--      les deux. Plus coûteux (boucle), donc uniquement en dernier recours
--      après l'échec des deux méthodes ci-dessus.
--   4) AUCUNE aura du tout : un simple compteur natif Blizzard affiché sur le
--      bouton d'action (C_Spell.GetSpellCastCount), sans buff associé —
--      confirmé en jeu pour une autre mécanique Mistweaver (Don de Sheilun,
--      cf. STACK_SPELLS/ApplyStackToText dans PriorityBar.lua).
-- Dans tous les cas, la valeur est transmise TELLE QUELLE à SetText (jamais
-- de tonumber/format/comparaison dessus, potentiellement secrète en combat).
-- dbg (optionnel) : table de diagnostic remplie en direct par /rcsecres pour
-- savoir EXACTEMENT quel chemin a repondu quoi, sans avoir a deviner. N'a
-- aucun effet sur le comportement normal (nil partout ailleurs).
-- sink(value) : callback qui tente de "consommer" value (secret-safe : jamais
-- de retour/comparaison dessus a l'interieur, juste transmise BRUTE) et
-- renvoie true/false selon si l'appel a reussi. Factorise pour etre reutilise
-- par 2 consommateurs differents : FontString:SetText (texte de ressource
-- secondaire, ApplyStacksToText ci-dessous) ET StatusBar:SetValue (arc
-- secondaire, ApplyStacksToCenterArc plus bas, utilise par CenterArc.lua) --
-- CONFIRME EN JEU : l'arc du DH Devoreur restait vide alors que le texte
-- s'affichait correctement pour le MEME spellID, parce que CenterArc.lua
-- avait sa propre version dupliquee qui ne cherchait QUE dans cdmData (tier 1),
-- jamais dans les fallbacks 1/2 ci-dessous -- exactement le tier qui trouve
-- effectivement cette aura dans ce cas. Une seule implementation partagee
-- élimine ce genre de divergence silencieuse a l'avenir.
local function ApplyStacksTo(sink, spellID, dbg)
  local A = ns.Auras
  local cdmPlayer = A and A.cdmData and A.cdmData.player
  local cdmEntry = cdmPlayer and cdmPlayer[spellID]
  if cdmEntry and cdmEntry.instID then
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if dbg then dbg.cdm = { ok = ok, disp = disp } end
    if ok and disp ~= nil and not IsConfirmedZero(disp) then
      if sink(disp) then if dbg then dbg.path = "cdm" end; return true end
    end
    -- Instance périmée : on tombe dans les fallbacks ci-dessous plutôt que d'abandonner.
  end

  -- Fallback 1 : GetPlayerAuraBySpellID (aura jamais vue par le CDM Blizzard)
  local okAura, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
  if dbg then dbg.f1 = { okAura = okAura, hasAura = (aura ~= nil), instID = aura and aura.auraInstanceID } end
  if okAura and aura then
    -- aura.applications d'ABORD (donnée directe, pas de 2e appel API) --
    -- CONFIRMÉ EN JEU (Glaçons/205473) : GetAuraApplicationDisplayCount sur
    -- l'auraInstanceID peut renvoyer ok=true val=nil pour une aura pourtant
    -- bien présente avec un vrai compte de stacks lisible via applications
    -- (5 confirmé). Ne jamais sauter applications pour aller direct à
    -- l'instanceID : c'était l'inverse ici, contrairement à
    -- GetPlayerAuraStackCount (ResourceMap.lua), qui, lui, essayait déjà
    -- applications en premier -- divergence silencieuse entre les 2 chemins.
    local okApp, app = pcall(function() return aura.applications end)
    if dbg then dbg.f1.okApp = okApp; dbg.f1.app = app end
    if okApp and app ~= nil and not IsConfirmedZero(app) then
      if sink(app) then if dbg then dbg.path = "fallback1-applications" end; return true end
    end
    if aura.auraInstanceID then
      local ok2, disp2 = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, aura.auraInstanceID, 1, 999)
      if dbg then dbg.f1.ok2 = ok2; dbg.f1.disp2 = disp2 end
      if ok2 and disp2 ~= nil and not IsConfirmedZero(disp2) then
        if sink(disp2) then if dbg then dbg.path = "fallback1-displaycount" end; return true end
      end
    end
  end

  -- Fallback 2 : énumération des auras HELPFUL (rattrape l'échec de
  -- GetPlayerAuraBySpellID). CONFIRMÉ EN JEU (erreur reproduite) : d.spellId
  -- sur l'AuraData renvoyée par GetAuraDataByIndex devient un SECRET NUMBER
  -- dès qu'on est en combat -- le comparer directement (d.spellId == spellID)
  -- PLANTE alors l'exécution ("attempt to compare... a secret number value"),
  -- contrairement à cdmEntry.spellId (copie mise en cache par l'addon, jamais
  -- secrète). Cette comparaison est donc protégée par pcall : en combat elle
  -- échoue proprement (okMatch=false, on passe à l'entrée suivante) plutôt que
  -- de planter toute la fonction (et empêcher SetSecResShown avec) -- mais ça
  -- veut aussi dire que ce fallback ne peut identifier l'aura QUE hors combat.
  -- d.applications est protégé de la même façon (même famille de champs).
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 60 do
      local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      -- ok3=false = CETTE position est secrète, pas "fin de liste" -- ne pas
      -- break, continuer vers la position suivante (confirmé en jeu : une
      -- énumération qui break au 1er échec ratait tout ce qui suivait).
      if ok3 and not d then break end
      if ok3 and d then
      local okMatch, isMatch = pcall(function() return d.spellId == spellID end)
      if dbg and not okMatch then dbg.f2MatchErrAt = dbg.f2MatchErrAt or i end
      if okMatch and isMatch then
        local okApp, disp3 = pcall(function() return d.applications end)
        if dbg then dbg.f2 = { matchedAt = i, okApp = okApp, disp3 = disp3 } end
        if okApp and disp3 ~= nil and not IsConfirmedZero(disp3) then
          if sink(disp3) then if dbg then dbg.path = "fallback2-applications" end; return true end
        end
        -- applications absent/0 confirmé : essaie quand même via
        -- auraInstanceID (sink combat-safe dédié, jamais secret lui-même).
        local okInstID, instID = pcall(function() return d.auraInstanceID end)
        if okInstID and instID then
          local okIdx, dispIdx = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, instID, 1, 999)
          if dbg then dbg.f2.okIdx = okIdx; dbg.f2.dispIdx = dispIdx end
          if okIdx and dispIdx ~= nil and not IsConfirmedZero(dispIdx) then
            if sink(dispIdx) then if dbg then dbg.path = "fallback2-instanceid" end; return true end
          end
        end
      end
      end
    end
  end

  -- PAS de fallback GetSpellCastCount ici, contrairement à ApplyStackToText
  -- dans PriorityBar.lua : CONFIRMÉ EN JEU que cette API répond ok=true
  -- count=0 quand on l'appelle avec le spellID d'un BUFF (ex: 115867, Thé de
  -- Mana) -- elle ne concerne que le sort ACTIVABLE (bouton d'action), un ID
  -- différent. Voir ApplyCastCountToText ci-dessous : appelée explicitement
  -- avec le bon spellID via secResDef.castCountSpellID, jamais devinée ici.
  return false
end

-- Pas de "local" ici : assigne l'upvalue forward-déclarée avant Update()
-- (cf. commentaire juste au-dessus de ResourceCircle.Update plus haut).
function ApplyStacksToText(fontString, spellID, dbg)
  return ApplyStacksTo(function(v) return pcall(fontString.SetText, fontString, v) end, spellID, dbg)
end

-- Expose la chaine complete (CDM + GetPlayerAuraBySpellID + enumeration,
-- chacune protegee par IsConfirmedZero) pour reutilisation hors de ce fichier
-- -- notamment les stacks d'icones (Debuffs.lua/Cooldowns.lua/Procs.lua),
-- qui n'avaient qu'un sous-ensemble de ces chemins (GetPlayerAuraBySpellID
-- seul) et ne pouvaient jamais confirmer un "0" en combat pour le cacher.
ResourceCircle.ApplyStacksTo = ApplyStacksTo

-- Équivalent de ApplyStacksTo mais pour un debuff de la CIBLE (pas une aura du
-- joueur). Pas d'équivalent target de GetPlayerAuraBySpellID -- donc seulement
-- 2 tiers ici (CDM, puis énumération HARMFUL), contrairement aux 3 tiers de
-- ApplyStacksTo ci-dessus. Utilisé par Mage Givre (specID 64, debuff 1246769,
-- cf. ns.SecondaryResourceDefs[64] dans Config/ResourceMap.lua).
-- ATTENTION : GetAuraDataByAuraInstanceID (AuraData complète) est REFUSÉ par
-- Blizzard dès que l'instID est secret (confirmé en jeu, patch 12.1 :
-- "Auras cannot be accessed when secret while tainted by 'AishCore'"), ce qui
-- est désormais quasi systématique pour un instID CDM. On utilise donc
-- GetAuraApplicationDisplayCount (API "blessed", ne lève pas cette exception)
-- comme confirmation de présence + valeur affichable, sans jamais tenter de
-- relire l'AuraData brute.
local function ApplyTargetStacksTo(sink, spellID, dbg)
  if not UnitExists("target") then return false end
  local A = ns.Auras
  local cdmTarget = A and A.cdmData and A.cdmData.target
  local cdmEntry = cdmTarget and cdmTarget[spellID]
  if cdmEntry and cdmEntry.instID then
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if dbg then dbg.cdm = { ok = ok, disp = disp } end
    if ok and disp ~= nil then
      -- Instance confirmée vivante : si le compte n'est pas exploitable (debuff
      -- à application unique, sans vrai compteur de stacks -- CONFIRMÉ EN
      -- JEU sur d'autres debuffs cible via TargetAuras.lua, `aura.applications
      -- or 0`), on affiche quand même "1" plutôt que d'échouer -- la présence
      -- seule reste une info utile, contrairement à ApplyStacksTo (joueur)
      -- qui suppose toujours une vraie aura stackable.
      local value = (not IsConfirmedZero(disp)) and disp or 1
      if sink(value) then if dbg then dbg.path = "cdm" end; return true end
    end
    -- Instance périmée (cdmData n'est jamais purgé, cf. commentaire plus
    -- haut) : on tombe dans le fallback ci-dessous.
  end

  -- Fallback : énumération des auras HARMFUL de la cible (même limite qu'en
  -- combat pour le fallback 2 joueur : la comparaison spellId doit être
  -- protégée par pcall, cf. commentaire détaillé sur ApplyStacksTo plus haut).
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
      if ok3 and not d then break end
      if ok3 and d then
      local okMatch, isMatch = pcall(function() return d.spellId == spellID end)
      if okMatch and isMatch then
        local okApp, disp3 = pcall(function() return d.applications end)
        if dbg then dbg.f2 = { matchedAt = i, okApp = okApp, disp3 = disp3 } end
        local value = (okApp and disp3 ~= nil and not IsConfirmedZero(disp3)) and disp3 or 1
        if sink(value) then if dbg then dbg.path = "fallback2-applications" end; return true end
      end
      end
    end
  end

  return false
end

local function ApplyTargetStacksToText(fontString, spellID, dbg)
  return ApplyTargetStacksTo(function(v) return pcall(fontString.SetText, fontString, v) end, spellID, dbg)
end

-- Compteur natif Blizzard affiché sur un bouton d'action (mécanisme distinct
-- d'une aura stackable OU d'un vrai système de charges de sort) : certains
-- sorts Mistweaver l'utilisent pour afficher un nombre de "stacks" sans aucun
-- buff associé (CONFIRMÉ EN JEU pour Don de Sheilun, cf. STACK_SPELLS/
-- ApplyStackToText dans PriorityBar.lua, et pour Thé de Mana : le buff
-- 115867 n'a pas ce compteur, mais le sort ACTIVABLE 115294 si). Appelé
-- uniquement quand secResDef.castCountSpellID est explicitement défini (cf.
-- ResourceMap.lua) -- jamais deviné automatiquement à partir de spellID
-- (ApplyStacksToText l'a confirmé trompeur pour un mauvais spellID : répond
-- toujours 0 au lieu de ne rien trouver).
--
-- LIMITE CONNUE (confirmée en jeu, plusieurs tentatives) : impossible de
-- masquer de façon fiable un "0" réel pendant le combat. Essayé et rejeté :
--   1) Comparer count==0 directement -> plante (secret number).
--   2) Comparer le texte déjà affiché (GetText après SetText) -> plante
--      aussi, la valeur reste secrète même une fois rendue à l'écran.
--   3) hooksecurefunc sur button.Count:SetText pour intercepter la valeur
--      AVANT notre propre lecture -> plante ENCORE : l'appel natif Blizzard
--      UpdateCount devient lui-même "tainted by AishCore" dès que notre
--      addon est chargé, donc même le texte que BLIZZARD passe à SetText
--      est déjà une secret string de son point de vue.
-- [CONFIRMÉ EN JEU via /rcsecres, count=0 en combat, Thé de Mana/115294] :
--   IsShown  ok=true val=true   <- toujours true, Blizzard ne Hide() JAMAIS le
--                                  FontString, il vide juste le texte -> piste
--                                  invalidée (contrairement à l'hypothèse de
--                                  départ), retirée.
--   GetText  ok=true val=nil    <- lecture qui NE PLANTE PAS et renvoie un nil
--                                  littéral (pas une valeur secrète maquillée en
--                                  "0") quand le bouton n'affiche rien.
--   GetStringWidth ok=true val=0 <- idem, nombre propre (largeur de rendu 0).
-- Différence avec la tentative #2 rejetée plus haut ("comparer le texte déjà
-- affiché -> plante") : celle-ci COMPARAIT le texte affiché à une valeur (donc
-- déclenchait la protection secret-value dès qu'un vrai nombre était présent).
-- Ici on se contente de LIRE (GetText/GetStringWidth), et on ne compare QUE
-- dans un pcall dédié -- si Blizzard renvoie un texte secret pour un compte >
-- 0, cette comparaison plante proprement (ok=false) et on ne gate simplement
-- pas, sans jamais casser l'affichage normal.
-- Bouton retrouvé via le cache de PriorityBar.lua (cachedSpellToButton,
-- reconstruit hors combat et préservé pendant le combat -- cf.
-- RebuildSpellButtonCache) plutôt que de dupliquer ce scan ici ; si
-- PriorityBar n'est pas chargé ou que le sort n'est sur aucune barre suivie,
-- on retombe silencieusement sur l'ancien comportement (affiche la valeur
-- réelle, cf. commentaire ci-dessus).
local function IsActionCountConfirmedHidden(spellID)
  local PB = ns.Modules and ns.Modules.PriorityBar
  local btn = PB and PB._GetCachedBtn and PB._GetCachedBtn(spellID)
  if not btn or not btn.Count then return false end
  local okTxt, isEmptyTxt = pcall(function()
    local t = btn.Count:GetText()
    return t == nil or t == ""
  end)
  if okTxt and isEmptyTxt then return true end
  local okW, isZeroW = pcall(function()
    return btn.Count:GetStringWidth() == 0
  end)
  if okW and isZeroW then return true end
  return false
end

-- Il n'existe donc aujourd'hui aucun signal exploitable en Lua pour
-- distinguer "0" de "3" sur cette valeur pendant le combat. On affiche donc
-- la valeur réelle (fonctionne, cf. IsConfirmedZero qui filtre au moins les
-- cas où la comparaison réussit, typiquement hors combat) en acceptant qu'un
-- vrai "0" en combat puisse s'afficher brièvement -- SAUF si
-- IsActionCountConfirmedHidden ci-dessus a pu trancher via le bouton natif.
local function ApplyCastCountToText(fontString, spellID)
  if not (C_Spell and C_Spell.GetSpellCastCount) then return false end
  if IsActionCountConfirmedHidden(spellID) then return false end
  local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
  if not ok or count == nil or IsConfirmedZero(count) then return false end
  return pcall(fontString.SetText, fontString, count)
end

-- Montant d'absorption restant pour une aura d'absorb (ex: Dur Au Mal / Ignore
-- Pain). IMPORTANT (confirmé en jeu) : AuraData.points est une SECRET TABLE
-- entière en combat (pas juste ses valeurs) — indexer aura.points[1] plante
-- ("attempt to index field 'points' (a secret table value)"), contrairement
-- aux stacks où seule la valeur (un number) est secrète et où
-- GetAuraApplicationDisplayCount sert de sink reconnu. Il n'existe pas
-- d'équivalent scalaire pour les points d'une aura précise. On utilise donc
-- UnitGetTotalAbsorbs("player") (déjà utilisé pour l'absorb bar dans
-- UnitBars.lua) qui renvoie directement un number (secret en combat, mais pas
-- une table) — sink reconnu de la même façon que 'disp' dans
-- ApplyStacksToText : passé BRUT en seul argument de FontString:SetText, sans
-- aucune opération dessus. La valeur affichée est donc le total des absorbs du
-- joueur, pas isolée à cette seule aura (Blizzard n'expose pas ce chiffre par
-- aura sans passer par une table secrète), mais pour Dur Au Mal cette aura est
-- presque toujours l'unique source de shield sur un Guerrier Protection.
--
-- IMPORTANT (confirmé en jeu) : la PRÉSENCE ne peut PAS se déterminer en
-- matchant juste cdmEntry.spellId — cdmData n'est JAMAIS nettoyé (aucune
-- suppression d'entrée nulle part dans CDMHooks.lua), donc une entrée Dur Au
-- Mal reste indéfiniment après la toute première utilisation, même une fois
-- le buff expiré (=> "0" affiché en permanence).
--
-- BUG CORRIGÉ : la validation utilisait GetAuraApplicationDisplayCount sur
-- cdmEntry.instID (l'instID du hook CDM), inutilisable pour TOUT lookup --
-- cette vérification échouait donc systématiquement en combat, empêchant l'affichage du
-- montant. On utilise à la place IsCDMAuraSwipePresent (CDMHooks.lua) :
-- canal event-driven déjà combat-safe, alimenté par le même swipe CDM que
-- la durée (donc déjà éprouvé pour ce spellID). GetPlayerAuraBySpellID en
-- repli pour les cas hors combat / juste après l'application du buff (avant
-- que le premier swipe CDM n'ait eu le temps de se déclencher).
local function ApplyAbsorbToText(fontString, spellID)
  local A = ns.Auras
  local present = A and A.IsCDMAuraSwipePresent and A.IsCDMAuraSwipePresent(spellID)
  if not present then
    local okP, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    present = okP and auraData ~= nil
  end
  if not present then return false end

  local fn = UnitAbsorb or UnitGetTotalAbsorbs
  if not fn then return false end
  local ok, absorb = pcall(fn, "player")
  if not ok or absorb == nil then return false end

  -- Option "grand nombre" (10000 -> "10k") : AbbreviateNumbers est C-side et
  -- accepte les secret numbers en argument (même sink que ShortenHP dans
  -- TopTargetBar.lua / SetHPText dans UnitBars.lua). Le résultat (une string,
  -- potentiellement secrète elle aussi) est ensuite passé BRUT à SetText.
  if ns.GetSecResCfg("secResAbsorbAbbreviate") and AbbreviateNumbers then
    local okAbbr, str = pcall(AbbreviateNumbers, absorb)
    if okAbbr and str then
      return pcall(fontString.SetText, fontString, str)
    end
  end

  return pcall(fontString.SetText, fontString, absorb)
end

function ResourceCircle.UpdateSecondaryResource()
  if not bar or not bar.secResText then return end
  if previewMode then return end  -- ne pas écraser la valeur factice affichée par SetPreview
  -- Le texte secondaire doit partager la visibilité du cercle central : ne
  -- jamais l'afficher/l'animer quand celui-ci est masqué (hors combat par
  -- défaut, cf. ShouldShow). BUG CORRIGÉ : secResFrame est parenté à UIParent
  -- (pas à bar, pour ses propres animations de pop indépendantes des
  -- combat-transitions) -- il ne suit donc PAS automatiquement bar:Hide(), et
  -- ce ticker (0.1s, indépendant de UpdateVisibility) le réaffichait dès que
  -- l'aura restait présente (ex: bouclier de Dur Au Mal encore actif en
  -- sortant du combat), même cercle central caché.
  if not bar:IsShown() then
    if _secResWasApplied or bar.secResText:IsShown() then
      SetSecResShown(false)
      if bar.secResFrame then bar.secResFrame:Hide() end
      _secResWasApplied = false
    end
    return
  end
  if not secResDef then
    -- Le stagger Brewmaster peut utiliser secResText indépendamment : ne pas le masquer dans ce cas
    if not staggerActive then SetSecResShown(false) end
    return
  end

  if secResDef.useStacks and secResDef.spellID then
    -- Alt aura (ex: Fragments de vide sous Métamorphose du vide)
    local applied = false
    if secResDef.altSpellID then
      applied = ApplyStacksToText(bar.secResText, secResDef.altSpellID)
    end
    -- Aura stackable classique (fallback si pas d'alt aura active)
    if not applied then
      applied = ApplyStacksToText(bar.secResText, secResDef.spellID)
    end
    -- Repli compteur bouton d'action (ex: Thé de Mana 115294) : uniquement si
    -- explicitement défini pour ce spec (cf. ApplyCastCountToText plus haut) --
    -- seule méthode qui survit au combat quand l'aura elle-même n'est ni
    -- suivie par le CDM Blizzard ni trouvable via GetPlayerAuraBySpellID.
    if not applied and secResDef.castCountSpellID then
      applied = ApplyCastCountToText(bar.secResText, secResDef.castCountSpellID)
    end
    -- Repli présence via le canal clone swipe (IsCDMAuraSwipePresent, même
    -- signal event-driven que ApplyAbsorbToText pour Dur Au Mal) : quand les 3
    -- tiers de ApplyStacksToText échouent tous (CONFIRMÉ EN JEU pour Bouclier
    -- d'os/195181 -- CDM lève "tainted", GetPlayerAuraBySpellID renvoie
    -- hasAura=false), on se contente de confirmer que l'aura est bien présente
    -- ; le TEXTE lui-même est déjà à jour, poussé indépendamment par
    -- PushStackApplications via l'abonnement clone-stack (cf.
    -- DetectSecondaryResource plus haut) -- on ne le réécrit jamais ici.
    local A = ns.Auras
    if not applied and A and A.IsCDMAuraSwipePresent
       and (A.IsCDMAuraSwipePresent(secResDef.spellID)
            or (secResDef.altSpellID and A.IsCDMAuraSwipePresent(secResDef.altSpellID))) then
      applied = true
    end
    -- Transitions 0 <-> 1+ stack EN COMBAT (pas seulement à l'entrée/sortie de
    -- combat) : petit pop fade+slide dans les deux sens, cf. StartSecResPop /
    -- StartSecResPopOut. `applied` est un simple booléen, jamais la valeur
    -- secrète elle-même.
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    -- Le pop-out cache lui-même le texte/déco une fois le fondu terminé (sinon
    -- rien ne serait visible en train de disparaître) ; SetSecResShown(false)
    -- immédiat ne s'applique donc que si aucun pop-out n'est en cours.
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif secResDef.useTargetDebuff and secResDef.spellID then
    -- Debuff de la CIBLE (pas une aura du joueur, cf. Mage Givre/specID 64
    -- dans Config/ResourceMap.lua) -- même logique de pop-in/pop-out que
    -- useStacks ci-dessus, juste via ApplyTargetStacksToText (unit "target").
    local applied = ApplyTargetStacksToText(bar.secResText, secResDef.spellID)
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif secResDef.useAbsorb and secResDef.spellID then
    -- Montant d'absorption restant (ex: Dur Au Mal / Ignore Pain)
    local applied = ApplyAbsorbToText(bar.secResText, secResDef.spellID)
    -- Recale la couleur à chaque tick sur celle de l'arc de durée (reflète en
    -- direct un changement de couleur via le color picker du panneau options).
    local c = GetDurationArcColor(ns._specID) or secResDef.color
    if c then bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif secResDef.useCharges and secResDef.spellID then
    -- Sort à charges : lecture via C_Spell.GetSpellCharges
    local count = nil
    local ok, info = pcall(C_Spell.GetSpellCharges, secResDef.spellID)
    if ok and info then
      count = tonumber(tostring(info.currentCharges))
    end
    if count and count > 0 then
      bar.secResText:SetText(tostring(count))
      SetSecResShown(true)
    else
      SetSecResShown(false)
    end
    return
  end

  SetSecResShown(false)
end

---------------------------------------------------------------------------
-- Arc de stagger (Moine Brasseur specID 268)
---------------------------------------------------------------------------
function ResourceCircle.DetectStagger()
  if not bar then return end
  staggerActive = false
  if staggerUpdateTicker then staggerUpdateTicker:Cancel(); staggerUpdateTicker = nil end
  if _arcOverlayTickers.stagger then _arcOverlayTickers.stagger:Cancel(); _arcOverlayTickers.stagger = nil end
  if bar.staggerArc          then bar.staggerArc:Hide() end
  if bar.staggerOverlayFrame then bar.staggerOverlayFrame:Hide() end
  if not secResDef then
    SetSecResShown(false)
    if bar.secResFrame then bar.secResFrame:Hide() end
  end
  if GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local ok, specID = pcall(GetSpecializationInfo, idx)
      if ok and specID == 268 then  -- Brewmaster Monk
        staggerActive = true
        staggerUpdateTicker = C_Timer.NewTicker(0.1, function()
          ResourceCircle.UpdateStagger()
        end)
      end
    end
  end
end

function ResourceCircle.UpdateStagger()
  if not bar or not staggerActive then return end
  -- Cercle central caché (hors combat, section Auras&Procs, etc.) : masquer
  -- le texte de stagger EN MEME TEMPS -- CONFIRMÉ EN JEU (avant ce fix) :
  -- il restait bloqué affiché à "0%" hors combat au lieu de disparaître
  -- avec le reste du cercle.
  if not bar:IsShown() then
    if bar.secResFrame and bar.secResFrame:IsShown() then
      SetSecResShown(false)
      bar.secResFrame:Hide()
    end
    return
  end
  if not bar.staggerArc or not bar.staggerArc:IsShown() then return end
  local ok1, stagAmt = pcall(UnitStagger, "player")
  local ok2, maxHP   = pcall(UnitHealthMax, "player")
  if not ok1 or not ok2 or not maxHP or maxHP <= 0 then return end

  -- L'arithmétique elle-même doit être protégée SÉPARÉMENT de l'appel API :
  -- stagAmt peut être une valeur secrète en combat (même piège qu'ailleurs
  -- dans ce module) -- une division/comparaison non protégée plante silencieusement TOUTE la
  -- fonction (le ticker avale l'erreur) : l'arc restait figé sur sa dernière
  -- valeur connue et le texte ne se mettait plus jamais à jour, exactement le
  -- symptôme rapporté ("seul l'arc s'affiche, plus le texte").
  local okPct, pct = pcall(function() return ((stagAmt or 0) / maxHP) * 100 end)
  if not okPct or pct == nil then return end

  local okC1, isLight    = pcall(function() return pct < 30 end)
  local okC2, isModerate = pcall(function() return pct < 60 end)
  local color = (okC1 and isLight and STAGGER_LIGHT)
    or (okC2 and isModerate and STAGGER_MODERATE)
    or STAGGER_HEAVY
  bar.staggerArc:SetStatusBarColor(color[1], color[2], color[3], 1)
  local okClamp, clamped = pcall(function() return math.min(pct, 100) end)
  ns.SmoothSetValue(bar.staggerArc, okClamp and clamped or pct)

  -- Affichage optionnel du % sous le texte de ressource (même slot que DH Dévoreur)
  if bar.secResText and bar.secResFrame and not secResDef then
    local cfg = ns.GetCfg("resourceCircle")
    if cfg.staggerShowPercent then
      -- Pourcentage (pas un stack) : pas de tirets décoratifs ici.
      bar.secResFrame:Show()
      local okFmt, txt = pcall(string.format, "%.1f%%", pct)
      if okFmt then bar.secResText:SetText(txt) end
      bar.secResText:SetTextColor(color[1], color[2], color[3], 1)
      bar.secResText:Show()
      if bar.secResDashL then bar.secResDashL:Hide() end
      if bar.secResDashR then bar.secResDashR:Hide() end
    else
      SetSecResShown(false)
      bar.secResFrame:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Arc de durée dans le cercle central : même pattern que les autres renders
-- SetCenterArcEntry(entry) : appelé par CenterArc.lua avec l'entrée de scan
-- (entry.durObj + entry.spellColor). SetTimerDuration : Blizzard anime à 60fps.
---------------------------------------------------------------------------
local INTERP_IMMED = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local TIMER_DRAIN  = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local _lastArcDurRef = nil  -- tostring(durObj) : change à chaque cast/refresh

function ResourceCircle.SetCenterArcEntry(entry)
  if not bar or not bar.durationArc then return end
  if entry and entry.durObj then
    -- Le durObj est recréé à chaque cast (même refresh) → tostring() change toujours.
    -- SetTimerDuration ne tourne que quand c'est un nouveau durObj.
    local durRef = tostring(entry.durObj)
    if durRef == _lastArcDurRef then return end
    _lastArcDurRef = durRef
    local color = entry.spellColor
    if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
    bar.durationArc:SetMinMaxValues(0, 1)
    if bar.durationArc.SetTimerDuration and INTERP_IMMED and TIMER_DRAIN then
      pcall(bar.durationArc.SetTimerDuration, bar.durationArc, entry.durObj, INTERP_IMMED, TIMER_DRAIN)
    end
    bar.durationArc:SetAlpha(1); bar.durationArc:Show()
    if bar.durationOvlFrame then bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show() end
  else
    -- Chemin CDM : SetTimerDuration(nil) uniquement si on avait un durObj actif.
    -- Si _lastArcDurRef est nil (chemin totem ou pas d'arc CDM), ne pas appeler
    -- SetTimerDuration(nil) — ça peut corrompre l'état de la StatusBar.
    if _lastArcDurRef then
      _lastArcDurRef = nil
      if bar.durationArc.SetTimerDuration then
        pcall(bar.durationArc.SetTimerDuration, bar.durationArc, nil)
      end
    end
    -- Toujours cacher l'arc visuellement (couvre chemin totem + chemin CDM).
    bar.durationArc:SetValue(0); bar.durationArc:Hide()
    if bar.durationOvlFrame then bar.durationOvlFrame:Hide() end
  end
end

-- Cas totem (Consécration) : pas de durObj, ticker manuel à 60fps côté CenterArc
function ResourceCircle.SetCenterArcColor(color)
  if not bar or not bar.durationArc then return end
  if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
end

function ResourceCircle.SetCenterArcValue(fraction, color)
  if not bar or not bar.durationArc then return end
  if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
  bar.durationArc:SetMinMaxValues(0, 1)
  ns.SmoothSetValue(bar.durationArc, math.max(0, math.min(1, fraction)))
  bar.durationArc:SetAlpha(1); bar.durationArc:Show()
  if bar.durationOvlFrame then bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show() end
end

-- Mode "absorb" de l'arc de durée (ex: Dur Au Mal, cfg.ignorePainArcAbsorb) :
-- remplissage proportionnel à une valeur/max génériques (montant d'absorption
-- restant, cf. CenterArc.lua) plutôt qu'au temps restant. `value` peut être un
-- secret number en combat : AUCUNE arithmétique dessus — on fixe juste les
-- bornes (maxValue, une constante/valeur Lua normale) et on passe value BRUT à
-- SetValue, qui calcule le remplissage côté C (même pattern que UpdateAbsorb
-- dans UnitBars.lua).
function ResourceCircle.SetCenterArcFill(value, maxValue, color)
  if not bar or not bar.durationArc then return end
  if not maxValue or maxValue <= 0 then return end
  if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
  bar.durationArc:SetMinMaxValues(0, maxValue)
  ns.SmoothSetValue(bar.durationArc, value)
  bar.durationArc:SetAlpha(1); bar.durationArc:Show()
  if bar.durationOvlFrame then bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show() end
end

-- Mode "cdmbar" (durée réellement combat-safe, cf. CDMHooks.lua "ABONNEMENTS
-- CLONE BAR") : relais BRUT vers bar.durationArc, SANS AUCUNE comparaison sur
-- lo/hi/value -- contrairement à SetCenterArcFill ci-dessus (qui compare
-- maxValue <= 0), invalide ici car hi peut être une valeur secrète en combat.
-- Exception : Blizzard envoie hi=0 en CLAIR au moment précis où le buff
-- expire (confirmé en jeu, /aacbar) -- seule comparaison sûre, utilisée pour
-- cacher proprement l'arc à ce moment-là.
function ResourceCircle.SetCenterArcBarMinMax(lo, hi)
  if not bar or not bar.durationArc then return end
  local okZero, isZero = pcall(function() return hi == 0 end)
  if okZero and isZero then
    bar.durationArc:SetValue(0); bar.durationArc:Hide()
    if bar.durationOvlFrame then bar.durationOvlFrame:Hide() end
    return
  end
  pcall(bar.durationArc.SetMinMaxValues, bar.durationArc, lo, hi)
  bar.durationArc:SetAlpha(1); bar.durationArc:Show()
  if bar.durationOvlFrame then bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show() end
end

function ResourceCircle.SetCenterArcBarValue(value)
  if not bar or not bar.durationArc then return end
  pcall(bar.durationArc.SetValue, bar.durationArc, value)
end

-- Proxy "clone-bar" : expose l'interface StatusBar (SetMinMaxValues/SetValue/
-- Show) attendue par ns.SubscribeCDMAuraBar, sans être une vraie StatusBar --
-- redirige vers bar.durationArc via les 2 sinks ci-dessus. CenterArc.lua
-- s'abonne à ce proxy plutôt qu'à bar.durationArc directement (ResourceCircle
-- garde la main sur son propre widget).
ResourceCircle.centerArcBarProxy = {
  SetMinMaxValues = function(_, lo, hi) ResourceCircle.SetCenterArcBarMinMax(lo, hi) end,
  SetValue        = function(_, value) ResourceCircle.SetCenterArcBarValue(value) end,
  Show            = function() end,
}

-- Remplit l'arc secondaire central directement depuis une aura stackable, en
-- reutilisant EXACTEMENT la meme chaine CDM + fallbacks que le texte de
-- ressource secondaire (ApplyStacksTo/ApplyStacksToText plus haut) -- pour
-- les specs a arc "stacks" lues via une aura (ex: DH Devoreur, cf.
-- CenterArc.lua/StackModeTick, qui n'a PAS de castCountSpellID contrairement
-- au The de Mana). Retourne true si une valeur a ete appliquee (arc affiche),
-- false sinon (l'appelant doit alors le cacher, cf. SetCenterArcEntry(nil)).
function ResourceCircle.ApplyStacksToCenterArc(spellID, maxValue, color, dbg)
  if not bar or not bar.durationArc then return false end
  if not maxValue or maxValue <= 0 then return false end
  bar.durationArc:SetMinMaxValues(0, maxValue)
  local applied = ApplyStacksTo(function(v)
    return pcall(ns.SmoothSetValue, bar.durationArc, v)
  end, spellID, dbg)
  if applied then
    if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
    bar.durationArc:SetAlpha(1); bar.durationArc:Show()
    if bar.durationOvlFrame then bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show() end
  end
  return applied
end

-- Accesseur debug (cf. /rcarc dans CenterArc.lua) : bar.durationArc/durationArcFrame
-- sont locaux a ce fichier, jamais exposes ailleurs.
function ResourceCircle._debug_GetDurationArc()
  return bar and bar.durationArc, bar and bar.durationArcFrame
end

---------------------------------------------------------------------------
-- Frame d'animation slide pour les secondary dots (même logique que Skyriding)
---------------------------------------------------------------------------
function ResourceCircle.CreateSecAnimFrame()
  if secAnimFrame then return end
  secAnimFrame = CreateFrame("Frame")
  secAnimFrame:SetScript("OnUpdate", function(_, dt)
    if secDotCount == 0 or not bar then return end
    for i = 1, secDotCount do
      local oa = secDotAnims[i]
      local f  = secDots[i]
      if not (oa and f) then break end

      -- Avancer l'animation slide
      if oa.progress ~= oa.target then
        local dir = oa.target > oa.progress and 1 or -1
        oa.progress = math.max(0.0, math.min(1.0, oa.progress + dir * SEC_SLIDE_SPEED * dt))
      end

      local t = oa.progress
      if t <= 0 then
        if f:IsShown() then f:Hide() end
      else
        if not f:IsShown() then f:Show() end
        -- ease-circ-out : démarre vite, amorti à l'arrivée (même courbe Skyriding)
        local eased = (t >= 1.0) and 1.0 or math.sqrt(1.0 - (1.0 - t) * (1.0 - t))
        -- Slide : part de SEC_SLIDE_SCALE × position cible vers la position finale
        local k = 1.0 + (SEC_SLIDE_SCALE - 1.0) * (1.0 - eased)
        if f._homeX then
          f:ClearAllPoints()
          f:SetPoint("CENTER", bar, "CENTER", f._homeX * k, f._homeY * k)
        end
        f:SetAlpha(eased)
      end
    end
  end)
end
---------------------------------------------------------------------------
-- Debug : /rcoverlay  — log tous les spell overlay events en temps réel
---------------------------------------------------------------------------
do
  local logging = false
  local logFrame = CreateFrame("Frame")
  logFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  logFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  logFrame:SetScript("OnEvent", function(_, event, spellID)
    if not logging then return end
    local tag = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and "|cff00ff00SHOW|r" or "|cffff4444HIDE|r"
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[RCOverlay]|r " .. tag .. " spellID=" .. tostring(spellID))
  end)
  SLASH_RCOVERLAY1 = "/rcoverlay"
  SlashCmdList["RCOVERLAY"] = function()
    logging = not logging
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[RCOverlay]|r logging " .. (logging and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
  end
end

---------------------------------------------------------------------------
-- [EXPERIMENTAL] /rcradial — bascule à chaud entre remplissage vertical
-- (actuel/défaut) et remplissage radial, pour tester sans passer par le
-- panneau de settings. Persiste dans le profil (cfg.radialFillTest).
---------------------------------------------------------------------------
SLASH_RCRADIAL1 = "/rcradial"
SlashCmdList["RCRADIAL"] = function()
  local cfg = ns.GetCfg("resourceCircle")
  cfg.radialFillTest = not cfg.radialFillTest
  -- ApplySettings() (pas juste ApplyRadialMode()) : re-synchronise aussi
  -- SetSize/SetPoint de bar.arc à sa taille/position correcte. Sans ça, si
  -- bar.arc avait été laissé à une taille périmée par une anim interrompue,
  -- ApplyRadialMode() seule ne le corrige pas (elle ne touche que
  -- Show/Hide/alpha/scale, jamais SetSize/SetPoint).
  ResourceCircle.ApplySettings()
  local state = cfg.radialFillTest and "|cff00ff00RADIAL|r" or "|cff88ccffVERTICAL (défaut)|r"
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[ResourceCircle]|r Remplissage : " .. state)
end

-- DEBUG TEMPORAIRE : dump complet de l'état de bar.arc, appelable à tout
-- moment (pas besoin d'attendre une transition de combat).
SLASH_RCARCDBG1 = "/rcarcdbg"
SlashCmdList["RCARCDBG"] = function()
  if not bar then print("[AishDbg] bar est nil"); return end
  if not bar.arc then print("[AishDbg] bar.arc est nil"); return end
  local a = bar.arc
  print(string.format("[AishDbg] bar: IsShown=%s IsVisible=%s Alpha=%.2f",
    tostring(bar:IsShown()), tostring(bar:IsVisible()), bar:GetAlpha()))
  print(string.format("[AishDbg] arc: IsShown=%s IsVisible=%s Alpha=%.2f Scale=%.3f",
    tostring(a:IsShown()), tostring(a:IsVisible()), a:GetAlpha(), a:GetScale()))
  local w, h = a:GetSize()
  print(string.format("[AishDbg] arc: Size=%.1fx%.1f FrameLevel=%s Strata=%s",
    w or -1, h or -1, tostring(a:GetFrameLevel()), tostring(a:GetFrameStrata())))
  local pt, relTo, relPt, x, y = a:GetPoint(1)
  print(string.format("[AishDbg] arc: Point=%s relTo=%s relPt=%s x=%s y=%s",
    tostring(pt), (relTo and relTo.GetName and relTo:GetName()) or tostring(relTo), tostring(relPt), tostring(x), tostring(y)))
  local okV, val = pcall(a.GetValue, a)
  local okMM, lo, hi = pcall(a.GetMinMaxValues, a)
  print(string.format("[AishDbg] arc: GetValue ok=%s val=%s | GetMinMax ok=%s lo=%s hi=%s",
    tostring(okV), tostring(val), tostring(okMM), tostring(lo), tostring(hi)))
  print(string.format("[AishDbg] cfg.radialFillTest=%s bar.radialFillFrame:IsShown=%s",
    tostring(ns.GetCfg("resourceCircle").radialFillTest), tostring(bar.radialFillFrame and bar.radialFillFrame:IsShown())))
  local okC, r, g, b, cAlpha = pcall(a.GetStatusBarColor, a)
  print(string.format("[AishDbg] arc: StatusBarColor ok=%s r=%s g=%s b=%s a=%s",
    tostring(okC), tostring(r), tostring(g), tostring(b), tostring(cAlpha)))
  local tex = a.GetStatusBarTexture and a:GetStatusBarTexture()
  if tex then
    local tw, th = tex:GetSize()
    print(string.format("[AishDbg] arc: tex IsShown=%s Alpha=%.2f Size=%.1fx%.1f Texture=%s",
      tostring(tex:IsShown()), tex:GetAlpha(), tw or -1, th or -1, tostring(tex:GetTexture())))
    local tpt, trelTo, trelPt, tx, ty = tex:GetPoint(1)
    print(string.format("[AishDbg] arc: tex Point=%s relTo=%s relPt=%s x=%s y=%s",
      tostring(tpt), (trelTo and trelTo.GetName and trelTo:GetName()) or tostring(trelTo), tostring(trelPt), tostring(tx), tostring(ty)))
  else
    print("[AishDbg] arc: GetStatusBarTexture() a échoué ou renvoyé nil")
  end
  if bar.overlayFrame then
    local of = bar.overlayFrame
    print(string.format("[AishDbg] overlayFrame: IsShown=%s IsVisible=%s Alpha=%.2f Scale=%.3f FrameLevel=%s",
      tostring(of:IsShown()), tostring(of:IsVisible()), of:GetAlpha(), of:GetScale(), tostring(of:GetFrameLevel())))
  end
  if bar.overlay then
    local ov = bar.overlay
    local ow, oh = ov:GetSize()
    local ovr, ovg, ovb, ova = ov:GetVertexColor()
    print(string.format("[AishDbg] overlay: IsShown=%s Alpha=%.2f Scale=%.3f Size=%.1fx%.1f VertexColor=%.2f,%.2f,%.2f,%.2f",
      tostring(ov:IsShown()), ov:GetAlpha(), ov:GetScale(), ow or -1, oh or -1, ovr or -1, ovg or -1, ovb or -1, ova or -1))
    local opt, orelTo, orelPt, ox, oy = ov:GetPoint(1)
    print(string.format("[AishDbg] overlay: Point=%s relTo=%s relPt=%s x=%s y=%s",
      tostring(opt), (orelTo and orelTo.GetName and orelTo:GetName()) or tostring(orelTo), tostring(orelPt), tostring(ox), tostring(oy)))
  end
end

---------------------------------------------------------------------------
-- Debug : /rcaura  — dump toutes les auras HELPFUL du joueur
---------------------------------------------------------------------------
SLASH_RCAURA1 = "/rcaura"
SlashCmdList["RCAURA"] = function()
  local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCAura]|r " .. tostring(msg)) end
  p("=== HELPFUL auras ===")
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    p("GetPlayerAuraBySpellID(369299) = " .. tostring(C_UnitAuras.GetPlayerAuraBySpellID(369299) ~= nil))
  end
  local found = 0
  for idx = 1, 60 do
    local ok, name, _, count, _, _, _, _, _, _, spellID = pcall(UnitAura, "player", idx, "HELPFUL")
    if not ok or not name then break end
    found = found + 1
    p(string.format("  [%d] spellID=%-8d stacks=%-2d  %s", idx, spellID or 0, count or 0, name or "?"))
  end
  if found == 0 then p("  (aucune aura HELPFUL)") end
end

---------------------------------------------------------------------------
-- Debug : /rcsecres — état complet du texte de ressource secondaire
---------------------------------------------------------------------------
SLASH_RCSECRES1 = "/rcsecres"
SlashCmdList["RCSECRES"] = function()
  local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCSecRes]|r " .. tostring(msg)) end
  if not bar then p("bar est nil"); return end
  p(string.format("InCombatLockdown=%s", tostring(InCombatLockdown and InCombatLockdown())))
  p(string.format("bar: IsShown=%s", tostring(bar:IsShown())))
  p(string.format("ShouldShow()=%s  lastVisibilityState=%s",
    tostring(ResourceCircle.ShouldShow()), tostring(lastVisibilityState)))
  local idx = GetSpecialization and GetSpecialization()
  local specID = idx and GetSpecializationInfo and select(1, pcall(GetSpecializationInfo, idx))
  local okSpec, sid = pcall(GetSpecializationInfo, idx or 0)
  p(string.format("GetSpecialization idx=%s specID(ok=%s)=%s", tostring(idx), tostring(okSpec), tostring(sid)))
  if secResDef then
    p(string.format("secResDef: spellID=%s useStacks=%s useAbsorb=%s useCharges=%s useTargetDebuff=%s altSpellID=%s",
      tostring(secResDef.spellID), tostring(secResDef.useStacks), tostring(secResDef.useAbsorb), tostring(secResDef.useCharges), tostring(secResDef.useTargetDebuff), tostring(secResDef.altSpellID)))
  else
    p("secResDef est nil")
  end
  if bar.secResFrame then
    p(string.format("secResFrame: IsShown=%s IsVisible=%s Alpha=%.2f FrameLevel=%s Strata=%s",
      tostring(bar.secResFrame:IsShown()), tostring(bar.secResFrame:IsVisible()),
      bar.secResFrame:GetAlpha(), tostring(bar.secResFrame:GetFrameLevel()), tostring(bar.secResFrame:GetFrameStrata())))
  else
    p("bar.secResFrame est nil")
  end
  if bar.secResText then
    p(string.format("secResText: IsShown=%s Alpha=%.2f Text=%q",
      tostring(bar.secResText:IsShown()), bar.secResText:GetAlpha(), tostring(bar.secResText:GetText())))
  else
    p("bar.secResText est nil")
  end
  if secResDef and secResDef.spellID and not secResDef.useTargetDebuff then
    local A = ns.Auras
    p(string.format("ns.Auras présent=%s  cdmData.player présent=%s",
      tostring(A ~= nil), tostring(A and A.cdmData and A.cdmData.player ~= nil)))
    local cdmPlayer = A and A.cdmData and A.cdmData.player
    local cdmEntry = cdmPlayer and cdmPlayer[secResDef.spellID]
    local foundInstID = cdmEntry and cdmEntry.instID
    p(string.format("cdmData: instID pour spellID %d = %s", secResDef.spellID, tostring(foundInstID)))
    if foundInstID then
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", foundInstID)
      p(string.format("GetAuraDataByAuraInstanceID ok=%s aura=%s", tostring(ok), tostring(aura ~= nil)))
      if ok and aura then
        -- Pas de lecture de aura.applications/aura.points ici : indexer un champ
        -- secret jette une erreur qui "tainted" tout le reste de CETTE fonction
        -- (donc fausse StacksFromCDM plus bas). On reste sur le seul sink sûr.
        local okD1, dispD1 = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, foundInstID, 1, 999)
        p(string.format("GetAuraApplicationDisplayCount(1,999) ok=%s value=%s type=%s", tostring(okD1), tostring(dispD1), type(dispD1)))
      end
    end
    -- altSpellID (ex: Fragments de vide 1227702 sous Metamorphose du vide, DH
    -- Devoreur) : teste EXACTEMENT comme UpdateSecondaryResource, essaye en
    -- premier, avant le spellID normal -- absent des diagnostics precedents,
    -- donc invisible dans /rcsecres jusqu'ici malgre son role prioritaire.
    if secResDef.altSpellID then
      local altDbg = {}
      local altApplied = ApplyStacksToText(bar.secResText, secResDef.altSpellID, altDbg)
      p(string.format("ApplyStacksToText altSpellID(%d) = %s  path=%s  secResText:GetText() ensuite = %q",
        secResDef.altSpellID, tostring(altApplied), tostring(altDbg.path), tostring(bar.secResText:GetText())))
      if altDbg.cdm then p(string.format("  [alt] cdm: ok=%s disp=%s", tostring(altDbg.cdm.ok), tostring(altDbg.cdm.disp))) end
      if altDbg.f1 then
        p(string.format("  [alt] fallback1(GetPlayerAuraBySpellID): okAura=%s hasAura=%s instID=%s ok2=%s disp2=%s",
          tostring(altDbg.f1.okAura), tostring(altDbg.f1.hasAura), tostring(altDbg.f1.instID), tostring(altDbg.f1.ok2), tostring(altDbg.f1.disp2)))
      end
      if altDbg.f2MatchErrAt then p(string.format("  [alt] fallback2: comparaison d.spellId a echoue (secret) a l'index %d", altDbg.f2MatchErrAt)) end
      if altDbg.f2 then
        p(string.format("  [alt] fallback2(enum HELPFUL): matchedAt=%s okApp=%s disp3=%s okIdx=%s dispIdx=%s",
          tostring(altDbg.f2.matchedAt), tostring(altDbg.f2.okApp), tostring(altDbg.f2.disp3), tostring(altDbg.f2.okIdx), tostring(altDbg.f2.dispIdx)))
      end
    end

    local dbg = {}
    local applied = ApplyStacksToText(bar.secResText, secResDef.spellID, dbg)
    p(string.format("ApplyStacksToText(%d) = %s  path=%s  secResText:GetText() ensuite = %q",
      secResDef.spellID, tostring(applied), tostring(dbg.path), tostring(bar.secResText:GetText())))
    if dbg.cdm then p(string.format("  cdm: ok=%s disp=%s", tostring(dbg.cdm.ok), tostring(dbg.cdm.disp))) end
    if dbg.f1 then
      p(string.format("  fallback1(GetPlayerAuraBySpellID): okAura=%s hasAura=%s instID=%s ok2=%s disp2=%s",
        tostring(dbg.f1.okAura), tostring(dbg.f1.hasAura), tostring(dbg.f1.instID), tostring(dbg.f1.ok2), tostring(dbg.f1.disp2)))
    end
    if dbg.f2MatchErrAt then p(string.format("  fallback2: comparaison d.spellId a echoue (secret) a l'index %d", dbg.f2MatchErrAt)) end
    if dbg.f2 then
      p(string.format("  fallback2(enum HELPFUL): matchedAt=%s okApp=%s disp3=%s okIdx=%s dispIdx=%s",
        tostring(dbg.f2.matchedAt), tostring(dbg.f2.okApp), tostring(dbg.f2.disp3), tostring(dbg.f2.okIdx), tostring(dbg.f2.dispIdx)))
    end
    if not applied and secResDef.castCountSpellID then
      local ccSid = secResDef.castCountSpellID
      local okCC, count = pcall(C_Spell.GetSpellCastCount, ccSid)
      p(string.format("castCountSpellID=%d GetSpellCastCount ok=%s count=%s", ccSid, tostring(okCC), tostring(count)))
      -- Diagnostic du bouton natif (IsActionCountConfirmedHidden) : à collecter
      -- EN COMBAT pour savoir pourquoi le gate IsShown() ne masque pas le "0".
      local PBdbg = ns.Modules and ns.Modules.PriorityBar
      local btnDbg = PBdbg and PBdbg._GetCachedBtn and PBdbg._GetCachedBtn(ccSid)
      p(string.format("  [btn] PriorityBar present=%s _GetCachedBtn=%s btn trouve=%s",
        tostring(PBdbg ~= nil), tostring(PBdbg and PBdbg._GetCachedBtn ~= nil), tostring(btnDbg ~= nil)))
      if btnDbg then
        p(string.format("  [btn] name=%s hasCount=%s", tostring(btnDbg.GetName and btnDbg:GetName()), tostring(btnDbg.Count ~= nil)))
        if btnDbg.Count then
          local okShown, shown = pcall(btnDbg.Count.IsShown, btnDbg.Count)
          local okTxt, txt     = pcall(btnDbg.Count.GetText, btnDbg.Count)
          local okW,   w       = pcall(btnDbg.Count.GetStringWidth, btnDbg.Count)
          local okA,   a       = pcall(btnDbg.Count.GetAlpha, btnDbg.Count)
          p(string.format("  [btn.Count] IsShown ok=%s val=%s | GetText ok=%s val=%s | GetStringWidth ok=%s val=%s | GetAlpha ok=%s val=%s",
            tostring(okShown), tostring(shown), tostring(okTxt), tostring(txt), tostring(okW), tostring(w), tostring(okA), tostring(a)))
        end
      end
      applied = ApplyCastCountToText(bar.secResText, ccSid)
      p(string.format("ApplyCastCountToText(%d) = %s  secResText:GetText() ensuite = %q",
        ccSid, tostring(applied), tostring(bar.secResText:GetText())))
    end
    if applied then SetSecResShown(true) end
  elseif secResDef and secResDef.spellID and secResDef.useTargetDebuff then
    -- Chemin cible (Mage Givre, cf. Config/ResourceMap.lua) : diagnostic
    -- séparé du bloc joueur ci-dessus, qui serait trompeur ici (le debuff
    -- n'est jamais sur "player").
    p(string.format("UnitExists(target)=%s", tostring(UnitExists("target"))))
    local A = ns.Auras
    p(string.format("ns.Auras présent=%s  cdmData.target présent=%s",
      tostring(A ~= nil), tostring(A and A.cdmData and A.cdmData.target ~= nil)))
    local cdmTarget = A and A.cdmData and A.cdmData.target
    local cdmEntryT = cdmTarget and cdmTarget[secResDef.spellID]
    local foundInstID = cdmEntryT and cdmEntryT.instID
    p(string.format("cdmData.target: instID pour spellID %d = %s", secResDef.spellID, tostring(foundInstID)))
    if foundInstID then
      local okAura, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "target", foundInstID)
      p(string.format("GetAuraDataByAuraInstanceID(target) ok=%s aura=%s", tostring(okAura), tostring(aura ~= nil)))
    end
    -- Enumeration HARMFUL brute de la cible : liste TOUT ce qui est vu dessus
    -- (spellId + applications), pour confirmer si le spellID attendu y figure
    -- vraiment -- seulement hors combat, la comparaison spellId plantant en
    -- combat (cf. commentaire détaillé sur ApplyStacksTo plus haut).
    if not (InCombatLockdown and InCombatLockdown()) and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local any = false
      for i = 1, 40 do
        local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
        if not ok3 or not d then break end
        any = true
        p(string.format("  [target HARMFUL #%d] spellId=%s name=%s applications=%s",
          i, tostring(d.spellId), tostring(d.name), tostring(d.applications)))
      end
      if not any then p("  (aucun debuff HARMFUL trouvé sur la cible)") end
    else
      p("  (énumération HARMFUL sautée : pas de cible, ou en combat -- spellId y serait secret)")
    end
    local dbg = {}
    local applied = ApplyTargetStacksToText(bar.secResText, secResDef.spellID, dbg)
    p(string.format("ApplyTargetStacksToText(%d) = %s  path=%s  secResText:GetText() ensuite = %q",
      secResDef.spellID, tostring(applied), tostring(dbg.path), tostring(bar.secResText:GetText())))
    if dbg.cdm then
      p(string.format("  cdm: ok=%s okApp=%s disp=%s", tostring(dbg.cdm.ok), tostring(dbg.cdm.okApp), tostring(dbg.cdm.disp)))
    end
    if dbg.f2 then
      p(string.format("  fallback2(enum HARMFUL): matchedAt=%s okApp=%s disp3=%s",
        tostring(dbg.f2.matchedAt), tostring(dbg.f2.okApp), tostring(dbg.f2.disp3)))
    end
    if applied then SetSecResShown(true) end
  end
end
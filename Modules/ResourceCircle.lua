-- Modules/ResourceCircle.lua : Cercle de ressource primaire (dynamique par classe/spec)
local addonName, ns = ...
local L = ns.L

local ResourceCircle = {}
ns.Modules.ResourceCircle = ResourceCircle

-- Styles de déco autour du texte de ressource secondaire ("- N -", "[ N ]"...) ; left/right jamais concaténés à N (cf. SetSecResShown).
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
-- rcAnimBusy = animation show/hide en cours ; rcAnimDirty = demande arrivée pendant, jamais interrompue, relance UpdateVisibility() à la fin.
local rcAnimBusy = false
local rcAnimDirty = false
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

-- Affiche/masque texte + tirets décoratifs ensemble ; tirets séparés de N car concat/format interdits sur une valeur secrète.
local function SetSecResShown(shown)
  if not bar then return end
  if bar.secResText  then bar.secResText:SetShown(shown)  end
  if bar.secResDashL then bar.secResDashL:SetShown(shown) end
  if bar.secResDashR then bar.secResDashR:SetShown(shown) end
end

-- Applique style/espacement déco (par spec, ns.GetSecResCfg) ; specID optionnel pour éviter de dépendre de ns._specID pas encore à jour.
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

-- Durées/courbes anim show/hide du cercle central ; opacity = alpha départ(show)/fin(hide) ; arc/arcOverlay animés indépendamment via `scale`.
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
  -- 11/12 (staggerArc/staggerOverlayFrame) : animés par AnimateArcOverlay avec la spec arc/arcOverlay.
  [13] = "textBackdrop",
  [14] = "secResText",
}

-- Géométrie de repos ("home") mémorisée via RecordHome() plutôt que relue via GetPoint/GetSize,
-- qui peut renvoyer des secret values en combat et bloquer les opérations Lua dessus.
local _elemHome = {}
local function RecordHome(element, point, relTo, relPoint, x, y, w, h)
  _elemHome[element] = { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y, w = w, h = h }
end

-- Ressource secondaire (texte sous le cercle : Bone Shield, Soul Fragments, etc.)
local secResDef        = nil   -- définition active (ou nil)
local secResUpdateTicker = nil -- ticker de mise à jour
-- spellID(s) abonnés au canal clone-stack (CDMHooks) pour bar.secResText, mémorisés pour désabonnement propre au changement de spec.
local _secResStackSubIDs = nil
local FONT_BOLD_ITALIC = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-BoldItalic.ttf"

-- Essence Burst (Evoker Preservation) : proc détecté via spell overlay
-- Sorts qui s'allument quand Essence Burst est actif
local ESSENCE_BURST_SPELLS = { [364343]=true, [355913]=true, [356995]=true }  -- Echo, Emerald Blossom, Disintegrate
local essenceBurstGlowing  = {}   -- [spellID] = true si overlay actif en ce moment
local essenceBurstActive   = false -- dérivé de essenceBurstGlowing

-- Fire Mage Heating Up (1) / Hot Streak (2) : overlay écran = Heating Up, glow Pyroblast/Flamestrike = Hot Streak.
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

-- Remplissage radial : jauge en arc de 280° (trou de 80° en bas, centré sur 6h), 1 quartier (RadialWedge.tga) par %
local RADIAL_FRAG_COUNT = 100
local RADIAL_ARC_SPAN_DEG  = 280   -- 360 - 80 (trou en bas)
local RADIAL_ARC_START_DEG = 220   -- bearing (0=midi, horaire) où commence le 0%

-- Recalcule taille/position/rotation des quartiers radiaux (rappelée depuis ApplySettings pour rester synchro avec le GUI)
local function LayoutRadialFrags()
  if not bar or not bar.radialFrags then return end
  local cfg = ns.GetCfg("resourceCircle")
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  -- Quartiers toujours en taille max ; c'est bar.overlay qui masque le centre par-dessus.
  local fragInnerR = (arcPx / 2) * 0.05  -- quasi le centre (jamais 0 pile, évite une taille nulle)
  local fragOuterR = (arcPx / 2) * 0.98
  local fragMidR   = (fragInnerR + fragOuterR) / 2
  local fragSize = (fragOuterR - fragInnerR) * 1.2  -- surdimensionné pour chevaucher les voisins (anti-aliasing)
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
      local tex = frag:GetStatusBarTexture()
      if tex then tex:SetRotation(-angle) end  -- signe négatif : SetRotation est anti-horaire, notre bearing est horaire
    end
  end
end

-- Verifie si les elements doivent etre visibles (en combat uniquement)
function ResourceCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideResourceCircle ~= false then return false end
  local cfg = ns.GetCfg("resourceCircle")
  if cfg.enabled == false then return false end
  -- "Toujours actif en instance" : ignore les transitions combat en donjon/raid.
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
    -- Desactivation live : interruption immediate, on remet le verrou de file d'attente a plat.
    rcAnimBusy = false
    rcAnimDirty = false
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
  -- radialFillFrame (mode radial) est ancré via SetAllPoints(bar), pas d'ancrage exploitable pour slide/scale
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
  -- Recaler les quartiers radiaux (dépend de arcPx/overlayRatio)
  LayoutRadialFrags()
  -- Ré-appliquer la valeur de démo (72%) après le recalage, sinon les quartiers restent vides en aperçu.
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
  -- Geometrie dependante de la spec : specID resolu fraichement ici (pas via ns._specID,
  -- pas encore rempli au login a ce stade) pour eviter d'ecraser la geometrie par-spec au login/reload.
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

  -- Synchronise affichage vertical/radial avec cfg.radialFillTest (bascule réellement l'élément visible)
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
  -- Fragments radiaux : même couleur que l'arc vertical (synchronisée pour que /rcradial ne montre jamais une couleur périmée)
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
  -- Reset Demonic Core si on n'est plus Warlock Démonologie (specID 266, pas 265=Affliction)
  if not (playerClass2 == "WARLOCK" and specID2 == 266) then
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
  -- +101 : réserve un niveau distinct à chacun des 100 quartiers radiaux sans dépasser l'overlay.
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

  -- Remplissage radial : 100 StatusBar quartiers, chacune sa plage MinMax, recevant le même pct via ns.SmoothSetValue (toggle : /rcradial)
  local radialFillFrame = CreateFrame("Frame", nil, bar)
  radialFillFrame:SetFrameLevel(arc:GetFrameLevel())
  radialFillFrame:SetAllPoints(bar)
  local radialFrags = {}
  for k = 0, RADIAL_FRAG_COUNT - 1 do
    local frag = CreateFrame("StatusBar", nil, radialFillFrame)
    -- Niveau explicite et croissant : évite un ordre d'empilement instable entre les quartiers.
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

  -- Déco "- N -" (style/espacement configurables, cf. RefreshSecResDeco) : FontStrings séparées ancrées aux bords de secResText.
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
      if wlSpecID == 266 then  -- Demonologie (265 = Affliction, cf. ns.SPEC_MAP)
        demonicCoreOverlayActive = isShow
      end
    end
  end)

  -- Pré-allouer la table d'éléments pour AnimateVisibility (11 slots fixes + 2 staggerArc conditionnels).
  do
    _rcAnimElems[1]  = { element = bar.bgGlow  }
    _rcAnimElems[2]  = { element = bar.bgLarge }
    _rcAnimElems[3]  = { element = bar.text    }
    -- Slots 4/5 (arc, overlayFrame) et 11/12 (staggerArc, staggerOverlayFrame) : animés par AnimateArcOverlay.
    _rcAnimElems[4]  = { element = nil }
    _rcAnimElems[5]  = { element = nil }
    _rcAnimElems[6]  = { element = bar.dot3 }
    _rcAnimElems[7]  = { element = bar.dot2 }
    _rcAnimElems[8]  = { element = bar.dot4 }
    _rcAnimElems[9]  = { element = bar.dot1 }
    _rcAnimElems[10] = { element = bar.dot5 }
    _rcAnimElems[11] = { element = nil }
    _rcAnimElems[12] = { element = nil }
    _rcAnimElems[13] = { element = bar.textBackdrop }
    _rcAnimElems[14] = { element = nil }  -- secResFrame (conditionnel : seulement si secResDef existe)
  end

  ResourceCircle.ApplyRadialMode()

  return bar
end

-- Bascule entre remplissage vertical (arc) et radial (fragments). Appelé au Create() et par /rcradial.
function ResourceCircle.ApplyRadialMode()
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")
  local radial = cfg.radialFillTest == true
  -- SetAlpha(1)/SetScale(1) sur l'élément actif : évite qu'il reste bloqué dans un état de transition interrompue.
  if bar.arc then
    if radial then bar.arc:Hide() else bar.arc:SetAlpha(1); bar.arc:SetScale(1); bar.arc:Show() end
  end
  if bar.radialFillFrame then
    if radial then bar.radialFillFrame:SetAlpha(1); bar.radialFillFrame:SetScale(1); bar.radialFillFrame:Show() else bar.radialFillFrame:Hide() end
  end
  -- Forcer un refresh immédiat pour éviter un flash à l'ancienne valeur.
  pcall(ResourceCircle.Update)
end

-- Applique pct (0-100) à l'arc actif (vertical ou radial). Radial : même pct poussé dans chaque quartier via ns.SmoothSetValue.
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

-- Anime l'arc actif et son overlay indépendamment (chacun son timing) ; l'overlay finit en dernier pour ne pas laisser transparaître le trou central.
local _arcOverlayTickers = { main = nil, stagger = nil }
-- Anime une paire arc+overlay avec CIRCLE_ANIM.arc/arcOverlay ; factorisé pour que l'arc de
-- stagger reçoive exactement la même animation que l'arc principal.
local function AnimateArcOverlayPair(key, shouldShow, arcEl, overlayEl, overlayVisualEl)
  if not arcEl or not overlayEl then return end
  -- /rcanimlog : trace chaque appel + si un cycle en cours est interrompu.
  if ns._rcAnimDebug then
    print(string.format("|cff88ffff[RCAnim]|r %.3f AnimateArcOverlayPair key=%s shouldShow=%s interrompt=%s",
      GetTime(), tostring(key), tostring(shouldShow), tostring(_arcOverlayTickers[key] ~= nil)))
  end
  if _arcOverlayTickers[key] then _arcOverlayTickers[key]:Cancel(); _arcOverlayTickers[key] = nil end

  local arcSpec     = shouldShow and CIRCLE_ANIM.arc.show        or CIRCLE_ANIM.arc.hide
  local overlaySpec = shouldShow and CIRCLE_ANIM.arcOverlay.show or CIRCLE_ANIM.arcOverlay.hide

  -- opacity = alpha de départ pour show / de fin pour hide (l'autre bout vaut toujours 1), même convention que ns.AnimateStagger.
  local arcOpacity, overlayOpacity = arcSpec.opacity or 0, overlaySpec.opacity or 0
  local arcStartAlpha, arcEndAlpha         = shouldShow and arcOpacity or 1,     shouldShow and 1 or arcOpacity
  local overlayStartAlpha, overlayEndAlpha = shouldShow and overlayOpacity or 1, shouldShow and 1 or overlayOpacity
  -- Repart du dernier alpha réellement appliqué (_aishAnimAlpha) si connu, pas du point canonique,
  -- pour éviter un décalage visible entre arc/overlay si une interruption survient à des instants différents.
  if arcEl._aishAnimAlpha then arcStartAlpha = arcEl._aishAnimAlpha end
  if overlayEl._aishAnimAlpha then overlayStartAlpha = overlayEl._aishAnimAlpha end

  -- Géométrie "home" via _elemHome (RecordHome), fiable même en combat contrairement à GetPoint/GetSize (secret values). Scale via SetSize, pas SetScale (pivot pas l'ancrage réel).
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
  -- Redimensionner une StatusBar ne réapplique pas son crop : force via ns.SmoothSetValue (pas un
  -- SetValue nu, écrasé par l'interpolation native déjà en cours). Textures (bar.overlay) : pas concernées.
  local function RefreshCrop(element)
    if element.GetValue and element.SetValue then
      ns.SmoothSetValue(element, element:GetValue())
    end
  end
  -- useGlobalScale : StatusBar (arc) utilise SetScale (évite le souci de redraw du crop) plutôt que
  -- SetSize (utilisé pour les Textures comme bar.overlay). Pivot de SetScale pas garanti = ancrage BOTTOM.
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
    -- Mémorise le dernier scale réellement appliqué, pour qu'une animation interrompue reprenne d'où elle en était.
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
    -- nil (pas 1) : un cycle complet doit laisser le prochain repartir du point de départ canonique.
    element._aishAnimScale = nil
  end

  local arcSlideX, arcSlideY = arcSpec.slideX or 0, arcSpec.slideY or 0
  local ovlSlideX, ovlSlideY = overlaySpec.slideX or 0, overlaySpec.slideY or 0
  local arcScale     = arcSpec.scale or 1
  local overlayScale = overlaySpec.scale or 1
  local arcStartScale, arcEndScale         = shouldShow and arcScale or 1,     shouldShow and 1 or arcScale
  local overlayStartScale, overlayEndScale = shouldShow and overlayScale or 1, shouldShow and 1 or overlayScale
  -- Repart du dernier scale réellement appliqué (_aishAnimScale) si connu, pas du point canonique,
  -- sinon des interruptions rapprochées (entrée/sortie combat successives) laissent l'élément bloqué petit.
  if arcEl and arcEl._aishAnimScale then arcStartScale = arcEl._aishAnimScale end
  if overlayVisualEl and overlayVisualEl._aishAnimScale then overlayStartScale = overlayVisualEl._aishAnimScale end

  local needArcTransform     = arcSlideX ~= 0 or arcSlideY ~= 0 or arcScale ~= 1
  local needOverlayTransform = ovlSlideX ~= 0 or ovlSlideY ~= 0 or overlayScale ~= 1
  local arcHome     = needArcTransform and captureHome(arcEl) or nil
  local overlayHome = needOverlayTransform and captureHome(overlayVisualEl) or nil

  arcEl:Show(); arcEl:SetAlpha(arcStartAlpha); arcEl._aishAnimAlpha = arcStartAlpha
  if overlayVisualEl then overlayVisualEl:Show() end
  overlayEl:Show(); overlayEl:SetAlpha(overlayStartAlpha); overlayEl:SetScale(1)
  overlayEl._aishAnimAlpha = overlayStartAlpha

  -- Applique la géométrie en p=0 immédiatement (comme l'alpha), pas seulement au 1er tick du ticker,
  -- sinon une interruption avant ce tick laisse l'overlay à la géométrie de l'animation précédente.
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
        -- Valeur calculée, jamais relue via :GetAlpha() (peut renvoyer une valeur secrète en combat).
        local curArcAlpha = arcStartAlpha + (arcEndAlpha - arcStartAlpha) * p
        arcEl:SetAlpha(curArcAlpha)
        arcEl._aishAnimAlpha = curArcAlpha
        if arcHome then
          applyTransform(arcEl, arcHome, arcSlideX, arcSlideY, p, arcStartScale + (arcEndScale - arcStartScale) * p, true)
        end
        if elapsed >= arcSpec.duration then
          arcEl:SetAlpha(arcEndAlpha)
          -- nil (pas arcEndAlpha) : un cycle qui va au bout ne laisse rien à reprendre, le suivant repart du point canonique.
          arcEl._aishAnimAlpha = nil
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
        -- Valeur calculée, jamais relue via :GetAlpha() -- même raison que pour l'arc ci-dessus.
        local curOverlayAlpha = overlayStartAlpha + (overlayEndAlpha - overlayStartAlpha) * p
        overlayEl:SetAlpha(curOverlayAlpha)
        overlayEl._aishAnimAlpha = curOverlayAlpha
        if overlayHome then
          applyTransform(overlayVisualEl, overlayHome, ovlSlideX, ovlSlideY, p, overlayStartScale + (overlayEndScale - overlayStartScale) * p)
        end
        if elapsed >= overlaySpec.duration then
          overlayEl:SetAlpha(overlayEndAlpha)
          overlayEl._aishAnimAlpha = nil
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

-- Anime l'arc actif + son overlay, et l'arc de stagger Brasseur avec la même spec si actif.
local function AnimateArcOverlay(shouldShow)
  if not bar then return end

  local cfg = ns.GetCfg("resourceCircle")
  local radial = cfg.radialFillTest == true
  local arcEl      = radial and bar.radialFillFrame or bar.arc
  local otherArcEl = radial and bar.arc or bar.radialFillFrame
  if otherArcEl then otherArcEl:Hide() end

  -- Slide/scale de l'overlay principal appliqués à la texture bar.overlay (ancrée CENTER), pas à bar.overlayFrame (SetAllPoints, pas de pivot exploitable).
  AnimateArcOverlayPair("main", shouldShow, arcEl, bar.overlayFrame, bar.overlay)

  -- Arc de stagger (Moine Brasseur) : structurellement identique à l'arc principal, donc exactement la même animation.
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

  -- Recalcule timing/courbe/mouvement de chaque slot depuis CIRCLE_ANIM selon la direction (show/hide peuvent différer complètement).
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
    -- Géométrie de repos pré-calculée (RecordHome) plutôt que relue via GetPoint/GetSize : fiable même en combat.
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
    if previewMode then
      rcAnimBusy = false
      return
    end
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
    rcAnimBusy = false
    if rcAnimDirty then
      rcAnimDirty = false
      ResourceCircle.UpdateVisibility()
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

  -- SetPreview est un override manuel : interruption immediate voulue (contrairement a UpdateVisibility).
  -- Remet aussi rcAnimBusy a plat, sinon il resterait bloque a true (son onComplete vient d'etre annule).
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end
  if moveTicker then moveTicker:Cancel(); moveTicker = nil end
  rcAnimBusy = false
  rcAnimDirty = false

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
    -- Texte de ressource secondaire visible en preview seulement si la spé a une définition.
    -- Reset explicite d'alpha/position : un pop-out interrompu peut laisser secResFrame à alpha 0.
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
    -- Respecter le mode radial en preview aussi, sinon l'arc vertical réapparaîtrait par-dessus le disque radial
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
      -- Met à jour les sliders X/Y du panneau de réglages (même convention que Skyriding.lua).
      local xSl = _G["AishCoreRCPosXSlider"]
      local ySl = _G["AishCoreRCPosYSlider"]
      if xSl then xSl:SetValue(newX) end
      if ySl then ySl:SetValue(newY) end
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
  if ns._rcAnimDebug then
    print(string.format("|cff88ffff[RCAnim]|r %.3f UpdateVisibility shouldShow=%s lastState=%s skyridingActive=%s inCombat=%s%s",
      GetTime(), tostring(shouldShow), tostring(lastVisibilityState), tostring(ns.skyridingActive),
      tostring(UnitAffectingCombat("player")),
      (lastVisibilityState == shouldShow) and " (no-op)" or " (TRANSITION)"))
  end
  if lastVisibilityState == shouldShow then return end

  -- Ne jamais interrompre une transition en cours : note juste la demande (rcAnimDirty), rappelée
  -- automatiquement une fois l'animation en cours terminée (cf. onComplete d'AnimateVisibility).
  if rcAnimBusy then
    rcAnimDirty = true
    return
  end
  lastVisibilityState = shouldShow
  rcAnimBusy = true

  if shouldShow then
    bar:Show()
    -- L'arc et l'overlay ont leur propre animation dédiée (timing/easing différents), voir AnimateArcOverlay
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
    -- Arc de stagger : Show()/alpha déjà gérés par AnimateArcOverlay ci-dessus, juste rafraîchir valeur/couleur.
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
    -- Pas de Hide() immédiat pour secResFrame/staggerArc : leur fondu animé (AnimateVisibility /
    -- AnimateArcOverlay) les cache déjà sur leur propre timing.
    local SE = ns.Modules and ns.Modules.SpellEffects
    if SE and SE.StopAllSustained then SE.StopAllSustained() end
    AnimateArcOverlay(false)
    ResourceCircle.AnimateVisibility(false)
  end
end

-- Forward-déclaré : vraie définition plus bas, requise par Update() ci-dessous pour Mage Givre.
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

  -- Fire Mage (spec 63) : afficher directement 0/1/2 au lieu de la mana (cache ns._playerClass/ns._specIndex).
  if ns._playerClass == "MAGE" and ns._specIndex == 2 then  -- spec 2 = Fire
    displayText = tostring(fireProcLevel)
  end

  ApplyArcValue(pct)

  -- Mage Givre (specID 64) : texte affiche les stacks de Glaçons (205473), arc reste sur la mana. Lit ns.AuraText.ICICLES directement, ApplyStacksToText échoue pour ce spellID.
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

-- Secondary Dots : cercles secondaires (DK runes, Combo Points, etc.)

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
  -- Warlock Démonologie (Coeur démoniaque) : orbes désactivées, lecture des stacks via GetPlayerAuraBySpellID peu fiable en combat.
  -- Stacks affichés via le texte de ressource secondaire (SecondaryResourceDefs[266]) qui passe par le canal clone-stack CDM à la place.
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

-- Ressource secondaire : texte sous le cercle (Bone Shield, Soul Fragments…)

-- Couleurs par défaut de l'arc de durée central (dupliqué de CenterArc.lua/SettingsPanel.lua pour éviter un couplage cross-module).
local ARC_DEFAULT_COLORS = {
  [66]  = { 1.00, 0.88, 0.10 },  -- Paladin Prot : Consécration
  [73]  = { 0.78, 0.25, 0.25 },  -- Guerrier Prot : Dur au mal
  [250] = { 0.20, 0.78, 0.35 },  -- DK Sang : Death's Due (188290)
}

-- Couleur courante de l'arc de durée pour une spec : override utilisateur sinon couleur par défaut ; aligne le texte de ressource secondaire sur l'arc quand ils représentent la même ressource.
local function GetDurationArcColor(specID)
  local r = ns.GetSecResCfg("durationArcColorR", specID)
  if r then
    return { r, ns.GetSecResCfg("durationArcColorG", specID) or 1, ns.GetSecResCfg("durationArcColorB", specID) or 1, 1 }
  end
  return ARC_DEFAULT_COLORS[specID]
end

-- Réapplique uniquement la géométrie dépendante de la spec (arc de durée, texte ressource secondaire), séparée d'ApplySettings pour ne pas interférer avec la visibilité combat.
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

    -- Priorité : override utilisateur > couleur de l'arc de durée si même ressource > def.color > repli "powerdotsb". Ici (pas DetectSecondaryResource) pour rester live via BindColorButton.
    local userR = ns.GetSecResCfg("secResColorR", specID)
    local c
    if userR then
      c = { userR, ns.GetSecResCfg("secResColorG", specID) or 1, ns.GetSecResCfg("secResColorB", specID) or 1, 1 }
    elseif secResDef then
      local CLR = ns.Modules.Colors
      c = (secResDef.useAbsorb and GetDurationArcColor(specID)) or secResDef.color or (CLR and CLR.Get("powerdotsb"))
    end
    if c then bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
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

  -- Désabonner l'ancien canal clone-stack avant d'en choisir un nouveau, sinon un vieux spellID resterait abonné indéfiniment.
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

  -- Abonner bar.secResText au canal clone-stack (CDMHooks) : ApplyStacksToText échoue en combat pour certains sorts, ce canal reste fiable.
  if def.useStacks and def.spellID and ns.Auras and ns.Auras.SubscribeCDMAuraStack then
    _secResStackSubIDs = { def.spellID }
    ns.Auras.SubscribeCDMAuraStack(def.spellID, "resourceCircleSecRes", bar.secResText)
    if def.altSpellID then
      _secResStackSubIDs[#_secResStackSubIDs + 1] = def.altSpellID
      ns.Auras.SubscribeCDMAuraStack(def.altSpellID, "resourceCircleSecRes", bar.secResText)
    end
    -- Marque ces spellID "stack capable" dès l'init pour éviter le blacklistage croisé par le tracker d'auras générique.
    if ns.Auras.MarkStackCapable then
      ns.Auras.MarkStackCapable(def.spellID)
      if def.altSpellID then ns.Auras.MarkStackCapable(def.altSpellID) end
    end
  end

  -- Démarrer le ticker de mise à jour (0.1s suffit pour ce type de ressource)
  secResUpdateTicker = C_Timer.NewTicker(0.1, function()
    ResourceCircle.UpdateSecondaryResource()
  end)

  -- Réapplique la géométrie de spec sans passer par ApplySettings() complet (perturberait lastVisibilityState).
  ResourceCircle.RefreshSecResSpecGeometry(specID)
end

-- GetPlayerAuraBySpellID() peu fiable pour certaines auras ; ns.Auras.cdmData fait référence. Valeur possiblement secrète en combat : jamais de concat/format dessus, juste SetText brut.
-- Pop (fade+slide) sur bar.secResFrame au passage 0 -> 1+ stack en combat, détecté via le booléen `applied` (jamais la valeur réelle). Durée dédiée, séparée de CIRCLE_ANIM.secResText.
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

-- Symétrique de StartSecResPop : transition 1+ -> 0 stack en combat, cache le texte/déco
-- une fois le fondu terminé (pas avant, sinon rien à voir disparaître).
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

-- Teste val == 0 sans planter si val est une secret value ; si la comparaison échoue, considère "pas confirmé zéro" et affiche quand même. Même helper que dans PriorityBar.lua.
local function IsConfirmedZero(val)
  if val == nil then return false end
  local ok, isZero = pcall(function() return val == 0 end)
  return ok and isZero == true
end

-- Cherche les stacks d'une ressource secondaire via CDM puis fallbacks (GetPlayerAuraBySpellID, énumération HELPFUL, GetSpellCastCount) ;
-- valeur transmise brute à sink (jamais de tonumber/comparaison, potentiellement secrète en combat), partagé entre SetText et SetValue.
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
    -- aura.applications d'abord : GetAuraApplicationDisplayCount peut renvoyer nil pour une aura
    -- pourtant présente avec un vrai compte lisible via applications (ex: Glaçons/205473).
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

  -- Fallback 2 : énumération des auras HELPFUL ; comparaison spellId protégée par pcall (secret en combat).
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 60 do
      local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      -- ok3=false = cette position est secrète, pas "fin de liste" -- continuer, pas de break.
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

  -- Pas de fallback GetSpellCastCount ici : répond count=0 pour le spellID d'un buff. Voir ApplyCastCountToText (secResDef.castCountSpellID).
  return false
end

-- Pas de "local" ici : assigne l'upvalue forward-déclarée avant Update().
function ApplyStacksToText(fontString, spellID, dbg)
  return ApplyStacksTo(function(v) return pcall(fontString.SetText, fontString, v) end, spellID, dbg)
end

-- Exposé pour réutilisation par les stacks d'icônes (Debuffs.lua/Cooldowns.lua/Procs.lua).
ResourceCircle.ApplyStacksTo = ApplyStacksTo

-- Équivalent de ApplyStacksTo pour un debuff de la cible (CDM puis énumération HARMFUL). Utilisé par Mage Givre (specID 64, debuff 1246769).
local function ApplyTargetStacksTo(sink, spellID, dbg)
  if not UnitExists("target") then return false end
  local A = ns.Auras
  local cdmTarget = A and A.cdmData and A.cdmData.target
  local cdmEntry = cdmTarget and cdmTarget[spellID]
  if cdmEntry and cdmEntry.instID then
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if dbg then dbg.cdm = { ok = ok, disp = disp } end
    if ok and disp ~= nil then
      -- Instance confirmée vivante : si le compte n'est pas exploitable (debuff à application
      -- unique), affiche "1" plutôt que d'échouer -- la présence seule reste une info utile.
      local value = (not IsConfirmedZero(disp)) and disp or 1
      if sink(value) then if dbg then dbg.path = "cdm" end; return true end
    end
    -- Instance périmée (cdmData jamais purgé) : tombe dans le fallback ci-dessous.
  end

  -- Fallback : énumération des auras HARMFUL de la cible (comparaison spellId protégée par pcall).
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

-- Compteur natif Blizzard sur un bouton d'action (certains sorts Mistweaver sans buff associé, ex Don de Sheilun/Thé de Mana), appelé seulement si secResDef.castCountSpellID est défini explicitement.
-- GetText/GetStringWidth sur button.Count restent lisibles sans planter (count==0 lui-même plante en combat) et permettent de détecter un bouton vide. Bouton retrouvé via le cache de PriorityBar.lua.
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

-- Aucun signal fiable pour distinguer "0" de "3" en combat : affiche la valeur réelle (IsConfirmedZero filtre hors combat), sauf si IsActionCountConfirmedHidden a tranché via le bouton natif.
local function ApplyCastCountToText(fontString, spellID)
  if not (C_Spell and C_Spell.GetSpellCastCount) then return false end
  if IsActionCountConfirmedHidden(spellID) then return false end
  local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
  if not ok or count == nil or IsConfirmedZero(count) then return false end
  return pcall(fontString.SetText, fontString, count)
end

-- Absorb restant via UnitGetTotalAbsorbs (AuraData.points est une secret table en combat, indexer plante) ; présence via IsCDMAuraSwipePresent, repli GetPlayerAuraBySpellID
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

  -- Option "grand nombre" (10000 -> "10k") : AbbreviateNumbers accepte les secret numbers, résultat passé brut à SetText (même pattern que ShortenHP/SetHPText).
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
  -- Le texte secondaire doit partager la visibilité du cercle central : secResFrame est parenté à UIParent (pas à bar, pour ses animations de pop indépendantes), donc ne suit pas bar:Hide() automatiquement.
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
    -- Repli compteur bouton d'action (ex: Thé de Mana 115294), uniquement si explicitement défini pour ce spec (cf. ApplyCastCountToText).
    if not applied and secResDef.castCountSpellID then
      applied = ApplyCastCountToText(bar.secResText, secResDef.castCountSpellID)
    end
    -- Repli présence via IsCDMAuraSwipePresent (même signal que ApplyAbsorbToText) quand les 3 tiers de ApplyStacksToText échouent (ex Bouclier d'os/195181) ; le texte est déjà poussé par le clone-stack.
    local A = ns.Auras
    if not applied and A and A.IsCDMAuraSwipePresent
       and (A.IsCDMAuraSwipePresent(secResDef.spellID)
            or (secResDef.altSpellID and A.IsCDMAuraSwipePresent(secResDef.altSpellID))) then
      applied = true
    end
    -- Transitions 0 <-> 1+ stack en combat : petit pop fade+slide, cf. StartSecResPop/StartSecResPopOut. `applied` est un simple booléen, jamais la valeur secrète.
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    -- Le pop-out cache lui-même texte/déco une fois le fondu terminé ; SetSecResShown(false) immédiat ne s'applique que si aucun pop-out n'est en cours.
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif secResDef.useTargetDebuff and secResDef.spellID then
    -- Debuff de la cible (Mage Givre/specID 64, Config/ResourceMap.lua) -- même logique de pop-in/pop-out que useStacks, via ApplyTargetStacksToText.
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

-- Arc de stagger (Moine Brasseur specID 268)
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
  -- Cercle central caché : masquer le texte de stagger en même temps, sinon il restait bloqué affiché à "0%" hors combat.
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

  -- Arithmétique protégée séparément de l'appel API : stagAmt peut être secret en combat, une division non protégée plante silencieusement toute la fonction (le ticker avale l'erreur).
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

-- Arc de durée dans le cercle central. SetCenterArcEntry(entry) : appelé par CenterArc.lua avec entry.durObj/entry.spellColor. SetTimerDuration anime à 60fps côté Blizzard.
local INTERP_IMMED = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local TIMER_DRAIN  = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local _lastArcDurRef = nil  -- tostring(durObj) : change à chaque cast/refresh

function ResourceCircle.SetCenterArcEntry(entry)
  if not bar or not bar.durationArc then return end
  if entry and entry.durObj then
    -- Le durObj est recréé à chaque cast (même refresh) → tostring() change toujours ; SetTimerDuration ne tourne que pour un nouveau durObj.
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
    -- Chemin CDM : SetTimerDuration(nil) uniquement si on avait un durObj actif, sinon ça peut corrompre l'état de la StatusBar.
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

-- Mode "absorb" de l'arc de durée (Dur Au Mal, cfg.ignorePainArcAbsorb) : remplissage proportionnel à une valeur/max génériques plutôt qu'au temps restant. `value` peut être secret : aucune arithmétique, passé brut à SetValue (même pattern que UpdateAbsorb dans UnitBars.lua).
function ResourceCircle.SetCenterArcFill(value, maxValue, color)
  if not bar or not bar.durationArc then return end
  if not maxValue or maxValue <= 0 then return end
  if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
  bar.durationArc:SetMinMaxValues(0, maxValue)
  ns.SmoothSetValue(bar.durationArc, value)
  bar.durationArc:SetAlpha(1); bar.durationArc:Show()
  if bar.durationOvlFrame then bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show() end
end

-- Mode "cdmbar" (durée combat-safe, CDMHooks.lua) : relais brut vers bar.durationArc, sans comparaison sur lo/hi/value (hi peut être secret en combat), sauf hi==0 (envoyé en clair à l'expiration du buff).
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

-- Proxy "clone-bar" : expose l'interface StatusBar attendue par ns.SubscribeCDMAuraBar sans être une vraie StatusBar, redirige vers bar.durationArc (ResourceCircle garde la main sur son widget).
ResourceCircle.centerArcBarProxy = {
  SetMinMaxValues = function(_, lo, hi) ResourceCircle.SetCenterArcBarMinMax(lo, hi) end,
  SetValue        = function(_, value) ResourceCircle.SetCenterArcBarValue(value) end,
  Show            = function() end,
}

-- Remplit l'arc secondaire central depuis une aura stackable, en réutilisant la même chaîne CDM + fallbacks que le texte de ressource secondaire (specs à arc "stacks" lues via une aura, ex DH Dévoreur).
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

-- Accesseur debug (/rcarc dans CenterArc.lua) : bar.durationArc/durationArcFrame sont locaux à ce fichier.
function ResourceCircle._debug_GetDurationArc()
  return bar and bar.durationArc, bar and bar.durationArcFrame
end

-- Frame d'animation slide pour les secondary dots (même logique que Skyriding)
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
-- Debug : /rcoverlay — log tous les spell overlay events en temps réel
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

-- /rcanimlog -- trace en direct UpdateVisibility et AnimateArcOverlayPair pour recouper avec /aishdebug sky (Skyriding.lua, mêmes horodatages GetTime()).
SLASH_RCANIMLOG1 = "/rcanimlog"
SlashCmdList["RCANIMLOG"] = function()
  ns._rcAnimDebug = not ns._rcAnimDebug
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[RCAnim]|r logging " .. (ns._rcAnimDebug and "|cff00ff00ON|r" or "|cffff4444OFF|r")
    .. " -- reproduire (atterrir + combat), puis /aishdebug sky pour la sequence Skyriding correspondante.")
end

-- /rcradial — bascule à chaud entre remplissage vertical et radial, persiste dans le profil (cfg.radialFillTest)
SLASH_RCRADIAL1 = "/rcradial"
SlashCmdList["RCRADIAL"] = function()
  local cfg = ns.GetCfg("resourceCircle")
  cfg.radialFillTest = not cfg.radialFillTest
  -- ApplySettings() (pas juste ApplyRadialMode()) : re-synchronise aussi SetSize/SetPoint de bar.arc, qu'ApplyRadialMode seule ne corrige pas (Show/Hide/alpha/scale uniquement).
  ResourceCircle.ApplySettings()
  local state = cfg.radialFillTest and "|cff00ff00RADIAL|r" or "|cff88ccffVERTICAL (défaut)|r"
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[ResourceCircle]|r Remplissage : " .. state)
end

-- Debug : dump complet de l'état de bar.arc, appelable à tout moment.
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

-- Debug : /rcaura — dump toutes les auras HELPFUL du joueur
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

-- Debug : /rcsecres — état complet du texte de ressource secondaire
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
        -- Pas de lecture de aura.applications/aura.points ici : indexer un champ secret jette une erreur qui tainte le reste de la fonction.
        local okD1, dispD1 = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, foundInstID, 1, 999)
        p(string.format("GetAuraApplicationDisplayCount(1,999) ok=%s value=%s type=%s", tostring(okD1), tostring(dispD1), type(dispD1)))
      end
    end
    -- altSpellID (ex Fragments de vide 1227702, DH Dévoreur) : teste comme UpdateSecondaryResource, en priorité avant le spellID normal.
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
      -- Diagnostic du bouton natif (IsActionCountConfirmedHidden), à collecter en combat pour savoir pourquoi le gate IsShown() ne masque pas le "0".
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
    -- Chemin cible (Mage Givre, Config/ResourceMap.lua) : diagnostic séparé du bloc joueur, trompeur ici puisque le debuff n'est jamais sur "player".
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
    -- Énumération HARMFUL brute de la cible, seulement hors combat (la comparaison spellId plante en combat, cf. ApplyStacksTo).
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
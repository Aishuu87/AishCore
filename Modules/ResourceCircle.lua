-- Modules/ResourceCircle.lua : Cercle de ressource primaire (dynamique par classe/spec)
local addonName, ns = ...

local ResourceCircle = {}
ns.Modules.ResourceCircle = ResourceCircle

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
local SEC_DOT_TEX     = "Interface\\AddOns\\Aishaddon\\Media\\Skyriding\\Circle_Smooth"
local SEC_SLIDE_SPEED = 9.0    -- vitesse de slide (units/s)
local SEC_SLIDE_SCALE = 1.55   -- facteur de départ (× plus loin du centre)
local secDotAnims     = {}     -- [i] = { progress, target }
local secAnimFrame    = nil    -- frame dédié à l'animation slide des sec dots

-- Ressource secondaire (texte sous le cercle : Bone Shield, Soul Fragments, etc.)
local secResDef        = nil   -- définition active (ou nil)
local secResUpdateTicker = nil -- ticker de mise à jour
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

-- Verifie si les elements doivent etre visibles (en combat uniquement)
function ResourceCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideResourceCircle ~= false then return false end
  local cfg = ns.GetCfg("resourceCircle")
  if cfg.enabled == false then return false end
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
  end
  local arcPx     = size * (cfg.arcSizeRatio or 1.0)
  local overlayPx = arcPx * (cfg.overlayRatio or 0.75)
  bar.arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  bar.arc:ClearAllPoints()
  bar.arc:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  if bar.overlay then
    if overlayPx >= 2 then
      bar.overlay:SetSize(overlayPx, overlayPx)
      bar.overlay:Show()
      if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    else
      bar.overlay:Hide()
    end
  end
  -- Redimensionner l'arc de stagger quand les settings changent
  if bar.staggerArc then
    local stagArcPx = arcPx * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
    bar.staggerArc:SetSize(stagArcPx, stagArcPx * ARC_CROP_H)
    bar.staggerArc:ClearAllPoints()
    bar.staggerArc:SetPoint("TOP", bar, "CENTER", 0, stagArcPx / 2)
    if bar.staggerOverlay then
      local stagOvPx = stagArcPx * (cfg.staggerOverlayRatio or STAGGER_OVERLAY_RATIO)
      if stagOvPx >= 2 then bar.staggerOverlay:SetSize(stagOvPx, stagOvPx) end
    end
  end
  if bar.durationArc then
    local durArcPx = arcPx * (cfg.durationArcRatio or DURATION_ARC_RATIO)
    bar.durationArc:SetSize(durArcPx, durArcPx * ARC_CROP_H)
    bar.durationArc:ClearAllPoints()
    bar.durationArc:SetPoint("TOP", bar, "CENTER", 0, durArcPx / 2)
    if bar.durationOvl then
      local durOvPx = durArcPx * (cfg.durationArcOverlayRatio or DURATION_ARC_OVL_RATIO)
      if durOvPx >= 2 then bar.durationOvl:SetSize(durOvPx, durOvPx) end
    end
  end
  bar.text:SetFont(cfg.font or ns.Media.font, cfg.fontSize)
  -- Texte de ressource secondaire : taille police + position
  if bar.secResText then
    bar.secResText:SetFont(cfg.secResFont or FONT_BOLD_ITALIC, cfg.secResTextSize or 11, "")
  end
  if bar.secResFrame and bar.text then
    bar.secResFrame:ClearAllPoints()
    bar.secResFrame:SetPoint("TOP", bar.text, "BOTTOM",
      cfg.secResTextOffsetX or 0,
      cfg.secResTextOffsetY or -2)
  end
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
    end
  end
  -- Appliquer les couleurs de la ressource active
  ResourceCircle.UpdateResourceColors()
  -- Re-detecter les secondary dots (option allSpecs, spec change)
  ResourceCircle.DetectSecondaryDots()
  -- Repositionner les secondary dots (runes, combo points)
  ResourceCircle.LayoutSecDots()

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

  bar = CreateFrame("Frame", "AishaddonRingBar", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetPoint("CENTER", parent, "CENTER", cfg.x, cfg.y)

  -- Glow de fond (DERRIERE bgLarge, sublevel -1)
  local bgGlow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  bgGlow:SetTexture("Interface\\AddOns\\Aishaddon\\Circle_Smooth2.tga")
  bgGlow:SetBlendMode("ADD")
  bgGlow:SetDesaturated(true)
  local glowPixelSize = math.floor((cfg.size * 1.1) * (cfg.glowSize or 1.0) + 0.5)
  bgGlow:SetSize(glowPixelSize, glowPixelSize)
  bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgGlow:SetAlpha(cfg.glowOpacity or 0.85)
  if cfg.glowEnabled == false then bgGlow:Hide() end
  bar.bgGlow = bgGlow

  -- Grand fond opaque
  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  bgLarge:SetTexture(ns.Media.circle)
  bgLarge:SetSize(cfg.bgSize, cfg.bgSize)
  bgLarge:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge

  -- Arc (remplissage bas -> haut, texture circulaire pre-croppee)
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  local arc = CreateFrame("StatusBar", "AishaddonRingBarArc", bar)
  arc:SetFrameLevel(bar:GetFrameLevel() + 1)
  arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  arc:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  arc:SetStatusBarTexture("Interface\\AddOns\\Aishaddon\\Media\\circle_piecrop.tga")
  arc:SetOrientation("VERTICAL")
  arc:SetMinMaxValues(0, 100)
  arc:SetValue(0)
  arc:Show()
  bar.arc = arc

  -- Overlay sombre : masque le centre pour simuler un arc en anneau
  local overlayPx = arcPx * (cfg.overlayRatio or 0.75)
  local overlayFrame = CreateFrame("Frame", nil, bar)
  overlayFrame:SetFrameLevel(arc:GetFrameLevel() + 1)
  overlayFrame:SetAllPoints(bar)
  local overlay = overlayFrame:CreateTexture(nil, "ARTWORK")
  overlay:SetTexture(ns.Media.circle)
  if overlayPx >= 2 then overlay:SetSize(overlayPx, overlayPx) else overlay:Hide() end
  overlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  overlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.overlay = overlay
  bar.overlayFrame = overlayFrame

  -- Arc de stagger (Moine Brasseur) : s'inscrit dans le trou laissé par l'overlay principal
  local staggerFrame = CreateFrame("Frame", nil, bar)
  staggerFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  staggerFrame:SetAllPoints(bar)

  local staggerArcPx = arcPx * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
  local staggerArc = CreateFrame("StatusBar", nil, staggerFrame)
  staggerArc:SetFrameLevel(staggerFrame:GetFrameLevel())
  staggerArc:SetSize(staggerArcPx, staggerArcPx * ARC_CROP_H)
  staggerArc:SetPoint("TOP", bar, "CENTER", 0, staggerArcPx / 2)
  staggerArc:SetStatusBarTexture("Interface\\AddOns\\Aishaddon\\Media\\circle_piecrop.tga")
  staggerArc:SetOrientation("VERTICAL")
  staggerArc:SetMinMaxValues(0, 100)
  staggerArc:SetValue(0)
  staggerArc:SetStatusBarColor(STAGGER_LIGHT[1], STAGGER_LIGHT[2], STAGGER_LIGHT[3], 1)
  staggerArc:Hide()
  bar.staggerArc   = staggerArc
  bar.staggerFrame = staggerFrame

  local staggerOverlayFrame = CreateFrame("Frame", nil, bar)
  staggerOverlayFrame:SetFrameLevel(staggerFrame:GetFrameLevel() + 1)
  staggerOverlayFrame:SetAllPoints(bar)
  local staggerOverlay = staggerOverlayFrame:CreateTexture(nil, "ARTWORK")
  staggerOverlay:SetTexture(ns.Media.circle)
  local staggerOverlayPx = staggerArcPx * (cfg.staggerOverlayRatio or STAGGER_OVERLAY_RATIO)
  if staggerOverlayPx >= 2 then staggerOverlay:SetSize(staggerOverlayPx, staggerOverlayPx) end
  staggerOverlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  staggerOverlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  staggerOverlayFrame:Hide()
  bar.staggerOverlay      = staggerOverlay
  bar.staggerOverlayFrame = staggerOverlayFrame

  -- Arc de durée (Pala Prot / Guerrier Prot / DK Sang) : parallèle au stagger, mutuellement exclusif
  -- Arc de durée (même approche que stagger : StatusBar + circle_piecrop.tga)
  local durationArcPx = arcPx * (cfg.durationArcRatio or DURATION_ARC_RATIO)
  local durationArcFrame = CreateFrame("Frame", nil, bar)
  durationArcFrame:SetFrameLevel(staggerFrame:GetFrameLevel())
  durationArcFrame:SetAllPoints(bar)
  local durationArcBar = CreateFrame("StatusBar", nil, durationArcFrame)
  durationArcBar:SetFrameLevel(durationArcFrame:GetFrameLevel())
  durationArcBar:SetSize(durationArcPx, durationArcPx * ARC_CROP_H)
  durationArcBar:SetPoint("TOP", bar, "CENTER", 0, durationArcPx / 2)
  durationArcBar:SetStatusBarTexture("Interface\\AddOns\\Aishaddon\\Media\\circle_piecrop.tga")
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
  durationOvl:SetTexture(ns.Media.circle)
  local durationOvlPx = durationArcPx * (cfg.durationArcOverlayRatio or DURATION_ARC_OVL_RATIO)
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
  end

  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(ns.Media.font, cfg.fontSize)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  text:SetTextColor(unpack(cfg.textColor))
  bar.text = text
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

  -- Fond sombre sous le power text pour lisibilité (masqué pour Brasseur qui a son propre overlay)
  local textBackdrop = textFrame:CreateTexture(nil, "BACKGROUND")
  textBackdrop:SetTexture(ns.Media.circle)
  textBackdrop:SetSize(35, 35)
  textBackdrop:SetPoint("CENTER", bar, "CENTER", 0, 0)
  textBackdrop:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.textBackdrop = textBackdrop

  bar:Show()
  _G.AishaddonRingBar = bar

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

  -- Pré-allouer la table d'éléments pour AnimateVisibility (10 slots fixes + 2 staggerArc conditionnels).
  -- Les frame-refs sont stables après Create(). Les slots 11-12 ont element=nil par défaut.
  do
    local si = 0.05
    _rcAnimElems[1]  = { element = bar.bgGlow,           delay = 0        }
    _rcAnimElems[2]  = { element = bar.bgLarge,          delay = si       }
    _rcAnimElems[3]  = { element = bar.text,             delay = si * 2   }
    _rcAnimElems[4]  = { element = bar.arc,              delay = si * 3   }
    _rcAnimElems[5]  = { element = bar.overlayFrame,     delay = si * 3   }
    _rcAnimElems[6]  = { element = bar.dot3,             delay = si * 4   }
    _rcAnimElems[7]  = { element = bar.dot2,             delay = si * 5   }
    _rcAnimElems[8]  = { element = bar.dot4,             delay = si * 5   }
    _rcAnimElems[9]  = { element = bar.dot1,             delay = si * 6   }
    _rcAnimElems[10] = { element = bar.dot5,             delay = si * 6   }
    _rcAnimElems[11] = { element = nil,                  delay = si * 3.5 }  -- staggerArc
    _rcAnimElems[12] = { element = nil,                  delay = si * 3.5 }  -- staggerOverlayFrame
  end

  return bar
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

  -- Mettre à jour les slots conditionnels staggerArc (mutation en place, pas d'allocation)
  _rcAnimElems[11].element = (staggerActive and bar.staggerArc)          or nil
  _rcAnimElems[12].element = (staggerActive and bar.staggerOverlayFrame) or nil
  -- textBackdrop : fond décoratif, pas d'animation scale (évite le 3.5px au départ),
  -- show/hide géré directement dans le callback ci-dessous.
  -- Les secondary dots ont leur propre animation slide (secAnimFrame) : exclus du stagger principal

  -- Utiliser l'animation partagée
  animationTicker = ns.AnimateStagger(_rcAnimElems, shouldShow, duration, staggerInterval, function()
    if previewMode then return end
    if not shouldShow then
      bar:Hide()
      bar.arc:Hide()
      if bar.overlay then bar.overlay:Hide() end
      bar.bgLarge:Hide()
      bar.text:Hide()
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
    -- Texte de ressource secondaire : visible en preview si la spec active a une def
    if bar.secResFrame and bar.secResText then
      if secResDef then
        bar.secResText:SetText("- 8 -")
        bar.secResText:Show()
        bar.secResFrame:Show()
      else
        bar.secResText:Hide()
        bar.secResFrame:Hide()
      end
    end
    -- Valeur fictive pour visualiser
    bar.arc:SetValue(72)
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
      GameTooltip:SetText("Clic-glisser pour deplacer")
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
    bar.arc:Show(); bar.arc:SetAlpha(0)
    if bar.overlay then bar.overlay:Show() end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(0); bar.overlayFrame:SetScale(1) end
    bar.bgLarge:Show(); bar.bgLarge:SetAlpha(0)
    local cfg2 = ns.GetCfg("resourceCircle")
    if bar.bgGlow and cfg2.glowEnabled ~= false then bar.bgGlow:Show(); bar.bgGlow:SetAlpha(0) end
    bar.text:Show(); bar.text:SetAlpha(0)
    for i = 1, 5 do
      if bar["dot" .. i] then bar["dot" .. i]:Show(); bar["dot" .. i]:SetAlpha(0) end
    end
    -- Les sec dots réinitialisent leur progress pour recréer le slide-in
    for i = 1, secDotCount do
      if secDotAnims[i] then
        secDotAnims[i].progress = 0
        secDotAnims[i].target = 0
      end
    end
    -- Montrer le frame de ressource secondaire s'il y a une définition active
    if bar.secResFrame and secResDef then bar.secResFrame:Show() end
    -- Arc de stagger : montré seulement si Brasseur actif
    if staggerActive and bar.staggerArc then
      bar.staggerArc:Show(); bar.staggerArc:SetAlpha(0)
      if bar.staggerOverlayFrame then bar.staggerOverlayFrame:Show(); bar.staggerOverlayFrame:SetAlpha(0) end
      ResourceCircle.UpdateStagger()
    end
    -- textBackdrop : fond décoratif, apparaît immédiatement (pas dans le stagger)
    if bar.textBackdrop then bar.textBackdrop:Show(); bar.textBackdrop:SetAlpha(1) end
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
    -- textBackdrop : masqué immédiatement (pas dans le stagger)
    if bar.textBackdrop then bar.textBackdrop:Hide() end
    -- Déclencher le slide-out des sec dots
    for i = 1, secDotCount do
      if secDotAnims[i] then secDotAnims[i].target = 0 end
    end
    -- Cacher le frame de ressource secondaire
    if bar.secResFrame then bar.secResFrame:Hide() end
    -- Cacher l'arc de stagger
    if bar.staggerArc then bar.staggerArc:Hide() end
    if bar.staggerOverlayFrame then bar.staggerOverlayFrame:Hide() end
    -- Stopper les animations 3D soutenues immédiatement
    local SE = ns.Modules and ns.Modules.SpellEffects
    if SE and SE.StopAllSustained then SE.StopAllSustained() end
    ResourceCircle.AnimateVisibility(false)
  end
end

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
    bar.arc:SetValue(0)
    bar.text:SetText("-")
    return
  end

  -- Fire Mage (spec 63) : afficher directement 0/1/2 au lieu de la mana
  -- Utilise le cache ns._playerClass / ns._specIndex (mis a jour au login + spec change)
  if ns._playerClass == "MAGE" and ns._specIndex == 2 then  -- spec 2 = Fire
    displayText = tostring(fireProcLevel)
  end

  pcall(ns.SmoothSetValue, bar.arc, pct)
  pcall(bar.text.SetText, bar.text, displayText)
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
      local f = CreateFrame("Frame", "AishaddonSecDot" .. i, bar)
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

-- Détecte la ressource secondaire selon la spec active et démarre le ticker
function ResourceCircle.DetectSecondaryResource()
  if not bar then return end

  -- Arrêter l'ancien ticker
  if secResUpdateTicker then secResUpdateTicker:Cancel(); secResUpdateTicker = nil end
  secResDef = nil

  -- Cacher le texte de ressource secondaire
  if bar.secResText then bar.secResText:Hide() end

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

  -- Appliquer la couleur du texte secondaire :
  -- priorité à def.color (ex: Soul Fragments), sinon couleur powerdotsb de la spé (Colors module)
  if bar.secResText then
    local CLR = ns.Modules.Colors
    local c = def.color or (CLR and CLR.Get("powerdotsb"))
    if c then
      bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
  end

  -- Démarrer le ticker de mise à jour (0.1s suffit pour ce type de ressource)
  secResUpdateTicker = C_Timer.NewTicker(0.1, function()
    ResourceCircle.UpdateSecondaryResource()
  end)
end

function ResourceCircle.UpdateSecondaryResource()
  if not bar or not bar.secResText then return end
  if not secResDef then
    -- Le stagger Brewmaster peut utiliser secResText indépendamment : ne pas le masquer dans ce cas
    if not staggerActive then bar.secResText:Hide() end
    return
  end

  local count = nil

  if secResDef.useStacks and secResDef.spellID then
    -- Alt aura (ex: Fragments de vide sous Métamorphose du vide)
    if secResDef.altSpellID then
      local ok2, altAura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, secResDef.altSpellID)
      if ok2 and altAura then
        local altStacks = tonumber(tostring(altAura.applications))
        if altStacks and altStacks > 0 then count = altStacks end
      end
    end
    -- Aura stackable classique (fallback si pas d'alt aura active)
    if not count then
      local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, secResDef.spellID)
      if ok and aura then
        -- tonumber(tostring()) pour détainter le secret number en combat
        local stacks = tonumber(tostring(aura.applications))
        if stacks and stacks > 0 then count = stacks end
      end
    end
  elseif secResDef.useCharges and secResDef.spellID then
    -- Sort à charges : lecture via C_Spell.GetSpellCharges
    local ok, info = pcall(C_Spell.GetSpellCharges, secResDef.spellID)
    if ok and info then
      count = tonumber(tostring(info.currentCharges))
    end
  end

  if count and count > 0 then
    bar.secResText:SetText(string.format("- %d -", count))
    bar.secResText:Show()
  else
    bar.secResText:Hide()
  end
end

---------------------------------------------------------------------------
-- Arc de stagger (Moine Brasseur specID 268)
---------------------------------------------------------------------------
function ResourceCircle.DetectStagger()
  if not bar then return end
  staggerActive = false
  if staggerUpdateTicker then staggerUpdateTicker:Cancel(); staggerUpdateTicker = nil end
  if bar.staggerArc          then bar.staggerArc:Hide() end
  if bar.staggerOverlayFrame then bar.staggerOverlayFrame:Hide() end
  if not secResDef then
    if bar.secResText  then bar.secResText:Hide() end
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
  if not bar.staggerArc or not bar.staggerArc:IsShown() then return end
  local ok1, stagAmt = pcall(UnitStagger, "player")
  local ok2, maxHP   = pcall(UnitHealthMax, "player")
  if not ok1 or not ok2 or not maxHP or maxHP <= 0 then return end
  local pct = ((stagAmt or 0) / maxHP) * 100
  local color = pct < 30 and STAGGER_LIGHT or (pct < 60 and STAGGER_MODERATE or STAGGER_HEAVY)
  bar.staggerArc:SetStatusBarColor(color[1], color[2], color[3], 1)
  ns.SmoothSetValue(bar.staggerArc, math.min(pct, 100))

  -- Affichage optionnel du % sous le texte de ressource (même slot que DH Dévoreur)
  if bar.secResText and bar.secResFrame and not secResDef then
    local cfg = ns.GetCfg("resourceCircle")
    if cfg.staggerShowPercent then
      bar.secResFrame:Show()
      bar.secResText:SetText(string.format("%.1f%%", pct))
      bar.secResText:SetTextColor(color[1], color[2], color[3], 1)
      bar.secResText:Show()
    else
      bar.secResText:Hide()
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
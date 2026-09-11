-- Modules/HealthCircle.lua : Cercle de vie - hors combat quand blessé
local addonName, ns = ...
local L = ns.L

local HealthCircle = {}
ns.Modules.HealthCircle = HealthCircle

-- Références locales
local bar = nil
local healthAnimTicker = nil
local lastHealthVisState = nil
local previewMode = false
-- File d'attente de transition (meme principe que ResourceCircle.lua) : ne jamais interrompre une anim en cours
local hcAnimBusy = false
local hcAnimDirty = false

-- Variable pour savoir si le bar etait montre en preview (pour annuler l'anim)
local healthMoveTicker = nil
local _hcAnimElems = {}   -- pré-alloué une fois dans Create(), réutilisé à chaque animation

-- Battement de coeur OOC : pouls lent sur le bar global
local pulseTicker    = nil
local pulseStartTime = 0
local PULSE_CYCLE = 1.45  -- secondes par cycle (0.65s battement + 0.80s repos)
-- Keyframes : temps ABSOLU converti en fraction de PULSE_CYCLE
-- Battement actif sur 0→0.65s, repos 0.65→1.45s (vitesse du battement = v1 originale)
local PULSE_KEYS = {
  { t = 0.000, s = 1.000 },   -- repos  -> montée
  { t = 0.103, s = 1.008 },   -- pic 1 (battement principal)
  { t = 0.207, s = 1.002 },   -- creux inter-battement
  { t = 0.310, s = 1.006 },   -- pic 2 (plus doux)
  { t = 0.448, s = 1.000 },   -- retour repos
  { t = 1.000, s = 1.000 },   -- fin de cycle
}

local function EvalPulse(phase)
  -- phase dans [0, 1] ; interpolation smoothstep entre keyframes
  for i = 1, #PULSE_KEYS - 1 do
    local k0, k1 = PULSE_KEYS[i], PULSE_KEYS[i + 1]
    if phase <= k1.t then
      local span = k1.t - k0.t
      local lp   = (phase - k0.t) / span
      local ease = lp * lp * (3 - 2 * lp)   -- smoothstep
      return k0.s + (k1.s - k0.s) * ease
    end
  end
  return 1.0
end

local function StartPulse()
  if pulseTicker then return end
  local cfg = ns.GetCfg("healthCircle")
  if cfg.heartbeatPulse == false then return end
  pulseStartTime = GetTime()
  -- Ancrer le cercle par le BAS so qu'il grossisse vers le haut
  if bar._pulseAnchorX and bar._pulseHalfSize then
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", bar._pulseAnchorX, bar._pulseAnchorY - bar._pulseHalfSize)
  end
  pulseTicker = C_Timer.NewTicker(0.016, function()
    if not bar or not bar:IsShown() then return end
    local now = GetTime()
    local phase = ((now - pulseStartTime) % PULSE_CYCLE) / PULSE_CYCLE
    bar:SetScale(EvalPulse(phase))
    -- Stagger de l'overlay : légèrement en retard → la bague de couleur se révèle brièvement
    if bar.overlayFrame then
      local phaseOvl = ((now - pulseStartTime - 0.2 + PULSE_CYCLE) % PULSE_CYCLE) / PULSE_CYCLE
      bar.overlayFrame:SetScale(EvalPulse(phaseOvl))
    end
  end)
end

local function StopPulse()
  if pulseTicker then pulseTicker:Cancel(); pulseTicker = nil end
  if bar then
    bar:SetScale(1)
    if bar.overlayFrame then bar.overlayFrame:SetScale(1) end
    if bar.text then bar.text:SetAlpha(1) end
    if bar._pulseAnchorX then
      bar:ClearAllPoints()
      bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bar._pulseAnchorX, bar._pulseAnchorY)
    end
  end
end

-- Crop constant for circle_piecrop.tga (texture pre-croppee, bas transparent supprime)
local ARC_CROP_H = 0.88

-- Coeur central : taille fixe (px, avant application du scale global du cercle).
local HEART_SIZE = 8

-- Suivi de l'état "blessé" via événements (contourne les secret numbers)
local playerIsDamaged = false
local lastHealthChangeTime = 0

-- Frame de tracking des événements de vie
local healthTrackFrame = CreateFrame("Frame")
healthTrackFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
healthTrackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
healthTrackFrame:RegisterEvent("PLAYER_DEAD")
healthTrackFrame:RegisterEvent("PLAYER_UNGHOST")
healthTrackFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
healthTrackFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
local _hcInCombat = false
healthTrackFrame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_DISABLED" then
    _hcInCombat = true
    -- En entrant en combat, marquer comme blessé mais ne pas toucher au timer :
    -- le timer démarrera proprement à la fin du combat.
    playerIsDamaged = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    _hcInCombat = false
    -- Démarrer le compte à rebours hideDelay à partir de maintenant,
    -- quelle que soit l'activité UNIT_HEALTH pendant le combat.
    lastHealthChangeTime = GetTime()
  elseif event == "PLAYER_ENTERING_WORLD" then
    playerIsDamaged = true
    lastHealthChangeTime = GetTime()
  elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" then
    playerIsDamaged = false
    lastHealthChangeTime = 0
  elseif event == "UNIT_HEALTH" then
    -- Mettre à jour le timer uniquement hors combat.
    -- En combat, les soins/regen ne doivent pas repousser indéfiniment le délai.
    if not _hcInCombat then
      playerIsDamaged = true
      lastHealthChangeTime = GetTime()
    end
  end
end)

-- Vérifie si le cercle doit être visible (hors combat + blessé)
function HealthCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideHealthCircle ~= false then return false end
  local cfg = ns.GetCfg("healthCircle")
  if cfg.enabled == false then return false end
  -- Jamais affiche si la vraie barre de vie (UnitBars) l'est deja, sinon double affichage de la meme info
  local UB = ns.Modules and ns.Modules.UnitBars
  if UB and UB.IsPlayerBarShown and UB.IsPlayerBarShown() then return false end
  -- "Toujours actif en instance" : ignore les transitions combat tant qu'on
  -- est en donjon/raid (ns.inInstance, cf. Core.lua).
  if cfg.alwaysInInstance and ns.inInstance then return true end
  if UnitAffectingCombat("player") then return false end
  local vMode = cfg.visibilityMode or "important"
  if vMode == "always" then return true end
  -- "important" (default) : visible seulement quand le joueur est blesse
  local hideDelay = cfg and cfg.hideDelay or 1.5
  if playerIsDamaged and (GetTime() - lastHealthChangeTime) > hideDelay then
    playerIsDamaged = false
  end
  return playerIsDamaged
end

-- Applique les settings en live (taille, police, etc.)
function HealthCircle.ApplySettings()
  if not bar then return end
  local cfg = ns.GetCfg("healthCircle")

  -- Gerer l'activation/desactivation en live
  if cfg.enabled == false then
    if healthAnimTicker then healthAnimTicker:Cancel(); healthAnimTicker = nil end
    -- Desactivation live du module : interruption immediate voulue (comme
    -- SetPreview) -- on remet aussi le verrou de file d'attente a plat.
    hcAnimBusy = false
    hcAnimDirty = false
    bar:Hide()
    bar._healthShown = false
    lastHealthVisState = nil
    return
  end
  -- Forcer un re-check de visibilite (le module vient peut-etre d'etre reactive)
  lastHealthVisState = nil

  local size   = cfg.size
  local bgSize = size * 1.1
  bar:SetSize(size, size)
  bar.bgLarge:SetSize(bgSize, bgSize)
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
  bar.text:SetFont(cfg.font or ns.Media.font, cfg.fontSize)
  -- Couleurs via Colors.Get() en priorité, sinon depuis la config
  local CLR    = ns.Modules.Colors
  local arcC   = (CLR and CLR.Get("oochealth")) or cfg.barColor
  local dotC   = (CLR and CLR.Get("oocdot"))    or cfg.barColor
  local textC  = dotC  -- texte du cercle de vie = couleur OoC Dot
  bar.text:SetTextColor(textC[1], textC[2], textC[3], textC[4] or 1)
  if bar.arc then bar.arc:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1) end
  -- Redimensionner le coeur central proportionnellement
  local baseSize = ns.Defaults.healthCircle.size
  local scale = size / baseSize
  if bar.dot3 then
    bar.dot3:SetSize(HEART_SIZE * scale, HEART_SIZE * scale)
    bar.dot3:ClearAllPoints()
    bar.dot3:SetPoint("BOTTOM", bar, "BOTTOM", cfg.dotPositions[3][1] * scale, cfg.dotPositions[3][2] * scale)
    bar.dot3:SetVertexColor(dotC[1], dotC[2], dotC[3], 1)
  end
  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  bar:ClearAllPoints()
  local _ax = sw * cfg.anchorPctX + cfg.x
  local _ay = sh * cfg.anchorPctY + cfg.y
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", _ax, _ay)
  bar._pulseAnchorX  = _ax
  bar._pulseAnchorY  = _ay
  bar._pulseHalfSize = cfg.size / 2

  -- Forcer la visibilite apres changement de settings
  -- Si le pouls vient d'être désactivé, l'arrêter immédiatement
  if ns.GetCfg("healthCircle").heartbeatPulse == false then
    StopPulse()
  end
  if previewMode then
    HealthCircle.SetPreview(true)
  else
    HealthCircle.UpdateVisibility()
  end
end

function HealthCircle.Create(parent)
  if bar then return bar end
  local cfg = ns.GetCfg("healthCircle")

  bar = CreateFrame("Frame", "AishCoreHealthRing", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetFrameStrata("LOW")

  -- Position : bas gauche + offset
  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  local _bax = sw * cfg.anchorPctX + cfg.x
  local _bay = sh * cfg.anchorPctY + cfg.y
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", _bax, _bay)
  bar._pulseAnchorX  = _bax
  bar._pulseAnchorY  = _bay
  bar._pulseHalfSize = cfg.size / 2

  -- Grand fond opaque
  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  bgLarge:SetTexture(ns.Media.circle)
  bgLarge:SetSize(cfg.bgSize, cfg.bgSize)
  bgLarge:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge

  -- Arc (remplissage bas -> haut, texture circulaire pre-croppee)
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  local arc = CreateFrame("StatusBar", "AishCoreHealthRingArc", bar)
  arc:SetFrameLevel(bar:GetFrameLevel() + 1)
  arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  arc:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  arc:SetStatusBarTexture("Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  arc:SetStatusBarColor(unpack(cfg.barColor))
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

  -- Texte + dots sur un frame superieur a overlayFrame (sinon caches derriere l'overlay)
  local textFrame = CreateFrame("Frame", nil, bar)
  textFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  textFrame:SetAllPoints(bar)

  -- Coeur central (remplace les 5 dots) : au milieu, en bas du cercle hors combat.
  -- Reprend taille/position/couleur du dot central (index 3, le plus gros).
  local dot = textFrame:CreateTexture(nil, "OVERLAY")
  dot:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\heart.tga")
  dot:SetSize(HEART_SIZE, HEART_SIZE)
  dot:SetPoint("BOTTOM", bar, "BOTTOM", cfg.dotPositions[3][1], cfg.dotPositions[3][2])
  dot:SetVertexColor(cfg.dotColors[3][1], cfg.dotColors[3][2], cfg.dotColors[3][3], 1)
  bar.dot3 = dot

  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(ns.Media.font, cfg.fontSize)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  local CLR0 = ns.Modules.Colors
  local tc0  = (CLR0 and CLR0.Get("oocdot")) or cfg.textColor
  text:SetTextColor(tc0[1], tc0[2], tc0[3], tc0[4] or 1)
  bar.text = text
  bar.textFrame = textFrame
  ns.healthRingTextFrame = textFrame

  bar:Hide()

  -- Pré-allouer la table d'éléments pour AnimateVisibility (5 slots fixes).
  -- Les frame-refs (bar.arc, etc.) sont stables après Create() : on ne les recrée jamais.
  do
    local si = 0.04
    _hcAnimElems[1] = { element = bar.bgLarge,     delay = 0      }
    _hcAnimElems[2] = { element = bar.text,         delay = si * 1 }
    _hcAnimElems[3] = { element = bar.arc,          delay = si * 2 }
    _hcAnimElems[4] = { element = bar.overlayFrame, delay = si * 2 }
    _hcAnimElems[5] = { element = bar.dot3,         delay = si * 3 }
  end

  return bar
end

-- Animation stagger
function HealthCircle.AnimateVisibility(shouldShow)
  if healthAnimTicker then
    healthAnimTicker:Cancel()
    healthAnimTicker = nil
  end
  if not bar then return end

  if not shouldShow then
    StopPulse()   -- arrêter le pouls avant le fade-out
  end

  -- Synchroniser les décorations OOC SpellEffects avec le cercle (même durée totale)
  local se = ns.Modules.SpellEffects
  if se and se.AnimateOocDeco then
    se.AnimateOocDeco(shouldShow, 0.35 + 0.04 * 5)  -- durée totale = duration + maxDelay du stagger
  end

  -- Table pré-allouée dans Create() : aucune allocation ici
  healthAnimTicker = ns.AnimateStagger(_hcAnimElems, shouldShow, 0.35, 0.04, function()
    if previewMode then
      hcAnimBusy = false
      return
    end
    if not shouldShow then
      bar:Hide()
    else
      StartPulse()  -- démarrer le pouls une fois le cercle pleinement visible
    end
    hcAnimBusy = false
    if hcAnimDirty then
      hcAnimDirty = false
      HealthCircle.UpdateVisibility()
    end
  end)
end

-- Mode preview : force l'affichage du cercle pour le settings panel
function HealthCircle.SetPreview(on)
  previewMode = on
  if not bar then return end

  -- Annuler toute animation en cours (override manuel du panneau de reglages,
  -- pas une transition automatique -- interruption immediate voulue ici).
  if healthAnimTicker then healthAnimTicker:Cancel(); healthAnimTicker = nil end
  hcAnimBusy = false
  hcAnimDirty = false
  StopPulse()   -- arrêter le pouls quand on entre/sort du mode preview

  if on then
    lastHealthVisState = nil
    -- Respecter le toggle : ne pas forcer l'affichage si desactive. Masquage
    -- explicite (pas un simple return) : previewMode court-circuite
    -- UpdateVisibility, donc rien d'autre ne cacherait le cercle si le module
    -- vient d'etre coupe depuis la page "Modules" panneau ouvert.
    local cfgPrev = ns.GetCfg("healthCircle")
    if cfgPrev.enabled == false then
      bar:Hide()
      bar._healthShown = false
      return
    end
    -- Forcer l'affichage de tous les elements
    bar:Show()
    bar:SetAlpha(1)
    bar:SetScale(1)
    local elements = { bar.bgLarge, bar.text, bar.arc, bar.dot3 }
    for _, el in ipairs(elements) do
      if el then
        el:Show()
        el:SetAlpha(1)
        if el.SetScale then el:SetScale(1) end
      end
    end
    if bar.overlay then bar.overlay:Show(); bar.overlay:SetAlpha(1) end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    bar._healthShown = true
    -- Valeur fictive pour visualiser
    bar.arc:SetValue(72)
    bar.text:SetText("72")
  else
    lastHealthVisState = nil
    bar._healthShown = false
    HealthCircle.Update()
    HealthCircle.UpdateVisibility()
  end
end

-- Rend le cercle deplacable par drag (pour le mode settings)
function HealthCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      -- Calculer la position en pourcentage depuis BOTTOMLEFT
      local cx, cy = self:GetCenter()
      local sw = UIParent:GetWidth()
      local sh = UIParent:GetHeight()
      local newPctX = cx / sw
      local newPctY = cy / sh
      -- Sauvegarder en DB (pct pur, x/y = 0)
      if not ns.DB then ns.DB = {} end
      if not ns.DB.healthCircle then ns.DB.healthCircle = {} end
      ns.DB.healthCircle.anchorPctX = newPctX
      ns.DB.healthCircle.anchorPctY = newPctY
      ns.DB.healthCircle.x = 0
      ns.DB.healthCircle.y = 0
      -- Repositionner proprement
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw * newPctX, sh * newPctY)
      self._pulseAnchorX = sw * newPctX
      self._pulseAnchorY = sh * newPctY
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
function HealthCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = HealthCircle.ShouldShow()
  if lastHealthVisState == shouldShow then return end

  if hcAnimBusy then
    hcAnimDirty = true
    return
  end
  lastHealthVisState = shouldShow
  hcAnimBusy = true

  if shouldShow then
    bar:Show()
    bar.arc:Show()
    if bar.overlay then bar.overlay:Show() end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    bar.bgLarge:Show()
    bar.text:Show()
    if bar.dot3 then bar.dot3:Show() end
    if not bar._healthShown then
      bar._healthShown = true
      HealthCircle.AnimateVisibility(true)
    else
      -- Deja affiche, aucune anim ne sera lancee : remettre le verrou a plat ici pour ne pas bloquer les futures demandes
      hcAnimBusy = false
    end
  else
    bar._healthShown = false
    HealthCircle.AnimateVisibility(false)
  end
end

-- Met à jour les valeurs
function HealthCircle.Update()
  if not bar or not bar.text then return end
  if previewMode then return end
  if not bar:IsShown() then return end  -- skip si le cercle de vie n'est pas affiche
  local cfg = ns.GetCfg("healthCircle")

  local pct = UnitHealthPercent("player", true, CurveConstants.ScaleTo100)
  if not pct then
    bar.arc:SetValue(0)
    bar.text:SetText("-")
    return
  end

  local CLR2  = ns.Modules.Colors
  local arcC2 = (CLR2 and CLR2.Get("oochealth")) or cfg.barColor
  local txtC2 = (CLR2 and CLR2.Get("oocdot"))    or cfg.textColor
  if bar.arc then bar.arc:SetStatusBarColor(arcC2[1], arcC2[2], arcC2[3], arcC2[4] or 1) end
  bar.text:SetTextColor(txtC2[1], txtC2[2], txtC2[3], txtC2[4] or 1)

  pcall(ns.SmoothSetValue, bar.arc, pct)
  bar.text:SetText(format('%d', pct))
  -- UpdateVisibility est maintenant appelé par le ticker avant Update().
  -- On ne l'appelle plus ici pour éviter un double appel.
end

-- Reset
function HealthCircle.ResetVisibility()
  lastHealthVisState = nil
end

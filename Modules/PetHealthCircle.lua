-- Modules/PetHealthCircle.lua : Cercle de vie du familier - hors combat, quand le familier est blesse
-- 3e cercle hors combat (page "Cercles hors combat"), meme rendu que OutOfCombatResourceCircle.lua :
-- arc radial natif sur un disque plein, anneau creuse par un masque central, couleurs du cercle de vie.
local addonName, ns = ...
local L = ns.L

local PetHealthCircle = {}
ns.Modules.PetHealthCircle = PetHealthCircle

local DB_KEY = "petHealthCircle"
local UNIT   = "pet"

local bar = nil
local animTicker = nil
local lastVisState = nil
local previewMode = false
local ghostBuild = false        -- construction / rendu de la copie d'apercu du GUI (cf. CreateGhost)
local hiddenForGui = false      -- force-masquage GUI (meme principe que OutOfCombatResourceCircle.SetGuiHidden)
local animBusy, animDirty = false, false
local _animElems = {}
local colorsHooked = false

local VERTICAL_CROP_H = 0.88    -- ratio de hauteur de circle_piecrop.tga
local FILL_INVERSE = { cw = "ccw", ccw = "cw", mirror_out = "mirror_in", mirror_in = "mirror_out", vertical = "vertical" }

local function Cfg() return ns.GetCfg(DB_KEY) end

-- Masque central qui creuse l'anneau : trou = 1 - epaisseur (en fraction du diametre de l'arc).
local function OverlayPx(cfg, arcPx)
  local hole = 1 - (cfg.arcThickness or 0.25)
  return arcPx * math.max(0, math.min(hole, 0.995))
end

-- SetMinMaxValues enveloppe : le maximum est agrandi de 360/etendue pour que 0-100 % ne parcoure que l'arc.
local function SetupRadialArc(sb)
  ns.SetSmoothStatusBarTexture(sb, ns.Media.circle)
  sb:SetRenderMode(Enum.StatusBarRenderMode.Radial)
  local raw = sb.SetMinMaxValues
  sb._k = 1
  sb.SetMinMaxValues = function(self, lo, hi)
    self._ulo, self._uhi = lo, hi
    local k, scaled = self._k or 1, hi
    if k ~= 1 then
      local ok, v = pcall(function() return hi * k end)
      if ok then scaled = v end
    end
    raw(self, lo, scaled)
  end
end

local function SetArcAngle(sb, startDeg, endDeg, reverse)
  if not sb then return end
  local a0, a1 = tonumber(startDeg) or 220, tonumber(endDeg) or 140
  local span = (a1 - a0) % 360
  if span < 1 then span = 360 end
  local tex = sb:GetStatusBarTexture()
  if tex and tex.SetRadialProgressBarReverse then
    sb:SetReverseFill(false)
    tex:SetRadialProgressBarReverse(reverse and true or false)
  else
    sb:SetReverseFill(reverse and true or false)
  end
  if tex then tex:SetRotation(-math.rad(reverse and a1 or a0)) end
  local k = 360 / span
  if sb._k ~= k then
    sb._k = k
    pcall(sb.SetMinMaxValues, sb, sb._ulo or 0, sb._uhi or 100)
  end
end

local function ApplyArcAngles()
  if not bar then return end
  local cfg = Cfg()
  local mode = cfg.arcFillMode or "vertical"
  local inverted = cfg.arcFillInverted == true
  if inverted then mode = FILL_INVERSE[mode] or mode end
  local mirror = (mode == "mirror_out" or mode == "mirror_in")
  bar.arc:SetShown(mode ~= "vertical")
  bar.arc2:SetShown(mirror)
  bar.arcV:SetShown(mode == "vertical")
  bar.arcV:SetReverseFill(inverted)
  if mode == "vertical" then return end
  local a0, a1 = tonumber(cfg.arcStartAngle) or 220, tonumber(cfg.arcEndAngle) or 140
  if mirror then
    local half = math.max(1, math.min(a1, 180))
    local out = (mode == "mirror_out")
    SetArcAngle(bar.arc,  a0, a0 + half, not out)
    SetArcAngle(bar.arc2, a0 - half, a0, out)
  else
    SetArcAngle(bar.arc, a0, a1, mode == "ccw")
  end
end

local function ApplyArcValue(pct)
  pcall(ns.SmoothBarValue, bar.arc, pct)
  pcall(ns.SmoothBarValue, bar.arc2, pct)
  pcall(ns.SmoothBarValue, bar.arcV, pct)
end

-- Apercu anime (panneau de reglages ouvert)
local previewTicker = nil
local previewPct = 72
local function PreviewSweep()
  local t = (GetTime() % 5) / 2.5
  if t > 1 then t = 2 - t end
  return math.floor(t * t * (3 - 2 * t) * 100 + 0.5)
end
local function StopPreviewAnim()
  if previewTicker then previewTicker:Cancel(); previewTicker = nil end
  previewPct = 72
end

-- Etat "blesse" du familier : sa vie a bouge il y a moins de hideDelay secondes (meme notion que HealthCircle)
local petDamaged = false
local lastChange = 0
local inCombat = false

local track = CreateFrame("Frame")
track:RegisterUnitEvent("UNIT_HEALTH", UNIT)
track:RegisterUnitEvent("UNIT_MAXHEALTH", UNIT)
track:RegisterUnitEvent("UNIT_PET", "player")
track:RegisterEvent("PLAYER_ENTERING_WORLD")
track:RegisterEvent("PLAYER_REGEN_DISABLED")
track:RegisterEvent("PLAYER_REGEN_ENABLED")
track:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    inCombat = true
    petDamaged = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    inCombat = false
    lastChange = GetTime()
  elseif event == "UNIT_PET" or event == "PLAYER_ENTERING_WORLD" then
    petDamaged = true
    lastChange = GetTime()
    lastVisState = nil
  elseif not inCombat then
    petDamaged = true
    lastChange = GetTime()
  end
  if bar then
    PetHealthCircle.UpdateVisibility()
    PetHealthCircle.Update()
  end
end)

-- Vie pleine ? true / false / nil si illisible (valeur secrete) : comparaison protegee, cf. OutOfCombatResourceCircle
local function _CompareFull(cur, max) return max > 0 and cur >= max end
local function IsPetFull()
  local okC, cur = pcall(UnitHealth, UNIT)
  local okM, max = pcall(UnitHealthMax, UNIT)
  if not (okC and okM) or cur == nil or max == nil then return nil end
  local okCmp, full = pcall(_CompareFull, cur, max)
  if not okCmp then return nil end
  return full and true or false
end

function PetHealthCircle.IsPetInjured()
  local full = IsPetFull()
  if full ~= nil then return not full end
  local hideDelay = Cfg().hideDelay or 2.5
  if petDamaged and (GetTime() - lastChange) > hideDelay then petDamaged = false end
  return petDamaged
end

function PetHealthCircle.ShouldShow()
  if hiddenForGui then return false end
  if ns.IsInBlockedState() then return false end
  -- Meme interrupteur Skyriding que le cercle de vie du joueur
  if ns.skyridingActive and ns.GetCfg("skyriding").hideHealthCircle ~= false then return false end
  local cfg = Cfg()
  if cfg.enabled == false then return false end
  if not UnitExists(UNIT) or UnitIsDeadOrGhost(UNIT) then return false end
  -- En vehicule, "pet" designe le vehicule
  if UnitHasVehicleUI and UnitHasVehicleUI("player") then return false end
  if UnitAffectingCombat("player") then return false end
  if (cfg.visibilityMode or "important") == "always" then return true end
  return PetHealthCircle.IsPetInjured()
end

-- Rendu (taille, arcs, police, couleurs) du cercle `bar` : vrai cercle ou copie d'apercu
local function RenderVisual(cfg)
  local size = cfg.size
  bar:SetSize(size, size)
  bar.bgLarge:SetSize(size * 1.1, size * 1.1)
  local arcPx = size * (cfg.arcSizeRatio or 1.0)
  local overlayPx = OverlayPx(cfg, arcPx)
  for _, a in ipairs({ bar.arc, bar.arc2 }) do
    a:SetSize(arcPx, arcPx)
    a:ClearAllPoints()
    a:SetPoint("CENTER", bar, "CENTER", 0, 0)
  end
  bar.arcV:SetSize(arcPx, arcPx * VERTICAL_CROP_H)
  bar.arcV:ClearAllPoints()
  bar.arcV:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  if overlayPx >= 2 then
    bar.overlay:SetSize(overlayPx, overlayPx)
    bar.overlay:Show()
  else
    bar.overlay:Hide()
  end
  ApplyArcAngles()
  bar.text:SetFont(cfg.font or ns.FONT_FALLBACK, cfg.fontSize or 9)
  PetHealthCircle.UpdateColors()
end

-- Couleurs du cercle de vie (Couleurs Thematiques) : arc = "oochealth", texte = "oocdot"
function PetHealthCircle.UpdateColors()
  if not bar then return end
  local cfg = Cfg()
  local CLR = ns.Modules.Colors
  local arcC = (CLR and CLR.Get("oochealth")) or cfg.barColor
  local txtC = (CLR and CLR.Get("oocdot")) or cfg.barColor
  for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV }) do
    a:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1)
  end
  bar.text:SetTextColor(txtC[1], txtC[2], txtC[3], txtC[4] or 1)
end

local function Reposition()
  local cfg = Cfg()
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
    UIParent:GetWidth() * cfg.anchorPctX + (cfg.x or 0), UIParent:GetHeight() * cfg.anchorPctY + (cfg.y or 0))
end

function PetHealthCircle.ApplySettings()
  if not bar then return end
  local cfg = Cfg()
  if cfg.enabled == false then
    if animTicker then animTicker:Cancel(); animTicker = nil end
    animBusy, animDirty = false, false
    bar:Hide()
    lastVisState = nil
    return
  end
  lastVisState = nil
  RenderVisual(cfg)
  Reposition()
  if previewMode then
    PetHealthCircle.SetPreview(true)
  else
    PetHealthCircle.UpdateVisibility()
  end
end

function PetHealthCircle.Create(parent)
  if bar then return bar end
  local cfg = Cfg()

  bar = CreateFrame("Frame", not ghostBuild and "AishCorePetHealthRing" or nil, parent)
  bar:SetSize(cfg.size, cfg.size)
  -- MEDIUM comme le cercle de ressource hors combat : en LOW, n'importe quel cadre souris pose au-dessus
  -- (barres d'action...) volait le clic et le glisser-deposer ne partait jamais
  bar:SetFrameStrata("MEDIUM")

  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  ns.SetSmoothTexture(bgLarge, ns.Media.circle)
  bgLarge:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge

  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  local arcGroup = CreateFrame("Frame", nil, bar)
  arcGroup:SetFrameLevel(bar:GetFrameLevel() + 1)
  arcGroup:SetAllPoints(bar)
  bar.arcGroup = arcGroup
  local function NewRadial()
    local a = CreateFrame("StatusBar", nil, arcGroup)
    a:SetFrameLevel(arcGroup:GetFrameLevel())
    a:SetSize(arcPx, arcPx)
    a:SetPoint("CENTER", bar, "CENTER", 0, 0)
    SetupRadialArc(a)
    a:SetMinMaxValues(0, 100)
    a:SetValue(0)
    return a
  end
  bar.arc  = NewRadial()
  bar.arc2 = NewRadial()   -- 2e moitie des remplissages miroir
  local arcV = CreateFrame("StatusBar", nil, arcGroup)
  arcV:SetFrameLevel(arcGroup:GetFrameLevel())
  ns.SetSmoothStatusBarTexture(arcV, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  arcV:SetOrientation("VERTICAL")
  arcV:SetMinMaxValues(0, 100)
  arcV:SetValue(0)
  bar.arcV = arcV

  local overlayFrame = CreateFrame("Frame", nil, bar)
  overlayFrame:SetFrameLevel(arcGroup:GetFrameLevel() + 1)
  overlayFrame:SetAllPoints(bar)
  local overlay = overlayFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(overlay, ns.Media.circle)
  overlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  overlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.overlay = overlay
  bar.overlayFrame = overlayFrame

  local textFrame = CreateFrame("Frame", nil, bar)
  textFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  textFrame:SetAllPoints(bar)
  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(cfg.font or ns.FONT_FALLBACK, cfg.fontSize or 9)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bar.text = text
  bar.textFrame = textFrame

  RenderVisual(cfg)
  bar:Hide()
  if ghostBuild then return bar end

  Reposition()
  local si = 0.04
  _animElems[1] = { element = bar.bgLarge,      delay = 0 }
  _animElems[2] = { element = bar.text,         delay = si }
  _animElems[3] = { element = bar.arcGroup,     delay = si * 2 }
  _animElems[4] = { element = bar.overlayFrame, delay = si * 2 }

  -- Couleurs Thematiques : suivre leurs changements comme le cercle de vie
  local CLR = ns.Modules.Colors
  if not colorsHooked and CLR and CLR.RegisterCallback then
    colorsHooked = true
    CLR.RegisterCallback(function() pcall(PetHealthCircle.UpdateColors) end)
  end
  return bar
end

function PetHealthCircle.Update()
  if not bar or not bar.text then return end
  if previewMode then return end
  if not bar:IsShown() then return end
  if not UnitExists(UNIT) then return end
  local ok, pct = pcall(UnitHealthPercent, UNIT, false, CurveConstants.ScaleTo100)
  if not ok or pct == nil then
    ApplyArcValue(0)
    bar.text:SetText("-")
    return
  end
  ApplyArcValue(pct)
  pcall(function() bar.text:SetText(format("%d", pct)) end)
end

function PetHealthCircle.ResetVisibility()
  lastVisState = nil
end

function PetHealthCircle.AnimateVisibility(shouldShow)
  if animTicker then animTicker:Cancel(); animTicker = nil end
  if not bar then return end
  animTicker = ns.AnimateStagger(_animElems, shouldShow, 0.35, 0.04, function()
    if previewMode then animBusy = false; return end
    if not shouldShow then bar:Hide() end
    animBusy = false
    if animDirty then
      animDirty = false
      PetHealthCircle.UpdateVisibility()
    end
  end)
end

function PetHealthCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = PetHealthCircle.ShouldShow()
  if lastVisState == shouldShow then return end
  if animBusy then animDirty = true; return end
  lastVisState = shouldShow
  animBusy = true
  if shouldShow then
    bar:Show()
    bar.arcGroup:Show()
    bar.bgLarge:Show()
    bar.text:Show()
    bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1)
    PetHealthCircle.Update()
    PetHealthCircle.AnimateVisibility(true)
  else
    PetHealthCircle.AnimateVisibility(false)
  end
end

-- Mode apercu (panneau de reglages)
function PetHealthCircle.SetPreview(on)
  previewMode = on and true or false
  if not bar then return end
  if animTicker then animTicker:Cancel(); animTicker = nil end
  animBusy, animDirty = false, false
  StopPreviewAnim()
  lastVisState = nil
  if previewMode then
    if Cfg().enabled == false or hiddenForGui then bar:Hide(); return end
    bar:Show()
    bar:SetAlpha(1); bar:SetScale(1)
    for _, el in ipairs({ bar.bgLarge, bar.text, bar.arcGroup, bar.overlayFrame }) do
      el:Show(); el:SetAlpha(1)
      if el.SetScale then el:SetScale(1) end
    end
    ApplyArcValue(72)
    bar.text:SetText("72")
    previewTicker = ns.NewTicker(0.03, function()
      if not (bar and previewMode and bar:IsShown()) then return StopPreviewAnim() end
      previewPct = PreviewSweep()
      ApplyArcValue(previewPct)
      bar.text:SetText(tostring(previewPct))
    end)
  else
    PetHealthCircle.UpdateVisibility()
    PetHealthCircle.Update()
  end
end

function PetHealthCircle.SetGuiHidden(on)
  hiddenForGui = on and true or false
  lastVisState = nil
  if hiddenForGui and bar then
    StopPreviewAnim()
    if animTicker then animTicker:Cancel(); animTicker = nil end
    animBusy, animDirty = false, false
    bar:Hide()
    return
  end
  PetHealthCircle.UpdateVisibility()
end

function PetHealthCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
      local c = Cfg()
      if c and c.locked then return end
      self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local cx, cy = self:GetCenter()
      local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
      if not ns.DB then ns.DB = {} end
      if not ns.DB[DB_KEY] then ns.DB[DB_KEY] = CopyTable(ns.Defaults[DB_KEY]) end
      local db = ns.DB[DB_KEY]
      db.anchorPctX, db.anchorPctY, db.x, db.y = cx / sw, cy / sh, 0, 0
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    end)
    if not bar._dragBorder then
      local border = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      border:SetAllPoints(bar)
      border:SetColorTexture(1, 1, 1, 0.15)
      bar._dragBorder = border
    end
    bar._dragBorder:Hide()
    bar:SetScript("OnEnter", function(self)
      local c = Cfg()
      if not (c and c.locked) then self._dragBorder:Show() end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["RESOURCE_DRAG_TOOLTIP"])
      GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function(self)
      self._dragBorder:Hide()
      GameTooltip:Hide()
    end)
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

function PetHealthCircle.ResetPosition()
  if not ns.DB then ns.DB = {} end
  if not ns.DB[DB_KEY] then ns.DB[DB_KEY] = CopyTable(ns.Defaults[DB_KEY]) end
  local db, def = ns.DB[DB_KEY], ns.Defaults[DB_KEY]
  db.anchorPctX, db.anchorPctY, db.x, db.y = def.anchorPctX, def.anchorPctY, def.x, def.y
  PetHealthCircle.ApplySettings()
end

-- Copie d'apercu pour le GUI (page Cercles Hors Combat), cf. OutOfCombatResourceCircle.CreateGhost
function PetHealthCircle.CreateGhost(parent)
  local real = bar
  bar, ghostBuild = nil, true
  local ok, g = pcall(PetHealthCircle.Create, parent)
  bar, ghostBuild = real, false
  if not ok then geterrorhandler()(g); return nil end
  g:ClearAllPoints()
  local strata = parent:GetFrameStrata()
  local function Deep(f)
    f:SetFrameStrata(strata)
    for _, c in ipairs({ f:GetChildren() }) do Deep(c) end
  end
  Deep(g)
  g:Show()
  return g
end

function PetHealthCircle.RenderGhost(g, pct)
  if not g then return end
  local real = bar
  bar, ghostBuild = g, true
  local ok, err = pcall(function()
    RenderVisual(Cfg())
    ApplyArcValue(pct)
    g.text:SetText(tostring(pct))
  end)
  bar, ghostBuild = real, false
  if not ok then geterrorhandler()(err) end
end

function PetHealthCircle.SetGhostValue(g, pct)
  if not g then return end
  local real = bar
  bar = g
  pcall(ApplyArcValue, pct)
  bar = real
  g.text:SetText(tostring(pct))
end

-- Le panneau de reglages pilote le cercle de ressource hors combat en de nombreux endroits (apercu, masquage selon
-- la page, glisser-deposer) : le cercle du familier suit exactement les memes etats.
do
  local OCRC = ns.Modules.OutOfCombatResourceCircle
  if OCRC then
    for _, fn in ipairs({ "SetPreview", "SetGuiHidden", "SetDraggable" }) do
      if OCRC[fn] then
        hooksecurefunc(OCRC, fn, function(on) PetHealthCircle[fn](on) end)
      end
    end
  end
end

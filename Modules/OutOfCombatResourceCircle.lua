-- Modules/OutOfCombatResourceCircle.lua : Cercle de ressource hors combat
-- Meme fonctionnement que ResourceCircle mais visible UNIQUEMENT hors combat.
-- Pas de dots decoratifs (fond + arc + texte), secondary dots sans runes DK.

local addonName, ns = ...

local OutOfCombatResourceCircle = {}
ns.Modules.OutOfCombatResourceCircle = OutOfCombatResourceCircle

-- References locales
local bar               = nil
local animationTicker   = nil
local _ocrcAnimElems = {}   -- slots créés lazily au premier appel, réutilisés ensuite
local lastVisibilityState = nil
local previewMode       = false
local lastResourceType  = nil
local secDots           = {}
local secDotCount       = 0
local secUpdateTicker   = nil
local secDotType        = nil

-- Zone vide supprimee de circle_piecrop.tga (deja crop) : ratio hauteur restante
-- La texture croppee = arcPx de large x arcPx*ARC_CROP_H de haut, ancrage TOP
local ARC_CROP_H = 0.88

---------------------------------------------------------------------------
-- Suivi des changements de ressource via UNIT_POWER_FREQUENT
-- Evite toute arithmetique / comparaison ordonnee sur les secret numbers.
-- UnitPower() est tainté quand son argument l'est ; GetTime() est toujours propre.
---------------------------------------------------------------------------
local powerLastChanged = {}  -- ["MANA"], ["ENERGY"], ... -> GetTime()
local POWER_TIMEOUT    = 2.5 -- secondes sans changement => considere "plein"

do
  local tracker = CreateFrame("Frame")
  tracker:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  tracker:SetScript("OnEvent", function(_, _, _, powerToken)
    powerLastChanged[powerToken] = GetTime()
  end)
end

local function PowerChangedRecently(token)
  local t = powerLastChanged[token]
  return t ~= nil and (GetTime() - t) < POWER_TIMEOUT
end

---------------------------------------------------------------------------
-- Specs de soin + Mage Arcane (pour la logique mana)
---------------------------------------------------------------------------
local ARCANE_MAGE_SPEC = 62
local HEAL_SPECS = {
  [65]   = true,  -- Paladin Holy
  [256]  = true,  -- Priest Discipline
  [257]  = true,  -- Priest Holy
  [105]  = true,  -- Druid Restoration
  [264]  = true,  -- Shaman Restoration
  [270]  = true,  -- Monk Mistweaver
  [1468] = true,  -- Evoker Preservation
}

local function GetSpecID()
  if not GetSpecialization then return nil end
  local idx = GetSpecialization()
  if not idx then return nil end
  local id = GetSpecializationInfo(idx)
  return id
end

---------------------------------------------------------------------------
-- Visibilite : uniquement HORS combat, avec logique par ressource
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideOOCResourceCircle ~= false then return false end
  if UnitAffectingCombat("player") then return false end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")
  if cfg.enabled == false then return false end

  -- Mode de visibilite : "always" = afficher constamment hors combat
  if (cfg.visibilityMode or "important") == "always" then return true end

  local resource = ns.GetPlayerResource()

  -- ── Ressource aura (string key) ────────────────────────────────────────
  if type(resource) == "string" then
    -- MAELSTROM_WEAPON : montrer si stacks != 0
    if resource == "MAELSTROM_WEAPON" then
      return (ns.AuraStacks["MAELSTROM_WEAPON"] or 0) ~= 0
    end
    -- Autres auras : masquer par defaut hors combat
    return false
  end

  -- ── Ressources numeriques ─────────────────────────────────────────────────
  -- UnitPower() retourne un secret number dans certains contextes (valeur taintee
  -- par l'addon). Meme == / ~= contre une valeur non-nil leve une exception.
  -- SEULE operation safe : comparaison avec nil (== nil / ~= nil).
  --
  -- Solution : ne jamais toucher la valeur retournee par UnitPower dans ShouldShow.
  -- On se base uniquement sur UNIT_POWER_FREQUENT (stocke dans powerLastChanged)
  -- dont le timestamp (GetTime()) est toujours propre.
  --
  -- Semantique de PowerChangedRecently(token) :
  --   - Energie/focus/mana : l'event s'arrete quand la ressource est pleine
  --     => revient false quand plein   => cercle cache quand plein          [voulu]
  --   - Rage/fury/runic/etc. : l'event s'arrete quand la ressource est vide
  --     => revient false apres vidange => cercle cache quand vide           [voulu]
  --   - Combo points : le token est "COMBO_POINTS", fire a chaque changement

  -- Energie : en regen OU combo points OU chi en train de changer
  if resource == Enum.PowerType.Energy then
    return PowerChangedRecently("ENERGY") or PowerChangedRecently("COMBO_POINTS") or PowerChangedRecently("CHI")
  end

  -- Focus
  if resource == Enum.PowerType.Focus then
    return PowerChangedRecently("FOCUS")
  end

  -- Mana : uniquement heal / Arcane Mage
  if resource == Enum.PowerType.Mana then
    local specID = GetSpecID()
    if not specID or not (HEAL_SPECS[specID] or specID == ARCANE_MAGE_SPEC) then return false end
    return PowerChangedRecently("MANA")
  end

  -- Maelstrom (Elemental) : decroit OOC => event tourne tant que > 0
  if resource == Enum.PowerType.Maelstrom then
    return PowerChangedRecently("MAELSTROM")
  end

  -- Rage
  if resource == Enum.PowerType.Rage then
    return PowerChangedRecently("RAGE")
  end

  -- Fury
  if resource == Enum.PowerType.Fury then
    return PowerChangedRecently("FURY")
  end

  -- Insanity
  if resource == Enum.PowerType.Insanity then
    return PowerChangedRecently("INSANITY")
  end

  -- Runic Power
  if resource == Enum.PowerType.RunicPower then
    return PowerChangedRecently("RUNIC_POWER")
  end

  -- Lunar Power
  if resource == Enum.PowerType.LunarPower then
    return PowerChangedRecently("LUNAR_POWER")
  end

  -- Holy Power
  if resource == Enum.PowerType.HolyPower then
    return PowerChangedRecently("HOLY_POWER")
  end

  -- Soul Shards : se vident OOC => event tourne tant que > 0
  if resource == Enum.PowerType.SoulShards then
    return PowerChangedRecently("SOUL_SHARDS")
  end

  -- Essence (Evoker DPS)
  if resource == Enum.PowerType.Essence then
    return PowerChangedRecently("ESSENCE")
  end

  -- Fallback : toujours visible
  return true
end

---------------------------------------------------------------------------
-- Applique les settings en live
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.ApplySettings()
  if not bar then return end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")

  if cfg.enabled == false then
    if animationTicker then animationTicker:Cancel(); animationTicker = nil end
    bar:Hide()
    lastVisibilityState = nil
    return
  end
  lastVisibilityState = nil

  local size   = cfg.size
  local bgSize = size * 1.1

  bar:SetSize(size, size)
  bar.bgLarge:SetSize(bgSize, bgSize)
  -- Glow
  if bar.bgGlow then
    local glowEnabled = cfg.glowEnabled ~= false
    local glowPixelSize = math.floor(bgSize * (cfg.glowSize or 0.7) + 0.5)
    bar.bgGlow:SetSize(glowPixelSize, glowPixelSize)
    bar.bgGlow:ClearAllPoints()
    bar.bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.bgGlow:SetAlpha(cfg.glowOpacity or 0.7)
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
  bar.text:SetFont(cfg.font or ns.Media.font, cfg.fontSize)

  OutOfCombatResourceCircle.UpdateResourceColors()
  -- Re-detecter les secondary dots (option allSpecs, spec change)
  OutOfCombatResourceCircle.DetectSecondaryDots()
  OutOfCombatResourceCircle.LayoutSecDots()

  -- Repositionner
  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw * cfg.anchorPctX + cfg.x, sh * cfg.anchorPctY + cfg.y)

  if previewMode then
    OutOfCombatResourceCircle.SetPreview(true)
  else
    OutOfCombatResourceCircle.UpdateVisibility()
  end
end

---------------------------------------------------------------------------
-- Couleurs selon la ressource active
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.UpdateResourceColors()
  if not bar then return end
  local powerType = ns.GetPlayerResource()
  local colors    = ns.GetResourceColors(powerType)
  local CLR       = ns.Modules.Colors

  local arcC  = (CLR and CLR.Get("powercircle")) or colors.bar
  local textC = (CLR and CLR.Get("powertext"))   or colors.text

  if bar.arc then bar.arc:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1) end
  bar.text:SetTextColor(textC[1], textC[2], textC[3], textC[4] or 1)
  if bar.bgGlow and CLR then
    local glowC = CLR.Get("glow")
    if glowC then bar.bgGlow:SetVertexColor(glowC[1], glowC[2], glowC[3], 1) end
  end
  lastResourceType = powerType
end

-- Appele quand le type de ressource change
function OutOfCombatResourceCircle.OnResourceChanged()
  if not bar then return false end
  local powerType = ns.GetPlayerResource()
  if powerType == lastResourceType then return false end
  OutOfCombatResourceCircle.UpdateResourceColors()
  OutOfCombatResourceCircle.Update()
  OutOfCombatResourceCircle.DetectSecondaryDots()
  return true
end

---------------------------------------------------------------------------
-- Creation du cercle
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.Create(parent)
  if bar then return bar end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")

  bar = CreateFrame("Frame", "AishaddonOCResourceRing", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetFrameStrata("MEDIUM")

  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw * cfg.anchorPctX + cfg.x, sh * cfg.anchorPctY + cfg.y)

  -- Glow de fond (DERRIERE bgLarge, sublevel -1)
  local bgGlow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  bgGlow:SetTexture("Interface\\AddOns\\Aishaddon\\Circle_Smooth2.tga")
  bgGlow:SetBlendMode("ADD")
  bgGlow:SetDesaturated(true)
  local glowPixelSize = math.floor((cfg.size * 1.1) * (cfg.glowSize or 0.7) + 0.5)
  bgGlow:SetSize(glowPixelSize, glowPixelSize)
  bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgGlow:SetAlpha(cfg.glowOpacity or 0.7)
  if cfg.glowEnabled == false then bgGlow:Hide() end
  bar.bgGlow = bgGlow

  -- Fond opaque
  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  bgLarge:SetTexture(ns.Media.circle)
  bgLarge:SetSize(cfg.size * 1.1, cfg.size * 1.1)
  bgLarge:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge

  -- Arc (remplissage bas -> haut, texture circulaire pre-croppee)
  -- Frame non-carre : largeur=arcPx, hauteur=arcPx*ARC_CROP_H pour eviter le stretch
  -- Ancre au TOP de bar => le cercle visuel reste centre sur bar
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  local arc = CreateFrame("StatusBar", "AishaddonOCResourceRingArc", bar)
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
  overlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  overlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  if overlayPx >= 2 then overlay:SetSize(overlayPx, overlayPx) else overlay:Hide() end
  bar.overlay = overlay
  bar.overlayFrame = overlayFrame

  -- Texte (frame superieur a overlayFrame pour rester visible par-dessus)
  local textFrame = CreateFrame("Frame", nil, bar)
  textFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  textFrame:SetAllPoints(bar)
  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(ns.Media.font, cfg.fontSize)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bar.text = text
  bar.textFrame = textFrame

  bar:Hide()

  OutOfCombatResourceCircle.DetectSecondaryDots()
  OutOfCombatResourceCircle.UpdateResourceColors()

  return bar
end

---------------------------------------------------------------------------
-- Mise a jour des valeurs (copie de ResourceCircle.Update)
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.Update()
  if not bar or not bar.text then return end
  if previewMode then return end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")
  if cfg.enabled == false then return end
  if not bar:IsShown() then return end  -- skip si le cercle resource n'est pas affiche

  local resource    = ns.GetPlayerResource()
  local pct         = nil
  local displayText = nil

  if type(resource) == "string" then
    if ns.AuraResources and ns.AuraResources[resource] then
      local def = ns.AuraResources[resource]
      local auraData = C_UnitAuras.GetPlayerAuraBySpellID(def.spellID)
      if not auraData and (ns.AuraStacks[resource] or 0) > 0 then
        ns.AuraStacks[resource] = 0
        ns.AuraText[resource]   = "0"
        ns.AuraPct[resource]    = 0
      end
      pct         = ns.AuraPct[resource]  or 0
      displayText = ns.AuraText[resource] or "0"
    end
  else
    local ok, val = pcall(UnitPowerPercent, "player", resource, true, CurveConstants.ScaleTo100)
    if ok then
      pct = val
      local rawDef = ns.RawDisplayResources and ns.RawDisplayResources[resource]
      if rawDef then
        if rawDef.maxValue then
          displayText = string.format(rawDef.fmt, pct * rawDef.maxValue / 100)
        else
          local ok2, txt = pcall(string.format, rawDef.fmt, UnitPower("player", resource))
          displayText = ok2 and txt or string.format("%.0f", pct)
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

  pcall(ns.SmoothSetValue,  bar.arc,  pct)
  pcall(bar.text.SetText,   bar.text, displayText)
end

function OutOfCombatResourceCircle.ResetVisibility()
  lastVisibilityState = nil
end

---------------------------------------------------------------------------
-- Secondary Dots — combo points uniquement (pas de runes DK)
---------------------------------------------------------------------------
local SEC_COLORS = {
  COMBO_ROGUE = {
    default = { 1.0, 0.8, 0.0 },   -- jaune doré
    full    = { 1.0, 0.2, 0.0 },   -- rouge-orange quand max
  },
  COMBO_DRUID = {
    default = { 1.0, 0.55, 0.0 },  -- orange ambré (couleur druide)
    full    = { 1.0, 0.15, 0.0 },  -- rouge-orangé quand max
  },
  CHI = {
    default = { 0.0, 0.9, 0.6 },   -- turquoise jade
    full    = { 1.0, 1.0, 1.0 },   -- blanc quand max
  },
  HOLY_POWER = {
    default = { 1.0, 0.82, 0.0 },  -- or sacré
    full    = { 1.0, 1.00, 0.6 },  -- or brillant quand max
  },
  ESSENCE = {
    default = { 0.16, 0.82, 0.65 },  -- vert-émeraude (Evoker)
    full    = { 0.45, 1.00, 0.80 },  -- vert brillant quand max
  },
  ARCANE_CHARGES = {
    default = { 0.55, 0.25, 0.90 },  -- violet arcanique
    full    = { 0.65, 0.35, 1.00 },  -- violet brillant quand 4/4
  },
}
local SEC_DIM = 0.25

function OutOfCombatResourceCircle.DetectSecondaryDots()
  local _, playerClass = UnitClass("player")
  local newType  = nil
  local newCount = 0

  -- NOTE : DK non gere volontairement (pas de runes hors combat)
  if playerClass == "ROGUE" then
    newType  = "COMBO_ROGUE"
    local maxCP = UnitPowerMax("player", Enum.PowerType.ComboPoints)
    newCount = (maxCP and maxCP > 0) and maxCP or 5
  elseif playerClass == "DRUID" then
    local formID = GetShapeshiftFormID()
    if formID == DRUID_CAT_FORM then
      newType  = "COMBO_DRUID"
      local maxCP = UnitPowerMax("player", Enum.PowerType.ComboPoints)
      newCount = (maxCP and maxCP > 0) and maxCP or 5
    end
  elseif playerClass == "MONK" then
    local specID = GetSpecID()
    if specID == 269 then  -- Windwalker (seule spec utilisant Chi)
      newType  = "CHI"
      local maxChi = UnitPowerMax("player", Enum.PowerType.Chi)
      newCount = (maxChi and maxChi > 0) and maxChi or 5
    end
  elseif playerClass == "PALADIN" then
    local specID = GetSpecID()
    local cfg = ns.GetCfg("outOfCombatResourceCircle")
    local holyPowerAllSpecs = cfg and cfg.holyPowerAllSpecs
    if specID == 65 or (holyPowerAllSpecs and (specID == 66 or specID == 70)) then
      newType  = "HOLY_POWER"
      local maxHP = UnitPowerMax("player", Enum.PowerType.HolyPower)
      newCount = (maxHP and maxHP > 0) and maxHP or 5
    end
  elseif playerClass == "EVOKER" then
    local specID = GetSpecID()
    local cfg = ns.GetCfg("outOfCombatResourceCircle")
    local essenceAllSpecs = cfg and cfg.essenceAllSpecs
    if specID == 1468 or (essenceAllSpecs and (specID == 1473 or specID == 1467)) then
      newType  = "ESSENCE"
      local maxEss = UnitPowerMax("player", Enum.PowerType.Essence)
      newCount = (maxEss and maxEss > 0) and maxEss or 6
    end
  elseif playerClass == "MAGE" then
    local specID = GetSpecID()
    if specID == 62 then  -- Arcane
      newType  = "ARCANE_CHARGES"
      newCount = 4
    end
  end

  if newType == secDotType and newCount == secDotCount then return end

  if secUpdateTicker then secUpdateTicker:Cancel(); secUpdateTicker = nil end
  for i = 1, #secDots do
    if secDots[i] then secDots[i]:Hide() end
  end

  secDotType  = newType
  secDotCount = newCount

  if not secDotType or secDotCount == 0 then return end

  OutOfCombatResourceCircle.EnsureSecDotFrames(secDotCount)
  OutOfCombatResourceCircle.LayoutSecDots()
  OutOfCombatResourceCircle.UpdateSecDotColors()

  secUpdateTicker = C_Timer.NewTicker(0.016, function()
    OutOfCombatResourceCircle.UpdateSecDots()
  end)
end

function OutOfCombatResourceCircle.EnsureSecDotFrames(count)
  if not bar then return end
  for i = 1, count do
    if not secDots[i] then
      local f = CreateFrame("Frame", "AishaddonOCSecDot" .. i, bar)
      -- Doit etre au-dessus de overlayFrame : meme niveau que textFrame
      if bar.textFrame then f:SetFrameLevel(bar.textFrame:GetFrameLevel()) end
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetTexture(ns.Media.circle); bg:SetAllPoints()
      bg:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1); f.bg = bg
      local fill = f:CreateTexture(nil, "ARTWORK")
      fill:SetTexture(ns.Media.circle)
      fill:SetPoint("BOTTOM", f, "BOTTOM", 0, 0); f.fill = fill
      local border = f:CreateTexture(nil, "OVERLAY")
      border:SetTexture(ns.Media.circle); border:SetAllPoints()
      border:SetVertexColor(0.3, 0.3, 0.3, 0.3); f.border = border
      f.fillPct = 0
      secDots[i] = f
    end
    secDots[i]:Show()
  end
end

function OutOfCombatResourceCircle.LayoutSecDots()
  if not bar or secDotCount == 0 then return end
  local cfg       = ns.GetCfg("outOfCombatResourceCircle")
  local size      = cfg.size
  -- Lecture avec fallback per-dotType → global (Feature 5)
  local pfx = secDotType and ("secondaryDots_" .. secDotType .. "_") or ""
  local function pv(k, fallback) local v = pfx ~= "" and cfg[pfx..k] or nil; return v ~= nil and v or cfg[fallback] end
  local dotSize     = size * (pv("size",     "secondaryDotsSize")     or 0.16)
  local radius      = size * (pv("radius",   "secondaryDotsRadius")   or 0.62)
  local centerAngle =         pv("rotation", "secondaryDotsRotation") or 90
  local spread      =         pv("spread",   "secondaryDotsSpread")   or 24
  local revKey      = pfx ~= "" and cfg[pfx.."reversed"]
  local reversed    = revKey ~= nil and revKey or cfg.secondaryDotsReversed

  for i = 1, secDotCount do
    local f = secDots[i]
    if f then
      local idx    = reversed and (secDotCount + 1 - i) or i
      local offset = (idx - (secDotCount + 1) / 2) * spread
      local angle  = math.rad(centerAngle + offset)
      f:SetSize(dotSize, dotSize)
      f:ClearAllPoints()
      f:SetPoint("CENTER", bar, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
      f.fill:SetSize(dotSize, dotSize)
    end
  end
end

function OutOfCombatResourceCircle.UpdateSecDotColors()
  if secDotCount == 0 then return end
  local color
  if secDotType == "CHI" then
    color = SEC_COLORS.CHI.default
  elseif secDotType == "HOLY_POWER" then
    color = SEC_COLORS.HOLY_POWER.default
  elseif secDotType == "ESSENCE" then
    color = SEC_COLORS.ESSENCE.default
  elseif secDotType == "ARCANE_CHARGES" then
    color = SEC_COLORS.ARCANE_CHARGES.default
  elseif secDotType == "COMBO_DRUID" then
    color = SEC_COLORS.COMBO_DRUID.default
  else
    color = SEC_COLORS.COMBO_ROGUE.default
  end
  for i = 1, secDotCount do
    local f = secDots[i]
    if f and f.fill then
      f.fill:SetVertexColor(color[1], color[2], color[3], 1)
      f._baseColor = color
    end
  end
end

function OutOfCombatResourceCircle.UpdateSecDots()
  if secDotCount == 0 then return end
  if previewMode then return end -- ne pas écraser les valeurs forcées par SetPreview

  if secDotType == "COMBO_ROGUE" or secDotType == "COMBO_DRUID" then
    local ok, cp = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if not ok then cp = 0 end
    local maxCP      = secDotCount
    local palette    = SEC_COLORS[secDotType]
    local comboColor = palette.default
    local fullColor  = palette.full
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if i <= cp then
          f:Show()
          f.fill:SetHeight(f:GetHeight())
          if cp >= maxCP then
            f.fill:SetVertexColor(fullColor[1],  fullColor[2],  fullColor[3],  1)
          else
            f.fill:SetVertexColor(comboColor[1], comboColor[2], comboColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          f:Hide()
        end
      end
    end

  elseif secDotType == "CHI" then
    local ok, chi = pcall(UnitPower, "player", Enum.PowerType.Chi)
    if not ok then chi = 0 end
    local maxChi   = secDotCount
    local chiColor = SEC_COLORS.CHI.default
    local fullColor = SEC_COLORS.CHI.full
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if i <= chi then
          f:Show()
          f.fill:SetHeight(f:GetHeight())
          if chi >= maxChi then
            f.fill:SetVertexColor(fullColor[1],  fullColor[2],  fullColor[3],  1)
          else
            f.fill:SetVertexColor(chiColor[1], chiColor[2], chiColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          f:Hide()
        end
      end
    end
  elseif secDotType == "HOLY_POWER" then
    local ok, hp = pcall(UnitPower, "player", Enum.PowerType.HolyPower)
    if not ok then hp = 0 end
    local maxHP     = secDotCount
    local defColor  = SEC_COLORS.HOLY_POWER.default
    local fullColor = SEC_COLORS.HOLY_POWER.full
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if i <= hp then
          f:Show()
          f.fill:SetHeight(f:GetHeight())
          if hp >= maxHP then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          f:Hide()
        end
      end
    end
  elseif secDotType == "ESSENCE" then
    local ok, ess = pcall(UnitPower, "player", Enum.PowerType.Essence)
    if not ok then ess = 0 end
    local maxEss    = secDotCount
    local defColor  = SEC_COLORS.ESSENCE.default
    local fullColor = SEC_COLORS.ESSENCE.full
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if i <= ess then
          f:Show()
          f.fill:SetHeight(f:GetHeight())
          if ess >= maxEss then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          f:Hide()
        end
      end
    end
  elseif secDotType == "ARCANE_CHARGES" then
    local ok, ac = pcall(UnitPower, "player", Enum.PowerType.ArcaneCharges)
    if not ok then ac = 0 end
    local maxAC     = secDotCount
    local defColor  = SEC_COLORS.ARCANE_CHARGES.default
    local fullColor = SEC_COLORS.ARCANE_CHARGES.full
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if i <= ac then
          f:Show()
          f.fill:SetHeight(f:GetHeight())
          if ac >= maxAC then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          f:Hide()
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Animation apparition / disparition
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.AnimateVisibility(shouldShow)
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end
  if not bar then return end

  local si = 0.04
  -- Rebuild en place : les tables {element,delay} sont créées une seule fois, puis les champs sont mutés.
  -- Aucune allocation après le premier appel, même si secDotCount change.
  _ocrcAnimElems[1] = _ocrcAnimElems[1] or {}; _ocrcAnimElems[1].element = bar.bgGlow;       _ocrcAnimElems[1].delay = 0
  _ocrcAnimElems[2] = _ocrcAnimElems[2] or {}; _ocrcAnimElems[2].element = bar.bgLarge;      _ocrcAnimElems[2].delay = si
  _ocrcAnimElems[3] = _ocrcAnimElems[3] or {}; _ocrcAnimElems[3].element = bar.text;         _ocrcAnimElems[3].delay = si * 2
  _ocrcAnimElems[4] = _ocrcAnimElems[4] or {}; _ocrcAnimElems[4].element = bar.arc;          _ocrcAnimElems[4].delay = si * 3
  _ocrcAnimElems[5] = _ocrcAnimElems[5] or {}; _ocrcAnimElems[5].element = bar.overlayFrame; _ocrcAnimElems[5].delay = si * 3
  for i = 1, secDotCount do
    local slot = 5 + i
    _ocrcAnimElems[slot] = _ocrcAnimElems[slot] or {}
    _ocrcAnimElems[slot].element = secDots[i]
    _ocrcAnimElems[slot].delay   = si * (3 + i * 0.5)
  end
  -- Tronquer les slots excédentaires si secDotCount a diminué
  for i = secDotCount + 6, #_ocrcAnimElems do _ocrcAnimElems[i] = nil end

  animationTicker = ns.AnimateStagger(_ocrcAnimElems, shouldShow, 0.35, si, function()
    if previewMode then return end
    if not shouldShow then bar:Hide() end
  end)
end

---------------------------------------------------------------------------
-- Mode preview (settings panel)
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.SetPreview(on)
  previewMode = on
  if not bar then return end
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end

  if on then
    lastVisibilityState = nil
    local cfgPrev = ns.GetCfg("outOfCombatResourceCircle")
    -- Respecter le toggle : si desactive, ne pas forcer l'affichage en preview
    if cfgPrev.enabled == false then return end
    bar:Show()
    bar:SetAlpha(1); bar:SetScale(1)
    if bar.bgGlow then
      if cfgPrev.glowEnabled ~= false then
        bar.bgGlow:Show(); bar.bgGlow:SetAlpha(cfgPrev.glowOpacity or 0.7)
      else
        bar.bgGlow:Hide()
      end
    end
    local elems = { bar.bgLarge, bar.text, bar.arc }
    for i = 1, secDotCount do elems[#elems + 1] = secDots[i] end
    for _, el in ipairs(elems) do
      if el then
        el:Show(); el:SetAlpha(1)
        if el.SetScale then el:SetScale(1) end
      end
    end
    if bar.overlay then bar.overlay:Show(); bar.overlay:SetAlpha(1) end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    bar.arc:SetValue(72)
    bar.text:SetText("72")
  else
    lastVisibilityState = nil
    OutOfCombatResourceCircle.Update()
    OutOfCombatResourceCircle.UpdateVisibility()
  end
end

---------------------------------------------------------------------------
-- Drag (pour le settings panel)
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local cx, cy = self:GetCenter()
      local sw = UIParent:GetWidth()
      local sh = UIParent:GetHeight()
      local newPctX = cx / sw
      local newPctY = cy / sh
      if not ns.DB then ns.DB = {} end
      if not ns.DB.outOfCombatResourceCircle then ns.DB.outOfCombatResourceCircle = {} end
      ns.DB.outOfCombatResourceCircle.anchorPctX = newPctX
      ns.DB.outOfCombatResourceCircle.anchorPctY = newPctY
      ns.DB.outOfCombatResourceCircle.x = 0
      ns.DB.outOfCombatResourceCircle.y = 0
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw * newPctX, sh * newPctY)
    end)
    if not bar._dragBorder then
      local border = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      border:SetAllPoints(bar)
      border:SetColorTexture(1, 1, 1, 0.15)
      bar._dragBorder = border
    end
    bar._dragBorder:Show()
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
    bar:SetScript("OnDragStop",  nil)
    bar:SetScript("OnEnter",     nil)
    bar:SetScript("OnLeave",     nil)
    if bar._dragBorder then bar._dragBorder:Hide() end
  end
end

---------------------------------------------------------------------------
-- Reinitialise la position aux valeurs par defaut
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.ResetPosition()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.outOfCombatResourceCircle then ns.DB.outOfCombatResourceCircle = {} end
  local db  = ns.DB.outOfCombatResourceCircle
  local def = ns.Defaults.outOfCombatResourceCircle
  -- Copier explicitement les valeurs de position depuis les defaults
  db.anchorPctX = def.anchorPctX
  db.anchorPctY = def.anchorPctY
  db.x          = def.x
  db.y          = def.y
  OutOfCombatResourceCircle.ApplySettings()
end

---------------------------------------------------------------------------
-- Mise a jour de la visibilite
---------------------------------------------------------------------------
function OutOfCombatResourceCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = OutOfCombatResourceCircle.ShouldShow()
  if lastVisibilityState == shouldShow then return end
  lastVisibilityState = shouldShow

  if shouldShow then
    bar:Show()
    bar.arc:Show()
    bar.bgLarge:Show()
    bar.text:Show()
    if bar.overlay then bar.overlay:Show() end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    local cfgOC = ns.GetCfg("outOfCombatResourceCircle")
    if bar.bgGlow and cfgOC.glowEnabled ~= false then bar.bgGlow:Show() end
    for i = 1, secDotCount do
      if secDots[i] then secDots[i]:Show() end
    end
    OutOfCombatResourceCircle.AnimateVisibility(true)
  else
    OutOfCombatResourceCircle.AnimateVisibility(false)
  end
end

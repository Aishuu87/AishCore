-- Modules/OutOfCombatResourceCircle.lua : Cercle de ressource hors combat
-- Même fonctionnement que ResourceCircle, visible uniquement hors combat ; secondary dots sans runes DK.

local addonName, ns = ...
local L = ns.L

local OutOfCombatResourceCircle = {}
ns.Modules.OutOfCombatResourceCircle = OutOfCombatResourceCircle

-- References locales
local bar               = nil
local animationTicker   = nil
local _ocrcAnimElems = {}   -- slots créés lazily au premier appel, réutilisés ensuite
local lastVisibilityState = nil
local previewMode       = false
-- File d'attente de transition : ne jamais interrompre une animation show/hide en cours, relancer UpdateVisibility() apres
local ocrcAnimBusy = false
local ocrcAnimDirty = false
local lastResourceType  = nil
local secDots           = {}
local secDotCount       = 0
local secUpdateTicker   = nil
local secDotType        = nil
-- Force-masquage GUI (meme pattern que PriorityBar/UnitBars/TopTargetBar.SetGuiHidden) : masquage inconditionnel depuis le panneau de reglages
local ocrcHiddenForGui  = false

-- Arc en rendu radial natif (StatusBar:SetRenderMode(Radial)) sur un disque plein : meme systeme que ResourceCircle.lua.

-- Migration unique des anciens profils : "overlayRatio" (taille du trou) devient "arcThickness" (epaisseur de l'anneau,
-- fraction du diametre de l'arc), comme sur le cercle principal. Le rendu des profils existants est conserve.
function OutOfCombatResourceCircle.EnsureArcSettings()
  local cfg = ns.GetCfg("outOfCombatResourceCircle")
  if not cfg then return cfg end
  if not cfg.arcGeomV2 then
    cfg.arcThickness = math.max(0.01, math.min(1, 1.073 - (cfg.overlayRatio or 0.75)))
    cfg.arcGeomV2 = true
  end
  return cfg
end

-- Masque central qui creuse l'anneau : trou = 1 - epaisseur (en fraction du diametre de l'arc).
local function OverlayPx(cfg, arcPx)
  local hole = 1 - (cfg.arcThickness or 0.32)
  return arcPx * math.max(0, math.min(hole, 0.995))
end

-- SetMinMaxValues est enveloppe : le maximum est agrandi de 360/etendue pour que 0-100 % ne parcoure que l'arc
-- (etendue < 360).
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

-- Angles (degres, horaire, 0 = midi) : depart et fin de l'arc ; SetReverseFill inverse le sens du remplissage.
local function SetArcAngle(sb, startDeg, endDeg, reverse)
  if not sb then return end
  local a0, a1 = tonumber(startDeg) or 220, tonumber(endDeg) or 140
  local span = (a1 - a0) % 360
  if span < 1 then span = 360 end
  -- Rendu radial : le sens antihoraire se regle sur la texture geree (SetRadialProgressBarReverse, 12.1) ;
  -- StatusBar:SetReverseFill ne joue que sur l'axe lineaire. Repli sur ce dernier si l'API est absente.
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

-- Remplissage (cfg.arcFillMode) : "cw" / "ccw" (sens horaire / antihoraire), "mirror_out" (du milieu de l'arc vers
-- les extremites), "mirror_in" (des extremites vers le milieu), "vertical" (de bas en haut, ancien rendu).
-- Les miroirs utilisent deux arcs natifs, un par sens.
-- Miroirs : l'angle de depart est le POINT D'ORIGINE commun des deux arcs, l'angle de fin l'etendue maximale de CHAQUE arc
-- (0 a 180 deg). Depart 0 / fin 90 : l'arc droit va de midi a 3 h, l'arc gauche de midi a 9 h. "Sortant" : les deux
-- partent de l'origine ; "entrant" : ils partent des extremites et convergent vers l'origine.
local VERTICAL_CROP_H = 0.88   -- ratio de hauteur de circle_piecrop.tga (deja croppee)
-- "Remplissage inverse" (cfg.arcFillInverted) : horaire <-> antihoraire, miroir sortant <-> entrant, vertical de haut en bas.
local FILL_INVERSE = { cw = "ccw", ccw = "cw", mirror_out = "mirror_in", mirror_in = "mirror_out", vertical = "vertical" }

local function ApplyArcAngles()
  if not bar then return end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")
  local mode = cfg.arcFillMode or "cw"
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
    SetArcAngle(bar.arc,  a0, a0 + half, not out)   -- arc horaire : origine -> origine + etendue
    SetArcAngle(bar.arc2, a0 - half, a0, out)       -- arc antihoraire : origine -> origine - etendue
  else
    SetArcAngle(bar.arc, a0, a1, mode == "ccw")
  end
end

-- Apercu anime (panneau de reglages ouvert) : le remplissage va et vient de 0 a 100 %, pour juger le mode choisi.
local previewTicker = nil
local previewPct = 72
local function PreviewSweep()
  local t = (GetTime() % 5) / 2.5
  if t > 1 then t = 2 - t end
  return math.floor(t * t * (3 - 2 * t) * 100 + 0.5)   -- lissage aux extremites
end
local function StopPreviewAnim()
  if previewTicker then previewTicker:Cancel(); previewTicker = nil end
  previewPct = 72
end

-- Applique pct (0-100) aux arcs (lisse) ; les masques par ApplyArcAngles ne servent pas, la valeur est posee partout.
local function ApplyArcValue(pct)
  pcall(ns.SmoothBarValue, bar.arc, pct)
  pcall(ns.SmoothBarValue, bar.arc2, pct)
  pcall(ns.SmoothBarValue, bar.arcV, pct)
end

-- Suivi des changements via UNIT_POWER_FREQUENT (evite comparaison sur secret numbers, GetTime() reste propre)
local powerLastChanged = {}  -- ["MANA"], ["ENERGY"], ... -> GetTime()
local POWER_TIMEOUT    = 2.5 -- secondes sans changement => considere "plein"

do
  local tracker = CreateFrame("Frame")
  tracker:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  tracker:SetScript("OnEvent", function(_, _, _, powerToken)
    powerLastChanged[powerToken] = GetTime()
  end)
end

-- Delai propre a la mana. La regeneration reste bloquee environ cinq secondes apres une
-- incantation : pendant ce blocage aucun changement n'est signale, et le delai commun de 2,5 s
-- faisait conclure a tort que la mana etait pleine -- le cercle disparaissait, puis revenait des
-- la reprise de la regeneration. Cette fenetre couvre le blocage.
local MANA_TIMEOUT     = 6.5

local function PowerChangedRecently(token, timeout)
  local t = powerLastChanged[token]
  return t ~= nil and (GetTime() - t) < (timeout or POWER_TIMEOUT)
end

--- La ressource est-elle au maximum ? true / false / nil quand la lecture est impossible.
--- UnitPower peut renvoyer un nombre secret : la comparaison est donc faite dans un pcall, et
--- l'echec se traduit par nil -- "je ne sais pas" -- plutot que par une reponse inventee.
-- Fonction pre-allouee pour pcall : la comparaison doit rester protegee (valeurs secretes),
-- mais une closure ecrite sur place etait allouee a CHAQUE appel -- et cette fonction tourne
-- a chaque passage du ticker de visibilite. On passe donc les valeurs en arguments.
local function _CompareFull(cur, max)
  return max > 0 and cur >= max
end

local function IsPowerFull(powerType)
  local okC, cur = pcall(UnitPower, "player", powerType)
  local okM, max = pcall(UnitPowerMax, "player", powerType)
  if not (okC and okM) or cur == nil or max == nil then return nil end
  local okCmp, full = pcall(_CompareFull, cur, max)
  if not okCmp then return nil end
  return full and true or false
end

-- Specs de soin + Mage Arcane (logique mana en Retail ; Forever affiche la mana pour tous)
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
  if not ns.GetSpecialization then return nil end
  local idx = ns.GetSpecialization()
  if not idx then return nil end
  local id = ns.GetSpecializationInfo(idx)
  return id
end

-- Visibilite : uniquement HORS combat, avec logique par ressource
function OutOfCombatResourceCircle.ShouldShow()
  if ocrcHiddenForGui then return false end
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideOOCResourceCircle ~= false then return false end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")
  if cfg.enabled == false then return false end
  -- Ne jamais s'afficher si le cercle central (ResourceCircle) est deja visible (evite le double affichage)
  local RC = ns.Modules and ns.Modules.ResourceCircle
  if RC and RC.ShouldShow and RC.ShouldShow() then return false end
  if UnitAffectingCombat("player") then return false end

  -- Mode de visibilite : "always" = afficher constamment hors combat
  if (cfg.visibilityMode or "important") == "always" then return true end

  local resource = ns.GetPlayerResource()

  -- Ressource aura (string key)
  if type(resource) == "string" then
    -- MAELSTROM_WEAPON : montrer si stacks != 0
    if resource == "MAELSTROM_WEAPON" then
      return (ns.AuraStacks["MAELSTROM_WEAPON"] or 0) ~= 0
    end
    -- Autres auras : masquer par defaut hors combat
    return false
  end

  -- UnitPower() peut renvoyer un secret number (seule comparaison safe = nil) ; on se base sur PowerChangedRecently().

  -- Energie : en regen OU combo points OU chi en train de changer
  if resource == Enum.PowerType.Energy then
    return PowerChangedRecently("ENERGY") or PowerChangedRecently("COMBO_POINTS") or PowerChangedRecently("CHI")
  end

  -- Focus
  if resource == Enum.PowerType.Focus then
    return PowerChangedRecently("FOCUS")
  end

  -- Mana. Retail : uniquement soigneurs / mage Arcane, les autres specs n'en dependent pas.
  -- Forever : affichee pour TOUTES les specs, la mana y est la ressource principale de presque
  -- toutes les classes (seuls voleur, guerrier et druide selon sa forme y echappent) ; la
  -- restriction Retail y laissait le cercle vide pour la quasi-totalite des personnages.
  if resource == Enum.PowerType.Mana then
    if not ns.IsForever then
      local specID = GetSpecID()
      if not specID or not (HEAL_SPECS[specID] or specID == ARCANE_MAGE_SPEC) then return false end
      return PowerChangedRecently("MANA")
    end
    -- Forever : trois cas, du plus sur au moins sur.
    local full = IsPowerFull(Enum.PowerType.Mana)
    -- 1. Lecture possible et mana pleine : plus rien a surveiller, on masque tout de suite.
    if full == true then return false end
    -- 2. Lecture possible et mana incomplete : on affiche, sans attendre un changement de valeur.
    if full == false then return true end
    -- 3. Valeur illisible (nombre secret) : on retombe sur le signal de changement, avec la
    -- fenetre allongee qui couvre le blocage de regeneration.
    return PowerChangedRecently("MANA", MANA_TIMEOUT)
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

-- Applique les settings en live
function OutOfCombatResourceCircle.ApplySettings()
  OutOfCombatResourceCircle.EnsureArcSettings()
  if not bar then return end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")

  if cfg.enabled == false then
    if animationTicker then animationTicker:Cancel(); animationTicker = nil end
    -- Desactivation live du module : interruption immediate voulue, verrou de file remis a plat
    ocrcAnimBusy = false
    ocrcAnimDirty = false
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
  local overlayPx = OverlayPx(cfg, arcPx)
  for _, a in ipairs({ bar.arc, bar.arc2 }) do
    a:SetSize(arcPx, arcPx)
    a:ClearAllPoints()
    a:SetPoint("CENTER", bar, "CENTER", 0, 0)
  end
  bar.arcV:SetSize(arcPx, arcPx * VERTICAL_CROP_H)
  bar.arcV:ClearAllPoints()
  bar.arcV:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  if bar.overlay then
    if overlayPx >= 2 then
      bar.overlay:SetSize(overlayPx, overlayPx)
      bar.overlay:Show()
      if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    else
      bar.overlay:Hide()
    end
  end
  ApplyArcAngles()
  if previewMode then ApplyArcValue(previewPct) end
  ns.ApplyFontReliable(bar.text, "OOCText",
    function() local c = ns.GetCfg("outOfCombatResourceCircle"); return c and c.font or ns.Media.font end,
    function() local c = ns.GetCfg("outOfCombatResourceCircle"); return c and c.fontSize or cfg.fontSize end)

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

-- Couleurs selon la ressource active
function OutOfCombatResourceCircle.UpdateResourceColors()
  if not bar then return end
  local powerType = ns.GetPlayerResource()
  local colors    = ns.GetResourceColors(powerType)
  local CLR       = ns.Modules.Colors

  local arcC  = (CLR and CLR.Get("powercircle")) or colors.bar
  local textC = (CLR and CLR.Get("powertext"))   or colors.text

  for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV }) do
    a:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1)
  end
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

-- Creation du cercle
function OutOfCombatResourceCircle.Create(parent)
  OutOfCombatResourceCircle.EnsureArcSettings()
  if bar then return bar end
  local cfg = ns.GetCfg("outOfCombatResourceCircle")

  bar = CreateFrame("Frame", "AishCoreOCResourceRing", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetFrameStrata("MEDIUM")

  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw * cfg.anchorPctX + cfg.x, sh * cfg.anchorPctY + cfg.y)

  -- Glow de fond (DERRIERE bgLarge, sublevel -1)
  local bgGlow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  ns.SetSmoothTexture(bgGlow, "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga")
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
  ns.SetSmoothTexture(bgLarge, ns.Media.circle)
  bgLarge:SetSize(cfg.size * 1.1, cfg.size * 1.1)
  bgLarge:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge

  -- Arc en rendu radial natif sur un disque plein (carre) ; l'overlay creuse l'anneau
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)
  -- arcGroup : un seul element a afficher / animer, quel que soit le mode de remplissage (cf. ApplyArcAngles)
  local arcGroup = CreateFrame("Frame", nil, bar)
  arcGroup:SetFrameLevel(bar:GetFrameLevel() + 1)
  arcGroup:SetAllPoints(bar)
  bar.arcGroup = arcGroup
  local function NewRadial(name)
    local a = CreateFrame("StatusBar", name, arcGroup)
    a:SetFrameLevel(arcGroup:GetFrameLevel())
    a:SetSize(arcPx, arcPx)
    a:SetPoint("CENTER", bar, "CENTER", 0, 0)
    SetupRadialArc(a)
    a:SetMinMaxValues(0, 100)
    a:SetValue(0)
    return a
  end
  local arc = NewRadial("AishCoreOCResourceRingArc")
  bar.arc = arc
  bar.arc2 = NewRadial(nil)   -- 2e moitie des remplissages miroir
  -- Remplissage vertical (ancien rendu) : barre de bas en haut sur la texture pre-croppee
  local arcV = CreateFrame("StatusBar", nil, arcGroup)
  arcV:SetFrameLevel(arcGroup:GetFrameLevel())
  arcV:SetSize(arcPx, arcPx * VERTICAL_CROP_H)
  arcV:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  ns.SetSmoothStatusBarTexture(arcV, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  arcV:SetOrientation("VERTICAL")
  arcV:SetMinMaxValues(0, 100)
  arcV:SetValue(0)
  bar.arcV = arcV

  -- Overlay sombre : masque le centre pour simuler un arc en anneau
  local overlayPx = OverlayPx(cfg, arcPx)
  local overlayFrame = CreateFrame("Frame", nil, bar)
  overlayFrame:SetFrameLevel(arc:GetFrameLevel() + 1)
  overlayFrame:SetAllPoints(bar)
  local overlay = overlayFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(overlay, ns.Media.circle)
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
  ApplyArcAngles()

  return bar
end

-- Mise a jour des valeurs (copie de ResourceCircle.Update)
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
    ApplyArcValue(0)
    bar.text:SetText("-")
    return
  end

  ApplyArcValue(pct)
  pcall(bar.text.SetText,   bar.text, displayText)
end

function OutOfCombatResourceCircle.ResetVisibility()
  lastVisibilityState = nil
end

-- Secondary Dots — combo points uniquement (pas de runes DK)
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

  -- DK non géré volontairement (pas de runes hors combat)
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

  local secSkip = 0
  secUpdateTicker = ns.NewTicker(0.016, function()
    if lastVisibilityState ~= true then
      secSkip = secSkip + 1
      if secSkip % 15 ~= 0 then return end
    end
    OutOfCombatResourceCircle.UpdateSecDots()
  end)
end

function OutOfCombatResourceCircle.EnsureSecDotFrames(count)
  if not bar then return end
  for i = 1, count do
    if not secDots[i] then
      local f = CreateFrame("Frame", "AishCoreOCSecDot" .. i, bar)
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
  -- Lecture avec fallback per-dotType → global
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

-- Animation apparition / disparition
function OutOfCombatResourceCircle.AnimateVisibility(shouldShow)
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end
  if not bar then return end

  local si = 0.04
  -- Rebuild en place : tables {element,delay} créées une fois puis mutées (pas d'allocation apres le 1er appel)
  local arcEl = bar.arcGroup
  _ocrcAnimElems[1] = _ocrcAnimElems[1] or {}; _ocrcAnimElems[1].element = bar.bgGlow;       _ocrcAnimElems[1].delay = 0
  _ocrcAnimElems[2] = _ocrcAnimElems[2] or {}; _ocrcAnimElems[2].element = bar.bgLarge;      _ocrcAnimElems[2].delay = si
  _ocrcAnimElems[3] = _ocrcAnimElems[3] or {}; _ocrcAnimElems[3].element = bar.text;         _ocrcAnimElems[3].delay = si * 2
  _ocrcAnimElems[4] = _ocrcAnimElems[4] or {}; _ocrcAnimElems[4].element = arcEl;            _ocrcAnimElems[4].delay = si * 3
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
    if previewMode then
      ocrcAnimBusy = false
      return
    end
    if not shouldShow then bar:Hide() end
    ocrcAnimBusy = false
    if ocrcAnimDirty then
      ocrcAnimDirty = false
      OutOfCombatResourceCircle.UpdateVisibility()
    end
  end)
end

-- Mode preview (settings panel)
function OutOfCombatResourceCircle.SetPreview(on)
  previewMode = on
  if not bar then return end
  -- Override manuel du panneau de reglages : interruption immediate voulue, verrou de file remis a plat
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end
  ocrcAnimBusy = false
  ocrcAnimDirty = false
  StopPreviewAnim()

  if on then
    lastVisibilityState = nil
    local cfgPrev = ns.GetCfg("outOfCombatResourceCircle")
    -- Respecter le toggle : si desactive, ne pas forcer l'affichage en preview.
    -- Masquage explicite (pas un simple return) : previewMode court-circuite
    -- UpdateVisibility, qui ne cacherait donc jamais le cercle si le module
    -- vient d'etre coupe depuis la page "Modules" panneau ouvert.
    if cfgPrev.enabled == false then
      bar:Hide()
      return
    end
    bar:Show()
    bar:SetAlpha(1); bar:SetScale(1)
    if bar.bgGlow then
      if cfgPrev.glowEnabled ~= false then
        bar.bgGlow:Show(); bar.bgGlow:SetAlpha(cfgPrev.glowOpacity or 0.7)
      else
        bar.bgGlow:Hide()
      end
    end
    local elems = { bar.bgLarge, bar.text, bar.arcGroup }
    for i = 1, secDotCount do elems[#elems + 1] = secDots[i] end
    for _, el in ipairs(elems) do
      if el then
        el:Show(); el:SetAlpha(1)
        if el.SetScale then el:SetScale(1) end
      end
    end
    if bar.overlay then bar.overlay:Show(); bar.overlay:SetAlpha(1) end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    ApplyArcValue(72)
    bar.text:SetText("72")
    previewTicker = ns.NewTicker(0.03, function()
      if not (bar and previewMode and bar:IsShown()) then return StopPreviewAnim() end
      previewPct = PreviewSweep()
      ApplyArcValue(previewPct)
      bar.text:SetText(tostring(previewPct))
    end)
  else
    lastVisibilityState = nil
    OutOfCombatResourceCircle.Update()
    OutOfCombatResourceCircle.UpdateVisibility()
  end
end

-- Force-masquage GUI : masque inconditionnellement, meme hors combat (contrairement a SetPreview(false))
function OutOfCombatResourceCircle.SetGuiHidden(on)
  ocrcHiddenForGui = on and true or false
  lastVisibilityState = nil  -- forcer UpdateVisibility a reevaluer
  OutOfCombatResourceCircle.UpdateVisibility()
end

-- Drag (pour le settings panel)
function OutOfCombatResourceCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
      -- Verrou relu A CHAUD : le drag est arme des l'ouverture du panneau (plus de bouton dedie),
      -- donc la case "Verrouiller la position" est le seul frein -- meme modele que unitBars.
      local c = ns.GetCfg("outOfCombatResourceCircle")
      if c and c.locked then return end
      self:StartMoving()
    end)
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
    -- Bordure affichee seulement au survol (un cadre permanent autour du cercle, panneau ouvert, etait
    -- tres visible), et seulement si le deplacement est reellement possible : la montrer sur un
    -- element verrouille laisserait croire qu'il est saisissable.
    bar._dragBorder:Hide()
    bar:SetScript("OnEnter", function(self)
      local c = ns.GetCfg("outOfCombatResourceCircle")
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
    bar:SetScript("OnDragStop",  nil)
    bar:SetScript("OnEnter",     nil)
    bar:SetScript("OnLeave",     nil)
    if bar._dragBorder then bar._dragBorder:Hide() end
  end
end

-- Reinitialise la position aux valeurs par defaut
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

-- Mise a jour de la visibilite
function OutOfCombatResourceCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = OutOfCombatResourceCircle.ShouldShow()
  if lastVisibilityState == shouldShow then return end

  if ocrcAnimBusy then
    ocrcAnimDirty = true
    return
  end
  lastVisibilityState = shouldShow
  ocrcAnimBusy = true

  if shouldShow then
    bar:Show()
    local cfgOC = ns.GetCfg("outOfCombatResourceCircle")
    bar.arcGroup:Show()
    bar.bgLarge:Show()
    bar.text:Show()
    if bar.overlay then bar.overlay:Show() end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    if bar.bgGlow and cfgOC.glowEnabled ~= false then bar.bgGlow:Show() end
    for i = 1, secDotCount do
      if secDots[i] then secDots[i]:Show() end
    end
    OutOfCombatResourceCircle.AnimateVisibility(true)
  else
    OutOfCombatResourceCircle.AnimateVisibility(false)
  end
end

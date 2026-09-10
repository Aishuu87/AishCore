-- UI/ModuleHoverOverlay.lua
-- Survol GUI -> lien direct vers la section de reglages : survoler un module a l'ecran affiche un
-- highlight avec une roue crantee, cliquer (ou clic droit sur le highlight) saute vers sa section.
local addonName, ns = ...
local L = ns.L

local Hover = {}
ns.ModuleHoverOverlay = Hover

-- REGISTRE des frames "module" survolables. getFrame() est relu a chaque tick (certaines frames
-- sont creees tardivement ou temporaires) et peut renvoyer nil : l'entree est alors ignoree.
local function G(name) return _G[name] end

local STATIC_ENTRIES = {
  { category = "resourceCircle", getFrame = function() return G("AishCoreRingBar") end },
  { category = "outOfCombat",    getFrame = function() return G("AishCoreHealthRing") end },
  { category = "outOfCombat",    getFrame = function() return G("AishCoreOCResourceRing") end },
  { category = "castBar",        getFrame = function() return G("AishCoreCastBar") end },
  { category = "targetCastBar",  getFrame = function() return G("AishCoreTargetCastBar") end },
  { category = "rotationHelper", getFrame = function() return G("AishCoreRotationHelperBar") end },
  -- TopTargetBar : roue en bas-droite (le haut-droit tombe hors d'atteinte pres du haut d'ecran).
  -- 2 entrees (barre cible + barre "cible de la cible", frame separee) sous la meme categorie.
  { category = "topTargetBar",   gearAnchor = "BOTTOMRIGHT", getFrame = function() return G("AishCoreTopTarget") end },
  { category = "topTargetBar",   gearAnchor = "BOTTOMRIGHT", getFrame = function() return G("AishCoreTopTargetTarget") end },
  -- XPBar : hoverFrame (zone autour du badge de niveau), pas le container qui reste alpha 0
  -- tant qu'on ne survole pas justement hoverFrame.
  { category = "xpBar", getFrame = function()
      local XB = ns.Modules and ns.Modules.XPBar
      return XB and XB.GetHoverFrame and XB.GetHoverFrame()
    end },
  -- Skyriding : AishCoreSkyridingFrame n'est qu'une ancre technique, sans rapport avec le cercle
  -- visible, donc GetHoverFrame() cible ce cercle directement.
  { category = "skyriding", getFrame = function()
      local SR = ns.Modules and ns.Modules.Skyriding
      return SR and SR.GetHoverFrame and SR.GetHoverFrame()
    end },
  -- TargetAuras : buffRow et debuffRow sont positionnees independamment (offsetX/offsetY), donc
  -- potentiellement hors du rectangle englobant : 2 entrees distinctes via GetHoverRows().
  { category = "targetAuras", getFrame = function()
      local TA = ns.Modules and ns.Modules.TargetAuras
      if not (TA and TA.GetHoverRows) then return nil end
      local buffRow = TA.GetHoverRows()
      return buffRow
    end },
  { category = "targetAuras", getFrame = function()
      local TA = ns.Modules and ns.Modules.TargetAuras
      if not (TA and TA.GetHoverRows) then return nil end
      local _, debuffRow = TA.GetHoverRows()
      return debuffRow
    end },
  -- PriorityBar : leftContainer/rightContainer sont locales au module (jamais
  -- de nom global), cf. PriorityBar.GetContainers() ajoute pour ce besoin.
  { category = "priorityBar", getFrame = function()
      local PB = ns.Modules and ns.Modules.PriorityBar
      local c = PB and PB.GetContainers and PB.GetContainers()
      return c and c.left
    end },
  { category = "priorityBar", getFrame = function()
      local PB = ns.Modules and ns.Modules.PriorityBar
      local c = PB and PB.GetContainers and PB.GetContainers()
      return c and c.right
    end },
}

-- Auras render frames (4 mises en page distinctes) : registre live cote
-- Modules/Auras (ns.Auras.renderFrames, alimente par ns.RegisterRender dans
-- chaque fichier de render -- cf. Modules/Auras/Core/Init.lua).
local AURAS_RENDER_CATEGORY = {
  iconlist   = "aurasIconlist",
  freebars   = "aurasFreebars",
  icons      = "aurasIcons",
  circlebars = "aurasCirclebars",
  -- Totems : rendu 100% manuel (pas d'AddAuraGroup, cf. Core/Totems.lua),
  -- mais enregistre son container dans ns.Auras.renderFrames comme les 4
  -- autres (EnsureTotemsContainer) -- meme mecanisme generique suffit.
  totems     = "aurasTotems",
}
for renderKey, catId in pairs(AURAS_RENDER_CATEGORY) do
  STATIC_ENTRIES[#STATIC_ENTRIES + 1] = { category = catId, getFrame = function()
    local A = ns.Auras
    local rf = A and A.renderFrames and A.renderFrames[renderKey]
    return rf and rf.container
  end }
end

-- UnitBars : nombre et cles variables (BAR_DEFS), aucune ne porte de nom
-- global -> construites une seule fois (a la 1ere activation) depuis
-- UnitBars.GetBars(), stable une fois UnitBars.Create() passe.
local ENTRIES = nil
local function BuildEntries()
  if ENTRIES then return ENTRIES end
  local list = {}
  for _, e in ipairs(STATIC_ENTRIES) do list[#list + 1] = e end
  local UB = ns.Modules and ns.Modules.UnitBars
  local bars = UB and UB.GetBars and UB.GetBars()
  if bars then
    for _, frame in pairs(bars) do
      local f = frame
      list[#list + 1] = { category = "unitBars", getFrame = function() return f end }
    end
  end
  ENTRIES = list
  return list
end

-- WIDGETS : un seul highlight + une seule roue crantee, repositionnes sur la frame survolee.
local highlight, gearBtn
local hoveredFrame, hoveredCategory
local HL_PAD   = 6
local ICON_TC  = 0.08

-- Coin d'ancrage de la roue : "TOPRIGHT" par defaut, override via e.gearAnchor pour rester atteignable.
local GEAR_ANCHORS = {
  TOPRIGHT    = { point = "TOPRIGHT",    dx = 3, dy = 3  },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", dx = 3, dy = -3 },
}

-- Saut vers la section de reglages du module survole, utilise par la roue et le clic droit.
local function GoToSettings()
  if not hoveredCategory then return end
  local panel = ns.SettingsPanel
  if panel and panel.SelectCategory then
    if not panel:IsShown() then panel:ShowUI() end
    panel:SelectCategory(hoveredCategory)
  end
end

local function EnsureWidgets()
  if highlight then return end

  -- "Button" (pas "Frame") pour capter le clic droit sur tout le highlight, cible plus large que la roue.
  highlight = CreateFrame("Button", "AishCoreModuleHoverHighlight", UIParent, "BackdropTemplate")
  highlight:SetFrameStrata("TOOLTIP")
  highlight:EnableMouse(true)
  highlight:RegisterForClicks("RightButtonUp")
  highlight:SetScript("OnClick", function(_, button)
    if button == "RightButton" then GoToSettings() end
  end)
  -- Le highlight au-dessus de tout capterait aussi le clic gauche du drag natif du module en
  -- dessous : SetPropagateMouseClicks laisse passer le clic gauche, garde le droit pour nous.
  highlight:SetScript("OnMouseDown", function(self, button)
    self:SetPropagateMouseClicks(button == "LeftButton")
  end)
  highlight:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  highlight:SetBackdropColor(0.2, 0.6, 1, 0.16)
  highlight:SetBackdropBorderColor(0.35, 0.75, 1, 0.9)
  highlight:Hide()

  gearBtn = CreateFrame("Button", "AishCoreModuleHoverGearButton", highlight)
  gearBtn:SetSize(22, 22)
  -- Point initial, repositionne par ShowHighlight selon e.gearAnchor a chaque survol.
  gearBtn:SetPoint("TOPRIGHT", highlight, "TOPRIGHT", 3, 3)
  gearBtn:SetFrameStrata("TOOLTIP")
  gearBtn:SetFrameLevel(highlight:GetFrameLevel() + 5)

  local gBg = gearBtn:CreateTexture(nil, "BACKGROUND")
  gBg:SetAllPoints(); gBg:SetColorTexture(0.06, 0.06, 0.08, 0.95)
  local gBorder = gearBtn:CreateTexture(nil, "BORDER")
  gBorder:SetPoint("TOPLEFT", -1, 1); gBorder:SetPoint("BOTTOMRIGHT", 1, -1)
  gBorder:SetColorTexture(0.35, 0.75, 1, 0.9)
  local gIcon = gearBtn:CreateTexture(nil, "ARTWORK")
  gIcon:SetPoint("TOPLEFT", 3, -3); gIcon:SetPoint("BOTTOMRIGHT", -3, 3)
  gIcon:SetTexture("Interface\\Icons\\Trade_Engineering")
  gIcon:SetTexCoord(ICON_TC, 1 - ICON_TC, ICON_TC, 1 - ICON_TC)

  gearBtn:SetScript("OnEnter", function(self)
    gIcon:SetVertexColor(1, 1, 0.6)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["MODULEHOVER_GEAR_TOOLTIP"], 1, 1, 1)
    GameTooltip:Show()
  end)
  gearBtn:SetScript("OnLeave", function()
    gIcon:SetVertexColor(1, 1, 1)
    GameTooltip:Hide()
  end)
  gearBtn:SetScript("OnClick", GoToSettings)
end

local function ShowHighlight(frame, category, gearAnchor)
  EnsureWidgets()
  hoveredFrame    = frame
  hoveredCategory = category
  highlight:ClearAllPoints()
  highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", -HL_PAD, HL_PAD)
  highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", HL_PAD, -HL_PAD)
  highlight:Show()

  local a = GEAR_ANCHORS[gearAnchor] or GEAR_ANCHORS.TOPRIGHT
  gearBtn:ClearAllPoints()
  gearBtn:SetPoint(a.point, highlight, a.point, a.dx, a.dy)
end

local function HideHighlight()
  hoveredFrame    = nil
  hoveredCategory = nil
  if highlight then highlight:Hide() end
end

-- DRIVER : ticker leger, actif uniquement pendant que le panneau est ouvert.
local TICK_INTERVAL = 0.05
local ticker

local function Tick()
  local panel = ns.SettingsPanel
  if not panel or not panel:IsShown() then
    HideHighlight()
    return
  end
  -- Ne pas "survoler" un module a travers le panneau d'options lui-meme :
  -- le curseur est au-dessus de la fenetre GUI, pas du jeu en dessous.
  if ns.IsFrameMouseOver(panel) then
    HideHighlight()
    return
  end
  -- La roue est un enfant du highlight : la survoler (pour cliquer dessus)
  -- ne doit jamais faire disparaitre le highlight en cours.
  if gearBtn and ns.IsFrameMouseOver(gearBtn) then
    return
  end

  -- Quand 2 frames survolables se chevauchent, on garde celle avec la plus petite aire :
  -- la plus specifique/imbriquee gagne, conforme a l'intuition visuelle.
  local best, bestArea, bestE
  for _, e in ipairs(BuildEntries()) do
    local ok, frame = pcall(e.getFrame)
    if ok and frame and frame:IsVisible() and ns.IsFrameMouseOver(frame) then
      local w, h = frame:GetSize()
      local area = (w or 0) * (h or 0)
      if not best or area < bestArea then
        best, bestArea, bestE = frame, area, e
      end
    end
  end

  if best then
    if hoveredFrame ~= best then
      ShowHighlight(best, bestE.category, bestE.gearAnchor)
    end
  else
    HideHighlight()
  end
end

local function Start()
  if ticker then return end
  ticker = C_Timer.NewTicker(TICK_INTERVAL, Tick)
end

local function Stop()
  if ticker then ticker:Cancel(); ticker = nil end
  HideHighlight()
end

-- Le panneau d'options est charge avant ce fichier ; C_Timer.After(0, ...) reste une garde defensive.
C_Timer.After(0, function()
  local panel = ns.SettingsPanel or _G["AishCoreSettingsPanel"]
  if not panel then return end
  panel:HookScript("OnShow", Start)
  panel:HookScript("OnHide", Stop)
  if panel:IsShown() then Start() end
end)

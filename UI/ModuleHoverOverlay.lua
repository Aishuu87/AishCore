-- UI/ModuleHoverOverlay.lua
-- Survol GUI -> lien direct vers la section de reglages : pendant que le
-- panneau d'options (AishCoreSettingsPanel) est ouvert, survoler un module
-- affiche a l'ecran (cercle de ressource, barres, auras...) l'encadre d'un
-- highlight bleu translucide avec une roue crantee dans le coin -- cliquer
-- dessus saute directement dans la section de reglages correspondante
-- (MainFrame:SelectCategory, cf. UI/SettingsPanel.lua).
local addonName, ns = ...
local L = ns.L

local Hover = {}
ns.ModuleHoverOverlay = Hover

------------------------------------------------------------------------
-- REGISTRE des frames "module" survolables.
-- getFrame() est relu a chaque tick (certaines frames sont creees tardivement,
-- ou n'existent que par instants -- ex: TopTargetBar sans cible) et peut
-- renvoyer nil : l'entree est alors simplement ignoree pour ce tick.
------------------------------------------------------------------------
local function G(name) return _G[name] end

local STATIC_ENTRIES = {
  { category = "resourceCircle", getFrame = function() return G("AishCoreRingBar") end },
  { category = "outOfCombat",    getFrame = function() return G("AishCoreHealthRing") end },
  { category = "outOfCombat",    getFrame = function() return G("AishCoreOCResourceRing") end },
  { category = "castBar",        getFrame = function() return G("AishCoreCastBar") end },
  { category = "targetCastBar",  getFrame = function() return G("AishCoreTargetCastBar") end },
  -- TopTargetBar : la roue par defaut (coin haut-droit) tombe hors d'atteinte
  -- pour ce module (positionne pres du haut de l'ecran) -- coin bas-droit ici.
  -- 2 entrees distinctes : la barre de cible principale (AishCoreTopTarget)
  -- ET la barre "cible de la cible" (AishCoreTopTargetTarget), une frame
  -- separee positionnee ailleurs a l'ecran -- sans sa propre entree, la
  -- survoler ne declenchait rien du tout (aucune entree du registre ne la
  -- couvrait). Meme categorie (topTargetBar) : les reglages ToT vivent dans
  -- la meme section que la barre principale.
  { category = "topTargetBar",   gearAnchor = "BOTTOMRIGHT", getFrame = function() return G("AishCoreTopTarget") end },
  { category = "topTargetBar",   gearAnchor = "BOTTOMRIGHT", getFrame = function() return G("AishCoreTopTargetTarget") end },
  -- XPBar : hoverFrame (zone de survol autour du badge de niveau), PAS le
  -- container de la barre elle-meme -- celle-ci reste cachee/alpha 0 tant
  -- qu'on ne survole pas justement hoverFrame (cf. XPBar.GetHoverFrame),
  -- donc cibler container rendait cette hitbox quasi inaccessible.
  { category = "xpBar", getFrame = function()
      local XB = ns.Modules and ns.Modules.XPBar
      return XB and XB.GetHoverFrame and XB.GetHoverFrame()
    end },
  { category = "skyriding",      getFrame = function() return G("AishCoreSkyridingFrame") end },
  { category = "targetAuras",    getFrame = function() return G("AishCoreTargetAuras") end },
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

------------------------------------------------------------------------
-- WIDGETS : un seul highlight + une seule roue crantee, repositionnes sur
-- la frame survolee (pas un jeu de widgets par module).
------------------------------------------------------------------------
local highlight, gearBtn
local hoveredFrame, hoveredCategory
local HL_PAD   = 6
local ICON_TC  = 0.08

-- Coin d'ancrage de la roue sur le highlight : "TOPRIGHT" par defaut, mais
-- certains modules (ex: topTargetBar, positionne pres du haut de l'ecran)
-- ont besoin d'un autre coin pour rester atteignable -- cf. e.gearAnchor
-- dans le registre plus haut.
local GEAR_ANCHORS = {
  TOPRIGHT    = { point = "TOPRIGHT",    dx = 3, dy = 3  },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", dx = 3, dy = -3 },
}

local function EnsureWidgets()
  if highlight then return end

  highlight = CreateFrame("Frame", "AishCoreModuleHoverHighlight", UIParent, "BackdropTemplate")
  highlight:SetFrameStrata("TOOLTIP")
  highlight:EnableMouse(false)
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
  -- Point initial (sera repositionne par ShowHighlight selon e.gearAnchor a
  -- chaque survol -- necessaire quand meme ici pour eviter un frame sans
  -- ancrage entre la creation et le tout premier ShowHighlight).
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
  gearBtn:SetScript("OnClick", function()
    if not hoveredCategory then return end
    local panel = ns.SettingsPanel
    if panel and panel.SelectCategory then
      if not panel:IsShown() then panel:ShowUI() end
      panel:SelectCategory(hoveredCategory)
    end
  end)
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

------------------------------------------------------------------------
-- DRIVER : ticker leger, actif uniquement pendant que le panneau est ouvert.
------------------------------------------------------------------------
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

  -- Quand 2 frames survolables se chevauchent a l'ecran (ex: la barre de
  -- cible principale et la barre "cible de la cible" positionnees proches
  -- l'une de l'autre), prendre le PREMIER match trouve dans le registre
  -- verrouillait arbitrairement sur la plus grosse/la premiere listee, meme
  -- en survolant visuellement l'autre. On scanne donc TOUTES les entrees et
  -- on garde celle avec la plus PETITE aire -- la plus specifique/imbriquee
  -- gagne, ce qui correspond a l'intuition visuelle (survoler une petite
  -- barre a l'interieur d'une plus grande doit cibler la petite).
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

-- Le panneau d'options (UI/SettingsPanel.lua) est charge avant ce fichier
-- (cf. AishCore.toc) et cree son frame global des le chargement du fichier
-- (pas au login) -- C_Timer.After(0, ...) reste une garde defensive minimale,
-- meme convention que UnitBars.lua/TopTargetBar.lua pour ce genre de hook.
C_Timer.After(0, function()
  local panel = ns.SettingsPanel or _G["AishCoreSettingsPanel"]
  if not panel then return end
  panel:HookScript("OnShow", Start)
  panel:HookScript("OnHide", Stop)
  if panel:IsShown() then Start() end
end)

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

-- section : cle de locale de l'en-tete de la page a deplier en y allant (cf. MainFrame:GoToElement).
-- name    : cle de locale du nom affiche au survol (sinon le nom de la page).
local STATIC_ENTRIES = {
  { category = "resourceCircle", getFrame = function() return G("AishCoreRingBar") end },
  { category = "outOfCombat",    section = "SETTINGS_SEC_HEALTH_CIRCLE", mod = "healthCircle", getFrame = function() return G("AishCoreHealthRing") end },
  { category = "outOfCombat",    section = "SETTINGS_SEC_OCRC",          mod = "outOfCombatResourceCircle", getFrame = function() return G("AishCoreOCResourceRing") end },
  { category = "outOfCombat",    section = "SETTINGS_SEC_WELLFED",       mod = "wellFedCircle", getFrame = function() return G("AishCoreWellFedRing") end },
  { category = "castBar",        getFrame = function() return G("AishCoreCastBar") end },
  { category = "targetCastBar",  getFrame = function() return G("AishCoreTargetCastBar") end },
  { category = "rotationHelper", getFrame = function() return G("AishCoreRotationHelperBar") end },
  -- TopTargetBar : roue en bas-droite (le haut-droit tombe hors d'atteinte pres du haut d'ecran).
  -- 2 entrees (barre cible + barre "cible de la cible", frame separee) sous la meme categorie.
  { category = "topTargetBar",   gearAnchor = "BOTTOMRIGHT", getFrame = function() return G("AishCoreTopTarget") end },
  { category = "topTargetBar",   gearAnchor = "BOTTOMRIGHT", mod = "topTargetBar_tot", getFrame = function() return G("AishCoreTopTargetTarget") end },
  -- XPBar : hoverFrame (zone autour du badge de niveau), pas le container qui reste alpha 0
  -- tant qu'on ne survole pas justement hoverFrame.
  { category = "xpBar", getFrame = function()
      local XB = ns.Modules and ns.Modules.XPBar
      return XB and XB.GetHoverFrame and XB.GetHoverFrame()
    end },
  { category = "location", getFrame = function() return G("AishCoreLocation") end },
  -- Skyriding : AishCoreSkyridingFrame n'est qu'une ancre technique, sans rapport avec le cercle
  -- visible, donc GetHoverFrame() cible ce cercle directement.
  { category = "skyriding", getFrame = function()
      local SR = ns.Modules and ns.Modules.Skyriding
      return SR and SR.GetHoverFrame and SR.GetHoverFrame()
    end },
  -- TargetAuras : buffRow et debuffRow sont positionnees independamment (offsetX/offsetY), donc
  -- potentiellement hors du rectangle englobant : 2 entrees distinctes via GetHoverRows().
  { category = "targetAuras", name = "SETTINGS_BUFFS", taGroup = "buffs", getFrame = function()
      local TA = ns.Modules and ns.Modules.TargetAuras
      if not (TA and TA.GetHoverRows) then return nil end
      local buffRow = TA.GetHoverRows()
      return buffRow
    end },
  { category = "targetAuras", name = "SETTINGS_DEBUFFS", taGroup = "debuffs", getFrame = function()
      local TA = ns.Modules and ns.Modules.TargetAuras
      if not (TA and TA.GetHoverRows) then return nil end
      local _, debuffRow = TA.GetHoverRows()
      return debuffRow
    end },
  -- Buffs manquants : icone d'alerte (cadre global du module Auras)
  { category = "aurasMissingBuffs", name = "AURASDATA_SEC_MISSINGBUFFS_LABEL", getFrame = function()
      -- Cree et place l'alerte meme sans buff manquant, pour avoir son cadre de reperage
      local MB = ns.Auras and ns.Auras.MissingBuffs
      if MB and MB.PrepareHoverAnchor then return MB.PrepareHoverAnchor() end
      return G("AishCoreMissingBuffFrame")
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

-- Auras de la cible : ouvrir la section du groupe clique (buffs ou debuffs), l'autre repliee, et y defiler
for _, e in ipairs(STATIC_ENTRIES) do
  if e.taGroup then
    local grp = e.taGroup
    e.onGo = function()
      local db = ns.DB and ns.DB.targetAuras
      if db then
        db.uiCollapsed = db.uiCollapsed or {}
        db.uiCollapsed.buffs = (grp ~= "buffs")
        db.uiCollapsed.debuffs = (grp ~= "debuffs")
      end
      if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("targetAuras") end
    end
    e.scrollTo = function() return ns.GetTargetAurasSettingsHeader and ns.GetTargetAurasSettingsHeader(grp) end
  end
end

-- Barre de menu
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
  category = "menuBar",
  getFrame = function()
    local MB = ns.Modules and ns.Modules.MenuBar
    return MB and MB.GetHoverFrame and MB.GetHoverFrame()
  end,
}

-- Extra Barres : une entree par barre ; onGo selectionne cette barre dans la page avant d'y sauter
for i = 1, 5 do
  STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
    category = "extraBars",
    getFrame = function()
      local EB = ns.Modules and ns.Modules.ExtraBars
      return EB and EB.GetBarFrame and EB.GetBarFrame(i)
    end,
    onGo = function() ns._extraBarsSelected = i end,
  }
end

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

local UNIT_BAR_NAMES = {
  player = "SETTINGS_UNIT_PLAYER", target = "SETTINGS_UNIT_TARGET", focus = "SETTINGS_UNIT_FOCUS",
  pet = "SETTINGS_UNIT_PET", targettarget = "SETTINGS_UNIT_TARGET_OF_TARGET",
}

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
    for key, frame in pairs(bars) do
      local f, bk = frame, key
      list[#list + 1] = {
        category = "unitBars", name = UNIT_BAR_NAMES[bk], section = "SETTINGS_SEC_UB_BAR_DETAILS",
        mod = "unitBars_" .. (bk == "targettarget" and "tot" or bk),
        getFrame = function() return f end,
        -- Deplie la sous-section de CETTE barre (les autres repliees), page reconstruite pour en tenir compte
        onGo = function()
          local db = ns.DB and ns.DB.unitBars
          if db and db.bars then
            for k, b in pairs(db.bars) do
              if type(b) == "table" then b.collapsed = (k ~= bk) end
            end
          end
          if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("unitBars") end
        end,
        scrollTo = function() return ns.GetUnitBarSettingsHeader and ns.GetUnitBarSettingsHeader(bk) end,
      }
    end
  end
  ENTRIES = list
  return list
end

-- WIDGETS : un seul highlight + une seule roue crantee, repositionnes sur la frame survolee.
local highlight, gearBtn
local hoveredFrame, hoveredCategory, hoveredEntry
local HL_PAD   = 6
local ICON_TC  = 0.08

-- Coin d'ancrage de la roue : "TOPRIGHT" par defaut, override via e.gearAnchor pour rester atteignable.
local GEAR_ANCHORS = {
  TOPRIGHT    = { point = "TOPRIGHT",    dx = 3, dy = 3  },
  BOTTOMRIGHT = { point = "BOTTOMRIGHT", dx = 3, dy = -3 },
}

-- Nom affiche d'une entree : son nom propre, sinon celui de sa section, sinon celui de sa page.
local function EntryName(e)
  if not e then return "" end
  local key = e.name or e.section
  if key and L[key] then return L[key] end
  return (ns.SettingsCategoryLabel and ns.SettingsCategoryLabel(e.category)) or e.category or ""
end

-- Saut vers la section de reglages du module survole (page ouverte, section depliee), roue et clic droit.
local function GoToSettings()
  if not hoveredCategory then return end
  -- Pre-selection propre a l'entree (ex. quelle Extra Barre), avant d'ouvrir la page
  if hoveredEntry and hoveredEntry.onGo then hoveredEntry.onGo() end
  local panel = ns.SettingsPanel
  if panel and panel.GoToElement then
    local section = hoveredEntry and hoveredEntry.section and L[hoveredEntry.section]
    panel:GoToElement(hoveredCategory, section and section:upper(), hoveredEntry and hoveredEntry.scrollTo)
  elseif panel and panel.SelectCategory then
    if not panel:IsShown() then panel:ShowUI() end
    panel:SelectCategory(hoveredCategory)
  end
  -- Page deja affichee : elle ne repasse pas par OnShow, rafraichissement explicite
  if hoveredCategory == "extraBars" and ns.ExtraBarsPageRefresh then ns.ExtraBarsPageRefresh() end
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
  -- Nom de l'element, en petit, au-dessus du coin haut-gauche (a l'exterieur du cadre)
  highlight.nameText = highlight:CreateFontString(nil, "OVERLAY")
  highlight.nameText:SetFont(ns.Media.font, 9, "OUTLINE")
  highlight.nameText:SetPoint("BOTTOMLEFT", highlight, "TOPLEFT", 2, 1)
  highlight.nameText:SetTextColor(0.55, 0.85, 1, 1)
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
  highlight.nameText:SetText(EntryName(hoveredEntry))
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

-- IsVisible() ne regarde QUE la chaine Show/Hide -- il reste vrai a alpha 0. Or la plupart des modules
-- de cet addon se masquent par SetAlpha(0) et jamais par Hide() (seul moyen sur pour une frame securisee
-- en combat, cf. PriorityBar.SafeHideContainers). Un module desactive gardait donc sa hitbox de survol :
-- highlight et roue crantee apparaissaient sur du vide. On exige donc aussi une opacite effective.
-- Seuil bas (pas > 0) : plusieurs modules ont un fondu hors combat legitime a 0.3/0.4, il ne faut pas
-- les rendre insurvolables. A l'inverse un module desactive est exactement a 0.
local MIN_HOVER_ALPHA = 0.05
local function IsEffectivelyVisible(frame)
  local okA, alpha = pcall(frame.GetEffectiveAlpha, frame)
  if not okA or type(alpha) ~= "number" then return true end -- doute : on garde l'ancien comportement
  return alpha > MIN_HOVER_ALPHA
end

-- PAGE "MODULES" : un cadre fin sur CHAQUE element de l'addon, meme masque ou desactive, pour les reperer
-- d'un coup d'oeil. Le cadre est ancre sur l'element (pas de lecture de position : celle des conteneurs
-- natifs d'auras est souvent secrete) et sert aussi a la detection du survol dans ce mode.
local boxes = {}
local function ModulesPageActive()
  local panel = ns.SettingsPanel
  return panel and panel.GetActiveCategory and panel:GetActiveCategory() == "modulesOverview"
end

local function BoxFor(i)
  local b = boxes[i]
  if b then return b end
  b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  b:SetFrameStrata("TOOLTIP")
  b:EnableMouse(false)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(0.2, 0.6, 1, 0.05)
  b:SetBackdropBorderColor(0.35, 0.75, 1, 0.55)

  -- Lueur exterieure (module survole dans la liste) : 4 bandes en degrade sur la LONGUEUR des bords, plus 4 coins
  -- en quart de disque doux (Circle_Smooth2), qui se raccordent sans se chevaucher. Rien n'est lu de la taille du
  -- cadre (souvent secrete pour les conteneurs d'auras) : tout est accroche a ses bords. Pulsation douce.
  local G, R, Gc, B, A = 10, 1, 0.82, 0.3, 0.55
  local glow = CreateFrame("Frame", nil, b)
  glow:SetAllPoints(b)
  local function Strip(p1, rel1, x1, y1, p2, rel2, x2, y2, orient, inner, outer)
    local t = glow:CreateTexture(nil, "BACKGROUND")
    t:SetPoint(p1, b, rel1, x1, y1)
    t:SetPoint(p2, b, rel2, x2, y2)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetBlendMode("ADD")
    -- SetGradient : 1re couleur = bas / gauche, 2e = haut / droite
    t:SetGradient(orient, CreateColor(R, Gc, B, inner), CreateColor(R, Gc, B, outer))
  end
  Strip("BOTTOMLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, G, "VERTICAL", A, 0)          -- haut
  Strip("TOPLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -G, "VERTICAL", 0, A)    -- bas
  Strip("TOPRIGHT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", -G, 0, "HORIZONTAL", 0, A)      -- gauche
  Strip("TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", G, 0, "HORIZONTAL", A, 0)     -- droite
  -- Coins : quart du disque doux dont le centre (le plus lumineux) tombe sur le coin du cadre
  local DISC = "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga"
  local function Corner(point, dx, dy, l, r, t, bo)
    local c = glow:CreateTexture(nil, "BACKGROUND")
    c:SetSize(G, G)
    c:SetPoint(point, b, point, dx, dy)
    c:SetTexture(DISC)
    c:SetTexCoord(l, r, t, bo)
    c:SetBlendMode("ADD")
    c:SetVertexColor(R, Gc, B, A)
  end
  Corner("TOPLEFT",     -G,  G, 0,   0.5, 0,   0.5)
  Corner("TOPRIGHT",     G,  G, 0.5, 1,   0,   0.5)
  Corner("BOTTOMLEFT",  -G, -G, 0,   0.5, 0.5, 1)
  Corner("BOTTOMRIGHT",  G, -G, 0.5, 1,   0.5, 1)
  local ag = glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(1); fade:SetToAlpha(0.35); fade:SetDuration(0.7); fade:SetSmoothing("IN_OUT")
  glow:Hide()
  b._glow, b._glowAG = glow, ag

  boxes[i] = b
  return b
end

-- Module survole dans la liste de la page Modules (cf. MakeModuleRow) : ses cadres brillent
local focusMod = nil
function ns.ModuleHoverFocus(id) focusMod = id end

local function EntryMatches(e, id)
  if not id then return false end
  local mod = e.mod or e.category
  if mod == id then return true end
  -- "Cadres d'unite" (ligne parente) : toutes les barres
  if id == "unitBars" and e.category == "unitBars" then return true end
  return false
end

local function StyleBox(b, lit)
  if b._lit == lit then return end
  b._lit = lit
  if lit then
    b:SetBackdropColor(1, 0.85, 0.3, 0.22)
    b:SetBackdropBorderColor(1, 0.85, 0.3, 1)
    b._glow:Show(); b._glowAG:Play()
  else
    b:SetBackdropColor(0.2, 0.6, 1, 0.05)
    b:SetBackdropBorderColor(0.35, 0.75, 1, 0.55)
    b._glowAG:Stop(); b._glow:Hide()
  end
end

local function HideBoxes()
  for _, b in ipairs(boxes) do b:Hide(); b._target = nil end
end

-- Renvoie l'entree survolee (cadre le plus petit) parmi tous les elements, visibles ou non.
local function UpdateBoxes()
  local best, bestArea, bestE
  local n = 0
  for _, e in ipairs(BuildEntries()) do
    local ok, frame = pcall(e.getFrame)
    if ok and frame then
      n = n + 1
      local b = BoxFor(n)
      if b._target ~= frame then
        b._target = frame
        b:ClearAllPoints()
        pcall(b.SetAllPoints, b, frame)
      end
      b:Show()
      StyleBox(b, EntryMatches(e, focusMod))
      if b:IsMouseOver() then
        local okS, w, h = pcall(b.GetSize, b)
        local area = (okS and type(w) == "number" and type(h) == "number") and (w * h) or math.huge
        if not best or area < bestArea then best, bestArea, bestE = frame, area, e end
      end
    end
  end
  for i = n + 1, #boxes do boxes[i]:Hide(); boxes[i]._target = nil end
  return best, bestE
end

-- DRIVER : ticker leger, actif uniquement pendant que le panneau est ouvert.
local TICK_INTERVAL = 0.05
local ticker

local function Tick()
  local panel = ns.SettingsPanel
  if not panel or not panel:IsShown() then
    HideHighlight()
    HideBoxes()
    return
  end
  local modulesPage = ModulesPageActive()
  local boxBest, boxBestE
  if modulesPage then boxBest, boxBestE = UpdateBoxes() else HideBoxes() end
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
  if modulesPage then
    -- Page Modules : tous les elements comptent, meme caches (detection par leur cadre)
    best, bestE = boxBest, boxBestE
  else
    for _, e in ipairs(BuildEntries()) do
      local ok, frame = pcall(e.getFrame)
      if ok and frame and frame:IsVisible() and IsEffectivelyVisible(frame) and ns.IsFrameMouseOver(frame) then
        local w, h = frame:GetSize()
        local area = (w or 0) * (h or 0)
        if not best or area < bestArea then
          best, bestArea, bestE = frame, area, e
        end
      end
    end
  end

  if best then
    if hoveredFrame ~= best then
      hoveredEntry = bestE
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
  HideBoxes()
end

-- Le panneau d'options est charge avant ce fichier ; C_Timer.After(0, ...) reste une garde defensive.
C_Timer.After(0, function()
  local panel = ns.SettingsPanel or _G["AishCoreSettingsPanel"]
  if not panel then return end
  panel:HookScript("OnShow", Start)
  panel:HookScript("OnHide", Stop)
  if panel:IsShown() then Start() end
end)

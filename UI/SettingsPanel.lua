-- UI/SettingsPanel.lua : Panneau de configuration principal
-- Layout deux colonnes : sidebar categories + contenu scrollable
local addonName, ns = ...
local L = ns.L

local SW     = ns.SharedWidgets
local Theme  = ns.Theme

-- Dimensions globales
local PANEL_WIDTH   = 940
local PANEL_HEIGHT  = 660
-- Plancher de redimensionnement, plus petit que la taille d'ouverture par defaut ; 620 reste au-dessus du plancher de CONTENT_W (370) pour eviter des rangees illisibles.
local PANEL_MIN_WIDTH  = 620
local PANEL_MIN_HEIGHT = 420
local TITLE_H       = 28
local SIDEBAR_W     = 170
local ROW_HEIGHT    = 28
local SECTION_GAP   = 8
local PADDING       = 10
local CAT_BTN_H     = 26
-- Largeur utile des widgets dans la zone de contenu droite
local CONTENT_W     = 680

-- Table des fonctions "BuildXxx" (une par section/page) : champs de Build.Xxx plutot que "local function" pour eviter la limite Lua de 200 locales de haut niveau par chunk.
local Build = {}

-- Frame principal
local MainFrame = CreateFrame("Frame", "AishCoreSettingsPanel", UIParent)
MainFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
MainFrame:SetFrameStrata("DIALOG")
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:SetClampedToScreen(true)
MainFrame:SetResizable(true)
-- Plafonds larges (jamais atteints) : SetClampedToScreen ci-dessus fait le vrai travail de limitation a l'ecran de l'utilisateur.
MainFrame:SetResizeBounds(PANEL_MIN_WIDTH, PANEL_MIN_HEIGHT, 3000, 2600)
MainFrame:Hide()

SW.ApplyPanelBackground(MainFrame)

-- Logo sticker AishUI (badge épinglé, déborde au-dessus du coin gauche)
local LOGO_SZ = 74
local _headerLogo = CreateFrame("Frame", nil, MainFrame)
_headerLogo:SetSize(LOGO_SZ, LOGO_SZ)
_headerLogo:SetPoint("CENTER", MainFrame, "TOPLEFT", 22, -12)
_headerLogo:SetFrameLevel(MainFrame:GetFrameLevel() + 10)
local _logoTex = _headerLogo:CreateTexture(nil, "ARTWORK")
_logoTex:SetAllPoints()
_logoTex:SetTexture("Interface\\AddOns\\AishCore\\Media\\Logo\\AishUILogo")

-- Numero de version, colle au bord droit du logo. Bloc do...end pour ne pas ajouter de locale de haut niveau (limite des 200 deja frolee).
do
  local _versionTxt = MainFrame:CreateFontString(nil, "ARTWORK")
  _versionTxt:SetFont(ns.Media.fontGui, 9)
  _versionTxt:SetPoint("LEFT", _headerLogo, "RIGHT", -4, 4)
  _versionTxt:SetTextColor(Theme.accentText[1], Theme.accentText[2], Theme.accentText[3], 0.85)
  _versionTxt:SetText(ns.GetVersionString and ns.GetVersionString() or ("v" .. tostring(ns.addonVersion or "?")))
  -- Expose via un champ du frame (pas une locale top-level) : re-affiche a chaque ouverture pour refleter le vrai statut une fois la SavedVariable chargee.
  MainFrame._versionTxt = _versionTxt
end

-- Title bar (zone de drag transparente — identité portée par le logo sticker)
local titleBar = SW.CreateTitleBar(MainFrame, "AishCore")
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
titleBar:SetScript("OnDragStart", function() MainFrame:StartMoving() end)
titleBar:SetScript("OnDragStop",  function() MainFrame:StopMovingOrSizing() end)

-- Bouton fermer
local closeBtn = SW.CreateCloseButton(MainFrame)
closeBtn:SetPoint("TOPRIGHT", MainFrame, "TOPRIGHT", -4, -4)
closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 2)

-- Poignée de redimensionnement — invisible avec chevron AishUI discret
local resizeGrip = CreateFrame("Button", nil, MainFrame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -2, 2)
resizeGrip:SetFrameLevel(MainFrame:GetFrameLevel() + 20)
local _gripChevron = resizeGrip:CreateTexture(nil, "OVERLAY")
_gripChevron:SetSize(14, 14)
_gripChevron:SetPoint("CENTER", resizeGrip, "CENTER")
_gripChevron:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\AishChevron")
_gripChevron:SetVertexColor(0.55, 0.55, 0.55, 0.55)
resizeGrip:SetScript("OnEnter", function() _gripChevron:SetVertexColor(0.85, 0.85, 0.85, 1) end)
resizeGrip:SetScript("OnLeave", function() _gripChevron:SetVertexColor(0.55, 0.55, 0.55, 0.55) end)
resizeGrip:SetScript("OnMouseDown", function(self, button)
  if button == "LeftButton" then MainFrame:StartSizing("BOTTOMRIGHT") end
end)
resizeGrip:SetScript("OnMouseUp", function()
  MainFrame:StopMovingOrSizing()
end)

table.insert(UISpecialFrames, "AishCoreSettingsPanel")

-- Sidebar gauche
local sidebar = CreateFrame("Frame", nil, MainFrame)
sidebar:SetPoint("TOPLEFT",    MainFrame, "TOPLEFT",    0, -TITLE_H)
sidebar:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", 0, 0)
sidebar:SetWidth(SIDEBAR_W)

local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, -1)
sidebarBg:SetAllPoints()
sidebarBg:SetColorTexture(0.00, 0.00, 0.00, 0.20)

-- Séparateur vertical
local divLine = MainFrame:CreateTexture(nil, "ARTWORK")
divLine:SetWidth(1)
divLine:SetPoint("TOPLEFT",    MainFrame, "TOPLEFT",    SIDEBAR_W, -TITLE_H)
divLine:SetPoint("BOTTOMLEFT", MainFrame, "BOTTOMLEFT", SIDEBAR_W, 0)
divLine:SetColorTexture(unpack(Theme.separator))

-- ScrollFrame (zone de contenu droite)
local scrollFrame = CreateFrame("ScrollFrame", nil, MainFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     MainFrame, "TOPLEFT",     SIDEBAR_W + 1 + PADDING, -(TITLE_H + PADDING))
scrollFrame:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -18,                     PADDING)

-- Masquer complètement la scrollbar Blizzard vanilla
if scrollFrame.ScrollBar then
  scrollFrame.ScrollBar:SetAlpha(0)
  scrollFrame.ScrollBar:EnableMouse(false)
end

-- Indicateur de défilement custom (rectangle fin, couleur C6B578)
-- Visible seulement quand le contenu dépasse la zone visible.
local _scrollTrack = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
_scrollTrack:SetWidth(5)
_scrollTrack:SetPoint("TOPRIGHT",    MainFrame, "TOPRIGHT",    -5, -(TITLE_H + PADDING))
_scrollTrack:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -5,  PADDING)
_scrollTrack:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                           edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
_scrollTrack:SetBackdropColor(0.08, 0.07, 0.05, 0.80)
_scrollTrack:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.50)
_scrollTrack:Hide()

local _scrollThumb = CreateFrame("Frame", nil, _scrollTrack, "BackdropTemplate")
_scrollThumb:SetPoint("LEFT",  _scrollTrack, "LEFT",  0, 0)
_scrollThumb:SetPoint("RIGHT", _scrollTrack, "RIGHT", 0, 0)
_scrollThumb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
_scrollThumb:SetBackdropColor(0.776, 0.710, 0.471, 0.88)  -- C6B578

-- Clic & drag sur le curseur pour defiler rapidement. SetHitRectInsets agrandit la zone cliquable : le curseur ne fait que 5px de large.
_scrollThumb:EnableMouse(true)
_scrollThumb:SetHitRectInsets(-8, -8, -4, -4)
_scrollThumb:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 0.93, 0.78, 1) end)
_scrollThumb:SetScript("OnLeave", function(self) self:SetBackdropColor(0.776, 0.710, 0.471, 0.88) end)
_scrollThumb:SetScript("OnMouseDown", function(self, button)
  if button ~= "LeftButton" then return end
  self:SetScript("OnUpdate", function(self)
    if not IsMouseButtonDown("LeftButton") then
      self:SetScript("OnUpdate", nil)
      return
    end
    local range = scrollFrame:GetVerticalScrollRange()
    if not range or range < 1 then return end
    local scale = _scrollTrack:GetEffectiveScale()
    local _, cursorY = GetCursorPosition()
    cursorY = cursorY / scale
    local trackTop = _scrollTrack:GetTop()
    local trackH   = _scrollTrack:GetHeight()
    local thumbH   = self:GetHeight()
    local maxOff   = math.max(1, trackH - thumbH)
    local offset   = (trackTop - cursorY) - thumbH / 2
    offset = math.max(0, math.min(maxOff, offset))
    scrollFrame:SetVerticalScroll((offset / maxOff) * range)
  end)
end)

local function _UpdateScrollIndicator()
  local range = scrollFrame:GetVerticalScrollRange()
  if not range or range < 1 then
    _scrollTrack:Hide()
    return
  end
  _scrollTrack:Show()
  local trackH = math.max(1, _scrollTrack:GetHeight() or 100)
  local viewH  = math.max(1, scrollFrame:GetHeight()  or 100)
  local ratio  = viewH / (viewH + range)
  local thumbH = math.max(16, math.floor(trackH * ratio))
  local scroll = scrollFrame:GetVerticalScroll() or 0
  local maxOff = math.max(1, trackH - thumbH)
  local posY   = math.floor((scroll / range) * maxOff)
  _scrollThumb:SetHeight(thumbH)
  _scrollThumb:ClearAllPoints()
  _scrollThumb:SetPoint("TOPLEFT",  _scrollTrack, "TOPLEFT",  0, -posY)
  _scrollThumb:SetPoint("TOPRIGHT", _scrollTrack, "TOPRIGHT", 0, -posY)
end

scrollFrame:HookScript("OnVerticalScroll",    function() _UpdateScrollIndicator() end)
scrollFrame:HookScript("OnScrollRangeChanged", function() _UpdateScrollIndicator() end)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetWidth(CONTENT_W)
content:SetHeight(1)
scrollFrame:SetScrollChild(content)

-- Mise à jour immédiate de la largeur du contenu au redimensionnement
-- (le rebuild des widgets est déclenché plus bas, après que toutes les
-- variables locales nécessaires soient déclarées)
local _resizeTimer = nil
MainFrame:SetScript("OnSizeChanged", function(self, w, h)
  local newContentW = math.max(370, math.floor(w - SIDEBAR_W - 1 - PADDING - 18 - PADDING))
  CONTENT_W = newContentW
  content:SetWidth(newContentW)
end)

-- Utilitaires de layout
local function NewLayout(container)
  local ctx = { y = 0, widgets = {} }

  function ctx:Add(w)
    w:ClearAllPoints()
    w:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -self.y)
    w:Show()
    self.y = self.y + (w:GetHeight() or ROW_HEIGHT) + 2
    table.insert(self.widgets, w)
    return w
  end

  function ctx:Spacer(h)
    self.y = self.y + (h or SECTION_GAP)
  end

  function ctx:Finalize()
    container:SetHeight(self.y + PADDING)
  end

  function ctx:AddRow(gap, ...)
    local args = { ... }
    local xOff = 0
    local rowH = 0
    for _, w in ipairs(args) do
      w:ClearAllPoints()
      w:SetPoint("TOPLEFT", container, "TOPLEFT", xOff, -self.y)
      w:Show()
      local wh = w:GetHeight() or ROW_HEIGHT
      if wh > rowH then rowH = wh end
      xOff = xOff + (w:GetWidth() or 0) + gap
      table.insert(self.widgets, w)
    end
    self.y = self.y + rowH + 2
  end

  -- Comme AddRow, mais centre verticalement chaque widget sur la hauteur de la rangee (ex: checkbox + slider de tailles differentes).
  function ctx:AddRowCentered(gap, ...)
    local args = { ... }
    local rowH = 0
    for _, w in ipairs(args) do
      local wh = w:GetHeight() or ROW_HEIGHT
      if wh > rowH then rowH = wh end
    end
    local xOff = 0
    for _, w in ipairs(args) do
      w:ClearAllPoints()
      local wh = w:GetHeight() or ROW_HEIGHT
      local yOff = math.floor((rowH - wh) / 2)
      w:SetPoint("TOPLEFT", container, "TOPLEFT", xOff, -(self.y + yOff))
      w:Show()
      xOff = xOff + (w:GetWidth() or 0) + gap
      table.insert(self.widgets, w)
    end
    self.y = self.y + rowH + 2
  end

  return ctx
end

-- Bind helpers
local function GetModKey(dbKey)
  local map = {
    resourceCircle             = "ResourceCircle",
    healthCircle               = "HealthCircle",
    outOfCombatResourceCircle  = "OutOfCombatResourceCircle",
    priorityBar                = "PriorityBar",
    rotationHelper             = "RotationHelper",
    spellEffects               = "SpellEffects",
    xpBar                      = "XPBar",
    unitBars                   = "UnitBars",
    groupNumber                = "GroupNumber",
    topTargetBar               = "TopTargetBar",
    targetAuras                = "TargetAuras",
    colors                     = "Colors",
    skyriding                  = "Skyriding",
    visibility                 = "Visibility",
    castBar                    = "CastBar",
    targetCastBar              = "TargetCastBar",
    cdmEssential               = "CooldownManagerEnhanced",
    cdmUtility                 = "CooldownManagerEnhanced",
    characterArmory            = "CharacterArmory",
    afkMode                    = "AFKMode",
    bigCursor                  = "BigCursor",
  }
  return map[dbKey]
end

-- Reconstruit une catégorie GUI en live ; forward-déclarée pour que LiveApply puisse aussi invalider la page "Modules" (mêmes flags que les pages individuelles).
local _invalidateCategory

local function LiveApply(dbKey)
  local mod = ns.Modules and ns.Modules[GetModKey(dbKey)]
  if mod and mod.ApplySettings then mod.ApplySettings() end
  if _invalidateCategory then _invalidateCategory("modulesOverview") end
end

-- dbKey -> id de categorie reel, pour les dbKey dont la page n'est pas du meme nom (healthCircle/outOfCombatResourceCircle partagent "outOfCombat").
local DBKEY_TO_CATEGORY = {
  healthCircle              = "outOfCombat",
  outOfCombatResourceCircle = "outOfCombat",
}

-- Invalide la page dediee d'un module -- utilise UNIQUEMENT par la page "Modules" (jamais par LiveApply, qui tournerait sur la page en cours d'edition et casserait le focus des sliders).
local function InvalidateOwnPage(dbKey)
  if not _invalidateCategory then return end
  local catId = DBKEY_TO_CATEGORY[dbKey] or dbKey
  if catId ~= "modulesOverview" then _invalidateCategory(catId) end
end

local function DBGet(dbKey, subKey)
  local db = ns.DB or {}
  if subKey then
    return db[dbKey] and db[dbKey][subKey]
  else
    return db[dbKey]
  end
end

local function DBSet(dbKey, subKey, val)
  if not ns.DB then ns.DB = {} end
  if subKey then
    if not ns.DB[dbKey] then ns.DB[dbKey] = {} end
    ns.DB[dbKey][subKey] = val
  else
    ns.DB[dbKey] = val
  end
  if ns.CallbackRegistry then
    ns.CallbackRegistry:Trigger("SettingChanged", dbKey, subKey, val)
  end
end

local function BindCheckbox(cb, dbKey, subKey, fallbackSubKey)
  local v = DBGet(dbKey, subKey)
  if v == nil and fallbackSubKey then v = DBGet(dbKey, fallbackSubKey) end
  cb:SetChecked(v and true or false)
  cb.onChanged = function(val) DBSet(dbKey, subKey, val); LiveApply(dbKey) end
  cb._dbKey  = dbKey
  cb._subKey = subKey
end

local function BindSlider(slider, dbKey, subKey, fallbackSubKey)
  local v = DBGet(dbKey, subKey)
  if v == nil and fallbackSubKey then v = DBGet(dbKey, fallbackSubKey) end
  if v then slider:SetValue(v) end
  slider.onChanged = function(val) DBSet(dbKey, subKey, val); LiveApply(dbKey) end
  slider._dbKey  = dbKey
  slider._subKey = subKey
end

local function BindDropdown(dd, dbKey, subKey, fallbackSubKey)
  local v = DBGet(dbKey, subKey)
  if v == nil and fallbackSubKey then v = DBGet(dbKey, fallbackSubKey) end
  if v ~= nil then dd:SetValue(v) end
  dd.onChanged = function(val) DBSet(dbKey, subKey, val); LiveApply(dbKey) end
  dd._dbKey  = dbKey
  dd._subKey = subKey
end

local function BindColorButton(colorBtn, dbKey, subKey)
  local v = DBGet(dbKey, subKey)
  if v and type(v) == "table" then colorBtn:SetColor(v[1], v[2], v[3], v[4]) end
  colorBtn.onChanged = function(val) DBSet(dbKey, subKey, val); LiveApply(dbKey) end
  colorBtn._dbKey  = dbKey
  colorBtn._subKey = subKey
end

-- Aide : groupe radio pour mode de visibilité (mutuellement exclusif)
-- modesList = { {key, label, tooltip}, ... }
-- defaultMode = valeur par défaut si pas dans la DB
local function MakeModeRadio(container, ctx, W, dbKey, modesList, defaultMode)
  local cbs = {}
  local function Refresh()
    local db = ns.DB and ns.DB[dbKey]
    local m = (db and db.visibilityMode) or defaultMode
    for _, pair in ipairs(modesList) do
      if cbs[pair[1]] then cbs[pair[1]]:SetChecked(m == pair[1]) end
    end
  end
  for _, pair in ipairs(modesList) do
    local mKey   = pair[1]
    local mLabel = pair[2]
    local mTip   = pair[3] or ""
    local cb = ctx:Add(SW.CreateCheckbox(container, mLabel, mTip, W))
    cb:SetScript("OnClick", function()
      DBSet(dbKey, "visibilityMode", mKey)
      LiveApply(dbKey)
      Refresh()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    cbs[mKey] = cb
  end
  Refresh()
  return Refresh
end

-- Toggle "Toujours actif en instance" : reste visible en continu tant que ns.inInstance est vrai (donjon/raid, pas scenario/arene/pvp monde). Pas pour Skyriding (pas de systeme visibilityMode).
local function MakeAlwaysInInstanceToggle(container, ctx, W, dbKey)
  local cb = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_VIS_ALWAYS_INSTANCE"], L["SETTINGS_VIS_ALWAYS_INSTANCE_TT"], W))
  BindCheckbox(cb, dbKey, "alwaysInInstance")
  return cb
end

-- Helpers : type de dots secondaires et libellés (pour RC et OCRC)
-- Miroir de la logique de DetectSecondaryDots() dans ResourceCircle.lua.
-- Utilisé pour l'affichage conditionnel et le nommage des sections.
local DOT_TYPE_LABELS = {
  RUNES          = L["SETTINGS_DOT_RUNES"],
  COMBO_ROGUE    = L["SETTINGS_DOT_COMBO_ROGUE"],
  COMBO_DRUID    = L["SETTINGS_DOT_COMBO_DRUID"],
  CHI            = L["SETTINGS_DOT_CHI"],
  HOLY_POWER     = L["SETTINGS_HOLY_POWER"],
  ESSENCE        = L["SETTINGS_ESSENCE"],
  ARCANE_CHARGES = L["SETTINGS_ARCANE_CHARGES"],
}

-- Retourne le dotType actif ("RUNES", "COMBO", …) ou nil si aucun.
local function GetActiveDotType()
  local specID = ns._specID
  local cls    = ns._playerClass or ""
  if cls == "DEATHKNIGHT" then return "RUNES" end
  if cls == "ROGUE"       then return "COMBO_ROGUE" end
  if cls == "DRUID"       then return specID == 103 and "COMBO_DRUID" or nil end
  if cls == "MONK"        then return specID == 269 and "CHI"         or nil end
  if cls == "PALADIN" then
    if specID == 65 then return "HOLY_POWER" end
    local cfg = ns.GetCfg("resourceCircle")
    if cfg and cfg.holyPowerAllSpecs and (specID == 66 or specID == 70) then return "HOLY_POWER" end
    return nil
  end
  if cls == "EVOKER" then
    if specID == 1468 then return "ESSENCE" end
    local cfg = ns.GetCfg("resourceCircle")
    if cfg and cfg.essenceAllSpecs and (specID == 1473 or specID == 1467) then return "ESSENCE" end
    return nil
  end
  if cls == "MAGE"        then return specID == 62  and "ARCANE_CHARGES" or nil end
  return nil
end

-- BUILD : Cercle de Ressource
function Build.ResourceCircle(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local SL_W2 = math.floor((W - 8) / 2)
  local SL_W3 = math.floor((W - 16) / 3)

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_RESOURCE_CIRCLE"], W))

  local cb = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_RC_ENABLE"],
    L["SETTINGS_RC_ENABLE_TT"], W))
  BindCheckbox(cb, "resourceCircle", "enabled")

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "resourceCircle", {
    { "always",  L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_RC_VIS_ALWAYS_TT"] },
    { "target",  L["SETTINGS_VIS_TARGET"],    L["SETTINGS_RC_VIS_TARGET_TT"] },
    { "combat",  L["SETTINGS_VIS_COMBAT"],    L["SETTINGS_RC_VIS_COMBAT_TT"] },
  }, "combat")
  MakeAlwaysInInstanceToggle(container, ctx, W, "resourceCircle")

  local slSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_SIZE"], 20, 200, 1, W))
  BindSlider(slSize, "resourceCircle", "size")

  local slRCArcSize = SW.CreateSlider(container, L["SETTINGS_ARC_SIZE_RATIO"], 0.5, 1.0, 0.05, SL_W2)
  BindSlider(slRCArcSize, "resourceCircle", "arcSizeRatio")
  -- Max étendu à 1.2 (au lieu de 0.99) : les quartiers radiaux sont surdimensionnés de 20%, leur bord déborde donc un peu au-delà du rayon nominal.
  local slRCThick = SW.CreateSlider(container, L["SETTINGS_ARC_THICKNESS"], 0.0, 1.2, 0.01, SL_W2)
  BindSlider(slRCThick, "resourceCircle", "overlayRatio")
  ctx:AddRow(8, slRCArcSize, slRCThick)

  -- Bascule remplissage vertical / radial
  local cbRCRadial = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_RC_RADIAL_FILL"] or "Remplissage radial (expérimental)",
    L["SETTINGS_RC_RADIAL_FILL_TT"] or "Bascule entre le remplissage vertical (par défaut) et un remplissage radial en arc de jauge.",
    W))
  BindCheckbox(cbRCRadial, "resourceCircle", "radialFillTest")

  local slFont = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 30, 1, W))
  BindSlider(slFont, "resourceCircle", "fontSize")
  local ddFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddFont, "resourceCircle", "font")

  ctx:Spacer(6)
  -- Option Paladin : Puissance Sacrée en spé Protection / Vindicte
  if ns._playerClass == "PALADIN" and (ns._specID == 66 or ns._specID == 70) then
    local cbHPAllSpecs = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_RC_HOLY_POWER_ORBS"],
      L["SETTINGS_RC_HOLY_POWER_ORBS_TT"], W))
    BindCheckbox(cbHPAllSpecs, "resourceCircle", "holyPowerAllSpecs")
    cbHPAllSpecs.onChanged = function(val)
      DBSet("resourceCircle", "holyPowerAllSpecs", val)
      LiveApply("resourceCircle")
      if _invalidateCategory then _invalidateCategory("resourceCircle") end
    end
  end
  -- Option Evoker : Essence en spé Dévastation / Augmentation
  if ns._playerClass == "EVOKER" and (ns._specID == 1473 or ns._specID == 1467) then
    local cbEssAllSpecs = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_RC_ESSENCE_ORBS"],
      L["SETTINGS_RC_ESSENCE_ORBS_TT"], W))
    BindCheckbox(cbEssAllSpecs, "resourceCircle", "essenceAllSpecs")
    cbEssAllSpecs.onChanged = function(val)
      DBSet("resourceCircle", "essenceAllSpecs", val)
      LiveApply("resourceCircle")
      if _invalidateCategory then _invalidateCategory("resourceCircle") end
    end
  end
  -- Section dots secondaires : titre dynamique selon classe/spec, masquée si aucun dot
  local dotType   = GetActiveDotType()
  local dotsLabel = dotType and (DOT_TYPE_LABELS[dotType] or L["SETTINGS_DOT_EXTERNAL"]) or nil
  if dotsLabel then
    ctx:Add(SW.CreateSectionHeader(container, dotsLabel, W))
    local dp = "secondaryDots_" .. dotType .. "_"  -- préfixe clé per-type

    local slRot = SW.CreateSlider(container, L["SETTINGS_ORB_ROTATION"], 0, 360, 1, SL_W2)
    BindSlider(slRot, "resourceCircle", dp.."rotation", "secondaryDotsRotation")
    local slSpread = SW.CreateSlider(container, L["SETTINGS_SPREAD"], 5, 60, 1, SL_W2)
    BindSlider(slSpread, "resourceCircle", dp.."spread", "secondaryDotsSpread")
    ctx:AddRow(8, slRot, slSpread)

    local slSecSize = SW.CreateSlider(container, L["SETTINGS_ORB_SIZE"], 0.05, 0.5, 0.01, SL_W2)
    BindSlider(slSecSize, "resourceCircle", dp.."size", "secondaryDotsSize")
    local slSecRadius = SW.CreateSlider(container, L["SETTINGS_RADIUS"], 0.2, 1.2, 0.01, SL_W2)
    BindSlider(slSecRadius, "resourceCircle", dp.."radius", "secondaryDotsRadius")
    ctx:AddRow(8, slSecSize, slSecRadius)

    local cbReversed = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_ORB_REVERSED_ORDER"],
      L["SETTINGS_ORB_REVERSED_ORDER_TT"], W))
    BindCheckbox(cbReversed, "resourceCircle", dp.."reversed", "secondaryDotsReversed")
  end

  -- Section arc de stagger : Moine Brasseur uniquement (spec 268)
  if ns._specID == 268 then
    ctx:Spacer(6)
    ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_STAGGER_ARC"], W))

    local slStagArc = SW.CreateSlider(container, L["SETTINGS_STAGGER_ARC_SIZE"], 0.3, 0.99, 0.01, SL_W2)
    BindSlider(slStagArc, "resourceCircle", "staggerArcRatio")
    local slStagThick = SW.CreateSlider(container, L["SETTINGS_STAGGER_ARC_THICKNESS"], 0.0, 0.99, 0.01, SL_W2)
    BindSlider(slStagThick, "resourceCircle", "staggerOverlayRatio")
    ctx:AddRow(8, slStagArc, slStagThick)

    local cbStagPct = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_STAGGER_SHOW_PCT"],
      L["SETTINGS_STAGGER_SHOW_PCT_TT"], W))
    BindCheckbox(cbStagPct, "resourceCircle", "staggerShowPercent")
  end

  -- Arc de durée dans le cercle central : toggle + taille/épaisseur par spec tank
  local _arcSpec
  if     ns._specID == 66  then _arcSpec = { cfgKey = "consecrationArcEnabled", label = L["SETTINGS_ARC_LABEL_CONSECRATION"], color = {1.00, 0.88, 0.10} }
  elseif ns._specID == 73  then _arcSpec = { cfgKey = "ignorePainArcEnabled",   label = L["SETTINGS_ARC_LABEL_IGNORE_PAIN"],  color = {0.78, 0.25, 0.25} }
  elseif ns._specID == 250 then _arcSpec = { cfgKey = "dndArcEnabled",          label = L["SETTINGS_ARC_LABEL_DND"], color = {0.20, 0.78, 0.35} }
  elseif ns._specID == 270 then _arcSpec = { cfgKey = "manaTeaArcEnabled",      label = L["SETTINGS_SEC_RES_LABEL_MANA_TEA"], color = {0.25, 0.85, 0.55} }
  elseif ns._specID == 1480 then _arcSpec = { cfgKey = "devourerArcEnabled",    label = L["SETTINGS_SEC_RES_LABEL_DEVOURER"], color = {0.70, 0.30, 1.00} }
  elseif ns._specID == 1473 then _arcSpec = { cfgKey = "ebonyPowerArcEnabled",  label = L["SETTINGS_ARC_LABEL_EBONYPOWER"],   color = {0.93, 0.64, 0.30} }
  end
  if _arcSpec then
    ctx:Spacer(6)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_ARC_DURATION_HEADER"], _arcSpec.label), W))
    -- 4e arg = tooltip, PAS le 3e : le 3e-comme-tooltip manquant faisait
    -- s'afficher W (une largeur en pixels, ex. "870") comme texte de tooltip --
    -- aucun intérêt pour l'utilisateur. nil = pas de tooltip.
    local cbDur = ctx:Add(SW.CreateCheckbox(container, string.format(L["SETTINGS_ARC_DURATION_SHOW"], _arcSpec.label), nil, W))
    BindCheckbox(cbDur, "resourceCircle", _arcSpec.cfgKey)
    cbDur.onChanged = function(v)
      DBSet("resourceCircle", _arcSpec.cfgKey, v)
      -- AutoConfigCenterArc/ResyncCenterArc vivent sur ns.Auras, pas sur ce ns principal.
      local AurasNS = ns.Auras
      if AurasNS and AurasNS.AutoConfigCenterArc then AurasNS.AutoConfigCenterArc() end
      -- Resync complet (pas juste AutoConfigCenterArc) : relance le ticker meme si activeInfo ne s'etait jamais resolu pour cette spe.
      if AurasNS and AurasNS.ResyncCenterArc then AurasNS.ResyncCenterArc() end
    end
    cbDur:SetChecked(DBGet("resourceCircle", _arcSpec.cfgKey) ~= false)

    -- Guerrier Prot uniquement : contenu de l'arc (durée vs absorption restante)
    if ns._specID == 73 then
      local cbArcAbsorb = ctx:Add(SW.CreateCheckbox(container,
        L["SETTINGS_ARC_MODE_ABSORB_TOGGLE"],
        L["SETTINGS_ARC_MODE_ABSORB_TOGGLE_TT"], W))
      BindCheckbox(cbArcAbsorb, "resourceCircle", "ignorePainArcAbsorb")
    end

    -- Taille/epaisseur specifiques a la spec active (cf. ns.SecResSpecKey),
    -- meme raison que la couleur ci-dessous : un guerrier et un moine
    -- Mistweaver n'ont aucune raison de partager le meme reglage visuel.
    local slDurArc = SW.CreateSlider(container, L["SETTINGS_ARC_SIZE"], 0.3, 0.99, 0.01, SL_W2)
    BindSlider(slDurArc, "resourceCircle", ns.SecResSpecKey("durationArcRatio"), "durationArcRatio")
    local slDurThick = SW.CreateSlider(container, L["SETTINGS_THICKNESS"], 0.0, 0.99, 0.01, SL_W2)
    BindSlider(slDurThick, "resourceCircle", ns.SecResSpecKey("durationArcOverlayRatio"), "durationArcOverlayRatio")
    ctx:AddRow(8, slDurArc, slDurThick)
    -- Color swatch (specifique a la spec active, cf. ns.SecResSpecKey)
    local durColorRKey = ns.SecResSpecKey("durationArcColorR")
    local durColorGKey = ns.SecResSpecKey("durationArcColorG")
    local durColorBKey = ns.SecResSpecKey("durationArcColorB")
    local cr = ns.GetSecResCfg("durationArcColorR") or _arcSpec.color[1]
    local cg = ns.GetSecResCfg("durationArcColorG") or _arcSpec.color[2]
    local cb_ = ns.GetSecResCfg("durationArcColorB") or _arcSpec.color[3]
    local colorRow = CreateFrame("Frame", nil, container); colorRow:SetSize(W, 26)
    local colorLbl = colorRow:CreateFontString(nil, "OVERLAY")
    colorLbl:SetFont(ns.Media.fontGui, 11); colorLbl:SetPoint("LEFT", 0, 0)
    colorLbl:SetTextColor(0.8, 0.8, 0.8, 1); colorLbl:SetText(L["SETTINGS_ARC_COLOR"])
    local sw = CreateFrame("Button", nil, colorRow); sw:SetSize(22, 22); sw:SetPoint("LEFT", colorLbl, "RIGHT", 8, 0)
    local swT = sw:CreateTexture(nil, "ARTWORK"); swT:SetAllPoints(); swT:SetColorTexture(cr, cg, cb_)
    local swB = sw:CreateTexture(nil, "BORDER"); swB:SetPoint("TOPLEFT",-1,1); swB:SetPoint("BOTTOMRIGHT",1,-1)
    swB:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    sw:SetScript("OnClick", function()
      ColorPickerFrame:SetupColorPickerAndShow({
        r = cr, g = cg, b = cb_,
        swatchFunc = function()
          cr, cg, cb_ = ColorPickerFrame:GetColorRGB()
          swT:SetColorTexture(cr, cg, cb_)
          DBSet("resourceCircle", durColorRKey, cr)
          DBSet("resourceCircle", durColorGKey, cg)
          DBSet("resourceCircle", durColorBKey, cb_)
        end,
        cancelFunc = function(pp)
          cr, cg, cb_ = pp.r, pp.g, pp.b
          swT:SetColorTexture(cr, cg, cb_)
          DBSet("resourceCircle", durColorRKey, cr)
          DBSet("resourceCircle", durColorGKey, cg)
          DBSet("resourceCircle", durColorBKey, cb_)
        end,
      })
    end)
    sw:SetScript("OnEnter", function() GameTooltip:SetOwner(sw,"ANCHOR_TOP"); GameTooltip:SetText(L["SETTINGS_ARC_DURATION_COLOR"],1,1,1); GameTooltip:Show() end)
    sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ctx:Add(colorRow)
  end

  -- Preview de l'arc de durée : cycle 1→0 sur 8s tant que la section est ouverte
  local _prevTicker = nil
  container:SetScript("OnShow", function()
    if not _arcSpec then return end
    local RC = ns.Modules and ns.Modules.ResourceCircle
    if not (RC and RC.SetCenterArcValue) then return end
    local t0 = GetTime()
    local function Tick()
      local frac = 1.0 - ((GetTime() - t0) % 8) / 8
      -- Relire la couleur depuis la config à chaque tick (reflète le color picker en direct)
      local col = _arcSpec.color
      local durR = ns.GetSecResCfg("durationArcColorR")
      if durR then
        col = {durR, ns.GetSecResCfg("durationArcColorG") or 1, ns.GetSecResCfg("durationArcColorB") or 1}
      end
      pcall(RC.SetCenterArcValue, frac, col)
    end
    Tick()
    _prevTicker = C_Timer.NewTicker(0.016, Tick)
  end)
  container:SetScript("OnHide", function()
    if _prevTicker then _prevTicker:Cancel(); _prevTicker = nil end
    local RC = ns.Modules and ns.Modules.ResourceCircle
    if RC and RC.SetCenterArcValue then pcall(RC.SetCenterArcValue, 0, nil) end
  end)

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_BG_GLOW"], W))

  local cbGlow = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_GLOW_ENABLE"],
    L["SETTINGS_RC_GLOW_ENABLE_TT"], W))
  BindCheckbox(cbGlow, "resourceCircle", "glowEnabled")

  local slGlowSize = SW.CreateSlider(container, L["SETTINGS_GLOW_SIZE"], 0.5, 8.0, 0.1, SL_W2)
  BindSlider(slGlowSize, "resourceCircle", "glowSize")
  local slGlowOpacity = SW.CreateSlider(container, L["SETTINGS_GLOW_OPACITY"], 0, 1, 0.05, SL_W2)
  BindSlider(slGlowOpacity, "resourceCircle", "glowOpacity")
  ctx:AddRow(8, slGlowSize, slGlowOpacity)

  ctx:Spacer(6)
  -- En-tête nommé selon la spec active (cf. ResourceMap.lua) plutôt qu'un texte générique.
  local SEC_RES_LABELS = {
    [250]  = L["SETTINGS_SEC_RES_LABEL_BONE_SHIELD"],
    [581]  = L["SETTINGS_SEC_RES_LABEL_SOUL_FRAGMENTS"],
    [73]   = L["SETTINGS_ARC_LABEL_IGNORE_PAIN"],
    [270]  = L["SETTINGS_SEC_RES_LABEL_MANA_TEA"],
  }
  local secResLabel = SEC_RES_LABELS[ns._specID]
  local secResHeaderText = secResLabel
    and string.format(L["SETTINGS_SEC_SECONDARY_RES_TEXT_NAMED"], secResLabel)
    or L["SETTINGS_SEC_SECONDARY_RES_TEXT"]
  ctx:Add(SW.CreateSectionHeader(container, secResHeaderText, W))

  -- Reglages specifiques a la spec active (ns.SecResSpecKey) : chaque spec garde sa config si personnalisee, sinon fallback sur l'ancienne cle plate.
  -- Police / Taille / Decalage X / Decalage Y sur une seule ligne : dropdown Police a largeur fixe, les 3 sliders partagent le reste.
  local DECO_DD_W = 220
  local secResRowW = math.floor((W - DECO_DD_W - 8 * 3) / 3)
  local ddSecResFont = SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), DECO_DD_W)
  BindDropdown(ddSecResFont, "resourceCircle", ns.SecResSpecKey("secResFont"), "secResFont")
  local slSecResSize = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 30, 1, secResRowW)
  BindSlider(slSecResSize, "resourceCircle", ns.SecResSpecKey("secResTextSize"), "secResTextSize")
  local slSecResX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -200, 200, 1, secResRowW)
  BindSlider(slSecResX, "resourceCircle", ns.SecResSpecKey("secResTextOffsetX"), "secResTextOffsetX")
  local slSecResY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -200, 200, 1, secResRowW)
  BindSlider(slSecResY, "resourceCircle", ns.SecResSpecKey("secResTextOffsetY"), "secResTextOffsetY")
  ctx:AddRow(8, ddSecResFont, slSecResSize, slSecResX, slSecResY)

  -- Couleur du texte : 3 sous-cles R/G/B, meme convention que le swatch de l'arc de duree. Appel explicite a LiveApply car ce texte n'a pas de ticker de rafraichissement.
  do
    local secColorRKey = ns.SecResSpecKey("secResColorR")
    local secColorGKey = ns.SecResSpecKey("secResColorG")
    local secColorBKey = ns.SecResSpecKey("secResColorB")
    local scr = ns.GetSecResCfg("secResColorR") or 1
    local scg = ns.GetSecResCfg("secResColorG") or 1
    local scb = ns.GetSecResCfg("secResColorB") or 1
    local colorRow = CreateFrame("Frame", nil, container); colorRow:SetSize(W, 26)
    local colorLbl = colorRow:CreateFontString(nil, "OVERLAY")
    colorLbl:SetFont(ns.Media.fontGui, 11); colorLbl:SetPoint("LEFT", 0, 0)
    colorLbl:SetTextColor(0.8, 0.8, 0.8, 1); colorLbl:SetText(L["SETTINGS_SEC_RES_TEXT_COLOR"])
    local sw = CreateFrame("Button", nil, colorRow); sw:SetSize(22, 22); sw:SetPoint("LEFT", colorLbl, "RIGHT", 8, 0)
    local swT = sw:CreateTexture(nil, "ARTWORK"); swT:SetAllPoints(); swT:SetColorTexture(scr, scg, scb)
    local swB = sw:CreateTexture(nil, "BORDER"); swB:SetPoint("TOPLEFT",-1,1); swB:SetPoint("BOTTOMRIGHT",1,-1)
    swB:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    local function ApplyColor()
      swT:SetColorTexture(scr, scg, scb)
      DBSet("resourceCircle", secColorRKey, scr)
      DBSet("resourceCircle", secColorGKey, scg)
      DBSet("resourceCircle", secColorBKey, scb)
      LiveApply("resourceCircle")
    end
    sw:SetScript("OnClick", function()
      ColorPickerFrame:SetupColorPickerAndShow({
        r = scr, g = scg, b = scb,
        swatchFunc = function() scr, scg, scb = ColorPickerFrame:GetColorRGB(); ApplyColor() end,
        cancelFunc = function(pp) scr, scg, scb = pp.r, pp.g, pp.b; ApplyColor() end,
      })
    end)
    sw:SetScript("OnEnter", function() GameTooltip:SetOwner(sw,"ANCHOR_TOP"); GameTooltip:SetText(L["SETTINGS_SEC_RES_TEXT_COLOR"],1,1,1); GameTooltip:Show() end)
    sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ctx:Add(colorRow)
  end

  -- Guerrier Prot uniquement : le texte affiche un montant (absorb Dur au Mal),
  -- les autres ressources secondaires (Bone Shield, Soul Fragments…) sont des
  -- petits nombres de stacks (0-10) où l'abréviation n'a pas de sens.
  if ns._specID == 73 then
    local cbSecResAbbr = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_SEC_RES_ABBREVIATE"],
      L["SETTINGS_SEC_RES_ABBREVIATE_TT"], W))
    BindCheckbox(cbSecResAbbr, "resourceCircle", ns.SecResSpecKey("secResAbsorbAbbreviate"), "secResAbsorbAbbreviate")
  end

  -- Style de déco / Police de déco / Espacement déco sur une seule ligne (largeurs fixes DECO_DD_W, Espacement récupère le reste).
  local decoOptions = {}
  for _, d in ipairs(ns.SEC_RES_DECO_STYLES) do
    local label = (d.key == "none") and L["SETTINGS_DECO_NONE"] or (d.left .. " N " .. d.right)
    table.insert(decoOptions, { value = d.key, text = label })
  end
  local ddSecResDeco = SW.CreateDropdown(container, L["SETTINGS_DECO_STYLE"], decoOptions, DECO_DD_W)
  BindDropdown(ddSecResDeco, "resourceCircle", ns.SecResSpecKey("secResDecoStyle"), "secResDecoStyle")
  local ddSecResDecoFont = SW.CreateDropdown(container, L["SETTINGS_DECO_FONT"], ns.GetFontList(), DECO_DD_W)
  BindDropdown(ddSecResDecoFont, "resourceCircle", ns.SecResSpecKey("secResDecoFont"), "secResDecoFont")
  local decoSpacingW = W - DECO_DD_W * 2 - 8 * 2
  local slSecResDecoSpacing = SW.CreateSlider(container, L["SETTINGS_DECO_SPACING"], 0, 20, 1, decoSpacingW)
  BindSlider(slSecResDecoSpacing, "resourceCircle", ns.SecResSpecKey("secResDecoSpacing"), "secResDecoSpacing")
  ctx:AddRow(8, ddSecResDeco, ddSecResDecoFont, slSecResDecoSpacing)

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION"], W))

  -- Position absolue (ancre CENTER de UIParent)
  local slRCPosX = SW.CreateSlider(container, L["SETTINGS_POSITION_X"], -2500, 2500, 1, SL_W2)
  BindSlider(slRCPosX, "resourceCircle", "x")
  local slRCPosY = SW.CreateSlider(container, L["SETTINGS_POSITION_Y"], -2500, 2500, 1, SL_W2)
  BindSlider(slRCPosY, "resourceCircle", "y")
  ctx:AddRow(8, slRCPosX, slRCPosY)
  -- Expose globalement : ResourceCircle.lua met ces sliders a jour apres un glisser-deposer en jeu.
  _G["AishCoreRCPosXSlider"] = slRCPosX
  _G["AishCoreRCPosYSlider"] = slRCPosY
  ctx:Spacer(6)

  -- Drag toggle for ResourceCircle
  local rcDragActive = false
  local rcDragBtn = CreateFrame("Button", nil, container)
  rcDragBtn:SetSize(W, 26)
  local _rcBg = rcDragBtn:CreateTexture(nil, "BACKGROUND")
  _rcBg:SetAllPoints(); _rcBg:SetColorTexture(0.10, 0.10, 0.13, 1)
  local _rcLabel = rcDragBtn:CreateFontString(nil, "OVERLAY")
  _rcLabel:SetFont(ns.Media.fontGui, 11); _rcLabel:SetPoint("CENTER")
  _rcLabel:SetTextColor(unpack(Theme.textNormal))
  _rcLabel:SetText(L["UI_MOVE_DRAG_DROP"])

  local function SetRCDragBtnState(active)
    if active then
      _rcBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _rcLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _rcLabel:SetText(L["SETTINGS_RC_DRAG_HINT"])
    else
      _rcBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _rcLabel:SetTextColor(unpack(Theme.textNormal))
      _rcLabel:SetText(L["UI_MOVE_DRAG_DROP"])
    end
  end

  rcDragBtn:SetScript("OnEnter", function()
    if not rcDragActive then
      _rcBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _rcLabel:SetTextColor(unpack(Theme.textHighlight))
    end
  end)
  rcDragBtn:SetScript("OnLeave", function()
    SetRCDragBtnState(rcDragActive)
  end)
  rcDragBtn:SetScript("OnClick", function()
    rcDragActive = not rcDragActive
    SetRCDragBtnState(rcDragActive)
    local RC = ns.Modules.ResourceCircle
    if RC and RC.SetDraggable then RC.SetDraggable(rcDragActive) end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(rcDragBtn)

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Hors Combat (Cercle de Vie + Cercle de Ressource Hors Combat)
function Build.OutOfCombat(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local SL_W2 = math.floor((W - 8) / 2)
  local SL_W3 = math.floor((W - 16) / 3)

  -- Cercle de Vie
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_HEALTH_CIRCLE"], W))

  local cbHC = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_HC_ENABLE"],
    L["SETTINGS_HC_ENABLE_TT"], W))
  BindCheckbox(cbHC, "healthCircle", "enabled")

  local slHCSize = SW.CreateSlider(container, L["SETTINGS_SIZE"], 10, 120, 1, SL_W3)
  BindSlider(slHCSize, "healthCircle", "size")
  local slHCArcSize = SW.CreateSlider(container, L["SETTINGS_ARC_SIZE"], 0.5, 1.0, 0.05, SL_W3)
  BindSlider(slHCArcSize, "healthCircle", "arcSizeRatio")
  local slHCThick = SW.CreateSlider(container, L["SETTINGS_THICKNESS"], 0.0, 0.99, 0.01, SL_W3)
  BindSlider(slHCThick, "healthCircle", "overlayRatio")
  ctx:AddRow(8, slHCSize, slHCArcSize, slHCThick)

  local slHCDelay = SW.CreateSlider(container, L["SETTINGS_HIDE_DELAY_S"], 0.5, 10, 0.5, SL_W2)
  BindSlider(slHCDelay, "healthCircle", "hideDelay")
  local slHCFont = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 4, 20, 1, SL_W2)
  BindSlider(slHCFont, "healthCircle", "fontSize")
  ctx:AddRow(8, slHCDelay, slHCFont)
  local ddHCFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddHCFont, "healthCircle", "font")

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_HC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "healthCircle", {
    { "always",    L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_HC_VIS_ALWAYS_TT"] },
    { "important", L["SETTINGS_VIS_IMPORTANT"], L["SETTINGS_HC_VIS_IMPORTANT_TT"] },
  }, "important")
  MakeAlwaysInInstanceToggle(container, ctx, W, "healthCircle")

  -- Heartbeat pulse toggle
  ctx:Spacer(4)
  local cbHCPulse = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_HC_HEARTBEAT_PULSE"],
    L["SETTINGS_HC_HEARTBEAT_PULSE_TT"], W))
  BindCheckbox(cbHCPulse, "healthCircle", "heartbeatPulse")

  -- Drag toggle for HealthCircle
  ctx:Spacer(2)
  local hcDragActive = false
  local hcDragBtn = CreateFrame("Button", nil, container)
  hcDragBtn:SetSize(W, 26)
  local _hcBg = hcDragBtn:CreateTexture(nil, "BACKGROUND")
  _hcBg:SetAllPoints(); _hcBg:SetColorTexture(0.10, 0.10, 0.13, 1)
  local _hcLabel = hcDragBtn:CreateFontString(nil, "OVERLAY")
  _hcLabel:SetFont(ns.Media.fontGui, 11); _hcLabel:SetPoint("CENTER")
  _hcLabel:SetTextColor(unpack(Theme.textNormal))
  _hcLabel:SetText(L["SETTINGS_HC_MOVE"])

  local function SetHCDragBtnState(active)
    if active then
      _hcBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _hcLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _hcLabel:SetText(L["SETTINGS_DRAG_CIRCLE_HINT"])
    else
      _hcBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _hcLabel:SetTextColor(unpack(Theme.textNormal))
      _hcLabel:SetText(L["SETTINGS_HC_MOVE"])
    end
  end

  hcDragBtn:SetScript("OnEnter", function()
    if not hcDragActive then
      _hcBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _hcLabel:SetTextColor(unpack(Theme.textHighlight))
    end
  end)
  hcDragBtn:SetScript("OnLeave", function()
    SetHCDragBtnState(hcDragActive)
  end)
  hcDragBtn:SetScript("OnClick", function()
    hcDragActive = not hcDragActive
    SetHCDragBtnState(hcDragActive)
    local HC = ns.Modules.HealthCircle
    if HC and HC.SetDraggable then HC.SetDraggable(hcDragActive) end
    if HC and HC.SetPreview   then HC.SetPreview(hcDragActive) end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(hcDragBtn)

  ctx:Spacer(10)

  -- Cercle de Ressource Hors Combat
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_OCRC"], W))

  local cbOCRC = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_OCRC_ENABLE"],
    L["SETTINGS_OCRC_ENABLE_TT"], W))
  BindCheckbox(cbOCRC, "outOfCombatResourceCircle", "enabled")

  local slOCRCSize = SW.CreateSlider(container, L["SETTINGS_SIZE"], 10, 120, 1, SL_W3)
  BindSlider(slOCRCSize, "outOfCombatResourceCircle", "size")
  local slOCRCArcSize = SW.CreateSlider(container, L["SETTINGS_ARC_SIZE"], 0.5, 1.0, 0.05, SL_W3)
  BindSlider(slOCRCArcSize, "outOfCombatResourceCircle", "arcSizeRatio")
  local slOCRCThick = SW.CreateSlider(container, L["SETTINGS_THICKNESS"], 0.0, 0.99, 0.01, SL_W3)
  BindSlider(slOCRCThick, "outOfCombatResourceCircle", "overlayRatio")
  ctx:AddRow(8, slOCRCSize, slOCRCArcSize, slOCRCThick)

  local slOCRCFont = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 4, 20, 1, SL_W2))
  BindSlider(slOCRCFont, "outOfCombatResourceCircle", "fontSize")
  local ddOCRCFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddOCRCFont, "outOfCombatResourceCircle", "font")

  -- Bascule remplissage vertical / radial (même système que le cercle principal)
  local cbOCRCRadial = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_RC_RADIAL_FILL"] or "Remplissage radial (expérimental)",
    L["SETTINGS_RC_RADIAL_FILL_TT"] or "Bascule entre le remplissage vertical (par défaut) et un remplissage radial en arc de jauge.",
    W))
  BindCheckbox(cbOCRCRadial, "outOfCombatResourceCircle", "radialFillTest")

  -- Section dots secondaires hors combat : titre dynamique, masquée si aucun dot
  -- Option Paladin : Puissance Sacrée en spé Protection / Vindicte
  if ns._playerClass == "PALADIN" and (ns._specID == 66 or ns._specID == 70) then
    ctx:Spacer(4)
    local cbOCRCHPAllSpecs = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_RC_HOLY_POWER_ORBS"],
      L["SETTINGS_OCRC_HOLY_POWER_ORBS_TT"], W))
    BindCheckbox(cbOCRCHPAllSpecs, "outOfCombatResourceCircle", "holyPowerAllSpecs")
    cbOCRCHPAllSpecs.onChanged = function(val)
      DBSet("outOfCombatResourceCircle", "holyPowerAllSpecs", val)
      LiveApply("outOfCombatResourceCircle")
      if _invalidateCategory then _invalidateCategory("outOfCombat") end
    end
  end
  -- Option Evoker : Essence en spé Dévastation / Augmentation
  if ns._playerClass == "EVOKER" and (ns._specID == 1473 or ns._specID == 1467) then
    ctx:Spacer(4)
    local cbOCRCEssAllSpecs = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_RC_ESSENCE_ORBS"],
      L["SETTINGS_OCRC_ESSENCE_ORBS_TT"], W))
    BindCheckbox(cbOCRCEssAllSpecs, "outOfCombatResourceCircle", "essenceAllSpecs")
    cbOCRCEssAllSpecs.onChanged = function(val)
      DBSet("outOfCombatResourceCircle", "essenceAllSpecs", val)
      LiveApply("outOfCombatResourceCircle")
      if _invalidateCategory then _invalidateCategory("outOfCombat") end
    end
  end
  local ocrcDotType   = GetActiveDotType()
  local ocrcDotsLabel = ocrcDotType and (DOT_TYPE_LABELS[ocrcDotType] or L["SETTINGS_DOT_EXTERNAL"]) or nil
  if ocrcDotsLabel then
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, ocrcDotsLabel, W))
    local odp = "secondaryDots_" .. ocrcDotType .. "_"  -- préfixe clé per-type

    local slOCRCRot = SW.CreateSlider(container, L["SETTINGS_ORB_ROTATION"], 0, 360, 1, SL_W2)
    BindSlider(slOCRCRot, "outOfCombatResourceCircle", odp.."rotation", "secondaryDotsRotation")
    local slOCRCSpread = SW.CreateSlider(container, L["SETTINGS_SPREAD"], 5, 60, 1, SL_W2)
    BindSlider(slOCRCSpread, "outOfCombatResourceCircle", odp.."spread", "secondaryDotsSpread")
    ctx:AddRow(8, slOCRCRot, slOCRCSpread)

    local slOCRCSecSize = SW.CreateSlider(container, L["SETTINGS_ORB_SIZE"], 0.05, 0.5, 0.01, SL_W2)
    BindSlider(slOCRCSecSize, "outOfCombatResourceCircle", odp.."size", "secondaryDotsSize")
    local slOCRCSecRadius = SW.CreateSlider(container, L["SETTINGS_RADIUS"], 0.2, 1.2, 0.01, SL_W2)
    BindSlider(slOCRCSecRadius, "outOfCombatResourceCircle", odp.."radius", "secondaryDotsRadius")
    ctx:AddRow(8, slOCRCSecSize, slOCRCSecRadius)

    local cbOCRCReversed = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_ORB_REVERSED_ORDER"],
      L["SETTINGS_ORB_REVERSED_ORDER_TT"], W))
    BindCheckbox(cbOCRCReversed, "outOfCombatResourceCircle", odp.."reversed", "secondaryDotsReversed")
  end

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_BG_GLOW_OOC"], W))

  local cbOCRCGlow = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_GLOW_ENABLE"],
    L["SETTINGS_OCRC_GLOW_ENABLE_TT"], W))
  BindCheckbox(cbOCRCGlow, "outOfCombatResourceCircle", "glowEnabled")

  local slOCRCGlowSize = SW.CreateSlider(container, L["SETTINGS_GLOW_SIZE"], 0.3, 8.0, 0.1, SL_W2)
  BindSlider(slOCRCGlowSize, "outOfCombatResourceCircle", "glowSize")
  local slOCRCGlowOpacity = SW.CreateSlider(container, L["SETTINGS_GLOW_OPACITY"], 0, 1, 0.05, SL_W2)
  BindSlider(slOCRCGlowOpacity, "outOfCombatResourceCircle", "glowOpacity")
  ctx:AddRow(8, slOCRCGlowSize, slOCRCGlowOpacity)

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_OCRC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "outOfCombatResourceCircle", {
    { "always",    L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_OCRC_VIS_ALWAYS_TT"] },
    { "important", L["SETTINGS_VIS_IMPORTANT"], L["SETTINGS_OCRC_VIS_IMPORTANT_TT"] },
  }, "important")
  -- Pas de toggle "Toujours actif en instance" ici : le cercle hors-combat
  -- n'a pas besoin de cette option (demande explicite -- contrairement aux
  -- 4 autres modules qui l'ont juste au-dessus de MakeModeRadio).

  ctx:Spacer(4)

  -- Drag toggle for OutOfCombatResourceCircle
  local ocrcDragActive = false
  local ocrcDragBtn = CreateFrame("Button", nil, container)
  ocrcDragBtn:SetSize(W, 26)
  local _ocrcBg = ocrcDragBtn:CreateTexture(nil, "BACKGROUND")
  _ocrcBg:SetAllPoints(); _ocrcBg:SetColorTexture(0.10, 0.10, 0.13, 1)
  local _ocrcLabel = ocrcDragBtn:CreateFontString(nil, "OVERLAY")
  _ocrcLabel:SetFont(ns.Media.fontGui, 11); _ocrcLabel:SetPoint("CENTER")
  _ocrcLabel:SetTextColor(unpack(Theme.textNormal))
  _ocrcLabel:SetText(L["SETTINGS_OCRC_MOVE"])

  local function SetOCRCDragBtnState(active)
    if active then
      _ocrcBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _ocrcLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _ocrcLabel:SetText(L["SETTINGS_DRAG_CIRCLE_HINT"])
    else
      _ocrcBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _ocrcLabel:SetTextColor(unpack(Theme.textNormal))
      _ocrcLabel:SetText(L["SETTINGS_OCRC_MOVE"])
    end
  end

  ocrcDragBtn:SetScript("OnEnter", function()
    if not ocrcDragActive then
      _ocrcBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _ocrcLabel:SetTextColor(unpack(Theme.textHighlight))
    end
  end)
  ocrcDragBtn:SetScript("OnLeave", function()
    SetOCRCDragBtnState(ocrcDragActive)
  end)
  ocrcDragBtn:SetScript("OnClick", function()
    ocrcDragActive = not ocrcDragActive
    SetOCRCDragBtnState(ocrcDragActive)
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    if OCRC and OCRC.SetDraggable then OCRC.SetDraggable(ocrcDragActive) end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(ocrcDragActive) end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(ocrcDragBtn)

  ctx:Spacer(4)

  -- Bouton reset position OCRC
  local resetOCRC = SW.CreateActionBtn(container, L["SETTINGS_OCRC_RESET_POSITION"], W,
    nil, Theme.gold, Theme.accentText)
  resetOCRC:SetScript("OnClick", function()
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    if OCRC and OCRC.ResetPosition then
      OCRC.ResetPosition()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
  end)
  ctx:Add(resetOCRC)

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Bouton de Rotation (miroir du highlight d'assistant de rotation Blizzard, cf. RotationHelper.lua).
function Build.RotationHelper(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local SL_W2 = math.floor((W - 8) / 2)

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_ROTATION_HELPER"], W))

  local cb = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_RH_ENABLE"],
    L["SETTINGS_RH_ENABLE_TT"], W))
  BindCheckbox(cb, "rotationHelper", "enabled")

  -- Visibilite : memes toggles que la Barre de rotation (priorityBar), meme
  -- header -- cf. ShouldShowIcons dans RotationHelper.lua.
  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "rotationHelper", {
    { "always",  L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_RH_VIS_ALWAYS_TT"] },
    { "target",  L["SETTINGS_VIS_TARGET"],    L["SETTINGS_RH_VIS_TARGET_TT"] },
    { "combat",  L["SETTINGS_VIS_COMBAT"],    L["SETTINGS_RH_VIS_COMBAT_TT"] },
  }, "combat")
  MakeAlwaysInInstanceToggle(container, ctx, W, "rotationHelper")
  local cbRest = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_RH_HIDE_RESTING"],
    L["SETTINGS_RH_HIDE_RESTING_TT"], W))
  BindCheckbox(cbRest, "rotationHelper", "ignoreWhileResting")

  ctx:Spacer(4)
  local slSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_SIZE"], 16, 80, 1, W))
  BindSlider(slSize, "rotationHelper", "iconSize")

  -- Glow : meme systeme que la Barre de rotation (priorityBar), table de
  -- styles partagee (ns.Modules.PriorityBar.LOOP_GLOW_TYPES) plutot que
  -- dupliquee -- cf. RotationHelper.lua (ApplyGlowConfig).
  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_GLOW"], W))
  local loopGlowItems = {}
  do
    local PB = ns.Modules.PriorityBar
    local LOOP = PB and PB.LOOP_GLOW_TYPES or {}
    for idx, def in ipairs(LOOP) do
      loopGlowItems[#loopGlowItems + 1] = { value = idx, text = def.name }
    end
  end
  local ddLoopGlow = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_PB_LOOP_GLOW_TYPE"], loopGlowItems, W))
  BindDropdown(ddLoopGlow, "rotationHelper", "loopGlowIndex")

  local colGlow = SW.CreateColorButton(container, L["SETTINGS_GLOW_COLOR"], SL_W2)
  BindColorButton(colGlow, "rotationHelper", "glowColor")
  local slGlowSize = SW.CreateSlider(container, L["SETTINGS_GLOW_SIZE"], 0, 16, 1, SL_W2)
  BindSlider(slGlowSize, "rotationHelper", "glowSize")
  ctx:AddRow(8, colGlow, slGlowSize)

  -- "Utiliser la couleur de la specialisation" : meme reglage/logique que
  -- priorityBar.useSpecGlowColor (ns.Modules.Colors.Get("glow")), cf.
  -- RotationHelper.lua::ApplyGlowConfig.
  local cbRHSpecColor = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_USE_SPEC_COLOR"],
    L["SETTINGS_PB_USE_SPEC_COLOR_TT"], W))
  BindCheckbox(cbRHSpecColor, "rotationHelper", "useSpecGlowColor")

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION"], W))
  local slX = SW.CreateSlider(container, L["SETTINGS_POSITION_X"], -2500, 2500, 1, SL_W2)
  BindSlider(slX, "rotationHelper", "x")
  local slY = SW.CreateSlider(container, L["SETTINGS_POSITION_Y"], -2500, 2500, 1, SL_W2)
  BindSlider(slY, "rotationHelper", "y")
  ctx:AddRow(8, slX, slY)
  -- Expose globalement : RotationHelper.lua met ces sliders a jour apres un glisser-deposer en jeu.
  _G["AishCoreRHPosXSlider"] = slX
  _G["AishCoreRHPosYSlider"] = slY
  ctx:Spacer(6)

  -- Drag toggle
  local rhDragActive = false
  local rhDragBtn = CreateFrame("Button", nil, container)
  rhDragBtn:SetSize(W, 26)
  local _rhBg = rhDragBtn:CreateTexture(nil, "BACKGROUND")
  _rhBg:SetAllPoints(); _rhBg:SetColorTexture(0.10, 0.10, 0.13, 1)
  local _rhLabel = rhDragBtn:CreateFontString(nil, "OVERLAY")
  _rhLabel:SetFont(ns.Media.fontGui, 11); _rhLabel:SetPoint("CENTER")
  _rhLabel:SetTextColor(unpack(Theme.textNormal))
  _rhLabel:SetText(L["UI_MOVE_DRAG_DROP"])

  local function SetRHDragBtnState(active)
    if active then
      _rhBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _rhLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _rhLabel:SetText(L["SETTINGS_RH_DRAG_HINT"])
    else
      _rhBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _rhLabel:SetTextColor(unpack(Theme.textNormal))
      _rhLabel:SetText(L["UI_MOVE_DRAG_DROP"])
    end
  end

  rhDragBtn:SetScript("OnEnter", function()
    if not rhDragActive then
      _rhBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _rhLabel:SetTextColor(unpack(Theme.textHighlight))
    end
  end)
  rhDragBtn:SetScript("OnLeave", function()
    SetRHDragBtnState(rhDragActive)
  end)
  rhDragBtn:SetScript("OnClick", function()
    rhDragActive = not rhDragActive
    SetRHDragBtnState(rhDragActive)
    local RH = ns.Modules.RotationHelper
    if RH and RH.EnableDrag then RH.EnableDrag(rhDragActive) end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(rhDragBtn)

  ctx:Finalize()
  return ctx.widgets
end

-- Helpers pour lire/écrire les valeurs à 3 niveaux : unitBars.bars.<key>.<prop>
-- Remontés au niveau fichier (utilisés par Build.UnitBars ET Build.ModulesOverview).
local function UBGet(barKey, prop)
  local db = ns.DB and ns.DB.unitBars
  local v = db and db.bars and db.bars[barKey] and db.bars[barKey][prop]
  if v ~= nil then return v end
  local def = ns.Defaults and ns.Defaults.unitBars
  return def and def.bars and def.bars[barKey] and def.bars[barKey][prop]
end
local function UBSet(barKey, prop, val)
  if not ns.DB then ns.DB = {} end
  if not ns.DB.unitBars then ns.DB.unitBars = {} end
  if not ns.DB.unitBars.bars then ns.DB.unitBars.bars = {} end
  if not ns.DB.unitBars.bars[barKey] then ns.DB.unitBars.bars[barKey] = {} end
  ns.DB.unitBars.bars[barKey][prop] = val
  LiveApply("unitBars")
end

-- BUILD : Barres de vie (Unit Bars)
function Build.UnitBars(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local UB_SECTION_INDENT = 20

  -- Force un rebuild complet de la page en sauvegardant/restaurant le scroll (meme mecanisme que AFKInvalidateKeepScroll). Locale a la fonction pour ne pas deborder la limite Lua de 200 locales de fichier.
  local function UBInvalidateKeepScroll()
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll()
    if _invalidateCategory then _invalidateCategory("unitBars") end
    if savedScroll then
      C_Timer.After(0, function()
        if scrollFrame then scrollFrame:SetVerticalScroll(savedScroll) end
      end)
    end
  end

  -- Etat plie/deplie d'une barre -- stocke comme un champ de plus sur la
  -- barre (ns.DB.unitBars.bars[cle].collapsed), via UBGet/UBSet comme
  -- n'importe quel autre reglage de barre.
  local function UBBarCollapsed(barKey)
    return UBGet(barKey, "collapsed") and true or false
  end
  local function UBToggleBarCollapsed(barKey)
    UBSet(barKey, "collapsed", not UBBarCollapsed(barKey))
    UBInvalidateKeepScroll()
  end

  --- En-tete cliquable "+ / - Nom de la barre" -- meme pattern que
  --- AFKCollapsibleHeader (Build.AFKMode), adapte a la structure UBGet/UBSet.
  --- `disabled` (barre decochee dans "Barres affichees" ou dans la page
  --- "Modules") : l'en-tete reste visible pour garder la liste des 5 barres
  --- lisible, mais grise, sans +/- et sans clic -- ses reglages n'ont aucun
  --- effet tant que la barre est coupee. Tooltip explicite au survol.
  local function UBCollapsibleHeader(sectionContainer, sectionW, label, barKey, disabled)
    if disabled then
      local header = SW.CreateSectionHeader(sectionContainer, label, sectionW, Theme.textDisabled)
      local hitbox = CreateFrame("Frame", nil, header)
      hitbox:SetAllPoints(header)
      hitbox:SetFrameLevel(header:GetFrameLevel() + 1)
      hitbox:EnableMouse(true)
      hitbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(L["SETTINGS_UB_BAR_DISABLED_TT"], unpack(Theme.textDim))
        GameTooltip:Show()
      end)
      hitbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return header, true
    end

    local collapsed = UBBarCollapsed(barKey)
    local header = SW.CreateSectionHeader(sectionContainer, (collapsed and "+ " or "- ") .. label, sectionW)

    local hitbox = CreateFrame("Button", nil, header)
    hitbox:SetAllPoints(header)
    hitbox:SetFrameLevel(header:GetFrameLevel() + 1)

    local hl = hitbox:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:Hide()
    hitbox:SetScript("OnEnter", function() hl:Show() end)
    hitbox:SetScript("OnLeave", function() hl:Hide() end)
    hitbox:SetScript("OnClick", function() UBToggleBarCollapsed(barKey) end)

    return header, collapsed
  end

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_UNIT_BARS"], W))

  -- Enable global
  local cbAll = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_ENABLE"],
    L["SETTINGS_UB_ENABLE_TT"], W))
  BindCheckbox(cbAll, "unitBars", "enabled")

  -- Verrouiller les positions
  local cbLock = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_LOCK_POSITIONS"],
    L["SETTINGS_UB_LOCK_POSITIONS_TT"], W))
  BindCheckbox(cbLock, "unitBars", "locked")

  -- Mode de visibilité (remplace "Masquer hors combat")
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "unitBars", {
    { "always",  L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_UB_VIS_ALWAYS_TT"] },
    { "target",  L["SETTINGS_VIS_TARGET"],    L["SETTINGS_UB_VIS_TARGET_TT"] },
    { "combat",  L["SETTINGS_VIS_COMBAT"],    L["SETTINGS_UB_VIS_COMBAT_TT"] },
  }, "combat")
  MakeAlwaysInInstanceToggle(container, ctx, W, "unitBars")

  local function UBGlobal(prop)
    local v = ns.DB and ns.DB.unitBars and ns.DB.unitBars[prop]
    if v ~= nil then return v end
    return ns.Defaults and ns.Defaults.unitBars and ns.Defaults.unitBars[prop]
  end
  local function UBGlobalSet(prop, val)
    if not ns.DB.unitBars then ns.DB.unitBars = {} end
    ns.DB.unitBars[prop] = val
    LiveApply("unitBars")
  end

  -- Texte des noms : police / contour / taille sur une seule rangee.
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_UB_NAME_TEXT"], W))
  local nameSL3 = math.floor((W - 2 * 8) / 3)
  local ddUBNameFont = SW.CreateDropdown(container, L["SETTINGS_UB_NAME_FONT"], ns.GetFontList(), nameSL3)
  local _ubNameFontV = UBGlobal("nameFont"); if _ubNameFontV then ddUBNameFont:SetValue(_ubNameFontV) end
  ddUBNameFont.onChanged = function(val) UBGlobalSet("nameFont", val) end
  local ddUBNameOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), nameSL3)
  ddUBNameOutline:SetValue(UBGlobal("nameOutlineStyle") or "OUTLINE")
  ddUBNameOutline.onChanged = function(val) UBGlobalSet("nameOutlineStyle", val) end
  local slName = SW.CreateSlider(container, L["SETTINGS_UB_NAME_FONT_SIZE"], 8, 28, 1, nameSL3)
  slName:SetValue(UBGlobal("nameSize") or 14)
  slName.onChanged = function(val) UBGlobalSet("nameSize", val) end
  ctx:AddRow(8, ddUBNameFont, ddUBNameOutline, slName)

  -- Texte de la vie (anciennement "Texte HP") : police/contour/taille sur
  -- une seule rangee, mode d'affichage pourcentage/valeur reste en dessous
  -- (2 toggles pleine largeur, inchange).
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_HP_TEXT"], W))
  local hpSL3 = math.floor((W - 2 * 8) / 3)
  local ddUBHpFont = SW.CreateDropdown(container, L["SETTINGS_UB_HP_FONT"], ns.GetFontList(), hpSL3)
  local _ubHpFontV = UBGlobal("font"); if _ubHpFontV then ddUBHpFont:SetValue(_ubHpFontV) end
  ddUBHpFont.onChanged = function(val) UBGlobalSet("font", val) end
  local ddUBHpOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), hpSL3)
  ddUBHpOutline:SetValue(UBGlobal("hpOutlineStyle") or "OUTLINE")
  ddUBHpOutline.onChanged = function(val) UBGlobalSet("hpOutlineStyle", val) end
  local slTxt = SW.CreateSlider(container, L["SETTINGS_UB_HP_FONT_SIZE"], 6, 20, 1, hpSL3)
  slTxt:SetValue(UBGlobal("textSize") or 8)
  slTxt.onChanged = function(val) UBGlobalSet("textSize", val) end
  ctx:AddRow(8, ddUBHpFont, ddUBHpOutline, slTxt)

  -- Mode d'affichage HP : pourcentage vs valeur (mutuellement exclusif)
  local cbPct = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_HP_SHOW_PCT"],
    L["SETTINGS_UB_HP_SHOW_PCT_TT"], W))
  local cbVal = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_HP_SHOW_VALUE"],
    L["SETTINGS_UB_HP_SHOW_VALUE_TT"], W))
  -- Init
  local function RefreshHPModeCheckboxes()
    local m = UBGlobal("hpDisplayMode") or "pct"
    cbPct:SetChecked(m == "pct")
    cbVal:SetChecked(m == "value")
  end
  RefreshHPModeCheckboxes()
  -- Remplacement complet de OnClick pour comportement radio (mutuellement exclusif)
  cbPct:SetScript("OnClick", function(self)
    UBGlobalSet("hpDisplayMode", "pct")
    RefreshHPModeCheckboxes()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  cbVal:SetScript("OnClick", function(self)
    UBGlobalSet("hpDisplayMode", "value")
    RefreshHPModeCheckboxes()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)

  -- Sous-titre texte simple, sans decoration (pas de point/hairline comme SW.CreateSectionHeader) : distingue "reglages de la barre" de "reglages du nom".
  local function MakeUBPlainSubtitle(parent, text, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 16)
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 11)
    lbl:SetPoint("LEFT", f, "LEFT", 0, 0)
    lbl:SetTextColor(unpack(ns.Theme.textNormal))
    lbl:SetText(text)
    return f
  end

  local function MakeXYRow(parent, rowW, bk, propA, propB, labelA, labelB)
    local halfW = math.floor((rowW - 8) / 2)
    local sA = SW.CreateSlider(parent, labelA or L["SETTINGS_OFFSET_X"], -200, 200, 1, halfW)
    sA:SetValue(UBGet(bk, propA) or 0)
    sA.onChanged = function(v) UBSet(bk, propA, v) end
    local sB = SW.CreateSlider(parent, labelB or L["SETTINGS_OFFSET_Y"], -200, 200, 1, halfW)
    sB:SetValue(UBGet(bk, propB) or 0)
    sB.onChanged = function(v) UBSet(bk, propB, v) end
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(rowW, sA:GetHeight())
    sA:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    -- Ancre sur la largeur REELLE du slider (plafonnee a MAX_SLIDER_W=220px), pas halfW, sinon les 2 sliders se retrouvent trop ecartes.
    sB:SetPoint("TOPLEFT", row, "TOPLEFT", sA:GetWidth() + 8, 0)
    return row
  end

  -- Ordre demande : Familier - Joueur - Cible - Cible de la cible - Focalisation
  -- (cbW = largeur adaptee au libelle, pour tenir sur une seule rangee).
  local BAR_LABELS = {
    { key = "pet",          label = L["SETTINGS_UNIT_PET"],              cbW = 90 },
    { key = "player",       label = L["SETTINGS_UNIT_PLAYER"],           cbW = 90 },
    { key = "target",       label = L["SETTINGS_UNIT_TARGET"],           cbW = 80 },
    { key = "targettarget", label = L["SETTINGS_UNIT_TARGET_OF_TARGET"], cbW = 150 },
    { key = "focus",        label = L["SETTINGS_UNIT_FOCUS"],            cbW = 115 },
  }

  -- "Barres affichees" : cocher/decocher fait apparaitre/disparaitre la sous-section correspondante (rebuild complet, meme mecanisme que AFKBindElemEnable).
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_UB_BARS_SHOWN"], W))
  local barCBs = {}
  for i, entry in ipairs(BAR_LABELS) do
    local bk = entry.key
    local cbBar = SW.CreateCheckbox(container, entry.label, L["SETTINGS_UB_BAR_ENABLE_TT"], entry.cbW or 120)
    cbBar:SetChecked(UBGet(bk, "enabled") ~= false)
    cbBar.onChanged = function(val)
      UBSet(bk, "enabled", val)
      UBInvalidateKeepScroll()
    end
    barCBs[i] = cbBar
  end
  ctx:AddRow(8, unpack(barCBs))

  -- Sous-section par barre, indentee, avec en-tete repliable "+ / -" -- meme
  -- principe que les elements de Build.AFKMode. Une barre decochee garde son
  -- en-tete mais grise et non cliquable (cf. UBCollapsibleHeader).
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_UB_BAR_DETAILS"], W))

  -- Reglages communs a TOUTES les barres (inversion de couleurs, hauteur tank, etc.), indentes comme les sous-sections repliables mais sans se replier.
  ctx:Spacer(6)
  do
    local preBarsW = W - UB_SECTION_INDENT
    local preBarsSL3 = math.floor((preBarsW - 16) / 3)
    local preBars = CreateFrame("Frame", nil, container)
    preBars:SetWidth(preBarsW)
    local pctx = NewLayout(preBars)

    local cbColorInvert = pctx:Add(SW.CreateCheckbox(preBars,
      L["SETTINGS_UB_COLOR_INVERTED"],
      L["SETTINGS_UB_COLOR_INVERTED_TT"], preBarsW))
    -- Champ DB "reversed" : sens inverse de l'ancien libelle "Mode classique" (coche = reversed false).
    cbColorInvert:SetChecked(UBGlobal("reversed") ~= true)
    cbColorInvert.onChanged = function(val) UBGlobalSet("reversed", not val) end

    pctx:Spacer(6)
    local cbTank = pctx:Add(SW.CreateCheckbox(preBars,
      L["SETTINGS_UB_TANK_HEIGHT"],
      L["SETTINGS_UB_TANK_HEIGHT_TT"], preBarsW))
    BindCheckbox(cbTank, "unitBars", "useTankHeight")

    local slTankW = pctx:Add(SW.CreateSlider(preBars, L["SETTINGS_UB_TANK_HEIGHT_SLIDER"], 2, 30, 1, preBarsW))
    slTankW:SetValue(UBGlobal("tankHeight") or 8)
    slTankW.onChanged = function(val) UBGlobalSet("tankHeight", val) end

    -- Slider grise/inactif quand le toggle est desactive (n'a aucun effet
    -- tant que "Hauteur elargie en spe tank" n'est pas coche).
    local function SetTankSliderEnabled(enabled)
      slTankW.slider:EnableMouse(enabled)
      if enabled then slTankW.editBox:Enable() else slTankW.editBox:Disable() end
      slTankW:SetAlpha(enabled and 1 or 0.4)
    end
    local _origCbTankOnChanged = cbTank.onChanged
    cbTank.onChanged = function(val)
      _origCbTankOnChanged(val)
      SetTankSliderEnabled(val)
    end
    SetTankSliderEnabled(cbTank:GetChecked())

    pctx:Spacer(6)
    local cbShowDots = pctx:Add(SW.CreateCheckbox(preBars,
      L["SETTINGS_UB_SHOW_DOTS"],
      L["SETTINGS_UB_SHOW_DOTS_TT"], preBarsW))
    BindCheckbox(cbShowDots, "unitBars", "showDots")

    local slDot = SW.CreateSlider(preBars, L["SETTINGS_UB_DOT_SIZE"], 4, 24, 1, preBarsSL3)
    slDot:SetValue(UBGlobal("dotSize") or 9)
    slDot.onChanged = function(val) UBGlobalSet("dotSize", val) end
    local slDotR = SW.CreateSlider(preBars, L["SETTINGS_UB_DOT_RATIO"], 0, 100, 1, preBarsSL3)
    slDotR:SetValue(UBGlobal("dotRatio") or 0)
    slDotR.onChanged = function(val) UBGlobalSet("dotRatio", val) end
    local slDotGap = SW.CreateSlider(preBars, L["SETTINGS_UB_DOT_GAP"], -10, 20, 1, preBarsSL3)
    slDotGap:SetValue(UBGlobal("dotGap") or 3)
    slDotGap.onChanged = function(val) UBGlobalSet("dotGap", val) end
    pctx:AddRow(8, slDot, slDotR, slDotGap)

    pctx:Spacer(4)
    pctx:Add(SW.CreateSectionHeader(preBars, L["SETTINGS_SEC_SHIELD_BAR"], preBarsW))
    local cbAbsorb = pctx:Add(SW.CreateCheckbox(preBars,
      L["SETTINGS_UB_SHOW_SHIELD_BAR"],
      L["SETTINGS_UB_SHOW_SHIELD_BAR_TT"], preBarsW))
    cbAbsorb:SetChecked(UBGlobal("showAbsorb") ~= false)
    cbAbsorb.onChanged = function(val) UBGlobalSet("showAbsorb", val) end

     local cbAbsorbRev = pctx:Add(SW.CreateCheckbox(preBars,
      L["SETTINGS_UB_ABSORB_MIRROR"],
      L["SETTINGS_UB_ABSORB_MIRROR_TT"], preBarsW))
    cbAbsorbRev:SetChecked(UBGlobal("absorbReversed") == true)
    cbAbsorbRev.onChanged = function(val) UBGlobalSet("absorbReversed", val) end

    local swAbsorb = pctx:Add(SW.CreateColorSwatch(preBars,
      L["SETTINGS_UB_ABSORB_COLOR"],
      L["SETTINGS_UB_ABSORB_COLOR_TT"], preBarsW))
    local _absC = UBGlobal("absorbColor") or { 0, 1, 0.918, 1 }
    swAbsorb:SetColor(_absC[1], _absC[2], _absC[3], _absC[4])
    swAbsorb.onChanged = function(r, g, b, a)
      UBGlobalSet("absorbColor", { r, g, b, a or 1 })
    end
    pctx:Finalize()

    preBars:ClearAllPoints()
    preBars:SetPoint("TOPLEFT", container, "TOPLEFT", UB_SECTION_INDENT, -ctx.y)
    preBars:Show()
    ctx.y = ctx.y + preBars:GetHeight() + 2
    table.insert(ctx.widgets, preBars)
  end

  ctx:Spacer(10)

  for _, entry in ipairs(BAR_LABELS) do
    local bk = entry.key
    local barOff = UBGet(bk, "enabled") == false
    ctx:Spacer(4)
    local headerW = W - UB_SECTION_INDENT
    local header, collapsed = UBCollapsibleHeader(container, headerW, entry.label, bk, barOff)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", container, "TOPLEFT", UB_SECTION_INDENT, -ctx.y)
    header:Show()
    ctx.y = ctx.y + header:GetHeight() + 2
    table.insert(ctx.widgets, header)

    if not collapsed then
      local detailW = W - UB_SECTION_INDENT
      local detailSL4 = math.floor((detailW - 3 * 8) / 4)
      local detail = CreateFrame("Frame", nil, container)
      detail:SetWidth(detailW)
      local dctx = NewLayout(detail)

      -- "Reglages de la barre" regroupe largeur/hauteur/decalage sur une seule rangee, distingue du decalage du nom juste en dessous.
      dctx:Add(MakeUBPlainSubtitle(detail, L["SETTINGS_SEC_UB_BAR_POSITION"], detailW))
      local slW = SW.CreateSlider(detail, L["SETTINGS_WIDTH"], 40, 700, 1, detailSL4)
      slW:SetValue(UBGet(bk, "width") or 200)
      slW.onChanged = function(val) UBSet(bk, "width", val) end
      local slH = SW.CreateSlider(detail, L["SETTINGS_HEIGHT"], 2, 40, 1, detailSL4)
      slH:SetValue(UBGet(bk, "height") or 4)
      slH.onChanged = function(val) UBSet(bk, "height", val) end
      local slBarX = SW.CreateSlider(detail, L["SETTINGS_OFFSET_X"], -200, 200, 1, detailSL4)
      slBarX:SetValue(UBGet(bk, "x") or 0)
      slBarX.onChanged = function(val) UBSet(bk, "x", val) end
      local slBarY = SW.CreateSlider(detail, L["SETTINGS_OFFSET_Y"], -200, 200, 1, detailSL4)
      slBarY:SetValue(UBGet(bk, "y") or 0)
      slBarY.onChanged = function(val) UBSet(bk, "y", val) end
      dctx:AddRow(8, slW, slH, slBarX, slBarY)

      dctx:Add(MakeUBPlainSubtitle(detail, L["SETTINGS_SEC_UB_NAME_POSITION"], detailW))
      dctx:Add(MakeXYRow(detail, detailW, bk, "nameOffX", "nameOffY"))
      dctx:Finalize()

      detail:ClearAllPoints()
      detail:SetPoint("TOPLEFT", container, "TOPLEFT", UB_SECTION_INDENT, -ctx.y)
      detail:Show()
      ctx.y = ctx.y + detail:GetHeight() + 2
      table.insert(ctx.widgets, detail)
    end
  end

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Numero de Groupe (raid uniquement) : vignette + texte, page separee dans "Cadres d'unites" (pas une sous-section de Barres de Vie).
function Build.GroupNumber(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local W2 = math.floor((W - 8) / 2)

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_GROUP_NUMBER"], W))

  local cbGN = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_GN_ENABLE"], L["SETTINGS_GN_ENABLE_TT"], W))
  BindCheckbox(cbGN, "groupNumber", "enabled")

  local slGNSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_GN_BADGE_SIZE"], 16, 48, 1, W))
  BindSlider(slGNSize, "groupNumber", "badgeSize")

  local colGNBadge = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_GN_BADGE_COLOR"], W))
  BindColorButton(colGNBadge, "groupNumber", "badgeColor")

  -- Point d'ancrage sur le conteneur de groupe ElvUI (mode multi-vignettes,
  -- cf. Modules/GroupNumber.lua) : les 8 coins/cotes possibles.
  local GN_POSITION_OPTIONS = {
    { value = "TOP",         text = L["SETTINGS_POS_TOP"] },
    { value = "BOTTOM",      text = L["SETTINGS_POS_BOTTOM"] },
    { value = "LEFT",        text = L["SETTINGS_POS_LEFT"] },
    { value = "RIGHT",       text = L["SETTINGS_POS_RIGHT"] },
    { value = "TOPLEFT",     text = L["SETTINGS_POS_TOPLEFT"] },
    { value = "TOPRIGHT",    text = L["SETTINGS_POS_TOPRIGHT"] },
    { value = "BOTTOMLEFT",  text = L["SETTINGS_POS_BOTTOMLEFT"] },
    { value = "BOTTOMRIGHT", text = L["SETTINGS_POS_BOTTOMRIGHT"] },
  }
  local ddGNPos = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_GN_POSITION"], GN_POSITION_OPTIONS, 220))
  BindDropdown(ddGNPos, "groupNumber", "badgePosition")

  local slGNBadgeX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -400, 400, 1, W2)
  BindSlider(slGNBadgeX, "groupNumber", "badgeX")
  local slGNBadgeY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -300, 300, 1, W2)
  BindSlider(slGNBadgeY, "groupNumber", "badgeY")
  ctx:AddRow(8, slGNBadgeX, slGNBadgeY)

  -- Police / contour / taille / couleur du texte sur une seule rangee.
  local gnSL4 = math.floor((W - 3 * 8) / 4)
  local ddGNFont = SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), gnSL4)
  BindDropdown(ddGNFont, "groupNumber", "font")

  local ddGNOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), gnSL4)
  BindDropdown(ddGNOutline, "groupNumber", "textOutlineStyle")

  local slGNTextSize = SW.CreateSlider(container, L["SETTINGS_GN_TEXT_SIZE"], 8, 32, 1, gnSL4)
  BindSlider(slGNTextSize, "groupNumber", "textSize")

  local colGNText = SW.CreateColorButton(container, L["SETTINGS_TEXT_COLOR"], gnSL4)
  BindColorButton(colGNText, "groupNumber", "textColor")
  ctx:AddRow(8, ddGNFont, ddGNOutline, slGNTextSize, colGNText)

  local slGNTextX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, W2)
  BindSlider(slGNTextX, "groupNumber", "textOffsetX")
  local slGNTextY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, W2)
  BindSlider(slGNTextY, "groupNumber", "textOffsetY")
  ctx:AddRow(8, slGNTextX, slGNTextY)

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Barre de Cast
function Build.CastBar(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  local function CBGet(prop)
    local db  = ns.DB       and ns.DB.castBar
    local def = ns.Defaults and ns.Defaults.castBar
    if db  and db[prop]  ~= nil then return db[prop]  end
    if def and def[prop] ~= nil then return def[prop] end
  end
  local function CBSet(prop, val)
    if not ns.DB         then ns.DB = {} end
    if not ns.DB.castBar then ns.DB.castBar = {} end
    ns.DB.castBar[prop] = val
    local CB = ns.Modules and ns.Modules.CastBar
    if CB and CB.ApplySettings then CB.ApplySettings() end
  end

  -- Ligne d'alignement : widget partage SW.CreateAlignRow (meme widget que
  -- Cast Cible / Top Target), lie a une propriete castBar via CBGet/CBSet.
  local function MakeAlignRow(prop, labelText, options)
    local row = SW.CreateAlignRow(container, labelText, W, options)
    row:SetValue(CBGet(prop) or "LEFT")
    row.onChanged = function(val) CBSet(prop, val) end
    return row
  end

  -- Barre
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CAST_BAR"], W))

  local cbEn = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_CB_ENABLE"], L["SETTINGS_CB_ENABLE_TT"], W))
  cbEn:SetChecked(CBGet("enabled") ~= false)
  cbEn.onChanged = function(val)
    CBSet("enabled", val)
    -- CBSet ne passe pas par _invalidateCategory : sans cet appel, la case "Activer" de la page "Modules" restait figee sur l'ancien etat.
    if _invalidateCategory then _invalidateCategory("modulesOverview") end
  end

  local _cbSL2 = math.floor((W - 8) / 2)
  local slW = SW.CreateSlider(container, L["SETTINGS_WIDTH"], 60, 500, 1, _cbSL2)
  slW:SetValue(CBGet("width") or 260)
  slW.onChanged = function(val) CBSet("width", val) end
  local slH = SW.CreateSlider(container, L["SETTINGS_HEIGHT"], 1, 20, 1, _cbSL2)
  slH:SetValue(CBGet("height") or 3)
  slH.onChanged = function(val) CBSet("height", val) end
  ctx:AddRow(8, slW, slH)

  -- Position
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION"], W))

  -- Bouton de repositionnement par drag (style thEme addon)
  local CB = ns.Modules and ns.Modules.CastBar
  local dragActive = false

  local dragBtn = CreateFrame("Button", nil, container)
  dragBtn:SetSize(W - 4, 26)

  local _dbBg = dragBtn:CreateTexture(nil, "BACKGROUND")
  _dbBg:SetAllPoints()
  _dbBg:SetColorTexture(0.10, 0.10, 0.13, 1)

  local _dbBorder = dragBtn:CreateTexture(nil, "BORDER")
  _dbBorder:SetPoint("TOPLEFT",     dragBtn, "TOPLEFT",     -1,  1)
  _dbBorder:SetPoint("BOTTOMRIGHT", dragBtn, "BOTTOMRIGHT",  1, -1)
  _dbBorder:SetColorTexture(unpack(ns.Theme.border))

  local _dbLabel = dragBtn:CreateFontString(nil, "OVERLAY")
  _dbLabel:SetFont(ns.Media.fontGui, 12)
  _dbLabel:SetPoint("CENTER")
  _dbLabel:SetTextColor(unpack(ns.Theme.textNormal))
  _dbLabel:SetText(L["UI_MOVE_DRAG_DROP"])

  local function SetDragBtnState(active)
    if active then
      _dbBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _dbLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _dbLabel:SetText(L["SETTINGS_CB_DRAG_HINT"])
    else
      _dbBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _dbLabel:SetTextColor(unpack(ns.Theme.textNormal))
      _dbLabel:SetText(L["UI_MOVE_DRAG_DROP"])
    end
  end

  dragBtn:SetScript("OnEnter", function()
    if not dragActive then
      _dbBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _dbLabel:SetTextColor(unpack(ns.Theme.textHighlight))
    end
  end)
  dragBtn:SetScript("OnLeave", function()
    SetDragBtnState(dragActive)
  end)

  -- Sliders X/Y (upvalues forward-declares : le bouton de drag ci-dessous
  -- les met a jour apres un drag-and-drop, remplace les anciens EditBox
  -- nommes globalement AishCoreCBXEditBox/YEditBox).
  local slCBPosX, slCBPosY

  dragBtn:SetScript("OnClick", function()
    dragActive = not dragActive
    SetDragBtnState(dragActive)
    if dragActive then
      -- DEverrouiller le drag et afficher la barre
      if CB and CB.SetDragUnlocked then CB.SetDragUnlocked(true) end
      if CB and CB.SetPreview      then CB.SetPreview(true)      end
    else
      -- Reverrouiller, repositionner, rafraEchir les champs
      if CB and CB.SetDragUnlocked then CB.SetDragUnlocked(false) end
      if CB and CB.ApplySettings   then CB.ApplySettings()       end
      local db = ns.DB and ns.DB.castBar
      if slCBPosX then slCBPosX:SetValue(math.floor((db and db.x) or CBGet("x") or 0)) end
      if slCBPosY then slCBPosY:SetValue(math.floor((db and db.y) or CBGet("y") or 0)) end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(dragBtn)

  local xyHalfW = math.floor((W - 8) / 2)
  slCBPosX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -200, 200, 1, xyHalfW)
  slCBPosX:SetValue(CBGet("x") or 0)
  slCBPosX.onChanged = function(v) CBSet("x", v) end
  slCBPosY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -200, 200, 1, xyHalfW)
  slCBPosY:SetValue(CBGet("y") or 0)
  slCBPosY.onChanged = function(v) CBSet("y", v) end
  ctx:AddRow(8, slCBPosX, slCBPosY)

  -- Remarque : X/Y sont relatifs E UIParent CENTER
  local hint = container:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 10)
  hint:SetTextColor(0.55, 0.55, 0.55, 1)
  hint:SetText(L["UI_OFFSET_HINT"])
  hint:SetJustifyH("LEFT")
  hint:SetSize(W - 10, 18)
  ctx:Add(hint)

  -- Reglage reserve (cf. Core.lua:ns.HasHeroicFeatures) : toggle masque tant
  -- que le champ racine SavedVariables correspondant n'est pas present.
  if ns.HasHeroicFeatures and ns.HasHeroicFeatures() then
    local cbSchool = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_CB_COLOR_BY_SCHOOL"],
      L["SETTINGS_CB_COLOR_BY_SCHOOL_TT"], W))
    cbSchool:SetChecked(CBGet("colorBySchool") or false)
    cbSchool.onChanged = function(val) CBSet("colorBySchool", val) end
  end

  -- Texte Nom
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SPELL_NAME_TEXT"], W))

  local slNS = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 28, 1, 200)
  slNS:SetValue(CBGet("nameSize") or 12)
  slNS.onChanged = function(val) CBSet("nameSize", val) end

  local slNOX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, 140)
  slNOX:SetValue(CBGet("nameOffX") or 0)
  slNOX.onChanged = function(val) CBSet("nameOffX", val) end

  local slNOY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, 140)
  slNOY:SetValue(CBGet("nameOffY") or 0)
  slNOY.onChanged = function(val) CBSet("nameOffY", val) end

  ctx:AddRow(10, slNS, slNOX, slNOY)

  local ddCBFont = SW.CreateDropdown(container, L["SETTINGS_UB_NAME_FONT"], ns.GetFontList(), 115)
  do
    local _v = CBGet("font"); if _v then ddCBFont:SetValue(_v) end
    ddCBFont.onChanged = function(val) CBSet("font", val) end
  end

  local ddCBNameOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 115)
  ddCBNameOutline:SetValue(CBGet("nameOutlineStyle") or "OUTLINE")
  ddCBNameOutline.onChanged = function(val) CBSet("nameOutlineStyle", val) end

  ctx:AddRow(8, ddCBFont, ddCBNameOutline)

  ctx:Add(MakeAlignRow("nameJustify", L["SETTINGS_CB_NAME_ALIGNMENT"]))

  -- Texte Timer
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TIMER_TEXT"], W))

  local slTS = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 20, 1, 200)
  slTS:SetValue(CBGet("timerSize") or 8)
  slTS.onChanged = function(val) CBSet("timerSize", val) end

  local slTOX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, 140)
  slTOX:SetValue(CBGet("timerOffX") or 0)
  slTOX.onChanged = function(val) CBSet("timerOffX", val) end

  local slTOY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, 140)
  slTOY:SetValue(CBGet("timerOffY") or 0)
  slTOY.onChanged = function(val) CBSet("timerOffY", val) end

  ctx:AddRow(10, slTS, slTOX, slTOY)

  local ddCBTimerFont = SW.CreateDropdown(container, L["SETTINGS_CB_TIMER_FONT"], ns.GetFontList(), 115)
  do
    local _v = CBGet("timerFont"); if _v then ddCBTimerFont:SetValue(_v) end
    ddCBTimerFont.onChanged = function(val) CBSet("timerFont", val) end
  end

  local ddCBTimerOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 115)
  ddCBTimerOutline:SetValue(CBGet("timerOutlineStyle") or "OUTLINE")
  ddCBTimerOutline.onChanged = function(val) CBSet("timerOutlineStyle", val) end

  ctx:AddRow(8, ddCBTimerFont, ddCBTimerOutline)

  ctx:Add(MakeAlignRow("timerJustify", L["SETTINGS_CB_TIMER_ALIGNMENT"]))

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Barre de Cast Cible
function Build.TargetCastBar(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  local function TCBGet(prop)
    local db  = ns.DB       and ns.DB.targetCastBar
    local def = ns.Defaults and ns.Defaults.targetCastBar
    if db  and db[prop]  ~= nil then return db[prop]  end
    if def and def[prop] ~= nil then return def[prop] end
  end
  local function TCBSet(prop, val)
    if not ns.DB               then ns.DB = {} end
    if not ns.DB.targetCastBar then ns.DB.targetCastBar = {} end
    ns.DB.targetCastBar[prop] = val
    local TCB = ns.Modules and ns.Modules.TargetCastBar
    if TCB and TCB.ApplySettings then TCB.ApplySettings() end
  end

  -- Ligne d'alignement : widget partage SW.CreateAlignRow (meme widget que
  -- Cast Joueur / Top Target), lie a une propriete targetCastBar via
  -- TCBGet/TCBSet.
  local function MakeTCBAlignRow(prop, labelText, options)
    local row = SW.CreateAlignRow(container, labelText, W, options)
    row:SetValue(TCBGet(prop) or "LEFT")
    row.onChanged = function(val) TCBSet(prop, val) end
    return row
  end

  -- Barre
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TARGET_CAST_BAR"], W))

  local tcbEn = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TCB_ENABLE"], L["SETTINGS_TCB_ENABLE_TT"], W))
  tcbEn:SetChecked(TCBGet("enabled") ~= false)
  tcbEn.onChanged = function(val)
    TCBSet("enabled", val)
    -- Meme raison que castBar/cbEn ci-dessus : TCBSet est generique et ne
    -- passe pas par LiveApply/_invalidateCategory.
    if _invalidateCategory then _invalidateCategory("modulesOverview") end
  end

  local tcbIcon = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TCB_SHOW_ICON"], L["SETTINGS_TCB_SHOW_ICON_TT"], W))
  tcbIcon:SetChecked(TCBGet("showIcon") ~= false)
  tcbIcon.onChanged = function(val) TCBSet("showIcon", val) end

  local _tcbSL2 = math.floor((W - 8) / 2)
  local slTCBW = SW.CreateSlider(container, L["SETTINGS_WIDTH"], 60, 500, 1, _tcbSL2)
  slTCBW:SetValue(TCBGet("width") or 260)
  slTCBW.onChanged = function(val) TCBSet("width", val) end
  local slTCBH = SW.CreateSlider(container, L["SETTINGS_HEIGHT"], 1, 20, 1, _tcbSL2)
  slTCBH:SetValue(TCBGet("height") or 3)
  slTCBH.onChanged = function(val) TCBSet("height", val) end
  ctx:AddRow(8, slTCBW, slTCBH)

  -- Position
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION"], W))

  local TCB = ns.Modules and ns.Modules.TargetCastBar
  local tcbDragActive = false

  local tcbDragBtn = CreateFrame("Button", nil, container)
  tcbDragBtn:SetSize(W - 4, 26)

  local _tdbBg = tcbDragBtn:CreateTexture(nil, "BACKGROUND")
  _tdbBg:SetAllPoints()
  _tdbBg:SetColorTexture(0.10, 0.10, 0.13, 1)

  local _tdbBorder = tcbDragBtn:CreateTexture(nil, "BORDER")
  _tdbBorder:SetPoint("TOPLEFT",     tcbDragBtn, "TOPLEFT",     -1,  1)
  _tdbBorder:SetPoint("BOTTOMRIGHT", tcbDragBtn, "BOTTOMRIGHT",  1, -1)
  _tdbBorder:SetColorTexture(unpack(ns.Theme.border))

  local _tdbLabel = tcbDragBtn:CreateFontString(nil, "OVERLAY")
  _tdbLabel:SetFont(ns.Media.fontGui, 12)
  _tdbLabel:SetPoint("CENTER")
  _tdbLabel:SetTextColor(unpack(ns.Theme.textNormal))
  _tdbLabel:SetText(L["UI_MOVE_DRAG_DROP"])

  local function SetTCBDragBtnState(active)
    if active then
      _tdbBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _tdbLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _tdbLabel:SetText(L["SETTINGS_TCB_DRAG_HINT"])
    else
      _tdbBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _tdbLabel:SetTextColor(unpack(ns.Theme.textNormal))
      _tdbLabel:SetText(L["UI_MOVE_DRAG_DROP"])
    end
  end

  tcbDragBtn:SetScript("OnEnter", function()
    if not tcbDragActive then
      _tdbBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _tdbLabel:SetTextColor(unpack(ns.Theme.textHighlight))
    end
  end)
  tcbDragBtn:SetScript("OnLeave", function()
    SetTCBDragBtnState(tcbDragActive)
  end)

  local slTCBPosX, slTCBPosY

  tcbDragBtn:SetScript("OnClick", function()
    tcbDragActive = not tcbDragActive
    SetTCBDragBtnState(tcbDragActive)
    if tcbDragActive then
      if TCB and TCB.SetDragUnlocked then TCB.SetDragUnlocked(true) end
      if TCB and TCB.SetPreview      then TCB.SetPreview(true)      end
    else
      if TCB and TCB.SetDragUnlocked then TCB.SetDragUnlocked(false) end
      if TCB and TCB.ApplySettings   then TCB.ApplySettings()       end
      local db = ns.DB and ns.DB.targetCastBar
      if slTCBPosX then slTCBPosX:SetValue(math.floor((db and db.x) or TCBGet("x") or 0)) end
      if slTCBPosY then slTCBPosY:SetValue(math.floor((db and db.y) or TCBGet("y") or 0)) end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(tcbDragBtn)

  local tcbHalfW = math.floor((W - 8) / 2)
  slTCBPosX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -200, 200, 1, tcbHalfW)
  slTCBPosX:SetValue(TCBGet("x") or 0)
  slTCBPosX.onChanged = function(v) TCBSet("x", v) end
  slTCBPosY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -200, 200, 1, tcbHalfW)
  slTCBPosY:SetValue(TCBGet("y") or 0)
  slTCBPosY.onChanged = function(v) TCBSet("y", v) end
  ctx:AddRow(8, slTCBPosX, slTCBPosY)

  local tcbHint = container:CreateFontString(nil, "OVERLAY")
  tcbHint:SetFont(ns.Media.fontGui, 10)
  tcbHint:SetTextColor(0.55, 0.55, 0.55, 1)
  tcbHint:SetText(L["UI_OFFSET_HINT"])
  tcbHint:SetJustifyH("LEFT")
  tcbHint:SetSize(W - 10, 18)
  ctx:Add(tcbHint)

  -- Couleurs
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_COLORS"], W))

  -- 4 colonnes sur la meme ligne (au lieu d'empiler chaque swatch sur sa
  -- propre ligne pleine largeur) -- largeurs adaptees a la longueur de
  -- chaque libelle plutot qu'un partage egal, pour eviter que "Non-
  -- interruptible" soit tronque.
  local colInt = SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_INTERRUPTIBLE"], 190)
  do local c = TCBGet("colorInterruptible") or {0,0.78,0.78,1}; colInt:SetColor(c[1],c[2],c[3],c[4]) end
  colInt.onChanged = function(val) TCBSet("colorInterruptible", val) end

  local colImp = SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_IMPORTANT"], 150)
  do local c = TCBGet("colorImportant") or {0.855,0.239,1,1}; colImp:SetColor(c[1],c[2],c[3],c[4]) end
  colImp.onChanged = function(val) TCBSet("colorImportant", val) end

  local colNI = SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_NOT_INTERRUPTIBLE"], 170)
  do local c = TCBGet("colorNotInterruptible") or {0.765,0.294,0.290,1}; colNI:SetColor(c[1],c[2],c[3],c[4]) end
  colNI.onChanged = function(val) TCBSet("colorNotInterruptible", val) end

  local colCh = SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_CHANNELING"], 150)
  do local c = TCBGet("colorChanneling") or {0.506,0.788,0.243,1}; colCh:SetColor(c[1],c[2],c[3],c[4]) end
  colCh.onChanged = function(val) TCBSet("colorChanneling", val) end

  ctx:AddRow(6, colInt, colImp, colNI, colCh)

  -- Texte Nom
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SPELL_NAME_TEXT"], W))

  local slTCBNS = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 28, 1, 140)
  slTCBNS:SetValue(TCBGet("nameSize") or 12)
  slTCBNS.onChanged = function(val) TCBSet("nameSize", val) end

  local slTCBNOX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, 140)
  slTCBNOX:SetValue(TCBGet("nameOffX") or 0)
  slTCBNOX.onChanged = function(val) TCBSet("nameOffX", val) end

  local slTCBNOY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, 140)
  slTCBNOY:SetValue(TCBGet("nameOffY") or 0)
  slTCBNOY.onChanged = function(val) TCBSet("nameOffY", val) end

  ctx:AddRow(10, slTCBNS, slTCBNOX, slTCBNOY)

  local ddTCBFont = SW.CreateDropdown(container, L["SETTINGS_UB_NAME_FONT"], ns.GetFontList(), 140)
  do
    local _v = TCBGet("font"); if _v then ddTCBFont:SetValue(_v) end
    ddTCBFont.onChanged = function(val) TCBSet("font", val) end
  end

  local ddTCBNameOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 140)
  ddTCBNameOutline:SetValue(TCBGet("nameOutlineStyle") or "OUTLINE")
  ddTCBNameOutline.onChanged = function(val) TCBSet("nameOutlineStyle", val) end

  ctx:AddRow(8, ddTCBFont, ddTCBNameOutline)

  ctx:Add(MakeTCBAlignRow("nameJustify", L["SETTINGS_CB_NAME_ALIGNMENT"]))

  -- Texte Timer
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TIMER_TEXT"], W))

  local slTCBTS = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 20, 1, 140)
  slTCBTS:SetValue(TCBGet("timerSize") or 8)
  slTCBTS.onChanged = function(val) TCBSet("timerSize", val) end

  local slTCBTOX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, 140)
  slTCBTOX:SetValue(TCBGet("timerOffX") or 0)
  slTCBTOX.onChanged = function(val) TCBSet("timerOffX", val) end

  local slTCBTOY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, 140)
  slTCBTOY:SetValue(TCBGet("timerOffY") or 0)
  slTCBTOY.onChanged = function(val) TCBSet("timerOffY", val) end

  ctx:AddRow(10, slTCBTS, slTCBTOX, slTCBTOY)

  local ddTCBTimerFont = SW.CreateDropdown(container, L["SETTINGS_CB_TIMER_FONT"], ns.GetFontList(), 140)
  do
    local _v = TCBGet("timerFont"); if _v then ddTCBTimerFont:SetValue(_v) end
    ddTCBTimerFont.onChanged = function(val) TCBSet("timerFont", val) end
  end

  local ddTCBTimerOutline = SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 140)
  ddTCBTimerOutline:SetValue(TCBGet("timerOutlineStyle") or "OUTLINE")
  ddTCBTimerOutline.onChanged = function(val) TCBSet("timerOutlineStyle", val) end

  ctx:AddRow(8, ddTCBTimerFont, ddTCBTimerOutline)

  ctx:Add(MakeTCBAlignRow("timerJustify", L["SETTINGS_CB_TIMER_ALIGNMENT"]))

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Animations 3D (Effets de Sort)
-- Helpers locaux pour le combo editor
local seSelectedSpellID = nil  -- spellID actuellement sélectionné dans la liste gauche
local seSelectedAuraID  = nil  -- auraID actuellement sélectionné (section Auras)
local seSelectedAnimIdx = nil  -- index de l'animation sélectionnée dans le combo
local seSpellList       = nil  -- frame de la liste de sorts (scrollable)
local seAuraList        = nil  -- frame de la liste d'auras (scrollable)
local seMissingBuffsList = nil -- frame de la liste "Buffs manquants" (scrollable)
local seAnimList        = nil  -- frame de la liste d'animations du combo
local seAnimEditor      = nil  -- frame de l'éditeur d'animation (sliders etc.)
local sePreviewModel    = nil  -- PlayerModel de preview live

-- Pseudo-sorts Fire Mage (Heating Up / Hot Streak) pour le module Animations 3D
-- Ces IDs fictifs correspondent aux procs détectés via SPELL_ACTIVATION_OVERLAY_SHOW dans ResourceCircle
local PSEUDO_SPELLS_3D = {
  [9000001] = { name = L["SETTINGS_PSEUDO_HEATING_UP"],    icon = 236218,  specID = 63 },
  [9000002] = { name = L["SETTINGS_PSEUDO_HOT_STREAK"],    icon = 1035045, specID = 63 },
  [9000003] = { name = L["SETTINGS_PSEUDO_ESSENCE_BURST"], icon = 4630437, specID = 1468 },
  [9000004] = { name = L["SETTINGS_PSEUDO_MAELSTROM_5"],   icon = 136063,  specID = 263  },
  [9000005] = { name = L["SETTINGS_PSEUDO_MAELSTROM_8"],   icon = 136063,  specID = 263  },
  [9000006] = { name = L["SETTINGS_PSEUDO_MAELSTROM_10"],  icon = 136063,  specID = 263  },
}

-- Utilitaire : résout le nom et l'icône d'un spellID
local function GetSpellInfo3D(spellID)
  if PSEUDO_SPELLS_3D[spellID] then
    return PSEUDO_SPELLS_3D[spellID].name, PSEUDO_SPELLS_3D[spellID].icon
  end
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
  if info then
    return info.name or string.format(L["SETTINGS_SPELL_FALLBACK_NAME"], spellID), info.iconID or 134400
  end
  -- GetSpellInfo (API globale) n'existe plus depuis longtemps sur retail --
  -- l'ancien fallback ici l'appelait quand meme, plantant avec "attempt to
  -- call a nil value" des que C_Spell.GetSpellInfo echouait (spellID pas
  -- encore mis en cache cote client, ex. 363405). Repli propre sur le nom
  -- generique plutot que sur une API qui n'existe plus.
  return string.format(L["SETTINGS_SPELL_FALLBACK_NAME"], spellID), 134400
end

-- Retourne la table combos de la DB (crée-la si besoin)
local function GetCombosDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.combos then ns.DB.spellEffects.combos = {} end
  return ns.DB.spellEffects.combos
end

-- Retourne la table des spellIDs ajoutés manuellement (via le champ SpellID)
local function GetManualSpellsDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.manualSpells then ns.DB.spellEffects.manualSpells = {} end
  return ns.DB.spellEffects.manualSpells
end

-- Valeurs par défaut d'une animation
local function NewAnimDefaults()
  return {
    modelID  = 0,
    duration = 0.8,
    z        = 0,
    x        = 0,
    y        = 0,
    rotation = 0,
    scale    = 1.0,
    alpha    = 1.0,
    delay    = 0,
    anchorX  = 0,
    anchorY  = 0,
    strata   = "BACKGROUND",
    trigger  = "onhit",
  }
end

-- Section active et sélection inter-sections (Sorts / Orbes / OOC / Auras / Buffs manquants)
-- "missingBuffs" réutilise seSelectedAuraID (même sélection, section distincte
-- uniquement par la valeur de seActiveSection — cf. GetActiveComboTable).
local seActiveSection      = "spells"  -- "spells" | "orbs" | "ooc" | "auras" | "missingBuffs"
local seSelectedTriggerKey = nil       -- trigger key pour orbs/ooc
local seOrbList            = nil       -- frame pour la liste de triggers orbes
local seOocList            = nil       -- frame pour la liste de triggers OOC

-- Triggers prédéfinis pour Globes Externes par classe
local ORB_TRIGGERS = {
  ROGUE = {
    { key = "combo",             label = L["SETTINGS_ORB_COMBO_POINTS"] },
    { key = "combo_max",         label = L["SETTINGS_ORB_COMBO_POINTS_MAX"] },
    { key = "combo_stealth",     label = L["SETTINGS_ORB_COMBO_POINTS_STEALTH"] },
    { key = "combo_max_stealth", label = L["SETTINGS_ORB_COMBO_POINTS_MAX_STEALTH"] },
  },
  DRUID = {
    { key = "combo",             label = L["SETTINGS_ORB_COMBO_POINTS"] },
    { key = "combo_max",         label = L["SETTINGS_ORB_COMBO_POINTS_MAX"] },
    { key = "combo_stealth",     label = L["SETTINGS_ORB_COMBO_POINTS_STEALTH"] },
    { key = "combo_max_stealth", label = L["SETTINGS_ORB_COMBO_POINTS_MAX_STEALTH"] },
  },
  DEATHKNIGHT = {
    { key = "rune_frost",  label = L["SETTINGS_ORB_RUNE_FROST"] },
    { key = "rune_blood",  label = L["SETTINGS_ORB_RUNE_BLOOD"] },
    { key = "rune_unholy", label = L["SETTINGS_ORB_RUNE_UNHOLY"] },
  },
  PALADIN = {
    { key = "holypower",     label = L["SETTINGS_HOLY_POWER"] },
    { key = "holypower_max", label = L["SETTINGS_ORB_HOLY_POWER_MAX"] },
  },
  EVOKER = {
    { key = "essence",       label = L["SETTINGS_ESSENCE"] },
    { key = "essence_burst", label = L["SETTINGS_PSEUDO_ESSENCE_BURST"] },
  },
  MONK = {
    { key = "chi", label = L["SETTINGS_ORB_CHI_POINTS"] },
  },
  MAGE = {
    { key = "arcane_charges",      label = L["SETTINGS_ARCANE_CHARGES"] },
    { key = "arcane_charges_full", label = L["SETTINGS_ORB_ARCANE_CHARGES_FULL"] },
  },
  -- WARLOCK (Coeur demoniaque) desactive : demande explicite -- cf. le
  -- guard inconditionnel correspondant dans SpellEffects.lua::GetValidOrbKeys,
  -- qui empeche aussi une combo deja configuree de continuer a se declencher.
}

-- Suffixe de classe pour isoler les données par classe (SavedVariables = account-wide)
local function OrbKeyForClass(baseKey)
  return baseKey .. "_" .. (ns._playerClass or "")
end

local function SpecKeyForClass(specIdx)
  return "spec_" .. (ns._playerClass or "") .. "_" .. specIdx
end

-- Accesseur combos orbes
local function GetOrbCombosDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.orbCombos then ns.DB.spellEffects.orbCombos = {} end
  return ns.DB.spellEffects.orbCombos
end

-- Accesseur couleurs des globes par condition
local function GetOrbGlobeColorsDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.orbGlobeColors then ns.DB.spellEffects.orbGlobeColors = {} end
  return ns.DB.spellEffects.orbGlobeColors
end

-- Accesseur combos cercle OOC
local function GetOocCombosDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.oocCombos then ns.DB.spellEffects.oocCombos = {} end
  return ns.DB.spellEffects.oocCombos
end

-- Accesseur combos d'auras (déclenchés par la présence d'une aura, joueur ou cible)
local function GetAuraCombosDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.auraCombos then ns.DB.spellEffects.auraCombos = {} end
  return ns.DB.spellEffects.auraCombos
end

-- Accesseur combos "Buffs manquants" (module dedie, cf. Modules/Auras/Core/MissingBuffs.lua) :
-- meme principe que GetAuraCombosDB, table separee -- la liste de sorts
-- selectionnables est restreinte par ns.Auras.MissingBuffs.GetTriggerSpells()
-- et le rendu s'ancre sur AishCoreMissingBuffFrame, pas sur le cercle central.
local function GetMissingBuffsCombosDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.missingBuffsCombos then ns.DB.spellEffects.missingBuffsCombos = {} end
  return ns.DB.spellEffects.missingBuffsCombos
end

-- Accesseur table des alias spellID ? configuredSpellID (IDs déclencheurs alternatifs)
local function GetCombosAliasesDB()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.spellEffects then ns.DB.spellEffects = {} end
  if not ns.DB.spellEffects.combosAliases then ns.DB.spellEffects.combosAliases = {} end
  return ns.DB.spellEffects.combosAliases
end

-- Retourne la table combo + clé correspondant à la section active
local function GetActiveComboTable()
  if seActiveSection == "orbs" and seSelectedTriggerKey then
    return GetOrbCombosDB(), OrbKeyForClass(seSelectedTriggerKey)
  elseif seActiveSection == "ooc" and seSelectedTriggerKey then
    return GetOocCombosDB(), seSelectedTriggerKey
  elseif seActiveSection == "spells" and seSelectedSpellID then
    return GetCombosDB(), seSelectedSpellID
  elseif seActiveSection == "auras" and seSelectedAuraID then
    return GetAuraCombosDB(), seSelectedAuraID
  elseif seActiveSection == "missingBuffs" and seSelectedAuraID then
    return GetMissingBuffsCombosDB(), seSelectedAuraID
  end
  return nil, nil
end

-- Coupe l'apercu force de l'icone "Buffs manquants" (cf. SetPreview(true,
-- spellId) lance au clic d'une ligne dans cette section) : inline (pas une
-- fonction nommee) a chaque site d'appel plutot qu'une locale de plus au
-- fichier -- le chunk principal est deja tres proche de la limite Lua de
-- 200 locales (confirme en jeu, une seule locale de plus l'a fait deborder).

-- Retourne l'ancre (ou table d'ancres) de preview selon la section active
local function GetPreviewAnchor()
  if seActiveSection == "missingBuffs" then
    return _G["AishCoreMissingBuffFrame"]
  elseif seActiveSection == "ooc" then
    return _G["AishCoreHealthRing"]
  elseif seActiveSection == "orbs" then
    -- Collecter TOUS les globes visibles pour multi-anchor preview
    local anchors = {}
    for i = 1, 10 do
      local dot = _G["AishCoreSecDot" .. i]
      if dot and dot:IsShown() then anchors[#anchors + 1] = dot end
    end
    if #anchors == 0 then
      for i = 1, 10 do
        local dot = _G["AishCoreOCSecDot" .. i]
        if dot and dot:IsShown() then anchors[#anchors + 1] = dot end
      end
    end
    if #anchors > 0 then return anchors end
  end
  return nil  -- nil = utilise l'ancre par défaut (AishCoreRingBar)
end

-- Triggers OOC cercle de vie : global (par classe) + un par spé du joueur
local function GetOocTriggers()
  local cls = ns._playerClass or ""
  local triggers = { { key = "global_" .. cls, label = L["SETTINGS_TRIGGER_REGEN_GLOBAL"] } }
  local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
  for i = 1, numSpecs do
    local _, specName = GetSpecializationInfo(i)
    if specName then
      triggers[#triggers + 1] = { key = SpecKeyForClass(i), label = string.format(L["SETTINGS_TRIGGER_REGEN_SPEC"], specName) }
    end
  end
  return triggers
end

-- Triggers orbes Evoker : global (essence / essence_burst) + variantes par spé du joueur.
-- Une variante de spé prend la priorité sur le global si elle est configurée.
local function GetEvokerOrbTriggers()
  local triggers = {
    { key = "essence",       label = L["SETTINGS_TRIGGER_ESSENCE_GLOBAL"] },
    { key = "essence_burst", label = L["SETTINGS_TRIGGER_ESSENCE_BURST_GLOBAL"] },
  }
  local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
  for i = 1, numSpecs do
    local _, specName = GetSpecializationInfo(i)
    if specName then
      triggers[#triggers + 1] = { key = "essence_spec" .. i,       label = string.format(L["SETTINGS_TRIGGER_ESSENCE_SPEC"], specName) }
      triggers[#triggers + 1] = { key = "essence_burst_spec" .. i, label = string.format(L["SETTINGS_TRIGGER_ESSENCE_BURST_SPEC"], specName) }
    end
  end
  return triggers
end

-- Retourne les triggers d'orbes pour la classe courante.
-- Pour l'Evoker, génère des variantes de spé dynamiquement.
local function GetClassOrbTriggers()
  local cls = ns._playerClass or ""
  if cls == "EVOKER" then return GetEvokerOrbTriggers() end
  return ORB_TRIGGERS[cls] or {}
end

-- Forward declarations
local RefreshSpellList, RefreshAnimList, RefreshAnimEditor, RefreshAliasRow
local RefreshOrbList, RefreshOocList, RefreshAuraList, RefreshMissingBuffsList, RelayoutSections

-- Lookup : FileID ? nom de modèle via AishCoreModelPaths (Data\ModelPaths.lua)
local seModelNameCache = {}  -- fileID(number) ? "name.m2"

local function GetModelPathsData()
  return AishCoreModelPaths
end

local function StripM2(name)
  if not name then return name end
  return name:gsub("%.m2$", ""):gsub("%.M2$", "")
end

local function GetModelNameByFileID(fileID)
  if not fileID or fileID == 0 then return nil end
  if seModelNameCache[fileID] then return seModelNameCache[fileID] end
  -- Utilise ns._modelFlat (table compacte créée au login depuis AishCoreModelPaths)
  local flat = ns._modelFlat
  if flat then
    for i = 1, #flat do
      local entry = flat[i]
      if entry.fileId == fileID then
        local name = StripM2(entry.text)
        seModelNameCache[fileID] = name
        return name
      end
    end
  end
  return nil
end

-- Model Picker Frame (singleton)

-- Tags de recherche rapide : clic sur un tag ? filtre tous les mots-clés associés
-- Keywords vides par défaut à restaurés au PLAYER_LOGIN depuis ns.DB.modelTagKeywords
local MODEL_TAGS = {
  { label = "Lightning",    color = {0.45, 0.70, 1.00}, keywords = {} },
  { label = "Holy",         color = {1.00, 0.90, 0.40}, keywords = {} },
  { label = "Fire",         color = {1.00, 0.45, 0.15}, keywords = {} },
  { label = "Life",         color = {0.30, 0.85, 0.30}, keywords = {} },
  { label = "Ice",          color = {0.50, 0.85, 1.00}, keywords = {} },
  { label = "Blood",        color = {0.80, 0.15, 0.15}, keywords = {} },
  { label = "Unholy",       color = {0.55, 0.80, 0.20}, keywords = {} },
  { label = "Earth",        color = {0.65, 0.50, 0.25}, keywords = {} },
  { label = "Shadow",       color = {0.55, 0.30, 0.80}, keywords = {} },
  { label = "Void",         color = {0.20, 0.22, 1.00}, keywords = {} },
  { label = "Combat",       color = {0.80, 0.60, 0.40}, keywords = {} },
  { label = "Arcanes",      color = {0.70, 0.50, 1.00}, keywords = {} },
  { label = "Wind",         color = {0.60, 0.85, 0.80}, keywords = {} },
  { label = "Feral",        color = {0.90, 0.70, 0.20}, keywords = {} },
  { label = "Water",        color = {0.20, 0.60, 1.00}, keywords = {} },
  { label = "Orbes / shield", color = {0.85, 0.75, 1.00}, keywords = {} },
  { label = "Hits",         color = {0.90, 0.90, 0.90}, keywords = {} },
  { label = "Light",        color = {1.00, 1.00, 0.75}, keywords = {} },
  { label = "Shadowflames", color = {0.60, 0.35, 0.60}, keywords = {} },
  { label = "Fel",          color = {0.45, 0.90, 0.20}, keywords = {} },
  { label = "Bronze",       color = {0.80, 0.65, 0.30}, keywords = {} },
  { label = "Misc",         color = {0.65, 0.65, 0.65}, keywords = {} },
  { label = "Death",        color = {0.50, 0.50, 0.55}, keywords = {} },
}

-- Nombre de tags built-in (figé au moment de la déclaration, avant les user-defined)
local MODEL_TAGS_BUILTIN_COUNT = #MODEL_TAGS

-- ExposE pour pouvoir Etre patchE depuis SavedVariables
ns.ModelTags = MODEL_TAGS

-- Merge des keywords depuis SavedVariables au login
do
  local _kwEvt = CreateFrame("Frame")
  _kwEvt:RegisterEvent("PLAYER_LOGIN")
  _kwEvt:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not ns.DB then return end
    -- Charger les tags créés par l'utilisateur
    local utags = ns.DB.modelTagUserDefined
    if utags then
      for _, ut in ipairs(utags) do
        local exists = false
        for _, mt in ipairs(MODEL_TAGS) do
          if mt.label == ut.label then exists = true; break end
        end
        if not exists then
          MODEL_TAGS[#MODEL_TAGS + 1] = { label = ut.label, color = ut.color or {0.6,0.6,0.6}, keywords = {} }
        end
      end
    end
    -- Restaurer les couleurs personnalisées
    local tcolors = ns.DB.modelTagColors
    if tcolors then
      for _, tag in ipairs(MODEL_TAGS) do
        if tcolors[tag.label] then tag.color = tcolors[tag.label] end
      end
    end
    -- Restaurer les keywords
    local kw = ns.DB.modelTagKeywords
    if kw then
      for _, tag in ipairs(MODEL_TAGS) do
        if kw[tag.label] and type(kw[tag.label]) == "table" then
          tag.keywords = kw[tag.label]
        end
      end
    end
  end)
end

-- Popup de confirmation pour la suppression d'un tag
StaticPopupDialogs["AISD_CONFIRM_DELETE_TAG"] = {
  text = L["SETTINGS_CONFIRM_DELETE_TAG"],
  button1 = L["SETTINGS_CONFIRM"], button2 = L["SETTINGS_CANCEL"],
  OnAccept = function(self, data)
    if data and data.callback then data.callback() end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

local ModelPickerFrame  -- singleton créé en lazy

-- Rechargement des tags de modèles lors d'un changement de profil.
-- MODEL_TAGS.keywords est un état mutable partagé : il faut le resynchroniser
-- à chaque switch de profil (PLAYER_LOGIN ne s'exécute qu'une seule fois).
ns.CallbackRegistry:Register("PROFILE_CHANGED", function()
  -- 1. Réinitialiser les keywords des tags built-in
  for i = 1, MODEL_TAGS_BUILTIN_COUNT do
    MODEL_TAGS[i].keywords = {}
  end
  -- 2. Supprimer les tags user-defined de la session précédente
  while #MODEL_TAGS > MODEL_TAGS_BUILTIN_COUNT do table.remove(MODEL_TAGS) end
  -- 3. Réintégrer les tags user-defined du nouveau profil
  local utags = ns.DB and ns.DB.modelTagUserDefined
  if utags then
    for _, ut in ipairs(utags) do
      local exists = false
      for _, mt in ipairs(MODEL_TAGS) do
        if mt.label == ut.label then exists = true; break end
      end
      if not exists then
        MODEL_TAGS[#MODEL_TAGS + 1] = { label = ut.label, color = ut.color or {0.6,0.6,0.6}, keywords = {} }
      end
    end
  end
  -- 4. Restaurer les couleurs de tags
  local tcolors = ns.DB and ns.DB.modelTagColors
  if tcolors then
    for _, tag in ipairs(MODEL_TAGS) do
      if tcolors[tag.label] then tag.color = tcolors[tag.label] end
    end
  end
  -- 5. Restaurer les keywords
  local kw = ns.DB and ns.DB.modelTagKeywords
  if kw then
    for _, tag in ipairs(MODEL_TAGS) do
      if kw[tag.label] and type(kw[tag.label]) == "table" then
        tag.keywords = kw[tag.label]
      end
    end
  end
  -- 6. Rafraîchir la sidebar (picker visible ou non : à la prochaine ouverture l'état sera correct)
  if ModelPickerFrame then
    ModelPickerFrame:RebuildTagSidebar()
  end
end)

-- Indicateur de scroll "moderne" (fin, doré, auto-masquant)
-- Même DA que le scroll principal du panneau de settings (cf. lignes ~105-150) :
-- masque la scrollbar Blizzard et affiche un rail/curseur discret qui ne
-- s'affiche que si le contenu dépasse réellement la zone visible.
-- Alias vers le scrollFrame de PAGE (capture avant que le parametre du meme
-- nom ci-dessous ne le masque) -- necessaire pour relayer la molette quand
-- une zone geree par SetupModernScroll n'a elle-meme rien a defiler (cf.
-- OnMouseWheel plus bas : sans ca, la molette etait avalee silencieusement
-- au lieu de faire defiler la page -- confirme en jeu sur l'editeur
-- d'animation, toujours dimensionne pile a son contenu donc range=0).
-- Deplacee ici (avant EnsureModelPicker, qui l'utilise aussi maintenant)
-- depuis sa position d'origine juste avant Build.SpellEffects.
local _pageScrollFrame = scrollFrame
local function SetupModernScroll(scrollFrame, width, xOffset)
  width = width or 5
  -- xOffset positionne le rail dans la marge réservée à la scrollbar Blizzard
  -- (typiquement -18 sur le bord droit du conteneur) : décalage positif =
  -- vers la droite, à l'intérieur de cette marge plutôt que sur le contenu.
  xOffset = xOffset or 7
  if scrollFrame.ScrollBar then
    scrollFrame.ScrollBar:SetAlpha(0)
    scrollFrame.ScrollBar:EnableMouse(false)
  end
  -- Permettre de scroller à la molette directement sur toute la zone de liste,
  -- pas seulement sur l'ancienne (minuscule) gouttière de la scrollbar Blizzard.
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local max = self:GetVerticalScrollRange()
    if max and max > 0 then
      self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 40)))
    elseif _pageScrollFrame and _pageScrollFrame ~= self then
      -- Rien a defiler ici (range=0) -- relayer a la page englobante plutot
      -- que d'avaler l'evenement (cf. commentaire pres de _pageScrollFrame).
      local handler = _pageScrollFrame:GetScript("OnMouseWheel")
      if handler then handler(_pageScrollFrame, delta) end
    end
  end)

  local track = CreateFrame("Frame", nil, scrollFrame, "BackdropTemplate")
  track:SetWidth(width)
  track:SetPoint("TOPRIGHT",    scrollFrame, "TOPRIGHT",    xOffset, 0)
  track:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", xOffset, 0)
  track:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
                      edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  track:SetBackdropColor(0.08, 0.07, 0.05, 0.80)
  track:SetBackdropBorderColor(0.35, 0.30, 0.18, 0.50)
  track:Hide()

  local thumb = CreateFrame("Frame", nil, track, "BackdropTemplate")
  thumb:SetPoint("LEFT",  track, "LEFT",  0, 0)
  thumb:SetPoint("RIGHT", track, "RIGHT", 0, 0)
  thumb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  thumb:SetBackdropColor(0.776, 0.710, 0.471, 0.88)  -- C6B578

  -- Clic & drag sur le curseur pour defiler rapidement -- purement visuel
  -- avant (juste un indicateur, pas interactif), confirme en jeu comme gene
  -- pour atteindre le bas d'une longue liste. Auto-terminant via IsMouseButtonDown
  -- dans OnUpdate plutot qu'un OnMouseUp pair (sinon un relachement hors du
  -- curseur, tres facile vu sa petite taille, laisserait le drag "colle").
  -- SetHitRectInsets (valeurs negatives = zone cliquable plus GRANDE que le
  -- rendu visuel) : le curseur ne fait que 5px de large, bien trop etroit
  -- pour viser au clic -- confirme en jeu, "trop compliqué de cliquer dessus".
  thumb:EnableMouse(true)
  thumb:SetHitRectInsets(-8, -8, -4, -4)
  thumb:SetScript("OnEnter", function(self) self:SetBackdropColor(1, 0.93, 0.78, 1) end)
  thumb:SetScript("OnLeave", function(self) self:SetBackdropColor(0.776, 0.710, 0.471, 0.88) end)
  thumb:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self:SetScript("OnUpdate", function(self)
      if not IsMouseButtonDown("LeftButton") then
        self:SetScript("OnUpdate", nil)
        return
      end
      local range = scrollFrame:GetVerticalScrollRange()
      if not range or range < 1 then return end
      local scale = track:GetEffectiveScale()
      local _, cursorY = GetCursorPosition()
      cursorY = cursorY / scale
      local trackTop = track:GetTop()
      local trackH   = track:GetHeight()
      local thumbH   = self:GetHeight()
      local maxOff   = math.max(1, trackH - thumbH)
      local offset   = (trackTop - cursorY) - thumbH / 2
      offset = math.max(0, math.min(maxOff, offset))
      scrollFrame:SetVerticalScroll((offset / maxOff) * range)
    end)
  end)

  local function Update()
    local range = scrollFrame:GetVerticalScrollRange()
    if not range or range < 1 then
      track:Hide()
      return
    end
    track:Show()
    local trackH = math.max(1, track:GetHeight() or 100)
    local viewH  = math.max(1, scrollFrame:GetHeight()  or 100)
    local ratio  = viewH / (viewH + range)
    local thumbH = math.max(16, math.floor(trackH * ratio))
    local scroll = scrollFrame:GetVerticalScroll() or 0
    local maxOff = math.max(1, trackH - thumbH)
    local posY   = math.floor((scroll / range) * maxOff)
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPLEFT",  track, "TOPLEFT",  0, -posY)
    thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -posY)
  end

  scrollFrame:HookScript("OnVerticalScroll",     Update)
  scrollFrame:HookScript("OnScrollRangeChanged", Update)
  scrollFrame:HookScript("OnSizeChanged",        Update)
  C_Timer.After(0, Update)
  return track
end

local function EnsureModelPicker()
  if ModelPickerFrame then return ModelPickerFrame end

  local TAG_W = 110  -- largeur colonne tags
  local TAG_MAX_INDICATORS = 6  -- max de petits rectangles colorés avant chaque nom

  -- Custom tags stockés en DB : { [fileID] = { [tagLabel] = true, ... } }
  local function GetCustomTags()
    if not ns.DB then ns.DB = {} end
    if not ns.DB.modelCustomTags then ns.DB.modelCustomTags = {} end
    return ns.DB.modelCustomTags
  end

  local function AddCustomTag(fileID, tagLabel)
    local ct = GetCustomTags()
    if not ct[fileID] then ct[fileID] = {} end
    ct[fileID][tagLabel] = true
  end

  local function RemoveCustomTag(fileID, tagLabel)
    local ct = GetCustomTags()
    if ct[fileID] then ct[fileID][tagLabel] = nil end
  end

  local function HasCustomTag(fileID, tagLabel)
    local ct = GetCustomTags()
    return ct[fileID] and ct[fileID][tagLabel]
  end

  -- Détermine les tags matchés pour un nom de modèle + fileID
  local function GetMatchingTags(modelName, fileID)
    local matched = {}
    local nameLower = strlower(modelName or "")
    for _, tag in ipairs(MODEL_TAGS) do
      local found = false
      -- Match par keywords
      for _, kw in ipairs(tag.keywords) do
        if nameLower:find(kw, 1, true) then found = true; break end
      end
      -- Match par custom tag
      if not found and HasCustomTag(fileID, tag.label) then found = true end
      if found then matched[#matched + 1] = tag end
    end
    return matched
  end

  -- Formate un nom de modèle avec les keywords colorés par tag
  local function FormatNameWithKeywordHighlights(modelName)
    if not modelName or modelName == "" then return modelName end
    local nameLower = strlower(modelName)
    -- Collecter tous les spans (startPos, endPos, color) pour chaque keyword matché
    local spans = {}
    for _, tag in ipairs(MODEL_TAGS) do
      local c = tag.color
      local hex = string.format("|cFF%02x%02x%02x",
        math.floor(c[1] * 255 + 0.5),
        math.floor(c[2] * 255 + 0.5),
        math.floor(c[3] * 255 + 0.5))
      for _, kw in ipairs(tag.keywords) do
        if kw ~= "" then
          local searchStart = 1
          while true do
            local s, e = nameLower:find(kw, searchStart, true)
            if not s then break end
            spans[#spans + 1] = { s = s, e = e, hex = hex }
            searchStart = e + 1
          end
        end
      end
    end
    if #spans == 0 then return modelName end
    -- Trier par position de début, puis par longueur décroissante (plus long match d'abord)
    table.sort(spans, function(a, b)
      if a.s ~= b.s then return a.s < b.s end
      return a.e > b.e
    end)
    -- Fusionner les overlaps : garder le premier span qui couvre chaque position
    local merged = {}
    local coveredUntil = 0
    for _, sp in ipairs(spans) do
      if sp.s > coveredUntil then
        merged[#merged + 1] = sp
        coveredUntil = sp.e
      elseif sp.e > coveredUntil then
        -- Overlap partiel : tronquer le début
        merged[#merged + 1] = { s = coveredUntil + 1, e = sp.e, hex = sp.hex }
        coveredUntil = sp.e
      end
    end
    -- Construire la chaîne finale
    local parts = {}
    local pos = 1
    for _, sp in ipairs(merged) do
      if sp.s > pos then
        parts[#parts + 1] = modelName:sub(pos, sp.s - 1)
      end
      parts[#parts + 1] = sp.hex .. modelName:sub(sp.s, sp.e) .. "|r"
      pos = sp.e + 1
    end
    if pos <= #modelName then
      parts[#parts + 1] = modelName:sub(pos)
    end
    return table.concat(parts)
  end

  local f = CreateFrame("Frame", "AishCoreModelPicker", UIParent, "BackdropTemplate")
  f:SetSize(900 + TAG_W, 640)
  -- FULLSCREEN_DIALOG (pas HIGH) : le panneau principal (MainFrame) est en
  -- DIALOG, qui passe AU-DESSUS de HIGH -- le picker s'affichait donc
  -- derriere la fenetre du GUI qui l'ouvre.
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
  f:SetBackdropBorderColor(unpack(Theme.accent))
  f:SetPoint("CENTER")
  f:Hide()
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

  -- Close button
  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(18, 18)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
  closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
  closeBtn:GetNormalTexture():SetVertexColor(0.7, 0.7, 0.7)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- Title
  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFont(ns.Media.fontTitle, 13, "OUTLINE")
  title:SetPoint("TOP", f, "TOP", 0, -8)
  title:SetTextColor(unpack(Theme.accentText))
  title:SetText(L["SETTINGS_MODEL_PICKER_TITLE"])

  -- Layout columns
  local LEFT_W = 340
  local RIGHT_W = 520

  -- Tag sidebar (colonne gauche)
  local tagFrame = CreateFrame("Frame", nil, f)
  tagFrame:SetWidth(TAG_W)
  tagFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -28)
  tagFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 5, 8)

  local tagTitle = tagFrame:CreateFontString(nil, "OVERLAY")
  tagTitle:SetFont(ns.Media.fontTitle, 10, "OUTLINE")
  tagTitle:SetPoint("TOPLEFT", tagFrame, "TOPLEFT", 4, -2)
  tagTitle:SetTextColor(0.6, 0.6, 0.6)
  tagTitle:SetText(L["SETTINGS_TAGS_HEADER"])

  local tagScrollFrame = CreateFrame("ScrollFrame", nil, tagFrame, "UIPanelScrollFrameTemplate")
  tagScrollFrame:SetPoint("TOPLEFT", tagTitle, "BOTTOMLEFT", 0, -2)
  tagScrollFrame:SetPoint("BOTTOMRIGHT", tagFrame, "BOTTOMRIGHT", -14, 56)
  local tagSC = CreateFrame("Frame", nil, tagScrollFrame)
  tagSC:SetWidth(TAG_W - 14)
  tagSC:SetHeight(1)
  tagScrollFrame:SetScrollChild(tagSC)
  SetupModernScroll(tagScrollFrame)

  -- Message "aucun keyword/categorie" : affiche a la place de la colonne de
  -- tags quand elle est vide (cf. RebuildTagSidebar, visIdx == 0), avec un
  -- lien vers Heroic Support en profiter de l'occasion.
  local noTagsMsg = SW.CreateSupportNag(tagFrame, TAG_W - 8, L["SETTINGS_MODEL_NO_TAGS_MSG"])
  noTagsMsg:SetPoint("TOPLEFT", tagTitle, "BOTTOMLEFT", 0, -206)
  noTagsMsg:Hide()
  f._noTagsMsg = noTagsMsg

  local tagBtnPool = {}
  local tagButtons  = {}
  f._activeTag  = nil   -- label du tag actif ou nil
  f._deleteMode = false -- mode "choisir un tag E supprimer"

  -- RebuildTagSidebar : recrée/reconfigure tous les boutons depuis MODEL_TAGS
  function f:RebuildTagSidebar()
    for _, btn in pairs(tagBtnPool) do btn:Hide() end
    tagButtons = {}

    local _ct    = GetCustomTags()
    local visIdx = 0
    for idx, tag in ipairs(MODEL_TAGS) do
      local btn = tagBtnPool[idx]
      if not btn then
        btn = CreateFrame("Button", nil, tagSC)
        btn:SetSize(TAG_W - 14, 18)
        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints(); btnBg:SetColorTexture(0, 0, 0, 0)
        btn._bg = btnBg
        local colorDot = btn:CreateTexture(nil, "ARTWORK")
        colorDot:SetSize(6, 6)
        colorDot:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn._dot = colorDot
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(ns.Media.fontGui, 10)
        lbl:SetPoint("LEFT", colorDot, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        lbl:SetJustifyH("LEFT")
        btn._lbl = lbl
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        tagBtnPool[idx] = btn
      end

      -- Calculer si ce tag a du contenu (keywords ou custom-tag sur un modèle)
      local _hasContent = #tag.keywords > 0
      if not _hasContent then
        for _, _entries in pairs(_ct) do
          if _entries[tag.label] then _hasContent = true; break end
        end
      end
      if not _hasContent then
        -- pas de contenu : ne pas afficher, passer au suivant
      else
      visIdx = visIdx + 1
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", tagSC, "TOPLEFT", 0, -(visIdx - 1) * 19)
      btn._dot:SetColorTexture(tag.color[1], tag.color[2], tag.color[3], 1)
      btn._lbl:SetText(tag.label)
      btn._lbl:SetTextColor(tag.color[1], tag.color[2], tag.color[3])
      btn._tag = tag

      btn:SetScript("OnEnter", function(s)
        if f._activeTag ~= tag.label then
          s._bg:SetColorTexture(tag.color[1], tag.color[2], tag.color[3], 0.15)
        end
        if f._deleteMode then
          s._lbl:SetTextColor(1, 0.3, 0.3)
        end
      end)
      btn:SetScript("OnLeave", function(s)
        if f._activeTag ~= tag.label then
          s._bg:SetColorTexture(0, 0, 0, 0)
        end
        if f._deleteMode then
          s._lbl:SetTextColor(tag.color[1] * 0.5, tag.color[2] * 0.5, tag.color[3] * 0.5, 0.5)
        end
      end)
      btn:SetScript("OnClick", function(s, button)
        -- Mode suppression : clic gauche ? demande confirmation
        if f._deleteMode and button == "LeftButton" then
          local delTag = tag
          StaticPopup_Show("AISD_CONFIRM_DELETE_TAG", tag.label, nil, {
            callback = function()
              for i, t in ipairs(MODEL_TAGS) do
                if t == delTag then table.remove(MODEL_TAGS, i); break end
              end
              if ns.DB then
                if ns.DB.modelTagKeywords   then ns.DB.modelTagKeywords[delTag.label]   = nil end
                if ns.DB.modelTagColors     then ns.DB.modelTagColors[delTag.label]     = nil end
                if ns.DB.modelTagUserDefined then
                  for i, ut in ipairs(ns.DB.modelTagUserDefined) do
                    if ut.label == delTag.label then table.remove(ns.DB.modelTagUserDefined, i); break end
                  end
                end
              end
              if f._activeTag == delTag.label then
                f._activeTag = nil; f._activeTagKeywords = nil
                if f._searchBox then f._searchBox:SetText(""); f:FilterModels("") end
              end
              f._deleteMode = false
              if f._delBtnLbl then
                f._delBtnBg:SetColorTexture(0.18, 0.04, 0.04, 1)
                f._delBtnLbl:SetText(L["SETTINGS_DELETE"])
                f._delBtnLbl:SetTextColor(1, 0.35, 0.35)
              end
              f:RebuildTagSidebar()
              if kwEditor and kwEditor:IsShown() and kwEditor._tag == delTag then kwEditor:Hide() end
            end
          })
          return
        end
        if button == "RightButton" then
          f:OpenKeywordEditor(tag, s)
          return
        end
        -- Toggle : re-clic sur le tag actif ? reset
        if f._activeTag == tag.label then
          f._activeTag = nil
          f._activeTagKeywords = nil
          s._bg:SetColorTexture(0, 0, 0, 0)
          f._searchBox:SetText("")
          f:FilterModels("")
        else
          for _, b in ipairs(tagButtons) do
            b._bg:SetColorTexture(0, 0, 0, 0)
          end
          f._activeTag = tag.label
          f._activeTagKeywords = tag.keywords
          s._bg:SetColorTexture(tag.color[1], tag.color[2], tag.color[3], 0.30)
          f._searchBox:SetText("[" .. tag.label .. "]")
          f:FilterModels(nil)
        end
      end)
      btn:Show()
      tagButtons[#tagButtons + 1] = btn
      end  -- if _hasContent
    end

    tagSC:SetHeight(math.max(1, visIdx * 19))
    f._tagButtons = tagButtons
    if f._noTagsMsg then
      if visIdx == 0 then f._noTagsMsg:Show() else f._noTagsMsg:Hide() end
    end
    self:RefreshTagDimming()
  end

  -- Bouton "+ Nouveau tag"
  local newTagBtn = CreateFrame("Button", nil, tagFrame)
  newTagBtn:SetSize(TAG_W - 16, 22)
  newTagBtn:SetPoint("BOTTOMLEFT", tagFrame, "BOTTOMLEFT", 2, 30)
  local newTagBtnBg = newTagBtn:CreateTexture(nil, "BACKGROUND")
  newTagBtnBg:SetAllPoints(); newTagBtnBg:SetColorTexture(0.06, 0.16, 0.06, 1)
  local newTagBtnLbl = newTagBtn:CreateFontString(nil, "OVERLAY")
  newTagBtnLbl:SetFont(ns.Media.fontGui, 10); newTagBtnLbl:SetPoint("CENTER")
  newTagBtnLbl:SetText(L["SETTINGS_NEW_TAG_BTN"]); newTagBtnLbl:SetTextColor(0.35, 0.85, 0.35)
  newTagBtn:SetScript("OnEnter", function()
    newTagBtnBg:SetColorTexture(0.10, 0.26, 0.10, 1); newTagBtnLbl:SetTextColor(0.6, 1, 0.6)
  end)
  newTagBtn:SetScript("OnLeave", function()
    newTagBtnBg:SetColorTexture(0.06, 0.16, 0.06, 1); newTagBtnLbl:SetTextColor(0.35, 0.85, 0.35)
  end)
  newTagBtn:SetScript("OnClick", function()
    local n, existingLabels = 1, {}
    for _, t in ipairs(MODEL_TAGS) do existingLabels[t.label] = true end
    while existingLabels[string.format(L["SETTINGS_NEW_TAG_DEFAULT_NAME"], n)] do n = n + 1 end
    local newTag = { label = string.format(L["SETTINGS_NEW_TAG_DEFAULT_NAME"], n), color = {0.6, 0.6, 0.6}, keywords = {} }
    MODEL_TAGS[#MODEL_TAGS + 1] = newTag
    if not ns.DB then ns.DB = {} end
    if not ns.DB.modelTagUserDefined then ns.DB.modelTagUserDefined = {} end
    ns.DB.modelTagUserDefined[#ns.DB.modelTagUserDefined + 1] = { label = newTag.label, color = newTag.color }
    f:RebuildTagSidebar()
    -- Un-dim le nouveau tag (pas encore de keywords, mais on vient de le créer)
    for _, btn in ipairs(tagButtons) do
      if btn._tag == newTag then
        btn._lbl:SetTextColor(newTag.color[1], newTag.color[2], newTag.color[3], 1)
        btn._dot:SetAlpha(1)
        break
      end
    end
    local lastBtn = tagButtons[#tagButtons]
    if lastBtn then f:OpenKeywordEditor(newTag, lastBtn) end
  end)

  -- Bouton "Supprimer" (rouge E mode suppression)
  local delBtn = CreateFrame("Button", nil, tagFrame)
  delBtn:SetSize(TAG_W - 16, 22)
  delBtn:SetPoint("BOTTOMLEFT", tagFrame, "BOTTOMLEFT", 2, 4)
  local delBtnBg = delBtn:CreateTexture(nil, "BACKGROUND")
  delBtnBg:SetAllPoints(); delBtnBg:SetColorTexture(0.18, 0.04, 0.04, 1)
  local delBtnLbl = delBtn:CreateFontString(nil, "OVERLAY")
  delBtnLbl:SetFont(ns.Media.fontGui, 10); delBtnLbl:SetPoint("CENTER")
  delBtnLbl:SetText(L["SETTINGS_DELETE"]); delBtnLbl:SetTextColor(1, 0.35, 0.35)
  f._delBtnBg  = delBtnBg
  f._delBtnLbl = delBtnLbl
  delBtn:SetScript("OnEnter", function()
    delBtnBg:SetColorTexture(0.30, 0.06, 0.06, 1); delBtnLbl:SetTextColor(1, 0.6, 0.6)
  end)
  delBtn:SetScript("OnLeave", function()
    if f._deleteMode then
      delBtnBg:SetColorTexture(0.40, 0.08, 0.08, 1)
    else
      delBtnBg:SetColorTexture(0.18, 0.04, 0.04, 1)
    end
    delBtnLbl:SetTextColor(1, 0.35, 0.35)
  end)
  delBtn:SetScript("OnClick", function()
    f._deleteMode = not f._deleteMode
    if f._deleteMode then
      delBtnBg:SetColorTexture(0.40, 0.08, 0.08, 1)
      delBtnLbl:SetText(L["SETTINGS_CANCEL_BACK"])
    else
      delBtnBg:SetColorTexture(0.18, 0.04, 0.04, 1)
      delBtnLbl:SetText(L["SETTINGS_DELETE"])
      -- Réinitialiser le dimming qui peut être rouge en mode suppression
      f:RebuildTagSidebar()
    end
  end)

  -- Rafraîchir le dimming des tags : un tag est "actif" s'il a des keywords OU des custom tags
  function f:RefreshTagDimming()
    local ct = GetCustomTags()
    for _, btn in ipairs(self._tagButtons) do
      local tag = btn._tag
      local hasContent = #tag.keywords > 0
      if not hasContent then
        -- Vérifier si au moins un modèle a ce tag custom
        for _, entries in pairs(ct) do
          if entries[tag.label] then hasContent = true; break end
        end
      end
      if hasContent then
        btn._lbl:SetTextColor(tag.color[1], tag.color[2], tag.color[3], 1)
        btn._dot:SetAlpha(1)
      else
        btn._lbl:SetTextColor(tag.color[1] * 0.5, tag.color[2] * 0.5, tag.color[3] * 0.5, 0.5)
        btn._dot:SetAlpha(0.35)
      end
    end
  end

  -- Premier rendu (aprEs dEfinition de RefreshTagDimming)
  f:RebuildTagSidebar()

  -- Search box + model list (dEcalEs E droite du tag sidebar)
  local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  SW.StyleEditBox(searchBox)
  searchBox:SetSize(LEFT_W - 10, 20)
  searchBox:SetPoint("TOPLEFT", tagFrame, "TOPRIGHT", 6, 0)
  searchBox:SetAutoFocus(false)
  searchBox:SetScript("OnEscapePressed", function() f:Hide() end)
  f._searchBox = searchBox

  -- Scroll list
  local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -4)
  scrollFrame:SetSize(LEFT_W - 10, 550)
  SetupModernScroll(scrollFrame)
  -- HookScript (n'ecrase pas le OnMouseWheel de SetupModernScroll, qui gere
  -- deja le defilement) : la liste est en virtual scroll (seules les lignes
  -- visibles sont rendues), il faut donc redeclencher RenderVisible() a
  -- chaque molette pour afficher les nouvelles lignes qui entrent dans le
  -- cadre.
  scrollFrame:HookScript("OnMouseWheel", function() f:RenderVisible() end)

  local sc = CreateFrame("Frame", nil, scrollFrame)
  sc:SetWidth(LEFT_W - 30)
  sc:SetHeight(1)
  scrollFrame:SetScrollChild(sc)
  f._sc = sc
  f._sf = scrollFrame

  -- Pool de lignes (virtual scroll E seules les lignes visibles sont rendues)
  local POOL_SIZE = 40  -- largement plus que visible (550px / 20px E 27 lignes)
  local ROW_H = 20
  local TAG_IND_W = 3   -- largeur d'un indicateur
  local TAG_IND_H = 14  -- hauteur
  local TAG_IND_GAP = 1 -- espace entre indicateurs
  local TAG_IND_TOTAL = (TAG_IND_W + TAG_IND_GAP) * TAG_MAX_INDICATORS  -- espace rEservE
  local rows = {}
  for i = 1, POOL_SIZE do
    local row = CreateFrame("Button", nil, sc)
    row:SetSize(LEFT_W - 30, ROW_H)
    -- position assignEe dynamiquement par RenderVisible
    local rbg = row:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints(); rbg:SetColorTexture(0, 0, 0, 0); row._bg = rbg
    -- Indicateurs de tags (petits rectangles colorés à gauche)
    row._tagInds = {}
    for ti = 1, TAG_MAX_INDICATORS do
      local ind = row:CreateTexture(nil, "ARTWORK")
      ind:SetSize(TAG_IND_W, TAG_IND_H)
      ind:SetPoint("LEFT", row, "LEFT", (ti - 1) * (TAG_IND_W + TAG_IND_GAP) + 2, 0)
      ind:SetColorTexture(1, 1, 1, 1)
      ind:Hide()
      row._tagInds[ti] = ind
    end
    local nm = row:CreateFontString(nil, "OVERLAY")
    nm:SetFont(ns.Media.fontGui, 10)
    nm:SetJustifyH("LEFT")
    nm:SetPoint("LEFT", row, "LEFT", TAG_IND_TOTAL + 4, 0)
    nm:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    nm:SetTextColor(unpack(Theme.textNormal))
    row._nm = nm
    row:SetScript("OnEnter", function(s)
      -- Highlight only if not selected
      if f._selectedRow ~= s then
        s._bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.22)
        s._nm:SetTextColor(unpack(Theme.textHighlight))
      end
      -- Tooltip with FileID
      GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
      GameTooltip:SetText(s._modelName or "", 1, 1, 1)
      GameTooltip:AddLine(string.format(L["SETTINGS_TOOLTIP_FILEID"], tostring(s._fileID or "?")), 0.6, 0.6, 0.6)
      GameTooltip:Show()
      -- Preview on hover
      if s._fileID and f._previewModel then
        f._previewModel:ClearModel()
        pcall(function() f._previewModel:SetModel(s._fileID) end)
        pcall(function() f._previewModel:SetPosition(f._pZ or 0, f._pX or 0, f._pY or 0) end)
        local curRot = f._rotSlider and f._rotSlider:GetValue() or 0
        pcall(function() f._previewModel:SetFacing(math.rad(curRot)) end)
        if f._selLabel then
          f._selLabel:SetText((s._modelName or tostring(s._fileID)) .. "  |cff888888(" .. tostring(s._fileID) .. ")|r")
        end
      end
    end)
    row:SetScript("OnLeave", function(s)
      GameTooltip:Hide()
      if f._selectedRow ~= s then
        s._bg:SetColorTexture(0, 0, 0, 0)
        s._nm:SetTextColor(unpack(Theme.textNormal))
      end
      -- Restaurer le modèle sélectionné quand on quitte un row
      local sel = f._selectedRow
      if sel and sel._fileID and f._previewModel then
        f._previewModel:ClearModel()
        pcall(function() f._previewModel:SetModel(sel._fileID) end)
        pcall(function() f._previewModel:SetPosition(f._pZ or 0, f._pX or 0, f._pY or 0) end)
        local curRot = f._rotSlider and f._rotSlider:GetValue() or 0
        pcall(function() f._previewModel:SetFacing(math.rad(curRot)) end)
        if f._selLabel then
          f._selLabel:SetText((sel._modelName or tostring(sel._fileID)) .. "  |cff888888(" .. tostring(sel._fileID) .. ")|r")
        end
      end
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(s, button)
      if button == "RightButton" then
        -- Menu contextuel custom (pas d'EasyMenu, deprecated en Retail)
        if not s._fileID then return end
        f:ShowTagContextMenu(s)
        return
      end
      -- Left click : Select this row (highlight) for preview
      if f._selectedRow and f._selectedRow ~= s then
        f._selectedRow._bg:SetColorTexture(0, 0, 0, 0)
        f._selectedRow._nm:SetTextColor(unpack(Theme.textNormal))
      end
      f._selectedRow = s
      f._selectedModelId = s._fileID
      s._bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.35)
      s._nm:SetTextColor(unpack(Theme.textHighlight))
      -- Load model in preview
      if s._fileID and f._previewModel then
        f._previewModel:ClearModel()
        pcall(function() f._previewModel:SetModel(s._fileID) end)
        pcall(function() f._previewModel:SetPosition(f._pZ or 0, f._pX or 0, f._pY or 0) end)
        local curRot = f._rotSlider and f._rotSlider:GetValue() or 0
        pcall(function() f._previewModel:SetFacing(math.rad(curRot)) end)
        if f._selLabel then
          f._selLabel:SetText((s._modelName or tostring(s._fileID)) .. "  |cff888888(" .. tostring(s._fileID) .. ")|r")
        end
      end
    end)
    row:Hide()
    rows[i] = row
  end

  -- Right-click tag context menu (frame custom, pas d'EasyMenu)
  local ctxMenu = CreateFrame("Frame", nil, f, "BackdropTemplate")
  ctxMenu:SetFrameStrata("TOOLTIP")
  ctxMenu:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  ctxMenu:SetBackdropColor(0.06, 0.06, 0.10, 1.0)
  ctxMenu:SetBackdropBorderColor(0.30, 0.30, 0.35, 1)
  ctxMenu:Hide()
  ctxMenu:EnableMouse(true)
  ctxMenu._rows = {}

  local CTX_ROW_H = 18
  local CTX_W     = 140
  local function GetCtxRow(ci)
    if ctxMenu._rows[ci] then return ctxMenu._rows[ci] end
    local cr = CreateFrame("Button", nil, ctxMenu)
    cr:SetSize(CTX_W - 8, CTX_ROW_H)
    cr:SetPoint("TOPLEFT", ctxMenu, "TOPLEFT", 4, -4 - (ci - 1) * CTX_ROW_H)
    local crBg = cr:CreateTexture(nil, "BACKGROUND")
    crBg:SetAllPoints(); crBg:SetColorTexture(0, 0, 0, 0)
    cr._bg = crBg
    local crDot = cr:CreateTexture(nil, "ARTWORK")
    crDot:SetSize(8, 8); crDot:SetPoint("LEFT", cr, "LEFT", 2, 0)
    cr._dot = crDot
    local crCheck = cr:CreateFontString(nil, "OVERLAY")
    crCheck:SetFont(ns.Media.fontGui, 11)
    crCheck:SetPoint("LEFT", crDot, "RIGHT", 3, 0)
    crCheck:SetTextColor(0.28, 0.78, 0.38)
    crCheck:SetText("")
    cr._check = crCheck
    local crLbl = cr:CreateFontString(nil, "OVERLAY")
    crLbl:SetFont(ns.Media.fontGui, 9); crLbl:SetPoint("LEFT", crCheck, "RIGHT", 2, 0)
    crLbl:SetJustifyH("LEFT")
    cr._lbl = crLbl
    cr._isMatched = false
    cr:SetScript("OnEnter", function(s) if not s._isMatched then s._bg:SetColorTexture(1, 1, 1, 0.08) end end)
    cr:SetScript("OnLeave", function(s) if not s._isMatched then s._bg:SetColorTexture(0, 0, 0, 0) end end)
    ctxMenu._rows[ci] = cr
    return cr
  end

  -- Fermer le menu quand on clique ailleurs
  ctxMenu:SetScript("OnShow", function()
    ctxMenu:SetScript("OnUpdate", function()
      if IsMouseButtonDown("LeftButton") and not ns.IsFrameMouseOver(ctxMenu) then
        ctxMenu:Hide()
      end
    end)
  end)
  ctxMenu:SetScript("OnHide", function()
    ctxMenu:SetScript("OnUpdate", nil)
  end)

  function f:ShowTagContextMenu(row)
    local fid      = row._fileID
    local mName    = row._modelName or ""
    -- Calculer une fois les tags matchés (keyword OU custom) pour ce modèle
    local matched  = GetMatchingTags(mName, fid)
    local matchedSet = {}
    for _, mt in ipairs(matched) do matchedSet[mt.label] = true end

    local n = #MODEL_TAGS
    -- Masquer les lignes du pool au-delE du nombre actuel de tags
    for ci = n + 1, #ctxMenu._rows do ctxMenu._rows[ci]:Hide() end
    ctxMenu:SetSize(CTX_W, 8 + n * CTX_ROW_H)
    for ci, tag in ipairs(MODEL_TAGS) do
      local cr        = GetCtxRow(ci)
      local hasCustom = HasCustomTag(fid, tag.label)
      local isMatched = matchedSet[tag.label] or false
      local c         = tag.color

      cr._dot:SetColorTexture(c[1], c[2], c[3], 1)
      cr._lbl:SetText(tag.label)

      cr._isMatched = isMatched
      if isMatched then
        -- Tag déjà actif : dim total, tiret vert, non-cliquable
        cr._dot:SetColorTexture(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1)
        cr._check:SetText("-")
        cr._lbl:SetTextColor(0.32, 0.32, 0.32)
        cr._bg:SetColorTexture(0, 0, 0, 0)
      else
        -- Tag non actif : pleine couleur, hover actif
        cr._dot:SetColorTexture(c[1], c[2], c[3], 1)
        cr._check:SetText("")
        cr._lbl:SetTextColor(c[1], c[2], c[3])
        cr._bg:SetColorTexture(0, 0, 0, 0)
      end

      cr:SetScript("OnClick", function()
        if hasCustom then RemoveCustomTag(fid, tag.label)
        else              AddCustomTag(fid, tag.label) end
        f:UpdateRowTagIndicators(row)
        f:RefreshTagDimming()
        -- Re-open to refresh checkmarks
        f:ShowTagContextMenu(row)
      end)
    end
    ctxMenu:ClearAllPoints()
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    ctxMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    ctxMenu:Show()
    ctxMenu:Raise()
  end

  -- Mise E jour des indicateurs de tag d'une row
  function f:UpdateRowTagIndicators(row)
    if not row._fileID then return end
    local matched = GetMatchingTags(row._modelName or "", row._fileID)
    for ti = 1, TAG_MAX_INDICATORS do
      local ind = row._tagInds[ti]
      if matched[ti] then
        local c = matched[ti].color
        ind:SetColorTexture(c[1], c[2], c[3], 1)
        ind:Show()
      else
        ind:Hide()
      end
    end
  end
  f._rows = rows

  -- Keyword Editor (clic droit sur un tag de la sidebar)
  local KW_W       = 254
  local KW_H       = 300
  local KW_CHIP_H  = 18
  local KW_PAD     = 6   -- padding horizontal dans un chip
  local KW_X_W     = 16  -- largeur du bouton X
  local KW_GAP_X   = 4
  local KW_GAP_Y   = 4
  local KW_AREA_W  = KW_W - 20  -- largeur utile pour les chips

  local kwEditor = CreateFrame("Frame", "AishCoreKwEditor", f, "BackdropTemplate")
  kwEditor:SetSize(KW_W, KW_H)
  kwEditor:SetFrameStrata("DIALOG")
  kwEditor:SetFrameLevel(f:GetFrameLevel() + 20)
  kwEditor:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  kwEditor:SetBackdropColor(0.05, 0.05, 0.08, 1.0)
  kwEditor:SetBackdropBorderColor(0.35, 0.35, 0.42, 1)
  kwEditor:Hide()
  kwEditor:EnableMouse(true)
  kwEditor:SetMovable(true)
  kwEditor:RegisterForDrag("LeftButton")
  kwEditor:SetScript("OnDragStart", function(s) s:StartMoving() end)
  kwEditor:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
  kwEditor:SetScript("OnShow", function()
    kwEditor:SetScript("OnUpdate", function()
      if IsMouseButtonDown("LeftButton") and not ns.IsFrameMouseOver(kwEditor) then
        kwEditor:Hide()
      end
    end)
  end)
  kwEditor:SetScript("OnHide", function() kwEditor:SetScript("OnUpdate", nil) end)

  local kwCloseBtn = CreateFrame("Button", nil, kwEditor)
  kwCloseBtn:SetSize(16, 16)
  kwCloseBtn:SetPoint("TOPRIGHT", kwEditor, "TOPRIGHT", -5, -5)
  local kwCloseLbl = kwCloseBtn:CreateFontString(nil, "OVERLAY")
  kwCloseLbl:SetFont(ns.Media.fontGui, 11); kwCloseLbl:SetPoint("CENTER"); kwCloseLbl:SetText("x")
  kwCloseLbl:SetTextColor(0.5, 0.5, 0.5)
  kwCloseBtn:SetScript("OnClick",  function() kwEditor:Hide() end)
  kwCloseBtn:SetScript("OnEnter", function() kwCloseLbl:SetTextColor(1, 0.3, 0.3) end)
  kwCloseBtn:SetScript("OnLeave", function() kwCloseLbl:SetTextColor(0.5, 0.5, 0.5) end)

  -- Header : swatch couleur cliquable + EditBox nom du tag
  local kwColorSwatch = CreateFrame("Button", nil, kwEditor)
  kwColorSwatch:SetSize(14, 14)
  kwColorSwatch:SetPoint("TOPLEFT", kwEditor, "TOPLEFT", 6, -6)
  local kwSwatchTex = kwColorSwatch:CreateTexture(nil, "ARTWORK")
  kwSwatchTex:SetAllPoints()
  kwColorSwatch._tex = kwSwatchTex

  local kwNameField = CreateFrame("EditBox", nil, kwEditor, "InputBoxTemplate")
  SW.StyleEditBox(kwNameField)
  kwNameField:SetHeight(18)
  kwNameField:SetPoint("LEFT", kwColorSwatch, "RIGHT", 4, 0)
  kwNameField:SetPoint("RIGHT", kwCloseBtn, "LEFT", -4, 0)
  kwNameField:SetAutoFocus(false)
  kwNameField:SetMaxLetters(48)
  kwNameField:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  kwEditor._nameField   = kwNameField
  kwEditor._colorSwatch = kwColorSwatch

  local kwSep = kwEditor:CreateTexture(nil, "ARTWORK")
  kwSep:SetHeight(1)
  kwSep:SetPoint("TOPLEFT",  kwEditor, "TOPLEFT",  6, -24)
  kwSep:SetPoint("TOPRIGHT", kwEditor, "TOPRIGHT", -6, -24)
  kwSep:SetColorTexture(0.28, 0.28, 0.34, 1)

  -- Zone de scroll pour les chips
  local kwScroll = CreateFrame("ScrollFrame", nil, kwEditor, "UIPanelScrollFrameTemplate")
  kwScroll:SetPoint("TOPLEFT",     kwEditor, "TOPLEFT",     6, -29)
  kwScroll:SetPoint("BOTTOMRIGHT", kwEditor, "BOTTOMRIGHT", -18, 36)
  SetupModernScroll(kwScroll)
  local kwContent = CreateFrame("Frame", nil, kwScroll)
  kwContent:SetWidth(KW_AREA_W)
  kwContent:SetHeight(1)
  kwScroll:SetScrollChild(kwContent)

  -- Ligne d'ajout (bas du panel)
  local kwInputBg = kwEditor:CreateTexture(nil, "ARTWORK")
  kwInputBg:SetColorTexture(0.09, 0.09, 0.12, 1)
  kwInputBg:SetPoint("BOTTOMLEFT",  kwEditor, "BOTTOMLEFT",  6,  6)
  kwInputBg:SetSize(180, 22)

  local kwInput = CreateFrame("EditBox", nil, kwEditor, "InputBoxTemplate")
  SW.StyleEditBox(kwInput)
  kwInput:SetSize(172, 18)
  kwInput:SetPoint("CENTER", kwInputBg, "CENTER", 2, 0)
  kwInput:SetAutoFocus(false)
  kwInput:SetMaxLetters(64)
  kwInput:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

  local kwAddBtn = CreateFrame("Button", nil, kwEditor)
  kwAddBtn:SetSize(54, 22)
  kwAddBtn:SetPoint("LEFT", kwInputBg, "RIGHT", 4, 0)
  local kwAddBg = kwAddBtn:CreateTexture(nil, "BACKGROUND")
  kwAddBg:SetAllPoints(); kwAddBg:SetColorTexture(0.10, 0.28, 0.10, 1)
  local kwAddLbl = kwAddBtn:CreateFontString(nil, "OVERLAY")
  kwAddLbl:SetFont(ns.Media.fontGui, 9); kwAddLbl:SetPoint("CENTER")
  kwAddLbl:SetText(L["SETTINGS_ADD_BTN"]); kwAddLbl:SetTextColor(0.4, 1, 0.4)
  kwAddBtn:SetScript("OnEnter", function() kwAddBg:SetColorTexture(0.14, 0.40, 0.14, 1); kwAddLbl:SetTextColor(1,1,1) end)
  kwAddBtn:SetScript("OnLeave", function() kwAddBg:SetColorTexture(0.10, 0.28, 0.10, 1); kwAddLbl:SetTextColor(0.4, 1, 0.4) end)

  -- Pool de chips
  local chipPool = {}
  local function GetChip(i)
    if chipPool[i] then return chipPool[i] end
    local chip = CreateFrame("Frame", nil, kwContent)
    chip:SetHeight(KW_CHIP_H)
    local cbg = chip:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints(); cbg:SetColorTexture(0.14, 0.14, 0.20, 1)
    chip._bg = cbg
    local clbl = chip:CreateFontString(nil, "OVERLAY")
    clbl:SetFont(ns.Media.fontGui, 9); clbl:SetJustifyH("LEFT")
    clbl:SetTextColor(0.82, 0.82, 0.88)
    clbl:SetPoint("LEFT", chip, "LEFT", KW_PAD, 0)
    chip._lbl = clbl
    local xb = CreateFrame("Button", nil, chip)
    xb:SetSize(KW_X_W, KW_CHIP_H)
    xb:SetPoint("RIGHT", chip, "RIGHT", 0, 0)
    local xbl = xb:CreateFontString(nil, "OVERLAY")
    xbl:SetFont(ns.Media.fontGui, 10); xbl:SetPoint("CENTER"); xbl:SetText("x")
    xbl:SetTextColor(0.42, 0.42, 0.42)
    xb:SetScript("OnEnter", function() xbl:SetTextColor(1, 0.22, 0.22); cbg:SetColorTexture(0.22, 0.09, 0.09, 1) end)
    xb:SetScript("OnLeave", function() xbl:SetTextColor(0.42, 0.42, 0.42); cbg:SetColorTexture(0.14, 0.14, 0.20, 1) end)
    chip._xb = xb
    chipPool[i] = chip
    return chip
  end

  local function SaveTagKeywords(tag)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.modelTagKeywords then ns.DB.modelTagKeywords = {} end
    ns.DB.modelTagKeywords[tag.label] = tag.keywords
  end

  local function SaveTagMeta(tag)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.modelTagColors then ns.DB.modelTagColors = {} end
    ns.DB.modelTagColors[tag.label] = tag.color
    -- Synchroniser le label dans modelTagUserDefined si c'est un tag utilisateur
    if ns.DB.modelTagUserDefined then
      for _, ut in ipairs(ns.DB.modelTagUserDefined) do
        if ut.label == tag.label then ut.color = tag.color; break end
      end
    end
  end

  local function RenameTag(tag, newLabel)
    newLabel = strtrim(newLabel)
    if newLabel == "" or newLabel == tag.label then return end
    local oldLabel = tag.label
    -- Migrer keywords DB
    if ns.DB and ns.DB.modelTagKeywords and ns.DB.modelTagKeywords[oldLabel] then
      ns.DB.modelTagKeywords[newLabel] = ns.DB.modelTagKeywords[oldLabel]
      ns.DB.modelTagKeywords[oldLabel] = nil
    end
    -- Migrer couleurs DB
    if ns.DB and ns.DB.modelTagColors and ns.DB.modelTagColors[oldLabel] then
      ns.DB.modelTagColors[newLabel] = ns.DB.modelTagColors[oldLabel]
      ns.DB.modelTagColors[oldLabel] = nil
    end
    -- Migrer user-defined DB
    if ns.DB and ns.DB.modelTagUserDefined then
      for _, ut in ipairs(ns.DB.modelTagUserDefined) do
        if ut.label == oldLabel then ut.label = newLabel; break end
      end
    end
    -- Migrer modelCustomTags
    if ns.DB and ns.DB.modelCustomTags then
      for _, entries in pairs(ns.DB.modelCustomTags) do
        if entries[oldLabel] then entries[newLabel] = entries[oldLabel]; entries[oldLabel] = nil end
      end
    end
    -- Tag actif : suivre le nouveau label
    if f._activeTag == oldLabel then
      f._activeTag = newLabel
      if f._searchBox then f._searchBox:SetText("[" .. newLabel .. "]") end
    end
    tag.label = newLabel
    f:RebuildTagSidebar()
    -- Rafraîchir le title dans le kwEditor si ouvert
    if kwEditor:IsShown() and kwEditor._tag == tag then
      kwEditor:Rebuild()
    end
  end

  -- Script de validation du nom dans le kwEditor
  kwNameField:SetScript("OnEnterPressed", function(s)
    s:ClearFocus()
    local tag = kwEditor._tag
    if not tag then return end
    RenameTag(tag, s:GetText())
  end)

  -- Color picker depuis le swatch
  kwColorSwatch:SetScript("OnClick", function()
    local tag = kwEditor._tag
    if not tag then return end
    local c = tag.color
    ColorPickerFrame:SetupColorPickerAndShow({
      hasOpacity = false,
      r = c[1], g = c[2], b = c[3],
      swatchFunc = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        tag.color = {r, g, b}
        kwColorSwatch._tex:SetColorTexture(r, g, b, 1)
        SaveTagMeta(tag)
        f:RebuildTagSidebar()
      end,
      cancelFunc = function(prev)
        tag.color = {prev.r, prev.g, prev.b}
        kwColorSwatch._tex:SetColorTexture(prev.r, prev.g, prev.b, 1)
        SaveTagMeta(tag)
        f:RebuildTagSidebar()
      end,
    })
  end)

  function kwEditor:Rebuild()
    local tag = self._tag
    if not tag then return end
    local c = tag.color
    -- Mettre E jour le header
    if self._nameField   then self._nameField:SetText(tag.label) end
    if self._colorSwatch then self._colorSwatch._tex:SetColorTexture(c[1], c[2], c[3], 1) end
    for _, ch in ipairs(chipPool) do ch:Hide() end
    local kws    = tag.keywords
    local rowX   = 2
    local rowY   = -2
    local maxH   = KW_CHIP_H + 4
    for i, kw in ipairs(kws) do
      local chipW = math.ceil(#kw * 6.5) + KW_PAD * 2 + KW_X_W
      chipW = math.max(chipW, 36)
      if rowX + chipW > KW_AREA_W and rowX > 2 then
        rowX = 2
        rowY = rowY - (KW_CHIP_H + KW_GAP_Y)
      end
      local chip = GetChip(i)
      chip._lbl:SetText(kw)
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", kwContent, "TOPLEFT", rowX, rowY)
      chip:SetWidth(chipW)
      chip:Show()
      local idx = i
      chip._xb:SetScript("OnClick", function()
        table.remove(tag.keywords, idx)
        SaveTagKeywords(tag)
        f:RefreshTagDimming()
        kwEditor:Rebuild()
      end)
      rowX = rowX + chipW + KW_GAP_X
      maxH = math.max(maxH, -rowY + KW_CHIP_H + 4)
    end
    if #kws == 0 then
      local empty = GetChip(1)
      empty._lbl:SetText("|cff555555" .. L["SETTINGS_NO_KEYWORD"] .. "|r")
      empty._xb:Hide()
      empty:ClearAllPoints()
      empty:SetPoint("TOPLEFT", kwContent, "TOPLEFT", 2, -2)
      empty:SetWidth(KW_AREA_W)
      empty:Show()
      maxH = KW_CHIP_H + 4
    end
    kwContent:SetHeight(math.max(1, maxH))
    kwScroll:SetVerticalScroll(0)
    kwInput:SetText("")
  end

  local function CommitKw()
    local tag = kwEditor._tag
    if not tag then return end
    local kw = strtrim(kwInput:GetText())
    if kw == "" then return end
    for _, ex in ipairs(tag.keywords) do
      if strlower(ex) == strlower(kw) then kwInput:SetText(""); return end
    end
    tag.keywords[#tag.keywords + 1] = strlower(kw)
    SaveTagKeywords(tag)
    f:RefreshTagDimming()
    kwEditor:Rebuild()
    kwInput:SetText("")
  end
  kwInput:SetScript("OnEnterPressed", function(s) s:ClearFocus(); CommitKw() end)
  kwAddBtn:SetScript("OnClick", CommitKw)

  function f:OpenKeywordEditor(tag, anchorBtn)
    kwEditor._tag = tag
    kwEditor:Rebuild()
    kwEditor:ClearAllPoints()
    kwEditor:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 4, 4)
    kwEditor:Show()
    kwEditor:Raise()
    kwInput:SetFocus()
  end

  f._allModels      = {}   -- { fileId=number, text="name.m2" }
  f._filteredModels = {}   -- sous-ensemble aprEs filtrage
  f._selectedModelId = nil

  -- Rend uniquement les lignes visibles dans le viewport (virtual scroll)
  function f:RenderVisible()
    local filtered = self._filteredModels
    if not filtered then return end
    local total    = #filtered
    local scroll   = self._sf:GetVerticalScroll()
    local viewH    = self._sf:GetHeight()
    local firstIdx = math.floor(scroll / ROW_H) + 1
    local lastIdx  = math.min(firstIdx + math.ceil(viewH / ROW_H) + 2, total)
    -- Masquer tout le pool
    for _, r in ipairs(rows) do r:Hide() end
    -- Assigner les lignes visibles
    local poolIdx = 1
    for dataIdx = firstIdx, lastIdx do
      if poolIdx > POOL_SIZE then break end
      local m = filtered[dataIdx]
      if m then
        local r = rows[poolIdx]
        r._fileID    = m.fileId
        r._modelName = m.text
        r._nm:SetText(FormatNameWithKeywordHighlights(m.text))
        if self._selectedModelId and self._selectedModelId == m.fileId then
          self._selectedRow = r
          r._bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.35)
          r._nm:SetTextColor(unpack(Theme.textHighlight))
        else
          r._bg:SetColorTexture(0, 0, 0, 0)
          r._nm:SetTextColor(unpack(Theme.textNormal))
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -(dataIdx - 1) * ROW_H)
        self:UpdateRowTagIndicators(r)
        r:Show()
        poolIdx = poolIdx + 1
      end
    end
  end

  -- Right panel: controls area (compact E sliders + Ajouter sur une ligne)
  local CTRL_H = 95  -- selLabel + 1 ligne de sliders + bouton

  local ctrlPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
  ctrlPanel:SetHeight(CTRL_H)
  ctrlPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 28)
  ctrlPanel:SetPoint("LEFT", f, "LEFT", TAG_W + LEFT_W + 24, 0)
  ctrlPanel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  ctrlPanel:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
  ctrlPanel:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)

  -- Selected label (inside ctrlPanel)
  local selLabel = ctrlPanel:CreateFontString(nil, "OVERLAY")
  selLabel:SetFont(ns.Media.fontGui, 9)
  selLabel:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 8, -8)
  selLabel:SetPoint("RIGHT", ctrlPanel, "RIGHT", -8, 0)
  selLabel:SetJustifyH("LEFT")
  selLabel:SetTextColor(unpack(Theme.textDim))
  selLabel:SetText(L["SETTINGS_HOVER_MODEL_PREVIEW"])
  f._selLabel = selLabel

  -- 4 sliders + bouton Ajouter : X / Y / Z / Rotation / [Ajouter]
  local _addBtnW = 90
  local _slGap   = 6
  local _ctrlSlW = math.floor(((900 + TAG_W - 12 - (TAG_W + LEFT_W + 24) - 6 - _addBtnW - _slGap) - 3 * _slGap) / 4)

  local xSlider = SW.CreateSlider(ctrlPanel, L["SETTINGS_AXIS_X_LR"], -30, 30, 0.1, _ctrlSlW)
  xSlider:ClearAllPoints()
  xSlider:SetPoint("TOPLEFT", selLabel, "BOTTOMLEFT", 0, -8)
  xSlider:SetValue(0)
  xSlider.onChanged = function(val)
    if f._previewModel then
      f._pX = val
      pcall(function() f._previewModel:SetPosition(f._pZ or 0, f._pX or 0, f._pY or 0) end)
    end
  end
  f._xSlider = xSlider

  local ySlider = SW.CreateSlider(ctrlPanel, L["SETTINGS_AXIS_Y_UD"], -30, 30, 0.1, _ctrlSlW)
  ySlider:ClearAllPoints()
  ySlider:SetPoint("TOPLEFT", selLabel, "BOTTOMLEFT", (_ctrlSlW + _slGap) * 1, -8)
  ySlider:SetValue(0)
  ySlider.onChanged = function(val)
    if f._previewModel then
      f._pY = val
      pcall(function() f._previewModel:SetPosition(f._pZ or 0, f._pX or 0, f._pY or 0) end)
    end
  end
  f._ySlider = ySlider

  local zSlider = SW.CreateSlider(ctrlPanel, L["SETTINGS_AXIS_Z_DEPTH"], -30, 30, 0.1, _ctrlSlW)
  zSlider:ClearAllPoints()
  zSlider:SetPoint("TOPLEFT", selLabel, "BOTTOMLEFT", (_ctrlSlW + _slGap) * 2, -8)
  zSlider:SetValue(0)
  zSlider.onChanged = function(val)
    if f._previewModel then
      f._pZ = val
      pcall(function() f._previewModel:SetPosition(f._pZ or 0, f._pX or 0, f._pY or 0) end)
    end
  end
  f._zSlider = zSlider

  local rotSlider = SW.CreateSlider(ctrlPanel, L["SETTINGS_ROTATION"], 0, 360, 5, _ctrlSlW)
  rotSlider:ClearAllPoints()
  rotSlider:SetPoint("TOPLEFT", selLabel, "BOTTOMLEFT", (_ctrlSlW + _slGap) * 3, -8)
  rotSlider:SetValue(0)
  rotSlider.onChanged = function(val)
    if f._previewModel then
      pcall(function() f._previewModel:SetFacing(math.rad(val)) end)
    end
  end
  f._rotSlider = rotSlider

  -- Bouton "Ajouter" ancrE E droite du footer (ctrlPanel)
  local addBtn = SW.CreateActionBtn(ctrlPanel, L["SETTINGS_ADD_BTN_FULL"], _addBtnW,
    { 0.06, 0.20, 0.06, 0.95 }, nil, Theme.accentGreen)
  addBtn:SetPoint("RIGHT", ctrlPanel, "RIGHT", -6, -8)
  f._addBtn = addBtn

  -- Init stored positions
  f._pZ, f._pX, f._pY = 0, 0, 0

  -- Right panel: preview area (fills space above ctrlPanel)
  local previewBg = CreateFrame("Frame", nil, f)
  previewBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
  previewBg:SetPoint("BOTTOMLEFT", ctrlPanel, "TOPLEFT", 0, 4)
  local pvBgTex = previewBg:CreateTexture(nil, "BACKGROUND")
  pvBgTex:SetAllPoints()
  pvBgTex:SetColorTexture(0.03, 0.03, 0.05, 1)

  local previewModel = CreateFrame("PlayerModel", nil, previewBg)
  previewModel:SetAllPoints()
  previewModel:SetKeepModelOnHide(true)
  f._previewModel = previewModel

  -- Hook scroll bar pour re-rendre lors d'un drag de la scrollbar
  if scrollFrame.ScrollBar then
    scrollFrame.ScrollBar:HookScript("OnValueChanged", function()
      f:RenderVisible()
    end)
  end

  -- Filter & populate
  function f:FilterModels(text)
    local keywords = self._activeTagKeywords
    local activeLabel = self._activeTag
    local t = ""
    if text ~= nil then
      t = strlower(text)
      -- Si l'utilisateur tape du texte manuellement, désactiver le tag actif
      if t ~= "" and not t:find("^%[") then
        self._activeTag = nil
        self._activeTagKeywords = nil
        keywords = nil
        activeLabel = nil
        for _, b in ipairs(self._tagButtons) do b._bg:SetColorTexture(0, 0, 0, 0) end
      end
    end
    local filtered = {}
    for _, m in ipairs(self._allModels) do
      local match = false
      local mLower = strlower(m.text)
      local mId    = tostring(m.fileId)
      if activeLabel then
        -- Mode tag : keyword match OU custom tag
        if keywords and #keywords > 0 then
          for _, kw in ipairs(keywords) do
            if mLower:find(kw, 1, true) then match = true; break end
          end
        end
        if not match and HasCustomTag(m.fileId, activeLabel) then match = true end
      elseif t == "" or t:find("^%[") then
        match = true
      else
        match = mLower:find(t, 1, true) or mId:find(t, 1, true)
      end
      if match then filtered[#filtered + 1] = m end
    end
    self._filteredModels = filtered
    self._selectedRow = nil
    self._selectedModelId = nil
    sc:SetHeight(math.max(1, #filtered * ROW_H))
    self._sf:SetVerticalScroll(0)
    self:RenderVisible()
  end

  searchBox:SetScript("OnTextChanged", function(self)
    local txt = self:GetText()
    -- Ne pas re-filtrer si c'est un tag label formaté [Tag]
    if txt:find("^%[") then return end
    f:FilterModels(txt)
  end)

  function f:Open(onSelect)
    self._onSelect = onSelect
    self._searchBox:SetText("")
    self._selectedRow = nil
    -- Reset tag actif
    self._activeTag = nil
    self._activeTagKeywords = nil
    -- Reconstruction de la sidebar pour refléter le profil courant (user-defined tags)
    self:RebuildTagSidebar()
    for _, b in ipairs(self._tagButtons) do b._bg:SetColorTexture(0, 0, 0, 0) end
    -- Construire self._allModels depuis ns._modelFlat (déjà libéré de AishCoreModelPaths au login)
    if not self._allModels or #self._allModels == 0 then
      local flat = ns._modelFlat
      local models = {}
      if flat then
        for i = 1, #flat do
          local entry = flat[i]
          models[#models + 1] = {
            fileId = entry.fileId,
            text   = StripM2(entry.text),
          }
        end
      end
      -- ns.FoldAccentsLower (Core.lua), cf. commentaire sur `filtered` plus
      -- bas -- strcmputf8i seul ne suffisait pas pour ce client.
      table.sort(models, function(a, b) return ns.FoldAccentsLower(a.text) < ns.FoldAccentsLower(b.text) end)
      self._allModels = models
      -- PrE-remplir le cache de noms
      for _, m in ipairs(models) do
        seModelNameCache[m.fileId] = m.text
      end
    end
    self:FilterModels("")
    self:RefreshTagDimming()
    self:Show()
    self:Raise()
    self._searchBox:SetFocus()
  end

  -- Ajouter OnClick (moved from button creation)
  addBtn:SetScript("OnClick", function()
    if f._selectedRow and f._onSelect and f._selectedRow._fileID then
      f._onSelect(f._selectedRow._fileID, f._selectedRow._modelName)
    end
  end)

  -- Resize handle (bottom-right corner)
  f:SetResizable(true)
  if f.SetResizeBounds then
    -- Même correctif que MainFrame plus haut : plafond large plutôt que
    -- dérivé de GetScreenHeight() (peut être plus petit que l'ancien plafond
    -- fixe selon l'échelle UI, ce qui a empiré le blocage plutôt que de le
    -- résoudre) -- SetClampedToScreen fait la vraie limitation à l'écran.
    f:SetResizeBounds(900 + TAG_W, 640, 3000, 2600)
  end
  local resizeBtn = CreateFrame("Button", nil, f)
  resizeBtn:SetSize(16, 16)
  resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resizeBtn:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  resizeBtn:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    -- Reflow scroll list height
    local h = f:GetHeight()
    scrollFrame:SetHeight(h - 90)
    -- Preview and controls auto-adjust via anchoring
  end)

  f:SetScript("OnHide", function(self)
    self._previewModel:ClearModel()
    self._selectedRow = nil
    self._activeTag = nil
    self._activeTagKeywords = nil
  end)

  ModelPickerFrame = f
  return f
end

-- Spell Picker for Animations 3D (rEutilise les spec spells)
local SESpellPickerFrame  -- singleton sEparE pour SpellEffects

-- Un Button mouse-enabled au-dessus d'un ScrollFrame "avale" la molette
-- (seul le frame topmost avec EnableMouse reçoit l'event) : on relaie
-- explicitement vers le ScrollFrame parent (row -> content -> scrollFrame)
-- pour pouvoir scroller en survolant directement les lignes de la liste.
local function ForwardMouseWheelToScrollParent(row)
  row:EnableMouseWheel(true)
  row:SetScript("OnMouseWheel", function(self, delta)
    local content = self:GetParent()
    local scrollFrame = content and content:GetParent()
    local handler = scrollFrame and scrollFrame:GetScript("OnMouseWheel")
    if handler then handler(scrollFrame, delta) end
  end)
end

-- Spell List (panneau gauche : liste des sorts configurEs)
local function BuildSpellListRow(parent, spellID, width, onClick, combosDB)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, 28)

  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(unpack(Theme.rowHover))
  row.hover:Hide()

  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(0, 0.45, 0.8, 0.25)
  row.sel:Hide()

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.label = row:CreateFontString(nil, "OVERLAY")
  row.label:SetFont(ns.Media.fontGui, 10)
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -24, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetTextColor(unpack(Theme.textNormal))

  row.countText = row:CreateFontString(nil, "OVERLAY")
  row.countText:SetFont(ns.Media.fontGui, 9)
  row.countText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.countText:SetTextColor(unpack(Theme.textDim))

  local name, icon = GetSpellInfo3D(spellID)
  row.icon:SetTexture(icon)
  row.label:SetText(name)
  row.spellID = spellID

  local combos = combosDB or GetCombosDB()
  local n = combos[spellID] and #combos[spellID] or 0
  row.countText:SetText(n > 0 and string.format(L["SETTINGS_FX_COUNT"], n) or "")

  -- Zone invisible par-dessus l'icône : affiche le tooltip natif WoW au survol
  local iconZone = CreateFrame("Frame", nil, row)
  iconZone:SetSize(22, 22)
  iconZone:SetPoint("LEFT", row, "LEFT", 4, 0)
  iconZone:EnableMouse(true)
  iconZone:EnableMouseWheel(true)
  iconZone:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(function() GameTooltip:SetSpellByID(spellID) end)
    GameTooltip:Show()
  end)
  iconZone:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  iconZone:SetScript("OnMouseWheel", function(self, delta)
    local content = row:GetParent()
    local sf = content and content:GetParent()
    local handler = sf and sf:GetScript("OnMouseWheel")
    if handler then handler(sf, delta) end
  end)

  row:SetScript("OnEnter", function(self) self.hover:Show() end)
  row:SetScript("OnLeave", function(self) self.hover:Hide() end)
  row:SetScript("OnClick", function(self)
    if onClick then onClick(self.spellID) end
  end)
  ForwardMouseWheelToScrollParent(row)

  function row:SetSelected(sel)
    self.sel:SetShown(sel)
  end

  return row
end

-- Tooltip simple (1 ligne), avec la meme police que le reste du GUI
-- (ns.Media.fontGui) et la couleur d'accent thematique -- le GameTooltip
-- natif Blizzard rend en police par defaut/blanc sinon, incoherent avec le
-- reste du panneau.
local function AddSimpleTooltip(widget, text)
  widget:HookScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    GameTooltip:AddLine(text)
    local tl = _G["GameTooltipTextLeft1"]
    if tl then
      tl:SetFont(ns.Media.fontGui, 12)
      local c = Theme.accentText or Theme.gold or Theme.accent
      tl:SetTextColor(c[1], c[2], c[3])
    end
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Anim List Row (une entrEe dans le combo du sort)
local function BuildAnimRow(parent, idx, anim, width, onClick, onTriggerChange, hideHC, hideMidLayer)
  local TRIG_CB_W  = 24  -- largeur de colonne par checkbox S/I (gauche)
  local LAYER_CB_W = 22  -- largeur de colonne par checkbox BG/MG/FG (droite)
  local TOGGLE_W   = 28
  local CB_COL_W = TRIG_CB_W
  local LABEL_LEFT = hideHC and 6 or (CB_COL_W * 2 + 6)
  local LABEL_RIGHT = TOGGLE_W + 4 + LAYER_CB_W * 3 + 6

  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, 24)

  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(unpack(Theme.rowHover))
  row.hover:Hide()

  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(0, 0.45, 0.8, 0.25)
  row.sel:Hide()

  -- Checkboxes de declenchement "Sort reussi" (S) / "En incantation" (I) --
  -- meme widget SW.CreateCheckbox que partout ailleurs dans le GUI (carre +
  -- coche), pas le toggle ON/OFF (reserve a l'etat actif/inactif de la
  -- ligne, plus bas). Mutuellement exclusifs comme avant (anim.trigger =
  -- "onhit" ou "casting").
  local trigOnHit = SW.CreateCheckbox(row, "", nil, TRIG_CB_W)
  trigOnHit:SetPoint("LEFT", row, "LEFT", 0, 0)
  local trigCast = SW.CreateCheckbox(row, "", nil, TRIG_CB_W)
  trigCast:SetPoint("LEFT", trigOnHit, "LEFT", TRIG_CB_W, 0)

  local function SetTrigger(trig)
    anim.trigger = trig
    trigOnHit:SetChecked(trig ~= "casting")
    trigCast:SetChecked(trig == "casting")
  end
  SetTrigger(anim.trigger or "onhit")

  trigOnHit.onChanged = function(val)
    SetTrigger(val and "onhit" or "casting")
    if onTriggerChange then onTriggerChange() end
  end
  trigCast.onChanged = function(val)
    SetTrigger(val and "casting" or "onhit")
    if onTriggerChange then onTriggerChange() end
  end

  AddSimpleTooltip(trigOnHit, L["SETTINGS_ANIM_TRIGGER_ONHIT_TT"])
  AddSimpleTooltip(trigCast, L["SETTINGS_ANIM_TRIGGER_CAST_TT"])

  if hideHC then
    trigOnHit:Hide()
    trigCast:Hide()
  end

  row._cbHit  = trigOnHit
  row._cbCast = trigCast

  -- Label
  row.label = row:CreateFontString(nil, "OVERLAY")
  row.label:SetFont(ns.Media.fontGui, 10)
  row.label:SetPoint("LEFT", row, "LEFT", LABEL_LEFT, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -LABEL_RIGHT, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetTextColor(unpack(Theme.textNormal))

  -- Checkboxes de couche "Arriere-plan" (BG) / "Moyen plan" (MG) /
  -- "Premier plan" (FG) -- deplacees ici depuis l'editeur d'animation
  -- (etaient un radio unique partage pour l'anim selectionnee ; chaque ligne
  -- edite maintenant directement sa propre anim.strata). Mutuellement
  -- exclusifs, meme valeurs que l'ancien radio (BACKGROUND/HIGH/FOREGROUND).
  -- Ancrees a la suite du label (ordre gauche->droite : BG, MG, FG, ON/OFF).
  local layerBg = SW.CreateCheckbox(row, "", nil, LAYER_CB_W)
  local layerMg = SW.CreateCheckbox(row, "", nil, LAYER_CB_W)
  local layerFg = SW.CreateCheckbox(row, "", nil, LAYER_CB_W)
  layerBg:SetPoint("LEFT", row.label, "RIGHT", 2, 0)
  layerMg:SetPoint("LEFT", layerBg, "LEFT", LAYER_CB_W, 0)
  layerFg:SetPoint("LEFT", layerMg, "LEFT", LAYER_CB_W, 0)

  local function SetLayer(strata)
    anim.strata = strata
    layerBg:SetChecked(strata ~= "HIGH" and strata ~= "MEDIUM" and strata ~= "FOREGROUND")
    layerMg:SetChecked(strata == "HIGH" or strata == "MEDIUM")
    layerFg:SetChecked(strata == "FOREGROUND")
  end
  SetLayer(anim.strata or "BACKGROUND")

  layerBg.onChanged = function(val) SetLayer(val and "BACKGROUND" or "HIGH") end
  layerMg.onChanged = function(val) SetLayer(val and "HIGH" or "BACKGROUND") end
  layerFg.onChanged = function(val) SetLayer(val and "FOREGROUND" or "BACKGROUND") end

  AddSimpleTooltip(layerBg, L["SETTINGS_LAYER_BACKGROUND"])
  AddSimpleTooltip(layerMg, L["SETTINGS_LAYER_MIDGROUND"])
  AddSimpleTooltip(layerFg, L["SETTINGS_LAYER_FOREGROUND"])

  if hideMidLayer then layerMg:Hide() end

  row._layerBg, row._layerMg, row._layerFg = layerBg, layerMg, layerFg

  -- Toggle ON/OFF (right side)
  local toggleBtn = SW.CreateToggle(row, TOGGLE_W)
  toggleBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
  toggleBtn:SetValue(anim.enabled ~= false)
  -- Sync label dim
  local function UpdateToggle()
    if toggleBtn:GetValue() then
      row.label:SetTextColor(unpack(Theme.textNormal))
    else
      row.label:SetTextColor(0.45, 0.45, 0.45, 1)
    end
  end
  UpdateToggle()
  toggleBtn.onChanged = function(val)
    anim.enabled = val
    UpdateToggle()
  end
  row._toggleBtn = toggleBtn

  local mid = anim.modelID or 0
  local delayStr = (anim.delay and anim.delay > 0) and string.format(" +%.1fs", anim.delay) or ""
  local modelName = GetModelNameByFileID(mid)
  if modelName then
    row.label:SetText(string.format(L["SETTINGS_ANIM_ROW_NAMED"], idx, modelName, delayStr))
  else
    row.label:SetText(string.format(L["SETTINGS_ANIM_ROW_UNNAMED"], idx, mid, delayStr))
  end
  row.animIdx = idx

  row:SetScript("OnEnter", function(self) self.hover:Show() end)
  row:SetScript("OnLeave", function(self) self.hover:Hide() end)
  row:SetScript("OnClick", function(self)
    if onClick then onClick(self.animIdx) end
  end)
  ForwardMouseWheelToScrollParent(row)

  function row:SetSelected(sel)
    self.sel:SetShown(sel)
  end

  function row:RefreshCheckboxes()
    self._cbHit:SetChecked((anim.trigger or "onhit") == "onhit")
    self._cbCast:SetChecked(anim.trigger == "casting")
  end

  return row
end

-- Trigger List Row (pour Globes Externes et Cercle de vie HC)
local function BuildTriggerRow(parent, triggerDef, width, sectionType, onClick)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, 26)

  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0)
  row._bg = bg

  local lbl = row:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 10)
  lbl:SetPoint("LEFT", row, "LEFT", 6, 0)
  lbl:SetPoint("RIGHT", row, "RIGHT", -30, 0)
  lbl:SetJustifyH("LEFT")
  lbl:SetTextColor(unpack(Theme.textNormal))
  lbl:SetText(triggerDef.label)

  -- Indicateur de nombre d'anims
  local fxTxt = row:CreateFontString(nil, "OVERLAY")
  fxTxt:SetFont(ns.Media.fontGui, 8)
  -- Pour les orbes : décaler vers la gauche pour faire place au swatch de couleur
  if sectionType == "orbs" then
    fxTxt:SetPoint("RIGHT", row, "RIGHT", -22, 0)
  else
    fxTxt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  end
  fxTxt:SetTextColor(unpack(Theme.textDim))
  row._fxTxt = fxTxt

  local function UpdateFxCount()
    local db = (sectionType == "orbs") and GetOrbCombosDB() or GetOocCombosDB()
    local dbKey = (sectionType == "orbs") and OrbKeyForClass(triggerDef.key) or triggerDef.key
    local combo = db[dbKey]
    if combo and #combo > 0 then
      fxTxt:SetText(string.format(L["SETTINGS_FX_COUNT"], #combo))
    else
      fxTxt:SetText("")
    end
  end
  UpdateFxCount()

  -- Swatch de couleur des globes (orbes uniquement)
  if sectionType == "orbs" then
    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(14, 14)
    sw:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    local swTex = sw:CreateTexture(nil, "ARTWORK")
    swTex:SetAllPoints()
    -- Couleur initiale depuis la DB
    local gcDB = GetOrbGlobeColorsDB()
    local qKey = OrbKeyForClass(triggerDef.key)
    local gc = gcDB[qKey]
    if gc then
      swTex:SetColorTexture(gc[1], gc[2], gc[3], 1)
    else
      swTex:SetColorTexture(0.3, 0.3, 0.3, 0.7)  -- gris = pas de couleur définie
    end
    sw._tex = swTex
    row._globeSwatch = sw

    sw:SetScript("OnClick", function()
      local gcDB2 = GetOrbGlobeColorsDB()
      local qKey2 = OrbKeyForClass(triggerDef.key)
      local cur = gcDB2[qKey2] or { 1, 1, 1 }
      ColorPickerFrame:SetupColorPickerAndShow({
        hasOpacity = false,
        r = cur[1], g = cur[2], b = cur[3],
        swatchFunc = function()
          local r, g, b = ColorPickerFrame:GetColorRGB()
          gcDB2[qKey2] = { r, g, b }
          swTex:SetColorTexture(r, g, b, 1)
          -- Appliquer en live si la déco orbe est active
          local SE = ns.Modules.SpellEffects
          if SE and SE.RefreshDecorations then SE.RefreshDecorations() end
        end,
        cancelFunc = function(prev)
          gcDB2[qKey2] = { prev.r, prev.g, prev.b }
          swTex:SetColorTexture(prev.r, prev.g, prev.b, 1)
        end,
      })
    end)

    sw:SetScript("OnEnter", function()
      GameTooltip:SetOwner(sw, "ANCHOR_RIGHT")
      GameTooltip:SetText(L["SETTINGS_ORB_GLOBE_COLOR"], 1, 1, 1)
      GameTooltip:AddLine(L["SETTINGS_TT_RIGHT_CLICK_RESET"], 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sw:SetScript("OnMouseUp", function(_, btn)
      if btn == "RightButton" then
        local gcDB2 = GetOrbGlobeColorsDB()
        local qKey2 = OrbKeyForClass(triggerDef.key)
        gcDB2[qKey2] = nil
        swTex:SetColorTexture(0.3, 0.3, 0.3, 0.7)
        local SE = ns.Modules.SpellEffects
        if SE and SE.RefreshDecorations then SE.RefreshDecorations() end
      end
    end)
  end

  local hover = row:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints(); hover:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.12)

  row:SetScript("OnClick", function()
    if onClick then onClick(triggerDef.key) end
  end)
  ForwardMouseWheelToScrollParent(row)

  function row:SetSelected(v)
    self._selected = v
    if v then
      self._bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.22)
    else
      self._bg:SetColorTexture(0, 0, 0, 0)
    end
  end

  function row:RefreshFx() UpdateFxCount() end

  return row
end

-- Build.SpellEffects E construction du panneau complet
function Build.SpellEffects(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_3D_ANIMATIONS"], W))

  -- Activer + toggles Raid/Groupe sur une seule ligne (3 colonnes) pour
  -- gagner de la place -- ces derniers masquent les animations reelles dans
  -- les configs ou elles genent (petit groupe, raid charge visuellement),
  -- cf. Modules/SpellEffects.lua AnimationsBlockedByGroupState, seul point de
  -- garde partage par tous les declencheurs reels (le preview du panneau
  -- reglages n'y est jamais soumis).
  local W3 = math.floor((W - 16) / 3)
  local cb = SW.CreateCheckbox(container, L["SETTINGS_SE_ENABLE"], L["SETTINGS_SE_ENABLE_TT"], W3)
  BindCheckbox(cb, "spellEffects", "enabled")
  local cbRaid = SW.CreateCheckbox(container, L["SETTINGS_SE_DISABLE_RAID"], L["SETTINGS_SE_DISABLE_RAID_TT"], W3)
  BindCheckbox(cbRaid, "spellEffects", "disableAnimsInRaid")
  local cbGroup = SW.CreateCheckbox(container, L["SETTINGS_SE_DISABLE_GROUP"], L["SETTINGS_SE_DISABLE_GROUP_TT"], W3)
  BindCheckbox(cbGroup, "spellEffects", "disableAnimsInGroup")
  ctx:AddRow(8, cb, cbRaid, cbGroup)
  ctx:Spacer(6)

  -- Layout : [Spell List (gauche)] [Anim List + Editor (droite)]
  -- PANEL_H dynamique : on occupe toute la hauteur disponible dans la fenêtre.
  -- scrollFrame:GetHeight() = MainFrame:GetHeight() - TITLE_H - 2*PADDING.
  -- ctx.y est l'offset déjà consommé par l'en-tête et la checkbox au-dessus.
  local PANEL_H
  do
    local sfH = scrollFrame:GetHeight()
    PANEL_H = (sfH > 200) and math.max(400, math.floor(sfH - ctx.y - PADDING)) or 520
  end
  local LEFT_W     = math.floor(W * 0.32)
  local RIGHT_W    = W - LEFT_W - 8
  local LIST_H     = 140     -- hauteur de la liste d'anims dans un combo
  -- Pas de limite de hauteur pour l'éditeur d'animation : il occupe toute la
  -- place disponible sous la liste de combo et s'ajuste à son contenu réel.

  -- Conteneur horizontal
  local hPanel = CreateFrame("Frame", nil, container)
  hPanel:SetSize(W, PANEL_H)
  local hPanelCtxY = ctx.y  -- offset du hPanel dans le container (avant ajout)
  ctx:Add(hPanel)

  -- GAUCHE : Sections repliables (Sorts / Orbes / Cercle OOC)
  local leftPanel = CreateFrame("Frame", nil, hPanel)
  leftPanel:SetSize(LEFT_W, PANEL_H)
  leftPanel:SetPoint("TOPLEFT", hPanel, "TOPLEFT", 0, 0)

  -- Scroll parent pour le panneau gauche (sections empilées)
  local leftScroll = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
  leftScroll:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 0, 0)
  leftScroll:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -2, 0)
  local leftContent = CreateFrame("Frame", nil, leftScroll)
  leftContent:SetWidth(LEFT_W - 20)
  leftScroll:SetScrollChild(leftContent)
  SetupModernScroll(leftScroll)

  -- Helpers pour créer les sections collapsibles
  local seSections = {}  -- { header, body, expanded, divider }
  local SEC_HDR_H  = 22
  local DIVIDER_H  = 6

  local function CreateSectionHdr(parent, label)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(LEFT_W - 20, SEC_HDR_H)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.14, 1)
    local arrow = f:CreateFontString(nil, "OVERLAY")
    arrow:SetFont("Fonts\\ARIALN.TTF", 10)
    arrow:SetPoint("LEFT", f, "LEFT", 4, 0)
    arrow:SetTextColor(unpack(Theme.accentText))
    f._arrow = arrow
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10)
    lbl:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    lbl:SetTextColor(unpack(Theme.textNormal))
    lbl:SetText(label)
    f._label = lbl
    f:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    f:GetHighlightTexture():SetAlpha(0.12)
    return f
  end

  local function CreateSectionDivider(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(LEFT_W - 20, DIVIDER_H)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetSize(LEFT_W - 28, 1)
    tex:SetPoint("CENTER")
    tex:SetColorTexture(0.25, 0.25, 0.30, 0.6)
    return f
  end

  local function UpdateArrow(sec)
    sec.header._arrow:SetText(sec.expanded and "v" or ">")
  end

  -- Section 1 : Sorts
  local sec1 = { expanded = false }
  sec1.header = CreateSectionHdr(leftContent, L["SETTINGS_SEC_CONFIGURED_SPELLS"])
  sec1.body = CreateFrame("Frame", nil, leftContent)
  sec1.body:SetWidth(LEFT_W - 20)
  -- Overhead fixe quand une seule section est ouverte :
  -- 5 en-têtes × SEC_HDR_H(22) + 4 séparateurs × DIVIDER_H(6) = 134 px
  -- (OOC, Sorts, Orbes, Auras, Auras manquantes)
  local SECTIONS_OVERHEAD = 5 * SEC_HDR_H + 4 * DIVIDER_H
  local SPELL_BODY_H = math.max(200, PANEL_H - SECTIONS_OVERHEAD)
  sec1.body:SetHeight(SPELL_BODY_H)

  -- Scroll area pour les sorts (à l'intérieur du body)
  local spellScroll = CreateFrame("ScrollFrame", nil, sec1.body, "UIPanelScrollFrameTemplate")
  spellScroll:SetPoint("TOPLEFT", sec1.body, "TOPLEFT", 0, 0)
  spellScroll:SetPoint("BOTTOMRIGHT", sec1.body, "BOTTOMRIGHT", -18, 58)
  local spellContent = CreateFrame("Frame", nil, spellScroll)
  spellContent:SetSize(LEFT_W - 38, 10)
  spellScroll:SetScrollChild(spellContent)
  seSpellList = spellContent
  seSpellList._rows = {}
  seSpellList._scrollParent = spellScroll
  SetupModernScroll(spellScroll)

  -- Helper : ajouter un spell via ID
  local function AddSpellByID(sid)
    if not sid or sid <= 0 then return end
    local combos = GetCombosDB()
    if not combos[sid] then
      combos[sid] = { NewAnimDefaults() }
    end
    -- Marquer comme ajout manuel si ce n'est pas un sort du grimoire
    local isPseudo = PSEUDO_SPELLS_3D[sid]
    local isPlayer = not isPseudo and IsPlayerSpell and IsPlayerSpell(sid)
    if not isPseudo and not isPlayer then
      local _, cls = UnitClass("player")
      GetManualSpellsDB()[sid] = cls or true
    end
    seActiveSection = "spells"
    do local MB = ns.Auras and ns.Auras.MissingBuffs; if MB and MB.SetPreview then MB.SetPreview(false) end end
    seSelectedSpellID = sid
    seSelectedTriggerKey = nil
    seSelectedAuraID = nil
    seSelectedAnimIdx = 1
    RefreshSpellList()
    if RefreshOrbList then RefreshOrbList() end
    if RefreshOocList then RefreshOocList() end
    if RefreshAuraList then RefreshAuraList() end
    if RefreshMissingBuffsList then RefreshMissingBuffsList() end
    RefreshAnimList()
    RefreshAnimEditor()
    if RefreshAliasRow then RefreshAliasRow() end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end

  -- Boutons Add / Remove
  local _btnHalf = (LEFT_W - 26) / 2 - 2
  local addBtn = SW.CreateActionBtn(sec1.body, L["SETTINGS_ADD_BTN"], _btnHalf,
    { 0.06, 0.14, 0.06, 0.9 }, nil, Theme.accentGreen)
  addBtn:SetPoint("BOTTOMLEFT", sec1.body, "BOTTOMLEFT", 0, 28)

  local remBtn = SW.CreateActionBtn(sec1.body, L["SETTINGS_REMOVE_BTN"], _btnHalf,
    { 0.14, 0.04, 0.04, 0.9 }, nil, { 1, 0.4, 0.4 })
  remBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)

  -- Input SpellID (en bas du body section 1)
  local inputBg = CreateFrame("Frame", nil, sec1.body)
  inputBg:SetSize(LEFT_W - 38, 24)
  inputBg:SetPoint("BOTTOMLEFT", sec1.body, "BOTTOMLEFT", 0, 0)
  do
    local bg = inputBg:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.12, 1)
    local brd = inputBg:CreateTexture(nil, "BORDER")
    brd:SetPoint("TOPLEFT", -1, 1); brd:SetPoint("BOTTOMRIGHT", 1, -1)
    brd:SetColorTexture(unpack(Theme.border))
  end
  local spellInput = CreateFrame("EditBox", nil, inputBg)
  spellInput:SetSize(LEFT_W - 50, 20)
  spellInput:SetPoint("LEFT", inputBg, "LEFT", 6, 0)
  spellInput:SetFont(ns.Media.fontGui, 10, "")
  spellInput:SetTextColor(unpack(Theme.textNormal))
  spellInput:SetAutoFocus(false)
  spellInput:SetMaxLetters(12)
  spellInput:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  spellInput:SetScript("OnEnterPressed", function(s)
    local sid = tonumber(s:GetText())
    if sid then AddSpellByID(sid); s:SetText("") end
    s:ClearFocus()
  end)
  local placeholder = spellInput:CreateFontString(nil, "OVERLAY")
  placeholder:SetFont(ns.Media.fontGui, 10)
  placeholder:SetPoint("LEFT", spellInput, "LEFT", 0, 0)
  placeholder:SetTextColor(unpack(Theme.textDim))
  placeholder:SetText(L["SETTINGS_SPELLID_PLACEHOLDER"])
  spellInput:SetScript("OnTextChanged", function(s)
    placeholder:SetShown(s:GetText() == "")
  end)

  -- Section OOC : Cercle de vie Hors-Combat
  local secOoc = { expanded = false, id = "ooc" }
  secOoc.header = CreateSectionHdr(leftContent, L["SETTINGS_SEC_HC_OOC"])
  secOoc.body = CreateFrame("Frame", nil, leftContent)
  secOoc.body:SetWidth(LEFT_W - 20)
  secOoc.body:Hide()

  -- Scroll area pour les triggers OOC
  local oocScroll = CreateFrame("ScrollFrame", nil, secOoc.body, "UIPanelScrollFrameTemplate")
  oocScroll:SetPoint("TOPLEFT", secOoc.body, "TOPLEFT", 0, 0)
  oocScroll:SetPoint("BOTTOMRIGHT", secOoc.body, "BOTTOMRIGHT", -18, 0)
  local oocContent = CreateFrame("Frame", nil, oocScroll)
  oocContent:SetSize(LEFT_W - 38, 10)
  oocScroll:SetScrollChild(oocContent)
  seOocList = oocContent
  seOocList._rows = {}
  SetupModernScroll(oocScroll)

  local oocTriggers = GetOocTriggers()
  local oocBodyH = math.max(60, #oocTriggers * 28 + 4)
  secOoc.body:SetHeight(oocBodyH)

  -- Section Spells : Sorts configurés (sec1 — déjà créé au-dessus)
  local secSpells = sec1
  secSpells.id = "spells"

  -- Section Orbs : Globes Externes
  local secOrbs = { expanded = false, id = "orbs" }
  secOrbs.header = CreateSectionHdr(leftContent, L["SETTINGS_DOT_EXTERNAL"])
  secOrbs.body = CreateFrame("Frame", nil, leftContent)
  secOrbs.body:SetWidth(LEFT_W - 20)
  secOrbs.body:Hide()

  -- Scroll area pour les triggers orbes
  local orbScroll = CreateFrame("ScrollFrame", nil, secOrbs.body, "UIPanelScrollFrameTemplate")
  orbScroll:SetPoint("TOPLEFT", secOrbs.body, "TOPLEFT", 0, 0)
  orbScroll:SetPoint("BOTTOMRIGHT", secOrbs.body, "BOTTOMRIGHT", -18, 0)
  local orbContent = CreateFrame("Frame", nil, orbScroll)
  orbContent:SetSize(LEFT_W - 38, 10)
  orbScroll:SetScrollChild(orbContent)
  seOrbList = orbContent
  seOrbList._rows = {}
  SetupModernScroll(orbScroll)

  -- Calculer la hauteur selon les triggers disponibles
  local orbTriggers = GetClassOrbTriggers()
  local orbBodyH = math.max(60, #orbTriggers * 28 + 4)
  secOrbs.body:SetHeight(orbBodyH)

  -- Griser et désactiver Globes externes si aucun trigger pour cette classe
  local orbsDisabled = (#orbTriggers == 0)
  if orbsDisabled then
    secOrbs.header._label:SetTextColor(0.40, 0.40, 0.40)
    secOrbs.header._arrow:SetTextColor(0.40, 0.40, 0.40)
    secOrbs.header:GetHighlightTexture():SetAlpha(0)
  end

  -- Section Auras : combos déclenchés par la présence d'une aura
  -- (même liste que "Auras à tracker" — apparition de l'aura → lecture en boucle)
  local secAuras = { expanded = false, id = "auras" }
  secAuras.header = CreateSectionHdr(leftContent, L["SETTINGS_AURAS"])
  secAuras.body = CreateFrame("Frame", nil, leftContent)
  secAuras.body:SetWidth(LEFT_W - 20)
  secAuras.body:Hide()

  -- Scroll area pour la liste d'auras
  local auraScroll = CreateFrame("ScrollFrame", nil, secAuras.body, "UIPanelScrollFrameTemplate")
  auraScroll:SetPoint("TOPLEFT", secAuras.body, "TOPLEFT", 0, 0)
  auraScroll:SetPoint("BOTTOMRIGHT", secAuras.body, "BOTTOMRIGHT", -18, 0)
  local auraContent = CreateFrame("Frame", nil, auraScroll)
  auraContent:SetSize(LEFT_W - 38, 10)
  auraScroll:SetScrollChild(auraContent)
  seAuraList = auraContent
  seAuraList._rows = {}
  SetupModernScroll(auraScroll)

  local AURA_BODY_H = math.max(150, PANEL_H - SECTIONS_OVERHEAD)
  secAuras.body:SetHeight(AURA_BODY_H)

  -- Section Buffs manquants : combos déclenchés par le module dédié
  -- "Buffs manquants" (Modules/Auras/Core/MissingBuffs.lua) -- liste de
  -- sorts restreinte à ns.Auras.MissingBuffs.GetTriggerSpells() (buffs de
  -- classe + postures/auras/accords + familiers/poisons selon la classe),
  -- PAS la liste générale des sorts trackés comme "Auras manquantes"
  -- ci-dessus. Runtime miroir dans Modules/SpellEffects.lua
  -- (ScanMissingBuffCombos), ancré sur AishCoreMissingBuffFrame au lieu du
  -- cercle central -- cf. GetPreviewAnchor plus haut.
  local secMissingBuffs = { expanded = false, id = "missingBuffs" }
  secMissingBuffs.header = CreateSectionHdr(leftContent, L["AURASDATA_SEC_MISSINGBUFFS_LABEL"])
  secMissingBuffs.body = CreateFrame("Frame", nil, leftContent)
  secMissingBuffs.body:SetWidth(LEFT_W - 20)
  secMissingBuffs.body:Hide()

  local missingBuffsScroll = CreateFrame("ScrollFrame", nil, secMissingBuffs.body, "UIPanelScrollFrameTemplate")
  missingBuffsScroll:SetPoint("TOPLEFT", secMissingBuffs.body, "TOPLEFT", 0, 0)
  missingBuffsScroll:SetPoint("BOTTOMRIGHT", secMissingBuffs.body, "BOTTOMRIGHT", -18, 0)
  local missingBuffsContent = CreateFrame("Frame", nil, missingBuffsScroll)
  missingBuffsContent:SetSize(LEFT_W - 38, 10)
  missingBuffsScroll:SetScrollChild(missingBuffsContent)
  seMissingBuffsList = missingBuffsContent
  seMissingBuffsList._rows = {}
  SetupModernScroll(missingBuffsScroll)

  local MISSING_BUFFS_BODY_H = math.max(150, PANEL_H - SECTIONS_OVERHEAD)
  secMissingBuffs.body:SetHeight(MISSING_BUFFS_BODY_H)

  -- Sections ordonnées : OOC, Sorts, Orbes, Auras, Buffs manquants
  seSections[1] = secOoc
  seSections[2] = secSpells
  seSections[3] = secOrbs
  seSections[4] = secAuras
  seSections[5] = secMissingBuffs

  secOoc.divider    = CreateSectionDivider(leftContent)
  secSpells.divider = CreateSectionDivider(leftContent)
  secOrbs.divider   = CreateSectionDivider(leftContent)
  secAuras.divider  = CreateSectionDivider(leftContent)
  -- pas de divider après la dernière section

  for _, sec in ipairs(seSections) do UpdateArrow(sec) end

  -- Nag "Heroic Support" sous les accordeons : seulement si l'utilisateur a
  -- configure moins de 4 combos d'animation (comptes par spellID distinct,
  -- cf. GetCombosDB) -- repositionne dans RelayoutSections ci-dessous pour
  -- rester APRES la derniere section, quel que soit l'etat plie/deplie.
  local seSupportNag
  do
    local comboCount = 0
    for _, list in pairs(GetCombosDB()) do
      if list and #list > 0 then comboCount = comboCount + 1 end
    end
    if comboCount < 4 then
      seSupportNag = SW.CreateSupportNag(leftContent, LEFT_W - 20, L["SETTINGS_SPELLEFFECTS_FEW_COMBOS_MSG"])
    end
  end

  -- Layout & toggle des sections (accordéon)
  RelayoutSections = function()
    local y = 0
    for i, sec in ipairs(seSections) do
      sec.header:ClearAllPoints()
      sec.header:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -y)
      y = y + SEC_HDR_H
      if sec.expanded then
        sec.body:ClearAllPoints()
        sec.body:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -y)
        sec.body:Show()
        y = y + sec.body:GetHeight()
      else
        sec.body:Hide()
      end
      -- Divider (entre les sections, pas après la dernière)
      if sec.divider then
        sec.divider:ClearAllPoints()
        sec.divider:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -y)
        y = y + DIVIDER_H
      end
    end
    if seSupportNag then
      y = y + 6
      seSupportNag:ClearAllPoints()
      seSupportNag:SetPoint("TOPLEFT", leftContent, "TOPLEFT", 0, -y)
      y = y + seSupportNag:GetHeight()
    end
    local totalH = math.max(PANEL_H, y)
    leftContent:SetHeight(totalH)
    -- Étirer leftPanel, hPanel et container au contenu réel :
    -- élimine le scroll interne de l'accordéon.
    -- Le scroll global (scrollFrame principal) prend le relais si besoin.
    leftPanel:SetHeight(totalH)
    local rh = rightPanel and rightPanel:GetHeight() or PANEL_H
    local newH = math.max(totalH, rh)
    hPanel:SetHeight(newH)
    container:SetHeight(hPanelCtxY + newH + 2 + PADDING)
  end

  local function ToggleSection(secIdx)
    local sec = seSections[secIdx]
    -- Si la section Orbes est désactivée, ne rien faire
    if sec.id == "orbs" and orbsDisabled then return end
    local opening = not sec.expanded
    -- Accordéon : fermer toutes les autres si on ouvre celle-ci
    if opening then
      for i, s in ipairs(seSections) do
        if i ~= secIdx and s.expanded then
          s.expanded = false
          UpdateArrow(s)
        end
      end
    end
    sec.expanded = opening
    UpdateArrow(sec)
    RelayoutSections()
  end

  secOoc.header:SetScript("OnClick",    function() ToggleSection(1) end)
  secSpells.header:SetScript("OnClick", function() ToggleSection(2) end)
  secOrbs.header:SetScript("OnClick",   function() ToggleSection(3) end)
  secAuras.header:SetScript("OnClick",  function() ToggleSection(4) end)
  secMissingBuffs.header:SetScript("OnClick", function() ToggleSection(5) end)

  -- Aucune section ouverte par défaut (l'utilisateur choisit) -- les flèches
  -- sont déjà à jour (cf. boucle UpdateArrow plus haut).
  RelayoutSections()

  -- DROITE : Combo list + Animation editor
  local rightPanel = CreateFrame("Frame", nil, hPanel)
  rightPanel:SetSize(RIGHT_W, PANEL_H)
  rightPanel:SetPoint("TOPRIGHT", hPanel, "TOPRIGHT", 0, 0)

  -- Titre
  local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY")
  rightTitle:SetFont(ns.Media.fontGui, 10)
  rightTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -2)
  rightTitle:SetTextColor(unpack(Theme.textDim))
  rightTitle:SetText(L["SETTINGS_COMBO_NO_SPELL_SELECTED"])

  -- En-têtes de colonnes pour les toggles (Sort réussi / En incantation) --
  -- offsets alignes sur TRIG_TOGGLE_W/CB_COL_W de BuildAnimRow (28/32).
  local colHeaderFrame = CreateFrame("Frame", nil, rightPanel)
  colHeaderFrame:SetSize(RIGHT_W - 18, 14)
  colHeaderFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -16)

  local hdrHit = colHeaderFrame:CreateFontString(nil, "OVERLAY")
  hdrHit:SetFont(ns.Media.fontGui, 8)
  hdrHit:SetPoint("LEFT", colHeaderFrame, "LEFT", 6, 0)
  hdrHit:SetTextColor(unpack(Theme.textDim))
  hdrHit:SetText("S")

  local hdrCast = colHeaderFrame:CreateFontString(nil, "OVERLAY")
  hdrCast:SetFont(ns.Media.fontGui, 8)
  hdrCast:SetPoint("LEFT", colHeaderFrame, "LEFT", 30, 0)
  hdrCast:SetTextColor(unpack(Theme.textDim))
  hdrCast:SetText("I")

  local hdrModel = colHeaderFrame:CreateFontString(nil, "OVERLAY")
  hdrModel:SetFont(ns.Media.fontGui, 8)
  hdrModel:SetPoint("LEFT", colHeaderFrame, "LEFT", 46, 0)
  hdrModel:SetTextColor(unpack(Theme.textDim))
  hdrModel:SetText(L["SETTINGS_MODEL"])

  -- En-têtes de colonnes pour les checkboxes de couche (BG/MG/FG), a droite
  -- -- offsets alignes sur TOGGLE_W/LAYER_CB_W de BuildAnimRow (28/22).
  -- Hitbox Button (pas juste un FontString, non-interactif) pour le survol.
  local function MakeLayerColHeader(text, tooltipText, rightOffset)
    local hitbox = CreateFrame("Button", nil, colHeaderFrame)
    hitbox:SetSize(20, 14)
    hitbox:SetPoint("RIGHT", colHeaderFrame, "RIGHT", -rightOffset, 0)
    local lbl = hitbox:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 8)
    lbl:SetAllPoints()
    lbl:SetTextColor(unpack(Theme.textDim))
    lbl:SetText(text)
    AddSimpleTooltip(hitbox, tooltipText)
    return hitbox
  end
  local hdrLayerFg = MakeLayerColHeader("FG", L["SETTINGS_LAYER_FOREGROUND"], 28 + 4 + 6)
  local hdrLayerMg = MakeLayerColHeader("MG", L["SETTINGS_LAYER_MIDGROUND"],  28 + 4 + 22 + 6)
  local hdrLayerBg = MakeLayerColHeader("BG", L["SETTINGS_LAYER_BACKGROUND"], 28 + 4 + 22 * 2 + 6)

  -- Références pour masquer les colonnes selon la section active
  local _hdrHit  = hdrHit
  local _hdrCast = hdrCast
  local _hdrModel = hdrModel
  local _hdrLayerMg = hdrLayerMg

  -- Scroll area pour la liste d'anims du combo
  local animScroll = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
  animScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -32)
  animScroll:SetSize(RIGHT_W - 18, LIST_H - 18)

  local animContent = CreateFrame("Frame", nil, animScroll)
  animContent:SetSize(RIGHT_W - 18, 10)
  animScroll:SetScrollChild(animContent)
  seAnimList = animContent
  seAnimList._rows = {}
  seAnimList._rightTitle = rightTitle
  SetupModernScroll(animScroll)

  -- Boutons Add/Remove anim + Preview combo
  local animBtnW = math.floor((RIGHT_W - 18) / 3) - 3
  local animAddBtn = SW.CreateActionBtn(rightPanel, L["SETTINGS_ANIM_ADD_BTN"], animBtnW,
    { 0.06, 0.14, 0.06, 0.9 }, nil, Theme.accentGreen)
  animAddBtn:SetPoint("TOPLEFT", animScroll, "BOTTOMLEFT", 0, -4)

  local animRemBtn = SW.CreateActionBtn(rightPanel, L["SETTINGS_ANIM_REMOVE_BTN"], animBtnW,
    { 0.14, 0.04, 0.04, 0.9 }, nil, { 1, 0.4, 0.4 })
  animRemBtn:SetPoint("LEFT", animAddBtn, "RIGHT", 4, 0)

  local previewComboBtn = SW.CreateActionBtn(rightPanel, L["SETTINGS_PREVIEW_COMBO_BTN"], animBtnW,
    { 0.08, 0.08, 0.16, 0.9 }, nil, Theme.accent)
  previewComboBtn:SetPoint("LEFT", animRemBtn, "RIGHT", 4, 0)
  previewComboBtn:SetScript("OnLeave", function(s)
    local SE = ns.Modules.SpellEffects
    if SE and SE.IsComboPreviewLooping and SE.IsComboPreviewLooping() then
      s._lbl:SetTextColor(0.3, 1, 0.3)
    else
      s._lbl:SetTextColor(unpack(Theme.accentText))
    end
  end)

  -- Ligne "Alt IDs" : IDs déclencheurs alternatifs pour le sort sélectionné
  local _aliasChips = {}
  local seAliasInput

  -- Deplacee sur la meme ligne que le titre "Combo : Nom du sort" -- PAS
  -- tout a droite (ca overlappait les en-tetes de colonnes BG/MG/FG, qui
  -- occupent la meme zone plus bas) : decalee vers la gauche pour degager
  -- cette zone. Etait avant sous la ligne de boutons Add/Remove/Preview combo.
  local aliasRow = CreateFrame("Frame", nil, rightPanel)
  aliasRow:SetSize(230, 22)
  aliasRow:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -100, -1)
  aliasRow:Hide()  -- visible seulement quand un sort est sélectionné

  local aliasLabel = aliasRow:CreateFontString(nil, "OVERLAY")
  aliasLabel:SetFont(ns.Media.fontGui, 9)
  aliasLabel:SetPoint("LEFT", aliasRow, "LEFT", 2 - 120, 0)
  aliasLabel:SetTextColor(unpack(Theme.textDim))
  aliasLabel:SetText(L["SETTINGS_ALT_IDS"])
  aliasLabel:SetWidth(44)

  -- Zone des chips (alias existants)
  local aliasChipsFrame = CreateFrame("Frame", nil, aliasRow)
  aliasChipsFrame:SetHeight(22)
  aliasChipsFrame:SetPoint("LEFT", aliasRow, "LEFT", 48, 0)
  aliasChipsFrame:SetPoint("RIGHT", aliasRow, "RIGHT", -90, 0)
  aliasChipsFrame:SetClipsChildren(true)

  -- input SpellID
  do
    local ibg = CreateFrame("Frame", nil, aliasRow)
    ibg:SetSize(60, 18)
    ibg:SetPoint("RIGHT", aliasRow, "RIGHT", -26 - 180, 0)
    ibg:SetPoint("TOP",   aliasRow, "TOP",   0,   -4)
    local bg2 = ibg:CreateTexture(nil, "BACKGROUND")
    bg2:SetAllPoints(); bg2:SetColorTexture(0.10, 0.10, 0.12, 1)
    local brd2 = ibg:CreateTexture(nil, "BORDER")
    brd2:SetPoint("TOPLEFT", -1, 1); brd2:SetPoint("BOTTOMRIGHT", 1, -1)
    brd2:SetColorTexture(unpack(Theme.border))
    seAliasInput = CreateFrame("EditBox", nil, ibg)
    seAliasInput:SetSize(56, 16)
    seAliasInput:SetPoint("CENTER", ibg, "CENTER")
    seAliasInput:SetFont(ns.Media.fontGui, 9, "")
    seAliasInput:SetTextColor(unpack(Theme.textNormal))
    seAliasInput:SetAutoFocus(false)
    seAliasInput:SetMaxLetters(10)
    seAliasInput:SetNumeric(true)
    local aliasPh = seAliasInput:CreateFontString(nil, "OVERLAY")
    aliasPh:SetFont(ns.Media.fontGui, 8)
    aliasPh:SetPoint("LEFT", seAliasInput, "LEFT", 0, 0)
    aliasPh:SetTextColor(unpack(Theme.textDim))
    aliasPh:SetText(L["SETTINGS_SPELLID_PLACEHOLDER"])
    seAliasInput:SetScript("OnTextChanged", function(s) aliasPh:SetShown(s:GetText() == "") end)
    seAliasInput:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    seAliasInput:SetScript("OnEnterPressed", function(s)
      local aliasID = tonumber(s:GetText())
      if aliasID and aliasID > 0 and seSelectedSpellID then
        GetCombosAliasesDB()[aliasID] = seSelectedSpellID
        s:SetText(""); RefreshAliasRow()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      end
      s:ClearFocus()
    end)
  end

  -- Bouton "+" alias -- construit a la main (pas SW.CreateActionBtn, dont la
  -- hauteur est fixee en dur a 24px) pour matcher la hauteur 18px du champ
  -- SpellID juste a cote (CreateActionBtn le rendait visiblement trop gros).
  local aliasAddBtn = CreateFrame("Button", nil, aliasRow, "BackdropTemplate")
  aliasAddBtn:SetSize(18, 18)
  aliasAddBtn:SetPoint("RIGHT", aliasRow, "RIGHT", -2 - 180, 0)
  aliasAddBtn:SetPoint("TOP",   aliasRow, "TOP",   0, -4)
  aliasAddBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  aliasAddBtn:SetBackdropColor(0.06, 0.14, 0.06, 0.9)
  aliasAddBtn:SetBackdropBorderColor(unpack(Theme.border))
  local aliasAddLbl = aliasAddBtn:CreateFontString(nil, "OVERLAY")
  aliasAddLbl:SetFont(ns.Media.fontGui, 11)
  aliasAddLbl:SetAllPoints()
  aliasAddLbl:SetJustifyH("CENTER")
  aliasAddLbl:SetTextColor(unpack(Theme.accentGreen))
  aliasAddLbl:SetText("+")
  aliasAddBtn:SetScript("OnEnter", function() aliasAddLbl:SetTextColor(1, 1, 1) end)
  aliasAddBtn:SetScript("OnLeave", function() aliasAddLbl:SetTextColor(unpack(Theme.accentGreen)) end)
  aliasAddBtn:SetScript("OnClick", function()
    if not seAliasInput or not seSelectedSpellID then return end
    local aliasID = tonumber(seAliasInput:GetText())
    if aliasID and aliasID > 0 then
      GetCombosAliasesDB()[aliasID] = seSelectedSpellID
      seAliasInput:SetText(""); RefreshAliasRow()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
  end)

  -- DROITE BAS : Éditeur d'animation (compact : sliders 3 par ligne)
  -- La ligne Alt IDs est maintenant sur la meme ligne que le titre (en haut
  -- a droite), plus besoin de lui reserver de la place ici sous les boutons
  -- Add/Remove/Preview combo.
  local editorTop = animScroll:GetHeight() + 20 + 26 + 20
  local editorFrame = CreateFrame("Frame", nil, rightPanel)
  editorFrame:SetWidth(RIGHT_W)
  editorFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 0, -editorTop)
  seAnimEditor = editorFrame

  -- Sous-titre
  local editorTitle = editorFrame:CreateFontString(nil, "OVERLAY")
  editorTitle:SetFont(ns.Media.fontGui, 10)
  editorTitle:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 4, -2)
  editorTitle:SetTextColor(unpack(Theme.textDim))
  editorTitle:SetText(L["SETTINGS_ANIM_EDITOR_TITLE"])
  seAnimEditor._title = editorTitle

  -- Conteneur scrollable pour les contrEles de l'éditeur
  local edScroll = CreateFrame("ScrollFrame", nil, editorFrame, "UIPanelScrollFrameTemplate")
  edScroll:SetPoint("TOPLEFT", editorFrame, "TOPLEFT", 0, -18)
  edScroll:SetPoint("BOTTOMRIGHT", editorFrame, "BOTTOMRIGHT", -18, 0)

  local edContent = CreateFrame("Frame", nil, edScroll)
  edContent:SetSize(RIGHT_W - 18, 500)
  edScroll:SetScrollChild(edContent)
  SetupModernScroll(edScroll)

  local edW = RIGHT_W - 24

  -- Fonction helper pour update un champ de l'anim sélectionnée
  local function SetAnimField(field, value)
    if not seSelectedAnimIdx then return end
    local db, key = GetActiveComboTable()
    if not db or not key then return end
    local combo = db[key]
    if not combo or not combo[seSelectedAnimIdx] then return end
    combo[seSelectedAnimIdx][field] = value
  end

  -- ModelID input + Model name display
  local modelIDLabel = edContent:CreateFontString(nil, "OVERLAY")
  modelIDLabel:SetFont(ns.Media.fontGui, 10)
  modelIDLabel:SetPoint("TOPLEFT", edContent, "TOPLEFT", 4, -4)
  modelIDLabel:SetTextColor(unpack(Theme.textNormal))
  modelIDLabel:SetText(L["SETTINGS_MODEL_FILE_ID"])

  local pickerBtnW = 74
  local previewBtnW = 70
  local modelInputW = edW - pickerBtnW - previewBtnW - 12

  local modelIDInputBg = CreateFrame("Frame", nil, edContent)
  modelIDInputBg:SetSize(modelInputW, 22)
  modelIDInputBg:SetPoint("TOPLEFT", edContent, "TOPLEFT", 4, -18)
  do
    local bg = modelIDInputBg:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.12, 1)
    local brd = modelIDInputBg:CreateTexture(nil, "BORDER")
    brd:SetPoint("TOPLEFT", -1, 1); brd:SetPoint("BOTTOMRIGHT", 1, -1)
    brd:SetColorTexture(unpack(Theme.border))
  end
  local modelIDInput = CreateFrame("EditBox", nil, modelIDInputBg)
  modelIDInput:SetSize(modelInputW - 12, 18)
  modelIDInput:SetPoint("LEFT", modelIDInputBg, "LEFT", 6, 0)
  modelIDInput:SetFont(ns.Media.fontGui, 10, "")
  modelIDInput:SetTextColor(unpack(Theme.textNormal))
  modelIDInput:SetAutoFocus(false)
  modelIDInput:SetMaxLetters(15)
  modelIDInput:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  modelIDInput:SetScript("OnEnterPressed", function(s)
    local val = tonumber(s:GetText())
    if val then
      SetAnimField("modelID", val)
      RefreshAnimList()
      RefreshAnimEditor()
    end
    s:ClearFocus()
  end)
  seAnimEditor._modelIDInput = modelIDInput

  -- Model Picker button
  local modelPickerBtn = SW.CreateActionBtn(edContent, L["SETTINGS_BROWSE_BTN"], pickerBtnW,
    { 0.10, 0.10, 0.16, 0.9 }, nil, Theme.accent)
  modelPickerBtn:SetPoint("LEFT", modelIDInputBg, "RIGHT", 4, 0)

  -- Preview button (loop toggle)
  local previewBtn = SW.CreateActionBtn(edContent, L["SETTINGS_PREVIEW_BTN"], previewBtnW,
    { 0.08, 0.08, 0.16, 0.9 }, nil, Theme.accent)
  previewBtn:SetPoint("LEFT", modelPickerBtn, "RIGHT", 4, 0)
  previewBtn:SetScript("OnLeave", function(s)
    local SE = ns.Modules.SpellEffects
    if SE and SE.IsPreviewLooping and SE.IsPreviewLooping() then
      s._lbl:SetTextColor(0.3, 1, 0.3)
    else
      s._lbl:SetTextColor(unpack(Theme.accentText))
    end
  end)
  seAnimEditor._previewBtn = previewBtn

  -- Model name display
  local modelNameLabel = edContent:CreateFontString(nil, "OVERLAY")
  modelNameLabel:SetFont(ns.Media.fontGui, 9)
  modelNameLabel:SetPoint("TOPLEFT", edContent, "TOPLEFT", 4, -42)
  modelNameLabel:SetPoint("RIGHT", edContent, "RIGHT", -4, 0)
  modelNameLabel:SetJustifyH("LEFT")
  modelNameLabel:SetTextColor(unpack(Theme.textDim))
  modelNameLabel:SetText("")
  seAnimEditor._modelNameLabel = modelNameLabel

  -- Compact sliders : 3 par ligne, avec valeur Editable
  -- (le selecteur de couche BG/MG/FG a ete deplace sur chaque ligne de la
  -- liste de combo -- cf. BuildAnimRow -- donc plus besoin ici)
  local COLS         = 3
  local COL_GAP      = 6
  local ROW_H        = 65   -- hauteur d'un mini-slider (SW.CreateSlider ~58px)
  local miniSliderW  = math.floor((edW - (COLS - 1) * COL_GAP) / COLS)
  local gridTopY     = -58

  local sliderDefs = {
    -- Ligne 1 : X, Y, Z
    { key = "x",         label = L["SETTINGS_OFFSET_X"], min = -30, max = 30,  step = 0.01, fmt = "%.2f" },
    { key = "y",         label = L["SETTINGS_OFFSET_Y"], min = -30, max = 30,  step = 0.01, fmt = "%.2f" },
    { key = "z",         label = L["SETTINGS_AXIS_Z_DEPTH"],  min = -30, max = 30,  step = 0.01, fmt = "%.2f" },
    -- Ligne 2 : Échelle, Rotation, Opacité
    { key = "scale",     label = L["SETTINGS_SCALE"],    min = 0.1, max = 5,   step = 0.01, fmt = "%.2f" },
    { key = "rotation",  label = L["SETTINGS_ROTATION"],   min = 0,   max = 360, step = 0.1,  fmt = "%.1f" },
    { key = "alpha",     label = L["SETTINGS_OPACITY"],    min = 0,   max = 1,   step = 0.01, fmt = "%.2f" },
    -- Ligne 3 : Position X, Position Y, Délai
    { key = "anchorX",   label = L["SETTINGS_POSITION_X"],     min = -800, max = 800, step = 1,   fmt = "%.0f" },
    { key = "anchorY",   label = L["SETTINGS_POSITION_Y"],     min = -800, max = 800, step = 1,   fmt = "%.0f" },
    { key = "delay",     label = L["SETTINGS_DELAY"],      min = 0,   max = 3,   step = 0.01, fmt = "%.2f" },
    -- Ligne 4 : Durée
    { key = "duration",  label = L["SETTINGS_DURATION"],      min = 0.1, max = 30,  step = 0.01, fmt = "%.2f" },
  }

  seAnimEditor._sliders = {}

  for i, def in ipairs(sliderDefs) do
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local xOff = col * (miniSliderW + COL_GAP)
    local yOff = gridTopY - row * ROW_H

    -- Slider compact (SharedWidgets)
    local ms = SW.CreateSlider(edContent, def.label, def.min, def.max, def.step, miniSliderW)
    ms:ClearAllPoints()
    ms:SetPoint("TOPLEFT", edContent, "TOPLEFT", xOff, yOff)
    ms:SetValue(0)
    ms.onChanged = function(val) SetAnimField(def.key, val) end

    seAnimEditor._sliders[def.key] = ms
  end

  -- D-pad flèches pour nudge Pos. X / Pos. Y (à droite du slider Durée, ligne 4)
  do
    local ARROW_SZ = 18
    local PAD = 1
    -- Ancrer à droite du slider Durée (col 0, row 3)
    local durationSlider = seAnimEditor._sliders["duration"]
    -- Conteneur du D-pad : ? ?? ?
    local dpad = CreateFrame("Frame", nil, edContent)
    dpad:SetSize(ARROW_SZ * 3 + PAD * 2, ARROW_SZ * 2 + PAD)
    dpad:SetPoint("LEFT", durationSlider, "RIGHT", 10, -4)
    seAnimEditor._dpad = dpad

    local function MakeArrow(parent, symbol, xOff, yOff, onClick)
      local btn = CreateFrame("Button", nil, parent)
      btn:SetSize(ARROW_SZ, ARROW_SZ)
      btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, -yOff)
      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(); bg:SetColorTexture(0.15, 0.15, 0.20, 0.9)
      btn._bg = bg
      local lbl = btn:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 11); lbl:SetPoint("CENTER")
      lbl:SetText(symbol); lbl:SetTextColor(0.7, 0.7, 0.7)
      btn:SetScript("OnEnter", function() bg:SetColorTexture(0.25, 0.25, 0.35, 1); lbl:SetTextColor(1,1,1) end)
      btn:SetScript("OnLeave", function() bg:SetColorTexture(0.15, 0.15, 0.20, 0.9); lbl:SetTextColor(0.7, 0.7, 0.7) end)
      btn:SetScript("OnClick", onClick)
      return btn
    end

    local function NudgePos(field, delta)
      local sl = seAnimEditor._sliders[field]
      if not sl then return end
      local cur = sl:GetValue() or 0
      local nv = cur + delta
      sl:SetValue(nv)
      SetAnimField(field, nv)
    end

    -- Layout : [<] [^][v] [>]
    MakeArrow(dpad, "<", 0, (ARROW_SZ + PAD) / 2 - ARROW_SZ / 2, function() NudgePos("anchorX", -1) end)
    MakeArrow(dpad, "^", ARROW_SZ + PAD, 0, function() NudgePos("anchorY", 1) end)
    MakeArrow(dpad, "v", ARROW_SZ + PAD, ARROW_SZ + PAD, function() NudgePos("anchorY", -1) end)
    MakeArrow(dpad, ">", (ARROW_SZ + PAD) * 2, (ARROW_SZ + PAD) / 2 - ARROW_SZ / 2, function() NudgePos("anchorX", 1) end)
  end

  local numRows = math.ceil(#sliderDefs / COLS)
  local gridBottomY = gridTopY - numRows * ROW_H
  edContent:SetHeight(math.abs(gridBottomY) + 12)

  -- L'éditeur n'est plus contraint en hauteur : il s'ajuste à son contenu réel,
  -- et le panneau droit (et le conteneur horizontal) s'étend pour lui laisser
  -- toute la place nécessaire (il y a de la marge sur le côté droit de la fenêtre).
  editorFrame:SetHeight(edContent:GetHeight() + 18)
  do
    local neededH = editorTop + editorFrame:GetHeight()
    local panelH = math.max(PANEL_H, neededH)
    if panelH > PANEL_H then
      hPanel:SetHeight(panelH)
      rightPanel:SetHeight(panelH)
      -- hPanel a déjà été ajouté au layout avec l'ancienne hauteur (PANEL_H) :
      -- corriger l'accumulateur pour que ctx:Finalize() dimensionne le conteneur correctement.
      ctx.y = ctx.y + (panelH - PANEL_H)
    end
  end

  -- Refresh functions
  RefreshSpellList = function()
    for _, row in ipairs(seSpellList._rows) do row:Hide() end
    wipe(seSpellList._rows)

    local combos = GetCombosDB()
    local sorted = {}
    for sid in pairs(combos) do
      if type(sid) == "number" then sorted[#sorted + 1] = sid end
    end

    -- Filtrer : n'afficher que les sorts de la classe/spEc actuelle
    -- + les sorts ajoutés manuellement via le champ SpellID
    local manualSpells = GetManualSpellsDB()

    -- Auto-migrer les entrées legacy (manualSpells = true) vers un tag de classe
    -- quand IsPlayerSpell le reconnaît sur le perso actuel.
    local _, playerCls = UnitClass("player")
    if playerCls then
      for sid, entry in pairs(manualSpells) do
        if entry == true and IsPlayerSpell and IsPlayerSpell(sid) then
          manualSpells[sid] = playerCls
        end
      end
    end

    -- Sorts manuels connus : forcer le tag de classe correct
    -- 48778 = Destrier de la Mort d'Achérus (DK uniquement)
    manualSpells[48778] = manualSpells[48778] or (combos[48778] and "DEATHKNIGHT") or nil

    local function IsCurrentClassSpell(sid)
      local ps = PSEUDO_SPELLS_3D[sid]
      if ps then
        -- Pseudo-sort : afficher seulement pour la spEc correspondante
        local idx = GetSpecialization and GetSpecialization()
        if not idx then return false end
        local ok, specID = pcall(GetSpecializationInfo, idx)
        return ok and specID == ps.specID
      end
      -- Sort avec tag de classe forcé : vérifier en priorité (avant IsPlayerSpell)
      local entry = manualSpells[sid]
      if entry and entry ~= true then
        local _, cls = UnitClass("player")
        return entry == cls
      end
      if IsPlayerSpell and IsPlayerSpell(sid) then return true end
      -- Sort ajouté manuellement : vérifier la classe
      if entry == true then
        -- Legacy sans tag de classe : toujours visible (utilisateur peut restreindre via "Assigner à ma classe")
        return true
      end
      return false
    end
    local filtered = {}
    for _, sid in ipairs(sorted) do
      if IsCurrentClassSpell(sid) then filtered[#filtered + 1] = sid end
    end
    -- Trier par ordre alphabétique du nom -- ns.FoldAccentsLower (Core.lua)
    -- classe les noms accentués (Â/É...) avec leur lettre, pas après tout
    -- l'alphabet. strcmputf8i seul ne suffisait pas pour ce client.
    table.sort(filtered, function(a, b)
      local nameA = GetSpellInfo3D(a) or ""
      local nameB = GetSpellInfo3D(b) or ""
      return ns.FoldAccentsLower(nameA) < ns.FoldAccentsLower(nameB)
    end)
    sorted = filtered

    local rowW = LEFT_W - 38
    local yy = 0
    for _, sid in ipairs(sorted) do
      local row = BuildSpellListRow(seSpellList, sid, rowW, function(clickedID)
        seActiveSection = "spells"
        do local MB = ns.Auras and ns.Auras.MissingBuffs; if MB and MB.SetPreview then MB.SetPreview(false) end end
        seSelectedSpellID = clickedID
        seSelectedTriggerKey = nil
        seSelectedAuraID = nil
        seSelectedAnimIdx = nil
        RefreshSpellList()
        if RefreshOrbList then RefreshOrbList() end
        if RefreshOocList then RefreshOocList() end
        if RefreshAuraList then RefreshAuraList() end
    if RefreshMissingBuffsList then RefreshMissingBuffsList() end
        RefreshAnimList()
        RefreshAnimEditor()
      end)
      row:SetPoint("TOPLEFT", seSpellList, "TOPLEFT", 0, -yy)
      row:SetSelected(seActiveSection == "spells" and sid == seSelectedSpellID)
      seSpellList._rows[#seSpellList._rows + 1] = row
      yy = yy + 28
    end
    seSpellList:SetHeight(math.max(10, yy))
    if RefreshAliasRow then RefreshAliasRow() end
  end

  RefreshAliasRow = function()
    -- Cacher et déplacer hors écran tous les chips du pool (réutilisables)
    for _, chip in ipairs(_aliasChips) do
      chip:Hide()
      chip:ClearAllPoints()
      chip:SetPoint("LEFT", aliasChipsFrame, "LEFT", -9999, 0)
    end
    if seActiveSection ~= "spells" or not seSelectedSpellID then
      aliasRow:Hide()
      return
    end
    aliasRow:Show()
    local aliases = GetCombosAliasesDB()
    local chipIdx = 0
    local x = 0
    for aliasID, configID in pairs(aliases) do
      if configID == seSelectedSpellID then
        chipIdx = chipIdx + 1
        -- Réutiliser un chip existant ou en créer un nouveau
        local chip = _aliasChips[chipIdx]
        if not chip then
          chip = CreateFrame("Button", nil, aliasChipsFrame)
          chip:SetSize(90, 18)
          local bg = chip:CreateTexture(nil, "BACKGROUND")
          bg:SetAllPoints()
          bg:SetColorTexture(0.2, 0.2, 0.35, 0.9)
          chip._bg = bg
          local lbl = chip:CreateFontString(nil, "OVERLAY")
          lbl:SetFont(ns.Media.fontGui, 9)
          lbl:SetPoint("LEFT",  chip, "LEFT",  3, 0)
          lbl:SetPoint("RIGHT", chip, "RIGHT", -14, 0)
          lbl:SetTextColor(1, 1, 1)
          chip._lbl = lbl
          local xLbl = chip:CreateFontString(nil, "OVERLAY")
          xLbl:SetFont(ns.Media.fontGui, 9)
          xLbl:SetPoint("RIGHT", chip, "RIGHT", -2, 0)
          xLbl:SetText("\195\151")  -- × UTF-8
          xLbl:SetTextColor(1, 0.4, 0.4)
          chip:SetScript("OnEnter", function(s) s._bg:SetColorTexture(0.35, 0.2, 0.2, 0.9) end)
          chip:SetScript("OnLeave", function(s) s._bg:SetColorTexture(0.2, 0.2, 0.35, 0.9) end)
          _aliasChips[chipIdx] = chip
        end
        -- Mettre à jour le contenu
        local sn = GetSpellInfo3D(aliasID)
        chip._lbl:SetText(tostring(aliasID) .. (sn and (" (" .. strsub(sn, 1, 8) .. ")") or ""))
        chip._bg:SetColorTexture(0.2, 0.2, 0.35, 0.9)
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", aliasChipsFrame, "LEFT", x, 0)
        chip:SetPoint("TOP",  aliasChipsFrame, "TOP",  0, -2)
        x = x + 92
        local capturedID = aliasID
        chip:SetScript("OnClick", function()
          aliases[capturedID] = nil
          RefreshAliasRow()
          PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end)
        chip:Show()
      end
    end
  end

  RefreshAnimList = function()
    for _, row in ipairs(seAnimList._rows) do row:Hide() end
    wipe(seAnimList._rows)

    -- Masquer colonnes S/I pour les sections orbs et ooc
    local hideHC = (seActiveSection ~= "spells")
    _hdrHit:SetShown(not hideHC)
    _hdrCast:SetShown(not hideHC)
    -- Masquer colonne MG (moyen plan) pour les globes (seulement arriere/premier plan)
    _hdrLayerMg:SetShown(seActiveSection ~= "orbs")
    if hideHC then
      _hdrModel:ClearAllPoints()
      _hdrModel:SetPoint("LEFT", colHeaderFrame, "LEFT", 6, 0)
    else
      _hdrModel:ClearAllPoints()
      _hdrModel:SetPoint("LEFT", colHeaderFrame, "LEFT", 70, 0)
    end

    local db, key = GetActiveComboTable()
    if not db or not key then
      seAnimList._rightTitle:SetText(L["SETTINGS_COMBO_NO_SELECTION"])
      return
    end

    -- Titre adapté selon la section active
    local titleText = ""
    if seActiveSection == "spells" then
      local name = GetSpellInfo3D(key)
      titleText = string.format(L["SETTINGS_COMBO_TITLE"], name or "?")
    elseif seActiveSection == "orbs" then
      local triggers = GetClassOrbTriggers()
      for _, t in ipairs(triggers) do
        if OrbKeyForClass(t.key) == key then titleText = string.format(L["SETTINGS_COMBO_TITLE"], t.label); break end
      end
    elseif seActiveSection == "ooc" then
      local triggers = GetOocTriggers()
      for _, t in ipairs(triggers) do
        if t.key == key then titleText = string.format(L["SETTINGS_COMBO_TITLE"], t.label); break end
      end
    elseif seActiveSection == "auras" or seActiveSection == "missingBuffs" then
      local name = GetSpellInfo3D(key)
      titleText = string.format(L["SETTINGS_COMBO_TITLE"], name or "?")
    end
    seAnimList._rightTitle:SetText(titleText)

    local combo = db[key]
    if not combo then combo = {} end

    -- Auto-selectionne le 1er combo de la liste si rien n'est deja
    -- selectionne (typiquement juste apres avoir clique un nouveau sort/aura
    -- a gauche, qui remet seSelectedAnimIdx a nil) -- evite d'atterrir sur un
    -- editeur vide alors qu'un combo existe deja pour ce sort.
    if not seSelectedAnimIdx and combo[1] then
      seSelectedAnimIdx = 1
    end

    local rowW = RIGHT_W - 18
    local hideMidLayer = (seActiveSection == "orbs")
    local yy = 0
    for idx, anim in ipairs(combo) do
      local row = BuildAnimRow(seAnimList, idx, anim, rowW, function(clickedIdx)
        seSelectedAnimIdx = clickedIdx
        RefreshAnimList()
        RefreshAnimEditor()
      end, function()
        -- Callback when trigger checkbox changed: refresh row checkboxes
        RefreshAnimList()
      end, hideHC, hideMidLayer)
      row:SetPoint("TOPLEFT", seAnimList, "TOPLEFT", 0, -yy)
      row:SetSelected(idx == seSelectedAnimIdx)
      seAnimList._rows[#seAnimList._rows + 1] = row
      yy = yy + 24
    end
    seAnimList:SetHeight(math.max(10, yy))
  end

  RefreshAnimEditor = function()
    local hasAnim = false
    local anim = nil
    if seSelectedAnimIdx then
      local db, key = GetActiveComboTable()
      if db and key then
        local combo = db[key]
        if combo and combo[seSelectedAnimIdx] then
          anim = combo[seSelectedAnimIdx]
          hasAnim = true
        end
      end
    end

    -- Stop any running preview loop when switching
    local SE = ns.Modules.SpellEffects
    if SE and SE.StopPreview then SE.StopPreview() end
    previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
    previewBtn._lbl:SetTextColor(unpack(Theme.accentText))

    if hasAnim then
      seAnimEditor._title:SetText(string.format(L["SETTINGS_ANIMATION_NUM"], seSelectedAnimIdx))
      seAnimEditor._modelIDInput:SetText(tostring(anim.modelID or 0))
      -- Model name
      local mName = GetModelNameByFileID(anim.modelID or 0)
      seAnimEditor._modelNameLabel:SetText(mName and ("|cff82c8e6" .. mName .. "|r") or "")
      for key, sl in pairs(seAnimEditor._sliders) do
        local val = anim[key]
        if val ~= nil then sl:SetValue(val) end
      end
      if seAnimEditor._refreshStrata then seAnimEditor._refreshStrata() end
    else
      seAnimEditor._title:SetText(L["SETTINGS_ANIM_EDITOR_NO_SELECTION"])
      seAnimEditor._modelIDInput:SetText("")
      seAnimEditor._modelNameLabel:SetText("")
      for _, sl in pairs(seAnimEditor._sliders) do
        sl:SetValue(0)
      end
      if seAnimEditor._refreshStrata then seAnimEditor._refreshStrata() end
    end

    -- Masquer délai/durée pour les sections orbes et OOC (boucle sans fin)
    local showTimingSliders = (seActiveSection == "spells")
    if seAnimEditor._sliders["delay"] then
      seAnimEditor._sliders["delay"]:SetShown(showTimingSliders)
    end
    if seAnimEditor._sliders["duration"] then
      seAnimEditor._sliders["duration"]:SetShown(showTimingSliders)
    end
  end

  -- Refresh listes Orbes & OOC

  RefreshOrbList = function()
    for _, row in ipairs(seOrbList._rows) do row:Hide() end
    wipe(seOrbList._rows)

    local triggers = GetClassOrbTriggers()
    local orbDB = GetOrbCombosDB()
    local rowW = LEFT_W - 38
    local yy = 0
    for _, tDef in ipairs(triggers) do
      -- Toujours afficher tous les triggers (y compris stealth) dans le panneau settings
      local row = BuildTriggerRow(seOrbList, tDef, rowW, "orbs", function(clickedKey)
        seActiveSection = "orbs"
        do local MB = ns.Auras and ns.Auras.MissingBuffs; if MB and MB.SetPreview then MB.SetPreview(false) end end
        seSelectedTriggerKey = clickedKey
        seSelectedSpellID = nil
        seSelectedAuraID = nil
        seSelectedAnimIdx = nil
        -- Crée l'entrée combo si inexistante (clé qualifiée)
        local db = GetOrbCombosDB()
        local qKey = OrbKeyForClass(clickedKey)
        if not db[qKey] then db[qKey] = {} end
        RefreshSpellList()
        RefreshOrbList()
        RefreshOocList()
        if RefreshAuraList then RefreshAuraList() end
    if RefreshMissingBuffsList then RefreshMissingBuffsList() end
        RefreshAnimList()
        RefreshAnimEditor()
      end)
      row:SetPoint("TOPLEFT", seOrbList, "TOPLEFT", 0, -yy)
      row:SetSelected(seActiveSection == "orbs" and seSelectedTriggerKey == tDef.key)
      seOrbList._rows[#seOrbList._rows + 1] = row
      yy = yy + 28
    end
    seOrbList:SetHeight(math.max(10, yy))
    -- Ajuster la hauteur du body et relancer le layout
    secOrbs.body:SetHeight(math.max(60, yy + 4))
    if RelayoutSections then RelayoutSections() end
  end

  RefreshOocList = function()
    for _, row in ipairs(seOocList._rows) do row:Hide() end
    wipe(seOocList._rows)

    local triggers = GetOocTriggers()
    local rowW = LEFT_W - 38
    local yy = 0
    for _, tDef in ipairs(triggers) do
      local row = BuildTriggerRow(seOocList, tDef, rowW, "ooc", function(clickedKey)
        seActiveSection = "ooc"
        do local MB = ns.Auras and ns.Auras.MissingBuffs; if MB and MB.SetPreview then MB.SetPreview(false) end end
        seSelectedTriggerKey = clickedKey
        seSelectedSpellID = nil
        seSelectedAuraID = nil
        seSelectedAnimIdx = nil
        -- Crée l'entrée combo si inexistante
        local db = GetOocCombosDB()
        if not db[clickedKey] then db[clickedKey] = {} end
        RefreshSpellList()
        RefreshOrbList()
        RefreshOocList()
        if RefreshAuraList then RefreshAuraList() end
    if RefreshMissingBuffsList then RefreshMissingBuffsList() end
        RefreshAnimList()
        RefreshAnimEditor()
      end)
      row:SetPoint("TOPLEFT", seOocList, "TOPLEFT", 0, -yy)
      row:SetSelected(seActiveSection == "ooc" and seSelectedTriggerKey == tDef.key)
      seOocList._rows[#seOocList._rows + 1] = row
      yy = yy + 28
    end
    seOocList:SetHeight(math.max(10, yy))
  end

  RefreshAuraList = function()
    for _, row in ipairs(seAuraList._rows) do row:Hide() end
    wipe(seAuraList._rows)

    local spells = ns.Auras and ns.Auras.GetSpecSpells and ns.Auras.GetSpecSpells()
    local buffs, debuffs, totems = {}, {}, {}
    if spells then
      for sid, info in pairs(spells) do
        if info.source ~= "equipment" then
          if info.source == "totem" then
            totems[#totems + 1] = { id = sid, info = info }
          elseif info.source == "debuff" then
            debuffs[#debuffs + 1] = { id = sid, info = info }
          else  -- "buff", "enhancement", ou inconnu → buff joueur
            buffs[#buffs + 1] = { id = sid, info = info }
          end
        end
      end
    end
    local function sortGroup(t)
      -- ns.FoldAccentsLower (Core.lua), cf. commentaire plus haut sur `filtered`.
      table.sort(t, function(a, b)
        return ns.FoldAccentsLower(GetSpellInfo3D(a.id) or "") < ns.FoldAccentsLower(GetSpellInfo3D(b.id) or "")
      end)
    end
    sortGroup(buffs)
    sortGroup(debuffs)
    sortGroup(totems)

    local auraCombos = GetAuraCombosDB()
    local rowW = LEFT_W - 38
    local yy = 0

    -- Crée un séparateur de section avec filet coloré + label
    local function MakeSectionLabel(label, r, g, b)
      local f = CreateFrame("Frame", nil, seAuraList)
      f:SetSize(rowW, 16)
      f:SetPoint("TOPLEFT", seAuraList, "TOPLEFT", 0, -yy)
      local line = f:CreateTexture(nil, "ARTWORK")
      line:SetHeight(1)
      line:SetPoint("LEFT", f, "LEFT", 0, -4); line:SetPoint("RIGHT", f, "RIGHT", 0, -4)
      line:SetColorTexture(r, g, b, 0.35)
      local txt = f:CreateFontString(nil, "OVERLAY")
      txt:SetFont(ns.Media.fontGui, 8)
      txt:SetPoint("LEFT", f, "LEFT", 2, 0)
      txt:SetTextColor(r, g, b, 0.85)
      txt:SetText(label)
      seAuraList._rows[#seAuraList._rows + 1] = f
      yy = yy + 18
    end

    local function AddGroup(group)
      for _, entry in ipairs(group) do
        local sid = entry.id
        local row = BuildSpellListRow(seAuraList, sid, rowW, function(clickedID)
          seActiveSection = "auras"
          do local MB = ns.Auras and ns.Auras.MissingBuffs; if MB and MB.SetPreview then MB.SetPreview(false) end end
          seSelectedAuraID = clickedID
          seSelectedSpellID = nil
          seSelectedTriggerKey = nil
          seSelectedAnimIdx = nil
          -- BUG CORRIGE : creer une entree auraCombos[clickedID] ICI, au
          -- simple CLIC de selection (juste pour parcourir la liste),
          -- polluait la DB en permanence -- des sorts d'AUTRES classes/spes
          -- jamais reellement configures
          -- (juste survoles un jour) s'accumulaient dans auraCombos avec un
          -- combo vide, iteres pour rien par ScanAuraCombos toutes les 2s.
          -- Inutile de toute facon : le flux "ajouter une animation"
          -- (picker de modele plus bas, GetActiveComboTable) fait deja
          -- lui-meme `if not db[key] then db[key] = {} end` au moment ou une
          -- animation est REELLEMENT ajoutee -- lazy, jamais sur un simple clic.
          RefreshSpellList()
          RefreshOrbList()
          RefreshOocList()
          RefreshAuraList()
                if RefreshMissingBuffsList then RefreshMissingBuffsList() end
          RefreshAnimList()
          RefreshAnimEditor()
        end, auraCombos)
        row:SetPoint("TOPLEFT", seAuraList, "TOPLEFT", 0, -yy)
        row:SetSelected(seActiveSection == "auras" and sid == seSelectedAuraID)
        seAuraList._rows[#seAuraList._rows + 1] = row
        yy = yy + 28
      end
    end

    if #buffs > 0 then
      MakeSectionLabel(L["SETTINGS_PLAYER_BUFFS"], 0.40, 0.85, 0.40)
      AddGroup(buffs)
    end
    if #debuffs > 0 then
      if #buffs > 0 then yy = yy + 4 end
      MakeSectionLabel(L["SETTINGS_TARGET_DEBUFFS"], 0.90, 0.38, 0.38)
      AddGroup(debuffs)
    end
    if #totems > 0 then
      if #buffs > 0 or #debuffs > 0 then yy = yy + 4 end
      MakeSectionLabel(L["SETTINGS_TOTEMS"], 0.85, 0.65, 0.25)
      AddGroup(totems)
    end

    seAuraList:SetHeight(math.max(10, yy))
    if RelayoutSections then RelayoutSections() end
  end

  -- Section "Buffs manquants" : contrairement à RefreshAuraList ci-dessus
  -- (source = ns.Auras.GetSpecSpells, tous les sorts trackés), la liste
  -- ici est restreinte à ns.Auras.MissingBuffs.GetTriggerSpells() -- uniquement les
  -- spellIDs que le module "Buffs manquants" peut réellement afficher pour la classe
  -- du joueur. Pas de découpage buffs/debuffs (tout est un "buff" ici), une seule
  -- liste triée alphabétiquement.
  RefreshMissingBuffsList = function()
    for _, row in ipairs(seMissingBuffsList._rows) do row:Hide() end
    wipe(seMissingBuffsList._rows)

    local MB = ns.Auras and ns.Auras.MissingBuffs
    local spellIDs = (MB and MB.GetTriggerSpells and MB.GetTriggerSpells()) or {}
    table.sort(spellIDs, function(a, b)
      return ns.FoldAccentsLower(GetSpellInfo3D(a) or "") < ns.FoldAccentsLower(GetSpellInfo3D(b) or "")
    end)

    local missingBuffsCombos = GetMissingBuffsCombosDB()
    local rowW = LEFT_W - 38
    local yy = 0

    for _, sid in ipairs(spellIDs) do
      local row = BuildSpellListRow(seMissingBuffsList, sid, rowW, function(clickedID)
        seActiveSection = "missingBuffs"
        seSelectedAuraID = clickedID
        seSelectedSpellID = nil
        seSelectedTriggerKey = nil
        seSelectedAnimIdx = nil
        -- Force l'apercu (icone+texte "Manquant") sur CE sort precis --
        -- sans ca, l'icone d'alerte reelle ne s'affiche QUE si le buff est
        -- vraiment absent, rendant le reglage des animations impossible ;
        -- et ScanMissingBuffCombos ne demarre le combo QUE si l'icone
        -- affichee correspond exactement au sort qu'on est en train de configurer.
        local MB = ns.Auras and ns.Auras.MissingBuffs
        if MB and MB.SetPreview then MB.SetPreview(true, clickedID) end
        -- Coupe toute anim/preview en cours pour le buff PRECEDENT avant de
        -- basculer -- sinon son animation restait affichee/en boucle par
        -- dessus la nouvelle icone (le picker ne relance jamais tout seul
        -- un preview au changement de ligne, seuls les boutons Preview/
        -- Preview Combo le font).
        local SE = ns.Modules.SpellEffects
        if SE then
          if SE.StopPreview then SE.StopPreview() end
          if SE.StopComboPreview then SE.StopComboPreview() end
          if SE.StopDecoPreview then SE.StopDecoPreview() end
        end
        if previewBtn then
          previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
          previewBtn._lbl:SetTextColor(unpack(Theme.accentText))
        end
        if previewComboBtn then
          previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
          previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
        end
        RefreshSpellList()
        RefreshOrbList()
        RefreshOocList()
        if RefreshAuraList then RefreshAuraList() end
            RefreshMissingBuffsList()
        RefreshAnimList()
        RefreshAnimEditor()
      end, missingBuffsCombos)
      row:SetPoint("TOPLEFT", seMissingBuffsList, "TOPLEFT", 0, -yy)
      row:SetSelected(seActiveSection == "missingBuffs" and sid == seSelectedAuraID)
      seMissingBuffsList._rows[#seMissingBuffsList._rows + 1] = row
      yy = yy + 28
    end

    seMissingBuffsList:SetHeight(math.max(10, yy))
    if RelayoutSections then RelayoutSections() end
  end

  -- Rafraîchir la liste des orbes quand l'état de furtivité change
  do
    local stealthFrame = CreateFrame("Frame")
    stealthFrame:RegisterEvent("UPDATE_STEALTH")
    stealthFrame:SetScript("OnEvent", function()
      if MainFrame:IsShown() and RefreshOrbList then RefreshOrbList() end
    end)
  end

  -- Button handlers

  -- Ajouter : ouvre le SpellPicker ou utilise l'input SpellID
  addBtn:SetScript("OnClick", function()
    -- Si un SpellID est tapE, l'utiliser directement
    local txt = spellInput:GetText()
    local sid = tonumber(txt)
    if sid and sid > 0 then
      AddSpellByID(sid)
      spellInput:SetText("")
      return
    end
    -- Sinon, ouvrir le picker
    if not SESpellPickerFrame then
      local pf = CreateFrame("Frame", "AishCoreSESpellPicker", UIParent, "BackdropTemplate")
      pf:SetSize(264, 318)
      pf:SetFrameStrata("TOOLTIP")
      pf:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
      pf:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
      pf:SetBackdropBorderColor(unpack(Theme.accent))
      pf:Hide(); pf:EnableMouse(true)

      local ptitle = pf:CreateFontString(nil, "OVERLAY")
      ptitle:SetFont(ns.Media.fontTitle, 11, "OUTLINE")
      ptitle:SetPoint("TOP", pf, "TOP", 0, -8)
      ptitle:SetTextColor(unpack(Theme.accentText))
      ptitle:SetText(L["SETTINGS_SPELL_PICKER_TITLE"])

      local pclose = CreateFrame("Button", nil, pf)
      pclose:SetSize(18, 18)
      pclose:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -5, -5)
      pclose:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
      pclose:GetNormalTexture():SetVertexColor(0.7, 0.7, 0.7)
      pclose:SetScript("OnClick", function() pf:Hide() end)

      local psearch = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
      SW.StyleEditBox(psearch)
      psearch:SetSize(238, 20)
      psearch:SetPoint("TOPLEFT", pf, "TOPLEFT", 8, -26)
      psearch:SetAutoFocus(false)
      psearch:SetScript("OnEscapePressed", function() pf:Hide() end)
      pf._searchBox = psearch

      local psf = CreateFrame("ScrollFrame", nil, pf, "UIPanelScrollFrameTemplate")
      psf:SetPoint("TOPLEFT", psearch, "BOTTOMLEFT", 0, -4)
      psf:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -28, 8)
      local psc = CreateFrame("Frame", nil, psf)
      psc:SetWidth(220); psc:SetHeight(1)
      psf:SetScrollChild(psc)
      pf._sc = psc; pf._sf = psf

      local PM = 120
      local prows = {}
      for ri = 1, PM do
        local pr = CreateFrame("Button", nil, psc)
        pr:SetSize(220, 22)
        pr:SetPoint("TOPLEFT", psc, "TOPLEFT", 0, -(ri - 1) * 22)
        local rbg = pr:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints(); rbg:SetColorTexture(0, 0, 0, 0); pr._bg = rbg
        local ico = pr:CreateTexture(nil, "ARTWORK")
        ico:SetSize(18, 18); ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ico:SetPoint("LEFT", pr, "LEFT", 2, 0); pr._ico = ico
        local nm = pr:CreateFontString(nil, "OVERLAY")
        nm:SetFont(ns.Media.fontGui, 10); nm:SetJustifyH("LEFT")
        nm:SetPoint("LEFT", ico, "RIGHT", 4, 0)
        nm:SetPoint("RIGHT", pr, "RIGHT", -2, 0)
        nm:SetTextColor(unpack(Theme.textNormal)); pr._nm = nm
        pr:SetScript("OnEnter", function(s)
          s._bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.22)
          s._nm:SetTextColor(unpack(Theme.textHighlight))
        end)
        pr:SetScript("OnLeave", function(s)
          s._bg:SetColorTexture(0, 0, 0, 0)
          s._nm:SetTextColor(unpack(Theme.textNormal))
        end)
        pr:SetScript("OnClick", function(s)
          if pf._onAdd then pf._onAdd(s._spellID) end
          pf:Hide()
        end)
        pr:Hide(); prows[ri] = pr
      end
      pf._rows = prows; pf._allSpells = {}

      function pf:FilterSpells(text)
        local t = strlower(text or "")
        local n = 0
        for _, s in ipairs(self._allSpells) do
          if t == "" or strlower(s.name):find(t, 1, true) then
            n = n + 1
            if n <= PM then
              local r = prows[n]
              r._spellID = s.id
              r._ico:SetTexture(s.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
              r._nm:SetText(s.name)
              r:Show()
            end
          end
        end
        for j = n + 1, PM do prows[j]:Hide() end
        psc:SetHeight(math.max(1, n * 22))
        self._sf:SetVerticalScroll(0)
      end

      psearch:SetScript("OnTextChanged", function(self)
        pf:FilterSpells(self:GetText())
      end)

      function pf:Open(anchor, onAdd)
        self._onAdd = onAdd
        self._searchBox:SetText("")
        local PB = ns.Modules.PriorityBar
        self._allSpells = (PB and PB.GetSpecSpells) and PB.GetSpecSpells() or {}
        -- Ajouter les pseudo-sorts de la spEc active (ex: Fire Mage Heating Up / Hot Streak)
        local idx = GetSpecialization and GetSpecialization()
        if idx then
          local ok, specID = pcall(GetSpecializationInfo, idx)
          if ok and specID then
            for sid, ps in pairs(PSEUDO_SPELLS_3D) do
              if ps.specID == specID then
                self._allSpells[#self._allSpells + 1] = { id = sid, name = ps.name, icon = ps.icon }
              end
            end
          end
        end
        self:FilterSpells("")
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        self:Show(); self:Raise()
        self._searchBox:SetFocus()
      end

      pf:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" then self:Hide() end
      end)
      SESpellPickerFrame = pf
    end
    SESpellPickerFrame:Open(addBtn, function(selectedID)
      AddSpellByID(selectedID)
    end)
  end)

  remBtn:SetScript("OnClick", function()
    if seActiveSection ~= "spells" or not seSelectedSpellID then return end
    local combos = GetCombosDB()
    combos[seSelectedSpellID] = nil
    -- Supprimer aussi le flag manuel
    GetManualSpellsDB()[seSelectedSpellID] = nil
    -- Supprimer aussi tous les alias qui pointaient vers ce sort
    local aliases = GetCombosAliasesDB()
    for aliasID, configID in pairs(aliases) do
      if configID == seSelectedSpellID then aliases[aliasID] = nil end
    end
    seSelectedSpellID = nil
    seSelectedAnimIdx = nil
    RefreshSpellList()
    RefreshAnimList()
    RefreshAnimEditor()
    if RefreshAliasRow then RefreshAliasRow() end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  end)

  -- Epingle automatiquement un sort "Auras" au Cooldown Manager natif des
  -- qu'un premier combo lui est configure -- sans ca, la sentinelle de
  -- detection (AddAuraGroup, SpellEffects.lua) ne reconnait JAMAIS ce
  -- spellID comme un candidat valide, meme si le buff est reellement actif
  -- (confirme en jeu : Thé de concentration foudroyante ne declenchait
  -- jamais son animation soutenue tant qu'il n'etait pas AUSSI coche
  -- manuellement dans le CDM Blizzard, alors que l'addon n'utilise jamais
  -- cet affichage natif lui-meme). Reutilise ns.PinAuraToCDM, deja au point
  -- pour "Auras a tracker" (CDMHooks.lua). Le popup de reload N'EST PAS
  -- affiche ici : PromptCDMReloadIfPending est deja appele au OnHide du
  -- panneau (plus bas dans ce fichier) -- pas besoin d'un 2e popup immediat
  -- qui interromprait l'utilisateur en pleine configuration d'un combo.
  --
  -- Section "missingBuffs" : les buffs manquants classiques n'ont RIEN a
  -- epingler (leur combo est pilote par l'etat de l'icone d'alerte, pas par
  -- une lecture d'aura). L'EXCEPTION est Ruee Ardente, cas "presence"
  -- inverse : son combo depend d'une vraie detection d'aura en combat, donc
  -- exactement des memes prerequis qu'un combo de la section "auras".
  local function PinAuraComboToCDMIfNeeded(key)
    local isBurningRush = (seActiveSection == "missingBuffs")
      and ns.Auras and key == ns.Auras.MISSING_WARLOCK_BURNING_RUSH
    if seActiveSection ~= "auras" and not isBurningRush then return end
    local Auras = ns.Auras
    if not (Auras and Auras.PinAuraToCDM) then return end
    local ok, msg = Auras.PinAuraToCDM(key, true)
    if not ok then ok, msg = Auras.PinAuraToCDM(key, false) end
    if not ok then
      print(string.format("|cffff4444[AishCore]|r Impossible d'epingler %s au Cooldown Manager natif (%s) -- "
        .. "l'animation soutenue de ce combo pourrait ne jamais se declencher.", tostring(GetSpellName(key)), tostring(msg)))
    end
  end

  -- +Anim : ouvre le Model Picker pour choisir un modèle
  animAddBtn:SetScript("OnClick", function()
    local picker = EnsureModelPicker()
    picker:Open(function(fileID, modelName)
      local db, key = GetActiveComboTable()
      if not db or not key then return end
      if not db[key] then db[key] = {} end
      local combo = db[key]
      -- #combo==0 (pas "db[key] absent") : table.remove (animRemBtn) ne
      -- supprime jamais la cle elle-meme, elle reste une table vide une fois
      -- le dernier anim retire -- sans ce test sur la longueur, un combo deja
      -- cree par le passe (meme vide depuis longtemps) ne redeclenche jamais
      -- l'auto-epinglage au prochain ajout.
      if #combo == 0 then
        PinAuraComboToCDMIfNeeded(key)
      end
      local newAnim = NewAnimDefaults()
      newAnim.modelID = fileID
      combo[#combo + 1] = newAnim
      seSelectedAnimIdx = #combo
      -- Cache name
      if modelName then seModelNameCache[fileID] = modelName end
      RefreshAnimList()
      RefreshAnimEditor()
      -- Section orbs/OOC : lancer immédiatement un DecoPreview sur l'anim ajoutée
      if seActiveSection ~= "spells" then
        local SE = ns.Modules.SpellEffects
        if SE then
          if SE.StopDecoPreview then SE.StopDecoPreview() end
          if SE.StartDecoPreview then
            SE.StartDecoPreview({ combo[seSelectedAnimIdx] }, GetPreviewAnchor())
          end
        end
        -- Mettre le bouton Preview en état "Stop"
        previewBtn._lbl:SetText(L["SETTINGS_STOP_BTN"])
        previewBtn._lbl:SetTextColor(0.3, 1, 0.3)
        previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
      end
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
  end)

  animRemBtn:SetScript("OnClick", function()
    if not seSelectedAnimIdx then return end
    local db, key = GetActiveComboTable()
    if not db or not key then return end
    local combo = db[key]
    if combo then
      table.remove(combo, seSelectedAnimIdx)
    end
    seSelectedAnimIdx = nil
    RefreshAnimList()
    RefreshAnimEditor()
    -- Rafraîchir les décorations si section orbs/OOC
    if seActiveSection ~= "spells" then
      local SE = ns.Modules.SpellEffects
      if SE then
        if SE.StopDecoPreview then SE.StopDecoPreview() end
        if SE.RefreshDecorations then SE.RefreshDecorations() end
      end
      -- Reset preview buttons
      previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
      previewBtn._lbl:SetTextColor(unpack(Theme.accentText))
      previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
      previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  end)

  -- Applique / efface la couleur de globe pour la preview "Globes externes"
  local function ApplyOrbColorPreview(key)
    if seActiveSection ~= "orbs" then return end
    local RC = ns.Modules and ns.Modules.ResourceCircle
    if not (RC and RC.SetSecDotColorOverride) then return end
    local cfg = ns.DB and ns.DB.spellEffects or {}
    local gc  = cfg.orbGlobeColors and cfg.orbGlobeColors[key]
    if gc then
      RC.SetSecDotColorOverride(gc[1], gc[2], gc[3])
    else
      RC.ClearSecDotColorOverride()
    end
  end
  local function ClearOrbColorPreview()
    if seActiveSection ~= "orbs" then return end
    local RC = ns.Modules and ns.Modules.ResourceCircle
    if RC and RC.ClearSecDotColorOverride then RC.ClearSecDotColorOverride() end
  end

  previewComboBtn:SetScript("OnClick", function()
    local SE = ns.Modules.SpellEffects
    if not SE then return end

    local isDeco = (seActiveSection == "orbs" or seActiveSection == "ooc")

    -- Arrêter la preview en cours
    if isDeco then
      if SE.IsDecoPreviewActive and SE.IsDecoPreviewActive() then
        SE.StopDecoPreview()
        ClearOrbColorPreview()
        SE.RefreshDecorations()
        previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
        return
      end
    else
      if SE.IsComboPreviewLooping and SE.IsComboPreviewLooping() then
        SE.StopComboPreview()
        previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
        return
      end
    end

    -- Stopper l'autre type de preview si actif
    if SE.IsPreviewLooping and SE.IsPreviewLooping() then
      SE.StopPreview()
      previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
      previewBtn._lbl:SetTextColor(unpack(Theme.accentText))
    end
    if SE.IsDecoPreviewActive and SE.IsDecoPreviewActive() then
      SE.StopDecoPreview()
      ClearOrbColorPreview()
    end

    -- Start combo/deco preview
    local db, key = GetActiveComboTable()
    if not db or not key then return end
    local combo = db[key]
    if not combo or #combo == 0 then return end

    if isDeco then
      ApplyOrbColorPreview(key)
      SE.StartDecoPreview(combo, GetPreviewAnchor())
    else
      SE.PreviewComboLoop(combo, GetPreviewAnchor())
    end
    previewComboBtn._lbl:SetText(L["SETTINGS_STOP_COMBO_BTN"])
    previewComboBtn._lbl:SetTextColor(0.3, 1, 0.3)
  end)

  -- Preview button : toggle loop
  previewBtn:SetScript("OnClick", function()
    local SE = ns.Modules.SpellEffects
    if not SE then return end

    local isDeco = (seActiveSection == "orbs" or seActiveSection == "ooc")

    -- Arrêter la preview en cours
    if isDeco then
      if SE.IsDecoPreviewActive and SE.IsDecoPreviewActive() then
        SE.StopDecoPreview()
        ClearOrbColorPreview()
        SE.RefreshDecorations()
        previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
        previewBtn._lbl:SetTextColor(unpack(Theme.accentText))
        return
      end
    else
      if SE.IsPreviewLooping and SE.IsPreviewLooping() then
        SE.StopPreview()
        previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
        previewBtn._lbl:SetTextColor(unpack(Theme.accentText))
        return
      end
    end

    -- Stopper l'autre type de preview si actif
    if SE.IsComboPreviewLooping and SE.IsComboPreviewLooping() then
      SE.StopComboPreview()
      previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
      previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
    end
    if SE.IsDecoPreviewActive and SE.IsDecoPreviewActive() then
      SE.StopDecoPreview()
      ClearOrbColorPreview()
    end

    -- Start single anim preview
    if not seSelectedAnimIdx then return end
    local db, key = GetActiveComboTable()
    if not db or not key then return end
    local combo = db[key]
    if not combo or not combo[seSelectedAnimIdx] then return end

    if isDeco then
      ApplyOrbColorPreview(key)
      SE.StartDecoPreview({ combo[seSelectedAnimIdx] }, GetPreviewAnchor())
    else
      SE.PreviewLoop(combo[seSelectedAnimIdx], GetPreviewAnchor())
    end
    previewBtn._lbl:SetText(L["SETTINGS_STOP_BTN"])
    previewBtn._lbl:SetTextColor(0.3, 1, 0.3)
  end)

  -- Model Picker button
  modelPickerBtn:SetScript("OnClick", function()
    local picker = EnsureModelPicker()
    picker:Open(function(fileID, modelName)
      local db, key = GetActiveComboTable()
      if not db or not key then return end
      if not db[key] then db[key] = {} end
      local combo = db[key]
      -- #combo==0 (pas "db[key] absent") : table.remove (animRemBtn) ne
      -- supprime jamais la cle elle-meme, elle reste une table vide une fois
      -- le dernier anim retire -- sans ce test sur la longueur, un combo deja
      -- cree par le passe (meme vide depuis longtemps) ne redeclenche jamais
      -- l'auto-epinglage au prochain ajout.
      if #combo == 0 then
        PinAuraComboToCDMIfNeeded(key)
      end
      local newAnim = NewAnimDefaults()
      newAnim.modelID = fileID
      combo[#combo + 1] = newAnim
      seSelectedAnimIdx = #combo
      if modelName then seModelNameCache[fileID] = modelName end
      RefreshAnimList()
      RefreshAnimEditor()
      if seActiveSection ~= "spells" then
        local SE = ns.Modules.SpellEffects
        if SE then
          if SE.StopDecoPreview then SE.StopDecoPreview() end
          if SE.StartDecoPreview then
            SE.StartDecoPreview({ combo[seSelectedAnimIdx] }, GetPreviewAnchor())
          end
        end
        previewBtn._lbl:SetText(L["SETTINGS_STOP_BTN"])
        previewBtn._lbl:SetTextColor(0.3, 1, 0.3)
        previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accentText))
      end
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
  end)

  -- ModelID input E apply on enter or focus lost
  modelIDInput:SetScript("OnEditFocusLost", function(s)
    local val = tonumber(s:GetText())
    if val then
      SetAnimField("modelID", val)
      RefreshAnimList()
      RefreshAnimEditor()
    end
  end)

  -- Initial refresh
  -- Migrer l'ancien format "spells" vers "combos" si besoin
  local cfg = ns.GetCfg("spellEffects") or {}
  if cfg.spells and next(cfg.spells) then
    local combos = GetCombosDB()
    for sid, data in pairs(cfg.spells) do
      if not combos[sid] then
        combos[sid] = {{
          modelID  = data.modelID,
          duration = data.duration or 0.8,
          z = 0, x = 0, y = 0, rotation = 0, scale = 1, alpha = 1,
          delay = 0, anchorX = 0, anchorY = 0, strata = "BACKGROUND",
        }}
      end
    end
  end

  RefreshSpellList()
  RefreshOrbList()
  RefreshOocList()
  RefreshAuraList()
  RefreshMissingBuffsList()
  RefreshAnimList()
  RefreshAnimEditor()

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Barre d'XP  (helpers 3 niveaux de profondeur)
local function DB3Get(k1, k2, k3)
  return ns.DB and ns.DB[k1] and ns.DB[k1][k2] and ns.DB[k1][k2][k3]
end
local function DB3Def(k1, k2, k3)
  return ns.Defaults and ns.Defaults[k1] and ns.Defaults[k1][k2] and ns.Defaults[k1][k2][k3]
end
local function DB3Val(k1, k2, k3)
  local v = DB3Get(k1, k2, k3)
  if v ~= nil then return v end
  return DB3Def(k1, k2, k3)
end
local function DB3Set(k1, k2, k3, val)
  if not ns.DB          then ns.DB = {} end
  if not ns.DB[k1]      then ns.DB[k1] = {} end
  if not ns.DB[k1][k2]  then ns.DB[k1][k2] = {} end
  ns.DB[k1][k2][k3] = val
end

local function MakeTextButton(container, label, W)
  local btn = CreateFrame("Button", nil, container)
  btn:SetSize(W, 26)
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.06, 0.04, 0.85)
  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFont(ns.Media.fontGui, 10)
  btn.text:SetPoint("CENTER")
  btn.text:SetText(label)
  btn.text:SetTextColor(unpack(Theme.accentText))
  btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1,1,1) end)
  btn:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(Theme.accentText)) end)
  return btn
end

local xpEditBtn  -- reference globale pour update du label

function Build.XPBar(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_XP_BAR"], W))

  local cb = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_XP_ENABLE"],
    L["SETTINGS_XP_ENABLE_TT"], W))
  BindCheckbox(cb, "xpBar", "enabled")

  local cbRest = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_XP_REST_INDICATOR"],
    L["SETTINGS_XP_REST_INDICATOR_TT"], W))
  BindCheckbox(cbRest, "xpBar", "restIndicator")

  local cbRestPreview = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_XP_REST_PREVIEW"],
    L["SETTINGS_XP_REST_PREVIEW_TT"], W))
  cbRestPreview:SetChecked(false)
  cbRestPreview.onChanged = function(val)
    if ns.Modules.XPBar then ns.Modules.XPBar.SetRestPreview(val) end
  end

  local _xpSL3 = math.floor((W - 16) / 3)
  local slRestX = SW.CreateSlider(container, L["SETTINGS_XP_REST_X"], -300, 600, 1, _xpSL3)
  slRestX:SetValue(DBGet("xpBar", "restX") or 0)
  slRestX.onChanged = function(val)
    DBSet("xpBar", "restX", val)
    if ns.Modules.XPBar then ns.Modules.XPBar.ApplyRestModelCfg() end
  end
  local slRestY = SW.CreateSlider(container, L["SETTINGS_XP_REST_Y"], -100, 400, 1, _xpSL3)
  slRestY:SetValue(DBGet("xpBar", "restY") or 0)
  slRestY.onChanged = function(val)
    DBSet("xpBar", "restY", val)
    if ns.Modules.XPBar then ns.Modules.XPBar.ApplyRestModelCfg() end
  end
  local slRestScale = SW.CreateSlider(container, L["SETTINGS_XP_REST_SCALE"], 0.3, 4.0, 0.05, _xpSL3)
  slRestScale:SetValue(DBGet("xpBar", "restScale") or 1.0)
  slRestScale.onChanged = function(val)
    DBSet("xpBar", "restScale", val)
    if ns.Modules.XPBar then ns.Modules.XPBar.ApplyRestModelCfg() end
  end
  ctx:AddRow(8, slRestX, slRestY, slRestScale)

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_MAX_LEVEL_BEHAVIOR"], W))

  local cbComp = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_XP_COMPANION"],
    L["SETTINGS_XP_COMPANION_TT"], W))
  BindCheckbox(cbComp, "xpBar", "companionXP")

  local cbRep = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_XP_REP_TRACKING"],
    L["SETTINGS_XP_REP_TRACKING_TT"], W))
  BindCheckbox(cbRep, "xpBar", "repEnabled")



  local rg = ctx:Add(SW.CreateRadioGroup(container, {
    {
      value   = "tracked",
      label   = L["SETTINGS_XP_REP_TRACKED"],
      tooltip = L["SETTINGS_XP_REP_TRACKED_TT"],
    },
    {
      value   = "lastGained",
      label   = L["SETTINGS_XP_REP_LAST_GAINED"],
      tooltip = L["SETTINGS_XP_REP_LAST_GAINED_TT"],
    },
  }, W))
  rg:SetValue(DBGet("xpBar", "repDisplayMode") or "tracked")
  rg.onChanged = function(val)
    DBSet("xpBar", "repDisplayMode", val)
    LiveApply("xpBar")
  end

  -- Synchronise la visibilité du radio group avec le toggle de réputation
  local function RefreshRepSection()
    if DBGet("xpBar", "repEnabled") == false then
      rg:Hide()
    else
      rg:Show()
    end
  end
  RefreshRepSection()  -- État initial

  -- Surcharge onChanged pour piloter aussi la visibilité
  local origOnChanged = cbRep.onChanged
  cbRep.onChanged = function(val)
    origOnChanged(val)
    RefreshRepSection()
  end

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_LEVEL_BADGE_FONT"], W))
  local ddXPFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_XP_BADGE_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddXPFont, "xpBar", "fontLevel")

  local ddXPOutline = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 220))
  BindDropdown(ddXPOutline, "xpBar", "levelOutlineStyle")

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Priority Bar
local SpellPickerFrame  -- singleton créé en lazy

function Build.PriorityBar(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_PRIORITY_BAR"], W))

  -- Activer (juste sous le header, avant Disposition)
  local cbPB = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_ENABLE"],
    L["SETTINGS_PB_ENABLE_TT"], W))
  BindCheckbox(cbPB, "priorityBar", "enabled")
  ctx:Spacer(8)

  -- Disposition (5 choix visuels, spec-specific)
  do
    local TEX_BASE = "Interface\\AddOns\\AishCore\\Media\\textures\\"
    local LAYOUT_TEX = {
      ["2x2"]     = "layout_2x2",
      ["3x3"]     = "layout_3x3",
      ["4x4line"] = "layout_4x4inline",
      ["4x4sq"]   = "layout_4x4",
      ["6x6"]     = "layout_6x6",
    }
    local LAYOUT_LABELS = {
      ["2x2"]     = L["SETTINGS_LAYOUT_2X2"],
      ["3x3"]     = L["SETTINGS_LAYOUT_3X3"],
      ["4x4line"] = L["SETTINGS_LAYOUT_4X4_INLINE"],
      ["4x4sq"]   = L["SETTINGS_LAYOUT_4X4_SQUARE"],
      ["6x6"]     = L["SETTINGS_LAYOUT_6X6"],
    }
    -- Les textures layout_*.tga font 230x80px (ratio ~2.875:1) : on dimensionne
    -- l'icone en consequence pour eviter tout etirement.
    local cardW, cardH, gap = 140, 95, 15
    local icoW, icoH = 130, math.floor(130 * 80 / 230 + 0.5)

    ctx:Add(SW.CreateSectionHeader(container, "Disposition", W))
    ctx:Spacer(4)

    local layoutCards = {}
    local function CurrentLayout()
      local PB = ns.Modules.PriorityBar
      return (PB and PB.GetCurrentSpecLayout and PB.GetCurrentSpecLayout()) or "2x2"
    end
    local function RefreshLayoutCards()
      local cur = CurrentLayout()
      for _, lc in ipairs(layoutCards) do
        local isAct = (lc.key == cur)
        local tex = TEX_BASE .. LAYOUT_TEX[lc.key] .. (isAct and "_active" or "_inactive")
        pcall(function() lc.ico:SetTexture(tex) end)
        lc.lbl:SetTextColor(unpack(isAct and Theme.textNormal or Theme.textDisabled))
        lc.actTx:SetShown(isAct)
      end
    end

    local function MakeCard(rowFrame, lk, x)
      local isAct = (CurrentLayout() == lk)
      local card = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
      card:SetSize(cardW, cardH)
      card:SetPoint("TOPLEFT", x, 0)

      local hoverGlow = card:CreateTexture(nil, "BACKGROUND", nil, 0)
      hoverGlow:SetAllPoints()
      hoverGlow:SetColorTexture(Theme.gold[1], Theme.gold[2], Theme.gold[3], 0.08)
      hoverGlow:Hide()

      local cbd = CreateFrame("Frame", nil, card, "BackdropTemplate"); cbd:SetAllPoints()
      cbd:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
      cbd:SetBackdropBorderColor(0, 0, 0, 0)

      local ico = card:CreateTexture(nil, "ARTWORK"); ico:SetSize(icoW, icoH); ico:SetPoint("TOP", 0, -8)
      pcall(function() ico:SetTexture(TEX_BASE .. LAYOUT_TEX[lk] .. (isAct and "_active" or "_inactive")) end)
      ico:SetVertexColor(1, 1, 1, 1)

      local clbl = card:CreateFontString(nil, "OVERLAY"); clbl:SetFont(ns.Media.fontGui, 12); clbl:SetPoint("BOTTOM", 0, 18)
      clbl:SetTextColor(unpack(isAct and Theme.textNormal or Theme.textDisabled))
      clbl:SetText(LAYOUT_LABELS[lk] or lk)

      local actTx = card:CreateFontString(nil, "OVERLAY"); actTx:SetFont(ns.Media.fontGui, 8); actTx:SetPoint("BOTTOM", 0, 4)
      actTx:SetTextColor(unpack(Theme.accentText)); actTx:SetText(L["SETTINGS_ACTIVE_BADGE"])
      actTx:SetShown(isAct)

      layoutCards[#layoutCards + 1] = { key = lk, card = card, ico = ico, lbl = clbl, actTx = actTx }

      card:SetScript("OnClick", function()
        local PB = ns.Modules.PriorityBar
        if PB and PB.SetCurrentSpecLayout then PB.SetCurrentSpecLayout(lk) end
        if container._buildSlotEditor then container._buildSlotEditor() end
        RefreshLayoutCards()
      end)
      card:SetScript("OnEnter", function()
        hoverGlow:Show()
        cbd:SetBackdropBorderColor(Theme.gold[1], Theme.gold[2], Theme.gold[3], 0.8)
        clbl:SetTextColor(1, 1, 1)
        pcall(function() ico:SetTexture(TEX_BASE .. LAYOUT_TEX[lk] .. "_active") end)
      end)
      card:SetScript("OnLeave", function()
        hoverGlow:Hide()
        cbd:SetBackdropBorderColor(0, 0, 0, 0)
        RefreshLayoutCards()
      end)
    end

    -- Ligne 1 : 2x2, 3x3, 4x4 Inline (3 cartes)
    local row1 = CreateFrame("Frame", nil, container)
    row1:SetSize(W, cardH)
    ctx:Add(row1)
    local sx1 = math.max(0, (W - (3 * cardW + 2 * gap)) / 2)
    for i, lk in ipairs({"2x2", "3x3", "4x4line"}) do
      MakeCard(row1, lk, sx1 + (i - 1) * (cardW + gap))
    end

    ctx:Spacer(6)

    -- Ligne 2 : 4x4 Carré, 6x6 (2 cartes)
    local row2 = CreateFrame("Frame", nil, container)
    row2:SetSize(W, cardH)
    ctx:Add(row2)
    local sx2 = math.max(0, (W - (2 * cardW + gap)) / 2)
    for i, lk in ipairs({"4x4sq", "6x6"}) do
      MakeCard(row2, lk, sx2 + (i - 1) * (cardW + gap))
    end

    container._refreshLayoutCards = RefreshLayoutCards

    if ns.CallbackRegistry then
      ns.CallbackRegistry:Register("PriorityBar.SpecChanged", RefreshLayoutCards)
    end

    ctx:Spacer(8)
  end

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "priorityBar", {
    { "always",  L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_PB_VIS_ALWAYS_TT"] },
    { "target",  L["SETTINGS_VIS_TARGET"],    L["SETTINGS_PB_VIS_TARGET_TT"] },
    { "combat",  L["SETTINGS_VIS_COMBAT"],    L["SETTINGS_PB_VIS_COMBAT_TT"] },
  }, "combat")
  MakeAlwaysInInstanceToggle(container, ctx, W, "priorityBar")

  local _pbSL2 = math.floor((W - 8) / 2)
  local _pbSL3 = math.floor((W - 16) / 3)
  local slPBSize = SW.CreateSlider(container, L["SETTINGS_PB_ICON_SIZE"], 16, 80, 1, _pbSL2)
  BindSlider(slPBSize, "priorityBar", "iconSize")
  local slPBSpacing = SW.CreateSlider(container, L["SETTINGS_SPACING"], 0, 30, 1, _pbSL2)
  BindSlider(slPBSpacing, "priorityBar", "iconSpacing")
  ctx:AddRow(8, slPBSize, slPBSpacing)

  local slPBOffset = SW.CreateSlider(container, L["SETTINGS_PB_HORIZ_DISTANCE"], 50, 400, 1, _pbSL2)
  BindSlider(slPBOffset, "priorityBar", "sideOffset")
  local origOff = slPBOffset.onChanged
  slPBOffset.onChanged = function(val)
    local PB = ns.Modules.PriorityBar
    if PB and PB.ClearDragPositions then PB.ClearDragPositions() end
    origOff(val)
  end
  local slPBVert = SW.CreateSlider(container, L["SETTINGS_VERTICAL_OFFSET"], -500, 500, 1, _pbSL2)
  BindSlider(slPBVert, "priorityBar", "verticalOffset")
  local origVert = slPBVert.onChanged
  slPBVert.onChanged = function(val)
    local PB = ns.Modules.PriorityBar
    if PB and PB.ClearDragPositions then PB.ClearDragPositions() end
    origVert(val)
  end
  ctx:AddRow(8, slPBOffset, slPBVert)

  ctx:Spacer(4)

  local cbSwipe = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_SHOW_SWIPE"],
    L["SETTINGS_PB_SHOW_SWIPE_TT"], W))
  BindCheckbox(cbSwipe, "priorityBar", "showCooldownSwipe")

  local cbDesat = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_DESATURATE"],
    L["SETTINGS_PB_DESATURATE_TT"], W))
  BindCheckbox(cbDesat, "priorityBar", "desaturateOnCooldown")

  local cbHideUnlearned = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_HIDE_UNLEARNED"],
    L["SETTINGS_PB_HIDE_UNLEARNED_TT"], W))
  BindCheckbox(cbHideUnlearned, "priorityBar", "hideUnlearned")

  local cbTooltipAlt = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_TOOLTIP_ALT_COMBAT"],
    L["SETTINGS_PB_TOOLTIP_ALT_COMBAT_TT"], W))
  BindCheckbox(cbTooltipAlt, "priorityBar", "tooltipAltCombatOnly")

  ctx:Spacer(4)

  -- Bordure
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_BORDER"], W))

  local cbBorder = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_SHOW_BORDER"], "", W))
  BindCheckbox(cbBorder, "priorityBar", "showBorder")

  local ddBorderStyle = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_STYLE"], {
    { value = "solid",  text = L["SETTINGS_BORDER_SOLID"]  },
    { value = "glow",   text = L["SETTINGS_BORDER_GLOW"]   },
    { value = "shadow", text = L["SETTINGS_BORDER_SHADOW"] },
  }, W))
  BindDropdown(ddBorderStyle, "priorityBar", "borderStyle")

  local slBorderSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_THICKNESS"], 1, 6, 1, W))
  BindSlider(slBorderSize, "priorityBar", "borderSize")

  local colBorder = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_BORDER_COLOR"], W))
  BindColorButton(colBorder, "priorityBar", "borderColor")

  ctx:Spacer(4)

  -- Texte de cooldown
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_COOLDOWN_TEXT"], W))

  local cbCDText = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_SHOW_COOLDOWN"], "", W))
  BindCheckbox(cbCDText, "priorityBar", "showCooldownText")

  local slCDFont = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 8, 24, 1, W))
  BindSlider(slCDFont, "priorityBar", "cooldownFontSize")

  local colCDText = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TEXT_COLOR"], W))
  BindColorButton(colCDText, "priorityBar", "cooldownTextColor")

  ctx:Spacer(4)

  -- Charges
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CHARGES"], W))

  local cbCharges = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_SHOW_CHARGES"], "", W))
  BindCheckbox(cbCharges, "priorityBar", "showCharges")

  local ddChargePos = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_POSITION"], {
    { value = "TOPLEFT",     text = L["SETTINGS_ANCHOR_TOPLEFT"]     },
    { value = "TOP",         text = L["SETTINGS_ANCHOR_TOP"]         },
    { value = "TOPRIGHT",    text = L["SETTINGS_ANCHOR_TOPRIGHT"]    },
    { value = "LEFT",        text = L["SETTINGS_ANCHOR_LEFT"]        },
    { value = "CENTER",      text = L["SETTINGS_ANCHOR_CENTER"]      },
    { value = "RIGHT",       text = L["SETTINGS_ANCHOR_RIGHT"]       },
    { value = "BOTTOMLEFT",  text = L["SETTINGS_ANCHOR_BOTTOMLEFT"]  },
    { value = "BOTTOM",      text = L["SETTINGS_ANCHOR_BOTTOM"]      },
    { value = "BOTTOMRIGHT", text = L["SETTINGS_ANCHOR_BOTTOMRIGHT"] },
  }, W))
  BindDropdown(ddChargePos, "priorityBar", "chargePosition")

  local slChargeOffX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, _pbSL3)
  BindSlider(slChargeOffX, "priorityBar", "chargeOffsetX")
  local slChargeOffY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, _pbSL3)
  BindSlider(slChargeOffY, "priorityBar", "chargeOffsetY")
  local slChargeFont = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 8, 24, 1, _pbSL3)
  BindSlider(slChargeFont, "priorityBar", "chargeFontSize")
  ctx:AddRow(8, slChargeOffX, slChargeOffY, slChargeFont)

  local colCharges = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_PB_CHARGES_COLOR"], W))
  BindColorButton(colCharges, "priorityBar", "chargeColor")

  ctx:Spacer(4)

  -- Glow
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_GLOW"], W))

  -- Single-icon glow preview
  local pvFrame = CreateFrame("Frame", nil, container)
  pvFrame:SetSize(W, 70)
  local pvBg = pvFrame:CreateTexture(nil, "BACKGROUND")
  pvBg:SetAllPoints(); pvBg:SetColorTexture(0.04, 0.04, 0.06, 0.6)

  local pIcon = CreateFrame("Frame", nil, pvFrame)
  pIcon:SetSize(40, 40)
  pIcon:SetPoint("CENTER", pvFrame, "CENTER", 0, 0)
  pIcon.icon = pIcon:CreateTexture(nil, "ARTWORK")
  pIcon.icon:SetAllPoints()
  pIcon.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  pIcon.icon:SetTexture(134154)
  pIcon.borderLines = {}
  for _, side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
    pIcon.borderLines[side] = pIcon:CreateTexture(nil, "OVERLAY", nil, 0)
  end
  -- Legacy pulse glow
  pIcon.glow = pIcon:CreateTexture(nil, "OVERLAY", nil, 1)
  pIcon.glow:SetBlendMode("ADD"); pIcon.glow:SetAlpha(0); pIcon.glow:Hide()
  pIcon.glowAG = pIcon.glow:CreateAnimationGroup()
  pIcon.glowAG:SetLooping("BOUNCE")
  pIcon.glowPulse = pIcon.glowAG:CreateAnimation("Alpha")
  pIcon.glowPulse:SetSmoothing("IN_OUT")
  -- Flipbook loop glow
  pIcon.loopFlipTex = pIcon:CreateTexture(nil, "OVERLAY", nil, 2)
  pIcon.loopFlipTex:SetAlpha(0); pIcon.loopFlipTex:Hide()
  pIcon.loopFlipAG = pIcon.loopFlipTex:CreateAnimationGroup()
  pIcon.loopFlipAG:SetLooping("REPEAT")
  pIcon.loopFlipAnim = pIcon.loopFlipAG:CreateAnimation("FlipBook")
  pIcon.loopFlipAnim:SetOrder(1)
  -- Flipbook proc start (one-shot)
  pIcon.procStartTex = pIcon:CreateTexture(nil, "OVERLAY", nil, 3)
  pIcon.procStartTex:SetAlpha(0); pIcon.procStartTex:Hide()
  pIcon.procStartAG = pIcon.procStartTex:CreateAnimationGroup()
  pIcon.procStartAG:SetLooping("NONE")
  pIcon.procStartFlip = pIcon.procStartAG:CreateAnimation("FlipBook")
  pIcon.procStartFlip:SetOrder(1)
  pIcon.procStartAG:SetScript("OnFinished", function()
    pIcon.procStartTex:SetAlpha(0); pIcon.procStartTex:Hide()
  end)

  -- Auto-loop timer for proc start preview
  local pvTicker
  pvFrame:SetScript("OnShow", function()
    if pvTicker then pvTicker:Cancel() end
    pvTicker = C_Timer.NewTicker(1.5, function()
      if not pvFrame:IsVisible() then return end
      if container._refreshPreview then container._refreshPreview() end
    end)
  end)
  pvFrame:SetScript("OnHide", function()
    if pvTicker then pvTicker:Cancel(); pvTicker = nil end
  end)

  local function RefreshPreview()
    local c = ns.DB and ns.DB.priorityBar or {}
    local sz        = c.iconSize    or 34
    local showB     = c.showBorder  ~= false
    local bStyle    = c.borderStyle or "solid"
    local bSize     = c.borderSize  or 2
    local bc        = c.borderColor or { 0.15, 0.15, 0.15, 0.9 }
    local glowColor = c.glowColor   or { 1, 0.85, 0, 0.8 }
    local glowSz    = c.glowSize    or 4
    local loopIdx   = c.loopGlowIndex or 1
    local psIdx     = c.procStartIndex or 1
    if c.useSpecGlowColor then
      local Clr = ns.Modules and ns.Modules.Colors
      if Clr and Clr.Get then
        local specC = Clr.Get("glow")
        if specC then glowColor = specC end
      end
    end
    local PB = ns.Modules.PriorityBar
    local LOOP = PB and PB.LOOP_GLOW_TYPES
    local PROC = PB and PB.PROC_START_TYPES
    local gt = LOOP and LOOP[loopIdx] or (LOOP and LOOP[1])
    local ps = PROC and PROC[psIdx]

    pIcon:SetSize(sz, sz)

    -- Border
    local blend = (bStyle == "glow") and "ADD" or "BLEND"
    local lines = pIcon.borderLines
    if showB then
      lines.TOP:ClearAllPoints();lines.TOP:SetHeight(bSize)
      lines.TOP:SetPoint("TOPLEFT",pIcon,"TOPLEFT",-bSize,bSize);lines.TOP:SetPoint("TOPRIGHT",pIcon,"TOPRIGHT",bSize,bSize)
      lines.TOP:SetColorTexture(bc[1],bc[2],bc[3],bc[4]);lines.TOP:SetBlendMode(blend);lines.TOP:Show()
      lines.BOTTOM:ClearAllPoints();lines.BOTTOM:SetHeight(bSize)
      lines.BOTTOM:SetPoint("BOTTOMLEFT",pIcon,"BOTTOMLEFT",-bSize,-bSize);lines.BOTTOM:SetPoint("BOTTOMRIGHT",pIcon,"BOTTOMRIGHT",bSize,-bSize)
      lines.BOTTOM:SetColorTexture(bc[1],bc[2],bc[3],bc[4]);lines.BOTTOM:SetBlendMode(blend);lines.BOTTOM:Show()
      lines.LEFT:ClearAllPoints();lines.LEFT:SetWidth(bSize)
      lines.LEFT:SetPoint("TOPLEFT",pIcon,"TOPLEFT",-bSize,bSize);lines.LEFT:SetPoint("BOTTOMLEFT",pIcon,"BOTTOMLEFT",-bSize,-bSize)
      lines.LEFT:SetColorTexture(bc[1],bc[2],bc[3],bc[4]);lines.LEFT:SetBlendMode(blend);lines.LEFT:Show()
      lines.RIGHT:ClearAllPoints();lines.RIGHT:SetWidth(bSize)
      lines.RIGHT:SetPoint("TOPRIGHT",pIcon,"TOPRIGHT",bSize,bSize);lines.RIGHT:SetPoint("BOTTOMRIGHT",pIcon,"BOTTOMRIGHT",bSize,-bSize)
      lines.RIGHT:SetColorTexture(bc[1],bc[2],bc[3],bc[4]);lines.RIGHT:SetBlendMode(blend);lines.RIGHT:Show()
    else
      for _, line in pairs(lines) do line:Hide() end
    end

    -- Stop all animations
    pIcon.glowAG:Stop(); pIcon.glow:SetAlpha(0); pIcon.glow:Hide()
    pIcon.loopFlipAG:Stop(); pIcon.loopFlipTex:SetAlpha(0); pIcon.loopFlipTex:Hide()
    pIcon.procStartAG:Stop(); pIcon.procStartTex:SetAlpha(0); pIcon.procStartTex:Hide()

    if gt then
      if gt.useAlphaPulse then
        -- Pulse mode
        if gt.atlas then
          pIcon.glow:SetTexture(nil);pIcon.glow:SetAtlas(gt.atlas);pIcon.glow:SetTexCoord(0,1,0,1)
        else
          pIcon.glow:SetTexture(gt.texture)
          if gt.texCoord then pIcon.glow:SetTexCoord(unpack(gt.texCoord)) else pIcon.glow:SetTexCoord(0,1,0,1) end
        end
        pIcon.glow:SetBlendMode(gt.blendMode or "ADD")
        pIcon.glow:SetVertexColor(glowColor[1],glowColor[2],glowColor[3],glowColor[4] or 1)
        pIcon.glow:ClearAllPoints()
        pIcon.glow:SetPoint("TOPLEFT",pIcon,"TOPLEFT",-glowSz,glowSz)
        pIcon.glow:SetPoint("BOTTOMRIGHT",pIcon,"BOTTOMRIGHT",glowSz,-glowSz)
        pIcon.glowPulse:SetFromAlpha(gt.fromAlpha or 0.4)
        pIcon.glowPulse:SetToAlpha(gt.toAlpha or 0.8)
        pIcon.glowPulse:SetDuration(gt.duration or 0.8)
        pIcon.glow:SetAlpha(0.6);pIcon.glow:Show();pIcon.glowAG:Play()
      else
        -- Flipbook mode
        if gt.atlas then
          pIcon.loopFlipTex:SetTexture(nil); pIcon.loopFlipTex:SetAtlas(gt.atlas)
        elseif gt.texture then
          pIcon.loopFlipTex:SetTexture(gt.texture)
        end
        local sc = gt.scale or 1
        local texSz = sz * sc + glowSz * 2
        pIcon.loopFlipTex:ClearAllPoints()
        pIcon.loopFlipTex:SetSize(texSz, texSz)
        pIcon.loopFlipTex:SetPoint("CENTER", pIcon, "CENTER", 0, 0)
        pIcon.loopFlipTex:SetVertexColor(glowColor[1],glowColor[2],glowColor[3],glowColor[4] or 1)
        pIcon.loopFlipTex:SetBlendMode("ADD")
        pIcon.loopFlipAnim:SetFlipBookRows(gt.rows or 6)
        pIcon.loopFlipAnim:SetFlipBookColumns(gt.columns or 5)
        pIcon.loopFlipAnim:SetFlipBookFrames(gt.frames or 30)
        pIcon.loopFlipAnim:SetDuration(gt.duration or 1.0)
        pIcon.loopFlipAnim:SetFlipBookFrameWidth(gt.frameW or 0)
        pIcon.loopFlipAnim:SetFlipBookFrameHeight(gt.frameH or 0)
        pIcon.loopFlipTex:SetAlpha(1); pIcon.loopFlipTex:Show()
        pIcon.loopFlipAG:Play()
      end
    end

    -- Proc start (one-shot)
    if ps and psIdx > 1 then
      if ps.atlas then
        pIcon.procStartTex:SetTexture(nil); pIcon.procStartTex:SetAtlas(ps.atlas)
      elseif ps.texture then
        pIcon.procStartTex:SetTexture(ps.texture)
      end
      local psc = ps.scale or 1
      local psScale = psc * (sz / 42)
      pIcon.procStartTex:ClearAllPoints()
      pIcon.procStartTex:SetSize(150, 150)
      pIcon.procStartTex:SetScale(psScale)
      pIcon.procStartTex:SetPoint("CENTER", pIcon, "CENTER", 0, 0)
      pIcon.procStartTex:SetVertexColor(glowColor[1],glowColor[2],glowColor[3],glowColor[4] or 1)
      pIcon.procStartTex:SetBlendMode("ADD")
      pIcon.procStartFlip:SetFlipBookRows(ps.rows or 6)
      pIcon.procStartFlip:SetFlipBookColumns(ps.columns or 5)
      pIcon.procStartFlip:SetFlipBookFrames(ps.frames or 30)
      pIcon.procStartFlip:SetDuration(ps.duration or 0.7)
      pIcon.procStartFlip:SetFlipBookFrameWidth(ps.frameW or 0)
      pIcon.procStartFlip:SetFlipBookFrameHeight(ps.frameH or 0)
      pIcon.procStartTex:SetAlpha(1); pIcon.procStartTex:Show()
      pIcon.procStartAG:Stop(); pIcon.procStartAG:Play()
    end
  end
  container._refreshPreview = RefreshPreview
  ctx:Add(pvFrame)

  -- Build loop glow dropdown items dynamically from PB.LOOP_GLOW_TYPES
  local loopGlowItems = {}
  do
    local PB = ns.Modules.PriorityBar
    local LOOP = PB and PB.LOOP_GLOW_TYPES or {}
    for idx, def in ipairs(LOOP) do
      loopGlowItems[#loopGlowItems + 1] = { value = idx, text = def.name }
    end
  end
  local ddLoopGlow = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_PB_LOOP_GLOW_TYPE"], loopGlowItems, W))
  BindDropdown(ddLoopGlow, "priorityBar", "loopGlowIndex")

  -- Build proc start dropdown items dynamically
  local procStartItems = {}
  do
    local PB = ns.Modules.PriorityBar
    local PROC = PB and PB.PROC_START_TYPES or {}
    for idx, def in ipairs(PROC) do
      procStartItems[#procStartItems + 1] = { value = idx, text = def.name }
    end
  end
  local ddProcStart = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_PB_PROC_START_ANIM"], procStartItems, W))
  BindDropdown(ddProcStart, "priorityBar", "procStartIndex")

  local colGlow = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_GLOW_COLOR"], W))
  BindColorButton(colGlow, "priorityBar", "glowColor")

  local slGlowSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_GLOW_SIZE"], 0, 16, 1, W))
  BindSlider(slGlowSize, "priorityBar", "glowSize")

  local cbSpecColor = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_USE_SPEC_COLOR"],
    L["SETTINGS_PB_USE_SPEC_COLOR_TT"], W))
  BindCheckbox(cbSpecColor, "priorityBar", "useSpecGlowColor")

  ctx:Spacer(4)

  -- Bouton reset
  local resetBtn = SW.CreateActionBtn(container, L["SETTINGS_PB_RESET_POSITIONS"], W,
    nil, Theme.gold, Theme.accentText)
  resetBtn:SetScript("OnClick", function()
    local PB = ns.Modules.PriorityBar
    if PB and PB.ResetPositions then PB.ResetPositions(); PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
  end)
  ctx:Add(resetBtn)

  -- Raccorder le preview
  local function WP(w)
    if w and w.onChanged then
      local orig = w.onChanged
      w.onChanged = function(val)
        orig(val)
        if container._refreshPreview then container._refreshPreview() end
      end
    end
  end
  WP(slPBSize); WP(cbBorder); WP(ddBorderStyle); WP(slBorderSize); WP(colBorder)
  WP(ddLoopGlow); WP(ddProcStart); WP(colGlow); WP(slGlowSize); WP(cbSpecColor)

  C_Timer.After(0, function()
    if container._refreshPreview then container._refreshPreview() end
  end)

  -- Section editeur de slots (par spec)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SLOT_SPELLS"], W))

  local slotBaseY = ctx.y

  -- Creation du SpellPicker en lazy (singleton global)
  if not SpellPickerFrame then
    local f = CreateFrame("Frame", "AishCoreSpellPicker", UIParent, "BackdropTemplate")
    f:SetSize(264, 318)
    f:SetFrameStrata("TOOLTIP")
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
    f:SetBackdropBorderColor(unpack(Theme.accent))
    f:Hide(); f:EnableMouse(true)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(ns.Media.fontTitle, 11, "OUTLINE")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetTextColor(unpack(Theme.accentText))
    title:SetText(L["SETTINGS_ADD_SPELL_TITLE"])

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    closeBtn:GetNormalTexture():SetVertexColor(0.7, 0.7, 0.7)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    SW.StyleEditBox(searchBox)
    searchBox:SetSize(238, 20)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -26)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self) f:FilterSpells(self:GetText()) end)
    searchBox:SetScript("OnEscapePressed", function() f:Hide() end)
    f._searchBox = searchBox

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     searchBox, "BOTTOMLEFT",  0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", -28, 8)
    local sc = CreateFrame("Frame", nil, scrollFrame)
    sc:SetWidth(220); sc:SetHeight(1)
    scrollFrame:SetScrollChild(sc)
    f._sc = sc; f._sf = scrollFrame

    local MAX_ROWS = 120
    local rows = {}
    for i = 1, MAX_ROWS do
      local row = CreateFrame("Button", nil, sc)
      row:SetSize(220, 22)
      row:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -(i-1)*22)
      local rbg = row:CreateTexture(nil, "BACKGROUND")
      rbg:SetAllPoints(); rbg:SetColorTexture(0,0,0,0); row._bg = rbg
      local ico = row:CreateTexture(nil, "ARTWORK")
      ico:SetSize(18,18); ico:SetTexCoord(0.08,0.92,0.08,0.92)
      ico:SetPoint("LEFT", row, "LEFT", 2, 0); row._ico = ico
      local nm = row:CreateFontString(nil, "OVERLAY")
      nm:SetFont(ns.Media.fontGui, 10); nm:SetJustifyH("LEFT")
      nm:SetPoint("LEFT", ico, "RIGHT", 4, 0)
      nm:SetPoint("RIGHT", row, "RIGHT", -2, 0)
      nm:SetTextColor(unpack(Theme.textNormal)); row._nm = nm
      row:SetScript("OnEnter", function(s)
        s._bg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.22)
        s._nm:SetTextColor(unpack(Theme.textHighlight))
      end)
      row:SetScript("OnLeave", function(s)
        s._bg:SetColorTexture(0,0,0,0)
        s._nm:SetTextColor(unpack(Theme.textNormal))
      end)
      row:SetScript("OnClick", function(s)
        if f._onAdd then f._onAdd(s._spellID) end
        f:Hide()
      end)
      row:Hide(); rows[i] = row
    end
    f._rows = rows; f._allSpells = {}

    function f:FilterSpells(text)
      local t = strlower(text or "")
      local n = 0
      for _, s in ipairs(self._allSpells) do
        if t == "" or strlower(s.name):find(t, 1, true) then
          n = n + 1
          if n <= MAX_ROWS then
            local r = rows[n]
            r._spellID = s.id
            r._ico:SetTexture(s.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r._nm:SetText(s.name); r:Show()
          end
        end
      end
      for i = n + 1, MAX_ROWS do rows[i]:Hide() end
      sc:SetHeight(math.max(1, n * 22))
      self._sf:SetVerticalScroll(0)
    end

    function f:Open(anchor, slotIdx, onAdd)
      self._onAdd = onAdd
      self._searchBox:SetText("")
      local PB = ns.Modules.PriorityBar
      self._allSpells = (PB and PB.GetSpecSpells) and PB.GetSpecSpells() or {}
      self:FilterSpells("")
      self:ClearAllPoints()
      self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
      self:Show(); self:Raise()
      self._searchBox:SetFocus()
    end

    f:SetScript("OnMouseDown", function(self, btn)
      if btn == "RightButton" then self:Hide() end
    end)
    SpellPickerFrame = f
  end

  -- Éditeur de slots : construction dynamique
  local slotEditorFrames = {}

  local function BuildSlotEditorUI()
    for _, fr in ipairs(slotEditorFrames) do fr:Hide() end
    wipe(slotEditorFrames)

    local PB = ns.Modules.PriorityBar
    if not (PB and PB.GetCurrentSpecSlots) then
      container:SetHeight(slotBaseY + 20)
      return
    end

    local currentSlots = PB.GetCurrentSpecSlots()
    local layoutDef = PB.LAYOUT_DEFS and PB.GetCurrentSpecLayout and (function()
      local id = PB.GetCurrentSpecLayout()
      for _, d in ipairs(PB.LAYOUT_DEFS) do if d.id == id then return d end end
      return PB.LAYOUT_DEFS[1]
    end)() or { totalSlots = 4 }
    local totalSlots = layoutDef.totalSlots
    -- Construire la table des noms complets (gauche puis droite)
    local allNames = {}
    if layoutDef.leftNames then
      for _, n in ipairs(layoutDef.leftNames)  do allNames[#allNames + 1] = n end
    end
    if layoutDef.rightNames then
      for _, n in ipairs(layoutDef.rightNames) do allNames[#allNames + 1] = n end
    end

    local yOff  = slotBaseY
    local ROW_H = 22
    local HEAD_H = 26

    for slotIndex = 1, totalSlots do
      local slotData = currentSlots[slotIndex] or { spellIDs = {}, name = allNames[slotIndex] or string.format(L["SETTINGS_SLOT_FALLBACK_NAME"], slotIndex) }
      local spellIDs = slotData.spellIDs or {}
      local slotName = allNames[slotIndex] or slotData.name or string.format(L["SETTINGS_SLOT_FALLBACK_NAME"], slotIndex)

      -- En-tête du slot
      local hdr = CreateFrame("Frame", nil, container)
      hdr:SetSize(W, HEAD_H)
      hdr:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOff)
      local hBg = hdr:CreateTexture(nil, "BACKGROUND")
      hBg:SetAllPoints(); hBg:SetColorTexture(0.07, 0.07, 0.12, 0.85)
      local hAccent = hdr:CreateTexture(nil, "ARTWORK")
      hAccent:SetWidth(3); hAccent:SetPoint("TOPLEFT", hdr, "TOPLEFT", 0, 0)
      hAccent:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
      hAccent:SetColorTexture(unpack(Theme.accent))
      local hTxt = hdr:CreateFontString(nil, "OVERLAY")
      hTxt:SetFont(ns.Media.fontTitle, 10, "OUTLINE")
      hTxt:SetPoint("LEFT", hdr, "LEFT", 10, 0)
      hTxt:SetTextColor(unpack(Theme.accentText))
      hTxt:SetText(slotName)
      slotEditorFrames[#slotEditorFrames + 1] = hdr
      yOff = yOff + HEAD_H

      -- Lignes par sort
      for rowIdx, spellID in ipairs(spellIDs) do
        local capturedRow   = rowIdx
        local capturedSIDs  = spellIDs
        local capturedSlot  = slotIndex
        local row = CreateFrame("Frame", nil, container)
        row:SetSize(W, ROW_H)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOff)
        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(rowIdx % 2 == 0 and 0.05 or 0.04, 0.05, 0.07, 0.6)
        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(18, 18); ico:SetTexCoord(0.08,0.92,0.08,0.92)
        ico:SetPoint("LEFT", row, "LEFT", 6, 0)
        local icoTex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
                    or (GetSpellTexture and GetSpellTexture(spellID))
                    or "Interface\\Icons\\INV_Misc_QuestionMark"
        ico:SetTexture(icoTex)
        local capturedSpellID = spellID

        local nm = row:CreateFontString(nil, "OVERLAY")
        nm:SetFont(ns.Media.fontGui, 10); nm:SetJustifyH("LEFT")
        nm:SetPoint("LEFT", ico, "RIGHT", 5, 0)
        nm:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        nm:SetTextColor(unpack(Theme.textNormal))
        local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or string.format(L["SETTINGS_SPELL_FALLBACK_HASH"], spellID)
        nm:SetText(spellName or string.format(L["SETTINGS_SPELL_FALLBACK_HASH"], spellID))

        -- Pastille de couleur de glow individuelle
        local colorBtn = CreateFrame("Button", nil, row)
        colorBtn:SetSize(18, ROW_H)
        colorBtn:SetPoint("RIGHT", row, "RIGHT", -78, 0)
        local cbBorder = colorBtn:CreateTexture(nil, "BACKGROUND")
        cbBorder:SetAllPoints()
        cbBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
        local cbColor = colorBtn:CreateTexture(nil, "ARTWORK")
        cbColor:SetPoint("TOPLEFT",     colorBtn, "TOPLEFT",     1, -1)
        cbColor:SetPoint("BOTTOMRIGHT", colorBtn, "BOTTOMRIGHT", -1,  1)
        do
          local sc = ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.spellColors
                     and ns.DB.priorityBar.spellColors[capturedSpellID]
          if sc then
            cbColor:SetColorTexture(sc[1], sc[2], sc[3], sc[4] or 1)
          else
            cbColor:SetColorTexture(0.4, 0.4, 0.4, 0.5)
          end
        end
        colorBtn:SetScript("OnClick", function(self, btn)
          if btn == "RightButton" then
            -- Clic droit : supprimer la couleur individuelle
            if ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.spellColors then
              ns.DB.priorityBar.spellColors[capturedSpellID] = nil
            end
            cbColor:SetColorTexture(0.4, 0.4, 0.4, 0.5)
            return
          end
          -- Clic gauche : ouvrir le sélecteur de couleur
          local sc = (ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.spellColors
                      and ns.DB.priorityBar.spellColors[capturedSpellID])
                     or { 1, 0.85, 0, 1 }
          local function ApplySpellColor(r, g, b, a)
            if not ns.DB             then ns.DB = {} end
            if not ns.DB.priorityBar then ns.DB.priorityBar = {} end
            if not ns.DB.priorityBar.spellColors then ns.DB.priorityBar.spellColors = {} end
            ns.DB.priorityBar.spellColors[capturedSpellID] = { r, g, b, a or 1 }
            cbColor:SetColorTexture(r, g, b, a or 1)
          end
          local info = {}
          info.r = sc[1]; info.g = sc[2]; info.b = sc[3]; info.opacity = sc[4] or 1
          info.hasOpacity = true
          info.swatchFunc = function()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
            ApplySpellColor(nr, ng, nb, na)
          end
          info.opacityFunc = info.swatchFunc
          info.cancelFunc = function(prev)
            if prev then
              ApplySpellColor(prev.r or sc[1], prev.g or sc[2], prev.b or sc[3],
                              prev.opacity or sc[4] or 1)
            end
          end
          ColorPickerFrame:SetupColorPickerAndShow(info)
        end)
        colorBtn:SetScript("OnEnter", function()
          cbBorder:SetColorTexture(1, 1, 1, 0.6)
          GameTooltip:SetOwner(colorBtn, "ANCHOR_TOP", 0, 4)
          GameTooltip:SetText(L["SETTINGS_PB_HIGHLIGHT_COLOR"], 1, 1, 1)
          GameTooltip:AddLine(L["SETTINGS_PB_HIGHLIGHT_COLOR_TT1"], 0.7, 0.7, 0.7, true)
          GameTooltip:AddLine(L["SETTINGS_PB_HIGHLIGHT_COLOR_TT2"], 0.6, 0.6, 0.6, true)
          GameTooltip:Show()
        end)
        colorBtn:SetScript("OnLeave", function()
          cbBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
          GameTooltip:Hide()
        end)

        local BTN = 18
        local btnUp = CreateFrame("Button", nil, row)
        btnUp:SetSize(BTN, ROW_H); btnUp:SetPoint("RIGHT", row, "RIGHT", -54, 0)
        btnUp:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        btnUp:GetNormalTexture():SetVertexColor(1,1,1, capturedRow == 1 and 0.25 or 0.8)
        btnUp:SetScript("OnClick", function()
          if InCombatLockdown() then return end
          local slots = PB.GetCurrentSpecSlots()
          local ids   = { unpack(slots[capturedSlot].spellIDs) }
          if capturedRow > 1 then
            ids[capturedRow], ids[capturedRow-1] = ids[capturedRow-1], ids[capturedRow]
            PB.SetSlotSpells(capturedSlot, ids); BuildSlotEditorUI()
          end
        end)

        local btnDn = CreateFrame("Button", nil, row)
        btnDn:SetSize(BTN, ROW_H); btnDn:SetPoint("RIGHT", row, "RIGHT", -34, 0)
        btnDn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        btnDn:GetNormalTexture():SetVertexColor(1,1,1, capturedRow == #capturedSIDs and 0.25 or 0.8)
        btnDn:SetScript("OnClick", function()
          if InCombatLockdown() then return end
          local slots = PB.GetCurrentSpecSlots()
          local ids   = { unpack(slots[capturedSlot].spellIDs) }
          if capturedRow < #ids then
            ids[capturedRow], ids[capturedRow+1] = ids[capturedRow+1], ids[capturedRow]
            PB.SetSlotSpells(capturedSlot, ids); BuildSlotEditorUI()
          end
        end)

        local btnDel = CreateFrame("Button", nil, row)
        btnDel:SetSize(BTN, ROW_H); btnDel:SetPoint("RIGHT", row, "RIGHT", -14, 0)
        btnDel:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        btnDel:GetNormalTexture():SetVertexColor(0.9, 0.3, 0.3)
        btnDel:SetScript("OnClick", function()
          if InCombatLockdown() then return end
          local slots = PB.GetCurrentSpecSlots()
          local ids   = { unpack(slots[capturedSlot].spellIDs) }
          table.remove(ids, capturedRow)
          PB.SetSlotSpells(capturedSlot, ids); BuildSlotEditorUI()
        end)

        slotEditorFrames[#slotEditorFrames + 1] = row
        yOff = yOff + ROW_H
      end

      -- Bouton "+ Ajouter un sort"
      local addBtn = CreateFrame("Button", nil, container)
      addBtn:SetSize(W, 22)
      addBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOff)
      local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
      addBg:SetAllPoints(); addBg:SetColorTexture(0.07, 0.11, 0.07, 0.75)
      addBtn:SetScript("OnEnter", function() addBg:SetColorTexture(0.10,0.16,0.10,0.9) end)
      addBtn:SetScript("OnLeave", function() addBg:SetColorTexture(0.07,0.11,0.07,0.75) end)
      local addTxt = addBtn:CreateFontString(nil, "OVERLAY")
      addTxt:SetFont(ns.Media.fontGui, 10); addTxt:SetPoint("CENTER")
      addTxt:SetTextColor(0.35, 0.9, 0.35); addTxt:SetText(L["SETTINGS_ADD_SPELL_BTN"])
      local capturedSlot2 = slotIndex
      addBtn:SetScript("OnClick", function(self)
        if InCombatLockdown() then return end
        SpellPickerFrame:Open(self, capturedSlot2, function(pickedID)
          local slots = PB.GetCurrentSpecSlots()
          local ids   = { unpack(slots[capturedSlot2].spellIDs) }
          for _, ex in ipairs(ids) do if ex == pickedID then return end end
          ids[#ids + 1] = pickedID
          PB.SetSlotSpells(capturedSlot2, ids); BuildSlotEditorUI()
        end)
      end)
      slotEditorFrames[#slotEditorFrames + 1] = addBtn
      yOff = yOff + 22 + 4
    end

    -- Hauteur reelle du container
    container:SetHeight(yOff + 16)
  end

  container._buildSlotEditor = BuildSlotEditorUI
  C_Timer.After(0.2, BuildSlotEditorUI)

  if ns.CallbackRegistry then
    ns.CallbackRegistry:Register("PriorityBar.SpecChanged", function()
      if container and container:IsShown() then
        C_Timer.After(0.1, BuildSlotEditorUI)
      end
    end)
  end

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Top Target Bar
function Build.TopTargetBar(container)
  local ctx = NewLayout(container)
  local W   = CONTENT_W

  local function TTBGet(prop)
    local db  = ns.DB       and ns.DB.topTargetBar
    local def = ns.Defaults and ns.Defaults.topTargetBar
    if db  and db[prop]  ~= nil then return db[prop]  end
    if def and def[prop] ~= nil then return def[prop] end
  end
  local function TTBSet(prop, val)
    if not ns.DB              then ns.DB = {} end
    if not ns.DB.topTargetBar then ns.DB.topTargetBar = {} end
    ns.DB.topTargetBar[prop] = val
    local TTB = ns.Modules and ns.Modules.TopTargetBar
    if TTB and TTB.ApplySettings then TTB.ApplySettings() end
  end

  -- Paire de sliders lies a 2 proprietes topTargetBar, placee sur une seule
  -- ligne (remplace les anciennes paires d'edit box position/taille/decalage).
  local _ttbSL2 = math.floor((W - 10) / 2)
  local function MakeTTBSliderRow(propA, propB, labelA, labelB, minA, maxA, stepA, minB, maxB, stepB)
    local sA = SW.CreateSlider(container, labelA, minA, maxA, stepA, _ttbSL2)
    sA:SetValue(TTBGet(propA) or 0)
    sA.onChanged = function(val) TTBSet(propA, val) end
    local sB = SW.CreateSlider(container, labelB, minB, maxB, stepB, _ttbSL2)
    sB:SetValue(TTBGet(propB) or 0)
    sB.onChanged = function(val) TTBSet(propB, val) end
    ctx:AddRow(10, sA, sB)
  end

  -- Activer / désactiver le module
  local cbTTB = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_TTB_ENABLE"],
    L["SETTINGS_TTB_ENABLE_TT"], W))
  cbTTB.onChanged = function(val)
    if not ns.DB              then ns.DB = {} end
    if not ns.DB.topTargetBar then ns.DB.topTargetBar = {} end
    ns.DB.topTargetBar.enabled = val
    local TTB = ns.Modules and ns.Modules.TopTargetBar
    if TTB and TTB.ApplySettings then TTB.ApplySettings() end
    -- Ce handler ecrit directement en DB (pas de LiveApply/_invalidateCategory
    -- automatique) -- sans cet appel, la case "Activer" de la page "Modules"
    -- restait figee sur l'ancien etat apres un toggle ici.
    if _invalidateCategory then _invalidateCategory("modulesOverview") end
  end
  do
    local db  = ns.DB       and ns.DB.topTargetBar
    local def = ns.Defaults and ns.Defaults.topTargetBar
    local v = (db and db.enabled ~= nil) and db.enabled or (def and def.enabled ~= nil and def.enabled or true)
    cbTTB:SetChecked(v)
  end

  -- Toggle : afficher la cible de la cible
  local cbShowTT = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TTB_SHOW_TOT"],
    L["SETTINGS_TTB_SHOW_TOT_TT"], W))
  do
    local db  = ns.DB       and ns.DB.topTargetBar
    local def = ns.Defaults and ns.Defaults.topTargetBar
    local v = (db and db.showTargetOfTarget ~= nil) and db.showTargetOfTarget
              or (def and def.showTargetOfTarget ~= nil and def.showTargetOfTarget or true)
    cbShowTT:SetChecked(v)
  end
  cbShowTT.onChanged = function(val)
    if not ns.DB              then ns.DB = {} end
    if not ns.DB.topTargetBar then ns.DB.topTargetBar = {} end
    ns.DB.topTargetBar.showTargetOfTarget = val
    local TTB = ns.Modules and ns.Modules.TopTargetBar
    if TTB and TTB.ApplySettings then TTB.ApplySettings() end
    if _invalidateCategory then _invalidateCategory("modulesOverview") end
  end

  -- Toggle : afficher la barre de ressource (énergie / mana / rage…)
  local cbShowPower = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TTB_SHOW_POWER_BAR"],
    L["SETTINGS_TTB_SHOW_POWER_BAR_TT"], W))
  do
    local db  = ns.DB       and ns.DB.topTargetBar
    local def = ns.Defaults and ns.Defaults.topTargetBar
    local v = (db and db.showPowerBar ~= nil) and db.showPowerBar
              or (def and def.showPowerBar ~= nil and def.showPowerBar or false)
    cbShowPower:SetChecked(v)
  end
  cbShowPower.onChanged = function(val)
    if not ns.DB              then ns.DB = {} end
    if not ns.DB.topTargetBar then ns.DB.topTargetBar = {} end
    ns.DB.topTargetBar.showPowerBar = val
    local TTB = ns.Modules and ns.Modules.TopTargetBar
    if TTB and TTB.ApplySettings then TTB.ApplySettings() end
  end

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_CONTAINER"], W))
  MakeTTBSliderRow("x", "y", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -400, 400, 1, -400, 400, 1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_BLACK_BG"], W))
  MakeTTBSliderRow("bgW",  "bgH",  L["SETTINGS_WIDTH"],     L["SETTINGS_HEIGHT"],    60, 700, 1, 1, 60, 1)
  MakeTTBSliderRow("bgOX", "bgOY", L["SETTINGS_OFFSET_X"],  L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_COLORED_BAR"], W))
  MakeTTBSliderRow("barW",  "barH",  L["SETTINGS_WIDTH"],    L["SETTINGS_HEIGHT"],    60, 700, 1, 1, 20, 0.1)
  MakeTTBSliderRow("barOX", "barOY", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_NAME_TEXT"], W))
  local ddTTBNameFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddTTBNameFont, "topTargetBar", "nameFont")
  MakeTTBSliderRow("nameOX", "nameOY", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_HP_TEXT"], W))
  local ddTTBHpFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddTTBHpFont, "topTargetBar", "hpFont")

  -- Ancrage : widget partage SW.CreateAlignRow (meme widget que "Alignement"
  -- dans les barres de cast), avec les libelles LEFT/MIDDLE/RIGHT propres a
  -- l'ancrage plutot que left/center/right generiques.
  local alignHpAnchor = ctx:Add(SW.CreateAlignRow(container, L["SETTINGS_ANCHOR_COLON"], W, {
    { k = "LEFT",   l = L["SETTINGS_ALIGN_LEFT"] },
    { k = "CENTER", l = L["SETTINGS_ANCHOR_MIDDLE"] },
    { k = "RIGHT",  l = L["SETTINGS_ALIGN_RIGHT"] },
  }))
  alignHpAnchor:SetValue(TTBGet("hpAnchor") or "LEFT")
  alignHpAnchor.onChanged = function(val) TTBSet("hpAnchor", val) end

  local slTTBHpSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 28, 1, 200))
  slTTBHpSize:SetValue(TTBGet("hpFontSize") or 10)
  slTTBHpSize.onChanged = function(val) TTBSet("hpFontSize", val) end

  MakeTTBSliderRow("hpOX", "hpOY", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 1)

  ctx:Spacer()
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_CONTAINER"], W))
  MakeTTBSliderRow("ttx", "tty", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -400, 400, 1, -400, 400, 1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_BLACK_BG"], W))
  MakeTTBSliderRow("ttBgW",  "ttBgH",  L["SETTINGS_WIDTH"],    L["SETTINGS_HEIGHT"],    20, 300, 1, 1, 60, 1)
  MakeTTBSliderRow("ttBgOX", "ttBgOY", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_COLORED_BAR"], W))
  MakeTTBSliderRow("ttBarW",  "ttBarH",  L["SETTINGS_WIDTH"],    L["SETTINGS_HEIGHT"],    20, 300, 1, 1, 20, 0.1)
  MakeTTBSliderRow("ttBarOX", "ttBarOY", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 0.1)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_NAME_TEXT"], W))
  MakeTTBSliderRow("ttNameOX", "ttNameOY", L["SETTINGS_OFFSET_X"], L["SETTINGS_OFFSET_Y"], -50, 50, 1, -50, 50, 0.1)

  ctx:Finalize()
end

-- BUILD : Buffs / Debuffs de la cible
function Build.TargetAuras(container)
  local ctx = NewLayout(container)
  local W   = CONTENT_W

  -- Liste d'ancres pour les dropdowns de positionnement
  local ANCHOR_LIST = {
    { value = "TOPLEFT",     text = "TOPLEFT" },
    { value = "TOP",         text = "TOP" },
    { value = "TOPRIGHT",    text = "TOPRIGHT" },
    { value = "LEFT",        text = "LEFT" },
    { value = "CENTER",      text = "CENTER" },
    { value = "RIGHT",       text = "RIGHT" },
    { value = "BOTTOMLEFT",  text = "BOTTOMLEFT" },
    { value = "BOTTOM",      text = "BOTTOM" },
    { value = "BOTTOMRIGHT", text = "BOTTOMRIGHT" },
  }

  -- DB helpers : root level (enabled, offsetX, offsetY, rowSpacing)
  local function TAGet(prop)
    local db  = ns.DB       and ns.DB.targetAuras
    local def = ns.Defaults and ns.Defaults.targetAuras
    if db  and db[prop]  ~= nil then return db[prop]  end
    if def and def[prop] ~= nil then return def[prop] end
  end
  local function TASet(prop, val)
    if not ns.DB             then ns.DB = {} end
    if not ns.DB.targetAuras then ns.DB.targetAuras = {} end
    ns.DB.targetAuras[prop] = val
    local TA = ns.Modules and ns.Modules.TargetAuras
    if TA and TA.ApplySettings then TA.ApplySettings() end
  end

  -- DB helpers : group level (buffs / debuffs sub-tables)
  local function GrpGet(group, prop)
    local db  = ns.DB       and ns.DB.targetAuras       and ns.DB.targetAuras[group]
    local def = ns.Defaults and ns.Defaults.targetAuras  and ns.Defaults.targetAuras[group]
    if db  and db[prop]  ~= nil then return db[prop]  end
    if def and def[prop] ~= nil then return def[prop] end
  end
  local function GrpSet(group, prop, val)
    if not ns.DB             then ns.DB = {} end
    if not ns.DB.targetAuras then ns.DB.targetAuras = {} end
    if not ns.DB.targetAuras[group] then ns.DB.targetAuras[group] = {} end
    ns.DB.targetAuras[group][prop] = val
    local TA = ns.Modules and ns.Modules.TargetAuras
    if TA and TA.ApplySettings then TA.ApplySettings() end
  end

  -- XY row helper (parametre : parent + largeur, pour pouvoir vivre dans le
  -- sous-frame indente "detail" d'un groupe pliable, cf. BuildGroupSection)
  local function MakeTAXYRow(parent, rowWidth, getterFn, setterFn, propA, propB, labelA, labelB)
    local halfW = math.floor((rowWidth - 8) / 2)
    local sA = SW.CreateSlider(parent, labelA or L["SETTINGS_OFFSET_X"], -200, 200, 1, halfW)
    sA:SetValue(getterFn(propA) or 0)
    sA.onChanged = function(v) setterFn(propA, v) end
    local sB = SW.CreateSlider(parent, labelB or L["SETTINGS_OFFSET_Y"], -200, 200, 1, halfW)
    sB:SetValue(getterFn(propB) or 0)
    sB.onChanged = function(v) setterFn(propB, v) end
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(rowWidth, sA:GetHeight())
    sA:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    -- cf. MakeXYRow (Build.UnitBars) : ancrer sur la largeur REELLE du
    -- slider (plafonnee a MAX_SLIDER_W), pas sur halfW, sinon Décalage X/Y
    -- se retrouvent ecartes au lieu d'etre cote a cote.
    sB:SetPoint("TOPLEFT", row, "TOPLEFT", sA:GetWidth() + 8, 0)
    return row
  end

  -- Grow direction radio helper (parametre : parent + largeur, meme raison
  -- que MakeTAXYRow ci-dessus)
  local function MakeGrowRow(parent, rowWidth, group)
    local ABTN_W = 90
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(rowWidth, 26)
    local btns = {}
    local function Refresh(val)
      for _, b in ipairs(btns) do
        if b.key == val then
          b._lbl:SetTextColor(unpack(ns.Theme.accentText))
          b:SetBackdropColor(0.20, 0.15, 0.08, 1)
        else
          b._lbl:SetTextColor(unpack(ns.Theme.textNormal))
          b:SetBackdropColor(0.08, 0.08, 0.12, 1)
        end
      end
    end
    for i, opt in ipairs({ {k="LEFT", l=L["SETTINGS_ALIGN_LEFT"]}, {k="RIGHT", l=L["SETTINGS_ALIGN_RIGHT"]} }) do
      local b = CreateFrame("Button", nil, row, "BackdropTemplate")
      b:SetSize(ABTN_W, 22)
      b:SetPoint("LEFT", row, "LEFT", (i-1) * (ABTN_W + 4), 0)
      b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      b:SetBackdropColor(0.08, 0.08, 0.12, 1)
      b:SetBackdropBorderColor(unpack(ns.Theme.border))
      local lbl = b:CreateFontString(nil, "OVERLAY")
      lbl:SetAllPoints()
      lbl:SetFont(ns.Media.fontGui, 11)
      lbl:SetJustifyH("CENTER")
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(opt.l)
      b._lbl = lbl
      b.key = opt.k
      b:SetScript("OnClick", function()
        GrpSet(group, "growDirection", opt.k)
        Refresh(opt.k)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      end)
      table.insert(btns, b)
    end
    Refresh(GrpGet(group, "growDirection") or "RIGHT")
    return row
  end

  -- Etat plie/deplie de chaque groupe (Buffs/Debuffs) -- persiste dans
  -- ns.DB.targetAuras.uiCollapsed[group], meme mecanisme de rebuild complet
  -- que AFKMode/CharacterArmory (AFKToggleCollapsed/CAToggleCollapsed) :
  -- pas de simple Show/Hide car ctx n'est qu'un accumulateur de Y, pas un
  -- layout reactif. Deplie par defaut (contrairement a AFK/Armory) -- ici
  -- il n'y a que 2 groupes, pas une quinzaine d'elements a decongestionner.
  local function TACollapsed(group)
    local db = ns.DB and ns.DB.targetAuras
    return db and db.uiCollapsed and db.uiCollapsed[group] and true or false
  end
  local function TAToggleCollapsed(group)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.targetAuras then ns.DB.targetAuras = {} end
    if not ns.DB.targetAuras.uiCollapsed then ns.DB.targetAuras.uiCollapsed = {} end
    ns.DB.targetAuras.uiCollapsed[group] = not TACollapsed(group)
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll()
    if _invalidateCategory then _invalidateCategory("targetAuras") end
    if savedScroll then
      C_Timer.After(0, function()
        if scrollFrame then scrollFrame:SetVerticalScroll(savedScroll) end
      end)
    end
  end
  local TA_GROUP_INDENT = 26

  -- Builder : section complète pour un groupe (buffs ou debuffs) -- en-tete
  -- pliable "+ Buffs"/"- Buffs", contenu indente dans un sous-frame dedie
  -- ("detail", avec son propre layout dctx) quand deplie.
  local function BuildGroupSection(group, title)
    local gGet = function(prop) return GrpGet(group, prop) end
    local gSet = function(prop, val) GrpSet(group, prop, val) end

    ctx:Spacer(10)

    local collapsed = TACollapsed(group)
    local header = SW.CreateSectionHeader(container, (collapsed and "+ " or "- ") .. title, W)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -ctx.y)
    header:Show()
    local hitbox = CreateFrame("Button", nil, header)
    hitbox:SetAllPoints(header)
    hitbox:SetFrameLevel(header:GetFrameLevel() + 1)
    local hl = hitbox:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide()
    hitbox:SetScript("OnEnter", function() hl:Show() end)
    hitbox:SetScript("OnLeave", function() hl:Hide() end)
    hitbox:SetScript("OnClick", function() TAToggleCollapsed(group) end)
    ctx.y = ctx.y + header:GetHeight() + 2
    table.insert(ctx.widgets, header)
    if collapsed then return end

    local dw       = W - TA_GROUP_INDENT
    local dHalfW   = math.floor((dw - 8) / 2)
    -- Ancre/point relatif = simples mots-clefs Blizzard (TOPLEFT, BOTTOMRIGHT...)
    -- -- pas besoin de la moitié de la largeur du panneau pour ça.
    local ANCHOR_DD_W = 100
    local OFFSET_SL_W = 130
    local detail   = CreateFrame("Frame", nil, container)
    detail:SetWidth(dw)
    local dctx = NewLayout(detail)

    -- Ligne 1 : Taille icone, Decalage X, Decalage Y
    -- Ligne 2 : Nombre par ligne, Espacement, Nombre de lignes, Espace entre lignes
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_POSITION"], dw))

    local iconRowSL3 = math.floor((dw - 2 * 8) / 3)
    local slSize = SW.CreateSlider(detail, L["SETTINGS_TA_ICON_SIZE"], 14, 48, 1, iconRowSL3)
    slSize:SetValue(gGet("iconSize") or 26)
    slSize.onChanged = function(val) gSet("iconSize", val) end
    local slOffX = SW.CreateSlider(detail, L["SETTINGS_OFFSET_X"], -200, 200, 1, iconRowSL3)
    slOffX:SetValue(gGet("offsetX") or 0)
    slOffX.onChanged = function(val) gSet("offsetX", val) end
    local slOffY = SW.CreateSlider(detail, L["SETTINGS_OFFSET_Y"], -200, 200, 1, iconRowSL3)
    slOffY:SetValue(gGet("offsetY") or 0)
    slOffY.onChanged = function(val) gSet("offsetY", val) end
    dctx:AddRow(8, slSize, slOffX, slOffY)

    local gridSL4 = math.floor((dw - 3 * 8) / 4)
    local slMax = SW.CreateSlider(detail, L["SETTINGS_TA_MAX_PER_ROW"], 1, 40, 1, gridSL4)
    slMax:SetValue(gGet("maxAuras") or 16)
    slMax.onChanged = function(val) gSet("maxAuras", val) end
    local slSpacing = SW.CreateSlider(detail, L["SETTINGS_SPACING"], 0, 10, 1, gridSL4)
    slSpacing:SetValue(gGet("iconSpacing") or 2)
    slSpacing.onChanged = function(val) gSet("iconSpacing", val) end
    local slNumRows = SW.CreateSlider(detail, L["SETTINGS_TA_NUM_ROWS"], 1, 5, 1, gridSL4)
    slNumRows:SetValue(gGet("numRows") or 1)
    slNumRows.onChanged = function(val) gSet("numRows", val) end
    local slRowSpacing = SW.CreateSlider(detail, L["SETTINGS_TA_ROW_SPACING"], 0, 20, 1, gridSL4)
    slRowSpacing:SetValue(gGet("rowSpacing") or 2)
    slRowSpacing.onChanged = function(val) gSet("rowSpacing", val) end
    dctx:AddRow(8, slMax, slSpacing, slNumRows, slRowSpacing)

    local cbGrowUp = dctx:Add(SW.CreateCheckbox(detail,
      L["SETTINGS_TA_GROW_UP"],
      L["SETTINGS_TA_GROW_UP_TT"], dw))
    cbGrowUp:SetChecked(gGet("growUpward") == true)
    cbGrowUp.onChanged = function(val) gSet("growUpward", val) end

    -- Option debuff joueur uniquement
    if group == "debuffs" then
      local cbOnlyPlayer = dctx:Add(SW.CreateCheckbox(detail,
        L["SETTINGS_TA_ONLY_PLAYER_DEBUFFS"],
        L["SETTINGS_TA_ONLY_PLAYER_DEBUFFS_TT"], dw))
      cbOnlyPlayer:SetChecked(gGet("onlyPlayer") == true)
      cbOnlyPlayer.onChanged = function(val) gSet("onlyPlayer", val) end
    end

    -- Ordre de tri
    dctx:Spacer(4)
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_SORT"], dw))
    local SORT_MODES = {
      { key = "playerFirst", label = L["SETTINGS_SORT_PLAYER_FIRST"] },
      { key = "shortFirst",  label = L["SETTINGS_SORT_SHORT_FIRST"] },
      { key = "longFirst",   label = L["SETTINGS_SORT_LONG_FIRST"] },
      { key = "alpha",       label = L["SETTINGS_SORT_ALPHA"] },
      { key = "index",       label = L["SETTINGS_SORT_BLIZZARD_ORDER"] },
    }
    local sortOpts = {}
    for _, m in ipairs(SORT_MODES) do
      sortOpts[#sortOpts + 1] = { value = m.key, text = m.label }
    end
    local ddSort = dctx:Add(SW.CreateDropdown(detail, L["SETTINGS_SORT"], sortOpts, 200))
    do
      local cur = gGet("sortMode") or "playerFirst"
      ddSort:SetValue(cur)
    end
    ddSort.onChanged = function(val)
      gSet("sortMode", val)
    end

    local cbReverse = dctx:Add(SW.CreateCheckbox(detail,
      L["SETTINGS_TA_REVERSE_SORT"], L["SETTINGS_TA_REVERSE_SORT_TT"], dw))
    cbReverse:SetChecked(gGet("reverseSort") == true)
    cbReverse.onChanged = function(val) gSet("reverseSort", val) end

    -- Direction croissance
    dctx:Spacer(4)
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_DIRECTION"], dw))
    dctx:Add(MakeGrowRow(detail, dw, group))

    -- Bordure
    dctx:Spacer(4)
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_BORDER"], dw))

    local cbBorder = dctx:Add(SW.CreateCheckbox(detail,
      L["SETTINGS_SHOW_BORDER"], L["SETTINGS_TA_SHOW_BORDER_TT"], dw))
    cbBorder:SetChecked(gGet("showBorder") ~= false)
    cbBorder.onChanged = function(val) gSet("showBorder", val) end

    local slBorderSize = SW.CreateSlider(detail, L["SETTINGS_TA_BORDER_THICKNESS"], 0, 4, 1, dHalfW)
    slBorderSize:SetValue(gGet("borderSize") or 1)
    slBorderSize.onChanged = function(val) gSet("borderSize", val) end
    dctx:Add(slBorderSize)

    local colBorder = dctx:Add(SW.CreateColorButton(detail, L["SETTINGS_BORDER_COLOR"], dw))
    do
      local c = gGet("borderColor") or { 1, 1, 1, 0.15 }
      colBorder:SetColor(c[1], c[2], c[3], c[4])
    end
    colBorder.onChanged = function(val) gSet("borderColor", val) end

    -- Cooldown swipe
    dctx:Spacer(4)
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_COOLDOWN_SWIPE"], dw))

    local cbSwipe = dctx:Add(SW.CreateCheckbox(detail,
      L["SETTINGS_TA_SHOW_SWIPE"], L["SETTINGS_TA_SHOW_SWIPE_TT"], dw))
    cbSwipe:SetChecked(gGet("showSwipe") ~= false)
    cbSwipe.onChanged = function(val) gSet("showSwipe", val) end

    local cbRevSwipe = dctx:Add(SW.CreateCheckbox(detail,
      L["SETTINGS_TA_REVERSE_SWIPE"], L["SETTINGS_TA_REVERSE_SWIPE_TT"], dw))
    cbRevSwipe:SetChecked(gGet("reverseSwipe") == true)
    cbRevSwipe.onChanged = function(val) gSet("reverseSwipe", val) end

    -- Police & couleur durée : police/taille/couleur sur une rangee (pas de
    -- contour disponible pour la duree -- countOutlineStyle n'existe que
    -- pour les stacks, cf. section suivante).
    dctx:Spacer(4)
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_DURATION_TEXT"], dw))

    local durSL3 = math.floor((dw - 2 * 8) / 3)
    local ddDurFont = SW.CreateDropdown(detail, L["SETTINGS_TA_DURATION_FONT"], ns.GetFontList(), durSL3)
    do
      local v = gGet("durationFont")
      if v then ddDurFont:SetValue(v) end
    end
    ddDurFont.onChanged = function(val) gSet("durationFont", val) end

    local slDurSize = SW.CreateSlider(detail, L["SETTINGS_TA_DURATION_SIZE"], 6, 18, 1, durSL3)
    slDurSize:SetValue(gGet("durationFontSize") or 9)
    slDurSize.onChanged = function(val) gSet("durationFontSize", val) end

    local colDur = SW.CreateColorButton(detail, L["SETTINGS_TA_DURATION_COLOR"], durSL3)
    do
      local c = gGet("durationColor") or { 1, 1, 1, 1 }
      colDur:SetColor(c[1], c[2], c[3], c[4])
    end
    colDur.onChanged = function(val) gSet("durationColor", val) end
    dctx:AddRow(8, ddDurFont, slDurSize, colDur)

    -- Positionnement durée : ancre + décalage X/Y sur une seule rangée --
    -- ancre réduite à ANCHOR_DD_W (les valeurs sont de simples mots-clés
    -- Blizzard type TOPLEFT/BOTTOMRIGHT, pas besoin de la moitié de la largeur).
    dctx:Spacer(2)
    local ddDurAnc = SW.CreateDropdown(detail, L["SETTINGS_TA_DURATION_ANCHOR"], ANCHOR_LIST, ANCHOR_DD_W)
    do local v = gGet("durationAnchor"); if v then ddDurAnc:SetValue(v) end end
    ddDurAnc.onChanged = function(val) gSet("durationAnchor", val) end

    local slDurOffX = SW.CreateSlider(detail, L["SETTINGS_OFFSET_X"], -200, 200, 1, OFFSET_SL_W)
    slDurOffX:SetValue(gGet("durationOffX") or 0)
    slDurOffX.onChanged = function(val) gSet("durationOffX", val) end
    local slDurOffY = SW.CreateSlider(detail, L["SETTINGS_OFFSET_Y"], -200, 200, 1, OFFSET_SL_W)
    slDurOffY:SetValue(gGet("durationOffY") or 0)
    slDurOffY.onChanged = function(val) gSet("durationOffY", val) end
    dctx:AddRow(8, ddDurAnc, slDurOffX, slDurOffY)

    -- Police & couleur stacks : police/contour/taille/couleur sur une rangée
    dctx:Spacer(4)
    dctx:Add(SW.CreateSectionHeader(detail, L["SETTINGS_TA_SEC_STACKS_TEXT"], dw))

    local cntSL4 = math.floor((dw - 3 * 8) / 4)
    local ddCntFont = SW.CreateDropdown(detail, L["SETTINGS_TA_STACKS_FONT"], ns.GetFontList(), cntSL4)
    do
      local v = gGet("countFont")
      if v then ddCntFont:SetValue(v) end
    end
    ddCntFont.onChanged = function(val) gSet("countFont", val) end

    local ddCntOutline = SW.CreateDropdown(detail, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), cntSL4)
    ddCntOutline:SetValue(gGet("countOutlineStyle") or "OUTLINE")
    ddCntOutline.onChanged = function(val) gSet("countOutlineStyle", val) end

    local slCntSize = SW.CreateSlider(detail, L["SETTINGS_TA_STACKS_SIZE"], 6, 18, 1, cntSL4)
    slCntSize:SetValue(gGet("countFontSize") or 10)
    slCntSize.onChanged = function(val) gSet("countFontSize", val) end

    local colCnt = SW.CreateColorButton(detail, L["SETTINGS_TA_STACKS_COLOR"], cntSL4)
    do
      local c = gGet("countColor") or { 1, 1, 1, 1 }
      colCnt:SetColor(c[1], c[2], c[3], c[4])
    end
    colCnt.onChanged = function(val) gSet("countColor", val) end
    dctx:AddRow(8, ddCntFont, ddCntOutline, slCntSize, colCnt)

    -- Positionnement stacks : ancre + point relatif + décalage X/Y, les 4
    -- sur une seule rangée (ancre/point relatif réduits à ANCHOR_DD_W).
    dctx:Spacer(2)
    local ddCntAnc = SW.CreateDropdown(detail, L["SETTINGS_TA_TEXT_ANCHOR"], ANCHOR_LIST, ANCHOR_DD_W)
    do local v = gGet("countAnchor"); if v then ddCntAnc:SetValue(v) end end
    ddCntAnc.onChanged = function(val) gSet("countAnchor", val) end
    local ddCntRel = SW.CreateDropdown(detail, L["SETTINGS_TA_RELATIVE_POINT"], ANCHOR_LIST, ANCHOR_DD_W)
    do local v = gGet("countRelPoint"); if v then ddCntRel:SetValue(v) end end
    ddCntRel.onChanged = function(val) gSet("countRelPoint", val) end

    local slCntOffX = SW.CreateSlider(detail, L["SETTINGS_OFFSET_X"], -200, 200, 1, OFFSET_SL_W)
    slCntOffX:SetValue(gGet("countOffX") or 0)
    slCntOffX.onChanged = function(val) gSet("countOffX", val) end
    local slCntOffY = SW.CreateSlider(detail, L["SETTINGS_OFFSET_Y"], -200, 200, 1, OFFSET_SL_W)
    slCntOffY:SetValue(gGet("countOffY") or 0)
    slCntOffY.onChanged = function(val) gSet("countOffY", val) end
    dctx:AddRow(8, ddCntAnc, ddCntRel, slCntOffX, slCntOffY)

    dctx:Finalize()
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", container, "TOPLEFT", TA_GROUP_INDENT, -ctx.y)
    detail:Show()
    ctx.y = ctx.y + detail:GetHeight() + 2
    table.insert(ctx.widgets, detail)
  end
  -- /BuildGroupSection

  -- Section globale (enabled, offset, row spacing)
  local cbEn = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TA_ENABLE"],
    L["SETTINGS_TA_ENABLE_TT"], W))
  cbEn:SetChecked(TAGet("enabled") ~= false)
  cbEn.onChanged = function(val)
    TASet("enabled", val)
    -- TASet est generique et ne passe pas par LiveApply/_invalidateCategory.
    if _invalidateCategory then _invalidateCategory("modulesOverview") end
  end

  -- Sections par groupe
  BuildGroupSection("buffs",   L["SETTINGS_BUFFS"])
  BuildGroupSection("debuffs", L["SETTINGS_DEBUFFS"])

  ctx:Finalize()
end

-- BUILD : Couleurs par spécialisation
function Build.Colors(container)
  local Colors = ns.Modules and ns.Modules.Colors
  if not Colors then
    local lbl = container:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 11)
    lbl:SetTextColor(1, 0.3, 0.3, 1)
    lbl:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -16)
    lbl:SetText(L["SETTINGS_COLORS_MODULE_NOT_FOUND"])
    container:SetHeight(60)
    return
  end

  local ELEM_KEYS   = Colors.ELEMENT_KEYS
  local ELEM_LABELS = Colors.ELEMENT_LABELS
  -- Rectangles de couleur (52x24, ajuste depuis les 68x30 d'origine -- rendu
  -- WoW plus grand a l'ecran qu'une maquette web a taille "identique") +
  -- libelle sur 2 lignes en dessous, gap resserre a 2px -- le nombre de
  -- colonnes se recalcule a partir de CONTENT_W (donc de la largeur de
  -- fenetre, cf. MainFrame OnSizeChanged qui rebuild toute la categorie
  -- active) : la grille revient seule a la ligne quand la fenetre est trop
  -- etroite pour tout tenir sur une rangee.
  local SWATCH_W    = 52
  local SWATCH_H    = 24
  local LABEL_H     = 24
  local GAP_X       = 2
  local GAP_Y       = 2
  local CELL_STRIDE = SWATCH_W + GAP_X
  local ROW_STRIDE  = SWATCH_H + 4 + LABEL_H + GAP_Y
  local CLS_HDR_H   = 24
  local SPEC_INDENT = 14
  local SPEC_GAP    = 10
  local SECTION_PAD = 6

  local _, playerClassFile = UnitClass("player")
  local playerClassKey = playerClassFile and playerClassFile:lower()

  local expanded     = {}
  local classSections = {}

  -- -- Couleurs thematiques (header standard + 2 toggles) ----------------
  local secHeader = SW.CreateSectionHeader(container, L["SETTINGS_COLOR_MODE_HEADER"], CONTENT_W)
  secHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

  -- Toggle 1 : theme du GUI lui-meme (points de section, hairlines, fond
  -- actif sidebar...) -- actif par defaut (cf. SW.RefreshAccentTheme).
  -- Independant du mode de couleurs des spes ci-dessous : purement decoratif
  -- pour le panneau d'options, n'affecte aucune couleur en jeu.
  local cbThemeGUI = SW.CreateCheckbox(container, L["SETTINGS_COLOR_THEME_GUI"], L["SETTINGS_COLOR_THEME_GUI_TT"], CONTENT_W)
  cbThemeGUI:SetPoint("TOPLEFT", secHeader, "BOTTOMLEFT", 0, -4)
  cbThemeGUI:SetChecked(not (ns.DB and ns.DB.colors and ns.DB.colors.themeGUI == false))
  cbThemeGUI.onChanged = function(val)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.colors then ns.DB.colors = {} end
    ns.DB.colors.themeGUI = val
    if SW.RefreshAccentTheme then SW.RefreshAccentTheme() end
    -- Namespace separe du module Auras (_addon.Auras.THEME), cf.
    -- Modules/Auras/Core/ClassColors.lua:RefreshAccentTheme.
    if ns.Auras and ns.Auras.RefreshAccentTheme then ns.Auras.RefreshAccentTheme() end
  end

  -- Toggle 2 : couleurs de classe par defaut, desactive tout le systeme de
  -- personnalisation par spe ci-dessous (remplace les 2 anciens radios
  -- "classe par defaut"/"personnalise" par un seul toggle -- l'etat "custom"
  -- est simplement l'inverse de "classe par defaut").
  local cbClassDef = SW.CreateCheckbox(container, L["SETTINGS_COLOR_MODE_CLASS_DEFAULTS"], nil, CONTENT_W)
  cbClassDef:SetPoint("TOPLEFT", cbThemeGUI, "BOTTOMLEFT", 0, -2)

  -- Nag "Heroic Support" au-dessus des accordeons de classe -- seulement si
  -- moins de 4 specs DISTINCTES (toutes classes confondues) ont deja une
  -- override de couleur non vide (cf. Colors.SetOverride, ns.DB.colors.overrides).
  local colorsSupportNag
  do
    local alteredSpecsCount = 0
    local overrides = ns.DB and ns.DB.colors and ns.DB.colors.overrides
    if overrides then
      for _, specs in pairs(overrides) do
        for _, elements in pairs(specs) do
          if next(elements) then alteredSpecsCount = alteredSpecsCount + 1 end
        end
      end
    end
    if alteredSpecsCount < 4 then
      colorsSupportNag = SW.CreateSupportNag(container, CONTENT_W, L["SETTINGS_COLORS_FEW_SPECS_MSG"])
      colorsSupportNag:SetPoint("TOPLEFT", cbClassDef, "BOTTOMLEFT", 0, -8)
    end
  end

  local HEADER_H = secHeader:GetHeight() + 4 + cbThemeGUI:GetHeight() + 2 + cbClassDef:GetHeight() + 6
    + (colorsSupportNag and (colorsSupportNag:GetHeight() + 8) or 0)

  local function GetUseClassDefaults()
    return ns.DB and ns.DB.colors and ns.DB.colors.useClassDefaults
  end

  -- Redispose toutes les sections selon l'état expanded -- DOIT être défini
  -- avant ApplyClassMode : sinon, au moment où le corps de ApplyClassMode est
  -- compilé, "RebuildLayout" n'existe pas encore comme locale et résout vers
  -- une globale nil -> C_Timer.After(0, nil) plantait ("bad argument #2",
  -- confirmé en jeu à chaque clic sur le toggle).
  local function RebuildLayout()
    local y = HEADER_H + 4
    for _, sec in ipairs(classSections) do
      sec.headerBtn:ClearAllPoints()
      sec.headerBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
      y = y + CLS_HDR_H + 2
      if expanded[sec.cd.key] then
        sec.contentFrame:ClearAllPoints()
        sec.contentFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
        sec.contentFrame:Show()
        y = y + sec.contentFrame:GetHeight() + SECTION_PAD
      else
        sec.contentFrame:Hide()
      end
    end
    container:SetHeight(y + PADDING)
  end

  local function ApplyClassMode(useClassDef)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.colors then ns.DB.colors = {} end
    ns.DB.colors.useClassDefaults = useClassDef
    for _, sec in ipairs(classSections) do
      if useClassDef then
        -- Fermer toutes les sections déployées
        if expanded[sec.cd.key] then
          expanded[sec.cd.key] = false
          sec.headerBtn.text:SetText(("+ " .. sec.cd.name):upper())
          sec.contentFrame:Hide()
        end
        sec.hitbox:EnableMouse(false)
        sec.headerBtn:SetAlpha(0.3)
      else
        sec.hitbox:EnableMouse(true)
        sec.headerBtn:SetAlpha(1)
      end
    end
    -- Broadcast immédiat : useClassDefaults est déjà écrit, les modules liront la bonne valeur
    Colors.Broadcast()
    -- RebuildLayout différé : WoW doit d'abord traiter les Hide() avant de recalculer les positions
    C_Timer.After(0, RebuildLayout)
  end
  cbClassDef:SetChecked(GetUseClassDefaults() == true)
  cbClassDef.onChanged = function(val) ApplyClassMode(val) end

  -- En-tête pliable "à points/hairline" (même habillage que SW.CreateSectionHeader,
  -- même mécanique que AFKCollapsibleHeader dans Build.AFKMode : préfixe +/- dans
  -- le libellé + hitbox superposé pour le clic/survol) -- remplace l'ancien
  -- bandeau plein (fond bleu-gris 0.10/0.10/0.16 utilisé nulle part ailleurs
  -- dans le GUI) pour harmoniser avec le reste des sections (ex. Écran AFK).
  -- colorOverride = couleur de classe, conservée telle quelle (cf. RefreshColor
  -- dans SharedWidgets.lua : un header colorOverride ignore le thème d'accent).
  local function CreateClassHeader(parent, width, label, color, isExpanded)
    local header = SW.CreateSectionHeader(parent, ((isExpanded and "- " or "+ ") .. label), width, color)
    local hitbox = CreateFrame("Button", nil, header)
    hitbox:SetAllPoints(header)
    hitbox:SetFrameLevel(header:GetFrameLevel() + 1)
    local hl = hitbox:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:Hide()
    hitbox:SetScript("OnEnter", function() hl:Show() end)
    hitbox:SetScript("OnLeave", function() hl:Hide() end)
    return header, hitbox
  end

  for _, cd in ipairs(Colors.CLASSES) do
    local fc = Colors.CLASS_FALLBACK[cd.file] or {1,1,1,1}

    -- -- En-tête de classe (pliable) --------------------------------------
    local hHeader, hHitbox = CreateClassHeader(container, CONTENT_W, cd.name, fc, expanded[cd.key])

    -- -- Contenu (grid de spés) -----------------------------------------
    local cFrame = CreateFrame("Frame", nil, container)
    cFrame:SetWidth(CONTENT_W)
    cFrame:SetHeight(1)
    cFrame:Hide()

    local sec = {
      headerBtn    = hHeader,
      hitbox       = hHitbox,
      contentFrame = cFrame,
      cd           = cd,
      built        = false,
    }

    -- Construction lazy du contenu de la classe
    sec.BuildContent = function()
      if sec.built then return end
      local fy = 0
      -- Nombre de colonnes recalculé à chaque build à partir de CONTENT_W
      -- courant (la catégorie est entièrement reconstruite au resize, cf.
      -- MainFrame OnSizeChanged) : la grille de rectangles revient donc seule
      -- à la ligne selon la largeur de la fenêtre. La grille démarre à
      -- SPEC_INDENT, aligné sur l'en-tête de spé au-dessus (même indentation
      -- que son point/hairline), donc la largeur disponible est réduite d'autant.
      local cols = math.max(1, math.floor((CONTENT_W - SPEC_INDENT + GAP_X) / CELL_STRIDE))

      for _, spec in ipairs(cd.specs) do
        -- En-tête de spé -- même habillage point/hairline que l'en-tête de
        -- classe, juste indenté et non pliable (pas de fond plein). Couleur =
        -- élément "Cercle de Puissance" de CETTE spé (pas le fallback classe) :
        -- reprend la teinte réellement utilisée en jeu pour cette spé précise.
        local powerColor = Colors.GetForSpec(cd.key, spec.id, "powercircle") or fc
        local specHeader = SW.CreateSectionHeader(cFrame, spec.name, CONTENT_W - SPEC_INDENT, powerColor)
        specHeader:SetPoint("TOPLEFT", cFrame, "TOPLEFT", SPEC_INDENT, -fy)
        fy = fy + specHeader:GetHeight() + 6

        -- Grille de couleurs : rectangles + libellé (2 lignes max) en dessous,
        -- indentée à SPEC_INDENT pour s'aligner avec l'en-tête de spé ci-dessus.
        local col = 0
        for _, ek in ipairs(ELEM_KEYS) do
          local cx = SPEC_INDENT + col * CELL_STRIDE

          local cell = CreateFrame("Frame", nil, cFrame)
          cell:SetSize(SWATCH_W, SWATCH_H + 4 + LABEL_H)
          cell:SetPoint("TOPLEFT", cFrame, "TOPLEFT", cx, -fy)

          -- Swatch
          local sw = CreateFrame("Button", nil, cell)
          sw:SetSize(SWATCH_W, SWATCH_H)
          sw:SetPoint("TOP", cell, "TOP", 0, 0)
          sw:RegisterForClicks("LeftButtonUp", "RightButtonUp")

          local swBg = sw:CreateTexture(nil, "BACKGROUND")
          swBg:SetAllPoints()
          swBg:SetColorTexture(0.06, 0.06, 0.06, 1)

          local swTex = sw:CreateTexture(nil, "ARTWORK")
          swTex:SetPoint("TOPLEFT",     sw, "TOPLEFT",     1, -1)
          swTex:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -1, 1)

          local swBorder = sw:CreateTexture(nil, "BORDER")
          swBorder:SetPoint("TOPLEFT",     sw, "TOPLEFT",     -1,  1)
          swBorder:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT",  1, -1)
          swBorder:SetColorTexture(unpack(ns.Theme.border))

          -- Appliquer couleur initiale
          local function RefreshSwatch()
            local c = Colors.GetForSpec(cd.key, spec.id, ek)
            swTex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
          end
          RefreshSwatch()

          -- Label élément, sous le rectangle, centré, 2 lignes max
          local cellLbl = cell:CreateFontString(nil, "OVERLAY")
          cellLbl:SetFont(ns.Media.fontGui, 8)
          cellLbl:SetPoint("TOP", sw, "BOTTOM", 0, -4)
          cellLbl:SetSize(SWATCH_W, LABEL_H)
          cellLbl:SetWordWrap(true)
          cellLbl:SetJustifyH("CENTER")
          cellLbl:SetJustifyV("TOP")
          cellLbl:SetTextColor(0.8, 0.8, 0.8, 1)
          cellLbl:SetText(ELEM_LABELS[ek] or ek)

          -- Clic gauche ? ColorPickerFrame
          sw:SetScript("OnClick", function(_, btn)
            if btn == "LeftButton" then
              local c = Colors.GetForSpec(cd.key, spec.id, ek)
              local info = {}
              info.r          = c[1]
              info.g          = c[2]
              info.b          = c[3]
              info.opacity    = c[4] or 1
              info.hasOpacity = true
              info.swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = 1
                if ColorPickerFrame.GetColorAlpha then
                  na = ColorPickerFrame:GetColorAlpha()
                end
                swTex:SetColorTexture(nr, ng, nb, na)
                Colors.SetOverride(cd.key, spec.id, ek, {nr, ng, nb, na})
              end
              info.opacityFunc = info.swatchFunc
              info.cancelFunc  = function(prev)
                if prev then
                  local pr = prev.r or c[1]
                  local pg = prev.g or c[2]
                  local pb = prev.b or c[3]
                  local pa = prev.opacity or c[4] or 1
                  swTex:SetColorTexture(pr, pg, pb, pa)
                  Colors.SetOverride(cd.key, spec.id, ek, {pr, pg, pb, pa})
                end
              end
              ColorPickerFrame:SetupColorPickerAndShow(info)
            elseif btn == "RightButton" then
              -- Réinitialiser au dEfaut
              Colors.ResetOverride(cd.key, spec.id, ek)
              RefreshSwatch()
            end
          end)

          sw:SetScript("OnEnter", function(self)
            swBorder:SetColorTexture(1, 1, 1, 0.6)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(ELEM_LABELS[ek] or ek, 1, 1, 1)
            GameTooltip:AddLine(L["SETTINGS_TT_LEFT_CLICK_EDIT"], 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L["SETTINGS_TT_RIGHT_CLICK_RESET_DEFAULT"], 0.8, 0.8, 0.8)
            GameTooltip:Show()
          end)
          sw:SetScript("OnLeave", function(self)
            swBorder:SetColorTexture(unpack(ns.Theme.border))
            GameTooltip:Hide()
          end)

          col = col + 1
          if col >= cols then
            col = 0
            fy  = fy + ROW_STRIDE
          end
        end
        -- Fin de la dernière ligne (incomplète)
        if col > 0 then
          fy = fy + ROW_STRIDE
        end
        fy = fy + SPEC_GAP
      end

      cFrame:SetHeight(fy)
      sec.built = true
    end

    -- Toggle expand / collapse
    hHitbox:SetScript("OnClick", function()
      expanded[cd.key] = not expanded[cd.key]
      hHeader.text:SetText(((expanded[cd.key] and "- " or "+ ") .. cd.name):upper())
      if expanded[cd.key] then
        sec.BuildContent()
      end
      RebuildLayout()
    end)

    table.insert(classSections, sec)
  end

  -- Expansion par défaut : classe du joueur (seulement en mode personnalisé)
  -- -- les en-têtes ont déjà été créées repliées ("+ ") au moment du for
  -- ci-dessus (expanded[cd.key] pas encore renseigné) : on met donc aussi le
  -- libellé à jour ici pour la classe qui se retrouve dépliée par défaut.
  if playerClassKey and not GetUseClassDefaults() then
    expanded[playerClassKey] = true
    for _, sec in ipairs(classSections) do
      if sec.cd.key == playerClassKey then
        sec.headerBtn.text:SetText(("- " .. sec.cd.name):upper())
        sec.BuildContent()
        break
      end
    end
  end

  -- Appliquer l'état initial du mode (dim si "couleurs de classe par défaut")
  if GetUseClassDefaults() then
    for _, sec in ipairs(classSections) do
      sec.hitbox:EnableMouse(false)
      sec.headerBtn:SetAlpha(0.3)
    end
  end

  RebuildLayout()
end

-- Build.AFKMode : ecran AFK personnalise, cf. Modules/AFKMode.lua. Chaque
-- texte/blason est un "element" configurable
-- individuellement (ns.DB.afkMode.elements[cle]) : cocher son "afficher"
-- fait apparaitre une sous-section de reglages en bas de page (rebuild
-- complet via _invalidateCategory, cf. Modules AFKMode.ElemCfg pour la
-- lecture fusionnee Defaults+DB).
--
-- Tout ce qui suit (options, libelles, helpers Get/Set/Bind, sous-section
-- par element) est enferme dans un bloc do...end : ces ~15 locales
-- internes restent scopees a ce bloc et ne s'ajoutent jamais aux locales
-- de plus haut niveau du fichier. Build.AFKMode (assignee plus bas, cf.
-- table Build en tete de fichier) n'a pas besoin de forward-declaration
-- local ici -- c'est un champ de table, pas une locale.
do

local AFK_STYLE_OPTIONS_STD = {
  { value = "blizzard",     text = L["SETTINGS_AFK_STYLE_BLIZZARD"] },
  { value = "sltheme",      text = L["SETTINGS_AFK_STYLE_SLTHEME"] },
  { value = "releaf-flat",  text = L["SETTINGS_AFK_STYLE_RELEAFFLAT"] },
}
local AFK_STYLE_OPTIONS_CLASS = {
  { value = "sltheme",      text = L["SETTINGS_AFK_STYLE_SLTHEME"] },
  { value = "releaf-flat",  text = L["SETTINGS_AFK_STYLE_RELEAFFLAT"] },
}
local AFK_STYLE_OPTIONS_EXPANSION = {
  { value = "auto",         text = L["SETTINGS_AFK_STYLE_AUTO"] },
  { value = "blizzard",     text = L["SETTINGS_AFK_STYLE_BLIZZARD"] },
  { value = "sltheme",      text = L["SETTINGS_AFK_STYLE_SLTHEME"] },
  { value = "releaf-flat",  text = L["SETTINGS_AFK_STYLE_RELEAFFLAT"] },
}
local AFK_ANIM_TYPE_OPTIONS = {
  { value = "slideIn",   text = L["SETTINGS_AFK_ANIM_SLIDEIN"] },
  { value = "slideSide", text = L["SETTINGS_AFK_ANIM_SLIDESIDE"] },
  { value = "none",      text = L["SETTINGS_AFK_ANIM_NONE"] },
}
local AFK_MODEL_ANIM_KEYS = { "wave", "dance", "salute", "talk", "shy", "roar", "lean", "walk", "run", "battlestance", "random" }
local AFK_ANCHOR_OPTIONS = {
  { value = "TOPLEFT",     text = L["SETTINGS_ANCHOR_TOPLEFT"] },
  { value = "TOP",         text = L["SETTINGS_ANCHOR_TOP"] },
  { value = "TOPRIGHT",    text = L["SETTINGS_ANCHOR_TOPRIGHT"] },
  { value = "BOTTOMLEFT",  text = L["SETTINGS_ANCHOR_BOTTOMLEFT"] },
  { value = "BOTTOM",      text = L["SETTINGS_ANCHOR_BOTTOM"] },
  { value = "BOTTOMRIGHT", text = L["SETTINGS_ANCHOR_BOTTOMRIGHT"] },
}
local AFK_DATE_FORMAT_OPTIONS = {
  { value = "dayMonth",     text = L["SETTINGS_AFK_DATE_FORMAT_DAYMONTH"] },
  { value = "monthDay",     text = L["SETTINGS_AFK_DATE_FORMAT_MONTHDAY"] },
  { value = "weekdayFirst", text = L["SETTINGS_AFK_DATE_FORMAT_WEEKDAYFIRST"] },
}


-- Libelles + regroupement des elements pour les cases "informations
-- affichees" / "blasons & logos" (cf. Modules/AFKMode.lua:TEXT_ELEMENTS /
-- GRAPHIC_ELEMENTS pour la logique d'affichage correspondante).
local AFK_TEXT_LABELS = {
  { key = "timer",       label = L["SETTINGS_AFK_SHOW_TIMER"] },
  { key = "playerName",  label = L["SETTINGS_AFK_SHOW_NAME"] },
  { key = "playerClass", label = L["SETTINGS_AFK_SHOW_CLASS"] },
  { key = "playerLevel", label = L["SETTINGS_AFK_SHOW_LEVEL"] },
  { key = "guild",       label = L["SETTINGS_AFK_SHOW_GUILD"] },
  { key = "date",        label = L["SETTINGS_AFK_SHOW_DATE"] },
  { key = "time",        label = L["SETTINGS_AFK_SHOW_TIME"] },
  { key = "tips",        label = L["SETTINGS_AFK_SHOW_TIPS"] },
}
local AFK_GRAPHIC_LABELS = {
  { key = "crestClass",    label = L["SETTINGS_AFK_CREST_CLASS"],    styleOptions = AFK_STYLE_OPTIONS_CLASS },
  { key = "crestFaction",  label = L["SETTINGS_AFK_CREST_FACTION"],  styleOptions = AFK_STYLE_OPTIONS_STD },
  { key = "logoFaction",   label = L["SETTINGS_AFK_LOGO_FACTION"],   styleOptions = AFK_STYLE_OPTIONS_STD },
  { key = "crestRace",     label = L["SETTINGS_AFK_CREST_RACE"],     styleOptions = AFK_STYLE_OPTIONS_STD },
  { key = "logoExpansion", label = L["SETTINGS_AFK_LOGO_EXPANSION"], styleOptions = AFK_STYLE_OPTIONS_EXPANSION },
  { key = "aishLogo",      label = L["SETTINGS_AFK_LOGO_AISHUI"] }, -- pas de styleOptions : texture fixe, pas de dropdown de style
}

-- Lecture/ecriture d'un champ d'element (ns.DB.afkMode.elements[cle][champ])
-- -- DBGet/DBSet/Bind* ne gerent qu'un seul niveau de sous-cle (cf.
-- GetModKey/DBGet plus haut), insuffisant pour cette structure imbriquee.
local function AFKGetElem(key, field)
  local AM = ns.Modules and ns.Modules.AFKMode
  local ec = AM and AM.ElemCfg and AM.ElemCfg(key)
  return ec and ec[field]
end
local function AFKSetElem(key, field, value)
  if not ns.DB then ns.DB = {} end
  if not ns.DB.afkMode then ns.DB.afkMode = {} end
  if not ns.DB.afkMode.elements then ns.DB.afkMode.elements = {} end
  if not ns.DB.afkMode.elements[key] then
    local defCfg = ns.Defaults and ns.Defaults.afkMode and ns.Defaults.afkMode.elements and ns.Defaults.afkMode.elements[key]
    local copy = {}
    if defCfg then for k, v in pairs(defCfg) do copy[k] = v end end
    ns.DB.afkMode.elements[key] = copy
  end
  ns.DB.afkMode.elements[key][field] = value
  LiveApply("afkMode")
end
local function AFKBindElemDropdown(dd, key, field)
  local v = AFKGetElem(key, field)
  if v ~= nil then dd:SetValue(v) end
  dd.onChanged = function(val) AFKSetElem(key, field, val) end
end
local function AFKBindElemSlider(sl, key, field)
  local v = AFKGetElem(key, field)
  if v then sl:SetValue(v) end
  sl.onChanged = function(val) AFKSetElem(key, field, val) end
end
local function AFKBindElemColor(btn, key, field)
  local v = AFKGetElem(key, field)
  if v and type(v) == "table" then btn:SetColor(v[1], v[2], v[3], v[4]) end
  btn.onChanged = function(val) AFKSetElem(key, field, val) end
end
--- Checkbox generique (pas "enable" -- celui-la vit dans AFKBindElemEnable et
--- fait apparaitre/disparaitre toute la sous-section, donc rebuild complet).
local function AFKBindElemCheckbox(cb, key, field)
  cb:SetChecked(AFKGetElem(key, field) and true or false)
  cb.onChanged = function(val) AFKSetElem(key, field, val) end
end
-- _invalidateCategory("afkMode") force un rebuild complet de la page (seul
-- moyen de faire apparaitre/disparaitre des sous-sections avec ce systeme de
-- layout non reactif) -- mais SelectCategory() termine TOUJOURS par
-- scrollFrame:SetVerticalScroll(0), pensé pour un vrai changement d'onglet,
-- pas pour un rebuild sur place. Sans ce correctif, chaque clic (plier/
-- deplier une sous-section, cocher "afficher") faisait sauter le scroll tout
-- en haut de la page. On sauvegarde la position AVANT, on la restaure APRES
-- -- via un second C_Timer.After(0, ...), qui s'execute donc APRES celui
-- programme a l'interieur de _invalidateCategory (meme ordre de file que le
-- reste du fichier utilise deja pour ce genre d'enchainement).
local function AFKInvalidateKeepScroll()
  local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll()
  if _invalidateCategory then _invalidateCategory("afkMode") end
  if savedScroll then
    C_Timer.After(0, function()
      if scrollFrame then scrollFrame:SetVerticalScroll(savedScroll) end
    end)
  end
end

-- Case "afficher" d'un element : contrairement aux autres champs, un
-- changement ici fait apparaitre/disparaitre toute une sous-section plus
-- bas -> rebuild complet de la page (_invalidateCategory), pas juste LiveApply.
local function AFKBindElemEnable(cb, key)
  cb:SetChecked(AFKGetElem(key, "enable") and true or false)
  cb.onChanged = function(val)
    AFKSetElem(key, "enable", val)
    AFKInvalidateKeepScroll()
  end
end

-- Etat plie/deplie d'une sous-section de detail -- stocke comme un champ de
-- plus sur l'element (ns.DB.afkMode.elements[cle].collapsed), persiste entre
-- sessions comme le reste des reglages AFK. Toggle -> rebuild de page (meme
-- mecanisme que AFKBindElemEnable), la sous-section ne montrant plus ses
-- widgets une fois pliee ne peut pas se faire par simple Hide() sans laisser
-- un trou (ctx est un simple accumulateur de Y, pas un layout reactif).
local function AFKElemCollapsed(key)
  return AFKGetElem(key, "collapsed") and true or false
end
local function AFKToggleCollapsed(key)
  AFKSetElem(key, "collapsed", not AFKElemCollapsed(key))
  AFKInvalidateKeepScroll()
end

-- En-tete de sous-section pliable : reprend le header standard (point +
-- libelle + hairline, cf. SW.CreateSectionHeader) et superpose un bouton
-- invisible qui capte le clic (plier/deplier) et le survol (highlight),
-- plus une petite fleche "detrompeur" devant le libelle indiquant l'etat.
local function AFKCollapsibleHeader(container, W, label, key)
  local collapsed = AFKElemCollapsed(key)
  local header = SW.CreateSectionHeader(container, (collapsed and "+ " or "- ") .. label, W)

  local hitbox = CreateFrame("Button", nil, header)
  hitbox:SetAllPoints(header)
  hitbox:SetFrameLevel(header:GetFrameLevel() + 1)

  local hl = hitbox:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  hl:Hide()
  hitbox:SetScript("OnEnter", function() hl:Show() end)
  hitbox:SetScript("OnLeave", function() hl:Hide() end)
  hitbox:SetScript("OnClick", function() AFKToggleCollapsed(key) end)

  return header, collapsed
end

-- Decalage horizontal, purement visuel, pour qu'on distingue tout de suite
-- une section "normale" ("DETAILS DE L'ELEMENT") d'une sous-section d'element
-- depliee EN DESSOUS (demande utilisateur : c'est l'EN-TETE "+ NOM DU JOUEUR"
-- etc. qui doit etre decale par rapport a sa section mere -- pas seulement
-- son contenu par rapport a lui-meme). Deux paliers cumulatifs :
--   AFK_SECTION_INDENT : en-tete de la sous-section, decale par rapport a
--                        "DETAILS DE L'ELEMENT" (container, x=0)
--   AFK_DETAIL_INDENT  : contenu (font/couleur/position...), decale EN PLUS
--                        par rapport a l'en-tete de SA PROPRE sous-section
-- ctx:Add() ancre toujours a x=0 ; on pose donc les points nous-memes au
-- lieu de passer par ctx:Add pour le header et pour "detail".
local AFK_SECTION_INDENT = 26
local AFK_DETAIL_INDENT  = 20

-- Sous-section de reglages detailles pour un element affiche (Font, Couleur,
-- Position/Ancrage, X/Y, Taille) -- construite uniquement si l'element est
-- actif (cf. appels en bas de Build.AFKMode). Cliquer son en-tete la plie/
-- deplie (cf. AFKCollapsibleHeader). Les widgets vivent dans un sous-frame
-- "detail" dedie (layout imbrique via un ctx local) plutot que directement
-- sur `container` : ca permet (a) de le decaler vers la droite (indentation)
-- et (b) de l'animer en fondu a l'ouverture -- ctx:Add(detail) le traite
-- ensuite comme un bloc unique dont la hauteur (fixee par dctx:Finalize())
-- pousse normalement la suite de la page.
local function AFKBuildElementSection(container, ctx, W, key, label, isGraphic)
  ctx:Spacer(4)

  local headerW = W - AFK_SECTION_INDENT
  local header, collapsed = AFKCollapsibleHeader(container, headerW, label, key)
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT", container, "TOPLEFT", AFK_SECTION_INDENT, -ctx.y)
  header:Show()
  ctx.y = ctx.y + header:GetHeight() + 2
  table.insert(ctx.widgets, header)
  if collapsed then return end

  local detailIndent = AFK_SECTION_INDENT + AFK_DETAIL_INDENT
  local detailW = W - detailIndent
  local W2 = math.floor((detailW - 8) / 2)
  local W3 = math.floor((detailW - 16) / 3)

  local detail = CreateFrame("Frame", nil, container)
  detail:SetWidth(detailW)
  local dctx = NewLayout(detail)

  if not isGraphic then
    local ddFont = SW.CreateDropdown(detail, L["SETTINGS_FONT"], ns.GetFontList(), W2)
    AFKBindElemDropdown(ddFont, key, "font")
    local colBtn = SW.CreateColorButton(detail, L["SETTINGS_AFK_ELEMENT_COLOR"], W2)
    AFKBindElemColor(colBtn, key, "color")
    dctx:AddRow(8, ddFont, colBtn)

    if key ~= "tips" then
      local ddOutline = SW.CreateDropdown(detail, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), W2)
      AFKBindElemDropdown(ddOutline, key, "outlineStyle")
      dctx:Add(ddOutline)
    end

    -- Couleur de specialisation : generalise a TOUS les elements
    -- texte (auparavant reserve a playerName, toujours code en dur sur
    -- Couleurs > Cercle de Puissance) -- desormais un menu deroulant choisit
    -- QUEL element du module Couleurs utiliser, au lieu d'imposer une seule
    -- couleur du theme. Liste construite inline (IIFE, pas de local partagee
    -- au niveau du fichier) : le fichier est deja au plafond des 200 locales
    -- par chunk (LUA_WARNING deja rencontre) -- les locales d'une closure
    -- imbriquee ne comptent pas dans ce budget, contrairement a une fonction
    -- nommee au niveau fichier.
    local cbSpecColor = SW.CreateCheckbox(detail,
      L["SETTINGS_USE_SPEC_COLOR"], L["SETTINGS_USE_SPEC_COLOR_TT"], W2)
    AFKBindElemCheckbox(cbSpecColor, key, "useSpecColor")
    local ddSpecColor = SW.CreateDropdown(detail, L["SETTINGS_SPEC_COLOR_ELEMENT"], (function()
      local CLR = ns.Modules and ns.Modules.Colors
      if not (CLR and CLR.ELEMENT_KEYS) then return {} end
      local list = {}
      for _, k in ipairs(CLR.ELEMENT_KEYS) do
        list[#list + 1] = { value = k, text = (CLR.ELEMENT_LABELS and CLR.ELEMENT_LABELS[k]) or k }
      end
      return list
    end)(), W2)
    AFKBindElemDropdown(ddSpecColor, key, "specColorKey")
    dctx:AddRow(8, cbSpecColor, ddSpecColor)
  end

  local ddAnchor = SW.CreateDropdown(detail, L["SETTINGS_POSITION"], AFK_ANCHOR_OPTIONS, W3)
  AFKBindElemDropdown(ddAnchor, key, "anchor")
  local slX = SW.CreateSlider(detail, L["SETTINGS_OFFSET_X"], -400, 400, 1, W3)
  AFKBindElemSlider(slX, key, "x")
  local slY = SW.CreateSlider(detail, L["SETTINGS_OFFSET_Y"], -300, 300, 1, W3)
  AFKBindElemSlider(slY, key, "y")
  dctx:AddRow(8, ddAnchor, slX, slY)

  if isGraphic then
    local slW = SW.CreateSlider(detail, L["SETTINGS_AFK_ELEMENT_WIDTH"], 8, 200, 1, W2)
    AFKBindElemSlider(slW, key, "width")
    local slH = SW.CreateSlider(detail, L["SETTINGS_AFK_ELEMENT_HEIGHT"], 8, 200, 1, W2)
    AFKBindElemSlider(slH, key, "height")
    dctx:AddRow(8, slW, slH)
  else
    local slSize = SW.CreateSlider(detail, L["SETTINGS_AFK_TEXT_SIZE"], 8, 32, 1, W2)
    AFKBindElemSlider(slSize, key, "size")
    if key == "tips" then
      -- Largeur de retour a la ligne (pas une taille d'element comme pour
      -- les blasons) : controle ou le ScrollingMessageFrame des astuces
      -- retourne a la ligne, cf. Modules/AFKMode.lua (tipsFrame:SetWidth).
      local slLineWidth = SW.CreateSlider(detail, L["SETTINGS_AFK_TIPS_LINE_WIDTH"], 150, 900, 10, W2)
      AFKBindElemSlider(slLineWidth, key, "lineWidth")
      dctx:AddRow(8, slSize, slLineWidth)
      -- tipThrottle est un reglage global (afkMode.tipThrottle), pas propre
      -- a un element -> BindSlider generique, pas AFKBindElemSlider.
      local slThrottle = SW.CreateSlider(detail, L["SETTINGS_AFK_TIP_THROTTLE"], 4, 60, 1, W2)
      BindSlider(slThrottle, "afkMode", "tipThrottle")
      dctx:Add(slThrottle)
    elseif key == "date" then
      local ddFormat = SW.CreateDropdown(detail, L["SETTINGS_AFK_DATE_FORMAT"], AFK_DATE_FORMAT_OPTIONS, W2)
      AFKBindElemDropdown(ddFormat, key, "format")
      dctx:AddRow(8, slSize, ddFormat)
    else
      dctx:Add(slSize)
    end
  end
  dctx:Finalize()

  -- Pose manuelle (indentation) puis comptabilisation dans le ctx exterieur,
  -- equivalent a ctx:Add(detail) mais avec un decalage x != 0.
  detail:ClearAllPoints()
  detail:SetPoint("TOPLEFT", container, "TOPLEFT", detailIndent, -ctx.y)
  detail:Show()

  -- Ligne-guide verticale, entre l'en-tete de la sous-section (x =
  -- AFK_SECTION_INDENT) et son contenu (x = detailIndent) -- relie
  -- visuellement les deux paliers d'indentation.
  local guide = detail:CreateTexture(nil, "ARTWORK")
  guide:SetWidth(2)
  guide:SetPoint("TOPLEFT", detail, "TOPLEFT", -math.floor(AFK_DETAIL_INDENT / 2), 0)
  guide:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", -math.floor(AFK_DETAIL_INDENT / 2), 0)
  guide:SetColorTexture(0.776, 0.710, 0.471, 0.35) -- meme teinte que le point/hairline des en-tetes (or discret)

  ctx.y = ctx.y + detail:GetHeight() + 2
  table.insert(ctx.widgets, detail)

  -- Fondu a l'ouverture : la sous-section est reconstruite a chaque depli
  -- (rebuild de page), une anim douce vaut mieux qu'un pop-in instantane.
  detail:SetAlpha(0)
  local fadeGroup = detail:CreateAnimationGroup()
  local fade = fadeGroup:CreateAnimation("Alpha")
  fade:SetFromAlpha(0)
  fade:SetToAlpha(1)
  fade:SetDuration(0.15)
  fade:SetSmoothing("OUT")
  fadeGroup:SetScript("OnFinished", function() detail:SetAlpha(1) end)
  fadeGroup:Play()
end

Build.AFKMode = function(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local W2 = math.floor((W - 8) / 2)
  local W3 = math.floor((W - 16) / 3)

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_AFK_MODE"], W))
  local cbEnable = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_AFK_ENABLE"], L["SETTINGS_AFK_ENABLE_TT"], W))
  BindCheckbox(cbEnable, "afkMode", "enabled")
  -- Pas de bouton "Tester" : l'apercu se lance/s'arrete tout seul en entrant/
  -- sortant de cette section (cf. UI/SettingsPanel.lua:MainFrame:SelectCategory
  -- et le hook OnShow, catId == "afkMode" -> AM.SetPreview(true)).

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_PANELS"], W))

  local ddAnim = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_AFK_ANIM_TYPE"], AFK_ANIM_TYPE_OPTIONS, W2))
  BindDropdown(ddAnim, "afkMode", "animType")

  local cbBounce = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_AFK_ANIM_BOUNCE"], nil, W2))
  BindCheckbox(cbBounce, "afkMode", "animBounce")

  local slAnimTime = SW.CreateSlider(container, L["SETTINGS_AFK_ANIM_TIME"], 0, 2, 0.05, W3)
  BindSlider(slAnimTime, "afkMode", "animTime")
  local slTopH = SW.CreateSlider(container, L["SETTINGS_AFK_PANEL_TOP_HEIGHT"], 30, 200, 1, W3)
  BindSlider(slTopH, "afkMode", "panelTopHeight")
  local slBottomH = SW.CreateSlider(container, L["SETTINGS_AFK_PANEL_BOTTOM_HEIGHT"], 30, 240, 1, W3)
  BindSlider(slBottomH, "afkMode", "panelBottomHeight")
  ctx:AddRow(8, slAnimTime, slTopH, slBottomH)

  local colBg = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_AFK_PANEL_COLOR"], W))
  BindColorButton(colBg, "afkMode", "panelBgColor")

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_MODEL"], W))

  local cbModel = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_AFK_MODEL_ENABLE"], nil, W2))
  BindCheckbox(cbModel, "afkMode", "modelEnabled")

  local modelAnimOptions = {}
  for _, key in ipairs(AFK_MODEL_ANIM_KEYS) do
    table.insert(modelAnimOptions, { value = key, text = L["SETTINGS_AFK_MODEL_ANIM_" .. key:upper()] })
  end
  local ddModelAnim = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_AFK_MODEL_ANIM"], modelAnimOptions, W2))
  BindDropdown(ddModelAnim, "afkMode", "modelAnim")

  local slModelDist = SW.CreateSlider(container, L["SETTINGS_AFK_MODEL_DISTANCE"], 1, 10, 0.1, W3)
  BindSlider(slModelDist, "afkMode", "modelDistance")
  local slModelRot = SW.CreateSlider(container, L["SETTINGS_AFK_MODEL_ROTATION"], -6.28, 6.28, 0.1, W3)
  BindSlider(slModelRot, "afkMode", "modelRotation")
  ctx:AddRow(8, slModelDist, slModelRot)

  local slModelX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -400, 400, 1, W3)
  BindSlider(slModelX, "afkMode", "modelXOffset")
  local slModelY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -300, 300, 1, W3)
  BindSlider(slModelY, "afkMode", "modelYOffset")
  ctx:AddRow(8, slModelX, slModelY)

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_TEXTS"], W))

  for i = 1, #AFK_TEXT_LABELS, 3 do
    local a, b, c = AFK_TEXT_LABELS[i], AFK_TEXT_LABELS[i + 1], AFK_TEXT_LABELS[i + 2]
    local cbA = SW.CreateCheckbox(container, a.label, nil, W3)
    AFKBindElemEnable(cbA, a.key)
    if b then
      local cbB = SW.CreateCheckbox(container, b.label, nil, W3)
      AFKBindElemEnable(cbB, b.key)
      if c then
        local cbC = SW.CreateCheckbox(container, c.label, nil, W3)
        AFKBindElemEnable(cbC, c.key)
        ctx:AddRow(8, cbA, cbB, cbC)
      else
        ctx:AddRow(8, cbA, cbB)
      end
    else
      ctx:Add(cbA)
    end
  end

  local cbCountdown = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_AFK_TIMER_COUNTDOWN"], L["SETTINGS_AFK_TIMER_COUNTDOWN_TT"], W2))
  BindCheckbox(cbCountdown, "afkMode", "timerCountdown")
  -- "Intervalle astuces" (tipThrottle) vit maintenant dans la sous-section
  -- de detail de l'element "tips" (cf. AFKBuildElementSection, a cote de
  -- "Largeur de ligne") -- plus logique la-bas qu'isole ici.

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_GRAPHICS"], W))

  for _, g in ipairs(AFK_GRAPHIC_LABELS) do
    if g.styleOptions then
      local cb = SW.CreateCheckbox(container, g.label, nil, W2)
      AFKBindElemEnable(cb, g.key)
      local dd = SW.CreateDropdown(container, nil, g.styleOptions, W2)
      AFKBindElemDropdown(dd, g.key, "style")
      ctx:AddRow(8, cb, dd)
    else
      -- Pas de styleOptions : texture fixe (ex. logo AishUI), pas de dropdown de style
      local cb = ctx:Add(SW.CreateCheckbox(container, g.label, nil, W))
      AFKBindElemEnable(cb, g.key)
    end
  end

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_MISC"], W))

  local cbCam  = SW.CreateCheckbox(container, L["SETTINGS_AFK_CAMERA_SPIN"], nil, W3)
  local cbChat = SW.CreateCheckbox(container, L["SETTINGS_AFK_CHAT_SHOW"], nil, W3)
  local cbExit = SW.CreateCheckbox(container, L["SETTINGS_AFK_EXIT_KEYPRESS"], L["SETTINGS_AFK_EXIT_KEYPRESS_TT"], W3)
  BindCheckbox(cbCam, "afkMode", "cameraSpin")
  BindCheckbox(cbChat, "afkMode", "chatShow")
  BindCheckbox(cbExit, "afkMode", "exitOnKeypress")
  ctx:AddRow(8, cbCam, cbChat, cbExit)

  local colAccent = SW.CreateColorButton(container, L["SETTINGS_AFK_ACCENT_COLOR"], W2)
  BindColorButton(colAccent, "afkMode", "accentColor")
  local cbTheme = SW.CreateCheckbox(container, L["SETTINGS_AFK_USE_THEME_COLORS"], L["SETTINGS_AFK_USE_THEME_COLORS_TT"], W2)
  BindCheckbox(cbTheme, "afkMode", "useThemeColors")
  ctx:AddRow(8, colAccent, cbTheme)
  -- Element du module Couleurs utilise par la couleur d'accent (date, ":" de
  -- l'heure, chevrons de guilde) quand cbTheme est coche -- meme dropdown que
  -- pour les elements individuels, defaut "powertext" (comportement d'avant
  -- cette fonctionnalite, inchange si jamais touche).
  local ddThemeColor = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_SPEC_COLOR_ELEMENT"], (function()
    local CLR = ns.Modules and ns.Modules.Colors
    if not (CLR and CLR.ELEMENT_KEYS) then return {} end
    local list = {}
    for _, k in ipairs(CLR.ELEMENT_KEYS) do
      list[#list + 1] = { value = k, text = (CLR.ELEMENT_LABELS and CLR.ELEMENT_LABELS[k]) or k }
    end
    return list
  end)(), W2))
  BindDropdown(ddThemeColor, "afkMode", "themeColorKey")

  -- Sous-sections dynamiques : une par element actuellement affiche
  -- (rebuild complet de la page a chaque bascule d'une case "afficher",
  -- cf. AFKBindElemEnable -> _invalidateCategory).
  local hasDetail = false
  for _, t in ipairs(AFK_TEXT_LABELS) do
    if AFKGetElem(t.key, "enable") then
      if not hasDetail then
        ctx:Spacer(10)
        ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_ELEMENT_DETAILS"], W))
        hasDetail = true
      end
      AFKBuildElementSection(container, ctx, W, t.key, t.label, false)
    end
  end
  for _, g in ipairs(AFK_GRAPHIC_LABELS) do
    if AFKGetElem(g.key, "enable") then
      if not hasDetail then
        ctx:Spacer(10)
        ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_AFK_ELEMENT_DETAILS"], W))
        hasDetail = true
      end
      AFKBuildElementSection(container, ctx, W, g.key, g.label, true)
    end
  end

  ctx:Finalize()
end

end -- do (bloc de portee pour les locales AFK Mode, cf. commentaire au-dessus de Build.AFKMode)

-- Build.Skyriding : port du WeakAura [SKYRIDING] - FIXE
function Build.Skyriding(container)
  local ctx = NewLayout(container)
  local W   = CONTENT_W
  local SR  = ns.Modules and ns.Modules.Skyriding

  local function SRGet(prop)
    local db  = ns.DB       and ns.DB.skyriding
    local def = ns.Defaults and ns.Defaults.skyriding
    if db  and db[prop]  ~= nil then return db[prop]  end
    if def and def[prop] ~= nil then return def[prop] end
  end
  local function SRSet(prop, val)
    if not ns.DB           then ns.DB = {} end
    if not ns.DB.skyriding then ns.DB.skyriding = {} end
    ns.DB.skyriding[prop] = val
    if SR and SR.ApplySettings then SR.ApplySettings() end
  end

  -- -- Activer / désactiver ------------------------------------------------
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SKYRIDING_GENERAL"], W))

  local cbEnable = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SR_ENABLE"],
    L["SETTINGS_SR_ENABLE_TT"], W))
  cbEnable.onChanged = function(val)
    SRSet("enabled", val)
    -- SRSet est generique et ne passe pas par LiveApply/_invalidateCategory.
    if _invalidateCategory then _invalidateCategory("modulesOverview") end
  end
  cbEnable:SetChecked(SRGet("enabled") ~= false)

  local cbHideLanding = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SR_HIDE_ON_LANDING"],
    L["SETTINGS_SR_HIDE_ON_LANDING_TT"], W))
  cbHideLanding.onChanged = function(val) SRSet("hideAtLanding", val) end
  cbHideLanding:SetChecked(SRGet("hideAtLanding") == true)

  -- -- Modules à masquer pendant le vol ------------------------------------
  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SR_HIDE_DURING_FLIGHT"], W))

  -- Helper : crée une checkbox liée à un toggle skyriding et l'applique en live
  local function MakeHideToggle(label, tooltip, key, applyFn)
    local cb = ctx:Add(SW.CreateCheckbox(container, label, tooltip, W))
    cb.onChanged = function(val)
      SRSet(key, val)
      if SR and SR.IsActive and SR.IsActive() then applyFn(val) end
    end
    cb:SetChecked(SRGet(key) ~= false)
  end

  local RC2   = ns.Modules and ns.Modules.ResourceCircle
  local HC2   = ns.Modules and ns.Modules.HealthCircle
  local OCRC2 = ns.Modules and ns.Modules.OutOfCombatResourceCircle
  local UB2   = ns.Modules and ns.Modules.UnitBars
  local PB2   = ns.Modules and ns.Modules.PriorityBar
  local RH2   = ns.Modules and ns.Modules.RotationHelper

  MakeHideToggle(
    L["SETTINGS_SR_HIDE_RC"],
    L["SETTINGS_SR_HIDE_RC_TT"],
    "hideResourceCircle",
    function(val)
      if RC2 then RC2.ResetVisibility(); RC2.UpdateVisibility() end
    end)

  MakeHideToggle(
    L["SETTINGS_SR_HIDE_HC"],
    L["SETTINGS_SR_HIDE_HC_TT"],
    "hideHealthCircle",
    function(val)
      if HC2 then HC2.ResetVisibility(); HC2.UpdateVisibility() end
    end)

  MakeHideToggle(
    L["SETTINGS_SR_HIDE_OCRC"],
    L["SETTINGS_SR_HIDE_OCRC_TT"],
    "hideOOCResourceCircle",
    function(val)
      if OCRC2 then OCRC2.ResetVisibility(); OCRC2.UpdateVisibility() end
    end)

  MakeHideToggle(
    L["SETTINGS_SR_HIDE_UB"],
    L["SETTINGS_SR_HIDE_UB_TT"],
    "hideUnitBars",
    function(val)
      if UB2 then UB2.SetSkyridingActive(val) end
    end)

  MakeHideToggle(
    L["SETTINGS_SR_HIDE_PB"],
    L["SETTINGS_SR_HIDE_PB_TT"],
    "hidePriorityBar",
    function(val)
      if PB2 then PB2.SetSkyridingActive(val) end
    end)

  MakeHideToggle(
    L["SETTINGS_SR_HIDE_RH"],
    L["SETTINGS_SR_HIDE_RH_TT"],
    "hideRotationHelper",
    function(val)
      if val and RH2 then RH2.SetSkyridingActive(true) end
      -- Désactivation : les icônes réapparaissent au prochain tick de polling
    end)

  -- -- Position X/Y --------------------------------------------------------
  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION_SCALE"], W))

  local srHalfW = math.floor((W - 8) / 2)
  local slSRPosX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -200, 200, 1, srHalfW)
  slSRPosX:SetValue(SRGet("x") or 0)
  slSRPosX.onChanged = function(v) SRSet("x", v) end
  local slSRPosY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -200, 200, 1, srHalfW)
  slSRPosY:SetValue(SRGet("y") or 0)
  slSRPosY.onChanged = function(v) SRSet("y", v) end
  ctx:AddRow(8, slSRPosX, slSRPosY)
  -- Exposes globalement (remplace les anciens EditBox nommes
  -- AishCoreSRXEditBox/YEditBox) : Modules/Skyriding.lua met ces sliders a
  -- jour apres un drag-and-drop du cercle directement en jeu.
  _G["AishCoreSRPosXSlider"] = slSRPosX
  _G["AishCoreSRPosYSlider"] = slSRPosY

  ctx:Spacer(4)
  local scaleSlider = SW.CreateSlider(container, L["SETTINGS_SR_GLOBAL_SCALE"], 0.4, 1.5, 0.05, W)
  scaleSlider.onChanged = function(val) SRSet("scale", val) end
  scaleSlider:SetValue(SRGet("scale") or 0.8)
  ctx:Add(scaleSlider)

  -- -- Déplacer le HUD -----------------------------------------------------
  ctx:Spacer(4)
  local srDragActive = false

  local srDragBtn = CreateFrame("Button", nil, container)
  srDragBtn:SetSize(W - 4, 26)

  local _srBg = srDragBtn:CreateTexture(nil, "BACKGROUND")
  _srBg:SetAllPoints()
  _srBg:SetColorTexture(0.10, 0.10, 0.13, 1)

  local _srBorder = srDragBtn:CreateTexture(nil, "BORDER")
  _srBorder:SetPoint("TOPLEFT",     srDragBtn, "TOPLEFT",     -1,  1)
  _srBorder:SetPoint("BOTTOMRIGHT", srDragBtn, "BOTTOMRIGHT",  1, -1)
  _srBorder:SetColorTexture(unpack(ns.Theme.border))

  local _srLabel = srDragBtn:CreateFontString(nil, "OVERLAY")
  _srLabel:SetFont(ns.Media.fontGui, 11)
  _srLabel:SetPoint("CENTER")
  _srLabel:SetTextColor(unpack(ns.Theme.textNormal))
  _srLabel:SetText(L["UI_MOVE_DRAG_DROP"])

  local function SetSRDragBtnState(active)
    if active then
      _srBg:SetColorTexture(0.05, 0.18, 0.08, 1)
      _srLabel:SetTextColor(0.3, 1.0, 0.3, 1)
      _srLabel:SetText(L["SETTINGS_SR_DRAG_HINT"])
    else
      _srBg:SetColorTexture(0.10, 0.10, 0.13, 1)
      _srLabel:SetTextColor(unpack(ns.Theme.textNormal))
      _srLabel:SetText(L["UI_MOVE_DRAG_DROP"])
    end
  end

  srDragBtn:SetScript("OnEnter", function()
    if not srDragActive then
      _srBg:SetColorTexture(0.16, 0.15, 0.20, 1)
      _srLabel:SetTextColor(unpack(ns.Theme.textHighlight))
    end
  end)
  srDragBtn:SetScript("OnLeave", function()
    SetSRDragBtnState(srDragActive)
  end)
  srDragBtn:SetScript("OnClick", function()
    srDragActive = not srDragActive
    SetSRDragBtnState(srDragActive)
    if SR and SR.SetLayoutMode then
      SR.SetLayoutMode(srDragActive)
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(srDragBtn)

  local hint = container:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 9)
  hint:SetTextColor(0.65, 0.65, 0.65, 1)
  hint:SetText(L["SETTINGS_SR_DRAG_HINT_LONG"])
  hint:SetJustifyH("LEFT")
  hint:SetSize(W - 10, 22)
  ctx:Add(hint)

  -- -- Taille des cercles --------------------------------------------------
  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SR_CIRCLE_SIZES"], W))

  local _srSL2 = math.floor((W - 8) / 2)
  local _srSL3 = math.floor((W - 16) / 3)
  local slBg = SW.CreateSlider(container, L["SETTINGS_SR_BG"], 40, 250, 1, _srSL3)
  slBg.onChanged = function(val) SRSet("bgSize", val) end
  slBg:SetValue(SRGet("bgSize") or 120)
  local slSpeed = SW.CreateSlider(container, L["SETTINGS_SR_SPEED_CIRCLE"], 40, 250, 1, _srSL3)
  slSpeed.onChanged = function(val) SRSet("speedSize", val) end
  slSpeed:SetValue(SRGet("speedSize") or 110)
  local slM1 = SW.CreateSlider(container, L["SETTINGS_SR_MASK_1"], 20, 240, 1, _srSL3)
  slM1.onChanged = function(val) SRSet("mask1Size", val) end
  slM1:SetValue(SRGet("mask1Size") or 102)
  ctx:AddRow(8, slBg, slSpeed, slM1)

  local slAsc = SW.CreateSlider(container, L["SETTINGS_SR_ASCENT_CIRCLE"], 20, 240, 1, _srSL3)
  slAsc.onChanged = function(val) SRSet("ascentSize", val) end
  slAsc:SetValue(SRGet("ascentSize") or 98)
  local slM2 = SW.CreateSlider(container, L["SETTINGS_SR_MASK_2"], 10, 200, 1, _srSL3)
  slM2.onChanged = function(val) SRSet("mask2Size", val) end
  slM2:SetValue(SRGet("mask2Size") or 85)
  local slOrb = SW.CreateSlider(container, L["SETTINGS_SR_ORB_SIZE"], 4, 60, 1, _srSL3)
  slOrb.onChanged = function(val) SRSet("orbSize", val) end
  slOrb:SetValue(SRGet("orbSize") or 19)
  ctx:AddRow(8, slAsc, slM2, slOrb)

  local slOrbRad = SW.CreateSlider(container, L["SETTINGS_SR_ORB_RADIUS"], 10, 200, 1, _srSL3)
  slOrbRad.onChanged = function(val) SRSet("orbRadius", val) end
  slOrbRad:SetValue(SRGet("orbRadius") or 65)
  local slOrbStart = SW.CreateSlider(container, L["SETTINGS_SR_ORB_START_ANGLE"], 0, 359, 1, _srSL3)
  slOrbStart.onChanged = function(val) SRSet("orbStartAngle", val) end
  slOrbStart:SetValue(SRGet("orbStartAngle") or 210)
  local slOrbSpacing = SW.CreateSlider(container, L["SETTINGS_SR_ORB_SPACING"], 1, 90, 1, _srSL3)
  slOrbSpacing.onChanged = function(val) SRSet("orbSpacing", val) end
  slOrbSpacing:SetValue(SRGet("orbSpacing") or 24)
  ctx:AddRow(8, slOrbRad, slOrbStart, slOrbSpacing)

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SR_SECOND_WIND"], W))

  local slDotSz = SW.CreateSlider(container, L["SETTINGS_SR_DOT_SIZE"], 1, 20, 1, _srSL3)
  slDotSz.onChanged = function(val) SRSet("dotSize", val) end
  slDotSz:SetValue(SRGet("dotSize") or 3)
  local slDotX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -80, 80, 1, _srSL3)
  slDotX.onChanged = function(val) SRSet("dotOffsetX", val) end
  slDotX:SetValue(SRGet("dotOffsetX") or 0)
  local slDotY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -80, 80, 1, _srSL3)
  slDotY.onChanged = function(val) SRSet("dotOffsetY", val) end
  slDotY:SetValue(SRGet("dotOffsetY") or -12)
  ctx:AddRow(8, slDotSz, slDotX, slDotY)

  -- -- Texte ---------------------------------------------------------------
  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SR_SPEED_TEXT"], W))

  local slTxt = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 30, 1, W))
  slTxt.onChanged = function(val) SRSet("textSize", val) end
  slTxt:SetValue(SRGet("textSize") or 14)

  local ddSRFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_SR_SPEED_FONT"], ns.GetFontList(), 220))
  do
    local _v = SRGet("font"); if _v then ddSRFont:SetValue(_v) end
    ddSRFont.onChanged = function(val) SRSet("font", val) end
  end

  -- -- Couleurs ------------------------------------------------------------
  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_COLORS"], W))

  -- Trois boutons exclusifs : Spé / Monture / Custom -- Monture est un
  -- reglage reserve (cf. Core.lua:ns.HasHeroicFeatures), masque tant que le
  -- champ racine SavedVariables correspondant n'est pas present.
  local cbCustom, cbSpec, cbMount
  local function SetColorMode(mode)
    SRSet("colorMode", mode)
    cbCustom:SetChecked(mode == "custom")
    cbSpec:SetChecked(mode == "spec")
    if cbMount then cbMount:SetChecked(mode == "mount") end
  end

  cbSpec = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SR_COLOR_SPEC"],
    L["SETTINGS_SR_COLOR_SPEC_TT"], W))
  cbSpec.onChanged = function(val) if val then SetColorMode("spec") end end
  cbSpec:SetChecked((SRGet("colorMode") or "custom") == "spec")

  if ns.HasHeroicFeatures and ns.HasHeroicFeatures() then
    cbMount = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_SR_COLOR_MOUNT"],
      L["SETTINGS_SR_COLOR_MOUNT_TT"], W))
    cbMount.onChanged = function(val) if val then SetColorMode("mount") end end
    cbMount:SetChecked((SRGet("colorMode") or "custom") == "mount")
  end

  cbCustom = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SR_COLOR_CUSTOM"],
    L["SETTINGS_SR_COLOR_CUSTOM_TT"], W))
  cbCustom.onChanged = function(val) if val then SetColorMode("custom") end end
  cbCustom:SetChecked((SRGet("colorMode") or "custom") == "custom")

  ctx:Spacer(4)
  local colNoGlow = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_SR_COLOR_NO_BUFF"], W))
  do
    local v = SRGet("colorNoGlow") or { 0.45, 0.45, 0.45, 1 }
    colNoGlow:SetColor(v[1], v[2], v[3], v[4] or 1)
    colNoGlow.onChanged = function(val) SRSet("colorNoGlow", val) end
  end

  local colGlow = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_SR_COLOR_WITH_BUFF"], W))
  do
    local v = SRGet("colorGlow") or { 0, 0.8824, 0.5373, 1 }
    colGlow:SetColor(v[1], v[2], v[3], v[4] or 1)
    colGlow.onChanged = function(val) SRSet("colorGlow", val) end
  end

  ctx:Spacer()
end

-- BUILD : Visibilité (Global) – transparence d'éléments tiers (ElvUI...)
function Build.Visibility(container)
  local ctx = NewLayout(container)
  local W   = CONTENT_W
  local SL_W2 = math.floor((W - 8) / 2)

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY_ELVUI_BUFFS"], W))

  local cbEnable = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_VIS_ELVUI_BUFFS_ENABLE"],
    L["SETTINGS_VIS_ELVUI_BUFFS_ENABLE_TT"], W))
  BindCheckbox(cbEnable, "visibility", "elvuiBuffsEnabled")

  local slOoc = SW.CreateSlider(container, L["SETTINGS_VIS_ELVUI_BUFFS_OOC_ALPHA"], 0, 1, 0.05, SL_W2)
  BindSlider(slOoc, "visibility", "elvuiBuffsOocAlpha")
  local slCombat = SW.CreateSlider(container, L["SETTINGS_VIS_ELVUI_BUFFS_COMBAT_ALPHA"], 0, 1, 0.05, SL_W2)
  BindSlider(slCombat, "visibility", "elvuiBuffsCombatAlpha")
  ctx:AddRow(8, slOoc, slCombat)

  local cbHover = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_VIS_ELVUI_BUFFS_HOVER"],
    L["SETTINGS_VIS_ELVUI_BUFFS_HOVER_TT"], W))
  BindCheckbox(cbHover, "visibility", "elvuiBuffsHoverReveal")

  ctx:Spacer()
  ctx:Finalize()
end

-- BUILD : Profils  –  helpers popup

-- Popup export : grand bloc de texte scrollable
local _exportPopup
local function ShowExportPopup(text)
  if not _exportPopup then
    local f = CreateFrame("Frame", "AishCoreExportPopup", UIParent, "BackdropTemplate")
    f:SetSize(640, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    -- Fond solide opaque pour éviter que les éléments arrière-plan ne transparaissent
    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    solidBg:SetColorTexture(0, 0, 0, 1)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets   = { left=11, right=12, top=12, bottom=11 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.98)

    local titleLbl = f:CreateFontString(nil, "OVERLAY")
    titleLbl:SetFont(ns.Media.fontGui, 13)
    titleLbl:SetTextColor(1, 0.88, 0.3)
    titleLbl:SetText(L["SETTINGS_EXPORT_PROFILE_TITLE"])
    titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont(ns.Media.fontGui, 9)
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText(L["SETTINGS_SELECT_COPY_HINT"])
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -36)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     14, -58)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 46)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetFont(ns.Media.fontGui, 9, "")
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    sf:SetScrollChild(eb)
    eb:SetWidth(sf:GetWidth())
    f._eb = eb

    local doneBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    doneBtn:SetSize(130, 26)
    doneBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    doneBtn:SetText(L["SETTINGS_CLOSE"])
    doneBtn:SetScript("OnClick", function() f:Hide() end)

    _exportPopup = f
  end
  _exportPopup._eb:SetText(text)
  _exportPopup._eb:HighlightText()
  _exportPopup:Show()
  _exportPopup._eb:SetFocus()
end

-- Popup saisie de nom (créer profil, etc.)
local _namePopup
local function ShowNamePopup(title, onConfirm)
  if not _namePopup then
    local f = CreateFrame("Frame", "AishCoreNamePopup", UIParent, "BackdropTemplate")
    f:SetSize(340, 130)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets   = { left=11, right=12, top=12, bottom=11 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.98)

    local titleLbl = f:CreateFontString(nil, "OVERLAY")
    titleLbl:SetFont(ns.Media.fontGui, 12)
    titleLbl:SetTextColor(1, 0.88, 0.3)
    titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    f._titleLbl = titleLbl

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    SW.StyleEditBox(eb)
    eb:SetSize(300, 24)
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -44)
    eb:SetAutoFocus(true)
    eb:SetMaxLetters(48)
    eb:SetFont(ns.Media.fontGui, 11, "")
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function()
      if f._onConfirm then f._onConfirm(eb:GetText()) end
      f:Hide()
    end)
    f._eb = eb

    local confirmBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    confirmBtn:SetSize(130, 26)
    confirmBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    confirmBtn:SetText(L["SETTINGS_CONFIRM"])
    confirmBtn:SetScript("OnClick", function()
      if f._onConfirm then f._onConfirm(f._eb:GetText()) end
      f:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    cancelBtn:SetSize(130, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    cancelBtn:SetText(L["SETTINGS_CANCEL"])
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    _namePopup = f
  end
  _namePopup._titleLbl:SetText(title)
  _namePopup._eb:SetText("")
  _namePopup._onConfirm = onConfirm
  _namePopup:Show()
  _namePopup._eb:SetFocus()
end

-- Popup import : champ nom + grande zone de collage
local _importPopup
local function ShowImportPopup(onConfirm)
  if not _importPopup then
    local PW, PH = 640, 480
    local f = CreateFrame("Frame", "AishCoreImportPopup", UIParent, "BackdropTemplate")
    f:SetSize(PW, PH)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets   = { left=11, right=12, top=12, bottom=11 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.98)

    local titleLbl = f:CreateFontString(nil, "OVERLAY")
    titleLbl:SetFont(ns.Media.fontGui, 13)
    titleLbl:SetTextColor(0.5, 0.8, 1)
    titleLbl:SetText(L["SETTINGS_IMPORT_PROFILE_TITLE"])
    titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Champ nom
    local nameLbl = f:CreateFontString(nil, "OVERLAY")
    nameLbl:SetFont(ns.Media.fontGui, 10)
    nameLbl:SetTextColor(0.7, 0.7, 0.7)
    nameLbl:SetText(L["SETTINGS_NEW_PROFILE_NAME"])
    nameLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -42)

    local nameEB = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    SW.StyleEditBox(nameEB)
    nameEB:SetSize(300, 24)
    nameEB:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -62)
    nameEB:SetAutoFocus(false)
    nameEB:SetMaxLetters(48)
    nameEB:SetFont(ns.Media.fontGui, 11, "")
    nameEB:SetScript("OnEscapePressed", function() f:Hide() end)
    f._nameEB = nameEB

    -- Zone de collage
    local pasteLbl = f:CreateFontString(nil, "OVERLAY")
    pasteLbl:SetFont(ns.Media.fontGui, 10)
    pasteLbl:SetTextColor(0.7, 0.7, 0.7)
    pasteLbl:SetText(L["SETTINGS_PASTE_PROFILE_STRING"])
    pasteLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -96)

    -- Fond noir visible derrière la zone de collage
    local pasteArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    pasteArea:SetPoint("TOPLEFT",     f, "TOPLEFT",      14, -114)
    pasteArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14,  52)
    pasteArea:SetBackdrop({
      bgFile  = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 10,
      insets   = { left=3, right=3, top=3, bottom=3 },
    })
    pasteArea:SetBackdropColor(0.03, 0.03, 0.03, 1)
    pasteArea:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    -- ScrollFrame + EditBox à l'intérieur du fond
    local sf = CreateFrame("ScrollFrame", nil, pasteArea, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     pasteArea, "TOPLEFT",      4,  -4)
    sf:SetPoint("BOTTOMRIGHT", pasteArea, "BOTTOMRIGHT", -22,  4)

    -- Largeur fixe calculée : PW - marges gauche/droite - scrollbar
    local ebW = PW - 14 - 14 - 22 - 8  -- ˜ 582

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetSize(ebW, 400)   -- hauteur généreuse pour le contenu
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetFont(ns.Media.fontGui, 9, "")
    eb:SetTextInsets(4, 4, 4, 4)
    eb:SetTextColor(0.9, 0.9, 0.9)
    eb:EnableMouse(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f._eb = eb

    -- Clic sur la zone de fond ? focus l'EditBox
    pasteArea:EnableMouse(true)
    pasteArea:SetScript("OnMouseDown", function() eb:SetFocus() end)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)
    eb:SetScript("OnMouseDown", function(self) self:SetFocus() end)

    local importBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    importBtn:SetSize(160, 26)
    importBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    importBtn:SetText(L["SETTINGS_IMPORT"])
    importBtn:SetScript("OnClick", function()
      local name = f._nameEB:GetText() or ""
      local str  = f._eb:GetText() or ""
      print("|cff00b0ff[AishCore Import DBG]|r nom='" .. name .. "' strLen=" .. #str)
      if not f._onConfirm then
        print("|cffff4444[AishCore Import DBG] _onConfirm est nil !|r")
        f:Hide(); return
      end
      f:Hide()
      f._onConfirm(name, str)
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    cancelBtn:SetSize(130, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    cancelBtn:SetText(L["SETTINGS_CANCEL"])
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    _importPopup = f
  end
  _importPopup._nameEB:SetText("")
  _importPopup._eb:SetText("")
  _importPopup._onConfirm = onConfirm
  _importPopup:Show()
  _importPopup._nameEB:SetFocus()
end

-- Forward-déclarations : doivent être visibles par Build.Profiles ET par les
-- SetScripts définis plus bas (SelectCategory, OnSizeChanged, etc.).
local categoryContainers = {}
local activeCategory     = nil
-- Définition de _invalidateCategory (forward-déclarée plus haut pour Build.ResourceCircle etc.)
_invalidateCategory = function(catId)
  if not categoryContainers or not categoryContainers[catId] then return end
  categoryContainers[catId].frame:Hide()
  categoryContainers[catId] = nil
  if activeCategory == catId then
    local prev = catId
    activeCategory = nil
    C_Timer.After(0, function() MainFrame:SelectCategory(prev) end)
  end
end
-- Expose pour un refresh externe (ex: Colors.lua sur PLAYER_SPECIALIZATION_CHANGED) :
-- un categoryContainer construit une fois reste en cache pour toute la session --
-- les sections dont le contenu depend de ns._specID au moment du build (dotsLabel,
-- arc de stagger, _arcSpec...) ne se remettent donc JAMAIS a jour toutes seules
-- apres un changement de spe, contrairement aux checkboxes qui appellent deja
-- _invalidateCategory dans leur propre onChanged (ex: holyPowerAllSpecs). No-op
-- silencieux si le container n'a jamais ete construit (cf. garde ci-dessus).
MainFrame.InvalidateCategory = _invalidateCategory
function Build.Profiles(container)
  local ctx = NewLayout(container)
  local W   = CONTENT_W
  local P   = ns.Profiles

  -- -- Profil actuel + Réinitialiser ------------------------------------
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_PROFILES"], W))

  local currentLabel = container:CreateFontString(nil, "OVERLAY")
  currentLabel:SetFont(ns.Media.fontGui, 11)
  currentLabel:SetTextColor(unpack(ns.Theme.textNormal))
  currentLabel:SetJustifyH("LEFT")
  currentLabel:SetSize(W, 18)
  currentLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -ctx.y)
  ctx.y = ctx.y + 20

  local function UpdateCurrentLabel()
    currentLabel:SetText(string.format(L["SETTINGS_CURRENT_PROFILE"], "|cffffd700" .. P.GetActive() .. "|r"))
  end
  UpdateCurrentLabel()

  local BTN_W = 100  -- largeur commune pour tous les boutons de cette page

  local resetBtn = CreateFrame("Button", nil, container)
  resetBtn:SetSize(BTN_W, 22)
  do
    local bg = resetBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.18, 0.10, 0.00, 0.95)
    local lbl = resetBtn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10); lbl:SetPoint("CENTER")
    lbl:SetText(L["UI_RESET"])
    lbl:SetTextColor(1, 0.65, 0.15)
    resetBtn._lbl = lbl
  end
  resetBtn:SetScript("OnClick", function()
    if not resetBtn._confirmPending then
      resetBtn._confirmPending = true
      resetBtn._lbl:SetText(L["SETTINGS_CONFIRM_QUESTION"])
      C_Timer.After(4, function()
        if resetBtn._confirmPending then
          resetBtn._confirmPending = false
          resetBtn._lbl:SetText(L["UI_RESET"])
        end
      end)
    else
      resetBtn._confirmPending = false
      resetBtn._lbl:SetText(L["UI_RESET"])
      local active = P.GetActive()
      local ok, err = P.Reset(active)
      if not ok then
        print(string.format(L["SETTINGS_PROFILE_ERROR_MSG"], tostring(err)))
      else
        print(string.format(L["SETTINGS_PROFILE_RESET_MSG"], "|cffffd700" .. active .. "|r"))
      end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(resetBtn)

  -- -- Nouveau profil ---------------------------------------------------
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_NEW_PROFILE"], W))

  local EB_NEW_W = 100
  local OK_W     = 36
  local nameEB = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
  SW.StyleEditBox(nameEB)
  nameEB:SetSize(EB_NEW_W, 22)
  nameEB:SetFont(ns.Media.fontGui, 10, "")
  nameEB:SetAutoFocus(false)
  nameEB:SetMaxLetters(48)

  local okBtn = CreateFrame("Button", nil, container)
  okBtn:SetSize(OK_W, 22)
  okBtn:Hide()
  do
    local bg = okBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.22, 0.06, 0.95)
    local lbl = okBtn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10); lbl:SetPoint("CENTER")
    lbl:SetText(L["SETTINGS_OK"]); lbl:SetTextColor(0.4, 1, 0.4)
  end

  local function DoCreateProfile()
    local name = (nameEB:GetText() or ""):match("^%s*(.-)%s*$")
    if name == "" then return end
    local ok, err = P.Create(name)
    if not ok then
      print(string.format(L["SETTINGS_PROFILE_ERROR_MSG"], tostring(err)))
    else
      nameEB:SetText("")
      okBtn:Hide()
      P.SetActive(name)
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end

  nameEB:SetScript("OnTextChanged", function(self)
    local txt = (self:GetText() or ""):match("^%s*(.-)%s*$")
    if txt ~= "" then okBtn:Show() else okBtn:Hide() end
  end)
  nameEB:SetScript("OnEnterPressed", function() DoCreateProfile() end)
  okBtn:SetScript("OnClick", function() DoCreateProfile() end)

  -- Décalage de 15px à droite pour éviter le crop du bord InputBoxTemplate
  nameEB:ClearAllPoints()
  nameEB:SetPoint("TOPLEFT", container, "TOPLEFT", 15, -ctx.y)
  nameEB:Show()
  okBtn:ClearAllPoints()
  okBtn:SetPoint("TOPLEFT", container, "TOPLEFT", 15 + EB_NEW_W + 4, -ctx.y)
  -- okBtn reste caché jusqu'à saisie
  ctx.y = ctx.y + 22 + 2

  -- -- Profils existants ------------------------------------------------
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_EXISTING_PROFILES"], W))

  local existDDLbl = container:CreateFontString(nil, "OVERLAY")
  existDDLbl:SetFont(ns.Media.fontGui, 10)
  existDDLbl:SetTextColor(unpack(ns.Theme.textNormal))
  existDDLbl:SetJustifyH("LEFT")
  existDDLbl:SetWidth(W)
  existDDLbl:SetHeight(14)
  existDDLbl:SetText(L["SETTINGS_ACTIVE_PROFILE"])
  ctx:Add(existDDLbl)
  ctx:Spacer(5)

  local existDD = ctx:Add(SW.CreateDropdown(container, "", {}, W))
  existDD._btn:ClearAllPoints()
  existDD._btn:SetPoint("TOPLEFT", existDD, "TOPLEFT", 1, 4)
  existDD._btn:SetSize(100, 20)
  existDD._btn:HookScript("OnEnter", function()
    GameTooltip:SetOwner(existDD._btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["SETTINGS_TT_SELECT_PROFILE_ACTIVATE"], 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  existDD._btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

  -- Profil global ou par personnage
  local function RefreshCharCB() end  -- sera défini plus bas
  local charCB = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_PROFILE_USE_FOR_ALL_CHARS"],
    L["SETTINGS_PROFILE_USE_FOR_ALL_CHARS_TT"],
    W))
  -- Coché = global (pas de liaison per-char)
  charCB:SetChecked(P.GetCharBinding() == nil)
  charCB.onChanged = function(val)
    if val then
      -- Global : supprimer la liaison per-char
      P.ClearCharProfile()
    else
      -- Per-char : lier le profil actif à ce personnage
      P.SetCharProfile(P.GetActive())
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end
  RefreshCharCB = function()
    charCB:SetChecked(P.GetCharBinding() == nil)
  end

  -- -- Profils de spécialisation ----------------------------------------
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SPEC_PROFILES"], W))

  local specDesc = container:CreateFontString(nil, "OVERLAY")
  specDesc:SetFont(ns.Media.fontGui, 10)
  specDesc:SetTextColor(unpack(ns.Theme.textDim))
  specDesc:SetJustifyH("LEFT")
  specDesc:SetWordWrap(true)
  specDesc:SetWidth(W)
  specDesc:SetHeight(40)
  specDesc:SetText(L["SETTINGS_SPEC_PROFILES_DESC"])
  ctx:Add(specDesc)

  local specCB = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SPEC_PROFILES_ENABLE"],
    L["SETTINGS_SPEC_PROFILES_ENABLE_TT"],
    W))
  specCB:SetChecked(P.GetSpecProfilesEnabled())

  -- Dropdowns par spec en colonnes (3 cols, ou 4 pour le druide)
  local numSpecs  = GetNumSpecializations and GetNumSpecializations() or 0
  local specIDs   = {}
  local specNames = {}
  local specDDs   = {}

  -- Widget compact : label spec (en haut, centré) + dropdown 100px (en bas)
  local function CreateSpecColumn(colW)
    local LABEL_H = 14
    local GAP     = 5
    local DD_W    = 130
    local frame   = CreateFrame("Frame", nil, container)
    frame:SetSize(DD_W, LABEL_H + GAP + 28)
    local lbl = frame:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10)
    lbl:SetTextColor(unpack(ns.Theme.textNormal))
    lbl:SetJustifyH("CENTER")
    lbl:SetSize(DD_W, LABEL_H)
    lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
    frame._specLbl = lbl
    local dd = SW.CreateDropdown(frame, "", {}, DD_W)
    dd:ClearAllPoints()
    dd:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(LABEL_H + GAP))
    dd._btn:SetSize(DD_W, 20)
    dd._btn:ClearAllPoints()
    dd._btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 1, 4)
    if dd.label then dd.label:Hide() end
    frame._dd = dd
    function frame:SetOptions(opts)   self._dd:SetOptions(opts)       end
    function frame:SetValue(val)      self._dd:SetValue(val)          end
    function frame:GetValue()         return self._dd:GetValue()      end
    function frame:SetLabelText(t)    self._specLbl:SetText(t)        end
    return frame
  end

  local function GetActiveSpecID()
    if not GetSpecialization then return nil end
    local idx = GetSpecialization()
    return idx and (GetSpecializationInfo(idx)) or nil
  end

  if numSpecs > 0 then
    local GAP_COL = 6
    local activeID = GetActiveSpecID()
    for i = 1, numSpecs do
      local specID, specName = GetSpecializationInfo(i)
      specIDs[i]   = specID
      specNames[i] = specName or string.format(L["SETTINGS_SPEC_FALLBACK_NAME"], i)
      local col = CreateSpecColumn()
      local labelTxt = specNames[i]
      if specID == activeID then labelTxt = labelTxt .. L["SETTINGS_SPEC_ACTIVE_SUFFIX"] end
      col:SetLabelText(labelTxt)
      specDDs[i] = col
    end
    ctx:AddRow(GAP_COL, unpack(specDDs))
  end

  local function SetSpecDDsLocked(locked)
    for i = 1, numSpecs do
      local col = specDDs[i]
      if col then
        local btn = col._dd._btn
        if locked then
          btn:Disable()
          btn:SetBackdropColor(0.10, 0.10, 0.10, 0.5)
          btn.text:SetTextColor(0.45, 0.45, 0.45, 1)
          btn.arrow:SetTextColor(0.35, 0.35, 0.35, 1)
        else
          btn:Enable()
          btn:SetBackdropColor(0.12, 0.12, 0.14, 1)
          btn.text:SetTextColor(unpack(ns.Theme.textNormal))
          btn.arrow:SetTextColor(unpack(ns.Theme.textDim))
        end
      end
    end
  end

  local function RefreshSpecDDs(allOpts)
    local activeID   = GetActiveSpecID()
    local specEnabled = P.GetSpecProfilesEnabled()
    local activeProf  = P.GetActive()
    for i = 1, numSpecs do
      local col = specDDs[i]
      if col then
        col:SetOptions(allOpts)
        local val
        if specEnabled then
          val = P.GetSpecProfile(specIDs[i]) or activeProf
        else
          val = activeProf
        end
        col:SetValue(val)
        local labelTxt = specNames[i]
        if specIDs[i] == activeID then labelTxt = labelTxt .. L["SETTINGS_SPEC_ACTIVE_SUFFIX"] end
        col:SetLabelText(labelTxt)
        col._dd.onChanged = (function(sid, isActive)
          return function(name)
            P.SetSpecProfile(sid, name)
            -- Si c'est la spé actuellement active, appliquer le profil immédiatement
            if isActive then
              local root = AishaddonDB
              if root._profiles and root._profiles[name] then
                P.SetActive(name)
              end
            end
          end
        end)(specIDs[i], specIDs[i] == activeID)
      end
    end
  end

  -- Verrouille/déverrouille le dropdown "Profil actif" selon l'état des profils de spé
  local function SetExistDDLocked(locked)
    if locked then
      existDD._btn:Disable()
      existDD._btn:SetBackdropColor(0.10, 0.10, 0.10, 0.5)
      existDD._btn.text:SetTextColor(0.45, 0.45, 0.45, 1)
      existDD._btn.arrow:SetTextColor(0.35, 0.35, 0.35, 1)
    else
      existDD._btn:Enable()
      existDD._btn:SetBackdropColor(0.12, 0.12, 0.14, 1)
      existDD._btn.text:SetTextColor(unpack(ns.Theme.textNormal))
      existDD._btn.arrow:SetTextColor(unpack(ns.Theme.textDim))
    end
  end

  local function SetSpecRowsVisible(show)
    SetSpecDDsLocked(not show)
    SetExistDDLocked(show)
  end

  specCB.onChanged = function(val)
    P.SetSpecProfilesEnabled(val)
    if val then
      -- Initialise les assignations non encore définies avec le profil actif
      local active = P.GetActive()
      for i = 1, numSpecs do
        if specIDs[i] and not P.GetSpecProfile(specIDs[i]) then
          P.SetSpecProfile(specIDs[i], active)
        end
      end
    end
    SetSpecRowsVisible(val)
    if val then P.ApplySpecProfile() end
  end

  -- -- Cooldown Manager par spécialisation --------------------------------
  -- Section masquee : feature plus utilisee (cf. aussi P.ApplyCDMForSpec,
  -- deja en "do return end" depuis le standby taint CDM). Code garde intact
  -- pour reactivation eventuelle -- juste enveloppe dans if false.
  if false then
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_PROFILES"], W))

  local cdmDesc = container:CreateFontString(nil, "OVERLAY")
  cdmDesc:SetFont(ns.Media.fontGui, 10)
  cdmDesc:SetTextColor(unpack(ns.Theme.textDim))
  cdmDesc:SetJustifyH("LEFT")
  cdmDesc:SetWordWrap(true)
  cdmDesc:SetWidth(W)
  cdmDesc:SetHeight(48)
  cdmDesc:SetText(L["SETTINGS_CDM_PROFILES_DESC"])
  ctx:Add(cdmDesc)

  local cdmCB = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_CDM_AUTOAPPLY"],
    L["SETTINGS_CDM_AUTOAPPLY_TT"],
    W))
  cdmCB:SetChecked(P.GetCDMAutoApplyEnabled())
  cdmCB.onChanged = function(val) P.SetCDMAutoApplyEnabled(val) end

  ctx:Spacer(6)

  local cdmSaveBtn = CreateFrame("Button", nil, container)
  cdmSaveBtn:SetSize(180, 22)
  do
    local bg = cdmSaveBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.22, 0.06, 0.95)
    local lbl = cdmSaveBtn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10); lbl:SetPoint("CENTER")
    lbl:SetTextColor(0.4, 1, 0.4)
    cdmSaveBtn._lbl = lbl
  end
  ctx:Add(cdmSaveBtn)

  local cdmStatus = container:CreateFontString(nil, "OVERLAY")
  cdmStatus:SetFont(ns.Media.fontGui, 10)
  cdmStatus:SetTextColor(unpack(ns.Theme.textDim))
  cdmStatus:SetJustifyH("LEFT")
  cdmStatus:SetWordWrap(true)
  cdmStatus:SetWidth(W)
  cdmStatus:SetHeight(28)
  ctx:Add(cdmStatus)

  local function GetActiveSpecIDAndName()
    if not GetSpecialization then return nil end
    local idx = GetSpecialization()
    if not idx then return nil end
    return GetSpecializationInfo(idx)
  end

  local function RefreshCDMSection()
    local specID, specName = GetActiveSpecIDAndName()
    if specID then
      cdmSaveBtn._lbl:SetText(string.format(L["SETTINGS_CDM_SAVE_BTN"], specName or ("#" .. specID)))
      cdmSaveBtn:Enable()
    else
      cdmSaveBtn._lbl:SetText(L["SETTINGS_CDM_SAVE_BTN_NOSPEC"])
      cdmSaveBtn:Disable()
    end
    local ids = P.ListCDMSpecs()
    if #ids == 0 then
      cdmStatus:SetText(L["SETTINGS_CDM_NONE_SAVED"])
    else
      local names = {}
      for _, sid in ipairs(ids) do
        local _, n = GetSpecializationInfoByID(sid)
        names[#names + 1] = n or ("#" .. sid)
      end
      cdmStatus:SetText(string.format(L["SETTINGS_CDM_SAVED_LIST"], table.concat(names, ", ")))
    end
  end
  RefreshCDMSection()

  cdmSaveBtn:SetScript("OnClick", function()
    local specID, specName = GetActiveSpecIDAndName()
    if not specID then return end
    local ok, err = P.SaveCDMForSpec(specID)
    if ok then
      print(string.format(L["SETTINGS_CDM_SAVED_MSG"], "|cffffd700" .. (specName or ("#" .. specID)) .. "|r", "|cffffd700" .. P.GetActive() .. "|r"))
    else
      print(string.format(L["SETTINGS_CDM_SAVE_ERROR"], tostring(err)))
    end
    RefreshCDMSection()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)

  ns.CallbackRegistry:Register("SPEC_CHANGED", RefreshCDMSection)
  ns.CallbackRegistry:Register("PROFILE_CHANGED", RefreshCDMSection)
  end -- if false (section CDM par spe masquee)

  -- -- Copier à partir de -----------------------------------------------
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_COPY_FROM"], W))

  local copyDesc = container:CreateFontString(nil, "OVERLAY")
  copyDesc:SetFont(ns.Media.fontGui, 10)
  copyDesc:SetTextColor(unpack(ns.Theme.textDim))
  copyDesc:SetJustifyH("LEFT")
  copyDesc:SetWordWrap(true)
  copyDesc:SetWidth(W)
  copyDesc:SetHeight(26)
  copyDesc:SetText(L["SETTINGS_COPY_FROM_DESC"])
  ctx:Add(copyDesc)

  local copyLbl = container:CreateFontString(nil, "OVERLAY")
  copyLbl:SetFont(ns.Media.fontGui, 10)
  copyLbl:SetTextColor(unpack(ns.Theme.textNormal))
  copyLbl:SetJustifyH("LEFT")
  copyLbl:SetWidth(W)
  copyLbl:SetHeight(14)
  copyLbl:SetText(L["SETTINGS_SEC_COPY_FROM"])
  ctx:Add(copyLbl)
  ctx:Spacer(5)

  local copyDD = ctx:Add(SW.CreateDropdown(container, "", {}, W))
  if copyDD.label then copyDD.label:Hide() end
  copyDD._btn:ClearAllPoints()
  copyDD._btn:SetPoint("TOPLEFT", copyDD, "TOPLEFT", 1, 4)
  copyDD._btn:SetSize(100, 20)
  copyDD.onChanged = function(src)
    local ok, err = P.CopyFrom(src)
    if not ok then
      print(string.format(L["SETTINGS_PROFILE_ERROR_MSG"], tostring(err)))
    else
      print(string.format(L["SETTINGS_PROFILE_COPIED_MSG"], "|cffffd700" .. src .. "|r", "|cffffd700" .. P.GetActive() .. "|r"))
    end
    -- Réinitialiser le dropdown après copie
    C_Timer.After(0.05, function()
      copyDD._btn.text:SetText("--")
      copyDD.currentValue = nil
    end)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end

  -- -- Supprimer un profil -----------------------------------------------
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_DELETE_PROFILE"], W))

  local delDesc = container:CreateFontString(nil, "OVERLAY")
  delDesc:SetFont(ns.Media.fontGui, 10)
  delDesc:SetTextColor(unpack(ns.Theme.textDim))
  delDesc:SetJustifyH("LEFT")
  delDesc:SetWordWrap(true)
  delDesc:SetWidth(W)
  delDesc:SetHeight(16)
  delDesc:SetText(L["SETTINGS_DELETE_PROFILE_DESC"])
  ctx:Add(delDesc)

  local delDDLbl = container:CreateFontString(nil, "OVERLAY")
  delDDLbl:SetFont(ns.Media.fontGui, 10)
  delDDLbl:SetTextColor(unpack(ns.Theme.textNormal))
  delDDLbl:SetJustifyH("LEFT")
  delDDLbl:SetWidth(W)
  delDDLbl:SetHeight(14)
  delDDLbl:SetText(L["SETTINGS_PROFILE_TO_DELETE"])
  ctx:Add(delDDLbl)
  ctx:Spacer(5)

  local deleteDD = ctx:Add(SW.CreateDropdown(container, "", {}, W))
  deleteDD._btn:ClearAllPoints()
  deleteDD._btn:SetPoint("TOPLEFT", deleteDD, "TOPLEFT", 1, 4)
  deleteDD._btn:SetSize(100, 20)

  local delBtn = CreateFrame("Button", nil, container)
  do
    local bg = delBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.22, 0.04, 0.04, 0.95)
    local lbl = delBtn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10); lbl:SetPoint("CENTER")
    lbl:SetText(L["SETTINGS_DELETE_SELECTED_PROFILE"])
    lbl:SetTextColor(1, 0.4, 0.4)
    delBtn._lbl = lbl
    delBtn:SetSize(lbl:GetStringWidth() + 24, 22)
  end
  delBtn:SetScript("OnClick", function()
    local name = deleteDD:GetValue()
    if not name then
      print(L["SETTINGS_PROFILE_SELECT_TO_DELETE_MSG"])
      return
    end
    if not delBtn._confirmPending then
      delBtn._confirmPending = true
      delBtn._lbl:SetText(string.format(L["SETTINGS_CONFIRM_DELETE_PROFILE"], name))
      C_Timer.After(5, function()
        if delBtn._confirmPending then
          delBtn._confirmPending = false
          delBtn._lbl:SetText(L["SETTINGS_DELETE_SELECTED_PROFILE"])
        end
      end)
    else
      delBtn._confirmPending = false
      delBtn._lbl:SetText(L["SETTINGS_DELETE_SELECTED_PROFILE"])
      local ok, err = P.Delete(name)
      if not ok then
        print(string.format(L["SETTINGS_PROFILE_ERROR_MSG"], tostring(err)))
      else
        print(string.format(L["SETTINGS_PROFILE_DELETED_MSG"], "|cffffd700" .. name .. "|r"))
      end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(delBtn)

  -- -- Import / Export -------------------------------------------------
  ctx:Spacer(10)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_IMPORT_EXPORT"], W))

  local exportBtn = CreateFrame("Button", nil, container)
  do
    local bg = exportBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.16, 0.06, 0.95)
    local lbl = exportBtn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10); lbl:SetPoint("CENTER")
    lbl:SetText(L["SETTINGS_EXPORT_ACTIVE_PROFILE_BTN"])
    lbl:SetTextColor(0.4, 1, 0.4)
    exportBtn:SetSize(lbl:GetStringWidth() + 24, 22)
  end
  exportBtn:SetScript("OnClick", function()
    local str, err = P.Export(P.GetActive())
    if not str then
      print(string.format(L["SETTINGS_PROFILE_ERROR_MSG_LABELED"], tostring(err)))
    else
      ShowExportPopup(str)
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)

  local importBtn = CreateFrame("Button", nil, container)
  do
    local bg = importBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.12, 0.22, 0.95)
    local lbl = importBtn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10); lbl:SetPoint("CENTER")
    lbl:SetText(L["SETTINGS_IMPORT_PROFILE_BTN"])
    lbl:SetTextColor(0.5, 0.8, 1)
    importBtn:SetSize(lbl:GetStringWidth() + 24, 22)
  end
  importBtn:SetScript("OnClick", function()
    ShowImportPopup(function(name, str)
      local ok, err = P.Import(str, name)
      if not ok then
        print(string.format(L["SETTINGS_PROFILE_ERROR_MSG_LABELED"], tostring(err)))
      else
        print(string.format(L["SETTINGS_PROFILE_IMPORTED_MSG"], "|cffffd700" .. name .. "|r"))
        P.SetActive(name)
      end
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
  end)
  ctx:AddRow(4, exportBtn, importBtn)

  ctx:Spacer()

  -- -- Refresh global ---------------------------------------------------
  local function RefreshAll()
    local active   = P.GetActive()
    local allNames = P.List()
    local allOpts  = {}
    for _, n in ipairs(allNames) do allOpts[#allOpts + 1] = { value = n, text = n } end

    UpdateCurrentLabel()
    RefreshCharCB()

    existDD:SetOptions(allOpts)
    existDD:SetValue(active)
    SetExistDDLocked(P.GetSpecProfilesEnabled())
    SetSpecDDsLocked(not P.GetSpecProfilesEnabled())

    copyDD:SetOptions(allOpts)

    local inactiveOpts = {}
    for _, n in ipairs(allNames) do
      if n ~= active then inactiveOpts[#inactiveOpts + 1] = { value = n, text = n } end
    end
    deleteDD:SetOptions(inactiveOpts)
    -- Réinitialiser si le profil sélectionné est devenu actif ou n'existe plus
    local delExists = false
    if deleteDD.currentValue and deleteDD.currentValue ~= active then
      for _, n in ipairs(allNames) do
        if n == deleteDD.currentValue then delExists = true; break end
      end
    end
    if not delExists then
      deleteDD._btn.text:SetText("--")
      deleteDD.currentValue = nil
    end

    RefreshSpecDDs(allOpts)
  end

  existDD.onChanged = function(name)
    local ok, err = P.SetActive(name)
    if not ok then
      print(string.format(L["SETTINGS_PROFILE_ERROR_MSG_LABELED"], tostring(err)))
    end
    -- PROFILE_CHANGED déclenche RefreshAll
  end

  RefreshAll()

  -- Callbacks de rafraîchissement
  ns.CallbackRegistry:Register("PROFILE_LIST_CHANGED", function()
    RefreshAll()
  end)

  -- Mise à jour des labels "- Actif" quand on change de spé sans changer de profil
  ns.CallbackRegistry:Register("SPEC_CHANGED", function()
    local allOpts = {}
    for _, n in ipairs(P.List()) do allOpts[#allOpts + 1] = { value = n, text = n } end
    RefreshSpecDDs(allOpts)
    SetSpecDDsLocked(not P.GetSpecProfilesEnabled())
  end)

  ns.CallbackRegistry:Register("PROFILE_CHANGED", function()
    RefreshAll()
    if not categoryContainers then return end
    local toInvalidate = {}
    for catId in pairs(categoryContainers) do
      if catId ~= "profiles" then
        toInvalidate[#toInvalidate + 1] = catId
      end
    end
    for _, catId in ipairs(toInvalidate) do
      categoryContainers[catId].frame:Hide()
      categoryContainers[catId] = nil
    end
    if activeCategory and activeCategory ~= "profiles" then
      local prev = activeCategory
      activeCategory = nil
      C_Timer.After(0, function() MainFrame:SelectCategory(prev) end)
    end
  end)

  ctx:Finalize()
end

-- Wrappers vers les menus Auras & Procs (ns.Auras, anciennement AishUIAura)
function Build.AurasRender(container, renderKey)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildRenderMenu then
    ns.Auras.SettingsPanel.BuildRenderMenu(container, CONTENT_W, renderKey)
  end
end
function Build.AurasTactics(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildTacticsMenu then
    ns.Auras.SettingsPanel.BuildTacticsMenu(container, CONTENT_W)
  end
end
function Build.AurasEquipment(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildEquipmentMenu then
    ns.Auras.SettingsPanel.BuildEquipmentMenu(container, CONTENT_W)
  end
end
function Build.AurasEffects(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildEffectsMenu then
    ns.Auras.SettingsPanel.BuildEffectsMenu(container, CONTENT_W)
  end
end
function Build.AurasMissingBuffs(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildMissingBuffsMenu then
    ns.Auras.SettingsPanel.BuildMissingBuffsMenu(container, CONTENT_W)
  end
end

-- BUILD : Modules (vue d'ensemble) — liste tous les modules de l'addon,
-- groupés par catégorie, avec un toggle par module ET par catégorie entière.
-- Désactiver une catégorie replie son bloc et coupe tous ses modules ;
-- la réactiver restaure l'état individuel de chacun (pas un "tout à ON").

-- Entrée générique : lit/écrit ns.DB.<dbKey>.<subKey>, réapplique via LiveApply.
local function ModEntry(id, label, dbKey, subKey, tooltip)
  return {
    id = id, label = label, tooltip = tooltip,
    get = function() return DBGet(dbKey, subKey) ~= false end,
    set = function(val)
      DBSet(dbKey, subKey, val)
      LiveApply(dbKey)
      InvalidateOwnPage(dbKey)
    end,
  }
end

-- Entrée "barre d'unité" : délègue à UBGet/UBSet (unitBars.bars.<barKey>.enabled),
-- qui applique déjà LiveApply("unitBars") en interne.
local function ModUBEntry(id, label, barKey)
  return {
    id = id, label = label,
    get = function() return UBGet(barKey, "enabled") ~= false end,
    set = function(val)
      UBSet(barKey, "enabled", val)
      InvalidateOwnPage("unitBars")
    end,
  }
end

-- Entrée "style Auras & Procs" : ces flags (iconlistEnabled, freebarsEnabled...)
-- vivent dans ns.Auras.db (SavedVariable séparée, AishUIAuraDB), pas ns.DB —
-- cf. Modules/Auras/Core/Defaults.lua. RebuildDisplay() ré-init + re-scan tous
-- les renders, ce qui masque/affiche le style visé (chaque render relit son
-- propre flag <x>Enabled dans sa fonction Update).
local function ModAuraEntry(id, label, auraKey)
  return {
    id = id, label = label,
    get = function()
      local A = ns.Auras
      return A and A.db and A.db[auraKey] ~= false
    end,
    set = function(val)
      local A = ns.Auras
      if A and A.db then A.db[auraKey] = val end
      if A and A.RebuildDisplay then A.RebuildDisplay() end
    end,
  }
end

-- Entrée "Tracking d'auras" : miroir INVERSE de ns.Auras.db.useNativeCDM
-- (toggle "Utiliser le CDM natif", cf. Modules/Auras/UI/Menus/Tactics.lua) --
-- remplace les 4 anciennes lignes par style de rendu (iconlist/freebars/
-- icons/circlebars, toujours actives/desactivees ENSEMBLE via ce meme
-- useNativeCDM cote Tactics.lua) par UN SEUL toggle, cf. demande utilisateur.
-- ns.SetUseNativeCDM (definie dans Tactics.lua) applique tous les effets de
-- bord necessaires (SetAlpha des containers, ScanAuras/RebuildDisplay,
-- RefreshCDMMask) -- pas de duplication de cette logique ici.
local function ModAurasTrackingEntry()
  return {
    id = "aurasTracking", label = L["SETTINGS_MOD_AURAS_TRACKING"], tooltip = L["SETTINGS_MOD_AURAS_TRACKING_TT"],
    get = function()
      local A = ns.Auras
      return not (A and A.db and A.db.useNativeCDM == true)
    end,
    set = function(val)
      local A = ns.Auras
      if A and A.SetUseNativeCDM then A.SetUseNativeCDM(not val) end
    end,
  }
end

local MODULE_CATEGORIES = {
  {
    key = "combat", label = L["SETTINGS_GROUP_COMBAT"],
    modules = {
      ModEntry("resourceCircle", L["SETTINGS_SEC_RESOURCE_CIRCLE"],  "resourceCircle", "enabled"),
      ModEntry("orbs",           L["SETTINGS_MOD_ORBS"],             "spellEffects",   "orbsEnabled", L["SETTINGS_MOD_ORBS_TT"]),
      ModEntry("priorityBar",    L["SETTINGS_SEC_PRIORITY_BAR"],     "priorityBar",    "enabled"),
      ModEntry("cdmEssential",   L["SETTINGS_CAT_CDM_ESSENTIAL"],    "cdmEssential",   "enabled"),
      ModEntry("cdmUtility",     L["SETTINGS_CAT_CDM_UTILITY"],      "cdmUtility",     "enabled"),
      ModEntry("bigCursor",      L["SETTINGS_MOD_BIG_CURSOR"],       "bigCursor",      "enabled", L["SETTINGS_MOD_BIG_CURSOR_TT"]),
      ModEntry("rotationHelper", L["SETTINGS_CAT_ROTATION_HELPER"],  "rotationHelper", "enabled"),
    },
  },
  {
    key = "unitFrames", label = L["SETTINGS_GROUP_UNIT_FRAMES"],
    modules = {
      (function()
        local m = ModEntry("unitBars", L["SETTINGS_CAT_HEALTH_BARS"], "unitBars", "enabled")
        m.children = {
          ModUBEntry("unitBars_player", L["SETTINGS_UNIT_PLAYER"],           "player"),
          ModUBEntry("unitBars_target", L["SETTINGS_UNIT_TARGET"],           "target"),
          ModUBEntry("unitBars_focus",  L["SETTINGS_UNIT_FOCUS"],            "focus"),
          ModUBEntry("unitBars_pet",    L["SETTINGS_UNIT_PET"],              "pet"),
          ModUBEntry("unitBars_tot",    L["SETTINGS_UNIT_TARGET_OF_TARGET"], "targettarget"),
        }
        return m
      end)(),
      -- Barres de cast joueur/cible : rattachees aux cadres d'unites (et non
      -- plus a "Combat"), comme leurs sections dans la barre laterale.
      ModEntry("castBar",       L["SETTINGS_SEC_CAST_BAR"],    "castBar",       "enabled"),
      ModEntry("targetCastBar", L["SETTINGS_CAT_TARGET_CAST"], "targetCastBar", "enabled"),
      (function()
        local m = ModEntry("topTargetBar", L["SETTINGS_CAT_TOP_TARGET"], "topTargetBar", "enabled")
        m.children = {
          ModEntry("topTargetBar_tot", L["SETTINGS_UNIT_TARGET_OF_TARGET"], "topTargetBar", "showTargetOfTarget"),
          ModEntry("targetAuras",      L["SETTINGS_CAT_TARGET_AURAS"],      "targetAuras",  "enabled"),
        }
        return m
      end)(),
      ModEntry("groupNumber", L["SETTINGS_SEC_GROUP_NUMBER"], "groupNumber", "enabled"),
    },
  },
  {
    key = "world", label = L["SETTINGS_GROUP_WORLD"],
    modules = {
      ModEntry("healthCircle",              L["SETTINGS_MOD_HEALTH_CIRCLE"], "healthCircle",              "enabled"),
      ModEntry("outOfCombatResourceCircle", L["SETTINGS_SEC_OCRC"],          "outOfCombatResourceCircle", "enabled"),
      ModEntry("xpBar",     L["SETTINGS_CAT_XP_BAR"],    "xpBar",     "enabled"),
      ModEntry("skyriding", L["SETTINGS_CAT_SKYRIDING"], "skyriding", "enabled"),
      ModEntry("afkMode",   L["SETTINGS_CAT_AFK_MODE"],  "afkMode",   "enabled"),
      ModEntry("characterArmory", L["SETTINGS_CAT_CHARACTER_ARMORY"], "characterArmory", "enabled"),
      ModEntry("visibility", L["SETTINGS_MOD_ELVUI_BUFFS"], "visibility", "elvuiBuffsEnabled", L["SETTINGS_MOD_ELVUI_BUFFS_TT"]),
    },
  },
  {
    key = "auras", label = L["SETTINGS_GROUP_AURAS_PROCS"],
    modules = {
      ModEntry("spellEffects", L["SETTINGS_SEC_3D_ANIMATIONS"], "spellEffects", "enabled"),
      ModAurasTrackingEntry(),
      ModAuraEntry("aurasTrinkets",   L["SETTINGS_CAT_TRINKETS"],    "equipmentEnabled"),
      {
        id = "aurasMissingBuffs", label = L["AURASDATA_SEC_MISSINGBUFFS_LABEL"],
        get = function()
          local A = ns.Auras
          return A and A.MissingBuffs and A.MissingBuffs.Cfg().enabled == true
        end,
        set = function(val)
          local A = ns.Auras
          if A and A.MissingBuffs then
            A.MissingBuffs.Cfg().enabled = val
            A.MissingBuffs.RequestCheck()
          end
          InvalidateOwnPage("aurasMissingBuffs")
        end,
      },
    },
  },
}

-- ns.DB.modulesPanel.categoryOff[catKey] : true si la catégorie a été coupée
-- en bloc depuis cette page (persistant, cf. Config/Defaults.lua).
local function IsCategoryOff(catKey)
  local db = ns.DB and ns.DB.modulesPanel
  return db and db.categoryOff and db.categoryOff[catKey] == true
end

-- Parcourt récursivement les modules d'une catégorie (+ leurs `children`),
-- fn(entry, depth) — depth sert à l'indentation visuelle des sous-lignes.
local function WalkModulesDepth(modules, depth, fn)
  for _, m in ipairs(modules) do
    fn(m, depth)
    if m.children then WalkModulesDepth(m.children, depth + 1, fn) end
  end
end

-- Active/désactive toute une catégorie. Off : sauvegarde l'état individuel
-- (get()) de chaque module dans le snapshot puis force tout à false. On :
-- restaure le snapshot (true si un module n'y figure pas, ex. jamais coupé
-- avant) et l'efface. Réactiver ne remet PAS tout à ON aveuglément : ça rend
-- à chaque module l'état qu'il avait avant que la catégorie entière soit
-- coupée.
local function SetCategoryOff(catDef, off)
  ns.DB = ns.DB or {}
  ns.DB.modulesPanel = ns.DB.modulesPanel or {}
  ns.DB.modulesPanel.categoryOff = ns.DB.modulesPanel.categoryOff or {}
  ns.DB.modulesPanel.snapshot    = ns.DB.modulesPanel.snapshot or {}
  local catKey = catDef.key
  if off then
    local snap = {}
    WalkModulesDepth(catDef.modules, 0, function(m) snap[m.id] = m.get(); m.set(false) end)
    ns.DB.modulesPanel.snapshot[catKey] = snap
  else
    local snap = ns.DB.modulesPanel.snapshot[catKey] or {}
    WalkModulesDepth(catDef.modules, 0, function(m)
      local prev = snap[m.id]
      m.set(prev == nil and true or prev)
    end)
    ns.DB.modulesPanel.snapshot[catKey] = nil
  end
  ns.DB.modulesPanel.categoryOff[catKey] = off
  if _invalidateCategory then _invalidateCategory("modulesOverview") end
end

local MOD_ROW_H       = 22
local MOD_HEADER_H    = 22
local MOD_INDENT      = 14   -- décalage supplémentaire par profondeur (sous-modules)
local MOD_BASE_INDENT = 14   -- décalage des modules de 1er niveau par rapport à la catégorie
local MOD_COL_GAP     = 14
local MOD_TRUNK_X0    = 6    -- x du "tronc" vertical (modules de 1er niveau)
-- x du tronc imbriqué (sous-modules) : décalé du même pas que MOD_INDENT, pour
-- que la largeur des petits traits horizontaux (ticks) reste identique à
-- chaque profondeur (cf. calcul dans Build.CategoryColumn : 8 + MOD_BASE_INDENT
-- - MOD_TRUNK_X0, indépendant de la profondeur puisque les deux décalages
-- s'annulent).
local MOD_TRUNK_X1    = MOD_TRUNK_X0 + MOD_INDENT

-- Ligne toggle générique (module ou sous-module) : réutilise directement
-- SW.CreateCheckbox (case à cocher à gauche, libellé à droite — même
-- convention que toutes les autres pages "Activer X" de ce panneau).
-- `indent` décale juste la case (le libellé, ancré à la case, suit).
local function MakeModuleRow(container, entry, indent, width)
  local cb = SW.CreateCheckbox(container, entry.label, entry.tooltip, width, MOD_ROW_H)
  cb:SetChecked(entry.get())
  if indent > 0 then
    cb.box:ClearAllPoints()
    cb.box:SetPoint("LEFT", cb, "LEFT", 8 + indent, 0)
  end
  cb.onChanged = function(val) entry.set(val) end
  return cb
end

-- En-tête de catégorie : même case à cocher que les modules (coupe/restaure
-- toute la catégorie via SetCategoryOff, cf. plus haut — off = repliée),
-- libellé légèrement plus petit qu'avant (police titre réduite) et en or pour
-- bien la distinguer des modules, + liseré en bas pour séparer visuellement
-- l'en-tête de ses modules.
local function MakeCategoryHeader(container, catDef, width, off)
  local cb = SW.CreateCheckbox(container, catDef.label, L["SETTINGS_MOD_CATEGORY_OFF_TT"], width, MOD_HEADER_H)
  cb:SetChecked(not off)
  cb.label:SetFont(ns.Media.fontTitle, 11)
  local gold = Theme.accentText or Theme.gold or Theme.accent
  cb.label:SetTextColor(gold[1], gold[2], gold[3], 1)
  -- CreateCheckbox remet le libellé en blanc au survol (OnEnter) puis le
  -- ramène à Theme.textNormal au OnLeave -- on ne touche pas au OnEnter (le
  -- survol blanc reste un bon feedback), seul le OnLeave est remplacé pour
  -- revenir à l'or plutôt qu'au gris normal des modules.
  cb:SetScript("OnLeave", function(self)
    self.label:SetTextColor(gold[1], gold[2], gold[3], 1)
    GameTooltip:Hide()
  end)

  local hairline = cb:CreateTexture(nil, "ARTWORK")
  hairline:SetHeight(1)
  hairline:SetPoint("BOTTOMLEFT",  cb, "BOTTOMLEFT",  8, -2)
  hairline:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, -2)
  hairline:SetColorTexture(unpack(Theme.separator))

  cb.onChanged = function(val) SetCategoryOff(catDef, not val) end
  return cb
end

-- Trait fin (1px) horizontal ou vertical, pour dessiner l'arbre de
-- rattachement catégorie -> modules -> sous-modules (organigramme discret).
-- Texture posée directement sur `container` (pas sur une ligne), donc rendue
-- derrière les lignes (Frame enfants), jamais par-dessus une case à cocher.
local function DrawHLine(container, x, y, w)
  local tex = container:CreateTexture(nil, "BACKGROUND")
  tex:SetColorTexture(unpack(Theme.separator))
  tex:SetSize(math.max(1, w), 1)
  tex:SetPoint("TOPLEFT", container, "TOPLEFT", x, -y)
end

local function DrawVLine(container, x, yTop, yBottom)
  local tex = container:CreateTexture(nil, "BACKGROUND")
  tex:SetColorTexture(unpack(Theme.separator))
  tex:SetSize(1, math.max(1, yBottom - yTop))
  tex:SetPoint("TOPLEFT", container, "TOPLEFT", x, -yTop)
end

-- Construit une colonne : empile les catégories de `catKeys` (repliées si
-- off), ancrées à `container` en (x, -(yOffset + y locale à la colonne)).
-- Retourne la hauteur totale utilisée par la colonne (pour dimensionner le
-- conteneur global, cf. Build.ModulesOverview -- les 3 colonnes n'ont pas
-- forcément la même hauteur selon combien de catégories/modules elles listent).
function Build.CategoryColumn(container, catKeys, x, colW, yOffset)
  local y = 0
  for _, catKey in ipairs(catKeys) do
    local catDef
    for _, c in ipairs(MODULE_CATEGORIES) do
      if c.key == catKey then catDef = c; break end
    end
    if catDef then
      local off      = IsCategoryOff(catDef.key)
      local expanded = not off

      local header = MakeCategoryHeader(container, catDef, colW, off)
      header:ClearAllPoints()
      header:SetPoint("TOPLEFT", container, "TOPLEFT", x, -(yOffset + y))
      header:Show()
      y = y + MOD_HEADER_H + 2

      if expanded then
        local headerBottomY = y  -- juste après le hairline de l'en-tête
        -- topRows[i] = { y = centre vertical, children = { centres verticaux
        -- des sous-modules, ou nil } } -- rempli au fil de la boucle pour
        -- pouvoir dessiner tronc + ticks APRÈS avoir positionné toutes les
        -- lignes (on a besoin du centre du DERNIER item avant de tracer le
        -- tronc, cf. plus bas).
        local topRows = {}
        WalkModulesDepth(catDef.modules, 0, function(entry, depth)
          local indent = MOD_BASE_INDENT + depth * MOD_INDENT
          local row = MakeModuleRow(container, entry, indent, colW)
          row:ClearAllPoints()
          row:SetPoint("TOPLEFT", container, "TOPLEFT", x, -(yOffset + y))
          row:Show()
          local rowCenterY = y + MOD_ROW_H / 2
          if depth == 0 then
            topRows[#topRows + 1] = { y = rowCenterY }
          else
            local parent = topRows[#topRows]
            parent.children = parent.children or {}
            table.insert(parent.children, rowCenterY)
          end
          y = y + MOD_ROW_H + 1
        end)

        -- Arbre de rattachement (organigramme) : un tronc vertical reliant
        -- tous les modules de 1er niveau d'une même catégorie, + un petit
        -- trait horizontal ("tick") par module -- et, pour les modules ayant
        -- des enfants (Barres de vie, Top Target), un second tronc imbriqué
        -- reliant leurs sous-modules. `tickW` est le même à toute profondeur
        -- (cf. calcul de MOD_TRUNK_X1 plus haut).
        local tickW = 8 + MOD_BASE_INDENT - MOD_TRUNK_X0
        if #topRows > 0 then
          local trunkX0 = x + MOD_TRUNK_X0
          DrawVLine(container, trunkX0, yOffset + headerBottomY, yOffset + topRows[#topRows].y)
          for _, r in ipairs(topRows) do
            DrawHLine(container, trunkX0, yOffset + r.y, tickW)
            if r.children and #r.children > 0 then
              local trunkX1 = x + MOD_TRUNK_X1
              DrawVLine(container, trunkX1, yOffset + r.y, yOffset + r.children[#r.children])
              for _, cy in ipairs(r.children) do
                DrawHLine(container, trunkX1, yOffset + cy, tickW)
              end
            end
          end
        end
      end
      y = y + 10
    end
  end
  return y
end

-- 3 colonnes : Cadres d'unités / Combat / le reste (Monde, Auras & Procs, Divers).
local MOD_COLUMNS = {
  { "unitFrames" },
  { "combat" },
  { "world", "auras", "misc" },
}

function Build.ModulesOverview(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_MODULES"], W))
  ctx:Spacer(6)

  local baseY = ctx.y
  local colW  = math.floor((W - 2 * MOD_COL_GAP) / 3)
  local maxH  = 0
  for i, catKeys in ipairs(MOD_COLUMNS) do
    local x = (i - 1) * (colW + MOD_COL_GAP)
    local h = Build.CategoryColumn(container, catKeys, x, colW, baseY)
    if h > maxH then maxH = h end
  end

  ctx.y = baseY + maxH
  ctx:Finalize()
end

-- BUILD : Cooldown Manager Essentiels / Utilitaires, cf.
-- Modules/CooldownManagerEnhanced.lua. Meme page pour les 2 viewers,
-- parametree par dbKey ("cdmEssential" / "cdmUtility").
-- Cellule compacte "couleur par etat" (etiquette + [Activer][swatch][Desaturer]
-- sur une seule ligne, PAS de section header/hairline -- 3 de ces cellules
-- sont ensuite alignees par ligne via ctx:AddRow pour un tableau a 3 colonnes,
-- cf. mise en page ActionBarsEnhanced fournie en reference).
local function CreateCDMColorCell(container, colW, dbKey, stateLabel, prefix)
  local CELL_H = 40
  local cell = CreateFrame("Frame", nil, container)
  cell:SetSize(colW, CELL_H)

  local lbl = cell:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 10)
  lbl:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, 0)
  lbl:SetTextColor(0.776, 0.710, 0.471, 1)
  lbl:SetText((stateLabel or ""):upper())
  cell.text = lbl

  local colorKey = prefix:sub(1, 1):lower() .. prefix:sub(2) .. "Color"
  local desatKey = prefix:sub(1, 1):lower() .. prefix:sub(2) .. "Desaturate"

  local swatchW = 26
  local cbW = math.floor((colW - swatchW - 6) / 2)

  local cbUse = SW.CreateCheckbox(cell, L["SETTINGS_CDM_COLOR_USE"], nil, cbW)
  cbUse:ClearAllPoints()
  cbUse:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -16)
  BindCheckbox(cbUse, dbKey, "use" .. prefix .. "Color")

  local colBtn = SW.CreateColorButton(cell, "", swatchW)
  colBtn:ClearAllPoints()
  colBtn:SetPoint("LEFT", cbUse, "RIGHT", 3, 0)
  BindColorButton(colBtn, dbKey, colorKey)

  local cbDesat = SW.CreateCheckbox(cell, L["SETTINGS_CDM_COLOR_DESATURATE"], nil, cbW)
  cbDesat:ClearAllPoints()
  cbDesat:SetPoint("LEFT", colBtn, "RIGHT", 3, 0)
  BindCheckbox(cbDesat, dbKey, desatKey)

  return cell
end

-- Bloc "Police / Taille / Couleur / Ancrage / Decalage" reutilise pour les 3
-- sous-sections Decompte / Stacks / Charges (memes controles, cles differentes).
local function CreateCDMTextControls(container, ctx, W, SL_W2, dbKey, sectionLabel,
    fontKey, useSizeKey, sizeKey, useColorKey, colorKey, pointKey, offXKey, offYKey)
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, sectionLabel, W))

  local dd = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(dd, dbKey, fontKey)

  local cbSize = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_COOLDOWN_FONT_SIZE"], nil, SL_W2)
  BindCheckbox(cbSize, dbKey, useSizeKey)
  local slSize = SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 30, 1, SL_W2)
  BindSlider(slSize, dbKey, sizeKey)
  ctx:AddRowCentered(8, cbSize, slSize)

  local cbColor = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_COOLDOWN_FONT_COLOR"], nil, SL_W2)
  BindCheckbox(cbColor, dbKey, useColorKey)
  local col = SW.CreateColorButton(container, "", SL_W2)
  BindColorButton(col, dbKey, colorKey)
  ctx:AddRowCentered(8, cbColor, col)

  local ddPoint = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_CDM_STACKS_POINT"], {
    { value = "TOPLEFT",     text = L["SETTINGS_ANCHOR_TOPLEFT"]     },
    { value = "TOP",         text = L["SETTINGS_ANCHOR_TOP"]         },
    { value = "TOPRIGHT",    text = L["SETTINGS_ANCHOR_TOPRIGHT"]    },
    { value = "LEFT",        text = L["SETTINGS_ANCHOR_LEFT"]        },
    { value = "CENTER",      text = L["SETTINGS_ANCHOR_CENTER"]      },
    { value = "RIGHT",       text = L["SETTINGS_ANCHOR_RIGHT"]       },
    { value = "BOTTOMLEFT",  text = L["SETTINGS_ANCHOR_BOTTOMLEFT"]  },
    { value = "BOTTOM",      text = L["SETTINGS_ANCHOR_BOTTOM"]      },
    { value = "BOTTOMRIGHT", text = L["SETTINGS_ANCHOR_BOTTOMRIGHT"] },
  }, 220))
  BindDropdown(ddPoint, dbKey, pointKey)

  local slOffX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -20, 20, 1, SL_W2)
  BindSlider(slOffX, dbKey, offXKey)
  local slOffY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -20, 20, 1, SL_W2)
  BindSlider(slOffY, dbKey, offYKey)
  ctx:AddRow(8, slOffX, slOffY)
end

function Build.CDM(container, dbKey)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local SL_W2 = math.floor((W - 8) / 2)
  local SL_W3 = math.floor((W - 16) / 3)

  local cbEnable = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_CDM_ENABLE"], L["SETTINGS_CDM_ENABLE_TT"], W))
  BindCheckbox(cbEnable, dbKey, "enabled")

  -- Layout & grille
  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_LAYOUT"], W))
  local cbGrowUp = SW.CreateCheckbox(container, L["SETTINGS_CDM_GROW_UP"], nil, SL_W2)
  BindCheckbox(cbGrowUp, dbKey, "growUp")
  local cbGrowRight = SW.CreateCheckbox(container, L["SETTINGS_CDM_GROW_RIGHT"], nil, SL_W2)
  BindCheckbox(cbGrowRight, dbKey, "growRight")
  ctx:AddRow(8, cbGrowUp, cbGrowRight)

  local ddGrid = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_CDM_GRID_TYPE"], ns.CDM_GRID_LAYOUT_OPTIONS, 220))
  BindDropdown(ddGrid, dbKey, "gridLayoutType")
  local ddHide = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_CDM_HIDE_INACTIVE"], ns.CDM_HIDE_INACTIVE_OPTIONS, 220))
  BindDropdown(ddHide, dbKey, "hideWhenInactive")

  local slStride = ctx:Add(SW.CreateSlider(container, L["SETTINGS_CDM_STRIDE_OVERRIDE"], 0, 60, 1, 220))
  BindSlider(slStride, dbKey, "strideOverride")

  local cbItemSize = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_ITEM_SIZE"], nil, SL_W2)
  BindCheckbox(cbItemSize, dbKey, "useItemSize")
  local slItemSize = SW.CreateSlider(container, L["SETTINGS_CDM_ITEM_SIZE"], 16, 80, 1, SL_W2)
  BindSlider(slItemSize, dbKey, "itemSize")
  ctx:AddRowCentered(8, cbItemSize, slItemSize)

  -- Couleurs par etat : grille compacte 3 colonnes, pas de separateur entre lignes
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_COLORS"], W))
  do
    local colGap = 8
    local colW = math.floor((W - 2 * colGap) / 3)
    local states = {
      { L["SETTINGS_CDM_STATE_NORMAL"], "Normal" },
      { L["SETTINGS_CDM_STATE_CD"],     "Cd" },
      { L["SETTINGS_CDM_STATE_GCD"],    "Gcd" },
      { L["SETTINGS_CDM_STATE_OOR"],    "Oor" },
      { L["SETTINGS_CDM_STATE_OOM"],    "Oom" },
      { L["SETTINGS_CDM_STATE_NOUSE"],  "Nouse" },
      { L["SETTINGS_CDM_STATE_AURA"],   "Aura" },
    }
    local row = {}
    for i, s in ipairs(states) do
      row[#row + 1] = CreateCDMColorCell(container, colW, dbKey, s[1], s[2])
      if #row == 3 or i == #states then
        ctx:AddRow(colGap, unpack(row))
        row = {}
      end
    end
  end

  -- Bordure / backdrop
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_BORDER"], W))
  local cbBackdrop = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_BACKDROP"], nil, SL_W3)
  BindCheckbox(cbBackdrop, dbKey, "useBackdrop")
  local slBackdropSize = SW.CreateSlider(container, L["SETTINGS_CDM_BACKDROP_SIZE"], 1, 6, 1, SL_W3)
  BindSlider(slBackdropSize, dbKey, "backdropSize")
  local colBackdrop = SW.CreateColorButton(container, L["SETTINGS_CDM_BACKDROP_COLOR"], SL_W3)
  BindColorButton(colBackdrop, dbKey, "backdropColor")
  ctx:AddRowCentered(8, cbBackdrop, slBackdropSize, colBackdrop)

  local cbBackdropAura = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_BACKDROP_AURA"], nil, SL_W2)
  BindCheckbox(cbBackdropAura, dbKey, "useBackdropAuraColor")
  local colBackdropAura = SW.CreateColorButton(container, L["SETTINGS_CDM_BACKDROP_AURA_COLOR"], SL_W2)
  BindColorButton(colBackdropAura, dbKey, "backdropAuraColor")
  ctx:AddRow(8, cbBackdropAura, colBackdropAura)

  local cbBackdropPandemic = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_BACKDROP_PANDEMIC"], nil, SL_W2)
  BindCheckbox(cbBackdropPandemic, dbKey, "useBackdropPandemicColor")
  local colBackdropPandemic = SW.CreateColorButton(container, L["SETTINGS_CDM_BACKDROP_PANDEMIC_COLOR"], SL_W2)
  BindColorButton(colBackdropPandemic, dbKey, "backdropPandemicColor")
  ctx:AddRow(8, cbBackdropPandemic, colBackdropPandemic)

  -- Cooldown swipe
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_SWIPE"], W))
  local cbCdColor = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_COOLDOWN_COLOR"], nil, SL_W2)
  BindCheckbox(cbCdColor, dbKey, "useCooldownColor")
  local colCd = SW.CreateColorButton(container, L["SETTINGS_CDM_COOLDOWN_COLOR"], SL_W2)
  BindColorButton(colCd, dbKey, "cooldownColor")
  ctx:AddRow(8, cbCdColor, colCd)

  local cbCdAuraColor = SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_COOLDOWN_AURA_COLOR"], nil, SL_W2)
  BindCheckbox(cbCdAuraColor, dbKey, "useCooldownAuraColor")
  local colCdAura = SW.CreateColorButton(container, L["SETTINGS_CDM_COOLDOWN_AURA_COLOR"], SL_W2)
  BindColorButton(colCdAura, dbKey, "cooldownAuraColor")
  ctx:AddRow(8, cbCdAuraColor, colCdAura)

  local cbReverse = SW.CreateCheckbox(container, L["SETTINGS_CDM_REVERSE_SWIPE"], nil, SL_W2)
  BindCheckbox(cbReverse, dbKey, "reverseSwipe")
  local cbAuraReverse = SW.CreateCheckbox(container, L["SETTINGS_CDM_AURA_REVERSE_SWIPE"], nil, SL_W2)
  BindCheckbox(cbAuraReverse, dbKey, "auraReverseSwipe")
  ctx:AddRow(8, cbReverse, cbAuraReverse)

  local cbRemoveGCD = SW.CreateCheckbox(container, L["SETTINGS_CDM_REMOVE_GCD_SWIPE"], nil, SL_W2)
  BindCheckbox(cbRemoveGCD, dbKey, "removeGCDSwipe")
  local cbAuraRemove = SW.CreateCheckbox(container, L["SETTINGS_CDM_AURA_REMOVE_SWIPE"], nil, SL_W2)
  BindCheckbox(cbAuraRemove, dbKey, "auraRemoveSwipe")
  ctx:AddRow(8, cbRemoveGCD, cbAuraRemove)

  -- Pandemie
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_PANDEMIC"], W))
  local cbPandemic = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_CDM_REMOVE_PANDEMIC"], nil, W))
  BindCheckbox(cbPandemic, dbKey, "removePandemic")

  -- Decompte / Stacks / Charges : meme structure (Police, Taille+toggle,
  -- Couleur+toggle, Ancrage, Decalage X/Y), 3 champs de cle differents.
  CreateCDMTextControls(container, ctx, W, SL_W2, dbKey, L["SETTINGS_SEC_CDM_COOLDOWN_FONT"],
    "cooldownFont", "useCooldownFontSize", "cooldownFontSize", "useCooldownFontColor", "cooldownFontColor",
    "cooldownPoint", "cooldownOffsetX", "cooldownOffsetY")

  CreateCDMTextControls(container, ctx, W, SL_W2, dbKey, L["SETTINGS_SEC_CDM_STACKS_FONT"],
    "stacksFont", "useStacksFontSize", "stacksFontSize", "useStacksColor", "stacksColor",
    "stacksPoint", "stacksOffsetX", "stacksOffsetY")

  CreateCDMTextControls(container, ctx, W, SL_W2, dbKey, L["SETTINGS_SEC_CDM_CHARGES"],
    "chargesFont", "useChargesFontSize", "chargesFontSize", "useChargesColor", "chargesColor",
    "chargesPoint", "chargesOffsetX", "chargesOffsetY")
  local cbChargesCountdown = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_CDM_SHOW_CHARGES_COUNTDOWN"], nil, W))
  BindCheckbox(cbChargesCountdown, dbKey, "showCountdownNumbersForCharges")

  -- Fondu (fading)
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_FADING"], W))
  local cbFading = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_CDM_USE_FADING"], L["SETTINGS_CDM_USE_FADING_TT"], W))
  BindCheckbox(cbFading, dbKey, "useFading")
  local slFadeAlpha = ctx:Add(SW.CreateSlider(container, L["SETTINGS_CDM_FADE_ALPHA"], 0, 1, 0.05, W))
  BindSlider(slFadeAlpha, dbKey, "fadeAlpha")
  local cbFadeCombat = SW.CreateCheckbox(container, L["SETTINGS_CDM_FADE_COMBAT"], nil, SL_W2)
  BindCheckbox(cbFadeCombat, dbKey, "fadeInCombat")
  local cbFadeTarget = SW.CreateCheckbox(container, L["SETTINGS_CDM_FADE_TARGET"], nil, SL_W2)
  BindCheckbox(cbFadeTarget, dbKey, "fadeOnTarget")
  ctx:AddRow(8, cbFadeCombat, cbFadeTarget)
  local cbFadeCasting = SW.CreateCheckbox(container, L["SETTINGS_CDM_FADE_CASTING"], nil, SL_W2)
  BindCheckbox(cbFadeCasting, dbKey, "fadeOnCasting")
  local cbFadeHover = SW.CreateCheckbox(container, L["SETTINGS_CDM_FADE_HOVER"], nil, SL_W2)
  BindCheckbox(cbFadeHover, dbKey, "fadeOnHover")
  ctx:AddRow(8, cbFadeCasting, cbFadeHover)

  -- Forme de l'icone
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CDM_ICON_MASK"], W))
  local ddMask = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_CDM_ICON_MASK"], ns.CDM_ICON_MASK_OPTIONS, 220))
  BindDropdown(ddMask, dbKey, "iconMaskIndex")

  ctx:Finalize()
  return ctx.widgets
end

-- BUILD : Armurerie (CharacterArmory) 
-- Reglages a 3 niveaux (characterArmory.<groupe>.<champ>) : les helpers
-- Bind*/DBGet/DBSet partages (utilises par ~15 autres pages) ne gerent qu'un
-- niveau -- on ajoute ici des variantes "x Nested" locales a cette section,
-- sans toucher aux helpers partages.
local function DBGetNested(group, field)
  local t = ns.DB and ns.DB.characterArmory and ns.DB.characterArmory[group]
  return t and t[field]
end
local function DBSetNested(group, field, val)
  ns.DB.characterArmory = ns.DB.characterArmory or {}
  ns.DB.characterArmory[group] = ns.DB.characterArmory[group] or {}
  ns.DB.characterArmory[group][field] = val
  if ns.CallbackRegistry then ns.CallbackRegistry:Trigger("SettingChanged", "characterArmory", group .. "." .. field, val) end
  LiveApply("characterArmory")
end
local function BindNestedCheckbox(cb, group, field)
  cb:SetChecked(DBGetNested(group, field) and true or false)
  cb.onChanged = function(val) DBSetNested(group, field, val) end
end
local function BindNestedSlider(slider, group, field)
  local v = DBGetNested(group, field)
  if v then slider:SetValue(v) end
  slider.onChanged = function(val) DBSetNested(group, field, val) end
end
local function BindNestedDropdown(dd, group, field)
  local v = DBGetNested(group, field)
  if v ~= nil then dd:SetValue(v) end
  dd.onChanged = function(val) DBSetNested(group, field, val) end
end
local function BindNestedColorButton(colorBtn, group, field)
  local v = DBGetNested(group, field)
  if v and type(v) == "table" then colorBtn:SetColor(v[1], v[2], v[3], v[4]) end
  colorBtn.onChanged = function(val) DBSetNested(group, field, val) end
end

-- Rangee police + taille + contour, partagee par les onglets Niveau d'objet /
-- Enchantement / Durabilite (memes 3 champs partout : font/fontSize/fontStyle)
local function BuildFontRow(container, ctx, group, W)
  local w3 = math.floor((W - 16) / 3)
  local ddFont = SW.CreateDropdown(container, L["SETTINGS_ARMORY_FONT"], ns.GetFontList(), w3)
  BindNestedDropdown(ddFont, group, "font")
  local slSize = SW.CreateSlider(container, L["SETTINGS_ARMORY_FONT_SIZE"], 6, 22, 1, w3)
  BindNestedSlider(slSize, group, "fontSize")
  local rgOutline = SW.CreateRadioGroup(container, {
    { value = "",             label = L["SETTINGS_ARMORY_OUTLINE_NONE"] },
    { value = "OUTLINE",      label = L["SETTINGS_ARMORY_OUTLINE_THIN"] },
    { value = "THICKOUTLINE", label = L["SETTINGS_ARMORY_OUTLINE_THICK"] },
    { value = "SLUG",         label = L["TEXT_OUTLINE_SLUG"] },
  }, w3)
  BindNestedDropdown(rgOutline, group, "fontStyle")
  ctx:AddRow(8, ddFont, slSize, rgOutline)
end

-- Rangee decalage X/Y, partagee par plusieurs onglets
local function BuildOffsetRow(container, ctx, group, W, xMin, xMax, yMin, yMax)
  local w2 = math.floor((W - 8) / 2)
  local slX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], xMin, xMax, 1, w2)
  BindNestedSlider(slX, group, "xOffset")
  local slY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], yMin, yMax, 1, w2)
  BindNestedSlider(slY, group, "yOffset")
  ctx:AddRow(8, slX, slY)
end

function Build.CharacterArmoryLook(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local dbKey = "characterArmory"

  local cbLayout = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_ENABLE_LAYOUT"], L["SETTINGS_ARMORY_ENABLE_LAYOUT_TT"], W))
  BindCheckbox(cbLayout, dbKey, "layoutEnabled")

  local w2 = math.floor((W - 8) / 2)
  local slZone = SW.CreateSlider(container, L["SETTINGS_ARMORY_ZONE_WIDTH"], -50, 300, 1, w2)
  BindSlider(slZone, dbKey, "zoneWidth")

  local slHeight = SW.CreateSlider(container, L["SETTINGS_ARMORY_FRAME_HEIGHT"], 420, 480, 1, w2)
  BindSlider(slHeight, dbKey, "frameHeight")
  ctx:AddRow(8, slZone, slHeight)

  local slModelScale = ctx:Add(SW.CreateSlider(container, L["SETTINGS_ARMORY_MODEL_SCALE"], 0.5, 2.0, 0.05, W))
  BindSlider(slModelScale, dbKey, "modelScale")

  local cbHideCorners = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_HIDE_CORNERS"], L["SETTINGS_ARMORY_HIDE_CORNERS_TT"], W))
  BindCheckbox(cbHideCorners, dbKey, "hideCorners")

  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryIlvl(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local rg = ctx:Add(SW.CreateRadioGroup(container, {
    { value = "NONE",     label = L["SETTINGS_ARMORY_ILVL_NONE"] },
    { value = "QUALITY",  label = L["SETTINGS_ARMORY_ILVL_QUALITY"] },
    { value = "GRADIENT", label = L["SETTINGS_ARMORY_ILVL_GRADIENT"] },
  }, W))
  BindNestedDropdown(rg, "ilvl", "colorType")
  BuildFontRow(container, ctx, "ilvl", W)
  BuildOffsetRow(container, ctx, "ilvl", W, -40, 150, -22, 3)
  ctx:Finalize()
  return ctx.widgets
end

-- Niveau d'objet GLOBAL (natif Blizzard, CharacterStatsPane.ItemLevelFrame.Value,
-- juste au-dessus de "Caracteristiques") -- distinct du niveau d'objet PAR
-- OBJET ci-dessus (cf. Modules/CharacterArmory.lua:ApplyGlobalIlvlConfig).
function Build.CharacterArmoryGlobalIlvl(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local cbEnable = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_GLOBAL_ILVL_ENABLE"], L["SETTINGS_ARMORY_GLOBAL_ILVL_ENABLE_TT"], W))
  BindNestedCheckbox(cbEnable, "globalIlvl", "enabled")
  BuildFontRow(container, ctx, "globalIlvl", W)
  local colColor = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_ARMORY_GLOBAL_ILVL_COLOR"], W))
  BindNestedColorButton(colColor, "globalIlvl", "color")
  local cbSpecColor = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_USE_SPEC_COLOR"], L["SETTINGS_USE_SPEC_COLOR_TT"], W))
  BindNestedCheckbox(cbSpecColor, "globalIlvl", "useSpecColor")
  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryEnchant(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local cbReal = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_ENCHANT_SHOWREAL"], L["SETTINGS_ARMORY_ENCHANT_SHOWREAL_TT"], W))
  BindNestedCheckbox(cbReal, "enchant", "showReal")
  local cbIconOnly = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_ENCHANT_ICONONLY"], L["SETTINGS_ARMORY_ENCHANT_ICONONLY_TT"], W))
  BindNestedCheckbox(cbIconOnly, "enchant", "iconOnly")
  BuildFontRow(container, ctx, "enchant", W)
  BuildOffsetRow(container, ctx, "enchant", W, -10, 40, -13, 13)
  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryGem(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local cbTooltips = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_ARMORY_SHOW_GEMS"], nil, W))
  BindNestedCheckbox(cbTooltips, "gem", "showTooltips")
  local slSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_ARMORY_GEM_SIZE"], 8, 30, 1, W))
  BindNestedSlider(slSize, "gem", "size")
  BuildOffsetRow(container, ctx, "gem", W, -40, 150, -10, 22)
  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryTransmog(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local cbArrow = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_ENABLE_TRANSMOG"], L["SETTINGS_ARMORY_ENABLE_TRANSMOG_TT"], W))
  BindNestedCheckbox(cbArrow, "transmog", "enableArrow")

  local slSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_ARMORY_TRANSMOG_SIZE"], 8, 32, 1, W))
  BindNestedSlider(slSize, "transmog", "iconSize")

  local cbGlow = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_ARMORY_TRANSMOG_GLOW"], nil, W))
  BindNestedCheckbox(cbGlow, "transmog", "enableGlow")

  local glowOptions = {}
  for i, def in ipairs(ns.GLOW_DEFS or {}) do glowOptions[#glowOptions + 1] = { value = i, text = def.name } end
  local ddGlowStyle = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_ARMORY_TRANSMOG_GLOW_STYLE"], glowOptions, 220))
  BindNestedDropdown(ddGlowStyle, "transmog", "glowStyleIdx")

  local colGlow = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_ARMORY_TRANSMOG_GLOW_COLOR"], W))
  BindNestedColorButton(colGlow, "transmog", "glowColor")
  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryGradient(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local cbEnable = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_ARMORY_GRADIENT_ENABLE"], L["SETTINGS_ARMORY_GRADIENT_ENABLE_TT"], W))
  BindNestedCheckbox(cbEnable, "gradient", "enable")

  local colColor = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_ARMORY_GRADIENT_COLOR"], W))
  BindNestedColorButton(colColor, "gradient", "color")

  local cbQuality = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_ARMORY_GRADIENT_QUALITY"], nil, W))
  BindNestedCheckbox(cbQuality, "gradient", "quality")

  local cbSetArmor = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_ARMORY_GRADIENT_SET_ARMOR"], nil, W))
  BindNestedCheckbox(cbSetArmor, "gradient", "setArmor")

  local colSetArmor = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_ARMORY_GRADIENT_SET_ARMOR_COLOR"], W))
  BindNestedColorButton(colSetArmor, "gradient", "setArmorColor")

  local colWarning = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_ARMORY_GRADIENT_WARNING_COLOR"], W))
  BindNestedColorButton(colWarning, "gradient", "warningColor")

  local colWarningBar = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_ARMORY_GRADIENT_WARNING_BAR_COLOR"], W))
  BindNestedColorButton(colWarningBar, "gradient", "warningBarColor")
  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryDurability(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local rg = ctx:Add(SW.CreateRadioGroup(container, {
    { value = "Always",      label = L["SETTINGS_ARMORY_DURABILITY_ALWAYS"] },
    { value = "DamagedOnly", label = L["SETTINGS_ARMORY_DURABILITY_DAMAGED"] },
    { value = "Hide",        label = HIDE or L["SETTINGS_ARMORY_DURABILITY_DISPLAY"] },
  }, W))
  BindNestedDropdown(rg, "durability", "display")
  BuildFontRow(container, ctx, "durability", W)
  BuildOffsetRow(container, ctx, "durability", W, -10, 150, -22, 5)
  local slThreshold = ctx:Add(SW.CreateSlider(container, L["SETTINGS_ARMORY_DURABILITY_THRESHOLD"], 0, 100, 1, W))
  BindNestedSlider(slThreshold, "durability", "warnPct")
  ctx:Finalize()
  return ctx.widgets
end

function Build.CharacterArmoryBackground(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local bgOptions = {
    { value = "HIDE",          text = HIDE },
    { value = "CUSTOM",        text = CUSTOM },
    { value = "CLASS",         text = CLASS },
    { value = "Arena-bliz",    text = ARENA },
    { value = "Space",         text = L["SETTINGS_ARMORY_BG_SPACE"] },
    { value = "TheEmpire",     text = L["SETTINGS_ARMORY_BG_EMPIRE"] },
    { value = "Castle",        text = L["SETTINGS_ARMORY_BG_CASTLE"] },
    { value = "Alliance-text", text = FACTION_ALLIANCE },
    { value = "Horde-text",    text = FACTION_HORDE },
  }
  local ddBg = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_ARMORY_BG_SELECT"], bgOptions, 220))
  ddBg:SetValue(DBGetNested("background", "selectedBG"))

  -- Champ texture personnalisee : visible seulement si selectedBG == CUSTOM
  local row = CreateFrame("Frame", nil, container)
  row:SetSize(W, 32)
  local lbl = row:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 11)
  lbl:SetTextColor(unpack(Theme.textNormal))
  lbl:SetText(L["SETTINGS_ARMORY_BG_CUSTOM_TEXTURE"])
  lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  SW.StyleEditBox(eb)
  eb:SetSize(W - 8, 20)
  eb:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -2)
  eb:SetAutoFocus(false)
  eb:SetText(DBGetNested("background", "customTexture") or "")
  eb:SetScript("OnEnterPressed", function(self) DBSetNested("background", "customTexture", self:GetText()); self:ClearFocus() end)
  eb:SetScript("OnEditFocusLost", function(self) DBSetNested("background", "customTexture", self:GetText()) end)
  row:SetShown(DBGetNested("background", "selectedBG") == "CUSTOM")
  ctx:Add(row)

  ddBg.onChanged = function(val)
    DBSetNested("background", "selectedBG", val)
    row:SetShown(val == "CUSTOM")
  end
  ctx:Finalize()
  return ctx.widgets
end


do
  local function CACollapsed(key)
    local db = ns.DB and ns.DB.characterArmory
    return db and db.uiCollapsed and db.uiCollapsed[key] and true or false
  end
  local function CAInvalidateKeepScroll()
    local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll()
    if _invalidateCategory then _invalidateCategory("characterArmory") end
    if savedScroll then
      C_Timer.After(0, function()
        if scrollFrame then scrollFrame:SetVerticalScroll(savedScroll) end
      end)
    end
  end
  local function CAToggleCollapsed(key)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.characterArmory then ns.DB.characterArmory = {} end
    if not ns.DB.characterArmory.uiCollapsed then ns.DB.characterArmory.uiCollapsed = {} end
    ns.DB.characterArmory.uiCollapsed[key] = not CACollapsed(key)
    CAInvalidateKeepScroll()
  end

  local function CACollapsibleSection(container, ctx, W, key, label, buildFn)
    ctx:Spacer(4)
    local collapsed = CACollapsed(key)
    local header = SW.CreateSectionHeader(container, (collapsed and "+ " or "- ") .. label, W)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -ctx.y)
    header:Show()

    local hitbox = CreateFrame("Button", nil, header)
    hitbox:SetAllPoints(header)
    hitbox:SetFrameLevel(header:GetFrameLevel() + 1)
    local hl = hitbox:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.06); hl:Hide()
    hitbox:SetScript("OnEnter", function() hl:Show() end)
    hitbox:SetScript("OnLeave", function() hl:Hide() end)
    hitbox:SetScript("OnClick", function() CAToggleCollapsed(key) end)

    ctx.y = ctx.y + header:GetHeight() + 2
    table.insert(ctx.widgets, header)
    if collapsed then return end

    local detail = CreateFrame("Frame", nil, container)
    detail:SetWidth(W)
    buildFn(detail) -- construit + Finalize (SetHeight) tout seul
    detail:ClearAllPoints()
    detail:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -ctx.y)
    detail:Show()
    ctx.y = ctx.y + detail:GetHeight() + 2
    table.insert(ctx.widgets, detail)
  end

  Build.CharacterSheet = function(container)
    local ctx = NewLayout(container)
    local W = CONTENT_W
    local dbKey = "characterArmory"

    ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_CHARACTER_ARMORY"], W))
    local cbEnable = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_ARMORY_ENABLE"], L["SETTINGS_ARMORY_ENABLE_TT"], W))
    BindCheckbox(cbEnable, dbKey, "enabled")
    local cbWarning = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_ARMORY_SHOW_WARNING"], L["SETTINGS_ARMORY_SHOW_WARNING_TT"], W))
    BindCheckbox(cbWarning, dbKey, "showWarning")
    ctx:Spacer(10)

    CACollapsibleSection(container, ctx, W, "look",       L["SETTINGS_ARMORY_TAB_LOOK"],       Build.CharacterArmoryLook)
    CACollapsibleSection(container, ctx, W, "ilvl",       L["SETTINGS_ARMORY_TAB_ILVL"],       Build.CharacterArmoryIlvl)
    CACollapsibleSection(container, ctx, W, "globalIlvl", L["SETTINGS_ARMORY_TAB_GLOBAL_ILVL"], Build.CharacterArmoryGlobalIlvl)
    CACollapsibleSection(container, ctx, W, "enchant",    L["SETTINGS_ARMORY_TAB_ENCHANT"],    Build.CharacterArmoryEnchant)
    CACollapsibleSection(container, ctx, W, "gem",        L["SETTINGS_ARMORY_TAB_GEM"],        Build.CharacterArmoryGem)
    CACollapsibleSection(container, ctx, W, "transmog",   L["SETTINGS_ARMORY_TAB_TRANSMOG"],   Build.CharacterArmoryTransmog)
    CACollapsibleSection(container, ctx, W, "gradient",   L["SETTINGS_ARMORY_TAB_GRADIENT"],   Build.CharacterArmoryGradient)
    CACollapsibleSection(container, ctx, W, "durability", L["SETTINGS_ARMORY_TAB_DURABILITY"], Build.CharacterArmoryDurability)
    CACollapsibleSection(container, ctx, W, "background", L["SETTINGS_ARMORY_TAB_BACKGROUND"], Build.CharacterArmoryBackground)

    ctx:Finalize()
  end
end

-- Page dediee minimaliste : un seul reglage (enabled) + la taille du curseur.
function Build.BigCursor(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_MOD_BIG_CURSOR"], W))
  local cbBC = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_BIGCURSOR_ENABLE"], L["SETTINGS_MOD_BIG_CURSOR_TT"], W))
  BindCheckbox(cbBC, "bigCursor", "enabled")
  -- cursorSize est un INDEX Blizzard (cursorSizePreferred), pas un facteur
  -- d'echelle continu -- 1 a 4 (0 = taille normale, jamais propose ici
  -- puisque le but de ce curseur est justement d'agrandir), cf.
  -- Modules/BigCursor.lua et Config/Defaults.lua pour le detail des tailles
  -- en pixels par palier.
  local slBC = ctx:Add(SW.CreateSlider(container, L["SETTINGS_BIGCURSOR_SIZE"], 1, 4, 1, W))
  BindSlider(slBC, "bigCursor", "cursorSize")
  ctx:Finalize()
  return ctx.widgets
end

-- Popup "copier le lien" -- variante compacte (1 ligne) de ShowExportPopup
-- (meme habillage visuel, meme convention SetFocus+HighlightText pour que
-- Ctrl+A/Ctrl+C marchent immediatement) : WoW n'expose aucune API pour
-- ouvrir une URL dans un navigateur depuis un addon (sandbox de securite),
-- donc "copier le lien pour l'ouvrir soi-meme ailleurs" EST la solution,
-- pas un simple repli.
local _copyLinkPopup
local function ShowCopyLinkPopup(title, url)
  if not _copyLinkPopup then
    local f = CreateFrame("Frame", "AishCoreCopyLinkPopup", UIParent, "BackdropTemplate")
    f:SetSize(420, 132)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints(); solidBg:SetColorTexture(0, 0, 0, 1)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets   = { left=11, right=12, top=12, bottom=11 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.98)

    local titleLbl = f:CreateFontString(nil, "OVERLAY")
    titleLbl:SetFont(ns.Media.fontGui, 13)
    titleLbl:SetTextColor(1, 0.88, 0.3)
    titleLbl:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -16)
    f._titleLbl = titleLbl

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont(ns.Media.fontGui, 9)
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText(L["SETTINGS_SELECT_COPY_HINT"])
    hint:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local ebBd = CreateFrame("Frame", nil, f, "BackdropTemplate")
    ebBd:SetPoint("TOPLEFT",  f, "TOPLEFT",  18, -60)
    ebBd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -60)
    ebBd:SetHeight(24)
    ebBd:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    ebBd:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    ebBd:SetBackdropBorderColor(unpack(ns.Theme.border))

    local eb = CreateFrame("EditBox", nil, ebBd)
    eb:SetAutoFocus(false)
    eb:SetFont(ns.Media.fontGui, 11, "")
    eb:SetTextColor(1, 1, 1)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetPoint("TOPLEFT",     ebBd, "TOPLEFT",     0, 0)
    eb:SetPoint("BOTTOMRIGHT", ebBd, "BOTTOMRIGHT", 0, 0)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f._eb = eb

    local doneBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    doneBtn:SetSize(130, 26)
    doneBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    doneBtn:SetText(L["SETTINGS_CLOSE"])
    doneBtn:SetScript("OnClick", function() f:Hide() end)

    _copyLinkPopup = f
  end
  _copyLinkPopup._titleLbl:SetText(title or L["SETTINGS_COPY_LINK_TITLE"])
  _copyLinkPopup._eb:SetText(url or "")
  _copyLinkPopup._eb:HighlightText()
  _copyLinkPopup:Show()
  _copyLinkPopup._eb:SetFocus()
end

-- BUILD : Heroic Support -- page de remerciements/soutien (categorie Global)
--
-- MODIFIEZ ICI pour brancher les vraies infos (liens + images du carrousel) :
-- les valeurs ci-dessous sont des PLACEHOLDERS en attendant les vrais liens/
-- visuels. Chaque entree de HEROIC_SUPPORT_LINKS est une icone cliquable
-- qui ouvre la popup "copier le lien" (WoW ne peut pas ouvrir un navigateur
-- depuis un addon). Chaque entree de HEROIC_SUPPORT_IMAGES est une image du
-- carrousel (textures existantes de l'addon en attendant les vrais visuels
-- -- cf. SW.CreateCarousel : GIFs non supportes, images statiques uniquement).
-- Logos "wordmark" (pas des icones carrees) : ratio W/H propre a chaque
-- fichier (cf. Media/Logo/*.tga), necessaire pour les dimensionner sans les
-- deformer -- imgW/imgH = dimensions reelles du fichier.
local HEROIC_SUPPORT_LINKS = {
  { icon = "Interface\\AddOns\\AishCore\\Media\\Logo\\kofi",      imgW = 128, imgH = 35,  label = "Ko-fi",      url = "https://ko-fi.com/aishuutv" },
  { icon = "Interface\\AddOns\\AishCore\\Media\\Logo\\discord",   imgW = 128, imgH = 19,  label = "Discord",    url = "https://discord.gg/xamhJnSsbp" },
  { icon = "Interface\\AddOns\\AishCore\\Media\\Logo\\CurseForge", imgW = 776, imgH = 150, label = "CurseForge", url = "https://www.curseforge.com/wow/addons/REMPLACER" },
}

-- Toutes les images font 1374x552 (ratio verifie via les fichiers, cf.
-- CAROUSEL_IMG_RATIO ci-dessous) : chemin AVEC extension .jpg -- contrairement
-- au reste de l'addon (.tga/.blp), qui laisse WoW resoudre l'extension toute
-- seule, ce n'est fiable qu'avec ces 2 formats. A verifier en jeu : si une
-- image reste invisible/noire, le client ne sait probablement pas charger un
-- .jpg via Texture:SetTexture (a reconvertir en .tga/.png dans ce cas).
-- Legendes : PLACEHOLDERS en attendant les vraies (l'utilisateur les
-- remplacera lui-meme).
-- Legendes : passees par L[...] (SETTINGS_HEROIC_CAROUSEL_N) -- texte VISIBLE
-- en jeu (legende sous l'image ET tooltip au survol, cf. SW.CreateCarousel/
-- UI/SharedWidgets.lua), pas juste un commentaire de dev : etaient avant en
-- dur en francais, jamais traduites (confirme par l'historique -- ce carrousel
-- n'a jamais eu de version anglaise depuis sa creation).
local HEROIC_SUPPORT_IMAGES = {
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\reshade.jpg",       tooltip = L["SETTINGS_HEROIC_CAROUSEL_1"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\fx_2.jpg",           tooltip = L["SETTINGS_HEROIC_CAROUSEL_2"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\modelpicker_1.jpg",  tooltip = L["SETTINGS_HEROIC_CAROUSEL_3"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\fx_1.jpg",           tooltip = L["SETTINGS_HEROIC_CAROUSEL_4"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\colortheme_2.jpg",   tooltip = L["SETTINGS_HEROIC_CAROUSEL_5"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\colortheme_3.jpg",   tooltip = L["SETTINGS_HEROIC_CAROUSEL_6"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\skyriding_1.jpg",    tooltip = L["SETTINGS_HEROIC_CAROUSEL_7"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\addons_1.jpg",       tooltip = L["SETTINGS_HEROIC_CAROUSEL_8"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\addons_2.jpg",       tooltip = L["SETTINGS_HEROIC_CAROUSEL_9"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\addons_3.jpg",       tooltip = L["SETTINGS_HEROIC_CAROUSEL_10"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\addons_4.jpg",       tooltip = L["SETTINGS_HEROIC_CAROUSEL_11"] },
  { texture = "Interface\\AddOns\\AishCore\\Media\\Carousel\\nameplates_1.jpg",   tooltip = L["SETTINGS_HEROIC_CAROUSEL_12"] },
}
-- Ratio EXACT des images (552/1374) : evite tout etirement -- SW.CreateCarousel
-- recoit une hauteur calculee depuis ce ratio plutot qu'un pourcentage approximatif.
local CAROUSEL_IMG_RATIO = 552 / 1374

-- Perks "Heroic support debloque" : une entree par ligne (icone coche +
-- texte), cf. colonne gauche du bloc 2 colonnes plus bas.
local HEROIC_SUPPORT_PERKS = {
  L["SETTINGS_HEROIC_PERK_1"],  L["SETTINGS_HEROIC_PERK_2"],
  L["SETTINGS_HEROIC_PERK_3"],  L["SETTINGS_HEROIC_PERK_4"],
  L["SETTINGS_HEROIC_PERK_5"],  L["SETTINGS_HEROIC_PERK_6"],
  L["SETTINGS_HEROIC_PERK_7"],  L["SETTINGS_HEROIC_PERK_8"],
  L["SETTINGS_HEROIC_PERK_9"],  L["SETTINGS_HEROIC_PERK_10"],
  L["SETTINGS_HEROIC_PERK_11"], L["SETTINGS_HEROIC_PERK_12"],
}
-- Texture standard des cases a cocher Blizzard (UICheckButtonTemplate) : sert
-- ici de puce, simplement teintee en dore (CAROUSEL_GOLD) plutot que blanche.
local HEROIC_PERK_CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"

function Build.HeroicSupport(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_HEROIC_SUPPORT"], W))

  -- Carrousel (bandeau rectangulaire + miniatures + auto-scroll) -- legerement
  -- reduit et centre (pas pleine largeur) : la bordure du cadre deborde de
  -- quelques px hors du cadre lui-meme, et pleine largeur ca la faisait
  -- rogner par le bord gauche de la zone de contenu (confirme en jeu).
  local carouselW = W - 60

  -- Texte de remerciement : legerement plus etroit que le carrousel (pas
  -- juste toute la largeur du contenu) et centre au-dessus, meme technique
  -- que le carrousel (ancrage "TOP" sans TOPLEFT -- centre automatiquement
  -- puisque plus etroit que container). Un peu d'air au-dessus (sous
  -- l'en-tete de section) et en-dessous (avant le carrousel).
  ctx:Spacer(8)
  local thanks = container:CreateFontString(nil, "OVERLAY")
  thanks:SetFont(ns.Media.fontGui, 12)
  thanks:SetTextColor(unpack(ns.Theme.textNormal))
  thanks:SetJustifyH("LEFT")
  thanks:SetWordWrap(true)
  local thanksW = carouselW - 40
  thanks:SetWidth(thanksW)
  thanks:SetText(L["SETTINGS_HEROIC_SUPPORT_THANKYOU"])
  thanks:SetHeight(thanks:GetStringHeight())
  thanks:ClearAllPoints()
  thanks:SetPoint("TOP", container, "TOP", 0, -ctx.y)
  ctx.y = ctx.y + thanks:GetHeight() + 2
  table.insert(ctx.widgets, thanks)
  ctx:Spacer(10)

  local carousel = SW.CreateCarousel(container, carouselW, math.floor(carouselW * CAROUSEL_IMG_RATIO), HEROIC_SUPPORT_IMAGES, 6)
  carousel:ClearAllPoints()
  carousel:SetPoint("TOP", container, "TOP", 0, -ctx.y)
  ctx.y = ctx.y + carousel:GetHeight() + 2
  table.insert(ctx.widgets, carousel)
  ctx:Spacer(18)

  -- Bloc 2 colonnes sous le carrousel, centre (meme largeur/alignement que
  -- le carrousel juste au-dessus) : a gauche la liste doree des avantages
  -- ("Heroic support debloque"), a droite les 3 logos de liens empiles
  -- verticalement (au lieu de la rangee horizontale d'avant), separes par un
  -- hairline vertical -- meme rendu (couleur + degrade) que le hairline
  -- horizontal des en-tetes de section, juste tourne a 90 deg.
  local LOGO_H, BAR_H, BAR_GAP, LOGO_VGAP = 28, 2, 4, 18
  local PERK_ICON, PERK_ICON_GAP, PERK_ROW_GAP = 12, 6, 8
  local COL_GAP = 22 -- de chaque cote du divider
  local PERKS_INDENT = 20 -- colonne gauche (en-tete + liste) decalee vers la droite
  local THANKS_GAP, THANKS_FONT_SIZE = 16, 10 -- espace + police du bloc credits sous les logos

  local logoWidths, logosColW = {}, 0
  for i, entry in ipairs(HEROIC_SUPPORT_LINKS) do
    local w = math.floor(LOGO_H * (entry.imgW / entry.imgH))
    logoWidths[i] = w
    if w > logosColW then logosColW = w end
  end

  local blockW = carouselW
  local perksColW = blockW - logosColW - COL_GAP * 2 - 1
  local perksTextW = perksColW - PERKS_INDENT

  local block = CreateFrame("Frame", nil, container)
  block:SetWidth(blockW)

  -- Colonne gauche : en-tete souligne + liste a coches dorees, le tout
  -- indente de PERKS_INDENT (bord droit de la colonne inchange, seul le
  -- bord gauche rentre) -- cf. demande utilisateur.
  local perksHeader = block:CreateFontString(nil, "OVERLAY")
  perksHeader:SetFont(ns.Media.fontGui, 13)
  perksHeader:SetTextColor(unpack(SW.HEROIC_GOLD))
  perksHeader:SetJustifyH("LEFT")
  perksHeader:SetWordWrap(true)
  perksHeader:SetWidth(perksTextW)
  perksHeader:SetText(L["SETTINGS_HEROIC_PERKS_HEADER"])
  perksHeader:SetPoint("TOPLEFT", block, "TOPLEFT", PERKS_INDENT, 0)

  -- Soulignement : pas de style "underline" natif sur un FontString --
  -- simple hairline doree calee sur la largeur reelle du texte (pas toute la
  -- colonne, un vrai soulignement de mot).
  local headerUnderline = block:CreateTexture(nil, "ARTWORK")
  headerUnderline:SetHeight(1)
  headerUnderline:SetColorTexture(unpack(SW.HEROIC_GOLD))
  headerUnderline:SetPoint("TOPLEFT", perksHeader, "BOTTOMLEFT", 0, -2)
  headerUnderline:SetWidth(math.max(1, perksHeader:GetStringWidth()))

  local py = perksHeader:GetStringHeight() + 2 + 6 + 8

  for _, perkText in ipairs(HEROIC_SUPPORT_PERKS) do
    local icon = block:CreateTexture(nil, "OVERLAY")
    icon:SetSize(PERK_ICON, PERK_ICON)
    icon:SetTexture(HEROIC_PERK_CHECK_TEX)
    icon:SetVertexColor(unpack(SW.HEROIC_GOLD))

    local line = block:CreateFontString(nil, "OVERLAY")
    line:SetFont(ns.Media.fontGui, 12)
    line:SetTextColor(unpack(SW.HEROIC_GOLD))
    line:SetJustifyH("LEFT")
    line:SetWordWrap(true)
    line:SetWidth(perksTextW - PERK_ICON - PERK_ICON_GAP)
    line:SetText(perkText)

    local rowH = math.max(PERK_ICON, line:GetStringHeight())
    icon:SetPoint("TOPLEFT", block, "TOPLEFT", PERKS_INDENT, -(py + math.floor((rowH - PERK_ICON) / 2)))
    line:SetPoint("TOPLEFT", block, "TOPLEFT", PERKS_INDENT + PERK_ICON + PERK_ICON_GAP, -py)
    py = py + rowH + PERK_ROW_GAP
  end
  local perksColH = py - PERK_ROW_GAP

  -- Colonne droite : les 3 logos, un au-dessus de l'autre, chacun centre
  -- dans la colonne (largeurs differentes -- ratio propre a chaque fichier).
  local logosX = perksColW + COL_GAP * 2 + 1
  local ly = 0
  for i, entry in ipairs(HEROIC_SUPPORT_LINKS) do
    local w = logoWidths[i]
    local btn = CreateFrame("Button", nil, block)
    btn:SetSize(w, LOGO_H)
    btn:SetPoint("TOPLEFT", block, "TOPLEFT", logosX + math.floor((logosColW - w) / 2), -ly)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(entry.icon)
    local bar = btn:CreateTexture(nil, "OVERLAY")
    bar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -BAR_GAP)
    bar:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -BAR_GAP)
    bar:SetHeight(BAR_H)
    bar:SetColorTexture(unpack(SW.HEROIC_GOLD))
    bar:Hide()
    btn:SetScript("OnClick", function() ShowCopyLinkPopup(entry.label, entry.url) end)
    btn:SetScript("OnEnter", function(self)
      bar:Show()
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(entry.label, 1, 1, 1)
      GameTooltip:AddLine(entry.url, 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
      bar:Hide()
      GameTooltip:Hide()
    end)
    ly = ly + LOGO_H + BAR_GAP + BAR_H + LOGO_VGAP
  end
  local logosColH = ly - LOGO_VGAP

  local colH = math.max(perksColH, logosColH)
  block:SetHeight(colH)

  -- Divider vertical, meme rendu (couleur + degrade) que le hairline des
  -- en-tetes de section (SW.CreateSectionHeader) -- degrade du haut (dore,
  -- opaque) vers le bas (dore assombri, quasi transparent).
  local divider = block:CreateTexture(nil, "ARTWORK")
  divider:SetWidth(1)
  divider:SetHeight(colH)
  divider:SetPoint("TOPLEFT", block, "TOPLEFT", perksColW + COL_GAP, 0)
  divider:SetColorTexture(1, 1, 1, 1)
  local g = SW.HEROIC_GOLD
  pcall(function()
    if CreateColor then
      divider:SetGradient("VERTICAL",
        CreateColor(g[1] * 0.20, g[2] * 0.20, g[3] * 0.20, 0.10),
        CreateColor(g[1], g[2], g[3], 0.85))
    end
  end)

  block:ClearAllPoints()
  block:SetPoint("TOP", container, "TOP", 0, -ctx.y)
  ctx.y = ctx.y + colH + 2
  table.insert(ctx.widgets, block)
  ctx:Spacer(THANKS_GAP)

  -- "Special Thanks" : sous les 2 colonnes (pas dans la colonne des logos),
  -- pleine largeur du bloc et centre, meme technique que le texte de
  -- remerciement/le carrousel plus haut.
  local specialThanks = container:CreateFontString(nil, "OVERLAY")
  specialThanks:SetFont(ns.Media.fontGui, THANKS_FONT_SIZE)
  specialThanks:SetTextColor(unpack(ns.Theme.textDim))
  specialThanks:SetJustifyH("LEFT")
  specialThanks:SetWordWrap(true)
  specialThanks:SetWidth(blockW)
  specialThanks:SetText(L["SETTINGS_HEROIC_SPECIAL_THANKS"])
  specialThanks:SetHeight(specialThanks:GetStringHeight())
  specialThanks:ClearAllPoints()
  specialThanks:SetPoint("TOP", container, "TOP", 0, -ctx.y)
  ctx.y = ctx.y + specialThanks:GetHeight() + 2
  table.insert(ctx.widgets, specialThanks)

  ctx:Finalize()
  return ctx.widgets
end

-- Definition des categories
local CATEGORIES = {
  {
    id    = "modulesOverview",
    label = L["SETTINGS_CAT_MODULES"],
    icon  = "Interface\\Icons\\INV_Misc_Gear_01",
    build = Build.ModulesOverview,
  },
  {
    id    = "profiles",
    label = L["SETTINGS_SEC_PROFILES"],
    icon  = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    build = Build.Profiles,
  },
  {
    id    = "heroicSupport",
    label = L["SETTINGS_CAT_HEROIC_SUPPORT"],
    icon  = "Interface\\Icons\\Achievement_GuildPerk_MobileBanking",
    build = Build.HeroicSupport,
  },
  {
    id    = "castBar",
    label = L["SETTINGS_SEC_CAST_BAR"],
    icon  = "Interface\\Icons\\spell_holy_borrowedtime",
    build = Build.CastBar,
  },
  {
    id    = "targetCastBar",
    label = L["SETTINGS_CAT_TARGET_CAST"],
    icon  = "Interface\\Icons\\ability_warrior_charge",
    build = Build.TargetCastBar,
  },
  {
    id    = "skyriding",
    label = L["SETTINGS_CAT_SKYRIDING"],
    icon  = "Interface\\Icons\\ability_mount_drake_twilight",
    build = Build.Skyriding,
  },
  {
    id    = "topTargetBar",
    label = L["SETTINGS_CAT_TOP_TARGET"],
    icon  = "Interface\\Icons\\ability_hunter_snipershot",
    build = Build.TopTargetBar,
  },
  {
    id    = "targetAuras",
    label = L["SETTINGS_CAT_TARGET_AURAS"],
    icon  = "Interface\\Icons\\spell_holy_divinespirit",
    build = Build.TargetAuras,
  },
  {
    id    = "groupNumber",
    label = L["SETTINGS_SEC_GROUP_NUMBER"],
    icon  = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    build = Build.GroupNumber,
  },
  {
    id    = "unitBars",
    label = L["SETTINGS_CAT_HEALTH_BARS"],
    icon  = "Interface\\Icons\\ability_warrior_defensivestance",
    build = Build.UnitBars,
  },
  {
    id    = "resourceCircle",
    label = L["SETTINGS_CAT_CENTRAL_CIRCLE"],
    icon  = "Interface\\Icons\\ability_mage_incantersabsorbtion",
    build = Build.ResourceCircle,
  },
  {
    id    = "outOfCombat",
    label = L["SETTINGS_CAT_OOC_CIRCLES"],
    icon  = "Interface\\Icons\\spell_holy_sealofsacrifice",
    build = Build.OutOfCombat,
  },
  {
    id    = "priorityBar",
    label = L["SETTINGS_SEC_PRIORITY_BAR"],
    icon  = "Interface\\Icons\\ability_warrior_savageblow",
    build = Build.PriorityBar,
  },
  {
    id    = "rotationHelper",
    label = L["SETTINGS_CAT_ROTATION_HELPER"],
    icon  = "Interface\\Icons\\ability_hunter_mastermarksman",
    build = Build.RotationHelper,
  },
  {
    id    = "spellEffects",
    label = L["SETTINGS_SEC_3D_ANIMATIONS"],
    icon  = "Interface\\Icons\\spell_arcane_arcane01",
    build = Build.SpellEffects,
  },
  {
    id    = "xpBar",
    label = L["SETTINGS_CAT_XP_BAR"],
    icon  = "Interface\\Icons\\inv_misc_note_01",
    build = Build.XPBar,
  },
  {
    id    = "afkMode",
    label = L["SETTINGS_CAT_AFK_MODE"],
    icon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    build = Build.AFKMode,
  },
  {
    id    = "characterArmory",
    label = L["SETTINGS_CAT_CHARACTER_ARMORY"],
    icon  = "Interface\\Icons\\INV_Chest_Cloth_17",
    build = Build.CharacterSheet,
  },
  {
    id    = "colors",
    label = L["SETTINGS_CAT_COLORS"],
    icon  = "Interface\\Icons\\inv_misc_gem_variety_02",
    build = Build.Colors,
  },
  {
    id    = "visibility",
    label = L["SETTINGS_CAT_VISIBILITY"],
    icon  = "Interface\\Icons\\inv_misc_eye_01",
    build = Build.Visibility,
  },
  {
    id    = "cdmEssential",
    label = L["SETTINGS_CAT_CDM_ESSENTIAL"],
    icon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    build = function(c) Build.CDM(c, "cdmEssential") end,
  },
  {
    id    = "cdmUtility",
    label = L["SETTINGS_CAT_CDM_UTILITY"],
    icon  = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    build = function(c) Build.CDM(c, "cdmUtility") end,
  },
  {
    -- Page dediee minimaliste : un seul reglage (enabled).
    id    = "bigCursor",
    label = L["SETTINGS_MOD_BIG_CURSOR"],
    icon  = "Interface\\Icons\\INV_Misc_Spyglass_03",
    build = Build.BigCursor,
  },
  -- Auras & Procs (fusionné depuis AishUIAura)
  {
    id    = "aurasTracked",
    label = L["SETTINGS_CAT_AURAS_TRACKED"],
    icon  = "Interface\\Icons\\inv_misc_note_06",
    build = Build.AurasTactics,
  },
  {
    id    = "aurasIconlist",
    label = L["SETTINGS_CAT_ICON_LIST"],
    icon  = "Interface\\Icons\\spell_shadow_curseofmannoroth",
    build = function(c) Build.AurasRender(c, "iconlist") end,
  },
  {
    id    = "aurasFreebars",
    label = L["SETTINGS_CAT_CIRCLE_BARS"],
    icon  = "Interface\\Icons\\spell_holy_divineprotection",
    build = function(c) Build.AurasRender(c, "freebars") end,
  },
  {
    id    = "aurasIcons",
    label = L["SETTINGS_CAT_ICONS"],
    icon  = "Interface\\Icons\\spell_arcane_prismaticcloak",
    build = function(c) Build.AurasRender(c, "icons") end,
  },
  {
    id    = "aurasCirclebars",
    label = L["SETTINGS_CAT_FREE_BARS"],
    icon  = "Interface\\Icons\\spell_nature_timestop",
    build = function(c) Build.AurasRender(c, "circlebars") end,
  },
  {
    id    = "aurasTotems",
    label = L["SETTINGS_CAT_TOTEMS"],
    icon  = "Interface\\Icons\\spell_nature_totemofwrath",
    build = function(c) Build.AurasRender(c, "totems") end,
  },
  {
    id    = "aurasTrinkets",
    label = L["SETTINGS_CAT_TRINKETS"],
    icon  = "Interface\\Icons\\inv_jewelry_trinketpvp_01",
    build = Build.AurasEquipment,
  },
  {
    id    = "aurasMissingBuffs",
    label = L["AURASDATA_SEC_MISSINGBUFFS_LABEL"],
    icon  = "Interface\\Icons\\spell_holy_greaterheal",
    build = Build.AurasMissingBuffs,
  },
  --[[ -- Effets 3D Auras (désactivé)
  {
    id    = "aurasEffects",
    label = "Effets 3D Auras",
    icon  = "Interface\\Icons\\spell_arcane_arcane04",
    build = Build.AurasEffects,
  },
  --]]
}

-- Groupes de la sidebar (style AishUI : headers parchemin + sections cliquables)
local SIDEBAR_GROUPS = {
  { label = L["SETTINGS_GROUP_GLOBAL"],      ids = { "modulesOverview", "colors", "profiles", "heroicSupport" } },
  { label = L["SETTINGS_GROUP_UNIT_FRAMES"], ids = { "unitBars", "castBar", "targetCastBar", "topTargetBar", "targetAuras", "groupNumber" } },
  { label = L["SETTINGS_GROUP_COMBAT"],      ids = { "resourceCircle", "priorityBar", "cdmEssential", "cdmUtility", "bigCursor", "rotationHelper" } },
  { label = L["SETTINGS_GROUP_WORLD"],       ids = { "outOfCombat", "xpBar", "skyriding", "afkMode", "visibility", "characterArmory" } },
  { label = L["SETTINGS_GROUP_AURAS_PROCS"], ids = { "aurasTracked", "aurasIconlist", "aurasFreebars", "aurasIcons", "aurasCirclebars", "aurasTotems", "aurasTrinkets", "aurasMissingBuffs", "spellEffects" } },
}

-- Table catId → bouton (remplace l'ancien tableau indexé)
local categoryButtons = {}
local _sbSearchFilter = ""

-- Recherche "plein texte" dans le contenu de chaque section (pas seulement
-- son nom) : demande utilisateur -- taper "cd" doit remonter toute section
-- contenant un reglage lie aux CDs quelque part, pas seulement les sections
-- dont le NOM contient "cd". GetOrBuildContainer (defini plus bas, d'ou
-- l'avant-declaration) construit deja paresseusement chaque page au premier
-- besoin et la met en cache pour toute la session (categoryContainers) --
-- on reutilise EXACTEMENT ce meme mecanisme pour l'indexation : aucun
-- risque nouveau, juste declenche plus tot (des la 1ere recherche au lieu
-- d'attendre la navigation manuelle). Le texte extrait (tous les
-- FontString du sous-arbre, checkboxes/sliders/dropdowns/headers inclus)
-- est mis en cache par section, calcule une seule fois par session.
local GetOrBuildContainer -- avant-declaration, assignee plus bas (ligne ~10837)
local _categorySearchIndex = {}

local function CollectFrameText(f, buf)
  local ok = pcall(function()
    for _, region in ipairs({ f:GetRegions() }) do
      if region.GetObjectType and region:GetObjectType() == "FontString" then
        local txt = region:GetText()
        if txt and txt ~= "" then buf[#buf + 1] = txt end
      end
    end
    for _, child in ipairs({ f:GetChildren() }) do
      CollectFrameText(child, buf)
    end
  end)
  if not ok then return end
end

local function GetCategorySearchText(catId)
  local cached = _categorySearchIndex[catId]
  if cached ~= nil then return cached end
  if not GetOrBuildContainer then _categorySearchIndex[catId] = ""; return "" end

  local text = ""
  local ok = pcall(function()
    local entry = GetOrBuildContainer(catId)
    if entry and entry.frame then
      local buf = {}
      CollectFrameText(entry.frame, buf)
      text = table.concat(buf, " "):lower()
    end
  end)
  if not ok then text = "" end

  _categorySearchIndex[catId] = text
  return text
end

-- Etat repli/deploi de chaque groupe (accordeon) : cle = grp.label, valeur =
-- true (replie) / false (deploye). Replie par defaut (cf. BuildSidebar qui
-- initialise chaque groupe a true) ; le groupe contenant activeCategory est
-- toujours force ouvert (cf. containsActive plus bas), independamment de cet
-- etat manuel -- on ne doit jamais pouvoir masquer la section courante.
sidebar._groupCollapsed = sidebar._groupCollapsed or {}

-- Rafraîchit la position et l'état actif de tous les items de la sidebar
local function RefreshSidebar()
  if not sidebar._accContainer then return end
  local filter    = _sbSearchFilter
  local hasFilter = filter ~= ""
  local _gold     = Theme.gold or Theme.accent

  -- Lookup rapide catId → label
  local catLabels = {}
  for _, cat in ipairs(CATEGORIES) do catLabels[cat.id] = cat.label end

  -- Cache tout
  for _, entry in pairs(sidebar._groupEntries or {}) do
    if entry.headerBtn then entry.headerBtn:Hide() end
    for _, btn in pairs(entry.sectionBtns or {}) do btn:Hide() end
  end

  local CAT_HEADER_H   = 26
  local CAT_HEADER_GAP = 10
  local SECTION_H      = 20
  local CAT_TO_SECT    = 2
  local ac = sidebar._accContainer
  local y  = 0

  for _, grp in ipairs(SIDEBAR_GROUPS) do
    local entry = sidebar._groupEntries[grp.label]
    if entry then
      -- Sections matchantes (filtre de recherche)
      local grpLower = grp.label:lower()
      local matchingSections = {}
      local containsActive = false
      for _, cid in ipairs(grp.ids) do
        local lbl = (catLabels[cid] or cid):lower()
        -- La recherche plein-texte (GetCategorySearchText) n'est evaluee que
        -- si rien d'autre n'a deja matche (court-circuit du "or") : evite de
        -- construire/indexer une page pour rien quand le nom seul suffit.
        if (not hasFilter)
            or lbl:find(filter, 1, true)
            or grpLower:find(filter, 1, true)
            or GetCategorySearchText(cid):find(filter, 1, true) then
          matchingSections[#matchingSections + 1] = cid
        end
        if cid == activeCategory then containsActive = true end
      end

      if #matchingSections > 0 then
        -- Header groupe
        if y > 0 then y = y + CAT_HEADER_GAP end
        entry.headerBtn:ClearAllPoints()
        entry.headerBtn:SetPoint("TOPLEFT",  ac, "TOPLEFT",  0, -y)
        entry.headerBtn:SetPoint("TOPRIGHT", ac, "TOPRIGHT", 0, -y)
        entry.headerBtn:Show()
        y = y + CAT_HEADER_H + CAT_TO_SECT

        -- Deploye si : filtre de recherche actif (sinon la recherche ne
        -- trouverait jamais rien dans un groupe replie), OU la section
        -- courante vit dans ce groupe, OU l'utilisateur a explicitement
        -- deplie ce groupe (clic sur le header).
        local expanded = hasFilter or containsActive or (sidebar._groupCollapsed[grp.label] == false)
        entry.headerBtn:SetExpanded(expanded)

        if expanded then
          -- Items section
          for _, cid in ipairs(matchingSections) do
            local btn = entry.sectionBtns[cid]
            if btn then
              btn:ClearAllPoints()
              btn:SetPoint("TOPLEFT",  ac, "TOPLEFT",  0, -y)
              btn:SetPoint("TOPRIGHT", ac, "TOPRIGHT", 0, -y)
              btn:Show()
              btn:UpdateSelected(activeCategory == cid)
              y = y + SECTION_H
            end
          end
        end
      end
    end
  end

  ac:SetHeight(math.max(50, y))
end

-- Couleur du fond actif (TabActiveBackground.tga) de la section selectionnee
-- dans la sidebar : Theme.gold, tenu a jour par SW.RefreshAccentTheme() --
-- meme source unique que le reste des accents du panneau (cf. commentaire
-- dans SharedWidgets.lua pres de RefreshAccentTheme).
local function GetSectionBgColor()
  return Theme.gold or Theme.accent
end

-- Couleur des gros libelles de groupe de la sidebar (GLOBAL, CADRES
-- D'UNITES, COMBAT, HUD, AURAS & PROCS) : element "Cercle de Puissance" du
-- module Colors, suit donc la spe active -- repli sur le gris neutre
-- d'origine si le module Colors est indisponible.
local function GetGroupHeaderColor()
  local CLR = ns.Modules and ns.Modules.Colors
  local c = CLR and CLR.Get and CLR.Get("powercircle")
  return c or { 0.62, 0.62, 0.62 }
end

local function BuildSidebar()
  local _gold = Theme.gold or Theme.accent
  local _sbActiveColor = GetSectionBgColor()
  -- Textures de fond des boutons de section, pour pouvoir toutes les
  -- retenter en une fois quand la spe change (cf. MainFrame.RefreshSidebarColors) :
  -- sans ca, la couleur restait figee sur celle de la toute 1ere spe active au
  -- moment du build de la sidebar (une seule fois par session), jamais mise a
  -- jour au changement de spe -- confirme en jeu.
  sidebar._sectionBgTextures = {}

  -- Barre de recherche en haut de la sidebar
  local searchBox = CreateFrame("EditBox", nil, sidebar, "BackdropTemplate")
  searchBox:SetHeight(22)
  searchBox:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",   12, -28)
  searchBox:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -12, -28)
  searchBox:SetAutoFocus(false)
  searchBox:SetFont(ns.Media.fontGui, 12, "")
  searchBox:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3], 1)
  searchBox:SetTextInsets(8, 24, 2, 2)
  searchBox:SetMaxLetters(40)
  searchBox:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  searchBox:SetBackdropColor(0, 0, 0, 0.4)
  searchBox:SetBackdropBorderColor(_gold[1], _gold[2], _gold[3], 0.35)

  local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
  placeholder:SetFont(ns.Media.fontGui, 10)
  placeholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
  placeholder:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3], 0.7)
  placeholder:SetText(L["SETTINGS_SEARCH_PLACEHOLDER"])

  searchBox:SetScript("OnEditFocusGained", function(self)
    self:SetBackdropBorderColor(_gold[1], _gold[2], _gold[3], 0.85)
  end)
  searchBox:SetScript("OnEditFocusLost", function(self)
    self:SetBackdropBorderColor(_gold[1], _gold[2], _gold[3], 0.35)
  end)
  searchBox:SetScript("OnEscapePressed", function(self)
    self:SetText(""); self:ClearFocus()
  end)
  searchBox:SetScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    _sbSearchFilter = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if txt == "" then placeholder:Show() else placeholder:Hide() end
    RefreshSidebar()
  end)

  -- ScrollFrame contenant l'accordion
  local sbSF = CreateFrame("ScrollFrame", nil, sidebar)
  sbSF:SetPoint("TOPLEFT",     searchBox, "BOTTOMLEFT",  -12, -8)
  sbSF:SetPoint("BOTTOMRIGHT", sidebar,   "BOTTOMRIGHT",   0, 10)
  sbSF:EnableMouseWheel(true)
  sbSF:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local mx  = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(mx, cur - delta * 24)))
  end)

  local accContainer = CreateFrame("Frame", nil, sbSF)
  accContainer:SetPoint("TOPLEFT", sbSF, "TOPLEFT", 16, -8)
  accContainer:SetWidth(SIDEBAR_W - 32)
  accContainer:SetHeight(1)
  sbSF:SetScrollChild(accContainer)
  sidebar._sbSF        = sbSF
  sidebar._accContainer = accContainer

  -- Lookup catId → cat def
  local catById = {}
  for _, cat in ipairs(CATEGORIES) do catById[cat.id] = cat end

  -- Pré-créer headers + boutons de section pour chaque groupe
  sidebar._groupEntries = {}

  for _, grp in ipairs(SIDEBAR_GROUPS) do
    local entry = { sectionBtns = {} }

    -- Header groupe : cartouche parchemin AishParchemin.tga, cliquable pour
    -- replier/deplier ce groupe (accordeon, cf. RefreshSidebar). Replie par
    -- defaut (sidebar._groupCollapsed[grp.label] = true ci-dessous), sauf
    -- le/les groupes forces ouverts parce qu'ils contiennent activeCategory.
    if sidebar._groupCollapsed[grp.label] == nil then
      sidebar._groupCollapsed[grp.label] = true
    end
    local h = CreateFrame("Button", nil, accContainer)
    h:SetHeight(26)
    local htxt = h:CreateFontString(nil, "OVERLAY")
    -- Taille x1.5 (etait 9) : les grandes sections doivent se distinguer
    -- nettement des labels de sous-section (11px) au-dessus/en-dessous.
    htxt:SetFont(ns.Media.fontTitle, 14)
    htxt:SetPoint("LEFT", 14, 0)
    do
      local c = GetGroupHeaderColor()
      htxt:SetTextColor(c[1], c[2], c[3], 1)
    end
    sidebar._groupHeaderTexts = sidebar._groupHeaderTexts or {}
    sidebar._groupHeaderTexts[#sidebar._groupHeaderTexts + 1] = htxt
    local hBg = h:CreateTexture(nil, "BACKGROUND")
    hBg:SetPoint("TOPLEFT",     htxt, "TOPLEFT",     -10,  5)
    hBg:SetPoint("BOTTOMRIGHT", htxt, "BOTTOMRIGHT",  10, -5)
    hBg:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\AishParchemin")
    pcall(function()
      if hBg.SetTextureSliceMode   then hBg:SetTextureSliceMode(0) end
      if hBg.SetTextureSliceMargins then hBg:SetTextureSliceMargins(16, 16, 16, 16) end
    end)
    -- Prefixe +/- (pas de glyphe fleche : evite les polices custom sans ce
    -- caractere) reflete l'etat courant ; recalcule a chaque RefreshSidebar
    -- via SetExpanded, jamais au clic seul (l'ouverture forcee par
    -- activeCategory doit aussi mettre a jour le prefixe).
    function h:SetExpanded(expanded)
      self._expanded = expanded
      htxt:SetText((expanded and "- " or "+ ") .. grp.label)
    end
    h:SetExpanded(sidebar._groupCollapsed[grp.label] == false)
    h:SetScript("OnClick", function()
      sidebar._groupCollapsed[grp.label] = not sidebar._groupCollapsed[grp.label]
      RefreshSidebar()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    h:SetScript("OnEnter", function()
      local c = GetGroupHeaderColor()
      htxt:SetTextColor(math.min(1, c[1] * 1.3), math.min(1, c[2] * 1.3), math.min(1, c[3] * 1.3), 1)
    end)
    h:SetScript("OnLeave", function()
      local c = GetGroupHeaderColor()
      htxt:SetTextColor(c[1], c[2], c[3], 1)
    end)
    entry.headerBtn = h

    -- Boutons de section (cliquables)
    for _, cid in ipairs(grp.ids) do
      local cat = catById[cid]
      if cat then
        local s = CreateFrame("Button", nil, accContainer)
        s:SetHeight(24)
        s.catId = cid

        -- Barre verticale or (indicateur actif 2px gauche)
        local shl = s:CreateTexture(nil, "BACKGROUND")
        shl:SetPoint("TOPLEFT",    0, 0)
        shl:SetPoint("BOTTOMLEFT", 0, 0)
        shl:SetWidth(2)
        shl:SetColorTexture(_gold[1], _gold[2], _gold[3], 0)

        -- Label
        local stxt = s:CreateFontString(nil, "OVERLAY")
        stxt:SetFont(ns.Media.fontTitle, 11)
        stxt:SetPoint("LEFT", 14, 0)
        stxt:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3], 1)
        stxt:SetText(cat.label)

        -- Fond actif : TabActiveBackground (épouse le texte)
        local sbg = s:CreateTexture(nil, "BACKGROUND")
        sbg:SetPoint("TOPLEFT",     stxt, "TOPLEFT",     -8,  3)
        sbg:SetPoint("BOTTOMRIGHT", stxt, "BOTTOMRIGHT",  8, -3)
        sbg:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\TabActiveBackground")
        -- TabActiveBackground.tga deja desature manuellement (le
        -- SetDesaturated(true) applicatif reste en filet de secours, no-op si
        -- la texture est deja neutre -- SetVertexColor multiplie avec la
        -- couleur presente dans la texture, donc une base non-neutre empeche
        -- toute teinte cible de s'appliquer proprement, cf. spark honor system
        -- dans Debuffs.lua pour le meme correctif).
        pcall(function() sbg:SetDesaturated(true) end)
        sbg:SetVertexColor(_sbActiveColor[1], _sbActiveColor[2], _sbActiveColor[3], 1)
        sidebar._sectionBgTextures[#sidebar._sectionBgTextures + 1] = { tex = sbg, catId = cid }
        pcall(function()
          if sbg.SetTextureSliceMargins then sbg:SetTextureSliceMargins(12, 12, 12, 12) end
          if sbg.SetTextureSliceMode    then sbg:SetTextureSliceMode(1) end
        end)
        sbg:SetAlpha(0)

        s._txt = stxt; s._hl = shl; s._bg = sbg

        -- Hover : teinte le texte avec la couleur "Cercle de puissance" de la
        -- spe active (ns.Modules.Colors, meme systeme que ResourceCircle) --
        -- repli sur Theme.textHighlight si le module Couleurs est indisponible.
        s:SetScript("OnEnter", function(btn)
          if activeCategory ~= btn.catId then
            sbg:SetAlpha(0.15)
            local CLR = ns.Modules and ns.Modules.Colors
            local c = (CLR and CLR.Get and CLR.Get("powercircle")) or Theme.textHighlight
            stxt:SetTextColor(c[1], c[2], c[3], 1)
          end
        end)
        s:SetScript("OnLeave", function(btn)
          if activeCategory ~= btn.catId then
            sbg:SetAlpha(0)
            stxt:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3], 1)
          end
        end)
        s:SetScript("OnClick", function(btn)
          MainFrame:SelectCategory(btn.catId)
          PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)

        -- UpdateSelected (appelé par SelectCategory)
        function s:UpdateSelected(selected)
          self._hl:SetAlpha(selected and 1 or 0)
          self._bg:SetAlpha(selected and 1 or 0)
          if selected then
            local bright = Theme.textBright or Theme.textHighlight or { 1, 0.96, 0.90 }
            self._txt:SetTextColor(bright[1], bright[2], bright[3], 1)
          else
            self._txt:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3], 1)
          end
        end

        entry.sectionBtns[cid] = s
        categoryButtons[cid]   = s   -- accessible par catId (pairs)
      end
    end

    sidebar._groupEntries[grp.label] = entry
  end

  RefreshSidebar()
end

-- Re-teinte les fonds de boutons de section deja crees (cf. sidebar._sectionBgTextures
-- rempli dans BuildSidebar) avec la couleur "Divers" courante -- beaucoup plus
-- leger qu'un InvalidateCategory (pas de reconstruction de widgets, juste un
-- SetVertexColor), donc appelable aussi bien sur un vrai changement de spe que
-- sur un simple edit de couleur en direct dans le panneau Colors (cf. hook dans
-- Colors.lua) sans provoquer de flicker/rebuild genant.
MainFrame.RefreshSidebarColors = function()
  if sidebar._sectionBgTextures then
    local c = GetSectionBgColor()
    for _, entry in ipairs(sidebar._sectionBgTextures) do
      entry.tex:SetVertexColor(c[1], c[2], c[3], 1)
      -- Bug confirme : SetVertexColor sur cette texture (desaturee) reinitialise
      -- parfois son alpha visible a 1 cote client, meme si SetAlpha(0) avait ete
      -- pose avant (bouton non selectionne/non survole) -- constate au changement
      -- de spe, TOUTES les sections apparaissaient "allumees" jusqu'a un simple
      -- survol (qui repasse par OnEnter/OnLeave et corrige l'alpha). On reimpose
      -- explicitement l'etat correct juste apres la reteinte plutot que de
      -- compter sur l'alpha deja en place.
      entry.tex:SetAlpha(activeCategory == entry.catId and 1 or 0)
    end
  end
  if sidebar._groupHeaderTexts then
    local gc = GetGroupHeaderColor()
    for _, htxt in ipairs(sidebar._groupHeaderTexts) do
      htxt:SetTextColor(gc[1], gc[2], gc[3], 1)
    end
  end
end

-- Containers de categorie (build a la demande)
GetOrBuildContainer = function(catId)
  if categoryContainers[catId] then return categoryContainers[catId] end

  local cat
  for _, c in ipairs(CATEGORIES) do
    if c.id == catId then cat = c; break end
  end
  if not cat then return nil end

  local frame = CreateFrame("Frame", nil, content)
  frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  frame:SetWidth(CONTENT_W)
  frame:SetHeight(1)
  frame:Hide()

  local widgets = cat.build(frame)
  categoryContainers[catId] = { frame = frame, widgets = widgets }
  return categoryContainers[catId]
end

-- Catégories de la section sidebar "AURAS & PROCS" (cf. SIDEBAR_GROUPS,
-- SETTINGS_GROUP_AURAS_PROCS) : masquer le HUD Skyriding + les cercles
-- vie/ressource hors combat pendant
-- que cette section est ouverte (ils gênent visuellement la config des
-- auras/procs), et les réafficher en quittant. "spellEffects" (Animations
-- 3D) est volontairement EXCLU de ce groupe : il gère déjà sa propre
-- logique, opposée pour les cercles (gardés visibles exprès -- "les décos
-- 3D s'affichent dessus", cf. bloc dédié plus bas) -- ne pas entrer en
-- conflit avec elle.
local AURAS_PROCS_CATS = {
  aurasTracked = true, aurasIconlist = true, aurasFreebars = true,
  aurasIcons = true, aurasCirclebars = true, aurasTotems = true, aurasTrinkets = true,
  aurasMissingBuffs = true,
}

function MainFrame:SelectCategory(catId)
  local prevCat = activeCategory
  if prevCat == catId then return end
  activeCategory = catId

  -- Quitter une section "Auras & Procs" ? réafficher le cercle de vie +
  -- OutOfCombatResourceCircle tout de suite (nécessaire même si on va vers
  -- Animations 3D, qui les veut visibles aussi) -- ResourceCircle N'EST PAS
  -- touché : "le cercle central", volontairement gardé visible en
  -- permanence dans cette section (≠ des cercles "hors combat"). Skyriding
  -- seulement si on NE va PAS vers
  -- Animations 3D (qui gère elle-même sa propre extinction de Skyriding, en
  -- DIRECT -- un second appel différé ici entrerait en conflit d'ordre
  -- d'exécution avec son SR.SetPreview(false) synchrone).
  if AURAS_PROCS_CATS[prevCat] and not AURAS_PROCS_CATS[catId] then
    local HC   = ns.Modules.HealthCircle
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    if HC   and HC.SetPreview   then HC.SetPreview(true)   end
    -- Lever le force-masquage AVANT SetPreview(true) (cf. entrée : sinon
    -- le flag ocrcHiddenForGui resterait vrai en permanence après coup).
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(false) end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(true)    end
    if catId ~= "spellEffects" then
      local SR = ns.Modules.Skyriding
      C_Timer.After(0, function()
        if SR and SR.SetPreview then SR.SetPreview(true) end
      end)
    end
  end

  -- Quitter la section Animations 3D ? relancer les décos réelles + previews modules
  if prevCat == "spellEffects" and catId ~= "spellEffects" then
    local SE = ns.Modules.SpellEffects
    if SE then
      if SE.StopDecoPreview then SE.StopDecoPreview() end
      if SE.StopPreview then SE.StopPreview() end
      if SE.StopComboPreview then SE.StopComboPreview() end
      if SE.SetGuiMode then SE.SetGuiMode(false) end
    end
    -- Filet de securite : si la derniere ligne selectionnee dans "Animations
    -- 3D" etait un sort "Buffs manquants", son apercu force reste actif
    -- (SetPreview(true, spellId)) tant qu'on ne quitte pas explicitement
    -- cette section -- couper ici aussi en quittant toute la categorie.
    do local MB = ns.Auras and ns.Auras.MissingBuffs; if MB and MB.SetPreview then MB.SetPreview(false) end end
    -- Réactiver les previews des autres modules
    local RC   = ns.Modules.ResourceCircle
    local HC   = ns.Modules.HealthCircle
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    local PB   = ns.Modules.PriorityBar
    local CB   = ns.Modules.CastBar
    local SR   = ns.Modules.Skyriding
    local RH   = ns.Modules.RotationHelper
    local UB   = ns.Modules.UnitBars
    local TTB  = ns.Modules.TopTargetBar
    if RC   and RC.SetPreview     then RC.SetPreview(true)     end
    if HC   and HC.SetPreview     then HC.SetPreview(true)     end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(true)   end
    -- SetGuiHidden / SetPreview sur frames potentiellement sécurisées :
    -- différer d'une frame pour sortir du contexte tainté (OnClick en combat).
    C_Timer.After(0, function()
      if PB   and PB.SetGuiHidden   then PB.SetGuiHidden(false)  end
      if PB   and PB.SetPreview     then PB.SetPreview(true)     end
      if CB   and CB.SetPreview     then CB.SetPreview(true)     end
      if SR   and SR.SetPreview     then SR.SetPreview(true)     end
      if RH   and RH.SetPreview     then RH.SetPreview(true)     end
      if UB   and UB.SetGuiHidden   then UB.SetGuiHidden(false)  end
      if TTB  and TTB.SetGuiHidden  then TTB.SetGuiHidden(false) end
    end)
  end

  -- Entrer dans la section Animations 3D ? stopper les décos réelles + cacher les barres
  -- Les cercles (RC, HC, OCRC) restent visibles car les décos 3D s'affichent dessus
  if catId == "spellEffects" then
    local SE = ns.Modules.SpellEffects
    if SE and SE.SetGuiMode then SE.SetGuiMode(true) end
    local PB   = ns.Modules.PriorityBar
    local CB   = ns.Modules.CastBar
    local SR   = ns.Modules.Skyriding
    local RH   = ns.Modules.RotationHelper
    local UB   = ns.Modules.UnitBars
    local TTB  = ns.Modules.TopTargetBar
    if PB   and PB.SetPreview    then PB.SetPreview(false)    end
    if CB   and CB.SetPreview    then CB.SetPreview(false)    end
    if SR   and SR.SetPreview    then SR.SetPreview(false)    end
    if RH   and RH.SetPreview    then RH.SetPreview(false)    end
    if UB   and UB.SetGuiHidden  then UB.SetGuiHidden(true)   end
    if TTB  and TTB.SetGuiHidden then TTB.SetGuiHidden(true)  end
  end

  -- Entrer dans une section "Auras & Procs" ? masquer cercle de vie +
  -- OutOfCombatResourceCircle + Skyriding. ResourceCircle N'EST PAS touché :
  -- "le cercle central", gardé visible en permanence. Placé APRÈS les blocs
  -- Animations 3D ci-dessus : si on
  -- vient de spellEffects, son bloc de sortie relance Skyriding en DIFFÉRÉ
  -- -- notre propre extinction doit donc AUSSI être différée et programmée
  -- APRÈS, pour gagner l'ordre d'exécution (les callbacks
  -- C_Timer.After(0, ...) s'exécutent dans leur ordre de programmation).
  if AURAS_PROCS_CATS[catId] then
    local HC   = ns.Modules.HealthCircle
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    local SR   = ns.Modules.Skyriding
    if HC   and HC.SetPreview   then HC.SetPreview(false)   end
    if OCRC and OCRC.SetPreview then OCRC.SetPreview(false) end
    -- SetPreview(false) seul ne suffit pas pour OCRC : il retombe sur son
    -- affichage NORMAL hors-combat (quasi toujours vrai pendant les
    -- réglages) -- SetGuiHidden force le masquage, indépendamment de l'état
    -- combat/hors-combat réel. Appelé APRÈS SetPreview pour ne pas être
    -- court-circuité par son propre guard interne (previewMode).
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(true) end
    C_Timer.After(0, function()
      if SR and SR.SetPreview then SR.SetPreview(false) end
    end)
  end

  -- Quitter l'onglet Cast Cible ? couper la preview
  if prevCat == "targetCastBar" and catId ~= "targetCastBar" then
    local TCB = ns.Modules.TargetCastBar
    if TCB and TCB.SetPreview then TCB.SetPreview(false) end
  end

  -- Entrer dans l'onglet Cast Cible ? lancer la preview
  if catId == "targetCastBar" then
    local TCB = ns.Modules.TargetCastBar
    C_Timer.After(0, function()
      if TCB and TCB.SetPreview then TCB.SetPreview(true) end
    end)
  end

  -- Quitter l'onglet Buffs manquants ? couper la preview de l'icone d'alerte
  if prevCat == "aurasMissingBuffs" and catId ~= "aurasMissingBuffs" then
    local MB = ns.Auras and ns.Auras.MissingBuffs
    if MB and MB.SetPreview then MB.SetPreview(false) end
  end

  -- Entrer dans l'onglet Buffs manquants ? afficher l'icone d'alerte meme
  -- si aucune condition reelle n'est remplie
  if catId == "aurasMissingBuffs" then
    local MB = ns.Auras and ns.Auras.MissingBuffs
    if MB and MB.SetPreview then MB.SetPreview(true) end
  end

  -- Quitter la section Mode AFK ? stopper l'apercu (SetPreview, cf.
  -- Modules/AFKMode.lua) + relancer les previews des autres modules,
  -- masques a l'entree (AFK Mode = prise de controle plein ecran, pas de
  -- superposition avec les autres modules comme spellEffects).
  if prevCat == "afkMode" and catId ~= "afkMode" then
    local AM = ns.Modules.AFKMode
    if AM and AM.SetPreview then AM.SetPreview(false) end

    local RC   = ns.Modules.ResourceCircle
    local HC   = ns.Modules.HealthCircle
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    local PB   = ns.Modules.PriorityBar
    local CB   = ns.Modules.CastBar
    local SR   = ns.Modules.Skyriding
    local RH   = ns.Modules.RotationHelper
    local UB   = ns.Modules.UnitBars
    local TTB  = ns.Modules.TopTargetBar
    local TA   = ns.Modules.TargetAuras
    if RC   and RC.SetPreview     then RC.SetPreview(true)     end
    if HC   and HC.SetPreview     then HC.SetPreview(true)     end
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(false) end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(true)   end
    if PB   and PB.SetGuiHidden   then PB.SetGuiHidden(false)  end
    if PB   and PB.SetPreview     then PB.SetPreview(true)     end
    if CB   and CB.SetPreview     then CB.SetPreview(true)     end
    if SR   and SR.SetPreview     then SR.SetPreview(true)     end
    if RH   and RH.SetPreview     then RH.SetPreview(true)     end
    if UB   and UB.SetGuiHidden   then UB.SetGuiHidden(false)  end
    if TTB  and TTB.SetGuiHidden  then TTB.SetGuiHidden(false) end
    if TA   and TA.SetPreview     then TA.SetPreview(true)     end
  end

  -- Entrer dans la section Mode AFK ? masquer les previews des autres
  -- modules (prise de controle plein ecran) puis lancer l'apercu AFK.
  if catId == "afkMode" then
    local RC   = ns.Modules.ResourceCircle
    local HC   = ns.Modules.HealthCircle
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    local PB   = ns.Modules.PriorityBar
    local CB   = ns.Modules.CastBar
    local SR   = ns.Modules.Skyriding
    local RH   = ns.Modules.RotationHelper
    local UB   = ns.Modules.UnitBars
    local TTB  = ns.Modules.TopTargetBar
    local TA   = ns.Modules.TargetAuras
    if RC   and RC.SetPreview     then RC.SetPreview(false)    end
    if HC   and HC.SetPreview     then HC.SetPreview(false)    end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(false)  end
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(true) end
    if PB   and PB.SetPreview     then PB.SetPreview(false)    end
    if CB   and CB.SetPreview     then CB.SetPreview(false)    end
    if SR   and SR.SetPreview     then SR.SetPreview(false)    end
    if RH   and RH.SetPreview     then RH.SetPreview(false)    end
    if UB   and UB.SetGuiHidden   then UB.SetGuiHidden(true)   end
    if TTB  and TTB.SetGuiHidden  then TTB.SetGuiHidden(true)  end
    if TA   and TA.SetPreview     then TA.SetPreview(false)    end

    local AM = ns.Modules.AFKMode
    C_Timer.After(0, function()
      if AM and AM.SetPreview then AM.SetPreview(true) end
    end)
  end

  for cid, btn in pairs(categoryButtons) do
    btn:UpdateSelected(cid == catId)
  end
  RefreshSidebar()

  for _, entry in pairs(categoryContainers) do
    entry.frame:Hide()
  end

  local entry = GetOrBuildContainer(catId)
  if entry then
    entry.frame:Show()
    content:SetHeight(entry.frame:GetHeight())
  end

  scrollFrame:SetVerticalScroll(0)
end

-- Refresh : recharger les valeurs depuis la DB
function MainFrame:RefreshValues()
  for _, entry in pairs(categoryContainers) do
    if entry.widgets then
      for _, w in ipairs(entry.widgets) do
        if w._dbKey then
          local val = DBGet(w._dbKey, w._subKey)
          if w.SetChecked then
            w:SetChecked(val and true or false)
          elseif w.SetValue and w.slider then
            if val then w:SetValue(val) end
          elseif w.SetValue and w._menu then
            if val ~= nil then w:SetValue(val) end
          elseif w.SetColor and w._swatchColor then
            if val and type(val) == "table" then
              w:SetColor(val[1], val[2], val[3], val[4])
            end
          end
        end
      end
    end
  end
end

-- ShowUI / Toggle
function MainFrame:ShowUI()
  if self._versionTxt and ns.GetVersionString then
    self._versionTxt:SetText(ns.GetVersionString())
  end
  self:Show()
  PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
end

function MainFrame:Toggle()
  if InCombatLockdown() then
    print(L["SETTINGS_CANNOT_OPEN_IN_COMBAT"])
    return
  end
  if self:IsShown() then
    self:Hide()
    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
  else
    self:ShowUI()
  end
end

-- Fermer automatiquement en combat pour éviter les appels aux valeurs teintées.
MainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
MainFrame:HookScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_DISABLED" and self:IsShown() then
    self:Hide()
    print(L["SETTINGS_PANEL_AUTO_CLOSED"])
  end
end)

-- Initialisation au premier affichage
local initialized = false

-- Rebuild des widgets après redimensionnement : remplace le SetScript partiel
-- défini plus haut, maintenant que categoryContainers / initialized / activeCategory
-- sont toutes des upvalues correctement capturables.
MainFrame:SetScript("OnSizeChanged", function(self, w, h)
  local newContentW = math.max(370, math.floor(w - SIDEBAR_W - 1 - PADDING - 18 - PADDING))
  CONTENT_W = newContentW
  content:SetWidth(newContentW)
  if not initialized then return end  -- pas encore ouvert, rien à rebuilder
  if _resizeTimer then _resizeTimer:Cancel() end
  _resizeTimer = C_Timer.NewTimer(0.25, function()
    _resizeTimer = nil
    for _, entry in pairs(categoryContainers) do
      entry.frame:Hide()
    end
    wipe(categoryContainers)
    if activeCategory then
      local prev = activeCategory
      activeCategory = nil
      MainFrame:SelectCategory(prev)
    end
  end)
end)

MainFrame:SetScript("OnShow", function(self)
  -- Animation d'entrée : fade-in 0.3s
  self:SetAlpha(0)
  local _fadeT = 0
  self:SetScript("OnUpdate", function(sf, elapsed)
    _fadeT = _fadeT + elapsed
    if _fadeT >= 0.30 then
      sf:SetAlpha(1)
      sf:SetScript("OnUpdate", nil)
    else
      sf:SetAlpha(_fadeT / 0.30)
    end
  end)

  if not initialized then
    initialized = true
    BuildSidebar()
    self:SelectCategory(CATEGORIES[1].id)
  end
  self:RefreshValues()

  local RC   = ns.Modules.ResourceCircle
  local HC   = ns.Modules.HealthCircle
  local OCRC = ns.Modules.OutOfCombatResourceCircle
  local PB   = ns.Modules.PriorityBar
  local CB   = ns.Modules.CastBar
  local SR   = ns.Modules.Skyriding
  local RH   = ns.Modules.RotationHelper

  local UB   = ns.Modules.UnitBars
  local TTB  = ns.Modules.TopTargetBar

  -- Si on est sur Animations 3D : cercles visibles, barres d'unités cachées
  if activeCategory == "spellEffects" then
    local SE = ns.Modules.SpellEffects
    if SE and SE.SetGuiMode then SE.SetGuiMode(true) end
    if RC   and RC.SetPreview    then RC.SetPreview(true)     end
    if HC   and HC.SetPreview    then HC.SetPreview(true)     end
    if OCRC and OCRC.SetPreview  then OCRC.SetPreview(true)   end
    if PB   and PB.SetPreview    then PB.SetPreview(false)    end
    if CB   and CB.SetPreview    then CB.SetPreview(false)    end
    if SR   and SR.SetPreview    then SR.SetPreview(false)    end
    if RH   and RH.SetPreview    then RH.SetPreview(false)    end
    if PB   and PB.SetGuiHidden  then PB.SetGuiHidden(true)   end
    if UB   and UB.SetGuiHidden  then UB.SetGuiHidden(true)   end
    if TTB  and TTB.SetGuiHidden then TTB.SetGuiHidden(true)  end
    return
  end

  -- Si on est sur Mode AFK : previews des autres modules masquees, apercu
  -- AFK relance (meme cas que spellEffects ci-dessus -- reouverture directe
  -- du panneau sur cette section, pas seulement via un clic SelectCategory).
  if activeCategory == "afkMode" then
    local TA = ns.Modules.TargetAuras
    if RC   and RC.SetPreview     then RC.SetPreview(false)    end
    if HC   and HC.SetPreview     then HC.SetPreview(false)    end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(false)  end
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(true) end
    if PB   and PB.SetPreview     then PB.SetPreview(false)    end
    if CB   and CB.SetPreview     then CB.SetPreview(false)    end
    if SR   and SR.SetPreview     then SR.SetPreview(false)    end
    if RH   and RH.SetPreview     then RH.SetPreview(false)    end
    if UB   and UB.SetGuiHidden   then UB.SetGuiHidden(true)   end
    if TTB  and TTB.SetGuiHidden  then TTB.SetGuiHidden(true)  end
    if TA   and TA.SetPreview     then TA.SetPreview(false)    end
    local AM = ns.Modules.AFKMode
    C_Timer.After(0, function()
      if AM and AM.SetPreview then AM.SetPreview(true) end
    end)
    return
  end

  -- Si on est sur une section "Auras & Procs" : cercle de vie +
  -- OutOfCombatResourceCircle + Skyriding cachés (cf. AURAS_PROCS_CATS/
  -- SelectCategory) -- ResourceCircle ("le cercle central") reste visible,
  -- pris en compte ici aussi pour le cas ou le panneau se rouvre
  -- DIRECTEMENT sur cette section (dernière catégorie mémorisée d'une
  -- session précédente), pas seulement au clic.
  if AURAS_PROCS_CATS[activeCategory] then
    if RC   and RC.SetPreview   then RC.SetPreview(true)    end
    if HC   and HC.SetPreview   then HC.SetPreview(false)   end
    if OCRC and OCRC.SetPreview then OCRC.SetPreview(false) end
    -- SetPreview(false) seul ne suffit pas pour OCRC (retombe sur son
    -- affichage normal hors-combat) -- SetGuiHidden force le masquage.
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(true) end
    if PB   and PB.SetPreview   then PB.SetPreview(true)    end
    if PB   and PB.SetDraggable then PB.SetDraggable(true)  end
    if CB   and CB.SetPreview   then CB.SetPreview(true)    end
    if SR   and SR.SetPreview   then SR.SetPreview(false)   end
    if RH   and RH.SetPreview   then RH.SetPreview(true)    end
    local TA  = ns.Modules.TargetAuras
    if TA   and TA.SetPreview   then TA.SetPreview(true)    end
    return
  end

  -- Autre catégorie : tout visible
  if RC   and RC.SetPreview     then RC.SetPreview(true)     end
  if HC   and HC.SetPreview     then HC.SetPreview(true)     end
  if OCRC and OCRC.SetPreview   then OCRC.SetPreview(true)   end
  if PB   and PB.SetPreview     then PB.SetPreview(true)     end
  if PB   and PB.SetDraggable   then PB.SetDraggable(true)   end
  if CB   and CB.SetPreview     then CB.SetPreview(true)     end
  if SR   and SR.SetPreview     then SR.SetPreview(true)     end
  if RH   and RH.SetPreview     then RH.SetPreview(true)     end
  local TA  = ns.Modules.TargetAuras
  if TA   and TA.SetPreview     then TA.SetPreview(true)     end
end)

MainFrame:SetScript("OnHide", function(self)
  -- Stopper les previews et désactiver le mode GUI
  local SE = ns.Modules.SpellEffects
  if SE then
    if SE.StopDecoPreview then SE.StopDecoPreview() end
    if SE.StopPreview then SE.StopPreview() end
    if SE.StopComboPreview then SE.StopComboPreview() end
    if SE.SetGuiMode then SE.SetGuiMode(false) end
  end
  local RC   = ns.Modules.ResourceCircle
  local HC   = ns.Modules.HealthCircle
  local OCRC = ns.Modules.OutOfCombatResourceCircle
  local PB   = ns.Modules.PriorityBar
  local CB   = ns.Modules.CastBar
  local SR   = ns.Modules.Skyriding
  local UB   = ns.Modules.UnitBars
  local TTB  = ns.Modules.TopTargetBar
  local RH   = ns.Modules.RotationHelper
  if RH   and RH.EnableDrag      then RH.EnableDrag(false)      end
  if RC   and RC.SetDraggable    then RC.SetDraggable(false)    end
  if HC   and HC.SetDraggable    then HC.SetDraggable(false)    end
  if OCRC and OCRC.SetDraggable  then OCRC.SetDraggable(false)  end
  if RC   and RC.SetPreview      then RC.SetPreview(false)      end
  if HC   and HC.SetPreview      then HC.SetPreview(false)      end
  -- Lever le force-masquage AVANT SetPreview(false) : sinon le flag
  -- ocrcHiddenForGui resterait vrai en permanence si le panneau se ferme
  -- pendant qu'une section "Auras & Procs" est active (SetPreview(false)
  -- retombe sur ShouldShow(), qui le respecterait indéfiniment sinon).
  if OCRC and OCRC.SetGuiHidden  then OCRC.SetGuiHidden(false)  end
  if OCRC and OCRC.SetPreview    then OCRC.SetPreview(false)    end
  if PB   and PB.SetDraggable    then PB.SetDraggable(false)    end
  if PB   and PB.SetGuiHidden    then PB.SetGuiHidden(false)    end
  if PB   and PB.SetPreview      then PB.SetPreview(false)      end
  if CB   and CB.SetPreview      then CB.SetPreview(false)      end
  if CB   and CB.SetDragUnlocked then CB.SetDragUnlocked(false) end
  local TCB = ns.Modules.TargetCastBar
  if TCB  and TCB.SetPreview      then TCB.SetPreview(false)      end
  if TCB  and TCB.SetDragUnlocked then TCB.SetDragUnlocked(false) end
  if SR   and SR.SetLayoutMode   then SR.SetLayoutMode(false)   end
  if SR   and SR.SetPreview      then SR.SetPreview(false)      end
  if RH   and RH.SetPreview      then RH.SetPreview(false)      end
  if UB   and UB.SetGuiHidden    then UB.SetGuiHidden(false)    end
  if TTB  and TTB.SetGuiHidden   then TTB.SetGuiHidden(false)   end
  local TA  = ns.Modules.TargetAuras
  if TA   and TA.SetPreview      then TA.SetPreview(false)      end
  local AM  = ns.Modules.AFKMode
  if AM   and AM.SetPreview      then AM.SetPreview(false)      end
  -- Buffs manquants : meme filet de securite -- SetPreview(true) est lance a
  -- l'entree de la categorie "aurasMissingBuffs" (cf. bloc SelectCategory
  -- plus haut) mais son pendant SetPreview(false) n'est appele QUE sur un
  -- changement de categorie -- fermer le panneau entier (Echap, clic
  -- ailleurs...) sans changer de categorie au prealable ne declenchait
  -- jamais ce nettoyage, laissant l'icone affichee indefiniment.
  local MB = ns.Auras and ns.Auras.MissingBuffs
  if MB   and MB.SetPreview      then MB.SetPreview(false)      end

  -- FILET DE SECURITE : ns.Auras (menu "Auras & Procs",
  -- Render.lua/Tactics.lua/Effects.lua) pose ns._previewBars/_previewMode
  -- sur OnShow/OnHide de CHAQUE sous-panneau individuel -- si le GUI entier
  -- se ferme sans que ce sous-panneau precis ait recu son propre OnHide
  -- (ex: fermeture via un bouton/raccourci qui cache directement MainFrame
  -- sans repasser par le sous-panneau actif), le flag restait bloque a
  -- true indefiniment. Invisible avant la migration native (le rendu
  -- preview retombait sur un container toujours cache de toute facon) --
  -- confirme en jeu comme cause d'un affichage PERMANENT de l'ancien rendu
  -- Lua (barres/couleurs/glows d'avant migration) une fois le GUI ferme.
  local Auras2 = ns.Auras
  if Auras2 and (Auras2._previewBars or Auras2._previewMode) then
    Auras2._previewBars = false
    Auras2._previewMode = nil
    pcall(function() Auras2.ScanAuras() end)
  end

  -- Auto-epinglage CDM (cf. Whitelist.lua/CDMHooks.lua) : si des sorts ont
  -- ete epingles pendant que le panneau etait ouvert, propose maintenant
  -- (une seule fois, pas a chaque coche) de recharger l'interface pour
  -- appliquer le changement.
  local Auras = ns.Auras
  if Auras and Auras.PromptCDMReloadIfPending then Auras.PromptCDMReloadIfPending() end
end)

-- Export de données (keywords + tags manuels) ? popup copiable
local ExportFrame

local function SerializeStringList(arr)
  if not arr or #arr == 0 then return "{}" end
  local parts = {}
  for _, v in ipairs(arr) do
    parts[#parts + 1] = string.format("%q", v)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function BuildExportString()
  local lines = {}
  lines[#lines + 1] = "-- AISHCORE EXPORT"
  lines[#lines + 1] = L["SETTINGS_EXPORT_PASTE_INSTRUCTIONS"]
  lines[#lines + 1] = L["SETTINGS_EXPORT_PATH_HINT"]
  lines[#lines + 1] = ""

  -- modelTagKeywords (depuis MODEL_TAGS actuellement chargé)
  local hasKW = false
  for _, tag in ipairs(MODEL_TAGS) do
    if tag.keywords and #tag.keywords > 0 then hasKW = true; break end
  end
  if hasKW then
    lines[#lines + 1] = '    ["modelTagKeywords"] = {'
    for _, tag in ipairs(MODEL_TAGS) do
      if tag.keywords and #tag.keywords > 0 then
        lines[#lines + 1] = '        ' .. string.format("[%q]", tag.label)
                           .. ' = ' .. SerializeStringList(tag.keywords) .. ','
      end
    end
    lines[#lines + 1] = '    },'
    lines[#lines + 1] = ""
  else
    lines[#lines + 1] = L["SETTINGS_EXPORT_NO_KEYWORDS"]
    lines[#lines + 1] = ""
  end

  -- modelCustomTags (tags manuels clic-droit)
  local ct = ns.DB and ns.DB.modelCustomTags
  if ct and next(ct) then
    lines[#lines + 1] = '    ["modelCustomTags"] = {'
    for fileID, tags in pairs(ct) do
      local tagParts = {}
      for tagLabel, v in pairs(tags) do
        if v then
          tagParts[#tagParts + 1] = string.format("[%q]", tagLabel) .. " = true"
        end
      end
      if #tagParts > 0 then
        lines[#lines + 1] = '        [' .. tostring(fileID) .. '] = {'
                           .. table.concat(tagParts, ", ") .. '},'
      end
    end
    lines[#lines + 1] = '    },'
  else
    lines[#lines + 1] = L["SETTINGS_EXPORT_NO_CUSTOM_TAGS"]
  end

  -- specDefaults (couleurs de spés depuis Colors.SPEC_DEFAULTS)
  lines[#lines + 1] = ""
  local Colors = ns.Modules and ns.Modules.Colors
  local sd = Colors and Colors.SPEC_DEFAULTS
  if sd and next(sd) then
    lines[#lines + 1] = '    ["specDefaults"] = {'
    for classKey, specs in pairs(sd) do
      lines[#lines + 1] = '        ["' .. classKey .. '"] = {'
      for specID, elements in pairs(specs) do
        lines[#lines + 1] = '            [' .. tostring(specID) .. '] = {'
        for elem, c in pairs(elements) do
          lines[#lines + 1] = string.format(
            '                ["' .. elem .. '"] = {%.4f, %.4f, %.4f, %.4f},',
            c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
        end
        lines[#lines + 1] = '            },'
      end
      lines[#lines + 1] = '        },'
    end
    lines[#lines + 1] = '    },'
  else
    lines[#lines + 1] = L["SETTINGS_EXPORT_NO_SPEC_DEFAULTS"]
  end

  return table.concat(lines, "\n")
end

local function EnsureExportFrame()
  if ExportFrame then return ExportFrame end

  local f = CreateFrame("Frame", "AishCoreExportFrame", UIParent, "BackdropTemplate")
  f:SetSize(680, 480)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.06, 0.06, 0.10, 0.97)
  f:SetBackdropBorderColor(unpack(Theme.accent))
  f:SetPoint("CENTER")
  f:Hide()
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

  local title = f:CreateFontString(nil, "OVERLAY")
  title:SetFont(ns.Media.fontTitle, 13, "OUTLINE")
  title:SetPoint("TOP", f, "TOP", 0, -10)
  title:SetTextColor(unpack(Theme.accentText))
  title:SetText(L["SETTINGS_EXPORT_KEYWORDS_TITLE"])

  local hint = f:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 10, "")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
  hint:SetTextColor(0.75, 0.75, 0.75, 1)
  hint:SetText(L["SETTINGS_EXPORT_SELECT_COPY_HINT"])

  local closeBtn = CreateFrame("Button", nil, f)
  closeBtn:SetSize(18, 18)
  closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  closeBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
  closeBtn:GetNormalTexture():SetVertexColor(0.7, 0.7, 0.7)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  -- Refresh button
  local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  refreshBtn:SetSize(100, 22)
  refreshBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
  refreshBtn:SetText(L["SETTINGS_REFRESH"])

  -- ScrollFrame + EditBox
  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT",     f, "TOPLEFT",  12, -60)
  sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 40)

  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetWidth(sf:GetWidth())
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  sf:SetScrollChild(eb)

  refreshBtn:SetScript("OnClick", function()
    local txt = BuildExportString()
    eb:SetText(txt)
    eb:SetCursorPosition(0)
    eb:HighlightText()
  end)

  f.editbox = eb
  f.refresh = refreshBtn
  ExportFrame = f
  return f
end

local function OpenExportFrame()
  local f = EnsureExportFrame()
  local txt = BuildExportString()
  f.editbox:SetText(txt)
  f.editbox:SetCursorPosition(0)
  f:Show()
  f.editbox:SetFocus()
  f.editbox:HighlightText()
end

-- Commande slash : /aishcore export
SLASH_AISHCOREEXPORT1 = "/aishexport"
SlashCmdList["AISHCOREEXPORT"] = function()
  OpenExportFrame()
end

-- Également accessible via /aishcore export  (si une commande principale existe déjà)
local _origAish = SlashCmdList["AISHCORE"]
SLASH_AISHCORE1 = "/aishcore"
SlashCmdList["AISHCORE"] = function(msg)
  local cmd = msg and msg:lower():match("^(%S+)")
  if cmd == "export" then
    OpenExportFrame()
  elseif _origAish then
    _origAish(msg)
  else
    print(L["SETTINGS_SLASH_COMMANDS_HINT"])
  end
end

-- Méthode Toggle (ouvrir/fermer, utilisée par la slash-cmd et le bouton minimap)
function MainFrame:Toggle()
  if InCombatLockdown() then
    print(L["SETTINGS_CANNOT_OPEN_IN_COMBAT"])
    return
  end
  if self:IsShown() then
    self:Hide()
    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
  else
    self:ShowUI()
  end
end

-- Intégration Options > Add-ons (WoW Settings API, retail 10.x+)
-- Apparaît dans la liste Options > Add-ons ; un bouton ouvre le panneau custom.
local function RegisterWoWSettings()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

  local canvas = CreateFrame("Frame")
  canvas:SetSize(820, 567)

  -- Logo
  local logoTex = canvas:CreateTexture(nil, "ARTWORK")
  logoTex:SetTexture("Interface\\AddOns\\AishCore\\Media\\logo_icon.tga")
  logoTex:SetSize(64, 64)
  logoTex:SetPoint("TOPLEFT", canvas, "TOPLEFT", 24, -24)

  -- Titre
  local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetText("AishCore")
  title:SetPoint("BOTTOMLEFT", logoTex, "BOTTOMRIGHT", 12, 4)

  -- Version
  local ver = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  ver:SetText(ns.GetVersionString and ns.GetVersionString() or ("v" .. (ns.addonVersion or "?")))
  ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

  -- Description
  local desc = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  desc:SetText(L["SETTINGS_WOW_PANEL_DESC"])
  desc:SetWidth(680)
  desc:SetJustifyH("LEFT")
  desc:SetPoint("TOPLEFT", logoTex, "BOTTOMLEFT", 0, -20)

  -- Bouton principal
  local openBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
  openBtn:SetSize(240, 34)
  openBtn:SetText(L["SETTINGS_OPEN_AISHCORE_SETTINGS"])
  openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
  openBtn:SetScript("OnClick", function()
    -- Fermer le panneau Options WoW
    if SettingsPanel and SettingsPanel.Close then
      SettingsPanel:Close()
    elseif SettingsPanel and SettingsPanel.Hide then
      HideUIPanel(SettingsPanel)
    end
    -- Ouvrir le panneau AishCore
    if ns.SettingsPanel then
      ns.SettingsPanel:Show()
    end
  end)

  local cat = Settings.RegisterCanvasLayoutCategory(canvas, "AishCore")
  Settings.RegisterAddOnCategory(cat)
  ns._wowSettingsCategory = cat
end

RegisterWoWSettings()

-- Exporter
ns.SettingsPanel = MainFrame
-- Invalidation d'une page de reglages (cf. _invalidateCategory plus haut),
-- exposee pour les fichiers hors SettingsPanel.lua dont la case "Activer"
-- ne passe pas par les Bind* d'ici (ex: MissingBuffs.lua, dont la config vit
-- dans ns.Auras.db, pas ns.DB) -- sans ca, toggler cette case-la depuis sa
-- propre page laissait la ligne miroir de la page "Modules" figee.
MainFrame.InvalidateCategory = function(catId) if _invalidateCategory then _invalidateCategory(catId) end end

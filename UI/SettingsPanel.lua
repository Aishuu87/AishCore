-- UI/SettingsPanel.lua : Panneau de configuration principal
-- Layout deux colonnes : sidebar categories + contenu scrollable
local addonName, ns = ...
local L = ns.L

local SW     = ns.SharedWidgets
local Theme  = ns.Theme

-- Dimensions globales
local PANEL_WIDTH   = 940
local PANEL_HEIGHT  = 660
local TITLE_H       = 28
local SIDEBAR_W     = 220
local ROW_HEIGHT    = 28
local SECTION_GAP   = 8
local PADDING       = 10
local CAT_BTN_H     = 26
-- Largeur utile des widgets dans la zone de contenu droite
local CONTENT_W     = 680

---------------------------------------------------------------------------
-- Frame principal
---------------------------------------------------------------------------
local MainFrame = CreateFrame("Frame", "AishaddonSettingsPanel", UIParent)
MainFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
MainFrame:SetFrameStrata("DIALOG")
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:SetClampedToScreen(true)
MainFrame:SetResizable(true)
MainFrame:SetResizeBounds(PANEL_WIDTH, PANEL_HEIGHT, 1400, 1000)
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
_logoTex:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\Logo\\AishUILogo")

-- Title bar (zone de drag transparente — identité portée par le logo sticker)
local titleBar = SW.CreateTitleBar(MainFrame, "Aishaddon")
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
_gripChevron:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\UI\\AishChevron")
_gripChevron:SetVertexColor(0.55, 0.55, 0.55, 0.55)
resizeGrip:SetScript("OnEnter", function() _gripChevron:SetVertexColor(0.85, 0.85, 0.85, 1) end)
resizeGrip:SetScript("OnLeave", function() _gripChevron:SetVertexColor(0.55, 0.55, 0.55, 0.55) end)
resizeGrip:SetScript("OnMouseDown", function(self, button)
  if button == "LeftButton" then MainFrame:StartSizing("BOTTOMRIGHT") end
end)
resizeGrip:SetScript("OnMouseUp", function()
  MainFrame:StopMovingOrSizing()
end)

table.insert(UISpecialFrames, "AishaddonSettingsPanel")

---------------------------------------------------------------------------
-- Sidebar gauche
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- ScrollFrame (zone de contenu droite)
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Utilitaires de layout
---------------------------------------------------------------------------
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

  return ctx
end

---------------------------------------------------------------------------
-- Bind helpers
---------------------------------------------------------------------------
local function GetModKey(dbKey)
  local map = {
    resourceCircle             = "ResourceCircle",
    healthCircle               = "HealthCircle",
    outOfCombatResourceCircle  = "OutOfCombatResourceCircle",
    priorityBar                = "PriorityBar",
    -- rotationHelper             = "RotationHelper",
    spellEffects               = "SpellEffects",
    xpBar                      = "XPBar",
    unitBars                   = "UnitBars",
    topTargetBar               = "TopTargetBar",
    targetAuras                = "TargetAuras",
    colors                     = "Colors",
    skyriding                  = "Skyriding",
  }
  return map[dbKey]
end

local function LiveApply(dbKey)
  local mod = ns.Modules and ns.Modules[GetModKey(dbKey)]
  if mod and mod.ApplySettings then mod.ApplySettings() end
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

-- Reconstruit une catégorie GUI en live (utilisé par les options allSpecs)
local _invalidateCategory  -- défini après categoryContainers

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

local function BindDropdown(dd, dbKey, subKey)
  local v = DBGet(dbKey, subKey)
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

---------------------------------------------------------------------------
-- Aide : groupe radio pour mode de visibilité (mutuellement exclusif)
-- modesList = { {key, label, tooltip}, ... }
-- defaultMode = valeur par défaut si pas dans la DB
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Helpers : type de dots secondaires et libellés (pour RC et OCRC)
-- Miroir de la logique de DetectSecondaryDots() dans ResourceCircle.lua.
-- Utilisé pour l'affichage conditionnel et le nommage des sections.
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- BUILD : Cercle de Ressource
---------------------------------------------------------------------------
local function BuildResourceCircle(container)
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

  local slSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_SIZE"], 20, 200, 1, W))
  BindSlider(slSize, "resourceCircle", "size")

  local slRCArcSize = SW.CreateSlider(container, L["SETTINGS_ARC_SIZE_RATIO"], 0.5, 1.0, 0.05, SL_W2)
  BindSlider(slRCArcSize, "resourceCircle", "arcSizeRatio")
  local slRCThick = SW.CreateSlider(container, L["SETTINGS_ARC_THICKNESS"], 0.0, 0.99, 0.01, SL_W2)
  BindSlider(slRCThick, "resourceCircle", "overlayRatio")
  ctx:AddRow(8, slRCArcSize, slRCThick)

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
  elseif ns._specID == 250 then _arcSpec = { cfgKey = "dndArcEnabled",          label = "188290",               color = {0.20, 0.78, 0.35} }
  end
  if _arcSpec then
    ctx:Spacer(6)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_ARC_DURATION_HEADER"], _arcSpec.label), W))
    local cbDur = ctx:Add(SW.CreateCheckbox(container, string.format(L["SETTINGS_ARC_DURATION_SHOW"], _arcSpec.label), W))
    BindCheckbox(cbDur, "resourceCircle", _arcSpec.cfgKey)
    cbDur.onChanged = function(v) DBSet("resourceCircle", _arcSpec.cfgKey, v); if ns.AutoConfigCenterArc then ns.AutoConfigCenterArc() end end
    cbDur:SetChecked(DBGet("resourceCircle", _arcSpec.cfgKey) ~= false)
    local slDurArc = SW.CreateSlider(container, L["SETTINGS_ARC_SIZE"], 0.3, 0.99, 0.01, SL_W2)
    BindSlider(slDurArc, "resourceCircle", "durationArcRatio")
    local slDurThick = SW.CreateSlider(container, L["SETTINGS_THICKNESS"], 0.0, 0.99, 0.01, SL_W2)
    BindSlider(slDurThick, "resourceCircle", "durationArcOverlayRatio")
    ctx:AddRow(8, slDurArc, slDurThick)
    -- Color swatch
    local cr = DBGet("resourceCircle", "durationArcColorR") or _arcSpec.color[1]
    local cg = DBGet("resourceCircle", "durationArcColorG") or _arcSpec.color[2]
    local cb_ = DBGet("resourceCircle", "durationArcColorB") or _arcSpec.color[3]
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
          DBSet("resourceCircle", "durationArcColorR", cr)
          DBSet("resourceCircle", "durationArcColorG", cg)
          DBSet("resourceCircle", "durationArcColorB", cb_)
        end,
        cancelFunc = function(pp)
          cr, cg, cb_ = pp.r, pp.g, pp.b
          swT:SetColorTexture(cr, cg, cb_)
          DBSet("resourceCircle", "durationArcColorR", cr)
          DBSet("resourceCircle", "durationArcColorG", cg)
          DBSet("resourceCircle", "durationArcColorB", cb_)
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
      local rcfg = ns.GetCfg("resourceCircle")
      if rcfg and rcfg.durationArcColorR then
        col = {rcfg.durationArcColorR, rcfg.durationArcColorG or 1, rcfg.durationArcColorB or 1}
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
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SECONDARY_RES_TEXT"], W))

  local slSecResSize = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 30, 1, W))
  BindSlider(slSecResSize, "resourceCircle", "secResTextSize")
  local ddSecResFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddSecResFont, "resourceCircle", "secResFont")

  local slSecResX = SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -200, 200, 1, SL_W2)
  BindSlider(slSecResX, "resourceCircle", "secResTextOffsetX")
  local slSecResY = SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -200, 200, 1, SL_W2)
  BindSlider(slSecResY, "resourceCircle", "secResTextOffsetY")
  ctx:AddRow(8, slSecResX, slSecResY)

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION"], W))

  -- Champs de saisie directe de la position X / Y
  local function MakePosInput(labelText, dbSubKey)
    local fw = SL_W2
    local f = CreateFrame("Frame", nil, container)
    f:SetSize(fw, 34)
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10)
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
    lbl:SetTextColor(unpack(Theme.textDim))
    lbl:SetText(labelText)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.08, 0.08, 0.11, 1)
    bg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bg:SetSize(fw, 20)
    local borderTex = f:CreateTexture(nil, "BORDER")
    borderTex:SetColorTexture(0.25, 0.25, 0.30, 0.8)
    borderTex:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    borderTex:SetSize(fw, 1)
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    SW.StyleEditBox(eb)
    eb:SetSize(fw - 6, 16)
    eb:SetPoint("CENTER", bg, "CENTER", 2, 0)
    eb:SetAutoFocus(false)
    local initVal = DBGet("resourceCircle", dbSubKey) or ns.Defaults.resourceCircle[dbSubKey] or 0
    eb:SetText(tostring(initVal))
    local function Commit()
      local val = tonumber(eb:GetText())
      if val == nil then
        eb:SetText(tostring(DBGet("resourceCircle", dbSubKey) or ns.Defaults.resourceCircle[dbSubKey] or 0))
        return
      end
      val = math.floor(val + 0.5)
      DBSet("resourceCircle", dbSubKey, val)
      local rcBar = _G["AishaddonRingBar"]
      if rcBar then
        local cx = DBGet("resourceCircle", "x") or ns.Defaults.resourceCircle.x or 0
        local cy = DBGet("resourceCircle", "y") or ns.Defaults.resourceCircle.y or 0
        rcBar:ClearAllPoints()
        rcBar:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
      end
    end
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit() end)
    eb:SetScript("OnEditFocusLost", Commit)
    f._eb = eb
    return f
  end

  local rcXInput = MakePosInput(L["SETTINGS_POSITION_X_PX"], "x")
  local rcYInput = MakePosInput(L["SETTINGS_POSITION_Y_PX"], "y")
  ctx:AddRow(8, rcXInput, rcYInput)
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

---------------------------------------------------------------------------
-- BUILD : Hors Combat (Cercle de Vie + Cercle de Ressource Hors Combat)
---------------------------------------------------------------------------
local function BuildOutOfCombat(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W
  local SL_W2 = math.floor((W - 8) / 2)
  local SL_W3 = math.floor((W - 16) / 3)

  -- ====== Cercle de Vie ======
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

  -- ====== Cercle de Ressource Hors Combat ======
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
    nil, Theme.gold, Theme.accent)
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

---------------------------------------------------------------------------
--[[ -- BUILD : Rotation Helper (désactivé)
---------------------------------------------------------------------------
local function BuildRotationHelper(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, "Rotation Helper", W))

  local cb = ctx:Add(SW.CreateCheckbox(container,
    "Activer le Rotation Helper",
    "Affiche des suggestions de sorts sur les boutons d'action.", W))
  BindCheckbox(cb, "rotationHelper", "enabled")

  ctx:Finalize()
  return ctx.widgets
end
--]]

---------------------------------------------------------------------------
-- BUILD : Barres de vie (Unit Bars)
---------------------------------------------------------------------------
local function BuildUnitBars(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  -- Helpers pour lire/Ecrire les valeurs E 3 niveaux : unitBars.bars.<key>.<prop>
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

  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_GLOBAL_OPTIONS"], W))

  -- Inversion des couleurs
  local cbRev = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_CLASSIC_MODE"],
    L["SETTINGS_UB_CLASSIC_MODE_TT"], W))
  BindCheckbox(cbRev, "unitBars", "reversed")

  -- Mode de visibilité (remplace "Masquer hors combat")
  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "unitBars", {
    { "always",  L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_UB_VIS_ALWAYS_TT"] },
    { "target",  L["SETTINGS_VIS_TARGET"],    L["SETTINGS_UB_VIS_TARGET_TT"] },
    { "combat",  L["SETTINGS_VIS_COMBAT"],    L["SETTINGS_UB_VIS_COMBAT_TT"] },
  }, "combat")

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

  -- Dots : toggle + sliders
  local cbShowDots = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_SHOW_DOTS"],
    L["SETTINGS_UB_SHOW_DOTS_TT"], W))
  BindCheckbox(cbShowDots, "unitBars", "showDots")

  -- Taille du dot principal
  local _ubSL2 = math.floor((W - 8) / 2)
  local _ubSL3 = math.floor((W - 16) / 3)
  local slDot = SW.CreateSlider(container, L["SETTINGS_UB_DOT_SIZE"], 4, 24, 1, _ubSL3)
  slDot:SetValue(UBGlobal("dotSize") or 9)
  slDot.onChanged = function(val) UBGlobalSet("dotSize", val) end
  -- Ratio dots (0=proportionnel, 100=identiques)
  local slDotR = SW.CreateSlider(container, L["SETTINGS_UB_DOT_RATIO"], 0, 100, 1, _ubSL3)
  slDotR:SetValue(UBGlobal("dotRatio") or 0)
  slDotR.onChanged = function(val) UBGlobalSet("dotRatio", val) end
  -- Ecart dots/barre
  local slDotGap = SW.CreateSlider(container, L["SETTINGS_UB_DOT_GAP"], -10, 20, 1, _ubSL3)
  slDotGap:SetValue(UBGlobal("dotGap") or 3)
  slDotGap.onChanged = function(val) UBGlobalSet("dotGap", val) end
  ctx:AddRow(8, slDot, slDotR, slDotGap)

  -- Barre de bouclier (absorb)
  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SHIELD_BAR"], W))
  local cbAbsorb = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_SHOW_SHIELD_BAR"],
    L["SETTINGS_UB_SHOW_SHIELD_BAR_TT"], W))
  cbAbsorb:SetChecked(UBGlobal("showAbsorb") ~= false)
  cbAbsorb.onChanged = function(val) UBGlobalSet("showAbsorb", val) end

  -- Couleur de la barre d'absorb
  local swAbsorb = ctx:Add(SW.CreateColorSwatch(container,
    L["SETTINGS_UB_ABSORB_COLOR"],
    L["SETTINGS_UB_ABSORB_COLOR_TT"], W))
  local _absC = UBGlobal("absorbColor") or { 0, 1, 0.918, 1 }
  swAbsorb:SetColor(_absC[1], _absC[2], _absC[3], _absC[4])
  swAbsorb.onChanged = function(r, g, b, a)
    UBGlobalSet("absorbColor", { r, g, b, a or 1 })
  end

  -- Sens de l'absorb (normal = droite, miroir = gauche)
  local cbAbsorbRev = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_ABSORB_MIRROR"],
    L["SETTINGS_UB_ABSORB_MIRROR_TT"], W))
  cbAbsorbRev:SetChecked(UBGlobal("absorbReversed") == true)
  cbAbsorbRev.onChanged = function(val) UBGlobalSet("absorbReversed", val) end

  -- Taille police texte HP
  local slTxt = ctx:Add(SW.CreateSlider(container, L["SETTINGS_UB_HP_FONT_SIZE"], 6, 20, 1, W))
  slTxt:SetValue(UBGlobal("textSize") or 8)
  slTxt.onChanged = function(val) UBGlobalSet("textSize", val) end
  local ddUBHpFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_UB_HP_FONT"], ns.GetFontList(), 220))
  local _ubHpFontV = UBGlobal("font"); if _ubHpFontV then ddUBHpFont:SetValue(_ubHpFontV) end
  ddUBHpFont.onChanged = function(val) UBGlobalSet("font", val) end

  -- Mode d'affichage HP : pourcentage vs valeur (mutuellement exclusif)
  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_HP_TEXT"], W))
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

  -- Taille police nom
  local slName = ctx:Add(SW.CreateSlider(container, L["SETTINGS_UB_NAME_FONT_SIZE"], 8, 28, 1, W))
  slName:SetValue(UBGlobal("nameSize") or 14)
  slName.onChanged = function(val) UBGlobalSet("nameSize", val) end
  local ddUBNameFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_UB_NAME_FONT"], ns.GetFontList(), 220))
  local _ubNameFontV = UBGlobal("nameFont"); if _ubNameFontV then ddUBNameFont:SetValue(_ubNameFontV) end
  ddUBNameFont.onChanged = function(val) UBGlobalSet("nameFont", val) end

  -- Mode tank
  ctx:Spacer(4)
  local cbTank = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_UB_TANK_HEIGHT"],
    L["SETTINGS_UB_TANK_HEIGHT_TT"], W))
  BindCheckbox(cbTank, "unitBars", "useTankHeight")

  local slTankW = ctx:Add(SW.CreateSlider(container, L["SETTINGS_UB_TANK_HEIGHT_SLIDER"], 2, 30, 1, W))
  slTankW:SetValue(UBGlobal("tankHeight") or 8)
  slTankW.onChanged = function(val) UBGlobalSet("tankHeight", val) end

  ctx:Spacer(6)

  -- Helper : ligne de 2 edit boxes cEte E cEte (rEutilisable)
  local function MakeXYRow(bk, propA, propB, labelA, labelB)
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 32)
    local function MakeInput(lTxt, prop, xAnchor)
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 11)
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(lTxt)
      lbl:SetPoint("LEFT", row, "LEFT", xAnchor, 6)
      local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
      SW.StyleEditBox(eb)
      eb:SetSize(54, 20)
      eb:SetAutoFocus(false)
      eb:SetNumeric(false)
      eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
      eb:SetText(tostring(UBGet(bk, prop) or 0))
      local function Commit(self)
        local v = tonumber(self:GetText())
        if v then UBSet(bk, prop, v) end
      end
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", Commit)
      return eb
    end
    MakeInput(labelA or L["SETTINGS_AXIS_X"], propA, 0)
    MakeInput(labelB or L["SETTINGS_AXIS_Y"], propB, W / 2)
    return row
  end

  local BAR_LABELS = {
    { key = "player",       label = L["SETTINGS_UNIT_PLAYER"] },
    { key = "target",       label = L["SETTINGS_UNIT_TARGET"] },
    { key = "focus",        label = L["SETTINGS_UNIT_FOCUS"] },
    { key = "pet",          label = L["SETTINGS_UNIT_PET"] },
    { key = "targettarget", label = L["SETTINGS_UNIT_TARGET_OF_TARGET"] },
  }

  for _, entry in ipairs(BAR_LABELS) do
    local bk = entry.key

    ctx:Add(SW.CreateSectionHeader(container, entry.label, W))

    local cbBar = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_ENABLE"], L["SETTINGS_UB_BAR_ENABLE_TT"], W))
    cbBar:SetChecked(UBGet(bk, "enabled") ~= false)
    cbBar.onChanged = function(val) UBSet(bk, "enabled", val) end

    local slW = SW.CreateSlider(container, L["SETTINGS_WIDTH"], 40, 700, 1, _ubSL2)
    slW:SetValue(UBGet(bk, "width") or 200)
    slW.onChanged = function(val) UBSet(bk, "width", val) end
    local slH = SW.CreateSlider(container, L["SETTINGS_HEIGHT"], 2, 40, 1, _ubSL2)
    slH:SetValue(UBGet(bk, "height") or 4)
    slH.onChanged = function(val) UBSet(bk, "height", val) end
    ctx:AddRow(8, slW, slH)

    ctx:Add(MakeXYRow(bk, "x", "y", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))
    ctx:Add(MakeXYRow(bk, "nameOffX", "nameOffY", L["SETTINGS_NAME_AXIS_X"], L["SETTINGS_NAME_AXIS_Y"]))

    ctx:Spacer(4)
  end

  ctx:Finalize()
  return ctx.widgets
end

---------------------------------------------------------------------------
-- BUILD : Barre de Cast
---------------------------------------------------------------------------
local function BuildCastBar(container)
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

  -- Helper : ligne de 2 edit boxes (X / Y)
  local function MakeCBXYRow(propA, propB, labelA, labelB)
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 32)
    local function MakeInput(lTxt, prop, xAnchor)
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 11)
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(lTxt)
      lbl:SetPoint("LEFT", row, "LEFT", xAnchor, 6)
      local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
      SW.StyleEditBox(eb)
      eb:SetSize(54, 20)
      eb:SetAutoFocus(false)
      eb:SetNumeric(false)
      eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
      eb:SetText(tostring(CBGet(prop) or 0))
      local function Commit(self)
        local v = tonumber(self:GetText())
        if v then CBSet(prop, v) end
      end
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", Commit)
    end
    MakeInput(labelA, propA, 0)
    MakeInput(labelB, propB, W / 2)
    return row
  end

  -- Helper : 3 boutons alignement (LEFT / CENTER / RIGHT)
  local function MakeAlignRow(prop, options)
    options = options or { { k="LEFT",   l=L["SETTINGS_ALIGN_LEFT"] },
                           { k="CENTER", l=L["SETTINGS_ALIGN_CENTER"] },
                           { k="RIGHT",  l=L["SETTINGS_ALIGN_RIGHT"] } }
    local ABTN_W = 90
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 26)
    local btns = {}
    local function Refresh(val)
      for _, b in ipairs(btns) do
        if b.key == val then
          b._lbl:SetTextColor(unpack(ns.Theme.accent))
          b:SetBackdropColor(0.20, 0.15, 0.08, 1)
        else
          b._lbl:SetTextColor(unpack(ns.Theme.textNormal))
          b:SetBackdropColor(0.08, 0.08, 0.12, 1)
        end
      end
    end
    for i, opt in ipairs(options) do
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
        CBSet(prop, opt.k)
        Refresh(opt.k)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      end)
      table.insert(btns, b)
    end
    Refresh(CBGet(prop) or options[1].k)
    return row
  end

  -- ====== Barre ======
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_CAST_BAR"], W))

  local cbEn = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_CB_ENABLE"], L["SETTINGS_CB_ENABLE_TT"], W))
  cbEn:SetChecked(CBGet("enabled") ~= false)
  cbEn.onChanged = function(val) CBSet("enabled", val) end

  local _cbSL2 = math.floor((W - 8) / 2)
  local slW = SW.CreateSlider(container, L["SETTINGS_WIDTH"], 60, 500, 1, _cbSL2)
  slW:SetValue(CBGet("width") or 260)
  slW.onChanged = function(val) CBSet("width", val) end
  local slH = SW.CreateSlider(container, L["SETTINGS_HEIGHT"], 1, 20, 1, _cbSL2)
  slH:SetValue(CBGet("height") or 3)
  slH.onChanged = function(val) CBSet("height", val) end
  ctx:AddRow(8, slW, slH)

  -- ====== Position ======
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
      local xEb = _G["AishaddonCBXEditBox"]
      local yEb = _G["AishaddonCBYEditBox"]
      if xEb then xEb:SetText(tostring(math.floor((db and db.x) or CBGet("x") or 0))) end
      if yEb then yEb:SetText(tostring(math.floor((db and db.y) or CBGet("y") or 0))) end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(dragBtn)

  -- Champs X/Y nommEs (avec des noms globaux pour la mise E jour post-drag)
  local xyRow = CreateFrame("Frame", nil, container)
  xyRow:SetSize(W, 32)
  local function MakePosInput(lTxt, prop, globalName, xAnchor)
    local lbl = xyRow:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 11)
    lbl:SetTextColor(unpack(ns.Theme.textNormal))
    lbl:SetText(lTxt)
    lbl:SetPoint("LEFT", xyRow, "LEFT", xAnchor, 6)
    local eb = CreateFrame("EditBox", globalName, xyRow, "InputBoxTemplate")
    SW.StyleEditBox(eb)
    eb:SetSize(70, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(false)
    eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
    eb:SetText(tostring(CBGet(prop) or 0))
    local function Commit(self)
      local v = tonumber(self:GetText())
      if v then CBSet(prop, v) end
    end
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", Commit)
  end
  MakePosInput(L["SETTINGS_AXIS_X"], "x", "AishaddonCBXEditBox", 0)
  MakePosInput(L["SETTINGS_AXIS_Y"], "y", "AishaddonCBYEditBox", W / 2)
  ctx:Add(xyRow)

  -- Remarque : X/Y sont relatifs E UIParent CENTER
  local hint = container:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 10)
  hint:SetTextColor(0.55, 0.55, 0.55, 1)
  hint:SetText(L["UI_OFFSET_HINT"])
  hint:SetJustifyH("LEFT")
  hint:SetSize(W - 10, 18)
  ctx:Add(hint)

  local cbSchool = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_CB_COLOR_BY_SCHOOL"],
    L["SETTINGS_CB_COLOR_BY_SCHOOL_TT"], W))
  cbSchool:SetChecked(CBGet("colorBySchool") or false)
  cbSchool.onChanged = function(val) CBSet("colorBySchool", val) end

  -- ====== Texte Nom ======
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SPELL_NAME_TEXT"], W))

  local slNS = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 28, 1, W))
  slNS:SetValue(CBGet("nameSize") or 12)
  slNS.onChanged = function(val) CBSet("nameSize", val) end

  local ddCBFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_UB_NAME_FONT"], ns.GetFontList(), 220))
  do
    local _v = CBGet("font"); if _v then ddCBFont:SetValue(_v) end
    ddCBFont.onChanged = function(val) CBSet("font", val) end
  end

  ctx:Add(MakeCBXYRow("nameOffX", "nameOffY", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CB_NAME_ALIGNMENT"], W))
  ctx:Add(MakeAlignRow("nameJustify"))

  -- ====== Texte Timer ======
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TIMER_TEXT"], W))

  local slTS = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 20, 1, W))
  slTS:SetValue(CBGet("timerSize") or 8)
  slTS.onChanged = function(val) CBSet("timerSize", val) end

  local ddCBTimerFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_CB_TIMER_FONT"], ns.GetFontList(), 220))
  do
    local _v = CBGet("timerFont"); if _v then ddCBTimerFont:SetValue(_v) end
    ddCBTimerFont.onChanged = function(val) CBSet("timerFont", val) end
  end

  ctx:Add(MakeCBXYRow("timerOffX", "timerOffY", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CB_TIMER_ALIGNMENT"], W))
  ctx:Add(MakeAlignRow("timerJustify"))

  ctx:Finalize()
  return ctx.widgets
end

---------------------------------------------------------------------------
-- BUILD : Barre de Cast Cible
---------------------------------------------------------------------------
local function BuildTargetCastBar(container)
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

  -- Helper : ligne de 2 edit boxes (X / Y)
  local function MakeTCBXYRow(propA, propB, labelA, labelB)
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 32)
    local function MakeInput(lTxt, prop, xAnchor)
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 11)
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(lTxt)
      lbl:SetPoint("LEFT", row, "LEFT", xAnchor, 6)
      local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
      SW.StyleEditBox(eb)
      eb:SetSize(54, 20)
      eb:SetAutoFocus(false)
      eb:SetNumeric(false)
      eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
      eb:SetText(tostring(TCBGet(prop) or 0))
      local function Commit(self)
        local v = tonumber(self:GetText())
        if v then TCBSet(prop, v) end
      end
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", Commit)
    end
    MakeInput(labelA, propA, 0)
    MakeInput(labelB, propB, W / 2)
    return row
  end

  -- Helper : 3 boutons alignement
  local function MakeTCBAlignRow(prop, options)
    options = options or { { k="LEFT", l=L["SETTINGS_ALIGN_LEFT"] }, { k="CENTER", l=L["SETTINGS_ALIGN_CENTER"] }, { k="RIGHT", l=L["SETTINGS_ALIGN_RIGHT"] } }
    local ABTN_W = 90
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 26)
    local btns = {}
    local function Refresh(val)
      for _, b in ipairs(btns) do
        if b.key == val then
          b._lbl:SetTextColor(unpack(ns.Theme.accent))
          b:SetBackdropColor(0.20, 0.15, 0.08, 1)
        else
          b._lbl:SetTextColor(unpack(ns.Theme.textNormal))
          b:SetBackdropColor(0.08, 0.08, 0.12, 1)
        end
      end
    end
    for i, opt in ipairs(options) do
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
        TCBSet(prop, opt.k)
        Refresh(opt.k)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      end)
      table.insert(btns, b)
    end
    Refresh(TCBGet(prop) or options[1].k)
    return row
  end

  -- ====== Barre ======
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TARGET_CAST_BAR"], W))

  local tcbEn = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TCB_ENABLE"], L["SETTINGS_TCB_ENABLE_TT"], W))
  tcbEn:SetChecked(TCBGet("enabled") ~= false)
  tcbEn.onChanged = function(val) TCBSet("enabled", val) end

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

  -- ====== Position ======
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
      local xEb = _G["AishaddonTCBXEditBox"]
      local yEb = _G["AishaddonTCBYEditBox"]
      if xEb then xEb:SetText(tostring(math.floor((db and db.x) or TCBGet("x") or 0))) end
      if yEb then yEb:SetText(tostring(math.floor((db and db.y) or TCBGet("y") or 0))) end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  ctx:Add(tcbDragBtn)

  -- Champs X/Y
  local tcbXYRow = CreateFrame("Frame", nil, container)
  tcbXYRow:SetSize(W, 32)
  local function MakeTCBPosInput(lTxt, prop, globalName, xAnchor)
    local lbl = tcbXYRow:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 11)
    lbl:SetTextColor(unpack(ns.Theme.textNormal))
    lbl:SetText(lTxt)
    lbl:SetPoint("LEFT", tcbXYRow, "LEFT", xAnchor, 6)
    local eb = CreateFrame("EditBox", globalName, tcbXYRow, "InputBoxTemplate")
    SW.StyleEditBox(eb)
    eb:SetSize(70, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(false)
    eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
    eb:SetText(tostring(TCBGet(prop) or 0))
    local function Commit(self)
      local v = tonumber(self:GetText())
      if v then TCBSet(prop, v) end
    end
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", Commit)
  end
  MakeTCBPosInput(L["SETTINGS_AXIS_X"], "x", "AishaddonTCBXEditBox", 0)
  MakeTCBPosInput(L["SETTINGS_AXIS_Y"], "y", "AishaddonTCBYEditBox", W / 2)
  ctx:Add(tcbXYRow)

  local tcbHint = container:CreateFontString(nil, "OVERLAY")
  tcbHint:SetFont(ns.Media.fontGui, 10)
  tcbHint:SetTextColor(0.55, 0.55, 0.55, 1)
  tcbHint:SetText(L["UI_OFFSET_HINT"])
  tcbHint:SetJustifyH("LEFT")
  tcbHint:SetSize(W - 10, 18)
  ctx:Add(tcbHint)

  -- ====== Couleurs ======
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_COLORS"], W))

  local colInt = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_INTERRUPTIBLE"], W))
  do local c = TCBGet("colorInterruptible") or {0,0.78,0.78,1}; colInt:SetColor(c[1],c[2],c[3],c[4]) end
  colInt.onChanged = function(val) TCBSet("colorInterruptible", val) end

  local colImp = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_IMPORTANT"], W))
  do local c = TCBGet("colorImportant") or {0.855,0.239,1,1}; colImp:SetColor(c[1],c[2],c[3],c[4]) end
  colImp.onChanged = function(val) TCBSet("colorImportant", val) end

  local colNI = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_NOT_INTERRUPTIBLE"], W))
  do local c = TCBGet("colorNotInterruptible") or {0.765,0.294,0.290,1}; colNI:SetColor(c[1],c[2],c[3],c[4]) end
  colNI.onChanged = function(val) TCBSet("colorNotInterruptible", val) end

  local colCh = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TCB_COLOR_CHANNELING"], W))
  do local c = TCBGet("colorChanneling") or {0.506,0.788,0.243,1}; colCh:SetColor(c[1],c[2],c[3],c[4]) end
  colCh.onChanged = function(val) TCBSet("colorChanneling", val) end

  -- ====== Texte Nom ======
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SPELL_NAME_TEXT"], W))

  local slTCBNS = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 28, 1, W))
  slTCBNS:SetValue(TCBGet("nameSize") or 12)
  slTCBNS.onChanged = function(val) TCBSet("nameSize", val) end

  local ddTCBFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_UB_NAME_FONT"], ns.GetFontList(), 220))
  do
    local _v = TCBGet("font"); if _v then ddTCBFont:SetValue(_v) end
    ddTCBFont.onChanged = function(val) TCBSet("font", val) end
  end

  ctx:Add(MakeTCBXYRow("nameOffX", "nameOffY", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CB_NAME_ALIGNMENT"], W))
  ctx:Add(MakeTCBAlignRow("nameJustify"))

  -- ====== Texte Timer ======
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TIMER_TEXT"], W))

  local slTCBTS = ctx:Add(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 20, 1, W))
  slTCBTS:SetValue(TCBGet("timerSize") or 8)
  slTCBTS.onChanged = function(val) TCBSet("timerSize", val) end

  local ddTCBTimerFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_CB_TIMER_FONT"], ns.GetFontList(), 220))
  do
    local _v = TCBGet("timerFont"); if _v then ddTCBTimerFont:SetValue(_v) end
    ddTCBTimerFont.onChanged = function(val) TCBSet("timerFont", val) end
  end

  ctx:Add(MakeTCBXYRow("timerOffX", "timerOffY", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CB_TIMER_ALIGNMENT"], W))
  ctx:Add(MakeTCBAlignRow("timerJustify"))

  ctx:Finalize()
  return ctx.widgets
end

---------------------------------------------------------------------------
-- BUILD : Animations 3D (Effets de Sort)
---------------------------------------------------------------------------
-- Helpers locaux pour le combo editor
local seSelectedSpellID = nil  -- spellID actuellement sélectionné dans la liste gauche
local seSelectedAuraID  = nil  -- auraID actuellement sélectionné (section Auras)
local seSelectedAnimIdx = nil  -- index de l'animation sélectionnée dans le combo
local seSpellList       = nil  -- frame de la liste de sorts (scrollable)
local seAuraList        = nil  -- frame de la liste d'auras (scrollable)
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
  -- Fallback ancien API
  local name, _, icon = GetSpellInfo(spellID)
  return name or string.format(L["SETTINGS_SPELL_FALLBACK_NAME"], spellID), icon or 134400
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

-- Section active et sélection inter-sections (Sorts / Orbes / OOC / Auras)
local seActiveSection      = "spells"  -- "spells" | "orbs" | "ooc" | "auras"
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
  WARLOCK = {
    { key = "demonic_core",     label = L["SETTINGS_ORB_DEMONIC_CORE"] },
    { key = "demonic_core_max", label = L["SETTINGS_ORB_DEMONIC_CORE_MAX"] },
  },
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
  end
  return nil, nil
end

-- Retourne l'ancre (ou table d'ancres) de preview selon la section active
local function GetPreviewAnchor()
  if seActiveSection == "ooc" then
    return _G["AishaddonHealthRing"]
  elseif seActiveSection == "orbs" then
    -- Collecter TOUS les globes visibles pour multi-anchor preview
    local anchors = {}
    for i = 1, 10 do
      local dot = _G["AishaddonSecDot" .. i]
      if dot and dot:IsShown() then anchors[#anchors + 1] = dot end
    end
    if #anchors == 0 then
      for i = 1, 10 do
        local dot = _G["AishaddonOCSecDot" .. i]
        if dot and dot:IsShown() then anchors[#anchors + 1] = dot end
      end
    end
    if #anchors > 0 then return anchors end
  end
  return nil  -- nil = utilise l'ancre par défaut (AishaddonRingBar)
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
local RefreshOrbList, RefreshOocList, RefreshAuraList, RelayoutSections

---------------------------------------------------------------------------
-- Lookup : FileID ? nom de modèle via AishaddonModelPaths (Data\ModelPaths.lua)
---------------------------------------------------------------------------
local seModelNameCache = {}  -- fileID(number) ? "name.m2"

local function GetModelPathsData()
  return AishaddonModelPaths
end

local function StripM2(name)
  if not name then return name end
  return name:gsub("%.m2$", ""):gsub("%.M2$", "")
end

local function GetModelNameByFileID(fileID)
  if not fileID or fileID == 0 then return nil end
  if seModelNameCache[fileID] then return seModelNameCache[fileID] end
  -- Utilise ns._modelFlat (table compacte créée au login depuis AishaddonModelPaths)
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

---------------------------------------------------------------------------
-- Model Picker Frame (singleton)
---------------------------------------------------------------------------

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

  local f = CreateFrame("Frame", "AishaddonModelPicker", UIParent, "BackdropTemplate")
  f:SetSize(900 + TAG_W, 640)
  f:SetFrameStrata("HIGH")
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
  title:SetTextColor(unpack(Theme.accent))
  title:SetText(L["SETTINGS_MODEL_PICKER_TITLE"])

  -- Layout columns
  local LEFT_W = 340
  local RIGHT_W = 520

  ---------------------------------------------------------------------------
  -- Tag sidebar (colonne gauche)
  ---------------------------------------------------------------------------
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
  tagScrollFrame:EnableMouseWheel(true)
  tagScrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 40)))
  end)

  local tagBtnPool = {}
  local tagButtons  = {}
  f._activeTag  = nil   -- label du tag actif ou nil
  f._deleteMode = false -- mode "choisir un tag E supprimer"

  ---------------------------------------------------------------------------
  -- RebuildTagSidebar : recrée/reconfigure tous les boutons depuis MODEL_TAGS
  ---------------------------------------------------------------------------
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
    self:RefreshTagDimming()
  end

  ---------------------------------------------------------------------------
  -- Bouton "+ Nouveau tag"
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- Bouton "Supprimer" (rouge E mode suppression)
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- Search box + model list (dEcalEs E droite du tag sidebar)
  ---------------------------------------------------------------------------
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
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 60)))
    f:RenderVisible()
  end)

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

  ---------------------------------------------------------------------------
  -- Right-click tag context menu (frame custom, pas d'EasyMenu)
  ---------------------------------------------------------------------------
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
      if IsMouseButtonDown("LeftButton") and not ctxMenu:IsMouseOver() then
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

  ---------------------------------------------------------------------------
  -- Keyword Editor (clic droit sur un tag de la sidebar)
  ---------------------------------------------------------------------------
  local KW_W       = 254
  local KW_H       = 300
  local KW_CHIP_H  = 18
  local KW_PAD     = 6   -- padding horizontal dans un chip
  local KW_X_W     = 16  -- largeur du bouton X
  local KW_GAP_X   = 4
  local KW_GAP_Y   = 4
  local KW_AREA_W  = KW_W - 20  -- largeur utile pour les chips

  local kwEditor = CreateFrame("Frame", "AishaddonKwEditor", f, "BackdropTemplate")
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
      if IsMouseButtonDown("LeftButton") and not kwEditor:IsMouseOver() then
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
  kwScroll:EnableMouseWheel(true)
  kwScroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local max = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 30)))
  end)
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

  ---------------------------------------------------------------------------
  -- Right panel: controls area (compact E sliders + Ajouter sur une ligne)
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- Right panel: preview area (fills space above ctrlPanel)
  ---------------------------------------------------------------------------
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
    -- Construire self._allModels depuis ns._modelFlat (déjà libéré de AishaddonModelPaths au login)
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
      table.sort(models, function(a, b) return a.text < b.text end)
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
    f:SetResizeBounds(900 + TAG_W, 640, 1400 + TAG_W, 1000)
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

---------------------------------------------------------------------------
-- Spell Picker for Animations 3D (rEutilise les spec spells)
---------------------------------------------------------------------------
local SESpellPickerFrame  -- singleton sEparE pour SpellEffects

---------------------------------------------------------------------------
-- Un Button mouse-enabled au-dessus d'un ScrollFrame "avale" la molette
-- (seul le frame topmost avec EnableMouse reçoit l'event) : on relaie
-- explicitement vers le ScrollFrame parent (row -> content -> scrollFrame)
-- pour pouvoir scroller en survolant directement les lignes de la liste.
---------------------------------------------------------------------------
local function ForwardMouseWheelToScrollParent(row)
  row:EnableMouseWheel(true)
  row:SetScript("OnMouseWheel", function(self, delta)
    local content = self:GetParent()
    local scrollFrame = content and content:GetParent()
    local handler = scrollFrame and scrollFrame:GetScript("OnMouseWheel")
    if handler then handler(scrollFrame, delta) end
  end)
end

---------------------------------------------------------------------------
-- Spell List (panneau gauche : liste des sorts configurEs)
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Anim List Row (une entrEe dans le combo du sort)
---------------------------------------------------------------------------
local function BuildAnimRow(parent, idx, anim, width, onClick, onTriggerChange, hideHC)
  local CB_SIZE = 14
  local CB_COL_W = 20  -- width per checkbox column
  local LABEL_LEFT = hideHC and 6 or (CB_COL_W * 2 + 6)
  local TOGGLE_W = 28

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

  -- Checkbox "On Hit"
  local cbHit = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cbHit:SetSize(CB_SIZE, CB_SIZE)
  cbHit:SetPoint("LEFT", row, "LEFT", 3, 0)
  cbHit:SetChecked((anim.trigger or "onhit") == "onhit")
  cbHit:SetScript("OnClick", function(self)
    anim.trigger = self:GetChecked() and "onhit" or "casting"
    if not self:GetChecked() then
      anim.trigger = "casting"
    end
    if onTriggerChange then onTriggerChange() end
  end)

  -- Checkbox "Casting"
  local cbCast = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  cbCast:SetSize(CB_SIZE, CB_SIZE)
  cbCast:SetPoint("LEFT", row, "LEFT", 3 + CB_COL_W, 0)
  cbCast:SetChecked(anim.trigger == "casting")
  cbCast:SetScript("OnClick", function(self)
    anim.trigger = self:GetChecked() and "casting" or "onhit"
    if not self:GetChecked() then
      anim.trigger = "onhit"
    end
    if onTriggerChange then onTriggerChange() end
  end)

  if hideHC then
    cbHit:Hide()
    cbCast:Hide()
  end

  row._cbHit  = cbHit
  row._cbCast = cbCast

  -- Label
  row.label = row:CreateFontString(nil, "OVERLAY")
  row.label:SetFont(ns.Media.fontGui, 10)
  row.label:SetPoint("LEFT", row, "LEFT", LABEL_LEFT, 0)
  row.label:SetPoint("RIGHT", row, "RIGHT", -(TOGGLE_W + 4), 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetTextColor(unpack(Theme.textNormal))

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

---------------------------------------------------------------------------
-- Trigger List Row (pour Globes Externes et Cercle de vie HC)
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Indicateur de scroll "moderne" (fin, doré, auto-masquant)
-- Même DA que le scroll principal du panneau de settings (cf. lignes ~105-150) :
-- masque la scrollbar Blizzard et affiche un rail/curseur discret qui ne
-- s'affiche que si le contenu dépasse réellement la zone visible.
---------------------------------------------------------------------------
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
    self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 40)))
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

---------------------------------------------------------------------------
-- BuildSpellEffects E construction du panneau complet
---------------------------------------------------------------------------
local function BuildSpellEffects(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_3D_ANIMATIONS"], W))

  -- Enable checkbox
  local cb = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SE_ENABLE"],
    L["SETTINGS_SE_ENABLE_TT"], W))
  BindCheckbox(cb, "spellEffects", "enabled")
  ctx:Spacer(6)

  ---------------------------------------------------------------------------
  -- Layout : [Spell List (gauche)] [Anim List + Editor (droite)]
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- GAUCHE : Sections repliables (Sorts / Orbes / Cercle OOC)
  ---------------------------------------------------------------------------
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
    arrow:SetTextColor(unpack(Theme.accent))
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

  -- -----------------------------------------------------------------------
  -- Section 1 : Sorts configurés
  -- -----------------------------------------------------------------------
  local sec1 = { expanded = true }
  sec1.header = CreateSectionHdr(leftContent, L["SETTINGS_SEC_CONFIGURED_SPELLS"])
  sec1.body = CreateFrame("Frame", nil, leftContent)
  sec1.body:SetWidth(LEFT_W - 20)
  -- Overhead fixe quand une seule section est ouverte :
  -- 4 en-têtes × SEC_HDR_H(22) + 3 séparateurs × DIVIDER_H(6) = 106 px
  local SECTIONS_OVERHEAD = 4 * SEC_HDR_H + 3 * DIVIDER_H
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
    seSelectedSpellID = sid
    seSelectedTriggerKey = nil
    seSelectedAuraID = nil
    seSelectedAnimIdx = 1
    RefreshSpellList()
    if RefreshOrbList then RefreshOrbList() end
    if RefreshOocList then RefreshOocList() end
    if RefreshAuraList then RefreshAuraList() end
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

  -- -----------------------------------------------------------------------
  -- Section OOC : Cercle de vie Hors-Combat
  -- -----------------------------------------------------------------------
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

  -- -----------------------------------------------------------------------
  -- Section Spells : Sorts configurés (sec1 — déjà créé au-dessus)
  -- -----------------------------------------------------------------------
  local secSpells = sec1
  secSpells.id = "spells"

  -- -----------------------------------------------------------------------
  -- Section Orbs : Globes Externes
  -- -----------------------------------------------------------------------
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

  -- -----------------------------------------------------------------------
  -- Section Auras : combos déclenchés par la présence d'une aura
  -- (même liste que "Auras à tracker" — apparition de l'aura → lecture en boucle)
  -- -----------------------------------------------------------------------
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

  -- Sections ordonnées : OOC, Sorts, Orbes, Auras
  seSections[1] = secOoc
  seSections[2] = secSpells
  seSections[3] = secOrbs
  seSections[4] = secAuras

  secOoc.divider    = CreateSectionDivider(leftContent)
  secSpells.divider = CreateSectionDivider(leftContent)
  secOrbs.divider   = CreateSectionDivider(leftContent)
  -- pas de divider après la dernière section

  for _, sec in ipairs(seSections) do UpdateArrow(sec) end

  -- -----------------------------------------------------------------------
  -- Layout & toggle des sections (accordéon)
  -- -----------------------------------------------------------------------
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

  -- Ouvrir Sorts par défaut
  secSpells.expanded = true
  UpdateArrow(secSpells)
  RelayoutSections()

  ---------------------------------------------------------------------------
  -- DROITE : Combo list + Animation editor
  ---------------------------------------------------------------------------
  local rightPanel = CreateFrame("Frame", nil, hPanel)
  rightPanel:SetSize(RIGHT_W, PANEL_H)
  rightPanel:SetPoint("TOPRIGHT", hPanel, "TOPRIGHT", 0, 0)

  -- Titre
  local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY")
  rightTitle:SetFont(ns.Media.fontGui, 10)
  rightTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -2)
  rightTitle:SetTextColor(unpack(Theme.textDim))
  rightTitle:SetText(L["SETTINGS_COMBO_NO_SPELL_SELECTED"])

  -- En-têtes de colonnes pour les checkboxes (On Hit / Casting)
  local colHeaderFrame = CreateFrame("Frame", nil, rightPanel)
  colHeaderFrame:SetSize(RIGHT_W - 18, 14)
  colHeaderFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 4, -16)

  local hdrHit = colHeaderFrame:CreateFontString(nil, "OVERLAY")
  hdrHit:SetFont(ns.Media.fontGui, 8)
  hdrHit:SetPoint("LEFT", colHeaderFrame, "LEFT", 3, 0)
  hdrHit:SetTextColor(unpack(Theme.textDim))
  hdrHit:SetText("H")

  local hdrCast = colHeaderFrame:CreateFontString(nil, "OVERLAY")
  hdrCast:SetFont(ns.Media.fontGui, 8)
  hdrCast:SetPoint("LEFT", colHeaderFrame, "LEFT", 23, 0)
  hdrCast:SetTextColor(unpack(Theme.textDim))
  hdrCast:SetText("C")

  local hdrModel = colHeaderFrame:CreateFontString(nil, "OVERLAY")
  hdrModel:SetFont(ns.Media.fontGui, 8)
  hdrModel:SetPoint("LEFT", colHeaderFrame, "LEFT", 46, 0)
  hdrModel:SetTextColor(unpack(Theme.textDim))
  hdrModel:SetText(L["SETTINGS_MODEL"])

  -- Références pour masquer les colonnes H/C selon la section active
  local _hdrHit  = hdrHit
  local _hdrCast = hdrCast
  local _hdrModel = hdrModel

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
      s._lbl:SetTextColor(unpack(Theme.accent))
    end
  end)

  ---------------------------------------------------------------------------
  -- Ligne "Alt IDs" : IDs déclencheurs alternatifs pour le sort sélectionné
  ---------------------------------------------------------------------------
  local _aliasChips = {}
  local seAliasInput

  local aliasRow = CreateFrame("Frame", nil, rightPanel)
  aliasRow:SetSize(RIGHT_W - 18, 26)
  aliasRow:SetPoint("TOPLEFT", animAddBtn, "BOTTOMLEFT", 0, -4)
  aliasRow:Hide()  -- visible seulement quand un sort est sélectionné

  local aliasLabel = aliasRow:CreateFontString(nil, "OVERLAY")
  aliasLabel:SetFont(ns.Media.fontGui, 9)
  aliasLabel:SetPoint("LEFT", aliasRow, "LEFT", 2, 0)
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
    ibg:SetPoint("RIGHT", aliasRow, "RIGHT", -26, 0)
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

  -- Bouton "+" alias
  local aliasAddBtn = SW.CreateActionBtn(aliasRow, "+", 22,
    { 0.06, 0.14, 0.06, 0.9 }, nil, Theme.accentGreen)
  aliasAddBtn:SetPoint("RIGHT", aliasRow, "RIGHT", -2, 0)
  aliasAddBtn:SetPoint("TOP",   aliasRow, "TOP",   0, -4)
  aliasAddBtn:SetScript("OnClick", function()
    if not seAliasInput or not seSelectedSpellID then return end
    local aliasID = tonumber(seAliasInput:GetText())
    if aliasID and aliasID > 0 then
      GetCombosAliasesDB()[aliasID] = seSelectedSpellID
      seAliasInput:SetText(""); RefreshAliasRow()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
  end)

  ---------------------------------------------------------------------------
  -- DROITE BAS : Éditeur d'animation (compact : sliders 3 par ligne)
  ---------------------------------------------------------------------------
  local editorTop = animScroll:GetHeight() + 20 + 26 + 8 + 30  -- +30 pour la ligne Alt IDs
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
      s._lbl:SetTextColor(unpack(Theme.accent))
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

  ---------------------------------------------------------------------------
  -- Foreground / Background radio toggle
  ---------------------------------------------------------------------------
  local strataFrame = CreateFrame("Frame", nil, edContent)
  strataFrame:SetSize(edW, 20)
  strataFrame:SetPoint("TOPLEFT", edContent, "TOPLEFT", 4, -56)

  local strataLabel = strataFrame:CreateFontString(nil, "OVERLAY")
  strataLabel:SetFont(ns.Media.fontGui, 9)
  strataLabel:SetPoint("LEFT", strataFrame, "LEFT", 0, 0)
  strataLabel:SetTextColor(unpack(Theme.textDim))
  strataLabel:SetText(L["SETTINGS_LAYER"])

  local strataBgBtn = CreateFrame("Button", nil, strataFrame)
  strataBgBtn:SetSize(80, 18)
  strataBgBtn:SetPoint("LEFT", strataLabel, "RIGHT", 8, 0)

  local strataBgRing = strataBgBtn:CreateTexture(nil, "ARTWORK")
  strataBgRing:SetSize(12, 12)
  strataBgRing:SetPoint("LEFT", strataBgBtn, "LEFT", 0, 0)
  strataBgRing:SetColorTexture(unpack(Theme.checkboxOff))
  local strataBgDot = strataBgBtn:CreateTexture(nil, "OVERLAY")
  strataBgDot:SetSize(8, 8)
  strataBgDot:SetPoint("CENTER", strataBgRing, "CENTER")
  strataBgDot:SetColorTexture(unpack(Theme.checkboxOn))
  local strataBgLabel = strataBgBtn:CreateFontString(nil, "OVERLAY")
  strataBgLabel:SetFont(ns.Media.fontGui, 9)
  strataBgLabel:SetPoint("LEFT", strataBgRing, "RIGHT", 4, 0)
  strataBgLabel:SetTextColor(unpack(Theme.textNormal))
  strataBgLabel:SetText(L["SETTINGS_LAYER_BACKGROUND"])

  local strataFgBtn = CreateFrame("Button", nil, strataFrame)
  strataFgBtn:SetSize(80, 18)
  strataFgBtn:SetPoint("LEFT", strataBgBtn, "RIGHT", 6, 0)

  local strataFgRing = strataFgBtn:CreateTexture(nil, "ARTWORK")
  strataFgRing:SetSize(12, 12)
  strataFgRing:SetPoint("LEFT", strataFgBtn, "LEFT", 0, 0)
  strataFgRing:SetColorTexture(unpack(Theme.checkboxOff))
  local strataFgDot = strataFgBtn:CreateTexture(nil, "OVERLAY")
  strataFgDot:SetSize(8, 8)
  strataFgDot:SetPoint("CENTER", strataFgRing, "CENTER")
  strataFgDot:SetColorTexture(unpack(Theme.checkboxOn))
  local strataFgLabel = strataFgBtn:CreateFontString(nil, "OVERLAY")
  strataFgLabel:SetFont(ns.Media.fontGui, 9)
  strataFgLabel:SetPoint("LEFT", strataFgRing, "RIGHT", 4, 0)
  strataFgLabel:SetTextColor(unpack(Theme.textNormal))
  strataFgLabel:SetText(L["SETTINGS_LAYER_MIDGROUND"])

  local strataTopBtn = CreateFrame("Button", nil, strataFrame)
  strataTopBtn:SetSize(85, 18)
  strataTopBtn:SetPoint("LEFT", strataFgBtn, "RIGHT", 6, 0)

  local strataTopRing = strataTopBtn:CreateTexture(nil, "ARTWORK")
  strataTopRing:SetSize(12, 12)
  strataTopRing:SetPoint("LEFT", strataTopBtn, "LEFT", 0, 0)
  strataTopRing:SetColorTexture(unpack(Theme.checkboxOff))
  local strataTopDot = strataTopBtn:CreateTexture(nil, "OVERLAY")
  strataTopDot:SetSize(8, 8)
  strataTopDot:SetPoint("CENTER", strataTopRing, "CENTER")
  strataTopDot:SetColorTexture(unpack(Theme.checkboxOn))
  local strataTopLabel = strataTopBtn:CreateFontString(nil, "OVERLAY")
  strataTopLabel:SetFont(ns.Media.fontGui, 9)
  strataTopLabel:SetPoint("LEFT", strataTopRing, "RIGHT", 4, 0)
  strataTopLabel:SetTextColor(unpack(Theme.textNormal))
  strataTopLabel:SetText(L["SETTINGS_LAYER_FOREGROUND"])

  local function RefreshStrataRadio()
    local db, key = GetActiveComboTable()
    local combo = db and key and db[key]
    local anim = combo and seSelectedAnimIdx and combo[seSelectedAnimIdx]
    local strata = anim and anim.strata or "BACKGROUND"

    -- Masquer "Moyen plan" pour les globes (seulement arrière/premier)
    local showMid = (seActiveSection ~= "orbs")
    strataFgBtn:SetShown(showMid)
    if showMid then
      strataTopBtn:ClearAllPoints()
      strataTopBtn:SetPoint("LEFT", strataFgBtn, "RIGHT", 6, 0)
    else
      strataTopBtn:ClearAllPoints()
      strataTopBtn:SetPoint("LEFT", strataBgBtn, "RIGHT", 6, 0)
    end

    local isMid = (strata == "HIGH" or strata == "MEDIUM")
    local isTop = (strata == "FOREGROUND")
    if isTop then
      strataTopRing:SetColorTexture(unpack(Theme.checkboxOn))
      strataTopDot:Show()
      strataFgRing:SetColorTexture(unpack(Theme.checkboxOff))
      strataFgDot:Hide()
      strataBgRing:SetColorTexture(unpack(Theme.checkboxOff))
      strataBgDot:Hide()
    elseif isMid and showMid then
      strataFgRing:SetColorTexture(unpack(Theme.checkboxOn))
      strataFgDot:Show()
      strataBgRing:SetColorTexture(unpack(Theme.checkboxOff))
      strataBgDot:Hide()
      strataTopRing:SetColorTexture(unpack(Theme.checkboxOff))
      strataTopDot:Hide()
    else
      strataBgRing:SetColorTexture(unpack(Theme.checkboxOn))
      strataBgDot:Show()
      strataFgRing:SetColorTexture(unpack(Theme.checkboxOff))
      strataFgDot:Hide()
      strataTopRing:SetColorTexture(unpack(Theme.checkboxOff))
      strataTopDot:Hide()
    end
  end
  seAnimEditor._refreshStrata = RefreshStrataRadio

  strataBgBtn:SetScript("OnClick", function()
    SetAnimField("strata", "BACKGROUND")
    RefreshStrataRadio()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  strataFgBtn:SetScript("OnClick", function()
    SetAnimField("strata", "HIGH")
    RefreshStrataRadio()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  strataTopBtn:SetScript("OnClick", function()
    SetAnimField("strata", "FOREGROUND")
    RefreshStrataRadio()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)

  ---------------------------------------------------------------------------
  -- Compact sliders : 3 par ligne, avec valeur Editable
  ---------------------------------------------------------------------------
  local COLS         = 3
  local COL_GAP      = 6
  local ROW_H        = 65   -- hauteur d'un mini-slider (SW.CreateSlider ~58px)
  local miniSliderW  = math.floor((edW - (COLS - 1) * COL_GAP) / COLS)
  local gridTopY     = -78  -- Y de dEpart sous la radio strata

  local sliderDefs = {
    -- Ligne 1 : X, Y, Z
    { key = "x",         label = L["SETTINGS_ANIM_X_OFFSET"], min = -30, max = 30,  step = 0.01, fmt = "%.2f" },
    { key = "y",         label = L["SETTINGS_ANIM_Y_OFFSET"], min = -30, max = 30,  step = 0.01, fmt = "%.2f" },
    { key = "z",         label = L["SETTINGS_AXIS_Z_DEPTH"],  min = -30, max = 30,  step = 0.01, fmt = "%.2f" },
    -- Ligne 2 : Échelle, Rotation, Opacité
    { key = "scale",     label = L["SETTINGS_SCALE"],    min = 0.1, max = 5,   step = 0.01, fmt = "%.2f" },
    { key = "rotation",  label = L["SETTINGS_ROTATION"],   min = 0,   max = 360, step = 0.1,  fmt = "%.1f" },
    { key = "alpha",     label = L["SETTINGS_OPACITY"],    min = 0,   max = 1,   step = 0.01, fmt = "%.2f" },
    -- Ligne 3 : Offset X (Pos. X), Offset Y (Pos. Y), Délai
    { key = "anchorX",   label = L["SETTINGS_POS_X"],     min = -800, max = 800, step = 1,   fmt = "%.0f" },
    { key = "anchorY",   label = L["SETTINGS_POS_Y"],     min = -800, max = 800, step = 1,   fmt = "%.0f" },
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

  -- Stop All button
  local numRows = math.ceil(#sliderDefs / COLS)
  local stopBtnY = gridTopY - numRows * ROW_H - 8
  local stopBtn = CreateFrame("Button", nil, edContent)
  stopBtn:SetSize(edW, 24)
  stopBtn:SetPoint("TOPLEFT", edContent, "TOPLEFT", 0, stopBtnY)
  do
    local bg = stopBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.18, 0.06, 0.06, 0.9)
    stopBtn.text = stopBtn:CreateFontString(nil, "OVERLAY")
    stopBtn.text:SetFont(ns.Media.fontGui, 11); stopBtn.text:SetPoint("CENTER")
    stopBtn.text:SetText(L["SETTINGS_STOP_ALL_ANIMS"])
    stopBtn.text:SetTextColor(1, 0.4, 0.4)
    stopBtn:SetScript("OnEnter", function(s) s.text:SetTextColor(1,1,1) end)
    stopBtn:SetScript("OnLeave", function(s) s.text:SetTextColor(1, 0.4, 0.4) end)
    stopBtn:SetScript("OnClick", function()
      local SE = ns.Modules.SpellEffects
      -- Stopper uniquement les previews, PAS les animations en conditions réelles
      if SE and SE.StopDecoPreview then SE.StopDecoPreview() end
      if SE and SE.StopPreview then SE.StopPreview() end
      if SE and SE.StopComboPreview then SE.StopComboPreview() end
      -- Relancer les décorations réelles
      if SE and SE.RefreshDecorations then SE.RefreshDecorations() end
      -- Reset preview button states
      previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
      previewBtn._lbl:SetTextColor(unpack(Theme.accent))
      previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
      previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
    end)
  end

  edContent:SetHeight(math.abs(stopBtnY) + 30)

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

  ---------------------------------------------------------------------------
  -- Refresh functions
  ---------------------------------------------------------------------------
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
    -- Trier par ordre alphabétique du nom
    table.sort(filtered, function(a, b)
      local nameA = GetSpellInfo3D(a) or ""
      local nameB = GetSpellInfo3D(b) or ""
      return strlower(nameA) < strlower(nameB)
    end)
    sorted = filtered

    local rowW = LEFT_W - 38
    local yy = 0
    for _, sid in ipairs(sorted) do
      local row = BuildSpellListRow(seSpellList, sid, rowW, function(clickedID)
        seActiveSection = "spells"
        seSelectedSpellID = clickedID
        seSelectedTriggerKey = nil
        seSelectedAuraID = nil
        seSelectedAnimIdx = nil
        RefreshSpellList()
        if RefreshOrbList then RefreshOrbList() end
        if RefreshOocList then RefreshOocList() end
        if RefreshAuraList then RefreshAuraList() end
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

    -- Masquer colonnes H/C pour les sections orbs et ooc
    local hideHC = (seActiveSection ~= "spells")
    _hdrHit:SetShown(not hideHC)
    _hdrCast:SetShown(not hideHC)
    if hideHC then
      _hdrModel:ClearAllPoints()
      _hdrModel:SetPoint("LEFT", colHeaderFrame, "LEFT", 6, 0)
    else
      _hdrModel:ClearAllPoints()
      _hdrModel:SetPoint("LEFT", colHeaderFrame, "LEFT", 46, 0)
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
    elseif seActiveSection == "auras" then
      local name = GetSpellInfo3D(key)
      titleText = string.format(L["SETTINGS_COMBO_TITLE"], name or "?")
    end
    seAnimList._rightTitle:SetText(titleText)

    local combo = db[key]
    if not combo then combo = {} end

    local rowW = RIGHT_W - 18
    local yy = 0
    for idx, anim in ipairs(combo) do
      local row = BuildAnimRow(seAnimList, idx, anim, rowW, function(clickedIdx)
        seSelectedAnimIdx = clickedIdx
        RefreshAnimList()
        RefreshAnimEditor()
      end, function()
        -- Callback when trigger checkbox changed: refresh row checkboxes
        RefreshAnimList()
      end, hideHC)
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
    previewBtn._lbl:SetTextColor(unpack(Theme.accent))

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

  ---------------------------------------------------------------------------
  -- Refresh listes Orbes & OOC
  ---------------------------------------------------------------------------

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
    local buffs, debuffs = {}, {}
    if spells then
      for sid, info in pairs(spells) do
        if info.source ~= "equipment" then
          if info.source == "debuff" then
            debuffs[#debuffs + 1] = { id = sid, info = info }
          else  -- "buff", "enhancement", ou inconnu → buff joueur
            buffs[#buffs + 1] = { id = sid, info = info }
          end
        end
      end
    end
    local function sortGroup(t)
      table.sort(t, function(a, b)
        return strlower(GetSpellInfo3D(a.id) or "") < strlower(GetSpellInfo3D(b.id) or "")
      end)
    end
    sortGroup(buffs)
    sortGroup(debuffs)

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
          seSelectedAuraID = clickedID
          seSelectedSpellID = nil
          seSelectedTriggerKey = nil
          seSelectedAnimIdx = nil
          if not auraCombos[clickedID] then auraCombos[clickedID] = {} end
          RefreshSpellList()
          RefreshOrbList()
          RefreshOocList()
          RefreshAuraList()
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

    seAuraList:SetHeight(math.max(10, yy))
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

  ---------------------------------------------------------------------------
  -- Button handlers
  ---------------------------------------------------------------------------

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
      local pf = CreateFrame("Frame", "AishaddonSESpellPicker", UIParent, "BackdropTemplate")
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
      ptitle:SetTextColor(unpack(Theme.accent))
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

  -- +Anim : ouvre le Model Picker pour choisir un modèle
  animAddBtn:SetScript("OnClick", function()
    local picker = EnsureModelPicker()
    picker:Open(function(fileID, modelName)
      local db, key = GetActiveComboTable()
      if not db or not key then return end
      if not db[key] then db[key] = {} end
      local combo = db[key]
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
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
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
      previewBtn._lbl:SetTextColor(unpack(Theme.accent))
      previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
      previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
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
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
        return
      end
    else
      if SE.IsComboPreviewLooping and SE.IsComboPreviewLooping() then
        SE.StopComboPreview()
        previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
        return
      end
    end

    -- Stopper l'autre type de preview si actif
    if SE.IsPreviewLooping and SE.IsPreviewLooping() then
      SE.StopPreview()
      previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
      previewBtn._lbl:SetTextColor(unpack(Theme.accent))
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
        previewBtn._lbl:SetTextColor(unpack(Theme.accent))
        return
      end
    else
      if SE.IsPreviewLooping and SE.IsPreviewLooping() then
        SE.StopPreview()
        previewBtn._lbl:SetText(L["SETTINGS_PREVIEW_BTN"])
        previewBtn._lbl:SetTextColor(unpack(Theme.accent))
        return
      end
    end

    -- Stopper l'autre type de preview si actif
    if SE.IsComboPreviewLooping and SE.IsComboPreviewLooping() then
      SE.StopComboPreview()
      previewComboBtn._lbl:SetText(L["SETTINGS_PREVIEW_COMBO_BTN"])
      previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
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
        previewComboBtn._lbl:SetTextColor(unpack(Theme.accent))
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

  ---------------------------------------------------------------------------
  -- Initial refresh
  ---------------------------------------------------------------------------
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
  RefreshAnimList()
  RefreshAnimEditor()

  ctx:Finalize()
  return ctx.widgets
end

---------------------------------------------------------------------------
-- BUILD : Barre d'XP  (helpers 3 niveaux de profondeur)
---------------------------------------------------------------------------
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
  btn.text:SetTextColor(unpack(Theme.accent))
  btn:SetScript("OnEnter", function(self) self.text:SetTextColor(1,1,1) end)
  btn:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(Theme.accent)) end)
  return btn
end

local xpEditBtn  -- reference globale pour update du label

local function BuildXPBar(container)
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

  ctx:Finalize()
  return ctx.widgets
end

---------------------------------------------------------------------------
-- BUILD : Priority Bar
---------------------------------------------------------------------------
local SpellPickerFrame  -- singleton créé en lazy

local function BuildPriorityBar(container)
  local ctx = NewLayout(container)
  local W = CONTENT_W

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_PRIORITY_BAR"], W))

  ---------------------------------------------------------------------------
  -- Disposition (5 choix visuels, spec-specific)
  ---------------------------------------------------------------------------
  do
    local TEX_BASE = "Interface\\AddOns\\Aishaddon\\Media\\textures\\"
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
      actTx:SetTextColor(unpack(Theme.accent)); actTx:SetText(L["SETTINGS_ACTIVE_BADGE"])
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

  -- Activer
  local cbPB = ctx:Add(SW.CreateCheckbox(container, L["SETTINGS_PB_ENABLE"],
    L["SETTINGS_PB_ENABLE_TT"], W))
  BindCheckbox(cbPB, "priorityBar", "enabled")

  ctx:Spacer(4)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  MakeModeRadio(container, ctx, W, "priorityBar", {
    { "always",  L["SETTINGS_VIS_ALWAYS"],    L["SETTINGS_PB_VIS_ALWAYS_TT"] },
    { "target",  L["SETTINGS_VIS_TARGET"],    L["SETTINGS_PB_VIS_TARGET_TT"] },
    { "combat",  L["SETTINGS_VIS_COMBAT"],    L["SETTINGS_PB_VIS_COMBAT_TT"] },
  }, "combat")

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

  local slChargeOffX = SW.CreateSlider(container, L["SETTINGS_PB_CHARGE_OFFSET_X"], -20, 20, 1, _pbSL3)
  BindSlider(slChargeOffX, "priorityBar", "chargeOffsetX")
  local slChargeOffY = SW.CreateSlider(container, L["SETTINGS_PB_CHARGE_OFFSET_Y"], -20, 20, 1, _pbSL3)
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
    nil, Theme.gold, Theme.accent)
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

  ---------------------------------------------------------------------------
  -- Section editeur de slots (par spec)
  ---------------------------------------------------------------------------
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SLOT_SPELLS"], W))

  local slotBaseY = ctx.y

  -- Creation du SpellPicker en lazy (singleton global)
  if not SpellPickerFrame then
    local f = CreateFrame("Frame", "AishaddonSpellPicker", UIParent, "BackdropTemplate")
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
    title:SetTextColor(unpack(Theme.accent))
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
      hTxt:SetTextColor(unpack(Theme.accent))
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

---------------------------------------------------------------------------
-- BUILD : Top Target Bar
---------------------------------------------------------------------------
local function BuildTopTargetBar(container)
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

  local function MakeTTBXYRow(propA, propB, labelA, labelB)
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 32)
    local function MakeInput(lTxt, prop, xAnchor)
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 10)
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(lTxt)
      lbl:SetPoint("LEFT", row, "LEFT", xAnchor, 6)
      local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
      SW.StyleEditBox(eb)
      eb:SetSize(70, 20)
      eb:SetAutoFocus(false)
      eb:SetNumeric(false)
      eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
      eb:SetText(tostring(TTBGet(prop) or 0))
      local function Commit(self)
        local v = tonumber(self:GetText())
        if v then TTBSet(prop, v) end
      end
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", Commit)
    end
    MakeInput(labelA, propA, 0)
    MakeInput(labelB, propB, W / 2)
    return row
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
  ctx:Add(MakeTTBXYRow("x", "y", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_BLACK_BG"], W))
  ctx:Add(MakeTTBXYRow("bgW",  "bgH",  L["SETTINGS_WIDTH_SHORT"],    L["SETTINGS_HEIGHT_SHORT"]))
  ctx:Add(MakeTTBXYRow("bgOX", "bgOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_COLORED_BAR"], W))
  ctx:Add(MakeTTBXYRow("barW",  "barH",  L["SETTINGS_WIDTH_SHORT"],    L["SETTINGS_HEIGHT_SHORT"]))
  ctx:Add(MakeTTBXYRow("barOX", "barOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_NAME_TEXT"], W))
  local ddTTBNameFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddTTBNameFont, "topTargetBar", "nameFont")
  ctx:Add(MakeTTBXYRow("nameOX", "nameOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TTB_HP_TEXT"], W))
  local ddTTBHpFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), 220))
  BindDropdown(ddTTBHpFont, "topTargetBar", "hpFont")

  -- Ligne ancrage
  do
    local ancRow = CreateFrame("Frame", nil, container)
    ancRow:SetSize(W, 26)
    local ancLbl = ancRow:CreateFontString(nil, "OVERLAY")
    ancLbl:SetFont(ns.Media.fontGui, 10)
    ancLbl:SetTextColor(unpack(ns.Theme.textNormal))
    ancLbl:SetText(L["SETTINGS_ANCHOR_COLON"])
    ancLbl:SetPoint("LEFT", ancRow, "LEFT", 0, 0)
    local ANCS   = { "LEFT",   "CENTER", "RIGHT"  }
    local ANLBLS = { L["SETTINGS_ALIGN_LEFT"], L["SETTINGS_ANCHOR_MIDDLE"], L["SETTINGS_ALIGN_RIGHT"] }
    local ancBtns = {}
    for i, anc in ipairs(ANCS) do
      local btn = CreateFrame("Button", nil, ancRow)
      btn:SetSize(80, 20)
      btn:SetPoint("LEFT", ancRow, "LEFT", 72 + (i - 1) * 84, 0)
      local outer = btn:CreateTexture(nil, "ARTWORK")
      outer:SetSize(12, 12); outer:SetPoint("LEFT", btn, "LEFT", 0, 0)
      outer:SetColorTexture(0.15, 0.15, 0.25, 1)
      local bord = btn:CreateTexture(nil, "BORDER")
      bord:SetPoint("TOPLEFT",     outer, "TOPLEFT",     -1,  1)
      bord:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT",  1, -1)
      bord:SetColorTexture(unpack(ns.Theme.border))
      local chk = btn:CreateTexture(nil, "OVERLAY")
      chk:SetSize(6, 6); chk:SetPoint("CENTER", outer, "CENTER", 0, 0)
      chk:SetColorTexture(0.4, 0.85, 1, 1)
      local lbl = btn:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 10)
      lbl:SetPoint("LEFT", outer, "RIGHT", 4, 0)
      lbl:SetTextColor(0.85, 0.85, 0.85, 1)
      lbl:SetText(ANLBLS[i])
      btn._anchor = anc; btn._chk = chk
      chk:SetShown((TTBGet("hpAnchor") or "LEFT") == anc)
      btn:SetScript("OnClick", function()
        TTBSet("hpAnchor", anc)
        for _, b in ipairs(ancBtns) do b._chk:SetShown(b._anchor == anc) end
      end)
      btn:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1) end)
      btn:SetScript("OnLeave", function() lbl:SetTextColor(0.85, 0.85, 0.85, 1) end)
      ancBtns[i] = btn
    end
    ctx:Add(ancRow)
  end

  -- Taille (input unique)
  do
    local szRow = CreateFrame("Frame", nil, container)
    szRow:SetSize(W, 32)
    local szLbl = szRow:CreateFontString(nil, "OVERLAY")
    szLbl:SetFont(ns.Media.fontGui, 10)
    szLbl:SetTextColor(unpack(ns.Theme.textNormal))
    szLbl:SetText(L["SETTINGS_SIZE_COLON"])
    szLbl:SetPoint("LEFT", szRow, "LEFT", 0, 6)
    local szEb = CreateFrame("EditBox", nil, szRow, "InputBoxTemplate")
    SW.StyleEditBox(szEb)
    szEb:SetSize(70, 20); szEb:SetAutoFocus(false); szEb:SetNumeric(false)
    szEb:SetPoint("LEFT", szLbl, "RIGHT", 4, -1)
    szEb:SetText(tostring(TTBGet("hpFontSize") or 10))
    local function CommitSz(self)
      local v = tonumber(self:GetText()); if v then TTBSet("hpFontSize", v) end
    end
    szEb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); CommitSz(self) end)
    szEb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    szEb:SetScript("OnEditFocusLost", CommitSz)
    ctx:Add(szRow)
  end

  ctx:Add(MakeTTBXYRow("hpOX", "hpOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Spacer()
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_CONTAINER"], W))
  ctx:Add(MakeTTBXYRow("ttx", "tty", L["SETTINGS_AXIS_X"], L["SETTINGS_AXIS_Y"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_BLACK_BG"], W))
  ctx:Add(MakeTTBXYRow("ttBgW",  "ttBgH",  L["SETTINGS_WIDTH_SHORT"],    L["SETTINGS_HEIGHT_SHORT"]))
  ctx:Add(MakeTTBXYRow("ttBgOX", "ttBgOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_COLORED_BAR"], W))
  ctx:Add(MakeTTBXYRow("ttBarW",  "ttBarH",  L["SETTINGS_WIDTH_SHORT"],    L["SETTINGS_HEIGHT_SHORT"]))
  ctx:Add(MakeTTBXYRow("ttBarOX", "ttBarOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_TOT_NAME_TEXT"], W))
  ctx:Add(MakeTTBXYRow("ttNameOX", "ttNameOY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

  ctx:Finalize()
end

---------------------------------------------------------------------------
-- BUILD : Buffs / Debuffs de la cible
---------------------------------------------------------------------------
local function BuildTargetAuras(container)
  local ctx = NewLayout(container)
  local W   = CONTENT_W
  local _halfW = math.floor((W - 8) / 2)

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

  ---------------------------------------------------------------------------
  -- DB helpers : root level (enabled, offsetX, offsetY, rowSpacing)
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- DB helpers : group level (buffs / debuffs sub-tables)
  ---------------------------------------------------------------------------
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

  ---------------------------------------------------------------------------
  -- XY row helper
  ---------------------------------------------------------------------------
  local function MakeTAXYRow(getterFn, setterFn, propA, propB, labelA, labelB)
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 32)
    local function MakeInput(lTxt, prop, xAnchor)
      local lbl = row:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 10)
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(lTxt)
      lbl:SetPoint("LEFT", row, "LEFT", xAnchor, 6)
      local eb = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
      SW.StyleEditBox(eb)
      eb:SetSize(70, 20)
      eb:SetAutoFocus(false)
      eb:SetNumeric(false)
      eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
      eb:SetText(tostring(getterFn(prop) or 0))
      local function Commit(self)
        local v = tonumber(self:GetText())
        if v then setterFn(prop, v) end
      end
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", Commit)
    end
    MakeInput(labelA, propA, 0)
    MakeInput(labelB, propB, W / 2)
    return row
  end

  ---------------------------------------------------------------------------
  -- Grow direction radio helper
  ---------------------------------------------------------------------------
  local function MakeGrowRow(group)
    local ABTN_W = 90
    local row = CreateFrame("Frame", nil, container)
    row:SetSize(W, 26)
    local btns = {}
    local function Refresh(val)
      for _, b in ipairs(btns) do
        if b.key == val then
          b._lbl:SetTextColor(unpack(ns.Theme.accent))
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

  ---------------------------------------------------------------------------
  -- Builder : section complète pour un groupe (buffs ou debuffs)
  ---------------------------------------------------------------------------
  local function BuildGroupSection(group, title)
    local gGet = function(prop) return GrpGet(group, prop) end
    local gSet = function(prop, val) GrpSet(group, prop, val) end
    local gXY  = function(pA, pB, lA, lB) return MakeTAXYRow(gGet, gSet, pA, pB, lA, lB) end

    ctx:Spacer(10)
    ctx:Add(SW.CreateSectionHeader(container, title, W))

    -- Position de cette ligne d'auras
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_POSITION"], title), W))
    ctx:Add(gXY("offsetX", "offsetY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

    -- Icônes : taille, espacement, max, largeur ligne
    local slSize = SW.CreateSlider(container, L["SETTINGS_TA_ICON_SIZE"], 14, 48, 1, _halfW)
    slSize:SetValue(gGet("iconSize") or 26)
    slSize.onChanged = function(val) gSet("iconSize", val) end
    local slSpacing = SW.CreateSlider(container, L["SETTINGS_SPACING"], 0, 10, 1, _halfW)
    slSpacing:SetValue(gGet("iconSpacing") or 2)
    slSpacing.onChanged = function(val) gSet("iconSpacing", val) end
    ctx:AddRow(8, slSize, slSpacing)

    local slMax = SW.CreateSlider(container, L["SETTINGS_TA_MAX_PER_ROW"], 1, 40, 1, _halfW)
    slMax:SetValue(gGet("maxAuras") or 16)
    slMax.onChanged = function(val) gSet("maxAuras", val) end
    ctx:AddRow(8, slMax)

    local slNumRows = SW.CreateSlider(container, L["SETTINGS_TA_NUM_ROWS"], 1, 5, 1, _halfW)
    slNumRows:SetValue(gGet("numRows") or 1)
    slNumRows.onChanged = function(val) gSet("numRows", val) end
    local slRowSpacing = SW.CreateSlider(container, L["SETTINGS_TA_ROW_SPACING"], 0, 20, 1, _halfW)
    slRowSpacing:SetValue(gGet("rowSpacing") or 2)
    slRowSpacing.onChanged = function(val) gSet("rowSpacing", val) end
    ctx:AddRow(8, slNumRows, slRowSpacing)

    local cbGrowUp = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_TA_GROW_UP"],
      L["SETTINGS_TA_GROW_UP_TT"], W))
    cbGrowUp:SetChecked(gGet("growUpward") == true)
    cbGrowUp.onChanged = function(val) gSet("growUpward", val) end

    -- Option debuff joueur uniquement
    if group == "debuffs" then
      local cbOnlyPlayer = ctx:Add(SW.CreateCheckbox(container,
        L["SETTINGS_TA_ONLY_PLAYER_DEBUFFS"],
        L["SETTINGS_TA_ONLY_PLAYER_DEBUFFS_TT"], W))
      cbOnlyPlayer:SetChecked(gGet("onlyPlayer") == true)
      cbOnlyPlayer.onChanged = function(val) gSet("onlyPlayer", val) end
    end

    -- Ordre de tri
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_SORT"], title), W))
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
    local ddSort = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_SORT"], sortOpts, W))
    do
      local cur = gGet("sortMode") or "playerFirst"
      ddSort:SetValue(cur)
    end
    ddSort.onChanged = function(val)
      gSet("sortMode", val)
    end

    local cbReverse = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_TA_REVERSE_SORT"], L["SETTINGS_TA_REVERSE_SORT_TT"], W))
    cbReverse:SetChecked(gGet("reverseSort") == true)
    cbReverse.onChanged = function(val) gSet("reverseSort", val) end

    -- Direction croissance
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_DIRECTION"], title), W))
    ctx:Add(MakeGrowRow(group))

    -- Bordure
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_BORDER"], title), W))

    local cbBorder = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_SHOW_BORDER"], L["SETTINGS_TA_SHOW_BORDER_TT"], W))
    cbBorder:SetChecked(gGet("showBorder") ~= false)
    cbBorder.onChanged = function(val) gSet("showBorder", val) end

    local slBorderSize = SW.CreateSlider(container, L["SETTINGS_TA_BORDER_THICKNESS"], 0, 4, 1, _halfW)
    slBorderSize:SetValue(gGet("borderSize") or 1)
    slBorderSize.onChanged = function(val) gSet("borderSize", val) end
    ctx:Add(slBorderSize)

    local colBorder = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_BORDER_COLOR"], W))
    do
      local c = gGet("borderColor") or { 1, 1, 1, 0.15 }
      colBorder:SetColor(c[1], c[2], c[3], c[4])
    end
    colBorder.onChanged = function(val) gSet("borderColor", val) end

    -- Cooldown swipe
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_COOLDOWN_SWIPE"], title), W))

    local cbSwipe = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_TA_SHOW_SWIPE"], L["SETTINGS_TA_SHOW_SWIPE_TT"], W))
    cbSwipe:SetChecked(gGet("showSwipe") ~= false)
    cbSwipe.onChanged = function(val) gSet("showSwipe", val) end

    local cbRevSwipe = ctx:Add(SW.CreateCheckbox(container,
      L["SETTINGS_TA_REVERSE_SWIPE"], L["SETTINGS_TA_REVERSE_SWIPE_TT"], W))
    cbRevSwipe:SetChecked(gGet("reverseSwipe") == true)
    cbRevSwipe.onChanged = function(val) gSet("reverseSwipe", val) end

    -- Police & couleur durée
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_DURATION_TEXT"], title), W))

    local ddDurFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_TA_DURATION_FONT"], ns.GetFontList(), 220))
    do
      local v = gGet("durationFont")
      if v then ddDurFont:SetValue(v) end
    end
    ddDurFont.onChanged = function(val) gSet("durationFont", val) end

    local slDurSize = SW.CreateSlider(container, L["SETTINGS_TA_DURATION_SIZE"], 6, 18, 1, _halfW)
    slDurSize:SetValue(gGet("durationFontSize") or 9)
    slDurSize.onChanged = function(val) gSet("durationFontSize", val) end
    ctx:Add(slDurSize)

    local colDur = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TA_DURATION_COLOR"], W))
    do
      local c = gGet("durationColor") or { 1, 1, 1, 1 }
      colDur:SetColor(c[1], c[2], c[3], c[4])
    end
    colDur.onChanged = function(val) gSet("durationColor", val) end

    -- Positionnement durée
    ctx:Spacer(2)
    local ddDurAnc = SW.CreateDropdown(container, L["SETTINGS_TA_DURATION_ANCHOR"], ANCHOR_LIST, _halfW)
    do local v = gGet("durationAnchor"); if v then ddDurAnc:SetValue(v) end end
    ddDurAnc.onChanged = function(val) gSet("durationAnchor", val) end
    ctx:Add(ddDurAnc)

    ctx:Add(gXY("durationOffX", "durationOffY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))

    -- Police & couleur stacks
    ctx:Spacer(4)
    ctx:Add(SW.CreateSectionHeader(container, string.format(L["SETTINGS_TA_SEC_STACKS_TEXT"], title), W))

    local ddCntFont = ctx:Add(SW.CreateDropdown(container, L["SETTINGS_TA_STACKS_FONT"], ns.GetFontList(), 220))
    do
      local v = gGet("countFont")
      if v then ddCntFont:SetValue(v) end
    end
    ddCntFont.onChanged = function(val) gSet("countFont", val) end

    local slCntSize = SW.CreateSlider(container, L["SETTINGS_TA_STACKS_SIZE"], 6, 18, 1, _halfW)
    slCntSize:SetValue(gGet("countFontSize") or 10)
    slCntSize.onChanged = function(val) gSet("countFontSize", val) end
    ctx:Add(slCntSize)

    local colCnt = ctx:Add(SW.CreateColorButton(container, L["SETTINGS_TA_STACKS_COLOR"], W))
    do
      local c = gGet("countColor") or { 1, 1, 1, 1 }
      colCnt:SetColor(c[1], c[2], c[3], c[4])
    end
    colCnt.onChanged = function(val) gSet("countColor", val) end

    -- Positionnement stacks
    ctx:Spacer(2)
    local ddCntAnc = SW.CreateDropdown(container, L["SETTINGS_TA_TEXT_ANCHOR"], ANCHOR_LIST, _halfW)
    do local v = gGet("countAnchor"); if v then ddCntAnc:SetValue(v) end end
    ddCntAnc.onChanged = function(val) gSet("countAnchor", val) end
    local ddCntRel = SW.CreateDropdown(container, L["SETTINGS_TA_RELATIVE_POINT"], ANCHOR_LIST, _halfW)
    do local v = gGet("countRelPoint"); if v then ddCntRel:SetValue(v) end end
    ddCntRel.onChanged = function(val) gSet("countRelPoint", val) end
    ctx:AddRow(8, ddCntAnc, ddCntRel)

    ctx:Add(gXY("countOffX", "countOffY", L["SETTINGS_OFFSET_X_COLON"], L["SETTINGS_OFFSET_Y_COLON"]))
  end
  -- /BuildGroupSection

  ---------------------------------------------------------------------------
  -- Section globale (enabled, offset, row spacing)
  ---------------------------------------------------------------------------
  local cbEn = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_TA_ENABLE"],
    L["SETTINGS_TA_ENABLE_TT"], W))
  cbEn:SetChecked(TAGet("enabled") ~= false)
  cbEn.onChanged = function(val) TASet("enabled", val) end

  ---------------------------------------------------------------------------
  -- Sections par groupe
  ---------------------------------------------------------------------------
  BuildGroupSection("buffs",   L["SETTINGS_BUFFS"])
  BuildGroupSection("debuffs", L["SETTINGS_DEBUFFS"])

  ctx:Finalize()
end

---------------------------------------------------------------------------
-- BUILD : Couleurs par spécialisation
---------------------------------------------------------------------------
local function BuildColors(container)
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
  local COLS        = 4
  local CELL_W      = math.floor(CONTENT_W / COLS)
  local CELL_H      = 28
  local SPEC_HDR_H  = 22
  local CLS_HDR_H   = 30
  local SPEC_GAP    = 8
  local SECTION_PAD = 6

  local _, playerClassFile = UnitClass("player")
  local playerClassKey = playerClassFile and playerClassFile:lower()

  local expanded     = {}
  local classSections = {}

  -- -- Mode des couleurs (radios en haut du panneau) ------------------
  local HEADER_H  = 70
  local modeFrame = CreateFrame("Frame", nil, container)
  modeFrame:SetSize(CONTENT_W, HEADER_H)
  modeFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  local mBg = modeFrame:CreateTexture(nil, "BACKGROUND")
  mBg:SetAllPoints(); mBg:SetColorTexture(0.08, 0.08, 0.14, 0.92)
  local mTitle = modeFrame:CreateFontString(nil, "OVERLAY")
  mTitle:SetFont(ns.Media.fontGui, 10, "")
  mTitle:SetPoint("TOPLEFT", modeFrame, "TOPLEFT", 10, -8)
  mTitle:SetTextColor(0.8, 0.8, 0.9, 1)
  mTitle:SetText(L["SETTINGS_COLOR_MODE_HEADER"])
  local mSep = modeFrame:CreateTexture(nil, "BORDER")
  mSep:SetSize(CONTENT_W, 1)
  mSep:SetPoint("BOTTOMLEFT", modeFrame, "BOTTOMLEFT", 0, 0)
  mSep:SetColorTexture(0.3, 0.3, 0.5, 0.6)

  local rbClassDef, rbCustom
  local function GetUseClassDefaults()
    return ns.DB and ns.DB.colors and ns.DB.colors.useClassDefaults
  end

  local function MakeRadio(parent, text, offsetY)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CONTENT_W - 20, 22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, offsetY)
    local outer = btn:CreateTexture(nil, "ARTWORK")
    outer:SetSize(13, 13); outer:SetPoint("LEFT", btn, "LEFT", 0, 0)
    outer:SetColorTexture(0.15, 0.15, 0.25, 1)
    local bord = btn:CreateTexture(nil, "BORDER")
    bord:SetPoint("TOPLEFT",     outer, "TOPLEFT",     -1,  1)
    bord:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT",  1, -1)
    bord:SetColorTexture(unpack(ns.Theme.border))
    local chk = btn:CreateTexture(nil, "OVERLAY")
    chk:SetSize(7, 7); chk:SetPoint("CENTER", outer, "CENTER", 0, 0)
    chk:SetColorTexture(0.4, 0.85, 1, 1); chk:Hide()
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10)
    lbl:SetPoint("LEFT", outer, "RIGHT", 6, 0)
    lbl:SetTextColor(0.85, 0.85, 0.85, 1)
    lbl:SetText(text)
    btn.check = chk; btn.lbl = lbl
    btn:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function() lbl:SetTextColor(0.85, 0.85, 0.85, 1) end)
    return btn
  end
  rbClassDef = MakeRadio(modeFrame, L["SETTINGS_COLOR_MODE_CLASS_DEFAULTS"], -26)
  rbCustom   = MakeRadio(modeFrame, L["SETTINGS_COLOR_MODE_CUSTOM"],       -48)

  local function ApplyClassMode(useClassDef)
    if not ns.DB then ns.DB = {} end
    if not ns.DB.colors then ns.DB.colors = {} end
    ns.DB.colors.useClassDefaults = useClassDef
    rbClassDef.check:SetShown(useClassDef == true)
    rbCustom.check:SetShown(useClassDef ~= true)
    for _, sec in ipairs(classSections) do
      if useClassDef then
        -- Fermer toutes les sections déployées
        if expanded[sec.cd.key] then
          expanded[sec.cd.key] = false
          sec.arrow:SetText("\226\150\182")  -- ?
          sec.contentFrame:Hide()
        end
        sec.headerBtn:SetMouseClickEnabled(false)
        sec.headerBtn:SetAlpha(0.3)
      else
        sec.headerBtn:SetMouseClickEnabled(true)
        sec.headerBtn:SetAlpha(1)
      end
    end
    -- Broadcast immédiat : useClassDefaults est déjà écrit, les modules liront la bonne valeur
    Colors.Broadcast()
    -- RebuildLayout différé : WoW doit d'abord traiter les Hide() avant de recalculer les positions
    C_Timer.After(0, RebuildLayout)
  end
  rbClassDef:SetScript("OnClick", function() ApplyClassMode(true)  end)
  rbCustom:SetScript("OnClick",   function() ApplyClassMode(false) end)

  -- État initial des radios (sections pas encore construites)
  rbClassDef.check:SetShown(GetUseClassDefaults() == true)
  rbCustom.check:SetShown(GetUseClassDefaults() ~= true)

  -- Redispose toutes les sections selon l'état expanded
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

  for _, cd in ipairs(Colors.CLASSES) do
    -- -- En-tête de classe ----------------------------------------------
    local hBtn = CreateFrame("Button", nil, container)
    hBtn:SetSize(CONTENT_W, CLS_HDR_H)

    local hBg = hBtn:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetColorTexture(0.10, 0.10, 0.16, 0.92)

    local hLine = hBtn:CreateTexture(nil, "BORDER")
    hLine:SetSize(CONTENT_W, 1)
    hLine:SetPoint("BOTTOMLEFT", hBtn, "BOTTOMLEFT", 0, 0)
    local fc = Colors.CLASS_FALLBACK[cd.file] or {1,1,1,1}
    hLine:SetColorTexture(fc[1]*0.6, fc[2]*0.6, fc[3]*0.6, 0.8)

    local hLabel = hBtn:CreateFontString(nil, "OVERLAY")
    hLabel:SetFont(ns.Media.fontGui, 11, "")
    hLabel:SetPoint("LEFT", hBtn, "LEFT", 10, 0)
    hLabel:SetTextColor(fc[1], fc[2], fc[3], 1)
    hLabel:SetText(cd.name)

    local hArrow = hBtn:CreateFontString(nil, "OVERLAY")
    hArrow:SetFont(ns.Media.fontGui, 11)
    hArrow:SetPoint("RIGHT", hBtn, "RIGHT", -8, 0)
    hArrow:SetTextColor(0.7, 0.7, 0.7, 1)

    -- -- Contenu (grid de spés) -----------------------------------------
    local cFrame = CreateFrame("Frame", nil, container)
    cFrame:SetWidth(CONTENT_W)
    cFrame:SetHeight(1)
    cFrame:Hide()

    local sec = {
      headerBtn    = hBtn,
      contentFrame = cFrame,
      arrow        = hArrow,
      cd           = cd,
      built        = false,
    }

    -- Construction lazy du contenu de la classe
    sec.BuildContent = function()
      if sec.built then return end
      local fy = 0

      for _, spec in ipairs(cd.specs) do
        -- En-tête de spE
        local shFrame = CreateFrame("Frame", nil, cFrame)
        shFrame:SetSize(CONTENT_W, SPEC_HDR_H)
        shFrame:SetPoint("TOPLEFT", cFrame, "TOPLEFT", 0, -fy)

        local shBg = shFrame:CreateTexture(nil, "BACKGROUND")
        shBg:SetAllPoints()
        shBg:SetColorTexture(fc[1]*0.08, fc[2]*0.08, fc[3]*0.08, 0.85)

        local shLabel = shFrame:CreateFontString(nil, "OVERLAY")
        shLabel:SetFont(ns.Media.fontGui, 10, "")
        shLabel:SetPoint("LEFT", shFrame, "LEFT", 6, 0)
        shLabel:SetTextColor(fc[1], fc[2], fc[3], 0.9)
        shLabel:SetText(spec.name)
        fy = fy + SPEC_HDR_H + 2

        -- Grille de couleurs : 4 colonnes à N lignes
        local col = 0
        for _, ek in ipairs(ELEM_KEYS) do
          local cx = col * CELL_W

          local cell = CreateFrame("Frame", nil, cFrame)
          cell:SetSize(CELL_W, CELL_H)
          cell:SetPoint("TOPLEFT", cFrame, "TOPLEFT", cx, -fy)

          -- Swatch
          local sw = CreateFrame("Button", nil, cell)
          sw:SetSize(18, 18)
          sw:SetPoint("LEFT", cell, "LEFT", 3, 0)
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

          -- Label élément
          local cellLbl = cell:CreateFontString(nil, "OVERLAY")
          cellLbl:SetFont(ns.Media.fontGui, 9)
          cellLbl:SetPoint("LEFT",  sw,   "RIGHT", 3,  0)
          cellLbl:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
          cellLbl:SetTextColor(0.75, 0.75, 0.75, 1)
          cellLbl:SetText(ELEM_LABELS[ek] or ek)
          cellLbl:SetJustifyH("LEFT")

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
          if col >= COLS then
            col = 0
            fy  = fy + CELL_H
          end
        end
        -- Fin de la dernière ligne (incomplète)
        if col > 0 then
          fy = fy + CELL_H
        end
        fy = fy + SPEC_GAP
      end

      cFrame:SetHeight(fy)
      sec.built = true
    end

    -- Toggle expand / collapse
    hBtn:SetScript("OnClick", function()
      expanded[cd.key] = not expanded[cd.key]
      hArrow:SetText(expanded[cd.key] and "\226\150\188" or "\226\150\182")
      if expanded[cd.key] then
        sec.BuildContent()
      end
      RebuildLayout()
    end)
    hBtn:SetScript("OnEnter", function() hBg:SetColorTexture(0.16, 0.16, 0.24, 0.95) end)
    hBtn:SetScript("OnLeave", function() hBg:SetColorTexture(0.10, 0.10, 0.16, 0.92) end)

    table.insert(classSections, sec)
  end

  -- Expansion par défaut : classe du joueur (seulement en mode personnalisé)
  if playerClassKey and not GetUseClassDefaults() then
    expanded[playerClassKey] = true
    for _, sec in ipairs(classSections) do
      if sec.cd.key == playerClassKey then
        sec.arrow:SetText("\226\150\188")  -- ?
        sec.BuildContent()
        break
      end
    end
  end
  -- Flèche ? pour classes fermées
  for _, sec in ipairs(classSections) do
    if not expanded[sec.cd.key] then
      sec.arrow:SetText("\226\150\182")  -- ?
    end
  end

  -- Appliquer l'état initial du mode (dim si "couleurs de classe par défaut")
  if GetUseClassDefaults() then
    for _, sec in ipairs(classSections) do
      sec.headerBtn:SetMouseClickEnabled(false)
      sec.headerBtn:SetAlpha(0.3)
    end
  end

  RebuildLayout()
end

---------------------------------------------------------------------------
-- BuildSkyriding : port du WeakAura [SKYRIDING] - FIXE
---------------------------------------------------------------------------
local function BuildSkyriding(container)
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
  cbEnable.onChanged = function(val) SRSet("enabled", val) end
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
  -- local RH2   = ns.Modules and ns.Modules.RotationHelper

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

--[[ -- Aide à la rotation (désactivé)
  MakeHideToggle(
    "Aide à la rotation",
    "Masque les icônes de suggestion de sort\npendant le Skyriding.",
    "hideRotationHelper",
    function(val)
      if val and RH2 then RH2.SetSkyridingActive(true) end
      -- Désactivation : les icônes réapparaissent au prochain tick de polling
    end)
--]]

  -- -- Position X/Y --------------------------------------------------------
  ctx:Spacer(8)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_POSITION_SCALE"], W))

  local posRow = CreateFrame("Frame", nil, container)
  posRow:SetSize(W, 32)
  do
    local function MakePosInput(lTxt, prop, globalName, xAnchor)
      local lbl = posRow:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 10)
      lbl:SetTextColor(unpack(ns.Theme.textNormal))
      lbl:SetText(lTxt)
      lbl:SetPoint("LEFT", posRow, "LEFT", xAnchor, 6)
      local eb = CreateFrame("EditBox", globalName, posRow, "InputBoxTemplate")
      SW.StyleEditBox(eb)
      eb:SetSize(70, 20)
      eb:SetAutoFocus(false)
      eb:SetNumeric(false)
      eb:SetPoint("LEFT", lbl, "RIGHT", 4, -1)
      eb:SetText(tostring(SRGet(prop) or 0))
      local function Commit(self)
        local v = tonumber(self:GetText())
        if v then SRSet(prop, v) end
      end
      eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Commit(self) end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", Commit)
    end
    MakePosInput(L["SETTINGS_AXIS_X"], "x", "AishaddonSRXEditBox", 0)
    MakePosInput(L["SETTINGS_AXIS_Y"], "y", "AishaddonSRYEditBox", W / 2)
  end
  ctx:Add(posRow)

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
  local slDotX = SW.CreateSlider(container, L["SETTINGS_SR_DOT_POS_X"], -80, 80, 1, _srSL3)
  slDotX.onChanged = function(val) SRSet("dotOffsetX", val) end
  slDotX:SetValue(SRGet("dotOffsetX") or 0)
  local slDotY = SW.CreateSlider(container, L["SETTINGS_SR_DOT_POS_Y"], -80, 80, 1, _srSL3)
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

  -- Trois boutons exclusifs : Spé / Monture / Custom
  local cbCustom, cbSpec, cbMount
  local function SetColorMode(mode)
    SRSet("colorMode", mode)
    cbCustom:SetChecked(mode == "custom")
    cbSpec:SetChecked(mode == "spec")
    cbMount:SetChecked(mode == "mount")
  end

  cbSpec = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SR_COLOR_SPEC"],
    L["SETTINGS_SR_COLOR_SPEC_TT"], W))
  cbSpec.onChanged = function(val) if val then SetColorMode("spec") end end
  cbSpec:SetChecked((SRGet("colorMode") or "custom") == "spec")

  cbMount = ctx:Add(SW.CreateCheckbox(container,
    L["SETTINGS_SR_COLOR_MOUNT"],
    L["SETTINGS_SR_COLOR_MOUNT_TT"], W))
  cbMount.onChanged = function(val) if val then SetColorMode("mount") end end
  cbMount:SetChecked((SRGet("colorMode") or "custom") == "mount")

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

---------------------------------------------------------------------------
-- BUILD : Profils  –  helpers popup
---------------------------------------------------------------------------

-- Popup export : grand bloc de texte scrollable
local _exportPopup
local function ShowExportPopup(text)
  if not _exportPopup then
    local f = CreateFrame("Frame", "AishaddonExportPopup", UIParent, "BackdropTemplate")
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
    local f = CreateFrame("Frame", "AishaddonNamePopup", UIParent, "BackdropTemplate")
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
    local f = CreateFrame("Frame", "AishaddonImportPopup", UIParent, "BackdropTemplate")
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
      print("|cff00b0ff[Aishaddon Import DBG]|r nom='" .. name .. "' strLen=" .. #str)
      if not f._onConfirm then
        print("|cffff4444[Aishaddon Import DBG] _onConfirm est nil !|r")
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

---------------------------------------------------------------------------
-- Forward-déclarations : doivent être visibles par BuildProfiles ET par les
-- SetScripts définis plus bas (SelectCategory, OnSizeChanged, etc.).
local categoryContainers = {}
local activeCategory     = nil
-- Définition de _invalidateCategory (forward-déclarée plus haut pour BuildResourceCircle etc.)
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
---------------------------------------------------------------------------
local function BuildProfiles(container)
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
    local DD_W    = 100
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

---------------------------------------------------------------------------
-- Wrappers vers les menus Auras & Procs (ns.Auras, anciennement AishUIAura)
---------------------------------------------------------------------------
local function BuildAurasRender(container, renderKey)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildRenderMenu then
    ns.Auras.SettingsPanel.BuildRenderMenu(container, CONTENT_W, renderKey)
  end
end
local function BuildAurasTactics(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildTacticsMenu then
    ns.Auras.SettingsPanel.BuildTacticsMenu(container, CONTENT_W)
  end
end
local function BuildAurasEquipment(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildEquipmentMenu then
    ns.Auras.SettingsPanel.BuildEquipmentMenu(container, CONTENT_W)
  end
end
local function BuildAurasEffects(container)
  if ns.Auras and ns.Auras.SettingsPanel and ns.Auras.SettingsPanel.BuildEffectsMenu then
    ns.Auras.SettingsPanel.BuildEffectsMenu(container, CONTENT_W)
  end
end

---------------------------------------------------------------------------
-- Definition des categories
---------------------------------------------------------------------------
local CATEGORIES = {
  {
    id    = "profiles",
    label = L["SETTINGS_SEC_PROFILES"],
    icon  = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    build = BuildProfiles,
  },
  {
    id    = "castBar",
    label = L["SETTINGS_SEC_CAST_BAR"],
    icon  = "Interface\\Icons\\spell_holy_borrowedtime",
    build = BuildCastBar,
  },
  {
    id    = "targetCastBar",
    label = L["SETTINGS_CAT_TARGET_CAST"],
    icon  = "Interface\\Icons\\ability_warrior_charge",
    build = BuildTargetCastBar,
  },
  {
    id    = "skyriding",
    label = L["SETTINGS_CAT_SKYRIDING"],
    icon  = "Interface\\Icons\\ability_mount_drake_twilight",
    build = BuildSkyriding,
  },
  {
    id    = "topTargetBar",
    label = L["SETTINGS_CAT_TOP_TARGET"],
    icon  = "Interface\\Icons\\ability_hunter_snipershot",
    build = BuildTopTargetBar,
  },
  {
    id    = "targetAuras",
    label = L["SETTINGS_CAT_TARGET_AURAS"],
    icon  = "Interface\\Icons\\spell_holy_divinespirit",
    build = BuildTargetAuras,
  },
  {
    id    = "unitBars",
    label = L["SETTINGS_CAT_HEALTH_BARS"],
    icon  = "Interface\\Icons\\ability_warrior_defensivestance",
    build = BuildUnitBars,
  },
  {
    id    = "resourceCircle",
    label = L["SETTINGS_CAT_CENTRAL_CIRCLE"],
    icon  = "Interface\\Icons\\ability_mage_incantersabsorbtion",
    build = BuildResourceCircle,
  },
  {
    id    = "outOfCombat",
    label = L["SETTINGS_CAT_OOC_CIRCLES"],
    icon  = "Interface\\Icons\\spell_holy_sealofsacrifice",
    build = BuildOutOfCombat,
  },
  {
    id    = "priorityBar",
    label = L["SETTINGS_SEC_PRIORITY_BAR"],
    icon  = "Interface\\Icons\\ability_warrior_savageblow",
    build = BuildPriorityBar,
  },
--[[ -- Rotation Helper (désactivé)
  {
    id    = "rotationHelper",
    label = "Rotation Helper",
    icon  = "Interface\\Icons\\ability_hunter_mastermarksman",
    build = BuildRotationHelper,
  },
--]]
  {
    id    = "spellEffects",
    label = L["SETTINGS_SEC_3D_ANIMATIONS"],
    icon  = "Interface\\Icons\\spell_arcane_arcane01",
    build = BuildSpellEffects,
  },
  {
    id    = "xpBar",
    label = L["SETTINGS_CAT_XP_BAR"],
    icon  = "Interface\\Icons\\inv_misc_note_01",
    build = BuildXPBar,
  },
  {
    id    = "colors",
    label = L["SETTINGS_CAT_COLORS"],
    icon  = "Interface\\Icons\\inv_misc_gem_variety_02",
    build = BuildColors,
  },
  -- Auras & Procs (fusionné depuis AishUIAura)
  {
    id    = "aurasTracked",
    label = L["SETTINGS_CAT_AURAS_TRACKED"],
    icon  = "Interface\\Icons\\inv_misc_note_06",
    build = BuildAurasTactics,
  },
  {
    id    = "aurasIconlist",
    label = L["SETTINGS_CAT_ICON_LIST"],
    icon  = "Interface\\Icons\\spell_shadow_curseofmannoroth",
    build = function(c) BuildAurasRender(c, "iconlist") end,
  },
  {
    id    = "aurasFreebars",
    label = L["SETTINGS_CAT_CIRCLE_BARS"],
    icon  = "Interface\\Icons\\spell_holy_divineprotection",
    build = function(c) BuildAurasRender(c, "freebars") end,
  },
  {
    id    = "aurasIcons",
    label = L["SETTINGS_CAT_ICONS"],
    icon  = "Interface\\Icons\\spell_arcane_prismaticcloak",
    build = function(c) BuildAurasRender(c, "icons") end,
  },
  {
    id    = "aurasCirclebars",
    label = L["SETTINGS_CAT_FREE_BARS"],
    icon  = "Interface\\Icons\\spell_nature_timestop",
    build = function(c) BuildAurasRender(c, "circlebars") end,
  },
  {
    id    = "aurasTrinkets",
    label = L["SETTINGS_CAT_TRINKETS"],
    icon  = "Interface\\Icons\\inv_jewelry_trinketpvp_01",
    build = BuildAurasEquipment,
  },
  --[[ -- Effets 3D Auras (désactivé)
  {
    id    = "aurasEffects",
    label = "Effets 3D Auras",
    icon  = "Interface\\Icons\\spell_arcane_arcane04",
    build = BuildAurasEffects,
  },
  --]]
}

---------------------------------------------------------------------------
-- Groupes de la sidebar (style AishUI : headers parchemin + sections cliquables)
---------------------------------------------------------------------------
local SIDEBAR_GROUPS = {
  { label = L["SETTINGS_GROUP_UNIT_FRAMES"], ids = { "unitBars", "targetCastBar", "topTargetBar", "targetAuras" } },
  { label = L["SETTINGS_GROUP_COMBAT"],      ids = { "resourceCircle", "priorityBar", "castBar", "targetCastBar" } },
  { label = L["SETTINGS_GROUP_WORLD"],       ids = { "outOfCombat", "xpBar", "skyriding" } },
  { label = L["SETTINGS_GROUP_AURAS_PROCS"], ids = { "aurasTracked", "aurasIconlist", "aurasFreebars", "aurasIcons", "aurasCirclebars", "aurasTrinkets", "spellEffects" } },
  { label = L["SETTINGS_GROUP_GLOBAL"],      ids = { "colors", "profiles" } },
}

-- Table catId → bouton (remplace l'ancien tableau indexé)
local categoryButtons = {}
local _sbSearchFilter = ""

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
  local CAT_HEADER_GAP = 14
  local SECTION_H      = 24
  local CAT_TO_SECT    = 4
  local ac = sidebar._accContainer
  local y  = 0

  for _, grp in ipairs(SIDEBAR_GROUPS) do
    local entry = sidebar._groupEntries[grp.label]
    if entry then
      -- Sections matchantes (filtre de recherche)
      local grpLower = grp.label:lower()
      local matchingSections = {}
      for _, cid in ipairs(grp.ids) do
        local lbl = (catLabels[cid] or cid):lower()
        if (not hasFilter)
            or lbl:find(filter, 1, true)
            or grpLower:find(filter, 1, true) then
          matchingSections[#matchingSections + 1] = cid
        end
      end

      if #matchingSections > 0 then
        -- Header groupe
        if y > 0 then y = y + CAT_HEADER_GAP end
        entry.headerBtn:ClearAllPoints()
        entry.headerBtn:SetPoint("TOPLEFT",  ac, "TOPLEFT",  0, -y)
        entry.headerBtn:SetPoint("TOPRIGHT", ac, "TOPRIGHT", 0, -y)
        entry.headerBtn:Show()
        y = y + CAT_HEADER_H + CAT_TO_SECT

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

  ac:SetHeight(math.max(50, y))
end

local function BuildSidebar()
  local _gold = Theme.gold or Theme.accent

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

    -- Header groupe : cartouche parchemin AishParchemin.tga (non cliquable)
    local h = CreateFrame("Frame", nil, accContainer)
    h:SetHeight(26)
    local htxt = h:CreateFontString(nil, "OVERLAY")
    htxt:SetFont(ns.Media.fontTitle, 9)
    htxt:SetPoint("LEFT", 14, 0)
    htxt:SetText(grp.label)
    htxt:SetTextColor(0.62, 0.62, 0.62, 1)
    local hBg = h:CreateTexture(nil, "BACKGROUND")
    hBg:SetPoint("TOPLEFT",     htxt, "TOPLEFT",     -10,  5)
    hBg:SetPoint("BOTTOMRIGHT", htxt, "BOTTOMRIGHT",  10, -5)
    hBg:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\UI\\AishParchemin")
    pcall(function()
      if hBg.SetTextureSliceMode   then hBg:SetTextureSliceMode(0) end
      if hBg.SetTextureSliceMargins then hBg:SetTextureSliceMargins(16, 16, 16, 16) end
    end)
    h:EnableMouse(false)
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
        sbg:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\UI\\TabActiveBackground")
        pcall(function()
          if sbg.SetTextureSliceMargins then sbg:SetTextureSliceMargins(12, 12, 12, 12) end
          if sbg.SetTextureSliceMode    then sbg:SetTextureSliceMode(1) end
        end)
        sbg:SetAlpha(0)

        s._txt = stxt; s._hl = shl; s._bg = sbg

        -- Hover
        s:SetScript("OnEnter", function(btn)
          if activeCategory ~= btn.catId then
            sbg:SetAlpha(0.15)
            stxt:SetTextColor(Theme.textHighlight[1], Theme.textHighlight[2], Theme.textHighlight[3], 1)
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

---------------------------------------------------------------------------
-- Containers de categorie (build a la demande)
---------------------------------------------------------------------------
local function GetOrBuildContainer(catId)
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

function MainFrame:SelectCategory(catId)
  local prevCat = activeCategory
  if prevCat == catId then return end
  activeCategory = catId

  -- Quitter la section Animations 3D ? relancer les décos réelles + previews modules
  if prevCat == "spellEffects" and catId ~= "spellEffects" then
    local SE = ns.Modules.SpellEffects
    if SE then
      if SE.StopDecoPreview then SE.StopDecoPreview() end
      if SE.StopPreview then SE.StopPreview() end
      if SE.StopComboPreview then SE.StopComboPreview() end
      if SE.SetGuiMode then SE.SetGuiMode(false) end
    end
    -- Réactiver les previews des autres modules
    local RC   = ns.Modules.ResourceCircle
    local HC   = ns.Modules.HealthCircle
    local OCRC = ns.Modules.OutOfCombatResourceCircle
    local PB   = ns.Modules.PriorityBar
    local CB   = ns.Modules.CastBar
    local SR   = ns.Modules.Skyriding
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
    local UB   = ns.Modules.UnitBars
    local TTB  = ns.Modules.TopTargetBar
    if PB   and PB.SetPreview    then PB.SetPreview(false)    end
    if CB   and CB.SetPreview    then CB.SetPreview(false)    end
    if SR   and SR.SetPreview    then SR.SetPreview(false)    end
    if UB   and UB.SetGuiHidden  then UB.SetGuiHidden(true)   end
    if TTB  and TTB.SetGuiHidden then TTB.SetGuiHidden(true)  end
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

---------------------------------------------------------------------------
-- Refresh : recharger les valeurs depuis la DB
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- ShowUI / Toggle
---------------------------------------------------------------------------
function MainFrame:ShowUI()
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

---------------------------------------------------------------------------
-- Initialisation au premier affichage
---------------------------------------------------------------------------
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
    if PB   and PB.SetGuiHidden  then PB.SetGuiHidden(true)   end
    if UB   and UB.SetGuiHidden  then UB.SetGuiHidden(true)   end
    if TTB  and TTB.SetGuiHidden then TTB.SetGuiHidden(true)  end
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
  if RC   and RC.SetDraggable    then RC.SetDraggable(false)    end
  if HC   and HC.SetDraggable    then HC.SetDraggable(false)    end
  if OCRC and OCRC.SetDraggable  then OCRC.SetDraggable(false)  end
  if RC   and RC.SetPreview      then RC.SetPreview(false)      end
  if HC   and HC.SetPreview      then HC.SetPreview(false)      end
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
  if UB   and UB.SetGuiHidden    then UB.SetGuiHidden(false)    end
  if TTB  and TTB.SetGuiHidden   then TTB.SetGuiHidden(false)   end
  local TA  = ns.Modules.TargetAuras
  if TA   and TA.SetPreview      then TA.SetPreview(false)      end
end)

---------------------------------------------------------------------------
-- Export de données (keywords + tags manuels) ? popup copiable
---------------------------------------------------------------------------
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
  lines[#lines + 1] = "-- AISHADDON EXPORT"
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

  local f = CreateFrame("Frame", "AishaddonExportFrame", UIParent, "BackdropTemplate")
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
  title:SetTextColor(unpack(Theme.accent))
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

-- Commande slash : /aishaddon export
SLASH_AISHADDONEXPORT1 = "/aishexport"
SlashCmdList["AISHADDONEXPORT"] = function()
  OpenExportFrame()
end

-- Également accessible via /aishaddon export  (si une commande principale existe déjà)
local _origAish = SlashCmdList["AISHADDON"]
SLASH_AISHADDON1 = "/aishaddon"
SlashCmdList["AISHADDON"] = function(msg)
  local cmd = msg and msg:lower():match("^(%S+)")
  if cmd == "export" then
    OpenExportFrame()
  elseif _origAish then
    _origAish(msg)
  else
    print(L["SETTINGS_SLASH_COMMANDS_HINT"])
  end
end

---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Intégration Options > Add-ons (WoW Settings API, retail 10.x+)
-- Apparaît dans la liste Options > Add-ons ; un bouton ouvre le panneau custom.
---------------------------------------------------------------------------
local function RegisterWoWSettings()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

  local canvas = CreateFrame("Frame")
  canvas:SetSize(820, 567)

  -- Logo
  local logoTex = canvas:CreateTexture(nil, "ARTWORK")
  logoTex:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\logo_icon.tga")
  logoTex:SetSize(64, 64)
  logoTex:SetPoint("TOPLEFT", canvas, "TOPLEFT", 24, -24)

  -- Titre
  local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetText("Aishaddon")
  title:SetPoint("BOTTOMLEFT", logoTex, "BOTTOMRIGHT", 12, 4)

  -- Version
  local ver = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  ver:SetText("v" .. (ns.addonVersion or "?"))
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
  openBtn:SetText(L["SETTINGS_OPEN_AISHADDON_SETTINGS"])
  openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
  openBtn:SetScript("OnClick", function()
    -- Fermer le panneau Options WoW
    if SettingsPanel and SettingsPanel.Close then
      SettingsPanel:Close()
    elseif SettingsPanel and SettingsPanel.Hide then
      HideUIPanel(SettingsPanel)
    end
    -- Ouvrir le panneau Aishaddon
    if ns.SettingsPanel then
      ns.SettingsPanel:Show()
    end
  end)

  local cat = Settings.RegisterCanvasLayoutCategory(canvas, "Aishaddon")
  Settings.RegisterAddOnCategory(cat)
  ns._wowSettingsCategory = cat
end

RegisterWoWSettings()

---------------------------------------------------------------------------
-- Exporter
ns.SettingsPanel = MainFrame

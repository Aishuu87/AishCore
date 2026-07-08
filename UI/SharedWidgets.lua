-- UI/SharedWidgets.lua : Widgets reutilisables pour le panneau de settings
local addonName, ns = ...

local SharedWidgets = {}
ns.SharedWidgets = SharedWidgets

-- Couleurs du theme — AishUI Black & Gold
local Theme = {
  -- Surfaces (noir quasi pur)
  bg            = { 0.030, 0.030, 0.035, 0.97 },
  bgHeader      = { 0.060, 0.060, 0.065, 1.00 },
  -- Bordures & séparateurs
  border        = { 0.180, 0.180, 0.195, 0.65 },
  separator     = { 0.260, 0.260, 0.280, 0.40 },
  -- Texte (hiérarchie off-white claire)
  textNormal    = { 0.92, 0.92, 0.93 },
  textBright    = { 0.98, 0.96, 0.90 },
  textHighlight = { 1.00, 1.00, 1.00 },
  textDisabled  = { 0.40, 0.40, 0.42 },
  textDim       = { 0.58, 0.58, 0.62 },
  -- Accent or (signature AishUI)
  accent        = { 0.78, 0.62, 0.30 },
  gold          = { 0.78, 0.62, 0.30 },
  accentGreen   = { 0.3,  0.9,  0.3  },
  -- Contrôles
  checkboxOn    = { 0.78, 0.62, 0.30 },
  checkboxOff   = { 0.180, 0.180, 0.195 },
  sliderThumb   = { 0.78, 0.62, 0.30 },
  sliderTrack   = { 0.180, 0.180, 0.195 },
  rowHover      = { 1, 1, 1, 0.04 },
}
ns.Theme = Theme

---------------------------------------------------------------------------
-- Checkbox (12×12) — style AishUI
---------------------------------------------------------------------------
function SharedWidgets.CreateCheckbox(parent, label, tooltip, width, height)
  width  = width  or 260
  height = height or 26

  local row = CreateFrame("Button", nil, parent)
  row:SetSize(width, height)

  -- Carré OFF/ON
  row.box = row:CreateTexture(nil, "ARTWORK")
  row.box:SetSize(12, 12)
  row.box:SetPoint("LEFT", 8, 0)
  row.box:SetColorTexture(unpack(Theme.checkboxOff))

  -- Coche Blizzard
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetSize(10, 10)
  row.check:SetPoint("CENTER", row.box)
  row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  row.check:Hide()

  -- Label
  row.label = row:CreateFontString(nil, "OVERLAY")
  row.label:SetFont(ns.Media.fontGui, 12)
  row.label:SetPoint("LEFT", row.box, "RIGHT", 6, 0)
  row.label:SetTextColor(unpack(Theme.textNormal))
  row.label:SetText(label or "")
  row.label:SetJustifyH("LEFT")

  row.tooltipText = tooltip
  row.checked = false

  function row:SetChecked(val)
    self.checked = val
    if val then
      self.box:SetColorTexture(unpack(Theme.checkboxOn))
      self.check:Show()
    else
      self.box:SetColorTexture(unpack(Theme.checkboxOff))
      self.check:Hide()
    end
  end

  function row:GetChecked()
    return self.checked
  end

  row:SetScript("OnEnter", function(self)
    self.label:SetTextColor(1, 1, 1)
    if self.tooltipText then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1, 1, 1)
      GameTooltip:AddLine(self.tooltipText, unpack(Theme.textNormal))
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function(self)
    self.label:SetTextColor(unpack(Theme.textNormal))
    GameTooltip:Hide()
  end)
  row:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if self.onChanged then self.onChanged(self.checked) end
    PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  end)

  return row
end

---------------------------------------------------------------------------
-- Slider (valeur numerique) â€” Style ElvUI : track plat + thumb carre + EditBox
---------------------------------------------------------------------------
function SharedWidgets.CreateSlider(parent, label, minVal, maxVal, step, width)
  width = width or 260
  -- Largeur maximale : Ã©vite qu'un slider en pleine largeur de panneau
  -- (W = CONTENT_W potentiellement large) devienne immense.
  local MAX_SLIDER_W = 220
  width = math.min(width, MAX_SLIDER_W)
  minVal = minVal or 0
  maxVal = maxVal or 100
  step   = step or 1

  local TRACK_H    = 6       -- hauteur de la piste plate
  local THUMB_W    = 10      -- largeur du curseur carre
  local THUMB_H    = 16      -- hauteur du curseur carre
  local EDIT_W     = 50      -- largeur de l'EditBox
  local EDIT_H     = 18
  local LABEL_H    = 14
  local GAP        = 3
  local BOTTOM_ROW = EDIT_H + 2
  local height     = LABEL_H + GAP + THUMB_H + GAP + BOTTOM_ROW + 2

  -- Nombre de decimales a afficher, base sur le pas
  local decimals = 0
  if step < 1 then
    decimals = math.max(1, math.ceil(-math.log10(step + 1e-9)))
  end
  local fmt = "%." .. decimals .. "f"

  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(width, height)

  -- Label (en haut, centre)
  container.label = container:CreateFontString(nil, "OVERLAY")
  container.label:SetFont(ns.Media.fontGui, 11)
  container.label:SetPoint("TOP", container, "TOP", 0, -1)
  container.label:SetTextColor(unpack(Theme.textNormal))
  container.label:SetText(label or "")

  -- Slider frame (PAS de template Blizzard â€” look epure ElvUI)
  local slider = CreateFrame("Slider", nil, container)
  slider:SetSize(width, THUMB_H)
  slider:SetPoint("TOP", container.label, "BOTTOM", 0, -GAP)
  slider:SetMinMaxValues(minVal, maxVal)
  slider:SetValueStep(step)
  slider:SetObeyStepOnDrag(true)
  slider:SetOrientation("HORIZONTAL")

  -- Piste plate (track)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(TRACK_H)
  track:SetColorTexture(unpack(Theme.sliderTrack))

  -- Curseur circulaire (thumb AishUI — Circle_Smooth2)
  local thumb = slider:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(THUMB_W, THUMB_H)
  thumb:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\Wheel\\Circle_Smooth2")
  thumb:SetVertexColor(1, 1, 1, 1)
  slider:SetThumbTexture(thumb)

  -- Ligne sous le slider : min | EditBox | max
  local minText = container:CreateFontString(nil, "OVERLAY")
  minText:SetFont(ns.Media.fontGui, 10)
  minText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -GAP)
  minText:SetTextColor(unpack(Theme.textDim))
  minText:SetText(string.format(fmt, minVal))

  local maxText = container:CreateFontString(nil, "OVERLAY")
  maxText:SetFont(ns.Media.fontGui, 10)
  maxText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -GAP)
  maxText:SetTextColor(unpack(Theme.textDim))
  maxText:SetText(string.format(fmt, maxVal))

  -- EditBox (centre, sous le slider, fond sombre integre)
  local editBox = CreateFrame("EditBox", nil, container)
  editBox:SetSize(EDIT_W, EDIT_H)
  editBox:SetPoint("TOP", slider, "BOTTOM", 0, -GAP + 1)
  editBox:SetAutoFocus(false)
  editBox:SetFont(ns.Media.fontGui, 11, "")
  editBox:SetTextColor(unpack(Theme.textHighlight))
  editBox:SetJustifyH("CENTER")
  editBox:SetNumeric(false)

  -- Fond sombre de l'EditBox (style ElvUI)
  local editBg = editBox:CreateTexture(nil, "BACKGROUND")
  editBg:SetPoint("TOPLEFT", -4, 2)
  editBg:SetPoint("BOTTOMRIGHT", 4, -2)
  editBg:SetColorTexture(0.06, 0.06, 0.08, 0.9)

  -- Bordure fine autour de l'EditBox
  local editBorder = CreateFrame("Frame", nil, editBox, "BackdropTemplate")
  editBorder:SetPoint("TOPLEFT", -4, 2)
  editBorder:SetPoint("BOTTOMRIGHT", 4, -2)
  editBorder:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
  })
  editBorder:SetBackdropBorderColor(unpack(Theme.border))

  container.slider    = slider
  container.editBox   = editBox
  container.currentValue = minVal

  -- Formate la valeur affichee
  local function FormatVal(val)
    return string.format(fmt, val)
  end

  -- Clamp + snap to step (pour le slider et SetValue programmatique)
  local function ClampAndStep(val)
    val = math.max(minVal, math.min(maxVal, val))
    if step > 0 then
      val = math.floor((val - minVal) / step + 0.5) * step + minVal
      -- Eviter les erreurs de flottants
      val = tonumber(string.format(fmt, val))
    end
    return val
  end

  -- Snap to step SANS clamping (pour la saisie manuelle dans l'EditBox)
  -- Permet d'entrer des valeurs hors de la plage du slider.
  local function SnapStep(val)
    if step > 0 then
      val = math.floor(val / step + 0.5) * step
      val = tonumber(string.format(fmt, val))
    end
    return val
  end

  function container:SetValue(val)
    val = SnapStep(val)                                    -- step-snap, no clamping
    self._programmaticSet = true
    self.slider:SetValue(math.max(minVal, math.min(maxVal, val)))  -- thumb stays within bounds
    self._programmaticSet = false
    -- Set currentValue and editBox AFTER the slider call so OnValueChanged's
    -- clamped write is overridden by the real (possibly out-of-range) value.
    self.currentValue = val
    self.editBox:SetText(FormatVal(val))
    self.editBox:SetCursorPosition(0)
  end

  function container:GetValue()
    return self.currentValue
  end

  -- Quand le slider bouge
  slider:SetScript("OnValueChanged", function(_, val)
    val = ClampAndStep(val)
    container.currentValue = val
    -- Mettre a jour l'editbox seulement si elle n'a pas le focus
    if not editBox:HasFocus() then
      editBox:SetText(FormatVal(val))
      editBox:SetCursorPosition(0)
    end
    if container.onChanged and not container._programmaticSet then
      container.onChanged(val)
    end
  end)

  -- Validation de l'EditBox (Enter ou perte de focus)
  -- La valeur saisie peut dépasser [minVal, maxVal] intentionnellement :
  -- le slider se positionne à la borne la plus proche, mais currentValue
  -- et onChanged reçoivent la vraie valeur saisie.
  local function CommitEditBox()
    local text = editBox:GetText()
    local num  = tonumber(text)
    if num then
      num = SnapStep(num)
      container.currentValue = num
      -- Slider : affichage borné à [minVal, maxVal] (pas de taint)
      slider:SetValue(math.max(minVal, math.min(maxVal, num)))
      editBox:SetText(FormatVal(num))
      if container.onChanged then
        container.onChanged(num)
      end
    else
      -- Texte invalide → restaurer la valeur courante
      editBox:SetText(FormatVal(container.currentValue))
    end
    editBox:SetCursorPosition(0)
    editBox:ClearFocus()
  end

  editBox:SetScript("OnEnterPressed", CommitEditBox)
  editBox:SetScript("OnEscapePressed", function()
    editBox:SetText(FormatVal(container.currentValue))
    editBox:ClearFocus()
  end)
  editBox:SetScript("OnEditFocusLost", CommitEditBox)

  -- Compatibilite : expose valueText pour le code existant
  container.valueText = container.editBox

  return container
end

---------------------------------------------------------------------------
-- Section Header — style AishUI (gold dot + texte uppercase + gold hairline)
---------------------------------------------------------------------------
function SharedWidgets.CreateSectionHeader(parent, text, width)
  width = width or 280
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 24)
  local g = Theme.gold or Theme.accent

  -- Dot or (circleflat2, 7×7)
  local dot = f:CreateTexture(nil, "OVERLAY")
  dot:SetSize(7, 7)
  dot:SetPoint("LEFT", 2, 0)
  dot:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\Wheel\\circleflat2")
  dot:SetVertexColor(g[1], g[2], g[3], 1)

  -- Label uppercase
  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 11)
  lbl:SetPoint("LEFT", 14, 0)
  lbl:SetTextColor(0.776, 0.710, 0.471, 1)  -- C6B578
  lbl:SetText((text or ""):upper())
  f.text = lbl

  -- Hairline or dégradé (du bord droit du texte jusqu'à la fin)
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("LEFT",  lbl,  "RIGHT", 10, 0)
  line:SetPoint("RIGHT", f,    "RIGHT", -2, 0)
  line:SetColorTexture(1, 1, 1, 1)
  pcall(function()
    if CreateColor then
      line:SetGradient("HORIZONTAL",
        CreateColor(g[1], g[2], g[3], 0.85),
        CreateColor(g[1] * 0.20, g[2] * 0.20, g[3] * 0.20, 0.10))
    end
  end)

  return f
end

---------------------------------------------------------------------------
-- Color swatch — carré coloré cliquable qui ouvre le picker natif WoW
---------------------------------------------------------------------------
function SharedWidgets.CreateColorSwatch(parent, label, tooltip, width)
  width = width or 260
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(width, 26)

  -- Carré coloré (bouton)
  local swatch = CreateFrame("Button", nil, row)
  swatch:SetSize(20, 20)
  swatch:SetPoint("LEFT", row, "LEFT", 0, 0)

  local border = swatch:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     -1,  1)
  border:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT",  1, -1)
  border:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.9)

  local colorTex = swatch:CreateTexture(nil, "ARTWORK")
  colorTex:SetAllPoints(swatch)
  swatch._colorTex = colorTex

  -- Label
  local lbl = row:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 12)
  lbl:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3])
  lbl:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
  lbl:SetText(label or "")

  -- État courant
  local _r, _g, _b, _a = 1, 1, 1, 1

  local function Redraw()
    colorTex:SetColorTexture(_r, _g, _b, 1)
  end

  -- API publique
  function row:SetColor(r, g, b, a)
    _r, _g, _b, _a = r or 0, g or 0, b or 0, (a or 1)
    Redraw()
  end

  -- Hover
  swatch:SetScript("OnEnter", function(self)
    border:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.9)
    if tooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label or "", 1, 1, 1)
      GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end
  end)
  swatch:SetScript("OnLeave", function(self)
    border:SetColorTexture(Theme.border[1], Theme.border[2], Theme.border[3], 0.9)
    GameTooltip:Hide()
  end)

  -- Clic → picker natif WoW (fallback multi-versions)
  swatch:SetScript("OnClick", function(self)
    local prevR, prevG, prevB = _r, _g, _b
    local function OnChange()
      local r, g, b = ColorPickerFrame:GetColorRGB()
      _r, _g, _b = r, g, b
      Redraw()
      if row.onChanged then row.onChanged(r, g, b, _a) end
    end
    local function OnCancel()
      _r, _g, _b = prevR, prevG, prevB
      Redraw()
      if row.onChanged then row.onChanged(prevR, prevG, prevB, _a) end
    end
    local info = {
      r = _r, g = _g, b = _b,
      hasOpacity = false,
      swatchFunc = OnChange,
      cancelFunc = OnCancel,
    }
    if OpenColorPickerWithOptions then
      OpenColorPickerWithOptions(info)
    elseif ColorPickerFrame.SetupColorPickerAndShow then
      ColorPickerFrame:SetupColorPickerAndShow(info)
    else
      -- Fallback classique (pre-Dragonflight)
      ColorPickerFrame.hasOpacity = false
      ColorPickerFrame.func       = OnChange
      ColorPickerFrame.cancelFunc = OnCancel
      ColorPickerFrame:SetColorRGB(_r, _g, _b)
      ShowUIPanel(ColorPickerFrame)
    end
  end)

  Redraw()
  return row
end

---------------------------------------------------------------------------
-- Bouton fermer (X)
---------------------------------------------------------------------------
function SharedWidgets.CreateCloseButton(parent, size)
  size = size or 20
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(size, size)

  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFont(ns.Media.fontGui, 15)
  btn.text:SetPoint("CENTER")
  btn.text:SetText("x")
  btn.text:SetTextColor(unpack(Theme.textDim))

  btn:SetScript("OnEnter", function(self)
    self.text:SetTextColor(1, 0.3, 0.3)
  end)
  btn:SetScript("OnLeave", function(self)
    self.text:SetTextColor(unpack(Theme.textDim))
  end)
  btn:SetScript("OnClick", function()
    parent:Hide()
    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
  end)

  return btn
end

---------------------------------------------------------------------------
-- Background panel (fond arrondi avec bordure)
---------------------------------------------------------------------------
function SharedWidgets.ApplyPanelBackground(frame)
  -- Fond texturé noir AishUI (grain procédural + vignette)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\UI\\PanelBackground")
  bg:SetVertexColor(1, 1, 1, Theme.bg[4] or 0.97)
  frame._bg = bg

  -- Bordures manuelles 1px (4 côtés)
  local bc = Theme.border
  local function MakeEdge()
    local t = frame:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.65)
    return t
  end
  local eTop = MakeEdge()
  eTop:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
  eTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  eTop:SetHeight(1)
  local eBot = MakeEdge()
  eBot:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
  eBot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  eBot:SetHeight(1)
  local eLeft = MakeEdge()
  eLeft:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0, 0)
  eLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  eLeft:SetWidth(1)
  local eRight = MakeEdge()
  eRight:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, 0)
  eRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  eRight:SetWidth(1)
end

---------------------------------------------------------------------------
-- Title bar (barre de titre en haut)
---------------------------------------------------------------------------
function SharedWidgets.CreateTitleBar(frame, title, height)
  height = height or 28
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetHeight(height)
  bar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  1, -1)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  -- Transparent : le logo sticker porte l'identité visuelle du panneau
  -- bar.title / bar.version créés pour compatibilité descendante mais non visibles
  bar.title   = bar:CreateFontString(nil, "OVERLAY")
  bar.version = bar:CreateFontString(nil, "OVERLAY")
  return bar
end

---------------------------------------------------------------------------
-- Helpers privés SharedWidgets
---------------------------------------------------------------------------
local function _ApplyBD(f, bg, edge)
  if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
  f:SetBackdrop({
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 0.8)
end

---------------------------------------------------------------------------
-- Dropdown (liste déroulante) — style AishUI : label au-dessus, bouton pleine largeur
---------------------------------------------------------------------------
function SharedWidgets.CreateDropdown(parent, label, options, width)
  -- options = { { value = ..., text = "..." }, ... }
  width = width or 260
  -- Label vide ("") traité comme absent
  local hasLabel = label and label ~= ""
  local BTN_H    = 22
  local LBL_H    = 18
  local height   = hasLabel and (LBL_H + BTN_H) or BTN_H

  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(width, height)

  -- Label au-dessus (optionnel)
  if hasLabel then
    container.label = container:CreateFontString(nil, "OVERLAY")
    container.label:SetFont(ns.Media.fontGui, 10)
    container.label:SetPoint("TOPLEFT")
    container.label:SetTextColor(unpack(Theme.textDim))
    container.label:SetText(label)
  end

  -- Bouton principal (pleine largeur, BackdropTemplate)
  local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
  btn:SetSize(width, BTN_H)
  btn:SetPoint("TOPLEFT", 0, hasLabel and -LBL_H or 0)
  _ApplyBD(btn, { 0.12, 0.12, 0.14, 1 }, Theme.border)

  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFont(ns.Media.fontGui, 10)
  btn.text:SetPoint("LEFT", 6, 0)
  btn.text:SetPoint("RIGHT", -20, 0)
  btn.text:SetJustifyH("LEFT")
  btn.text:SetTextColor(1, 1, 1)

  local ar = btn:CreateFontString(nil, "OVERLAY")
  ar:SetFont(ns.Media.fontGui, 9)
  ar:SetPoint("RIGHT", -6, 0)
  ar:SetText("v")
  ar:SetTextColor(unpack(Theme.textDim))
  btn.arrow = ar

  -- Menu déroulant (conteneur + scroll interne)
  local ITEM_H_PX   = 20
  local MAX_VISIBLE = 10
  local TOP_PAD     = 2

  local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
  menu:SetFrameStrata("TOOLTIP")
  menu:SetFrameLevel(200)
  menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
  menu:SetSize(width, BTN_H)
  menu:Hide()
  menu:EnableMouseWheel(true)
  _ApplyBD(menu, { 0.08, 0.08, 0.10, 0.97 }, Theme.border)

  -- scrollClip : zone de découpe
  local scrollClip = CreateFrame("Frame", nil, menu)
  scrollClip:SetClipsChildren(true)
  scrollClip:SetAllPoints(menu)

  -- menuContent : tous les items
  local menuContent = CreateFrame("Frame", nil, scrollClip)
  menuContent:SetWidth(width)
  menuContent:SetHeight(1)

  local scrollOffset = 0

  local function GetMaxScroll()
    local n = #container._options
    local v = math.min(n, MAX_VISIBLE)
    return math.max(0, (n - v) * ITEM_H_PX)
  end

  local function ApplyScroll()
    menuContent:ClearAllPoints()
    menuContent:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, scrollOffset - TOP_PAD)
  end

  local function DoScroll(delta)
    scrollOffset = math.max(0, math.min(GetMaxScroll(),
      scrollOffset + (-delta) * ITEM_H_PX * 3))
    ApplyScroll()
  end

  menu:SetScript("OnMouseWheel", function(_, delta) DoScroll(delta) end)

  container._btn     = btn
  container._menu    = menu
  container._options = options or {}
  container._items   = {}
  container.currentValue = nil

  local function CloseMenu()
    menu:Hide()
  end

  local function BuildMenuItems()
    for _, item in ipairs(container._items) do item:Hide() end
    wipe(container._items)
    scrollOffset = 0

    local numOpts  = #container._options
    local visCount = math.min(numOpts, MAX_VISIBLE)
    local menuH    = visCount * ITEM_H_PX + TOP_PAD * 2
    menu:SetHeight(math.max(menuH, BTN_H))
    menuContent:SetWidth(width - 2)
    menuContent:SetHeight(numOpts * ITEM_H_PX + TOP_PAD * 2)
    ApplyScroll()

    local yOff = 0
    for _, opt in ipairs(container._options) do
      local item = CreateFrame("Button", nil, menuContent)
      item:SetSize(width - 2, ITEM_H_PX)
      item:SetPoint("TOPLEFT", menuContent, "TOPLEFT", 1, yOff)
      item:EnableMouseWheel(true)
      item:SetScript("OnMouseWheel", function(_, delta) DoScroll(delta) end)

      local iBg = item:CreateTexture(nil, "BACKGROUND")
      iBg:SetAllPoints()
      iBg:SetColorTexture(0, 0, 0, 0)

      local iTx = item:CreateFontString(nil, "OVERLAY")
      iTx:SetFont(ns.Media.fontGui, 10)
      iTx:SetPoint("LEFT", 6, 0)
      iTx:SetPoint("RIGHT", -6, 0)
      iTx:SetJustifyH("LEFT")
      iTx:SetTextColor(unpack(Theme.textNormal))
      iTx:SetText(opt.text or tostring(opt.value))

      item:SetScript("OnEnter", function()
        iBg:SetColorTexture(unpack(Theme.rowHover))
        iTx:SetTextColor(1, 1, 1)
      end)
      item:SetScript("OnLeave", function()
        iBg:SetColorTexture(0, 0, 0, 0)
        iTx:SetTextColor(unpack(Theme.textNormal))
      end)
      item:SetScript("OnClick", function()
        container:SetValue(opt.value)
        CloseMenu()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if container.onChanged then container.onChanged(opt.value) end
      end)

      container._items[#container._items + 1] = item
      yOff = yOff - ITEM_H_PX
    end
  end

  function container:SetOptions(opts)
    self._options = opts or {}
    BuildMenuItems()
  end

  function container:SetValue(val)
    self.currentValue = val
    for _, opt in ipairs(self._options) do
      if opt.value == val then
        self._btn.text:SetText(opt.text or tostring(val))
        return
      end
    end
    self._btn.text:SetText(tostring(val))
  end

  function container:GetValue()
    return self.currentValue
  end

  btn:SetScript("OnClick", function()
    if menu:IsShown() then
      CloseMenu()
    else
      BuildMenuItems()
      menu:Show()
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)

  btn:SetScript("OnEnter", function(self)
    self:SetBackdropColor(0.16, 0.16, 0.18, 1)
  end)
  btn:SetScript("OnLeave", function(self)
    self:SetBackdropColor(0.12, 0.12, 0.14, 1)
  end)

  -- Fermer au clic extérieur
  menu:SetScript("OnUpdate", function(self)
    if not self:IsShown() then return end
    if not self:IsMouseOver() and not btn:IsMouseOver() then
      if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
        CloseMenu()
      end
    end
  end)

  BuildMenuItems()
  return container
end

---------------------------------------------------------------------------
-- Color Button (ouvre le ColorPicker Blizzard)
---------------------------------------------------------------------------
function SharedWidgets.CreateColorButton(parent, label, width)
  width = width or 260
  local height = 28

  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(width, height)

  local swatch = CreateFrame("Button", nil, container)
  swatch:SetSize(18, 18)
  swatch:SetPoint("LEFT", container, "LEFT", 4, 0)

  container.label = container:CreateFontString(nil, "OVERLAY")
  container.label:SetFont(ns.Media.fontGui, 11)
  container.label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
  container.label:SetTextColor(unpack(Theme.textNormal))
  container.label:SetText(label or "")

  local swatchBg = swatch:CreateTexture(nil, "BACKGROUND")
  swatchBg:SetAllPoints()
  swatchBg:SetColorTexture(0.1, 0.1, 0.1, 1)

  local swatchColor = swatch:CreateTexture(nil, "ARTWORK")
  swatchColor:SetAllPoints()
  swatchColor:SetColorTexture(1, 1, 1, 1)

  local swatchBorder = swatch:CreateTexture(nil, "BORDER")
  swatchBorder:SetPoint("TOPLEFT", -1, 1)
  swatchBorder:SetPoint("BOTTOMRIGHT", 1, -1)
  swatchBorder:SetColorTexture(unpack(Theme.border))

  container._swatch = swatch
  container._swatchColor = swatchColor
  container.currentColor = { 1, 1, 1, 1 }

  function container:SetColor(r, g, b, a)
    self.currentColor = { r or 1, g or 1, b or 1, a or 1 }
    self._swatchColor:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
  end

  function container:GetColor()
    return unpack(self.currentColor)
  end

  swatch:SetScript("OnEnter", function(self)
    swatchBorder:SetColorTexture(1, 1, 1, 0.6)
  end)
  swatch:SetScript("OnLeave", function(self)
    swatchBorder:SetColorTexture(unpack(Theme.border))
  end)

  swatch:SetScript("OnClick", function()
    local r, g, b, a = unpack(container.currentColor)
    local info = {}
    info.r = r
    info.g = g
    info.b = b
    info.opacity = a or 1
    info.hasOpacity = true
    info.swatchFunc = function()
      local nr, ng, nb = ColorPickerFrame:GetColorRGB()
      local na = 1
      if ColorPickerFrame.GetColorAlpha then
        na = ColorPickerFrame:GetColorAlpha()
      end
      container:SetColor(nr, ng, nb, na)
      if container.onChanged then
        container.onChanged({ nr, ng, nb, na })
      end
    end
    info.opacityFunc = info.swatchFunc
    info.cancelFunc = function(prev)
      if prev then
        local pr = prev.r or container.currentColor[1]
        local pg = prev.g or container.currentColor[2]
        local pb = prev.b or container.currentColor[3]
        local pa = prev.a or prev.opacity or container.currentColor[4]
        container:SetColor(pr, pg, pb, pa)
        if container.onChanged then
          container.onChanged({ pr, pg, pb, pa })
        end
      end
    end
    ColorPickerFrame:SetupColorPickerAndShow(info)
  end)

  return container
end

---------------------------------------------------------------------------
-- Groupe de boutons Radio (choix exclusif)
---------------------------------------------------------------------------
-- options = { { value = "...", label = "...", tooltip = "..." }, ... }
-- Retourne un frame avec :SetValue(val) / :GetValue() / .onChanged
---------------------------------------------------------------------------
function SharedWidgets.CreateRadioGroup(parent, options, width)
  width    = width or 260
  local itemH  = 28
  local totalH = #options * itemH

  local group = CreateFrame("Frame", nil, parent)
  group:SetSize(width, totalH)
  group._selected = nil
  group._buttons  = {}

  local function Refresh()
    for _, btn in ipairs(group._buttons) do
      local sel = (btn._value == group._selected)
      if sel then
        btn.ring:SetColorTexture(unpack(Theme.checkboxOn))
        btn.dot:Show()
        btn.label:SetTextColor(unpack(Theme.textHighlight))
      else
        btn.ring:SetColorTexture(unpack(Theme.checkboxOff))
        btn.dot:Hide()
        btn.label:SetTextColor(unpack(Theme.textNormal))
      end
    end
  end

  for idx, opt in ipairs(options) do
    local btn = CreateFrame("Button", nil, group)
    btn:SetSize(width, itemH)
    btn:SetPoint("TOPLEFT", group, "TOPLEFT", 0, -(idx - 1) * itemH)
    btn._value = opt.value

    btn.hover = btn:CreateTexture(nil, "BACKGROUND")
    btn.hover:SetAllPoints()
    btn.hover:SetColorTexture(unpack(Theme.rowHover))
    btn.hover:Hide()

    btn.ring = btn:CreateTexture(nil, "ARTWORK")
    btn.ring:SetSize(14, 14)
    btn.ring:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.ring:SetColorTexture(unpack(Theme.checkboxOff))

    btn.dot = btn:CreateTexture(nil, "OVERLAY")
    btn.dot:SetSize(8, 8)
    btn.dot:SetPoint("CENTER", btn.ring, "CENTER", 0, 0)
    btn.dot:SetColorTexture(unpack(Theme.checkboxOn))
    btn.dot:Hide()

    btn.label = btn:CreateFontString(nil, "OVERLAY")
    btn.label:SetFont(ns.Media.fontGui, 12)
    btn.label:SetPoint("LEFT", btn.ring, "RIGHT", 8, 0)
    btn.label:SetTextColor(unpack(Theme.textNormal))
    btn.label:SetText(opt.label or "")
    btn.label:SetJustifyH("LEFT")

    btn:SetScript("OnEnter", function(self)
      self.hover:Show()
      if opt.tooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(opt.label, 1, 1, 1)
        GameTooltip:AddLine(opt.tooltip, unpack(Theme.textNormal))
        GameTooltip:Show()
      end
    end)
    btn:SetScript("OnLeave", function(self)
      self.hover:Hide()
      GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
      group._selected = self._value
      Refresh()
      if group.onChanged then group.onChanged(group._selected) end
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    group._buttons[idx] = btn
  end

  function group:SetValue(val)
    self._selected = val
    Refresh()
  end

  function group:GetValue()
    return self._selected
  end

  return group
end

---------------------------------------------------------------------------
-- Toggle ON/OFF (pilule or) — style AishUI
-- Usage : t = SW.CreateToggle(parent, width); t:SetValue(bool); t.onChanged = fn
---------------------------------------------------------------------------
function SharedWidgets.CreateToggle(parent, width)
  width = width or 44
  local h = 18
  local g = Theme.gold or Theme.accent

  local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
  f:SetSize(width, h)
  _ApplyBD(f, { 0.06, 0.06, 0.07, 1 }, { g[1] * 0.55, g[2] * 0.55, g[3] * 0.45, 0.85 })

  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 9)
  lbl:SetAllPoints()
  lbl:SetJustifyH("CENTER")
  f._lbl = lbl
  f._on  = false

  local function Refresh()
    if f._on then
      f:SetBackdropColor(g[1], g[2], g[3], 0.95)
      f:SetBackdropBorderColor(g[1] * 0.6, g[2] * 0.6, g[3] * 0.4, 1)
      lbl:SetText("ON")
      lbl:SetTextColor(0.05, 0.05, 0.05, 1)
    else
      f:SetBackdropColor(0.06, 0.06, 0.07, 1)
      f:SetBackdropBorderColor(g[1] * 0.55, g[2] * 0.55, g[3] * 0.45, 0.85)
      lbl:SetText("OFF")
      lbl:SetTextColor(g[1] * 0.85, g[2] * 0.85, g[3] * 0.85, 1)
    end
  end
  Refresh()

  function f:SetValue(v)
    self._on = v and true or false
    Refresh()
  end
  function f:GetValue() return self._on end

  f:SetScript("OnClick", function(s)
    s._on = not s._on
    Refresh()
    if s.onChanged then s.onChanged(s._on) end
    PlaySound(s._on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  end)
  f:SetScript("OnEnter", function(s)
    if s._on then
      s:SetBackdropColor(g[1] * 1.10, g[2] * 1.10, g[3] * 1.10, 1)
    else
      s:SetBackdropBorderColor(g[1], g[2], g[3], 1)
    end
  end)
  f:SetScript("OnLeave", function() Refresh() end)

  return f
end

---------------------------------------------------------------------------
-- Action Button (bouton d'action avec backdrop) — style AishUI
-- Usage : btn = SW.CreateActionBtn(parent, "Texte", width, bgColor, borderColor, textColor)
-- Defaults : dark bg + theme border + white text
---------------------------------------------------------------------------
function SharedWidgets.CreateActionBtn(parent, text, width, bgColor, borderColor, textColor)
  width = width or 160
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width, 24)
  _ApplyBD(btn,
    bgColor     or { 0.08, 0.08, 0.12, 1 },
    borderColor or Theme.border)

  local lbl = btn:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 11)
  lbl:SetAllPoints()
  lbl:SetJustifyH("CENTER")
  if textColor then
    lbl:SetTextColor(textColor[1], textColor[2], textColor[3])
  else
    lbl:SetTextColor(1, 1, 1)
  end
  lbl:SetText(text or "")
  btn._lbl = lbl

  local _bg = bgColor or { 0.08, 0.08, 0.12, 1 }
  btn:SetScript("OnEnter", function(s)
    s:SetBackdropColor(_bg[1] + 0.06, _bg[2] + 0.06, _bg[3] + 0.06, _bg[4] or 1)
    lbl:SetTextColor(1, 1, 1)
  end)
  btn:SetScript("OnLeave", function(s)
    s:SetBackdropColor(_bg[1], _bg[2], _bg[3], _bg[4] or 1)
    if textColor then
      lbl:SetTextColor(textColor[1], textColor[2], textColor[3])
    else
      lbl:SetTextColor(1, 1, 1)
    end
  end)

  return btn
end

---------------------------------------------------------------------------
-- StyleEditBox — applique le thème AishUI Black & Gold sur un EditBox.
-- Masque les textures Blizzard (InputBoxTemplate), ajoute un fond sombre
-- et une bordure fine, et applique la police fontGui.
-- Usage :  SW.StyleEditBox(eb)           -- taille 11 par défaut
--          SW.StyleEditBox(eb, 10)        -- taille personnalisée
---------------------------------------------------------------------------
function SharedWidgets.StyleEditBox(eb, size)
  size = size or 11
  -- Masquer les textures du template Blizzard (Left / Middle / Right)
  for _, name in ipairs({ "Left", "Middle", "Right", "AltLeft", "AltMiddle", "AltRight" }) do
    local region = eb[name]
    if region and region.SetAlpha then region:SetAlpha(0) end
  end
  -- Police cohérente avec le panel
  eb:SetFont(ns.Media.fontGui, size, "")
  eb:SetTextColor(1, 1, 1)
  eb:SetTextInsets(4, 4, 2, 2)
  -- Fond sombre
  local eBg = eb:CreateTexture(nil, "BACKGROUND")
  eBg:SetPoint("TOPLEFT",     -2,  2)
  eBg:SetPoint("BOTTOMRIGHT",  2, -2)
  eBg:SetColorTexture(0.06, 0.06, 0.08, 0.95)
  -- Bordure fine 1 px (BackdropTemplate enfant)
  local eBd = CreateFrame("Frame", nil, eb, "BackdropTemplate")
  eBd:SetPoint("TOPLEFT",     -2,  2)
  eBd:SetPoint("BOTTOMRIGHT",  2, -2)
  eBd:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  eBd:SetBackdropBorderColor(unpack(Theme.border))
end

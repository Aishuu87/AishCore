-- UI/SharedWidgets.lua : Widgets reutilisables pour le panneau de settings
local addonName, ns = ...
local L = ns.L

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
  -- Accent de TEXTE (labels, titres...) -- distinct de accent/gold (dots, hairlines) ; cf. RefreshAccentTheme.
  accentText    = { 0.776, 0.710, 0.471 },
  accentGreen   = { 0.3,  0.9,  0.3  },
  -- Contrôles
  checkboxOn    = { 0.78, 0.62, 0.30 },
  checkboxOff   = { 0.180, 0.180, 0.195 },
  sliderThumb   = { 0.78, 0.62, 0.30 },
  sliderTrack   = { 0.180, 0.180, 0.195 },
  rowHover      = { 1, 1, 1, 0.04 },
}
ns.Theme = Theme

-- Checkbox (12×12) — style AishUI
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
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
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

-- Slider (valeur numerique) â€” Style ElvUI : track plat + thumb carre + EditBox
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

  -- Tooltip optionnel (`container.tooltipText`, renseigne par l'appelant), pose sur le
  -- LABEL uniquement : le survol du track et de l'EditBox reste libre pour le reglage.
  local labelHit = CreateFrame("Frame", nil, container)
  labelHit:SetPoint("TOP", container, "TOP", 0, 0)
  labelHit:SetSize(width, LABEL_H)
  labelHit:EnableMouse(true)
  labelHit:SetScript("OnEnter", function(self)
    if not container.tooltipText then return end
    container.label:SetTextColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(label or "", 1, 1, 1)
    GameTooltip:AddLine(container.tooltipText, unpack(Theme.textNormal))
    GameTooltip:Show()
  end)
  labelHit:SetScript("OnLeave", function()
    container.label:SetTextColor(unpack(Theme.textNormal))
    GameTooltip:Hide()
  end)

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
  thumb:SetTexture("Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2")
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

  -- Validation de l'EditBox (Enter ou perte de focus) : la valeur saisie peut
  -- depasser [minVal, maxVal] intentionnellement (slider cale sur la borne
  -- proche, mais currentValue/onChanged recoivent la vraie valeur).
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

-- Section Header — style AishUI (gold dot + texte uppercase + gold hairline).
-- Un TITRE DE SECTION (SharedWidgets.MakeSectionTitle) reprend le meme habillage en
-- deux points pres : libelle 2 tailles au-dessus, et couple de teintes distinct.
local HEADER_FONT_SIZE = 11
local TITLE_FONT_SIZE  = 13
local TITLE_HEIGHT     = 26
-- Filet d'1 pixel physique : un trait de 1 unite d'interface tombe souvent a cheval sur deux pixels ecran (trait
-- flou, ou de 2 px d'epaisseur selon sa position). Epaisseur = exactement 1 pixel, rendu cale sur la grille ;
-- recalculee a chaque affichage du parent (l'echelle peut changer). vertical = trait vertical (largeur).
function SharedWidgets.PixelLine(tex, vertical)
  if not tex then return tex end
  if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true); tex:SetTexelSnappingBias(0) end
  local function Fit()
    local _, ph = GetPhysicalScreenSize()
    local ok, es = pcall(tex.GetEffectiveScale, tex)
    if not (ok and es and es > 0 and ph and ph > 0) then return end
    local px = 768 / ph / es
    if vertical then tex:SetWidth(px) else tex:SetHeight(px) end
  end
  Fit()
  local p = tex:GetParent()
  if p and p.HookScript then p:HookScript("OnShow", Fit) end
  return tex
end

function SharedWidgets.CreateSectionHeader(parent, text, width, colorOverride)
  width = width or 280
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 24)
  -- Theme.gold/accentText suivent RefreshAccentTheme (theme de spe) ;
  -- colorOverride fixe une teinte propre (ex. couleur de classe) qui l'ignore.
  local g = colorOverride or Theme.gold or Theme.accent

  -- Dot or (circleflat2, 7×7)
  local dot = f:CreateTexture(nil, "OVERLAY")
  dot:SetSize(7, 7)
  dot:SetPoint("LEFT", 2, 0)
  dot:SetTexture("Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2")
  dot:SetVertexColor(g[1], g[2], g[3], 1)

  -- Label uppercase (Theme.accentText, suit RefreshAccentTheme, distinct du dot/hairline)
  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, HEADER_FONT_SIZE)
  lbl:SetPoint("LEFT", 14, 0)
  -- Nouveaute du dernier patch : l'icone remplace le point (cf. Data/PatchNotes.lua)
  if ns.IsNewHeader and ns.IsNewHeader(text) then
    local badge = ns.CreateNewBadge(f, 16)
    if badge then
      badge:SetPoint("LEFT", 0, 0)
      ns.RegisterNewBadge(badge, function(shown)
        dot:SetShown(not shown)
        lbl:SetPoint("LEFT", shown and (badge:GetWidth() + 3) or 14, 0)
      end)
    end
  end
  local tc = colorOverride or Theme.accentText or { 0.776, 0.710, 0.471 }
  lbl:SetTextColor(tc[1], tc[2], tc[3], 1)
  -- Libelle "nu", sans le prefixe +/- d'un en-tete repliable : SetHeaderCollapsedState
  -- le reecrit a chaque pli, il lui faut donc la base intacte.
  f._baseText = (text or ""):upper()
  lbl:SetText(f._baseText)
  f.text = lbl

  -- Hairline or dégradé (du bord droit du texte jusqu'à la fin)
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  SharedWidgets.PixelLine(line)
  line:SetPoint("LEFT",  lbl,  "RIGHT", 10, 0)
  line:SetPoint("RIGHT", f,    "RIGHT", -2, 0)
  line:SetColorTexture(1, 1, 1, 1)
  local function ApplyGradient(color)
    pcall(function()
      if CreateColor then
        line:SetGradient("HORIZONTAL",
          CreateColor(color[1], color[2], color[3], 0.85),
          CreateColor(color[1] * 0.20, color[2] * 0.20, color[3] * 0.20, 0.10))
      end
    end)
  end
  ApplyGradient(g)

  -- Header mis en cache par session ; RefreshColor() permet de le retenter
  -- au changement de spe sans rebuild (cf. RefreshSectionHeaderColors).
  function f:RefreshColor()
    -- Un header colorOverride garde sa teinte propre (couleur de classe) --
    -- seuls les headers "neutres" suivent le theme d'accent global.
    local c, tc
    if f._isSectionTitle then
      -- Titre de page : point + filet en "Decorations B", libelle en "Cercle de puissance".
      c  = colorOverride or Theme.accentText or Theme.gold
      tc = colorOverride or SharedWidgets.GetSectionTitleColor()
    else
      c  = colorOverride or Theme.gold or Theme.accent
      tc = colorOverride or Theme.accentText or c
    end
    dot:SetVertexColor(c[1], c[2], c[3], 1)
    ApplyGradient(c)
    lbl:SetTextColor(tc[1], tc[2], tc[3], 1)
  end

  -- Marqueur lu par le systeme de layout (NewLayout, SettingsPanel.lua) pour decouper
  -- une page en sections repliables. Les en-tetes pliables "maison" de certaines pages
  -- (Animations 3D, Ecran AFK, Armurerie...) ne passent pas par ctx:Add et ne sont donc
  -- jamais concernes.
  f._isSectionHeader = true
  f._dot = dot
  f._lbl = lbl

  SharedWidgets._sectionHeaders = SharedWidgets._sectionHeaders or {}
  table.insert(SharedWidgets._sectionHeaders, f)

  return f
end

-- Transforme un section header en en-tete repliable : le libelle est prefixe de
-- "+ " / "- " (meme rendu que les sous-sections de l'Ecran AFK : point dore, puis
-- le signe, puis le titre) et un bouton transparent par-dessus capte clic et survol.
-- Idempotent. L'etat n'est PAS stocke ici : l'appelant fournit onToggle et pilote
-- l'affichage via SharedWidgets.SetHeaderCollapsedState.
function SharedWidgets.MakeHeaderCollapsible(f, onToggle)
  if not f or f._collapseReady then return f end
  f._collapseReady = true

  local hitbox = CreateFrame("Button", nil, f)
  hitbox:SetAllPoints(f)
  hitbox:SetFrameLevel(f:GetFrameLevel() + 1)
  local hl = hitbox:CreateTexture(nil, "BACKGROUND")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.06)
  hl:Hide()
  hitbox:SetScript("OnEnter", function() hl:Show() end)
  hitbox:SetScript("OnLeave", function() hl:Hide() end)
  hitbox:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    SharedWidgets.HeaderClick(f, onToggle)
  end)
  f._hitbox = hitbox

  return f
end

-- Clic sur un en-tete pliable. Double clic (f._onSetAll(collapsed), pose par l'appelant) : plie / deplie
-- toutes les sections de la page dans le sens du 1er clic. Un repli attend FOLD_DELAY s pour laisser
-- venir le 2e clic ; un depli est immediat. Un 2e clic arrive apres le repli (entre FOLD_DELAY et
-- DOUBLE_CLICK) n'a rien a annuler : il etend simplement le repli aux autres sections.
-- Partage avec Modules/Auras/UI/SharedWidgets.lua.
local DOUBLE_CLICK = 0.25
local FOLD_DELAY   = 0.15
function SharedWidgets.HeaderClick(f, onToggle)
  local now = GetTime()
  local double = f._lastClick and (now - f._lastClick) < DOUBLE_CLICK
  if double and f._onSetAll then
    if f._pendingFold then f._pendingFold:Cancel(); f._pendingFold = nil end
    f._lastClick = nil
    f._onSetAll(f._lastClickFolds)
    return
  end
  f._lastClick = now
  f._lastClickFolds = not f._collapsed
  if f._onSetAll and not f._collapsed then
    if f._pendingFold then f._pendingFold:Cancel() end
    f._pendingFold = C_Timer.NewTimer(FOLD_DELAY, function()
      f._pendingFold = nil
      if onToggle then onToggle() end
    end)
  elseif onToggle then
    onToggle()
  end
end

--- Met a jour le seul prefixe +/- (aucun effet sur un header non pliable).
function SharedWidgets.SetHeaderCollapsedState(f, collapsed)
  if not f then return end
  f._collapsed = collapsed
  if not f._collapseReady or not f._lbl then return end
  f._lbl:SetText((collapsed and "+ " or "- ") .. (f._baseText or ""))
end

-- Couleur du libelle d'un titre de section : "Cercle de puissance" de la spe active
-- (meme source que ResourceCircle), repli sur l'ocre statique si le theme GUI est coupe
-- ou le module Couleurs indisponible.
local TITLE_TEXT_STATIC = { 0.78, 0.62, 0.30 }
function SharedWidgets.GetSectionTitleColor()
  local useTheme = not (ns.DB and ns.DB.colors and ns.DB.colors.themeGUI == false)
  if useTheme then
    local CLR = ns.Modules and ns.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get("powercircle")
    if c then return c end
  end
  return TITLE_TEXT_STATIC
end

-- Promeut un section header en TITRE DE SECTION : le premier en-tete d'une page,
-- jamais repliable, legerement plus gros et dans un couple de teintes distinct
-- (cf. RefreshColor ci-dessus). Idempotent.
function SharedWidgets.MakeSectionTitle(f)
  if not f or f._isSectionTitle then return f end
  f._isSectionTitle = true
  -- Plus jamais candidat au decoupage en sections repliables (cf. NewLayout).
  f._isSectionHeader = nil
  if f._lbl then f._lbl:SetFont(ns.Media.fontGui, TITLE_FONT_SIZE) end
  f:SetHeight(TITLE_HEIGHT)
  if f.RefreshColor then f:RefreshColor() end
  return f
end

-- Recolore les section headers existants sans rebuild (safe au changement de spe ou edit couleur en direct).
function SharedWidgets.RefreshSectionHeaderColors()
  for _, f in ipairs(SharedWidgets._sectionHeaders or {}) do
    if f.RefreshColor then f:RefreshColor() end
  end
end

-- Theme d'accent GUI (gold/accent = "Points de Puissance A", accentText = "B"),
-- source du module Colors si ns.DB.colors.themeGUI est actif, sinon ocre statique.
-- Mute les tables Theme EN PLACE (lues directement a ~90 endroits) ; les
-- widgets deja peints ne se repeignent pas retroactivement sans refresh explicite.
local ACCENT_STATIC      = { 0.78, 0.62, 0.30 }
local ACCENT_TEXT_STATIC = { 0.776, 0.710, 0.471 }
function SharedWidgets.RefreshAccentTheme()
  local useTheme = not (ns.DB and ns.DB.colors and ns.DB.colors.themeGUI == false)
  local c, ct = ACCENT_STATIC, ACCENT_TEXT_STATIC
  if useTheme then
    local CLR = ns.Modules and ns.Modules.Colors
    local dc = CLR and CLR.Get and CLR.Get("powerdotsa")
    if dc then c = dc end
    local tc = CLR and CLR.Get and CLR.Get("powerdotsb")
    if tc then ct = tc end
  end
  for i = 1, 3 do
    Theme.gold[i]       = c[i]
    Theme.accent[i]     = c[i]
    Theme.accentText[i] = ct[i]
  end
  SharedWidgets.RefreshSectionHeaderColors()
  local SP = ns.SettingsPanel
  if SP and SP.RefreshSidebarColors then pcall(SP.RefreshSidebarColors) end
end

-- Color swatch — carré coloré cliquable qui ouvre le picker natif WoW
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
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
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

-- Molette fluide : chaque cran deplace une cible, le defilement la rejoint en ease-out.
-- Un SetVerticalScroll venu d'ailleurs (changement de page, drag du curseur) annule l'animation.
-- Retourne false si le cadre n'a rien a defiler (l'appelant peut relayer la molette).
function SharedWidgets.SmoothScroll(sf, delta, step)
  local max = sf:GetVerticalScrollRange() or 0
  if max <= 0 then return false end
  local cur = sf:GetVerticalScroll() or 0
  local d = sf._ssDriver
  local running = d and d:IsShown() and sf._ssLast and math.abs(cur - sf._ssLast) < 0.5
  local target = math.max(0, math.min(max, (running and sf._ssTarget or cur) - delta * step))
  if SharedWidgets.animEnabled == false then
    sf:SetVerticalScroll(target)
    return true
  end
  sf._ssTarget, sf._ssLast = target, cur
  if not d then
    d = CreateFrame("Frame")
    d:Hide()
    d:SetScript("OnUpdate", function(self, elapsed)
      local now = sf:GetVerticalScroll() or 0
      if math.abs(now - (sf._ssLast or now)) > 0.5 then self:Hide() return end
      local t = math.min(sf._ssTarget, sf:GetVerticalScrollRange() or 0)
      local v = now + (t - now) * math.min(1, elapsed * 14)
      if math.abs(t - v) < 0.5 then v = t; self:Hide() end
      sf:SetVerticalScroll(v)
      sf._ssLast = v
    end)
    sf._ssDriver = d
  end
  d:Show()
  return true
end

-- Bouton fermer (X)
function SharedWidgets.CreateCloseButton(parent, size)
  size = size or 20
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(size, size)

  btn.text = btn:CreateFontString(nil, "OVERLAY")
  btn.text:SetFont(ns.Media.fontGui, math.floor(15 * size / 20 + 0.5))
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

-- Background panel (fond arrondi avec bordure)
function SharedWidgets.ApplyPanelBackground(frame)
  -- Fond texturé noir AishUI (grain procédural + vignette)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\PanelBackground")
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
  frame._edges = { eTop, eBot, eLeft, eRight }
end

-- Bords "parchemin" : masque dechire (gamepad-map-texture-mask, etire sur tout le cadre) applique au fond du cadre
-- et aux textures `extra` (fonds d'autres sous-cadres, separateurs). Un masque ne decoupe que des textures, et
-- seulement celles de son propre cadre : un masque par cadre parent, ancre sur `frame`. Les bordures droites de
-- 1 px (ApplyPanelBackground) sont retirees, elles casseraient l'effet.
local PARCHMENT_MASK = "Interface\\AddOns\\AishCore\\Media\\UI\\gamepad-map-texture-mask.png"
function SharedWidgets.ApplyParchmentMask(frame, extra)
  local masks = {}
  local function MaskFor(owner)
    local m = masks[owner]
    if not m then
      m = owner:CreateMaskTexture()
      m:SetTexture(PARCHMENT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(frame)
      masks[owner] = m
    end
    return m
  end
  local list = { frame._bg }
  for _, t in ipairs(extra or {}) do list[#list + 1] = t end
  for _, t in ipairs(list) do
    if t then t:AddMaskTexture(MaskFor(t:GetParent())) end
  end
  for _, e in ipairs(frame._edges or {}) do e:Hide() end
end

-- Title bar (barre de titre en haut)
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

-- Helpers privés SharedWidgets
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

-- Relayout anime. layoutFn() repositionne / affiche / masque les frames de `frames` comme d'habitude
-- (resultat final immediat) ; on compare l'avant/l'apres pour glisser verticalement les frames qui
-- bougent et fondre celles qui apparaissent ou disparaissent. Sans pilote d'animation, ou si le
-- panneau n'est pas visible : layoutFn() seul. `key` identifie l'animation en cours (une par page).
local _layoutAnims = {}
function SharedWidgets.AnimateLayout(key, frames, layoutFn)
  local SWm = SharedWidgets
  if not (SWm.StartAnim and SWm.animEnabled) or not (frames[1] and frames[1]:IsVisible()) then
    layoutFn()
    return
  end
  -- Une animation precedente est terminee d'office : on repart d'un etat final propre
  local prev = _layoutAnims[key]
  if prev then SWm.StopAnim(key); prev() ; _layoutAnims[key] = nil end

  local before = {}
  for i, f in ipairs(frames) do
    local info = { shown = f:IsShown(), pts = {} }
    if info.shown then
      for p = 1, f:GetNumPoints() do info.pts[p] = { f:GetPoint(p) } end
    end
    before[i] = info
  end

  layoutFn()

  local moving, fadeIn, fadeOut = {}, {}, {}
  for i, f in ipairs(frames) do
    local b, shown = before[i], f:IsShown()
    if shown and b.shown then
      local n = f:GetNumPoints()
      if n == #b.pts and n > 0 then
        local after, dy = {}, 0
        for p = 1, n do after[p] = { f:GetPoint(p) } end
        dy = (b.pts[1][5] or 0) - (after[1][5] or 0)
        if math.abs(dy) > 0.5 then moving[#moving + 1] = { f = f, after = after, dy = dy } end
      end
    elseif shown and not b.shown then
      fadeIn[#fadeIn + 1] = f
    elseif b.shown and not shown then
      -- on la garde visible le temps du fondu, a son ancienne position
      f:ClearAllPoints()
      for _, pt in ipairs(b.pts) do f:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
      f:Show()
      fadeOut[#fadeOut + 1] = f
    end
  end
  if #moving + #fadeIn + #fadeOut == 0 then return end

  local function Finish()
    for _, m in ipairs(moving) do
      m.f:ClearAllPoints()
      for _, pt in ipairs(m.after) do m.f:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
    end
    for _, f in ipairs(fadeIn) do f:SetAlpha(1) end
    for _, f in ipairs(fadeOut) do f:Hide(); f:SetAlpha(1) end
  end
  _layoutAnims[key] = Finish
  for _, f in ipairs(fadeIn) do f:SetAlpha(0) end
  SWm.StartAnim(key, 0.18, function(e)
    for _, m in ipairs(moving) do
      m.f:ClearAllPoints()
      for _, pt in ipairs(m.after) do
        m.f:SetPoint(pt[1], pt[2], pt[3], pt[4], (pt[5] or 0) + m.dy * (1 - e))
      end
    end
    for _, f in ipairs(fadeIn) do f:SetAlpha(e) end
    for _, f in ipairs(fadeOut) do f:SetAlpha(1 - e) end
  end, function()
    Finish()
    _layoutAnims[key] = nil
  end)
end

-- Ouverture animee d'un menu deroulant (fondu + deploiement en hauteur), pilote SW.StartAnim defini
-- par UI/SettingsPanel.lua. Partage avec les menus du module Auras. Sans pilote : ouverture seche.
function SharedWidgets.AnimateMenuOpen(menu)
  if not (SharedWidgets.StartAnim and SharedWidgets.animEnabled) then return end
  local fullH = menu:GetHeight()
  if not fullH or fullH <= 6 then return end
  menu:SetAlpha(0)
  menu:SetHeight(4)
  SharedWidgets.StartAnim(menu, 0.14, function(e)
    menu:SetAlpha(e)
    menu:SetHeight(math.max(4, fullH * e))
  end, function()
    menu:SetAlpha(1)
    menu:SetHeight(fullH)
  end)
end

-- Dropdown (liste déroulante) — style AishUI : label au-dessus, bouton pleine largeur
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

  -- Parente a UIParent (et non au bouton) : la liste n'est ainsi pas decoupee par la zone defilante de la page et peut deborder
  -- de la fenetre. Ancree au bouton ; l'echelle est recalee sur celle du bouton, la fermeture suit le masquage du bouton.
  local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  menu:SetFrameStrata("TOOLTIP")
  menu:SetFrameLevel(200)
  menu:SetClampedToScreen(true)
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
  local SB_W = 7                -- barre de defilement (listes de plus de MAX_VISIBLE entrees)

  local function GetMaxScroll()
    local n = #container._options
    local v = math.min(n, MAX_VISIBLE)
    return math.max(0, (n - v) * ITEM_H_PX)
  end

  -- Barre de defilement cliquable : clic sur la piste = saut a cet endroit, poignee a glisser.
  local track = CreateFrame("Button", nil, menu)
  track:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -TOP_PAD - 1)
  track:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -2, TOP_PAD + 1)
  track:SetWidth(SB_W - 2)
  track:SetFrameLevel(menu:GetFrameLevel() + 5)
  local trackBg = track:CreateTexture(nil, "BACKGROUND")
  trackBg:SetAllPoints()
  trackBg:SetColorTexture(1, 1, 1, 0.06)
  local thumb = CreateFrame("Button", nil, track)
  thumb:SetWidth(SB_W - 2)
  thumb:SetFrameLevel(track:GetFrameLevel() + 1)
  local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
  thumbTex:SetAllPoints()
  local function ThumbColor(hover)
    local a = Theme.accentText or Theme.gold or { 0.78, 0.62, 0.30 }
    thumbTex:SetColorTexture(a[1], a[2], a[3], hover and 0.95 or 0.6)
  end
  ThumbColor(false)
  track:Hide()

  local function TrackMetrics()
    local trackH = track:GetHeight() or 0
    local n = math.max(1, #container._options)
    local thumbH = math.max(14, trackH * math.min(1, MAX_VISIBLE / n))
    return trackH, thumbH
  end

  local function UpdateThumb()
    local maxS = GetMaxScroll()
    if maxS <= 0 then track:Hide(); return end
    track:Show()
    local trackH, thumbH = TrackMetrics()
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(trackH - thumbH) * (scrollOffset / maxS))
  end

  local function ApplyScroll()
    menuContent:ClearAllPoints()
    menuContent:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, scrollOffset - TOP_PAD)
    UpdateThumb()
  end

  -- Ordonnee du curseur dans la piste (0 = haut), en unites de la piste
  local function CursorInTrack()
    local _, cy = GetCursorPosition()
    local sc = track:GetEffectiveScale()
    return (track:GetTop() or 0) - cy / sc
  end

  local function ScrollToTrackY(y, grabOffset)
    local maxS = GetMaxScroll()
    local trackH, thumbH = TrackMetrics()
    local range = trackH - thumbH
    if range <= 0 then return end
    local top = math.max(0, math.min(range, y - (grabOffset or thumbH / 2)))
    scrollOffset = math.floor(maxS * top / range + 0.5)
    ApplyScroll()
  end

  local dragGrab
  local function StopDrag() dragGrab = nil; track:SetScript("OnUpdate", nil) end
  local function StartDrag(grab)
    dragGrab = grab
    track:SetScript("OnUpdate", function()
      if not IsMouseButtonDown("LeftButton") then StopDrag(); return end
      ScrollToTrackY(CursorInTrack(), dragGrab)
    end)
  end
  -- Clic sur la piste : la poignee saute sous le curseur (centree) puis suit la souris tant que le bouton est enfonce
  track:SetScript("OnMouseDown", function()
    local _, thumbH = TrackMetrics()
    ScrollToTrackY(CursorInTrack(), thumbH / 2)
    StartDrag(thumbH / 2)
  end)
  -- Clic sur la poignee : elle suit la souris depuis le point saisi
  thumb:SetScript("OnMouseDown", function()
    StartDrag(CursorInTrack() - ((thumb:GetTop() and track:GetTop()) and (track:GetTop() - thumb:GetTop()) or 0))
  end)
  thumb:SetScript("OnEnter", function() ThumbColor(true) end)
  thumb:SetScript("OnLeave", function() ThumbColor(false) end)
  track:EnableMouseWheel(true)

  local function DoScroll(delta)
    scrollOffset = math.max(0, math.min(GetMaxScroll(),
      scrollOffset + (-delta) * ITEM_H_PX * 3))
    ApplyScroll()
  end

  menu:SetScript("OnMouseWheel", function(_, delta) DoScroll(delta) end)
  track:SetScript("OnMouseWheel", function(_, delta) DoScroll(delta) end)

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
    -- Liste plus longue que la zone visible : place pour la barre de defilement a droite
    local itemW = (numOpts > MAX_VISIBLE) and (width - 2 - SB_W) or (width - 2)
    menuContent:SetWidth(itemW)
    menuContent:SetHeight(numOpts * ITEM_H_PX + TOP_PAD * 2)
    ApplyScroll()

    local yOff = 0
    for _, opt in ipairs(container._options) do
      local item = CreateFrame("Button", nil, menuContent)
      item:SetSize(itemW, ITEM_H_PX)
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
    -- Pas de correspondance exacte (ex: chemin de police obsolete) : afficher
    -- le nom de fichier plutot que le chemin complet illisible.
    local display = tostring(val)
    local base = display:match("([^\\/]+)$") or display
    base = base:gsub("%.%a+$", "")
    self._btn.text:SetText(base ~= "" and base or display)
  end

  function container:GetValue()
    return self.currentValue
  end

  btn:HookScript("OnHide", CloseMenu)

  btn:SetScript("OnClick", function()
    if menu:IsShown() then
      CloseMenu()
    else
      BuildMenuItems()
      local ratio = btn:GetEffectiveScale() / UIParent:GetEffectiveScale()
      menu:SetScale(ratio)
      -- Pas la place en dessous : la liste s'ouvre vers le haut
      menu:ClearAllPoints()
      local bottom = btn:GetBottom() or 0
      if bottom * btn:GetEffectiveScale() < menu:GetHeight() * menu:GetEffectiveScale() + 10 then
        menu:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 1)
      else
        menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
      end
      menu:Show()
      SharedWidgets.AnimateMenuOpen(menu)
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
    if not btn:IsVisible() then return CloseMenu() end   -- page / panneau masque : la liste (parentee a UIParent) ne doit pas rester
    if not ns.IsFrameMouseOver(self) and not ns.IsFrameMouseOver(btn) then
      if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
        CloseMenu()
      end
    end
  end)

  BuildMenuItems()
  return container
end

-- Color Button (ouvre le ColorPicker Blizzard)
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

  -- Grisage : la pastille cesse de reagir a la souris et l'ensemble s'estompe, pour montrer que
  -- le reglage est ignore (typiquement quand une couleur thematique prend le relais).
  function container:SetEnabled(enabled)
    self._enabled = enabled and true or false
    self._swatch:EnableMouse(self._enabled)
    self:SetAlpha(self._enabled and 1 or 0.35)
  end

  swatch:SetScript("OnEnter", function(self)
    swatchBorder:SetColorTexture(1, 1, 1, 0.6)
  end)
  swatch:SetScript("OnLeave", function(self)
    swatchBorder:SetColorTexture(unpack(Theme.border))
  end)

  -- Clic droit : reinitialisation laissee a l'appelant (container.onReset), meme convention que les Modes
  swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  swatch:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      if container.onReset then container.onReset() end
      return
    end
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

-- Ligne d'alignement/ancrage : 3 boutons exclusifs, label simple au-dessus.
-- Partage entre Alignement (cast bars) et Ancrage (Top Target).
function SharedWidgets.CreateAlignRow(parent, label, width, options)
  options = options or {
    { k = "LEFT",   l = L["SETTINGS_ALIGN_LEFT"] },
    { k = "CENTER", l = L["SETTINGS_ALIGN_CENTER"] },
    { k = "RIGHT",  l = L["SETTINGS_ALIGN_RIGHT"] },
  }
  local ABTN_W = 90
  local LBL_H  = 14
  local GAP    = 3
  local BTN_H  = 22

  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(width or 260, LBL_H + GAP + BTN_H)

  local lbl = container:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 10)
  lbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
  lbl:SetTextColor(unpack(Theme.textDim))
  lbl:SetText(label or "")

  container.currentValue = options[1].k
  local btns = {}
  local function Refresh(val)
    container.currentValue = val
    for _, b in ipairs(btns) do
      if b.key == val then
        b._lbl:SetTextColor(unpack(Theme.accentText))
        b:SetBackdropColor(0.20, 0.15, 0.08, 1)
      else
        b._lbl:SetTextColor(unpack(Theme.textNormal))
        b:SetBackdropColor(0.08, 0.08, 0.12, 1)
      end
    end
  end

  for i, opt in ipairs(options) do
    local b = CreateFrame("Button", nil, container, "BackdropTemplate")
    b:SetSize(ABTN_W, BTN_H)
    b:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (ABTN_W + 4), -(LBL_H + GAP))
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(0.08, 0.08, 0.12, 1)
    b:SetBackdropBorderColor(unpack(Theme.border))
    local blbl = b:CreateFontString(nil, "OVERLAY")
    blbl:SetAllPoints()
    blbl:SetFont(ns.Media.fontGui, 11)
    blbl:SetJustifyH("CENTER")
    blbl:SetTextColor(unpack(Theme.textNormal))
    blbl:SetText(opt.l)
    b._lbl = blbl
    b.key = opt.k
    b:SetScript("OnClick", function()
      Refresh(opt.k)
      if container.onChanged then container.onChanged(opt.k) end
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    table.insert(btns, b)
  end

  function container:SetValue(val)
    Refresh(val or options[1].k)
  end

  container:SetValue(options[1].k)
  return container
end

-- Groupe de boutons Radio (choix exclusif)
-- options = { { value = "...", label = "...", tooltip = "..." }, ... }
-- Retourne un frame avec :SetValue(val) / :GetValue() / .onChanged
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
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
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

-- Toggle ON/OFF (pilule or) — style AishUI
-- Usage : t = SW.CreateToggle(parent, width); t:SetValue(bool); t.onChanged = fn
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
      lbl:SetText(L["WIDGET_TOGGLE_ON"])
      lbl:SetTextColor(0.05, 0.05, 0.05, 1)
    else
      f:SetBackdropColor(0.06, 0.06, 0.07, 1)
      f:SetBackdropBorderColor(g[1] * 0.55, g[2] * 0.55, g[3] * 0.45, 0.85)
      lbl:SetText(L["WIDGET_TOGGLE_OFF"])
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

-- Action Button (bouton d'action avec backdrop) — style AishUI
-- Usage : btn = SW.CreateActionBtn(parent, "Texte", width, bgColor, borderColor, textColor)
-- Defaults : dark bg + theme border + white text
-- Fond des encarts d'apercu (toast de niveau, barre de menu, barres dynamiques) : capture d'ecran du jeu (1280 x 720),
-- posee a sa taille reelle et centree dans un cadre qui rogne ce qui depasse de l'encart : on n'en voit qu'une bande,
-- jamais etiree ni comprimee (un recadrage par coordonnees de texture dependait de la taille de l'encart au moment du
-- calcul et pouvait rester inapplique). Encart plus grand que l'image : elle est agrandie juste assez pour le couvrir.
-- Le fond de la backdrop devient transparent, la bordure reste.
local PREVIEW_SCREEN = "Interface\\AddOns\\AishCore\\Media\\UI\\previewscreen.png"
local PREVIEW_W, PREVIEW_IH = 1280, 720
function SharedWidgets.ApplyPreviewScreen(frame)
  if not frame or frame._previewScreen then return end
  if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0) end
  -- Meme niveau que l'encart : ses enfants (contenu de l'apercu, un niveau au-dessus) restent devant
  local lvl = frame:GetFrameLevel()
  local clip = CreateFrame("Frame", nil, frame)
  clip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  clip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  clip:SetClipsChildren(true)
  clip:SetFrameLevel(lvl)
  local holder = CreateFrame("Frame", nil, clip)
  holder:SetSize(PREVIEW_W, PREVIEW_IH)
  holder:SetPoint("CENTER", clip, "CENTER", 0, 0)
  holder:SetFrameLevel(lvl)
  local t = holder:CreateTexture(nil, "BACKGROUND")
  t:SetTexture(PREVIEW_SCREEN)
  t:SetAllPoints(holder)
  frame._previewScreen = t
  local function Fit()
    local w, h = frame:GetWidth(), frame:GetHeight()
    local k = 1
    if w and h and w > 0 and h > 0 then k = math.max(1, w / PREVIEW_W, h / PREVIEW_IH) end
    holder:SetSize(PREVIEW_W * k, PREVIEW_IH * k)
  end
  frame:HookScript("OnSizeChanged", Fit)
  Fit()
end

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

-- StyleEditBox — applique le thème AishUI Black & Gold sur un EditBox (masque
-- les textures Blizzard, ajoute fond sombre + bordure fine, police fontGui).
-- Usage : SW.StyleEditBox(eb[, size])  -- taille 11 par défaut
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

-- Nag de soutien : phrase grisee avec une portion cliquable (SimpleHTML,
-- seul type de frame Blizzard a gerer wrap + lien cliquable a la fois).
-- template : phrase localisee avec un "%s" ou inserer la portion cliquable.
function SharedWidgets.CreateSupportNag(parent, width, template)
  local html = CreateFrame("SimpleHTML", nil, parent)
  html:SetWidth(width)
  -- SimpleHTML:SetFont() ne supporte que p/h1-h3 (pas "a") : couleur du lien
  -- via un code couleur |cffRRGGBB inline dans le texte visible.
  html:SetFont("p", ns.Media.fontGui, 11, "")
  html:SetTextColor("p", 0.45, 0.45, 0.47)

  local ar, ag, ab = Theme.accentText[1], Theme.accentText[2], Theme.accentText[3]
  local hex = string.format("%02x%02x%02x",
    math.floor(ar * 255 + 0.5), math.floor(ag * 255 + 0.5), math.floor(ab * 255 + 0.5))
  local linkTag = string.format('<a href="heroicsupport">|cff%s%s|r</a>', hex, L["SETTINGS_SUPPORT_LINK_TEXT"])
  local body = string.format(template, linkTag)
  html:SetText("<html><body><p>" .. body .. "</p></body></html>")

  html:SetScript("OnHyperlinkClick", function()
    local panel = ns.SettingsPanel
    if not panel then return end
    if not panel:IsShown() and panel.ShowUI then panel:ShowUI() end
    if panel.SelectCategory then panel:SelectCategory("heroicSupport") end
  end)
  -- Survol signale par une texture de soulignement dessinee sous le lien
  -- (SimpleHTML ne supporte pas le tag <u>, pas de SetCursor non plus).
  local underline = html:CreateTexture(nil, "OVERLAY")
  underline:SetColorTexture(ar, ag, ab, 1)
  underline:SetHeight(1)
  SharedWidgets.PixelLine(underline)
  underline:Hide()
  html:SetScript("OnHyperlinkEnter", function(_, _, _, region)
    if not region then return end
    underline:ClearAllPoints()
    underline:SetPoint("TOPLEFT", region, "BOTTOMLEFT", 0, -1)
    underline:SetPoint("TOPRIGHT", region, "BOTTOMRIGHT", 0, -1)
    underline:Show()
  end)
  html:SetScript("OnHyperlinkLeave", function()
    underline:Hide()
  end)

  -- Hauteur de contenu calculee par SimpleHTML apres SetText+SetWidth ; relue ici pour l'appelant.
  html:SetHeight(math.max(16, html:GetHeight() or 16))
  return html
end

-- Carrousel d'images : bandeau + miniatures cliquables, defilement auto (pause
-- 10s apres un clic manuel). images = { { texture = "chemin", tooltip =
-- "optionnel" }, ... }. Pas de GIF anime (pas de decodeur GIF dans WoW).
-- Dore FIXE, independant de Theme.accent/gold (mutes par RefreshAccentTheme
-- selon la spe) : le carrousel reste dore quel que soit le theme d'accent.
local CAROUSEL_GOLD = { 0.78, 0.62, 0.30 }
-- Expose pour les usages hors de ce fichier (ex: Build.HeroicSupport) qui doivent
-- eux aussi rester dores en permanence, independamment du theme d'accent.
SharedWidgets.HEROIC_GOLD = CAROUSEL_GOLD
-- Police de la legende : police du jeu (2002), disponible dans toutes les locales.
-- Aucune dependance a une media pack externe.
local CAROUSEL_CAPTION_FONT = ns.FONT_FALLBACK

function SharedWidgets.CreateCarousel(parent, width, height, images, autoInterval)
  autoInterval = autoInterval or 6
  -- THUMB=8 (moitie de l'ancienne taille) evite le rendu flou observe a 10px/16px.
  local THUMB, GAP = 8, 4
  local FOOT_H = 16 -- rangee sous le cadre : legende (gauche) + miniatures (droite)

  local container = CreateFrame("Frame", nil, parent)
  container:SetSize(width, height + FOOT_H + 8)

  local mainFrame = CreateFrame("Frame", nil, container)
  mainFrame:SetSize(width, height)
  mainFrame:SetPoint("TOP", container, "TOP", 0, 0)
  local mainBorder = mainFrame:CreateTexture(nil, "BORDER")
  mainBorder:SetPoint("TOPLEFT", -2, 2)
  mainBorder:SetPoint("BOTTOMRIGHT", 2, -2)
  mainBorder:SetColorTexture(unpack(CAROUSEL_GOLD))
  local tex = mainFrame:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()

  -- Barre de progression (style "story") : visualise le temps restant avant
  -- le prochain slide, remise a 0 a chaque changement (manuel ou auto).
  local progressTrack = mainFrame:CreateTexture(nil, "OVERLAY")
  progressTrack:SetPoint("BOTTOMLEFT", 0, 0)
  progressTrack:SetPoint("BOTTOMRIGHT", 0, 0)
  progressTrack:SetHeight(4)
  progressTrack:SetColorTexture(0, 0, 0, 0)
  local progressBar = mainFrame:CreateTexture(nil, "OVERLAY")
  progressBar:SetPoint("BOTTOMLEFT", 0, 0)
  progressBar:SetHeight(4)
  progressBar:SetWidth(1)
  progressBar:SetColorTexture(unpack(CAROUSEL_GOLD))
  -- pendingWait : delai avant le prochain slide (10s apres un clic manuel).
  -- Un seul chrono (slideStartTime) pilote barre + defilement, evite la
  -- desync de l'ancien systeme a deux chronos separes.
  local slideStartTime = GetTime()
  local pendingWait = autoInterval
  mainFrame:SetScript("OnUpdate", function()
    local pct = math.min(1, (GetTime() - slideStartTime) / pendingWait)
    progressBar:SetWidth(math.max(1, math.floor(width * pct)))
  end)

  -- Legende (nom de l'image courante), bas-gauche, italique -- meme niveau
  -- que les miniatures cote droit.
  local caption = container:CreateFontString(nil, "OVERLAY")
  caption:SetFont(CAROUSEL_CAPTION_FONT, 10, "")
  caption:SetTextColor(unpack(CAROUSEL_GOLD))
  caption:SetJustifyH("LEFT")
  caption:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
  caption:SetPoint("TOP", container, "TOP", 0, -(height + 6))

  local thumbs = {}
  local current = 1
  local n = #images

  -- Pas de defilement auto avec 0-1 image : pas de barre de progression non
  -- plus (rien a "attendre").
  if n <= 1 then
    progressTrack:Hide()
    progressBar:Hide()
    mainFrame:SetScript("OnUpdate", nil)
  end

  local function ShowSlide(idx)
    if n == 0 then return end
    idx = ((idx - 1) % n) + 1
    current = idx
    slideStartTime = GetTime()
    tex:SetTexture(images[idx].texture)
    caption:SetText(images[idx].tooltip or "")
    -- Carre plein = miniature active, vide = inactive (thFill/thHole, memes couleurs, remplissage different).
    for i, t in ipairs(thumbs) do
      t.fill:SetShown(i == idx)
    end
  end

  -- Miniatures alignees sous le coin BAS-DROIT du cadre (pas centrees).
  local totalW = n * THUMB + math.max(0, n - 1) * GAP
  local startX = width - totalW
  for i, img in ipairs(images) do
    local th = CreateFrame("Button", nil, container)
    th:SetSize(THUMB, THUMB)
    th:SetPoint("TOPLEFT", container, "TOPLEFT", startX + (i - 1) * (THUMB + GAP), -(height + 6))
    -- 3 calques dans cet ordre (peignent par-dessus) : BACKGROUND = disque
    -- dore plein (anneau visible), BORDER = disque noir plus petit (creuse
    -- le trou = rond vide), ARTWORK = disque dore cache par defaut (rebouche
    -- le trou pour la miniature active).
    local DOT_TEX = "Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2"
    local thGoldBg = th:CreateTexture(nil, "BACKGROUND")
    thGoldBg:SetAllPoints()
    thGoldBg:SetTexture(DOT_TEX)
    thGoldBg:SetVertexColor(unpack(CAROUSEL_GOLD))
    local thHole = th:CreateTexture(nil, "BORDER")
    thHole:SetPoint("TOPLEFT", 2, -2)
    thHole:SetPoint("BOTTOMRIGHT", -2, 2)
    thHole:SetTexture(DOT_TEX)
    thHole:SetVertexColor(0.05, 0.05, 0.06, 1)
    local thFill = th:CreateTexture(nil, "ARTWORK")
    thFill:SetPoint("TOPLEFT", 2, -2)
    thFill:SetPoint("BOTTOMRIGHT", -2, 2)
    thFill:SetTexture(DOT_TEX)
    thFill:SetVertexColor(unpack(CAROUSEL_GOLD))
    thFill:Hide()
    th:SetScript("OnClick", function()
      pendingWait = 10 -- pause plus longue qu'un defilement auto normal
      ShowSlide(i)
    end)
    if img.tooltip then
      th:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetText(img.tooltip, 1, 1, 1)
        GameTooltip:Show()
      end)
      th:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    thumbs[i] = { fill = thFill }
  end

  if n > 0 then ShowSlide(1) end

  -- Poll rapide (0.1s) : verifie si pendingWait est ecoule depuis le dernier
  -- slide, reste synchro avec la barre de progression. Annule sur OnHide
  -- pour ne pas tourner indefiniment en arriere-plan.
  if n > 1 then
    local ticker = ns.NewTicker(0.1, function()
      if GetTime() - slideStartTime >= pendingWait then
        pendingWait = autoInterval
        ShowSlide(current + 1)
      end
    end)
    container:SetScript("OnHide", function() ticker:Cancel() end)
  end

  container.ShowSlide = ShowSlide
  return container
end

-- Menu contextuel generique, affiche au curseur. Un seul frame reutilise pour tout l'addon :
-- ouvrir un menu ferme automatiquement le precedent.
-- items = { { label = "...", onClick = function() end, disabled = bool, color = {r,g,b},
--             separator = true }, ... }
-- EasyMenu n'est pas utilise (deprecie), meme choix que le menu de tags du selecteur de modeles.
local contextMenuFrame
function SharedWidgets.ShowContextMenu(items)
  if type(items) ~= "table" or #items == 0 then return end

  if not contextMenuFrame then
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")

    -- Fond et bordure poses en TEXTURES plutot que via SetBackdrop : selon le client, le backdrop
    -- peut ne rien dessiner du tout, et le menu devient alors illisible par transparence.
    -- Des textures unies fonctionnent partout et ne dependent d'aucun template.
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints(f)
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.97)
    f._solidBg = bg

    -- Bordure : quatre traits fins, insensibles a l'absence de backdrop.
    local function EdgeTex()
      local t = f:CreateTexture(nil, "BORDER")
      t:SetColorTexture(0.32, 0.32, 0.38, 1)
      return t
    end
    local eTop, eBottom, eLeft, eRight = EdgeTex(), EdgeTex(), EdgeTex(), EdgeTex()
    eTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    eTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    eTop:SetHeight(1)
    eBottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    eBottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    eBottom:SetHeight(1)
    eLeft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    eLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    eLeft:SetWidth(1)
    eRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    eRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    eRight:SetWidth(1)

    f:EnableMouse(true)
    f:Hide()
    f._rows = {}

    -- Lueur diffuse derriere le menu : il se detache du fond du panneau, souvent tres charge.
    -- Texture de glow doux etiree au-dela des bords, en BACKGROUND pour rester sous le fond opaque
    -- du menu -- seul le halo deborde.
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetTexture("Interface\\Cooldown\\star4")
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", -26, 26)
    glow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 26, -26)
    f._glowTex = glow
    -- Fermeture des que l'on clique en dehors.
    f:SetScript("OnShow", function(self)
      self:SetScript("OnUpdate", function(sf)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
           and not ns.IsFrameMouseOver(sf) then
          sf:Hide()
        end
      end)
    end)
    f:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    contextMenuFrame = f
  end

  local f = contextMenuFrame
  f:Hide()
  for _, r in ipairs(f._rows) do r:Hide() end

  -- Nuance "Lueur" de la spe active, relue a chaque ouverture : elle suit un changement de spe
  -- ou de couleurs sans qu'il faille recreer le menu. Repli discret si le module est absent.
  if f._glowTex then
    local CLR = ns.Modules and ns.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get("glow")
    if c then
      f._glowTex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, 0.30)
    else
      f._glowTex:SetVertexColor(1, 0.85, 0, 0.22)
    end
  end

  local ROW_H, PAD, W = 18, 5, 190
  local y = -PAD
  for i, item in ipairs(items) do
    local r = f._rows[i]
    if not r then
      r = CreateFrame("Button", nil, f)
      local bg = r:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0)
      r._bg = bg
      local lbl = r:CreateFontString(nil, "OVERLAY")
      lbl:SetFont(ns.Media.fontGui, 10)
      lbl:SetPoint("LEFT", r, "LEFT", 6, 0)
      lbl:SetJustifyH("LEFT")
      r._lbl = lbl
      f._rows[i] = r
    end
    r:SetSize(W - PAD * 2, item.separator and 6 or ROW_H)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    r._lbl:SetText(item.separator and "" or (item.label or ""))
    if item.separator then
      r._bg:SetColorTexture(1, 1, 1, 0.10)
      r:SetScript("OnEnter", nil); r:SetScript("OnLeave", nil); r:SetScript("OnClick", nil)
      r:EnableMouse(false)
      y = y - 6
    else
      r:EnableMouse(true)
      r._bg:SetColorTexture(0, 0, 0, 0)
      local c = item.color
      if item.disabled then
        r._lbl:SetTextColor(0.45, 0.45, 0.45)
      elseif c then
        r._lbl:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1)
      else
        r._lbl:SetTextColor(unpack(Theme.textNormal))
      end
      if item.disabled then
        r:SetScript("OnEnter", nil); r:SetScript("OnLeave", nil); r:SetScript("OnClick", nil)
      else
        r:SetScript("OnEnter", function(self) self._bg:SetColorTexture(1, 1, 1, 0.08) end)
        r:SetScript("OnLeave", function(self) self._bg:SetColorTexture(0, 0, 0, 0) end)
        r:SetScript("OnClick", function()
          f:Hide()
          if item.onClick then item.onClick() end
        end)
      end
      y = y - ROW_H
    end
    r:Show()
  end

  f:SetSize(W, math.abs(y) + PAD)
  -- Positionnement au curseur, en coordonnees UIParent.
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
  f:Show()
end

function SharedWidgets.HideContextMenu()
  if contextMenuFrame then contextMenuFrame:Hide() end
end

-- Page du GUI abandonnée (invalidée puis reconstruite) : WoW ne libère jamais une frame, mais on
-- rend au GC les closures de ses scripts et de ses callbacks internes, et on coupe ses événements.
-- Sans ça, chaque reconstruction de page gardait l'ancienne en mémoire jusqu'au /reload.
local RELEASE_SCRIPTS = {
  "OnClick", "OnDoubleClick", "OnEnter", "OnLeave", "OnShow", "OnHide", "OnUpdate", "OnEvent",
  "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnValueChanged", "OnTextChanged", "OnChar",
  "OnEditFocusGained", "OnEditFocusLost", "OnEnterPressed", "OnEscapePressed", "OnTabPressed",
  "OnKeyDown", "OnKeyUp", "OnSizeChanged", "OnDragStart", "OnDragStop", "OnReceiveDrag",
  "OnVerticalScroll", "OnScrollRangeChanged", "OnCursorChanged",
}

local function ReleaseTree(f)
  for _, s in ipairs(RELEASE_SCRIPTS) do
    if f:HasScript(s) and f:GetScript(s) then pcall(f.SetScript, f, s, nil) end
  end
  if f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
  for _, child in ipairs({ f:GetChildren() }) do ReleaseTree(child) end
end

local function NoOp() end

-- entry = { frame, callbacks } d'un categoryContainer (cf. GetOrBuildContainer)
function SharedWidgets.ReleasePage(entry)
  if not entry then return end
  if entry.frame then
    entry.frame:Hide()
    pcall(ReleaseTree, entry.frame)
  end
  -- Neutralisés sur place (pas retirés) : la liste peut être en cours de parcours par Trigger
  for _, cb in ipairs(entry.callbacks or {}) do
    cb.func, cb.owner = NoOp, nil
  end
  entry.callbacks = nil
end

-- Exécute fn(...) en relevant les callbacks enregistrés pendant l'appel. Retourne la liste des
-- entrées de ns.CallbackRegistry créées, puis les retours de fn (pcall).
function SharedWidgets.TrackCallbacks(fn, ...)
  local CR = ns.CallbackRegistry
  local orig = CR.Register
  local created = {}
  CR.Register = function(self, event, func, owner)
    orig(self, event, func, owner)
    local list = self.events[event]
    created[#created + 1] = list[#list]
  end
  local res = { pcall(fn, ...) }
  CR.Register = orig
  return created, unpack(res)
end

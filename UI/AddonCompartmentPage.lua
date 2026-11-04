-- UI/AddonCompartmentPage.lua : page "Compartiment d'addons" du GUI (logique : Modules/AddonCompartment.lua).
-- La liste reste ouverte pres de la minimap tant que la page est affichee : chaque reglage s'y voit en direct.
local addonName, ns = ...
local L  = ns.L
local SW = ns.SharedWidgets

function ns.BuildAddonCompartmentPage(container, W, NewLayout)
  local AC = ns.Modules and ns.Modules.AddonCompartment
  local ctx = NewLayout(container)
  local W2 = math.floor((W - 8) / 2)

  local function DB()
    ns.DB = ns.DB or {}
    ns.DB.addonCompartment = ns.DB.addonCompartment or {}
    return ns.DB.addonCompartment
  end

  -- Changement de reglage : une application par frame
  local pending = false
  local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      if not AC then return end
      AC.ApplySettings()
      if container:IsVisible() then AC.SetPreview(true) end
    end)
  end

  local bound = {}
  local function Bind(w, key, kind)
    bound[#bound + 1] = { w = w, key = key, kind = kind }
    w._subKey = key   -- cases maitresses / themees (cf. NewLayout), sans changer l'identifiant du mode disposition
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      DB()[key] = v
      Changed()
    end
    return w
  end

  -- Couleur + case "Couleurs thematiques" : le selecteur est grise tant que la case est cochee
  local themedPairs = {}
  local function ThemedRow(label, key, themedKey, element)
    local col = Bind(SW.CreateColorButton(container, label, W2), key, "color")
    local tt = string.format(L["MENUBAR_THEMED_TT"], L[element])
    local cb = Bind(SW.CreateCheckbox(container, L["MENUBAR_THEMED"], tt, W2), themedKey, "bool")
    -- Couleur sans effet tant que les Couleurs thematiques sont actives : grisee et inerte (grisage commun, qui tient
    -- aux fondus du pli des sections)
    local function State(on) SW.SetGrayReason(col, "spec", on and true or false) end
    local orig = cb.onChanged
    cb.onChanged = function(v)
      if orig then orig(v) end
      State(v and true or false)
    end
    themedPairs[#themedPairs + 1] = { State = State, key = themedKey }
    return col, cb
  end

  local bgOpts = {}
  for _, d in ipairs(AC and AC.BG_TEXTURES or {}) do
    -- Textures des Barres dynamiques : leurs libelles ; les autres : libelles propres au module
    local prefix = d.nine and "EXTRABARS_BG_TEX_" or "ADDONCOMP_BG_TEX_"
    bgOpts[#bgOpts + 1] = { value = d.value, text = L[prefix .. d.value:upper()] }
  end

  local anchors = {}
  for _, p in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
    anchors[#anchors + 1] = { value = p, text = L["SETTINGS_ANCHOR_" .. p] }
  end

  -- Page ---------------------------------------------------------------------------------------------
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_ADDON_COMPARTMENT"], W))
  local cbEnable = ctx:TitleToggle(Bind(SW.CreateCheckbox(container, L["ADDONCOMP_ENABLE"], L["SETTINGS_CAT_ADDON_COMPARTMENT_TT"], W2), "enabled", "bool"))
  local replay = SW.CreateActionBtn(container, L["ADDONCOMP_REPLAY"], W2)
  replay:SetScript("OnClick", function() if AC then AC.Replay() end end)
  ctx:Add(replay)

  -- Position
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["ADDONCOMP_SEC_POSITION"], W))
  local ddAnchor = Bind(SW.CreateDropdown(container, L["ADDONCOMP_ANCHOR"], anchors, W2), "point", "string")
  local slSize = Bind(SW.CreateSlider(container, L["ADDONCOMP_BTN_SIZE"], 12, 64, 1, W2), "size", "number")
  ctx:AddRow(8, ddAnchor, slSize)
  local slX = Bind(SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -150, 150, 1, W2), "x", "number")
  local slY = Bind(SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -150, 150, 1, W2), "y", "number")
  ctx:AddRow(8, slX, slY)

  -- Bouton
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["ADDONCOMP_SEC_BUTTON"], W))
  local ddBtnTex = Bind(SW.CreateDropdown(container, L["EXTRABARS_BG_TEXTURE"], bgOpts, W2), "btnTexture", "string")
  local colBtn = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_COLOR"], W2), "btnColor", "color")
  ctx:AddRow(8, ddBtnTex, colBtn)
  local slBtnBorder = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_BORDER_SIZE"], 0, 6, 1, W2), "btnBorderSize", "number")
  local colBtnBorder = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_BORDER_COLOR"], W2), "btnBorderColor", "color")
  ctx:AddRowCentered(8, slBtnBorder, colBtnBorder)
  local ddFont = Bind(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), W2), "font", "string")
  local ddOutline = Bind(SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), W2), "outline", "string")
  ctx:AddRow(8, ddFont, ddOutline)
  ctx:Add(Bind(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 8, 32, 1, W2), "fontSize", "number"))
  local colText, cbTextThemed = ThemedRow(L["SETTINGS_TEXT_COLOR"], "textColor", "textThemed", "COLORSMOD_ELEM_POWERCIRCLE")
  ctx:AddRowCentered(8, colText, cbTextThemed)

  -- Liste des addons
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["ADDONCOMP_SEC_LIST"], W))
  local ddOpen = Bind(SW.CreateDropdown(container, L["ADDONCOMP_OPEN_MODE"], {
    { value = "click", text = L["ADDONCOMP_OPEN_CLICK"] },
    { value = "hover", text = L["ADDONCOMP_OPEN_HOVER"] },
  }, W2), "openMode", "string")
  local ddDir = Bind(SW.CreateDropdown(container, L["ADDONCOMP_DIRECTION"], {
    { value = "auto",  text = L["ADDONCOMP_DIR_AUTO"] },
    { value = "down",  text = L["ADDONCOMP_DIR_DOWN"] },
    { value = "up",    text = L["ADDONCOMP_DIR_UP"] },
    { value = "left",  text = L["ADDONCOMP_DIR_LEFT"] },
    { value = "right", text = L["ADDONCOMP_DIR_RIGHT"] },
  }, W2), "direction", "string")
  ctx:AddRow(8, ddOpen, ddDir)
  local ddLayout = Bind(SW.CreateDropdown(container, L["ADDONCOMP_LAYOUT"], {
    { value = "grid", text = L["ADDONCOMP_LAYOUT_GRID"] },
    { value = "list", text = L["ADDONCOMP_LAYOUT_LIST"] },
  }, W2), "layout", "string")
  local slGap = Bind(SW.CreateSlider(container, L["ADDONCOMP_GAP"], 0, 40, 1, W2), "gap", "number")
  ctx:AddRow(8, ddLayout, slGap)
  local slCols = Bind(SW.CreateSlider(container, L["ADDONCOMP_COLUMNS"], 1, 12, 1, W2), "columns", "number")
  local slListCols = Bind(SW.CreateSlider(container, L["ADDONCOMP_LIST_COLUMNS"], 1, 4, 1, W2), "listColumns", "number")
  ctx:AddRow(8, slCols, slListCols)
  local slIcon = Bind(SW.CreateSlider(container, L["ADDONCOMP_ICON_SIZE"], 12, 48, 1, W2), "iconSize", "number")
  local slSpacing = Bind(SW.CreateSlider(container, L["ADDONCOMP_SPACING"], 0, 20, 1, W2), "spacing", "number")
  ctx:AddRow(8, slIcon, slSpacing)
  local ddListFont = Bind(SW.CreateDropdown(container, L["ADDONCOMP_LIST_FONT"], ns.GetFontList(), W2), "listFont", "string")
  local slListFont = Bind(SW.CreateSlider(container, L["ADDONCOMP_LIST_FONT_SIZE"], 8, 24, 1, W2), "listFontSize", "number")
  local colList = Bind(SW.CreateColorButton(container, L["ADDONCOMP_LIST_COLOR"], W2), "listColor", "color")
  ctx:AddRowCentered(8, ddListFont, slListFont, colList)
  local colHover, cbHoverThemed = ThemedRow(L["MENUBAR_HOVER_COLOR"], "hoverColor", "hoverThemed", "COLORSMOD_ELEM_POWERDOTSB")
  ctx:AddRowCentered(8, colHover, cbHoverThemed)
  ctx:Add(Bind(SW.CreateCheckbox(container, L["ADDONCOMP_ANIMATE"], nil, W), "animate", "bool"))

  -- Arriere-plan de la liste
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_BACKGROUND"], W))
  local ddBgTex = Bind(SW.CreateDropdown(container, L["EXTRABARS_BG_TEXTURE"], bgOpts, W2), "bgTexture", "string")
  local colBg = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_COLOR"], W2), "bgColor", "color")
  ctx:AddRow(8, ddBgTex, colBg)
  local slPadX = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_PAD_X"], 0, 60, 1, W2), "bgPadX", "number")
  local slPadY = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_PAD_Y"], 0, 60, 1, W2), "bgPadY", "number")
  ctx:AddRow(8, slPadX, slPadY)
  local slEdge = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_EDGE"], 0, 64, 1, W2), "bgEdge", "number")
  local slBgBorder = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_BORDER_SIZE"], 0, 6, 1, W2), "bgBorderSize", "number")
  ctx:AddRow(8, slEdge, slBgBorder)
  ctx:Add(Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_BORDER_COLOR"], W2), "bgBorderColor", "color"))

  -- Addons supportes : un interrupteur (affiche dans la liste) et une etoile (favori, pose sur la minimap) par addon
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["ADDONCOMP_SEC_SUPPORTED"], W))
  local supported = CreateFrame("Frame", nil, container)
  supported:SetSize(W, 20)
  local rowsPool = {}
  local ROW_H = 24
  local STAR = "Interface\\Common\\ReputationStar"

  local function PaintRow(row)
    local on = not AC.IsHidden(row.key)
    local fav = AC.IsFavorite(row.key)
    row.toggle:SetValue(on)
    row.label:SetTextColor(on and 0.92 or 0.5, on and 0.88 or 0.5, on and 0.80 or 0.5, 1)
    row.icon:SetDesaturated(not on)
    row.star.tex:SetDesaturated(not fav)
    row.star.tex:SetAlpha(fav and 1 or 0.35)
  end

  local function NewRow()
    local row = CreateFrame("Frame", nil, supported)
    row:SetSize(W2, ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.03)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.toggle = SW.CreateToggle(row, 40)
    row.toggle:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.star = CreateFrame("Button", nil, row)
    row.star:SetSize(18, 18)
    row.star:SetPoint("RIGHT", row.toggle, "LEFT", -6, 0)
    row.star.tex = row.star:CreateTexture(nil, "ARTWORK")
    row.star.tex:SetAllPoints()
    row.star.tex:SetTexture(STAR)
    row.star.tex:SetTexCoord(0, 0.5, 0, 0.5)
    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFont(ns.Media.fontGui, 11)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row.star, "LEFT", -6, 0)
    row.toggle.onChanged = function(v)
      AC.SetHidden(row.key, not v)
      PaintRow(row)
      Changed()
    end
    row.star:SetScript("OnClick", function()
      AC.SetFavorite(row.key, not AC.IsFavorite(row.key))
      PaintRow(row)
      Changed()
    end)
    row.star:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["ADDONCOMP_FAVORITE"], 1, 1, 1)
      GameTooltip:AddLine(L["ADDONCOMP_FAVORITE_TT"], 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    row.star:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowsPool[#rowsPool + 1] = row
    return row
  end

  local emptyFs = supported:CreateFontString(nil, "OVERLAY")
  emptyFs:SetFont(ns.Media.fontGui, 11)
  emptyFs:SetTextColor(0.6, 0.6, 0.6, 1)
  emptyFs:SetPoint("TOPLEFT", supported, "TOPLEFT", 4, -4)
  emptyFs:SetText(L["ADDONCOMP_SUPPORTED_EMPTY"])

  local function RebuildSupported()
    local entries = AC and AC.GetEntries() or {}
    for i, e in ipairs(entries) do
      local row = rowsPool[i] or NewRow()
      row.key = e.key
      row.label:SetText(e.label)
      AC.CopyIcon(row.icon, e.rec)
      local c, r = (i - 1) % 2, math.floor((i - 1) / 2)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", supported, "TOPLEFT", c * (W2 + 8), -r * (ROW_H + 2))
      PaintRow(row)
      row:Show()
    end
    for i = #entries + 1, #rowsPool do rowsPool[i]:Hide() end
    emptyFs:SetShown(#entries == 0)
    local h = math.max(20, math.ceil(#entries / 2) * (ROW_H + 2))
    if h ~= supported:GetHeight() then
      supported:SetHeight(h)
      if ctx.Relayout then ctx:Relayout() end
    end
  end
  ctx:Add(supported)

  -- Addons favoris : grille de leurs icones sur la minimap
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["ADDONCOMP_SEC_FAVORITES"], W))
  local ddFavAnchor = Bind(SW.CreateDropdown(container, L["ADDONCOMP_ANCHOR"], anchors, W2), "favPoint", "string")
  local slFavSize = Bind(SW.CreateSlider(container, L["ADDONCOMP_ICON_SIZE"], 12, 48, 1, W2), "favIconSize", "number")
  ctx:AddRow(8, ddFavAnchor, slFavSize)
  local slFavCols = Bind(SW.CreateSlider(container, L["ADDONCOMP_FAV_COLUMNS"], 1, 12, 1, W2), "favColumns", "number")
  local slFavRows = Bind(SW.CreateSlider(container, L["ADDONCOMP_FAV_ROWS"], 1, 12, 1, W2), "favRows", "number")
  ctx:AddRow(8, slFavCols, slFavRows)
  local slFavX = Bind(SW.CreateSlider(container, L["SETTINGS_OFFSET_X"], -150, 150, 1, W2), "favX", "number")
  local slFavY = Bind(SW.CreateSlider(container, L["SETTINGS_OFFSET_Y"], -150, 150, 1, W2), "favY", "number")
  ctx:AddRow(8, slFavX, slFavY)
  local slFavAlpha = Bind(SW.CreateSlider(container, L["ADDONCOMP_FAV_ALPHA"], 0, 1, 0.05, W2), "favAlpha", "number")
  local slFavHover = Bind(SW.CreateSlider(container, L["ADDONCOMP_FAV_HOVER_ALPHA"], 0, 1, 0.05, W2), "favHoverAlpha", "number")
  ctx:AddRow(8, slFavAlpha, slFavHover)
  ctx:Add(Bind(SW.CreateSlider(container, L["ADDONCOMP_SPACING"], 0, 20, 1, W2), "favSpacing", "number"))

  -- Fond des favoris (meme section) : grille entiere, puis chaque icone ; sous-titre deplacable en mode disposition
  ctx:Spacer(6)
  do
    local sub = SW.CreateSectionHeader(container, L["ADDONCOMP_SEC_FAV_BG"], W)
    sub._isSectionHeader = nil
    sub._leKind, sub._leText = "subheader", L["ADDONCOMP_SEC_FAV_BG"]
    ctx:Add(sub)
  end
  local ddFavBg = Bind(SW.CreateDropdown(container, L["ADDONCOMP_FAV_GRID_BG"], bgOpts, W2), "favBgTexture", "string")
  local colFavBg = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_COLOR"], W2), "favBgColor", "color")
  ctx:AddRow(8, ddFavBg, colFavBg)
  local slFavPadX = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_PAD_X"], 0, 40, 1, W2), "favBgPadX", "number")
  local slFavPadY = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_PAD_Y"], 0, 40, 1, W2), "favBgPadY", "number")
  ctx:AddRow(8, slFavPadX, slFavPadY)
  local slFavEdge = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_EDGE"], 0, 64, 1, W2), "favBgEdge", "number")
  local slFavBorder = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_BORDER_SIZE"], 0, 6, 1, W2), "favBgBorderSize", "number")
  ctx:AddRow(8, slFavEdge, slFavBorder)
  ctx:Add(Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_BORDER_COLOR"], W2), "favBgBorderColor", "color"))
  ctx:Spacer(6)
  local ddIconBg = Bind(SW.CreateDropdown(container, L["ADDONCOMP_FAV_ICON_BG"], bgOpts, W2), "favIconBgTexture", "string")
  local colIconBg = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_COLOR"], W2), "favIconBgColor", "color")
  ctx:AddRow(8, ddIconBg, colIconBg)
  local slIconPad = Bind(SW.CreateSlider(container, L["ADDONCOMP_FAV_ICON_PAD"], 0, 16, 1, W2), "favIconBgPad", "number")
  local slIconBorder = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_BORDER_SIZE"], 0, 6, 1, W2), "favIconBgBorderSize", "number")
  ctx:AddRow(8, slIconPad, slIconBorder)
  ctx:Add(Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_BORDER_COLOR"], W2), "favIconBgBorderColor", "color"))

  ctx:Spacer()
  ctx:Finalize()

  -- Relecture des valeurs depuis la DB (ou des defauts)
  local function RefreshAll()
    local cfg = ns.GetCfg("addonCompartment") or {}
    for _, e in ipairs(bound) do
      local v = cfg[e.key]
      if e.kind == "bool" then
        if e.w.SetChecked then e.w:SetChecked(v and true or false) else e.w:SetValue(v and true or false) end
      elseif e.kind == "color" then
        if type(v) == "table" then e.w:SetColor(v[1], v[2], v[3], v[4]) end
      elseif v ~= nil then
        e.w:SetValue(v)
      end
    end
    for _, t in ipairs(themedPairs) do t.State(cfg[t.key] ~= false) end
  end
  container:HookScript("OnShow", function()
    RefreshAll()
    if AC then
      AC.SetPreview(true)
      -- Les boutons des addons sont ranges un peu apres l'ouverture (scan) : liste relue ensuite
      RebuildSupported()
      C_Timer.After(0.1, RebuildSupported)
    end
  end)
  container:HookScript("OnHide", function()
    if AC then AC.SetPreview(false) end
  end)
  RefreshAll()
  if AC then RebuildSupported() end
  if container:IsVisible() and AC then AC.SetPreview(true) end
end

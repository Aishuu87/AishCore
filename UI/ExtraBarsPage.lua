-- UI/ExtraBarsPage.lua : page "Extra Barres" du GUI (logique : Modules/ExtraBars.lua).
-- Sélecteur de barre + interrupteur, aperçu, tags à cocher, puis sections repliables (NewLayout).
-- Tous les réglages pointent sur la barre sélectionnée : changer de barre relit les valeurs sans
-- reconstruire la page.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local PREVIEW_H = 130
local PREVIEW_MIN = 5            -- au moins 5 boutons dans l'aperçu, pour régler taille / disposition
local PLACEHOLDER_ICON = 134400
local FAKE_STACKS = { [1] = "3", [3] = "12", [4] = "5" }  -- piles fictives de l'aperçu
local FAKE_CD_INDEX = 2                                    -- bouton de l'aperçu en temps de recharge

local function Gold() return Theme.accentText or Theme.gold or Theme.accent end

-- Pastille de tag cliquable (dorée quand cochée)
local function NewPill(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, 24)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b.fs = b:CreateFontString(nil, "OVERLAY")
  b.fs:SetFont(ns.Media.fontGui, 10)
  b.fs:SetPoint("LEFT", 6, 0)
  b.fs:SetPoint("RIGHT", -6, 0)
  b.fs:SetText(text)
  function b:SetActive(on)
    self.on = on
    local g = Gold()
    if on then
      self:SetBackdropColor(g[1] * 0.35, g[2] * 0.35, g[3] * 0.25, 1)
      self:SetBackdropBorderColor(g[1], g[2], g[3], 1)
      self.fs:SetTextColor(g[1], g[2], g[3])
    else
      self:SetBackdropColor(0.06, 0.06, 0.07, 1)
      self:SetBackdropBorderColor(unpack(Theme.border))
      self.fs:SetTextColor(unpack(Theme.textDim))
    end
  end
  b:SetScript("OnEnter", function(self) if not self.on then self.fs:SetTextColor(unpack(Theme.textNormal)) end end)
  b:SetScript("OnLeave", function(self) self:SetActive(self.on) end)
  return b
end

local POINT_OPTIONS
local function PointOptions()
  POINT_OPTIONS = POINT_OPTIONS or {
    { value = "TOPLEFT",     text = L["EXTRABARS_CORNER_TOPLEFT"] },
    { value = "TOPRIGHT",    text = L["EXTRABARS_CORNER_TOPRIGHT"] },
    { value = "BOTTOMLEFT",  text = L["EXTRABARS_CORNER_BOTTOMLEFT"] },
    { value = "BOTTOMRIGHT", text = L["EXTRABARS_CORNER_BOTTOMRIGHT"] },
    { value = "CENTER",      text = L["EXTRABARS_CENTER"] },
  }
  return POINT_OPTIONS
end

function ns.BuildExtraBarsPage(container, W, NewLayout)
  local EB = ns.Modules and ns.Modules.ExtraBars
  local ctx = NewLayout(container)
  local W2 = math.floor((W - 8) / 2)
  ns._extraBarsSelected = ns._extraBarsSelected or 1

  local function Bar() return EB and EB.BarCfg(ns._extraBarsSelected) end

  -- Liaisons widget <-> clé de la barre sélectionnée
  local bound = {}
  local RefreshAll, RefreshPreview, RefreshBlacklist
  -- Regroupé à une seule application par frame : un slider qu'on tire envoie une valeur
  -- par mouvement de souris. `full` = noms de barres / widgets à resynchroniser (tags, copie).
  local pending, pendingFull = false, false
  local function Changed(full)
    pendingFull = pendingFull or full == true
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      if EB then EB.ApplySettings() end
      if pendingFull then RefreshAll() else RefreshPreview(Bar()) end
      pendingFull = false
    end)
  end
  local function Bind(w, key, kind)
    bound[#bound + 1] = { w = w, key = key, kind = kind }
    w.onChanged = function(v)
      local bc = Bar()
      if not bc then return end
      if kind == "number" then v = tonumber(v) or v end
      bc[key] = v
      Changed()
    end
    return w
  end

  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_EXTRA_BARS"], W))

  -- Sélecteur de barre (centré) + interrupteur de la barre ------------------------------------------
  local top = CreateFrame("Frame", nil, container)
  top:SetSize(W, 26)
  local barDD = SW.CreateDropdown(top, "", {}, 420)
  barDD:SetPoint("CENTER", top, "CENTER", -32, 0)
  local toggle = SW.CreateToggle(top, 54)
  toggle:SetPoint("LEFT", barDD, "RIGHT", 12, 0)
  barDD.onChanged = function(v) ns._extraBarsSelected = tonumber(v) or 1; RefreshAll() end
  Bind(toggle, "enabled", "bool")
  ctx:Spacer(4)
  ctx:Add(top)

  -- Aperçu ---------------------------------------------------------------------------------------
  ctx:Spacer(8)
  local preview = CreateFrame("Frame", nil, container, "BackdropTemplate")
  preview:SetSize(W, PREVIEW_H)
  preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  preview:SetBackdropColor(0.02, 0.02, 0.025, 0.9)
  preview:SetBackdropBorderColor(unpack(Theme.border))
  preview:SetClipsChildren(true)
  local grid = CreateFrame("Frame", nil, preview)
  -- Rappel des tags suivis, en bas à gauche de l'encart
  local tagsText = preview:CreateFontString(nil, "OVERLAY")
  tagsText:SetFont(ns.Media.fontGui, 10)
  tagsText:SetTextColor(unpack(Theme.textDim))
  tagsText:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 8, 6)
  tagsText:SetPoint("RIGHT", preview, "RIGHT", -8, 0)
  tagsText:SetJustifyH("LEFT")
  tagsText:SetWordWrap(false)
  local previewButtons = {}
  ctx:Add(preview)

  -- Placement des barres + copie des réglages
  ctx:Spacer(8)
  local dragBtn = SW.CreateActionBtn(container, L["EXTRABARS_MOVE"], W2)
  local function RefreshDragBtn()
    dragBtn._lbl:SetText(EB and EB.IsDragUnlocked() and L["EXTRABARS_LOCK"] or L["EXTRABARS_MOVE"])
  end
  dragBtn:SetScript("OnClick", function()
    if EB then EB.SetDragUnlocked(not EB.IsDragUnlocked()) end
    RefreshDragBtn()
  end)
  container:HookScript("OnHide", function()
    if EB and EB.IsDragUnlocked() then EB.SetDragUnlocked(false); RefreshDragBtn() end
  end)
  local copyBtn = SW.CreateActionBtn(container, L["EXTRABARS_COPY_TO"], W2)
  copyBtn:SetScript("OnClick", function()
    if not EB then return end
    local from = ns._extraBarsSelected
    local function CopyTo(targets)
      for _, to in ipairs(targets) do EB.CopySettings(from, to) end
      print("|cff00ccff[AishCore]|r " .. L["EXTRABARS_COPIED"])
      Changed(true)
    end
    local items, all = {}, {}
    for i = 1, EB.NUM_BARS do
      if i ~= from then
        all[#all + 1] = i
        items[#items + 1] = { label = EB.BarName(i, EB.BarCfg(i)), onClick = function() CopyTo({ i }) end }
      end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = L["EXTRABARS_COPY_ALL"], onClick = function() CopyTo(all) end }
    SW.ShowContextMenu(items)
  end)
  -- Ce qui est copié : au survol seulement, pour ne pas charger la page
  copyBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["EXTRABARS_COPY_HINT"], 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  copyBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  ctx:AddRow(8, dragBtn, copyBtn)

  -- Tags -----------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_TAGS"], W))
  local PER_ROW, GAP = 5, 6
  local tags = EB and EB.TAGS or {}
  local pillW = math.floor((W - (PER_ROW - 1) * GAP) / PER_ROW)
  local tagBox = CreateFrame("Frame", nil, container)
  tagBox:SetSize(W, math.ceil(#tags / PER_ROW) * (24 + GAP))
  local pills = {}
  for i, tag in ipairs(tags) do
    local pill = NewPill(tagBox, L["EXTRABARS_TAG_" .. tag:upper()], pillW)
    local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
    pill:SetPoint("TOPLEFT", tagBox, "TOPLEFT", col * (pillW + GAP), -row * (24 + GAP))
    pill:SetScript("OnClick", function(self)
      local bc = Bar()
      if not bc then return end
      bc.tags = bc.tags or {}
      -- false explicite (pas nil) : sinon MergeDefaults réactiverait un tag décoché par défaut
      bc.tags[tag] = not self.on
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      Changed(true)
    end)
    pill.tag = tag
    pills[#pills + 1] = pill
  end
  ctx:Add(tagBox)

  -- Blacklist ------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_BLACKLIST"], W))
  local blHint = container:CreateFontString(nil, "OVERLAY")
  blHint:SetFont(ns.Media.fontGui, 10)
  blHint:SetTextColor(0.55, 0.55, 0.55, 1)
  blHint:SetJustifyH("LEFT")
  blHint:SetWordWrap(true)
  blHint:SetSize(W - 10, 28)
  blHint:SetText(L["EXTRABARS_BL_HINT"])
  ctx:Add(blHint)

  local blRow = CreateFrame("Frame", nil, container)
  blRow:SetSize(W, 24)
  local blInput = CreateFrame("EditBox", nil, blRow, "InputBoxTemplate")
  SW.StyleEditBox(blInput)
  blInput:SetSize(W - 126, 20)
  blInput:SetPoint("LEFT", blRow, "LEFT", 6, 0)
  blInput:SetAutoFocus(false)
  local blAdd = SW.CreateActionBtn(blRow, L["EXTRABARS_BL_ADD"], 110)
  blAdd:SetPoint("RIGHT", blRow, "RIGHT", 0, 0)
  ctx:Add(blRow)

  local BL_PER_ROW, BL_H = 3, 24
  local blChipW = math.floor((W - (BL_PER_ROW - 1) * GAP) / BL_PER_ROW)
  local blList = CreateFrame("Frame", nil, container)
  blList:SetSize(W, BL_H)
  local blEmpty = blList:CreateFontString(nil, "OVERLAY")
  blEmpty:SetFont(ns.Media.fontGui, 10)
  blEmpty:SetTextColor(0.55, 0.55, 0.55, 1)
  blEmpty:SetPoint("LEFT", blList, "LEFT", 6, 0)
  blEmpty:SetText(L["EXTRABARS_BL_EMPTY"])
  ctx:Add(blList)

  local blChips = {}
  local function NewChip()
    local chip = NewPill(blList, "", blChipW)
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(16, 16)
    chip.icon:SetPoint("LEFT", chip, "LEFT", 4, 0)
    chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    chip.fs:ClearAllPoints()
    chip.fs:SetPoint("LEFT", chip.icon, "RIGHT", 5, 0)
    chip.fs:SetPoint("RIGHT", chip, "RIGHT", -6, 0)
    chip.fs:SetJustifyH("LEFT")
    chip.fs:SetWordWrap(false)
    chip:SetActive(false)
    chip:SetScript("OnClick", function(self)
      if EB and self.itemID then EB.SetBlacklisted(Bar(), self.itemID, false) end
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
      GameTooltip:Hide()
      RefreshBlacklist()
      RefreshPreview(Bar())
    end)
    chip:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetItemByID(self.itemID)
      GameTooltip:AddLine(L["EXTRABARS_BL_REMOVE"], 1, 0.82, 0)
      GameTooltip:Show()
    end)
    chip:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return chip
  end

  RefreshBlacklist = function()
    local ids = {}
    for id in pairs(EB and EB.Blacklist(Bar()) or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, chip in ipairs(blChips) do chip:Hide() end
    for i, id in ipairs(ids) do
      local chip = blChips[i] or NewChip()
      blChips[i] = chip
      chip.itemID = id
      chip.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
      local name = C_Item.GetItemNameByID(id)
      if not name then
        -- Objet pas encore en cache : nom affiché dès son chargement
        Item:CreateFromItemID(id):ContinueOnItemLoad(function()
          if chip.itemID == id then chip.fs:SetText(C_Item.GetItemNameByID(id) or ("#" .. id)) end
        end)
      end
      chip.fs:SetText(name or ("#" .. id))
      local col, row = (i - 1) % BL_PER_ROW, math.floor((i - 1) / BL_PER_ROW)
      chip:ClearAllPoints()
      chip:SetPoint("TOPLEFT", blList, "TOPLEFT", col * (blChipW + GAP), -row * (BL_H + GAP))
      chip:Show()
    end
    blEmpty:SetShown(#ids == 0)
    local rows = math.max(1, math.ceil(#ids / BL_PER_ROW))
    local h = rows * BL_H + (rows - 1) * GAP
    if math.abs(blList:GetHeight() - h) > 0.5 then
      blList:SetHeight(h)
      if ctx._finalized then ctx:Relayout() end
    end
  end

  -- ID d'objet, lien d'objet collé, ou objet glissé depuis les sacs
  local function AddItem(itemID)
    if not (EB and itemID and C_Item.GetItemInfoInstant(itemID)) then
      print("|cff00ccff[AishCore]|r " .. L["EXTRABARS_BL_INVALID"])
      return
    end
    EB.SetBlacklisted(Bar(), itemID, true)
    blInput:SetText("")
    blInput:ClearFocus()
    RefreshBlacklist()
    RefreshPreview(Bar())
  end
  local function AddFromInput()
    local text = blInput:GetText() or ""
    AddItem(tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")))
  end
  local function AddFromCursor()
    local kind, itemID = GetCursorInfo()
    if kind == "item" then
      ClearCursor()
      AddItem(itemID)
    end
  end
  blAdd:SetScript("OnClick", AddFromInput)
  blInput:SetScript("OnEnterPressed", AddFromInput)
  blInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  blInput:SetScript("OnReceiveDrag", AddFromCursor)
  blInput:HookScript("OnMouseDown", AddFromCursor)
  RefreshBlacklist()

  -- Visibilité -----------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  local ddVis = Bind(SW.CreateDropdown(container, L["EXTRABARS_VISIBILITY"], {
    { value = "always",   text = L["EXTRABARS_VIS_ALWAYS"] },
    { value = "combat",   text = L["EXTRABARS_VIS_COMBAT"] },
    { value = "nocombat", text = L["EXTRABARS_VIS_NOCOMBAT"] },
    { value = "injured",  text = L["EXTRABARS_VIS_INJURED"] },
  }, W2), "visibility", "string")
  local slAlpha = Bind(SW.CreateSlider(container, L["SETTINGS_OPACITY"], 0, 1, 0.05, W2), "alpha", "number")
  ctx:AddRow(8, ddVis, slAlpha)
  local cbMouse = Bind(SW.CreateCheckbox(container, L["EXTRABARS_MOUSEOVER"], L["EXTRABARS_MOUSEOVER_TT"], W2), "mouseover", "bool")
  local slMouseAlpha = Bind(SW.CreateSlider(container, L["EXTRABARS_MOUSEOVER_ALPHA"], 0, 1, 0.05, W2), "mouseoverAlpha", "number")
  ctx:AddRowCentered(8, cbMouse, slMouseAlpha)

  -- Disposition ----------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_LAYOUT"], W))
  local slWidth = Bind(SW.CreateSlider(container, L["EXTRABARS_BUTTON_WIDTH"], 12, 80, 1, W2), "buttonWidth", "number")
  local slHeight = Bind(SW.CreateSlider(container, L["EXTRABARS_BUTTON_HEIGHT"], 12, 80, 1, W2), "buttonHeight", "number")
  ctx:AddRow(8, slWidth, slHeight)
  local slGap = Bind(SW.CreateSlider(container, L["EXTRABARS_SPACING"], -2, 20, 1, W2), "spacing", "number")
  local slMax = Bind(SW.CreateSlider(container, L["EXTRABARS_MAX_BUTTONS"], 1, 24, 1, W2), "maxButtons", "number")
  ctx:AddRow(8, slGap, slMax)
  local slPer = Bind(SW.CreateSlider(container, L["EXTRABARS_PER_ROW"], 1, 24, 1, W2), "buttonsPerRow", "number")
  local cbVert = Bind(SW.CreateCheckbox(container, L["EXTRABARS_VERTICAL"], nil, W2), "vertical", "bool")
  ctx:AddRowCentered(8, slPer, cbVert)
  local ddCorner = Bind(SW.CreateDropdown(container, L["EXTRABARS_START_CORNER"], {
    { value = "TOPLEFT",     text = L["EXTRABARS_CORNER_TOPLEFT"] },
    { value = "TOPRIGHT",    text = L["EXTRABARS_CORNER_TOPRIGHT"] },
    { value = "BOTTOMLEFT",  text = L["EXTRABARS_CORNER_BOTTOMLEFT"] },
    { value = "BOTTOMRIGHT", text = L["EXTRABARS_CORNER_BOTTOMRIGHT"] },
  }, W2), "startCorner", "string")
  ctx:Add(ddCorner)

  -- Arrière-plan ---------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_BACKGROUND"], W))
  ctx:Add(Bind(SW.CreateCheckbox(container, L["EXTRABARS_BG_SHOW"], nil, W), "bgEnabled", "bool"))
  local bgOpts = {}
  for _, d in ipairs(EB and EB.BG_TEXTURES or {}) do
    bgOpts[#bgOpts + 1] = { value = d.value, text = L["EXTRABARS_BG_TEX_" .. d.value:upper()] }
  end
  local ddBgTex = Bind(SW.CreateDropdown(container, L["EXTRABARS_BG_TEXTURE"], bgOpts, W2), "bgTexture", "string")
  local colBg = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_COLOR"], W2), "bgColor", "color")
  ctx:AddRow(8, ddBgTex, colBg)
  local slPadX = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_PAD_X"], 0, 40, 1, W2), "bgPadX", "number")
  local slPadY = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_PAD_Y"], 0, 40, 1, W2), "bgPadY", "number")
  ctx:AddRow(8, slPadX, slPadY)
  local slEdge = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_EDGE"], 0, 64, 1, W2), "bgEdge", "number")
  local slBgBorder = Bind(SW.CreateSlider(container, L["EXTRABARS_BG_BORDER_SIZE"], 0, 6, 1, W2), "bgBorderSize", "number")
  ctx:AddRow(8, slEdge, slBgBorder)
  ctx:Add(Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_BORDER_COLOR"], W2), "bgBorderColor", "color"))

  -- Icônes ---------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_ICONS"], W))
  local cbZoom = Bind(SW.CreateCheckbox(container, L["EXTRABARS_ICON_ZOOM"], L["EXTRABARS_ICON_ZOOM_TT"], W2), "iconZoom", "bool")
  local cbBorder = Bind(SW.CreateCheckbox(container, L["EXTRABARS_BORDER"], nil, W2), "showBorder", "bool")
  ctx:AddRow(8, cbZoom, cbBorder)
  local colBorder = Bind(SW.CreateColorButton(container, L["EXTRABARS_BORDER_COLOR"], W2), "borderColor", "color")
  ctx:Add(colBorder)

  -- Sections de texte (piles / raccourcis) : mêmes réglages, préfixe de clé différent
  local function TextSection(title, prefix, showKey, showLabel, minSize, maxSize)
    ctx:Spacer(6)
    ctx:Add(SW.CreateSectionHeader(container, title, W))
    ctx:Add(Bind(SW.CreateCheckbox(container, showLabel, nil, W), showKey, "bool"))
    local ddFont = Bind(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), W2), prefix .. "Font", "string")
    local ddOutline = Bind(SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), W2), prefix .. "Outline", "string")
    ctx:AddRow(8, ddFont, ddOutline)
    local slSize = Bind(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], minSize, maxSize, 1, W2), prefix .. "Size", "number")
    local ddPoint = Bind(SW.CreateDropdown(container, L["EXTRABARS_TEXT_POSITION"], PointOptions(), W2), prefix .. "Point", "string")
    ctx:AddRow(8, slSize, ddPoint)
    local slX = Bind(SW.CreateSlider(container, L["EXTRABARS_OFFSET_X"], -30, 30, 1, W2), prefix .. "OffsetX", "number")
    local slY = Bind(SW.CreateSlider(container, L["EXTRABARS_OFFSET_Y"], -30, 30, 1, W2), prefix .. "OffsetY", "number")
    ctx:AddRow(8, slX, slY)
    ctx:Add(Bind(SW.CreateColorButton(container, L["SETTINGS_TEXT_COLOR"], W2), prefix .. "Color", "color"))
  end

  TextSection(L["EXTRABARS_SEC_STACKS"], "count", "showCount", L["EXTRABARS_SHOW_STACKS"], 6, 24)

  -- Temps de recharge ----------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_COOLDOWN"], W))
  local cbCdNum = Bind(SW.CreateCheckbox(container, L["EXTRABARS_COOLDOWN_NUMBERS"], nil, W2), "showCooldownNumbers", "bool")
  local slSwipe = Bind(SW.CreateSlider(container, L["EXTRABARS_SWIPE_ALPHA"], 0, 1, 0.05, W2), "swipeAlpha", "number")
  ctx:AddRowCentered(8, cbCdNum, slSwipe)
  local ddCdFont = Bind(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), W2), "cooldownFont", "string")
  local slCdSize = Bind(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 6, 32, 1, W2), "cooldownSize", "number")
  ctx:AddRow(8, ddCdFont, slCdSize)
  ctx:Add(Bind(SW.CreateCheckbox(container, L["EXTRABARS_BANDAGE_CD"], L["EXTRABARS_BANDAGE_CD_TT"], W), "bandageCooldown", "bool"))
  ctx:Add(Bind(SW.CreateColorButton(container, L["SETTINGS_TEXT_COLOR"], W2), "cooldownColor", "color"))

  TextSection(L["EXTRABARS_SEC_KEYBINDS"], "keybind", "showKeybind", L["EXTRABARS_SHOW_KEYBINDS"], 6, 20)
  local bindHint = container:CreateFontString(nil, "OVERLAY")
  bindHint:SetFont(ns.Media.fontGui, 10)
  bindHint:SetTextColor(0.55, 0.55, 0.55, 1)
  bindHint:SetJustifyH("LEFT")
  bindHint:SetWordWrap(true)
  bindHint:SetSize(W - 10, 28)
  bindHint:SetText(L["EXTRABARS_KEYBINDS_HINT"])
  ctx:Add(bindHint)

  ctx:Spacer()
  ctx:Finalize()

  -- Aperçu : vrais objets des sacs, complétés par l'icône de chaque tag suivi (au moins 5 boutons),
  -- avec un temps de recharge, des piles et des raccourcis fictifs, au style de la barre.
  local function PreviewIcons(bc, n)
    local icons = {}
    for _, e in ipairs(EB.Collect(bc)) do
      if #icons >= n then break end
      icons[#icons + 1] = C_Item.GetItemIconByID(e.itemID) or PLACEHOLDER_ICON
    end
    local tagIcons = {}
    for _, tag in ipairs(EB.TAGS) do
      if bc.tags and bc.tags[tag] then tagIcons[#tagIcons + 1] = EB.TAG_ICONS[tag] end
    end
    local k = 0
    while #icons < n do
      k = k + 1
      icons[#icons + 1] = (#tagIcons > 0) and tagIcons[(k - 1) % #tagIcons + 1] or PLACEHOLDER_ICON
    end
    return icons
  end

  RefreshPreview = function(bc)
    for _, pb in ipairs(previewButtons) do pb:Hide() end
    if not (EB and bc) then return end
    local maxB = math.min(bc.maxButtons or 12, 24)
    local n = math.min(maxB, math.max(#EB.Collect(bc), PREVIEW_MIN))
    local icons = PreviewIcons(bc, n)
    local w, h, gap = bc.buttonWidth or 32, bc.buttonHeight or 32, bc.spacing or 4
    local cols, rows, per = EB.GridSize(bc, n)
    local gw, gh = math.max(1, cols * w + (cols - 1) * gap), math.max(1, rows * h + (rows - 1) * gap)
    grid:SetSize(gw, gh)
    EB.StyleBackground(grid, bc, gw, gh)
    -- Réduit l'aperçu s'il dépasse l'encart (le texte des tags garde sa place en bas), fond compris
    local padX = bc.bgEnabled and (bc.bgPadX or 6) or 0
    local padY = bc.bgEnabled and (bc.bgPadY or 6) or 0
    grid:SetScale(math.min(1, (W - 24) / (gw + 2 * padX), (PREVIEW_H - 34) / (gh + 2 * padY)))
    -- Fond de l'encart : couleur d'accent assombrie (pas du noir) pour juger fonds et transparences
    local g = Gold()
    preview:SetBackdropColor(g[1] * 0.13, g[2] * 0.13, g[3] * 0.13, 1)
    grid:ClearAllPoints()
    grid:SetPoint("CENTER", preview, "CENTER", 0, 7)
    for j = 1, n do
      local pb = previewButtons[j]
      if not pb then
        pb = EB.CreateVisual(grid, nil, false)
        pb.cooldown:SetScript("OnCooldownDone", function(cd) cd:SetCooldown(GetTime(), 45) end)
        previewButtons[j] = pb
      end
      pb.icon:SetTexture(icons[j])
      EB.StyleButton(pb, bc, w, h)
      local col, row = EB.GridCell(bc, j, cols, rows, per)
      pb:ClearAllPoints()
      pb:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (w + gap), -row * (h + gap))
      pb.count:SetText(FAKE_STACKS[j] or "")
      pb.hotkey:SetText(EB.ShortKey(j <= 9 and tostring(j) or ("SHIFT-" .. (j - 9))))
      if j == FAKE_CD_INDEX then pb.cooldown:SetCooldown(GetTime() - 15, 45) else pb.cooldown:Clear() end
      pb:Show()
    end
    local label = EB.TagsLabel(bc, " - ")
    tagsText:SetText(label ~= "" and label or L["EXTRABARS_NO_TAG"])
  end

  RefreshAll = function()
    local bc = Bar()
    local opts = {}
    for i = 1, (EB and EB.NUM_BARS or 5) do
      opts[#opts + 1] = { value = i, text = EB and EB.BarName(i, EB.BarCfg(i)) or tostring(i) }
    end
    barDD:SetOptions(opts)
    barDD:SetValue(ns._extraBarsSelected)
    if not bc then return end
    for _, e in ipairs(bound) do
      local v = bc[e.key]
      if e.kind == "bool" then
        if e.w.SetChecked then e.w:SetChecked(v and true or false) else e.w:SetValue(v and true or false) end
      elseif e.kind == "color" then
        if type(v) == "table" then e.w:SetColor(v[1], v[2], v[3], v[4]) end
      elseif v ~= nil then
        e.w:SetValue(v)
      end
    end
    for _, pill in ipairs(pills) do pill:SetActive(bc.tags and bc.tags[pill.tag] == true) end
    RefreshBlacklist()
    RefreshPreview(bc)
    RefreshDragBtn()
  end
  -- Clic droit sur une barre à l'écran (UI/ModuleHoverOverlay.lua) : sélection de cette barre
  ns.ExtraBarsPageRefresh = function() if container:IsVisible() then RefreshAll() end end

  container:HookScript("OnShow", function() RefreshAll() end)
  RefreshAll()
end

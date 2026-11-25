-- UI/ActionBarsPage.lua : page "Barres d'action" du GUI (logique : Modules/ActionBars.lua).
-- Bloc epingle : titre + interrupteur du module, selecteur de barre + interrupteur de la barre, apercu de la barre
-- (rendu par le module, comme en jeu). Puis copie des reglages et les sections de la barre selectionnee ; les
-- reglages communs a toutes les barres sont sous un sous-titre "Commun a toutes les barres". Changer de barre relit
-- les valeurs sans reconstruire la page.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local PREVIEW_H = 130
local TITLE_H, PIN_TOP_H = 30, 26
local PREVIEW_MAX_SCALE = 2
local GRAY = 0.35
local NOT_COPIED = { enabled = true, x = true, y = true, group = true }

local function AB() return ns.Modules and ns.Modules.ActionBars end

local ANCHORS
local function AnchorOptions()
  if not ANCHORS then
    ANCHORS = {}
    for _, p in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
      ANCHORS[#ANCHORS + 1] = { value = p, text = L["SETTINGS_ANCHOR_" .. p] }
    end
  end
  return ANCHORS
end

-- Grise un widget et lui retire la souris (cache qui capte les clics), sans le masquer
local function Gray(w, on, keepAlpha)
  if not w._grayBlock then
    local b = CreateFrame("Frame", nil, w)
    b:SetAllPoints(w)
    b:SetFrameLevel(w:GetFrameLevel() + 20)
    b:EnableMouse(true)
    w._grayBlock = b
  end
  w._grayBlock:SetShown(on)
  if not keepAlpha then w:SetAlpha(on and GRAY or 1) end
end

local function Subtitle(parent, text, width, divider)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 18)
  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 10)
  lbl:SetPoint("LEFT", f, "LEFT", 0, 0)
  lbl:SetTextColor(unpack(Theme.textDim))
  lbl:SetText(text)
  f._lbl = lbl
  f._leKind, f._leText = "subheader", text
  if divider then
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    SW.PixelLine(line)
    line:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    line:SetColorTexture(1, 1, 1, 0.12)
  end
  return f
end

function ns.BuildActionBarsPage(container, W, NewLayout)
  local ctx = NewLayout(container)
  ctx.noGrid = true
  ctx.noMasters = true   -- grisages geres par la page (RefreshStates)
  local GAP = 12
  local function Cols(n) return math.floor((W - (n - 1) * GAP) / n) end
  local function Span(n, k) return (k or 1) * Cols(n) + ((k or 1) - 1) * GAP end
  local function CB(label, tt, n, k) return SW.CreateCheckbox(container, label, tt, Span(n, k)) end
  local function SL(label, lo, hi, step, n, k) return SW.CreateSlider(container, label, lo, hi, step, Span(n, k), true) end
  local function DD(label, opts, n, k) return SW.CreateDropdown(container, label, opts, Span(n, k)) end
  local function AR(label, opts, n, k) return SW.CreateAlignRow(container, label, Span(n, k), opts, true) end
  local function COL(label, n, k) return SW.CreateColorButton(container, label, Span(n, k)) end
  local function Row(n, ...)
    local args = { ... }
    for i = 1, select("#", ...) do
      if not args[i] then
        local e = CreateFrame("Frame", nil, container)
        e:SetSize(Cols(n), 1)
        e._leEmpty = true
        args[i] = e
      end
    end
    ctx:AddRowCentered(GAP, unpack(args))
    ctx:Spacer(4)
  end
  local function Section(text)
    ctx:Spacer(6)
    ctx:Add(SW.CreateSectionHeader(container, text, W))
  end

  local m0 = AB()
  ns._actionBarsSelected = ns._actionBarsSelected or "bar1"
  local function Sel() return ns._actionBarsSelected end
  local function Bar() return AB().BarDB(Sel()) end
  local function BV(prop) return AB().BV(Sel(), prop) end
  local function GV(prop) return AB().GV(prop) end

  local bound, gbound = {}, {}
  local RefreshAll, RefreshPreview, RefreshStates
  local pending = false
  local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      local m = AB()
      if m then m.ApplySettings() end
      RefreshStates()
      RefreshPreview()
    end)
  end
  local function Bind(w, key, kind)
    bound[#bound + 1] = { w = w, key = key, kind = kind }
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      AB().SetBV(Sel(), key, v)   -- barre groupee : reglage du groupe (sauf position / disposition)
      Changed()
    end
    return w
  end
  local function GBind(w, key, kind)
    gbound[#gbound + 1] = { w = w, key = key, kind = kind }
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      AB().DB()[key] = v
      Changed()
    end
    return w
  end

  -- Bloc epingle ----------------------------------------------------------------------------------------------------
  local pin = CreateFrame("Frame", nil, container)
  local title = SW.CreateSectionHeader(pin, L["SETTINGS_CAT_ACTION_BARS"], W)
  title:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, 0)
  ctx:PinnedTitle(title, pin)
  local cbModule = GBind(SW.CreateCheckbox(container, L["ACTIONBARS_ENABLE"], L["ACTIONBARS_ENABLE_TT"], W), "enabled", "bool")
  local origModule = cbModule.onChanged
  cbModule.onChanged = function(v)
    origModule(v)
    if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("modulesOverview") end
  end
  ctx:TitleToggle(cbModule)

  local top = CreateFrame("Frame", nil, pin)
  top:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, -TITLE_H)
  top:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 0, -TITLE_H)
  top:SetHeight(PIN_TOP_H)
  local barDD = SW.CreateDropdown(top, "", {}, 420)
  barDD:SetPoint("CENTER", top, "CENTER", -32, 0)
  local toggle = SW.CreateToggle(top, 54)
  toggle:SetPoint("LEFT", barDD, "RIGHT", 12, 0)
  barDD.onChanged = function(v) ns._actionBarsSelected = v; RefreshAll() end
  toggle.onChanged = function(v)
    Bar().enabled = v and true or false
    Changed()
  end

  local preview = CreateFrame("Frame", nil, pin, "BackdropTemplate")
  preview:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, -(TITLE_H + PIN_TOP_H + 6))
  preview:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 0, -(TITLE_H + PIN_TOP_H + 6))
  preview:SetHeight(PREVIEW_H)
  preview:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  preview:SetBackdropBorderColor(unpack(Theme.border))
  preview:SetClipsChildren(true)
  SW.ApplyPreviewScreen(preview)
  local hint = preview:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 10)
  hint:SetTextColor(1, 1, 1, 1)
  hint:SetShadowColor(0, 0, 0, 0.9)
  hint:SetShadowOffset(1, -1)
  hint:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 8, 6)
  hint:SetText(L["ACTIONBARS_PREVIEW_HINT"])
  local pf = m0 and m0.CreatePreview(preview)
  if pf then pf:SetFrameLevel(preview:GetFrameLevel() + 5) end

  -- Verrou (deplacement des barres a l'ecran) et mode raccourcis de Blizzard
  local lockBtn = SW.CreateActionBtn(preview, L["UNITBARS_LOCK"], 130)
  lockBtn:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -6, 6)
  lockBtn:SetFrameLevel(preview:GetFrameLevel() + 60)
  local function LockLabel()
    lockBtn._lbl:SetText(GV("locked") == false and L["UNITBARS_LOCK"] or L["UNITBARS_UNLOCK"])
  end
  lockBtn:SetScript("OnClick", function()
    AB().SetLocked(GV("locked") == false)
    LockLabel()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  local keyBtn = SW.CreateActionBtn(preview, L["ACTIONBARS_KEYBIND_MODE"], 130)
  keyBtn:SetPoint("BOTTOMRIGHT", lockBtn, "TOPRIGHT", 0, 6)
  keyBtn:SetFrameLevel(preview:GetFrameLevel() + 60)
  keyBtn:SetScript("OnClick", function() AB().OpenQuickKeybind() end)
  keyBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["ACTIONBARS_KEYBIND_MODE_TT"], 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  keyBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  -- Option : barres reelles forcees (opacite pleine, emplacements visibles) tant que la page est ouverte ;
  -- decoche par defaut, les barres gardent leur comportement reel (survol, visibilite)
  local showT = SW.CreateToggle(preview, 40)
  showT:SetPoint("BOTTOMRIGHT", keyBtn, "TOPRIGHT", 0, 6)
  showT:SetFrameLevel(preview:GetFrameLevel() + 60)
  local showLbl = preview:CreateFontString(nil, "OVERLAY")
  showLbl:SetFont(ns.Media.fontGui, 10)
  showLbl:SetTextColor(1, 1, 1, 1)
  showLbl:SetShadowColor(0, 0, 0, 0.9)
  showLbl:SetShadowOffset(1, -1)
  showLbl:SetPoint("RIGHT", showT, "LEFT", -6, 0)
  showLbl:SetText(L["ACTIONBARS_GUI_SHOW"])
  local function GuiForce()
    local m = AB()
    if m then m.SetGuiForce(container:IsVisible() and GV("guiForceBars") == true) end
  end
  showT.onChanged = function(v)
    AB().DB().guiForceBars = v and true or false
    GuiForce()
  end

  local function PinUp()
    if ns.SettingsPin then ns.SettingsPin(pin, TITLE_H + PIN_TOP_H + 6 + PREVIEW_H) end
  end
  container:HookScript("OnShow", function() PinUp(); GuiForce() end)
  container:HookScript("OnHide", function()
    if ns.SettingsUnpin then ns.SettingsUnpin(pin) end
    local m = AB()
    if m then m.SetGuiForce(false) end
  end)

  -- Copie des reglages vers une autre barre ----------------------------------------------------------------------------
  ctx:Spacer(8)
  local copyBtn = SW.CreateActionBtn(container, L["EXTRABARS_COPY_TO"], Cols(4))
  copyBtn:SetScript("OnClick", function()
    local from = Sel()
    local function CopyTo(targets)
      local m = AB()
      for _, to in ipairs(targets) do
        for k in pairs(ns.ActionBarCommon or {}) do
          if not NOT_COPIED[k] then
            local v = m.BV(from, k)
            m.SetBV(to, k, type(v) == "table" and CopyTable(v) or v)
          end
        end
      end
      print("|cff00ccff[AishCore]|r " .. L["UNITBARS_COPIED"])
      Changed()
    end
    local items, all = {}, {}
    for _, def in ipairs(AB().BARS) do
      if def.key ~= from then
        all[#all + 1] = def.key
        items[#items + 1] = { label = AB().Label(def.key), onClick = function() CopyTo({ def.key }) end }
      end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = L["EXTRABARS_COPY_ALL"], onClick = function() CopyTo(all) end }
    SW.ShowContextMenu(items)
  end)
  ctx:Add(copyBtn)

  -- Groupe de barres : reglages partages (sauf position et disposition) ----------------------------------------------
  Section(L["ACTIONBARS_SEC_GROUP"])
  local function AskName(default, cb)
    StaticPopupDialogs["AISHCORE_AB_GROUP_NAME"] = StaticPopupDialogs["AISHCORE_AB_GROUP_NAME"] or {
      text = L["ACTIONBARS_GROUP_PROMPT"], button1 = OKAY, button2 = CANCEL, hasEditBox = 1, maxLetters = 40,
      timeout = 0, whileDead = true, hideOnEscape = true,
      OnShow = function(self, data)
        local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
        if eb then eb:SetText(data and data.default or ""); eb:HighlightText(); eb:SetFocus() end
      end,
      OnAccept = function(self, data)
        local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
        if eb and data and data.cb then data.cb(eb:GetText()) end
      end,
      EditBoxOnEnterPressed = function(eb, data)
        if data and data.cb then data.cb(eb:GetText()) end
        eb:GetParent():Hide()
      end,
      EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    }
    StaticPopup_Show("AISHCORE_AB_GROUP_NAME", nil, nil, { default = default, cb = cb })
  end
  local function NextGroupName()
    local used, n = {}, 1
    for _, g in pairs(AB().Groups()) do used[g.name or ""] = true end
    while used[L["ACTIONBARS_GROUP_DEFAULT"]:format(n)] do n = n + 1 end
    return L["ACTIONBARS_GROUP_DEFAULT"]:format(n)
  end
  local ddGroup = DD(L["ACTIONBARS_GROUP"], {}, 4)
  ddGroup.onChanged = function(v)
    AB().SetGroup(Sel(), v ~= "none" and v or nil)
    RefreshAll()
    Changed()
  end
  local btnNew = SW.CreateActionBtn(container, L["ACTIONBARS_GROUP_NEW"], Cols(4))
  btnNew:SetScript("OnClick", function()
    AskName(NextGroupName(), function(name)
      name = strtrim(name or "")
      if name == "" then return end
      AB().SetGroup(Sel(), nil)
      AB().NewGroup(Sel(), name)
      RefreshAll()
      Changed()
    end)
  end)
  btnNew:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["ACTIONBARS_GROUP_TT"], 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  btnNew:HookScript("OnLeave", function() GameTooltip:Hide() end)
  local btnRename = SW.CreateActionBtn(container, L["ACTIONBARS_GROUP_RENAME"], Cols(4))
  btnRename:SetScript("OnClick", function()
    local g = AB().GroupOf(Sel())
    if not g then return end
    AskName(g.name, function(name)
      name = strtrim(name or "")
      if name == "" then return end
      g.name = name
      RefreshAll()
    end)
  end)
  local btnDelete = SW.CreateActionBtn(container, L["ACTIONBARS_GROUP_DELETE"], Cols(4))
  btnDelete:SetScript("OnClick", function()
    local _, id = AB().GroupOf(Sel())
    if not id then return end
    AB().DeleteGroup(id)
    RefreshAll()
    Changed()
  end)
  Row(4, ddGroup, btnNew, btnRename, btnDelete)

  -- Disposition -----------------------------------------------------------------------------------------------------
  Section(L["ACTIONBARS_SEC_LAYOUT"])
  local slCount = Bind(SL(L["ACTIONBARS_COUNT"], 1, 12, 1, 4), "count", "number")
  local slPerRow = Bind(SL(L["ACTIONBARS_PER_ROW"], 1, 12, 1, 4), "perRow", "number")
  local rowGrowH = Bind(AR(L["ACTIONBARS_GROW_H"], {
    { k = "RIGHT", l = L["ACTIONBARS_GROW_RIGHT"] }, { k = "LEFT", l = L["ACTIONBARS_GROW_LEFT"] },
  }, 4), "growH", "string")
  local rowGrowV = Bind(AR(L["ACTIONBARS_GROW_V"], {
    { k = "DOWN", l = L["ACTIONBARS_GROW_DOWN"] }, { k = "UP", l = L["ACTIONBARS_GROW_UP"] },
  }, 4), "growV", "string")
  Row(4, slCount, slPerRow, rowGrowH, rowGrowV)
  local slW = Bind(SL(L["SETTINGS_WIDTH"], 16, 80, 1, 4), "width", "number")
  local slH = Bind(SL(L["SETTINGS_HEIGHT"], 16, 80, 1, 4), "height", "number")
  local slSpX = Bind(SL(L["ACTIONBARS_SPACING_X"], -4, 40, 1, 4), "spacingX", "number")
  local slSpY = Bind(SL(L["ACTIONBARS_SPACING_Y"], -4, 40, 1, 4), "spacingY", "number")
  Row(4, slW, slH, slSpX, slSpY)
  local slX = Bind(SL(L["SETTINGS_OFFSET_X"], -1600, 1600, 1, 4), "x", "number")
  local slY = Bind(SL(L["SETTINGS_OFFSET_Y"], -900, 900, 1, 4), "y", "number")
  Row(4, slX, slY, false, false)

  -- Visibilite et opacite : Normal / Discret / Avance (regles cumulables, affichees en Avance seulement) -----------
  Section(L["ACTIONBARS_SEC_VISIBILITY"])
  local rowMode = Bind(AR(L["ACTIONBARS_VIS_MODE"], {
    { k = "normal", l = L["ACTIONBARS_MODE_NORMAL"] }, { k = "discreet", l = L["ACTIONBARS_MODE_DISCREET"] },
    { k = "advanced", l = L["ACTIONBARS_MODE_ADVANCED"] },
  }, 4, 2), "visMode", "string")
  local modeHint = CreateFrame("Frame", nil, container)
  modeHint:SetSize(Span(4, 2), 34)
  modeHint._lbl = modeHint:CreateFontString(nil, "OVERLAY")
  modeHint._lbl:SetFont(ns.Media.fontGui, 10)
  modeHint._lbl:SetTextColor(unpack(Theme.textDim))
  modeHint._lbl:SetAllPoints()
  modeHint._lbl:SetJustifyH("LEFT")
  modeHint._lbl:SetJustifyV("MIDDLE")
  modeHint._lbl:SetWordWrap(true)
  Row(4, rowMode, modeHint)
  local slAlpha = Bind(SL(L["ACTIONBARS_ALPHA_SHOWN"], 0, 1, 0.05, 4), "alpha", "number")
  local slMouseA = Bind(SL(L["ACTIONBARS_ALPHA_HIDDEN"], 0, 1, 0.05, 4), "mouseoverAlpha", "number")
  local function VCB(label, key, tt) local c = Bind(CB(label, tt, 4), key, "bool"); c._noMaster = true; return c end
  local cbEmpty = VCB(L["ACTIONBARS_SHOW_EMPTY"], "showEmpty", L["ACTIONBARS_SHOW_EMPTY_TT"])
  Row(4, slAlpha, slMouseA, cbEmpty, false)
  -- Avance
  local function NotAdvanced() return BV("visMode") ~= "advanced" end
  local advFrom = #ctx.flow
  ctx:Add(Subtitle(container, L["ACTIONBARS_MODE_ADVANCED"], W, true))
  local cbAlways = VCB(L["SETTINGS_UB_VR_ALWAYS"], "visAlways", L["ACTIONBARS_VR_ALWAYS_TT"])
  local cbHover = VCB(L["SETTINGS_UB_VIS_HOVER"], "visHover", L["ACTIONBARS_VR_HOVER_TT"])
  local cbCombat = VCB(L["ACTIONBARS_VIS_COMBAT"], "visCombat")
  local cbInjured = VCB(L["ACTIONBARS_VR_INJURED"], "visInjured")
  Row(4, cbAlways, cbHover, cbCombat, cbInjured)
  local cbFriendly = VCB(L["SETTINGS_UB_VR_FRIENDLY"], "visFriendly")
  local cbAttack = VCB(L["SETTINGS_UB_VR_ATTACKABLE"], "visAttackable")
  local cbGroup = VCB(L["SETTINGS_UB_VR_GROUP"], "visGroup")
  local cbInstance = VCB(L["SETTINGS_UB_VR_INSTANCE"], "visInstance")
  Row(4, cbFriendly, cbAttack, cbGroup, cbInstance)
  local showRules = { cbHover, cbCombat, cbInjured, cbFriendly, cbAttack, cbGroup, cbInstance }
  local cbMounted = VCB(L["SETTINGS_UB_VR_HIDE_MOUNT"], "hideMounted", L["ACTIONBARS_VR_HIDE_TT"])
  local cbResting = VCB(L["SETTINGS_UB_VR_HIDE_REST"], "hideResting", L["ACTIONBARS_VR_HIDE_TT"])
  local cbVehicle = VCB(L["ACTIONBARS_HIDE_VEHICLE"], "hideVehicle", L["ACTIONBARS_HIDE_VEHICLE_TT"])
  local cbSky = VCB(L["ACTIONBARS_HIDE_SKYRIDING"], "hideSkyriding")
  Row(4, cbMounted, cbResting, cbVehicle, cbSky)
  if ctx.HideIf then ctx:HideIf(advFrom, NotAdvanced) end
  local advWidgets = { cbAlways, cbHover, cbCombat, cbInjured, cbFriendly, cbAttack, cbGroup, cbInstance, cbMounted,
                       cbResting, cbVehicle, cbSky }
  local lastMode = BV("visMode")
  local origMode = rowMode.onChanged
  rowMode.onChanged = function(v)
    origMode(v)
    if v ~= lastMode then lastMode = v; if ctx.Relayout then ctx:Relayout(true) end end
  end
  ctx:Add(Subtitle(container, L["ACTIONBARS_SUB_COMMON"], W, true))
  local slFade = GBind(SL(L["ACTIONBARS_FADE_TIME"], 0, 1.5, 0.05, 4), "fadeTime", "number")
  local slDelay = GBind(SL(L["ACTIONBARS_HOVER_DELAY"], 0, 3, 0.1, 4), "hoverDelay", "number")
  local slPad = GBind(SL(L["SETTINGS_UB_HOVER_TOLERANCE"], 0, 60, 1, 4), "hoverPad", "number")
  Row(4, slFade, slDelay, slPad)

  -- Boutons ---------------------------------------------------------------------------------------------------------
  Section(L["ACTIONBARS_SEC_BUTTONS"])
  local shapeOpts = {
    { value = "square", text = L["ACTIONBARS_SHAPE_SQUARE"] }, { value = "circle", text = L["ACTIONBARS_SHAPE_CIRCLE"] },
    { value = "diamond", text = L["ACTIONBARS_SHAPE_DIAMOND"] }, { value = "grunge", text = L["ACTIONBARS_SHAPE_GRUNGE"] },
    { value = "feather", text = L["ACTIONBARS_SHAPE_FEATHER"] },
  }
  local ddShape = Bind(DD(L["ACTIONBARS_SHAPE"], shapeOpts, 4), "shape", "string")
  local cbZoom = Bind(CB(L["ACTIONBARS_ICON_ZOOM"], L["ACTIONBARS_ICON_ZOOM_TT"], 4), "iconZoom", "bool")
  local slBorder = Bind(SL(L["ACTIONBARS_BORDER_SIZE"], 0, 6, 1, 4), "borderSize", "number")
  local colBorder = Bind(COL(L["ACTIONBARS_BORDER_COLOR"], 4), "borderColor", "color")
  cbZoom._noMaster = true
  Row(4, ddShape, cbZoom, slBorder, colBorder)
  local cbBorderTheme = Bind(CB(L["CASTBARS_THEMED"], L["ACTIONBARS_BORDER_THEMED_TT"], 4), "borderThemed", "bool")
  local colSlot = Bind(COL(L["ACTIONBARS_SLOT_COLOR"], 4), "slotColor", "color")
  local cbTexVar = Bind(CB(L["ACTIONBARS_TEX_VARIATION"], L["ACTIONBARS_TEX_VARIATION_TT"], 4), "texVariation", "bool")
  cbBorderTheme._noMaster, cbTexVar._noMaster = true, true
  Row(4, colSlot, cbTexVar, cbBorderTheme, false)
  local colHover = Bind(COL(L["ACTIONBARS_HOVER_COLOR"], 4), "hoverColor", "color")
  local colPushed = Bind(COL(L["ACTIONBARS_PUSHED_COLOR"], 4), "pushedColor", "color")
  local colChecked = Bind(COL(L["ACTIONBARS_CHECKED_COLOR"], 4), "checkedColor", "color")
  Row(4, colHover, colPushed, colChecked, false)
  ctx:Add(Subtitle(container, L["ACTIONBARS_SUB_COMMON"], W, true))
  local cbRange = GBind(CB(L["ACTIONBARS_RANGE_TINT"], L["ACTIONBARS_RANGE_TINT_TT"], 4), "rangeTint", "bool")
  local colRange = GBind(COL(L["ACTIONBARS_RANGE_COLOR"], 4), "rangeColor", "color")
  local cbRangeThemed = GBind(CB(L["CASTBARS_THEMED"], L["ACTIONBARS_RANGE_THEMED_TT"], 4), "rangeThemed", "bool")
  cbRange._noMaster, cbRangeThemed._noMaster = true, true
  Row(4, cbRange, colRange, cbRangeThemed, false)

  -- Recharge --------------------------------------------------------------------------------------------------------
  Section(L["ACTIONBARS_SEC_COOLDOWN"])
  local cbCd = Bind(CB(L["ACTIONBARS_CD_NUMBERS"], nil, 4), "cdNumbers", "bool")
  cbCd._noMaster = true
  local slSwipe = Bind(SL(L["ACTIONBARS_SWIPE_ALPHA"], 0, 1, 0.05, 4), "swipeAlpha", "number")
  local cbCdThemed = Bind(CB(L["CASTBARS_THEMED"], L["ACTIONBARS_TEXT_THEMED_TT"], 4), "cdThemed", "bool")
  cbCdThemed._noMaster = true
  Row(4, cbCd, slSwipe, cbCdThemed, false)
  local ddCdFont = Bind(DD(L["SETTINGS_FONT"], ns.GetFontList(), 4), "cdFont", "string")
  local slCdSize = Bind(SL(L["SETTINGS_FONT_SIZE"], 6, 40, 1, 4), "cdSize", "number")
  local ddCdOutline = Bind(DD(L["SETTINGS_TEXT_OUTLINE"], {
    { value = "OUTLINE", text = L["TEXT_OUTLINE_THIN"] }, { value = "THICKOUTLINE", text = L["TEXT_OUTLINE_THICK"] },
  }, 4), "cdOutline", "string")
  local colCd = Bind(COL(L["UNITBARS_COLOR"], 4), "cdColor", "color")
  Row(4, ddCdFont, slCdSize, ddCdOutline, colCd)
  local cdWidgets = { ddCdFont, slCdSize, ddCdOutline, colCd, cbCdThemed }

  -- Surbrillance des procs : glow d'AishCore a la taille de l'icone ------------------------------------------------
  Section(L["ACTIONBARS_SEC_GLOW"])
  local glowOpts = { { value = "auto", text = L["ACTIONBARS_GLOW_AUTO"] }, { value = "none", text = L["ACTIONBARS_BG_NONE"] } }
  for i, d in ipairs(ns.Auras and ns.Auras.GLOW_DEFS or {}) do
    if i > 1 and not d.isProcStart then glowOpts[#glowOpts + 1] = { value = d.name, text = d.name } end
  end
  local ddGlow = Bind(DD(L["SETTINGS_ARMORY_TRANSMOG_GLOW_STYLE"], glowOpts, 4), "glowStyle", "string")
  local psOpts = { { value = "auto", text = L["ACTIONBARS_GLOW_AUTO"] }, { value = "none", text = L["ACTIONBARS_BG_NONE"] } }
  for _, d in ipairs(ns.Auras and ns.Auras.GLOW_DEFS or {}) do
    if d.isProcStart then psOpts[#psOpts + 1] = { value = d.name, text = d.name } end
  end
  local ddProcStart = Bind(DD(L["ACTIONBARS_PROC_START"], psOpts, 4), "procStart", "string")
  local colGlow = Bind(COL(L["SETTINGS_GLOW_COLOR"], 4), "glowColor", "color")
  local cbGlowThemed = Bind(CB(L["CASTBARS_THEMED"], L["ACTIONBARS_GLOW_THEMED_TT"], 4), "glowThemed", "bool")
  cbGlowThemed._noMaster = true
  Row(4, ddGlow, ddProcStart, colGlow, cbGlowThemed)

  -- Textes : raccourci, charges, nom de macro (meme gabarit) ----------------------------------------------------------
  local textBlocks = {}
  local function TextSection(secText, pre, showText, extra)
    Section(secText)
    local cbShow = Bind(CB(showText, nil, 4), pre .. "Show", "bool")
    local ext = extra and extra() or false
    Row(4, cbShow, ext, false, false)
    local ddFont = Bind(DD(L["SETTINGS_FONT"], ns.GetFontList(), 4), pre .. "Font", "string")
    local slSize = Bind(SL(L["SETTINGS_FONT_SIZE"], 6, 40, 1, 4), pre .. "Size", "number")
    local ddOut = Bind(DD(L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 4), pre .. "Outline", "string")
    local col = Bind(COL(L["UNITBARS_COLOR"], 4), pre .. "Color", "color")
    Row(4, ddFont, slSize, ddOut, col)
    local ddAnchor = Bind(DD(L["UNITBARS_ANCHOR"], AnchorOptions(), 4), pre .. "Anchor", "string")
    local slX = Bind(SL(L["SETTINGS_OFFSET_X"], -40, 40, 1, 4), pre .. "X", "number")
    local slY = Bind(SL(L["SETTINGS_OFFSET_Y"], -40, 40, 1, 4), pre .. "Y", "number")
    local cbThemed = Bind(CB(L["CASTBARS_THEMED"], L["ACTIONBARS_TEXT_THEMED_TT"], 4), pre .. "Themed", "bool")
    cbThemed._noMaster = true
    Row(4, ddAnchor, slX, slY, cbThemed)
    textBlocks[#textBlocks + 1] = { pre = pre, col = col,
      ws = { ext or nil, ddFont, slSize, ddOut, col, ddAnchor, slX, slY, cbThemed } }
  end
  TextSection(L["ACTIONBARS_SEC_HOTKEY"], "hk", L["ACTIONBARS_HK_SHOW"], function()
    return Bind(CB(L["ACTIONBARS_HK_SHORT"], L["ACTIONBARS_HK_SHORT_TT"], 4), "hkShort", "bool")
  end)
  TextSection(L["ACTIONBARS_SEC_COUNT"], "ct", L["ACTIONBARS_CT_SHOW"])
  TextSection(L["ACTIONBARS_SEC_MACRO"], "nm", L["ACTIONBARS_NM_SHOW"])

  -- Fond de barre ---------------------------------------------------------------------------------------------------
  Section(L["ACTIONBARS_SEC_BACKGROUND"])
  local bgOpts = {}
  for _, d in ipairs(m0 and m0.BG_TEXTURES or {}) do
    local k
    if d.value == "none" then k = "ACTIONBARS_BG_NONE"
    elseif d.nine then k = "EXTRABARS_BG_TEX_" .. d.value:upper()
    else k = "ADDONCOMP_BG_TEX_" .. d.value:upper() end
    bgOpts[#bgOpts + 1] = { value = d.value, text = L[k] }
  end
  local ddBg = Bind(DD(L["EXTRABARS_BG_TEXTURE"], bgOpts, 4), "bgTexture", "string")
  local colBg = Bind(COL(L["EXTRABARS_BG_COLOR"], 4), "bgColor", "color")
  local slPadX = Bind(SL(L["EXTRABARS_BG_PAD_X"], 0, 60, 1, 4), "bgPadX", "number")
  local slPadY = Bind(SL(L["EXTRABARS_BG_PAD_Y"], 0, 60, 1, 4), "bgPadY", "number")
  Row(4, ddBg, colBg, slPadX, slPadY)
  local slEdge = Bind(SL(L["EXTRABARS_BG_EDGE"], 0, 64, 1, 4), "bgEdge", "number")
  local slBgBorder = Bind(SL(L["EXTRABARS_BG_BORDER_SIZE"], 0, 6, 1, 4), "bgBorderSize", "number")
  local colBgBorder = Bind(COL(L["EXTRABARS_BG_BORDER_COLOR"], 4), "bgBorderColor", "color")
  local slBgAlpha = Bind(SL(L["XP_TOAST_BG_ALPHA"], 0, 1, 0.05, 4), "bgAlpha", "number")
  Row(4, slEdge, slBgBorder, colBgBorder, slBgAlpha)

  ctx:Spacer()
  ctx:Finalize()

  -- Apercu : clic droit sur un bouton = section Boutons, sur le fond = Disposition
  local function OpenSection(text)
    local panel = ns.SettingsPanel
    if panel and panel.OpenSection then panel:OpenSection("actionBars", text:upper(), true) end
  end
  local bgClick = CreateFrame("Button", nil, preview)
  bgClick:SetAllPoints()
  bgClick:SetFrameLevel(preview:GetFrameLevel() + 1)
  bgClick:RegisterForClicks("RightButtonUp")
  bgClick:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    OpenSection(L["ACTIONBARS_SEC_LAYOUT"])
  end)
  if pf then
    for _, b in ipairs(pf.buttons) do
      b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      b:SetScript("OnClick", function(self, button)
        self:SetChecked(false)
        if button == "RightButton" then
          PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
          OpenSection(L["ACTIONBARS_SEC_BUTTONS"])
        end
      end)
    end
  end

  RefreshPreview = function()
    local m = AB()
    if not (m and pf) then return end
    local w, h = m.StylePreview(pf, Sel())
    local padX, padY = 0, 0
    if (BV("bgTexture") or "none") ~= "none" then padX, padY = BV("bgPadX") or 0, BV("bgPadY") or 0 end
    local pw = preview:GetWidth()
    if not pw or pw < 50 then pw = W end
    local sc = math.min(PREVIEW_MAX_SCALE, (pw - 300) / math.max(1, w + 2 * padX), (PREVIEW_H - 24) / math.max(1, h + 2 * padY))
    pf:SetScale(math.max(0.2, sc))
    pf:ClearAllPoints()
    pf:SetPoint("CENTER", preview, "CENTER", -60 / pf:GetScale(), 4 / pf:GetScale())
  end

  RefreshStates = function()
    local off = title._moduleOff
    local mode = BV("visMode") or "normal"
    local adv = mode == "advanced"
    local always = BV("visAlways") ~= false
    for _, w in ipairs(advWidgets) do Gray(w, not adv, off) end
    if adv then for _, w in ipairs(showRules) do Gray(w, always, off) end end
    Gray(slMouseA, adv and (always or not BV("visHover")), off)
    modeHint._lbl:SetText(L["ACTIONBARS_MODE_" .. mode:upper() .. "_TT"] or "")
    if mode ~= lastMode then lastMode = mode; if ctx.Relayout then ctx:Relayout() end end
    local grouped = AB().GroupOf(Sel()) ~= nil
    Gray(btnRename, not grouped, off)
    Gray(btnDelete, not grouped, off)
    Gray(colBorder, BV("borderThemed") == true, off)
    Gray(colRange, GV("rangeTint") == false or GV("rangeThemed") == true, off)
    Gray(cbRangeThemed, GV("rangeTint") == false, off)
    for _, w in ipairs(cdWidgets) do Gray(w, BV("cdNumbers") == false, off) end
    if BV("cdNumbers") ~= false then Gray(colCd, BV("cdThemed") == true, off) end
    for _, b in ipairs(textBlocks) do
      local on = BV(b.pre .. "Show") ~= false
      for _, w in pairs(b.ws) do Gray(w, not on, off) end
      if on then Gray(b.col, BV(b.pre .. "Themed") == true, off) end
    end
    Gray(colGlow, BV("glowThemed") == true, off)
    local bgTex = BV("bgTexture") or "none"
    local nine = false
    for _, d in ipairs(AB().BG_TEXTURES) do if d.value == bgTex then nine = d.nine == true end end
    for _, w in ipairs({ colBg, slPadX, slPadY, slBgAlpha }) do Gray(w, bgTex == "none", off) end
    for _, w in ipairs({ slEdge, slBgBorder, colBgBorder }) do Gray(w, not nine, off) end
    -- Familier / postures : 10 boutons au plus ; totems : nombre fixe par Blizzard (emplacements appris)
    local def = AB().BAR_BY[Sel()]
    Gray(slCount, def.kind == "totem", off)
    if slCount.SetMinMaxValues then slCount:SetMinMaxValues(1, def.count) end
    if slPerRow.SetMinMaxValues then slPerRow:SetMinMaxValues(1, def.count) end
  end

  local function RefreshPos()
    slX:SetValue(BV("x") or 0)
    slY:SetValue(BV("y") or 0)
    LockLabel()
    showT:SetValue(GV("guiForceBars") == true)
  end

  RefreshAll = function()
    local m = AB()
    local opts = {}
    for _, def in ipairs(m.BARS) do
      local _, gid = m.GroupOf(def.key)
      local gname = m.GroupName(gid)
      local text = m.Label(def.key)
      if gname then text = text .. " (" .. gname .. ")" end
      opts[#opts + 1] = { value = def.key, text = text }
    end
    barDD:SetOptions(opts)
    barDD:SetValue(Sel())
    local gOpts, ids = { { value = "none", text = L["ACTIONBARS_BG_NONE"] } }, {}
    for id in pairs(m.Groups()) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (m.GroupName(a) or a) < (m.GroupName(b) or b) end)
    for _, id in ipairs(ids) do gOpts[#gOpts + 1] = { value = id, text = m.GroupName(id) or id } end
    ddGroup:SetOptions(gOpts)
    local _, gid = m.GroupOf(Sel())
    ddGroup:SetValue(gid or "none")
    toggle:SetValue(BV("enabled") ~= false)
    cbModule:SetChecked(GV("enabled") == true)
    for _, e in ipairs(bound) do
      local v = BV(e.key)
      if e.kind == "bool" then
        if e.w.SetChecked then e.w:SetChecked(v and true or false) else e.w:SetValue(v and true or false) end
      elseif e.kind == "color" then
        if type(v) == "table" then e.w:SetColor(v[1], v[2], v[3], v[4]) end
      elseif v ~= nil then
        e.w:SetValue(v)
      end
    end
    for _, e in ipairs(gbound) do
      if e.w ~= cbModule then
        local v = GV(e.key)
        if e.kind == "bool" then
          e.w:SetChecked(v and true or false)
        elseif e.kind == "color" then
          if type(v) == "table" then e.w:SetColor(v[1], v[2], v[3], v[4]) end
        elseif v ~= nil then
          e.w:SetValue(v)
        end
      end
    end
    RefreshPos()
    RefreshStates()
    RefreshPreview()
  end

  preview:SetScript("OnSizeChanged", function() RefreshPreview() end)
  ns.ActionBarsPageRefresh = function() if container:IsVisible() then RefreshAll() end end
  ns.ActionBarsPagePosChanged = function(key)
    if container:IsVisible() and key == Sel() then RefreshPos() end
  end
  container:HookScript("OnShow", function() RefreshAll() end)
  RefreshAll()
  if container:IsVisible() then PinUp(); GuiForce() end
end

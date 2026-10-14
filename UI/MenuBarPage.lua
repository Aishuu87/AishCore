-- UI/MenuBarPage.lua : page "Barre de menu" du GUI (logique : Modules/MenuBar.lua).
-- Apercu epingle en haut de la page (reste visible quand on defile) : clic sur un raccourci = choisir son action,
-- glisser un raccourci sur un autre = les echanger (animation), "+" de chaque cote = ajouter un raccourci.
-- Puis sections repliables (NewLayout) : general, couleurs et survol, arriere-plan, visibilite, horloge.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local PIN_H = 96

-- Confirmation de suppression d'un raccourci (glisse hors de l'apercu)
StaticPopupDialogs["AISD_CONFIRM_REMOVE_MENUBAR_SLOT"] = {
  text = L["MENUBAR_CONFIRM_REMOVE"],
  button1 = L["SETTINGS_CONFIRM"], button2 = L["SETTINGS_CANCEL"],
  OnAccept = function(self, data)
    if data and data.callback then data.callback() end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns.BuildMenuBarPage(container, W, NewLayout)
  local MB = ns.Modules and ns.Modules.MenuBar
  local ctx = NewLayout(container)
  local W2 = math.floor((W - 8) / 2)

  local function DB()
    ns.DB = ns.DB or {}
    ns.DB.menuBar = ns.DB.menuBar or {}
    return ns.DB.menuBar
  end

  -- Apercu epingle ---------------------------------------------------------------------------------
  local pin = CreateFrame("Frame", nil, container, "BackdropTemplate")
  pin:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  pin:SetBackdropColor(0.07, 0.065, 0.055, 1)
  pin:SetBackdropBorderColor(unpack(Theme.border))
  pin:SetClipsChildren(true)
  local strip = MB and MB.NewStrip(pin, true)
  local hint = pin:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 10)
  hint:SetTextColor(unpack(Theme.textDim))
  hint:SetPoint("BOTTOM", pin, "BOTTOM", 0, 6)
  hint:SetText(L["MENUBAR_PREVIEW_HINT"])

  local function Fit()
    if not strip then return end
    local full = strip:FullWidth()
    local avail = math.max(50, (pin:GetWidth() or W) - 24)
    local scale = math.min(1, avail / math.max(1, full))
    strip.frame:SetScale(scale)
    strip.frame:ClearAllPoints()
    strip.frame:SetPoint("CENTER", pin, "CENTER", 0, 8)
  end
  local function RefreshPreview()
    if not strip then return end
    strip:Layout()
    Fit()
  end
  pin:SetScript("OnSizeChanged", Fit)

  -- Changement de reglage : barre reelle + apercu, regroupes a une application par frame
  local pending = false
  local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      if MB then MB.ApplySettings() end
      RefreshPreview()
    end)
  end

  if strip then
    strip.onSlotClick = function(b)
      local items = {}
      local cur = b.actionId
      for _, a in ipairs(MB.ACTIONS) do
        if a.macro() then
          items[#items + 1] = {
            label = (a.id == cur and "|cffffd100> |r" or "   ") .. MB.ActionName(a.id),
            onClick = function()
              MB.SetSlot(b.side, b.idx, a.id)
              Changed()
            end,
          }
        end
      end
      items[#items + 1] = { separator = true }
      items[#items + 1] = {
        label = L["MENUBAR_REMOVE_SLOT"], color = { 1, 0.4, 0.4 },
        onClick = function()
          MB.RemoveSlot(b.side, b.idx)
          Changed()
        end,
      }
      SW.ShowContextMenu(items)
    end
    strip.onRemove = function(b)
      local side, idx, id = b.side, b.idx, b.actionId
      StaticPopup_Show("AISD_CONFIRM_REMOVE_MENUBAR_SLOT", MB.ActionName(id), nil, {
        callback = function()
          -- La liste a pu changer entre-temps : on ne retire que si le raccourci est toujours la
          if MB.GetSlots(side)[idx] == id then
            MB.RemoveSlot(side, idx)
            Changed()
          end
        end,
      })
    end
    strip.onAdd = function(side)
      if MB.AddSlot(side) then Changed() end
    end
    strip.onSwap = function(a, b)
      MB.SwapSlots(a.side, a.idx, b.side, b.idx)
      if MB then MB.ApplySettings() end
      RefreshPreview()
      strip:AnimateSwap(a, b)
    end
  end

  local function PinUp()
    if ns.SettingsPin then ns.SettingsPin(pin, PIN_H) end
    RefreshPreview()
  end
  container:HookScript("OnShow", PinUp)
  container:HookScript("OnHide", function()
    if ns.SettingsUnpin then ns.SettingsUnpin(pin) end
    if MB and MB.IsDragUnlocked() then MB.SetDragUnlocked(false) end
  end)

  -- Liaisons widget <-> cle de la DB --------------------------------------------------------------
  local bound = {}
  local function Bind(w, key, kind)
    bound[#bound + 1] = { w = w, key = key, kind = kind }
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      DB()[key] = v
      Changed()
    end
    return w
  end

  -- Page ---------------------------------------------------------------------------------------------
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_MENU_BAR"], W))
  local cbEnable = Bind(SW.CreateCheckbox(container, L["MENUBAR_ENABLE"], L["SETTINGS_CAT_MENU_BAR_TT"], W2), "enabled", "bool")
  local cbHideBlizz = Bind(SW.CreateCheckbox(container, L["MENUBAR_HIDE_BLIZZARD"], L["MENUBAR_HIDE_BLIZZARD_TT"], W2), "hideBlizzard", "bool")
  ctx:AddRow(8, cbEnable, cbHideBlizz)

  local dragBtn = SW.CreateActionBtn(container, L["MENUBAR_MOVE"], W2)
  local function RefreshDragBtn()
    dragBtn._lbl:SetText(MB and MB.IsDragUnlocked() and L["MENUBAR_LOCK"] or L["MENUBAR_MOVE"])
  end
  dragBtn:SetScript("OnClick", function()
    if MB then MB.SetDragUnlocked(not MB.IsDragUnlocked()) end
    RefreshDragBtn()
  end)
  ctx:Add(dragBtn)

  -- General
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["MENUBAR_SEC_GENERAL"], W))
  local slSize = Bind(SW.CreateSlider(container, L["MENUBAR_ICON_SIZE"], 12, 48, 1, W2), "iconSize", "number")
  local slGap = Bind(SW.CreateSlider(container, L["EXTRABARS_SPACING"], 0, 40, 1, W2), "spacing", "number")
  ctx:AddRow(8, slSize, slGap)
  ctx:Add(Bind(SW.CreateCheckbox(container, L["MENUBAR_TOOLTIP"], nil, W), "tooltip", "bool"))

  -- Couleurs et survol
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["MENUBAR_SEC_COLORS"], W))
  local cbDesat = Bind(SW.CreateCheckbox(container, L["MENUBAR_DESATURATE"], L["MENUBAR_DESATURATE_TT"], W2), "desaturate", "bool")
  local cbHover = Bind(SW.CreateCheckbox(container, L["MENUBAR_HOVER"], nil, W2), "hoverEnabled", "bool")
  ctx:AddRow(8, cbDesat, cbHover)
  -- Couleur + case "Couleur thematique" a droite : le selecteur est grise tant que la case est cochee
  local themedPairs = {}
  local function ThemedRow(label, key, themedKey, element)
    local col = Bind(SW.CreateColorButton(container, label, W2), key, "color")
    local tt = string.format(L["MENUBAR_THEMED_TT"], L[element])
    local cb = Bind(SW.CreateCheckbox(container, L["MENUBAR_THEMED"], tt, W2), themedKey, "bool")
    local blocker = CreateFrame("Frame", nil, col)
    blocker:SetAllPoints(col)
    blocker:SetFrameLevel(col:GetFrameLevel() + 20)
    blocker:EnableMouse(true)
    local function State(on)
      col:SetAlpha(on and 0.4 or 1)
      blocker:SetShown(on)
    end
    local orig = cb.onChanged
    cb.onChanged = function(v)
      if orig then orig(v) end
      State(v and true or false)
    end
    themedPairs[#themedPairs + 1] = { cb = cb, State = State, key = themedKey }
    return col, cb
  end
  local colIcon, cbIconThemed = ThemedRow(L["MENUBAR_ICON_COLOR"], "iconColor", "iconThemed", "COLORSMOD_ELEM_POWERTEXT")
  ctx:AddRowCentered(8, colIcon, cbIconThemed)
  local colHover, cbHoverThemed = ThemedRow(L["MENUBAR_HOVER_COLOR"], "hoverColor", "hoverThemed", "COLORSMOD_ELEM_POWERDOTSB")
  ctx:AddRowCentered(8, colHover, cbHoverThemed)
  ctx:Add(Bind(SW.CreateCheckbox(container, L["MENUBAR_HOVER_GROW"], nil, W), "hoverGrow", "bool"))

  -- Arriere-plan (memes reglages que les Barres dynamiques)
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["EXTRABARS_SEC_BACKGROUND"], W))
  ctx:Add(Bind(SW.CreateCheckbox(container, L["EXTRABARS_BG_SHOW"], nil, W), "bgEnabled", "bool"))
  local bgOpts = {}
  local EB = ns.Modules and ns.Modules.ExtraBars
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

  -- Visibilite
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  local cbCombat = Bind(SW.CreateCheckbox(container, L["SETTINGS_LOC_HIDE_COMBAT"], nil, W2), "hideInCombat", "bool")
  local slAlpha = Bind(SW.CreateSlider(container, L["SETTINGS_OPACITY"], 0, 1, 0.05, W2), "alpha", "number")
  ctx:AddRowCentered(8, cbCombat, slAlpha)
  local cbMouse = Bind(SW.CreateCheckbox(container, L["EXTRABARS_MOUSEOVER"], L["EXTRABARS_MOUSEOVER_TT"], W2), "mouseover", "bool")
  local slMouseAlpha = Bind(SW.CreateSlider(container, L["EXTRABARS_MOUSEOVER_ALPHA"], 0, 1, 0.05, W2), "mouseoverAlpha", "number")
  ctx:AddRowCentered(8, cbMouse, slMouseAlpha)

  -- Horloge
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["MENUBAR_SEC_CLOCK"], W))
  ctx:Add(Bind(SW.CreateCheckbox(container, L["MENUBAR_CLOCK_ENABLE"], nil, W), "clockEnabled", "bool"))
  local ddPos = Bind(SW.CreateDropdown(container, L["MENUBAR_CLOCK_POS"], {
    { value = "left",   text = L["MENUBAR_POS_LEFT"] },
    { value = "center", text = L["MENUBAR_POS_CENTER"] },
    { value = "right",  text = L["MENUBAR_POS_RIGHT"] },
  }, W2), "clockPos", "string")
  local cb24 = Bind(SW.CreateCheckbox(container, L["MENUBAR_CLOCK_24H"], nil, W2), "clock24", "bool")
  ctx:AddRowCentered(8, ddPos, cb24)
  local cbBlink = Bind(SW.CreateCheckbox(container, L["MENUBAR_CLOCK_BLINK"], L["MENUBAR_CLOCK_BLINK_TT"], W2), "clockBlink", "bool")
  local cbServer = Bind(SW.CreateCheckbox(container, L["MENUBAR_CLOCK_SERVER"], nil, W2), "clockServer", "bool")
  ctx:AddRow(8, cbBlink, cbServer)
  local ddFont = Bind(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), W2), "clockFont", "string")
  local ddOutline = Bind(SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), W2), "clockOutline", "string")
  ctx:AddRow(8, ddFont, ddOutline)
  ctx:Add(Bind(SW.CreateSlider(container, L["SETTINGS_FONT_SIZE"], 8, 48, 1, W2), "clockSize", "number"))
  local colClock, cbClockThemed = ThemedRow(L["SETTINGS_TEXT_COLOR"], "clockColor", "clockThemed", "COLORSMOD_ELEM_POWERCIRCLE")
  ctx:AddRowCentered(8, colClock, cbClockThemed)

  ctx:Spacer()
  ctx:Finalize()

  -- Relecture des valeurs depuis la DB (ou des defauts)
  local function RefreshAll()
    local cfg = ns.GetCfg("menuBar") or {}
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
    RefreshDragBtn()
    RefreshPreview()
  end
  container:HookScript("OnShow", RefreshAll)
  RefreshAll()
  if container:IsVisible() then PinUp() end
end

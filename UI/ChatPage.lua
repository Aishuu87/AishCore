-- UI/ChatPage.lua : page "Tchat" du GUI (logique : Modules/Chat.lua, notes : docs/CHAT.md).
-- Sections repliables (NewLayout) : texte, fond, animations, fondu, habillage, messages epures, onglets, couleurs.
-- Les reglages de Blizzard (whispers en onglet, couleurs des canaux) sont des CVars / API natives :
-- lus et ecrits directement, jamais copies dans le profil.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local function GetCVarValue(name)
  if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
  return GetCVar and GetCVar(name)
end
local function SetCVarValue(name, v)
  if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, v) elseif SetCVar then SetCVar(name, v) end
end

-- Texte explicatif sur toute la largeur
local function Note(container, text, W)
  local f = CreateFrame("Frame", nil, container)
  f:SetWidth(W)
  local fs = f:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Media.fontGui, 10)
  fs:SetPoint("TOPLEFT", 2, 0)
  fs:SetWidth(W - 4)
  fs:SetJustifyH("LEFT")
  fs:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3], 1)
  fs:SetText(text)
  f.text = fs
  f:SetHeight(math.max(14, (fs:GetStringHeight() or 12) + 4))
  return f
end

-- Types de discussion proposes a la couleur (libelles de Blizzard)
local COLOR_TYPES = {
  "SAY", "YELL", "EMOTE", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
  "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "WHISPER", "BN_WHISPER",
  "CHANNEL1", "CHANNEL2", "CHANNEL3", "CHANNEL4", "CHANNEL5",
}
-- Types concernes par les noms en couleur de classe
local CLASS_TYPES = { "SAY", "YELL", "EMOTE", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING",
  "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM" }
for i = 1, 20 do CLASS_TYPES[#CLASS_TYPES + 1] = "CHANNEL" .. i end

local function TypeLabel(t)
  local n = t:match("^CHANNEL(%d+)$")
  if n then
    local _, name = GetChannelName(tonumber(n))
    if type(name) == "string" and name ~= "" then return n .. ". " .. (name:match("^([^%-]+)") or name):gsub("%s+$", "") end
    return (_G.CHANNEL or "Channel") .. " " .. n
  end
  return _G["CHAT_MSG_" .. t] or t
end

function ns.BuildChatPage(container, W, NewLayout)
  local CH = ns.Modules and ns.Modules.Chat
  local ctx = NewLayout(container)
  local W2 = math.floor((W - 8) / 2)
  local W3 = math.floor((W - 16) / 3)

  local function DB()
    ns.DB = ns.DB or {}
    ns.DB.chat = ns.DB.chat or {}
    return ns.DB.chat
  end

  local pv   -- apercu (bloc epingle, plus bas)
  local pending = false
  local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      if CH then CH.ApplySettings() end
      if pv then pv:Refresh() end
    end)
  end

  local bound = {}
  local function Bind(w, key, kind)
    bound[#bound + 1] = { w = w, key = key, kind = kind }
    w._dbKey, w._subKey = "chat", key
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      DB()[key] = v
      Changed()
    end
    if kind == "number" then SW.TrackDB(w, function() return DB()[key] end) end
    return w
  end
  local function Check(label, key, tip, width) return Bind(SW.CreateCheckbox(container, label, tip, width or W2), key, "bool") end
  local function Slider(label, key, mn, mx, step, width) return Bind(SW.CreateSlider(container, label, mn, mx, step, width or W2), key, "number") end

  -- Bloc epingle : titre + interrupteur, apercu (faux tchat en boucle, cf. Chat.CreatePreview) et mode test du survol
  local TITLE_H, PREVIEW_H = 30, 190
  local pin = CreateFrame("Frame", nil, container)
  local title = SW.CreateSectionHeader(pin, L["SETTINGS_CAT_CHAT"] .. " (Beta)", W)
  title:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, 0)
  ctx:PinnedTitle(title, pin)
  local box = CreateFrame("Frame", nil, pin, "BackdropTemplate")
  box:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, -TITLE_H)
  box:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 0, -TITLE_H)
  box:SetHeight(PREVIEW_H)
  box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  box:SetBackdropBorderColor(unpack(Theme.border))
  box:SetClipsChildren(true)
  SW.ApplyPreviewScreen(box)
  pv = CH and CH.CreatePreview and CH.CreatePreview(box)
  if pv then
    pv:SetPoint("TOPLEFT", box, "TOPLEFT", 16, -10)
    pv:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -190, 10)
    pv:SetFrameLevel(box:GetFrameLevel() + 5)
  end
  local testT = SW.CreateToggle(box, 40)
  testT:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 8)
  testT:SetFrameLevel(box:GetFrameLevel() + 60)
  local testLbl = box:CreateFontString(nil, "OVERLAY")
  testLbl:SetFont(ns.Media.fontGui, 10)
  testLbl:SetTextColor(1, 1, 1, 1)
  testLbl:SetShadowColor(0, 0, 0, 0.9)
  testLbl:SetShadowOffset(1, -1)
  testLbl:SetPoint("RIGHT", testT, "LEFT", -6, 0)
  testLbl:SetText(L["CHAT_PREVIEW_TEST"])
  local testHint = box:CreateFontString(nil, "OVERLAY")
  testHint:SetFont(ns.Media.fontGui, 9)
  testHint:SetTextColor(0.8, 0.8, 0.8, 1)
  testHint:SetShadowColor(0, 0, 0, 0.9)
  testHint:SetShadowOffset(1, -1)
  testHint:SetWidth(170)
  testHint:SetJustifyH("RIGHT")
  testHint:SetPoint("BOTTOMRIGHT", testT, "TOPRIGHT", 0, 6)
  testHint:SetText(L["CHAT_PREVIEW_TEST_TT"])
  testT:SetValue(false)
  testT.onChanged = function(v) if pv then pv:SetTest(v) end end
  local function PinUp()
    if ns.SettingsPin then ns.SettingsPin(pin, TITLE_H + PREVIEW_H) end
  end
  container:HookScript("OnShow", PinUp)
  container:HookScript("OnHide", function()
    if ns.SettingsUnpin then ns.SettingsUnpin(pin) end
    testT:SetValue(false)
    if pv then pv:SetTest(false) end
  end)

  local cbEnable = ctx:TitleToggle(Check(L["CHAT_ENABLE"], "enabled", L["CHAT_ENABLE_TT"], W))
  local enableChanged = cbEnable.onChanged
  cbEnable.onChanged = function(v)
    enableChanged(v)
    if not v then StaticPopup_Show("AISHCORE_CHAT_RELOAD") end
  end

  -- Texte ------------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_TEXT"], W))
  local ddFont = Bind(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), W2), "font", "string")
  local ddOutline = Bind(SW.CreateDropdown(container, L["SETTINGS_TEXT_OUTLINE"], {
    { value = "NONE",         text = L["CHAT_OUTLINE_NONE"] },
    { value = "OUTLINE",      text = L["TEXT_OUTLINE_THIN"] },
    { value = "THICKOUTLINE", text = L["TEXT_OUTLINE_THICK"] },
  }, W2), "outline", "string")
  ctx:AddRow(8, ddFont, ddOutline)
  local cbSize = Check(L["CHAT_FONT_SIZE_CUSTOM"], "fontSizeCustom", L["CHAT_FONT_SIZE_CUSTOM_TT"])
  local slSize = Slider(L["SETTINGS_FONT_SIZE"], "fontSize", 8, 32, 1)
  ctx:AddRowCentered(8, cbSize, slSize)
  ctx:Depends(cbSize, { slSize })
  local cbShadow = ctx:Add(Check(L["CHAT_SHADOW"], "shadow", L["CHAT_SHADOW_TT"], W))
  local slShA = Slider(L["CHAT_SHADOW_ALPHA"], "shadowAlpha", 0, 1, 0.05, W3)
  local slShO = Slider(L["CHAT_SHADOW_OFFSET"], "shadowOffset", 0, 3, 0.5, W3)
  local slSpacing = Slider(L["CHAT_SPACING"], "spacing", 0, 10, 1, W3)
  ctx:AddRow(8, slShA, slShO, slSpacing)
  ctx:Depends(cbShadow, { slShA, slShO })

  -- Fond -------------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_BACKGROUND"], W))
  local ddBg = Bind(SW.CreateDropdown(container, L["CHAT_BG_STYLE"], {
    { value = "shadow",   text = L["CHAT_BG_SHADOW"] },
    { value = "solid",    text = L["CHAT_BG_SOLID"] },
    { value = "blizzard", text = L["CHAT_BG_BLIZZARD"] },
    { value = "none",     text = L["CHAT_BG_NONE"] },
  }, W2), "bgStyle", "string")
  local colBg = Bind(SW.CreateColorButton(container, L["CHAT_BG_COLOR"], W2), "bgColor", "color")
  ctx:AddRow(8, ddBg, colBg)
  local slPad = Slider(L["CHAT_BG_PAD"], "bgPad", 0, 40, 1, W3)
  local slEdge = Slider(L["CHAT_BG_EDGE"], "bgEdge", 0, 64, 1, W3)
  local slBorder = Slider(L["EXTRABARS_BG_BORDER_SIZE"], "bgBorderSize", 0, 4, 1, W3)
  ctx:AddRow(8, slPad, slEdge, slBorder)
  local colBorder = Bind(SW.CreateColorButton(container, L["EXTRABARS_BG_BORDER_COLOR"], W2), "bgBorderColor", "color")
  local cbBgHover = Check(L["CHAT_BG_HOVER"], "bgHover", L["CHAT_BG_HOVER_TT"])
  ctx:AddRow(8, colBorder, cbBgHover)
  ctx:Add(Note(container, L["CHAT_BG_NOTE"], W))

  -- Animations -------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_ANIM"], W))
  local cbIn = Check(L["CHAT_ANIM_IN"], "animIn", L["CHAT_ANIM_IN_TT"])
  local cbPush = Check(L["CHAT_ANIM_PUSH"], "animPush", L["CHAT_ANIM_PUSH_TT"])
  ctx:AddRow(8, cbIn, cbPush)
  local slDur = Slider(L["CHAT_ANIM_DURATION"], "animDuration", 0.1, 1, 0.05)
  local slOff = Slider(L["CHAT_ANIM_OFFSET"], "animOffset", 0, 60, 1)
  ctx:AddRow(8, slDur, slOff)
  ctx:Depends(cbIn, { slOff })

  -- Fondu ------------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_FADE"], W))
  local cbFade = ctx:Add(Check(L["CHAT_FADE"], "fade", L["CHAT_FADE_TT"], W))
  local slAfter = Slider(L["CHAT_FADE_AFTER"], "fadeAfter", 5, 600, 5)
  local slFadeDur = Slider(L["CHAT_FADE_DURATION"], "fadeDuration", 0.5, 10, 0.5)
  ctx:AddRow(8, slAfter, slFadeDur)
  local cbReveal = Check(L["CHAT_REVEAL_HOVER"], "revealOnHover", L["CHAT_REVEAL_HOVER_TT"])
  local slHold = Slider(L["CHAT_HOVER_HOLD"], "hoverHold", 0, 5, 0.25)
  ctx:AddRowCentered(8, cbReveal, slHold)
  ctx:Depends(cbFade, { slAfter, slFadeDur, cbReveal })

  -- Horodatage : colonne a gauche du texte (l'horodatage natif de Blizzard est coupe par le module, cf. ApplySettings)
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_TIMESTAMPS"], W))
  local cbTs = ctx:Add(Check(L["CHAT_TIMESTAMPS_ENABLE"], "timestamps", L["CHAT_TIMESTAMPS_ENABLE_TT"], W))
  local tsOpts = {}
  for _, f in ipairs({ "%H:%M", "%H:%M:%S", "%I:%M", "%I:%M:%S", "%I:%M %p", "%I:%M:%S %p" }) do
    tsOpts[#tsOpts + 1] = { value = f, text = date(f) }
  end
  local ddTs = Bind(SW.CreateDropdown(container, L["CHAT_TIMESTAMP_FORMAT"], tsOpts, W2), "timestampFormat", "string")
  local cbTsHover = Check(L["CHAT_TIMESTAMP_HOVER"], "timestampHover", L["CHAT_TIMESTAMP_HOVER_TT"])
  ctx:AddRowCentered(8, ddTs, cbTsHover)
  ctx:Depends(cbTs, { ddTs, cbTsHover })

  -- Habillage --------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_SKIN"], W))
  ctx:AddRow(8, Check(L["CHAT_HIDE_BUTTONS"], "hideButtons", L["CHAT_HIDE_BUTTONS_TT"]),
    Check(L["CHAT_HIDE_SCROLLBAR"], "hideScrollBar"))
  ctx:Add(Check(L["CHAT_STYLE_EDITBOX"], "styleEditBox", nil, W))
  ctx:AddRow(8, Check(L["CHAT_COPY_BUTTON"], "copyButton", L["CHAT_COPY_BUTTON_TT"]),
    Check(L["CHAT_JUMP_BUTTON"], "jumpButton", L["CHAT_JUMP_BUTTON_TT"]))
  local colAccent = Bind(SW.CreateColorButton(container, L["CHAT_ACCENT"], W2), "accentColor", "color")
  local cbAccentTheme = Check(L["SETTINGS_AFK_USE_THEME_COLORS"], "accentThemed", L["CHAT_ACCENT_THEMED_TT"])
  ctx:AddRowCentered(8, colAccent, cbAccentTheme)
  ctx:Depends(cbAccentTheme, { colAccent }, true)

  -- Onglets (apparence, disposition) ----------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_TABSTYLE"], W))
  local cbStyleTabs = Check(L["CHAT_STYLE_TABS"], "styleTabs", L["CHAT_STYLE_TABS_TT"])
  ctx:AddRow(8, cbStyleTabs, Check(L["CHAT_TABS_HOVER"], "tabsHover", L["CHAT_TABS_HOVER_TT"]))
  local ddLayout = Bind(SW.CreateDropdown(container, L["CHAT_TAB_LAYOUT"], {
    { value = "horizontal", text = L["CHAT_TAB_LAYOUT_H"] },
    { value = "vertical",   text = L["CHAT_TAB_LAYOUT_V"] },
  }, W2), "tabLayout", "string")
  local ddTabFont = Bind(SW.CreateDropdown(container, L["SETTINGS_FONT"], ns.GetFontList(), W2), "tabFont", "string")
  ctx:AddRow(8, ddLayout, ddTabFont)
  local ddVStyle = Bind(SW.CreateDropdown(container, L["CHAT_TAB_VSTYLE"], {
    { value = "icon", text = L["CHAT_TAB_VSTYLE_ICON"] },
    { value = "text", text = L["CHAT_TAB_VSTYLE_TEXT"] },
  }, W2), "tabVStyle", "string")
  local slTabSize = Slider(L["SETTINGS_FONT_SIZE"], "tabFontSize", 8, 24, 1, W2)
  ctx:AddRow(8, ddVStyle, slTabSize)
  local slVW = Slider(L["CHAT_TAB_VWIDTH"], "tabVWidth", 20, 48, 1, W3)
  local slVTW = Slider(L["CHAT_TAB_VTEXTWIDTH"], "tabVTextWidth", 40, 200, 5, W3)
  local slVSp = Slider(L["CHAT_TAB_VSPACING"], "tabVSpacing", 0, 12, 1, W3)
  ctx:AddRow(8, slVW, slVTW, slVSp)
  local slVX = Slider(L["CHAT_TAB_VX"], "tabVX", -400, 400, 1)
  local slVY = Slider(L["CHAT_TAB_VY"], "tabVY", -400, 400, 1)
  ctx:AddRow(8, slVX, slVY)
  local colActive = Bind(SW.CreateColorButton(container, L["CHAT_TAB_ACTIVE"], W2), "tabColorActive", "color")
  local cbActiveAccent = Check(L["CHAT_TAB_ACTIVE_ACCENT"], "tabActiveAccent", L["CHAT_TAB_ACTIVE_ACCENT_TT"])
  ctx:AddRowCentered(8, colActive, cbActiveAccent)
  ctx:Depends(cbActiveAccent, { colActive }, true)
  local colInactive = Bind(SW.CreateColorButton(container, L["CHAT_TAB_INACTIVE"], W3), "tabColorInactive", "color")
  local colWhisper = Bind(SW.CreateColorButton(container, L["CHAT_TAB_WHISPER"], W3), "tabColorWhisper", "color")
  local colAlert = Bind(SW.CreateColorButton(container, L["CHAT_TAB_ALERT"], W3), "tabColorAlert", "color")
  ctx:AddRow(8, colInactive, colWhisper, colAlert)
  local colBN = Bind(SW.CreateColorButton(container, L["CHAT_TAB_BN"], W3), "tabColorBN", "color")
  ctx:Add(colBN)
  -- fond de la barre verticale : texture des Extra Barres (grunge, doux, plein...) et opacite des boutons
  local EBm = ns.Modules and ns.Modules.ExtraBars
  local barOpts = { { value = "none", text = L["CHAT_BG_NONE"] } }
  for _, d in ipairs(EBm and EBm.BG_TEXTURES or {}) do
    barOpts[#barOpts + 1] = { value = d.value, text = L["EXTRABARS_BG_TEX_" .. d.value:upper()] }
  end
  local ddBarBg = Bind(SW.CreateDropdown(container, L["CHAT_TAB_VBAR_BG"], barOpts, W2), "tabVBarBg", "string")
  local colBar = Bind(SW.CreateColorButton(container, L["CHAT_TAB_VBAR_COLOR"], W2), "tabVBarColor", "color")
  ctx:AddRow(8, ddBarBg, colBar)
  local slBarPad = Slider(L["CHAT_TAB_VBAR_PAD"], "tabVBarPad", 0, 30, 1)
  local slBtnA = Slider(L["CHAT_TAB_VBTN_ALPHA"], "tabVBtnAlpha", 0, 1, 0.05)
  ctx:AddRow(8, slBarPad, slBtnA)
  ctx:Depends(cbStyleTabs, { ddTabFont, slTabSize, colActive, cbActiveAccent, colInactive, colWhisper, colAlert, colBN })
  ctx:Add(Note(container, L["CHAT_TAB_V_NOTE"], W))

  -- Messages epures --------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_CLEAN"], W))
  ctx:AddRow(8, Check(L["CHAT_CLEAN_MONEY"], "cleanMoney"), Check(L["CHAT_CLEAN_CURRENCY"], "cleanCurrency"))
  local cbLoot = Check(L["CHAT_CLEAN_LOOT"], "cleanLoot")
  local cbIcons = Check(L["CHAT_LOOT_ICONS"], "lootIcons")
  ctx:AddRow(8, cbLoot, cbIcons)
  local qOpts = { { value = 0, text = L["CHAT_QUALITY_ALL"] } }
  for q = 2, 4 do
    local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    local col = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if col and col.hex then name = col.hex .. name .. "|r" end
    qOpts[#qOpts + 1] = { value = q, text = string.format(L["CHAT_QUALITY_MIN"], name) }
  end
  local ddQ = ctx:Add(Bind(SW.CreateDropdown(container, L["CHAT_OTHERS_LOOT"], qOpts, W2), "othersLootQuality", "number"))
  ctx:Depends(cbLoot, { cbIcons, ddQ })
  ctx:AddRow(8, Check(L["CHAT_CLEAN_XP"], "cleanXP"), Check(L["CHAT_CLEAN_REP"], "cleanRep"))
  ctx:AddRow(8, Check(L["CHAT_CLEAN_SKILL"], "cleanSkill"), Check(L["CHAT_CLEAN_HONOR"], "cleanHonor"))
  ctx:AddRow(8, Check(L["CHAT_CLEAN_ZONE"], "cleanZone", L["CHAT_CLEAN_ZONE_TT"]), Check(L["CHAT_CLEAN_FRIENDS"], "cleanFriends"))
  ctx:AddRow(8, Check(L["CHAT_CLEAN_QUEST"], "cleanQuest", L["CHAT_CLEAN_QUEST_TT"]), Check(L["CHAT_HIDE_AFK"], "hideAFK"))
  ctx:Add(Check(L["CHAT_SHORT_CHANNELS"], "shortChannels", L["CHAT_SHORT_CHANNELS_TT"], W))

  -- Apercu : message d'origine -> version epuree
  local ex = CreateFrame("Frame", nil, container, "BackdropTemplate")
  ex:SetWidth(W)
  ex:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  ex:SetBackdropColor(0, 0, 0, 0.35)
  ex:SetBackdropBorderColor(unpack(Theme.border))
  ex.rows = {}
  local function FillExamples()
    local list = CH and CH.Examples and CH.Examples() or {}
    local y = -8
    for i, pair in ipairs(list) do
      local row = ex.rows[i]
      if not row then
        row = {}
        row.a = ex:CreateFontString(nil, "OVERLAY")
        row.a:SetFont(ns.FONT_FALLBACK, 11, "")
        row.a:SetWidth(W / 2 - 24)
        row.a:SetJustifyH("LEFT")
        row.a:SetWordWrap(false)
        row.a:SetTextColor(0.62, 0.62, 0.62)
        row.b = ex:CreateFontString(nil, "OVERLAY")
        row.b:SetFont(ns.FONT_FALLBACK, 12, "")
        row.b:SetShadowOffset(1, -1)
        row.b:SetWidth(W / 2 - 24)
        row.b:SetJustifyH("LEFT")
        row.arrow = ex:CreateFontString(nil, "OVERLAY")
        row.arrow:SetFont(ns.FONT_FALLBACK, 11, "")
        row.arrow:SetTextColor(1, 0.82, 0.2)
        row.arrow:SetText(">")
        ex.rows[i] = row
      end
      row.a:ClearAllPoints(); row.a:SetPoint("TOPLEFT", ex, "TOPLEFT", 10, y)
      row.arrow:ClearAllPoints(); row.arrow:SetPoint("TOP", ex, "TOP", 0, y)
      row.b:ClearAllPoints(); row.b:SetPoint("TOPLEFT", ex, "TOP", 14, y)
      row.a:SetText((pair[1]:gsub("|H.-|h(.-)|h", "%1")))
      row.b:SetText(pair[2])
      y = y - 18
    end
    for i = #list + 1, #ex.rows do ex.rows[i].a:SetText(""); ex.rows[i].b:SetText(""); ex.rows[i].arrow:SetText("") end
    ex:SetHeight(math.max(20, -y + 4))
  end
  FillExamples()
  ctx:Add(ex)

  -- Onglets et discussions -------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_TABS"], W))
  local modes = {
    { value = "inline",            text = L["CHAT_WHISPER_INLINE"] },
    { value = "popout",            text = L["CHAT_WHISPER_POPOUT"] },
    { value = "popout_and_inline", text = L["CHAT_WHISPER_BOTH"] },
  }
  local ddWhisper = SW.CreateDropdown(container, L["CHAT_WHISPER_MODE"], modes, W2)
  ddWhisper.onChanged = function(v) SetCVarValue("whisperMode", v) end
  local ddBN = SW.CreateDropdown(container, L["CHAT_BN_WHISPER_MODE"], modes, W2)
  ddBN.onChanged = function(v) SetCVarValue("bnWhisperMode", v) end
  ctx:AddRow(8, ddWhisper, ddBN)
  ctx:Add(Note(container, L["CHAT_WHISPER_NOTE"], W))
  -- Style de saisie (CVar native chatStyle) : en "im", chaque onglet a sa saisie, qui garde son type (whisper vers
  -- l'interlocuteur dans son onglet, /p ou /r collant dans l'onglet Groupe). Applique au /reload.
  local ddStyle = SW.CreateDropdown(container, L["CHAT_INPUT_STYLE"], {
    { value = "im",      text = L["CHAT_INPUT_IM"] },
    { value = "classic", text = L["CHAT_INPUT_CLASSIC"] },
  }, W2)
  ddStyle.onChanged = function(v)
    if GetCVarValue("chatStyle") ~= v then
      SetCVarValue("chatStyle", v)
      StaticPopup_Show("AISHCORE_CHAT_RELOAD")
    end
  end
  ctx:Add(ddStyle)
  ctx:Add(Note(container, L["CHAT_INPUT_STYLE_NOTE"], W))

  local cbClass = SW.CreateCheckbox(container, L["CHAT_CLASS_COLORS"], L["CHAT_CLASS_COLORS_TT"], W2)
  cbClass.onChanged = function(v)
    if GetCVarValue("chatClassColorOverride") ~= nil then SetCVarValue("chatClassColorOverride", v and "0" or "1") end
    if SetChatColorNameByClass then
      for _, t in ipairs(CLASS_TYPES) do if ChatTypeInfo and ChatTypeInfo[t] then pcall(SetChatColorNameByClass, t, v) end end
    end
  end
  ctx:Add(cbClass)

  local btnGroup = SW.CreateActionBtn(container, L["CHAT_GROUP_TAB_CREATE"], W2)
  local function RefreshGroupBtn()
    local exists = CH and CH.FindGroupTab and CH.FindGroupTab()
    btnGroup._lbl:SetText(exists and L["CHAT_GROUP_TAB_EXISTS"] or L["CHAT_GROUP_TAB_CREATE"])
  end
  btnGroup:SetScript("OnClick", function()
    if CH and not CH.FindGroupTab() then CH.CreateGroupTab() end
    RefreshGroupBtn()
  end)
  -- Pas de bouton vers les reglages de Blizzard : ouverts depuis l'addon, ils contamineraient la configuration du
  -- tchat (taint). Simple indication du chemin natif.
  ctx:Add(btnGroup)
  ctx:Add(Note(container, L["CHAT_GROUP_TAB_NOTE"], W))
  ctx:Add(Note(container, L["CHAT_BLIZZARD_SETTINGS"], W))

  -- Couleurs des canaux (couleurs de Blizzard, communes a tous les personnages) -----------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CHAT_SEC_COLORS"], W))
  local colorBtns = {}
  local row = {}
  for _, t in ipairs(COLOR_TYPES) do
    if ChatTypeInfo and ChatTypeInfo[t] then
      local b = SW.CreateColorButton(container, TypeLabel(t), W3)
      b._chatType = t
      b.onChanged = function(v)
        if ChangeChatColor then ChangeChatColor(t, v[1], v[2], v[3]) end
      end
      colorBtns[#colorBtns + 1] = b
      row[#row + 1] = b
      if #row == 3 then ctx:AddRow(8, row[1], row[2], row[3]); row = {} end
    end
  end
  if #row > 0 then ctx:AddRow(8, unpack(row)) end

  -- Habillage retire (textures de Blizzard videes) : elles ne reviennent qu'au /reload
  for _, e in ipairs(bound) do
    if e.key == "styleTabs" or e.key == "styleEditBox" or e.key == "bgStyle" then
      local orig = e.w.onChanged
      e.w.onChanged = function(v)
        orig(v)
        if v == false or v == "blizzard" then StaticPopup_Show("AISHCORE_CHAT_RELOAD") end
      end
    end
  end

  ctx:Spacer()
  ctx:Finalize()

  local function RefreshAll()
    local cfg = ns.GetCfg("chat") or {}
    for _, e in ipairs(bound) do
      local v = cfg[e.key]
      if e.kind == "bool" then
        e.w:SetChecked(v and true or false)
      elseif e.kind == "color" then
        if type(v) == "table" then e.w:SetColor(v[1], v[2], v[3], v[4]) end
      elseif v ~= nil then
        e.w:SetValue(v)
      end
    end
    ddWhisper:SetValue(GetCVarValue("whisperMode") or "inline")
    ddBN:SetValue(GetCVarValue("bnWhisperMode") or "inline")
    ddStyle:SetValue(GetCVarValue("chatStyle") == "classic" and "classic" or "im")
    local override = GetCVarValue("chatClassColorOverride")
    local classOn
    if override ~= nil then classOn = override == "0"
    else classOn = ChatTypeInfo and ChatTypeInfo.SAY and ChatTypeInfo.SAY.colorNameByClass end
    cbClass:SetChecked(classOn and true or false)
    for _, b in ipairs(colorBtns) do
      local info = ChatTypeInfo[b._chatType]
      if info then b:SetColor(info.r or 1, info.g or 1, info.b or 1, 1) end
    end
    RefreshGroupBtn()
    FillExamples()
  end
  container:HookScript("OnShow", RefreshAll)
  RefreshAll()
  if container:IsVisible() then PinUp() end
end

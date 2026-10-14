-- UI/PatchNotesPage.lua : page "Patch Notes" du GUI (donnees : Data/PatchNotes.lua).
-- Onglets en haut (une version par onglet, la plus recente ouverte par defaut), puis les notes de la version.
-- Chaque titre de partie est un en-tete de section natif (pliable, replie par defaut, etat memorise par
-- NewLayout). Un titre lie porte une icone a droite qui ouvre ses reglages ; une puce qui cite un element de
-- l'addon (lien explicite ou terme de ns.PatchNoteLinks) est cliquable de la meme facon.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local WHITE = "Interface\\Buttons\\WHITE8x8"
local GEAR  = "Interface\\Buttons\\UI-OptionsButton"
local TAB_H, TAB_GAP = 24, 6
local FOREVER_TAG = "[Forever]"
local FOREVER_HEX = "66ccff"

-- Onglet selectionne (memoire de session) : index dans ns.PatchNotes, 1 = derniere version
ns._patchNotesSel = ns._patchNotesSel or 1

local IS_FR = (GetLocale() == "frFR")

local function LineText(line)
  return (IS_FR and line.fr) or line.t or ""
end

-- Premier terme connu dans la ligne (ns.PatchNoteLinks, deja tries du plus long au plus court)
local function FindLink(text)
  local low = text:lower()
  for _, l in ipairs(ns.PatchNoteLinks or {}) do
    local s, e = low:find(l.match, 1, true)
    if s then return l, s, e end
  end
end

-- Colore le terme lie ; etendu jusqu'a la fin du mot ("missing buff" -> "missing buffs")
local function Colorize(text, s, e, hex)
  while e < #text and text:sub(e + 1, e + 1):match("[%w']") do e = e + 1 end
  return text:sub(1, s - 1) .. "|cff" .. hex .. text:sub(s, e) .. "|r" .. text:sub(e + 1)
end

-- Etiquette [Forever] coloree (les emoji ne passent pas dans les polices WoW)
local function TagForever(text)
  local s, e = text:find(FOREVER_TAG, 1, true)
  if not s then return text end
  return text:sub(1, s - 1) .. "|cff" .. FOREVER_HEX .. FOREVER_TAG .. "|r" .. text:sub(e + 1)
end

local function Hex(c)
  return string.format("%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function LinkLabel(link)
  local label = (ns.SettingsCategoryLabel and ns.SettingsCategoryLabel(link.page)) or link.page
  if link.section and L[link.section] then label = label .. " > " .. L[link.section] end
  return label
end

local function OpenLink(link)
  local panel = ns.SettingsPanel
  if not (panel and panel.GoToElement and link and link.page) then return end
  local section = link.section and L[link.section]
  panel:GoToElement(link.page, section and section:upper())
  PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function ShowLinkTip(owner, link)
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
  GameTooltip:SetText(string.format(L["PATCHNOTES_CLICK_TT"], LinkLabel(link)), 1, 1, 1)
  GameTooltip:Show()
end

-- Zone cliquable posee sur une ligne liee : cadre + teinte d'accent au survol, infobulle, clic = ouvrir
local function MakeLinkZone(parent, fs, link)
  local z = CreateFrame("Button", nil, parent, "BackdropTemplate")
  z:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 2)
  z:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -2)
  z:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  local ac = Theme.accentText or Theme.gold or { 1, 0.82, 0.3 }
  z:SetBackdropColor(ac[1], ac[2], ac[3], 0)
  z:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0)
  z:SetScript("OnEnter", function(self)
    self:SetBackdropColor(ac[1], ac[2], ac[3], 0.12)
    self:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0.85)
    ShowLinkTip(self, link)
  end)
  z:SetScript("OnLeave", function(self)
    self:SetBackdropColor(ac[1], ac[2], ac[3], 0)
    self:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0)
    GameTooltip:Hide()
  end)
  z:SetScript("OnClick", function() OpenLink(link) end)
  return z
end

-- Icone "reglages" a droite d'un titre lie : le clic sur le titre plie / deplie, l'icone ouvre la page.
-- Niveau de frame au-dessus de la hitbox de pli (MakeHeaderCollapsible, posee a +1 au Finalize).
local function MakeHeaderLink(header, link)
  local ac = Theme.accentText or Theme.gold or { 1, 0.82, 0.3 }
  local b = CreateFrame("Button", nil, header)
  b:SetSize(18, 18)
  b:SetPoint("RIGHT", header, "RIGHT", -2, 0)
  b:SetFrameLevel(header:GetFrameLevel() + 5)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", -3, 3); bg:SetPoint("BOTTOMRIGHT", 3, -3)
  bg:SetColorTexture(0.06, 0.06, 0.08, 1)
  local ic = b:CreateTexture(nil, "ARTWORK")
  ic:SetAllPoints()
  ic:SetTexture(GEAR)
  ic:SetVertexColor(ac[1], ac[2], ac[3], 0.75)
  b:SetScript("OnEnter", function(self)
    ic:SetVertexColor(1, 1, 1, 1)
    ShowLinkTip(self, link)
  end)
  b:SetScript("OnLeave", function()
    ic:SetVertexColor(ac[1], ac[2], ac[3], 0.75)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function() OpenLink(link) end)
  return b
end

-- Puce : cadre de la largeur du contenu (passe par ctx:Add, donc suit les plis)
local function MakeItem(container, W, line, hex, tn, dim)
  local indent = (line.lvl == 2) and 36 or 18
  local text = LineText(line)
  local link = line.link
  if link then
    text = "|cff" .. hex .. text .. "|r"
  else
    local l, s, e = FindLink(text)
    if l then link = l; text = Colorize(text, s, e, hex) end
  end
  text = TagForever(text)

  local holder = CreateFrame("Frame", nil, container)
  holder:SetWidth(W)
  local dot = holder:CreateFontString(nil, "OVERLAY")
  dot:SetFont(ns.Media.fontGui, 11)
  dot:SetTextColor(dim[1], dim[2], dim[3])
  dot:SetText(line.lvl == 2 and "-" or "\226\128\162")   -- puce
  dot:SetPoint("TOPLEFT", holder, "TOPLEFT", indent - 11, -2)
  local fs = holder:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Media.fontGui, 11)
  fs:SetTextColor(tn[1], tn[2], tn[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetWidth(W - indent - 10)
  fs:SetPoint("TOPLEFT", holder, "TOPLEFT", indent, -2)
  fs:SetText(text)
  if link then MakeLinkZone(holder, fs, link) end
  holder:SetHeight(math.ceil(fs:GetStringHeight()) + 5)
  return holder
end

function ns.BuildPatchNotesPage(container, W, NewLayout)
  local ctx = NewLayout(container)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_CAT_PATCH_NOTES"], W))
  local notes = ns.PatchNotes or {}
  if #notes == 0 then
    local holder = CreateFrame("Frame", nil, container); holder:SetSize(W, 20)
    local fs = holder:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.Media.fontGui, 11)
    fs:SetText(L["PATCHNOTES_EMPTY"])
    fs:SetPoint("TOPLEFT")
    ctx:Add(holder)
    ctx:Finalize()
    return
  end
  local sel = math.max(1, math.min(ns._patchNotesSel or 1, #notes))
  local ac = Theme.accentText or Theme.gold or { 1, 0.82, 0.3 }
  local tn = Theme.textNormal or { 0.9, 0.9, 0.9 }
  local dim = Theme.textDim or { 0.6, 0.6, 0.6 }

  -- Onglets (passent a la ligne si besoin)
  local tabs = CreateFrame("Frame", nil, container)
  tabs:SetWidth(W)
  local x, y = 0, 0
  for i, n in ipairs(notes) do
    local b = CreateFrame("Button", nil, tabs, "BackdropTemplate")
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(ns.Media.fontGui, 11)
    fs:SetText("v" .. n.version)
    fs:SetPoint("CENTER")
    local bw = math.max(58, math.floor(fs:GetStringWidth() + 22))
    if x > 0 and x + bw > W then x = 0; y = y + TAB_H + 4 end
    b:SetSize(bw, TAB_H)
    b:SetPoint("TOPLEFT", tabs, "TOPLEFT", x, -y)
    x = x + bw + TAB_GAP
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    local on = (i == sel)
    if on then
      b:SetBackdropColor(ac[1], ac[2], ac[3], 0.18)
      b:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1)
      fs:SetTextColor(1, 1, 1)
    else
      b:SetBackdropColor(0.08, 0.08, 0.1, 0.9)
      b:SetBackdropBorderColor(unpack(Theme.border or { 0.3, 0.3, 0.3, 1 }))
      fs:SetTextColor(dim[1], dim[2], dim[3])
      b:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 1) end)
      b:SetScript("OnLeave", function() fs:SetTextColor(dim[1], dim[2], dim[3]) end)
      b:SetScript("OnClick", function()
        ns._patchNotesSel = i
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("patchNotes") end
      end)
    end
  end
  tabs:SetHeight(y + TAB_H)
  ctx:Add(tabs)
  ctx:Spacer(8)

  -- Titre de la version selectionnee
  local n = notes[sel]
  local th = CreateFrame("Frame", nil, container)
  th:SetWidth(W)
  local title = th:CreateFontString(nil, "OVERLAY")
  title:SetFont(ns.Media.fontTitle, 15)
  title:SetTextColor(ac[1], ac[2], ac[3])
  title:SetPoint("TOPLEFT", th, "TOPLEFT", 0, 0)
  title:SetText(string.format(L["PATCHNOTES_VERSION"], n.version)
    .. (n.date and ("  |cff" .. Hex(dim) .. n.date .. "|r") or ""))
  th:SetHeight(math.ceil(title:GetStringHeight()) + 4)
  ctx:Add(th)
  ctx:Spacer(4)

  -- Parties : un en-tete natif par titre, ses puces dessous
  local hex = Hex(ac)
  local inSection = false
  for _, line in ipairs(n.lines or {}) do
    if line.k == "h" then
      if inSection then ctx:Spacer(6) end
      local text = LineText(line)
      local h = SW.CreateSectionHeader(container, text, W)
      local link = line.link
      if not link then link = FindLink(text) end
      if link then MakeHeaderLink(h, link) end
      ctx:Add(h)
      inSection = true
    else
      ctx:Add(MakeItem(container, W, line, hex, tn, dim))
    end
  end
  ctx:Finalize()
end

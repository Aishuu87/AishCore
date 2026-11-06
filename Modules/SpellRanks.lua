-- Modules/SpellRanks.lua : "Nouveaux rangs de competence" (QoL, grimoire classique de Forever).
-- Quand une barre d'action porte un rang inferieur d'un sort dont un rang superieur est appris (et pas deja pose
-- ailleurs), une fleche verte s'affiche sur le sort dans le grimoire. Au survol, un petit bouton remplace d'un clic
-- tous les rangs inferieurs poses par le rang max, avec une icone factice qui glisse vers le bas en fondu.
-- Reglage : ns.DB.comfort.spellRanks. Rien n'est remplace en combat (PlaceAction y est interdit).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local SpellRanks = {}
ns.Modules.SpellRanks = SpellRanks

local L = ns.L
local MAX_ACTION_SLOT = 180

local function Enabled()
  if not ns.QoLEnabled() then return false end
  local c = ns.GetCfg("comfort") or {}
  local v = c.spellRanks
  if v == nil then v = ns.Defaults.comfort and ns.Defaults.comfort.spellRanks end
  return v and true or false
end

-- ── Infos de sorts (API Forever / moderne, avec repli) ──────────────────────────────────────────
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and n then return n end
  end
  if GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, id)
    if ok then return n end
  end
end

local function SpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, t = pcall(C_Spell.GetSpellTexture, id)
    if ok and t then return t end
  end
  if GetSpellTexture then
    local ok, t = pcall(GetSpellTexture, id)
    if ok then return t end
  end
end

-- "Rang 3" / "Rank 3" -> 3 ; nil pour un sort sans rang
local function SpellRank(id)
  local ok, sub = pcall(function()
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
    if GetSpellSubtext then return GetSpellSubtext(id) end
  end)
  if ok and type(sub) == "string" then return tonumber(sub:match("(%d+)")) end
end

local BOOK = BOOKTYPE_SPELL or "spell"

-- Sort d'un emplacement du grimoire du joueur -> spellID, nom, rang (nil si pas un sort)
local function BookSpell(slot)
  local id, name, sub
  if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    local bank = Enum.SpellBookSpellBank.Player
    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
    if ok and type(info) == "table" then
      local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
      if spellType and info.itemType and info.itemType ~= spellType then return nil end
      id, name, sub = info.spellID or info.actionID, info.name, info.subName
    end
    if C_SpellBook.GetSpellBookItemName and not sub then
      local ok2, n, sn = pcall(C_SpellBook.GetSpellBookItemName, slot, bank)
      if ok2 then name, sub = name or n, sn end
    end
  end
  if not id and GetSpellBookItemInfo then
    local ok, kind, sid = pcall(GetSpellBookItemInfo, slot, BOOK)
    if ok then
      if kind ~= "SPELL" then return nil end
      id = sid
    end
  end
  if not sub and GetSpellBookItemName then
    local ok, n, sn = pcall(GetSpellBookItemName, slot, BOOK)
    if ok then name, sub = name or n, sn end
  end
  if not id then return nil end
  name = name or SpellName(id)
  local rank = type(sub) == "string" and tonumber(sub:match("(%d+)")) or SpellRank(id)
  return id, name, rank
end

local function NumBookSlots()
  local total = 0
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local ok, n = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if ok and n and n > 0 then
      for i = 1, n do
        local ok2, info = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
        if ok2 and type(info) == "table" then
          total = math.max(total, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0))
        end
      end
    end
  end
  if total == 0 and GetNumSpellTabs and GetSpellTabInfo then
    local ok, n = pcall(GetNumSpellTabs)
    for i = 1, (ok and n) or 0 do
      local _, _, offset, count = GetSpellTabInfo(i)
      total = math.max(total, (offset or 0) + (count or 0))
    end
  end
  return total
end

-- Rang le plus haut connu d'un sort, d'apres son nom (le jeu resout le nom vers le rang max appris)
local function KnownByName(name)
  local id
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" then id = info.spellID end
  end
  if not id and GetSpellInfo then
    local ok, _, _, _, _, _, _, sid = pcall(GetSpellInfo, name)
    if ok then id = sid end
  end
  local rank = id and SpellRank(id)
  if rank then return { id = id, rank = rank } end
end

-- ── Analyse : rang max appris vs rangs poses sur les barres ─────────────────────────────────────
local best = {}      -- nom -> { id, rank, slot (grimoire) }
local pending = {}   -- nom -> { slots d'action a mettre a jour }
local stats = {}     -- compteurs pour /aish ranks

local hooked   -- grimoire classique branche (absent en Retail : rien a analyser)
local QueueScan, OnButtonEnter, PopupHideLater, popup   -- definis plus bas

local function Scan()
  wipe(best); wipe(pending); wipe(stats)
  if not ((ns.IsForever or hooked or _G.SpellButton1) and Enabled()) then return end
  local nBook = NumBookSlots()
  stats.bookSlots, stats.ranked, stats.barSpells = nBook, 0, 0
  for slot = 1, nBook do
    local id, name, rank = BookSpell(slot)
    if id and name and rank then
      stats.ranked = stats.ranked + 1
      local b = best[name]
      if not b or rank > b.rank then best[name] = { id = id, rank = rank, slot = slot } end
    end
  end
  -- Une seule version sur les barres et pas au rang max -> proposition ; rang max present -> rien
  local hasMax = {}
  for slot = 1, MAX_ACTION_SLOT do
    local ok, kind, id = pcall(GetActionInfo, slot)
    if ok and kind == "spell" and id then
      stats.barSpells = stats.barSpells + 1
      local name = SpellName(id)
      local b = name and best[name]
      if name and not b then
        b = KnownByName(name)
        best[name] = b
      end
      if b then
        local rank = SpellRank(id)
        if id == b.id or (rank and rank >= b.rank) then
          hasMax[name] = true
        else
          local list = pending[name] or {}
          list[#list + 1] = slot
          pending[name] = list
        end
      end
    end
  end
  for name in pairs(hasMax) do pending[name] = nil end
end

-- ── Fleche sur les boutons du grimoire ──────────────────────────────────────────────────────────
local function ArrowTexture(tex)
  local atlas = "bags-greenarrow"
  if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
    tex:SetAtlas(atlas)
  else
    tex:SetTexture("Interface\Buttons\UI-MicroStream-Green")
    tex:SetRotation(math.pi)
  end
end

-- Sort affiche par un bouton du grimoire : nom et rang lus sur le bouton (textes "SpellName" / "SpellSubName")
local function ButtonText(btn, key)
  local fs = btn[key] or (btn:GetName() and _G[btn:GetName() .. key])
  if fs and fs.GetText and fs:IsShown() then return fs:GetText() end
end

local function ButtonSpell(btn)
  -- Grimoire moderne (PlayerSpellsFrame) : l'entree porte son emplacement de grimoire
  local item = btn._aishItem
  if item then
    local ed = item.elementData
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if ed and ed.spellBank ~= nil and bank ~= nil and ed.spellBank ~= bank then return nil end
    local slot = (ed and ed.slotIndex) or item.slotIndex
    if slot then
      local _, n, r = BookSpell(slot)
      return n, r
    end
    local info = item.spellBookItemInfo
    if info and info.name then
      return info.name, type(info.subName) == "string" and tonumber(info.subName:match("(%d+)")) or nil
    end
    return nil
  end
  local book = _G.SpellBookFrame
  if book and book.bookType and book.bookType ~= BOOK then return nil end
  local name = ButtonText(btn, "SpellName")
  local sub = ButtonText(btn, "SpellSubName")
  local rank = type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
  if not name and SpellBook_GetSpellBookSlot then
    local ok, slot = pcall(SpellBook_GetSpellBookSlot, btn)
    if ok and slot then
      local _, n, r = BookSpell(slot)
      name, rank = n, r
    end
  end
  return name, rank
end

-- Le bouton montre-t-il le rang max d'un sort a mettre a jour ?
local function ButtonPending(btn)
  local name, rank = ButtonSpell(btn)
  local b = name and best[name]
  if b and pending[name] and (not rank or rank >= b.rank) then return name end
end

local function UpdateButton(btn)
  if not btn then return end
  local arrow = btn._aishRankArrow
  local show = Enabled() and btn:IsShown() and ButtonPending(btn)
  if show and not arrow then
    arrow = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetSize(27, 27)
    arrow:SetPoint("TOPLEFT", btn, "TOPLEFT", -7, 7)
    ArrowTexture(arrow)
    btn._aishRankArrow = arrow
  end
  if arrow then arrow:SetShown(show and true or false) end
end

local function SpellButtons()
  local list, n = {}, _G.SPELLS_PER_PAGE or 12
  for i = 1, n do
    local b = _G["SpellButton" .. i]
    if b then list[#list + 1] = b end
  end
  return list
end

-- Grimoire moderne : icones des entrees affichees (collectees a chaque rafraichissement)
local CollectModern   -- defini plus bas (accroche le survol)
local modernButtons = {}

local function UpdateAllButtons()
  for _, b in ipairs(SpellButtons()) do UpdateButton(b) end
  if CollectModern then CollectModern() end
  for _, b in ipairs(modernButtons) do UpdateButton(b) end
end

-- ── Animation factice : l'icone du sort glisse vers le bas en fondu ─────────────────────────────
local flyPool = {}
local function Fly(fromBtn, icon)
  local f
  for _, x in ipairs(flyPool) do if not x:IsShown() then f = x; break end end
  if not f then
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    flyPool[#flyPool + 1] = f
  end
  local scale = fromBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local w, h = fromBtn:GetSize()
  local cx, cy = fromBtn:GetCenter()
  if not cx then return end
  cx, cy, w, h = cx * scale, cy * scale, w * scale, h * scale
  f.tex:SetTexture(icon)
  local DUR, DIST = 0.9, 80
  local t = 0
  f:SetSize(w, h)
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
  f:SetAlpha(1)
  f:Show()
  f:SetScript("OnUpdate", function(self, elapsed)
    t = t + elapsed
    local p = math.min(t / DUR, 1)
    local ease = (p >= 1) and 1 or (1 - 2 ^ (-10 * p))  -- ease-out exponentiel
    local s = 1 - 0.25 * ease                           -- retrecit un peu en s'eloignant
    self:SetSize(w * s, h * s)
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy - DIST * ease)
    self:SetAlpha(1 - p * p * (3 - 2 * p))              -- fondu smoothstep
    if p >= 1 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
    end
  end)
end

-- ── Remplacement sur les barres ─────────────────────────────────────────────────────────────────
local function PickupBest(b)
  if b.slot and C_SpellBook and C_SpellBook.PickupSpellBookItem and Enum and Enum.SpellBookSpellBank then
    if pcall(C_SpellBook.PickupSpellBookItem, b.slot, Enum.SpellBookSpellBank.Player) then return end
  end
  if b.slot and PickupSpellBookItem and pcall(PickupSpellBookItem, b.slot, BOOK) then return end
  if C_Spell and C_Spell.PickupSpell then pcall(C_Spell.PickupSpell, b.id) return end
  if PickupSpell then pcall(PickupSpell, b.id) end
end

local function Replace(name)
  if InCombatLockdown() then
    UIErrorsFrame:AddMessage(L["SPELLRANKS_COMBAT"], 1, 0.1, 0.1)
    return false
  end
  local b, slots = best[name], pending[name]
  if not (b and slots) then return false end
  ClearCursor()
  for _, slot in ipairs(slots) do
    PickupBest(b)
    PlaceAction(slot)
    ClearCursor()   -- PlaceAction rend l'ancien rang au curseur : on le jette
  end
  return true
end

-- ── Petit bouton au survol d'un sort du grimoire ────────────────────────────────────────────────
function PopupHideLater()
  if not popup then return end
  C_Timer.After(0.15, function()
    if popup:IsShown() and not popup:IsMouseOver() and not (popup.owner and popup.owner:IsMouseOver()) then
      popup:Hide()
    end
  end)
end

local function EnsurePopup()
  if popup then return popup end
  popup = CreateFrame("Button", nil, UIParent)
  popup:SetSize(26, 26)
  popup:SetFrameStrata("TOOLTIP")
  -- Forme ronde : disques pleins (masque de portrait du jeu) teintes, bordure verte sous le fond sombre
  local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
  local border = popup:CreateTexture(nil, "BACKGROUND", nil, 0)
  border:SetAllPoints()
  border:SetTexture(CIRCLE)
  border:SetVertexColor(0.2, 0.9, 0.3, 1)
  local bg = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetPoint("TOPLEFT", 1.5, -1.5)
  bg:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
  bg:SetTexture(CIRCLE)
  bg:SetVertexColor(0.05, 0.05, 0.05, 0.92)
  local arrow = popup:CreateTexture(nil, "ARTWORK")
  arrow:SetPoint("TOPLEFT", 5, -5)
  arrow:SetPoint("BOTTOMRIGHT", -5, 5)
  ArrowTexture(arrow)
  local hl = popup:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(bg)
  hl:SetTexture(CIRCLE)
  hl:SetVertexColor(0.2, 1, 0.3, 0.18)
  popup:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["SPELLRANKS_POPUP"], 0.3, 1, 0.4)
    local b = self.spell and best[self.spell]
    if b then
      GameTooltip:AddLine(string.format(L["SPELLRANKS_POPUP_TT"], self.spell, b.rank), 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  popup:SetScript("OnLeave", function() GameTooltip:Hide(); PopupHideLater() end)
  popup:SetScript("OnClick", function(self)
    local name, owner = self.spell, self.owner
    local b = name and best[name]
    if not b then self:Hide(); return end
    if Replace(name) then
      local snd = SOUNDKIT and (SOUNDKIT.IG_ABILITY_ICON_DROP or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      if snd then PlaySound(snd) end
      if owner then Fly(owner, SpellIcon(b.id)) end
      GameTooltip:Hide()
      self:Hide()
    end
  end)
  popup:Hide()
  return popup
end

function OnButtonEnter(btn)
  if not Enabled() then return end
  UpdateButton(btn)
  local name = ButtonPending(btn)
  if not name then return end
  local p = EnsurePopup()
  if p:IsShown() and p.owner == btn then return end
  p.spell, p.owner = name, btn
  local h = btn:GetHeight()
  if not h or h <= 0 then h = p:GetHeight() end
  p:SetSize(h, h)
  -- Sort de l'icone vers la gauche : depart sous l'icone, arrivee a gauche du sort, sur la meme ligne
  local FROM, TO, DUR = h, -6, 0.3
  local t = 0
  p:ClearAllPoints()
  p:SetPoint("RIGHT", btn, "LEFT", FROM, 0)
  p:SetAlpha(0)
  p:Show()
  p:SetScript("OnUpdate", function(self, elapsed)
    t = t + elapsed
    local k = math.min(t / DUR, 1)
    local ease = (k >= 1) and 1 or (1 - 2 ^ (-10 * k))   -- ease-out exponentiel
    self:SetPoint("RIGHT", btn, "LEFT", FROM + (TO - FROM) * ease, 0)
    self:SetAlpha(ease)
    if k >= 1 then self:SetScript("OnUpdate", nil) end
  end)
end

-- ── Grimoire moderne (PlayerSpellsFrame.SpellBookFrame, utilise par Forever) ────────────────────
local function ModernBook()
  return _G.PlayerSpellsFrame and _G.PlayerSpellsFrame.SpellBookFrame
end

local function HookModernButton(btn, item)
  btn._aishItem = item
  if btn._aishRankHooked then return end
  btn._aishRankHooked = true
  btn:HookScript("OnEnter", OnButtonEnter)
  btn:HookScript("OnLeave", PopupHideLater)
  btn:HookScript("OnHide", function(self) if popup and popup.owner == self then popup:Hide() end end)
end

-- Entrees de sort affichees : frames portant elementData / spellBookItemInfo et une icone (.Button)
local function Walk(frame, depth)
  for _, child in ipairs({ frame:GetChildren() }) do
    if child:IsShown() then
      local btn = child.Button
      if btn and (child.elementData or child.spellBookItemInfo) and type(btn) == "table" and btn.HookScript then
        HookModernButton(btn, child)
        modernButtons[#modernButtons + 1] = btn
      elseif depth < 5 then
        Walk(child, depth + 1)
      end
    end
  end
end

CollectModern = function()
  wipe(modernButtons)
  local sb = ModernBook()
  if not (sb and sb:IsVisible()) then return end
  Walk(sb.PagedSpellsFrame or sb, 0)
end

-- Pages / onglets / recherche reecrivent les entrees sans evenement simple : rafraichi tant que le grimoire est ouvert
local modernTicker
local function ModernShown()
  if modernTicker then modernTicker:Cancel() end
  UpdateAllButtons()
  modernTicker = C_Timer.NewTicker(0.25, function()
    local sb = ModernBook()
    if not (sb and sb:IsVisible()) then
      if modernTicker then modernTicker:Cancel(); modernTicker = nil end
      return
    end
    UpdateAllButtons()
  end)
end

local modernHooked
local function HookModernBook()
  local sb = ModernBook()
  if modernHooked or not sb then return end
  modernHooked = true
  sb:HookScript("OnShow", function() QueueScan(); ModernShown() end)
  sb:HookScript("OnHide", function()
    if modernTicker then modernTicker:Cancel(); modernTicker = nil end
    if popup then popup:Hide() end
  end)
  if sb:IsVisible() then ModernShown() end
end

local scanQueued
function QueueScan()
  if scanQueued then return end
  scanQueued = true
  C_Timer.After(0.2, function()
    scanQueued = false
    Scan()
    UpdateAllButtons()
    if popup and popup:IsShown() and not (popup.spell and pending[popup.spell]) then popup:Hide() end
  end)
end

-- ── Branchement sur le grimoire classique ───────────────────────────────────────────────────────
local function HookBook()
  HookModernBook()
  if hooked or not _G.SpellButton1 then return end
  hooked = true
  for _, b in ipairs(SpellButtons()) do
    b:HookScript("OnEnter", OnButtonEnter)
    b:HookScript("OnLeave", PopupHideLater)
    b:HookScript("OnHide", function(self) if popup and popup.owner == self then popup:Hide() end end)
    b:HookScript("OnShow", UpdateButton)
  end
  -- Changement de page / d'onglet : les boutons sont reecrits sans etre recrees
  if SpellButton_UpdateButton then hooksecurefunc("SpellButton_UpdateButton", UpdateButton) end
  for _, fn in ipairs({ "SpellBookFrame_Update", "SpellBookFrame_UpdateSpells" }) do
    if _G[fn] then hooksecurefunc(fn, UpdateAllButtons) end
  end
  -- Grimoire charge a la demande : l'analyse faite avant lui etait vide, on la relance
  if _G.SpellBookFrame then _G.SpellBookFrame:HookScript("OnShow", QueueScan) end
  QueueScan()
end

-- /aish ranks : etat de la detection, dans une fenetre copiable (Ctrl+A, Ctrl+C)
local dbgFrame
local function ShowDebugText(text)
  if not dbgFrame then
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(760, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    f:SetBackdropBorderColor(0.2, 0.9, 0.3, 1)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -28)
    sf:SetPoint("BOTTOMRIGHT", -30, 10)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(ns.FONT_FALLBACK, 12, "")
    eb:SetWidth(710)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb
    dbgFrame = f
  end
  dbgFrame.eb:SetText(text)
  dbgFrame:Show()
  dbgFrame.eb:SetFocus()
  dbgFrame.eb:HighlightText()
end

local function S(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
  return table.concat(t, ", ")
end

local function RawSubtext(id)
  local fn = (C_Spell and C_Spell.GetSpellSubtext) or GetSpellSubtext
  if not (fn and id) then return "-" end
  return S(pcall(fn, id))
end

function SpellRanks.Debug()
  HookBook()
  Scan()
  UpdateAllButtons()
  local out = {}
  local function W(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
  local c = ns.GetCfg("comfort") or {}
  local book = _G.SpellBookFrame
  W("== AishCore SpellRanks == build %s | IsForever=%s | locale=%s", S(GetBuildInfo()), tostring(ns.IsForever), GetLocale())
  W("Enabled=%s (QoL=%s, spellRanks=%s) hooked=%s SpellButton1=%s SpellBookFrame=%s shown=%s bookType=%s",
    tostring(Enabled()), tostring(ns.QoLEnabled()), tostring(c.spellRanks), tostring(hooked), tostring(_G.SpellButton1 ~= nil),
    tostring(book ~= nil), tostring(book and book:IsShown()), tostring(book and book.bookType))
  W("API: C_SpellBook.GetSpellBookItemInfo=%s C_SpellBook.GetSpellBookItemName=%s GetNumSpellBookSkillLines=%s | GetSpellBookItemInfo=%s GetSpellBookItemName=%s GetNumSpellTabs=%s",
    tostring(C_SpellBook and C_SpellBook.GetSpellBookItemInfo ~= nil), tostring(C_SpellBook and C_SpellBook.GetSpellBookItemName ~= nil),
    tostring(C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines ~= nil), tostring(GetSpellBookItemInfo ~= nil),
    tostring(GetSpellBookItemName ~= nil), tostring(GetNumSpellTabs ~= nil))
  W("API: C_Spell.GetSpellSubtext=%s GetSpellSubtext=%s C_Spell.GetSpellInfo=%s SpellBook_GetSpellBookSlot=%s SpellButton_UpdateButton=%s PickupSpellBookItem=%s C_SpellBook.PickupSpellBookItem=%s",
    tostring(C_Spell and C_Spell.GetSpellSubtext ~= nil), tostring(GetSpellSubtext ~= nil), tostring(C_Spell and C_Spell.GetSpellInfo ~= nil),
    tostring(SpellBook_GetSpellBookSlot ~= nil), tostring(SpellButton_UpdateButton ~= nil), tostring(PickupSpellBookItem ~= nil),
    tostring(C_SpellBook and C_SpellBook.PickupSpellBookItem ~= nil))
  local msb = ModernBook()
  W("Grimoire moderne : PlayerSpellsFrame=%s SpellBookFrame=%s visible=%s hooked=%s entrees=%d",
    tostring(_G.PlayerSpellsFrame ~= nil), tostring(msb ~= nil), tostring(msb and msb:IsVisible()), tostring(modernHooked), #modernButtons)
  W("Grimoire : %s emplacements, %s avec rang | sorts sur les barres : %s",
    tostring(stats.bookSlots), tostring(stats.ranked), tostring(stats.barSpells))

  W("")
  W("-- Grimoire (40 premiers emplacements, valeurs brutes)")
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  for slot = 1, math.min(stats.bookSlots or 0, 40) do
    local parts = { "#" .. slot }
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo and bank then
      local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
      if ok and type(info) == "table" then
        parts[#parts + 1] = string.format("C.info{type=%s id=%s action=%s name=%s sub=%s}", tostring(info.itemType),
          tostring(info.spellID), tostring(info.actionID), tostring(info.name), tostring(info.subName))
      else
        parts[#parts + 1] = "C.info=" .. S(ok, info)
      end
    end
    if C_SpellBook and C_SpellBook.GetSpellBookItemName and bank then
      parts[#parts + 1] = "C.name=" .. S(pcall(C_SpellBook.GetSpellBookItemName, slot, bank))
    end
    if GetSpellBookItemInfo then parts[#parts + 1] = "info=" .. S(pcall(GetSpellBookItemInfo, slot, BOOK)) end
    if GetSpellBookItemName then parts[#parts + 1] = "name=" .. S(pcall(GetSpellBookItemName, slot, BOOK)) end
    local id, name, rank = BookSpell(slot)
    parts[#parts + 1] = string.format("=> id=%s nom=%s rang=%s subtext=%s", tostring(id), tostring(name), tostring(rank), RawSubtext(id))
    W("%s", table.concat(parts, " | "))
  end

  W("")
  W("-- Barres d'action")
  for slot = 1, MAX_ACTION_SLOT do
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if ok and kind then
      local name = (kind == "spell" and id) and SpellName(id) or nil
      local b = name and best[name]
      W("barre %d : %s id=%s sub=%s nom=%s subtext=%s -> max=%s%s", slot, tostring(kind), tostring(id), tostring(sub),
        tostring(name), kind == "spell" and RawSubtext(id) or "-",
        b and (b.rank .. " (id " .. b.id .. ", grimoire " .. tostring(b.slot) .. ")") or "-",
        (name and pending[name]) and "  << A METTRE A JOUR" or "")
    end
  end

  W("")
  W("-- A mettre a jour")
  for name, slots in pairs(pending) do W("%s : barres %s", name, table.concat(slots, ",")) end

  W("")
  W("-- Boutons du grimoire")
  for i, btn in ipairs(SpellButtons()) do
    local n, r = ButtonSpell(btn)
    W("SpellButton%d shown=%s nom=%s rang=%s texteNom=%s texteRang=%s fleche=%s", i, tostring(btn:IsShown()),
      tostring(n), tostring(r), tostring(ButtonText(btn, "SpellName")), tostring(ButtonText(btn, "SpellSubName")),
      tostring(btn._aishRankArrow and btn._aishRankArrow:IsShown()))
  end
  for i, btn in ipairs(modernButtons) do
    local n, r = ButtonSpell(btn)
    local ed = btn._aishItem and btn._aishItem.elementData
    W("Entree %d slot=%s bank=%s nom=%s rang=%s fleche=%s", i, tostring(ed and ed.slotIndex), tostring(ed and ed.spellBank),
      tostring(n), tostring(r), tostring(btn._aishRankArrow and btn._aishRankArrow:IsShown()))
  end
  ShowDebugText(table.concat(out, "\n"))
end

function SpellRanks.ApplySettings()
  HookBook()
  if not Enabled() and popup then popup:Hide() end
  QueueScan()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
ev:SetScript("OnEvent", function(_, event)
  if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then HookBook() end
  if event == "ADDON_LOADED" then return end
  QueueScan()
end)

-- Raccourci direct du debug (en plus de /aish ranks)
SLASH_AISHRANKS1 = "/aishranks"
SlashCmdList["AISHRANKS"] = function() SpellRanks.Debug() end

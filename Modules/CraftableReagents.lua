-- Modules/CraftableReagents.lua : fenetre de metier (QoL). Un ingredient que le personnage sait fabriquer avec le
-- metier ouvert porte une fleche (atlas shop-header-arrow-pressed) a gauche de son icone, qui glisse au survol.
-- Survol : panneau a gauche de la fleche avec les ingredients de sa recette (lignes en cascade venant de la droite),
-- dans la police du panneau du metier. Clic droit : ouvre sa recette.
-- Retail : ProfessionsFrame.CraftingPage.SchematicForm (post-hook de Init) ; ouverture via C_TradeSkillUI.OpenRecipe.
-- Forever : TradeSkillFrame classique (post-hook de TradeSkillFrame_SetSelection), recettes reperees par leur nom.
-- Aucun script Blizzard remplace : OnMouseUp accroche une fois par bouton (le jeu ne le reecrit jamais), survol lu
-- par IsMouseOver dans le OnUpdate du detrompeur (OnEnter / OnLeave sont reecrits a chaque Init).
-- Reglage : ns.DB.comfort.craftableReagents.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local CR = {}
ns.Modules.CraftableReagents = CR

local L = ns.L or {}
local ARROW_ATLAS = "shop-header-arrow-pressed"
local ARROW_FALLBACK = "Interface\\ChatFrame\\ChatFrameExpandArrow" -- client sans l'atlas
local ARROW_H, ARROW_GAP, ARROW_SLIDE = 20, 2, 5
local WHITE = "Interface\\Buttons\\WHITE8x8"
local GOLD = { 1, 0.78, 0.25 }

local function Enabled()
  if not ns.QoLEnabled() then return false end
  local c = ns.GetCfg("comfort") or {}
  return c.craftableReagents ~= false
end

-- Police du panneau du metier : lue sur le texte du bouton d'ingredient (repli : police par defaut de l'addon)
local curFont
local function Font() return curFont or ns.FONT_FALLBACK or STANDARD_TEXT_FONT end

local function FontOf(fs)
  if fs and fs.GetFont then
    local file = fs:GetFont()
    if file then return file end
  end
end

local function FontFromButton(btn, nameFS)
  local f = FontOf(nameFS)
  if f then return f end
  for _, r in ipairs({ btn:GetRegions() }) do
    if r.GetObjectType and r:GetObjectType() == "FontString" then
      f = FontOf(r)
      if f then return f end
    end
  end
end

local function ItemIDFromLink(link)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

local function ItemCount(itemID)
  if C_Item and C_Item.GetItemCount then
    return C_Item.GetItemCount(itemID, true, false, true, true) or 0
  end
  return GetItemCount and GetItemCount(itemID, true) or 0
end

local function ItemName(itemID)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  if not n and GetItemInfo then n = GetItemInfo(itemID) end
  if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  return n
end

local function ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
  return GetItemIcon and GetItemIcon(itemID)
end

-- ── Fournisseurs : Retail (C_TradeSkillUI moderne) / Forever (TradeSkillFrame classique) ──────────────
-- Interface commune : Find(itemID) -> handle | nil ; Info(handle) -> { name, icon, count, reagents = {
-- { itemID, name, icon, need, have } } } ; Open(handle).
local Retail, Classic = {}, {}

-- Retail : sortie des recettes apprises du metier ouvert (toutes qualites) -> recipeID
local rMap, rKey
local function RetailKey()
  local info = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  return info and info.professionID or 0
end

local function RetailUsable()
  local T = C_TradeSkillUI
  if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return false end
  if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return false end
  if T.IsNPCCrafting and T.IsNPCCrafting() then return false end
  if T.IsRuneforging and T.IsRuneforging() then return false end
  return true
end

local function RetailBuild()
  local key = RetailKey()
  if rMap and rKey == key then return rMap end
  local T = C_TradeSkillUI
  local map = {}
  for _, rid in ipairs(T.GetAllRecipeIDs and T.GetAllRecipeIDs() or {}) do
    local ri = T.GetRecipeInfo(rid)
    if ri and ri.learned and not ri.isRecraft and not ri.isSalvageRecipe and not ri.isGatheringRecipe
      and not ri.isDummyRecipe and not ri.isEnchantingRecipe then
      local out = T.GetRecipeOutputItemData and T.GetRecipeOutputItemData(rid)
      if out and out.itemID and not map[out.itemID] then map[out.itemID] = rid end
      local q = T.GetRecipeQualityItemIDs and T.GetRecipeQualityItemIDs(rid)
      if q then
        for _, id in ipairs(q) do
          if not map[id] then map[id] = rid end
        end
      end
    end
  end
  rMap, rKey = map, key
  return map
end

function Retail.Find(itemID)
  if not itemID or not RetailUsable() then return nil end
  return RetailBuild()[itemID]
end

function Retail.Info(rid)
  local T = C_TradeSkillUI
  local ri = T.GetRecipeInfo(rid)
  local sch = T.GetRecipeSchematic and T.GetRecipeSchematic(rid, false)
  if not (ri and sch) then return nil end
  local list = {}
  local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
  for _, rs in ipairs(sch.reagentSlotSchematics or {}) do
    if rs.reagentType == BASIC and (rs.quantityRequired or 0) > 0 then
      local first = rs.reagents and rs.reagents[1]
      if first and first.itemID then
        local have = 0
        for _, r in ipairs(rs.reagents) do
          if r.itemID then have = have + ItemCount(r.itemID) end
        end
        list[#list + 1] = { itemID = first.itemID, name = ItemName(first.itemID), icon = ItemIcon(first.itemID),
          need = rs.quantityRequired, have = have }
      elseif first and first.currencyID and C_CurrencyInfo then
        local ci = C_CurrencyInfo.GetCurrencyInfo(first.currencyID)
        if ci then
          list[#list + 1] = { name = ci.name, icon = ci.iconFileID, need = rs.quantityRequired, have = ci.quantity or 0 }
        end
      end
    end
  end
  return { name = ri.name, icon = ri.icon, count = ri.numAvailable, reagents = list }
end

-- Metier deja ouvert : C_TradeSkillUI.OpenRecipe ne fait rien (la reponse n'est appliquee qu'au chargement de la
-- liste). On selectionne donc dans la page de craft : formulaire, puis liste (selection + defilement).
local function RetailShown(form, rid)
  local cur = form and form.GetRecipeInfo and form:GetRecipeInfo()
  return cur and cur.recipeID == rid
end

function Retail.Open(rid)
  local pf = _G.ProfessionsFrame
  local cp = pf and pf.CraftingPage
  local ri = C_TradeSkillUI.GetRecipeInfo(rid)
  if cp and ri then
    if cp.RecipeList and cp.RecipeList.SelectRecipe then pcall(cp.RecipeList.SelectRecipe, cp.RecipeList, ri, true) end
    if not RetailShown(cp.SchematicForm, rid) and cp.SelectRecipe then pcall(cp.SelectRecipe, cp, ri) end
    if RetailShown(cp.SchematicForm, rid) then return end
  end
  if C_TradeSkillUI.OpenRecipe then C_TradeSkillUI.OpenRecipe(rid) end
end

-- Forever : objet fabrique -> nom de la recette. Les index de la liste changent avec les filtres et les
-- en-tetes replies : on garde le nom, et l'index est recherche a l'usage. Cumul sur la session (recettes jamais
-- perdues), remis a zero au changement de metier.
local cMap, cKey = {}, nil

local function ClassicScan()
  local key = GetTradeSkillLine and GetTradeSkillLine() or ""
  if key ~= cKey then cMap, cKey = {}, key end
  for i = 1, (GetNumTradeSkills() or 0) do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local id = ItemIDFromLink(GetTradeSkillItemLink(i))
      if id and not cMap[id] then cMap[id] = name end
    end
  end
end

local function ClassicIndex(name, expand)
  for i = 1, (GetNumTradeSkills() or 0) do
    local n, kind = GetTradeSkillInfo(i)
    if n == name and kind ~= "header" and kind ~= "subheader" then return i end
  end
  if expand and ExpandTradeSkillSubClass then
    ExpandTradeSkillSubClass(0)
    return ClassicIndex(name, false)
  end
end

function Classic.Find(itemID)
  if not itemID then return nil end
  if IsTradeSkillLinked and IsTradeSkillLinked() then return nil end
  return cMap[itemID]
end

function Classic.Info(name)
  local i = ClassicIndex(name, false)
  local info = { name = name, reagents = {} }
  if not i then return info end
  local _, _, avail = GetTradeSkillInfo(i)
  info.count = avail
  info.icon = GetTradeSkillIcon and GetTradeSkillIcon(i)
  for r = 1, (GetTradeSkillNumReagents(i) or 0) do
    local rname, rtex, need, have = GetTradeSkillReagentInfo(i, r)
    local id = ItemIDFromLink(GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, r))
    info.reagents[#info.reagents + 1] = { itemID = id, name = rname or (id and ItemName(id)), icon = rtex,
      need = need or 0, have = id and ItemCount(id) or have or 0 }
  end
  return info
end

function Classic.Open(name)
  local i = ClassicIndex(name, true)
  if not (i and TradeSkillFrame_SetSelection) then return end
  TradeSkillFrame_SetSelection(i)
  -- Faire defiler la liste jusqu'a la recette (FauxScrollFrame classique)
  local sf = _G.TradeSkillListScrollFrame
  local rows = _G.TRADE_SKILLS_DISPLAYED or 8
  local h = _G.TRADE_SKILL_HEIGHT or 16
  if sf and FauxScrollFrame_GetOffset then
    local off = FauxScrollFrame_GetOffset(sf)
    if i <= off or i > off + rows then
      local newOff = math.max(0, math.min(i - 1, (GetNumTradeSkills() or 0) - rows))
      local bar = sf.ScrollBar or _G[sf:GetName() .. "ScrollBar"]
      if bar then bar:SetValue(newOff * h) end
    end
  end
  if TradeSkillFrame_Update then TradeSkillFrame_Update() end
end

-- ── Panneau des ingredients ───────────────────────────────────────────────────────────────────────────
local PAD, ROW_H, ICON = 10, 20, 16
local STAGGER, ROW_DUR, SLIDE = 0.045, 0.22, 14
local panel, panelOwner, panelProv, panelHandle

local function EaseOut(t) t = 1 - t; return 1 - t * t * t end

local function NewText(parent, size, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(Font(), size, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetJustifyH("LEFT")
  return fs
end

local function NewRow(i)
  local row = CreateFrame("Frame", nil, panel)
  row:SetSize(10, ROW_H)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", 0, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = NewText(row, 12)
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.count = NewText(row, 12)
  row.count:SetJustifyH("RIGHT")
  row.count:SetPoint("RIGHT", 0, 0)
  panel.rows[i] = row
  return row
end

local function EnsurePanel()
  if panel then return panel end
  panel = CreateFrame("Frame", "AishCoreCraftableReagentsPanel", UIParent, "BackdropTemplate")
  panel:SetFrameStrata("TOOLTIP")
  panel:SetClampedToScreen(true)
  panel:EnableMouse(false)
  panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  panel:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
  panel:SetBackdropBorderColor(GOLD[1] * 0.55, GOLD[2] * 0.55, GOLD[3] * 0.55, 1)
  -- Liseré dore a droite, cote fleche
  local edge = panel:CreateTexture(nil, "BORDER")
  edge:SetTexture(WHITE)
  edge:SetPoint("TOPRIGHT", -1, -1)
  edge:SetPoint("BOTTOMRIGHT", -1, 1)
  edge:SetWidth(2)
  edge:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
  panel.headIcon = panel:CreateTexture(nil, "ARTWORK")
  panel.headIcon:SetSize(22, 22)
  panel.headIcon:SetPoint("TOPLEFT", PAD + 2, -PAD)
  panel.headIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  panel.title = NewText(panel, 13)
  panel.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  panel.title:SetPoint("TOPLEFT", panel.headIcon, "TOPRIGHT", 7, 0)
  panel.sub = NewText(panel, 11)
  panel.sub:SetTextColor(0.75, 0.75, 0.75)
  panel.sub:SetPoint("BOTTOMLEFT", panel.headIcon, "BOTTOMRIGHT", 7, 0)
  panel.sep = panel:CreateTexture(nil, "ARTWORK")
  panel.sep:SetTexture(WHITE)
  panel.sep:SetHeight(1)
  panel.sep:SetVertexColor(1, 1, 1, 0.12)
  panel.hint = NewText(panel, 9)
  panel.hint:SetTextColor(0.38, 0.38, 0.38)
  panel.rows = {}
  panel:Hide()
  return panel
end

local function CountText(have, need)
  local col = have >= need and "|cff4ee44e" or "|cffff5a5a"
  return col .. have .. "|r|cff9a9a9a / " .. need .. "|r"
end

-- Panneau a gauche de la fleche, cale sur sa position glissee (fixe : la fleche bouge, pas le panneau)
local function Anchor(m)
  panel:ClearAllPoints()
  panel:SetPoint("TOPRIGHT", m, "TOPLEFT", -(ARROW_GAP + m.arrowW + ARROW_SLIDE + 4), 0)
end

local function SetFonts()
  local f = Font()
  panel.title:SetFont(f, 13, "")
  panel.sub:SetFont(f, 11, "")
  panel.hint:SetFont(f, 9, "")
  for _, row in ipairs(panel.rows) do
    row.name:SetFont(f, 12, "")
    row.count:SetFont(f, 12, "")
  end
end

-- Remplit le panneau ; animate = false pour un simple rafraichissement (noms arrives du cache)
local function Fill(animate)
  local info = panelProv.Info(panelHandle)
  if not info then panel:Hide(); return end
  SetFonts()
  panel.headIcon:SetTexture(info.icon or 134400)
  panel.title:SetText(info.name or "")
  panel.title:ClearAllPoints()
  if info.count and info.count > 0 then
    panel.sub:SetText(string.format(L["CRAFTABLE_COUNT"] or "Craftable: %d", info.count))
    panel.sub:Show()
    panel.title:SetPoint("TOPLEFT", panel.headIcon, "TOPRIGHT", 7, 0)
  else
    panel.sub:SetText("")
    panel.sub:Hide()
    panel.title:SetPoint("LEFT", panel.headIcon, "RIGHT", 7, 0)
  end
  local headW = 22 + 7 + math.max(panel.title:GetStringWidth(), panel.sub:IsShown() and panel.sub:GetStringWidth() or 0)
  local y = -(PAD + 22 + 8)
  panel.sep:ClearAllPoints()
  panel.sep:SetPoint("TOPLEFT", PAD + 2, y)
  panel.sep:SetPoint("TOPRIGHT", -PAD, y)
  y = y - 6
  local nameW, countW = 0, 0
  for i, r in ipairs(info.reagents) do
    local row = panel.rows[i] or NewRow(i)
    row.icon:SetTexture(r.icon or 134400)
    row.name:SetText(r.name or "...")
    row.count:SetText(CountText(r.have or 0, r.need or 0))
    nameW = math.max(nameW, row.name:GetStringWidth())
    countW = math.max(countW, row.count:GetStringWidth())
    row._y = y - (i - 1) * ROW_H
    row:Show()
  end
  for i = #info.reagents + 1, #panel.rows do panel.rows[i]:Hide() end
  local rowW = ICON + 6 + nameW + 18 + countW
  panel.hint:SetText(L["CRAFTABLE_HINT"] or "Right-click: open the recipe")
  local w = math.max(headW, rowW, panel.hint:GetStringWidth()) + PAD * 2 + 2
  panel:SetWidth(math.ceil(w))
  for i = 1, #info.reagents do panel.rows[i]:SetWidth(rowW) end
  y = y - #info.reagents * ROW_H - 6
  panel.hint:ClearAllPoints()
  panel.hint:SetPoint("TOPLEFT", PAD + 2, y)
  panel:SetHeight(math.ceil(-y + 11 + PAD - 2))
  panel._n = #info.reagents
  if animate then
    panel._t = 0
    panel:SetAlpha(0)
  end
  CR._Step(animate and 0 or (panel._t or 99))
end

-- Fondu du panneau, puis chaque ligne glisse depuis la droite avec un decalage (cascade)
function CR._Step(t)
  local n = panel._n or 0
  local hintDelay = n * STAGGER
  local done = t >= hintDelay + ROW_DUR
  panel:SetAlpha(EaseOut(math.min(1, t / 0.12)))
  for i = 1, n do
    local row = panel.rows[i]
    local p = math.max(0, math.min(1, (t - (i - 1) * STAGGER) / ROW_DUR))
    local e = EaseOut(p)
    row:SetAlpha(e)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", PAD + 2 + SLIDE * (1 - e), row._y)
  end
  local ph = math.max(0, math.min(1, (t - hintDelay) / ROW_DUR))
  panel.hint:SetAlpha(EaseOut(ph))
  return done
end

local function PanelOnUpdate(self, elapsed)
  self._t = (self._t or 0) + elapsed
  if CR._Step(self._t) then self:SetScript("OnUpdate", nil) end
end

local function ShowPanel(m)
  EnsurePanel()
  panelOwner, panelProv, panelHandle = m.btn, m.prov, m.handle
  curFont = m.font
  Anchor(m)
  panel:Show()
  Fill(true)
  panel:SetScript("OnUpdate", PanelOnUpdate)
end

local function HidePanel(owner)
  if panel and (owner == nil or panelOwner == owner) then
    panel:SetScript("OnUpdate", nil)
    panel:Hide()
    panelOwner, panelHandle = nil, nil
  end
end

-- ── Fleche sur le bouton d'ingredient ─────────────────────────────────────────────────────────────────
local function PlaceArrow(m)
  m.arrow:ClearAllPoints()
  m.arrow:SetPoint("RIGHT", m, "LEFT", -ARROW_GAP - (m.arrowX or 0), 0)
end

local function MarkerOnUpdate(m, elapsed)
  local btn = m.btn
  local over = btn:IsVisible() and (btn:IsMouseOver() or m.hit:IsMouseOver())
  if over and not m.hover then
    m.hover = true
    m.wait = 0
  elseif not over and m.hover then
    m.hover = false
    m.wait = nil
    HidePanel(btn)
  end
  -- Glissement de la fleche vers la gauche (cote panneau) au survol, retour au repos sinon
  local target = m.hover and ARROW_SLIDE or 0
  local x = m.arrowX or 0
  if x ~= target then
    x = x + (target - x) * math.min(1, elapsed * 14)
    if math.abs(target - x) < 0.1 then x = target end
    m.arrowX = x
    PlaceArrow(m)
  end
  -- Ouverture apres une frame : survol confirme
  if m.hover and m.wait then
    m.wait = m.wait + elapsed
    if m.wait > 0.03 then
      m.wait = nil
      ShowPanel(m)
    end
  end
end

local function OnMouseUp(btn, button)
  local m = btn._aishCR
  if button ~= "RightButton" or not (m and m:IsShown() and m.handle) or not Enabled() then return end
  HidePanel()
  m.prov.Open(m.handle)
end

local function GetMarker(btn, iconRegion)
  local m = btn._aishCR
  if m then return m end
  m = CreateFrame("Frame", nil, btn)
  m:SetFrameLevel(btn:GetFrameLevel() + 3)
  m:SetAllPoints(iconRegion or btn)
  m:EnableMouse(false)
  m.btn = btn
  local arrow = m:CreateTexture(nil, "OVERLAY")
  local ai = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(ARROW_ATLAS)
  if ai and ai.width and ai.height and ai.height > 0 then
    arrow:SetAtlas(ARROW_ATLAS)
    m.arrowW = math.floor(ARROW_H * ai.width / ai.height + 0.5)
  else
    arrow:SetTexture(ARROW_FALLBACK)
    m.arrowW = ARROW_H
  end
  arrow:SetSize(m.arrowW, ARROW_H)
  m.arrow = arrow
  m.arrowX = 0
  PlaceArrow(m)
  -- Zone cliquable sur toute la course de la fleche : clic droit = ouvrir la recette, comme sur le bouton
  local hit = CreateFrame("Frame", nil, m)
  hit:SetPoint("RIGHT", m, "LEFT", 0, 0)
  hit:SetSize(ARROW_GAP + m.arrowW + ARROW_SLIDE, ARROW_H)
  hit:EnableMouse(true)
  hit:SetScript("OnMouseUp", function(_, button) OnMouseUp(btn, button) end)
  m.hit = hit
  m:SetScript("OnHide", function(self)
    self.wait = nil
    self.arrowX = 0
    PlaceArrow(self)
    if self.hover then self.hover = false; HidePanel(btn) end
  end)
  m:SetScript("OnUpdate", MarkerOnUpdate)
  btn:HookScript("OnMouseUp", OnMouseUp)
  btn._aishCR = m
  m:Hide()
  return m
end

local function SetMarker(btn, iconRegion, prov, handle, nameFS)
  if not handle then
    if btn._aishCR then btn._aishCR.handle = nil; btn._aishCR:Hide() end
    return
  end
  local m = GetMarker(btn, iconRegion)
  if m.handle ~= handle and m.hover then HidePanel(btn); m.hover = false end
  m.prov, m.handle = prov, handle
  m.font = FontFromButton(btn, nameFS)
  m:Show()
end

-- ── Retail : formulaire de recette ────────────────────────────────────────────────────────────────────
local function DecorateRetail()
  local pf = _G.ProfessionsFrame
  local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
  if not (form and form.reagentSlots) then return end
  local on = Enabled()
  local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
  for _, slots in pairs(form.reagentSlots) do
    for _, slot in ipairs(slots) do
      local btn = slot.Button
      if btn then
        local handle
        local rs = on and slot.GetReagentSlotSchematic and slot:GetReagentSlotSchematic()
        if rs and rs.reagentType == BASIC and rs.reagents then
          for _, r in ipairs(rs.reagents) do
            handle = Retail.Find(r.itemID)
            if handle then break end
          end
        end
        SetMarker(btn, nil, Retail, handle, slot.Name)
      end
    end
  end
end

local retailHooked
local function HookRetail()
  local pf = _G.ProfessionsFrame
  local form = pf and pf.CraftingPage and pf.CraftingPage.SchematicForm
  if retailHooked or not form then return end
  retailHooked = true
  hooksecurefunc(form, "Init", DecorateRetail)
end

-- ── Forever : TradeSkillFrame classique ───────────────────────────────────────────────────────────────
local function DecorateClassic(index)
  if not (_G.TradeSkillFrame and _G.TradeSkillFrame:IsShown()) then return end
  local on = Enabled()
  if on then ClassicScan() end
  index = index or (GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex())
  local n = (on and index and index > 0) and (GetTradeSkillNumReagents(index) or 0) or 0
  for r = 1, (_G.MAX_TRADE_SKILL_REAGENTS or 8) do
    local btn = _G["TradeSkillReagent" .. r]
    if btn then
      local handle
      if r <= n then handle = Classic.Find(ItemIDFromLink(GetTradeSkillReagentItemLink(index, r))) end
      SetMarker(btn, _G["TradeSkillReagent" .. r .. "IconTexture"], Classic, handle, _G["TradeSkillReagent" .. r .. "Name"])
    end
  end
end

local classicHooked
local function HookClassic()
  if classicHooked or not _G.TradeSkillFrame_SetSelection then return end
  classicHooked = true
  hooksecurefunc("TradeSkillFrame_SetSelection", function(id) DecorateClassic(id) end)
end

-- ── Evenements ────────────────────────────────────────────────────────────────────────────────────────
local function TryHook()
  if _G.ProfessionsFrame then HookRetail() end
  if _G.TradeSkillFrame_SetSelection then HookClassic() end
end

function CR.ApplySettings()
  TryHook()
  if not Enabled() then HidePanel() end
  if retailHooked then DecorateRetail() end
  if classicHooked then DecorateClassic() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "NEW_RECIPE_LEARNED", "TRADE_SKILL_DATA_SOURCE_CHANGED",
  "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED", "TRADE_SKILL_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == "Blizzard_Professions" or arg1 == "Blizzard_TradeSkillUI" then TryHook() end
  elseif event == "PLAYER_LOGIN" then
    TryHook()
  elseif event == "TRADE_SKILL_CLOSE" then
    HidePanel()
  elseif event == "NEW_RECIPE_LEARNED" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "TRADE_SKILL_SHOW" then
    rMap = nil
    TryHook()
  elseif event == "TRADE_SKILL_UPDATE" then
    -- Forever : liste chargee / modifiee -> reperage des recettes et detrompeurs a jour
    if classicHooked then DecorateClassic() end
  elseif event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" then
    -- Noms arrives du cache / stock modifie : panneau ouvert rafraichi, sans rejouer l'animation
    if panel and panel:IsShown() and panelHandle then Fill(false) end
  end
end)

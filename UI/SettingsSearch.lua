-- UI/SettingsSearch.lua : suggestions de la barre de recherche du GUI, facon moteur de recherche.
-- Pendant la frappe, les options les plus proches (Data/SearchIndex.lua) s'affichent sous la barre ;
-- un clic (ou Entree) ouvre leur page, deplie leur section, y fait defiler le panneau et encadre
-- l'option quelques instants. Le filtre de la sidebar (SettingsPanel.lua) reste inchange.
local _, ns = ...
local L = ns.L
local SW = ns.SharedWidgets
local Theme = ns.Theme

local S = {}
ns.SettingsSearch = S

local MAX_ROWS, ROW_H, DD_W = 8, 26, 380
local MIN_CHARS = 2
local LABEL_MAX = 70
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Accents -> lettre de base : "deplacer" trouve "Déplacer"
local FOLD = {}
do
  local groups = {
    a = "àâäáãåÀÂÄÁÃÅ", c = "çÇ", e = "éèêëÉÈÊË", i = "îïíìÎÏÍÌ", o = "ôöóòõÔÖÓÒÕ",
    u = "ùûüúÙÛÜÚ", y = "ÿýŸÝ", n = "ñÑ", oe = "œŒ", ae = "æÆ", ss = "ß",
  }
  for base, chars in pairs(groups) do
    for ch in chars:gmatch("[\192-\255][\128-\191]*") do FOLD[ch] = base end
  end
end

-- Texte affiche sans codes couleur / icones
local function Strip(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  s = s:gsub("|n", " "):gsub("[\r\n]", " "):gsub("[ \t]+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end

-- Minuscules sans accents ; withMap : position d'origine (debut / fin) de chaque octet produit
local function Norm(s, withMap)
  local out = {}
  local ostart, oend = withMap and {} or nil, withMap and {} or nil
  local n, i, len = 0, 1, #s
  while i <= len do
    local b = s:byte(i)
    local cl = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
    local ch = s:sub(i, i + cl - 1)
    local r = (cl == 1 and ch:lower()) or FOLD[ch] or ch
    out[#out + 1] = r
    if withMap then
      for _ = 1, #r do n = n + 1; ostart[n] = i; oend[n] = i + cl - 1 end
    end
    i = i + cl
  end
  return table.concat(out), ostart, oend
end

-- Cle de comparaison d'un texte de la page (en-tetes en majuscules suivis de "  +" / "  -", deux-points...)
local function TextKey(s)
  if type(s) ~= "string" or s == "" then return nil end
  local k = Norm(Strip(s))
  k = k:gsub("…", ""):gsub("[ \t%+%-:%.%*]+$", "")
  return k
end

-- ---------------------------------------------------------------------------
-- Index des options : une entree par libelle et par page, info-bulle (_TT) rattachee a son option
-- ---------------------------------------------------------------------------
local entries

local function BuildEntries()
  entries = {}
  local MF = ns.SettingsPanel
  local data = MF and MF._searchData
  if not (data and ns.SEARCH_INDEX) then return end
  local catLabel, order, n = {}, {}, 0
  for _, c in ipairs(data.categories) do catLabel[c.id] = c.label end
  for _, grp in ipairs(ns._sidebarGroups or {}) do
    for _, cid in ipairs(grp.ids) do
      if not order[cid] then n = n + 1; order[cid] = n end
    end
  end
  local heroic = ns.HasHeroicFeatures and ns.HasHeroicFeatures()
  local function Text(key)
    if not heroic and data.heroicKeys[key] then return nil end
    if not ns.IsForever and data.foreverKeys[key] then return nil end
    local t = rawget(L, key)
    return type(t) == "string" and t or nil
  end

  for catId, raw in pairs(ns.SEARCH_INDEX) do
    if order[catId] and catLabel[catId] then
      -- "F:CLE" / "R:CLE" : option posee seulement sur Forever / Retail (cf. generate_search_index.py)
      local keys = {}
      for k in raw:gmatch("%S+") do
        local cl, key = k:match("^([FR]):(.+)$")
        if not cl or (cl == "F") == (ns.IsForever and true or false) then keys[#keys + 1] = key or k end
      end
      local tips, seen = {}, {}
      for _, key in ipairs(keys) do
        local base = key:match("^(.+)_TT$")
        local t = base and Text(key)
        if t then tips[base] = Norm(Strip(t)) end
      end
      for _, key in ipairs(keys) do
        local t = not key:find("_TT$") and Text(key)
        if t then
          local label = Strip(t)
          -- Libelles dynamiques ("%s", "%d") ou paragraphes d'aide : pas des options
          -- Messages de confirmation ("... copies.") : pas des options non plus
          if label ~= "" and #label <= LABEL_MAX and not label:find("%%[%-%d%.]*[sdfi]")
              and not (label:find("[%.!]$") and not label:find("%.%.%.$"))
              and not label:find("^%(") then   -- notes entre parentheses sous une option
            local nl = Norm(label)
            local id = nl
            local prev = seen[id]
            if prev then
              if tips[key] then prev.tip = prev.tip .. " " .. tips[key] end
            else
              local e = { cat = catId, page = catLabel[catId], order = order[catId], label = label,
                          n = nl, k = TextKey(t), tip = tips[key] or "" }
              seen[id] = e
              entries[#entries + 1] = e
            end
          end
        end
      end
    end
  end
end

local function IsWordStart(s, pos)
  return pos == 1 or not s:sub(pos - 1, pos - 1):find("[%w\128-\255]")
end

-- Rang d'une entree (plus petit = meilleur) et position du terme dans le libelle normalise
local function Score(e, q, words)
  local s = e.n
  if s == q then return 0, 1, #q end
  if s:sub(1, #q) == q then return 1, 1, #q end
  local pos, first = 1, nil
  while true do
    local p = s:find(q, pos, true)
    if not p then break end
    first = first or p
    if IsWordStart(s, p) then return 2, p, #q end
    pos = p + 1
  end
  if first then return 3, first, #q end
  if #words > 1 then
    local inLabel = true
    for _, w in ipairs(words) do
      if not s:find(w, 1, true) then
        inLabel = false
        if not e.tip:find(w, 1, true) then return nil end
      end
    end
    local p = s:find(words[1], 1, true)
    return inLabel and 4 or 5, p, p and #words[1]
  end
  if e.tip:find(q, 1, true) then return 5 end
  return nil
end

-- Textes reellement affiches par une page deja construite : une option que la page n'a pas posee
-- (reglage reserve a un client ou a une API, a une classe...) n'est pas proposee. Page pas encore
-- construite : on s'en tient a l'index. Vide a chaque prise de focus (pages reconstruites entre-temps).
local pageTexts = {}

local function CollectTexts(f, set)
  for _, r in ipairs({ f:GetRegions() }) do
    if r:GetObjectType() == "FontString" then
      local k = TextKey(r:GetText())
      if k then set[k] = true end
    end
  end
  for _, c in ipairs({ f:GetChildren() }) do CollectTexts(c, set) end
end

local function PageHas(e)
  local MF = ns.SettingsPanel
  local cat = MF.categoryRedirect[e.cat] or e.cat
  local entry = MF._searchData.containers[cat]
  if not entry then return true end
  local set = pageTexts[entry.frame]
  if not set then
    set = {}
    CollectTexts(entry.frame, set)
    pageTexts[entry.frame] = set
  end
  return set[e.k] or false
end

local function Search(q)
  if not entries then BuildEntries() end
  local words = {}
  for w in q:gmatch("[^ ]+") do words[#words + 1] = w end
  local res = {}
  for _, e in ipairs(entries) do
    local sc, p, l = Score(e, q, words)
    if sc and not PageHas(e) then sc = nil end
    if sc then res[#res + 1] = { e = e, sc = sc, p = p, l = l } end
  end
  table.sort(res, function(a, b)
    if a.sc ~= b.sc then return a.sc < b.sc end
    if #a.e.label ~= #b.e.label then return #a.e.label < #b.e.label end
    if a.e.order ~= b.e.order then return a.e.order < b.e.order end
    return a.e.label < b.e.label
  end)
  for i = #res, MAX_ROWS + 1, -1 do res[i] = nil end
  return res
end

-- ---------------------------------------------------------------------------
-- Saut vers l'option : page, section depliee, defilement, encadre
-- ---------------------------------------------------------------------------
local function IsDescendant(obj, root)
  local p = obj:GetParent()
  while p do
    if p == root then return true end
    p = p:GetParent()
  end
  return false
end

-- FontString de la page dont le texte correspond a `key` (visible de preference)
local function FindText(root, key)
  local best
  local function Visit(f)
    for _, r in ipairs({ f:GetRegions() }) do
      if r:GetObjectType() == "FontString" and TextKey(r:GetText()) == key then
        if r:IsVisible() then return r end
        best = best or r
      end
    end
    for _, c in ipairs({ f:GetChildren() }) do
      local hit = Visit(c)
      if hit then return hit end
    end
  end
  return Visit(root) or best
end

-- Section repliable (ctx de la page) qui contient la FontString
local function SectionOf(ctx, fs)
  if not (ctx and ctx.flow) then return nil end
  local map = {}
  for _, item in ipairs(ctx.flow) do
    if item.kind == "widget" or item.kind == "manual" then
      map[item.w] = item.section or false
    elseif item.widgets then
      for _, w in ipairs(item.widgets) do map[w] = item.section or false end
    end
  end
  local p = fs:GetParent()
  while p do
    local s = map[p]
    if s ~= nil then return s or nil end
    p = p:GetParent()
  end
end

local function ScrollTo(region)
  local data = ns.SettingsPanel._searchData
  local sf, content = data.scrollFrame, data.content
  if not IsDescendant(region, content) then return end
  local rt, ct = region:GetTop(), content:GetTop()
  if not (rt and ct) then return end
  local range = sf:GetVerticalScrollRange() or 0
  local target = math.max(0, math.min(range, ct - rt - (sf:GetHeight() or 0) * 0.3))
  local from = sf:GetVerticalScroll() or 0
  if SW.animEnabled then
    SW.StartAnim("settingsSearchScroll", 0.25, function(e) sf:SetVerticalScroll(from + (target - from) * e) end)
  else
    sf:SetVerticalScroll(target)
  end
end

local hl
local function Highlight(fs, cat)
  local MF = ns.SettingsPanel
  local content = MF._searchData.content
  if not hl then
    hl = CreateFrame("Frame", nil, MF, "BackdropTemplate")
    hl:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    hl:EnableMouse(false)
    hl:Hide()
    hl:SetScript("OnUpdate", function(self)
      local t = GetTime() - self.t0
      if t >= 2 or MF:GetActiveCategory() ~= self.cat then self:Hide(); return end
      -- 3 pulsations puis fondu
      local a = t < 1.4 and (0.35 + 0.65 * (0.5 + 0.5 * math.cos(2 * math.pi * t / (1.4 / 3)))) or (2 - t) / 0.6
      self:SetAlpha(a)
    end)
  end
  local g = Theme.gold
  hl:SetBackdropColor(g[1], g[2], g[3], 0.18)
  hl:SetBackdropBorderColor(g[1], g[2], g[3], 1)
  local parent = IsDescendant(fs, content) and content or MF
  hl:SetParent(parent)
  hl:SetFrameStrata(MF:GetFrameStrata())
  hl:SetFrameLevel(math.min(9000, parent:GetFrameLevel() + 100))
  local w = fs:GetStringWidth() or 40
  local fw = fs:GetWidth() or 0
  if fw > 1 and fw < w then w = fw end
  local h = fs:GetStringHeight() or 0
  if h < 8 then h = 12 end
  local j = fs:GetJustifyH()
  local pt = (j == "CENTER" and "CENTER") or (j == "RIGHT" and "RIGHT") or "LEFT"
  hl:ClearAllPoints()
  hl:SetPoint(pt, fs, pt, (pt == "LEFT" and -6) or (pt == "RIGHT" and 6) or 0, 0)
  hl:SetSize(w + 12, h + 8)
  hl.cat = cat
  hl.t0 = GetTime()
  hl:SetAlpha(1)
  hl:Show()
end

local function Reveal(fs, sec, cat, stackHdr)
  if not fs:IsVisible() then
    -- Option masquee par la page elle-meme (reglage conditionnel) : on montre sa section
    local hdr = stackHdr or (sec and sec.header)
    fs = hdr and hdr._lbl
    if not (fs and fs:IsVisible()) then return end
  end
  ScrollTo(fs)
  Highlight(fs, cat)
end

local function Locate(cat, e, tries)
  local MF = ns.SettingsPanel
  local entry = MF._searchData.containers[cat]
  if not (entry and entry.frame:IsShown()) then
    if tries < 6 then C_Timer.After(0.1, function() Locate(cat, e, tries + 1) end) end
    return
  end
  local fs = e.k and FindText(entry.frame, e.k)
  if not fs then return end
  local sec = SectionOf(SW.pageCtx[cat], fs)
  local unfolded = false
  if sec and sec.collapsed and sec.header and sec.header._baseText then
    MF:OpenSection(cat, sec.header._baseText)
    unfolded = true
  end
  -- Sections des pages Auras (SW.CreateSectionStack) : de la plus externe a la plus interne
  local stack, stackHdr = {}, nil
  local p = fs:GetParent()
  if p and p._searchUnfold then unfolded = true end   -- en-tete de section : son contenu s'ouvre
  while p and p ~= entry.frame do
    if p._searchUnfold then
      table.insert(stack, 1, p)
      stackHdr = stackHdr or p._searchHeader
    end
    p = p:GetParent()
  end
  for _, sub in ipairs(stack) do
    if not sub:IsShown() then unfolded = true end
    sub._searchUnfold()
  end
  C_Timer.After(unfolded and 0.12 or 0.02, function() Reveal(fs, sec, cat, stackHdr) end)
end

function S.GoTo(e)
  local MF = ns.SettingsPanel
  if not MF:IsShown() then MF:ShowUI() end
  MF:SelectCategory(e.cat)
  local cat = MF.categoryRedirect[e.cat] or e.cat
  C_Timer.After(0.05, function() Locate(cat, e, 1) end)
end

-- ---------------------------------------------------------------------------
-- Liste de suggestions sous la barre de recherche
-- ---------------------------------------------------------------------------
local box, dd, rows
local results, sel = {}, 1

local function HexGold()
  local g = Theme.gold
  local function c(v) return math.floor(math.min(1, v * 1.3) * 255 + 0.5) end
  return string.format("|cff%02x%02x%02x", c(g[1]), c(g[2]), c(g[3]))
end

local function Esc(s) return (s:gsub("|", "||")) end

-- Libelle avec le terme tape en or
local function Colorize(r)
  local label = r.e.label
  if not (r.p and r.l) then return Esc(label) end
  local _, ostart, oend = Norm(label, true)
  local a, b = ostart[r.p], oend[r.p + r.l - 1]
  if not (a and b) then return Esc(label) end
  return Esc(label:sub(1, a - 1)) .. HexGold() .. Esc(label:sub(a, b)) .. "|r" .. Esc(label:sub(b + 1))
end

local function Paint()
  for i, row in ipairs(rows) do
    local on = (i == sel)
    row.bg:SetShown(on)
    row.bar:SetShown(on)
  end
end

local function Open(i)
  local r = results[i]
  if not r then return end
  dd:Hide()
  box:ClearFocus()
  S.GoTo(r.e)
end

local function CreateDropdown()
  local MF = ns.SettingsPanel
  dd = CreateFrame("Frame", nil, MF, "BackdropTemplate")
  dd:SetFrameStrata("FULLSCREEN_DIALOG")
  dd:SetClampedToScreen(true)
  dd:SetWidth(DD_W)
  dd:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -3)
  dd:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  dd:SetBackdropColor(0.03, 0.03, 0.035, 0.97)
  local g = Theme.gold
  dd:SetBackdropBorderColor(g[1], g[2], g[3], 0.6)
  dd:EnableMouse(true)
  dd:Hide()
  MF:HookScript("OnHide", function() dd:Hide() end)

  rows = {}
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Button", nil, dd)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", dd, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", dd, "TOPRIGHT", -1, -1 - (i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(g[1], g[2], g[3], 0.16)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetWidth(2)
    r.bar:SetColorTexture(g[1], g[2], g[3], 1)
    r.page = r:CreateFontString(nil, "OVERLAY")
    r.page:SetFont(ns.Media.fontGui, 10, "")
    r.page:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.page:SetJustifyH("RIGHT")
    r.page:SetWordWrap(false)
    r.page:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3], 1)
    r.text = r:CreateFontString(nil, "OVERLAY")
    r.text:SetFont(ns.Media.fontGui, 12, "")
    r.text:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.text:SetPoint("RIGHT", r.page, "LEFT", -10, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.text:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3], 1)
    r:SetScript("OnEnter", function() sel = i; Paint() end)
    r:SetScript("OnClick", function() Open(i) end)
    rows[i] = r
  end
end

local function Update()
  if not dd then return end
  local q = Norm(Strip(box:GetText() or "")):gsub("[ \t]+", " "):gsub("^ ", ""):gsub(" $", "")
  if #q < MIN_CHARS or not box:HasFocus() then dd:Hide(); return end
  results = Search(q)
  if #results == 0 then dd:Hide(); return end
  for i, row in ipairs(rows) do
    local r = results[i]
    if r then
      row.page:SetWidth(0)
      row.page:SetText(r.e.page)
      row.page:SetWidth(math.min(140, row.page:GetStringWidth() + 2))
      row.text:SetText(Colorize(r))
      row:Show()
    else
      row:Hide()
    end
  end
  sel = 1
  Paint()
  dd:SetHeight(#results * ROW_H + 2)
  dd:Show()
end

function S.Attach(searchBox)
  box = searchBox
  CreateDropdown()
  box:HookScript("OnTextChanged", Update)
  box:HookScript("OnEditFocusGained", function()
    wipe(pageTexts)
    Update()
  end)
  box:HookScript("OnEditFocusLost", function()
    -- Clic sur une suggestion : la perte de focus precede le clic, la liste doit rester le temps du clic
    if dd:IsMouseOver() then
      C_Timer.After(0.3, function() if not box:HasFocus() then dd:Hide() end end)
    else
      dd:Hide()
    end
  end)
  box:SetScript("OnArrowPressed", function(_, key)
    if not dd:IsShown() or #results == 0 then return end
    if key == "DOWN" then sel = sel % #results + 1 elseif key == "UP" then sel = (sel - 2) % #results + 1 end
    Paint()
  end)
  box:SetScript("OnTabPressed", function()
    if not dd:IsShown() or #results == 0 then return end
    sel = (IsShiftKeyDown() and (sel - 2) or sel) % #results + 1
    Paint()
  end)
  box:SetScript("OnEnterPressed", function(self)
    if dd:IsShown() and results[sel] then Open(sel) else self:ClearFocus() end
  end)
end

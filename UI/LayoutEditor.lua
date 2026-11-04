-- UI/LayoutEditor.lua : mode disposition du GUI (/aishlayout). Sur les pages construites par le moteur (NewLayout,
-- UI/SettingsPanel.lua), les widgets standards (curseurs, menus, couleurs, cases, rangees d'alignement, boutons) se
-- rangent, section par section, sur une grille de N colonnes. En mode disposition ils deviennent inertes et se
-- deplacent au glisser-deposer (cale sur une case de la grille, d'une section a l'autre) ; sur l'en-tete d'une section :
-- nouvelle section en dessous, separateur, -/+ colonnes, reinitialiser (et supprimer pour une section ajoutee) ;
-- clic droit sur un widget ou un titre = renommer, sur un separateur = le retirer. Les pages de la sidebar se
-- reorganisent aussi (cf. BuildSidebar dans UI/SettingsPanel.lua).
-- Disposition d'une section : celle enregistree (AishaddonDB._guiLayout, compte), sinon celle du code
-- (Data/GuiLayout.lua, reportee depuis "Exporter"), sinon les rangees de la page. Le reste de la page (blocs faits a
-- la main, apercus) ne bouge pas.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local LE = { editing = false }
ns.LayoutEditor = LE

local MOVABLE = { slider = true, dropdown = true, color = true, check = true, align = true, button = true, divider = true,
                  subheader = true }
-- Pseudo-widgets qui occupent la fin de leur rangee (de leur colonne au bord droit)
local FULL_ROW = { divider = true, subheader = true }
local DEFAULT_COLS, MIN_COLS, MAX_COLS = 4, 1, 6
local ROW_GAP = 4
local DIV_PREFIX = "__div:"
local SEC_PREFIX = "__sec:"
local EMPTY_H = 30   -- zone de depot d'une section vide (mode disposition)

-- Tables de reglages aux widgets identiques (meme page, selecteur de barre) : une seule disposition pour les deux
local ID_ALIAS = { cdmUtility = "cdmEssential" }

local function Kind(w) return w._gridKind or w._leKind end

local function Store()
  AishaddonDB = AishaddonDB or {}
  AishaddonDB._guiLayout = AishaddonDB._guiLayout or {}
  return AishaddonDB._guiLayout
end

-- Cle de section : cle de locale de son titre (meme cle quelle que soit la langue), sinon le titre affiche.
-- Plusieurs cles peuvent porter le meme texte : toutes sont candidates, la plus petite sert a l'enregistrement.
local reverse
local function SectionKeys(baseText)
  if not reverse then
    reverse = {}
    for k, v in pairs(L) do
      if type(v) == "string" then
        local u = v:upper()
        reverse[u] = reverse[u] or {}
        table.insert(reverse[u], k)
      end
    end
    for _, list in pairs(reverse) do table.sort(list) end
  end
  return reverse[baseText] or {}
end

local function FindIn(tbl, keys, baseText)
  if not tbl then return nil end
  for _, k in ipairs(keys) do if tbl[k] then return tbl[k], k end end
  if baseText and tbl[baseText] then return tbl[baseText], baseText end
  return nil
end

-- Titres renommes (titre de page "__title", sections par leur cle) : AishaddonDB._guiTitles[catId][cle] = texte
local function Titles(catId, create)
  AishaddonDB = AishaddonDB or {}
  AishaddonDB._guiTitles = AishaddonDB._guiTitles or {}
  if create then AishaddonDB._guiTitles[catId] = AishaddonDB._guiTitles[catId] or {} end
  return AishaddonDB._guiTitles[catId]
end

local function SaveTitle(catId, key, text)
  local t = Titles(catId, true)
  t[key] = text
  if not next(t) then AishaddonDB._guiTitles[catId] = nil end
end

local function Save(catId, secId, layout)
  local s = Store()
  s[catId] = s[catId] or {}
  s[catId][secId] = layout
  if not next(s[catId]) then s[catId] = nil end
end

-- Identifiant stable d'un widget : cle DB, sinon type + libelle + section d'origine (pages qui lient leurs reglages
-- elles-memes : un meme libelle revient d'une section a l'autre) ; doublons numerotes (a l'echelle de la page)
local function WidgetId(w, used, secKey)
  local id
  if w._leId then
    id = w._leId   -- identifiant fixe pose par la page (reglages communs a plusieurs elements, cf. Ecran AFK)
  elseif w._dbKey and w._subKey then
    local sub = tostring(w._subKey)
    -- Reglages par spe du texte secondaire du cercle central (ns.SecResSpecKey) : meme identifiant pour toutes les spes
    if w._dbKey == "resourceCircle" then sub = sub:gsub("^secRes_%d+_", "") end
    id = (ID_ALIAS[w._dbKey] or w._dbKey) .. "." .. sub
  else
    local lbl = w.label or w._lbl
    local t = w._leText or (lbl and lbl.GetText and lbl:GetText())   -- sous-titre : texte avant mise en majuscules
    id = (Kind(w) or "?") .. ":" .. ((t and t ~= "") and t or "?") .. (secKey and ("@" .. secKey) or "")
  end
  if used[id] then
    local n = 2
    while used[id .. "#" .. n] do n = n + 1 end
    id = id .. "#" .. n
  end
  used[id] = true
  return id
end

local function CopyRows(rows)
  local out = {}
  for r, row in ipairs(rows) do
    out[r] = {}
    for c, id in pairs(row) do out[r][c] = id end
  end
  return out
end

local function Compact(rows)
  local out = {}
  for _, row in ipairs(rows) do if next(row) then out[#out + 1] = row end end
  return out
end

local function IsDivId(id) return type(id) == "string" and id:sub(1, #DIV_PREFIX) == DIV_PREFIX end

-- Separateur horizontal (pseudo-widget du mode disposition) : filet fin, de sa colonne a la fin de la rangee
local function NewDivider(container)
  local f = CreateFrame("Frame", nil, container)
  f:SetHeight(9)
  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetHeight(1)
  if SW.PixelLine then SW.PixelLine(line) end
  line:SetPoint("LEFT")
  line:SetPoint("RIGHT")
  line:SetColorTexture(1, 1, 1, 0.12)
  f._leKind = "divider"
  return f
end

local function LabelOf(w) return w.label or w._lbl end

-- Cle d'un en-tete : "__title" pour le titre de la page, cle propre d'une section ajoutee, sinon cle de locale
local function HeaderKey(ctx, hdr)
  if hdr == ctx._title then return "__title" end
  if hdr._leKey then return hdr._leKey end
  if hdr._leSecKey then return hdr._leSecKey end   -- titre variable, cle fixee par la page
  local base = hdr._baseText or ""
  return SectionKeys(base)[1] or base
end

-- Titre affiche d'un en-tete (le signe +/- est ajoute par SetHeaderCollapsedState)
local function SetHeaderText(hdr, text)
  hdr._displayText = text and text:upper() or nil
  if hdr._lbl then
    local shown = hdr._displayText or hdr._baseText or ""
    if hdr._collapseReady and hdr._collapsed ~= nil then shown = shown .. (hdr._collapsed and "  +" or "  -") end
    hdr._lbl:SetText(shown)
  end
end

-- Texte d'un libelle / titre du code : par langue ({ frFR = ..., enUS = ... }), repli anglais
local function Localized(t)
  if type(t) == "table" then return t[GetLocale()] or t.enUS end
  return t
end

-- Titre d'un en-tete : renomme en jeu, sinon renomme dans le code (Data/GuiLayout.lua, __titles). Un titre enregistre
-- identique a celui du code est efface (le code prend le relais).
local function TitleFor(catId, key)
  local saved = Titles(catId)
  local code = ns.GUI_LAYOUT and ns.GUI_LAYOUT[catId] and ns.GUI_LAYOUT[catId].__titles
  local c = code and Localized(code[key])
  local s = saved and saved[key]
  if s and c and s:upper() == c:upper() then SaveTitle(catId, key, nil); s = nil end
  return s or c
end

local function ApplyTitles(ctx, catId)
  if ctx._title then
    local t = TitleFor(catId, "__title")
    if t then SetHeaderText(ctx._title, t) end
  end
  for _, sec in ipairs(ctx.sections) do
    if not sec.header._leKey then
      local t = TitleFor(catId, HeaderKey(ctx, sec.header))
      if t then SetHeaderText(sec.header, t) end
    end
  end
end

local function ItemWidgets(item)
  return (item.kind == "widget" and { item.w }) or (item.kind == "row" and item.widgets) or nil
end

-- Rangees de la page : widgets deplacables de chaque section (pool commun a la page), places par la page
local function Analyse(ctx, colW4, gap)
  local unit = colW4 + gap
  local pool, used = { byId = {}, origin = {} }, {}
  for _, sec in ipairs(ctx.sections) do sec._leInfo = { rows = {} } end
  for idx, item in ipairs(ctx.flow) do
    local sec = item.section
    if sec and sec._leInfo and not (item.kind == "widget" and item.w == sec.header) then
      local ws = ItemWidgets(item)
      -- Rangee deplacable : uniquement des widgets standards (cases vides des pages a grille propre comprises,
      -- cf. Row dans UI/CastBarsPage.lua / UI/UnitBarsPage.lua) et au moins un vrai widget
      local movable, real = ws and #ws > 0, 0
      if movable then
        for _, w in ipairs(ws) do
          if w._leEmpty then
          elseif MOVABLE[Kind(w)] then real = real + 1
          else movable = false end
        end
      end
      if movable and real > 0 then
        local info = sec._leInfo
        local row = {}
        local x = 0   -- placement libre (sans positions de grille) : x cumule comme dans PlaceItem
        for i, w in ipairs(ws) do
          local wx = (item.kind == "row" and item.xs and item.xs[i]) or x
          x = x + (w:GetWidth() or 0) + (item.gap or gap)
          if not w._leEmpty then
            local col = (item.kind == "row" and math.floor(wx / unit + 0.5) + 1) or i
            while row[col] do col = col + 1 end
            local id = WidgetId(w, used, ctx.noGrid and HeaderKey(ctx, sec.header) or nil)
            pool.byId[id] = w
            pool.origin[id] = sec
            row[col] = id
          end
        end
        info.rows[#info.rows + 1] = row
        item._leMovable = true
        info.first = info.first or idx
        info.last = idx
      end
    end
  end
  return pool
end

-- Sections ajoutees en mode disposition : en-tete insere apres sa section de reference (ou en fin de page)
local function AddCustomSections(ctx, container, catId, list, cw)
  for _, def in ipairs(list or {}) do
    local after
    for _, sec in ipairs(ctx.sections) do
      if HeaderKey(ctx, sec.header) == def.after then after = sec end
    end
    local hdr = SW.CreateSectionHeader(container, TitleFor(catId, def.id) or L["LAYOUT_NEW_SECTION"], cw)
    hdr._leKey = def.id
    local newSec = { header = hdr }
    -- Position dans la liste des sections et dans le flux : apres le dernier element de la section de reference
    local si = #ctx.sections + 1
    for i, sec in ipairs(ctx.sections) do if sec == after then si = i + 1 end end
    table.insert(ctx.sections, si, newSec)
    local fi = #ctx.flow
    if after then
      for i, item in ipairs(ctx.flow) do if item.section == after then fi = i end end
    end
    table.insert(ctx.flow, fi + 1, { kind = "spacer", h = 6, section = after })
    table.insert(ctx.flow, fi + 2, { kind = "widget", w = hdr, section = newSec })
    hdr:Show()
  end
end

-- Identifiants du code (Data/GuiLayout.lua) independants de la langue : un widget sans cle DB y est note par la cle
-- de locale de son libelle, "type:$CLE", et de sa section d'origine, "@$CLE" (pages qui lient leurs reglages
-- elles-memes) ; traduits ici dans la langue du client pour retrouver l'identifiant calcule par WidgetId.
local function TranslateId(id)
  if type(id) ~= "string" then return id end
  local kind, body, rest = id:match("^(%a+):([^@#]*)(.*)$")
  if not kind or not (body:find("^%$") or rest:find("@%$")) then return id end
  rest = rest:gsub("@%$([%w_]+)", function(sk)
    local t = L[sk]
    if type(t) ~= "string" then return "@" .. sk end
    local u = t:upper()
    return "@" .. (SectionKeys(u)[1] or u)
  end)
  local key = body:match("^%$([%w_]+)$")
  if key then
    local text = L[key]
    body = type(text) == "string" and text or key
  end
  return kind .. ":" .. body .. rest
end

local translated = setmetatable({}, { __mode = "k" })
function LE.Translated(src)
  if not src then return nil end
  if translated[src] then return translated[src] end
  local out = { cols = src.cols, rows = {}, labels = nil }
  for r, row in ipairs(src.rows or {}) do
    out.rows[r] = {}
    for c, id in pairs(row) do out.rows[r][c] = TranslateId(id) end
  end
  if src.labels then
    out.labels = {}
    for id, text in pairs(src.labels) do out.labels[TranslateId(id)] = text end
  end
  translated[src] = out
  return out
end

-- Deux dispositions identiques : colonnes, cases (memes widgets aux memes places) et libelles (ceux du code, par
-- langue, compares dans la langue du client)
local function LabelText(t)
  if type(t) == "table" then return t[GetLocale()] or t.enUS end
  return t
end
function LE.SameLayout(a, b)
  if (a.cols or DEFAULT_COLS) ~= (b.cols or DEFAULT_COLS) then return false end
  local ra, rb = a.rows or {}, b.rows or {}
  if #ra ~= #rb then return false end
  for r = 1, #ra do
    for c, id in pairs(ra[r]) do if rb[r][c] ~= id then return false end end
    for c, id in pairs(rb[r]) do if ra[r][c] ~= id then return false end end
  end
  local la, lb = a.labels or {}, b.labels or {}
  for k, v in pairs(la) do if LabelText(v) ~= LabelText(lb[k]) then return false end end
  for k, v in pairs(lb) do if LabelText(v) ~= LabelText(la[k]) then return false end end
  return true
end

-- Appele au debut de ctx:Finalize (page du moteur) : sections ajoutees, puis grille de N colonnes pour chaque section
-- qui a une disposition (enregistree, du code, toutes en mode disposition, ou qui a perdu / recu un widget)
function LE.Apply(ctx, container, catId, colWFn, gap)
  if not (ctx._isPage and catId) then return end
  ApplyTitles(ctx, catId)
  if ctx._noCollapse then return end
  if ctx._tracked ~= #ctx.widgets or math.abs(ctx.y - ctx._shadowY) >= 0.5 or #ctx.sections == 0 then return end
  local colW4 = colWFn()
  local cw = colW4 * DEFAULT_COLS + gap * (DEFAULT_COLS - 1)
  ctx._le = { catId = catId, gap = gap, cw = cw }
  local saved = Store()[catId]
  local code = ns.GUI_LAYOUT and ns.GUI_LAYOUT[catId]

  -- Sections ajoutees enregistrees identiques a celles du code : effacees (le code prend le relais)
  if saved and saved.__sections and code and code.__sections and #saved.__sections == #code.__sections then
    local same = true
    for i, def in ipairs(saved.__sections) do
      local c = code.__sections[i]
      if def.id ~= c.id or def.after ~= c.after then same = false end
    end
    if same then
      saved.__sections = nil
      if not next(saved) then Store()[catId] = nil; saved = nil end
    end
  end
  AddCustomSections(ctx, container, catId, (saved and saved.__sections) or (code and code.__sections), cw)
  local pool = Analyse(ctx, colW4, gap)

  -- Disposition source de chaque section ; ancienne entree enregistree sous le titre affiche rangee sous sa cle
  local srcOf, claim = {}, {}
  for _, sec in ipairs(ctx.sections) do
    local base = sec.header._baseText
    local keys = sec.header._leKey and { sec.header._leKey }
      or (sec.header._leSecKey and { sec.header._leSecKey }) or SectionKeys(base or "")
    local secId = keys[1] or base
    local fromSaved, savedKey = FindIn(saved, keys, base)
    if fromSaved and savedKey ~= secId then Save(catId, savedKey, nil); Save(catId, secId, fromSaved) end
    local fromCode = LE.Translated(FindIn(code, keys, base))
    -- Disposition du code qui place un widget identifie par son libelle introuvable ici (libelle modifie depuis le
    -- report) : ignoree, la section garde la disposition de la page
    if fromCode then
      for _, row in ipairs(fromCode.rows or {}) do
        for _, id in pairs(row) do
          if not IsDivId(id) and not id:find("^[%w_]+%.") and not pool.byId[id] then fromCode = nil; break end
        end
        if not fromCode then break end
      end
    end
    -- Copie enregistree identique a la disposition du code (reportee depuis l'export) : effacee, le code prend le relais
    if fromSaved and fromCode and LE.SameLayout(fromSaved, fromCode) then
      Save(catId, secId, nil)
      fromSaved = nil
    end
    srcOf[sec] = fromSaved or fromCode
    sec._leId = secId
    sec._leCustom = fromSaved ~= nil
    -- Widgets places par cette disposition (le premier qui le liste le garde) ; separateurs crees
    for _, row in ipairs(srcOf[sec] and srcOf[sec].rows or {}) do
      for _, id in pairs(row) do
        if IsDivId(id) and not pool.byId[id] then pool.byId[id] = NewDivider(container) end
        if pool.byId[id] and not claim[id] then claim[id] = sec end
      end
    end
  end

  -- Sections a recomposer
  local layouts = {}
  for _, sec in ipairs(ctx.sections) do
    local info, src = sec._leInfo, srcOf[sec]
    local lost = false
    for _, row in ipairs(info.rows) do
      for _, id in pairs(row) do if claim[id] and claim[id] ~= sec then lost = true end end
    end
    if src or lost or (LE.editing and sec.header._baseText) then
      local rows, seen = {}, {}
      for r, row in ipairs(src and src.rows or {}) do
        rows[r] = {}
        for c, id in pairs(row) do
          if claim[id] == sec and not seen[id] then rows[r][c] = id; seen[id] = true end
        end
      end
      -- Widgets de la section que personne n'a places : en fin (rangees d'origine si rien n'est enregistre)
      for _, row in ipairs(info.rows) do
        local nr = {}
        for c, id in pairs(row) do
          if not claim[id] and not seen[id] then nr[c] = id; seen[id] = true end
        end
        if next(nr) then
          if src then for _, id in pairs(nr) do rows[#rows + 1] = { [1] = id } end else rows[#rows + 1] = nr end
        end
      end
      layouts[sec] = { cols = math.max(MIN_COLS, math.min(MAX_COLS, src and src.cols or DEFAULT_COLS)),
                       rows = Compact(rows), labels = src and src.labels }
    end
  end

  -- Grille de chaque section recomposee
  local grids = {}
  for sec, layout in pairs(layouts) do
    local n = layout.cols
    local colW = math.floor((cw - (n - 1) * gap) / n)
    local function Width(w, c) return FULL_ROW[Kind(w)] and (cw - (c - 1) * (colW + gap)) or colW end
    local grid = {}
    for r, row in ipairs(layout.rows) do
      local ws, xs, rowH = {}, {}, 0
      for c = 1, n do
        local w = row[c] and pool.byId[row[c]]
        if w then
          w:SetWidth(Width(w, c))
          ws[#ws + 1] = w
          xs[#xs + 1] = (c - 1) * (colW + gap)
          rowH = math.max(rowH, w:GetHeight() or 22)
        end
      end
      if #ws > 0 then
        if #grid > 0 then grid[#grid + 1] = { kind = "spacer", h = ROW_GAP, section = sec } end
        grid[#grid + 1] = { kind = "row", widgets = ws, gap = gap, xs = xs, centered = true, rowH = rowH,
                            section = sec, _leRow = r }
      end
      for c, id in pairs(row) do
        if c > n and pool.byId[id] then
          local w = pool.byId[id]
          w:SetWidth(Width(w, 1))
          grid[#grid + 1] = { kind = "spacer", h = ROW_GAP, section = sec }
          grid[#grid + 1] = { kind = "row", widgets = { w }, gap = gap, xs = { 0 }, centered = true,
                              rowH = w:GetHeight() or 22, section = sec }
        end
      end
    end
    if #grid == 0 and LE.editing then grid[1] = { kind = "spacer", h = EMPTY_H, section = sec } end
    -- Libelles renommes
    for id, text in pairs(layout.labels or {}) do
      local w = pool.byId[id]
      local lbl = w and LabelOf(w)
      if lbl and lbl.SetText then
        w._leOrigLabel = w._leOrigLabel or lbl:GetText()
        -- Libelle du code : par langue ({ frFR = ..., enUS = ... }), repli anglais
        if type(text) == "table" then text = text[GetLocale()] or text.enUS end
        if text then lbl:SetText(text) end
      end
    end
    grids[sec] = grid
    sec._le = { id = sec._leId, layout = layout, colW = colW, pool = pool, custom = sec._leCustom }
  end

  -- Nouveau flux : grille a la place de la 1re rangee deplacable de la section (sinon juste sous son en-tete) ;
  -- rangees deplacables des sections recomposees retirees, ainsi que les espacements entre elles
  -- Section videe par la disposition (ses widgets places ailleurs, rien d'autre dedans) : masquee hors mode disposition
  local emptied = {}
  if not LE.editing then
    for sec, grid in pairs(grids) do
      if #grid == 0 then
        local other = false
        for _, item in ipairs(ctx.flow) do
          if item.section == sec and not item._leMovable and item.kind ~= "spacer"
              and not (item.kind == "widget" and item.w == sec.header) then other = true end
        end
        if not other then emptied[sec] = true; sec.header:Hide() end
      end
    end
    if next(emptied) then
      local kept = {}
      for _, sec in ipairs(ctx.sections) do if not emptied[sec] then kept[#kept + 1] = sec end end
      ctx.sections = kept
    end
  end

  local flow = {}
  for idx, item in ipairs(ctx.flow) do
    local sec = item.section
    local info = sec and sec._leInfo
    local recomposed = sec and grids[sec]
    if sec and emptied[sec] then
      -- section masquee : en-tete et espacements retires
    elseif recomposed and item._leMovable then
      if idx == info.first then for _, g in ipairs(recomposed) do flow[#flow + 1] = g end end
    elseif recomposed and item.kind == "spacer" and info.first and idx > info.first and idx < info.last then
      -- espacement entre rangees deplacables : retire
    else
      flow[#flow + 1] = item
      if recomposed and not info.first and item.kind == "widget" and item.w == sec.header then
        for _, g in ipairs(recomposed) do flow[#flow + 1] = g end
      end
    end
  end
  ctx.flow = flow
end

-- ═══ Mode disposition ═══════════════════════════════════════════════════════════════════════════════
local banner

local function Refresh()
  if ns.RefreshActiveSettingsPage then ns.RefreshActiveSettingsPage() end
end

local function Popup(name, w, h)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(0.05, 0.05, 0.06, 0.97)
  f:SetBackdropBorderColor(unpack(Theme.gold or Theme.border))
  f:EnableMouse(true)
  return f
end

local function CopyPopup(text)
  local f = LE._copy
  if not f then
    f = Popup("AishCoreLayoutExport", 560, 340)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -10)
    sf:SetPoint("BOTTOMRIGHT", -30, 40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(ns.Media.fontGui, 11, "")
    eb:SetWidth(510)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.eb = eb
    local close = SW.CreateActionBtn(f, CLOSE or "Close", 100)
    close:SetPoint("BOTTOMRIGHT", -10, 10)
    close:SetScript("OnClick", function() f:Hide() end)
    LE._copy = f
  end
  f.eb:SetText(text)
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

-- Saisie du nouveau libelle d'un widget / titre (Entree valide, Echap annule, texte vide = libelle d'origine)
function LE.RenamePopup(current, onDone)
  local f = LE._rename
  if not f then
    f = Popup("AishCoreLayoutRename", 380, 92)
    local t = f:CreateFontString(nil, "OVERLAY")
    t:SetFont(ns.Media.fontGui, 11, "")
    t:SetPoint("TOPLEFT", 10, -10)
    t:SetText(L["LAYOUT_RENAME"])
    local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    eb:SetSize(360, 22)
    eb:SetPoint("TOPLEFT", 10, -28)
    eb:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    eb:SetBackdropColor(0, 0, 0, 0.6)
    eb:SetBackdropBorderColor(unpack(Theme.border))
    eb:SetFont(ns.Media.fontGui, 12, "")
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetAutoFocus(false)
    local ok = SW.CreateActionBtn(f, OKAY or "OK", 90)
    ok:SetPoint("BOTTOMRIGHT", -10, 8)
    local cancel = SW.CreateActionBtn(f, CANCEL or "Cancel", 90)
    cancel:SetPoint("RIGHT", ok, "LEFT", -6, 0)
    local function Done()
      f:Hide()
      if f._cb then f._cb(eb:GetText() or "") end
    end
    ok:SetScript("OnClick", Done)
    eb:SetScript("OnEnterPressed", Done)
    cancel:SetScript("OnClick", function() f:Hide() end)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.eb = eb
    LE._rename = f
  end
  f._cb = onDone
  f.eb:SetText(current or "")
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

-- Texte d'export : sections ajoutees, dispositions (cases vides = "-"), libelles et titres renommes, sidebar
local function ExportText()
  local lines = {}
  local catIds = {}
  for catId in pairs(Store()) do catIds[#catIds + 1] = catId end
  table.sort(catIds)
  for _, catId in ipairs(catIds) do
    local page = Store()[catId]
    for _, def in ipairs(page.__sections or {}) do
      lines[#lines + 1] = string.format("[%s] section: %s after %s", catId, def.id, tostring(def.after))
    end
    local secs = {}
    for name in pairs(page) do if name ~= "__sections" then secs[#secs + 1] = name end end
    table.sort(secs)
    for _, name in ipairs(secs) do
      local lay = page[name]
      lines[#lines + 1] = string.format("[%s] %s  (%d col.)", catId, name, lay.cols or DEFAULT_COLS)
      for r, row in ipairs(lay.rows or {}) do
        local cells, maxC = {}, lay.cols or DEFAULT_COLS
        for c in pairs(row) do if c > maxC then maxC = c end end
        for c = 1, maxC do cells[c] = row[c] or "-" end
        lines[#lines + 1] = string.format("  %d: %s", r, table.concat(cells, " | "))
      end
      local ids = {}
      for id in pairs(lay.labels or {}) do ids[#ids + 1] = id end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local t = lay.labels[id]
        if type(t) == "table" then t = t[GetLocale()] or t.enUS end
        lines[#lines + 1] = string.format("  label: %s => %s", id, tostring(t))
      end
    end
  end
  local tAll = AishaddonDB and AishaddonDB._guiTitles or {}
  local tCats = {}
  for catId in pairs(tAll) do tCats[#tCats + 1] = catId end
  table.sort(tCats)
  for _, catId in ipairs(tCats) do
    local keys = {}
    for k in pairs(tAll[catId]) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do lines[#lines + 1] = string.format("[%s] title: %s => %s", catId, k, tAll[catId][k]) end
  end
  local sb = AishaddonDB and AishaddonDB._guiSidebar
  if sb then
    for gi, ids in ipairs(sb) do
      local grp = ns._sidebarGroups and ns._sidebarGroups[gi]
      lines[#lines + 1] = string.format("[sidebar] %d %s: %s", gi, grp and grp.label or "?", table.concat(ids, ", "))
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or L["LAYOUT_EXPORT_EMPTY"]
end

local function EnsureBanner()
  if banner then return banner end
  local panel = _G.AishCoreSettingsPanel
  if not panel then return nil end
  banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  banner:SetHeight(30)
  banner:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 4)
  banner:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 4)
  banner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  banner:SetBackdropColor(0.35, 0.22, 0.05, 0.95)
  banner:SetBackdropBorderColor(unpack(Theme.gold or Theme.border))
  local t = banner:CreateFontString(nil, "OVERLAY")
  t:SetFont(ns.Media.fontGui, 12, "")
  t:SetPoint("LEFT", 10, 0)
  t:SetText(L["LAYOUT_EDIT_BANNER"])
  local quit = SW.CreateActionBtn(banner, L["LAYOUT_QUIT"], 80)
  quit:SetPoint("RIGHT", -4, 0)
  quit:SetScript("OnClick", function() LE.Toggle(false) end)
  local exp = SW.CreateActionBtn(banner, L["LAYOUT_EXPORT"], 80)
  exp:SetPoint("RIGHT", quit, "LEFT", -6, 0)
  exp:SetScript("OnClick", function() CopyPopup(ExportText()) end)
  local reset = SW.CreateActionBtn(banner, L["LAYOUT_RESET_PAGE"], 140)
  reset:SetPoint("RIGHT", exp, "LEFT", -6, 0)
  reset:SetScript("OnClick", function()
    local catId = LE._page
    if catId then
      Store()[catId] = nil
      if AishaddonDB._guiTitles then AishaddonDB._guiTitles[catId] = nil end
      Refresh()
    end
  end)
  local resetSb = SW.CreateActionBtn(banner, L["LAYOUT_RESET_SIDEBAR"], 140)
  resetSb:SetPoint("RIGHT", reset, "LEFT", -6, 0)
  resetSb:SetScript("OnClick", function()
    AishaddonDB._guiSidebar = nil
    print("|cff00ccff[AishCore]|r " .. L["LAYOUT_SIDEBAR_RESET_DONE"])
  end)
  return banner
end

function LE.Toggle(on)
  if on == nil then on = not LE.editing end
  LE.editing = on and true or false
  local b = EnsureBanner()
  if b then b:SetShown(LE.editing) end
  if ns.InvalidateAllSettingsPages then ns.InvalidateAllSettingsPages() else Refresh() end
  print("|cff00ccff[AishCore]|r " .. (LE.editing and L["LAYOUT_ON"] or L["LAYOUT_OFF"]))
end

SLASH_AISHLAYOUT1 = "/aishlayout"
SlashCmdList["AISHLAYOUT"] = function() LE.Toggle() end

-- Petit bouton texte de l'en-tete de section
local function HeadBtn(parent, text, tip, w)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 20, 18)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(0.1, 0.1, 0.12, 1)
  b:SetBackdropBorderColor(unpack(Theme.gold or Theme.border))
  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Media.fontGui, 12, "")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  if tip then
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tip, 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return b
end

-- Appele a la fin de ctx:Finalize : en mode disposition, titres renommables ; sur une page du moteur, sections
-- depliees, page inerte, widgets deplacables d'une case / section a l'autre
function LE.After(ctx, container, catId)
  if not (LE.editing and ctx._isPage and catId) then return end
  LE._page = catId
  local saved = Store()[catId]
  local code = ns.GUI_LAYOUT and ns.GUI_LAYOUT[catId]
  local customList = (saved and saved.__sections) or (code and code.__sections) or {}

  local function SaveSections(list)
    Store()[catId] = Store()[catId] or {}
    Store()[catId].__sections = (#list > 0) and list or nil
    if not next(Store()[catId]) then Store()[catId] = nil end
  end

  -- Titre de la page et titres de section : clic droit = renommer (texte vide = titre d'origine)
  local function HeaderOverlay(hdr, parent, level)
    local ov = CreateFrame("Button", nil, parent)
    ov:SetAllPoints(hdr)
    ov:SetFrameLevel(level)
    ov:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = ov:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:Hide()
    ov:SetScript("OnEnter", function(self)
      hl:Show()
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["LAYOUT_TITLE_TT"], 1, 1, 1)
      GameTooltip:Show()
    end)
    ov:SetScript("OnLeave", function() hl:Hide(); GameTooltip:Hide() end)
    ov:SetScript("OnClick", function(_, btn)
      -- Clic gauche : transmis a l'en-tete (plier / deplier, tout plier sur le titre)
      if btn == "LeftButton" then
        if hdr._hitbox then hdr._hitbox:Click() end
        return
      end
      local key = HeaderKey(ctx, hdr)
      LE.RenamePopup(hdr._displayText or hdr._baseText or "", function(text)
        local orig = (hdr._leKey and L["LAYOUT_NEW_SECTION"] or hdr._baseText or ""):upper()
        SaveTitle(catId, key, (text ~= "" and text:upper() ~= orig) and text or nil)
        Refresh()
      end)
    end)
  end
  if ctx._title then HeaderOverlay(ctx._title, ctx._title, ctx._title:GetFrameLevel() + 20) end
  for _, sec in ipairs(ctx.sections) do HeaderOverlay(sec.header, container, container:GetFrameLevel() + 38) end
  if not ctx._le then return end

  for _, sec in ipairs(ctx.sections) do
    sec.collapsed = false
    SW.SetHeaderCollapsedState(sec.header, false)
  end
  ctx:Relayout(false)
  local gap, cw = ctx._le.gap, ctx._le.cw
  local base = container:GetFrameLevel()

  -- Calque inerte sur toute la page
  local block = CreateFrame("Frame", nil, container)
  block:SetAllPoints()
  block:SetFrameLevel(base + 30)
  block:EnableMouse(true)
  local tint = block:CreateTexture(nil, "BACKGROUND")
  tint:SetAllPoints()
  tint:SetColorTexture(0.35, 0.22, 0.05, 0.06)
  local indicator = block:CreateTexture(nil, "OVERLAY")
  local g = Theme.gold or Theme.accentText
  indicator:SetColorTexture(g[1], g[2], g[3], 0.35)
  indicator:Hide()

  local function Cursor()
    local x, y = GetCursorPosition()
    local s = container:GetEffectiveScale()
    return x / s - container:GetLeft(), container:GetTop() - y / s
  end

  -- Geometrie des sections recomposees : zone verticale (de son en-tete au suivant), rangees de sa grille. Relue a chaque
  -- prise d'un widget (RefreshZones) : un element de la page peut changer de hauteur apres coup (liste remplie un peu
  -- apres l'ouverture...) et decaler les sections suivantes.
  local zones = {}
  for _, sec in ipairs(ctx.sections) do
    local le = sec._le
    if le then zones[#zones + 1] = { sec = sec, le = le, n = le.layout.cols, colW = le.colW, rows = {} } end
  end
  local function RefreshZones()
    local tyOf = {}
    for _, item in ipairs(ctx.flow) do
      if item.kind == "widget" then tyOf[item.w] = item._ty end
    end
    for _, z in ipairs(zones) do
      local sec = z.sec
      wipe(z.rows)
      for _, item in ipairs(ctx.flow) do
        if item.section == sec and item._leRow then z.rows[#z.rows + 1] = { r = item._leRow, ty = item._ty, h = item.rowH } end
      end
      z.top = tyOf[sec.header] or 0
      z.body = z.top + (sec.header:GetHeight() or 20) + 2
      z.bottom = math.huge
      for i, s2 in ipairs(ctx.sections) do
        if s2 == sec and ctx.sections[i + 1] then z.bottom = tyOf[ctx.sections[i + 1].header] or math.huge end
      end
    end
  end
  RefreshZones()

  -- Case visee : section sous le curseur, puis rangee / colonne ; quart haut / bas d'une case occupee = nouvelle
  -- rangee au-dessus / en dessous ; sous la derniere rangee (ou section vide) = nouvelle rangee en fin
  local function Target(cx, cy)
    for _, z in ipairs(zones) do
      if cy >= z.top and cy < z.bottom then
        local layout, n = z.le.layout, z.n
        local unit = z.colW + gap
        local col = math.max(1, math.min(n, math.floor(cx / unit) + 1))
        local t = { zone = z, col = col }
        if #z.rows == 0 then
          t.newRow, t.y, t.h = true, z.body, EMPTY_H
          return t
        end
        local last = z.rows[#z.rows]
        local bottom = last.ty + last.h
        if cy >= bottom + ROW_GAP then
          t.newRow, t.y, t.h = true, bottom + ROW_GAP, last.h
          return t
        end
        local rw = z.rows[1]
        for _, r in ipairs(z.rows) do if cy >= r.ty - ROW_GAP then rw = r end end
        local occupied = layout.rows[rw.r][col] ~= nil
        local rel = (cy - rw.ty) / math.max(1, rw.h)
        t.row = rw.r
        if occupied and rel < 0.25 then
          t.insert, t.y, t.h = rw.r, rw.ty - 2, 3
        elseif occupied and rel > 0.75 then
          t.insert, t.y, t.h = rw.r + 1, rw.ty + rw.h, 3
        else
          t.y, t.h = rw.ty, rw.h
        end
        return t
      end
    end
    return nil
  end

  -- Enregistre une ou deux sections (deplacement entre sections) puis reconstruit
  local function SaveZone(z, rows, cols, labels)
    Save(catId, z.le.id, { cols = cols or z.n, rows = Compact(rows), labels = labels })
  end

  for _, z in ipairs(zones) do
    local le, layout, n = z.le, z.le.layout, z.n
    local function Commit(newRows, newCols, newLabels)
      SaveZone(z, newRows, newCols, newLabels or layout.labels)
      Refresh()
    end

    -- En-tete : nouvelle section / separateur / - N colonnes + / reinitialiser / supprimer (section ajoutee)
    local hdr = z.sec.header
    local ctl = CreateFrame("Frame", nil, container)
    ctl:SetSize(220, 18)
    ctl:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    ctl:SetFrameLevel(base + 40)
    local isCustom = hdr._leKey ~= nil
    local last
    if isCustom then
      local del = HeadBtn(ctl, "X", L["LAYOUT_DELETE_SECTION"])
      del:SetPoint("RIGHT")
      del:SetScript("OnClick", function()
        local list = {}
        for _, def in ipairs(customList) do if def.id ~= hdr._leKey then list[#list + 1] = def end end
        SaveSections(list)
        Save(catId, hdr._leKey, nil)
        SaveTitle(catId, hdr._leKey, nil)
        Refresh()
      end)
      last = del
    end
    local reset = HeadBtn(ctl, "R", L["LAYOUT_RESET_SECTION"])
    if last then reset:SetPoint("RIGHT", last, "LEFT", -6, 0) else reset:SetPoint("RIGHT") end
    local plus = HeadBtn(ctl, "+")
    plus:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    local lbl = ctl:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 11, "")
    lbl:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    lbl:SetText(string.format(L["LAYOUT_COLS"], n))
    local minus = HeadBtn(ctl, "-")
    minus:SetPoint("RIGHT", lbl, "LEFT", -4, 0)
    local div = HeadBtn(ctl, "—", L["LAYOUT_ADD_DIVIDER"])
    div:SetPoint("RIGHT", minus, "LEFT", -10, 0)
    local addSec = HeadBtn(ctl, "S+", L["LAYOUT_ADD_SECTION"], 26)
    addSec:SetPoint("RIGHT", div, "LEFT", -6, 0)
    plus:SetScript("OnClick", function() if n < MAX_COLS then Commit(CopyRows(layout.rows), n + 1) end end)
    minus:SetScript("OnClick", function()
      if n <= MIN_COLS then return end
      local m = n - 1
      local out = {}
      for _, row in ipairs(layout.rows) do
        local nr, extra = {}, {}
        for c, id in pairs(row) do if c <= m then nr[c] = id else extra[#extra + 1] = id end end
        for _, id in ipairs(extra) do
          local placed = false
          for c = 1, m do if not nr[c] then nr[c] = id; placed = true; break end end
          if not placed then out[#out + 1] = nr; nr = { [1] = id } end
        end
        out[#out + 1] = nr
      end
      Commit(out, m)
    end)
    div:SetScript("OnClick", function()
      local k = 1
      for _, zz in ipairs(zones) do
        for _, row in ipairs(zz.le.layout.rows) do
          for _, id in pairs(row) do
            local num = IsDivId(id) and tonumber(id:sub(#DIV_PREFIX + 1))
            if num and num >= k then k = num + 1 end
          end
        end
      end
      local nr = CopyRows(layout.rows)
      nr[#nr + 1] = { [1] = DIV_PREFIX .. k }
      Commit(nr)
    end)
    addSec:SetScript("OnClick", function()
      local k = 1
      for _, def in ipairs(customList) do
        local num = tonumber(def.id:sub(#SEC_PREFIX + 1))
        if num and num >= k then k = num + 1 end
      end
      local list = {}
      for _, def in ipairs(customList) do list[#list + 1] = { id = def.id, after = def.after } end
      list[#list + 1] = { id = SEC_PREFIX .. k, after = le.id }
      SaveSections(list)
      Refresh()
    end)
    reset:SetScript("OnClick", function() Save(catId, le.id, nil); Refresh() end)

    -- Calques des widgets
    for r, row in ipairs(layout.rows) do
      for c, id in pairs(row) do
        local w = le.pool.byId[id]
        if w and w:IsShown() then
          local isDiv = Kind(w) == "divider"
          local ov = CreateFrame("Button", nil, container)
          ov:SetAllPoints(w)
          ov:SetFrameLevel(base + 35)
          ov:RegisterForClicks("RightButtonUp")
          local hl = ov:CreateTexture(nil, "OVERLAY")
          hl:SetAllPoints()
          hl:SetColorTexture(1, 1, 1, isDiv and 0.15 or 0.08)
          hl:SetShown(isDiv)
          ov:SetScript("OnEnter", function(self)
            hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(isDiv and L["LAYOUT_DIVIDER_TT"] or L["LAYOUT_WIDGET_TT"], 1, 1, 1)
            GameTooltip:Show()
          end)
          ov:SetScript("OnLeave", function() hl:SetShown(isDiv); GameTooltip:Hide() end)
          -- Clic droit : separateur retire ; autre widget renomme (texte vide = libelle d'origine)
          ov:SetScript("OnClick", function()
            if isDiv then
              local nr = CopyRows(layout.rows)
              nr[r][c] = nil
              Commit(nr)
              return
            end
            local lb = LabelOf(w)
            if not (lb and lb.GetText) then return end
            LE.RenamePopup(lb:GetText() or "", function(text)
              local labels = {}
              for k, v in pairs(layout.labels or {}) do labels[k] = v end
              local orig = w._leOrigLabel or lb:GetText()
              labels[id] = (text ~= "" and text ~= orig) and text or nil
              Commit(CopyRows(layout.rows), nil, next(labels) and labels or nil)
            end)
          end)
          ov:SetScript("OnMouseDown", function(_, btn)
            if btn ~= "LeftButton" then return end
            RefreshZones()
            local cx, cy = Cursor()
            local gx = cx - (w:GetLeft() - container:GetLeft())
            local gy = cy - (container:GetTop() - w:GetTop())
            w:SetAlpha(0.7)
            block:SetScript("OnUpdate", function()
              local x, y = Cursor()
              w:ClearAllPoints()
              w:SetPoint("TOPLEFT", container, "TOPLEFT", x - gx, -(y - gy))
              local t = Target(x, y)
              if t then
                indicator:ClearAllPoints()
                indicator:SetPoint("TOPLEFT", container, "TOPLEFT", (t.col - 1) * (t.zone.colW + gap), -t.y)
                indicator:SetSize(t.zone.colW, t.h)
                indicator:Show()
              else
                indicator:Hide()
              end
            end)
            ov._drag = true
          end)
          ov:SetScript("OnMouseUp", function(_, btn)
            if btn ~= "LeftButton" or not ov._drag then return end
            ov._drag = nil
            block:SetScript("OnUpdate", nil)
            indicator:Hide()
            local t = Target(Cursor())
            if not t then Refresh(); return end
            local tz = t.zone
            local same = (tz == z)
            local src = CopyRows(layout.rows)
            local dst = same and src or CopyRows(tz.le.layout.rows)
            src[r][c] = nil
            if t.newRow then
              dst[#dst + 1] = { [t.col] = id }
            elseif t.insert then
              table.insert(dst, t.insert, { [t.col] = id })
            else
              local other = dst[t.row][t.col]
              dst[t.row][t.col] = id
              if other and other ~= id then src[r][c] = other end
            end
            if same then
              SaveZone(z, src, nil, layout.labels)
            else
              -- Le libelle renomme suit le widget dans sa nouvelle section
              local sl, dl = {}, {}
              for k, v in pairs(layout.labels or {}) do sl[k] = v end
              for k, v in pairs(tz.le.layout.labels or {}) do dl[k] = v end
              dl[id], sl[id] = sl[id], nil
              SaveZone(z, src, nil, next(sl) and sl or nil)
              SaveZone(tz, dst, nil, next(dl) and dl or nil)
            end
            Refresh()
          end)
        end
      end
    end
  end
end

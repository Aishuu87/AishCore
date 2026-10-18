-- Modules/LevelUpToast.lua : toast de montee de niveau ("Niveau X !", gains de stats, nouvelles competences).
-- Memes polices, couleurs, icones et repartition des stats que l'apercu du prochain niveau (Modules/XPBar.lua). Fond tire
-- au hasard parmi frame_jailer1 a 3, ancre par un point a 105 px de son bord haut : son ajustement en hauteur au contenu
-- et son zoom d'entree se font autour de ce point.
-- Reglages dans ns.DB.xpBar (toast*), section "Toast de niveau" de la page Barre d'XP (apercu sur fond beige).
local addonName, ns = ...
local L = ns.L

local LUT = {}
ns.Modules = ns.Modules or {}
ns.Modules.LevelUpToast = LUT

local MEDIA_XP   = "Interface\\AddOns\\AishCore\\Media\\XPBar\\"
local MEDIA_UI   = "Interface\\AddOns\\AishCore\\Media\\UI\\"
local SM         = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\"
local FONT_TITLE = SM .. "Montserrat-BoldItalic.ttf"
local FONT_BOLD  = SM .. "Montserrat-Bold.ttf"
local FALLBACK   = ns.FONT_FALLBACK or "Fonts\\2002.TTF"
local WHITE      = "Interface\\Buttons\\WHITE8x8"
local BGS        = { "frame_jailer1.png", "frame_jailer2.png", "frame_jailer3.png" }

-- Repere de conception : fond de 611 x 428 ; positions depuis le bord HAUT du toast (y negatif), x depuis son centre.
-- BG_PIVOT : point d'ancrage du fond, a 105 px de son bord haut. DARK_BOTTOM : bas de sa partie sombre (depuis son haut),
-- que l'ajustement en hauteur amene juste sous le contenu.
local BG_W, BG_H, BG_PIVOT, DARK_BOTTOM = 611, 428, 105, 330
local Y_TITLE, RULE_GAP = -110, 46               -- filets dores a RULE_GAP l'un de l'autre, centres sur le titre
local STATS_BELOW_RULE, STAT_ROW = 35, 37         -- 1re rangee de stats : sous le filet du bas
local HDR_GAP, SPELL_GAP, SPELL_ROW = 32, 43, 44   -- derniere rangee de stats -> en-tete -> 1re rangee de sorts
local STAT_ICON = 30
local STAT_COL_W = 84                              -- largeur d'une colonne de stats (4 colonnes au plus)
local SPELL_ICON, SPELL_TW = 33, 150
local SPELL_COL_L = { -177, 28 }                   -- bord gauche des deux colonnes de sorts (15 d'ecart)
local SPELL_PER_COL, MAX_SPELLS = 3, 6
-- Fond du titre, embarque en PNG (taille a l'echelle de "Taille du niveau") ; TITLE_BG = nil : deux filets dores autour
-- du titre a la place. dy = decalage du centre de la texture par rapport a celui du titre.
--   "gearUpdate-glow-filigree" : halo et filet a losange, le filet tombe juste sous le texte
--   "shop-header-menu-bg" (level_title_bg.png, 330 x 51, dy -2) : halo brun-dore a filet lumineux
local TITLE_BG = MEDIA_UI .. "level_title_filigree.png"
local TITLE_BG_W, TITLE_BG_H, TITLE_BG_DY = 263, 97, 10
local RULE_W = 240                                 -- filets dores autour du titre (1 pixel ecran de haut)

local TEAL      = { 0.00, 0.89, 0.64 }
local OCRE      = { 1, 189 / 255, 116 / 255 }
local DIM       = { 0.66, 0.60, 0.50 }
local BROWN     = { 0.42, 0.30, 0.17 }   -- en-tetes de l'apercu du prochain niveau (NL.BROWN)
local GREY_RANK = { 0.60, 0.60, 0.60 }
local GOLD_LINE = { 0.86, 0.68, 0.22 }
local ICONS = {
  hp = "hp_icon.tga", power = "res_icon.tga", str = "str_icon.tga", agi = "agi_icon.tga",
  sta = "stam_icon.tga", int = "int_icon.tga", spi = "spi_icon.tga",
}

-- Animations (memes courbes que l'apercu du prochain niveau : cubique sortante, decalages etires)
local ANIM_DUR, STAGGER, SLIDE_R, SLIDE_U = 0.65, 1.9, 22, 14
local BG_DUR, OUT_DUR, OUT_RISE = 0.9, 0.7, 10

LUT.DEFAULTS = {
  toastEnabled = true, toastWaitCombat = true, toastDuration = 6, toastScale = 1, toastTitleScale = 1,
  toastFontScale = 1, toastBgScale = 1, toastBgAlpha = 0.85, toastTitleColor = { 1, 0.82, 0.10, 1 },
  toastX = 0, toastY = 220,
}
local function V(k)
  local c = ns.GetCfg and ns.GetCfg("xpBar")
  local v = c and c[k]
  if v == nil then v = LUT.DEFAULTS[k] end
  return v
end

local function EaseOut(v) return 1 - (1 - v) * (1 - v) * (1 - v) end
local function EaseInOut(v) return v < 0.5 and 4 * v * v * v or 1 - ((-2 * v + 2) ^ 3) / 2 end

-- ═══ Construction ════════════════════════════════════════════════════════════════════════════════
-- group : "title" (taille du niveau) ou "body" (stats et competences), chacun avec son reglage de taille
local fontSeq = 0
local function Text(o, parent, font, size, color, justify, group)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fontSeq = fontSeq + 1
  fs._font, fs._size, fs._key, fs._group = font, size, "LevelToast" .. fontSeq, group or "body"
  fs:SetFont(FALLBACK, size, "")
  fs:SetTextColor(color[1], color[2], color[3], 1)
  fs:SetJustifyH(justify or "CENTER")
  fs:SetShadowColor(0, 0, 0, 0.7)
  fs:SetShadowOffset(1, -1)
  o.texts[#o.texts + 1] = fs
  return fs
end

-- Filet horizontal en degrade (transparent -> couleur) : `fadeLeft` = transparent a gauche
local function Line(parent, w, h, color, alpha, fadeLeft)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(WHITE)
  t:SetSize(w, h)
  local a, b = CreateColor(color[1], color[2], color[3], 0), CreateColor(color[1], color[2], color[3], alpha)
  if fadeLeft then t:SetGradient("HORIZONTAL", a, b) else t:SetGradient("HORIZONTAL", b, a) end
  return t
end

-- Ville(s) du maitre d'armes sous une competence d'arme : boite a la largeur de la colonne ; un texte plus long
-- defile lentement d'un bout a l'autre (pause aux extremites) au lieu de deborder sur la colonne voisine
local CITY_SPEED, CITY_PAUSE = 14, 1.5   -- px/s, s

local function CityScroll(clip, el)
  local fs = clip.text
  local over = fs:GetStringWidth() - clip:GetWidth()
  if over <= 0 then return end
  clip.t = clip.t + el
  local run = over / CITY_SPEED
  local cycle = 2 * (CITY_PAUSE + run)
  local t = clip.t % cycle
  local x
  if t < CITY_PAUSE then x = 0
  elseif t < CITY_PAUSE + run then x = (t - CITY_PAUSE) * CITY_SPEED
  elseif t < 2 * CITY_PAUSE + run then x = over
  else x = over - (t - 2 * CITY_PAUSE - run) * CITY_SPEED end
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", clip, "LEFT", -x, 0)
end

local function Cell(o)
  local c = CreateFrame("Frame", nil, o.root)
  c:SetFrameLevel(o.root:GetFrameLevel() + 2)
  c:Hide()
  return c
end

function LUT.Build(parent, isPreview)
  local o = { texts = {}, items = {}, preview = isPreview }
  local root = CreateFrame("Frame", nil, parent)
  root:SetSize(BG_W, BG_H)
  root:Hide()
  o.root = root
  o.bg = root:CreateTexture(nil, "BACKGROUND")

  -- Titre entre deux filets dores (deux moities en degrade vers les bords)
  o.rules = {}
  local function GoldRule()
    local c = Cell(o)
    c:SetSize(RULE_W, 4)
    local l = Line(c, RULE_W / 2, 1, GOLD_LINE, 0.9, true)
    l:SetPoint("RIGHT", c, "CENTER", 0, 0)
    local r = Line(c, RULE_W / 2, 1, GOLD_LINE, 0.9, false)
    r:SetPoint("LEFT", c, "CENTER", 0, 0)
    o.rules[#o.rules + 1], o.rules[#o.rules + 2] = l, r
    c.halves = { l, r }
    return c
  end
  o.lineTop, o.lineBot = GoldRule(), GoldRule()
  o.titleBg = Cell(o)
  o.titleBg:SetFrameLevel(o.root:GetFrameLevel() + 1)   -- sous le texte du niveau
  o.titleBgTex = o.titleBg:CreateTexture(nil, "ARTWORK")
  o.titleBgTex:SetAllPoints(o.titleBg)
  if TITLE_BG then o.titleBgTex:SetTexture(TITLE_BG) end
  o.title = Cell(o)
  o.titleText = Text(o, o.title, FONT_TITLE, 40, { 1, 1, 1 }, "CENTER", "title")
  o.titleText:SetPoint("CENTER", o.title, "CENTER", 0, 0)

  -- Stats : "+N" Montserrat Bold turquoise, icone ocre a droite
  o.stats = {}
  for i = 1, 7 do
    local c = Cell(o)
    c:SetHeight(STAT_ICON)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(STAT_ICON, STAT_ICON)
    c.icon:SetVertexColor(OCRE[1], OCRE[2], OCRE[3], 1)
    c.icon:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    c.value = Text(o, c, FONT_BOLD, 22, TEAL, "RIGHT")
    c.value:SetPoint("RIGHT", c.icon, "LEFT", 2, 0)
    o.stats[i] = c
  end

  -- "nouvelles competences" entre deux filets discrets
  o.hdr = Cell(o)
  o.hdr:SetSize(300, 20)
  o.hdrText = Text(o, o.hdr, FALLBACK, 15, BROWN, "CENTER")
  o.hdrText:SetPoint("CENTER", o.hdr, "CENTER", 0, 0)
  o.hdrL = Line(o.hdr, 80, 1, DIM, 0.55, true)
  o.hdrL:SetPoint("RIGHT", o.hdrText, "LEFT", -10, 0)
  o.hdrR = Line(o.hdr, 80, 1, DIM, 0.55, false)
  o.hdrR:SetPoint("LEFT", o.hdrText, "RIGHT", 10, 0)

  -- Sorts : icone, "+" turquoise au coin, nom et "(Rang X)" dessous (comme l'apercu du prochain niveau)
  o.spells = {}
  for i = 1, MAX_SPELLS do
    local c = Cell(o)
    c:SetSize(SPELL_ICON + 6 + SPELL_TW, SPELL_ICON)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(SPELL_ICON, SPELL_ICON)
    c.icon:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- badge "+" (sort nouveau) ou chevron (nouveau rang), pose par LUT.Layout
    c.plus = c:CreateTexture(nil, "OVERLAY")
    c.plus:SetSize(20, 20)
    c.plus:SetPoint("CENTER", c.icon, "TOPRIGHT", -4, -1)
    c.name = Text(o, c, FALLBACK, 12, TEAL, "LEFT")
    c.name:SetWidth(SPELL_TW)
    c.name:SetWordWrap(true)
    c.name:SetMaxLines(2)
    c.rank = Text(o, c, FALLBACK, 10, GREY_RANK, "LEFT")
    c.rank:SetWidth(SPELL_TW)
    c.city = CreateFrame("Frame", nil, c)
    c.city:SetSize(SPELL_TW, 12)
    c.city:SetClipsChildren(true)
    c.city.text = Text(o, c.city, FALLBACK, 10, GREY_RANK, "LEFT")
    c.city.text:SetWordWrap(false)
    c.city.t = 0
    c.city:Hide()
    o.spells[i] = c
  end
  LUT.ApplyFonts(o)
  return o
end

-- Polices a la taille reglee (Montserrat via ns.ApplyFontReliable : repli 2002 si absente)
function LUT.ApplyFonts(o)
  local kTitle, kBody = V("toastTitleScale") or 1, V("toastFontScale") or 1
  for _, fs in ipairs(o.texts) do
    local k = (fs._group == "title") and kTitle or kBody
    local size = math.max(6, math.floor(fs._size * k + 0.5))
    if fs._font == FALLBACK or not ns.ApplyFontReliable then
      pcall(fs.SetFont, fs, fs._font, size, "")
    else
      ns.ApplyFontReliable(fs, fs._key, fs._font, size, "")
    end
  end
end

-- ═══ Mise en page ════════════════════════════════════════════════════════════════════════════════
local function SpellRank(id)
  if not id then return nil end
  local ok, sub = pcall(function()
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
    if GetSpellSubtext then return GetSpellSubtext(id) end
  end)
  if ok and type(sub) == "string" and sub ~= "" then return sub end
  return nil
end

local function ShortNum(n)
  local XB = ns.Modules and ns.Modules.XPBar
  if XB and XB.ShortNum then return XB.ShortNum(n) end
  return tostring(math.floor(n or 0))
end

-- Place une cellule : centre a (x, y) depuis le bord haut du toast ; dir = "up" (arrive du bas) ou "right"
local function Add(o, cell, x, y, dir, delay)
  cell.bx, cell.by, cell.dir = x, y, dir
  cell:ClearAllPoints()
  cell:SetPoint("CENTER", o.root, "TOP", x, y)
  cell:SetAlpha(0)
  cell:Show()
  o.items[#o.items + 1] = { cell = cell, delay = delay * STAGGER }
end

-- Fond a l'echelle `sc` (zoom d'entree) autour de son point d'ancrage, a BG_PIVOT px de son bord haut
local function PlaceBg(o, sc)
  local fy = o.bgFitY
  local s = o.bgScale * sc
  o.bg:SetSize(BG_W * s, BG_H * s * fy)
  o.bg:ClearAllPoints()
  o.bg:SetPoint("TOP", o.root, "TOP", 0, -BG_PIVOT + BG_PIVOT * s * fy)
end

-- Stats dans l'ordre de l'apercu du prochain niveau (PV, ressource, puis caracteristiques)
local function StatList(stats)
  local list = {}
  if not stats then return list end
  for _, k in ipairs({ "hp", "power", "str", "agi", "sta", "int", "spi" }) do
    if stats[k] then list[#list + 1] = { k = k, v = stats[k] } end
  end
  return list
end

function LUT.Layout(o, data)
  wipe(o.items)
  for _, c in ipairs({ o.lineTop, o.lineBot, o.titleBg, o.title, o.hdr }) do c:Hide() end
  for _, c in ipairs(o.stats) do c:Hide() end
  for _, c in ipairs(o.spells) do c:Hide() end
  LUT.ApplyFonts(o)

  -- Fond : tire au hasard, opacite reglee
  o.bg:SetTexture(MEDIA_UI .. BGS[data.bgIndex or 1])
  o.bgAlpha = V("toastBgAlpha")

  local delay = 0
  -- Titre "Niveau X !" et ses filets
  local tc = V("toastTitleColor")
  o.titleText:SetTextColor(tc[1], tc[2], tc[3], 1)
  o.titleText:SetText(string.format(L["XP_TOAST_TITLE"], data.level or 0))
  o.title:SetSize(o.titleText:GetStringWidth() + 20, o.titleText:GetStringHeight() + 10)
  local px = ((PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()) or 1)
    / math.max(0.01, o.root:GetEffectiveScale())
  for _, t in ipairs(o.rules) do t:SetHeight(px) end
  -- Ecart et longueur des filets a l'echelle de "Taille du niveau" (l'epaisseur reste d'un pixel)
  local kT = V("toastTitleScale") or 1
  for _, c in ipairs({ o.lineTop, o.lineBot }) do
    c:SetWidth(RULE_W * kT)
    for _, h in ipairs(c.halves) do h:SetWidth(RULE_W * kT / 2) end
  end
  local yLineTop, yLineBot = Y_TITLE + RULE_GAP * kT / 2, Y_TITLE - RULE_GAP * kT / 2
  if TITLE_BG then
    o.titleBg:SetSize(TITLE_BG_W * kT, TITLE_BG_H * kT)
    Add(o, o.titleBg, 0, Y_TITLE + TITLE_BG_DY * kT, "up", delay)
  else
    Add(o, o.lineTop, 0, yLineTop, "up", delay)
    Add(o, o.lineBot, 0, yLineBot, "up", delay + 0.06)
  end
  Add(o, o.title, 0, Y_TITLE, "up", delay + 0.03)
  delay = delay + 0.12
  local bottom = -yLineBot + 4
  local lastY = yLineBot   -- repere du bloc suivant
  local yStats = yLineBot - STATS_BELOW_RULE

  -- Stats : meme nombre de colonnes en haut et en bas. 1 a 3 stats : une rangee ; au-dela, deux rangees, remplies
  -- colonne par colonne (PV puis ressource dans la 1re colonne). Nombre impair : la colonne a une seule stat est la
  -- derniere, sauf sans ressource (voleur, guerrier...) ou ce sont les PV, seuls dans la 1re colonne.
  local list = StatList(data.stats)
  local n = #list
  local rows = 0
  if n > 0 then
    local cols = {}
    if n <= 3 then
      for i = 1, n do cols[i] = { list[i] } end
    else
      local i = 1
      if n % 2 == 1 and not (data.stats and data.stats.power) and list[1].k == "hp" then
        cols[1] = { list[1] }
        i = 2
      end
      while i <= n do
        cols[#cols + 1] = { list[i], list[i + 1] }
        i = i + 2
      end
    end
    local nc = #cols
    local idx = 0
    for ci, col in ipairs(cols) do
      local right = -nc * STAT_COL_W / 2 + ci * STAT_COL_W
      for ri, st in ipairs(col) do
        idx = idx + 1
        local c = o.stats[idx]
        c.icon:SetTexture(MEDIA_XP .. ICONS[st.k])
        c.value:SetText("+" .. ShortNum(st.v))
        local w = c.value:GetStringWidth() + STAT_ICON
        c:SetWidth(w)
        Add(o, c, right - w / 2, yStats - (ri - 1) * STAT_ROW, "right", delay)
        delay = delay + 0.04
        if ri > rows then rows = ri end
      end
    end
    lastY = yStats - (rows - 1) * STAT_ROW
    bottom = -lastY + STAT_ICON / 2
  end

  -- Nouvelles competences : en-tete puis deux colonnes de trois au plus (rangee par rangee)
  local spells = data.spells or {}
  local n = math.min(#spells, MAX_SPELLS)
  if n > 0 then
    delay = delay + 0.04
    local yHdr = (rows > 0) and (lastY - HDR_GAP) or (yLineBot - 40)
    o.hdrText:SetText(L["XP_NL_SPELLS"])
    Add(o, o.hdr, 0, yHdr, "up", delay)
    delay = delay + 0.05
    local y0 = yHdr - SPELL_GAP
    local cellW = SPELL_ICON + 6 + SPELL_TW
    for i = 1, n do
      local sp, c = spells[i], o.spells[i]
      c.icon:SetTexture(sp.icon or 134400)
      c.name:SetText(sp.name or "")
      local r = sp.rank or (not sp.weapon and SpellRank(sp.id)) or nil
      local XB = ns.Modules and ns.Modules.XPBar
      c.plus:SetTexture(XB and XB.SpellBadge and XB.SpellBadge(sp, r) or (MEDIA_UI .. "plus.png"))
      if r and r ~= "" then
        if not r:find("^%(") then r = "(" .. r .. ")" end
        c.rank:SetText(r)
        c.rank:Show()
      else
        r = nil
        c.rank:Hide()
      end
      -- Competence d'arme : la ou les villes du maitre d'armes a la place du rang
      local cities = (not r) and sp.cities and #sp.cities > 0 and table.concat(sp.cities, ", ") or nil
      local cb = c.city
      if cities then
        cb.text:SetText(cities)
        cb:SetHeight(cb.text:GetStringHeight() + 2)
        cb.text:ClearAllPoints()
        cb.text:SetPoint("LEFT", cb, "LEFT", 0, 0)
        cb.t = 0
        cb:SetScript("OnUpdate", (cb.text:GetStringWidth() > SPELL_TW) and CityScroll or nil)
        cb:Show()
      else
        cb:SetScript("OnUpdate", nil)
        cb:Hide()
      end
      local sub = (r and (c.rank:GetStringHeight() + 1)) or (cities and (cb:GetHeight() + 1)) or 0
      local block = c.name:GetStringHeight() + sub
      c.name:ClearAllPoints()
      c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 6, -math.max(0, (SPELL_ICON - block) / 2))
      c.rank:ClearAllPoints()
      c.rank:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -1)
      cb:ClearAllPoints()
      cb:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, 0)
      local row, col = math.floor((i - 1) / 2), (i - 1) % 2 + 1
      local left = (n == 1) and -cellW / 2 or SPELL_COL_L[col]
      local y = y0 - row * SPELL_ROW
      Add(o, c, left + cellW / 2, y, "right", delay + (i - 1) * 0.05)
      bottom = -y + SPELL_ICON / 2
    end
  end

  -- Fond : taille reglee ; hauteur ajustee autour du point d'ancrage pour que la partie sombre couvre le contenu
  o.bgScale = V("toastBgScale") or 1
  o.bgFitY = math.min(2, math.max(0.45, (bottom + 30 - BG_PIVOT) / (DARK_BOTTOM - BG_PIVOT)))
  PlaceBg(o, 1)
end

-- ═══ Animations ══════════════════════════════════════════════════════════════════════════════════
-- Entree : fond en fondu + leger zoom ; titre, filets et en-tete montent du bas ; stats et sorts glissent depuis la
-- droite, decales. Sortie (apres la duree reglee) : fondu doux de l'ensemble, qui remonte legerement.
local function Step(o, el)
  local root = o.root
  o.t = o.t + el
  if o.phase == "hold" then
    if o.hold and o.t >= o.hold then o.phase, o.t = "out", 0 end
  elseif o.phase == "in" then
    local v = math.min(1, o.t / BG_DUR)
    local e = EaseOut(v)
    o.bg:SetAlpha(e * o.bgAlpha)
    PlaceBg(o, 0.97 + 0.03 * e)
    local pending = v < 1
    for _, it in ipairs(o.items) do
      local p = (o.t - it.delay) / ANIM_DUR
      if p < 1 then pending = true end
      if p < 0 then p = 0 elseif p > 1 then p = 1 end
      local ee = EaseOut(p)
      local c = it.cell
      c:SetAlpha(ee)
      c:ClearAllPoints()
      if c.dir == "right" then
        c:SetPoint("CENTER", root, "TOP", c.bx + (1 - ee) * SLIDE_R, c.by)
      else
        c:SetPoint("CENTER", root, "TOP", c.bx, c.by - (1 - ee) * SLIDE_U)
      end
    end
    if not pending then o.phase, o.t = "hold", 0 end
  elseif o.phase == "out" then
    local v = math.min(1, o.t / OUT_DUR)
    local e = EaseInOut(v)
    root:SetAlpha(1 - e)
    root:ClearAllPoints()
    root:SetPoint(o.point[1], o.point[2], o.point[3], o.point[4], o.point[5] + e * OUT_RISE)
    if v >= 1 then
      root:SetScript("OnUpdate", nil)
      root:Hide()
      root:SetAlpha(1)
      if o.onDone then o.onDone() end
    end
  end
end

local function Anchor(o, point)
  o.point = point
  o.root:ClearAllPoints()
  o.root:SetPoint(point[1], point[2], point[3], point[4], point[5])
  o.root:SetAlpha(1)
  o.root:Show()
end

-- point = { point, relTo, relPoint, x, y } ; hold = duree d'affichage (nil = reste affiche)
function LUT.Play(o, data, point, hold, onDone)
  LUT.Layout(o, data)
  o.data = data
  o.hold, o.onDone, o.phase, o.t = hold, onDone, "in", 0
  o.bg:SetAlpha(0)
  Anchor(o, point)
  o.root:SetScript("OnUpdate", function(_, el) Step(o, el) end)
end

-- Etat final immediat, sans animation (apercu pendant qu'on regle : retour visuel direct)
function LUT.ShowStatic(o, data, point)
  o.root:SetScript("OnUpdate", nil)
  LUT.Layout(o, data)
  o.data = data
  o.bg:SetAlpha(o.bgAlpha)
  for _, it in ipairs(o.items) do it.cell:SetAlpha(1) end
  Anchor(o, point)
end

-- ═══ Donnees d'un niveau ═════════════════════════════════════════════════════════════════════════
-- Sorts du niveau SUIVANT memorises a l'avance : sur Retail, une fois le niveau pris ils ne sont plus des sorts
-- "futurs" du livre de sorts. Forever : sorts vendus par l'entraineur a ce niveau (donnees livrees / releves).
local spellCache = { lvl = nil, list = nil }
local function SpellsAt(lvl)
  local XB = ns.Modules and ns.Modules.XPBar
  local ok, list = pcall(function() return XB and XB.SpellsLearnedAtLevel and XB.SpellsLearnedAtLevel(lvl) end)
  return (ok and type(list) == "table") and list or {}
end
local function CacheNextSpells()
  local lvl = (UnitLevel("player") or 0) + 1
  spellCache.lvl, spellCache.list = lvl, SpellsAt(lvl)
end

-- Gains : Retail, arguments de PLAYER_LEVEL_UP (deltas de PV, ressource, caracteristiques) ; Forever, memes donnees que
-- l'apercu du prochain niveau (gains releves pour ce niveau de cette classe, sinon Data/LevelGains.lua).
local function StatsFor(level, hp, power, a4, a5, a6, a7, a8, a9)
  local function N(v) return (type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v > 0) and v or nil end
  if ns.IsForever then
    local cf = select(2, UnitClass("player"))
    local rec = AishaddonDB and AishaddonDB.levelGainsByClass and AishaddonDB.levelGainsByClass[cf]
    rec = rec and rec[level]
    if rec and rec.v == 2 then
      return { hp = rec.hp, power = rec.power, str = rec.str, agi = rec.agi, sta = rec.sta, int = rec.int, spi = rec.spi }
    end
    local row = ns.LevelGains and ns.LevelGains[cf] and ns.LevelGains[cf][level]
    if row then
      return { hp = N(row[1]), power = N(row[2]), str = N(row[3]), agi = N(row[4]), sta = N(row[5]), int = N(row[6]), spi = N(row[7]) }
    end
    return { hp = N(hp), power = N(power), str = N(a5), agi = N(a6), sta = N(a7), int = N(a8), spi = N(a9) }
  end
  -- Retail : (niveau, PV, ressource, talents, emplacements JcJ, force, agilite, endurance, intelligence)
  return { hp = N(hp), power = N(power), str = N(a6), agi = N(a7), sta = N(a8), int = N(a9) }
end

local lastBg
local function RandomBg()
  local i = math.random(1, #BGS)
  if i == lastBg then i = i % #BGS + 1 end   -- jamais deux fois de suite le meme
  lastBg = i
  return i
end

-- ═══ Autres annonces de niveau ═══════════════════════════════════════════════════════════════════
-- Tant que notre toast est actif, les annonces de niveau qui le chevaucheraient sont coupees :
--  - Blizzard : LevelUpDisplay (rendu transparent) et le gestionnaire de toasts d'evenements (arrete par sa propre methode
--    StopToasting ; il sert aussi a d'autres annonces, d'ou une coupure limitee a la duree de notre toast, 15 s minimum,
--    comme le fait GnomeLevelUp) ;
--  - HorizonSuite (module Presence) : son bandeau "LEVEL_UP" est ignore ;
--  - GnomeLevelUp : son ecran est referme des qu'il s'ouvre.
local Suppress = { active = false, token = 0, hooked = {}, saved = {} }
Suppress.BLIZZ = { "LevelUpDisplay", "LevelUpDisplayAlertFrame", "LevelUpDisplayFrame", "LevelUpDisplayLevelFrame" }

local function ToastOn() return V("toastEnabled") ~= false end

function Suppress.StopETM()
  local etm = _G.EventToastManagerFrame
  if etm and etm.StopToasting then pcall(etm.StopToasting, etm) end
end

function Suppress.Start(seconds)
  if not ToastOn() then return end
  Suppress.active = true
  Suppress.token = Suppress.token + 1
  local token = Suppress.token
  local etm = _G.EventToastManagerFrame
  if etm and not Suppress.hooked[etm] and etm.HookScript then
    Suppress.hooked[etm] = true
    etm:HookScript("OnShow", function() if Suppress.active then Suppress.StopETM() end end)
  end
  Suppress.StopETM()
  for _, name in ipairs(Suppress.BLIZZ) do
    local f = _G[name]
    if f and f.SetAlpha then
      if Suppress.saved[f] == nil then Suppress.saved[f] = f:GetAlpha() end
      if not Suppress.hooked[f] and f.HookScript then
        Suppress.hooked[f] = true
        f:HookScript("OnShow", function(self) if Suppress.active then self:SetAlpha(0) end end)
      end
      f:SetAlpha(0)
    end
  end
  C_Timer.After(math.max(15, (seconds or 0) + 1), function()
    if token ~= Suppress.token then return end
    Suppress.active = false
    for f, a in pairs(Suppress.saved) do pcall(f.SetAlpha, f, a) end
    wipe(Suppress.saved)
  end)
end

-- Addons tiers, accroches une fois charges
function Suppress.HookAddons()
  local P = _G.HorizonSuite and _G.HorizonSuite.Presence
  if P and type(P.QueueOrPlay) == "function" and not Suppress.horizon then
    Suppress.horizon = true
    local orig = P.QueueOrPlay
    P.QueueOrPlay = function(typeName, ...)
      if typeName == "LEVEL_UP" and ToastOn() then return end
      return orig(typeName, ...)
    end
  end
  local glu = _G.GnomeLevelUpFrame
  if glu and glu.HookScript and not Suppress.hooked[glu] then
    Suppress.hooked[glu] = true
    glu:HookScript("OnShow", function(self) if ToastOn() then self:Hide() end end)
  end
end

-- ═══ Toast en jeu ════════════════════════════════════════════════════════════════════════════════
local live, pending
-- Hote hors de UIParent : DialogueUI cache UIParent (ou le rend transparent) pendant un dialogue avec un PNJ, et on
-- monte souvent de niveau en rendant une quete. Meme echelle et meme taille que UIParent, recalculees a chaque toast.
-- Test depuis le GUI (isTest) : sous UIParent en strate TOOLTIP, pour passer par-dessus le panneau d'options.
local host
local function Host(isTest)
  local parent = isTest and UIParent or WorldFrame
  if not host then host = CreateFrame("Frame", nil, parent) end
  if host:GetParent() ~= parent then host:SetParent(parent) end
  host:ClearAllPoints()
  host:SetPoint("CENTER", parent, "CENTER")
  host:SetFrameStrata(isTest and "TOOLTIP" or "FULLSCREEN")
  host:SetScale(UIParent:GetEffectiveScale() / math.max(0.01, parent:GetEffectiveScale()))
  host:SetSize(UIParent:GetWidth(), UIParent:GetHeight())
  return host
end
local function LivePoint(isTest)
  return { "TOP", Host(isTest), "CENTER", V("toastX") or 0, (V("toastY") or 220) + BG_H / 2 }
end
local function ShowLive(data, isTest)
  if not live then
    live = LUT.Build(Host(isTest), false)
    -- Clic droit sur le texte "Niveau XX !" seulement : fermeture (sortie animee habituelle). Le reste du toast
    -- laisse passer la souris (camera) ; les autres clics sur le texte traversent si le client le permet.
    live.title:EnableMouse(true)
    if live.title.SetPropagateMouseClicks then live.title:SetPropagateMouseClicks(true) end
    live.title:SetScript("OnMouseUp", function(_, button)
      if button == "RightButton" and live.phase ~= "out" then live.phase, live.t = "out", 0 end
    end)
  end
  live.isTest = isTest
  Host(isTest)
  live.root:SetFrameStrata(isTest and "TOOLTIP" or "FULLSCREEN")
  live.root:SetScale(V("toastScale") or 1)
  data.bgIndex = data.bgIndex or RandomBg()
  Suppress.Start((V("toastDuration") or 6) + 2)   -- annonces de Blizzard / d'addons coupees pendant notre toast
  LUT.Play(live, data, LivePoint(isTest), V("toastDuration"))
end

function LUT.Show(data)
  if V("toastEnabled") == false then return end
  if V("toastWaitCombat") and InCombatLockdown() then
    pending = data
    return
  end
  ShowLive(data)
end

-- Exemple pour l'apercu et le test : vrais sorts du prochain niveau s'il y en a, sinon six sorts d'exemple (pour regler
-- la grille entiere meme sur un personnage qui ne gagnera rien au prochain niveau)
local SAMPLE_ICONS = { 135963, 135949, 132269, 135873, 135926, 135893 }
function LUT.SampleData(withSpells)
  local lvl = (UnitLevel("player") or 7) + 1
  local spells = {}
  if withSpells then
    spells = SpellsAt(lvl)
    if #spells == 0 then
      spells = {}
      for i = 1, MAX_SPELLS do
        spells[i] = { name = L["XP_TOAST_SAMPLE_SPELL" .. i], rank = (i % 2 == 1) and L["XP_TOAST_SAMPLE_RANK"] or nil,
                      icon = SAMPLE_ICONS[i], upgrade = (i % 3 == 2) }
      end
      -- Exemple de competence d'arme (Forever) : villes du maitre d'armes, qui defilent si plusieurs
      local XB = ns.Modules and ns.Modules.XPBar
      local cities = XB and XB.WeaponCities and XB.WeaponCities(1180)
      if cities and #cities > 1 then spells[4].cities = cities end
    end
  end
  local stats = StatsFor(lvl)
  if not next(stats) then stats = { hp = 18, power = 25, str = 1, agi = 1 } end
  return { level = lvl, stats = stats, spells = spells, bgIndex = RandomBg() }
end

-- withSpells = false : toast de test sans competences (case "Avec competences" de l'apercu decochee)
function LUT.Test(withSpells)
  ShowLive(LUT.SampleData(withSpells ~= false), true)
end

-- Reglage modifie : toast en jeu reaffiche avec les nouvelles valeurs s'il est visible
function LUT.Refresh()
  if live and live.root:IsShown() and live.data then ShowLive(live.data, live.isTest) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LEVEL_UP" then
    local level = ...
    if type(level) ~= "number" then return end
    local spells = (spellCache.lvl == level and spellCache.list) or SpellsAt(level)
    local data = { level = level, stats = StatsFor(...), spells = spells }
    -- Coupure immediate (meme si notre toast attend la fin du combat : l'annonce de Blizzard, elle, part tout de suite)
    Suppress.HookAddons()
    Suppress.Start(15)
    LUT.Show(data)
    -- Le livre de sorts / les tables du niveau suivant ne sont a jour qu'un instant apres
    C_Timer.After(3, CacheNextSpells)
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pending then
      local d = pending
      pending = nil
      C_Timer.After(0.5, function() ShowLive(d) end)
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(3, CacheNextSpells)
    Suppress.HookAddons()
  elseif event == "ADDON_LOADED" then
    Suppress.HookAddons()
  end
end)
ev:RegisterEvent("ADDON_LOADED")

-- /aishtoast : affiche un toast d'exemple
SLASH_AISHTOAST1 = "/aishtoast"
SlashCmdList["AISHTOAST"] = function() LUT.Test(true) end

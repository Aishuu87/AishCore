-- UI/CastBarsPage.lua : page "Barres de cast" du GUI (joueur : Modules/CastBar.lua ; cible et focus :
-- Modules/TargetCastBar.lua, une instance par unite). Meme structure que la page Barres de vie : bloc epingle
-- (titre, selecteur de barre + interrupteur, apercu dont chaque element ouvre sa section au clic droit), copie des
-- reglages, puis les sections de la barre selectionnee. Changer de barre reconstruit la page (les reglages de
-- couleur different entre la barre du joueur et celles de la cible / du focus).
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local PREVIEW_H = 120
local TITLE_H, PIN_TOP_H = 30, 26
local PREVIEW_MAX_SCALE = 2
local DARK = 14 / 255

local BARS = {
  { key = "player", cfg = "castBar",       mod = "CastBar",       label = "SETTINGS_UNIT_PLAYER" },
  { key = "target", cfg = "targetCastBar", mod = "TargetCastBar", label = "SETTINGS_UNIT_TARGET" },
  { key = "focus",  cfg = "focusCastBar",  mod = "FocusCastBar",  label = "SETTINGS_UNIT_FOCUS" },
}
local BY_KEY = {}
for _, b in ipairs(BARS) do BY_KEY[b.key] = b end
-- Copie : reglages communs aux deux tables de defauts, hors position, activation et couleurs propres a chaque type
local NOT_COPIED = {
  enabled = true, locked = true, x = true, y = true, point = true, relativePoint = true,
}
-- Reglages sans valeur par defaut (absents = deduits d'un autre reglage) : copies aussi, absence comprise
local OPTIONAL = { nameAnchor = true, timerAnchor = true }

local NAME_DEFAULT  = { 0.792, 0.639, 0.392, 1 }
local TIMER_DEFAULT = { 0.847, 0.627, 0.380, 1 }

local function Sel()
  local k = ns._castBarsSelected
  return BY_KEY[k] and k or "player"
end

-- Texte : ancrage 9 points + alignement, meme regle que les modules (cf. TextPoints dans Modules/CastBar.lua)
local TP_FLIP = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
local function TextPoints(anchor, justify)
  justify = justify or "CENTER"
  if not anchor then
    anchor = (justify == "LEFT" and "TOPLEFT") or (justify == "RIGHT" and "TOPRIGHT") or "TOP"
  end
  local v = anchor:match("^TOP") or anchor:match("^BOTTOM") or ""
  local h = (justify == "CENTER") and "" or justify
  local p
  if v ~= "" then
    p = TP_FLIP[v] .. h
  else
    p = (h ~= "" and h) or (TP_FLIP[anchor:match("LEFT$") or anchor:match("RIGHT$") or ""] or "")
  end
  return (p ~= "" and p or "CENTER"), anchor
end

local ANCHORS9
local function AnchorOptions()
  if not ANCHORS9 then
    ANCHORS9 = {}
    for _, a in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do
      ANCHORS9[#ANCHORS9 + 1] = { value = a, text = L["SETTINGS_ANCHOR_" .. a] }
    end
  end
  return ANCHORS9
end

-- Animation de l'apercu : deux incantations puis une canalisation, en boucle
local PREVIEW_SPELLS = {
  { id = 133, school = 4 },                                             -- Boule de feu (feu)
  { id = 116, school = 16 },                                            -- Trait de givre (givre)
  { id = ns.IsForever and 689 or 234153, school = 32, channel = true }, -- Drain de vie (ombre)
}
local PREVIEW_CAST_TIME = 2.2
local function SpellNameIcon(id)
  local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
  local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
  if not name and GetSpellInfo then
    local n, _, ic = GetSpellInfo(id)
    name, icon = n, icon or ic
  end
  return name or L["CASTBAR_PREVIEW_SPELL_NAME"], icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local ANCHORS3 = {
  { k = "LEFT",   l = L["SETTINGS_ALIGN_LEFT"] },
  { k = "CENTER", l = L["SETTINGS_ALIGN_CENTER"] },
  { k = "RIGHT",  l = L["SETTINGS_ALIGN_RIGHT"] },
}

function ns.BuildCastBarsPage(container, W, NewLayout)
  local ctx = NewLayout(container)
  ctx.noGrid = true   -- grille propre a la page (colonnes par section, cf. Cols / Span)
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
        e._leEmpty = true   -- case vide (mode disposition, UI/LayoutEditor.lua)
        args[i] = e
      end
    end
    ctx:AddRowCentered(GAP, unpack(args))
    ctx:Spacer(4)
  end

  local selKey = Sel()
  local bar = BY_KEY[selKey]
  local isPlayer = selKey == "player"
  ns._castBarsBuiltFor = selKey

  local function Mod() return ns.Modules and ns.Modules[bar.mod] end
  local function Get(prop)
    local db = ns.DB and ns.DB[bar.cfg]
    if db and db[prop] ~= nil then return db[prop] end
    local def = ns.Defaults and ns.Defaults[bar.cfg]
    return def and def[prop]
  end
  -- Table de lecture pour ns.StyleCastIcon (attend une table de reglages)
  local cfgView = setmetatable({}, { __index = function(_, k) return Get(k) end })

  local RefreshPreview, RefreshStates = function() end, function() end
  local pending = false
  local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      local m = Mod()
      if m and m.ApplySettings then m.ApplySettings() end
      RefreshStates()
      RefreshPreview()
    end)
  end
  local function Set(prop, v)
    ns.DB[bar.cfg] = ns.DB[bar.cfg] or {}
    ns.DB[bar.cfg][prop] = v
    Changed()
  end
  local function Bind(w, prop, kind)
    local v = Get(prop)
    if kind == "bool" then
      if w.SetChecked then w:SetChecked(v and true or false) else w:SetValue(v and true or false) end
    elseif kind == "color" then
      if type(v) == "table" then w:SetColor(v[1], v[2], v[3], v[4] or 1) end
    elseif v ~= nil then
      w:SetValue(v)
    end
    w.onChanged = function(nv)
      if kind == "number" then nv = tonumber(nv) or nv end
      Set(prop, nv)
    end
    if kind == "number" then SW.TrackDB(w, function() return Get(prop) end) end
    return w
  end
  local function Gray(w, reason, on) SW.SetGrayReason(w, reason, on) end
  local function ColorTrio(col, cbA, keyA, cbB, keyB)
    local function Apply()
      local a, b = cbA:GetChecked() and true or false, cbB and cbB:GetChecked() and true or false
      Gray(col, "trio", a or b)
      -- Une case cochee reste toujours active : avec les 2 cochees (ancien profil), elles se grisaient l'une l'autre
      Gray(cbA, "trio", b and not a)
      if cbB then Gray(cbB, "trio", a and not b) end
    end
    local function Hook(cb, other, otherKey)
      local orig = cb.onChanged
      cb.onChanged = function(v)
        if orig then orig(v) end
        if v and other and other:GetChecked() then other:SetChecked(false); Set(otherKey, false) end
        Apply()
      end
    end
    Hook(cbA, cbB, keyB)
    if cbB then Hook(cbB, cbA, keyA) end
    Apply()
  end

  -- Bloc epingle : titre, selecteur, apercu ---------------------------------------------------------------------------
  local pin = CreateFrame("Frame", nil, container)
  local title = SW.CreateSectionHeader(pin, L["SETTINGS_CAT_CAST_BARS"], W)
  title:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, 0)
  ctx:PinnedTitle(title, pin)

  local top = CreateFrame("Frame", nil, pin)
  top:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, -TITLE_H)
  top:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 0, -TITLE_H)
  top:SetHeight(PIN_TOP_H)
  local opts = {}
  for _, b in ipairs(BARS) do opts[#opts + 1] = { value = b.key, text = L[b.label] } end
  local barDD = SW.CreateDropdown(top, "", opts, 420)
  barDD:SetPoint("CENTER", top, "CENTER", -32, 0)
  barDD:SetValue(selKey)
  barDD.onChanged = function(v)
    if v == selKey then return end
    ns._castBarsSelected = v
    if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("castBars") end
  end
  -- Interrupteur de la barre (module de la barre selectionnee)
  local toggle = SW.CreateToggle(top, 54)
  toggle:SetPoint("LEFT", barDD, "RIGHT", 12, 0)
  toggle:SetValue(Get("enabled") ~= false)
  toggle.onChanged = function(v)
    Set("enabled", v and true or false)
    if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("modulesOverview") end
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
  hint:SetText(L["UNITBARS_PREVIEW_HINT"])

  -- Deverrouiller : glisser-deposer de la barre a l'ecran ; au verrouillage, X / Y relus
  local slX, slY
  local dragOn = false
  local lockBtn = SW.CreateActionBtn(preview, L["UNITBARS_UNLOCK"], 130)
  lockBtn:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -6, 6)
  lockBtn:SetFrameLevel(preview:GetFrameLevel() + 60)
  lockBtn:SetScript("OnClick", function(self)
    dragOn = not dragOn
    local m = Mod()
    if m and m.SetDragUnlocked then m.SetDragUnlocked(dragOn) end
    if m and m.SetPreview then m.SetPreview(true) end
    if not dragOn then
      if slX then slX:SetValue(math.floor((Get("x") or 0) + 0.5)) end
      if slY then slY:SetValue(math.floor((Get("y") or 0) + 0.5)) end
    end
    self._lbl:SetText(dragOn and L["UNITBARS_LOCK"] or L["UNITBARS_UNLOCK"])
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)

  -- Apercu : barre fictive (rendu du GUI, a 60 %), chaque element survolable
  local pf = CreateFrame("Frame", nil, preview)
  pf:SetFrameLevel(preview:GetFrameLevel() + 5)
  local pvBg = pf:CreateTexture(nil, "BACKGROUND", nil, 1)
  pvBg:SetAllPoints(pf)
  pvBg:SetColorTexture(DARK, DARK, DARK, 1)
  local pvBorder = pf:CreateTexture(nil, "BACKGROUND", nil, 0)
  pvBorder:SetPoint("TOPLEFT", pf, "TOPLEFT", -1, 1)
  pvBorder:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 1, -1)
  pvBorder:SetColorTexture(DARK, DARK, DARK, 1)
  local pvBar = CreateFrame("StatusBar", nil, pf)
  pvBar:SetAllPoints(pf)
  pvBar:SetMinMaxValues(0, 1)
  pvBar:SetValue(0.6)
  local top2 = CreateFrame("Frame", nil, pf)
  top2:SetAllPoints(pf)
  top2:SetFrameLevel(pvBar:GetFrameLevel() + 3)
  local pvSpark = top2:CreateTexture(nil, "OVERLAY")
  pvSpark:SetBlendMode("ADD")
  local pvIcon = top2:CreateTexture(nil, "ARTWORK")
  pvIcon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(116)) or "Interface\\Icons\\INV_Misc_QuestionMark")
  local pvIconBorder = CreateFrame("Frame", nil, top2, "BackdropTemplate")
  pvIconBorder:SetFrameLevel(top2:GetFrameLevel() + 1)
  local pvName = top2:CreateFontString(nil, "OVERLAY")
  local pvNameRing = ns.CreateSlugRing and ns.CreateSlugRing(top2, pvName)
  local pvTimer = top2:CreateFontString(nil, "OVERLAY")
  local pvTimerRing = ns.CreateSlugRing and ns.CreateSlugRing(top2, pvTimer)
  -- Etat de l'animation (largeur, sens, couleurs) : pose par RefreshPreview, lu a chaque image
  local anim = { w = 260, rtl = false, fc = { 1, 1, 1, 1 }, ch = { 1, 1, 1, 1 }, idx = 1, t0 = GetTime() }

  local function ResolveColor(c, default) return type(c) == "table" and c or default end
  local heroic = ns.HasHeroicFeatures and ns.HasHeroicFeatures()
  local function SchoolGradient()
    local CBm = ns.Modules and ns.Modules.CastBar
    local cur = PREVIEW_SPELLS[anim.idx]
    local g = CBm and CBm.SchoolGradient and CBm.SchoolGradient(cur.id, cur.school)
    if not (g and CBm.ParseGradient) then return nil end
    return g, CBm.ParseGradient(g)
  end
  local function SchoolTextColor()
    local g = SchoolGradient()
    if not g then return nil end
    local _, rhex = strsplit(":", g)
    rhex = rhex or g
    return { (tonumber(rhex:sub(1, 2), 16) or 255) / 255, (tonumber(rhex:sub(3, 4), 16) or 255) / 255,
             (tonumber(rhex:sub(5, 6), 16) or 255) / 255, 1 }
  end
  local function ThemeColor()
    local CLR = ns.Modules and ns.Modules.Colors
    return CLR and CLR.Get and CLR.Get("powerdotsa")
  end
  -- Remplissage : degrade d'ecole (joueur, reglage reserve) ou couleur unie
  local function PaintBar(c)
    local tex = pvBar:GetStatusBarTexture()
    if isPlayer and heroic and Get("colorBySchool") then
      local g, lc, rc = SchoolGradient()
      if g and tex and tex.SetGradient then
        pvBar:SetStatusBarColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", lc, rc)
        return
      end
    end
    if tex and tex.SetGradient then tex:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)) end
    pvBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
  end
  -- Textes (joueur) : ecole du sort courant, couleurs thematiques, sinon couleur choisie
  local function PaintTexts()
    local nc, tc
    if isPlayer then
      nc = (heroic and Get("textUseSchoolColor") and SchoolTextColor())
        or (Get("textUseSpecColor") and ThemeColor()) or ResolveColor(Get("textColor"), NAME_DEFAULT)
      tc = (heroic and Get("timerUseSchoolColor") and SchoolTextColor())
        or (Get("timerUseSpecColor") and ThemeColor()) or ResolveColor(Get("timerColor"), nc)
    else
      nc = ResolveColor(Get("nameColor"), NAME_DEFAULT)
      tc = ResolveColor(Get("timerColor"), TIMER_DEFAULT)
    end
    pvName:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
    pvTimer:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
  end
  RefreshPreview = function()
    local w, h = Get("width") or 260, Get("height") or 3
    pf:SetSize(w, h)
    local rtl = Get("fillDir") == "RTL"
    -- Remplissage
    pvBar:SetStatusBarTexture(ns.ResolveBarTexFromKey(Get("barTexture")))
    pvBar:SetReverseFill(rtl)
    local fc, ch
    if isPlayer then
      fc = Get("barColor") or { 0.471, 0.392, 0.271, 1 }
      if Get("useSpecColor") then
        local CLR = ns.Modules and ns.Modules.Colors
        fc = (CLR and CLR.Get and CLR.Get("powerdotsa")) or fc
      end
      ch = fc
    else
      fc = Get("colorInterruptible") or { 0, 0.78, 0.78, 1 }
      ch = Get("colorChanneling") or { 0.506, 0.788, 0.243, 1 }
    end
    anim.w, anim.rtl, anim.fc, anim.ch = w, rtl, fc, ch
    local cur = PREVIEW_SPELLS[anim.idx]
    PaintBar(cur.channel and ch or fc)
    -- Etincelle (aucune : esquissee a 20 %, pour rester survolable)
    local CBm = ns.Modules and ns.Modules.CastBar
    local TEX = CBm and CBm.SPARK_TEXTURES or {}
    local sk = Get("sparkTexture") or (isPlayer and "default" or "none")
    local t = TEX[sk] or TEX.default
    if t then
      local k = (tonumber(Get("sparkSize")) or 100) / 100
      pvSpark:SetTexture(t.path or ns.Media.circle)
      pvSpark:SetSize(t.w * k, t.h * k)
      local sc = ResolveColor(Get("sparkColor"), { 1, 0.867, 0.710, 1 })
      pvSpark:SetVertexColor(sc[1], sc[2], sc[3], (sc[4] or 1) * ((sk == "none") and 0.2 or 1))
      pvSpark:Show()
    end
    -- Icone (masquee : esquissee a 20 %)
    ns.StyleCastIcon(pvIcon, pvIconBorder, cfgView)
    pvIcon:ClearAllPoints()
    local ox, oy, anchor = Get("iconOffX") or 0, Get("iconOffY") or 0, Get("iconAnchor")
    if anchor == "RIGHT" then
      pvIcon:SetPoint("LEFT", pf, "RIGHT", 4 + ox, oy)
    elseif anchor == "CENTER" then
      pvIcon:SetPoint("CENTER", pf, "CENTER", ox, oy)
    else
      pvIcon:SetPoint("RIGHT", pf, "LEFT", -4 + ox, oy)
    end
    pvIcon:Show()
    pvIcon:SetAlpha(Get("showIcon") == false and 0.2 or 1)
    pvIconBorder:SetShown(Get("iconBorder") and true or false)
    -- Nom du sort
    local nJ = Get("nameJustify") or "CENTER"
    local nS, nR = TextPoints(Get("nameAnchor"), nJ)
    ns.ApplyTextOutlineStyle(pvName, pvNameRing, Get("font") or ns.FONT_FALLBACK, Get("nameSize") or 12, Get("nameOutlineStyle"), true)
    pvName:SetJustifyH(nJ)
    pvName:SetWidth(0)
    pvName:ClearAllPoints()
    pvName:SetPoint(nS, pf, nR, Get("nameOffX") or 0, Get("nameOffY") or 9)
    -- Temps d'incantation
    local tJ = Get("timerJustify") or "RIGHT"
    local tS, tR = TextPoints(Get("timerAnchor"), tJ)
    ns.ApplyTextOutlineStyle(pvTimer, pvTimerRing, Get("timerFont") or ns.Media.font, Get("timerSize") or 8, Get("timerOutlineStyle"), true)
    pvTimer:SetJustifyH(tJ)
    pvTimer:SetWidth(0)
    pvTimer:ClearAllPoints()
    pvTimer:SetPoint(tS, pf, tR, Get("timerOffX") or 1, Get("timerOffY") or 2)
    PaintTexts()
    -- Mise a l'echelle : la barre, son icone et ses textes tiennent dans l'apercu
    local pw = preview:GetWidth()
    if not pw or pw < 50 then pw = W end
    local iw = (Get("iconWidth") or 15) + 8
    local need = math.max(h, Get("iconHeight") or 15) + 2 * ((Get("nameSize") or 12) + math.abs(Get("nameOffY") or 0))
    local sc = math.max(0.2, math.min(PREVIEW_MAX_SCALE, (pw - 60) / math.max(1, w + 2 * iw), (PREVIEW_H - 24) / math.max(1, need)))
    pf:SetScale(sc)
    pf:ClearAllPoints()
    pf:SetPoint("CENTER", preview, "CENTER", 0, -4 / sc)
  end

  local function ApplySpell()
    local cur = PREVIEW_SPELLS[anim.idx]
    local name, icon = SpellNameIcon(cur.id)
    pvName:SetText(name)
    pvIcon:SetTexture(icon)
    PaintBar(cur.channel and anim.ch or anim.fc)
    PaintTexts()
  end
  pf:SetScript("OnUpdate", function()
    local now = GetTime()
    local el = now - anim.t0
    if el >= PREVIEW_CAST_TIME then
      anim.idx = anim.idx % #PREVIEW_SPELLS + 1
      anim.t0, el = now, 0
      ApplySpell()
    end
    local prog = el / PREVIEW_CAST_TIME
    if PREVIEW_SPELLS[anim.idx].channel then prog = 1 - prog end
    pvBar:SetValue(prog)
    pvSpark:ClearAllPoints()
    pvSpark:SetPoint("CENTER", pf, "LEFT", (anim.rtl and (1 - prog) or prog) * anim.w, 0)
    pvTimer:SetText(string.format("%.1f", PREVIEW_CAST_TIME - el))
  end)

  local function PinUp()
    if ns.SettingsPin then ns.SettingsPin(pin, TITLE_H + PIN_TOP_H + 6 + PREVIEW_H) end
    RefreshPreview()
  end
  container:HookScript("OnShow", PinUp)
  container:HookScript("OnHide", function()
    if ns.SettingsUnpin then ns.SettingsUnpin(pin) end
    if dragOn then
      local m = Mod()
      if m and m.SetDragUnlocked then m.SetDragUnlocked(false) end
      dragOn = false
    end
  end)
  preview:HookScript("OnSizeChanged", function() RefreshPreview() end)

  -- Copie des reglages vers une autre barre -------------------------------------------------------------------------
  ctx:Spacer(8)
  local copyBtn = SW.CreateActionBtn(container, L["EXTRABARS_COPY_TO"], Cols(4))
  copyBtn:SetScript("OnClick", function()
    local function CopyTo(targets)
      -- Valeurs effectives de la barre source (enregistrees, sinon par defaut) : une table de reglages encore vide
      -- (jamais modifiee) se copie aussi
      local keys = {}
      for k in pairs(ns.Defaults[bar.cfg] or {}) do keys[k] = true end
      for k in pairs(ns.DB[bar.cfg] or {}) do keys[k] = true end
      for _, to in ipairs(targets) do
        local tb = BY_KEY[to]
        local tdef = ns.Defaults[tb.cfg] or {}
        ns.DB[tb.cfg] = ns.DB[tb.cfg] or {}
        for k in pairs(OPTIONAL) do keys[k] = true end
        for k in pairs(keys) do
          local v = Get(k)
          if OPTIONAL[k] then
            ns.DB[tb.cfg][k] = v
          elseif not NOT_COPIED[k] and tdef[k] ~= nil and v ~= nil then
            ns.DB[tb.cfg][k] = type(v) == "table" and CopyTable(v) or v
          end
        end
        local m = ns.Modules and ns.Modules[tb.mod]
        if m and m.ApplySettings then m.ApplySettings() end
      end
      -- Copie vers une seule barre : la page passe sur elle, le resultat se voit tout de suite
      if #targets == 1 then
        ns._castBarsSelected = targets[1]
        if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("castBars") end
      end
    end
    local items, all = {}, {}
    for _, b in ipairs(BARS) do
      if b.key ~= selKey then
        all[#all + 1] = b.key
        items[#items + 1] = { label = L[b.label], onClick = function() CopyTo({ b.key }) end }
      end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = L["EXTRABARS_COPY_ALL"], onClick = function() CopyTo(all) end }
    SW.ShowContextMenu(items)
  end)
  ctx:Add(copyBtn)

  -- Taille & Position (4 colonnes) ------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SIZE_POSITION"], W))
  local slW = Bind(SL(L["SETTINGS_WIDTH"], 60, 600, 1, 4), "width", "number")
  local slH = Bind(SL(L["SETTINGS_HEIGHT"], 1, 30, 1, 4), "height", "number")
  slX = Bind(SL(L["SETTINGS_OFFSET_X"], -1500, 1500, 1, 4), "x", "number")
  slY = Bind(SL(L["SETTINGS_OFFSET_Y"], -1000, 1000, 1, 4), "y", "number")
  Row(4, slW, slH, slX, slY)
  if isPlayer then
    Row(4, Bind(CB(L["CASTBARS_HIDE_BLIZZARD"], L["CASTBARS_HIDE_BLIZZARD_TT"], 4, 2), "hideBlizzard", "bool"), false, false)
  end

  -- Remplissage (4 colonnes) -----------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["UNITBARS_SEC_FILL"], W))
  local ddTex = Bind(DD(L["SETTINGS_BAR_TEXTURE"], ns.GetBarTextureList(), 4), "barTexture", "string")
  local rowDir = Bind(AR(L["UNITBARS_FILL_DIR"], {
    { k = "LTR", l = L["UNITBARS_FILL_LTR"] },
    { k = "RTL", l = L["UNITBARS_FILL_RTL"] },
  }, 4), "fillDir", "string")
  if Get("fillDir") == nil then rowDir:SetValue("LTR") end
  Row(4, ddTex, rowDir, false, false)
  local heroicOpt = ns.HasHeroicFeatures and ns.HasHeroicFeatures()
  if isPlayer then
    -- Couleur fixe / Couleurs Thematiques / ecole de magie (reglage reserve) : une case cochee grise le reste de la ligne
    local colBar = Bind(COL(L["SETTINGS_CB_BAR_COLOR"], 4), "barColor", "color")
    local cbSpec = Bind(CB(L["CASTBARS_THEMED"], L["SETTINGS_CB_USE_SPEC_COLOR_TT"], 4), "useSpecColor", "bool")
    local cbSchool = heroicOpt and Bind(CB(L["CASTBARS_SCHOOL"], L["SETTINGS_CB_COLOR_BY_SCHOOL_TT"], 4), "colorBySchool", "bool") or false
    Row(4, colBar, cbSpec, cbSchool, false)
    ColorTrio(colBar, cbSpec, "useSpecColor", cbSchool or nil, "colorBySchool")
  else
    -- Couleurs par type de cast (les sorts importants et non interruptibles passent par-dessus)
    Row(4,
      Bind(COL(L["SETTINGS_TCB_COLOR_INTERRUPTIBLE"], 4), "colorInterruptible", "color"),
      Bind(COL(L["SETTINGS_TCB_COLOR_IMPORTANT"], 4), "colorImportant", "color"),
      Bind(COL(L["SETTINGS_TCB_COLOR_NOT_INTERRUPTIBLE"], 4), "colorNotInterruptible", "color"),
      Bind(COL(L["SETTINGS_TCB_COLOR_CHANNELING"], 4), "colorChanneling", "color"))
  end

  -- Nom du sort (4 colonnes) -----------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CASTBARS_SEC_NAME"], W))
  -- Ancre : sans choix enregistre, deduite de l'ancien alignement (au-dessus de la barre)
  local ddNameAnchor = Bind(DD(L["UNITBARS_ANCHOR"], AnchorOptions(), 4), "nameAnchor", "string")
  ddNameAnchor:SetValue(select(2, TextPoints(Get("nameAnchor"), Get("nameJustify"))))
  Row(4,
    Bind(DD(L["SETTINGS_FONT"], ns.GetFontList(), 4), "font", "string"),
    Bind(SL(L["SETTINGS_FONT_SIZE"], 6, 28, 1, 4), "nameSize", "number"),
    Bind(DD(L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 4), "nameOutlineStyle", "string"),
    false)
  Row(4, ddNameAnchor,
    Bind(AR(L["UNITBARS_JUSTIFY"], ANCHORS3, 4), "nameJustify", "string"),
    Bind(SL(L["SETTINGS_OFFSET_X"], -100, 100, 1, 4), "nameOffX", "number"),
    Bind(SL(L["SETTINGS_OFFSET_Y"], -100, 100, 1, 4), "nameOffY", "number"))
  if isPlayer then
    local colName = Bind(COL(L["SETTINGS_CB_TEXT_COLOR"], 4), "textColor", "color")
    if type(Get("textColor")) ~= "table" then colName:SetColor(unpack(NAME_DEFAULT)) end
    local cbNSpec = Bind(CB(L["CASTBARS_THEMED"], L["SETTINGS_CB_TEXT_SPEC_TT"], 4), "textUseSpecColor", "bool")
    local cbNSchool = heroicOpt and Bind(CB(L["CASTBARS_SCHOOL"], L["SETTINGS_CB_TEXT_SCHOOL_TT"], 4), "textUseSchoolColor", "bool") or false
    Row(4, colName, cbNSpec, cbNSchool, false)
    ColorTrio(colName, cbNSpec, "textUseSpecColor", cbNSchool or nil, "textUseSchoolColor")
  else
    Row(4, Bind(COL(L["SETTINGS_TEXT_COLOR"], 4), "nameColor", "color"), false, false, false)
  end

  -- Icone du sort (4 colonnes) ---------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_SPELL_ICON"], W))
  local cbIcon = CB(L["SETTINGS_TCB_SHOW_ICON"], L["SETTINGS_TCB_SHOW_ICON_TT"], 4)
  cbIcon:SetChecked(Get("showIcon") ~= false)
  cbIcon.onChanged = function(v) Set("showIcon", v and true or false) end
  Row(4, cbIcon, false, false, false)
  local rowIconAnchor = Bind(AR(L["UNITBARS_ANCHOR"], {
    { k = "LEFT",   l = L["SETTINGS_ALIGN_LEFT"] },
    { k = "CENTER", l = L["SETTINGS_ANCHOR_MIDDLE"] },
    { k = "RIGHT",  l = L["SETTINGS_ALIGN_RIGHT"] },
  }, 4), "iconAnchor", "string")
  local slIW = Bind(SL(L["SETTINGS_WIDTH"], 4, 96, 1, 4), "iconWidth", "number")
  local slIH = Bind(SL(L["SETTINGS_HEIGHT"], 4, 96, 1, 4), "iconHeight", "number")
  Row(4, rowIconAnchor, slIW, slIH, false)
  local slIX = Bind(SL(L["SETTINGS_OFFSET_X"], -100, 100, 1, 4), "iconOffX", "number")
  local slIY = Bind(SL(L["SETTINGS_OFFSET_Y"], -100, 100, 1, 4), "iconOffY", "number")
  Row(4, slIX, slIY, false, false)
  local cbIBorder = Bind(CB(L["SETTINGS_SHOW_BORDER"], nil, 4), "iconBorder", "bool")
  local ddIBTex = Bind(DD(L["SETTINGS_BORDER_TEXTURE"], ns.GetBorderTextureList(), 4), "iconBorderTexture", "string")
  local slIBSize = Bind(SL(L["SETTINGS_THICKNESS"], 1, 16, 1, 4), "iconBorderSize", "number")
  local colIB = Bind(COL(L["SETTINGS_BORDER_COLOR"], 4), "iconBorderColor", "color")
  Row(4, cbIBorder, false, false, false)
  Row(4, ddIBTex, slIBSize, colIB, false)
  local iconWidgets = { rowIconAnchor, slIW, slIH, slIX, slIY, cbIBorder }
  local borderWidgets = { ddIBTex, slIBSize, colIB }

  -- Temps d'incantation (4 colonnes) ---------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CASTBARS_SEC_TIMER"], W))
  local ddTimerAnchor = Bind(DD(L["UNITBARS_ANCHOR"], AnchorOptions(), 4), "timerAnchor", "string")
  ddTimerAnchor:SetValue(select(2, TextPoints(Get("timerAnchor"), Get("timerJustify"))))
  Row(4,
    Bind(DD(L["SETTINGS_FONT"], ns.GetFontList(), 4), "timerFont", "string"),
    Bind(SL(L["SETTINGS_FONT_SIZE"], 6, 24, 1, 4), "timerSize", "number"),
    Bind(DD(L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 4), "timerOutlineStyle", "string"),
    false)
  Row(4, ddTimerAnchor,
    Bind(AR(L["UNITBARS_JUSTIFY"], ANCHORS3, 4), "timerJustify", "string"),
    Bind(SL(L["SETTINGS_OFFSET_X"], -100, 100, 1, 4), "timerOffX", "number"),
    Bind(SL(L["SETTINGS_OFFSET_Y"], -100, 100, 1, 4), "timerOffY", "number"))
  -- Joueur : sans couleur choisie, le temps suit la couleur du nom
  local colTimer = Bind(COL(L["SETTINGS_TEXT_COLOR"], 4), "timerColor", "color")
  if type(Get("timerColor")) ~= "table" then colTimer:SetColor(unpack(isPlayer and (Get("textColor") or NAME_DEFAULT) or TIMER_DEFAULT)) end
  if isPlayer then
    local cbTSpec = Bind(CB(L["CASTBARS_THEMED"], L["SETTINGS_CB_TEXT_SPEC_TT"], 4), "timerUseSpecColor", "bool")
    local cbTSchool = heroicOpt and Bind(CB(L["CASTBARS_SCHOOL"], L["SETTINGS_CB_TEXT_SCHOOL_TT"], 4), "timerUseSchoolColor", "bool") or false
    Row(4, colTimer, cbTSpec, cbTSchool, false)
    ColorTrio(colTimer, cbTSpec, "timerUseSpecColor", cbTSchool or nil, "timerUseSchoolColor")
  else
    Row(4, colTimer, false, false, false)
  end

  -- Etincelle (4 colonnes) -------------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["CASTBARS_SEC_SPARK"], W))
  local sparkNames = { none = L["SETTINGS_CB_SPARK_NONE"], default = L["SETTINGS_CB_SPARK_DEFAULT"], line = L["SETTINGS_CB_SPARK_LINE"],
                       star = L["SETTINGS_CB_SPARK_STAR"], burst = L["SETTINGS_CB_SPARK_BURST"], dot = L["SETTINGS_CB_SPARK_DOT"] }
  local sparkItems = {}
  local CBm = ns.Modules and ns.Modules.CastBar
  for _, k in ipairs((CBm and CBm.SPARK_KEYS) or { "none", "default" }) do
    sparkItems[#sparkItems + 1] = { value = k, text = sparkNames[k] or k }
  end
  local ddSpark = Bind(DD(L["SETTINGS_CB_SPARK_TEXTURE"], sparkItems, 4), "sparkTexture", "string")
  local slSpark = Bind(SL(L["SETTINGS_CB_SPARK_SIZE"], 25, 400, 5, 4), "sparkSize", "number")
  local colSpark = Bind(COL(L["SETTINGS_CB_SPARK_COLOR"], 4), "sparkColor", "color")
  Row(4, ddSpark, slSpark, colSpark, false)

  ctx:Spacer()
  ctx:Finalize()

  -- Etats : reglages sans effet grises ------------------------------------------------------------------------------
  RefreshStates = function()
    local iconOn = Get("showIcon") ~= false
    for _, w in ipairs(iconWidgets) do Gray(w, "icon", not iconOn) end
    for _, w in ipairs(borderWidgets) do Gray(w, "icon", not (iconOn and Get("iconBorder"))) end
    local noSpark = (Get("sparkTexture") or (isPlayer and "default" or "none")) == "none"
    Gray(slSpark, "spark", noSpark)
    Gray(colSpark, "spark", noSpark)
  end
  RefreshStates()

  -- Apercu : zones survolables (clic droit = ouvre la section, replie les autres) -------------------------------------
  local function OpenSection(labelKey)
    local panel = ns.SettingsPanel
    if panel and panel.OpenSection then panel:OpenSection("castBars", L[labelKey]:upper(), true) end
  end
  local function NewZone(labelKey, level)
    local z = CreateFrame("Button", nil, pf)
    z:SetFrameLevel(pf:GetFrameLevel() + level)
    z:RegisterForClicks("RightButtonUp")
    local hl = z:CreateTexture(nil, "OVERLAY")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    hl:SetBlendMode("ADD")
    hl:Hide()
    local edges = {}
    for i = 1, 4 do
      local t = z:CreateTexture(nil, "OVERLAY")
      local g = Theme.accentText
      t:SetColorTexture(g[1], g[2], g[3], 0.9)
      edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT");    edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");    edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");   edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    local function Show(on)
      hl:SetShown(on)
      for _, t in ipairs(edges) do t:SetShown(on) end
    end
    Show(false)
    z:SetScript("OnEnter", function(self)
      Show(true)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L[labelKey], 1, 1, 1)
      GameTooltip:AddLine(L["UNITBARS_PREVIEW_RCLICK"], 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end)
    z:SetScript("OnLeave", function() Show(false); GameTooltip:Hide() end)
    z:SetScript("OnClick", function()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      OpenSection(labelKey)
    end)
    return z
  end
  local zBar = NewZone("UNITBARS_SEC_FILL", 20)
  zBar:SetPoint("TOPLEFT", pf, "TOPLEFT", -2, 3)
  zBar:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", 2, -3)
  local zSpark = NewZone("CASTBARS_SEC_SPARK", 30)
  zSpark:SetPoint("TOPLEFT", pvSpark, "TOPLEFT", -2, 2)
  zSpark:SetPoint("BOTTOMRIGHT", pvSpark, "BOTTOMRIGHT", 2, -2)
  local zIcon = NewZone("SETTINGS_SEC_SPELL_ICON", 30)
  zIcon:SetPoint("TOPLEFT", pvIcon, "TOPLEFT", -2, 2)
  zIcon:SetPoint("BOTTOMRIGHT", pvIcon, "BOTTOMRIGHT", 2, -2)
  local zName = NewZone("CASTBARS_SEC_NAME", 30)
  zName:SetPoint("TOPLEFT", pvName, "TOPLEFT", -3, 2)
  zName:SetPoint("BOTTOMRIGHT", pvName, "BOTTOMRIGHT", 3, -2)
  local zTimer = NewZone("CASTBARS_SEC_TIMER", 31)
  zTimer:SetPoint("TOPLEFT", pvTimer, "TOPLEFT", -3, 2)
  zTimer:SetPoint("BOTTOMRIGHT", pvTimer, "BOTTOMRIGHT", 3, -2)
  -- Fond de l'apercu : clic droit = Taille & Position (sous la barre et ses zones)
  local bgClick = CreateFrame("Button", nil, preview)
  bgClick:SetAllPoints()
  bgClick:SetFrameLevel(preview:GetFrameLevel() + 1)
  bgClick:RegisterForClicks("RightButtonUp")
  bgClick:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    OpenSection("SETTINGS_SEC_SIZE_POSITION")
  end)

  -- Police des textes (et de leur anneau SLUG) posee par RefreshPreview avant tout SetText ("Font not set")
  RefreshPreview()
  ApplySpell()
  return ctx.widgets
end

-- Page deja affichee (survol d'une barre a l'ecran -> roue / clic droit) : reconstruite si la barre a change
function ns.CastBarsPageRefresh()
  if ns._castBarsBuiltFor ~= Sel() and ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("castBars") end
end

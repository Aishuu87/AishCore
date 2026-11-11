-- UI/UnitBarsPage.lua : page "Barres de vie" du GUI (logique : Modules/UnitBars.lua).
-- Bloc epingle : titre + interrupteur du module, selecteur de barre + interrupteur de la barre, apercu de la barre
-- (chaque element survolable, clic droit = sa section). Puis copie des reglages, section Generale (commune a toutes
-- les barres), Visibilite, et les sections de la barre selectionnee : changer de barre relit les valeurs sans
-- reconstruire la page.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local PREVIEW_H = 130
local TITLE_H, PIN_TOP_H = 30, 26
local PREVIEW_MAX_SCALE = 2
local GRAY = 0.35

local BAR_LABEL = {
  player = "SETTINGS_UNIT_PLAYER", target = "SETTINGS_UNIT_TARGET", focus = "SETTINGS_UNIT_FOCUS",
  pet = "SETTINGS_UNIT_PET", targettarget = "SETTINGS_UNIT_TARGET_OF_TARGET",
}
local HIDE_KEYS = { player = "hideBlizzPlayer", target = "hideBlizzTarget", focus = "hideBlizzFocus",
                    pet = "hideBlizzPet", targettarget = "hideBlizzTargetTarget" }
-- Ordre d'affichage (selecteur, cases) : Familier - Joueur - Cible - Cible de la cible - Focalisation
local ORDER = { "pet", "player", "target", "targettarget", "focus" }
-- Copie : tout sauf ce qui place ou active la barre
local NOT_COPIED = { enabled = true, x = true, y = true, layout = true, mirrorOf = true, collapsed = true, fillColor = true }

local function UB() return ns.Modules and ns.Modules.UnitBars end
local function DB()
  ns.DB.unitBars = ns.DB.unitBars or {}
  return ns.DB.unitBars
end

-- Apercus des autres modules sur cette page : cercles hors combat masques, cercle central / barre de rotation /
-- barres de cast selon les interrupteurs de l'apercu (unitBars.guiPreview*, nil = affiche).
-- on = false : retour aux apercus par defaut du panneau. Appele par SelectCategory et a la reouverture du panneau.
local PREVIEW_TOGGLES = {
  { key = "guiPreviewCircle",   label = "SETTINGS_CAT_CENTRAL_CIRCLE" },
  { key = "guiPreviewPriority", label = "SETTINGS_SEC_PRIORITY_BAR" },
  { key = "guiPreviewCast",     label = "UNITBARS_PREVIEW_CASTS" },
}
function ns.UnitBarsGuiPreviews(on)
  local M = ns.Modules
  local RC, HC, OCRC = M.ResourceCircle, M.HealthCircle, M.OutOfCombatResourceCircle
  local PB, CB, TCB = M.PriorityBar, M.CastBar, M.TargetCastBar
  local function Want(k) return not on or DB()[k] ~= false end
  if HC and HC.SetPreview then HC.SetPreview(not on) end
  if on then
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(false)  end
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(true) end
  else
    if OCRC and OCRC.SetGuiHidden then OCRC.SetGuiHidden(false) end
    if OCRC and OCRC.SetPreview   then OCRC.SetPreview(true)    end
  end
  if RC and RC.SetPreview then RC.SetPreview(Want("guiPreviewCircle")) end
  local pb = Want("guiPreviewPriority")
  if PB and PB.SetGuiHidden then PB.SetGuiHidden(not pb) end
  if PB and PB.SetPreview   then PB.SetPreview(pb) end
  -- Interrupteur ON : visible meme si une regle (hors combat, cible...) devrait la cacher
  if PB and PB.SetGuiForced then PB.SetGuiForced(on and pb) end
  if CB  and CB.SetPreview  then CB.SetPreview(Want("guiPreviewCast")) end
  -- Cast cible / focus : pas d'apercu hors de leur page
  if TCB and TCB.SetPreview then TCB.SetPreview(on and DB().guiPreviewCast ~= false) end
  local FCB = M.FocusCastBar
  if FCB and FCB.SetPreview then FCB.SetPreview(on and DB().guiPreviewCast ~= false) end
end
local function GV(prop)
  local v = DB()[prop]
  if v == nil and ns.Defaults and ns.Defaults.unitBars then v = ns.Defaults.unitBars[prop] end
  return v
end

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

-- Grise un widget et lui retire la souris (un cache capte les clics), sans le masquer. `keepAlpha` : module coupe,
-- la page entiere est deja grisee (SW.AttachTitleToggle), l'opacite n'est pas touchee.
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

-- Sous-titre simple (texte seul), dans une section
local function Subtitle(parent, text, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 18)
  local lbl = f:CreateFontString(nil, "OVERLAY")
  lbl:SetFont(ns.Media.fontGui, 10)
  lbl:SetPoint("LEFT", f, "LEFT", 0, 0)
  lbl:SetTextColor(unpack(Theme.textDim))
  lbl:SetText(text)
  return f
end

function ns.BuildUnitBarsPage(container, W, NewLayout)
  local ctx = NewLayout(container)
  ctx.noGrid = true   -- grille propre a la page (colonnes par section, cf. Cols / Span)
  -- Grille de colonnes : chaque section a un nombre de colonnes fixe, chaque widget occupe une cellule (ou `span`
  -- cellules) ; les rangees s'alignent donc colonne par colonne. Row(n, ...) : widgets, ou false = cellule vide.
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
  ns._unitBarsSelected = ns._unitBarsSelected or "player"

  local function Sel() return ns._unitBarsSelected end
  local function Bar()
    local db = DB()
    db.bars = db.bars or {}
    db.bars[Sel()] = db.bars[Sel()] or {}
    return db.bars[Sel()]
  end
  local function BV(prop) local m = UB(); return m and m.BV(Sel(), prop) end

  local bound, gbound = {}, {}
  local RefreshAll, RefreshPreview, RefreshStates
  -- Regroupe a une seule application par frame : un slider qu'on tire envoie une valeur par mouvement de souris.
  local pending = false
  local function Changed()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
      pending = false
      local m = UB()
      if m then m.ApplySettings() end
      RefreshStates()
      RefreshPreview()
    end)
  end

  -- Liaisons widget <-> reglage de la barre selectionnee
  local function Bind(w, key, kind)
    bound[#bound + 1] = { w = w, key = key, kind = kind }
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      Bar()[key] = v
      Changed()
    end
    return w
  end
  -- Liaisons widget <-> reglage commun (racine de unitBars) ; `invert` : case cochee = valeur false
  local function GBind(w, key, kind, invert)
    gbound[#gbound + 1] = { w = w, key = key, kind = kind, invert = invert }
    w.onChanged = function(v)
      if kind == "number" then v = tonumber(v) or v end
      if invert then v = not v end
      DB()[key] = v
      Changed()
    end
    return w
  end

  -- Bloc epingle en haut de la page (reste visible quand on defile) : titre, selecteur, apercu ---------------------
  local pin = CreateFrame("Frame", nil, container)

  local title = SW.CreateSectionHeader(pin, L["SETTINGS_SEC_UNIT_BARS"], W)
  title:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, 0)
  ctx:PinnedTitle(title, pin)
  local cbModule = GBind(SW.CreateCheckbox(container, L["SETTINGS_UB_ENABLE"], L["SETTINGS_UB_ENABLE_TT"], W), "enabled", "bool")
  local origModule = cbModule.onChanged
  cbModule.onChanged = function(v)
    origModule(v)
    if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("modulesOverview") end
  end
  ctx:TitleToggle(cbModule)

  -- Selecteur de barre (centre) + interrupteur de la barre
  local top = CreateFrame("Frame", nil, pin)
  top:SetPoint("TOPLEFT", pin, "TOPLEFT", 0, -TITLE_H)
  top:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 0, -TITLE_H)
  top:SetHeight(PIN_TOP_H)
  local barDD = SW.CreateDropdown(top, "", {}, 420)
  barDD:SetPoint("CENTER", top, "CENTER", -32, 0)
  local toggle = SW.CreateToggle(top, 54)
  toggle:SetPoint("LEFT", barDD, "RIGHT", 12, 0)
  barDD.onChanged = function(v) ns._unitBarsSelected = v; RefreshAll() end
  toggle.onChanged = function(v)
    Bar().enabled = v and true or false
    if ns.InvalidateSettingsPage then ns.InvalidateSettingsPage("modulesOverview") end
    Changed()
  end

  -- Apercu : la barre selectionnee, rendue par le module (meme rendu qu'en jeu), sur une capture d'ecran du jeu
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
  hint:SetTextColor(1, 1, 1, 1)   -- blanc pur, ombre : lisible sur la capture d'ecran du fond
  hint:SetShadowColor(0, 0, 0, 0.9)
  hint:SetShadowOffset(1, -1)
  hint:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 8, 6)
  hint:SetText(L["UNITBARS_PREVIEW_HINT"])
  local pf = UB() and UB().CreatePreview(preview)
  -- Verrouiller / deverrouiller le glisser-deposer des barres a l'ecran (unitBars.locked)
  local lockBtn = SW.CreateActionBtn(preview, L["UNITBARS_LOCK"], 130)
  lockBtn:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -6, 6)
  lockBtn:SetFrameLevel(preview:GetFrameLevel() + 60)
  lockBtn:SetScript("OnClick", function(self)
    DB().locked = not GV("locked")
    self._lbl:SetText(GV("locked") and L["UNITBARS_UNLOCK"] or L["UNITBARS_LOCK"])
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  end)
  -- Interrupteurs des apercus des autres modules, empiles au-dessus du bouton de verrouillage
  local prevToggles = {}
  local below = lockBtn
  for i = #PREVIEW_TOGGLES, 1, -1 do
    local e = PREVIEW_TOGGLES[i]
    local t = SW.CreateToggle(preview, 40)
    t:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, 6)
    t:SetFrameLevel(preview:GetFrameLevel() + 60)
    local lbl = preview:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10)
    lbl:SetTextColor(1, 1, 1, 1)
    lbl:SetShadowColor(0, 0, 0, 0.9)
    lbl:SetShadowOffset(1, -1)
    lbl:SetPoint("RIGHT", t, "LEFT", -6, 0)
    lbl:SetText(L[e.label])
    t.onChanged = function(v)
      DB()[e.key] = v and true or false
      ns.UnitBarsGuiPreviews(true)
    end
    prevToggles[e.key] = t
    below = t
  end

  local function PinUp()
    if ns.SettingsPin then ns.SettingsPin(pin, TITLE_H + PIN_TOP_H + 6 + PREVIEW_H) end
  end
  container:HookScript("OnShow", PinUp)
  container:HookScript("OnHide", function() if ns.SettingsUnpin then ns.SettingsUnpin(pin) end end)

  -- Copie des reglages vers une autre barre ---------------------------------------------------------------------
  ctx:Spacer(8)
  local copyBtn = SW.CreateActionBtn(container, L["EXTRABARS_COPY_TO"], Cols(4))
  copyBtn:SetScript("OnClick", function()
    local from = Sel()
    local function CopyTo(targets)
      local bars = DB().bars
      for _, to in ipairs(targets) do
        bars[to] = bars[to] or {}
        for k, v in pairs(bars[from] or {}) do
          if not NOT_COPIED[k] then bars[to][k] = type(v) == "table" and CopyTable(v) or v end
        end
      end
      print("|cff00ccff[AishCore]|r " .. L["UNITBARS_COPIED"])
      Changed()
    end
    local items, all = {}, {}
    for _, k in ipairs(ORDER) do
      if k ~= from then
        all[#all + 1] = k
        items[#items + 1] = { label = L[BAR_LABEL[k]], onClick = function() CopyTo({ k }) end }
      end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = L["EXTRABARS_COPY_ALL"], onClick = function() CopyTo(all) end }
    SW.ShowContextMenu(items)
  end)
  copyBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["UNITBARS_COPY_HINT"], 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  copyBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
  ctx:Add(copyBtn)

  -- General : reglages communs a toutes les barres (5 colonnes) ---------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["UNITBARS_SEC_GENERAL"], W))

  -- Cadres d'unites Blizzard (Modules/BlizzardUnitFrames.lua) : masquage reversible, sans /reload
  ctx:Add(Subtitle(container, L["SETTINGS_SEC_HIDE_BLIZZARD_FRAMES"], W))
  local hideCBs = {}
  for _, k in ipairs(ORDER) do
    local cb = GBind(CB(L[BAR_LABEL[k]], L["SETTINGS_HIDE_BLIZZARD_FRAME_TT"], 5), HIDE_KEYS[k], "bool")
    local orig = cb.onChanged
    cb.onChanged = function(v)
      orig(v)
      local M = ns.Modules and ns.Modules.BlizzardUnitFrames
      if M then M.ApplySettings() end
    end
    hideCBs[#hideCBs + 1] = cb
  end
  Row(5, unpack(hideCBs))

  -- Couleurs (5 colonnes, colonnes 1-2) ; puis hauteur en spe tank, bouclier et soins previsionnels (3 colonnes). Couleurs inversees : champ
  -- "reversed", sens inverse du libelle ; couleur de la vie grisee tant que les couleurs thematiques sont cochees,
  -- couleur de fond toujours reglable.
  local function Sub(key, n) return Subtitle(container, L[key], Cols(n or 5)) end
  local cbInvert = GBind(CB(L["SETTINGS_UB_COLOR_INVERTED"], L["SETTINGS_UB_COLOR_INVERTED_TT"], 5), "reversed", "bool", true)
  local cbThemed = GBind(CB(L["SETTINGS_UB_THEMED_COLORS"], L["SETTINGS_UB_THEMED_COLORS_TT"], 5), "themedColors", "bool")
  local colBar = GBind(COL(L["UNITBARS_HEALTH_COLOR"], 5), "barColor", "color")
  local colBg  = GBind(COL(L["UNITBARS_BG_COLOR"], 5), "bgColor", "color")
  local cbAbsorb = GBind(CB(L["SETTINGS_UB_SHOW_SHIELD_BAR"], L["SETTINGS_UB_SHOW_SHIELD_BAR_TT"],3), "showAbsorb", "bool")
  local cbAbsorbRev = GBind(CB(L["SETTINGS_UB_ABSORB_MIRROR"], L["SETTINGS_UB_ABSORB_MIRROR_TT"],3), "absorbReversed", "bool")
  local colAbsorb = GBind(COL(L["SETTINGS_UB_ABSORB_COLOR"],3), "absorbColor", "color")
  local cbHeal = GBind(CB(L["SETTINGS_UB_HEALPRED"], L["SETTINGS_UB_HEALPRED_TT"],3), "showHealPrediction", "bool")
  local colHeal = GBind(COL(L["SETTINGS_UB_HEALPRED_COLOR"],3), "healPredColor", "color")
  Row(5, Sub("UNITBARS_SUB_COLORS"), false, false, false, false)
  Row(5, cbThemed, false, false, false, false)
  Row(5, colBar, colBg, false, false, false)
  -- Reaction des PNJ (cible, cible de la cible) : grisees hors couleurs thematiques
  local colReact = {
    GBind(COL(L["UNITBARS_COLOR_HOSTILE"], 5), "hostileColor", "color"),
    GBind(COL(L["UNITBARS_COLOR_NEUTRAL"], 5), "neutralColor", "color"),
    GBind(COL(L["UNITBARS_COLOR_FRIENDLY"], 5), "friendlyColor", "color"),
    GBind(COL(L["UNITBARS_COLOR_LOWLEVEL"], 5), "lowLevelColor", "color"),
  }
  Row(5, colReact[1], colReact[2], colReact[3], colReact[4], false)
  Row(5, cbInvert, false, false, false, false)
  -- Hauteur elargie en spe tank (joueur, cible, focalisation) : slider sans titre, grise tant que la case est decochee
  local cbTank = GBind(CB(L["SETTINGS_UB_TANK_HEIGHT"], L["SETTINGS_UB_TANK_HEIGHT_TT"],3), "useTankHeight", "bool")
  local slTank = GBind(SL("", 2, 60, 1, 3), "tankHeight", "number")
  Row(3, Sub("UNITBARS_SUB_TANK", 3), Sub("SETTINGS_SEC_SHIELD_BAR", 3), Sub("UNITBARS_SUB_HEALPRED", 3))
  Row(3, cbTank, cbAbsorb, cbHeal)
  Row(3, slTank, cbAbsorbRev, colHeal)
  Row(3, false, colAbsorb, false)

  -- Visibilite : cases cumulables (l'une suffit a montrer les cadres ; en combat ils sont toujours visibles), en une
  -- colonne ou une colonne par role de la spe active ("Options par role"). Cf. UnitBars.GetVisRules.
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_VISIBILITY"], W))
  local RefreshVis
  do
    local UBm = UB()
    local KEYS = UBm and UBm.VIS_KEYS or {}
    local LABEL = {
      always = L["SETTINGS_UB_VR_ALWAYS"], hover = L["SETTINGS_UB_VIS_HOVER"],
      friendly = L["SETTINGS_UB_VR_FRIENDLY"], attackable = L["SETTINGS_UB_VR_ATTACKABLE"],
      group = L["SETTINGS_UB_VR_GROUP"], instance = L["SETTINGS_UB_VR_INSTANCE"],
      hideMount = L["SETTINGS_UB_VR_HIDE_MOUNT"], hideRest = L["SETTINGS_UB_VR_HIDE_REST"],
    }
    local TT = {
      always = L["SETTINGS_UB_VR_ALWAYS_TT"], hover = L["SETTINGS_UB_VIS_HOVER_TT"],
      hideMount = L["SETTINGS_UB_VR_HIDE_TT"], hideRest = L["SETTINGS_UB_VR_HIDE_TT"],
    }
    -- Avec "Toujours", les conditions qui montrent les cadres n'ont plus d'effet : grisees ; les "Cacher" restent actives
    local LOCKABLE = { hover = true, friendly = true, attackable = true, group = true, instance = true }
    local CB_H, GAP_HIDE = 26, 8
    local columns = {}   -- { role, cbs }

    local function RefreshColumn(col)
      local r = UBm.GetVisRules(col.role)
      for key, cb in pairs(col.cbs) do
        cb:SetChecked(r[key] and true or false)
        local locked = r.always and LOCKABLE[key]
        cb:SetAlpha(locked and 0.4 or 1)
        cb:EnableMouse(not locked)
      end
    end
    RefreshVis = function() for _, col in ipairs(columns) do RefreshColumn(col) end end

    local function BuildColumn(parent, x, y0, w, role)
      local col = { role = role, cbs = {} }
      local y = y0
      for _, key in ipairs(KEYS) do
        if key == "hideMount" then y = y + GAP_HIDE end
        local cb = SW.CreateCheckbox(parent, LABEL[key], TT[key], w)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        cb.onChanged = function(v)
          UBm.SetVisRule(role, key, v)
          RefreshVis()   -- invariant Toujours / Au survol : l'autre case a pu changer
          Changed()
        end
        col.cbs[key] = cb
        y = y + CB_H
      end
      columns[#columns + 1] = col
      return y
    end

    local cbRole = GBind(SW.CreateCheckbox(container, L["SETTINGS_UB_ROLE_OPTIONS"], L["SETTINGS_UB_ROLE_OPTIONS_TT"], W), "roleVisibility", "bool")
    ctx:Add(cbRole)

    local visBox = CreateFrame("Frame", nil, container)
    visBox:SetSize(W, 1)

    -- Colonne simple
    local simple = CreateFrame("Frame", nil, visBox)
    simple:SetPoint("TOPLEFT")
    local simpleH = BuildColumn(simple, 0, 4, math.floor(W / 2), nil) + 4
    simple:SetSize(W, simpleH)

    -- Trois colonnes par role, separees par deux filets grunge verticaux
    local roles = CreateFrame("Frame", nil, visBox)
    roles:SetPoint("TOPLEFT")
    local SEP = 24
    local INDENT = 50   -- retrait a gauche ; les 3 colonnes se partagent la largeur restante
    local colW = math.floor((W - INDENT - 2 * SEP) / 3)
    local ROLE_TITLE_H = 26
    local ROLE_TITLE = { DAMAGER = L["SETTINGS_UB_ROLE_DAMAGER"], HEALER = L["SETTINGS_UB_ROLE_HEALER"], TANK = L["SETTINGS_UB_ROLE_TANK"] }
    -- Nom d'une specialisation dans SA couleur "Cercle de puissance" (module Couleurs, reglage de cette spe)
    local function SpecColored(classFile, specID, name)
      local CLR = ns.Modules and ns.Modules.Colors
      local c = CLR and CLR.GetForSpec and classFile and specID and CLR.GetForSpec(classFile:lower(), specID, "powercircle")
      if not c then return name end
      return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, name)
    end
    -- Specialisations du role, toutes classes : { { classe, "spe, spe" (colorees) }, ... }. Client sans ces API (ou
    -- qui ne renvoie rien) : repli sur les specialisations de la classe du joueur.
    local function RoleSpecLines(role)
      local lines = {}
      if GetNumClasses and GetClassInfo and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        for c = 1, GetNumClasses() do
          local cname, cfile, cid = GetClassInfo(c)
          local specs = {}
          for idx = 1, (cid and GetNumSpecializationsForClassID(cid) or 0) do
            local sid, sname, _, _, r = GetSpecializationInfoForClassID(cid, idx)
            if sid and ns.HEALER_LIKE_SPECS and ns.HEALER_LIKE_SPECS[sid] then r = "HEALER" end   -- Augmentation
            -- Forever : le druide a un seul arbre "Combat farouche" (Farouche + Gardien), traite comme tank
            if ns.IsForever and cfile == "DRUID" then
              if sid == 103 then sname = nil end
              if sid == 104 then sname = L["SETTINGS_UB_FERAL_COMBAT"] end
            end
            if r == role and sname then specs[#specs + 1] = SpecColored(cfile, sid, sname) end
          end
          if cname and #specs > 0 then lines[#lines + 1] = { cname, table.concat(specs, ", ") } end
        end
      end
      if #lines == 0 then
        local cname, cfile = UnitClass("player")
        local specs = {}
        for idx = 1, (ns.GetNumSpecs and ns.GetNumSpecs() or 0) do
          local sid, name, _, _, r = ns.GetSpecializationInfo(idx)
          if sid and ns.HEALER_LIKE_SPECS and ns.HEALER_LIKE_SPECS[sid] then r = "HEALER" end
          if r == role and name then specs[#specs + 1] = SpecColored(cfile, sid, name) end
        end
        if #specs > 0 then lines[1] = { cname, table.concat(specs, ", ") } end
      end
      return lines
    end

    local rolesH = 0
    for i, role in ipairs({ "DAMAGER", "HEALER", "TANK" }) do
      local x = INDENT + (i - 1) * (colW + SEP)
      -- Titre : survol = specialisations comprises dans ce role
      local t = CreateFrame("Button", nil, roles)
      t:SetSize(colW, ROLE_TITLE_H - 4)
      t:SetPoint("TOPLEFT", roles, "TOPLEFT", x - 65, -2)   -- titre decale de 65 px vers la gauche
      local fs = t:CreateFontString(nil, "OVERLAY")
      fs:SetFont(ns.Media.fontGui, 12)
      fs:SetPoint("CENTER")
      fs:SetTextColor(Theme.accentText[1], Theme.accentText[2], Theme.accentText[3], 1)
      fs:SetText(ROLE_TITLE[role])
      t:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ROLE_TITLE[role], 1, 1, 1)
        local lines = RoleSpecLines(role)
        if #lines == 0 then
          GameTooltip:AddLine(L["SETTINGS_UB_ROLE_NONE"], 0.8, 0.8, 0.8, true)
        else
          for _, ln in ipairs(lines) do GameTooltip:AddLine(ln[1] .. " : " .. ln[2], 0.85, 0.85, 0.85, true) end
        end
        GameTooltip:Show()
      end)
      t:SetScript("OnLeave", function() GameTooltip:Hide() end)
      rolesH = math.max(rolesH, BuildColumn(roles, x, ROLE_TITLE_H, colW, role))
      if i > 1 then
        local div = roles:CreateTexture(nil, "ARTWORK")
        div:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\DividerGrungeV.tga")
        div:SetWidth(8)
        div:SetPoint("TOP", roles, "TOPLEFT", x - SEP / 2 - 40, -2)
        local sc = Theme.separator or { 1, 1, 1, 0.15 }
        div:SetVertexColor(sc[1], sc[2], sc[3], math.min(1, (sc[4] or 0.15) * 1.5))
        roles._divs = roles._divs or {}
        roles._divs[#roles._divs + 1] = div
      end
    end
    rolesH = rolesH + 4
    roles:SetSize(W, rolesH)
    for _, div in ipairs(roles._divs or {}) do div:SetHeight(rolesH - 4) end

    local function ShowMode()
      local on = GV("roleVisibility") == true
      simple:SetShown(not on)
      roles:SetShown(on)
      visBox:SetHeight(on and rolesH or simpleH)
      if ctx._finalized then ctx:Relayout(true) end
    end
    local origRole = cbRole.onChanged
    cbRole.onChanged = function(v)
      origRole(v)
      ShowMode()
    end
    ShowMode()
    ctx:Add(visBox)

    -- Tolerance du survol : elargit la detection du survol et la zone cliquable des barres. Le slider dessine la
    -- zone cliquable a l'ecran : c'est elle qu'on regle a l'aveugle.
    ctx:Spacer(10)
    local slTol = GBind(SL(L["SETTINGS_UB_HOVER_TOLERANCE"], 0, 60, 1, 4), "hoverTolerance", "number")
    slTol.tooltipText = L["SETTINGS_UB_HOVER_TOLERANCE_TT"]
    local origTol = slTol.onChanged
    slTol.onChanged = function(v)
      origTol(v)
      local m = UB()
      if m and m.FlashHitbox then C_Timer.After(0, m.FlashHitbox) end
    end
    ctx:Add(slTol)
  end

  -- Position & Taille (4 colonnes) ---------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["UNITBARS_SEC_POSITION"], W))
  local slW = Bind(SL(L["SETTINGS_WIDTH"], 20, 700, 1, 4), "width", "number")
  local slH = Bind(SL(L["SETTINGS_HEIGHT"], 2, 60, 1, 4), "height", "number")
  -- X / Y : position libre, ou decalage par rapport a la barre de reference en parente (relX / relY). Hors de
  -- `bound` : relus par RefreshPos (position calculee d'une barre liee).
  local slX = SL(L["SETTINGS_OFFSET_X"], -1000, 1000, 1, 4)
  local slY = SL(L["SETTINGS_OFFSET_Y"], -700, 700, 1, 4)
  for axis, sl in pairs({ X = slX, Y = slY }) do
    sl.onChanged = function(v)
      local key = (BV("layout") == "parent" and UB() and UB().IsLinked(Sel())) and ("rel" .. axis) or axis:lower()
      Bar()[key] = tonumber(v) or 0
      Changed()
    end
  end
  Row(4, slW, slH, slX, slY)
  -- Disposition : libre (x / y), ou en symetrie d'une autre barre (axe vertical au centre de l'ecran)
  local rowLayout = Bind(AR(L["UNITBARS_LAYOUT"], {
    { k = "free",   l = L["UNITBARS_LAYOUT_FREE"] },
    { k = "mirror", l = L["UNITBARS_LAYOUT_MIRROR"] },
    { k = "parent", l = L["UNITBARS_LAYOUT_PARENT"] },
  }, 4), "layout", "string")
  -- La barre garde sa place a l'ecran quand on change de disposition ou de barre de reference : libre = position
  -- actuelle ; parentee = decalage actuel par rapport a la reference. (La symetrie, elle, impose sa position.)
  local function KeepPlace(apply)
    local m = UB()
    if not m then return apply() end
    local x, y = m.BarPos(Sel())
    apply()
    local bc = Bar()
    if bc.layout == "free" then
      bc.x, bc.y = math.floor(x + 0.5), math.floor(y + 0.5)
    elseif bc.layout == "parent" and m.IsLinked(Sel()) then
      local sx, sy = m.BarPos(bc.mirrorOf)
      bc.relX, bc.relY = math.floor(x - sx + 0.5), math.floor(y - sy + 0.5)
    end
  end
  local origLayout = rowLayout.onChanged
  rowLayout.onChanged = function(v) KeepPlace(function() origLayout(v) end) end
  local ddMirror = Bind(DD(L["UNITBARS_MIRROR_OF"], {}, 4), "mirrorOf", "string")
  local origMirror = ddMirror.onChanged
  ddMirror.onChanged = function(v) KeepPlace(function() origMirror(v) end) end
  Row(4, false, rowLayout, ddMirror, false)

  -- Nom et niveau de l'unite (4 colonnes) --------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["UNITBARS_SEC_NAME"], W))
  local cbName = Bind(CB(L["UNITBARS_SHOW_NAME"], nil, 4), "showName", "bool")
  local cbLevel = Bind(CB(L["UNITBARS_SHOW_LEVEL"], L["SETTINGS_UB_TARGET_LEVEL_TT"], 4), "showLevel", "bool")
  -- Joueur seulement : nom en permanence, et plus seulement au survol (invisible sur les autres barres)
  local cbNameAlways = Bind(CB(L["UNITBARS_NAME_ALWAYS"], L["UNITBARS_NAME_ALWAYS_TT"], 4), "nameAlways", "bool")
  Row(4, cbName, cbLevel, cbNameAlways, false)
  local ddNameFont = Bind(DD(L["SETTINGS_FONT"], ns.GetFontList(), 4), "nameFont", "string")
  local slNameSize = Bind(SL(L["SETTINGS_FONT_SIZE"], 6, 40, 1, 4), "nameSize", "number")
  local ddNameOutline = Bind(DD(L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 4), "nameOutline", "string")
  local rowJustify = Bind(AR(L["UNITBARS_JUSTIFY"], nil, 4), "nameJustify", "string")
  Row(4, ddNameFont, slNameSize, ddNameOutline, rowJustify)
  local ddNameAnchor = Bind(DD(L["UNITBARS_ANCHOR"], AnchorOptions(), 4), "nameAnchor", "string")
  local slNameX = Bind(SL(L["SETTINGS_OFFSET_X"], -200, 200, 1, 4), "nameOffX", "number")
  local slNameY = Bind(SL(L["SETTINGS_OFFSET_Y"], -200, 200, 1, 4), "nameOffY", "number")
  -- Largeur de boite : coupe le nom trop long (0 = libre) ; la boite s'affiche dans l'apercu pendant le reglage
  local slNameBox = Bind(SL(L["UNITBARS_NAME_BOX_W"], 0, 400, 1, 4), "nameBoxW", "number")
  slNameBox.tooltipText = L["UNITBARS_NAME_BOX_W_TT"]
  Row(4, ddNameAnchor, slNameX, slNameY, slNameBox)
  -- Ombre derriere la barre : hors grisage du nom (elle ne depend pas de lui)
  local cbShadow = Bind(CB(L["UNITBARS_NAME_SHADOW"], L["UNITBARS_NAME_SHADOW_TT"], 4), "nameShadow", "bool")
  local slShadowA = Bind(SL(L["UNITBARS_NAME_SHADOW_ALPHA"], 0, 1, 0.05, 4), "nameShadowAlpha", "number")
  local cbShadowFlip = Bind(CB(L["UNITBARS_SHADOW_FLIP"], L["UNITBARS_SHADOW_FLIP_TT"], 4), "nameShadowFlip", "bool")
  Row(4, cbShadow, slShadowA, cbShadowFlip, false)
  local slShadowW = Bind(SL(L["UNITBARS_SHADOW_W"], 10, 200, 5, 4), "nameShadowW", "number")
  local slShadowH = Bind(SL(L["UNITBARS_SHADOW_H"], 10, 400, 5, 4), "nameShadowH", "number")
  Row(4, slShadowW, slShadowH, false, false)
  local nameWidgets = { cbLevel, ddNameFont, slNameSize, ddNameOutline, ddNameAnchor, rowJustify, slNameX, slNameY, slNameBox }

  -- Texte de vie (4 colonnes) : texte, puis son cadre (forme, taille, couleur) --------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["SETTINGS_SEC_HP_TEXT"], W))
  local cbHp = Bind(CB(L["UNITBARS_HP_SHOW"], nil, 4), "hpShow", "bool")
  Row(4, cbHp, false, false, false)
  local cbHpHover = Bind(CB(L["SETTINGS_UB_HP_HOVER_VALUE"], L["SETTINGS_UB_HP_HOVER_VALUE_TT"], 4), "hpHoverValue", "bool")
  local rowHpMode = Bind(AR(L["UNITBARS_HP_MODE"], {
    { k = "pct",   l = L["UNITBARS_HP_MODE_PCT"] },
    { k = "value", l = L["UNITBARS_HP_MODE_VALUE"] },
  }, 4), "hpMode", "string")
  Row(4, cbHpHover, rowHpMode, false, false)
  local ddHpFont = Bind(DD(L["SETTINGS_FONT"], ns.GetFontList(), 4), "hpFont", "string")
  local slHpSize = Bind(SL(L["SETTINGS_FONT_SIZE"], 6, 40, 1, 4), "hpSize", "number")
  local ddHpOutline = Bind(DD(L["SETTINGS_TEXT_OUTLINE"], ns.GetTextOutlineStyles(), 4), "hpOutline", "string")
  local ddHpAnchor = Bind(DD(L["UNITBARS_ANCHOR"], AnchorOptions(), 4), "hpAnchor", "string")
  local slHpX = Bind(SL(L["SETTINGS_OFFSET_X"], -200, 200, 1, 4), "hpOffX", "number")
  local slHpY = Bind(SL(L["SETTINGS_OFFSET_Y"], -200, 200, 1, 4), "hpOffY", "number")
  Row(4, ddHpFont, slHpSize, ddHpOutline, false)
  Row(4, ddHpAnchor, slHpX, slHpY, false)
  local cbHpBg = Bind(CB(L["UNITBARS_HP_BG"], L["UNITBARS_HP_BG_TT"], 4), "hpBg", "bool")
  Row(4, cbHpBg, false, false, false)
  local slHpW = Bind(SL(L["SETTINGS_WIDTH"], 8, 200, 1, 4), "hpBoxW", "number")
  local slHpH = Bind(SL(L["SETTINGS_HEIGHT"], 6, 80, 1, 4), "hpBoxH", "number")
  local colHpBg = Bind(COL(L["UNITBARS_COLOR"], 4), "hpBgColor", "color")
  local ddHpShape = Bind(DD(L["UNITBARS_HP_SHAPE"], {
    { value = "rect",    text = L["UNITBARS_BOX_RECT"] },
    { value = "diamond", text = L["UNITBARS_BOX_DIAMOND"] },
    { value = "circle",  text = L["UNITBARS_BOX_CIRCLE"] },
  }, 4), "hpBgShape", "string")
  Row(4, slHpW, slHpH, colHpBg, ddHpShape)
  local hpWidgets = { cbHpHover, rowHpMode, ddHpFont, slHpSize, ddHpOutline, ddHpAnchor, slHpX, slHpY, cbHpBg }
  local hpBoxWidgets = { slHpW, slHpH, colHpBg, ddHpShape }

  -- Remplissage (4 colonnes) ---------------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["UNITBARS_SEC_FILL"], W))
  local dirOpts = {}
  for _, d in ipairs(UB() and UB().FILL_DIRS or {}) do dirOpts[#dirOpts + 1] = { value = d, text = L["UNITBARS_FILL_" .. d] } end
  local ddBgTex = Bind(DD(L["SETTINGS_UB_BG_TEXTURE"], ns.GetBarTextureList(), 4), "bgTexture", "string")
  local ddFillTex = Bind(DD(L["SETTINGS_UB_FILL_TEXTURE"], ns.GetBarTextureList(), 4), "barTexture", "string")
  local ddDir = Bind(DD(L["UNITBARS_FILL_DIR"], dirOpts, 4), "fillDir", "string")
  Row(4, ddBgTex, ddFillTex, ddDir, false)

  -- Formes decoratives (4 colonnes) -------------------------------------------------------------------------------
  ctx:Spacer(6)
  ctx:Add(SW.CreateSectionHeader(container, L["UNITBARS_SEC_DOTS"], W))
  Row(4, Bind(CB(L["UNITBARS_SHOW_DOTS"], nil, 4), "showDots", "bool"), false, false, false)
  local shapeOpts = {}
  for _, s in ipairs(UB() and UB().DOT_SHAPES or {}) do shapeOpts[#shapeOpts + 1] = { value = s, text = L["UNITBARS_SHAPE_" .. s:upper()] } end
  local ddShape = Bind(DD(L["UNITBARS_DOT_SHAPE"], shapeOpts, 4), "dotShape", "string")
  local rowSide = Bind(AR(L["UNITBARS_DOT_SIDE"], {
    { k = "LEFT",  l = L["SETTINGS_ALIGN_LEFT"] },
    { k = "RIGHT", l = L["SETTINGS_ALIGN_RIGHT"] },
    { k = "BOTH",  l = L["UNITBARS_DOT_SIDE_BOTH"] },
  }, 4), "dotSide", "string")
  local slDotGap = Bind(SL(L["UNITBARS_DOT_GAP"], -20, 40, 1, 4), "dotGap", "number")
  Row(4, ddShape, rowSide, slDotGap, false)
  local slCount = Bind(SL(L["UNITBARS_DOT_COUNT"], 1, UB() and UB().DOT_MAX or 5, 1, 4), "dotCount", "number")
  local slDot = Bind(SL(L["UNITBARS_DOT_SIZE"], 2, 40, 1, 4), "dotSize", "number")
  local slDotR = Bind(SL(L["UNITBARS_DOT_GRADIENT"], 0, 100, 1, 4), "dotRatio", "number")
  local slDotSp = Bind(SL(L["UNITBARS_DOT_SPACING"], -5, 30, 1, 4), "dotSpacing", "number")
  Row(4, slCount, slDot, slDotR, slDotSp)
  local dotWidgets = { ddShape, rowSide, slDotGap, slCount, slDot, slDotR, slDotSp }

  ctx:Spacer()
  ctx:Finalize()

  -- Apercu : zones survolables -------------------------------------------------------------------------------------
  -- Une zone par element ; clic droit = ouvre (deplie) sa section et y fait defiler la page.
  local zones = {}
  local zDotsL, zDotsR
  local function OpenSection(labelKey)
    local panel = ns.SettingsPanel
    if panel and panel.OpenSection then panel:OpenSection("unitBars", L[labelKey]:upper(), true) end
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
    zones[labelKey] = z
    return z
  end
  if pf then
    -- Barre (remplissage), sous les autres zones
    local zBar = NewZone("UNITBARS_SEC_FILL", 20)
    zBar:SetPoint("TOPLEFT", pf.bgTex, "TOPLEFT", -2, 3)
    zBar:SetPoint("BOTTOMRIGHT", pf.bgTex, "BOTTOMRIGHT", 2, -3)
    local zName = NewZone("UNITBARS_SEC_NAME", 30)
    zName:SetPoint("TOPLEFT", pf.nameTxt, "TOPLEFT", -3, 2)
    zName:SetPoint("BOTTOMRIGHT", pf.nameTxt, "BOTTOMRIGHT", 3, -2)
    local zHp = NewZone("SETTINGS_SEC_HP_TEXT", 30)
    zHp:SetAllPoints(pf.textBG)
    -- Points : une zone par groupe (deux en "Les deux"), ancrees a chaque rafraichissement
    zDotsL = NewZone("UNITBARS_SEC_DOTS", 30)
    zDotsR = NewZone("UNITBARS_SEC_DOTS", 30)
  end
  -- Boite du nom, montree dans l'apercu pendant le reglage de sa largeur (masquee 1,5 s apres le dernier changement)
  if pf then
    local box = CreateFrame("Frame", nil, pf)
    box:SetFrameLevel(pf:GetFrameLevel() + 40)
    box:SetAllPoints(pf.nameTxt)
    local g = Theme.accentText
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
      local t = box:CreateTexture(nil, "OVERLAY")
      t:SetColorTexture(g[1], g[2], g[3], 0.9)
      t:SetPoint(e[1]); t:SetPoint(e[2])
      if e[3] then t:SetHeight(1) else t:SetWidth(1) end
    end
    local fill = box:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(g[1], g[2], g[3], 0.12)
    box:Hide()
    local gen = 0
    local orig = slNameBox.onChanged
    slNameBox.onChanged = function(v)
      orig(v)
      gen = gen + 1
      local my = gen
      box:Show()
      C_Timer.After(1.5, function() if gen == my then box:Hide() end end)
    end
  end

  -- Fond de l'apercu : clic droit = section Position et taille (sous la barre et ses zones)
  local bgClick = CreateFrame("Button", nil, preview)
  bgClick:SetAllPoints()
  bgClick:SetFrameLevel(preview:GetFrameLevel() + 1)
  bgClick:RegisterForClicks("RightButtonUp")
  bgClick:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    OpenSection("UNITBARS_SEC_POSITION")
  end)
  if pf then pf:SetFrameLevel(preview:GetFrameLevel() + 5) end

  RefreshPreview = function()
    local m = UB()
    if not (m and pf) then return end
    m.StylePreview(pf, Sel())
    -- Groupes de points : rang 1 = le plus eloigne de la barre. Gauche = indices 1..n, droite = les n suivants
    -- (ou 1..n si seul a droite).
    local n, side = pf._dotN or 0, BV("dotSide")
    local function Place(z, first, last)
      z:ClearAllPoints()
      local a, b = pf.dots[first], pf.dots[last]
      if n == 0 or not (a and b) then z:Hide(); return end
      z:SetPoint("LEFT", a, "LEFT", -2, 0)
      z:SetPoint("RIGHT", b, "RIGHT", 2, 0)
      z:SetHeight((pf._dotSizes[last] or pf._dotSizes[first] or 4) + 4)
      z:Show()
    end
    if side == "RIGHT" then
      Place(zDotsL, n, 1)
      zDotsR:Hide()
    else
      Place(zDotsL, 1, n)
      if side == "BOTH" then Place(zDotsR, 2 * n, n + 1) else zDotsR:Hide() end
    end
    -- Mise a l'echelle : la barre la plus grande possible dans l'encart (textes compris), sans depasser x2
    local pw = preview:GetWidth()
    if not pw or pw < 50 then pw = W end
    local need = pf:GetHeight() + 2 * math.max(BV("nameSize") or 14, BV("hpBoxH") or 17) + 16
    pf:SetScale(math.max(0.2, math.min(PREVIEW_MAX_SCALE, (pw - 60) / math.max(1, pf:GetWidth()), (PREVIEW_H - 20) / need)))
    pf:ClearAllPoints()
    pf:SetPoint("CENTER", preview, "CENTER", 0, 0)
  end

  -- Etats dependants : grises selon d'autres reglages
  RefreshStates = function()
    local key, off = Sel(), title._moduleOff
    local layout = BV("layout")
    local mirror = layout == "mirror"
    Gray(ddMirror, layout == "free", off)
    if ddMirror.label then ddMirror.label:SetText(layout == "parent" and L["UNITBARS_PARENT_OF"] or L["UNITBARS_MIRROR_OF"]) end
    Gray(slX, mirror, off)
    Gray(slY, mirror, off)
    -- Nom jamais affiche (case decochee, et pour le joueur "Toujours afficher" aussi) : reste de la section grise
    local player = key == "player"
    local nameOn = BV("showName") or (player and BV("nameAlways"))
    for _, w in ipairs(nameWidgets) do Gray(w, not nameOn, off) end
    -- "Toujours afficher le nom" : barre du joueur seulement, invisible (et inerte) ailleurs
    Gray(cbNameAlways, not player, true)
    cbNameAlways:SetAlpha(player and (off and GRAY or 1) or 0)
    local shadowOn = BV("nameShadow")
    Gray(slShadowA, not shadowOn, off)
    Gray(cbShadowFlip, not shadowOn, off)
    Gray(slShadowW, not shadowOn, off)
    Gray(slShadowH, not shadowOn, off)
    -- Texte de vie desactive : tout le reste grise ; cadre desactive : ses reglages grises
    local hpOn = BV("hpShow")
    for _, w in ipairs(hpWidgets) do Gray(w, not hpOn, off) end
    for _, w in ipairs(hpBoxWidgets) do Gray(w, not (hpOn and BV("hpBg")), off) end
    -- Formes decoratives desactivees : reglages grises
    for _, w in ipairs(dotWidgets) do Gray(w, not BV("showDots"), off) end
    Gray(slTank, not GV("useTankHeight"), off)
    Gray(colBar, GV("themedColors") ~= false, off)
    for _, w in ipairs(colReact) do Gray(w, GV("themedColors") == false, off) end
    -- Nom du joueur : au survol seulement (hors combat)
    cbName.label:SetText(key == "player" and L["UNITBARS_SHOW_NAME_HOVER"] or L["UNITBARS_SHOW_NAME"])
    cbName.tooltipText = key == "player" and L["SETTINGS_UB_PLAYER_NAME_HOVER_TT"] or nil
  end

  -- Valeurs X / Y suivies apres un glisser-deposer de la barre a l'ecran (UnitBars, OnDragStop)
  local function RefreshPos()
    local m = UB()
    if not m then return end
    local x, y
    if BV("layout") == "parent" and m.IsLinked(Sel()) then
      x, y = BV("relX") or 0, BV("relY") or 0
    else
      x, y = m.BarPos(Sel())
    end
    slX:SetValue(math.floor(x + 0.5))
    slY:SetValue(math.floor(y + 0.5))
    lockBtn._lbl:SetText(GV("locked") and L["UNITBARS_UNLOCK"] or L["UNITBARS_LOCK"])
    for k, t in pairs(prevToggles) do t:SetValue(DB()[k] ~= false) end
  end

  RefreshAll = function()
    local opts, mirrorOpts = {}, {}
    for _, k in ipairs(ORDER) do
      opts[#opts + 1] = { value = k, text = L[BAR_LABEL[k]] }
      if k ~= Sel() then mirrorOpts[#mirrorOpts + 1] = { value = k, text = L[BAR_LABEL[k]] } end
    end
    barDD:SetOptions(opts)
    barDD:SetValue(Sel())
    ddMirror:SetOptions(mirrorOpts)
    toggle:SetValue(BV("enabled") ~= false)
    cbModule:SetChecked(GV("enabled") ~= false)   -- a pu changer depuis la page Modules
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
          if e.invert then v = not v end
          e.w:SetChecked(v and true or false)
        elseif e.kind == "color" then
          if type(v) == "table" then e.w:SetColor(v[1], v[2], v[3], v[4]) end
        elseif v ~= nil then
          e.w:SetValue(v)
        end
      end
    end
    RefreshPos()   -- barre en symetrie : sa position calculee, pas celle enregistree
    if RefreshVis then RefreshVis() end
    RefreshStates()
    RefreshPreview()
  end

  preview:SetScript("OnSizeChanged", function() RefreshPreview() end)
  -- Clic droit sur une barre a l'ecran (UI/ModuleHoverOverlay.lua) : selection de cette barre
  ns.UnitBarsPageRefresh = function() if container:IsVisible() then RefreshAll() end end
  ns.UnitBarsPagePosChanged = function() if container:IsVisible() then RefreshPos(); RefreshPreview() end end

  container:HookScript("OnShow", function() RefreshAll() end)
  RefreshAll()
  if container:IsVisible() then PinUp() end
end

-- UI/CDMLayoutPage.lua : page "Gestionnaire de temps de recharge" du GUI (logique : Modules/CDMLayout.lua).
-- Liste des cooldowns que le Cooldown Manager connaît pour la spé active (sorts, trinkets, potions) :
-- suivi ou non, Essentiel ou Utilitaire (exclusif), ordre des Essentiels. Les changements vont dans le
-- profil ; "Appliquer" les écrit dans le CDM et recharge l'interface.
local addonName, ns = ...
local L     = ns.L
local SW    = ns.SharedWidgets
local Theme = ns.Theme

local ROW_H, SEC_H = 26, 24
local TC = 0.08

-- Table du thème mutée EN PLACE au changement de spé (SW.RefreshAccentTheme) : la lire au moment de
-- peindre, et repeindre ce qui a été peint avant (cf. PaintAccentButton, Refresh).
local function Gold() return Theme.accentText or Theme.gold or Theme.accent end

-- Bouton principal doré : la couleur passée à CreateActionBtn est une référence vivante au thème
-- (survol / sortie relisent les valeurs actuelles) ; liseré et libellé repeints ici.
local function NewAccentButton(parent, text, w)
  local b = SW.CreateActionBtn(parent, text, w, { 0.16, 0.13, 0.05, 1 }, Gold(), Gold())
  return b
end
local function PaintAccentButton(b)
  local g = Gold()
  b:SetBackdropBorderColor(g[1], g[2], g[3], 0.9)
  b._lbl:SetTextColor(g[1], g[2], g[3])
end

local function EntryDisplay(e)
  if e.equipSlot then
    local itemID = GetInventoryItemID("player", e.equipSlot)
    local name = itemID and C_Item.GetItemNameByID(itemID)
    local icon = itemID and C_Item.GetItemIconByID(itemID)
    return string.format(L["CDM_LAYOUT_TRINKET"], e.equipSlot, name or "?"), icon
  end
  local name = e.spellID and C_Spell.GetSpellName(e.spellID)
  local icon = e.spellID and C_Spell.GetSpellTexture(e.spellID)
  return name or ("#" .. tostring(e.cooldownID)), icon
end

-- Petit bouton à état (badge Essentiel / Utilitaire, flèches)
local function NewBadge(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, 18)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b.fs = b:CreateFontString(nil, "OVERLAY")
  b.fs:SetFont(ns.Media.fontGui, 9)
  b.fs:SetAllPoints()
  b.fs:SetText(text)
  function b:SetActive(on, enabled)
    local g = Gold()
    if on then
      self:SetBackdropColor(g[1], g[2], g[3], 0.9)
      self:SetBackdropBorderColor(g[1] * 0.6, g[2] * 0.6, g[3] * 0.4, 1)
      self.fs:SetTextColor(0.05, 0.05, 0.05)
    else
      self:SetBackdropColor(0.06, 0.06, 0.07, 1)
      self:SetBackdropBorderColor(unpack(Theme.border))
      self.fs:SetTextColor(unpack(Theme.textDim))
    end
    if enabled == false then self:Disable(); self:SetAlpha(0.3) else self:Enable(); self:SetAlpha(1) end
  end
  return b
end

-- Fenêtre "nom du build" : titre, explication, champ prérempli, [Créer] [autre action] [Annuler].
-- alt = { libellé, fonction } (optionnel, ex. "Modifier « X »"). Au-dessus du GUI (FULLSCREEN_DIALOG).
local askFrame
function ns.CDMLayoutAskName(title, hint, default, onOk, alt)
  if not askFrame then
    local f = CreateFrame("Frame", "AishCoreCDMBuildName", UIParent)
    f:SetSize(460, 170)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    SW.ApplyPanelBackground(f)
    tinsert(UISpecialFrames, "AishCoreCDMBuildName")

    local gold = Gold()
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(ns.Media.fontTitle or ns.Media.fontGui, 13)
    f.title:SetTextColor(gold[1], gold[2], gold[3], 1)
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetPoint("RIGHT", -16, 0)
    f.title:SetJustifyH("LEFT")

    f.hint = f:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont(ns.Media.fontGui, 10)
    f.hint:SetTextColor(unpack(Theme.textDim))
    f.hint:SetPoint("TOPLEFT", 16, -38)
    f.hint:SetPoint("RIGHT", -16, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetWordWrap(true)

    f.eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    SW.StyleEditBox(f.eb)
    f.eb:SetSize(300, 22)
    f.eb:SetPoint("TOPLEFT", 20, -78)
    f.eb:SetAutoFocus(false)
    f.eb:SetMaxLetters(40)

    f.ok = NewAccentButton(f, L["CDM_LAYOUT_CREATE_BTN"], 120)
    f.ok:SetPoint("BOTTOMLEFT", 16, 14)
    f.alt = SW.CreateActionBtn(f, "", 170)
    f.alt:SetPoint("LEFT", f.ok, "RIGHT", 8, 0)
    local cancel = SW.CreateActionBtn(f, L["SETTINGS_CANCEL"], 110)
    cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    cancel:SetScript("OnClick", function() f:Hide() end)

    local function Confirm()
      local name = (f.eb:GetText() or ""):match("^%s*(.-)%s*$")
      if name == "" then return end
      f:Hide()
      if f.onOk then f.onOk(name) end
    end
    f.ok:SetScript("OnClick", Confirm)
    f.eb:SetScript("OnEnterPressed", Confirm)
    f.eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.alt:SetScript("OnClick", function() f:Hide(); if f.altFn then f.altFn() end end)
    askFrame = f
  end
  local f = askFrame
  local gold = Gold()
  f.title:SetTextColor(gold[1], gold[2], gold[3], 1)
  PaintAccentButton(f.ok)
  f.title:SetText(title)
  f.hint:SetText(hint or "")
  f.eb:SetText(default or "")
  f.onOk = onOk
  f.altFn = alt and alt[2]
  f.alt:SetShown(alt ~= nil)
  if alt then f.alt._lbl:SetText(alt[1]) end
  f:Show()
  f:Raise()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

function ns.BuildCDMLayoutPage(p, cw)
  local CDM = ns.Modules and ns.Modules.CDMLayout
  local W = cw - 20

  local title = SW.MakeSectionTitle(SW.CreateSectionHeader(p, L["SETTINGS_CAT_CDM_LAYOUT"], W))
  title:SetPoint("TOPLEFT", 10, 0)

  local desc = p:CreateFontString(nil, "OVERLAY")
  desc:SetFont(ns.Media.fontGui, 10)
  desc:SetTextColor(unpack(Theme.textDim))
  desc:SetJustifyH("LEFT")
  desc:SetWordWrap(true)
  desc:SetWidth(W)
  desc:SetPoint("TOPLEFT", 10, -30)
  desc:SetText(L["CDM_LAYOUT_DESC"])

  local specLbl = p:CreateFontString(nil, "OVERLAY")
  specLbl:SetFont(ns.Media.fontGui, 12)
  specLbl:SetPoint("TOPLEFT", 10, -80)
  specLbl:SetWidth(150)
  specLbl:SetJustifyH("LEFT")
  -- Build actif de la spé (ou "Aucun" : CDM libre)
  local buildDD = SW.CreateDropdown(p, "", {}, 240)
  buildDD:SetPoint("TOPLEFT", 165, -76)
  local status = p:CreateFontString(nil, "OVERLAY")
  status:SetFont(ns.Media.fontGui, 11)
  status:SetPoint("LEFT", buildDD, "RIGHT", 12, 0)
  -- Survol du statut : détail des écarts entre le profil et le CDM
  local statusHit = CreateFrame("Frame", nil, p)
  statusHit:SetAllPoints(status)
  statusHit:EnableMouse(true)
  local CAT_NAME = { [0] = L["CDM_LAYOUT_SEC_NONE"], [1] = L["CDM_LAYOUT_SEC_ESSENTIAL"], [2] = L["CDM_LAYOUT_SEC_UTILITY"] }
  statusHit:SetScript("OnEnter", function(self)
    local specID = CDM and CDM.CurrentSpecID()
    if not (specID and CDM.GetSpecConfig(specID) and CDM.IsAvailable()) then return end
    local diffs, orderDiffers = CDM.Diff(specID)
    if #diffs == 0 and not orderDiffers then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(L["CDM_LAYOUT_DIFF_TITLE"], 1, 1, 1)
    for i, d in ipairs(diffs) do
      if i > 15 then GameTooltip:AddLine(string.format(L["CDM_LAYOUT_DIFF_MORE"], #diffs - 15), 0.6, 0.6, 0.6); break end
      local name = EntryDisplay(d.entry)
      GameTooltip:AddDoubleLine(name, string.format(L["CDM_LAYOUT_DIFF_LINE"], CAT_NAME[d.want], CAT_NAME[d.current]), 1, 1, 1, 1, 0.67, 0.2)
    end
    if orderDiffers then GameTooltip:AddLine(L["CDM_LAYOUT_DIFF_ORDER"], 1, 0.67, 0.2) end
    GameTooltip:Show()
  end)
  statusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local applyBtn = NewAccentButton(p, L["CDM_LAYOUT_APPLY_BTN"], 200)
  applyBtn:SetPoint("TOPLEFT", 10, -110)
  local saveAsBtn = SW.CreateActionBtn(p, L["CDM_LAYOUT_SAVEAS_BTN"], 260)
  saveAsBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
  local deleteBtn = SW.CreateActionBtn(p, L["CDM_LAYOUT_DELETE_BTN"], 170)
  deleteBtn:SetPoint("LEFT", saveAsBtn, "RIGHT", 8, 0)

  local cbUnknown = SW.CreateCheckbox(p, L["CDM_LAYOUT_SHOW_UNKNOWN"], nil, 300, 22)
  cbUnknown:SetPoint("TOPLEFT", 4, -142)

  local LIST_TOP = -172
  local list = CreateFrame("Frame", nil, p)
  list:SetPoint("TOPLEFT", 10, LIST_TOP)
  list:SetWidth(W)

  local rows, secs = {}, {}
  local Refresh

  -- Builds déjà autorisés à la modification directe pendant cette session ("spec:nom")
  local unlocked = {}

  -- Avant la 1re modification d'un build : proposer d'en créer un nouveau, pour garder l'original
  -- intact (on peut toujours y revenir). Le build "AishUI" n'est jamais modifié en place. Sans build
  -- actif, la modification crée un build depuis l'état actuel du CDM.
  local function EnsureEditable(fn)
    local specID = CDM.CurrentSpecID()
    local active = CDM.GetActiveName(specID)
    if active and active ~= CDM.DEFAULT and unlocked[specID .. ":" .. active] then return fn() end
    -- Build virtuel Défaut : rien à modifier en place, on crée un vrai build à partir d'ici.
    if active == CDM.DEFAULT then active = nil end
    -- Mode admin (/aishadmin) : mise au point du build AishUI livré avec le pack, modifié en place
    if active == CDM.OFFICIAL and ns.Auras and ns.Auras._adminMode then return fn() end
    local function Unlock(name) unlocked[specID .. ":" .. name] = true end
    if not active then
      ns.CDMLayoutAskName(L["CDM_LAYOUT_CREATE_TITLE"], L["CDM_LAYOUT_CREATE_HINT"], L["CDM_LAYOUT_DEFAULT_NAME"], function(name)
        if CDM.SaveCurrentAs(specID, name) then Unlock(name); fn() end
      end)
      return
    end
    local alt
    if active ~= CDM.OFFICIAL then
      alt = { string.format(L["CDM_LAYOUT_EDIT_DIRECT"], active), function() Unlock(active); fn() end }
    end
    ns.CDMLayoutAskName(string.format(L["CDM_LAYOUT_FORK_TITLE"], active), L["CDM_LAYOUT_FORK_HINT"],
      active == CDM.OFFICIAL and L["CDM_LAYOUT_DEFAULT_NAME"] or (active .. " 2"), function(name)
        if CDM.CopyBuild(specID, active, name) then Unlock(name); fn() end
      end, alt)
  end

  local function EditConf()
    return CDM.GetSpecConfig(CDM.CurrentSpecID())
  end

  local function SetCategory(cid, cat)
    EnsureEditable(function()
    local conf = EditConf()
    if not conf then return end
    conf.cats[cid] = cat
    if cat ~= CDM.ESSENTIAL then
      for i = #conf.order, 1, -1 do if conf.order[i] == cid then table.remove(conf.order, i) end end
    else
      local found = false
      for _, x in ipairs(conf.order) do if x == cid then found = true end end
      if not found then conf.order[#conf.order + 1] = cid end
    end
    Refresh()
    end)
  end

  -- La barre des Essentiels (CooldownManagerEnhanced) se remplit de droite à gauche quand "vers la
  -- droite" est décoché : la liste de la page est alors affichée à l'envers pour se lire comme la barre.
  local function EssentialsReversed()
    local cfg = ns.GetCfg("cdmEssential")
    return cfg and cfg.enabled and cfg.growRight ~= true
  end

  local function Move(cid, delta)
    if EssentialsReversed() then delta = -delta end
    EnsureEditable(function()
    local conf = EditConf()
    if not conf then return end
    local ordered = CDM.OrderedEssentials(conf, CDM.ListCooldowns())
    for i, x in ipairs(ordered) do
      if x == cid then
        local j = i + delta
        if ordered[j] then ordered[i], ordered[j] = ordered[j], ordered[i] end
        break
      end
    end
    conf.order = ordered
    Refresh()
    end)
  end

  local function GetRow(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, list)
    r:SetSize(W, ROW_H)
    r:EnableMouse(true)
    local hover = r:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:SetColorTexture(unpack(Theme.rowHover))
    hover:Hide()

    r.cb = SW.CreateCheckbox(r, "", nil, 26, ROW_H)
    r.cb:SetPoint("LEFT", -4, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 26, 0)
    r.icon:SetTexCoord(TC, 1 - TC, TC, 1 - TC)
    r.name = r:CreateFontString(nil, "OVERLAY")
    r.name:SetFont(ns.Media.fontGui, 11)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -230, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.down = NewBadge(r, "v", 20)
    r.down:SetPoint("RIGHT", -2, 0)
    r.up = NewBadge(r, "^", 20)
    r.up:SetPoint("RIGHT", r.down, "LEFT", -3, 0)
    r.util = NewBadge(r, L["CDM_LAYOUT_UTILITY"], 80)
    r.util:SetPoint("RIGHT", r.up, "LEFT", -8, 0)
    r.ess = NewBadge(r, L["CDM_LAYOUT_ESSENTIAL"], 80)
    r.ess:SetPoint("RIGHT", r.util, "LEFT", -3, 0)

    r.cb.onChanged = function(on)
      SetCategory(r.entry.cooldownID, on and CDM.UTILITY or nil)
    end
    r.ess:SetScript("OnClick", function() SetCategory(r.entry.cooldownID, CDM.ESSENTIAL) end)
    r.util:SetScript("OnClick", function() SetCategory(r.entry.cooldownID, CDM.UTILITY) end)
    r.up:SetScript("OnClick", function() Move(r.entry.cooldownID, -1) end)
    r.down:SetScript("OnClick", function() Move(r.entry.cooldownID, 1) end)
    r:SetScript("OnEnter", function(self)
      hover:Show()
      local e = self.entry
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      if e.equipSlot then GameTooltip:SetInventoryItem("player", e.equipSlot)
      elseif e.spellID then GameTooltip:SetSpellByID(e.spellID) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() hover:Hide(); GameTooltip:Hide() end)
    rows[i] = r
    return r
  end

  local function GetSection(i)
    local s = secs[i]
    if s then return s end
    s = list:CreateFontString(nil, "OVERLAY")
    s:SetFont(ns.Media.fontTitle or ns.Media.fontGui, 11)
    local gold = Gold()
    s:SetTextColor(gold[1], gold[2], gold[3], 1)
    s:SetJustifyH("LEFT")
    s.line = list:CreateTexture(nil, "ARTWORK")
    s.line:SetColorTexture(unpack(Theme.separator))
    s.line:SetHeight(1)
    secs[i] = s
    return s
  end

  local function ByName(a, b) return (a._name or "") < (b._name or "") end

  Refresh = function()
    PaintAccentButton(applyBtn)
    for _, r in ipairs(rows) do r:Hide() end
    for _, s in ipairs(secs) do s:Hide(); s.line:Hide() end

    local specIdx = GetSpecialization and GetSpecialization()
    local specID, specName
    if specIdx then specID, specName = GetSpecializationInfo(specIdx) end
    specLbl:SetText(string.format(L["CDM_LAYOUT_SPEC"], specName or "?"))
    specLbl:SetTextColor(unpack(Theme.textNormal))

    if not (CDM and specID and CDM.IsAvailable()) then
      status:SetText("|cffff5555" .. L["CDM_LAYOUT_ERR_UNAVAILABLE"] .. "|r")
      -- Le CDM finit souvent de basculer sa disposition quelques secondes après un changement de spé
      if not p.__cdmRetry then
        p.__cdmRetry = true
        C_Timer.After(2, function() p.__cdmRetry = nil; if p:IsVisible() then Refresh() end end)
      end
      applyBtn:Disable(); applyBtn:SetAlpha(0.4)
      list:SetHeight(1)
      p:SetHeight(-LIST_TOP + 20)
      return
    end

    -- Menu des builds de la spé : "AishUI" en doré, puis les builds perso, puis "Aucun"
    local opts, gold = {}, Gold()
    local goldHex = string.format("|cff%02x%02x%02x", gold[1] * 255, gold[2] * 255, gold[3] * 255)
    for _, name in ipairs(CDM.ListBuilds(specID)) do
      local label = CDM.BuildLabel(name)
      opts[#opts + 1] = { value = name, text = (name == CDM.OFFICIAL) and (goldHex .. label .. "|r") or label }
    end
    opts[#opts + 1] = { value = "", text = L["CDM_LAYOUT_NONE"] }
    buildDD:SetOptions(opts)
    local activeName = CDM.GetActiveName(specID)
    buildDD:SetValue(activeName or "")
    -- Le build virtuel Défaut ne se supprime pas : il n'est stocké nulle part.
    if activeName and activeName ~= CDM.DEFAULT then deleteBtn:Enable(); deleteBtn:SetAlpha(1)
    else deleteBtn:Disable(); deleteBtn:SetAlpha(0.4) end

    local entries = CDM.ListCooldowns()
    local conf = CDM.GetSpecConfig(specID)
    -- Sans config : on affiche l'état actuel du CDM (la 1re modification le capture)
    local view = conf or { cats = {}, order = {} }
    if not conf then
      for _, e in ipairs(entries) do
        if e.current ~= 0 then view.cats[e.cooldownID] = e.current end
        if e.current == CDM.ESSENTIAL then view.order[#view.order + 1] = e.cooldownID end
      end
      status:SetText("|cff999999" .. L["CDM_LAYOUT_STATUS_NONE"] .. "|r")
    else
      local st = CDM.Status(specID)
      if st == "applied" then
        status:SetText("|cff55dd55" .. L["CDM_LAYOUT_STATUS_APPLIED"] .. "|r")
      elseif st == "same" then
        status:SetText("|cffffaa33" .. L["CDM_LAYOUT_STATUS_SAME"] .. "|r")
      else
        status:SetText("|cffffaa33" .. L["CDM_LAYOUT_STATUS_PENDING"] .. "|r")
      end
    end
    local canApply = conf ~= nil
    if canApply then applyBtn:Enable(); applyBtn:SetAlpha(1) else applyBtn:Disable(); applyBtn:SetAlpha(0.4) end

    local byID, ess, util, none = {}, {}, {}, {}
    local showUnknown = cbUnknown:GetChecked()
    for _, e in ipairs(entries) do
      e._name, e._icon = EntryDisplay(e)
      byID[e.cooldownID] = e
      local cat = view.cats[e.cooldownID]
      if e.isKnown or showUnknown or cat then
        if cat == CDM.UTILITY then util[#util + 1] = e
        elseif cat ~= CDM.ESSENTIAL then none[#none + 1] = e end
      end
    end
    for _, cid in ipairs(CDM.OrderedEssentials(view, entries)) do
      local e = byID[cid]
      if e then ess[#ess + 1] = e end
    end
    if EssentialsReversed() then
      for i = 1, math.floor(#ess / 2) do ess[i], ess[#ess + 1 - i] = ess[#ess + 1 - i], ess[i] end
    end
    table.sort(util, ByName)
    table.sort(none, ByName)

    local y, ri, si = 0, 0, 0
    local groups = {
      { L["CDM_LAYOUT_SEC_ESSENTIAL"], ess, CDM.ESSENTIAL },
      { L["CDM_LAYOUT_SEC_UTILITY"], util, CDM.UTILITY },
      { L["CDM_LAYOUT_SEC_NONE"], none, nil },
    }
    for _, grp in ipairs(groups) do
      si = si + 1
      local s = GetSection(si)
      s:ClearAllPoints()
      s:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y - 4)
      s:SetText(string.format("%s (%d)", grp[1], #grp[2]))
      s:SetTextColor(gold[1], gold[2], gold[3], 1)
      s:Show()
      s.line:ClearAllPoints()
      s.line:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y - SEC_H + 2)
      s.line:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y - SEC_H + 2)
      s.line:Show()
      y = y + SEC_H + 2
      for idx, e in ipairs(grp[2]) do
        ri = ri + 1
        local r = GetRow(ri)
        r.entry = e
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
        r.icon:SetTexture(e._icon or 134400)
        r.name:SetText(e._name)
        r.name:SetTextColor(unpack(e.isKnown and Theme.textNormal or Theme.textDisabled))
        local tracked = grp[3] ~= nil
        r.cb:SetChecked(tracked)
        r.ess:SetActive(grp[3] == CDM.ESSENTIAL, tracked)
        r.util:SetActive(grp[3] == CDM.UTILITY, tracked)
        local isEss = grp[3] == CDM.ESSENTIAL
        r.up:SetShown(isEss); r.down:SetShown(isEss)
        if isEss then
          r.up:SetActive(false, idx > 1)
          r.down:SetActive(false, idx < #grp[2])
        end
        r:Show()
        y = y + ROW_H
      end
      y = y + 8
    end
    list:SetHeight(math.max(1, y))
    p:SetHeight(-LIST_TOP + y + 20)
  end

  applyBtn:SetScript("OnClick", function()
    local specID = CDM.CurrentSpecID()
    CDM.ClearSkip(specID)
    local ok, err, noReload = CDM.Apply(specID)
    if not ok then print("|cffff4444[AishCore]|r " .. tostring(err)) end
    -- Contenu déjà identique : rien d'écrit, pas de rechargement, seul le statut change
    if noReload then Refresh() end
  end)
  saveAsBtn:SetScript("OnClick", function()
    local specID = CDM.CurrentSpecID()
    ns.CDMLayoutAskName(L["CDM_LAYOUT_SAVEAS_TITLE"], L["CDM_LAYOUT_SAVEAS_HINT"],
      (function(a) return (a and a ~= CDM.DEFAULT) and a or L["CDM_LAYOUT_DEFAULT_NAME"] end)(CDM.GetActiveName(specID)),
      function(name)
        if CDM.SaveCurrentAs(specID, name) then unlocked[specID .. ":" .. name] = true end
        Refresh()
      end)
  end)
  -- Destructif : second clic de confirmation dans les 3 s
  deleteBtn:SetScript("OnClick", function(self)
    if not self.armed then
      self.armed = true
      self._lbl:SetText(L["CDM_LAYOUT_DELETE_CONFIRM"])
      C_Timer.After(3, function() self.armed = nil; self._lbl:SetText(L["CDM_LAYOUT_DELETE_BTN"]) end)
      return
    end
    self.armed = nil
    self._lbl:SetText(L["CDM_LAYOUT_DELETE_BTN"])
    local specID = CDM.CurrentSpecID()
    CDM.DeleteBuild(specID, CDM.GetActiveName(specID))
    Refresh()
  end)
  buildDD.onChanged = function(v)
    CDM.SetActive(CDM.CurrentSpecID(), v ~= "" and v or nil)
    Refresh()
  end
  cbUnknown.onChanged = function() Refresh() end

  -- Laisse le CDM reconstruire ses données pour la nouvelle spé avant de relire
  ns.CallbackRegistry:Register("SPEC_CHANGED", function()
    C_Timer.After(3, function() if p:IsVisible() then Refresh() end end)
  end)
  p:HookScript("OnShow", function() Refresh() end)
  Refresh()
end

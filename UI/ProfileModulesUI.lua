-- UI/ProfileModulesUI.lua : fenêtres d'export / import / copie / réinitialisation par élément de profil
-- (arbre : Config/ProfileModules.lua, logique : Config/Profiles.lua). Même disposition que la page
-- "Modules" : sections > éléments > sous-éléments, sur 3 colonnes. Fichier à part pour ne pas alourdir
-- le chunk principal de UI/SettingsPanel.lua (limite des 200 locales).
local addonName, ns = ...
local L  = ns.L
local SW = ns.SharedWidgets
local Theme = ns.Theme

local ROW_H, HEADER_H = 20, 22
local INDENT, BASE_INDENT, TRUNK_X0 = 14, 14, 6
local COL_GAP = 14
-- Colonnes de l'arbre (ids de sections), équilibrées en hauteur
local TREE_COLUMNS = { { "unitFrames", "global" }, { "combat", "hud" }, { "aurasProcs", "animations" } }

local function Gold() return Theme.accentText or Theme.gold or Theme.accent end

-- Fenêtre ---------------------------------------------------------------------------------------
local function NewPopup(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  -- Au-dessus du panneau d'options (strate DIALOG)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  SW.ApplyPanelBackground(f)
  tinsert(UISpecialFrames, name) -- Échap ferme la fenêtre

  local gold = Gold()
  local t = f:CreateFontString(nil, "OVERLAY")
  t:SetFont(ns.Media.fontTitle or ns.Media.fontGui, 13)
  t:SetTextColor(gold[1], gold[2], gold[3], 1)
  t:SetText(title)
  t:SetPoint("TOPLEFT", 16, -14)

  local line = f:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(unpack(Theme.separator))
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 12, -36)
  line:SetPoint("TOPRIGHT", -12, -36)

  local close = SW.CreateCloseButton(f, 20)
  close:SetPoint("TOPRIGHT", -8, -8)
  return f
end

local function NewLabel(parent, size, color)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Media.fontGui, size or 10)
  local c = color or Theme.textDim
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetJustifyH("LEFT")
  return fs
end

-- Bouton principal (or) ou secondaire (sombre)
local function NewButton(parent, text, w, primary)
  local g = Gold()
  if primary then
    return SW.CreateActionBtn(parent, text, w, { 0.16, 0.13, 0.05, 1 }, { g[1], g[2], g[3], 0.9 }, { g[1], g[2], g[3] })
  end
  return SW.CreateActionBtn(parent, text, w)
end

local function SetButtonEnabled(btn, on)
  if on then btn:Enable(); btn:SetAlpha(1) else btn:Disable(); btn:SetAlpha(0.4) end
end

-- Zone de texte multiligne (export en lecture, import en saisie) : fond sombre + liseré, défilement
-- à la molette (pas de barre Blizzard).
local function NewTextBox(parent)
  local area = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  area:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  area:SetBackdropColor(0.02, 0.02, 0.025, 0.95)
  area:SetBackdropBorderColor(unpack(Theme.border))

  local sf = CreateFrame("ScrollFrame", nil, area)
  sf:SetPoint("TOPLEFT", 4, -4)
  sf:SetPoint("BOTTOMRIGHT", -4, 4)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 30))
    self:SetVerticalScroll(v)
  end)

  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  eb:SetFont(ns.Media.fontGui, 9, "")
  eb:SetTextInsets(2, 2, 2, 2)
  eb:SetTextColor(0.85, 0.85, 0.85)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sf:SetScrollChild(eb)
  sf:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(w) end)
  area:EnableMouse(true)
  area:SetScript("OnMouseDown", function() eb:SetFocus() end)
  area.eb = eb
  return area
end

-- Arbre de sélection ----------------------------------------------------------------------------
local function DrawLine(parent, x, y, w, h)
  local tex = parent:CreateTexture(nil, "BACKGROUND")
  tex:SetColorTexture(unpack(Theme.separator))
  tex:SetSize(math.max(1, w), math.max(1, h))
  tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
end

-- Enfants disponibles sur ce client (cf. ns.IsModuleAvailable)
local function AvailableChildren(node)
  local out = {}
  for _, c in ipairs(node.children or {}) do
    if ns.IsModuleAvailable(c.id) then out[#out + 1] = c end
  end
  return out
end

-- Nœuds porteurs de données d'un sous-arbre (le nœud compris)
local function DataNodes(node, out)
  out = out or {}
  if not ns.IsModuleAvailable(node.id) then return out end
  if ns.IsProfileDataNode(node) then out[#out + 1] = node end
  for _, c in ipairs(node.children or {}) do DataNodes(c, out) end
  return out
end

-- Coche visuelle : 1 = coché, 0.5 = partiel, 0 = vide
local function PaintRow(row, state)
  local g = Theme.checkboxOn
  if state == 0 then
    row.box:SetColorTexture(unpack(Theme.checkboxOff))
    row.check:Hide()
  else
    row.box:SetColorTexture(g[1], g[2], g[3], state == 1 and 1 or 0.45)
    row.check:Show()
    row.check:SetAlpha(state == 1 and 1 or 0.35)
  end
end

-- tree.selected[id] = true pour les nœuds porteurs de données cochés. tree.available[id] = false grise
-- un élément (import : absent de la chaîne). tree.onChanged() après chaque clic.
local function NewTree(parent, width)
  local tree = CreateFrame("Frame", nil, parent)
  tree.selected, tree.available, tree.rows = {}, {}, {}
  local idx = ns.GetProfileTreeIndex()
  local colW = math.floor((width - 2 * COL_GAP) / 3)

  local function IsAvailable(n) return tree.available[n.id] ~= false end

  function tree:Refresh()
    for _, row in ipairs(self.rows) do
      local nodes, on, total = DataNodes(row.node), 0, 0
      for _, n in ipairs(nodes) do
        if IsAvailable(n) then
          total = total + 1
          if self.selected[n.id] then on = on + 1 end
        end
      end
      PaintRow(row, (total > 0 and on == total) and 1 or (on > 0 and 0.5 or 0))
      if total > 0 then row:Enable(); row:SetAlpha(1) else row:Disable(); row:SetAlpha(0.35) end
    end
  end

  function tree:SetAll(on)
    for _, n in ipairs(idx.order) do
      if ns.IsProfileDataNode(n) then self.selected[n.id] = (on and IsAvailable(n)) or nil end
    end
    self:Refresh()
  end

  function tree:GetSelected()
    local ids = {}
    for _, n in ipairs(idx.order) do
      if self.selected[n.id] and IsAvailable(n) then ids[#ids + 1] = n.id end
    end
    return ids
  end

  -- Clic : coche tout le sous-arbre s'il n'était pas entièrement coché, sinon le décoche
  local function OnRowClick(row)
    local nodes, all = DataNodes(row.node), true
    for _, n in ipairs(nodes) do
      if IsAvailable(n) and not tree.selected[n.id] then all = false; break end
    end
    for _, n in ipairs(nodes) do
      if IsAvailable(n) then tree.selected[n.id] = (not all) or nil end
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    tree:Refresh()
    if tree.onChanged then tree.onChanged() end
  end

  local function MakeRow(node, x, y, indent, header)
    local row = SW.CreateCheckbox(tree, L[node.label] or node.id, nil, colW, header and HEADER_H or ROW_H)
    row:SetPoint("TOPLEFT", tree, "TOPLEFT", x, -y)
    if indent > 0 then
      row.box:ClearAllPoints()
      row.box:SetPoint("LEFT", row, "LEFT", 8 + indent, 0)
    end
    if header then
      local gold = Gold()
      row.label:SetFont(ns.Media.fontTitle or ns.Media.fontGui, 11)
      row.label:SetTextColor(gold[1], gold[2], gold[3], 1)
      row:SetScript("OnLeave", function(self) self.label:SetTextColor(gold[1], gold[2], gold[3], 1) end)
      local hair = row:CreateTexture(nil, "ARTWORK")
      hair:SetHeight(1)
      hair:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, -2)
      hair:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
      hair:SetColorTexture(unpack(Theme.separator))
    end
    row.node = node
    row:SetScript("OnClick", OnRowClick)
    tree.rows[#tree.rows + 1] = row
    return row
  end

  -- Même organigramme que la page "Modules" : tronc vertical par section + petits traits
  local maxH = 0
  for c, sectionIds in ipairs(TREE_COLUMNS) do
    local x, y = (c - 1) * (colW + COL_GAP), 0
    for _, sid in ipairs(sectionIds) do
      local section = idx.byId[sid]
      if section then
        MakeRow(section, x, y, 0, true)
        y = y + HEADER_H + 3
        local top, tickW = {}, 8 + BASE_INDENT - TRUNK_X0
        local headerBottom = y
        for _, child in ipairs(AvailableChildren(section)) do
          MakeRow(child, x, y, BASE_INDENT, false)
          local entry = { y = y + ROW_H / 2, kids = {} }
          top[#top + 1] = entry
          y = y + ROW_H + 1
          for _, sub in ipairs(AvailableChildren(child)) do
            MakeRow(sub, x, y, BASE_INDENT + INDENT, false)
            entry.kids[#entry.kids + 1] = y + ROW_H / 2
            y = y + ROW_H + 1
          end
        end
        if #top > 0 then
          DrawLine(tree, x + TRUNK_X0, headerBottom, 1, top[#top].y - headerBottom)
          for _, r in ipairs(top) do
            DrawLine(tree, x + TRUNK_X0, r.y, tickW, 1)
            if #r.kids > 0 then
              local x1 = x + TRUNK_X0 + INDENT
              DrawLine(tree, x1, r.y, 1, r.kids[#r.kids] - r.y)
              for _, ky in ipairs(r.kids) do DrawLine(tree, x1, ky, tickW, 1) end
            end
          end
        end
        y = y + 10
      end
    end
    if y > maxH then maxH = y end
  end
  tree:SetSize(width, maxH)
  return tree
end

-- Grise les éléments sans donnée dans le profil source
local function SetSourceAvailability(tree, profileName)
  local avail = ns.Profiles.ProfileItemAvailability(profileName or "")
  for _, id in ipairs(ns.Profiles.AllItemIds()) do tree.available[id] = avail[id] == true end
end

local function ProfileOptions(exclude)
  local opts = {}
  for _, n in ipairs(ns.Profiles.List()) do
    if n ~= exclude then opts[#opts + 1] = { value = n, text = n } end
  end
  return opts
end

local function Report(ok, err, target)
  if ok then
    print(string.format(L["PROFILE_MODULES_DONE"], "|cffffd700" .. tostring(target) .. "|r"))
  else
    print(string.format(L["SETTINGS_PROFILE_ERROR_MSG_LABELED"], tostring(err)))
  end
end

-- Boutons "Tout cocher / Tout décocher" alignés à droite du titre
local function AddSelectAllButtons(f, tree)
  local none = NewButton(f, L["PROFILE_MODULES_NONE_BTN"], 110)
  none:SetHeight(20)
  none:SetPoint("TOPRIGHT", -36, -10)
  none:SetScript("OnClick", function() tree:SetAll(false); if tree.onChanged then tree.onChanged() end end)
  local all = NewButton(f, L["PROFILE_MODULES_ALL"], 110)
  all:SetHeight(20)
  all:SetPoint("RIGHT", none, "LEFT", -6, 0)
  all:SetScript("OnClick", function() tree:SetAll(true); if tree.onChanged then tree.onChanged() end end)
end

local W = 700

-- Export -----------------------------------------------------------------------------------------
local exportFrame
function ns.ShowModuleExportPopup(profileName)
  local P = ns.Profiles
  if not exportFrame then
    local f = NewPopup("AishCoreModuleExportPopup", W, 100, L["PROFILE_MODULES_EXPORT_TITLE"])
    local tree = NewTree(f, W - 32)
    tree:SetPoint("TOPLEFT", 16, -48)
    f.tree = tree
    AddSelectAllButtons(f, tree)

    f.box = NewTextBox(f)
    f.box:SetPoint("TOPLEFT", tree, "BOTTOMLEFT", 0, -8)
    f.box:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.box:SetHeight(84)
    f.box.eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    f.size = NewLabel(f, 10)
    f.size:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", 2, -10)

    local done = NewButton(f, L["SETTINGS_CLOSE"], 130)
    done:SetPoint("TOPRIGHT", f.box, "BOTTOMRIGHT", 0, -6)
    done:SetScript("OnClick", function() f:Hide() end)

    -- Sérialisation + compression : quelques centaines de ms sur un gros profil. Régénérée une seule
    -- fois quand les clics s'arrêtent, pas à chaque case.
    local token = 0
    local function Generate()
      local ids = tree:GetSelected()
      local str = (#ids > 0) and P.ExportItems(f.profileName, ids) or ""
      f.box.eb:SetText(str or "")
      f.box.eb:HighlightText()
      f.size:SetText(string.format(L["PROFILE_MODULES_SIZE"], BreakUpLargeNumbers(#(str or ""))))
    end
    tree.onChanged = function()
      token = token + 1
      local mine = token
      f.box.eb:SetText("")
      f.size:SetText(L["PROFILE_MODULES_GENERATING"])
      C_Timer.After(0.35, function() if mine == token and f:IsShown() then Generate() end end)
    end
    f.Generate = Generate
    f:SetHeight(48 + tree:GetHeight() + 8 + 84 + 44)
    exportFrame = f
  end
  local f = exportFrame
  f.profileName = profileName or P.GetActive()
  SetSourceAvailability(f.tree, f.profileName)
  f.tree:SetAll(true)
  f:Show()
  f:Raise()
  f.Generate()
  f.box.eb:SetFocus()
end

-- Import -----------------------------------------------------------------------------------------
local importFrame
function ns.ShowModuleImportPopup()
  local P = ns.Profiles
  if not importFrame then
    local f = NewPopup("AishCoreModuleImportPopup", W, 100, L["PROFILE_MODULES_IMPORT_TITLE"])

    local pasteLbl = NewLabel(f, 10)
    pasteLbl:SetText(L["SETTINGS_PASTE_PROFILE_STRING"])
    pasteLbl:SetPoint("TOPLEFT", 18, -46)

    f.box = NewTextBox(f)
    f.box:SetPoint("TOPLEFT", 16, -62)
    f.box:SetPoint("TOPRIGHT", -16, -62)
    f.box:SetHeight(64)

    local analyze = NewButton(f, L["PROFILE_MODULES_ANALYZE"], 140, true)
    analyze:SetPoint("TOPLEFT", f.box, "BOTTOMLEFT", 0, -8)

    f.info = NewLabel(f, 10, Theme.textNormal)
    f.info:SetPoint("LEFT", analyze, "RIGHT", 10, 0)
    f.info:SetPoint("RIGHT", f, "RIGHT", -18, 0)

    local tree = NewTree(f, W - 32)
    tree:SetPoint("TOPLEFT", analyze, "BOTTOMLEFT", 0, -12)
    f.tree = tree
    AddSelectAllButtons(f, tree)

    local targetY = -(62 + 64 + 8 + 24 + 12 + tree:GetHeight() + 6)
    f.newRadio = SW.CreateCheckbox(f, L["PROFILE_MODULES_TARGET_NEW"], nil, 200, 22)
    f.newRadio:SetPoint("TOPLEFT", 16, targetY)
    f.existRadio = SW.CreateCheckbox(f, L["PROFILE_MODULES_TARGET_EXISTING"], nil, 200, 22)
    f.existRadio:SetPoint("TOPLEFT", 16 + W / 2, targetY)

    f.nameEB = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    SW.StyleEditBox(f.nameEB)
    f.nameEB:SetSize(280, 22)
    f.nameEB:SetPoint("TOPLEFT", 26, targetY - 28)
    f.nameEB:SetAutoFocus(false)
    f.nameEB:SetMaxLetters(48)
    f.nameEB:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f.targetDD = SW.CreateDropdown(f, "", {}, 280)
    f.targetDD:SetPoint("TOPLEFT", 26 + W / 2 - 10, targetY - 28)

    f.warn = NewLabel(f, 10, { 1, 0.6, 0.2 })
    f.warn:SetPoint("TOPLEFT", 18, targetY - 60)
    f.warn:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.warn:SetWordWrap(true)

    f.importBtn = NewButton(f, L["SETTINGS_IMPORT"], 160, true)
    f.importBtn:SetPoint("BOTTOMLEFT", 16, 14)
    local cancel = NewButton(f, L["SETTINGS_CANCEL"], 130)
    cancel:SetPoint("BOTTOMRIGHT", -16, 14)
    cancel:SetScript("OnClick", function() f:Hide() end)

    local function Refresh()
      local hasPayload = f.payload ~= nil
      local warn = {}
      if hasPayload and P.IsPayloadNewer(f.payload) then
        warn[#warn + 1] = string.format(L["PROFILE_MODULES_NEWER_WARN"], tostring(f.payload.addon))
      end
      local target = f.modeExisting and f.targetDD:GetValue()
      if hasPayload and target and #tree:GetSelected() > 0 then
        warn[#warn + 1] = string.format(L["PROFILE_MODULES_OVERWRITE_WARN"], target)
      end
      f.warn:SetText(table.concat(warn, "\n"))
      f.nameEB:SetShown(not f.modeExisting)
      f.targetDD:SetShown(f.modeExisting)
      f.newRadio:SetChecked(not f.modeExisting)
      f.existRadio:SetChecked(f.modeExisting)
      SetButtonEnabled(f.importBtn, hasPayload and #tree:GetSelected() > 0)
    end
    f.Refresh = Refresh
    tree.onChanged = Refresh
    f.newRadio.onChanged = function() f.modeExisting = false; Refresh() end
    f.existRadio.onChanged = function() f.modeExisting = true; Refresh() end
    f.targetDD.onChanged = Refresh

    analyze:SetScript("OnClick", function()
      local payload, err = P.DecodeExport(f.box.eb:GetText() or "")
      f.payload = payload
      if not payload then
        f.info:SetText("|cffff5555" .. tostring(err) .. "|r")
      elseif payload.addon then
        f.info:SetText(string.format(L["PROFILE_MODULES_SOURCE_INFO"], tostring(payload.addon), tostring(payload.date or "?")))
      else
        f.info:SetText("")
      end
      wipe(tree.available)
      local items = payload and payload.items or {}
      for _, id in ipairs(P.AllItemIds()) do tree.available[id] = items[id] == true end
      tree:SetAll(true)
      Refresh()
    end)

    f.importBtn:SetScript("OnClick", function()
      local ids = tree:GetSelected()
      if #ids == 0 then print(L["PROFILE_MODULES_NONE"]); return end
      local ok, err, target
      if f.modeExisting then
        target = f.targetDD:GetValue()
        ok, err = P.ApplyItems(f.payload, target, ids)
      else
        target = (f.nameEB:GetText() or ""):match("^%s*(.-)%s*$")
        ok, err = P.Import(f.box.eb:GetText() or "", target, ids)
        if ok then P.SetActive(target) end
      end
      Report(ok, err, target)
      if ok then f:Hide() end
    end)

    f:SetHeight(-targetY + 60 + 34 + 48)
    importFrame = f
  end
  local f = importFrame
  f.payload, f.modeExisting = nil, false
  f.box.eb:SetText("")
  f.info:SetText("")
  f.nameEB:SetText("")
  f.targetDD:SetOptions(ProfileOptions())
  f.targetDD:SetValue(P.GetActive())
  -- Rien d'importable tant que la chaîne n'est pas analysée
  for _, id in ipairs(P.AllItemIds()) do f.tree.available[id] = false end
  f.tree:SetAll(false)
  f:Show()
  f:Raise()
  f.Refresh()
  f.box.eb:SetFocus()
end

-- Copie / réinitialisation -----------------------------------------------------------------------
local copyFrame
function ns.ShowModuleCopyPopup()
  local P = ns.Profiles
  if not copyFrame then
    local f = NewPopup("AishCoreModuleCopyPopup", W, 100, L["PROFILE_MODULES_COPY_TITLE"])

    f.target = NewLabel(f, 10, Theme.textNormal)
    f.target:SetPoint("TOPLEFT", 18, -48)

    f.sourceDD = SW.CreateDropdown(f, L["PROFILE_MODULES_COPY_FROM"], {}, 280)
    f.sourceDD:SetPoint("TOPLEFT", 16, -66)

    local tree = NewTree(f, W - 32)
    f.sourceDD.onChanged = function(v) SetSourceAvailability(tree, v); tree:SetAll(false) end
    tree:SetPoint("TOPLEFT", 16, -118)
    f.tree = tree
    AddSelectAllButtons(f, tree)

    local copyBtn = NewButton(f, L["PROFILE_MODULES_COPY_BTN"], 230, true)
    copyBtn:SetPoint("BOTTOMLEFT", 16, 14)
    copyBtn:SetScript("OnClick", function()
      local ids = tree:GetSelected()
      if #ids == 0 then print(L["PROFILE_MODULES_NONE"]); return end
      local active = P.GetActive()
      local ok, err = P.CopyItems(f.sourceDD:GetValue(), active, ids)
      Report(ok, err, active)
      if ok then f:Hide() end
    end)

    -- Destructif : second clic de confirmation dans les 3 s
    local resetBtn = NewButton(f, L["PROFILE_MODULES_RESET_BTN"], 230)
    resetBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    resetBtn:SetScript("OnClick", function(self)
      local ids = tree:GetSelected()
      if #ids == 0 then print(L["PROFILE_MODULES_NONE"]); return end
      if not self.armed then
        self.armed = true
        self._lbl:SetText(L["PROFILE_MODULES_RESET_CONFIRM"])
        C_Timer.After(3, function()
          self.armed = nil
          self._lbl:SetText(L["PROFILE_MODULES_RESET_BTN"])
        end)
        return
      end
      self.armed = nil
      self._lbl:SetText(L["PROFILE_MODULES_RESET_BTN"])
      local active = P.GetActive()
      local ok, err = P.ResetItems(active, ids)
      Report(ok, err, active)
      if ok then f:Hide() end
    end)

    f:SetHeight(118 + tree:GetHeight() + 50)
    copyFrame = f
  end
  local f, active = copyFrame, P.GetActive()
  f.target:SetText(string.format(L["PROFILE_MODULES_COPY_TARGET"], "|cffffd700" .. active .. "|r"))
  local opts = ProfileOptions(active)
  f.sourceDD:SetOptions(opts)
  f.sourceDD:SetValue(opts[1] and opts[1].value or "")
  SetSourceAvailability(f.tree, f.sourceDD:GetValue())
  f.tree:SetAll(false)
  f:Show()
  f:Raise()
end

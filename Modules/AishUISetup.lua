-- Modules/AishUISetup.lua : configuration automatique du pack AishUI au premier login
-- (versions avec kfe2pr_tmtc uniquement, cf. ns.HasHeroicFeatures).
-- EllesmereUI : chaque module est un addon séparé, son état vit dans les AddOns.txt du client (pas dans
-- les SavedVariables copiées par l'installeur). Appliqué une fois par compte Battle.net : le hash du
-- BattleTag stocké dans AishaddonDB est celui d'Aishuu dans le pack, il diffère donc chez l'utilisateur.
-- Platynator / ElvUI (profil privé) : profils par personnage, appliqués au premier login de chaque perso.
local addonName, ns = ...
local L = ns.L

-- Modules gardés actifs ; tout autre enfant de la suite est désactivé (y compris les futurs modules).
local KEEP = {
  EllesmereUIActionBars   = true,
  EllesmereUIUnitFrames   = true,
  EllesmereUIResourceBars = true,
  EllesmereUIRaidFrames   = true,
  EllesmereUIQoL          = true,
  EllesmereUIDataBars     = true,
  EllesmereUIBlizzardSkin = true,
  EllesmereUIMinimap      = true,
  -- Forever : modules actifs dans la config d'Aishuu sur ce client (absents en Retail)
  EllesmereUIQuickdraw         = true,
  EllesmereUIForeverEssentials = true,
}

-- Parent et enfants LoadOnDemand indispensables : jamais touchés.
local SKIP = {
  EllesmereUI        = true,
  EllesmereUIOptions = true,
  EllesmereUILocales = true,
}

-- djb2 : évite de diffuser le BattleTag en clair dans le pack.
local function Hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return string.format("%08x", h)
end

local FONT = "Fonts\\2002.TTF"
local GOLD = { 0.78, 0.62, 0.30 }

-- Popups au thème du GUI. Strate TOOLTIP : passe au-dessus des popups d'Ellesmere (FULLSCREEN_DIALOG),
-- et le voile plein écran bloque les clics sur celles-ci tant que la nôtre est ouverte.
-- buttons = { { text, primary, onClick }, ... } (1 à 3, centrés). Une popup par `name`, construite
-- une seule fois.
local popups = {}
local function ShowSetupPopup(name, titleText, msgText, buttons)
  local popup = popups[name]
  -- Déjà construite : seul le texte peut changer (ex. nom du build dans la popup du CDM)
  if popup then popup.msg:SetText(msgText); popup:Show(); return popup end
  local T = ns.Theme or {}

  popup = CreateFrame("Frame", name, UIParent)
  popups[name] = popup
  popup:SetFrameStrata("TOOLTIP")
  popup:SetAllPoints(UIParent)
  popup:EnableMouse(true)
  local dim = popup:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints()
  dim:SetColorTexture(0, 0, 0, 0.65)
  -- Échap = Plus tard. Pas d'UISpecialFrames : le CloseAllWindows() lancé par Blizzard à l'affichage
  -- de l'UI au login (12.1, UI.TopLevelParentShown) refermerait la popup aussitôt.
  popup:EnableKeyboard(true)
  popup:SetScript("OnKeyDown", function(self, key)
    local esc = key == "ESCAPE"
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not esc) end
    if esc then self:Hide() end
  end)

  local W, H = 560, 260
  local box = CreateFrame("Frame", nil, popup)
  box:SetSize(W, H)
  box:SetPoint("CENTER", 0, 40)
  box:SetFrameLevel(popup:GetFrameLevel() + 5)
  if ns.SharedWidgets and ns.SharedWidgets.ApplyPanelBackground then
    ns.SharedWidgets.ApplyPanelBackground(box)
  else
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.03, 0.035, 0.97)
  end
  -- Liseré or en haut du panneau
  local line = box:CreateTexture(nil, "OVERLAY")
  line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
  line:SetPoint("TOPLEFT", 1, -1)
  line:SetPoint("TOPRIGHT", -1, -1)
  line:SetHeight(2)

  -- Logo AishUI centré, à cheval sur le bord supérieur (fond teinté derrière, comme le header du GUI)
  local logo = CreateFrame("Frame", nil, box)
  logo:SetSize(96, 96)
  logo:SetPoint("CENTER", box, "TOP", 0, 0)
  logo:SetFrameLevel(box:GetFrameLevel() + 5)
  local logoBg = logo:CreateTexture(nil, "ARTWORK", nil, -1)
  logoBg:SetAllPoints()
  logoBg:SetTexture(ns.GetBrandLogoBgPath and ns.GetBrandLogoBgPath() or "Interface\\AddOns\\AishCore\\Media\\Logo\\aishui_hollow_bg")
  local c = ns.GetBrandLogoBgColor and ns.GetBrandLogoBgColor() or { 1, 1, 1, 1 }
  logoBg:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  local logoTex = logo:CreateTexture(nil, "ARTWORK")
  logoTex:SetAllPoints()
  logoTex:SetTexture("Interface\\AddOns\\AishCore\\Media\\Logo\\aishui_hollow")

  local title = box:CreateFontString(nil, "OVERLAY")
  title:SetFont(FONT, 18, "")
  title:SetPoint("TOP", 0, -58)
  local at = T.accentText or GOLD
  title:SetTextColor(at[1], at[2], at[3])
  title:SetText(titleText)

  local msg = box:CreateFontString(nil, "OVERLAY")
  msg:SetFont(FONT, 13, "")
  msg:SetPoint("TOP", title, "BOTTOM", 0, -14)
  msg:SetWidth(W - 60)
  msg:SetJustifyH("CENTER")
  msg:SetSpacing(3)
  local tn = T.textNormal or { 0.92, 0.92, 0.93 }
  msg:SetTextColor(tn[1], tn[2], tn[3])
  msg:SetText(msgText)
  popup.msg = msg

  local function MakeBtn(text, primary, w)
    local b = CreateFrame("Button", nil, box, "BackdropTemplate")
    b:SetSize(w, 32)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    local bgc = primary and { 0.16, 0.12, 0.05 } or { 0.08, 0.08, 0.09 }
    local edge = primary and GOLD or (T.border or { 0.18, 0.18, 0.195 })
    b:SetBackdropColor(bgc[1], bgc[2], bgc[3], 1)
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 13, "")
    fs:SetAllPoints()
    if primary then fs:SetTextColor(at[1], at[2], at[3]) else fs:SetTextColor(tn[1], tn[2], tn[3]) end
    fs:SetText(text)
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(bgc[1] + 0.06, bgc[2] + 0.06, bgc[3] + 0.06, 1) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(bgc[1], bgc[2], bgc[3], 1) end)
    return b
  end

  local n, gap = #buttons, 12
  local bw = n >= 3 and 160 or 180
  local x0 = -((n * bw + (n - 1) * gap) / 2)
  for i, def in ipairs(buttons) do
    local b = MakeBtn(def[1], def[2], bw)
    b:SetPoint("BOTTOMLEFT", box, "BOTTOM", x0 + (i - 1) * (bw + gap), 24)
    b:SetScript("OnClick", function() popup:Hide(); def[3]() end)
  end

  popup:Show()
  return popup
end

-- Réutilisée par le Gestionnaire de temps de recharge (Modules/CDMLayout.lua)
ns.ShowSetupPopup = ShowSetupPopup

local function ShowReloadPopup()
  ShowSetupPopup("AishCoreEllesmereSetup", L["ELLESMERE_SETUP_TITLE"], L["ELLESMERE_SETUP_PROMPT"], {
    { L["ELLESMERE_SETUP_RELOAD"], true, ReloadUI },
    { L["CDM_RELOAD_LATER"], false, function() end },
  })
end

-- Modules EllesmereUI (niveau compte). Renvoie true si un reload est nécessaire.
local function SetupEllesmere()
  if not (C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("EllesmereUI")) then return end
  if not BNGetInfo then return end
  local _, battleTag = BNGetInfo()
  if not battleTag or battleTag == "" then return end  -- Battle.net hors ligne : retenté au prochain login

  local id = Hash(battleTag)
  if AishaddonDB._ellesmereSetup == id then return end

  local needReload = false
  for i = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(i)
    if name and name:find("^EllesmereUI") and not SKIP[name] then
      local keep = KEEP[name] and true or false
      -- Sans nom de perso : s'applique à tous les personnages du compte
      if keep then C_AddOns.EnableAddOn(name) else C_AddOns.DisableAddOn(name) end
      if keep ~= (C_AddOns.IsAddOnLoaded(name) and true or false) then needReload = true end
    end
  end

  AishaddonDB._ellesmereSetup = id
  return needReload
end

-- Profils par personnage : une seule fois par perso (AishUISetupCharDB), pour laisser
-- l'utilisateur changer de profil ensuite. Écriture brute, prise en compte au reload.
local PLATYNATOR_PROFILE = "AishUI"
local PLATYNATOR_STYLE = "AishUI - DPS"
local ELVUI_PRIVATE_PROFILE = "AishUI - Private"

local function SetupPlatynator(done)
  if done.platynator or not C_AddOns.IsAddOnLoaded("Platynator") then return end
  local profiles = PLATYNATOR_CONFIG and PLATYNATOR_CONFIG.Profiles
  local prof = profiles and profiles[PLATYNATOR_PROFILE]
  if not prof then return end
  done.platynator = true
  local changed = false
  -- Style du profil (partagé par le compte) : seulement si le design existe
  if prof.designs and prof.designs[PLATYNATOR_STYLE] and prof.style ~= PLATYNATOR_STYLE then
    prof.style = PLATYNATOR_STYLE
    changed = true
  end
  if PLATYNATOR_CURRENT_PROFILE ~= PLATYNATOR_PROFILE then
    PLATYNATOR_CURRENT_PROFILE = PLATYNATOR_PROFILE
    changed = true
  end
  return changed
end

local function SetupElvUIPrivate(done)
  if done.elvuiPrivate or not C_AddOns.IsAddOnLoaded("ElvUI") then return end
  local db = ElvPrivateDB
  if not (db and db.profiles and db.profiles[ELVUI_PRIVATE_PROFILE]) then return end
  done.elvuiPrivate = true
  -- Clé de perso AceDB
  local charKey = UnitName("player") .. " - " .. GetRealmName()
  db.profileKeys = db.profileKeys or {}
  if db.profileKeys[charKey] == ELVUI_PRIVATE_PROFILE then return end
  db.profileKeys[charKey] = ELVUI_PRIVATE_PROFILE
  return true
end

-- Mode Édition Blizzard. Les dispositions vivent côté serveur (pas dans WTF) : la disposition est
-- capturée en chaîne dans AishaddonDB chez Aishuu (voyage avec le pack), puis importée en type Compte
-- chez l'utilisateur et activée au premier login de chaque perso. Même méthode que
-- EllesmereUI.ApplyPresetEditMode (pas d'EditModeManagerFrame:ImportLayout, cassé avant 1re ouverture).
local EDITMODE_LAYOUT = "AishUI"

local function EditModeReady()
  return C_EditMode and C_EditMode.GetLayouts and C_EditMode.ConvertStringToLayoutInfo
    and C_EditMode.ConvertLayoutInfoToString and C_EditMode.SaveLayouts and C_EditMode.SetActiveLayout
    and EditModeManagerFrame and EditModeManagerFrame.accountSettings
    and EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts
end

local function FindSavedLayout(info)
  for i, l in ipairs(info.layouts) do
    if l.layoutName == EDITMODE_LAYOUT then return i, l end
  end
end

-- Garde la chaîne à jour (login + logout) ; ne l'efface jamais si la disposition est absente.
local function CaptureEditMode()
  if not (AishaddonDB and EditModeReady()) then return end
  local info = C_EditMode.GetLayouts()
  if not (info and info.layouts) then return end
  local _, layout = FindSavedLayout(info)
  if not layout then return end
  local str = C_EditMode.ConvertLayoutInfoToString(layout)
  if type(str) == "string" and str ~= "" then AishaddonDB._editModeLayout = str end
end

local function SetupEditMode(done)
  if done.editMode or InCombatLockdown() or not EditModeReady() then return end
  local info = C_EditMode.GetLayouts()
  if not (info and info.layouts) then return end
  local mgr = EditModeManagerFrame
  local layouts = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
  local presetCount = #layouts

  local idx = FindSavedLayout(info)
  if idx then
    -- Disposition déjà présente sur le compte : simple activation sur ce perso
    done.editMode = true
    if info.activeLayout == presetCount + idx then return end
    C_EditMode.SetActiveLayout(presetCount + idx)
    return true
  end

  local str = AishaddonDB._editModeLayout
  if type(str) ~= "string" or str == "" then return end
  local imported = C_EditMode.ConvertStringToLayoutInfo(str)
  if not imported then return end
  imported.layoutType = Enum.EditModeLayoutType.Account
  imported.layoutName = EDITMODE_LAYOUT
  -- Complète les réglages ajoutés par les versions du client plus récentes que la chaîne
  if mgr.ReconcileWithModern then
    mgr:ReconcileWithModern(imported)
    for _, l in ipairs(info.layouts) do mgr:ReconcileWithModern(l) end
  end

  -- Index combinés : presets Blizzard, puis dispositions Compte, puis Personnage
  for _, l in ipairs(info.layouts) do layouts[#layouts + 1] = l end
  local slot = #layouts + 1
  for i = presetCount + 1, #layouts do
    if layouts[i].layoutType == Enum.EditModeLayoutType.Character then slot = i; break end
  end
  table.insert(layouts, slot, imported)

  info.layouts = layouts
  info.activeLayout = slot
  C_EditMode.SaveLayouts(info)
  C_EditMode.SetActiveLayout(slot)
  done.editMode = true
  return true
end

local function Apply()
  if not (C_AddOns and AishaddonDB) then return end
  -- Version AishUI uniquement : la version gratuite n'embarque pas les profils des autres addons
  if not (ns.HasHeroicFeatures and ns.HasHeroicFeatures()) then return end

  AishUISetupCharDB = AishUISetupCharDB or {}
  local done = AishUISetupCharDB

  local r1 = SetupEllesmere()
  local r2 = SetupPlatynator(done)
  local r3 = SetupElvUIPrivate(done)
  if r1 or r2 or r3 then ShowReloadPopup() end
end

local function SafeRun(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then print("|cffff4444[AishCore]|r AishUISetup : " .. tostring(err)) end
end

-- Étape mode Édition : capture puis import/activation (version AishUI uniquement)
local function ApplyEditMode()
  if not (AishaddonDB and ns.HasHeroicFeatures and ns.HasHeroicFeatures()) then return end
  CaptureEditMode()
  AishUISetupCharDB = AishUISetupCharDB or {}
  if SetupEditMode(AishUISetupCharDB) then ShowReloadPopup() end
end

-- PLAYER_LOGIN : BNGetInfo est renseigné, les SV des autres addons sont chargées, et on passe
-- avant les popups d'Ellesmere (conflits à +2 s).
-- EDIT_MODE_LAYOUTS_UPDATED : dispositions reçues du serveur ; différé d'une frame pour laisser
-- EditModeManagerFrame traiter l'event avant nous (accountSettings).
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    SafeRun(Apply)
  elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
    self:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    C_Timer.After(0, function() SafeRun(ApplyEditMode) end)
  elseif event == "PLAYER_LOGOUT" then
    if AishaddonDB and ns.HasHeroicFeatures and ns.HasHeroicFeatures() then
      pcall(CaptureEditMode)
    end
  end
end)

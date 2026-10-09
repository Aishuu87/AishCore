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
--
-- Plusieurs popups peuvent être demandées au même login (setup AishUI + Gestionnaire de temps de
-- recharge sur une spé jamais configurée) : les superposer rendrait les deux illisibles. Une seule
-- est jamais affichée à la fois ; les suivantes attendent en file et s'affichent au fur et à mesure
-- que les précédentes se ferment (reload, bouton ou Échap).
local popups = {}
local activeName
local queue = {}
local DisplaySetupPopup -- déclarée ici, définie plus bas (ProcessQueue la referme avant)

local function ProcessQueue()
  if activeName then return end
  local item = table.remove(queue, 1)
  if item then DisplaySetupPopup(item.name, item.title, item.msg, item.buttons) end
end

function DisplaySetupPopup(name, titleText, msgText, buttons)
  activeName = name
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
  -- Libère la place pour la prochaine popup en file, quelle que soit la façon dont celle-ci
  -- se ferme (bouton, Échap, ou :Hide() direct).
  popup:HookScript("OnHide", function()
    if activeName == name then activeName = nil end
    ProcessQueue()
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
    -- Texte du bouton : ancrage et justification explicites (le SetAllPoints() seul laissait le
    -- texte invisible sur Forever), couche au-dessus du fond, et repli si la police est refusee.
    b:SetFrameLevel(box:GetFrameLevel() + 10)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetDrawLayer("OVERLAY", 7)
    if not pcall(fs.SetFont, fs, FONT, 13, "") then fs:SetFont("Fonts\\FRIZQT__.TTF", 13, "") end
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetWidth(w - 8)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    if primary then fs:SetTextColor(at[1], at[2], at[3]) else fs:SetTextColor(tn[1], tn[2], tn[3]) end
    fs:SetText(text or "")
    b.label = fs
    -- Relu a l'affichage : certains clients perdent le texte pose avant le 1er Show()
    b:SetScript("OnShow", function(self) self.label:SetText(text or "") end)
    if (text or "") ~= "" and fs:GetStringWidth() == 0 then
      print("|cff33aaffAishCore|r texte de bouton vide : '" .. tostring(text) .. "' (police " .. tostring(FONT) .. ")")
    end
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
    -- L'action D'ABORD, Hide() après : un clic sur "Recharger" doit appeler ReloadUI() en tout
    -- premier, sans rien exécuter entre le clic et l'appel protégé. Hide() déclenche OnHide, qui
    -- peut à son tour afficher la popup suivante de la file (ProcessQueue) -- toute la création de
    -- frame que ça entraîne, intercalée avant ReloadUI(), suffit à faire échouer l'appel protégé
    -- sur certains clients (Forever : ADDON_ACTION_BLOCKED sur Reload()).
    b:SetScript("OnClick", function() def[3](); popup:Hide() end)
  end

  popup:Show()
  return popup
end

-- Point d'entrée public : affiche tout de suite si rien d'autre n'est à l'écran, sinon met en
-- file (remplace une entrée en attente du même nom plutôt que d'en empiler deux).
local function ShowSetupPopup(name, titleText, msgText, buttons)
  if activeName and activeName ~= name then
    for i, q in ipairs(queue) do
      if q.name == name then
        queue[i] = { name = name, title = titleText, msg = msgText, buttons = buttons }
        return
      end
    end
    queue[#queue + 1] = { name = name, title = titleText, msg = msgText, buttons = buttons }
    return
  end
  return DisplaySetupPopup(name, titleText, msgText, buttons)
end

-- Réutilisée par le Gestionnaire de temps de recharge (Modules/CDMLayout.lua)
ns.ShowSetupPopup = ShowSetupPopup

-- ReloadUI() refusé une 1re fois (ADDON_ACTION_BLOCKED) à cause de l'ordre Hide()/action, corrigé
-- plus bas (DisplaySetupPopup : l'action tourne avant Hide()). Après ce fix, plus aucune erreur de
-- blocage constatée -- le souci suivant (modules pas désactivés) était un bug séparé côté
-- SetupEllesmere, déjà réglé. Donc ReloadUI(), identique à Retail : à retester.
local function ShowReloadPopup()
  ShowSetupPopup("AishCoreEllesmereSetup", L["ELLESMERE_SETUP_TITLE"], L["ELLESMERE_SETUP_PROMPT"], {
    { L["ELLESMERE_SETUP_RELOAD"], true, ReloadUI },
    { L["CDM_RELOAD_LATER"], false, function() end },
  })
end

-- Active/desactive les addons EllesmereUI* selon KEEP. Renvoie true si au moins un a change d'etat
-- (donc reload necessaire).
local function ApplyEllesmereStates()
  local matched, needReload = 0, false
  for i = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(i)
    if name and name:find("^EllesmereUI") and not SKIP[name] then
      matched = matched + 1
      local keep = KEEP[name] and true or false
      local loaded = C_AddOns.IsAddOnLoaded(name) and true or false
      if keep ~= loaded then
        needReload = true
        -- Sans nom de perso. pcall : un appel refuse par ce client ne doit jamais interrompre la
        -- suite de Apply() (Platynator, profil prive ElvUI) -- vecu avec une variante a deux
        -- arguments retiree depuis.
        pcall(keep and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn, name)
      end
    end
  end
  if matched == 0 then
    print("|cffff4444[AishCore]|r SetupEllesmere : aucun addon EllesmereUI* trouvé par GetAddOnInfo (rien à activer/désactiver).")
  end
  return needReload
end

-- Modules EllesmereUI. Renvoie true si un reload est nécessaire.
-- L'etat des addons vit dans l'AddOns.txt de CHAQUE personnage : un verrou par compte ne suffit donc
-- pas, un perso fraichement cree gardait les modules actives (et seul /aishsetup, qui efface le
-- verrou, les corrigeait). Trois cas :
--   1) Compte jamais configure (ou /aishsetup) : on applique, et on note le compte + ce perso.
--   2) Compte deja verrouille mais perso NEUF (AishUISetupCharDB encore vide : premier login de ce
--      perso avec l'addon) : on applique pour ce perso. Les persos deja connus de l'addon ne sont
--      jamais retouches par ce chemin.
--   3) Perso traite au login precedent : une seule verification apres le reload (la 1re ecriture
--      de l'etat d'un perso neuf n'est pas toujours prise en compte), puis plus jamais -- l'utilisateur
--      reste libre de reactiver un module a la main.
local function SetupEllesmere(done, freshChar)
  if not (C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("EllesmereUI")) then return end
  -- ElvUI chargé ce perso = l'utilisateur est sur ce flavor-là (choix de l'installeur ou manuel) :
  -- ne jamais réactiver EllesmereUI par-dessus, même si EllesmereUI est resté sur le disque et que
  -- _ellesmereSetup a été remis à zéro par une réinstallation (AishaddonDB réécrite avec le pack).
  if C_AddOns.IsAddOnLoaded("ElvUI") then return end
  if not BNGetInfo then return end
  local _, battleTag = BNGetInfo()
  if not battleTag or battleTag == "" then return end  -- Battle.net hors ligne : retenté au prochain login

  local id = Hash(battleTag)
  local accountLocked = AishaddonDB._ellesmereSetup == id

  if done.ellesmere then
    -- Cas 3 : verification unique apres le reload
    if done.ellesmereVerified then return end
    done.ellesmereVerified = true
    return ApplyEllesmereStates()
  end

  -- Cas 1 / 2 : le verrou se pose AVANT la correction (une correction qui échoue ne doit jamais
  -- retenter indéfiniment -- bug vécu).
  if accountLocked and not freshChar then return end
  done.ellesmere = true
  AishaddonDB._ellesmereSetup = id
  return ApplyEllesmereStates()
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
  -- Perso neuf = aucune de ces etapes encore posee (editMode ignore : son evenement peut passer avant
  -- PLAYER_LOGIN). SetupEllesmere tourne en premier, avant que Platynator/ElvUI posent leur cle.
  local freshChar = not (done.platynator or done.elvuiPrivate or done.ellesmere)

  -- Chaque étape dans son propre pcall : une erreur dans l'une (ex. SetupEllesmere sur un client
  -- qui refuse un appel) ne doit plus jamais empêcher les suivantes de tourner -- vécu avec
  -- Platynator et le profil privé ElvUI restés sans effet à cause d'une erreur plus haut.
  local function Try(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
      print("|cffff4444[AishCore]|r AishUISetup : " .. tostring(result))
      return false
    end
    return result
  end

  local r1 = Try(SetupEllesmere, done, freshChar)
  local r2 = Try(SetupPlatynator, done)
  local r3 = Try(SetupElvUIPrivate, done)
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

-- ── /aishuiswitch : bascule ce personnage entre ElvUI et EllesmereUI ─────────────────────────────────
-- Les deux familles ne tournent jamais ensemble (cf. l'installeur) : on active celle qui est absente et on
-- coupe l'autre, puis reload. Cote EllesmereUI on retombe sur la meme liste de modules que le setup auto
-- (KEEP/SKIP). L'etat des addons est PAR PERSONNAGE : seule la session courante est concernee.
local function UiFlavorOf(name)
  if name:find("^ElvUI") then return "ElvUI" end
  if name:find("^EllesmereUI") then return "Ellesmere" end
  return nil
end

local function SwitchUiFlavor(target)
  for i = 1, C_AddOns.GetNumAddOns() do
    local name = C_AddOns.GetAddOnInfo(i)
    local flavor = name and UiFlavorOf(name)
    if flavor then
      local enable
      if flavor ~= target then
        enable = false
      elseif flavor == "Ellesmere" then
        enable = (KEEP[name] or SKIP[name]) and true or false   -- meme liste que le setup auto
      elseif name == "ElvUI_SLE" then
        enable = nil   -- Shadow & Light : jamais active par la commande (on ne touche pas a son etat)
      else
        enable = true
      end
      if enable ~= nil then pcall(enable and C_AddOns.EnableAddOn or C_AddOns.DisableAddOn, name) end
    end
  end
  -- Le setup auto des modules EllesmereUI est deja fait pour ce perso : pas de repassage au prochain login
  if target == "Ellesmere" then
    AishUISetupCharDB = AishUISetupCharDB or {}
    AishUISetupCharDB.ellesmere = true
    AishUISetupCharDB.ellesmereVerified = true
  end
end

SLASH_AISHUISWITCH1 = "/aishuiswitch"
SlashCmdList["AISHUISWITCH"] = function()
  local P = "|cff00ccff[AishCore]|r "
  if InCombatLockdown() then print(P .. L["UISWITCH_COMBAT"]); return end
  local hasElv = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("ElvUI")
  local hasEui = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("EllesmereUI")
  local current = C_AddOns.IsAddOnLoaded("ElvUI") and "ElvUI"
    or (C_AddOns.IsAddOnLoaded("EllesmereUI") and "Ellesmere") or nil
  local target = (current == "ElvUI") and "Ellesmere" or "ElvUI"
  if (target == "ElvUI" and not hasElv) or (target == "Ellesmere" and not hasEui) then
    print(P .. string.format(L["UISWITCH_MISSING"], target == "ElvUI" and "ElvUI" or "EllesmereUI"))
    return
  end
  local function Label(f) return f == "ElvUI" and "ElvUI" or "EllesmereUI" end
  local msg = current
    and string.format(L["UISWITCH_PROMPT"], Label(current), Label(target))
    or string.format(L["UISWITCH_PROMPT_NONE"], Label(target))
  ShowSetupPopup("AishCoreUiSwitch", L["UISWITCH_TITLE"], msg, {
    { L["UISWITCH_CONFIRM"], true, function() SwitchUiFlavor(target); ReloadUI() end },
    { L["UISWITCH_CANCEL"], false, function() end },
  })
end

-- Commande slash dédiée : AishCore.lua charge APRÈS ce fichier (section "# Init" en fin de .toc)
-- et écrase SlashCmdList["AISHCORE"] sans jamais chaîner vers un handler précédent -- un sous-
-- commande "setup" greffée sur /aishcore serait donc silencieusement perdue. Commande à part,
-- comme /aishspec ou /aishdebug ailleurs dans l'addon.
-- Relance le setup auto (modules EllesmereUI, profils Platynator et ElvUI privé, mode Édition)
-- sans attendre un nouveau login. Utile si le popup n'a pas été proposé la première fois, ou pour
-- revalider manuellement l'état d'un compte. Le changement d'état des addons EllesmereUI ne prend
-- effet qu'au reload/relog suivant, comme d'habitude -- cette commande relance seulement la
-- détection + la correction, pas le reload.
SLASH_AISHSETUP1 = "/aishsetup"
SlashCmdList["AISHSETUP"] = function()
  AishaddonDB = AishaddonDB or {}
  AishaddonDB._ellesmereSetup = nil
  AishUISetupCharDB = AishUISetupCharDB or {}
  AishUISetupCharDB.ellesmere = nil
  AishUISetupCharDB.ellesmereVerified = nil
  AishUISetupCharDB.platynator = nil
  AishUISetupCharDB.elvuiPrivate = nil
  AishUISetupCharDB.editMode = nil
  print("|cff00ccff[AishCore]|r Setup relancé.")
  SafeRun(Apply)
  SafeRun(ApplyEditMode)
end

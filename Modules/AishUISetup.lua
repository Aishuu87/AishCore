-- Modules/AishUISetup.lua : configuration automatique du pack AishUI au premier login
-- (versions avec kfe2pr_tmtc uniquement, cf. ns.HasHeroicFeatures).
-- EllesmereUI : chaque module est un addon séparé, son état vit dans les AddOns.txt du client (pas dans
-- les SavedVariables copiées par l'installeur). Appliqué une fois par compte Battle.net : le hash du
-- BattleTag stocké dans AishaddonDB est celui d'Aishuu dans le pack, il diffère donc chez l'utilisateur.
-- Platynator / ElvUI (profil privé) : profils par personnage, appliqués au premier login de chaque perso.
local addonName, ns = ...
local L = ns.L

-- Modules gardés actifs ; tout autre enfant de la suite est désactivé (y compris les futurs modules).
-- KEEP + SKIP sont dupliquées dans l'installeur (EllesmereKeep, InstallService.cs) : les garder synchronisées.
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

local FONT = ns.FONT_FALLBACK
local GOLD = { 0.78, 0.62, 0.30 }

-- Popups au thème du GUI. Strate TOOLTIP : passe au-dessus des popups d'Ellesmere (FULLSCREEN_DIALOG),
-- et le voile plein écran bloque les clics sur celles-ci tant que la nôtre est ouverte.
-- buttons = { { text, primary, onClick }, ... } (1 à 3, centrés), avec en option buttons.width /
-- buttons.height (libellés longs sur deux lignes), buttons.bottom (marge basse) et buttons.back
-- (lien « < Retour » en bas à gauche). Une popup par `name`, construite une seule fois.
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
  -- Déjà construite : texte et actions des boutons repris de la nouvelle demande. Les actions capturent
  -- leur contexte (ex. spé du CDM) : garder celles de la 1re construction faisait que « Ne plus demander »
  -- enregistrait la spé de la 1re popup de la session, et la popup revenait pour la spé courante.
  if popup then
    popup.msg:SetText(msgText)
    popup.defs = buttons
    for i, b in ipairs(popup.btns or {}) do
      local def = buttons[i]
      if def then b._text = def[1]; b:SetLabel(def[1]); b:Show() else b:Hide() end
    end
    popup:Show()
    return popup
  end
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
  -- OnHide est aussi declenche quand UIParent se cache (cinematique de premiere connexion, capture d'ecran) :
  -- la popup reste alors "shown" (IsShown vrai, IsVisible faux) et reapparait avec l'interface. La liberer ici
  -- affichait la suivante par-dessus, d'ou deux popups superposees apres la cinematique.
  popup:HookScript("OnHide", function(self)
    if self:IsShown() then return end
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
    b:SetSize(w, buttons.height or 32)
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
    b.label = fs
    -- 2e ligne éventuelle ("Titre\n(précision)") : 2 tailles en dessous, gris moyen
    local sub = b:CreateFontString(nil, "OVERLAY")
    sub:SetDrawLayer("OVERLAY", 7)
    if not pcall(sub.SetFont, sub, FONT, 11, "") then sub:SetFont("Fonts\\FRIZQT__.TTF", 11, "") end
    sub:SetPoint("TOP", fs, "BOTTOM", 0, -2)
    sub:SetWidth(w - 8)
    sub:SetJustifyH("CENTER")
    sub:SetTextColor(0.55, 0.55, 0.57)
    function b:SetLabel(t)
      local main, rest = (t or ""):match("^([^\n]*)\n(.*)$")
      fs:ClearAllPoints()
      if main then
        fs:SetPoint("CENTER", self, "CENTER", 0, 7)
        fs:SetText(main); sub:SetText(rest); sub:Show()
      else
        fs:SetPoint("CENTER", self, "CENTER", 0, 0)
        fs:SetText(t or ""); sub:Hide()
      end
    end
    b:SetLabel(text)
    -- Relu a l'affichage : certains clients perdent le texte pose avant le 1er Show()
    b._text = text
    b:SetScript("OnShow", function(self) self:SetLabel(self._text) end)
    if (text or "") ~= "" and fs:GetStringWidth() == 0 then
      print("|cff33aaffAishCore|r texte de bouton vide : '" .. tostring(text) .. "' (police " .. tostring(FONT) .. ")")
    end
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(bgc[1] + 0.06, bgc[2] + 0.06, bgc[3] + 0.06, 1) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(bgc[1], bgc[2], bgc[3], 1) end)
    return b
  end

  local n, gap = #buttons, 12
  local bw = buttons.width or (n >= 3 and 160 or 180)
  local x0 = -((n * bw + (n - 1) * gap) / 2)
  popup.defs, popup.btns = buttons, {}
  for i, def in ipairs(buttons) do
    local b = MakeBtn(def[1], def[2], bw)
    popup.btns[i] = b
    b:SetPoint("BOTTOMLEFT", box, "BOTTOM", x0 + (i - 1) * (bw + gap), buttons.bottom or 24)
    -- L'action D'ABORD, Hide() après : un clic sur "Recharger" doit appeler ReloadUI() en tout
    -- premier, sans rien exécuter entre le clic et l'appel protégé. Hide() déclenche OnHide, qui
    -- peut à son tour afficher la popup suivante de la file (ProcessQueue) -- toute la création de
    -- frame que ça entraîne, intercalée avant ReloadUI(), suffit à faire échouer l'appel protégé
    -- sur certains clients (Forever : ADDON_ACTION_BLOCKED sur Reload()).
    b:SetScript("OnClick", function() local d = popup.defs[i] or def; d[3](); popup:Hide() end)
  end

  -- Lien « < Retour » en bas à gauche (buttons.back = action), même ordre action puis Hide()
  if buttons.back then
    local back = CreateFrame("Button", nil, box)
    back:SetFrameLevel(box:GetFrameLevel() + 10)
    back:SetPoint("BOTTOMLEFT", 14, 10)
    local fs = back:CreateFontString(nil, "OVERLAY")
    if not pcall(fs.SetFont, fs, FONT, 11, "") then fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "") end
    fs:SetPoint("LEFT")
    fs:SetText("< " .. L["ROLE_BACK"])
    back:SetSize(fs:GetStringWidth() + 6, 18)
    local function Tone(v) fs:SetTextColor(v, v, v + 0.02) end
    Tone(0.55)
    back:SetScript("OnEnter", function() Tone(0.85) end)
    back:SetScript("OnLeave", function() Tone(0.55) end)
    back:SetScript("OnClick", function()
      if popup.defs.back then popup.defs.back() end
      popup:Hide()
    end)
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
-- Vrai dès que le setup a demandé un rechargement : la proposition de profil par rôle attend celui-ci.
local setupPending = false

local function ShowReloadPopup()
  setupPending = true
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
  if r1 or r2 or r3 then ShowReloadPopup(); return true end
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
  if SetupEditMode(AishUISetupCharDB) then ShowReloadPopup(); return true end
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
      elseif name == "ElvUI_WindTools" then
        enable = false -- WindTools ne fait plus partie d'AishUI (fonctions reprises par AishCore) : jamais active
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

-- ── Profils ElvUI / EllesmereUI par rôle et barres d'action ──────────────────────────────────────────
-- Profils livrés avec le pack : un par rôle, en deux variantes (barres montrées / cachées). Les noms
-- diffèrent entre les deux UI, et EllesmereUI n'a pas de soigneur vertical (repli sur le soigneur).
local ROLES = { "DPS", "HEALER", "HEALER_V", "TANK" }
local PROFILE_FMT = {
  ElvUI = {
    DPS = "AishUI - DPS - %s", HEALER = "AishUI - HEALER - %s",
    HEALER_V = "AishUI - HEALER Vertical - %s", TANK = "AishUI - TANK - %s",
  },
  Ellesmere = {
    DPS = "AishUI - DPS %s", HEALER = "AishUI - Healer %s",
    HEALER_V = "AishUI - Healer %s", TANK = "AishUI - Tank %s",
  },
}
local BARS_SUFFIX = { [true] = "Show Bars", [false] = "Hide Bars" }

local function ProfileName(flavor, role, show)
  local fmt = PROFILE_FMT[flavor] and PROFILE_FMT[flavor][role]
  return fmt and string.format(fmt, BARS_SUFFIX[show and true or false])
end

-- Accès au profil de l'UI chargée : { flavor, current(), exists(n), apply(n) }, ou nil.
local function GetUiApi()
  if C_AddOns.IsAddOnLoaded("ElvUI") and ElvUI then
    local E = ElvUI[1]
    local data = E and E.data
    if not data then return end
    return {
      flavor = "ElvUI",
      current = function() return data:GetCurrentProfile() end,
      exists = function(n) return data.sv and data.sv.profiles and data.sv.profiles[n] end,
      apply = function(n)
        data:SetProfile(n)
        -- Profils par spé d'ElvUI (LibDualSpec) actifs : on y range aussi le choix, sinon ElvUI
        -- remettrait l'ancien profil au prochain changement de spé.
        if data.IsDualSpecEnabled and data:IsDualSpecEnabled() and data.SetDualSpecProfile then
          data:SetDualSpecProfile(n)
        end
      end,
    }
  end
  if C_AddOns.IsAddOnLoaded("EllesmereUI") and EllesmereUI and EllesmereUI.SwitchProfile then
    local EUI = EllesmereUI
    local function exists(n) return EllesmereUIDB and EllesmereUIDB.profiles and EllesmereUIDB.profiles[n] end
    return {
      flavor = "Ellesmere",
      current = function() return EUI.GetActiveProfileName and EUI.GetActiveProfileName() end,
      exists = exists,
      -- Même enchaînement que les raccourcis de profil d'EllesmereUI (EnsureProfileBindBtn)
      apply = function(n)
        local prof = exists(n)
        local reload = (EUI.ProfileChangesFont and EUI.ProfileChangesFont(prof))
          or (EUI.ProfileChangesWindowSkins and EUI.ProfileChangesWindowSkins(prof))
          or (EUI.ProfileChangesStyle and EUI.ProfileChangesStyle(prof))
        EUI.SwitchProfile(n)
        if EUI.RefreshAllAddons then EUI.RefreshAllAddons(true) end
        if reload then
          ShowSetupPopup("AishCoreBarsReload", L["BARS_TITLE"], L["BARS_RELOAD"], {
            { L["ELLESMERE_SETUP_RELOAD"], true, ReloadUI },
            { L["CDM_RELOAD_LATER"], false, function() end },
          })
        elseif EUI.RefreshPage then
          EUI:RefreshPage()
        end
      end,
    }
  end
end

-- Spé courante : id, nom, rôle Blizzard (TANK / HEALER / DAMAGER)
local function CurrentSpec()
  local idx = ns.GetSpecialization and ns.GetSpecialization()
  if not idx or idx == 0 then return end
  local id, name, _, _, role = ns.GetSpecializationInfo(idx)
  if not id then return end
  return id, name, role or (ns.GetSpecializationRole and ns.GetSpecializationRole(idx))
end

-- Choix retenus pour ce perso, par spé : AishUISetupCharDB.roleChoice[specID] = { role = "DPS", show = true }.
-- Indépendants de l'UI : /aishuiswitch retrouve le même profil de l'autre côté.
local function Choices()
  AishUISetupCharDB = AishUISetupCharDB or {}
  AishUISetupCharDB.roleChoice = AishUISetupCharDB.roleChoice or {}
  return AishUISetupCharDB.roleChoice
end

-- Profil actif -> rôle + barres de la spé courante, seulement si un choix existe déjà (profil changé à la
-- main ou par /aish show|hide bars). Garde le soigneur vertical quand EllesmereUI ne le distingue pas.
local function RecordCurrent()
  local api, specID = GetUiApi(), CurrentSpec()
  local entry = specID and Choices()[specID]
  if not (api and entry) then return end
  local cur = api.current()
  for _, show in ipairs({ true, false }) do
    if ProfileName(api.flavor, entry.role, show) == cur then entry.show = show; return end
  end
  for _, role in ipairs(ROLES) do
    for _, show in ipairs({ true, false }) do
      if ProfileName(api.flavor, role, show) == cur then entry.role, entry.show = role, show; return end
    end
  end
end

-- /aish show bars | hide bars : profil actif vers sa variante opposée (remplacement du suffixe).
local function BarsTarget(current, show)
  if not current then return end
  local from, to = BARS_SUFFIX[not show], BARS_SUFFIX[show]
  if current:sub(-#to) == to then return nil, "already" end
  if current:sub(-#from) ~= from then return nil, "nomatch" end
  return current:sub(1, -#from - 1) .. to
end

function ns.SwitchBarsProfile(show)
  local P = "|cff00ccff[AishCore]|r "
  if InCombatLockdown() then print(P .. L["UISWITCH_COMBAT"]); return end
  local api = GetUiApi()
  if not api then print(P .. L["BARS_NO_UI"]); return end
  local current = api.current()
  local target, why = BarsTarget(current, show)
  if why == "already" then print(P .. string.format(L["BARS_ALREADY"], current)); return end
  if not target then print(P .. string.format(L["BARS_NOMATCH"], tostring(current))); return end
  if not api.exists(target) then print(P .. string.format(L["BARS_MISSING"], target)); return end
  api.apply(target)
  RecordCurrent()
  print(P .. string.format(L["BARS_DONE"], target))
end

-- Alias /aishui show bars | hide bars (même chose que /aish show bars | hide bars)
SLASH_AISHUIBARS1 = "/aishui"
SlashCmdList["AISHUIBARS"] = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "show bars" or msg == "hide bars" then
    ns.SwitchBarsProfile(msg == "show bars")
  else
    print("|cff00ccff[AishCore]|r /aishui show bars | hide bars")
  end
end

-- ── Profil suggéré à la 1re activation de chaque spé (version AishUI) ───────────────────────────────
-- Rôle de la spé -> profil proposé ; puis barres montrées / cachées. Le choix est ensuite réappliqué
-- à chaque passage sur cette spé (EllesmereUI n'a pas de profil par spé et par perso) et après
-- /aishuiswitch. Jamais dans la session du setup initial : la proposition attend son rechargement.
local SUGGESTED = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DPS" }
local SPEC_SUGGEST = { [1473] = "HEALER" } -- Évocateur Augmentation : joué avec le profil soigneur
local ROLE_LABEL = { DPS = "ROLE_DPS", HEALER = "ROLE_HEALER", TANK = "ROLE_TANK" }
local askedThisSession = {}
local pendingRoleCheck

local function PickLabel(flavor, role)
  if role == "HEALER" and flavor == "ElvUI" then return L["ROLE_HEALER_H"] end
  if role == "HEALER_V" then return L["ROLE_HEALER_V"] end
  return L[ROLE_LABEL[role]]
end

local function ApplyChoice(api, entry)
  local name = ProfileName(api.flavor, entry.role, entry.show)
  if not api.exists(name) then
    print("|cff00ccff[AishCore]|r " .. string.format(L["BARS_MISSING"], name))
    return
  end
  if api.current() ~= name then api.apply(name) end
end

local CheckRole, AskRole

local function AskBars(specID, role)
  local api = GetUiApi()
  if not api then return end
  local function Choose(show)
    local entry = { role = role, show = show }
    Choices()[specID] = entry
    if InCombatLockdown() then pendingRoleCheck = true; return end
    if CurrentSpec() == specID then ApplyChoice(api, entry) end
  end
  local buttons = {
    { L["ROLE_BARS_HIDE"], false, function() Choose(false) end },
    { api.flavor == "ElvUI" and L["ROLE_BARS_SHOW_ELVUI"] or L["ROLE_BARS_SHOW_EUI"], false, function() Choose(true) end },
    width = 240, height = 44,
  }
  ShowSetupPopup("AishCoreRoleBars", L["ROLE_TITLE"], L["ROLE_BARS_PROMPT"], buttons)
end

local function AskOther(specID, suggested)
  local api = GetUiApi()
  if not api then return end
  -- Autres profils existants, sans doublon (EllesmereUI : soigneur vertical = soigneur)
  local seen, buttons = { [ProfileName(api.flavor, suggested, true)] = true }, {}
  for _, role in ipairs(ROLES) do
    local name = ProfileName(api.flavor, role, true)
    if not seen[name] and (api.exists(name) or api.exists(ProfileName(api.flavor, role, false))) then
      seen[name] = true
      buttons[#buttons + 1] = { PickLabel(api.flavor, role), false, function() AskBars(specID, role) end }
    end
  end
  if #buttons == 0 then return end
  buttons.bottom = 60
  buttons.back = function() AskRole(false) end
  -- Nom par nombre de boutons : leur placement est figé à la construction de la popup
  ShowSetupPopup("AishCoreRolePick" .. #buttons, L["ROLE_TITLE"], L["ROLE_PICK_PROMPT"], buttons)
end

AskRole = function(force)
  local api = GetUiApi()
  local specID, specName, blizzRole = CurrentSpec()
  if not (api and specID) then
    if force then print("|cff00ccff[AishCore]|r " .. L["BARS_NO_UI"]) end
    return
  end
  local suggested = SPEC_SUGGEST[specID] or SUGGESTED[blizzRole] or "DPS"
  askedThisSession[specID] = true
  -- Couleurs Thématiques de la spé : nom en « Cercle de Puissance », rôle en « Décorations A »
  local Colors = ns.Modules.Colors
  local _, classFile = UnitClass("player")
  local function Tint(text, element)
    local c = Colors and Colors.GetForSpec and classFile and Colors.GetForSpec(classFile:lower(), specID, element)
    if not c then return text end
    return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
  end
  ShowSetupPopup("AishCoreRolePrompt", L["ROLE_TITLE"],
    string.format(L["ROLE_PROMPT"], Tint(specName or "?", "powercircle"),
      Tint(L[ROLE_LABEL[suggested]], "powerdotsa")), {
    { L["ROLE_YES"], true, function() AskBars(specID, suggested) end },
    { L["ROLE_OTHER"], false, function() AskOther(specID, suggested) end },
    { L["ROLE_NEVER"], false, function()
        AishUISetupCharDB = AishUISetupCharDB or {}
        AishUISetupCharDB.roleNever = true
      end },
  })
end

CheckRole = function()
  if not (AishaddonDB and ns.HasHeroicFeatures and ns.HasHeroicFeatures()) then return end
  if setupPending then return end
  local api = GetUiApi()
  local specID = CurrentSpec()
  if not (api and specID) then return end
  if InCombatLockdown() then pendingRoleCheck = true; return end
  local entry = Choices()[specID]
  if entry then ApplyChoice(api, entry); return end
  if AishUISetupCharDB.roleNever or askedThisSession[specID] then return end
  AskRole(false)
end

-- /aish role | /aishrole : proposition à la demande (même si déjà choisi ou « Ne plus demander »)
function ns.AskRoleProfile()
  if not (AishaddonDB and ns.HasHeroicFeatures and ns.HasHeroicFeatures()) then return end
  if InCombatLockdown() then print("|cff00ccff[AishCore]|r " .. L["UISWITCH_COMBAT"]); return end
  AskRole(true)
end

SLASH_AISHROLE1 = "/aishrole"
SlashCmdList["AISHROLE"] = function() ns.AskRoleProfile() end

local roleEv = CreateFrame("Frame")
roleEv:RegisterEvent("PLAYER_ENTERING_WORLD")
ns.TrackSpecFrame(roleEv)
roleEv:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
roleEv:RegisterEvent("PLAYER_REGEN_ENABLED")
roleEv:RegisterEvent("PLAYER_LOGOUT")
roleEv:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_REGEN_ENABLED" then
    if pendingRoleCheck then pendingRoleCheck = nil; C_Timer.After(1, CheckRole) end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- Forever : rejoué par ns.FireSpecChanged, sans unité
    if arg1 == nil or arg1 == "player" then C_Timer.After(3, CheckRole) end
  elseif event == "PLAYER_LOGOUT" then
    -- Profil changé à la main dans ElvUI / EllesmereUI : retenu pour cette spé (et pour /aishuiswitch)
    pcall(RecordCurrent)
  elseif arg1 or arg2 then
    -- Login / reload seulement : laisse passer le setup et les popups d'EllesmereUI (+2 s)
    C_Timer.After(4, function() SafeRun(CheckRole) end)
  end
end)

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
  if not (ns.HasHeroicFeatures and ns.HasHeroicFeatures()) then
    print("|cff00ccff[AishCore]|r " .. L["SETUP_NOT_AISHUI"])
    return
  end
  print("|cff00ccff[AishCore]|r Setup relancé.")
  -- Aucune etape n'a rien change (pas de popup de reload) : on le dit, sinon la commande semble muette
  local ok1, changed1 = pcall(Apply)
  local ok2, changed2 = pcall(ApplyEditMode)
  if not ok1 then print("|cffff4444[AishCore]|r AishUISetup : " .. tostring(changed1)) end
  if not ok2 then print("|cffff4444[AishCore]|r AishUISetup : " .. tostring(changed2)) end
  if ok1 and ok2 and not changed1 and not changed2 then
    print("|cff00ccff[AishCore]|r " .. L["SETUP_NOTHING_TO_DO"])
  end
end

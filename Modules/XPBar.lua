-- Modules/XPBar.lua : Barre d'experience custom (fond + overlay + badge niveau, layout mode drag/resize)
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local XPBar = {}
ns.Modules.XPBar = XPBar

-- Constantes
local TEX_OVERLAY   = "Interface\\AddOns\\AishCore\\Media\\XPBar\\aishui_xpbar.png"
local TEX_GRUNGE    = "Interface\\AddOns\\AishCore\\Media\\XPBar\\grunge_spot1.png"
local TEX_SPARK     = "Interface\\CastingBar\\UI-CastingBar-Spark"
local TEX_SOLID     = "Interface\\BUTTONS\\WHITE8X8"

local FONT_LEVEL    = ns.FONT_FALLBACK  -- police du jeu (2002)
local FONT_INFO     = ns.FONT_FALLBACK  -- meme casse que ns.FONT_LIST (sinon doublon dans le dropdown)
-- Font du badge de niveau (mise a jour via ApplySettings si l'utilisateur change la police)
local xpFontLevel   = FONT_LEVEL
local xpFontInfo    = FONT_INFO  -- textes d'info (tooltip, XP centrale), cf. cfg.fontInfo

local BAR_H         = 9
local SPARK_W       = 107
local SPARK_H       = 54
local HOVER_W       = 50
local HOVER_H       = 50
local SHOW_DURATION = 4.5
local ANIM_IN_DUR   = 0.3
local ANIM_OUT_DUR  = 0.5

local TEAL_DARK  = CreateColor(0.01, 0.76, 0.55, 1)
local TEAL_LIGHT = CreateColor(0.05, 1.00, 0.74, 1)
local SPARK_CLR  = { 0.97254908, 0.86274517, 0.29411766 }

-- Gain XP animation
local GAIN_COLOR         = { 0.12, 0.95, 0.82, 0.85 }  -- turquoise vif
local GAIN_ANIM_GROW_DUR = 1.05   -- durée croissance (s)
local GAIN_ANIM_HOLD_DUR = 1.80   -- durée maintien plein (s)
local GAIN_ANIM_FADE_DUR = 0.45   -- durée disparition (s)
local SPARK_PULSE_SPEED  = 2     -- pulsations par seconde (scintillement doux)

-- Defaults locaux (fallback si DB manquante)
local DEF_LB = { x = -34, y = 2.15, w = 116, h = 79, rot = 201 }
local DEF_TF = { x = -34, y = 85,   w = 145, h = 48,
                 bgRot = 48, bgW = 200, bgH = 104, bgOffX = -23, bgOffY = 0 }

-- Etat prive
local container
local bgTex
local xpBar
local overlayTex
local sparkTex
local levelBg
local lbTex           -- texture background badge (pour maj rotation)
local repNameLabel    -- FontString flottant plein nom au hover (mode réputation)
local levelText
local tooltipFrame
local ttTex           -- texture background tooltip (pour maj rotation)
local tooltipXP
local tooltipRested
local centerXPText
local nlPanel            -- apercu du prochain niveau (coin bas droit), cf. ShowNextLevelPanel
local qPanel             -- quetes pretes a rendre (Alt au survol), cf. ShowQuestPanel
local fontObjs = {}     -- objets Font des textes d'info, cf. XPBar.ApplySettings
local hoverFrame
local fxModel
local restModel       -- animation 3D indicateur de zone de repos

--- Applique le style de contour a levelText (factorise les ~9 sites qui refont SetFont).
local function SetLevelTextFont(size)
  ns.ApplyTextOutlineStyle(levelText, levelText.slugRing, xpFontLevel, size,
    ns.DB.xpBar and ns.DB.xpBar.levelOutlineStyle, true)
end

-- Elements layout mode
local lbBorder        -- Frame bordure rouge autour de levelBg
local lbCoordText     -- FontString coordonnees levelBg
local lbResizeHandle  -- Frame handle resize levelBg (coin bas-droit)
local tfBorder
local tfCoordText
local tfResizeHandle

local showAnim
local hideAnim
local showTimer
local isHovered       = false
local petMode         = false  -- Forever : survol de la barre du familier (cf. XPBar.SetPetHover)
local isLayoutMode    = false
local isRepMode           = false  -- vrai quand on affiche la réputation (niveau max)
local isCompanionMode     = false  -- vrai quand on affiche l'XP compagnon de gouffre
local COMPANION_FACTION_IDS    = {2640, 2744}  -- Brann (TWW), Valeera (Midnight)
local companionStandingCache   = {}            -- {[factionID]=standing} pour détecter les gains
local activeCompanionFactionID = nil           -- faction qui gagne de l'XP pendant le scénario
-- Whitelist mapIDs gouffres (valeur = factionID compagnon préféré) ; TWW couvert par scenarioType=11, Midnight via fallback
local DELVE_MAP_IDS = {
  -- Midnight (Valeera 2744)
  [2503] = 2744,  -- Cryptes du Crépuscule
  [2535] = 2744,  -- Atal'Aman
  [2577] = 2744,  -- Calamité Universitaire
  [2578] = 2744,  -- Calamité Universitaire  
  [2547] = 2744,  -- Calamité Universitaire
  [2502] = 2744,  -- L'Enclave Ombreuse
  [2506] = 2744,  -- Halte de l'Ombre-Garde
  [2528] = 2744,  -- Sanctum des Tue-Soleil
  [2571] = 2744,  -- Sanctum des Tue-Soleil
  [2510] = 2744,  -- La fosse de la Rancoeur
  [2505] = 2744,  -- Le golfe du Souvenir
  [2507] = 2744,  -- Eminence du tourment
  [2525] = 2744,  -- Sombrevoie
  [2545] = 2744,  -- Parhélion
  [2633] = 2744,  -- Arène de la Gloire
  -- TWW (Brann 2640) - normalement détectés via scenarioType=11
  [2269] = 2640,  -- Mines de Rampeterre
  [2250] = 2640,  -- Repos de Kriegval
  [2249] = 2640,  -- Folie fongique
  [2396] = 2640,  -- Site d'excavation 9
  [2302] = 2640,  -- La fosse de l'Effroi
  [2251] = 2640,  -- Le moulin à eau
  [2312] = 2640,  -- Grotte de Mycomancie
  [2310] = 2640,  -- Brèche Grouillante
  [2269] = 2640,  -- Le Puisard
  [2277] = 2640,  -- Sanctuaire Noctechute
  [2347] = 2640,  -- La Trame spiralée
  [2259] = 2640,  -- Abysse de Tak-Rethan
  [2299] = 2640,  -- Le donjon de l'Abîme
  [2348] = 2640,  -- Tanière de Zekvir
  [2423] = 2640,  -- Chenal de ruelle
  [2426] = 2640,  -- Dôme de la Démolition
  [2452] = 2640,  -- Assaut des Archives
  [2484] = 2640  -- Sanctuaire du Rasoir du Vide

}
local blizzBarsHidden     = false  -- forward : assigné avant première utilisation
local SetBlizzXPBarHidden         -- forward declaration (défini plus bas)
local ApplyRestModelCfg           -- forward declaration (défini plus bas)
local UpdateRestingIndicator      -- forward declaration (défini plus bas)
local restPreview = false         -- mode prévisualisation : affiche le modèle même hors zone de repos
local repCache             = {}   -- {[factionID] = progressKey} pour détecter les gains
local repPctCache          = {}   -- {[factionID] = pct (0-1)} snapshot au précédent check
local lastGainedRepData    = nil  -- dernière réputation qui a progressé
local knownMajorFactionIDs = {}   -- set de factionIDs Renommée (TWW Major Factions)
local factionNameCache     = {}   -- {[factionID] = name} évite GetFactionDataByID à chaque scan

-- Gain XP animation state
local gainBar
local gainAnimFrame
local gainPhase     = "idle"  -- "grow" | "hold" | "fade" | "idle"
local gainElapsed   = 0
local gainStartX    = 0
local gainTargetW   = 0
local prevXP        = nil
local prevCompanionPct = nil  -- pour détecter le delta d'XP compagnon
local prevRepPct       = nil  -- pour détecter le delta de réputation

--- Réinitialise l'état du mode compagnon (sortie gouffre, loading screen, toggle).
local function ResetCompanionState()
  isCompanionMode          = false
  prevCompanionPct         = nil
  activeCompanionFactionID = nil
  wipe(companionStandingCache)
end

local FX_MODEL_ID = 4507696
local FX_W, FX_H = 313, 283

-- Indicateur de zone de repos, ancré sur le badge de niveau (levelBg)
local REST_MODEL_ID = 165675
local REST_W        = 85.591751098633
local REST_H        = 66.667037963867
local REST_SCALE    = 40               
local REST_TX       = 40               

-- Helpers DB
local function GetCfgLB()
  local db = ns.DB and ns.DB.xpBar and ns.DB.xpBar.levelBg
  if not db then db = ns.Defaults and ns.Defaults.xpBar and ns.Defaults.xpBar.levelBg end
  if not db then return DEF_LB end
  return {
    x   = db.x   or DEF_LB.x,
    y   = db.y   or DEF_LB.y,
    w   = db.w   or DEF_LB.w,
    h   = db.h   or DEF_LB.h,
    rot = db.rot or DEF_LB.rot,
  }
end

local function GetCfgTF()
  local db = ns.DB and ns.DB.xpBar and ns.DB.xpBar.tooltipFrame
  if not db then db = ns.Defaults and ns.Defaults.xpBar and ns.Defaults.xpBar.tooltipFrame end
  if not db then return DEF_TF end
  return {
    x      = db.x      or DEF_TF.x,
    y      = db.y      or DEF_TF.y,
    w      = db.w      or DEF_TF.w,
    h      = db.h      or DEF_TF.h,
    bgRot  = db.bgRot  or DEF_TF.bgRot,
    bgW    = db.bgW    or DEF_TF.bgW,
    bgH    = db.bgH    or DEF_TF.bgH,
    bgOffX = db.bgOffX or DEF_TF.bgOffX,
    bgOffY = db.bgOffY or DEF_TF.bgOffY,
  }
end

local function SaveLB()
  if not levelBg then return end
  if not ns.DB    then ns.DB    = {} end
  if not ns.DB.xpBar then ns.DB.xpBar = {} end
  local x, y = levelBg:GetLeft(), levelBg:GetBottom()
  local ux, uy = UIParent:GetLeft() or 0, UIParent:GetBottom() or 0
  local w, h = levelBg:GetSize()
  ns.DB.xpBar.levelBg = ns.DB.xpBar.levelBg or {}
  ns.DB.xpBar.levelBg.x = x - ux
  ns.DB.xpBar.levelBg.y = y - uy
  ns.DB.xpBar.levelBg.w = w
  ns.DB.xpBar.levelBg.h = h
end

local function SaveTF()
  if not tooltipFrame then return end
  if not ns.DB         then ns.DB = {} end
  if not ns.DB.xpBar   then ns.DB.xpBar = {} end
  local x, y = tooltipFrame:GetLeft(), tooltipFrame:GetBottom()
  local ux, uy = UIParent:GetLeft() or 0, UIParent:GetBottom() or 0
  local w, h = tooltipFrame:GetSize()
  ns.DB.xpBar.tooltipFrame = ns.DB.xpBar.tooltipFrame or {}
  ns.DB.xpBar.tooltipFrame.x = x - ux
  ns.DB.xpBar.tooltipFrame.y = y - uy
  ns.DB.xpBar.tooltipFrame.w = w
  ns.DB.xpBar.tooltipFrame.h = h
end

-- Helpers display
local function GetClassColor()
  local _, class = UnitClass("player")
  local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function GetBarWidth()
  return UIParent:GetWidth()
end

local function UpdateBarColor()
  if not xpBar then return end
  local r, g, b
  local CLR = ns.Modules.Colors
  if CLR then
    local c = CLR.Get(petMode and "pethealthbar" or "misc")  -- Misc = barre XP elle-même ; sur le familier : "PV du Familier"
    r, g, b = c[1], c[2], c[3]
  else
    r, g, b = GetClassColor()
  end
  local barTex = xpBar:GetStatusBarTexture()
  if barTex and barTex.SetGradient then
    barTex:SetGradient("VERTICAL",
      CreateColor(r * 0.45, g * 0.45, b * 0.45, 1),
      CreateColor(r,        g,        b,        1))
  else
    xpBar:SetStatusBarColor(r, g, b, 1)
  end
end

-- Applique la couleur XP Bar (texte niveau, hover, texte central) ; GAIN_COLOR n'est jamais touchée
local function UpdateXPColors()
  local r, g, b
  local CLR = ns.Modules.Colors
  if CLR then
    local c = CLR.Get(petMode and "pethealthbar" or "xpbar")  -- XP Bar = textes niveau ; sur le familier : "PV du Familier"
    r, g, b = c[1], c[2], c[3]
  else
    r, g, b = GetClassColor()
  end
  if levelText    then levelText:SetTextColor(r, g, b, 1) end
  if repNameLabel then repNameLabel:SetTextColor(r, g, b, 1) end
  if tooltipXP    then tooltipXP:SetTextColor(r, g, b, 1) end
  if centerXPText then centerXPText:SetTextColor(r, g, b, 1) end
  -- tooltipRested reste toujours bleu (rested XP)
end

local function AnimateXPGain(oldPct, deltaPct)
  if not gainBar or not gainAnimFrame then return end
  if deltaPct <= 0 then return end
  local totalW = GetBarWidth()
  gainStartX  = oldPct * totalW
  gainTargetW = math.max(2, deltaPct * totalW)
  gainElapsed = 0
  gainPhase   = "grow"
  gainBar:ClearAllPoints()
  gainBar:SetPoint("LEFT", container, "LEFT", gainStartX, 0)
  gainBar:SetSize(1, BAR_H)
  gainBar:SetAlpha(1)
  gainBar:Show()
  if sparkTex then
    sparkTex:ClearAllPoints()
    sparkTex:SetPoint("CENTER", container, "LEFT", gainStartX, 0)
    sparkTex:SetAlpha(1)
    sparkTex:Show()
  end
  gainAnimFrame:Show()
end

local function IsMaxLevel()
  return UnitLevel("player") >= GetMaxPlayerLevel()
end

-- Réputation trackée (mode niveau max)
--- Données d'une faction (les 3 systèmes : Renommée, Amitié, Classique). factionData optionnel pour le chemin classique.
local function GetRepDataForFaction(factionID, factionName, factionData)
  if not factionID or not factionName or factionName == "" then return nil end
  local name   = factionName
  local letter = string.upper(string.sub(name, 1, 3)) .. "."

  -- isAccountWide (bataillon) déterminé une fois pour tous les systèmes
  local isBattalion = false
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, basefd = pcall(C_Reputation.GetFactionDataByID, factionID)
    if ok and basefd then isBattalion = basefd.isAccountWide or false end
  end

  -- Système de Renommée (Dragonflight / TWW — Major Factions)
  if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
    local ok, mf = pcall(C_MajorFactions.GetMajorFactionData, factionID)
    if ok and mf and mf.renownLevel ~= nil then
      local cur = mf.renownReputationEarned or 0
      local max = mf.renownLevelThreshold   or 1
      local pct = (max > 0) and (cur / max) or 0
      return {
        name        = name,
        letter      = letter,
        pct         = math.max(0, math.min(1, pct)),
        cur         = cur,
        max         = max,
        standing    = string.format(L["XP_RENOWN_LEVEL"], mf.renownLevel),
        isBattalion = isBattalion,
      }
    end
  end

  -- Système de Réputation d'amitié (Chromie, etc.)
  if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
    local ok, fr = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
    if ok and fr and fr.friendshipFactionID and fr.friendshipFactionID > 0 then
      local base  = fr.reactionThreshold or 0
      local range = fr.nextThreshold and (fr.nextThreshold - base) or 0
      local cur   = (fr.standing or 0) - base
      local pct   = (range > 0) and (cur / range) or 1
      return {
        name        = name,
        letter      = letter,
        pct         = math.max(0, math.min(1, pct)),
        cur         = math.max(0, cur),
        max         = math.max(1, range),
        standing    = fr.reaction or name,
        isBattalion = isBattalion,
      }
    end
  end

  -- Système classique (standings Amical / Honorable / Exalté…)
  local fd
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, r = pcall(C_Reputation.GetFactionDataByID, factionID)
    if ok then fd = r end
  end
  if not fd then fd = factionData end
  if not fd then return nil end
  local range = (fd.nextReactionThreshold or 0) - (fd.currentReactionThreshold or 0)
  local cur   = (fd.currentStanding       or 0) - (fd.currentReactionThreshold or 0)
  local pct   = (range > 0) and (cur / range) or 0
  if range <= 0 and (fd.reaction or 0) >= 8 then pct = 1 end
  local sLabel  = (fd.reaction and _G["FACTION_STANDING_LABEL" .. fd.reaction]) or "?"
  local rank    = fd.reaction or 0
  local rankMax = (isBattalion and 6) or (MAX_REPUTATION_REACTION or 8)
  return {
    name        = name,
    letter      = letter,
    pct         = math.max(0, math.min(1, pct)),
    cur         = math.max(0, cur),
    max         = math.max(1, range),
    standing    = sLabel,
    rank        = rank,
    rankMax     = rankMax,
    isBattalion = isBattalion,
  }
end

--- Retourne les données de la réputation actuellement trackée, ou nil.
local function GetRepData()
  if not (C_Reputation and C_Reputation.GetWatchedFactionData) then return nil end
  local data = C_Reputation.GetWatchedFactionData()
  if not data or not data.name or data.name == "" then return nil end
  return GetRepDataForFaction(data.factionID, data.name, data)
end

--- Réputation à afficher selon le mode configuré ("tracked" ou "lastGained"), ou nil si désactivé.
local function GetActiveRepData()
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.repEnabled == false then return nil end
  local mode = cfg and cfg.repDisplayMode or "tracked"
  if mode == "lastGained" and lastGainedRepData then
    return lastGainedRepData
  end
  return GetRepData()
end

--- Retourne true uniquement si le joueur est dans un gouffre (TWW Delve / Midnight Gouffre).
local function IsInDelve()
  if not (C_Scenario and C_Scenario.IsInScenario) then return false end
  local ok, inScenario = pcall(C_Scenario.IsInScenario)
  if not ok or not inScenario then return false end
  -- 1. APIs directes TWW (C_DelvesUI)
  if C_DelvesUI then
    if C_DelvesUI.IsInDelve then
      local okD, res = pcall(C_DelvesUI.IsInDelve)
      if okD and res == true then return true end
    end
    if C_DelvesUI.HasCompanionPanel then
      local okP, res = pcall(C_DelvesUI.HasCompanionPanel)
      if okP and res == true then return true end
    end
    if C_DelvesUI.GetActiveDelveInfo then
      local okI, info = pcall(C_DelvesUI.GetActiveDelveInfo)
      if okI and info ~= nil then return true end
    end
  end
  -- 2. scenarioType 11 = gouffre TWW
  if C_Scenario.GetScenarioInfo then
    local okI, info = pcall(C_Scenario.GetScenarioInfo)
    if okI and info then
      if info.scenarioType == 11 then return true end
    end
  end
  -- 3. Fallback mapID (Midnight et futurs gouffres sans C_DelvesUI)
  if C_Map and C_Map.GetBestMapForUnit then
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID and DELVE_MAP_IDS[mapID] then return true end
  end
  return false
end

--- Données XP du compagnon de gouffre (Brann / Valeera), ou nil si inactif (niveau max + en gouffre requis).
-- ═══ Forever : XP du familier de chasseur, affichee a la place de celle du joueur pendant le survol de sa barre ═══
-- (cf. XPBar.SetPetHover, appelee par UnitBars). Niveau de loyaute : voir PetLoyaltyLine.
local LOYALTY_PATTERNS = {}   -- rempli a la demande : nom localise (minuscules) -> niveau
local function LoyaltyLevelFromName(text)
  if type(text) ~= "string" or text == "" then return nil end
  if #LOYALTY_PATTERNS == 0 then
    for i = 1, 6 do
      for _, key in ipairs({ "XP_PET_LOYALTY_" .. i, "XP_PET_LOYALTY_EN_" .. i }) do
        local n = L[key]
        if type(n) == "string" and n ~= key then LOYALTY_PATTERNS[#LOYALTY_PATTERNS + 1] = { n:lower(), i } end
      end
    end
  end
  local low = text:lower()
  local digit = low:match("(%d)")
  if digit then return tonumber(digit) end
  for _, p in ipairs(LOYALTY_PATTERNS) do
    if low:find(p[1], 1, true) then return p[2] end
  end
  return nil
end

-- Ligne "Loyaute N - Nom". Source : le texte du panneau Familier de Blizzard (PetCharacterLevelText), de la forme
-- "Ours niveau 7 ((Niveau de loyaute 1) Rebelle)" -- le niveau de loyaute est le dernier nombre, juste avant ")".
-- Repli : GetPetLoyalty() (texte ou nombre) s'il existe. /aishpet affiche ce que le jeu renvoie.
-- PetCharacterLevelText est un CADRE (fstack) : le texte est dans une de ses regions ou dans un cadre enfant. On cherche
-- le premier FontString non vide, sur trois niveaux.
local function FindFrameText(f, depth)
  if not f then return nil end
  if f.GetText then
    local ok, t = pcall(f.GetText, f)
    if ok and type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then return t end
  end
  if f.GetRegions then
    for _, r in ipairs({ f:GetRegions() }) do
      if r.GetText then
        local ok, t = pcall(r.GetText, r)
        if ok and type(t) == "string" and t ~= "" and not (issecretvalue and issecretvalue(t)) then return t end
      end
    end
  end
  if (depth or 0) < 2 and f.GetChildren then
    for _, c in ipairs({ f:GetChildren() }) do
      local t = FindFrameText(c, (depth or 0) + 1)
      if t then return t end
    end
  end
  return nil
end

local function PetPanelText()
  return FindFrameText(_G.PetCharacterLevelText) or FindFrameText(_G.PaperDollPetLevelInfo)
end

-- Fonctions de loyaute du client : GetPetLoyalty() (Vanilla / TBC : c'est elle qui remplit le panneau Familier) ou toute autre
-- fonction globale / de C_PetInfo dont le nom contient "loyal". Liste etablie une fois (le parcours de _G coute).
local loyaltyFns
local function LoyaltyFunctions()
  if loyaltyFns then return loyaltyFns end
  loyaltyFns = {}
  local seen = {}
  local function Add(name, fn)
    if type(fn) == "function" and not seen[fn] then seen[fn] = true; loyaltyFns[#loyaltyFns + 1] = { name = name, fn = fn } end
  end
  Add("GetPetLoyalty", _G.GetPetLoyalty)
  Add("UnitLoyalty", _G.UnitLoyalty)
  if C_PetInfo then
    Add("C_PetInfo.GetPetLoyalty", C_PetInfo.GetPetLoyalty)
    for k, v in pairs(C_PetInfo) do
      if type(k) == "string" and k:lower():find("loyal") then Add("C_PetInfo." .. k, v) end
    end
  end
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "function" then
      local low = k:lower()
      if low:find("loyal") and low:find("pet") then Add(k, v) end
    end
  end
  return loyaltyFns
end

local function PetLoyaltyLine()
  local raw, lvl
  local panel = PetPanelText()
  if type(panel) == "string" and panel ~= "" and not (issecretvalue and issecretvalue(panel)) then
    local n = panel:match("(%d+)%s*%)")
    if n then lvl = tonumber(n) else lvl = LoyaltyLevelFromName(panel:match("%)%s*([^%)]+)%)%s*$") or "") end
  end
  if not lvl then
    for _, c in ipairs(LoyaltyFunctions()) do
      local ok, v = pcall(c.fn, "pet")
      if not ok or v == nil or v == false then ok, v = pcall(c.fn) end
      if ok and v ~= nil and v ~= false and not (issecretvalue and issecretvalue(v)) then
        local n = (type(v) == "number") and v or LoyaltyLevelFromName(tostring(v))
        if n and n >= 1 and n <= 6 then lvl = n; break end
        if raw == nil and type(v) == "string" and v ~= "" then raw = v end
      end
    end
  end
  if not lvl and raw ~= nil then
    if type(raw) == "number" then lvl = raw else lvl = LoyaltyLevelFromName(tostring(raw)) end
  end
  if not lvl and raw == nil then return nil end
  if lvl and lvl >= 1 and lvl <= 6 then
    return string.format(L["XP_PET_LOYALTY"], lvl, L["XP_PET_LOYALTY_" .. lvl])
  end
  return type(raw) == "string" and raw ~= "" and raw or nil
end

local function GetPetXPData()
  if not (ns.IsForever and UnitExists("pet") and GetPetExperience and HasPetUI) then return nil end
  local _, isHunterPet = HasPetUI()
  if not isHunterPet then return nil end
  local ok, cur, maxXP = pcall(GetPetExperience)
  if not ok or type(cur) ~= "number" or type(maxXP) ~= "number" or maxXP <= 0 then return nil end
  if issecretvalue and (issecretvalue(cur) or issecretvalue(maxXP)) then return nil end
  return { level = UnitLevel("pet") or 0, xp = cur, maxXP = maxXP, pct = cur / maxXP, loyalty = PetLoyaltyLine() }
end

local function GetCompanionXPData()
  if not IsMaxLevel() then return nil end
  local cfg = ns.GetCfg("xpBar")
  if not cfg or cfg.companionXP == false then return nil end
  if not IsInDelve() then return nil end
  if not (C_GossipInfo and C_GossipInfo.GetFriendshipReputation) then return nil end
  -- Ordre de préférence : compagnon actif ce scénario, puis préféré selon mapID, puis liste complète
  local preferredID = activeCompanionFactionID
  if not preferredID and C_Map and C_Map.GetBestMapForUnit then
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then preferredID = DELVE_MAP_IDS[mapID] end
  end
  local orderedIDs
  if preferredID then
    orderedIDs = { preferredID }
    for _, fid in ipairs(COMPANION_FACTION_IDS) do
      if fid ~= preferredID then
        orderedIDs[#orderedIDs + 1] = fid
      end
    end
  else
    orderedIDs = COMPANION_FACTION_IDS
  end
  for _, factionID in ipairs(orderedIDs) do
    local okR, fr = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
    if okR and fr and fr.standing then
      -- Le level vient de GetFriendshipReputationRanks (champ séparé)
      local level, maxLevel = 1, 60
      if C_GossipInfo.GetFriendshipReputationRanks then
        local okLvl, ranks = pcall(C_GossipInfo.GetFriendshipReputationRanks, factionID)
        if okLvl and ranks then
          level    = ranks.currentLevel or 1
          maxLevel = ranks.maxLevel     or 60
        end
      end
      -- XP dans le niveau courant : standing relatif au seuil du niveau
      local xp    = (fr.standing or 0) - (fr.reactionThreshold or 0)
      local maxXP = (fr.nextThreshold or 0) - (fr.reactionThreshold or 0)
      if maxXP <= 0 then maxXP = 1 end
      local pct  = math.max(0, math.min(1, xp / maxXP))
      local name = fr.name or L["XP_COMPANION_FALLBACK_NAME"]
      return {
        name     = name,
        letter   = string.upper(string.sub(name, 1, 3)) .. ".",
        level    = level,
        maxLevel = maxLevel,
        xp       = xp,
        maxXP    = maxXP,
        pct      = pct,
      }
    end
  end
  return nil
end

--- Clé de progression monotone croissante pour une faction (Renommée/Amitié/Classique), ou nil si inconnue.
local function GetFactionProgressKey(fid)
  if not fid or fid <= 0 then return nil end
  -- Renommée
  if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
    local ok, mf = pcall(C_MajorFactions.GetMajorFactionData, fid)
    if ok and mf and mf.renownLevel ~= nil then
      return mf.renownLevel * 100000 + (mf.renownReputationEarned or 0)
    end
  end
  -- Amitié
  if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
    local ok, fr = pcall(C_GossipInfo.GetFriendshipReputation, fid)
    if ok and fr and fr.friendshipFactionID and fr.friendshipFactionID > 0 then
      return fr.standing or 0
    end
  end
  -- Classique
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, fd = pcall(C_Reputation.GetFactionDataByID, fid)
    if ok and fd and fd.currentStanding then
      return fd.currentStanding
    end
  end
  return nil
end

--- Remplit knownMajorFactionIDs + factionNameCache pour les factions de Renommée ; safe à rappeler plusieurs fois.
local function EnrichMajorFactionIDs()
  if not (C_MajorFactions and C_MajorFactions.GetMajorFactionIDs) then return end
  local maxExp = (LE_EXPANSION_LEVEL_CURRENT or 10) + 1
  for exp = 9, maxExp do
    local ok, ids = pcall(C_MajorFactions.GetMajorFactionIDs, exp)
    if ok and ids then
      for _, fid in ipairs(ids) do
        if not knownMajorFactionIDs[fid] then
          knownMajorFactionIDs[fid] = true
          if not factionNameCache[fid] then
            -- Essai 1 : GetFactionDataByID (factions classiques / Renommée standard)
            if C_Reputation and C_Reputation.GetFactionDataByID then
              local okN, fd = pcall(C_Reputation.GetFactionDataByID, fid)
              if okN and fd and fd.name and fd.name ~= "" then
                factionNameCache[fid] = fd.name
              end
            end
            -- Essai 2 : GetMajorFactionData (couvre les Journey/Season comme La Traque)
            if not factionNameCache[fid] then
              local okM, mf = pcall(C_MajorFactions.GetMajorFactionData, fid)
              if okM and mf and mf.name and mf.name ~= "" then
                factionNameCache[fid] = mf.name
              end
            end
          end
        end
      end
    end
  end
end

--- Détecte les gains de réputation parmi les factions connues (noms pré-cachés).
local function ScanRepGains()
  local function CheckFaction(fid, fname, fdHint)
    if not fid or fid <= 0 then return end
    local key = GetFactionProgressKey(fid)
    if not key then return end
    local prev = repCache[fid]
    if prev == nil then
      repCache[fid] = key  -- première vue : baseline seulement, pas un gain
      -- Initialiser repPctCache pour les factions découvertes après InitRepCache
      if not repPctCache[fid] then
        local name2 = fname or factionNameCache[fid]
        if name2 then
          local rd = GetRepDataForFaction(fid, name2, fdHint)
          if rd then repPctCache[fid] = rd.pct end
        end
      end
    elseif key > prev then
      repCache[fid] = key
      local name = fname or factionNameCache[fid]
      -- Essais de récupération du nom si absent du cache
      if not name or name == "" then
        -- 1) Journey / Season factions (La Traque, etc.)
        if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
          local okM, mf = pcall(C_MajorFactions.GetMajorFactionData, fid)
          if okM and mf and mf.name and mf.name ~= "" then
            name = mf.name
            factionNameCache[fid] = name
          end
        end
        -- 2) Factions classiques / bataillon (GetFactionDataByID)
        if (not name or name == "") and C_Reputation and C_Reputation.GetFactionDataByID then
          local okF, fd = pcall(C_Reputation.GetFactionDataByID, fid)
          if okF and fd and fd.name and fd.name ~= "" then
            name = fd.name
            factionNameCache[fid] = name
          end
        end
      end
      if not name or name == "" then return end  -- faction vraiment inconnue, skip
      local rdata = GetRepDataForFaction(fid, name, fdHint)
      if rdata then
        rdata.prevPct    = repPctCache[fid]  -- pct AVANT ce gain (nil si premier gain)
        repPctCache[fid] = rdata.pct         -- mettre à jour pour les prochains gains
        lastGainedRepData = rdata
      end
    end
  end

  -- Factions de Renommée TWW/DF (principal système en jeu actuel)
  for fid in pairs(knownMajorFactionIDs) do
    CheckFaction(fid, factionNameCache[fid])
  end

  -- Faction classique suivie (systèmes legacy / amitié)
  if C_Reputation and C_Reputation.GetWatchedFactionData then
    local data = C_Reputation.GetWatchedFactionData()
    if data and data.factionID and data.factionID > 0 then
      CheckFaction(data.factionID, data.name, data)
    end
  end
end

--- Initialise les caches au login / reload (knownMajorFactionIDs, factionNameCache, baselines repCache).
local function InitRepCache()
  repCache         = {}
  repPctCache      = {}
  factionNameCache = {}
  knownMajorFactionIDs = {}
  -- Factions Renommée (principal chemin TWW)
  EnrichMajorFactionIDs()
  for fid in pairs(knownMajorFactionIDs) do
    local key = GetFactionProgressKey(fid)
    if key then
      repCache[fid] = key
      local name = factionNameCache[fid]
      if name then
        local rd = GetRepDataForFaction(fid, name)
        if rd then repPctCache[fid] = rd.pct end
      end
    end
  end
  -- Faction classique suivie (fallback legacy / amitié)
  if C_Reputation and C_Reputation.GetWatchedFactionData then
    local data = C_Reputation.GetWatchedFactionData()
    if data and data.factionID and data.factionID > 0 and not repCache[data.factionID] then
      local key = GetFactionProgressKey(data.factionID)
      if key then
        repCache[data.factionID] = key
        factionNameCache[data.factionID] = data.name
        local rd = GetRepDataForFaction(data.factionID, data.name, data)
        if rd then repPctCache[data.factionID] = rd.pct end
      end
    end
  end
end

-- (GetBarWidth est defini plus haut)

local function ShortNum(n)
  n = math.floor(n or 0)
  if n >= 1e12 then return (string.format("%.1f", n/1e12):gsub("%.0$", "")) .. "t"
  elseif n >= 1e9  then return (string.format("%.1f", n/1e9 ):gsub("%.0$", "")) .. "g"
  elseif n >= 1e6  then return (string.format("%.1f", n/1e6 ):gsub("%.0$", "")) .. "m"
  elseif n >= 1e3  then return (string.format("%.1f", n/1e3 ):gsub("%.0$", "")) .. "k"
  else return tostring(n)
  end
end

local function UpdateCoordText(frame, coordText)
  if not frame or not coordText then return end
  local x = frame:GetLeft()
  local y = frame:GetBottom()
  local ux = UIParent:GetLeft()  or 0
  local uy = UIParent:GetBottom() or 0
  local w, h = frame:GetSize()
  coordText:SetText(string.format("x:%.0f y:%.0f  %dx%d", x-ux, y-uy, w, h))
end

local function UpdateBarFill()
  if not xpBar then return end
  if petMode then
    local pd = GetPetXPData()
    if pd then
      isCompanionMode, isRepMode = false, false
      xpBar:SetValue(pd.pct)
      UpdateBarColor()
      if sparkTex and gainPhase == "idle" then sparkTex:Hide() end
      return
    end
  end
  if IsMaxLevel() then
    local comp = GetCompanionXPData()
    if comp then
      isCompanionMode = true
      isRepMode = false
      xpBar:SetValue(comp.pct)
      UpdateBarColor()
      if sparkTex and gainPhase == "idle" then sparkTex:Hide() end
      return
    end
    isCompanionMode = false
    local rep = GetActiveRepData()
    isRepMode = (rep ~= nil)
    xpBar:SetValue(rep and rep.pct or 0)
    UpdateBarColor()
    if sparkTex and gainPhase == "idle" then sparkTex:Hide() end
    return
  end
  isRepMode = false
  isCompanionMode = false
  local xp    = UnitXP("player")
  local maxXP = UnitXPMax("player")
  local pct   = (maxXP > 0) and (xp / maxXP) or 0
  xpBar:SetValue(pct)
  UpdateBarColor()
  if sparkTex and gainPhase == "idle" then
    sparkTex:Hide()
  end
end

-- Entree / sortie des elements du survol : fondu + leger glissement vers le haut, decales entre eux
-- (fond, puis textes). Chaque cle (tooltipFrame, centerXPText) a une progression p dans [0,1].
local FADE_IN, FADE_OUT = 0.3, 0.2
local SLIDE = 8
local fades, fadeP, hookedFade = {}, {}, {}
local fadeDriver

local function Eased(p, delay)
  local v = (p - delay) / (1 - 0.4)
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  return 1 - (1 - v) * (1 - v)
end

local function ApplyFade(obj, p)
  if obj == centerXPText then
    local e = Eased(p, 0.1)
    obj:SetAlpha(e)
    obj:ClearAllPoints()
    obj:SetPoint("CENTER", obj:GetParent(), "CENTER", 0, -SLIDE * (1 - e))
  elseif obj == nlPanel or obj == qPanel then
    obj:SetAlpha(Eased(p, 0))
  elseif obj == tooltipFrame then
    local eBg, eTxt, eRest = Eased(p, 0), Eased(p, 0.2), Eased(p, 0.4)
    ttTex:SetAlpha(eBg)
    tooltipXP:SetAlpha(eTxt)
    tooltipXP:ClearAllPoints()
    tooltipXP:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 32, -12 - SLIDE * (1 - eTxt))
    tooltipRested:SetAlpha(eRest)
    tooltipRested:ClearAllPoints()
    tooltipRested:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 10, -26 - SLIDE * (1 - eRest))
  end
end

local function FadeStep(_, el)
  for obj, to in pairs(fades) do
    local p = fadeP[obj] or 0
    if to == 1 then p = math.min(1, p + el / FADE_IN) else p = math.max(0, p - el / FADE_OUT) end
    fadeP[obj] = p
    ApplyFade(obj, p)
    if p == to then
      fades[obj] = nil
      if to == 0 then fadeP[obj] = 1; ApplyFade(obj, 1); obj:Hide() end
    end
  end
  if not next(fades) then fadeDriver:SetScript("OnUpdate", nil) end
end

local function FadeTo(obj, show)
  if not obj then return end
  if not fadeDriver then fadeDriver = CreateFrame("Frame") end
  if not hookedFade[obj] then
    hookedFade[obj] = true
    -- Quelle que soit la facon dont l'objet est cache, on le remet dans son etat nominal : les
    -- affichages directs (mode layout) le retrouvent complet.
    if obj.HookScript then
      obj:HookScript("OnHide", function() fades[obj] = nil; fadeP[obj] = 1; ApplyFade(obj, 1) end)
    end
  end
  if show then
    if not obj:IsShown() then fadeP[obj] = 0; ApplyFade(obj, 0); obj:Show() end
    if (fadeP[obj] or 1) >= 1 and not fades[obj] then return end
  else
    if not obj:IsShown() then fades[obj] = nil; return end
  end
  fades[obj] = show and 1 or 0
  fadeDriver:SetScript("OnUpdate", FadeStep)
end

local function UpdateTooltip()
  if not tooltipFrame then return end
  if petMode then
    local pd = GetPetXPData()
    if pd then
      tooltipXP:SetText(string.format(L["XP_TOOLTIP_TOTAL"], string.format("%.2f%%", pd.pct * 100)))
      if pd.loyalty then
        tooltipRested:SetText(pd.loyalty)
        tooltipRested:SetTextColor(0.40, 0.80, 1.00, 1)
        tooltipRested:Show()
        tooltipFrame:SetHeight(48)
      else
        tooltipRested:Hide()
        tooltipFrame:SetHeight(28)
      end
      FadeTo(tooltipFrame, true)
      if centerXPText then
        centerXPText:SetText(string.format("[ %s  /  %s ]", ShortNum(pd.xp), ShortNum(pd.maxXP)))
        FadeTo(centerXPText, true)
      end
      return
    end
  end
  if IsMaxLevel() then
    -- Priorité 1 (max level) : compagnon de gouffre
    local comp = GetCompanionXPData()
    if comp then
      tooltipXP:SetText(string.format(L["XP_TOOLTIP_COMPANION_LEVEL"], comp.level, comp.maxLevel or 60, comp.pct * 100))
      tooltipRested:Hide()
      tooltipFrame:SetHeight(28)
      FadeTo(tooltipFrame, true)
      if centerXPText then
        centerXPText:SetText(string.format("[ %s  /  %s ]", ShortNum(comp.xp), ShortNum(comp.maxXP)))
        FadeTo(centerXPText, true)
      end
      return
    end
    -- Priorité 2 (max level, pas en gouffre) : réputation
    local rep = GetActiveRepData()
    if not rep then tooltipFrame:Hide(); return end
    -- Ligne 1 : rang + index numérique (si applicable) + pourcentage
    local standingFull = rep.standing
    if rep.rank and rep.rankMax then
      standingFull = standingFull .. string.format(" - %d/%d", rep.rank, rep.rankMax)
    end
    tooltipXP:SetText(standingFull)
    -- Ligne 2 : bataillon ou non
    if rep.isBattalion then
      tooltipRested:SetText(L["XP_BATTALION_REP"])
      tooltipRested:SetTextColor(0.40, 0.80, 1.00, 1)
    else
      tooltipRested:SetText(L["XP_BATTALION_REP_NOT_SHARED"])
      tooltipRested:SetTextColor(0.50, 0.50, 0.50, 1)
    end
    tooltipRested:Show()
    tooltipFrame:SetHeight(48)
    FadeTo(tooltipFrame, true)
    if centerXPText then
      centerXPText:SetText(string.format("[ %s / %s ]  %s  —  %.1f%%",
        ShortNum(rep.cur), ShortNum(rep.max), rep.standing, rep.pct * 100))
      FadeTo(centerXPText, true)
    end
    return
  end
  local xp     = UnitXP("player")
  local maxXP  = UnitXPMax("player")
  local pct    = (maxXP > 0) and (xp / maxXP * 100) or 0
  tooltipXP:SetText(string.format(L["XP_TOOLTIP_TOTAL"], string.format("%.2f%%", pct)))

  local rested    = GetXPExhaustion() or 0
  local restedPct = (maxXP > 0) and (rested / maxXP * 100) or 0
  if restedPct > 0 then
    tooltipRested:SetText(string.format(L["XP_TOOLTIP_RESTED"], string.format("%.2f%%", restedPct)))
    tooltipRested:SetTextColor(0.40, 0.80, 1.00, 1)
    tooltipRested:Show()
    tooltipFrame:SetHeight(48)
  else
    tooltipRested:Hide()
    tooltipFrame:SetHeight(28)
  end
  FadeTo(tooltipFrame, true)

  if centerXPText then
    centerXPText:SetText(string.format("[ %s  /  %s ]", ShortNum(xp), ShortNum(maxXP)))
    FadeTo(centerXPText, true)
  end
end

-- Animations
local function BuildAnimations()
  showAnim = container:CreateAnimationGroup()
  showAnim:SetToFinalAlpha(true)

  local t = showAnim:CreateAnimation("Translation")
  t:SetOffset(0, 20)
  t:SetDuration(ANIM_IN_DUR)
  t:SetSmoothing("IN")
  t:SetOrder(1)

  local a = showAnim:CreateAnimation("Alpha")
  a:SetFromAlpha(0)
  a:SetToAlpha(1)
  a:SetDuration(ANIM_IN_DUR)
  a:SetSmoothing("IN")
  a:SetOrder(1)

  showAnim:SetScript("OnFinished", function()
    container:ClearAllPoints()
    container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    container:SetAlpha(1)
  end)

  hideAnim = container:CreateAnimationGroup()
  hideAnim:SetToFinalAlpha(true)

  local ao = hideAnim:CreateAnimation("Alpha")
  ao:SetFromAlpha(1)
  ao:SetToAlpha(0)
  ao:SetDuration(ANIM_OUT_DUR)
  ao:SetOrder(1)

  hideAnim:SetScript("OnFinished", function()
    container:SetAlpha(1)
    container:Hide()
    if fxModel then fxModel:Hide() end
  end)
end

-- Show / Hide
local function ShowXPBar()
  if IsMaxLevel() and not petMode and not GetCompanionXPData() and not GetActiveRepData() then return end
  if not container then return end

  -- Si deja completement visible (hors anim en cours), juste maj du fill sans relancer l'entree
  local alreadyVisible = container:IsVisible()
                      and container:GetAlpha() > 0.5
                      and not (hideAnim and hideAnim:IsPlaying())
                      and not (showAnim and showAnim:IsPlaying())
  if alreadyVisible then
    UpdateBarFill()
    if fxModel then fxModel:Show() end
    -- Relance l'anim de gain si gainAnimFrame a été stoppé (ex : autre addon qui cache/reaffiche l'UI)
    if gainAnimFrame and gainPhase ~= "idle" and not gainAnimFrame:IsVisible() then
      gainAnimFrame:Show()
    end
    return
  end

  -- Barre cachee ou en transition : lancer l'animation d'entree
  if hideAnim and hideAnim:IsPlaying() then
    hideAnim:Stop()
  end
  UpdateBarFill()
  container:SetAlpha(0)
  container:ClearAllPoints()
  container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, -20)
  container:Show()
  if showAnim then
    showAnim:Stop()
    showAnim:Play()
  end
  if fxModel then fxModel:Show() end
  -- Reprendre l'animation de gain si elle était en cours quand container a été caché
  if gainAnimFrame and gainPhase ~= "idle" then
    gainAnimFrame:Show()
  end

  -- Sécurité : si OnFinished ne fire pas, forcer position/alpha après le délai théorique
  C_Timer.After(ANIM_IN_DUR + 0.05, function()
    if container and container:IsVisible()
       and not (hideAnim and hideAnim:IsPlaying()) then
      container:ClearAllPoints()
      container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
      container:SetAlpha(1)
    end
  end)
end

--- Barre gardee affichee en permanence ? Les details (total au centre, tooltip) restent lies au
--- survol quoi qu'il arrive : seule la barre elle-meme devient permanente.
local function IsAlwaysVisible()
  local cfg = ns.GetCfg("xpBar")
  return cfg and cfg.alwaysVisible == true
end

local function HideXPBar()
  if not container then return end
  if not container:IsVisible() then return end
  if isHovered or petMode then return end
  if IsAlwaysVisible() then return end
  if showAnim and showAnim:IsPlaying() then showAnim:Stop() end
  if hideAnim and not hideAnim:IsPlaying() then
    hideAnim:Play()
  end
end

-- Callback XP
local function OnXPGained()
  if IsMaxLevel() then return end
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.enabled == false then return end

  local newXP = UnitXP("player")
  local maxXP = UnitXPMax("player")

  if prevXP and maxXP > 0 then
    local oldPct   = prevXP / maxXP
    local newPct   = newXP  / maxXP
    local deltaPct = newPct - oldPct
    if deltaPct > 0 then
      AnimateXPGain(oldPct, deltaPct)
    end
  end
  prevXP = newXP

  ShowXPBar()
  if showTimer then showTimer:Cancel() end
  showTimer = C_Timer.NewTimer(SHOW_DURATION, function()
    showTimer = nil
    if not isHovered then HideXPBar() end
  end)
end

-- Helpers layout mode
local function MakeBorder(parent, color)
  local b = CreateFrame("Frame", nil, parent)
  b:SetAllPoints(parent)
  b:SetFrameLevel(parent:GetFrameLevel() + 10)
  local thickness = 2
  local sides = { "TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT" }
  local lines = {}
  -- top
  local t = b:CreateTexture(nil, "OVERLAY")
  t:SetHeight(thickness); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
  t:SetColorTexture(unpack(color)); lines[1] = t
  -- bottom
  local bt = b:CreateTexture(nil, "OVERLAY")
  bt:SetHeight(thickness); bt:SetPoint("BOTTOMLEFT"); bt:SetPoint("BOTTOMRIGHT")
  bt:SetColorTexture(unpack(color)); lines[2] = bt
  -- left
  local lt = b:CreateTexture(nil, "OVERLAY")
  lt:SetWidth(thickness); lt:SetPoint("TOPLEFT"); lt:SetPoint("BOTTOMLEFT")
  lt:SetColorTexture(unpack(color)); lines[3] = lt
  -- right
  local rt = b:CreateTexture(nil, "OVERLAY")
  rt:SetWidth(thickness); rt:SetPoint("TOPRIGHT"); rt:SetPoint("BOTTOMRIGHT")
  rt:SetColorTexture(unpack(color)); lines[4] = rt
  b:Hide()
  return b
end

local function MakeResizeHandle(parent, onStop)
  local h = CreateFrame("Frame", nil, parent)
  h:SetSize(14, 14)
  h:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  h:SetFrameLevel(parent:GetFrameLevel() + 20)
  local hTex = h:CreateTexture(nil, "OVERLAY")
  hTex:SetAllPoints()
  hTex:SetColorTexture(1, 0.6, 0, 0.9)
  h:EnableMouse(true)
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnEnter", function() hTex:SetColorTexture(1, 1, 0, 1) end)
  h:SetScript("OnLeave", function() hTex:SetColorTexture(1, 0.6, 0, 0.9) end)
  h:SetScript("OnDragStart", function()
    parent:SetResizable(true)
    parent:SetResizeBounds(20, 20)
    parent:StartSizing("BOTTOMRIGHT")
  end)
  h:SetScript("OnDragStop", function()
    parent:StopMovingOrSizing()
    if onStop then onStop() end
  end)
  h:Hide()
  return h
end

local function MakeCoordText(parent)
  local f = parent:CreateFontString(nil, "OVERLAY")
  f:SetFont(xpFontInfo, 10, "OUTLINE")
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
  f:SetTextColor(1, 1, 0, 1)
  f:SetShadowOffset(1, -1)
  f:Hide()
  return f
end

-- Callbacks inner (extraits de Create pour ne pas depasser 60 upvalues)
local function OnGainUpdate(self, dt)
  gainElapsed = gainElapsed + dt
  -- Pulse de base (0.4 -> 1.0), modifie par phase
  local pulse = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(gainElapsed * SPARK_PULSE_SPEED * math.pi * 2))
  if gainPhase == "grow" then
    local p     = math.min(gainElapsed / GAIN_ANIM_GROW_DUR, 1)
    local eased = 1 - (1 - p) ^ 3
    local w = math.max(1, gainTargetW * eased)
    gainBar:SetWidth(w)
    if sparkTex then
      sparkTex:ClearAllPoints()
      sparkTex:SetPoint("CENTER", container, "LEFT", gainStartX + w, 0)
      sparkTex:SetAlpha(pulse)
    end
    if p >= 1 then
      gainPhase   = "hold"
      gainElapsed = 0
    end
  elseif gainPhase == "hold" then
    if sparkTex then
      sparkTex:ClearAllPoints()
      sparkTex:SetPoint("CENTER", container, "LEFT", gainStartX + gainTargetW, 0)
      sparkTex:SetAlpha(pulse)
    end
    if gainElapsed >= GAIN_ANIM_HOLD_DUR then
      gainPhase   = "fade"
      gainElapsed = 0
    end
  elseif gainPhase == "fade" then
    local p = math.min(gainElapsed / GAIN_ANIM_FADE_DUR, 1)
    gainBar:SetAlpha(1 - p)
    -- Spark : pulse multiplie par le facteur de fondu -> s'eteint progressivement
    if sparkTex then
      sparkTex:SetAlpha(pulse * (1 - p))
    end
    if p >= 1 then
      gainPhase = "idle"
      gainBar:Hide()
      if sparkTex then sparkTex:Hide() end
      self:Hide()
    end
  end
end

local function OnLbResizeStop()
  SaveLB()
  UpdateCoordText(levelBg, lbCoordText)
  if ns.CallbackRegistry then
    ns.CallbackRegistry:Trigger("SettingChanged", "xpBar", "levelBg",
      ns.DB and ns.DB.xpBar and ns.DB.xpBar.levelBg)
  end
end

local function OnTfResizeStop()
  SaveTF()
  UpdateCoordText(tooltipFrame, tfCoordText)
  if ns.CallbackRegistry then
    ns.CallbackRegistry:Trigger("SettingChanged", "xpBar", "tooltipFrame",
      ns.DB and ns.DB.xpBar and ns.DB.xpBar.tooltipFrame)
  end
end

local function OnLevelBgDragStart(self)
  if isLayoutMode then self:StartMoving() end
end

local function OnLevelBgDragStop(self)
  self:StopMovingOrSizing()
  SaveLB()
  UpdateCoordText(levelBg, lbCoordText)
  if ns.CallbackRegistry then
    ns.CallbackRegistry:Trigger("SettingChanged", "xpBar", "levelBg",
      ns.DB and ns.DB.xpBar and ns.DB.xpBar.levelBg)
  end
end

local function OnTooltipDragStart(self)
  if isLayoutMode then self:StartMoving() end
end

local function OnTooltipDragStop(self)
  self:StopMovingOrSizing()
  SaveTF()
  UpdateCoordText(tooltipFrame, tfCoordText)
  if ns.CallbackRegistry then
    ns.CallbackRegistry:Trigger("SettingChanged", "xpBar", "tooltipFrame",
      ns.DB and ns.DB.xpBar and ns.DB.xpBar.tooltipFrame)
  end
end

-- ═══ Apercu du prochain niveau (survol du niveau) ═════════════════════════════════════════════════
-- Grosse ombre dans le coin bas droit de l'ecran (comme le detail de RestedXP) listant ce que debloque le
-- prochain niveau. Sorts : livre de sorts (sorts "futurs" appris a ce niveau). Gains de PV / stats : aucune
-- API ne les donne a l'avance, on affiche donc ceux du DERNIER niveau gagne (releves a chaque PLAYER_LEVEL_UP,
-- sauvegardes par personnage) comme estimation. Les tables livrees (Data/LevelGains.lua) passent avant ce repli.

-- Gains de niveau SANS equipement ni buffs : les arguments de PLAYER_LEVEL_UP ne distinguent pas ce qui vient du niveau de
-- ce qu'apporte l'equipement, on fait donc la difference entre deux instantanes de stats DE BASE (stat effective moins bonus
-- positifs et negatifs), pris a chaque connexion puis apres chaque montee de niveau.
-- PV et ressource sont ramenes a la base de la meme facon : on retire ce que l'endurance / l'intelligence de bonus apportent.
local HP_PER_STA, MANA_PER_INT = 10, 15

local function ReadBaseStats()
  local function N(v) return (type(v) == "number" and not (issecretvalue and issecretvalue(v))) and v or nil end
  local base, eff = {}, {}
  for i, k in ipairs({ "str", "agi", "sta", "int", "spi" }) do
    local _, e, pos, neg = UnitStat("player", i)
    e = N(e)
    if not e then return nil end
    eff[k] = e
    base[k] = e - (N(pos) or 0) - (N(neg) or 0)
  end
  local maxHP = N(UnitHealthMax("player"))
  if maxHP then base.hp = maxHP - HP_PER_STA * (eff.sta - base.sta) end
  if UnitPowerType and UnitPowerType("player") == 0 then
    local mp = N(UnitPowerMax("player", 0))
    if mp then base.power = mp - MANA_PER_INT * (eff.int - base.int) end
  end
  base.level = UnitLevel("player")
  return base
end

local function SnapshotBaseStats()
  local snap = ReadBaseStats()
  if not snap then return end
  AishUILearnDB = AishUILearnDB or { learnedDurations = {}, verbose = false }
  AishUILearnDB.baseSnap = snap
end

local function RecordLevelGains(level, _, _, talents)
  -- Le jeu met les stats a jour un instant apres l'evenement
  C_Timer.After(2, function()
    local now = ReadBaseStats()
    if not now then return end
    AishUILearnDB = AishUILearnDB or { learnedDurations = {}, verbose = false }
    local prev = AishUILearnDB.baseSnap
    AishUILearnDB.baseSnap = now
    -- Pas d'instantane du niveau precedent (premiere fois, ou niveaux pris hors connexion) : rien a comparer
    if not (prev and type(level) == "number" and prev.level == level - 1 and now.level == level) then return end
    -- v = 2 : gains sans equipement. Les anciens releves (sans v) incluaient l'equipement et sont ignores.
    local gains = { v = 2, level = level, talents = (type(talents) == "number" and talents ~= 0) and talents or nil }
    for _, k in ipairs({ "hp", "power", "str", "agi", "sta", "int", "spi" }) do
      if now[k] and prev[k] then
        local d = now[k] - prev[k]
        if d < 0 or d > ((k == "hp" or k == "power") and 1000 or 50) then return end   -- mesure incoherente
        if d > 0 then gains[k] = d end
      end
    end
    AishUILearnDB.levelGains = gains
    -- Memoire du compte : gains releves par classe ET par niveau. Aucune table des gains n'existe cote client (ils sont
    -- calcules par le serveur) : chaque personnage qui monte complete la liste, et le panneau affiche la valeur exacte
    -- releve pour ce niveau de cette classe quand elle existe (sinon l'estimation des tables livrees, Data/LevelGains.lua).
    local cf = select(2, UnitClass("player"))
    if cf and AishaddonDB then
      AishaddonDB.levelGainsByClass = AishaddonDB.levelGainsByClass or {}
      AishaddonDB.levelGainsByClass[cf] = AishaddonDB.levelGainsByClass[cf] or {}
      AishaddonDB.levelGainsByClass[cf][level] = gains
    end
  end)
end

-- Sorts a venir releves chez l'entraineur de classe : le livre de sorts de Forever ne liste que les sorts deja
-- appris (aucun sort "futur"), l'entraineur est la seule source d'un niveau d'apprentissage. A chaque ouverture
-- on memorise, par niveau requis, les sorts pas encore appris, pour TOUT LE COMPTE et par classe
-- (AishaddonDB.futureSpells[classe]) : un seul passage par classe suffit, tous les personnages en profitent.
-- Le spellID (extrait du lien du sort) rend la donnee independante de la langue.
-- Donnees livrees avec l'addon (optionnel) : ns.ClassSpellLevels[classe][niveau] = { spellID, ... }.
-- Retail : pas d'entraineur de classe ni de rangs, tout s'apprend en montant de niveau, et le livre de sorts liste lui-meme les
-- sorts "futurs" avec leur niveau (C_SpellBook). Releves d'entraineur, donnees livrees (build Forever) et mode Maj n'ont alors
-- aucun sens. Detection par API plutot que par nom de client.
-- Forever expose ces API (moteur moderne) mais son livre de sorts ne liste aucun sort futur : on force les entraineurs.
local HAS_CLASS_TRAINERS = ns.IsForever or not (C_SpellBook and C_SpellBook.GetSpellBookItemLevelLearned
                                and Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell)

-- Competences d'armes (Forever), apprises chez un maitre d'armes : niveau 1 et 10 pa, sauf les armes d'hast (niveau 20,
-- 1 po). Classes autorisees par arme. Donnees reprises de l'addon WhatsTraining (Classes/WeaponSkills.lua, regles "era").
-- Une seule table (et pas des locales) : le fichier est a la limite des 200 locales.
XPBar.WEAPON_SKILLS = {
  { id = 196,   classes = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, SHAMAN = 1 } },                          -- haches a une main
  { id = 197,   classes = { WARRIOR = 1, PALADIN = 1, HUNTER = 1 } },                                      -- haches a deux mains
  { id = 198,   classes = { WARRIOR = 1, PALADIN = 1, ROGUE = 1, PRIEST = 1, SHAMAN = 1, DRUID = 1 } },     -- masses a une main
  { id = 199,   classes = { WARRIOR = 1, PALADIN = 1, DRUID = 1 } },                                       -- masses a deux mains
  { id = 201,   classes = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, ROGUE = 1, MAGE = 1, WARLOCK = 1 } },    -- epees a une main
  { id = 202,   classes = { WARRIOR = 1, PALADIN = 1, HUNTER = 1 } },                                      -- epees a deux mains
  { id = 1180,  classes = { WARRIOR = 1, HUNTER = 1, ROGUE = 1, PRIEST = 1, SHAMAN = 1, DRUID = 1, WARLOCK = 1, MAGE = 1 } }, -- dagues
  { id = 15590, classes = { WARRIOR = 1, HUNTER = 1, ROGUE = 1, SHAMAN = 1, DRUID = 1 } },                 -- armes de pugilat
  { id = 227,   classes = { WARRIOR = 1, HUNTER = 1, PRIEST = 1, SHAMAN = 1, DRUID = 1, WARLOCK = 1, MAGE = 1 } }, -- batons
  { id = 200,   classes = { WARRIOR = 1, PALADIN = 1, HUNTER = 1, DRUID = 1 }, level = 20, cost = 10000 },  -- armes d'hast
  { id = 264,   classes = { WARRIOR = 1, HUNTER = 1, ROGUE = 1 } },                                        -- arcs
  { id = 266,   classes = { WARRIOR = 1, HUNTER = 1, ROGUE = 1 } },                                        -- armes a feu
  { id = 5011,  classes = { WARRIOR = 1, HUNTER = 1, ROGUE = 1 } },                                        -- arbaletes
  { id = 2567,  classes = { WARRIOR = 1, HUNTER = 1, ROGUE = 1 } },                                        -- armes de jet
}

-- Villes des maitres d'armes (donnees "era" de WhatsTraining) : id de zone (GetAreaInfo, nom localise), carte de repli
local WEAPON_CITY = {
  IF = { 1537, 1455 }, SW = { 1519, 1453 }, DARN = { 1657, 1457 },
  ORG = { 1637, 1454 }, TB = { 1638, 1456 }, UC = { 1497, 1458 },
}
local WEAPON_TRAINERS = {
  [196]   = { Alliance = { "IF" },               Horde = { "ORG" } },
  [197]   = { Alliance = { "IF" },               Horde = { "ORG" } },
  [198]   = { Alliance = { "IF" },               Horde = { "TB" } },
  [199]   = { Alliance = { "IF" },               Horde = { "TB" } },
  [201]   = { Alliance = { "SW" },               Horde = { "UC" } },
  [202]   = { Alliance = { "SW" },               Horde = { "UC" } },
  [1180]  = { Alliance = { "IF", "SW", "DARN" }, Horde = { "ORG", "UC" } },
  [15590] = { Alliance = { "IF", "DARN" },       Horde = { "ORG" } },
  [227]   = { Alliance = { "SW", "DARN" },       Horde = { "ORG", "TB" } },
  [200]   = { Alliance = { "SW" },               Horde = { "UC" } },
  [264]   = { Alliance = { "DARN" },             Horde = { "ORG" } },
  [266]   = { Alliance = { "IF" },               Horde = { "TB" } },
  [5011]  = { Alliance = { "IF", "SW" },         Horde = { "UC" } },
  [2567]  = { Alliance = { "IF", "DARN" },       Horde = { "ORG" } },
}

local function CityName(key)
  local c = WEAPON_CITY[key]
  local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(c[1])
  if not name or name == "" then
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(c[2])
    name = info and info.name
  end
  return name or key
end

-- Villes (noms localises, faction du joueur) ou un maitre d'armes enseigne cette competence ; nil si inconnue
function XPBar.WeaponCities(id)
  local t = WEAPON_TRAINERS[id]
  local list = t and t[UnitFactionGroup("player") or ""]
  if not list then return nil end
  local out = {}
  for i, key in ipairs(list) do out[i] = CityName(key) end
  return out
end

-- Competences d'armes de la classe du joueur, pas encore apprises, dont le niveau requis est entre lo et hi.
-- Renvoie une liste { id, name, icon, cost, level, weapon = true, cities }. Forever uniquement (maitres d'armes).
function XPBar.WeaponUnlocks(lo, hi)
  local out = {}
  if not HAS_CLASS_TRAINERS then return out end
  local cf = select(2, UnitClass("player"))
  for _, w in ipairs(XPBar.WEAPON_SKILLS) do
    local lvl = w.level or 1
    if w.classes[cf] and lvl >= lo and lvl <= hi then
      local known = (IsPlayerSpell and IsPlayerSpell(w.id)) or (IsSpellKnown and IsSpellKnown(w.id))
      local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(w.id)
      if not known and name then
        out[#out + 1] = { id = w.id, name = name, icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(w.id),
                          cost = w.cost or 1000, level = lvl, weapon = true, cities = XPBar.WeaponCities(w.id) }
      end
    end
  end
  return out
end

local function ScanTrainerSpells()
  if not HAS_CLASS_TRAINERS then return end
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceLevelReq) then return end
  if IsTradeskillTrainer and IsTradeskillTrainer() then return end      -- metiers : pas des sorts de classe
  local n = GetNumTrainerServices() or 0
  if n <= 0 then return end
  local classFile = select(2, UnitClass("player"))
  if not (classFile and AishaddonDB) then return end
  local byLevel, total = {}, 0
  for i = 1, n do
    -- Sur Forever le 2e retour est la CATEGORIE ("available" / "unavailable" / "used" / "header"), pas le rang :
    -- on la cherche parmi les retours suivants, et le rang n'est retenu que s'il en reste une autre chaine.
    local name, r2, r3 = GetTrainerServiceInfo(i)
    local CAT = { available = true, unavailable = true, used = true, header = true }
    local category = (CAT[r2] and r2) or (CAT[r3] and r3) or nil
    local rank = (type(r2) == "string" and not CAT[r2] and r2) or (type(r3) == "string" and not CAT[r3] and r3) or nil
    if type(name) == "string" and category ~= "header" then
      local lvl = GetTrainerServiceLevelReq(i)
      if type(lvl) == "number" and lvl > 0 then
        local row = byLevel[lvl]
        if not row then row = {}; byLevel[lvl] = row end
        local id
        if GetTrainerServiceItemLink then
          local link = GetTrainerServiceItemLink(i)
          id = type(link) == "string" and tonumber(link:match("spell:(%d+)")) or nil
        end
        local cost = GetTrainerServiceCost and select(1, GetTrainerServiceCost(i)) or nil
        row[#row + 1] = { id = id, name = name, rank = (type(rank) == "string" and rank ~= "") and rank or nil,
                          icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil,
                          cost = (type(cost) == "number" and cost > 0) and cost or nil,
                          used = (category == "used") or nil }     -- deja appris : releve quand meme (liste complete de l'entraineur)
        total = total + 1
      end
    end
  end
  if total == 0 then return end
  -- FUSION avec les releves precedents (jamais d'ecrasement) : un personnage de haut niveau, qui a tout appris, voit toute
  -- la liste de l'entraineur ; un personnage de bas niveau complete ce qu'il voit en plus.
  AishaddonDB.futureSpells = AishaddonDB.futureSpells or {}
  local old = AishaddonDB.futureSpells[classFile] or {}
  for lvl, row in pairs(byLevel) do
    local dst = old[lvl]
    if not dst then
      old[lvl] = row
    else
      for _, e in ipairs(row) do
        local found
        for _, d in ipairs(dst) do
          if d.name == e.name and d.icon == e.icon and d.rank == e.rank then found = d; break end
        end
        if found then
          found.used = e.used
          found.cost = e.cost or found.cost
          found.id = e.id or found.id
        else
          dst[#dst + 1] = e
        end
      end
    end
  end
  AishaddonDB.futureSpells[classFile] = old
end

local trainerEvt = CreateFrame("Frame")
trainerEvt:SetScript("OnEvent", function() pcall(ScanTrainerSpells) end)
for _, ev in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do pcall(trainerEvt.RegisterEvent, trainerEvt, ev) end

-- Retail : les `maxN` prochains sorts a debloquer en montant de niveau (sorts "futurs" du livre de sorts), du plus
-- proche au plus lointain, chacun avec son niveau d'apprentissage (affiche a la place du rang, inexistant sur Retail).
-- Renvoie une liste { id, name, icon, rank = "Niveau 25" }.
local function UpcomingSpells(maxN)
  local list, seen = {}, {}
  local SB = C_SpellBook
  local T = Enum and Enum.SpellBookItemType
  if not (SB and T and T.FutureSpell and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo
          and SB.GetSpellBookItemInfo and SB.GetSpellBookItemLevelLearned) then return list end
  local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local cur = UnitLevel("player") or 0
  pcall(function()
    for line = 1, SB.GetNumSpellBookSkillLines() do
      local li = SB.GetSpellBookSkillLineInfo(line)
      if li and (not li.offSpecID or li.offSpecID == 0) then
        for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
          local info = SB.GetSpellBookItemInfo(slot, bank)
          if info and info.itemType == T.FutureSpell and info.spellID and not seen[info.spellID] then
            local lvl = SB.GetSpellBookItemLevelLearned(slot, bank)
            if type(lvl) == "number" and lvl > cur then
              seen[info.spellID] = true
              list[#list + 1] = { id = info.spellID, name = info.name, icon = info.iconID, lvl = lvl }
            end
          end
        end
      end
    end
  end)
  table.sort(list, function(a, b)
    if a.lvl ~= b.lvl then return a.lvl < b.lvl end
    return (a.name or "") < (b.name or "")
  end)
  local out = {}
  for i = 1, math.min(maxN, #list) do
    local e = list[i]
    e.rank = string.format(L["XP_NL_UNLOCK_LEVEL"], e.lvl)
    out[i] = e
  end
  return out
end

-- Sorts appris au niveau `lvl` : sorts "futurs" du livre de sorts (Retail), sinon ceux releves chez l'entraineur.
-- Renvoie une liste { id, name, icon, rank }.
local function SpellsLearnedAtLevel(lvl)
  local out, seen = {}, {}
  local SB = C_SpellBook
  local T = Enum and Enum.SpellBookItemType
  if not (SB and T and T.FutureSpell and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo
          and SB.GetSpellBookItemInfo and SB.GetSpellBookItemLevelLearned) then return out end
  local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  pcall(function()
    for line = 1, SB.GetNumSpellBookSkillLines() do
      local li = SB.GetSpellBookSkillLineInfo(line)
      if li and (not li.offSpecID or li.offSpecID == 0) then
        for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
          local info = SB.GetSpellBookItemInfo(slot, bank)
          if info and info.itemType == T.FutureSpell and info.spellID and not seen[info.spellID] then
            if SB.GetSpellBookItemLevelLearned(slot, bank) == lvl then
              seen[info.spellID] = true
              out[#out + 1] = { id = info.spellID, name = info.name, icon = info.iconID }
            end
          end
        end
      end
    end
  end)
  if #out == 0 and HAS_CLASS_TRAINERS then
    local classFile = select(2, UnitClass("player"))
    -- donnees livrees avec l'addon (spellIDs), sinon celles relevees chez l'entraineur sur ce compte
    -- 1) releves du joueur (dans SA langue)
    -- 0) donnees livrees (Data/ClassSpellLevels.lua) : avec identifiant, le jeu donne nom / icone / rang dans la langue
    --    du joueur ; sans identifiant (rares sorts a competences), nom francais valable en frFR seulement
    local shipped = ns.ClassSpellLevels and ns.ClassSpellLevels[classFile] and ns.ClassSpellLevels[classFile][lvl]
    if shipped then
      for _, e in ipairs(shipped) do
        if e.id then
          local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(e.id)
          local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id)
          if name then out[#out + 1] = { id = e.id, name = name, icon = icon } end
        elseif ns.ClassSpellLevelsLocale == GetLocale() then
          out[#out + 1] = { name = e.name, icon = e.icon }
        end
      end
    end
    local saved = AishaddonDB and AishaddonDB.futureSpells and AishaddonDB.futureSpells[classFile]
    saved = saved and saved[lvl]
    if #out > 0 then
      -- (donnees livrees trouvees)
    elseif saved then
      for _, e in ipairs(saved) do
        if not e.used then
          local name = e.id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(e.id) or e.name
          local icon = e.id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id) or e.icon
          -- anciens releves : le champ "rang" contenait la categorie (available / unavailable / used)
          local rank = (e.rank ~= "unavailable" and e.rank ~= "available" and e.rank ~= "used") and e.rank or nil
          out[#out + 1] = { id = e.id, name = name, rank = rank, icon = icon }
        end
      end
    end
    -- competences d'armes qui se debloquent a ce niveau (maitre d'armes)
    for _, w in ipairs(XPBar.WeaponUnlocks(lvl, lvl)) do out[#out + 1] = w end
  end
  return out
end

-- Pour le toast de niveau (Modules/LevelUpToast.lua) : memes sorts et meme format de nombres que l'apercu
XPBar.SpellsLearnedAtLevel = SpellsLearnedAtLevel
XPBar.ShortNum = ShortNum

-- Badge d'un sort a venir (apercu du prochain niveau, toast de niveau) : "+" pour un sort nouveau, chevron pour un
-- nouveau rang d'un sort deja connu. Connu = le jeu resout son nom (le livre de sorts ne resout que les sorts appris) ;
-- repli sans cette API : rang 2 ou plus. sp.upgrade (booleen) force le choix (exemples de l'apercu).
XPBar.BADGE_PLUS    = "Interface\\AddOns\\AishCore\\Media\\UI\\plus.png"
XPBar.BADGE_CHEVRON = "Interface\\AddOns\\AishCore\\Media\\UI\\chevron.png"
function XPBar.IsSpellUpgrade(sp, rank)
  if type(sp) ~= "table" then return false end
  if sp.upgrade ~= nil then return sp.upgrade and true or false end
  -- Retail : pas de rangs, et les sorts a venir sont deja dans le livre de sorts (leur nom s'y resout) : toujours "+"
  if not HAS_CLASS_TRAINERS then return false end
  local name = sp.name
  if type(name) == "string" and name ~= "" and C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok then return type(info) == "table" and info.spellID ~= nil end
  end
  local n = type(rank) == "string" and tonumber(rank:match("(%d+)")) or nil
  return n ~= nil and n > 1
end
function XPBar.SpellBadge(sp, rank)
  return XPBar.IsSpellUpgrade(sp, rank) and XPBar.BADGE_CHEVRON or XPBar.BADGE_PLUS
end

-- /xpnl : diagnostic de la source des sorts du prochain niveau (livre de sorts)
SLASH_AISHXPNL1 = "/xpnl"
SlashCmdList["AISHXPNL"] = function()
  local P = "|cff33aaff[XPNL]|r "
  local SB = C_SpellBook
  print(P .. string.format("niveau=%s | C_SpellBook=%s FutureSpell=%s GetSpellBookItemLevelLearned=%s GetSpellLevelLearned=%s",
    tostring(UnitLevel("player")), tostring(SB ~= nil), tostring(Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell),
    tostring(SB and SB.GetSpellBookItemLevelLearned ~= nil), tostring(GetSpellLevelLearned ~= nil)))
  local saved = AishaddonDB and AishaddonDB.futureSpells and AishaddonDB.futureSpells[select(2, UnitClass("player"))]
  local nSaved = 0
  if saved then for _, t in pairs(saved) do nSaved = nSaved + #t end end
  print(P .. string.format("entraineur : API=%s/%s/%s | sorts a venir memorises=%d", tostring(GetNumTrainerServices ~= nil),
    tostring(GetTrainerServiceInfo ~= nil), tostring(GetTrainerServiceLevelReq ~= nil), nSaved))
  if not (SB and SB.GetNumSpellBookSkillLines) then return end
  local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local nLines = SB.GetNumSpellBookSkillLines()
  print(P .. "lignes de livre de sorts : " .. tostring(nLines))
  local shown = 0
  for line = 1, nLines do
    local li = SB.GetSpellBookSkillLineInfo(line)
    if li then
      local counts = {}
      local lastFuture
      for slot = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
        local info = SB.GetSpellBookItemInfo(slot, bank)
        local t = info and tostring(info.itemType) or "nil"
        counts[t] = (counts[t] or 0) + 1
        if info and info.itemType == (Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell) and shown < 6 then
          shown = shown + 1
          local lv = SB.GetSpellBookItemLevelLearned and SB.GetSpellBookItemLevelLearned(slot, bank)
          print(P .. string.format("  futur : %s (id %s) niveau=%s", tostring(info.name), tostring(info.spellID), tostring(lv)))
        end
      end
      local parts = {}
      for t, n in pairs(counts) do parts[#parts + 1] = t .. "=" .. n end
      print(P .. string.format("  ligne %d '%s' offSpec=%s items=%d types : %s", line, tostring(li.name), tostring(li.offSpecID),
        li.numSpellBookItems or 0, table.concat(parts, ", ")))
    end
  end
end

-- Le tout vit dans un bloc `do ... end` : sans cela ses ~60 locales depasseraient la limite de 200 du fichier.
local ShowNextLevelPanel, HideNextLevelPanel, ShowQuestPanel, HideQuestPanel, NLSetMode, NLSetAlt
do
local NL = {}
-- ═══ Panneau du prochain niveau : mise en page du mockup ═══════════════════════════════════════════
-- Tout est exprime dans le repere du mockup : coin BAS DROIT de l'ecran (la texture d'ombre de 1024 px est
-- collee dans ce coin, 1 pixel de texture = 1 unite d'interface). dx = distance au bord droit, dy = distance
-- au bord bas. Les blocs s'empilent du bas vers le haut : le cas complet (3 rangees de stats, 2 rangees de
-- sorts) retombe exactement sur le mockup, un cas plus court descend, un plus long remonte.
NL.MEDIA       = "Interface\\AddOns\\AishCore\\Media\\XPBar\\"
NL.TEX_SHADOW  = NL.MEDIA .. "grunge_shadow_big.png"   -- 656x400, collee dans le coin bas droit
NL.TEX_RECT    = NL.MEDIA .. "grunge_shadow_rectangle.png"   -- 621x211, fond du panneau des quetes
NL.TEX_DIVIDER = NL.MEDIA .. "divider_dual.png"       -- 314x129 : deux filets (rangees 0-3 et 124-128)
NL.ICONS = {
  hp = "hp_icon.tga", power = "res_icon.tga", str = "str_icon.tga", agi = "agi_icon.tga",
  sta = "stam_icon.tga", int = "int_icon.tga", spi = "spi_icon.tga",
}
NL.SM          = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\"
NL.TEAL        = { 0.00, 0.89, 0.64 }
NL.CREAM       = { 0.95, 0.86, 0.64 }
NL.BROWN       = { 0.42, 0.30, 0.17 }
NL.DIM         = { 0.62, 0.58, 0.50 }
NL.STATS_RIGHT = { 272, 168, 64 }                   -- dx du bord droit de l'icone, colonnes 1 a 3
NL.STAT_ICON, NL.STAT_ROW_H = 42, 32
NL.LABEL_DX = 10   -- libelles de stats (Alt) : decalage vers la droite, en px
NL.SPELL_ICON, NL.SPELL_ROW_H = 33, 41
-- colonnes de sorts (x = bord gauche de l'icone depuis la gauche du mockup 680 px, tw = largeur du texte)
NL.SPELL_LAYOUT = {
  [3] = { L = { 180, 345, 520 }, tw = { 113, 123, 100 } },
  [2] = { L = { 280, 470 },      tw = { 132, 154 } },
  [1] = { L = { 420 },           tw = { 204 } },
}
NL.W = 680
NL.SHADOW_DUR = 1.6   -- l'ombre arrive plus doucement que le texte : fondu + leger glissement + leger zoom
NL.ANIM_DUR, NL.ANIM_SLIDE, NL.ANIM_STAGGER = 0.65, 22, 1.9   -- duree d'un element, glissement, etirement des decalages
NL.OCRE = { 1, 189 / 255, 116 / 255 }   -- ocre des tooltips XP (#FFBD74) : icones de stats, quetes de difficulte "normale"
NL.GREY = { 72 / 255, 72 / 255, 72 / 255 }       -- "5525xp to" (#484848)

-- Montserrat vient de SharedMedia_MyMedia, que le client n'accepte pas toujours des le premier SetFont (cf.
-- ns.ApplyFontReliable) : la police est reposee apres 2 s et 6 s, et le texte reste en 2002 tant qu'elle manque.
NL.FONT_LIGHT       = NL.SM .. "Montserrat-MediumItalic.ttf"
NL.FONT_BOLD_ITALIC = NL.SM .. "Montserrat-BoldItalic.ttf"
NL.FONT_BOLD        = NL.SM .. "Montserrat-Bold.ttf"
local nlFontSeq = 0

function NL.Text(parent, font, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  if font == ns.FONT_FALLBACK then
    fs:SetFont(font, size, "")
  elseif ns.ApplyFontReliable then
    nlFontSeq = nlFontSeq + 1
    ns.ApplyFontReliable(fs, "NextLevel" .. nlFontSeq, font, size, "")
  else
    local ok, res = pcall(fs.SetFont, fs, font, size, "")
    if not ok or res == false then fs:SetFont(ns.FONT_FALLBACK, size, "") end
  end
  fs:SetTextColor(color[1], color[2], color[3], 1)
  fs:SetJustifyH(justify or "RIGHT")
  fs:SetShadowColor(0, 0, 0, 0.7)
  fs:SetShadowOffset(1, -1)
  return fs
end

-- La barre d'xp (barre, badge de niveau, infobulle, texte central) doit rester visible PAR-DESSUS les panneaux :
-- on la monte d'une strate tant que l'un d'eux est affiche, puis on remet les strates d'origine.
local nlRaised
local nlRaiseUsers = {}
function NL.RaiseXPBar(user)
  nlRaiseUsers[user] = true
  if nlRaised then return end
  nlRaised = {}
  local frames = { container, levelBg, levelText and levelText:GetParent(), tooltipFrame,
                   centerXPText and centerXPText:GetParent() }
  for _, fr in pairs(frames) do
    if fr and fr.GetFrameStrata then
      nlRaised[#nlRaised + 1] = { fr = fr, strata = fr:GetFrameStrata() }
      fr:SetFrameStrata("FULLSCREEN_DIALOG")
    end
  end
end

function NL.RestoreXPBar(user)
  nlRaiseUsers[user] = nil
  if next(nlRaiseUsers) or not nlRaised then return end
  for _, e in ipairs(nlRaised) do e.fr:SetFrameStrata(e.strata) end
  nlRaised = nil
end

-- cellule = prix | icone | nom ; w = largeur de la cellule, L = bord gauche (repere du mockup, 680 px de large)
NL.TRAIN_LAYOUT = {
  [1] = { w = 240, L = { 425 } },
  [2] = { w = 215, L = { 225, 450 } },
  [3] = { w = 172, L = { 120, 298, 476 } },
}
NL.GREY_RANK = { 0.60, 0.60, 0.60 }

local function BuildNextLevelPanel()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(656, 400)
  f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
  f:SetFrameStrata("FULLSCREEN")   -- devant les barres dynamiques, cadres de dialogue...
  f:Hide()
  f:SetScript("OnHide", function() NL.hiding = false; NL.RestoreXPBar("level") end)
  f.shadow = f:CreateTexture(nil, "BACKGROUND")
  f.shadow:SetTexture(NL.TEX_SHADOW)
  f.shadow:SetSize(656, 400)
  f.shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.shadowX, f.shadowY, f.curX, f.curY, f.shadowT = 0, 0, 0, 0, 0

  -- chaque element vit dans sa cellule : c'est elle qui glisse / se fond a l'apparition
  local function Cell()
    local c = CreateFrame("Frame", nil, f)
    c:SetFrameLevel(f:GetFrameLevel() + 2)
    c:Hide()
    return c
  end

  -- titre : "4500 xp to " (Medium Italic) + "level 10" (Bold Italic)
  f.title = Cell()
  f.titleLight = NL.Text(f.title, NL.FONT_LIGHT, 21, NL.GREY, "RIGHT")        -- "5525 xp to" : plus petit
  f.titleBold = NL.Text(f.title, NL.FONT_BOLD_ITALIC, 28, NL.CREAM, "RIGHT")   -- "level 10"
  f.titleBold:SetPoint("BOTTOMRIGHT", f.title, "BOTTOMRIGHT", 0, 0)
  f.titleLight:SetPoint("BOTTOMRIGHT", f.titleBold, "BOTTOMLEFT", 0, 1)       -- meme ligne de base

  -- en-tetes (police du jeu) avec leur filet a gauche
  local function Header(r0, r1)
    local c = Cell()
    c.text = NL.Text(c, ns.FONT_FALLBACK, 15, NL.BROWN, "RIGHT")
    c.text:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    c.line = c:CreateTexture(nil, "ARTWORK")
    c.line:SetTexture(NL.TEX_DIVIDER)
    c.line:SetSize(314, r1 - r0)
    -- rognage d'un des deux filets (rangees r0..r1-1 des 129 de la texture) ; le filet finit au bord droit
    c.line:SetTexCoord(0, 1, r0 / 129, r1 / 129)
    c.line:SetPoint("RIGHT", c.text, "LEFT", -8, 0)
    return c
  end
  f.hdrGain = Header(0, 4)
  f.hdrSpells = Header(124, 129)

  -- stats : "+N" Montserrat Bold turquoise puis l'icone a droite
  f.stats = {}
  for i = 1, 7 do
    local c = Cell()
    c:SetSize(104, NL.STAT_ICON)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(NL.STAT_ICON, NL.STAT_ICON)
    c.icon:SetVertexColor(NL.OCRE[1], NL.OCRE[2], NL.OCRE[3], 1)
    c.icon:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    c.value = NL.Text(c, NL.FONT_BOLD, 23, NL.TEAL, "RIGHT")
    -- ancre a la cellule (pas a l'icone) : l'icone glisse avec Alt, le "+N" reste en place
    c.value:SetPoint("RIGHT", c, "RIGHT", -(NL.STAT_ICON - 4), 0)
    -- Alt maintenu : l'icone monte et s'efface, ce texte (PV, FOR, ESP...) arrive par le bas a sa place
    -- Montserrat Bold comme le "+N" s'il est installe, sinon la 2002 (repli fait par NL.Text / ApplyFontReliable)
    c.label = NL.Text(c, NL.FONT_BOLD, 17, NL.OCRE, "LEFT")
    c.label:SetPoint("LEFT", c, "RIGHT", -NL.STAT_ICON + NL.LABEL_DX, 0)   -- justifie a gauche, depuis le bord gauche de l'icone
    c.label:SetAlpha(0)
    f.stats[i] = c
  end

  -- sorts : icone, "+" turquoise au coin, nom (police du jeu) et "(Rang X)" gris dessous
  f.spells = {}
  for i = 1, 12 do
    local c = Cell()
    c:SetHeight(NL.SPELL_ICON)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(NL.SPELL_ICON, NL.SPELL_ICON)
    c.icon:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- badge "+" (sort nouveau) ou chevron (nouveau rang), pose par LayoutLevel (XPBar.SpellBadge)
    c.plus = c:CreateTexture(nil, "OVERLAY")
    c.plus:SetSize(20, 20)
    c.plus:SetPoint("CENTER", c.icon, "TOPRIGHT", -4, -1)
    c.name = NL.Text(c, ns.FONT_FALLBACK, 12, NL.TEAL, "LEFT")
    c.name:SetWordWrap(true)
    c.name:SetMaxLines(2)
    c.rank = NL.Text(c, ns.FONT_FALLBACK, 10, NL.GREY_RANK, "LEFT")
    f.spells[i] = c
  end

  -- competences a entrainer (Maj) : prix a gauche de l'icone, nom + rang a droite
  f.train = {}
  for i = 1, 18 do
    local c = Cell()
    c:SetSize(190, 36)
    c.price = NL.Text(c, ns.FONT_FALLBACK, 11, { 1, 1, 1 }, "RIGHT")
    c.price:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.price:SetWidth(56)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(36, 36)
    c.icon:SetPoint("LEFT", c, "LEFT", 60, 0)
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.name = NL.Text(c, ns.FONT_FALLBACK, 12, NL.TEAL, "LEFT")
    c.name:SetWordWrap(true)
    c.name:SetMaxLines(2)
    c.rank = NL.Text(c, ns.FONT_FALLBACK, 10, NL.GREY_RANK, "LEFT")
    f.train[i] = c
  end
  f.total = Cell()
  f.total:SetSize(300, 24)
  f.totalValue = NL.Text(f.total, ns.FONT_FALLBACK, 16, NL.CREAM, "RIGHT")
  f.totalValue:SetPoint("RIGHT", f.total, "RIGHT", 0, 0)
  f.totalLabel = NL.Text(f.total, ns.FONT_FALLBACK, 16, NL.CREAM, "RIGHT")
  f.totalLabel:SetPoint("RIGHT", f.totalValue, "LEFT", -12, 0)

  -- "..." : des competences ne tiennent pas dans l'affichage (le total, lui, les compte toutes)
  f.more = Cell()
  f.more:SetSize(30, 14)
  f.moreText = NL.Text(f.more, ns.FONT_FALLBACK, 16, NL.CREAM, "RIGHT")
  f.moreText:SetPoint("RIGHT", f.more, "RIGHT", 0, 0)
  f.moreText:SetText("...")

  f.hint = Cell()
  f.hintText = NL.Text(f.hint, ns.FONT_FALLBACK, 13, NL.DIM, "RIGHT")
  f.hintText:SetPoint("RIGHT", f.hint, "RIGHT", 0, 0)
  f.hintText:SetWidth(300)
  f.hintText:SetWordWrap(true)

  f.items = {}
  return f
end

-- Ville(s) du maitre d'armes sous une competence d'arme : boite a la largeur du nom ; un texte plus long defile
-- lentement d'un bout a l'autre (pause aux extremites) au lieu de deborder sur la colonne voisine
NL.CITY_SPEED, NL.CITY_PAUSE = 14, 1.5   -- px/s, s
function NL.CityScroll(clip, el)
  local fs = clip.text
  local over = fs:GetStringWidth() - clip:GetWidth()
  if over <= 0 then return end
  clip.t = clip.t + el
  local sp, pause = NL.CITY_SPEED, NL.CITY_PAUSE
  local run = over / sp
  local t = clip.t % (2 * (pause + run))
  local x
  if t < pause then x = 0
  elseif t < pause + run then x = (t - pause) * sp
  elseif t < 2 * pause + run then x = over
  else x = over - (t - 2 * pause - run) * sp end
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", clip, "LEFT", -x, 0)
end

-- Ligne des villes (sous le nom, a la place du rang) ; renvoie sa hauteur, 0 si rien a afficher
function NL.CityLine(c, cities, tw)
  local txt = type(cities) == "table" and #cities > 0 and table.concat(cities, ", ") or nil
  local cb = c.city
  if not txt then
    if cb then cb:SetScript("OnUpdate", nil); cb:Hide() end
    return 0
  end
  if not cb then
    cb = CreateFrame("Frame", nil, c)
    cb:SetClipsChildren(true)
    cb.text = cb:CreateFontString(nil, "OVERLAY")
    cb.text:SetWordWrap(false)
    cb.text:SetJustifyH("LEFT")
    c.city = cb
  end
  local font, size, flags = c.rank:GetFont()
  cb.text:SetFont(font or "Fonts\\2002.TTF", size or 10, flags or "")
  cb.text:SetTextColor(c.rank:GetTextColor())
  cb.text:SetShadowColor(c.rank:GetShadowColor())
  cb.text:SetShadowOffset(c.rank:GetShadowOffset())
  cb.text:SetText(txt)
  cb:SetSize(tw, cb.text:GetStringHeight() + 2)
  cb.text:ClearAllPoints()
  cb.text:SetPoint("LEFT", cb, "LEFT", 0, 0)
  cb.t = 0
  cb:SetScript("OnUpdate", (cb.text:GetStringWidth() > tw) and NL.CityScroll or nil)
  cb:ClearAllPoints()
  cb:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, 0)
  cb:Show()
  return cb:GetHeight()
end

-- Nom d'un sort + "(Rang X)" sous le nom (gris, plus petit), le bloc etant centre sur l'icone. cities : competence
-- d'arme, villes de son maitre d'armes a la place du rang
function NL.NameBlock(c, name, rank, tw, iconSize, cities)
  c.name:SetWidth(tw)
  c.name:SetText(name or "")
  local r = (type(rank) == "string" and rank ~= "") and rank or nil
  if r then
    if not r:find("^%(") then r = "(" .. r .. ")" end
    c.rank:SetWidth(tw)
    c.rank:SetText(r)
    c.rank:Show()
  else
    c.rank:Hide()
  end
  local cityH = NL.CityLine(c, (not r) and cities or nil, tw)
  local block = c.name:GetStringHeight() + (r and (c.rank:GetStringHeight() + 1) or (cityH > 0 and cityH + 1) or 0)
  c.name:ClearAllPoints()
  c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 6, -math.max(0, (iconSize - block) / 2))
  c.rank:ClearAllPoints()
  c.rank:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -1)
end

-- Prix avec les icones de pieces (or / argent / cuivre) a la suite de chaque montant ; size = hauteur de l'icone
function NL.Money(copper, size)
  copper = math.floor(copper or 0)
  size = size or 12
  local function Coin(tex) return string.format("|TInterface\\MoneyFrame\\%s:%d:%d:2:0|t", tex, size, size) end
  local g, s, k = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. Coin("UI-GoldIcon") end
  if s > 0 then t[#t + 1] = s .. Coin("UI-SilverIcon") end
  if k > 0 or #t == 0 then t[#t + 1] = k .. Coin("UI-CopperIcon") end
  return table.concat(t, " ")
end

-- Place une cellule : coin bas droit a (dx, dy) du coin bas droit de l'ecran
function NL.Place(f, cell, dx, dy, w, h)
  cell.dx, cell.dy = dx, dy
  if w then cell:SetWidth(w) end
  if h then cell:SetHeight(h) end
  cell:ClearAllPoints()
  cell:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -dx, dy)
end

function NL.Add(f, cell, delay)
  cell:SetAlpha(0)
  cell:Show()
  f.items[#f.items + 1] = { cell = cell, delay = delay * NL.ANIM_STAGGER }
end

-- Apparition de l'ombre : fondu + leger glissement + leger zoom (et rattrapage doux de son decalage hors ecran)
function NL.ShadowStep(f)
  local v = f.shadowT / NL.SHADOW_DUR
  if v > 1 then v = 1 end
  local e = 1 - (1 - v) * (1 - v) * (1 - v)
  local sc = 0.97 + 0.03 * e
  f.shadow:SetAlpha(e)
  f.shadow:SetSize(656 * sc, 400 * sc)
  f.shadow:ClearAllPoints()
  f.shadow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", f.curX + (1 - e) * 14, f.curY - (1 - e) * 9)
end

-- Apparition des elements : fondu + glissement depuis la droite, decales d'un element a l'autre.
-- keepShadow : changement de contenu (Maj) -> l'ombre reste, seuls les elements rejouent leur entree.
function NL.Animate(f, keepShadow)
  f.t = 0
  if not keepShadow then
    f.shadowT = 0
    f.curX, f.curY = f.shadowX, f.shadowY
  end
  NL.ShadowStep(f)
  for _, it in ipairs(f.items) do
    it.cell:SetAlpha(0)
    it.cell:ClearAllPoints()
    it.cell:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -it.cell.dx + NL.ANIM_SLIDE, it.cell.dy)
  end
  f:SetScript("OnUpdate", function(self, el)
    self.t = self.t + el
    self.shadowT = self.shadowT + el
    local k = math.min(1, el * 6)
    local dX, dY = self.shadowX - self.curX, self.shadowY - self.curY
    self.curX, self.curY = self.curX + dX * k, self.curY + dY * k
    local pending = self.shadowT < NL.SHADOW_DUR or math.abs(dX) > 0.5 or math.abs(dY) > 0.5
    NL.ShadowStep(self)
    for _, it in ipairs(self.items) do
      local v = (self.t - it.delay) / NL.ANIM_DUR
      if v < 1 then pending = true end
      if v < 0 then v = 0 elseif v > 1 then v = 1 end
      local e = 1 - (1 - v) * (1 - v) * (1 - v)
      it.cell:SetAlpha(e)
      it.cell:ClearAllPoints()
      it.cell:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -it.cell.dx + (1 - e) * NL.ANIM_SLIDE, it.cell.dy)
    end
    if not pending then self:SetScript("OnUpdate", nil) end
  end)
end

-- Competences debloquees mais pas encore apprises : releves a la derniere visite chez l'entraineur
-- (AishaddonDB.futureSpells), niveau requis atteint, sort pas encore connu. Renvoie la liste et le cout total.
-- Rang d'un sort ("Rang 2") : sous-texte du sort ; nil si le sort n'en a pas
function NL.SpellRank(id)
  if not id then return nil end
  local ok, sub = pcall(function()
    if C_Spell and C_Spell.GetSpellSubtext then return C_Spell.GetSpellSubtext(id) end
    if GetSpellSubtext then return GetSpellSubtext(id) end
  end)
  if ok and type(sub) == "string" and sub ~= "" then return sub end
  return nil
end

-- Ajoute a la liste "a entrainer" les competences d'armes non apprises dont le niveau est atteint (maitre d'armes)
function NL.AddWeapons(out, total, lvl)
  for _, w in ipairs(XPBar.WeaponUnlocks(1, lvl)) do
    out[#out + 1] = { name = w.name, icon = w.icon, cost = w.cost, cities = w.cities }
    total = total + (w.cost or 0)
  end
  return out, total
end

function NL.CollectTrainable()
  local out, total = {}, 0
  local cf = select(2, UnitClass("player"))
  local lvl = UnitLevel("player") or 0
  local function IsKnown(id)
    -- IsSpellKnown(id, true) : competences de familier (grimoires du Demoniste), pas dans le livre de sorts du joueur
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and (IsSpellKnown(id) or IsSpellKnown(id, true))) or false
  end

  -- 1) donnees livrees (toutes les classes, cout et rang exacts) : sort vendu, niveau requis atteint, pas encore appris
  local data = ns.ClassSpellLevels and ns.ClassSpellLevels[cf]
  if data then
    -- rang le plus eleve connu par famille de sorts : un rang plus bas est alors remplace, donc deja "connu"
    local knownRank = {}
    for _, list in pairs(data) do
      for _, e in ipairs(list) do
        if e.id and e.f and IsKnown(e.id) then knownRank[e.f] = math.max(knownRank[e.f] or 0, e.r or 0) end
      end
    end
    local levels = {}
    for l in pairs(data) do if type(l) == "number" and l <= lvl then levels[#levels + 1] = l end end
    table.sort(levels)
    for _, l in ipairs(levels) do
      for _, e in ipairs(data[l]) do
        local known, name, icon, rank
        if e.id then
          known = IsKnown(e.id) or (e.f and knownRank[e.f] and (e.r or 0) <= knownRank[e.f]) or false
          name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(e.id)
          icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id)
          rank = NL.SpellRank(e.id)
        elseif ns.ClassSpellLevelsLocale == GetLocale() then
          name, icon = e.name, e.icon
          local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(e.name)
          known = info ~= nil
        else
          known = true      -- nom francais inutilisable dans une autre langue : on ne l'affiche pas
        end
        if not known and name then
          out[#out + 1] = { name = name, icon = icon, rank = rank, cost = e.cost }
          if e.cost then total = total + e.cost end
        end
      end
    end
    return NL.AddWeapons(out, total, lvl)
  end

  -- 2) classe absente des donnees livrees : releves faits par le joueur chez son entraineur
  local saved = AishaddonDB and AishaddonDB.futureSpells and AishaddonDB.futureSpells[cf]
  if not saved then return NL.AddWeapons(out, 0, lvl) end
  local levels = {}
  for l in pairs(saved) do if type(l) == "number" and l <= lvl then levels[#levels + 1] = l end end
  table.sort(levels)
  for _, l in ipairs(levels) do
    for _, e in ipairs(saved[l]) do
      if not e.used and not (e.id and IsKnown(e.id)) then
        local name = e.id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(e.id) or e.name
        local icon = e.id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id) or e.icon
        local rank = (e.rank ~= "unavailable" and e.rank ~= "available" and e.rank ~= "used") and e.rank or nil
        out[#out + 1] = { name = name, icon = icon, rank = rank or NL.SpellRank(e.id), cost = type(e.cost) == "number" and e.cost or nil }
        if type(e.cost) == "number" then total = total + e.cost end
      end
    end
  end
  return NL.AddWeapons(out, total, lvl)
end

local nlMode = "level"     -- "level" : prochain niveau ; "train" : competences a entrainer (Maj enfonce)
NLSetMode = function(mode) nlMode = mode end

-- Alt maintenu : les icones des stats montent en s'effacant, les libelles (PV, FOR, ESP...) les remplacent par le bas.
-- NL.altP = progression 0 (icones) -> 1 (libelles), lissee par un petit pilote.
NL.altP, NL.altTarget = 0, 0
local ALT_SLIDE, ALT_DUR = 12, 0.25
function NL.ApplyStatAlt(f, p)
  if not (f and f.stats) then return end
  local e = 1 - (1 - p) * (1 - p)
  for _, c in ipairs(f.stats) do
    c.icon:SetAlpha(1 - e)
    c.icon:ClearAllPoints()
    c.icon:SetPoint("RIGHT", c, "RIGHT", 0, ALT_SLIDE * e)
    c.label:SetAlpha(e)
    c.label:ClearAllPoints()
    c.label:SetPoint("LEFT", c, "RIGHT", -NL.STAT_ICON + NL.LABEL_DX - (c.labelDX or 0), -ALT_SLIDE * (1 - e))
  end
end
local altDriver = CreateFrame("Frame")
local function AltStep(_, el)
  local t, p = NL.altTarget, NL.altP
  if t > p then p = math.min(t, p + el / ALT_DUR) else p = math.max(t, p - el / ALT_DUR) end
  NL.altP = p
  NL.ApplyStatAlt(nlPanel, p)
  if p == t then altDriver:SetScript("OnUpdate", nil) end
end
NLSetAlt = function(on, instant)
  NL.altTarget = on and 1 or 0
  if instant then
    NL.altP = NL.altTarget
    NL.ApplyStatAlt(nlPanel, NL.altP)
    altDriver:SetScript("OnUpdate", nil)
  elseif NL.altP ~= NL.altTarget then
    altDriver:SetScript("OnUpdate", AltStep)
  end
end

-- Bord gauche de l'ombre (texture 656x400) : distance au bord DROIT de l'ecran selon la hauteur depuis le bas.
local NL_EDGE = { { 0, 595 }, { 50, 573 }, { 100, 537 }, { 150, 481 }, { 200, 414 }, { 250, 385 }, { 300, 367 },
                  { 340, 250 }, { 365, 75 } }
function NL.EdgeAt(h)
  if h <= 0 then return NL_EDGE[1][2] end
  for i = 2, #NL_EDGE do
    local a, b = NL_EDGE[i - 1], NL_EDGE[i]
    if h <= b[1] then return a[2] + (b[2] - a[2]) * (h - a[1]) / (b[1] - a[1]) end
  end
  return 0
end

-- Ombre decalee hors ecran (vers le bas ET vers la droite) : la plus petite qui couvre encore chaque element du contenu
-- avec une petite marge a gauche (15) et au-dessus (30). Le bord gauche est en pente : descendre l'ombre ou la pousser vers la droite
-- la retrecit ; chaque element impose sa propre limite (un titre etroit en haut n'a pas besoin de la largeur des sorts).
function NL.FitShadow(f)
  local boxes, top = {}, 0
  for _, it in ipairs(f.items) do
    local c = it.cell
    local ext = (c.dx or 0) + c:GetWidth()
    if c.line then ext = ext + 8 + 120 end        -- le filet d'un en-tete s'efface vite : on n'en compte qu'une partie
    local t = (c.dy or 0) + c:GetHeight()
    boxes[#boxes + 1] = { left = ext, top = t }
    top = math.max(top, t)
  end
  -- d'abord on descend l'ombre autant que possible (c'est elle qui depasse le plus au-dessus du texte), puis on la
  -- pousse un peu vers la droite avec ce qui reste de marge (au plus 40 px)
  local function Fits(S, X)
    -- le plein de l'ombre monte a ~300 px au bord droit (au-dessus ce ne sont que des eclaboussures)
    if top + S + 30 > 300 then return false end
    for _, bx in ipairs(boxes) do
      if NL.EdgeAt(bx.top + S) - X < bx.left + 15 then return false end
    end
    return true
  end
  local bestS, bestX = 0, 0
  for S = 0, 260, 2 do
    if Fits(S, 0) then bestS = S else break end
  end
  for X = 0, 40, 2 do
    if Fits(bestS, X) then bestX = X else break end
  end
  f.shadowX, f.shadowY = bestX, -bestS
end

function NL.HideAll(f)
  for _, c in ipairs(f.stats) do c:Hide() end
  for _, c in ipairs(f.spells) do c:Hide() end
  for _, c in ipairs(f.train) do c:Hide() end
  f.title:Hide(); f.hdrGain:Hide(); f.hdrSpells:Hide(); f.hint:Hide(); f.total:Hide(); f.more:Hide()
  f.items = {}
end

function NL.LayoutTrain(f, lvlX, lvlY)
  local list, total = NL.CollectTrainable()
  local n = math.min(#list, 18)
  local delay = 0
  -- peu de competences : 1 ou 2 colonnes calees a droite (comme les nouveaux sorts), 3 colonnes a partir de 5
  -- 1 colonne jusqu'a 2, 2 colonnes jusqu'a 8 (plus de lignes plutot que des colonnes trop serrees), 3 au-dela
  local ncols = n <= 2 and 1 or (n <= 8 and 2 or 3)
  local lay = NL.TRAIN_LAYOUT[ncols]
  local Ls, cellW = lay.L, lay.w
  local rows = math.max(1, math.ceil(n / ncols))
  local lastRow = (total > 0) and 76 or 44      -- le total occupe le bas : les rangees remontent d'autant
  local topRow = lastRow + (rows - 1) * NL.SPELL_ROW_H
  local yHdr = (n == 0) and 64 or (topRow + 39)   -- rien a entrainer : en-tete et message serres, en bas

  f.hdrSpells.text:SetText(L["XP_NL_TRAIN"])
  f.hdrSpells:SetSize(f.hdrSpells.text:GetStringWidth() + 4, 24)
  NL.Place(f, f.hdrSpells, 30, yHdr - 12)   -- cale a droite, a quelques pixels du bord (comme les noms de sorts dessous)
  NL.Add(f, f.hdrSpells, delay)
  delay = delay + 0.05

  if n == 0 then
    local cf = select(2, UnitClass("player"))
    local hasData = (ns.ClassSpellLevels and ns.ClassSpellLevels[cf])
                    or (AishaddonDB and AishaddonDB.futureSpells and AishaddonDB.futureSpells[cf]
                        and next(AishaddonDB.futureSpells[cf]) ~= nil)
    f.hintText:SetText(hasData and L["XP_NL_TRAIN_NONE"] or L["XP_NEXTLEVEL_NO_DATA"])
    f.hint:SetSize(300, 40)
    NL.Place(f, f.hint, 30, 40 - 20)
    NL.Add(f, f.hint, delay)
    -- rien a afficher : l'ombre garde exactement la taille du mode normal (sans Maj)
    f.shadowX, f.shadowY = lvlX or 0, lvlY or 0
    return
  end
  for k = 1, n do
    local sp = list[k]
    local c = f.train[k]
    local col = (k - 1) % ncols + 1
    local row = math.ceil(k / ncols)
    c.icon:SetTexture(sp.icon)
    c.price:SetText(sp.cost and NL.Money(sp.cost) or "")
    NL.NameBlock(c, sp.name, sp.rank, cellW - 60 - 36 - 6, 36, sp.cities)
    local cy = lastRow + (rows - row) * NL.SPELL_ROW_H
    NL.Place(f, c, NL.W - (Ls[col] + cellW), cy - 18, cellW)
    NL.Add(f, c, delay + (k - 1) * 0.04)
  end
  if total > 0 then
    f.totalLabel:SetText(L["XP_NL_TOTAL"])
    f.totalValue:SetText(NL.Money(total, 16))
    f.total:SetSize(f.totalLabel:GetStringWidth() + f.totalValue:GetStringWidth() + 34, 24)
    NL.Place(f, f.total, 30, 30 - 12)
    NL.Add(f, f.total, delay + n * 0.04 + 0.05)
  end
  -- plus de competences que de cases : "..." juste au-dessus du coin haut droit du total (qui compte tout)
  if #list > n then
    NL.Place(f, f.more, 30, (total > 0) and 40 or 30)
    NL.Add(f, f.more, delay + n * 0.04 + 0.1)
  end
  -- une ou deux competences SANS total : meme empreinte que le mode normal -> meme ombre ; avec le total (ligne en plus en bas), l'ombre se calcule sur le contenu
  if n <= 2 and total <= 0 and lvlX then
    f.shadowX, f.shadowY = lvlX, lvlY
  else
    NL.FitShadow(f)
  end
end

function NL.LayoutLevel(f)
  local nextLvl = (UnitLevel("player") or 0) + 1
  local okXP, remaining = pcall(function() return (UnitXPMax("player") or 0) - (UnitXP("player") or 0) end)
  if not okXP or type(remaining) ~= "number" or remaining < 0 then remaining = nil end

  -- gains exacts releves pour ce niveau de cette classe (compte entier), sinon estimation : dernier niveau gagne
  local cfc = select(2, UnitClass("player"))
  local byClass = AishaddonDB and AishaddonDB.levelGainsByClass and AishaddonDB.levelGainsByClass[cfc]
  local g = byClass and byClass[nextLvl]
  if g and g.v ~= 2 then g = nil end    -- ancien releve (equipement inclus) : ignore
  if not g then
    -- tables livrees (Data/LevelGains.lua) : estimation par classe et par niveau, avant le repli sur le dernier niveau gagne
    local row = ns.LevelGains and ns.LevelGains[cfc] and ns.LevelGains[cfc][nextLvl]
    if row then
      local function Z(v) return v and v ~= 0 and v or nil end
      g = { hp = Z(row[1]), power = Z(row[2]), str = Z(row[3]), agi = Z(row[4]), sta = Z(row[5]), int = Z(row[6]), spi = Z(row[7]) }
    end
  end
  if not g then
    local last = AishUILearnDB and AishUILearnDB.levelGains
    g = (last and last.v == 2) and last or nil
  end
  local cols = { {}, {}, {} }
  if g then
    if g.hp then cols[1][#cols[1] + 1] = { key = "hp", v = g.hp } end
    if g.power then cols[1][#cols[1] + 1] = { key = "power", v = g.power } end
    local others = {}
    for _, k in ipairs({ "str", "agi", "sta", "int", "spi" }) do
      if g[k] then others[#others + 1] = { key = k, v = g[k] } end
    end
    -- colonnes 2 et 3 : la 3e est toujours la plus fournie (nombre impair -> la derniere colonne prend l'extra)
    local n2 = math.floor(#others / 2)
    for i, s in ipairs(others) do
      local col = (i <= n2) and cols[2] or cols[3]
      col[#col + 1] = s
    end
  end
  local statRows = math.max(#cols[1], #cols[2], #cols[3])
  -- Retail : les 6 prochains sorts du leveling (avec leur niveau) plutot que ceux du seul niveau suivant
  local spells = HAS_CLASS_TRAINERS and SpellsLearnedAtLevel(nextLvl) or UpcomingSpells(6)
  local nSp = #spells
  local spOverflow = nSp > 12
  if nSp > 12 then nSp = 12 end
  local cf = select(2, UnitClass("player"))
  -- Retail : le livre de sorts fait foi, un niveau sans nouveau sort n'est pas un manque de donnees
  local hasData = (not HAS_CLASS_TRAINERS) or (ns.ClassSpellLevels and ns.ClassSpellLevels[cf])
                  or (AishaddonDB and AishaddonDB.futureSpells and AishaddonDB.futureSpells[cf]
                      and next(AishaddonDB.futureSpells[cf]) ~= nil)
  local showSpellBlock = nSp > 0 or not hasData

  -- ----- mise en page, de bas en haut
  local spCols = nSp <= 2 and 1 or (nSp <= 4 and 2 or 3)
  local spRows = nSp > 0 and math.ceil(nSp / spCols) or 1
  local y                                       -- centre de la rangee la plus basse du bloc suivant
  local yHdrSpells, yTopSpell
  if showSpellBlock then
    yTopSpell = 44 + (spRows - 1) * NL.SPELL_ROW_H
    yHdrSpells = yTopSpell + 39
    y = yHdrSpells + 31
  else
    y = 60
  end
  local lastStatRow, yHdrGain, yTitle
  if statRows > 0 then
    lastStatRow = y
    local yTopStat = lastStatRow + (statRows - 1) * NL.STAT_ROW_H
    yHdrGain = yTopStat + 29
    yTitle = yHdrGain + 22
  else
    yTitle = (showSpellBlock and (yHdrSpells + 35)) or 38   -- rien d'autre a afficher : le titre descend vers le bas
  end
  local delay = 0
  -- titre
  f.titleLight:SetText(string.format("%s %s ", remaining and ShortNum(remaining) or "?", L["XP_NL_XPTO"]))
  f.titleBold:SetText(string.format("%s %d", L["XP_NL_LEVEL"], nextLvl))
  -- "niveau N" : couleur de la cle "Barre XP" des Couleurs Thematiques (comme le badge de niveau), sinon creme
  do
    local CLR = ns.Modules and ns.Modules.Colors
    local c = (CLR and CLR.Get and CLR.Get("xpbar")) or NL.CREAM
    f.titleBold:SetTextColor(c[1], c[2], c[3], 1)
  end
  f.title:SetSize(f.titleLight:GetStringWidth() + f.titleBold:GetStringWidth() + 4, 34)
  NL.Place(f, f.title, 52, yTitle - 17 + 10)
  NL.Add(f, f.title, delay)

  -- gains
  if statRows > 0 then
    delay = delay + 0.06
    f.hdrGain.text:SetText(L["XP_NL_GAIN"])
    f.hdrGain:SetSize(f.hdrGain.text:GetStringWidth() + 4, 24)
    NL.Place(f, f.hdrGain, 57, yHdrGain - 12 + 4)
    NL.Add(f, f.hdrGain, delay)
    delay = delay + 0.05
    local idx = 0
    for ci = 1, 3 do
      for ri, s in ipairs(cols[ci]) do
        idx = idx + 1
        local c = f.stats[idx]
        if c then
          c.icon:SetTexture(NL.MEDIA .. NL.ICONS[s.key])
          c.label:SetText(L["XP_STAT_LABEL_" .. s.key] or s.key)
          c.value:SetText("+" .. ShortNum(s.v))
          local cy = lastStatRow + (statRows - ri) * NL.STAT_ROW_H
          NL.Place(f, c, NL.STATS_RIGHT[ci] - 15, cy - NL.STAT_ICON / 2)
          NL.Add(f, c, delay)
          delay = delay + 0.04
        end
      end
    end
  end

  -- sorts
  if showSpellBlock then
    delay = delay + 0.04
    f.hdrSpells.text:SetText(HAS_CLASS_TRAINERS and L["XP_NL_SPELLS"] or L["XP_NL_UPCOMING"])
    f.hdrSpells:SetSize(f.hdrSpells.text:GetStringWidth() + 4, 24)
    NL.Place(f, f.hdrSpells, 53, yHdrSpells - 12)
    NL.Add(f, f.hdrSpells, delay)
    delay = delay + 0.05
    if nSp == 0 then
      f.hintText:SetText(L["XP_NEXTLEVEL_NO_DATA"])
      f.hint:SetSize(300, 40)
      NL.Place(f, f.hint, 53, 44 - 20)
      NL.Add(f, f.hint, delay)
    else
      local lay = NL.SPELL_LAYOUT[spCols]
      local order = (spCols == 3) and { 2, 3, 1 } or { 1, 2 }   -- on remplit d'abord la colonne centrale
      for k = 1, nSp do
        local sp = spells[k]
        local colIdx = order[math.ceil(k / spRows)]
        local row = (k - 1) % spRows + 1
        local c = f.spells[k]
        local tw = lay.tw[colIdx]
        c.icon:SetTexture(sp.icon)
        local rk = sp.rank or (not sp.weapon and NL.SpellRank(sp.id)) or nil
        NL.NameBlock(c, sp.name, rk, tw, NL.SPELL_ICON, sp.cities)
        c.plus:SetTexture(XPBar.SpellBadge(sp, rk))
        local cellW = NL.SPELL_ICON + 6 + tw
        local cy = 44 + (spRows - row) * NL.SPELL_ROW_H
        NL.Place(f, c, NL.W - (lay.L[colIdx] + cellW), cy - NL.SPELL_ICON / 2, cellW)
        NL.Add(f, c, delay + (k - 1) * 0.05)
      end
      -- plus de sorts que de cases : "..." sous la derniere rangee, a droite (meme repere que le total du mode Maj)
      if spOverflow then
        NL.Place(f, f.more, 53, 44 - NL.SPELL_ICON / 2 - 16)
        NL.Add(f, f.more, delay + nSp * 0.05)
      end
    end
  end
  NL.FitShadow(f)
end

-- Rappel des touches, en gris, a droite du badge de niveau pendant le survol
function NL.ShowHint()
  if not NL.hint then
    local h = CreateFrame("Frame", nil, UIParent)
    h:SetSize(10, 16)
    h:SetFrameStrata("TOOLTIP")   -- au-dessus de l'infobulle total / xp reposee, qui est remontee pendant le survol
    h:Hide()
    h.text = NL.Text(h, ns.FONT_FALLBACK, 9, { 0.55, 0.55, 0.55 }, "RIGHT")
    h.text:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.target = 0
    h:SetScript("OnUpdate", function(self, el)
      local a = self:GetAlpha()
      if self.target > a then a = math.min(1, a + el / 0.35) else a = math.max(0, a - el / 0.2) end
      self:SetAlpha(a)
      if a == self.target then
        if a == 0 then self:Hide() end
      end
    end)
    NL.hint = h
  end
  local h = NL.hint
  h.text:SetText(HAS_CLASS_TRAINERS and L["XP_NL_HINT"] or L["XP_NL_HINT_RETAIL"])
  -- meme couleur que la barre d'xp (celle du texte d'xp, cf. UpdateBarColor)
  local r, g, b = 0.55, 0.55, 0.55
  if tooltipXP and tooltipXP.GetTextColor then r, g, b = tooltipXP:GetTextColor() end
  h.text:SetTextColor(r, g, b, 1)
  h:SetWidth(h.text:GetStringWidth() + 4)
  h:ClearAllPoints()
  h:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, BAR_H)   -- coin bas droit, juste au-dessus de la barre d'xp
  if not h:IsShown() then h:SetAlpha(0); h:Show() end
  h.target = 1
end

function NL.HideHint()
  if NL.hint and NL.hint:IsShown() then NL.hint.target = 0 end
end

-- refresh : le panneau est deja affiche (Maj enfonce / relache) -> on garde l'ombre, on remplace le contenu
ShowNextLevelPanel = function(refresh)
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.nextLevelPreview == false then return end
  if IsMaxLevel() then return end
  -- deja affiche et pas en train de disparaitre (survol relance, Alt...) : on ne rejoue pas l'animation
  if not refresh and nlPanel and nlPanel:IsShown() and not NL.hiding then return end
  NL.hiding = false
  if not nlPanel then nlPanel = BuildNextLevelPanel() end
  local f = nlPanel
  f:SetScript("OnUpdate", nil)
  NL.HideAll(f)
  if nlMode == "train" then
    -- on calcule d'abord la mise en page normale pour connaitre la taille d'ombre de reference
    NL.LayoutLevel(f)
    local lx, ly = f.shadowX, f.shadowY
    NL.HideAll(f)
    NL.LayoutTrain(f, lx, ly)
  else
    NL.LayoutLevel(f)
  end
  NL.RaiseXPBar("level")
  if not refresh then NL.ShowHint() end
  if refresh and f:IsShown() then
    NL.Animate(f, true)
  else
    NL.Animate(f)
    FadeTo(f, true)
  end
end

HideNextLevelPanel = function()
  NL.HideHint()
  if nlPanel and nlPanel:IsShown() then NL.hiding = true end
  if nlPanel then FadeTo(nlPanel, false) end
end

-- ═══ Quetes pretes a rendre (ALT enfonce au survol) ═══════════════════════════════════════════════
-- Au-dessus du texte d'xp central : chaque quete terminee avec l'xp qu'elle donnerait, en % de la barre du niveau,
-- puis le total si on rendait tout.
-- 3e/4e retours : quetes EN COURS (pas encore pretes) avec l'xp qu'elles donneraient, et leur total (Retail seulement,
-- affichees avec Maj a la place des competences a entrainer de Forever).
local function GetTurnInQuests()
  local out, totalXP = {}, 0
  local prog, progXP = {}, 0
  local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and select(1, C_QuestLog.GetNumQuestLogEntries()))
            or (GetNumQuestLogEntries and select(1, GetNumQuestLogEntries())) or 0
  for i = 1, n do
    pcall(function()
      local title, level, questID, isHeader, ready, hidden
      if C_QuestLog and C_QuestLog.GetInfo then
        local info = C_QuestLog.GetInfo(i)
        if info then title, level, questID, isHeader, hidden = info.title, info.level, info.questID, info.isHeader, info.isHidden end
        if questID and not isHeader then
          ready = (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID))
                  or (C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID))
        end
      elseif GetQuestLogTitle then
        local t, lv, _, hdr, _, isComplete, _, qid = GetQuestLogTitle(i)
        title, level, isHeader, questID = t, lv, hdr, qid
        ready = (isComplete == 1) or (isComplete == true)
      end
      if not title or isHeader or hidden then return end
      if not ready and ns.IsForever then return end
      local xp
      if GetQuestLogRewardXP and questID then xp = GetQuestLogRewardXP(questID) end
      if (not xp or xp == 0) and GetRewardXP and SelectQuestLogEntry then
        local prev = GetQuestLogSelection and GetQuestLogSelection()
        SelectQuestLogEntry(i)
        xp = GetRewardXP()
        if prev and prev > 0 then SelectQuestLogEntry(prev) end
      end
      if type(xp) == "number" and xp > 0 then
        if ready then
          out[#out + 1] = { title = title, level = level, xp = xp }
          totalXP = totalXP + xp
        else
          prog[#prog + 1] = { title = title, level = level, xp = xp }
          progXP = progXP + xp
        end
      end
    end)
  end
  return out, totalXP, prog, progXP
end

-- Couleur d'une quete selon sa difficulte par rapport au joueur ; "normale" (niveau proche du sien) = ocre #FFBD74
local function QuestColor(level)
  local plvl = UnitLevel("player") or 1
  if type(level) ~= "number" or level <= 0 then return NL.OCRE end
  local d = level - plvl
  if d >= 5 then return { 1.00, 0.10, 0.10 } end          -- impossible
  if d >= 3 then return { 1.00, 0.50, 0.25 } end          -- tres difficile
  if d >= -2 then return NL.OCRE end                      -- normale
  local green = (GetQuestGreenRange and GetQuestGreenRange()) or 8
  if -d <= green then return { 0.25, 0.75, 0.25 } end     -- facile
  return { 0.50, 0.50, 0.50 }                             -- triviale
end

-- Barre turquoise du gain potentiel, posee sur la barre d'xp elle-meme (du remplissage actuel vers actuel + gain)
local potTex, potDrv
local function PotStep(self, el)
  self.t = self.t + el
  if self.mode == "in" then
    local v = math.min(1, self.t / 0.55)
    local e = 1 - (1 - v) * (1 - v) * (1 - v)
    potTex:SetWidth(math.max(1, self.w * e))
    potTex:SetAlpha(0.95 * math.min(1, self.t / 0.25))
    if v >= 1 then self:SetScript("OnUpdate", nil) end
  else
    local v = math.min(1, self.t / 0.3)
    potTex:SetAlpha(0.95 * (1 - v))
    if v >= 1 then potTex:Hide(); self:SetScript("OnUpdate", nil) end
  end
end

function NL.ShowPot(totalXP, xpMax)
  if not xpBar then return end
  if not potTex then
    potTex = xpBar:CreateTexture(nil, "ARTWORK", nil, 1)   -- au-dessus du remplissage, sous le cadre decoratif
    potTex:SetColorTexture(NL.TEAL[1], NL.TEAL[2], NL.TEAL[3], 1)
    potDrv = CreateFrame("Frame")
  end
  local okC, cur = pcall(UnitXP, "player")
  if not okC or type(cur) ~= "number" then return end
  local W = GetBarWidth()
  local frac0 = math.min(1, cur / xpMax)
  local frac1 = math.min(1, (cur + totalXP) / xpMax)
  potTex:ClearAllPoints()
  potTex:SetPoint("TOPLEFT", xpBar, "TOPLEFT", frac0 * W, 0)
  potTex:SetPoint("BOTTOMLEFT", xpBar, "BOTTOMLEFT", frac0 * W, 0)
  potTex:SetWidth(1)
  potTex:SetAlpha(0)
  potTex:Show()
  potDrv.t, potDrv.mode, potDrv.w = 0, "in", math.max(2, (frac1 - frac0) * W)
  potDrv:SetScript("OnUpdate", PotStep)
end

function NL.HidePot()
  if not potTex or not potTex:IsShown() then return end
  potDrv.t, potDrv.mode = 0, "out"
  potDrv:SetScript("OnUpdate", PotStep)
end

local function BuildQuestPanel()
  local q = CreateFrame("Frame", nil, UIParent)
  q:SetFrameStrata("FULLSCREEN")
  q:Hide()
  q:SetScript("OnHide", function() NL.RestoreXPBar("quest") end)
  q.shadow = q:CreateTexture(nil, "BACKGROUND")
  q.shadow:SetTexture(NL.TEX_RECT)
  q.shadow:SetPoint("TOPLEFT", q, "TOPLEFT", -60, 46)
  q.shadow:SetPoint("BOTTOMRIGHT", q, "BOTTOMRIGHT", 60, -28)
  local function Sub()
    local c = CreateFrame("Frame", nil, q)
    c:SetFrameLevel(q:GetFrameLevel() + 2)
    c:Hide()
    return c
  end
  -- en-tete + filet
  q.hdr = Sub()
  q.hdr.text = NL.Text(q.hdr, ns.FONT_FALLBACK, 14, NL.BROWN, "LEFT")
  q.hdr.text:SetPoint("TOPLEFT", q.hdr, "TOPLEFT", 0, 0)
  q.hdr.rule = q.hdr:CreateTexture(nil, "ARTWORK")
  q.hdr.rule:SetTexture(NL.TEX_DIVIDER)
  q.hdr.rule:SetTexCoord(0, 1, 0, 4 / 129)
  -- une ligne par quete : titre colore par difficulte a gauche, "+x%" turquoise a droite
  q.rows = {}
  for i = 1, 15 do
    local r = Sub()
    r.name = NL.Text(r, ns.FONT_FALLBACK, 13, NL.TEAL, "LEFT")
    r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.pct = NL.Text(r, ns.FONT_FALLBACK, 13, NL.TEAL, "RIGHT")
    r.pct:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    q.rows[i] = r
  end
  -- total
  q.tot = Sub()
  q.tot.value = NL.Text(q.tot, ns.FONT_FALLBACK, 17, NL.CREAM, "RIGHT")
  q.tot.value:SetPoint("RIGHT", q.tot, "RIGHT", 0, 0)
  q.tot.label = NL.Text(q.tot, ns.FONT_FALLBACK, 17, NL.CREAM, "RIGHT")
  q.tot.label:SetPoint("RIGHT", q.tot.value, "LEFT", -22, 0)
  return q
end

HideQuestPanel = function()
  if qPanel then FadeTo(qPanel, false) end
  NL.HidePot()
end

-- ALT : quetes pretes a rendre. Maj (Retail, sans entraineur de classe) : quetes en cours, meme presentation.
ShowQuestPanel = function()
  local kind = (IsAltKeyDown() and "ready") or ((not HAS_CLASS_TRAINERS and IsShiftKeyDown()) and "progress") or nil
  if not kind or IsMaxLevel() then HideQuestPanel(); return end
  local ready, readyXP, prog, progXP = GetTurnInQuests()
  local list, totalXP = ready, readyXP
  if kind == "progress" then
    -- les plus rentables d'abord (le panneau n'a que 15 lignes ; le total compte toutes les quetes)
    table.sort(prog, function(a, b) return a.xp > b.xp end)
    list, totalXP = prog, progXP
  end
  local xpMax = (UnitXPMax and UnitXPMax("player")) or 0
  if #list == 0 or xpMax <= 0 then HideQuestPanel(); return end
  if not qPanel then qPanel = BuildQuestPanel() end
  local q = qPanel
  local function Pct(xp)
    local p = xp / xpMax * 100
    if p < 1 then return string.format("+%.1f%%", p) end
    return string.format("+%d%%", math.floor(p + 0.5))
  end
  for _, r in ipairs(q.rows) do r:Hide() end
  q.hdr:Hide(); q.tot:Hide()

  q.hdr.text:SetText(kind == "progress" and string.format(L["XP_QUESTS_IN_PROGRESS"], #list) or L["XP_QUESTS_READY"])
  local nameW = q.hdr.text:GetStringWidth()
  local n = math.min(#list, #q.rows)
  for i = 1, n do
    local e, r = list[i], q.rows[i]
    r.name:SetText(string.format("[%s] %s", tostring(e.level or "?"), e.title))
    local col = QuestColor(e.level)
    r.name:SetTextColor(col[1], col[2], col[3], 1)
    r.pct:SetText(Pct(e.xp))
    nameW = math.max(nameW, r.name:GetStringWidth() + 70)
  end
  q.tot.label:SetText(L["XP_NL_TOTAL"])
  q.tot.value:SetText(Pct(totalXP))
  local W = math.max(190, nameW + 10)
  local LH = 16

  -- positions de base (depuis le coin haut gauche du panneau) ; l'animation les decale vers la gauche
  q.items = {}
  local function Item(frame, w, h, y, delay)
    frame:SetSize(w, h)
    q.items[#q.items + 1] = { f = frame, x = 0, y = y, delay = delay }
    frame:SetAlpha(0)
    frame:Show()
  end
  q.hdr.rule:ClearAllPoints()
  q.hdr.rule:SetPoint("TOPLEFT", q.hdr, "TOPLEFT", 0, -20)
  q.hdr.rule:SetSize(W, 4)
  Item(q.hdr, W, 24, 0, 0.08)
  local y = -32
  for i = 1, n do
    Item(q.rows[i], W, LH, y, 0.2 + (i - 1) * 0.08)
    y = y - LH
  end
  y = y - 4
  Item(q.tot, W, 22, y, 0.2 + n * 0.08 + 0.06)
  q:SetSize(W, -y + 22)
  q:ClearAllPoints()
  q:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BAR_H + 20 + 10)

  -- animation : lignes en glissement leger depuis la gauche (decalees), ombre en glissement leger depuis le bas
  q.t = 0
  q:SetScript("OnUpdate", function(self, el)
    self.t = self.t + el
    local pending = false
    local sv = math.min(1, self.t / 0.9)
    local se = 1 - (1 - sv) * (1 - sv) * (1 - sv)
    self.shadow:SetAlpha(se)
    self.shadow:ClearAllPoints()
    self.shadow:SetPoint("TOPLEFT", self, "TOPLEFT", -60, 46 - (1 - se) * 34)
    self.shadow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 60, -28 - (1 - se) * 34)
    if sv < 1 then pending = true end
    for _, it in ipairs(self.items) do
      local v = (self.t - it.delay) / 0.6
      if v < 1 then pending = true end
      if v < 0 then v = 0 elseif v > 1 then v = 1 end
      local e = 1 - (1 - v) * (1 - v) * (1 - v)
      it.f:SetAlpha(e)
      it.f:ClearAllPoints()
      it.f:SetPoint("TOPLEFT", self, "TOPLEFT", it.x - (1 - e) * 24, it.y)
    end
    if not pending then self:SetScript("OnUpdate", nil) end
  end)
  for _, it in ipairs(q.items) do
    it.f:ClearAllPoints()
    it.f:SetPoint("TOPLEFT", q, "TOPLEFT", it.x - 24, it.y)
  end
  q.shadow:SetAlpha(0)

  NL.RaiseXPBar("quest")
  FadeTo(q, true)
  if totalXP > 0 then NL.ShowPot(totalXP, xpMax) else NL.HidePot() end
end

-- Maj : remplace le contenu du panneau du prochain niveau par les competences a entrainer ; Alt : quetes a rendre
local nlModEvt = CreateFrame("Frame")
nlModEvt:RegisterEvent("MODIFIER_STATE_CHANGED")
nlModEvt:SetScript("OnEvent", function(_, _, key)
  if not isHovered then return end
  if HAS_CLASS_TRAINERS and (key == "LSHIFT" or key == "RSHIFT") then
    local mode = IsShiftKeyDown() and "train" or "level"
    if mode ~= nlMode then
      nlMode = mode
      if nlPanel and nlPanel:IsShown() then ShowNextLevelPanel(true) end
    end
  elseif key == "LALT" or key == "RALT" then
    NLSetAlt(IsAltKeyDown())
    ShowQuestPanel()
  elseif not HAS_CLASS_TRAINERS and (key == "LSHIFT" or key == "RSHIFT") then
    ShowQuestPanel()
  end
end)
end  -- do (panneaux du prochain niveau / des quetes)

local function OnHoverEnter()
  isHovered = true
  -- Mode badge (rep ou compagnon) : remplacer l'abréviation par le nom complet
  if IsMaxLevel() and repNameLabel and levelText then
    local comp = GetCompanionXPData()
    local displayName = comp and comp.name
    if not displayName then
      local rep = GetActiveRepData()
      if rep then displayName = rep.name end
    end
    if displayName then
      levelText:Hide()
      repNameLabel:SetText(string.upper(displayName))
      repNameLabel:Show()
    end
  end
  ShowXPBar()
  UpdateTooltip()
  NLSetMode((HAS_CLASS_TRAINERS and IsShiftKeyDown()) and "train" or "level")
  ShowNextLevelPanel()
  NLSetAlt(IsAltKeyDown())
  ShowQuestPanel()
end

local function OnHoverLeave()
  isHovered = false
  NLSetAlt(false, true)
  HideNextLevelPanel()
  HideQuestPanel()
  -- Restaurer l'abréviation dans le badge
  if repNameLabel then repNameLabel:Hide() end
  if levelText then levelText:Show() end
  if tooltipFrame and not isLayoutMode then FadeTo(tooltipFrame, false) end
  if centerXPText then FadeTo(centerXPText, false) end
  if not showTimer then HideXPBar() end
end

--- Détecte quel compagnon de gouffre gagne de l'XP (UPDATE_FACTION en scénario).
local function TrackCompanionXPGain()
  if not IsMaxLevel() then return end
  if not IsInDelve() then return end
  if not (C_GossipInfo and C_GossipInfo.GetFriendshipReputation) then return end
  for _, fid in ipairs(COMPANION_FACTION_IDS) do
    local okR, fr = pcall(C_GossipInfo.GetFriendshipReputation, fid)
    if okR and fr then
      local cur  = fr.standing or 0
      local prev = companionStandingCache[fid]
      if prev and cur > prev then
        activeCompanionFactionID = fid  -- ce compagnon vient de gagner de l'XP
      end
      companionStandingCache[fid] = cur
    end
  end
end

-- Callback réputation (niveau max) : montre la barre + réinitialise le timer
local function OnRepChanged()
  if not IsMaxLevel() then return end
  if GetCompanionXPData() then return end    -- compagnon prioritaire, ignorer
  local prevLast = lastGainedRepData           -- snapshot avant scan pour détecter un gain
  ScanRepGains()
  local rep = GetActiveRepData()
  if not rep then return end
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.enabled == false then return end
  SetBlizzXPBarHidden(true)  -- événement UPDATE_FACTION peut relâcher la barre Blizz

  local oldRepPct = prevRepPct
  prevRepPct = rep.pct

  UpdateBarFill()  -- synchronise isRepMode + couleur + valeur

  -- S'assure que badge et zone de survol sont visibles (peuvent être cachés entre deux UpdateVisibility)
  if levelBg    and not levelBg:IsVisible()    then levelBg:Show()    end
  if hoverFrame and not hoverFrame:IsVisible() then hoverFrame:Show() end

  -- Rafraîchit le texte/police du badge (lettre de la faction)
  if levelText then
    SetLevelTextFont(13)
    levelText:SetText(rep.letter)
    UpdateXPColors()
  end

  -- ShowXPBar() AVANT AnimateXPGain : gainAnimFrame est enfant de container, inactif si container caché
  ShowXPBar()

  -- Flash turquoise : déclencheur 1 = gain détecté par ScanRepGains (coords via prevPct), déclencheur 2 = fallback sur pct affiché
  local gainDetected = (lastGainedRepData ~= prevLast and lastGainedRepData ~= nil)
  if gainDetected then
    local gd      = lastGainedRepData
    local startPct = gd.prevPct  -- nil si faction jamais vue avant ce gain
    -- Renown level-up ou 1er gain : prevPct nil ou > pct → flash depuis 0
    if startPct == nil or startPct > gd.pct then startPct = 0 end
    if gd.pct > startPct then
      AnimateXPGain(startPct, gd.pct - startPct)
    end
  elseif oldRepPct and rep.pct > oldRepPct then
    AnimateXPGain(oldRepPct, rep.pct - oldRepPct)
  end

  if showTimer then showTimer:Cancel() end
  showTimer = C_Timer.NewTimer(SHOW_DURATION, function()
    showTimer = nil
    if not isHovered then HideXPBar() end
  end)
end

-- Callback XP compagnon de gouffre : ACTIVE_DELVE_DATA_UPDATE
local function OnCompanionUpdate()
  if not IsMaxLevel() then return end
  local comp = GetCompanionXPData()
  if not comp then
    ResetCompanionState()
    XPBar.UpdateVisibility()
    return
  end
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.enabled == false then return end

  local oldCompanionPct    = prevCompanionPct
  local isFirstDetection   = (oldCompanionPct == nil)   -- première vue après entrée/reload
  local hasGain            = (not isFirstDetection) and (comp.pct > oldCompanionPct)
  prevCompanionPct = comp.pct

  -- Toujours mettre à jour la valeur de remplissage
  UpdateBarFill()

  -- S'assure que badge et zone de survol sont visibles en mode compagnon
  if levelBg    and not levelBg:IsVisible()    then levelBg:Show()    end
  if hoverFrame and not hoverFrame:IsVisible() then hoverFrame:Show() end

  -- Rafraîchit le texte du badge (lettre du compagnon)
  if levelText and comp then
    SetLevelTextFont(13)
    levelText:SetText(comp.letter)
    UpdateXPColors()
  end

  -- 1ere détection : badge+barre sans anim ; gain réel : avec flash turquoise ; sinon maj silencieuse
  if isFirstDetection or hasGain then
    -- ShowXPBar() AVANT AnimateXPGain : gainAnimFrame est enfant de container, inactif si container caché
    ShowXPBar()
    if hasGain then
      AnimateXPGain(oldCompanionPct, comp.pct - oldCompanionPct)
    end
    if showTimer then showTimer:Cancel() end
    showTimer = C_Timer.NewTimer(SHOW_DURATION, function()
      showTimer = nil
      if not isHovered then HideXPBar() end
    end)
  end
end

local function OnXPBarEvent(_, event, arg1, ...)
  if event == "PLAYER_XP_UPDATE" then
    OnXPGained()
  elseif event == "PLAYER_LEVEL_UP" then
    -- gains de ce niveau (PV, ressource, stats, talents) : servent d'estimation pour le suivant
    pcall(RecordLevelGains, arg1, ...)
    prevXP = 0
    -- UnitLevel("player") n'est pas encore a jour quand l'evenement arrive (le badge restait au niveau precedent) :
    -- on pose tout de suite le niveau de l'evenement (arg1), puis on rafraichit une fois le jeu a jour.
    if levelText and not petMode and type(arg1) == "number" and arg1 < GetMaxPlayerLevel() then
      SetLevelTextFont(19)
      levelText:SetText(tostring(arg1))
    end
    XPBar.UpdateVisibility()
    C_Timer.After(1, function() XPBar.Update() end)
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Instantane des stats de base du niveau courant : point de comparaison du prochain gain de niveau
    C_Timer.After(5, function() pcall(SnapshotBaseStats) end)
    prevXP = UnitXP("player")
    ResetCompanionState()
    isRepMode         = false
    prevRepPct        = nil
    lastGainedRepData = nil
    InitRepCache()
    XPBar.UpdateVisibility()
    -- Initialiser prevRepPct au pct courant pour ne pas flasher au premier UPDATE_FACTION
    if IsMaxLevel() then
      local rep = GetActiveRepData()
      if rep then prevRepPct = rep.pct end
    end
    -- Retries échelonnés pour rattraper les APIs qui se stabilisent après le loading screen
    for _, delay in ipairs({0.5, 1.5, 3, 6}) do
      C_Timer.After(delay, function()
        if XPBar.UpdateVisibility then XPBar.UpdateVisibility() end
        if XPBar.Update then XPBar.Update() end
        -- Initialiser prevRepPct si les APIs n'étaient pas prêtes à PLAYER_ENTERING_WORLD
        if IsMaxLevel() and prevRepPct == nil then
          local rep = GetActiveRepData()
          if rep then prevRepPct = rep.pct end
        end
      end)
    end
  elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
    -- arg1 = factionID : enregistré dans knownMajorFactionIDs pour les scans futurs
    if arg1 and arg1 > 0 then
      knownMajorFactionIDs[arg1] = true
      -- Pré-cache le nom si pas encore connu
      if not factionNameCache[arg1] and C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, fd = pcall(C_Reputation.GetFactionDataByID, arg1)
        if ok and fd and fd.name then factionNameCache[arg1] = fd.name end
      end
      if not repCache[arg1] then
        -- Nouvelle baseline au moment du level-up
        local key = GetFactionProgressKey(arg1)
        if key then repCache[arg1] = key end
      end
    end
    OnRepChanged()
  elseif event == "UPDATE_FACTION" then
    TrackCompanionXPGain()
    if IsMaxLevel() and GetCompanionXPData() then
      OnCompanionUpdate()
    else
      -- Sortie de gouffre : ACTIVE_DELVE_DATA_UPDATE n'a peut-être pas firé
      if isCompanionMode then
        ResetCompanionState()
        XPBar.UpdateVisibility()
      end
      OnRepChanged()
    end
  elseif event == "ACTIVE_DELVE_DATA_UPDATE" then
    OnCompanionUpdate()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- Court délai pour laisser le scénario se stabiliser (IsInDelve/mapID fiables), puis refresh
    C_Timer.After(0.5, function()
      if not XPBar.UpdateVisibility then return end
      XPBar.UpdateVisibility()
      XPBar.Update()
    end)
    C_Timer.After(2, function()
      if not XPBar.UpdateVisibility then return end
      XPBar.UpdateVisibility()
      XPBar.Update()
    end)
  end
end

-- Debug commande /xbdelve
SLASH_XBDELVE1 = "/xbdelve"
SlashCmdList["XBDELVE"] = function()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info  = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  local name  = (info and info.name) or "?"
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[XBDelve]|r subzone mapID=" .. tostring(mapID) .. " (" .. name .. ")")
end

-- Enregistrement des events au niveau module (independant de Create)
do
  local evtFrame = CreateFrame("Frame")
  evtFrame:RegisterEvent("PLAYER_XP_UPDATE")
  evtFrame:RegisterEvent("PLAYER_LEVEL_UP")
  evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  evtFrame:RegisterEvent("UPDATE_FACTION")
  evtFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
  evtFrame:RegisterEvent("ACTIVE_DELVE_DATA_UPDATE")
  evtFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  evtFrame:SetScript("OnEvent", OnXPBarEvent)
end

-- Apply layout visuals (positions/sizes/rotations depuis DB)
local function ApplyLayoutCfg()
  local lb = GetCfgLB()
  local tf = GetCfgTF()

  if levelBg then
    levelBg:ClearAllPoints()
    levelBg:SetSize(lb.w, lb.h)
    levelBg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", lb.x, lb.y)
  end
  if lbTex then
    lbTex:SetRotation(math.rad(lb.rot))
  end
  -- Sync hoverFrame sur levelBg pour qu'il suive les déplacements en layout mode
  if hoverFrame then
    hoverFrame:ClearAllPoints()
    hoverFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", lb.x, math.max(0, lb.y))
  end

  if tooltipFrame then
    tooltipFrame:ClearAllPoints()
    tooltipFrame:SetSize(tf.w, tf.h)
    tooltipFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", tf.x, tf.y)
  end
  if ttTex then
    ttTex:SetSize(tf.bgW, tf.bgH)
    ttTex:SetPoint("TOPLEFT", tooltipXP, "TOPLEFT", tf.bgOffX, tf.bgOffY)
    ttTex:SetRotation(math.rad(tf.bgRot))
  end
end

-- Create : sous-fonctions (découpage pour rester sous 60 upvalues chacune)

-- 1. Barre de fond + StatusBar XP + animation de gain
local function CreateXPBar_Container()
  local sw = GetBarWidth()
  container = CreateFrame("Frame", "AishuuXPBarContainer", UIParent)
  container:SetSize(sw, BAR_H)
  container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  container:SetFrameStrata("MEDIUM")
  container:Hide()

  bgTex = container:CreateTexture(nil, "BACKGROUND")
  bgTex:SetAllPoints(container)
  bgTex:SetColorTexture(0, 0, 0, 1)

  xpBar = CreateFrame("StatusBar", nil, container)
  xpBar:SetAllPoints(container)
  xpBar:SetStatusBarTexture(TEX_SOLID)
  xpBar:SetMinMaxValues(0, 1)
  xpBar:SetValue(0)
  UpdateBarColor()

  gainAnimFrame = CreateFrame("Frame", nil, container)
  gainAnimFrame:Hide()
  gainAnimFrame:SetScript("OnUpdate", OnGainUpdate)

  -- Ordre overlayHolder : overlayTex (déco) < gainBar (flash) < sparkTex (au-dessus)
  local overlayHolder = CreateFrame("Frame", nil, container)
  overlayHolder:SetAllPoints(container)
  overlayHolder:SetFrameLevel(xpBar:GetFrameLevel() + 1)

  overlayTex = overlayHolder:CreateTexture(nil, "ARTWORK")
  -- Cadre decoratif 4 px plus large de chaque cote que la barre
  overlayTex:SetPoint("TOPLEFT", overlayHolder, "TOPLEFT", -4, 0)
  overlayTex:SetPoint("BOTTOMRIGHT", overlayHolder, "BOTTOMRIGHT", 4, 0)
  overlayTex:SetTexture(TEX_OVERLAY)

  gainBar = overlayHolder:CreateTexture(nil, "OVERLAY", nil, 0)
  gainBar:SetColorTexture(unpack(GAIN_COLOR))
  gainBar:SetHeight(BAR_H)
  gainBar:Hide()

  sparkTex = overlayHolder:CreateTexture(nil, "OVERLAY", nil, 1)
  sparkTex:SetTexture(TEX_SPARK)
  sparkTex:SetSize(SPARK_W, SPARK_H)
  sparkTex:SetBlendMode("ADD")
  sparkTex:SetVertexColor(unpack(SPARK_CLR))
  sparkTex:SetPoint("CENTER", container, "LEFT", 0, 0)
  sparkTex:Hide()
end

-- 2. Badge de niveau
local function CreateXPBar_Badge(lb)
  levelBg = CreateFrame("Frame", nil, UIParent)
  levelBg:SetSize(lb.w, lb.h)
  levelBg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", lb.x, lb.y)
  levelBg:SetFrameStrata("BACKGROUND")
  levelBg:SetMovable(true)
  levelBg:RegisterForDrag("LeftButton")

  lbTex = levelBg:CreateTexture(nil, "BACKGROUND")
  lbTex:SetAllPoints()
  lbTex:SetTexture(TEX_GRUNGE)
  lbTex:SetVertexColor(0, 0, 0, 0.9)
  lbTex:SetRotation(math.rad(lb.rot))

  -- Holder enfant de levelBg : suit position/visibilité automatiquement,
  -- mais rendu à la même strate que le tooltip (HIGH) pour passer devant le chat.
  local levelTextHolder = CreateFrame("Frame", nil, levelBg)
  levelTextHolder:SetAllPoints(levelBg)
  levelTextHolder:SetFrameStrata("MEDIUM")

  levelText = levelTextHolder:CreateFontString(nil, "OVERLAY")
  levelText.slugRing = ns.CreateSlugRing(levelTextHolder, levelText)
  SetLevelTextFont(19)
  levelText:SetPoint("CENTER", levelBg, "CENTER", 0, 0)
  levelText:SetJustifyH("CENTER")

  -- Label plein nom affiché au hover en mode réputation (remplace temporairement levelText)
  -- Ancré sur UIParent BOTTOMLEFT à x=4 pour rester on-screen (lb.x=-34 serait hors-écran)
  repNameLabel = levelTextHolder:CreateFontString(nil, "OVERLAY")
  repNameLabel.slugRing = ns.CreateSlugRing(levelTextHolder, repNameLabel)
  ns.ApplyTextOutlineStyle(repNameLabel, repNameLabel.slugRing, xpFontLevel, 13, ns.DB.xpBar and ns.DB.xpBar.levelOutlineStyle, true)
  repNameLabel:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 4, lb.y + lb.h * 0.45 + 2)
  repNameLabel:SetJustifyH("LEFT")
  repNameLabel:Hide()
  levelBg:Hide()
end

-- 3. Tooltip XP + texte centré
local function CreateXPBar_Tooltip(tf)
  tooltipFrame = CreateFrame("Frame", nil, UIParent)
  tooltipFrame:SetSize(tf.w, tf.h)
  tooltipFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", tf.x, tf.y)
  tooltipFrame:SetFrameStrata("MEDIUM")
  tooltipFrame:SetMovable(true)
  tooltipFrame:RegisterForDrag("LeftButton")

  tooltipXP = tooltipFrame:CreateFontString(nil, "OVERLAY")
  tooltipXP:SetFont(xpFontInfo, 12, "OUTLINE")
  tooltipXP:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 32, -12)
  tooltipXP:SetJustifyH("LEFT")
  tooltipXP:SetTextColor(1, 0.741, 0.455, 1)

  ttTex = tooltipFrame:CreateTexture(nil, "BACKGROUND")
  ttTex:SetTexture(TEX_GRUNGE)
  ttTex:SetVertexColor(0, 0, 0, 0.9)
  ttTex:SetSize(tf.bgW, tf.bgH)
  ttTex:SetPoint("TOPLEFT", tooltipXP, "TOPLEFT", tf.bgOffX, tf.bgOffY)
  ttTex:SetRotation(math.rad(tf.bgRot))

  tooltipRested = tooltipFrame:CreateFontString(nil, "OVERLAY")
  tooltipRested:SetFont(xpFontInfo, 12, "OUTLINE")
  tooltipRested:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 10, -26)
  tooltipRested:SetJustifyH("LEFT")
  tooltipRested:SetTextColor(0.40, 0.80, 1.00, 1)
  tooltipFrame:Hide()

  local centerXPHolder = CreateFrame("Frame", nil, UIParent)
  centerXPHolder:SetSize(300, 20)
  centerXPHolder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BAR_H)
  centerXPHolder:SetFrameStrata("DIALOG")

  centerXPText = centerXPHolder:CreateFontString(nil, "OVERLAY")
  centerXPText:SetFont(xpFontInfo, 13, "OUTLINE")
  centerXPText:SetPoint("CENTER", centerXPHolder, "CENTER", 0, 0)
  centerXPText:SetJustifyH("CENTER")
  centerXPText:SetTextColor(1, 0.741, 0.455, 1)
  centerXPText:SetShadowOffset(1, -1)
  centerXPText:SetShadowColor(0, 0, 0, 1)
  centerXPText:Hide()
end

-- 4. Zone de survol + modèle 3D
local function CreateXPBar_HoverAndModel(lb)
  hoverFrame = CreateFrame("Frame", nil, UIParent)
  hoverFrame:SetSize(HOVER_W, HOVER_H)
  hoverFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", lb.x, math.max(0, lb.y))
  hoverFrame:SetFrameStrata("HIGH")
  hoverFrame:EnableMouse(true)
  hoverFrame:Hide()
  hoverFrame:SetScript("OnEnter", OnHoverEnter)
  hoverFrame:SetScript("OnLeave", OnHoverLeave)

  fxModel = CreateFrame("PlayerModel", nil, UIParent)
  fxModel:SetSize(FX_W, FX_H)
  fxModel:SetPoint("BOTTOMLEFT", UIParent, "LEFT", -127.8, -170.3)
  fxModel:SetFrameStrata("BACKGROUND")
  fxModel:SetKeepModelOnHide(true)
  pcall(function()
    fxModel:SetModel(FX_MODEL_ID)
    fxModel:SetPosition(0, -1.8, -5.6)
    fxModel:SetFacing(math.pi / 2)
  end)
  fxModel:Hide()

  -- Indicateur de zone de repos : même pattern que SpellEffects (PlayerModel + SetKeepModelOnHide + SetModel(tonumber))
  restModel = CreateFrame("PlayerModel", "AishCoreRestModel", UIParent)
  restModel:SetSize(REST_W, REST_H)
  restModel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  restModel:SetFrameStrata("HIGH")
  restModel:SetKeepModelOnHide(true)
  pcall(function()
    restModel:SetModel(tonumber(REST_MODEL_ID))
  end)
  restModel:Hide()
  ApplyRestModelCfg()
end

-- 5. Helpers layout + scripts de drag
local function CreateXPBar_LayoutTools()
  lbBorder     = MakeBorder(levelBg,     { 1, 0.2, 0.2, 1 })
  lbCoordText  = MakeCoordText(levelBg)
  lbResizeHandle = MakeResizeHandle(levelBg, OnLbResizeStop)

  tfBorder     = MakeBorder(tooltipFrame,  { 0.2, 0.6, 1, 1 })
  tfCoordText  = MakeCoordText(tooltipFrame)
  tfResizeHandle = MakeResizeHandle(tooltipFrame, OnTfResizeStop)

  levelBg:SetScript("OnDragStart", OnLevelBgDragStart)
  levelBg:SetScript("OnDragStop",  OnLevelBgDragStop)

  tooltipFrame:SetScript("OnDragStart", OnTooltipDragStart)
  tooltipFrame:SetScript("OnDragStop",  OnTooltipDragStop)
end

-- 6. Finalisation : animations + ticker de sécurité + init XP
local function CreateXPBar_Finalize()
  BuildAnimations()

  -- Ticker de sécurité : rattrape les cas où OnHoverLeave n'a pas firé
  -- (frame caché sous la souris, lag, transition de zone) laissant isHovered=true.
  ns.NewTicker(1, function()
    if not container or not container:IsVisible() then return end
    if isLayoutMode then return end
    if isHovered or showTimer then return end
    HideXPBar()
  end)

  if prevXP == nil then
    prevXP = UnitXP("player")
  end

  XPBar.UpdateVisibility()
  XPBar.Update()
end

-- Create
function XPBar.Create()
  if container then return end  -- deja cree, evite double-creation sur PLAYER_ENTERING_WORLD
  local cfg = ns.GetCfg("xpBar")
  if not cfg then return end

  local lb = GetCfgLB()
  local tf = GetCfgTF()

  CreateXPBar_Container()
  CreateXPBar_Badge(lb)
  CreateXPBar_Tooltip(tf)
  CreateXPBar_HoverAndModel(lb)
  CreateXPBar_LayoutTools()
  CreateXPBar_Finalize()
end

-- SetLayoutMode
-- ApplyRestModelCfg
ApplyRestModelCfg = function()
  if not restModel then return end
  local cfg = ns.GetCfg("xpBar")
  if not cfg then return end
  local x     = cfg.restX     or 0
  local y     = cfg.restY     or 0
  local scale = cfg.restScale or 1.0
  restModel:ClearAllPoints()
  restModel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  restModel:SetSize(REST_W * scale, REST_H * scale)
end
XPBar.ApplyRestModelCfg = ApplyRestModelCfg

function XPBar.SetRestPreview(enabled)
  restPreview = enabled and true or false
  UpdateRestingIndicator()
end

-- Force le restModel au centre de l'écran, bypass total de toute la logique
function XPBar.ForceRestCenter()
  if not restModel then
    print("|cffff4444[AishCore]|r restModel est nil")
    return
  end
  restModel:ClearAllPoints()
  restModel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  restModel:SetSize(300, 300)
  restModel:SetAlpha(1)
  restModel:SetFrameStrata("TOOLTIP")
  restModel:Show()
  print("|cff00b0ff[AishCore]|r ForceRestCenter visible=" .. tostring(restModel:IsVisible()))
end

-- UpdateRestingIndicator
UpdateRestingIndicator = function()
  if not restModel then return end
  local cfg = ns.GetCfg("xpBar")
  if not cfg or cfg.enabled == false or cfg.restIndicator == false then
    restModel:Hide()
    return
  end
  if restPreview or IsResting() then
    ApplyRestModelCfg()
    restModel:Show()
  else
    restModel:Hide()
  end
end
XPBar.UpdateRestingIndicator = UpdateRestingIndicator

function XPBar.SetLayoutMode(enabled)
  if not levelBg then return end
  isLayoutMode = enabled

  if enabled then
    -- Montre les frames meme si barre cachee
    levelBg:Show()
    tooltipFrame:Show()
    tooltipXP:SetText(string.format(L["XP_TOOLTIP_TOTAL"], "--.--%%"))
    tooltipRested:SetText(string.format(L["XP_TOOLTIP_RESTED"], "--.--%%"))
    tooltipRested:Show()
    -- Bordures
    lbBorder:Show(); tfBorder:Show()
    -- Coord texts
    UpdateCoordText(levelBg, lbCoordText); lbCoordText:Show()
    UpdateCoordText(tooltipFrame, tfCoordText); tfCoordText:Show()
    -- Resize handles
    lbResizeHandle:Show(); tfResizeHandle:Show()
    -- hoverFrame masque pour ne pas intercepter la souris
    if hoverFrame then hoverFrame:Hide() end
    -- Mouse sur les frames
    levelBg:EnableMouse(true)
    tooltipFrame:EnableMouse(true)
  else
    -- Cache les helpers
    lbBorder:Hide(); tfBorder:Hide()
    lbCoordText:Hide(); tfCoordText:Hide()
    lbResizeHandle:Hide(); tfResizeHandle:Hide()
    levelBg:EnableMouse(false)
    tooltipFrame:EnableMouse(false)
    -- Restore normal visibility
    XPBar.UpdateVisibility()
    if hoverFrame and not IsMaxLevel() then hoverFrame:Show() end
  end
end

function XPBar.GetLayoutMode()
  return isLayoutMode
end

-- Accesseur hoverFrame pour ModuleHoverOverlay : la hitbox est hoverFrame, pas container (alpha 0 hors survol)
function XPBar.GetHoverFrame()
  return hoverFrame
end

-- Forever : survol de la barre du familier (UnitBars) -> la barre d'xp, le badge de niveau et l'infobulle passent sur le
-- familier (niveau, xp, loyaute). Sans effet hors Forever ou sans familier de chasseur.
function XPBar.SetPetHover(on)
  if not (container and ns.IsForever) then return end
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.enabled == false then return end
  if on then
    if petMode or not GetPetXPData() then return end
    petMode = true
    if repNameLabel then repNameLabel:Hide() end
    if levelText then levelText:Show() end
    XPBar.Update()
    ShowXPBar()
    UpdateTooltip()
  else
    if not petMode then return end
    petMode = false
    XPBar.Update()
    UpdateBarColor()
    UpdateBarFill()
    if tooltipFrame and not isLayoutMode then FadeTo(tooltipFrame, false) end
    if centerXPText then FadeTo(centerXPText, false) end
    if not isHovered and not showTimer then HideXPBar() end
  end
end

-- /aishpet : ce que le jeu renvoie pour le familier (xp, loyaute, satisfaction), pour ajuster la lecture si besoin
SLASH_AISHPET1 = "/aishpet"
SlashCmdList["AISHPET"] = function()
  local P = "|cff33aaff[AishPet]|r "
  local function J(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end return table.concat(t, ", ") end
  print(P .. "UnitExists(pet)=" .. tostring(UnitExists("pet")) .. " niveau=" .. tostring(UnitLevel("pet")))
  if HasPetUI then print(P .. "HasPetUI = " .. J(HasPetUI())) end
  if GetPetExperience then print(P .. "GetPetExperience = " .. J(GetPetExperience())) end
  local fns = LoyaltyFunctions()
  if #fns == 0 then
    print(P .. "aucune fonction de loyaute trouvee (GetPetLoyalty, UnitLoyalty, C_PetInfo, _G)")
  end
  for _, c in ipairs(fns) do
    print(P .. c.name .. "() = " .. J(pcall(c.fn)) .. "  |  (\"pet\") = " .. J(pcall(c.fn, "pet")))
  end
  if C_PetInfo and C_PetInfo.GetPetHappiness then print(P .. "C_PetInfo.GetPetHappiness = " .. J(C_PetInfo.GetPetHappiness())) end
  if GetPetHappiness then print(P .. "GetPetHappiness = " .. J(GetPetHappiness())) end
  print(P .. "PetCharacterLevelText (cadre) : " .. tostring(_G.PetCharacterLevelText)
    .. " | PaperDollPetLevelInfo : " .. tostring(_G.PaperDollPetLevelInfo))
  print(P .. "texte du panneau Familier : " .. tostring(PetPanelText()))
  local pd = GetPetXPData()
  print(P .. "ligne de loyaute : " .. tostring(pd and pd.loyalty))
end

-- Update
function XPBar.Update()
  if not container then return end
  if not levelText then return end
  if petMode then
    local pd = GetPetXPData()
    if pd then
      SetLevelTextFont(19)
      levelText:SetText(tostring(pd.level))
      UpdateXPColors()
      UpdateBarColor()
      UpdateBarFill()
      return
    end
  end
  if IsMaxLevel() then
    local comp = GetCompanionXPData()
    if comp then
      SetLevelTextFont(13)
      levelText:SetText(comp.letter)
      UpdateXPColors()
      return
    end
    local rep = GetActiveRepData()
    if rep then
      SetLevelTextFont(13)  -- plus petit pour 4 chars
      levelText:SetText(rep.letter)
      UpdateXPColors()
    else
      SetLevelTextFont(19)
      levelText:SetText(tostring(UnitLevel("player")))   -- sortie du survol du familier : le badge reprend le niveau du joueur
    end
    return
  end
  SetLevelTextFont(19)  -- taille normale pour le niveau
  levelText:SetText(tostring(UnitLevel("player")))
  UpdateXPColors()
  UpdateBarColor()
  if container:IsVisible() then
    UpdateBarFill()
  end
end

-- UpdateVisibility
function XPBar.UpdateVisibility()
  if not container then return end
  if isLayoutMode then return end  -- layout mode gere sa propre visibilite
  local cfg = ns.GetCfg("xpBar")
  if cfg and cfg.enabled == false then return end  -- respecte le toggle
  if ns.IsInBlockedState() then
    container:Hide()
    if fxModel      then fxModel:Hide()       end
    if restModel    then restModel:Hide()     end
    if levelBg      then levelBg:Hide()       end
    if tooltipFrame then tooltipFrame:Hide()  end
    if centerXPText then centerXPText:Hide()  end
    if hoverFrame   then hoverFrame:Hide()    end
    if showTimer    then showTimer:Cancel(); showTimer = nil end
    return
  end
  local maxLevel = IsMaxLevel()

  if maxLevel then
    -- Priorité 1 (max level) : compagnon de gouffre
    local comp = GetCompanionXPData()
    if comp then
      SetBlizzXPBarHidden(true)
      if levelBg then levelBg:Show() end
      if levelText then
        SetLevelTextFont(13)
        levelText:SetText(comp.letter)
        UpdateXPColors()
      end
      if hoverFrame then hoverFrame:Show() end
      UpdateRestingIndicator()
      -- Met à jour fill + isCompanionMode.
      -- prevCompanionPct est géré exclusivement par OnCompanionUpdate.
      UpdateBarFill()
      -- Montre la barre dès l'entrée en gouffre (détectée via UpdateVisibility).
      -- Le showTimer l'a automatiquement après SHOW_DURATION si pas de hover.
      ShowXPBar()
      if showTimer then showTimer:Cancel() end
      showTimer = C_Timer.NewTimer(SHOW_DURATION, function()
        showTimer = nil
        if not isHovered then HideXPBar() end
      end)
    -- Priorité 2 (max level, pas en gouffre) : réputation
    else
      local rep = GetActiveRepData()
      if rep then
        -- Mode réputation : badge avec première lettre + zone hover active
        SetBlizzXPBarHidden(true)  -- la barre Blizz peut se réafficher après un TP
        if levelBg then levelBg:Show() end
        if levelText then
          SetLevelTextFont(13)  -- plus petit pour 4 chars
          levelText:SetText(rep.letter)
          UpdateXPColors()
        end
        if hoverFrame then hoverFrame:Show() end
        UpdateRestingIndicator()
        UpdateBarFill()  -- synchronise isRepMode=true, isCompanionMode=false
        -- Nettoie la barre si elle était visible du mode précédent (sortie gouffre)
        if showTimer then showTimer:Cancel(); showTimer = nil end
        if container:IsVisible() and not isHovered then HideXPBar() end
      else
        -- Niveau max sans rep/compagnon : si en gouffre, retry différé plutôt que masquer définitivement
        if IsInDelve() then
          C_Timer.After(2, function() if XPBar.UpdateVisibility then XPBar.UpdateVisibility() end end)
          return  -- ne pas masquer, attendre le retry
        end
        isCompanionMode = false
        isRepMode       = false
        container:Hide()
        if fxModel      then fxModel:Hide()       end
        if levelBg      then levelBg:Hide()       end
        if tooltipFrame then tooltipFrame:Hide()  end
        if centerXPText then centerXPText:Hide()  end
        if hoverFrame   then hoverFrame:Hide()    end
        if showTimer    then showTimer:Cancel(); showTimer = nil end
        UpdateRestingIndicator()
      end
    end
  else
    if levelBg then levelBg:Show() end
    if levelText then
      SetLevelTextFont(19)  -- taille normale pour le niveau
      levelText:SetText(tostring(UnitLevel("player")))
      UpdateXPColors()
    end
    if hoverFrame then hoverFrame:Show() end
    UpdateRestingIndicator()
  end
  -- Option "toujours visible" : afficher la barre tout de suite, sans attendre un gain d'XP.
  -- ShowXPBar ne relance rien si elle est deja affichee (il se contente de rafraichir le
  -- remplissage), l'appel est donc sans effet de bord a chaque rafraichissement.
  if IsAlwaysVisible() and not ns.IsInBlockedState() then ShowXPBar() end

end

-- Masquer les barres Blizzard XP/Rép : hook UpdateBarsShown pour réappliquer alpha 0 à chaque événement
local function HookBlizzBars()
  if not StatusTrackingBarManager then return end
  if StatusTrackingBarManager._aishHooked then return end
  StatusTrackingBarManager._aishHooked = true
  hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", function(self)
    if blizzBarsHidden then
      self:SetAlpha(0)
    end
  end)
end

SetBlizzXPBarHidden = function(hide)
  blizzBarsHidden = hide and true or false
  if StatusTrackingBarManager then
    HookBlizzBars()
    StatusTrackingBarManager:SetAlpha(blizzBarsHidden and 0 or 1)
  end
end

-- ApplySettings
function XPBar.ApplySettings()
  if not container then return end
  local cfg = ns.GetCfg("xpBar")
  if not cfg then return end

  if cfg.enabled == false then
    container:Hide()
    if fxModel      then fxModel:Hide()      end
    if restModel    then restModel:Hide()    end
    if levelBg      then levelBg:Hide()      end
    if tooltipFrame then tooltipFrame:Hide() end
    if centerXPText then centerXPText:Hide() end
    if hoverFrame   then hoverFrame:Hide()   end
    if showTimer    then showTimer:Cancel(); showTimer = nil end
    if isLayoutMode then XPBar.SetLayoutMode(false) end
    SetBlizzXPBarHidden(false)  -- restaurer la barre Blizzard
    return
  end

  -- Police du badge de niveau (mis a jour avant les fonctions dynamiques)
  xpFontLevel = cfg.fontLevel or FONT_LEVEL
  xpFontInfo  = cfg.fontInfo  or FONT_INFO
  if levelText then
    local _, sz = levelText:GetFont()
    -- GetFont peut rendre une hauteur <= 0 (police pas encore chargee) : SetFont plante alors
    SetLevelTextFont((sz and sz > 0) and sz or 19)
    -- Un SetFont ne rafraichit pas toujours le rendu du texte deja pose : on le re-pose
    local t = levelText:GetText()
    if t then levelText:SetText(t) end
  end
  -- Textes d'info (infobulle XP / repos, XP centrale) : police et contour appliques en direct, sinon
  -- seul le /reload les prenait en compte (ils n'etaient styles qu'a la creation)
  do
    -- Via un objet Font (SetFontObject) : changer la police d'un FontString deja affiche avec un
    -- simple SetFont n'est pas toujours pris en compte par le client, alors que la mise a jour d'un
    -- objet Font se propage a tous les textes qui l'utilisent.
    local style = cfg.levelOutlineStyle
    local flags = (style == "THICKOUTLINE") and "THICKOUTLINE" or ((style == "SLUG" or style == "") and "" or "OUTLINE")
    local function RestyleInfo(fs, key, defSize)
      if not fs then return end
      local _, sz = fs:GetFont()
      sz = (sz and sz > 0) and sz or defSize
      local fo = fontObjs[key]
      if not fo then
        fo = CreateFont("AishCoreXPInfoFont_" .. key)
        fontObjs[key] = fo
      end
      local okF, res = pcall(fo.SetFont, fo, xpFontInfo, sz, flags)
      if not okF or res == false then fo:SetFont("Fonts\\FRIZQT__.TTF", sz, flags) end
      if style == "SLUG" then
        fo:SetShadowOffset(0, 0)
      else
        fo:SetShadowColor(0, 0, 0, 1)
        fo:SetShadowOffset(1, -1)
      end
      fs:SetFontObject(fo)
      local t = fs:GetText()
      if t then fs:SetText("") ; fs:SetText(t) end
    end
    RestyleInfo(tooltipXP, "tooltipXP", 12)
    RestyleInfo(tooltipRested, "tooltipRested", 12)
    RestyleInfo(centerXPText, "centerXP", 13)
  end
  if repNameLabel then
    local _, sz = repNameLabel:GetFont()
    ns.ApplyTextOutlineStyle(repNameLabel, repNameLabel.slugRing, xpFontLevel, (sz and sz > 0) and sz or 13, cfg.levelOutlineStyle, true)
  end
  -- Re-applique positions/tailles/rotations depuis DB
  ApplyLayoutCfg()
  ApplyRestModelCfg()
  UpdateBarColor()
  UpdateXPColors()
  XPBar.UpdateVisibility()
  SetBlizzXPBarHidden(true)   -- cacher la barre Blizzard
end

-- Init
function XPBar.Init()
  XPBar.Create()
end
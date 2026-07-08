-- Modules/XPBar.lua : Barre d'experience custom
-- Structure : fond noir | StatusBar (degrade teal) | overlay aishui_xpbar.png
-- Badge de niveau et infos en grunge_spot1.png. Info XP centre au hover.
-- Layout mode : drag/resize + sliders settings pour positionner les elements.
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local XPBar = {}
ns.Modules.XPBar = XPBar

-- ---------------------------------------------------------------------------
-- Constantes
-- ---------------------------------------------------------------------------
local TEX_OVERLAY   = "Interface\\AddOns\\AishuuMedia\\aishui_xpbar.png"
local TEX_GRUNGE    = "Interface\\AddOns\\AishuuMedia\\grunge_spot1.png"
local TEX_SPARK     = "Interface\\CastingBar\\UI-CastingBar-Spark"
local TEX_SOLID     = "Interface\\BUTTONS\\WHITE8X8"

local FONT_LEVEL    = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-BoldItalic.ttf"
local FONT_INFO     = "Fonts\\2002.ttf"
-- Font du badge de niveau (mise a jour via ApplySettings si l'utilisateur change la police)
local xpFontLevel   = FONT_LEVEL

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

-- ---------------------------------------------------------------------------
-- Etat prive
-- ---------------------------------------------------------------------------
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
local hoverFrame
local fxModel
local restModel       -- animation 3D indicateur de zone de repos

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
local isLayoutMode    = false
local isRepMode           = false  -- vrai quand on affiche la réputation (niveau max)
local isCompanionMode     = false  -- vrai quand on affiche l'XP compagnon de gouffre
local COMPANION_FACTION_IDS    = {2640, 2744}  -- Brann (TWW), Valeera (Midnight)
local companionStandingCache   = {}            -- {[factionID]=standing} pour détecter les gains
local activeCompanionFactionID = nil           -- faction qui gagne de l'XP pendant le scénario
-- Whitelist mapIDs gouffres : valeur = factionID compagnon préféré.
-- TWW est couvert par scenarioType=11 ; Midnight nécessite ce fallback.
-- Ajouter les IDs manquants via /xbdelve depuis chaque gouffre.
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

--- Réinitialise proprement tout l'état lié au mode compagnon de gouffre.
--- Appelée UNIQUEMENT aux transitions explicites (sortie gouffre, loading screen, toggle).
local function ResetCompanionState()
  isCompanionMode          = false
  prevCompanionPct         = nil
  activeCompanionFactionID = nil
  wipe(companionStandingCache)
end

local FX_MODEL_ID = 4507696
local FX_W, FX_H = 313, 283

-- Indicateur de zone de repos 
-- fileID 165675 · ancré sur le badge de niveau (levelBg)
local REST_MODEL_ID = 165675
local REST_W        = 85.591751098633
local REST_H        = 66.667037963867
local REST_SCALE    = 40               
local REST_TX       = 40               

-- ---------------------------------------------------------------------------
-- Helpers DB
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Helpers display
-- ---------------------------------------------------------------------------
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
    local c = CLR.Get("misc")  -- élément Misc = barre XP elle-même
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

-- Applique la couleur XP Bar (texte niveau, hover, texte central)
-- la couleur GAIN_COLOR turquoise du gain XP n'est jamais touchée
local function UpdateXPColors()
  local r, g, b
  local CLR = ns.Modules.Colors
  if CLR then
    local c = CLR.Get("xpbar")  -- élément XP Bar = textes niveau
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

-- ---------------------------------------------------------------------------
-- Réputation trackée (mode niveau max)
-- ---------------------------------------------------------------------------
--- Données d'une faction par factionID + nom (les 3 systèmes : Renommée, Amitié, Classique).
--- factionData optionnel (struct FactionData déjà obtenu) : utilisé pour le chemin classique.
--- Champs retournés : name, letter, pct (0–1), cur, max, standing, rank*, rankMax*, isBattalion
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

  -- ── Système de Renommée (Dragonflight / TWW — Major Factions) ────────────
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

  -- ── Système de Réputation d'amitié (Chromie, etc.) ───────────────────────
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

  -- ── Système classique (standings Amical / Honorable / Exalté…) ───────────
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

--- Retourne la réputation à afficher selon le mode configuré, ou nil si le module est désactivé.
---   repEnabled = false → nil
---   "tracked"          → réputation trackée dans le panneau Réputations
---   "lastGained"       → dernière réputation qui a progressé (jusqu'au prochain gain)
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

--- Retourne les données XP du compagnon de gouffre (Brann / Valeera), ou nil si inactif.
--- Actif seulement : niveau max + dans un gouffre + option companionXP activée.
local function GetCompanionXPData()
  if not IsMaxLevel() then return nil end
  local cfg = ns.GetCfg("xpBar")
  if not cfg or cfg.companionXP == false then return nil end
  if not IsInDelve() then return nil end
  -- IsInDelve() est l'autorité : en gouffre on cherche forcément un compagnon.
  if not (C_GossipInfo and C_GossipInfo.GetFriendshipReputation) then return nil end
  -- Ordre de préférence :
  --  1. compagnon qui a déjà gagné de l'XP ce scénario (activeCompanionFactionID)
  --  2. compagnon préféré selon le mapID (TWW→Brann 2640, Midnight→Valeera 2744)
  --  3. liste complète
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

--- Calcule une clé de progression monotone croissante pour une faction donnée.
--- Renommée  : renownLevel * 100000 + earned  (ne régresse jamais même au level-up)
--- Amitié    : standing absolu
--- Classique : currentStanding absolu
--- Retourne nil si la faction est inconnue.
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

--- Remplit knownMajorFactionIDs + factionNameCache pour toutes les extensions
--- contenant des factions de Renommée (Dragonflight=9, TWW=10, +1 pour le futur).
--- N'itère que les factionIDs non encore vus : peut être appelé plusieurs fois.
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

--- Détecte les gains de réputation parmi les factions connues.
--- Coût par appel : N * pcall(GetMajorFactionData) où N = factions Renommée connues (~15-20).
--- Les noms sont pré-cachés → aucun GetFactionDataByID supplémentaire.
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

--- Initialise les caches au login / reload.
--- Remplit knownMajorFactionIDs, factionNameCache et les baselines repCache.
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

local function UpdateTooltip()
  if not tooltipFrame then return end
  if IsMaxLevel() then
    -- Priorité 1 (max level) : compagnon de gouffre
    local comp = GetCompanionXPData()
    if comp then
      tooltipXP:SetText(string.format(L["XP_TOOLTIP_COMPANION_LEVEL"], comp.level, comp.maxLevel or 60, comp.pct * 100))
      tooltipRested:Hide()
      tooltipFrame:SetHeight(28)
      tooltipFrame:Show()
      if centerXPText then
        centerXPText:SetText(string.format("[ %s  /  %s ]", ShortNum(comp.xp), ShortNum(comp.maxXP)))
        centerXPText:Show()
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
    tooltipFrame:Show()
    if centerXPText then
      centerXPText:SetText(string.format("[ %s / %s ]  %s  —  %.1f%%",
        ShortNum(rep.cur), ShortNum(rep.max), rep.standing, rep.pct * 100))
      centerXPText:Show()
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
    tooltipRested:Show()
    tooltipFrame:SetHeight(48)
  else
    tooltipRested:Hide()
    tooltipFrame:SetHeight(28)
  end
  tooltipFrame:Show()

  if centerXPText then
    centerXPText:SetText(string.format("[ %s  /  %s ]", ShortNum(xp), ShortNum(maxXP)))
    centerXPText:Show()
  end
end

-- ---------------------------------------------------------------------------
-- Animations
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Show / Hide
-- ---------------------------------------------------------------------------
local function ShowXPBar()
  if IsMaxLevel() and not GetCompanionXPData() and not GetActiveRepData() then return end
  if not container then return end

  -- Si la barre est deja completement visible (hors hideAnim/showAnim en cours),
  -- on met juste a jour le fill sans relancer l'animation d'entree.
  local alreadyVisible = container:IsVisible()
                      and container:GetAlpha() > 0.5
                      and not (hideAnim and hideAnim:IsPlaying())
                      and not (showAnim and showAnim:IsPlaying())
  if alreadyVisible then
    UpdateBarFill()
    if fxModel then fxModel:Show() end
    -- Si une animation de gain était en cours et que gainAnimFrame a été stoppé
    -- (ex : autre addon qui cache/reaffiche l'UI), le relancer.
    if gainAnimFrame and gainPhase ~= "idle" and not gainAnimFrame:IsVisible() then
      gainAnimFrame:Show()
    end
    return
  end

  -- Barre cachee ou en cours de hide/show : lancer l'animation d'entree
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

  -- Sécurité : si l'animation OnFinished ne fire pas (rare mais possible),
  -- forcer la position et l'alpha corrects après le délai théorique.
  C_Timer.After(ANIM_IN_DUR + 0.05, function()
    if container and container:IsVisible()
       and not (hideAnim and hideAnim:IsPlaying()) then
      container:ClearAllPoints()
      container:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
      container:SetAlpha(1)
    end
  end)
end

local function HideXPBar()
  if not container then return end
  if not container:IsVisible() then return end
  if isHovered then return end
  if showAnim and showAnim:IsPlaying() then showAnim:Stop() end
  if hideAnim and not hideAnim:IsPlaying() then
    hideAnim:Play()
  end
end

-- ---------------------------------------------------------------------------
-- Callback XP
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Helpers layout mode
-- ---------------------------------------------------------------------------
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
  f:SetFont(FONT_INFO, 10, "OUTLINE")
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -2)
  f:SetTextColor(1, 1, 0, 1)
  f:SetShadowOffset(1, -1)
  f:Hide()
  return f
end

-- ---------------------------------------------------------------------------
-- Callbacks inner (extraits de Create pour ne pas depasser 60 upvalues)
-- ---------------------------------------------------------------------------
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
end

local function OnHoverLeave()
  isHovered = false
  -- Restaurer l'abréviation dans le badge
  if repNameLabel then repNameLabel:Hide() end
  if levelText then levelText:Show() end
  if tooltipFrame and not isLayoutMode then tooltipFrame:Hide() end
  if centerXPText then centerXPText:Hide() end
  if not showTimer then HideXPBar() end
end

--- Détecte quel compagnon de gouffre gagne de l'XP (UPDATE_FACTION en scénario).
--- Met à jour activeCompanionFactionID et companionStandingCache.
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

  -- S'assure que le badge et la zone de survol sont visibles (peuvent être cachés
  -- entre deux UpdateVisibility si on vient d'un état sans réputation).
  if levelBg    and not levelBg:IsVisible()    then levelBg:Show()    end
  if hoverFrame and not hoverFrame:IsVisible() then hoverFrame:Show() end

  -- Rafraîchit le texte/police du badge (lettre de la faction)
  if levelText then
    levelText:SetFont(xpFontLevel, 13, "OUTLINE")
    levelText:SetText(rep.letter)
    UpdateXPColors()
  end

  -- ShowXPBar() AVANT AnimateXPGain : gainAnimFrame est enfant de container,
  -- son OnUpdate ne fire pas si container est caché.
  ShowXPBar()

  -- Animation de gain réputation (turquoise flash)
  -- Déclencheur 1 : ScanRepGains a détecté un gain (référence lastGainedRepData changée).
  --   Utilise lastGainedRepData.prevPct pour les coords exactes, même si prevRepPct
  --   était nil (1er gain après login) ou provenait d'une autre faction.
  -- Déclencheur 2 (fallback) : pct de la faction affichée a augmenté (même faction).
  local gainDetected = (lastGainedRepData ~= prevLast and lastGainedRepData ~= nil)
  if gainDetected then
    local gd      = lastGainedRepData
    local startPct = gd.prevPct  -- nil si faction jamais vue avant ce gain
    -- Renown level-up (pct repart de 0) ou 1er gain : prevPct nil ou > pct → flash depuis 0
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
    levelText:SetFont(xpFontLevel, 13, "OUTLINE")
    levelText:SetText(comp.letter)
    UpdateXPColors()
  end

  -- Première détection : afficher badge + barre sans animation (entrée en gouffre)
  -- Gain réel : afficher avec animation turquoise
  -- Aucun des deux : mise à jour silencieuse du fill uniquement
  if isFirstDetection or hasGain then
    -- ShowXPBar() AVANT AnimateXPGain : gainAnimFrame est enfant de container,
    -- son OnUpdate ne fire pas si container est caché.
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

local function OnXPBarEvent(_, event, arg1)
  if event == "PLAYER_XP_UPDATE" then
    OnXPGained()
  elseif event == "PLAYER_LEVEL_UP" then
    prevXP = 0
    XPBar.UpdateVisibility()
  elseif event == "PLAYER_ENTERING_WORLD" then
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
    -- arg1 = factionID, arg2 = newRenownLevel
    -- On enregistre ce factionID dans knownMajorFactionIDs pour les scans futurs
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
      -- Sortie de gouffre : ACTIVE_DELVE_DATA_UPDATE n'a peut-être pas firé.
      if isCompanionMode then
        ResetCompanionState()
        XPBar.UpdateVisibility()
      end
      OnRepChanged()
    end
  elseif event == "ACTIVE_DELVE_DATA_UPDATE" then
    OnCompanionUpdate()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    -- Transition de zone complète : les APIs (IsInDelve, mapID) sont fiables.
    -- Court délai pour laisser le scénario se stabiliser, puis refresh complet.
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

-- ---------------------------------------------------------------------------
-- Debug commande /xbdelve
-- ---------------------------------------------------------------------------
SLASH_XBDELVE1 = "/xbdelve"
SlashCmdList["XBDELVE"] = function()
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info  = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  local name  = (info and info.name) or "?"
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[XBDelve]|r subzone mapID=" .. tostring(mapID) .. " (" .. name .. ")")
end

--[[
  -- ancien debug complet
  local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[XBDelve]|r " .. tostring(msg)) end

  p("=== Delve Companion Debug v5 ===")

  -- Zone / Map ID courant
  p("-- Zone info --")
  do
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    p("mapID=" .. tostring(mapID))
    if mapID then
      local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
      p("mapName=" .. tostring(info and info.name))
    end
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    local subzone = GetSubZoneText and GetSubZoneText() or "?"
    p("zone=" .. zone .. " / subzone=" .. subzone)
  end

  -- Etat IsInDelve() etape par etape
  p("-- IsInDelve() diagnostic --")
  do
    local inScenario = false
    if C_Scenario and C_Scenario.IsInScenario then
      local ok, v = pcall(C_Scenario.IsInScenario)
      p("C_Scenario.IsInScenario ok="..tostring(ok).." v="..tostring(v))
      inScenario = ok and v == true
    else
      p("C_Scenario.IsInScenario: indisponible")
    end
    if C_DelvesUI then
      if C_DelvesUI.IsInDelve then
        local ok, v = pcall(C_DelvesUI.IsInDelve)
        p("C_DelvesUI.IsInDelve ok="..tostring(ok).." v="..tostring(v))
      else p("C_DelvesUI.IsInDelve: nil") end
      if C_DelvesUI.HasCompanionPanel then
        local ok, v = pcall(C_DelvesUI.HasCompanionPanel)
        p("C_DelvesUI.HasCompanionPanel ok="..tostring(ok).." v="..tostring(v))
      else p("C_DelvesUI.HasCompanionPanel: nil") end
      if C_DelvesUI.GetActiveDelveInfo then
        local ok, v = pcall(C_DelvesUI.GetActiveDelveInfo)
        p("C_DelvesUI.GetActiveDelveInfo ok="..tostring(ok).." v="..tostring(v ~= nil and "table" or v))
      else p("C_DelvesUI.GetActiveDelveInfo: nil") end
    else
      p("C_DelvesUI: nil (pas disponible)")
    end
    if C_Scenario and C_Scenario.GetScenarioInfo then
      local ok, info = pcall(C_Scenario.GetScenarioInfo)
      if ok and info then
        p("ScenarioInfo: type="..tostring(info.scenarioType).." name="..tostring(info.name))
      else p("GetScenarioInfo: ok="..tostring(ok).." info=nil") end
    end
    if C_Scenario and C_Scenario.GetScenarioInfo then
      local okI, info = pcall(C_Scenario.GetScenarioInfo)
      if okI and info then
        p("ScenarioInfo: type=" .. tostring(info.scenarioType) .. " name=" .. tostring(info.name))
      else
        p("GetScenarioInfo: ok=" .. tostring(okI) .. " info=nil")
      end
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    p("DELVE_MAP_IDS[" .. tostring(mapID) .. "] = " .. tostring(DELVE_MAP_IDS[mapID or 0]))
    p("IsInDelve() final => " .. tostring(IsInDelve()))
  end

  -- Dump complet de GetFactionDataByID pour Brann(2640) et Valeera(2744)
  p("-- GetFactionDataByID full dump --")
  for _, fid in ipairs({2640, 2744}) do
    if C_Reputation and C_Reputation.GetFactionDataByID then
      local ok, fd = pcall(C_Reputation.GetFactionDataByID, fid)
      if ok and fd then
        p("fid="..tostring(fid)..":")
        for k, v in pairs(fd) do p("  ."..tostring(k).."="..tostring(v)) end
      else
        p("fid="..tostring(fid)..": nil")
      end
    end
  end

  -- Friendship reputation APIs
  p("-- Friendship APIs --")
  for _, fid in ipairs({2640, 2744}) do
    -- GetFriendshipReputation
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
      local ok, r = pcall(C_GossipInfo.GetFriendshipReputation, fid)
      p("GetFriendshipReputation("..fid..") ok="..tostring(ok))
      if ok and type(r) == "table" then
        for k,v in pairs(r) do p("  ."..tostring(k).."="..tostring(v)) end
      elseif ok then p("  r="..tostring(r)) end
    end
    -- GetFriendshipReputationRanks
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputationRanks then
      local ok, r = pcall(C_GossipInfo.GetFriendshipReputationRanks, fid)
      p("GetFriendshipReputationRanks("..fid..") ok="..tostring(ok))
      if ok and type(r) == "table" then
        for k,v in pairs(r) do p("  ."..tostring(k).."="..tostring(v)) end
      elseif ok then p("  r="..tostring(r)) end
    end
  end

  -- C_Reputation plus récente : GetFactionDataByIndex + IsFriendshipReputation
  p("-- IsFriendshipReputation --")
  for _, fid in ipairs({2640, 2744}) do
    if C_Reputation and C_Reputation.IsFriendshipReputation then
      local ok, v = pcall(C_Reputation.IsFriendshipReputation, fid)
      p("IsFriendshipReputation("..fid..") ok="..tostring(ok).." v="..tostring(v))
    end
    if C_Reputation and C_Reputation.GetFriendshipReputation then
      local ok, v = pcall(C_Reputation.GetFriendshipReputation, fid)
      p("C_Reputation.GetFriendshipReputation("..fid..") ok="..tostring(ok))
      if ok and type(v) == "table" then
        for k,v2 in pairs(v) do p("  ."..tostring(k).."="..tostring(v2)) end
      elseif ok then p("  v="..tostring(v)) end
    end
  end

  -- Résultat final
  local comp = GetCompanionXPData()
  if comp then
    p("GetCompanionXPData => name="..comp.name.." lvl="..comp.level.." xp="..comp.xp.."/"..comp.maxXP.." pct="..string.format("%.1f%%", comp.pct*100))
  else p("GetCompanionXPData => nil") end
end
]]

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

-- ---------------------------------------------------------------------------
-- Apply layout visuals (positions/sizes/rotations depuis DB)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Create : sous-fonctions (découpage pour rester sous 60 upvalues chacune)
-- ---------------------------------------------------------------------------

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

  -- Ordre dans overlayHolder (frame level au-dessus de xpBar) :
  --   ARTWORK  (sublevel 0) : overlayTex   — décoration (aishui_xpbar.png)
  --   OVERLAY  (sublevel 0) : gainBar      — flash de gain, toujours au-dessus de la déco
  --   OVERLAY  (sublevel 1) : sparkTex     — spark, au-dessus du flash
  local overlayHolder = CreateFrame("Frame", nil, container)
  overlayHolder:SetAllPoints(container)
  overlayHolder:SetFrameLevel(xpBar:GetFrameLevel() + 1)

  overlayTex = overlayHolder:CreateTexture(nil, "ARTWORK")
  overlayTex:SetAllPoints(overlayHolder)
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
  levelText:SetFont(xpFontLevel, 19, "OUTLINE")
  levelText:SetPoint("CENTER", levelBg, "CENTER", 0, 0)
  levelText:SetJustifyH("CENTER")
  levelText:SetShadowOffset(1, -1)
  levelText:SetShadowColor(0, 0, 0, 1)

  -- Label plein nom affiché au hover en mode réputation (remplace temporairement levelText)
  -- Ancré sur UIParent BOTTOMLEFT à x=4 pour rester on-screen (lb.x=-34 serait hors-écran)
  repNameLabel = levelTextHolder:CreateFontString(nil, "OVERLAY")
  repNameLabel:SetFont(xpFontLevel, 13, "OUTLINE")
  repNameLabel:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 4, lb.y + lb.h * 0.45 + 2)
  repNameLabel:SetJustifyH("LEFT")
  repNameLabel:SetShadowOffset(1, -1)
  repNameLabel:SetShadowColor(0, 0, 0, 1)
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
  tooltipXP:SetFont(FONT_INFO, 12, "OUTLINE")
  tooltipXP:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 32, -12)
  tooltipXP:SetJustifyH("LEFT")
  tooltipXP:SetTextColor(0.780, 0.667, 0.400, 1)

  ttTex = tooltipFrame:CreateTexture(nil, "BACKGROUND")
  ttTex:SetTexture(TEX_GRUNGE)
  ttTex:SetVertexColor(0, 0, 0, 0.9)
  ttTex:SetSize(tf.bgW, tf.bgH)
  ttTex:SetPoint("TOPLEFT", tooltipXP, "TOPLEFT", tf.bgOffX, tf.bgOffY)
  ttTex:SetRotation(math.rad(tf.bgRot))

  tooltipRested = tooltipFrame:CreateFontString(nil, "OVERLAY")
  tooltipRested:SetFont(FONT_INFO, 12, "OUTLINE")
  tooltipRested:SetPoint("TOPLEFT", tooltipFrame, "TOPLEFT", 10, -26)
  tooltipRested:SetJustifyH("LEFT")
  tooltipRested:SetTextColor(0.40, 0.80, 1.00, 1)
  tooltipFrame:Hide()

  local centerXPHolder = CreateFrame("Frame", nil, UIParent)
  centerXPHolder:SetSize(300, 20)
  centerXPHolder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, BAR_H)
  centerXPHolder:SetFrameStrata("DIALOG")

  centerXPText = centerXPHolder:CreateFontString(nil, "OVERLAY")
  centerXPText:SetFont(FONT_INFO, 13, "OUTLINE")
  centerXPText:SetPoint("CENTER", centerXPHolder, "CENTER", 0, 0)
  centerXPText:SetJustifyH("CENTER")
  centerXPText:SetTextColor(0.780, 0.667, 0.400, 1)
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
  restModel = CreateFrame("PlayerModel", "AishaddonRestModel", UIParent)
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
  C_Timer.NewTicker(1, function()
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

-- ---------------------------------------------------------------------------
-- Create
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- SetLayoutMode
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- ApplyRestModelCfg
-- ---------------------------------------------------------------------------
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
    print("|cffff4444[Aishaddon]|r restModel est nil")
    return
  end
  restModel:ClearAllPoints()
  restModel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  restModel:SetSize(300, 300)
  restModel:SetAlpha(1)
  restModel:SetFrameStrata("TOOLTIP")
  restModel:Show()
  print("|cff00b0ff[Aishaddon]|r ForceRestCenter visible=" .. tostring(restModel:IsVisible()))
end

-- ---------------------------------------------------------------------------
-- UpdateRestingIndicator
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
function XPBar.Update()
  if not container then return end
  if not levelText then return end
  if IsMaxLevel() then
    local comp = GetCompanionXPData()
    if comp then
      levelText:SetFont(xpFontLevel, 13, "OUTLINE")
      levelText:SetText(comp.letter)
      UpdateXPColors()
      return
    end
    local rep = GetActiveRepData()
    if rep then
      levelText:SetFont(xpFontLevel, 13, "OUTLINE")  -- plus petit pour 4 chars
      levelText:SetText(rep.letter)
      UpdateXPColors()
    end
    return
  end
  levelText:SetFont(xpFontLevel, 19, "OUTLINE")  -- taille normale pour le niveau
  levelText:SetText(tostring(UnitLevel("player")))
  UpdateXPColors()
  UpdateBarColor()
  if container:IsVisible() then
    UpdateBarFill()
  end
end

-- ---------------------------------------------------------------------------
-- UpdateVisibility
-- ---------------------------------------------------------------------------
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
        levelText:SetFont(xpFontLevel, 13, "OUTLINE")
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
          levelText:SetFont(xpFontLevel, 13, "OUTLINE")  -- plus petit pour 4 chars
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
        -- Niveau max sans réputation trackee ni compagnon
        -- Si on est en gouffre, les données compagnon arrivent peut-être avec délai :
        -- on planifie un retry plutôt que de tout masquer définitivement.
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
      levelText:SetFont(xpFontLevel, 19, "OUTLINE")  -- taille normale pour le niveau
      levelText:SetText(tostring(UnitLevel("player")))
      UpdateXPColors()
    end
    if hoverFrame then hoverFrame:Show() end
    UpdateRestingIndicator()
  end
end

-- ---------------------------------------------------------------------------
-- Masquer la barre XP / Réputation Blizzard quand notre module est actif
-- ---------------------------------------------------------------------------
-- Un seul hook sur UpdateBarsShown suffit : c'est la méthode que le
-- StatusTrackingBarManager appelle sur chaque événement (XP, rep, level-up)
-- pour remettre les barres à jour. On réapplique l'alpha 0 immédiatement après.
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

-- ---------------------------------------------------------------------------
-- ApplySettings
-- ---------------------------------------------------------------------------
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
  if levelText then
    local _, sz, fl = levelText:GetFont()
    levelText:SetFont(xpFontLevel, sz or 19, fl or "OUTLINE")
  end
  if repNameLabel then
    local _, sz, fl = repNameLabel:GetFont()
    repNameLabel:SetFont(xpFontLevel, sz or 13, fl or "OUTLINE")
  end
  -- Re-applique positions/tailles/rotations depuis DB
  ApplyLayoutCfg()
  ApplyRestModelCfg()
  UpdateBarColor()
  UpdateXPColors()
  XPBar.UpdateVisibility()
  SetBlizzXPBarHidden(true)   -- cacher la barre Blizzard
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------
function XPBar.Init()
  XPBar.Create()
end
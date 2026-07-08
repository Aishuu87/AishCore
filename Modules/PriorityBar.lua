-- Modules/PriorityBar.lua : Barre de priorite avec 4 slots fixes
-- Chaque slot affiche le sort highlight en priorite, sinon le premier sort de sa liste
-- 2 conteneurs (gauche: slots 1+2, droite: slots 3+4) de part et d'autre du cercle
local addonName, ns = ...

local PriorityBar = {}
ns.Modules.PriorityBar = PriorityBar

---------------------------------------------------------------------------
-- Noms des boutons d'action standard Blizzard
-- (meme liste que RotationHelper pour scanner les highlights)
---------------------------------------------------------------------------
local BUTTON_PREFIXES = {
  "ActionButton",
  "MultiBarBottomLeftButton",
  "MultiBarBottomRightButton",
  "MultiBarRightButton",
  "MultiBarLeftButton",
  "MultiBar5Button",
  "MultiBar6Button",
  "MultiBar7Button",
}

---------------------------------------------------------------------------
-- Types de glow (loop) — flipbook sprite-sheet animations
-- Les textures ABE sont chargées depuis l'addon ActionBarsEnhanced/assets.
---------------------------------------------------------------------------
local ABE_ASSETS = "Interface/addons/ActionBarsEnhanced/assets/"

local LOOP_GLOW_TYPES = {
  -- 1 : Aucun
  { name = "Aucun" },
  -- 2 : Pulse (ancien glow maison — alpha bounce, pas flipbook)
  { name = "Pulse", useAlphaPulse = true,
    texture = "Interface\\SpellActivationOverlay\\IconAlert",
    texCoord = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 },
    blendMode = "ADD", fromAlpha = 0.4, toAlpha = 0.8, duration = 0.8 },
  -- 3..N : Flipbook-based (from ABE templates)
  { name = "Modern Blizzard Glow",
    atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook" },
  { name = "Modern Blizzard Assist Blue",
    atlas = "RotationHelper-ProcLoopBlue-Flipbook" },
  { name = "Modern Blizzard Assist Ants",
    atlas = "RotationHelper_Ants_Flipbook" },
  { name = "Modern Blizzard Assist White",
    texture = ABE_ASSETS .. "flipbook2.tga" },
  { name = "Modern Blizzard Assist Rainbow",
    texture = ABE_ASSETS .. "ABE_flipbook_rainbow.png",
    rows = 6, columns = 10, frames = 60, duration = 0.9,
    frameW = 80, frameH = 80, scale = 1.05 },
  { name = "Classic Blizzard Glow",
    texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
    rows = 5, columns = 5, frames = 25, duration = 0.3,
    frameW = 48, frameH = 48, scale = 0.85 },
  { name = "ABE Classic-like Blizzard Glow",
    texture = ABE_ASSETS .. "AB_ClassicLike_Glow.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.5,
    frameW = 100, frameH = 100, scale = 1 },
  { name = "ABE Star 1",
    texture = ABE_ASSETS .. "stars_new2.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.5,
    frameW = 100, frameH = 100, scale = 0.9 },
  { name = "ABE Star 2",
    texture = ABE_ASSETS .. "stars_new.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.5,
    frameW = 100, frameH = 100, scale = 0.9 },
  { name = "ABE Star 2 Rainbow",
    texture = ABE_ASSETS .. "stars_rainbow_new.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.5,
    frameW = 100, frameH = 100, scale = 0.9 },
  { name = "ABE Lines",
    texture = ABE_ASSETS .. "AB_Lines.tga",
    rows = 6, columns = 4, frames = 24, duration = 1.0,
    frameW = 50, frameH = 50, scale = 0.85 },
  { name = "ABE Lines Pixel-like",
    texture = ABE_ASSETS .. "AB_Lines_Pixel.tga",
    rows = 6, columns = 2, frames = 12, duration = 0.35,
    frameW = 50, frameH = 50, scale = 0.85 },
  { name = "ABE Leaves",
    texture = ABE_ASSETS .. "AB_Leaves.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.0,
    frameW = 50, frameH = 50, scale = 0.85 },
  { name = "ABE Void",
    texture = ABE_ASSETS .. "AB_Void.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.0,
    frameW = 50, frameH = 50, scale = 0.85 },
  { name = "ABE Garg",
    texture = ABE_ASSETS .. "AB_Garg.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.0,
    frameW = 100, frameH = 100, scale = 0.85 },
  { name = "ABE Energy",
    texture = ABE_ASSETS .. "ABE_Energy.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.5,
    frameW = 72, frameH = 72, scale = 0.85 },
  { name = "ABE Fire",
    texture = ABE_ASSETS .. "ABE_Fire.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.0,
    frameW = 72, frameH = 72, scale = 0.9 },
  { name = "ABE Fire2",
    texture = ABE_ASSETS .. "ABE_Fire2.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.0,
    frameW = 80, frameH = 80, scale = 0.9 },
  { name = "ABE Antorus",
    texture = ABE_ASSETS .. "ABE_Antorus.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.9,
    frameW = 100, frameH = 100, scale = 0.85 },
  { name = "ABE Lightning",
    texture = ABE_ASSETS .. "ABE_Lightning.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.2,
    frameW = 100, frameH = 100, scale = 0.85 },
  { name = "ABE Zereth Square",
    texture = ABE_ASSETS .. "proc_4.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.2,
    frameW = 100, frameH = 100, scale = 1.01 },
  { name = "ABE Pulse",
    texture = ABE_ASSETS .. "pulse_01.tga",
    rows = 6, columns = 5, frames = 30, duration = 1.0,
    frameW = 100, frameH = 100, scale = 0.95 },
  { name = "ABE Square Pixel-like",
    texture = ABE_ASSETS .. "ABE_Square_PixelLike.png",
    rows = 6, columns = 5, frames = 30, duration = 0.35,
    frameW = 100, frameH = 100, scale = 0.82 },
  { name = "ABE Arc Raiders",
    texture = ABE_ASSETS .. "ABE_ArcRaiders.png",
    rows = 10, columns = 6, frames = 60, duration = 1,
    frameW = 100, frameH = 100, scale = 1 },
  { name = "GCD",
    atlas = "UI-CooldownManager-Alert-Flipbook",
    rows = 11, columns = 2, frames = 22, duration = 1.0, scale = 0.7 },
  { name = "GCD 2",
    texture = ABE_ASSETS .. "GCD_2.tga",
    rows = 6, columns = 2, frames = 12, duration = 0.5,
    frameW = 47, frameH = 47, scale = 0.7 },
  { name = "Rogue CP Blue",
    atlas = "UF-RogueCP-Slash-Blue",
    rows = 3, columns = 6, frames = 18, duration = 0.7, scale = 1.3 },
  { name = "Rogue CP Red",
    atlas = "UF-RogueCP-Slash-Red",
    rows = 3, columns = 6, frames = 18, duration = 0.7, scale = 1.3 },
  { name = "Druid CP Red",
    atlas = "UF-DruidCP-Slash",
    rows = 3, columns = 8, frames = 24, duration = 0.7, scale = 1.3 },
  { name = "Chi Wind",
    atlas = "UF-Chi-WindFX",
    rows = 3, columns = 6, frames = 18, duration = 0.7, scale = 1.3 },
  { name = "Essence",
    atlas = "UF-Essence-Flipbook-FX-Circ",
    rows = 3, columns = 10, frames = 30, duration = 1.0, scale = 1.2 },
  { name = "Vigor",
    atlas = "dragonriding_sgvigor_burst_flipbook",
    rows = 4, columns = 4, frames = 16, duration = 1.0, scale = 1.2 },
  { name = "Vigor 2",
    atlas = "dragonriding_sgvigor_decor_flipbook_left",
    rows = 2, columns = 4, frames = 8, duration = 0.7, scale = 0.8 },
  { name = "FX",
    atlas = "groupfinder-eye-flipbook-foundfx",
    rows = 5, columns = 15, frames = 75, duration = 1.0, scale = 1.0 },
  { name = "Arrow",
    atlas = "Ping_Marker_FlipBook_OnMyWay",
    rows = 4, columns = 6, frames = 24, duration = 1.0, scale = 0.7 },
  { name = "Soul",
    atlas = "UF-SoulShards-Flipbook-Soul",
    rows = 3, columns = 7, frames = 21, duration = 1.2, scale = 0.9 },
  { name = "Frost",
    atlas = "perks-frost-FX",
    rows = 3, columns = 5, frames = 15, duration = 0.7, scale = 0.9 },
}

---------------------------------------------------------------------------
-- Types de proc start (one-shot entry animation)
---------------------------------------------------------------------------
local PROC_START_TYPES = {
  -- 1 : Aucun
  { name = "Aucun" },
  -- 2..N : Flipbook-based (from ABE templates)
  { name = "Modern Blizzard Proc",
    atlas = "UI-HUD-ActionBar-Proc-Start-Flipbook" },
  { name = "Modern Blizzard Proc Short",
    texture = ABE_ASSETS .. "ProcStartYellow.tga",
    rows = 3, columns = 6, frames = 18, duration = 0.5, scale = 1.0 },
  { name = "Modern Blizzard Proc Shorter",
    texture = ABE_ASSETS .. "ProcStartYellow_Shorter.tga",
    rows = 2, columns = 5, frames = 10, duration = 0.35, scale = 1.0 },
  { name = "Modern Blizzard Blue Proc",
    atlas = "RotationHelper-ProcStartBlue-Flipbook-2x" },
  { name = "Modern Blizzard Blue Proc Short",
    texture = ABE_ASSETS .. "ProcStartBlue.tga",
    rows = 3, columns = 6, frames = 18, duration = 0.5, scale = 1.0 },
  { name = "Modern Blizzard Blue Proc Shorter",
    texture = ABE_ASSETS .. "ProcStartBlue_Shorter.tga",
    rows = 2, columns = 5, frames = 10, duration = 0.35, scale = 1.0 },
  { name = "Modern Blizzard White Proc Short",
    texture = ABE_ASSETS .. "ProcStartWhite.tga",
    rows = 3, columns = 6, frames = 18, duration = 0.5, scale = 1.0 },
  { name = "Modern Blizzard White Proc Shorter",
    texture = ABE_ASSETS .. "ProcStartWhite_Shorter.tga",
    rows = 2, columns = 5, frames = 10, duration = 0.35, scale = 1.0 },
  { name = "Modern Blizzard Rainbow Proc Short",
    texture = ABE_ASSETS .. "ABE_ProcRainbow_Short.png",
    rows = 3, columns = 6, frames = 18, duration = 0.5, scale = 1.0 },
  { name = "Modern Blizzard Rainbow Proc Shorter",
    texture = ABE_ASSETS .. "ABE_ProcRainbow_Shorter.png",
    rows = 2, columns = 5, frames = 10, duration = 0.35, scale = 1.0 },
  { name = "Classic-like Blizzard Proc",
    texture = ABE_ASSETS .. "ClassicLike_Flipbook.tga",
    rows = 4, columns = 3, frames = 12, duration = 0.25,
    frameW = 80, frameH = 80, scale = 0.9 },
  { name = "ABE Burst Square",
    texture = ABE_ASSETS .. "burst_square.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.33,
    frameW = 100, frameH = 100, scale = 0.38 },
  { name = "ABE Burst Rune Square",
    texture = ABE_ASSETS .. "burst_2.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.33,
    frameW = 100, frameH = 100, scale = 0.38 },
  { name = "ABE Burst Rune Square 2",
    texture = ABE_ASSETS .. "burst_3.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.33,
    frameW = 100, frameH = 100, scale = 0.38 },
  { name = "ABE Burst Zereth Square",
    texture = ABE_ASSETS .. "burst_4.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.33,
    frameW = 100, frameH = 100, scale = 0.42 },
  { name = "ABE Burst Ring",
    texture = ABE_ASSETS .. "burst_5.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.7,
    frameW = 100, frameH = 100, scale = 0.38 },
  { name = "ABE Burst Ring 2",
    texture = ABE_ASSETS .. "burst_6.tga",
    rows = 6, columns = 5, frames = 30, duration = 0.4,
    frameW = 100, frameH = 100, scale = 0.38 },
}

-- Exporter pour le SettingsPanel (dropdown options)
PriorityBar.LOOP_GLOW_TYPES  = LOOP_GLOW_TYPES
PriorityBar.PROC_START_TYPES = PROC_START_TYPES

---------------------------------------------------------------------------
-- Layouts disponibles (2 conteneurs symétriques gauche/droite)
-- rows/cols : grille de chaque côté
-- leftNames : noms des slots dans l'ordre gauche (haut-gauche → bas-droite)
-- rightNames : noms des slots dans l'ordre droite (haut-gauche → bas-droite)
-- totalSlots : leftNames + rightNames
---------------------------------------------------------------------------
local LAYOUT_DEFS = {
  { id = "2x2",     name = "2×2 (par défaut)", totalSlots = 4,  rows = 1, cols = 2,
    leftNames  = {"A", "B"},
    rightNames = {"Y", "Z"} },
  { id = "3x3",     name = "3×3",              totalSlots = 6,  rows = 1, cols = 3,
    leftNames  = {"A", "B", "C"},
    rightNames = {"X", "Y", "Z"} },
  { id = "4x4line", name = "4×4 Inline",       totalSlots = 8,  rows = 1, cols = 4,
    leftNames  = {"A", "B", "C", "D"},
    rightNames = {"W", "X", "Y", "Z"} },
  { id = "4x4sq",   name = "4×4 Carré",        totalSlots = 8,  rows = 2, cols = 2,
    leftNames  = {"A", "B", "C", "D"},
    rightNames = {"Y", "Z", "W", "X"} },
  { id = "6x6",     name = "6×6",              totalSlots = 12, rows = 2, cols = 3,
    leftNames  = {"A", "B", "C", "D", "E", "F"},
    rightNames = {"X", "Y", "Z", "U", "V", "W"} },
}
PriorityBar.LAYOUT_DEFS = LAYOUT_DEFS

local MAX_SLOTS = 12  -- nombre maximum de slots (layout 6x6)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local slotFrames = {}          -- { [1..MAX_SLOTS] = frame }
local leftContainer = nil      -- conteneur gauche
local rightContainer = nil     -- conteneur droite
local pbFadeTicker  = nil      -- ticker pour l'animation fade in/out combat
local initialized = false
local pollTicker = nil
local cdViewerTicker = nil  -- ticker isole pour ScanCooldownViewer (evite taint propagation)
local debugMode = false
local testMode = false
local dragEnabled = false
local chargeCache        = {}  -- spellID → maxCharges (construit hors combat)
local overrideToBase     = {}  -- overrideSpellID → baseSpellID (reverse map)
local learnedSpells      = {}  -- spellID → true si IsPlayerSpell (construit hors combat, jamais tainted)
local spellCDBase        = {}  -- spellID → base cooldown en secondes (construit hors combat)
local _realCDEndTimes    = {}  -- spellID → GetTime() estimé de fin de CD (en combat)
local estimatedCharges   = {}  -- spellID → nombre estimé de charges actuelles (en combat)
local chargeRechargeTime = {}  -- spellID → durée de recharge d'une charge en sec
local chargeTimers             = {}  -- spellID → C_Timer handle pour recharge programmée
local _chargeRechargeStartedAt = {}  -- spellID → GetTime() quand la recharge courante a démarré
local _chargeRechargeData      = {}  -- spellID → { start, duration } recharge en cours (ticker isolé)
local _chargeSwipeStartTime    = {}  -- spellID → GetTime() du dernier cast (pour swipe recharge)
local _chargeHasRecharge       = {}  -- spellID → bool : currentCharges < max (ticker isolé, propre)
local _chargeCountCache        = {}  -- spellID → dernier currentCharges connu (ticker isolé)
local _chargeHastedRechargeTime = {} -- spellID → durée de recharge hastée (GetSpellCooldown, ticker isolé)
local _chargeIsOnRealCD        = {}  -- spellID → bool : duration>1.5s (vrai CD) vs GCD (ticker isolé)
local _cdViewerState           = {}  -- spellID → { onCD = bool, charges = number|nil }
local _cdViewerAvail     = false  -- true si le dernier scan CDViewer a trouvé des données
local _cvDbgSnap         = ""   -- fingerprint du dernier état CDViewer logué
local _swipeDbg          = {}   -- [slot] → dernier état logué (swipeRunning|spellOnCD|spellID)
local _lastSuccessTime   = {}  -- spellName → GetTime() du dernier UNIT_SPELLCAST_SUCCEEDED (dedupe)
-- Forward declarations (définitions effectives plus bas dans le fichier)
local GetCurrentLayoutDef

---------------------------------------------------------------------------
-- Utility : convertir un nombre (potentiellement un secret number TWW)
-- en vrai nombre Lua. Fonctionne UNIQUEMENT hors combat (OOC).
-- En combat, les secret numbers TWW bloquent TOUTE opération Lua :
-- arithmétique, comparaison, tonumber, string ops, même SetID/GetID
-- retourne des valeurs taintées. Pour le combat, utiliser GetSpellName()
-- pour les comparaisons (retourne des strings propres).
---------------------------------------------------------------------------
local function SecretToNumber(val)
  if val == nil then return nil end
  if type(val) == "number" then
    local ok, res = pcall(function() return val + 0 end)
    if ok then return res end
  end
  local n = tonumber(val)
  if n then return n end
  -- Dernier recours: tonumber(tostring(val)) pour OOC
  local ok2, s = pcall(tostring, val)
  if ok2 and s then return tonumber(s) end
  return nil
end

-- Extraire un entier PROPRE (0-20) à partir d'une valeur potentiellement tainted.
-- Utilise pcall(==) contre chaque entier candidat pour trouver la valeur exacte
-- et retourne un nombre Lua natif (jamais tainted).
local function CleanInt(val)
  if type(val) ~= "number" then return nil end
  -- En TWW, les secret numbers ne peuvent pas être comparés (même ==, ~=, <, >, etc.)
  -- mais les opérations arithmétiques (+, floor, etc.) sont autorisées. PROBLÈME :
  -- math.floor(secret + 0) peut encore renvoyer un secret number (la taint se
  -- propage dans les chaînes taintées). type(n) == "number" passe quand même.
  -- SOLUTION : tester pcall(==) contre un littéral. Si ça crash, c'est un secret
  -- et on doit abandonner. Si ça réussit, on retourne le littéral propre.
  local ok, n = pcall(function() return math.floor(val + 0) end)
  if not ok or type(n) ~= "number" then return nil end
  -- Vérification de propreté via comparaison littérale + retour du littéral
  for i = 0, 20 do
    local okEq, eq = pcall(function() return n == i end)
    if not okEq then return nil end  -- n est secret → abandon total
    if eq then return i end           -- match : on retourne le littéral clean
  end
  return nil  -- hors range (ne devrait pas arriver pour des charges)
end

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local function Debug(msg)
  if debugMode then
    print("|cff00b0ff[PB]|r " .. tostring(msg))
  end
end

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------
local function GetSpellIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  return nil
end

local function GetSpellName(spellID)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and name then return name end
  end
  return "Spell#" .. tostring(spellID)
end

local function FormatCooldown(remaining)
  if remaining >= 60 then
    return string.format("%dm", math.ceil(remaining / 60))
  elseif remaining >= 3 then
    return string.format("%d", math.ceil(remaining))
  else
    return string.format("%.1f", remaining)
  end
end

---------------------------------------------------------------------------
-- Cache bouton → spellID  (reconstruit HORS combat uniquement)
-- Evite d'appeler GetActionInfo en combat (taint propagation).
-- cachedSpellToAction permet de retrouver le slot d'action depuis un spellID.
---------------------------------------------------------------------------
local cachedButtonData = {}        -- buttonKey → { button, spellID }
local cachedSpellToAction = {}     -- spellID → actionSlotNumber
local cachedSpellToButton = {}     -- spellID → ActionButton frame (pour lire le Count FontString)

-- [12.0.5] Interception directe du nombre de charges via hook SetText.
-- Blizzard appelle button.Count:SetText("2") depuis du code natif NON tainté ;
-- en hookant SetText on capture le nombre propre AVANT toute propagation de
-- taint, éliminant le problème des "secret strings" en combat.
-- liveChargeByButton[button] = number (ou 0 si vide)
local liveChargeByButton = {}
local _hookedCountTexts  = {}      -- éviter de re-hooker le même FontString

-- [12.0.5] Cache des charges alimenté par un ticker DÉDIÉ (stack propre).
-- Diagnostic empirique : `C_Spell.GetSpellCharges` retourne un secret number
-- quand appelé depuis une stack taintée par notre addon (ex: PollSlots qui a
-- fait ScanHighlights/UpdateSlot avant). Mais la MÊME API appelée depuis un
-- contexte isolé (slash command, ticker minimaliste) renvoie un nombre propre.
-- On exploite ça en faisant tourner un ticker séparé qui ne fait QUE lire les
-- charges et rien d'autre — sa stack reste propre, l'API reste clean.
-- liveChargesByID[spellID] = number (dernière valeur clean lue)
local liveChargesByID = {}
local _chargesTicker  = nil
-- [12.0.5 diag] compteurs pour savoir quelle source alimente liveChargesByID
local _chargesStats = {
  eventFires     = 0,  -- SPELL_UPDATE_CHARGES firé
  eventWrites    = 0,  -- écriture effective depuis l'event
  tickerRuns     = 0,  -- ticker dédié exécuté
  tickerWrites   = 0,  -- écriture effective depuis le ticker
  lastEventTime  = 0,
  lastTickerTime = 0,
}

-- Snapshot du cache pris juste avant le décollage en Skyriding.
-- Pendant le vol la barre d'action affiche les sorts du véhicule : on préserve
-- la dernière version "combat" ici pour pouvoir la restaurer au dismount,
-- même si on est déjà en combat à ce moment-là.
local _preDrakeButtonData     = {}   -- snapshot buttonKey → { button, spellID }
local _preDrakeSpellToAction  = {}   -- snapshot spellID → actionSlotNumber
local _hasDrakeSnapshot       = false

local function RebuildSpellButtonCache()
  if InCombatLockdown() then
    Debug("RebuildSpellButtonCache SKIPPED (InCombat)")
    return
  end
  -- Ne jamais écraser le cache avec les sorts de montée (Dragonriding/Skyriding).
  -- UnitPowerBarID 631 = barre Dragonriding active (fiable, pas de nil).
  -- La dernière version construite AVANT le décollage est correcte et reste valide.
  if UnitPowerBarID("player") == 631 then
    Debug("RebuildSpellButtonCache SKIPPED (Dragonriding actif)")
    return
  end
  _hasDrakeSnapshot = false   -- snapshot obsolète, on vient de reconstruire proprement
  wipe(cachedButtonData)
  wipe(cachedSpellToAction)
  wipe(cachedSpellToButton)
  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local bName = prefix .. i
      local button = _G[bName]
      if button and button.action and type(button.action) == "number" then
        local aType, id = GetActionInfo(button.action)
        if aType == "spell" and id and id > 0 then
          cachedButtonData[bName] = { button = button, spellID = id }
          cachedSpellToAction[id] = button.action
          cachedSpellToButton[id] = button
          Debug("  cache: " .. bName .. " -> " .. id .. " (" .. (GetSpellName(id) or "?") .. ")")
        end
      end
    end
  end
  local count = 0; for _ in pairs(cachedButtonData) do count = count + 1 end
  Debug("Button cache rebuilt: " .. count .. " entrees")
end

---------------------------------------------------------------------------
-- Alerte chat : sorts de la Priority Bar absents des barres d'action.
-- Appelé après RebuildSpellButtonCache + ConfigureSlots (hors combat).
-- Si aucun des spellIDs d'un slot n'est trouvé dans le cache, le joueur
-- est averti — sans action bar, highlights et rotation ne fonctionnent pas.
---------------------------------------------------------------------------
local function CheckMissingSpellsFromActionBars()
  local missing = {}
  for i = 1, MAX_SLOTS do
    local slot = slotFrames[i]
    if slot and not slot._hidden and slot.spellIDs and #slot.spellIDs > 0 then
      -- Skip si le joueur ne connaît aucun des sorts du slot (build différent, talent non pris)
      local known = false
      for _, sid in ipairs(slot.spellIDs) do
        if IsSpellKnown and IsSpellKnown(sid) then known = true; break end
      end
      if known then
        local found = false
        for _, sid in ipairs(slot.spellIDs) do
          if cachedSpellToButton[sid] then found = true; break end
          -- vérifie aussi le sort override (forme de voyage, etc.)
          if C_Spell and C_Spell.GetOverrideSpell then
            local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
            if ok and ov and ov ~= sid and ov > 0 and cachedSpellToButton[ov] then
              found = true; break
            end
          end
        end
        if not found then
          local name = GetSpellName(slot.spellIDs[1]) or ("Sort #" .. slot.spellIDs[1])
          missing[#missing + 1] = { num = i, name = name, slotName = slot.slotName or ("Slot " .. i) }
        end
      end
    end
  end

  if #missing > 0 then
    local P = "|cffff6600[Aishaddon]|r "
    print(P .. "Priority Bar — |cffffff00sort(s) non placé(s) dans les barres d'action :|r")
    for _, m in ipairs(missing) do
      print(P .. "  |cffff9900•|r " .. m.slotName .. " — |cffffffff" .. m.name .. "|r")
    end
    print(P .. "Placez ces sorts dans une barre d'action pour activer highlights et rotation.")
  end
end

---------------------------------------------------------------------------
-- Cache des charges (construit hors combat uniquement)
-- On stocke le maxCharges pour chaque spellID configure.
-- En combat les API de charges retournent des secret numbers,
-- donc on se base sur ce cache pour savoir quels sorts ont des charges.
-- On synchronise aussi les charges ACTUELLES (estimatedCharges) et le
-- temps de recharge (chargeRechargeTime) hors combat.
---------------------------------------------------------------------------
local function RebuildChargeCache()
  if InCombatLockdown() then return end
  wipe(chargeCache)
  wipe(overrideToBase)
  for i = 1, MAX_SLOTS do
    local slot = slotFrames[i]
    if slot and slot.spellIDs then
      for _, sid in ipairs(slot.spellIDs) do
        if C_Spell and C_Spell.GetSpellCharges then
          local chargeInfo = C_Spell.GetSpellCharges(sid)
          if chargeInfo and chargeInfo.maxCharges then
            local okCmp, isMulti = pcall(function() return chargeInfo.maxCharges > 1 end)
            if okCmp and isMulti then
              local okNum, maxC = pcall(function() return math.floor(chargeInfo.maxCharges + 0) end)
              chargeCache[sid] = (okNum and maxC) or 2
              -- Sync charges actuelles + recharge time (hors combat = clean)
              if chargeInfo.currentCharges then
                local cur = CleanInt(chargeInfo.currentCharges)
                if cur then estimatedCharges[sid] = cur end
              end
              if chargeInfo.cooldownDuration then
                local okDur, dur = pcall(function() return chargeInfo.cooldownDuration + 0 end)
                if okDur and dur and dur > 0 then chargeRechargeTime[sid] = dur end
              end
              -- Aussi cacher l'override (ex: sort modifie par talent)
              if C_Spell.GetOverrideSpell then
                local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
                if ok and ov and ov ~= sid and ov > 0 then
                  chargeCache[ov] = chargeCache[sid]
                  overrideToBase[ov] = sid
                  estimatedCharges[ov] = estimatedCharges[sid]
                  chargeRechargeTime[ov] = chargeRechargeTime[sid]
                end
              end
            end
          end
        end
        -- Construire le reverse override map pour tous les sorts (pas seulement charges)
        if C_Spell and C_Spell.GetOverrideSpell then
          local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
          if ok and ov and ov ~= sid and ov > 0 then
            overrideToBase[ov] = sid
          end
        end
      end
    end
  end
  Debug("Charge cache rebuilt (" .. (next(chargeCache) and "OK" or "empty") .. ")")
end

---------------------------------------------------------------------------
-- Programmation de recharge d'une charge (timer-based, en combat)
-- Quand le joueur utilise une charge, on programme un C_Timer pour la regen.
---------------------------------------------------------------------------
local ScheduleChargeRecharge  -- forward decl

ScheduleChargeRecharge = function(spellID)
  -- Si un timer de recharge est deja en cours, ne pas le redemarrer.
  -- Dans WoW, consommer une 2e charge ne relance pas le timer de la 1ere.
  if chargeTimers[spellID] then return end
  local rechargeTime = chargeRechargeTime[spellID]
  local maxC = chargeCache[spellID]
  if not rechargeTime or rechargeTime <= 0 or not maxC then return end
  local clean = CleanInt(estimatedCharges[spellID]) or 0
  if clean >= maxC then return end
  _chargeRechargeStartedAt[spellID] = GetTime()  -- timestamp de début de cette recharge
  chargeTimers[spellID] = C_Timer.NewTimer(rechargeTime, function()
    chargeTimers[spellID] = nil
    local prev = CleanInt(estimatedCharges[spellID]) or 0
    estimatedCharges[spellID] = math.min(maxC, prev + 1)
    Debug("Charge regen: " .. (GetSpellName(spellID) or spellID) .. " → " .. tostring(estimatedCharges[spellID]) .. "/" .. maxC)
    -- Programmer la prochaine recharge si pas encore au max
    if (CleanInt(estimatedCharges[spellID]) or 0) < maxC then
      ScheduleChargeRecharge(spellID)
      -- Relancer le swipe pour la prochaine charge
      local cfg = ns.GetCfg("priorityBar") or {}
      if cfg.showCooldownSwipe ~= false then
        for i = 1, MAX_SLOTS do
          local slot = slotFrames[i]
          if slot and slot.currentSpellID and slot.cooldown then
            local sid = slot.currentSpellID
            local base = overrideToBase[sid] or sid
            local chSid = chargeCache[sid] and sid or (chargeCache[base] and base)
            if chSid == spellID then
              slot.cooldown:Show()
              slot.cooldown:SetCooldown(GetTime(), rechargeTime)
              -- Mettre à jour le tracking pour que UpdateSlotExtras ne relance
              -- pas le swipe inutilement au prochain tick (évite le double reset)
              local sName = GetSpellName(spellID)
              if sName then
                slot._swipeSpellName = sName
                slot._onCooldown = true
              end
              break
            end
          end
        end
      end
    end
  end)
end

---------------------------------------------------------------------------
-- Cache des CD de base (construit hors combat uniquement)
-- GetSpellBaseCooldown retourne le CD de base en millisecondes.
-- On stocke en secondes. Sert a savoir quels sorts ont un vrai CD (> GCD).
-- NOTE : PAS de wipe(spellCDBase) ! Les CD appris par SyncCooldownsOOC ou
-- par observation in-combat doivent persister entre les rebuilds, car
-- GetSpellBaseCooldown ne fonctionne pas pour tous les sorts en TWW.
-- Le wipe ne se fait qu'au changement de spec (ConfigureSlots path).
---------------------------------------------------------------------------
local function RebuildCooldownCache()
  if InCombatLockdown() then return end
  -- PAS de wipe : on merge par-dessus les valeurs existantes.
  -- GetSpellBaseCooldown est prioritaire quand il retourne un resultat valide.
  for i = 1, MAX_SLOTS do
    local slot = slotFrames[i]
    if slot and slot.spellIDs then
      for _, sid in ipairs(slot.spellIDs) do
        -- Methode 1 : GetSpellBaseCooldown (retourne ms)
        if GetSpellBaseCooldown then
          local ok, ms = pcall(GetSpellBaseCooldown, sid)
          if ok and ms and type(ms) == "number" and ms > 0 then
            spellCDBase[sid] = ms / 1000
          end
        end
        -- Methode 2 (fallback) : Si le sort est actuellement en CD, lire la duree
        if not spellCDBase[sid] and C_Spell and C_Spell.GetSpellCooldown then
          local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
          if ok and cdInfo and cdInfo.duration then
            local okDur, dur = pcall(function()
              local d = cdInfo.duration + 0
              if d > 1.5 then return d end
            end)
            if okDur and dur then
              spellCDBase[sid] = dur
            end
          end
        end
        -- Override spell
        if C_Spell and C_Spell.GetOverrideSpell then
          local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
          if ok and ov and ov ~= sid and ov > 0 then
            if not spellCDBase[ov] and spellCDBase[sid] then
              spellCDBase[ov] = spellCDBase[sid]
            end
            if not spellCDBase[ov] and GetSpellBaseCooldown then
              local ok2, ms2 = pcall(GetSpellBaseCooldown, ov)
              if ok2 and ms2 and type(ms2) == "number" and ms2 > 0 then
                spellCDBase[ov] = ms2 / 1000
              end
            end
          end
        end
      end
    end
  end
  Debug("Cooldown cache rebuilt (" .. (next(spellCDBase) and "OK" or "empty") .. ")")
end

---------------------------------------------------------------------------
-- Synchronisation OOC des charges (appele a la sortie du combat)
-- Relit les valeurs reelles et corrige toute derive des estimations.
---------------------------------------------------------------------------
local function SyncChargesOOC()
  -- [fix] C_Spell.GetSpellCharges fonctionne en combat (prouvé empiriquement).
  -- Quand on a une valeur réelle de l'API, on annule TOUJOURS les timers prédictifs
  -- (en et hors combat). Le timer est un filet de secours ; si l'API donne la vraie
  -- valeur, le timer ne doit plus interférer sous peine de sur-compter.
  for sid, maxC in pairs(chargeCache) do
    if C_Spell and C_Spell.GetSpellCharges then
      local ok, info = pcall(C_Spell.GetSpellCharges, sid)
      if ok and info and info.currentCharges then
        local cur = tonumber(tostring(info.currentCharges))
        if cur then
          estimatedCharges[sid] = cur
          Debug("SyncCharges: " .. (GetSpellName(sid) or sid) .. " = " .. cur .. "/" .. maxC)
          -- Annuler le timer prédictif : on a la vraie valeur, plus besoin de lui.
          if chargeTimers[sid] then chargeTimers[sid]:Cancel(); chargeTimers[sid] = nil end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- [12.0.5] Live-read tentatif des charges en combat.
-- Stratégie : on essaie d'extraire une valeur CLEAN (Lua natif) via CleanInt.
-- Si la 12.0.5 expose les charges comme non-secret en combat → on obtient
-- une valeur autoritative. Si Blizzard continue à retourner un secret number,
-- CleanInt renvoie nil et on retombe sur l'estimation prédictive.
--
-- Zéro risque : comportement identique à avant si l'API reste taintée.
-- Gain potentiel : précision parfaite (pas de drift par procs, CDR, haste…).
--
-- Utilise aussi cooldownDuration == 0 pour détecter "at max" (nouveau en 12.0.5 :
-- "Duration APIs now return a zero-span duration when a spell is at maximum charges").
--
-- @param spellID number
-- @return number? current, number? max (ou nil, nil si illisible)
---------------------------------------------------------------------------
local function TryLiveReadCharges(spellID)
  local maxC = chargeCache[spellID]

  -- [fix] C_Spell.GetSpellCharges fonctionne en et hors combat (prouvé via
  -- TestCharges.lua sur Stormstrike 17364). CleanInt gère les secret numbers
  -- résiduels : si la valeur est taintée elle renvoie nil et on retombe sur
  -- estimatedCharges dans le caller. Pas de perte de sécurité.
  if not (C_Spell and C_Spell.GetSpellCharges) then return nil, maxC end
  local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
  if not ok or not info then return nil, maxC end
  -- [fix] tonumber(tostring()) fonctionne dans TOUS les contextes d'exécution
  -- (event handler ET C_Timer ticker), contrairement à CleanInt qui utilise
  -- pcall(n == i) — la comparaison peut échouer silencieusement si la stack
  -- est taintée par d'autres opérations du ticker (ex: GetOverrideSpell, etc.).
  -- tostring() sur un secret number retourne sa valeur décimale correcte ;
  -- tonumber() dessus donne un entier clean et non-tainté.
  -- Prouvé équivalent au SetText(info.currentCharges) direct du TestCharges.lua.
  local cur = tonumber(tostring(info.currentCharges))
  local max = tonumber(tostring(info.maxCharges)) or maxC

  -- Filet de secours "at max" si currentCharges est nil (normalement impossible
  -- avec tonumber/tostring, mais garde la robustesse).
  if cur == nil and max ~= nil then
    if info.cooldownDuration ~= nil then
      local okDur, isZero = pcall(function() return info.cooldownDuration + 0 == 0 end)
      if okDur and isZero then cur = max end
    end
    if cur == nil and C_Spell.GetSpellChargeDuration then
      local okCD, dur = pcall(C_Spell.GetSpellChargeDuration, spellID)
      if okCD and dur ~= nil then
        local okZ, isZ = pcall(function() return dur + 0 == 0 end)
        if okZ and isZ then cur = max end
      end
    end
  end
  return cur, max
end

-- Accès rapide : combien de charges actuellement, en privilégiant le live read.
-- Retourne un entier ou nil. Met à jour silencieusement estimatedCharges si on
-- obtient une valeur live (permet aussi aux autres call sites basés sur
-- estimatedCharges de profiter de la correction automatique).
local function GetAuthoritativeCharges(spellID)
  local cur, _max = TryLiveReadCharges(spellID)
  if cur ~= nil then
    -- [12.0.5] Écriture INCONDITIONNELLE. La comparaison `~=` contre
    -- estimatedCharges[spellID] peut crasher si la valeur stockée est un
    -- reliquat de secret number (placé par un CleanInt précédent qui
    -- n'aurait pas pu l'extraire proprement). Le pcall ci-dessous protège
    -- aussi contre tout futur edge case.
    pcall(function() estimatedCharges[spellID] = cur end)
    -- Si on est au max, annuler le timer de recharge prédictif pour éviter
    -- qu'il ne re-incrémente et dépasse le max à son tick suivant.
    local maxC = chargeCache[spellID]
    if maxC and cur >= maxC and chargeTimers[spellID] then
      chargeTimers[spellID]:Cancel(); chargeTimers[spellID] = nil
    end
    return cur
  end
  return CleanInt(estimatedCharges[spellID])
end

---------------------------------------------------------------------------
-- Synchronisation OOC des CD en cours (appele a la sortie du combat)
-- Relit les vrais CD et corrige _realCDEndTimes pour les sorts encore en CD.
---------------------------------------------------------------------------
local function SyncCooldownsOOC()
  if InCombatLockdown() then return end
  -- 1) Corriger _realCDEndTimes pour les sorts encore en CD
  for sid, _ in pairs(_realCDEndTimes) do
    if C_Spell and C_Spell.GetSpellCooldown then
      local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
      if ok and cdInfo and cdInfo.duration and cdInfo.startTime then
        local dur   = tonumber(tostring(cdInfo.duration))
        local start = tonumber(tostring(cdInfo.startTime))
        if dur and start and dur > 1.5 then
          local remaining = (start + dur) - GetTime()
          if remaining > 0 then
            _realCDEndTimes[sid] = GetTime() + remaining
          else
            _realCDEndTimes[sid] = nil
          end
        else
          _realCDEndTimes[sid] = nil
        end
      else
        _realCDEndTimes[sid] = nil
      end
    else
      _realCDEndTimes[sid] = nil
    end
  end
  -- 2) Apprendre spellCDBase depuis les sorts actuellement en CD (OOC = clean)
  --    C'est le mecanisme principal d'apprentissage pour les sorts dont
  --    GetSpellBaseCooldown ne fonctionne pas (retire en TWW pour certains sorts).
  if C_Spell and C_Spell.GetSpellCooldown then
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.spellIDs then
        for _, sid in ipairs(slot.spellIDs) do
          if not spellCDBase[sid] then
            local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, sid)
            if ok and cdInfo and cdInfo.duration then
              local dur = tonumber(tostring(cdInfo.duration))
              if dur and dur > 1.5 then
                spellCDBase[sid] = dur
                Debug("LearnCD OOC: " .. (GetSpellName(sid) or sid) .. " = " .. string.format("%.1f", dur) .. "s")
              end
            end
          end
          -- Idem pour l'override
          if C_Spell.GetOverrideSpell then
            local ok2, ov = pcall(C_Spell.GetOverrideSpell, sid)
            if ok2 and ov and ov ~= sid and ov > 0 and not spellCDBase[ov] then
              local okCD, cdInfo = pcall(C_Spell.GetSpellCooldown, ov)
              if okCD and cdInfo and cdInfo.duration then
                local dur = tonumber(tostring(cdInfo.duration))
                if dur and dur > 1.5 then
                  spellCDBase[ov] = dur
                  Debug("LearnCD OOC override: " .. (GetSpellName(ov) or ov) .. " = " .. string.format("%.1f", dur) .. "s")
                end
              end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Scan du CooldownViewer Blizzard (UtilityCooldownViewer)
-- Seule source fiable de l'état CD en combat dans TWW :
--   • Cooldown:IsShown() = true → sort en CD, false → prêt
--   • ChargeCount.Current:GetText() → charges lisibles (nil si non-charge)
-- Appelé à chaque tick de PollSlots (0.15s).
-- Si le CDViewer n'est pas disponible, _cdViewerAvail reste false
-- et UpdateSlotExtras tombe sur le fallback event-driven.
---------------------------------------------------------------------------
local function ScanCooldownViewer()
  wipe(_cdViewerState)
  _cdViewerAvail = false
  -- Sorts à charges : lire la durée du CD depuis GetSpellCooldown (ticker isolé = propre).
  -- d > 1.5s → vrai CD (recharge ~7.5s) ; d ≤ 1.5s → GCD seul ; nil → inconnu.
  -- Stocké dans _chargeIsOnRealCD[chSid] et utilisé par UpdateSlotExtras (hideGCDSwipe).
  wipe(_chargeRechargeData)
  if C_Spell and C_Spell.GetSpellCooldown then
    for chSid in pairs(chargeCache) do
      local okCD, cdInfo = pcall(C_Spell.GetSpellCooldown, chSid)
      if okCD and cdInfo and cdInfo.duration then
        local okCmp, isLong = pcall(function() return cdInfo.duration > 1.5 end)
        _chargeIsOnRealCD[chSid] = (okCmp and isLong) or nil
      else
        _chargeIsOnRealCD[chSid] = nil
      end
    end
  end
  if ns._cdViewerDisabled then return end
  local viewer = _G["UtilityCooldownViewer"]
  if not viewer or not viewer.itemFramePool then return end

  local ok = pcall(function()
    for itemFrame in viewer.itemFramePool:EnumerateActive() do
      local info = itemFrame.cooldownInfo
      if info and info.spellID then
        local spellID = info.spellID
        -- CD state : Cooldown:IsShown() = true → en CD
        -- isOnGCD filtre les frames GCD (booléen natif CDM, lisible en tainté).
        local onCD = false
        local cdStart, cdDuration = nil, nil
        local isGCDFrame = itemFrame.isOnGCD == true
        if not isGCDFrame and itemFrame.Cooldown then
          local okS, shown = pcall(itemFrame.Cooldown.IsShown, itemFrame.Cooldown)
          if okS and shown then onCD = true end
          -- Lire les temps exacts du swipe via GetCooldownTimes (retourne ms → conversion en s)
          -- C'est la source la plus fiable, même principe que ChargeCount:GetText() pour les charges.
          local okT, s, d = pcall(itemFrame.Cooldown.GetCooldownTimes, itemFrame.Cooldown)
          if okT and s and d and d > 500 then
            cdStart   = s / 1000
            cdDuration = d / 1000
          end
        end

        -- Charges : lire le FontString (toujours clean, nil si non-charge)
        local charges = nil
        if itemFrame.ChargeCount and itemFrame.ChargeCount.Current then
          local okC, txt = pcall(function()
            local t = itemFrame.ChargeCount.Current:GetText()
            if t then local _ = t .. ""; return tonumber(t) end
            return nil
          end)
          if okC then charges = txt end
        end

        -- Stocker en préférant la durée la plus longue : quand deux frames existent
        -- pour le même sort (ex: frame GCD + frame vrai CD), garder le vrai CD.
        -- Frame GCD (isOnGCD=true) → cdDuration=nil ; frame vrai CD → cdDuration=12s.
        -- Frame GCD (isOnGCD=false) → cdDuration=1.5s ; frame vrai CD → cdDuration=12s.
        -- "prefer longer" garantit que _cdViewerState reflète toujours le vrai CD.
        local _prev = _cdViewerState[spellID]
        local _useNew = not _prev
                     or (cdDuration and (not _prev.cdDuration or cdDuration > _prev.cdDuration))
        if _useNew then
          _cdViewerState[spellID] = { onCD = onCD, charges = charges, cdStart = cdStart, cdDuration = cdDuration }
          -- Apprendre spellCDBase depuis le CDViewer (couvre les sorts où
          -- GetSpellBaseCooldown renvoie nil en TWW, ex: Crash Lightning).
          if cdDuration and cdDuration > 1.5 and not spellCDBase[spellID] then
            spellCDBase[spellID] = cdDuration
          end
        end
        _cdViewerAvail = true

        -- Indexer aussi sous l'overrideSpellID du cooldownInfo (si différent)
        if info.overrideSpellID then
          local okOv, ovID = pcall(function()
            if info.overrideSpellID ~= spellID and info.overrideSpellID > 0 then
              return info.overrideSpellID
            end
            return nil
          end)
          if okOv and ovID then
            _cdViewerState[ovID] = _cdViewerState[spellID]
          end
        end

        -- Indexer aussi sous l'override LIVE (ex: Voidform → Attaque Mentale 8092
        -- devient Trait de Vide). GetOverrideSpell retourne l'override actuel
        -- meme en combat, car c'est un simple lookup pas un secret number.
        if C_Spell and C_Spell.GetOverrideSpell then
          local okOv2, ovID2 = pcall(C_Spell.GetOverrideSpell, spellID)
          if okOv2 and ovID2 and ovID2 ~= spellID and ovID2 > 0 then
            _cdViewerState[ovID2] = _cdViewerState[spellID]
          end
        end

        -- Indexer aussi sous le spellID DE BASE si le CDViewer utilise l'override
        -- comme clé. overrideToBase[override] = base, donc si spellID est un
        -- override, on stocke aussi sous la clé base pour que FindCDViewerState
        -- trouve l'entrée quand slot.spellIDs contient le sort de base.
        local baseOfCD = overrideToBase[spellID]
        if baseOfCD and baseOfCD ~= spellID then
          _cdViewerState[baseOfCD] = _cdViewerState[spellID]
        end
      end
    end
  end)

  -- Debug : loguer l'état CDViewer quand il change (on ne spam pas, seulement sur delta)
  if debugMode then
    local snap = {}
    for id, cv in pairs(_cdViewerState) do
      table.insert(snap, tostring(id) .. (cv.onCD and "Y" or "N")
        .. (cv.charges ~= nil and ("c" .. tostring(cv.charges)) or "")
        .. (cv.cdStart and ("@" .. string.format("%.0f", cv.cdStart)) or ""))
    end
    table.sort(snap)
    local s = table.concat(snap, "|")
    if s ~= _cvDbgSnap then
      _cvDbgSnap = s
      if #snap > 0 then
        local detail = {}
        for id, cv in pairs(_cdViewerState) do
          local n = (GetSpellName(id) or tostring(id)) .. "(" .. id .. ")"
          local rem = (cv.cdStart and cv.cdDuration)
            and string.format(" rem=%.1fs", cv.cdStart + cv.cdDuration - GetTime())
            or ""
          table.insert(detail, n .. ":onCD=" .. tostring(cv.onCD)
            .. " chg=" .. (cv.charges ~= nil and tostring(cv.charges) or "nil") .. rem)
        end
        Debug("CDViewer: " .. table.concat(detail, " | "))
      else
        Debug("CDViewer: (vide)")
      end
    end
  end

  -- NOTE : GetSpellCharges retourne des secret numbers en combat TWW.
  -- Impossible de les extraire (taint bloque arithmetic, comparison,
  -- tonumber, string ops, et même SetID/GetID). Le tracking des charges
  -- repose donc sur SPELLCAST_SUCCEEDED + ScheduleChargeRecharge timers.
  -- SyncChargesOOC corrige toute dérive à la sortie du combat.
end

---------------------------------------------------------------------------
-- Cache des sorts appris (construit hors combat uniquement)
-- IsPlayerSpell peut retourner un secret boolean en combat → on n'appelle
-- jamais cette API dans le polling tick. Le cache est rebuild :
--   • au login / reload
--   • à la sortie du combat (PLAYER_REGEN_ENABLED)
--   • au changement de spé (ACTIVE_TALENT_GROUP_CHANGED)
---------------------------------------------------------------------------
local function RebuildLearnedCache()
  if InCombatLockdown() then
    Debug("RebuildLearnedCache SKIPPED (InCombat)")
    return
  end
  wipe(learnedSpells)
  for i = 1, MAX_SLOTS do
    local slot = slotFrames[i]
    if slot and slot.spellIDs then
      for _, sid in ipairs(slot.spellIDs) do
        -- Test direct
        local ok, known = pcall(IsPlayerSpell, sid)
        if ok and known then
          learnedSpells[sid] = true
        end
        -- Fallback : IsSpellKnownOrOverridesKnown (couvre les IDs talent-upgrade
        -- que IsPlayerSpell ne reconnaît pas, ex: 382266 Souffle de feu)
        if not learnedSpells[sid] and IsSpellKnownOrOverridesKnown then
          local ok2, known2 = pcall(IsSpellKnownOrOverridesKnown, sid)
          if ok2 and known2 then
            learnedSpells[sid] = true
          end
        end
        -- Test sur l'override eventuel (talent qui remplace un sort de base)
        if C_Spell and C_Spell.GetOverrideSpell then
          local ok2, ov = pcall(C_Spell.GetOverrideSpell, sid)
          if ok2 and ov and ov ~= sid and ov > 0 then
            local ok3, known2 = pcall(IsPlayerSpell, ov)
            if ok3 and known2 then
              learnedSpells[sid] = true   -- le sort de base est consideré appris via son override
              learnedSpells[ov]  = true
            end
          end
        end
      end
    end
  end
  Debug("Learned cache rebuilt (" .. (next(learnedSpells) and "OK" or "empty") .. ")")
end

---------------------------------------------------------------------------
-- Detection des highlights
-- Trois sources possibles de glow sur un bouton Blizzard :
--   1. AssistedCombatHighlightFrame  : rotation assistant (conseille le prochain sort)
--   2. SpellHighlightTexture         : proc highlight (talent, buff, etc.)
--   3. SpellHighlightAnim            : animation de proc (confirme si SHT frozen/buggé)
-- Selon la classe et le build, seul l'un de ces systèmes peut être utilisé.
-- BM Hunter par exemple : les procs passent par SHT, jamais par ACHF.
-- On vérifie les trois via pcall pour éviter tout taint.
---------------------------------------------------------------------------
local function ButtonHasGlow(button)
  if not button then return false end
  -- 1) Rotation assistant
  if button.AssistedCombatHighlightFrame then
    local ok, shown = pcall(button.AssistedCombatHighlightFrame.IsShown, button.AssistedCombatHighlightFrame)
    if ok and shown then return true end
  end
  -- 2) Proc highlight texture
  if button.SpellHighlightTexture then
    local ok, shown = pcall(button.SpellHighlightTexture.IsShown, button.SpellHighlightTexture)
    if ok and shown then return true end
  end
  -- 3) Proc highlight animation (fallback si texture visible mais IsFrozen)
  if button.SpellHighlightAnim then
    local ok, playing = pcall(button.SpellHighlightAnim.IsPlaying, button.SpellHighlightAnim)
    if ok and playing then return true end
  end
  return false
end

-- Table réutilisable pour éviter une allocation par tick
local _glowedSpells = {}

-- Lit le spellID LIVE d'un bouton d'action (safe en combat via pcall).
-- Utilisé par CollectGlowedSpells pour les boutons dont le contenu a changé
-- après un changement de forme Druide (action bar paging).
local function GetLiveButtonSpellID(button)
  if not button then return nil end
  -- 1) Via GetSpellID method (TWW buttons) — API propre, préférée
  if button.GetSpellID then
    local ok, sid = pcall(button.GetSpellID, button)
    if ok and sid and type(sid) == "number" and sid > 0 then return sid end
  end
  -- 2) Via action slot + GetActionInfo (fallback)
  if button.action and type(button.action) == "number" then
    local ok, aType, id = pcall(GetActionInfo, button.action)
    if ok and aType == "spell" and id and id > 0 then return id end
  end
  return nil
end

-- Ajoute un spellID glowé + ses overrides/base dans la table glowed.
local function AddGlowedSpell(glowed, sid, bName)
  glowed[sid] = true
  Debug("  glow: " .. bName .. " spellID=" .. sid .. " (" .. (GetSpellName(sid) or "?") .. ")")
  -- Ajouter aussi l'override courant (ex: Flame Shock -> Voltaic Blaze)
  if C_Spell and C_Spell.GetOverrideSpell then
    local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
    if ok and ov and ov ~= sid and ov > 0 then
      glowed[ov] = true
      Debug("    override: " .. ov .. " (" .. (GetSpellName(ov) or "?") .. ")")
    end
  end
  -- Ajouter le base spell (lien inverse override→base, ex: 444995→1221348)
  if FindBaseSpellByID then
    local ok, base = pcall(FindBaseSpellByID, sid)
    if ok and base and base ~= sid and base > 0 then
      glowed[base] = true
      Debug("    base: " .. base .. " (" .. (GetSpellName(base) or "?") .. ")")
    end
  end
end

local function CollectGlowedSpells()
  local glowed = _glowedSpells
  wipe(glowed)
  local foundAny = false
  local scannedButtons = {}

  -- Passe 1 : boutons du cache (ou snapshot Dragonriding).
  -- Pour chaque bouton avec glow, on lit le spellID LIVE pour couvrir les
  -- changements de forme Druide (action bar paging change le contenu du bouton).
  local sourceData = (_hasDrakeSnapshot and next(_preDrakeButtonData) ~= nil) and _preDrakeButtonData or cachedButtonData
  for bName, data in pairs(sourceData) do
    scannedButtons[bName] = true
    local button = data.button
    if button and ButtonHasGlow(button) then
      foundAny = true
      -- Préférer le spellID live (couvre les changements de forme en combat)
      local liveID = GetLiveButtonSpellID(button)
      local sid = liveID or data.spellID
      AddGlowedSpell(glowed, sid, bName)
      -- Si le live diffère du cache, ajouter aussi le cache (ceinture+bretelles)
      if liveID and liveID ~= data.spellID then
        glowed[data.spellID] = true
      end
    end
  end

  -- Passe 2 : scanner TOUS les boutons non encore vérifiés.
  -- Couvre les boutons qui n'étaient pas dans le cache (slots vides dans la
  -- forme précédente, remplis après un changement de forme Druide en combat).
  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local bName = prefix .. i
      if not scannedButtons[bName] then
        local button = _G[bName]
        if button and ButtonHasGlow(button) then
          local sid = GetLiveButtonSpellID(button)
          if sid then
            foundAny = true
            AddGlowedSpell(glowed, sid, bName .. " (uncached)")
          end
        end
      end
    end
  end

  if not foundAny then
    local cacheSize = 0; for _ in pairs(sourceData) do cacheSize = cacheSize + 1 end
    Debug("CollectGlowedSpells: aucun glow (source=" .. (_hasDrakeSnapshot and "snapshot" or "cache") .. " " .. cacheSize .. " entrees, full scan done)")
  end
  return glowed
end

---------------------------------------------------------------------------
-- Creation des conteneurs (gauche et droite)
---------------------------------------------------------------------------
local function CreateContainer(name)
  local cfg = ns.GetCfg("priorityBar") or {}
  local size = cfg.iconSize or 34
  local spacing = cfg.iconSpacing or 6
  local container = CreateFrame("Frame", name, UIParent)
  container:SetSize(size * 2 + spacing, size)
  container:SetFrameStrata("MEDIUM")
  container:SetFrameLevel(55)
  container:SetMovable(true)
  container:EnableMouse(false)
  container:SetClampedToScreen(true)
  container:Show()       -- toujours visible pour WoW, jamais de Show/Hide en lockdown
  container:SetAlpha(0)  -- visuellement caché au départ : géré par alpha uniquement
  return container
end

---------------------------------------------------------------------------
-- Creation d'un slot
---------------------------------------------------------------------------
local function CreateSlotFrame(index, parent)
  local cfg = ns.GetCfg("priorityBar") or {}
  local size = cfg.iconSize or 34

  -- SecureActionButton : cliquable pour caster le sort
  local frame = CreateFrame("Button", "AishaddonPriorityBarSlot" .. index, parent, "SecureActionButtonTemplate")
  frame:SetSize(size, size)
  frame:SetFrameStrata("MEDIUM")
  frame:SetFrameLevel(60)
  frame:RegisterForClicks("AnyDown", "AnyUp")

  -- Conteneur interne : icone, cooldown, glows et texte de charges sont parentes ici.
  -- La bordure reste sur le button frame et ne glisse pas. C'est ce frame qu'on anime.
  local inner = CreateFrame("Frame", "AishaddonPBInner" .. index, frame)
  inner:SetAllPoints()
  inner:SetFrameLevel(frame:GetFrameLevel() + 1)
  frame.innerFrame = inner

  -- Texture de fond : affiche l'ancienne icone pendant le slide-in de la nouvelle.
  -- Ancree au slot frame (pas a inner) pour rester fixe pendant l'animation.
  frame.iconBg = frame:CreateTexture(nil, "ARTWORK", nil, -1)
  frame.iconBg:SetAllPoints()
  frame.iconBg:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.iconBg:Hide()

  -- Icone du sort (plein cadre dans inner)
  frame.icon = inner:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Frame dummy pour l'animation slide-in (OnUpdate pur Lua, zero taint)
  frame.slideAnimFrame = CreateFrame("Frame", nil, frame)

  -- Cooldown swipe – parente a inner pour suivre le slide
  frame.cooldown = CreateFrame("Cooldown", "AishaddonPBCD" .. index, inner, "CooldownFrameTemplate")
  frame.cooldown:SetAllPoints()
  frame.cooldown:SetDrawSwipe(true)
  frame.cooldown:SetDrawEdge(false)
  frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
  frame.cooldown:SetHideCountdownNumbers(false)
  frame.cooldown:SetFrameLevel(frame:GetFrameLevel() + 2)

  -- Callback quand le cooldown swipe se termine.
  -- Se déclenche aussi quand le GCD expire, OU quand un CD est reset (wipe).
  -- C'est le mécanisme PRINCIPAL pour savoir qu'un sort n'est plus en CD.
  -- En combat, les secret numbers empêchent toute lecture directe : seule
  -- cette callback C-side nous informe fiablement de la fin du CD.
  frame.cooldown:SetScript("OnCooldownDone", function()
    frame._onCooldown = false
    frame._swipeSpellName = nil  -- swipe terminé → libérer pour restart
    -- Nettoyer _realCDEndTimes UNIQUEMENT si le CD est vraiment terminé.
    -- Si le swipe s'est arrêté prématurément (durée pessimiste 3s, ou swipe GCD
    -- qui finit avant le vrai CD), _realCDEndTimes contient encore le bon end-time
    -- du sort — on le préserve pour que UpdateSlotExtras puisse redémarrer le swipe.
    -- Sans ce guard, le clear prématuré effaçait la source de vérité et le swipe
    -- ne redémarrait pas, laissant le sort désaturé sans animation visible.
    if frame.currentSpellID then
      local endTime = _realCDEndTimes[frame.currentSpellID]
      if not endTime or endTime <= GetTime() + 0.3 then
        _realCDEndTimes[frame.currentSpellID] = nil
        local base = overrideToBase[frame.currentSpellID] or frame.currentSpellID
        local baseEnd = _realCDEndTimes[base]
        if not baseEnd or baseEnd <= GetTime() + 0.3 then
          _realCDEndTimes[base] = nil
        end
      end
    end
  end)

  -- Bordure (4 textures + ombre optionnelle)
  frame.borderLines = {}
  for _, side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
    frame.borderLines[side] = frame:CreateTexture(nil, "OVERLAY", nil, 0)
  end

  local function ApplyBorder()
    local c = ns.GetCfg("priorityBar") or {}
    local show = c.showBorder ~= false
    local style = c.borderStyle or "solid"
    local t = c.borderSize or 2
    local bc = c.borderColor or { 0.15, 0.15, 0.15, 0.9 }
    local lines = frame.borderLines

    if not show then
      for _, line in pairs(lines) do line:Hide() end
      if frame.borderShadow then
        for _, s in pairs(frame.borderShadow) do s:Hide() end
      end
      return
    end

    local blend = (style == "glow") and "ADD" or "BLEND"

    lines.TOP:ClearAllPoints(); lines.TOP:SetHeight(t)
    lines.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", -t, t)
    lines.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", t, t)
    lines.TOP:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    lines.TOP:SetBlendMode(blend)

    lines.BOTTOM:ClearAllPoints(); lines.BOTTOM:SetHeight(t)
    lines.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -t, -t)
    lines.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", t, -t)
    lines.BOTTOM:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    lines.BOTTOM:SetBlendMode(blend)

    lines.LEFT:ClearAllPoints(); lines.LEFT:SetWidth(t)
    lines.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", -t, t)
    lines.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -t, -t)
    lines.LEFT:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    lines.LEFT:SetBlendMode(blend)

    lines.RIGHT:ClearAllPoints(); lines.RIGHT:SetWidth(t)
    lines.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", t, t)
    lines.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", t, -t)
    lines.RIGHT:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
    lines.RIGHT:SetBlendMode(blend)

    -- Shadow style : anneau exterieur sombre
    if style == "shadow" then
      if not frame.borderShadow then
        frame.borderShadow = {}
        for _, s in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
          frame.borderShadow[s] = frame:CreateTexture(nil, "OVERLAY", nil, -1)
        end
      end
      local so = frame.borderShadow
      local st = t + 1
      so.TOP:ClearAllPoints(); so.TOP:SetHeight(1)
      so.TOP:SetPoint("TOPLEFT", frame, "TOPLEFT", -st, st)
      so.TOP:SetPoint("TOPRIGHT", frame, "TOPRIGHT", st, st)
      so.TOP:SetColorTexture(0, 0, 0, 0.7); so.TOP:Show()
      so.BOTTOM:ClearAllPoints(); so.BOTTOM:SetHeight(1)
      so.BOTTOM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -st, -st)
      so.BOTTOM:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", st, -st)
      so.BOTTOM:SetColorTexture(0, 0, 0, 0.7); so.BOTTOM:Show()
      so.LEFT:ClearAllPoints(); so.LEFT:SetWidth(1)
      so.LEFT:SetPoint("TOPLEFT", frame, "TOPLEFT", -st, st)
      so.LEFT:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -st, -st)
      so.LEFT:SetColorTexture(0, 0, 0, 0.7); so.LEFT:Show()
      so.RIGHT:ClearAllPoints(); so.RIGHT:SetWidth(1)
      so.RIGHT:SetPoint("TOPRIGHT", frame, "TOPRIGHT", st, st)
      so.RIGHT:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", st, -st)
      so.RIGHT:SetColorTexture(0, 0, 0, 0.7); so.RIGHT:Show()
    elseif frame.borderShadow then
      for _, s in pairs(frame.borderShadow) do s:Hide() end
    end

    for _, line in pairs(lines) do line:Show() end
  end
  ApplyBorder()
  frame.ApplyBorder = ApplyBorder

  -- =========== Glow system (pulse fallback + flipbook) ===========

  -- Container frame for the glow overlays (above icon, below cooldown)
  local glowContainer = CreateFrame("Frame", nil, inner)
  glowContainer:SetAllPoints(inner)
  glowContainer:SetFrameLevel(inner:GetFrameLevel() + 1)
  frame.glowContainer = glowContainer  -- expose pour réappliquer le level après SetParent

  -- Pulse glow texture (legacy alpha-bounce, used only for type #1 "Pulse")
  frame.glow = glowContainer:CreateTexture(nil, "OVERLAY", nil, 1)
  frame.glow:SetBlendMode("ADD")
  frame.glow:SetAlpha(0)
  frame.glow:Hide()

  frame.glowAG = frame.glow:CreateAnimationGroup()
  frame.glowAG:SetLooping("BOUNCE")
  frame.glowPulse = frame.glowAG:CreateAnimation("Alpha")
  frame.glowPulse:SetSmoothing("IN_OUT")

  -- Flipbook loop glow: texture + AnimationGroup owned by the texture
  frame.loopFlipTex = glowContainer:CreateTexture(nil, "OVERLAY", nil, 2)
  frame.loopFlipTex:SetAlpha(0)
  frame.loopFlipTex:Hide()

  frame.loopFlipAG = frame.loopFlipTex:CreateAnimationGroup()
  frame.loopFlipAG:SetLooping("REPEAT")
  frame.loopFlipAnim = frame.loopFlipAG:CreateAnimation("FlipBook")
  frame.loopFlipAnim:SetOrder(1)

  -- Flipbook proc start: texture + AnimationGroup (one-shot)
  frame.procStartTex = glowContainer:CreateTexture(nil, "OVERLAY", nil, 3)
  frame.procStartTex:SetAlpha(0)
  frame.procStartTex:Hide()

  frame.procStartAG = frame.procStartTex:CreateAnimationGroup()
  frame.procStartAG:SetLooping("NONE")
  frame.procStartFlip = frame.procStartAG:CreateAnimation("FlipBook")
  frame.procStartFlip:SetOrder(1)

  -- Applique la config du glow (type, couleur, taille)
  local function ApplyGlowConfig()
    local c = ns.GetCfg("priorityBar") or {}

    -- Resolve glow color
    local glowColor
    if c.useSpecGlowColor then
      local Clr = ns.Modules and ns.Modules.Colors
      if Clr and Clr.Get then glowColor = Clr.Get("glow") end
    end
    glowColor = glowColor or c.glowColor or { 1, 0.85, 0, 0.8 }
    local glowSize = c.glowSize or 4
    local loopIdx = c.loopGlowIndex or 1
    local gt = LOOP_GLOW_TYPES[loopIdx] or LOOP_GLOW_TYPES[1]

    -- === Pulse (type #1) vs Flipbook ===
    if gt.useAlphaPulse then
      -- Legacy pulse mode
      frame.loopFlipAG:Stop(); frame.loopFlipTex:SetAlpha(0); frame.loopFlipTex:Hide()
      frame._useFlipbook = false

      if gt.atlas then
        frame.glow:SetTexture(nil); frame.glow:SetAtlas(gt.atlas); frame.glow:SetTexCoord(0,1,0,1)
      else
        frame.glow:SetTexture(gt.texture)
        if gt.texCoord then frame.glow:SetTexCoord(unpack(gt.texCoord))
        else frame.glow:SetTexCoord(0,1,0,1) end
      end
      frame.glow:SetBlendMode(gt.blendMode or "ADD")
      frame.glow:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
      frame.glow:ClearAllPoints()
      frame.glow:SetPoint("TOPLEFT", inner, "TOPLEFT", -glowSize, glowSize)
      frame.glow:SetPoint("BOTTOMRIGHT", inner, "BOTTOMRIGHT", glowSize, -glowSize)
      frame.glowPulse:SetFromAlpha(gt.fromAlpha or 0.4)
      frame.glowPulse:SetToAlpha(gt.toAlpha or 0.8)
      frame.glowPulse:SetDuration(gt.duration or 0.8)
    else
      -- Flipbook mode
      frame.glowAG:Stop(); frame.glow:SetAlpha(0); frame.glow:Hide()
      frame._useFlipbook = true

      if gt.atlas then
        frame.loopFlipTex:SetTexture(nil); frame.loopFlipTex:SetAtlas(gt.atlas)
      elseif gt.texture then
        frame.loopFlipTex:SetTexture(gt.texture)
      end
      local sc = gt.scale or 1
      local baseSize = (c.iconSize or 34)
      local texSize = baseSize * sc + glowSize * 2
      frame.loopFlipTex:ClearAllPoints()
      frame.loopFlipTex:SetSize(texSize, texSize)
      frame.loopFlipTex:SetPoint("CENTER", inner, "CENTER", 0, 0)
      frame.loopFlipTex:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
      frame.loopFlipTex:SetBlendMode("ADD")
      frame.loopFlipAnim:SetFlipBookRows(gt.rows or 6)
      frame.loopFlipAnim:SetFlipBookColumns(gt.columns or 5)
      frame.loopFlipAnim:SetFlipBookFrames(gt.frames or 30)
      frame.loopFlipAnim:SetDuration(gt.duration or 1.0)
      frame.loopFlipAnim:SetFlipBookFrameWidth(gt.frameW or 0)
      frame.loopFlipAnim:SetFlipBookFrameHeight(gt.frameH or 0)
    end

    -- === Proc start ===
    local psIdx = c.procStartIndex or 1
    local ps = PROC_START_TYPES[psIdx]
    frame._procStartEnabled = (ps and psIdx > 1) or false
    if frame._procStartEnabled then
      if ps.atlas then
        frame.procStartTex:SetTexture(nil); frame.procStartTex:SetAtlas(ps.atlas)
      elseif ps.texture then
        frame.procStartTex:SetTexture(ps.texture)
      end
      local psc = ps.scale or 1
      local psScale = psc * ((c.iconSize or 34) / 42)
      frame.procStartTex:ClearAllPoints()
      frame.procStartTex:SetSize(150, 150)
      frame.procStartTex:SetScale(psScale)
      frame.procStartTex:SetPoint("CENTER", inner, "CENTER", 0, 0)
      frame.procStartTex:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
      frame.procStartTex:SetBlendMode("ADD")
      frame.procStartFlip:SetFlipBookRows(ps.rows or 6)
      frame.procStartFlip:SetFlipBookColumns(ps.columns or 5)
      frame.procStartFlip:SetFlipBookFrames(ps.frames or 30)
      frame.procStartFlip:SetDuration(ps.duration or 0.7)
      frame.procStartFlip:SetFlipBookFrameWidth(ps.frameW or 0)
      frame.procStartFlip:SetFlipBookFrameHeight(ps.frameH or 0)
    end
  end
  ApplyGlowConfig()
  frame.ApplyGlowConfig = ApplyGlowConfig

  -- Overlay au-dessus du cooldown swipe (pour charges)
  local cdOverlay = CreateFrame("Frame", nil, inner)
  cdOverlay:SetAllPoints(inner)
  cdOverlay:SetFrameLevel(inner:GetFrameLevel() + 5)
  frame._cdOverlay = cdOverlay  -- expose pour debug /pbzdbg

  -- Compteur de charges (au-dessus du cooldown swipe)
  frame.chargeText = cdOverlay:CreateFontString(nil, "OVERLAY")
  local chargePos  = cfg.chargePosition or "BOTTOMRIGHT"
  local cx = cfg.chargeOffsetX or 0
  local cy = cfg.chargeOffsetY or 0
  frame.chargeText:SetPoint(chargePos, inner, chargePos, cx, cy)
  frame.chargeText:SetFont(ns.Media.font, cfg.chargeFontSize or 12, "OUTLINE")
  local cc = cfg.chargeColor or { 1, 1, 1, 1 }
  frame.chargeText:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
  frame.chargeText:Hide()

  -- Tooltip
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    if self.currentSpellID then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
      GameTooltip:SetSpellByID(self.currentSpellID)
      GameTooltip:Show()
    end
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- State
  frame.slotIndex = index
  frame.currentSpellID = nil
  frame._isHighlighted = false
  frame._onCooldown = false
  frame.spellIDs = {}

  frame:SetAlpha(1)
  frame:Show()

  return frame
end

---------------------------------------------------------------------------
-- Glow ON / OFF
---------------------------------------------------------------------------
local function StartSlotGlow(slot)
  -- Ré-appliquer systématiquement le frame level du glowContainer à chaque activation,
  -- même si le glow est déjà actif pour le même sort. Corrige toute dérive Z-order
  -- provoquée par PlaySlideIn (ClearAllPoints/SetPoint sur inner) ou un SetParent
  -- WoW interne en cours de combat. Sans ce refresh, l'early return ci-dessous fait
  -- qu'un glow peut rester "caché" indéfiniment derrière l'icône d'un slot voisin.
  if slot.glowContainer and slot.innerFrame then
    slot.glowContainer:SetFrameLevel(slot.innerFrame:GetFrameLevel() + 1)
  end

  if slot.isHighlighted and slot._glowSpellID == slot.currentSpellID then return end
  -- isNewProc = vrai si le slot n'était pas en glow, OU si le sort a changé (slide-in vers un nouveau sort)
  local isNewProc = not slot.isHighlighted or (slot._glowSpellID ~= slot.currentSpellID)
  slot.isHighlighted = true
  slot._glowSpellID  = slot.currentSpellID

  local cfg = ns.GetCfg("priorityBar") or {}
  local gc
  if cfg.spellColors and slot.currentSpellID then
    gc = cfg.spellColors[slot.currentSpellID]
  end
  if not gc and cfg.useSpecGlowColor then
    local Clr = ns.Modules and ns.Modules.Colors
    if Clr and Clr.Get then gc = Clr.Get("glow") end
  end
  gc = gc or cfg.glowColor or { 1, 0.85, 0, 0.8 }

  if slot._useFlipbook then
    -- Flipbook loop glow
    slot.loopFlipTex:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1)
    slot.loopFlipTex:SetAlpha(1)
    slot.loopFlipTex:Show()
    if not slot.loopFlipAG:IsPlaying() then slot.loopFlipAG:Play() end
    -- Proc start (one-shot) on first trigger
    if isNewProc and slot._procStartEnabled then
      slot.procStartTex:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1)
      slot.procStartTex:SetAlpha(1)
      slot.procStartTex:Show()
      slot.procStartAG:Stop()
      slot.procStartAG:Play()
    end
  else
    -- Legacy pulse mode
    slot.glow:SetVertexColor(gc[1], gc[2], gc[3], gc[4] or 1)
    slot.glow:SetAlpha(0.6)
    slot.glow:Show()
    if not slot.glowAG:IsPlaying() then slot.glowAG:Play() end
  end
  Debug("Slot " .. slot.slotIndex .. " GLOW ON → spellID=" .. tostring(slot.currentSpellID))
end

local function StopSlotGlow(slot)
  if not slot.isHighlighted then return end
  slot.isHighlighted = false
  slot._glowSpellID  = nil
  -- Stop all animation systems
  if slot.glowAG then slot.glowAG:Stop() end
  if slot.glow then slot.glow:SetAlpha(0); slot.glow:Hide() end
  if slot.loopFlipAG then slot.loopFlipAG:Stop() end
  if slot.loopFlipTex then slot.loopFlipTex:SetAlpha(0); slot.loopFlipTex:Hide() end
  if slot.procStartAG then slot.procStartAG:Stop() end
  if slot.procStartTex then slot.procStartTex:SetAlpha(0); slot.procStartTex:Hide() end
  Debug("Slot " .. slot.slotIndex .. " GLOW OFF")
end

---------------------------------------------------------------------------
-- Positionnement des slots
---------------------------------------------------------------------------
local function LayoutSlots()
  local cfg = ns.GetCfg("priorityBar") or {}
  local size = cfg.iconSize or 34
  local spacing = cfg.iconSpacing or 6
  local sideOffset = cfg.sideOffset or 150
  local verticalOffset = cfg.verticalOffset or 0

  local layoutDef = GetCurrentLayoutDef()
  local cols = layoutDef.cols
  local rows = layoutDef.rows
  local leftCount  = #layoutDef.leftNames
  local rightCount = #layoutDef.rightNames

  -- Taille des conteneurs selon la grille
  local containerW = cols * size + (cols - 1) * spacing
  local containerH = rows * size + (rows - 1) * spacing
  if leftContainer  then leftContainer:SetSize(containerW, containerH)  end
  if rightContainer then rightContainer:SetSize(containerW, containerH) end

  -- Position : position custom du profil actif si disponible, sinon sideOffset par défaut.
  -- On relit toujours cfg depuis GetCfg pour que les changements de profil soient appliqués.
  local pbCfg = ns.GetCfg("priorityBar") or {}
  if leftContainer then
    leftContainer:ClearAllPoints()
    if pbCfg.leftAnchor then
      leftContainer:SetPoint(pbCfg.leftAnchor, UIParent, pbCfg.leftAnchor, pbCfg.leftX or 0, pbCfg.leftY or 0)
      leftContainer._userPlaced = true
    else
      leftContainer._userPlaced = false
      leftContainer:SetPoint("TOPLEFT", UIParent, "CENTER", -sideOffset, verticalOffset)
    end
  end
  if rightContainer then
    rightContainer:ClearAllPoints()
    if pbCfg.rightAnchor then
      rightContainer:SetPoint(pbCfg.rightAnchor, UIParent, pbCfg.rightAnchor, pbCfg.rightX or 0, pbCfg.rightY or 0)
      rightContainer._userPlaced = true
    else
      rightContainer._userPlaced = false
      rightContainer:SetPoint("TOPRIGHT", UIParent, "CENTER", sideOffset, verticalOffset)
    end
  end

  -- Cacher tous les slots puis repositionner les actifs
  for i = 1, MAX_SLOTS do
    if slotFrames[i] then
      slotFrames[i]:ClearAllPoints()
      slotFrames[i]:Hide()
    end
  end

  -- Helper : réappliquer les niveaux de frame après un SetParent
  -- (SetParent peut perturber les niveaux des sous-frames dans WoW)
  local function ReapplyLevels(f)
    local base = f:GetFrameLevel()
    if f.innerFrame    then f.innerFrame:SetFrameLevel(base + 1) end
    if f.glowContainer then f.glowContainer:SetFrameLevel(base + 2) end
    if f.cooldown      then f.cooldown:SetFrameLevel(base + 2) end
  end

  -- Slots gauche : indices 1..leftCount
  for j = 1, leftCount do
    local f = slotFrames[j]
    if f then
      f:SetParent(leftContainer)
      f:SetFrameLevel(60)
      ReapplyLevels(f)
      local row0 = math.floor((j - 1) / cols)
      local col0 = (j - 1) % cols
      f:SetSize(size, size)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", leftContainer, "TOPLEFT",
                 col0 * (size + spacing), -row0 * (size + spacing))
      -- La visibilité réelle est gérée par ConfigureSlots (slot vide → caché)
      -- On ne montre ici que si le slot n'est pas explicitement caché par _hidden
      if not f._hidden then f:Show() end
    end
  end

  -- Slots droite : indices leftCount+1..totalSlots
  for j = 1, rightCount do
    local i = leftCount + j
    local f = slotFrames[i]
    if f then
      f:SetParent(rightContainer)
      f:SetFrameLevel(60)
      ReapplyLevels(f)
      local row0 = math.floor((j - 1) / cols)
      local col0 = (j - 1) % cols
      f:SetSize(size, size)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", rightContainer, "TOPLEFT",
                 col0 * (size + spacing), -row0 * (size + spacing))
      if not f._hidden then f:Show() end
    end
  end
end

---------------------------------------------------------------------------
-- Cherche si un spellID du slot est highlight
-- On compare EXACTEMENT le spellID du slot avec les IDs detectes
-- (pas d'expansion base/override — on fait confiance au scan brut
-- comme le RotationHelper qui fonctionne).
-- Si ca ne matche pas, on teste aussi l'override courant du sort
-- configure (ex: si le slot a FlameShock 188389, et le bouton affiche
-- Voltaic Blaze 470057 qui est un override → on checke aussi).
---------------------------------------------------------------------------
local function FindHighlightedSpell(slot, glowedSpells)
  if not slot or not slot.spellIDs then return nil end
  for _, spellID in ipairs(slot.spellIDs) do
    -- Match direct
    if glowedSpells[spellID] then
      return spellID
    end
    -- Le bouton pourrait montrer l'override du sort configure
    -- Ex: slot a 188389 (Flame Shock), bouton montre 470057 (Voltaic Blaze)
    if C_Spell and C_Spell.GetOverrideSpell then
      local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
      if ok and overrideID and overrideID ~= spellID and overrideID > 0 then
        if glowedSpells[overrideID] then
          return overrideID
        end
      end
    end
    -- Lien inverse : le sort config est l'override d'un base spell glowé
    -- Ex: slot a 444995 (Totem déferlant), glow sur 1221348 (base spell)
    if FindBaseSpellByID then
      local ok, baseID = pcall(FindBaseSpellByID, spellID)
      if ok and baseID and baseID ~= spellID and baseID > 0 then
        if glowedSpells[baseID] then
          return spellID
        end
      end
    end
  end
  -- Recherche inverse : un spell glowé est le base d'un sort configuré
  -- Couvre le cas où GetOverrideSpell(glowedBase) → sort configuré
  if C_Spell and C_Spell.GetOverrideSpell then
    for glowedID in pairs(glowedSpells) do
      local ok, ov = pcall(C_Spell.GetOverrideSpell, glowedID)
      if ok and ov and ov ~= glowedID and ov > 0 then
        for _, spellID in ipairs(slot.spellIDs) do
          if ov == spellID then
            return spellID
          end
        end
      end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Animation slide-in : l'icone entre par le haut quand le sort affiche change.
-- OnUpdate pur Lua sur une frame dummy → zero taint, zero secret number.
-- Le yOffset passe de +DIST a 0, l'alpha de 0 a 1, avec un ease-out quadratique.
---------------------------------------------------------------------------
local SLIDE_DIST = 20    -- pixels depuis le haut
local SLIDE_DUR  = 0.26 -- secondes

local function PlaySlideIn(slot)
  if not slot.slideAnimFrame or not slot.innerFrame then return end
  local anim  = slot.slideAnimFrame
  local inner = slot.innerFrame
  -- Stopper l'animation precedente si elle tournait encore
  anim:SetScript("OnUpdate", nil)
  -- Copier l'ancienne icone dans iconBg pour la garder visible pendant le slide
  if slot.iconBg then
    local prevTex = slot.icon:GetTexture()
    if prevTex then
      slot.iconBg:SetTexture(prevTex)
      slot.iconBg:Show()
    end
  end
  inner:SetAlpha(0)
  local startTime = GetTime()
  anim:SetScript("OnUpdate", function()
    local t = math.min((GetTime() - startTime) / SLIDE_DUR, 1)
    -- Slide : ease-out cubique pour le mouvement (decelere vite)
    local easeSlide = 1 - (1 - t) * (1 - t) * (1 - t)
    -- Alpha : exponentielle (demarre tres lentement, accelere vers la fin)
    local easeAlpha = t == 0 and 0 or (1 - math.pow(2, -10 * t))
    local yOff = SLIDE_DIST * (1 - easeSlide)
    inner:ClearAllPoints()
    inner:SetPoint("TOPLEFT",     slot, "TOPLEFT",     0,  yOff)
    inner:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0,  yOff)
    inner:SetAlpha(easeAlpha)
    if t >= 1 then
      anim:SetScript("OnUpdate", nil)
      inner:ClearAllPoints()
      inner:SetAllPoints()
      inner:SetAlpha(1)
      if slot.iconBg then slot.iconBg:Hide() end
    end
  end)
end

---------------------------------------------------------------------------
-- Retrouve le slot d'action dans le cache pour un slot de la PriorityBar
---------------------------------------------------------------------------
local function FindActionSlotForSpell(slot)
  if not slot then return nil end
  -- 1) Match sur le spell actuellement affiche
  if slot.currentSpellID and cachedSpellToAction[slot.currentSpellID] then
    return cachedSpellToAction[slot.currentSpellID]
  end
  -- 2) Match sur les base spellIDs configures + leurs overrides
  if slot.spellIDs then
    for _, sid in ipairs(slot.spellIDs) do
      if cachedSpellToAction[sid] then
        return cachedSpellToAction[sid]
      end
      if C_Spell and C_Spell.GetOverrideSpell then
        local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
        if ok and ov and ov ~= sid and ov > 0 and cachedSpellToAction[ov] then
          return cachedSpellToAction[ov]
        end
      end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Recherche CDViewer state pour un slot.
-- Sources, par ordre de priorité :
--   1. ns.Auras.cdmCDData (event-driven : hooks SetCooldown/Clear sur frames CDM)
--      → onCD + cdStart + cdDuration fiables, mis à jour instantanément
--   2. _cdViewerState (polling ScanCooldownViewer, 0.15s)
--      → fournit charges en supplément
-- Le CDViewer indexe par spellID de base (ex: Attaque mentale 8092),
-- mais le PB peut afficher un override (ex: Trait de Vide).
-- On cherche sous : displayedID, baseDisplayed, puis tous les spellIDs
-- configures du slot + leurs overrides inverses (overrideToBase).
---------------------------------------------------------------------------
local function FindCDViewerState(slot)
  -- Source event-driven (plus fiable que IsShown polling)
  local cdmEventData = ns.Auras and ns.Auras.cdmCDData
  local displayedID   = slot.currentSpellID
  local baseDisplayed = overrideToBase[displayedID] or displayedID

  -- Auto-expire une entrée cdmCDData si son timing est dépassé.
  -- Couvre le cas "pool return sans Clear()" : quand un sort à charges repasse
  -- à max charges, le CDM retourne la frame au pool sans forcément appeler Clear().
  local function autoExpire(ev)
    if ev and ev.onCD and ev.cdStart and ev.cdDuration then
      if ev.cdStart + ev.cdDuration <= GetTime() + 0.15 then
        ev.onCD = false  -- auto-expire
      end
    end
  end

  -- Helper interne : pour un ID donné, construit un résultat fusionné.
  -- Préfère cdmEventData pour onCD+timing ; enrichit avec les charges du polling.
  -- Retourne { onCD=false } explicitement quand CDM a signé la fin du CD : signal
  -- clair qui empêche le polling stale ou d'autres spellIDs du slot de retourner
  -- un faux onCD=true pour ce sort.
  local function tryID(id)
    local evEntry = cdmEventData and cdmEventData[id]
    if evEntry then autoExpire(evEntry) end
    local pollEntry = _cdViewerAvail and _cdViewerState[id]

    if evEntry then
      if pollEntry then
        return {
          onCD       = evEntry.onCD,
          cdStart    = evEntry.cdStart    or pollEntry.cdStart,
          cdDuration = evEntry.cdDuration or pollEntry.cdDuration,
          charges    = pollEntry.charges,
        }
      end
      -- Retourner même si onCD=false (signal "pas en CD" explicite).
      return { onCD=evEntry.onCD, cdStart=evEntry.cdStart, cdDuration=evEntry.cdDuration }
    end

    -- Pas de données event-driven → retomber sur le polling
    if pollEntry then return pollEntry end

    -- Chercher aussi sous l'override LIVE (GetOverrideSpell)
    if C_Spell and C_Spell.GetOverrideSpell then
      local ok, ov = pcall(C_Spell.GetOverrideSpell, id)
      if ok and ov and ov ~= id and ov > 0 then
        local evOv = cdmEventData and cdmEventData[ov]
        if evOv then autoExpire(evOv) end
        local pollOv = _cdViewerAvail and _cdViewerState[ov]
        if evOv then
          if pollOv then
            return { onCD=evOv.onCD, cdStart=evOv.cdStart or pollOv.cdStart,
                     cdDuration=evOv.cdDuration or pollOv.cdDuration, charges=pollOv.charges }
          end
          return { onCD=evOv.onCD, cdStart=evOv.cdStart, cdDuration=evOv.cdDuration }
        end
        if pollOv then return pollOv end
      end
    end
    return nil
  end

  -- 1) Match direct (displayedID + base via overrideToBase)
  local cv = tryID(displayedID)
  if cv then return cv end
  if baseDisplayed ~= displayedID then
    cv = tryID(baseDisplayed)
    if cv then return cv end
  end

  -- 2) Chercher sous les spellIDs du slot, UNIQUEMENT ceux qui sont des variantes
  --    du sort affiché (même sort, ID différent via override/base connu).
  --    Filtre "isRelated" : évite de retourner le CD d'un sort INDÉPENDANT du slot
  --    (ex : Lava Lash dans un slot Stormstrike) qui polluerait la durée ou
  --    déclencherait un faux swipe. Ce filtrage est la clé pour les mauvaises durées.
  if slot.spellIDs then
    for _, sid in ipairs(slot.spellIDs) do
      if sid ~= displayedID and sid ~= baseDisplayed then
        -- Le sid est-il une variante du sort affiché ?
        local isRelated = (overrideToBase[sid] == displayedID)
                       or (overrideToBase[sid] == baseDisplayed)
        if not isRelated and C_Spell and C_Spell.GetOverrideSpell then
          -- GetOverrideSpell(sid) retourne le sort actif de sid pendant les
          -- transformations (ex : GetOverrideSpell(Stormstrike)=Windstrike).
          -- Si l'override de sid EST le sort affiché, sid est bien une variante.
          local ok, ovSid = pcall(C_Spell.GetOverrideSpell, sid)
          if ok and ovSid and (ovSid == displayedID or ovSid == baseDisplayed) then
            isRelated = true
          end
        end
        if isRelated then
          cv = tryID(sid)
          if cv then return cv end
          local base = overrideToBase[sid] or sid
          if base ~= sid then
            cv = tryID(base)
            if cv then return cv end
          end
        end
      end
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Mise a jour cooldown / charges / desaturation
-- Approche hybride : cooldown SWIPE en C-to-C (SetCooldown avec secret
-- numbers), mais desaturation et charges en EVENT-DRIVEN.
---------------------------------------------------------------------------
-- Désabonnement CDM swipe pour un slot (appelé à la mise à nil de currentSpellID).
local function ClearSlotCDMSubscription(slot)
  if not (ns.Auras and ns.Auras.UnsubscribeCDMCooldown) then return end
  if slot.currentSpellID then
    ns.Auras.UnsubscribeCDMCooldown(slot.currentSpellID, slot)
    local base = overrideToBase[slot.currentSpellID] or slot.currentSpellID
    if base ~= slot.currentSpellID then
      ns.Auras.UnsubscribeCDMCooldown(base, slot)
    end
  end
end

local function UpdateSlotExtras(slot)
  local cfg = ns.GetCfg("priorityBar") or {}
  if not slot.currentSpellID then return end

  local actionSlot = FindActionSlotForSpell(slot)

  -- 1) Cooldown swipe : GetSpellCooldownDuration → SetCooldownFromDurationObject
  --    (chemin combat-safe, aucune comparaison de secret number en Lua).
  --    Uniquement pour slot.currentSpellID (sort affiché).
  --    Si showCooldownSwipe == false, on force Clear+Hide a chaque tick.
  --    Si le sort est highlighted (proc/reset), on annule le swipe et le tracking.
  if slot.cooldown then
    local showSwipe = cfg.showCooldownSwipe ~= false
    local showText  = cfg.showCooldownText  ~= false
    if not showSwipe and not showText then
      slot.cooldown:Clear()
      slot.cooldown:Hide()
      slot._swipeSpellName = nil
      slot._onCooldown = false
    elseif slot._isHighlighted then
      -- Sort procce ou recommande : le CD a ete reset, annuler le swipe
      slot.cooldown:Clear()
      slot._swipeSpellName = nil
      slot._onCooldown = false
      if slot.currentSpellID then
        local base = overrideToBase[slot.currentSpellID] or slot.currentSpellID
        _realCDEndTimes[slot.currentSpellID] = nil
        _realCDEndTimes[base] = nil
      end
    else
      -- CD swipe : C_Spell.GetSpellCooldown (nombres propres) pour détecter GCD vs vrai CD.
      -- SetCooldownFromDurationObject pour l'animation (durObj opaque → aucune lecture Lua).
      -- On utilise UNIQUEMENT slot.currentSpellID (sort affiché) pour ne jamais
      -- déclencher le swipe d'un sort caché du même slot.
      local curID  = slot.currentSpellID
      local baseID = curID and (overrideToBase[curID] or curID)

      -- isActive est un booléen (safe) : true = vrai CD de sort, false = GCD seul.
      -- En TWW isActive peut être vrai même pour un GCD pur sur certains sorts.
      local spellCD  = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(curID)
      if not spellCD and baseID and baseID ~= curID then
        spellCD = C_Spell.GetSpellCooldown(baseID)
      end
      local isRealCD = spellCD and spellCD.isActive
      local _chSwipeSid = chargeCache[curID] and curID
                       or (baseID ~= curID and chargeCache[baseID] and baseID)
      -- hideGCDSwipe : sorts normaux uniquement (pas les sorts à charges).
      -- Pour les charges, GetSpellCooldown.duration retourne 0 en TWW (pas la durée
      -- de recharge) → impossible de distinguer GCD de recharge via durée.
      -- Les sorts à charges utilisent isActive + SetCooldownFromDurationObject naturellement.
      if cfg.hideGCDSwipe and isRealCD and not _chSwipeSid then
        local _cdmD = ns.Auras and ns.Auras.cdmCDData
        local _cdmE = _cdmD and (_cdmD[curID] or (baseID ~= curID and _cdmD[baseID]) or nil)
        if not (_cdmE and _cdmE.onCD) then isRealCD = false end
      end

      if isRealCD then
        -- Vrai CD : alimenter le frame avec le durObj opaque (aucune lecture en Lua)
        local durObj = C_Spell.GetSpellCooldownDuration(curID)
                       or (baseID ~= curID and C_Spell.GetSpellCooldownDuration(baseID))
        if durObj then
          pcall(slot.cooldown.SetCooldownFromDurationObject, slot.cooldown, durObj)
          slot.cooldown:SetDrawSwipe(showSwipe)
          slot.cooldown:SetHideCountdownNumbers(not showText)
          slot.cooldown:Show()
          slot._onCooldown     = true
          slot._swipeSpellName = curID and GetSpellName(curID)
        else
          slot.cooldown:Clear()
          slot._onCooldown     = false
          slot._swipeSpellName = nil
        end
      else
        slot.cooldown:Clear()
        slot._onCooldown     = false
        slot._swipeSpellName = nil
      end
    end
  end

  -- 2) Desaturation : CDViewer est la source de verite en combat.
  --    Sort a charges : desat quand CDViewer charges == 0, ou fallback estimatedCharges == 0
  --    Sort normal    : desat quand CDViewer onCD == true, ou fallback _realCDEndTimes actif
  --    IMPORTANT : on ne consulte le CDViewer QUE pour les sorts avec un vrai CD
  --    connu (spellCDBase > 1.5s) ou un sort a charges.  Les fillers sans CD
  --    (ex: Fouet Mental) apparaissent aussi dans le CDViewer pendant leur
  --    cast/channel (bordure verte = buff) mais ne doivent PAS etre desatures.
  if cfg.desaturateOnCooldown then
    local desat = false

    if not slot._isHighlighted then
      local displayedID   = slot.currentSpellID
      local baseDisplayed = overrideToBase[displayedID] or displayedID

      -- isChargeSpell : uniquement pour le sort AFFICHÉ (displayedID / baseDisplayed).
      -- Ne pas itérer slot.spellIDs : un sort caché à charges ne doit jamais
      -- provoquer la désaturation du sort affiché qui, lui, est disponible.
      local isChargeSpell = chargeCache[displayedID] or chargeCache[baseDisplayed]
      local chargeSid     = chargeCache[displayedID] and displayedID
                         or (chargeCache[baseDisplayed] and baseDisplayed or nil)

      local _cdmData  = ns.Auras and ns.Auras.cdmCDData
      local hasRealCD = (spellCDBase[displayedID] and spellCDBase[displayedID] > 1.5)
                     or (spellCDBase[baseDisplayed] and spellCDBase[baseDisplayed] > 1.5)
                     -- Fallback live : le sort est dans _cdViewerState (CDM utility viewer)
                     -- avec onCD=true → il est sur un vrai CD, même si spellCDBase l'ignore.
                     or (_cdViewerAvail
                         and (_cdViewerState[displayedID] and _cdViewerState[displayedID].onCD
                              or _cdViewerState[baseDisplayed] and _cdViewerState[baseDisplayed].onCD)
                         and true or false)
                     -- Fallback event-driven : cdmCDData signale un vrai CD (wasSetFromCooldown+!isOnGCD).
                     -- Couvre le cas où spellCDBase est nil et le CDViewer n'a pas encore scanné.
                     or (_cdmData and (_cdmData[displayedID] or _cdmData[baseDisplayed]) and true or false)
      local cvState = (hasRealCD or isChargeSpell) and FindCDViewerState(slot) or nil

      if isChargeSpell then
        -- Desat uniquement si charges == 0 CONFIRMÉES.
        -- On évite toute lecture via GetSpellCharges (contexte tainté PollSlots :
        -- tonumber/tostring peut retourner nil → ancienne faute) et
        -- GetAuthoritativeCharges/TryLiveReadCharges (fallback "cooldownDuration==0"
        -- peut corrompre estimatedCharges si l'arithmétique sur secret number
        -- retourne 0 de façon incorrecte).
        --
        -- Source 1 : cvState.charges (CDViewer via GetText sur FontString Blizzard
        --   = valeur propre garantie, ticker isolé)
        -- Source 2 : estimatedCharges (maintenu par SyncChargesOOC appelé depuis
        --   les event handlers SPELL_UPDATE_CHARGES en contexte propre)
        -- Si aucune source fiable : pas de désaturation (optimiste).
        if chargeSid then
          local cur = nil
          if cvState and type(cvState.charges) == "number" then
            -- Valeur directe : 0, 1, 2 … issue du ChargeCount FontString Blizzard
            cur = cvState.charges
          end
          if cur == nil then
            -- Fallback : estimatedCharges maintenu par SyncChargesOOC + event handlers.
            -- On N'utilise PAS cvState.onCD comme proxy pour charges==0 : quand
            -- le sort a 1 charge restante et qu'une 2ème recharge, onCD=true mais
            -- le sort est utilisable → désaturation incorrecte si on assume cur=0.
            cur = CleanInt(estimatedCharges[chargeSid])
          end
          if cur ~= nil then
            desat = (cur == 0)
          end
        end
      else
        -- Sort normal (pas de charges) : vrai CD uniquement, jamais GCD seul.
        -- Source 1 : cvState (event-driven cdmCDData, filtré wasSetFromCooldown+!isOnGCD).
        --   Prioritaire car zéro-lag et fiable sur toute la durée du CD.
        -- Source 2 : _cdViewerState polling (filtre isOnGCD → GCDs exclus).
        -- Source 3 : _realCDEndTimes (set par SPELLCAST_SUCCEEDED, jamais GCD).
        if cvState then
          desat = cvState.onCD
        else
          local cvPoll = _cdViewerAvail and (_cdViewerState[displayedID] or _cdViewerState[baseDisplayed])
          if cvPoll then
            desat = cvPoll.onCD
          else
            local cdEnd = _realCDEndTimes[displayedID] or _realCDEndTimes[baseDisplayed]
            desat = cdEnd ~= nil and GetTime() < cdEnd
          end
        end
      end
    end

    slot.icon:SetDesaturated(desat)
  else
    slot.icon:SetDesaturated(false)
  end

  -- 3) Charges : afficher uniquement quand le sort AFFICHE est le sort a charges
  --    (ou son override live). Ne pas afficher quand un AUTRE sort du slot a des
  --    charges mais que c'est un sort different qui est affiche (ex: Torrent du Vide
  --    affiche dans le slot Y ne doit pas montrer les charges d'Attaque Mentale).
  if slot.chargeText and cfg.showCharges then
    local displayedID   = slot.currentSpellID
    local baseDisplayed = overrideToBase[displayedID] or displayedID

    -- Match direct : le sort affiche est dans chargeCache
    local isChargeSpell = chargeCache[displayedID] or chargeCache[baseDisplayed]
    local chargeSid     = chargeCache[displayedID] and displayedID
                       or (chargeCache[baseDisplayed] and baseDisplayed or nil)

    -- Match override live : le sort affiche est l'override actuel d'un sort a charges
    -- Ex: Attaque Mentale (8092) → Trait de Vide pendant Voidform
    if not isChargeSpell and slot.spellIDs and C_Spell and C_Spell.GetOverrideSpell then
      for _, sid in ipairs(slot.spellIDs) do
        if chargeCache[sid] then
          local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
          if ok and ov and ov == displayedID then
            isChargeSpell = true; chargeSid = sid; break
          end
        end
      end
    end

    if isChargeSpell and chargeSid and C_Spell and C_Spell.GetSpellCharges then
      -- Lecture directe, identique à TestCharges.lua.
      -- SetText accepte la valeur brute : pas de conversion, pas d'estimation,
      -- pas de fallback. Si pcall échoue (API indisponible), on cache.
      local ok, cInfo = pcall(C_Spell.GetSpellCharges, chargeSid)
      if ok and cInfo then
        slot.chargeText:SetText(cInfo.currentCharges)
        slot.chargeText:Show()
      else
        slot.chargeText:Hide()
      end
    else
      slot.chargeText:Hide()
    end
  elseif slot.chargeText then
    slot.chargeText:Hide()
  end
end

---------------------------------------------------------------------------
-- Mise a jour d'un slot : icone + glow
---------------------------------------------------------------------------
local function UpdateSlot(slot, glowedSpells)
  if not slot or not slot.spellIDs or #slot.spellIDs == 0 then
    -- Slot vide : cacher la frame entière (pas seulement la texture)
    if slot and slot:IsShown() then slot:Hide(); slot._hidden = true end
    return
  end

  -- Hide unlearned : utilise le cache learnedSpells (construit hors combat uniquement).
  -- On ne teste JAMAIS IsPlayerSpell ici pour eviter les secret booleans en combat.
  -- Fail-open si le cache est vide (pas encore construit au premier tick).
  local cfg = ns.GetCfg("priorityBar") or {}
  if cfg.hideUnlearned and next(learnedSpells) ~= nil then
    local anyKnown = false
    for _, sid in ipairs(slot.spellIDs) do
      if learnedSpells[sid] then anyKnown = true; break end
    end
    if not anyKnown then
      slot:Hide()
      slot._hidden = true
      return
    elseif slot._hidden then
      slot._hidden = false
      slot:Show()
    end
  elseif slot._hidden then
    slot._hidden = false
    slot:Show()
  end

  local highlightedID = FindHighlightedSpell(slot, glowedSpells)

  -- Sort a afficher par defaut : premier sort APPRIS de la liste.
  -- Si le cache est vide (pas encore construit), fallback sur spellIDs[1].
  -- Résout aussi l'override pour afficher l'icone live (ex: proc qui remplace).
  local defaultID = nil
  local cacheReady = next(learnedSpells) ~= nil
  for _, sid in ipairs(slot.spellIDs) do
    if not cacheReady or learnedSpells[sid] then
      defaultID = sid
      break
    end
  end
  -- Fallback ultime : prendre le premier si aucun sort appris (ne devrait pas arriver)
  if not defaultID then defaultID = slot.spellIDs[1] end
  if not highlightedID and defaultID and C_Spell and C_Spell.GetOverrideSpell then
    local ok, ov = pcall(C_Spell.GetOverrideSpell, defaultID)
    if ok and ov and ov ~= defaultID and ov > 0 then
      defaultID = ov
    end
  end

  local displayID = highlightedID or defaultID

  -- Changer l'icone si necessaire + rafraichir pour les proc icon swaps.
  -- GetActionTexture(slot) retourne l'icone LIVE de la barre d'action, incluant
  -- les procs qui remplacent l'icone (ex : Ravage proc sur Druid Guardian remplace
  -- l'icone de Mutiler/Destruction Massive).  GetSpellTexture lui est statique.
  -- IMPORTANT : GetActionTexture n'est utilise QUE pour les sorts highlighted,
  -- car le bouton Blizzard peut etre visuellement override par un autre sort
  -- (ex: Voidform remplace Mot de l'ombre:Folie par Torrent du Vide sur le
  -- meme bouton). Pour les sorts non-highlighted, on utilise GetSpellIcon
  -- qui retourne toujours l'icone du spellID demande.
  do
    local tex
    if highlightedID then
      -- Sort highlighted : utiliser GetActionTexture pour le proc icon swap
      -- (ex: Ravage remplace Mutiler sur le même bouton sans changer le spellID).
      -- On n'utilise QUE le lookup direct displayID→actionSlot.
      -- Le fallback sur d'autres spellIDs du slot est dangereux après un
      -- changement de forme Druide : le slot caché pointe vers un bouton
      -- qui affiche maintenant un sort complètement différent.
      local actionSlotForIcon = cachedSpellToAction[displayID]
      if actionSlotForIcon then
        local ok, actionTex = pcall(GetActionTexture, actionSlotForIcon)
        if ok and actionTex then tex = actionTex end
      end
      tex = tex or GetSpellIcon(displayID)
    else
      -- Sort par defaut (non-highlighted) : icone statique du spellID
      tex = GetSpellIcon(displayID)
    end

    -- Mettre a jour si le sort OU la texture a change (proc swap sans changement de spellID).
    if tex and (displayID ~= slot.currentSpellID or tex ~= slot._displayTex) then
      slot.icon:SetTexture(tex)
      slot._displayTex = tex
    end
    if displayID ~= slot.currentSpellID then
      local hadSpell = slot.currentSpellID ~= nil
      -- Mise à jour de l'abonnement CDM swipe clone : désabonner l'ancien sort,
      -- s'abonner au nouveau. On s'abonne sous displayID ET sous son ID de base
      -- (overrideToBase) car le CDM peut indexer le CD sous l'un ou l'autre.
      if ns.Auras and ns.Auras.UnsubscribeCDMCooldown then
        if slot.currentSpellID then
          ns.Auras.UnsubscribeCDMCooldown(slot.currentSpellID, slot)
          local oldBase = overrideToBase[slot.currentSpellID] or slot.currentSpellID
          if oldBase ~= slot.currentSpellID then
            ns.Auras.UnsubscribeCDMCooldown(oldBase, slot)
          end
        end
        -- forDisplayID = displayID : guard qui empêche les sorts cachés du même
        -- slot de déclencher le swipe du sort affiché.
        ns.Auras.SubscribeCDMCooldown(displayID, slot, slot.cooldown, slot, displayID)
        local newBase = overrideToBase[displayID] or displayID
        if newBase ~= displayID then
          -- Le CDM track le CD sous l'ID de base (ex: StormStrike) même quand
          -- le sort affiché est l'override (ex: WindStrike). forDisplayID reste
          -- displayID pour que le guard slot.currentSpellID == forDisplayID soit valide.
          ns.Auras.SubscribeCDMCooldown(newBase, slot, slot.cooldown, slot, displayID)
        end
      end
      slot.currentSpellID = displayID
      -- Le sort a changé → clear le swipe s'il était pour un autre sort
      if slot.cooldown and slot._swipeSpellName then
        local newName = GetSpellName(displayID)
        if newName ~= slot._swipeSpellName then
          local oldSwipe = slot._swipeSpellName
          slot.cooldown:Clear()
          slot._swipeSpellName = nil
          slot._onCooldown = false
          Debug("Slot " .. slot.slotIndex .. " swipe cleared (was " .. oldSwipe .. ", now " .. (newName or "?") .. ")")
        end
      end
      Debug("Slot " .. slot.slotIndex .. " → " .. GetSpellName(displayID) .. " (" .. displayID .. ")" .. (highlightedID and " [HL]" or ""))
      -- Animer uniquement quand on remplace un sort existant (pas au premier affichage)
      if hadSpell then PlaySlideIn(slot) end
    end
  end

  -- Tracker le highlight pour la desaturation
  slot._isHighlighted = (highlightedID ~= nil)

  -- Glow : on/off
  if highlightedID then
    StartSlotGlow(slot)
  else
    StopSlotGlow(slot)
  end

  -- Cooldown, charges, desaturation
  UpdateSlotExtras(slot)
end

---------------------------------------------------------------------------
-- Polling : scan les highlights et met a jour les 4 slots
---------------------------------------------------------------------------
local function PollSlots()
  if testMode then return end
  -- Skip si aucun conteneur visible : pas la peine de scanner les glows
  if (not leftContainer or not leftContainer:IsVisible()) and
     (not rightContainer or not rightContainer:IsVisible()) then
    return
  end
  -- ScanCooldownViewer() tourne sur son propre ticker isole (voir StartPolling)
  local glowedSpells = CollectGlowedSpells()
  for i = 1, MAX_SLOTS do
    if slotFrames[i] and slotFrames[i]:IsShown() then
      UpdateSlot(slotFrames[i], glowedSpells)
    end
  end
end

local function StartPolling()
  if pollTicker then return end
  pollTicker = C_Timer.NewTicker(0.15, PollSlots)
  -- Ticker isole pour le scan CDViewer : s'execute dans un contexte
  -- d'execution separe pour eviter toute propagation de taint vers
  -- les fonctions de PollSlots (GetOverrideSpell, GetActionTexture, etc.)
  if not cdViewerTicker then
    cdViewerTicker = C_Timer.NewTicker(0.15, ScanCooldownViewer)
  end
  Debug("Polling started")
end

local function StopPolling()
  if pollTicker then pollTicker:Cancel(); pollTicker = nil end
  if cdViewerTicker then cdViewerTicker:Cancel(); cdViewerTicker = nil end
  Debug("Polling stopped")
end

---------------------------------------------------------------------------
-- Helpers securises pour Show/Hide les conteneurs
---------------------------------------------------------------------------
local function SafeShowContainers()
  if leftContainer  then leftContainer:SetAlpha(1)  end
  if rightContainer then rightContainer:SetAlpha(1) end
end

local function SafeHideContainers()
  if leftContainer  then leftContainer:SetAlpha(0)  end
  if rightContainer then rightContainer:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Visibilité pure Lua (même pattern que ResourceCircle) :
-- ShouldShow → lastVisState debounce → AnimatePB fade
---------------------------------------------------------------------------
local pbLastVisState       = nil   -- true/false/nil — dernier état connu
local pbHiddenForSkyriding = false -- masqué explicitement pour le skyriding
local pbHiddenForGui       = false -- masqué quand le panneau Animations 3D est ouvert

local function PBShouldShow()
  if pbHiddenForGui       then return false end
  if pbHiddenForSkyriding then return false end
  local cfg = ns.GetCfg("priorityBar") or {}
  if cfg.enabled == false then return false end
  if ns.IsInBlockedState() then return false end
  if dragEnabled then return true end
  local vMode = cfg.visibilityMode or "combat"
  if vMode == "always" then return true end
  if vMode == "target"  then return UnitExists("target") end
  -- "combat"
  return UnitAffectingCombat("player") and true or false
end

local function AnimatePB(shouldShow)
  if pbFadeTicker then pbFadeTicker:Cancel(); pbFadeTicker = nil end
  if shouldShow then
    -- Déjà complètement visible : rien à faire
    if leftContainer and leftContainer:GetAlpha() >= 1 then return end
    if leftContainer  then leftContainer:SetAlpha(0)  end
    if rightContainer then rightContainer:SetAlpha(0) end
    local _t0 = GetTime()
    pbFadeTicker = C_Timer.NewTicker(0.016, function()
      local _p = math.min((GetTime() - _t0) / 0.35, 1)
      local _a = 1 - (1 - _p)^3
      if leftContainer  then leftContainer:SetAlpha(_a)  end
      if rightContainer then rightContainer:SetAlpha(_a) end
      if _p >= 1 then pbFadeTicker:Cancel(); pbFadeTicker = nil end
    end)
  else
    -- Déjà complètement caché : rien à faire
    if leftContainer and leftContainer:GetAlpha() <= 0 then return end
    if leftContainer  then leftContainer:SetAlpha(1)  end
    if rightContainer then rightContainer:SetAlpha(1) end
    local _t0 = GetTime()
    pbFadeTicker = C_Timer.NewTicker(0.016, function()
      local _p = math.min((GetTime() - _t0) / 0.35, 1)
      local _a = (1 - _p)^3
      if leftContainer  then leftContainer:SetAlpha(_a)  end
      if rightContainer then rightContainer:SetAlpha(_a) end
      if _p >= 1 then
        pbFadeTicker:Cancel(); pbFadeTicker = nil
        if leftContainer  then leftContainer:SetAlpha(0)  end
        if rightContainer then rightContainer:SetAlpha(0) end
      end
    end)
  end
end

function PriorityBar.SetSkyridingActive(active)
  if not leftContainer then return end
  pbHiddenForSkyriding = active
  -- Pas de reset de pbLastVisState : le debounce de UpdateVisibility
  -- détecte naturellement le changement via PBShouldShow().
  PriorityBar.UpdateVisibility()
end

function PriorityBar.SetGuiHidden(on)
  if not leftContainer then return end
  pbHiddenForGui = on
  pbLastVisState = nil  -- forcer UpdateVisibility à réévaluer
  PriorityBar.UpdateVisibility()
end

function PriorityBar.UpdateVisibility()
  if not leftContainer then return end
  local shouldShow = PBShouldShow()
  if shouldShow == pbLastVisState then return end
  pbLastVisState = shouldShow
  AnimatePB(shouldShow)
end

---------------------------------------------------------------------------
-- Configuration des slots
---------------------------------------------------------------------------
function PriorityBar.ConfigureSlots(slotConfigs)
  if InCombatLockdown() then
    Debug("ConfigureSlots skipped (in combat)")
    return
  end
  local layoutDef = GetCurrentLayoutDef()
  local totalSlots = layoutDef and layoutDef.totalSlots or 4
  for i = 1, MAX_SLOTS do
    local slotCfg = slotConfigs and slotConfigs[i]
    if i <= totalSlots and slotCfg and slotFrames[i] then
      slotFrames[i].spellIDs = slotCfg.spellIDs or {}
      slotFrames[i].slotName = slotCfg.name or ("Slot " .. i)
      -- Reset glow
      slotFrames[i].isHighlighted = true
      StopSlotGlow(slotFrames[i])

      -- Configurer le SecureActionButton (hors combat seulement)
      -- Macro /cast Spell1 \n /cast Spell2 ... pour multi-sorts
      local macroLines = {}
      for _, sid in ipairs(slotCfg.spellIDs or {}) do
        local name = GetSpellName(sid)
        if name and name ~= ("Spell#" .. tostring(sid)) then
          macroLines[#macroLines + 1] = "/cast " .. name
        end
      end
      if #macroLines > 0 then
        slotFrames[i]:SetAttribute("type", "macro")
        slotFrames[i]:SetAttribute("macrotext", table.concat(macroLines, "\n"))
      end

      -- Afficher le premier sort par defaut
      if #slotFrames[i].spellIDs > 0 then
        local defaultID = slotFrames[i].spellIDs[1]
        if C_Spell and C_Spell.GetOverrideSpell then
          local ok, ov = pcall(C_Spell.GetOverrideSpell, defaultID)
          if ok and ov and ov ~= defaultID and ov > 0 then defaultID = ov end
        end
        local tex = GetSpellIcon(defaultID)
        if tex then
          slotFrames[i].icon:SetTexture(tex)
          slotFrames[i].currentSpellID = defaultID
        end
        -- S'assurer que le slot est visible (peut avoir été caché sur un profil précédent)
        slotFrames[i]._hidden = false
        slotFrames[i]:Show()
      else
        -- Slot vide dans le profil courant : vider et cacher la frame entière
        slotFrames[i].icon:SetTexture(nil)
        ClearSlotCDMSubscription(slotFrames[i])
        slotFrames[i].currentSpellID = nil
        slotFrames[i]._hidden = true
        slotFrames[i]:Hide()
      end
      Debug("Slot " .. i .. " configured: " .. (slotCfg.name or "?") .. " (" .. #(slotCfg.spellIDs or {}) .. " spells)")
    elseif slotFrames[i] then
      -- Aucune config pour ce slot dans le profil courant : vider et cacher
      slotFrames[i].spellIDs       = {}
      slotFrames[i].slotName       = "Slot " .. i
      ClearSlotCDMSubscription(slotFrames[i])
      slotFrames[i].currentSpellID = nil
      slotFrames[i].icon:SetTexture(nil)
      slotFrames[i].isHighlighted  = true
      StopSlotGlow(slotFrames[i])
      slotFrames[i]:SetAttribute("type",      nil)
      slotFrames[i]:SetAttribute("macrotext", "")
      slotFrames[i]._hidden = true
      slotFrames[i]:Hide()
    end
  end
  -- Les spellIDs sont maintenant à jour : reconstruire le cache des sorts appris
  -- immédiatement (ConfigureSlots est toujours appelé hors combat).
  RebuildLearnedCache()
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------
-- Exposer slotFrames pour le debug (/aishdebug pbslots)
PriorityBar._debug_slotFrames = slotFrames
-- Exposer les tables internes pour le debug (/aishdebug pbcharges)
PriorityBar._debug_internals = {
  chargeCache      = chargeCache,
  overrideToBase   = overrideToBase,
  estimatedCharges = estimatedCharges,
  _cdViewerState   = _cdViewerState,
  spellCDBase      = spellCDBase,
  _realCDEndTimes  = _realCDEndTimes,
  SecretToNumber   = SecretToNumber,
}
-- _cdViewerAvail est un boolean plain → getter pour accès live
PriorityBar._debug_getCdViewerAvail = function() return _cdViewerAvail end

-- [12.0.5] Helpers pour /aish charges : accès aux tables internes depuis
-- le slash command sans exposer les tables complètes.
function PriorityBar._GetCachedBtn(spellID)
  return cachedSpellToButton and cachedSpellToButton[spellID] or nil
end
function PriorityBar._GetLiveCharge(btn)
  return liveChargeByButton and liveChargeByButton[btn] or nil
end
function PriorityBar._GetEstimated(spellID)
  return estimatedCharges and estimatedCharges[spellID] or nil
end
function PriorityBar._GetMaxCharges(spellID)
  return chargeCache and chargeCache[spellID] or nil
end
function PriorityBar._GetLiveByID(spellID)
  return liveChargesByID and liveChargesByID[spellID] or nil
end
function PriorityBar._GetChargesStats()
  return _chargesStats
end
function PriorityBar._GetActionSlot(spellID)
  return cachedSpellToAction and cachedSpellToAction[spellID] or nil
end

-- [12.0.5 diag] Dump instantané de chaque slot qui référence spellID :
-- affiche slot index, visible?, currentSpellID (= ce qui s'affiche), liste des
-- spellIDs, détecte si le render aurait reconnu "isChargeSpell".
function PriorityBar._DumpSlotsForSpell(spellID)
  print("|cff00ccff  -- Slots PB référençant " .. tostring(spellID) .. " --|r")
  local anyFound = false
  for i, slot in ipairs(slotFrames or {}) do
    if slot and slot.spellIDs then
      local hit = false
      for _, sid in ipairs(slot.spellIDs) do
        if sid == spellID then hit = true; break end
      end
      if hit then
        anyFound = true
        local displayed = slot.currentSpellID
        local base      = overrideToBase[displayed] or displayed
        local isChargeSpell = chargeCache[displayed] or chargeCache[base]
        local chargeSid = (chargeCache[displayed] and displayed)
                       or (chargeCache[base] and base)
                       or nil
        -- Si pas de match direct, tenter override live (comme dans le render)
        if not isChargeSpell and C_Spell and C_Spell.GetOverrideSpell then
          for _, sid in ipairs(slot.spellIDs) do
            if chargeCache[sid] then
              local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
              if ok and ov and ov == displayed then
                isChargeSpell = true; chargeSid = sid; break
              end
            end
          end
        end
        local chText = "—"
        if slot.chargeText then
          chText = (slot.chargeText:IsShown() and (slot.chargeText:GetText() or "")) or "hidden"
        end
        print(string.format("  slot%d visible=%s current=%s base=%s isCharge=%s chSid=%s chargeText=%s",
          i, tostring(slot:IsShown()), tostring(displayed), tostring(base),
          tostring(isChargeSpell and true or false), tostring(chargeSid), tostring(chText)))
      end
    end
  end
  if not anyFound then
    print("  (aucun slot PB ne contient ce spellID)")
  end
end

function PriorityBar.Init()
  if initialized then return end
  initialized = true

  leftContainer = CreateContainer("AishaddonPBLeft")
  rightContainer = CreateContainer("AishaddonPBRight")

  slotFrames[1] = CreateSlotFrame(1, leftContainer)
  slotFrames[2] = CreateSlotFrame(2, leftContainer)
  slotFrames[3] = CreateSlotFrame(3, rightContainer)
  slotFrames[4] = CreateSlotFrame(4, rightContainer)
  -- Slots supplémentaires pour les layouts étendus (5-12)
  -- Initialement cachés ; LayoutSlots() les re-parentera et positionnera
  for i = 5, MAX_SLOTS do
    slotFrames[i] = CreateSlotFrame(i, leftContainer)
    slotFrames[i]:Hide()
  end

  LayoutSlots()

  -- Restaurer les positions sauvegardees
  local cfg = ns.GetCfg("priorityBar") or {}
  if cfg.leftAnchor then
    leftContainer:ClearAllPoints()
    leftContainer:SetPoint(cfg.leftAnchor, UIParent, cfg.leftAnchor, cfg.leftX or 0, cfg.leftY or 0)
    leftContainer._userPlaced = true
  end
  if cfg.rightAnchor then
    rightContainer:ClearAllPoints()
    rightContainer:SetPoint(cfg.rightAnchor, UIParent, cfg.rightAnchor, cfg.rightX or 0, cfg.rightY or 0)
    rightContainer._userPlaced = true
  end

  -- Charger la config des slots selon la spec active
  C_Timer.After(0.1, function()
    local initSlots = PriorityBar.GetCurrentSpecSlots()
    PriorityBar.ConfigureSlots(initSlots)
  end)

  leftContainer:SetAlpha(0)
  rightContainer:SetAlpha(0)

  -- Évaluation initiale de la visibilité (remplace RegisterCombatStateDriver)
  PriorityBar.UpdateVisibility()

  -- Frame d'evenements pour reconstruire le cache bouton→sort hors combat
  local eventFrame = CreateFrame("Frame")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  eventFrame:RegisterEvent("UPDATE_MACROS")
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  -- Snapshot du cache au décollage Dragonriding :
  -- UNIT_POWER_BAR_SHOW/HIDE sont des unit-events : RegisterUnitEvent obligatoire.
  -- UNIT_POWER_BAR_SHOW se déclenche quand la barre Dragonriding (ID 631) apparaît.
  -- UNIT_POWER_BAR_HIDE = dismount → restaurer immédiatement, même en combat.
  eventFrame:RegisterUnitEvent("UNIT_POWER_BAR_SHOW", "player")
  eventFrame:RegisterUnitEvent("UNIT_POWER_BAR_HIDE", "player")
  -- UNIT_SPELLCAST_START sur le joueur : prendre le snapshot AVANT que la barre
  -- change. C'est le signal le plus precoce du montage (avant ACTIONBAR_SLOT_CHANGED).
  -- On prend un snapshot preventif pour tout cast ; il sera ecrase ou valide selon
  -- que UNIT_POWER_BAR_SHOW suit dans les prochains frames.
  eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
  -- UNIT_SPELLCAST_SUCCEEDED : savoir quand le joueur lance un sort.
  -- C'est le mecanisme PRINCIPAL pour detecter les CD en combat (event-driven).
  eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  -- SPELL_UPDATE_COOLDOWN : detecter les CD resets (wipes) en combat.
  -- On ne peut pas lire les valeurs, mais le prochain tick de polling passera
  -- GetActionCooldown(0,0) a SetCooldown → OnCooldownDone fire → un-desat.
  eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  -- SPELL_UPDATE_CHARGES : backup pour re-sync les charges si notre estimation derive.
  eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
  eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    -- UNIT_SPELLCAST_START : snapshot préventif avant que la barre d'action change.
    -- Couvre le cas où ACTIONBAR_SLOT_CHANGED arrive avant UNIT_POWER_BAR_SHOW.
    -- On snap à chaque début de cast (overhead minimal, juste copie de tables).
    -- Le snapshot sera validé par UNIT_POWER_BAR_SHOW, ou ignoré si c'est un cast normal.
    if event == "UNIT_SPELLCAST_START" then
      if not InCombatLockdown() and not _hasDrakeSnapshot then
        wipe(_preDrakeButtonData)
        wipe(_preDrakeSpellToAction)
        for k, v in pairs(cachedButtonData)    do _preDrakeButtonData[k]   = { button = v.button, spellID = v.spellID } end
        for k, v in pairs(cachedSpellToAction) do _preDrakeSpellToAction[k] = v end
        Debug("UNIT_SPELLCAST_START : snapshot preventif (" .. (function() local n=0; for _ in pairs(_preDrakeButtonData) do n=n+1 end; return n end)() .. " entrees)")
      end
      return
    end

    ---------------------------------------------------------------------------
    -- UNIT_SPELLCAST_SUCCEEDED : le joueur a lance un sort avec succes.
    -- C'est le signal pour tracker les CD et les charges en combat.
    -- arg2 = castGUID (inutile), arg3 = spellID
    --
    -- DEDUPE : certains sorts fire UNIT_SPELLCAST_SUCCEEDED plusieurs fois
    -- pour un seul cast logique (ex: Stormstrike Chaman Amélioration → 2x le
    -- même spellID en quelques ms + un autre event "(main gauche)" avec un
    -- NOM différent). Sans dedupe on décrémente les charges 2x par clic.
    -- Fenêtre 100ms = tolérance large vs GCD min (~750ms).
    ---------------------------------------------------------------------------
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      local castSpellID = arg3
      if not castSpellID then return end
      -- Dedupe par spellID (secret number → on utilise le nom comme clé propre)
      do
        local rawName = GetSpellName(castSpellID)
        if rawName then
          local now = GetTime()
          local prev = _lastSuccessTime[rawName]
          if prev and (now - prev) < 0.1 then
            Debug("SPELLCAST dedupe: " .. rawName .. " ignoré (<100ms du précédent)")
            return
          end
          _lastSuccessTime[rawName] = now
        end
      end
      -- STRATEGY : GetSpellName retourne TOUJOURS une string propre (clean),
      -- même en combat TWW. On compare les NOMS au lieu des spellIDs
      -- (qui sont des secret numbers impossibles à manipuler en Lua).
      local castName = GetSpellName(castSpellID)
      if not castName then return end
      local anyMatch = false
      for i = 1, MAX_SLOTS do
        local slot = slotFrames[i]
        if slot and slot.currentSpellID then
          local displayName = GetSpellName(slot.currentSpellID)
          if castName == displayName then
            anyMatch = true
            -- Résoudre si c'est un sort à charges.
            -- slot.spellIDs contient des IDs PROPRES (configurés hors combat).
            -- chargeCache utilise aussi des clés propres (construit OOC).
            -- On cherche quel spellID de la config correspond au cast.
            local isChargeSpell, chSid = nil, nil
            if slot.spellIDs then
              for _, sid in ipairs(slot.spellIDs) do
                if chargeCache[sid] then
                  -- Vérifier : le sort affiché est-il ce sid ou son override ?
                  local sidName = GetSpellName(sid)
                  if castName == sidName then
                    isChargeSpell = chargeCache[sid]
                    chSid = sid
                    break
                  end
                  -- Vérifier l'override live (ex: Attaque Mentale → Trait de Vide)
                  if C_Spell and C_Spell.GetOverrideSpell then
                    local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
                    if ok and ov then
                      local ovName = GetSpellName(ov)
                      if castName == ovName then
                        isChargeSpell = chargeCache[sid]
                        chSid = sid
                        break
                      end
                    end
                  end
                end
              end
            end
            Debug("SPELLCAST slot" .. i .. ": cast=" .. castName .. " isCharge=" .. tostring(isChargeSpell) .. " chSid=" .. tostring(chSid))
            if isChargeSpell and chSid then
              -- Enregistrer le timestamp du cast pour le swipe de recharge.
              -- Utilisé par UpdateSlotExtras (hideGCDSwipe) avec chargeRechargeTime
              -- pour savoir si une recharge est en cours (valeurs propres, pas d'API taintée).
              _chargeSwipeStartTime[chSid] = GetTime()
              -- Sort à charges : animer le swipe CD si on vient du max de charges.
              -- Le display des charges est géré par lecture directe dans UpdateSlotExtras
              -- (identique à TestCharges.lua), pas d'estimation ici.
              local maxC = chargeCache[chSid] or 2
              local wasAtMax = false
              if C_Spell and C_Spell.GetSpellCharges then
                local ok, cInfo = pcall(C_Spell.GetSpellCharges, chSid)
                if ok and cInfo then
                  local curPost = tonumber(tostring(cInfo.currentCharges)) or 0
                  wasAtMax = (curPost == maxC - 1)
                end
              end
              Debug("Cast charge: " .. castName .. " wasAtMax=" .. tostring(wasAtMax))
              local cfg = ns.GetCfg("priorityBar") or {}
              if wasAtMax and slot.cooldown and cfg.showCooldownSwipe ~= false then
                local rechargeT = chargeRechargeTime[chSid]
                if rechargeT and rechargeT > 0 then
                  slot.cooldown:Show()
                  slot.cooldown:SetCooldown(GetTime(), rechargeT)
                  slot._swipeSpellName = castName
                  slot._onCooldown = true
                end
              end
            else
              -- Sort normal avec CD : estimer la fin du CD et démarrer le swipe
              -- Chercher baseCD par NOM dans spellCDBase (les clés sont propres)
              local baseCD = nil
              local matchedSid = nil
              local matchedOvID = nil
              if slot.spellIDs then
                for _, sid in ipairs(slot.spellIDs) do
                  if spellCDBase[sid] then
                    local sidName = GetSpellName(sid)
                    if castName == sidName then
                      baseCD = spellCDBase[sid]; matchedSid = sid; break
                    end
                    if C_Spell and C_Spell.GetOverrideSpell then
                      local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
                      if ok and ov then
                        local ovName = GetSpellName(ov)
                        if castName == ovName then
                          baseCD = spellCDBase[sid]; matchedSid = sid; matchedOvID = ov; break
                        end
                      end
                    end
                  end
                end
              end
              if baseCD and baseCD > 1.5 then
                local adjustedCD = baseCD
                if GetHaste then
                  local ok, haste = pcall(GetHaste)
                  if ok and haste and type(haste) == "number" then
                    local okA, adj = pcall(function() return baseCD / (1 + haste / 100) end)
                    if okA and adj then adjustedCD = adj end
                  end
                end
                local now = GetTime()
                -- Stocker UNIQUEMENT pour le sort casté (matchedSid) et son override.
                -- Ne pas écrire pour tous les spellIDs du slot : les autres sorts ont
                -- leurs propres CDs et seraient incorrectement désaturés/non-désaturés.
                if matchedSid then
                  _realCDEndTimes[matchedSid] = now + adjustedCD
                  if matchedOvID then
                    _realCDEndTimes[matchedOvID] = now + adjustedCD
                  end
                end
                local cfg = ns.GetCfg("priorityBar") or {}
                if slot.cooldown and cfg.showCooldownSwipe ~= false then
                  slot.cooldown:Show()
                  slot.cooldown:SetCooldown(now, adjustedCD)
                  slot._swipeSpellName = castName
                  slot._onCooldown = true
                end
                Debug("Cast CD: " .. castName .. " → adjusted=" .. string.format("%.1f", adjustedCD) .. "s")
              end
            end
          end
        end
      end
      if not anyMatch then
        Debug("SPELLCAST NO MATCH: cast=" .. castName)
      end
      return
    end

    ---------------------------------------------------------------------------
    -- SPELL_UPDATE_COOLDOWN : quelque chose a change dans les cooldowns.
    -- Potentiellement un CD reset/wipe. On ne peut pas lire les valeurs,
    -- mais le prochain tick de polling passera GetActionCooldown a SetCooldown.
    -- Si le CD a ete reset, SetCooldown recevra (0,0) → OnCooldownDone fire.
    -- Aucune action directe necessaire ici, le polling s'en charge.
    ---------------------------------------------------------------------------
    if event == "SPELL_UPDATE_COOLDOWN" then
      -- Pas d'action : le polling + OnCooldownDone gerent les resets
      return
    end

    ---------------------------------------------------------------------------
    -- SPELL_UPDATE_CHARGES : les charges ont change pour un sort.
    -- OOC : resync complet via SyncChargesOOC (comportement historique).
    -- [12.0.5] En combat : tentative de live-read ; si l'API expose maintenant
    -- des valeurs clean, on corrige immédiatement toutes les estimations et on
    -- annule les timers pour éviter les double-incréments.
    ---------------------------------------------------------------------------
    if event == "SPELL_UPDATE_CHARGES" then
      _chargesStats.eventFires = _chargesStats.eventFires + 1
      _chargesStats.lastEventTime = GetTime()
      -- [fix] SyncChargesOOC lit maintenant les charges en et hors combat.
      -- Corrige immédiatement toute dérive (procs de reset, CDR, maîtrise, etc.).
      SyncChargesOOC()
      return
    end

    -- UNIT_POWER_BAR_SHOW : la barre Dragonriding (ID 631) vient d'apparaître.
    -- Valider le snapshot préventif pris sur UNIT_SPELLCAST_START, ou en prendre
    -- un nouveau si le snapshot préventif est vide / manquant.
    if event == "UNIT_POWER_BAR_SHOW" then
      if next(_preDrakeButtonData) ~= nil then
        -- Snapshot préventif déjà en place, juste le valider
        _hasDrakeSnapshot = true
        Debug("UNIT_POWER_BAR_SHOW : snapshot preventif valide (" .. (function() local n=0; for _ in pairs(_preDrakeButtonData) do n=n+1 end; return n end)() .. " entrees)")
      else
        -- Pas de snapshot préventif (ACTIONBAR_SLOT_CHANGED n'a pas encore frappé ?)
        -- Prendre un snapshot du cache actuel, même s'il peut déjà être partiellement corrompu
        wipe(_preDrakeButtonData)
        wipe(_preDrakeSpellToAction)
        for k, v in pairs(cachedButtonData)    do _preDrakeButtonData[k]   = { button = v.button, spellID = v.spellID } end
        for k, v in pairs(cachedSpellToAction) do _preDrakeSpellToAction[k] = v end
        _hasDrakeSnapshot = true
        Debug("UNIT_POWER_BAR_SHOW : nouveau snapshot (" .. (function() local n=0; for _ in pairs(_preDrakeButtonData) do n=n+1 end; return n end)() .. " entrees)")
      end
      return
    end

    -- UNIT_POWER_BAR_HIDE : dismount.
    -- Restaurer le snapshot immédiatement, MÊME en combat.
    -- cachedButtonData = frame-refs + nombres normaux, zéro secret number.
    if event == "UNIT_POWER_BAR_HIDE" then
      if _hasDrakeSnapshot then
        wipe(cachedButtonData)
        wipe(cachedSpellToAction)
        for k, v in pairs(_preDrakeButtonData)    do cachedButtonData[k]    = { button = v.button, spellID = v.spellID } end
        for k, v in pairs(_preDrakeSpellToAction) do cachedSpellToAction[k] = v end
        _hasDrakeSnapshot = false
        Debug("UNIT_POWER_BAR_HIDE : cache restauré (" .. (function() local n=0; for _ in pairs(cachedButtonData) do n=n+1 end; return n end)() .. " entrees)")
      end
      if not InCombatLockdown() then
        C_Timer.After(0, RebuildSpellButtonCache)
      end
      return
    end

    -- Combat enter : UpdateVisibility calcule ShouldShow → true → AnimatePB fade-in
    if event == "PLAYER_REGEN_DISABLED" then
      -- Wipe partiel de cdmCDData : supprimer uniquement les entrées onCD=false
      -- (CD déjà expiré → pas de fantôme possible). Garder les onCD=true :
      -- le sort est encore en CD au début du combat, swipe et désaturation doivent
      -- continuer sans coupure. Le CDM remettra onCD=false via Clear() quand il expire.
      local cdmEventData = ns.Auras and ns.Auras.cdmCDData
      if cdmEventData then
        local _toRemove = {}
        for sid, entry in pairs(cdmEventData) do
          if not entry.onCD then _toRemove[#_toRemove + 1] = sid end
        end
        for _, sid in ipairs(_toRemove) do cdmEventData[sid] = nil end
      end
      PriorityBar.UpdateVisibility()
      -- Ne pas alerter si le combat démarre en Skyriding (barre Dragonriding
      -- active, UnitPowerBarID 631) : cachedSpellToButton reflète alors les
      -- "vraies" barres d'avant décollage (RebuildSpellButtonCache les gèle),
      -- mais elles ne sont pas affichées/utilisables tant qu'on est monté →
      -- l'alerte n'a de sens qu'une fois les vraies barres actives au sol.
      if UnitPowerBarID("player") ~= 631 then
        CheckMissingSpellsFromActionBars()
      end
      return
    end

    -- Tous les autres events : jamais traiter en combat
    if InCombatLockdown() then
      Debug("EVENT " .. event .. " SKIPPED (InCombat)")
      return
    end

    -- Fin de combat : UpdateVisibility calcule ShouldShow → false → AnimatePB fade-out
    if event == "PLAYER_REGEN_ENABLED" then
      PriorityBar.UpdateVisibility()  -- le debounce détecte le changement d'état
      -- Synchroniser les CD et charges depuis l'API (hors combat = clean)
      SyncCooldownsOOC()
      SyncChargesOOC()
      -- Reconstruire le cache bouton après chaque combat : garantit un état
      -- propre avant le prochain pull (couvre les upgrades talent qui changent
      -- GetActionInfo sans déclencher ACTIONBAR_SLOT_CHANGED).
      C_Timer.After(0, function()
        if not InCombatLockdown() then
          RebuildSpellButtonCache()
        end
      end)
    end

    RebuildSpellButtonCache()
    RebuildChargeCache()
    RebuildCooldownCache()
    -- Ne pas appeler RebuildLearnedCache ici : les sorts appris ne changent qu'au
    -- changement de spec/login. Le faire ici provoque une race condition avec
    -- ACTIVE_TALENT_GROUP_CHANGED (cache reconstruit avec les anciens spellIDs).
  end)

  -- Rechargement des slots a chaque changement de spec
  local specEventFrame = CreateFrame("Frame")
  specEventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  specEventFrame:SetScript("OnEvent", function()
    if InCombatLockdown() then return end
    C_Timer.After(0.5, function()
      LayoutSlots()
      local newSlots = PriorityBar.GetCurrentSpecSlots()
      -- ConfigureSlots appelle RebuildLearnedCache en interne
      PriorityBar.ConfigureSlots(newSlots)
      RebuildChargeCache()
      -- Wipe complet des CD au changement de spec (les sorts changent)
      wipe(spellCDBase)
      wipe(_realCDEndTimes)
      RebuildCooldownCache()
      RebuildSpellButtonCache()
      CheckMissingSpellsFromActionBars()
      if ns.CallbackRegistry then
        ns.CallbackRegistry:Trigger("PriorityBar.SpecChanged")
      end
    end)
    -- Second passage à 2s : filet de sécurité si IsPlayerSpell n'était pas
    -- encore à jour à 0.5s (changement de build talent lent).
    C_Timer.After(2.0, function()
      if not InCombatLockdown() then
        RebuildLearnedCache()
      end
    end)
  end)

  -- Construction initiale du cache
  C_Timer.After(1, function()
    RebuildSpellButtonCache()
    RebuildChargeCache()
    RebuildCooldownCache()
    RebuildLearnedCache()
    CheckMissingSpellsFromActionBars()
  end)

  StartPolling()

  -- Diagnostic: dump le cache a l'entree en combat (actif si /pbdebug ON)
  local combatDebugFrame = CreateFrame("Frame")
  combatDebugFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  combatDebugFrame:SetScript("OnEvent", function()
    if not debugMode then return end
    local count = 0
    local names = {}
    for bName, data in pairs(cachedButtonData) do
      count = count + 1
      names[#names+1] = bName .. "=" .. data.spellID .. "(" .. (GetSpellName(data.spellID) or "?") .. ")"
    end
    print("|cffff6600[PB-DEBUG] COMBAT START|r cache=" .. count .. " entrees")
    for _, s in ipairs(names) do print("|cffff6600[PB-DEBUG]|r  " .. s) end
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.spellIDs then
        local ids = {}
        for _, sid in ipairs(slot.spellIDs) do
          ids[#ids+1] = sid .. "(" .. (GetSpellName(sid) or "?") .. ")"
        end
        print("|cffff6600[PB-DEBUG]|r slot" .. i .. " cherche: " .. table.concat(ids, ", "))
      end
    end
  end)

  -- /pbdebug : active/desactive les logs
  SLASH_PBDEBUG1 = "/pbdebug"
  SlashCmdList["PBDEBUG"] = function()
    debugMode = not debugMode
    print("|cff00b0ff[PB]|r debug: " .. (debugMode and "|cff00ff00ON|r (logs dans le chat)" or "|cffff0000OFF|r"))
    if debugMode then
      print("|cff00b0ff[PB]|r /pbcache pour voir le cache actuel")
    end
  end

  ---------------------------------------------------------------------------
  -- /pbcharges : dump complet du système de charges
  -- Affiche chargeCache, estimatedCharges, lecture live de l'API, et ce que
  -- chaque slot afficherait. A lancer IN ou HORS combat.
  ---------------------------------------------------------------------------
  SLASH_PBCHARGES1 = "/pbcharges"
  SlashCmdList["PBCHARGES"] = function()
    local P = "|cffff8800[PB-CHG]|r "
    print(P .. "=== DIAGNOSTIC CHARGES (InCombat=" .. tostring(InCombatLockdown()) .. ") ===")

    -- 1) chargeCache
    local nCache = 0; for _ in pairs(chargeCache) do nCache = nCache + 1 end
    print(P .. "chargeCache (" .. nCache .. " sorts):")
    if nCache == 0 then
      print(P .. "  |cffff4444VIDE — RebuildChargeCache n'a pas tourné (OOC seulement)|r")
    end
    for sid, maxC in pairs(chargeCache) do
      print(string.format("%s  [%d] %s  maxC=%s  estimated=%s",
        P, sid, GetSpellName(sid) or "?",
        tostring(maxC),
        tostring(estimatedCharges[sid])))
    end

    -- 2) Lecture API brute pour chaque sort du cache
    print(P .. "Lecture C_Spell.GetSpellCharges (brut, sans CleanInt) :")
    for sid, _ in pairs(chargeCache) do
      if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, sid)
        if ok and info then
          local rawCur = info.currentCharges
          local rawMax = info.maxCharges
          local tnCur  = tonumber(tostring(rawCur))
          local tnMax  = tonumber(tostring(rawMax))
          -- Test CleanInt séparé pour voir s'il échoue
          local ciCur  = CleanInt(rawCur)
          print(string.format(
            "%s  [%d] %s  rawCur=%s  tonumber(tostring)=%s  CleanInt=%s  rawMax=%s  tnMax=%s",
            P, sid, GetSpellName(sid) or "?",
            tostring(rawCur), tostring(tnCur), tostring(ciCur),
            tostring(rawMax), tostring(tnMax)))
        else
          print(P .. "  [" .. sid .. "] pcall FAILED: " .. tostring(info))
        end
      end
    end

    -- 3) TryLiveReadCharges + GetAuthoritativeCharges
    print(P .. "TryLiveReadCharges + GetAuthoritativeCharges :")
    for sid, _ in pairs(chargeCache) do
      local liveCur, liveMax = TryLiveReadCharges(sid)
      local auth = GetAuthoritativeCharges(sid)
      print(string.format("%s  [%d] %s  TryLive=(%s,%s)  GetAuth=%s  estimated_after=%s",
        P, sid, GetSpellName(sid) or "?",
        tostring(liveCur), tostring(liveMax),
        tostring(auth),
        tostring(estimatedCharges[sid])))
    end

    -- 4) Etat de chaque slot
    print(P .. "Slots (currentSpellID / chargeSid / texte affiché) :")
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot then
        local dispID = slot.currentSpellID
        local baseD  = dispID and (overrideToBase[dispID] or dispID)
        local csid   = nil
        if dispID then
          csid = (chargeCache[dispID] and dispID)
              or (chargeCache[baseD] and baseD)
        end
        local authVal = csid and GetAuthoritativeCharges(csid)
        local shown   = slot.chargeText and slot.chargeText:IsShown()
        local txt     = slot.chargeText and slot.chargeText:GetText()
        print(string.format(
          "%s  slot%d: displayed=%s(%s) base=%s chargeSid=%s GetAuth=%s  shown=%s txt=%s",
          P, i,
          tostring(dispID), dispID and (GetSpellName(dispID) or "?") or "nil",
          tostring(baseD),
          tostring(csid),
          tostring(authVal),
          tostring(shown), tostring(txt)))
      end
    end

    print(P .. "=== FIN DIAGNOSTIC ===")
  end

  -- /pbcache : affiche le cache et les slots configures
  SLASH_PBCACHE1 = "/pbcache"
  SlashCmdList["PBCACHE"] = function()
    local count = 0
    print("|cff00b0ff[PB-CACHE]|r InCombat=" .. tostring(InCombatLockdown()) .. " snapshot=" .. tostring(_hasDrakeSnapshot) .. " PowerBarID=" .. tostring(UnitPowerBarID("player")))
    for bName, data in pairs(cachedButtonData) do
      count = count + 1
      print("|cff00b0ff[PB-CACHE]|r " .. bName .. " -> " .. data.spellID .. " (" .. (GetSpellName(data.spellID) or "?") .. ")")
    end
    print("|cff00b0ff[PB-CACHE]|r total: " .. count .. " entrees en cache")
    -- Snapshot
    local snap = 0; for _ in pairs(_preDrakeButtonData) do snap=snap+1 end
    print("|cff00b0ff[PB-CACHE]|r snapshot: " .. snap .. " entrees (_hasDrakeSnapshot=" .. tostring(_hasDrakeSnapshot) .. ")")
    for bName, data in pairs(_preDrakeButtonData) do
      print("|cff00b0ff[PB-CACHE]|r  SNAP: " .. bName .. " -> " .. data.spellID .. " (" .. (GetSpellName(data.spellID) or "?") .. ")")
    end
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.spellIDs then
        local ids = {}
        for _, sid in ipairs(slot.spellIDs) do
          ids[#ids+1] = sid .. "(" .. (GetSpellName(sid) or "?") .. ")"
        end
        print("|cff00b0ff[PB-CACHE]|r slot" .. i .. ": " .. table.concat(ids, ", "))
      end
    end
  end

  -- /pbscan : scanne TOUS les boutons d'action (pas seulement ceux du cache) pour
  -- trouver les glows actifs et les sorts non mappes. A utiliser quand le cache semble
  -- vide ou incorrect (ex: apres un dismount, pour voir quel bouton est en glow).
  SLASH_PBSCAN1 = "/pbscan"
  SlashCmdList["PBSCAN"] = function()
    print("|cffff9900[PB-SCAN]|r Scan complet de TOUS les boutons d'action")
    print("|cffff9900[PB-SCAN]|r InCombat=" .. tostring(InCombatLockdown()) .. " snapshot=" .. tostring(_hasDrakeSnapshot))
    local glowFound  = 0
    local totalFound = 0
    local notInCache = {}
    for _, prefix in ipairs(BUTTON_PREFIXES) do
      for i = 1, 12 do
        local bName = prefix .. i
        local button = _G[bName]
        if button then
          -- Verifier si ce bouton a un glow actif
          local glow = false
          if button.AssistedCombatHighlightFrame then
            local ok, s = pcall(button.AssistedCombatHighlightFrame.IsShown, button.AssistedCombatHighlightFrame)
            if ok and s then glow = true end
          end
          if not glow and button.SpellHighlightTexture then
            local ok, s = pcall(button.SpellHighlightTexture.IsShown, button.SpellHighlightTexture)
            if ok and s then glow = true end
          end
          if not glow and button.SpellHighlightAnim then
            local ok, s = pcall(button.SpellHighlightAnim.IsPlaying, button.SpellHighlightAnim)
            if ok and s then glow = true end
          end
          -- Lire le spellID du bouton
          local spellID = nil
          if button.action and type(button.action) == "number" then
            local ok2, aType, id = pcall(GetActionInfo, button.action)
            if ok2 and aType == "spell" and id and id > 0 then spellID = id end
          end
          if spellID then
            totalFound = totalFound + 1
            -- Est-il dans le cache ?
            local inCache = cachedButtonData[bName] ~= nil
            if not inCache then notInCache[#notInCache+1] = bName .. "=" .. spellID .. "(" .. (GetSpellName(spellID) or "?") .. ")" end
            if glow then
              glowFound = glowFound + 1
              print(string.format("|cffff9900[PB-SCAN]|r |cff00ff00GLOW|r %s spell=%d(%s) inCache=%s",
                bName, spellID, GetSpellName(spellID) or "?", tostring(inCache)))
            end
          end
        end
      end
    end
    print("|cffff9900[PB-SCAN]|r " .. glowFound .. " glow(s) detecTE(s) sur " .. totalFound .. " boutons avec sorts")
    if #notInCache > 0 then
      print("|cffff9900[PB-SCAN]|r |cffff4444Boutons avec sort HORS CACHE:|r " .. table.concat(notInCache, ", "))
    else
      print("|cffff9900[PB-SCAN]|r Tous les boutons avec sorts sont dans le cache. OK")
    end
    -- Comparer avec ce que cherchent les slots
    print("|cffff9900[PB-SCAN]|r Slots configurEs:")
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.spellIDs then
        local parts = {}
        for _, sid in ipairs(slot.spellIDs) do
          local inCache = cachedSpellToAction[sid] ~= nil
          parts[#parts+1] = sid .. "(" .. (GetSpellName(sid) or "?") .. ")" .. (inCache and "|cff00ff00OK|r" or "|cffff4444MANQUANT|r")
        end
        print("|cffff9900[PB-SCAN]|r  slot" .. i .. ": " .. table.concat(parts, ", "))
      end
    end
  end

  -- /pbovr : dump complet des maps override + simulation CollectGlowedSpells + FindHighlightedSpell
  -- A lancer IN ou HORS combat pour voir si les overrides sont bien en place
  SLASH_PBOVR1 = "/pbovr"
  SlashCmdList["PBOVR"] = function()
    local P = "|cffff88ff[PB-OVR]|r "
    print(P .. "=== OVERRIDE MAPS (InCombat=" .. tostring(InCombatLockdown()) .. ") ===")
    -- 1) Dump overrideToBase
    local n1 = 0; for _ in pairs(overrideToBase) do n1 = n1 + 1 end
    print(P .. "overrideToBase (" .. n1 .. " entrees):")
    for ov, base in pairs(overrideToBase) do
      print(string.format("%s  %d(%s) -> base %d(%s)", P, ov, GetSpellName(ov) or "?", base, GetSpellName(base) or "?"))
    end
    -- 2) GetOverrideSpell live pour chaque sort configure
    print(P .. "GetOverrideSpell LIVE par slot:")
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.spellIDs and #slot.spellIDs > 0 then
        for _, sid in ipairs(slot.spellIDs) do
          local liveOv = nil
          if C_Spell and C_Spell.GetOverrideSpell then
            local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
            if ok and ov and ov ~= sid and ov > 0 then liveOv = ov end
          end
          print(string.format("%s  slot%d sid=%d(%s) -> liveOv=%s", P, i, sid, GetSpellName(sid) or "?", liveOv and (liveOv .. "(" .. (GetSpellName(liveOv) or "?") .. ")") or "none"))
        end
      end
    end
    -- 4) Simulation CollectGlowedSpells (avec scan complet)
    print(P .. "CollectGlowedSpells() simulation:")
    local sourceData = (_hasDrakeSnapshot and next(_preDrakeButtonData) ~= nil) and _preDrakeButtonData or cachedButtonData
    local simGlowed = {}
    local scannedSim = {}
    -- Passe 1 : boutons du cache
    for bName, data in pairs(sourceData) do
      scannedSim[bName] = true
      local button = data.button
      if button and ButtonHasGlow(button) then
        local liveID = GetLiveButtonSpellID(button)
        local sid = liveID or data.spellID
        simGlowed[sid] = true
        if liveID and liveID ~= data.spellID then
          simGlowed[data.spellID] = true
        end
        local base = overrideToBase[sid]
        local liveOv = nil
        if C_Spell and C_Spell.GetOverrideSpell then
          local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
          if ok and ov and ov ~= sid and ov > 0 then liveOv = ov end
        end
        print(string.format("%s  GLOW btn=%s sid=%d(%s) cached=%d liveOv=%s",
          P, bName, sid, GetSpellName(sid) or "?", data.spellID,
          liveOv and (liveOv .. "(" .. (GetSpellName(liveOv) or "?") .. ")") or "nil"))
        if base then simGlowed[base] = true end
        if liveOv then simGlowed[liveOv] = true end
      end
    end
    -- Passe 2 : boutons non-cachés
    for _, prefix in ipairs(BUTTON_PREFIXES) do
      for ii = 1, 12 do
        local bName2 = prefix .. ii
        if not scannedSim[bName2] then
          local button2 = _G[bName2]
          if button2 and ButtonHasGlow(button2) then
            local sid2 = GetLiveButtonSpellID(button2)
            if sid2 then
              simGlowed[sid2] = true
              print(string.format("%s  GLOW btn=%s(uncached) sid=%d(%s)", P, bName2, sid2, GetSpellName(sid2) or "?"))
            end
          end
        end
      end
    end
    local ng = 0; for _ in pairs(simGlowed) do ng = ng + 1 end
    if ng == 0 then
      print(P .. "  (aucun glow actif)")
    else
      print(P .. "glowedSpells finaux (" .. ng .. "):")
      for sid in pairs(simGlowed) do
        print(string.format("%s  -> %d (%s)", P, sid, GetSpellName(sid) or "?"))
      end
    end
    -- 5) FindHighlightedSpell par slot
    print(P .. "FindHighlightedSpell par slot:")
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.spellIDs and #slot.spellIDs > 0 then
        local found = FindHighlightedSpell(slot, simGlowed)
        print(string.format("%s  slot%d -> %s", P, i, found and (found .. "(" .. (GetSpellName(found) or "?") .. ")") or "nil"))
      end
    end
  end

  -- /pbglow : inspecte l'etat glow sur chaque bouton (cache + scan complet)
  -- A lancer EN COMBAT quand les glows sont absents pour voir pourquoi
  SLASH_PBGLOW1 = "/pbglow"
  SlashCmdList["PBGLOW"] = function()
    local P = "|cffffff00[PB-GLOW]|r "
    print(P .. "InCombat=" .. tostring(InCombatLockdown()) .. " cache=" .. (function() local n=0; for _ in pairs(cachedButtonData) do n=n+1 end; return n end)() .. " entrees")
    local function DumpButton(bName, button, cachedSpell)
      if not button then
        print(P .. bName .. ": button=NIL")
        return
      end
      local visible = button:IsVisible()
      local hasACHF = button.AssistedCombatHighlightFrame ~= nil
      local achfShown = false
      if hasACHF then
        local ok, shown = pcall(button.AssistedCombatHighlightFrame.IsShown, button.AssistedCombatHighlightFrame)
        achfShown = ok and shown or false
      end
      local hasSHT  = button.SpellHighlightTexture ~= nil
      local shtShown = hasSHT and button.SpellHighlightTexture:IsShown() or false
      local hasSHA  = button.SpellHighlightAnim ~= nil
      local shaPlaying = hasSHA and button.SpellHighlightAnim:IsPlaying() or false
      local liveID = GetLiveButtonSpellID(button)
      local spellStr = cachedSpell and tostring(cachedSpell) or "nil"
      if liveID and liveID ~= cachedSpell then
        spellStr = spellStr .. "→live=" .. liveID .. "(" .. (GetSpellName(liveID) or "?") .. ")"
      end
      print(string.format("%s%s | vis=%s | ACHF=%s(shown=%s) | SHT=%s(shown=%s) | SHA=%s(playing=%s) | spell=%s",
        P, bName,
        tostring(visible),
        tostring(hasACHF), tostring(achfShown),
        tostring(hasSHT),  tostring(shtShown),
        tostring(hasSHA),  tostring(shaPlaying),
        spellStr
      ))
    end
    -- Cached buttons
    local scanned = {}
    for bName, data in pairs(cachedButtonData) do
      scanned[bName] = true
      DumpButton(bName, data.button, data.spellID)
    end
    -- Uncached buttons (form switch may have added spells to empty slots)
    local uncachedCount = 0
    for _, prefix in ipairs(BUTTON_PREFIXES) do
      for i = 1, 12 do
        local bName = prefix .. i
        if not scanned[bName] then
          local button = _G[bName]
          if button then
            local liveID = GetLiveButtonSpellID(button)
            local hasGlow = ButtonHasGlow(button)
            if liveID or hasGlow then
              uncachedCount = uncachedCount + 1
              DumpButton(bName .. " (uncached)", button, nil)
            end
          end
        end
      end
    end
    if uncachedCount > 0 then
      print(P .. uncachedCount .. " boutons non-cachés avec sort/glow détectés")
    end
  end

  -- /pbcharges : diagnostic charges (event-driven)
  SLASH_PBCHARGES1 = "/pbcharges"
  SlashCmdList["PBCHARGES"] = function()
    print("|cff00ffff[PB-CHARGES]|r InCombat=" .. tostring(InCombatLockdown()))
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.currentSpellID then
        local sid = slot.currentSpellID
        local base = overrideToBase[sid] or sid
        local chargeID = chargeCache[sid] and sid or (chargeCache[base] and base) or nil
        if chargeID then
          local maxC    = chargeCache[chargeID]
          local estim   = estimatedCharges[chargeID]
          local recharge = chargeRechargeTime[chargeID]
          local hasTimer = chargeTimers[chargeID] and true or false
          print(string.format("|cff00ffff[PB-CHARGES]|r slot%d %s(%d) estimated=%s/%s recharge=%.1fs timer=%s",
            i, GetSpellName(sid) or "?", sid,
            tostring(estim), tostring(maxC),
            recharge or 0, tostring(hasTimer)))
        end
      end
    end
  end

  ---------------------------------------------------------------------------
  -- /pbcddbg : diagnostic event-driven CD/charges/desat pour chaque slot.
  -- Montre l'etat interne : spellCDBase, _realCDEndTimes, estimatedCharges,
  -- chargeRechargeTime, chargeTimers, et l'etat visuel actuel.
  ---------------------------------------------------------------------------
  SLASH_PBCDDBG1 = "/pbcddbg"
  SlashCmdList["PBCDDBG"] = function()
    local P = "|cffff8800[PB-CDDBG]|r "
    local cfg = ns.GetCfg("priorityBar") or {}
    print(P .. "=== CD/CHARGES/DESAT v3 (event-driven) ===")
    print(P .. "InCombat=" .. tostring(InCombatLockdown())
      .. " desat=" .. tostring(cfg.desaturateOnCooldown)
      .. " charges=" .. tostring(cfg.showCharges))

    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.currentSpellID then
        local sid = slot.currentSpellID
        local base = overrideToBase[sid] or sid
        local actionSlot = FindActionSlotForSpell(slot)
        local isCharge = chargeCache[sid] or chargeCache[base]
        print(P .. "--- slot" .. i .. " " .. (GetSpellName(sid) or "?") .. " (" .. sid .. ") base=" .. base .. " action=" .. tostring(actionSlot))

        -- CD base
        local baseCD = spellCDBase[sid] or spellCDBase[base]
        print(P .. "  baseCD=" .. tostring(baseCD and string.format("%.1fs", baseCD) or "nil"))

        -- CD end time (event-driven)
        local cdEnd = _realCDEndTimes[sid] or _realCDEndTimes[base]
        if cdEnd then
          local rem = cdEnd - GetTime()
          print(P .. "  _realCDEndTimes: end=" .. string.format("%.1f", cdEnd) .. " remaining=" .. string.format("%.1fs", rem) .. (rem > 0 and " (ON CD)" or " (EXPIRED)"))
        else
          print(P .. "  _realCDEndTimes: nil (pas en CD)")
        end

        -- Charges
        if isCharge then
          local chSid = chargeCache[sid] and sid or base
          print(P .. "  charges: estimated=" .. tostring(estimatedCharges[chSid]) .. "/" .. tostring(chargeCache[chSid])
            .. " rechargeTime=" .. tostring(chargeRechargeTime[chSid] and string.format("%.1fs", chargeRechargeTime[chSid]) or "nil")
            .. " timerActive=" .. tostring(chargeTimers[chSid] and true or false))
        end

        -- Visual state
        print(P .. "  visual: desat=" .. tostring(slot.icon:IsDesaturated())
          .. " chargeText=" .. tostring(slot.chargeText and slot.chargeText:IsShown() and slot.chargeText:GetText() or "hidden")
          .. " isHL=" .. tostring(slot._isHighlighted)
          .. " _onCooldown=" .. tostring(slot._onCooldown))
      end
    end
  end

  ---------------------------------------------------------------------------
  -- /pbzdbg : diagnostic Z-order pour le bug "glow caché derrière une icône".
  -- Usage : /pbzdbg           → dump immédiat de tous les frame levels + état glow
  --         /pbzdbg watch     → surveillance 0.3 s — auto-report si anomalie
  --         /pbzdbg watch off → arrête la surveillance
  ---------------------------------------------------------------------------
  local _zdbgWatcher = nil

  local function DumpZOrder(prefix)
    local p = prefix or "|cffff44ff[PB-ZDBG]|r "
    print(p .. "=== Z-ORDER / GLOW HIDE DEBUG === t=" .. string.format("%.1f", GetTime())
          .. " combat=" .. tostring(InCombatLockdown()))

    -- 1) Niveaux de frame + état glow par slot actif
    local anyGlow = false
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot:IsShown() then
        local fl   = slot:GetFrameLevel()
        local ifl  = slot.innerFrame    and slot.innerFrame:GetFrameLevel()    or "?"
        local gcfl = slot.glowContainer and slot.glowContainer:GetFrameLevel() or "?"
        local cdfl = slot.cooldown      and slot.cooldown:GetFrameLevel()      or "?"
        local ovfl = slot._cdOverlay    and slot._cdOverlay:GetFrameLevel()    or "?"
        local gcVis = slot.glowContainer
          and ("|cff" .. (slot.glowContainer:IsVisible() and "00ff00" or "ff4444")
               .. tostring(slot.glowContainer:IsVisible()) .. "|r")
          or "?"

        local glowState
        if slot.isHighlighted then
          anyGlow = true
          if slot._useFlipbook then
            local tex = slot.loopFlipTex
            if tex then
              glowState = string.format("|cff00ff00GLOW(flip)|r shown=%s vis=%s alpha=%.2f playing=%s",
                tostring(tex:IsShown()), tostring(tex:IsVisible()),
                tex:GetAlpha(),
                tostring(slot.loopFlipAG and slot.loopFlipAG:IsPlaying()))
            else
              glowState = "|cff00ff00GLOW|r [loopFlipTex=NIL!]"
            end
          else
            local tex = slot.glow
            if tex then
              glowState = string.format("|cff00ff00GLOW(pulse)|r shown=%s alpha=%.2f playing=%s",
                tostring(tex:IsShown()), tex:GetAlpha(),
                tostring(slot.glowAG and slot.glowAG:IsPlaying()))
            else
              glowState = "|cff00ff00GLOW|r [glow=NIL!]"
            end
          end
          if slot.procStartTex and slot.procStartTex:IsShown() then
            glowState = glowState .. " |cffff6600procStart:visible|r"
          end
        else
          glowState = "none"
        end

        local spellName = slot.currentSpellID
          and string.format("%s(%d)", GetSpellName(slot.currentSpellID) or "??", slot.currentSpellID)
          or "vide"
        print(string.format(p .. "slot%d %-28s fl=%d inner=%s gc=%s(vis=%s) cd=%s ov=%s | %s",
          i, spellName, fl, tostring(ifl), tostring(gcfl), gcVis, tostring(cdfl), tostring(ovfl), glowState))
      end
    end

    -- 2) Détection d'inversions Z-order (glowContainer <= inner d'un autre slot)
    local inversions = {}
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.isHighlighted and slot.glowContainer and slot:IsShown() then
        local gcfl = slot.glowContainer:GetFrameLevel()
        for j = 1, MAX_SLOTS do
          if j ~= i then
            local other = slotFrames[j]
            if other and other.innerFrame and other:IsShown() then
              local oifl = other.innerFrame:GetFrameLevel()
              if gcfl <= oifl then
                local warn = string.format("|cffff0000INVERSION!|r slot%d.glowCont(%d) <= slot%d.inner(%d) — glow caché!",
                  i, gcfl, j, oifl)
                table.insert(inversions, warn)
                print(p .. warn)
              end
            end
          end
        end
        -- glowContainer invisible sans raison ?
        if not slot.glowContainer:IsVisible() then
          local warn = string.format("|cffff0000WARN|r slot%d glowContainer:IsVisible()=false (parent hidden?)", i)
          table.insert(inversions, warn)
          print(p .. warn)
        end
        -- Glow texture invisible malgré isHighlighted=true ?
        local glowTex = slot._useFlipbook and slot.loopFlipTex or slot.glow
        if glowTex and (not glowTex:IsShown() or glowTex:GetAlpha() < 0.05) then
          local warn = string.format("|cffff0000WARN|r slot%d glowTex not visible (shown=%s alpha=%.2f) mais isHighlighted=true",
            i, tostring(glowTex:IsShown()), glowTex:GetAlpha())
          table.insert(inversions, warn)
          print(p .. warn)
        end
      end
    end

    -- 3) Glows Blizzard détectés au tick courant
    local glowed = CollectGlowedSpells()
    local glist = {}
    for sid in pairs(glowed) do
      glist[#glist+1] = string.format("%s(%d)", GetSpellName(sid) or "?", sid)
    end
    print(p .. "Blizzard glows: " .. (#glist > 0 and table.concat(glist, ", ") or "(aucun)"))

    -- 4) Bounds glow textures vs slot icons pour slots en glow
    for i = 1, MAX_SLOTS do
      local slot = slotFrames[i]
      if slot and slot.isHighlighted and slot:IsShown() then
        local glowTex = slot._useFlipbook and slot.loopFlipTex or slot.glow
        if glowTex then
          local gl, gb, gw, gh = glowTex:GetRect()
          local sl2, sb, sw, sh = slot:GetRect()
          if gl then
            print(string.format(p .. "  slot%d glow: x=%.0f y=%.0f %dx%d | slot: x=%.0f y=%.0f %dx%d | dépasse G=%s D=%s H=%s B=%s",
              i, gl, gb, gw or 0, gh or 0, sl2, sb, sw or 0, sh or 0,
              tostring((sl2 or 0) > gl),
              tostring((gl + (gw or 0)) > (sl2 + (sw or 0))),
              tostring((gb + (gh or 0)) > (sb + (sh or 0))),
              tostring(sb > gb)))
          end
        end
      end
    end

    -- Conclusion
    if not anyGlow then
      print(p .. "|cffffff00Aucun slot en glow|r — lance /pbzdbg quand le bug est visible")
    elseif #inversions == 0 then
      print(p .. "|cff00ff00Aucune inversion Z détectée|r —"
        .. " bug probable dans rendering sublayer ou parent chain (voir WARN ci-dessus)")
    end
    print(p .. "=== FIN ===")
    return inversions
  end

  SLASH_PBZDBG1 = "/pbzdbg"
  SlashCmdList["PBZDBG"] = function(msg)
    local arg = msg and strtrim(msg):lower() or ""
    if arg == "watch" then
      if _zdbgWatcher then
        print("|cffff44ff[PB-ZDBG]|r Surveillance déjà active — /pbzdbg watch off pour arrêter")
        return
      end
      local lastAnomalyTime = 0
      _zdbgWatcher = C_Timer.NewTicker(0.3, function()
        for i = 1, MAX_SLOTS do
          local slot = slotFrames[i]
          if slot and slot.isHighlighted and slot.glowContainer and slot:IsShown() then
            local gcfl = slot.glowContainer:GetFrameLevel()
            -- Inversion de frame level ?
            for j = 1, MAX_SLOTS do
              if j ~= i then
                local other = slotFrames[j]
                if other and other.innerFrame and other:IsShown() then
                  if gcfl <= other.innerFrame:GetFrameLevel() then
                    local now = GetTime()
                    if now - lastAnomalyTime > 5 then
                      lastAnomalyTime = now
                      DumpZOrder("|cffff0000[PB-ZDBG AUTO]|r ")
                    end
                    return
                  end
                end
              end
            end
            -- Glow texture invisible malgré isHighlighted ?
            local glowTex = slot._useFlipbook and slot.loopFlipTex or slot.glow
            if glowTex and (not glowTex:IsShown() or glowTex:GetAlpha() < 0.05) then
              local now = GetTime()
              if now - lastAnomalyTime > 5 then
                lastAnomalyTime = now
                DumpZOrder("|cffff0000[PB-ZDBG AUTO]|r ")
              end
              return
            end
          end
        end
      end)
      print("|cffff44ff[PB-ZDBG]|r Surveillance démarrée (check /0.3s). /pbzdbg watch off pour arrêter.")
    elseif arg == "watch off" or arg == "off" then
      if _zdbgWatcher then
        _zdbgWatcher:Cancel()
        _zdbgWatcher = nil
        print("|cffff44ff[PB-ZDBG]|r Surveillance arrêtée.")
      else
        print("|cffff44ff[PB-ZDBG]|r Surveillance n'était pas active.")
      end
    else
      DumpZOrder()
    end
  end
end

function PriorityBar.ApplySettings()
  if InCombatLockdown() then
    -- Reporter l'application apres le combat
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self)
      self:UnregisterAllEvents()
      PriorityBar.ApplySettings()
    end)
    return
  end

  local cfg = ns.GetCfg("priorityBar") or {}
  local size = cfg.iconSize or 34

  for i = 1, MAX_SLOTS do
    local slot = slotFrames[i]
    if slot then
      slot:SetSize(size, size)
      slot.icon:ClearAllPoints()
      slot.icon:SetAllPoints()

      -- Bordure
      if slot.ApplyBorder then slot.ApplyBorder() end

      -- Glow config (type, couleur, taille)
      if slot.ApplyGlowConfig then slot.ApplyGlowConfig() end

      -- Cooldown swipe + texte
      if slot.cooldown then
        local showSwipe = cfg.showCooldownSwipe ~= false
        local showText  = cfg.showCooldownText  ~= false
        if showSwipe or showText then
          slot.cooldown:Show()
          slot.cooldown:SetDrawSwipe(showSwipe)
          if showSwipe then
            slot.cooldown:SetSwipeColor(0, 0, 0, 0.8)
          end
          slot.cooldown:SetHideCountdownNumbers(not showText)
        else
          slot.cooldown:Clear()
          slot.cooldown:Hide()
        end
        -- Taille et couleur du texte du minuteur
        if showText then
          local cdFontSize = cfg.cooldownFontSize or 14
          local cdColor = cfg.cooldownTextColor or { 1, 1, 1, 1 }
          for _, region in pairs({slot.cooldown:GetRegions()}) do
            if region:IsObjectType("FontString") then
              region:SetFont(ns.Media.font, cdFontSize, "OUTLINE")
              region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4] or 1)
            end
          end
        end
      end

      -- Charges
      if slot.chargeText then
        local pos = cfg.chargePosition or "BOTTOMRIGHT"
        local cx  = cfg.chargeOffsetX or 0
        local cy  = cfg.chargeOffsetY or 0
        slot.chargeText:ClearAllPoints()
        slot.chargeText:SetPoint(pos, slot.innerFrame or slot, pos, cx, cy)
        slot.chargeText:SetFont(ns.Media.font, cfg.chargeFontSize or 12, "OUTLINE")
        local cc = cfg.chargeColor or { 1, 1, 1, 1 }
        slot.chargeText:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
        if not cfg.showCharges then slot.chargeText:Hide() end
      end
    end
  end

  LayoutSlots()

  -- Re-configurer les slots selon la spec active
  local currentSlots = PriorityBar.GetCurrentSpecSlots()
  PriorityBar.ConfigureSlots(currentSlots)
  -- Reappliquer le mode de visibilite (peut avoir change dans les settings)
  PriorityBar.UpdateVisibility()
end

function PriorityBar.SetEnabled(enabled)
  if enabled then
    StartPolling()
    pbLastVisState = nil
    PriorityBar.UpdateVisibility()
  else
    StopPolling()
    pbLastVisState = false  -- enregistrer l'état caché (évite un UpdateVisibility→AnimatePB flash)
    if pbFadeTicker then pbFadeTicker:Cancel(); pbFadeTicker = nil end
    SafeHideContainers()
  end
end

function PriorityBar.Reset()
  for i = 1, MAX_SLOTS do
    if slotFrames[i] then
      slotFrames[i].isHighlighted = true
      StopSlotGlow(slotFrames[i])
      slotFrames[i]:SetAlpha(1)
      -- Remettre le premier sort
      if slotFrames[i].spellIDs and #slotFrames[i].spellIDs > 0 then
        local defaultID = slotFrames[i].spellIDs[1]
        if C_Spell and C_Spell.GetOverrideSpell then
          local ok, ov = pcall(C_Spell.GetOverrideSpell, defaultID)
          if ok and ov and ov ~= defaultID and ov > 0 then defaultID = ov end
        end
        local tex = GetSpellIcon(defaultID)
        if tex then
          slotFrames[i].icon:SetTexture(tex)
          slotFrames[i].currentSpellID = defaultID
        end
      end
    end
  end
end

function PriorityBar.ToggleDebug()
  debugMode = not debugMode
  print("|cff00b0ff[PriorityBar]|r Debug " .. (debugMode and "ON" or "OFF"))
  for i = 1, MAX_SLOTS do
    local slot = slotFrames[i]
    if slot then
      local spells = {}
      for _, sid in ipairs(slot.spellIDs or {}) do
        spells[#spells + 1] = GetSpellName(sid) .. "(" .. sid .. ")"
      end
      print("  Slot " .. i .. ": " .. (slot.slotName or "?") ..
            " | Current: " .. (slot.currentSpellID and (GetSpellName(slot.currentSpellID) .. "(" .. slot.currentSpellID .. ")") or "none") ..
            " | HL: " .. tostring(slot.isHighlighted) ..
            " | Spells: " .. table.concat(spells, ", "))
    end
  end
  if debugMode then
    print("  Button cache: " .. (next(cachedButtonData) and "OK" or "EMPTY — /reload hors combat"))
    local count = 0
    for _ in pairs(cachedButtonData) do count = count + 1 end
    print("  Cached buttons: " .. count)
    local glowed = CollectGlowedSpells()
    local list = {}
    for sid in pairs(glowed) do
      list[#list + 1] = GetSpellName(sid) .. "(" .. sid .. ")"
    end
    print("  Glowed: " .. (#list > 0 and table.concat(list, ", ") or "(none)"))
  end
end

-- Test : force la visibilite pendant 8 sec
function PriorityBar.Test()
  if InCombatLockdown() then
    print("|cff00b0ff[PB]|r Test: impossible en combat")
    return
  end
  testMode = true
  StopPolling()
  SafeShowContainers()
  print("|cff00b0ff[PB]|r Test: slots visibles pendant 8 sec")

  C_Timer.After(2, function()
    -- Simuler un highlight sur slot 1
    if slotFrames[1] and slotFrames[1].spellIDs and #slotFrames[1].spellIDs > 0 then
      local fakeGlow = { [slotFrames[1].spellIDs[1]] = true }
      UpdateSlot(slotFrames[1], fakeGlow)
      print("|cff00b0ff[PB]|r Test: highlight simule sur slot 1")
    end
  end)

  C_Timer.After(8, function()
    PriorityBar.Reset()
    testMode = false
    StartPolling()
    lastVisState = nil
    PriorityBar.UpdateVisibility()
    print("|cff00b0ff[PB]|r Test: fin, reprise du polling")
  end)
end

-- Preset Enhancement Shaman
function PriorityBar.LoadEnhancementPreset()
  local slots = {
    { spellIDs = { 60103 },                             name = "A" },  -- Lava Lash
    { spellIDs = { 188196, 188443 },                    name = "B" },  -- Lightning Bolt, Chain Lightning
    { spellIDs = { 17364, 187874, 197214, 1218090 },    name = "Y" },  -- Stormstrike, Crash Lightning, Sundering, Primordial Storm
    { spellIDs = { 444995, 470057 },                    name = "Z" },  -- Surging Totem, Voltaic Blaze
  }
  PriorityBar.ConfigureSlots(slots)
  if ns.DB and ns.DB.priorityBar then
    ns.DB.priorityBar.slots = slots
  end
  print("|cff00b0ff[PB]|r Enhancement preset loaded!")
  lastVisState = nil
  if not InCombatLockdown() then
    PriorityBar.UpdateVisibility()
  end
end

---------------------------------------------------------------------------
-- Drag
---------------------------------------------------------------------------
function PriorityBar.EnableDrag(enable)
  if InCombatLockdown() then return end
  dragEnabled = enable

  local function OnDragStop(container, sideName)
    container:StopMovingOrSizing()
    container._userPlaced = true
    local point, _, _, x, y = container:GetPoint()
    if ns.DB and ns.DB.priorityBar then
      ns.DB.priorityBar[sideName .. "Anchor"] = point
      ns.DB.priorityBar[sideName .. "X"] = x
      ns.DB.priorityBar[sideName .. "Y"] = y
    end
  end

  local function SetupDrag(container, sideName)
    if not container then return end
    if enable then
      container:SetAlpha(1)
      container:EnableMouse(true)
      container:RegisterForDrag("LeftButton")
      container:SetScript("OnDragStart", function(self) self:StartMoving() end)
      container:SetScript("OnDragStop", function(self) OnDragStop(self, sideName) end)
      if not container.dragBg then
        container.dragBg = container:CreateTexture(nil, "BACKGROUND")
        container.dragBg:SetAllPoints()
        container.dragBg:SetColorTexture(0, 0.69, 1, 0.15)
      end
      container.dragBg:Show()
      -- Drag sur les slots enfants aussi
      for i = 1, MAX_SLOTS do
        local slot = slotFrames[i]
        if slot and slot:GetParent() == container then
          slot:RegisterForDrag("LeftButton")
          slot:SetScript("OnDragStart", function() container:StartMoving() end)
          slot:SetScript("OnDragStop", function() OnDragStop(container, sideName) end)
        end
      end
    else
      container:EnableMouse(false)
      container:SetScript("OnDragStart", nil)
      container:SetScript("OnDragStop", nil)
      if container.dragBg then container.dragBg:Hide() end
      for i = 1, MAX_SLOTS do
        local slot = slotFrames[i]
        if slot and slot:GetParent() == container then
          slot:RegisterForDrag()
          slot:SetScript("OnDragStart", nil)
          slot:SetScript("OnDragStop", nil)
        end
      end
    end
  end

  SetupDrag(leftContainer, "left")
  SetupDrag(rightContainer, "right")

  if not enable then
    pbLastVisState = nil
    PriorityBar.UpdateVisibility()
  end
end

function PriorityBar.SetDraggable(on)
  PriorityBar.EnableDrag(on)
end

function PriorityBar.SetPreview(on)
  if InCombatLockdown() then return end
  if on then
    -- Ne pas afficher si le GUI cache explicitement la barre
    if pbHiddenForGui then return end
    -- Forcer l'affichage pour la preview (plus de StateDriver à suspendre)
    SafeShowContainers()
  else
    for i = 1, MAX_SLOTS do
      if slotFrames[i] then
        slotFrames[i].isHighlighted = true
        StopSlotGlow(slotFrames[i])
      end
    end
    pbLastVisState = nil
    PriorityBar.UpdateVisibility()
  end
end

function PriorityBar.ClearDragPositions()
  if leftContainer then leftContainer._userPlaced = false end
  if rightContainer then rightContainer._userPlaced = false end
end

function PriorityBar.ResetPositions()
  if leftContainer then leftContainer._userPlaced = false end
  if rightContainer then rightContainer._userPlaced = false end
  if ns.DB and ns.DB.priorityBar then
    ns.DB.priorityBar.leftAnchor = nil
    ns.DB.priorityBar.leftX = nil
    ns.DB.priorityBar.leftY = nil
    ns.DB.priorityBar.rightAnchor = nil
    ns.DB.priorityBar.rightX = nil
    ns.DB.priorityBar.rightY = nil
  end
  LayoutSlots()
end

---------------------------------------------------------------------------
-- Gestion per-spec des slots
---------------------------------------------------------------------------

local function GetCurrentSpecID_Internal()
  if GetSpecialization then
    local specIndex = GetSpecialization()
    if specIndex and specIndex > 0 then
      local ok, specID = pcall(GetSpecializationInfo, specIndex)
      if ok and specID and specID > 0 then return specID end
    end
  end
  return 0
end

GetCurrentLayoutDef = function()
  local specID = GetCurrentSpecID_Internal()
  local id = ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.layoutBySpec
              and ns.DB.priorityBar.layoutBySpec[specID]
  if id then
    for _, def in ipairs(LAYOUT_DEFS) do
      if def.id == id then return def end
    end
  end
  return LAYOUT_DEFS[1]  -- fallback : 2x2
end

function PriorityBar.GetCurrentSpecID()
  return GetCurrentSpecID_Internal()
end

function PriorityBar.GetCurrentSpecLayout()
  local specID = GetCurrentSpecID_Internal()
  return (ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.layoutBySpec
          and ns.DB.priorityBar.layoutBySpec[specID]) or "2x2"
end

function PriorityBar.SetCurrentSpecLayout(id)
  if InCombatLockdown() then return end
  local specID = GetCurrentSpecID_Internal()
  if not ns.DB then ns.DB = {} end
  if not ns.DB.priorityBar then ns.DB.priorityBar = {} end
  if not ns.DB.priorityBar.layoutBySpec then ns.DB.priorityBar.layoutBySpec = {} end
  ns.DB.priorityBar.layoutBySpec[specID] = id
  LayoutSlots()
  local slots = PriorityBar.GetCurrentSpecSlots()
  PriorityBar.ConfigureSlots(slots)
end

-- Recharge le layout et les slots pour la spec active (ex : changement de spé)
function PriorityBar.RefreshLayout()
  LayoutSlots()
  local slots = PriorityBar.GetCurrentSpecSlots()
  PriorityBar.ConfigureSlots(slots)
end

function PriorityBar.GetCurrentSpecSlots()
  local specID = GetCurrentSpecID_Internal()
  local layoutDef = GetCurrentLayoutDef()
  -- Construire la liste ordonnée des noms pour ce layout
  local allNames = {}
  for _, n in ipairs(layoutDef.leftNames)  do allNames[#allNames + 1] = n end
  for _, n in ipairs(layoutDef.rightNames) do allNames[#allNames + 1] = n end

  -- Obtenir la table brute des slots et migrer l'ancien format tableau → map par nom
  local function LoadSlotMap()
    if not (ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.slotsBySpec) then return nil end
    local raw = ns.DB.priorityBar.slotsBySpec[specID]
    if not raw then return nil end
    -- Migration : ancien format tableau {[1]={name=…,spellIDs=…}, …} → map {["A"]={spellIDs=…}, …}
    if raw[1] ~= nil then
      local newMap = {}
      for _, entry in ipairs(raw) do
        if type(entry) == "table" and entry.name then
          newMap[entry.name] = { spellIDs = entry.spellIDs or {} }
        end
      end
      ns.DB.priorityBar.slotsBySpec[specID] = newMap
      return newMap
    end
    return raw
  end

  local slotMap = LoadSlotMap()
  if slotMap then
    local result = {}
    for i, slotName in ipairs(allNames) do
      local data = slotMap[slotName]
      result[i] = { spellIDs = (data and data.spellIDs) or {}, name = slotName }
    end
    return result, specID
  end
  -- Slots vides avec noms issus du layout
  local empty = {}
  for i, slotName in ipairs(allNames) do
    empty[i] = { spellIDs = {}, name = slotName }
  end
  return empty, specID
end

function PriorityBar.SaveCurrentSpecSlots()
  local specID = GetCurrentSpecID_Internal()
  local layoutDef = GetCurrentLayoutDef()
  local allNames = {}
  for _, n in ipairs(layoutDef.leftNames)  do allNames[#allNames + 1] = n end
  for _, n in ipairs(layoutDef.rightNames) do allNames[#allNames + 1] = n end
  if not ns.DB then ns.DB = {} end
  if not ns.DB.priorityBar then ns.DB.priorityBar = {} end
  if not ns.DB.priorityBar.slotsBySpec then ns.DB.priorityBar.slotsBySpec = {} end
  -- Préserver les données des autres noms de slots (cross-layout persistence)
  local existing = ns.DB.priorityBar.slotsBySpec[specID]
  -- Si encore l'ancien format tableau → vider (la migration se fera au prochain Get)
  if type(existing) ~= "table" or existing[1] ~= nil then existing = {} end
  -- Sauvegarder uniquement les noms du layout actif, sans toucher aux autres
  for i, slotName in ipairs(allNames) do
    local frame = slotFrames[i]
    existing[slotName] = { spellIDs = frame and frame.spellIDs and { unpack(frame.spellIDs) } or {} }
  end
  ns.DB.priorityBar.slotsBySpec[specID] = existing
  -- Retourner un tableau positionnel (compatible avec le code existant)
  local result = {}
  for i, slotName in ipairs(allNames) do
    result[i] = { spellIDs = existing[slotName].spellIDs, name = slotName }
  end
  return result
end

function PriorityBar.SetSlotSpells(slotIndex, newSpellIDs)
  if InCombatLockdown() then return end
  local slot = slotFrames[slotIndex]
  if not slot then return end
  slot.spellIDs = { unpack(newSpellIDs) }
  -- Mettre a jour la macro du SecureActionButton
  local macroLines = {}
  for _, sid in ipairs(newSpellIDs) do
    local name = GetSpellName(sid)
    if name and name ~= ("Spell#" .. tostring(sid)) then
      macroLines[#macroLines + 1] = "/cast " .. name
    end
  end
  if #macroLines > 0 then
    slot:SetAttribute("type", "macro")
    slot:SetAttribute("macrotext", table.concat(macroLines, "\n"))
  else
    slot:SetAttribute("type", nil)
    slot:SetAttribute("macrotext", nil)
  end
  -- Mettre a jour l'icone et la visibilite du slot
  if #newSpellIDs > 0 then
    local defaultID = newSpellIDs[1]
    if C_Spell and C_Spell.GetOverrideSpell then
      local ok, ov = pcall(C_Spell.GetOverrideSpell, defaultID)
      if ok and ov and ov ~= defaultID and ov > 0 then defaultID = ov end
    end
    local tex = GetSpellIcon(defaultID)
    if tex then
      slot.icon:SetTexture(tex)
      slot.currentSpellID = defaultID
    end
    slot._hidden = false
    slot:Show()
  else
    slot.icon:SetTexture(nil)
    ClearSlotCDMSubscription(slot)
    slot.currentSpellID = nil
    slot._hidden = true
    slot:Hide()
  end
  -- Forcer la mise à jour de visibilité des conteneurs (utile en mode "always")
  pbLastVisState = nil
  PriorityBar.UpdateVisibility()
  RebuildChargeCache()
  RebuildLearnedCache()
  PriorityBar.SaveCurrentSpecSlots()
end

---------------------------------------------------------------------------
-- Detection de la surbrillance d'aide (Spell Activation Overlay)
---------------------------------------------------------------------------

-- Retourne la liste des sorts de la spec active (depuis le spellbook)
-- Filtre : uniquement les sorts avec surbrillance d'aide (Spell Activation Overlay)
function PriorityBar.GetSpecSpells()
  local spells = {}
  local seen   = {}

  -- API TWW (C_SpellBook)
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local ok1, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if ok1 and numLines then
      for lineIdx = 1, numLines do
        local ok2, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, lineIdx)
        if ok2 and lineInfo and lineInfo.numSpellBookItems then
          -- Ignorer les tabs d'autres specs (off-spec)
          if not lineInfo.offSpecID or lineInfo.offSpecID == 0 then
            local startSlot = lineInfo.itemIndexOffset + 1
            local endSlot   = lineInfo.itemIndexOffset + lineInfo.numSpellBookItems
            for slot = startSlot, endSlot do
              local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or "spell"
              local ok3, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
              if ok3 and info and info.spellID and info.spellID > 0 and not seen[info.spellID] then
                if not info.isPassive then
                  seen[info.spellID] = true
                  local name = info.name
                  local icon = info.iconID
                  if not name and C_Spell and C_Spell.GetSpellName then
                    local ok4, n = pcall(C_Spell.GetSpellName, info.spellID)
                    if ok4 then name = n end
                  end
                  if name then
                    spells[#spells + 1] = { id = info.spellID, name = name, icon = icon }
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- Fallback ancienne API (pre-DF)
  if #spells == 0 then
    local ok1, numTabs = pcall(GetNumSpellTabs)
    if ok1 and numTabs then
      for t = 1, numTabs do
        local ok2, _, _, offset, numInTab, _, offspecID = pcall(GetSpellTabInfo, t)
        if ok2 and (not offspecID or offspecID == 0) then
          for i = offset + 1, offset + (numInTab or 0) do
            local ok3, spellType, id = pcall(GetSpellBookItemInfo, i, "spell")
            if ok3 and spellType == "SPELL" and id and id > 0 and not seen[id] then
              seen[id] = true
              local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
              local icon = GetSpellTexture and GetSpellTexture(id)
              if name then
                spells[#spells + 1] = { id = id, name = name, icon = icon }
              end
            end
          end
        end
      end
    end
  end

  -- Sorts supplémentaires par spec (absents du grimoire Blizzard mais présents en rotation)
  -- Chaque entrée : { id, fallbackName, fallbackIcon } — garantit l'affichage même si l'API échoue
  local EXTRA_SPEC_SPELLS = {
    [265] = {
      { id = 30146, fallbackName = "Invocation de gangregarde", fallbackIcon = 136216 },
    },
  }
  -- Résolution du specID courant : priorité ns._specID, fallback API directe
  local currentSpecID = ns._specID
  if not currentSpecID then
    local specIdx = GetSpecialization and GetSpecialization()
    if specIdx then
      local ok, sid2 = pcall(GetSpecializationInfo, specIdx)
      if ok and sid2 then currentSpecID = sid2 end
    end
  end
  if currentSpecID and EXTRA_SPEC_SPELLS[currentSpecID] then
    for _, extra in ipairs(EXTRA_SPEC_SPELLS[currentSpecID]) do
      local sid = extra.id
      if not seen[sid] then
        seen[sid] = true
        local name, icon = extra.fallbackName, extra.fallbackIcon
        -- Tenter de récupérer nom/icône depuis l'API (plus à jour que le fallback)
        if C_Spell and C_Spell.GetSpellInfo then
          local ok, info = pcall(C_Spell.GetSpellInfo, sid)
          if ok and info and info.name then name = info.name; icon = info.iconID end
        end
        if not name or not icon then
          local ok, n, _, ic = pcall(GetSpellInfo, sid)
          if ok then
            if n then name = n end
            if ic then icon = ic end
          end
        end
        spells[#spells + 1] = { id = sid, name = name or ("Spell " .. sid), icon = icon }
      end
    end
  end

  table.sort(spells, function(a, b) return a.name < b.name end)
  return spells
end

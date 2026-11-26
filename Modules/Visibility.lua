-- Modules/Visibility.lua : reglages de transparence d'elements tiers (zone de buffs d'ElvUI
-- ou d'EllesmereUI) via SetAlpha, non bloque par le lockdown combat.
local addonName, ns = ...

local Visibility = {}
ns.Modules.Visibility = Visibility

-- Zone de buffs de l'UI hote : ajustée via noms de frame connus, pas de réglage d'opacité
-- natif hors combat. Survol détecté via OnEnter/OnLeave (GetRect/MouseIsOver échouent) ;
-- délai de grâce pour éviter le clignotement.
-- ElvUI et EllesmereUI ne tournent jamais ensemble : la boucle n'en trouvera qu'un.
-- EllesmereUI dimensionne son conteneur exactement sur la grille d'icones, donc activer la
-- souris dessus ne cree pas de zone morte a cote des buffs.
local BUFFS_FRAME_CANDIDATES = {
  "ElvuiPlayerBuffs", "ElvUIPlayerBuffs",     -- ElvUI
  "EllesmereUIPlayerAuraBars_Buffs",          -- EllesmereUI (cf. EllesmereUIUnitFrames_PlayerAuraBars.lua)
}

-- Vitesse de transition (ease exponentiel, comme StatusBarInterpolation.ExponentialEaseOut) : plus haut = plus rapide.
local FADE_SPEED    = 8
local TICK_INTERVAL = 0.02
local HOVER_GRACE   = 0.15  -- delai avant de considerer le survol termine

local frameStates = {}  -- [frame] = { alpha = <alpha courant interpole> }
local hoverUntil  = {}  -- [frame] = timestamp GetTime() jusqu'auquel considere survole (math.huge = en cours)
local hookedHover = {}  -- [frame] = true une fois OnEnter/OnLeave attaches

-- Table reutilisee : cette fonction est appelee 50 fois par seconde par le ticker, une
-- table neuve a chaque passage alimentait le ramasse-miettes en continu pour rien.
local _framesBuf = {}
local function GetBuffsFrames()
  local frames = wipe(_framesBuf)
  for _, name in ipairs(BUFFS_FRAME_CANDIDATES) do
    local f = _G[name]
    if f then frames[#frames + 1] = f end
  end
  return frames
end

local function TargetAlpha(cfg, isHovered)
  if isHovered and cfg.elvuiBuffsHoverReveal ~= false then return 1 end
  if InCombatLockdown() then return cfg.elvuiBuffsCombatAlpha or 1 end
  return cfg.elvuiBuffsOocAlpha or 0.2
end

local function EnsureHoverTracking(f)
  if hookedHover[f] then return end
  hookedHover[f] = true

  pcall(f.EnableMouse, f, true)

  f:HookScript("OnEnter", function()
    hoverUntil[f] = math.huge
  end)
  f:HookScript("OnLeave", function()
    hoverUntil[f] = GetTime() + HOVER_GRACE
  end)
end

local function IsFrameHovered(f)
  local until_ = hoverUntil[f]
  if not until_ then return false end
  return until_ == math.huge or GetTime() < until_
end

local ticker = CreateFrame("Frame")
local elapsedAcc = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  local cfg = ns.GetCfg("visibility")
  if not cfg or cfg.elvuiBuffsEnabled == false then return end
  elapsedAcc = elapsedAcc + elapsed
  if elapsedAcc < TICK_INTERVAL then return end
  local dt = elapsedAcc
  elapsedAcc = 0

  for _, f in ipairs(GetBuffsFrames()) do
    EnsureHoverTracking(f)

    local st = frameStates[f]
    if not st then
      st = { alpha = f:GetAlpha() or 1 }
      frameStates[f] = st
    end

    -- L'UI hote garde la main sur ses propres masquages : EllesmereUI pose alpha 0 sur sa
    -- zone de buffs quand il la supprime (vehicule, suppression prise en combat, cf.
    -- SetParentShownSafe dans EllesmereUIUnitFrames_PlayerAuraBars.lua). Une frame tombee a
    -- zero sans que ce soit nous est donc a lui : on arrete d'ecrire, sinon le ticker
    -- ferait reapparaitre des buffs qu'il vient d'eteindre. On reprend la main des qu'il
    -- la remonte lui-meme.
    -- Ecart minimal exige avec notre derniere ecriture : GetAlpha arrondit (0.0018 relu 0), et
    -- un fondu vers une opacite reglee a 0 etait pris pour un masquage de l'hote (survol et
    -- changements d'opacite ignores jusqu'au prochain toggle).
    local okA, cur = pcall(f.GetAlpha, f)
    cur = (okA and type(cur) == "number" and not (issecretvalue and issecretvalue(cur))) and cur or nil
    if cur then
      if cur <= 0.001 and (st.written or 1) > 0.02 then
        st.hostOff = true
      elseif st.hostOff and cur > 0.001 then
        st.hostOff = false
      end
    end

    if st.hostOff then
      st.alpha = 0
    else
      local target = TargetAlpha(cfg, IsFrameHovered(f))
      if math.abs(st.alpha - target) > 0.002 then
        local ease = 1 - math.exp(-FADE_SPEED * dt)
        st.alpha = st.alpha + (target - st.alpha) * ease
      else
        st.alpha = target
      end
      pcall(f.SetAlpha, f, st.alpha)
      st.written = st.alpha
    end
  end
end)

-- ═══ Cadres de groupe et de raid ═══════════════════════════════════════════════════════════════════════
-- Attenues hors combat a groupFramesOocAlpha, opacite d'origine en combat et (option) au survol d'un membre.
-- Conteneurs de premier niveau : ElvUI (ElvUF_Party, ElvUF_Raid1..3, ElvUF_Raidpet), EllesmereUI (conteneurs sans
-- nom, retrouves par le parent de leurs en-tetes ; ses previews d'options y ecrivent aussi l'opacite) et Blizzard.
-- Une ecriture de l'hote depuis notre dernier passage devient l'opacite d'origine (0 = masque par lui, rendu).
-- Survol : GetMouseFoci + remontee des parents (les boutons de membre prennent la souris, pas les conteneurs).
local GROUP_FRAME_NAMES = {
  "ElvUF_Party", "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3", "ElvUF_Raidpet",
  "ERFPetHeader",
  "CompactPartyFrame", "CompactRaidFrameContainer", "PartyFrame",
}
local GROUP_PARENT_OF = { "ERFPartyHeader", "ERFFlatHeader", "ERFGroupHeader1" }  -- EllesmereUI : parent = conteneur

local groupStates = {}   -- [frame] = { alpha, host, written, hostOff }
local groupHoverUntil = 0
local _groupBuf, _groupSeen = {}, {}

local function GetGroupFrames()
  local frames, seen = wipe(_groupBuf), wipe(_groupSeen)
  local function add(f)
    if f and not seen[f] and f.SetAlpha then
      seen[f] = true
      frames[#frames + 1] = f
    end
  end
  for _, name in ipairs(GROUP_FRAME_NAMES) do add(_G[name]) end
  for _, name in ipairs(GROUP_PARENT_OF) do
    local h = _G[name]
    local p = h and h.GetParent and h:GetParent()
    if p and p ~= UIParent then add(p) end
  end
  return frames
end

local function GroupFramesHovered(frames)
  local foci
  if GetMouseFoci then
    local ok, r = pcall(GetMouseFoci)
    foci = ok and r
  elseif GetMouseFocus then
    local ok, r = pcall(GetMouseFocus)
    foci = ok and r and { r }
  end
  if not foci then return false end
  for _, focus in ipairs(foci) do
    local f, depth = focus, 0
    while f and depth < 12 do
      if _groupSeen[f] then return true end
      local ok, p = pcall(f.GetParent, f)
      f = ok and p or nil
      depth = depth + 1
    end
  end
  return false
end

local function GroupRelease(f)
  local st = groupStates[f]
  if not st then return end
  if not st.hostOff then pcall(f.SetAlpha, f, st.host or 1) end
  groupStates[f] = nil
end

local groupTicker = CreateFrame("Frame")
local groupAcc = 0
groupTicker:SetScript("OnUpdate", function(_, elapsed)
  local cfg = ns.GetCfg("visibility")
  if not (cfg and cfg.groupFramesEnabled) then return end
  groupAcc = groupAcc + elapsed
  if groupAcc < TICK_INTERVAL then return end
  local dt = groupAcc
  groupAcc = 0

  local frames = GetGroupFrames()
  local full = InCombatLockdown() or UnitAffectingCombat("player")
  if not full and cfg.groupFramesHoverReveal ~= false then
    local now = GetTime()
    if GroupFramesHovered(frames) then groupHoverUntil = now + HOVER_GRACE end
    full = now < groupHoverUntil
  end
  local low = cfg.groupFramesOocAlpha or 0.3

  for _, f in ipairs(frames) do
    local st = groupStates[f]
    local okA, cur = pcall(f.GetAlpha, f)
    cur = (okA and type(cur) == "number" and not (issecretvalue and issecretvalue(cur))) and cur or nil
    if not st then
      st = { alpha = cur or 1, host = cur or 1 }
      if st.host <= 0.001 then st.hostOff = true end
      groupStates[f] = st
    end
    -- Ecriture de l'hote depuis notre dernier passage (ecart > arrondi de GetAlpha)
    if cur then
      if st.hostOff then
        if cur > 0.001 then st.hostOff = false; st.host = cur; st.alpha = cur end
      elseif st.written and math.abs(cur - st.written) > 0.01 then
        if cur <= 0.001 then st.hostOff = true else st.host = cur; st.alpha = cur end
      end
    end
    if not st.hostOff then
      local target = full and st.host or math.min(st.host, low)
      if math.abs(st.alpha - target) > 0.002 then
        st.alpha = st.alpha + (target - st.alpha) * (1 - math.exp(-FADE_SPEED * dt))
      else
        st.alpha = target
      end
      pcall(f.SetAlpha, f, st.alpha)
      st.written = st.alpha
    end
  end
end)

-- Rien à initialiser (le ticker relit ns.GetCfg() à chaque frame) ; si désactivé, on remet alpha=1.
function Visibility.ApplySettings()
  local cfg = ns.GetCfg("visibility")
  if cfg and cfg.elvuiBuffsEnabled == false then
    for _, f in ipairs(GetBuffsFrames()) do
      pcall(f.SetAlpha, f, 1)
      frameStates[f] = nil
    end
  end
  if not (cfg and cfg.groupFramesEnabled) then
    for f in pairs(groupStates) do GroupRelease(f) end
  end
end

-- Diagnostic : /aishdebug buffs (tostring() fonctionne meme sur une valeur secrete).
function Visibility.Debug()
  local P = function(s) print("|cff00ccff[Buffs]|r " .. s) end

  local cfg = ns.GetCfg("visibility")
  if not cfg then
    P("|cffff4444ns.GetCfg('visibility') renvoie nil|r")
    return
  end
  P(string.format("cfg: enabled=%s hoverReveal=%s oocAlpha=%s combatAlpha=%s inCombat=%s",
    tostring(cfg.elvuiBuffsEnabled), tostring(cfg.elvuiBuffsHoverReveal),
    tostring(cfg.elvuiBuffsOocAlpha), tostring(cfg.elvuiBuffsCombatAlpha),
    tostring(InCombatLockdown())))

  local frames = GetBuffsFrames()
  if #frames == 0 then
    P("|cffff4444Aucun frame trouve parmi les candidats: " .. table.concat(BUFFS_FRAME_CANDIDATES, ", ") .. "|r")
    return
  end

  for _, f in ipairs(frames) do
    EnsureHoverTracking(f)

    P(string.format("Frame %s : shown=%s alpha=%s mouseEnabled=%s",
      tostring(f:GetName()), tostring(f:IsShown()), tostring(f:GetAlpha()), tostring(f.IsMouseEnabled and f:IsMouseEnabled())))

    P("  hoverUntil = " .. tostring(hoverUntil[f]) .. "   IsFrameHovered = " .. tostring(IsFrameHovered(f)))

    local st = frameStates[f]
    P("  alpha interpole courant = " .. tostring(st and st.alpha)
      .. "   dernier ecrit = " .. tostring(st and st.written)
      .. "   rendu a l'hote = " .. tostring(st and st.hostOff or false))
  end

  P("Passe la souris sur la zone de buffs puis relance /aishdebug buffs pour voir si hoverUntil bouge.")
end

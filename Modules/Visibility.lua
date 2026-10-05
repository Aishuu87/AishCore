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
    local okA, cur = pcall(f.GetAlpha, f)
    cur = okA and cur or nil
    if cur then
      if cur <= 0.001 and (st.written or 1) > 0.001 then
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

-- Rien à initialiser (le ticker relit ns.GetCfg() à chaque frame) ; si désactivé, on remet alpha=1.
function Visibility.ApplySettings()
  local cfg = ns.GetCfg("visibility")
  if cfg and cfg.elvuiBuffsEnabled == false then
    for _, f in ipairs(GetBuffsFrames()) do
      pcall(f.SetAlpha, f, 1)
      frameStates[f] = nil
    end
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

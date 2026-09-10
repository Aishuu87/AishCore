-- Modules/Visibility.lua : reglages de transparence d'elements tiers (ElvUI) via SetAlpha, non bloque par le lockdown combat.
local addonName, ns = ...

local Visibility = {}
ns.Modules.Visibility = Visibility

-- Zone de buffs ElvUI : ajustée via noms de frame connus, pas de réglage d'opacité natif hors combat.
-- Survol détecté via OnEnter/OnLeave (GetRect/MouseIsOver échouent) ; délai de grâce pour éviter le clignotement.
local ELVUI_BUFFS_FRAME_CANDIDATES = { "ElvuiPlayerBuffs", "ElvUIPlayerBuffs" }

-- Vitesse de transition (ease exponentiel, comme StatusBarInterpolation.ExponentialEaseOut) : plus haut = plus rapide.
local FADE_SPEED    = 8
local TICK_INTERVAL = 0.02
local HOVER_GRACE   = 0.15  -- delai avant de considerer le survol termine

local frameStates = {}  -- [frame] = { alpha = <alpha courant interpole> }
local hoverUntil  = {}  -- [frame] = timestamp GetTime() jusqu'auquel considere survole (math.huge = en cours)
local hookedHover = {}  -- [frame] = true une fois OnEnter/OnLeave attaches

local function GetElvUIBuffsFrames()
  local frames = {}
  for _, name in ipairs(ELVUI_BUFFS_FRAME_CANDIDATES) do
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

  for _, f in ipairs(GetElvUIBuffsFrames()) do
    EnsureHoverTracking(f)

    local st = frameStates[f]
    if not st then
      st = { alpha = f:GetAlpha() or 1 }
      frameStates[f] = st
    end
    local target = TargetAlpha(cfg, IsFrameHovered(f))
    if math.abs(st.alpha - target) > 0.002 then
      local ease = 1 - math.exp(-FADE_SPEED * dt)
      st.alpha = st.alpha + (target - st.alpha) * ease
    else
      st.alpha = target
    end
    pcall(f.SetAlpha, f, st.alpha)
  end
end)

-- Rien à initialiser (le ticker relit ns.GetCfg() à chaque frame) ; si désactivé, on remet alpha=1.
function Visibility.ApplySettings()
  local cfg = ns.GetCfg("visibility")
  if cfg and cfg.elvuiBuffsEnabled == false then
    for _, f in ipairs(GetElvUIBuffsFrames()) do
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

  local frames = GetElvUIBuffsFrames()
  if #frames == 0 then
    P("|cffff4444Aucun frame trouve parmi les candidats: " .. table.concat(ELVUI_BUFFS_FRAME_CANDIDATES, ", ") .. "|r")
    return
  end

  for _, f in ipairs(frames) do
    EnsureHoverTracking(f)

    P(string.format("Frame %s : shown=%s alpha=%s mouseEnabled=%s",
      tostring(f:GetName()), tostring(f:IsShown()), tostring(f:GetAlpha()), tostring(f.IsMouseEnabled and f:IsMouseEnabled())))

    P("  hoverUntil = " .. tostring(hoverUntil[f]) .. "   IsFrameHovered = " .. tostring(IsFrameHovered(f)))

    local st = frameStates[f]
    P("  alpha interpole courant = " .. tostring(st and st.alpha))
  end

  P("Passe la souris sur la zone de buffs puis relance /aishdebug buffs pour voir si hoverUntil bouge.")
end

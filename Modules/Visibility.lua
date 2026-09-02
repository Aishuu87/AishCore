-- Modules/Visibility.lua : reglages de transparence pour des elements tiers
-- (ElvUI...) que l'addon ne cree pas lui-meme mais peut ajuster via SetAlpha
-- (jamais bloque par le lockdown combat, contrairement a Show/Hide).
local addonName, ns = ...

local Visibility = {}
ns.Modules.Visibility = Visibility

------------------------------------------------------------------------
-- Zone de buffs ElvUI : ElvUI ne propose pas de reglage d'opacite hors
-- combat nativement. On essaie les noms de frame connus ; silencieux si
-- ElvUI n'est pas installe ou si son nom de frame differe (meme approche
-- defensive que ApplyElvUITargetAlpha dans TopTargetBar.lua).
--
-- Detection du survol -- HISTORIQUE (pour ne pas retenter les memes pistes) :
-- 1) MouseIsOver(frame)/IsMouseOver() -> secret boolean, plante (patch 12.0).
-- 2) ns.IsFrameMouseOver(f), sondage geometrique via GetRect/GetCursorPosition
--    -> ne plante pas mais ne detecte plus jamais rien : le conteneur ElvUI
--    (CreateFrame('AuraContainer', ..., 'DisableUntrustedLayoutScriptsTemplate'))
--    a sa geometrie TOUJOURS secrete (confirme via /aishdebug buffs :
--    issecretvalue() = true sur les 4 valeurs de f:GetRect(), meme hors combat).
-- 3) Frame a nous ancre sur le conteneur via SetAllPoints(f), puis sonde de
--    CE frame -> toujours rien : confirme via /aishdebug buffs que
--    catcher:GetRect() renvoie les memes valeurs (secretes par propagation).
--    Le statut "secret" suit le graphe d'ancrage, pas seulement le widget
--    d'origine -- impossible d'obtenir une geometrie lisible pour quoi que
--    ce soit qui derive, meme indirectement, de ce conteneur.
-- 4) (actuel) Evenements natifs OnEnter/OnLeave. Le moteur declenche ces
--    scripts sans jamais exposer de valeur secrete a Lua (on ne LIT rien,
--    on reagit juste a un evenement) -- aucun rapport avec le mecanisme de
--    Secret Values. On force EnableMouse(true) sur le conteneur (l'etat
--    mouse-enabled n'est pas protege par le combat lockdown) pour etre sûr
--    qu'il recoive lui-meme OnEnter/OnLeave, meme si visuellement les icones
--    (ses enfants) sont les elements normalement survoles pour le tooltip.
--    Un delai de grace apres OnLeave absorbe le "saut de focus" entre le
--    conteneur, une icone et le tooltip natif d'ElvUI qui s'affiche par-
--    dessus au survol (cause du clignotement observe avec un OnLeave direct
--    sans delai).
------------------------------------------------------------------------
local ELVUI_BUFFS_FRAME_CANDIDATES = { "ElvuiPlayerBuffs", "ElvUIPlayerBuffs" }

-- Vitesse de la transition (ease exponentiel, meme principe que
-- StatusBarInterpolation.ExponentialEaseOut) : plus haut = plus rapide.
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

-- Rien a initialiser explicitement : le ticker OnUpdate lit ns.GetCfg("visibility")
-- a chaque frame et s'adapte immediatement (activation/desactivation, sliders
-- modifies en live). Si la fonctionnalite est desactivee, on remet les frames
-- connus a alpha=1 (comportement natif ElvUI) une bonne fois.
function Visibility.ApplySettings()
  local cfg = ns.GetCfg("visibility")
  if cfg and cfg.elvuiBuffsEnabled == false then
    for _, f in ipairs(GetElvUIBuffsFrames()) do
      pcall(f.SetAlpha, f, 1)
      frameStates[f] = nil
    end
  end
end

------------------------------------------------------------------------
-- Diagnostic : /aishdebug buffs. On ne devine plus -- on affiche les
-- valeurs reelles (tostring() marche meme sur une valeur secrete, cf.
-- DumpPBCharges dans Debug.lua) pour voir precisement ou ca coince.
------------------------------------------------------------------------
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

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
  if Visibility.ApplyEuiBars then Visibility.ApplyEuiBars() end
end

-- ═══ Barres d'action EllesmereUI (1, 2, 3) ═══════════════════════════════════════════════════════
-- Attenuees a cfg.euiBarsAlpha ; opacite d'origine (celle posee par EllesmereUI, son reglage d'opacite de barre) en
-- monture, en combat, avec une cible, au survol d'une des barres, grimoire ouvert ou blesse (meme detection que le
-- cercle de vie hors combat). SetAlpha n'est pas bloque en combat. Une barre qu'EllesmereUI met lui-meme a 0
-- (visibilite "jamais", vehicule...) lui est rendue, comme la zone de buffs plus haut.
local EUI_BARS = { "EABBar_MainBar", "EABBar_Bar2", "EABBar_Bar3", "EABPagingFrame" }
-- Cle de la barre dans les reglages d'EllesmereUI (fleches de pagination : celles de la barre 1)
local EUI_BAR_KEY = { EABBar_MainBar = "MainBar", EABBar_Bar2 = "Bar2", EABBar_Bar3 = "Bar3", EABPagingFrame = "MainBar" }
local euiStates = {}   -- [frame] = { alpha, host, written, hostOff }

-- Reglages de la barre dans le profil actif d'EllesmereUI
local function EuiBarSettings(barKey)
  local db = _G.EllesmereUIDB
  local prof = db and db.profiles and db.activeProfile and db.profiles[db.activeProfile]
  local bars = prof and prof.addons and prof.addons.EllesmereUIActionBars and prof.addons.EllesmereUIActionBars.bars
  return bars and bars[barKey]
end

-- Barre reglee sur "Toujours", sans survol : seule celle-la est attenuee (une barre en survol, en combat seulement, etc.
-- reste entierement a EllesmereUI)
local function EuiBarAlways(barKey)
  local s = EuiBarSettings(barKey)
  if not s then return false end
  return (s.barVisibility or "always") == "always" and not s.mouseoverEnabled
end

-- Barre rendue a EllesmereUI. Integration coupee : opacite d'origine. Barre passee dans un autre mode (changement de
-- profil "Show Bars" -> "Hide Bars"...) : en mode survol, EllesmereUI la veut a 0 hors survol mais ne la remet a 0 qu'a la
-- sortie de la souris -> posee a 0 tout de suite ; dans les autres modes, rien n'est ecrit (EllesmereUI gere).
local function EuiRelease(f, barKey)
  local st = euiStates[f]
  if not st then return end
  if not st.hostOff then
    local s = barKey and EuiBarSettings(barKey)
    if not barKey then
      pcall(f.SetAlpha, f, st.host or 1)
    elseif s and s.mouseoverEnabled then
      pcall(f.SetAlpha, f, 0)
    end
  end
  euiStates[f] = nil
end

local function EuiShowFull()
  if IsMounted and IsMounted() then return true end
  if InCombatLockdown() or UnitAffectingCombat("player") then return true end
  if UnitExists("target") then return true end
  if (PlayerSpellsFrame and PlayerSpellsFrame:IsShown()) or (SpellBookFrame and SpellBookFrame:IsShown()) then return true end
  local HC = ns.Modules.HealthCircle
  if HC and HC.IsPlayerInjured then
    local ok, injured = pcall(HC.IsPlayerInjured)
    if ok and injured == true then return true end
  end
  for i = 1, 3 do
    local f = _G[EUI_BARS[i]]
    if f and f:IsVisible() and EuiBarAlways(EUI_BAR_KEY[EUI_BARS[i]]) then
      local ok, over = pcall(f.IsMouseOver, f)
      if ok and over == true then return true end
    end
  end
  return false
end

local euiTicker = CreateFrame("Frame")
local euiAcc = 0
euiTicker:SetScript("OnUpdate", function(_, elapsed)
  local cfg = ns.GetCfg("visibility")
  if not (cfg and cfg.euiBarsEnabled) then return end
  euiAcc = euiAcc + elapsed
  if euiAcc < TICK_INTERVAL then return end
  local dt = euiAcc
  euiAcc = 0
  local full = EuiShowFull()
  for _, name in ipairs(EUI_BARS) do
    local f = _G[name]
    if f and not EuiBarAlways(EUI_BAR_KEY[name]) then
      EuiRelease(f, EUI_BAR_KEY[name])
    elseif f then
      local st = euiStates[f]
      local okA, cur = pcall(f.GetAlpha, f)
      cur = (okA and type(cur) == "number" and not (issecretvalue and issecretvalue(cur))) and cur or nil
      if not st then
        st = { alpha = cur or 1, host = cur or 1 }
        euiStates[f] = st
      end
      -- Ecriture d'EllesmereUI depuis notre dernier passage : nouvelle opacite d'origine (ou barre masquee par lui)
      if cur and st.written and math.abs(cur - st.written) > 0.01 then
        if cur <= 0.001 then st.hostOff = true else st.hostOff = false; st.host = cur; st.alpha = cur end
      end
      if not st.hostOff then
        local target = full and st.host or math.min(st.host, cfg.euiBarsAlpha or 0.2)
        if math.abs(st.alpha - target) > 0.002 then
          st.alpha = st.alpha + (target - st.alpha) * (1 - math.exp(-FADE_SPEED * dt))
        else
          st.alpha = target
        end
        pcall(f.SetAlpha, f, st.alpha)
        st.written = st.alpha
      end
    end
  end
end)

-- Integration coupee : opacite d'origine rendue
function Visibility.ApplyEuiBars()
  local cfg = ns.GetCfg("visibility")
  if cfg and cfg.euiBarsEnabled then return end
  for f in pairs(euiStates) do EuiRelease(f) end
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

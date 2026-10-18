-- Modules/HealthCircle.lua : Cercle de vie - hors combat quand blessé
local addonName, ns = ...
local L = ns.L

local HealthCircle = {}
ns.Modules.HealthCircle = HealthCircle

-- Références locales
local bar = nil
local healthAnimTicker = nil
local lastHealthVisState = nil
local previewMode = false
-- File d'attente de transition (meme principe que ResourceCircle.lua) : ne jamais interrompre une anim en cours
local hcAnimBusy = false
local hcAnimDirty = false

-- Variable pour savoir si le bar etait montre en preview (pour annuler l'anim)
local healthMoveTicker = nil
local _hcAnimElems = {}   -- pré-alloué une fois dans Create(), réutilisé à chaque animation

-- Diametre de repli du cache sombre sous le texte (px), si la config n'en donne pas.
-- Reglable via healthCircle.textBackdropSize, comme sur le cercle central.
local TEXT_BACKDROP_DEFAULT = 18

-- Battement de coeur OOC : pouls lent sur le bar global
local pulseTicker    = nil
local pulseStartTime = 0
local PULSE_CYCLE = 1.45  -- secondes par cycle (0.65s battement + 0.80s repos)
-- Keyframes : temps ABSOLU converti en fraction de PULSE_CYCLE
-- Battement actif sur 0→0.65s, repos 0.65→1.45s (vitesse du battement = v1 originale)
local PULSE_KEYS = {
  { t = 0.000, s = 1.000 },   -- repos  -> montée
  { t = 0.103, s = 1.008 },   -- pic 1 (battement principal)
  { t = 0.207, s = 1.002 },   -- creux inter-battement
  { t = 0.310, s = 1.006 },   -- pic 2 (plus doux)
  { t = 0.448, s = 1.000 },   -- retour repos
  { t = 1.000, s = 1.000 },   -- fin de cycle
}

local function EvalPulse(phase)
  -- phase dans [0, 1] ; interpolation smoothstep entre keyframes
  for i = 1, #PULSE_KEYS - 1 do
    local k0, k1 = PULSE_KEYS[i], PULSE_KEYS[i + 1]
    if phase <= k1.t then
      local span = k1.t - k0.t
      local lp   = (phase - k0.t) / span
      local ease = lp * lp * (3 - 2 * lp)   -- smoothstep
      return k0.s + (k1.s - k0.s) * ease
    end
  end
  return 1.0
end

local function StartPulse()
  if pulseTicker then return end
  local cfg = ns.GetCfg("healthCircle")
  if cfg.heartbeatPulse == false then return end
  pulseStartTime = GetTime()
  -- Ancrer le cercle par le BAS so qu'il grossisse vers le haut
  if bar._pulseAnchorX and bar._pulseHalfSize then
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", bar._pulseAnchorX, bar._pulseAnchorY - bar._pulseHalfSize)
  end
  pulseTicker = ns.NewTicker(0.016, function()
    if not bar or not bar:IsShown() then return end
    local now = GetTime()
    local phase = ((now - pulseStartTime) % PULSE_CYCLE) / PULSE_CYCLE
    bar:SetScale(EvalPulse(phase))
    -- Stagger de l'overlay : légèrement en retard → la bague de couleur se révèle brièvement
    if bar.overlayFrame then
      local phaseOvl = ((now - pulseStartTime - 0.2 + PULSE_CYCLE) % PULSE_CYCLE) / PULSE_CYCLE
      bar.overlayFrame:SetScale(EvalPulse(phaseOvl))
    end
  end)
end

local function StopPulse()
  if pulseTicker then pulseTicker:Cancel(); pulseTicker = nil end
  if bar then
    bar:SetScale(1)
    if bar.overlayFrame then bar.overlayFrame:SetScale(1) end
    if bar.text then bar.text:SetAlpha(1) end
    if bar._pulseAnchorX then
      bar:ClearAllPoints()
      bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bar._pulseAnchorX, bar._pulseAnchorY)
    end
  end
end

-- Soins previsionnels : calculateur cree dans HealthCircle.Create. Declare ICI, avant
-- Create : plus bas, l'assignation serait partie dans un global et ce local serait reste nil.
local hpCalc
local _hcCalcTries = 0   -- tentatives de creation du calculateur

--- Cree le calculateur au besoin, et le reessaie tant qu'il manque : une seule tentative a
--- l'init suffisait a tout condamner en silence, le code retombant alors sur
--- UnitGetIncomingHeals -- muette sur retail, d'ou des soins toujours nuls.
--- Memes modes que les barres d'unites (cf. Modules/UnitBars.lua), qui elles fonctionnent.
local function EnsureHealCalc()
  if hpCalc then return hpCalc end
  if not CreateUnitHealPredictionCalculator then return nil end
  _hcCalcTries = _hcCalcTries + 1
  pcall(function()
    local c = CreateUnitHealPredictionCalculator()
    if c.SetMaximumHealthMode and Enum and Enum.UnitMaximumHealthMode then
      c:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
    end
    if c.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
      c:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
    end
    if c.SetIncomingHealClampMode and Enum and Enum.UnitIncomingHealClampMode then
      c:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)
    end
    hpCalc = c
  end)
  return hpCalc
end

-- Crop constant for circle_piecrop.tga (texture pre-croppee, bas transparent supprime)
local ARC_CROP_H = 0.88
local PIECROP = "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga"

-- Arcs en rendu radial natif (StatusBar:SetRenderMode(Radial)) sur un disque plein, comme OutOfCombatResourceCircle.lua.
-- Remplissage (cfg.arcFillMode) : "vertical" (bas -> haut, ancien rendu, defaut), "cw" / "ccw", "mirror_out" (du milieu
-- de l'arc vers les extremites), "mirror_in" (des extremites vers le milieu). Les miroirs utilisent deux arcs, un par sens.
-- Miroirs : l'angle de depart est le POINT D'ORIGINE commun des deux arcs, l'angle de fin l'etendue maximale de CHAQUE arc
-- (0 a 180 deg). Depart 0 / fin 90 : l'arc droit va de midi a 3 h, l'arc gauche de midi a 9 h. "Sortant" : les deux
-- partent de l'origine ; "entrant" : ils partent des extremites et convergent vers l'origine.

-- Migration unique des anciens profils : "overlayRatio" (taille du trou) devient "arcThickness" (epaisseur de l'anneau,
-- fraction du diametre de l'arc). Le rendu des profils existants est conserve.
function HealthCircle.EnsureArcSettings()
  local cfg = ns.GetCfg("healthCircle")
  if not cfg then return cfg end
  if not cfg.arcGeomV2 then
    cfg.arcThickness = math.max(0.01, math.min(1, 1 - (cfg.overlayRatio or 0.75)))
    cfg.arcGeomV2 = true
  end
  return cfg
end

-- Masque central qui creuse l'anneau : trou = 1 - epaisseur (en fraction du diametre de l'arc).
local function OverlayPx(cfg, arcPx)
  local hole = 1 - (cfg.arcThickness or 0.25)
  return arcPx * math.max(0, math.min(hole, 0.995))
end

-- SetMinMaxValues est enveloppe : le maximum est agrandi de 360/etendue pour que 0-100 % ne parcoure que l'arc.
local function SetupRadialArc(sb)
  ns.SetSmoothStatusBarTexture(sb, ns.Media.circle)
  sb:SetRenderMode(Enum.StatusBarRenderMode.Radial)
  local raw = sb.SetMinMaxValues
  sb._k = 1
  sb.SetMinMaxValues = function(self, lo, hi)
    self._ulo, self._uhi = lo, hi
    local k, scaled = self._k or 1, hi
    if k ~= 1 then
      local ok, v = pcall(function() return hi * k end)
      if ok then scaled = v end
    end
    raw(self, lo, scaled)
  end
end

-- Angles (degres, horaire, 0 = midi) : depart et fin de l'arc ; SetReverseFill inverse le sens du remplissage.
local function SetArcAngle(sb, startDeg, endDeg, reverse)
  if not sb then return end
  local a0, a1 = tonumber(startDeg) or 220, tonumber(endDeg) or 140
  sb._angS, sb._angE, sb._angR = a0, a1, reverse and true or false   -- relus par l'arc de soins entrants
  local span = (a1 - a0) % 360
  if span < 1 then span = 360 end
  -- Rendu radial : le sens antihoraire se regle sur la texture geree (SetRadialProgressBarReverse, 12.1) ;
  -- StatusBar:SetReverseFill ne joue que sur l'axe lineaire. Repli sur ce dernier si l'API est absente.
  local tex = sb:GetStatusBarTexture()
  if tex and tex.SetRadialProgressBarReverse then
    sb:SetReverseFill(false)
    tex:SetRadialProgressBarReverse(reverse and true or false)
  else
    sb:SetReverseFill(reverse and true or false)
  end
  if tex then tex:SetRotation(-math.rad(reverse and a1 or a0)) end
  local k = 360 / span
  if sb._k ~= k then
    sb._k = k
    pcall(sb.SetMinMaxValues, sb, sb._ulo or 0, sb._uhi or 100)
  end
end

-- "Remplissage inverse" (cfg.arcFillInverted) : horaire <-> antihoraire, miroir sortant <-> entrant, vertical de haut en bas.
local FILL_INVERSE = { cw = "ccw", ccw = "cw", mirror_out = "mirror_in", mirror_in = "mirror_out", vertical = "vertical" }

-- Mode de remplissage courant : montre / cache les arcs concernes et regle leurs angles.
-- Les arcs de soins (harc, harc2) sont montres par UpdateHealPrediction.
-- Modes radiaux : la regle verticale (arcV) est peinte de la couleur du fond du cercle. Posee entre le disque de
-- prevision (dessous) et les arcs de vie (dessus), elle masque le vert partout ou la vie "est deja", y compris dans
-- l'ouverture de l'arc : seul le vert entre le bout de l'arc et le bout des soins reste visible.
local function PaintRuler()
  if not (bar and bar.arcV) then return end
  if bar._hRuler then
    local r, g, b = 0x0e / 255, 0x0e / 255, 0x0e / 255
    if bar.bgLarge then r, g, b = bar.bgLarge:GetVertexColor() end
    bar.arcV:SetStatusBarColor(r, g, b, 1)
  end
end

local function ApplyArcAngles()
  if not bar then return end
  local cfg = ns.GetCfg("healthCircle")
  local mode = cfg.arcFillMode or "vertical"
  local inverted = cfg.arcFillInverted == true
  if inverted then mode = FILL_INVERSE[mode] or mode end
  local vertical = (mode == "vertical")
  local mirror = (mode == "mirror_out" or mode == "mirror_in")
  bar.arc:SetShown(not vertical)
  bar.arc2:SetShown(mirror)
  -- Remplissage vertical toujours present : en modes radiaux il reste invisible (texture a alpha 0) et ne sert
  -- que de regle a la prevision des soins, qui reste verticale (hybride : sur Retail, vie et soins sont secrets,
  -- seul l'ancrage sur le sommet du remplissage permet d'"additionner" les deux).
  bar.arcV:Show()
  local vtex = bar.arcV:GetStatusBarTexture()
  -- Modes radiaux : regle invisible (repere de hauteur seulement) ; seul le disque de prevision se voit, sous les arcs
  -- Alpha du CADRE (pas de la texture : le StatusBar la reaffiche quand sa valeur change). Les ancrages de la
  -- prevision restent valides sur un cadre transparent.
  if vtex then vtex:SetAlpha(1) end
  bar.arcV:SetAlpha(vertical and 1 or 0)
  bar._hRuler = false
  -- Plans : disque de prevision < regle < arcs de vie < masque central < texte
  local base = bar.arcGroup and bar.arcGroup:GetFrameLevel()
  if base then
    if bar.healClip then bar.healClip:SetFrameLevel(base) end
    bar.arcV:SetFrameLevel(base + 1)
    bar.arc:SetFrameLevel(base + 2); bar.arc2:SetFrameLevel(base + 2)
    if bar.overlayFrame then bar.overlayFrame:SetFrameLevel(base + 3) end
    if bar.textFrame then bar.textFrame:SetFrameLevel(base + 4) end
  end
  if vertical then
    local CLR = ns.Modules.Colors
    local c = (CLR and CLR.Get("oochealth")) or cfg.barColor
    bar.arcV:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
  else
    PaintRuler()
  end

  -- Modes radiaux : la regle verticale doit arriver a la HAUTEUR du bout de l'arc de vie, pas a "% de vie" du
  -- disque (l'arc ne demarre pas forcement en bas, et la hauteur d'un point de l'arc n'est pas lineaire en
  -- angle). Courbe "% de vie -> % de remplissage vertical", deduite des angles et du mode, evaluee par le jeu
  -- sur la vie secrete (UnitHealthPercent avec courbe, cf. HealthCircle.Update). Si le bout de l'arc DESCEND
  -- quand la vie monte, la regle se remplit depuis le haut et la prevision s'etend vers le bas.
  -- Axe de la prevision : "v" (origine en bas / en haut, depart ~0 / ~180), "h" (sur le cote, ~90 / ~270), sinon
  -- aucun (horaire, antihoraire, axe en biais) : pas de prevision plutot qu'une prevision fausse.
  local axis
  if vertical then
    axis = (not inverted) and "v" or nil
  elseif mirror then
    local o = (tonumber(cfg.arcStartAngle) or 220) % 180
    if o <= 2 or o >= 178 then axis = "v" elseif math.abs(o - 90) <= 2 then axis = "h" end
  end
  bar._predAxis = axis
  bar._hCurve, bar._hDown = nil, false
  if not vertical and axis and C_CurveUtil and C_CurveUtil.CreateCurve then
    local a0c, a1c = tonumber(cfg.arcStartAngle) or 220, tonumber(cfg.arcEndAngle) or 140
    -- Bout de l'arc pour f = % de vie (convention de SetArcAngle : "reverse" part de l'angle de fin). Miroirs : moitie
    -- horaire, l'autre est symetrique en hauteur.
    local function Front(f)
      if mirror then
        local half = math.max(1, math.min(a1c, 180))
        if mode == "mirror_out" then return a0c + f * half end
        return a0c + half - f * half
      end
      local span = (a1c - a0c) % 360
      if span < 1 then span = 360 end
      if mode == "ccw" then return a1c - f * span end
      return a0c + f * span
    end
    local lo = 1 - 2 * ARC_CROP_H                  -- bas de la regle (texture croppee), en unites du rayon
    local function H(f)
      -- L'angle 0 du rendu radial est EN BAS (6h), pas a midi (constate en jeu : depart 180 = midi) : d'ou le signe.
      -- Axe horizontal : position gauche -> droite sur le disque entier (regle carree, sans decoupe).
      local a = math.rad(Front(f))
      if axis == "h" then
        return math.max(0, math.min(1, (1 - math.sin(a)) / 2))
      end
      local y = -math.cos(a)
      return math.max(0, math.min(1, (y - lo) / (2 * ARC_CROP_H)))
    end
    local down = H(1) < H(0)
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if ok and c then
      for i = 0, 40 do
        local f = i / 40
        local h = H(f)
        c:AddPoint(f, (down and (1 - h) or h) * 100)
      end
      bar._hCurve, bar._hDown = c, down
    end
  end
  local down = bar._hDown
  local hAxis = (axis == "h")
  bar._hRulerBar = hAxis and bar.arcH or bar.arcV
  bar.arcV:SetReverseFill((vertical and inverted) or (not vertical and not hAxis and down))
  -- Jeu horizontal : regles et cadre de rognage, sens selon que le bout de l'arc va vers la gauche ou la droite
  if bar.arcH then
    local ht2 = bar.arcHealH:GetStatusBarTexture()
    local rt = bar.arcH:GetStatusBarTexture()
    bar.arcH:SetReverseFill(hAxis and down or false)
    bar.arcHealH:ClearAllPoints()
    bar.arcHealH:SetReverseFill(hAxis and down or false)
    if hAxis and down then bar.arcHealH:SetPoint("RIGHT", rt, "LEFT", 0, 0) else bar.arcHealH:SetPoint("LEFT", rt, "RIGHT", 0, 0) end
    local cH = bar.healClipH
    cH:ClearAllPoints()
    cH:SetPoint("TOP", bar.arcH, "TOP", 0, 0)
    cH:SetPoint("BOTTOM", bar.arcH, "BOTTOM", 0, 0)
    if hAxis and down then
      cH:SetPoint("RIGHT", bar.arcH, "RIGHT", 0, 0)
      cH:SetPoint("LEFT", ht2, "LEFT", 0, 0)
    else
      cH:SetPoint("LEFT", bar.arcH, "LEFT", 0, 0)
      cH:SetPoint("RIGHT", ht2, "RIGHT", 0, 0)
    end
    local dH = math.max(1, (bar.arcH:GetWidth() or 60) * 0.02)
    bar.healTexH:ClearAllPoints()
    bar.healTexH:SetPoint("TOPLEFT", bar.arcH, "TOPLEFT", dH, -dH)
    bar.healTexH:SetPoint("BOTTOMRIGHT", bar.arcH, "BOTTOMRIGHT", -dH, dH)
    if base then cH:SetFrameLevel(base); bar.arcH:SetFrameLevel(base + 1) end
    cH:SetShown(hAxis and cfg.showHealPrediction ~= false)
  end

  -- Regle des soins entrants : posee au bout de la regle de vie, dans le sens ou elle avance
  local vt = bar.arcV:GetStatusBarTexture()
  if bar.arcHeal then
    bar.arcHeal:ClearAllPoints()
    if down then bar.arcHeal:SetPoint("TOP", vt, "BOTTOM", 0, 0) else bar.arcHeal:SetPoint("BOTTOM", vt, "TOP", 0, 0) end
    bar.arcHeal:SetReverseFill(down and true or false)
  end
  -- Disque de prevision : en radial, legerement plus petit que les arcs (meme centre, meme decoupe du bas) pour
  -- qu'aucun liseret vert ne depasse de leur bord exterieur ; en vertical, cale sur la regle.
  if bar.healTex then
    bar.healTex:ClearAllPoints()
    if vertical then
      bar.healTex:SetAllPoints(bar.arcV)
      if bar.healClip then bar.healClip:SetAlpha(1) end   -- l'opacite pilotee par les soins ne sert qu'en radial
    else
      local d = math.max(1, (bar.arcV:GetWidth() or 60) * 0.02)
      bar.healTex:SetPoint("TOPLEFT", bar.arcV, "TOPLEFT", d, -d)
      bar.healTex:SetPoint("BOTTOMRIGHT", bar.arcV, "BOTTOMRIGHT", -d, d * (2 * ARC_CROP_H - 1))
    end
  end
  -- Soins previsionnels verticaux : ancres sur le sommet du remplissage, donc inutilisables s'il part du haut
  if bar.healClip then
    -- Radial : la bande de prevision est horizontale, elle n'est juste que si les deux bouts de l'arc sont toujours a
    -- la meme hauteur, c.-a-d. en miroir avec l'origine en haut ou en bas (depart ~0 ou ~180). Sinon (axe en biais,
    -- horaire / antihoraire) : pas de prevision plutot qu'une prevision fausse.
    local predOK = axis ~= nil
    bar._predOK = predOK
    bar.healClip:SetShown(axis == "v" and cfg.showHealPrediction ~= false)
    -- Vertical : bande entre le sommet de la vie et celui des soins. Radial : disque "vie + soins" entier, depuis
    -- le bord de depart de la regle jusqu'au bout des soins, pose SOUS les arcs : seule la part qui depasse se voit.
    local clip, ht = bar.healClip, bar.arcHeal:GetStatusBarTexture()
    clip:ClearAllPoints()
    clip:SetPoint("LEFT",  bar.arcV, "LEFT",  0, 0)
    clip:SetPoint("RIGHT", bar.arcV, "RIGHT", 0, 0)
    if vertical then
      clip:SetPoint("BOTTOM", vt, "TOP", 0, 0)
      clip:SetPoint("TOP", ht, "TOP", 0, 0)
    elseif down then
      clip:SetPoint("TOP", bar.arcV, "TOP", 0, 0)
      clip:SetPoint("BOTTOM", ht, "BOTTOM", 0, 0)
    else
      clip:SetPoint("BOTTOM", bar.arcV, "BOTTOM", 0, 0)
      clip:SetPoint("TOP", ht, "TOP", 0, 0)
    end
  end
  if vertical then
    bar.harc:Hide(); bar.harc2:Hide()
    if bar.iarc then bar.iarc:Hide(); bar.iarc2:Hide() end
    if bar.gapArc then bar.gapArc:Hide() end
    return
  end
  local a0, a1 = tonumber(cfg.arcStartAngle) or 220, tonumber(cfg.arcEndAngle) or 140
  -- Ouverture : de la fin de l'arc a son debut (miroir : d'une extremite a l'autre en passant par l'exterieur)
  if bar.gapArc then
    local g0, g1
    if mirror then
      local half = math.max(1, math.min(a1, 180))
      if half < 179.5 then g0, g1 = a0 + half, a0 - half end
    else
      local span = (a1 - a0) % 360
      if span >= 1 and span < 359.5 then g0, g1 = a1, a0 end
    end
    local show = g0 ~= nil and bar._predOK and cfg.showHealPrediction ~= false
    bar.gapArc:SetShown(show)
    if show then
      if base then bar.gapArc:SetFrameLevel(base + 1) end
      local r, g, b = 0x0e / 255, 0x0e / 255, 0x0e / 255
      if bar.bgLarge then r, g, b = bar.bgLarge:GetVertexColor() end
      bar.gapArc:SetStatusBarColor(r, g, b, 1)
      SetArcAngle(bar.gapArc, g0, g1, false)
      bar.gapArc:SetValue(100)
    end
  end
  if mirror then
    local half = math.max(1, math.min(a1, 180))
    local out = (mode == "mirror_out")
    SetArcAngle(bar.arc,   a0, a0 + half, not out)   -- arc horaire : origine -> origine + etendue
    SetArcAngle(bar.harc,  a0, a0 + half, not out)
    SetArcAngle(bar.arc2,  a0 - half, a0, out)       -- arc antihoraire : origine -> origine - etendue
    SetArcAngle(bar.harc2, a0 - half, a0, out)
  else
    SetArcAngle(bar.arc,  a0, a1, mode == "ccw")
    SetArcAngle(bar.harc, a0, a1, mode == "ccw")
  end
end

-- Apercu anime (panneau de reglages ouvert) : le remplissage va et vient de 0 a 100 %, pour juger le mode choisi.
local previewTicker = nil
local previewPct = 72
local function PreviewSweep()
  local t = (GetTime() % 5) / 2.5
  if t > 1 then t = 2 - t end
  return math.floor(t * t * (3 - 2 * t) * 100 + 0.5)   -- lissage aux extremites
end
local function StopPreviewAnim()
  if previewTicker then previewTicker:Cancel(); previewTicker = nil end
  previewPct = 72
end

-- Applique pct (0-100, peut etre secret) aux arcs de vie.
local function ApplyArcValue(pct)
  pcall(ns.SmoothBarValue, bar.arc, pct)
  pcall(ns.SmoothBarValue, bar.arc2, pct)
  pcall(ns.SmoothBarValue, bar.arcV, pct)
end

-- Coeur central : taille fixe (px, avant application du scale global du cercle).
local HEART_SIZE = 8

-- Suivi de l'état "blessé" via événements (contourne les secret numbers)
local playerIsDamaged = false
local lastHealthChangeTime = 0

-- Frame de tracking des événements de vie
local healthTrackFrame = CreateFrame("Frame")
healthTrackFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
-- Un soin en vol ne change pas encore la vie : sans cet evenement, le cercle se masquait
-- au bout de hideDelay pendant tout le cast, Update() sortait aussitot et la prevision
-- n'etait jamais calculee -- elle n'apparaissait qu'une fois le soin applique.
healthTrackFrame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", "player")
healthTrackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
healthTrackFrame:RegisterEvent("PLAYER_DEAD")
healthTrackFrame:RegisterEvent("PLAYER_UNGHOST")
healthTrackFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
healthTrackFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
local _hcInCombat = false
local hcClickPending = false   -- EnableMouse sur la zone de clic reporte a la sortie de combat
local hcClickWanted  = false   -- valeur demandee pendant le combat, rejouee telle quelle ensuite
local hcDragArmed    = false   -- panneau de reglages ouvert : le drag prime sur la zone de clic

-- La zone de clic suit le cercle hors combat seulement : en combat elle reste cachee (Show/Hide
-- d'un bouton securise y sont interdits), le cercle lui-meme restant libre de s'afficher/se cacher.
-- Aucun ancrage au cercle (un frame securise ancre dessus pourrait le rendre protege) : le bouton
-- est cale sur UIParent aux coordonnees ecran du cercle, recopiees a chaque synchro.
local function SyncClickVisibility()
  local click = bar and bar.clickOverlay
  if not click or InCombatLockdown() then return end
  local show = bar:IsShown() and not _hcInCombat
  if show then
    local cx, cy = bar:GetCenter()
    if not cx then show = false else
      local k = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
      click:ClearAllPoints()
      click:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * k, cy * k)
      click:SetSize(bar:GetWidth() * k, bar:GetHeight() * k)
    end
  end
  click:SetShown(show)
end

healthTrackFrame:SetScript("OnEvent", function(self, event)
  if event == "PLAYER_REGEN_DISABLED" then
    _hcInCombat = true
    -- Event recu juste AVANT le verrouillage de combat : dernier moment pour cacher le bouton securise
    SyncClickVisibility()
    -- En entrant en combat, marquer comme blessé mais ne pas toucher au timer :
    -- le timer démarrera proprement à la fin du combat.
    playerIsDamaged = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    _hcInCombat = false
    -- Démarrer le compte à rebours hideDelay à partir de maintenant,
    -- quelle que soit l'activité UNIT_HEALTH pendant le combat.
    lastHealthChangeTime = GetTime()
    -- Rejouer la demande TELLE QUELLE : relire la config ici ré-armerait le clic alors que
    -- le panneau de reglages, ouvert pendant le combat, l'avait desarme pour le drag.
    if hcClickPending then HealthCircle.ApplyClickable(hcClickWanted) end
    SyncClickVisibility()
  elseif event == "PLAYER_ENTERING_WORLD" then
    playerIsDamaged = true
    lastHealthChangeTime = GetTime()
  elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" then
    playerIsDamaged = false
    lastHealthChangeTime = 0
  elseif event == "UNIT_HEAL_PREDICTION" then
    -- Hors combat seulement, comme UNIT_HEALTH : en combat le cercle est masque de toute facon.
    if not _hcInCombat then
      playerIsDamaged = true
      lastHealthChangeTime = GetTime()
    end
  elseif event == "UNIT_HEALTH" then
    -- Mettre à jour le timer uniquement hors combat.
    -- En combat, les soins/regen ne doivent pas repousser indéfiniment le délai.
    if not _hcInCombat then
      playerIsDamaged = true
      lastHealthChangeTime = GetTime()
    end
  end
end)

-- Joueur "blessé" : sa vie a bougé il y a moins de hideDelay secondes (ou on sort de combat).
-- Même notion que celle qui affiche le cercle ; réutilisée par les Extra Bars.
function HealthCircle.IsPlayerInjured()
  local cfg = ns.GetCfg("healthCircle")
  local hideDelay = cfg and cfg.hideDelay or 1.5
  if playerIsDamaged and (GetTime() - lastHealthChangeTime) > hideDelay then
    playerIsDamaged = false
  end
  return playerIsDamaged and true or false
end

-- Vérifie si le cercle doit être visible (hors combat + blessé)
function HealthCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideHealthCircle ~= false then return false end
  local cfg = ns.GetCfg("healthCircle")
  if cfg.enabled == false then return false end
  -- Jamais affiche si la vraie barre de vie (UnitBars) l'est deja, sinon double affichage de la meme info
  local UB = ns.Modules and ns.Modules.UnitBars
  if UB and UB.IsPlayerBarShown and UB.IsPlayerBarShown() then return false end
  -- "Toujours actif en instance" : ignore les transitions combat tant qu'on
  -- est en donjon/raid (ns.inInstance, cf. Core.lua).
  if cfg.alwaysInInstance and ns.inInstance then return true end
  if UnitAffectingCombat("player") then return false end
  local vMode = cfg.visibilityMode or "important"
  if vMode == "always" then return true end
  -- "important" (default) : visible seulement quand le joueur est blesse
  return HealthCircle.IsPlayerInjured()
end

-- Applique les settings en live (taille, police, etc.)
function HealthCircle.ApplySettings()
  HealthCircle.EnsureArcSettings()
  if not bar then return end
  local cfg = ns.GetCfg("healthCircle")

  -- Gerer l'activation/desactivation en live
  if cfg.enabled == false then
    if healthAnimTicker then healthAnimTicker:Cancel(); healthAnimTicker = nil end
    -- Desactivation live du module : interruption immediate voulue (comme
    -- SetPreview) -- on remet aussi le verrou de file d'attente a plat.
    hcAnimBusy = false
    hcAnimDirty = false
    bar:Hide()
    bar._healthShown = false
    lastHealthVisState = nil
    return
  end
  -- Forcer un re-check de visibilite (le module vient peut-etre d'etre reactive)
  lastHealthVisState = nil

  local size   = cfg.size
  local bgSize = size * 1.1
  bar:SetSize(size, size)
  bar.bgLarge:SetSize(bgSize, bgSize)
  local arcPx     = size * (cfg.arcSizeRatio or 1.0)
  local overlayPx = OverlayPx(cfg, arcPx)
  for _, a in ipairs({ bar.arc, bar.arc2, bar.harc, bar.harc2, bar.iarc, bar.iarc2, bar.gapArc }) do
    a:SetSize(arcPx, arcPx)
    a:ClearAllPoints()
    a:SetPoint("CENTER", bar, "CENTER", 0, 0)
  end
  bar.arcV:SetSize(arcPx, arcPx * ARC_CROP_H)
  bar.arcV:ClearAllPoints()
  bar.arcV:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  -- La regle de mesure garde sa taille, mais PAS son ancrage : il doit rester pose sur le
  -- sommet du fill de vie, c'est lui qui fait l'addition (cf. HealthCircle.Create).
  if bar.arcHeal then bar.arcHeal:SetSize(arcPx, arcPx * ARC_CROP_H) end
  for _, r in ipairs({ bar.arcH, bar.arcHealH }) do r:SetSize(arcPx, arcPx) end
  if bar.overlay then
    if overlayPx >= 2 then
      bar.overlay:SetSize(overlayPx, overlayPx)
      bar.overlay:Show()
      if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    else
      bar.overlay:Hide()
    end
  end
  if bar.textBackdrop then
    local tbPx = math.max(1, cfg.textBackdropSize or TEXT_BACKDROP_DEFAULT)
    bar.textBackdrop:SetSize(tbPx, tbPx)
    ns.SizeTextBackdropGlow(bar.textBackdropGlow, tbPx)
  end
  bar.text:SetFont(cfg.font or ns.Media.font, cfg.fontSize)
  -- Couleurs via Colors.Get() en priorité, sinon depuis la config
  local CLR    = ns.Modules.Colors
  local arcC   = (CLR and CLR.Get("oochealth")) or cfg.barColor
  local dotC   = (CLR and CLR.Get("oocdot"))    or cfg.barColor
  local textC  = dotC  -- texte du cercle de vie = couleur OoC Dot
  bar.text:SetTextColor(textC[1], textC[2], textC[3], textC[4] or 1)
  for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV }) do
    a:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1)
  end
  PaintRuler()
  ApplyArcAngles()
  -- Redimensionner le coeur central proportionnellement
  local baseSize = ns.Defaults.healthCircle.size
  local scale = size / baseSize
  if bar.dot3 then
    bar.dot3:SetSize(HEART_SIZE * scale, HEART_SIZE * scale)
    bar.dot3:ClearAllPoints()
    bar.dot3:SetPoint("BOTTOM", bar, "BOTTOM", cfg.dotPositions[3][1] * scale, cfg.dotPositions[3][2] * scale)
    bar.dot3:SetVertexColor(dotC[1], dotC[2], dotC[3], 1)
  end
  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  bar:ClearAllPoints()
  local _ax = sw * cfg.anchorPctX + cfg.x
  local _ay = sh * cfg.anchorPctY + cfg.y
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", _ax, _ay)
  bar._pulseAnchorX  = _ax
  bar._pulseAnchorY  = _ay
  bar._pulseHalfSize = cfg.size / 2

  -- Forcer la visibilite apres changement de settings
  -- Si le pouls vient d'être désactivé, l'arrêter immédiatement
  if ns.GetCfg("healthCircle").heartbeatPulse == false then
    StopPulse()
  end
  -- Le panneau ouvert arme le drag, qui exige que la zone de clic lache la souris.
  if hcDragArmed then HealthCircle.ApplyClickable(false) else HealthCircle.ApplyClickable() end

  if previewMode then
    HealthCircle.SetPreview(true)
  else
    HealthCircle.UpdateVisibility()
  end
end

function HealthCircle.Create(parent)
  HealthCircle.EnsureArcSettings()
  if bar then return bar end
  local cfg = ns.GetCfg("healthCircle")

  bar = CreateFrame("Frame", "AishCoreHealthRing", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetFrameStrata("LOW")

  -- Position : bas gauche + offset
  local sw = UIParent:GetWidth()
  local sh = UIParent:GetHeight()
  local _bax = sw * cfg.anchorPctX + cfg.x
  local _bay = sh * cfg.anchorPctY + cfg.y
  bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", _bax, _bay)
  bar._pulseAnchorX  = _bax
  bar._pulseAnchorY  = _bay
  bar._pulseHalfSize = cfg.size / 2

  -- Grand fond opaque
  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  bgLarge:SetTexture(ns.Media.circle)
  bgLarge:SetSize(cfg.bgSize, cfg.bgSize)
  bgLarge:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge

  -- Arc (remplissage bas -> haut, texture circulaire pre-croppee)
  local arcPx = cfg.size * (cfg.arcSizeRatio or 1.0)

  -- Soins previsionnels : second arc, de meme geometrie, rempli a (vie + soins) et pose
  -- SOUS celui de la vie. La bande qui depasse l'arc de vie est donc exactement la part
  -- des soins en vol ; a zero soin les deux arcs coincident et celui-ci est invisible.
  EnsureHealCalc()

  -- arcGroup : un seul element a afficher / animer, quel que soit le mode de remplissage (cf. ApplyArcAngles)
  local arcGroup = CreateFrame("Frame", nil, bar)
  arcGroup:SetFrameLevel(bar:GetFrameLevel() + 1)
  arcGroup:SetAllPoints(bar)
  bar.arcGroup = arcGroup
  local function NewRadial(name, lvl)
    local a = CreateFrame("StatusBar", name, arcGroup)
    a:SetFrameLevel(arcGroup:GetFrameLevel() + lvl)
    a:SetSize(arcPx, arcPx)
    a:SetPoint("CENTER", bar, "CENTER", 0, 0)
    SetupRadialArc(a)
    a:SetMinMaxValues(0, 100)
    a:SetValue(0)
    return a
  end
  -- Soins previsionnels en radial : arcs poses SOUS ceux de la vie, remplis a (vie + soins) ; la bande qui depasse est la part des soins.
  bar.harc  = NewRadial(nil, 0)
  bar.harc2 = NewRadial(nil, 0)
  -- Soins entrants (prevision pendant un cast) : arcs qui DEMARRENT au bout de l'arc de vie (cf. UpdateHealPrediction)
  bar.iarc  = NewRadial(nil, 0)
  bar.iarc2 = NewRadial(nil, 0)
  local arc = NewRadial("AishCoreHealthRingArc", 1)
  arc:SetStatusBarColor(unpack(cfg.barColor))
  bar.arc = arc
  bar.arc2 = NewRadial(nil, 1)   -- 2e moitie des remplissages miroir
  -- Cache de l'ouverture de l'arc (modes radiaux) : secteur plein, couleur du fond, pose sur le disque de prevision.
  -- Le vert ne peut ainsi apparaitre que dans l'amplitude de l'arc (angle de fin), jamais dans son ouverture.
  bar.gapArc = NewRadial(nil, 1)
  bar.gapArc:SetStatusBarColor(0x0e / 255, 0x0e / 255, 0x0e / 255, 1)
  bar.gapArc:SetValue(100)
  bar.gapArc:Hide()

  -- Remplissage vertical (ancien rendu) : barre de bas en haut sur la texture pre-croppee
  local arcV = CreateFrame("StatusBar", nil, arcGroup)
  arcV:SetFrameLevel(arcGroup:GetFrameLevel() + 1)
  arcV:SetSize(arcPx, arcPx * ARC_CROP_H)
  arcV:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  arcV:SetStatusBarTexture(PIECROP)
  arcV:SetStatusBarColor(unpack(cfg.barColor))
  arcV:SetOrientation("VERTICAL")
  arcV:SetMinMaxValues(0, 100)
  arcV:SetValue(0)
  bar.arcV = arcV

  -- Soins previsionnels (mode vertical) : exactement le principe des barres d'unites -- aucun calcul, c'est
  -- l'ANCRAGE qui additionne. L'arithmetique sur les valeurs secretes etant refusee, c'est
  -- la seule voie. Trois pieces :
  --   arcHeal  : regle de mesure invisible, posee sur le sommet du fill de vie et remplie a
  --              "soins" -- le sommet de SON fill tombe donc pile a (vie + soins)
  --   healClip : cadre de rognage tendu entre ces deux sommets
  --   healTex  : le disque entier, aligne sur l'arc de vie et non sur le cadre, donc jamais
  --              deforme ; seule la tranche [vie, vie+soins] en ressort
  local arcHeal = CreateFrame("StatusBar", nil, bar)
  arcHeal:SetFrameLevel(bar:GetFrameLevel() + 1)
  arcHeal:SetSize(arcPx, arcPx * ARC_CROP_H)
  arcHeal:SetPoint("BOTTOM", arcV:GetStatusBarTexture(), "TOP", 0, 0)
  arcHeal:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
  arcHeal:SetOrientation("VERTICAL")
  arcHeal:SetMinMaxValues(0, 100)
  arcHeal:SetValue(0)
  arcHeal:SetAlpha(0)          -- regle de mesure : jamais visible
  bar.arcHeal = arcHeal

  local healClip = CreateFrame("Frame", nil, arcGroup)
  healClip:SetFrameLevel(arcGroup:GetFrameLevel())
  healClip:SetPoint("LEFT",   arcV, "LEFT",  0, 0)
  healClip:SetPoint("RIGHT",  arcV, "RIGHT", 0, 0)
  healClip:SetPoint("BOTTOM", arcV:GetStatusBarTexture(), "TOP", 0, 0)
  healClip:SetPoint("TOP",    arcHeal:GetStatusBarTexture(), "TOP", 0, 0)
  if healClip.SetClipsChildren then healClip:SetClipsChildren(true) end
  bar.healClip = healClip

  local healTex = healClip:CreateTexture(nil, "ARTWORK")
  healTex:SetTexture(PIECROP)
  healTex:SetAllPoints(arcV)   -- aligne sur le cercle, pas sur le cadre de rognage
  bar.healTex = healTex

  -- Meme mecanique sur l'axe horizontal (miroir avec origine a 90 / 270) : regle de vie, regle des soins, cadre de
  -- rognage et disque de prevision, de gauche a droite ou de droite a gauche.
  local function Ruler(parent)
    local r = CreateFrame("StatusBar", nil, parent)
    r:SetSize(arcPx, arcPx)
    r:SetPoint("CENTER", bar, "CENTER", 0, 0)
    r:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r:SetOrientation("HORIZONTAL")
    r:SetMinMaxValues(0, 100)
    r:SetValue(0)
    r:SetAlpha(0)                 -- regle : jamais visible
    return r
  end
  bar.arcH = Ruler(arcGroup)
  bar.arcHealH = Ruler(bar)
  local healClipH = CreateFrame("Frame", nil, arcGroup)
  if healClipH.SetClipsChildren then healClipH:SetClipsChildren(true) end
  healClipH:Hide()
  bar.healClipH = healClipH
  bar.healTexH = healClipH:CreateTexture(nil, "ARTWORK")
  bar.healTexH:SetTexture(ns.Media.circle)

  -- Overlay sombre : masque le centre pour simuler un arc en anneau
  local overlayPx = OverlayPx(cfg, arcPx)
  local overlayFrame = CreateFrame("Frame", nil, bar)
  overlayFrame:SetFrameLevel(arc:GetFrameLevel() + 1)
  overlayFrame:SetAllPoints(bar)
  local overlay = overlayFrame:CreateTexture(nil, "ARTWORK")
  overlay:SetTexture(ns.Media.circle)
  if overlayPx >= 2 then overlay:SetSize(overlayPx, overlayPx) else overlay:Hide() end
  overlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  overlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.overlay = overlay
  bar.overlayFrame = overlayFrame

  -- Texte + dots sur un frame superieur a overlayFrame (sinon caches derriere l'overlay)
  local textFrame = CreateFrame("Frame", nil, bar)
  textFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  textFrame:SetAllPoints(bar)

  -- Coeur central (remplace les 5 dots) : au milieu, en bas du cercle hors combat.
  -- Reprend taille/position/couleur du dot central (index 3, le plus gros).
  local dot = textFrame:CreateTexture(nil, "OVERLAY")
  dot:SetTexture("Interface\\AddOns\\AishCore\\Media\\UI\\heart.tga")
  dot:SetSize(HEART_SIZE, HEART_SIZE)
  dot:SetPoint("BOTTOM", bar, "BOTTOM", cfg.dotPositions[3][1], cfg.dotPositions[3][2])
  dot:SetVertexColor(cfg.dotColors[3][1], cfg.dotColors[3][2], cfg.dotColors[3][3], 1)
  bar.dot3 = dot

  -- Cache sombre sous le texte, comme sur le cercle central (cf. bar.textBackdrop dans
  -- Modules/ResourceCircle.lua). Il vit dans textFrame, donc AU-DESSUS de overlayFrame :
  -- c'est ce qui fait passer les animations 3D en moyen plan derriere lui, puisque
  -- SpellEffects les pose a healthRingTextFrame:GetFrameLevel() - 1.
  local tbPx = math.max(1, cfg.textBackdropSize or TEXT_BACKDROP_DEFAULT)
  local textBackdrop = textFrame:CreateTexture(nil, "BACKGROUND")
  textBackdrop:SetTexture(ns.Media.circle)
  textBackdrop:SetSize(tbPx, tbPx)
  textBackdrop:SetPoint("CENTER", bar, "CENTER", 0, 0)
  textBackdrop:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.textBackdrop = textBackdrop

  -- Halo de reperage, allume par le slider du panneau (cf. HealthCircle.FlashTextBackdrop).
  bar.textBackdropGlow = ns.CreateTextBackdropGlow(textFrame, bar)
  ns.SizeTextBackdropGlow(bar.textBackdropGlow, tbPx)

  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(ns.Media.font, cfg.fontSize)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  local CLR0 = ns.Modules.Colors
  local tc0  = (CLR0 and CLR0.Get("oocdot")) or cfg.textColor
  text:SetTextColor(tc0[1], tc0[2], tc0[3], tc0[4] or 1)
  bar.text = text
  bar.textFrame = textFrame
  ns.healthRingTextFrame = textFrame

  bar:Hide()

  -- Zone de clic : bouton securise pose sur le cercle, jamais le cercle lui-meme. Seul un
  -- SecureUnitButton peut cibler et ouvrir le menu d'unite.
  -- PAS enfant de `bar` : un enfant securise rendrait le cercle protege, et ses Show/Hide
  -- seraient bloques en combat (ADDON_ACTION_BLOCKED). Calque sur UIParent, cale sur le
  -- cercle, dont la visibilite est recopiee hors combat (cf. SyncClickVisibility).
  local click = CreateFrame("Button", "AishCoreHealthRingClick", UIParent, "SecureUnitButtonTemplate")
  click:Hide()
  bar:HookScript("OnShow", SyncClickVisibility)
  bar:HookScript("OnHide", SyncClickVisibility)
  -- Le cercle vit en strata LOW : un bouton laisse a ce niveau se ferait voler ses clics
  -- par a peu pres n'importe quel element d'interface pose au-dessus.
  click:SetFrameStrata("MEDIUM")
  click:SetFrameLevel(bar:GetFrameLevel() + 8)
  click:RegisterForClicks("AnyUp")
  click:SetAttribute("unit", "player")
  click:SetAttribute("*type1", "target")      -- clic gauche = se cibler
  click:SetAttribute("*type2", "togglemenu")  -- clic droit  = menu contextuel du joueur
  click:EnableMouse(false)                    -- arme seulement si l'option est cochee
  bar.clickOverlay = click

  -- Pré-allouer la table d'éléments pour AnimateVisibility (5 slots fixes).
  -- Les frame-refs (bar.arc, etc.) sont stables après Create() : on ne les recrée jamais.
  do
    local si = 0.04
    _hcAnimElems[1] = { element = bar.bgLarge,      delay = 0      }
    _hcAnimElems[2] = { element = bar.text,         delay = si * 1 }
    _hcAnimElems[3] = { element = bar.arcGroup,     delay = si * 2 }
    _hcAnimElems[4] = { element = bar.overlayFrame, delay = si * 2 }
    _hcAnimElems[5] = { element = bar.dot3,         delay = si * 3 }
    -- Meme delai que le texte : le cache doit apparaitre et disparaitre avec lui,
    -- sinon on voit un disque noir seul au milieu du cercle pendant la transition.
    _hcAnimElems[6] = { element = bar.textBackdrop, delay = si * 1 }
  end

  ApplyArcAngles()
  return bar
end

-- Animation stagger
function HealthCircle.AnimateVisibility(shouldShow)
  if healthAnimTicker then
    healthAnimTicker:Cancel()
    healthAnimTicker = nil
  end
  if not bar then return end

  if not shouldShow then
    StopPulse()   -- arrêter le pouls avant le fade-out
  end

  -- Synchroniser les décorations OOC SpellEffects avec le cercle (même durée totale)
  local se = ns.Modules.SpellEffects
  if se and se.AnimateOocDeco then
    se.AnimateOocDeco(shouldShow, 0.35 + 0.04 * 5)  -- durée totale = duration + maxDelay du stagger
  end

  -- Table pré-allouée dans Create() : aucune allocation ici
  healthAnimTicker = ns.AnimateStagger(_hcAnimElems, shouldShow, 0.35, 0.04, function()
    if previewMode then
      hcAnimBusy = false
      return
    end
    if not shouldShow then
      bar:Hide()
    else
      StartPulse()  -- démarrer le pouls une fois le cercle pleinement visible
    end
    hcAnimBusy = false
    if hcAnimDirty then
      hcAnimDirty = false
      HealthCircle.UpdateVisibility()
    end
  end)
end

-- Mode preview : force l'affichage du cercle pour le settings panel
--- Allume le halo du fond de texte (appele par le slider du panneau).
function HealthCircle.FlashTextBackdrop()
  if bar then ns.FlashTextBackdropGlow(bar.textBackdropGlow) end
end

function HealthCircle.SetPreview(on)
  previewMode = on
  if not bar then return end
  -- Sortie du panneau : le halo n'a plus lieu d'etre.
  if not on and bar.textBackdropGlow then ns.HideTextBackdropGlow(bar.textBackdropGlow) end

  -- Annuler toute animation en cours (override manuel du panneau de reglages,
  -- pas une transition automatique -- interruption immediate voulue ici).
  if healthAnimTicker then healthAnimTicker:Cancel(); healthAnimTicker = nil end
  hcAnimBusy = false
  hcAnimDirty = false
  StopPulse()   -- arrêter le pouls quand on entre/sort du mode preview
  StopPreviewAnim()

  if on then
    lastHealthVisState = nil
    -- Respecter le toggle : ne pas forcer l'affichage si desactive. Masquage
    -- explicite (pas un simple return) : previewMode court-circuite
    -- UpdateVisibility, donc rien d'autre ne cacherait le cercle si le module
    -- vient d'etre coupe depuis la page "Modules" panneau ouvert.
    local cfgPrev = ns.GetCfg("healthCircle")
    if cfgPrev.enabled == false then
      bar:Hide()
      bar._healthShown = false
      return
    end
    -- Forcer l'affichage de tous les elements
    bar:Show()
    bar:SetAlpha(1)
    bar:SetScale(1)
    local elements = { bar.bgLarge, bar.text, bar.arcGroup, bar.dot3, bar.textBackdrop }
    for _, el in ipairs(elements) do
      if el then
        el:Show()
        el:SetAlpha(1)
        if el.SetScale then el:SetScale(1) end
      end
    end
    if bar.overlay then bar.overlay:Show(); bar.overlay:SetAlpha(1) end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    bar._healthShown = true
    -- Valeur fictive pour visualiser
    ApplyArcValue(72)
    bar.text:SetText("72")
    previewTicker = ns.NewTicker(0.03, function()
      if not (bar and previewMode and bar:IsShown()) then return StopPreviewAnim() end
      previewPct = PreviewSweep()
      ApplyArcValue(previewPct)
      bar.text:SetText(tostring(previewPct))
    end)
  else
    lastHealthVisState = nil
    bar._healthShown = false
    HealthCircle.Update()
    HealthCircle.UpdateVisibility()
  end
end

--- Arme ou desarme la zone de clic. EnableMouse est protege sur un frame securise : en
--- combat on note la demande et PLAYER_REGEN_ENABLED la rejoue.
--- `force` = false desarme quoi qu'en dise la config (mode deplacement : sinon le calque
--- mange le drag du cercle).
function HealthCircle.ApplyClickable(force)
  if not (bar and bar.clickOverlay) then return end
  local want = force
  if want == nil then
    local cfg = ns.GetCfg("healthCircle")
    want = (cfg and cfg.clickable == true) or false
  end
  if InCombatLockdown() then
    hcClickPending = true
    hcClickWanted  = want
    return
  end
  hcClickPending = false
  bar.clickOverlay:EnableMouse(want and true or false)
  SyncClickVisibility()  -- recale le bouton (position/taille changees par ApplySettings ou un drag)
end

-- Rend le cercle deplacable par drag (pour le mode settings)
function HealthCircle.SetDraggable(on)
  if not bar then return end
  hcDragArmed = (on == true)
  -- Le calque de clic capterait le glisser : on le desarme tant que le panneau est ouvert.
  if hcDragArmed then HealthCircle.ApplyClickable(false) else HealthCircle.ApplyClickable() end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
      -- Verrou relu A CHAUD : le drag est arme des l'ouverture du panneau (plus de bouton dedie),
      -- donc la case "Verrouiller la position" est le seul frein -- meme modele que unitBars.
      local c = ns.GetCfg("healthCircle")
      if c and c.locked then return end
      self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      -- Calculer la position en pourcentage depuis BOTTOMLEFT
      local cx, cy = self:GetCenter()
      local sw = UIParent:GetWidth()
      local sh = UIParent:GetHeight()
      local newPctX = cx / sw
      local newPctY = cy / sh
      -- Sauvegarder en DB (pct pur, x/y = 0)
      if not ns.DB then ns.DB = {} end
      if not ns.DB.healthCircle then ns.DB.healthCircle = {} end
      ns.DB.healthCircle.anchorPctX = newPctX
      ns.DB.healthCircle.anchorPctY = newPctY
      ns.DB.healthCircle.x = 0
      ns.DB.healthCircle.y = 0
      -- Repositionner proprement
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw * newPctX, sh * newPctY)
      self._pulseAnchorX = sw * newPctX
      self._pulseAnchorY = sh * newPctY
    end)
    -- Bordure visuelle "deplacable"
    if not bar._dragBorder then
      local border = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      border:SetAllPoints(bar)
      border:SetColorTexture(1, 1, 1, 0.15)
      bar._dragBorder = border
    end
    -- Bordure affichee seulement au survol (un cadre permanent autour du cercle, panneau ouvert, etait
    -- tres visible), et seulement si le deplacement est reellement possible : la montrer sur un
    -- element verrouille laisserait croire qu'il est saisissable.
    bar._dragBorder:Hide()
    -- Tooltip au survol
    bar:SetScript("OnEnter", function(self)
      local c = ns.GetCfg("healthCircle")
      if not (c and c.locked) then self._dragBorder:Show() end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["RESOURCE_DRAG_TOOLTIP"])
      GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function(self)
      self._dragBorder:Hide()
      GameTooltip:Hide()
    end)
  else
    bar:SetMovable(false)
    bar:EnableMouse(false)
    bar:RegisterForDrag()
    bar:SetScript("OnDragStart", nil)
    bar:SetScript("OnDragStop", nil)
    bar:SetScript("OnEnter", nil)
    bar:SetScript("OnLeave", nil)
    if bar._dragBorder then bar._dragBorder:Hide() end
  end
end

-- Met à jour la visibilité
function HealthCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = HealthCircle.ShouldShow()
  if lastHealthVisState == shouldShow then return end

  if hcAnimBusy then
    hcAnimDirty = true
    return
  end
  lastHealthVisState = shouldShow
  hcAnimBusy = true

  if shouldShow then
    bar:Show()
    bar.arcGroup:Show()
    if bar.overlay then bar.overlay:Show() end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    bar.bgLarge:Show()
    bar.text:Show()
    if bar.textBackdrop then bar.textBackdrop:Show() end
    if bar.dot3 then bar.dot3:Show() end
    if not bar._healthShown then
      bar._healthShown = true
      HealthCircle.AnimateVisibility(true)
    else
      -- Deja affiche, aucune anim ne sera lancee : remettre le verrou a plat ici pour ne pas bloquer les futures demandes
      hcAnimBusy = false
    end
  else
    bar._healthShown = false
    HealthCircle.AnimateVisibility(false)
  end
end

-- Soins previsionnels sur l'arc.
-- Soins previsionnels sur l'arc. Meme principe que les barres d'unites : aucune valeur
-- n'est lue ni calculee -- l'arithmetique est refusee sur les valeurs secretes. C'est
-- l'ANCRAGE qui additionne (cf. arcHeal / healClip dans HealthCircle.Create).
local function UpdateHealPrediction(predPct)
  local arcHeal, healTex = bar and bar.arcHeal, bar and bar.healTex
  if not (arcHeal and healTex) then return end
  local cfg = ns.GetCfg("healthCircle")
  local mode = cfg.arcFillMode or "vertical"
  if cfg.arcFillInverted == true then mode = FILL_INVERSE[mode] or mode end
  local radial = (mode ~= "vertical")
  local on = cfg.showHealPrediction ~= false

  -- Modes radiaux : prevision hybride, la bande verticale (healClip, sous les arcs) sert aussi ici.
  bar.harc:Hide(); bar.harc2:Hide()
  if bar.iarc then bar.iarc:Hide(); bar.iarc2:Hide() end
  ns._hcPredDbg = { mode = radial and "hybride (bande verticale)" or "vertical" }

  if not on then
    arcHeal:SetValue(0)
    return
  end

  local hc = cfg.healPredColor or { 0.45, 1, 0.55, 1 }
  healTex:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 1)
  if bar.healTexH then bar.healTexH:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 1) end

  EnsureHealCalc()
  if hpCalc and UnitGetDetailedHealPrediction then
    local ok = pcall(function()
      UnitGetDetailedHealPrediction("player", "player", hpCalc)
      local inc = (hpCalc:GetIncomingHeals())
      arcHeal:SetMinMaxValues(0, hpCalc:GetMaximumHealth())
      arcHeal:SetValue(inc)
      -- Opacite = soins entrants (valeur secrete acceptee, bornee a 1) : 0 sans soin en cours, 1 des qu'un soin
      -- arrive. La regen et le leger decalage de lissage entre regle et arc ne montrent donc plus de vert.
      if radial and bar.healClip then pcall(bar.healClip.SetAlpha, bar.healClip, inc) end
      if bar.arcHealH then
        bar.arcHealH:SetMinMaxValues(0, hpCalc:GetMaximumHealth())
        bar.arcHealH:SetValue(inc)
        pcall(bar.healClipH.SetAlpha, bar.healClipH, inc)
      end
    end)
    if ok then return end
  end

  -- Repli Classic : meme principe, sans calculateur.
  if not pcall(function()
    arcHeal:SetMinMaxValues(0, UnitHealthMax("player"))
    arcHeal:SetValue(UnitGetIncomingHeals and (UnitGetIncomingHeals("player") or 0) or 0)
  end) then
    arcHeal:SetValue(0)
  end
end

-- Met à jour les valeurs
function HealthCircle.Update()
  if not bar or not bar.text then return end
  if previewMode then return end
  if not bar:IsShown() then return end  -- skip si le cercle de vie n'est pas affiche
  local cfg = ns.GetCfg("healthCircle")

  -- Vie seule pour l'arc et le texte ; vie + soins entrants (prevision) pour les arcs de soins radiaux
  local pct = UnitHealthPercent("player", false, CurveConstants.ScaleTo100)
  local okP, predPct = pcall(UnitHealthPercent, "player", true, CurveConstants.ScaleTo100)
  if not okP then predPct = nil end
  if not pct then
    if bar.arcHeal then bar.arcHeal:SetValue(0) end
    for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV, bar.harc, bar.harc2, bar.iarc, bar.iarc2 }) do a:SetValue(0) end
    bar.text:SetText("-")
    return
  end

  local CLR2  = ns.Modules.Colors
  local arcC2 = (CLR2 and CLR2.Get("oochealth")) or cfg.barColor
  local txtC2 = (CLR2 and CLR2.Get("oocdot"))    or cfg.textColor
  for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV }) do
    a:SetStatusBarColor(arcC2[1], arcC2[2], arcC2[3], arcC2[4] or 1)
  end
  PaintRuler()
  bar.text:SetTextColor(txtC2[1], txtC2[2], txtC2[3], txtC2[4] or 1)

  ApplyArcValue(pct)
  if bar._hCurve then
    local okC, hv = pcall(UnitHealthPercent, "player", false, bar._hCurve)
    if okC and type(hv) ~= "nil" then pcall(ns.SmoothBarValue, bar._hRulerBar or bar.arcV, hv) end
  end
  UpdateHealPrediction(predPct)
  bar.text:SetText(format('%d', pct))
  -- UpdateVisibility est maintenant appelé par le ticker avant Update().
  -- On ne l'appelle plus ici pour éviter un double appel.
end

-- Reset
function HealthCircle.ResetVisibility()
  lastHealthVisState = nil
end

-- /aishhp : diagnostic des soins previsionnels du cercle de vie (a lancer pendant qu'un soin est en cours d'incantation sur soi)
SLASH_AISHHP1 = "/aishhp"
SlashCmdList["AISHHP"] = function(msg)
  local P = "|cff33ff99[AishCore soins]|r "
  -- "/aishhp rot" : une rotation de texture accepte-t-elle une valeur secrete ? (piste pour la prevision en arc)
  if msg == "rot" then
    local okV, sv = pcall(UnitHealthPercent, "player", false, CurveConstants.ZeroToOne or CurveConstants.ScaleTo100)
    print(P .. "valeur de test secrete=" .. tostring(okV and issecretvalue and issecretvalue(sv)))
    local f = CreateFrame("Frame")
    local t = f:CreateTexture()
    local okR, errR = pcall(t.SetRotation, t, sv)
    print(P .. "Texture:SetRotation(secret) -> " .. (okR and "ACCEPTE" or ("refuse : " .. tostring(errR))))
    local okC = C_CurveUtil and C_CurveUtil.CreateCurve
    print(P .. "C_CurveUtil.CreateCurve -> " .. (okC and "present" or "absent"))
    if okC and hpCalc and hpCalc.EvaluateCurrentHealthPercent then
      local okE = pcall(function()
        local c = C_CurveUtil.CreateCurve()
        c:AddPoint(0, 0); c:AddPoint(1, 6.28)
        local r = hpCalc:EvaluateCurrentHealthPercent(c)
        t:SetRotation(r)
      end)
      print(P .. "rotation via courbe du calculateur -> " .. (okE and "ACCEPTE" or "refuse"))
    end
    return
  end
  local function S(x)
    if issecretvalue and issecretvalue(x) then return "<secret>" end
    return tostring(x)
  end
  local cfg = ns.GetCfg("healthCircle") or {}
  print(P .. "mode=" .. tostring(cfg.arcFillMode) .. " inverse=" .. tostring(cfg.arcFillInverted)
    .. " affiche=" .. tostring(cfg.showHealPrediction ~= false) .. " previewMode=" .. tostring(previewMode))
  local okA, a = pcall(UnitHealthPercent, "player", false, CurveConstants.ScaleTo100)
  local okB, b = pcall(UnitHealthPercent, "player", true, CurveConstants.ScaleTo100)
  print(P .. "UnitHealthPercent sans prevision=" .. (okA and S(a) or "erreur") .. " avec prevision=" .. (okB and S(b) or "erreur"))
  print(P .. "UnitGetIncomingHeals=" .. (UnitGetIncomingHeals and S(select(2, pcall(UnitGetIncomingHeals, "player"))) or "absente"))
  EnsureHealCalc()
  if hpCalc and UnitGetDetailedHealPrediction then
    pcall(UnitGetDetailedHealPrediction, "player", "player", hpCalc)
    local function G(m) local ok, r = pcall(hpCalc[m], hpCalc); return ok and S(r) or "erreur" end
    print(P .. "calculateur : vie=" .. G("GetCurrentHealth") .. " soins=" .. G("GetIncomingHeals") .. " max=" .. G("GetMaximumHealth"))
  else
    print(P .. "calculateur absent")
  end
  -- Modes et methodes du calculateur : cherche un moyen natif d'obtenir (vie + soins entrants) sans calcul
  for _, en in ipairs({ "UnitMaximumHealthMode", "UnitIncomingHealClampMode", "UnitDamageAbsorbClampMode", "UnitHealAbsorbMode", "UnitHealAbsorbClampMode" }) do
    local t = Enum and Enum[en]
    if t then
      local ks = {}
      for k, v in pairs(t) do ks[#ks + 1] = k .. "=" .. tostring(v) end
      table.sort(ks)
      print(P .. en .. " : " .. table.concat(ks, ", "))
    end
  end
  if hpCalc then
    local mt = getmetatable(hpCalc)
    local idx = mt and mt.__index
    local ms = {}
    if type(idx) == "table" then for k in pairs(idx) do ms[#ms + 1] = k end end
    table.sort(ms)
    print(P .. "methodes : " .. table.concat(ms, ", "))
  end
  local d = ns._hcPredDbg
  print(P .. "methode de l'arc de soins=" .. (d and tostring(d.mode) or "jamais"))
  if bar and bar.harc then
    print(P .. string.format("arc de soins : shown=%s visible=%s niveau=%s | arc de vie niveau=%s",
      tostring(bar.harc:IsShown()), tostring(bar.harc:IsVisible()), tostring(bar.harc:GetFrameLevel()),
      tostring(bar.arc and bar.arc:GetFrameLevel())))
  end
end

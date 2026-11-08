-- Modules/TaxiMode.lua : "Mode Taxi" -- pendant un vol (maitre de vol), deux bandes noires facon cinema et, dans la
-- bande du bas, la route : depart a gauche, destination a droite, etapes intermediaires (cercles) avec leur heure
-- d'arrivee estimee, et un losange qui suit le personnage avec le temps ecoule.
--
-- Route : capturee au clic sur la carte des vols (hook de TakeTaxiNode : GetNumRoutes / TaxiGetNodeSlot).
-- Durees : apprises vol apres vol (AishaddonDB.taxiTimes, par troncon, commun au compte), sinon estimees a partir de
-- la distance a vol d'oiseau et d'une vitesse moyenne elle aussi apprise (AishaddonDB.taxiSpeed).
-- Passage d'une etape : detecte par la position du joueur sur la carte des vols (repli : au temps estime).
-- "Arret ici" : TaxiRequestEarlyLanding() pose a l'etape SUIVANTE ; pour une etape plus lointaine, la demande est
-- differee jusqu'au passage de l'etape qui la precede.
-- Interface : UIParent rendu transparent (toujours cliquable) ; l'element survole (chat, minimap, barres...)
-- reapparait le temps du survol, et une fenetre ouverte (sacs, personnage...) reste visible tant qu'elle l'est
-- (SetIgnoreParentAlpha sur son cadre de plus haut niveau).
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local TaxiMode = {}
ns.Modules.TaxiMode = TaxiMode

local GetTime, floor, max, min, sqrt, format = GetTime, math.floor, math.max, math.min, math.sqrt, string.format

local CIRCLE_TEX = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local GLOW_TEX   = "Interface\\AddOns\\AishCore\\Media\\UI\\SpotGlow.tga"
local WHITE      = "Interface\\Buttons\\WHITE8x8"

local DEFAULT_SPEED = 24     -- verges/s a vol d'oiseau (trajet reel plus long que la ligne droite)
local DEFAULT_HOP   = 60     -- secondes, troncon sans position connue
local ANIM_TIME     = 0.45   -- entree / sortie des bandes et fondu de l'interface
local REVEAL_GRACE  = 0.6    -- un element survole reste visible ce temps apres le depart de la souris
local UI_FADE       = 1.6    -- fondu de l'interface au decollage / a l'atterrissage
local FADE_IN       = 0.35   -- un element qui reapparait
local FADE_OUT      = 1.4    -- un element qui redevient transparent
local CHAT_REVEAL   = 8      -- une nouvelle ligne de chat le montre ce temps

local CAN_STOP = type(TaxiRequestEarlyLanding) == "function"

local function Cfg() return ns.GetCfg("taxiMode") or {} end

-- ═══ Stockage du compte ═══════════════════════════════════════════════════════════════════════════
local function Store()
  if type(AishaddonDB) ~= "table" then return nil end
  AishaddonDB.taxiTimes = AishaddonDB.taxiTimes or {}
  return AishaddonDB
end

local function Speed()
  local db = Store()
  local s = db and tonumber(db.taxiSpeed)
  return (s and s > 4) and s or DEFAULT_SPEED
end

local function HopKey(a, b) return tostring(a.id or a.name) .. ">" .. tostring(b.id or b.name) end

local function Dist(a, b)
  if not (a and b and a.wx and b.wx) then return nil end
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  return sqrt(dx * dx + dy * dy)
end

local function HopEstimate(a, b)
  local db = Store()
  local t = db and db.taxiTimes[HopKey(a, b)]
  if t then return t end
  local d = Dist(a, b)
  if d then return max(5, d / Speed()) end
  return DEFAULT_HOP
end

-- Troncon parcouru : duree retenue, vitesse moyenne ajustee
local function Learn(a, b, seconds)
  local db = Store()
  if not db or not seconds or seconds < 3 or seconds > 1800 then return end
  db.taxiTimes[HopKey(a, b)] = floor(seconds + 0.5)
  local d = Dist(a, b)
  if d and d > 50 then
    local s = d / seconds
    if s > 4 and s < 120 then db.taxiSpeed = Speed() * 0.7 + s * 0.3 end
  end
end

-- ═══ Capture de la route ═════════════════════════════════════════════════════════════════════════
-- "Ratchet, Les Tarides" -> nom + zone ; sans virgule, zone de la carte a cet endroit.
local function SplitName(full, mapID, x, y)
  full = full or "?"
  local name, zone = full:match("^(.-),%s*(.+)$")
  if not name then
    name = full
    if mapID and x and C_Map and C_Map.GetMapInfoAtPosition then
      local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
      if info and info.name and info.name ~= name then zone = info.name end
    end
  end
  return name, zone
end

local function CaptureRoute(destSlot)
  if not (GetNumRoutes and TaxiGetNodeSlot and TaxiNodeName) then return nil end
  local hops = GetNumRoutes(destSlot)
  if not hops or hops < 1 then return nil end
  local slots = { TaxiGetNodeSlot(destSlot, 1, true) }
  for h = 1, hops do slots[#slots + 1] = TaxiGetNodeSlot(destSlot, h, false) end

  local mapID = GetTaxiMapID and GetTaxiMapID()
  local byslot = {}
  if mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
    for _, n in ipairs(C_TaxiMap.GetAllTaxiNodes(mapID) or {}) do
      if n.slotIndex then byslot[n.slotIndex] = n end
    end
  end
  local w, h
  if mapID and C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
  if not (w and h and w > 0 and h > 0) then w, h = nil, nil end

  local nodes = {}
  for i, slot in ipairs(slots) do
    local info = byslot[slot]
    local x, y
    if info and info.position then x, y = info.position.x, info.position.y
    elseif TaxiNodePosition then x, y = TaxiNodePosition(slot) end
    local name, zone = SplitName((info and info.name) or TaxiNodeName(slot), mapID, x, y)
    nodes[i] = {
      id = info and info.nodeID, name = name, zone = zone, x = x, y = y,
      wx = (w and x) and x * w or nil, wy = (h and y) and y * h or nil,
    }
  end
  return { mapID = mapID, w = w, h = h, nodes = nodes }
end

-- ═══ Etat du vol ═════════════════════════════════════════════════════════════════════════════════
local pending        -- route capturee au clic, en attente du decollage
local flight         -- vol en cours : route + start, reached, times, est, stop, requested
local preview = false
local demo           -- vol fictif de l'apercu

local function Elapsed(f) return GetTime() - f.start end

-- Positions de l'axe : temps estimes cumules au decollage (figes : les cercles ne bougent pas)
local function BuildEstimates(f)
  local n = f.nodes
  f.hop, f.axis = {}, { 0 }
  for i = 1, #n - 1 do
    f.hop[i] = HopEstimate(n[i], n[i + 1])
    f.axis[i + 1] = f.axis[i] + f.hop[i]
  end
end

-- Heure d'arrivee (temps de vol) de chaque etape : reelle si passee, sinon estimee depuis la derniere passee
local function ETAs(f, el)
  local eta = {}
  for i = 1, f.reached do eta[i] = f.times[i] end
  local t = f.times[f.reached]
  for i = f.reached + 1, #f.nodes do
    t = t + f.hop[i - 1]
    if i == f.reached + 1 and t < el then t = el end
    eta[i] = t
  end
  return eta
end

local function SaveFlight()
  local db = Store()
  if not db then return end
  if flight and not flight.isDemo then
    db._taxiFlight = { route = flight.route, start = flight.start, reached = flight.reached, times = flight.times,
      stop = flight.stop, requested = flight.requested }
  else
    db._taxiFlight = nil
  end
end

local function NewFlight(route, start)
  local f = { route = route, nodes = route.nodes, start = start or GetTime(), reached = 1, times = { 0 } }
  BuildEstimates(f)
  return f
end

-- ═══ Affichage ═══════════════════════════════════════════════════════════════════════════════════
local root, topBand, bottomBand, track, lineDone, lineGlow, lineTodo, diamond, elapsedText
local startDot, endDot, startName, startZone, endName, endZone, endEta
local checkpoints = {}
local animP, animTarget = 0, 0

local function Accent()
  local cfg = Cfg()
  if cfg.useThemeColors then
    local CLR = ns.Modules and ns.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get("powertext")
    if c then return c end
  end
  return cfg.accentColor or { 1, 0.76, 0.25, 1 }
end

local function FontPath()
  local f = Cfg().font
  return (ns.SafeFontPath and ns.SafeFontPath(f or ns.FONT_FALLBACK)) or f or ns.FONT_FALLBACK
end

local function NewText(parent, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(ns.FONT_FALLBACK, 12, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
  return fs
end

local function StyleText(fs, size, c)
  if not fs:SetFont(FontPath(), max(6, floor(size + 0.5)), "") then fs:SetFont(ns.FONT_FALLBACK, max(6, floor(size + 0.5)), "") end
  if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

-- Cercle : halo, bague, remplissage, reflet
local function NewDot(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.glow = b:CreateTexture(nil, "BACKGROUND")
  b.glow:SetTexture(GLOW_TEX)
  b.glow:SetPoint("CENTER")
  b.glow:SetSize(size * 2.6, size * 2.6)
  b.glow:SetBlendMode("ADD")
  b.ring = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.ring:SetTexture(CIRCLE_TEX)
  b.ring:SetAllPoints()
  b.fill = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.fill:SetTexture(CIRCLE_TEX)
  b.fill:SetPoint("TOPLEFT", 2, -2)
  b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
  b.shine = b:CreateTexture(nil, "ARTWORK", nil, 3)
  b.shine:SetTexture(CIRCLE_TEX)
  b.shine:SetSize(size * 0.42, size * 0.42)
  b.shine:SetPoint("CENTER", -size * 0.12, size * 0.14)
  b.shine:SetVertexColor(1, 1, 1, 0.35)
  return b
end

local function Tint(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end

local RED      = { 0.9, 0.12, 0.1, 1 }
local RED_DARK = { 0.4, 0.04, 0.03, 1 }
local DIM_RING = { 0.42, 0.36, 0.28, 1 }
local DIM_FILL = { 0.2, 0.17, 0.13, 1 }
local GREY     = { 0.72, 0.72, 0.72, 1 }
local GREY_DIM = { 0.55, 0.55, 0.55, 1 }

-- state : "done" (passee), "todo", "stop" (survol / arret choisi)
local function PaintDot(b, state)
  local a = Accent()
  if state == "stop" then
    Tint(b.ring, RED_DARK); Tint(b.fill, RED); Tint(b.glow, RED, 0.55); b.glow:Show()
  elseif state == "done" then
    b.ring:SetVertexColor(a[1] * 0.55, a[2] * 0.55, a[3] * 0.55, 1); Tint(b.fill, a, 1)
    Tint(b.glow, a, 0.35); b.glow:Show()
  else
    Tint(b.ring, DIM_RING); Tint(b.fill, DIM_FILL); b.glow:Hide()
  end
end

local function FormatTime(s)
  s = max(0, floor(s + 0.5))
  return format("%d:%02d", floor(s / 60), s % 60)
end

-- Majuscules, accents compris (string.upper ignore les lettres accentuees UTF-8 : "Croisée" -> "CROISéE")
local function Upper(s)
  return (s or ""):upper():gsub("\195([\160-\190])", function(c)
    if c ~= "\183" then return "\195" .. string.char(c:byte() - 32) end   -- \183 : signe de division
  end)
end

local function Ease(v) v = min(1, max(0, v)); return v * v * (3 - 2 * v) end

local Refresh   -- forward

-- Etape intermediaire : clic = s'arreter ici (re-clic = annuler tant que la demande n'est pas partie)
local function RequestLanding()
  if not (flight and CAN_STOP) or flight.requested then return end
  flight.requested = true
  pcall(TaxiRequestEarlyLanding)
  SaveFlight()
end

local function OnCheckpointClick(self)
  local f = flight
  if not f or f.isDemo or not CAN_STOP then return end
  local i = self.index
  if i <= f.reached or f.requested then return end
  if f.stop == i then f.stop = nil
  else
    f.stop = i
    if i == f.reached + 1 then RequestLanding() end   -- prochaine etape : tout de suite
  end
  SaveFlight()
  PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
  Refresh(true)
end

local function CheckpointStoppable(cp)
  local f = flight or demo
  return f and CAN_STOP and cp.index > f.reached and not f.requested
end

local function NewCheckpoint()
  local cp = NewDot(track, 15)
  cp:SetFrameLevel(track:GetFrameLevel() + 3)
  cp:SetHitRectInsets(-8, -8, -18, -14)
  cp.name = NewText(cp)
  cp.name:SetPoint("BOTTOM", cp, "TOP", 0, 5)
  cp.eta = NewText(cp)
  cp.eta:SetPoint("TOP", cp, "BOTTOM", 0, -4)
  cp.stopText = NewText(cp)
  cp.stopText:SetPoint("LEFT", cp, "RIGHT", 4, 0)
  cp.stopText:SetJustifyH("LEFT")
  cp.stopText:SetText(L["TAXIMODE_STOP_HERE"])
  cp.stopText:Hide()
  cp:SetScript("OnEnter", function(self) self.hover = true; Refresh(true) end)
  cp:SetScript("OnLeave", function(self) self.hover = false; Refresh(true) end)
  cp:SetScript("OnClick", OnCheckpointClick)
  return cp
end

local function Build()
  if root then return end
  root = CreateFrame("Frame", "AishCoreTaxiMode", UIParent)
  root:SetAllPoints(UIParent)
  root:SetIgnoreParentAlpha(true)    -- reste visible quand l'interface est rendue transparente
  root:SetFrameStrata("BACKGROUND")  -- l'interface survolee s'affiche par-dessus les bandes
  root:Hide()

  topBand = root:CreateTexture(nil, "BACKGROUND")
  topBand:SetTexture(WHITE)
  bottomBand = root:CreateTexture(nil, "BACKGROUND")
  bottomBand:SetTexture(WHITE)

  -- L'axe passe au-dessus de l'interface transparente : ses etapes doivent rester survolables
  track = CreateFrame("Frame", nil, root)
  track:SetFrameStrata("HIGH")
  track:SetFixedFrameStrata(true)   -- ne suit pas la strate de root (BACKGROUND en vol)
  track:SetHeight(1)

  lineTodo = track:CreateTexture(nil, "ARTWORK", nil, 0)
  lineTodo:SetTexture(WHITE)
  lineTodo:SetHeight(1)
  lineTodo:SetPoint("LEFT"); lineTodo:SetPoint("RIGHT")
  lineTodo:SetVertexColor(0.6, 0.6, 0.6, 0.45)
  lineGlow = track:CreateTexture(nil, "ARTWORK", nil, 1)
  lineGlow:SetTexture(GLOW_TEX)
  lineGlow:SetBlendMode("ADD")
  lineGlow:SetHeight(16)
  lineDone = track:CreateTexture(nil, "ARTWORK", nil, 2)
  lineDone:SetTexture(WHITE)
  lineDone:SetHeight(3)

  startDot = NewDot(track, 19)
  startDot:EnableMouse(false)
  startDot:SetPoint("CENTER", track, "LEFT", 0, 0)
  endDot = NewDot(track, 19)
  endDot:EnableMouse(false)
  endDot:SetPoint("CENTER", track, "RIGHT", 0, 0)
  startDot:SetFrameLevel(track:GetFrameLevel() + 3)
  endDot:SetFrameLevel(track:GetFrameLevel() + 3)

  startName = NewText(startDot)
  startName:SetPoint("BOTTOMRIGHT", startDot, "LEFT", -12, -1)
  startZone = NewText(startDot)
  startZone:SetPoint("TOPLEFT", startName, "BOTTOMLEFT", 0, -2)
  endName = NewText(endDot)
  endName:SetPoint("BOTTOMLEFT", endDot, "RIGHT", 12, -1)
  endZone = NewText(endDot)
  endZone:SetPoint("TOPRIGHT", endName, "BOTTOMRIGHT", 0, -2)
  endEta = NewText(endDot)
  endEta:SetPoint("TOP", endDot, "BOTTOM", 0, -4)

  -- Filets sous les noms (degrade vers l'exterieur)
  local function Rule(anchorFs, left)
    local t = track:CreateTexture(nil, "ARTWORK")
    t:SetTexture(WHITE)
    t:SetHeight(1)
    if left then
      t:SetPoint("TOPRIGHT", anchorFs, "BOTTOMRIGHT", 0, -1)
      t:SetWidth(160)
    else
      t:SetPoint("TOPLEFT", anchorFs, "BOTTOMLEFT", 0, -1)
      t:SetWidth(160)
    end
    t.left = left
    return t
  end
  startDot.rule = Rule(startName, true)
  endDot.rule = Rule(endName, false)

  -- Losange : bordure doree, coeur bleu-vert, reflet
  diamond = CreateFrame("Frame", nil, track)
  diamond:SetSize(20, 20)
  diamond:SetFrameLevel(track:GetFrameLevel() + 6)
  local function Square(size, layer, sub)
    local t = diamond:CreateTexture(nil, layer, nil, sub)
    t:SetColorTexture(1, 1, 1, 1)   -- couleur unie : SetRotation tourne le carre lui-meme (cf. Campfire.lua)
    t:SetSize(size, size)
    t:SetPoint("CENTER")
    t:SetRotation(math.pi / 4)
    return t
  end
  diamond.glow = diamond:CreateTexture(nil, "BACKGROUND")
  diamond.glow:SetTexture(GLOW_TEX)
  diamond.glow:SetBlendMode("ADD")
  diamond.glow:SetSize(52, 52)
  diamond.glow:SetPoint("CENTER")
  diamond.glow:SetVertexColor(0.2, 0.75, 0.9, 0.5)
  diamond.border = Square(15, "ARTWORK", 1)
  diamond.dark   = Square(12, "ARTWORK", 2)
  diamond.dark:SetVertexColor(0.04, 0.16, 0.2, 1)
  diamond.core   = Square(10, "ARTWORK", 3)
  diamond.core:SetVertexColor(0.13, 0.58, 0.68, 1)
  diamond.shine  = Square(4, "ARTWORK", 4)
  diamond.shine:ClearAllPoints()
  diamond.shine:SetPoint("CENTER", 0, 2.5)
  diamond.shine:SetVertexColor(0.75, 1, 1, 0.8)

  elapsedText = NewText(diamond)
  elapsedText:SetPoint("TOPRIGHT", diamond, "BOTTOMLEFT", 6, 1)
end

-- Mise en page (taille ecran, bandes, police, etapes)
local function Layout()
  local cfg, f = Cfg(), flight or demo
  if not (root and f) then return end
  local W = UIParent:GetWidth()
  local topH, botH = cfg.panelTopHeight or 60, cfg.panelBottomHeight or 90
  local bg = cfg.panelBgColor or { 0, 0, 0, 0.92 }
  topBand:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
  bottomBand:SetVertexColor(bg[1], bg[2], bg[3], bg[4] or 1)
  topBand:SetHeight(max(0.001, topH)); topBand:SetShown(topH > 0)
  bottomBand:SetHeight(botH)
  topBand:SetWidth(W); bottomBand:SetWidth(W)

  local tw = W * min(0.9, max(0.2, cfg.width or 0.5))
  track:SetWidth(tw)

  local S = cfg.fontSize or 18
  local a = Accent()
  local n = f.nodes
  StyleText(startName, S, a); startName:SetText(Upper(n[1].name))
  StyleText(endName, S, a);   endName:SetText(Upper(n[#n].name))
  StyleText(startZone, S * 0.66, GREY); startZone:SetText(n[1].zone or "")
  StyleText(endZone, S * 0.66, GREY);   endZone:SetText(n[#n].zone or "")
  StyleText(endEta, S * 0.56, GREY_DIM)
  StyleText(elapsedText, S * 0.78, a)
  for _, d in ipairs({ startDot, endDot }) do
    local r = d.rule
    if r.SetGradient and CreateColor then
      local c0, c1 = CreateColor(a[1], a[2], a[3], 0), CreateColor(a[1], a[2], a[3], 0.35)
      if r.left then r:SetGradient("HORIZONTAL", c0, c1) else r:SetGradient("HORIZONTAL", c1, c0) end
    else
      r:SetVertexColor(a[1], a[2], a[3], 0.25)
    end
  end
  lineDone:SetVertexColor(a[1], a[2], a[3], 1)
  lineGlow:SetVertexColor(a[1], a[2], a[3], 0.55)
  diamond.border:SetVertexColor(a[1], a[2], a[3], 1)

  -- Etapes intermediaires, placees au prorata des temps estimes
  local total = f.axis[#n]
  for i = 2, #n - 1 do
    local cp = checkpoints[i - 1] or NewCheckpoint()
    checkpoints[i - 1] = cp
    cp.index = i
    cp:ClearAllPoints()
    cp:SetPoint("CENTER", track, "LEFT", total > 0 and tw * f.axis[i] / total or tw * (i - 1) / (#n - 1), 0)
    StyleText(cp.name, S * 0.62, GREY); cp.name:SetText(n[i].name or "")
    StyleText(cp.eta, S * 0.56, GREY_DIM)
    StyleText(cp.stopText, S * 0.48, RED)
    cp:Show()
  end
  for j = #n - 1, #checkpoints do checkpoints[j]:Hide() end
end

-- Rafraichissement (losange : chaque image ; textes : 4x/s ou force)
local textClock = 0
function Refresh(force)
  local f = flight or demo
  if not (root and f) then return end
  local el = Elapsed(f)
  local n = f.nodes
  local eta = ETAs(f, el)
  local tw = track:GetWidth()
  local total = f.axis[#n]
  local function X(i) return total > 0 and tw * f.axis[i] / total or tw * (i - 1) / (#n - 1) end

  -- Losange : interpolation dans le troncon en cours
  local k = min(f.reached, #n - 1)
  local t0, t1 = f.times[k] or 0, eta[k + 1] or el
  local frac = (t1 > t0) and (el - t0) / (t1 - t0) or 1
  frac = min(0.97, max(0, frac))
  if f.reached >= #n then frac = 1 end
  local x = X(k) + (X(k + 1) - X(k)) * frac
  diamond:ClearAllPoints()
  diamond:SetPoint("CENTER", track, "LEFT", x, 0)
  lineDone:ClearAllPoints()
  lineDone:SetPoint("LEFT", track, "LEFT", 0, 0)
  lineDone:SetWidth(max(0.001, x))
  lineGlow:ClearAllPoints()
  lineGlow:SetPoint("LEFT", track, "LEFT", -6, 0)
  lineGlow:SetWidth(max(0.001, x + 6))

  textClock = textClock + 1
  if not force and textClock % 15 ~= 0 then return end

  elapsedText:SetText(FormatTime(el))
  PaintDot(startDot, "done")
  local stopIdx = f.stop
  PaintDot(endDot, (f.reached >= #n) and "done" or "todo")
  endEta:SetText(FormatTime(eta[#n]))
  local beyond = stopIdx and #n > stopIdx
  endDot:SetAlpha(beyond and 0.35 or 1)
  endName:SetAlpha(beyond and 0.5 or 1)
  for _, cp in ipairs(checkpoints) do
    if cp:IsShown() then
      local i = cp.index
      local selected = (stopIdx == i)
      local hot = selected or (cp.hover and CheckpointStoppable(cp))
      PaintDot(cp, hot and "stop" or (i <= f.reached and "done" or "todo"))
      cp.stopText:SetShown(hot and CAN_STOP)
      cp.eta:SetText(FormatTime(eta[i]))
      cp:SetAlpha((stopIdx and i > stopIdx) and 0.35 or 1)
    end
  end
end

-- ═══ Interface transparente ═══════════════════════════════════════════════════════════════════════
-- Un cadre de plus haut niveau (enfant direct d'UIParent) ignore l'alpha d'UIParent, donc reste visible :
--   - le temps du survol (+ REVEAL_GRACE) ;
--   - tant qu'une fenetre qu'il porte est ouverte (sacs, personnage, popups, fenetres fermables par Echap...).
local uiHidden, uiAlpha, uiSavedAlpha = false, 1, 1
local hoverUntil = {}    -- [cadre] = fin de grace du survol
local panels = {}        -- [cadre] = true : porte une fenetre ouverte (recalcule a chaque passage)
local tooltipIgnored

local function TopLevel(f)
  local guard = 0
  while f and guard < 40 do
    if f.IsForbidden and f:IsForbidden() then return nil end
    local p = f:GetParent()
    if p == UIParent then return f end
    if p == nil then return nil end
    f, guard = p, guard + 1
  end
end

local function Hover(f, now, dur)
  local top = f and TopLevel(f)
  if top and top ~= root then hoverUntil[top] = max(hoverUntil[top] or 0, now + (dur or REVEAL_GRACE)) end
end

-- Fenetres ouvertes : panneaux Blizzard (UIPanelWindows), fenetres fermables par Echap (UISpecialFrames, y compris
-- celles des addons de sacs), sacs Blizzard, popups, butin, anciens menus deroulants.
local EXTRA_PANELS = { "ContainerFrameCombinedBags", "LootFrame", "GroupLootContainer", "StaticPopup1", "StaticPopup2",
  "StaticPopup3", "StaticPopup4", "DropDownList1", "DropDownList2", "DropDownList3" }
for i = 1, 13 do EXTRA_PANELS[#EXTRA_PANELS + 1] = "ContainerFrame" .. i end

local function AddPanel(name)
  local f = type(name) == "string" and _G[name]
  if type(f) ~= "table" or not f.IsShown or not f:IsShown() then return end
  local top = TopLevel(f)
  if top and top ~= root then panels[top] = true end
end

local function ScanPanels()
  wipe(panels)
  if UIPanelWindows then for name in pairs(UIPanelWindows) do pcall(AddPanel, name) end end
  if UISpecialFrames then for _, name in ipairs(UISpecialFrames) do pcall(AddPanel, name) end end
  for _, name in ipairs(EXTRA_PANELS) do pcall(AddPanel, name) end
end

-- Fondu par cadre : ignore l'alpha d'UIParent et porte lui-meme l'opacite (alpha d'origine x avancement).
-- L'alpha d'origine est relu au debut de chaque disparition et rendu a la fin : un cadre qui gere son propre alpha
-- (barres en fondu, chat...) le retrouve tel quel ; une fois apparu, on ne le touche plus.
local fades = {}   -- [cadre] = { a = 0..1, base = alpha d'origine, want = bool, busy = bool }

local function Want(fr, want, instant)
  local s = fades[fr]
  if want then
    if not s and instant then
      -- Fenetre ouverte : affichee telle quelle, sans toucher a son alpha (elle peut gerer son propre fondu
      -- d'ouverture, comme le GUI d'AishCore)
      if fr.IsIgnoringParentAlpha and fr:IsIgnoringParentAlpha() then return end
      if InCombatLockdown() and fr:IsProtected() then return end
      if not pcall(fr.SetIgnoreParentAlpha, fr, true) then return end
      fades[fr] = { a = 1, want = true, busy = false }
    elseif not s then
      if fr.IsIgnoringParentAlpha and fr:IsIgnoringParentAlpha() then return end   -- deja visible (autre addon)
      if InCombatLockdown() and fr:IsProtected() then return end
      local base = fr:GetAlpha()
      local start = uiSavedAlpha > 0 and uiAlpha / uiSavedAlpha or 0   -- part de l'opacite affichee
      if not pcall(fr.SetIgnoreParentAlpha, fr, true) then return end
      fr:SetAlpha(base * start)
      fades[fr] = { a = start, base = base, want = true, busy = true }
    elseif not s.want then
      s.want, s.busy = true, true
    end
  elseif s and s.want then
    if not fr:IsShown() then   -- fenetre fermee : rien a fondre
      if s.busy and s.base then fr:SetAlpha(s.base) end
      pcall(fr.SetIgnoreParentAlpha, fr, false)
      fades[fr] = nil
      return
    end
    if not s.busy then s.base = fr:GetAlpha() end   -- alpha courant du cadre, a rendre en fin de fondu
    s.want, s.busy = false, true
  end
end

local function StepFades(el)
  for fr, s in pairs(fades) do
    if s.busy then
      if s.want then
        s.a = min(1, s.a + el / FADE_IN)
        fr:SetAlpha(s.base * s.a)
        if s.a >= 1 then s.busy = false end
      else
        s.a = max(0, s.a - el / FADE_OUT)
        fr:SetAlpha(s.base * s.a)
        if s.a <= 0 then
          fr:SetAlpha(s.base)
          pcall(fr.SetIgnoreParentAlpha, fr, false)
          fades[fr] = nil
        end
      end
    end
  end
end

local function ClearReveals()
  for fr, s in pairs(fades) do
    fr:SetAlpha(s.busy and s.base or fr:GetAlpha())
    pcall(fr.SetIgnoreParentAlpha, fr, false)
  end
  wipe(fades); wipe(hoverUntil); wipe(panels)
end

-- Minimap : fleche du joueur, points et noeuds de vol ignorent l'alpha. La minimap est donc masquee quand son
-- opacite affichee tombe sous MM_MIN, et rendue au-dessus.
local MM_MIN = 0.25
local mmHidden = false

local function CursorOver(fr)
  local l, b, w, h = fr:GetRect()
  if not l then return false end
  local x, y = GetCursorPosition()
  local sc = fr:GetEffectiveScale()
  x, y = x / sc, y / sc
  return x >= l and x <= l + w and y >= b and y <= b + h
end

local function SyncMinimap()
  if not Minimap or (InCombatLockdown() and Minimap:IsProtected()) then return end
  local hide = (uiHidden or uiAlpha < uiSavedAlpha) and Minimap:GetEffectiveAlpha() < MM_MIN
  if hide then
    -- Reaffirme a chaque image : un addon de minimap (EllesmereUI, survol...) peut la reafficher
    if Minimap:IsShown() and pcall(Minimap.Hide, Minimap) then mmHidden = true end
  elseif not hide and mmHidden then
    mmHidden = false
    pcall(Minimap.Show, Minimap)
    -- Carte restee masquee pendant le vol : son rendu peut rester fige sur l'ancienne zone. Un aller-retour
    -- de zoom force le moteur a le refaire (maintenant et juste apres, le temps que le cadre soit affiche).
    local function Redraw()
      if not (Minimap.GetZoom and Minimap.SetZoom) then return end
      local z = Minimap:GetZoom()
      local levels = Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6
      pcall(Minimap.SetZoom, Minimap, z > 0 and z - 1 or min(z + 1, levels - 1))
      pcall(Minimap.SetZoom, Minimap, z)
    end
    Redraw()
    C_Timer.After(0.2, Redraw)
  end
end

-- Nouvelle ligne dans une fenetre de chat affichee : montree CHAT_REVEAL secondes
local chatHooked
local function OnChatLine(cf)
  if uiHidden and cf:IsShown() then pcall(Hover, cf, GetTime(), CHAT_REVEAL) end
end
local function HookChat()
  if chatHooked then return end
  chatHooked = true
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and cf.AddMessage then hooksecurefunc(cf, "AddMessage", OnChatLine) end
  end
  -- Chattynator : fenetres a lui (les ChatFrame de Blizzard sont masquees), toutes portees par son
  -- HyperlinkHandler. Un modificateur est appele pour chaque ligne preparee a l'affichage.
  local API = Chattynator and Chattynator.API
  if API and API.AddModifier and API.GetHyperlinkHandler then
    pcall(API.AddModifier, function()
      if not uiHidden then return end
      local h = API.GetHyperlinkHandler()
      if h then pcall(Hover, h, GetTime(), CHAT_REVEAL) end
    end)
  end
end

local revealClock = 0
local function UpdateReveal(el)
  StepFades(el)
  revealClock = revealClock + el
  if revealClock < 0.1 then return end
  revealClock = 0
  local now = GetTime()
  if Cfg().revealOnHover ~= false then
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    for _, f in ipairs(foci or {}) do pcall(Hover, f, now) end
    local kb = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()   -- saisie dans le chat
    if kb then pcall(Hover, kb, now) end
    if mmHidden and CursorOver(Minimap) then pcall(Hover, Minimap, now) end   -- minimap masquee : plus de souris
  end
  ScanPanels()
  for fr, t in pairs(hoverUntil) do
    if now > t then hoverUntil[fr] = nil end
  end
  for fr in pairs(fades) do
    if not (panels[fr] or hoverUntil[fr]) then Want(fr, false) end
  end
  for fr in pairs(panels) do Want(fr, true, true) end
  for fr in pairs(hoverUntil) do Want(fr, true) end
end

local function SetUIHidden(on)
  if on == uiHidden then return end
  uiHidden = on
  if on then
    if uiAlpha >= uiSavedAlpha then   -- sinon : retour d'un vol precedent encore en cours, on repart de la
      uiSavedAlpha = UIParent:GetAlpha()
      if uiSavedAlpha < 0.05 then uiSavedAlpha = 1 end
      uiAlpha = uiSavedAlpha
    end
    if GameTooltip and not GameTooltip:IsIgnoringParentAlpha() then
      GameTooltip:SetIgnoreParentAlpha(true); tooltipIgnored = true
    end
    revealClock = 1   -- fenetres deja ouvertes : visibles des la premiere image
    HookChat()
  else
    -- Atterrissage : les elements visibles le restent, l'interface remonte autour d'eux ; ils rendent l'alpha
    -- d'UIParent une fois celle-ci revenue (cf. OnUpdate)
    for _, st in pairs(fades) do if not st.want then st.want, st.busy = true, true end end
    if tooltipIgnored then GameTooltip:SetIgnoreParentAlpha(false); tooltipIgnored = nil end
  end
end

-- ═══ Boucle ═══════════════════════════════════════════════════════════════════════════════════════
local driver = CreateFrame("Frame")
local posClock = 0

local function PlayerYards(f)
  local r = f.route
  if not (r.mapID and r.w and C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local pos = C_Map.GetPlayerMapPosition(r.mapID, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  if not (x and y) or (x == 0 and y == 0) then return nil end
  return { wx = x * r.w, wy = y * r.h }
end

-- Etape franchie : temps note, duree du troncon apprise, arret differe declenche
local function Pass(f, el, measured)
  local i = f.reached
  f.reached = i + 1
  f.times[i + 1] = el
  f.minD = nil
  if measured then Learn(f.nodes[i], f.nodes[i + 1], el - f.times[i]) end
  if f.stop and f.stop == f.reached + 1 then RequestLanding() end
  SaveFlight()
  Refresh(true)
end

local function Track(f, el)
  local nextI = f.reached + 1
  if nextI >= #f.nodes then return end   -- la derniere etape : l'atterrissage met fin au vol
  local hopT = f.hop[f.reached]
  local p = PlayerYards(f)
  local d = p and Dist(p, f.nodes[nextI])
  if d then
    f.minD = min(f.minD or d, d)
    if d < 40 or (f.minD < 120 and d > f.minD + 20) then return Pass(f, el, true) end
    if el > f.times[f.reached] + hopT * 1.8 + 30 then return Pass(f, el, false) end   -- filet de securite
  elseif el >= f.times[f.reached] + hopT then
    Pass(f, el, false)
  end
end

local EndFlight   -- forward

local function OnUpdate(_, el)
  -- Entree / sortie des bandes et fondu de l'interface
  if animP ~= animTarget then
    if animTarget > animP then animP = min(animTarget, animP + el / ANIM_TIME)
    else animP = max(animTarget, animP - el / ANIM_TIME) end
    local e = Ease(animP)
    local cfg = Cfg()
    topBand:ClearAllPoints()
    topBand:SetPoint("TOP", root, "TOP", 0, (1 - e) * (cfg.panelTopHeight or 60))
    bottomBand:ClearAllPoints()
    bottomBand:SetPoint("BOTTOM", root, "BOTTOM", 0, -(1 - e) * (cfg.panelBottomHeight or 90))
    track:ClearAllPoints()
    track:SetPoint("CENTER", bottomBand, "CENTER", 0, 0)
    track:SetAlpha(e)
    if animP == 0 and animTarget == 0 then
      root:Hide()
    end
  end
  if uiHidden or uiAlpha < uiSavedAlpha then
    local want = uiHidden and 0 or uiSavedAlpha
    if uiAlpha ~= want then
      local step = el / UI_FADE * uiSavedAlpha
      uiAlpha = (want < uiAlpha) and max(want, uiAlpha - step) or min(want, uiAlpha + step)
      UIParent:SetAlpha(uiAlpha)
    end
  end
  if uiHidden then UpdateReveal(el)
  elseif next(fades) then
    StepFades(el)
    if uiAlpha >= uiSavedAlpha then ClearReveals() end
  end
  if uiHidden or mmHidden then SyncMinimap() end

  if flight then
    if not UnitOnTaxi("player") then return EndFlight() end
    posClock = posClock + el
    if posClock >= 0.2 then posClock = 0; Track(flight, Elapsed(flight)) end
  elseif demo then
    -- Apercu : boucle sur la duree du vol fictif, etapes franchies au temps estime
    local d = demo
    if Elapsed(d) > d.axis[#d.nodes] + 4 then d.start = GetTime() - 150; d.reached = 1; d.times = { 0 } end
    while d.reached < #d.nodes and Elapsed(d) >= d.axis[d.reached + 1] do
      d.reached = d.reached + 1; d.times[d.reached] = d.axis[d.reached]
    end
  end
  if root and root:IsShown() and (flight or demo) then Refresh(false) end

  if animP == 0 and animTarget == 0 and not uiHidden and uiAlpha >= uiSavedAlpha and not mmHidden and not flight and not demo then
    driver:SetScript("OnUpdate", nil)
  end
end

local function ShowOverlay(strata)
  Build()
  Layout()
  root:SetFrameStrata(strata or "BACKGROUND")
  root:Show()
  animTarget = 1
  Refresh(true)
  driver:SetScript("OnUpdate", OnUpdate)
end

local function HideOverlay()
  animTarget = 0
  driver:SetScript("OnUpdate", OnUpdate)
end

local function StartFlight(route, start)
  local cfg = Cfg()
  if not cfg.enabled or not route then return end
  demo = nil
  flight = NewFlight(route, start)
  SaveFlight()
  ShowOverlay("BACKGROUND")
  if cfg.hideUI ~= false then SetUIHidden(true) end
end

function EndFlight()
  local f = flight
  if f then
    -- Dernier troncon : appris si l'on s'est pose sur l'etape attendue (destination ou arret choisi)
    local land = f.stop or #f.nodes
    local p = PlayerYards(f)
    local d = p and Dist(p, f.nodes[f.reached + 1])
    if land == f.reached + 1 and d and d < 300 then
      Learn(f.nodes[f.reached], f.nodes[land], Elapsed(f) - f.times[f.reached])
    end
  end
  flight = nil
  pending = nil
  SaveFlight()
  SetUIHidden(false)
  if preview then TaxiMode.SetPreview(true) else HideOverlay() end
end

-- ═══ Apercu (page de reglages) ═══════════════════════════════════════════════════════════════════
local function DemoRoute()
  local list = L["TAXIMODE_DEMO"] or {}
  local nodes = {}
  for i, e in ipairs(list) do nodes[i] = { name = e[1], zone = e[2], demoT = e[3] } end
  return { nodes = nodes }
end

function TaxiMode.SetPreview(on)
  preview = on and true or false
  if flight then return end   -- un vrai vol garde la main
  if preview and Cfg().enabled then
    local r = DemoRoute()
    if #r.nodes < 2 then return end
    demo = { route = r, nodes = r.nodes, start = GetTime() - 215, reached = 1, times = { 0 }, isDemo = true,
      hop = {}, axis = { 0 } }
    for i = 2, #r.nodes do
      demo.axis[i] = r.nodes[i].demoT
      demo.hop[i - 1] = demo.axis[i] - demo.axis[i - 1]
    end
    ShowOverlay("HIGH")   -- sous le panneau de reglages (DIALOG)
  else
    demo = nil
    HideOverlay()
  end
end

function TaxiMode.ApplySettings()
  local cfg = Cfg()
  if not cfg.enabled then
    if flight then EndFlight() end
    if demo then TaxiMode.SetPreview(false); preview = true end
    return
  end
  if flight then
    if cfg.hideUI ~= false then SetUIHidden(true) else SetUIHidden(false) end
  elseif preview and not demo then
    TaxiMode.SetPreview(true)
  end
  if root and root:IsShown() then Layout(); Refresh(true) end
end

-- ═══ Evenements ═══════════════════════════════════════════════════════════════════════════════════
if hooksecurefunc and TakeTaxiNode then
  hooksecurefunc("TakeTaxiNode", function(slot)
    if not Cfg().enabled then return end
    local ok, route = pcall(CaptureRoute, slot)
    if ok and route then pending = { route = route, at = GetTime() } end
  end)
end

-- Decollage : UnitOnTaxi passe a vrai un peu apres la perte de controle
local function WatchTakeoff()
  local tries = 0
  local function check()
    tries = tries + 1
    if flight or not pending then return end
    if UnitOnTaxi("player") then
      StartFlight(pending.route)
      pending = nil
    elseif tries < 40 and GetTime() - pending.at < 15 then
      C_Timer.After(0.25, check)
    end
  end
  check()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_CONTROL_LOST")
ev:RegisterEvent("PLAYER_CONTROL_GAINED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_CONTROL_LOST" then
    if pending then WatchTakeoff() end
  elseif event == "PLAYER_CONTROL_GAINED" then
    if flight then C_Timer.After(0.1, function() if flight and not UnitOnTaxi("player") then EndFlight() end end) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- /reload en plein vol : on reprend le vol enregistre
    local db = Store()
    local saved = db and db._taxiFlight
    if flight or not saved then return end
    if UnitOnTaxi("player") and Cfg().enabled and type(saved.route) == "table" and saved.start
       and saved.start <= GetTime() and GetTime() - saved.start < 3600 then
      StartFlight(saved.route, saved.start)
      flight.reached, flight.times = saved.reached or 1, saved.times or { 0 }
      flight.stop, flight.requested = saved.stop, saved.requested
      SaveFlight()
      Refresh(true)
    else
      db._taxiFlight = nil
    end
  elseif root and root:IsShown() then
    Layout(); Refresh(true)
  end
end)

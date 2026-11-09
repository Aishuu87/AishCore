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

local GLOW_TEX   = "Interface\\AddOns\\AishCore\\Media\\UI\\SpotGlow.tga"
local WHITE      = "Interface\\Buttons\\WHITE8x8"
local FLY        = "Interface\\AddOns\\AishCore\\Media\\UI\\Fly\\"
local NODE_TEX   = { todo = FLY .. "node_etape.png", done = FLY .. "node_etape_checked.png", stop = FLY .. "node_etape_stop.png" }
local NODE_END   = 22     -- depart / arrivee
local NODE_STEP  = 16     -- etapes intermediaires
local NODE_HOVER = 1.2    -- etape survolee (arret possible) : legerement plus grande

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
local root, topBand, bottomBand, track, lineDone, lineShine, lineGlow, lineTodo, diamond, elapsedText
local startDot, endDot, startName, startZone, endName, endZone, endEta, startGroup, endGroup
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

local function FontPath(f)
  return (ns.SafeFontPath and ns.SafeFontPath(f or ns.FONT_FALLBACK)) or f or ns.FONT_FALLBACK
end

-- Reglages d'un texte (prefixe : startName, endName, zone, step, eta, elapsed) : police, taille, couleur, alignement
local function TextCfg(prefix)
  local cfg = Cfg()
  local c = cfg[prefix .. "Accent"] and Accent() or cfg[prefix .. "Color"] or { 1, 1, 1, 1 }
  return cfg[prefix .. "Font"], cfg[prefix .. "Size"] or 12, c, cfg[prefix .. "Align"] or "CENTER"
end

-- "LEFT" / "RIGHT" -> suffixe de point d'ancrage ; "CENTER" -> "" (TOP / BOTTOM)
local function J(align) return (align == "LEFT" or align == "RIGHT") and align or "" end

local function NewText(parent, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(ns.FONT_FALLBACK, 12, "")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
  return fs
end

local function StyleText(fs, size, c, font)
  if not fs:SetFont(FontPath(font), max(6, floor(size + 0.5)), "") then fs:SetFont(ns.FONT_FALLBACK, max(6, floor(size + 0.5)), "") end
  if c then fs:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
end

-- Style complet d'un texte d'apres ses reglages ; renvoie son alignement
local function ApplyText(fs, prefix)
  local font, size, c, align = TextCfg(prefix)
  StyleText(fs, size, c, font)
  fs:SetJustifyH(align)
  return align
end

-- Noeud (depart, arrivee, etape) : texture Media/UI/Fly selon l'etat, non colorisee
local function NewDot(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.baseSize = size
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.tex:SetTexture(NODE_TEX.todo)
  return b
end

local RED = { 0.9, 0.12, 0.1, 1 }

-- state : "done" (passee), "todo", "stop" (survol / arret choisi)
local function PaintDot(b, state)
  if b.state == state then return end
  b.state = state
  b.tex:SetTexture(NODE_TEX[state] or NODE_TEX.todo)
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

-- Survol d'une etape : le cadre garde sa taille (nom / ETA ancres dessus restent fixes) ; seuls l'icone
-- (agrandie), la lueur rouge et "ARRET ICI" (glisse depuis la gauche) s'animent.
local STOP_ANIM  = 0.18   -- duree des transitions
local STOP_SLIDE = 12     -- distance de glissement du texte

local function CheckpointAnim(cp, elapsed)
  local step = elapsed / STOP_ANIM
  local function Toward(cur, target)
    if cur < target then return min(target, cur + step) end
    return max(target, cur - step)
  end
  cp.sP = Toward(cp.sP, cp.sT)
  cp.tP = Toward(cp.tP, cp.tT)
  local s, t = Ease(cp.sP), Ease(cp.tP)
  local sz = cp.baseSize * (1 + (NODE_HOVER - 1) * s)
  cp.tex:SetSize(sz, sz)
  cp.glow:SetAlpha(0.75 * t)
  local x = 6 - STOP_SLIDE * (1 - t)
  cp.stopText:SetPoint("BOTTOMLEFT", cp, "RIGHT", x, 1)
  cp.stopText2:SetPoint("TOPLEFT", cp, "RIGHT", x, -1)
  cp.stopText:SetAlpha(t); cp.stopText2:SetAlpha(t)
  cp.stopText:SetShown(t > 0); cp.stopText2:SetShown(t > 0)
  if cp.sP == cp.sT and cp.tP == cp.tT then cp:SetScript("OnUpdate", nil) end
end

local function SetCheckpointTargets(cp, big, red)
  local sT, tT = big and 1 or 0, red and 1 or 0
  if cp.sT == sT and cp.tT == tT then return end
  cp.sT, cp.tT = sT, tT
  cp:SetScript("OnUpdate", CheckpointAnim)
end

local function NewCheckpoint()
  local cp = NewDot(track, NODE_STEP)
  cp:SetFrameLevel(track:GetFrameLevel() + 3)
  cp:SetHitRectInsets(-8, -8, -18, -14)
  cp.tex:ClearAllPoints()
  cp.tex:SetPoint("CENTER")
  cp.tex:SetSize(NODE_STEP, NODE_STEP)
  cp.glow = cp:CreateTexture(nil, "BACKGROUND")
  cp.glow:SetTexture(GLOW_TEX)
  cp.glow:SetBlendMode("ADD")
  cp.glow:SetSize(NODE_STEP * 5, NODE_STEP * 5)
  cp.glow:SetPoint("CENTER")
  cp.glow:SetVertexColor(RED[1], RED[2], RED[3], 1)
  cp.glow:SetAlpha(0)
  cp.sP, cp.tP, cp.sT, cp.tT = 0, 0, 0, 0
  cp.name = NewText(cp)
  cp.eta = NewText(cp)
  -- "ARRET ICI" de part et d'autre de la ligne : 1re ligne au-dessus, le reste en dessous, a droite du noeud
  local w1, w2 = (L["TAXIMODE_STOP_HERE"] or ""):match("^([^\n]*)\n?(.*)$")
  cp.stopText = NewText(cp)
  cp.stopText:SetJustifyH("LEFT")
  cp.stopText:SetText(w1)
  cp.stopText2 = NewText(cp)
  cp.stopText2:SetJustifyH("LEFT")
  cp.stopText2:SetText(w2)
  CheckpointAnim(cp, 0)
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

  -- Timeline : texture Media/UI/Fly ; partie parcourue = meme texture teintee, recadree (pas etiree)
  lineTodo = track:CreateTexture(nil, "ARTWORK", nil, 0)
  lineTodo:SetTexture(FLY .. "timeline_off.png")
  lineTodo:SetHeight(6)
  lineTodo:SetPoint("LEFT"); lineTodo:SetPoint("RIGHT")
  lineGlow = track:CreateTexture(nil, "ARTWORK", nil, 1)
  lineGlow:SetTexture(GLOW_TEX)
  lineGlow:SetBlendMode("ADD")
  lineGlow:SetHeight(16)
  -- Partie parcourue : barre pleine en relief (timeline_on, niveaux de gris teintes) + reflet additif au centre
  -- (timeline_on_shine, quasi blanc) ; la barre utile occupe ~14/32 de la hauteur de la texture
  lineDone = track:CreateTexture(nil, "ARTWORK", nil, 2)
  lineDone:SetTexture(FLY .. "timeline_on.png")
  lineDone:SetHeight(15)
  lineShine = track:CreateTexture(nil, "ARTWORK", nil, 3)
  lineShine:SetTexture(FLY .. "timeline_on_shine.png")
  lineShine:SetBlendMode("ADD")
  lineShine:SetAllPoints(lineDone)

  startDot = NewDot(track, NODE_END)
  startDot:EnableMouse(false)
  startDot:SetPoint("CENTER", track, "LEFT", 0, 0)
  endDot = NewDot(track, NODE_END)
  endDot:EnableMouse(false)
  endDot:SetPoint("CENTER", track, "RIGHT", 0, 0)
  startDot:SetFrameLevel(track:GetFrameLevel() + 3)
  endDot:SetFrameLevel(track:GetFrameLevel() + 3)

  -- Groupes nom + zone : cadre d'un pixel de haut sur la ligne de base (nom au-dessus, zone en dessous), aussi large
  -- que le plus long des deux textes ; place a cote de son cercle (cf. Layout)
  startGroup = CreateFrame("Frame", nil, track)
  startGroup:SetFrameLevel(track:GetFrameLevel() + 3)
  endGroup = CreateFrame("Frame", nil, track)
  endGroup:SetFrameLevel(track:GetFrameLevel() + 3)
  startName = NewText(startGroup)
  startZone = NewText(startGroup)
  endName = NewText(endGroup)
  endZone = NewText(endGroup)
  endEta = NewText(endDot)

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

  -- Losange (position du joueur) : cadre fixe (diamond) + coeur (diamond_center), seul colorise, en couleurs
  -- thematiques ; sinon le coeur d'origine du losange reste visible
  diamond = CreateFrame("Frame", nil, track)
  diamond:SetSize(26, 27)   -- 41 x 43 a l'origine
  diamond:SetFrameLevel(track:GetFrameLevel() + 6)
  diamond.glow = diamond:CreateTexture(nil, "BACKGROUND")
  diamond.glow:SetTexture(GLOW_TEX)
  diamond.glow:SetBlendMode("ADD")
  diamond.glow:SetSize(52, 52)
  diamond.glow:SetPoint("CENTER")
  diamond.glow:SetVertexColor(0.2, 0.75, 0.9, 0.5)
  diamond.frame = diamond:CreateTexture(nil, "ARTWORK", nil, 1)
  diamond.frame:SetTexture(FLY .. "diamond.png")
  diamond.frame:SetAllPoints()
  diamond.core = diamond:CreateTexture(nil, "ARTWORK", nil, 2)
  diamond.core:SetTexture(FLY .. "diamond_center.png")
  diamond.core:SetAllPoints()

  elapsedText = NewText(diamond)
end

-- Route : centre de la bande du bas + decalage
local function PlaceTrack()
  local cfg = Cfg()
  track:ClearAllPoints()
  track:SetPoint("CENTER", bottomBand, "CENTER", cfg.trackX or 0, cfg.trackY or 0)
end

-- Texte au-dessus (above) ou en dessous d'un cercle, selon son alignement
local function PlaceAround(fs, dot, align, above, gap)
  local j = J(align)
  fs:ClearAllPoints()
  if above then fs:SetPoint("BOTTOM" .. j, dot, "TOP" .. j, 0, gap)
  else fs:SetPoint("TOP" .. j, dot, "BOTTOM" .. j, 0, -gap) end
end

-- Groupe nom + zone : a gauche du cercle de depart (left) ou a droite de celui de destination
local function PlaceGroup(g, name, zone, dot, left, nameAlign, zoneAlign, ox, oy)
  g:SetSize(max(1, name:GetStringWidth() or 0, zone:GetStringWidth() or 0), 1)
  g:ClearAllPoints()
  if left then g:SetPoint("RIGHT", dot, "LEFT", -12 + ox, -1 + oy)
  else g:SetPoint("LEFT", dot, "RIGHT", 12 + ox, -1 + oy) end
  local jn, jz = J(nameAlign), J(zoneAlign)
  name:ClearAllPoints()
  name:SetPoint("BOTTOM" .. jn, g, "TOP" .. jn, 0, 0)
  zone:ClearAllPoints()
  zone:SetPoint("TOP" .. jz, g, "BOTTOM" .. jz, 0, -2)
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

  PlaceTrack()
  local a = Accent()
  local n = f.nodes
  local alStart = ApplyText(startName, "startName"); startName:SetText(Upper(n[1].name))
  local alEnd   = ApplyText(endName, "endName");     endName:SetText(Upper(n[#n].name))
  local alZone  = ApplyText(startZone, "zone");      startZone:SetText(n[1].zone or "")
  ApplyText(endZone, "zone");                        endZone:SetText(n[#n].zone or "")
  PlaceGroup(startGroup, startName, startZone, startDot, true, alStart, alZone, cfg.startX or 0, cfg.startY or 0)
  PlaceGroup(endGroup, endName, endZone, endDot, false, alEnd, alZone, cfg.endX or 0, cfg.endY or 0)
  local alEta = ApplyText(endEta, "eta")
  PlaceAround(endEta, endDot, alEta, false, 4)
  local alElapsed = ApplyText(elapsedText, "elapsed")
  elapsedText:ClearAllPoints()
  if alElapsed == "LEFT" then elapsedText:SetPoint("TOPLEFT", diamond, "BOTTOMRIGHT", -6, 1)
  elseif alElapsed == "RIGHT" then elapsedText:SetPoint("TOPRIGHT", diamond, "BOTTOMLEFT", 6, 1)
  else elapsedText:SetPoint("TOP", diamond, "BOTTOM", 0, 1) end
  for _, d in ipairs({ startDot, endDot }) do
    local r = d.rule
    if r.SetGradient and CreateColor then
      local c0, c1 = CreateColor(a[1], a[2], a[3], 0), CreateColor(a[1], a[2], a[3], 0.35)
      if r.left then r:SetGradient("HORIZONTAL", c0, c1) else r:SetGradient("HORIZONTAL", c1, c0) end
    else
      r:SetVertexColor(a[1], a[2], a[3], 0.25)
    end
  end
  -- Texture de la partie parcourue : "fly" = barre en relief + reflet du mode taxi ; sinon texture de barre
  -- de la liste commune (pleine hauteur, donc barre plus basse, sans reflet)
  local texKey = cfg.doneTexture or "fly"
  if texKey == "fly" or not ns.ResolveBarTexFromKey then
    lineDone:SetTexture(FLY .. "timeline_on.png")
    lineDone:SetHeight(15)
    lineShine:Show()
  else
    lineDone:SetTexture(ns.ResolveBarTexFromKey(texKey))
    lineDone:SetHeight(6)
    lineShine:Hide()
  end
  lineDone:SetVertexColor(a[1], a[2], a[3], 1)
  -- Reflet : couleur d'accent eclaircie (coeur "chauffe a blanc" du modele)
  lineShine:SetVertexColor(a[1] + (1 - a[1]) * 0.55, a[2] + (1 - a[2]) * 0.55, a[3] + (1 - a[3]) * 0.55, 0.8)
  lineGlow:SetVertexColor(a[1], a[2], a[3], 0.55)
  local themed = cfg.useThemeColors and true or false
  diamond.core:SetShown(themed)
  if themed then
    diamond.core:SetVertexColor(a[1], a[2], a[3], 1)
    diamond.glow:SetVertexColor(a[1], a[2], a[3], 0.5)
  else
    diamond.glow:SetVertexColor(0.2, 0.75, 0.9, 0.5)
  end

  -- Etapes intermediaires, placees au prorata des temps estimes
  local total = f.axis[#n]
  for i = 2, #n - 1 do
    local cp = checkpoints[i - 1] or NewCheckpoint()
    checkpoints[i - 1] = cp
    cp.index = i
    cp:ClearAllPoints()
    cp:SetPoint("CENTER", track, "LEFT", total > 0 and tw * f.axis[i] / total or tw * (i - 1) / (#n - 1), 0)
    local alStep = ApplyText(cp.name, "step"); cp.name:SetText(n[i].name or "")
    PlaceAround(cp.name, cp, alStep, true, 5)
    PlaceAround(cp.eta, cp, ApplyText(cp.eta, "eta"), false, 4)
    local sFont, sSize = TextCfg("step")
    StyleText(cp.stopText, sSize, RED, sFont)
    StyleText(cp.stopText2, sSize, RED, sFont)
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
  lineDone:SetTexCoord(0, tw > 0 and min(1, max(0, x / tw)) or 0, 0, 1)
  lineShine:SetTexCoord(0, tw > 0 and min(1, max(0, x / tw)) or 0, 0, 1)
  lineGlow:ClearAllPoints()
  lineGlow:SetPoint("LEFT", track, "LEFT", -6, 0)
  lineGlow:SetWidth(max(0.001, x + 6))

  textClock = textClock + 1
  if not force and textClock % 15 ~= 0 then return end

  elapsedText:SetText(FormatTime(el))
  PaintDot(startDot, "done")
  local stopIdx = f.stop
  PaintDot(endDot, (f.reached >= #n) and "done" or "todo")
  endEta:SetText(f.reached >= #n and "" or FormatTime(eta[#n]))   -- etape atteinte : plus d'ETA
  local beyond = stopIdx and #n > stopIdx
  endDot:SetAlpha(beyond and 0.35 or 1)
  endName:SetAlpha(beyond and 0.5 or 1)
  for _, cp in ipairs(checkpoints) do
    if cp:IsShown() then
      local i = cp.index
      local selected = (stopIdx == i)
      local hot = selected or (cp.hover and CheckpointStoppable(cp))
      PaintDot(cp, hot and "stop" or (i <= f.reached and "done" or "todo"))
      SetCheckpointTargets(cp, cp.hover and hot, hot and CAN_STOP)
      cp.eta:SetText(i <= f.reached and "" or FormatTime(eta[i]))
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

-- Nouvelle ligne dans une fenetre de chat affichee : montree CHAT_REVEAL secondes. Pas pendant le fondu du
-- decollage (lignes systeme du depart) : le chat disparait avec le reste au lieu de remonter d'un coup.
local chatHooked
local function ChatReveal() return uiHidden and uiAlpha <= 0 end
local function OnChatLine(cf)
  if ChatReveal() and cf:IsShown() then pcall(Hover, cf, GetTime(), CHAT_REVEAL) end
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
      if not ChatReveal() then return end
      local h = API.GetHyperlinkHandler()
      if h then pcall(Hover, h, GetTime(), CHAT_REVEAL) end
    end)
  end
end

-- Survol relaye : un cadre survole revele aussi ses cadres associes (barre d'xp : la zone de survol, invisible,
-- revele la barre, le badge et les panneaux). getFrames renvoie la liste des cadres a reveler.
local hoverLinks = {}
function ns.TaxiLinkHover(owner, getFrames)
  if owner then hoverLinks[owner] = getFrames end
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
    for owner, get in pairs(hoverLinks) do
      if hoverUntil[owner] then
        local ok, list = pcall(get)
        for _, f in pairs(ok and list or {}) do
          if f.IsShown and f:IsShown() then pcall(Hover, f, now) end
        end
      end
    end
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
    PlaceTrack()
    track:SetAlpha(e)
    if animP == 0 and animTarget == 0 then
      root:Hide()
    end
  end
  if uiHidden or uiAlpha < uiSavedAlpha then
    -- Interface cachee puis reaffichee (Alt+Z) : le client remet UIParent a 1. On repart de l'alpha reel
    -- pour refaire le fondu, sinon uiAlpha (deja a 0) ne serait jamais reapplique.
    local real = UIParent:GetAlpha()
    if UIParent:IsShown() and math.abs(real - uiAlpha) > 0.01 then uiAlpha = min(real, uiSavedAlpha) end
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

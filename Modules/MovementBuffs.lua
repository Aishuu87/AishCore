-- Modules/MovementBuffs.lua : Buffs de deplacement (Auras & Procs), Retail et Forever.
-- Un petit rond fixe, et deux barres de part et d'autre qui se vident en miroir (vers le rond) pendant la
-- duree d'un buff de vitesse (Sprint, Celerite, Plume angelique...). Un buff de plus = une rangee de plus,
-- en dessous. Arrivee / depart : fondu + glissement + barres qui s'etirent / se replient.
-- Masque en monture, en vehicule et en combat de mascottes. Visibilite : toujours / en combat / hors combat.
-- En combat, les auras du joueur ne se lisent plus (valeurs secretes) : l'affichage passe a un conteneur natif
-- (AuraContainer, meme principe que la Liste d'icones) que le jeu remplit lui-meme, sans animation. Hors combat,
-- l'affichage anime reprend. Client sans AuraContainer : affichage anime en permanence.
local addonName, ns = ...
local L = ns.L

local MovementBuffs = {}
ns.Modules.MovementBuffs = MovementBuffs

-- Buffs suivis, par groupe (classe, racial, objet), comme la liste des Buffs manquants. Chaque entree :
--   id      : sort de reference (case a cocher, nom et icone dans les reglages, cle de la rangee)
--   alt     : autres IDs du meme buff (rangs, variantes) qui partagent la rangee
--   stacks  : barres pilotees par le nombre de stacks (max = stacks) au lieu de la duree
-- Les deux clients partagent la liste : une entree dont aucun ID n'existe sur le client est masquee.
-- Decocher une entree : ns.DB.movementBuffs.disabled[id] = true.
local GROUPS = {
  { key = "DEATHKNIGHT", list = { { id = 212552 }, { id = 48265 } } },                     -- Marche fantomatique, Avancee de la mort
  { key = "DEMONHUNTER", list = { { id = 389847 }, { id = 258920 } } },                    -- Ruee de gangrefeu, Flammes dechirantes
  { key = "DRUID",       list = { { id = 1850, alt = { 9821 } }, { id = 252216 }, { id = 106898, alt = { 77764, 77761 } } } },  -- Celerite, Ruee du tigre, Rugissement
  { key = "EVOKER",      list = { { id = 358267 } } },                                     -- Survol
  { key = "HUNTER",      list = { { id = 186257, alt = { 186258 } }, { id = 118922 }, { id = 1317257 } } },  -- Aspect du guepard, Hate, Strider Kick (Forever seulement)
  { key = "MAGE",        list = { { id = 108843 } } },                                     -- Vitesse flamboyante
  { key = "MONK",        list = { { id = 116841 }, { id = 119085 } } },                    -- Soif du tigre, Torpille de chi
  { key = "PALADIN",     list = { { id = 221883, alt = { 221885, 221886, 221887, 254471, 254472, 254473, 254474, 276111, 276112 } } } },  -- Destrier divin
  { key = "PRIEST",      list = { { id = 121557 }, { id = 65081 } } },                     -- Plume angelique, Corps et ame
  { key = "ROGUE",       list = { { id = 2983, alt = { 8696, 11305 } }, { id = 36554 } } },-- Sprint, Pas de l'ombre
  { key = "SHAMAN",      list = { { id = 58875 }, { id = 192082 } } },                     -- Marche spirituelle, Totem de bourrasque
  { key = "WARLOCK",     list = { { id = 111400 } } },                                     -- Ruee ardente
  { key = "WARRIOR",     list = { { id = 202164 } } },                                     -- Foulee bondissante
  { key = "RACIAL",      list = { { id = 68992 }, { id = 1299038, stacks = 30 } } },       -- Sombre envol (worgen), Tauren (Forever)
  { key = "ITEMS",       list = { { id = 2379 } } },                                       -- Rapidite (potion)
}
MovementBuffs.GROUPS = GROUPS

local function SpellExists(id)
  if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(id) ~= nil end
  return GetSpellInfo and GetSpellInfo(id) ~= nil
end

-- Premier ID de l'entree connu du client (nil = entree absente de ce client)
function MovementBuffs.EntrySpell(e)
  if SpellExists(e.id) then return e.id end
  for _, id in ipairs(e.alt or {}) do
    if SpellExists(id) then return id end
  end
end

-- ID suivi -> entree, reconstruit quand les cases changent
local trackMap, trackList
local function BuildTracking()
  local c = ns.GetCfg("movementBuffs") or {}
  local off = c.disabled or {}
  trackMap, trackList = {}, {}
  for _, g in ipairs(GROUPS) do
    for _, e in ipairs(g.list) do
      if not off[e.id] then
        for _, id in ipairs({ e.id, unpack(e.alt or {}) }) do
          if not trackMap[id] then
            trackMap[id] = e
            trackList[#trackList + 1] = id
          end
        end
      end
    end
  end
end
function MovementBuffs.InvalidateTracking() trackMap, trackList = nil, nil end

local root, driver, evt
local rows = {}               -- rangees actives, dans l'ordre d'affichage
local pool = {}               -- rangees libres
local previewOn = false
local previewTicker
local IN_DUR, OUT_DUR, SLIDE = 0.35, 0.35, 8

local function Cfg() return ns.GetCfg("movementBuffs") or {} end

-- Grille des pixels physiques : des barres de 1-3 px dont la hauteur ou le bord tombe entre deux pixels sont
-- tantot fines, tantot grossies d'un pixel. Tailles arrondies a un nombre entier de pixels ecran, positions calees
-- sur un pixel (y compris pendant le glissement d'apparition).
local function PixelUnit(region)
  local _, ph = GetPhysicalScreenSize()
  local es = (region and region:GetEffectiveScale()) or UIParent:GetEffectiveScale()
  if not ph or ph <= 0 or not es or es <= 0 then return 1 end
  return 768 / ph / es
end
local function Snap(v, px) return math.floor(v / px + 0.5) * px end
local function SnapSize(v, px) return math.max(1, math.floor(v / px + 0.5)) * px end
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local function Colors(c)
  -- Couleur de spe : rond = "Decorations B", barres = "Cercle de Puissance"
  if c.useSpecColor then
    local CLR = ns.Modules and ns.Modules.Colors
    local dot = CLR and CLR.Get and CLR.Get("powerdotsb")
    local bar = CLR and CLR.Get and CLR.Get("powercircle")
    if dot or bar then
      return dot or bar or c.dotColor or { 1, 1, 1, 1 }, bar or dot or c.barColor or { 1, 0.82, 0.2, 1 }
    end
  end
  return c.dotColor or { 1, 1, 1, 1 }, c.barColor or { 1, 0.82, 0.2, 1 }
end

-- ── Rangees ─────────────────────────────────────────────────────────────────

local function MakeBar(parent)
  local b = CreateFrame("StatusBar", nil, parent)
  ns.SetSmoothStatusBarTexture(b, "Interface\\Buttons\\WHITE8x8")
  local bt = b:GetStatusBarTexture()
  if bt then bt:SetSnapToPixelGrid(false); bt:SetTexelSnappingBias(0) end
  b:SetMinMaxValues(0, 1)
  b:SetValue(1)
  return b
end

local function NewRow()
  local r = table.remove(pool)
  if r then return r end
  r = CreateFrame("Frame", nil, root)
  r.dot = r:CreateTexture(nil, "ARTWORK")
  r.dot:SetTexture(ns.Media.circle)
  -- Gauche : remplissage ancre a droite (cote rond) ; droite : ancre a gauche. Les deux se vident vers le rond.
  -- Positions posees par StyleRow (calees sur les pixels).
  r.left = MakeBar(r)
  r.left:SetReverseFill(true)
  r.right = MakeBar(r)
  return r
end

-- Dimensions calees sur les pixels : rond, barres, ecart, hauteur de rangee
local function Metrics(region)
  local c = Cfg()
  local px = PixelUnit(region or root)
  local d   = SnapSize(c.dotSize or 5, px)
  local bh  = SnapSize(c.barHeight or 3, px)
  local gap = Snap(c.gap or 6, px)
  local bw  = SnapSize(c.barWidth or 70, px)
  local rh  = math.max(d, bh)
  return px, d, bh, gap, bw, rh
end

local function StyleRow(r)
  local c = Cfg()
  local dc, bc = Colors(c)
  local px, d, bh, gap, bw, rh = Metrics(r)
  r:SetSize(bw * 2 + gap * 2 + d, rh)
  -- Rond et barres poses depuis le HAUT de la rangee, avec des decalages entiers en pixels : jamais de bord a cheval
  r.dot:ClearAllPoints()
  r.dot:SetSize(d, d)
  r.dot:SetPoint("TOP", r, "TOP", 0, -Snap((rh - d) / 2, px))
  r.dot:SetVertexColor(dc[1], dc[2], dc[3], dc[4] or 1)
  local by = -Snap((rh - bh) / 2, px)
  r.left:ClearAllPoints();  r.left:SetPoint("TOPRIGHT", r, "TOP", -(Snap(d / 2, px) + gap), by)
  r.right:ClearAllPoints(); r.right:SetPoint("TOPLEFT", r, "TOP", Snap(d / 2, px) + gap, by)
  for _, b in ipairs({ r.left, r.right }) do
    b:SetHeight(bh)
    b:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)
  end
end

-- Duree : objet natif (Retail, valeurs secretes en combat) sinon expiration lisible (Forever), sinon barres pleines.
local function ArmRow(r, aura, entry)
  r.manualStart, r.manualDur = nil, nil
  -- Buff a stacks (Tauren, Forever) : la barre grandit avec le nombre de stacks, sans minuteur
  if entry and entry.stacks then
    local n = aura.applications
    local v = (Plain(n) and type(n) == "number") and math.max(0, math.min(1, n / entry.stacks)) or 1
    pcall(ns.SmoothBarValue, r.left, v); pcall(ns.SmoothBarValue, r.right, v)
    return
  end
  local dur, exp = aura.duration, aura.expirationTime
  if Plain(dur) and Plain(exp) then
    if not dur or dur <= 0 then
      r.left:SetValue(1); r.right:SetValue(1); r.timed = false
      return
    end
  end
  if type(aura.auraInstanceID) ~= "nil" and C_UnitAuras.GetAuraDuration and r.left.SetTimerDuration and Enum.StatusBarTimerDirection then
    local ok, obj = pcall(C_UnitAuras.GetAuraDuration, "player", aura.auraInstanceID)
    if ok and obj then
      local IMM = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
      local okL = pcall(r.left.SetTimerDuration, r.left, obj, IMM, Enum.StatusBarTimerDirection.RemainingTime)
      local okR = pcall(r.right.SetTimerDuration, r.right, obj, IMM, Enum.StatusBarTimerDirection.RemainingTime)
      if okL and okR then r.timed = true; return end
    end
  end
  if Plain(dur) and Plain(exp) and dur and exp then
    r.manualStart, r.manualDur = exp - dur, dur
  end
  r.timed = false
end

-- ── Disposition et animation ────────────────────────────────────────────────

local function RowStep()
  local c = Cfg()
  local px, _, _, _, _, rh = Metrics(root)
  return rh + Snap(c.rowSpacing or 8, px)
end

local function Ease(t) return 1 - (1 - t) * (1 - t) * (1 - t) end

local function StartDriver()
  if driver:GetScript("OnUpdate") then return end
  driver:SetScript("OnUpdate", function(_, el)
    local px, _, _, _, w = Metrics(root)
    local step = RowStep()
    local busy = false
    local now = GetTime()
    for i = #rows, 1, -1 do
      local r = rows[i]
      if r.state == "in" then
        r.t = math.min(1, r.t + el / IN_DUR)
        if r.t >= 1 then r.state = "on" end
      elseif r.state == "out" then
        r.t = math.max(0, r.t - el / OUT_DUR)
        if r.t <= 0 then
          -- Une rangee armee par le minuteur natif n'est pas recyclee : le minuteur continuerait sur la suivante
          r:Hide(); table.remove(rows, i)
          if not r.timed then pool[#pool + 1] = r end
        end
      end
    end
    for i, r in ipairs(rows) do
      local e = Ease(r.t)
      r.y = r.y or -(i - 1) * step
      local ty = -(i - 1) * step
      r.y = r.y + (ty - r.y) * math.min(1, el * 12)
      if math.abs(ty - r.y) > 0.3 then busy = true end
      r:SetAlpha(e)
      r:ClearAllPoints()
      r:SetPoint("TOP", root, "TOP", 0, Snap(r.y - (1 - e) * SLIDE, px))
      local bw = math.max(0.01, Snap(w * e, px))
      r.left:SetWidth(bw); r.right:SetWidth(bw)
      if r.state ~= "on" then busy = true end
      if r.manualStart then
        local v = 1 - (now - r.manualStart) / r.manualDur
        v = math.max(0, math.min(1, v))
        r.left:SetValue(v); r.right:SetValue(v)
        busy = true
      end
    end
    if not busy then driver:SetScript("OnUpdate", nil) end
  end)
end

local function FindRow(spellID)
  for _, r in ipairs(rows) do
    if r.spellID == spellID and r.state ~= "out" then return r end
  end
end

-- Synchronise les rangees avec la liste { {id=, aura=}, ... } (ordre conserve pour les rangees deja la).
-- instant : rangees nouvelles posees directement (sortie de combat, le conteneur natif les montrait deja).
local function Sync(active, instant)
  local seen = {}
  for _, a in ipairs(active) do
    seen[a.id] = true
    local r = FindRow(a.id)
    if not r then
      r = NewRow()
      r.spellID, r.state, r.t, r.y = a.id, instant and "on" or "in", instant and 1 or 0, nil
      StyleRow(r)
      r:Show()
      rows[#rows + 1] = r
    end
    ArmRow(r, a.aura, a.entry)
  end
  for _, r in ipairs(rows) do
    if r.state ~= "out" and not seen[r.spellID] then r.state = "out" end
  end
  StartDriver()
end

-- ── Lecture des auras ───────────────────────────────────────────────────────

-- Une rangee par entree (les rangs / variantes d'un meme buff partagent la rangee de l'entree)
local function ScanAuras()
  if not trackMap then BuildTracking() end
  local active, seen = {}, {}
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    for _, id in ipairs(trackList) do
      local e = trackMap[id]
      if not seen[e] then
        local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and a then
          seen[e] = true
          active[#active + 1] = { id = e.id, aura = a, entry = e }
        end
      end
    end
  elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not a then break end
      local id = a.spellId
      local e = Plain(id) and trackMap[id]
      if e and not seen[e] then
        seen[e] = true
        active[#active + 1] = { id = e.id, aura = a, entry = e }
      end
    end
  end
  return active
end

-- ── Visibilite ──────────────────────────────────────────────────────────────

local function ShouldShow()
  local c = Cfg()
  if c.enabled == false then return false end
  if previewOn then return true end
  if IsMounted and IsMounted() then return false end
  if ns.IsInBlockedState() then return false end
  local mode = c.visibilityMode or "always"
  local inCombat = UnitAffectingCombat("player")
  if mode == "combat" then return inCombat and true or false end
  if mode == "ooc" then return not inCombat end
  return true
end

-- ── Affichage natif (combat) ────────────────────────────────────────────────

local native                 -- AuraContainer ; false = absent de ce client
local nativeGroups = {}      -- entry.id -> true (groupe ajoute)
local nativeButtons = {}     -- boutons natifs construits (restyle)
local nativeDirty = false    -- groupes a resynchroniser hors combat
local inCombat = false

-- Rond + 2 barres miroir dans un bouton natif, meme rendu qu'une rangee animee. Les barres sont liees a la duree
-- par le jeu (SetDurationBar) : jamais de SetStatusBarTexture / SetReverseFill apres coup (cf. Liste d'icones).
local function StyleNativeButton(b)
  local c = Cfg()
  local dc, bc = Colors(c)
  local px, d, bh, gap, bw, rh = Metrics(root)
  pcall(b.SetSize, b, bw * 2 + gap * 2 + d, rh)
  b._mvbDot:SetSize(d, d)
  b._mvbDot:ClearAllPoints()
  b._mvbDot:SetPoint("TOP", b, "TOP", 0, -Snap((rh - d) / 2, px))
  b._mvbDot:SetVertexColor(dc[1], dc[2], dc[3], dc[4] or 1)
  local by = -Snap((rh - bh) / 2, px)
  b._mvbL:ClearAllPoints(); b._mvbL:SetPoint("TOPRIGHT", b, "TOP", -(Snap(d / 2, px) + gap), by)
  b._mvbR:ClearAllPoints(); b._mvbR:SetPoint("TOPLEFT", b, "TOP", Snap(d / 2, px) + gap, by)
  for _, bar in ipairs({ b._mvbL, b._mvbR }) do
    bar:SetSize(bw, bh)
    bar:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)
  end
end

local diag = { init = 0, denied = 0 }   -- /aishmvb
local function BuildNativeButton(b)
  diag.init = diag.init + 1
  local okCheck, can = pcall(function() return b.CanBeAccessedInContext and b:CanBeAccessedInContext() end)
  if not (okCheck and can) then diag.denied = diag.denied + 1 end
  if not (okCheck and can) or b._mvbDot then return end
  b._mvbDot = b:CreateTexture(nil, "ARTWORK")
  b._mvbDot:SetTexture(ns.Media.circle)
  local opts = { direction = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime }
  local function Bar(rev)
    local bar = CreateFrame("StatusBar", nil, b)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    if rev then bar:SetReverseFill(true) end   -- gauche : se vide vers le rond
    pcall(b.SetDurationBar, b, bar, opts)
    return bar
  end
  b._mvbL, b._mvbR = Bar(true), Bar(false)
  StyleNativeButton(b)
  nativeButtons[#nativeButtons + 1] = b
end

-- Groupes natifs : un par buff coche (ID principal + variantes), dans l'ordre de la liste. Hors combat seulement.
local function SyncNativeGroups()
  if not native then return end
  if InCombatLockdown() then nativeDirty = true; return end
  nativeDirty = false
  local c = Cfg()
  local off = c.disabled or {}
  local _, d, _, gap, bw, rh = Metrics(root)
  local px = PixelUnit(root)
  local spacing = Snap(c.rowSpacing or 8, px)
  for _, g in ipairs(GROUPS) do
    for _, e in ipairs(g.list) do
      local key = "aishMVB_" .. e.id
      local ids = {}
      if not off[e.id] and not e.stacks then
        for _, id in ipairs({ e.id, unpack(e.alt or {}) }) do ids[id] = true end
      else
        ids = { [0] = true }   -- decoche : neutralise par un ID bidon (jamais une table vide)
      end
      if nativeGroups[e.id] then
        pcall(native.SetAuraGroupCandidateFilters, native, key, { includeSpellIDs = ids })
      elseif ids[0] == nil then
        local ok = pcall(native.AddAuraGroup, native, key, "HELPFUL", {
          maxFrameCount = 1,
          candidateFilters = { includeSpellIDs = ids },
          layout = { elementSpacing = spacing, lineSpacing = spacing, elementWidth = bw * 2 + gap * 2 + d,
                     elementHeight = rh, layoutIndex = 1 },
          initializeFrame = function(b) pcall(BuildNativeButton, b) end,
        })
        if ok then nativeGroups[e.id] = true end
      end
    end
  end
  if native.UpdateAllAuras then pcall(native.UpdateAllAuras, native) end
end

local function EnsureNative()
  if native ~= nil or not root then return native end
  if InCombatLockdown() then return nil end
  local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  if not (ok and c) then native = false; return false end
  native = c
  -- Parent UIParent (et non root) : root se masque en combat (monture...), un conteneur natif ne doit pas l'etre ;
  -- sa visibilite passe par l'alpha. Ancre sur root, il en suit la position.
  c:SetFrameStrata("MEDIUM")
  c:SetPoint("TOP", root, "TOP", 0, 0)
  c:SetSize(root:GetWidth(), 400)
  pcall(c.SetEnabled, c, true)
  pcall(c.SetUnit, c, "player")
  pcall(c.SetFlowLayoutAnchorPoint, c, "TOP")
  pcall(c.SetFlowLayoutAxis, c, 1)
  pcall(c.SetFlowLayoutGrowthDirection, c, 1, -1)
  pcall(c.SetFlowLayoutMaximumLineSize, c, 2000)
  c:SetAlpha(0)
  c:Show()
  SyncNativeGroups()
  return native
end

local pending = false
local function Refresh()
  pending = false
  if not root then return end
  local show = ShouldShow()
  -- Combat : conteneur natif visible, rangees animees masquees (leurs auras ne se lisent plus)
  local nativeMode = native and inCombat and not previewOn
  if native then pcall(native.SetAlpha, native, (show and nativeMode) and 1 or 0) end
  if not show then
    root:Hide()
    return
  end
  root:Show()
  if previewOn then return end
  if nativeMode then
    for i = #rows, 1, -1 do
      local r = rows[i]
      r:Hide(); table.remove(rows, i)
      if not r.timed then pool[#pool + 1] = r end
    end
    return
  end
  Sync(ScanAuras(), native and true or false)
end

local function RequestRefresh()
  if pending then return end
  pending = true
  C_Timer.After(0, Refresh)
end

-- ── Apercu (panneau ouvert sur la page du module) ───────────────────────────

local function PreviewCycle()
  local now = GetTime()
  local fake = {
    { id = 2983, aura = { duration = 4, expirationTime = now + 4 } },
    { id = 1850, aura = { duration = 2.6, expirationTime = now + 2.6 } },
  }
  -- Fausses auras sans instance : ArmRow passe par l'expiration lisible (animation par OnUpdate)
  Sync(fake)
  C_Timer.After(2.7, function() if previewOn then Sync({ fake[1] }) end end)
  C_Timer.After(4.1, function() if previewOn then Sync({}) end end)
end

function MovementBuffs.SetPreview(on)
  if not root then return end
  on = on and Cfg().enabled ~= false
  if on == previewOn then return end
  previewOn = on
  for _, r in ipairs(rows) do r.state = "out" end
  if on then
    root:Show()
    PreviewCycle()
    previewTicker = ns.NewTicker(5, function() if previewOn then PreviewCycle() end end)
  else
    if previewTicker then previewTicker:Cancel(); previewTicker = nil end
    StartDriver()
    C_Timer.After(OUT_DUR + 0.05, RequestRefresh)
  end
  MovementBuffs.SetDraggable(on)
end

-- ── Position ────────────────────────────────────────────────────────────────

local function Place()
  local c = Cfg()
  root:ClearAllPoints()
  -- Ancre par le HAUT, au pixel pres (un CENTER sur une hauteur impaire tombe entre deux pixels)
  local px = PixelUnit(UIParent)
  local h = root:GetHeight() or 0
  root:SetPoint("TOP", UIParent, "BOTTOMLEFT",
    Snap(UIParent:GetWidth() * (c.anchorPctX or 0.5), px),
    Snap(UIParent:GetHeight() * (c.anchorPctY or 0.3) + h / 2, px))
end

function MovementBuffs.SetDraggable(on)
  if not root then return end
  local c = Cfg()
  local can = on and not c.locked
  root:SetMovable(true)
  root:EnableMouse(can and true or false)
  if can then
    root:RegisterForDrag("LeftButton")
    root:SetScript("OnDragStart", function(self) self:StartMoving() end)
    root:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local cx, cy = self:GetCenter()
      ns.DB.movementBuffs = ns.DB.movementBuffs or {}
      ns.DB.movementBuffs.anchorPctX = cx / UIParent:GetWidth()
      ns.DB.movementBuffs.anchorPctY = cy / UIParent:GetHeight()
      Place()
    end)
  else
    root:SetScript("OnDragStart", nil)
    root:SetScript("OnDragStop", nil)
  end
end

function MovementBuffs.ResetPosition()
  local d = ns.Defaults.movementBuffs or {}
  ns.DB.movementBuffs = ns.DB.movementBuffs or {}
  ns.DB.movementBuffs.anchorPctX, ns.DB.movementBuffs.anchorPctY = d.anchorPctX, d.anchorPctY
  if root then Place() end
end

-- Cadre de reperage (hitbox de la page Modules) : la taille d'une rangee, meme sans buff
function MovementBuffs.GetHoverFrame() return root end

-- ── Application des reglages ────────────────────────────────────────────────

function MovementBuffs.ApplySettings()
  if not root then return end
  trackMap, trackList = nil, nil
  local c = Cfg()
  local _, d, _, gap, bw, rh = Metrics(root)
  root:SetSize(bw * 2 + gap * 2 + d, rh)
  Place()
  for _, r in ipairs(rows) do StyleRow(r) end
  for _, r in ipairs(rows) do r.y = nil end
  for _, b in ipairs(nativeButtons) do pcall(StyleNativeButton, b) end
  -- Cree ici (hors combat) : le module demarre apres PLAYER_ENTERING_WORLD, qui ne suffisait donc pas
  if native == nil then EnsureNative() end
  if native then
    pcall(native.SetSize, native, root:GetWidth(), 400)
    SyncNativeGroups()
  end
  StartDriver()
  if c.enabled == false then
    if previewOn then MovementBuffs.SetPreview(false) end
    root:Hide()
    return
  end
  local panel = ns.SettingsPanel
  if panel and panel:IsShown() and panel.GetActiveCategory and panel:GetActiveCategory() == "movementBuffs" then
    MovementBuffs.SetPreview(true)
    MovementBuffs.SetDraggable(true)
  end
  RequestRefresh()
end

function MovementBuffs.Create(parent)
  if root then return end
  root = CreateFrame("Frame", "AishCoreMovementBuffs", parent or UIParent)
  root:SetFrameStrata("MEDIUM")
  root:SetClampedToScreen(true)
  driver = CreateFrame("Frame", nil, root)
  evt = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
                       "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
                       "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE" }) do
    pcall(evt.RegisterEvent, evt, e)
  end
  evt:RegisterUnitEvent("UNIT_AURA", "player")
  evt:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
      inCombat = false
      if native == nil then EnsureNative() elseif nativeDirty then SyncNativeGroups() end
    elseif event == "PLAYER_ENTERING_WORLD" then
      inCombat = InCombatLockdown() and true or false
      EnsureNative()
    end
    RequestRefresh()
  end)

  -- Apercu tant que la page du module est ouverte dans le panneau de reglages
  ns.NewTicker(0.25, function()
    local panel = ns.SettingsPanel
    local want = panel and panel:IsShown() and panel.GetActiveCategory and panel:GetActiveCategory() == "movementBuffs"
    if (want and true or false) ~= previewOn then MovementBuffs.SetPreview(want) end
  end)
  MovementBuffs.ApplySettings()
end

-- /aishmvb : etat de l'affichage natif (a lancer en combat, buff de deplacement actif)
SLASH_AISHMVB1 = "/aishmvb"
SlashCmdList["AISHMVB"] = function()
  local P = "|cff33ff99[AishCore mvb]|r "
  local ng = 0
  for _ in pairs(nativeGroups) do ng = ng + 1 end
  print(P .. "conteneur natif=" .. (native == nil and "non cree" or native == false and "ABSENT du client" or "ok")
    .. " groupes=" .. ng .. " initializeFrame=" .. diag.init .. " refuses (CanBeAccessedInContext)=" .. diag.denied
    .. " boutons=" .. #nativeButtons .. " combat=" .. tostring(inCombat) .. " rangees=" .. #rows)
  if native then
    print(P .. "alpha=" .. tostring(native:GetAlpha()) .. " visible=" .. tostring(native:IsVisible()))
  end
  if not trackMap then BuildTracking() end
  for _, id in ipairs(trackList) do
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if ok and a then print(P .. "lu par sort : " .. id) end
  end
end

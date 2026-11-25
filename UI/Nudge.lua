-- UI/Nudge.lua : deplacement au clavier des elements deverrouilles.
-- Clic sur un element deplacable (deverrouille) = selection ; fleches = 1 px, Maj+fleches = 10 px,
-- Echap ou clic ailleurs = deselection. La sauvegarde reutilise les handlers de drag de chaque module :
-- decalage des points, puis OnDragStart + OnDragStop rejoues avec StartMoving / StopMovingOrSizing neutralises
-- (le vrai StartMoving partirait de la position de la souris au dernier clic : saut de plusieurs dizaines de px).
local addonName, ns = ...

local N = {}
ns.Nudge = N

local handles = {}          -- poignee (frame cliquee) -> cible (frame deplacee)
local sel, selTarget        -- poignee / cible selectionnees
local started               -- cible dont le module a demande StartMoving pendant une sonde
local busy                  -- garde-fou de reentrance pendant une sonde

local box, hint, kb
local KEYS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
local function NoOp() end

-- Glisser de zero pixel : rejoue les scripts du module, position laissee telle quelle. Renvoie true si le module a
-- accepte le deplacement (il a demande StartMoving : element deverrouille), sinon rien n'est sauvegarde.
local function Replay(h)
  local t = handles[h]
  if not t or busy then return false end
  busy, started = true, nil
  local oStart, oStop = rawget(t, "StartMoving"), rawget(t, "StopMovingOrSizing")
  t.StartMoving = function(f) started = f end
  t.StopMovingOrSizing = NoOp
  local ok
  local ds = h:GetScript("OnDragStart")
  if ds then
    pcall(ds, h, "LeftButton")
    ok = started == t
    local stop = ok and h:GetScript("OnDragStop")
    if stop then pcall(stop, h) end
  else
    local md = h:GetScript("OnMouseDown")
    if md then pcall(md, h, "LeftButton") end
    ok = started == t
    local mu = ok and h:GetScript("OnMouseUp")
    if mu then pcall(mu, h, "LeftButton") end
  end
  t.StartMoving, t.StopMovingOrSizing = oStart, oStop
  busy = false
  return ok
end

local function Shift(f, dx, dy)
  local n = f:GetNumPoints()
  if n == 0 then return end
  local pts = {}
  for i = 1, n do pts[i] = { f:GetPoint(i) } end
  f:ClearAllPoints()
  for _, p in ipairs(pts) do f:SetPoint(p[1], p[2], p[3], (p[4] or 0) + dx, (p[5] or 0) + dy) end
end

local StopRepeat

function N.Clear()
  sel, selTarget = nil, nil
  if StopRepeat then StopRepeat() end
  if box then box:Hide() end
  if kb then
    kb:EnableKeyboard(false)
    kb:Hide()
  end
end

local function Valid()
  return sel and selTarget and sel:IsVisible() and selTarget:IsVisible() and sel:IsMouseEnabled()
    and not InCombatLockdown()
end

local function Nudge(dx, dy)
  if not Valid() then N.Clear(); return end
  Shift(selTarget, dx, dy)
  if not Replay(sel) then
    Shift(selTarget, -dx, -dy)   -- element reverrouille entre-temps : on annule
    N.Clear()
  end
  -- Sliders X / Y du GUI suivis (SW.TrackDB) : relus comme apres un glisser a la souris
  local SW = ns.SharedWidgets
  if SW and SW.SyncDBSliders then C_Timer.After(0, SW.SyncDBSliders) end
end

-- Poignee sous le curseur (la plus petite). Le cadre de survol des modules (GUI ouvert, cf. ModuleHoverOverlay)
-- recouvre l'element et recoit le clic : on regarde donc la position du curseur, pas le cadre qui a la souris.
-- Clic sur autre chose (panneau de reglages, fenetre du jeu...) : aucune poignee.
local HOVER_NAME = "AishCoreModuleHoverHighlight"
local function HandleUnderCursor()
  local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
  local top = foci[1]
  local onHandle = top and handles[top]
  if top and not onHandle and top ~= _G[HOVER_NAME] then return nil end
  if onHandle then return top end
  local best, bestA
  for h in pairs(handles) do
    if h:IsVisible() and h:IsMouseEnabled() and h:IsMouseOver() then
      local a = (h:GetWidth() or 0) * (h:GetHeight() or 0)
      if not bestA or a < bestA then best, bestA = h, a end
    end
  end
  return best
end

local Select

local function EnsureUI()
  if box then return end
  box = CreateFrame("Frame", nil, UIParent)
  box:SetFrameStrata("TOOLTIP")
  box:EnableMouse(false)
  local function Edge(p1, p2, w, h)
    local t = box:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(1, 0.82, 0, 0.9)
    t:SetPoint(p1); t:SetPoint(p2)
    if w then t:SetWidth(w) else t:SetHeight(h) end
  end
  Edge("TOPLEFT", "TOPRIGHT", nil, 1)
  Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
  Edge("TOPLEFT", "BOTTOMLEFT", 1)
  Edge("TOPRIGHT", "BOTTOMRIGHT", 1)
  hint = box:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.FONT_FALLBACK, 10, "OUTLINE")
  hint:SetTextColor(1, 0.82, 0)
  hint:SetPoint("BOTTOM", box, "TOP", 0, 3)
  box:Hide()

  -- Clavier : au-dessus du panneau de reglages (strate DIALOG)
  kb = CreateFrame("Frame", nil, UIParent)
  kb:SetFrameStrata("TOOLTIP")
  kb:SetFrameLevel(9000)
  kb:Hide()
  local heldKey, wait, ticker = nil, 0, CreateFrame("Frame")
  ticker:Hide()
  ticker:SetScript("OnUpdate", function(self, e)
    wait = wait - e
    if wait > 0 then return end
    wait = 0.04
    local d = heldKey and KEYS[heldKey]
    if not d then self:Hide(); return end
    local s = IsShiftKeyDown() and 10 or 1
    Nudge(d[1] * s, d[2] * s)
  end)
  StopRepeat = function() heldKey = nil; ticker:Hide() end
  kb:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    local d = KEYS[key]
    if d then
      self:SetPropagateKeyboardInput(false)
      local s = IsShiftKeyDown() and 10 or 1
      Nudge(d[1] * s, d[2] * s)
      heldKey, wait = key, 0.35
      ticker:Show()
    elseif key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      N.Clear()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  kb:SetScript("OnKeyUp", function(_, key) if key == heldKey then StopRepeat() end end)

  -- Element masque (fin du mode deverrouille, panneau ferme...) : deselection
  box:SetScript("OnUpdate", function() if not Valid() then N.Clear() end end)
end

Select = function(h)
  if InCombatLockdown() or not Replay(h) then return end
  EnsureUI()
  sel, selTarget = h, handles[h]
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", selTarget, "TOPLEFT", -2, 2)
  box:SetPoint("BOTTOMRIGHT", selTarget, "BOTTOMRIGHT", 2, -2)
  hint:SetText(ns.L["NUDGE_HINT"])
  box:Show()
  kb:Show()
  kb:EnableKeyboard(true)
  kb:SetPropagateKeyboardInput(true)
  return true
end

-- Clic gauche relache sur une poignee : selection (au tick suivant, le glisser reel eventuel est termine) ;
-- clic ailleurs : deselection. Combat : deselection.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
local hasGlobalUp = pcall(ev.RegisterEvent, ev, "GLOBAL_MOUSE_UP")
ev:SetScript("OnEvent", function(_, e, btn)
  if e == "PLAYER_REGEN_DISABLED" then N.Clear(); return end
  if btn ~= "LeftButton" or busy or InCombatLockdown() then return end
  local h = HandleUnderCursor()
  if not h then
    if sel then N.Clear() end
    return
  end
  if sel and handles[h] == selTarget then return end
  -- Element verrouille : la selection precedente tombe aussi
  C_Timer.After(0, function() if not (h:IsVisible() and Select(h)) and sel then N.Clear() end end)
end)

--- Rend une poignee de deplacement pilotable au clavier.
--- handle : frame qui recoit le clic (porte OnDragStart/OnDragStop, ou OnMouseDown/OnMouseUp) ;
--- target : frame reellement deplacee (StartMoving), handle par defaut.
function N.Attach(handle, target)
  if not handle or handles[handle] then return end
  handles[handle] = target or handle
  if hasGlobalUp then return end
  -- Client sans GLOBAL_MOUSE_UP : relachement du clic sur la poignee elle-meme
  handle:HookScript("OnMouseUp", function(h, btn)
    if btn ~= "LeftButton" or busy then return end
    C_Timer.After(0, function() if h:IsVisible() then Select(h) end end)
  end)
end

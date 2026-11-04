-- UI/PriorityBarPage.lua : apercu epingle de la page "Barre de rotation" (reste de la page : Build.PriorityBar, SettingsPanel.lua).
-- Les slots sont ceux du module (PriorityBar.NewPreviewSlot / StyleSlot / StartSlotGlow) : meme rendu qu'en jeu, a la meme
-- echelle, autour d'un cercle central fige et grise (ResourceCircle.NewPreviewDisc, reglages par defaut).
-- Clic sur un slot = tiroir de ses sorts. Dans le tiroir : glisser = priorite, clic droit = options (couleur du glow,
-- Camouflage pour Voleur / Druide, suppression), + = ajouter un sort.
local addonName, ns = ...
local L     = ns.L
local Theme = ns.Theme

local PAD, HINT_H  = 18, 14
local DPAD         = 6      -- marge interieure du tiroir
local CD_DEMO      = 12     -- duree du faux cooldown de l'apercu
local PROC_REPLAY  = 3.5    -- relance periodique de l'animation de proc
local PLUS_TEX     = "Interface\\AddOns\\AishCore\\Media\\UI\\plus.png"
local STEALTH_FALLBACK = { 0.58, 0.42, 0.86 }

-- Animations -------------------------------------------------------------------------------------------------------
-- Proprietes (a = alpha, x, y, s = echelle, h = hauteur) qui tendent vers leur cible en ease-out exponentiel ;
-- obj:_Apply() les pose a chaque frame. Une proprietete peut attendre (delay) avant de partir.
local active, settled = {}, {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
  local k = 1 - math.exp(-dt * 14)
  for obj in pairs(active) do
    local busy = false
    for _, t in pairs(obj._tw) do
      if t.delay and t.delay > 0 then
        t.delay = t.delay - dt
        busy = true
      elseif t.v ~= t.to then
        local d = t.to - t.v
        if math.abs(d) < 0.004 then t.v = t.to else t.v = t.v + d * k; busy = true end
      end
    end
    obj:_Apply()
    if not busy then
      active[obj] = nil
      if obj._onSettled then settled[#settled + 1] = obj end
    end
  end
  for i = #settled, 1, -1 do
    local obj = settled[i]
    settled[i] = nil
    local f = obj._onSettled
    obj._onSettled = nil
    if f then f(obj) end
  end
  if not next(active) then self:Hide() end
end)

local function Go(obj, prop, to, delay)
  obj._tw = obj._tw or {}
  local t = obj._tw[prop]
  if not t then t = { v = to }; obj._tw[prop] = t end
  t.to = to
  if delay then t.delay = delay end   -- sans delai precise, celui en cours est conserve
  active[obj] = true
  driver:Show()
end
local function Snap(obj, prop, v)
  obj._tw = obj._tw or {}
  obj._tw[prop] = { v = v, to = v }
end
local function V(obj, prop, def)
  local t = obj._tw and obj._tw[prop]
  if t then return t.v end
  return def
end
local function ApplyAlpha(self) self:SetAlpha(V(self, "a", 1)) end

-- Utilitaires ------------------------------------------------------------------------------------------------------
local function PB() return ns.Modules and ns.Modules.PriorityBar end
local function Cfg() return ns.GetCfg("priorityBar") or {} end

local function StealthColor()
  local CLR = ns.Modules and ns.Modules.Colors
  local cls = select(2, UnitClass("player"))
  return (CLR and CLR.GetForSpec and cls and CLR.GetForSpec(cls:lower(), CLR.STEALTH_ID, "powercircle")) or STEALTH_FALLBACK
end

local function SpellColor(sid)
  local sc = ns.DB and ns.DB.priorityBar and ns.DB.priorityBar.spellColors
  return sc and sc[sid]
end

local function Override(sid)
  if sid and C_Spell and C_Spell.GetOverrideSpell then
    local ok, ov = pcall(C_Spell.GetOverrideSpell, sid)
    if ok and ov and ov > 0 then return ov end
  end
  return sid
end

-- Niveaux des sous-frames d'un slot (SetFrameLevel ne les entraine pas)
local function Relevel(s, base)
  s:SetFrameLevel(base)
  if s.innerFrame    then s.innerFrame:SetFrameLevel(base + 1) end
  if s.glowContainer then s.glowContainer:SetFrameLevel(base + 2) end
  if s.cooldown      then s.cooldown:SetFrameLevel(base + 2) end
  if s._cdOverlay    then s._cdOverlay:SetFrameLevel(base + 6) end
  if s._deco         then s._deco:SetFrameLevel(base + 8) end
end

-- Coin "Camouflage" (triangle en haut a gauche) + surbrillance de survol
local function Decorate(s)
  local deco = CreateFrame("Frame", nil, s)
  deco:SetAllPoints(s)
  s._deco = deco
  local c = deco:CreateTexture(nil, "OVERLAY")
  c:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
  c:Hide()
  s._corner = c
  local hl = deco:CreateTexture(nil, "OVERLAY", nil, -1)
  hl:SetAllPoints(s)
  hl:SetColorTexture(1, 1, 1, 0.14)
  hl:SetBlendMode("ADD")
  hl:Hide()
  s._hl = hl
  -- Cible de depot (glisser un sort sur un autre slot)
  local drop = deco:CreateTexture(nil, "OVERLAY", nil, -2)
  drop:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 3)
  drop:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, -3)
  drop:SetColorTexture(0.3, 0.95, 0.3, 0.45)
  drop:SetBlendMode("ADD")
  drop:Hide()
  s._drop = drop
  -- Croix de suppression (sort glisse hors de la barre)
  local del = deco:CreateTexture(nil, "OVERLAY", nil, 2)
  del:SetTexture("Interface\\Buttons\\UI-StopButton")
  del:SetVertexColor(1, 0.25, 0.25, 1)
  del:SetPoint("CENTER", s, "TOPRIGHT", -2, -2)
  del:Hide()
  s._del = del
  s:EnableMouse(true)
  s:HookScript("OnEnter", function(self) self._hl:Show() end)
  s:HookScript("OnLeave", function(self) self._hl:Hide() end)
end

local function IndexOf(t, v)
  for i, x in ipairs(t) do if x == v then return i end end
end

local function SetCorner(s, on)
  local c = s._corner
  if not on then c:Hide(); return end
  local w = math.max(7, math.floor((s:GetWidth() or 34) * 0.36 + 0.5))
  local col = StealthColor()
  c:SetSize(w, w)
  c:SetColorTexture(col[1], col[2], col[3], 1)
  c:SetVertexOffset(4, -w, 0)   -- coin bas-droit ramene sur le bas-gauche : triangle
  c:Show()
end

function ns.BuildPriorityBarPreview(container)
  local PBm = PB()
  if not (PBm and PBm.NewPreviewSlot) then return function() end end

  local pin = CreateFrame("Frame", nil, container, "BackdropTemplate")
  pin:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  pin:SetBackdropBorderColor(unpack(Theme.border))
  pin:SetHeight(100)
  ns.SharedWidgets.ApplyPreviewScreen(pin)
  -- Encart pose dans la page, sous son titre (plus epingle en haut du panneau) : la page le place
  -- (container._pbPin) et redispose son flux quand sa hauteur change (container._pbOnResize).
  container._pbPin = pin
  local function SetPinHeight(h)
    if math.abs((pin:GetHeight() or 0) - h) < 0.5 then return end
    pin:SetHeight(h)
    if container._pbOnResize then container._pbOnResize() end
  end
  -- Le voile sombre du fond est pose par ApplyPreviewScreen ; ce cadre ne porte plus que le texte d'aide
  local veil = CreateFrame("Frame", nil, pin)
  veil:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
  veil:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
  veil:SetFrameLevel(pin:GetFrameLevel() + 1)
  local hint = veil:CreateFontString(nil, "OVERLAY")
  hint:SetFont(ns.Media.fontGui, 10)
  hint:SetTextColor(0.85, 0.8, 0.68, 0.9)
  hint:SetPoint("BOTTOM", pin, "BOTTOM", 0, 6)
  hint:SetText(L["PB_PREVIEW_HINT"])

  local built, pinH = false, 0
  local stage, catcher, dim, circle, drawer, drawerBg, plus, menuLayer
  local tops = {}
  local slots = {}
  local D = { slot = nil, items = {}, pool = {}, gen = 0 }
  local M = { item = nil }
  local menuBtns = {}
  local size, step = 34, 40

  local function Data() slots = PBm.GetCurrentSpecSlots() or {} end
  local function LayoutDef()
    local id = PBm.GetCurrentSpecLayout and PBm.GetCurrentSpecLayout()
    for _, d in ipairs(PBm.LAYOUT_DEFS or {}) do if d.id == id then return d end end
    return PBm.LAYOUT_DEFS[1]
  end
  local function IsStealth(slotIdx, sid)
    local d = slots[slotIdx]
    return d and d.stealth and d.stealth[sid] and true or false
  end

  -- Demonstration "en combat" d'un slot du haut ----------------------------------------------------------------
  -- Cycle de 4 : glow rotation / cooldown en cours / glow procs + charges / hors de portee. Raccourci partout.
  local function ApplyDemo(s, i)
    local cfg = Cfg()
    PBm.StopSlotGlow(s)
    s._demoCD = false
    s.cooldown:Clear()
    s.icon:SetDesaturated(false)
    s.icon:SetVertexColor(1, 1, 1, 1)
    s.chargeText:Hide()
    s.keybindText:Hide()
    if not s.currentSpellID then return end
    local st = (i - 1) % 4 + 1
    if st == 1 then
      PBm.StartSlotGlow(s, "rot")
    elseif st == 2 then
      local showSwipe, showText = cfg.showCooldownSwipe ~= false, cfg.showCooldownText ~= false
      if showSwipe or showText then
        s._demoCD = true
        s.cooldown:SetCooldown(GetTime() - 3, CD_DEMO)
        s.cooldown:SetDrawSwipe(showSwipe)
        s.cooldown:SetHideCountdownNumbers(not showText)
        local col = cfg.cooldownTextColor or { 1, 1, 1, 1 }
        for _, r in pairs({ s.cooldown:GetRegions() }) do
          if r:IsObjectType("FontString") then
            if not pcall(r.SetFont, r, cfg.cooldownFont or ns.FONT_FALLBACK, cfg.cooldownFontSize or 14, "OUTLINE") then
              r:SetFont(ns.FONT_FALLBACK, cfg.cooldownFontSize or 14, "OUTLINE")
            end
            r:SetTextColor(col[1], col[2], col[3], col[4] or 1)
          end
        end
      end
      if cfg.desaturateOnCooldown then s.icon:SetDesaturated(true) end
    elseif st == 3 then
      PBm.StartSlotGlow(s, cfg.procGlowEnabled and "proc" or "rot")
    elseif cfg.outOfRangeTint then
      local tint
      if cfg.outOfRangeUseTheme then
        local CLR = ns.Modules and ns.Modules.Colors
        tint = CLR and CLR.Get and CLR.Get("powercircle")
      end
      tint = tint or cfg.outOfRangeColor or { 0.9, 0.25, 0.25, 1 }
      s.icon:SetDesaturated(true)
      s.icon:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
    end
    if cfg.showCharges then
      -- Charges reelles si le sort en a (valeurs secretes en combat : lecture sous pcall), sinon "2" de demonstration
      local ok, txt = pcall(function()
        local ch = C_Spell.GetSpellCharges(s._baseID)
        if ch and ch.maxCharges > 1 then return ch.currentCharges end
      end)
      if not ok then txt = nil end
      if txt == nil and st == 3 then txt = 2 end
      if txt ~= nil then s.chargeText:SetText(txt); s.chargeText:Show() end
    end
    if cfg.showKeybind then
      s.keybindText:SetText(ns.GetKeybindForSpell(s.currentSpellID) or tostring(i))
      s.keybindText:Show()
    end
  end

  -- Sort affiche par un slot du haut : le premier hors Camouflage (comme hors furtivite), sinon le premier
  local function ShowTop(i, animate)
    local s = tops[i]
    local d = slots[i] or {}
    local pick
    for _, sid in ipairs(d.spellIDs or {}) do
      if not (d.stealth and d.stealth[sid]) then pick = sid; break end
    end
    pick = pick or (d.spellIDs or {})[1]
    local shown = Override(pick)
    if animate and shown and shown ~= s.currentSpellID and s.currentSpellID then PBm.PlaySlideIn(s) end
    s._baseID = pick
    s.currentSpellID = shown
    if shown then
      s.icon:SetTexture(PBm.GetSpellIcon(shown) or 134400)
      s.icon:SetAlpha(1)
    else
      s.icon:SetTexture(134400)   -- slot vide : meme placeholder que la vraie barre panneau ouvert
      s.icon:SetAlpha(0.55)
    end
    ApplyDemo(s, i)
    if not shown then s.icon:SetDesaturated(true) end
    SetCorner(s, pick and IsStealth(i, pick))
  end

  -- Assombrissement : tout ce qui n'est pas en cours d'edition passe en retrait --------------------------------
  local function UpdateDim()
    local open, menu = D.slot ~= nil, M.item ~= nil
    Go(catcher, "a", menu and 0.62 or (open and 0.28 or 0))
    catcher:EnableMouse(open)
    local dragging = D.press and D.press.dragging
    for i, s in ipairs(tops) do
      -- Pendant un glisser, les autres slots redeviennent visibles : ce sont des cibles de depot
      Go(s, "a", (not open) and 1 or ((i == D.slot and not menu) and 1 or (dragging and 0.9 or (menu and 0.28 or 0.5))))
    end
    Go(circle, "a", open and (menu and 0.3 or 0.5) or 1)
    if not open then return end   -- fermeture : le tiroir gere ses propres fondus
    Go(drawerBg, "a", menu and 0.45 or 1)
    for _, it in ipairs(D.items) do Go(it, "a", (menu and it ~= M.item) and 0.25 or 1) end
    Go(plus, "a", menu and 0.25 or 1)
  end

  -- Tiroir -----------------------------------------------------------------------------------------------------
  local function PosY(k) return -(DPAD + (k - 1) * step) end
  local function BgH(n) return DPAD * 2 + n * step + size end

  local function ApplyItem(self)
    local sc = math.max(0.05, V(self, "s", 1))
    self:SetScale(sc)
    self:ClearAllPoints()
    self:SetPoint("CENTER", drawer, "TOP", V(self, "x", 0) / sc, (V(self, "y", 0) - size / 2) / sc)
    self:SetAlpha(V(self, "a", 1))
  end

  -- Positions cibles ; pendant un glisser au-dessus de la colonne, une place reste libre a D.press.idx
  local function Relayout()
    local n = #D.items
    local p = D.press
    local gap = p and p.dragging and p.zone == "col" and p.idx or nil
    for k, it in ipairs(D.items) do
      Go(it, "x", 0)
      Go(it, "y", PosY((gap and k >= gap) and (k + 1) or k))
    end
    local m = n + (gap and 1 or 0)
    Go(plus, "y", PosY(m + 1))
    Go(drawerBg, "h", BgH(m))
  end

  local function Commit()
    if InCombatLockdown() or not D.slot then return end
    local ids = {}
    for _, it in ipairs(D.items) do ids[#ids + 1] = it.sid end
    PBm.SetSlotSpells(D.slot, ids)
    Data()
    ShowTop(D.slot, true)
  end

  local CloseMenu, OpenMenu

  local function Cursor()
    local x, y = GetCursorPosition()
    local e = drawer:GetEffectiveScale()
    return x / e, y / e
  end

  local function Release(it)
    PBm.StopSlotGlow(it)
    it:Hide()
    it._tw = nil
    active[it] = nil
    D.pool[#D.pool + 1] = it
  end

  local function Acquire(sid)
    local it = table.remove(D.pool)
    if not it then
      it = PBm.NewPreviewSlot(drawer, 0)
      Decorate(it)
      Relevel(it, drawer:GetFrameLevel() + 2)
      it._Apply = ApplyItem
      it:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        if M.item then CloseMenu(); return end
        if InCombatLockdown() then return end   -- les slots ne s'editent pas en combat
        local cx, cy = Cursor()
        D.press = { item = self, cx = cx, cy = cy, x0 = V(self, "x", 0), y0 = V(self, "y", 0) }
      end)
      it:SetScript("OnMouseUp", function(self, btn)
        if btn == "RightButton" then
          if D.press then return end
          if M.item == self then CloseMenu() else OpenMenu(self) end
        end
      end)
      it:HookScript("OnEnter", function(self)
        if D.press or M.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
        GameTooltip:SetSpellByID(self.sid)
        GameTooltip:AddLine(L["PB_PREVIEW_ITEM_TT"], 0.7, 0.9, 1, true)
        GameTooltip:Show()
      end)
      it:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    it.sid = sid
    it.currentSpellID = Override(sid)
    PBm.StyleSlot(it)
    it.cooldown:Clear()
    it.chargeText:Hide()
    it.keybindText:Hide()
    it.icon:SetTexture(PBm.GetSpellIcon(it.currentSpellID) or 134400)
    it.icon:SetDesaturated(false)
    it.icon:SetVertexColor(1, 1, 1, 1)
    it.icon:SetAlpha(1)
    SetCorner(it, IsStealth(D.slot, sid))
    it:Show()
    return it
  end

  -- Ajoute un sort a un autre slot (depot), en gardant son marquage Camouflage
  local function AddToSlot(j, sid, stealth)
    local ids = { unpack((slots[j] and slots[j].spellIDs) or {}) }
    for _, x in ipairs(ids) do if x == sid then return end end
    ids[#ids + 1] = sid
    PBm.SetSlotSpells(j, ids)
    if stealth then PBm.SetSlotSpellStealth(j, sid, true) end
  end

  -- Glisser-deposer, comme sur la barre du grimoire : l'icone suit le curseur. Au-dessus de la colonne = nouvelle
  -- priorite (les autres s'ecartent), sur un autre slot = deplacement, ailleurs = suppression (croix rouge).
  local function DragZone(p)
    local cx, cy = Cursor()
    if tops[D.slot]:IsMouseOver() then return "col", 1 end
    for j, s in ipairs(tops) do
      if j ~= D.slot and s:IsShown() and s:IsMouseOver() then return "slot", j end
    end
    local left, top = drawer:GetLeft(), drawer:GetTop()
    if not (left and top) then return "col" end
    local rx, ry = cx - (left + drawer:GetWidth() / 2), cy - top
    local n = #D.items
    if math.abs(rx) <= size + DPAD and ry <= size * 0.25 and ry >= -(BgH(n + 1) + size * 0.5) then
      local y = V(p.item, "y", 0)
      return "col", math.max(1, math.min(n + 1, math.floor((PosY(1) - y) / step + 0.5) + 1))
    end
    return "del"
  end

  local function SetDragLook(it, zone, target, old)
    if old and tops[old] then tops[old]._drop:Hide() end
    if zone == "slot" then tops[target]._drop:Show() end
    it._del:SetSize(size * 0.5, size * 0.5)
    it._del:SetShown(zone == "del")
    if zone == "del" then it.icon:SetVertexColor(1, 0.45, 0.45, 1) else it.icon:SetVertexColor(1, 1, 1, 1) end
  end

  local function EndDrag(p)
    local it = p.item
    D.press = nil
    if p.target and tops[p.target] then tops[p.target]._drop:Hide() end
    it._del:Hide()
    it.icon:SetVertexColor(1, 1, 1, 1)
    Relevel(it, drawer:GetFrameLevel() + 2)
    if p.zone == "col" then
      table.insert(D.items, p.idx, it)
      Go(it, "s", 1)
      Relayout()
      if p.idx ~= p.from then Commit() end
    else
      if p.zone == "slot" and not InCombatLockdown() then
        local s = tops[p.target]
        local tx, ty = s:GetCenter()
        local left, top = drawer:GetLeft(), drawer:GetTop()
        if tx and left then
          Go(it, "x", tx - (left + drawer:GetWidth() / 2))
          Go(it, "y", ty - top + size / 2)
        end
        Go(it, "a", 0); Go(it, "s", 0.6)
      else
        Go(it, "a", 0); Go(it, "s", 0.4)
      end
      it._onSettled = function(self) if not IndexOf(D.items, self) then Release(self) end end
      Relayout()
      local stealth = IsStealth(D.slot, it.sid)
      Commit()
      if p.zone == "slot" and not InCombatLockdown() then
        AddToSlot(p.target, it.sid, stealth)
        Data()
        ShowTop(p.target, true)
      end
    end
    UpdateDim()
  end

  local function DragTick()
    local p = D.press
    if not p then return end
    local it = p.item
    local cx, cy = Cursor()
    local dx, dy = cx - p.cx, cy - p.cy
    if not p.dragging then
      if math.abs(dx) < 4 and math.abs(dy) < 4 then
        if not IsMouseButtonDown("LeftButton") then D.press = nil end
        return
      end
      p.dragging = true
      p.from = IndexOf(D.items, it)
      p.idx, p.zone = p.from, "col"
      table.remove(D.items, p.from)   -- l'icone glissee sort de la liste ; sa place est reservee (Relayout)
      GameTooltip:Hide()
      Relevel(it, drawer:GetFrameLevel() + 16)
      Go(it, "s", 1.1)
      UpdateDim()
    end
    Snap(it, "x", p.x0 + dx)
    Snap(it, "y", p.y0 + dy)
    it:_Apply()
    local zone, arg = DragZone(p)
    local idx = (zone == "col") and arg or p.idx
    local target = (zone == "slot") and arg or nil
    if zone ~= p.zone or idx ~= p.idx or target ~= p.target then
      SetDragLook(it, zone, target, p.target)
      p.zone, p.idx, p.target = zone, idx, target
      Relayout()
    end
    if not IsMouseButtonDown("LeftButton") then EndDrag(p) end
  end

  local function CloseDrawer(instant)
    if ns.PBSpellPicker then ns.PBSpellPicker:Hide() end
    if M.item then CloseMenu(instant) end
    local p = D.press
    D.press = nil
    if p and p.dragging then   -- icone glissee hors de la liste : on la rend au pool
      if p.target and tops[p.target] then tops[p.target]._drop:Hide() end
      p.item._del:Hide()
      Relevel(p.item, drawer:GetFrameLevel() + 2)
      Release(p.item)
    end
    if not D.slot and not instant then return end
    D.slot = nil
    D.gen = D.gen + 1
    if instant then
      for _, it in ipairs(D.items) do Release(it) end
      wipe(D.items)
      plus:Hide()
      Snap(drawerBg, "h", 0); drawerBg:_Apply(); drawerBg:Hide()
      Snap(catcher, "a", 0); catcher:_Apply()
      catcher:EnableMouse(false)
      Snap(circle, "a", 1); circle:_Apply()
      for _, s in ipairs(tops) do Snap(s, "a", 1); s:_Apply() end
      return
    end
    local gen = D.gen
    for _, it in ipairs(D.items) do Go(it, "y", 0); Go(it, "a", 0); Go(it, "s", 0.8) end
    Go(plus, "y", 0); Go(plus, "a", 0); Go(plus, "s", 0.8)
    Go(drawerBg, "h", 0)
    Go(drawerBg, "a", 0)
    drawerBg._onSettled = function()
      if D.gen ~= gen then return end
      for _, it in ipairs(D.items) do Release(it) end
      wipe(D.items)
      plus:Hide()
      drawerBg:Hide()
    end
    UpdateDim()
  end

  local function OpenDrawer(i)
    if D.slot == i then CloseDrawer(); return end
    CloseDrawer(true)
    D.slot = i
    D.gen = D.gen + 1
    drawer:ClearAllPoints()
    drawer:SetPoint("TOP", tops[i], "BOTTOM", 0, -(4 + ((Cfg().showBorder ~= false) and (Cfg().borderSize or 2) or 0)))
    drawer:SetSize(size + DPAD * 2, 1)
    local ids = (slots[i] and slots[i].spellIDs) or {}
    for k, sid in ipairs(ids) do
      local it = Acquire(sid)
      D.items[k] = it
      Snap(it, "y", 0); Snap(it, "a", 0); Snap(it, "s", 0.8); it:_Apply()
      Go(it, "y", PosY(k), (k - 1) * 0.03); Go(it, "a", 1, (k - 1) * 0.03); Go(it, "s", 1, (k - 1) * 0.03)
    end
    local n = #ids
    plus:SetSize(size, size)
    plus:Show()
    Snap(plus, "y", 0); Snap(plus, "a", 0); Snap(plus, "s", 0.8); plus:_Apply()
    Go(plus, "y", PosY(n + 1), n * 0.03); Go(plus, "a", 1, n * 0.03); Go(plus, "s", 1, n * 0.03)
    drawerBg:SetWidth(size + DPAD * 2)
    drawerBg:Show()
    Snap(drawerBg, "a", 1)
    Snap(drawerBg, "h", 0)
    Go(drawerBg, "h", BgH(n))
    UpdateDim()
  end

  -- Glisser direct depuis un slot du haut (sans ouvrir son tiroir) : le sort affiche part sur un autre slot, ou
  -- hors de la barre pour etre supprime. Relache sur son propre slot = annule. Un simple clic ouvre le tiroir.
  local T = { press = nil, ghost = nil }

  local function StagePos()
    local x, y = GetCursorPosition()
    local e = stage:GetEffectiveScale()
    return x / e - (stage:GetLeft() or 0), y / e - (stage:GetBottom() or 0)
  end

  local function SlotCenter(s)
    local x, y = s:GetCenter()
    return (x or 0) - (stage:GetLeft() or 0), (y or 0) - (stage:GetBottom() or 0)
  end

  local function Ghost()
    local g = T.ghost
    if not g then
      g = PBm.NewPreviewSlot(stage, 0)
      Decorate(g)
      g:EnableMouse(false)
      Relevel(g, stage:GetFrameLevel() + 90)
      g._Apply = function(self)
        local sc = math.max(0.05, V(self, "s", 1))
        self:SetScale(sc)
        self:ClearAllPoints()
        self:SetPoint("CENTER", stage, "BOTTOMLEFT", V(self, "x", 0) / sc, V(self, "y", 0) / sc)
        self:SetAlpha(V(self, "a", 1))
      end
      T.ghost = g
    end
    return g
  end

  local function TopZone(src)
    for j, s in ipairs(tops) do
      if s:IsShown() and s:IsMouseOver() then return (j == src) and "back" or "slot", j end
    end
    return "del"
  end

  local function TopDragEnd(p)
    T.press = nil
    T.lastEnd = GetTime()
    local g, src = T.ghost, tops[p.src]
    if p.target then tops[p.target]._drop:Hide() end
    g._del:Hide()
    g.icon:SetVertexColor(1, 1, 1, 1)
    Go(src, "a", 1)
    g._onSettled = function(self) self:Hide() end
    if p.zone == "back" or InCombatLockdown() then
      local x, y = SlotCenter(src)
      Go(g, "x", x); Go(g, "y", y); Go(g, "s", 1); Go(g, "a", 0)
      return
    end
    local ids = {}
    for _, sid in ipairs((slots[p.src] and slots[p.src].spellIDs) or {}) do
      if sid ~= p.sid then ids[#ids + 1] = sid end
    end
    local stealth = IsStealth(p.src, p.sid)
    PBm.SetSlotSpells(p.src, ids)
    if p.zone == "slot" then
      local x, y = SlotCenter(tops[p.target])
      Go(g, "x", x); Go(g, "y", y); Go(g, "s", 0.6); Go(g, "a", 0)
      Data()
      AddToSlot(p.target, p.sid, stealth)
    else
      Go(g, "s", 0.4); Go(g, "a", 0)
    end
    Data()
    ShowTop(p.src, true)
    if p.zone == "slot" then ShowTop(p.target, true) end
  end

  local function TopDragTick()
    local p = T.press
    if not p then return end
    local x, y = StagePos()
    if not p.dragging then
      if math.abs(x - p.x0) < 4 and math.abs(y - p.y0) < 4 then
        if not IsMouseButtonDown("LeftButton") then T.press = nil end
        return
      end
      p.dragging = true
      if D.slot then CloseDrawer(true) end
      GameTooltip:Hide()
      local src = tops[p.src]
      local g = Ghost()
      PBm.StyleSlot(g)
      g.cooldown:Clear(); g.chargeText:Hide(); g.keybindText:Hide()
      g.currentSpellID = src.currentSpellID
      g.icon:SetTexture(src.icon:GetTexture())
      g.icon:SetDesaturated(false)
      g.icon:SetVertexColor(1, 1, 1, 1)
      SetCorner(g, IsStealth(p.src, p.sid))
      local cx, cy = SlotCenter(src)
      p.dx, p.dy = cx - p.x0, cy - p.y0   -- garde la prise : l'icone ne saute pas sous le curseur
      Snap(g, "x", cx); Snap(g, "y", cy); Snap(g, "a", 1); Snap(g, "s", 1); g:_Apply()
      Go(g, "s", 1.1)
      g:Show()
      Go(src, "a", 0.35)
      p.zone = "back"
    end
    local g = T.ghost
    Snap(g, "x", x + p.dx); Snap(g, "y", y + p.dy)
    g:_Apply()
    local zone, j = TopZone(p.src)
    local target = (zone == "slot") and j or nil
    if zone ~= p.zone or target ~= p.target then
      if p.target then tops[p.target]._drop:Hide() end
      if target then tops[target]._drop:Show() end
      g._del:SetSize(size * 0.5, size * 0.5)
      g._del:SetShown(zone == "del")
      if zone == "del" then g.icon:SetVertexColor(1, 0.45, 0.45, 1) else g.icon:SetVertexColor(1, 1, 1, 1) end
      p.zone, p.target = zone, target
    end
    if not IsMouseButtonDown("LeftButton") then TopDragEnd(p) end
  end

  -- Options au clic droit : couleur du glow (gauche), Camouflage (dessus), suppression (droite) ------------------
  local function MenuPos(which)
    local bs = menuBtns.color:GetWidth()
    local off = size / 2 + 5 + bs / 2
    if which == "color" then return -off, 0 end
    if which == "remove" then return off, 0 end
    return 0, off
  end

  local function ApplyMenuBtn(self)
    local sc = math.max(0.05, V(self, "s", 1))
    self:SetScale(sc)
    self:ClearAllPoints()
    if M.anchor then self:SetPoint("CENTER", M.anchor, "CENTER", V(self, "x", 0) / sc, V(self, "y", 0) / sc) end
    self:SetAlpha(V(self, "a", 0))
  end

  local function RefreshMenuState()
    local it = M.item
    if not it then return end
    local c = SpellColor(it.sid)
    if c then
      menuBtns.color._swatch:SetVertexColor(c[1], c[2], c[3], 1)
    else
      local g = Cfg().glowColor or { 1, 0.85, 0, 1 }
      menuBtns.color._swatch:SetVertexColor(g[1], g[2], g[3], 1)
    end
    local on = IsStealth(D.slot, it.sid)
    local sc = StealthColor()
    if on then menuBtns.eye._ico:SetVertexColor(sc[1], sc[2], sc[3], 1) else menuBtns.eye._ico:SetVertexColor(0.55, 0.55, 0.55, 1) end
    menuBtns.eye._ring:SetVertexColor(on and sc[1] or 0.3, on and sc[2] or 0.3, on and sc[3] or 0.3, 1)
  end

  -- Glow du sort edite (sa couleur) et des slots du haut qui l'affichent
  local function RefreshGlows()
    if M.item then
      PBm.StopSlotGlow(M.item)
      PBm.StartSlotGlow(M.item, "rot")
    end
    for i, s in ipairs(tops) do
      if s:IsShown() and s.isHighlighted then ApplyDemo(s, i) end
    end
  end

  OpenMenu = function(it)
    if M.item then CloseMenu(true) end
    GameTooltip:Hide()
    M.item, M.anchor = it, it
    PBm.StartSlotGlow(it, "rot")
    local stealthOK = PBm.StealthClass and PBm.StealthClass()
    for key, b in pairs(menuBtns) do
      if key ~= "eye" or stealthOK then
        b:Show()
        local mx, my = MenuPos(key)
        Snap(b, "x", 0); Snap(b, "y", 0); Snap(b, "a", 0); Snap(b, "s", 0.4); b:_Apply()
        Go(b, "x", mx); Go(b, "y", my); Go(b, "a", 1); Go(b, "s", 1)
        b._onSettled = nil
      else
        b:Hide()
      end
    end
    RefreshMenuState()
    UpdateDim()
  end

  CloseMenu = function(instant)
    local it = M.item
    if not it then return end
    M.item = nil
    PBm.StopSlotGlow(it)
    for _, b in pairs(menuBtns) do
      if instant then
        b:Hide()
      else
        Go(b, "x", 0); Go(b, "y", 0); Go(b, "a", 0); Go(b, "s", 0.4)
        b._onSettled = function(self) if not M.item then self:Hide() end end
      end
    end
    UpdateDim()
  end

  local function MakeMenuBtn(key, bs)
    local b = CreateFrame("Button", nil, menuLayer)
    b:SetSize(bs, bs)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(ns.Media.circle)
    bg:SetAllPoints()
    bg:SetVertexColor(0.04, 0.04, 0.05, 0.95)
    local ring = b:CreateTexture(nil, "BORDER")
    ring:SetTexture(ns.Media.circle)
    ring:SetPoint("CENTER")
    ring:SetSize(bs - 2, bs - 2)
    ring:SetVertexColor(0.3, 0.3, 0.3, 1)
    local inner = b:CreateTexture(nil, "ARTWORK", nil, -1)
    inner:SetTexture(ns.Media.circle)
    inner:SetPoint("CENTER")
    inner:SetSize(bs - 5, bs - 5)
    inner:SetVertexColor(0.04, 0.04, 0.05, 1)
    b._ring = ring
    b._Apply = ApplyMenuBtn
    b:Hide()
    b:SetScript("OnLeave", function() GameTooltip:Hide(); ring:SetAlpha(1) end)
    menuBtns[key] = b
    return b
  end

  local function BuildMenu(bs)
    if menuBtns.color then
      for _, b in pairs(menuBtns) do
        b:SetSize(bs, bs)
        b._ring:SetSize(bs - 2, bs - 2)
      end
      menuBtns.color._swatch:SetSize(bs - 9, bs - 9)
      menuBtns.eye._ico:SetSize(bs * 0.66, bs * 0.66)
      menuBtns.remove._ico:SetSize(bs * 0.56, bs * 0.56)
      return
    end
    -- Couleur du glow : gauche = selecteur, droit = couleur globale
    local col = MakeMenuBtn("color", bs)
    local sw = col:CreateTexture(nil, "ARTWORK")
    sw:SetTexture(ns.Media.circle)
    sw:SetPoint("CENTER")
    sw:SetSize(bs - 9, bs - 9)
    col._swatch = sw
    col:SetScript("OnClick", function(_, btn)
      local it = M.item
      if not it then return end
      local sid = it.sid
      ns.DB.priorityBar = ns.DB.priorityBar or {}
      ns.DB.priorityBar.spellColors = ns.DB.priorityBar.spellColors or {}
      local store = ns.DB.priorityBar.spellColors
      if btn == "RightButton" then
        store[sid] = nil
        RefreshMenuState(); RefreshGlows()
        return
      end
      local cur = store[sid] or Cfg().glowColor or { 1, 0.85, 0, 1 }
      local function Apply(r, g, b, a)
        store[sid] = { r, g, b, a or 1 }
        RefreshMenuState(); RefreshGlows()
      end
      ColorPickerFrame:SetupColorPickerAndShow({
        r = cur[1], g = cur[2], b = cur[3], opacity = cur[4] or 1, hasOpacity = true,
        swatchFunc = function()
          local r, g, b = ColorPickerFrame:GetColorRGB()
          Apply(r, g, b, ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1)
        end,
        opacityFunc = function()
          local r, g, b = ColorPickerFrame:GetColorRGB()
          Apply(r, g, b, ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1)
        end,
        cancelFunc = function(prev)
          if prev then Apply(prev.r or cur[1], prev.g or cur[2], prev.b or cur[3], prev.opacity or cur[4] or 1) end
        end,
      })
    end)
    col:SetScript("OnEnter", function(self)
      self._ring:SetAlpha(0.6)
      GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
      GameTooltip:SetText(L["SETTINGS_PB_HIGHLIGHT_COLOR"], 1, 1, 1)
      GameTooltip:AddLine(L["SETTINGS_PB_HIGHLIGHT_COLOR_TT1"], 0.7, 0.7, 0.7, true)
      GameTooltip:AddLine(L["SETTINGS_PB_HIGHLIGHT_COLOR_TT2"], 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)

    -- Camouflage (Voleur / Druide) : sort affiche seulement en furtivite
    local eye = MakeMenuBtn("eye", bs)
    local ei = eye:CreateTexture(nil, "ARTWORK")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("socialqueuing-icon-eye") then
      ei:SetAtlas("socialqueuing-icon-eye")
    else
      ei:SetTexture(132320)   -- Ability_Stealth
      ei:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    ei:SetPoint("CENTER")
    ei:SetSize(bs * 0.66, bs * 0.66)
    eye._ico = ei
    eye:SetScript("OnClick", function()
      local it = M.item
      if not it or InCombatLockdown() then return end
      PBm.SetSlotSpellStealth(D.slot, it.sid, not IsStealth(D.slot, it.sid))
      Data()
      SetCorner(it, IsStealth(D.slot, it.sid))
      RefreshMenuState()
      ShowTop(D.slot, true)
    end)
    eye:SetScript("OnEnter", function(self)
      self._ring:SetAlpha(0.6)
      GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
      GameTooltip:SetText(L["PB_STEALTH_SPELL"], 1, 1, 1)
      GameTooltip:AddLine(L["PB_STEALTH_SPELL_TT"], 0.7, 0.7, 0.7, true)
      GameTooltip:Show()
    end)

    -- Suppression
    local rm = MakeMenuBtn("remove", bs)
    local ri = rm:CreateTexture(nil, "ARTWORK")
    ri:SetTexture("Interface\\Buttons\\UI-StopButton")
    ri:SetVertexColor(0.95, 0.3, 0.3, 1)
    ri:SetPoint("CENTER")
    ri:SetSize(bs * 0.56, bs * 0.56)
    rm._ico = ri
    rm:SetScript("OnClick", function()
      local it = M.item
      if not it or InCombatLockdown() then return end
      CloseMenu()
      local idx = IndexOf(D.items, it)
      if idx then table.remove(D.items, idx) end
      Relevel(it, drawer:GetFrameLevel() + 2)
      Go(it, "a", 0); Go(it, "s", 0.5)
      it._onSettled = function(self) if not IndexOf(D.items, self) then Release(self) end end
      Relayout()
      Commit()
      UpdateDim()
    end)
    rm:SetScript("OnEnter", function(self)
      self._ring:SetAlpha(0.6)
      GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
      GameTooltip:SetText(L["PB_PREVIEW_REMOVE"], 1, 1, 1)
      GameTooltip:Show()
    end)
  end

  -- Construction (au premier affichage : le cadre est alors a son niveau definitif dans le panneau) --------------
  local function Build()
    built = true
    local L0 = pin:GetFrameLevel()

    -- Clic hors du tiroir = fermeture ; sa texture assombrit l'apercu
    catcher = CreateFrame("Frame", nil, pin)
    catcher:SetAllPoints(pin:GetParent())
    catcher:SetFrameLevel(L0 + 20)
    catcher:EnableMouse(false)
    dim = catcher:CreateTexture(nil, "BACKGROUND")
    dim:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    dim:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    dim:SetColorTexture(0, 0, 0, 1)
    catcher._Apply = function(self) dim:SetAlpha(V(self, "a", 0)) end
    Snap(catcher, "a", 0); catcher:_Apply()
    catcher:SetScript("OnMouseDown", function()
      if M.item then CloseMenu() else CloseDrawer() end
    end)

    stage = CreateFrame("Frame", nil, pin)
    stage:SetFrameLevel(L0 + 30)
    stage:SetSize(10, 10)

    circle = ns.Modules.ResourceCircle and ns.Modules.ResourceCircle.NewPreviewDisc
      and ns.Modules.ResourceCircle.NewPreviewDisc(stage) or CreateFrame("Frame", nil, stage)
    circle:SetPoint("CENTER", stage, "CENTER", 0, 0)
    circle._Apply = function(self)
      local a = V(self, "a", 1)
      if self.SetDim then self.SetDim(a) else self:SetAlpha(a) end
    end

    for i = 1, 12 do
      local s = PBm.NewPreviewSlot(stage, i)
      Decorate(s)
      Relevel(s, L0 + 34)
      s._Apply = ApplyAlpha
      -- Clic = tiroir ; glisser (bouton gauche) = deplacer / supprimer le sort affiche, cf. TopDragTick
      s:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" or InCombatLockdown() or not self._baseID then return end
        local x, y = StagePos()
        T.press = { src = i, sid = self._baseID, x0 = x, y0 = y }
      end)
      s:SetScript("OnMouseUp", function()
        local p = T.press
        if p and p.dragging then TopDragEnd(p); return end
        T.press = nil
        if GetTime() - (T.lastEnd or 0) < 0.15 then return end   -- fin de glisser deja traitee
        OpenDrawer(i)
      end)
      s.cooldown:SetScript("OnCooldownDone", function(cd)
        if s._demoCD then cd:SetCooldown(GetTime(), CD_DEMO) end
      end)
      tops[i] = s
    end

    drawer = CreateFrame("Frame", nil, stage)
    drawer:SetFrameLevel(L0 + 70)
    drawer:SetSize(1, 1)
    drawer:SetScript("OnUpdate", DragTick)

    drawerBg = CreateFrame("Frame", nil, drawer, "BackdropTemplate")
    drawerBg:SetFrameLevel(L0 + 70)
    drawerBg:SetPoint("TOP", drawer, "TOP", 0, 0)
    drawerBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    drawerBg:SetBackdropColor(0.03, 0.03, 0.04, 0.92)
    drawerBg:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.55)
    drawerBg:EnableMouse(true)
    drawerBg._Apply = function(self)
      local h = V(self, "h", 0)
      self:SetHeight(math.max(1, h))
      self:SetAlpha(h < 3 and 0 or V(self, "a", 1))   -- un tiroir quasi ferme ne laisse pas un trait de bordure
    end
    drawerBg:Hide()

    -- "+" vert : ajouter un sort (meme selecteur que l'ancienne liste "Sorts par slot")
    plus = CreateFrame("Button", nil, drawer)
    plus:SetFrameLevel(L0 + 72)
    local pbg = plus:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.05, 0.12, 0.05, 0.85)
    local pBorder = CreateFrame("Frame", nil, plus, "BackdropTemplate")
    pBorder:SetAllPoints()
    pBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    pBorder:SetBackdropBorderColor(0.3, 0.85, 0.3, 0.7)
    local pIco = plus:CreateTexture(nil, "ARTWORK")
    pIco:SetTexture(PLUS_TEX)
    pIco:SetPoint("CENTER")
    pIco:SetVertexColor(0.35, 0.9, 0.35, 1)
    plus._ico = pIco
    plus._Apply = ApplyItem
    plus:SetScript("OnEnter", function(self)
      pbg:SetColorTexture(0.08, 0.2, 0.08, 0.95)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
      GameTooltip:SetText(L["SETTINGS_ADD_SPELL_TITLE"], 1, 1, 1)
      GameTooltip:Show()
    end)
    plus:SetScript("OnLeave", function()
      pbg:SetColorTexture(0.05, 0.12, 0.05, 0.85)
      GameTooltip:Hide()
    end)
    plus:SetScript("OnClick", function(self)
      if M.item then CloseMenu(); return end
      local picker = ns.PBSpellPicker
      if InCombatLockdown() or not picker or not D.slot then return end
      local slotIdx = D.slot
      picker:Open(self, slotIdx, function(pickedID)
        if D.slot ~= slotIdx then return end
        for _, it in ipairs(D.items) do if it.sid == pickedID then return end end
        local n = #D.items + 1
        local it = Acquire(pickedID)
        D.items[n] = it
        Snap(it, "y", PosY(n)); Snap(it, "a", 0); Snap(it, "s", 0.4); it:_Apply()
        Go(it, "a", 1); Go(it, "s", 1)
        Relayout()
        Commit()
        UpdateDim()
      end)
    end)
    plus:Hide()

    stage:SetScript("OnUpdate", TopDragTick)

    menuLayer = CreateFrame("Frame", nil, stage)
    menuLayer:SetFrameLevel(L0 + 100)
    menuLayer:SetAllPoints(stage)
  end

  -- Mise en page : barres a l'echelle du jeu, cercle au centre --------------------------------------------------
  local function Layout()
    local cfg = Cfg()
    local def = LayoutDef()
    size = cfg.iconSize or 34
    local sp = cfg.iconSpacing or 6
    step = size + math.max(4, sp)
    local side = cfg.sideOffset or 170
    local cols, rows = def.cols, def.rows
    local cW = cols * size + (cols - 1) * sp
    local cH = rows * size + (rows - 1) * sp
    local bgSize = (circle:GetWidth() or 80) * 1.1
    local W = math.max(side * 2, bgSize) + 24
    local H = math.max(cH, bgSize) + 12
    stage:SetSize(W, H)

    local nL, nR = #def.leftNames, #def.rightNames
    for i = 1, 12 do
      local s = tops[i]
      s:ClearAllPoints()
      if i <= nL + nR then
        local j = (i <= nL) and i or (i - nL)
        local x0 = (i <= nL) and -side or (side - cW)
        local row0, col0 = math.floor((j - 1) / cols), (j - 1) % cols
        s:SetPoint("TOPLEFT", stage, "CENTER", x0 + col0 * (size + sp), cH / 2 - row0 * (size + sp))
        s:Show()
      else
        s:Hide()
      end
    end

    -- Meme echelle a l'ecran que la vraie barre (enfant d'UIParent), reduite seulement si la place manque
    local pe = pin:GetEffectiveScale()
    local sc = (pe and pe > 0) and (UIParent:GetEffectiveScale() / pe) or 1
    local avail = math.max(50, (pin:GetWidth() or 0) - 8)
    if (pin:GetWidth() or 0) > 50 and W * sc > avail then sc = avail / W end
    stage:SetScale(sc)
    stage:ClearAllPoints()
    stage:SetPoint("CENTER", pin, "CENTER", 0, HINT_H / 2 / sc)

    local h = math.ceil(H * sc) + PAD * 2 + HINT_H
    if h ~= pinH then
      pinH = h
      SetPinHeight(pinH)
    end
    BuildMenu(math.max(24, math.floor(size * 0.93 + 0.5)))
    if plus then plus._ico:SetSize(size * 0.55, size * 0.55) end
  end

  local function Refresh()
    if not built or not pin:IsVisible() then return end
    CloseDrawer(true)
    T.press = nil
    if T.ghost then T.ghost:Hide() end
    Data()
    if circle.Apply then circle.Apply() end   -- cercle : reglages du profil "Default"
    Layout()
    for i = 1, 12 do
      local s = tops[i]
      if s:IsShown() then
        PBm.StyleSlot(s)
        PBm.StopSlotGlow(s)
        s.currentSpellID = nil
        ShowTop(i, false)
      else
        PBm.StopSlotGlow(s)
        s._demoCD = false
      end
    end
  end

  local pending = false
  local function RefreshSoon()
    if pending then return end
    pending = true
    C_Timer.After(0, function() pending = false; Refresh() end)
  end

  -- Relance periodique de l'animation de proc (sinon jouee une seule fois a l'ouverture)
  local procTicker
  local function ProcReplay()
    for _, s in ipairs(tops) do
      if s:IsShown() and s.isHighlighted and s._procStartEnabled then
        s.procStartTex:SetAlpha(1)
        s.procStartTex:Show()
        s.procStartAG:Stop()
        s.procStartAG:Play()
      end
    end
  end

  local function PinUp()
    SetPinHeight(math.max(pinH, 100))
    if not built then Build() end
    Refresh()
    if procTicker then procTicker:Cancel() end
    procTicker = C_Timer.NewTicker(PROC_REPLAY, ProcReplay)
  end
  container:HookScript("OnShow", PinUp)
  container:HookScript("OnHide", function()
    if built then CloseDrawer(true) end
    if procTicker then procTicker:Cancel(); procTicker = nil end
  end)
  pin:SetScript("OnSizeChanged", function() if built then Layout() end end)

  if ns.CallbackRegistry then
    ns.CallbackRegistry:Register("SettingChanged", function(dbKey)
      if (dbKey == "priorityBar" or dbKey == "colors") and pin:IsVisible() then RefreshSoon() end
    end)
    ns.CallbackRegistry:Register("PriorityBar.SpecChanged", function()
      if pin:IsVisible() then RefreshSoon() end
    end)
  end
  if container:IsVisible() then C_Timer.After(0, PinUp) end   -- apres la mise en page (largeur de l'encart)

  return RefreshSoon
end

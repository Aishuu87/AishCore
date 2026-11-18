-- Modules/Fishing.lua : HUD de peche (Forever : la canne se tient en main droite).
--  * Icone de l'appat fixe sur la canne : rond cercle facon orbe du Camping HUD (grossit au survol, halo, infobulle
--    nom + bonus qui glisse vers l'exterieur), minuteur dessous.
--  * Bouton de reequipement : armes portees avant la canne (retenues par personnage), affiche en fondu quand on se
--    met a bouger canne en main ; un clic (bouton securise, /equipslot) les remet.
-- Retail : canne dans l'emplacement d'outil de metier, rien ne s'affiche (seul le double clic de la page reste utile).
local addonName, ns = ...

local Fishing = {}
ns.Modules.Fishing = Fishing
local L = ns.L

local MEDIA_UI   = "Interface\\AddOns\\AishCore\\Media\\UI\\"
local GRUNGE     = { MEDIA_UI .. "frame_jailer1.png", MEDIA_UI .. "frame_jailer2.png", MEDIA_UI .. "frame_jailer3.png" }
local GRUNGE_W, GRUNGE_H, GRUNGE_DY = 0.77, 0.63, 0.044   -- partie sombre du fond grunge (cf. Campfire.lua)
local GLOW_ROUND = "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga"
local MASK       = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW_RGB   = { 1, 0.85, 0.3 }
local FISH_ICON  = 136245
local PREVIEW_LURE, PREVIEW_DUR = 6532, 600
local POP = 0.55
local EMPTY_GROW = 0.25   -- rond vide : grossit moins au survol (le chapelet se deroule dessous)

local preview = false
local lure, swap, tip, driver
local lureEnd, lureItem, pendingLure
local swapHideAt

local function Cfg() return ns.GetCfg("fishing") or {} end
local function Clamp(u) return u < 0 and 0 or (u > 1 and 1 or u) end
local function EaseOut(u) return 1 - (1 - u) ^ 3 end
local function EaseIn(u) return u * u end
local function EaseBack(u) return 1 + 2.4 * (u - 1) ^ 3 + 1.4 * (u - 1) ^ 2 end
local function Plain(s) return type(s) == "string" and not (issecretvalue and issecretvalue(s)) end

local function Outline(fs, ring, path, size, style)
  path = path or ns.FONT_FALLBACK
  if ns.ApplyTextOutlineStyle then
    ns.ApplyTextOutlineStyle(fs, ring, path, size, (style == "NONE" or not style) and "" or style, true)
  else
    pcall(fs.SetFont, fs, path, size, style == "THICKOUTLINE" and "THICKOUTLINE" or (style == "OUTLINE" and "OUTLINE" or ""))
  end
end

-- ── Canne, appats, armes retenues ──────────────────────────────────────────

function Fishing.PoleEquipped()
  local id = GetInventoryItemID("player", 16)
  if not id then return false end
  local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
  return classID == 2 and subClassID == ((Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole) or 20)
end

local function Lures()
  local A = ns.Auras
  return (A and A.MISSING_FISHING_LURES) or {}
end

-- Sort d'utilisation -> appat (relu tant qu'un objet n'est pas en cache)
local lureBySpell = {}
local function LureFromSpell(sid)
  if not lureBySpell[sid] then
    for _, id in ipairs(Lures()) do
      local ok, _, s = pcall(C_Item.GetItemSpell, id)
      if ok and s then lureBySpell[s] = id end
    end
  end
  return lureBySpell[sid]
end

-- Donnees hors profil (AishaddonDB._fishing) : enchantement temporaire -> appat (appris a la pose, commun a tous),
-- armes portees avant la canne (par personnage)
local function Store()
  local root = _G.AishaddonDB
  if type(root) ~= "table" then return { gear = {}, enchants = {} } end
  root._fishing = root._fishing or {}
  local f = root._fishing
  f.gear, f.enchants = f.gear or {}, f.enchants or {}
  return f
end
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function Gear() return Store().gear[CharKey()] end

-- Bonus de l'appat : 1er nombre de la description de son sort, sinon ligne verte de la canne dans l'infobulle
local function LureStat(item)
  local ok, _, sid = pcall(C_Item.GetItemSpell, item or 0)
  local desc = ok and sid and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(sid)
  local n = Plain(desc) and desc:match("%d+")
  if n then return string.format(L["FISHING_LURE_STAT"], n) end
  if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
  local okT, data = pcall(C_TooltipInfo.GetInventoryItem, "player", 16)
  for _, line in ipairs(okT and data and data.lines or {}) do
    local t, col = line.leftText, line.leftColor
    if Plain(t) and col and col.g > 0.9 and col.r < 0.3 and t:find("%d") then
      return (t:gsub("%s*%(%d+[^%)]*%)%s*$", ""))
    end
  end
  return nil
end

-- Bonus de peche total (canne + appat) et competence effective, lus sur la competence elle-meme
local FISH_SPELLS = { 7620, 131474 }
local function FishingName() return C_Spell.GetSpellName(ns.IsForever and 7620 or 131474) end
local function FishingBonus()
  if GetProfessions and GetProfessionInfo then
    local _, _, _, fish = GetProfessions()
    if fish then
      local _, _, rank, _, _, _, _, mod = GetProfessionInfo(fish)
      if type(mod) == "number" then return mod, rank end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    local fname = FishingName()
    for i = 1, GetNumSkillLines() do
      local name, header, _, rank, _, mod = GetSkillLineInfo(i)
      if not header and fname and name == fname and type(mod) == "number" then return mod, rank end
    end
  end
  return nil
end
local function BonusLine()
  local mod, rank = FishingBonus()
  if not mod then return nil end
  if rank then return string.format(L["FISHING_TOTAL_BONUS_SKILL"], rank + mod, rank, mod) end
  return string.format(L["FISHING_TOTAL_BONUS"], mod)
end

local function ItemName(id)
  local n = id and C_Item.GetItemNameByID(id)
  if not Plain(n) then
    if id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    return nil
  end
  return n
end

-- ── Icones rondes (orbe du Camping HUD) ─────────────────────────────────────

-- Flotteur sur l'eau : petits sautillements rapides (~1 par seconde, pointe vers le bas plus franche), portes par
-- une houle lente, derive laterale legere. Relue a un instant decale par les plombs du chapelet.
local function BobberWave(f, t)
  local bob = math.sin(t * 6.2 + f.py)
  bob = bob < 0 and bob * 1.4 or bob * 0.8
  return 2.5 * math.sin(t * 0.9 + f.px) + 0.9 * math.sin(t * 3.1 + f.py),   -- derive + petit tangage
         2.2 * bob + 1.6 * math.sin(t * 1.4 + f.px)
end

local function WakeDriver() if driver then driver:Show() end end

local function FitGrunge(tex, w, h)
  local gh = h / GRUNGE_H
  tex:SetSize(w / GRUNGE_W, gh)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", tex:GetParent(), "CENTER", 0, -gh * GRUNGE_DY)
end

local function Tip()
  if tip then return tip end
  tip = CreateFrame("Frame", nil, UIParent)
  tip:SetFrameStrata("TOOLTIP")
  tip.bg = tip:CreateTexture(nil, "BACKGROUND")
  tip.bg:SetAlpha(0.85)
  tip.name = tip:CreateFontString(nil, "OVERLAY")
  tip.stat = tip:CreateFontString(nil, "OVERLAY")
  tip.extra = tip:CreateFontString(nil, "OVERLAY")
  if ns.CreateSlugRing then
    tip.nameRing = ns.CreateSlugRing(tip, tip.name, "ARTWORK")
    tip.statRing = ns.CreateSlugRing(tip, tip.stat, "ARTWORK")
    tip.extraRing = ns.CreateSlugRing(tip, tip.extra, "ARTWORK")
  end
  tip:Hide()
  return tip
end

local function ShowTip(f)
  if f.getTip then f.tipName, f.tipStat, f.tipExtra = f.getTip(f) end   -- objet arrive en cache depuis l'affichage
  if not (f.tipName or f.tipStat) then return end
  local t = Tip()
  local c = Cfg()
  local fs, font = c.tipFontSize or 13, c.tipFont or ns.FONT_FALLBACK
  local nc, sc = c.tipNameColor or { 0.74, 0.48, 0.27, 1 }, c.tipStatColor or { 1, 0.83, 0.42, 1 }
  Outline(t.name, t.nameRing, font, fs, c.tipOutline)
  t.name:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
  Outline(t.stat, t.statRing, font, math.max(6, fs - 1), c.tipOutline)
  t.stat:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
  Outline(t.extra, t.extraRing, font, math.max(6, fs - 1), c.tipOutline)
  t.extra:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
  t.gap = c.tipOffset or 8
  t.bg:SetTexture(GRUNGE[f.grunge or 1])
  local name, stat = f.tipName, f.tipStat or ""
  t.name:SetText(name or "")
  t.stat:SetText(stat)
  local extra = f.tipExtra
  t.extra:SetText(extra or "")
  t.extra:SetShown(extra ~= nil)
  local nh = name and t.name:GetStringHeight() or 0
  local eh = extra and (t.extra:GetStringHeight() + 3) or 0
  local w = math.max(name and t.name:GetStringWidth() or 0, t.stat:GetStringWidth(), extra and t.extra:GetStringWidth() or 0) + 28
  local h = nh + t.stat:GetStringHeight() + eh + (name and 3 or 0) + 14
  t:SetSize(w, h)
  t.name:ClearAllPoints()
  t.name:SetPoint("TOP", t, "TOP", 0, -7)
  t.stat:ClearAllPoints()
  if name then t.stat:SetPoint("TOP", t.name, "BOTTOM", 0, -3) else t.stat:SetPoint("TOP", t, "TOP", 0, -7) end
  t.extra:ClearAllPoints()
  t.extra:SetPoint("TOP", t.stat, "BOTTOM", 0, -3)
  FitGrunge(t.bg, w, h)
  -- Grains du chapelet : infobulle sur le cote (en dessous / au-dessus, elle couvrirait les grains voisins)
  local dir = c.tipDir or "TOP"
  if f.sideTip then dir = (dir == "LEFT") and "LEFT" or "RIGHT" end
  t.owner, t.dir, t.t0, t.out = f, dir, GetTime(), nil
  t:SetAlpha(0)
  t:Show()
  WakeDriver()
end

local function HideTip(f)
  if tip and tip.owner == f and not tip.out then tip.out = GetTime(); WakeDriver() end
end

-- Cadre deplacable (page de reglages ouverte et position deverrouillee) ; le corps (cercle, icone, halo) grossit
-- et flotte, le cadre reste fixe.
local function NewRound(name, prefix, secure)
  local f = CreateFrame("Button", name, UIParent, secure and "SecureActionButtonTemplate" or nil)
  f.prefix = prefix
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("CENTER")
  f.glow = f.body:CreateTexture(nil, "BACKGROUND", nil, -1)
  f.glow:SetTexture(GLOW_ROUND)
  f.glow:SetBlendMode("ADD")
  f.glow:SetVertexColor(GLOW_RGB[1], GLOW_RGB[2], GLOW_RGB[3], 1)
  f.glow:SetPoint("CENTER")
  f.glow:SetAlpha(0)
  f.ring = f.body:CreateTexture(nil, "BACKGROUND")
  f.ring:SetTexture(ns.Media.circle)
  f.ring:SetPoint("CENTER")
  f.tex = f.body:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("CENTER")
  f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local m = f.body:CreateMaskTexture()
  m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:SetAllPoints(f.tex)
  f.tex:AddMaskTexture(m)
  f.h, f.popT, f.alphaTarget = 0, 0, 1
  f.fx, f.fy = 0.9 + math.random() * 0.7, 1.2 + math.random() * 0.9
  f.px, f.py = math.random() * 6.28, math.random() * 6.28
  f:SetScript("OnEnter", function(self)
    self.hover = true
    ShowTip(self)
    WakeDriver()
  end)
  f:SetScript("OnLeave", function(self)
    self.hover = nil
    HideTip(self)
    WakeDriver()
  end)
  f:SetScript("OnDragStart", function(self)
    if preview and not Cfg()[prefix .. "Locked"] and not InCombatLockdown() then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local cx, cy = self:GetCenter()
    local db = ns.DB.fishing or {}
    ns.DB.fishing = db
    db[prefix .. "X"] = math.floor(cx - UIParent:GetWidth() / 2 + 0.5)
    db[prefix .. "Y"] = math.floor(cy - UIParent:GetHeight() / 2 + 0.5)
    Fishing.ApplySettings()
    local P = _G["AishCoreSettingsPanel"]
    if P and P.InvalidateCategory then P.InvalidateCategory("fishing") end
  end)
  f:Hide()
  return f
end

local function Layout(f)
  local c = Cfg()
  local p = f.prefix
  local S = c[p .. "Size"] or 32
  if not InCombatLockdown() then
    f:SetSize(S, S)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", c[p .. "X"] or 0, c[p .. "Y"] or 0)
  end
  f.body:SetSize(S, S)
  f.ring:SetSize(S + 4, S + 4)
  f.tex:SetSize(S, S)
  f.glow:SetSize(S * 1.9, S * 1.9)
  local rc = c[p .. "RingColor"] or { 1, 0.55, 0.15, 0.9 }
  f.ring:SetVertexColor(rc[1], rc[2], rc[3], rc[4] or 0.9)
  f.float = c[p .. "Float"] ~= false
  f.grow = (c[p .. "Grow"] or 60) / 100
end

local function Appear(f, alpha)
  f.alphaTarget, f.wantHide = alpha or 1, nil
  if not f:IsShown() then
    if f.secure and InCombatLockdown() then return end
    f.popT, f.h, f.curA = 0, 0, 0
    f:SetAlpha(0)
    f:Show()
  end
  WakeDriver()
end

local function Vanish(f, instant)
  if not f:IsShown() then return end
  HideTip(f)
  if instant then
    if f.secure and InCombatLockdown() then f:SetAlpha(0); f.curA = 0; f.wantHide = true; return end
    f:Hide(); f.hover = nil
    return
  end
  f.alphaTarget, f.wantHide = 0, true
  WakeDriver()
end

local function TimerText(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  if sec >= 60 then return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
  return string.format("%ds", sec)
end

local function OnDriver(_, dt)
  local now, busy = GetTime(), false
  for i = 1, 2 do
    local f = (i == 1) and lure or swap   -- pas d'ipairs : lure peut etre nil (jamais cree) avant swap
    if f and f:IsShown() then
      busy = true
      local hov = f.hover or f.hold   -- hold : chapelet d'appats ouvert, le rond reste grossi
      f.h = f.h + ((hov and 1 or 0) - f.h) * math.min(1, dt * 12)
      f.popT = f.popT + dt
      local s = EaseBack(Clamp(f.popT / POP)) * (1 + (f.grow or 0.6) * f.h)
      local x, y = 0, 0
      if f.float then
        local amp = 1 - (f.empty and 0.3 or 0.7) * f.h   -- rond vide : continue de flotter, chapelet ouvert
        if f == lure then
          local wx, wy = BobberWave(f, now)
          x, y = amp * wx, amp * wy
        else
          x = 1.5 * amp * math.sin(now * f.fx + f.px)
          y = 3 * amp * math.sin(now * f.fy + f.py)
        end
      end
      s = math.max(0.05, s)
      f.body:SetScale(s)
      f.body:ClearAllPoints()
      f.body:SetPoint("CENTER", f, "CENTER", x / s, y / s)
      -- Opacites gardees ici : GetAlpha arrondit au 1/255, un petit pas de fondu (haut framerate) n'y descendrait plus
      local gt = hov and 0.75 or 0
      local g = (f.ga or 0) + (gt - (f.ga or 0)) * math.min(1, dt * 10)
      if math.abs(g - gt) < 0.01 then g = gt end
      f.ga = g
      f.glow:SetAlpha(g)
      local target = (f.hover and f.hoverAlpha) or f.alphaTarget
      local a = f.curA or f:GetAlpha()
      a = a + (target - a) * math.min(1, dt * 6)
      if math.abs(a - target) < 0.01 then a = target end
      f.curA = a
      f:SetAlpha(a)
      if f.wantHide and a <= 0.01 and not f.hover and not (f.secure and InCombatLockdown()) then
        f:Hide(); f.wantHide = nil
      end
      if f.onTick then f.onTick(f, now) end
    end
  end
  if tip and tip:IsShown() then
    busy = true
    local e
    if tip.out then
      local u = Clamp((now - tip.out) / 0.15)
      e = 1 - EaseIn(u)
      if u >= 1 then tip:Hide(); tip.owner = nil end
    else
      e = EaseOut(Clamp((now - tip.t0) / 0.22))
    end
    local o, sl, gap = tip.owner, 8 * (1 - e), tip.gap or 8
    if o and o:IsShown() then
      local b = o.body
      tip:ClearAllPoints()
      if tip.dir == "LEFT" then tip:SetPoint("RIGHT", b, "LEFT", -gap + sl, 0)
      elseif tip.dir == "RIGHT" then tip:SetPoint("LEFT", b, "RIGHT", gap - sl, 0)
      elseif tip.dir == "BOTTOM" then tip:SetPoint("TOP", b, "BOTTOM", 0, -gap + sl)
      else tip:SetPoint("BOTTOM", b, "TOP", 0, gap - 2 - sl) end
      tip:SetAlpha(e)
    else
      tip:Hide(); tip.owner = nil
    end
  end
  if swapHideAt and now >= swapHideAt and swap and not swap.hover then
    swapHideAt = nil
    if not preview then Vanish(swap) end
  end
  if Fishing.UpdateChain and Fishing.UpdateChain(now, dt) then busy = true end
  if not busy and not swapHideAt then driver:Hide() end
end

-- ── Icone de l'appat ────────────────────────────────────────────────────────

local function StyleTimer()
  local c = Cfg()
  Outline(lure.timer, lure.timerRing, c.lureTimerFont or ns.FONT_FALLBACK, c.lureTimerSize or 11, c.lureTimerOutline or "OUTLINE")
  local tc = c.lureTimerColor or { 1, 1, 1, 1 }
  lure.timer:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
  lure.timer:ClearAllPoints()
  lure.timer:SetPoint("TOP", lure.body, "BOTTOM", c.lureTimerX or 0, c.lureTimerY or -2)
end

local function EnsureLure()
  if lure then return lure end
  lure = NewRound("AishCoreFishingLure", "lure")
  lure.grunge = 2
  lure.timer = lure:CreateFontString(nil, "OVERLAY")
  lure.timerRing = ns.CreateSlugRing and ns.CreateSlugRing(lure, lure.timer, "ARTWORK")
  -- "+" de l'etat vide (canne sans appat, appats dans les sacs)
  lure.plusH = lure.body:CreateTexture(nil, "OVERLAY")
  lure.plusV = lure.body:CreateTexture(nil, "OVERLAY")
  for _, t in ipairs({ lure.plusH, lure.plusV }) do
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint("CENTER")
    t:Hide()
  end
  lure:HookScript("OnEnter", function(self) if self.choices then Fishing.OpenChain() end end)
  lure.onTick = function(f, now)
    if (f._tt or 0) > now then return end
    f._tt = now + 0.2
    if f.empty then
      if not preview and GetWeaponEnchantInfo and GetWeaponEnchantInfo() then Fishing.RefreshLure() end
      return
    end
    -- Duree relue a chaque tick : appat retire puis repose, l'evenement d'inventaire peut arriver avant que
    -- le jeu ait mis a jour l'amelioration (ancienne duree gardee sinon)
    if not preview and GetWeaponEnchantInfo then
      local has, expMs, _, enchID = GetWeaponEnchantInfo()
      if not has or enchID ~= f._ench then Fishing.RefreshLure(); return end
      lureEnd = now + (expMs or 0) / 1000
    end
    local left = (lureEnd or now) - now
    if preview and left <= 0 then lureEnd = now + PREVIEW_DUR; left = PREVIEW_DUR end
    local txt = TimerText(left)
    if f.timer:GetText() ~= txt then f.timer:SetText(txt) end
  end
  return lure
end

-- Appat actif : enchantement temporaire de la canne, objet appris a la pose (sinon dernier pose)
local function ActiveLure()
  if not (GetWeaponEnchantInfo and Fishing.PoleEquipped()) then return nil end
  local has, expMs, _, enchID = GetWeaponEnchantInfo()
  if not has then return nil end
  local store = Store()
  if pendingLure and enchID then store.enchants[enchID] = pendingLure; pendingLure = nil end
  return (enchID and store.enchants[enchID]) or lureItem, (expMs or 0) / 1000
end

function Fishing.RefreshLure()
  local c = Cfg()
  local item, left, choices
  local show = c.lureEnabled ~= false and ns.IsForever
  if show and preview then
    item = PREVIEW_LURE
    if not lureEnd or lureEnd <= GetTime() then lureEnd = GetTime() + PREVIEW_DUR end
  elseif show then
    local active
    active, left = ActiveLure()
    if left then
      item = active; lureEnd = GetTime() + left
      choices = Fishing.BagLures()   -- chapelet au survol aussi : changer d'appat ou rafraichir le meme
    else
      -- Canne sans appat : rond vide si les sacs en contiennent
      choices = Fishing.PoleEquipped() and Fishing.BagLures() or nil
      show = choices ~= nil
    end
  end
  if not show then
    if lure then lure.empty, lure.choices = nil, nil; Fishing.CloseChain(true); Vanish(lure, true) end
    return
  end
  local f = EnsureLure()
  Layout(f)
  StyleTimer()
  f.item = item
  f.empty = not item and not preview   -- canne sans appat : rond vide "+"
  f.choices = not preview and choices or nil
  if f.empty then
    local S = c.lureSize or 32
    f.grow = math.min(f.grow or 0.6, EMPTY_GROW)
    f.tex:SetColorTexture(0.16, 0.10, 0.05, 1)
    local len, th = math.floor(S * 0.3 + 0.5), math.max(2, math.floor(S * 0.06 + 0.5))
    f.plusH:SetSize(len, th)
    f.plusV:SetSize(th, len)
    for _, t in ipairs({ f.plusH, f.plusV }) do t:SetVertexColor(1, 0.82, 0.3, 1); t:Show() end
    f.timer:SetText("")   -- pas Hide : le contour slug suit SetText, pas la visibilite (texte noir restant)
  else
    f.tex:SetTexture((item and C_Item.GetItemIconByID(item)) or FISH_ICON)
    f.plusH:Hide(); f.plusV:Hide()
  end
  f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  if not f.choices then Fishing.CloseChain(true)
  elseif f.hold then Fishing.OpenChain() end   -- sacs ou appat changes pendant que le chapelet est ouvert
  f._ench = (not preview and GetWeaponEnchantInfo) and select(4, GetWeaponEnchantInfo()) or nil
  f.getTip = function(o)
    if o.empty then return nil end   -- etat vide : le chapelet tient lieu d'infobulle
    return ItemName(o.item) or L["FISHING_LURE"], LureStat(o.item), BonusLine()
  end
  f.hoverAlpha = nil
  f:EnableMouse(true)
  f._tt = 0
  Appear(f, 1)
end

-- ── Chapelet des appats ──────────────────────────────────────────────────────
-- Survol du rond (vide ou appat pose) : les appats des sacs se deroulent dessous, en colonne de ronds plus petits (le
-- plus fort en haut). Celui deja pose porte une fleche "rafraichir". Grains = boutons securises (/use appat puis
-- /use 16), montres / caches hors combat seulement.
local REFRESH_ICON = "Interface\\Buttons\\UI-RefreshButton"

local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local BEAD_K, BEAD_GAP, BEAD_DROP, CHAIN_GRACE = 0.72, 10, 20, 0.25
local beads, chain = {}, { open = false, shown = false, t0 = 0, leaveAt = nil }

-- Appat utilisable : aucune ligne rouge dans son infobulle (competence de peche ou niveau insuffisants). Relu au
-- plus toutes les 5 s par objet (competence qui monte). Objet pas encore en cache : propose.
local usableCache = {}
local scanTip
local function IsRed(r, g, b) return r and r > 0.95 and g < 0.2 and b < 0.2 end
function Fishing.LureUsable(id)
  local now = GetTime()
  local e = usableCache[id]
  if e and e.t > now then return e.ok end
  local ok = true
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local okT, data = pcall(C_TooltipInfo.GetItemByID, id)
    for _, line in ipairs(okT and data and data.lines or {}) do
      local lc, rc = line.leftColor, line.rightColor
      if (lc and line.leftText and IsRed(lc.r, lc.g, lc.b)) or (rc and line.rightText and IsRed(rc.r, rc.g, rc.b)) then
        ok = false; break
      end
    end
  else
    scanTip = scanTip or CreateFrame("GameTooltip", "AishCoreFishingScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetItemByID(id)
    for i = 1, scanTip:NumLines() do
      for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G["AishCoreFishingScanTipText" .. side .. i]
        if fs and fs:IsShown() and (fs:GetText() or "") ~= "" and IsRed(fs:GetTextColor()) then ok = false end
      end
    end
    scanTip:Hide()
  end
  usableCache[id] = { ok = ok, t = now + 5 }
  return ok
end

function Fishing.BagLures()
  local list = Lures()
  local out = {}
  for i = #list, 1, -1 do
    local id = list[i]
    local n = GetCount(id) or 0
    if n > 0 and Fishing.LureUsable(id) then out[#out + 1] = { item = id, count = n } end
  end
  return #out > 0 and out or nil
end

local function Bead(i)
  if beads[i] then return beads[i] end
  local b = NewRound("AishCoreFishingLureChoice" .. i, "bead", true)
  b.secure, b.sideTip, b.grunge = true, true, 2
  b:RegisterForDrag()   -- grains non deplacables
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetScript("PostClick", function() C_Timer.After(0, function() Fishing.CloseChain() end) end)
  -- Fil : du bas du grain du dessus (ou du bouchon) au haut de celui-ci, suit leur flottement
  if b.CreateLine then
    b.line = b:CreateLine(nil, "BACKGROUND", nil, -3)
    b.line:SetThickness(1)
    b.line:SetColorTexture(1, 0.82, 0.3, 0.45)
  end
  -- Appat deja pose sur la canne : un clic le rafraichit
  b.refresh = b.body:CreateTexture(nil, "OVERLAY")
  b.refresh:SetTexture(REFRESH_ICON)
  b.refresh:SetPoint("CENTER")
  b.refresh:Hide()
  b.getTip = function(o)
    local n = ItemName(o.item) or L["FISHING_LURE"]
    return (o.count and o.count > 1) and (n .. " (" .. o.count .. ")") or n, LureStat(o.item), nil
  end
  beads[i] = b
  return b
end

function Fishing.OpenChain()
  if InCombatLockdown() or not (lure and lure.choices and lure:IsShown()) then return end
  local c = Cfg()
  local S = c.lureSize or 32
  local bs = math.floor(S * BEAD_K + 0.5)
  local rc = c.lureRingColor or { 1, 0.55, 0.15, 0.9 }
  local top = S * (1 + (lure.grow or 0.6)) / 2 + BEAD_DROP + bs / 2   -- sous le rond principal grossi
  local list = lure.choices
  for i, e in ipairs(list) do
    local b = Bead(i)
    b.item, b.count = e.item, e.count
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", "/use item:" .. e.item .. "\n/use 16")
    b:SetSize(bs, bs)
    b:ClearAllPoints()
    b:SetPoint("CENTER", lure, "CENTER", 0, -(top + (i - 1) * (bs + BEAD_GAP)))
    b:SetFrameLevel(lure:GetFrameLevel() + 2)
    b.body:SetSize(bs, bs)
    b.ring:SetSize(bs + 3, bs + 3)
    b.ring:SetVertexColor(rc[1], rc[2], rc[3], rc[4] or 0.9)
    b.tex:SetSize(bs, bs)
    b.tex:SetTexture(C_Item.GetItemIconByID(e.item) or FISH_ICON)
    local same = lure.item == e.item
    b.tex:SetVertexColor(same and 0.55 or 1, same and 0.55 or 1, same and 0.55 or 1)   -- icone assombrie sous la fleche
    b.refresh:SetSize(bs * 0.62, bs * 0.62)
    b.refresh:SetShown(same)
    b.glow:SetSize(bs * 1.9, bs * 1.9)
    b.step = bs + BEAD_GAP
    if b.line then
      b.line:SetStartPoint("BOTTOM", i == 1 and lure.body or beads[i - 1].body, 0, 0)
      b.line:SetEndPoint("TOP", b.body, 0, 0)
    end
    if not chain.open or not b:IsShown() then b.h, b.ga = 0, 0; b:SetAlpha(0) end
    b:Show()
  end
  for i = #list + 1, #beads do beads[i]:Hide() end
  chain.n = #list
  if not chain.open then chain.t0 = GetTime() end
  chain.open, chain.shown, chain.leaveAt = true, true, nil
  lure.hold = true
  WakeDriver()
end

function Fishing.CloseChain(instant)
  if lure then lure.hold = nil end
  if not chain.shown then return end
  if instant then
    if InCombatLockdown() then
      for _, b in ipairs(beads) do b:SetAlpha(0) end
      chain.open = false
      return
    end
    for _, b in ipairs(beads) do b:Hide(); b.hover = nil; HideTip(b) end
    chain.open, chain.shown = false, false
    return
  end
  if chain.open then chain.open, chain.t0 = false, GetTime() end
  WakeDriver()
end

-- Animation (appelee par le driver) : deroulement grain apres grain depuis le rond, fermeture par le bas
function Fishing.UpdateChain(now, dt)
  if not chain.shown then return false end
  if chain.open then
    local over = lure and lure:IsShown() and lure.hover
    for _, b in ipairs(beads) do if b:IsShown() and b.hover then over = true end end
    if over then chain.leaveAt = nil
    else
      chain.leaveAt = chain.leaveAt or (now + CHAIN_GRACE)
      if now >= chain.leaveAt then Fishing.CloseChain() end
    end
  end
  local n, done = chain.n or #beads, true
  for i, b in ipairs(beads) do
    if b:IsShown() then
      local e
      if chain.open then
        local u = Clamp((now - chain.t0 - (i - 1) * 0.045) / 0.28)
        e = u > 0 and EaseBack(u) or 0
        if u < 1 then done = false end
      else
        local u = Clamp((now - chain.t0 - (n - i) * 0.02) / 0.15)
        e = 1 - EaseIn(u)
        if u < 1 then done = false end
      end
      b.h = (b.h or 0) + ((b.hover and 1 or 0) - (b.h or 0)) * math.min(1, dt * 12)
      local s = math.max(0.05, (0.4 + 0.6 * e) * (1 + 0.25 * b.h))
      b.body:SetScale(s)
      -- Plombs sur la ligne : reprennent la vague du bouchon avec un retard et une ampleur qui decroissent vers le
      -- bas, plus un leger balancement propre
      local x, y = 0, 0
      if lure and lure.float then
        local wx, wy = BobberWave(lure, now - i * 0.18)
        local k = 0.6 * 0.85 ^ (i - 1)
        x = k * wx + 0.9 * math.sin(now * 1.7 + i * 1.3)
        y = k * wy * 0.7 + 0.6 * math.sin(now * 2.3 + i * 0.9)
      end
      b.body:ClearAllPoints()
      b.body:SetPoint("CENTER", b, "CENTER", x / s, (y + (b.step or 0) * (1 - math.min(1, e))) / s)   -- glisse depuis le grain du dessus
      local gt = b.hover and 0.75 or 0
      b.ga = (b.ga or 0) + (gt - (b.ga or 0)) * math.min(1, dt * 10)
      b.glow:SetAlpha(b.ga)
      b:SetAlpha(Clamp(e))
    end
  end
  if chain.open then return true end
  if done and not InCombatLockdown() then
    for _, b in ipairs(beads) do b:Hide(); b.hover = nil; HideTip(b) end
    chain.shown = false
    return false
  end
  return true
end

-- ── Bouton de reequipement ──────────────────────────────────────────────────

local function SwapMacro(g)
  local lines = {}
  if g.main then lines[#lines + 1] = "/equipslot 16 item:" .. g.main end
  if g.off then lines[#lines + 1] = "/equipslot 17 item:" .. g.off end
  return table.concat(lines, "\n")
end

local function EnsureSwap()
  if swap then return swap end
  swap = NewRound("AishCoreFishingSwap", "swap", true)
  swap.secure = true
  swap.grunge = 3
  swap:RegisterForClicks("AnyUp", "AnyDown")
  swap:SetScript("PostClick", function()
    if preview then return end
    swapHideAt = nil
    C_Timer.After(0, function() if swap then Vanish(swap) end end)
  end)
  return swap
end

-- Attributs securises et apparence : hors combat seulement
local function SetupSwap()
  if InCombatLockdown() then return end
  local f = EnsureSwap()
  local c = Cfg()
  Layout(f)
  local g = Gear()
  if preview or not g then
    f:SetAttribute("type", nil)
  else
    f:SetAttribute("type", "macro")
    f:SetAttribute("macrotext", SwapMacro(g))
  end
  local icon = g and C_Item.GetItemIconByID(g.main or g.off)
  f.tex:SetTexture(icon or "Interface\\Icons\\INV_Sword_04")
  local names = {}
  for _, id in ipairs({ g and g.main, g and g.off }) do
    if id then names[#names + 1] = ItemName(id) or ("item:" .. id) end
  end
  f.tipName = #names > 0 and table.concat(names, " + ") or nil
  f.tipStat = L["FISHING_SWAP_TIP"]
  f.hoverAlpha = c.swapHoverAlpha or 1
  f.alphaTarget = f.wantHide and 0 or (c.swapAlpha or 0.6)
end

local function SwapWanted()
  local c = Cfg()
  local g = Gear()
  return ns.IsForever and c.swapEnabled ~= false and g and (g.main or g.off) and Fishing.PoleEquipped()
end

function Fishing.RefreshSwap(moving)
  local c = Cfg()
  if preview then
    if c.swapEnabled ~= false and ns.IsForever then
      SetupSwap()
      if swap then Appear(swap, c.swapAlpha or 0.6) end
    elseif swap then Vanish(swap, true) end
    return
  end
  if swap and swap:IsShown() then SetupSwap() end   -- reglages en direct
  if not SwapWanted() then
    swapHideAt = nil
    if swap then Vanish(swap, true) end
    return
  end
  if moving == true then
    SetupSwap()
    if not swap then return end
    swapHideAt = nil
    Appear(swap, c.swapAlpha or 0.6)
  elseif (moving == false or (moving == nil and not swapHideAt)) and swap and swap:IsShown() then
    swapHideAt = GetTime() + (c.swapDelay or 3)
    WakeDriver()
  end
end

-- Armes en main hors canne : retenues (mains nues : on garde les precedentes)
local snapPending = false
local function Snapshot()
  snapPending = false
  if Fishing.PoleEquipped() then return end
  local m, o = GetInventoryItemID("player", 16), GetInventoryItemID("player", 17)
  if not m and not o then return end
  Store().gear[CharKey()] = { main = m, off = o }
end
local function QueueSnapshot()
  if snapPending then return end
  snapPending = true
  C_Timer.After(0.4, function()
    Snapshot()
    Fishing.RefreshLure()
    Fishing.RefreshSwap()
  end)
end

-- ── Son baisse pendant la peche ──────────────────────────────────────────────
-- Canne lancee (canalisation de Peche) : ambiance et musique a duckLevel % de leur volume. A l'arret, apres un
-- court delai (relance probable), elles remontent en fondu (duckFade s). Volumes d'origine gardes dans
-- AishaddonDB._fishing.duck, restaures au chargement si l'interface a ete rechargee en pleine peche.
local DUCK_CVARS = { "Sound_AmbienceVolume", "Sound_MusicVolume" }
local DUCK_GRACE, DUCK_DOWN = 3, 0.5
local duck = { frame = nil, from = nil, to = nil, t0 = 0, dur = 0, stopAt = nil }

local function GetVol(cv) return tonumber((C_CVar and C_CVar.GetCVar or GetCVar)(cv)) or 1 end
local function SetVol(cv, v) (C_CVar and C_CVar.SetCVar or SetCVar)(cv, string.format("%.3f", v)) end

local function IsFishingSpell(sid)
  if not sid then return false end
  local n = C_Spell.GetSpellName(sid)
  if not Plain(n) then return false end
  for _, id in ipairs(FISH_SPELLS) do
    if n == C_Spell.GetSpellName(id) then return true end
  end
  return false
end

-- Fondu de chaque volume, de sa valeur actuelle vers une fraction (k) de l'original
local function DuckTo(k, dur)
  local orig = Store().duck
  if not orig then return end
  duck.from, duck.to = {}, {}
  for i, cv in ipairs(DUCK_CVARS) do
    duck.from[i] = GetVol(cv)
    duck.to[i] = (orig[i] or 1) * k
  end
  duck.t0, duck.dur, duck.restore = GetTime(), math.max(0.05, dur), k >= 1
  if not duck.frame then
    duck.frame = CreateFrame("Frame")
    duck.frame:SetScript("OnUpdate", function(self)
      local now = GetTime()
      if duck.stopAt and now >= duck.stopAt then
        duck.stopAt = nil
        DuckTo(1, Cfg().duckFade or 4)
        return
      end
      if not duck.from then
        if not duck.stopAt then self:Hide() end
        return
      end
      if (self._t or 0) > now then return end
      self._t = now + 0.03
      local u = Clamp((now - duck.t0) / duck.dur)
      for i, cv in ipairs(DUCK_CVARS) do SetVol(cv, duck.from[i] + (duck.to[i] - duck.from[i]) * u) end
      if u >= 1 then
        duck.from = nil
        if duck.restore then Store().duck = nil end   -- volumes revenus a l'original
      end
    end)
  end
  duck.frame:Show()
end

local function DuckStart()
  local c = Cfg()
  if not c.duckEnabled then return end
  duck.stopAt = nil
  local s = Store()
  if not s.duck then
    s.duck = {}
    for i, cv in ipairs(DUCK_CVARS) do s.duck[i] = GetVol(cv) end
  end
  DuckTo((c.duckLevel or 30) / 100, DUCK_DOWN)
end

local function DuckStop()
  if not Store().duck then return end
  duck.stopAt = GetTime() + DUCK_GRACE
  if not duck.frame then DuckTo(1, Cfg().duckFade or 4) end
  duck.frame:Show()
end

-- Chargement : volumes laisses baisses par un /reload en pleine peche
local function DuckRecover()
  local orig = Store().duck
  if not orig then return end
  for i, cv in ipairs(DUCK_CVARS) do SetVol(cv, orig[i] or 1) end
  Store().duck = nil
end
Fishing.DuckRecover = DuckRecover

-- ── Raccourci lancer / relever ───────────────────────────────────────────────
-- Touche choisie dans le GUI (fishing.castKey), liee en priorite (override, hors combat) selon la cible d'interaction
-- (ciblage doux) : bouchon ou autre cible -> INTERACTTARGET (relever) ; aucune -> bouton securise Peche (lancer).
-- Rien de lie monte, en vehicule, mort, en combat ou (Forever) sans canne : la touche garde son action habituelle.
local CAST_SPELL = ns.IsForever and 7620 or 131474
local CAST_BTN = "AishCoreFishingCastButton"
local RANGE_CVAR, RANGE_FISH = "SoftTargetInteractRange", 30
local castBtn, castState, softChecked
local GetCV = (C_CVar and C_CVar.GetCVar) or GetCVar
local SetCV = (C_CVar and C_CVar.SetCVar) or SetCVar

local function CastKey()
  local c = Cfg()
  local k = c.castKeyEnabled and c.castKey
  return (type(k) == "string" and k ~= "") and k or nil
end

local function CastReady()
  if IsMounted() or (UnitInVehicle and UnitInVehicle("player")) or UnitIsDeadOrGhost("player") then return false end
  return not ns.IsForever or Fishing.PoleEquipped()
end

-- Ciblage doux de l'interaction (CVar SoftTargetInteract : 2 clavier-souris, 3 toujours) : requis pour viser le bouchon
local function EnsureSoftInteract()
  if softChecked then return end
  softChecked = true
  local v = tonumber(GetCV("SoftTargetInteract"))
  if v and v ~= 2 and v ~= 3 then pcall(SetCV, "SoftTargetInteract", "3") end
end

-- off : entree en combat (PLAYER_REGEN_DISABLED, encore permis) -> liaison retiree
function Fishing.UpdateCastKey(off)
  if InCombatLockdown() then return end
  local key = not off and CastKey()
  local want
  if key then
    EnsureSoftInteract()
    if CastReady() then want = (UnitGUID and UnitGUID("softinteract") ~= nil) and "interact" or "cast" end
  end
  local sig = want and (want .. key) or nil
  if sig == castState then return end
  if not castBtn then
    if not want then return end
    castBtn = CreateFrame("Button", CAST_BTN, UIParent, "SecureActionButtonTemplate")
    castBtn:RegisterForClicks("AnyUp", "AnyDown")
    castBtn:SetAttribute("type", "spell")
  end
  castState = sig
  ClearOverrideBindings(castBtn)
  if want == "interact" then
    SetOverrideBinding(castBtn, true, key, "INTERACTTARGET")
  elseif want == "cast" then
    castBtn:SetAttribute("spell", C_Spell.GetSpellName(CAST_SPELL) or CAST_SPELL)   -- par nom : rang le plus haut (Forever)
    SetOverrideBindingClick(castBtn, true, key, CAST_BTN)
  end
end

-- Portee du ciblage doux elargie le temps de la peche (bouchon lointain), rendue a l'arret ; restauree au chargement
-- si l'interface a ete rechargee canne lancee (AishaddonDB._fishing.interactRange)
local function RangeUp()
  if not CastKey() then return end
  local cur = tonumber(GetCV(RANGE_CVAR))
  if not cur or cur >= RANGE_FISH then return end
  local s = Store()
  if not s.interactRange then s.interactRange = cur end
  pcall(SetCV, RANGE_CVAR, tostring(RANGE_FISH))
end
local function RangeDown()
  local s = Store()
  if not s.interactRange then return end
  pcall(SetCV, RANGE_CVAR, tostring(s.interactRange))
  s.interactRange = nil
end

-- ── Reglages, apercu ─────────────────────────────────────────────────────────

function Fishing.SetPreview(on)
  preview = on and true or false
  if not preview then lureEnd = nil end
  Fishing.ApplySettings()
end

function Fishing.ResetPosition(prefix)
  local db = ns.DB.fishing
  local d = ns.Defaults.fishing or {}
  if db then db[prefix .. "X"], db[prefix .. "Y"] = d[prefix .. "X"], d[prefix .. "Y"] end
  Fishing.ApplySettings()
end

function Fishing.ApplySettings()
  if not driver then
    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", OnDriver)
  end
  Fishing.RefreshLure()
  Fishing.RefreshSwap(IsPlayerMoving and IsPlayerMoving() or nil)
  Fishing.UpdateCastKey()
  -- Option coupee en pleine peche : volumes rendus en fondu
  if not Cfg().duckEnabled and Store().duck and not (duck.stopAt or (duck.from and duck.restore)) then
    DuckTo(1, Cfg().duckFade or 4)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("PLAYER_STARTED_MOVING")
ev:RegisterEvent("PLAYER_STOPPED_MOVING")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
-- Raccourci lancer / relever (evenements absents d'un client : ignores)
local CAST_EVENTS = { PLAYER_SOFT_INTERACT_CHANGED = true, PLAYER_MOUNT_DISPLAY_CHANGED = true, PLAYER_DEAD = true,
                      PLAYER_ALIVE = true, PLAYER_UNGHOST = true }
for e in pairs(CAST_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
pcall(ev.RegisterUnitEvent, ev, "UNIT_ENTERED_VEHICLE", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_EXITED_VEHICLE", "player")
CAST_EVENTS.UNIT_ENTERED_VEHICLE, CAST_EVENTS.UNIT_EXITED_VEHICLE = true, true
ev:SetScript("OnEvent", function(_, event, a1, _, a3)
  -- Raccourci lancer / relever : tous les clients
  if CAST_EVENTS[event] then Fishing.UpdateCastKey(); return end
  if event == "PLAYER_REGEN_DISABLED" then Fishing.UpdateCastKey(true)
  elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LOGIN"
    or (event == "PLAYER_EQUIPMENT_CHANGED" and a1 == 16) then
    C_Timer.After(0, function() Fishing.UpdateCastKey() end)
  end
  -- Son baisse pendant la peche : tous les clients
  if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    if IsFishingSpell(a3) then
      if event == "UNIT_SPELLCAST_CHANNEL_START" then DuckStart(); RangeUp() else DuckStop(); RangeDown() end
    end
    return
  end
  if event == "PLAYER_LOGIN" then DuckRecover(); RangeDown() end
  if not ns.IsForever then return end
  if event == "PLAYER_LOGIN" then
    Snapshot()
    Fishing.ApplySettings()
  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    if a1 == 16 or a1 == 17 then QueueSnapshot() end
  elseif event == "UNIT_INVENTORY_CHANGED" then
    Fishing.RefreshLure()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local item = a3 and LureFromSpell(a3)
    if item then
      lureItem, pendingLure = item, item
      C_Timer.After(0.3, Fishing.RefreshLure)
      C_Timer.After(1.5, Fishing.RefreshLure)   -- amelioration parfois posee apres l'evenement
    end
  elseif event == "PLAYER_STARTED_MOVING" then
    Fishing.RefreshSwap(true)
  elseif event == "PLAYER_STOPPED_MOVING" then
    Fishing.RefreshSwap(false)
  elseif event == "PLAYER_REGEN_ENABLED" then
    Fishing.RefreshSwap(IsPlayerMoving and IsPlayerMoving() or nil)
    if not (lure and lure.hold) then Fishing.CloseChain(true) end   -- grains masques en combat (alpha 0)
  elseif event == "PLAYER_REGEN_DISABLED" then
    Fishing.CloseChain(true)   -- encore permis a cet instant : pas de grains cliquables en combat
  elseif event == "BAG_UPDATE_DELAYED" then
    Fishing.RefreshLure()
  end
end)

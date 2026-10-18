-- Modules/PixelSnap.lua : calage au pixel des barres et des textes.
-- Une barre fine (1-3 px) ou un texte dont le bord tombe entre deux pixels ecran est rendu tantot net, tantot
-- grossi / flou d'un pixel. Ce module recale, apres chaque mise en page, les cadres "barres + texte" d'AishCore :
-- tailles arrondies a un nombre entier de pixels physiques, coin haut-gauche de chaque element pose sur un pixel.
-- Ne touche qu'aux elements ancres en un seul point (ceux tendus entre deux ancres suivent leur parent, deja cale)
-- et jamais au remplissage d'une barre (gere par le jeu). Hors combat uniquement (cadres securises).
-- Toujours actif, sans reglage.
local addonName, ns = ...

local PixelSnap = {}
ns.Modules.PixelSnap = PixelSnap

-- Taille d'un pixel physique dans le repere d'un element
local function PixelUnit(region)
  local _, ph = GetPhysicalScreenSize()
  local ok, es = pcall(region.GetEffectiveScale, region)
  if not ok or not es or es <= 0 or not ph or ph <= 0 then return nil end
  return 768 / ph / es
end
ns.PixelUnit = PixelUnit

local function Plain(...)
  if not issecretvalue then return true end
  for i = 1, select("#", ...) do
    if issecretvalue((select(i, ...))) then return false end
  end
  return true
end

local function SnapRegion(r)
  local okF, forbidden = pcall(r.IsForbidden, r)
  if not okF or forbidden then return end
  local px = PixelUnit(r)
  if not px then return end
  local okN, n = pcall(r.GetNumPoints, r)
  if not okN or n ~= 1 then return end
  -- Taille entiere en pixels (pas pour un texte : sa largeur suit le texte)
  if r:GetObjectType() ~= "FontString" then
    local okS, w, h = pcall(r.GetSize, r)
    if okS and Plain(w, h) and w and h and w > 0 and h > 0 then
      local nw = math.max(1, math.floor(w / px + 0.5)) * px
      local nh = math.max(1, math.floor(h / px + 0.5)) * px
      if math.abs(nw - w) > 0.001 or math.abs(nh - h) > 0.001 then pcall(r.SetSize, r, nw, nh) end
    end
  end
  -- Coin haut-gauche sur un pixel : on decale l'ancre de la difference
  local okL, l, t = pcall(function() return r:GetLeft(), r:GetTop() end)
  if not (okL and l and t and Plain(l, t)) then return end
  local dx = math.floor(l / px + 0.5) * px - l
  local dy = math.floor(t / px + 0.5) * px - t
  if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then return end
  local okP, point, rel, relPoint, x, y = pcall(r.GetPoint, r, 1)
  if not (okP and point and Plain(x, y)) then return end
  pcall(r.SetPoint, r, point, rel, relPoint, (x or 0) + dx, (y or 0) + dy)
end

local function SnapTree(f, depth)
  if not f or depth > 8 then return end
  SnapRegion(f)
  local fill = f.GetStatusBarTexture and f:GetStatusBarTexture()
  local okR, regions = pcall(function() return { f:GetRegions() } end)
  if okR then
    for _, r in ipairs(regions) do
      if r ~= fill and r.GetNumPoints then SnapRegion(r) end
    end
  end
  local okC, children = pcall(function() return { f:GetChildren() } end)
  if okC then
    for _, c in ipairs(children) do SnapTree(c, depth + 1) end
  end
end

-- Cadres concernes : un getter par module (les cadres sont crees tardivement ou a la demande)
local function G(name) return _G[name] end
local function M(name) return ns.Modules and ns.Modules[name] end
local TARGETS = {
  { mod = "CastBar",        roots = function() return { G("AishCoreCastBar") } end },
  { mod = "TargetCastBar",  roots = function() return { G("AishCoreTargetCastBar") } end },
  { mod = "TopTargetBar",   roots = function() return { G("AishCoreTopTarget"), G("AishCoreTopTargetTarget") } end },
  { mod = "UnitBars",       roots = function()
      local UB = M("UnitBars"); local out = {}
      local bars = UB and UB.GetBars and UB.GetBars()
      if bars then for _, b in pairs(bars) do out[#out + 1] = b end end
      return out
    end },
  { mod = "XPBar",          roots = function() return { G("AishuuXPBarContainer") } end },
  { mod = "ExtraBars",      roots = function()
      local EB = M("ExtraBars"); local out = {}
      for i = 1, 5 do local b = EB and EB.GetBarFrame and EB.GetBarFrame(i); if b then out[#out + 1] = b end end
      return out
    end },
  { mod = "MenuBar",        roots = function() local MB = M("MenuBar"); return { MB and MB.GetHoverFrame and MB.GetHoverFrame() } end },
  { mod = "Location",       roots = function() local LO = M("Location"); return { LO and LO.GetHoverFrame and LO.GetHoverFrame() } end },
  { mod = "RotationHelper", roots = function() return { G("AishCoreRotationHelperBar") } end },
  -- Cercles : seulement leurs dots / orbes (petits ronds), pas les arcs ni les animations du cercle
  { mod = "ResourceCircle", fns = { "ApplySettings", "LayoutSecDots", "DetectSecondaryDots" }, roots = function()
      local out, bar = {}, G("AishCoreRingBar")
      if bar then for i = 1, 5 do if bar["dot" .. i] then out[#out + 1] = bar["dot" .. i] end end end
      for i = 1, 10 do local d = G("AishCoreSecDot" .. i); if d then out[#out + 1] = d end end
      return out
    end },
  { mod = "OutOfCombatResourceCircle", fns = { "ApplySettings", "LayoutSecDots", "DetectSecondaryDots" }, roots = function()
      local out = {}
      for i = 1, 10 do local d = G("AishCoreOCSecDot" .. i); if d then out[#out + 1] = d end end
      return out
    end },
}

local pending, queued = false, false
function PixelSnap.SnapAll()
  pending = false
  if InCombatLockdown() then queued = true; return end
  for _, t in ipairs(TARGETS) do
    local ok, roots = pcall(t.roots)
    if ok and roots then
      for _, f in pairs(roots) do pcall(SnapTree, f, 0) end
    end
  end
end

-- Regroupe les demandes (plusieurs reglages appliques dans la meme frame)
function PixelSnap.Request()
  if pending then return end
  pending = true
  C_Timer.After(0, PixelSnap.SnapAll)
end

-- Apres chaque mise en page d'un module concerne, et a chaque affichage de ses cadres
local hookedMods, hookedFrames = {}, setmetatable({}, { __mode = "k" })
local function HookAll()
  for _, t in ipairs(TARGETS) do
    local mod = M(t.mod)
    if mod and not hookedMods[t.mod] then
      for _, fn in ipairs(t.fns or { "ApplySettings" }) do
        if type(mod[fn]) == "function" then hooksecurefunc(mod, fn, PixelSnap.Request) end
      end
      hookedMods[t.mod] = true
    end
    local ok, roots = pcall(t.roots)
    if ok and roots then
      for _, f in pairs(roots) do
        if f and f.HookScript and not hookedFrames[f] then
          hookedFrames[f] = true
          f:HookScript("OnShow", PixelSnap.Request)
        end
      end
    end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if queued then queued = false; PixelSnap.Request() end
    return
  end
  -- Cadres crees au login : on attend qu'ils existent et soient places
  C_Timer.After(1, function() HookAll(); PixelSnap.Request() end)
  C_Timer.After(4, function() HookAll(); PixelSnap.Request() end)
end)

function PixelSnap.ApplySettings() PixelSnap.Request() end

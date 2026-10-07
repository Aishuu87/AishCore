-- Modules/AddonFonts.lua : force une police (fichier, taille, contour) sur certains textes de
-- Platynator (timers des auras, niveau) et Baganator (textes des icônes d'objets).
-- Réglages ns.DB.addonFonts.<cible>{Enabled,Font,Size,Outline}, page "Intégrations".
-- Chaque FontString ciblé est hooké une fois (SetFont/SetFontObject) : quand l'addon d'origine
-- restyle le texte, on mémorise sa police puis on réapplique la nôtre. Décocher restaure la
-- police mémorisée, sans /reload.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local AddonFonts = {}
ns.Modules.AddonFonts = AddonFonts

local FLAGS = { NONE = "", OUTLINE = "OUTLINE", THICKOUTLINE = "THICKOUTLINE", SLUG = "",
                SHADOW = "", OUTLINE_SHADOW = "OUTLINE", THICK_SHADOW = "THICKOUTLINE" }
-- Styles qui ajoutent une ombre noire native (compatible texte secret, contrairement a SLUG)
local SHADOW_STYLES = { SHADOW = true, OUTLINE_SHADOW = true, THICK_SHADOW = true }
local AURA_KINDS = { "buffs", "debuffs", "crowdControl" }

local tracked    = setmetatable({}, { __mode = "k" }) -- [fontString] = cible ("platLevel" = dynamique)
local owners     = setmetatable({}, { __mode = "k" }) -- [fontString] = widget Platynator propriétaire
local origFont   = setmetatable({}, { __mode = "k" }) -- [fontString] = { path, size, flags } d'origine
local customized = setmetatable({}, { __mode = "k" }) -- [fontString] = true si notre police est posée
local seenFrames = setmetatable({}, { __mode = "k" }) -- [conteneur d'auras] = nb de frames déjà vues
local seenDisplays = setmetatable({}, { __mode = "k" }) -- [display Platynator] = true
local unitDisplay = {}                                -- [nameplateN] = display Platynator
local rings      = setmetatable({}, { __mode = "k" }) -- [fontString] = anneau SLUG (8 copies noires)
local slugOn     = setmetatable({}, { __mode = "k" }) -- [fontString] = true si l'anneau est actif
local origShadow = setmetatable({}, { __mode = "k" }) -- [fontString] = { x, y, r, g, b, a } avant SLUG / ombre
local applying = false
local bagActive, bagHooked = false, false

local function Get(k)
  local c = ns.DB and ns.DB.addonFonts
  local v = c and c[k]
  if v == nil then v = ns.Defaults.addonFonts[k] end
  return v
end

-- Cible effective : un widget Platynator est recyclé d'un type de texte à l'autre.
local function TargetOf(fs)
  local t = tracked[fs]
  if t == "platLevel" then
    local o = owners[fs]
    if not (o and o.details and o.details.kind == "level") then return nil end
  elseif t == "bagItem" and not bagActive then
    return nil
  end
  return t
end

-- ── SLUG ────────────────────────────────────────────────────────────────────
-- L'anneau suit le texte d'origine : parent, échelle, opacité, visibilité (hooks posés à la création).
local function SyncRing(fs)
  local ring = rings[fs]
  if not ring or fs:IsForbidden() then return end
  local on = slugOn[fs] and fs:IsShown()
  local parent, scale, tscale, alpha = fs:GetParent(), fs:GetScale(), fs.GetTextScale and fs:GetTextScale(), fs:GetAlpha()
  for _, r in ipairs(ring) do
    if r:GetParent() ~= parent then r:SetParent(parent) end
    r:SetScale(scale)
    if tscale then r:SetTextScale(tscale) end
    r:SetAlpha(alpha)
    r:SetShown(on and true or false)
  end
  if on then
    local ok, text = pcall(fs.GetText, fs)
    if ok then pcall(ns.SetSlugRingText, ring, text) end
  end
end

local function EnsureRing(fs)
  local ring = rings[fs]
  if ring then return ring end
  ring = ns.CreateSlugRing(fs:GetParent(), fs)
  -- Juste sous le texte d'origine, sur la même couche
  local layer, sub = fs:GetDrawLayer()
  for _, r in ipairs(ring) do r:SetDrawLayer(layer, math.max(-8, (sub or 0) - 1)) end
  rings[fs] = ring
  local sync = function() SyncRing(fs) end
  for _, m in ipairs({ "Show", "Hide", "SetShown", "SetScale", "SetTextScale", "SetAlpha", "SetParent" }) do
    hooksecurefunc(fs, m, sync)
  end
  return ring
end

-- Taille "pixel perfect" : sur une nameplate, l'echelle effective du texte rend la taille en pixels
-- fractionnaire (glyphes flous, chiffres irreguliers). On arrondit la taille rendue a l'entier
-- de pixels le plus proche, puis on la reconvertit en unites d'interface.
local function SnapSize(fs, size)
  local ok, res = pcall(function()
    local _, physH = GetPhysicalScreenSize()
    local es = fs:GetEffectiveScale()
    if not physH or physH <= 0 or not es or es <= 0 then return size end
    local k = es * physH / 768 -- pixels physiques par unite de police
    local snapped = math.floor(size * k + 0.5) / k
    -- Garde-fou : si l'echelle est deja tres compensee (k minuscule), l'arrondi serait enorme.
    -- Au-dela de ~12 % d'ecart on garde la taille demandee.
    if snapped <= 0 or math.abs(snapped - size) > size * 0.12 then return size end
    return snapped
  end)
  return ok and type(res) == "number" and res or size
end

local function RestoreShadow(fs)
  local o = origShadow[fs]
  fs:SetShadowOffset(o[1], o[2])
  if o[3] then fs:SetShadowColor(o[3], o[4], o[5], o[6]) end
  origShadow[fs] = nil
end

local function ApplyUnsafe(fs)
  local target = TargetOf(fs)
  applying = true
  if target and Get(target .. "Enabled") then
    local path = ns.SafeFontPath(Get(target .. "Font") or ns.FONT_FALLBACK)
    local size, style = Get(target .. "Size") or 12, Get(target .. "Outline")
    if target ~= "bagItem" then size = SnapSize(fs, size) end
    -- SLUG réservé à Baganator : sur les nameplates, textes et opacités sont des valeurs
    -- secrètes en combat, l'anneau ne peut pas les suivre. Repli sur le contour fin.
    local slug = style == "SLUG" and target == "bagItem"
    if style == "SLUG" and not slug then style = "OUTLINE" end
    local shadow = SHADOW_STYLES[style]
    if (slug or shadow) and not origShadow[fs] then
      local x, y = fs:GetShadowOffset()
      local r, g, b, a = fs:GetShadowColor()
      origShadow[fs] = { x, y, r, g, b, a }
    end
    local ring = (slug or rings[fs]) and EnsureRing(fs) or nil
    if ring then
      ns.ApplyTextOutlineStyle(fs, ring, path, size, slug and "SLUG" or ((style == "NONE" or style == "SHADOW") and "" or FLAGS[style] or style), false)
    else
      pcall(fs.SetFont, fs, path, size, FLAGS[style] or "OUTLINE")
    end
    if slug then
      fs:SetShadowOffset(0, 0)
    elseif shadow then
      fs:SetShadowColor(0, 0, 0, 1)
      fs:SetShadowOffset(1, -1)
    elseif origShadow[fs] then
      RestoreShadow(fs)
    end
    slugOn[fs] = slug or nil
    customized[fs] = true
  elseif customized[fs] then
    local o = origFont[fs]
    if o and o[1] then pcall(fs.SetFont, fs, o[1], o[2], o[3]) end
    if origShadow[fs] then RestoreShadow(fs) end
    slugOn[fs] = nil
    customized[fs] = nil
  end
  applying = false
  SyncRing(fs)
end

-- Nameplates amicales en instance : objets interdits aux addons. IsForbidden() ne suffit pas
-- (un texte peut l'être via sa nameplate sans se déclarer interdit) : toute lecture est protégée,
-- et un objet illisible est simplement ignoré.
local function ReadFont(fs)
  local ok, path, size, flags = pcall(fs.GetFont, fs)
  if not ok then return nil end
  return { path, size, flags }
end

local function Apply(fs)
  local ok = pcall(ApplyUnsafe, fs)
  if not ok then applying = false end
end

-- L'addon d'origine vient de (re)poser sa police : on la mémorise puis on réapplique la nôtre.
local function OnOwnerFont(fs)
  if applying then return end
  local font = ReadFont(fs)
  if not font then return end
  origFont[fs] = font
  if customized[fs] or TargetOf(fs) then Apply(fs) end
end

local function Track(fs, target, owner)
  if tracked[fs] then return end
  local font = ReadFont(fs)
  if not font then return end
  tracked[fs] = target
  owners[fs] = owner
  origFont[fs] = font
  hooksecurefunc(fs, "SetFont", OnOwnerFont)
  hooksecurefunc(fs, "SetFontObject", OnOwnerFont)
  Apply(fs)
end

-- ── Platynator ──────────────────────────────────────────────────────────────

-- Les frames d'aura sont créées à la demande puis recyclées : UNIT_AURA n'est écouté que par
-- fenêtres (nouvelle display, entrée en combat) et coupé après AURA_QUIET s sans nouvelle frame.
local AURA_QUIET = 20
local platEv = CreateFrame("Frame")
local auraListening, lastDiscovery = false, 0

local function ListenAuras()
  lastDiscovery = GetTime()
  if not auraListening then
    auraListening = true
    platEv:RegisterEvent("UNIT_AURA")
  end
end

local function ScanPlatDisplay(display)
  local am = display.AurasManager
  if am then
    for _, kind in ipairs(AURA_KINDS) do
      local c = am[kind]
      local frames = c and c.frames
      if frames then
        -- Toutes les frames à chaque passe (Track est idempotent) : si Platynator recrée un
        -- texte sans changer le nombre de frames, le nouveau FontString est quand même repris.
        local seen = seenFrames[c] or 0
        if #frames > seen then lastDiscovery = GetTime() end
        for i = 1, #frames do
          local tc = frames[i].TextsContainer
          local cd = tc and tc.Countdown
          if cd and not tracked[cd] then
            Track(cd, "platAura")
            lastDiscovery = GetTime()
          end
        end
        seenFrames[c] = #frames
      end
    end
  end
  local widgets = display.widgets
  if widgets then
    for _, w in ipairs(widgets) do
      if w.text and w.details and w.details.kind == "level" then Track(w.text, "platLevel", w) end
    end
  end
end

-- Platynator préalloue une display par style sur chaque nameplate (ennemi, amical...) :
-- seule celle dont .unit vaut l'unité est active, les autres restent cachées.
local function FindDisplay(np, unit)
  if not np or np:IsForbidden() or np:GetNumChildren() == 0 then return nil end
  local shown
  for _, child in ipairs({ np:GetChildren() }) do
    if child.AurasManager or child.widgets then
      if child.unit == unit or child.interactUnit == unit then return child end
      if not shown and child:IsShown() then shown = child end
    end
  end
  return shown
end

local dirty, flushPending = {}, false

local function Flush()
  flushPending = false
  for unit, isNew in pairs(dirty) do
    dirty[unit] = nil
    if isNew == "added" or not unitDisplay[unit] or unitDisplay[unit].unit ~= unit then
      local ok, d = pcall(FindDisplay, C_NamePlate.GetNamePlateForUnit(unit), unit)
      unitDisplay[unit] = ok and d or nil
    end
    local d = unitDisplay[unit]
    if d then
      if not seenDisplays[d] then seenDisplays[d] = true; ListenAuras() end
      pcall(ScanPlatDisplay, d)
    end
  end
  if auraListening and GetTime() - lastDiscovery > AURA_QUIET then
    auraListening = false
    platEv:UnregisterEvent("UNIT_AURA")
  end
end

local function MarkDirty(unit, how)
  if dirty[unit] ~= "added" then dirty[unit] = how end
  if not flushPending then
    flushPending = true
    C_Timer.After(0.1, Flush)
  end
end

platEv:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_REGEN_DISABLED" then
    ListenAuras()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    MarkDirty(unit, "added")
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    unitDisplay[unit] = nil
  elseif unitDisplay[unit] then -- UNIT_AURA : nouvelles frames d'aura créées à la demande
    MarkDirty(unit, "aura")
  end
end)

local function SetPlatActive(on)
  if on then
    platEv:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    platEv:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    platEv:RegisterEvent("PLAYER_REGEN_DISABLED")
    ListenAuras()
    for _, np in ipairs(C_NamePlate.GetNamePlates()) do
      local unit = np.namePlateUnitToken
      if unit then MarkDirty(unit, "added") end
    end
  else
    platEv:UnregisterAllEvents()
    auraListening = false
    wipe(unitDisplay)
  end
end

-- ── Baganator ───────────────────────────────────────────────────────────────

local function OnBagRegion(details)
  if not bagActive or details.regionType ~= "CornerWidget" then return end
  local r = details.region
  -- Les icônes d'amélioration de qualité sont du balisage d'atlas : on n'y touche pas.
  if details.tags and details.tags[1] == "item_quality_upgrade_icons" then return end
  if r and r.GetObjectType and r:GetObjectType() == "FontString" then Track(r, "bagItem") end
end

-- Skins Baganator qui posent déjà leur propre police sur ces textes (ElvUI : police des sacs
-- d'ElvUI via FontTemplate ; GW2 UI : police imposée) : on s'efface pour ne pas se battre avec eux.
local BAG_SKIN_CONFLICTS = { elvui = "ElvUI", gw2_ui = "GW2 UI" }
function AddonFonts.BagSkinConflict()
  local api = Baganator and Baganator.API and Baganator.API.Skins
  if not (api and api.GetCurrentSkin) then return nil end
  local ok, skin = pcall(api.GetCurrentSkin)
  return ok and skin and BAG_SKIN_CONFLICTS[skin] or nil
end

local function SetBagActive(on)
  local api = Baganator and Baganator.API and Baganator.API.Skins
  if not api then return end
  bagActive = on
  if not on then return end
  if not bagHooked then
    bagHooked = true
    api.RegisterListener(OnBagRegion)
  end
  for _, details in ipairs(api.GetAllFrames() or {}) do OnBagRegion(details) end
end

-- ── Application ─────────────────────────────────────────────────────────────

function AddonFonts.ApplySettings()
  SetPlatActive(Platynator ~= nil and (Get("platAuraEnabled") or Get("platLevelEnabled")) and true or false)
  SetBagActive(Get("bagItemEnabled") and not AddonFonts.BagSkinConflict() and true or false)
  for fs in pairs(tracked) do Apply(fs) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  AddonFonts.ApplySettings()
end)

-- Modules/AddonCompartment.lua : "Compartiment d'addons" -- range les boutons de minimap des addons (LibDBIcon et
-- boutons classiques) dans un seul bouton ancre a la minimap, qui affiche leur nombre. Clic (ou survol) : liste
-- (icone + nom) ou grille d'icones, avec une arrivee en cascade.
-- Les vrais boutons sont reparentes sur leur case, invisibles (alpha 0) mais toujours cliquables : clics, menus et
-- infobulles restent ceux de l'addon. La case dessine sa propre copie de l'icone et le nom.
-- Par addon (cle = nom LibDBIcon ou nom du cadre), reglage du compte : masque (hidden) ou favori (favorites) -- les favoris quittent la liste et s'affichent en grille directement sur la minimap.
-- Reglages : page "Compartiment d'addons" (EXTRAS), cf. UI/AddonCompartmentPage.lua.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local AC = {}
ns.Modules.AddonCompartment = AC

local DEFAULT_FONT = ns.FONT_FALLBACK
local MEDIA = "Interface\\AddOns\\AishCore\\Media\\"
local SELF_BUTTON = "AishCoreMinimapButton"
local SELF_ICON = MEDIA .. "logo_icon.tga"
local STAGGER, ARRIVE, FADE, SLIDE = 0.022, 0.18, 0.12, 12   -- cascade : ecart entre cases, duree d'une case, fond, glissement
local HOVER_TIME, HOVER_GROW = 0.12, 0.15
local HOVER_CLOSE_DELAY = 0.45   -- ouverture au survol : delai avant fermeture une fois la souris sortie

-- Textures de fond : `nine` = decoupe en 9 des Barres dynamiques (ExtraBars.StyleBackground), sinon image etiree
AC.BG_TEXTURES = {
  { value = "none" },
  { value = "solid",      nine = true },
  { value = "soft",       nine = true },
  { value = "grunge",     nine = true },
  { value = "grungeSoft", nine = true },
  { value = "xpGrunge",   file = MEDIA .. "XPBar\\grunge_spot1.png" },
  { value = "xpRect",     file = MEDIA .. "XPBar\\grunge_shadow_rectangle.png" },
  { value = "xpShadow",   file = MEDIA .. "XPBar\\grunge_shadow_big.png" },
  { value = "circle",     file = MEDIA .. "Skyriding\\Circle_Smooth.tga" },
}
local NO_BG = { tex = "none" }
local BG_BY = {}
for _, d in ipairs(AC.BG_TEXTURES) do BG_BY[d.value] = d end

local function Cfg()
  return ns.GetCfg("addonCompartment") or {}
end

local function Loc(key)
  return (ns.L and ns.L[key]) or key
end

-- Couleur thematique du module Couleurs si l'option `flag` n'est pas decochee, sinon couleur propre du reglage
local function ThemeColor(cfg, flag, element, own, default)
  if cfg[flag] ~= false then
    local CL = ns.Modules.Colors
    local c = CL and CL.Get and CL.Get(element)
    if c then return c end
  end
  return own or default
end

local function EaseOut(v)
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  local i = 1 - v
  return 1 - i * i * i
end

-- Fond d'un cadre : `holder` = zone de contenu (w x h), le fond deborde de padX / padY
local function StyleBg(holder, o, w, h)
  local d = BG_BY[o.tex] or BG_BY.none
  local EB = ns.Modules.ExtraBars
  if EB and EB.StyleBackground then
    EB.StyleBackground(holder, {
      bgEnabled = d.nine == true, bgTexture = o.tex, bgColor = o.color, bgPadX = o.padX, bgPadY = o.padY,
      bgEdge = o.edge, bgBorderSize = o.border, bgBorderColor = o.borderColor,
    }, w, h, d.nine == true)
  end
  local t = holder.__acTex
  if not d.file then
    if t then t:Hide() end
    return
  end
  if not t then
    t = holder:CreateTexture(nil, "BACKGROUND", nil, -7)
    holder.__acTex = t
  end
  local c = o.color or { 0, 0, 0, 0.8 }
  t:SetTexture(d.file)
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", holder, "TOPLEFT", -(o.padX or 0), o.padY or 0)
  t:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", o.padX or 0, -(o.padY or 0))
  t:Show()
end

-- Noms et icones ---------------------------------------------------------------------------------------
local function StripCodes(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Compact(s)
  return (tostring(s or ""):lower():gsub("[^%w]", ""))
end

-- Titres des addons installes, indexes par nom compact ("Details!" -> "details")
local addonTitles
local function AddonTitles()
  if addonTitles then return addonTitles end
  addonTitles = {}
  local num = (C_AddOns and C_AddOns.GetNumAddOns or _G.GetNumAddOns)()
  local info = (C_AddOns and C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
  for i = 1, num do
    local name, title = info(i)
    if name then
      local t = StripCodes(title)
      addonTitles[Compact(name)] = (t ~= "" and t) or name
    end
  end
  return addonTitles
end

-- Nom lisible d'un bouton classique : nom du cadre nettoye, puis rapproche d'un addon installe
local function GuessLabel(frameName)
  local s = frameName
  s = s:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", "")
  for _, suf in ipairs({ "MinimapButton", "MiniMapButton", "Minimap_Button", "MinimapIcon", "MiniMapIcon",
                         "MapButton", "MapIcon", "Minimap", "MiniMap", "Button", "Icon", "Frame" }) do
    s = s:gsub("_?" .. suf .. "%d*$", "")
  end
  s = s:gsub("[_%d]+$", "")
  if s == "" then s = frameName end
  local key = Compact(s)
  local titles = AddonTitles()
  if titles[key] then return titles[key] end
  -- Addon dont le nom commence le nom du bouton (le plus long gagne)
  local best, bestLen
  for k, t in pairs(titles) do
    if #k >= 3 and key:sub(1, #k) == k and (not bestLen or #k > bestLen) then best, bestLen = t, #k end
  end
  return best or s
end

-- Textures d'habillage des boutons de minimap (bordure ronde, fond, survol) : jamais prises pour l'icone
local SKIP_TEX = {
  [136430] = true, [136467] = true, [136477] = true,
  ["interface\\minimap\\minimap-trackingborder"] = true,
  ["interface\\minimap\\ui-minimap-background"] = true,
  ["interface\\minimap\\ui-minimap-zoombutton-highlight"] = true,
  ["interface\\characterframe\\tempportraitalphamask"] = true,
}
local function Skipped(tex)
  if type(tex) == "string" then return SKIP_TEX[tex:lower()] == true end
  return SKIP_TEX[tex] == true
end

local function HasArt(t)
  return t and t.IsObjectType and t:IsObjectType("Texture") and (t:GetAtlas() or t:GetTexture()) and true or false
end

local function FindIcon(btn)
  for _, k in ipairs({ "icon", "Icon", "texture", "Texture" }) do
    local t = btn[k]
    if type(t) == "table" and HasArt(t) and not Skipped(t:GetTexture()) then return t end
  end
  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  if HasArt(n) and not Skipped(n:GetTexture()) then return n end
  -- Sinon la plus grande texture qui n'est ni la bordure ni le survol
  local best, bestA
  for _, r in ipairs({ btn:GetRegions() }) do
    if HasArt(r) and r:GetDrawLayer() ~= "HIGHLIGHT" and not Skipped(r:GetTexture()) then
      local a = (r:GetWidth() or 0) * (r:GetHeight() or 0)
      if not bestA or a > bestA then best, bestA = r, a end
    end
  end
  return best
end

local function CopyIcon(dst, rec)
  if rec.self then
    dst:SetTexture(SELF_ICON)
    dst:SetTexCoord(0, 1, 0, 1)
    dst:SetVertexColor(1, 1, 1, 1)
    dst:SetDesaturated(false)
    return
  end
  local src = rec.icon
  if not (src and HasArt(src)) then
    src = FindIcon(rec.btn)
    rec.icon = src
  end
  if not src then
    dst:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    dst:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dst:SetVertexColor(1, 1, 1, 1)
    return
  end
  local atlas = src:GetAtlas()
  if atlas then
    dst:SetAtlas(atlas)
  else
    dst:SetTexture(src:GetTexture())
    dst:SetTexCoord(src:GetTexCoord())
  end
  local r, g, b = src:GetVertexColor()
  dst:SetVertexColor(r or 1, g or 1, b or 1, 1)
  dst:SetDesaturated(src:IsDesaturated() and true or false)
end

-- Cadres ---------------------------------------------------------------------------------------------------
local mainBtn, countText, countRing, popup, content, emptyText, driver, favFrame
local records = {}   -- bouton d'origine -> fiche
local order = {}     -- fiches affichees dans la liste, dans l'ordre
local favOrder = {}  -- favoris poses sur la minimap
local favAlpha = 1
local isOpen, preview = false, false
local animT, animating = 0, false
local slideX, slideY = 0, 0
local hoverOff = 0
local pendingLayout = false

local function Kick() end   -- forward (driver d'animation, defini plus bas)

-- Un favori a deux cases (liste + minimap) pour un seul vrai bouton : rec.home = case qui le porte. L'autre case
-- montre un "capteur" : le survoler y amene le bouton (clics, menus, infobulle de l'addon).
local function MoveHome(rec, cell)
  if not cell or rec.home == cell then return end
  if rec.home then rec.home._ht = 0 end
  rec.home = cell
  if rec.active then
    rec.seatNow(rec)
  end
  for _, c in ipairs({ rec.cell, rec.favCell }) do
    if c then c.catch:SetShown(rec.isFav and c ~= rec.home) end
  end
end

local function NewCell(rec, parent, fav)
  local cell = CreateFrame("Frame", nil, parent)
  cell:Hide()
  cell.vis = CreateFrame("Frame", nil, cell)
  cell.vis:SetSize(1, 1)
  cell.hl = cell.vis:CreateTexture(nil, "BACKGROUND")
  cell.hl:SetTexture("Interface\\Buttons\\WHITE8x8")
  cell.hl:SetAllPoints(cell.vis)
  cell.hl:SetAlpha(0)
  -- Halo derriere l'icone survolee (favoris) : degrade radial doux, facon projecteur
  cell.glow = cell.vis:CreateTexture(nil, "BACKGROUND", nil, 1)
  cell.glow:SetTexture(MEDIA .. "UI\\SpotGlow.tga")
  cell.glow:SetBlendMode("ADD")
  cell.glow:SetAlpha(0)
  cell.iconHolder = CreateFrame("Frame", nil, cell.vis)
  cell.icon = cell.iconHolder:CreateTexture(nil, "ARTWORK")
  cell.icon:SetAllPoints(cell.iconHolder)
  cell.label = cell.vis:CreateFontString(nil, "OVERLAY")
  cell.label:SetFont(DEFAULT_FONT, 12, "OUTLINE")
  cell.label:SetJustifyH("LEFT")
  cell.label:SetWordWrap(false)
  cell._fav = fav and true or false
  cell.catch = CreateFrame("Frame", nil, cell)
  cell.catch:SetAllPoints(cell)
  cell.catch:SetFrameLevel(cell:GetFrameLevel() + 3)
  cell.catch:EnableMouse(true)
  cell.catch:Hide()
  cell.catch:SetScript("OnEnter", function() MoveHome(rec, cell) end)
  return cell
end

-- Place le vrai bouton sur sa case (garde : nos propres SetPoint ne doivent pas relancer les crochets)
local function Seat(rec)
  local b, home = rec.btn, rec.home or rec.cell
  rec.seating = true
  if b:GetParent() ~= home then b:SetParent(home) end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", home, "TOPLEFT", 0, 0)
  b:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", 0, 0)
  b:SetScale(1)
  b:SetAlpha(0)
  -- LibDBIcon fige strata et niveau (MEDIUM / 8) : sans ce deverrouillage le bouton reste sous la liste, qui capte la souris
  if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
  if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
  b:SetFrameStrata(home:GetFrameStrata())
  b:SetFrameLevel(home:GetFrameLevel() + 6)
  rec.seating = false
end

local function RequestLayout()
  if pendingLayout then return end
  pendingLayout = true
  C_Timer.After(0, function()
    pendingLayout = false
    AC.Layout()
  end)
end

local function Hook(rec)
  if rec.hooked then return end
  rec.hooked = true
  local b = rec.btn
  -- L'addon repositionne son bouton autour de la minimap (glisser, forme de la minimap...) : retour sur la case
  hooksecurefunc(b, "SetPoint", function() if rec.active and not rec.seating then Seat(rec) end end)
  hooksecurefunc(b, "SetParent", function() if rec.active and not rec.seating then Seat(rec) end end)
  hooksecurefunc(b, "SetAlpha", function(self, a)
    if rec.active and not rec.seating and a ~= 0 then
      rec.seating = true
      self:SetAlpha(0)
      rec.seating = false
    end
  end)
  -- Bouton masque / affiche par son addon (option "cacher l'icone de minimap") : compteur et liste a jour
  hooksecurefunc(b, "Show", function() if rec.active then RequestLayout() end end)
  hooksecurefunc(b, "Hide", function() if rec.active then RequestLayout() end end)
  hooksecurefunc(b, "SetShown", function() if rec.active then RequestLayout() end end)
  b:HookScript("OnEnter", function()
    if rec.active and rec.home then rec.home._ht = 1; Kick() end
  end)
  b:HookScript("OnLeave", function()
    if rec.active and rec.home then rec.home._ht = 0; Kick() end
  end)
end

local function Capture(b, label, libName)
  local rec = records[b]
  if rec and rec.active then return end
  if not rec then
    rec = { btn = b }
    records[b] = rec
  end
  local name = b:GetName()
  rec.libName = libName
  rec.key = libName or name
  rec.self = (name == SELF_BUTTON)
  rec.label = rec.self and "AishCore" or label or (name and GuessLabel(name)) or "?"
  rec.sortKey = rec.label:lower()
  rec.icon = nil
  local pts = {}
  for i = 1, b:GetNumPoints() do pts[i] = { b:GetPoint(i) } end
  rec.orig = {
    parent = b:GetParent(), points = pts, scale = b:GetScale(), alpha = b:GetAlpha(),
    strata = b:GetFrameStrata(), level = b:GetFrameLevel(), w = b:GetWidth(), h = b:GetHeight(),
    fixedStrata = b.HasFixedFrameStrata and b:HasFixedFrameStrata(),
    fixedLevel = b.HasFixedFrameLevel and b:HasFixedFrameLevel(),
  }
  if not rec.cell then rec.cell = NewCell(rec, content, false) end
  rec.seatNow = Seat
  rec.home = rec.cell
  rec.isFav = false
  rec.active = true
  b.__aishCompartment = true
  Hook(rec)
  Seat(rec)
  -- Repris a un autre collecteur qui l'avait cache : on le reaffiche (alpha 0, sur sa case)
  if not b:IsShown() and _G._EBS_AddonVisible and _G._EBS_AddonVisible[b] == true then b:Show() end
end

local function Release(rec)
  if not rec.active then return end
  local b, o = rec.btn, rec.orig
  rec.active = false
  b.__aishCompartment = nil
  rec.seating = true
  b:SetParent(o.parent)
  b:SetScale(o.scale or 1)
  b:SetAlpha(o.alpha or 1)
  b:SetFrameStrata(o.strata or "MEDIUM")
  b:SetFrameLevel(o.level or 1)
  if o.fixedStrata and b.SetFixedFrameStrata then b:SetFixedFrameStrata(true) end
  if o.fixedLevel and b.SetFixedFrameLevel then b:SetFixedFrameLevel(true) end
  b:ClearAllPoints()
  for _, p in ipairs(o.points) do b:SetPoint(unpack(p)) end
  if o.w and o.w > 0 then b:SetSize(o.w, o.h) end
  rec.seating = false
  if rec.cell then rec.cell:Hide() end
  if rec.favCell then rec.favCell:Hide() end
  local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
  if rec.libName and LDBI and LDBI.Refresh then pcall(LDBI.Refresh, LDBI, rec.libName) end
end

-- Recherche des boutons ------------------------------------------------------------------------------------
-- Cadres Blizzard (ou repères de carte) poses sur la minimap : jamais ranges
local IGNORE = {
  "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^ExpansionLanding", "^GarrisonLanding", "^QueueStatus",
  "^AddonCompartment", "^LFG", "^Battlefield", "^HybridMinimap", "^MinimapCluster", "^Hybrid",
  "Pin%d*$", "Node%d*$", "^HandyNotes", "^GatherMate", "^TomTom", "^Questie.*Note", "^HereBeDragons",
}

-- EllesmereUI (module Minimap) cache les boutons qu'il collecte (Hide + alpha 0) et note dans _EBS_AddonVisible
-- si l'addon, lui, veut son bouton affiche : on se fie a cette intention plutot qu'a IsShown.
local function WantedShown(f)
  local ev = _G._EBS_AddonVisible
  if ev and ev[f] ~= nil then return ev[f] == true end
  return f:IsShown()
end

local function IsCandidate(f)
  if type(f) ~= "table" or f == mainBtn or (records[f] and records[f].active) then return false end
  if f.IsForbidden and f:IsForbidden() then return false end
  if f:IsProtected() then return false end   -- jamais de cadre securise (reparentage interdit en combat)
  local name = f:GetName()
  if not name then return false end
  if name:find("^AishCore") and name ~= SELF_BUTTON then return false end
  for _, pat in ipairs(IGNORE) do
    if name:find(pat) then return false end
  end
  local clickable = f:IsObjectType("Button") or (f:HasScript("OnMouseUp") and f:GetScript("OnMouseUp") ~= nil)
  if not clickable or not f:IsMouseEnabled() then return false end
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  if w < 12 or h < 12 or w > 64 or h > 64 then return false end
  return WantedShown(f)
end

function AC.Scan()
  if not mainBtn or Cfg().enabled ~= true then return end
  local changed = false
  -- LibDBIcon : la grande majorite des addons ; ranges meme masques (l'addon peut les reafficher)
  local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
  if LDBI and type(LDBI.objects) == "table" then
    for name, b in pairs(LDBI.objects) do
      if type(b) == "table" and not (records[b] and records[b].active) and not b:IsProtected() then
        local dobj = b.dataObject
        local label = StripCodes((dobj and dobj.label) or name)
        local t = AddonTitles()[Compact(name)]
        Capture(b, (label ~= "" and label) or t or name, name)
        changed = true
      end
    end
  end
  -- Boutons classiques poses sur la minimap
  for _, parent in ipairs({ Minimap, _G.MinimapBackdrop }) do
    if parent then
      for _, f in ipairs({ parent:GetChildren() }) do
        if IsCandidate(f) then
          Capture(f)
          changed = true
        end
      end
    end
  end
  if changed then RequestLayout() end
end

function AC.ReleaseAll()
  for _, rec in pairs(records) do Release(rec) end
end

-- Masques / favoris : reglages du compte (AishaddonDB._device, cf. ns.GetDeviceSettings), jamais du profil --
-- les addons installes sont ceux du compte, quel que soit le profil actif.
local function Flags(field)
  local dev = ns.GetDeviceSettings and ns.GetDeviceSettings() or {}
  dev.addonCompartment = dev.addonCompartment or {}
  local db = dev.addonCompartment
  if type(db[field]) ~= "table" then db[field] = {} end
  -- Ancien emplacement (profil actif) : repris une fois puis retire du profil
  local prof = ns.DB and ns.DB.addonCompartment
  if prof and type(prof[field]) == "table" then
    for k, v in pairs(prof[field]) do if db[field][k] == nil then db[field][k] = v end end
    prof[field] = nil
  end
  return db[field]
end

local function Flag(field, key)
  return key ~= nil and Flags(field)[key] == true
end

function AC.IsHidden(key) return Flag("hidden", key) end
function AC.IsFavorite(key) return Flag("favorites", key) end
function AC.SetHidden(key, v)
  Flags("hidden")[key] = v and true or nil
  RequestLayout()
end
function AC.SetFavorite(key, v)
  Flags("favorites")[key] = v and true or nil
  RequestLayout()
end

local function SortRecs(list)
  table.sort(list, function(a, b)
    if a.self ~= b.self then return a.self and true or false end
    return a.sortKey < b.sortKey
  end)
end

-- Tous les addons ranges (page de reglages) : { key, label, rec }
function AC.GetEntries()
  local list = {}
  for _, rec in pairs(records) do
    if rec.active and rec.key then list[#list + 1] = rec end
  end
  SortRecs(list)
  local out = {}
  for i, rec in ipairs(list) do out[i] = { key = rec.key, label = rec.label, rec = rec } end
  return out
end

function AC.CopyIcon(dst, rec)
  CopyIcon(dst, rec)
end

-- Liste affichee ----------------------------------------------------------------------------------------
local function BuildOrder()
  wipe(order)
  wipe(favOrder)
  local cfg = Cfg()
  local cap = math.max(1, math.floor(cfg.favColumns or 1)) * math.max(1, math.floor(cfg.favRows or 1))
  local favs = {}
  for _, rec in pairs(records) do
    rec.isFav = false
    if rec.active and rec.btn:IsShown() and not AC.IsHidden(rec.key) then
      -- Les favoris restent aussi dans la liste
      order[#order + 1] = rec
      if AC.IsFavorite(rec.key) then favs[#favs + 1] = rec end
    elseif rec.cell then
      rec.cell:Hide()
    end
  end
  SortRecs(favs)
  -- Favoris au-dela de la grille (colonnes x lignes) : seulement dans la liste
  for i, rec in ipairs(favs) do
    if i <= cap then
      favOrder[#favOrder + 1] = rec
      rec.isFav = true
    end
  end
  for _, rec in pairs(records) do
    if not rec.isFav and rec.favCell then rec.favCell:Hide() end
    -- Case qui porte le vrai bouton : la liste pour un addon ordinaire ; pour un favori, la minimap,
    -- sauf s'il vient d'etre amene dans la liste ouverte
    if rec.active then
      if not rec.isFav then
        MoveHome(rec, rec.cell)
      else
        -- Case de la minimap creee meme quand le bouton reste dans la liste ouverte (favori ajoute liste ouverte) :
        -- l'animation et la disposition des favoris la parcourent
        rec.favCell = rec.favCell or NewCell(rec, favFrame, true)
        if not (rec.home == rec.cell and isOpen) then MoveHome(rec, rec.favCell) end
      end
      for _, c in ipairs({ rec.cell, rec.favCell }) do
        if c then c.catch:SetShown(rec.isFav and c ~= rec.home) end
      end
    end
  end
  SortRecs(order)
end

function AC.Count()
  return #order
end

-- Ouverture : direction ("down", "up", "left", "right") et bord d'alignement, auto = vers le centre de l'ecran
local function Direction(cfg)
  local x, y = mainBtn:GetCenter()
  local s = mainBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
  x, y = (x or 0) * s, (y or 0) * s
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local top, right = y > H / 2, x > W / 2
  local dir = cfg.direction or "auto"
  if dir == "auto" then dir = top and "down" or "up" end
  return dir, top, right
end

local function PlacePopup(cfg)
  local dir, top, right = Direction(cfg)
  local gap = cfg.gap or 4
  popup:ClearAllPoints()
  local h = right and "RIGHT" or "LEFT"
  local v = top and "TOP" or "BOTTOM"
  if dir == "down" then
    popup:SetPoint("TOP" .. h, mainBtn, "BOTTOM" .. h, 0, -gap)
    slideX, slideY = 0, SLIDE
  elseif dir == "up" then
    popup:SetPoint("BOTTOM" .. h, mainBtn, "TOP" .. h, 0, gap)
    slideX, slideY = 0, -SLIDE
  elseif dir == "left" then
    popup:SetPoint(v .. "RIGHT", mainBtn, v .. "LEFT", -gap, 0)
    slideX, slideY = SLIDE, 0
  else
    popup:SetPoint(v .. "LEFT", mainBtn, v .. "RIGHT", gap, 0)
    slideX, slideY = -SLIDE, 0
  end
end

local function PaintCell(cell, cfg, isList)
  local h = cell._h or 0
  local hc = ThemeColor(cfg, "hoverThemed", "powerdotsb", cfg.hoverColor, { 1, 0.82, 0.2, 1 })
  cell.hl:SetVertexColor(hc[1], hc[2], hc[3], 1)
  cell.hl:SetAlpha(cell._fav and 0 or (isList and 0.18 or 0.12) * h)
  cell.glow:SetVertexColor(hc[1], hc[2], hc[3], 1)
  cell.glow:SetAlpha(cell._fav and 0.9 * h or 0)
  cell.iconHolder:SetScale(1 + (isList and 0 or HOVER_GROW) * h)
  if isList then
    local c = cfg.listColor or { 0.95, 0.9, 0.8, 1 }
    cell.label:SetTextColor(c[1] + (hc[1] - c[1]) * h, c[2] + (hc[2] - c[2]) * h, c[3] + (hc[3] - c[3]) * h, 1)
  end
end

-- Position animee d'une case : p = 0 (depart, decalee et transparente) a 1 (en place)
local function PlaceVis(cell, p)
  local e = EaseOut(p)
  cell.vis:ClearAllPoints()
  cell.vis:SetPoint("TOPLEFT", cell, "TOPLEFT", slideX * (1 - e), slideY * (1 - e))
  cell.vis:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", slideX * (1 - e), slideY * (1 - e))
  cell.vis:SetAlpha(e)
end

function AC.Layout()
  if not mainBtn then return end
  local cfg = Cfg()
  local n = 0
  BuildOrder()
  n = #order
  countText:SetText(n)

  local isList = cfg.layout == "list"
  local icon = math.max(10, cfg.iconSize or 26)
  local gap = cfg.spacing or 4
  local cols, cw, ch
  local font = cfg.font or DEFAULT_FONT
  if isList then
    cols = math.max(1, math.floor(cfg.listColumns or 1))
    local fs = cfg.listFontSize or 12
    font = cfg.listFont or font   -- police propre aux noms de la liste (sinon celle du bouton)
    local maxW = 0
    for _, rec in ipairs(order) do
      local lbl = rec.cell.label
      if not pcall(lbl.SetFont, lbl, font, fs, "OUTLINE") or not lbl:GetFont() then lbl:SetFont(DEFAULT_FONT, fs, "OUTLINE") end
      lbl:SetText(rec.label)
      maxW = math.max(maxW, lbl:GetStringWidth() or 0)
    end
    ch = math.max(icon, fs + 4) + 4
    cw = math.ceil(4 + icon + 8 + math.min(maxW, 260) + 8)
  else
    cols = math.max(1, math.floor(cfg.columns or 5))
    cw, ch = icon, icon
  end
  cols = math.max(1, math.min(cols, n))
  local rows = math.max(1, math.ceil(n / cols))

  for i, rec in ipairs(order) do
    local cell = rec.cell
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    cell:ClearAllPoints()
    cell:SetSize(cw, ch)
    cell:SetPoint("TOPLEFT", content, "TOPLEFT", c * (cw + gap), -r * (ch + gap))
    cell.iconHolder:ClearAllPoints()
    cell.iconHolder:SetSize(icon, icon)
    cell.label:ClearAllPoints()
    if isList then
      cell.iconHolder:SetPoint("LEFT", cell.vis, "LEFT", 4, 0)
      cell.label:SetPoint("LEFT", cell.iconHolder, "RIGHT", 8, 0)
      cell.label:SetPoint("RIGHT", cell.vis, "RIGHT", -6, 0)
      cell.label:Show()
    else
      cell.iconHolder:SetPoint("CENTER", cell.vis, "CENTER", 0, 0)
      cell.label:Hide()
    end
    CopyIcon(cell.icon, rec)
    StyleBg(cell, NO_BG, cw, ch)
    if not animating then PlaceVis(cell, 1) end
    PaintCell(cell, cfg, isList)
    cell:Show()
    Seat(rec)
  end

  local w = (n > 0) and (cols * cw + (cols - 1) * gap) or 0
  local h = (n > 0) and (rows * ch + (rows - 1) * gap) or 0
  emptyText:SetShown(n == 0)
  if n == 0 then
    emptyText:SetFont(DEFAULT_FONT, 12, "OUTLINE")
    emptyText:SetText(Loc("ADDONCOMP_EMPTY"))
    w, h = math.ceil(emptyText:GetStringWidth() or 120), 16
  end
  local px, py = cfg.bgPadX or 10, cfg.bgPadY or 10
  content:SetSize(math.max(w, 1), math.max(h, 1))
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", popup, "TOPLEFT", px, -py)
  popup:SetSize(math.max(w, 1) + 2 * px, math.max(h, 1) + 2 * py)
  StyleBg(content, {
    tex = cfg.bgTexture or "grunge", color = cfg.bgColor, padX = px, padY = py, edge = cfg.bgEdge,
    border = cfg.bgBorderSize, borderColor = cfg.bgBorderColor,
  }, w, h)
  popup:SetScale(mainBtn:GetEffectiveScale() / UIParent:GetEffectiveScale())
  PlacePopup(cfg)
  AC.LayoutFavorites()
end

-- Favoris : grille posee sur la minimap (ancrage 9 points, colonnes x lignes)
function AC.LayoutFavorites()
  if not favFrame then return end
  local cfg = Cfg()
  local n = #favOrder
  if cfg.enabled ~= true or n == 0 or not Minimap:IsVisible() then
    favFrame:Hide()
    return
  end
  favFrame:SetScale(Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale())
  local size = math.max(10, cfg.favIconSize or 22)
  local gap = cfg.favSpacing or 4
  local cols = math.max(1, math.min(math.floor(cfg.favColumns or 1), n))
  local rows = math.ceil(n / cols)
  local ip = cfg.favIconBgPad or 2
  local iconBg = {
    tex = cfg.favIconBgTexture or "none", color = cfg.favIconBgColor, padX = ip, padY = ip,
    edge = math.floor(size / 3), border = cfg.favIconBgBorderSize, borderColor = cfg.favIconBgBorderColor,
  }
  for i, rec in ipairs(favOrder) do
    local cell = rec.favCell
    cell.glow:ClearAllPoints()
    cell.glow:SetSize(size * 3.4, size * 3.4)
    cell.glow:SetPoint("CENTER", cell.vis, "CENTER", 0, 0)
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    cell:ClearAllPoints()
    cell:SetSize(size, size)
    cell:SetPoint("TOPLEFT", favFrame, "TOPLEFT", c * (size + gap), -r * (size + gap))
    cell.iconHolder:ClearAllPoints()
    cell.iconHolder:SetSize(size, size)
    cell.iconHolder:SetPoint("CENTER", cell.vis, "CENTER", 0, 0)
    cell.label:Hide()
    CopyIcon(cell.icon, rec)
    StyleBg(cell, iconBg, size, size)
    PlaceVis(cell, 1)
    PaintCell(cell, cfg, false)
    cell:Show()
    Seat(rec)
  end
  local w, h = cols * size + (cols - 1) * gap, rows * size + (rows - 1) * gap
  favFrame:SetSize(w, h)
  StyleBg(favFrame, {
    tex = cfg.favBgTexture or "none", color = cfg.favBgColor, padX = cfg.favBgPadX or 6, padY = cfg.favBgPadY or 6,
    edge = cfg.favBgEdge, border = cfg.favBgBorderSize, borderColor = cfg.favBgBorderColor,
  }, w, h)
  favFrame:ClearAllPoints()
  local pt = cfg.favPoint or "TOPRIGHT"
  favFrame:SetPoint(pt, Minimap, pt, cfg.favX or 0, cfg.favY or 0)
  favFrame:Show()
  Kick()
end

-- Animations : cascade d'arrivee + survol des cases, un seul OnUpdate
local function Step(_, el)
  local cfg = Cfg()
  local isList = cfg.layout == "list"
  local active = false
  if animating then
    animT = animT + el
    popup:SetAlpha(math.min(1, animT / FADE))
    local done = true
    for i, rec in ipairs(order) do
      local p = (animT - (i - 1) * STAGGER) / ARRIVE
      if p < 1 then done = false end
      PlaceVis(rec.cell, p)
    end
    if done and animT >= FADE then animating = false else active = true end
  end
  for pass = 1, 2 do
    for _, rec in ipairs(pass == 1 and order or favOrder) do
      local cell = pass == 1 and rec.cell or rec.favCell
      local h, ht = cell._h or 0, cell._ht or 0
      if h ~= ht then
        local step = el / HOVER_TIME
        cell._h = (ht > h) and math.min(ht, h + step) or math.max(ht, h - step)
        PaintCell(cell, cfg, pass == 1 and isList)
        active = true
      end
    end
  end
  -- Favoris : opacite au repos / au survol, en fondu
  if favFrame and favFrame:IsShown() then
    local idle, hov = cfg.favAlpha or 1, cfg.favHoverAlpha or 1
    local target = (preview or favFrame:IsMouseOver()) and hov or idle
    if math.abs(favAlpha - target) > 0.01 then
      favAlpha = favAlpha + (target - favAlpha) * math.min(1, el * 10)
    else
      favAlpha = target
    end
    favFrame:SetAlpha(favAlpha)
    if idle ~= hov or favAlpha ~= target then active = true end
  end
  -- Ouverture au survol : fermeture une fois la souris sortie du bouton et de la liste
  if isOpen and not preview and cfg.openMode == "hover" then
    active = true
    if mainBtn:IsMouseOver() or popup:IsMouseOver() or AC.MenuOpen() then
      hoverOff = 0
    else
      hoverOff = hoverOff + el
      if hoverOff >= HOVER_CLOSE_DELAY then AC.Close() end
    end
  end
  if not active then driver:SetScript("OnUpdate", nil) end
end

Kick = function()
  if driver then driver:SetScript("OnUpdate", Step) end
end

-- Menu deroulant d'un addon ouvert (ne pas fermer la liste en cliquant dedans)
function AC.MenuOpen()
  local ok, open = pcall(function()
    local M = _G.Menu
    return M and M.GetManager and M.GetManager():IsAnyMenuOpen()
  end)
  if ok and open then return true end
  for _, n in ipairs({ "DropDownList1", "L_DropDownList1", "LibDropDownMenu_List1" }) do
    local f = _G[n]
    if f and f:IsShown() then return true end
  end
  return false
end

function AC.Open(noAnim)
  if not mainBtn or not mainBtn:IsShown() then return end
  AC.Scan()
  isOpen = true
  hoverOff = 0
  popup:Show()
  AC.Layout()
  if noAnim or Cfg().animate == false then
    animating = false
    popup:SetAlpha(1)
    for _, rec in ipairs(order) do PlaceVis(rec.cell, 1) end
  else
    animating, animT = true, 0
    popup:SetAlpha(0)
    for _, rec in ipairs(order) do PlaceVis(rec.cell, 0) end
  end
  Kick()
end

function AC.Close()
  if preview then return end
  isOpen = false
  if popup then popup:Hide() end
end

function AC.Toggle()
  if isOpen then AC.Close() else AC.Open() end
end

-- Rejoue la cascade (page de reglages)
function AC.Replay()
  if not popup then return end
  AC.Open()
end

-- Bouton principal ------------------------------------------------------------------------------------
local function StyleMain(cfg)
  local size = math.max(12, cfg.size or 26)
  mainBtn:SetSize(size, size)
  StyleBg(mainBtn, {
    tex = cfg.btnTexture or "circle", color = cfg.btnColor, padX = 0, padY = 0, edge = math.floor(size / 3),
    border = cfg.btnBorderSize, borderColor = cfg.btnBorderColor,
  }, size, size)
  local font = cfg.font or DEFAULT_FONT
  ns.ApplyTextOutlineStyle(countText, countRing, font, cfg.fontSize or 13, cfg.outline or "OUTLINE", true)
  local hov = mainBtn._hover
  local c = ThemeColor(cfg, "textThemed", "powercircle", cfg.textColor, { 1, 0.82, 0.2, 1 })
  if hov then c = ThemeColor(cfg, "hoverThemed", "powerdotsb", cfg.hoverColor, { 1, 0.82, 0.2, 1 }) end
  countText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  countText:ClearAllPoints()
  countText:SetPoint("CENTER", mainBtn, "CENTER", cfg.textX or 0, cfg.textY or 0)
  mainBtn:ClearAllPoints()
  local pt = cfg.point or "BOTTOMLEFT"
  mainBtn:SetScale(Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale())
  mainBtn:SetPoint("CENTER", Minimap, pt, cfg.x or 0, cfg.y or 0)
end

function AC.Create()
  if mainBtn then return end
  -- Enfant d'UIParent, ancre et echelle de la minimap : un enfant de la minimap est ramasse par les autres
  -- collecteurs de boutons (EllesmereUI le cachait dans son propre flyout)
  mainBtn = CreateFrame("Button", "AishCoreAddonCompartment", UIParent)
  mainBtn:SetFrameStrata("MEDIUM")
  mainBtn:SetFrameLevel(100)
  mainBtn:RegisterForClicks("AnyUp")
  mainBtn:Hide()
  -- Texte sur un cadre au-dessus du fond (le fond decoupe en 9 est lui-meme un cadre enfant du bouton)
  local textHolder = CreateFrame("Frame", nil, mainBtn)
  textHolder:SetAllPoints(mainBtn)
  textHolder:SetFrameLevel(mainBtn:GetFrameLevel() + 3)
  countText = textHolder:CreateFontString(nil, "OVERLAY")
  countText:SetFont(DEFAULT_FONT, 13, "OUTLINE")
  countText:SetJustifyH("CENTER")
  countRing = ns.CreateSlugRing(textHolder, countText, "ARTWORK")

  mainBtn:SetScript("OnClick", function()
    if Cfg().openMode ~= "hover" then AC.Toggle() end
  end)
  mainBtn:SetScript("OnEnter", function(self)
    self._hover = true
    StyleMain(Cfg())
    if Cfg().openMode == "hover" then
      if not isOpen then AC.Open() end
      hoverOff = 0
      return
    end
    if isOpen then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(Loc("SETTINGS_CAT_ADDON_COMPARTMENT"), 1, 1, 1)
    GameTooltip:AddLine(string.format(Loc("ADDONCOMP_TT_COUNT"), AC.Count()), 1, 0.82, 0.2)
    GameTooltip:AddLine(Loc("ADDONCOMP_TT_CLICK"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  mainBtn:SetScript("OnLeave", function(self)
    self._hover = false
    StyleMain(Cfg())
    GameTooltip:Hide()
  end)

  popup = CreateFrame("Frame", "AishCoreAddonCompartmentPopup", UIParent)
  popup:SetFrameStrata("FULLSCREEN")   -- au-dessus du GUI (DIALOG), sous les menus des addons (FULLSCREEN_DIALOG)
  popup:SetClampedToScreen(true)
  popup:EnableMouse(true)
  popup:Hide()
  popup:SetScript("OnHide", function()
    -- Favoris amenes dans la liste : retour sur la minimap
    for _, rec in pairs(records) do
      if rec.active and rec.isFav and rec.favCell then MoveHome(rec, rec.favCell) end
    end
    if preview then return end
    isOpen = false
  end)
  tinsert(UISpecialFrames, "AishCoreAddonCompartmentPopup")   -- Echap ferme la liste
  content = CreateFrame("Frame", nil, popup)
  content:SetFrameLevel(popup:GetFrameLevel() + 1)
  emptyText = content:CreateFontString(nil, "OVERLAY")
  emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  emptyText:SetTextColor(0.8, 0.8, 0.8, 1)
  driver = CreateFrame("Frame")   -- hors de la liste : anime aussi les favoris quand elle est fermee

  -- Favoris : enfant d'UIParent (ancre et echelle de la minimap) -- en enfant de la minimap, une partie des
  -- icones ne recevait pas la souris. Suit l'affichage de la minimap.
  favFrame = CreateFrame("Frame", "AishCoreAddonFavorites", UIParent)
  favFrame:SetFrameStrata("MEDIUM")
  favFrame:SetFrameLevel(100)
  favFrame:Hide()
  -- Bouton et favoris suivent l'affichage de la minimap
  Minimap:HookScript("OnShow", function() AC.ApplySettings() end)
  Minimap:HookScript("OnHide", function()
    favFrame:Hide()
    mainBtn:Hide()
    AC.Close()
  end)

  -- Clic ailleurs : referme la liste (sauf si le menu d'un addon est ouvert)
  local closer = CreateFrame("Frame")
  pcall(closer.RegisterEvent, closer, "GLOBAL_MOUSE_DOWN")
  closer:SetScript("OnEvent", function()
    if not isOpen or preview then return end
    if mainBtn:IsMouseOver() or popup:IsMouseOver() or AC.MenuOpen() then return end
    AC.Close()
  end)

  AC.ApplySettings()
end

function AC.ApplySettings()
  if not mainBtn then return end
  local cfg = Cfg()
  if cfg.enabled ~= true then
    preview = false
    AC.Close()
    mainBtn:Hide()
    favFrame:Hide()
    AC.ReleaseAll()
    return
  end
  StyleMain(cfg)
  mainBtn:SetShown(Minimap:IsVisible())
  AC.Scan()
  AC.Layout()
  if isOpen and popup:IsShown() then Kick() end
end

-- Liste ouverte tant que la page de reglages est affichee
function AC.SetPreview(on)
  if not mainBtn then return end
  if on and Cfg().enabled == true then
    -- Deja ouverte en apercu : simple remise en page (la cascade ne se rejoue pas a chaque reglage)
    if preview and isOpen and popup:IsShown() then
      AC.Layout()
      Kick()
      return
    end
    preview = false
    AC.Open()
    preview = true
  else
    preview = false
    AC.Close()
  end
end

function AC.GetHoverFrame()
  return mainBtn
end

function AC.GetFavoritesFrame()
  return favFrame
end

-- Couleurs thematiques : repeindre quand le module Couleurs change
do
  local CL = ns.Modules.Colors
  if CL and CL.RegisterCallback then
    CL.RegisterCallback(function()
      if mainBtn and mainBtn:IsShown() then StyleMain(Cfg()); AC.Layout() end
    end)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    -- Addon charge a la demande : son bouton apparait apres coup
    if mainBtn and arg1 ~= addonName and Cfg().enabled == true then
      addonTitles = nil
      C_Timer.After(1, AC.Scan)
    end
    return
  end
  AC.Create()
  AC.ApplySettings()
  -- Les addons creent leurs boutons a des moments differents : quelques passes apres le chargement
  C_Timer.After(1, AC.Scan)
  C_Timer.After(4, AC.Scan)
  -- Nouveaux boutons LibDBIcon
  local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
  if LDBI and LDBI.RegisterCallback and not AC._ldbiHooked then
    AC._ldbiHooked = true
    LDBI.RegisterCallback(AC, "LibDBIcon_IconCreated", function() C_Timer.After(0, AC.Scan) end)
  end
end)

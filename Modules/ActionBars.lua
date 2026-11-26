-- Modules/ActionBars.lua : "Barres d'action" -- remplace les barres d'action Blizzard (8 barres, familier, postures).
-- Principe (cf. docs/ACTION_BARS.md) : on ne cree PAS de boutons. Les boutons de Blizzard (ActionButton1-12,
-- MultiBar*Button, PetActionButton, StanceButton) sont repris dans nos propres barres securisees. Ils ont ete crees
-- par le jeu, hors de tout addon : leur code (recharges "secretes" de Midnight, procs, portee, raccourcis, Quick
-- Keybind, glisser-deposer) reste celui de Blizzard, sans taint. Nous ne faisons que :
--   - les reparenter / placer / dimensionner (hors combat, rattrape au PLAYER_REGEN_ENABLED) ;
--   - les habiller (textures, polices, masques : rien de protege) ;
--   - piloter la page de la barre 1 et la visibilite par des state drivers (environnement securise) ;
--   - gerer l'opacite (fondu, survol) : SetAlpha n'est pas protege.
-- Ecritures sur les boutons Blizzard : uniquement via snippets securises (Execute / _onstate) ou SetAttributeNoHandler,
-- jamais de champ Lua ni de methode reassignee (hooksecurefunc seulement).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local AB = {}
ns.Modules.ActionBars = AB

local L = ns.L
local MEDIA_UI = "Interface\\AddOns\\AishCore\\Media\\UI\\"
local MEDIA = "Interface\\AddOns\\AishCore\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_FONT = ns.FONT_FALLBACK

-- Barres : prefixe des boutons Blizzard, cadres Blizzard a masquer, page d'action (barres fixes), commande de raccourci
AB.BARS = {
  { key = "bar1", prefix = "ActionButton", count = 12, paged = true, bind = "ACTIONBUTTON",
    blizz = { "MainActionBar", "MainMenuBar" } },
  { key = "bar2", prefix = "MultiBarBottomLeftButton", count = 12, page = 6, bind = "MULTIACTIONBAR1BUTTON",
    blizz = { "MultiBarBottomLeft" } },
  { key = "bar3", prefix = "MultiBarBottomRightButton", count = 12, page = 5, bind = "MULTIACTIONBAR2BUTTON",
    blizz = { "MultiBarBottomRight" } },
  { key = "bar4", prefix = "MultiBarRightButton", count = 12, page = 3, bind = "MULTIACTIONBAR3BUTTON",
    blizz = { "MultiBarRight" } },
  { key = "bar5", prefix = "MultiBarLeftButton", count = 12, page = 4, bind = "MULTIACTIONBAR4BUTTON",
    blizz = { "MultiBarLeft" } },
  { key = "bar6", prefix = "MultiBar5Button", count = 12, page = 13, bind = "MULTIACTIONBAR5BUTTON",
    blizz = { "MultiBar5" } },
  { key = "bar7", prefix = "MultiBar6Button", count = 12, page = 14, bind = "MULTIACTIONBAR6BUTTON",
    blizz = { "MultiBar6" } },
  { key = "bar8", prefix = "MultiBar7Button", count = 12, page = 15, bind = "MULTIACTIONBAR7BUTTON",
    blizz = { "MultiBar7" } },
  { key = "pet", prefix = "PetActionButton", count = 10, kind = "pet", bind = "BONUSACTIONBUTTON",
    blizz = { "PetActionBar", "PetActionBarFrame" } },
  { key = "stance", prefix = "StanceButton", count = 10, kind = "stance", bind = "SHAPESHIFTBUTTON",
    blizz = { "StanceBar", "StanceBarFrame" } },
}
-- Barre de totems du chaman (MultiCastActionBarFrame, Forever) : le cadre Blizzard est repris entier (pages de totems,
-- menu de choix et liens securises restent les siens). Seuls l'invocation, les 4 emplacements et le rappel sont places
-- en grille ; les boutons de totem (MultiCastActionButton1-12) suivent leur emplacement (ancrage de Blizzard).
local TOTEM = _G.MultiCastActionBarFrame
if TOTEM and select(2, UnitClass("player")) == "SHAMAN" then
  AB.BARS[#AB.BARS + 1] = { key = "totem", kind = "totem", count = 6, blizz = {} }
else
  TOTEM = nil
end
local BAR_BY = {}
for _, d in ipairs(AB.BARS) do BAR_BY[d.key] = d end
AB.BAR_BY = BAR_BY

-- Formes des boutons : masque applique a l'icone (et au contour, au survol, au clic)
AB.SHAPES = {
  { value = "square" },
  { value = "circle",  file = "Interface\\CharacterFrame\\TempPortraitAlphaMask" },
  { value = "diamond", file = MEDIA_UI .. "Diamond.tga" },
  { value = "grunge",  file = MEDIA_UI .. "IconGrungeMask.png" },
  { value = "feather", file = MEDIA_UI .. "IconFeatherMask.png" },
}
local SHAPE_BY = {}
for _, s in ipairs(AB.SHAPES) do SHAPE_BY[s.value] = s end

-- Fonds de barre : memes textures que le Compartiment d'addons (decoupe en 9 des Barres dynamiques ou image etiree)
AB.BG_TEXTURES = {
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
local BG_BY = {}
for _, d in ipairs(AB.BG_TEXTURES) do BG_BY[d.value] = d end

AB.VIS_MODES = { "always", "combat", "nocombat", "never", "custom" }

-- Etat -----------------------------------------------------------------------------------------------------------
local hidden = CreateFrame("Frame", "AishCoreActionBarsHidden", UIParent)
hidden:Hide()
local frames, buttons = {}, {}                           -- key -> barre securisee ; key -> { boutons Blizzard }
local owner = setmetatable({}, { __mode = "k" })         -- bouton -> cle de barre
local skins = setmetatable({}, { __mode = "k" })         -- bouton -> habillage (textures, parties)
local adopted, pendingAdopt, pendingLayout = false, false, false
local placing = 0                                        -- > 0 : nos propres SetPoint / SetParent (hooks ignores)
local state = { hover = {}, alpha = {}, lastOver = {}, ruleShown = {}, drag = false, guiForce = false }

local function IsSecret(v) return ns.IsSecret and ns.IsSecret(v) end
local function Round(v) return math.floor(v + 0.5) end

-- Reglages ---------------------------------------------------------------------------------------------------------
local function Cfg() return ns.GetCfg("actionBars") or {} end
local function DefCfg() return (ns.Defaults and ns.Defaults.actionBars) or {} end
function AB.DB()
  ns.DB.actionBars = ns.DB.actionBars or {}
  return ns.DB.actionBars
end
function AB.BarDB(key)
  local db = AB.DB()
  db.bars = db.bars or {}
  db.bars[key] = db.bars[key] or {}
  return db.bars[key]
end
-- Reglage commun (racine de actionBars)
function AB.GV(prop)
  local v = Cfg()[prop]
  if v == nil then v = DefCfg()[prop] end
  return v
end
-- Groupes de barres : les barres d'un meme groupe partagent leurs reglages (groups[id].settings), sauf la
-- position et la disposition, propres a chaque barre
local LOCAL_PROPS = { enabled = true, group = true, x = true, y = true, count = true, perRow = true, growH = true,
                      growV = true, width = true, height = true, spacingX = true, spacingY = true, flyoutDir = true }
AB.LOCAL_PROPS = LOCAL_PROPS
local function GroupOf(key)
  local c = Cfg()
  local b = c.bars and c.bars[key]
  local id = b and b.group
  local g = id and c.groups and c.groups[id]
  if g then return g, id end
end
AB.GroupOf = GroupOf

-- Reglage d'une barre : groupe ou DB, defaut de la barre, puis defaut commun a toutes les barres
function AB.BV(key, prop)
  local c = Cfg()
  local b = c.bars and c.bars[key]
  local v
  local g = not LOCAL_PROPS[prop] and GroupOf(key)
  if g then v = g.settings and g.settings[prop] else v = b and b[prop] end
  if v == nil then
    local d = DefCfg().bars and DefCfg().bars[key]
    v = d and d[prop]
  end
  if v == nil and ns.ActionBarCommon then v = ns.ActionBarCommon[prop] end
  return v
end
local BV, GV = AB.BV, AB.GV

-- Ecriture d'un reglage : dans le groupe de la barre (reglage partage) ou dans la barre
function AB.SetBV(key, prop, v)
  local g = not LOCAL_PROPS[prop] and GroupOf(key)
  if g then
    g.settings = g.settings or {}
    g.settings[prop] = v
  else
    AB.BarDB(key)[prop] = v
  end
end

local function Copy(v) return type(v) == "table" and CopyTable(v) or v end
-- Reglages partageables d'une barre (valeurs effectives)
local function SharedSettings(key)
  local t = {}
  for prop in pairs(ns.ActionBarCommon or {}) do
    if not LOCAL_PROPS[prop] then t[prop] = Copy(BV(key, prop)) end
  end
  return t
end

function AB.Groups()
  local db = AB.DB()
  db.groups = db.groups or {}
  return db.groups
end
-- Nouveau groupe, reglages repris de la barre `key`, qui y entre
function AB.NewGroup(key, name)
  local groups = AB.Groups()
  local n = 1
  while groups["g" .. n] do n = n + 1 end
  local id = "g" .. n
  groups[id] = { name = name, settings = SharedSettings(key) }
  AB.BarDB(key).group = id
  return id
end
-- Entree dans un groupe (la barre en prend les reglages) ; nil = sortie, la barre garde une copie des reglages
function AB.SetGroup(key, id)
  local bar = AB.BarDB(key)
  if bar.group == id then return end
  if bar.group and GroupOf(key) then
    for prop, v in pairs(SharedSettings(key)) do bar[prop] = v end
  end
  bar.group = (id and AB.Groups()[id]) and id or nil
end
function AB.DeleteGroup(id)
  for _, def in ipairs(AB.BARS) do
    if AB.BarDB(def.key).group == id then AB.SetGroup(def.key, nil) end
  end
  AB.Groups()[id] = nil
end
function AB.GroupName(id)
  local g = id and AB.Groups()[id]
  return g and g.name
end

function AB.IsEnabled() return GV("enabled") == true end
function AB.IsAdopted() return adopted end
function AB.GetFrame(key) return frames[key] end

-- Couleur thematique (module Couleurs, "cercle de puissance") ou couleur propre
local function ThemedOr(key, flag, prop, element)
  if BV(key, flag) then
    local CL = ns.Modules.Colors
    local c = CL and CL.Get and CL.Get(element or "powercircle")
    if c and c[1] then return c[1], c[2], c[3], (BV(key, prop) or {})[4] or 1 end
  end
  local c = BV(key, prop) or { 0, 0, 0, 1 }
  return c[1], c[2], c[3], c[4] or 1
end

-- Texte court d'un raccourci : "SHIFT-F" -> "SF", "BUTTON4" -> "M4"
function AB.ShortKey(key)
  if not key then return "" end
  key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("META%-", "M")
  key = key:gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD"):gsub("BUTTON", "M")
  key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Spc"):gsub("ESCAPE", "Esc"):gsub("BACKSPACE", "Bs")
  key = key:gsub("CAPSLOCK", "Caps"):gsub("DELETE", "Del"):gsub("INSERT", "Ins"):gsub("PAGEUP", "PU")
  key = key:gsub("PAGEDOWN", "PD"):gsub("HOME", "Hm"):gsub("END", "End"):gsub("ENTER", "Ent"):gsub("TAB", "Tab")
  return key
end

local function IconTexCoord(w, h, zoom)
  local l, r, t, b = 0, 1, 0, 1
  if zoom ~= false then l, r, t, b = 0.08, 0.92, 0.08, 0.92 end
  if w > h then
    local cut = ((b - t) - (b - t) * h / w) / 2
    t, b = t + cut, b - cut
  elseif h > w then
    local cut = ((r - l) - (r - l) * w / h) / 2
    l, r = l + cut, r - cut
  end
  return l, r, t, b
end

-- Grille : taille de la barre et position de chaque bouton (i = 1..n), selon le sens de croissance
function AB.Grid(key, n)
  local w, h = BV(key, "width") or 36, BV(key, "height") or 36
  local sx, sy = BV(key, "spacingX") or 2, BV(key, "spacingY") or 2
  local per = math.max(1, math.min(n, BV(key, "perRow") or 12))
  local cols, rows = per, math.ceil(n / per)
  local W, H = cols * w + (cols - 1) * sx, rows * h + (rows - 1) * sy
  local right, down = BV(key, "growH") ~= "LEFT", BV(key, "growV") ~= "UP"
  local pt = (down and "TOP" or "BOTTOM") .. (right and "LEFT" or "RIGHT")
  local pos = {}
  for i = 1, n do
    local c, r = (i - 1) % per, math.floor((i - 1) / per)
    pos[i] = { (right and 1 or -1) * c * (w + sx), (down and -1 or 1) * r * (h + sy) }
  end
  return W, H, pt, pos, w, h
end

-- Barre de totems : invocation, emplacements actifs, rappel (ceux que Blizzard affiche)
local function TotemList()
  local list = {}
  if not TOTEM then return list end
  local n = tonumber(TOTEM.numActiveSlots) or 0
  if IsSecret(n) then n = 4 end
  local function Add(b) if b and b:IsShown() then list[#list + 1] = b end end
  Add(_G.MultiCastSummonSpellButton)
  for i = 1, math.max(0, math.min(4, n)) do Add(_G["MultiCastSlotButton" .. i]) end
  Add(_G.MultiCastRecallSpellButton)
  return list
end
AB.TotemList = TotemList

-- Nombre de boutons affiches (posture : nombre de formes connues, au moins 1 pour garder une taille)
function AB.Count(key)
  local def = BAR_BY[key]
  if def.kind == "totem" then return math.max(1, #TotemList()) end
  local n = math.max(1, math.min(def.count, BV(key, "count") or def.count))
  if def.kind == "stance" and GetNumShapeshiftForms then
    local f = GetNumShapeshiftForms() or 0
    if not IsSecret(f) and f > 0 then n = math.min(n, f) end
  end
  return n
end

-- Variation des textures (option "Varier les textures") : chaque bouton prend une des 8 orientations de la texture
-- (rotations de 90 deg et symetries), pour casser la repetition des formes grunge. Coins UL, LL, UR, LR.
local ORIENT = {
  { 0, 0, 0, 1, 1, 0, 1, 1 },   -- telle quelle
  { 0, 1, 1, 1, 0, 0, 1, 0 },   -- 90 deg
  { 1, 0, 1, 1, 0, 0, 0, 1 },   -- symetrie horizontale
  { 1, 1, 1, 0, 0, 1, 0, 0 },   -- 180 deg
  { 0, 1, 0, 0, 1, 1, 1, 0 },   -- symetrie verticale
  { 1, 0, 0, 0, 1, 1, 0, 1 },   -- 270 deg
  { 0, 0, 1, 0, 0, 1, 1, 1 },   -- transposee
  { 1, 1, 0, 1, 1, 0, 0, 0 },   -- antitransposee
}
-- Boutons : rotations seulement (SetRotation), le masque de l'icone ne suivant pas les coordonnees a 8 valeurs
-- (icone effacee) ; symetries reservees au fond de la barre. Sans SetRotation sur les masques : pas de variation.
local ROT = { { rot = 0 }, { rot = math.pi / 2 }, { rot = math.pi }, { rot = math.pi * 1.5 } }
local maskRotOK
local function Orient(key, i)
  if not (i and BV(key, "texVariation")) then return ORIENT[1] end
  if maskRotOK == nil then
    local m = UIParent:CreateMaskTexture()
    maskRotOK = type(m.SetRotation) == "function"
  end
  if not maskRotOK then return ORIENT[1] end
  return ROT[(i - 1) % #ROT + 1]
end
AB.Orient = Orient
local function SetOrient(t, o)
  if not t then return end
  if o.rot then
    pcall(t.SetTexCoord, t, 0, 1, 0, 1)
    if t.SetRotation then pcall(t.SetRotation, t, o.rot) end
  else
    if t.SetRotation then pcall(t.SetRotation, t, 0) end
    pcall(t.SetTexCoord, t, o[1], o[2], o[3], o[4], o[5], o[6], o[7], o[8])
  end
end

-- Habillage d'un bouton (reel ou apercu) -----------------------------------------------------------------------------
local function Parts(b)
  local name = b:GetName()
  local function G(suffix) return name and _G[name .. suffix] end
  return {
    icon = b.icon or b.Icon or G("Icon"),
    hotkey = b.HotKey or G("HotKey"),
    count = b.Count or G("Count"),
    name = b.Name or G("Name"),
    cooldown = b.cooldown or b.Cooldown or G("Cooldown"),
    hideArt = { b.GetNormalTexture and b:GetNormalTexture(), G("NormalTexture2"), G("FloatingBG"), b.SlotArt,
                b.SlotBackground, b.RightDivider, b.BottomDivider },
    iconMask = b.IconMask,
    -- Autocast du familier : cadre AutoCastOverlay (Retail), texture AutoCastable + etincelles AutoCastShine (Forever)
    autoOverlay = b.AutoCastOverlay,
    autoCastable = b.AutoCastable or G("AutoCastable"),
    autoShine = b.AutoCastShine or G("Shine") or G("AutoCastShine"),
    flash = b.Flash or G("Flash"),   -- clignotement rouge (attaque automatique, familier qui attaque)
    -- Calques de taille fixe (atlas prevus pour un bouton Blizzard) : bordure verte d'objet equipe, nouveau sort,
    -- sort mis en evidence, cadenas
    border = b.Border or G("Border"),
    overlays = { b.NewActionTexture, b.SpellHighlightTexture, b.QuickKeybindHighlightTexture },
    lockIcon = b.LevelLinkLockIcon,
    -- Effets (Retail) : cadres de 128 px dont les textures ont la taille de l'atlas, prevus pour un bouton de 45 px
    fxFrames = { b.SpellCastAnimFrame, b.InterruptDisplay, b.TargetReticleAnimFrame },
    cdFlash = b.CooldownFlash,
  }
end

-- Calques et effets de Blizzard recales sur l'icone (sinon a la taille d'un bouton Blizzard, ancres au coin)
local FX_BASE = 45
local function FitOverlays(b, P, ref, iw, ih)
  local bd = P.border
  if bd and bd.ClearAllPoints then
    bd:ClearAllPoints()
    if ns.IsForever then
      -- Forever : UI-ActionButton-Border, 62 px (halo compris) pour 36 px de bouton
      bd:SetPoint("CENTER", ref, "CENTER", 0, 0)
      bd:SetSize(iw * 62 / 36, ih * 62 / 36)
    else
      bd:SetAllPoints(ref)
    end
  end
  for _, t in pairs(P.overlays) do
    if t and t.ClearAllPoints then t:ClearAllPoints(); t:SetAllPoints(ref) end
  end
  if P.lockIcon and P.lockIcon.ClearAllPoints then
    P.lockIcon:ClearAllPoints()
    P.lockIcon:SetPoint("CENTER", ref, "CENTER", 0, 0)
  end
  -- Cadres enfants d'un bouton protege : hors combat seulement (rattrape a la mise en page suivante)
  if InCombatLockdown() then return end
  local sc = math.max(0.1, math.min(iw, ih) / FX_BASE)
  for _, f in pairs(P.fxFrames) do
    if f and f.SetScale then
      f:SetScale(sc)
      f:ClearAllPoints()
      f:SetPoint("CENTER", ref, "CENTER", 0, 0)
      if f ~= b.InterruptDisplay then f:SetSize(128, 128) else f:SetSize(FX_BASE, FX_BASE) end
    end
  end
  local cf = P.cdFlash
  if cf and cf.ClearAllPoints then
    cf:ClearAllPoints()
    cf:SetAllPoints(ref)
  end
end

-- Autocast : tailles d'origine prevues pour un bouton Blizzard de 30 px, recalees sur l'icone du bouton.
-- Cadres enfants d'un bouton protege : ancrage hors combat seulement (rattrape a la mise en page suivante).
local function FitAutoCast(P, ref, iw, ih)
  if InCombatLockdown() then return end
  local ov = P.autoOverlay
  if ov then
    ov:ClearAllPoints()
    ov:SetAllPoints(ref)
    local out = math.max(1, math.floor(math.min(iw, ih) * 0.06 + 0.5))
    for _, k in ipairs({ "Shine", "Corners", "Mask" }) do
      local t = ov[k]
      if t and t.ClearAllPoints then
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", ov, "TOPLEFT", -out, out)
        t:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT", out, -out)
      end
    end
  end
  -- Forever : bordure 58 px pour 30 px de bouton, etincelles 28 px
  if P.autoCastable then
    P.autoCastable:ClearAllPoints()
    P.autoCastable:SetPoint("CENTER", ref, "CENTER", 0, 0)
    P.autoCastable:SetSize(iw * 58 / 30, ih * 58 / 30)
  end
  if P.autoShine then
    P.autoShine:ClearAllPoints()
    P.autoShine:SetPoint("CENTER", ref, "CENTER", 0, 0)
    P.autoShine:SetSize(iw * 28 / 30, ih * 28 / 30)
  end
end

local function Skin(b)
  local s = skins[b]
  if s then return s end
  s = { p = Parts(b) }
  -- Contour : texture pleine (ou forme du masque) sous l'icone, l'icone etant inset de l'epaisseur du contour
  s.bord = b:CreateTexture(nil, "BACKGROUND", nil, -7)
  s.mask = b:CreateMaskTexture()
  -- Textes au-dessus du balayage de recharge
  s.textFrame = CreateFrame("Frame", nil, b)
  s.textFrame:SetAllPoints(b)
  local cd = s.p.cooldown
  s.textFrame:SetFrameLevel(math.max(b:GetFrameLevel(), cd and cd:GetFrameLevel() or 0) + 3)
  for _, k in ipairs({ "hotkey", "count", "name" }) do
    local fs = s.p[k]
    if fs and fs.SetParent then fs:SetParent(s.textFrame) end
  end
  -- Glow des procs : au-dessus de l'icone et de la recharge, sous les textes
  s.glow = CreateFrame("Frame", nil, b)
  s.glow:SetFrameLevel(s.textFrame:GetFrameLevel() - 1)
  skins[b] = s
  return s
end
AB.Skin = Skin

local ANCHOR_JUSTIFY = { LEFT = "LEFT", RIGHT = "RIGHT" }
local function StyleText(s, fs, ringKey, get, pre, w, key)
  if not fs then return end
  local style = get(pre .. "Outline") or "OUTLINE"
  local ring = s[ringKey]
  if style == "SLUG" and not ring then
    ring = ns.CreateSlugRing(s.textFrame, fs, "ARTWORK")   -- sous le texte (OVERLAY), sinon le noir le recouvre
    s[ringKey] = ring
  end
  ns.ApplyTextOutlineStyle(fs, ring, get(pre .. "Font") or DEFAULT_FONT, get(pre .. "Size") or 12, style, true)
  -- Texte de l'anneau apres sa police (SetText sans police : "Font not set")
  if ring and not ring._texted then ring._texted = true; ns.SetSlugRingText(ring, fs:GetText()) end
  if fs.SetVertexColor then fs:SetVertexColor(1, 1, 1, 1) end   -- teinte de Blizzard (portee) neutralisee
  fs:SetTextColor(ThemedOr(key, pre .. "Themed", pre .. "Color", "powertext"))
  local pt = get(pre .. "Anchor") or "CENTER"
  fs:ClearAllPoints()
  fs:SetPoint(pt, s.textFrame, pt, get(pre .. "X") or 0, get(pre .. "Y") or 0)
  fs:SetWidth(math.max(8, w))
  fs:SetJustifyH(ANCHOR_JUSTIFY[pt:match("LEFT") or pt:match("RIGHT") or ""] or "CENTER")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  -- Ancrage / justification changes : le texte n'est remis en page qu'au prochain SetText (sinon il fallait
  -- toucher a la taille pour voir le nouvel ancrage)
  local txt = fs:GetText()
  if txt and not IsSecret(txt) then fs:SetText(""); fs:SetText(txt) end
  local on = get(pre .. "Show") ~= false
  fs:SetAlpha(on and 1 or 0)
  if ring then for _, r in ipairs(ring) do r:SetAlpha(on and 1 or 0) end end
end

-- Peint un etat (survol, clic, coche) : forme du bouton, couleur unie, sur la zone de l'icone
local function Paint(t, file, icon, c, o)
  if not t then return end
  t:SetTexture(file or WHITE)
  SetOrient(t, o or ORIENT[1])
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  t:ClearAllPoints()
  t:SetAllPoints(icon)
end

-- Glow des procs : celui de Blizzard (taille fixee a sa creation, carre) est masque ; le notre (ns.ShowGlow) suit
-- l'icone. glowStyle : "auto" (style Blizzard du client), "none", ou nom d'une entree de ns.GLOW_DEFS.
local function GlowIdx(key)
  local style = BV(key, "glowStyle") or "auto"
  if style == "none" then return nil end
  if style == "auto" then style = ns.IsForever and "Classic Glow" or "Proc Gold" end
  for i, d in ipairs(ns.Auras and ns.Auras.GLOW_DEFS or {}) do
    if d.name == style then return i end
  end
end

-- Alerte de Blizzard masquee tant que le proc dure ; alpha rendu a la fin (le cadre est recycle par un pool)
local function BlizzAlert(b, s)
  local a = b.SpellActivationAlert or b.overlay
  if s.glowOn and a and a.SetAlpha then
    a:SetAlpha(0)
    s.alert = a
  elseif s.alert then
    s.alert:SetAlpha(1)
    s.alert = nil
  end
end

-- Animation d'entree (entrees "Proc: ..." de GLOW_DEFS), jouee a l'apparition d'un proc
local function ProcStartIdx(key)
  local style = BV(key, "procStart") or "auto"
  if style == "none" then return nil end
  if style == "auto" then style = ns.IsForever and "Proc: Classic-like" or "Proc: Blizzard" end
  for i, d in ipairs(ns.Auras and ns.Auras.GLOW_DEFS or {}) do
    if d.name == style and d.isProcStart then return i end
  end
end
local function GlowColor(key)
  local r, g, b, a = ThemedOr(key, "glowThemed", "glowColor", "glow")
  return { r, g, b, a }
end

local function PlayProcStart(b, key)
  local s = skins[b]
  local A = ns.Auras or {}
  local idx = s and s.glow and ProcStartIdx(key)
  if idx and A.PlayProcStart then
    pcall(A.PlayProcStart, s.glow, idx, GlowColor(key), 1)
  end
end
AB.PlayProcStart = PlayProcStart

local function UpdateGlow(b, key)
  local s = skins[b]
  if not (s and s.glow and key) then return end
  BlizzAlert(b, s)
  local A = ns.Auras or {}
  -- Aide a la rotation (surbrillance propre a chaque bouton, jamais recyclee) : remplacee par notre glow
  local hl = b.AssistedCombatHighlightFrame
  if hl and A.ShowGlow then hl:SetAlpha(0) end
  local idx = (s.glowOn or s.assistOn) and GlowIdx(key)
  if idx and A.ShowGlow then
    s.hideTok = nil
    local c = GlowColor(key)
    A.ShowGlow(s.glow, idx, c, c[4] or 1, 1, s.iw or 36, s.ih or 36)
  elseif A.HideGlow and s.glow._glowActiveIdx and not s.hideTok then
    -- Extinction differee : Blizzard eteint / rallume l'alerte en rafale (mises a jour des boutons) ; un rallumage
    -- dans l'intervalle garde l'animation en cours au lieu de la relancer (clignotement)
    local tok = {}
    s.hideTok = tok
    C_Timer.After(0.2, function()
      if s.hideTok ~= tok then return end
      s.hideTok = nil
      if not ((s.glowOn or s.assistOn) and GlowIdx(owner[b] or key)) then A.HideGlow(s.glow) end
    end)
  end
end
AB.UpdateGlow = UpdateGlow

-- `get(prop)` : reglage de la barre ; `key` sert aux couleurs thematiques
function AB.StyleButton(b, key, w, h)
  local s = Skin(b)
  local P = s.p
  local get = function(prop) return BV(key, prop) end
  for _, t in pairs(P.hideArt) do if t and t.SetAlpha then t:SetAlpha(0) end end
  local icon = P.icon
  if P.iconMask and icon and not s.noBlizzMask then
    pcall(icon.RemoveMaskTexture, icon, P.iconMask)
    s.noBlizzMask = true
  end
  local shape = SHAPE_BY[get("shape")] or SHAPE_BY.square
  local o = Orient(key, s.idx)
  local bs = math.max(0, get("borderSize") or 0)
  local br, bg, bb, ba = ThemedOr(key, "borderThemed", "borderColor")
  s.bord:SetTexture(shape.file or WHITE)
  SetOrient(s.bord, o)
  s.bord:ClearAllPoints()
  s.bord:SetAllPoints(b)
  s.bord:SetVertexColor(br, bg, bb, ba)
  s.bord:SetShown(bs > 0 and not s.noBord)
  if icon then
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", bs, -bs)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -bs, bs)
    if not s.keepCoord then
      icon:SetTexCoord(IconTexCoord(w - 2 * bs, h - 2 * bs, get("iconZoom") ~= false or shape.file ~= nil))
    end
    if shape.file then
      s.mask:SetTexture(shape.file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      SetOrient(s.mask, o)
      s.mask:ClearAllPoints()
      s.mask:SetAllPoints(icon)
      if not s.masked then icon:AddMaskTexture(s.mask); s.masked = true end
    elseif s.masked then
      icon:RemoveMaskTexture(s.mask)
      s.masked = false
    end
  end
  local cd = P.cooldown
  if cd then
    -- Cadre enfant d'un bouton protege : ancrage hors combat seulement (rattrape a la mise en page suivante)
    if not InCombatLockdown() then
      cd:ClearAllPoints()
      if icon then cd:SetAllPoints(icon) else cd:SetAllPoints(b) end
    end
    if cd.SetSwipeTexture then cd:SetSwipeTexture(shape.file or WHITE) end
    cd:SetSwipeColor(0, 0, 0, get("swipeAlpha") or 0.8)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(get("cdNumbers") == false) end
    local cdText = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if cdText then
      local outline = get("cdOutline") == "THICKOUTLINE" and "THICKOUTLINE" or "OUTLINE"
      pcall(cdText.SetFont, cdText, get("cdFont") or DEFAULT_FONT, get("cdSize") or 14, outline)
      cdText:SetTextColor(ThemedOr(key, "cdThemed", "cdColor", "powertext"))
    end
  end
  local ref = icon or b
  Paint(b.GetHighlightTexture and b:GetHighlightTexture(), shape.file, ref, get("hoverColor") or { 1, 1, 1, 0.25 }, o)
  Paint(b.GetPushedTexture and b:GetPushedTexture(), shape.file, ref, get("pushedColor") or { 1, 0.82, 0, 0.35 }, o)
  if b.GetCheckedTexture then Paint(b:GetCheckedTexture(), shape.file, ref, get("checkedColor") or { 1, 1, 1, 0.35 }, o) end
  StyleText(s, P.hotkey, "hkRing", get, "hk", w, key)
  StyleText(s, P.count, "ctRing", get, "ct", w, key)
  StyleText(s, P.name, "nmRing", get, "nm", w, key)
  s.glow:ClearAllPoints()
  s.glow:SetAllPoints(icon or b)
  s.iw, s.ih = math.max(1, w - 2 * bs), math.max(1, h - 2 * bs)
  if P.autoOverlay or P.autoCastable or P.autoShine then FitAutoCast(P, icon or b, s.iw, s.ih) end
  FitOverlays(b, P, icon or b, s.iw, s.ih)
  local fl = P.flash
  if fl and fl.SetAllPoints then
    fl:ClearAllPoints()
    fl:SetAllPoints(icon or b)
    if shape.file and not s.flashMasked then fl:AddMaskTexture(s.mask); s.flashMasked = true
    elseif not shape.file and s.flashMasked then fl:RemoveMaskTexture(s.mask); s.flashMasked = false end
  end
  if s.glowOn or s.assistOn then UpdateGlow(b, key) end
end

-- Raccourci : texte court (Blizzard le reecrit a chaque UPDATE_BINDINGS, d'ou le hook)
local function HotkeyText(b)
  local s, key = skins[b], owner[b]
  local hk = s and s.p.hotkey
  if not (hk and key) then return end
  if BV(key, "hkShow") == false then hk:SetAlpha(0); return end
  hk:SetAlpha(1)
  local cmd = s.cmd
  if cmd == nil and key == "totem" and type(b.buttonType) == "string" then
    -- Totems : commande de Blizzard (MULTICASTACTIONBUTTONn ; invocation / rappel : 1re liaison)
    cmd = b.buttonType .. (tonumber(b.buttonIndex) or 1)
  end
  local k = cmd and GetBindingKey(cmd)
  if k then
    if BV(key, "hkShort") ~= false then hk:SetText(AB.ShortKey(k)) end
  else
    -- Sans raccourci, Blizzard ecrit le temoin de portee (RANGE_INDICATOR, "●"), absent des polices choisies
    -- (affiche comme un "1") : efface
    local t = hk:GetText()
    if t and not IsSecret(t) and t == RANGE_INDICATOR then hk:SetText("") end
  end
end

-- Hors de portee : icone teintee (option commune). L'ancienne couleur d'utilisabilite est recalculee au retour.
local IsUsableAction = (C_ActionBar and C_ActionBar.IsUsableAction) or IsUsableAction
local function ApplyTint(b)
  local s = skins[b]
  local icon = s and s.p.icon
  if not icon then return end
  local want = s.oor and GV("rangeTint") ~= false
  if want then
    local c = GV("rangeColor") or { 0.9, 0.2, 0.2, 1 }
    if GV("rangeThemed") then   -- couleurs thematiques (option commune)
      local CL = ns.Modules.Colors
      local t = CL and CL.Get and CL.Get("powercircle")
      if t and t[1] then c = t end
    end
    icon:SetVertexColor(c[1], c[2], c[3])
  elseif s.tinted then
    local r, g, bl = 1, 1, 1
    local action = b.action
    if action and IsUsableAction then
      local ok, usable, oom = pcall(IsUsableAction, action)
      if ok and not IsSecret(usable) and not IsSecret(oom) then
        if oom then r, g, bl = 0.5, 0.5, 1 elseif not usable then r, g, bl = 0.4, 0.4, 0.4 end
      end
    end
    icon:SetVertexColor(r, g, bl)
  end
  s.tinted = want
end
local function OnRange(b, checksRange, inRange)
  local s = skins[b]
  if not (s and owner[b]) then return end
  -- Blizzard teinte le raccourci (blanc / rouge) selon la portee : couleur de la barre reappliquee
  local hk = s.p.hotkey
  if hk then
    hk:SetVertexColor(1, 1, 1, 1)
    hk:SetTextColor(ThemedOr(owner[b], "hkThemed", "hkColor", "powertext"))
  end
  if IsSecret(checksRange) or IsSecret(inRange) then return end
  s.oor = (checksRange and inRange == false) and true or false
  ApplyTint(b)
end

-- Mise en page --------------------------------------------------------------------------------------------------------
local LayoutAll   -- forward
-- `light` : boutons seulement replaces (Blizzard les deplace / masque), sans habillage ; une demande complete l'emporte
local pendingFull = false
local function QueueLayout(light)
  local P = AB._prof
  if P and P.on then P.src = "file d'attente <- " .. (debugstack(2, 3, 0) or "?") end
  if not light then pendingFull = true end
  if pendingLayout then return end
  pendingLayout = true
  C_Timer.After(0, function()
    if InCombatLockdown() then pendingFull = true; return end   -- rattrape au PLAYER_REGEN_ENABLED
    pendingLayout = false
    local full = pendingFull
    pendingFull = false
    LayoutAll(not full)
  end)
end
-- Blizzard replace / reparente / redimensionne ses boutons (Edit Mode, nombre d'icones...) : on reprend la main.
-- Remise en place seulement : UpdateShownButtons est rappele a chaque mise a jour d'action (habillage complet = saccade)
local function OnBlizzMove()
  if placing > 0 or not adopted then return end
  QueueLayout(true)
end

local function SlotTextures(f, n)
  f.__slots = f.__slots or {}
  for i = #f.__slots + 1, n do
    f.__slots[i] = f:CreateTexture(nil, "BACKGROUND", nil, -6)
  end
  return f.__slots
end

-- Cases vides (fond de chaque emplacement) : option "Afficher les emplacements vides", toujours pendant un glisser
local function StyleSlots(f, key, n, pos, pt, w, h, force)
  f.__slotArgs = { key, n, pos, pt, w, h }
  local slots = SlotTextures(f, 12)
  local shape = SHAPE_BY[BV(key, "shape")] or SHAPE_BY.square
  local c = BV(key, "slotColor") or { 0, 0, 0, 0.5 }
  local on = force or BV(key, "showEmpty") == true
  for i, t in ipairs(slots) do
    if on and i <= n then
      t:SetTexture(shape.file or WHITE)
      SetOrient(t, Orient(key, i))
      t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
      t:ClearAllPoints()
      t:SetPoint(pt, f, pt, pos[i][1], pos[i][2])
      t:SetSize(w, h)
      t:Show()
    else
      t:Hide()
    end
  end
end

-- Glisser un sort : emplacements montres / caches sans rien de protege (textures seulement), meme en combat
local function RefreshSlots()
  for _, f in pairs(frames) do
    local a = f.__slotArgs
    if a then StyleSlots(f, a[1], a[2], a[3], a[4], a[5], a[6], state.drag or state.guiForce or GV("locked") == false) end
  end
end
AB.StyleSlots = StyleSlots

-- Couleur du fond : l'opacite vient du curseur (pas de l'alpha de la couleur, 0.6 par defaut)
local function BgColor(key)
  local c = BV(key, "bgColor") or { 0, 0, 0 }
  return { c[1] or 0, c[2] or 0, c[3] or 0, BV(key, "bgAlpha") or 0.6 }
end

-- Fond de la barre (memes textures que le Compartiment d'addons)
function AB.StyleBackground(holder, key, w, h)
  local tex = BV(key, "bgTexture") or "none"
  local d = BG_BY[tex] or BG_BY.none
  local EB = ns.Modules.ExtraBars
  local px, py = BV(key, "bgPadX") or 6, BV(key, "bgPadY") or 6
  -- Variation : orientation tiree du rang de la barre (decoupe en 9 : symetries seulement)
  local bo = 1
  if BV(key, "texVariation") then
    for i, def in ipairs(AB.BARS) do if def.key == key then bo = (i * 3 - 1) % #ORIENT + 1 end end
  end
  if EB and EB.StyleBackground then
    EB.StyleBackground(holder, {
      bgEnabled = d.nine == true, bgTexture = tex, bgColor = BgColor(key), bgPadX = px, bgPadY = py,
      bgFlipH = bo == 3 or bo == 4, bgFlipV = bo == 4 or bo == 5,
      bgEdge = BV(key, "bgEdge"), bgBorderSize = BV(key, "bgBorderSize"), bgBorderColor = BV(key, "bgBorderColor"),
    }, w, h, d.nine == true)
    if holder.__bg then
      holder.__bg:SetFrameLevel(math.max(0, holder:GetFrameLevel() - 1))
      holder.__bg:SetAlpha(1)
    end
  end
  local t = holder.__abTex
  if not d.file then
    if t then t:Hide() end
    return
  end
  if not t then
    t = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
    holder.__abTex = t
  end
  local c = BgColor(key)
  t:SetTexture(d.file)
  SetOrient(t, ORIENT[bo])
  t:SetVertexColor(c[1], c[2], c[3], c[4])
  t:SetAlpha(1)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", holder, "TOPLEFT", -px, py)
  t:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", px, -py)
  t:Show()
end

-- Visibilite securisee : conditions de macro (state driver "visibility")
local function ValidCond(cond)
  if not SecureCmdOptionParse then return true end
  local ok = pcall(SecureCmdOptionParse, cond)
  return ok
end
AB.ValidCond = ValidCond
-- Regles cumulables (memes cases que les Barres de vie, plus En combat et Si blesse) : l'une suffit a montrer la barre.
-- Les "Cacher" passent avant, sauf en combat ; le survol (case "Au survol") passe avant tout. Evaluees en Lua :
-- hors combat, le pilote d'etat masque vraiment la barre ; en combat (pilote fige), seule l'opacite suit.
local function B(v) if IsSecret(v) then return true end return v end

-- Modes : "normal" (montree en combat, grimoire ouvert, blesse, vol dynamique, avec une cible, au survol ; sinon
-- opacite "cachee"), "discreet" (au survol seulement), "advanced" (regles cumulables ci-dessous)
local function VisMode(key) return BV(key, "visMode") or "normal" end
AB.VisMode = VisMode
local function SpellbookOpen()
  local P = _G.PlayerSpellsFrame
  local f = (P and P.SpellBookFrame) or _G.SpellBookFrame
  return f and f:IsVisible() and true or false
end
-- Blesse : meme notion que le cercle de vie (vie qui a bouge recemment), la vie du joueur pouvant etre secrete
local function Injured()
  local HC = ns.Modules and ns.Modules.HealthCircle
  return HC and HC.IsPlayerInjured and HC.IsPlayerInjured() or false
end
local function Skyriding()
  if ns.skyridingActive then return true end
  local GI = C_PlayerInfo and C_PlayerInfo.GetGlidingInfo
  if not GI then return false end
  local ok, _, canGlide = pcall(GI)
  return ok and not IsSecret(canGlide) and canGlide == true
end
-- Survol actif pour la barre (toujours en Normal / Discret ; case "Au survol" en Avance)
local function HoverRule(key)
  if VisMode(key) ~= "advanced" then return true end
  return BV(key, "visHover") and BV(key, "visAlways") == false
end

local function RuleShow(key, combat)
  local mode = VisMode(key)
  if mode == "discreet" then return false end
  if mode == "normal" then
    return (combat or SpellbookOpen() or Injured() or Skyriding() or UnitExists("target")) and true or false
  end
  if not combat then
    if BV(key, "hideMounted") and IsMounted() then return false end
    if BV(key, "hideResting") and ns.IsRestArea and ns.IsRestArea() then return false end
  end
  if BV(key, "visAlways") ~= false then return true end
  if BV(key, "visCombat") and combat then return true end
  if BV(key, "visAttackable") or BV(key, "visFriendly") then
    if UnitExists("target") and not B(UnitIsDeadOrGhost("target")) then
      local harm = B(UnitCanAttack("player", "target"))
      if BV(key, "visAttackable") and harm then return true end
      if BV(key, "visFriendly") and not harm and B(UnitIsFriend("player", "target")) then return true end
    end
  end
  if BV(key, "visGroup") and IsInGroup() then return true end
  if BV(key, "visInstance") and (ns.inInstance or IsInInstance()) then return true end
  if BV(key, "visInjured") and Injured() then return true end
  return false
end
AB.RuleShow = RuleShow
-- Regles qui peuvent changer en plein combat : la barre reste montree (pilote) pour que l'opacite puisse suivre
local function DynamicRules(key)
  return BV(key, "visAlways") == false and (BV(key, "visHover") or BV(key, "visCombat") or BV(key, "visFriendly")
    or BV(key, "visAttackable") or BV(key, "visInjured"))
end

local function ForceShown()
  return state.guiForce or GV("locked") == false
end

-- Barre montree par le pilote d'etat (le reste passe par l'opacite)
local function DriverShow(key, combat)
  if VisMode(key) ~= "advanced" then return true end   -- Normal / Discret : opacite seulement
  local show = ForceShown() or (BV(key, "visHover") and true) or RuleShow(key, combat)
  if combat and DynamicRules(key) then show = true end
  return show and true or false
end

-- `combat` : pilote pose a l'entree en combat (PLAYER_REGEN_DISABLED, juste avant le verrouillage)
function AB.VisCondition(key, combat)
  local def = BAR_BY[key]
  local parts = { "[petbattle] hide;" }
  local adv = VisMode(key) == "advanced"
  if not adv or BV(key, "hideVehicle") ~= false then parts[#parts + 1] = "[vehicleui][overridebar] hide;" end
  if adv and BV(key, "hideSkyriding") then parts[#parts + 1] = "[bonusbar:5] hide;" end
  if def.kind == "pet" then parts[#parts + 1] = "[nopet] hide;" end
  local show = DriverShow(key, combat)
  parts[#parts + 1] = show and "show" or "hide"
  state.ruleShown[key] = show
  return table.concat(parts, " ")
end

local function ApplyVisibility(key, combat)
  local f = frames[key]
  if not f or InCombatLockdown() then pendingLayout = true; return end
  UnregisterStateDriver(f, "visibility")
  local def = BAR_BY[key]
  if not AB.IsEnabled() or BV(key, "enabled") == false then
    f:Hide()
    return
  end
  if ForceShown() then
    f:Show()
    state.ruleShown[key] = true
    return
  end
  local cond = AB.VisCondition(key, combat)
  if def.kind == "stance" then
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    if IsSecret(n) or n == 0 then cond = "hide" end
  end
  if def.kind == "totem" and not (TOTEM:IsShown() and #TotemList() > 0) then cond = "hide" end
  RegisterStateDriver(f, "visibility", cond)
end

local function LayoutBar(key, light)
  local f, list = frames[key], buttons[key]
  if not (f and list) then return end
  if InCombatLockdown() then pendingLayout = true; return end
  local def = BAR_BY[key]
  if def.kind == "totem" then return AB.LayoutTotem(key, f, light) end
  local n = AB.Count(key)
  local W, H, pt, pos, w, h = AB.Grid(key, n)
  placing = placing + 1
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", BV(key, "x") or 0, BV(key, "y") or 0)
  f:SetSize(W, H)
  for i, b in pairs(list) do
    if i <= n then
      b:SetParent(f)
      b:SetScale(1)
      b:SetSize(w, h)
      b:ClearAllPoints()
      b:SetPoint(pt, f, pt, pos[i][1], pos[i][2])
      if not def.kind then
        -- Bouton masque par Blizzard (nombre d'icones de l'Edit Mode) : rendu a la barre
        if b:GetAttribute("statehidden") then b:SetAttributeNoHandler("statehidden", nil) end
        local action = b.action
        if action and not IsSecret(action) and HasAction(action) then b:Show() end
        AB.ApplyFlyoutDir(b, key)
      end
    else
      b:SetParent(hidden)
    end
  end
  placing = placing - 1
  if light then return end
  for i, b in pairs(list) do
    if i <= n then AB.StyleButton(b, key, w, h); HotkeyText(b) end
  end
  StyleSlots(f, key, n, pos, pt, w, h, state.drag or ForceShown())
  AB.StyleBackground(f, key, W, H)
  ApplyVisibility(key)
end

-- Barre de totems : le cadre Blizzard passe dans notre barre (opacite, visibilite) ; jamais de SetAlpha / Show / Hide
-- sur lui (cf. Comfort.lua : ses boutons seraient marques et leurs recharges secretes leveraient des erreurs)
function AB.LayoutTotem(key, f, light)
  local list = TotemList()
  local n = math.max(1, #list)
  local W, H, pt, pos, w, h = AB.Grid(key, n)
  placing = placing + 1
  if TOTEM:GetParent() ~= f then TOTEM:SetParent(f) end
  f:ClearAllPoints()
  f:SetPoint("CENTER", UIParent, "CENTER", BV(key, "x") or 0, BV(key, "y") or 0)
  f:SetSize(W, H)
  TOTEM:ClearAllPoints()
  TOTEM:SetAllPoints(f)
  for i, b in ipairs(list) do
    b:SetSize(w, h)
    b:ClearAllPoints()
    b:SetPoint(pt, f, pt, pos[i][1], pos[i][2])
  end
  -- Totems des 3 pages : poses sur leur emplacement (Blizzard les place par rapport a sa barre d'origine)
  for j = 1, 12 do
    local a, slot = _G["MultiCastActionButton" .. j], _G["MultiCastSlotButton" .. ((j - 1) % 4 + 1)]
    if a and slot then
      a:ClearAllPoints()
      a:SetAllPoints(slot)
    end
  end
  placing = placing - 1
  if light then return end
  for _, b in pairs(buttons[key]) do AB.StyleButton(b, key, w, h); HotkeyText(b) end
  StyleSlots(f, key, #list, pos, pt, w, h, state.drag or ForceShown())
  AB.StyleBackground(f, key, W, H)
  ApplyVisibility(key)
end

function AB.OwnsTotemBar() return adopted and frames.totem ~= nil end

LayoutAll = function(light)
  if not adopted then return end
  if InCombatLockdown() then pendingLayout = true; return end
  pendingLayout = false
  for _, def in ipairs(AB.BARS) do LayoutBar(def.key, light) end
  if AB.UpdateMovers then AB.UpdateMovers() end
end

-- Pagination de la barre 1 (formes, furtivite, vol dynamique, possession, barres 1-6 de Blizzard)
local function Idx(fn, alt, def)
  local f = _G[fn] or (C_ActionBar and C_ActionBar[fn])
  local ok, v = pcall(f or function() return def end)
  if not ok or type(v) ~= "number" then v = def end
  return v or alt
end
function AB.PagingConditions()
  local O = Idx("GetOverrideBarIndex", 14, 14)
  local V = Idx("GetVehicleBarIndex", 12, 12)
  local T = Idx("GetTempShapeshiftBarIndex", 13, 13)
  -- Druide : en Rôder, la forme de félin garde bonusbar:1 (Retail comme Forever) ; la page 8 est la page Rôder
  -- (comme ElvUI). Un client qui passerait en bonusbar:2 tombe de toute facon sur la page 8.
  local prowl = (select(2, UnitClass("player")) == "DRUID") and "[bonusbar:1,stealth] 8; " or ""
  return ("[overridebar] %d; [vehicleui][possessbar] %d; [shapeshift] %d; [bonusbar:5] 11; %s[bonusbar:1] 7; "
    .. "[bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1")
    :format(O, V, T, prowl)
end

-- Barres securisees ------------------------------------------------------------------------------------------------
local function CreateBar(def, list)
  local f = CreateFrame("Frame", "AishCoreActionBar_" .. def.key, UIParent, "SecureHandlerStateTemplate")
  f:SetSize(1, 1)
  f:SetPoint("CENTER")
  f:SetClampedToScreen(true)
  f:SetFrameStrata("MEDIUM")
  if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
  for i, b in pairs(list) do f:SetFrameRef("b" .. i, b) end
  f:Execute([[
    btns = newtable()
    for i = 1, 12 do
      local b = self:GetFrameRef("b" .. i)
      if b then btns[i] = b end
    end
  ]])
  if def.page then
    -- Page fixe, posee dans l'environnement securise (boutons et barre : useparent-actionpage)
    f:Execute(([[
      self:SetAttribute("actionpage", %d)
      for _, b in pairs(btns) do b:SetAttribute("actionpage", %d) end
    ]]):format(def.page, def.page))
  elseif def.paged then
    -- Changement de page : attribut pose sur chaque bouton (son OnAttributeChanged relit l'action, en securise)
    f:SetAttribute("_onstate-page", [[
      local page = tonumber(newstate) or 1
      self:SetAttribute("actionpage", page)
      for _, b in pairs(btns) do b:SetAttribute("actionpage", page) end
    ]])
    RegisterStateDriver(f, "page", AB.PagingConditions())
    -- La page change une frame apres UPDATE_BONUS_ACTIONBAR (state driver) : l'index des raccourcis (barre de rotation,
    -- bouton de rotation), reconstruit entre-temps sur l'ancienne page, est invalide une fois les actions relues
    f:HookScript("OnAttributeChanged", function(_, name)
      if name ~= "state-page" then return end
      if ns.InvalidateKeybindCache then ns.InvalidateKeybindCache() end
      if ns.CallbackRegistry then ns.CallbackRegistry:Trigger("ActionBars.PageChanged") end
    end)
  end
  return f
end

local function HookButton(b, def, i)
  hooksecurefunc(b, "SetPoint", OnBlizzMove)
  hooksecurefunc(b, "SetParent", OnBlizzMove)
  hooksecurefunc(b, "SetScale", OnBlizzMove)
  local function Restyle(self)
    local key = owner[self]
    if not key then return end
    local w, h = BV(key, "width") or 36, BV(key, "height") or 36
    AB.StyleButton(self, key, w, h)
    HotkeyText(self)
  end
  if b.UpdateButtonArt then hooksecurefunc(b, "UpdateButtonArt", Restyle) end
  if b.UpdateHotkeys then hooksecurefunc(b, "UpdateHotkeys", HotkeyText) end
  if b.SetHotkeys then hooksecurefunc(b, "SetHotkeys", HotkeyText) end
  if b.UpdateRangeIndicator then hooksecurefunc(b, "UpdateRangeIndicator", OnRange) end
  if b.UpdateUsable then hooksecurefunc(b, "UpdateUsable", function(self) if skins[self] and skins[self].oor then ApplyTint(self) end end) end
  local s = Skin(b)
  s.idx = i
  s.cmd = def.bind and (def.bind .. i) or nil
end

-- Barres Blizzard : masquees sans toucher a leurs evenements (elles tiennent a jour pet / postures)
local blizzHidden = {}
local function HideBlizzard()
  for _, def in ipairs(AB.BARS) do
    for _, name in ipairs(def.blizz) do
      local bar = _G[name]
      if bar and not blizzHidden[bar] then
        blizzHidden[bar] = true
        if name == "MainActionBar" then
          -- Gardee "affichee" (transitions vehicule / barre de remplacement de Blizzard), invisible et inerte
          bar:SetAlpha(0)
          bar:EnableMouse(false)
          hooksecurefunc(bar, "Show", function(self) self:SetAlpha(0) end)
          local pager = bar.ActionBarPageNumber
          if pager then
            pager:Hide()
            for _, k in ipairs({ "UpButton", "DownButton" }) do if pager[k] then pager[k]:EnableMouse(false) end end
          end
          if bar.EndCaps then bar.EndCaps:Hide() end
          if bar.BorderArt then bar.BorderArt:Hide() end
        else
          bar:SetParent(hidden)
          hooksecurefunc(bar, "SetParent", function(self, p)
            if p ~= hidden and not InCombatLockdown() then self:SetParent(hidden) end
          end)
        end
        -- Re-disposition par Blizzard (Edit Mode, nombre d'icones) : nos boutons sont repris aussitot
        for _, m in ipairs({ "UpdateGridLayout", "UpdateShownButtons", "UpdateVisibility" }) do
          if type(bar[m]) == "function" then hooksecurefunc(bar, m, OnBlizzMove) end
        end
      end
    end
  end
end

-- Premiere reprise : positions, nombre d'icones et taille releves sur les barres Blizzard (meme ecran qu'avant)
local function Capture()
  local db = AB.DB()
  local uiW, uiH = UIParent:GetSize()
  local us = UIParent:GetEffectiveScale()
  for _, def in ipairs(AB.BARS) do
    local bc = AB.BarDB(def.key)
    local bar
    for _, name in ipairs(def.blizz) do bar = bar or _G[name] end
    if bar then
      pcall(function()
        local b1 = _G[def.prefix .. "1"]
        if b1 then
          local bw = b1:GetWidth() * b1:GetEffectiveScale() / us
          local bh = b1:GetHeight() * b1:GetEffectiveScale() / us
          if bw > 10 and bh > 10 then bc.width, bc.height = Round(bw), Round(bh) end
        end
        if not def.kind then
          bc.enabled = bar:IsShown() and true or false
          local n = bar.numButtonsShowable
          if type(n) == "number" and n > 0 then bc.count = n end
          local rows = bar.numRows
          if type(rows) == "number" and rows > 0 then
            local cnt = bc.count or def.count
            if bar.isHorizontal == false then
              bc.perRow = rows
            else
              bc.perRow = math.ceil(cnt / rows)
            end
          end
          local pad = bar.buttonPadding
          if type(pad) == "number" then bc.spacingX, bc.spacingY = Round(pad), Round(pad) end
        end
        local cx, cy = bar:GetCenter()
        local s = bar:GetEffectiveScale()
        if cx and cy and bar:IsShown() and not IsSecret(cx) then
          bc.x = Round(cx * s / us - uiW / 2)
          bc.y = Round(cy * s / us - uiH / 2)
        end
      end)
    end
  end
  db._captured = true
end

-- Barre de totems : boutons habilles (invocation, emplacements, rappel, totems des 3 pages). Les emplacements n'ont
-- pas d'icone propre : leur fond (element vide) en tient lieu. Le contour des totems est celui de leur emplacement.
-- Menu de choix des totems (MultiCastFlyoutFrame, Lua non securise de Blizzard) : ouvert au survol du triangle,
-- boutons qui montent un a un depuis l'emplacement (fondu + glissement, animations seulement : rien de deplace)
local FLY_HOLD, FLY_STEP, FLY_DUR, FLY_RISE = 0.0, 0.03, 0.16, 10
-- Sens des tiroirs (reglage flyoutDir de la barre) : vecteur d'ouverture et points d'ancrage (bouton, precedent)
AB.FLY_DIRS = {
  UP = { 0, 1, "BOTTOM", "TOP" }, DOWN = { 0, -1, "TOP", "BOTTOM" },
  LEFT = { -1, 0, "RIGHT", "LEFT" }, RIGHT = { 1, 0, "LEFT", "RIGHT" },
}
function AB.FlyoutDir(key)
  local d = BV(key, "flyoutDir")
  return AB.FLY_DIRS[d] and d or "UP"
end
-- Sorts a tiroir (pistage, auras...) : attribut lu par le SpellFlyout securise et par la fleche du bouton.
-- Hors combat seulement (LayoutBar).
function AB.ApplyFlyoutDir(b, key)
  local d = AB.FlyoutDir(key)
  if b:GetAttribute("flyoutDirection") == d then return end
  if not b.GetPopupDirection then
    b.GetPopupDirection = function(self) return self:GetAttribute("flyoutDirection") or "UP" end
  end
  b:SetAttribute("flyoutDirection", d)
  if b.UpdateFlyout then pcall(b.UpdateFlyout, b) end
end
local flyAnims = setmetatable({}, { __mode = "k" })
local function FlyAnim(b)
  local ag = flyAnims[b]
  if ag then return ag end
  ag = b:CreateAnimationGroup()
  local hide = ag:CreateAnimation("Alpha")
  hide:SetOrder(1); hide:SetFromAlpha(0); hide:SetToAlpha(0)
  local down = ag:CreateAnimation("Translation")
  down:SetOrder(1)
  local fade = ag:CreateAnimation("Alpha")
  fade:SetOrder(2); fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(FLY_DUR); fade:SetSmoothing("OUT")
  local up = ag:CreateAnimation("Translation")
  up:SetOrder(2); up:SetDuration(FLY_DUR); up:SetSmoothing("OUT")
  ag.hold = { hide, down }
  ag.back, ag.fwd = down, up
  flyAnims[b] = ag
  return ag
end
-- Menu des totems tourne vers le sens choisi : boutons enchaines depuis l'emplacement, bouton de fermeture au bout
local function OrientTotemFlyout(frame)
  local parent = frame and frame.parent
  if not (parent and type(frame.buttons) == "table") then return end
  local d = AB.FLY_DIRS[AB.FlyoutDir("totem")]
  local up = d[2] == 1   -- vers le haut : disposition de Blizzard
  if frame.top then frame.top:SetAlpha(up and 1 or 0) end
  if frame.middle then frame.middle:SetAlpha(up and 1 or 0) end
  if up then return end
  local vert, prev, len = d[1] == 0, parent, 0
  for _, b in ipairs(frame.buttons) do
    if b:IsShown() then
      b:ClearAllPoints()
      b:SetPoint(d[3], prev, d[4], d[1] * 2, d[2] * 2)
      len = len + (vert and b:GetHeight() or b:GetWidth()) + 2
      prev = b
    end
  end
  local close = _G.MultiCastFlyoutFrameCloseButton
  if close then
    close:ClearAllPoints()
    close:SetPoint(d[3], prev, d[4])
    len = len + (vert and close:GetHeight() or close:GetWidth())
  end
  frame:ClearAllPoints()
  frame:SetPoint(d[3], parent, d[4])
  if vert then frame:SetSize(parent:GetWidth(), len) else frame:SetSize(len, parent:GetHeight()) end
end
-- Triangle d'ouverture : du cote du sens choisi
local function OrientTotemOpenButton(btn, _, parent)
  parent = parent or (btn and btn.parent)
  if not parent then return end
  local dir = AB.FlyoutDir("totem")
  local d = AB.FLY_DIRS[dir]
  local rot = ({ DOWN = math.pi, LEFT = math.pi / 2, RIGHT = -math.pi / 2 })[dir] or 0
  for _, t in ipairs({ btn:GetNormalTexture(), btn:GetHighlightTexture(), btn:GetPushedTexture() }) do
    if t and t.SetRotation then t:SetRotation(rot) end
  end
  if d[2] == 1 then return end
  btn:ClearAllPoints()
  btn:SetPoint(d[3], parent, d[4])
end
local function AnimateFlyout(frame)
  if not (frame and frame:IsShown() and type(frame.buttons) == "table") then return end
  OrientTotemFlyout(frame)
  local d = AB.FLY_DIRS[AB.FlyoutDir("totem")]
  local n = 0
  for _, b in ipairs(frame.buttons) do
    if b:IsShown() then
      local ag = FlyAnim(b)
      ag:Stop()
      ag.back:SetOffset(-FLY_RISE * d[1], -FLY_RISE * d[2])
      ag.fwd:SetOffset(FLY_RISE * d[1], FLY_RISE * d[2])
      local d = math.max(0.001, FLY_HOLD + n * FLY_STEP)
      for _, a in ipairs(ag.hold) do a:SetDuration(d) end
      ag:Play()
      n = n + 1
    end
  end
end
-- Fermeture : souris hors du menu, de son emplacement et du triangle pendant FLY_CLOSE s, boutons qui redescendent
local FLY_CLOSE, FLY_OUT = 1.5, 0.12
local flyOut = setmetatable({}, { __mode = "k" })
local function CloseFlyout(fly)
  local last
  for _, b in ipairs(fly.buttons or {}) do
    if b:IsShown() then
      local ag = flyOut[b]
      if not ag then
        ag = b:CreateAnimationGroup()
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1); a:SetToAlpha(0); a:SetDuration(FLY_OUT); a:SetSmoothing("IN")
        local t = ag:CreateAnimation("Translation")
        t:SetDuration(FLY_OUT); t:SetSmoothing("IN")
        ag.t = t
        flyOut[b] = ag
      end
      local d = AB.FLY_DIRS[AB.FlyoutDir("totem")]
      ag.t:SetOffset(-FLY_RISE * d[1], -FLY_RISE * d[2])
      if flyAnims[b] then flyAnims[b]:Stop() end
      ag:SetScript("OnFinished", nil)
      ag:Play()
      last = ag
    end
  end
  local function Done()
    if not fly:IsShown() then return end
    if type(_G.MultiCastFlyoutFrame_Hide) == "function" then _G.MultiCastFlyoutFrame_Hide(fly, true) else fly:Hide() end
    for b, ag in pairs(flyOut) do ag:Stop() end
  end
  if last then last:SetScript("OnFinished", Done) else Done() end
end
local function HookTotemFlyout()
  local fly, open = _G.MultiCastFlyoutFrame, _G.MultiCastFlyoutFrameOpenButton
  if fly then
    local away, closing = 0, false
    local watch = CreateFrame("Frame")
    watch:SetScript("OnUpdate", function(_, el)
      if not fly:IsShown() then away, closing = 0, false; return end
      if closing then return end
      local p = fly.parent
      if fly:IsMouseOver() or (p and p:IsMouseOver()) or (open and open:IsShown() and open:IsMouseOver()) then
        away = 0
        return
      end
      away = away + el
      if away >= FLY_CLOSE then
        closing = true
        CloseFlyout(fly)
      end
    end)
  end
  if type(_G.MultiCastFlyoutFrame_ToggleFlyout) == "function" then
    hooksecurefunc("MultiCastFlyoutFrame_ToggleFlyout", function(frame) AnimateFlyout(frame) end)
  end
  if type(_G.MultiCastFlyoutFrameOpenButton_Show) == "function" then
    hooksecurefunc("MultiCastFlyoutFrameOpenButton_Show", OrientTotemOpenButton)
  end
  if fly and open then
    open:HookScript("OnEnter", function(self)
      if fly:IsShown() and fly.parent == self.parent then return end
      if self.type and self.parent and _G.MultiCastFlyoutFrame_ToggleFlyout then
        _G.MultiCastFlyoutFrame_ToggleFlyout(fly, self.type, self.parent)
      end
    end)
  end
end

function AB.AdoptTotem(def)
  local list = {}
  local function Add(b, i, layout, kind)
    if not b then return end
    list[#list + 1] = b
    owner[b] = def.key
    if layout then
      hooksecurefunc(b, "SetPoint", OnBlizzMove)
      hooksecurefunc(b, "SetSize", OnBlizzMove)
    end
    if b.UpdateHotkeys then hooksecurefunc(b, "UpdateHotkeys", HotkeyText) end
    local s = Skin(b)
    s.idx = i
    if kind == "slot" then
      s.p.icon = s.p.icon or b.background
      s.keepCoord = true   -- fond pris dans une planche de textures : coordonnees de Blizzard
      s.p.hideArt[#s.p.hideArt + 1] = b.overlayTex
    elseif kind == "action" then
      s.noBord = true
      s.p.hideArt[#s.p.hideArt + 1] = b.overlayTex
    end
  end
  Add(_G.MultiCastSummonSpellButton, 1, true)
  for i = 1, 4 do Add(_G["MultiCastSlotButton" .. i], i + 1, true, "slot") end
  Add(_G.MultiCastRecallSpellButton, 6, true)
  for i = 1, 12 do Add(_G["MultiCastActionButton" .. i], (i - 1) % 4 + 2, true, "action") end
  if not list[1] then return end
  hooksecurefunc(TOTEM, "SetPoint", OnBlizzMove)
  HookTotemFlyout()
  -- Blizzard affiche / masque la barre (totems appris, entree dans le monde) : visibilite et grille revues
  hooksecurefunc(TOTEM, "Show", function() if adopted then QueueLayout() end end)
  hooksecurefunc(TOTEM, "Hide", function() if adopted then QueueLayout() end end)
  frames[def.key] = CreateBar(def, {})
  buttons[def.key] = list
end

function AB.Adopt()
  if adopted then return true end
  if InCombatLockdown() then pendingAdopt = true; return false end
  pendingAdopt = false
  if not AB.DB()._captured then Capture() end
  HideBlizzard()
  for _, def in ipairs(AB.BARS) do
    local list = {}
    if def.kind == "totem" then
      AB.AdoptTotem(def)
    else
      for i = 1, def.count do
        local b = _G[def.prefix .. i]
        if b then list[i] = b end
      end
    end
    if list[1] then
      for i, b in pairs(list) do
        owner[b] = def.key
        HookButton(b, def, i)
      end
      frames[def.key] = CreateBar(def, list)
      buttons[def.key] = list
    end
  end
  adopted = true
  -- Procs : Retail (ActionButtonSpellAlertManager) ou anciens clients (ActionButton_Show/HideOverlayGlow)
  local function SetGlow(b, on)
    local s = b and owner[b] and skins[b]
    if not s then return end
    local was = s.glowOn
    local lit = s.glow and s.glow._glowActiveIdx   -- glow encore affiche (extinction differee en cours)
    s.glowOn = on
    UpdateGlow(b, owner[b])
    if on and not was and not lit then PlayProcStart(b, owner[b]) end
  end
  local M = _G.ActionButtonSpellAlertManager
  if type(M) == "table" then
    if type(M.ShowAlert) == "function" then hooksecurefunc(M, "ShowAlert", function(_, b) SetGlow(b, true) end) end
    if type(M.HideAlert) == "function" then hooksecurefunc(M, "HideAlert", function(_, b) SetGlow(b, false) end) end
  end
  if type(_G.ActionButton_ShowOverlayGlow) == "function" then
    hooksecurefunc("ActionButton_ShowOverlayGlow", function(b) SetGlow(b, true) end)
  end
  if type(_G.ActionButton_HideOverlayGlow) == "function" then
    hooksecurefunc("ActionButton_HideOverlayGlow", function(b) SetGlow(b, false) end)
  end
  -- Aide a la rotation (AssistedCombatManager, Retail)
  local AC = _G.AssistedCombatManager
  if type(AC) == "table" and type(AC.SetAssistedHighlightFrameShown) == "function" then
    hooksecurefunc(AC, "SetAssistedHighlightFrameShown", function(_, b, shown)
      local s = b and owner[b] and skins[b]
      if not s then return end
      s.assistOn = shown and true or false
      UpdateGlow(b, owner[b])
    end)
  end
  for b in pairs(owner) do
    local hl = b.AssistedCombatHighlightFrame
    if hl and hl:IsShown() and skins[b] then skins[b].assistOn = true; UpdateGlow(b, owner[b]) end
  end
  -- Proc deja actif a la reprise
  for b in pairs(owner) do
    local a = b.SpellActivationAlert or b.overlay
    if a and a.IsShown and a:IsShown() then SetGlow(b, true) end
  end
  -- Portee (fonction globale de Blizzard sur les anciens clients)
  if type(_G.ActionButton_UpdateRangeIndicator) == "function" then
    hooksecurefunc("ActionButton_UpdateRangeIndicator", OnRange)
  end
  LayoutAll()
  AB.StartFader()
  return true
end

-- Survol / fondu ---------------------------------------------------------------------------------------------------
local function Over(f, pad)
  if not (f and f:IsVisible()) then return false end
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local l, b, w, h = f:GetRect()
  if not l or IsSecret(l) or IsSecret(b) or IsSecret(w) or IsSecret(h) or IsSecret(cx) or IsSecret(scale) then return false end
  cx, cy = cx / scale, cy / scale
  return cx >= l - pad and cx <= l + w + pad and cy >= b - pad and cy <= b + h + pad
end


local function TotemFlyoutOpen()
  local fl = _G.MultiCastFlyoutFrame
  return fl and fl:IsVisible() and true or false
end

local function FlyoutOwnerKey()
  local fl = _G.SpellFlyout
  if fl and fl:IsShown() then
    local p = fl:GetParent()
    return p and owner[p]
  end
end

-- Opacite visee : "Opacite" si une regle montre la barre ou au survol, sinon "Opacite hors survol" (barres
-- "Au survol") ou 0
function AB.TargetAlpha(key, hovered, shown)
  if ForceShown() or state.drag then return 1 end
  local a = BV(key, "alpha") or 1
  if shown or hovered then return a end
  if VisMode(key) ~= "advanced" then return BV(key, "mouseoverAlpha") or 0 end   -- opacite "cachee"
  if BV(key, "visHover") then return math.min(a, BV(key, "mouseoverAlpha") or 0) end
  return 0
end

local fader = CreateFrame("Frame")
local acc = 0
local groupHover = {}   -- id de groupe -> une de ses barres est survolee
local function FaderTick(_, el)
  acc = acc + el
  local now = GetTime()
  if acc >= 0.05 then
    acc = 0
    state.drag = GetCursorInfo() ~= nil
    local pad, delay = GV("hoverPad") or 4, GV("hoverDelay") or 0.3
    local flyKey = FlyoutOwnerKey()
    local combat = InCombatLockdown() or UnitAffectingCombat("player")
    wipe(groupHover)
    for key, f in pairs(frames) do
      local need = HoverRule(key)
      local over = need and (Over(f, pad) or flyKey == key or (key == "totem" and TotemFlyoutOpen()))
      if over then state.lastOver[key] = now end
      local h = need and (now - (state.lastOver[key] or -100) <= delay)
      state.hover[key] = h
      if h then
        -- Survol d'une barre groupee : tout le groupe apparait
        local _, gid = GroupOf(key)
        if gid then groupHover[gid] = true end
      end
    end
    state.target = state.target or {}
    local free = not InCombatLockdown() and AB.IsEnabled()
    for key in pairs(frames) do
      local need = HoverRule(key)
      local _, gid = GroupOf(key)
      local h = state.hover[key] or (gid and groupHover[gid] and need)
      local shown = RuleShow(key, combat)
      state.target[key] = AB.TargetAlpha(key, h, shown)
      -- Hors combat : le pilote d'etat suit les regles (barre vraiment masquee, plus cliquable)
      if free and BV(key, "enabled") ~= false then
        if DriverShow(key, combat) ~= state.ruleShown[key] then ApplyVisibility(key, combat) end
      end
    end
    -- Glisser un sort : emplacements visibles le temps du glisser
    if state.drag ~= state.lastDrag then
      state.lastDrag = state.drag
      RefreshSlots()
    end
  end
  local ft = math.max(0.01, GV("fadeTime") or 0.25)
  local step = el / ft
  local test = AB._test   -- essais de /aishdebug abtest (floor : jamais sous 1/255 ; instant : sans fondu)
  if test and test.instant then step = 1 end
  for key, f in pairs(frames) do
    local tgt = state.target and state.target[key] or 1
    local cur = state.alpha[key] or tgt
    if cur ~= tgt then
      if math.abs(tgt - cur) <= step then cur = tgt elseif tgt > cur then cur = cur + step else cur = cur - step end
    end
    state.alpha[key] = cur
    local out = (test and test.floor and cur < 0.004) and 0.004 or cur
    if math.abs(f:GetAlpha() - out) > 0.0005 then f:SetAlpha(out) end
  end
end

function AB.StartFader()
  fader:SetScript("OnUpdate", adopted and FaderTick or nil)
end

-- Deplacement (barres deverrouillees) ------------------------------------------------------------------------------
local movers = {}
local function Label(key)
  local k = "ACTIONBARS_BAR_" .. key:upper()
  return (L and L[k]) or key
end
AB.Label = Label

local function SaveMoverPos(m)
  local key = m.key
  local cx, cy = m:GetCenter()
  local ux, uy = UIParent:GetCenter()
  if not (cx and ux) then return end
  local s = m:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local bc = AB.BarDB(key)
  bc.x, bc.y = Round(cx * s - ux), Round(cy * s - uy)
end

local function NewMover(key)
  local m = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  m.key = key
  m:SetFrameStrata("DIALOG")
  m:SetMovable(true)
  m:SetClampedToScreen(true)
  m:RegisterForDrag("LeftButton")
  m:RegisterForClicks("RightButtonUp")
  m:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  local r, g, b = ns.HitboxColor()
  m:SetBackdropColor(r, g, b, 0.18)
  m:SetBackdropBorderColor(r, g, b, 0.9)
  local fs = m:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.FONT_FALLBACK, 11, "OUTLINE")
  fs:SetPoint("CENTER")
  fs:SetTextColor(1, 1, 1, 1)
  fs:SetText(Label(key))
  m.text = fs
  if ns.Nudge then ns.Nudge.Attach(m) end   -- fleches = deplacement au pixel
  m:SetScript("OnDragStart", function(self)
    if InCombatLockdown() then return end
    self:StartMoving()
    self:SetScript("OnUpdate", function(s)
      if InCombatLockdown() then return end
      SaveMoverPos(s)
      local f = frames[s.key]
      if f then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", BV(s.key, "x") or 0, BV(s.key, "y") or 0)
      end
    end)
  end)
  m:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetScript("OnUpdate", nil)
    SaveMoverPos(self)
    LayoutBar(self.key)
    AB.UpdateMovers()
    if ns.ActionBarsPagePosChanged then ns.ActionBarsPagePosChanged(self.key) end
  end)
  m:SetScript("OnClick", function(self)
    ns._actionBarsSelected = self.key
    local panel = ns.SettingsPanel
    if panel and panel.GoToElement then
      panel:GoToElement("actionBars")
    elseif panel and panel.SelectCategory then
      if not panel:IsShown() and panel.ShowUI then panel:ShowUI() end
      panel:SelectCategory("actionBars")
    end
    if ns.ActionBarsPageRefresh then ns.ActionBarsPageRefresh() end
  end)
  m:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(Label(self.key), 1, 1, 1)
    GameTooltip:AddLine(L["ACTIONBARS_MOVER_TT"], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  m:SetScript("OnLeave", function() GameTooltip:Hide() end)
  movers[key] = m
  return m
end

function AB.UpdateMovers()
  local show = adopted and AB.IsEnabled() and GV("locked") == false
  for _, def in ipairs(AB.BARS) do
    local key = def.key
    local f = frames[key]
    local m = movers[key]
    if show and f and BV(key, "enabled") ~= false then
      m = m or NewMover(key)
      local W, H = AB.Grid(key, AB.Count(key))
      m:ClearAllPoints()
      m:SetPoint("CENTER", UIParent, "CENTER", BV(key, "x") or 0, BV(key, "y") or 0)
      m:SetSize(math.max(W, 24), math.max(H, 16))
      m:Show()
    elseif m then
      m:Hide()
    end
  end
end

function AB.SetLocked(locked)
  AB.DB().locked = locked and true or false
  if InCombatLockdown() then pendingLayout = true; return end
  LayoutAll()
end

-- Apercu du GUI : barres reelles visibles (opacite pleine) tant que la page est ouverte
function AB.SetGuiForce(on)
  on = on and true or false
  if state.guiForce == on then return end
  state.guiForce = on
  if adopted and not InCombatLockdown() then LayoutAll() else pendingLayout = true end
end

-- Mode raccourcis de Blizzard (Quick Keybind) : fonctionne tel quel, les boutons sont ceux de Blizzard
function AB.OpenQuickKeybind()
  if InCombatLockdown() then return end
  local qk = _G.QuickKeybindFrame
  if qk then
    if ns.SettingsPanel and ns.SettingsPanel.Hide then ns.SettingsPanel:Hide() end
    qk:Show()
  end
end

-- /kb : mode raccourcis (comme ElvUI / Bartender), meme module desactive
SLASH_AISHCOREKB1 = "/kb"
SlashCmdList["AISHCOREKB"] = function()
  if InCombatLockdown() then print("|cff00ccffAishCore|r " .. L["ACTIONBARS_KB_COMBAT"]); return end
  if not _G.QuickKeybindFrame then print("|cff00ccffAishCore|r " .. L["ACTIONBARS_KB_UNAVAILABLE"]); return end
  AB.OpenQuickKeybind()
end

-- Apercu du GUI (UI/ActionBarsPage.lua) ----------------------------------------------------------------------------
-- Boutons factices (non securises), habilles par AB.StyleButton comme les vrais : meme rendu.
local FALLBACK_ICONS = { 135808, 136048, 132369, 135753, 136197, 135812, 136075, 132316, 135846, 136116, 132090, 134400 }

-- Icone reelle d'un emplacement (hors combat), sinon icone d'exemple
local function SampleIcon(key, i)
  local def = BAR_BY[key]
  local tex
  if def.kind == "pet" and GetPetActionInfo then
    local ok, _, t, isToken = pcall(GetPetActionInfo, i)
    if ok and t and not IsSecret(t) then tex = isToken and _G[t] or t end
  elseif def.kind == "stance" and GetShapeshiftFormInfo then
    local ok, t = pcall(GetShapeshiftFormInfo, i)
    if ok and not IsSecret(t) then tex = t end
  elseif def.kind == "totem" then
    -- Totem choisi (bouton de la page affichee) ou fond de l'emplacement ; invocation / rappel : leur icone
    local b = TotemList()[i]
    local name = b and b:GetName() or ""
    local slot = tonumber(name:match("^MultiCastSlotButton(%d)$"))
    local function Tex(t)
      local v = t and t.IsShown and t:IsShown() and t:GetTexture()
      if v and not IsSecret(v) then return v end
    end
    if slot then
      for j = slot, 12, 4 do
        local a = _G["MultiCastActionButton" .. j]
        local ic = a and a:IsVisible() and (a.icon or _G["MultiCastActionButton" .. j .. "Icon"])
        tex = tex or Tex(ic)
      end
      tex = tex or Tex(b.background)
    elseif b then
      tex = Tex(b.icon or _G[name .. "Icon"])
    end
  else
    local page = def.page or 1
    local ok, t = pcall(GetActionTexture, (page - 1) * 12 + i)
    if ok and not IsSecret(t) then tex = t end
  end
  return tex or FALLBACK_ICONS[(i - 1) % #FALLBACK_ICONS + 1]
end

local function NewPreviewButton(parent)
  local b = CreateFrame("CheckButton", nil, parent)
  b.icon = b:CreateTexture(nil, "BACKGROUND", nil, 0)
  b.icon:SetAllPoints()
  b:SetHighlightTexture(WHITE)
  b:SetPushedTexture(WHITE)
  b:SetCheckedTexture(WHITE)
  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints()
  b.cooldown:SetDrawEdge(false)
  b.HotKey = b:CreateFontString(nil, "OVERLAY")
  b.Count = b:CreateFontString(nil, "OVERLAY")
  b.Name = b:CreateFontString(nil, "OVERLAY")
  for _, fs in ipairs({ b.HotKey, b.Count, b.Name }) do fs:SetFont(DEFAULT_FONT, 11, "OUTLINE") end
  b:SetScript("OnClick", function(self) self:SetChecked(false) end)
  return b
end

function AB.CreatePreview(parent)
  local pf = CreateFrame("Frame", nil, parent)
  pf:SetSize(10, 10)
  pf.buttons = {}
  for i = 1, 12 do pf.buttons[i] = NewPreviewButton(pf) end
  return pf
end

-- `key` : barre dont on montre les reglages. Bouton 1 en surbrillance (proc), 2 en recharge (en boucle), 3 avec des charges, 4 avec un nom
-- de macro, 5 coche, 1 en surbrillance (proc) ; dernier emplacement vide si "Afficher les emplacements vides".
function AB.StylePreview(pf, key)
  local def = BAR_BY[key]
  local n = math.max(1, math.min(def.count, BV(key, "count") or def.count))
  if def.kind == "totem" then n = AB.Count(key) end
  local W, H, pt, pos, w, h = AB.Grid(key, n)
  pf:SetSize(W, H)
  local empty = BV(key, "showEmpty") and n > 1 and n or nil
  local now = GetTime()
  for i, b in ipairs(pf.buttons) do
    if i <= n then
      b:ClearAllPoints()
      b:SetPoint(pt, pf, pt, pos[i][1], pos[i][2])
      b:SetSize(w, h)
      Skin(b).idx = i
      AB.StyleButton(b, key, w, h)
      b.icon:SetTexture(SampleIcon(key, i))
      b.icon:SetVertexColor(1, 1, 1)
      local hk = def.bind and GetBindingKey(def.bind .. i)
      local hkText = hk and (BV(key, "hkShort") ~= false and AB.ShortKey(hk) or GetBindingText(hk, 1)) or tostring(i % 10)
      b.HotKey:SetText(hkText)
      if skins[b].hkRing then ns.SetSlugRingText(skins[b].hkRing, hkText) end
      local ct = (i == 3) and "3" or ""
      b.Count:SetText(ct)
      if skins[b].ctRing then ns.SetSlugRingText(skins[b].ctRing, ct) end
      local nm = (i == 4) and "Macro" or ""
      b.Name:SetText(nm)
      if skins[b].nmRing then ns.SetSlugRingText(skins[b].nmRing, nm) end
      b:SetChecked(i == 5)
      skins[b].glowOn = (i == 1)   -- apercu du glow des procs sur le 1er bouton
      UpdateGlow(b, key)
      -- Animation d'entree rejouee quand son style (ou la barre affichee) change
      local ps = key .. ":" .. tostring(BV(key, "procStart"))
      if i == 1 and pf._ps ~= ps then pf._ps = ps; PlayProcStart(b, key) end
      if i == 2 then
        if not b._cdStart or now - b._cdStart > 9 then b._cdStart = now end
        b.cooldown:SetCooldown(b._cdStart, 10)
      else
        b.cooldown:Clear()
      end
      if i == empty then
        b:Hide()
      else
        b:Show()
      end
    else
      b:Hide()
    end
  end
  StyleSlots(pf, key, n, pos, pt, w, h, false)
  AB.StyleBackground(pf, key, W, H)
  pf:SetAlpha(BV(key, "alpha") or 1)
  return W, H
end

-- Activation -------------------------------------------------------------------------------------------------------
StaticPopupDialogs["AISHCORE_ACTIONBARS_RELOAD"] = {
  text = L["ACTIONBARS_RELOAD_PROMPT"],
  button1 = RELOADUI,
  button2 = L["CDM_RELOAD_LATER"],
  OnAccept = function() ReloadUI() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Anciens reglages (mode "vis", "mouseover", fondu commun) -> regles cumulables
local function MigrateVis()
  local db = ns.DB and ns.DB.actionBars
  if not (db and db.bars) or db._visRules then return end
  db._visRules = true
  local sf = { visCombat = db.sfCombat ~= false, visAttackable = db.sfTarget ~= false, visFriendly = db.sfTarget ~= false,
               visInjured = db.sfHealth ~= false }
  for _, b in pairs(db.bars) do
    if b.vis == "combat" then b.visAlways = false; b.visCombat = true end
    if b.mouseover then b.visAlways = false; b.visHover = true end
    if b.smartFade then
      b.visAlways = false
      for k, v in pairs(sf) do if v then b[k] = true end end
    end
    b.vis, b.visCustom, b.mouseover, b.smartFade = nil, nil, nil, nil
  end
  db.smartFadeAlpha, db.sfCombat, db.sfTarget, db.sfCasting, db.sfHealth = nil, nil, nil, nil, nil
end

-- Modes de visibilite (Normal / Discret / Avance) : une barre deja reglee avec les regles passe en Avance
local function MigrateVisMode()
  local db = ns.DB and ns.DB.actionBars
  if not db or db._visModes then return end
  db._visModes = true
  local function Conv(t)
    if t and t.visMode == nil and (t.visAlways == false or t.hideMounted or t.hideResting) then t.visMode = "advanced" end
  end
  for _, b in pairs(db.bars or {}) do Conv(b) end
  for _, g in pairs(db.groups or {}) do Conv(g.settings) end
end

function AB.ApplySettings()
  if not ns.DB then return end
  MigrateVis()
  MigrateVisMode()
  if not AB.IsEnabled() then
    if adopted and not AB._reloadAsked then
      -- Les boutons ne sont pas rendus a Blizzard a chaud : /reload propose (une fois)
      AB._reloadAsked = true
      for _, f in pairs(frames) do if not InCombatLockdown() then UnregisterStateDriver(f, "visibility"); f:Hide() end end
      AB.UpdateMovers()
      StaticPopup_Show("AISHCORE_ACTIONBARS_RELOAD")
    end
    return
  end
  AB._reloadAsked = nil
  if not adopted then
    AB.Adopt()
    return
  end
  if InCombatLockdown() then
    pendingLayout = true   -- mise en page et habillage a la sortie de combat
    return
  end
  LayoutAll()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UPDATE_BINDINGS",
                     "UPDATE_SHAPESHIFT_FORMS", "EDIT_MODE_LAYOUTS_UPDATED", "UPDATE_MULTI_CAST_ACTIONBAR" }) do
  pcall(ev.RegisterEvent, ev, e)   -- evenement absent d'un client (Forever) : ignore
end
ev:SetScript("OnEvent", function(_, event)
  if not (ns.DB and AB.IsEnabled()) then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if not adopted then AB.Adopt() else QueueLayout() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingAdopt then AB.Adopt() end
    if pendingLayout then LayoutAll() elseif adopted then for key in pairs(frames) do ApplyVisibility(key) end end
  elseif event == "PLAYER_REGEN_DISABLED" then
    for _, m in pairs(movers) do m:StopMovingOrSizing(); m:SetScript("OnUpdate", nil) end
    if adopted then for key in pairs(frames) do ApplyVisibility(key, true) end end
  elseif event == "UPDATE_BINDINGS" then
    C_Timer.After(0, function() for b in pairs(owner) do HotkeyText(b) end end)
  elseif adopted then
    QueueLayout()
  end
end)

-- Couleurs thematiques : repeindre les contours quand le module Couleurs change (fichier charge apres Colors.lua)
do
  local CL = ns.Modules.Colors
  if CL and CL.RegisterCallback then
    CL.RegisterCallback(function()
      if not adopted then return end
      for key, list in pairs(buttons) do
        local w, h = BV(key, "width") or 36, BV(key, "height") or 36
        for _, b in pairs(list) do
          if b:GetParent() ~= hidden then
            AB.StyleButton(b, key, w, h)
            if skins[b] and skins[b].oor then ApplyTint(b) end
          end
        end
      end
    end)
  end
end

-- Mesure (/aishdebug ab) : temps passe dans les fonctions du module, lu image par image par Debug.lua
do
  local prof = { on = false, t = {}, n = {} }
  AB._prof = prof
  AB.Buttons = function() return owner end
  local function Prof(name, fn)
    return function(...)
      if not prof.on then return fn(...) end
      local t0 = debugprofilestop()
      local r1, r2, r3, r4 = fn(...)
      prof.t[name] = (prof.t[name] or 0) + debugprofilestop() - t0
      prof.n[name] = (prof.n[name] or 0) + 1
      return r1, r2, r3, r4
    end
  end
  local rawLayout = LayoutAll
  LayoutAll = Prof("LayoutAll", function(...)
    if prof.on and not prof.src then prof.src = "direct <- " .. (debugstack(2, 3, 0) or "?") end
    return rawLayout(...)
  end)
  UpdateGlow = Prof("UpdateGlow", UpdateGlow)
  AB.StyleButton = Prof("StyleButton", AB.StyleButton)
  HotkeyText = Prof("HotkeyText", HotkeyText)
  ApplyTint = Prof("ApplyTint", ApplyTint)
  OnRange = Prof("OnRange", OnRange)
  RefreshSlots = Prof("RefreshSlots", RefreshSlots)
  ApplyVisibility = Prof("ApplyVisibility", ApplyVisibility)
  FaderTick = Prof("FaderTick", FaderTick)
end

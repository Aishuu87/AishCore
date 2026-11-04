-- Modules/Campfire.lua : "Campement" (Forever, ebauche). Pres d'un feu de camp (aura "Feu de camp proche"), un HUD
-- rond apparait ; un clic assoit le personnage. Pendant la minute assise (aura "Feu de camp accueillant"), l'anneau se
-- remplit et les bonus du camp s'affichent autour, le temps de les lire avant qu'ils tombent.
-- Le jeu ne dit pas quels objets sont poses autour d'un feu : on retient ceux que le joueur survole pres du feu
-- (infobulle d'objet), reconnus par le nom de leur sort de pose -- localise par le client, comme leur description,
-- resolue au niveau du joueur. Tout vient des tables du client : aucune donnee recopiee d'un autre addon.
local addonName, ns = ...

local Campfire = {}
ns.Modules.Campfire = Campfire

local NEARBY_AURA  = 1283391   -- Feu de camp proche (100 m) : pas toujours pose, cf. NearCampfire
local WELCOME_AURAS = { 1229739, 1289723 }   -- Feu de camp accueillant (deux variantes) : la minute pres du feu
local COOLDOWN_AURA = 1308027  -- Campement : recharge commune des bonus
local CAMPFIRE_SPELLS = { 1307227, 1307252, 1307237 }   -- Feu de camp basique / de compagnon / de specialiste
-- metres : autour d'un feu survole (sans l'aura "Feu de camp proche"), le HUD reste affiche
local NEAR_RADIUS = { [1307227] = 10, [1307252] = 30, [1307237] = 30 }
local FIRE_ICON = 135805

-- Objets de camp : sort de pose (nom de l'objet, description du bonus) -> sort du bonus (nom, icone).
-- alt : objets des paliers 2 et 3 (memes bonus que le palier 1), reconnus par leur nom au survol.
-- sum : resume affiche (cle de locale), rempli avec les nombres de la description resolue, dans l'ordre ;
-- def : valeurs fixes si la description n'en donne pas.
local FEATURES = {
  { place = 1307259, buff = 1230587, alt = { 1263005, 1263078 }, sum = "CAMPFIRE_SUM_MANA" },    -- Puits de mana (Alchimie)
  { place = 1307392, buff = 1230172, alt = { 1263041, 1263073 }, sum = "CAMPFIRE_SUM_STR" },     -- Meule a aiguiser (Forge)
  { place = 1307234, buff = 1230653, alt = { 1263056, 1263082 }, sum = "CAMPFIRE_SUM_LUTE", n = 3 },   -- Luth enchante (Enchantement)
  { place = 1307244, buff = 1230124, alt = { 1262996, 1263001 }, sum = "CAMPFIRE_SUM_STA" },     -- Trousse de premiers soins (Secourisme)
  { place = 1307245, buff = 1230098, alt = { 1262990, 1262998 }, sum = "CAMPFIRE_SUM_STATS", def = { 8 } },   -- Bocal a poisson (Peche)
  { place = 1307251, buff = 1229513, alt = { 1262980, 1263070 }, sum = "CAMPFIRE_SUM_INT" },     -- Bougie d'encens (Herboristerie)
  { place = 1307230, buff = 1229487, alt = { 1263031, 1263079 }, sum = "CAMPFIRE_SUM_REST", def = { 5 } },    -- Tente du camp (Travail du cuir)
  { place = 1307254, buff = 1230164, alt = { 1262975, 1263071 }, sum = "CAMPFIRE_SUM_AP" },      -- Magnetite (Minage)
  { place = 1307229, buff = 1229519, alt = { 1262985, 1262982 }, sum = "CAMPFIRE_SUM_CRIT", def = { 2 } },    -- Chaise du camp (Depecage)
  { place = 1307239, buff = 1229718, alt = { 1263032, 1263080 }, sum = "CAMPFIRE_SUM_SPI" },     -- Banniere de faction, Alliance (Couture)
  { place = 1307240, buff = 1229718, alt = { 1263032, 1263080 }, sum = "CAMPFIRE_SUM_SPI" },     -- Banniere de faction, Horde (Couture)
}

local function Cfg() return ns.GetCfg("campfire") or {} end

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function SpellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
  return GetSpellTexture and GetSpellTexture(id) or nil
end
local function SpellDesc(id)
  local d = (C_Spell and C_Spell.GetSpellDescription and C_Spell.GetSpellDescription(id))
    or (GetSpellDescription and GetSpellDescription(id))
  if type(d) ~= "string" then return nil end
  return (d:match("^(.-)\n") or d)   -- 1er paragraphe : le bonus (la suite parle de recharge commune)
end

local function HasAura(id)
  if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
  local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
  return ok and a or nil
end

local function WelcomeAura()
  for _, id in ipairs(WELCOME_AURAS) do
    local a = HasAura(id)
    if a then return a end
  end
end

-- ── Proximite d'un feu ──────────────────────────────────────────────────────
-- Trois signaux : l'aura "Feu de camp proche" (absente sur certaines builds), l'aura "Feu de camp accueillant"
-- (assis pres du feu), ou le survol d'un feu de camp : on retient alors l'endroit (UnitPosition) et le
-- HUD reste affiche tant qu'on reste a moins de NEAR_RADIUS metres (selon le feu).
local campPos   -- { y, x, instance }

local function PlayerPos()
  if not UnitPosition then return nil end
  local y, x, _, inst = UnitPosition("player")
  if type(y) ~= "number" or (issecretvalue and issecretvalue(y)) then return nil end
  return y, x, inst
end

local function RememberCamp(radius)
  local y, x, inst = PlayerPos()
  if y then campPos = { y = y, x = x, inst = inst, r = radius } end
end

local function NearCampfire()
  if HasAura(NEARBY_AURA) or WelcomeAura() then return true end
  if not campPos then return false end
  local y, x, inst = PlayerPos()
  if y and inst == campPos.inst and ((y - campPos.y) ^ 2 + (x - campPos.x) ^ 2) <= campPos.r * campPos.r then
    return true
  end
  campPos = nil
  return false
end

-- ── Objets reperes pres du feu (survol) ─────────────────────────────────────

local seen = {}   -- index FEATURES -> true

local function Plain(s) return type(s) == "string" and not (issecretvalue and issecretvalue(s)) end

-- Noms en minuscules, mis en cache (un nom pas encore charge par le client est redemande au survol suivant)
local lowNames = {}
local function LowName(id)
  local n = lowNames[id]
  if n == nil then
    n = SpellName(id)
    if not n then return nil end
    n = n:lower()
    lowNames[id] = n
  end
  return n
end

local function MatchFeature(objectName)
  local low = objectName:lower()
  local function Is(id)
    local n = LowName(id)
    if not n then return false end
    -- "Chaise du camp" posee s'appelle parfois juste "Chaise" : l'un contient l'autre
    return low == n or low:find(n, 1, true) or n:find(low, 1, true)
  end
  for i, f in ipairs(FEATURES) do
    if Is(f.place) then return i end
    for _, id in ipairs(f.alt or {}) do
      if Is(id) then return i end
    end
  end
end

-- Le feu pose ne porte pas toujours le nom exact du sort ("Feu de camp" pour "Feu de camp basique") :
-- l'un contient l'autre
local function IsCampfireName(objectName)
  local low = objectName:lower()
  if #low < 4 then return nil end   -- "" ou mot court : contenu dans n'importe quel nom
  for _, id in ipairs(CAMPFIRE_SPELLS) do
    local n = LowName(id)
    if n and (low == n or low:find(n, 1, true) or n:find(low, 1, true)) then return id end
  end
end

local lastHover   -- dernier objet survole (diagnostic /aishcamp)

local function OnObjectTooltip(_, data)
  if InCombatLockdown() then return end   -- jamais de feu de camp en combat
  local line = data and data.lines and data.lines[1]
  local name = line and line.leftText
  if not Plain(name) then return end
  lastHover = name
  -- Seul le survol d'un feu de camp signale le camp : un objet (forge, chaise...) peut exister hors camp
  local fire = IsCampfireName(name)
  if fire then
    RememberCamp(NEAR_RADIUS[fire])
    if Campfire.Refresh then Campfire.Refresh() end
    return
  end
  if not NearCampfire() then return end
  local i = MatchFeature(name)
  if not i then return end
  if not seen[i] then
    seen[i] = true
    -- Bannieres Alliance / Horde : un seul bonus
    for j, f in ipairs(FEATURES) do
      if f.buff == FEATURES[i].buff then seen[j] = true end
    end
  end
  if Campfire.Refresh then Campfire.Refresh() end
end

-- ── HUD ─────────────────────────────────────────────────────────────────────

local hud, hint
local LABEL_FONT = "Fonts\\2002.TTF"
local MEDIA_UI   = "Interface\\AddOns\\AishCore\\Media\\UI\\"
local FRAME_TEX  = MEDIA_UI .. "camp_hud_frame.png"
local GRUNGE     = { MEDIA_UI .. "frame_jailer1.png", MEDIA_UI .. "frame_jailer2.png", MEDIA_UI .. "frame_jailer3.png" }
local CHEVRON    = MEDIA_UI .. "chevron.png"   -- chevron des rangs de sorts (apercu du prochain niveau), pointe en haut
local TIMER_FONT = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-Bold.ttf"   -- repli 2002 si absente
Campfire.TIMER_FONT = TIMER_FONT
local GLOW_SQUARE = "Interface\\Buttons\\UI-ActionButton-Border"
local GLOW_ROUND  = "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga"
local MASK  = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQRT2 = math.sqrt(2)
local OCRE  = { 1, 189 / 255, 116 / 255 }
local GLOW_RGB = { 1, 0.85, 0.3 }
-- Fond grunge (611 x 428) : sa partie sombre couvre ~77 % de la largeur, ~63 % de la hauteur, centree 4 % plus haut
local GRUNGE_W, GRUNGE_H, GRUNGE_DY = 0.77, 0.63, 0.044
local FRAME_FIT = 1.02   -- le losange de camp_hud_frame.png remplit ~98 % de la texture
-- Bordure sombre de la texture, entre le filet clair et le bord (fraction de la demi-diagonale) : barre de la minute assise
local BAND_IN, BAND_OUT = 0.86, 0.99
local INNER = 0.85       -- filet clair interieur : reperes du minuteur
local SUM_RGB = { 16 / 255, 217 / 255, 149 / 255, 1 }   -- accent du resume des gains (#10D995)

local TIMER_RGB = { 0.95, 0.89, 0.78, 1 }
local TIP_NAME_RGB = { 0.74, 0.48, 0.27, 1 }   -- infobulle d'orbe : nom de l'objet (marron)
local TIP_STAT_RGB = { 1, 0.83, 0.42, 1 }      -- bonus (ocre / jaune)
local BAR_RGB   = { 1, 0.55, 0.15, 1 }
local SPARK_RGB = { 1, 1, 1, 1 }
local ITEM_BORDER_RGB = { 0, 0, 0, 0.9 }   -- contour des cases d'objets de camp
-- Etincelle de la barre (memes cles que la barre de cast), taille de base pour une barre de 3.2 px
local SPARKS = {
  default = { path = "Interface\\CastingBar\\UI-CastingBar-Spark", w = 16, h = 16 },
  line    = { path = "Interface\\Buttons\\WHITE8X8",               w = 2,  h = 12 },
  star    = { path = "Interface\\Cooldown\\star4",                 w = 24, h = 24 },
  burst   = { path = "Interface\\Cooldown\\starburst",             w = 24, h = 24 },
  dot     = { path = nil,                                          w = 8,  h = 8  },   -- nil : disque de l'addon
}
Campfire.SPARK_KEYS = { "default", "line", "star", "burst", "dot" }
-- Animations du losange : barre qui rattrape / se vide, minuteur qui apparait / s'efface, zoom de survol (px)
local BAR_IN, BAR_DRAIN, TIMER_IN, TIMER_OUT, HOVER_PX = 0.8, 1.2, 0.6, 0.8, 6

local orbSize = 26       -- orbes des bonus, a l'echelle du HUD (cf. LayoutDiamond)
local itemW, itemH = 26, 26   -- cases d'objets de camp (largeur, hauteur)
local SetGlow            -- cf. plus bas (halos de survol)
local WakeDriver, TimerFade

local function Pct(v) return (tonumber(v) or 100) / 100 end
local function Clamp(u) return u < 0 and 0 or (u > 1 and 1 or u) end
local function EaseOut(u) return 1 - (1 - u) ^ 3 end
local function EaseIn(u) return u * u end
local function EaseInOut(u) return u < 0.5 and 4 * u ^ 3 or 1 - (-2 * u + 2) ^ 3 / 2 end
local function EaseBack(u) return 1 + 2.4 * (u - 1) ^ 3 + 1.4 * (u - 1) ^ 2 end   -- leger depassement

-- Contour d'un texte : "NONE" | "OUTLINE" | "THICKOUTLINE" | "SLUG" (anneau de copies noires, cf. ns.CreateSlugRing).
-- reliableKey : police posee en dernier par ns.ApplyFontReliable (repli 2002 si la police est absente).
-- shadow : ombre noire (1, -1) hors SLUG.
local function Outline(fs, ring, path, size, style, reliableKey, shadow)
  path = path or LABEL_FONT
  if ns.ApplyTextOutlineStyle then
    ns.ApplyTextOutlineStyle(fs, ring, path, size, style == "NONE" and "" or style, shadow)
  else
    pcall(fs.SetFont, fs, path, size, style == "THICKOUTLINE" and "THICKOUTLINE" or (style == "OUTLINE" and "OUTLINE" or ""))
  end
  if reliableKey and ns.ApplyFontReliable then
    ns.ApplyFontReliable(fs, reliableKey, path, size,
      style == "THICKOUTLINE" and "THICKOUTLINE" or (style == "OUTLINE" and "OUTLINE" or ""))
  end
end

-- Opacite du minuteur et de son anneau SLUG (des FontStrings a part, qui ne suivent pas celle du texte)
local function SetTimerAlpha(a)
  hud.timer:SetAlpha(a)
  for _, r in ipairs(hud.timerRing or {}) do r:SetAlpha(a) end
end

-- Minuteur : position reglee + glissement vertical de l'animation (dy)
local function PlaceTimer(dy)
  hud.timer:ClearAllPoints()
  hud.timer:SetPoint("CENTER", hud.core, "CENTER", hud._timerX or 0, (hud._timerY or 0) + (dy or 0))
end

-- Decalages divises par l'echelle du HUD (zoom d'apparition) : le centre reste au meme endroit de l'ecran
local function Place()
  local c = Cfg()
  local s = hud:GetScale()
  hud:ClearAllPoints()
  -- Apercu du GUI : centre dans son cadre, un peu bas (le resume s'affiche au-dessus du losange)
  if hud._host then
    hud:SetPoint("CENTER", hud._host, "CENTER", 0, (hud._hostDY or 0) / s + (hud._dy or 0) / s)
    return
  end
  hud:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
    UIParent:GetWidth() * (c.anchorPctX or 0.5) / s, (UIParent:GetHeight() * (c.anchorPctY or 0.62) + (hud._dy or 0)) / s)
end

-- Fond grunge pose sous un bloc de w x h (centre du bloc = centre de la texture parente)
local function FitGrunge(tex, w, h)
  local gh = h / GRUNGE_H
  tex:SetSize(w / GRUNGE_W, gh)
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", tex:GetParent(), "CENTER", 0, -gh * GRUNGE_DY)
end

local function Create()
  if hud then return end
  hud = CreateFrame("Button", "AishCoreCampfire", UIParent)
  hud:SetFrameStrata("MEDIUM")
  hud:SetClampedToScreen(true)
  hud:SetMovable(true)
  hud:RegisterForDrag("LeftButton")
  hud:Hide()

  -- Losange (texture, barre de la minute, minuteur, halo interieur) : calque a part, grossit un peu au survol
  hud.core = CreateFrame("Frame", nil, hud)
  hud.core:SetPoint("CENTER")
  hud.core:SetSize(1, 1)
  hud.bg = hud.core:CreateTexture(nil, "BACKGROUND")
  hud.bg:SetPoint("CENTER")
  hud.bg:SetTexture(FRAME_TEX)
  hud.halo = hud.core:CreateTexture(nil, "ARTWORK")
  hud.halo:SetTexture(GLOW_ROUND)
  hud.halo:SetBlendMode("ADD")
  hud.halo:SetVertexColor(GLOW_RGB[1], GLOW_RGB[2], GLOW_RGB[3], 1)
  hud.halo:SetPoint("CENTER")
  hud.halo:SetAlpha(0)
  hud.halo._ga = 0.22

  -- Minute pres du feu : remplissage du filet interieur, 4 cotes pivotes autour de leur sommet de depart
  hud.fill = {}
  for i = 1, 4 do
    hud.fill[i] = hud.core:CreateTexture(nil, "OVERLAY")
  end
  hud.spark = hud.core:CreateTexture(nil, "OVERLAY", nil, 2)
  hud.spark:SetBlendMode("ADD")
  -- Lueur doree de fin de minute, sur le contour (cf. doneFx)
  hud.doneGlow = hud.core:CreateTexture(nil, "OVERLAY", nil, 1)
  hud.doneGlow:SetTexture(GLOW_SQUARE)
  hud.doneGlow:SetBlendMode("ADD")
  hud.doneGlow:SetVertexColor(1, 0.8, 0.25, 1)
  hud.doneGlow:SetPoint("CENTER")
  hud.doneGlow:SetRotation(math.pi / 4)
  hud.doneGlow:SetAlpha(0)
  hud.timer = hud.core:CreateFontString(nil, "OVERLAY")
  hud.timer:SetFont(LABEL_FONT, 12, "OUTLINE")
  hud.timerRing = ns.CreateSlugRing and ns.CreateSlugRing(hud.core, hud.timer, "ARTWORK")
  Outline(hud.timer, hud.timerRing, LABEL_FONT, 12, "OUTLINE")   -- police posee sur l'anneau avant tout SetText
  SetTimerAlpha(0)

  hint = hud:CreateFontString(nil, "OVERLAY")
  hint:SetFont(LABEL_FONT, 11, "OUTLINE")
  hint:SetPoint("TOP", hud, "BOTTOM", 0, -6)
  hint:SetTextColor(1, 0.82, 0.5, 1)
  hint:SetSpacing(2)
  -- Au survol du losange : aide (clic gauche / droit) sur une ombre, a la place de l'etat (alphas pilotes par SetGlow)
  hud.help = hud:CreateFontString(nil, "OVERLAY")
  hud.help:SetFont(LABEL_FONT, 11, "OUTLINE")
  hud.help:SetPoint("TOP", hud, "BOTTOM", 0, -6)
  hud.help:SetTextColor(1, 0.82, 0.5, 1)
  hud.help:SetSpacing(2)
  hud.help:SetAlpha(0)
  hud.help._ga = 1
  hud.hintShadow = hud:CreateTexture(nil, "BORDER")
  hud.hintShadow:SetTexture(GLOW_ROUND)
  hud.hintShadow:SetVertexColor(0, 0, 0, 1)
  hud.hintShadow:SetPoint("CENTER", hud.help, "CENTER", 0, 0)
  hud.hintShadow:SetAlpha(0)
  hud.hintShadow._ga = 0.75
  hud.hintFade = hint       -- etat : s'efface pendant le survol
  hint._ga = 1
  hud.glow = hud:CreateTexture(nil, "BACKGROUND", nil, -1)
  hud.glow:SetTexture(GLOW_SQUARE)
  hud.glow:SetBlendMode("ADD")
  hud.glow:SetVertexColor(GLOW_RGB[1], GLOW_RGB[2], GLOW_RGB[3], 1)
  hud.glow:SetPoint("CENTER")
  hud.glow:SetRotation(math.pi / 4)
  hud.glow:SetAlpha(0)
  hud.glow._ga = 0.35

  -- Eclat de fusion des orbes, au sommet du losange
  hud.flash = hud:CreateTexture(nil, "OVERLAY", nil, 3)
  hud.flash:SetTexture(GLOW_ROUND)
  hud.flash:SetBlendMode("ADD")
  hud.flash:SetVertexColor(1, 0.6, 0.2, 1)
  hud.flash:Hide()

  hud:SetFrameLevel(10)
  hud.core:SetFrameLevel(11)
  hud:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  hud:SetScript("OnClick", function(self, button)
    if button == "RightButton" then Campfire.TogglePanels(); return end
    if self._host then return end   -- apercu du GUI : pas d'emote
    if WelcomeAura() then return end
    DoEmote("SIT")
  end)
  hud:SetScript("OnDragStart", function(self)
    if Cfg().locked or self._host then return end
    self._moving = true
    self:StartMoving()
  end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self._moving = nil
    local cx, cy = self:GetCenter()
    local sc = self:GetScale()
    cx, cy = cx * sc, cy * sc
    ns.DB.campfire = ns.DB.campfire or {}
    ns.DB.campfire.anchorPctX = cx / UIParent:GetWidth()
    ns.DB.campfire.anchorPctY = (cy - (self._dy or 0)) / UIParent:GetHeight()
    Place()
  end)
  hud:SetScript("OnEnter", function(self)
    SetGlow(self.glow, true)
    SetGlow(self.halo, true)
    self._hovT = 1
    if self._panels then return end   -- panneaux deplies : le panneau du bas occupe la place
    if self._host then return end   -- apercu : pas d'aide clic gauche / droit
    self.help:SetText(ns.L["CAMPFIRE_HINT_SIT"])
    self.hintShadow:SetSize(self.help:GetStringWidth() + 60, self.help:GetStringHeight() + 26)
    SetGlow(self.help, true)
    SetGlow(self.hintShadow, true)
    SetGlow(hint, false)
  end)
  hud:SetScript("OnLeave", function(self)
    SetGlow(self.glow, false)
    SetGlow(self.halo, false)
    self._hovT = 0
    SetGlow(self.help, false)
    SetGlow(self.hintShadow, false)
    if not self._panels then SetGlow(hint, true) end
  end)
end

-- ── Chargement en losange ───────────────────────────────────────────────────
-- Sommets depuis le haut, sens horaire : haut -> droite -> bas -> gauche. Chaque cote part de son sommet et
-- grandit vers le suivant (pivot de rotation sur son bord gauche) ; un quart de la duree par cote, vitesse
-- constante sur tout le contour. La barre couvre la bordure sombre de la texture ; chaque cote demarre une
-- demi-epaisseur avant son sommet, pour que les angles soient pleins.
local DIAMOND = {
  { 0, 1,  -math.pi / 4 },        -- haut -> droite
  { 1, 0,  -3 * math.pi / 4 },    -- droite -> bas
  { 0, -1,  3 * math.pi / 4 },    -- bas -> gauche
  { -1, 0,  math.pi / 4 },        -- gauche -> haut
}
local PIVOT = CreateVector2D and CreateVector2D(0, 0.5)

-- Couleur et texture de la barre, avant LayoutDiamond (qui pose la rotation des cotes)
local function StyleBar()
  local c = Cfg()
  local path = ns.ResolveBarTexFromKey and ns.ResolveBarTexFromKey(c.barTexture or ns.BAR_TEXTURE_DEFAULT)
  local col = c.barColor or BAR_RGB
  for _, t in ipairs(hud.fill) do
    t:SetTexture(path or "Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
  end
end

local function LayoutDiamond(size)
  local c = Cfg()
  local R = size / 2
  local r = R * (BAND_IN + BAND_OUT) / 2           -- milieu de la bordure
  local thick = math.max(2, R * (BAND_OUT - BAND_IN) / SQRT2) * Pct(c.barSize)
  local side = r * SQRT2
  StyleBar()
  hud:SetSize(size, size)
  hud.core:SetSize(size, size)
  hud.bg:SetSize(size * FRAME_FIT, size * FRAME_FIT)
  for i, d in ipairs(DIAMOND) do
    local t = hud.fill[i]
    local n = DIAMOND[i % 4 + 1]
    local ux, uy = (n[1] - d[1]) / SQRT2, (n[2] - d[2]) / SQRT2   -- direction du cote
    t:ClearAllPoints()
    t:SetPoint("LEFT", hud.core, "CENTER", d[1] * r - ux * thick / 2, d[2] * r - uy * thick / 2)
    t:SetHeight(thick)
    if PIVOT then t:SetRotation(d[3], PIVOT) else t:SetRotation(d[3]) end
  end
  hud._thick = thick
  local ri = R * INNER
  -- Zone cliquable : carre inscrit dans le losange, les panneaux des metiers restent cliquables tout autour
  local inset = size / 4
  hud:SetHitRectInsets(inset, inset, inset, inset)
  -- Minuteur dans la pointe du haut (police, taille, couleur et decalage reglables)
  local fs = math.max(6, math.floor(math.max(12, R * 0.17) * Pct(c.timerSize) + 0.5))
  Outline(hud.timer, hud.timerRing, c.timerFont or TIMER_FONT, fs, c.timerOutline or "OUTLINE", "campfireTimer")
  local tc = c.timerColor or TIMER_RGB
  hud.timer:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
  hud._timerX, hud._timerY = c.timerX or 0, ri - fs * 0.95 + (c.timerY or 0)
  PlaceTimer(0)
  -- Halo de survol : disque doux inscrit dans le filet interieur, la bordure exterieure reste intacte
  hud.halo:SetSize(ri * 1.5, ri * 1.5)
  hud.glow:SetSize(R * 2.6, R * 2.6)   -- le carre lumineux de la texture occupe ~56 % de sa largeur
  hud.doneGlow:SetSize(R * 2.6, R * 2.6)
  local base = 26 * math.sqrt(size / 70)
  orbSize = math.floor(base * Pct(c.buffSize) + 0.5)
  -- Cases d'objets : largeur et hauteur en % de la taille de base (ancien reglage unique itemSize en repli)
  local ib = base * Pct(c.itemSize)
  itemW = math.floor(ib * Pct(c.itemWidth) + 0.5)
  itemH = math.floor(ib * Pct(c.itemHeight) + 0.5)
  -- Etincelle : proportionnelle a l'epaisseur de la barre
  local sp = SPARKS[c.barSpark or "default"] or SPARKS.default
  local k = thick / 3.2
  local ks = k * Pct(c.barSparkSize)
  hud._spW, hud._spH = math.max(2, sp.w * ks), math.max(2, sp.h * ks)
  hud._spAnim = c.barSparkAnim ~= false
  hud._barAnim = c.barAnim == true
  if not hud._barAnim then for _, t in ipairs(hud.fill) do t:SetAlpha(1) end end
  local sc = c.barSparkColor or SPARK_RGB
  hud.spark:SetTexture(sp.path or ns.Media.circle)
  hud.spark:SetVertexColor(sc[1], sc[2], sc[3], 1)
  hud._spA = sc[4] or 1
  hud.spark:SetSize(hud._spW, hud._spH)
  hud.spark:SetAlpha(hud._spA)
  hud._side, hud._pr, hud._r, hud._size = side, r, R, size
end

-- p : 0..1 sur le contour entier
local function SetDiamondProgress(p)
  local side, r = hud._side or 1, hud._pr or 1
  local total = math.max(0, math.min(1, p)) * 4
  hud._p = p
  local tipX, tipY, tipA
  -- Braise sur la barre : opacite qui ondule entre 50 et 100 %
  if hud._barAnim then
    local t = GetTime()
    local n = (math.sin(t * 3.1) + math.sin(t * 5.3 + 1.7) + math.sin(t * 8.9 + 0.6)) / 3   -- -1..1
    local a = 0.75 + 0.25 * n
    for _, f in ipairs(hud.fill) do f:SetAlpha(a) end
  end
  for i, d in ipairs(DIAMOND) do
    local f = math.max(0, math.min(1, total - (i - 1)))
    local fill = hud.fill[i]
    if f <= 0 then
      fill:Hide()
    else
      fill:SetWidth(side * f + (hud._thick or 2) / 2)
      fill:Show()
      local nx, ny = DIAMOND[i % 4 + 1][1], DIAMOND[i % 4 + 1][2]
      tipX = (d[1] + (nx - d[1]) * f) * r
      tipY = (d[2] + (ny - d[2]) * f) * r
      tipA = d[3]
    end
  end
  if tipX and p > 0 and p < 1 then
    hud.spark:ClearAllPoints()
    hud.spark:SetPoint("CENTER", hud.core, "CENTER", tipX, tipY)
    hud.spark:SetRotation(tipA)
    -- Braise : opacite qui vacille et leger pulse de taille (sinus de frequences sans rapport simple)
    if hud._spAnim then
      local t = GetTime()
      local n1 = (math.sin(t * 11) + math.sin(t * 17.3 + 1.3) + math.sin(t * 5.1 + 2)) / 3
      local n2 = (math.sin(t * 7.7 + 0.4) + math.sin(t * 13.1 + 2.2)) / 2
      local s = 1 + 0.12 * n2
      hud.spark:SetSize(hud._spW * s, hud._spH * s)
      hud.spark:SetAlpha((hud._spA or 1) * (0.72 + 0.28 * n1))
    end
    hud.spark:Show()
  else
    hud.spark:Hide()
  end
end

local diaStart, diaDur, diaSec = 0, 1, false   -- diaSec false : arrete
-- diaEnter : la barre rattrape la progression reelle en demarrant (minute deja entamee, barre en train de se vider) ;
-- drain : apres la minute (levee ou fin), la barre recule jusqu'a se vider au lieu de disparaitre
local diaEnter, drain
local diaLoop = false   -- apercu du GUI : la minute recommence aussitot finie, sans pause
-- doneFx : minute complete, la barre passe a l'or, brille un instant puis s'efface (au lieu de se vider)
local doneFx
local DONE_RGB = { 1, 0.8, 0.25 }
local DONE_IN, DONE_HOLD, DONE_OUT = 0.35, 1.5, 1.6

local function RestoreBar()
  StyleBar()
  for _, t in ipairs(hud.fill) do t:SetAlpha(1) end
  hud.doneGlow:SetAlpha(0)
end

local function DiamondUpdate()
  local now = GetTime()
  if diaLoop and now - diaStart >= diaDur then
    diaStart = diaStart + diaDur * math.floor((now - diaStart) / diaDur)
    diaEnter = nil
  end
  local elapsed = now - diaStart
  local p = Clamp(elapsed / diaDur)
  if diaEnter then
    local u = Clamp((now - diaEnter.t0) / BAR_IN)
    if u >= 1 then diaEnter = nil else p = diaEnter.from + (p - diaEnter.from) * EaseOut(u) end
  end
  SetDiamondProgress(p)
  local left = diaDur - elapsed
  local sec = left > 0 and math.ceil(left) or 0
  if sec ~= diaSec then
    diaSec = sec
    if sec > 0 then hud.timer:SetText(sec) else TimerFade(false) end   -- 0 : le dernier chiffre s'efface
  end
  if left <= 0 and not diaEnter then hud:SetScript("OnUpdate", nil) end
end

-- instant : HUD masque ou reinitialise, sans animation de sortie
-- complete : minute allee a son terme (effet doré au lieu de la vidange)
local function StopDiamond(instant, complete)
  if instant then
    hud:SetScript("OnUpdate", nil)
    diaEnter, drain, diaLoop = nil, nil, false
    if doneFx then doneFx = nil; RestoreBar() end
    SetDiamondProgress(0)
    hud._tf = nil
    SetTimerAlpha(0)
    hud.timer:SetText("")
    PlaceTimer(0)
    diaStart, diaDur, diaSec = 0, 1, false
    return
  end
  if diaSec == false then return end   -- deja a l'arret
  hud:SetScript("OnUpdate", nil)
  diaEnter = nil
  diaStart, diaDur, diaSec = 0, 1, false
  if (hud._p or 0) > 0 then
    if complete then
      SetDiamondProgress(1)
      doneFx = { t0 = GetTime() }
    else
      drain = { from = hud._p, t0 = GetTime() }
    end
    WakeDriver()
  end
  TimerFade(false)
end

local function RunDiamond(startTime, duration)
  if diaSec ~= false and diaStart == startTime and diaDur == duration then return end   -- deja lance
  if doneFx then doneFx = nil; RestoreBar(); SetDiamondProgress(0) end
  diaStart, diaDur, diaSec = startTime, duration, nil
  diaEnter, drain = { from = hud._p or 0, t0 = GetTime() }, nil
  TimerFade(true)
  hud:SetScript("OnUpdate", DiamondUpdate)
end

-- Resume du bonus : nombres de la description resolue au niveau du joueur, dans l'ordre (le client FR ecrit
-- "8 %" avec une espace insecable : seuls les chiffres sont lus, l'unite vient du libelle)
local function Summary(f, desc)
  local vals = {}
  if desc then
    for v in desc:gmatch("%d[%d%.,]*") do
      vals[#vals + 1] = (v:gsub("[%.,]+$", ""))
      if #vals >= (f.n or 1) then break end
    end
  end
  if #vals < (f.n or 1) then vals = f.def end
  if not vals or #vals < (f.n or 1) then return nil end
  return string.format(ns.L[f.sum], unpack(vals))
end

-- ── Animations : orbes des bonus, rassemblement, resume, panneaux des metiers ──
-- Un seul OnUpdate (driver), actif tant qu'un element bouge ou flotte.
local GATHER = 0.55        -- trajet d'une orbe vers le sommet du losange
local SUM_HOLD = 14        -- duree d'affichage du resume des gains
local SUM_FONT, SUM_ICON, SUM_ROW, SUM_Y = 17, 20, 23, 54   -- SUM_Y : 1re ligne au-dessus du sommet
local SUM_IN, SUM_OUT, ORB_POP = 0.6, 0.9, 0.55            -- entree / sortie du resume, apparition d'une orbe
local ARC_SPAN, ARC_STEP = math.rad(150), math.rad(30)   -- arc des orbes : ouverture maxi, ecart maxi
local orbs, sumLines, panels, slots, bars = {}, {}, {}, {}, {}
local fx = {}              -- phase = nil | "gather" | "summary" ; sum0, flash0, sumT0, sumEnd
local panelOpen, panelT0 = false, 0
local barE, barFrom = 0, 0
local curList = {}         -- bonus actuellement en orbes
local glows = {}           -- texture de survol -> 1 (allumer) | 0 (eteindre)
local tip, sumBg
local driver, OnDriver
local UpdateDeco
local testUntil = 0        -- /aishcamp test : Refresh laisse la main a la demo

for i, f in ipairs(FEATURES) do f.i = i end

local function MaskedIcon(parent, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetPoint("CENTER")
  t:SetSize(size, size)
  t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local m = parent:CreateMaskTexture()
  m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:SetAllPoints(t)
  t:AddMaskTexture(m)
  return t
end

WakeDriver = function()
  if not driver then
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self, dt) OnDriver(self, dt) end)
  end
  driver:Show()
end

-- Halo jaune de survol (texture ADD, alpha maxi t._ga), allume / eteint en fondu par le driver
local function GlowTex(parent, tex, layer, maxA)
  local g = parent:CreateTexture(nil, layer or "BACKGROUND", nil, -1)
  g:SetTexture(tex)
  g:SetBlendMode("ADD")
  g:SetVertexColor(GLOW_RGB[1], GLOW_RGB[2], GLOW_RGB[3], 1)
  g:SetPoint("CENTER")
  g:SetAlpha(0)
  g._ga = maxA or 0.8
  return g
end

SetGlow = function(g, on)
  glows[g] = on and 1 or 0
  WakeDriver()
end

-- Minuteur : apparait en descendant dans la pointe, s'efface en remontant (anime par le driver)
TimerFade = function(on)
  local to = on and 1 or 0
  if hud._tf and hud._tf.to == to then return end
  local a = hud.timer:GetAlpha()
  if not hud._tf and a == to then return end
  hud._tf = { from = a, to = to, t0 = GetTime() }
  WakeDriver()
end

-- ── Geometrie des panneaux des metiers ──────────────────────────────────────
-- d : panneaux en diagonale, cotes paralleles a ceux du losange et glisses un peu dessous ; D : panneau du bas, cale
-- entre les deux panneaux du bas (4 px d'ecart)
local function PanelGeometry()
  local R = hud._r or 35
  local r = R * 0.54                       -- demi-diagonale d'un panneau
  return R, r, (R + r) / SQRT2 - R * 0.06, 2 * r + 4 * SQRT2
end

-- ── Orbes des bonus ─────────────────────────────────────────────────────────

local function Tip()
  if tip then return tip end
  tip = CreateFrame("Frame", nil, hud)
  tip:SetFrameLevel(hud:GetFrameLevel() + 8)
  tip.bg = tip:CreateTexture(nil, "BACKGROUND")
  tip.bg:SetAlpha(0.85)
  tip.name = tip:CreateFontString(nil, "OVERLAY")
  tip.name:SetFont(LABEL_FONT, 13, "")
  tip.name:SetShadowOffset(1, -1)
  tip.stat = tip:CreateFontString(nil, "OVERLAY")
  tip.stat:SetFont(LABEL_FONT, 12, "")
  tip.stat:SetShadowOffset(1, -1)
  if ns.CreateSlugRing then
    tip.nameRing = ns.CreateSlugRing(tip, tip.name, "ARTWORK")
    tip.statRing = ns.CreateSlugRing(tip, tip.stat, "ARTWORK")
  end
  Outline(tip.name, tip.nameRing, LABEL_FONT, 13, "NONE", nil, true)
  Outline(tip.stat, tip.statRing, LABEL_FONT, 12, "NONE", nil, true)
  tip:Hide()
  return tip
end

local function ShowTip(o)
  local t = Tip()
  local c = Cfg()
  local fs, font = c.tipFontSize or 13, c.tipFont or LABEL_FONT
  local nc, sc = c.tipNameColor or TIP_NAME_RGB, c.tipStatColor or TIP_STAT_RGB
  Outline(t.name, t.nameRing, font, fs, c.tipOutline or "NONE", nil, true)
  t.name:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
  Outline(t.stat, t.statRing, font, math.max(6, fs - 1), c.tipOutline or "NONE", nil, true)
  t.stat:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
  t.gap = c.tipOffset or 8
  t.bg:SetTexture(GRUNGE[(o.i % 3) + 1])
  t.name:SetText(o.item or "")
  t.stat:SetText(o.stat or "")
  local nh = o.item and t.name:GetStringHeight() or 0
  local sh = t.stat:GetStringHeight()
  local w = math.max(o.item and t.name:GetStringWidth() or 0, t.stat:GetStringWidth()) + 28
  local h = nh + sh + (o.item and 3 or 0) + 14
  t:SetSize(w, h)
  t.name:ClearAllPoints()
  t.name:SetPoint("TOP", t, "TOP", 0, -7)
  t.stat:ClearAllPoints()
  if o.item then t.stat:SetPoint("TOP", t.name, "BOTTOM", 0, -3) else t.stat:SetPoint("TOP", t, "TOP", 0, -7) end
  FitGrunge(t.bg, w, h)
  t.owner, t.dir, t.t0, t.out = o, o.dir, GetTime(), nil
  t:SetAlpha(0)
  t:Show()
  WakeDriver()
end

local function HideTip(o)
  if tip and tip.owner == o and not tip.out then tip.out = GetTime(); WakeDriver() end
end

-- Orbe d'un bonus : icone ronde cerclee ; au survol elle grossit et son infobulle glisse vers l'exterieur
local function Orb(i)
  local o = orbs[i]
  if o then return o end
  o = CreateFrame("Frame", nil, hud)
  o:SetFrameLevel(hud:GetFrameLevel() + 3)
  o.glow = GlowTex(o, GLOW_ROUND, "BACKGROUND", 0.75)
  o.ring = o:CreateTexture(nil, "BACKGROUND")
  o.ring:SetTexture(ns.Media.circle)
  o.ring:SetPoint("CENTER")
  o.ring:SetVertexColor(1, 0.55, 0.15, 0.9)
  o.tex = MaskedIcon(o, orbSize)
  o.h = 0
  o:EnableMouse(true)
  o:SetScript("OnEnter", function(self)
    self.hover = true
    self:SetFrameLevel(hud:GetFrameLevel() + 5)
    SetGlow(self.glow, true)
    ShowTip(self)
  end)
  o:SetScript("OnLeave", function(self)
    self.hover = nil
    self:SetFrameLevel(hud:GetFrameLevel() + 3)
    SetGlow(self.glow, false)
    HideTip(self)
  end)
  -- Flottement : frequences et phases propres a chaque orbe
  o.fx, o.fy = 0.9 + math.random() * 0.7, 1.2 + math.random() * 0.9
  o.px, o.py = math.random() * 6.28, math.random() * 6.28
  o.cx, o.cy, o.tx, o.ty = 0, 0, 0, 0
  o.i = i
  o:Hide()
  orbs[i] = o
  return o
end

-- Orbes en arc de cercle au-dessus du losange, de gauche a droite. Le rayon garde les orbes espacees (10 au plus)
-- et s'agrandit quand les panneaux des metiers sont deplies, pour passer au-dessus.
local function LayoutOrbs(list)
  curList = list
  local n, S, R = #list, orbSize, hud._r or 35
  local step = n > 1 and math.min(ARC_STEP, ARC_SPAN / (n - 1)) or ARC_STEP
  local radius = math.max(R + S / 2 + 12, (S + 6) / step)
  if panelOpen then
    local _, r, d = PanelGeometry()
    radius = math.max(d + r + S / 2 + 8, radius + R * 0.35)
  end
  local want = {}
  for k, f in ipairs(list) do
    want[f.i] = true
    local o = Orb(f.i)
    local off = ((n + 1) / 2 - k) * step
    local a = math.pi / 2 + off
    o.tx, o.ty = radius * math.cos(a), radius * math.sin(a)
    -- Infobulle : vers le haut pour l'orbe du milieu (les deux du milieu si leur nombre est pair), sinon vers l'exterieur
    o.dir = math.abs(off) <= step / 2 + 0.01 and "up" or (off > 0 and "left" or "right")
    o:SetSize(S, S)
    o.ring:SetSize(S + 4, S + 4)
    o.tex:SetSize(S, S)
    o.glow:SetSize(S * 1.9, S * 1.9)
    if not o:IsShown() then
      o.cx, o.cy, o.popT, o.g0 = o.tx * 0.7, o.ty * 0.7, 0, nil
      o:SetAlpha(0)
      o:Show()
    end
    o.tex:SetTexture(SpellIcon(f.buff) or FIRE_ICON)
    o.stat = Summary(f, SpellDesc(f.place)) or SpellName(f.buff) or "?"
    o.item = SpellName(f.place)
  end
  for i, o in pairs(orbs) do
    if not want[i] then
      o:Hide()
      o.hover = nil
      HideTip(o)
    end
  end
  if n > 0 then WakeDriver() end
end

-- Bonus reperes au survol (bannieres Alliance / Horde : un seul)
local function SeenList()
  local list, done = {}, {}
  for i, f in ipairs(FEATURES) do
    if seen[i] and not done[f.buff] then done[f.buff] = true; list[#list + 1] = f end
  end
  return list
end

-- Bonus obtenus : reperes au survol ou presents sur le joueur
local function GainedList()
  local list, done = {}, {}
  for i, f in ipairs(FEATURES) do
    if (seen[i] or HasAura(f.buff)) and not done[f.buff] then done[f.buff] = true; list[#list + 1] = f end
  end
  return list
end

local function HideSummary()
  for _, l in ipairs(sumLines) do l:Hide() end
  if sumBg then sumBg:Hide() end
end

local function SumLine(k)
  local l = sumLines[k]
  if l then return l end
  l = CreateFrame("Frame", nil, hud)
  l:SetSize(10, SUM_ROW)
  l:SetFrameLevel(hud:GetFrameLevel() + 6)
  l.icon = MaskedIcon(l, SUM_ICON)
  l.icon:ClearAllPoints()
  l.icon:SetPoint("LEFT")
  l.text = l:CreateFontString(nil, "OVERLAY")
  l.text:SetFont(LABEL_FONT, SUM_FONT, "OUTLINE")
  l.ring = ns.CreateSlugRing and ns.CreateSlugRing(l, l.text, "ARTWORK")
  Outline(l.text, l.ring, LABEL_FONT, SUM_FONT, "OUTLINE")
  l.text:SetPoint("LEFT", l.icon, "RIGHT", 8, 0)
  l:Hide()
  sumLines[k] = l
  return l
end

-- Resume des gains au-dessus du losange, sur fond grunge (comme le toast de niveau) : une ligne par bonus,
-- glissement de droite a gauche en decale
local function StartSummary(list)
  list = list or GainedList()
  fx.sumList = list
  HideSummary()
  if #list == 0 then fx.phase = nil; if UpdateDeco then UpdateDeco() end; return end
  local now, m, R = GetTime(), #list, hud._r or 35
  -- Police, taille et couleur reglables ; icone et interligne suivent la taille du texte
  local c = Cfg()
  local fs = c.buffFontSize or SUM_FONT
  local icon, row = math.floor(fs * SUM_ICON / SUM_FONT + 0.5), math.floor(fs * SUM_ROW / SUM_FONT + 0.5)
  local col = c.buffColor or SUM_RGB
  local maxW = 0
  for k, f in ipairs(list) do
    local l = SumLine(k)
    l:SetHeight(row)
    l.icon:SetSize(icon, icon)
    l.icon:SetTexture(SpellIcon(f.buff) or FIRE_ICON)
    Outline(l.text, l.ring, c.buffFont or LABEL_FONT, fs, c.buffOutline or "OUTLINE")
    l.text:SetTextColor(col[1], col[2], col[3], col[4] or 1)
    l.text:SetText(Summary(f, SpellDesc(f.place)) or SpellName(f.buff) or "?")
    local w = icon + 8 + l.text:GetStringWidth()
    l:SetWidth(w)
    maxW = math.max(maxW, w)
    l.y = R + SUM_Y + (c.sumY or 0) + (m - k) * row
    l.t0 = now + (k - 1) * 0.09
    l:SetAlpha(0)
    l:Show()
  end
  fx.sumX, fx.sumOX = -maxW / 2 + (c.sumX or 0), c.sumX or 0
  if not sumBg then
    sumBg = CreateFrame("Frame", nil, hud)
    sumBg:SetFrameLevel(hud:GetFrameLevel() + 5)
    sumBg.tex = sumBg:CreateTexture(nil, "BACKGROUND")
    sumBg.tex:SetAlpha(0.8)
  end
  sumBg.tex:SetTexture(GRUNGE[math.random(#GRUNGE)])
  local w, h = maxW + 60, m * row + 28
  sumBg:SetSize(w, h)
  FitGrunge(sumBg.tex, w, h)
  sumBg.y = R + SUM_Y + (c.sumY or 0) + (m - 1) * row / 2
  sumBg:SetAlpha(0)
  sumBg:Show()
  fx.phase, fx.sumT0, fx.sumEnd = "summary", now, now + (m - 1) * 0.09 + SUM_IN + SUM_HOLD
  WakeDriver()
  if UpdateDeco then UpdateDeco() end
end

-- Fin de la minute : les orbes rejoignent le sommet du losange et s'y fondent, puis le resume s'affiche
local function StartGather()
  local now, k = GetTime(), 0
  if tip then tip:Hide(); tip.owner = nil end
  for _, f in ipairs(SeenList()) do
    local o = orbs[f.i]
    if o and o:IsShown() then
      o.g0, o.gx, o.gy = now + k * 0.08, o.cx, o.cy
      k = k + 1
    end
  end
  fx.phase = "gather"
  if k > 0 then
    fx.sum0 = now + (k - 1) * 0.08 + GATHER + 0.15
    fx.flash0 = fx.sum0 - 0.3
  else
    fx.sum0, fx.flash0 = now + 0.3, nil
  end
  WakeDriver()
end

-- ── Panneaux des metiers et barres d'objets de camp (clic droit) ────────────
-- Boutons securises (macro, comme le Menu Bar ; objet du sac pour les barres) : crees, deplaces et masques hors
-- combat seulement. Ordre horaire pour le decalage : haut gauche, haut droite, bas droite, bas, bas gauche.
local PANELS = {
  { key = "1",        arg = "1",          ang = 3 * math.pi / 4,  name = "CAMPFIRE_PROF_1",       icon = 134400 },
  { key = "2",        arg = "2",          ang = math.pi / 4,      name = "CAMPFIRE_PROF_2",       icon = 134400 },
  { key = "firstaid", arg = '"firstaid"', ang = -math.pi / 4,     name = "CAMPFIRE_PROF_AID",     icon = 135966 },
  { key = "fishing",  arg = '"fishing"',  ang = -math.pi / 2,     name = "CAMPFIRE_PROF_FISHING", icon = 136245, low = true },
  { key = "cooking",  arg = '"cooking"',  ang = -3 * math.pi / 4, name = "CAMPFIRE_PROF_COOKING", icon = 133971 },
}
local MAX_ITEMS = 10       -- cases d'objets, reparties sur les deux barres

local function ProfInfo(key)
  if not (GetProfessions and GetProfessionInfo) then return nil end
  local p1, p2, arch, fish, cook, aid = GetProfessions()
  -- Forever : les Premiers soins sont renvoyes en 3e position (cf. AishCoreMenuBar_Profession)
  if ns.IsForever then aid = aid or arch end
  local idx = ({ ["1"] = p1, ["2"] = p2, cooking = cook, firstaid = aid, fishing = fish })[key]
  if not idx then return nil end
  return GetProfessionInfo(idx)
end

-- Mot "feu de camp" du client : partie commune aux noms des trois feux (FR "Feu de camp ...", EN "... Campfire")
local campWord
local function CampWord()
  if campWord then return campWord end
  local names = {}
  for _, id in ipairs(CAMPFIRE_SPELLS) do
    local n = LowName(id)
    if not n then return nil end
    names[#names + 1] = n
  end
  local a, best = names[1], ""
  for i = 1, #a do
    for j = i + #best, #a do
      local sub = a:sub(i, j)
      local all = true
      for k = 2, #names do if not names[k]:find(sub, 1, true) then all = false; break end end
      if not all then break end
      best = sub
    end
  end
  best = best:gsub("^%s+", ""):gsub("%s+$", "")
  if #best >= 4 then campWord = best end
  return campWord
end

-- Mots cherches dans les infobulles : celui du client, plus les formes FR / EN
local function CampWords()
  local list, w = { "feu de camp", "campfire" }, CampWord()
  if w and w ~= list[1] and w ~= list[2] then table.insert(list, 1, w) end
  return list
end

-- Infobulle d'un objet du sac : vrai si une ligne contient le mot (memorise par objet)
local tipHit = {}
local scanTip
local function TooltipMentions(bag, slot, id, words)
  if tipHit[id] then return true end
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetBagItem then
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    for _, l in ipairs(data and data.lines or {}) do lines[#lines + 1] = l.leftText end
  else
    scanTip = scanTip or CreateFrame("GameTooltip", "AishCoreCampfireScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetBagItem(bag, slot)
    for i = 1, scanTip:NumLines() do
      local fs = _G["AishCoreCampfireScanTipTextLeft" .. i]
      lines[#lines + 1] = fs and fs:GetText()
    end
    scanTip:Hide()
  end
  -- Seuls les resultats positifs sont memorises : une infobulle pas encore chargee est relue au scan suivant
  for _, t in ipairs(lines) do
    if Plain(t) then
      local low = t:lower()
      for _, w in ipairs(words) do
        if low:find(w, 1, true) then tipHit[id] = true; return true end
      end
    end
  end
  return false
end

-- Objets de camp dans les sacs : objets dont l'infobulle parle de feu de camp, dont le nom est celui d'un objet de
-- FEATURES, ou dont le sort d'utilisation en pose un. Les feux de camp eux-memes sont ecartes (un feu est deja la).
-- Une entree par objet. diag : liste des objets retenus ou ecartes, pour /aishcamp.
local placeSpell
-- Objets de camp connus par leur ID (reconnus meme si leur infobulle n'est pas encore chargee)
local CAMP_ITEMS = {
  [279962] = true,   -- Bougie d'encens
}
local function CampItems(diag)
  local CC = C_Container
  local NumSlots = CC and CC.GetContainerNumSlots or GetContainerNumSlots
  local ItemID = CC and CC.GetContainerItemID or GetContainerItemID
  local ItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  local Count = (C_Item and C_Item.GetItemCount) or GetItemCount
  local Icon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if not (NumSlots and ItemID) then
    if diag then diag[#diag + 1] = "API des sacs absente" end
    return {}
  end
  local words = CampWords()
  local fires = {}
  for _, id in ipairs(CAMPFIRE_SPELLS) do fires[id] = true end
  if not placeSpell then
    placeSpell = {}
    for i, f in ipairs(FEATURES) do
      placeSpell[f.place] = i
      for _, id in ipairs(f.alt or {}) do placeSpell[id] = i end
    end
  end
  local list, done = {}, {}
  local scanned = 0
  -- Sacs equipes, sac de composants compris (Forever : NUM_TOTAL_EQUIPPED_BAG_SLOTS, cf. MissingBuffs)
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, (NumSlots(bag) or 0) do
      local id = ItemID(bag, slot)
      -- Recettes ecartees : leur infobulle reprend celle de l'objet fabrique (nourriture, objet de camp...)
      local classID = id and C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(id))
      if classID == ((Enum.ItemClass and Enum.ItemClass.Recipe) or 9) then id = nil end
      if id and not done[id] then
        scanned = scanned + 1
        local sname, sid
        if ItemSpell then
          local ok, a, b = pcall(ItemSpell, id)
          if ok then sname, sid = a, b end
        end
        local fi = (sid and placeSpell[sid]) or (CAMP_ITEMS[id] and #FEATURES + 1)
        if not fi and Plain(sname) then
          local low = sname:lower()
          for spell, i in pairs(placeSpell) do
            if LowName(spell) == low then fi = i; break end
          end
        end
        local iname = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
        if not fi and Plain(iname) and #iname >= 6 then fi = MatchFeature(iname) end
        local isFire = (sid and fires[sid]) or (Plain(iname) and IsCampfireName(iname))
        local mention = not fi and not isFire and TooltipMentions(bag, slot, id, words)
        if mention then fi = #FEATURES + 1 end   -- objet de camp hors FEATURES : apres les autres
        if diag and (fi or isFire) then
          diag[#diag + 1] = string.format("%s (%d) sort=%s/%s %s", tostring(iname), id, tostring(sname), tostring(sid),
            isFire and "feu : ecarte" or (mention and "infobulle" or "objet connu"))
        end
        if fi and not isFire then
          done[id] = true
          list[#list + 1] = { id = id, bag = bag, slot = slot, fi = fi,
            count = Count and Count(id) or 1, icon = Icon and Icon(id) }
        end
      end
    end
  end
  table.sort(list, function(a, b) if a.fi ~= b.fi then return a.fi < b.fi end return a.id < b.id end)
  if diag then diag[#diag + 1] = "objets lus dans les sacs : " .. scanned end
  return list
end

-- Apercu du GUI : objets de camp fictifs (icone et nom du sort de pose), sans action
local function PreviewItems()
  local list = {}
  for _, i in ipairs({ 1, 2, 4, 5, 7, 9 }) do
    local f = FEATURES[i]
    list[#list + 1] = { icon = SpellIcon(f.place), name = SpellName(f.place), count = (i % 3) + 1 }
  end
  return list
end

local function CreatePanels()
  if panels[1] or InCombatLockdown() then return end
  -- Calque des lumieres de survol : au-dessus des panneaux, sous le losange
  local lights = CreateFrame("Frame", nil, hud)
  hud._lights = lights
  lights:SetAllPoints()
  lights:SetFrameLevel(math.max(1, hud:GetFrameLevel() - 1))
  for k in ipairs(PANELS) do
    local p = CreateFrame("Button", "AishCoreCampfireProf" .. k, UIParent, "SecureActionButtonTemplate")
    p:RegisterForClicks("AnyDown", "AnyUp")
    p:SetFrameStrata("MEDIUM")
    p:SetFrameLevel(math.max(1, hud:GetFrameLevel() - 2))
    p.glow = GlowTex(p, GLOW_SQUARE, "BACKGROUND", 0.45)
    p.glow:SetRotation(math.pi / 4)
    p.bg = p:CreateTexture(nil, "BORDER")
    p.bg:SetPoint("CENTER")
    p.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    p.bg:SetRotation(math.pi / 4)
    p.icon = MaskedIcon(p, 20)
    p.light = lights:CreateTexture(nil, "ARTWORK")
    p.light:SetTexture(GLOW_ROUND)
    p.light:SetBlendMode("ADD")
    p.light:SetVertexColor(1, 0.78, 0.38, 1)
    p.light:SetAlpha(0)
    p.light._ga = 0.9
    p.e, p.from = 0, 0
    -- Metier non appris : inactif (ni halo ni lumiere, infobulle grisee)
    p:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not self._known then
        GameTooltip:SetText(self._name or "", 0.6, 0.6, 0.6)
        GameTooltip:AddLine(ns.L["CAMPFIRE_PROF_UNKNOWN"], 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
        return
      end
      SetGlow(self.glow, true)
      SetGlow(self.light, true)
      GameTooltip:SetText(self._name or "", 1, 1, 1)
      GameTooltip:AddLine(ns.L["CAMPFIRE_PROF_TT"], 0.85, 0.85, 0.85, true)
      GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function(self)
      SetGlow(self.glow, false)
      SetGlow(self.light, false)
      GameTooltip:Hide()
    end)
    p:Hide()
    panels[k] = p
  end
  for k = 1, MAX_ITEMS do
    local s = CreateFrame("Button", "AishCoreCampfireItem" .. k, UIParent, "SecureActionButtonTemplate")
    s:RegisterForClicks("AnyDown", "AnyUp")
    s:SetFrameStrata("MEDIUM")
    s:SetFrameLevel(math.max(1, hud:GetFrameLevel() - 1))
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetPoint("TOPLEFT", -1, 1)
    s.bg:SetPoint("BOTTOMRIGHT", 1, -1)
    s.bg:SetColorTexture(0, 0, 0, 0.9)
    s.icon = s:CreateTexture(nil, "BORDER")   -- sous l'anneau SLUG des stacks (ARTWORK), lui-meme sous le nombre (OVERLAY)
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.count = s:CreateFontString(nil, "OVERLAY")
    s.count:SetFont(LABEL_FONT, 10, "OUTLINE")
    s.count:SetPoint("BOTTOMRIGHT", -1, 2)
    s.countRing = ns.CreateSlugRing and ns.CreateSlugRing(s, s.count, "ARTWORK")
    Outline(s.count, s.countRing, LABEL_FONT, 10, "OUTLINE")
    s.glow = GlowTex(s, GLOW_SQUARE, "OVERLAY", 0.9)
    s:SetScript("OnEnter", function(self)
      SetGlow(self.glow, true)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      if self._bag then GameTooltip:SetBagItem(self._bag, self._slot)
      elseif self._ph then GameTooltip:SetText(self._ph, 1, 1, 1) end   -- objet fictif de l'apercu
      GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function(self)
      SetGlow(self.glow, false)
      GameTooltip:Hide()
    end)
    s:Hide()
    slots[k] = s
  end
end

-- Barre d'objets (side -1 : a gauche, 1 : a droite) : fond grunge et chevron ocre pres de la pointe du losange
local function Bar(side)
  local b = bars[side]
  if b then return b end
  b = CreateFrame("Frame", nil, hud)
  b:SetSize(1, 1)
  b:SetFrameLevel(math.max(1, hud:GetFrameLevel() - 3))
  b.bgf = CreateFrame("Frame", nil, b)
  b.bgf:SetSize(1, 1)
  b.bgf:SetFrameLevel(b:GetFrameLevel())
  b.chf = CreateFrame("Frame", nil, b)   -- chevron au-dessus du fond
  b.chf:SetAllPoints()
  b.chf:SetFrameLevel(b:GetFrameLevel() + 2)
  b.bg = b.bgf:CreateTexture(nil, "BACKGROUND")
  b.bg:SetTexture(GRUNGE[side < 0 and 1 or 2])
  b.bg:SetAlpha(0.85)
  -- Chevron turquoise teinte en ocre : desature puis colore, double en ADD pour garder son eclat
  b.chev = {}
  for i, mode in ipairs({ "BLEND", "ADD" }) do
    local t = b.chf:CreateTexture(nil, "ARTWORK", nil, i)
    t:SetTexture(CHEVRON)
    t:SetDesaturated(true)
    t:SetVertexColor(OCRE[1], OCRE[2], OCRE[3], 1)
    t:SetBlendMode(mode)
    t:SetRotation(side < 0 and math.pi / 2 or -math.pi / 2)   -- pointe vers l'exterieur
    b.chev[i] = t
  end
  b._side = side
  b:Hide()
  bars[side] = b
  return b
end

local function SetupPanels()
  local R, r = PanelGeometry()
  local side = r * SQRT2
  for k, p in ipairs(panels) do
    local def = PANELS[k]
    local name, icon, rank = ProfInfo(def.key)
    if name and (tonumber(rank) or 1) <= 0 then name, icon = nil, nil end   -- ligne de metier sans rang : pas appris
    p._name, p._known = name or ns.L[def.name], name ~= nil
    p:SetSize(r * 2, r * 2)
    p:SetHitRectInsets(r * 0.3, r * 0.3, r * 0.3, r * 0.3)
    p.bg:SetSize(side, side)
    p.glow:SetSize(side * 1.9, side * 1.9)
    -- Lumiere : ovale chaud a cheval sur le bord du losange, du cote du panneau, sous le losange
    local dist = def.low and R * 0.95 or (R / SQRT2 + r * 0.2)
    p.light:ClearAllPoints()
    p.light:SetPoint("CENTER", hud, "CENTER", math.cos(def.ang) * dist, math.sin(def.ang) * dist)
    p.light:SetSize(side * 1.7, r * 1.5)
    p.light:SetRotation(def.ang - math.pi / 2)
    p.icon:SetSize(r * 0.95, r * 0.95)
    -- Non appris : icone en noir et blanc, assombrie
    p.icon:SetTexture(icon or def.icon)
    p.icon:SetDesaturated(not name)
    if p.icon.SetDesaturation then p.icon:SetDesaturation(name and 0 or 1) end
    p.icon:SetVertexColor(name and 1 or 0.6, name and 1 or 0.6, name and 1 or 0.6)
    p.icon:SetAlpha(name and 1 or 0.5)
    if not name then glows[p.glow], glows[p.light] = nil, nil; p.glow:SetAlpha(0); p.light:SetAlpha(0) end
    p:SetAttribute("type", name and "macro" or nil)
    p:SetAttribute("macrotext", name and ("/run AishCoreMenuBar_Profession(" .. def.arg .. ")") or nil)
  end
end

-- Cases d'objets : la 1re moitie a gauche, le reste a droite, de la pointe du losange vers l'exterieur.
-- s._x : distance du centre de la case au centre du HUD.
local function SetupItems()
  if InCombatLockdown() or not slots[1] then return end
  local items = hud._host and PreviewItems() or CampItems()
  local n = math.min(#items, MAX_ITEMS)
  local R, SW, SH = hud._r or 35, itemW, itemH
  -- Ecart entre les cases et contour (epaisseur, couleur) reglables
  local c = Cfg()
  local gap, bd = c.itemGap or 4, c.itemBorder or 1
  local bc = c.itemBorderColor or ITEM_BORDER_RGB
  local C = math.max(12, math.floor(SH * 0.55 + 0.5))  -- chevron
  -- Icone non carree : rognee pour garder ses proportions (coins de 8 % ecartes comme avant)
  local u0, u1, v0, v1 = 0.08, 0.92, 0.08, 0.92
  if SW > SH then local d = 0.84 * (1 - SH / SW) / 2; v0, v1 = v0 + d, v1 - d
  elseif SH > SW then local d = 0.84 * (1 - SW / SH) / 2; u0, u1 = u0 + d, u1 - d end
  -- Nombre d'objets : point d'ancrage dans la case et decalage
  local cp = c.itemCountPoint or "BOTTOMRIGHT"
  local cx, cy = c.itemCountX or -1, c.itemCountY or 2
  local x0 = R + C + 6                                 -- bord interieur d'une barre
  local nL = math.ceil(n / 2)
  for k, s in ipairs(slots) do
    local it = k <= n and items[k]
    if it then
      local side = k <= nL and -1 or 1
      local j = side < 0 and (nL - k) or (k - nL - 1)   -- 0 : case la plus proche du losange
      s._side, s._x, s._bag, s._slot = side, x0 + 6 + SW / 2 + j * (SW + gap), it.bag, it.slot
      s:SetSize(SW, SH)
      s.icon:SetTexCoord(u0, u1, v0, v1)
      s.count:ClearAllPoints()
      s.count:SetPoint(cp, s, cp, cx, cy)
      s.bg:ClearAllPoints()
      s.bg:SetPoint("TOPLEFT", -bd, bd)
      s.bg:SetPoint("BOTTOMRIGHT", bd, -bd)
      s.bg:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 1)
      s.bg:SetShown(bd > 0)
      -- Nombre d'objets (stack) : police, taille, contour, couleur
      Outline(s.count, s.countRing, c.itemCountFont or LABEL_FONT, c.itemCountSize or 10, c.itemCountOutline or "OUTLINE")
      local cc = c.itemCountColor or SPARK_RGB
      s.count:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
      s.glow:SetSize(SW * 1.75, SH * 1.75)
      s.icon:SetTexture(it.icon or 134400)
      s.count:SetText((it.count or 1) > 1 and it.count or "")
      s._ph = it.name
      s:SetAttribute("type", it.bag and "item" or nil)
      s:SetAttribute("item", it.bag and (it.bag .. " " .. it.slot) or nil)
      if panelOpen then s:Show() end
    else
      s._side, s._bag, s._slot, s._ph = nil, nil, nil, nil
      s:SetAttribute("type", nil)
      s:SetAttribute("item", nil)
      s:Hide()
    end
  end
  for _, side in ipairs({ -1, 1 }) do
    local b = Bar(side)
    local m = side < 0 and nL or (n - nL)
    if m > 0 then
      local w, h = 12 + m * SW + (m - 1) * gap, SH + 16
      b.bgf:ClearAllPoints()
      b.bgf:SetPoint("CENTER", b, "CENTER", side * (x0 + w / 2), 0)
      FitGrunge(b.bg, w, h)
      for _, t in ipairs(b.chev) do
        t:SetSize(C, C)
        t:ClearAllPoints()
        t:SetPoint("CENTER", b, "CENTER", side * (R + C / 2 + 3), 0)
      end
      if panelOpen then b:Show() end
    else
      b:Hide()
    end
  end
end

local function ClosePanelsNow()
  if InCombatLockdown() then return end
  panelOpen = false
  barE, barFrom = 0, 0
  for _, p in ipairs(panels) do p.e, p.from = 0, 0; p:Hide() end
  for _, s in ipairs(slots) do s:Hide() end
  for _, b in pairs(bars) do b:Hide() end
  if hint then glows[hint] = nil; hint:SetAlpha(1) end
  if hud then hud._panels = nil end
end

function Campfire.TogglePanels()
  if InCombatLockdown() or not hud then return end
  CreatePanels()
  if not panels[1] then return end
  -- Le cadre d'apercu coupe ses enfants et les dessine avec lui : des panneaux restes enfants d'UIParent passaient
  -- toujours devant le HUD, quel que soit leur niveau. Ils rejoignent donc le cadre le temps de l'apercu.
  local strata = hud._host and "FULLSCREEN" or "MEDIUM"
  local parent = hud._host or UIParent
  -- Niveaux reposes a chaque ouverture, relatifs au HUD (deplace dans le cadre du GUI, ses niveaux ont pu changer) :
  -- barres d'objets < panneaux < lumieres et cases < HUD < losange
  local base = hud:GetFrameLevel()
  hud.core:SetFrameLevel(base + 1)
  if hud._lights then hud._lights:SetFrameLevel(math.max(1, base - 1)) end
  for _, p in ipairs(panels) do p:SetParent(parent); p:SetScale(1); p:SetFrameStrata(strata); p:SetFrameLevel(math.max(1, base - 2)) end
  for _, s in ipairs(slots) do s:SetParent(parent); s:SetScale(1); s:SetFrameStrata(strata); s:SetFrameLevel(math.max(1, base - 1)) end
  for _, b in pairs(bars) do b:SetFrameLevel(math.max(1, base - 3)) end
  panelOpen = not panelOpen
  panelT0 = GetTime()
  barFrom = barE
  if panelOpen then SetupPanels(); SetupItems() end
  for _, p in ipairs(panels) do
    p.from = p.e
    p:Show()
  end
  if panelOpen then
    for _, s in ipairs(slots) do if s._side then s:Show() end end
    for _, b in pairs(bars) do
      local any = false
      for _, s in ipairs(slots) do if s._side == b._side then any = true end end
      b:SetShown(any)
    end
  end
  glows[hint] = nil
  hint:SetAlpha(panelOpen and 0 or 1)
  hud._panels = panelOpen or nil
  if panelOpen then
    glows[hud.help], glows[hud.hintShadow] = nil, nil
    hud.help:SetAlpha(0); hud.hintShadow:SetAlpha(0)
  end
  -- Les orbes s'ecartent pour passer au-dessus des panneaux ; au repli, elles attendent que ceux-ci soient rentres
  local open = panelOpen
  local function Relayout()
    if panelOpen == open and #curList > 0 and fx.phase ~= "gather" then LayoutOrbs(curList) end
  end
  if open then Relayout() else C_Timer.After(0.3, Relayout) end
  WakeDriver()
end

-- ── Apparition / disparition du HUD ─────────────────────────────────────────
local FADE_IN, FADE_OUT, FADE_RISE = 1.1, 1.0, 18   -- lent : c'est une halte

local ResetFx

local function ShowHud()
  if hud:IsShown() and not hud._fadeOut then return end
  if not hud:IsShown() then
    hud:SetAlpha(0)
    hud:SetScale(0.82)
    hud._dy = -FADE_RISE
    Place()
    hud:Show()
  end
  hud._fadeOut = nil
  hud._fade = { from = hud:GetAlpha(), to = 1, t0 = GetTime(), dur = FADE_IN }
  WakeDriver()
end

local function EndHide()
  hud._fade, hud._fadeOut = nil, nil
  StopDiamond(true)
  ResetFx()
  hud:Hide()
  hud:SetAlpha(1)
  hud:SetScale(1)
  hud._dy = 0
  hud._hov, hud._hovT = 0, 0
  hud.core:SetScale(1)
  glows[hud.halo] = nil
  hud.halo:SetAlpha(0)
  Place()
  UpdateDeco()
end

-- instant : entree en combat
local function HideHud(instant)
  if instant or not hud:IsShown() then EndHide(); return end
  if hud._fadeOut then return end
  ClosePanelsNow()
  hud._fadeOut = true
  hud._fade = { from = hud:GetAlpha(), to = 0, t0 = GetTime(), dur = FADE_OUT }
  WakeDriver()
end

-- ── Boucle d'animation ──────────────────────────────────────────────────────
OnDriver = function(self, dt)
  if not hud then self:Hide(); return end
  local now = GetTime()
  local R = hud._r or 35
  local busy = false

  -- Fondu du HUD : monte en apparaissant, redescend en disparaissant
  local fd = hud._fade
  if fd then
    busy = true
    local u = Clamp((now - fd.t0) / fd.dur)
    local appear = fd.to > fd.from
    local e = appear and EaseOut(u) or EaseIn(u)
    hud:SetAlpha(fd.from + (fd.to - fd.from) * e)
    -- Zoom : 0.82 -> 1 avec un leger depassement en apparaissant, 1 -> 0.88 en disparaissant
    local sc = appear and (0.82 + 0.18 * EaseBack(u)) or (1 - 0.12 * e)
    hud:SetScale(math.max(0.05, sc))
    hud._dy = appear and -FADE_RISE * (1 - e) or -FADE_RISE * 0.7 * e
    if not hud._moving then Place() end
    if u >= 1 then
      if fd.to == 0 then EndHide() else hud._fade, hud._dy = nil, 0; hud:SetScale(1); Place() end
    end
  end

  -- Survol du losange : leger zoom (quelques pixels)
  local ht, hv = hud._hovT or 0, hud._hov or 0
  if hv ~= ht then
    hv = hv + (ht - hv) * math.min(1, dt * 10)
    if math.abs(hv - ht) < 0.01 then hv = ht else busy = true end
    hud._hov = hv
    hud.core:SetScale(1 + hv * HOVER_PX / (hud._size or 70))
  end

  -- Barre de la minute qui se vide
  if drain then
    busy = true
    local u = Clamp((now - drain.t0) / BAR_DRAIN)
    SetDiamondProgress(drain.from * (1 - EaseInOut(u)))
    if u >= 1 then drain = nil; SetDiamondProgress(0) end
  end

  -- Minute complete : la barre vire a l'or et brille (leger pulse), puis s'efface doucement
  if doneFx then
    busy = true
    local t = now - doneFx.t0
    local e = EaseOut(Clamp(t / DONE_IN))
    local col = Cfg().barColor or BAR_RGB
    local r, g, b = col[1] + (DONE_RGB[1] - col[1]) * e, col[2] + (DONE_RGB[2] - col[2]) * e, col[3] + (DONE_RGB[3] - col[3]) * e
    local keep = 1 - EaseInOut(Clamp((t - DONE_HOLD) / DONE_OUT))
    for _, f in ipairs(hud.fill) do
      f:SetVertexColor(r, g, b, col[4] or 1)
      f:SetAlpha(keep)
    end
    hud.doneGlow:SetAlpha(e * keep * (0.75 + 0.25 * math.sin(t * 7)))
    if keep <= 0 then doneFx = nil; SetDiamondProgress(0); RestoreBar() end
  end

  -- Minuteur : fondu et glissement (descend en apparaissant, remonte en s'effacant)
  local tf = hud._tf
  if tf then
    busy = true
    local appear = tf.to > tf.from
    local u = Clamp((now - tf.t0) / (appear and TIMER_IN or TIMER_OUT))
    local e = appear and EaseOut(u) or EaseIn(u)
    SetTimerAlpha(tf.from + (tf.to - tf.from) * e)
    PlaceTimer(appear and 6 * (1 - e) or 6 * e)
    if u >= 1 then
      hud._tf = nil
      PlaceTimer(0)
      if tf.to == 0 then hud.timer:SetText("") end
    end
  end

  -- Halos de survol
  local gk = math.min(1, dt * 10)
  for g, want in pairs(glows) do
    local target = want * g._ga
    local a = g:GetAlpha()
    a = a + (target - a) * gk
    if math.abs(a - target) < 0.01 then a = target; glows[g] = nil else busy = true end
    g:SetAlpha(a)
  end

  for _, o in pairs(orbs) do
    if o:IsShown() then
      busy = true
      local x, y, s, a
      if fx.phase == "gather" and o.g0 then
        local u = Clamp((now - o.g0) / GATHER)
        local e = EaseInOut(u)
        x, y = o.gx * (1 - e), o.gy + (R - o.gy) * e
        s = 1 - 0.55 * e
        a = u < 0.7 and 1 or (1 - (u - 0.7) / 0.3)
        if u >= 1 then o.g0 = nil; o:Hide() end
      else
        local k = math.min(1, dt * 8)
        o.cx, o.cy = o.cx + (o.tx - o.cx) * k, o.cy + (o.ty - o.cy) * k
        o.popT = (o.popT or 1) + dt
        local u = Clamp(o.popT / ORB_POP)
        s, a = EaseBack(u), Clamp(u * 2)
        -- Grossit au survol
        o.h = o.h + ((o.hover and 1 or 0) - o.h) * math.min(1, dt * 12)
        s = s * (1 + 0.6 * o.h)
        -- Bulle : petit va-et-vient vertical, derive horizontale plus faible (attenues au survol)
        local amp = 1 - 0.7 * o.h
        x = o.cx + 1.5 * amp * math.sin(now * o.fx + o.px)
        y = o.cy + 3 * amp * math.sin(now * o.fy + o.py)
      end
      s = math.max(0.05, s)
      o:SetScale(s)
      o:ClearAllPoints()
      o:SetPoint("CENTER", hud, "CENTER", x / s, y / s)
      o:SetAlpha(a)
    end
  end

  -- Infobulle d'orbe : fondu et glissement vers l'exterieur
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
    local o, sl = tip.owner, 8 * (1 - e)
    if o and o:IsShown() then
      tip:ClearAllPoints()
      if tip.dir == "up" then
        tip:SetPoint("BOTTOM", o, "TOP", 0, (tip.gap or 8) - 2 - sl)
      elseif tip.dir == "left" then
        tip:SetPoint("RIGHT", o, "LEFT", -(tip.gap or 8) + sl, 0)
      else
        tip:SetPoint("LEFT", o, "RIGHT", (tip.gap or 8) - sl, 0)
      end
      tip:SetAlpha(e)
    else
      tip:Hide()
      tip.owner = nil
    end
  end

  -- Fusion au sommet : eclat qui grossit et s'efface
  if fx.flash0 then
    busy = true
    local u = (now - fx.flash0) / 0.5
    if u >= 1 then
      fx.flash0 = nil
      hud.flash:Hide()
    elseif u >= 0 then
      local e = EaseOut(u)
      hud.flash:ClearAllPoints()
      hud.flash:SetPoint("CENTER", hud, "CENTER", 0, R)
      hud.flash:SetSize(orbSize * (0.6 + 1.6 * e), orbSize * (0.6 + 1.6 * e))
      hud.flash:SetAlpha(0.9 * (1 - u))
      hud.flash:Show()
    end
  end

  if fx.phase == "gather" then
    busy = true
    if now >= fx.sum0 then StartSummary() end
  elseif fx.phase == "summary" then
    busy = true
    local out = Clamp((now - fx.sumEnd) / SUM_OUT)
    for _, l in ipairs(sumLines) do
      if l:IsShown() then
        local e = EaseOut(Clamp((now - l.t0) / SUM_IN))
        l:ClearAllPoints()
        l:SetPoint("LEFT", hud, "CENTER", fx.sumX + 36 * (1 - e), l.y)
        l:SetAlpha(e * (1 - out))
      end
    end
    -- Fond : fondu et leger zoom d'entree, comme le toast de niveau
    if sumBg and sumBg:IsShown() then
      local e = EaseOut(Clamp((now - fx.sumT0) / (SUM_IN + 0.1)))
      local s = 0.92 + 0.08 * e
      sumBg:SetScale(s)
      sumBg:ClearAllPoints()
      sumBg:SetPoint("CENTER", hud, "CENTER", (fx.sumOX or 0) / s, sumBg.y / s)
      sumBg:SetAlpha(e * (1 - out))
    end
    if out >= 1 then
      HideSummary(); fx.phase = nil; UpdateDeco()
      if hud._host then LayoutOrbs(SeenList())   -- apercu du GUI : les orbes reviennent
      else Campfire.Refresh() end                 -- feu toujours proche ? (cf. Refresh, HUD garde pendant le resume)
    end
  end

  -- Panneaux : sortent de sous le losange, chacun par son cote, en decale ; se replient dans l'ordre inverse.
  -- Barres d'objets : glissent depuis les pointes du losange apres les panneaux, rentrent en premier.
  if panels[1] and panels[1]:IsShown() and not InCombatLockdown() then
    busy = true
    -- Centre du HUD en unites d'UIParent ; ps : echelle des panneaux (1 hors apercu du GUI, cf. TogglePanels)
    local cx, cy = hud:GetCenter()
    if cx then local k = hud:GetEffectiveScale() / UIParent:GetEffectiveScale(); cx, cy = cx * k, cy * k end
    local ps = panels[1]:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local _, _, d, D = PanelGeometry()
    local n, done = #panels, true
    for k, p in ipairs(panels) do
      local delay = (panelOpen and (k - 1) or (n - k)) * 0.06
      local u = Clamp((now - panelT0 - delay) / (panelOpen and 0.34 or 0.26))
      if u < 1 then done = false end
      local target = panelOpen and 1 or 0
      p.e = p.from + (target - p.from) * (panelOpen and EaseBack(u) or EaseIn(u))
      local def = PANELS[k]
      local dist = def.low and D or d
      p:ClearAllPoints()
      if cx then
        p:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cx + math.cos(def.ang) * dist * p.e * ps) / ps,
          (cy + math.sin(def.ang) * dist * p.e * ps) / ps)
      end
      p:SetAlpha(Clamp(p.e * 1.6))
    end
    local u = Clamp((now - panelT0 - (panelOpen and 0.2 or 0)) / (panelOpen and 0.3 or 0.18))
    if u < 1 then done = false end
    barE = barFrom + ((panelOpen and 1 or 0) - barFrom) * (panelOpen and EaseOut(u) or EaseIn(u))
    local slide = 18 * (1 - barE)
    for _, b in pairs(bars) do
      if b:IsShown() then
        b:ClearAllPoints()
        b:SetPoint("CENTER", hud, "CENTER", -b._side * slide, 0)
        b:SetAlpha(barE)
      end
    end
    for _, s in ipairs(slots) do
      if s:IsShown() and s._side and cx then
        s:ClearAllPoints()
        s:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (cx + s._side * (s._x - slide) * ps) / ps, cy / ps)
        s:SetAlpha(barE)
      end
    end
    if done and not panelOpen then ClosePanelsNow() end
  end

  if not busy then self:Hide() end
end

local laidSeen   -- nombre de bonus reperes deja places en orbes (nil : a refaire)
local decoState  -- dernier etat envoye a SpellEffects
local previewing -- apercu depuis le GUI (Animations 3D > Camping HUD) : Refresh laisse la main

-- "shown" : HUD affiche ; "sitting" : minute assise ; "buffs" : rassemblement et resume des gains ; nil : masque
UpdateDeco = function()
  local st
  if hud and hud:IsShown() and not hud._fadeOut then
    if fx.phase then st = "buffs"
    elseif diaSec ~= false then st = "sitting"
    else st = "shown" end
  end
  if st == decoState then return end
  decoState = st
  local SE = ns.Modules.SpellEffects
  if SE and SE.SetCampfireState then SE.SetCampfireState(st) end
end

ResetFx = function()
  laidSeen = nil
  curList = {}
  for _, o in pairs(orbs) do o:Hide(); o.hover = nil; o.h = 0; o.glow:SetAlpha(0) end
  if tip then tip:Hide(); tip.owner = nil end
  HideSummary()
  fx.phase, fx.flash0 = nil, nil
  if hud and hud.flash then hud.flash:Hide() end
  ClosePanelsNow()
end

local function Resize(size)
  LayoutDiamond(size)
  SetDiamondProgress(hud._p or 0)
  laidSeen = nil
end

local sitting, sitExp = false, 0

function Campfire.Refresh()
  if not hud or previewing or GetTime() < testUntil then return end
  if InCombatLockdown() and not hud:IsShown() then return end
  local c = Cfg()
  local near = c.enabled ~= false and NearCampfire()
  -- Fin de la minute : "Feu de camp proche" peut manquer un instant quand "Feu de camp accueillant" tombe ; le HUD
  -- (et ses panneaux) reste le temps du rassemblement et du resume, puis Refresh est relance
  if not near and c.enabled ~= false and fx.phase and hud:IsShown() and not InCombatLockdown() then
    UpdateDeco()
    return
  end
  if not near or InCombatLockdown() then
    if not near and next(seen) then wipe(seen) end
    if (hud:IsShown() and not hud._fadeOut) or sitting then
      sitting = false
      HideHud(InCombatLockdown())
    end
    UpdateDeco()
    return
  end

  local size = c.size or 70
  if hud._size ~= size then Resize(size) end
  ShowHud()

  local welcome = WelcomeAura()
  if welcome then
    -- Assis : le contour suit la minute restante, les bonus reperes flottent autour
    local dur, exp = welcome.duration, welcome.expirationTime
    if type(dur) == "number" and type(exp) == "number" and dur > 0 then
      RunDiamond(exp - dur, dur)
      sitting, sitExp = true, exp
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    if n ~= laidSeen then
      laidSeen = n
      local list = SeenList()
      LayoutOrbs(list)
      hint:SetText(#list == 0 and ns.L["CAMPFIRE_HINT_NONE"] or "")
    end
  else
    -- Minute terminee : rassemblement puis resume ; levee avant la fin : les panneaux se replient
    local complete
    if sitting then
      sitting = false
      complete = GetTime() >= sitExp - 1.5
      if complete then StartGather()
      elseif panelOpen and not InCombatLockdown() then Campfire.TogglePanels() end
    end
    StopDiamond(false, complete)
    if laidSeen and not fx.phase then LayoutOrbs({}) end
    laidSeen = nil
    hint:SetText(HasAura(COOLDOWN_AURA) and ns.L["CAMPFIRE_HINT_COOLDOWN"] or "")
  end
  UpdateDeco()
end

-- Apercu epingle de la page Camping (cadre fourni par le GUI) : le vrai HUD y est deplace, interactif au survol
-- (halo, orbes et leurs infobulles), barre de la minute en boucle de 10 s sans pause, gain des bonus a la demande
-- (Campfire.PreviewGain). Les objets reperes du joueur sont mis de cote le temps de l'apercu.
local PREVIEW_LOOP = 10
local savedSeen, stage
local previewCount = 4   -- bonus affiches dans l'apercu (1 a 10, cf. Campfire.SetPreviewCount)

-- Bonus fictifs de l'apercu : les previewCount premiers (une seule banniere, index 10)
local function PreviewSeen()
  wipe(seen)
  for i = 1, previewCount do seen[i] = true end
end

-- Strate du HUD et de tous ses enfants (orbes, resume, modeles 3D...)
local function SetStrataDeep(f, s)
  f:SetFrameStrata(s)
  for _, c in ipairs({ f:GetChildren() }) do SetStrataDeep(c, s) end
end

local function RestoreSeen()
  if not savedSeen then return end
  wipe(seen)
  for k in pairs(savedSeen) do seen[k] = true end
  savedSeen = nil
end

-- Echelle du cadre d'apercu : exactement celle du jeu (UIParent), quelle que soit l'echelle de la fenetre du GUI,
-- pour juger les reglages tels qu'ils seront en jeu. Ce qui depasse du cadre est coupe.
local function FitStage()
  if not (stage and hud._host) then return end
  local hostScale = stage:GetParent():GetEffectiveScale()
  stage:SetScale(hostScale > 0 and UIParent:GetEffectiveScale() / hostScale or 1)
  hud._hostDY = -45
  Place()
end

function Campfire.SetHostPreview(host)
  if not ns.IsModuleAvailable("campfire") then return end
  if not host then
    if not (hud and hud._host) then return end
    previewing = false
    EndHide()
    hud._host, hud._hostDY = nil, nil
    hud:SetParent(UIParent)
    SetStrataDeep(hud, "MEDIUM")
    hud:SetFrameLevel(10)
    RestoreSeen()
    Place()
    Campfire.Refresh()
    return
  end
  Create()
  RestoreSeen()
  previewing = true
  EndHide()
  if not stage then stage = CreateFrame("Frame", nil, host) end
  stage:SetParent(host)
  stage:ClearAllPoints()
  stage:SetAllPoints(host)
  stage:Show()
  hud._host = stage
  -- Strate au-dessus de la fenetre du GUI (les modeles 3D suivent celle du HUD, cf. SpellEffects)
  hud:SetParent(stage)
  SetStrataDeep(hud, "FULLSCREEN")
  hud:SetFrameLevel(10)
  Resize(Cfg().size or 70)
  FitStage()
  savedSeen = {}
  for k in pairs(seen) do savedSeen[k] = true end
  wipe(seen)
  PreviewSeen()
  ShowHud()
  hint:SetText("")
  RunDiamond(GetTime(), PREVIEW_LOOP)
  diaLoop = true
  LayoutOrbs(SeenList())
  UpdateDeco()
end

-- Boutons - / + de l'apercu : nombre de bonus affiches (1 a 10) ; renvoie le nombre retenu
function Campfire.SetPreviewCount(n)
  previewCount = math.max(1, math.min(10, math.floor(tonumber(n) or previewCount)))
  if hud and hud._host then
    PreviewSeen()
    if fx.phase ~= "gather" and fx.phase ~= "summary" then LayoutOrbs(SeenList()) end
  end
  return previewCount
end

function Campfire.GetPreviewCount() return previewCount end

-- Bouton de l'apercu : fin de la minute assise (rassemblement des orbes puis resume des gains)
function Campfire.PreviewGain()
  if not (hud and hud._host) or fx.phase then return end
  StartGather()
  UpdateDeco()
end

-- Apercu depuis Animations 3D > Camping HUD : HUD affiche dans l'etat de l'entree selectionnee
function Campfire.SetPreview(on, state)
  if not ns.IsModuleAvailable("campfire") or InCombatLockdown() then return end
  if hud and hud._host then return end   -- l'apercu epingle de la page Camping garde la main
  if not on then
    if not previewing then return end
    previewing = false
    EndHide()
    Campfire.Refresh()
    return
  end
  Create()
  previewing = true
  EndHide()
  Place()
  Resize(Cfg().size or 70)
  ShowHud()
  hint:SetText("")
  if state == "sitting" then
    RunDiamond(GetTime(), 60)
  elseif state == "buffs" then
    StartSummary({ FEATURES[1], FEATURES[2], FEATURES[5] })
    fx.sumEnd = GetTime() + 3600
  end
end

-- Losange de deplacement : affiche en jeu tant que le panneau d'options est ouvert et la position deverrouillee
-- (le vrai HUD n'apparait que pres d'un feu, ou dans l'apercu de la page Camping)
local mover
local function PlaceMover()
  local c = Cfg()
  local size = c.size or 70
  mover:SetSize(size, size)
  mover.tex:SetSize(size * FRAME_FIT, size * FRAME_FIT)
  mover:ClearAllPoints()
  mover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UIParent:GetWidth() * (c.anchorPctX or 0.5),
    UIParent:GetHeight() * (c.anchorPctY or 0.62))
end

function Campfire.UpdateMover()
  if not ns.IsModuleAvailable("campfire") then return end
  local panel = _G["AishCoreSettingsPanel"]
  local c = Cfg()
  local want = panel and panel:IsShown() and c.enabled ~= false and not c.locked
  if not want then if mover then mover:Hide() end; return end
  if not mover then
    mover = CreateFrame("Frame", "AishCoreCampfireMover", UIParent)
    mover:SetFrameStrata("HIGH")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.tex = mover:CreateTexture(nil, "ARTWORK")
    mover.tex:SetPoint("CENTER")
    mover.tex:SetTexture(FRAME_TEX)
    mover.tex:SetAlpha(0.85)
    mover.glow = mover:CreateTexture(nil, "BACKGROUND")
    mover.glow:SetTexture(GLOW_SQUARE)
    mover.glow:SetBlendMode("ADD")
    mover.glow:SetVertexColor(GLOW_RGB[1], GLOW_RGB[2], GLOW_RGB[3], 1)
    mover.glow:SetPoint("CENTER")
    mover.glow:SetRotation(math.pi / 4)
    mover.glow:SetAlpha(0.35)
    mover.label = mover:CreateFontString(nil, "OVERLAY")
    mover.label:SetFont(LABEL_FONT, 11, "OUTLINE")
    mover.label:SetPoint("TOP", mover, "BOTTOM", 0, -4)
    mover.label:SetTextColor(1, 0.82, 0.5, 1)
    mover.label:SetText(ns.L["SETTINGS_SEC_CAMPFIRE_HUD"])
    mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mover:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local cx, cy = self:GetCenter()
      ns.DB.campfire = ns.DB.campfire or {}
      ns.DB.campfire.anchorPctX = cx / UIParent:GetWidth()
      ns.DB.campfire.anchorPctY = cy / UIParent:GetHeight()
      PlaceMover()
      if hud and not hud._host then Place() end
    end)
  end
  local R = (Cfg().size or 70) / 2
  mover.glow:SetSize(R * 2.6, R * 2.6)
  PlaceMover()
  mover:Show()
end

function Campfire.ResetPosition()
  if ns.DB.campfire then ns.DB.campfire.anchorPctX, ns.DB.campfire.anchorPctY = nil, nil end
  if hud then Place() end
  if mover and mover:IsShown() then PlaceMover() end
end

function Campfire.ApplySettings()
  if not ns.IsModuleAvailable("campfire") then return end
  Create()
  -- Reglages en direct : losange, orbes, resume et panneaux refaits a la nouvelle taille / police
  Resize(Cfg().size or 70)
  if #curList > 0 and fx.phase ~= "gather" then LayoutOrbs(curList) end
  if fx.phase == "summary" then
    local keep = fx.sumEnd
    StartSummary(fx.sumList)
    if keep and fx.sumEnd and keep > fx.sumEnd then fx.sumEnd = keep end   -- apercu "buffs" : resume fige
  end
  if panelOpen and not InCombatLockdown() then SetupPanels(); SetupItems() end
  if hud._host then FitStage() else Place() end
  local SE = ns.Modules.SpellEffects
  if SE and SE.RefreshCampfireDeco then SE.RefreshCampfireDeco() end
  Campfire.UpdateMover()
  Campfire.Refresh()
end

-- Distance au camp retenu : verifiee chaque seconde tant qu'il y en a un
ns.NewTicker(1, function()
  if campPos and hud and not InCombatLockdown() and ns.IsModuleAvailable("campfire") then Campfire.Refresh() end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event)
  if not ns.IsModuleAvailable("campfire") then return end
  if event == "PLAYER_LOGIN" then
    Campfire.ApplySettings()
    if TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Object then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnObjectTooltip)
    end
    return
  end
  -- Objet pose ou recu : barres d'objets a jour tant que les panneaux sont deplies
  if event == "BAG_UPDATE_DELAYED" then
    if panelOpen and hud and not InCombatLockdown() then SetupItems(); WakeDriver() end
    return
  end
  -- Entree en combat : panneaux securises masques tant que c'est permis (le verrouillage suit cet evenement)
  -- Pas de feu de camp en combat : plus aucune lecture d'aura jusqu'a la sortie
  if event == "PLAYER_REGEN_DISABLED" then
    ev:UnregisterEvent("UNIT_AURA")
    testUntil = 0
    if hud then sitting = false; HideHud(true) end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then ev:RegisterUnitEvent("UNIT_AURA", "player") end
  Campfire.Refresh()
end)

-- /aishcamp : etat du module (a lancer pres d'un feu de camp)
SLASH_AISHCAMP1 = "/aishcamp"
SlashCmdList["AISHCAMP"] = function(msg)
  local P = "|cff33ff99[AishCore camp]|r "
  -- /aishcamp test [n] : demo sans feu de camp (losange de 12 s, n bonus fictifs (4 par defaut, 10 au plus),
  -- rassemblement puis resume)
  if msg and msg:lower():match("^%s*test") then
    if InCombatLockdown() then return end
    if not hud then Create() end
    Place()
    EndHide()
    Resize(Cfg().size or 70)
    ShowHud()
    hint:SetText("")
    local DEMO = 12
    testUntil = GetTime() + DEMO + SUM_HOLD + 4
    wipe(seen)
    local want = math.max(1, math.min(10, tonumber(msg:match("(%d+)")) or 4))
    local ids = want == 4 and { 1, 2, 5, 9 } or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
    for k = 1, want do seen[ids[k]] = true end
    RunDiamond(GetTime(), DEMO)
    UpdateDeco()
    LayoutOrbs(SeenList())
    C_Timer.After(DEMO, function()
      if hud and GetTime() < testUntil then StopDiamond(false, true); StartGather(); UpdateDeco() end
    end)
    C_Timer.After(DEMO + SUM_HOLD + 4.1, function() if hud then wipe(seen); Campfire.Refresh() end end)
    print(P .. "test : demo de " .. (DEMO + SUM_HOLD + 4) .. " s (clic droit : panneaux des metiers)")
    return
  end
  local function A(id)
    local a = HasAura(id)
    return a and ("oui (" .. tostring(a.name) .. ")") or "non"
  end
  print(P .. "module dispo=" .. tostring(ns.IsModuleAvailable("campfire")) .. " active=" .. tostring(Cfg().enabled ~= false)
    .. " HUD cree=" .. tostring(hud ~= nil) .. " affiche=" .. tostring(hud and hud:IsShown()) .. " combat=" .. tostring(InCombatLockdown()))
  print(P .. "aura Feu de camp proche=" .. A(NEARBY_AURA) .. " | accueillant=" .. A(WELCOME_AURAS[1]) .. "/" .. A(WELCOME_AURAS[2])
    .. " | recharge=" .. A(COOLDOWN_AURA) .. " | camp retenu=" .. tostring(campPos ~= nil) .. " | pres d'un feu=" .. tostring(NearCampfire()))
  print(P .. "dernier objet survole=" .. tostring(lastHover) .. " | feu reconnu=" .. tostring(lastHover and IsCampfireName(lastHover) or false))
  local diag = {}
  print(P .. "objets de camp dans les sacs=" .. #CampItems(diag) .. " | mots cherches : " .. table.concat(CampWords(), ", "))
  for _, l in ipairs(diag) do print(P .. "  " .. l) end
  -- Toutes les auras du joueur dont le nom parle de camp / feu (si l'ID differe sur ce client)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not a then break end
      if Plain(a.name) and (a.name:lower():find("camp") or a.name:lower():find("feu")) then
        print(P .. "  aura joueur : " .. a.name .. " (" .. tostring(a.spellId) .. ")")
      end
    end
  end
  if hud then
    local x, y = hud:GetCenter()
    print(P .. string.format("position %.0f, %.0f  taille %.0f  alpha %.2f", x or -1, y or -1, hud:GetWidth(), hud:GetEffectiveAlpha()))
  end
end

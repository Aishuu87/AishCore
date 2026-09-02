-- Modules/Skyriding.lua
-- Suivi natif de la vigueur et de la vitesse en vol dragon (Skyriding).
-- Cercle de vitesse, charges de vigueur, second souffle.
-- FX 3D : désactivés pour l'instant (phase ultérieure).
local addonName, ns = ...

local Skyriding = {}
ns.Modules = ns.Modules or {}
ns.Modules.Skyriding = Skyriding

---------------------------------------------------------------------------
-- CONSTANTES
---------------------------------------------------------------------------
local DR_POWERBAR_ID   = 631        -- Barre de puissance Skyriding
local MAX_SPEED        = 105.0      -- yd/s max pour remplir le cercle à 100 %
local SPEED_TEXT_FACTOR = 100 / 7   -- Conversion yd/s → move%

-- Sorts / buffs
local SURGE_FORWARD    = 372608     -- Accélération (charges de vigueur)
local ASCENT_SPELL     = 372610     -- Skyward Ascent (boost)
local THRILL_BUFF      = 377234     -- Thrill of the Skies
local SECOND_SOUFFLE   = 425782     -- Second Souffle / Aerial Halt

-- Durée du boost d'Ascension
local ASCENT_DURATION  = 3.0

-- Remplissage du cercle : 220° → 140° CW (280° total, ouverture en bas)
local ARC_START        = 220
local ARC_TOTAL        = 280

-- Fly charges : arrangement circulaire (convention math : 0°=droite, CCW)
local FLY_ROTATION     = 210        -- angle de départ du premier orbe
local FLY_STEP_ANGLE   = 24         -- espacement angulaire entre charges
local FLY_ORB_SIZE     = 19         -- taille d'une orbe

-- Animation slide des orbes extérieurs
local ORB_SLIDE_SPEED  = 9.0        -- vitesse de l'animation (units/s)
local ORB_SLIDE_SCALE  = 1.55       -- facteur départ (× plus loin du centre)

-- Second Souffle : arrangement horizontal
local SOUFFLE_SIZE     = 5
local SOUFFLE_SPACE    = 4
local SOUFFLE_Y_OFF    = -16.67

-- FileIDs des modèles 3D
local MODEL_CRAWTH     = 4520560    -- galeforce precast (orbes + souffle)

-- Textures
local TEX_CIRCLEFLAT   = "Interface\\AddOns\\AishuuMedia\\ElvUI\\circleflat"
local TEX_CIRCLE_SMOOTH = "Interface\\AddOns\\AishCore\\Media\\Skyriding\\Circle_Smooth"
local TEX_SQUARE_WHITE = "Interface\\AddOns\\AishCore\\Media\\Skyriding\\Square_FullWhite"
local FONT_MONTSERRAT_B = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-Bold.ttf"

-- Couleurs
local COL_BG            = { 0.0549, 0.0549, 0.0549, 1 }
local COL_SPEED_NORMAL  = { 0, 0.8824, 0.5373, 1 }          -- teal (buff actif)
local COL_SPEED_BOOST   = { 0, 1, 0.8118, 1 }               -- cyan (ascension)
local COL_SPEED_NOGLOW  = { 0.45, 0.45, 0.45, 1 }           -- gris (sans buff)
local COL_ASCENT        = { 0.5961, 0.9608, 0.8549, 1 }     -- mint
local COL_SPEEDCAP      = { 0.8824, 0.7490, 0.4784, 1 }
local COL_TXT_NORMAL    = { 0, 0.8824, 0.5373, 1 }          -- teal (buff actif)
local COL_TXT_BOOST     = { 0.2196, 0.7529, 1, 1 }          -- cyan (ascension)
local COL_TXT_NOGLOW    = { 0.55, 0.55, 0.55, 1 }           -- gris (sans buff)
local COL_TXT_SHADOW    = { 0, 0, 0, 0.4775 }
local COL_ORB_BASE      = { 0.4549, 0.4549, 0.4549, 1 }

-- Ratio orbe / bgSize (65 / 120 par défaut dans le WA)
local ORB_RADIUS_RATIO  = 65 / 120

---------------------------------------------------------------------------
-- ÉTAT INTERNE
---------------------------------------------------------------------------
local container         -- Frame racine
local ringAnchor        -- Frame d'ancrage du cercle (centre +20 y)

-- Couches : frame + CircularProgress
local bgFrame,     bgCP
local speedFrame,  speedCP
local mask1Frame,  mask1CP
local ascentFrame, ascentCP
local mask2Frame,  mask2CP
local speedCapLine
local speedText            -- FontString

-- Fly Charges (6 orbes)
local flyOrbs  = {}        -- [i] = { frame, texture, model }
local orbAnims = {}        -- [i] = { progress, target }  pour l'animation slide

-- Second Souffle (3 charges)
local souffleOrbs      = {}     -- [i] = model frame
local souffleDots      = {}     -- [i] = { frame, texture }  petits indicateurs
local souffleDotsAnchor = nil   -- frame ancre des points (repositionnable)

-- État
local isActive      = false
local hudVisible    = false  -- vrai quand notre HUD est effectivement affiché (debounce AnimShow/Hide)
local ascentStart   = 0
local isLayoutMode  = false
local previewActive = false  -- vrai quand le panneau de configuration est ouvert
local smoothSpeed   = 0
local activateTime  = 0      -- horodatage du dernier tick en vol (pour le délai de grâce hideAtLanding)
local wasAirborne   = false  -- devient true après le premier vrai décollage (speed>1), reset au démontage

---------------------------------------------------------------------------
-- DEBUG LOG (buffer circulaire — /aishdebug sky pour afficher)
---------------------------------------------------------------------------
local _dbgLog = {}
local function DbgLog(msg)
  local entry = string.format("[%.2f] %s", GetTime(), msg)
  _dbgLog[#_dbgLog + 1] = entry
  if #_dbgLog > 20 then table.remove(_dbgLog, 1) end
end

-- Animation d'apparition / disparition
local anim      = { progress = 0, target = 0, speed = 5.0 }
local animFrame = nil   -- frame dédié au ticker d'anim (créé dans Skyriding.Create)

-- Couleur de la monture (capturée au décollage depuis le dernier sort lancé)
local mountColorSlow   = nil   -- première couleur du dégradé (vitesse lente)
local mountColorBuffed = nil   -- deuxième couleur du dégradé (vitesse buffée)
local lastMountSpellId = nil

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function IsDragonriding()
  -- Vérification primaire : power bar ID
  if UnitPowerBarID("player") == DR_POWERBAR_ID then return true end
  -- Fallback : canGlide = true dès qu'on est sur une monture Skyriding
  -- (résistant aux hotfixes Blizzard qui cassent UnitPowerBarID)
  local _, canGlide = C_PlayerInfo.GetGlidingInfo()
  return canGlide == true
end

local function GetForwardSpeed()
  local _, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
  return forwardSpeed or 0
end

local function GetCfg()
  return ns.GetCfg("skyriding") or ns.Defaults.skyriding or {}
end

--- Si le canal le plus fort de la couleur est sous minBright, scale tous les
--- canaux pour l'y amener. Préserve la teinte/saturation, rehausse juste la valeur.
local function EnforceBrightness(c, minBright, targetBright)
  if not c then return c end
  local maxCh = math.max(c[1], c[2], c[3])
  if maxCh > 0 and maxCh < minBright then
    local s = (targetBright or minBright) / maxCh
    return { math.min(c[1]*s, 1), math.min(c[2]*s, 1), math.min(c[3]*s, 1), c[4] or 1 }
  end
  return c
end

--- Calcule un degré (slow, buffed) {r,g,b,a} depuis un spellId.
--- Retourne deux couleurs : première = gauche du dégradé, seconde = droite.
local function ComputeSpellGradient(spellId)
  if not spellId then return nil, nil end
  local SC_SOLID = {
    [2]  = { 1.00, 0.77, 0.24, 1 },  -- Holy
    [4]  = { 1.00, 0.33, 0.00, 1 },  -- Fire
    [8]  = { 0.30, 0.69, 0.31, 1 },  -- Nature
    [16] = { 0.46, 0.73, 0.99, 1 },  -- Frost
    [32] = { 0.61, 0.15, 0.69, 1 },  -- Shadow
    [64] = { 0.40, 0.23, 0.72, 1 },  -- Arcane
  }
  local gradient = ns.SpellGradients and ns.SpellGradients[spellId]
  if not gradient then
    local school = ns.SpellSchools and ns.SpellSchools[spellId]
    if school then
      for _, mask in ipairs({64, 32, 16, 8, 4, 2}) do
        if bit.band(school, mask) ~= 0 and SC_SOLID[mask] then
          local c = SC_SOLID[mask]
          return c, c  -- même couleur pour les deux
        end
      end
    end
    return nil, nil
  end
  -- gradient = "lhex:rhex" ou juste "hex"
  local lhex, rhex = strsplit(":", gradient)
  rhex = rhex and string.len(rhex) >= 6 and rhex or lhex
  local function hex2rgb(h)
    return { (tonumber(string.sub(h,1,2),16) or 0)/255,
             (tonumber(string.sub(h,3,4),16) or 0)/255,
             (tonumber(string.sub(h,5,6),16) or 0)/255, 1 }
  end
  return hex2rgb(lhex), hex2rgb(rhex)
end

--- Helper générique : résout (colorSlow, colorBuffed) selon mode + état.
local function ResolveDisplayColor(hasThrill, boosting, specSlowKey, specFastKey)
  local cfg    = GetCfg()
  local mode   = cfg.colorMode or "custom"
  local cslow, cbuffed
  if mode == "spec" then
    local Colors = ns.Modules and ns.Modules.Colors
    cslow   = Colors and Colors.Get(specSlowKey)
    cbuffed = Colors and Colors.Get(specFastKey)
  elseif mode == "mount" and ns.HasHeroicFeatures and ns.HasHeroicFeatures() then
    -- Reglage reserve, cf. Core.lua:ns.HasHeroicFeatures -- si le mode est
    -- "mount" (config importee, ancienne valeur...) mais le flag absent, on
    -- traverse simplement ce elseif sans rien affecter : cslow/cbuffed
    -- restent nil et retombent sur les valeurs par defaut plus bas.
    cslow   = mountColorSlow
    cbuffed = mountColorBuffed
  end
  cslow   = cslow   or cfg.colorNoGlow or COL_SPEED_NOGLOW
  cbuffed = cbuffed or cfg.colorGlow   or COL_SPEED_NORMAL
  if boosting or hasThrill then
    return cbuffed, cbuffed
  end
  return cslow, cslow
end

--- Couleur du cercle de vitesse : powertext (lent) / powercircle (buffé)
local function GetDisplayColor(hasThrill, boosting)
  return ResolveDisplayColor(hasThrill, boosting, "powertext", "powercircle")
end

--- Couleur des orbes extérieurs : powerdotsa (lent) / powerdotsb (buffé)
local function GetOrbColor(hasThrill, boosting)
  return ResolveDisplayColor(hasThrill, boosting, "powerdotsa", "powerdotsb")
end

--- Position d'un orbe (convention math : 0°=droite, CCW, y=up)
local function FlyOrbPos(index, orbRadius, startAngle, stepAngle)
  local angle = math.rad((startAngle or FLY_ROTATION) + (index - 1) * (stepAngle or FLY_STEP_ANGLE))
  return math.cos(angle) * orbRadius, math.sin(angle) * orbRadius
end

---------------------------------------------------------------------------
-- FABRIQUE DE COUCHE CIRCULAIRE
-- Crée un frame + CircularProgress attaché au ringAnchor.
-- texture = circleflat (plein), color, level dans le parent.
---------------------------------------------------------------------------
local function MakeCircleLayer(parent, size, color, level, mirror)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(size, size)
  f:SetPoint("CENTER")
  f:SetFrameLevel(level)

  local cp = ns.CircularProgress.create(f, "ARTWORK", 0)
  ns.CircularProgress.modify(cp, {
    texture   = TEX_CIRCLEFLAT,
    blendMode = "BLEND",
    width     = size,
    height    = size,
    crop_x    = 1,
    crop_y    = 1,
    mirror    = mirror or false,
  })
  cp:SetColor(color[1], color[2], color[3], color[4])
  return f, cp
end

---------------------------------------------------------------------------
-- ANIMATION (slide-in / scale-in, easing expo-out)
---------------------------------------------------------------------------

--- Applique l'état courant de l'animation sur le container.
local function AnimApply()
  if not container then return end
  if isLayoutMode then return end  -- ne pas lutter contre le drag
  local t = anim.progress
  -- Ease-out-expo : démarre vite, se pose en douceur
  -- (la même courbe lue à l'envers donne un ease-in naturel pour le hide)
  local eased = (t <= 0) and 0 or (t >= 1) and 1 or (1.0 - 2^(-10.0 * t))
  local cfg    = GetCfg()
  local baseX  = cfg.x     or 0
  local baseY  = cfg.y     or 250
  local baseSc = cfg.scale or 0.8
  -- Alpha : 0 → 1
  container:SetAlpha(eased)
  -- Scale : 0.70 → baseSc  (léger zoom)
  container:SetScale(baseSc * (0.70 + 0.30 * eased))
  -- Slide : monte de -24 px jusqu'à sa position finale
  container:ClearAllPoints()
  container:SetPoint("BOTTOM", UIParent, "BOTTOM",
    baseX, baseY + (1.0 - eased) * (-24))
end

--- Demande une animation vers l'état « visible ».
local function AnimShow()
  if not container then return end
  container:Show()   -- toujours s'assurer que le container est visible
  anim.target = 1
  -- Notifier les autres modules seulement si l'état change (debounce)
  if not hudVisible then
    hudVisible = true
    ns.skyridingActive = true
    DbgLog("AnimShow → hudVisible=true (container:IsShown=" .. tostring(container:IsShown()) .. ")")
    ns.CallbackRegistry:Trigger("SKYRIDING_CHANGED", true)
  end
end

--- Demande une animation vers l'état « caché ».
local function AnimHide()
  if not container then return end
  if previewActive then
    DbgLog("AnimHide IGNORÉ (previewActive=true)")
    return
  end
  anim.target = 0
  -- Notifier les autres modules seulement si l'état change (debounce)
  if hudVisible then
    hudVisible = false
    ns.skyridingActive = false
    DbgLog("AnimHide → hudVisible=false")
    ns.CallbackRegistry:Trigger("SKYRIDING_CHANGED", false)
  end
end

---------------------------------------------------------------------------
-- MISE À JOUR VITESSE + ASCENSION
---------------------------------------------------------------------------
local function UpdateSpeed()
  local raw = GetForwardSpeed()
  -- Lissage exponentiel léger
  smoothSpeed = smoothSpeed + (raw - smoothSpeed) * 0.4

  local speed    = smoothSpeed
  local thrill   = C_UnitAuras.GetPlayerAuraBySpellID(THRILL_BUFF)
  local now      = GetTime()
  local boosting = thrill and (now < ascentStart + ASCENT_DURATION)

  -- ── Cercle de vitesse (pie fill) ────────────────────────────────────────
  local circleCol, textCol = GetDisplayColor(thrill ~= nil, boosting)
  local fraction = math.max(0, math.min(1, speed / MAX_SPEED))
  if fraction >= 0.005 then
    speedCP:SetColor(circleCol[1], circleCol[2], circleCol[3], circleCol[4] or 1)
    speedCP:Show()
    speedCP:SetProgress(ARC_START, ARC_START + fraction * ARC_TOTAL)
  else
    speedCP:Hide()
  end

  -- ── Cacher à l'atterrissage ────────────────────────────────────────────
  local cfg = GetCfg()
  if cfg.hideAtLanding then
    local isGliding = C_PlayerInfo.GetGlidingInfo()
    if isGliding then
      -- En vol confirmé : afficher et garder activateTime à jour
      wasAirborne  = true
      activateTime = GetTime()
      AnimShow()
    elseif wasAirborne and GetTime() < activateTime + 0.3 then
      -- Micro-grace pour la phase de décollage uniquement (isGliding pas encore true).
      -- À l'atterrissage isGliding=false immédiatement → on ne passe jamais ici.
      AnimShow()
    else
      -- Sol : cacher (smoothSpeed ignoré ici pour éviter le délai dû au lissage)
      AnimHide()
    end
  else
    AnimShow()
  end

  -- ── Texte vitesse (move%) ───────────────────────────────────────────────
  if speedText then
    if speed >= 1 then
      speedText:SetText(string.format("%.0f", speed * SPEED_TEXT_FACTOR))
      speedText:SetTextColor(textCol[1], textCol[2], textCol[3], textCol[4] or 1)
    else
      speedText:SetText("")
    end
  end

  -- ── Cercle d'ascension (pie fill, drain sur la durée du buff) ───────────
  if boosting then
    local elapsed = now - ascentStart
    local p = math.max(0, 1 - elapsed / ASCENT_DURATION)
    if p > 0.01 then
      ascentCP:Show()
      ascentCP:SetProgress(ARC_START, ARC_START + p * ARC_TOTAL)
    else
      ascentCP:Hide()
    end
  else
    ascentCP:Hide()
  end
end

---------------------------------------------------------------------------
-- MISE À JOUR DES CHARGES DE VIGUEUR (6 orbes)
---------------------------------------------------------------------------
local function UpdateFlyCharges()
  local info    = C_Spell.GetSpellCharges(SURGE_FORWARD)
  local current = info and info.currentCharges or 0
  local thrill  = C_UnitAuras.GetPlayerAuraBySpellID(THRILL_BUFF) ~= nil
  local boosting = thrill and (GetTime() < ascentStart + ASCENT_DURATION)
  local activeCol = GetOrbColor(thrill, boosting)

  for i = 1, 6 do
    local orb = flyOrbs[i]
    local oa  = orbAnims[i]
    if not orb then break end
    -- pilote l'animation : 1 = montrer (slide-in), 0 = cacher (slide-out)
    if oa then oa.target = (i <= current) and 1 or 0 end
    -- couleur mise à jour même pendant la transition
    if orb.texture then
      orb.texture:SetVertexColor(activeCol[1], activeCol[2], activeCol[3], activeCol[4] or 1)
    end
    if orb.model then
      orb.model:SetAlpha(thrill and 0.8 or 0.3)
    end
  end
end

---------------------------------------------------------------------------
-- MISE À JOUR SECOND SOUFFLE
---------------------------------------------------------------------------
local function UpdateSecondSouffle()
  local info    = C_Spell.GetSpellCharges(SECOND_SOUFFLE)
  local current = info and info.currentCharges or 0
  local maxChg  = info and info.maxCharges or 0

  for i = 1, 3 do
    local orb = souffleOrbs[i]
    if not orb then break end
    if i > maxChg then
      orb:Hide()
    elseif i <= current then
      orb:Show()
      orb:SetAlpha(1)
    else
      orb:Show()
      orb:SetAlpha(0.2)
    end
  end

  -- Petits points indicateurs sous le texte de vitesse
  for i = 1, 3 do
    local dot = souffleDots[i]
    if dot then
      if i > maxChg then
        dot.frame:Hide()
      elseif i <= current then
        dot.frame:Show()
        dot.texture:SetVertexColor(1, 1, 1, 0.85)
      else
        dot.frame:Show()
        dot.texture:SetVertexColor(0.4, 0.4, 0.4, 0.35)
      end
    end
  end
end

---------------------------------------------------------------------------
-- TICK
---------------------------------------------------------------------------
local function OnTick()
  if not isActive then return end
  UpdateSpeed()
  UpdateFlyCharges()
  UpdateSecondSouffle()
end

---------------------------------------------------------------------------
-- VISIBILITÉ
---------------------------------------------------------------------------
local function ShowAll()
  AnimShow()
end

local function HideAll()
  smoothSpeed = 0
  AnimHide()
end

local function Activate()
  if isActive then return end
  isActive = true
  wasAirborne  = false   -- pas encore en vol : grace period désactivée jusqu'au premier décollage
  activateTime = 0
  DbgLog("Activate (powerBarID=" .. tostring(UnitPowerBarID("player")) .. ")")
  -- Si hideAtLanding : ne PAS appeler ShowAll() ici. UpdateSpeed() déclenchera AnimShow()
  -- dès que la vitesse dépasse 1, évitant l'affichage au sol avant décollage.
  local cfg = GetCfg()
  if not cfg.hideAtLanding then
    ShowAll()
  end
  -- container:OnUpdate ne tourne que si le container est visible. Si on n'a pas appelé ShowAll(),
  -- on s'appuie sur animFrame (qui tourne toujours) pour déclencher le premier UpdateSpeed via
  -- le flag isActive — sauf que animFrame n'appelle pas UpdateSpeed. Contournement : on Show()
  -- le container silencieusement (alpha=0 via anim.progress=0) pour que son OnUpdate tourne.
  if cfg.hideAtLanding then
    container:Show()   -- necessite d'être visible pour que OnUpdate tourne; alpha=0 car anim.progress=0
  end
  pcall(function()
    if EncounterBar and EncounterBar:IsVisible() then EncounterBar:Hide() end
  end)
end

local function Deactivate()
  if not isActive then return end
  isActive    = false
  wasAirborne = false   -- reset pour le prochain montage
  DbgLog("Deactivate (powerBarID=" .. tostring(UnitPowerBarID("player")) .. ")")
  pcall(function()
    if EncounterBar then EncounterBar:Show() end
  end)
  HideAll()  -- AnimHide() déclenche SKYRIDING_CHANGED(false) si hudVisible
end

local function CheckState()
  local cfg = GetCfg()
  if cfg.enabled == false then
    DbgLog("CheckState → Deactivate (cfg.enabled=false)")
    Deactivate(); return
  end
  local pbID = UnitPowerBarID("player")
  local _, canGlide = C_PlayerInfo.GetGlidingInfo()
  local dr   = IsDragonriding()
  DbgLog("CheckState → " .. (dr and "Activate" or "Deactivate")
    .. " powerBarID=" .. tostring(pbID)
    .. " canGlide=" .. tostring(canGlide)
    .. " (attendu=" .. DR_POWERBAR_ID .. ")")
  if dr then Activate() else Deactivate() end
end

---------------------------------------------------------------------------
-- CRÉATION
---------------------------------------------------------------------------
function Skyriding.Create()
  if container then return end
  local cfg = GetCfg()

  local bgSize    = cfg.bgSize    or 120
  local speedSize = cfg.speedSize or 110
  local m1Size    = cfg.mask1Size or 102
  local ascSize   = cfg.ascentSize or 98
  local m2Size    = cfg.mask2Size or 85
  local txtSize   = cfg.textSize  or 14

  ---------------------------------------------------------------------------
  -- Container
  ---------------------------------------------------------------------------
  container = CreateFrame("Frame", "AishCoreSkyridingFrame", UIParent)
  container:SetSize(10, 10)
  container:SetFrameStrata("MEDIUM")
  container:Hide()
  container:SetPoint("BOTTOM", UIParent, "BOTTOM", cfg.x or 0, cfg.y or 250)
  container:SetScale(cfg.scale or 0.8)
  container:SetMovable(true)
  container:EnableMouse(false)

  ---------------------------------------------------------------------------
  -- Ring Anchor (centre du cercle, +20 y par rapport au container)
  ---------------------------------------------------------------------------
  ringAnchor = CreateFrame("Frame", nil, container)
  ringAnchor:SetSize(bgSize, bgSize)
  ringAnchor:SetPoint("CENTER", container, "CENTER", 0, 20)
  ringAnchor:SetFrameStrata("MEDIUM")

  local base = ringAnchor:GetFrameLevel()

  ---------------------------------------------------------------------------
  -- STACKING (du plus bas au plus haut) :
  --   1. BG               (cercle noir plein)
  --   2. Speed circle      (cercle coloré, remplissage pie-chart animé)
  --   3. Mask 1            (cercle noir plein, masque le centre de Speed)
  --   4. Ascension circle  (cercle coloré, remplissage pie-chart animé)
  --   5. Mask 2            (cercle noir plein, masque le centre d'Ascension)
  --   6. Texte vitesse     (par-dessus tout)
  --   7. Second Souffle    (par-dessus tout)
  ---------------------------------------------------------------------------

  -- 1 – BG
  bgFrame, bgCP = MakeCircleLayer(ringAnchor, bgSize, COL_BG, base + 1, true)
  bgCP:SetProgress(0, 360)
  bgCP:Show()

  -- 2 – Speed
  speedFrame, speedCP = MakeCircleLayer(ringAnchor, speedSize, COL_SPEED_NORMAL, base + 2)
  speedCP:Hide()

  -- 3 – Mask 1
  mask1Frame, mask1CP = MakeCircleLayer(ringAnchor, m1Size, COL_BG, base + 3, true)
  mask1CP:SetProgress(0, 360)
  mask1CP:Show()

  -- 4 – Ascension
  ascentFrame, ascentCP = MakeCircleLayer(ringAnchor, ascSize, COL_ASCENT, base + 4)
  ascentCP:Hide()

  -- 5 – Mask 2
  mask2Frame, mask2CP = MakeCircleLayer(ringAnchor, m2Size, COL_BG, base + 5, true)
  mask2CP:SetProgress(0, 360)
  mask2CP:Show()

  -- Speed cap marker (petit trait doré en haut)
  local capFrame = CreateFrame("Frame", nil, ringAnchor)
  capFrame:SetSize(2, 10)
  capFrame:SetPoint("CENTER", ringAnchor, "CENTER", 0, bgSize * 0.292)
  capFrame:SetFrameLevel(base + 6)
  speedCapLine = capFrame:CreateTexture(nil, "OVERLAY")
  speedCapLine:SetAllPoints()
  speedCapLine:SetTexture(TEX_SQUARE_WHITE)
  speedCapLine:SetVertexColor(unpack(COL_SPEEDCAP))

  -- 6 – Speed text
  local textFrame = CreateFrame("Frame", nil, ringAnchor)
  textFrame:SetAllPoints()
  textFrame:SetFrameLevel(base + 7)
  speedText = textFrame:CreateFontString(nil, "OVERLAY")
  speedText:SetFont(FONT_MONTSERRAT_B, txtSize, "")
  speedText:SetJustifyH("CENTER")
  speedText:SetShadowColor(unpack(COL_TXT_SHADOW))
  speedText:SetShadowOffset(1, -1)
  speedText:SetTextColor(unpack(COL_TXT_NORMAL))
  speedText:SetPoint("CENTER", ringAnchor, "CENTER", 0, -1)
  speedText:SetText("")

  -- 7 – Second Souffle (3 modèles horizontaux)
  local souffleAnchor = CreateFrame("Frame", nil, ringAnchor)
  souffleAnchor:SetSize(1, 1)
  souffleAnchor:SetPoint("CENTER", ringAnchor, "CENTER", 0, SOUFFLE_Y_OFF)
  souffleAnchor:SetScale(0.9)
  souffleAnchor:SetFrameLevel(base + 8)

  local totalW  = 3 * SOUFFLE_SIZE + 2 * SOUFFLE_SPACE
  local startX  = -(totalW / 2) + SOUFFLE_SIZE / 2
  for i = 1, 3 do
    local x = startX + (i - 1) * (SOUFFLE_SIZE + SOUFFLE_SPACE)
    local mdl = CreateFrame("PlayerModel", nil, souffleAnchor)
    mdl:SetSize(SOUFFLE_SIZE, SOUFFLE_SIZE)
    mdl:SetPoint("CENTER", souffleAnchor, "CENTER", x, 0)
    mdl:SetFrameLevel(base + 8)
    pcall(function()
      mdl:SetFileDataID(MODEL_CRAWTH)
      mdl:MakeCurrentCameraCustom()
      mdl:SetPosition(0, -0.1, 0.6)
      mdl:SetTransform(40, 0, 0, math.rad(90), 0, math.rad(90), 40)
    end)
    mdl:Hide()
    souffleOrbs[i] = mdl
  end

  -- 7b – Second Souffle : petits points sous le texte de vitesse
  local dotSz  = cfg.dotSize    or 3
  local dotOX  = cfg.dotOffsetX or 0
  local dotOY  = cfg.dotOffsetY or -12
  local DOT_GAP = 4
  souffleDotsAnchor = CreateFrame("Frame", nil, ringAnchor)
  souffleDotsAnchor:SetSize(1, 1)
  souffleDotsAnchor:SetPoint("CENTER", ringAnchor, "CENTER", dotOX, dotOY)
  souffleDotsAnchor:SetFrameLevel(base + 9)
  do
    local totalDW = 3 * dotSz + 2 * DOT_GAP
    local sdX     = -(totalDW / 2) + dotSz / 2
    for i = 1, 3 do
      local df = CreateFrame("Frame", nil, souffleDotsAnchor)
      df:SetSize(dotSz, dotSz)
      df:SetPoint("CENTER", souffleDotsAnchor, "CENTER", sdX + (i - 1) * (dotSz + DOT_GAP), 0)
      df:SetFrameLevel(base + 9)
      local dtex = df:CreateTexture(nil, "ARTWORK")
      dtex:SetAllPoints()
      dtex:SetTexture(TEX_CIRCLE_SMOOTH)
      dtex:SetVertexColor(0.4, 0.4, 0.4, 0.35)
      df:Hide()
      souffleDots[i] = { frame = df, texture = dtex }
    end
  end

  ---------------------------------------------------------------------------
  -- FLY CHARGES (6 orbes autour du cercle BG)
  ---------------------------------------------------------------------------
  do
    local orbSz   = cfg.orbSize      or FLY_ORB_SIZE
    local orbRad  = cfg.orbRadius    or (bgSize * ORB_RADIUS_RATIO)
    local sAngle  = cfg.orbStartAngle or FLY_ROTATION
    local stAngle = cfg.orbSpacing   or FLY_STEP_ANGLE
    for i = 1, 6 do
      local ox, oy = FlyOrbPos(i, orbRad, sAngle, stAngle)

      local orbFrame = CreateFrame("Frame", nil, container)
      orbFrame:SetSize(orbSz, orbSz)
      orbFrame:SetPoint("CENTER", container, "CENTER", ox, oy + 20)
      orbFrame:SetFrameLevel(base + 2)
      orbFrame:Hide()

      local tex = orbFrame:CreateTexture(nil, "ARTWORK")
      tex:SetAllPoints()
      tex:SetTexture(TEX_CIRCLE_SMOOTH)
      tex:SetVertexColor(unpack(COL_ORB_BASE))

      -- Sub-model glow
      local mdl = CreateFrame("PlayerModel", nil, orbFrame)
      mdl:SetSize(orbSz + 42, orbSz + 57)
      mdl:SetPoint("CENTER")
      mdl:SetAlpha(0.3)
      pcall(function()
        mdl:SetFileDataID(MODEL_CRAWTH)
        mdl:MakeCurrentCameraCustom()
        mdl:SetPosition(-0.4, -0.3, -12.25)
        mdl:SetTransform(0, 0, 0, math.rad(270), 0, 0, 40)
      end)

      flyOrbs[i]  = { frame = orbFrame, texture = tex, model = mdl }
      orbAnims[i] = { progress = 0, target = 0 }
    end
  end

  ---------------------------------------------------------------------------
  -- animFrame : ticker dédié à l'animation show/hide (tourne toujours)
  ---------------------------------------------------------------------------
  animFrame = CreateFrame("Frame")
  anim.progress = 0
  anim.target   = 0
  local mountPollTimer = 0
  animFrame:SetScript("OnUpdate", function(_, dt)
    -- ── Fallback de détection mount (si PLAYER_MOUNT_DISPLAY_CHANGED a raté) ──
    -- Sonde IsDragonriding() toutes les 0.5 s quand le HUD est inactif.
    if not isActive then
      mountPollTimer = mountPollTimer + dt
      if mountPollTimer >= 0.5 then
        mountPollTimer = 0
        local cfg2 = GetCfg()
        if cfg2.enabled ~= false and IsDragonriding() then
          DbgLog("animFrame poll: IsDragonriding → Activate")
          Activate()
        end
      end
    else
      mountPollTimer = 0
    end

    -- ── Animation du container (slide + scale global) ─────────────────────────
    if anim.progress ~= anim.target then
      local dir = anim.target > anim.progress and 1 or -1
      anim.progress = math.max(0.0, math.min(1.0, anim.progress + dir * anim.speed * dt))
      AnimApply()
      -- NB : on ne cache JAMAIS via Hide() ici.
    end

    -- ── Animation slide des orbes (ease-circ-out, extérieur → position finale) ──
    if not container then return end
    local cfg2       = GetCfg()
    local bgSz2      = cfg2.bgSize       or 120
    local startAngle = cfg2.orbStartAngle or FLY_ROTATION
    local stepAngle  = cfg2.orbSpacing   or FLY_STEP_ANGLE
    local orbRad     = cfg2.orbRadius    or (bgSz2 * ORB_RADIUS_RATIO)
    for i = 1, 6 do
      local oa  = orbAnims[i]
      local orb = flyOrbs[i]
      if not (oa and orb) then break end
      if oa.progress ~= oa.target then
        local dir = oa.target > oa.progress and 1 or -1
        oa.progress = math.max(0.0, math.min(1.0, oa.progress + dir * ORB_SLIDE_SPEED * dt))
      end
      local t = oa.progress
      if t <= 0 then
        orb.frame:Hide()
      else
        if not orb.frame:IsShown() then orb.frame:Show() end
        -- ease-circ-out : démarre vite, amorti à l'arrivée
        local eased = (t >= 1.0) and 1.0 or math.sqrt(1.0 - (1.0 - t) * (1.0 - t))
        -- slide depuis ORB_SLIDE_SCALE × rayon vers la position cible
        local ox, oy = FlyOrbPos(i, orbRad, startAngle, stepAngle)
        local k = 1.0 + (ORB_SLIDE_SCALE - 1.0) * (1.0 - eased)
        orb.frame:ClearAllPoints()
        orb.frame:SetPoint("CENTER", container, "CENTER", ox * k, oy * k + 20)
        orb.frame:SetAlpha(eased)
      end
    end
  end)

  ---------------------------------------------------------------------------
  -- OnUpdate : animation fluide (chaque frame)
  -- Fly charges + souffle ne changent pas à 60fps, on les poll moins souvent
  ---------------------------------------------------------------------------
  local slowElapsed = 0
  container:SetScript("OnUpdate", function(_, dt)
    if not isActive then return end
    UpdateSpeed()
    slowElapsed = slowElapsed + dt
    if slowElapsed >= 0.2 then
      slowElapsed = 0
      UpdateFlyCharges()
      UpdateSecondSouffle()
    end
  end)

  ---------------------------------------------------------------------------
  -- ÉVÉNEMENTS
  ---------------------------------------------------------------------------
  local evtFrame = CreateFrame("Frame")
  evtFrame:RegisterEvent("UNIT_POWER_BAR_SHOW")
  evtFrame:RegisterEvent("UNIT_POWER_BAR_HIDE")
  evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  evtFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")  -- fallback si UNIT_POWER_BAR_SHOW ne fire plus
  evtFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  evtFrame:RegisterUnitEvent("UNIT_SPELLCAST_START",     "player")
  evtFrame:SetScript("OnEvent", function(_, event, unit, ...)
    -- Mémoriser le dernier sort lancé (pour capturer la couleur de monture)
    if event == "UNIT_SPELLCAST_START" then
      local _, spellId = ...
      lastMountSpellId = spellId
      return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      local _, spellId = ...
      if spellId == ASCENT_SPELL then
        ascentStart = GetTime()
      end
      return
    end
    -- Journaliser les events de visibilité critiques
    if event == "UNIT_POWER_BAR_SHOW" then
      local pbID = UnitPowerBarID("player")
      local _, cg = C_PlayerInfo.GetGlidingInfo()
      DbgLog("EVENT:UNIT_POWER_BAR_SHOW powerBarID=" .. tostring(pbID) .. " canGlide=" .. tostring(cg))
    elseif event == "UNIT_POWER_BAR_HIDE" then
      local _, cg = C_PlayerInfo.GetGlidingInfo()
      DbgLog("EVENT:UNIT_POWER_BAR_HIDE powerBarID=" .. tostring(UnitPowerBarID("player")) .. " canGlide=" .. tostring(cg))
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
      local _, cg = C_PlayerInfo.GetGlidingInfo()
      DbgLog("EVENT:PLAYER_MOUNT_DISPLAY_CHANGED canGlide=" .. tostring(cg))
      -- L'API GetGlidingInfo peut ne pas être à jour au moment exact où l'event fire.
      -- Re-vérifier après un court délai pour attraper le cas où canGlide devient true un frame plus tard.
      C_Timer.After(0.5, CheckState)
    elseif event == "PLAYER_ENTERING_WORLD" then
      local isLogin, isReload = ...
      DbgLog("EVENT:PLAYER_ENTERING_WORLD login=" .. tostring(isLogin) .. " reload=" .. tostring(isReload))
    end
    -- Au décollage : capturer les deux couleurs du dégradé de la monture
    -- (UNIT_POWER_BAR_SHOW ne fire plus depuis un hotfix Blizzard → fallback sur PLAYER_MOUNT_DISPLAY_CHANGED)
    if (event == "UNIT_POWER_BAR_SHOW" or event == "PLAYER_MOUNT_DISPLAY_CHANGED") and IsDragonriding() and lastMountSpellId then
      local cs, cb = ComputeSpellGradient(lastMountSpellId)
      if cs then mountColorSlow   = EnforceBrightness(cs, 0.55, 0.72) end
      if cb then mountColorBuffed = cb end
      DbgLog("MountColor capturée spellId=" .. tostring(lastMountSpellId) .. " via " .. event)
    end
    CheckState()
  end)

  CheckState()
end

---------------------------------------------------------------------------
-- APPLY SETTINGS  (appelé lors de changements de config)
---------------------------------------------------------------------------
function Skyriding.IsActive()
  return isActive
end

-- Vrai si le HUD Skyriding (notre roue) est actuellement affiché.
-- Suit le flag hudVisible (mis à jour par AnimShow/AnimHide avec debounce).
function Skyriding.HUDIsVisible()
  return hudVisible
end

function Skyriding.ApplySettings()
  if not container then return end
  local cfg = GetCfg()

  if cfg.enabled == false then
    previewActive = false   -- ne pas bloquer AnimHide si le panneau était ouvert
    Deactivate(); return
  end

  -- Position + échelle (via AnimApply pour respecter l'état d'animation courant)
  AnimApply()

  -- Tailles
  local bgSize    = cfg.bgSize    or 120
  local speedSize = cfg.speedSize or 110
  local m1Size    = cfg.mask1Size or 102
  local ascSize   = cfg.ascentSize or 98
  local m2Size    = cfg.mask2Size or 85
  local txtSize   = cfg.textSize  or 14

  ringAnchor:SetSize(bgSize, bgSize)

  -- Resize chaque couche (frame + CircularProgress interne)
  local function ResizeLayer(frame, cp, sz)
    if frame then frame:SetSize(sz, sz) end
    if cp then
      cp.width  = sz
      cp.height = sz
      -- Rebind textures au nouveau frame
      for i = 1, 3 do
        cp.textures[i]:ClearAllPoints()
        cp.textures[i]:SetAllPoints(frame)
      end
      cp:UpdateTextures()
    end
  end

  ResizeLayer(bgFrame,     bgCP,     bgSize)
  ResizeLayer(speedFrame,  speedCP,  speedSize)
  ResizeLayer(mask1Frame,  mask1CP,  m1Size)
  ResizeLayer(ascentFrame, ascentCP, ascSize)
  ResizeLayer(mask2Frame,  mask2CP,  m2Size)

  -- Texte
  if speedText then
    speedText:SetFont(cfg.font or FONT_MONTSERRAT_B, txtSize, "")
  end

  -- Speed cap marker repositionné en fonction du bgSize
  if speedCapLine then
    local cap = speedCapLine:GetParent()
    if cap then
      cap:ClearAllPoints()
      cap:SetPoint("CENTER", ringAnchor, "CENTER", 0, bgSize * 0.292)
    end
  end

  -- Orbs : redimensionner uniquement (le positionnement est géré par l'animFrame)
  local orbSize = cfg.orbSize or FLY_ORB_SIZE
  for i = 1, 6 do
    local orb = flyOrbs[i]
    if orb then
      orb.frame:SetSize(orbSize, orbSize)
      if orb.model then
        orb.model:SetSize(orbSize + 42, orbSize + 57)
      end
    end
  end

  -- Points Second Souffle : reposition + redimensionner
  if souffleDotsAnchor then
    local dotSz  = cfg.dotSize    or 3
    local dotOX  = cfg.dotOffsetX or 0
    local dotOY  = cfg.dotOffsetY or -12
    local DOT_GAP = 4
    souffleDotsAnchor:ClearAllPoints()
    souffleDotsAnchor:SetPoint("CENTER", ringAnchor, "CENTER", dotOX, dotOY)
    local totalDW = 3 * dotSz + 2 * DOT_GAP
    local sdX     = -(totalDW / 2) + dotSz / 2
    for i = 1, 3 do
      local dot = souffleDots[i]
      if dot then
        dot.frame:SetSize(dotSz, dotSz)
        dot.frame:ClearAllPoints()
        dot.frame:SetPoint("CENTER", souffleDotsAnchor, "CENTER", sdX + (i - 1) * (dotSz + DOT_GAP), 0)
      end
    end
  end

  CheckState()
end

---------------------------------------------------------------------------
-- MODE LAYOUT (repositionnement par drag)
---------------------------------------------------------------------------
local layoutHighlight = nil

function Skyriding.SetLayoutMode(enable)
  if not container then return end
  isLayoutMode = enable  -- avant tout : bloque AnimApply pendant le drag

  if enable then
    -- Figer l'animation en état « visible »
    anim.progress = 1 ; anim.target = 1
    local cfg = GetCfg()
    container:ClearAllPoints()
    container:SetPoint("BOTTOM", UIParent, "BOTTOM", cfg.x or 0, cfg.y or 250)
    container:SetAlpha(1)
    container:SetScale(cfg.scale or 0.8)
    container:Show()

    if not layoutHighlight then
      layoutHighlight = CreateFrame("Frame", nil, container, "BackdropTemplate")
      layoutHighlight:SetBackdrop({
        bgFile    = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile  = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
      })
      layoutHighlight:SetBackdropColor(0.2, 0.6, 1, 0.25)
      layoutHighlight:SetBackdropBorderColor(0.2, 0.7, 1, 0.8)
      layoutHighlight:SetSize(130, 130)
      layoutHighlight:SetPoint("CENTER", container, "CENTER", 0, 20)
      layoutHighlight:SetFrameLevel(container:GetFrameLevel() + 10)
    end
    layoutHighlight:Show()

    -- Drag manuel via delta curseur : évite tout problème de conversion de
    -- coordonnées lié au scale du container (StartMoving/StopMovingOrSizing
    -- retournent des valeurs dans l'espace local du frame, pas UIParent).
    layoutHighlight:EnableMouse(true)
    local dragging     = false
    local dMouseX0, dMouseY0 = 0, 0   -- position curseur au début du drag (pixels écran)
    local dFrameX0, dFrameY0 = 0, 0   -- offset BOTTOM:UIParent:BOTTOM au début du drag

    layoutHighlight:SetScript("OnMouseDown", function(self, btn)
      if btn ~= "LeftButton" then return end
      dragging  = true
      dMouseX0, dMouseY0 = GetCursorPosition()
      local cfg2 = GetCfg()
      dFrameX0 = (ns.DB.skyriding and ns.DB.skyriding.x) or cfg2.x or 0
      dFrameY0 = (ns.DB.skyriding and ns.DB.skyriding.y) or cfg2.y or 250
    end)

    layoutHighlight:SetScript("OnMouseUp", function(self, btn)
      if btn ~= "LeftButton" then return end
      dragging = false
      -- Les valeurs DB sont déjà à jour (écrites au fil du OnUpdate).
      -- Mettre à jour les champs X/Y du panneau de config.
      local db = ns.DB.skyriding or {}
      local xSl = _G["AishCoreSRPosXSlider"]
      local ySl = _G["AishCoreSRPosYSlider"]
      if xSl then xSl:SetValue(db.x or 0) end
      if ySl then ySl:SetValue(db.y or 0) end
    end)

    layoutHighlight:SetScript("OnUpdate", function()
      if not dragging then return end
      local mx, my    = GetCursorPosition()
      local uiEffScale = UIParent:GetEffectiveScale()
      -- Convertit le delta pixels écran en unités logiques UIParent
      local newX = math.floor(dFrameX0 + (mx - dMouseX0) / uiEffScale + 0.5)
      local newY = math.floor(dFrameY0 + (my - dMouseY0) / uiEffScale + 0.5)
      container:ClearAllPoints()
      container:SetPoint("BOTTOM", UIParent, "BOTTOM", newX, newY)
      if not ns.DB.skyriding then ns.DB.skyriding = {} end
      ns.DB.skyriding.x = newX
      ns.DB.skyriding.y = newY
    end)
  else
    if layoutHighlight then
      layoutHighlight:EnableMouse(false)
      layoutHighlight:SetScript("OnMouseDown", nil)
      layoutHighlight:SetScript("OnMouseUp",   nil)
      layoutHighlight:SetScript("OnUpdate",    nil)
      layoutHighlight:Hide()
    end
    if not IsDragonriding() and not previewActive then HideAll() end
  end
end

---------------------------------------------------------------------------
-- PREVIEW (affiché lors de l'ouverture du panneau de configuration)
---------------------------------------------------------------------------
function Skyriding.SetPreview(on)
  if not container then return end
  previewActive = on
  if on then
    -- Figer l'animation en état « visible »
    anim.progress = 1 ; anim.target = 1
    local cfg = GetCfg()
    container:ClearAllPoints()
    container:SetPoint("BOTTOM", UIParent, "BOTTOM", cfg.x or 0, cfg.y or 250)
    container:SetAlpha(1)
    container:SetScale(cfg.scale or 0.8)
    container:Show()
    -- Cercle de vitesse à ~70 %
    local frac = 0.7
    local previewCircleCol, previewTextCol = GetDisplayColor(true, false)  -- simule buff actif, pas de boost
    speedCP:SetColor(previewCircleCol[1], previewCircleCol[2], previewCircleCol[3], 1)
    speedCP:Show()   -- Show() avant SetProgress : met visible=true pour que UpdateTextures calcule l'arc
    speedCP:SetProgress(ARC_START, ARC_START + frac * ARC_TOTAL)
    -- Texte vitesse
    if speedText then
      speedText:SetText("73")
      speedText:SetTextColor(previewTextCol[1], previewTextCol[2], previewTextCol[3], 1)
    end
    -- 6 orbes en position finale
    local previewOrbCol = GetOrbColor(true, false)  -- simule buff actif, pas de boost
    for i = 1, 6 do
      local oa = orbAnims[i]
      if oa then oa.progress = 1 ; oa.target = 1 end
      local orb = flyOrbs[i]
      if orb then
        orb.frame:SetAlpha(1)
        if orb.texture then
          orb.texture:SetVertexColor(previewOrbCol[1], previewOrbCol[2], previewOrbCol[3], 1)
        end
      end
    end
    -- 3 points Second Souffle actifs
    for i = 1, 3 do
      local dot = souffleDots[i]
      if dot then
        dot.frame:Show()
        dot.texture:SetVertexColor(1, 1, 1, 0.85)
      end
    end
  else
    local cfg2 = GetCfg()
    if cfg2.enabled ~= false and IsDragonriding() then
      AnimShow()  -- restaurer l'état animé réel (SetPreview(true) avait gelé progress/target directement)
    elseif not isLayoutMode then
      HideAll()
    end
  end
end

---------------------------------------------------------------------------
-- DEBUG DUMP  (/aishdebug sky)
---------------------------------------------------------------------------
function Skyriding.DebugDump()
  local function yn(v) return v and "|cff00ff00OUI|r" or "|cffff4444NON|r" end
  local sep = "|cff00ccff[Sky Debug]|r"
  local cfg = GetCfg()
  print(sep .. " ─────────────────────────────────────────")
  -- État interne
  print(sep .. " isActive=" .. yn(isActive)
    .. "  hudVisible=" .. yn(hudVisible)
    .. "  previewActive=" .. yn(previewActive)
    .. "  isLayoutMode=" .. yn(isLayoutMode))
  -- Container
  if container then
    local parent = container:GetParent()
    local parentVis = parent and parent:IsVisible()
    print(sep .. " container:"
      .. " Show=" .. yn(container:IsShown())
      .. " Visible=" .. yn(container:IsVisible())
      .. " alpha=" .. string.format("%.2f", container:GetAlpha())
      .. " scale=" .. string.format("%.2f", container:GetEffectiveScale())
      .. " strata=" .. tostring(container:GetFrameStrata()))
    print(sep .. " parent=|cffff9900" .. tostring(parent and parent:GetName() or "?") .. "|r"
      .. "  parentVisible=" .. yn(parentVis))
  else
    print(sep .. " container: |cffff4444NIL — Skyriding.Create() pas encore appelé|r")
  end
  -- Animation
  print(sep .. " anim: progress=" .. string.format("%.2f", anim.progress)
    .. "  target=" .. string.format("%.2f", anim.target)
    .. "  speed=" .. anim.speed)
  -- Power bar + gliding raw state
  local pbID = UnitPowerBarID("player")
  local isGliding, canGlide, fwdSpeed = C_PlayerInfo.GetGlidingInfo()
  print(sep .. " UnitPowerBarID(player)=|cffff9900" .. tostring(pbID) .. "|r"
    .. "  attendu=" .. DR_POWERBAR_ID
    .. "  pbID_match=" .. yn(pbID == DR_POWERBAR_ID)
    .. "  IsDragonriding=" .. yn(IsDragonriding()))
  print(sep .. " GetGlidingInfo:"
    .. "  isGliding=" .. yn(isGliding)
    .. "  canGlide=" .. yn(canGlide)
    .. "  forwardSpeed=" .. string.format("%.1f", fwdSpeed or 0))
  -- État personnage
  print(sep .. " UnitIsOnTaxi=" .. yn(UnitIsOnTaxi("player"))
    .. "  UnitInVehicle=" .. yn(UnitInVehicle("player"))
    .. "  IsMounted=" .. yn(IsMounted()))
  -- Config
  print(sep .. " cfg.enabled=" .. tostring(cfg.enabled ~= false)
    .. "  cfg.hideAtLanding=" .. tostring(cfg.hideAtLanding)
    .. "  smoothSpeed=" .. string.format("%.2f", smoothSpeed))
  -- Config complète (champs numériques/strings)
  local cfgParts = {}
  for k, v in pairs(cfg) do
    if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
      cfgParts[#cfgParts+1] = k .. "=" .. tostring(v)
    end
  end
  table.sort(cfgParts)
  print(sep .. " cfg complet: " .. table.concat(cfgParts, "  "))
  -- Journal
  print(sep .. " — Journal des derniers événements :")
  if #_dbgLog == 0 then
    print("  (vide — monte sur la monture, puis tape /aishdebug sky)")
  else
    for _, line in ipairs(_dbgLog) do
      print("  " .. line)
    end
  end
  print(sep .. " ─────────────────────────────────────────")
end

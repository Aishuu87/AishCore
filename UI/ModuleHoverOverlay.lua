-- UI/ModuleHoverOverlay.lua
-- Survol GUI -> lien direct vers la section de reglages : survoler un module a l'ecran affiche un
-- highlight (lueur, nom, aide "Clic droit : Regler") ; clic droit sur le highlight : saut vers sa section.
local addonName, ns = ...
local L = ns.L

local Hover = {}
ns.ModuleHoverOverlay = Hover

-- REGISTRE des frames "module" survolables. getFrame() est relu a chaque tick (certaines frames
-- sont creees tardivement ou temporaires) et peut renvoyer nil : l'entree est alors ignoree.
local function G(name) return _G[name] end

-- section : cle de locale de l'en-tete de la page a deplier en y allant (cf. MainFrame:GoToElement).
-- name    : cle de locale du nom affiche au survol (sinon le nom de la page).
local STATIC_ENTRIES = {
  { category = "resourceCircle", getFrame = function() return G("AishCoreRingBar") end },
  -- Cercles hors combat : une page pour les deux, onGo y selectionne le cercle survole
  { category = "outOfCombat", mod = "healthCircle", name = "SETTINGS_SEC_HEALTH_CIRCLE",
    onGo = function() ns._oocSelected = "health" end, getFrame = function() return G("AishCoreHealthRing") end },
  { category = "outOfCombat", mod = "outOfCombatResourceCircle", name = "SETTINGS_SEC_OCRC",
    onGo = function() ns._oocSelected = "resource" end, getFrame = function() return G("AishCoreOCResourceRing") end },
  { category = "outOfCombat", mod = "petHealthCircle", name = "SETTINGS_MOD_PET_HEALTH_CIRCLE",
    onGo = function() ns._oocSelected = "pet" end, getFrame = function() return G("AishCorePetHealthRing") end },
  { category = "wellFed",        mod = "wellFedCircle", getFrame = function() return G("AishCoreWellFedRing") end },
  -- Barres de cast : une page pour les trois, onGo y selectionne la barre survolee
  { category = "castBars", mod = "castBar",       name = "SETTINGS_SEC_CAST_BAR",
    onGo = function() ns._castBarsSelected = "player" end, getFrame = function() return G("AishCoreCastBar") end },
  { category = "castBars", mod = "targetCastBar", name = "SETTINGS_CAT_TARGET_CAST",
    onGo = function() ns._castBarsSelected = "target" end, getFrame = function() return G("AishCoreTargetCastBar") end },
  { category = "castBars", mod = "focusCastBar",  name = "SETTINGS_CAT_FOCUS_CAST",
    onGo = function() ns._castBarsSelected = "focus" end, getFrame = function() return G("AishCoreFocusCastBar") end },
  { category = "rotationHelper", getFrame = function() return G("AishCoreRotationHelperBar") end },
  -- TopTargetBar : 2 entrees (barre cible + barre "cible de la cible", frame separee), page Barres de vie
  { category = "unitBars", mod = "topTargetBar", name = "SETTINGS_CAT_TOP_TARGET",
    onGo = function() ns._unitBarsSelected = "topTarget" end, getFrame = function() return G("AishCoreTopTarget") end },
  { category = "unitBars", mod = "topTargetBar_tot", name = "TTB_TOT_LABEL",
    onGo = function() ns._unitBarsSelected = "topTargetTot" end, getFrame = function() return G("AishCoreTopTargetTarget") end },
  -- XPBar : hoverFrame (zone autour du badge de niveau), pas le container qui reste alpha 0
  -- tant qu'on ne survole pas justement hoverFrame.
  { category = "xpBar", getFrame = function()
      local XB = ns.Modules and ns.Modules.XPBar
      return XB and XB.GetHoverFrame and XB.GetHoverFrame()
    end },
  { category = "location", getFrame = function() return G("AishCoreLocation") end },
  { category = "chat", getFrame = function()
      local CH = ns.Modules and ns.Modules.Chat
      return CH and CH.Cfg().enabled and CH.GetHoverFrame()
    end },
  -- Skyriding : AishCoreSkyridingFrame n'est qu'une ancre technique, sans rapport avec le cercle
  -- visible, donc GetHoverFrame() cible ce cercle directement.
  { category = "skyriding", getFrame = function()
      local SR = ns.Modules and ns.Modules.Skyriding
      return SR and SR.GetHoverFrame and SR.GetHoverFrame()
    end },
  -- TargetAuras : buffRow et debuffRow sont positionnees independamment (offsetX/offsetY), donc
  -- potentiellement hors du rectangle englobant : 2 entrees distinctes via GetHoverRows().
  { category = "unitBars", mod = "targetAuras", name = "UNITBARS_TARGET_BUFFS", taGroup = "taBuffs", getFrame = function()
      local TA = ns.Modules and ns.Modules.TargetAuras
      if not (TA and TA.GetHoverRows) then return nil end
      local buffRow = TA.GetHoverRows()
      return buffRow
    end },
  { category = "unitBars", mod = "targetAuras", name = "UNITBARS_TARGET_DEBUFFS", taGroup = "taDebuffs", getFrame = function()
      local TA = ns.Modules and ns.Modules.TargetAuras
      if not (TA and TA.GetHoverRows) then return nil end
      local _, debuffRow = TA.GetHoverRows()
      return debuffRow
    end },
  -- Buffs manquants : icone d'alerte (cadre global du module Auras)
  { category = "aurasMissingBuffs", name = "AURASDATA_SEC_MISSINGBUFFS_LABEL", getFrame = function()
      -- Cree et place l'alerte meme sans buff manquant, pour avoir son cadre de reperage
      local MB = ns.Auras and ns.Auras.MissingBuffs
      if MB and MB.PrepareHoverAnchor then return MB.PrepareHoverAnchor() end
      return G("AishCoreMissingBuffFrame")
    end },
  -- PriorityBar : leftContainer/rightContainer sont locales au module (jamais
  -- de nom global), cf. PriorityBar.GetContainers() ajoute pour ce besoin.
  { category = "priorityBar", getFrame = function()
      local PB = ns.Modules and ns.Modules.PriorityBar
      local c = PB and PB.GetContainers and PB.GetContainers()
      return c and c.left
    end },
  { category = "priorityBar", getFrame = function()
      local PB = ns.Modules and ns.Modules.PriorityBar
      local c = PB and PB.GetContainers and PB.GetContainers()
      return c and c.right
    end },
}

-- Auras de la cible : page Barres de vie, groupe survole selectionne
for _, e in ipairs(STATIC_ENTRIES) do
  if e.taGroup then
    local sel = e.taGroup
    e.onGo = function() ns._unitBarsSelected = sel end
  end
end

-- Buffs de deplacement : cadre d'une rangee, present meme sans buff actif
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
  category = "movementBuffs",
  getFrame = function()
    local MVB = ns.Modules and ns.Modules.MovementBuffs
    return MVB and MVB.GetHoverFrame and MVB.GetHoverFrame()
  end,
}

-- Camping HUD (Forever) : place meme masque (loin d'un feu), cadre visible sur la page Modules
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
  category = "campfire",
  getFrame = function()
    if not (ns.IsModuleAvailable and ns.IsModuleAvailable("campfire")) then return nil end
    return G("AishCoreCampfire")
  end,
}

-- Peche (Forever) : icone de l'appat et bouton de reequipement, chacun vers sa section
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = { category = "fishing", mod = "fishingLure", section = "SETTINGS_FISHING_SEC_LURE",
  getFrame = function() return G("AishCoreFishingLure") end }
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = { category = "fishing", mod = "fishingSwap", section = "SETTINGS_FISHING_SEC_SWAP",
  getFrame = function() return G("AishCoreFishingSwap") end }

-- Barre de menu
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
  category = "menuBar",
  getFrame = function()
    local MB = ns.Modules and ns.Modules.MenuBar
    return MB and MB.GetHoverFrame and MB.GetHoverFrame()
  end,
}

-- Compartiment d'addons : bouton pose sur la minimap
STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
  category = "addonCompartment",
  getFrame = function()
    local AC = ns.Modules and ns.Modules.AddonCompartment
    return AC and AC.GetHoverFrame and AC.GetHoverFrame()
  end,
}

-- Extra Barres : une entree par barre ; onGo selectionne cette barre dans la page avant d'y sauter
for i = 1, 5 do
  STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
    category = "extraBars",
    getFrame = function()
      local EB = ns.Modules and ns.Modules.ExtraBars
      return EB and EB.GetBarFrame and EB.GetBarFrame(i)
    end,
    onGo = function() ns._extraBarsSelected = i end,
  }
end

-- Barres d'action : une entree par barre ; onGo selectionne cette barre dans la page avant d'y sauter
do
  local AB = ns.Modules and ns.Modules.ActionBars
  for _, def in ipairs(AB and AB.BARS or {}) do
    local key = def.key
    STATIC_ENTRIES[#STATIC_ENTRIES + 1] = {
      category = "actionBars", name = "ACTIONBARS_BAR_" .. key:upper(),
      -- Barre masquee par ses regles comprise (comme les autres modules) ; barre desactivee exclue
      getFrame = function()
        local m = ns.Modules and ns.Modules.ActionBars
        if not (m and m.IsEnabled() and m.IsAdopted() and m.BV(key, "enabled") ~= false) then return nil end
        return m.GetFrame(key)
      end,
      onGo = function() ns._actionBarsSelected = key end,
    }
  end
end

-- Auras render frames (4 mises en page distinctes) : registre live cote
-- Modules/Auras (ns.Auras.renderFrames, alimente par ns.RegisterRender dans
-- chaque fichier de render -- cf. Modules/Auras/Core/Init.lua).
local AURAS_RENDER_CATEGORY = {
  iconlist   = "aurasIconlist",
  freebars   = "aurasFreebars",
  icons      = "aurasIcons",
  circlebars = "aurasCirclebars",
  -- Totems : rendu 100% manuel (pas d'AddAuraGroup, cf. Core/Totems.lua),
  -- mais enregistre son container dans ns.Auras.renderFrames comme les 4
  -- autres (EnsureTotemsContainer) -- meme mecanisme generique suffit.
  totems     = "aurasTotems",
}
for renderKey, catId in pairs(AURAS_RENDER_CATEGORY) do
  STATIC_ENTRIES[#STATIC_ENTRIES + 1] = { category = catId, getFrame = function()
    local A = ns.Auras
    local rf = A and A.renderFrames and A.renderFrames[renderKey]
    return rf and rf.container
  end }
end

local UNIT_BAR_NAMES = {
  player = "SETTINGS_UNIT_PLAYER", target = "SETTINGS_UNIT_TARGET", focus = "SETTINGS_UNIT_FOCUS",
  pet = "SETTINGS_UNIT_PET", targettarget = "SETTINGS_UNIT_TARGET_OF_TARGET",
}

-- UnitBars : nombre et cles variables (BAR_DEFS), aucune ne porte de nom
-- global -> construites une seule fois (a la 1ere activation) depuis
-- UnitBars.GetBars(), stable une fois UnitBars.Create() passe.
local ENTRIES = nil
local function BuildEntries()
  if ENTRIES then return ENTRIES end
  local list = {}
  for _, e in ipairs(STATIC_ENTRIES) do list[#list + 1] = e end
  local UB = ns.Modules and ns.Modules.UnitBars
  local bars = UB and UB.GetBars and UB.GetBars()
  if bars then
    for key, frame in pairs(bars) do
      local f, bk = frame, key
      list[#list + 1] = {
        category = "unitBars", name = UNIT_BAR_NAMES[bk],
        mod = "unitBars_" .. (bk == "targettarget" and "tot" or bk),
        getFrame = function() return f end,
        -- Selectionne CETTE barre dans la page avant d'y sauter
        onGo = function() ns._unitBarsSelected = bk end,
      }
    end
  end
  ENTRIES = list
  return list
end

-- WIDGETS : un seul highlight (lueur + nom + aide "Clic droit"), repositionne sur la frame survolee.
local highlight
local hoveredFrame, hoveredCategory, hoveredEntry
local HL_PAD   = 0   -- collé a l'element : la lueur part de la bordure de la hitbox (cf. BoxFor)
local LVL_TEXT = 40   -- niveau des textes (nom, aide), au-dessus de toutes les lueurs

-- Couleur "Lueur" des Couleurs Thematiques (spe active), repli sur l'or
local function GlowRGB()
  local C = ns.Modules and ns.Modules.Colors
  local c = C and C.Get and C.Get("glow")
  if c and c[1] then return c[1], c[2], c[3] end
  return 1, 0.82, 0.3
end

-- Nom des hitbox : "texte de puissance" des Couleurs Thematiques ; couleurs de base : bleu des hitbox eclairci
-- (meme condition que ns.HitboxColor)
local function NameRGB()
  local C = ns.Modules and ns.Modules.Colors
  if C and C.Get and ns.DB and ns.DB.colors and not ns.DB.colors.useClassDefaults then
    local c = C.Get("powertext")
    if c and c[1] then return c[1], c[2], c[3] end
  end
  local r, g, b = ns.HitboxColor()
  return r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5
end

-- Lueur exterieure autour de `anchor` : backdrop dont la bordure est GlowTex.tga (technique ElvUI, cf. survol des
-- barres d'unites), propre dans les coins. Rien n'est lu de la taille du cadre (souvent secrete pour les conteneurs
-- d'auras) : tout est accroche a ses bords. glow:SetGlowColor(r, g, b) la recolore.
local GLOW_TEX = "Interface\\AddOns\\AishCore\\Media\\UI\\GlowTex.tga"
local function BuildGlow(parent, anchor, G, A)
  local glow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -G, G)
  glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", G, -G)
  glow:SetBackdrop({ edgeFile = GLOW_TEX, edgeSize = G })
  function glow:SetGlowColor(r, g, b)
    if self._r == r and self._g == g and self._b == b then return end
    self._r, self._g, self._b = r, g, b
    self:SetBackdropBorderColor(r, g, b, A)
  end
  return glow
end

-- Texte a contour SLUG (police 2002 par defaut, cf. ns.FONT_FALLBACK)
local function SlugText(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ring = ns.CreateSlugRing(parent, fs, "ARTWORK")
  ns.ApplyTextOutlineStyle(fs, ring, ns.FONT_FALLBACK, size, "SLUG")
  return fs
end

-- Nom affiche d'une entree : son nom propre, sinon celui de sa section, sinon celui de sa page.
local function EntryName(e)
  if not e then return "" end
  local key = e.name or e.section
  if key and L[key] then return L[key] end
  return (ns.SettingsCategoryLabel and ns.SettingsCategoryLabel(e.category)) or e.category or ""
end

-- Saut vers la section de reglages du module survole (page ouverte, section depliee), clic droit.
local function GoToSettings()
  if not hoveredCategory then return end
  -- Pre-selection propre a l'entree (ex. quelle Extra Barre), avant d'ouvrir la page
  if hoveredEntry and hoveredEntry.onGo then hoveredEntry.onGo() end
  local panel = ns.SettingsPanel
  if panel and panel.GoToElement then
    local section = hoveredEntry and hoveredEntry.section and L[hoveredEntry.section]
    panel:GoToElement(hoveredCategory, section and section:upper(), hoveredEntry and hoveredEntry.scrollTo)
  elseif panel and panel.SelectCategory then
    if not panel:IsShown() then panel:ShowUI() end
    panel:SelectCategory(hoveredCategory)
  end
  -- Page deja affichee : elle ne repasse pas par OnShow, rafraichissement explicite
  if hoveredCategory == "extraBars" and ns.ExtraBarsPageRefresh then ns.ExtraBarsPageRefresh() end
  if hoveredCategory == "unitBars" and ns.UnitBarsPageRefresh then ns.UnitBarsPageRefresh() end
  if hoveredCategory == "castBars" and ns.CastBarsPageRefresh then ns.CastBarsPageRefresh() end
  if hoveredCategory == "actionBars" and ns.ActionBarsPageRefresh then ns.ActionBarsPageRefresh() end
  if hoveredCategory == "outOfCombat" and ns.OOCPageRefresh then ns.OOCPageRefresh() end
end

local function EnsureWidgets()
  if highlight then return end

  -- "Button" (pas "Frame") pour capter le clic droit sur tout le highlight.
  highlight = CreateFrame("Button", "AishCoreModuleHoverHighlight", UIParent, "BackdropTemplate")
  highlight:SetFrameStrata("TOOLTIP")
  highlight:EnableMouse(true)
  highlight:RegisterForClicks("RightButtonUp")
  highlight:SetScript("OnClick", function(_, button)
    if button == "RightButton" then GoToSettings() end
  end)
  -- Le highlight au-dessus de tout capterait aussi le clic gauche du drag natif du module en
  -- dessous : SetPropagateMouseClicks laisse passer le clic gauche, garde le droit pour nous.
  highlight:SetScript("OnMouseDown", function(self, button)
    self:SetPropagateMouseClicks(button == "LeftButton")
  end)
  highlight:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  -- Niveaux : fond (1) < lueur (2) < cadres de la page Modules (10) < textes (LVL_TEXT). La lueur, additive, ne doit
  -- jamais passer sur un texte : elle eclaircirait l'anneau noir du contour SLUG.
  highlight:SetFrameLevel(1)
  -- Lueur "Lueur" (Couleurs Thematiques) autour de l'element survole
  highlight._glow = BuildGlow(highlight, highlight, 6, 0.9)
  highlight._glow:SetFrameLevel(2)
  -- Nom de l'element, au-dessus du coin haut-gauche (a l'exterieur du cadre). Sur la page Modules, le cadre de
  -- chaque element porte deja son nom (cf. BoxFor) : celui-ci est alors masque.
  local txt = CreateFrame("Frame", nil, highlight)
  txt:SetAllPoints(highlight)
  txt:SetFrameLevel(LVL_TEXT)
  highlight.nameText = SlugText(txt, 10)
  highlight.nameText:SetPoint("BOTTOMLEFT", highlight, "TOPLEFT", 2, 2)
  -- Aide "Clic droit : Regler" au centre de l'element (sous lui s'il est trop petit), en fondu a chaque survol
  -- (cadre propre : l'anneau SLUG suit l'alpha)
  local hint = CreateFrame("Frame", nil, highlight)
  hint:SetAllPoints(highlight)
  hint:SetFrameLevel(LVL_TEXT)
  hint.text = SlugText(hint, 8)
  hint.text:SetText(L["MODULEHOVER_HINT"])
  hint.text:SetTextColor(0.9, 0.9, 0.9, 1)
  local ag = hint:CreateAnimationGroup()
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(0); fade:SetToAlpha(0.85); fade:SetDuration(0.35); fade:SetSmoothing("OUT")
  ag:SetToFinalAlpha(true)
  highlight._hint, highlight._hintAG = hint, ag
  highlight:Hide()
end

local function ShowHighlight(frame, category, onModulesPage)
  EnsureWidgets()
  hoveredFrame    = frame
  hoveredCategory = category
  highlight.nameText:SetText(EntryName(hoveredEntry))
  highlight.nameText:SetShown(not onModulesPage)
  -- Fond noir a 50 % (masque l'element, l'aide "Clic droit" reste lisible) ; nom : couleur des hitbox
  -- (ns.HitboxColor) ; liseré et lueur : "Lueur" des Couleurs Thematiques
  local r, g, b = ns.HitboxColor()
  local gr, gg, gb = GlowRGB()
  highlight:SetBackdropColor(0, 0, 0, 0.5)
  highlight:SetBackdropBorderColor(r, g, b, 1)
  highlight._glow:SetGlowColor(gr, gg, gb)
  highlight.nameText:SetTextColor(NameRGB())
  highlight:ClearAllPoints()
  highlight:SetPoint("TOPLEFT", frame, "TOPLEFT", -HL_PAD, HL_PAD)
  highlight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", HL_PAD, -HL_PAD)
  highlight:Show()
  -- Au centre si le cadre a la place (taille lisible : celle des conteneurs d'auras peut etre secrete), sinon dessous
  local hintText = highlight._hint.text
  local inside = false
  pcall(function()
    local w, h = frame:GetSize()
    inside = w >= hintText:GetStringWidth() + 12 and h >= hintText:GetStringHeight() + 8
  end)
  hintText:ClearAllPoints()
  if inside then
    hintText:SetPoint("CENTER", frame, "CENTER", 0, 0)
  else
    hintText:SetPoint("TOP", highlight, "BOTTOM", 0, -3)
  end
  highlight._hint:SetAlpha(0)
  highlight._hintAG:Stop()
  highlight._hintAG:Play()
end

local function HideHighlight()
  hoveredFrame    = nil
  hoveredCategory = nil
  if highlight then highlight:Hide() end
end

-- IsVisible() ne regarde QUE la chaine Show/Hide -- il reste vrai a alpha 0. Or la plupart des modules
-- de cet addon se masquent par SetAlpha(0) et jamais par Hide() (seul moyen sur pour une frame securisee
-- en combat, cf. PriorityBar.SafeHideContainers). Un module desactive gardait donc sa hitbox de survol :
-- le highlight apparaissait sur du vide. On exige donc aussi une opacite effective.
-- Seuil bas (pas > 0) : plusieurs modules ont un fondu hors combat legitime a 0.3/0.4, il ne faut pas
-- les rendre insurvolables. A l'inverse un module desactive est exactement a 0.
local MIN_HOVER_ALPHA = 0.05
local function IsEffectivelyVisible(frame)
  local okA, alpha = pcall(frame.GetEffectiveAlpha, frame)
  if not okA or type(alpha) ~= "number" then return true end -- doute : on garde l'ancien comportement
  return alpha > MIN_HOVER_ALPHA
end

-- PAGE "MODULES" : un cadre fin sur CHAQUE element de l'addon, meme masque ou desactive, pour les reperer
-- d'un coup d'oeil. Le cadre est ancre sur l'element (pas de lecture de position : celle des conteneurs
-- natifs d'auras est souvent secrete) et sert aussi a la detection du survol dans ce mode.
local boxes = {}
local function ModulesPageActive()
  local panel = ns.SettingsPanel
  return panel and panel.GetActiveCategory and panel:GetActiveCategory() == "modulesOverview"
end

local function BoxFor(i)
  local b = boxes[i]
  if b then return b end
  b = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  b:SetFrameStrata("TOOLTIP")
  b:EnableMouse(false)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(0.2, 0.6, 1, 0.05)
  b:SetBackdropBorderColor(0.35, 0.75, 1, 0.55)
  b:SetFrameLevel(10)

  -- Nom de l'element, toujours affiche au-dessus du coin haut-gauche (au-dessus des lueurs, cf. LVL_TEXT)
  local txt = CreateFrame("Frame", nil, b)
  txt:SetAllPoints(b)
  txt:SetFrameLevel(LVL_TEXT + 1)
  b._name = SlugText(txt, 10)
  b._name:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 1, 2)

  -- Lueur "Lueur" (module survole dans la liste de la page), pulsation douce
  local glow = BuildGlow(b, b, 6, 0.8)
  glow:SetFrameLevel(11)
  local ag = glow:CreateAnimationGroup()
  ag:SetLooping("BOUNCE")
  local fade = ag:CreateAnimation("Alpha")
  fade:SetFromAlpha(1); fade:SetToAlpha(0.35); fade:SetDuration(0.7); fade:SetSmoothing("IN_OUT")
  glow:Hide()
  b._glow, b._glowAG = glow, ag

  boxes[i] = b
  return b
end

-- Module survole dans la liste de la page Modules (cf. MakeModuleRow) : ses cadres brillent
local focusMod = nil
function ns.ModuleHoverFocus(id) focusMod = id end

local function EntryMatches(e, id)
  if not id then return false end
  local mod = e.mod or e.category
  if mod == id then return true end
  -- "Cadres d'unite" (ligne parente) : toutes les barres
  if id == "unitBars" and e.category == "unitBars" then return true end
  if id == "fishing" and e.category == "fishing" then return true end   -- "Peche" : appat et bouton
  if id == "outOfCombat" and e.category == "outOfCombat" then return true end   -- les trois cercles hors combat
  return false
end

-- Cadre "cercle de puissance", nom "texte de puissance", lueur (module mis en avant depuis la liste) "Lueur".
-- Reappliques seulement si une couleur change (spe, reglage).
local function StyleBox(b, lit)
  local r, g, bl = ns.HitboxColor()
  local tr, tg, tb = NameRGB()
  local key = string.format("%s|%.3f%.3f%.3f|%.3f%.3f%.3f", tostring(lit), r, g, bl, tr, tg, tb)
  if b._styleKey == key then return end
  b._styleKey = key
  b:SetBackdropColor(r, g, bl, lit and 0.15 or 0.05)
  b:SetBackdropBorderColor(r, g, bl, lit and 1 or 0.55)
  b._name:SetTextColor(tr, tg, tb, 1)
  if lit and not b._lit then
    b._glow:SetGlowColor(GlowRGB())
    b._glow:Show(); b._glowAG:Play()
  elseif not lit and b._lit then
    b._glowAG:Stop(); b._glow:Hide()
  end
  b._lit = lit and true or false
end

local function HideBoxes()
  for _, b in ipairs(boxes) do b:Hide(); b._target = nil end
end

-- Module de l'entree active (cf. ns.ModuleEntryEnabled, page Modules) ; inconnu : considere actif
local function ModuleOn(e)
  local f = ns.ModuleEntryEnabled
  if not f then return true end
  local ok, v = pcall(f, e.mod or e.category)
  return not ok or v ~= false
end

-- Renvoie l'entree survolee (cadre le plus petit) parmi tous les elements, visibles ou non (modules coupes exclus).
-- Opacite : 30 % au repos, 100 % pour la hitbox survolee (ou mise en avant depuis la liste de la page).
local BOX_IDLE_ALPHA = 0.3
local function UpdateBoxes(overPanel)
  local best, bestArea, bestE, bestBox
  local n = 0
  for _, e in ipairs(BuildEntries()) do
    local ok, frame = pcall(e.getFrame)
    if ok and frame and ModuleOn(e) then
      n = n + 1
      local b = BoxFor(n)
      if b._target ~= frame then
        b._target = frame
        b:ClearAllPoints()
        pcall(b.SetAllPoints, b, frame)
      end
      local nm = EntryName(e)
      if b._nameStr ~= nm then b._nameStr = nm; b._name:SetText(nm) end
      b:Show()
      StyleBox(b, EntryMatches(e, focusMod))
      if not overPanel and b:IsMouseOver() then
        local okS, w, h = pcall(b.GetSize, b)
        local area = (okS and type(w) == "number" and type(h) == "number") and (w * h) or math.huge
        if not best or area < bestArea then best, bestArea, bestE, bestBox = frame, area, e, b end
      end
    end
  end
  for i = n + 1, #boxes do boxes[i]:Hide(); boxes[i]._target = nil end
  for i = 1, n do
    local b = boxes[i]
    b:SetAlpha((b == bestBox or b._lit) and 1 or BOX_IDLE_ALPHA)
  end
  return best, bestE
end

-- DRIVER : ticker leger, actif uniquement pendant que le panneau est ouvert.
local TICK_INTERVAL = 0.05
local ticker

local function Tick()
  local panel = ns.SettingsPanel
  -- GUI minimise : plus de hitbox, les elements retrouvent leur survol normal (ex. tooltip de la barre d'XP)
  if not panel or not panel:IsShown() or panel._minimized then
    HideHighlight()
    HideBoxes()
    return
  end
  local modulesPage = ModulesPageActive()
  local boxBest, boxBestE
  if modulesPage then boxBest, boxBestE = UpdateBoxes(ns.IsFrameMouseOver(panel)) else HideBoxes() end
  -- Ne pas "survoler" un module a travers le panneau d'options lui-meme :
  -- le curseur est au-dessus de la fenetre GUI, pas du jeu en dessous.
  if ns.IsFrameMouseOver(panel) then
    HideHighlight()
    return
  end
  -- Quand 2 frames survolables se chevauchent, on garde celle avec la plus petite aire :
  -- la plus specifique/imbriquee gagne, conforme a l'intuition visuelle.
  local best, bestArea, bestE
  if modulesPage then
    -- Page Modules : tous les elements comptent, meme caches (detection par leur cadre)
    best, bestE = boxBest, boxBestE
  else
    for _, e in ipairs(BuildEntries()) do
      local ok, frame = pcall(e.getFrame)
      if ok and frame and frame:IsVisible() and IsEffectivelyVisible(frame) and ns.IsFrameMouseOver(frame) then
        local w, h = frame:GetSize()
        local area = (w or 0) * (h or 0)
        if not best or area < bestArea then
          best, bestArea, bestE = frame, area, e
        end
      end
    end
  end

  if best then
    if hoveredFrame ~= best then
      hoveredEntry = bestE
      ShowHighlight(best, bestE.category, modulesPage)
    end
  else
    HideHighlight()
  end
end

local function Start()
  if ticker then return end
  ticker = ns.NewTicker(TICK_INTERVAL, Tick)
end

local function Stop()
  if ticker then ticker:Cancel(); ticker = nil end
  HideHighlight()
  HideBoxes()
end

-- Le panneau d'options est charge avant ce fichier ; C_Timer.After(0, ...) reste une garde defensive.
C_Timer.After(0, function()
  local panel = ns.SettingsPanel or _G["AishCoreSettingsPanel"]
  if not panel then return end
  panel:HookScript("OnShow", Start)
  panel:HookScript("OnHide", Stop)
  if panel:IsShown() then Start() end
end)

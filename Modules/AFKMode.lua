-- Modules/AFKMode.lua : ecran AFK personnalise (modele 3D, timer, blasons, camera).
-- Elements configurables via ns.DB.afkMode.elements[cle], cf. UI/SettingsPanel.lua:BuildAFKMode.
local addonName, ns = ...
local L = ns.L

local AFKMode = {}
ns.Modules.AFKMode = AFKMode

local GetTime, floor, format, date, random = GetTime, floor, format, date, random
local UnitIsAFK, UnitCastingInfo, InCombatLockdown = UnitIsAFK, UnitCastingInfo, InCombatLockdown
local UnitClass, UnitRace, UnitFactionGroup, UnitLevel = UnitClass, UnitRace, UnitFactionGroup, UnitLevel
local UnitName, GetGuildInfo, IsInGuild = UnitName, GetGuildInfo, IsInGuild
local MoveViewLeftStart, MoveViewLeftStop = MoveViewLeftStart, MoveViewLeftStop
local CloseAllWindows, GetBattlefieldStatus = CloseAllWindows, GetBattlefieldStatus
local C_Timer, CreateFrame = C_Timer, CreateFrame

-- Textures : blasons classe / faction / race / extension (Media/AFK/)
local AFK_TEX_BASE = "Interface\\AddOns\\AishCore\\Media\\AFK\\"

-- Extension par categorie/style : race/factioncrest "blizzard" en .blp, le reste en .tga
local AFK_TEX_EXT = {
  classes      = { ["releaf-flat"] = "tga", sltheme = "tga" },
  race         = { blizzard = "blp", ["releaf-flat"] = "tga", sltheme = "tga" },
  factioncrest = { blizzard = "blp", ["releaf-flat"] = "tga", sltheme = "tga" },
  factionlogo  = { blizzard = "tga", ["releaf-flat"] = "tga", sltheme = "tga" },
  expansion    = { blizzard = "tga", ["releaf-flat"] = "tga", sltheme = "tga" },
}

-- Mechagnome -> fichier MechaGnome.blp (seule divergence connue du set)
local RACE_FILE_OVERRIDE = { Mechagnome = "MechaGnome" }

-- Jetons par extension WoW : seul "blizzard" a un fichier par extension
local EXPANSION_TOKENS = {
  [LE_EXPANSION_CLASSIC]                 = "classic",
  [LE_EXPANSION_BURNING_CRUSADE]         = "tbc",
  [LE_EXPANSION_WRATH_OF_THE_LICH_KING]  = "wotlk",
  [LE_EXPANSION_CATACLYSM]               = "cata",
  [LE_EXPANSION_MISTS_OF_PANDARIA]       = "mop",
  [LE_EXPANSION_WARLORDS_OF_DRAENOR]     = "wod",
  [LE_EXPANSION_LEGION]                  = "legion",
  [LE_EXPANSION_BATTLE_FOR_AZEROTH]      = "bfa",
  [LE_EXPANSION_SHADOWLANDS]             = "sl",
  [LE_EXPANSION_DRAGONFLIGHT]            = "df",
}
local EXPANSION_STYLE_TOKENS = {
  blizzard        = { classic=true, tbc=true, wotlk=true, cata=true, mop=true, wod=true, legion=true, bfa=true, sl=true, df=true },
  ["releaf-flat"] = { sl = true },
  sltheme         = { sl = true },
}

local function ResolveTexturePath(category, style, token, override)
  if not token or not style then return nil end
  local ext = AFK_TEX_EXT[category] and AFK_TEX_EXT[category][style]
  if not ext then return nil end
  local file = override and override[token] or token
  return AFK_TEX_BASE .. category .. "\\" .. style .. "\\" .. file .. "." .. ext
end

local function ResolveExpansionTexture(style)
  if style == "auto" then return nil end
  local token = EXPANSION_TOKENS[GetClientDisplayExpansionLevel and GetClientDisplayExpansionLevel() or 0]
  if not token or not (EXPANSION_STYLE_TOKENS[style] and EXPANSION_STYLE_TOKENS[style][token]) then
    return nil -- pas de fichier pour ce style/cette extension -> fallback auto
  end
  return AFK_TEX_BASE .. "expansion\\" .. style .. "\\" .. token .. ".tga"
end

-- Animations du modele 3D (id natifs Blizzard). "wait" = pause avant de rejouer
-- une fois finie ; garder a 0 pour toutes (sinon le perso reste en idle trop longtemps).
local MODEL_ANIMATIONS = {
  wave   = { id = 67,   facing = 6,   wait = 0,  duration = 2.3 },
  lean   = { id = 1260, facing = 5.8, wait = 0,  duration = 600 },
  dance  = { id = 69,   facing = 6,   wait = 0,  duration = 300 },
  salute = { id = 113,  facing = 6,   wait = 0,  duration = 5 },
  talk   = { id = 60,   facing = 6.2, wait = 0,  duration = 10 },
  shy    = { id = 83,   facing = 6.2, wait = 0,  duration = 10 },
  roar   = { id = 74,   facing = 6,   wait = 0,  duration = 5 },
  -- Bouclees (4=Walk, 5=Run, 25=ReadyUnarmed) : duration longue = jamais de repli idle
  walk         = { id = 4,  facing = 6, wait = 0, duration = 999999 },
  run          = { id = 5,  facing = 6, wait = 0, duration = 999999 },
  battlestance = { id = 25, facing = 6, wait = 0, duration = 999999 },
}
local REAL_ANIM_KEYS = { "wave", "dance", "salute", "talk", "shy", "roar", "lean", "walk", "run", "battlestance" }
AFKMode.MODEL_ANIMATIONS = MODEL_ANIMATIONS
AFKMode.REAL_ANIM_KEYS = REAL_ANIM_KEYS

local function ResolveAnimKey(cfg)
  if cfg.modelAnim == "random" then
    return REAL_ANIM_KEYS[random(#REAL_ANIM_KEYS)]
  end
  return cfg.modelAnim
end

-- Touches ignorees pour la sortie AFK au clavier (copie depuis AFK.lua natif)
local ignoreKeys = { LALT = true, LSHIFT = true, RSHIFT = true }
local printKeys  = { PRINTSCREEN = true }
if IsMacClient and IsMacClient() then printKeys[_G.KEY_PRINTSCREEN_MAC] = true end

-- Elements configurables (textes + blasons) : panneau, ancrage par defaut, categorie de texture.
-- Valeurs par defaut (font/size/color/anchor/x/y/width/height) : Config/Defaults.lua:afkMode.elements
local TEXT_ELEMENTS = {
  { key = "timer",       panel = "top",    anchor = "TOP" },
  { key = "playerName",  panel = "bottom", anchor = "BOTTOMLEFT" },
  { key = "playerClass", panel = "bottom", anchor = "BOTTOMLEFT" },
  { key = "playerLevel", panel = "bottom", anchor = "BOTTOMLEFT" },
  { key = "guild",       panel = "bottom", anchor = "BOTTOMLEFT" },
  { key = "date",        panel = "top",    anchor = "TOPRIGHT" },
  { key = "time",        panel = "top",    anchor = "TOPRIGHT" },
}
local GRAPHIC_ELEMENTS = {
  { key = "crestClass",    panel = "bottom", anchor = "BOTTOMRIGHT", category = "classes" },
  { key = "crestFaction",  panel = "bottom", anchor = "BOTTOMRIGHT", category = "factioncrest" },
  { key = "logoFaction",   panel = "bottom", anchor = "BOTTOMLEFT",  category = "factionlogo" },
  { key = "crestRace",     panel = "bottom", anchor = "BOTTOMRIGHT", category = "race" },
  { key = "logoExpansion", panel = "top",    anchor = "TOPLEFT",     category = "expansion" },
  { key = "aishLogo",      panel = "top",    anchor = "TOPRIGHT",    category = nil }, -- texture fixe, pas de style
}
-- Logo AishCore (meme fichier que l'en-tete du panneau de reglages)
local AISH_LOGO_PATH = "Interface\\AddOns\\AishCore\\Media\\Logo\\AishUILogo"
AFKMode.TEXT_ELEMENTS    = TEXT_ELEMENTS
AFKMode.GRAPHIC_ELEMENTS = GRAPHIC_ELEMENTS

-- Etat interne
local frame          -- overlay plein ecran
local topPanel, bottomPanel
local modelHolder, model
local chatFrame, tipsFrame
local texts    = {} -- [elementKey] -> FontString
local textSlugs = {} -- [elementKey] -> anneau SLUG (cf. ns.CreateSlugRing)
local graphics = {} -- [elementKey] -> Texture
local eventFrame
local timerElapsed, tipsElapsed, elapsedSeconds = 0, 0, 0
local isPreview = false -- true pendant l'apercu GUI (SetPreview), distinct du vrai AFK (AFKMode.isAFK)

local function Cfg()
  return ns.GetCfg("afkMode") or {}
end

-- ns.GetCfg ne fusionne qu'au 1er niveau : on fusionne Defaults + DB explicitement par element
local function ElemCfg(key)
  local defCfg = ns.Defaults and ns.Defaults.afkMode and ns.Defaults.afkMode.elements and ns.Defaults.afkMode.elements[key]
  local dbCfg  = ns.DB and ns.DB.afkMode and ns.DB.afkMode.elements and ns.DB.afkMode.elements[key]
  if not dbCfg then return defCfg or {} end
  if not defCfg then return dbCfg end
  local merged = {}
  for k, v in pairs(defCfg) do merged[k] = v end
  for k, v in pairs(dbCfg) do merged[k] = v end
  return merged
end
AFKMode.ElemCfg = ElemCfg

-- Modele 3D : animation d'entree + boucle idle
local function SetModelAnimation(key)
  if not model then return end
  local cfg = Cfg()
  local opt = MODEL_ANIMATIONS[key] or MODEL_ANIMATIONS.wave
  model.curAnimation = key
  model.duration     = opt.duration
  model.idleDuration = opt.wait
  model.startTime    = GetTime()
  model.isIdle       = nil
  model:SetFacing(opt.facing + (cfg.modelRotation or 0))
  model:SetAnimation(opt.id)
end

local function ModelOnUpdate(self)
  if self.isIdle then return end
  if (GetTime() - self.startTime) >= self.duration then
    -- wait <= 0 : boucle immediate (evite un flash d'idle sur les anims courtes)
    if self.idleDuration and self.idleDuration > 0 then
      self:SetAnimation(0)
      self.isIdle = true
      C_Timer.After(self.idleDuration, function()
        if (AFKMode.isAFK or isPreview) and model.curAnimation then
          SetModelAnimation(model.curAnimation)
        end
      end)
    elseif model.curAnimation then
      SetModelAnimation(model.curAnimation)
    end
  end
end

-- Style commun texte/blason : ancrage sur le MEME point que le panneau parent, decale de x/y.
-- Toujours ancre au frame plein ecran (jamais topPanel/bottomPanel, trop petits pour les coins).
local function AnchorElement(widget, panelKey, def, ec)
  local anchor = ec.anchor or def.anchor
  widget:ClearAllPoints()
  widget:SetPoint(anchor, frame, anchor, ec.x or 0, ec.y or 0)
end

-- Justification deduite du point d'ancrage : gauche/droite pour les coins, centre pour TOP/BOTTOM
local JUSTIFY_BY_ANCHOR = {
  TOPLEFT = "LEFT", BOTTOMLEFT = "LEFT",
  TOP = "CENTER", BOTTOM = "CENTER",
  TOPRIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
}

-- Largeur fixe requise pour que SetJustifyH ait un effet (sinon le FontString s'auto-dimensionne au texte)
local TEXT_ELEMENT_WIDTH = 400

-- Si useSpecColor est coche, pioche la couleur dans ns.Modules.Colors (specColorKey) sinon ec.color/fallback
local function ResolveElementColor(ec, fallback)
  if ec.useSpecColor then
    local CLR = ns.Modules and ns.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get(ec.specColorKey or "powercircle")
    if c then return c end
  end
  return ec.color or fallback or {1, 1, 1, 1}
end

local function ApplyTextStyle(key, def)
  local ec = ElemCfg(key)
  local fs = texts[key]
  fs:SetShown(ec.enable and true or false)
  if not ec.enable then return end
  ns.ApplyTextOutlineStyle(fs, textSlugs[key], ec.font or ns.Media.font, ec.size or 14, ec.outlineStyle)
  local c = ResolveElementColor(ec)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  local anchor = ec.anchor or def.anchor
  fs:SetWidth(TEXT_ELEMENT_WIDTH)
  fs:SetJustifyH(JUSTIFY_BY_ANCHOR[anchor] or "CENTER")
  AnchorElement(fs, def.panel, def, ec)
end

-- Textes dynamiques : contenu + style recalcules a chaque appel (1x/seconde max)
-- Couleur d'accent (date, heure, guilde) : cfg.accentColor, ou couleur theme de la spe si coche
local function AccentColor()
  local cfg = Cfg()
  if cfg.useThemeColors then
    local CLR = ns.Modules and ns.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get(cfg.themeColorKey or "powertext")
    if c then return c end
  end
  return cfg.accentColor or { 0, 0.667, 1, 1 }
end

local function AccentHex()
  local c = AccentColor()
  return format("%02x%02x%02x", (c[1] or 0) * 255, (c[2] or 0) * 255, (c[3] or 0) * 255)
end

-- Date/heure dans la langue du CLIENT WoW via les tables L["AFKMODE_MONTHS"/"AFKMODE_WEEKDAYS"]
local function LocalizedDateString()
  local hex = AccentHex()
  local t = date("*t")
  local months   = L["AFKMODE_MONTHS"]
  local weekdays = L["AFKMODE_WEEKDAYS"]
  local monthName   = months and months[t.month]
  local weekdayName = weekdays and weekdays[t.wday]
  if monthName and weekdayName then
    local fmt = ElemCfg("date").format
    if fmt == "monthDay" then
      return format("%s %d, |cff" .. hex .. "%s|r", monthName, t.day, weekdayName)
    elseif fmt == "weekdayFirst" then
      return format("|cff" .. hex .. "%s|r %d %s", weekdayName, t.day, monthName)
    end
    return format("%d %s, |cff" .. hex .. "%s|r", t.day, monthName, weekdayName)
  end
  return date("%d %B, |cff" .. hex .. "%A|r") -- repli : locale systeme
end

local function RefreshDateTime()
  local def = TEXT_ELEMENTS[6] -- "date"
  ApplyTextStyle("date", def)
  if ElemCfg("date").enable then
    texts.date:SetText(LocalizedDateString())
  end

  ApplyTextStyle("time", TEXT_ELEMENTS[7])
  if ElemCfg("time").enable then
    local hex = AccentHex()
    texts.time:SetText(date("%H|cff" .. hex .. ":|r%M|cff" .. hex .. ":|r%S"))
  end
end

local function RefreshTimerText()
  local cfg = Cfg()
  ApplyTextStyle("timer", TEXT_ELEMENTS[1])
  local ec = ElemCfg("timer")
  if not ec.enable then return end

  local fs = texts.timer
  local minutes = floor(elapsedSeconds / 60)
  local seconds = elapsedSeconds % 60
  if cfg.timerCountdown then
    local remain = 1800 - elapsedSeconds -- 30 min avant deconnexion AFK Blizzard
    if remain <= 0 then
      fs:SetFormattedText("%s : |cffff0000%s|r", L["AFKMODE_LOGOUT_IN"] or "Logout in", "00:00")
    else
      fs:SetFormattedText("%s : %02d:%02d", L["AFKMODE_LOGOUT_IN"] or "Logout in", floor(remain / 60), remain % 60)
    end
  else
    fs:SetFormattedText("%02d:%02d", minutes, seconds)
  end
end

-- Astuces defilantes
local lastTipIndex
local function ShowNextTip()
  local tips = L["AFKMODE_TIPS"]
  if not tips or #tips == 0 then return end
  local idx = random(1, #tips)
  if #tips > 1 then
    while idx == lastTipIndex do idx = random(1, #tips) end
  end
  lastTipIndex = idx
  local c = ResolveElementColor(ElemCfg("tips"))
  tipsFrame:AddMessage(tips[idx], c[1], c[2], c[3])
end

-- Textes statiques (nom/classe/niveau/guilde) : recalcules a chaque affichage, pas a chaque tick
local function RefreshTextStrings()
  local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
  local r, g, b = 1, 1, 1
  if classColor then r, g, b = classColor.r, classColor.g, classColor.b end

  ApplyTextStyle("playerName", TEXT_ELEMENTS[2])
  if ElemCfg("playerName").enable then
    -- useSpecColor : couleur du module Couleurs (specColorKey) au lieu de la couleur de classe
    local nameEc = ElemCfg("playerName")
    local specColor = nameEc.useSpecColor and ns.Modules.Colors and ns.Modules.Colors.Get
      and ns.Modules.Colors.Get(nameEc.specColorKey or "powercircle")
    if specColor then
      texts.playerName:SetTextColor(specColor[1], specColor[2], specColor[3])
    else
      texts.playerName:SetTextColor(r, g, b)
    end
    texts.playerName:SetText((UnitName("player")))
  end

  ApplyTextStyle("playerClass", TEXT_ELEMENTS[3])
  if ElemCfg("playerClass").enable then
    local _, classFile = UnitClass("player")
    local className = classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] or ""
    texts.playerClass:SetText(className)
  end

  ApplyTextStyle("playerLevel", TEXT_ELEMENTS[4])
  if ElemCfg("playerLevel").enable then
    texts.playerLevel:SetFormattedText("%s %d", LEVEL or "Level", UnitLevel("player"))
  end

  ApplyTextStyle("guild", TEXT_ELEMENTS[5])
  if ElemCfg("guild").enable then
    if IsInGuild() then
      local gName, gRank = GetGuildInfo("player")
      texts.guild:SetFormattedText("|cff" .. AccentHex() .. "<%s>|r %s", gName or "", gRank or "")
    else
      texts.guild:SetText(L["AFKMODE_NO_GUILD"] or NO_GUILD or "")
    end
  end

  local tipsEc = ElemCfg("tips")
  tipsFrame:SetShown(tipsEc.enable and true or false)
  if tipsEc.enable then
    tipsFrame:SetFont(tipsEc.font or ns.Media.fontGui, tipsEc.size or 11, "")
    tipsFrame:SetWidth(tipsEc.lineWidth or 500) -- largeur de retour a la ligne
    tipsFrame:SetJustifyH(JUSTIFY_BY_ANCHOR[tipsEc.anchor] or "CENTER")
    AnchorElement(tipsFrame, "bottom", { panel = "bottom", anchor = "BOTTOM" }, tipsEc)
    tipsFrame:Clear()
    ShowNextTip() -- affiche la 1ere tout de suite, sans attendre tipThrottle
  end

  RefreshDateTime()
  RefreshTimerText()
end

-- Blasons / logos
local function ApplyGraphicStyle(key, def, texturePath)
  local ec = ElemCfg(key)
  local tex = graphics[key]
  local shown = ec.enable and texturePath and true or false
  tex:SetShown(shown)
  if not shown then return end
  tex:SetSize(ec.width or 40, ec.height or 40)
  AnchorElement(tex, def.panel, def, ec)
  tex:SetTexture(texturePath)
end

local function RefreshGraphics()
  local _, classToken = UnitClass("player")
  local _, raceToken  = UnitRace("player")
  local faction        = UnitFactionGroup("player") or "Neutral"

  local TOKEN_BY_KEY = {
    crestClass   = classToken,
    crestFaction = faction,
    logoFaction  = faction,
    crestRace    = raceToken,
  }

  for _, def in ipairs(GRAPHIC_ELEMENTS) do
    local ec = ElemCfg(def.key)
    if def.key == "logoExpansion" then
      local path = nil
      if ec.enable then
        path = ResolveExpansionTexture(ec.style)
        if not path and GetExpansionDisplayInfo and GetClientDisplayExpansionLevel then
          local info = GetExpansionDisplayInfo(GetClientDisplayExpansionLevel())
          path = info and info.logo
        end
      end
      ApplyGraphicStyle(def.key, def, path)
    elseif def.key == "aishLogo" then
      ApplyGraphicStyle(def.key, def, ec.enable and AISH_LOGO_PATH or nil)
    else
      local override = (def.key == "crestRace") and RACE_FILE_OVERRIDE or nil
      local path = ec.enable and ResolveTexturePath(def.category, ec.style, TOKEN_BY_KEY[def.key], override) or nil
      ApplyGraphicStyle(def.key, def, path)
    end
  end
end

-- Animation d'entree des panneaux (Slide) via AnimationGroup natif
local function AnchorTopNatural()
  topPanel:ClearAllPoints()
  topPanel:SetPoint("TOP", frame, "TOP", 0, 0)
end

local function AnchorBottomNatural()
  bottomPanel:ClearAllPoints()
  bottomPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
end

local function PlayPanelAnimations()
  local cfg = Cfg()

  -- Toujours repartir de la position naturelle (ancrage au bord de l'ecran)
  AnchorTopNatural()
  AnchorBottomNatural()
  topPanel:SetAlpha(1); bottomPanel:SetAlpha(1)

  if cfg.animType == "none" or (cfg.animTime or 0) <= 0 then return end

  if not topPanel.anim then
    topPanel.anim  = topPanel:CreateAnimationGroup()
    topPanel.slide = topPanel.anim:CreateAnimation("Translation")
    -- OnFinished requis : sinon le panneau flashe puis redisparait hors ecran
    topPanel.anim:SetScript("OnFinished", AnchorTopNatural)

    bottomPanel.anim  = bottomPanel:CreateAnimationGroup()
    bottomPanel.slide = bottomPanel.anim:CreateAnimation("Translation")
    bottomPanel.anim:SetScript("OnFinished", AnchorBottomNatural)
  end

  local screenW = GetScreenWidth()
  local topH, bottomH = topPanel:GetHeight(), bottomPanel:GetHeight()

  if cfg.animType == "slideSide" then
    -- Depart hors ecran (gauche/droite), l'offset ramene au point naturel
    topPanel:ClearAllPoints();    topPanel:SetPoint("TOP", frame, "TOP", -screenW, 0)
    bottomPanel:ClearAllPoints(); bottomPanel:SetPoint("BOTTOM", frame, "BOTTOM", screenW, 0)
    topPanel.slide:SetOffset(screenW, 0)
    bottomPanel.slide:SetOffset(-screenW, 0)
  else -- "slideIn" (vertical, defaut) : depart hors ecran (haut/bas)
    topPanel:ClearAllPoints();    topPanel:SetPoint("TOP", frame, "TOP", 0, topH)
    bottomPanel:ClearAllPoints(); bottomPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, -bottomH)
    topPanel.slide:SetOffset(0, -topH)
    bottomPanel.slide:SetOffset(0, bottomH)
  end

  topPanel.slide:SetDuration(cfg.animTime)
  bottomPanel.slide:SetDuration(cfg.animTime)
  topPanel.slide:SetSmoothing(cfg.animBounce and "OUT" or "NONE")
  bottomPanel.slide:SetSmoothing(cfg.animBounce and "OUT" or "NONE")

  topPanel.anim:Play()
  bottomPanel.anim:Play()
end

-- OnUpdate : timer, astuces, boucle du modele
local function OnFrameUpdate(_, elapsed)
  if not (AFKMode.isAFK or isPreview) then return end
  local cfg = Cfg()

  timerElapsed = timerElapsed + elapsed
  if timerElapsed >= 1 then
    local ticks = floor(timerElapsed)
    elapsedSeconds = elapsedSeconds + ticks
    timerElapsed = timerElapsed - ticks
    RefreshTimerText()
    RefreshDateTime()
  end

  if ElemCfg("tips").enable then
    tipsElapsed = tipsElapsed + elapsed
    if tipsElapsed >= (cfg.tipThrottle or 12) then
      tipsElapsed = 0
      ShowNextTip()
    end
  end
end

-- Bascule visuelle (affichage plein ecran + camera + chat)
function AFKMode:SetAFKState(status)
  if not frame then
    print("|cffff4444[AishCore AFKMode]|r SetAFKState appele avant Create() -- module non initialise (voir /aish diag on)")
    return
  end
  local cfg = Cfg()
  if not cfg.enabled then return end

  if status then
    if AFKMode.isAFK then return end

    -- pcall : evite qu'une erreur laisse UIParent masque en permanence
    local ok, err = pcall(function()
      CloseAllWindows()
      if cfg.cameraSpin then MoveViewLeftStart(0.035) end

      RefreshTextStrings()
      RefreshGraphics()

      if cfg.modelEnabled then
        model:Show()
        SetModelAnimation(ResolveAnimKey(cfg))
      else
        model:Hide()
      end

      if cfg.chatShow then
        chatFrame:RegisterEvent("CHAT_MSG_WHISPER")
        chatFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
        chatFrame:RegisterEvent("CHAT_MSG_GUILD")
        chatFrame:Show()
      else
        chatFrame:Hide()
      end

      elapsedSeconds, timerElapsed, tipsElapsed = 0, 0, 0
      frame:SetFrameStrata("FULLSCREEN_DIALOG") -- au cas ou un apercu GUI (strata HIGH) etait actif
      frame:Show()
      UIParent:Hide()
      PlayPanelAnimations()
    end)

    if not ok then
      print("|cffff4444[AishCore AFKMode]|r Erreur a l'activation : " .. tostring(err))
      UIParent:Show()
      frame:Hide()
      return
    end

    AFKMode.isAFK = true
  elseif AFKMode.isAFK then
    UIParent:Show()
    if cfg.cameraSpin then MoveViewLeftStop() end

    chatFrame:UnregisterAllEvents()
    chatFrame:Clear()

    AFKMode.isAFK = false

    -- Si un apercu GUI etait en cours avant que le vrai AFK ne prenne le
    -- dessus, on lui rend la main plutot que de tout masquer.
    if isPreview then
      frame:SetFrameStrata("HIGH")
    else
      frame:Hide()
    end
  end
end

-- Apercu GUI (section "Mode AFK") : contrairement a SetAFKState, ne masque pas UIParent
-- ni ne joue camera/chat -- juste le rendu visuel, actif tant que la section est ouverte.
function AFKMode.SetPreview(status)
  if not frame then return end

  if status then
    if AFKMode.isAFK then return end -- le vrai AFK est prioritaire
    local cfg = Cfg()
    if not cfg.enabled then return end
    if InCombatLockdown() then return end -- meme prudence que SetAFKState

    local ok, err = pcall(function()
      RefreshTextStrings()
      RefreshGraphics()

      if cfg.modelEnabled then
        model:Show()
        SetModelAnimation(ResolveAnimKey(cfg))
      else
        model:Hide()
      end
      chatFrame:Hide() -- pas de capture chat en apercu, juste visuel

      elapsedSeconds, timerElapsed, tipsElapsed = 0, 0, 0
      frame:SetFrameStrata("HIGH") -- sous le panneau de reglages (DIALOG), au-dessus du jeu normal
      frame:Show()
      -- Pas d'animation d'entree ici : eviterait du bruit visuel a chaque refresh de reglage
      AnchorTopNatural();    topPanel:SetAlpha(1)
      AnchorBottomNatural(); bottomPanel:SetAlpha(1)
    end)

    if not ok then
      print("|cffff4444[AishCore AFKMode]|r Erreur pendant l'apercu : " .. tostring(err))
      frame:Hide()
      isPreview = false
      return
    end

    isPreview = true
  else
    isPreview = false
    if not AFKMode.isAFK then
      frame:Hide()
      frame:SetFrameStrata("FULLSCREEN_DIALOG")
    end
  end
end

-- Garde d'activation — 100% API Blizzard native
local function OnAFKEvent(event, arg1)
  if event == "PLAYER_REGEN_ENABLED" then
    eventFrame:UnregisterEvent(event)
    return
  elseif event == "UPDATE_BATTLEFIELD_STATUS" or event == "PLAYER_REGEN_DISABLED" or event == "LFG_PROPOSAL_SHOW" then
    if event ~= "UPDATE_BATTLEFIELD_STATUS" or (GetBattlefieldStatus(arg1) == "confirm") then
      AFKMode:SetAFKState(false)
    end
    if event == "PLAYER_REGEN_DISABLED" then
      eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    return
  end

  local cfg = Cfg()
  if (not cfg.enabled)
    or (event == "PLAYER_FLAGS_CHANGED" and arg1 ~= "player")
    or InCombatLockdown()
    or (_G.CinematicFrame and _G.CinematicFrame:IsShown())
    or (_G.MovieFrame and _G.MovieFrame:IsShown())
    or (ns.IsInBlockedState and ns.IsInBlockedState())
  then
    return
  end

  if UnitCastingInfo("player") then
    C_Timer.After(30, function() OnAFKEvent("PLAYER_FLAGS_CHANGED", "player") end)
    return
  end

  local inPetBattle = C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
  AFKMode:SetAFKState(UnitIsAFK("player") and not inPetBattle)
end

local function OnKeyDown(_, key)
  if ignoreKeys[key] then return end
  if printKeys[key] then
    Screenshot()
  elseif AFKMode.isAFK and Cfg().exitOnKeypress ~= false then
    AFKMode:SetAFKState(false)
    C_Timer.After(60, function() OnAFKEvent("PLAYER_FLAGS_CHANGED", "player") end)
  end
end

-- Construction des frames
local function CreateTexts()
  for _, def in ipairs(TEXT_ELEMENTS) do
    local panel = (def.panel == "top") and topPanel or bottomPanel
    texts[def.key] = panel:CreateFontString(nil, "OVERLAY")
    textSlugs[def.key] = ns.CreateSlugRing(panel, texts[def.key])
  end
end

local function CreateGraphics()
  for _, def in ipairs(GRAPHIC_ELEMENTS) do
    local panel = (def.panel == "top") and topPanel or bottomPanel
    graphics[def.key] = panel:CreateTexture(nil, "ARTWORK")
  end
end

local function CreateModel()
  local cfg = Cfg()
  modelHolder = CreateFrame("Frame", nil, bottomPanel)
  modelHolder:SetSize(150, 150)
  modelHolder:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT", cfg.modelXOffset or -60, cfg.modelYOffset or 0)

  model = CreateFrame("PlayerModel", "AishCoreAFKPlayerModel", modelHolder)
  model:SetPoint("CENTER", modelHolder)
  model:SetSize(GetScreenWidth() * 2, GetScreenHeight() * 2) -- evite le clipping, position geree par modelHolder
  model:SetUnit("player")
  model:SetCamDistanceScale(cfg.modelDistance or 4.5)
  model:SetScript("OnUpdate", ModelOnUpdate)
end

local function CreatePanels()
  local cfg = Cfg()
  -- Ancrage a un seul point (pas TOPLEFT+TOPRIGHT) : requis pour repositionner hors ecran dans PlayPanelAnimations()
  local screenW = GetScreenWidth()

  topPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  topPanel:SetSize(screenW, cfg.panelTopHeight or 60)
  topPanel:SetPoint("TOP", frame, "TOP", 0, 0)

  bottomPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  bottomPanel:SetSize(screenW, cfg.panelBottomHeight or 100)
  bottomPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)

  for _, panel in ipairs({ topPanel, bottomPanel }) do
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  end
end

local function CreateChatAndTips()
  chatFrame = CreateFrame("ScrollingMessageFrame", "AishCoreAFKChat", frame)
  chatFrame:SetSize(480, 160)
  chatFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -80)
  chatFrame:SetFont(ns.Media.fontGui, 12, "")
  chatFrame:SetJustifyH("LEFT")
  chatFrame:SetMaxLines(200)
  chatFrame:SetFading(false)
  chatFrame:UnregisterAllEvents()
  chatFrame:SetScript("OnEvent", function(self, event, msg, sender)
    local shortSender = sender and Ambiguate and Ambiguate(sender, "none") or sender or "?"
    self:AddMessage(format("|cff" .. AccentHex() .. "[%s]|r: %s", shortSender, msg), 1, 1, 1)
  end)

  tipsFrame = CreateFrame("ScrollingMessageFrame", "AishCoreAFKTips", bottomPanel)
  tipsFrame:SetSize(500, 120) -- genereux : une astuce peut faire plusieurs lignes une fois wrappee
  tipsFrame:SetPoint("BOTTOM", bottomPanel, "BOTTOM", 0, 8)
  tipsFrame:SetFont(ns.Media.fontGui, 11, "")
  tipsFrame:SetJustifyH("CENTER")
  tipsFrame:SetFading(false)
  tipsFrame:SetMaxLines(1)
  tipsFrame:SetTimeVisible(1)
end

-- API publique du module
function AFKMode.Create(parent)
  if frame then return end

  -- Aucun parent (SetAFKState masque UIParent, un enfant d'UIParent serait masque avec lui)
  -- SetScale requis car un frame sans parent n'a pas l'echelle d'UIParent par defaut.
  frame = CreateFrame("Frame", "AishCoreAFKFrame")
  frame:SetScale(UIParent:GetEffectiveScale())
  frame:SetAllPoints(parent or UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:EnableKeyboard(true)
  frame:SetScript("OnKeyDown", OnKeyDown)
  frame:SetScript("OnUpdate", OnFrameUpdate)
  frame:Hide()

  CreatePanels()
  CreateTexts()
  CreateGraphics()
  CreateModel()
  CreateChatAndTips()

  eventFrame = CreateFrame("Frame")
  eventFrame:SetScript("OnEvent", function(_, event, arg1)
    local ok, err = pcall(OnAFKEvent, event, arg1)
    if not ok then
      print("|cffff4444[AishCore AFKMode]|r Erreur OnAFKEvent (" .. tostring(event) .. ") : " .. tostring(err))
    end
  end)
  eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
  eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  eventFrame:RegisterEvent("LFG_PROPOSAL_SHOW")
  eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
  if SetCVar then SetCVar("autoClearAFK", 1) end -- reproduit le comportement de l'ecran AFK natif

  AFKMode.isAFK = false
end

function AFKMode.ApplySettings()
  if not frame then return end
  local cfg = Cfg()

  topPanel:SetSize(GetScreenWidth(), cfg.panelTopHeight or 60)
  bottomPanel:SetSize(GetScreenWidth(), cfg.panelBottomHeight or 100)
  local bg = cfg.panelBgColor or { 0, 0, 0, 0.85 }
  for _, panel in ipairs({ topPanel, bottomPanel }) do
    panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
  end

  model:SetCamDistanceScale(cfg.modelDistance or 4.5)
  modelHolder:ClearAllPoints()
  modelHolder:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT", cfg.modelXOffset or -60, cfg.modelYOffset or 0)
  if (AFKMode.isAFK or isPreview) and cfg.modelEnabled then
    SetModelAnimation(ResolveAnimKey(cfg)) -- relit cfg.modelAnim a chaque appel, pas le cache
  end

  -- Repercute en direct si l'ecran ou l'apercu GUI est deja affiche
  if AFKMode.isAFK or isPreview then
    RefreshTextStrings()
    RefreshGraphics()
  end

  if not cfg.enabled then
    if AFKMode.isAFK then AFKMode:SetAFKState(false) end
    if isPreview then AFKMode.SetPreview(false) end
  end
end

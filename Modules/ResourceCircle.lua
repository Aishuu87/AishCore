-- Modules/ResourceCircle.lua : Cercle de ressource primaire (dynamique par classe/spec)
local addonName, ns = ...
local L = ns.L

local ResourceCircle = {}
ns.Modules.ResourceCircle = ResourceCircle

-- Styles de déco autour du texte de ressource secondaire ("- N -", "[ N ]"...) ; left/right jamais concaténés à N (cf. SetSecResShown).
ns.SEC_RES_DECO_STYLES = {
  { key = "none",         left = "",     right = ""    },
  { key = "dash",         left = "-",    right = "-"   },
  { key = "bullet",       left = "•",    right = "•"   },
  { key = "slash",        left = "/",    right = "/"   },
  { key = "slash2",       left = "//",   right = "//"  },
  { key = "bslash",       left = "\\",   right = "\\"  },
  { key = "bslash2",      left = "\\\\", right = "\\\\" },
  { key = "pipe",         left = "|",    right = "|"   },
  { key = "ddash",        left = "--",   right = "--"  },
  { key = "underscore",   left = "_",    right = "_"   },
  { key = "dunderscore",  left = "__",   right = "__"  },
  { key = "equal",        left = "=",    right = "="   },
  { key = "tilde",        left = "~",    right = "~"   },
  { key = "hash",         left = "#",    right = "#"   },
  { key = "quote",        left = "\"",   right = "\""  },
  { key = "apostrophe",   left = "'",    right = "'"   },
  { key = "brackets",     left = "[",    right = "]"   },
  { key = "braces",       left = "{",    right = "}"   },
  { key = "parens",       left = "(",    right = ")"   },
}
local SEC_RES_DECO_BY_KEY = {}
for _, d in ipairs(ns.SEC_RES_DECO_STYLES) do SEC_RES_DECO_BY_KEY[d.key] = d end
local function GetSecResDeco(styleKey)
  return SEC_RES_DECO_BY_KEY[styleKey] or SEC_RES_DECO_BY_KEY.dash
end

-- Références locales
local bar = nil
local animationTicker = nil
local moveTicker = nil
local _rcAnimElems = {}   -- pré-alloué dans Create(), slots 11-12 mis à jour conditionnellement
local lastVisibilityState = nil
-- rcAnimBusy = animation show/hide en cours ; rcAnimDirty = demande arrivée pendant, jamais interrompue, relance UpdateVisibility() à la fin.
local rcAnimBusy = false
local rcAnimDirty = false
local previewMode = false
local lastResourceType = nil  -- dernier type de ressource detecte
local secDots = {}   -- secondary dot frames (runes, combo points, etc.)
local secDotCount = 0  -- nombre de secondary dots actifs
local secUpdateTicker = nil  -- ticker pour le fill progressif
local secDotType = nil  -- "RUNES", "COMBO", nil
local _secDotColorOverride = nil  -- {r, g, b} imposé par SpellEffects, ou nil

-- Animation slide des secondary dots (même esthétique que les orbes Skyriding)
local SEC_DOT_TEX     = (ns.Media and ns.Media.circle) or "Interface\\AddOns\\AishCore\\Media\\Skyriding\\Circle_Smooth"
local SEC_SLIDE_SPEED = 9.0    -- vitesse de slide (units/s)
local SEC_SLIDE_SCALE = 1.55   -- facteur de départ (× plus loin du centre)
local secDotAnims     = {}     -- [i] = { progress, target }
local secAnimFrame    = nil    -- frame dédié à l'animation slide des sec dots

-- Barre de duree de la ressource secondaire : deux StatusBars miroir qui se contractent
-- vers le centre (illusion d'une barre qui se reduit par les deux bouts).
--
-- Elle a son PROPRE sort par spec, volontairement decorrele de CENTER_ARC_SPELLS
-- (CenterArc.lua) : l'arc central du DK Sang suit Mort et decrepitude, alors que la
-- barre doit suivre Bouclier d'os -- le buff que le texte de ressource secondaire
-- juste au-dessus d'elle affiche deja en stacks.
--
-- Deux sources, dans cet ordre :
--   1. canal clone-bar CDM (ns.SubscribeCDMAuraBar) : combat-safe, valeurs jamais lues
--   2. repli GetPlayerAuraBySpellID hors combat, quand le sort n'est pas epingle sur le
--      viewer "Barres" de la CDM (le canal 1 n'existe alors pas)
local SEC_RES_DUR_BAR_SPELLS = {
  [73]  = { spellID = 190456, color = { 0.78, 0.25, 0.25 } },  -- Guerrier Prot : Dur au mal
  [104] = { spellID = 192081, color = { 0.85, 0.65, 0.30 } },  -- Druide Gardien : Fer-poil
  [250] = { spellID = 195181, color = { 0.75, 0.88, 1.00 } },  -- DK Sang : Bouclier d'os
}

local _secResDurInfo   = nil  -- entree SEC_RES_DUR_BAR_SPELLS active (ou nil)
local _secResDurSpecID = nil  -- spec pour laquelle le pilote a ete arme
local _secResDurTicker = nil  -- ticker du repli hors combat
local _secResDurLastFeed = nil  -- GetTime() du dernier SetValue recu du canal CDM

--- Expose le sort suivi par la barre de duree, pour que le module Auras puisse lui
--- activer sa destination de scan (cf. ns.AutoConfigSecResDurBar dans CenterArc.lua).
function ns.GetSecResDurBarSpellID(specID)
  local e = SEC_RES_DUR_BAR_SPELLS[specID or _secResDurSpecID or ns._specID or 0]
  return e and e.spellID or nil
end

local function SecResDurInfoFor(specID)
  return SEC_RES_DUR_BAR_SPELLS[specID or 0]
end

--- Avec un specID : question theorique ("cette spec aurait-elle une barre ?"), utilisee
--- par RefreshSecResDurBar pour armer ou couper le pilote.
--- Sans specID : etat REEL du pilote. On ne retombe surtout pas sur ns._specID, qui reste
--- nil un moment apres un /reload (meme defaut que les detecteurs, cf. ResolveSpecID) --
--- les barres etaient alors masquees a chaque tick malgre un pilote correctement arme.
local function SecResDurBarsActive(specID)
  if specID then
    if not SecResDurInfoFor(specID) then return false end
    return ns.GetSecResCfg("secResDurBarEnabled", specID) and true or false
  end
  if not _secResDurInfo then return false end
  return ns.GetSecResCfg("secResDurBarEnabled", _secResDurSpecID) and true or false
end

--- Applique `fn` aux deux moities (gauche puis droite), si elles existent.
local function SecResDurEach(fn)
  if not (bar and bar.secResDurL and bar.secResDurR) then return end
  fn(bar.secResDurL)
  fn(bar.secResDurR)
end

--- Show/Hide des deux moities. Un show ne passe que si la spec + l'option l'autorisent.
local function SecResDurShow(shown)
  if shown and not SecResDurBarsActive() then shown = false end
  SecResDurEach(function(b) b:SetShown(shown) end)
end

--- Couleur : celle choisie par l'utilisateur si definie, sinon celle du sort suivi.
local function SecResDurColor(specID)
  specID = specID or _secResDurSpecID
  local r = ns.GetSecResCfg("secResDurBarColorR", specID)
  if r then
    return { r, ns.GetSecResCfg("secResDurBarColorG", specID) or 1,
                ns.GetSecResCfg("secResDurBarColorB", specID) or 1 }
  end
  local info = SecResDurInfoFor(specID)
  return info and info.color or nil
end

local function SecResDurApplyColor(specID)
  local c = SecResDurColor(specID)
  if c then SecResDurEach(function(db) db:SetStatusBarColor(c[1], c[2], c[3], 1) end) end
end

-- Proxy "clone-bar" : meme contrat que ResourceCircle.centerArcBarProxy (SetMinMaxValues /
-- SetValue / Show), sans etre une vraie StatusBar. lo/hi/value peuvent etre secrets en
-- combat : relayes bruts, jamais compares -- sauf hi == 0, envoye en clair a l'expiration.
ResourceCircle.secResDurBarProxy = {
  SetMinMaxValues = function(_, lo, hi)
    if not SecResDurBarsActive() then SecResDurShow(false); return end
    local okZero, isZero = pcall(function() return hi == 0 end)
    if okZero and isZero then
      SecResDurEach(function(db) db:SetValue(0) end)
      SecResDurShow(false)
      return
    end
    SecResDurApplyColor()
    SecResDurEach(function(db)
      db:SetAlpha(1)
      pcall(db.SetMinMaxValues, db, lo, hi)
    end)
    SecResDurShow(true)
  end,
  SetValue = function(_, value)
    _secResDurLastFeed = GetTime()
    SecResDurEach(function(db) pcall(db.SetValue, db, value) end)
  end,
  Show = function() end,
}

-- Animation combat-safe : SetTimerDuration(durObj) laisse Blizzard vider la barre a
-- 60fps sans qu'on lise jamais la valeur. C'est la seule source utilisable en combat,
-- ou duration/expirationTime sont des valeurs secretes.
local SRD_INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local SRD_DRAIN  = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local SRD_GetAuraDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
local _secResDurLastRef = nil  -- tostring(durObj) arme sur les deux moities

--- auraInstanceID du sort suivi. cdmData d'abord : GetPlayerAuraBySpellID echoue pour
--- beaucoup d'auras en combat, alors que le registre CDM reste fiable.
local function SecResDurAuraInstID(spellID)
  local A = ns.Auras
  local cdmPlayer = A and A.cdmData and A.cdmData.player
  local e = cdmPlayer and cdmPlayer[spellID]
  if e and e.instID then return e.instID end
  local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
  if ok and data then return data.auraInstanceID end
  return nil
end

--- Duration object du sort, pris dans ns.Auras.auraData : ce sont les entrees que les
--- renders qui FONCTIONNENT en combat (barres de cercle, barres libres...) consomment
--- deja. Les resoudre nous-memes via GetAuraDuration echoue en combat, le ticker etant
--- un contexte taint AishCore ("Auras cannot be accessed when secret while tainted") --
--- alors que Scan.lua, lui, les resout depuis un contexte propre.
local function SecResDurFindDurObj(spellID)
  local A = ns.Auras
  local data = A and A.auraData
  if not data then return nil end
  for _, list in pairs(data) do
    if type(list) == "table" then
      for i = 1, #list do
        local e = list[i]
        if e and e.spellID == spellID and e.durObj then return e.durObj end
      end
    end
  end
  return nil
end

--- Coupe le timer arme sur les deux moities (uniquement s'il y en avait un : passer nil
--- a SetTimerDuration sans timer actif peut corrompre l'etat de la StatusBar).
local function SecResDurClearTimer()
  if not _secResDurLastRef then return end
  _secResDurLastRef = nil
  SecResDurEach(function(db)
    if db.SetTimerDuration then pcall(db.SetTimerDuration, db, nil) end
    db:SetValue(0)
  end)
end

--- Trois sources, par ordre de fiabilite :
---   1. canal clone-bar CDM, s'il nous alimente reellement (sort epingle sur "Barres")
---   2. duration object via C_UnitAuras.GetAuraDuration -- marche EN COMBAT
---   3. lecture numerique duration/expirationTime, hors combat uniquement
local function SecResDurTick()
  if previewMode then return end  -- SetPreview pilote les barres dans ce mode
  if not SecResDurBarsActive() then SecResDurShow(false); return end
  local info = _secResDurInfo
  if not info then return end

  -- 1) Le canal CDM a la priorite, mais seulement s'il nous a REELLEMENT alimente
  -- recemment. Tester IsCDMAuraBarPresent ne suffit pas : un sort peut etre suivi par la
  -- CDM sans etre epingle sur le viewer "Barres", auquel cas le proxy ne recoit jamais
  -- de SetValue -- la barre restait a 0, donc affichee mais invisible.
  if _secResDurLastFeed and (GetTime() - _secResDurLastFeed) < 0.5 then return end

  local instID = SecResDurAuraInstID(info.spellID)
  if not instID then
    -- Aura absente : couper proprement, sinon le timer continuerait a animer dans le vide.
    SecResDurClearTimer()
    SecResDurShow(false)
    return
  end

  -- 2) Duration object. On lit d'abord le cache rempli par Scan.lua : ce ticker est un
  -- contexte taint AishCore, ou GetAuraDuration se fait refuser l'acces aux auras
  -- secretes en combat ("Auras cannot be accessed when secret while tainted"). Scan,
  -- lui, resout le durObj depuis un contexte propre. L'appel direct ne reste qu'en
  -- second recours (hors combat, ou si le sort n'est pas suivi par le pipeline).
  do
    local durObj = SecResDurFindDurObj(info.spellID)
    if not durObj and SRD_GetAuraDuration then
      local okD, d = pcall(SRD_GetAuraDuration, "player", instID)
      durObj = okD and d or nil
    end
    if durObj then
      local ref = tostring(durObj)
      if ref ~= _secResDurLastRef then
        _secResDurLastRef = ref
        SecResDurApplyColor()
        SecResDurEach(function(db)
          db:SetAlpha(1)
          db:SetMinMaxValues(0, 1)
          if db.SetTimerDuration and SRD_INTERP and SRD_DRAIN then
            pcall(db.SetTimerDuration, db, durObj, SRD_INTERP, SRD_DRAIN)
          end
        end)
      end
      SecResDurShow(true)
      return
    end
  end

  -- 3) Repli numerique : GetAuraDuration echoue silencieusement pour certaines auras
  -- pourtant lisibles autrement. En combat le calcul leve (valeurs secretes), le pcall
  -- echoue proprement et on laisse la barre en l'etat plutot que de la vider a tort.
  local okA, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, info.spellID)
  if not okA or not data then return end
  local okF, frac = pcall(function()
    local dur = data.duration
    if not dur or dur <= 0 then return nil end
    return (data.expirationTime - GetTime()) / dur
  end)
  if not okF or not frac then return end
  SecResDurClearTimer()
  SecResDurApplyColor()
  SecResDurEach(function(db)
    db:SetAlpha(1)
    db:SetMinMaxValues(0, 1)
    ns.SmoothSetValue(db, math.max(0, math.min(1, frac)))
  end)
  SecResDurShow(true)
end

--- Coupe tout : desabonnement du canal CDM, arret du ticker de repli, barres masquees.
local function SecResDurStop()
  if _secResDurInfo and ns.Auras and ns.Auras.UnsubscribeCDMAuraBar then
    ns.Auras.UnsubscribeCDMAuraBar(_secResDurInfo.spellID, "secResDurBar")
  end
  SecResDurClearTimer()
  _secResDurInfo = nil
  _secResDurSpecID = nil
  _secResDurLastFeed = nil
  if _secResDurTicker then _secResDurTicker:Cancel(); _secResDurTicker = nil end
  SecResDurShow(false)
end

--- (Re)branche la barre sur le sort de `specID`. Appele a chaque changement de spec et
--- a chaque changement de reglage (l'option peut etre (de)cochee a chaud).
local function SecResDurStart(specID)
  SecResDurStop()
  if not SecResDurBarsActive(specID) then return end
  local info = SecResDurInfoFor(specID)
  if not info then return end
  _secResDurInfo = info
  _secResDurSpecID = specID or ns._specID
  if ns.Auras and ns.Auras.SubscribeCDMAuraBar then
    ns.Auras.SubscribeCDMAuraBar(info.spellID, "secResDurBar", ResourceCircle.secResDurBarProxy)
  end
  _secResDurTicker = C_Timer.NewTicker(0.05, SecResDurTick)
end

-- Affiche/masque texte + tirets décoratifs ensemble ; tirets séparés de N car concat/format interdits sur une valeur secrète.
local function SetSecResShown(shown)
  if not bar then return end
  if bar.secResText  then bar.secResText:SetShown(shown)  end
  if bar.secResDashL then bar.secResDashL:SetShown(shown) end
  if bar.secResDashR then bar.secResDashR:SetShown(shown) end
  -- Le texte cache : la barre de duree n'a plus de sens (elle lui est ancree).
  -- L'inverse n'est pas vrai : un texte visible n'implique pas un buff actif, donc
  -- c'est le pilote (canal CDM / repli) qui decide du show.
  if not shown then SecResDurShow(false) end
end

--- Geometrie + couleur de la barre de duree (par spec). `secResDurBarWidth` est la
--- largeur TOTALE : chaque moitie en prend la moitie, et elles se touchent au point
--- d'ancrage, qui est le bord (haut ou bas) du texte de ressource secondaire decale
--- de (offX, offY).
local function RefreshSecResDurBar(specID)
  if not (bar and bar.secResDurL and bar.secResDurR and bar.secResText) then return end
  -- Appelee aussi depuis ApplySettings, qui resout la spec en ligne et peut passer nil
  -- (juste apres un /reload). Sans ce repli, la comparaison de reference plus bas
  -- desarmerait un pilote pourtant correct.
  specID = specID or _secResDurSpecID or ns._specID
  local totalW = ns.GetSecResCfg("secResDurBarWidth",  specID) or 60
  local h      = ns.GetSecResCfg("secResDurBarHeight", specID) or 3
  local anchor = ns.GetSecResCfg("secResDurBarAnchor", specID) or "BOTTOM"
  local offX   = ns.GetSecResCfg("secResDurBarOffX",   specID) or 0
  local offY   = ns.GetSecResCfg("secResDurBarOffY",   specID) or -2
  local halfW  = math.max(1, totalW / 2)
  if h < 1 then h = 1 end
  -- "TOP" = au-dessus du texte, tout le reste (defaut) = en dessous.
  local relPoint = (anchor == "TOP") and "TOP" or "BOTTOM"

  bar.secResDurL:SetSize(halfW, h)
  bar.secResDurL:ClearAllPoints()
  bar.secResDurL:SetPoint("RIGHT", bar.secResText, relPoint, offX, offY)

  bar.secResDurR:SetSize(halfW, h)
  bar.secResDurR:ClearAllPoints()
  bar.secResDurR:SetPoint("LEFT", bar.secResText, relPoint, offX, offY)

  local c = SecResDurColor(specID)
  if c then SecResDurEach(function(db) db:SetStatusBarColor(c[1], c[2], c[3], 1) end) end
  -- L'option est modifiable a chaud : on rebranche (ou on coupe) le pilote ici plutot
  -- que d'attendre un changement de spec.
  if SecResDurBarsActive(specID) then
    -- Comparaison de REFERENCE de table : detecte aussi un changement de spec
    -- (73 -> 250), qui doit rebrancher la barre sur l'autre sort.
    if _secResDurInfo ~= SecResDurInfoFor(specID) then SecResDurStart(specID) end
  else
    SecResDurStop()
  end
end

-- Applique style/espacement déco (par spec, ns.GetSecResCfg) ; specID optionnel pour éviter de dépendre de ns._specID pas encore à jour.
local function RefreshSecResDeco(specID)
  if not bar or not bar.secResDashL or not bar.secResDashR or not bar.secResText then return end
  local deco = GetSecResDeco(ns.GetSecResCfg("secResDecoStyle", specID))
  local spacing = ns.GetSecResCfg("secResDecoSpacing", specID) or 4
  bar.secResDashL:SetText(deco.left)
  bar.secResDashR:SetText(deco.right)
  bar.secResDashL:ClearAllPoints()
  bar.secResDashL:SetPoint("RIGHT", bar.secResText, "LEFT", -spacing, 0)
  bar.secResDashR:ClearAllPoints()
  bar.secResDashR:SetPoint("LEFT", bar.secResText, "RIGHT", spacing, 0)
end

-- Durées/courbes anim show/hide du cercle central ; opacity = alpha départ(show)/fin(hide) ; arc/arcOverlay animés indépendamment via `scale`.
local CIRCLE_ANIM = {
  background = { -- bgGlow
    show = { duration = 0.3,  delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, scaleX = 2.5, scaleY = 2.5, opacity = 1 },
    hide = { duration = 0.3,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 0, scaleX = 0.5, scaleY = 0, opacity = 0 },
  },
  backgroundSlow = { -- bgLarge (traîne légèrement derrière "background", cf. delay)
    show = { duration = 0.2,  delay = 0.050, ease = "Quint", easeType = "Out", slideX = 0, slideY = -20, scaleX = 0.5, scaleY = 0.5, opacity = 1 },
    hide = { duration = 0.2,  delay = 0.050, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, scaleX = 0.5, scaleY = 0.5, opacity = 0 },
  },
  arc = { -- arc radial natif
    show = { duration = 0.8, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = -20, opacity = 1, scale = 0.5 },
    hide = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  arcOverlay = { -- masque du centre de l'arc — 100% indépendant de "arc" (délai/durée/ease/scale)
    show = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, opacity = 1, scale = 1 },
    hide = { duration = 0.4, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  durationArc = { -- arc de duree (ressource secondaire) : apparait apres les autres elements, part parmi les premiers
    show = { duration = 0.6, delay = 0.450, ease = "Quint", easeType = "Out", slideX = 0, slideY = -20, opacity = 1, scale = 0.5 },
    hide = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  durationArcLive = { -- meme arc, quand c'est la donnee (buff) qui le fait entrer/sortir cercle visible : sans delai
    show = { duration = 0.35, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = -20, opacity = 1, scale = 0.5 },
    hide = { duration = 0.20, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  durationArcOverlayLive = {
    show = { duration = 0.20, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, opacity = 1, scale = 1 },
    hide = { duration = 0.30, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  durationArcOverlay = { -- masque central de l'arc de duree
    show = { duration = 0.2, delay = 0.450, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, opacity = 1, scale = 1 },
    hide = { duration = 0.4, delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, opacity = 0, scale = 0.5 },
  },
  textBackdrop = { -- petit cache sombre sous le texte (même transformations que arcOverlay)
    show = { duration = 0.2, delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 0, scaleX = 1,   scaleY = 1,   opacity = 1 },
    hide = { duration = 0.4, delay = 0.000, ease = "Quint", easeType = "In",  slideX = 0, slideY = -20, scaleX = 0.5, scaleY = 0.5, opacity = 0 },
  },
  text = {
    show = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "Out", slideX = 0, slideY = -10, scaleX = 1, scaleY = 1, opacity = 1 },
    hide = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 1, scaleY = 1, opacity = 0 },
  },
  secResText = { -- texte de ressource secondaire (Bone Shield, Soul Fragments...)
    show = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "Out", slideX = 0, slideY = -10, scaleX = 1, scaleY = 1, opacity = 1 },
    -- slideY négatif : contrairement au groupe "text", ce texte sort par le BAS
    -- (home.y + slideY < home.y) plutôt que par le haut à la disparition.
    hide = { duration = 0.4,  delay = 0.100, ease = "Quint", easeType = "In", slideX = 0, slideY = -20, scaleX = 1, scaleY = 1, opacity = 0 },
  },
  dotCenter = { -- dot3
    show = { duration = 0.5,  delay = 0.00, ease = "Quint", easeType = "Out", slideX = 0, slideY = 15, scaleX = 0.8, scaleY = 3.2, opacity = 1 },
    hide = { duration = 0.5,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 0.6, scaleY = 2.1, opacity = 0 },
  },
  dotMid = { -- dot2 / dot4
    show = { duration = 1,  delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 15, scaleX = 0.8, scaleY = 3.8, opacity = 1 },
    hide = { duration = 0.4,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 0.6, scaleY = 2.1, opacity = 0 },
  },
  dotOuter = { -- dot1 / dot5
    show = { duration = 1.5,  delay = 0.000, ease = "Quint", easeType = "Out", slideX = 0, slideY = 15, scaleX = 0.8, scaleY = 3.8, opacity = 1 },
    hide = { duration = 0.3,  delay = 0.000, ease = "Quint", easeType = "In", slideX = 0, slideY = 20, scaleX = 0.6, scaleY = 2.1, opacity = 0 },
  },
}

-- Mappe chaque slot de _rcAnimElems à son groupe CIRCLE_ANIM (nil = pas de
-- groupe, ex: slots 4/5 arc/overlay animés séparément par AnimateArcOverlay).
local _RC_ANIM_GROUP = {
  [1] = "background", [2] = "backgroundSlow", [3] = "text",
  [6] = "dotCenter", [7] = "dotMid", [8] = "dotMid",
  [9] = "dotOuter", [10] = "dotOuter",
  -- 11/12 (staggerArc/staggerOverlayFrame) : animés par AnimateArcOverlay avec la spec arc/arcOverlay.
  [13] = "textBackdrop",
  [14] = "secResText",
}

-- Géométrie de repos ("home") mémorisée via RecordHome() plutôt que relue via GetPoint/GetSize,
-- qui peut renvoyer des secret values en combat et bloquer les opérations Lua dessus.
local _elemHome = {}
local function RecordHome(element, point, relTo, relPoint, x, y, w, h)
  _elemHome[element] = { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y, w = w, h = h }
end

-- Ressource secondaire (texte sous le cercle : Bone Shield, Soul Fragments, etc.)
local secResDef        = nil   -- définition active (ou nil)
local secResUpdateTicker = nil -- ticker de mise à jour
-- spellID(s) abonnés au canal clone-stack (CDMHooks) pour bar.secResText, mémorisés pour désabonnement propre au changement de spec.
local _secResStackSubIDs = nil
local FONT_SECRES_DEFAULT = ns.FONT_FALLBACK  -- police du jeu (2002)

-- Essence Burst (Evoker Preservation) : proc détecté via spell overlay
-- Sorts qui s'allument quand Essence Burst est actif
local ESSENCE_BURST_SPELLS = { [364343]=true, [355913]=true, [356995]=true }  -- Echo, Emerald Blossom, Disintegrate
local essenceBurstGlowing  = {}   -- [spellID] = true si overlay actif en ce moment
local essenceBurstActive   = false -- dérivé de essenceBurstGlowing

-- Fire Mage Heating Up (1) / Hot Streak (2) : overlay écran = Heating Up, glow Pyroblast/Flamestrike = Hot Streak.
local FIRE_PYRO_SPELLS  = { [11366]=true, [2120]=true }  -- Pyroblast, Flamestrike
local fireOverlayActive = false  -- overlay écran présent
local firePyroGlowing   = false  -- glow Pyroblast/Flamestrike actif
local fireProcLevel     = 0      -- 0/1/2 dérivé

-- Arc de stagger (Moine Brasseur specID 268)
local staggerActive         = false
local durArcVert            = false   -- l'arc de duree affiche est la barre verticale (canal clone-bar, plage secrete)
local function DurArcEl() return durArcVert and bar.durationArcV or bar.durationArc end
local previewDurShown, previewStagShown, previewDurEl = false, false, nil   -- arcs secondaires montres par l'apercu du panneau
local durShown, durBusy = false, false   -- arc de duree : etat affiche (animation terminee) / animation en cours
local RunDurAnim
local durArcWanted          = false   -- l'arc de duree a du contenu (independamment de la visibilite du cercle)

-- Warlock Demonologie : Demonic Core (buff 264173, stacks 0-2)
-- Fallback : glow sur Incantation de la Foudre Démoniaque / Demonbolt (264178)
local demonicCoreStacks        = 0
local demonicCoreOverlayActive = false
local DEMONBOLT_SPELL_ID       = 264178

-- Enhancement Shaman Maelstrom Weapon pseudo-spells (specID 263)
-- 0=aucun, 1=≥5 stacks, 2=≥8 stacks, 3=10 stacks
local mwStackLevel = 0
local staggerUpdateTicker   = nil
local STAGGER_ARC_RATIO     = 0.72   -- taille relative à arcPx (s'inscrit dans le trou de l'overlay)
local STAGGER_OVERLAY_RATIO = 0.76   -- overlay interne du cercle de stagger
local STAGGER_LIGHT    = { 0.52, 1.00, 0.52 }  -- < 30%  : vert
local STAGGER_MODERATE = { 1.00, 0.69, 0.00 }  -- 30-60% : orange
local STAGGER_HEAVY    = { 1.00, 0.15, 0.15 }  -- >= 60% : rouge

-- Arc de durée dans le cercle central : piloté par CenterArc.lua (module autonome)
local DURATION_ARC_RATIO     = 0.72
local DURATION_ARC_OVL_RATIO = 0.76

-- Arcs en rendu radial natif (StatusBar:SetRenderMode(Radial)) sur un disque plein : hauteur = largeur.
local ARC_CROP_H = 1
-- Barre verticale de l'arc de duree (sources a plage secrete, canal clone-bar) : texture pre-croppee comme avant
local ARC_CROP_V = 0.88

-- Le disque natif est peint pile jusqu'au rayon nominal de l'arc ; le slider d'epaisseur etant regle pour un rayon
-- peint un peu plus grand (ancien rendu), on retranche cet ecart pour conserver la meme epaisseur visible.
local ARC_OVERLAY_OFFSET = 0.073

-- Diametre de l'arc : 1.0 = tout le fond (bgLarge, 1.1 x la taille globale).
local function ArcPx(cfg)
  return cfg.size * 1.1 * (cfg.arcSizeRatio or 1.0)
end

-- Migration unique des anciens profils : l'ancien ratio d'arc partait de la taille globale (pas du fond) et
-- "epaisseur" etait en fait la taille du trou (0 = disque plein). Le rendu des profils existants est conserve.
function ResourceCircle.EnsureArcSettings()
  local cfg = ns.GetCfg("resourceCircle")
  if not cfg then return cfg end
  if not cfg.arcGeomV2 then
    cfg.arcSizeRatio = math.floor((cfg.arcSizeRatio or 1.0) / 1.1 * 1000 + 0.5) / 1000
    cfg.arcThickness = math.max(0.01, math.min(1, 1.073 - (cfg.overlayRatio or 0.75)))
    cfg.arcGeomV2 = true
  end
  -- Arcs secondaires : meme inversion (ancien "ratio d'overlay" = taille du trou, nouvelle epaisseur = 1 - trou).
  if not cfg.secArcGeomV2 then
    local function Thick(ratio, default) return math.max(0.01, math.min(1, 1 - (ratio or default))) end
    cfg.staggerArcThickness = Thick(cfg.staggerOverlayRatio, STAGGER_OVERLAY_RATIO)
    cfg.durationArcThickness = Thick(cfg.durationArcOverlayRatio, DURATION_ARC_OVL_RATIO)
    local specKeys = {}
    for k in pairs(cfg) do
      if type(k) == "string" and k:match("^secRes_%d+_durationArcOverlayRatio$") then specKeys[#specKeys + 1] = k end
    end
    for _, k in ipairs(specKeys) do
      cfg[k:gsub("durationArcOverlayRatio$", "durationArcThickness")] = Thick(cfg[k], DURATION_ARC_OVL_RATIO)
    end
    cfg.secArcGeomV2 = true
  end
  return cfg
end

-- Trou des masques des arcs secondaires, en fraction du diametre de leur arc.
local function StaggerHole(cfg)
  return math.max(0, math.min(1 - (cfg.staggerArcThickness or (1 - STAGGER_OVERLAY_RATIO)), 0.995))
end
local function DurationHole(specID)
  local t = ns.GetSecResCfg("durationArcThickness", specID) or (1 - DURATION_ARC_OVL_RATIO)
  return math.max(0, math.min(1 - t, 0.995))
end

-- Masque central qui creuse l'anneau : trou = 1 - epaisseur (en fraction du diametre de l'arc).
local function OverlayPx(cfg, arcPx)
  local hole = 1 - (cfg.arcThickness or 0.32)
  return arcPx * math.max(0, math.min(hole, 0.995))
end

-- Arc en rendu radial natif : disque plein, c'est l'overlay qui creuse l'anneau.
-- SetMinMaxValues est enveloppe : le maximum est agrandi de 360/etendue pour que 0-100 % ne parcoure que l'arc
-- (etendue < 360). Maximum secret : laisse tel quel (pas d'arithmetique possible), l'arc va alors jusqu'a 360 deg.
local function SetupRadialArc(sb)
  ns.SetSmoothStatusBarTexture(sb, ns.Media.circle)
  sb:SetRenderMode(Enum.StatusBarRenderMode.Radial)
  local raw = sb.SetMinMaxValues
  sb._k = 1
  sb.SetMinMaxValues = function(self, lo, hi)
    self._ulo, self._uhi = lo, hi
    local k, scaled = self._k or 1, hi
    if k ~= 1 then
      local ok, v = pcall(function() return hi * k end)
      if ok then scaled = v end
    end
    raw(self, lo, scaled)
  end
end

-- Angles (degres, horaire, 0 = midi) : depart et fin de l'arc. Convention du rendu natif : 0 % commence a midi
-- sans rotation (NATIVE_START), horaire ; la rotation de la texture decale le depart, SetReverseFill inverse le sens.
-- Sens inverse : l'arc reste au meme endroit, le remplissage part de la fin et revient vers le depart.
local NATIVE_START = 0
local function SetArcAngle(sb, startDeg, endDeg, reverse)
  if not sb then return end
  local a0, a1 = tonumber(startDeg) or 220, tonumber(endDeg) or 140
  local span = (a1 - a0) % 360
  if span < 1 then span = 360 end
  -- Rendu radial : le sens antihoraire se regle sur la texture geree (SetRadialProgressBarReverse, 12.1) ;
  -- StatusBar:SetReverseFill ne joue que sur l'axe lineaire. Repli sur ce dernier si l'API est absente.
  local tex = sb:GetStatusBarTexture()
  if tex and tex.SetRadialProgressBarReverse then
    sb:SetReverseFill(false)
    tex:SetRadialProgressBarReverse(reverse and true or false)
  else
    sb:SetReverseFill(reverse and true or false)
  end
  if tex then tex:SetRotation(-math.rad((reverse and a1 or a0) - NATIVE_START)) end
  local k = 360 / span
  if sb._k ~= k then
    sb._k = k
    pcall(sb.SetMinMaxValues, sb, sb._ulo or 0, sb._uhi or 100)
  end
end

-- Taille / position / "home" de l'arc de stagger et de son masque central, relus depuis les reglages.
local function ApplyStaggerGeometry()
  if not (bar and bar.staggerArc) then return end
  local cfg = ns.GetCfg("resourceCircle")
  local stagArcPx = ArcPx(cfg) * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
  bar.staggerArc:SetSize(stagArcPx, stagArcPx * ARC_CROP_H)
  bar.staggerArc:ClearAllPoints()
  bar.staggerArc:SetPoint("TOP", bar, "CENTER", 0, stagArcPx / 2)
  RecordHome(bar.staggerArc, "TOP", bar, "CENTER", 0, stagArcPx / 2, stagArcPx, stagArcPx * ARC_CROP_H)
  if bar.staggerOverlay then
    local ov = math.max(stagArcPx * StaggerHole(cfg), 0.01)
    bar.staggerOverlay:SetSize(ov, ov)
    bar.staggerOverlay:ClearAllPoints()
    bar.staggerOverlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
    RecordHome(bar.staggerOverlay, "CENTER", bar, "CENTER", 0, 0, ov, ov)
  end
end

-- Reinitialise le rendu radial d'une barre (texture, mode, rotation, plage) : apres un redimensionnement, une barre radiale dont
-- la valeur ne change plus (stagger au repos) pouvait rester invisible jusqu'au /reload.
local function ResetRadialArc(sb)
  if not sb then return end
  local ok, v = pcall(sb.GetValue, sb)
  ns.SetSmoothStatusBarTexture(sb, ns.Media.circle)
  sb:SetRenderMode(Enum.StatusBarRenderMode.Radial)
  sb._k = nil   -- force la reapplication de la plage et de la rotation par SetArcAngle
  if ok then pcall(sb.SetValue, sb, v) end
end

-- Applique angles + sens aux trois arcs (principal, stagger, duree ; ce dernier par spec).
local function ApplyArcAngles(specID)
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")
  -- Spec resolue ici : juste apres un /reload ns._specID est encore nil, et les reglages par spec (arc de duree)
  -- retombaient alors sur les valeurs plates par defaut.
  if not specID and GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local ok, sid = pcall(GetSpecializationInfo, idx)
      if ok and sid and sid > 0 then specID = sid end
    end
  end
  SetArcAngle(bar.arc, cfg.arcStartAngle, cfg.arcEndAngle, cfg.arcReverse)
  SetArcAngle(bar.staggerArc, cfg.staggerArcStartAngle, cfg.staggerArcEndAngle, cfg.staggerArcReverse)
  SetArcAngle(bar.durationArc, ns.GetSecResCfg("durationArcStartAngle", specID), ns.GetSecResCfg("durationArcEndAngle", specID),
    ns.GetSecResCfg("durationArcReverse", specID))
end

-- Verifie si les elements doivent etre visibles (en combat uniquement)
function ResourceCircle.ShouldShow()
  if ns.IsInBlockedState() then return false end
  if ns.skyridingActive and ns.GetCfg("skyriding").hideResourceCircle ~= false then return false end
  local cfg = ns.GetCfg("resourceCircle")
  if cfg.enabled == false then return false end
  -- "Toujours actif en instance" : ignore les transitions combat en donjon/raid.
  if cfg.alwaysInInstance and ns.inInstance then return true end
  local vMode = cfg.visibilityMode or "combat"
  if vMode == "always" then return true end
  -- Regle commune du mode "Cible uniquement", cf. ns.ShouldShowForTargetMode
  if vMode == "target" then return ns.ShouldShowForTargetMode() end
  -- "combat"
  if UnitAffectingCombat("player") then return true end
  return false
end

-- ═══ Delai Attaque auto (Forever) ═══════════════════════════════════════════════════════════════
-- Le client Forever fournit un minuteur natif : l'evenement PLAYER_SWING(swingDuration, swingType) part a
-- chaque attaque du joueur (le journal de combat est interdit aux addons ; meme source qu'EllesmereUI).
-- Affichage au choix : arc (moteur CircularProgress : rotation, angle, sens, miroir) ou simple barre.
-- Un OnUpdate ne tourne que pendant un delai en cours.
local SWING_RING_FMT = "Interface\\AddOns\\AishCore\\Media\\UI\\SwingRing%d.tga"
local SWING_BAR_TEX  = "Interface\\Buttons\\WHITE8x8"
local swingArc, swingArcCW, swingArcCCW, swingMask   -- cadre de l'arc, 2 CircularProgress (normal / miroir), masque en anneau
local swingBar, swingBarFull, swingBarL, swingBarR, swingBarBg
local swingEvt, swingDriver, swingPreviewTicker
local swingStart, swingDur
-- Entree / sortie : fondu + leger glissement vers le haut. swingAlpha = progression 0..1 (lineaire, adoucie a l'affichage)
local SWING_FADE_IN, SWING_FADE_OUT, SWING_SLIDE = 0.30, 0.30, 8
local swingAlpha, swingEnded = 0, false
local swingOpt = {}                            -- reglages utiles au dessin, relus a chaque ApplySwingSettings

-- prefix "swing" (arc) ou "swingBar" (barre) : chaque visualisation a sa couleur / couleur de spe
local function SwingColor(cfg, prefix)
  if cfg[prefix .. "UseSpecColor"] then
    local CLR = ns.Modules and ns.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get(cfg[prefix .. "SpecColorKey"] or "powercircle")
    if c then return c[1], c[2], c[3], c[4] or 1 end
  end
  local c = cfg[prefix .. "Color"] or { 1, 0.82, 0.2, 1 }
  return c[1], c[2], c[3], c[4] or 1
end

-- Une valeur secrete lance une erreur a la comparaison : toute duree illisible est ecartee (cf. EllesmereUI)
local function Plain(v)
  return not (issecretvalue and issecretvalue(v))
end

-- Dessine le secteur [w1, w2] (degres, sens horaire depuis le haut). Le sens antihoraire n'a pas besoin de
-- miroir : le miroir du moteur ne retourne que la texture (un disque est symetrique), pas le secteur. Il
-- suffit de placer le secteur du bon cote du point de depart.
local function SwingWedge(cp, w1, w2)
  if not cp then return end
  if w2 - w1 < 0.05 then cp:Hide(); return end
  local a1 = w1 % 360
  cp:Show()
  cp:SetProgress(a1, a1 + (w2 - w1))
end

-- p = fraction ecoulee du delai (0..1). Memes regles que la barre simple, le point de depart S jouant le role
-- du centre et le point oppose (S +/- A/2) celui des extremites :
--   cw / ccw          : un seul sens, l'arc croit (remplissage inverse) ou recule (vidage) depuis S.
--   miroir "out"      : deux moities partant de S, vers 1h, 2h, 3h... et vers 11h, 10h, 9h... : l'arc GRANDIT
--                       depuis S ; en remplissage inverse il SE VIDE depuis S (il reste a l'oppose).
--   miroir "in"       : les bords vont de l'oppose vers S : l'arc SE VIDE vers S ; en remplissage inverse
--                       il GRANDIT depuis l'oppose.
local function DrawSwingArc(p)
  local o = swingOpt
  local S, A = o.rot, o.angle
  if o.dir == "mirror_out" or o.dir == "mirror_in" then
    local h = A / 2
    local growing   = (o.dir == "mirror_out") ~= o.fillUp
    local fromStart = not o.fillUp            -- partie visible ancree en S, ou a l'oppose
    local v = growing and p or (1 - p)
    if fromStart then
      SwingWedge(swingArcCW,  S, S + v * h)
      SwingWedge(swingArcCCW, S - v * h, S)
    else
      SwingWedge(swingArcCW,  S + (1 - v) * h, S + h)
      SwingWedge(swingArcCCW, S - h, S - (1 - v) * h)
    end
    return
  end
  local v = o.fillUp and p or (1 - p)
  if o.dir == "ccw" then
    swingArcCW:Hide()
    if o.fillUp then SwingWedge(swingArcCCW, S - v * A, S)
    else SwingWedge(swingArcCCW, S - A, S - (1 - v) * A) end
  else
    swingArcCCW:Hide()
    if o.fillUp then SwingWedge(swingArcCW, S, S + v * A)
    else SwingWedge(swingArcCW, S + (1 - v) * A, S + A) end
  end
end

-- p = fraction ecoulee du delai (0..1)
local function DrawSwingBar(p)
  local o = swingOpt
  if o.barDir == "in" or o.barDir == "out" then
    -- Deux moities en miroir, positions de 0 (gauche) a 100 (droite), centre = 50.
    --   "out"            : un bord va de 50 vers 0, l'autre de 50 vers 100 -> la barre GRANDIT depuis le centre
    --   "out" + inverse  : memes bords, mais la barre SE VIDE depuis le centre (reste aux extremites)
    --   "in"             : un bord va de 0 vers 50, l'autre de 100 vers 50 -> la barre SE VIDE vers le centre
    --   "in"  + inverse  : memes bords, mais la barre GRANDIT depuis les extremites
    local growing    = (o.barDir == "out") ~= o.fillUp
    local fromCenter = not o.fillUp          -- ancrage de la partie visible : centre, ou extremites
    local v = growing and p or (1 - p)
    swingBarFull:Hide(); swingBarL:Show(); swingBarR:Show()
    swingBarL:SetReverseFill(fromCenter); swingBarR:SetReverseFill(not fromCenter)
    swingBarL:SetValue(v); swingBarR:SetValue(v)
  else
    local v = o.fillUp and p or (1 - p)
    swingBarL:Hide(); swingBarR:Hide(); swingBarFull:Show()
    -- ltr : plein a gauche au remplissage, vide a gauche au vidage (reste ancre a droite) ; rtl : l'inverse
    local anchoredLeft = (o.barDir ~= "rtl") == o.fillUp
    swingBarFull:SetReverseFill(not anchoredLeft)
    swingBarFull:SetValue(v)
  end
end

-- Barre animee par le MOTEUR : SetTimerDuration avance le remplissage a chaque frame, avec une precision
-- sub-pixel, la ou un SetValue pose depuis un OnUpdate avancait par a-coups visibles (meme methode
-- qu'EllesmereUI). Renvoie false si l'API n'existe pas : on retombe alors sur le dessin par OnUpdate.
local swingBarObjs = {}
local swingBarTimed = false
local function ArmSwingBar()
  swingBarTimed = false
  if ns._swingNoTimer then return false end   -- diagnostic : /swingdbg notimer
  if not (C_DurationUtil and C_DurationUtil.CreateDuration and Enum.StatusBarTimerDirection
          and Enum.StatusBarInterpolation and swingBarFull.SetTimerDuration) then return false end
  local o = swingOpt
  local DIR, IMM = Enum.StatusBarTimerDirection, Enum.StatusBarInterpolation.Immediate
  local function Arm(sb, reverse, growing)
    sb:SetReverseFill(reverse)
    local obj = swingBarObjs[sb]
    if not obj then obj = C_DurationUtil.CreateDuration(); swingBarObjs[sb] = obj end
    obj:SetTimeFromStart(swingStart, swingDur)
    sb:SetTimerDuration(obj, IMM, growing and DIR.ElapsedTime or DIR.RemainingTime)
  end
  local ok = pcall(function()
    if o.barDir == "in" or o.barDir == "out" then
      local growing    = (o.barDir == "out") ~= o.fillUp
      local fromCenter = not o.fillUp
      swingBarFull:Hide(); swingBarL:Show(); swingBarR:Show()
      Arm(swingBarL, fromCenter, growing); Arm(swingBarR, not fromCenter, growing)
    else
      swingBarL:Hide(); swingBarR:Hide(); swingBarFull:Show()
      local anchoredLeft = (o.barDir ~= "rtl") == o.fillUp
      Arm(swingBarFull, not anchoredLeft, o.fillUp)
    end
  end)
  swingBarTimed = ok
  return ok
end

local function StopSwingVisuals()
  if swingDriver then swingDriver:SetScript("OnUpdate", nil) end
  swingAlpha = 0
  if swingArc then swingArc:Hide() end
  if swingBar then swingBar:Hide() end
end

-- Applique fondu + glissement sur la visualisation active (arc ou barre)
local function ApplySwingAnim()
  local t = swingAlpha
  local e = 1 - (1 - t) * (1 - t) * (1 - t)        -- ease-out cubique
  local off = (1 - e) * SWING_SLIDE
  if swingOpt.barMode then
    swingBar:SetAlpha(e)
    swingBar:ClearAllPoints()
    swingBar:SetPoint("CENTER", bar, "CENTER", swingOpt.barX or 0, (swingOpt.barY or -58) - off)
  else
    swingArc:SetAlpha(e)
    swingArc:ClearAllPoints()
    swingArc:SetPoint("CENTER", bar, "CENTER", 0, -off)
  end
end

local function SwingTick(_, el)
  el = el or 0
  if not swingStart or not swingDur then StopSwingVisuals(); return end
  local p = (GetTime() - swingStart) / swingDur
  local active = p < 1
  if active then
    swingAlpha = math.min(1, swingAlpha + el / SWING_FADE_IN)
    if p < 0 then p = 0 end
  else
    swingAlpha = math.max(0, swingAlpha - el / SWING_FADE_OUT)
    p = 1
  end
  -- Une derniere passe a p = 1 fige l'etat final (barre / arc plein en remplissage) pendant le fondu de sortie
  if active or not swingEnded then
    if swingOpt.barMode then
      if not swingBarTimed then DrawSwingBar(p) end
    else
      DrawSwingArc(p)
    end
    if not active then swingEnded = true end
  end
  ApplySwingAnim()
  if not active and swingAlpha <= 0 then StopSwingVisuals() end
end

local function StartSwing(dur)
  if not swingDriver or type(dur) ~= "number" or not Plain(dur) or dur ~= dur or dur <= 0 or dur == math.huge then return end
  swingStart, swingDur = GetTime(), dur
  swingEnded = false
  if swingOpt.barMode then
    swingBar:Show(); swingArc:Hide()
    ArmSwingBar()
  else
    swingArc:Show(); swingBar:Hide()
  end
  swingDriver:SetScript("OnUpdate", SwingTick)
  SwingTick()
end

-- Main droite et tir uniquement : la main gauche garde son propre rythme et ferait doublon
local function OnSwingEvent(_, event, dur, swingType)
  if event ~= "PLAYER_SWING" or not (Plain(dur) and Plain(swingType)) then return end
  local T = Enum.PlayerSwingType
  if swingType == T.MainHand or swingType == T.Ranged then StartSwing(dur) end
end

-- Apercu : tant que le panneau d'options est ouvert, un faux delai se relance en boucle
local function RefreshSwingPreview()
  local cfg = ns.GetCfg("resourceCircle") or {}
  if previewMode and cfg.swingEnabled and swingDriver then
    if not swingPreviewTicker then
      swingPreviewTicker = C_Timer.NewTicker(2.4, function() StartSwing(2.0) end)
    end
    StartSwing(2.0)
  elseif swingPreviewTicker then
    swingPreviewTicker:Cancel(); swingPreviewTicker = nil
  end
end

local function EnsureSwingFrames()
  if swingArc then return end
  swingDriver = CreateFrame("Frame", nil, bar)
  -- Arc : deux CircularProgress, le second en miroir (sens antihoraire)
  swingArc = CreateFrame("Frame", nil, bar)
  swingArc:SetPoint("CENTER", bar, "CENTER", 0, 0)
  swingArcCW  = ns.CircularProgress.create(swingArc, "ARTWORK", 0)
  swingArcCCW = ns.CircularProgress.create(swingArc, "ARTWORK", 0)
  -- Le moteur decoupe des secteurs en deplaçant les coins d'une texture : sur une texture d'ANNEAU, les bords
  -- degeneres du secteur laissent des filets (une croix au centre). On decoupe donc un DISQUE plein, et c'est
  -- un masque en anneau qui donne la forme finale.
  swingMask = swingArc:CreateMaskTexture()
  swingMask:SetAllPoints(swingArc)
  for _, cp in ipairs({ swingArcCW, swingArcCCW }) do
    for i = 1, 3 do cp.textures[i]:AddMaskTexture(swingMask) end
  end
  swingArc:Hide()
  -- Barre : une barre pleine (gauche/droite) et deux moities (vers le centre / l'exterieur)
  swingBar = CreateFrame("Frame", nil, bar)
  swingBar:SetPoint("CENTER", bar, "CENTER", 0, 0)
  swingBarBg = swingBar:CreateTexture(nil, "BACKGROUND")
  swingBarBg:SetAllPoints()
  swingBarBg:SetColorTexture(0, 0, 0, 0.45)
  local function MakeBar()
    local b = CreateFrame("StatusBar", nil, swingBar)
    ns.SetSmoothStatusBarTexture(b, SWING_BAR_TEX)
    -- Sans accrochage a la grille de pixels : la largeur du remplissage avance en continu au lieu de sauter d'1 px
    local bt = b:GetStatusBarTexture()
    if bt then bt:SetSnapToPixelGrid(false); bt:SetTexelSnappingBias(0) end
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    return b
  end
  swingBarFull, swingBarL, swingBarR = MakeBar(), MakeBar(), MakeBar()
  swingBar:Hide()
end

-- /swingdbg : etat du delai d'attaque auto (diagnostic) ; "/swingdbg test" lance un faux delai de 3 s
SLASH_AISHSWINGDBG1 = "/swingdbg"
SlashCmdList["AISHSWINGDBG"] = function(msg)
  local P = "|cff33aaff[Swing]|r "
  local cfg = ns.GetCfg("resourceCircle") or {}
  print(P .. string.format("forever=%s api=%s enabled=%s barMode=%s dir=%s strata=%s ratio=%s epaisseur=%s angle=%s rot=%s",
    tostring(ns.IsForever), tostring(C_SwingTimer ~= nil and Enum.PlayerSwingType ~= nil), tostring(cfg.swingEnabled),
    tostring(cfg.swingBarMode), tostring(cfg.swingDirection), tostring(cfg.swingStrata), tostring(cfg.swingSizeRatio),
    tostring(cfg.swingThickness), tostring(cfg.swingAngle), tostring(cfg.swingRotation)))
  if msg == "nomask" and swingMask then
    for _, cp in ipairs({ swingArcCW, swingArcCCW }) do
      for i = 1, 3 do cp.textures[i]:RemoveMaskTexture(swingMask) end
    end
    print(P .. "masque retire des textures de l'arc")
  elseif msg == "maskcircle" and swingMask then
    swingMask:SetTexture(ns.Media.circle, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    print(P .. "masque remplace par le disque plein (ns.Media.circle)")
  end
  if msg == "notimer" then ns._swingNoTimer = not ns._swingNoTimer; print(P .. "minuteur du moteur pour la barre : " .. (ns._swingNoTimer and "DESACTIVE (dessin manuel)" or "actif")) end
  if msg == "test" or msg == "nomask" or msg == "maskcircle" or msg == "notimer" then StartSwing(3.0) end
  print(P .. string.format("cadres : arc=%s barre=%s driver=%s | arcShown=%s arcVisible=%s", tostring(swingArc ~= nil),
    tostring(swingBar ~= nil), tostring(swingDriver ~= nil), tostring(swingArc and swingArc:IsShown()),
    tostring(swingArc and swingArc:IsVisible())))
  if swingArc then
    print(P .. string.format("arc : taille=%.0fx%.0f niveau=%s alpha=%.2f masque=%s", swingArc:GetWidth(), swingArc:GetHeight(),
      tostring(swingArc:GetFrameLevel()), swingArc:GetEffectiveAlpha(), tostring(swingMask and swingMask:GetTexture())))
    for k, cp in pairs({ CW = swingArcCW, CCW = swingArcCCW }) do
      local t = {}
      for i = 1, 3 do t[i] = tostring(cp.textures[i]:IsShown()) end
      print(P .. string.format("  %s : visible=%s textures=%s angles=%s..%s tex=%s", k, tostring(cp.visible), table.concat(t, "/"),
        tostring(cp.angle1), tostring(cp.angle2), tostring(cp.textures[1]:GetTexture())))
    end
  end
  print(P .. string.format("delai : debut=%s duree=%s maintenant=%.2f", tostring(swingStart), tostring(swingDur), GetTime()))
end

function ResourceCircle.ApplySwingSettings()
  if not ns.IsForever or not bar then return end
  if not (C_SwingTimer and Enum.PlayerSwingType) then return end  -- minuteur natif absent : rien a afficher
  local cfg = ns.GetCfg("resourceCircle") or {}
  if not cfg.swingEnabled then
    if swingEvt then swingEvt:UnregisterAllEvents() end
    if swingPreviewTicker then swingPreviewTicker:Cancel(); swingPreviewTicker = nil end
    StopSwingVisuals()
    return
  end
  EnsureSwingFrames()

  swingOpt.barMode = cfg.swingBarMode and true or false
  -- Remplissage inverse propre a chaque visualisation (arc / barre)
  swingOpt.fillUp  = (cfg.swingBarMode and cfg.swingBarFillUp or (not cfg.swingBarMode and cfg.swingFillUp)) and true or false
  swingOpt.dir     = cfg.swingDirection or "cw"
  if swingOpt.dir == "mirror" then swingOpt.dir = "mirror_out" end   -- ancien nom du reglage
  swingOpt.rot     = cfg.swingRotation or 0
  swingOpt.angle   = math.max(1, math.min(360, cfg.swingAngle or 360))
  swingOpt.barDir  = cfg.swingBarDirection or "ltr"
  swingOpt.barX, swingOpt.barY = cfg.swingBarX or 0, cfg.swingBarY or -58

  -- Plan : niveau de frame. bg = derriere le fond de l'anneau central ; mid = niveau des arcs de ressource
  -- secondaire ; front = au-dessus de tout sauf du texte.
  local function LevelFor(mode)
    if mode == "bg" then
      return math.max(0, bar:GetFrameLevel() - 1)
    elseif mode == "front" then
      return (bar.textFrame and bar.textFrame:GetFrameLevel() or (bar:GetFrameLevel() + 200)) - 1
    end
    return bar.durationArcFrame and bar.durationArcFrame:GetFrameLevel() or (bar:GetFrameLevel() + 2)
  end
  local lvlArc = LevelFor(cfg.swingStrata or "mid")
  local lvlBar = LevelFor("front")   -- la barre n'a pas de reglage de plan : toujours devant
  local r, g, b, a = SwingColor(cfg, "swing")
  local br, bg_, bb, ba = SwingColor(cfg, "swingBar")

  -- Arc
  local d = (cfg.size or 80) * (cfg.swingSizeRatio or 1.15)
  swingArc:SetSize(d, d)
  swingArc:SetFrameLevel(lvlArc)
  local tex = string.format(SWING_RING_FMT, math.max(1, math.min(8, math.floor((cfg.swingThickness or 3) + 0.5))))
  swingMask:SetTexture(tex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  for _, cp in ipairs({ swingArcCW, swingArcCCW }) do
    ns.CircularProgress.modify(cp, {
      texture = ns.Media.circle, blendMode = "BLEND", width = d, height = d, crop_x = 1, crop_y = 1,
      mirror = false,
    })
    cp:SetColor(r, g, b, a)
  end

  -- Barre
  local len, thick = cfg.swingBarLength or 120, cfg.swingBarThickness or 8
  swingBar:SetSize(len, thick)
  swingBar:ClearAllPoints()
  swingBar:SetPoint("CENTER", bar, "CENTER", cfg.swingBarX or 0, cfg.swingBarY or -58)
  swingBar:SetFrameLevel(lvlBar)
  local bgc = cfg.swingBarBgColor or { 0, 0, 0, 0.45 }
  swingBarBg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4] or 1)
  swingBarFull:SetAllPoints(swingBar)
  swingBarL:ClearAllPoints(); swingBarL:SetPoint("TOPLEFT", swingBar, "TOPLEFT"); swingBarL:SetPoint("BOTTOMRIGHT", swingBar, "BOTTOM")
  swingBarR:ClearAllPoints(); swingBarR:SetPoint("TOPRIGHT", swingBar, "TOPRIGHT"); swingBarR:SetPoint("BOTTOMLEFT", swingBar, "BOTTOM")
  for _, sb in ipairs({ swingBarFull, swingBarL, swingBarR }) do
    sb:SetFrameLevel(lvlBar + 1)
    sb:SetStatusBarColor(br, bg_, bb, ba)
  end

  if not swingEvt then
    swingEvt = CreateFrame("Frame")
    swingEvt:SetScript("OnEvent", OnSwingEvent)
  end
  swingEvt:RegisterEvent("PLAYER_SWING")
  -- Delai en cours : on le redessine avec les nouveaux reglages
  if swingStart and swingDur and GetTime() < swingStart + swingDur then
    if swingOpt.barMode then swingBar:Show(); swingArc:Hide(); ArmSwingBar() else swingArc:Show(); swingBar:Hide() end
    swingAlpha = 1
    swingDriver:SetScript("OnUpdate", SwingTick)
  else
    StopSwingVisuals()
  end
  RefreshSwingPreview()
end

-- Applique les settings en live (taille, police, etc.)
function ResourceCircle.ApplySettings()
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")

  -- Gerer l'activation/desactivation en live
  if cfg.enabled == false then
    if animationTicker then animationTicker:Cancel(); animationTicker = nil end
    if moveTicker then moveTicker:Cancel(); moveTicker = nil end
    -- Desactivation live : interruption immediate, on remet le verrou de file d'attente a plat.
    rcAnimBusy = false
    rcAnimDirty = false
    bar:Hide()
    lastVisibilityState = nil
    return
  end
  -- Forcer un re-check de visibilite (le module vient peut-etre d'etre reactive)
  lastVisibilityState = nil

  ResourceCircle.EnsureArcSettings()
  local size   = cfg.size
  local bgSize = size * 1.1
  bar:SetSize(size, size)
  bar.bgLarge:SetSize(bgSize, bgSize)
  bar.bgLarge:ClearAllPoints()
  bar.bgLarge:SetPoint("BOTTOM", bar, "CENTER", 0, -bgSize / 2)
  RecordHome(bar.bgLarge, "BOTTOM", bar, "CENTER", 0, -bgSize / 2, bgSize, bgSize)
  -- Repositionner la frame (la position peut avoir changé via un autre profil)
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
  -- Glow
  if bar.bgGlow then
    local glowEnabled = cfg.glowEnabled ~= false
    local glowPixelSize = math.floor(bgSize * (cfg.glowSize or 1.0) + 0.5)
    bar.bgGlow:SetSize(glowPixelSize, glowPixelSize)
    bar.bgGlow:ClearAllPoints()
    bar.bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.bgGlow:SetAlpha(cfg.glowOpacity or 0.85)
    if glowEnabled then bar.bgGlow:Show() else bar.bgGlow:Hide() end
    RecordHome(bar.bgGlow, "CENTER", bar, "CENTER", 0, 0, glowPixelSize, glowPixelSize)
  end
  -- Fond de texte : le home doit suivre, sinon la prochaine animation le remettrait a
  -- son ancienne taille (cf. RecordHome / _elemHome).
  if bar.textBackdrop then
    local tbPx = math.max(1, cfg.textBackdropSize or 35)
    bar.textBackdrop:SetSize(tbPx, tbPx)
    bar.textBackdrop:ClearAllPoints()
    bar.textBackdrop:SetPoint("CENTER", bar, "CENTER", 0, 0)
    RecordHome(bar.textBackdrop, "CENTER", bar, "CENTER", 0, 0, tbPx, tbPx)
    ns.SizeTextBackdropGlow(bar.textBackdropGlow, tbPx)
  end
  local arcPx     = ArcPx(cfg)
  local overlayPx = OverlayPx(cfg, arcPx)
  bar.arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  bar.arc:ClearAllPoints()
  bar.arc:SetPoint("BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H)
  RecordHome(bar.arc, "BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H, arcPx, arcPx * ARC_CROP_H)
  if bar.overlay then
    if overlayPx >= 2 then
      bar.overlay:SetSize(overlayPx, overlayPx)
      bar.overlay:Show()
      if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    else
      bar.overlay:SetSize(0.01, 0.01)
      bar.overlay:Hide()
    end
    bar.overlay:ClearAllPoints()
    bar.overlay:SetPoint("BOTTOM", bar, "CENTER", 0, -overlayPx / 2)
    local ovHome = math.max(overlayPx, 0.01)
    RecordHome(bar.overlay, "BOTTOM", bar, "CENTER", 0, -overlayPx / 2, ovHome, ovHome)
  end
  -- Redimensionner l'arc de stagger quand les settings changent
  if bar.staggerArc then
    local stagArcPx = arcPx * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
    bar.staggerArc:SetSize(stagArcPx, stagArcPx * ARC_CROP_H)
    bar.staggerArc:ClearAllPoints()
    bar.staggerArc:SetPoint("TOP", bar, "CENTER", 0, stagArcPx / 2)
    RecordHome(bar.staggerArc, "TOP", bar, "CENTER", 0, stagArcPx / 2, stagArcPx, stagArcPx * ARC_CROP_H)
    if bar.staggerOverlay then
      local stagOvPx = stagArcPx * StaggerHole(cfg)
      bar.staggerOverlay:SetSize(math.max(stagOvPx, 0.01), math.max(stagOvPx, 0.01))
      RecordHome(bar.staggerOverlay, "CENTER", bar, "CENTER", 0, 0, math.max(stagOvPx, 0.01), math.max(stagOvPx, 0.01))
    end
  end
  ns.ApplyFontReliable(bar.text, "RCText",
    function() local c = ns.GetCfg("resourceCircle"); return c and c.font or ns.Media.font end,
    function() local c = ns.GetCfg("resourceCircle"); return c and c.fontSize or cfg.fontSize end)
  -- Geometrie dependante de la spec : specID resolu fraichement ici (pas via ns._specID,
  -- pas encore rempli au login a ce stade) pour eviter d'ecraser la geometrie par-spec au login/reload.
  local specID = nil
  if GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx and idx > 0 then
      local ok, sid = pcall(GetSpecializationInfo, idx)
      if ok and sid and sid > 0 then specID = sid end
    end
  end
  ResourceCircle.RefreshSecResSpecGeometry(specID)
  -- Redimensionner les dots proportionnellement
  local baseSize = ns.Defaults.resourceCircle.size
  local scale = size / baseSize
  -- dotSizes et dotPositions viennent toujours des defaults (pas modifiables via GUI)
  local dotSizes = ns.Defaults.resourceCircle.dotSizes
  local dotPositions = ns.Defaults.resourceCircle.dotPositions
  for i = 1, 5 do
    local dot = bar["dot" .. i]
    if dot then
      dot:SetSize(dotSizes[i] * scale, dotSizes[i] * scale)
      dot:ClearAllPoints()
      dot:SetPoint("BOTTOM", bar, "BOTTOM", dotPositions[i][1] * scale, dotPositions[i][2] * scale)
      RecordHome(dot, "BOTTOM", bar, "BOTTOM", dotPositions[i][1] * scale, dotPositions[i][2] * scale,
        dotSizes[i] * scale, dotSizes[i] * scale)
    end
  end
  -- Appliquer les couleurs de la ressource active
  ResourceCircle.UpdateResourceColors()
  -- Re-detecter les secondary dots (option allSpecs, spec change)
  ResourceCircle.DetectSecondaryDots()
  -- Repositionner les secondary dots (runes, combo points)
  ResourceCircle.LayoutSecDots()

  ApplyArcAngles()

  -- Delai Attaque auto (Forever)
  ResourceCircle.ApplySwingSettings()

  -- Forcer la visibilite apres changement de settings
  if previewMode then
    ResourceCircle.SetPreview(true)
  else
    ResourceCircle.UpdateVisibility()
  end
end

-- Couleur de l'arriere plan : fond du cercle et tous les masques qui doivent lui ressembler (masque central, masques des
-- arcs de stagger / de duree, fond du texte, fond des orbes secondaires). Reglage cfg.bgColor.
local DEFAULT_BG = { 0x0e/255, 0x0e/255, 0x0e/255, 1 }
local function GetBgColor()
  local cfg = ns.GetCfg("resourceCircle")
  if not cfg or cfg.themedColors ~= false then return DEFAULT_BG end   -- couleurs thematiques : fond d'origine
  return cfg.bgColor or DEFAULT_BG
end

-- Met a jour les couleurs (arcs, texte, dots) selon la ressource primaire du joueur
function ResourceCircle.UpdateResourceColors()
  if not bar then return end
  local powerType = ns.GetPlayerResource()
  local colors    = ns.GetResourceColors(powerType)
  local CLR       = ns.Modules.Colors

  -- Colors.Get() prend priorité sur les couleurs de ressource (thème par spé)
  local arcC  = (CLR and CLR.Get("powercircle")) or colors.bar
  local textC = (CLR and CLR.Get("powertext"))   or colors.text
  -- Couleurs thematiques decochees : couleur de l'arc et du texte de ressource choisies dans les reglages
  local cfgC = ns.GetCfg("resourceCircle")
  if cfgC and cfgC.themedColors == false then
    arcC  = cfgC.arcColor  or arcC
    textC = cfgC.textColor or textC
  end
  local bgC = GetBgColor()
  for _, k in ipairs({ "bgLarge", "overlay", "staggerOverlay", "durationOvl", "textBackdrop" }) do
    if bar[k] then bar[k]:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1) end
  end
  for _, f in pairs(secDots) do
    if f.bg then f.bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4] or 1) end
  end
  -- Outer dots (indices 1,2,4,5) → powerdotsa ; central (3) → powerdotsb
  local dotsA = (CLR and CLR.Get("powerdotsa"))  or colors.bar
  local dotsB = (CLR and CLR.Get("powerdotsb"))  or colors.bar
  -- dot 3 = gros central → powerdotsA ; dots 1,2,4,5 = petits → powerdotsB
  local DOT_C = { dotsB, dotsB, dotsA, dotsB, dotsB }

  -- Glow color (couleur de spec)
  if bar.bgGlow then
    local glowC = (CLR and CLR.Get("glow")) or {1, 1, 1, 1}
    bar.bgGlow:SetVertexColor(glowC[1], glowC[2], glowC[3], 1)
  end
  -- Arc
  if bar.arc then bar.arc:SetStatusBarColor(arcC[1], arcC[2], arcC[3], arcC[4] or 1) end
  -- Texte
  bar.text:SetTextColor(textC[1], textC[2], textC[3], textC[4] or 1)
  -- Dots
  for i = 1, 5 do
    local dot = bar["dot" .. i]
    if dot then
      local c = DOT_C[i]
      dot:SetVertexColor(c[1], c[2], c[3], 1)
    end
  end
  lastResourceType = powerType
end

-- Appele quand le type de ressource change (spec, forme druide)
-- Retourne true si la ressource a effectivement change
function ResourceCircle.OnResourceChanged()
  if not bar then return false end
  local powerType = ns.GetPlayerResource()
  if powerType == lastResourceType then return false end
  ResourceCircle.UpdateResourceColors()
  ResourceCircle.Update()
  -- Re-detecter les secondary dots (druide forme chat <-> caster)
  ResourceCircle.DetectSecondaryDots()
  -- Re-detecter la ressource secondaire (changement de spec/forme)
  ResourceCircle.DetectSecondaryResource()
  -- Re-detecter l'arc de stagger (changement de spec)
  ResourceCircle.DetectStagger()
  -- Utilise le cache (mis a jour au login + PLAYER_SPECIALIZATION_CHANGED)
  local playerClass2 = ns._playerClass or ""
  local specID2      = ns._specID
  local SE_rc = ns.Modules and ns.Modules.SpellEffects
  -- Reset état Fire Mage si on n'est plus Mage Feu
  if not (playerClass2 == "MAGE" and specID2 == 63) then
    fireOverlayActive = false
    firePyroGlowing   = false
    if fireProcLevel ~= 0 then
      fireProcLevel = 0
      if SE_rc and SE_rc.StopSustained then
        SE_rc.StopSustained(9000001)
        SE_rc.StopSustained(9000002)
      end
    end
  end
  -- Reset Essence Burst si on n'est plus Evoker Preservation
  if not (playerClass2 == "EVOKER" and specID2 == 1468) then
    if essenceBurstActive then
      essenceBurstActive = false
      for k in pairs(essenceBurstGlowing) do essenceBurstGlowing[k] = nil end
      if SE_rc and SE_rc.StopSustained then SE_rc.StopSustained(9000003) end
    end
  end
  -- Reset Maelstrom Weapon si on n'est plus Shaman Enhancement
  if not (playerClass2 == "SHAMAN" and specID2 == 263) then
    if mwStackLevel ~= 0 then
      mwStackLevel = 0
      if SE_rc and SE_rc.StopSustained then
        SE_rc.StopSustained(9000004)
        SE_rc.StopSustained(9000005)
        SE_rc.StopSustained(9000006)
      end
    end
  end
  -- Reset Demonic Core si on n'est plus Warlock Démonologie (specID 266, pas 265=Affliction)
  if not (playerClass2 == "WARLOCK" and specID2 == 266) then
    demonicCoreStacks        = 0
    demonicCoreOverlayActive = false
  end
  return true
end

-- Création de la StatusBar circulaire avec 2 arcs
function ResourceCircle.Create(parent)
  if bar then return bar end
  local cfg = ns.GetCfg("resourceCircle")

  ResourceCircle.EnsureArcSettings()
  bar = CreateFrame("Frame", "AishCoreRingBar", parent)
  bar:SetSize(cfg.size, cfg.size)
  bar:SetPoint("CENTER", parent, "CENTER", cfg.x, cfg.y)

  -- Glow de fond (DERRIERE bgLarge, sublevel -1)
  local bgGlow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  ns.SetSmoothTexture(bgGlow, "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga")
  bgGlow:SetBlendMode("ADD")
  bgGlow:SetDesaturated(true)
  local glowPixelSize = math.floor((cfg.size * 1.1) * (cfg.glowSize or 1.0) + 0.5)
  bgGlow:SetSize(glowPixelSize, glowPixelSize)
  bgGlow:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bgGlow:SetAlpha(cfg.glowOpacity or 0.85)
  if cfg.glowEnabled == false then bgGlow:Hide() end
  bar.bgGlow = bgGlow
  RecordHome(bgGlow, "CENTER", bar, "CENTER", 0, 0, glowPixelSize, glowPixelSize)

  -- Grand fond opaque
  local bgLarge = bar:CreateTexture(nil, "BACKGROUND")
  ns.SetSmoothTexture(bgLarge, ns.Media.circle)
  bgLarge:SetSize(cfg.bgSize, cfg.bgSize)
  bgLarge:SetPoint("BOTTOM", bar, "CENTER", 0, -cfg.bgSize / 2)
  bgLarge:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bgLarge
  RecordHome(bgLarge, "BOTTOM", bar, "CENTER", 0, -cfg.bgSize / 2, cfg.bgSize, cfg.bgSize)

  -- Arc (remplissage radial natif sur un disque plein)
  local arcPx = ArcPx(cfg)
  local arc = CreateFrame("StatusBar", "AishCoreRingBarArc", bar)
  arc:SetFrameLevel(bar:GetFrameLevel() + 1)
  arc:SetSize(arcPx, arcPx * ARC_CROP_H)
  arc:SetPoint("BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H)
  SetupRadialArc(arc)
  arc:SetMinMaxValues(0, 100)
  arc:SetValue(0)
  arc:Show()
  bar.arc = arc
  RecordHome(arc, "BOTTOM", bar, "CENTER", 0, arcPx / 2 - arcPx * ARC_CROP_H, arcPx, arcPx * ARC_CROP_H)

  -- Overlay sombre : masque le centre pour simuler un arc en anneau
  local overlayPx = OverlayPx(cfg, arcPx)
  local overlayFrame = CreateFrame("Frame", nil, bar)
  overlayFrame:SetFrameLevel(arc:GetFrameLevel() + 1)
  overlayFrame:SetAllPoints(bar)
  local overlay = overlayFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(overlay, ns.Media.circle)
  if overlayPx >= 2 then overlay:SetSize(overlayPx, overlayPx) else overlay:SetSize(0.01, 0.01); overlay:Hide() end
  overlay:SetPoint("BOTTOM", bar, "CENTER", 0, -overlayPx / 2)
  overlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.overlay = overlay
  bar.overlayFrame = overlayFrame
  RecordHome(overlay, "BOTTOM", bar, "CENTER", 0, -overlayPx / 2, overlayPx, overlayPx)

  -- Arc de stagger (Moine Brasseur) : s'inscrit dans le trou laissé par l'overlay principal
  local staggerFrame = CreateFrame("Frame", nil, bar)
  staggerFrame:SetFrameLevel(overlayFrame:GetFrameLevel() + 1)
  staggerFrame:SetAllPoints(bar)

  local staggerArcPx = arcPx * (cfg.staggerArcRatio or STAGGER_ARC_RATIO)
  local staggerArc = CreateFrame("StatusBar", nil, staggerFrame)
  staggerArc:SetFrameLevel(staggerFrame:GetFrameLevel())
  staggerArc:SetSize(staggerArcPx, staggerArcPx * ARC_CROP_H)
  staggerArc:SetPoint("TOP", bar, "CENTER", 0, staggerArcPx / 2)
  SetupRadialArc(staggerArc)
  staggerArc:SetMinMaxValues(0, 100)
  staggerArc:SetValue(0)
  staggerArc:SetStatusBarColor(STAGGER_LIGHT[1], STAGGER_LIGHT[2], STAGGER_LIGHT[3], 1)
  staggerArc:Hide()
  bar.staggerArc   = staggerArc
  bar.staggerFrame = staggerFrame
  RecordHome(staggerArc, "TOP", bar, "CENTER", 0, staggerArcPx / 2, staggerArcPx, staggerArcPx * ARC_CROP_H)

  local staggerOverlayFrame = CreateFrame("Frame", nil, bar)
  staggerOverlayFrame:SetFrameLevel(staggerFrame:GetFrameLevel() + 1)
  staggerOverlayFrame:SetAllPoints(bar)
  local staggerOverlay = staggerOverlayFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(staggerOverlay, ns.Media.circle)
  local staggerOverlayPx = staggerArcPx * StaggerHole(cfg)
  staggerOverlay:SetSize(math.max(staggerOverlayPx, 0.01), math.max(staggerOverlayPx, 0.01))
  staggerOverlay:SetPoint("CENTER", bar, "CENTER", 0, 0)
  RecordHome(staggerOverlay, "CENTER", bar, "CENTER", 0, 0, math.max(staggerOverlayPx, 0.01), math.max(staggerOverlayPx, 0.01))
  staggerOverlay:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  staggerOverlayFrame:Hide()
  bar.staggerOverlay      = staggerOverlay
  bar.staggerOverlayFrame = staggerOverlayFrame

  -- Arc de durée (Pala Prot / Guerrier Prot / DK Sang) : parallèle au stagger, mutuellement exclusif
  -- Arc de durée (même approche que stagger : StatusBar radiale native)
  local durationArcPx = arcPx * (ns.GetSecResCfg("durationArcRatio") or DURATION_ARC_RATIO)
  local durationArcFrame = CreateFrame("Frame", nil, bar)
  durationArcFrame:SetFrameLevel(staggerFrame:GetFrameLevel())
  durationArcFrame:SetAllPoints(bar)
  local durationArcBar = CreateFrame("StatusBar", nil, durationArcFrame)
  durationArcBar:SetFrameLevel(durationArcFrame:GetFrameLevel())
  durationArcBar:SetSize(durationArcPx, durationArcPx * ARC_CROP_H)
  durationArcBar:SetPoint("TOP", bar, "CENTER", 0, durationArcPx / 2)
  RecordHome(durationArcBar, "TOP", bar, "CENTER", 0, durationArcPx / 2, durationArcPx, durationArcPx * ARC_CROP_H)
  SetupRadialArc(durationArcBar)
  durationArcBar:SetMinMaxValues(0, 1)
  durationArcBar:SetValue(0)
  durationArcBar:Hide()
  -- Barre verticale (vide de haut en bas) pour les sources dont la plage est secrete : impossible de la mettre a l'echelle
  -- d'une etendue d'arc, on garde donc l'ancien rendu pour elles.
  local durationArcV = CreateFrame("StatusBar", nil, durationArcFrame)
  durationArcV:SetFrameLevel(durationArcFrame:GetFrameLevel())
  durationArcV:SetSize(durationArcPx, durationArcPx * ARC_CROP_V)
  durationArcV:SetPoint("TOP", bar, "CENTER", 0, durationArcPx / 2)
  ns.SetSmoothStatusBarTexture(durationArcV, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  durationArcV:SetOrientation("VERTICAL")
  durationArcV:SetMinMaxValues(0, 1)
  durationArcV:SetValue(0)
  durationArcV:Hide()
  RecordHome(durationArcV, "TOP", bar, "CENTER", 0, durationArcPx / 2, durationArcPx, durationArcPx * ARC_CROP_V)
  bar.durationArcV     = durationArcV
  bar.durationArc      = durationArcBar
  bar.durationArcFrame = durationArcFrame

  local durationOvlFrame = CreateFrame("Frame", nil, bar)
  durationOvlFrame:SetFrameLevel(staggerOverlayFrame:GetFrameLevel())
  durationOvlFrame:SetAllPoints(bar)
  local durationOvl = durationOvlFrame:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(durationOvl, ns.Media.circle)
  local durationOvlPx = durationArcPx * DurationHole()
  durationOvl:SetSize(math.max(durationOvlPx, 0.01), math.max(durationOvlPx, 0.01))
  durationOvl:SetPoint("CENTER", bar, "CENTER", 0, 0)
  RecordHome(durationOvl, "CENTER", bar, "CENTER", 0, 0, math.max(durationOvlPx, 0.01), math.max(durationOvlPx, 0.01))
  durationOvl:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  durationOvlFrame:Hide()
  bar.durationOvlFrame = durationOvlFrame
  bar.durationOvl      = durationOvl

  -- Texte + dots sur un frame superieur a staggerOverlayFrame (sinon cachés derrière)
  local textFrame = CreateFrame("Frame", nil, bar)
  textFrame:SetFrameLevel(staggerOverlayFrame:GetFrameLevel() + 1)
  textFrame:SetAllPoints(bar)

  -- 5 petits cercles colorés en bas (sur textFrame pour passer au-dessus de l'overlay)
  local initDotSizes = ns.Defaults.resourceCircle.dotSizes
  local initDotPositions = ns.Defaults.resourceCircle.dotPositions
  for i = 1, 5 do
    local dot = textFrame:CreateTexture(nil, "OVERLAY")
    dot:SetTexture(ns.Media.circle)
    dot:SetSize(initDotSizes[i], initDotSizes[i])
    dot:SetPoint("BOTTOM", bar, "BOTTOM", initDotPositions[i][1], initDotPositions[i][2])
    dot:SetVertexColor(cfg.dotColors[i][1], cfg.dotColors[i][2], cfg.dotColors[i][3], 1)
    bar["dot" .. i] = dot
    RecordHome(dot, "BOTTOM", bar, "BOTTOM", initDotPositions[i][1], initDotPositions[i][2], initDotSizes[i], initDotSizes[i])
  end

  local text = textFrame:CreateFontString(nil, "OVERLAY")
  text:SetFont(ns.Media.font, cfg.fontSize)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  text:SetTextColor(unpack(cfg.textColor))
  bar.text = text
  RecordHome(text, "CENTER", bar, "CENTER", 0, 0)
  bar.textFrame = textFrame
  ns.ringBarTextFrame = textFrame  -- exposé pour SpellEffects (frame level de référence)

  -- Texte de ressource secondaire (Bone Shield, Soul Fragments, etc.)
  -- Affiché sous le texte de puissance (bar.text), sur un frame UIParent.
  local secResFrame = CreateFrame("Frame", nil, UIParent)
  secResFrame:SetSize(120, 18)
  secResFrame:SetFrameLevel(textFrame:GetFrameLevel() + 1)
  secResFrame:SetPoint("TOP", text, "BOTTOM", 0, -2)
  bar.secResFrame = secResFrame

  local secResText = secResFrame:CreateFontString(nil, "OVERLAY")
  secResText:SetFont(FONT_SECRES_DEFAULT, 11, "")
  secResText:SetPoint("CENTER", secResFrame, "CENTER", 0, 0)
  secResText:SetTextColor(1, 1, 1, 1)
  secResText:SetText("")
  secResText:Hide()
  bar.secResText = secResText

  -- Déco "- N -" (style/espacement configurables, cf. RefreshSecResDeco) : FontStrings séparées ancrées aux bords de secResText.
  local secResDashL = secResFrame:CreateFontString(nil, "OVERLAY")
  secResDashL:SetFont(FONT_SECRES_DEFAULT, 11, "")
  secResDashL:SetTextColor(1, 1, 1, 1)
  secResDashL:Hide()
  bar.secResDashL = secResDashL

  local secResDashR = secResFrame:CreateFontString(nil, "OVERLAY")
  secResDashR:SetFont(FONT_SECRES_DEFAULT, 11, "")
  secResDashR:SetTextColor(1, 1, 1, 1)
  secResDashR:Hide()
  bar.secResDashR = secResDashR

  -- Barre de duree : moitie gauche remplie depuis sa DROITE (SetReverseFill), moitie
  -- droite depuis sa GAUCHE. Les deux se rejoignent au centre, donc a valeur egale on
  -- voit une seule barre qui se vide symetriquement par les deux extremites.
  -- Geometrie/couleur posees par RefreshSecResDurBar (par spec).
  for _, side in ipairs({ "L", "R" }) do
    local db = CreateFrame("StatusBar", nil, secResFrame)
    db:SetFrameLevel(secResFrame:GetFrameLevel())
    db:SetStatusBarTexture(ns.ResolveBarTexFromKey(nil))
    db:SetOrientation("HORIZONTAL")
    db:SetReverseFill(side == "L")
    db:SetMinMaxValues(0, 1)
    db:SetValue(0)
    db:Hide()
    bar["secResDur" .. side] = db
  end
  RefreshSecResDurBar()

  RefreshSecResDeco()

  -- Fond sombre sous le power text pour lisibilité (masqué pour Brasseur qui a son propre overlay)
  local tbPx = math.max(1, cfg.textBackdropSize or 35)
  local textBackdrop = textFrame:CreateTexture(nil, "BACKGROUND")
  textBackdrop:SetTexture(ns.Media.circle)
  textBackdrop:SetSize(tbPx, tbPx)
  textBackdrop:SetPoint("CENTER", bar, "CENTER", 0, 0)
  textBackdrop:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.textBackdrop = textBackdrop
  RecordHome(textBackdrop, "CENTER", bar, "CENTER", 0, 0, tbPx, tbPx)

  -- Halo de reperage : le cache est noir sur fond noir, invisible tant qu'on ne le regle
  -- pas. Allume par le slider du panneau (cf. ResourceCircle.FlashTextBackdrop), jamais en
  -- jeu -- il reste donc hors du systeme d'animation.
  bar.textBackdropGlow = ns.CreateTextBackdropGlow(textFrame, bar)
  ns.SizeTextBackdropGlow(bar.textBackdropGlow, tbPx)

  bar:Show()
  _G.AishCoreRingBar = bar

  -- Detecter le type de secondary dots selon la classe/forme
  ResourceCircle.DetectSecondaryDots()
  -- Detecter la ressource secondaire (Bone Shield, Soul Fragments…)
  ResourceCircle.DetectSecondaryResource()
  -- Detecter l'arc de stagger (Moine Brasseur)
  ResourceCircle.DetectStagger()
  -- Create() tourne a l'init de l'addon, bien avant que la spec soit lisible apres un
  -- /reload : sans ce retry les trois detecteurs ci-dessus restent sur "aucune spec".
  ResourceCircle.RetrySpecDetectionIfNeeded()
  -- Démarrer le frame d'animation slide des secondary dots
  ResourceCircle.CreateSecAnimFrame()

  -- Frame dédié au tracking Essence Burst + Fire Mage procs via spell overlay glow
  local overlayEvtFrame = CreateFrame("Frame")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
  overlayEvtFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
  overlayEvtFrame:SetScript("OnEvent", function(_, event, spellID)
    local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or (event == "SPELL_ACTIVATION_OVERLAY_SHOW")
    local isGlow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW") or (event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

    -- Essence Burst (Evoker Preservation) : glow sur sorts spécifiques
    if isGlow and ESSENCE_BURST_SPELLS[spellID] then
      if isShow then essenceBurstGlowing[spellID] = true
      else            essenceBurstGlowing[spellID] = nil end
      local any = false
      for _ in pairs(essenceBurstGlowing) do any = true break end
      local prevActive = essenceBurstActive
      essenceBurstActive = any
      -- Animer le combo SpellEffects uniquement pour Preservation (specID 1468)
      if essenceBurstActive ~= prevActive then
        local _, ebClass = UnitClass("player")
        if ebClass == "EVOKER" then
          local ebSpecIdx = GetSpecialization and GetSpecialization() or nil
          local ebSpecID = ebSpecIdx and (GetSpecializationInfo and GetSpecializationInfo(ebSpecIdx)) or nil
          if ebSpecID == 1468 then
            local SE_eb = ns.Modules and ns.Modules.SpellEffects
            if SE_eb then
              if essenceBurstActive then
                if SE_eb.StartSustained then SE_eb.StartSustained(9000003) end
              else
                if SE_eb.StopSustained then SE_eb.StopSustained(9000003) end
              end
            end
          end
        end
      end
    end

    -- Fire Mage (spec 2 = Fire uniquement)
    local _, playerClass = UnitClass("player")
    if playerClass == "MAGE" and GetSpecialization() == 2 then
      if not isGlow then
        -- SPELL_ACTIVATION_OVERLAY_SHOW/HIDE : overlay écran = Heating Up
        fireOverlayActive = isShow
      elseif FIRE_PYRO_SPELLS[spellID] then
        -- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE sur Pyroblast/Flamestrike = Hot Streak
        firePyroGlowing = isShow
      end
      local newLevel = firePyroGlowing and 2 or (fireOverlayActive and 1 or 0)
      if newLevel ~= fireProcLevel then
        local prevLevel = fireProcLevel
        fireProcLevel = newLevel
        if bar and bar.text then bar.text:SetText(tostring(fireProcLevel)) end
        -- Démarrer/arrêter l'animation soutenue SpellEffects selon l'état
        local SE = ns.Modules and ns.Modules.SpellEffects
        if SE then
          if newLevel == 0 then
            -- Aucun proc : tout éteindre immédiatement
            if SE.StopSustained then SE.StopSustained(9000001) end
            if SE.StopSustained then SE.StopSustained(9000002) end
          elseif newLevel == 1 then
            -- Heating Up actif : éteindre Hot Streak, allumer Heating Up
            if SE.StopSustained  then SE.StopSustained(9000002)  end
            if SE.StartSustained then SE.StartSustained(9000001) end
          elseif newLevel == 2 then
            -- Hot Streak actif : éteindre Heating Up, allumer Hot Streak
            if SE.StopSustained  then SE.StopSustained(9000001)  end
            if SE.StartSustained then SE.StartSustained(9000002) end
          end
        end
      end
    end

    -- Warlock Démonologie : Demonic Core → glow sur Demonbolt (264178)
    local _, wlClass = UnitClass("player")
    if isGlow and spellID == DEMONBOLT_SPELL_ID and wlClass == "WARLOCK" then
      local wlSpecIdx = GetSpecialization and GetSpecialization() or nil
      local wlSpecID  = wlSpecIdx and (GetSpecializationInfo and GetSpecializationInfo(wlSpecIdx)) or nil
      if wlSpecID == 266 then  -- Demonologie (265 = Affliction, cf. ns.SPEC_MAP)
        demonicCoreOverlayActive = isShow
      end
    end
  end)

  -- Pré-allouer la table d'éléments pour AnimateVisibility (11 slots fixes + 2 staggerArc conditionnels).
  do
    _rcAnimElems[1]  = { element = bar.bgGlow  }
    _rcAnimElems[2]  = { element = bar.bgLarge }
    _rcAnimElems[3]  = { element = bar.text    }
    -- Slots 4/5 (arc, overlayFrame) et 11/12 (staggerArc, staggerOverlayFrame) : animés par AnimateArcOverlay.
    _rcAnimElems[4]  = { element = nil }
    _rcAnimElems[5]  = { element = nil }
    _rcAnimElems[6]  = { element = bar.dot3 }
    _rcAnimElems[7]  = { element = bar.dot2 }
    _rcAnimElems[8]  = { element = bar.dot4 }
    _rcAnimElems[9]  = { element = bar.dot1 }
    _rcAnimElems[10] = { element = bar.dot5 }
    _rcAnimElems[11] = { element = nil }
    _rcAnimElems[12] = { element = nil }
    _rcAnimElems[13] = { element = bar.textBackdrop }
    _rcAnimElems[14] = { element = nil }  -- secResFrame (conditionnel : seulement si secResDef existe)
  end

  ApplyArcAngles()
  pcall(ResourceCircle.Update)

  return bar
end

-- Applique pct (0-100) a l'arc, interpole nativement (ns.SmoothBarValue).
local function ApplyArcValue(pct)
  pcall(ns.SmoothBarValue, bar.arc, pct)
end

-- Apercu du panneau : le remplissage monte progressivement de 50 a 100 %, marque une pause, puis redescend plus vite.
-- Pose directe a chaque frame (pas d'interpolation native, qui rendrait la montee saccadee).
local previewAnimFrame
local PREVIEW_RISE, PREVIEW_HOLD, PREVIEW_FALL = 3.2, 0.4, 1.0
local function StopPreviewAnim()
  if previewAnimFrame then previewAnimFrame:SetScript("OnUpdate", nil) end
end
local function StartPreviewAnim()
  if not previewAnimFrame then previewAnimFrame = CreateFrame("Frame") end
  local t, lastShown = 0, nil
  local total = PREVIEW_RISE + PREVIEW_HOLD + PREVIEW_FALL + PREVIEW_HOLD
  previewAnimFrame:SetScript("OnUpdate", function(_, el)
    if not (bar and previewMode) then StopPreviewAnim(); return end
    t = (t + el) % total
    local v
    if t < PREVIEW_RISE then
      local p = t / PREVIEW_RISE
      v = 50 + 50 * (p * p * (3 - 2 * p))                  -- montee douce (smoothstep)
    elseif t < PREVIEW_RISE + PREVIEW_HOLD then
      v = 100
    elseif t < PREVIEW_RISE + PREVIEW_HOLD + PREVIEW_FALL then
      local p = (t - PREVIEW_RISE - PREVIEW_HOLD) / PREVIEW_FALL
      v = 100 - 50 * (p * p * (3 - 2 * p))
    else
      v = 50
    end
    pcall(bar.arc.SetValue, bar.arc, v)
    if previewDurShown and previewDurEl then pcall(previewDurEl.SetValue, previewDurEl, v) end
    if previewStagShown then pcall(bar.staggerArc.SetValue, bar.staggerArc, v) end
    local shown = math.floor(v + 0.5)
    if shown ~= lastShown then lastShown = shown; bar.text:SetText(tostring(shown)) end
  end)
end

-- Anime l'arc actif et son overlay indépendamment (chacun son timing) ; l'overlay finit en dernier pour ne pas laisser transparaître le trou central.
local _arcOverlayTickers = { main = nil, stagger = nil }
-- Anime une paire arc+overlay avec CIRCLE_ANIM.arc/arcOverlay ; factorisé pour que l'arc de
-- stagger reçoive exactement la même animation que l'arc principal.
local function AnimateArcOverlayPair(key, shouldShow, arcEl, overlayEl, overlayVisualEl, arcKey, overlayKey, onDone)
  if not arcEl or not overlayEl then return end
  -- /rcanimlog : trace chaque appel + si un cycle en cours est interrompu.
  if ns._rcAnimDebug then
    print(string.format("|cff88ffff[RCAnim]|r %.3f AnimateArcOverlayPair key=%s shouldShow=%s interrompt=%s",
      GetTime(), tostring(key), tostring(shouldShow), tostring(_arcOverlayTickers[key] ~= nil)))
  end
  if _arcOverlayTickers[key] then _arcOverlayTickers[key]:Cancel(); _arcOverlayTickers[key] = nil end

  local arcAnim, overlayAnim = CIRCLE_ANIM[arcKey or "arc"], CIRCLE_ANIM[overlayKey or "arcOverlay"]
  local arcSpec     = shouldShow and arcAnim.show     or arcAnim.hide
  local overlaySpec = shouldShow and overlayAnim.show or overlayAnim.hide

  -- opacity = alpha de départ pour show / de fin pour hide (l'autre bout vaut toujours 1), même convention que ns.AnimateStagger.
  local arcOpacity, overlayOpacity = arcSpec.opacity or 0, overlaySpec.opacity or 0
  local arcStartAlpha, arcEndAlpha         = shouldShow and arcOpacity or 1,     shouldShow and 1 or arcOpacity
  local overlayStartAlpha, overlayEndAlpha = shouldShow and overlayOpacity or 1, shouldShow and 1 or overlayOpacity
  -- Repart du dernier alpha réellement appliqué (_aishAnimAlpha) si connu, pas du point canonique,
  -- pour éviter un décalage visible entre arc/overlay si une interruption survient à des instants différents.
  if arcEl._aishAnimAlpha then arcStartAlpha = arcEl._aishAnimAlpha end
  if overlayEl._aishAnimAlpha then overlayStartAlpha = overlayEl._aishAnimAlpha end

  -- Géométrie "home" via _elemHome (RecordHome), fiable même en combat contrairement à GetPoint/GetSize (secret values). Scale via SetSize, pas SetScale (pivot pas l'ancrage réel).
  local function captureHome(element)
    if not element then return nil end
    local cached = _elemHome[element]
    if cached then return cached end
    -- Filet de sécurité si jamais l'élément n'a pas de géométrie enregistrée.
    local home = {}
    local point, relTo, relPoint, x, y = element:GetPoint(1)
    if point and not ns.IsSecret(point) and not ns.IsSecret(x) and not ns.IsSecret(y) then
      home.point, home.relTo, home.relPoint, home.x, home.y = point, relTo, relPoint, x, y
    end
    local w, h = element:GetSize()
    if not ns.IsSecret(w) and not ns.IsSecret(h) then
      home.w, home.h = w, h
    end
    if not home.point and not home.w then return nil end
    return home
  end
  -- Redimensionner une StatusBar ne réapplique pas son crop : force via ns.SmoothSetValue (pas un
  -- SetValue nu, écrasé par l'interpolation native déjà en cours). Textures (bar.overlay) : pas concernées.
  local function RefreshCrop(element)
    if element.GetValue and element.SetValue then
      ns.SmoothSetValue(element, element:GetValue())
    end
  end
  -- useGlobalScale : StatusBar (arc) utilise SetScale (évite le souci de redraw du crop) plutôt que
  -- SetSize (utilisé pour les Textures comme bar.overlay). Pivot de SetScale pas garanti = ancrage BOTTOM.
  local function applyTransform(element, home, slideX, slideY, p, scale, useGlobalScale)
    if not home then return end
    if home.point then
      local fromX = shouldShow and (home.x + slideX) or home.x
      local toX   = shouldShow and home.x or (home.x + slideX)
      local fromY = shouldShow and (home.y + slideY) or home.y
      local toY   = shouldShow and home.y or (home.y + slideY)
      element:ClearAllPoints()
      element:SetPoint(home.point, home.relTo, home.relPoint,
        fromX + (toX - fromX) * p, fromY + (toY - fromY) * p)
    end
    if useGlobalScale then
      element:SetScale(scale)
    elseif home.w then
      element:SetSize(home.w * scale, home.h * scale)
      RefreshCrop(element)
    end
    -- Mémorise le dernier scale réellement appliqué, pour qu'une animation interrompue reprenne d'où elle en était.
    element._aishAnimScale = scale
  end
  local function resetTransform(element, home, useGlobalScale)
    if not home then return end
    if home.point then
      element:ClearAllPoints()
      element:SetPoint(home.point, home.relTo, home.relPoint, home.x, home.y)
    end
    if useGlobalScale then
      element:SetScale(1)
    elseif home.w then
      element:SetSize(home.w, home.h)
      RefreshCrop(element)
    end
    -- nil (pas 1) : un cycle complet doit laisser le prochain repartir du point de départ canonique.
    element._aishAnimScale = nil
  end

  local arcSlideX, arcSlideY = arcSpec.slideX or 0, arcSpec.slideY or 0
  local ovlSlideX, ovlSlideY = overlaySpec.slideX or 0, overlaySpec.slideY or 0
  local arcScale     = arcSpec.scale or 1
  local overlayScale = overlaySpec.scale or 1
  local arcStartScale, arcEndScale         = shouldShow and arcScale or 1,     shouldShow and 1 or arcScale
  local overlayStartScale, overlayEndScale = shouldShow and overlayScale or 1, shouldShow and 1 or overlayScale
  -- Repart du dernier scale réellement appliqué (_aishAnimScale) si connu, pas du point canonique,
  -- sinon des interruptions rapprochées (entrée/sortie combat successives) laissent l'élément bloqué petit.
  if arcEl and arcEl._aishAnimScale then arcStartScale = arcEl._aishAnimScale end
  if overlayVisualEl and overlayVisualEl._aishAnimScale then overlayStartScale = overlayVisualEl._aishAnimScale end

  local needArcTransform     = arcSlideX ~= 0 or arcSlideY ~= 0 or arcScale ~= 1
  local needOverlayTransform = ovlSlideX ~= 0 or ovlSlideY ~= 0 or overlayScale ~= 1
  local arcHome     = needArcTransform and captureHome(arcEl) or nil
  local overlayHome = needOverlayTransform and captureHome(overlayVisualEl) or nil

  arcEl:Show(); arcEl:SetAlpha(arcStartAlpha); arcEl._aishAnimAlpha = arcStartAlpha
  if overlayVisualEl then overlayVisualEl:Show() end
  overlayEl:Show(); overlayEl:SetAlpha(overlayStartAlpha); overlayEl:SetScale(1)
  overlayEl._aishAnimAlpha = overlayStartAlpha

  -- Applique la géométrie en p=0 immédiatement (comme l'alpha), pas seulement au 1er tick du ticker,
  -- sinon une interruption avant ce tick laisse l'overlay à la géométrie de l'animation précédente.
  if arcHome then
    applyTransform(arcEl, arcHome, arcSlideX, arcSlideY, 0, arcStartScale, true)
  end
  if overlayHome then
    applyTransform(overlayVisualEl, overlayHome, ovlSlideX, ovlSlideY, 0, overlayStartScale)
  end

  local now = GetTime()
  local arcStart, overlayStart = now + arcSpec.delay, now + overlaySpec.delay
  local arcDone, overlayDone = false, false

  _arcOverlayTickers[key] = C_Timer.NewTicker(0.016, function()
    local tick = GetTime()

    if not arcDone then
      local elapsed = tick - arcStart
      if elapsed >= 0 then
        local p = ns.Ease(arcSpec.ease, arcSpec.easeType, math.min(elapsed / arcSpec.duration, 1))
        -- Valeur calculée, jamais relue via :GetAlpha() (peut renvoyer une valeur secrète en combat).
        local curArcAlpha = arcStartAlpha + (arcEndAlpha - arcStartAlpha) * p
        arcEl:SetAlpha(curArcAlpha)
        arcEl._aishAnimAlpha = curArcAlpha
        if arcHome then
          applyTransform(arcEl, arcHome, arcSlideX, arcSlideY, p, arcStartScale + (arcEndScale - arcStartScale) * p, true)
        end
        if elapsed >= arcSpec.duration then
          arcEl:SetAlpha(arcEndAlpha)
          -- nil (pas arcEndAlpha) : un cycle qui va au bout ne laisse rien à reprendre, le suivant repart du point canonique.
          arcEl._aishAnimAlpha = nil
          resetTransform(arcEl, arcHome, true)
          if not shouldShow then arcEl:Hide() end
          arcDone = true
        end
      end
    end

    if not overlayDone then
      local elapsed = tick - overlayStart
      if elapsed >= 0 then
        local p = ns.Ease(overlaySpec.ease, overlaySpec.easeType, math.min(elapsed / overlaySpec.duration, 1))
        -- Valeur calculée, jamais relue via :GetAlpha() -- même raison que pour l'arc ci-dessus.
        local curOverlayAlpha = overlayStartAlpha + (overlayEndAlpha - overlayStartAlpha) * p
        overlayEl:SetAlpha(curOverlayAlpha)
        overlayEl._aishAnimAlpha = curOverlayAlpha
        if overlayHome then
          applyTransform(overlayVisualEl, overlayHome, ovlSlideX, ovlSlideY, p, overlayStartScale + (overlayEndScale - overlayStartScale) * p)
        end
        if elapsed >= overlaySpec.duration then
          overlayEl:SetAlpha(overlayEndAlpha)
          overlayEl._aishAnimAlpha = nil
          resetTransform(overlayVisualEl, overlayHome)
          if not shouldShow then
            overlayEl:Hide()
            if overlayVisualEl then overlayVisualEl:Hide() end
          end
          overlayDone = true
        end
      end
    end

    if arcDone and overlayDone then
      _arcOverlayTickers[key]:Cancel()
      _arcOverlayTickers[key] = nil
      if onDone then onDone() end
    end
  end)
end

-- Anime l'arc actif + son overlay, et l'arc de stagger Brasseur avec la même spec si actif.
local function AnimateArcOverlay(shouldShow)
  if not bar then return end

  local arcEl = bar.arc

  -- Slide/scale de l'overlay principal appliqués à la texture bar.overlay (ancrée CENTER), pas à bar.overlayFrame (SetAllPoints, pas de pivot exploitable).
  AnimateArcOverlayPair("main", shouldShow, arcEl, bar.overlayFrame, bar.overlay)

  -- Arc de duree (ressource secondaire) : meme animation, mais calee pour arriver en dernier / partir en premier.
  if bar.durationArc and bar.durationOvlFrame then
    -- Le cercle entre / sort avec tout le reste : interrompt une eventuelle animation liee aux donnees.
    if _arcOverlayTickers.duration then _arcOverlayTickers.duration:Cancel(); _arcOverlayTickers.duration = nil end
    durBusy = false
    if shouldShow then
      if durArcWanted then RunDurAnim(true, false) end
    elseif durShown then
      RunDurAnim(false, false)
    end
  end

  -- Arc de stagger (Moine Brasseur) : structurellement identique à l'arc principal, donc exactement la même animation.
  if bar.staggerArc and bar.staggerOverlayFrame then
    if staggerActive then
      if shouldShow then
        ApplyStaggerGeometry()
        ResetRadialArc(bar.staggerArc)
        ApplyArcAngles()
      end
      AnimateArcOverlayPair("stagger", shouldShow, bar.staggerArc, bar.staggerOverlayFrame, bar.staggerOverlay)
    elseif _arcOverlayTickers.stagger then
      _arcOverlayTickers.stagger:Cancel(); _arcOverlayTickers.stagger = nil
      bar.staggerArc:Hide()
      bar.staggerOverlayFrame:Hide()
    end
  end
end

-- Animation pour l'apparition/disparition avec stagger et scale
function ResourceCircle.AnimateVisibility(shouldShow)
  if animationTicker then
    animationTicker:Cancel()
    animationTicker = nil
  end
  if not bar then return end

  local cfg = ns.GetCfg("resourceCircle")
  local duration = 0.4
  local staggerInterval = 0.05
  local startTime = GetTime()
  local targetAlpha = shouldShow and 1 or 0

  -- Mettre à jour les slots conditionnels (mutation en place, pas d'allocation)
  _rcAnimElems[14].element = (secResDef and bar.secResFrame)             or nil
  -- Les secondary dots ont leur propre animation slide (secAnimFrame) : exclus du stagger principal
  -- staggerArc/staggerOverlayFrame : exclus aussi, cf. AnimateArcOverlay

  -- Recalcule timing/courbe/mouvement de chaque slot depuis CIRCLE_ANIM selon la direction (show/hide peuvent différer complètement).
  for i, group in pairs(_RC_ANIM_GROUP) do
    local spec = shouldShow and CIRCLE_ANIM[group].show or CIRCLE_ANIM[group].hide
    local slot = _rcAnimElems[i]
    slot.delay    = spec.delay
    slot.duration = spec.duration
    slot.ease     = spec.ease
    slot.easeType = spec.easeType
    slot.slideX   = spec.slideX
    slot.slideY   = spec.slideY
    slot.scaleX   = spec.scaleX
    slot.scaleY   = spec.scaleY
    slot.opacity  = spec.opacity
    -- Géométrie de repos pré-calculée (RecordHome) plutôt que relue via GetPoint/GetSize : fiable même en combat.
    local home = slot.element and _elemHome[slot.element]
    if home then
      slot.homePoint, slot.homeRelTo, slot.homeRelPoint = home.point, home.relTo, home.relPoint
      slot.homeX, slot.homeY = home.x, home.y
      slot.homeW, slot.homeH = home.w, home.h
    else
      slot.homePoint = nil
    end
  end

  -- Utiliser l'animation partagée
  animationTicker = ns.AnimateStagger(_rcAnimElems, shouldShow, duration, staggerInterval, function()
    if previewMode then
      rcAnimBusy = false
      return
    end
    if not shouldShow then
      bar:Hide()
      -- (arc / overlay : masqués par AnimateArcOverlay,
      -- sur son propre timing — pas ici, pour ne pas les couper en avance.)
      bar.bgLarge:Hide()
      bar.text:Hide()
      if bar.textBackdrop then bar.textBackdrop:Hide() end
      for i = 1, 5 do
        if bar["dot" .. i] then bar["dot" .. i]:Hide() end
      end
      -- Forcer le slide-out immédiat des secondary dots
      for i = 1, secDotCount do
        if secDotAnims[i] then secDotAnims[i].target = 0 end
      end
      -- Stopper toutes les animations 3D (Play en cours + soutenues + pool)
      local SE = ns.Modules and ns.Modules.SpellEffects
      if SE and SE.StopAll then SE.StopAll() end
    end
    rcAnimBusy = false
    if rcAnimDirty then
      rcAnimDirty = false
      ResourceCircle.UpdateVisibility()
    end
  end)

  -- Animation du mouvement Y pour le frame parent
  if moveTicker then moveTicker:Cancel() end
  moveTicker = C_Timer.NewTicker(0.016, function()
    local elapsed = GetTime() - startTime
    local frameProgress = math.min(elapsed / duration, 1)
    local easeProgress = 1 - (1 - frameProgress) ^ 3

    local startOffsetY = shouldShow and -20 or 0
    local endOffsetY = shouldShow and 0 or -20
    local currentOffsetY = startOffsetY + (endOffsetY - startOffsetY) * easeProgress

    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y + currentOffsetY)

    if elapsed >= duration + staggerInterval * 5 then
      moveTicker:Cancel()
      bar:ClearAllPoints()
      bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    end
  end)
end

-- Mode preview : force l'affichage du cercle pour le settings panel
--- Allume le halo du fond de texte (appele par le slider du panneau).
function ResourceCircle.FlashTextBackdrop()
  if bar then ns.FlashTextBackdropGlow(bar.textBackdropGlow) end
end

function ResourceCircle.SetPreview(on)
  previewMode = on
  if not bar then return end
  if ns.IsForever then C_Timer.After(0, RefreshSwingPreview) end
  -- Sortie du panneau : le halo n'a plus lieu d'etre.
  if not on and bar.textBackdropGlow then ns.HideTextBackdropGlow(bar.textBackdropGlow) end

  -- SetPreview est un override manuel : interruption immediate voulue (contrairement a UpdateVisibility).
  -- Remet aussi rcAnimBusy a plat, sinon il resterait bloque a true (son onComplete vient d'etre annule).
  if animationTicker then animationTicker:Cancel(); animationTicker = nil end
  if moveTicker then moveTicker:Cancel(); moveTicker = nil end
  rcAnimBusy = false
  rcAnimDirty = false

  if on then
    lastVisibilityState = nil
    for _, k in ipairs({ "main", "stagger", "duration" }) do
      if _arcOverlayTickers[k] then _arcOverlayTickers[k]:Cancel(); _arcOverlayTickers[k] = nil end
    end
    durBusy = false
    for _, el in ipairs({ bar.arc, bar.overlayFrame, bar.overlay, bar.staggerArc, bar.staggerOverlayFrame, bar.staggerOverlay,
                          bar.durationArc, bar.durationArcV, bar.durationOvlFrame, bar.durationOvl }) do
      el._aishAnimAlpha, el._aishAnimScale = nil, nil
    end
    -- Respecter le toggle : pas d'apercu pour un module desactive (meme garde
    -- que HealthCircle/OutOfCombatResourceCircle). Masquage explicite : avec
    -- previewMode a true, UpdateVisibility est court-circuite et ne le ferait
    -- jamais de lui-meme.
    if ns.GetCfg("resourceCircle").enabled == false then
      bar:Hide()
      return
    end
    -- Forcer l'affichage de tous les elements
    bar:Show()
    bar:SetAlpha(1)
    bar:SetScale(1)
    local cfgPrev = ns.GetCfg("resourceCircle")
    if bar.bgGlow then
      if cfgPrev.glowEnabled ~= false then
        bar.bgGlow:Show()
        bar.bgGlow:SetAlpha(cfgPrev.glowOpacity or 0.85)
        bar.bgGlow:SetScale(1)  -- remet l'echelle si l'animation avait ete coupée
      else
        bar.bgGlow:Hide()
      end
    end
    local elements = { bar.bgLarge, bar.text, bar.arc }
    for i = 1, 5 do elements[#elements+1] = bar["dot" .. i] end
    for _, el in ipairs(elements) do
      if el then
        el:Show()
        el:SetAlpha(1)
        if el.SetScale then el:SetScale(1) end
      end
    end
    -- Sec dots : forcer progress=1 pour aperçu immédiat
    for i = 1, secDotCount do
      local f = secDots[i]
      if f then
        if secDotAnims[i] then secDotAnims[i].progress = 1; secDotAnims[i].target = 1 end
        if f.radial then f.radial:SetValue(1); f.radial:SetAlpha(1) end
        f:Show()
        f:SetAlpha(1)
        if f.SetScale then f:SetScale(1) end
        if f._homeX then
          f:ClearAllPoints()
          f:SetPoint("CENTER", bar, "CENTER", f._homeX, f._homeY)
        end
      end
    end
    if bar.overlay then bar.overlay:Show(); bar.overlay:SetAlpha(1) end
    if bar.overlayFrame then bar.overlayFrame:Show(); bar.overlayFrame:SetAlpha(1); bar.overlayFrame:SetScale(1) end
    if bar.textBackdrop then bar.textBackdrop:Show(); bar.textBackdrop:SetAlpha(1) end
    -- Texte de ressource secondaire visible en preview seulement si la spé a une définition.
    -- Reset explicite d'alpha/position : un pop-out interrompu peut laisser secResFrame à alpha 0.
    if bar.secResFrame and bar.secResText then
      -- Moine Brasseur : pas de secResDef, c'est le pourcentage de Report qui occupe ce
      -- meme slot de texte (cf. UpdateStagger). Sans ce cas l'apercu restait vide et les
      -- reglages de police/couleur/position du pourcentage n'etaient pas previsualisables.
      local _prevCfg = ns.GetCfg("resourceCircle")
      local _staggerPreview = (not secResDef) and ns._specID == 268
        and _prevCfg and _prevCfg.staggerShowPercent
      if secResDef or _staggerPreview then
        local function PlaceSecResFrame()
          bar.secResFrame:SetAlpha(1)
          local home = _elemHome[bar.secResFrame]
          if home then
            bar.secResFrame:ClearAllPoints()
            bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint, home.x, home.y)
          end
          bar.secResFrame:Show()
        end
        if secResDef then
          bar.secResText:SetText("8")
          SetSecResShown(true)
        else
          -- Valeur factice dans la bande "moderee" (30-60%), d'ou la couleur orange :
          -- meme rendu que ce que produira UpdateStagger en jeu.
          bar.secResText:SetText("42.5%")
          bar.secResText:SetTextColor(STAGGER_MODERATE[1], STAGGER_MODERATE[2], STAGGER_MODERATE[3], 1)
          bar.secResText:Show()
          -- Un pourcentage n'est pas un nombre de stacks : pas de tirets decoratifs,
          -- exactement comme le chemin reel dans UpdateStagger.
          if bar.secResDashL then bar.secResDashL:Hide() end
          if bar.secResDashR then bar.secResDashR:Hide() end
        end
        PlaceSecResFrame()
      else
        SetSecResShown(false)
        bar.secResFrame:Hide()
      end
    end
    -- Barre de duree : sans valeur fictive elle restait a 0 en apercu, donc invisible,
    -- et largeur/epaisseur/couleur/position n'etaient pas reglables a vue.
    if bar.secResDurL and bar.secResDurR then
      if SecResDurBarsActive(ns._specID) then
        RefreshSecResDurBar(ns._specID)
        SecResDurApplyColor(ns._specID)
        SecResDurEach(function(db)
          db:SetAlpha(1)
          db:SetMinMaxValues(0, 1)
          db:SetValue(0.6)
          db:Show()
        end)
      else
        SecResDurEach(function(db) db:Hide() end)
      end
    end

    -- Arc de Report (Brasseur) : comme le pourcentage ci-dessus, il n'apparaissait pas
    -- en apercu, donc taille/epaisseur/couleur n'etaient pas reglables a vue. Valeur
    -- fictive coherente avec le texte (42.5 sur une echelle 0-100, bande "moderee").
    if bar.staggerArc and bar.staggerOverlayFrame then
      if staggerActive or ns._specID == 268 then
        bar.staggerArc:SetStatusBarColor(STAGGER_MODERATE[1], STAGGER_MODERATE[2], STAGGER_MODERATE[3], 1)
        bar.staggerArc:SetMinMaxValues(0, 100)
        bar.staggerArc:SetValue(42.5)
        bar.staggerArc:SetScale(1); bar.staggerArc:SetAlpha(1); bar.staggerArc:Show()
        bar.staggerOverlayFrame:SetScale(1); bar.staggerOverlayFrame:SetAlpha(1); bar.staggerOverlayFrame:Show()
        bar.staggerOverlay:SetAlpha(1); bar.staggerOverlay:Show()
        previewStagShown = true
      else
        previewStagShown = false
        bar.staggerArc:Hide()
        bar.staggerOverlayFrame:Hide()
      end
    end
    -- Arc de duree (ressource secondaire des specs tank, etc.) : apercu avec la couleur reelle, anime comme l'arc principal.
    previewDurShown, previewDurEl = false, nil
    if bar.durationArc and bar.durationOvlFrame then
      local info = ns.Auras and ns.Auras.GetCenterArcPreview and ns.Auras.GetCenterArcPreview()
      if info then
        -- Source a plage secrete (canal clone-bar) : l'arc reel est la barre verticale, c'est elle qu'on previsualise.
        durArcVert = info.vertical and true or false
        local el = durArcVert and bar.durationArcV or bar.durationArc
        local other = durArcVert and bar.durationArc or bar.durationArcV
        if other then other:Hide() end
        local c = info.color or { 1, 1, 1 }
        el:SetStatusBarColor(c[1], c[2], c[3], 1)
        el:SetMinMaxValues(0, 100)
        el:SetValue(75)
        el:SetScale(1); el:SetAlpha(1); el:Show()
        bar.durationOvlFrame:SetScale(1); bar.durationOvlFrame:SetAlpha(1); bar.durationOvlFrame:Show()
        bar.durationOvl:SetAlpha(1); bar.durationOvl:Show()
        durBusy, durShown = false, true
        previewDurShown, previewDurEl = true, el
      end
    end
    -- Valeur fictive animee pour visualiser
    StartPreviewAnim()
  else
    StopPreviewAnim()
    if previewStagShown then ResourceCircle.DetectStagger() end
    previewStagShown = false
    if previewDurShown then
      previewDurShown, previewDurEl = false, nil
      if not durArcWanted then
        bar.durationArc:Hide()
        if bar.durationArcV then bar.durationArcV:Hide() end
        if bar.durationOvlFrame then bar.durationOvlFrame:Hide() end
        durShown = false
      end
    end
    lastVisibilityState = nil
    ResourceCircle.Update()
    ResourceCircle.UpdateVisibility()
  end
end

-- Rend le cercle deplacable par drag (pour le mode settings)
function ResourceCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
      -- Verrou relu A CHAUD : le drag est arme des l'ouverture du panneau (plus de bouton dedie),
      -- donc la case "Verrouiller la position" est le seul frein -- meme modele que unitBars.
      local c = ns.GetCfg("resourceCircle")
      if c and c.locked then return end
      self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      -- Calculer le nouvel offset depuis CENTER de UIParent
      local cx, cy = self:GetCenter()
      local ucx, ucy = UIParent:GetCenter()
      local newX = math.floor(cx - ucx + 0.5)
      local newY = math.floor(cy - ucy + 0.5)
      -- Sauvegarder en DB
      if not ns.DB then ns.DB = {} end
      if not ns.DB.resourceCircle then ns.DB.resourceCircle = {} end
      ns.DB.resourceCircle.x = newX
      ns.DB.resourceCircle.y = newY
      -- Repositionner proprement
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "CENTER", newX, newY)
      -- Met à jour les sliders X/Y du panneau de réglages (même convention que Skyriding.lua).
      local xSl = _G["AishCoreRCPosXSlider"]
      local ySl = _G["AishCoreRCPosYSlider"]
      if xSl then xSl:SetValue(newX) end
      if ySl then ySl:SetValue(newY) end
    end)
    -- Bordure visuelle "deplacable"
    if not bar._dragBorder then
      local border = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      border:SetAllPoints(bar)
      border:SetColorTexture(1, 1, 1, 0.15)
      bar._dragBorder = border
    end
    -- Bordure affichee seulement au survol (un cadre permanent autour du cercle, panneau ouvert, etait
    -- tres visible), et seulement si le deplacement est reellement possible : la montrer sur un
    -- element verrouille laisserait croire qu'il est saisissable.
    bar._dragBorder:Hide()
    -- Tooltip au survol
    bar:SetScript("OnEnter", function(self)
      local c = ns.GetCfg("resourceCircle")
      if not (c and c.locked) then self._dragBorder:Show() end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["RESOURCE_DRAG_TOOLTIP"])
      GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function(self)
      self._dragBorder:Hide()
      GameTooltip:Hide()
    end)
  else
    bar:SetMovable(false)
    bar:EnableMouse(false)
    bar:RegisterForDrag()
    bar:SetScript("OnDragStart", nil)
    bar:SetScript("OnDragStop", nil)
    bar:SetScript("OnEnter", nil)
    bar:SetScript("OnLeave", nil)
    if bar._dragBorder then bar._dragBorder:Hide() end
  end
end

-- Met à jour la visibilité
function ResourceCircle.UpdateVisibility()
  if not bar then return end
  if previewMode then return end
  local shouldShow = ResourceCircle.ShouldShow()
  if ns._rcAnimDebug then
    print(string.format("|cff88ffff[RCAnim]|r %.3f UpdateVisibility shouldShow=%s lastState=%s skyridingActive=%s inCombat=%s%s",
      GetTime(), tostring(shouldShow), tostring(lastVisibilityState), tostring(ns.skyridingActive),
      tostring(UnitAffectingCombat("player")),
      (lastVisibilityState == shouldShow) and " (no-op)" or " (TRANSITION)"))
  end
  if lastVisibilityState == shouldShow then return end

  -- Ne jamais interrompre une transition en cours : note juste la demande (rcAnimDirty), rappelée
  -- automatiquement une fois l'animation en cours terminée (cf. onComplete d'AnimateVisibility).
  if rcAnimBusy then
    rcAnimDirty = true
    return
  end
  lastVisibilityState = shouldShow
  rcAnimBusy = true

  if shouldShow then
    bar:Show()
    -- L'arc et l'overlay ont leur propre animation dédiée (timing/easing différents), voir AnimateArcOverlay
    AnimateArcOverlay(true)
    bar.bgLarge:Show(); bar.bgLarge:SetAlpha(0)
    local cfg2 = ns.GetCfg("resourceCircle")
    if bar.bgGlow and cfg2.glowEnabled ~= false then bar.bgGlow:Show(); bar.bgGlow:SetAlpha(0) end
    bar.text:Show(); bar.text:SetAlpha(0)
    for i = 1, 5 do
      if bar["dot" .. i] then bar["dot" .. i]:Show(); bar["dot" .. i]:SetAlpha(0) end
    end
    if bar.textBackdrop then bar.textBackdrop:Show(); bar.textBackdrop:SetAlpha(0) end
    -- Les sec dots réinitialisent leur progress pour recréer le slide-in
    for i = 1, secDotCount do
      if secDotAnims[i] then
        secDotAnims[i].progress = 0
        secDotAnims[i].target = 0
      end
    end
    -- Montrer le frame de ressource secondaire s'il y a une définition active
    -- (SetAlpha(0) : laisse AnimateVisibility faire le fade+slide-in, cf. CIRCLE_ANIM.secResText)
    if bar.secResFrame and secResDef then bar.secResFrame:Show(); bar.secResFrame:SetAlpha(0) end
    -- Arc de stagger : Show()/alpha déjà gérés par AnimateArcOverlay ci-dessus, juste rafraîchir valeur/couleur.
    if staggerActive and bar.staggerArc then
      ResourceCircle.UpdateStagger()
    end
    -- Relancer les animations soutenues si un proc est toujours actif
    local SE_show = ns.Modules and ns.Modules.SpellEffects
    if SE_show and SE_show.StartSustained then
      local _, playerClassShow = UnitClass("player")
      local specShow = GetSpecialization and GetSpecialization() or nil
      local specIDShow = specShow and (GetSpecializationInfo and GetSpecializationInfo(specShow)) or nil
      -- Mage Feu
      if playerClassShow == "MAGE" and specIDShow == 63 then
        if fireProcLevel == 1 then SE_show.StartSustained(9000001) end
        if fireProcLevel == 2 then SE_show.StartSustained(9000002) end
      end
      -- Evoker Preservation : Essence Burst
      if playerClassShow == "EVOKER" and specIDShow == 1468 then
        if essenceBurstActive then SE_show.StartSustained(9000003) end
      end
      -- Shaman Enhancement : Maelstrom Weapon
      if playerClassShow == "SHAMAN" and specIDShow == 263 then
        if mwStackLevel == 1 then SE_show.StartSustained(9000004)
        elseif mwStackLevel == 2 then SE_show.StartSustained(9000005)
        elseif mwStackLevel == 3 then SE_show.StartSustained(9000006) end
      end
    end
    ResourceCircle.AnimateVisibility(true)
  else
    -- Déclencher le slide-out des sec dots
    for i = 1, secDotCount do
      if secDotAnims[i] then secDotAnims[i].target = 0 end
    end
    -- Pas de Hide() immédiat pour secResFrame/staggerArc : leur fondu animé (AnimateVisibility /
    -- AnimateArcOverlay) les cache déjà sur leur propre timing.
    local SE = ns.Modules and ns.Modules.SpellEffects
    if SE and SE.StopAllSustained then SE.StopAllSustained() end
    AnimateArcOverlay(false)
    ResourceCircle.AnimateVisibility(false)
  end
end

-- Forward-déclaré : vraie définition plus bas, requise par Update() ci-dessous pour Mage Givre.
local ApplyStacksToText

-- Met a jour la valeur et le texte selon la ressource primaire detectee
-- Le texte n'est repose que s'il a CHANGE : le ticker tourne a 5 Hz et reecrivait la meme
-- valeur en boucle, or ce FontString porte un anneau SLUG et chaque SetText est propage a
-- 8 autres FontStrings. La comparaison est protegee : string.format sur une valeur secrete
-- rend une SECRET STRING, que l'on ne peut pas comparer.
local _rcLastText
local function SetResourceText(txt)
  -- Texte secret : aucune comparaison possible (elle serait bloquee et journalisee)
  local okCmp, same = false, nil
  if not (issecretvalue and issecretvalue(txt)) then
    okCmp, same = pcall(function() return txt == _rcLastText end)
  end
  if okCmp then
    if same then return end
    _rcLastText = txt
  else
    _rcLastText = nil
  end
  pcall(bar.text.SetText, bar.text, txt)
end

-- /aishrctext : couleur / alpha du texte de ressource (config, texte reel, selecteur de couleur), pour diagnostiquer l'alpha
SLASH_AISHRCTEXT1 = "/aishrctext"
SlashCmdList["AISHRCTEXT"] = function()
  local P = "|cff33aaff[RCText]|r "
  local cfg = ns.GetCfg("resourceCircle")
  local tc = cfg and cfg.textColor
  print(P .. "themedColors=" .. tostring(cfg and cfg.themedColors) .. " textColor="
    .. (tc and string.format("%.2f/%.2f/%.2f/%s", tc[1], tc[2], tc[3], tostring(tc[4])) or "nil"))
  if bar and bar.text then
    print(P .. "texte reel : GetTextColor=" .. table.concat({ tostring(select(1, bar.text:GetTextColor())),
      tostring(select(2, bar.text:GetTextColor())), tostring(select(3, bar.text:GetTextColor())),
      tostring(select(4, bar.text:GetTextColor())) }, "/")
      .. " alpha=" .. tostring(bar.text:GetAlpha()) .. " effectif=" .. tostring(bar.text:GetEffectiveAlpha()))
  end
  local cp = ColorPickerFrame
  print(P .. "selecteur : GetColorAlpha=" .. tostring(cp and cp.GetColorAlpha ~= nil)
    .. " OpacitySliderFrame=" .. tostring(_G.OpacitySliderFrame ~= nil)
    .. (cp and cp.GetColorAlpha and (" alpha=" .. tostring(cp:GetColorAlpha())) or ""))
end

function ResourceCircle.Update()
  if not bar or not bar.text then return end
  if previewMode then return end
  if not bar:IsShown() then return end  -- rien a mettre a jour si le cercle est cache

  local resource = ns.GetPlayerResource()
  local pct
  local displayText

  -- Ressource aura (string key, ex: MAELSTROM_WEAPON, ICICLES)
  if type(resource) == "string" then
    if ns.AuraResources[resource] then
      -- Filet de securite : si le buff n'existe plus, forcer le cache a 0
      local def = ns.AuraResources[resource]
      local auraData = C_UnitAuras.GetPlayerAuraBySpellID(def.spellID)
      if not auraData and (ns.AuraStacks[resource] or 0) > 0 then
        ns.AuraStacks[resource] = 0
        ns.AuraText[resource]   = "0"
        ns.AuraPct[resource]    = 0
      end
      pct = ns.AuraPct[resource] or 0
      displayText = ns.AuraText[resource] or "0"
      -- Maelstrom Weapon pseudo-spells (Enhancement Shaman specID 263)
      if resource == "MAELSTROM_WEAPON" and ns._playerClass == "SHAMAN" and ns._specID == 263 then
        local stacks = ns.AuraStacks["MAELSTROM_WEAPON"] or 0
        local newMwLevel = (stacks >= 10) and 3 or (stacks >= 8) and 2 or (stacks >= 5) and 1 or 0
        if newMwLevel ~= mwStackLevel then
          mwStackLevel = newMwLevel
          local SE_mw = ns.Modules and ns.Modules.SpellEffects
          if SE_mw then
            if SE_mw.StopSustained then
              SE_mw.StopSustained(9000004)
              SE_mw.StopSustained(9000005)
              SE_mw.StopSustained(9000006)
            end
            if newMwLevel == 1 and SE_mw.StartSustained then SE_mw.StartSustained(9000004)
            elseif newMwLevel == 2 and SE_mw.StartSustained then SE_mw.StartSustained(9000005)
            elseif newMwLevel == 3 and SE_mw.StartSustained then SE_mw.StartSustained(9000006) end
          end
        end
      end
    end
  else
    -- Ressource standard (Enum.PowerType)
    local ok, val = pcall(UnitPowerPercent, "player", resource, true, CurveConstants.ScaleTo100)
    if ok then
      pct = val
      -- Affichage brut pour certaines ressources (Essence, SoulShards, etc.)
      local rawDef = ns.RawDisplayResources and ns.RawDisplayResources[resource]
      if rawDef then
        if rawDef.maxValue then
          -- Deriver la valeur decimale depuis le pourcentage (evite secret numbers)
          displayText = string.format(rawDef.fmt, pct * rawDef.maxValue / 100)
        else
          -- Formater directement sans arithmetique sur le secret number
          local ok2, text = pcall(string.format, rawDef.fmt, UnitPower("player", resource))
          displayText = ok2 and text or string.format("%.0f", pct)
        end
      else
        displayText = string.format("%.0f", pct)
      end
    end
  end

  if pct == nil then
    ApplyArcValue(0)
    bar.text:SetText("-")
    return
  end

  -- Fire Mage (spec 63) : afficher directement 0/1/2 au lieu de la mana (cache ns._playerClass/ns._specIndex).
  if ns._playerClass == "MAGE" and ns._specIndex == 2 then  -- spec 2 = Fire
    displayText = tostring(fireProcLevel)
  end

  ApplyArcValue(pct)

  -- Mage Givre (specID 64) : texte affiche les stacks de Glaçons (205473), arc reste sur la mana. Lit ns.AuraText.ICICLES directement, ApplyStacksToText échoue pour ce spellID.
  if ns._playerClass == "MAGE" and ns._specID == 64 then
    local txt = ns.AuraText and ns.AuraText.ICICLES
    pcall(bar.text.SetText, bar.text, txt or "0")
  else
    SetResourceText(displayText)
  end
end

-- Reset l'état de visibilité (pour les changements de config)
function ResourceCircle.ResetVisibility()
  lastVisibilityState = nil
end

-- Secondary Dots : cercles secondaires (DK runes, Combo Points, etc.)

-- Couleurs par type et spec
local SEC_COLORS = {
  -- DK Runes par spec
  RUNES = {
    [250] = { 0.9, 0.1, 0.1 },  -- Blood : rouge
    [251] = { 0.3, 0.7, 1.0 },  -- Frost : bleu
    [252] = { 0.3, 0.9, 0.1 },  -- Unholy : vert
    default = { 0, 0.7, 0.9 },
  },
  -- Combo Points Rogue
  COMBO_ROGUE = {
    default = { 1.0, 0.8, 0.0 },  -- jaune doré
    full    = { 1.0, 0.2, 0.0 },  -- rouge-orange quand max
  },
  -- Combo Points Druide (Félin)
  COMBO_DRUID = {
    default = { 1.0, 0.55, 0.0 },  -- orange ambré (couleur druide)
    full    = { 1.0, 0.15, 0.0 },  -- rouge-orangé quand max
  },
  -- Chi (Moine Windwalker)
  CHI = {
    default = { 0.0, 0.9, 0.6 },  -- turquoise jade
    full    = { 1.0, 1.0, 1.0 },  -- blanc quand max
  },
  -- Holy Power (Paladin Sacré)
  HOLY_POWER = {
    default = { 1.0, 0.82, 0.0 },  -- or sacré
    full    = { 1.0, 1.00, 0.6 },  -- or brillant quand max (remplacé par dotsA à l'affichage)
  },
  ESSENCE = {
    default = { 0.16, 0.82, 0.65 },  -- vert-émeraude (Preservation Evoker)
    full    = { 0.45, 1.00, 0.80 },  -- vert brillant quand max
    burst   = { 1.00, 1.00, 1.00 },  -- blanc : Essence Burst proc (369299)
  },
  -- Arcane Charges (Mage Arcane)
  ARCANE_CHARGES = {
    default = { 0.55, 0.25, 0.90 },  -- violet arcanique
    full    = { 0.65, 0.35, 1.00 },  -- violet brillant quand 4/4
  },
  -- Coeur Démoniaque (Warlock Démonologie, specID 265)
  DEMONIC_CORE = {
    default = { 0.55, 0.22, 0.85 },  -- violet infernal
    full    = { 0.80, 0.45, 1.00 },  -- violet brillant quand 2/2
  },
}
local SEC_DIM = 0.25  -- alpha quand vide/en cd

-- Detecte le type de secondary dots selon la classe/forme
function ResourceCircle.DetectSecondaryDots()
  local _, playerClass = UnitClass("player")
  local newType = nil
  local newCount = 0

  if playerClass == "DEATHKNIGHT" then
    newType = "RUNES"
    newCount = 6
  elseif playerClass == "ROGUE" then
    newType = "COMBO_ROGUE"
    local maxCP = UnitPowerMax("player", Enum.PowerType.ComboPoints)
    newCount = (maxCP and maxCP > 0) and maxCP or 5
  elseif playerClass == "DRUID" then
    local formID = GetShapeshiftFormID()
    if formID == DRUID_CAT_FORM then
      newType = "COMBO_DRUID"
      local maxCP = UnitPowerMax("player", Enum.PowerType.ComboPoints)
      newCount = (maxCP and maxCP > 0) and maxCP or 5
    end
  elseif playerClass == "MONK" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    if specID == 269 then  -- Windwalker
      newType = "CHI"
      local maxChi = UnitPowerMax("player", Enum.PowerType.Chi)
      newCount = (maxChi and maxChi > 0) and maxChi or 5
    end
  elseif playerClass == "PALADIN" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    local cfg = ns.GetCfg("resourceCircle")
    local holyPowerAllSpecs = cfg and cfg.holyPowerAllSpecs
    if specID == 65 or (holyPowerAllSpecs and (specID == 66 or specID == 70)) then
      newType = "HOLY_POWER"
      local maxHP = UnitPowerMax("player", Enum.PowerType.HolyPower)
      newCount = (maxHP and maxHP > 0) and maxHP or 5
    end
  elseif playerClass == "EVOKER" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    local cfg = ns.GetCfg("resourceCircle")
    local essenceAllSpecs = cfg and cfg.essenceAllSpecs
    if specID == 1468 or (essenceAllSpecs and (specID == 1473 or specID == 1467)) then
      newType = "ESSENCE"
      local maxEss = UnitPowerMax("player", Enum.PowerType.Essence)
      newCount = (maxEss and maxEss > 0) and maxEss or 6
    end
  elseif playerClass == "MAGE" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    if specID == 62 then  -- Arcane
      newType = "ARCANE_CHARGES"
      newCount = 4
    end
  -- Warlock Démonologie (Coeur démoniaque) : orbes désactivées, lecture des stacks via GetPlayerAuraBySpellID peu fiable en combat.
  -- Stacks affichés via le texte de ressource secondaire (SecondaryResourceDefs[266]) qui passe par le canal clone-stack CDM à la place.
  end

  -- Si le type/count n'a pas change, ne rien faire
  if newType == secDotType and newCount == secDotCount then return end

  -- Nettoyer l'ancien ticker
  if secUpdateTicker then secUpdateTicker:Cancel(); secUpdateTicker = nil end

  -- Cacher les anciens dots en surplus et réinitialiser leur anim
  for i = 1, #secDots do
    if secDots[i] then
      secDots[i]:Hide()
      secDots[i]:SetAlpha(0)
      if secDotAnims[i] then
        secDotAnims[i].progress = 0
        secDotAnims[i].target   = 0
      end
    end
  end

  secDotType = newType
  secDotCount = newCount

  if not secDotType or secDotCount == 0 then return end

  -- Creer ou recycler les frames (réinitialise l'état d'animation)
  ResourceCircle.EnsureSecDotFrames(secDotCount)
  -- Positionner
  ResourceCircle.LayoutSecDots()
  -- Couleurs
  ResourceCircle.UpdateSecDotColors()
  -- Ticker pour le fill + ciblage des animations
  -- Cercle masque : 1 passe sur 15 suffit (les cibles d'animation retombent a 0 sans rafale a 60 Hz)
  local secSkip = 0
  secUpdateTicker = C_Timer.NewTicker(0.016, function()
    if lastVisibilityState ~= true then
      secSkip = secSkip + 1
      if secSkip % 15 ~= 0 then return end
    end
    ResourceCircle.UpdateSecDots()
  end)
end

-- Cree les frames secondary dot si necessaire (recycler)
function ResourceCircle.EnsureSecDotFrames(count)
  if not bar then return end
  for i = 1, count do
    if not secDots[i] then
      local f = CreateFrame("Frame", "AishCoreSecDot" .. i, bar)
      -- Doit etre au-dessus de overlayFrame : meme niveau que textFrame
      if bar.textFrame then f:SetFrameLevel(bar.textFrame:GetFrameLevel()) end
      -- Fond sombre
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetTexture(SEC_DOT_TEX)
      bg:SetAllPoints()
      local bgc = GetBgColor()
      bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4] or 1)
      f.bg = bg
      -- Fill (même texture Circle_Smooth que le Skyriding)
      local fill = f:CreateTexture(nil, "ARTWORK")
      fill:SetTexture(SEC_DOT_TEX)
      fill:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
      f.fill = fill
      -- Bordure subtile
      local border = f:CreateTexture(nil, "OVERLAY")
      border:SetTexture(SEC_DOT_TEX)
      border:SetAllPoints()
      border:SetVertexColor(0.3, 0.3, 0.3, 0.3)
      f.border = border
      -- Runes : remplissage radial natif (le fill par hauteur reste pour les autres types d'orbes)
      local radial = CreateFrame("StatusBar", nil, f)
      radial:SetAllPoints(f)
      radial:SetFrameLevel(f:GetFrameLevel() + 1)
      ns.SetSmoothStatusBarTexture(radial, ns.Media.circle)
      radial:SetRenderMode(Enum.StatusBarRenderMode.Radial)
      radial:SetMinMaxValues(0, 1)
      radial:SetValue(1)
      radial:Hide()
      f.radial = radial
      f.fillPct = 0
      f._homeX = 0
      f._homeY = 0
      secDots[i] = f
    end
    -- Initialiser / réinitialiser l'état d'animation
    secDotAnims[i] = secDotAnims[i] or {}
    secDotAnims[i].progress = 0
    secDotAnims[i].target   = 0
    local isRune = (secDotType == "RUNES")
    secDots[i].fill:SetShown(not isRune)
    secDots[i].radial:SetShown(isRune)
    -- Masquer pour que le slide-in parte de zéro
    secDots[i]:SetAlpha(0)
    secDots[i]:Hide()
  end
end

-- Positionne les secondary dots en arc autour du cercle
function ResourceCircle.LayoutSecDots()
  if not bar or secDotCount == 0 then return end
  local cfg = ns.GetCfg("resourceCircle")
  local size = cfg.size
  -- Lecture avec fallback per-dotType → global (Feature 5)
  local pfx = secDotType and ("secondaryDots_" .. secDotType .. "_") or ""
  local function pv(k, fallback) local v = pfx ~= "" and cfg[pfx..k] or nil; return v ~= nil and v or cfg[fallback] end
  local dotSize    = size * (pv("size",     "secondaryDotsSize")     or 0.16)
  local radius     = size * (pv("radius",   "secondaryDotsRadius")   or 0.62)
  local centerAngle =       (pv("rotation", "secondaryDotsRotation") or 90)
  local spread     =         pv("spread",   "secondaryDotsSpread")   or 24
  local revKey     = pfx ~= "" and cfg[pfx.."reversed"]
  local reversed   = revKey ~= nil and revKey or cfg.secondaryDotsReversed

  for i = 1, secDotCount do
    local f = secDots[i]
    if f then
      -- Calculer l'angle : centre +/- spread (inversé si option active)
      local idx = reversed and (secDotCount + 1 - i) or i
      local offset = (idx - (secDotCount + 1) / 2) * spread
      local angle = math.rad(centerAngle + offset)
      local rx = math.cos(angle) * radius
      local ry = math.sin(angle) * radius

      -- Mémoriser la position "home" pour l'animation slide
      f._homeX = rx
      f._homeY = ry

      f:SetSize(dotSize, dotSize)
      f:ClearAllPoints()
      f:SetPoint("CENTER", bar, "CENTER", rx, ry)
      f.fill:SetSize(dotSize, dotSize)
    end
  end
end

-- Met a jour les couleurs des secondary dots
function ResourceCircle.UpdateSecDotColors()
  if secDotCount == 0 then return end
  local color
  if secDotType == "RUNES" then
    local specIndex = GetSpecialization and GetSpecialization() or nil
    local specID = specIndex and (GetSpecializationInfo and GetSpecializationInfo(specIndex)) or nil
    color = SEC_COLORS.RUNES[specID] or SEC_COLORS.RUNES.default
  elseif secDotType == "COMBO_ROGUE" then
    color = SEC_COLORS.COMBO_ROGUE.default
  elseif secDotType == "COMBO_DRUID" then
    color = SEC_COLORS.COMBO_DRUID.default
  elseif secDotType == "CHI" then
    color = SEC_COLORS.CHI.default
  elseif secDotType == "HOLY_POWER" then
    color = SEC_COLORS.HOLY_POWER.default
  elseif secDotType == "ESSENCE" then
    color = SEC_COLORS.ESSENCE.default
  elseif secDotType == "ARCANE_CHARGES" then
    color = SEC_COLORS.ARCANE_CHARGES.default
  elseif secDotType == "DEMONIC_CORE" then
    color = SEC_COLORS.DEMONIC_CORE.default
  else
    color = { 1, 1, 1 }
  end
  -- Override couleur globes (SpellEffects peut imposer une couleur par condition)
  local activeColor = _secDotColorOverride or color
  for i = 1, secDotCount do
    local f = secDots[i]
    if f and f.fill then
      f.fill:SetVertexColor(activeColor[1], activeColor[2], activeColor[3], 1)
      if f.radial then f.radial:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], 1) end
      f._baseColor = color
    end
  end
end

--- Override la couleur des globes secondaires (imposé par SpellEffects selon la condition active).
--- Appeler avec nil pour retirer l'override.
function ResourceCircle.SetSecDotColorOverride(r, g, b)
  _secDotColorOverride = (r and { r, g, b }) or nil
  ResourceCircle.UpdateSecDotColors()
end

function ResourceCircle.ClearSecDotColorOverride()
  _secDotColorOverride = nil
  ResourceCircle.UpdateSecDotColors()
end

--- Retourne true si le proc Essence Burst est actif (Evoker Preservation).
function ResourceCircle.IsEssenceBurstActive()
  return essenceBurstActive == true
end

--- Retourne le nombre de Coeurs Démoniaques actifs (Warlock Démonologie, 0-2).
function ResourceCircle.GetDemonicCoreStacks()
  return demonicCoreStacks
end

-- Met a jour le fill des secondary dots (et les cibles d'animation slide)
function ResourceCircle.UpdateSecDots()
  if secDotCount == 0 then return end
  if previewMode then return end -- ne pas écraser les valeurs forcées par SetPreview
  -- Ne pas piloter les cibles quand le cercle est en cours de disparition
  local circleVisible = (lastVisibilityState == true)

  if secDotType == "RUNES" then
    local now = GetTime()
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        local start, duration, runeReady = GetRuneCooldown(i)
        local pct
        if runeReady then
          pct = 1
        elseif start and duration and duration > 0 then
          pct = math.min((now - start) / duration, 1)
        else
          pct = 1
        end
        -- Les runes sont toujours "présentes" (slide-in dès que la case existe)
        if circleVisible then oa.target = 1 end
        f.radial:SetValue(pct)
        f.radial:SetAlpha(pct >= 1 and 1 or (SEC_DIM + (1 - SEC_DIM) * pct))
      end
    end

  elseif secDotType == "COMBO_ROGUE" or secDotType == "COMBO_DRUID" then
    local ok, cp = pcall(UnitPower, "player", Enum.PowerType.ComboPoints)
    if not ok then cp = 0 end
    local maxCP = secDotCount
    local palette = SEC_COLORS[secDotType]
    local comboColor = _secDotColorOverride or palette.default
    local fullColor  = _secDotColorOverride or palette.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= cp then
          -- Slide-in : piloter la cible de l'animation
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if cp >= maxCP then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(comboColor[1], comboColor[2], comboColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end

  elseif secDotType == "CHI" then
    local ok, chi = pcall(UnitPower, "player", Enum.PowerType.Chi)
    if not ok then chi = 0 end
    local maxChi = secDotCount
    local chiColor  = _secDotColorOverride or SEC_COLORS.CHI.default
    local fullColor = _secDotColorOverride or SEC_COLORS.CHI.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= chi then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if chi >= maxChi then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(chiColor[1], chiColor[2], chiColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end

  elseif secDotType == "HOLY_POWER" then
    local ok, hp = pcall(UnitPower, "player", Enum.PowerType.HolyPower)
    if not ok then hp = 0 end
    local maxHP = secDotCount
    local CLR = ns.Modules.Colors
    local defaultColor = _secDotColorOverride or SEC_COLORS.HOLY_POWER.default
    local dotsA = _secDotColorOverride or (CLR and CLR.Get("powerdotsa")) or SEC_COLORS.HOLY_POWER.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= hp then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if hp >= maxHP then
            f.fill:SetVertexColor(dotsA[1], dotsA[2], dotsA[3], 1)
          else
            f.fill:SetVertexColor(defaultColor[1], defaultColor[2], defaultColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end

  elseif secDotType == "ESSENCE" then
    local ok, ess = pcall(UnitPower, "player", Enum.PowerType.Essence)
    if not ok then ess = 0 end
    local maxEss = secDotCount
    local defaultColor = _secDotColorOverride or SEC_COLORS.ESSENCE.default
    local fullColor    = _secDotColorOverride or SEC_COLORS.ESSENCE.full
    local CLR = ns.Modules.Colors
    local burstColor = _secDotColorOverride or (CLR and CLR.Get("powertext")) or SEC_COLORS.ESSENCE.burst
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= ess then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if essenceBurstActive then
            f.fill:SetVertexColor(burstColor[1], burstColor[2], burstColor[3], 1)
          elseif ess >= maxEss then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defaultColor[1], defaultColor[2], defaultColor[3], 1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end
  elseif secDotType == "ARCANE_CHARGES" then
    local ok, ac = pcall(UnitPower, "player", Enum.PowerType.ArcaneCharges)
    if not ok then ac = 0 end
    local maxAC     = secDotCount
    local defColor  = _secDotColorOverride or SEC_COLORS.ARCANE_CHARGES.default
    local fullColor = _secDotColorOverride or SEC_COLORS.ARCANE_CHARGES.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= ac then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if ac >= maxAC then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end
  elseif secDotType == "DEMONIC_CORE" then
    -- Priorité : stacks du buff 264173 ; fallback : glow Demonbolt si buff indisponible
    local stacks = 0
    local ok, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 264173)
    if ok and auraData then
      stacks = (auraData.applications or 0)
      if stacks == 0 then stacks = 1 end  -- aura présente = au moins 1 charge
    elseif demonicCoreOverlayActive then
      stacks = 1
    end
    demonicCoreStacks = stacks
    local defColor  = _secDotColorOverride or SEC_COLORS.DEMONIC_CORE.default
    local fullColor = _secDotColorOverride or SEC_COLORS.DEMONIC_CORE.full
    for i = 1, secDotCount do
      local f = secDots[i]
      local oa = secDotAnims[i]
      if f and oa then
        if i <= stacks then
          if circleVisible then oa.target = 1 end
          local fullSize = f:GetHeight()
          if fullSize > 0 then f.fill:SetHeight(fullSize) end
          if stacks >= secDotCount then
            f.fill:SetVertexColor(fullColor[1], fullColor[2], fullColor[3], 1)
          else
            f.fill:SetVertexColor(defColor[1],  defColor[2],  defColor[3],  1)
          end
          f.fill:SetAlpha(1)
        else
          oa.target = 0
        end
      end
    end
  end
end

-- Alias pour compatibilite
function ResourceCircle.UpdateRuneColors()
  ResourceCircle.UpdateSecDotColors()
end

-- Ressource secondaire : texte sous le cercle (Bone Shield, Soul Fragments…)

-- Couleurs par défaut de l'arc de durée central (dupliqué de CenterArc.lua/SettingsPanel.lua pour éviter un couplage cross-module).
local ARC_DEFAULT_COLORS = {
  [66]  = { 1.00, 0.88, 0.10 },  -- Paladin Prot : Consécration
  [73]  = { 0.78, 0.25, 0.25 },  -- Guerrier Prot : Dur au mal
  [250] = { 0.20, 0.78, 0.35 },  -- DK Sang : Death's Due (188290)
}

-- Couleur courante de l'arc de durée pour une spec : override utilisateur sinon couleur par défaut ; aligne le texte de ressource secondaire sur l'arc quand ils représentent la même ressource.
local function GetDurationArcColor(specID)
  local r = ns.GetSecResCfg("durationArcColorR", specID)
  if r then
    return { r, ns.GetSecResCfg("durationArcColorG", specID) or 1, ns.GetSecResCfg("durationArcColorB", specID) or 1, 1 }
  end
  return ARC_DEFAULT_COLORS[specID]
end

-- Réapplique uniquement la géométrie dépendante de la spec (arc de durée, texte ressource secondaire), séparée d'ApplySettings pour ne pas interférer avec la visibilité combat.
function ResourceCircle.RefreshSecResSpecGeometry(specID)
  if not bar then return end
  local cfg = ns.GetCfg("resourceCircle")
  local arcPx = ArcPx(cfg)

  if bar.durationArc then
    local durArcPx = arcPx * (ns.GetSecResCfg("durationArcRatio", specID) or DURATION_ARC_RATIO)
    bar.durationArc:SetSize(durArcPx, durArcPx * ARC_CROP_H)
    bar.durationArc:ClearAllPoints()
    bar.durationArc:SetPoint("TOP", bar, "CENTER", 0, durArcPx / 2)
    RecordHome(bar.durationArc, "TOP", bar, "CENTER", 0, durArcPx / 2, durArcPx, durArcPx * ARC_CROP_H)
    if bar.durationOvl then
      local durOvPx = durArcPx * DurationHole(specID)
      bar.durationOvl:SetSize(math.max(durOvPx, 0.01), math.max(durOvPx, 0.01))
      RecordHome(bar.durationOvl, "CENTER", bar, "CENTER", 0, 0, math.max(durOvPx, 0.01), math.max(durOvPx, 0.01))
    end
    SetArcAngle(bar.durationArc, ns.GetSecResCfg("durationArcStartAngle", specID), ns.GetSecResCfg("durationArcEndAngle", specID),
      ns.GetSecResCfg("durationArcReverse", specID))
    if bar.durationArcV then
      bar.durationArcV:SetSize(durArcPx, durArcPx * ARC_CROP_V)
      bar.durationArcV:ClearAllPoints()
      bar.durationArcV:SetPoint("TOP", bar, "CENTER", 0, durArcPx / 2)
      RecordHome(bar.durationArcV, "TOP", bar, "CENTER", 0, durArcPx / 2, durArcPx, durArcPx * ARC_CROP_V)
    end
  end

  RefreshSecResDurBar(specID)

  local secResTextSize = ns.GetSecResCfg("secResTextSize", specID) or 11
  if bar.secResText then
    bar.secResText:SetFont(ns.GetSecResCfg("secResFont", specID) or FONT_SECRES_DEFAULT, secResTextSize, "")
    -- Police de la déco : indépendante (secResDecoFont), reprend secResFont si non définie.
    local decoFont = ns.GetSecResCfg("secResDecoFont", specID) or ns.GetSecResCfg("secResFont", specID) or FONT_SECRES_DEFAULT
    if bar.secResDashL then bar.secResDashL:SetFont(decoFont, secResTextSize, "") end
    if bar.secResDashR then bar.secResDashR:SetFont(decoFont, secResTextSize, "") end

    -- Priorité : override utilisateur > couleur de l'arc de durée si même ressource > def.color > repli "powerdotsb". Ici (pas DetectSecondaryResource) pour rester live via BindColorButton.
    local userR = ns.GetSecResCfg("secResColorR", specID)
    local c
    if userR then
      c = { userR, ns.GetSecResCfg("secResColorG", specID) or 1, ns.GetSecResCfg("secResColorB", specID) or 1, 1 }
    elseif secResDef then
      local CLR = ns.Modules.Colors
      c = (secResDef.useAbsorb and GetDurationArcColor(specID)) or secResDef.color or (CLR and CLR.Get("powerdotsb"))
    end
    if c then bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
  end
  if bar.secResFrame and bar.text then
    local secResOffX = ns.GetSecResCfg("secResTextOffsetX", specID) or 0
    local secResOffY = ns.GetSecResCfg("secResTextOffsetY", specID) or -2
    bar.secResFrame:ClearAllPoints()
    bar.secResFrame:SetPoint("TOP", bar.text, "BOTTOM", secResOffX, secResOffY)
    RecordHome(bar.secResFrame, "TOP", bar.text, "BOTTOM", secResOffX, secResOffY, 120, 18)
  end
  RefreshSecResDeco(specID)
end

--- Resolution de spec exploitable, ou nil. Ne renvoie JAMAIS de valeur par defaut :
--- juste apres un /reload, GetSpecialization() repond nil pendant un court instant, et
--- un detecteur qui interprete ce nil comme "pas ma spe" se desactive jusqu'au prochain
--- changement de spe (symptome : ressource secondaire, arc de Report et barre de duree
--- absents apres un reload, revenant seulement en rechangeant de spe).
local function ResolveSpecID()
  if not (GetSpecialization and GetSpecializationInfo) then return nil end
  local idx = GetSpecialization()
  if not idx or idx == 0 then return nil end
  local ok, specID = pcall(GetSpecializationInfo, idx)
  if not ok or not specID or specID == 0 then return nil end
  return specID
end

--- Relance les detecteurs dependants de la spec des qu'elle devient lisible. Sans effet
--- si elle l'est deja. Retry borne, meme motif que RetryHealth dans UnitBars.lua.
local _specRetryRunning = false
function ResourceCircle.RetrySpecDetectionIfNeeded()
  if ResolveSpecID() then return end
  if _specRetryRunning then return end
  _specRetryRunning = true
  local tries = 0
  local function Retry()
    tries = tries + 1
    if ResolveSpecID() then
      _specRetryRunning = false
      ResourceCircle.DetectSecondaryDots()
      ResourceCircle.DetectSecondaryResource()
      ResourceCircle.DetectStagger()
      return
    end
    if tries < 10 then
      C_Timer.After(0.5, Retry)
    else
      _specRetryRunning = false
    end
  end
  C_Timer.After(0.3, Retry)
end

-- Détecte la ressource secondaire selon la spec active et démarre le ticker
function ResourceCircle.DetectSecondaryResource()
  if not bar then return end

  -- Arrêter l'ancien ticker
  if secResUpdateTicker then secResUpdateTicker:Cancel(); secResUpdateTicker = nil end
  secResDef = nil

  -- Désabonner l'ancien canal clone-stack avant d'en choisir un nouveau, sinon un vieux spellID resterait abonné indéfiniment.
  if _secResStackSubIDs and ns.Auras and ns.Auras.UnsubscribeCDMAuraStack then
    for _, sid in ipairs(_secResStackSubIDs) do
      ns.Auras.UnsubscribeCDMAuraStack(sid, "resourceCircleSecRes")
    end
  end
  _secResStackSubIDs = nil

  -- Cacher le texte de ressource secondaire
  SetSecResShown(false)

  if not ns.SecondaryResourceDefs then return end

  -- Résoudre le specID courant (nil = pas encore lisible, cf. ResolveSpecID)
  local specID = ResolveSpecID()
  if not specID then return end

  local def = ns.SecondaryResourceDefs[specID]
  if not def then return end

  secResDef = def

  -- Abonner bar.secResText au canal clone-stack (CDMHooks) : ApplyStacksToText échoue en combat pour certains sorts, ce canal reste fiable.
  -- useArmor y est inclus : le montant d'armure n'est pas lisible en combat, mais le
  -- nombre de stacks l'est via ce canal -- mieux vaut un compteur qu'un texte vide.
  if (def.useStacks or def.useArmor) and def.spellID and ns.Auras and ns.Auras.SubscribeCDMAuraStack then
    _secResStackSubIDs = { def.spellID }
    ns.Auras.SubscribeCDMAuraStack(def.spellID, "resourceCircleSecRes", bar.secResText)
    if def.altSpellID then
      _secResStackSubIDs[#_secResStackSubIDs + 1] = def.altSpellID
      ns.Auras.SubscribeCDMAuraStack(def.altSpellID, "resourceCircleSecRes", bar.secResText)
    end
    -- Marque ces spellID "stack capable" dès l'init pour éviter le blacklistage croisé par le tracker d'auras générique.
    if ns.Auras.MarkStackCapable then
      ns.Auras.MarkStackCapable(def.spellID)
      if def.altSpellID then ns.Auras.MarkStackCapable(def.altSpellID) end
    end
  end

  -- Démarrer le ticker de mise à jour (0.1s suffit pour ce type de ressource)
  secResUpdateTicker = C_Timer.NewTicker(0.1, function()
    ResourceCircle.UpdateSecondaryResource()
  end)

  -- Réapplique la géométrie de spec sans passer par ApplySettings() complet (perturberait lastVisibilityState).
  ResourceCircle.RefreshSecResSpecGeometry(specID)
end

-- GetPlayerAuraBySpellID() peu fiable pour certaines auras ; ns.Auras.cdmData fait référence. Valeur possiblement secrète en combat : jamais de concat/format dessus, juste SetText brut.
-- Pop (fade+slide) sur bar.secResFrame au passage 0 -> 1+ stack en combat, détecté via le booléen `applied` (jamais la valeur réelle). Durée dédiée, séparée de CIRCLE_ANIM.secResText.
local SEC_RES_POP_DURATION = 0.3
local _secResWasApplied = false
local _secResPopTicker  = nil
local function StartSecResPop()
  if not bar or not bar.secResFrame then return end
  if _secResPopTicker then _secResPopTicker:Cancel(); _secResPopTicker = nil end
  local spec  = CIRCLE_ANIM.secResText.show
  local home  = _elemHome[bar.secResFrame]
  local start = GetTime()
  bar.secResFrame:SetAlpha(0)
  _secResPopTicker = C_Timer.NewTicker(0.016, function()
    local t = math.min((GetTime() - start) / SEC_RES_POP_DURATION, 1)
    local eased = ns.Ease(spec.ease, spec.easeType, t)
    bar.secResFrame:SetAlpha(eased)
    if home then
      bar.secResFrame:ClearAllPoints()
      bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint,
        home.x, home.y + (spec.slideY or 0) * (1 - eased))
    end
    if t >= 1 then
      _secResPopTicker:Cancel(); _secResPopTicker = nil
    end
  end)
end

-- Symétrique de StartSecResPop : transition 1+ -> 0 stack en combat, cache le texte/déco
-- une fois le fondu terminé (pas avant, sinon rien à voir disparaître).
local function StartSecResPopOut()
  if not bar or not bar.secResFrame then return end
  if _secResPopTicker then _secResPopTicker:Cancel(); _secResPopTicker = nil end
  local spec  = CIRCLE_ANIM.secResText.hide
  local home  = _elemHome[bar.secResFrame]
  local start = GetTime()
  _secResPopTicker = C_Timer.NewTicker(0.016, function()
    local t = math.min((GetTime() - start) / SEC_RES_POP_DURATION, 1)
    local eased = ns.Ease(spec.ease, spec.easeType, t)
    bar.secResFrame:SetAlpha(1 - eased)
    if home then
      bar.secResFrame:ClearAllPoints()
      bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint,
        home.x, home.y + (spec.slideY or 0) * eased)
    end
    if t >= 1 then
      _secResPopTicker:Cancel(); _secResPopTicker = nil
      SetSecResShown(false)
      -- Remettre à l'état de repos pour que le prochain pop-in reparte propre.
      bar.secResFrame:SetAlpha(1)
      if home then
        bar.secResFrame:ClearAllPoints()
        bar.secResFrame:SetPoint(home.point, home.relTo, home.relPoint, home.x, home.y)
      end
    end
  end)
end

-- Teste val == 0 sans planter si val est une secret value ; si la comparaison échoue, considère "pas confirmé zéro" et affiche quand même. Même helper que dans PriorityBar.lua.
local function IsConfirmedZero(val)
  if val == nil then return false end
  local ok, isZero = pcall(function() return val == 0 end)
  return ok and isZero == true
end

-- Cherche les stacks d'une ressource secondaire via CDM puis fallbacks (GetPlayerAuraBySpellID, énumération HELPFUL, GetSpellCastCount) ;
-- valeur transmise brute à sink (jamais de tonumber/comparaison, potentiellement secrète en combat), partagé entre SetText et SetValue.
local function ApplyStacksTo(sink, spellID, dbg)
  local A = ns.Auras
  local cdmPlayer = A and A.cdmData and A.cdmData.player
  local cdmEntry = cdmPlayer and cdmPlayer[spellID]
  if cdmEntry and cdmEntry.instID then
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if dbg then dbg.cdm = { ok = ok, disp = disp } end
    if ok and disp ~= nil and not IsConfirmedZero(disp) then
      if sink(disp) then if dbg then dbg.path = "cdm" end; return true end
    end
    -- Instance périmée : on tombe dans les fallbacks ci-dessous plutôt que d'abandonner.
  end

  -- Fallback 1 : GetPlayerAuraBySpellID (aura jamais vue par le CDM Blizzard)
  local okAura, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
  if dbg then dbg.f1 = { okAura = okAura, hasAura = (aura ~= nil), instID = aura and aura.auraInstanceID } end
  if okAura and aura then
    -- aura.applications d'abord : GetAuraApplicationDisplayCount peut renvoyer nil pour une aura
    -- pourtant présente avec un vrai compte lisible via applications (ex: Glaçons/205473).
    local okApp, app = pcall(function() return aura.applications end)
    if dbg then dbg.f1.okApp = okApp; dbg.f1.app = app end
    if okApp and app ~= nil and not IsConfirmedZero(app) then
      if sink(app) then if dbg then dbg.path = "fallback1-applications" end; return true end
    end
    if aura.auraInstanceID then
      local ok2, disp2 = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, aura.auraInstanceID, 1, 999)
      if dbg then dbg.f1.ok2 = ok2; dbg.f1.disp2 = disp2 end
      if ok2 and disp2 ~= nil and not IsConfirmedZero(disp2) then
        if sink(disp2) then if dbg then dbg.path = "fallback1-displaycount" end; return true end
      end
    end
  end

  -- Fallback 2 : énumération des auras HELPFUL ; comparaison spellId protégée par pcall (secret en combat).
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 60 do
      local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      -- ok3=false = cette position est secrète, pas "fin de liste" -- continuer, pas de break.
      if ok3 and not d then break end
      if ok3 and d then
      local okMatch, isMatch = pcall(function() return d.spellId == spellID end)
      if dbg and not okMatch then dbg.f2MatchErrAt = dbg.f2MatchErrAt or i end
      if okMatch and isMatch then
        local okApp, disp3 = pcall(function() return d.applications end)
        if dbg then dbg.f2 = { matchedAt = i, okApp = okApp, disp3 = disp3 } end
        if okApp and disp3 ~= nil and not IsConfirmedZero(disp3) then
          if sink(disp3) then if dbg then dbg.path = "fallback2-applications" end; return true end
        end
        -- applications absent/0 confirmé : essaie quand même via
        -- auraInstanceID (sink combat-safe dédié, jamais secret lui-même).
        local okInstID, instID = pcall(function() return d.auraInstanceID end)
        if okInstID and instID then
          local okIdx, dispIdx = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, instID, 1, 999)
          if dbg then dbg.f2.okIdx = okIdx; dbg.f2.dispIdx = dispIdx end
          if okIdx and dispIdx ~= nil and not IsConfirmedZero(dispIdx) then
            if sink(dispIdx) then if dbg then dbg.path = "fallback2-instanceid" end; return true end
          end
        end
      end
      end
    end
  end

  -- Pas de fallback GetSpellCastCount ici : répond count=0 pour le spellID d'un buff. Voir ApplyCastCountToText (secResDef.castCountSpellID).
  return false
end

-- Pas de "local" ici : assigne l'upvalue forward-déclarée avant Update().
function ApplyStacksToText(fontString, spellID, dbg)
  return ApplyStacksTo(function(v) return pcall(fontString.SetText, fontString, v) end, spellID, dbg)
end

-- Exposé pour réutilisation par les stacks d'icônes (Debuffs.lua/Cooldowns.lua/Procs.lua).
ResourceCircle.ApplyStacksTo = ApplyStacksTo

-- Équivalent de ApplyStacksTo pour un debuff de la cible (CDM puis énumération HARMFUL). Utilisé par Mage Givre (specID 64, debuff 1246769).
local function ApplyTargetStacksTo(sink, spellID, dbg)
  if not UnitExists("target") then return false end
  local A = ns.Auras
  local cdmTarget = A and A.cdmData and A.cdmData.target
  local cdmEntry = cdmTarget and cdmTarget[spellID]
  if cdmEntry and cdmEntry.instID then
    local ok, disp = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, cdmEntry.instID, 1, 999)
    if dbg then dbg.cdm = { ok = ok, disp = disp } end
    if ok and disp ~= nil then
      -- Instance confirmée vivante : si le compte n'est pas exploitable (debuff à application
      -- unique), affiche "1" plutôt que d'échouer -- la présence seule reste une info utile.
      local value = (not IsConfirmedZero(disp)) and disp or 1
      if sink(value) then if dbg then dbg.path = "cdm" end; return true end
    end
    -- Instance périmée (cdmData jamais purgé) : tombe dans le fallback ci-dessous.
  end

  -- Fallback : énumération des auras HARMFUL de la cible (comparaison spellId protégée par pcall).
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    for i = 1, 40 do
      local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
      if ok3 and not d then break end
      if ok3 and d then
      local okMatch, isMatch = pcall(function() return d.spellId == spellID end)
      if okMatch and isMatch then
        local okApp, disp3 = pcall(function() return d.applications end)
        if dbg then dbg.f2 = { matchedAt = i, okApp = okApp, disp3 = disp3 } end
        local value = (okApp and disp3 ~= nil and not IsConfirmedZero(disp3)) and disp3 or 1
        if sink(value) then if dbg then dbg.path = "fallback2-applications" end; return true end
      end
      end
    end
  end

  return false
end

local function ApplyTargetStacksToText(fontString, spellID, dbg)
  return ApplyTargetStacksTo(function(v) return pcall(fontString.SetText, fontString, v) end, spellID, dbg)
end

-- Compteur natif Blizzard sur un bouton d'action (certains sorts Mistweaver sans buff associé, ex Don de Sheilun/Thé de Mana), appelé seulement si secResDef.castCountSpellID est défini explicitement.
-- GetText/GetStringWidth sur button.Count restent lisibles sans planter (count==0 lui-même plante en combat) et permettent de détecter un bouton vide. Bouton retrouvé via le cache de PriorityBar.lua.
local function IsActionCountConfirmedHidden(spellID)
  local PB = ns.Modules and ns.Modules.PriorityBar
  local btn = PB and PB._GetCachedBtn and PB._GetCachedBtn(spellID)
  if not btn or not btn.Count then return false end
  local okTxt, isEmptyTxt = pcall(function()
    local t = btn.Count:GetText()
    return t == nil or t == ""
  end)
  if okTxt and isEmptyTxt then return true end
  local okW, isZeroW = pcall(function()
    return btn.Count:GetStringWidth() == 0
  end)
  if okW and isZeroW then return true end
  return false
end

-- Aucun signal fiable pour distinguer "0" de "3" en combat : affiche la valeur réelle (IsConfirmedZero filtre hors combat), sauf si IsActionCountConfirmedHidden a tranché via le bouton natif.
local function ApplyCastCountToText(fontString, spellID)
  if not (C_Spell and C_Spell.GetSpellCastCount) then return false end
  if IsActionCountConfirmedHidden(spellID) then return false end
  local ok, count = pcall(C_Spell.GetSpellCastCount, spellID)
  if not ok or count == nil or IsConfirmedZero(count) then return false end
  return pcall(fontString.SetText, fontString, count)
end

-- Absorb restant via UnitGetTotalAbsorbs (AuraData.points est une secret table en combat, indexer plante) ; présence via IsCDMAuraSwipePresent, repli GetPlayerAuraBySpellID
local function ApplyAbsorbToText(fontString, spellID)
  local A = ns.Auras
  local present = A and A.IsCDMAuraSwipePresent and A.IsCDMAuraSwipePresent(spellID)
  if not present then
    local okP, auraData = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    present = okP and auraData ~= nil
  end
  if not present then return false end

  local fn = UnitAbsorb or UnitGetTotalAbsorbs
  if not fn then return false end
  local ok, absorb = pcall(fn, "player")
  if not ok or absorb == nil then return false end

  -- Option "grand nombre" (10000 -> "10k") : AbbreviateNumbers accepte les secret numbers, résultat passé brut à SetText (même pattern que ShortenHP/SetHPText).
  if ns.GetSecResCfg("secResAbsorbAbbreviate") and AbbreviateNumbers then
    local okAbbr, str = pcall(AbbreviateNumbers, absorb)
    if okAbbr and str then
      return pcall(fontString.SetText, fontString, str)
    end
  end

  return pcall(fontString.SetText, fontString, absorb)
end

-- Montant d'armure accorde par un buff (Fer-poil / Ironfur 192081).
-- Pourquoi l'infobulle et pas AuraData.points : points est secret en combat, et surtout
-- il ne porte que la valeur d'UNE application -- l'infobulle, elle, affiche le total
-- courant, stacks compris, qui est ce qu'on veut montrer.
-- Le parsing prend le PLUS GRAND nombre de l'infobulle : les autres nombres qu'on peut y
-- croiser (stacks, secondes restantes) sont d'un ordre de grandeur bien inferieur a un
-- montant d'armure. Tolerant aux separateurs de milliers selon la locale
-- (espace, espace insecable, virgule, point).
local function ApplyArmorToText(fontString, spellID)
  -- instID par la CDM d'abord : GetPlayerAuraBySpellID echoue pour beaucoup d'auras en
  -- combat, et un echec ici ne doit PAS court-circuiter le repli sur les stacks.
  local A = ns.Auras
  local cdmPlayer = A and A.cdmData and A.cdmData.player
  local cdmEntry  = cdmPlayer and cdmPlayer[spellID]
  local instID    = cdmEntry and cdmEntry.instID
  if not instID then
    local okA, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if okA and data then instID = data.auraInstanceID end
  end

  if instID and C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID then
    local okT, tip = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", instID)
    if okT and tip and tip.lines then
      local best
      for _, line in ipairs(tip.lines) do
        local txt = line and line.leftText
        if type(txt) == "string" then
          for raw in string.gmatch(txt, "%d[%d%s\194\160%.,]*") do
            local n = tonumber((string.gsub(raw, "[%s\194\160%.,]", "")))
            if n and (not best or n > best) then best = n end
          end
        end
      end
      if best then
        -- Meme option "grand nombre" (10000 -> "10k") que le montant d'absorption.
        if ns.GetSecResCfg("secResAbsorbAbbreviate") and AbbreviateNumbers then
          local okAb, str = pcall(AbbreviateNumbers, best)
          if okAb and str then return pcall(fontString.SetText, fontString, str) end
        end
        return pcall(fontString.SetText, fontString, best)
      end
    end
  end

  -- Repli 1 : chaine de stacks normale (fiable hors combat).
  if ApplyStacksToText and ApplyStacksToText(fontString, spellID) then return true end

  -- Repli 2 : derniere valeur du canal clone-stack. En combat c'est la seule qui passe,
  -- GetAuraApplicationDisplayCount etant refuse a un appelant taint. Valeur possiblement
  -- secrete : relayee brute a SetText, jamais comparee.
  local A2 = ns.Auras
  if A2 and A2.GetCDMLastApplications then
    local appl = A2.GetCDMLastApplications(spellID)
    if appl ~= nil then return pcall(fontString.SetText, fontString, appl) end
  end
  return false
end

function ResourceCircle.UpdateSecondaryResource()
  if not bar or not bar.secResText then return end
  if previewMode then return end  -- ne pas écraser la valeur factice affichée par SetPreview
  -- Le texte secondaire doit partager la visibilité du cercle central : secResFrame est parenté à UIParent (pas à bar, pour ses animations de pop indépendantes), donc ne suit pas bar:Hide() automatiquement.
  if not bar:IsShown() then
    if _secResWasApplied or bar.secResText:IsShown() then
      SetSecResShown(false)
      if bar.secResFrame then bar.secResFrame:Hide() end
      _secResWasApplied = false
    end
    return
  end
  if not secResDef then
    -- Le stagger Brewmaster peut utiliser secResText indépendamment : ne pas le masquer dans ce cas
    if not staggerActive then SetSecResShown(false) end
    return
  end

  if secResDef.useStacks and secResDef.spellID then
    -- Alt aura (ex: Fragments de vide sous Métamorphose du vide)
    local applied = false
    if secResDef.altSpellID then
      applied = ApplyStacksToText(bar.secResText, secResDef.altSpellID)
    end
    -- Aura stackable classique (fallback si pas d'alt aura active)
    if not applied then
      applied = ApplyStacksToText(bar.secResText, secResDef.spellID)
    end
    -- Repli compteur bouton d'action (ex: Thé de Mana 115294), uniquement si explicitement défini pour ce spec (cf. ApplyCastCountToText).
    if not applied and secResDef.castCountSpellID then
      applied = ApplyCastCountToText(bar.secResText, secResDef.castCountSpellID)
    end
    -- Repli Démonologie : l'aura 264173 est illisible en combat si le CDM ne la suit pas ; le glow de Démonbolt
    -- (demonicCoreOverlayActive) prouve qu'au moins un Cœur Démoniaque est actif -> affiche "1" faute de mieux.
    if not applied and secResDef.glowFallback and demonicCoreOverlayActive then
      applied = pcall(bar.secResText.SetText, bar.secResText, 1)
    end
    -- Repli présence via IsCDMAuraSwipePresent (même signal que ApplyAbsorbToText) quand les 3 tiers de ApplyStacksToText échouent (ex Bouclier d'os/195181) ; le texte est déjà poussé par le clone-stack.
    local A = ns.Auras
    if not applied and A and A.IsCDMAuraSwipePresent
       and (A.IsCDMAuraSwipePresent(secResDef.spellID)
            or (secResDef.altSpellID and A.IsCDMAuraSwipePresent(secResDef.altSpellID))) then
      applied = true
    end
    -- Transitions 0 <-> 1+ stack en combat : petit pop fade+slide, cf. StartSecResPop/StartSecResPopOut. `applied` est un simple booléen, jamais la valeur secrète.
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    -- Le pop-out cache lui-même texte/déco une fois le fondu terminé ; SetSecResShown(false) immédiat ne s'applique que si aucun pop-out n'est en cours.
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif (secResDef.useItemCount and secResDef.itemID) or secResDef.useAmmo then
    -- Forever : ressource materialisee par un objet des sacs (fragments d'ame, 6265) ou par les munitions
    -- equipees du chasseur (emplacement de munitions). Le compte d'objets n'est jamais secret : texte
    -- pose directement, pop-in/out comme les autres.
    local count
    if secResDef.useAmmo then
      count = (GetInventoryItemCount and GetInventoryItemCount("player", 0)) or 0
    else
      count = C_Item.GetItemCount(secResDef.itemID) or 0
    end
    local applied = count > 0
    if applied then
      bar.secResText:SetText(count)
      if secResDef.useAmmo then
        -- Couleur selon la quantite : Normal >= seuil haut, Critique < seuil bas, Alerte entre les deux
        local sid = ResolveSpecID()
        local hi  = ns.GetSecResCfg("ammoThresholdHigh", sid) or 200
        local lo  = ns.GetSecResCfg("ammoThresholdLow", sid) or 50
        local c
        if count >= hi then
          c = ns.GetSecResCfg("ammoColorNormal", sid) or { 1, 1, 1, 1 }
        elseif count < lo then
          c = ns.GetSecResCfg("ammoColorCritical", sid) or { 1, 0.2, 0.2, 1 }
        else
          c = ns.GetSecResCfg("ammoColorAlert", sid) or { 1, 0.6, 0.1, 1 }
        end
        bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
      end
    end
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif secResDef.useTargetDebuff and secResDef.spellID then
    -- Debuff de la cible (Mage Givre/specID 64, Config/ResourceMap.lua) -- même logique de pop-in/pop-out que useStacks, via ApplyTargetStacksToText.
    local applied = ApplyTargetStacksToText(bar.secResText, secResDef.spellID)
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif (secResDef.useAbsorb or secResDef.useArmor) and secResDef.spellID then
    -- Montant d'absorption restant (Dur Au Mal) ou d'armure accordee (Fer-poil) :
    -- meme traitement ensuite (couleur suivie sur l'arc, pop, show/hide).
    -- if/else explicite et pas `a and f() or g()` : f() renvoie false en cas d'echec,
    -- ce qui ferait retomber sur g() -- donc afficher une absorption pour le Fer-poil.
    local applied
    if secResDef.useArmor then
      applied = ApplyArmorToText(bar.secResText, secResDef.spellID)
      -- Le canal clone-stack pousse le compteur directement dans le FontString : si
      -- l'aura est la, le texte est a jour meme quand nos lectures echouent (combat).
      -- Sans ce repli de PRESENCE, `applied` restait faux et on masquait un texte
      -- pourtant correctement rempli.
      if not applied then
        local A3 = ns.Auras
        if A3 and A3.IsCDMAuraSwipePresent and A3.IsCDMAuraSwipePresent(secResDef.spellID) then
          applied = true
        end
      end
    else
      applied = ApplyAbsorbToText(bar.secResText, secResDef.spellID)
    end
    -- Recale la couleur à chaque tick sur celle de l'arc de durée (reflète en
    -- direct un changement de couleur via le color picker du panneau options).
    local c = GetDurationArcColor(ns._specID) or secResDef.color
    if c then bar.secResText:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
    if applied and not _secResWasApplied then
      StartSecResPop()
    elseif not applied and _secResWasApplied then
      StartSecResPopOut()
    end
    _secResWasApplied = applied
    if applied then
      SetSecResShown(true)
    elseif not _secResPopTicker then
      SetSecResShown(false)
    end
    return
  elseif secResDef.useCharges and secResDef.spellID then
    -- Sort à charges : lecture via C_Spell.GetSpellCharges
    local count = nil
    local ok, info = pcall(C_Spell.GetSpellCharges, secResDef.spellID)
    if ok and info then
      count = tonumber(tostring(info.currentCharges))
    end
    if count and count > 0 then
      bar.secResText:SetText(tostring(count))
      SetSecResShown(true)
    else
      SetSecResShown(false)
    end
    return
  end

  SetSecResShown(false)
end

-- Arc de stagger (Moine Brasseur specID 268)
function ResourceCircle.DetectStagger()
  if not bar then return end
  staggerActive = false
  if staggerUpdateTicker then staggerUpdateTicker:Cancel(); staggerUpdateTicker = nil end
  if _arcOverlayTickers.stagger then _arcOverlayTickers.stagger:Cancel(); _arcOverlayTickers.stagger = nil end
  if bar.staggerArc          then bar.staggerArc:Hide() end
  if bar.staggerOverlayFrame then bar.staggerOverlayFrame:Hide() end
  if not secResDef then
    SetSecResShown(false)
    if bar.secResFrame then bar.secResFrame:Hide() end
  end
  if ResolveSpecID() == 268 then  -- Brewmaster Monk
    staggerActive = true
    staggerUpdateTicker = C_Timer.NewTicker(0.1, function()
      ResourceCircle.UpdateStagger()
    end)
  end
end

function ResourceCircle.UpdateStagger()
  if not bar or not staggerActive or previewMode then return end
  -- Cercle central caché : masquer le texte de stagger en même temps, sinon il restait bloqué affiché à "0%" hors combat.
  if not bar:IsShown() then
    if bar.secResFrame and bar.secResFrame:IsShown() then
      SetSecResShown(false)
      bar.secResFrame:Hide()
    end
    return
  end
  if not bar.staggerArc or not bar.staggerArc:IsShown() then return end
  local ok1, stagAmt = pcall(UnitStagger, "player")
  local ok2, maxHP   = pcall(UnitHealthMax, "player")
  if not ok1 or not ok2 or not maxHP or maxHP <= 0 then return end

  -- Arithmétique protégée séparément de l'appel API : stagAmt peut être secret en combat, une division non protégée plante silencieusement toute la fonction (le ticker avale l'erreur).
  local okPct, pct = pcall(function() return ((stagAmt or 0) / maxHP) * 100 end)
  if not okPct or pct == nil then return end

  local okC1, isLight    = pcall(function() return pct < 30 end)
  local okC2, isModerate = pcall(function() return pct < 60 end)
  local color = (okC1 and isLight and STAGGER_LIGHT)
    or (okC2 and isModerate and STAGGER_MODERATE)
    or STAGGER_HEAVY
  bar.staggerArc:SetStatusBarColor(color[1], color[2], color[3], 1)
  local okClamp, clamped = pcall(function() return math.min(pct, 100) end)
  ns.SmoothSetValue(bar.staggerArc, okClamp and clamped or pct)

  -- Affichage optionnel du % sous le texte de ressource (même slot que DH Dévoreur)
  if bar.secResText and bar.secResFrame and not secResDef then
    local cfg = ns.GetCfg("resourceCircle")
    if cfg.staggerShowPercent then
      -- Pourcentage (pas un stack) : pas de tirets décoratifs ici.
      bar.secResFrame:Show()
      local okFmt, txt = pcall(string.format, "%.1f%%", pct)
      if okFmt then bar.secResText:SetText(txt) end
      bar.secResText:SetTextColor(color[1], color[2], color[3], 1)
      bar.secResText:Show()
      if bar.secResDashL then bar.secResDashL:Hide() end
      if bar.secResDashR then bar.secResDashR:Hide() end
    else
      SetSecResShown(false)
      bar.secResFrame:Hide()
    end
  end
end

-- Arc de durée dans le cercle central. SetCenterArcEntry(entry) : appelé par CenterArc.lua avec entry.durObj/entry.spellColor. SetTimerDuration anime à 60fps côté Blizzard.
local INTERP_IMMED = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local TIMER_DRAIN  = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
local _lastArcDurRef = nil  -- tostring(durObj) : change à chaque cast/refresh

-- Arc de duree dont l'etendue est < 360 deg : SetTimerDuration impose sa propre plage (l'etendue est alors ignoree), on
-- pilote donc la barre a la main avec le pourcentage restant du durObj (valeur possiblement secrete, jamais lue).
local arcDriver, _arcTimerOn
local _arcDriverOn = false   -- pilotage manuel actif : le canal clone-bar (proxy) ne doit alors plus ecrire dans l'arc
local function StopArcDriver()
  _arcDriverOn = false
  if arcDriver then arcDriver:SetScript("OnUpdate", nil) end
end
local function StartArcDriver(durObj)
  local curve = CurveConstants and CurveConstants.ScaleTo100
  if not (curve and durObj and durObj.EvaluateRemainingPercent) then return false end
  if not pcall(durObj.EvaluateRemainingPercent, durObj, curve) then return false end
  local arc = bar.durationArc
  arc:SetMinMaxValues(0, 100)
  if not arcDriver then arcDriver = CreateFrame("Frame") end
  arcDriver:SetScript("OnUpdate", function()
    local ok, v = pcall(durObj.EvaluateRemainingPercent, durObj, curve)
    if ok then pcall(arc.SetValue, arc, v) end
  end)
  _arcDriverOn = true
  return true
end

-- Affichage de l'arc de duree. Cercle visible + nouvel arc : entree animee ; deja affiche : rien a refaire (une animation
-- en cours ne doit pas etre ecrasee par les mises a jour de valeur). Cercle masque : on note juste qu'il y a du contenu,
-- l'animation d'apparition du cercle (AnimateArcOverlay) le fera entrer au bon moment.
-- Rapproche l'etat affiche (durShown) de l'etat voulu (durArcWanted), une animation a la fois : si une entree/sortie est en
-- cours, la suivante attend sa fin (sinon l'arc reprenait a mi-course, deforme, quand un proc le refaisait apparaitre).
local function DurArcReconcile()
  if durBusy or durArcWanted == durShown then return end
  if lastVisibilityState ~= true or not bar:IsShown() then return end
  RunDurAnim(durArcWanted, true)
end

RunDurAnim = function(show, live)
  local el = DurArcEl()
  if not (el and bar.durationOvlFrame) then return end
  durBusy = true
  AnimateArcOverlayPair("duration", show, el, bar.durationOvlFrame, bar.durationOvl,
    live and "durationArcLive" or "durationArc", live and "durationArcOverlayLive" or "durationArcOverlay",
    function()
      durBusy = false
      durShown = show
      DurArcReconcile()
    end)
end

-- Affichage de l'arc de duree. Cercle masque : on note juste qu'il y a du contenu, l'animation d'apparition du cercle
-- (AnimateArcOverlay) le fera entrer au bon moment.
local function DurArcShow()
  durArcWanted = true
  DurArcReconcile()
end

local function DurArcHide()
  if not durArcWanted then return end   -- deja masque (ou sortie en cours) : les appels repetes ne relancent rien
  durArcWanted = false
  if lastVisibilityState == true and bar:IsShown() and durShown then
    DurArcReconcile()
  else
    if _arcOverlayTickers.duration then _arcOverlayTickers.duration:Cancel(); _arcOverlayTickers.duration = nil end
    durBusy, durShown = false, false
    local el = DurArcEl()
    el:SetValue(0); el:Hide()
    if bar.durationOvlFrame then bar.durationOvlFrame:Hide() end
  end
end

-- Bascule entre la barre radiale (durObj, valeur, stacks) et la barre verticale (canal clone-bar) : l'autre est masquee.
local function SetDurArcMode(vertical)
  if durArcVert == vertical then return end
  if _arcOverlayTickers.duration then _arcOverlayTickers.duration:Cancel(); _arcOverlayTickers.duration = nil end
  durBusy, durShown = false, false
  local old = DurArcEl()
  durArcVert = vertical
  old:SetValue(0); old:Hide()
  durArcWanted = false   -- la prochaine apparition rejoue l'entree animee sur le nouvel element
end

function ResourceCircle.SetCenterArcEntry(entry)
  if not bar or not bar.durationArc or previewDurShown then return end
  if entry and entry.durObj then
    -- Le durObj est recréé à chaque cast (même refresh) → tostring() change toujours ; SetTimerDuration ne tourne que pour un nouveau durObj.
    local durRef = tostring(entry.durObj)
    if durRef == _lastArcDurRef then return end
    _lastArcDurRef = durRef
    SetDurArcMode(false)
    local color = entry.spellColor
    if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
    bar.durationArc:SetMinMaxValues(0, 1)
    StopArcDriver()
    local driven = (bar.durationArc._k or 1) ~= 1 and StartArcDriver(entry.durObj)
    if driven then
      if _arcTimerOn then
        _arcTimerOn = false
        if bar.durationArc.SetTimerDuration then pcall(bar.durationArc.SetTimerDuration, bar.durationArc, nil) end
      end
    elseif bar.durationArc.SetTimerDuration and INTERP_IMMED and TIMER_DRAIN then
      _arcTimerOn = true
      pcall(bar.durationArc.SetTimerDuration, bar.durationArc, entry.durObj, INTERP_IMMED, TIMER_DRAIN)
    end
    DurArcShow()
  else
    -- Chemin CDM : SetTimerDuration(nil) uniquement si on avait un durObj actif, sinon ça peut corrompre l'état de la StatusBar.
    StopArcDriver()
    if _lastArcDurRef then
      _lastArcDurRef = nil
      if _arcTimerOn and bar.durationArc.SetTimerDuration then
        pcall(bar.durationArc.SetTimerDuration, bar.durationArc, nil)
      end
      _arcTimerOn = false
    end
    -- Toujours cacher l'arc visuellement (couvre chemin totem + chemin CDM).
    DurArcHide()
  end
end

-- Cas totem (Consécration) : pas de durObj, ticker manuel à 60fps côté CenterArc
function ResourceCircle.SetCenterArcColor(color)
  if not bar or not bar.durationArc then return end
  if color then
    bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1)
    if bar.durationArcV then bar.durationArcV:SetStatusBarColor(color[1], color[2], color[3], 1) end
  end
end

function ResourceCircle.SetCenterArcValue(fraction, color)
  if not bar or not bar.durationArc or previewDurShown then return end
  SetDurArcMode(false)
  StopArcDriver()
  if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
  bar.durationArc:SetMinMaxValues(0, 1)
  ns.SmoothSetValue(bar.durationArc, math.max(0, math.min(1, fraction)))
  DurArcShow()
end

-- Mode "absorb" de l'arc de durée (Dur Au Mal, cfg.ignorePainArcAbsorb) : remplissage proportionnel à une valeur/max génériques plutôt qu'au temps restant. `value` peut être secret : aucune arithmétique, passé brut à SetValue (même pattern que UpdateAbsorb dans UnitBars.lua).
function ResourceCircle.SetCenterArcFill(value, maxValue, color)
  if not bar or not bar.durationArc or previewDurShown then return end
  SetDurArcMode(false)
  StopArcDriver()
  if not maxValue or maxValue <= 0 then return end
  if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
  bar.durationArc:SetMinMaxValues(0, maxValue)
  ns.SmoothSetValue(bar.durationArc, value)
  DurArcShow()
end

-- Mode "cdmbar" (durée combat-safe, CDMHooks.lua) : relais brut vers bar.durationArc, sans comparaison sur lo/hi/value (hi peut être secret en combat), sauf hi==0 (envoyé en clair à l'expiration du buff).
function ResourceCircle.SetCenterArcBarMinMax(lo, hi)
  if not bar or not bar.durationArcV or previewDurShown then return end
  SetDurArcMode(true)
  StopArcDriver()
  local okZero, isZero = pcall(function() return hi == 0 end)
  if okZero and isZero then
    DurArcHide()
    return
  end
  pcall(bar.durationArcV.SetMinMaxValues, bar.durationArcV, lo, hi)
  DurArcShow()
end

function ResourceCircle.SetCenterArcBarValue(value)
  if not bar or not bar.durationArcV or previewDurShown then return end
  pcall(bar.durationArcV.SetValue, bar.durationArcV, value)
end

-- Proxy "clone-bar" : expose l'interface StatusBar attendue par ns.SubscribeCDMAuraBar sans être une vraie StatusBar, redirige vers bar.durationArc (ResourceCircle garde la main sur son widget).
ResourceCircle.centerArcBarProxy = {
  SetMinMaxValues = function(_, lo, hi) ResourceCircle.SetCenterArcBarMinMax(lo, hi) end,
  SetValue        = function(_, value) ResourceCircle.SetCenterArcBarValue(value) end,
  Show            = function() end,
}

-- Remplit l'arc secondaire central depuis une aura stackable, en réutilisant la même chaîne CDM + fallbacks que le texte de ressource secondaire (specs à arc "stacks" lues via une aura, ex DH Dévoreur).
function ResourceCircle.ApplyStacksToCenterArc(spellID, maxValue, color, dbg)
  if not bar or not bar.durationArc or previewDurShown then return false end
  if not maxValue or maxValue <= 0 then return false end
  SetDurArcMode(false)
  -- SetMinMaxValues doit preceder SetValue, mais rien ne garantit que les stacks
  -- s'appliqueront : on memorise la plage courante pour la restaurer en cas d'echec.
  -- Sans ca, un simple appel exploratoire (ex. la sonde de /rcarc) reglait l'arc sur
  -- la plage demandee et le laissait fausse -- il sautait a 100% en mode absorb.
  local okPrev, prevMin, prevMax = true, bar.durationArc._ulo or 0, bar.durationArc._uhi or 1
  bar.durationArc:SetMinMaxValues(0, maxValue)
  local applied = ApplyStacksTo(function(v)
    return pcall(ns.SmoothSetValue, bar.durationArc, v)
  end, spellID, dbg)
  -- Repli combat : le canal clone-stack garde la derniere valeur vue, la ou
  -- GetAuraApplicationDisplayCount (utilise par ApplyStacksTo) est refuse a un appelant
  -- taint. Valeur possiblement secrete : passee brute a SetValue, jamais comparee.
  if not applied then
    local A2 = ns.Auras
    local appl = A2 and A2.GetCDMLastApplications and A2.GetCDMLastApplications(spellID)
    if appl ~= nil then
      applied = pcall(ns.SmoothSetValue, bar.durationArc, appl)
    end
  end
  if not applied and okPrev then
    pcall(bar.durationArc.SetMinMaxValues, bar.durationArc, prevMin, prevMax)
  end
  if applied then
    if color then bar.durationArc:SetStatusBarColor(color[1], color[2], color[3], 1) end
    DurArcShow()
  end
  return applied
end

-- Accesseur debug (/rcarc dans CenterArc.lua) : bar.durationArc/durationArcFrame sont locaux à ce fichier.
function ResourceCircle._debug_GetDurationArc()
  return bar and bar.durationArc, bar and bar.durationArcFrame
end

-- Frame d'animation slide pour les secondary dots (même logique que Skyriding)
function ResourceCircle.CreateSecAnimFrame()
  if secAnimFrame then return end
  secAnimFrame = CreateFrame("Frame")
  secAnimFrame:SetScript("OnUpdate", function(_, dt)
    if secDotCount == 0 or not bar then return end
    for i = 1, secDotCount do
      local oa = secDotAnims[i]
      local f  = secDots[i]
      if not (oa and f) then break end

      -- Avancer l'animation slide
      if oa.progress ~= oa.target then
        local dir = oa.target > oa.progress and 1 or -1
        oa.progress = math.max(0.0, math.min(1.0, oa.progress + dir * SEC_SLIDE_SPEED * dt))
      end

      local t = oa.progress
      if t <= 0 then
        if f:IsShown() then f:Hide() end
      else
        if not f:IsShown() then f:Show() end
        -- ease-circ-out : démarre vite, amorti à l'arrivée (même courbe Skyriding)
        local eased = (t >= 1.0) and 1.0 or math.sqrt(1.0 - (1.0 - t) * (1.0 - t))
        -- Slide : part de SEC_SLIDE_SCALE × position cible vers la position finale
        local k = 1.0 + (SEC_SLIDE_SCALE - 1.0) * (1.0 - eased)
        if f._homeX then
          f:ClearAllPoints()
          f:SetPoint("CENTER", bar, "CENTER", f._homeX * k, f._homeY * k)
        end
        f:SetAlpha(eased)
      end
    end
  end)
end
-- Debug : /rcoverlay — log tous les spell overlay events en temps réel
do
  local logging = false
  local logFrame = CreateFrame("Frame")
  logFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
  logFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
  logFrame:SetScript("OnEvent", function(_, event, spellID)
    if not logging then return end
    local tag = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and "|cff00ff00SHOW|r" or "|cffff4444HIDE|r"
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[RCOverlay]|r " .. tag .. " spellID=" .. tostring(spellID))
  end)
  SLASH_RCOVERLAY1 = "/rcoverlay"
  SlashCmdList["RCOVERLAY"] = function()
    logging = not logging
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[RCOverlay]|r logging " .. (logging and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
  end
end

-- /rcanimlog -- trace en direct UpdateVisibility et AnimateArcOverlayPair pour recouper avec /aishdebug sky (Skyriding.lua, mêmes horodatages GetTime()).
SLASH_RCANIMLOG1 = "/rcanimlog"
SlashCmdList["RCANIMLOG"] = function()
  ns._rcAnimDebug = not ns._rcAnimDebug
  DEFAULT_CHAT_FRAME:AddMessage("|cff88ffff[RCAnim]|r logging " .. (ns._rcAnimDebug and "|cff00ff00ON|r" or "|cffff4444OFF|r")
    .. " -- reproduire (atterrir + combat), puis /aishdebug sky pour la sequence Skyriding correspondante.")
end

-- Debug : dump complet de l'état de bar.arc, appelable à tout moment.
SLASH_RCARCDBG1 = "/rcarcdbg"
SlashCmdList["RCARCDBG"] = function()
  if not bar then print("[AishDbg] bar est nil"); return end
  if not bar.arc then print("[AishDbg] bar.arc est nil"); return end
  local a = bar.arc
  print(string.format("[AishDbg] bar: IsShown=%s IsVisible=%s Alpha=%.2f",
    tostring(bar:IsShown()), tostring(bar:IsVisible()), bar:GetAlpha()))
  print(string.format("[AishDbg] arc: IsShown=%s IsVisible=%s Alpha=%.2f Scale=%.3f",
    tostring(a:IsShown()), tostring(a:IsVisible()), a:GetAlpha(), a:GetScale()))
  local w, h = a:GetSize()
  print(string.format("[AishDbg] arc: Size=%.1fx%.1f FrameLevel=%s Strata=%s",
    w or -1, h or -1, tostring(a:GetFrameLevel()), tostring(a:GetFrameStrata())))
  local pt, relTo, relPt, x, y = a:GetPoint(1)
  print(string.format("[AishDbg] arc: Point=%s relTo=%s relPt=%s x=%s y=%s",
    tostring(pt), (relTo and relTo.GetName and relTo:GetName()) or tostring(relTo), tostring(relPt), tostring(x), tostring(y)))
  local okV, val = pcall(a.GetValue, a)
  local okMM, lo, hi = pcall(a.GetMinMaxValues, a)
  print(string.format("[AishDbg] arc: GetValue ok=%s val=%s | GetMinMax ok=%s lo=%s hi=%s",
    tostring(okV), tostring(val), tostring(okMM), tostring(lo), tostring(hi)))
  local okC, r, g, b, cAlpha = pcall(a.GetStatusBarColor, a)
  print(string.format("[AishDbg] arc: StatusBarColor ok=%s r=%s g=%s b=%s a=%s",
    tostring(okC), tostring(r), tostring(g), tostring(b), tostring(cAlpha)))
  local tex = a.GetStatusBarTexture and a:GetStatusBarTexture()
  if tex then
    local tw, th = tex:GetSize()
    print(string.format("[AishDbg] arc: tex IsShown=%s Alpha=%.2f Size=%.1fx%.1f Texture=%s",
      tostring(tex:IsShown()), tex:GetAlpha(), tw or -1, th or -1, tostring(tex:GetTexture())))
    local tpt, trelTo, trelPt, tx, ty = tex:GetPoint(1)
    print(string.format("[AishDbg] arc: tex Point=%s relTo=%s relPt=%s x=%s y=%s",
      tostring(tpt), (trelTo and trelTo.GetName and trelTo:GetName()) or tostring(trelTo), tostring(trelPt), tostring(tx), tostring(ty)))
  else
    print("[AishDbg] arc: GetStatusBarTexture() a échoué ou renvoyé nil")
  end
  if bar.overlayFrame then
    local of = bar.overlayFrame
    print(string.format("[AishDbg] overlayFrame: IsShown=%s IsVisible=%s Alpha=%.2f Scale=%.3f FrameLevel=%s",
      tostring(of:IsShown()), tostring(of:IsVisible()), of:GetAlpha(), of:GetScale(), tostring(of:GetFrameLevel())))
  end
  if bar.overlay then
    local ov = bar.overlay
    local ow, oh = ov:GetSize()
    local ovr, ovg, ovb, ova = ov:GetVertexColor()
    print(string.format("[AishDbg] overlay: IsShown=%s Alpha=%.2f Scale=%.3f Size=%.1fx%.1f VertexColor=%.2f,%.2f,%.2f,%.2f",
      tostring(ov:IsShown()), ov:GetAlpha(), ov:GetScale(), ow or -1, oh or -1, ovr or -1, ovg or -1, ovb or -1, ova or -1))
    local opt, orelTo, orelPt, ox, oy = ov:GetPoint(1)
    print(string.format("[AishDbg] overlay: Point=%s relTo=%s relPt=%s x=%s y=%s",
      tostring(opt), (orelTo and orelTo.GetName and orelTo:GetName()) or tostring(orelTo), tostring(orelPt), tostring(ox), tostring(oy)))
  end
end

-- Debug : /rcaura — dump toutes les auras HELPFUL du joueur
SLASH_RCAURA1 = "/rcaura"
SlashCmdList["RCAURA"] = function()
  local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCAura]|r " .. tostring(msg)) end
  p("=== HELPFUL auras ===")
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    p("GetPlayerAuraBySpellID(369299) = " .. tostring(C_UnitAuras.GetPlayerAuraBySpellID(369299) ~= nil))
  end
  local found = 0
  for idx = 1, 60 do
    local ok, name, _, count, _, _, _, _, _, _, spellID = pcall(UnitAura, "player", idx, "HELPFUL")
    if not ok or not name then break end
    found = found + 1
    p(string.format("  [%d] spellID=%-8d stacks=%-2d  %s", idx, spellID or 0, count or 0, name or "?"))
  end
  if found == 0 then p("  (aucune aura HELPFUL)") end
end

-- Debug : /rcsecres — état complet du texte de ressource secondaire
SLASH_RCSECRES1 = "/rcsecres"
SlashCmdList["RCSECRES"] = function()
  local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCSecRes]|r " .. tostring(msg)) end
  if not bar then p("bar est nil"); return end
  p(string.format("InCombatLockdown=%s", tostring(InCombatLockdown and InCombatLockdown())))
  p(string.format("bar: IsShown=%s", tostring(bar:IsShown())))
  p(string.format("ShouldShow()=%s  lastVisibilityState=%s",
    tostring(ResourceCircle.ShouldShow()), tostring(lastVisibilityState)))
  local idx = GetSpecialization and GetSpecialization()
  local specID = idx and GetSpecializationInfo and select(1, pcall(GetSpecializationInfo, idx))
  local okSpec, sid = pcall(GetSpecializationInfo, idx or 0)
  p(string.format("GetSpecialization idx=%s specID(ok=%s)=%s", tostring(idx), tostring(okSpec), tostring(sid)))
  p(string.format("ns._specID=%s  ResolveSpecID()=%s", tostring(ns._specID), tostring(ResolveSpecID and ResolveSpecID())))

  -- --- Barre de duree (deux moities miroir) ---------------------------------
  do
    local liveSpec = (ResolveSpecID and ResolveSpecID()) or ns._specID
    local entry = SEC_RES_DUR_BAR_SPELLS[liveSpec or 0]
    p(string.format("durBar: spe=%s  sort attendu=%s  option=%s",
      tostring(liveSpec), tostring(entry and entry.spellID),
      tostring(ns.GetSecResCfg("secResDurBarEnabled", liveSpec))))
    p(string.format("durBar: pilote arme=%s (spellID=%s, spec=%s)  ticker=%s",
      tostring(_secResDurInfo ~= nil), tostring(_secResDurInfo and _secResDurInfo.spellID),
      tostring(_secResDurSpecID), tostring(_secResDurTicker ~= nil)))
    if _secResDurInfo then
      local A = ns.Auras
      local cdmOk = A and A.IsCDMAuraBarPresent and A.IsCDMAuraBarPresent(_secResDurInfo.spellID)
      p(string.format("durBar: canal CDM present=%s (sinon repli GetPlayerAuraBySpellID)", tostring(cdmOk)))
      local okA, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, _secResDurInfo.spellID)
      p(string.format("durBar: aura lisible=%s  duration=%s", tostring(okA and data ~= nil),
        tostring(okA and data and data.duration)))
      -- Source principale en combat. On distingue les DEUX origines : le pipeline
      -- (ns.Auras.auraData, celui qui fait marcher les barres de cercle) et l'API
      -- directe (qui echoue en combat depuis ce contexte taint).
      local instID   = SecResDurAuraInstID(_secResDurInfo.spellID)
      local fromData = SecResDurFindDurObj(_secResDurInfo.spellID)
      local fromAPI
      if instID and SRD_GetAuraDuration then
        local okD, d = pcall(SRD_GetAuraDuration, "player", instID)
        fromAPI = okD and d or nil
      end
      p(string.format("durBar: instID=%s  durObj pipeline=%s  durObj API=%s  timer arme=%s  SetTimerDuration dispo=%s",
        tostring(instID), tostring(fromData ~= nil), tostring(fromAPI ~= nil),
        tostring(_secResDurLastRef ~= nil),
        tostring(bar.secResDurL and bar.secResDurL.SetTimerDuration ~= nil)))
      -- Ou le sort apparait-il dans le pipeline, et avec ou sans durObj ?
      local A2 = ns.Auras
      if A2 and A2.auraData then
        for dest, list in pairs(A2.auraData) do
          if type(list) == "table" then
            for i = 1, #list do
              local e = list[i]
              if e and e.spellID == _secResDurInfo.spellID then
                p(string.format("   auraData[%s][%d] : durObj=%s directDuration=%s",
                  tostring(dest), i, tostring(e.durObj ~= nil), tostring(e.directDuration)))
              end
            end
          end
        end
      else
        p("   ns.Auras.auraData absent")
      end
    end
    if bar.secResDurL then
      p(string.format("durBar L: IsShown=%s Alpha=%.2f Taille=%.0fx%.0f",
        tostring(bar.secResDurL:IsShown()), bar.secResDurL:GetAlpha(),
        bar.secResDurL:GetWidth(), bar.secResDurL:GetHeight()))
    else
      p("durBar: les moities n'existent pas (bar.secResDurL nil)")
    end
  end
  if secResDef then
    p(string.format("secResDef: spellID=%s useStacks=%s useAbsorb=%s useCharges=%s useTargetDebuff=%s altSpellID=%s",
      tostring(secResDef.spellID), tostring(secResDef.useStacks), tostring(secResDef.useAbsorb), tostring(secResDef.useCharges), tostring(secResDef.useTargetDebuff), tostring(secResDef.altSpellID)))
  else
    p("secResDef est nil")
  end
  if bar.secResFrame then
    p(string.format("secResFrame: IsShown=%s IsVisible=%s Alpha=%.2f FrameLevel=%s Strata=%s",
      tostring(bar.secResFrame:IsShown()), tostring(bar.secResFrame:IsVisible()),
      bar.secResFrame:GetAlpha(), tostring(bar.secResFrame:GetFrameLevel()), tostring(bar.secResFrame:GetFrameStrata())))
  else
    p("bar.secResFrame est nil")
  end
  if bar.secResText then
    p(string.format("secResText: IsShown=%s Alpha=%.2f Text=%q",
      tostring(bar.secResText:IsShown()), bar.secResText:GetAlpha(), tostring(bar.secResText:GetText())))
  else
    p("bar.secResText est nil")
  end
  if secResDef and secResDef.spellID and not secResDef.useTargetDebuff then
    local A = ns.Auras
    p(string.format("ns.Auras présent=%s  cdmData.player présent=%s",
      tostring(A ~= nil), tostring(A and A.cdmData and A.cdmData.player ~= nil)))
    local cdmPlayer = A and A.cdmData and A.cdmData.player
    local cdmEntry = cdmPlayer and cdmPlayer[secResDef.spellID]
    local foundInstID = cdmEntry and cdmEntry.instID
    p(string.format("cdmData: instID pour spellID %d = %s", secResDef.spellID, tostring(foundInstID)))
    if foundInstID then
      local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", foundInstID)
      p(string.format("GetAuraDataByAuraInstanceID ok=%s aura=%s", tostring(ok), tostring(aura ~= nil)))
      if ok and aura then
        -- Pas de lecture de aura.applications/aura.points ici : indexer un champ secret jette une erreur qui tainte le reste de la fonction.
        local okD1, dispD1 = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, foundInstID, 1, 999)
        p(string.format("GetAuraApplicationDisplayCount(1,999) ok=%s value=%s type=%s", tostring(okD1), tostring(dispD1), type(dispD1)))
      end
    end
    -- altSpellID (ex Fragments de vide 1227702, DH Dévoreur) : teste comme UpdateSecondaryResource, en priorité avant le spellID normal.
    if secResDef.altSpellID then
      local altDbg = {}
      local altApplied = ApplyStacksToText(bar.secResText, secResDef.altSpellID, altDbg)
      p(string.format("ApplyStacksToText altSpellID(%d) = %s  path=%s  secResText:GetText() ensuite = %q",
        secResDef.altSpellID, tostring(altApplied), tostring(altDbg.path), tostring(bar.secResText:GetText())))
      if altDbg.cdm then p(string.format("  [alt] cdm: ok=%s disp=%s", tostring(altDbg.cdm.ok), tostring(altDbg.cdm.disp))) end
      if altDbg.f1 then
        p(string.format("  [alt] fallback1(GetPlayerAuraBySpellID): okAura=%s hasAura=%s instID=%s ok2=%s disp2=%s",
          tostring(altDbg.f1.okAura), tostring(altDbg.f1.hasAura), tostring(altDbg.f1.instID), tostring(altDbg.f1.ok2), tostring(altDbg.f1.disp2)))
      end
      if altDbg.f2MatchErrAt then p(string.format("  [alt] fallback2: comparaison d.spellId a echoue (secret) a l'index %d", altDbg.f2MatchErrAt)) end
      if altDbg.f2 then
        p(string.format("  [alt] fallback2(enum HELPFUL): matchedAt=%s okApp=%s disp3=%s okIdx=%s dispIdx=%s",
          tostring(altDbg.f2.matchedAt), tostring(altDbg.f2.okApp), tostring(altDbg.f2.disp3), tostring(altDbg.f2.okIdx), tostring(altDbg.f2.dispIdx)))
      end
    end

    local dbg = {}
    local applied = ApplyStacksToText(bar.secResText, secResDef.spellID, dbg)
    p(string.format("ApplyStacksToText(%d) = %s  path=%s  secResText:GetText() ensuite = %q",
      secResDef.spellID, tostring(applied), tostring(dbg.path), tostring(bar.secResText:GetText())))
    if dbg.cdm then p(string.format("  cdm: ok=%s disp=%s", tostring(dbg.cdm.ok), tostring(dbg.cdm.disp))) end
    if dbg.f1 then
      p(string.format("  fallback1(GetPlayerAuraBySpellID): okAura=%s hasAura=%s instID=%s ok2=%s disp2=%s",
        tostring(dbg.f1.okAura), tostring(dbg.f1.hasAura), tostring(dbg.f1.instID), tostring(dbg.f1.ok2), tostring(dbg.f1.disp2)))
    end
    if dbg.f2MatchErrAt then p(string.format("  fallback2: comparaison d.spellId a echoue (secret) a l'index %d", dbg.f2MatchErrAt)) end
    if dbg.f2 then
      p(string.format("  fallback2(enum HELPFUL): matchedAt=%s okApp=%s disp3=%s okIdx=%s dispIdx=%s",
        tostring(dbg.f2.matchedAt), tostring(dbg.f2.okApp), tostring(dbg.f2.disp3), tostring(dbg.f2.okIdx), tostring(dbg.f2.dispIdx)))
    end
    if not applied and secResDef.castCountSpellID then
      local ccSid = secResDef.castCountSpellID
      local okCC, count = pcall(C_Spell.GetSpellCastCount, ccSid)
      p(string.format("castCountSpellID=%d GetSpellCastCount ok=%s count=%s", ccSid, tostring(okCC), tostring(count)))
      -- Diagnostic du bouton natif (IsActionCountConfirmedHidden), à collecter en combat pour savoir pourquoi le gate IsShown() ne masque pas le "0".
      local PBdbg = ns.Modules and ns.Modules.PriorityBar
      local btnDbg = PBdbg and PBdbg._GetCachedBtn and PBdbg._GetCachedBtn(ccSid)
      p(string.format("  [btn] PriorityBar present=%s _GetCachedBtn=%s btn trouve=%s",
        tostring(PBdbg ~= nil), tostring(PBdbg and PBdbg._GetCachedBtn ~= nil), tostring(btnDbg ~= nil)))
      if btnDbg then
        p(string.format("  [btn] name=%s hasCount=%s", tostring(btnDbg.GetName and btnDbg:GetName()), tostring(btnDbg.Count ~= nil)))
        if btnDbg.Count then
          local okShown, shown = pcall(btnDbg.Count.IsShown, btnDbg.Count)
          local okTxt, txt     = pcall(btnDbg.Count.GetText, btnDbg.Count)
          local okW,   w       = pcall(btnDbg.Count.GetStringWidth, btnDbg.Count)
          local okA,   a       = pcall(btnDbg.Count.GetAlpha, btnDbg.Count)
          p(string.format("  [btn.Count] IsShown ok=%s val=%s | GetText ok=%s val=%s | GetStringWidth ok=%s val=%s | GetAlpha ok=%s val=%s",
            tostring(okShown), tostring(shown), tostring(okTxt), tostring(txt), tostring(okW), tostring(w), tostring(okA), tostring(a)))
        end
      end
      applied = ApplyCastCountToText(bar.secResText, ccSid)
      p(string.format("ApplyCastCountToText(%d) = %s  secResText:GetText() ensuite = %q",
        ccSid, tostring(applied), tostring(bar.secResText:GetText())))
    end
    if applied then SetSecResShown(true) end
  elseif secResDef and secResDef.spellID and secResDef.useTargetDebuff then
    -- Chemin cible (Mage Givre, Config/ResourceMap.lua) : diagnostic séparé du bloc joueur, trompeur ici puisque le debuff n'est jamais sur "player".
    p(string.format("UnitExists(target)=%s", tostring(UnitExists("target"))))
    local A = ns.Auras
    p(string.format("ns.Auras présent=%s  cdmData.target présent=%s",
      tostring(A ~= nil), tostring(A and A.cdmData and A.cdmData.target ~= nil)))
    local cdmTarget = A and A.cdmData and A.cdmData.target
    local cdmEntryT = cdmTarget and cdmTarget[secResDef.spellID]
    local foundInstID = cdmEntryT and cdmEntryT.instID
    p(string.format("cdmData.target: instID pour spellID %d = %s", secResDef.spellID, tostring(foundInstID)))
    if foundInstID then
      local okAura, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "target", foundInstID)
      p(string.format("GetAuraDataByAuraInstanceID(target) ok=%s aura=%s", tostring(okAura), tostring(aura ~= nil)))
    end
    -- Énumération HARMFUL brute de la cible, seulement hors combat (la comparaison spellId plante en combat, cf. ApplyStacksTo).
    if not (InCombatLockdown and InCombatLockdown()) and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local any = false
      for i = 1, 40 do
        local ok3, d = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
        if not ok3 or not d then break end
        any = true
        p(string.format("  [target HARMFUL #%d] spellId=%s name=%s applications=%s",
          i, tostring(d.spellId), tostring(d.name), tostring(d.applications)))
      end
      if not any then p("  (aucun debuff HARMFUL trouvé sur la cible)") end
    else
      p("  (énumération HARMFUL sautée : pas de cible, ou en combat -- spellId y serait secret)")
    end
    local dbg = {}
    local applied = ApplyTargetStacksToText(bar.secResText, secResDef.spellID, dbg)
    p(string.format("ApplyTargetStacksToText(%d) = %s  path=%s  secResText:GetText() ensuite = %q",
      secResDef.spellID, tostring(applied), tostring(dbg.path), tostring(bar.secResText:GetText())))
    if dbg.cdm then
      p(string.format("  cdm: ok=%s okApp=%s disp=%s", tostring(dbg.cdm.ok), tostring(dbg.cdm.okApp), tostring(dbg.cdm.disp)))
    end
    if dbg.f2 then
      p(string.format("  fallback2(enum HARMFUL): matchedAt=%s okApp=%s disp3=%s",
        tostring(dbg.f2.matchedAt), tostring(dbg.f2.okApp), tostring(dbg.f2.disp3)))
    end
    if applied then SetSecResShown(true) end
  end
end
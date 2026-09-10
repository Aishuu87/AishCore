-- Core.lua : Namespace partagé entre tous les fichiers de l'addon
local addonName, ns = ...

-- Table principale de l'addon
ns.addonName    = addonName
ns.addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

-- Références vers les modules (remplies par chaque module)
ns.Modules = {}

-- Référence vers la config (remplie par Defaults.lua)
ns.Defaults = {}
ns.DB = {}  -- sera rempli par la SavedVariable au login

-- Reserve certains reglages (couleurs de cast par ecole, monture Vol Ascendant)
-- aux profils ayant le champ racine kfe2pr_tmtc dans le SavedVariables original.
function ns.HasHeroicFeatures()
  return AishaddonDB ~= nil and AishaddonDB.kfe2pr_tmtc == true
end

-- Marqueur discret sur les screenshots : 2e "." apres le "v" si kfe2pr_tmtc present
function ns.GetVersionString()
  local dots = (ns.HasHeroicFeatures and ns.HasHeroicFeatures()) and ".." or "."
  return "v" .. dots .. tostring(ns.addonVersion or "?")
end

-- Registre d'evenements internes leger (pub/sub)
local CallbackRegistry = {}
CallbackRegistry.events = {}
ns.CallbackRegistry = CallbackRegistry

function CallbackRegistry:Register(event, func, owner)
  if not self.events[event] then self.events[event] = {} end
  table.insert(self.events[event], { func = func, owner = owner })
end

function CallbackRegistry:Trigger(event, ...)
  if not self.events[event] then return end
  for _, cb in ipairs(self.events[event]) do
    if cb.owner then
      cb.func(cb.owner, ...)
    else
      cb.func(...)
    end
  end
end

-- Accesseur config : DB d'abord, sinon Defaults
function ns.GetCfg(key)
  if ns.DB and ns.DB[key] ~= nil then return ns.DB[key] end
  return ns.Defaults[key]
end

-- Prefixe une cle "resourceCircle" pour la rendre specifique a la spec active
function ns.SecResSpecKey(baseKey, specID)
  specID = specID or ns._specID
  return specID and ("secRes_" .. specID .. "_" .. baseKey) or baseKey
end

-- Lit un reglage "resourceCircle" spec-specifique, retombe sur la cle plate partagee
function ns.GetSecResCfg(baseKey, specID)
  local cfg = ns.GetCfg("resourceCircle")
  if not cfg then return nil end
  local v = cfg[ns.SecResSpecKey(baseKey, specID)]
  if v == nil then v = cfg[baseKey] end
  return v
end

-- Règle commune "tooltip en combat seulement avec ALT" (PriorityBar + Auras)
function ns.ShouldShowSpellTooltip()
  local cfg = ns.GetCfg("priorityBar")
  if not (cfg and cfg.tooltipAltCombatOnly) then return true end
  if not UnitAffectingCombat("player") then return true end
  return IsAltKeyDown()
end

-- Table de correspondance lettre accentuée -> lettre de base ASCII, pour le tri alphabétique
local ACCENT_FOLD = {
  ["\195\128"]="A", ["\195\129"]="A", ["\195\130"]="A", ["\195\131"]="A", ["\195\132"]="A", ["\195\133"]="A", -- À Á Â Ã Ä Å
  ["\195\135"]="C", -- Ç
  ["\195\136"]="E", ["\195\137"]="E", ["\195\138"]="E", ["\195\139"]="E", -- È É Ê Ë
  ["\195\140"]="I", ["\195\141"]="I", ["\195\142"]="I", ["\195\143"]="I", -- Ì Í Î Ï
  ["\195\145"]="N", -- Ñ
  ["\195\146"]="O", ["\195\147"]="O", ["\195\148"]="O", ["\195\149"]="O", ["\195\150"]="O", -- Ò Ó Ô Õ Ö
  ["\195\153"]="U", ["\195\154"]="U", ["\195\155"]="U", ["\195\156"]="U", -- Ù Ú Û Ü
  ["\195\157"]="Y", -- Ý
  ["\195\160"]="a", ["\195\161"]="a", ["\195\162"]="a", ["\195\163"]="a", ["\195\164"]="a", ["\195\165"]="a", -- à á â ã ä å
  ["\195\167"]="c", -- ç
  ["\195\168"]="e", ["\195\169"]="e", ["\195\170"]="e", ["\195\171"]="e", -- è é ê ë
  ["\195\172"]="i", ["\195\173"]="i", ["\195\174"]="i", ["\195\175"]="i", -- ì í î ï
  ["\195\177"]="n", -- ñ
  ["\195\178"]="o", ["\195\179"]="o", ["\195\180"]="o", ["\195\181"]="o", ["\195\182"]="o", -- ò ó ô õ ö
  ["\195\185"]="u", ["\195\186"]="u", ["\195\187"]="u", ["\195\188"]="u", -- ù ú û ü
  ["\195\189"]="y", -- ý
}

-- Remplace les accents par leur lettre de base + minuscules, pour comparaison ASCII simple
function ns.FoldAccentsLower(str)
  if not str or str == "" then return "" end
  local ok, folded = pcall(string.gsub, str, "\195[\128-\191]", ACCENT_FOLD)
  return string.lower(ok and folded or str)
end

-- Ne rend le conteneur d'auras cliquable que pendant ALT (evite qu'il capte le survol
-- en permanence), sauf pendant un drag actif (frame._aishDragging).
function ns.EnableMouseOnlyOnAlt(frame)
  frame:EnableMouse(IsAltKeyDown())
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
  watcher:SetScript("OnEvent", function()
    if frame._aishDragging then return end
    frame:EnableMouse(IsAltKeyDown())
  end)
end

-- Chemins media
ns.Media = {
  circle    = "Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2.tga",
  font      = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat.ttf",
  fontGui   = "Fonts\\FRIZQT__.TTF",
  fontTitle = "Fonts\\FRIZQT__.TTF",
}

-- Filtrage trilineaire (mipmaps) : réduit l'aliasing sur les cercles minifiés
function ns.SetSmoothTexture(texture, path)
  if not texture or not texture.SetTexture then return end
  texture:SetTexture(path, nil, nil, "TRILINEAR")
end

-- Idem pour une StatusBar : repasse par GetStatusBarTexture() (SetStatusBarTexture n'a pas de filterMode)
function ns.SetSmoothStatusBarTexture(bar, path)
  if not bar then return end
  bar:SetStatusBarTexture(path)
  local tex = bar:GetStatusBarTexture()
  ns.SetSmoothTexture(tex, path)
end

-- Liste shared des fonts disponibles dans les dropdowns de sélection (SettingsPanel)
-- Triée par ordre alphabétique (text)
local _SM = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\"
ns.FONT_LIST = {
  { value = "Fonts\\2002.ttf",                       text = "2002 (WoW)"                    },
  { value = _SM.."AccidentalPresidency.ttf",         text = "Accidental Presidency"         },
  { value = "Fonts\\ARIALN.TTF",                     text = "Arial Narrow (WoW)"            },
  { value = _SM.."BebasNeue-Regular.ttf",            text = "Bebas Neue"                    },
  { value = _SM.."FiraMono-Medium.ttf",              text = "Fira Mono Medium"              },
  { value = _SM.."FiraSans-Black.ttf",               text = "Fira Sans Black"               },
  { value = _SM.."FiraSansCondensed-Black.ttf",      text = "Fira Sans Condensed Black"     },
  { value = _SM.."FiraSansCondensed-Medium.ttf",     text = "Fira Sans Condensed Medium"    },
  { value = _SM.."FiraSans-Medium.ttf",              text = "Fira Sans Medium"              },
  { value = _SM.."Fontin-Bold.ttf",                  text = "Fontin Bold"                   },
  { value = _SM.."Fontin-Italic.ttf",                text = "Fontin Italic"                 },
  { value = _SM.."Fontin-Regular.ttf",               text = "Fontin Regular"                },
  { value = _SM.."Fontin-SmallCaps.ttf",             text = "Fontin Small Caps"             },
  { value = _SM.."FORCED SQUARE.ttf",                text = "Forced Square"                 },
  { value = "Fonts\\FRIZQT__.TTF",                   text = "Friz Quadrata (WoW)"           },
  { value = _SM.."HARRYP__.TTF",                     text = "Harry Potter"                  },
  { value = _SM.."HomespunUPPERCASE.ttf",            text = "Homespun Uppercase"            },
  { value = _SM.."imagine_font.ttf",                 text = "Imagine"                       },
  { value = _SM.."Montserrat.ttf",                   text = "Montserrat"                    },
  { value = _SM.."Montserrat-Bold.ttf",              text = "Montserrat Bold"               },
  { value = _SM.."Montserrat-BoldItalic.ttf",        text = "Montserrat Bold Italic"        },
  { value = _SM.."Montserrat-ExtraLight.ttf",        text = "Montserrat ExtraLight"         },
  { value = _SM.."Montserrat-ExtraLightItalic.ttf",  text = "Montserrat ExtraLight Italic"  },
  { value = _SM.."Montserrat-Medium.ttf",            text = "Montserrat Medium"             },
  { value = _SM.."Montserrat-MediumItalic.ttf",      text = "Montserrat Medium Italic"      },
  { value = _SM.."Montserrat-Regular.ttf",           text = "Montserrat Regular"            },
  { value = _SM.."Montserrat-SemiBold.ttf",          text = "Montserrat SemiBold"           },
  { value = _SM.."Montserrat-SemiBoldItalic.ttf",    text = "Montserrat SemiBold Italic"    },
  { value = "Fonts\\MORPHEUS.ttf",                   text = "Morpheus (WoW)"                },
  { value = _SM.."Nueva Std Cond.ttf",               text = "Nueva Std Condensed"           },
  { value = _SM.."OblikCaps.ttf",                    text = "Oblik Caps"                    },
  { value = _SM.."Oswald-Regular.ttf",               text = "Oswald Regular"                },
  { value = _SM.."PTSansNarrow-Regular.ttf",         text = "PT Sans Narrow"                },
  { value = _SM.."PTSansNarrow-Bold.ttf",            text = "PT Sans Narrow Bold"           },
  { value = _SM.."PTSans-NarrowUppercase.ttf",       text = "PT Sans Narrow Majuscules"     },
  { value = _SM.."Roadway.ttf",                      text = "Roadway"                       },
  { value = "Fonts\\SKURRI.TTF",                     text = "Skurri (WoW)"                  },
  { value = _SM.."TrashHand.TTF",                    text = "Trash Hand"                    },
  { value = _SM.."vibrocentric bd.ttf",              text = "Vibrocentric Bold"             },
  { value = _SM.."vibrocentric bd it.ttf",           text = "Vibrocentric Bold Italic"      },
  { value = _SM.."vibrocentric rg.ttf",              text = "Vibrocentric Regular"          },
  { value = _SM.."vibrocentric rg it.ttf",           text = "Vibrocentric Regular Italic"   },
}

-- Retourne la liste des polices depuis LibSharedMedia-3.0 si disponible,
-- sinon fallback sur la liste hardcodée ci-dessus.
local _fontListCache
function ns.GetFontList()
    if _fontListCache then return _fontListCache end
    local ok, LSM = pcall(function()
        return LibStub and LibStub("LibSharedMedia-3.0", true)
    end)
    if ok and LSM then
        local names = LSM:List("font")
        if names and #names > 0 then
            table.sort(names)
            local list = {}
            for _, name in ipairs(names) do
                list[#list + 1] = { value = LSM:Fetch("font", name), text = name }
            end
            _fontListCache = list
            return _fontListCache
        end
    end
    return ns.FONT_LIST  -- LSM absent ou vide, non mis en cache (retry au prochain appel)
end

-- Style de contour de texte partagé : Fin/Epais (natifs) ou SLUG (anneau de 8 copies noires,
-- plus lisible que OUTLINE a petite taille).
local SLUG_RING_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1,  0 },            { 1,  0 },
    { -1,  1 }, { 0,  1 }, { 1,  1 },
}

-- Construite paresseusement : L n'est pas encore rempli quand Core.lua s'execute
local _textOutlineStylesCache
function ns.GetTextOutlineStyles()
    if _textOutlineStylesCache then return _textOutlineStylesCache end
    if not (ns.L and ns.L["TEXT_OUTLINE_THIN"]) then
        -- L pas encore charge : liste non cachee, retry au prochain appel
        return {
            { value = "OUTLINE",      text = "Fin" },
            { value = "THICKOUTLINE", text = "Epais" },
            { value = "SLUG",         text = "SLUG" },
        }
    end
    _textOutlineStylesCache = {
        { value = "OUTLINE",      text = ns.L["TEXT_OUTLINE_THIN"] },
        { value = "THICKOUTLINE", text = ns.L["TEXT_OUTLINE_THICK"] },
        { value = "SLUG",         text = ns.L["TEXT_OUTLINE_SLUG"] },
    }
    return _textOutlineStylesCache
end

--- Cree 8 FontStrings d'ombre en anneau autour de `target`. Ne fonctionne que si
--- `target` n'est jamais animé directement (anime un frame parent commun a la place).
function ns.CreateSlugRing(parent, target, layer)
    local ring = {}
    for i, off in ipairs(SLUG_RING_OFFSETS) do
        local fs = parent:CreateFontString(nil, layer or "ARTWORK")
        -- Ancre TOPLEFT+BOTTOMRIGHT (toute la boite, pas juste CENTER) pour reproduire
        -- exactement le meme rendu de glyphe qu'un texte justifie LEFT/RIGHT.
        fs:SetPoint("TOPLEFT", target, "TOPLEFT", off[1], off[2])
        fs:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", off[1], off[2])
        fs:SetJustifyH(target:GetJustifyH())
        fs:SetJustifyV(target:GetJustifyV())
        ring[i] = fs
    end
    -- Auto-synchronise texte + justification avec `target`
    hooksecurefunc(target, "SetText", function(_, text) ns.SetSlugRingText(ring, text) end)
    hooksecurefunc(target, "SetJustifyH", function(_, justify)
        for _, fs in ipairs(ring) do fs:SetJustifyH(justify) end
    end)
    hooksecurefunc(target, "SetJustifyV", function(_, justify)
        for _, fs in ipairs(ring) do fs:SetJustifyV(justify) end
    end)
    return ring
end

--- Applique le style de contour choisi a `fontString` + son eventuel anneau SLUG `ring`.
--- `applyDefaultShadow` : n'activer que pour les textes qui suivaient déjà la convention
--- d'ombre noire (1,-1)/(0,0,0,1) — l'appelant reste responsable de désactiver sa propre
--- ombre native quand `style == "SLUG"` (sinon elle se cumule avec l'anneau).
function ns.ApplyTextOutlineStyle(fontString, ring, fontPath, size, style, applyDefaultShadow)
    -- style == "" (distinct de nil) : certains menus ont deja leur propre "Aucun contour"
    local flags = "OUTLINE"
    if style == "THICKOUTLINE" then flags = "THICKOUTLINE"
    elseif style == "SLUG" or style == "" then flags = "" end
    local safePath = fontPath or (ns.Media and ns.Media.font) or "Fonts\\FRIZQT__.TTF"
    local ok = pcall(function() fontString:SetFont(safePath, size or 12, flags) end)
    if not ok then fontString:SetFont("Fonts\\FRIZQT__.TTF", size or 12, flags) end
    if applyDefaultShadow then
        if style == "SLUG" then
            fontString:SetShadowOffset(0, 0)
        else
            fontString:SetShadowColor(0, 0, 0, 1)
            fontString:SetShadowOffset(1, -1)
        end
    end
    if ring then
        local slugOn = (style == "SLUG")
        for _, fs in ipairs(ring) do
            local rok = pcall(function() fs:SetFont(safePath, size or 12, "") end)
            if not rok then fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "") end
            fs:SetTextColor(0, 0, 0, 1)
            fs:SetShown(slugOn)
        end
    end
end

--- Recopie `text` sur le FontString principal ET chaque copie de l'anneau
--- SLUG (si present) -- a appeler partout ou le texte affiche change.
function ns.SetSlugRingText(ring, text)
    if not ring then return end
    for _, fs in ipairs(ring) do fs:SetText(text) end
end

-- Barres lissées via StatusBarInterpolation native (remplace bar:SetValue(value))
local _INTERP = StatusBarInterpolation and StatusBarInterpolation.ExponentialEaseOut

function ns.SmoothSetValue(bar, value)
  if not bar or value == nil then return end
  pcall(bar.SetValue, bar, value, _INTERP)
end

-- Utilitaire : deep copy d'une table
function ns.DeepCopy(src)
  if type(src) ~= "table" then return src end
  local copy = {}
  for k, v in pairs(src) do
    copy[k] = ns.DeepCopy(v)
  end
  return copy
end

-- Utilitaire : fusion de deux tables (defaults + saved), sans écraser les valeurs existantes
function ns.MergeDefaults(saved, defaults)
  if type(defaults) ~= "table" then return saved end
  if type(saved) ~= "table" then return ns.DeepCopy(defaults) end
  for k, v in pairs(defaults) do
    if saved[k] == nil then
      saved[k] = ns.DeepCopy(v)
    elseif type(v) == "table" and type(saved[k]) == "table" then
      ns.MergeDefaults(saved[k], v)
    end
  end
  return saved
end

-- Retourne true si le joueur est dans un état bloquant l'affichage (véhicule ou battle pet)
function ns.IsInBlockedState()
  if UnitInVehicle and UnitInVehicle("player") then return true end
  if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return true end
  return false
end

-- Flag Skyriding : mis à jour par Modules/Skyriding.lua, utilisé par ShouldShow() pour s'effacer en vol
ns.skyridingActive = false

-- Flag "en instance" (donjon/raid) : mis en cache au chargement plutôt que d'appeler
-- IsInInstance() à chaque ShouldShow(). Sert à l'option "Toujours actif en instance".
ns.inInstance = false
local _instEvt = CreateFrame("Frame")
_instEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
_instEvt:SetScript("OnEvent", function()
  local inInst, instType = IsInInstance()
  ns.inInstance = inInst and (instType == "party" or instType == "raid") or false
end)

-- Détection des "secret values" (anti-taint) : toute arithmétique/comparaison dessus plante l'addon
local _issecretvalue = issecretvalue
function ns.IsSecret(value)
  return _issecretvalue and _issecretvalue(value) or false
end

-- frame:IsMouseOver() renvoie un booleen secret (patch 12.0) : on recalcule le survol
-- via curseur vs rect du frame, en renonçant si ces valeurs sont elles-mêmes secrètes.
function ns.IsFrameMouseOver(f)
  if not f or not f:IsShown() then return false end
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local left, bottom, width, height = f:GetRect()
  if ns.IsSecret(scale) or ns.IsSecret(cx) or ns.IsSecret(cy)
     or ns.IsSecret(left) or ns.IsSecret(bottom) or ns.IsSecret(width) or ns.IsSecret(height) then
    return false
  end
  if not left or not scale or scale == 0 then return false end
  cx, cy = cx / scale, cy / scale
  return cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height
end

-- Bibliothèque d'easing générique (formules standard, cf. easings.net)
-- ns.Ease(family, kind, t) : t dans [0,1] -> progression easée. Retombe sur Cubic/Out si inconnu.
ns.Easing = {
  Linear = {
    In    = function(t) return t end,
    Out   = function(t) return t end,
    InOut = function(t) return t end,
  },
  Sine = {
    In    = function(t) return 1 - math.cos((t * math.pi) / 2) end,
    Out   = function(t) return math.sin((t * math.pi) / 2) end,
    InOut = function(t) return -(math.cos(math.pi * t) - 1) / 2 end,
  },
  Quad = {
    In    = function(t) return t * t end,
    Out   = function(t) return 1 - (1 - t) * (1 - t) end,
    InOut = function(t)
      if t < 0.5 then return 2 * t * t end
      return 1 - ((-2 * t + 2) ^ 2) / 2
    end,
  },
  Cubic = {
    In    = function(t) return t ^ 3 end,
    Out   = function(t) return 1 - (1 - t) ^ 3 end,
    InOut = function(t)
      if t < 0.5 then return 4 * t ^ 3 end
      return 1 - ((-2 * t + 2) ^ 3) / 2
    end,
  },
  Quart = {
    In    = function(t) return t ^ 4 end,
    Out   = function(t) return 1 - (1 - t) ^ 4 end,
    InOut = function(t)
      if t < 0.5 then return 8 * t ^ 4 end
      return 1 - ((-2 * t + 2) ^ 4) / 2
    end,
  },
  Quint = {
    In    = function(t) return t ^ 5 end,
    Out   = function(t) return 1 - (1 - t) ^ 5 end,
    InOut = function(t)
      if t < 0.5 then return 16 * t ^ 5 end
      return 1 - ((-2 * t + 2) ^ 5) / 2
    end,
  },
  Expo = {
    In    = function(t) if t <= 0 then return 0 end; if t >= 1 then return 1 end; return 2 ^ (10 * t - 10) end,
    Out   = function(t) if t <= 0 then return 0 end; if t >= 1 then return 1 end; return 1 - 2 ^ (-10 * t) end,
    InOut = function(t)
      if t <= 0 then return 0 end
      if t >= 1 then return 1 end
      if t < 0.5 then return (2 ^ (20 * t - 10)) / 2 end
      return (2 - 2 ^ (-20 * t + 10)) / 2
    end,
  },
  Circ = {
    In    = function(t) return 1 - math.sqrt(1 - t ^ 2) end,
    Out   = function(t) return math.sqrt(1 - (t - 1) ^ 2) end,
    InOut = function(t)
      if t < 0.5 then return (1 - math.sqrt(1 - (2 * t) ^ 2)) / 2 end
      return (math.sqrt(1 - (-2 * t + 2) ^ 2) + 1) / 2
    end,
  },
}

function ns.Ease(family, kind, t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local fam = ns.Easing[family] or ns.Easing.Cubic
  local fn  = fam[kind] or fam.Out
  return fn(t)
end

-- Utilitaire : animation stagger générique pour un ensemble d'éléments.
-- Chaque item : { element, delay, duration, ease, easeType, slideX, slideY,
-- scaleX, scaleY, opacity, homePoint, homeRelTo, homeRelPoint, homeX, homeY,
-- homeW, homeH } ; seul `element` est obligatoire, le reste retombe sur le
-- comportement historique (Cubic/Out, scale 0.1->1, pas de slide, fondu 0<->1).
-- home* : géométrie pré-calculée par l'appelant, pour slide/scale sans jamais
-- appeler GetPoint/GetSize (recommandé en combat, où ces lectures peuvent être secrètes).
-- scaleX/scaleY non-uniformes utilisent SetSize (SetScale est uniforme) via ns.SmoothSetValue
-- pour réappliquer le crop de texture des StatusBars (SetValue seul ne suffit pas).
local function RefreshCrop(element)
  if element.GetValue and element.SetValue then
    ns.SmoothSetValue(element, element:GetValue())
  end
end

function ns.AnimateStagger(elements, shouldShow, duration, staggerInterval, onComplete)
  duration = duration or 0.35
  staggerInterval = staggerInterval or 0.04
  local startTime = GetTime()

  -- État capturé au lancement de CETTE animation (pas mis en cache entre appels)
  local homeState = {}
  for _, item in ipairs(elements) do
    if item.element then
      local st = {}
      -- Géométrie pré-calculée par l'appelant si fournie (zéro lecture GetPoint/GetSize,
      -- important en combat où ces valeurs peuvent être secrètes et bloquer tout calcul).
      if (item.slideX and item.slideX ~= 0) or (item.slideY and item.slideY ~= 0) then
        if item.homePoint then
          st.point, st.relTo, st.relPoint, st.x, st.y = item.homePoint, item.homeRelTo, item.homeRelPoint, item.homeX, item.homeY
        elseif item.element.GetPoint then
          local point, relTo, relPoint, x, y = item.element:GetPoint(1)
          -- Filet de sécurité : si secret, abandonne le slide pour cet élément plutôt que de crasher
          if point and not ns.IsSecret(point) and not ns.IsSecret(x) and not ns.IsSecret(y) then
            st.point, st.relTo, st.relPoint, st.x, st.y = point, relTo, relPoint, x, y
          end
        end
      end
      if item.scaleX and item.scaleY and item.scaleX ~= item.scaleY then
        if item.homeW then
          st.w, st.h = item.homeW, item.homeH
        elseif item.element.GetSize then
          local w, h = item.element:GetSize()
          if not ns.IsSecret(w) and not ns.IsSecret(h) then
            st.w, st.h = w, h
          end
        end
      end
      homeState[item] = st
    end
  end

  if shouldShow then
    for _, item in ipairs(elements) do
      if item.element then
        item.element:SetAlpha(item.opacity or 0)
        local sx = item.scaleX or 0.1
        local sy = item.scaleY or 0.1
        local st = homeState[item]
        if st.w then
          item.element:SetSize(st.w * sx, st.h * sy)
          RefreshCrop(item.element)
        elseif item.element.SetScale then
          item.element:SetScale(sx)
        end
      end
    end
  end

  local ticker
  ticker = C_Timer.NewTicker(0.016, function()
    local elapsed = GetTime() - startTime

    for _, item in ipairs(elements) do
      if item.element then
        local st = homeState[item]
        local itemDuration = item.duration or duration
        local elementElapsed = elapsed - (item.delay or 0)
        if elementElapsed >= 0 then
          local elementProgress = math.min(elementElapsed / itemDuration, 1)
          local easeProgress = ns.Ease(item.ease or "Cubic", item.easeType or "Out", elementProgress)
          local opacity = item.opacity or 0
          local startAlpha = shouldShow and opacity or 1
          local endAlpha   = shouldShow and 1 or opacity
          item.element:SetAlpha(startAlpha + (endAlpha - startAlpha) * easeProgress)

          local sx, sy = item.scaleX or 0.1, item.scaleY or 0.1
          local startScale = shouldShow and sx or 1
          local endScale   = shouldShow and 1 or sx
          if st.w then
            local startScaleY = shouldShow and sy or 1
            local endScaleY   = shouldShow and 1 or sy
            local curX = startScale  + (endScale  - startScale)  * easeProgress
            local curY = startScaleY + (endScaleY - startScaleY) * easeProgress
            item.element:SetSize(st.w * curX, st.h * curY)
            RefreshCrop(item.element)
          elseif item.element.SetScale then
            item.element:SetScale(startScale + (endScale - startScale) * easeProgress)
          end

          if st.point then
            local slideX, slideY = item.slideX or 0, item.slideY or 0
            local fromX = shouldShow and (st.x + slideX) or st.x
            local toX   = shouldShow and st.x or (st.x + slideX)
            local fromY = shouldShow and (st.y + slideY) or st.y
            local toY   = shouldShow and st.y or (st.y + slideY)
            item.element:ClearAllPoints()
            item.element:SetPoint(st.point, st.relTo, st.relPoint,
              fromX + (toX - fromX) * easeProgress, fromY + (toY - fromY) * easeProgress)
          end
        elseif not shouldShow then
          item.element:SetAlpha(1)
          if st.w then
            item.element:SetSize(st.w, st.h)
            RefreshCrop(item.element)
          elseif item.element.SetScale then
            item.element:SetScale(1)
          end
          if st.point then
            item.element:ClearAllPoints()
            item.element:SetPoint(st.point, st.relTo, st.relPoint, st.x, st.y)
          end
        end
      end
    end

    local maxDelay = 0
    for _, item in ipairs(elements) do
      local itemTotal = (item.delay or 0) + (item.duration or duration) - duration
      if itemTotal > maxDelay then maxDelay = itemTotal end
    end

    if elapsed >= duration + maxDelay then
      ticker:Cancel()
      for _, item in ipairs(elements) do
        if item.element then
          local st = homeState[item]
          if shouldShow then
            item.element:SetAlpha(1)
          end
          -- Taille/scale reviennent à leur valeur de repos quelle que soit la direction
          -- (sinon un hide laisse l'élément figé à son échelle "hors écran" au show suivant)
          if st.w then
            item.element:SetSize(st.w, st.h)
            RefreshCrop(item.element)
          elseif item.element.SetScale then
            item.element:SetScale(1)
          end
          if st.point then
            item.element:ClearAllPoints()
            item.element:SetPoint(st.point, st.relTo, st.relPoint, st.x, st.y)
          end
        end
      end
      if onComplete then onComplete() end
    end
  end)

  return ticker
end

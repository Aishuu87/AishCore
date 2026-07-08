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

-- CallbackRegistry (inspire de Plumber)
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

-- Chemins media
ns.Media = {
  circle    = "Interface\\AddOns\\Aishaddon\\circleflat2.tga",
  arcLeft   = "Interface\\AddOns\\Aishaddon\\arc_left.tga",
  arcRight  = "Interface\\AddOns\\Aishaddon\\arc_right.tga",
  font      = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat.ttf",
  fontGui   = "Fonts\\FRIZQT__.TTF",
  fontTitle = "Fonts\\FRIZQT__.TTF",
}

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

-- Barres lissées (même approche qu'ElvUI Retail)
-- StatusBarInterpolation.ExponentialEaseOut est géré nativement par WoW C++.
-- Aucun custom OnUpdate, aucun problème de taint — Blizzard gère à 60fps.
-- Usage : ns.SmoothSetValue(bar, value)  ←  remplace bar:SetValue(value)
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

-- Flag Skyriding : mis à jour par Modules/Skyriding.lua
-- Les cercles et unit frames l'utilisent dans ShouldShow() pour s'effacer pendant le vol.
ns.skyridingActive = false

-- Utilitaire : animation stagger générique pour un ensemble d'éléments
function ns.AnimateStagger(elements, shouldShow, duration, staggerInterval, onComplete)
  duration = duration or 0.35
  staggerInterval = staggerInterval or 0.04
  local startTime = GetTime()
  local targetAlpha = shouldShow and 1 or 0

  if shouldShow then
    for _, item in ipairs(elements) do
      if item.element then
        item.element:SetAlpha(0)
        if item.element.SetScale then item.element:SetScale(0.1) end
      end
    end
  end

  local ticker
  ticker = C_Timer.NewTicker(0.016, function()
    local elapsed = GetTime() - startTime

    for _, item in ipairs(elements) do
      if item.element then
        local elementElapsed = elapsed - (item.delay or 0)
        if elementElapsed >= 0 then
          local elementProgress = math.min(elementElapsed / duration, 1)
          local easeProgress = 1 - (1 - elementProgress) ^ 3
          local currentAlpha = (shouldShow and 0 or 1) + (targetAlpha - (shouldShow and 0 or 1)) * easeProgress
          item.element:SetAlpha(currentAlpha)
          if item.element.SetScale then
            local startScale = shouldShow and 0.1 or 1
            local endScale = shouldShow and 1 or 0.1
            item.element:SetScale(startScale + (endScale - startScale) * easeProgress)
          end
        elseif not shouldShow then
          item.element:SetAlpha(1)
          if item.element.SetScale then item.element:SetScale(1) end
        end
      end
    end

    local maxDelay = 0
    for _, item in ipairs(elements) do
      if (item.delay or 0) > maxDelay then maxDelay = item.delay end
    end

    if elapsed >= duration + maxDelay then
      ticker:Cancel()
      if shouldShow then
        for _, item in ipairs(elements) do
          if item.element then
            item.element:SetAlpha(1)
            if item.element.SetScale then item.element:SetScale(1) end
          end
        end
      end
      if onComplete then onComplete() end
    end
  end)

  return ticker
end

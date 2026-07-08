-- Locales/Debug.lua : bascule de langue en jeu, sans changer le client
-- Usage : /aish locale enUS | /aish locale frFR | /aish locale reset
local addonName, ns = ...

local currentOverride = nil -- nil = auto-détection via GetLocale()

local function RebuildActiveTable(source)
  wipe(ns.L)
  for k, v in pairs(ns.L_enUS) do ns.L[k] = v end
  if source and source ~= ns.L_enUS then
    for k, v in pairs(source) do ns.L[k] = v end
  end
end

function ns.SetLocale(code)
  code = code and code:lower() or ""
  if code == "enus" then
    RebuildActiveTable(ns.L_enUS)
    currentOverride = "enUS"
  elseif code == "frfr" then
    RebuildActiveTable(ns.L_frFR)
    currentOverride = "frFR"
  elseif code == "reset" or code == "" then
    RebuildActiveTable(GetLocale() == "frFR" and ns.L_frFR or ns.L_enUS)
    currentOverride = nil
  else
    return false
  end
  return true
end

function ns.GetActiveLocaleCode()
  return currentOverride or ((GetLocale() == "frFR") and "frFR (auto)" or "enUS (auto)")
end

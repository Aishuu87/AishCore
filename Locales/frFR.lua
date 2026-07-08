-- Locales/frFR.lua : traductions françaises (langue d'origine de l'addon)
local addonName, ns = ...

local L = {}
ns.L_frFR = L

L["UI_MOVE_DRAG_DROP"] = "Déplacer (glisser-déposer)"
L["UI_RESET"]          = "Réinitialiser"
L["UI_OFFSET_HINT"]    = "X / Y : offset depuis le centre de l'écran."

-- Ne s'applique par-dessus le socle enUS que si le client est en français ;
-- tout autre client garde l'anglais chargé par enUS.lua.
if GetLocale() == "frFR" then
  for k, v in pairs(L) do
    ns.L[k] = v
  end
end

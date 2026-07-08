-- Locales/enUS.lua : traductions anglaises (fallback pour tout client non listé ci-dessous)
local addonName, ns = ...

local L = {}
ns.L_enUS = L

L["UI_MOVE_DRAG_DROP"] = "Move (drag & drop)"
L["UI_RESET"]          = "Reset"
L["UI_OFFSET_HINT"]    = "X / Y: offset from screen center."

-- ns.L est la table active, lue partout dans l'addon via "local L = ns.L".
-- enUS est toujours chargé en premier et sert de socle complet : toute clé
-- absente d'une locale ultérieure retombe automatiquement sur l'anglais.
ns.L = ns.L or {}
for k, v in pairs(L) do
  ns.L[k] = v
end

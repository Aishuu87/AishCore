-- Modules/BigCursor.lua : agrandit le curseur de la souris en combat.
-- Bascule le CVar cursorSizePreferred entre 0 (normal) et 2 (agrandi) selon
-- InCombatLockdown, remis a 0 en entrant dans le monde au cas ou un
-- logout/reload aurait fige la valeur agrandie.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local BigCursor = {}
ns.Modules.BigCursor = BigCursor

local function Cfg()
  return ns.GetCfg("bigCursor") or {}
end

local function ApplyCursorSize(inCombat)
  local cfg = Cfg()
  if not cfg.enabled then
    C_CVar.SetCVar("cursorSizePreferred", 0)
    return
  end
  C_CVar.SetCVar("cursorSizePreferred", inCombat and (cfg.cursorSize or 2) or 0)
end

function BigCursor.ApplySettings()
  ApplyCursorSize(InCombatLockdown() and true or false)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
  ApplyCursorSize(event == "PLAYER_REGEN_DISABLED")
end)

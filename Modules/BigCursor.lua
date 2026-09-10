-- Modules/BigCursor.lua : agrandit le curseur en combat via le CVar cursorSizePreferred.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local BigCursor = {}
ns.Modules.BigCursor = BigCursor

local function Cfg()
  return ns.GetCfg("bigCursor") or {}
end

local function ApplyCursorSize(inCombat)
  local cfg = Cfg()
  -- Desactive : ne touche plus au CVar, laisse le reglage jeu de l'utilisateur intact
  if not cfg.enabled then return end
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

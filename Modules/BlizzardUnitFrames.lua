-- Modules/BlizzardUnitFrames.lua : masque les cadres d'unités Blizzard (joueur, cible, focalisation,
-- familier, cible de la cible), réglages ns.DB.unitBars.hideBlizz<Unité> (page "Barres de vie").
-- Méthode réversible : le cadre est reparenté dans un conteneur caché (sa propre logique continue de
-- tourner, il reste simplement invisible), puis rendu à son parent d'origine quand on décoche, sans
-- /reload. Ces cadres sont protégés : SetParent uniquement hors combat (sinon différé).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local BlizzardUnitFrames = {}
ns.Modules.BlizzardUnitFrames = BlizzardUnitFrames

local hider = CreateFrame("Frame", "AishCoreBlizzardFrameHider", UIParent)
hider:Hide()

-- clé de réglage -> cadre Blizzard (résolu à l'usage : certains n'existent qu'après le chargement de l'UI)
local FRAMES = {
  { key = "hideBlizzPlayer",       get = function() return PlayerFrame end },
  { key = "hideBlizzTarget",       get = function() return TargetFrame end },
  { key = "hideBlizzFocus",        get = function() return FocusFrame end },
  { key = "hideBlizzPet",          get = function() return PetFrame end },
  { key = "hideBlizzTargetTarget", get = function() return (TargetFrame and TargetFrame.totFrame) or TargetFrameToT end },
}

local origParent = {} -- [cadre] = parent avant masquage
local pending = false

local function SetHidden(frame, hide)
  if not frame then return end
  if hide then
    if origParent[frame] then return end
    origParent[frame] = frame:GetParent() or UIParent
    frame:SetParent(hider)
  elseif origParent[frame] then
    frame:SetParent(origParent[frame])
    origParent[frame] = nil
  end
end

function BlizzardUnitFrames.ApplySettings()
  if InCombatLockdown() then pending = true; return end
  pending = false
  local cfg = ns.GetCfg("unitBars") or {}
  for _, def in ipairs(FRAMES) do
    pcall(SetHidden, def.get(), cfg[def.key] == true)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  BlizzardUnitFrames.ApplySettings()
end)

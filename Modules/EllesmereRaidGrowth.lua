-- Modules/EllesmereRaidGrowth.lua : integration EllesmereUI. Miroite "Down and then Right" des
-- cadres de raid (Croissance du groupe) : le nom reste le meme, mais les colonnes s'ajoutent vers
-- la GAUCHE. Aucune option ajoutee, rien ne touche aux fichiers d'EllesmereUI : on patche a
-- l'execution les fonctions de placement du ns de EllesmereUIRaidFrames. Sans effet si absent.
local addonName, ns = ...

local GRID = "DOWNRIGHT"

local function PatchRuntime(R)
  if R._aishMirrorGrid then return end
  if not (R._RFGroupFlow and R._RFEffectiveGrowth and R._RFGrowthCorner) then return end
  R._aishMirrorGrid = true

  local origFlow, origEff, origCorner = R._RFGroupFlow, R._RFEffectiveGrowth, R._RFGrowthCorner

  -- Meme grille, axe X des slots inverse ; l'origine (minX) est recalculee sur les 4 premiers slots.
  R._RFGroupFlow = function(groupGrowth, groupW, groupH, gs, count, out)
    local slots, minX, maxY = origFlow(groupGrowth, groupW, groupH, gs, count, out)
    if groupGrowth ~= GRID then return slots, minX, maxY end
    minX = 0
    for i = 0, (count or 4) - 1 do
      local p = slots[i]
      if p then
        p[1] = -p[1]
        if i < 4 and p[1] < minX then minX = p[1] end
      end
    end
    return slots, minX, maxY
  end

  -- Groupes fusionnes : le header plat ne sait faire qu'un axe -> LEFT au lieu de RIGHT.
  R._RFEffectiveGrowth = function(unitGrowth, groupGrowth, merged)
    if merged and groupGrowth == GRID then groupGrowth = "LEFT" end
    return origEff(unitGrowth, groupGrowth, merged)
  end

  -- Colonne qui avance a gauche = coin droit fixe ; les lignes vers le bas gardent le haut.
  R._RFGrowthCorner = function(unitGrowth, groupGrowth)
    if groupGrowth == GRID then groupGrowth = "LEFT" end
    return origCorner(unitGrowth, groupGrowth)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
  self:UnregisterAllEvents()
  local EUI = _G.EllesmereUI
  local R = EUI and EUI._ModuleNS and EUI._ModuleNS["EllesmereUIRaidFrames"]
  if R then PatchRuntime(R) end
end)

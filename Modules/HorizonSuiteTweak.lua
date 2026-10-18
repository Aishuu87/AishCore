-- Modules/HorizonSuiteTweak.lua : integration Horizon Suite (page Integrations).
-- DESACTIVE : retire du .toc. Garde pour reference, jamais charge. Section du GUI (Build.Visibility, avant les
-- numeros de groupes), a remettre dans UI/SettingsPanel.lua pour la reactiver :
--[[
  AddonHeader(L["HSTWEAK_SEC"], "HorizonSuite")
  local cbHS = ctx:Add(SW.CreateCheckbox(container, L["HSTWEAK_ENABLE"], L["HSTWEAK_ENABLE_TT"], W))
  BindCheckbox(cbHS, "horizonSuite", "enabled")
  local slHS = ctx:Add(SW.CreateSlider(container, L["HSTWEAK_OFFSET"], -100, 100, 1, SL_W2))
  BindSlider(slHS, "horizonSuite", "offsetY")
]]

-- Le panneau des quetes d'Horizon Suite (HSFrame) est accroche a l'ecran (SetClampedToScreen) : il ne peut pas aller
-- plus haut que le bord. Le decalage vertical passe par la position qu'Horizon Suite enregistre lui-meme (DB x / y,
-- puis RestoreSavedPosition) : decaler le cadre directement le ferait deriver, Horizon Suite resauvegardant la position
-- reelle a chaque deplacement. La marge d'accrochage est elargie d'autant pour que l'ecran ne le ramene pas.
-- Reglages : ns.DB.horizonSuite.enabled / offsetY (px, + = vers le haut) ; _applied = decalage deja reporte.
local addonName, ns = ...

local HorizonSuiteTweak = {}
ns.Modules.HorizonSuiteTweak = HorizonSuiteTweak

local function DB()
  ns.DB.horizonSuite = ns.DB.horizonSuite or {}
  return ns.DB.horizonSuite
end

local ev = CreateFrame("Frame")

function HorizonSuiteTweak.ApplySettings()
  local HS, frame = _G.HorizonSuite, _G.HSFrame
  if not (HS and frame and HS.GetDB and HS.SetDB) then return end
  if InCombatLockdown() then ev._pending = true; return end
  local db = DB()
  -- Correctif unique : avant la pose precoce de la marge, le decalage etait perdu au /reload alors que _applied le
  -- croyait encore en place -> on le reapplique une fois.
  if not db._v2 then db._v2 = true; db._applied = 0 end
  local want = db.enabled and (tonumber(db.offsetY) or 0) or 0
  local applied = tonumber(db._applied) or 0
  -- Marge d'accrochage : le panneau peut deborder de |decalage| en haut comme en bas
  local m = math.abs(want)
  pcall(frame.SetClampRectInsets, frame, 0, 0, -m, m)

  local delta = want - applied
  if delta == 0 then return end
  if HS.EnsureDB then pcall(HS.EnsureDB) end
  local pt = HS.GetDB("point", nil)
  local y = HS.GetDB("y", nil)
  if not pt or not y then
    -- Jamais deplace : on part de sa position par defaut
    HS.SetDB("point", "TOPRIGHT"); HS.SetDB("relPoint", "TOPRIGHT")
    HS.SetDB("x", HS.PANEL_X or -40)
    y = HS.PANEL_Y or -100
  end
  HS.SetDB("y", y + delta)
  db._applied = want
  if HS.RestoreSavedPosition then pcall(HS.RestoreSavedPosition) end
end

-- Marge d'accrochage posee DES le chargement d'Horizon Suite, avant qu'il ne restaure (et ne remesure) sa position :
-- posee plus tard, l'ecran avait deja ramene le panneau dans ses bords et Horizon Suite resauvegardait cette position
-- rabotee au premier redimensionnement, d'ou un decalage perdu a chaque /reload.
local function ApplyClamp()
  local frame = _G.HSFrame
  if not frame then return end
  local db = ns.DB and ns.DB.horizonSuite
  local m = (db and db.enabled) and math.abs(tonumber(db.offsetY) or 0) or 0
  pcall(frame.SetClampRectInsets, frame, 0, 0, -m, m)
end

ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if _G.HSFrame then ApplyClamp() end   -- des qu'Horizon Suite est charge (avant ou apres nous)
  elseif event == "PLAYER_ENTERING_WORLD" then
    ApplyClamp()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- Apres la restauration de position d'Horizon Suite (ADDON_LOADED)
    C_Timer.After(1, HorizonSuiteTweak.ApplySettings)
  elseif self._pending then
    self._pending = nil
    HorizonSuiteTweak.ApplySettings()
  end
end)

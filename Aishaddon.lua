-- Aishaddon.lua : Point d'entree principal (init + event dispatch)
local addonName, ns = ...

-- Frame principal pour les evenements
local frame = CreateFrame("Frame", "AishaddonMainFrame", UIParent)
frame:SetSize(1, 1)
frame:SetPoint("CENTER")

-- Raccourcis modules
local RC   = ns.Modules.ResourceCircle
local HC   = ns.Modules.HealthCircle
local OCRC = ns.Modules.OutOfCombatResourceCircle
local SE   = ns.Modules.SpellEffects
local RH   = ns.Modules.RotationHelper
local PB   = ns.Modules.PriorityBar
local XB   = ns.Modules.XPBar
local UB   = ns.Modules.UnitBars
local CB   = ns.Modules.CastBar
local TCB  = ns.Modules.TargetCastBar
local TTB  = ns.Modules.TopTargetBar
local TA   = ns.Modules.TargetAuras
local CLR  = ns.Modules.Colors
local SR   = ns.Modules.Skyriding

---------------------------------------------------------------------------
-- [DEBUG 12.0.5] Diagnostic d'initialisation
-- Active un log détaillé en cas de problème silencieux (module manquant,
-- API Blizzard cassée, erreur non affichée si "Lua Errors" est off).
-- Activer / désactiver : ns._diag = true (ou /aish diag on)
---------------------------------------------------------------------------
ns._diag = ns._diag or false  -- par défaut off ; flip à true pour logs verbeux
ns._diagInit = {}              -- trace des appels d'init (nom → "ok" | "MISSING" | erreur)

local function DPrint(msg)
  if ns._diag then
    print("|cff00ccff[Aishaddon DIAG]|r " .. tostring(msg))
  end
end
ns.DPrint = DPrint

-- Exécute mod.method(...) en pcall, log l'erreur et la trace.
-- Retourne true si l'appel a réussi, false sinon.
-- CRUCIAL : sans ce wrapper, la première erreur d'un module stoppe tout le
-- reste de PLAYER_ENTERING_WORLD sans affichage si les erreurs Lua sont off.
local function SafeCall(modName, methodName, ...)
  local mod = ns.Modules[modName]
  if not mod then
    ns._diagInit[modName .. "." .. methodName] = "MISSING MODULE"
    DPrint("|cffff4444MODULE ABSENT|r : ns.Modules." .. modName
           .. " est nil — fichier non chargé ou erreur au load")
    return false
  end
  local fn = mod[methodName]
  if type(fn) ~= "function" then
    ns._diagInit[modName .. "." .. methodName] = "MISSING METHOD"
    DPrint("|cffff8800MÉTHODE ABSENTE|r : " .. modName .. "." .. methodName
           .. " (type=" .. type(fn) .. ")")
    return false
  end
  local ok, err = pcall(fn, ...)
  if not ok then
    ns._diagInit[modName .. "." .. methodName] = tostring(err)
    -- Toujours afficher les erreurs d'init, même diag off : sinon on ne saurait
    -- jamais pourquoi l'addon ne fonctionne pas après une maj Blizzard.
    print("|cffff4444[Aishaddon]|r Erreur " .. modName .. "." .. methodName
          .. " : " .. tostring(err))
    return false
  end
  ns._diagInit[modName .. "." .. methodName] = "ok"
  return true
end
ns.SafeCall = SafeCall

-- Slash command : /aish ou /aishaddon
SLASH_AISHADDON1 = "/aish"
SLASH_AISHADDON2 = "/aishaddon"
SlashCmdList["AISHADDON"] = function(msg)
  msg = strtrim((msg or ""):lower())
  -- [DEBUG 12.0.5] /aish diag — dump l'état d'init complet
  if msg == "diag" or msg == "diag on" or msg == "diag off" then
    if msg == "diag on"  then ns._diag = true ; print("|cff00ccff[Aishaddon]|r diag |cff00ff00ON|r  — /reload pour rejouer l'init avec logs") ; return end
    if msg == "diag off" then ns._diag = false; print("|cff00ccff[Aishaddon]|r diag |cffff0000OFF|r") ; return end
    -- Dump immédiat de l'état
    print("|cff00ccff==== Aishaddon Diagnostic ====|r")
    print("  Version : " .. tostring(ns.addonVersion)
      .. "  | Interface TOC : " .. tostring((C_AddOns and C_AddOns.GetAddOnMetadata
         and C_AddOns.GetAddOnMetadata(ns.addonName, "Interface")) or "?")
      .. "  | Build : " .. tostring(select(4, GetBuildInfo())))
    print("  ns.DB       : " .. tostring(ns.DB ~= nil)
      .. "  | ns.Defaults : " .. tostring(ns.Defaults ~= nil)
      .. "  | Profils    : " .. tostring(ns.Profiles ~= nil))
    local names = { "ResourceCircle","HealthCircle","OutOfCombatResourceCircle",
      "SpellEffects","RotationHelper","PriorityBar","XPBar","UnitBars",
      "CastBar","TargetCastBar","TopTargetBar","TargetAuras","Colors","Skyriding" }
    print("  Modules enregistrés :")
    for _, n in ipairs(names) do
      local m = ns.Modules[n]
      if m then
        local methods = {}
        for _, meth in ipairs({ "Create","Init","ApplySettings","Update","UpdateVisibility" }) do
          if type(m[meth]) == "function" then methods[#methods+1] = meth end
        end
        print(string.format("   |cff00ff00✓|r %-28s [%s]", n, table.concat(methods, ",")))
      else
        print(string.format("   |cffff4444✗ MANQUANT|r %s", n))
      end
    end
    print("  Résultats d'init (PLAYER_ENTERING_WORLD) :")
    if ns._diagInit and next(ns._diagInit) then
      for k, v in pairs(ns._diagInit) do
        local color = (v == "ok") and "|cff00ff00" or "|cffff4444"
        print(string.format("    %s%-40s|r %s", color, k, tostring(v)))
      end
    else
      print("    (pas encore exécuté — attends PLAYER_ENTERING_WORLD ou /reload)")
    end
    print("  Astuce : /aish diag on puis /reload pour un log verbeux complet.")
    return
  elseif msg == "rh debug" then
    local rh = ns.Modules.RotationHelper
    if rh and rh.ToggleDebug then
      rh.ToggleDebug()
    else
      print("|cff00b0ff[Aishaddon]|r RotationHelper module not found")
    end
  elseif msg == "rh drag" then
    local rh = ns.Modules.RotationHelper
    if rh then
      rh._dragEnabled = not rh._dragEnabled
      rh.EnableDrag(rh._dragEnabled)
      print("|cff00b0ff[Aishaddon]|r Rotation Helper drag " .. (rh._dragEnabled and "ON" or "OFF"))
    end
  elseif msg == "rh test" then
    local rh = ns.Modules.RotationHelper
    if rh and rh.Test then
      rh.Test()
    else
      print("|cff00b0ff[Aishaddon]|r RotationHelper module not found")
    end
  elseif msg:find("^rh inspect") then
    local rh = ns.Modules.RotationHelper
    if rh and rh.Inspect then
      local num = msg:match("rh inspect%s+(%d+)")
      rh.Inspect(num)
    else
      print("|cff00b0ff[Aishaddon]|r RotationHelper module not found")
    end
  elseif msg == "ps debug" then
    local pb = ns.Modules.PriorityBar
    if pb and pb.ToggleDebug then
      pb.ToggleDebug()
    else
      print("|cff00b0ff[Aishaddon]|r PriorityBar module not found")
    end
  elseif msg == "ps test" then
    local pb = ns.Modules.PriorityBar
    if pb and pb.Test then
      pb.Test()
    else
      print("|cff00b0ff[Aishaddon]|r PriorityBar module not found")
    end
  elseif msg == "ps enh" or msg == "ps enhancement" then
    local pb = ns.Modules.PriorityBar
    if pb and pb.LoadEnhancementPreset then
      pb.LoadEnhancementPreset()
    else
      print("|cff00b0ff[Aishaddon]|r PriorityBar module not found")
    end
  elseif msg:find("^aura%s+") then
    -- Debug : /aish aura 195181  → dump tous les champs de l'aura
    -- ou   : /aish aura scan     → liste tous les buffs actifs
    local arg = msg:match("^aura%s+(.+)")
    if arg == "scan" then
      print("|cff00b0ff[Aishaddon]|r Scan buffs joueur :")
      for i = 1, 64 do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        -- Dump complet de chaque aura pour debug
        local fields = string.format("  [%d] spellId=%-7s name=%-25s applications=%-4s",
          i, tostring(aura.spellId), tostring(aura.name), tostring(aura.applications))
        print(fields)
      end
    else
      local sid = tonumber(arg)
      if not sid then
        print("|cff00b0ff[Aishaddon]|r Usage: /aish aura <spellID> | /aish aura scan")
      else
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
        if not aura then
          print("|cff00b0ff[Aishaddon]|r Aura " .. sid .. " : non trouvée via GetPlayerAuraBySpellID")
        else
          print("|cff00b0ff[Aishaddon]|r Aura " .. sid .. " trouvée :")
          for k, v in pairs(aura) do
            if type(v) ~= "table" then
              print("  " .. tostring(k) .. " = " .. tostring(v))
            end
          end
        end
      end
    end
  elseif msg:find("^charges%s+") or msg == "charges" then
    -- [12.0.5] Diagnostic complet du tracking des charges.
    -- Usage : /aish charges <spellID> (ex: 17364 pour Stormstrike)
    -- À exécuter OOC puis EN COMBAT pour comparer.
    local arg = msg:match("^charges%s+(.+)") or ""
    local sid = tonumber(arg)
    if not sid then
      print("|cff00b0ff[Aishaddon]|r Usage : /aish charges <spellID>")
      return
    end
    local pb = ns.Modules.PriorityBar
    print("|cff00ccff==== /aish charges "..sid.." ====|r")
    print("  InCombat : "..tostring(InCombatLockdown()))

    -- [1] C_Spell.GetSpellCharges
    if C_Spell and C_Spell.GetSpellCharges then
      local ok, info = pcall(C_Spell.GetSpellCharges, sid)
      if not ok then
        print("  |cffff4444C_Spell.GetSpellCharges CRASH :|r "..tostring(info))
      elseif not info then
        print("  |cffffff00C_Spell.GetSpellCharges → nil|r")
      else
        local ok2, dump = pcall(function()
          return string.format("cur=%s max=%s startT=%s dur=%s mod=%s",
            tostring(info.currentCharges), tostring(info.maxCharges),
            tostring(info.cooldownStartTime), tostring(info.cooldownDuration),
            tostring(info.chargeModRate))
        end)
        print("  "..(ok2 and "|cff00ff00C_Spell.GetSpellCharges|r → "..dump
                       or "|cffff4444C_Spell.GetSpellCharges|r champs TAINTED"))
      end
    end

    -- [1b] GetActionCharges (ancienne API, celle qu'utilise Blizzard dans ActionButton.lua)
    if GetActionCharges then
      local pb = ns.Modules.PriorityBar
      local actionSlot = pb and pb._GetActionSlot and pb._GetActionSlot(sid)
      if actionSlot then
        local ok, cur, maxC, chargeStart, chargeDur = pcall(GetActionCharges, actionSlot)
        if ok then
          print(string.format("  |cff00ff00GetActionCharges(%d)|r → cur=%s max=%s startT=%s dur=%s",
            actionSlot, tostring(cur), tostring(maxC), tostring(chargeStart), tostring(chargeDur)))
        else
          print("  |cffff4444GetActionCharges CRASH|r")
        end
      else
        print("  |cffffff00GetActionCharges|r : pas d'action slot en cache pour ce sort")
      end
    end

    -- [2] C_Spell.GetSpellChargeDuration (NOUVEAU 12.0.5)
    if C_Spell and C_Spell.GetSpellChargeDuration then
      local ok, d = pcall(C_Spell.GetSpellChargeDuration, sid)
      if not ok then
        print("  |cffff4444GetSpellChargeDuration CRASH :|r "..tostring(d))
      elseif d == nil then
        print("  |cffffff00GetSpellChargeDuration → nil|r")
      else
        local ok2, dump = pcall(function()
          return string.format("start=%s dur=%s mod=%s",
            tostring(d.startTime), tostring(d.duration), tostring(d.modRate))
        end)
        print("  |cff00ff00GetSpellChargeDuration|r → "..(ok2 and dump or "TAINTED"))
        local ok3, isMax = pcall(function()
          return (type(d.duration)=="number") and d.duration==0
        end)
        print("    → "..((ok3 and isMax) and "AT MAX (zero-span)" or "en recharge / taint"))
      end
    else
      print("  |cffff4444GetSpellChargeDuration : API manquante|r")
    end

    -- [3] Lecture du FontString Count via btn mis en cache
    if pb and pb._GetCachedBtn then
      local btn = pb._GetCachedBtn(sid)
      if not btn then
        print("  FontString Count : |cffffff00bouton non trouvé dans le cache|r")
      else
        print("  Bouton : "..tostring(btn:GetName()))
        if btn.Count and btn.Count.GetText then
          local ok, txt = pcall(btn.Count.GetText, btn.Count)
          if not ok then
            print("    Count:GetText() → |cffff4444CRASH|r")
          else
            print("    Count:GetText() → type="..type(txt).." tonumber="..tostring(tonumber(txt)))
            if btn.Count.IsShown then
              print("    Count:IsShown() → "..tostring(btn.Count:IsShown()))
            end
          end
        end
        if pb._GetLiveCharge then
          print("  liveChargeByButton[btn] (hook) → "..tostring(pb._GetLiveCharge(btn)))
        end
      end
    end

    -- [4] État interne PriorityBar
    if pb and pb._GetEstimated then
      print("  estimatedCharges["..sid.."] → "..tostring(pb._GetEstimated(sid)))
    end
    if pb and pb._GetMaxCharges then
      print("  chargeCache["..sid.."] max → "..tostring(pb._GetMaxCharges(sid)))
    end
    if pb and pb._GetLiveByID then
      print("  liveChargesByID["..sid.."] (ticker dédié) → "..tostring(pb._GetLiveByID(sid)))
    end
    if pb and pb._GetChargesStats then
      local s = pb._GetChargesStats()
      local now = GetTime()
      print(string.format("  stats: event fires=%d writes=%d (il y a %.1fs) | ticker runs=%d writes=%d (il y a %.1fs)",
        s.eventFires or 0, s.eventWrites or 0, now - (s.lastEventTime or 0),
        s.tickerRuns or 0, s.tickerWrites or 0, now - (s.lastTickerTime or 0)))
    end
    -- [5] Dump des slots PB : quel sort affiché, si isChargeSpell se déclenche
    if pb and pb._DumpSlotsForSpell then
      pb._DumpSlotsForSpell(sid)
    end
    print("|cff00ccff=============================|r")
    return
  elseif msg == "ttb debug" then
    local ttb = ns.Modules.TopTargetBar
    if ttb and ttb.Debug then
      ttb.Debug()
    else
      print("|cff00b0ff[Aishaddon]|r TopTargetBar module introuvable")
    end
    -- Debug forcé de l'indicateur de zone de repos
    local xb = ns.Modules.XPBar
    if not xb then print("|cffff4444[Aishaddon]|r XPBar module introuvable"); return end
    -- Accès direct au restModel via la table du module
    local rm = xb._restModel and xb._restModel()
    -- Forcer via preview
    xb.SetRestPreview(true)
    -- Diagnostics
    local cfg = ns.GetCfg("xpBar") or {}
    print("|cff00b0ff[Aishaddon]|r REST DEBUG :")
    print("  enabled=" .. tostring(cfg.enabled))
    print("  restIndicator=" .. tostring(cfg.restIndicator))
    print("  restPreview=true (forcé)")
    print("  restX=" .. tostring(cfg.restX) .. " restY=" .. tostring(cfg.restY) .. " restScale=" .. tostring(cfg.restScale))
    print("  IsResting=" .. tostring(IsResting()))
    -- Forcer position au centre pour confirmer le rendu
    xb.ForceRestCenter()
  elseif msg == "testbar" then
    -- Barre de vie test : loop 0→100% pour valider le smooth bars
    if ns._testBar then
      ns._testBar:Hide()
      if ns._testBarTicker     then ns._testBarTicker:Cancel();     ns._testBarTicker = nil     end
      if ns._testBarAnimTicker then ns._testBarAnimTicker:Cancel(); ns._testBarAnimTicker = nil end
      ns._testBar = nil
      print("|cff00ccff[Aishaddon]|r testbar fermé")
      return
    end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(300, 36); f:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.95); f:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function(s, b) if b == "LeftButton" then s:StartMoving() end end)
    f:SetScript("OnMouseUp",   function(s) s:StopMovingOrSizing() end)
    -- StatusBar
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", 4, -4); bar:SetPoint("BOTTOMRIGHT", -4, 4)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.8, 0.3, 1)
    bar:SetMinMaxValues(0, 100); bar:SetValue(0)
    -- Label
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(ns.Media.fontGui, 10, "OUTLINE")
    lbl:SetPoint("CENTER"); lbl:SetText("Smooth Bars Test")
    lbl:SetTextColor(1, 1, 1, 0.9)
    f:Show(); ns._testBar = f
    -- Loop : saut à 0% → interpolation manuelle smooth vers 100%, puis reset
    local ANIM_DURATION = 1.2   -- durée de la montée en secondes
    local TICK_RATE     = 0.03  -- ~33 fps
    local animTicker    = nil
    local function StartAnim(fromVal, toVal, label)
      if animTicker then animTicker:Cancel(); animTicker = nil end
      lbl:SetText(label)
      local elapsed = 0
      animTicker = C_Timer.NewTicker(TICK_RATE, function()
        elapsed = elapsed + TICK_RATE
        local t = math.min(elapsed / ANIM_DURATION, 1)
        -- ease-out expo : démarre vite, s'écrase net à la fin
        local eased = t >= 1 and 1 or (1 - 2^(-10 * t))
        bar:SetValue(fromVal + (toVal - fromVal) * eased)
        if t >= 1 then
          animTicker:Cancel(); animTicker = nil
          ns._testBarAnimTicker = nil
        end
      end)
      ns._testBarAnimTicker = animTicker
    end
    local function Step()
      -- Saut instant à 20% (dégâts), puis remontée smooth vers 100% (soin)
      bar:SetValue(20)
      C_Timer.After(0.08, function()
        if ns._testBar then StartAnim(20, 100, "↑ Soin (smooth)") end
      end)
    end
    Step()
    ns._testBarTicker = C_Timer.NewTicker(2.2, function()
      if ns._testBar then Step() end
    end)
    print("|cff00ccff[Aishaddon]|r testbar ouvert — /aish testbar pour fermer")
  elseif msg == "arc force" then
    -- Test visuel direct : force l'arc à 70% pendant 5s
    local rc = ns.Modules and ns.Modules.ResourceCircle
    if rc then
      if rc.SetCenterArcValue then
        rc.SetCenterArcValue(0.7, {1, 0.5, 0})
        C_Timer.After(5, function() if rc.SetCenterArcValue then rc.SetCenterArcValue(0, nil) end end)
        print("|cff00ccff[Aishaddon]|r arc force → arc à 70% pendant 5s")
      elseif rc.SetCenterArcEntry then
        print("|cffff4444[Aishaddon]|r SetCenterArcValue absent, teste SetCenterArcEntry...")
      else
        print("|cffff4444[Aishaddon]|r ResourceCircle sans SetCenterArcValue")
      end
    else
      print("|cffff4444[Aishaddon]|r ResourceCircle introuvable")
    end
  elseif ns.SettingsPanel then
    ns.SettingsPanel:Toggle()
  end
end

-- Chargement de la SavedVariable
local function LoadDatabase()
  -- Delègue au moteur de profils : migration legacy, merge defaults, pointage ns.DB
  ns.Profiles.InitDB()
end

-- Cache de classe/spec joueur : invariants entre deux changements de spec.
-- Mis a jour au login et sur PLAYER_SPECIALIZATION_CHANGED / UPDATE_SHAPESHIFT_FORM.
-- Remplace les appels UnitClass() / GetSpecialization() dans les tickers.
-- IMPORTANT : ne jamais écraser une valeur déjà cachée par nil (API parfois
-- indisponible brièvement lors de transitions d'instance / M+).
local function CachePlayerSpec()
  local _, cls = UnitClass("player")
  if cls and cls ~= "" then
    ns._playerClass = cls
  end
  local idx = GetSpecialization and GetSpecialization() or nil
  if idx then
    ns._specIndex = idx
    local sid = GetSpecializationInfo and select(1, GetSpecializationInfo(idx)) or nil
    if sid then
      ns._specID = sid
    end
  end
end

-- Ticker de visibilite (0.2s) + mise a jour de la ressource
local visibilityTicker = nil
local function StartVisibilityTicker()
  if visibilityTicker then return end
  visibilityTicker = C_Timer.NewTicker(0.2, function()
    RC.UpdateVisibility()
    RC.Update()
    HC.UpdateVisibility()  -- doit précéder HC.Update() car Update() ne fait que les valeurs
    HC.Update()
    OCRC.Update()
    OCRC.UpdateVisibility()
    -- Watchdog : rattrape les cas où l'entrée en combat a manqué l'appel initial
    -- (race condition quand InCombatLockdown() était déjà true au moment de l'event).
    -- Le debounce (ubLastVisState / pbLastVisState) garantit zéro overhead si rien n'a changé.
    if UB then UB.UpdateAllVisibility() end
    if PB then PB.UpdateVisibility()   end
  end)
end

-- Callback Skyriding : masquer / restaurer les modules selon leurs toggles individuels
ns.CallbackRegistry:Register("SKYRIDING_CHANGED", function(active)
  local srCfg = ns.GetCfg("skyriding") or {}
  -- Cercles : ShouldShow() vérifie srCfg directement, toujours rafraîchir
  if RC   then RC.ResetVisibility();   RC.UpdateVisibility()   end
  if HC   then HC.ResetVisibility();   HC.UpdateVisibility()   end
  if OCRC then OCRC.ResetVisibility(); OCRC.UpdateVisibility() end
  -- UnitBars et PriorityBar : StateDriver géré manuellement
  if UB then UB.SetSkyridingActive(active and srCfg.hideUnitBars     ~= false) end
  if PB then PB.SetSkyridingActive(active and srCfg.hidePriorityBar  ~= false) end
  -- RotationHelper : reset des icônes au décollage si option active
  if RH and active and srCfg.hideRotationHelper ~= false then RH.SetSkyridingActive(true) end
end)

-- Enregistrement des evenements
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
frame:RegisterUnitEvent("UNIT_MAXPOWER", "player")   -- max ressource change (ex: Holy Power 3→5)
frame:RegisterUnitEvent("UNIT_HEALTH", "player")
frame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")  -- changement de type de ressource affiche
frame:RegisterUnitEvent("UNIT_AURA", "player")            -- pour les ressources trackees par aura (Maelstrom Weapon)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")     -- changement de spe
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")             -- forme druide
frame:RegisterEvent("RUNE_POWER_UPDATE")                   -- DK runes
frame:RegisterEvent("UNIT_ENTERED_VEHICLE")
frame:RegisterEvent("UNIT_EXITED_VEHICLE")
frame:RegisterEvent("PET_BATTLE_OPENING_START")
frame:RegisterEvent("PET_BATTLE_CLOSE")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")   -- zone de repos (hearthstone inn, capitale)

frame:SetScript("OnEvent", function(self, event, arg1, ...)
  if event == "ADDON_LOADED" and arg1 == addonName then
    -- [DEBUG 12.0.5] wrap pour surfacer une erreur de chargement de la DB
    -- (si ns.Profiles manque ou si une migration de profil plante, tout
    -- l'addon tombe silencieusement sans DB ni ns.GetCfg utilisable)
    if not ns.Profiles or not ns.Profiles.InitDB then
      print("|cffff4444[Aishaddon]|r ns.Profiles.InitDB introuvable — "
        .. "Config/Profiles.lua n'a pas été chargé correctement.")
    else
      local ok, err = pcall(LoadDatabase)
      if not ok then
        print("|cffff4444[Aishaddon]|r LoadDatabase a échoué : " .. tostring(err))
      else
        DPrint("DB chargée, profil actif : "
          .. tostring(ns.DB and ns.DB._profileName or "?"))
      end
    end
    self:UnregisterEvent("ADDON_LOADED")

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- [DEBUG 12.0.5] Snapshot des modules présents avant l'init
    if ns._diag then
      local present, missing = {}, {}
      for _, name in ipairs({ "ResourceCircle","HealthCircle","OutOfCombatResourceCircle",
        "SpellEffects","RotationHelper","PriorityBar","XPBar","UnitBars",
        "CastBar","TargetCastBar","TopTargetBar","TargetAuras","Colors","Skyriding" }) do
        if ns.Modules[name] then table.insert(present, name)
        else table.insert(missing, name) end
      end
      DPrint("Modules présents (" .. #present .. ") : " .. table.concat(present, ", "))
      if #missing > 0 then
        DPrint("|cffff4444Modules MANQUANTS|r (" .. #missing .. ") : "
               .. table.concat(missing, ", "))
      end
    end

    -- Creation des elements UI (tous via SafeCall : une erreur d'un module
    -- n'empêche pas les autres de s'initialiser — sans ce filet, un seul
    -- module cassé par une MAJ Blizzard fait perdre TOUT l'addon)
    SafeCall("ResourceCircle",            "Create", UIParent)
    SafeCall("HealthCircle",              "Create", UIParent)
    SafeCall("OutOfCombatResourceCircle", "Create", UIParent)
    SafeCall("SpellEffects",              "Init")
    SafeCall("RotationHelper",            "Init")
    SafeCall("PriorityBar",               "Init")
    SafeCall("XPBar",                     "Init")
    SafeCall("UnitBars",                  "Create", UIParent)
    SafeCall("CastBar",                   "Create", UIParent)
    SafeCall("TargetCastBar",             "Create", UIParent)
    SafeCall("TopTargetBar",              "Create")
    SafeCall("TargetAuras",               "Init")
    SafeCall("Skyriding",                 "Create")

    -- Appliquer les settings (recalcule tailles/positions proportionnellement)
    SafeCall("ResourceCircle",            "ApplySettings")
    SafeCall("HealthCircle",              "ApplySettings")
    SafeCall("OutOfCombatResourceCircle", "ApplySettings")
    SafeCall("RotationHelper",            "ApplySettings")
    SafeCall("PriorityBar",               "ApplySettings")
    SafeCall("XPBar",                     "ApplySettings")
    SafeCall("UnitBars",                  "ApplySettings")
    SafeCall("CastBar",                   "ApplySettings")
    SafeCall("TargetCastBar",             "ApplySettings")
    SafeCall("TopTargetBar",              "ApplySettings")
    SafeCall("TargetAuras",               "ApplySettings")
    SafeCall("Skyriding",                 "ApplySettings")

    -- Bouton minimap
    if ns.MinimapButton then
      local ok, err = pcall(ns.MinimapButton.Init)
      if not ok then print("|cffff4444[Aishaddon]|r MinimapButton.Init : " .. tostring(err)) end
    else
      DPrint("ns.MinimapButton absent")
    end

    -- Cache classe/spec AVANT les couleurs (évite specID nil → fallback classe)
    local ok, err = pcall(CachePlayerSpec)
    if not ok then print("|cffff4444[Aishaddon]|r CachePlayerSpec : " .. tostring(err)) end

    -- Detecter la ressource primaire et appliquer les couleurs
    SafeCall("ResourceCircle",            "UpdateResourceColors")
    SafeCall("OutOfCombatResourceCircle", "UpdateResourceColors")
    if ns.ScanAuraStacks then
      local ok2, err2 = pcall(ns.ScanAuraStacks)
      if not ok2 then print("|cffff4444[Aishaddon]|r ScanAuraStacks : " .. tostring(err2)) end
    else
      DPrint("ns.ScanAuraStacks absent (Libs/SpellSchools.lua pas chargé ?)")
    end

    -- Mise a jour initiale
    SafeCall("ResourceCircle",            "Update")
    SafeCall("HealthCircle",              "Update")
    SafeCall("OutOfCombatResourceCircle", "Update")
    SafeCall("ResourceCircle",            "UpdateVisibility")
    SafeCall("HealthCircle",              "UpdateVisibility")
    SafeCall("OutOfCombatResourceCircle", "UpdateVisibility")

    StartVisibilityTicker()

    -- Filet de sécurité : re-broadcast des couleurs une fois les APIs stables
    -- (rattrape les cas où CachePlayerSpec n'avait pas encore les données
    -- lors d'une transition d'instance / M+).
    C_Timer.After(0.5, function()
      CachePlayerSpec()
      local CLR = ns.Modules and ns.Modules.Colors
      if CLR and CLR.Broadcast then CLR.Broadcast() end
    end)

    -- Libérer AishaddonModelPaths (~19 MB disque → ~60-80 MB Lua) dès le login.
    -- On compacte la table volumineuse en un tableau plat { fileId, text } (ns._modelFlat),
    -- puis on nil la globale et on force un GC complet. Le model picker utilise ns._modelFlat.
    if AishaddonModelPaths then
      ns._modelFlat = {}
      for _, cat in pairs(AishaddonModelPaths) do
        if type(cat) == "table" and cat.children then
          for _, entry in ipairs(cat.children) do
            if entry.fileId then
              local fid = tonumber(entry.fileId) or 0
              local txt = entry.text or entry.value or tostring(entry.fileId)
              ns._modelFlat[#ns._modelFlat + 1] = { fileId = fid, text = txt }
            end
          end
        end
      end
      AishaddonModelPaths = nil
      collectgarbage("collect")
    end

    -- Surcharge de la font des timers de debuffs Platynator avec Montserrat-Bold.
    -- PlatynatorNameplateCooldownFont est cree lors de PLAYER_LOGIN par Platynator ;
    -- on le redirige ici (PLAYER_ENTERING_WORLD se declenche apres PLAYER_LOGIN).
    -- Le hooksecurefunc maintient la font meme si l'utilisateur change le design
    -- dans les options de Platynator (ce qui appellerait SetFont sur cet objet).
    if PlatynatorNameplateCooldownFont then
      local PLAT_FONT_PATH  = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-Bold.ttf"
      local PLAT_FONT_SIZE  = 11
      local PLAT_FONT_FLAGS = "OUTLINE"
      PlatynatorNameplateCooldownFont:SetFont(PLAT_FONT_PATH, PLAT_FONT_SIZE, PLAT_FONT_FLAGS)
      PlatynatorNameplateCooldownFont:SetShadowOffset(0, 0)
      if not self._platynatorFontHooked then
        self._platynatorFontHooked = true
        local overriding = false
        hooksecurefunc(PlatynatorNameplateCooldownFont, "SetFont", function(file)
          if not overriding and file ~= PLAT_FONT_PATH then
            overriding = true
            PlatynatorNameplateCooldownFont:SetFont(PLAT_FONT_PATH, PLAT_FONT_SIZE, PLAT_FONT_FLAGS)
            PlatynatorNameplateCooldownFont:SetShadowOffset(0, 0)
            overriding = false
          end
        end)
      end
    end

  elseif event == "UNIT_AURA" and arg1 == "player" then
    local updateInfo = ...
    ns.HandleUnitAura(updateInfo)
    if RC   then RC.Update()          end
    if RC   then RC.UpdateStagger()   end
    if OCRC then OCRC.Update()        end

  elseif event == "UNIT_POWER_UPDATE" and arg1 == "player" then
    if RC   then RC.Update()        end
    if RC   then RC.UpdateStagger() end
    if OCRC then OCRC.Update()      end

  elseif event == "UNIT_MAXPOWER" and arg1 == "player" then
    -- powerToken = "HOLY_POWER", "COMBO_POINTS", "CHI", "MANA", etc.
    -- On re-detecte les secondary dots quand le max d'une ressource trackee change
    -- (ex: Rogue Deeper Stratagem 5→7, Pala Holy Power 3→5, Moine Chi)
    local powerToken = ...
    if powerToken == "HOLY_POWER" or powerToken == "COMBO_POINTS" or powerToken == "CHI" then
      if RC   then RC.DetectSecondaryDots()   end
      if OCRC then OCRC.DetectSecondaryDots() end
    end

  elseif (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and arg1 == "player" then
    HC.Update()
    if RC then RC.UpdateStagger() end

  elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UNIT_DISPLAYPOWER" then
    CachePlayerSpec()  -- spec/classe vient de changer, recacher
    if RH then RH.Reset() end
    if PB then PB.Reset() end
    if RC then
      RC.OnResourceChanged()
      RC.UpdateRuneColors()
      -- Forcer la re-détection des dots secondaires même si la ressource primaire
      -- n'a pas changé (ex: Mage Feu → Mage Arcane, les deux utilisent le Mana).
      RC.DetectSecondaryDots()
    end
    if OCRC then
      OCRC.OnResourceChanged()
      OCRC.DetectSecondaryDots()
    end

  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then
    if RC   then RC.UpdateVisibility()   end
    if HC   then HC.UpdateVisibility()   end
    if OCRC then OCRC.UpdateVisibility() end
    if PB   then PB.UpdateVisibility()   end

  elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE"
      or event == "PET_BATTLE_OPENING_START" or event == "PET_BATTLE_CLOSE" then
    -- Forcer le reciclage de visibilite de tous les modules non-secure
    if RC   then RC.UpdateVisibility()   end
    if HC   then HC.UpdateVisibility()   end
    if OCRC then OCRC.UpdateVisibility() end
    if PB   then PB.UpdateVisibility()   end
    if RH   then RH.Reset()              end  -- cacher les icones de rotation

  elseif event == "PLAYER_UPDATE_RESTING" then
    if XB then XB.UpdateRestingIndicator() end
  end
end)
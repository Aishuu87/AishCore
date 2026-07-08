-- Modules/RotationHelper.lua : Affiche les icones des sorts mis en surbrillance
-- par l'assistant de rotation Blizzard (spell overlay glow)
-- Detection par polling des action slots + multi-API fallback
local addonName, ns = ...

local RotationHelper = {}
ns.Modules.RotationHelper = RotationHelper

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local containerFrame = nil
local iconPool = {}               -- { spellID = iconFrame }
local activeIcons = {}            -- liste ordonnee des spellID actifs
local activeSet = {}              -- { spellID = true }
local iconSize = 40
local iconSpacing = 4
local maxIcons = 8
local initialized = false
local pollTicker = nil
local debugMode = false
local testMode = false

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local function Debug(msg)
  if debugMode then
    print("|cff00b0ff[RH]|r " .. tostring(msg))
  end
end

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------
local function GetSpellIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  return nil
end

---------------------------------------------------------------------------
-- Noms des boutons d'action standard Blizzard / ABE
---------------------------------------------------------------------------
local BUTTON_PREFIXES = {
  "ActionButton",
  "MultiBarBottomLeftButton",
  "MultiBarBottomRightButton",
  "MultiBarRightButton",
  "MultiBarLeftButton",
  "MultiBar5Button",
  "MultiBar6Button",
  "MultiBar7Button",
}

-- Verifie si un bouton est mis en surbrillance par l'assistant de rotation
local function ButtonHasGlow(button)
  if not button then return false end
  -- Uniquement l'assistant de rotation TWW (AssistedCombatHighlightFrame)
  if button.AssistedCombatHighlightFrame then
    local ok, shown = pcall(button.AssistedCombatHighlightFrame.IsShown, button.AssistedCombatHighlightFrame)
    if ok and shown then return true end
  end
  return false
end

-- Extrait le spellID d'un bouton d'action
local function GetButtonSpellID(button)
  if not button then return nil end
  -- Via action slot
  if button.action and type(button.action) == "number" then
    local ok, aType, id = pcall(GetActionInfo, button.action)
    if ok and aType == "spell" and id and id > 0 then return id end
  end
  -- Via GetSpellID method (TWW buttons)
  if button.GetSpellID then
    local ok, sid = pcall(button.GetSpellID, button)
    if ok and sid and type(sid) == "number" and sid > 0 then return sid end
  end
  return nil
end

---------------------------------------------------------------------------
-- Collecte des spellIDs glow en scannant les boutons d'action
---------------------------------------------------------------------------
local function CollectGlowedSpells()
  local glowed = {}

  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button then
        if ButtonHasGlow(button) then
          local spellID = GetButtonSpellID(button)
          if spellID then
            glowed[spellID] = true
          end
        end
      end
    end
  end

  return glowed
end

---------------------------------------------------------------------------
-- Creation du conteneur principal
---------------------------------------------------------------------------
local function CreateContainer()
  if containerFrame then return containerFrame end
  local cfg = ns.GetCfg("rotationHelper") or {}

  containerFrame = CreateFrame("Frame", "AishaddonRotationHelperBar", UIParent)
  containerFrame:SetSize(1, 1)
  containerFrame:SetPoint(
    cfg.anchor or "TOP",
    UIParent,
    cfg.anchor or "TOP",
    cfg.x or 0,
    cfg.y or -220
  )
  containerFrame:SetFrameStrata("MEDIUM")
  containerFrame:SetFrameLevel(50)
  containerFrame:SetMovable(true)
  containerFrame:EnableMouse(false)
  containerFrame:SetClampedToScreen(true)
  return containerFrame
end

---------------------------------------------------------------------------
-- Creation d'une icone de sort
---------------------------------------------------------------------------
local function CreateSpellIcon(spellID)
  local cfg = ns.GetCfg("rotationHelper") or {}
  local size = cfg.iconSize or iconSize

  local frame = CreateFrame("Frame", nil, containerFrame)
  frame:SetSize(size, size)

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(0, 0, 0, 0.7)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("TOPLEFT", 2, -2)
  frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)

  local tex = GetSpellIcon(spellID)
  if tex then
    frame.icon:SetTexture(tex)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end

  frame.border = frame:CreateTexture(nil, "OVERLAY")
  frame.border:SetAllPoints()
  frame.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  frame.border:SetBlendMode("ADD")
  frame.border:SetAlpha(0.5)

  frame.glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
  frame.glow:SetPoint("TOPLEFT", -4, 4)
  frame.glow:SetPoint("BOTTOMRIGHT", 4, -4)
  frame.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
  frame.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
  frame.glow:SetBlendMode("ADD")
  frame.glow:SetAlpha(0.6)

  frame.glowAG = frame.glow:CreateAnimationGroup()
  frame.glowAG:SetLooping("BOUNCE")
  local pulse = frame.glowAG:CreateAnimation("Alpha")
  pulse:SetFromAlpha(0.4)
  pulse:SetToAlpha(0.8)
  pulse:SetDuration(0.8)
  pulse:SetSmoothing("IN_OUT")
  frame.glowAG:Play()

  frame.showAG = frame:CreateAnimationGroup()
  local fadeIn = frame.showAG:CreateAnimation("Alpha")
  fadeIn:SetFromAlpha(0)
  fadeIn:SetToAlpha(1)
  fadeIn:SetDuration(0.2)
  fadeIn:SetSmoothing("OUT")
  local scaleIn = frame.showAG:CreateAnimation("Scale")
  scaleIn:SetScaleFrom(0.3, 0.3)
  scaleIn:SetScaleTo(1, 1)
  scaleIn:SetDuration(0.2)
  scaleIn:SetSmoothing("OUT")
  frame.showAG:SetScript("OnFinished", function()
    frame:SetAlpha(1)
  end)

  frame.hideAG = frame:CreateAnimationGroup()
  local fadeOut = frame.hideAG:CreateAnimation("Alpha")
  fadeOut:SetFromAlpha(1)
  fadeOut:SetToAlpha(0)
  fadeOut:SetDuration(0.15)
  fadeOut:SetSmoothing("IN")
  local scaleOut = frame.hideAG:CreateAnimation("Scale")
  scaleOut:SetScaleFrom(1, 1)
  scaleOut:SetScaleTo(0.3, 0.3)
  scaleOut:SetDuration(0.15)
  scaleOut:SetSmoothing("IN")
  frame.hideAG:SetScript("OnFinished", function()
    frame:Hide()
  end)

  frame.spellID = spellID
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
    GameTooltip:SetSpellByID(self.spellID)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  frame:SetAlpha(0)
  frame:Hide()
  return frame
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function LayoutIcons()
  if not containerFrame then return end
  local cfg = ns.GetCfg("rotationHelper") or {}
  local size = cfg.iconSize or iconSize
  local spacing = cfg.iconSpacing or iconSpacing
  local count = #activeIcons
  if count == 0 then return end

  local totalWidth = count * size + (count - 1) * spacing
  for i, spellID in ipairs(activeIcons) do
    local icon = iconPool[spellID]
    if icon then
      icon:ClearAllPoints()
      local xOffset = (i - 1) * (size + spacing) - totalWidth / 2 + size / 2
      icon:SetPoint("CENTER", containerFrame, "CENTER", xOffset, 0)
    end
  end
end

---------------------------------------------------------------------------
-- Show / Hide
---------------------------------------------------------------------------
local function ShowSpellIcon(spellID)
  if not containerFrame or not spellID or spellID == 0 then return end
  local cfg = ns.GetCfg("rotationHelper") or {}
  if cfg.enabled == false then return end
  if ns.IsInBlockedState() then return end
  if ns.skyridingActive and (ns.GetCfg("skyriding") or {}).hideRotationHelper ~= false then return end
  if activeSet[spellID] then return end
  if #activeIcons >= (cfg.maxIcons or maxIcons) then return end

  local icon = iconPool[spellID]
  if not icon then
    icon = CreateSpellIcon(spellID)
    iconPool[spellID] = icon
  else
    local tex = GetSpellIcon(spellID)
    if tex then icon.icon:SetTexture(tex) end
    icon.spellID = spellID
  end

  table.insert(activeIcons, spellID)
  activeSet[spellID] = true
  LayoutIcons()

  icon.hideAG:Stop()
  icon:Show()
  icon:SetAlpha(0)
  icon.showAG:Play()
  icon.glowAG:Play()

  Debug("SHOW " .. spellID)
end

local function HideSpellIcon(spellID)
  if not spellID or not activeSet[spellID] then return end
  local icon = iconPool[spellID]

  activeSet[spellID] = nil
  for i = #activeIcons, 1, -1 do
    if activeIcons[i] == spellID then
      table.remove(activeIcons, i)
      break
    end
  end

  if icon then
    icon.showAG:Stop()
    icon.glowAG:Stop()
    icon.hideAG:Play()
  end

  Debug("HIDE " .. spellID)

  C_Timer.After(0.16, function() LayoutIcons() end)
end

---------------------------------------------------------------------------
-- Polling
---------------------------------------------------------------------------
local function PollGlows()
  if testMode then return end
  local currentGlows = CollectGlowedSpells()

  for spellID in pairs(currentGlows) do
    if not activeSet[spellID] then
      ShowSpellIcon(spellID)
    end
  end

  local toHide = {}
  for spellID in pairs(activeSet) do
    if not currentGlows[spellID] then
      toHide[#toHide + 1] = spellID
    end
  end
  for _, spellID in ipairs(toHide) do
    HideSpellIcon(spellID)
  end
end

local function StartPolling()
  if pollTicker then return end
  pollTicker = C_Timer.NewTicker(0.15, PollGlows)
end

local function StopPolling()
  if pollTicker then pollTicker:Cancel(); pollTicker = nil end
end

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------

-- Hook UpdateSpellHighlightMark sur tous les boutons (detection plus rapide)
local buttonsHooked = false
local pendingPoll = false
local function ScheduleQuickPoll()
  if pendingPoll then return end
  pendingPoll = true
  -- Attendre que l'UI finisse sa mise a jour avant de scanner
  C_Timer.After(0.2, function()
    pendingPoll = false
    PollGlows()
  end)
end

local function HookActionButtons()
  if buttonsHooked then return end
  buttonsHooked = true
  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button and button.UpdateSpellHighlightMark and not button._rh_hooked then
        hooksecurefunc(button, "UpdateSpellHighlightMark", function(btn)
          Debug("Hook: UpdateSpellHighlightMark on " .. (prefix .. i))
          ScheduleQuickPoll()
        end)
        button._rh_hooked = true
      end
      if button and button.UpdateSpellAlert and not button._rh_hooked_sa then
        hooksecurefunc(button, "UpdateSpellAlert", function(btn)
          Debug("Hook: UpdateSpellAlert on " .. (prefix .. i))
          ScheduleQuickPoll()
        end)
        button._rh_hooked_sa = true
      end
    end
  end
  Debug("Hooks installed on action buttons")
end

function RotationHelper.Init()
  if initialized then return end
  initialized = true
  CreateContainer()
  
  -- Vérifier la configuration avant de démarrer
  local cfg = ns.GetCfg("rotationHelper") or {}
  if cfg.enabled ~= false then
    StartPolling()
  end

  -- Installer les hooks apres un bref delai (les boutons doivent etre prets)
  C_Timer.After(1, HookActionButtons)
  
  -- Rafraîchissement forcé quand on entre en combat
  local combatFrame = CreateFrame("Frame")
  combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  combatFrame:SetScript("OnEvent", function()
    local currentCfg = ns.GetCfg("rotationHelper") or {}
    if currentCfg.enabled ~= false then
      C_Timer.After(0.2, function()
        PollGlows()
      end)
    end
  end)
end

function RotationHelper.ApplySettings()
  if not containerFrame then return end
  local cfg = ns.GetCfg("rotationHelper") or {}

  -- Gérer l'activation/désactivation
  RotationHelper.SetEnabled(cfg.enabled ~= false)

  containerFrame:ClearAllPoints()
  containerFrame:SetPoint(
    cfg.anchor or "TOP",
    UIParent,
    cfg.anchor or "TOP",
    cfg.x or 0,
    cfg.y or -220
  )

  local size = cfg.iconSize or iconSize
  for _, icon in pairs(iconPool) do
    icon:SetSize(size, size)
    icon.icon:SetPoint("TOPLEFT", 2, -2)
    icon.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  end
  LayoutIcons()
end

function RotationHelper.SetEnabled(enabled)
  if not containerFrame then return end
  if enabled then
    -- Ajuster la taille pour que le frame soit visible
    containerFrame:SetSize(200, 60)
    containerFrame:Show()
    StartPolling()
    -- Forcer un rafraîchissement immédiat quand on active
    C_Timer.After(0.1, function()
      PollGlows()
    end)
  else
    StopPolling()
    for _, icon in pairs(iconPool) do icon:Hide() end
    wipe(activeIcons)
    wipe(activeSet)
    containerFrame:Hide()
    -- Réduire la taille quand désactivé
    containerFrame:SetSize(1, 1)
  end
end

function RotationHelper.EnableDrag(enable)
  if not containerFrame then return end
  containerFrame:EnableMouse(enable)
  if enable then
    containerFrame:SetSize(200, 60)
    containerFrame:RegisterForDrag("LeftButton")
    containerFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    containerFrame:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local point, _, _, x, y = self:GetPoint()
      if ns.DB and ns.DB.rotationHelper then
        ns.DB.rotationHelper.anchor = point
        ns.DB.rotationHelper.x = x
        ns.DB.rotationHelper.y = y
      end
    end)
    if not containerFrame.dragBg then
      containerFrame.dragBg = containerFrame:CreateTexture(nil, "BACKGROUND")
      containerFrame.dragBg:SetAllPoints()
      containerFrame.dragBg:SetColorTexture(0, 0.69, 1, 0.15)
    end
    containerFrame.dragBg:Show()
  else
    containerFrame:SetSize(1, 1)
    containerFrame:EnableMouse(false)
    containerFrame:SetScript("OnDragStart", nil)
    containerFrame:SetScript("OnDragStop", nil)
    if containerFrame.dragBg then containerFrame.dragBg:Hide() end
  end
end

function RotationHelper.Reset()
  for _, icon in pairs(iconPool) do
    icon:Hide(); icon.showAG:Stop(); icon.hideAG:Stop(); icon.glowAG:Stop()
  end
  wipe(activeIcons)
  wipe(activeSet)
  LayoutIcons()
end

function RotationHelper.SetSkyridingActive(active)
  if active then
    RotationHelper.Reset()  -- masquer les icônes en cours immédiatement
  end
  -- Désactivation : les icônes réapparaissent naturellement au prochain tick de polling
end

function RotationHelper.ToggleDebug()
  debugMode = not debugMode
  print("|cff00b0ff[RotationHelper]|r Debug " .. (debugMode and "ON" or "OFF"))

  print("--- System ---")
  print("  Container: " .. (containerFrame and "OK" or "nil"))
  print("  Polling: " .. (pollTicker and "active" or "inactive"))
  print("  Hooks: " .. (buttonsHooked and "installed" or "not installed"))
  print("  Active icons: " .. #activeIcons)

  print("--- Button Scan ---")
  local totalButtons, visibleButtons, glowCount, spellButtons = 0, 0, 0, 0
  local detailLines = {}

  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button then
        totalButtons = totalButtons + 1
        if button:IsVisible() then
          visibleButtons = visibleButtons + 1
          local spellID = GetButtonSpellID(button)
          if spellID then
            spellButtons = spellButtons + 1
            local hasGlow = ButtonHasGlow(button)
            if hasGlow then glowCount = glowCount + 1 end

            -- Detail SHT pour les boutons qui ont un sort assigne
            local shtShown, shtAlpha, shtVisible = "n/a", "n/a", "n/a"
            local shaPlaying = "n/a"
            if button.SpellHighlightTexture then
              local ok1, s = pcall(button.SpellHighlightTexture.IsShown, button.SpellHighlightTexture)
              shtShown = ok1 and tostring(s) or "err"
              local ok2, a = pcall(button.SpellHighlightTexture.GetAlpha, button.SpellHighlightTexture)
              shtAlpha = ok2 and string.format("%.2f", a or 0) or "err"
              local ok3, v = pcall(button.SpellHighlightTexture.IsVisible, button.SpellHighlightTexture)
              shtVisible = ok3 and tostring(v) or "err"
            end
            if button.SpellHighlightAnim and button.SpellHighlightAnim.IsPlaying then
              local ok4, p = pcall(button.SpellHighlightAnim.IsPlaying, button.SpellHighlightAnim)
              shaPlaying = ok4 and tostring(p) or "err"
            end

            local name = ""
            if C_Spell and C_Spell.GetSpellName then
              local ok, n = pcall(C_Spell.GetSpellName, spellID)
              if ok and n then name = n end
            end

            local color = hasGlow and "|cff00ff00" or "|cffaaaaaa"
            detailLines[#detailLines + 1] = color .. prefix .. i .. "|r: " .. spellID .. " (" .. name .. ") SHT:shown=" .. shtShown .. ",alpha=" .. shtAlpha .. ",vis=" .. shtVisible .. " Anim:" .. shaPlaying .. (hasGlow and " |cff00ff00** GLOW **|r" or "")
          end
        end
      end
    end
  end

  print("  Total: " .. totalButtons .. ", Visible: " .. visibleButtons .. ", WithSpell: " .. spellButtons .. ", Glowing: " .. glowCount)

  -- Affiche les details seulement pour les boutons avec sort (max 30 pour eviter spam)
  if #detailLines > 0 then
    print("--- Button Details (spell buttons) ---")
    for idx, line in ipairs(detailLines) do
      if idx > 30 then print("  ... (" .. (#detailLines - 30) .. " more)"); break end
      print("  " .. line)
    end
  end
end

-- Commande test : force l'affichage de quelques icones pour verifier le display
function RotationHelper.Test()
  -- Bloquer le polling (ticker + hooks) pendant le test
  testMode = true
  StopPolling()

  -- Chercher 3 sorts assignes sur les barres
  local testSpells = {}
  local count = 0
  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button and button:IsVisible() then
        local sid = GetButtonSpellID(button)
        if sid and not testSpells[sid] then
          testSpells[sid] = true
          count = count + 1
          ShowSpellIcon(sid)
          if count >= 3 then break end
        end
      end
    end
    if count >= 3 then break end
  end
  if count > 0 then
    print("|cff00b0ff[RH]|r Test: " .. count .. " icones forcees pendant 5 sec")
    C_Timer.After(5, function()
      print("|cff00b0ff[RH]|r Test: fin, reprise du polling")
      -- Copie la liste avant de la modifier
      local toRemove = {}
      for _, sid in ipairs(activeIcons) do toRemove[#toRemove + 1] = sid end
      for _, sid in ipairs(toRemove) do
        HideSpellIcon(sid)
      end
      testMode = false
      StartPolling()
    end)
  else
    print("|cff00b0ff[RH]|r Test: aucun sort trouve sur les barres")
    testMode = false
    StartPolling()
  end
end

-- Inspection profonde d'un bouton : dump tous les children, regions, overlays
function RotationHelper.Inspect(slotStr)
  local slot = tonumber(slotStr)
  if not slot then
    print("|cff00b0ff[RH]|r Usage: /aish rh inspect <numero> (ex: 5 pour ActionButton5)")
    return
  end

  -- Trouver le bouton
  local button = _G["ActionButton" .. slot]
  local btnName = "ActionButton" .. slot
  if not button then
    print("|cff00b0ff[RH]|r Button ActionButton" .. slot .. " not found")
    return
  end

  local spellID = GetButtonSpellID(button)
  local spellName = ""
  if spellID and C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, spellID)
    if ok and n then spellName = n end
  end
  print("|cff00b0ff[RH]|r === Inspect " .. btnName .. " ===")
  print("  SpellID: " .. tostring(spellID) .. " (" .. spellName .. ")")
  print("  IsVisible: " .. tostring(button:IsVisible()))
  print("  IsShown: " .. tostring(button:IsShown()))

  -- Lister TOUTES les proprietes (tables et userdata = potentiels frames enfants)
  print("--- All Table/Userdata Properties ---")
  local propCount = 0
  for k, v in pairs(button) do
    local t = type(v)
    if t == "table" or t == "userdata" then
      propCount = propCount + 1
      local info = k .. " [" .. t .. "]"
      -- Essayer de voir si c'est un frame avec IsShown/IsVisible
      if t == "table" or t == "userdata" then
        local hasShow = (type(v) == "table" and type(v.IsShown) == "function") or
                        (type(v) == "userdata" and pcall(function() return v.IsShown end))
        if type(v.IsShown) == "function" then
          local ok, shown = pcall(v.IsShown, v)
          local ok2, vis = pcall(v.IsVisible, v)
          info = info .. " shown=" .. (ok and tostring(shown) or "err") .. " visible=" .. (ok2 and tostring(vis) or "err")
        end
        if type(v.GetAlpha) == "function" then
          local ok, a = pcall(v.GetAlpha, v)
          info = info .. " alpha=" .. (ok and string.format("%.2f", a or 0) or "err")
        end
        if type(v.IsPlaying) == "function" then
          local ok, p = pcall(v.IsPlaying, v)
          info = info .. " playing=" .. (ok and tostring(p) or "err")
        end
        if type(v.GetObjectType) == "function" then
          local ok, ot = pcall(v.GetObjectType, v)
          info = info .. " type=" .. (ok and tostring(ot) or "err")
        end
      end
      print("  " .. info)
    end
  end
  print("  (" .. propCount .. " table/userdata properties)")

  -- Lister les children (frames enfants du bouton)
  print("--- Children Frames ---")
  local children = { button:GetChildren() }
  for idx, child in ipairs(children) do
    local cname = child:GetName() or "(anonymous)"
    local ctype = child:GetObjectType()
    local cshown = child:IsShown()
    local cvis = child:IsVisible()
    local calpha = child:GetAlpha()
    local info = "#" .. idx .. " " .. cname .. " [" .. ctype .. "] shown=" .. tostring(cshown) .. " visible=" .. tostring(cvis) .. " alpha=" .. string.format("%.2f", calpha)
    -- Sous-enfants
    local subChildren = { child:GetChildren() }
    if #subChildren > 0 then
      info = info .. " subChildren=" .. #subChildren
      for si, sc in ipairs(subChildren) do
        local scname = sc:GetName() or "(anon)"
        local scshown = sc:IsShown()
        local scvis = sc:IsVisible()
        info = info .. "\n      #" .. idx .. "." .. si .. " " .. scname .. " [" .. sc:GetObjectType() .. "] shown=" .. tostring(scshown) .. " vis=" .. tostring(scvis)
        if scvis then
          info = info .. " |cff00ff00** VISIBLE **|r"
        end
      end
    end
    -- Sous-regions (textures, fontstrings)
    local subRegions = { child:GetRegions() }
    local visibleRegions = 0
    for _, r in ipairs(subRegions) do
      if r:IsVisible() then visibleRegions = visibleRegions + 1 end
    end
    if visibleRegions > 0 then
      info = info .. " visibleRegions=" .. visibleRegions
    end
    if cvis then
      info = "|cff00ff00" .. info .. "|r"
    end
    print("  " .. info)
  end

  -- Regions du bouton (textures)
  print("--- Regions (textures) ---")
  local regions = { button:GetRegions() }
  local visRegions = 0
  for idx, region in ipairs(regions) do
    if region:IsVisible() then
      visRegions = visRegions + 1
      local rname = region:GetName() or "(anon)"
      local rtype = region:GetObjectType()
      local ralpha = region:GetAlpha()
      local tex = ""
      if rtype == "Texture" and region.GetTexture then
        local ok, t = pcall(region.GetTexture, region)
        if ok and t then tex = " tex=" .. tostring(t) end
      end
      print("  " .. rname .. " [" .. rtype .. "] alpha=" .. string.format("%.2f", ralpha) .. tex)
    end
  end
  print("  (" .. visRegions .. " visible / " .. #regions .. " total)")
end

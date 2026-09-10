-- Modules/RotationHelper.lua : icones des sorts surlignes par l'assistant de rotation Blizzard (polling action slots + fallback API)
local addonName, ns = ...

local RotationHelper = {}
ns.Modules.RotationHelper = RotationHelper

-- State
local containerFrame = nil
local iconPool = {}               -- { spellID = iconFrame }
local activeIcons = {}            -- liste ordonnee des spellID actifs
local activeSet = {}              -- { spellID = true }
local iconSize = 40
local initialized = false
local pollTicker = nil
local debugMode = false
local testMode = false
local dragUnlocked = false -- glisser/deposer arme (bouton "reglages > position"), cf. EnableDrag
local previewMode = false
local previewIcon = nil -- icone dediee au SetPreview du panneau de reglages, cf. plus bas

-- Debug
local function Debug(msg)
  if debugMode then
    print("|cff00b0ff[RH]|r " .. tostring(msg))
  end
end

-- Utilitaires
local function GetSpellIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  return nil
end

-- Noms des boutons d'action standard Blizzard / ABE
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

-- API Blizzard directe pour le sort suggere (meme source que PriorityBar.lua), plus fiable que scanner les boutons un par un
local C_AC_GetNextCastSpell = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell

local function GetAssistedCombatHighlightSpell()
  if not C_AC_GetNextCastSpell then return nil end
  local ok, sid = pcall(C_AC_GetNextCastSpell)
  if not ok or not sid or sid == 0 then return nil end
  -- Patch 12.x : une valeur retournee depuis une pile taintee peut etre secrete.
  if type(issecretvalue) == "function" then
    local okSec, isSec = pcall(issecretvalue, sid)
    if okSec and isSec then return nil end
  end
  return sid
end

-- Collecte du/des sort(s) surligne(s) : API directe en priorite, repli sur scan des boutons si indisponible
local function CollectGlowedSpells()
  local glowed = {}

  local assistedSid = GetAssistedCombatHighlightSpell()
  if assistedSid then
    glowed[assistedSid] = true
    return glowed
  end

  for _, prefix in ipairs(BUTTON_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button and ButtonHasGlow(button) then
        local spellID = GetButtonSpellID(button)
        if spellID then
          glowed[spellID] = true
        end
      end
    end
  end

  return glowed
end

-- Creation du conteneur principal
local function CreateContainer()
  if containerFrame then return containerFrame end
  local cfg = ns.GetCfg("rotationHelper") or {}

  containerFrame = CreateFrame("Frame", "AishCoreRotationHelperBar", UIParent)
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

-- Glisser/deposer relaye depuis l'icone visible vers containerFrame (un enfant recoit la souris avant son parent), gardé derriere dragUnlocked
local function OnRHDragStart()
  if not dragUnlocked or not containerFrame then return end
  containerFrame:StartMoving()
end

local function OnRHDragStop()
  if not containerFrame then return end
  containerFrame:StopMovingOrSizing()
  local point, _, _, x, y = containerFrame:GetPoint()
  if ns.DB and ns.DB.rotationHelper then
    ns.DB.rotationHelper.anchor = point
    ns.DB.rotationHelper.x = x
    ns.DB.rotationHelper.y = y
  end
  -- Met a jour les sliders X/Y du panneau de reglages (meme convention que ResourceCircle/Skyriding)
  local xSl = _G["AishCoreRHPosXSlider"]
  local ySl = _G["AishCoreRHPosYSlider"]
  if xSl then xSl:SetValue(x) end
  if ySl then ySl:SetValue(y) end
end

-- Creation d'une icone de sort
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

  -- Glow non porte par l'icone : instance unique partagee sur containerFrame (cf. bloc GLOW PARTAGE plus bas)

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
  -- Relais de glisser/deposer vers containerFrame (l'icone visible recoit le clic, pas le containerFrame invisible/1x1)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", OnRHDragStart)
  frame:SetScript("OnDragStop", OnRHDragStop)
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

-- GLOW PARTAGE : instance unique sur containerFrame (pas par icone/spellID, evite le bug de glow qui ne se rallumait qu'une fois sur deux).
-- L'anim (pulse/flipbook) demarre une seule fois et tourne en permanence ; StartGlow/StopGlow ne font que Show()/Hide(), jamais Play()/Stop().
local rhGlowContainer, rhGlowTex, rhGlowAG, rhGlowPulse
local rhLoopFlipTex, rhLoopFlipAG, rhLoopFlipAnim
local rhGlowMode = "none"

local function EnsureContainerGlow()
  if rhGlowContainer or not containerFrame then return end
  rhGlowContainer = CreateFrame("Frame", nil, containerFrame)
  rhGlowContainer:SetPoint("CENTER", containerFrame, "CENTER", 0, 0)
  rhGlowContainer:SetFrameLevel(containerFrame:GetFrameLevel() + 2)

  rhGlowTex = rhGlowContainer:CreateTexture(nil, "OVERLAY", nil, 1)
  rhGlowTex:SetBlendMode("ADD")
  rhGlowTex:SetAlpha(0)
  rhGlowTex:Hide()
  rhGlowAG = rhGlowTex:CreateAnimationGroup()
  rhGlowAG:SetLooping("BOUNCE")
  rhGlowPulse = rhGlowAG:CreateAnimation("Alpha")
  rhGlowPulse:SetSmoothing("IN_OUT")

  rhLoopFlipTex = rhGlowContainer:CreateTexture(nil, "OVERLAY", nil, 2)
  rhLoopFlipTex:SetAlpha(0)
  rhLoopFlipTex:Hide()
  rhLoopFlipAG = rhLoopFlipTex:CreateAnimationGroup()
  rhLoopFlipAG:SetLooping("REPEAT")
  rhLoopFlipAnim = rhLoopFlipAG:CreateAnimation("FlipBook")
  rhLoopFlipAnim:SetOrder(1)
end

-- Applique la config de glow (type/couleur/taille), meme logique que PriorityBar.ApplyGlowConfig. Appelee a la creation/reglage, jamais a chaque activation (cf. StartGlow)
local function ApplyGlowConfig()
  EnsureContainerGlow()
  if not rhGlowContainer then return end
  local cfg = ns.GetCfg("rotationHelper") or {}
  local PB = ns.Modules and ns.Modules.PriorityBar
  local LOOP = PB and PB.LOOP_GLOW_TYPES
  if not LOOP then rhGlowMode = "none"; return end

  -- Couleur : priorite a la couleur "Glow" de la spec active si demande, retombe sur cfg.glowColor sinon
  local glowColor
  if cfg.useSpecGlowColor then
    local Clr = ns.Modules and ns.Modules.Colors
    if Clr and Clr.Get then glowColor = Clr.Get("glow") end
  end
  glowColor = glowColor or cfg.glowColor or { 1, 0.85, 0, 0.8 }
  local glowSize  = cfg.glowSize or 4
  local loopIdx   = cfg.loopGlowIndex or 1
  local gt = LOOP[loopIdx] or LOOP[1]
  local size = cfg.iconSize or iconSize
  rhGlowContainer:SetSize(size, size)

  -- Repli sur "Pulse" (LOOP[2]) si l'atlas choisi n'existe pas sur ce client : SetAtlas echoue silencieusement sinon (icone invisible)
  if gt.atlas and C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(gt.atlas) then
    gt = LOOP[2] or gt
  end

  if gt.useAlphaPulse then
    rhGlowMode = "pulse"
    rhLoopFlipAG:Stop(); rhLoopFlipTex:SetAlpha(0); rhLoopFlipTex:Hide()

    if gt.atlas then
      rhGlowTex:SetTexture(nil); rhGlowTex:SetAtlas(gt.atlas); rhGlowTex:SetTexCoord(0, 1, 0, 1)
    else
      rhGlowTex:SetTexture(gt.texture)
      if gt.texCoord then rhGlowTex:SetTexCoord(unpack(gt.texCoord))
      else rhGlowTex:SetTexCoord(0, 1, 0, 1) end
    end
    rhGlowTex:SetBlendMode(gt.blendMode or "ADD")
    rhGlowTex:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
    rhGlowTex:ClearAllPoints()
    rhGlowTex:SetPoint("TOPLEFT", rhGlowContainer, "TOPLEFT", -glowSize, glowSize)
    rhGlowTex:SetPoint("BOTTOMRIGHT", rhGlowContainer, "BOTTOMRIGHT", glowSize, -glowSize)
    rhGlowPulse:SetFromAlpha(gt.fromAlpha or 0.4)
    rhGlowPulse:SetToAlpha(gt.toAlpha or 0.8)
    rhGlowPulse:SetDuration(gt.duration or 0.8)
  elseif gt.atlas or gt.texture then
    rhGlowMode = "flipbook"
    rhGlowAG:Stop(); rhGlowTex:SetAlpha(0); rhGlowTex:Hide()

    if gt.atlas then
      rhLoopFlipTex:SetTexture(nil); rhLoopFlipTex:SetAtlas(gt.atlas)
    else
      rhLoopFlipTex:SetTexture(gt.texture)
    end
    local sc = gt.scale or 1
    local texSize = size * sc + glowSize * 2
    rhLoopFlipTex:ClearAllPoints()
    rhLoopFlipTex:SetSize(texSize, texSize)
    rhLoopFlipTex:SetPoint("CENTER", rhGlowContainer, "CENTER", 0, 0)
    rhLoopFlipTex:SetVertexColor(glowColor[1], glowColor[2], glowColor[3], glowColor[4] or 1)
    rhLoopFlipTex:SetBlendMode("ADD")
    rhLoopFlipAnim:SetFlipBookRows(gt.rows or 6)
    rhLoopFlipAnim:SetFlipBookColumns(gt.columns or 5)
    rhLoopFlipAnim:SetFlipBookFrames(gt.frames or 30)
    rhLoopFlipAnim:SetDuration(gt.duration or 1.0)
    rhLoopFlipAnim:SetFlipBookFrameWidth(gt.frameW or 0)
    rhLoopFlipAnim:SetFlipBookFrameHeight(gt.frameH or 0)
  else
    -- "Aucun" (index 1 : ni useAlphaPulse, ni atlas, ni texture)
    rhGlowMode = "none"
    rhGlowAG:Stop(); rhGlowTex:SetAlpha(0); rhGlowTex:Hide()
    rhLoopFlipAG:Stop(); rhLoopFlipTex:SetAlpha(0); rhLoopFlipTex:Hide()
  end

  -- Demarre l'anim active ici une seule fois, elle tourne ensuite en permanence jusqu'au prochain changement de reglage.
  if rhGlowMode == "flipbook" and not rhLoopFlipAG:IsPlaying() then rhLoopFlipAG:Play() end
  if rhGlowMode == "pulse" and not rhGlowAG:IsPlaying() then rhGlowAG:Play() end
end

-- Rafraichit la couleur "spec" du glow au changement de spec/profil (sinon useSpecGlowColor reste fige sur l'ancienne spec)
if ns.CallbackRegistry then
  local function RefreshGlowColorOnSpecChange()
    if containerFrame and (ns.GetCfg("rotationHelper") or {}).useSpecGlowColor then
      ApplyGlowConfig()
    end
  end
  ns.CallbackRegistry:Register("SPEC_CHANGED", RefreshGlowColorOnSpecChange)
  ns.CallbackRegistry:Register("PROFILE_CHANGED", RefreshGlowColorOnSpecChange)
end

-- Affiche/masque le glow (seule condition : une icone est affichee), ne touche jamais Play()/Stop() (gere par ApplyGlowConfig)
local function StartGlow()
  if not rhGlowContainer then ApplyGlowConfig() end
  if not rhGlowContainer then return end
  if rhGlowMode == "flipbook" then
    rhLoopFlipTex:SetAlpha(1)
    rhLoopFlipTex:Show()
  elseif rhGlowMode == "pulse" then
    rhGlowTex:SetAlpha(0.6)
    rhGlowTex:Show()
  end
end

local function StopGlow()
  if not rhGlowContainer then return end
  rhGlowTex:SetAlpha(0); rhGlowTex:Hide()
  rhLoopFlipTex:SetAlpha(0); rhLoopFlipTex:Hide()
end

-- Layout : une seule icone possible (cf. ShowSpellIcon), toujours centree.
local function LayoutIcons()
  if not containerFrame then return end
  local spellID = activeIcons[1]
  if not spellID then return end
  local icon = iconPool[spellID]
  if icon then
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", containerFrame, "CENTER", 0, 0)
  end
end

-- Show / Hide
local function ShowSpellIcon(spellID)
  if not containerFrame or not spellID or spellID == 0 then return end
  local cfg = ns.GetCfg("rotationHelper") or {}
  if cfg.enabled == false then return end
  if ns.IsInBlockedState() then return end
  -- ns.skyridingActive ne couvre que le HUD Skyriding ; IsFlying() couvre aussi un mont volant classique (masquage "pendant le vol" au sens large)
  if (ns.skyridingActive or (IsFlying and IsFlying())) and (ns.GetCfg("skyriding") or {}).hideRotationHelper ~= false then return end
  if activeSet[spellID] then return end
  -- Une seule icone a la fois (miroir du highlight Blizzard, qui ne suggere jamais qu'un seul sort a la fois)
  if #activeIcons >= 1 then return end

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
  StartGlow()

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
    icon.hideAG:Play()
  end
  StopGlow()

  Debug("HIDE " .. spellID)

  C_Timer.After(0.16, function() LayoutIcons() end)
end

-- Vrai si la cible existe, est vivante et est attaquable par le joueur (meme verification que MissingBuffs.lua)
local function IsTargetAttackable()
  return UnitExists("target")
    and not UnitIsDeadOrGhost("target")
    and UnitCanAttack and UnitCanAttack("player", "target")
end

-- Visibilite (memes reglages que PriorityBar) : consultee uniquement par PollGlows, Test()/SetPreview contournent volontairement
local function ShouldShowIcons()
  local cfg = ns.GetCfg("rotationHelper") or {}
  if cfg.enabled == false then return false end
  if ns.IsInBlockedState() then return false end
  if (ns.skyridingActive or (IsFlying and IsFlying())) and (ns.GetCfg("skyriding") or {}).hideRotationHelper ~= false then return false end
  local vMode = cfg.visibilityMode or "combat"
  -- Zone de repos : les modes "Cible uniquement"/"En combat" overrident ce masquage s'ils sont satisfaits, seul "Toujours" y reste soumis
  if cfg.ignoreWhileResting and IsResting and IsResting() then
    if vMode == "target" then
      if not IsTargetAttackable() then return false end
    elseif vMode == "combat" then
      if not UnitAffectingCombat("player") then return false end
    else
      return false
    end
  end
  if cfg.alwaysInInstance and ns.inInstance then return true end
  if vMode == "always" then return true end
  -- "Cible uniquement" : vrai seulement si la cible est reellement attaquable (pas juste presente)
  if vMode == "target" then return IsTargetAttackable() and true or false end
  return UnitAffectingCombat("player") and true or false
end

-- Polling
local function PollGlows()
  if testMode or previewMode then return end
  local currentGlows = ShouldShowIcons() and CollectGlowedSpells() or {}

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

-- API publique

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

  -- Re-applique le glow (type/couleur/taille) : instance partagee (cf. GLOW PARTAGE), redemarre l'affichage seulement si une icone est visible
  ApplyGlowConfig()
  if #activeIcons > 0 or previewMode then
    StartGlow()
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

-- Apercu force pour le panneau de reglages (meme convention que CastBar.SetPreview). Icone dediee (cle "preview") pour eviter les gardes de ShowSpellIcon.
function RotationHelper.SetPreview(on)
  if not containerFrame then return end
  local cfg = ns.GetCfg("rotationHelper") or {}
  if on and cfg.enabled == false then return end
  previewMode = on
  if on then
    StopPolling()
    for _, icon in pairs(iconPool) do icon:Hide() end
    wipe(activeIcons)
    wipe(activeSet)
    containerFrame:SetSize(200, 60)
    containerFrame:Show()
    if not previewIcon then
      previewIcon = CreateSpellIcon(133) -- Boule de feu : meme sort "neutre" que CastBar/TargetCastBar SetPreview
      iconPool.preview = previewIcon      -- redimensionne automatiquement avec les autres (cf. ApplySettings)
    end
    previewIcon:ClearAllPoints()
    previewIcon:SetPoint("CENTER", containerFrame, "CENTER", 0, 0)
    previewIcon:SetAlpha(1)
    previewIcon:Show()
    StartGlow()
  else
    StopGlow()
    if previewIcon then
      previewIcon:Hide()
    end
    if cfg.enabled ~= false then
      StartPolling()
      C_Timer.After(0.1, function() PollGlows() end)
    else
      containerFrame:SetSize(1, 1)
      containerFrame:Hide()
    end
  end
end

function RotationHelper.EnableDrag(enable)
  if not containerFrame then return end
  -- Arme/desarme aussi le relais sur l'icone (cf. OnRHDragStart) : c'est elle qui recoit le clic, containerFrame est invisible/1x1 hors mode drag
  dragUnlocked = enable
  containerFrame:EnableMouse(enable)
  if enable then
    containerFrame:SetSize(200, 60)
    containerFrame:RegisterForDrag("LeftButton")
    containerFrame:SetScript("OnDragStart", OnRHDragStart)
    containerFrame:SetScript("OnDragStop", OnRHDragStop)
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
    icon:Hide(); icon.showAG:Stop(); icon.hideAG:Stop()
  end
  StopGlow()
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

-- Commande test : force l'affichage de l'icone pour verifier le display (une seule a la fois)
function RotationHelper.Test()
  -- Bloquer le polling (ticker + hooks) pendant le test
  testMode = true
  StopPolling()

  -- Chercher 1 sort assigne sur les barres
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
          if count >= 1 then break end
        end
      end
    end
    if count >= 1 then break end
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

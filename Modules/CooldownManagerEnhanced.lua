-- Modules/CooldownManagerEnhanced.lua : personnalisation des viewers natifs Essentiels/Utilitaires
-- (masques, bordures, grille, fondu, charges), limite a ces 2 viewers, textures/atlas Blizzard uniquement.
local addonName, ns = ...
local L = ns.L

local CDME = {}
ns.Modules.CooldownManagerEnhanced = CDME

-- Viewers geres + mapping frameName -> cle de config
local VIEWER_CFGKEY = {
  EssentialCooldownViewer = "cdmEssential",
  UtilityCooldownViewer   = "cdmUtility",
}
local VIEWER_NAMES = { "EssentialCooldownViewer", "UtilityCooldownViewer" }

local function GetCfgFor(frameName)
  local key = VIEWER_CFGKEY[frameName]
  return key and ns.GetCfg(key)
end

-- Masques d'icone : uniquement des atlas Blizzard natifs (aucun asset tiers)
local ICON_MASK_OPTIONS = {
  { value = 1, text = L["SETTINGS_CDM_MASK_DEFAULT"], atlas = "common-iconmask" },
  { value = 2, text = L["SETTINGS_CDM_MASK_CDM"],      atlas = "UI-HUD-CoolDownManager-Mask" },
  { value = 3, text = L["SETTINGS_CDM_MASK_CIRCLE"],   atlas = "CircleMaskScalable" },
  { value = 4, text = L["SETTINGS_CDM_MASK_HEXAGON"],  atlas = "CovenantSanctum-Renown-Hexagon-Mask" },
  { value = 5, text = L["SETTINGS_CDM_MASK_TALENT"],   atlas = "talents-node-choiceflyout-mask" },
  -- Carre plein : pas un atlas mais une texture unie, donc aucun arrondi ni fondu de
  -- bord. Utile pour verifier si un halo vient du masque ou d'une region native.
  { value = 6, text = L["SETTINGS_CDM_MASK_SQUARE"],   atlas = "Interface\\Buttons\\WHITE8X8" },
}
ns.CDM_ICON_MASK_OPTIONS = ICON_MASK_OPTIONS

ns.CDM_GRID_LAYOUT_OPTIONS = {
  { value = 1, text = L["SETTINGS_CDM_GRID_CENTERED"] },
  { value = 2, text = L["SETTINGS_CDM_GRID_STANDARD"] },
  { value = 3, text = L["SETTINGS_CDM_GRID_STANDARD_KEEPEMPTY"] },
}
ns.CDM_HIDE_INACTIVE_OPTIONS = {
  { value = 1, text = L["SETTINGS_CDM_HIDE_NEVER"] },
  { value = 2, text = L["SETTINGS_CDM_HIDE_UNLESS_AURA"] },
  { value = 3, text = L["SETTINGS_CDM_HIDE_UNLESS_ACTIVE"] },
}

-- Texture ou atlas
local function SetTextureOrAtlas(region, texture, useAtlasSize)
  if not region then return end
  if not texture or texture == "" then region:SetTexture(nil); return end
  if C_Texture.GetAtlasInfo(texture) then
    region:SetAtlas(texture, useAtlasSize or false)
  else
    region:SetTexture(texture)
  end
end

-- BORDURE D'ICONE : quatre textures ancrees, PAS un frame "BackdropTemplate".
--
-- Depuis le patch 12.x, la taille des frames du Cooldown Viewer est une valeur secrete.
-- Un frame BackdropTemplate ancre dessus en herite, et le SetupTextureCoordinates de
-- Blizzard (Blizzard_SharedXML/Backdrop.lua) fait de l'arithmetique sur cette taille a
-- chaque OnSizeChanged : sous une pile taintee par l'addon, cela leve en boucle
-- "attempt to perform arithmetic on local 'width' (a secret number value)".
-- Des textures positionnees uniquement par SetPoint sont dimensionnees par le moteur de
-- layout, sans aucun calcul Lua sur la taille : le probleme disparait a la source.
--
-- `anchorTo` : region que la bordure doit epouser. On memorise le choix sur la frame
-- pour que les rafraichissements ulterieurs (qui ne le repassent pas) gardent la meme
-- cible. Par defaut le parent, comme avant.
local function SetBorderEdgeSize(frame, borderSize, anchorTo)
  anchorTo = anchorTo or frame.__borderAnchor or frame:GetParent()
  frame.__borderAnchor = anchorTo
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, 0)
  frame:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)

  local s = (borderSize and borderSize > 0) and borderSize or 1
  -- Bords horizontaux pleine largeur, bords verticaux en retrait de l'epaisseur : les
  -- coins ne se superposent pas, donc pas de double alpha sur une couleur translucide.
  frame.__top:ClearAllPoints()
  frame.__top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.__top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
  frame.__top:SetHeight(s)

  frame.__bottom:ClearAllPoints()
  frame.__bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  frame.__bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  frame.__bottom:SetHeight(s)

  frame.__left:ClearAllPoints()
  frame.__left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -s)
  frame.__left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, s)
  frame.__left:SetWidth(s)

  frame.__right:ClearAllPoints()
  frame.__right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -s)
  frame.__right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, s)
  frame.__right:SetWidth(s)
end

local function SetBorderEdgeColor(frame, r, g, b, a)
  if not frame or not frame.__edges then return end
  for _, tex in ipairs(frame.__edges) do
    tex:SetColorTexture(r, g, b, a or 1)
  end
end

local function CreateBorder(frame, frameName, cfg)
  -- La bordure doit epouser l'ICONE. Avant, on remontait au bouton parent et on ancrait
  -- dessus : le bouton etant plus grand que son icone, le backdrop dessinait un cadre
  -- noir nettement plus large que l'icone -- tres visible a petite taille, et pris pour
  -- une "texture fantome" en plus de la bordure.
  local anchorTo = frame
  if frame:GetObjectType() == "Texture" then
    frame = frame:GetParent()
  end
  local edgeSize = (cfg.backdropSize and cfg.backdropSize > 0) and cfg.backdropSize or 1
  local border = CreateFrame("Frame", nil, frame)
  border.__top    = border:CreateTexture(nil, "OVERLAY")
  border.__bottom = border:CreateTexture(nil, "OVERLAY")
  border.__left   = border:CreateTexture(nil, "OVERLAY")
  border.__right  = border:CreateTexture(nil, "OVERLAY")
  border.__edges  = { border.__top, border.__bottom, border.__left, border.__right }
  SetBorderEdgeSize(border, edgeSize, anchorTo)
  local c = cfg.backdropColor or { 0, 0, 0, 1 }
  SetBorderEdgeColor(border, c[1], c[2], c[3], c[4] or 1)
  frame:SetClampedToScreen(false)
  return border
end

local function SetBorderColor(button, color)
  if not button or not color then return end
  if button.__iconBorder then
    SetBorderEdgeColor(button.__iconBorder, color[1], color[2], color[3], color[4] or 1)
  end
end

-- Grille de layout via GridLayoutUtil/AnchorUtil (growUp/growRight lus comme booleens Lua)
local function HideInactiveChildren(layoutChildren, keepEmpty)
  if #layoutChildren == 0 then return end
  local visible = {}
  for _, frame in ipairs(layoutChildren) do
    if frame.__isActive ~= nil then
      if frame.__isActive or frame.__isEditing or EditModeManagerFrame:IsEditModeActive() or CooldownViewerSettings:IsVisible() then
        frame:Show()
        table.insert(visible, frame)
      elseif keepEmpty then
        frame:Hide()
        table.insert(visible, frame)
      else
        frame:Hide()
      end
    else
      -- __isActive == nil : mode "ne jamais masquer" (hideWhenInactive = 1).
      if (frame:IsVisible() or frame.__shouldBeVisible) or frame.__isEditing or EditModeManagerFrame:IsEditModeActive() or CooldownViewerSettings:IsVisible() then
        if not frame:IsVisible() then frame:Show() end
        table.insert(visible, frame)
      else
        -- NE PAS appeler Hide() ici. Dans ce mode la seule source de verite est frame:IsVisible(),
        -- puisque __shouldBeVisible n'est ecrit nulle part. Masquer nous-memes une frame que Blizzard
        -- n'a pas encore montree (reacquisition du pool, changement de spec/talents) la verrouillait :
        -- au passage suivant IsVisible() etait toujours false, donc on la re-masquait, indefiniment.
        -- L'icone ne revenait plus jamais et son sort disparaissait de la barre. On se contente de ne
        -- pas l'inclure dans le layout ; Blizzard garde la main pour la reafficher.
        if keepEmpty then table.insert(visible, frame) end
      end
    end
  end
  return visible
end

-- Memo de layout. Comparer le seul NOMBRE de visibles ne suffisait pas : l'ensemble peut changer a
-- effectif constant (une icone s'eteint pendant qu'une autre s'allume). Le layout etait alors saute et
-- la frame nouvellement visible restait sur l'ancre de son passage precedent -- deux icones superposees,
-- et un trou la ou l'une des deux aurait du etre. On memorise donc l'ensemble, pas son cardinal.
local function SameVisibleSet(self, visibleChildren)
  local prev = self.__wasVisibleChildren
  if type(prev) == "table" and #prev == #visibleChildren then
    local same = true
    for i = 1, #visibleChildren do
      if prev[i] ~= visibleChildren[i] then same = false; break end
    end
    if same then return true end
  end
  local snapshot = {}
  for i = 1, #visibleChildren do snapshot[i] = visibleChildren[i] end
  self.__wasVisibleChildren = snapshot
  return false
end

local function ApplyStandardGridLayout(self, layoutChildren, stride, padding)
  if not self or not layoutChildren or #layoutChildren == 0 then return end

  local visibleChildren = HideInactiveChildren(layoutChildren, self.keepEmpty)
  if SameVisibleSet(self, visibleChildren) then return end

  local goingRight = self.__layoutFramesGoingRight
  local goingUp    = self.__layoutFramesGoingUp
  local xMultiplier = goingRight and 1 or -1
  local yMultiplier = goingUp and 1 or -1

  local layout
  if self.isHorizontal then
    layout = GridLayoutUtil.CreateStandardGridLayout(stride, padding, padding, xMultiplier, yMultiplier)
  else
    layout = GridLayoutUtil.CreateVerticalGridLayout(stride, padding, padding, xMultiplier, yMultiplier)
  end

  local anchorPoint
  if goingUp then
    anchorPoint = goingRight and "BOTTOMLEFT" or "BOTTOMRIGHT"
  else
    anchorPoint = goingRight and "TOPLEFT" or "TOPRIGHT"
  end
  GridLayoutUtil.ApplyGridLayout(visibleChildren, AnchorUtil.CreateAnchor(anchorPoint, self, anchorPoint), layout)
end

local function ApplyCenteredGridLayout(self, layoutChildren, stride, padding)
  if not self or not layoutChildren or #layoutChildren == 0 then return end

  local visibleChildren = HideInactiveChildren(layoutChildren, false)
  if SameVisibleSet(self, visibleChildren) then return end
  if #visibleChildren == 0 then return end

  stride = math.min(stride, #visibleChildren)
  local firstChild = visibleChildren[1]
  local width, height = firstChild:GetWidth(), firstChild:GetHeight()
  if width == 0 or height == 0 then width, height = 36, 36 end

  local spacing = padding
  local isHorizontal = self.isHorizontal
  local goingRight = self.__layoutFramesGoingRight
  local goingUp    = self.__layoutFramesGoingUp

  local anchorPoint
  if isHorizontal then
    anchorPoint = goingUp and "BOTTOM" or "TOP"
  else
    anchorPoint = goingRight and "LEFT" or "RIGHT"
  end

  if isHorizontal then
    local itemStep, rowStep = width + spacing, height + spacing
    local numRows = math.ceil(#visibleChildren / stride)
    for rowIndex = 0, numRows - 1 do
      local rowStart = rowIndex * stride + 1
      local rowEnd = math.min(rowStart + stride - 1, #visibleChildren)
      local itemCount = rowEnd - rowStart + 1
      local halfWidth = (itemCount - 1) * itemStep / 2
      local startX = goingRight and -halfWidth or halfWidth
      local stepX  = goingRight and itemStep or -itemStep
      local y = rowIndex * rowStep
      if not goingUp then y = -y end
      for i = rowStart, rowEnd do
        local child = visibleChildren[i]
        local x = startX + (i - rowStart) * stepX
        child:ClearAllPoints()
        child:SetPoint(anchorPoint, self, anchorPoint, x, y)
      end
    end
  else
    local itemStep, colStep = height + spacing, width + spacing
    local numCols = math.ceil(#visibleChildren / stride)
    for colIndex = 0, numCols - 1 do
      local colStart = colIndex * stride + 1
      local colEnd = math.min(colStart + stride - 1, #visibleChildren)
      local itemCount = colEnd - colStart + 1
      local halfHeight = (itemCount - 1) * itemStep / 2
      local startY = goingUp and -halfHeight or halfHeight
      local stepY  = goingUp and itemStep or -itemStep
      local x = colIndex * colStep
      x = goingRight and x or -x
      for i = colStart, colEnd do
        local child = visibleChildren[i]
        local y = startY + (i - colStart) * stepY
        child:ClearAllPoints()
        child:SetPoint(anchorPoint, self, anchorPoint, x, y)
      end
    end
  end
end

local function ResizeLayoutGrid(frame, visibleChildren, strideOverride)
  if not frame then return end
  local layoutChildren = visibleChildren or frame:GetLayoutChildren()
  frame:SetSize(1, 1)
  if #layoutChildren == 0 then frame:SetSize(40, 40); return end

  local width, height = layoutChildren[1]:GetWidth(), layoutChildren[1]:GetHeight()
  if width == 0 or height == 0 then width, height = 40, 40 end

  local numActive = #layoutChildren
  local isHorizontal = frame.isHorizontal
  local padding = frame.__padding
  local stride = math.min(strideOverride or frame.stride, numActive)
  local numRows = math.ceil(numActive / stride)

  if isHorizontal then
    frame:SetSize((stride * width) + ((stride - 1) * padding), (numRows * height) + ((numRows - 1) * padding))
  else
    frame:SetSize((numRows * width) + ((numRows - 1) * padding), (stride * height) + ((stride - 1) * padding))
  end
end

-- Detection couleur native Blizzard (OOR/OOM/Inutilisable) par comparaison de teinte, pour savoir quel etat appliquer
local NATIVE_OOR   = { 0.64, 0.15, 0.15 }
local NATIVE_OOM   = { 0.5, 0.5, 1.0 }
local NATIVE_NOUSE = { 0.4, 0.4, 0.4 }

local function RefreshDesaturation(self)
  if not self or self.__desaturated == nil then return end
  self:GetIconTexture():SetDesaturated(self.__desaturated)
end

local function RefreshDesaturationOnCooldownOnly(self, cfg)
  if self.spellOutOfRange == true then return end
  if self.__isOnActualCooldown and cfg.useCdColor then
    self.__desaturated = cfg.cdDesaturate
  elseif self.__isOnGCD and cfg.useGcdColor then
    self.__desaturated = cfg.gcdDesaturate
  else
    if not self.__removeAura and self.__isOnAura and cfg.useAuraColor then
      self.__desaturated = cfg.auraDesaturate
    elseif cfg.useNormalColor then
      self.__desaturated = cfg.normalDesaturate
    else
      self.__desaturated = false
    end
  end
  RefreshDesaturation(self)
end

local function OnButtonRefreshIconColor(self)
  local spellID = self:GetSpellID()
  if not spellID then return end
  local frame = self:GetParent()
  local frameName = frame:GetName()
  local cfg = GetCfgFor(frameName)
  if not cfg then return end

  local iconTexture = self:GetIconTexture()
  local outOfRangeTexture = self.GetOutOfRangeTexture and self:GetOutOfRangeTexture() or nil

  local iconColor = { iconTexture:GetVertexColor() }
  for i, n in ipairs(iconColor) do iconColor[i] = RoundToSignificantDigits(n, 2) end

  local oorMatch   = iconColor[1] == NATIVE_OOR[1]   and iconColor[2] == NATIVE_OOR[2]   and iconColor[3] == NATIVE_OOR[3]
  local nouseMatch = iconColor[1] == NATIVE_NOUSE[1] and iconColor[2] == NATIVE_NOUSE[2] and iconColor[3] == NATIVE_NOUSE[3]
  local oomMatch   = iconColor[1] == NATIVE_OOM[1]   and iconColor[2] == NATIVE_OOM[2]   and iconColor[3] == NATIVE_OOM[3]

  local color = { 1, 1, 1, 1 }

  if cfg.useOorColor and oorMatch then
    color = cfg.oorColor
    if outOfRangeTexture then outOfRangeTexture:SetShown(false) end
    self.__desaturated = cfg.oorDesaturate
  elseif self.__isOnActualCooldown and cfg.useCdColor then
    color = cfg.cdColor
    self.__desaturated = cfg.cdDesaturate
  elseif self.__isOnGCD and cfg.useGcdColor then
    color = cfg.gcdColor
    self.__desaturated = cfg.gcdDesaturate
  else
    if cfg.useNouseColor and nouseMatch then
      color = cfg.nouseColor
      self.__desaturated = cfg.nouseDesaturate
    elseif cfg.useOomColor and oomMatch then
      color = cfg.oomColor
      self.__desaturated = cfg.oomDesaturate
    else
      if not self.__removeAura and self.__isOnAura and cfg.useAuraColor then
        color = cfg.auraColor
        self.__desaturated = cfg.auraDesaturate
      elseif cfg.useNormalColor then
        color = cfg.normalColor
        self.__desaturated = cfg.normalDesaturate
      else
        self.__desaturated = false
      end
    end
  end

  iconTexture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
  RefreshDesaturation(self)
end

-- Forward : CheckItemVisibility est defini plus bas (avec le layout), mais les callbacks de fin de
-- cooldown ci-dessous doivent pouvoir le rappeler.
local CheckItemVisibility

-- Recalcule __isActive puis redemande un layout. Indispensable a la FIN d'un cooldown : les drapeaux
-- (__isOnActualCooldown / __isOnAura / __cooldownSet) etaient bien remis a false, mais __isActive, lui,
-- n'etait recalcule que depuis le hook RefreshData -- c'est-a-dire au prochain rafraichissement spontane
-- de Blizzard. D'ou l'icone qui restait affichee 10 a 20 s apres que le sort soit redisponible, alors que
-- l'animation "pret" avait deja joue. RefreshLayoutGrid est memoise (SameVisibleSet) : no-op si rien n'a
-- bouge, donc l'appeler ici ne coute rien quand l'icone etait deja dans le bon etat.
local function RefreshItemVisibility(button)
  if not CheckItemVisibility or not button then return end
  CheckItemVisibility(button)
  local bar = button:GetParent()
  if bar and bar.RefreshLayoutGrid then bar:RefreshLayoutGrid() end
end

-- Etat de cooldown (CD / GCD / aura / pandemie)
local function CheckCooldownState(button)
  if not button.cooldownUseAuraDisplayTime or button.__removeAura then
    if button.isOnGCD and not button.isOnActualCooldown then
      button.__isOnGCD = true
    else
      button.__isOnActualCooldown = not button.wasSetFromCharges
    end
  end
end

local function Hook_OnCooldownDone(self)
  local button = self:GetParent()
  if not button.__cooldownSet then return end
  local bar = button:GetParent()
  local cfg = GetCfgFor(bar:GetName())
  if not cfg then return end

  button.__cooldownSet = nil
  button.__isOnGCD = false
  button.__isOnActualCooldown = false
  button.__isOnAura = false

  RefreshDesaturationOnCooldownOnly(button, cfg)
  if cfg.useBackdrop then SetBorderColor(button, cfg.backdropColor) end
  RefreshItemVisibility(button)
end

local function OnCooldownClear(cooldownFrame, button)
  if not cooldownFrame or not button or not button.__cooldownSet then return end
  local bar = button:GetParent()
  local cfg = GetCfgFor(bar and bar:GetName())
  if not cfg then return end

  button.__cooldownSet = nil
  button.__isOnGCD = false
  button.__isOnActualCooldown = false
  button.__isOnAura = false

  if cfg.useBackdrop then SetBorderColor(button, cfg.backdropColor) end
  RefreshItemVisibility(button)
end

local function OnCooldownSet(cooldownFrame, button)
  if not cooldownFrame or not button then return end
  local barFrame = button:GetParent()
  local barName = barFrame:GetName()
  local cfg = GetCfgFor(barName)
  if not cfg or not cfg.enabled then return end

  button.__cooldownSet = true
  button.__isOnActualCooldown = false
  if not button.__cooldownDoneHooked then
    cooldownFrame:HookScript("OnCooldownDone", Hook_OnCooldownDone)
    button.__cooldownDoneHooked = true
  end

  button.__removeAura = cfg.auraRemoveSwipe

  if button.cooldownUseAuraDisplayTime or button.pandemicAlertTriggerTime then
    button.__isOnAura = not button.__removeAura
    cooldownFrame:SetHideCountdownNumbers(false)

    if button.__removeAura then
      local duration = C_Spell.GetSpellChargeDuration(button:GetSpellID()) or C_Spell.GetSpellCooldownDuration(button:GetSpellID())
      cooldownFrame:SetUseAuraDisplayTime(false)
      cooldownFrame:Clear()
      if cfg.useCooldownColor then cooldownFrame:SetSwipeColor(unpack(cfg.cooldownColor)) end
      cooldownFrame:SetCooldownFromDurationObject(duration, true)
      CheckCooldownState(button)
    end

    if not button.__removeAura and cfg.useCooldownAuraColor then
      cooldownFrame:SetSwipeColor(unpack(cfg.cooldownAuraColor))
    end
    if not button.__removeAura and cfg.useBackdropAuraColor and not button.__isInPandemic then
      SetBorderColor(button, cfg.backdropAuraColor)
    end
  else
    button.__isOnAura = false
    if cfg.useCooldownColor then cooldownFrame:SetSwipeColor(unpack(cfg.cooldownColor)) end
    if cfg.useBackdrop then SetBorderColor(button, cfg.backdropColor) end

    CheckCooldownState(button)

    if (button.isOnGCD and not button.isOnActualCooldown and not button.wasSetFromCharges) and cfg.removeGCDSwipe then
      cooldownFrame:Clear()
    end
    if button.wasSetFromCharges then
      cooldownFrame:SetHideCountdownNumbers(not cfg.showCountdownNumbersForCharges)
    end
  end

  CDME.RefreshCooldownFrame(button, barName, cfg)
  -- Reassert position du decompte : Blizzard peut re-ancrer sa fontstring a
  -- chaque redemarrage de cooldown (cf. commentaire sur RefreshCooldownFont)
  if button.Cooldown then CDME.RefreshCooldownFont(button, cfg) end
  -- Pendant du couple Hook_OnCooldownDone / OnCooldownClear : le cooldown vient de demarrer, donc
  -- l'icone doit apparaitre tout de suite en mode "masquer sauf si actif", sans attendre le prochain
  -- RefreshData de Blizzard.
  RefreshItemVisibility(button)
end

local function OnRefreshCooldownInfo(button)
  local barFrame = button:GetParent()
  local barName = barFrame:GetName()
  local cfg = GetCfgFor(barName)
  if not cfg then return end
  local cooldownFrame = button:GetCooldownFrame()
  if not cooldownFrame then return end

  if not button.__isOnAura and cfg.useCooldownAuraColor then
    cooldownFrame:SetSwipeColor(unpack(cfg.cooldownAuraColor))
  end
  if not button.__isOnAura and cfg.useCooldownColor then
    cooldownFrame:SetSwipeColor(unpack(cfg.cooldownColor))
  end
end

-- Pandemie (flash de renouvellement de buff/debuff)
local function IterateAllAnimationGroups(frame, func)
  local animGroups = { frame:GetAnimationGroups() }
  for _, animGroup in ipairs(animGroups) do func(animGroup) end
  local children = { frame:GetChildren() }
  for _, child in ipairs(children) do IterateAllAnimationGroups(child, func) end
end

local function Hook_SetupPandemic(self, frame)
  if not frame then return end
  local button = frame:GetParent()
  local cfg = GetCfgFor(button:GetParent():GetName())
  if not cfg or not cfg.enabled then return end

  if not button.__isInPandemic then
    if cfg.removePandemic and not frame.__pandemicRemoved then
      frame.Border.Border:SetTexture("")
      IterateAllAnimationGroups(frame, function(g) if g then g:RemoveAnimations() end end)
      frame.FX:Hide()
      frame.__pandemicRemoved = true
    end
    if cfg.useBackdropPandemicColor then
      SetBorderColor(button, cfg.backdropPandemicColor)
    end
    button.__isInPandemic = true
  end
end

local function Hook_HidePandemic(self, frame)
  local button = frame:GetParent()
  local cfg = GetCfgFor(button:GetParent():GetName())
  if not cfg or not cfg.enabled then return end

  if button.__isInPandemic then
    if not button.__hidePandemicScheduled then
      button.__hidePandemicScheduled = true
      C_Timer.After(0, function()
        button.__hidePandemicScheduled = false
        if button.PandemicIcon and button.PandemicIcon:IsVisible() then return end
        if cfg.useBackdrop then SetBorderColor(button, cfg.backdropColor) end
        button.__isInPandemic = nil
      end)
    end
  end
end

-- Personnalisation par bouton : taille, masque, police cooldown/stacks, swipe
function CDME.RefreshItemSize(child, cfg)
  local size = cfg.itemSize
  child:SetSize(size, size)
  if not child.__scaleHooked and child.SetScale then
    hooksecurefunc(child, "SetScale", function(f, scale) if scale ~= 1 then f:SetScale(1) end end)
    child.__scaleHooked = true
    child:SetScale(1)
  end
end

-- Contour natif du bouton CDM. /cdmregions le revele : sur un bouton de 28x28, cette
-- texture OVERLAY mesure 46x44 -- elle deborde donc largement de l'icone et se lit comme
-- un halo noir, d'autant plus visible que les icones sont petites. Elle n'a rien a voir
-- avec le masque (la forme) ni avec notre bordure, d'ou l'impression de "texture fantome".
-- Toujours masquee : ce halo n'a aucun cas d'usage, il n'y a donc plus de reglage.
local NATIVE_ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"

function CDME.RefreshIconOverlay(child)
  for _, r in ipairs({ child:GetRegions() }) do
    local ok, typ = pcall(r.GetObjectType, r)
    if ok and typ == "Texture" then
      local okA, atlas = pcall(r.GetAtlas, r)
      if okA and atlas == NATIVE_ICON_OVERLAY_ATLAS then
        -- SetAlpha plutot que Hide : Blizzard reaffiche la region a ses propres refresh,
        -- et un Hide perdu laisserait le halo revenir jusqu'au prochain Layout.
        r:SetAlpha(0)
      end
    end
  end
end

function CDME.RefreshIconMask(child, cfg)
  local opt = ICON_MASK_OPTIONS[cfg.iconMaskIndex] or ICON_MASK_OPTIONS[1]
  local icon = child.Icon
  local mask = icon:GetMaskTexture(1)
  if mask then
    mask:SetHorizTile(false)
    mask:SetVertTile(false)
    SetTextureOrAtlas(mask, opt.atlas)
  end
end

function CDME.RefreshCooldownFrame(child, frameName, cfg)
  local cooldownFrame = child.Cooldown
  if not cooldownFrame then return end
  if not child.__removeAura and child.__isOnAura then
    cooldownFrame:SetReverse(cfg.auraReverseSwipe)
  else
    cooldownFrame:SetReverse(cfg.reverseSwipe)
  end
end

-- Le widget Cooldown natif peut re-ancrer sa fontstring de decompte a chaque cooldown/GCD, d'ou le rappel depuis OnCooldownSet
function CDME.RefreshCooldownFont(child, cfg)
  local color = cfg.useCooldownFontColor and cfg.cooldownFontColor or { 1, 1, 1, 1 }
  local fontSize = (cfg.useCooldownFontSize and cfg.cooldownFontSize) or 17
  local fontPath = cfg.cooldownFont or ns.Media.font

  local fontName = "AishCoreCDMCooldownFont_" .. tostring(child:GetParent():GetName())
  local fontObj = _G[fontName]
  if not fontObj then
    fontObj = CreateFont(fontName)
  end
  fontObj:SetFont(fontPath, fontSize, "OUTLINE")
  fontObj:SetTextColor(color[1], color[2], color[3], color[4] or 1)

  child.Cooldown:SetCountdownFont(fontName)

  local timerString = child.Cooldown:GetCountdownFontString()
  if timerString then
    local point = cfg.cooldownPoint or "CENTER"
    timerString:ClearAllPoints()
    timerString:SetPoint(point, child.Cooldown, point, cfg.cooldownOffsetX or 0, cfg.cooldownOffsetY or 0)
  end
end

-- Stacks : child.Applications.Applications (compteur de stacks d'aura)
function CDME.RefreshStacksFont(child, cfg)
  local stacksFrame = child.Applications
  local stacksString = stacksFrame and stacksFrame.Applications
  if not stacksString then return end

  local fontPath = cfg.stacksFont or ns.Media.font
  local fontSize = (cfg.useStacksFontSize and cfg.stacksFontSize) or 16
  stacksString:SetFont(fontPath, fontSize, "OUTLINE")
  if cfg.useStacksColor then
    local c = cfg.stacksColor
    stacksString:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  end

  local point = cfg.stacksPoint or "BOTTOMRIGHT"
  stacksString:SetWidth(0)
  stacksString:ClearAllPoints()
  stacksString:SetPoint(point, stacksString:GetParent(), point, cfg.stacksOffsetX or 0, cfg.stacksOffsetY or 0)
end

-- Charges : child.ChargeCount.Current (compteur de charges de sort)
function CDME.RefreshChargesFont(child, cfg)
  local chargesFrame = child.ChargeCount
  local chargesString = chargesFrame and chargesFrame.Current
  if not chargesString then return end

  local fontPath = cfg.chargesFont or ns.Media.font
  local fontSize = (cfg.useChargesFontSize and cfg.chargesFontSize) or 16
  chargesString:SetFont(fontPath, fontSize, "OUTLINE")
  if cfg.useChargesColor then
    local c = cfg.chargesColor
    chargesString:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  end

  local point = cfg.chargesPoint or "BOTTOMRIGHT"
  chargesString:SetWidth(0)
  chargesString:ClearAllPoints()
  chargesString:SetPoint(point, chargesString:GetParent(), point, cfg.chargesOffsetX or 0, cfg.chargesOffsetY or 0)
end

-- Fondu (fading) : opacite du viewer selon combat/cible/incantation/survol souris (SetAlpha, jamais bloque en combat)
local FADE_DURATION = 0.25

local Fader = CreateFrame("Frame")
Fader.Frames = {}
Fader.interval = 0.025

local function FadingOnUpdate(_, elapsed)
  Fader.timer = (Fader.timer or 0) + elapsed
  if Fader.timer <= Fader.interval then return end
  Fader.timer = 0

  for frame, data in next, Fader.Frames do
    if frame:IsVisible() then
      data.fadeTimer = (data.fadeTimer or 0) + (elapsed + Fader.interval)
    else
      data.fadeTimer = (data.fadeTimer or 0) + 1
    end

    if data.fadeTimer < data.duration then
      if data.mode == "IN" then
        frame:SetAlpha((data.fadeTimer / data.duration) * data.diffAlpha + data.fromAlpha)
      else
        frame:SetAlpha(((data.duration - data.fadeTimer) / data.duration) * data.diffAlpha + data.toAlpha)
      end
    else
      frame:SetAlpha(data.toAlpha)
      Fader.Frames[frame] = nil
    end
  end
  if not next(Fader.Frames) then
    Fader:SetScript("OnUpdate", nil)
  end
end

local function FrameFade(frame)
  local fade = frame.__fade
  frame:SetAlpha(fade.fromAlpha)
  Fader.Frames[frame] = fade
  if not Fader:GetScript("OnUpdate") then
    Fader:SetScript("OnUpdate", FadingOnUpdate)
  end
end

local function FrameFadeIn(frame, duration, fromAlpha, toAlpha)
  frame.__fade = frame.__fade or {}
  frame.__fade.mode, frame.__fade.duration = "IN", duration
  frame.__fade.fromAlpha, frame.__fade.toAlpha = fromAlpha, toAlpha
  frame.__fade.diffAlpha, frame.__fade.fadeTimer = toAlpha - fromAlpha, nil
  FrameFade(frame)
end

local function FrameFadeOut(frame, duration, fromAlpha, toAlpha)
  frame.__fade = frame.__fade or {}
  frame.__fade.mode, frame.__fade.duration = "OUT", duration
  frame.__fade.fromAlpha, frame.__fade.toAlpha = fromAlpha, toAlpha
  frame.__fade.diffAlpha, frame.__fade.fadeTimer = fromAlpha - toAlpha, nil
  FrameFade(frame)
end

local function SetFrameAlpha(frame, toAlpha)
  -- Un fondu deja en route vers CETTE cible ne doit pas etre relance : FrameFade remet
  -- l'alpha a fromAlpha et repart de zero. Rappele plus vite que FADE_DURATION (ce qui
  -- arrive des que Blizzard relayoute souvent), le fondu ne se terminait jamais et
  -- l'alpha restait bloque pres de sa valeur de depart -- le viewer paraissait donc
  -- rester allume, comme si les bascules de fondu etaient ignorees.
  local inFlight = Fader.Frames[frame]
  if inFlight and inFlight.toAlpha == toAlpha then return end
  local currentAlpha = frame:GetAlpha()
  if toAlpha == currentAlpha then
    Fader.Frames[frame] = nil   -- deja a la bonne opacite : purge un fondu obsolete
    return
  end
  if toAlpha > currentAlpha then
    FrameFadeIn(frame, FADE_DURATION, currentAlpha, toAlpha)
  else
    FrameFadeOut(frame, FADE_DURATION, currentAlpha, toAlpha)
  end
end

local function ShouldFadeIn(cfg, isHover)
  -- "Cible selectionnee" suit la regle commune ns.ShouldShowForTargetMode : en combat
  -- meme sans cible, hors combat seulement sur cible attaquable, et sans condition de
  -- cible hors combat en spe de soin.
  return (cfg.fadeInCombat and UnitAffectingCombat("player"))
    or (cfg.fadeOnTarget and ns.ShouldShowForTargetMode())
    or (cfg.fadeOnCasting and (UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil))
    or (cfg.fadeOnHover and isHover)
    or false
end

local _isHovered = {}  -- [frameName] = true/nil, mis a jour par le hover par bouton

local function RefreshFade(frameName)
  local frame = _G[frameName]
  local cfg = GetCfgFor(frameName)
  if not frame or not cfg or not cfg.enabled then return end

  if not cfg.useFading then
    if frame:GetAlpha() ~= 1 then SetFrameAlpha(frame, 1) end
    return
  end

  if ShouldFadeIn(cfg, _isHovered[frameName]) then
    SetFrameAlpha(frame, 1)
  else
    SetFrameAlpha(frame, cfg.fadeAlpha or 0.35)
  end
end

local function RefreshFadeAll()
  for _, frameName in ipairs(VIEWER_NAMES) do RefreshFade(frameName) end
end

-- Veille legere : Blizzard repositionne/reaffiche ses viewers et remet leur opacite a 1
-- en dehors de tout evenement que l'on ecoute. On reaffirme donc la cible periodiquement.
-- Sans risque de relancer un fondu en boucle : SetFrameAlpha ignore une cible deja en
-- cours et purge un fondu obsolete quand l'opacite est deja bonne.
C_Timer.NewTicker(0.2, function()
  for _, frameName in ipairs(VIEWER_NAMES) do
    local cfg = GetCfgFor(frameName)
    if cfg and cfg.enabled and cfg.useFading then RefreshFade(frameName) end
  end
end)

local fadeEventFrame = CreateFrame("Frame")
fadeEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
fadeEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
fadeEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
fadeEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
fadeEventFrame:RegisterUnitEvent("UNIT_FACTION", "target")
fadeEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
fadeEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
fadeEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
fadeEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
fadeEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
fadeEventFrame:SetScript("OnEvent", RefreshFadeAll)

-- Layout principal (hook sur Layout du viewer)
local _forced = nil

function CheckItemVisibility(child)
  if child.__hideType == 3 then
    child.__isActive = (child.__isOnActualCooldown or child.__isOnAura or child.wasSetFromCharges) and true or false
  elseif child.__hideType == 2 then
    child.__isActive = child.__isOnAura and true or false
  elseif child.__hideType == 1 then
    child.__isActive = nil
  end
end

local function Hook_Layout(self)
  if self.__locked then return end
  self.__locked = true

  local frameName = self:GetName()
  local cfg = GetCfgFor(frameName)
  if not cfg or not cfg.enabled then self.__locked = false; return end

  local forceUpdate = _forced == frameName

  -- Toujours resynchronise depuis cfg (2 booleens, cout negligeable) --
  -- pas besoin de cache "premiere lecture seulement" ici.
  self.__layoutFramesGoingUp    = cfg.growUp
  self.__layoutFramesGoingRight = cfg.growRight
  self.__padding = self.childXPadding or self.childYPadding
  self.gridLayoutType = cfg.gridLayoutType

  -- Blizzard remet l'alpha du viewer a 1 lors de ses propres mises a jour (relayout,
  -- changement de sort/aura...). Sans cette reapplication, le fondu etait perdu et la
  -- barre restait visible jusqu'a ce qu'un survol rappelle RefreshFade.
  RefreshFade(frameName)

  local layoutChildren = self:GetLayoutChildren()
  if not self:ShouldUpdateLayout(layoutChildren) then self.__locked = false; return end

  -- PRE-PASSE de visibilite, separee de la customisation ci-dessous, et volontairement AVANT elle.
  -- Deux raisons :
  --  1. Evaluer __isActive tout de suite, sans attendre le hook RefreshData de chaque enfant. Sur une
  --     frame fraichement acquise (typiquement apres un /reload) il valait encore nil, et
  --     HideInactiveChildren retombe alors sur le mode "ne jamais masquer" : la regle hideWhenInactive
  --     ne s'appliquait pas et tout ce que Blizzard affichait a cet instant restait visible.
  --  2. La boucle de customisation s'interrompt (`return`) au premier enfant en donnees Edit Mode.
  --     Tous les enfants SUIVANTS restaient alors sans __hideType ni __isActive, donc en "ne jamais
  --     masquer" a vie -- l'icone fantome qui ne disparaissait que le jour ou Blizzard recyclait sa
  --     frame pour un vrai cooldown. La pre-passe, elle, ne saute jamais personne.
  -- Les drapeaux de cooldown sont nil a ce stade, donc on part masque et on se devoile des qu'un
  -- cooldown demarre (cf. RefreshItemVisibility dans OnCooldownSet).
  for _, child in ipairs(layoutChildren) do
    child.__hideType = cfg.hideWhenInactive
    CheckItemVisibility(child)
  end

  for _, child in ipairs(layoutChildren) do
    if child:HasEditModeData() then self.__locked = false; return end

    if not child.__hooked then
      if child.RefreshData then hooksecurefunc(child, "RefreshData", function(c)
        local parent = c:GetParent()
        local pcfg = GetCfgFor(parent:GetName())
        if not pcfg or not pcfg.enabled then return end
        CheckItemVisibility(c)
        if parent.RefreshLayoutGrid then parent:RefreshLayoutGrid() end
      end) end
      if child.Cooldown and child.Cooldown.SetCooldown then
        hooksecurefunc(child.Cooldown, "SetCooldown", function(cd) OnCooldownSet(cd, child) end)
        hooksecurefunc(child.Cooldown, "Clear", function(cd) OnCooldownClear(cd, child) end)
      end
      if child.RefreshCooldownInfo then hooksecurefunc(child, "RefreshCooldownInfo", OnRefreshCooldownInfo) end
      if child.RefreshSpellCooldownInfo then hooksecurefunc(child, "RefreshSpellCooldownInfo", OnRefreshCooldownInfo) end
      -- Re-affirmation de la decision au moment meme du Show. Nos Hide() ne se produisent que pendant
      -- une passe de layout ; Blizzard, lui, peut rappeler Show() sur l'item APRES cette passe (le hook
      -- RefreshData tourne quand RefreshData rend la main, mais le viewer reaffiche parfois l'item
      -- ensuite). Le Hide() etait alors ecrase, sans qu'aucune nouvelle passe ne vienne le retablir :
      -- l'icone restait affichee jusqu'a ce qu'un vrai cooldown declenche un layout. C'est exactement
      -- l'etat observe au diagnostic -- IsShown=true avec __isActive=false.
      -- Strictement borne a __isActive == false (donc hideWhenInactive 2 ou 3, sort inactif) : en mode
      -- "ne jamais masquer" __isActive vaut nil et ce hook ne fait rien. Memes echappatoires Edit Mode
      -- que HideInactiveChildren. Hide() ne declenche pas OnShow, donc pas de boucle.
      child:HookScript("OnShow", function(c)
        if c.__isActive == false
           and not c.__isEditing
           and not EditModeManagerFrame:IsEditModeActive()
           and not CooldownViewerSettings:IsVisible() then
          c:Hide()
        end
      end)
      child.__hooked = true
    end

    if not child.__fadeHooked then
      child:HookScript("OnEnter", function()
        _isHovered[frameName] = true
        RefreshFade(frameName)
      end)
      child:HookScript("OnLeave", function()
        _isHovered[frameName] = nil
        RefreshFade(frameName)
      end)
      child.__fadeHooked = true
    end

    if not child.__refreshIconHook then
      if child.RefreshIconColor then hooksecurefunc(child, "RefreshIconColor", OnButtonRefreshIconColor) end
      if child.RefreshIconDesaturation then hooksecurefunc(child, "RefreshIconDesaturation", RefreshDesaturation) end
      child.__refreshIconHook = true
    end

    if cfg.useBackdrop then
      if child.Icon and not child.__iconBorder then
        child.__iconBorder = CreateBorder(child.Icon, frameName, cfg)
        child.__iconBorder:Show()
      elseif child.Icon and child.__iconBorder then
        if forceUpdate then
          SetBorderEdgeSize(child.__iconBorder, cfg.backdropSize)
          local bc = cfg.backdropColor
          SetBorderEdgeColor(child.__iconBorder, bc[1], bc[2], bc[3], bc[4] or 1)
        end
        child.__iconBorder:Show()
      end
    elseif child.__iconBorder then
      child.__iconBorder:Hide()
      child.__iconBorder = nil
    end

    if child.Cooldown and (not child.__cooldownFontSet or forceUpdate) then
      CDME.RefreshCooldownFont(child, cfg)
      child.__cooldownFontSet = true
    end

    if child.Applications and child.Applications.Applications and (not child.__stacksFontSet or forceUpdate) then
      CDME.RefreshStacksFont(child, cfg)
      child.__stacksFontSet = true
    end

    if child.ChargeCount and child.ChargeCount.Current and (not child.__chargesFontSet or forceUpdate) then
      CDME.RefreshChargesFont(child, cfg)
      child.__chargesFontSet = true
    end

    if cfg.useItemSize and (not child.__sizeHooked or forceUpdate) then
      CDME.RefreshItemSize(child, cfg)
      child.__sizeHooked = true
    end

    -- Reapplique a CHAQUE passage (pas de cache) : Blizzard remet l'alpha de sa texture
    -- a 1 lors de ses propres rafraichissements.
    CDME.RefreshIconOverlay(child)

    if cfg.iconMaskIndex and cfg.iconMaskIndex > 1 and (not child.__iconMaskSet or forceUpdate) then
      CDME.RefreshIconMask(child, cfg)
      child.__iconMaskSet = true
    end
  end

  if #layoutChildren == 0 then _forced = nil; self.__locked = false; return end

  self.keepEmpty = self.gridLayoutType == 3
  self.__wasVisibleChildren = nil

  if not self.RefreshLayoutGrid then
    self.RefreshLayoutGrid = function(frame)
      local children = frame:GetLayoutChildren()
      -- Ne jamais ecrire sur frame.stride (champ natif) : ca taint le frame et casse CheckAuraAddedAlertTriggers
      local fcfg = GetCfgFor(frame:GetName())
      local strideOverride = fcfg and fcfg.strideOverride and fcfg.strideOverride > 0 and fcfg.strideOverride or nil
      local stride = strideOverride or frame.stride
      local padding = frame.__padding
      if frame.gridLayoutType == 1 then
        ApplyCenteredGridLayout(frame, children, stride, padding)
      else
        ApplyStandardGridLayout(frame, children, stride, padding)
      end
      if not InCombatLockdown() then ResizeLayoutGrid(frame, children, strideOverride) end
      frame:CacheLayoutSettings(children)
    end
  end

  self:RefreshLayoutGrid()
  self.__locked = false
  _forced = nil
end

-- Liaison a la barre de vie du joueur (cfg.linkToPlayerBar) : le viewer est repositionne contre un bord
-- de la barre, en coordonnees UIParent calculees par UnitBars.GetPlayerBarRect, et re-cale a chaque
-- changement de la barre (UnitBars.NotifyPlayerBarMoved). Jamais ANCRE sur la barre : c'est un
-- SecureUnitButton, et un frame ancre sur un frame protege devient protege a son tour (le layout
-- Blizzard du viewer serait alors bloque en combat).
-- Cote de la barre joueur -> point du viewer qui vient s'y coller (donc le point OPPOSE).
local LINK_VIEWER_POINT = {
  RIGHT = "LEFT", LEFT = "RIGHT", TOP = "BOTTOM", BOTTOM = "TOP",
  -- Coins : le viewer se pose en diagonale a l'exterieur du coin vise.
  TOPLEFT     = "BOTTOMRIGHT", TOPRIGHT    = "BOTTOMLEFT",
  BOTTOMLEFT  = "TOPRIGHT",    BOTTOMRIGHT = "TOPLEFT",
}
local _linkApplying = false
local _linkActive = {}   -- [frameName] = true tant que la position est pilotee par la liaison
local _linkPending = false

local function ApplyPlayerBarLink(frameName)
  local viewer = _G[frameName]
  if not viewer then return end
  local cfg = GetCfgFor(frameName)
  if not (cfg and cfg.enabled and cfg.linkToPlayerBar) then
    -- Liaison retiree : rend la main a la position Edit Mode
    if _linkActive[frameName] and not InCombatLockdown() then
      _linkActive[frameName] = nil
      if viewer.ApplySystemAnchor then pcall(viewer.ApplySystemAnchor, viewer) end
    end
    return
  end
  -- En Edit Mode, on laisse Blizzard deplacer le viewer ; recale a la sortie (hook OnHide plus bas)
  if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then return end
  if InCombatLockdown() then _linkPending = true; return end

  local UB = ns.Modules and ns.Modules.UnitBars
  if not (UB and UB.GetPlayerBarRect) then return end
  local l, r, b, t = UB.GetPlayerBarRect()
  if not l then return end

  local side = LINK_VIEWER_POINT[cfg.linkSide] and cfg.linkSide or "RIGHT"
  local gap, off = cfg.linkGap or 4, cfg.linkOffset or 0
  local x, y
  if side == "RIGHT" then        x, y = r + gap, (b + t) / 2 + off
  elseif side == "LEFT" then     x, y = l - gap, (b + t) / 2 + off
  elseif side == "TOP" then      x, y = (l + r) / 2 + off, t + gap
  elseif side == "BOTTOM" then   x, y = (l + r) / 2 + off, b - gap
  -- Coins : pas de perpendiculaire unique en diagonale, `off` decale horizontalement.
  elseif side == "TOPLEFT" then     x, y = l - gap + off, t + gap
  elseif side == "TOPRIGHT" then    x, y = r + gap + off, t + gap
  elseif side == "BOTTOMLEFT" then  x, y = l - gap + off, b - gap
  else                              x, y = r + gap + off, b - gap end

  -- Offsets de SetPoint exprimes dans l'echelle du viewer
  local scale = viewer:GetScale()
  if not scale or scale == 0 then scale = 1 end
  _linkApplying = true
  pcall(function()
    viewer:ClearAllPoints()
    viewer:SetPoint(LINK_VIEWER_POINT[side], UIParent, "CENTER", x / scale, y / scale)
  end)
  _linkApplying = false
  _linkActive[frameName] = true
end

function CDME.RefreshPlayerBarLink()
  for _, frameName in ipairs(VIEWER_NAMES) do ApplyPlayerBarLink(frameName) end
end

-- Setup (hooks une seule fois, hors combat)
local _hooksSet = {}

local function SetHooksFor(frameName)
  if _hooksSet[frameName] then return end
  local frame = _G[frameName]
  if not frame then return end

  if frame.Layout then
    hooksecurefunc(frame, "Layout", Hook_Layout)
    frame:Layout()
  end
  if frame.AnchorPandemicStateFrame then
    hooksecurefunc(frame, "AnchorPandemicStateFrame", Hook_SetupPandemic)
  end
  if frame.HidePandemicStateFrame then
    hooksecurefunc(frame, "HidePandemicStateFrame", Hook_HidePandemic)
  end
  -- Edit Mode reapplique sa propre ancre (chargement/changement de layout) : on recale derriere lui
  hooksecurefunc(frame, "SetPoint", function()
    if _linkApplying then return end
    local cfg = GetCfgFor(frameName)
    if cfg and cfg.enabled and cfg.linkToPlayerBar then
      C_Timer.After(0, function() ApplyPlayerBarLink(frameName) end)
    end
  end)
  _hooksSet[frameName] = true
  RefreshFade(frameName)
end

local function ForceUpdate(frameName)
  local frame = _G[frameName]
  if not frame or not frame.Layout then return end
  _forced = frameName
  frame:Layout()
  _forced = nil
end

-- Reapplique les reglages en live (appele par le panneau de reglages via LiveApply)
function CDME.ApplySettings()
  for _, frameName in ipairs(VIEWER_NAMES) do
    SetHooksFor(frameName)
    if not InCombatLockdown() then
      ForceUpdate(frameName)
    end
    RefreshFade(frameName)
  end
  CDME.RefreshPlayerBarLink()
end

-- Debug : /cdmregions, liste TOUTES les regions du 1er bouton d'un viewer avec leur
-- texture/atlas, taille et calque. Sert a identifier une texture native non geree par
-- l'addon (halo, ombre, cadre) que ni la bordure ni le masque n'expliquent.
SLASH_CDMREGIONS1 = "/cdmregions"
SlashCmdList["CDMREGIONS"] = function()
  local function p(m) DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[CDMRegions]|r " .. tostring(m)) end
  for _, frameName in ipairs(VIEWER_NAMES) do
    local frame = _G[frameName]
    local kids = frame and frame.GetLayoutChildren and frame:GetLayoutChildren()
    local child = kids and kids[1]
    if child then
      p(frameName .. " -> 1er bouton : " .. tostring(child:GetName() or "(sans nom)")
        .. string.format("  taille=%.0fx%.0f", child:GetWidth(), child:GetHeight()))
      for _, r in ipairs({ child:GetRegions() }) do
        local ok, typ = pcall(r.GetObjectType, r)
        if ok and typ == "Texture" then
          local atlas = r.GetAtlas and r:GetAtlas() or nil
          local tex   = r.GetTexture and r:GetTexture() or nil
          p(string.format("   [%s] shown=%s alpha=%.2f taille=%.0fx%.0f atlas=%s tex=%s",
            tostring(r:GetDrawLayer()), tostring(r:IsShown()), r:GetAlpha(),
            r:GetWidth(), r:GetHeight(), tostring(atlas), tostring(tex)))
        end
      end
      -- Sous-frames (Cooldown, Border, FX...) : leurs textures aussi
      for _, sub in ipairs({ child:GetChildren() }) do
        p(string.format("   sous-frame %s shown=%s alpha=%.2f taille=%.0fx%.0f",
          tostring(sub:GetName() or "(sans nom)"), tostring(sub:IsShown()), sub:GetAlpha(),
          sub:GetWidth(), sub:GetHeight()))
        for _, r in ipairs({ sub:GetRegions() }) do
          local ok, typ = pcall(r.GetObjectType, r)
          if ok and typ == "Texture" and r:IsShown() then
            local atlas = r.GetAtlas and r:GetAtlas() or nil
            p(string.format("      [%s] alpha=%.2f atlas=%s tex=%s",
              tostring(r:GetDrawLayer()), r:GetAlpha(), tostring(atlas),
              tostring(r.GetTexture and r:GetTexture())))
          end
        end
      end
      return
    end
  end
  p("aucun bouton trouve (viewers vides ou CDM non charge)")
end

-- Init
local _editModeHooked = false
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
initFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
initFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if _linkPending then _linkPending = false; CDME.RefreshPlayerBarLink() end
    return
  end
  for _, frameName in ipairs(VIEWER_NAMES) do
    SetHooksFor(frameName)
  end
  if not _editModeHooked and EditModeManagerFrame then
    EditModeManagerFrame:HookScript("OnHide", function() CDME.RefreshPlayerBarLink() end)
    _editModeHooked = true
  end
  -- Differe : laisse Edit Mode et UnitBars poser leurs positions avant de recaler
  C_Timer.After(0.5, CDME.RefreshPlayerBarLink)
end)

-- /cdmdbg : diagnostic -- etat du viewer (visibilite, alpha, fading, enfants)
SLASH_CDMDBG1 = "/cdmdbg"
SlashCmdList["CDMDBG"] = function()
  local P = "|cff00ffcc[CDM-DBG]|r "
  for _, frameName in ipairs(VIEWER_NAMES) do
    local frame = _G[frameName]
    local cfg = GetCfgFor(frameName)
    print(P .. frameName .. " -------------------------------------------------")
    if not frame then
      print(P .. "  frame introuvable (addon Blizzard pas encore charge ?)")
    else
      print(string.format("%s  enabled=%s  IsShown=%s  GetAlpha=%.2f  locked=%s",
        P, tostring(cfg and cfg.enabled), tostring(frame:IsShown()), frame:GetAlpha(), tostring(frame.__locked)))
      print(string.format("%s  useFading=%s  fadeAlpha=%s  fadeInCombat=%s  fadeOnTarget=%s  fadeOnCasting=%s  fadeOnHover=%s  isHovered=%s",
        P, tostring(cfg and cfg.useFading), tostring(cfg and cfg.fadeAlpha),
        tostring(cfg and cfg.fadeInCombat), tostring(cfg and cfg.fadeOnTarget),
        tostring(cfg and cfg.fadeOnCasting), tostring(cfg and cfg.fadeOnHover),
        tostring(_isHovered[frameName])))
      if cfg then
        print(string.format("%s  ShouldFadeIn()=%s (donc alpha cible = %s)",
          P, tostring(ShouldFadeIn(cfg, _isHovered[frameName])),
          ShouldFadeIn(cfg, _isHovered[frameName]) and "1" or tostring(cfg.fadeAlpha)))
      end
      print(string.format("%s  gridLayoutType=%s  hideWhenInactive=%s  stride=%s  isHorizontal=%s  GetSize=%dx%d",
        P, tostring(cfg and cfg.gridLayoutType), tostring(cfg and cfg.hideWhenInactive),
        tostring(frame.stride), tostring(frame.isHorizontal), frame:GetWidth(), frame:GetHeight()))

      local ok, layoutChildren = pcall(frame.GetLayoutChildren, frame)
      if not ok or not layoutChildren then
        print(P .. "  GetLayoutChildren() a echoue ou vide")
      else
        print(P .. "  " .. #layoutChildren .. " icone(s) trackee(s) par Blizzard :")
        for i, child in ipairs(layoutChildren) do
          local okS, spellID = pcall(child.GetSpellID, child)
          -- Drapeaux sources en plus de __isActive : ils disent POURQUOI une icone reste affichee.
          -- __hideType=nil = enfant jamais vu par la pre-passe de Hook_Layout (bug de fantome) ;
          -- __isActive=true avec les 3 drapeaux a false/nil = incoherence de CheckItemVisibility ;
          -- editData=true hors Edit Mode = frame de previsualisation restee dans le pool.
          local okE, hasEdit = pcall(child.HasEditModeData, child)
          print(string.format("%s   [%d] spell=%s  IsShown=%s  IsVisible=%s  __isActive=%s  __hideType=%s  cd=%s  aura=%s  charges=%s  editData=%s",
            P, i, tostring(okS and spellID), tostring(child:IsShown()), tostring(child:IsVisible()),
            tostring(child.__isActive), tostring(child.__hideType),
            tostring(child.__isOnActualCooldown), tostring(child.__isOnAura),
            tostring(child.wasSetFromCharges), tostring(okE and hasEdit)))
        end
      end
    end
  end
end

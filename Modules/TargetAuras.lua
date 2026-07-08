-- Modules/TargetAuras.lua : Buffs & Debuffs de la cible, affichés sous la TopTargetBar
-- Technique identique à ElvUI/oUF : C_UnitAuras.GetAuraSlots + GetAuraDataBySlot
-- avec gestion des secret values (instances, rated content).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local TargetAuras = {}
ns.Modules.TargetAuras = TargetAuras

---------------------------------------------------------------------------
-- Raccourcis API (cache local)
---------------------------------------------------------------------------
local GetAuraSlots                  = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot             = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local GetAuraDuration               = C_UnitAuras and C_UnitAuras.GetAuraDuration
local GetAuraApplicationDisplayCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
local _issecretvalue                = issecretvalue

local GetTime     = GetTime
local pcall       = pcall
local ipairs      = ipairs
local math_floor  = math.floor
local wipe        = wipe

---------------------------------------------------------------------------
-- Helpers secret-value
---------------------------------------------------------------------------
local function IsSecret(value)
  return _issecretvalue and _issecretvalue(value) or false
end

local function SafeNum(value, fallback)
  if value == nil then return fallback or 0 end
  if IsSecret(value) then return fallback or 0 end
  return value
end

---------------------------------------------------------------------------
-- Constantes / Textures
---------------------------------------------------------------------------
local DARK        = 14 / 255
local FONT_BOLD   = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Bold.ttf"
local FONT_FILE   = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\PTSansNarrow-Regular.ttf"
local DEBUFF_TYPE_COLORS = {
  Magic   = { 0.20, 0.60, 1.00 },
  Curse   = { 0.60, 0.00, 1.00 },
  Disease = { 0.60, 0.40, 0.00 },
  Poison  = { 0.00, 0.60, 0.00 },
  none    = { 0.80, 0.00, 0.00 },
}

---------------------------------------------------------------------------
-- Etat du module
---------------------------------------------------------------------------
local frame         = nil
local buffIcons     = {}
local debuffIcons   = {}
local buffRow       = nil
local debuffRow     = nil
local previewMode   = false
local lastUnit      = "target"

---------------------------------------------------------------------------
-- Configuration helpers
---------------------------------------------------------------------------
local function Cfg()
  return ns.GetCfg("targetAuras")
end

-- Sous-config par groupe (buffs / debuffs) avec fallback vers defaults
local function GrpCfg(group)
  local root = Cfg()
  if not root then return {} end
  local db  = root[group]
  local def = ns.Defaults and ns.Defaults.targetAuras and ns.Defaults.targetAuras[group]
  if not db and not def then return {} end
  -- On renvoie la table DB si elle existe, le Lua de GetCfg fait le merge
  return db or def or {}
end

local function GrpGet(group, key)
  local cfg  = Cfg()
  local db   = cfg and cfg[group]
  local def  = ns.Defaults and ns.Defaults.targetAuras and ns.Defaults.targetAuras[group]
  if db  and db[key]  ~= nil then return db[key] end
  if def and def[key] ~= nil then return def[key] end
end

---------------------------------------------------------------------------
-- Tooltip handlers (style ElvUI/oUF)
---------------------------------------------------------------------------
local function Aura_OnEnter(self)
  if not self.auraInstanceID then return end
  if not self._unit then return end
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -2)
  if self._filter == "HELPFUL" then
    GameTooltip:SetUnitBuffByAuraInstanceID(self._unit, self.auraInstanceID)
  else
    GameTooltip:SetUnitDebuffByAuraInstanceID(self._unit, self.auraInstanceID)
  end
  GameTooltip:Show()
end

local function Aura_OnLeave(self)
  GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Création d'une icône réutilisable
---------------------------------------------------------------------------
local function CreateAuraIcon(parent, index, namePrefix)
  local f = CreateFrame("Frame", "Aishaddon" .. namePrefix .. index, parent)
  f:SetSize(26, 26)
  f:EnableMouse(true)
  f:SetScript("OnEnter", Aura_OnEnter)
  f:SetScript("OnLeave", Aura_OnLeave)

  f._unit   = nil   -- unit for tooltip
  f._filter = nil   -- "HELPFUL" or "HARMFUL"

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(DARK, DARK, DARK, 0.85)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  f.icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  f.border = f:CreateTexture(nil, "OVERLAY")
  f.border:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
  f.border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
  f.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
  f.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)

  f.cooldown = CreateFrame("Cooldown", "$parentCooldown", f, "CooldownFrameTemplate")
  f.cooldown:SetAllPoints(f.icon)
  f.cooldown:SetDrawEdge(false)
  -- Le moteur C++ gère le texte de countdown (secret values incluses)
  f.cooldown:SetHideCountdownNumbers(false)

  local raised = CreateFrame("Frame", nil, f)
  raised:SetAllPoints()
  raised:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)

  f.count = raised:CreateFontString(nil, "OVERLAY")
  f.count:SetFont(FONT_BOLD, 10, "OUTLINE")
  f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  f.count:SetJustifyH("RIGHT")

  f.auraInstanceID = nil
  f.expirationTime = 0
  f.totalDuration  = 0
  f:Hide()
  return f
end

---------------------------------------------------------------------------
-- Pool management
---------------------------------------------------------------------------
local function EnsureIcons(pool, parent, count, prefix)
  for i = #pool + 1, count do
    pool[i] = CreateAuraIcon(parent, i, prefix)
  end
end

---------------------------------------------------------------------------
-- Layout : positionne les icônes visibles en grille (multi-ligne)
---------------------------------------------------------------------------
local function LayoutRow(pool, activeCount, rowFrame, grp)
  local size      = grp.iconSize or 26
  local spacing   = grp.iconSpacing or 2
  local growLeft  = grp.growDirection == "LEFT"
  local growUp    = grp.growUpward == true
  local numRows   = grp.numRows or 1
  local rowSpace  = grp.rowSpacing or 2

  -- Nombre d'icônes par ligne (explicite via config)
  local perRow = grp.maxAuras or 16

  for i = 1, activeCount do
    local icon = pool[i]
    icon:SetSize(size, size)
    icon.icon:ClearAllPoints()
    icon.icon:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    icon.icon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
    icon:ClearAllPoints()

    local row  = math.floor((i - 1) / perRow)
    local col  = (i - 1) - row * perRow
    local yOff = row * (size + rowSpace)
    if growUp then yOff = yOff else yOff = -yOff end

    local vAnchor = growUp and "BOTTOMLEFT" or "TOPLEFT"
    local vAnchorR = growUp and "BOTTOMRIGHT" or "TOPRIGHT"

    if growLeft then
      local xOff = -(col * (size + spacing))
      icon:SetPoint(vAnchorR, rowFrame, vAnchorR, xOff, yOff)
    else
      local xOff = col * (size + spacing)
      icon:SetPoint(vAnchor, rowFrame, vAnchor, xOff, yOff)
    end
  end
  for i = activeCount + 1, #pool do
    pool[i]:Hide()
  end
end


---------------------------------------------------------------------------
-- Collecte des auras via C_UnitAuras
---------------------------------------------------------------------------
local _auraCache = {}

local function CollectAuras(unit, filter)
  wipe(_auraCache)
  if not GetAuraSlots then return _auraCache end

  local ok, token, s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,
        s11,s12,s13,s14,s15,s16,s17,s18,s19,s20,
        s21,s22,s23,s24,s25,s26,s27,s28,s29,s30,
        s31,s32,s33,s34,s35,s36,s37,s38,s39,s40
        = pcall(GetAuraSlots, unit, filter)
  if not ok then return _auraCache end

  local allSlots = { s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,
                     s11,s12,s13,s14,s15,s16,s17,s18,s19,s20,
                     s21,s22,s23,s24,s25,s26,s27,s28,s29,s30,
                     s31,s32,s33,s34,s35,s36,s37,s38,s39,s40 }

  for _, slot in ipairs(allSlots) do
    if slot then
      local okD, aura = pcall(GetAuraDataBySlot, unit, slot)
      if okD and aura then
        _auraCache[#_auraCache + 1] = aura
      end
    end
  end
  return _auraCache
end

---------------------------------------------------------------------------
-- Applique une aura sur une icône (avec config par groupe)
---------------------------------------------------------------------------
local function ApplyAuraToIcon(icon, aura, unit, isDebuff, grp)
  icon:Show()
  icon.auraInstanceID = aura.auraInstanceID
  icon._unit   = unit
  icon._filter  = isDebuff and "HARMFUL" or "HELPFUL"

  -- Texture
  if aura.icon and not IsSecret(aura.icon) then
    icon.icon:SetTexture(aura.icon)
  elseif aura.spellId and C_Spell and C_Spell.GetSpellTexture then
    local okTex, tex = pcall(C_Spell.GetSpellTexture, aura.spellId)
    icon.icon:SetTexture((okTex and tex) or 134400)
  else
    icon.icon:SetTexture(134400)
  end

  -- Stacks
  local apps = aura.applications or 0
  if IsSecret(apps) then
    if GetAuraApplicationDisplayCount and aura.auraInstanceID then
      local okC, countText = pcall(GetAuraApplicationDisplayCount, unit, aura.auraInstanceID, 2, 99)
      if okC and countText then
        icon.count:SetText(countText)
      else
        icon.count:SetText("")
      end
    else
      icon.count:SetText("")
    end
  else
    icon.count:SetText(apps > 1 and apps or "")
  end

  -- Bordure
  local showBorder = grp.showBorder ~= false
  if showBorder then
    if isDebuff then
      local dispelType = aura.dispelName
      if IsSecret(dispelType) then dispelType = nil end
      local c = DEBUFF_TYPE_COLORS[dispelType] or DEBUFF_TYPE_COLORS.none
      icon.border:SetVertexColor(c[1], c[2], c[3], 1)
    else
      local bc = grp.borderColor or { 1, 1, 1, 0.15 }
      icon.border:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
    end
    icon.border:Show()
  else
    icon.border:Hide()
  end

  -- Cooldown swipe + countdown natif
  -- On garde TOUJOURS le cooldown actif pour que le moteur C++ affiche
  -- le timer.  Si showSwipe est désactivé, on rend le swipe invisible
  -- via SetSwipeColor alpha 0 au lieu de Clear()/Hide().
  local showSwipe = grp.showSwipe ~= false
  icon.cooldown:SetReverse(grp.reverseSwipe == true)
  if showSwipe then
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.8)
  else
    icon.cooldown:SetSwipeColor(0, 0, 0, 0)
  end
  if GetAuraDuration and aura.auraInstanceID then
    local okDur, durObj = pcall(GetAuraDuration, unit, aura.auraInstanceID)
    if okDur and durObj then
      local okSet = pcall(icon.cooldown.SetCooldownFromDurationObject, icon.cooldown, durObj)
      if not okSet then icon.cooldown:Clear() end
    else
      icon.cooldown:Clear()
    end
  else
    local dur = SafeNum(aura.duration, 0)
    local exp = SafeNum(aura.expirationTime, 0)
    if dur > 0 and exp > 0 then
      icon.cooldown:SetCooldown(exp - dur, dur)
    else
      icon.cooldown:Clear()
    end
  end
  icon.cooldown:Show()

  icon.expirationTime = SafeNum(aura.expirationTime, 0)
  icon.totalDuration  = SafeNum(aura.duration, 0)
end

---------------------------------------------------------------------------
-- Applique le style (font, couleur, position) aux icônes d'un pool.
-- Le texte de countdown est rendu par le moteur C++ (gère les secrets).
-- On stylise ET repositionne le FontString natif du cooldown.
---------------------------------------------------------------------------
local function StyleCooldownText(cd, iconFrame, font, fontSize, color, anchor, relPoint, offX, offY)
  -- Le CooldownFrameTemplate crée un FontString enfant pour le countdown.
  -- On le cherche dans les régions et les enfants du frame.
  local function styleFS(fs)
    if not fs or not fs.SetFont then return end
    pcall(fs.SetFont, fs, font, fontSize, "OUTLINE")
    pcall(fs.SetTextColor, fs, color[1], color[2], color[3], color[4] or 1)
    -- Repositionner : détacher du centre par défaut, ancrer sur l'icône
    fs:ClearAllPoints()
    fs:SetPoint(anchor, iconFrame, relPoint, offX, offY)
    fs:SetJustifyH("CENTER")
  end
  -- Vérifier les régions directes
  for i = 1, cd:GetNumRegions() do
    local region = select(i, cd:GetRegions())
    if region and region:IsObjectType("FontString") then
      styleFS(region)
    end
  end
  -- Vérifier les enfants (Blizzard ajoute parfois un frame CooldownDisplay)
  for i = 1, cd:GetNumChildren() do
    local child = select(i, cd:GetChildren())
    if child then
      for j = 1, child:GetNumRegions() do
        local region = select(j, child:GetRegions())
        if region and region:IsObjectType("FontString") then
          styleFS(region)
        end
      end
    end
  end
end

local function StyleIcons(pool, grp)
  local size = grp.iconSize or 26
  local dFont = grp.durationFont or FONT_FILE
  local dSize = grp.durationFontSize or 9
  local dCol  = grp.durationColor or { 1, 1, 1, 1 }
  local dAnc  = grp.durationAnchor   or "CENTER"
  local dOX   = grp.durationOffX     or 0
  local dOY   = grp.durationOffY     or 0
  local cFont = grp.countFont or FONT_BOLD
  local cSize = grp.countFontSize or 10
  local cCol  = grp.countColor or { 1, 1, 1, 1 }

  local bSz = grp.borderSize or 1

  for _, icon in ipairs(pool) do
    icon:SetSize(size, size)

    -- Border size
    icon.border:ClearAllPoints()
    icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -bSz, bSz)
    icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bSz, -bSz)

    -- Style + position du texte countdown natif (C++)
    StyleCooldownText(icon.cooldown, icon, dFont, dSize, dCol, dAnc, dOX, dOY)

    -- Count text
    icon.count:ClearAllPoints()
    icon.count:SetFont(cFont, cSize, "OUTLINE")
    icon.count:SetTextColor(cCol[1], cCol[2], cCol[3], cCol[4] or 1)
    icon.count:SetPoint(
      grp.countAnchor   or "BOTTOMRIGHT",
      icon,
      grp.countRelPoint or "BOTTOMRIGHT",
      grp.countOffX     or -1,
      grp.countOffY     or 1
    )
  end
end

---------------------------------------------------------------------------
-- Tri des auras (configurable par groupe)
-- Modes : playerFirst, shortFirst, longFirst, alpha, index
---------------------------------------------------------------------------
local function IsPlayer(aura)
  return (not IsSecret(aura.sourceUnit)) and (aura.sourceUnit == "player") or false
end

local function SafeName(aura)
  if aura.name and not IsSecret(aura.name) then return aura.name end
  return ""
end

local SORT_COMPARATORS = {
  -- Joueur d'abord, puis durée restante croissante
  playerFirst = function(a, b)
    local ap, bp = IsPlayer(a), IsPlayer(b)
    if ap ~= bp then return ap end
    local aExp = SafeNum(a.expirationTime, 0)
    local bExp = SafeNum(b.expirationTime, 0)
    if aExp == 0 and bExp ~= 0 then return false end
    if bExp == 0 and aExp ~= 0 then return true end
    return aExp < bExp
  end,
  -- Durée restante la plus courte d'abord
  shortFirst = function(a, b)
    local aExp = SafeNum(a.expirationTime, 0)
    local bExp = SafeNum(b.expirationTime, 0)
    if aExp == 0 and bExp ~= 0 then return false end
    if bExp == 0 and aExp ~= 0 then return true end
    return aExp < bExp
  end,
  -- Durée restante la plus longue d'abord
  longFirst = function(a, b)
    local aExp = SafeNum(a.expirationTime, 0)
    local bExp = SafeNum(b.expirationTime, 0)
    if aExp == 0 and bExp ~= 0 then return false end
    if bExp == 0 and aExp ~= 0 then return true end
    return aExp > bExp
  end,
  -- Alphabétique par nom
  alpha = function(a, b)
    return SafeName(a) < SafeName(b)
  end,
  -- Ordre d'index Blizzard (pas de tri)
  index = function() return false end,
}

local function SortAuras(list, mode, reverse)
  if mode ~= "index" then
    local cmp = SORT_COMPARATORS[mode or "playerFirst"] or SORT_COMPARATORS.playerFirst
    if reverse then
      table.sort(list, function(a, b) return cmp(b, a) end)
    else
      table.sort(list, cmp)
    end
  elseif reverse then
    local n = #list
    for i = 1, math.floor(n / 2) do
      list[i], list[n - i + 1] = list[n - i + 1], list[i]
    end
  end
end

---------------------------------------------------------------------------
-- Données de preview (faux buffs/debuffs quand pas de cible)
---------------------------------------------------------------------------
local PREVIEW_BUFF_TEMPLATES = {
  { icon = 135932, name = "Fortitude",      duration = 3600, remaining = 2880, applications = 0, sourceUnit = "player" },
  { icon = 135987, name = "Renew",          duration = 15,   remaining = 11,   applications = 0, sourceUnit = "player" },
  { icon = 136051, name = "Power Infusion", duration = 20,   remaining = 14,   applications = 0, sourceUnit = "player" },
  { icon = 135964, name = "Shield",         duration = 30,   remaining = 22,   applications = 3, sourceUnit = "party1" },
  { icon = 136075, name = "Mark of the Wild",duration = 3600, remaining = 3120, applications = 0, sourceUnit = "party2" },
}
local PREVIEW_DEBUFF_TEMPLATES = {
  { icon = 136139, name = "Shadow Word: Pain", duration = 18,  remaining = 12, applications = 0, sourceUnit = "player", dispelName = "Magic" },
  { icon = 136188, name = "Corruption",        duration = 14,  remaining = 8,  applications = 0, sourceUnit = "player" },
  { icon = 132095, name = "Rend",              duration = 120, remaining = 95, applications = 0, sourceUnit = "party1", dispelName = "Curse" },
  { icon = 136066, name = "Poison",            duration = 12,  remaining = 5,  applications = 5, sourceUnit = "party2", dispelName = "Poison" },
}

local function MakePreviewAuras(templates)
  local now = GetTime()
  local out = {}
  for i, t in ipairs(templates) do
    out[i] = {
      icon            = t.icon,
      name            = t.name,
      duration        = t.duration,
      expirationTime  = now + t.remaining,
      applications    = t.applications or 0,
      sourceUnit      = t.sourceUnit or "player",
      dispelName      = t.dispelName,
      auraInstanceID  = nil,
    }
  end
  return out
end

---------------------------------------------------------------------------
-- Scan complet et rafraîchissement visuel
---------------------------------------------------------------------------
local function RefreshAuras()
  if not frame then return end
  local cfg = Cfg()
  if not cfg then return end
  if cfg.enabled == false and not previewMode then return end
  local unit = lastUnit
  local usePreview = previewMode and not UnitExists(unit)

  if not UnitExists(unit) and not usePreview then
    for _, icon in ipairs(buffIcons)  do icon:Hide() end
    for _, icon in ipairs(debuffIcons) do icon:Hide() end
    return
  end

  local bGrp = GrpCfg("buffs")
  local dGrp = GrpCfg("debuffs")

  -- === BUFFS ===
  local perRowB = bGrp.maxAuras or 16
  local maxBuffs = perRowB * (bGrp.numRows or 1)
  local buffs = usePreview and MakePreviewAuras(PREVIEW_BUFF_TEMPLATES) or CollectAuras(unit, "HELPFUL")
  SortAuras(buffs, bGrp.sortMode, bGrp.reverseSort)
  local buffCount = math.min(#buffs, maxBuffs)
  EnsureIcons(buffIcons, buffRow, buffCount, "TargetBuff")
  for i = 1, buffCount do
    ApplyAuraToIcon(buffIcons[i], buffs[i], unit, false, bGrp)
  end
  for i = buffCount + 1, #buffIcons do buffIcons[i]:Hide() end
  StyleIcons(buffIcons, bGrp)
  LayoutRow(buffIcons, buffCount, buffRow, bGrp)

  -- === DEBUFFS ===
  local perRowD = dGrp.maxAuras or 16
  local maxDebuffs = perRowD * (dGrp.numRows or 1)
  local debuffs = usePreview and MakePreviewAuras(PREVIEW_DEBUFF_TEMPLATES) or CollectAuras(unit, "HARMFUL")

  -- Filtre "debuffs du joueur uniquement"
  if dGrp.onlyPlayer and not usePreview then
    local filtered = {}
    for _, aura in ipairs(debuffs) do
      if IsPlayer(aura) then
        filtered[#filtered + 1] = aura
      end
    end
    debuffs = filtered
  end

  SortAuras(debuffs, dGrp.sortMode, dGrp.reverseSort)
  local debuffCount = math.min(#debuffs, maxDebuffs)
  EnsureIcons(debuffIcons, debuffRow, debuffCount, "TargetDebuff")
  for i = 1, debuffCount do
    ApplyAuraToIcon(debuffIcons[i], debuffs[i], unit, true, dGrp)
  end
  for i = debuffCount + 1, #debuffIcons do debuffIcons[i]:Hide() end
  StyleIcons(debuffIcons, dGrp)
  LayoutRow(debuffIcons, debuffCount, debuffRow, dGrp)
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event, unit, updateInfo)
  if event == "UNIT_AURA" then
    if unit == lastUnit then
      RefreshAuras()
    end
  elseif event == "PLAYER_TARGET_CHANGED" then
    TargetAuras.UpdateVisibility()
    RefreshAuras()
  end
end

---------------------------------------------------------------------------
-- ShouldShow
---------------------------------------------------------------------------
function TargetAuras.ShouldShow()
  if ns.IsInBlockedState and ns.IsInBlockedState() then return false end
  local cfg = Cfg()
  if not cfg or cfg.enabled == false then return false end
  return UnitExists(lastUnit)
end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------
function TargetAuras.Create(parent)
  if frame then return frame end
  local cfg = Cfg()
  local bGrp = GrpCfg("buffs")
  local dGrp = GrpCfg("debuffs")

  frame = CreateFrame("Frame", "AishaddonTargetAuras", parent or UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetSize(530, 80)

  buffRow = CreateFrame("Frame", nil, frame)
  buffRow:SetSize(bGrp.rowWidth or 530, bGrp.iconSize or 26)
  buffRow:SetPoint("TOP", frame, "TOP", bGrp.offsetX or 0, bGrp.offsetY or 0)

  debuffRow = CreateFrame("Frame", nil, frame)
  debuffRow:SetSize(dGrp.rowWidth or 530, dGrp.iconSize or 26)
  debuffRow:SetPoint("TOP", buffRow, "BOTTOM", dGrp.offsetX or 0, dGrp.offsetY or -2)

  eventFrame:SetScript("OnEvent", OnEvent)
  eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  eventFrame:RegisterUnitEvent("UNIT_AURA", "target")

  TargetAuras.ApplySettings()
  return frame
end

---------------------------------------------------------------------------
-- ApplySettings
---------------------------------------------------------------------------
function TargetAuras.ApplySettings()
  if not frame then return end
  local cfg = Cfg()
  if not cfg then return end

  if cfg.enabled == false then
    frame:Hide()
    return
  end

  local bGrp = GrpCfg("buffs")
  local dGrp = GrpCfg("debuffs")
  local bSize = bGrp.iconSize or 26
  local dSize = dGrp.iconSize or 26
  local bSpacing = bGrp.iconSpacing or 2
  local dSpacing = dGrp.iconSpacing or 2
  local bPerRow = bGrp.maxAuras or 16
  local dPerRow = dGrp.maxAuras or 16
  local bRows = bGrp.numRows or 1
  local dRows = dGrp.numRows or 1
  local bRowW = bPerRow * (bSize + bSpacing) - bSpacing
  local dRowW = dPerRow * (dSize + dSpacing) - dSpacing
  local bRowH = bRows * (bSize + (bGrp.rowSpacing or 2)) - (bGrp.rowSpacing or 2)
  local dRowH = dRows * (dSize + (dGrp.rowSpacing or 2)) - (dGrp.rowSpacing or 2)
  local maxRowW = math.max(bRowW, dRowW)

  -- Container positionné en haut-centre de l'écran
  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "TOP", 0, 0)
  frame:SetSize(maxRowW, bRowH + dRowH + 10)

  -- Buffs : ancrés au top center de l'écran (via frame)
  buffRow:ClearAllPoints()
  buffRow:SetSize(bRowW, bRowH)
  buffRow:SetPoint("TOP", UIParent, "TOP", bGrp.offsetX or 0, bGrp.offsetY or -40)

  -- Debuffs : ancrés indépendamment au top center de l'écran
  debuffRow:ClearAllPoints()
  debuffRow:SetSize(dRowW, dRowH)
  debuffRow:SetPoint("TOP", UIParent, "TOP", dGrp.offsetX or 0, dGrp.offsetY or -70)

  -- Style des icônes existantes
  StyleIcons(buffIcons, bGrp)
  StyleIcons(debuffIcons, dGrp)

  TargetAuras.UpdateVisibility()
  RefreshAuras()
end

---------------------------------------------------------------------------
-- Visibilité
---------------------------------------------------------------------------
function TargetAuras.UpdateVisibility()
  if not frame then return end
  if previewMode then frame:Show(); return end
  if TargetAuras.ShouldShow() then
    frame:Show()
  else
    frame:Hide()
  end
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------
function TargetAuras.SetPreview(on)
  previewMode = on
  if not frame then return end
  if on then
    frame:Show()
    RefreshAuras()
  else
    TargetAuras.UpdateVisibility()
    RefreshAuras()
  end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function TargetAuras.Init()
  TargetAuras.Create(UIParent)
end

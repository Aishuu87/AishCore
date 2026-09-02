-- Modules/TargetAuras.lua : Buffs & Debuffs de la cible, affichés sous la TopTargetBar
--
-- RENDU NATIF : ni GetAuraSlots ni l'énumération legacy (GetAuraDataByIndex)
-- ne sont utilisables sur "target" en combat -- les DEUX lèvent
-- systématiquement "Auras cannot be accessed when secret while tainted by
-- 'AishCore'" dès qu'une seule aura de la cible est secrète/tainted
-- (contrairement au joueur, où l'énumération individuelle survit). Aucun
-- fallback Lua possible ici. Seule solution : un AuraContainer natif
-- (AddAuraGroup, SetUnit("target")) -- même recette que les auras du joueur
-- (cf. Modules/Auras/Core/AuraTrackerContainer.lua). Blizzard lit les
-- données secrètes côté C++ et ne nous rend que des pixels déjà dessinés --
-- immunisé au taint. La preview (pas de vraie cible) reste sur l'ancien
-- pipeline Lua/icônes manuelles (le natif ne peut afficher que de VRAIES
-- auras).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local TargetAuras = {}
ns.Modules.TargetAuras = TargetAuras

---------------------------------------------------------------------------
-- Raccourcis API (cache local) -- conservés uniquement pour /tadebug
---------------------------------------------------------------------------
local GetAuraSlots       = C_UnitAuras and C_UnitAuras.GetAuraSlots
local GetAuraDataBySlot  = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local _issecretvalue     = issecretvalue

local GetTime = GetTime
local pcall   = pcall
local ipairs  = ipairs

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
local buffIcons     = {}   -- pool preview uniquement (pas de vraie cible)
local debuffIcons   = {}   -- idem
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

local function IsPlayer(aura)
  return (not IsSecret(aura.sourceUnit)) and (aura.sourceUnit == "player") or false
end

local function SafeName(aura)
  if aura.name and not IsSecret(aura.name) then return aura.name end
  return ""
end

---------------------------------------------------------------------------
-- Tooltip handlers (preview uniquement -- les auraButton natifs affichent
-- déjà leur tooltip nativement, cf. ApplyNativeButtonStyle plus bas)
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
  if IsAltKeyDown() and self.spellId then
    pcall(GameTooltip.AddDoubleLine, GameTooltip, "Spell ID", self.spellId, 1, 1, 1, 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end

local function Aura_OnLeave(self)
  GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Création d'une icône réutilisable (PREVIEW uniquement)
---------------------------------------------------------------------------
local function CreateAuraIcon(parent, index, namePrefix)
  local f = CreateFrame("Frame", "AishCore" .. namePrefix .. index, parent)
  f:SetSize(26, 26)
  f:EnableMouse(true)
  f:SetScript("OnEnter", Aura_OnEnter)
  f:SetScript("OnLeave", Aura_OnLeave)

  f._unit   = nil
  f._filter = nil

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
  f.cooldown:SetHideCountdownNumbers(false)

  local raised = CreateFrame("Frame", nil, f)
  raised:SetAllPoints()
  raised:SetFrameLevel(f.cooldown:GetFrameLevel() + 1)

  f.count = raised:CreateFontString(nil, "OVERLAY")
  f.countSlug = ns.CreateSlugRing(raised, f.count)
  ns.ApplyTextOutlineStyle(f.count, f.countSlug, FONT_BOLD, 10, nil)
  f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  f.count:SetJustifyH("RIGHT")

  f.auraInstanceID = nil
  f.expirationTime = 0
  f.totalDuration  = 0
  f:Hide()
  return f
end

local function EnsureIcons(pool, parent, count, prefix)
  for i = #pool + 1, count do
    pool[i] = CreateAuraIcon(parent, i, prefix)
  end
end

local function LayoutRow(pool, activeCount, rowFrame, grp)
  local size      = grp.iconSize or 26
  local spacing   = grp.iconSpacing or 2
  local growLeft  = grp.growDirection == "LEFT"
  local growUp    = grp.growUpward == true
  local rowSpace  = grp.rowSpacing or 2
  local perRow    = grp.maxAuras or 16

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
    if not growUp then yOff = -yOff end

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

local function ApplyAuraToIcon(icon, aura, unit, isDebuff, grp)
  icon:Show()
  icon.auraInstanceID = aura.auraInstanceID
  icon._unit   = unit
  icon._filter = isDebuff and "HARMFUL" or "HELPFUL"
  icon.spellId = aura.spellId

  if aura.icon and not IsSecret(aura.icon) then
    icon.icon:SetTexture(aura.icon)
  elseif aura.spellId and C_Spell and C_Spell.GetSpellTexture then
    local okTex, tex = pcall(C_Spell.GetSpellTexture, aura.spellId)
    icon.icon:SetTexture((okTex and tex) or 134400)
  else
    icon.icon:SetTexture(134400)
  end

  local apps = aura.applications or 0
  if IsSecret(apps) then
    icon.count:SetText("")
  else
    icon.count:SetText(apps > 1 and apps or "")
  end

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

  local showSwipe = grp.showSwipe ~= false
  icon.cooldown:SetReverse(grp.reverseSwipe == true)
  if showSwipe then
    icon.cooldown:SetSwipeColor(0, 0, 0, 0.8)
  else
    icon.cooldown:SetSwipeColor(0, 0, 0, 0)
  end
  local dur = SafeNum(aura.duration, 0)
  local exp = SafeNum(aura.expirationTime, 0)
  if dur > 0 and exp > 0 then
    icon.cooldown:SetCooldown(exp - dur, dur)
  else
    icon.cooldown:Clear()
  end
  icon.cooldown:Show()

  icon.expirationTime = SafeNum(aura.expirationTime, 0)
  icon.totalDuration  = SafeNum(aura.duration, 0)
end

---------------------------------------------------------------------------
-- Style d'un FontString de countdown natif (widget Cooldown) -- utilisé à
-- la fois par la preview (icônes manuelles) et le rendu natif (auraButton).
---------------------------------------------------------------------------
local function StyleCooldownText(cd, iconFrame, font, fontSize, color, anchor, relPoint, offX, offY)
  local function styleFS(fs)
    if not fs or not fs.SetFont then return end
    pcall(fs.SetFont, fs, font, fontSize, "OUTLINE")
    pcall(fs.SetTextColor, fs, color[1], color[2], color[3], color[4] or 1)
    fs:ClearAllPoints()
    pcall(fs.SetPoint, fs, anchor, iconFrame, relPoint, offX, offY)
    fs:SetJustifyH("CENTER")
  end
  for i = 1, cd:GetNumRegions() do
    local region = select(i, cd:GetRegions())
    if region and region:IsObjectType("FontString") then
      styleFS(region)
    end
  end
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
  local dAnc  = grp.durationAnchor or "CENTER"
  local dOX   = grp.durationOffX or 0
  local dOY   = grp.durationOffY or 0
  local cFont = grp.countFont or FONT_BOLD
  local cSize = grp.countFontSize or 10
  local cCol  = grp.countColor or { 1, 1, 1, 1 }

  local bSz = grp.borderSize or 1

  for _, icon in ipairs(pool) do
    icon:SetSize(size, size)

    icon.border:ClearAllPoints()
    icon.border:SetPoint("TOPLEFT", icon, "TOPLEFT", -bSz, bSz)
    icon.border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", bSz, -bSz)

    StyleCooldownText(icon.cooldown, icon, dFont, dSize, dCol, dAnc, dAnc, dOX, dOY)

    icon.count:ClearAllPoints()
    ns.ApplyTextOutlineStyle(icon.count, icon.countSlug, cFont, cSize, grp.countOutlineStyle)
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
-- Tri (PREVIEW uniquement -- le rendu natif utilise TASortParams, cf. plus
-- bas, qui traduit ces mêmes modes vers l'équivalent Blizzard le plus proche)
---------------------------------------------------------------------------
local SORT_COMPARATORS = {
  playerFirst = function(a, b)
    local ap, bp = IsPlayer(a), IsPlayer(b)
    if ap ~= bp then return ap end
    local aExp = SafeNum(a.expirationTime, 0)
    local bExp = SafeNum(b.expirationTime, 0)
    if aExp == 0 and bExp ~= 0 then return false end
    if bExp == 0 and aExp ~= 0 then return true end
    return aExp < bExp
  end,
  shortFirst = function(a, b)
    local aExp = SafeNum(a.expirationTime, 0)
    local bExp = SafeNum(b.expirationTime, 0)
    if aExp == 0 and bExp ~= 0 then return false end
    if bExp == 0 and aExp ~= 0 then return true end
    return aExp < bExp
  end,
  longFirst = function(a, b)
    local aExp = SafeNum(a.expirationTime, 0)
    local bExp = SafeNum(b.expirationTime, 0)
    if aExp == 0 and bExp ~= 0 then return false end
    if bExp == 0 and aExp ~= 0 then return true end
    return aExp > bExp
  end,
  alpha = function(a, b)
    return ns.FoldAccentsLower(SafeName(a)) < ns.FoldAccentsLower(SafeName(b))
  end,
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
-- Rafraîchissement PREVIEW (pas de vraie cible) -- le rendu réel passe par
-- les AuraContainer natifs (ConfigureNativeRow plus bas), jamais par ici.
---------------------------------------------------------------------------
local function RefreshAuras()
  if not frame then return end
  local cfg = Cfg()
  if not cfg then return end
  if cfg.enabled == false and not previewMode then return end
  local unit = lastUnit
  local usePreview = previewMode and not UnitExists(unit)

  if not usePreview then
    for _, icon in ipairs(buffIcons)  do icon:Hide() end
    for _, icon in ipairs(debuffIcons) do icon:Hide() end
    return
  end

  local bGrp = GrpCfg("buffs")
  local dGrp = GrpCfg("debuffs")

  -- === BUFFS ===
  local perRowB = bGrp.maxAuras or 16
  local maxBuffs = perRowB * (bGrp.numRows or 1)
  local buffs = MakePreviewAuras(PREVIEW_BUFF_TEMPLATES)
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
  local debuffs = MakePreviewAuras(PREVIEW_DEBUFF_TEMPLATES)
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
-- RENDU NATIF (AddAuraGroup, unit="target") -- combat-safe.
-- Recette identique à AuraTrackerContainer.lua (auras du joueur) : icône/
-- bordure/cooldown/stacks créés UNE SEULE FOIS dans initializeFrame, jamais
-- retouchés en dehors (les enfants deviennent "forbidden" dès qu'une vraie
-- aura secrète leur est assignée) -- seules leurs PROPRIÉTÉS (taille,
-- couleur, police, position) peuvent être remises à jour ensuite, via
-- ApplyNativeButtonStyle, à chaque changement de réglage.
--
-- candidateFilters = {} (aucun includeSpellIDs) = AUCUNE liste blanche =
-- Blizzard montre TOUT ce qui matche le filtre HELPFUL/HARMFUL -- confirmé
-- par lecture du code source d'ElvUI (Modules/UnitFrames/Elements/Auras.lua :
-- allowList/blockList restent nil par défaut, et Auras_CanidateFilters(nil,
-- nil, ...) produit exactement cette table vide) -- c'est la même API que
-- les unitframes buffs/debuffs d'ElvUI, jamais spécifique à un sort.
---------------------------------------------------------------------------
local SORTMETHOD    = _G.AuraContainerSortMethod
local SORTDIRECTION = _G.AuraContainerSortDirection
local AURA_BORDER_STYLE = _G.AuraButtonBorderStyle

local buffState   = { container = nil, pool = {}, groupCreated = false, key = "aishTABuffs" }
local debuffState = { container = nil, pool = {}, groupCreated = false, key = "aishTADebuffs" }

-- growDirection (LEFT/RIGHT) + growUpward -> paramètres du flow layout natif.
-- Toujours horizontal (multi-lignes gérées via SetFlowLayoutMaximumLineSize),
-- même principe que GrowthToFlowParams dans AuraTrackerContainer.lua.
local function TAFlowParams(growDirection, growUpward)
  local growLeft = growDirection == "LEFT"
  local hDir = growLeft and -1 or 1
  local vDir = growUpward and 1 or -1
  local anchorPoint
  if growUpward then
    anchorPoint = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
  else
    anchorPoint = growLeft and "TOPRIGHT" or "TOPLEFT"
  end
  return anchorPoint, hDir, vDir
end

-- sortMode/reverseSort -> équivalent natif Blizzard le plus proche.
-- "playerFirst" n'a pas d'équivalent direct (le tri natif ne connaît pas la
-- notion de source du buff) -- UnitFrameDebuff est l'heuristique utilisée
-- par les unitframes Blizzard elles-mêmes (priorité/source), approximation
-- la plus proche disponible côté natif.
local function TASortParams(sortMode, reverseSort)
  if not SORTMETHOD then return nil, nil end
  local method
  if sortMode == "shortFirst" or sortMode == "longFirst" then
    method = SORTMETHOD.Expiration
  elseif sortMode == "alpha" then
    method = SORTMETHOD.Name
  elseif sortMode == "index" then
    method = SORTMETHOD.AuraInstanceIDOnly or SORTMETHOD.Default
  else -- playerFirst (défaut)
    method = SORTMETHOD.UnitFrameDebuff or SORTMETHOD.Default
  end
  local reverse = (sortMode == "longFirst") ~= (reverseSort == true)
  local direction = SORTDIRECTION and (reverse and SORTDIRECTION.Reverse or SORTDIRECTION.Normal)
  return method, direction
end

-- Créé UNE SEULE FOIS (dans initializeFrame) : icône, bordure(s), cooldown,
-- texte de stacks. Jamais retouché ailleurs -- cf. en-tête de section.
local function CreateNativeButtonWidgets(auraButton, isDebuff)
  local icon = auraButton:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(auraButton)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  -- NE PAS remplir icon:SetTexture() -- Blizzard le fait en interne dès que
  -- SetIcon() est lié à un vrai candidat (même recette que la destination
  -- "icons" des auras du joueur).
  auraButton:SetIcon(icon)

  local border = auraButton:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("TOPLEFT", auraButton, "TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(DARK, DARK, DARK, 1)
  auraButton._aishBorder = border

  -- Bordure debuff : colorée par TYPE DE DISPEL directement par Blizzard
  -- (SetAuraBorder, natif) -- on ne peut JAMAIS lire aura.dispelName
  -- nous-mêmes pour une aura cible (donnée non exposée par l'AuraContainer),
  -- donc on délègue entièrement le calcul de couleur à Blizzard.
  local dispelBorder = auraButton:CreateTexture(nil, "BACKGROUND", nil, -1)
  dispelBorder:SetPoint("TOPLEFT", auraButton, "TOPLEFT", -1, 1)
  dispelBorder:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", 1, -1)
  dispelBorder:SetColorTexture(1, 1, 1, 1)
  auraButton._aishDispelBorder = dispelBorder
  if isDebuff and AURA_BORDER_STYLE and AURA_BORDER_STYLE.Color then
    pcall(auraButton.SetAuraBorder, auraButton, dispelBorder, {
      style = AURA_BORDER_STYLE.Color,
      showWhenHarmful = true,
      showWhenHelpful = false,
      showWithoutDispelType = true,
    })
  end

  local cd = CreateFrame("Cooldown", nil, auraButton, "CooldownFrameTemplate")
  cd:SetAllPoints(auraButton)
  cd:SetDrawEdge(false)
  cd:SetHideCountdownNumbers(false)
  auraButton:SetDurationCooldown(cd)
  auraButton._aishCD = cd

  -- Le FONT doit être posé AVANT SetApplicationCount -- Blizzard touche le
  -- texte immédiatement/synchroniquement dès l'appel (confirmé en jeu pour
  -- la destination "icons" : sans font posé avant, ça plante avec "Font not
  -- set" et fait échouer tout AddAuraGroup englobant).
  local countFS = auraButton:CreateFontString(nil, "OVERLAY", nil, 7)
  auraButton._aishCountSlug = ns.CreateSlugRing(auraButton, countFS)
  ns.ApplyTextOutlineStyle(countFS, auraButton._aishCountSlug, FONT_BOLD, 10, nil)
  countFS:SetJustifyH("RIGHT")
  auraButton:SetApplicationCount(countFS, {})
  auraButton._aishCount = countFS
end

-- Réapplique le style COURANT (taille/bordure/swipe/police durée/police
-- stacks/positions) à un auraButton DÉJÀ créé -- AddAuraGroup ne rappelle
-- initializeFrame qu'une seule fois par bouton, jamais à chaque changement
-- de réglage (même limitation que la destination "icons").
local function ApplyNativeButtonStyle(auraButton, grp, isDebuff)
  local okCheck, canAccess = pcall(function()
    return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
  end)
  if not (okCheck and canAccess) then return end
  pcall(function()
    local size = grp.iconSize or 26
    auraButton:SetSize(size, size)

    local showBorder = grp.showBorder ~= false
    local bSz = grp.borderSize or 1
    if auraButton._aishBorder then
      auraButton._aishBorder:ClearAllPoints()
      auraButton._aishBorder:SetPoint("TOPLEFT", auraButton, "TOPLEFT", -bSz, bSz)
      auraButton._aishBorder:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", bSz, -bSz)
      if isDebuff then
        -- Le debuff utilise dispelBorder (couleur native SetAuraBorder) à la place.
        auraButton._aishBorder:Hide()
      else
        local bc = grp.borderColor or { 1, 1, 1, 0.15 }
        auraButton._aishBorder:SetVertexColor(bc[1], bc[2], bc[3], bc[4] or 1)
        if showBorder then auraButton._aishBorder:Show() else auraButton._aishBorder:Hide() end
      end
    end
    if auraButton._aishDispelBorder then
      if isDebuff and showBorder then
        auraButton._aishDispelBorder:ClearAllPoints()
        auraButton._aishDispelBorder:SetPoint("TOPLEFT", auraButton, "TOPLEFT", -bSz, bSz)
        auraButton._aishDispelBorder:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", bSz, -bSz)
        auraButton._aishDispelBorder:Show()
      else
        auraButton._aishDispelBorder:Hide()
      end
    end

    if auraButton._aishCD then
      local cd = auraButton._aishCD
      cd:SetReverse(grp.reverseSwipe == true)
      if grp.showSwipe ~= false then
        cd:SetSwipeColor(0, 0, 0, 0.8)
      else
        cd:SetSwipeColor(0, 0, 0, 0)
      end
      local dAnc = grp.durationAnchor or "CENTER"
      StyleCooldownText(cd, auraButton,
        grp.durationFont or FONT_FILE, grp.durationFontSize or 9,
        grp.durationColor or { 1, 1, 1, 1 },
        dAnc, dAnc, grp.durationOffX or 0, grp.durationOffY or 0)
    end

    if auraButton._aishCount then
      local cnt = auraButton._aishCount
      ns.ApplyTextOutlineStyle(cnt, auraButton._aishCountSlug, grp.countFont or FONT_BOLD, grp.countFontSize or 10, grp.countOutlineStyle)
      local cc = grp.countColor or { 1, 1, 1, 1 }
      cnt:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
      cnt:ClearAllPoints()
      cnt:SetPoint(grp.countAnchor or "BOTTOMRIGHT", auraButton,
        grp.countRelPoint or "BOTTOMRIGHT", grp.countOffX or -1, grp.countOffY or 1)
    end
  end)
end

local function EnsureNativeContainer(state, rowFrame)
  if state.container then return state.container end
  if InCombatLockdown and InCombatLockdown() then return nil end
  local ok, result = pcall(CreateFrame, "AuraContainer", nil, rowFrame, "CustomAuraContainerTemplate")
  if not ok or not result then return nil end
  state.container = result
  result:SetSize(8, 8) -- redimensionné par le flow layout lui-même
  -- ORDRE OBLIGATOIRE (confirmé en jeu, destination "icons") :
  -- SetEnabled/SetUnit/Show AVANT AddAuraGroup, jamais après.
  pcall(result.SetEnabled, result, true)
  pcall(result.SetUnit, result, "target")
  result:Show()
  return result
end

-- Crée (une seule fois) ou reconfigure (via les setters Set* natifs) le
-- groupe partagé d'une ligne (buffs ou debuffs). Appelée depuis ApplySettings
-- à chaque changement de réglage -- AddAuraGroup lui-même ne peut être
-- rappelé qu'une seule fois pour une même clé.
local function ConfigureNativeRow(state, rowFrame, filterBase, grp, isDebuff)
  local c = EnsureNativeContainer(state, rowFrame)
  if not c then return end

  local size    = grp.iconSize or 26
  local spacing = grp.iconSpacing or 2
  local rowGap  = grp.rowSpacing or 2
  local perRow  = grp.maxAuras or 16
  local numRows = grp.numRows or 1

  local filter = filterBase
  if isDebuff and grp.onlyPlayer then
    filter = filter .. "|PLAYER"
  end

  local sortMethod, sortDirection = TASortParams(grp.sortMode, grp.reverseSort)
  local anchorPoint, hDir, vDir = TAFlowParams(grp.growDirection, grp.growUpward == true)

  local layout = {
    elementSpacing = spacing,
    lineSpacing = rowGap,
    elementWidth = size,
    elementHeight = size,
    layoutIndex = 1,
  }

  if not state.groupCreated then
    local okAdd = pcall(function()
      c:AddAuraGroup(state.key, filter, {
        maxFrameCount = perRow * numRows,
        candidateFilters = {},
        sortMethod = sortMethod,
        sortDirection = sortDirection,
        layout = layout,
        initializeFrame = function(auraButton)
          local okCheck, canAccess = pcall(function()
            return auraButton.CanBeAccessedInContext and auraButton:CanBeAccessedInContext()
          end)
          if not (okCheck and canAccess) then return end
          local okBuild = pcall(CreateNativeButtonWidgets, auraButton, isDebuff)
          if okBuild then
            state.pool[#state.pool + 1] = auraButton
          end
          ApplyNativeButtonStyle(auraButton, GrpCfg(isDebuff and "debuffs" or "buffs"), isDebuff)
        end,
      })
    end)
    if okAdd then state.groupCreated = true end
  else
    pcall(c.SetAuraGroupFilterString, c, state.key, filter)
    pcall(c.SetAuraGroupCandidateFilters, c, state.key, {})
    pcall(c.SetAuraGroupMaxFrameCount, c, state.key, perRow * numRows)
    pcall(c.SetAuraGroupSortMethod, c, state.key, sortMethod, sortDirection)
    pcall(c.SetAuraGroupLayout, c, state.key, layout)
  end

  pcall(c.SetFlowLayoutAnchorPoint, c, anchorPoint)
  pcall(c.SetFlowLayoutAxis, c, 0) -- 0 = horizontal (numérique obligatoire, cf. AuraTrackerContainer.lua)
  pcall(c.SetFlowLayoutGrowthDirection, c, hDir, vDir)
  pcall(c.SetFlowLayoutMaximumLineSize, c, (size + spacing) * perRow - spacing + 1)

  c:ClearAllPoints()
  c:SetPoint(anchorPoint, rowFrame, anchorPoint, 0, 0)

  for _, btn in ipairs(state.pool) do
    ApplyNativeButtonStyle(btn, grp, isDebuff)
  end
end

---------------------------------------------------------------------------
-- /tadebug : diagnostic API brute (GetAuraSlots + énumération legacy) --
-- confirme que les deux échouent en combat sur "target". Ne reflète plus le
-- pipeline de rendu réel (natif désormais), gardé pour diagnostic futur.
---------------------------------------------------------------------------
local function DebugDumpTargetAuras(filter)
  filter = filter == "debuff" and "HARMFUL" or "HELPFUL"
  local unit = "target"
  local P = "|cff00ffff[TA-DEBUG]|r "
  print(P .. string.format("unit=%s filter=%s UnitExists=%s InCombat=%s",
    unit, filter, tostring(UnitExists(unit)), tostring(InCombatLockdown and InCombatLockdown())))
  if not GetAuraSlots then
    print(P .. "|cffff4444C_UnitAuras.GetAuraSlots indisponible sur ce client.|r")
    return
  end
  local ok, token, s1,s2,s3,s4,s5,s6,s7,s8,s9,s10 = pcall(GetAuraSlots, unit, filter)
  print(P .. string.format("GetAuraSlots : pcall_ok=%s token=%s (10 premiers slots) %s,%s,%s,%s,%s,%s,%s,%s,%s,%s",
    tostring(ok), tostring(token), tostring(s1),tostring(s2),tostring(s3),tostring(s4),tostring(s5),
    tostring(s6),tostring(s7),tostring(s8),tostring(s9),tostring(s10)))
  local slots = {}
  if ok then
    local allSlots = { s1,s2,s3,s4,s5,s6,s7,s8,s9,s10 }
    for _, slot in ipairs(allSlots) do
      if slot then
        local okD, aura = pcall(GetAuraDataBySlot, unit, slot)
        if okD and aura then slots[#slots + 1] = aura end
      end
    end
  else
    print(P .. "|cffffaa00GetAuraSlots a echoue -- test de l'enumeration legacy (GetAuraDataByIndex, 1 slot a la fois).|r")
    local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not GetAuraDataByIndex then
      print(P .. "|cffff4444C_UnitAuras.GetAuraDataByIndex indisponible sur ce client.|r")
    else
      for i = 1, 10 do
        local okI, errOrAura = pcall(GetAuraDataByIndex, unit, i, filter)
        print(P .. string.format("  legacy #%d : pcall_ok=%s %s", i, tostring(okI),
          okI and ("aura=" .. tostring(errOrAura ~= nil)) or ("err=" .. tostring(errOrAura))))
      end
    end
  end
  print(P .. string.format("%d aura(s) lisible(s) via l'API brute -- le rendu reel passe desormais par l'AuraContainer natif (unit=target), immunise a cet echec.", #slots))
end

SLASH_TADEBUG1 = "/tadebug"
SlashCmdList["TADEBUG"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  DebugDumpTargetAuras(msg == "debuff" and "debuff" or "buff")
end

-- /tanative : état des conteneurs/groupes natifs (creation, taille du pool,
-- filtre courant) -- pour verifier en jeu que le rendu natif est bien
-- alimente sans avoir a deviner.
SLASH_TANATIVE1 = "/tanative"
SlashCmdList["TANATIVE"] = function()
  local P = "|cff00ffff[TA-NATIVE]|r "
  local function dump(label, state)
    print(P .. string.format("%s : container=%s groupCreated=%s poolSize=%d",
      label, tostring(state.container ~= nil), tostring(state.groupCreated), #state.pool))
    if state.container then
      print(P .. string.format("  IsShown=%s", tostring(state.container:IsShown())))
    end
  end
  dump("Buffs", buffState)
  dump("Debuffs", debuffState)
  print(P .. string.format("SORTMETHOD present=%s SORTDIRECTION present=%s AuraButtonBorderStyle present=%s",
    tostring(SORTMETHOD ~= nil), tostring(SORTDIRECTION ~= nil), tostring(AURA_BORDER_STYLE ~= nil)))
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnEvent(self, event)
  if event == "PLAYER_TARGET_CHANGED" then
    if buffState.container and buffState.container.UpdateAllAuras then
      pcall(buffState.container.UpdateAllAuras, buffState.container)
    end
    if debuffState.container and debuffState.container.UpdateAllAuras then
      pcall(debuffState.container.UpdateAllAuras, debuffState.container)
    end
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

  frame = CreateFrame("Frame", "AishCoreTargetAuras", parent or UIParent)
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

  frame:ClearAllPoints()
  frame:SetPoint("TOP", UIParent, "TOP", 0, 0)
  frame:SetSize(maxRowW, bRowH + dRowH + 10)

  buffRow:ClearAllPoints()
  buffRow:SetSize(bRowW, bRowH)
  buffRow:SetPoint("TOP", UIParent, "TOP", bGrp.offsetX or 0, bGrp.offsetY or -40)

  debuffRow:ClearAllPoints()
  debuffRow:SetSize(dRowW, dRowH)
  debuffRow:SetPoint("TOP", UIParent, "TOP", dGrp.offsetX or 0, dGrp.offsetY or -70)

  -- Style des icônes de preview existantes
  StyleIcons(buffIcons, bGrp)
  StyleIcons(debuffIcons, dGrp)

  -- Rendu réel (natif, combat-safe)
  ConfigureNativeRow(buffState, buffRow, "HELPFUL", bGrp, false)
  ConfigureNativeRow(debuffState, debuffRow, "HARMFUL", dGrp, true)

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

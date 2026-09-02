-- UI/MinimapButton.lua : Bouton circulaire autour de la minimap
-- Clic gauche : ouvrir/fermer le panneau de config
-- Glisser (clic gauche) : repositionner autour de la minimap
local addonName, ns = ...
local L = ns.L

-- Format recommandé : TGA 32-bit avec canal alpha (fond transparent)
-- Placer le fichier dans : Media/logo.tga
local ICON_PATH   = "Interface\\AddOns\\AishCore\\Media\\logo_icon.tga"
local BUTTON_SIZE = 32
local RADIUS      = 80   -- distance du centre de la minimap

---------------------------------------------------------------------------
-- Création du bouton
---------------------------------------------------------------------------
local btn = CreateFrame("Button", "AishCoreMinimapButton", Minimap)
btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetMovable(true)

-- Icône (le TGA gère lui-même la transparence, pas besoin de masque)
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetTexture(ICON_PATH)
icon:SetAllPoints()

-- Highlight au survol : léger assombrissement
local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
highlight:SetColorTexture(1, 1, 1, 0.15)
highlight:SetAllPoints()

---------------------------------------------------------------------------
-- Positionnement
---------------------------------------------------------------------------
local function UpdatePosition()
  local cfg = ns.DB and ns.DB.minimapButton
  local angle = math.rad(cfg and cfg.angle or 225)
  local x = math.cos(angle) * RADIUS
  local y = math.sin(angle) * RADIUS
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

---------------------------------------------------------------------------
-- Drag : repositionner autour de la minimap à la souris
---------------------------------------------------------------------------
local isDragging = false

btn:RegisterForDrag("LeftButton")

btn:SetScript("OnDragStart", function(self)
  isDragging = true
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    cx, cy = cx / s, cy / s
    local angle = math.deg(math.atan2(cy - my, cx - mx))
    ns.DB.minimapButton = ns.DB.minimapButton or {}
    ns.DB.minimapButton.angle = angle
    UpdatePosition()
  end)
end)

btn:SetScript("OnDragStop", function(self)
  self:SetScript("OnUpdate", nil)
  -- Petit délai pour ignorer le OnClick qui suit
  C_Timer.After(0.05, function() isDragging = false end)
end)

---------------------------------------------------------------------------
-- Clic gauche : ouvrir / fermer le panneau
---------------------------------------------------------------------------
btn:SetScript("OnClick", function(self, button)
  if button == "LeftButton" and not isDragging then
    if ns.SettingsPanel then
      ns.SettingsPanel:Toggle()
    end
  end
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
btn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["MINIMAP_TOOLTIP_TITLE"], 0, 0.69, 1)
  GameTooltip:AddLine(L["MINIMAP_TOOLTIP_LEFT_CLICK"], 1, 1, 1)
  GameTooltip:AddLine(L["MINIMAP_TOOLTIP_DRAG"], 0.8, 0.8, 0.8)
  GameTooltip:Show()
end)

btn:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Initialisation après chargement de la DB (PLAYER_ENTERING_WORLD)
---------------------------------------------------------------------------
ns.MinimapButton = {}

function ns.MinimapButton.Init()
  ns.DB.minimapButton = ns.DB.minimapButton or { angle = 225, hidden = false }
  UpdatePosition()
  if ns.DB.minimapButton.hidden then
    btn:Hide()
  else
    btn:Show()
  end
end

-- Masquer / afficher depuis la console ou les settings
function ns.MinimapButton.SetHidden(hidden)
  ns.DB.minimapButton = ns.DB.minimapButton or {}
  ns.DB.minimapButton.hidden = hidden
  if hidden then btn:Hide() else btn:Show() end
end

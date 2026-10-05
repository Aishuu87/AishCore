-- Modules/Location.lua : nom de zone / sous-zone en overlay (equivalent LocationPlus).
-- Texte unique "Zone : Sous-zone", tronque a la largeur configuree, avec masquage en
-- combat et mode mouseover (opacite reduite hors survol).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local Location = {}
ns.Modules.Location = Location

local DEFAULTS = {
    point = "TOP", relativePoint = "TOP", x = 0, y = -12,
    width = 240, fontSize = 14, align = "CENTER",
    font = "Fonts\\2002.TTF",
}

-- Couleurs de statut PvP (memes valeurs que LocationPlus, pour retrouver le meme rendu)
local PVP_COLORS = {
    sanctuary = { 0.41, 0.80, 0.94 },
    arena     = { 1.00, 0.10, 0.10 },
    friendly  = { 0.10, 1.00, 0.10 },
    hostile   = { 1.00, 0.10, 0.10 },
    contested = { 1.00, 0.70, 0.10 },
    combat    = { 1.00, 0.10, 0.10 },
}
local PVP_COLOR_INSTANCE = { 1.00, 0.10, 0.10 }
local PVP_COLOR_DEFAULT  = { 1.00, 0.70, 0.10 }  -- territoire conteste (repli LocationPlus)

-- Vitesse du fondu mouseover (ease exponentiel, cf. Modules/Visibility.lua)
local FADE_SPEED = 8

local frame, text, textSlug
local dragUnlocked = false
local currentAlpha = 1
local lastLine     = nil

local function Cfg()
    return ns.GetCfg("location") or {}
end

local function ZoneStatusColor()
    local pvpType = GetZonePVPInfo and GetZonePVPInfo()
    local c = pvpType and PVP_COLORS[pvpType]
    if c then return c end
    if IsInInstance() then return PVP_COLOR_INSTANCE end
    return PVP_COLOR_DEFAULT
end

-- "Zone: Sous-zone" quand les deux different, sinon le libelle disponible.
local function BuildLine(cfg)
    local subZone = (GetMinimapZoneText and GetMinimapZoneText()) or ""
    local zone    = (GetRealZoneText and GetRealZoneText()) or UNKNOWN or ""
    if cfg.showZone == false then
        return (subZone ~= "" and subZone) or zone
    end
    if subZone ~= "" and subZone ~= zone then
        return zone .. ": " .. subZone
    end
    return (subZone ~= "" and subZone) or zone
end

-- Ancres self/relative selon l'alignement : le texte reste colle au bord choisi de la boite
local function TextAnchor(align)
    if align == "LEFT"  then return "LEFT",  "LEFT"  end
    if align == "RIGHT" then return "RIGHT", "RIGHT" end
    return "CENTER", "CENTER"
end

-- Opacite visee : 0 si masque en combat, `hoverAlpha` quand le curseur est dessus en mode
-- mouseover, `alpha` le reste du temps (mode mouseover ou non).
function Location.TargetAlpha(cfg)
    cfg = cfg or Cfg()
    local alpha = cfg.alpha
    if alpha == nil then alpha = 1 end
    if dragUnlocked then return 1 end
    if cfg.hideInCombat and UnitAffectingCombat("player") then return 0 end
    if cfg.mouseover and ns.IsFrameMouseOver(frame) then
        local hover = cfg.hoverAlpha
        if hover == nil then hover = 1 end
        return hover
    end
    return alpha
end

function Location.Create(parent)
    if frame then return end
    local cfg = Cfg()

    frame = CreateFrame("Frame", "AishCoreLocation", parent or UIParent)
    frame:SetSize(cfg.width or DEFAULTS.width, (cfg.fontSize or DEFAULTS.fontSize) + 8)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)   -- reactive seulement pendant le drag (sinon capte les clics monde)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not dragUnlocked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not ns.DB          then ns.DB = {} end
        if not ns.DB.location then ns.DB.location = {} end
        local point, _, relativePoint, ox, oy = self:GetPoint(1)
        ns.DB.location.point         = point
        ns.DB.location.relativePoint = relativePoint
        ns.DB.location.x = ox
        ns.DB.location.y = oy
    end)
    frame:SetPoint(cfg.point or DEFAULTS.point, UIParent,
                   cfg.relativePoint or DEFAULTS.relativePoint,
                   cfg.x or DEFAULTS.x, cfg.y or DEFAULTS.y)

    text = frame:CreateFontString(nil, "OVERLAY")
    textSlug = ns.CreateSlugRing(frame, text)

    -- Fondu mouseover : IsFrameMouseOver plutot que OnEnter/OnLeave -- la frame n'a pas
    -- de zone souris active en jeu normal, et un OnLeave manque ne fige donc rien.
    frame:SetScript("OnUpdate", function(self, elapsed)
        local target = Location.TargetAlpha()
        if currentAlpha == target then return end   -- etat stable : rien a reposer
        if math.abs(currentAlpha - target) > 0.002 then
            currentAlpha = currentAlpha + (target - currentAlpha) * (1 - math.exp(-FADE_SPEED * elapsed))
        else
            currentAlpha = target
        end
        self:SetAlpha(currentAlpha)
    end)

    Location.ApplySettings()
end

-- Recalcule le libelle et sa couleur (changement de zone + ticker de secours).
function Location.Update()
    if not frame then return end
    local cfg = Cfg()

    local line = BuildLine(cfg)
    if line ~= lastLine then
        lastLine = line
        text:SetText(line)
    end

    local r, g, b, a
    if cfg.useZoneColor == false then
        local c = cfg.textColor or { 1, 1, 1, 1 }
        r, g, b, a = c[1], c[2], c[3], c[4] or 1
    else
        local c = ZoneStatusColor()
        r, g, b = c[1], c[2], c[3]
        a = (cfg.textColor and cfg.textColor[4]) or 1
    end
    text:SetTextColor(r, g, b, a)
end

function Location.ApplySettings()
    if not frame then return end
    local cfg = Cfg()

    if cfg.enabled == false then
        frame:Hide()
        return
    end
    frame:Show()

    local width = cfg.width    or DEFAULTS.width
    local size  = cfg.fontSize or DEFAULTS.fontSize
    local align = cfg.align    or DEFAULTS.align

    frame:SetSize(width, size + 8)
    frame:ClearAllPoints()
    frame:SetPoint(cfg.point or DEFAULTS.point, UIParent,
                   cfg.relativePoint or DEFAULTS.relativePoint,
                   cfg.x or DEFAULTS.x, cfg.y or DEFAULTS.y)

    ns.ApplyTextOutlineStyle(text, textSlug, cfg.font or DEFAULTS.font, size,
                             cfg.textOutlineStyle, false)
    -- Ombre portee geree ici et non par ApplyTextOutlineStyle : elle est optionnelle, et
    -- doit rester eteinte en style SLUG ou elle se cumulerait avec l'anneau.
    if cfg.shadow and cfg.textOutlineStyle ~= "SLUG" then
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    else
        text:SetShadowOffset(0, 0)
    end

    -- Troncature : largeur fixe + pas de retour a la ligne, WoW coupe alors avec "..."
    text:SetWidth(width)
    text:SetWordWrap(false)
    text:SetMaxLines(1)
    text:SetJustifyH(align)   -- hook de CreateSlugRing : l'anneau suit
    text:SetJustifyV("MIDDLE")
    local selfPt, relPt = TextAnchor(align)
    text:ClearAllPoints()
    text:SetPoint(selfPt, frame, relPt, 0, 0)
    for _, fs in ipairs(textSlug) do
        fs:SetWordWrap(false)
        fs:SetMaxLines(1)
    end

    frame:EnableMouse(dragUnlocked)

    -- Invalide le cache de libelle : un FontString deja rendu ne se repositionne pas sur
    -- un simple SetJustifyH (seul un SetFont/SetText le relayout), donc changer
    -- l'alignement ne se voyait qu'au prochain changement de police ou de contour.
    lastLine = nil
    Location.Update()
end

-- Mode placement : la frame capte la souris et repasse en pleine opacite.
function Location.SetDragUnlocked(val)
    dragUnlocked = val and true or false
    if frame then frame:EnableMouse(dragUnlocked) end
end

-- Cible du survol GUI (cf. UI/ModuleHoverOverlay.lua)
function Location.GetHoverFrame()
    return frame
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    Location.Update()
end)

-- Filet de secours : GetMinimapZoneText change parfois sans evenement (meme approche que
-- LocationPlus). Les changements de zone passent de toute facon par les evenements ci-dessus,
-- ce ticker ne rattrape que les cas muets : 2 s suffisent largement.
-- Comparaison de chaine d'abord, donc aucun SetText inutile.
C_Timer.NewTicker(2, function()
    if frame and frame:IsShown() then Location.Update() end
end)

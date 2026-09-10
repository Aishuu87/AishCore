-- AishUIAura/Core/ClassColors.lua : couleurs de classe pour les barres HUD + redirection Theme.accent vers l'or AISHUI
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.CLASS_COLORS = {
    DRUID       = { { 1.000, 0.231, 0.039 }, { 1.000, 0.490, 0.278 } },
    ROGUE       = { { 1.000, 0.961, 0.412 }, { 1.000, 0.980, 0.700 } },
    WARRIOR     = { { 0.780, 0.610, 0.430 }, { 0.900, 0.760, 0.580 } },
    DEATHKNIGHT = { { 0.627, 0.835, 0.376 }, { 0.780, 0.920, 0.530 } },
    HUNTER      = { { 0.957, 0.376, 0.102 }, { 1.000, 0.550, 0.300 } },
    MAGE        = { { 0.098, 0.749, 1.000 }, { 0.350, 0.850, 1.000 } },
    PALADIN     = { { 1.000, 0.925, 0.847 }, { 1.000, 0.960, 0.920 } },
    WARLOCK     = { { 0.529, 0.529, 0.929 }, { 0.700, 0.700, 1.000 } },
    PRIEST      = { { 1.000, 1.000, 1.000 }, { 1.000, 1.000, 1.000 } },
    SHAMAN      = { { 0.067, 0.533, 1.000 }, { 0.300, 0.680, 1.000 } },
    MONK        = { { 0.392, 1.000, 0.902 }, { 0.580, 1.000, 0.950 } },
    DEMONHUNTER = { { 0.471, 0.220, 0.780 }, { 0.650, 0.400, 0.900 } },
    EVOKER      = { { 1.000, 0.031, 0.082 }, { 1.000, 0.300, 0.350 } },
}

do
    local _, cls = UnitClass("player")
    local c = ns.CLASS_COLORS[cls]
    ns.barColor    = c and c[1] or { 1, 0.231, 0.039 }
    ns.sparkColor  = c and c[2] or { 1, 0.490, 0.278 }
    -- Thème AISHUI Black & Gold : redirige Theme.accent vers l'or (ns.barColor garde la couleur de classe)
    if ns.THEME then
        local g = ns.THEME.gold or { 0.78, 0.62, 0.30 }
        ns.THEME.accent     = { g[1], g[2], g[3] }
        ns.THEME.checkboxOn = { g[1], g[2], g[3] }
    end
end

-- Accent thématique du GUI Auras (dots/texte des headers), équivalent SharedWidgets.RefreshAccentTheme
-- pour le namespace _addon.Auras.THEME. Gate par _addon.DB.colors.themeGUI (actif par défaut).
local ACCENT_STATIC      = { 0.78, 0.62, 0.30 }
local ACCENT_TEXT_STATIC = { 0.776, 0.710, 0.471 }
function ns.RefreshAccentTheme()
    if not ns.THEME then return end
    local useTheme = not (_addon.DB and _addon.DB.colors and _addon.DB.colors.themeGUI == false)
    local g, tc = ACCENT_STATIC, ACCENT_TEXT_STATIC
    if useTheme then
        local CLR = _addon.Modules and _addon.Modules.Colors
        local dc = CLR and CLR.Get and CLR.Get("powerdotsa")
        if dc then g = dc end
        local tt = CLR and CLR.Get and CLR.Get("powerdotsb")
        if tt then tc = tt end
    end
    ns.THEME.gold       = ns.THEME.gold or {}
    ns.THEME.accent     = ns.THEME.accent or {}
    ns.THEME.accentText = ns.THEME.accentText or {}
    for i = 1, 3 do
        ns.THEME.gold[i]       = g[i]
        ns.THEME.accent[i]     = g[i]
        ns.THEME.accentText[i] = tc[i]
    end
    ns.THEME.checkboxOn = ns.THEME.accent
    if ns.SharedWidgets and ns.SharedWidgets.RefreshSectionHeaderColors then
        ns.SharedWidgets.RefreshSectionHeaderColors()
    end
end

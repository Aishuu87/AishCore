-- AishUIAura/UI/CategoryDispatcher.lua
-- ============================================================================
-- Routeur qui prend (catId, sectionId) et appelle le bon builder de menu existant.
--
-- Le dispatcher ne crée PAS les menus lui-même, il se contente de :
--   1. Trouver la section dans ns.CATEGORIES
--   2. Regarder son champ `builder` (+ éventuel `builderArg`)
--   3. Appeler la fonction ns.SettingsPanel.BuildXxxMenu(parent, width, arg)
--      ou afficher un placeholder "À venir" si `builder` est nil
--
-- Les builders existants (dans UI/Menus/*.lua) sont réutilisés tels quels,
-- aucune modification n'est nécessaire côté menus.
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}
ns.CategoryDispatcher = {}

local CreateFrame, pcall = CreateFrame, pcall

-- ============================================================================
-- Placeholder "À venir" pour sections non-encore-branchées (Aishaddon futur)
-- ============================================================================
local function BuildPlaceholder(parent, contentW, section)
    local FONT = ns.Media.font
    local Theme = ns.THEME

    -- Cartouche central
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(math.min(contentW - 40, 400), 200)
    card:SetPoint("TOP", 0, -60)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local cardBg = (Theme.cardBg) or { 0.05, 0.05, 0.06 }
    card:SetBackdropColor(cardBg[1], cardBg[2], cardBg[3], 1)
    card:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)

    -- Titre "À venir"
    local gold = Theme.gold or { 0.78, 0.62, 0.30 }
    local title = card:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(title, FONT, 16)
    title:SetPoint("TOP", 0, -30)
    title:SetTextColor(gold[1], gold[2], gold[3], 1)
    title:SetText(L["AURASMENU_CATDISP_COMING_SOON"])

    -- Nom de la section
    local name = card:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(name, FONT, 14)
    name:SetPoint("TOP", title, "BOTTOM", 0, -14)
    name:SetTextColor(unpack(Theme.textNormal))
    name:SetText(section.label or "")

    -- Explication
    local desc = card:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(desc, FONT, 11)
    desc:SetPoint("TOP", name, "BOTTOM", 0, -16)
    desc:SetPoint("LEFT", 20, 0); desc:SetPoint("RIGHT", -20, 0)
    desc:SetJustifyH("CENTER")
    desc:SetTextColor(unpack(Theme.textDim))
    desc:SetText(L["AURASMENU_CATDISP_COMING_SOON_DESC"])

    -- Source tag
    local textDisabled = Theme.textDisabled or { 0.40, 0.40, 0.42 }
    local source = card:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(source, FONT, 9)
    source:SetPoint("BOTTOM", 0, 14)
    source:SetTextColor(textDisabled[1], textDisabled[2], textDisabled[3], 1)
    source:SetText(string.format(L["AURASMENU_CATDISP_SOURCE_LABEL"], (section.source or "?")))

    return card
end

-- ============================================================================
-- Dispatch principal
-- ============================================================================
-- Appelé par le UnifiedPanel quand l'utilisateur clique une section dans la sidebar.
-- Retourne la frame créée (pour que le panel puisse la gérer).
--
-- @param parent   Frame parente (zone de contenu)
-- @param contentW Largeur de la zone de contenu
-- @param catId    ID de la catégorie active (ex: "mesSorts")
-- @param sectionId ID de la section à afficher (ex: "debuffs")
-- @return frame   La frame qui contient le menu, ou nil en cas d'erreur
function ns.CategoryDispatcher.ShowSection(parent, contentW, catId, sectionId)
    if not parent or not catId or not sectionId then return nil end

    local section = ns.GetSection(catId, sectionId)
    if not section then
        -- Section introuvable : affiche un message d'erreur doux
        local Theme = ns.THEME
        local err = parent:CreateFontString(nil, "OVERLAY")
        ns.ApplyFont(err, ns.Media.font, 12)
        err:SetPoint("TOP", 0, -40)
        err:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3], 1)
        err:SetText(string.format(L["AURASMENU_CATDISP_SECTION_NOT_FOUND"], tostring(catId), tostring(sectionId)))
        return err
    end

    -- Pas d'en-tête orné ici : les menus internes ont déjà leurs propres SectionHeader
    -- (● DISPOSITION, ● SECTION, etc.) qui jouent ce rôle. Mettre un ● DEBUFFS en plus
    -- au-dessus ferait 2 dots rapprochés = trop redondant visuellement.
    -- Le titre de la section est déjà visible dans la sidebar (or) et dans le tab rouge.

    -- Si la section a un builder défini, on l'appelle
    if section.builder and ns.SettingsPanel[section.builder] then
        local fn = ns.SettingsPanel[section.builder]
        -- Wrapper centré : on réserve une largeur généreuse pour que les menus
        -- existants (codés autour de 470px de large) aient toute la place, et on
        -- centre horizontalement le wrapper dans le parent.
        -- On permet maintenant jusqu'à 700px de large pour mieux occuper l'espace
        -- quand la preview est cachée (zone contenu peut atteindre ~780px).
        local wrapperW = math.max(440, math.min(contentW - 20, 700))
        local wrapper = CreateFrame("Frame", nil, parent)
        wrapper:SetWidth(wrapperW)
        wrapper:SetPoint("TOP", parent, "TOP", 0, 0)
        wrapper:SetHeight(1)   -- grandira avec le contenu (les menus ancrent en TOPLEFT)
        local ok, frameOrErr = pcall(fn, wrapper, wrapperW, section.builderArg)
        if ok then
            return wrapper
        else
            -- Erreur d'exécution : affiche un message
            local err = parent:CreateFontString(nil, "OVERLAY")
            ns.ApplyFont(err, ns.Media.font, 11)
            err:SetPoint("TOPLEFT", 10, -10)
            err:SetTextColor(1, 0.4, 0.4, 1)
            err:SetText(string.format(L["AURASMENU_CATDISP_BUILD_ERROR"], tostring(section.builder), tostring(frameOrErr)))
            return err
        end
    end

    -- Sinon, placeholder : cartouche central "À venir".
    local ph = BuildPlaceholder(parent, contentW, section)
    if ph and ph.ClearAllPoints then
        ph:ClearAllPoints()
        ph:SetPoint("TOP", parent, "TOP", 0, -20)
    end
    return ph
end

-- ============================================================================
-- Helper pour l'info-bulle (?) d'une section
-- ============================================================================
-- Retourne le texte de tooltip si défini, sinon nil
function ns.CategoryDispatcher.GetTooltip(catId, sectionId)
    local section = ns.GetSection(catId, sectionId)
    return section and section.tooltip or nil
end

-- ============================================================================
-- Debug helper : liste toutes les sections et leur état (branchée ou placeholder)
-- Utilisation : /run ns.CategoryDispatcher.PrintStatus()
-- ============================================================================
function ns.CategoryDispatcher.PrintStatus()
    print(L["AURASMENU_CATDISP_DEBUG_HEADER"])
    for _, cat in ipairs(ns.CATEGORIES) do
        print(string.format("  |cffc79e4d%s|r (%s)", cat.label, cat.id))
        for _, sec in ipairs(cat.sections) do
            local status
            if sec.builder and ns.SettingsPanel[sec.builder] then
                status = L["AURASMENU_CATDISP_OK_STATUS"]
            elseif sec.builder then
                status = string.format(L["AURASMENU_CATDISP_MISSING_BUILDER"], sec.builder)
            else
                status = L["AURASMENU_CATDISP_PLACEHOLDER_STATUS"]
            end
            print(string.format("    - %-30s %s", sec.label, status))
        end
    end
end

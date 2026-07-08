-- AishUIAura/UI/InfoPanel.lua
-- ============================================================================
-- Panneau d'info contextuelle à droite du panel de config.
--
-- Affiche pour la section active :
--   • Une image preview (si section.preview est défini dans Categories.lua)
--     sinon un cartouche visuel avec le label de la section en gros (fallback)
--   • Le nom de la section en titre
--   • La description (section.desc) en texte dim
--   • Un tag "À venir" discret si la section est un placeholder Aishaddon
--
-- Usage :
--   local info = ns.InfoPanel.Create(parent, width)
--   info:ShowFor(catId, secId)
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.InfoPanel = ns.InfoPanel or {}

local CreateFrame = CreateFrame

-- ============================================================================
-- Création du panneau
-- ============================================================================
-- @param parent Frame parente (le panel principal)
-- @param width  Largeur fixe du panneau (typiquement 240)
-- @return frame La frame InfoPanel (à positionner avec SetPoint)
function ns.InfoPanel.Create(parent, width)
    local Theme = ns.THEME
    local FONT = ns.Media.font
    local gold = Theme.gold or { 0.78, 0.62, 0.30 }

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetWidth(width or 240)
    -- Fond + bordure transparents : quand on est child d'une fenêtre flottante
    -- (previewFrame) qui a déjà son propre cadre, on ne veut pas doubler les
    -- bordures. Le fond du parent fait le boulot.
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0, 0, 0, 0)         -- transparent
    f:SetBackdropBorderColor(0, 0, 0, 0)   -- transparent

    -- Pas d'en-tête orné au-dessus du cadre preview (demandé par l'utilisateur).
    -- Les boutons i/x sont ajoutés par SettingsPanel dans le wrapper en haut-droite,
    -- donc on laisse juste une marge de 40px en haut pour ne pas les chevaucher.

    -- Zone preview : cadre carré en haut qui accueille une image ou un fallback
    local preview = CreateFrame("Frame", nil, f)
    preview:SetPoint("TOPLEFT",  f, "TOPLEFT",  12, -40)
    preview:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -40)
    preview:SetHeight(140)  -- ratio ~16:10
    local previewBg = preview:CreateTexture(nil, "BACKGROUND")
    previewBg:SetAllPoints()
    previewBg:SetColorTexture(0, 0, 0, 0.5)
    local previewImg = preview:CreateTexture(nil, "ARTWORK")
    previewImg:SetAllPoints()
    previewImg:Hide()   -- affichée uniquement si section.preview défini

    -- Bordure fine or autour du cartouche preview
    local previewBorder = CreateFrame("Frame", nil, preview, "BackdropTemplate")
    previewBorder:SetAllPoints()
    previewBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    previewBorder:SetBackdropBorderColor(Theme.border[1], Theme.border[2], Theme.border[3], 0.5)

    -- Texte fallback au centre du cartouche quand pas d'image
    local fallback = preview:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(fallback, FONT, 13)
    fallback:SetPoint("CENTER", 0, 0)
    fallback:SetPoint("LEFT",  10, 0)
    fallback:SetPoint("RIGHT", -10, 0)
    fallback:SetJustifyH("CENTER"); fallback:SetJustifyV("MIDDLE")
    fallback:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3], 1)
    fallback:SetText("")

    -- Tag "À venir" en overlay haut-droite du cartouche (pour les placeholders Aishaddon)
    local comingSoonTag = preview:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(comingSoonTag, FONT, 9)
    comingSoonTag:SetPoint("TOPRIGHT", -6, -6)
    comingSoonTag:SetTextColor(gold[1], gold[2], gold[3], 1)
    comingSoonTag:SetText("")

    -- Titre de la section (sous la preview)
    local title = f:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(title, FONT, 13)
    title:SetPoint("TOPLEFT",  preview, "BOTTOMLEFT",  0, -14)
    title:SetPoint("TOPRIGHT", preview, "BOTTOMRIGHT", 0, -14)
    title:SetJustifyH("LEFT")
    title:SetTextColor(Theme.textHighlight[1], Theme.textHighlight[2], Theme.textHighlight[3], 1)
    title:SetText("")

    -- Description (sous le titre, multi-lignes)
    local desc = f:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(desc, FONT, 10)
    desc:SetPoint("TOPLEFT",  title, "BOTTOMLEFT",  0, -8)
    desc:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -8)
    desc:SetJustifyH("LEFT"); desc:SetJustifyV("TOP")
    desc:SetTextColor(Theme.textDim[1], Theme.textDim[2], Theme.textDim[3], 1)
    desc:SetWordWrap(true); desc:SetNonSpaceWrap(false)
    desc:SetText("")

    -- (Plus de tag "Source :" en bas — demandé par l'utilisateur, rend la preview plus épurée)

    -- Expose les refs en interne pour ShowFor
    f._previewImg    = previewImg
    f._fallback      = fallback
    f._comingSoonTag = comingSoonTag
    f._title         = title
    f._desc          = desc

    -- ------------------------------------------------------------------------
    -- Mise à jour du contenu selon la section active
    -- ------------------------------------------------------------------------
    function f:ShowFor(catId, secId)
        local section = ns.GetSection and ns.GetSection(catId, secId)
        if not section then
            self:Hide()
            return
        end
        -- Ne PAS faire Show() si la preview parent est en mode collapsed
        -- (autrement le contenu de l'InfoPanel ressort chaque fois qu'on change de section)
        local previewParent = self:GetParent()
        if previewParent and previewParent._collapsed then
            return   -- on laisse l'InfoPanel caché, on ne touche pas son contenu
        end
        self:Show()

        -- Image preview ou fallback
        if section.preview then
            pcall(function() self._previewImg:SetTexture(section.preview) end)
            self._previewImg:Show()
            self._fallback:SetText("")
        else
            self._previewImg:Hide()
            -- Fallback neutre : "Aperçu à venir" au lieu du label de la section.
            -- Évite le doublon avec le vrai titre de section affiché juste en dessous.
            self._fallback:SetText("Aperçu à venir")
        end

        -- Tag "À venir" supprimé de la preview : l'info est déjà dans le panneau
        -- central (placeholder "À venir / Cadres d'unités / Cette section sera..."),
        -- pas besoin de la répéter à 30 cm à droite.
        self._comingSoonTag:SetText("")

        -- Titre + description
        self._title:SetText(section.label or "")
        self._desc:SetText(section.desc or "")
    end

    return f
end

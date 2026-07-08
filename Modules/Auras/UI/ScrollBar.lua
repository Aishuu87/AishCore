-- AishUIAura/UI/ScrollBar.lua
-- ============================================================================
-- Scrollbar custom minimaliste.
--
-- Usage :
--   local bar = ns.ScrollBar.Create(parent, scrollFrame)
--   bar:SetPoint("TOPRIGHT", ...); bar:SetPoint("BOTTOMRIGHT", ...)
--
-- Apparence :
--   • Rail : ligne verticale fine (3px) gris très sombre, toujours visible
--   • Thumb : petit rectangle or, 3px au repos → 7px au hover (anim douce)
--   • Pas de flèches haut/bas (épuré)
--   • Se cache auto si aucun scroll nécessaire
--   • Fait le lien avec un ScrollFrame Blizzard standard : écoute OnVerticalScroll
--     + OnScrollRangeChanged, et peut dragger pour faire scroller le parent.
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.ScrollBar = ns.ScrollBar or {}

local CreateFrame = CreateFrame
local math, pcall = math, pcall

local RAIL_WIDTH  = 3
local THUMB_WIDTH = 3
local THUMB_WIDTH_HOVER = 7
local ANIM_SPEED  = 10    -- vitesse lerp du thumb (plus haut = plus rapide)

-- ============================================================================
-- Création d'une scrollbar pour un ScrollFrame Blizzard
-- ============================================================================
-- @param parent       Frame parente (typiquement la zone qui contient le ScrollFrame)
-- @param scrollFrame  Le ScrollFrame Blizzard à piloter
-- @return frame       La frame scrollbar (à positionner avec SetPoint)
function ns.ScrollBar.Create(parent, scrollFrame)
    local Theme = ns.THEME
    local gold  = Theme.gold or { 0.78, 0.62, 0.30 }

    -- Frame conteneur (largeur fixe = THUMB_WIDTH_HOVER pour pas bouger au hover)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(THUMB_WIDTH_HOVER)
    bar:EnableMouse(true)   -- indispensable pour que le thumb soit drag-able

    -- Rail (la ligne verticale de fond, toujours visible)
    local rail = bar:CreateTexture(nil, "BACKGROUND")
    rail:SetWidth(RAIL_WIDTH)
    rail:SetPoint("TOP",    bar, "TOP",    0, 0)
    rail:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    rail:SetColorTexture(1, 1, 1, 1)
    rail:SetVertexColor(gold[1], gold[2], gold[3], 0.15)

    -- Thumb (le curseur or qui représente la position/portion visible)
    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetSize(THUMB_WIDTH, 40)  -- hauteur ajustée dynamiquement
    thumb:SetFrameLevel((bar:GetFrameLevel() or 1) + 5)
    thumb:EnableMouse(true)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints()
    thumbTex:SetColorTexture(1, 1, 1, 1)
    thumbTex:SetVertexColor(gold[1], gold[2], gold[3], 0.75)

    -- État interne pour animation
    bar._curWidth = THUMB_WIDTH
    bar._targetWidth = THUMB_WIDTH
    bar._dragging = false

    -- ------------------------------------------------------------------------
    -- Positionnement & dimensionnement du thumb en fonction du scroll
    -- ------------------------------------------------------------------------
    local function UpdateThumb()
        if not scrollFrame then return end

        local barH = bar:GetHeight()
        if barH <= 1 then return end

        -- API WoW : GetVerticalScrollRange() retourne un seul number (pas un couple)
        local maxScroll = 0
        pcall(function() maxScroll = scrollFrame:GetVerticalScrollRange() or 0 end)

        -- Détection fine : le scrollChild a une hauteur "fictive" large (3000 souvent)
        -- pour garantir que les widgets ne soient jamais coupés. Du coup maxScroll > 0
        -- systématiquement. On regarde si le parent visible (cf) est PLUS PETIT que
        -- le contenu réel (= scrollFrame:GetHeight), sinon on considère qu'il n'y a
        -- rien à scroller et on cache la bar.
        local scrollChild = scrollFrame:GetScrollChild()
        local viewH   = scrollFrame:GetHeight() or 1
        local childH  = (scrollChild and scrollChild:GetHeight()) or viewH

        -- Pas de scroll effectif : on cache complètement la barre
        if maxScroll <= 0 or childH <= viewH + 2 then
            bar:Hide()
            return
        end
        bar:Show()

        -- Hauteur du thumb : proportionnelle à la portion visible du contenu
        local ratio   = math.min(1, viewH / math.max(viewH, childH))
        local thumbH  = math.max(20, math.floor(barH * ratio))
        thumb:SetHeight(thumbH)

        -- Position du thumb : proportionnelle à scrollOffset / maxScroll
        local offset   = scrollFrame:GetVerticalScroll() or 0
        local progress = (maxScroll > 0) and (offset / maxScroll) or 0
        progress = math.max(0, math.min(1, progress))
        local thumbY = (barH - thumbH) * progress

        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -thumbY)
    end
    bar.UpdateThumb = UpdateThumb

    -- ------------------------------------------------------------------------
    -- Hooks sur le ScrollFrame : refresh auto quand scroll ou range change
    -- ------------------------------------------------------------------------
    if scrollFrame:HasScript("OnVerticalScroll") then
        scrollFrame:HookScript("OnVerticalScroll", function() UpdateThumb() end)
    end
    if scrollFrame:HasScript("OnScrollRangeChanged") then
        scrollFrame:HookScript("OnScrollRangeChanged", function() UpdateThumb() end)
    end
    if scrollFrame:HasScript("OnSizeChanged") then
        scrollFrame:HookScript("OnSizeChanged", function() UpdateThumb() end)
    end
    bar:SetScript("OnSizeChanged", UpdateThumb)
    bar:SetScript("OnShow", UpdateThumb)

    -- ------------------------------------------------------------------------
    -- Hover : élargit le thumb
    -- ------------------------------------------------------------------------
    local function OnHoverEnter() bar._targetWidth = THUMB_WIDTH_HOVER end
    local function OnHoverLeave() if not bar._dragging then bar._targetWidth = THUMB_WIDTH end end
    bar:SetScript("OnEnter",   OnHoverEnter)
    bar:SetScript("OnLeave",   OnHoverLeave)
    thumb:SetScript("OnEnter", OnHoverEnter)
    thumb:SetScript("OnLeave", OnHoverLeave)

    -- ------------------------------------------------------------------------
    -- Drag du thumb : convertit le mouvement Y en scroll
    -- ------------------------------------------------------------------------
    thumb:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        bar._dragging = true
        bar._dragStartY = select(2, GetCursorPosition())
        bar._dragStartScroll = scrollFrame:GetVerticalScroll() or 0
    end)
    thumb:SetScript("OnMouseUp", function(self)
        bar._dragging = false
        if not thumb:IsMouseOver() and not bar:IsMouseOver() then
            bar._targetWidth = THUMB_WIDTH
        end
    end)

    -- ------------------------------------------------------------------------
    -- OnUpdate : gère l'animation de largeur + drag
    -- ------------------------------------------------------------------------
    bar:SetScript("OnUpdate", function(self, elapsed)
        -- Animation de largeur (lerp doux)
        if math.abs(self._curWidth - self._targetWidth) > 0.05 then
            self._curWidth = self._curWidth + (self._targetWidth - self._curWidth) * math.min(1, elapsed * ANIM_SPEED)
            thumb:SetWidth(self._curWidth)
        elseif self._curWidth ~= self._targetWidth then
            self._curWidth = self._targetWidth
            thumb:SetWidth(self._curWidth)
        end
        -- Drag : convertit delta curseur en scroll
        if self._dragging then
            local _, cy = GetCursorPosition()
            local dy = (self._dragStartY - cy)  -- descendre = scroll++
            local barH  = bar:GetHeight()
            local thumbH = thumb:GetHeight()
            local maxScroll = scrollFrame:GetVerticalScrollRange() or 0
            local thumbRange = math.max(1, barH - thumbH)
            local newOffset = (self._dragStartScroll or 0) + (dy / thumbRange) * maxScroll
            newOffset = math.max(0, math.min(maxScroll, newOffset))
            scrollFrame:SetVerticalScroll(newOffset)
        end
    end)

    -- Init : calcul du thumb dès que le parent est prêt
    C_Timer.After(0.05, UpdateThumb)

    return bar
end

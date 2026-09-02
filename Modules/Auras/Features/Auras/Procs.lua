-- AishUIAura/Features/Auras/Procs.lua
-- Layout Fury (sous le portrait du joueur)
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
local Inst = {}
ns.RegisterRender("icons", Inst)
local CreateFrame, math, pcall = CreateFrame, math, pcall
local TEXCOORD = 0.07

-- Forward declaration : HideRowModels est defini plus bas mais reference par
-- CreateFuryRow pour le callback _aishHideCleanup.
local HideRowModels

local function Dims()
    local c = ns.db and ns.db.icons or ns.Defaults.icons
    return c.iconW or 26, c.iconH or 26, c.barW or 26, c.barH or 3, c.gap or 4, c.rowGap or 2
end

-- SPARK ajoute pour l'apercu ("icons" n'en avait jamais eu dans l'ancien
-- pipeline). Meme pattern que Cooldowns.lua::CreateSpark. sparkSameAsBar :
-- repli sur ns.barColor (couleur statique par defaut de la barre a la
-- creation) -- pas de suivi dynamique par-aura ici, meme limitation deja
-- acceptee sur les sparks des 3 autres destinations en mode apercu.
local function CreateSpark(bar, cfg)
    if not cfg.sparkEnabled then return nil end
    local s = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    local st = cfg.sparkTexture
    if st and st:find("^atlas:") then
        pcall(function() s:SetAtlas(st:sub(7)) end)
    elseif st and st ~= "" then
        pcall(function() s:SetTexture(ns.ResolveBarTexFromKey(st)) end)
    else
        s:SetTexture(ns.Media.sparkTex)
    end
    s:SetSize(cfg.sparkW or 17, cfg.sparkH or 6)
    s:SetBlendMode("ADD")
    local sameAsBar = cfg.sparkSameAsBar == true
    local r, g, b = ns.sparkColor[1], ns.sparkColor[2], ns.sparkColor[3]
    if sameAsBar then r, g, b = ns.barColor[1], ns.barColor[2], ns.barColor[3]
    elseif cfg.sparkColorR ~= nil then r, g, b = cfg.sparkColorR, cfg.sparkColorG or 0.5, cfg.sparkColorB or 0.5 end
    if sameAsBar or cfg.sparkColorR ~= nil or cfg.sparkGradient then
        pcall(function() s:SetDesaturated(true) end)
    end
    if cfg.sparkGradient then
        s:SetVertexColor(1, 1, 1, cfg.sparkAlpha or 0.9)
        pcall(function()
            s:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(cfg.sparkGradR2 or r*0.2, cfg.sparkGradG2 or g*0.2, cfg.sparkGradB2 or b*0.2, 1))
        end)
    else s:SetVertexColor(r, g, b, cfg.sparkAlpha or 0.9) end
    return s
end


local function CreateFuryRow(cont, i, cfg)
    local iw, ih, bw, bh, gp = Dims()
    local showBar = cfg.showBarUnderIcon ~= false
    local barH = showBar and (cfg.barUnderHeight or 3) or 0
    local rowH = ih + (showBar and (gp + barH) or 0)
    local row = CreateFrame("Frame", "AishIFR"..i, cont); row:SetSize(iw, rowH)
    local barPos = cfg.barPosition or "BOTTOM"
    local ib = CreateFrame("Button", nil, row); ib:SetSize(iw, ih)
    -- Insets négatifs : élargit légèrement la zone de survol au-delà du cadre
    -- visuel pour absorber les écarts d'arrondi pixel entre ib et le Cooldown
    -- superposé (cd), qui pouvaient laisser une fine bande (1-2px) sur un bord
    -- comme seule zone réellement réactive au tooltip.
    ib:SetHitRectInsets(-1, -1, -1, -1)
    ib:SetScript("OnEnter", ns.AuraIconOnEnter)
    ib:SetScript("OnLeave", ns.AuraIconOnLeave)
    if showBar and barPos == "TOP" then ib:SetPoint("BOTTOM") else ib:SetPoint("TOP") end
    local icon = ib:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints()
    icon:SetTexCoord(TEXCOORD, 1-TEXCOORD, TEXCOORD, 1-TEXCOORD)
    local cd = CreateFrame("Cooldown", nil, ib, "CooldownFrameTemplate")
    cd:SetAllPoints(ib)
    cd:EnableMouse(false) -- purement visuel (swipe) : ne doit jamais intercepter le survol de ib
    cd:SetHideCountdownNumbers(true); cd:SetReverse(true)
    cd:SetDrawSwipe(cfg.swipeEnabled == true); cd:SetDrawEdge(cfg.swipeEnabled == true)
    -- Stack text (sublevel 7) — stacks d'aura
    local stCfg = ns.db and ns.db.icons or ns.Defaults.icons
    local st = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(st, stCfg.stackFont or ns.Media.font, stCfg.stackSize or 10, "OUTLINE")
    st:SetPoint(stCfg.stackPos or "BOTTOMRIGHT", ib, stCfg.stackPos or "BOTTOMRIGHT", stCfg.stackOffX or 0, stCfg.stackOffY or 0)
    st:SetJustifyH("RIGHT")
    st:SetTextColor(stCfg.stackColorR or 1, stCfg.stackColorG or 1, stCfg.stackColorB or 1)
    st:Hide()
    ib._stackText = st

    -- Charges text (sublevel 7) — charges de sort (zone visuelle indépendante)
    local ct = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(ct, stCfg.chargesFont or ns.Media.font, stCfg.chargesSize or 10, "OUTLINE")
    ct:SetPoint(stCfg.chargesPos or "TOPLEFT", ib, stCfg.chargesPos or "TOPLEFT", stCfg.chargesOffX or 0, stCfg.chargesOffY or 0)
    ct:SetJustifyH("LEFT")
    ct:SetTextColor(stCfg.chargesColorR or 0.4, stCfg.chargesColorG or 0.7, stCfg.chargesColorB or 1.0)
    ct:Hide()
    ib._chargesText = ct

    -- Duration text (timer icône) — centré sur l'icône
    local dt = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(dt, stCfg.timerFont or ns.Media.font, stCfg.timerSize or 10, "OUTLINE")
    dt:SetPoint("CENTER", ib, "CENTER", stCfg.timerIconOffX or 0, stCfg.timerIconOffY or 0)
    dt:SetJustifyH("CENTER")
    dt:SetTextColor(stCfg.timerColorR or 1, stCfg.timerColorG or 1, stCfg.timerColorB or 1, 0.9)
    dt._lastText = ""
    ib._durText = dt

    local bar, barWrap, spark
    if showBar then
        local wr = CreateFrame("Frame", nil, row); wr:SetSize(iw, barH)
        if barPos == "TOP" then
            wr:SetPoint("BOTTOM", ib, "TOP", 0, gp)
        else
            wr:SetPoint("TOP", ib, "BOTTOM", 0, -gp)
        end
        bar = CreateFrame("StatusBar", nil, wr); bar:SetAllPoints()
        bar:SetStatusBarTexture(ns.ResolveBarTexFromKey(cfg.texture))
        bar:SetMinMaxValues(0, 1); bar:SetValue(1)
        bar:SetReverseFill(cfg.barReverseFill == true)
        bar:SetStatusBarColor(ns.barColor[1], ns.barColor[2], ns.barColor[3])
        local bg = wr:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints()
        local bgR = type(cfg.barBgR) == "number" and cfg.barBgR or 0.055
        local bgG = type(cfg.barBgG) == "number" and cfg.barBgG or 0.055
        local bgB = type(cfg.barBgB) == "number" and cfg.barBgB or 0.055
        bg:SetColorTexture(bgR, bgG, bgB, type(cfg.barBgAlpha) == "number" and cfg.barBgAlpha or 1)
        wr._bar = bar  -- utilise par ShowFill2D pour ancrer la texture sur bar:GetStatusBarTexture()

        -- SPARK : "front" (sur la StatusBar, au-dessus du fill) ou "back"
        -- (sur le wrapper, en-dessous) -- meme convention que les 3 autres
        -- destinations.
        local sparkParent = (cfg.sparkLayer ~= "back") and bar or wr
        spark = CreateSpark(sparkParent, cfg)
        wr._spark = spark
        wr._spark2D = spark

        barWrap = wr
    end
    row:Hide(); row.iconBtn = ib; row.icon = icon; row.iconCD = cd
    -- row.spark (pas seulement wr._spark2D) : Animation.lua::AnimateRender
    -- lit row.spark DIRECTEMENT pour la mise a jour de position par frame
    -- (meme convention que Cooldowns.lua CreateVanguardRow/CreateBannerRow,
    -- single-bar) -- sans ce champ le spark reste cree mais jamais anime/
    -- positionne, donc invisible/fige.
    row.bar = bar; row.wrap = barWrap; row.spark = spark
    row._reverse = (cfg.barReverseFill == true)
    -- Callback de cleanup FX3D appele par DeferHideRow juste avant row:Hide().
    -- Cache les PlayerModels qui ne suivent pas toujours Hide() de leur parent
    -- (quirk Blizzard). Necessaire au decochage d'un sort en cours de tracking.
    row._aishHideCleanup = function() HideRowModels(row) end
    return row
end

------------------------------------------------------------------------
-- 3D MODEL APPLY
------------------------------------------------------------------------
-- Scratch tables réutilisées pour ShowXxxModel (évite alloc par aura par scan si fx3d on)
local _iconModelCfg = {}
local _barModelCfg = {}
local _sparkModelCfg = {}
local _fill2DCfg = {}
local _overlayCfg = {}

-- Helpers hoist pour HideRowModels
-- Note : on NE cache PAS les Fill 2D ici (voir Cooldowns.lua pour la raison)
local function _HideBar(fx, wrap) fx:Hide(wrap, "bar") end
local function _HideSpark(fx, wrap) fx:Hide(wrap, "spark") end
local function _HideIcon(fx, ib) fx:Hide(ib, "icon") end

local function ApplyIconModels(ib, aura)
    if not ns.db or not ns.EffectsActive() or not ns.SpellFX then return end
    if aura.iconModelID and aura.iconModelID > 0 then
        _iconModelCfg.alpha = aura.iconModelA or 0.5
        _iconModelCfg.rotation = aura.iconModelRot or 0
        _iconModelCfg.x = aura.iconModelX or 0
        _iconModelCfg.y = aura.iconModelY or 0
        _iconModelCfg.z = aura.iconModelZ or 0
        _iconModelCfg.scale = aura.iconModelS or 1
        _iconModelCfg.layer = aura.iconModelL or "back"
        _iconModelCfg.fxW = aura.iconFxW or 0
        _iconModelCfg.fxH = aura.iconFxH or 0
        _iconModelCfg.posX = aura.iconPosX or 0
        _iconModelCfg.posY = aura.iconPosY or 0
        ns.SpellFX:Show(ib, "icon", aura.iconModelID, _iconModelCfg)
    else ns.SpellFX:Hide(ib, "icon") end
end

local function ApplyBarModels(wrap, aura)
    if not ns.db or not ns.EffectsActive() or not ns.SpellFX then return end
    -- Cache spellID pour ne hider que si vraie aura change (pas a chaque scan).
    local spellID = aura.spellID
    local prevID = wrap and wrap._fxAuraID
    -- Mode FOND (front) PlayerModel 3D / Mode REMPLISSAGE (mid) Texture 2D
    local mode = aura.barModelMode or "front"
    if (mode == "front" or mode == "back") and aura.barModelID and aura.barModelID > 0 then
        _barModelCfg.alpha = aura.barModelA or 0.5
        _barModelCfg.rotation = aura.barModelRot or 0
        _barModelCfg.x = aura.barModelX or 0
        _barModelCfg.y = aura.barModelY or 0
        _barModelCfg.z = aura.barModelZ or 0
        _barModelCfg.scale = aura.barModelS or 1
        _barModelCfg.layer = aura.barModelL or "back"
        _barModelCfg.mode = mode  -- "front" ou "back"
        _barModelCfg.fxW = aura.barFxW or 0
        _barModelCfg.fxH = aura.barFxH or 0
        _barModelCfg.durObj = aura.durObj
        _barModelCfg.barAlphaWith3D = (ns.db and ns.db.icons and ns.db.icons.barAlphaWith3D) or 1.0
        ns.SpellFX:Show(wrap, "bar", aura.barModelID, _barModelCfg)
        ns.SpellFX:Hide(wrap, "fill")
    elseif mode == "mid" and aura.barFillTex and aura.barFillTex ~= "" then
        _fill2DCfg.texturePath = aura.barFillTex
        _fill2DCfg.alpha = aura.barFillAlpha or 0.7
        _fill2DCfg.tintR = aura.barFillTintR or 1
        _fill2DCfg.tintG = aura.barFillTintG or 1
        _fill2DCfg.tintB = aura.barFillTintB or 1
        _fill2DCfg.scrollSpeed = aura.barFillScroll or 0
        _fill2DCfg.layer = aura.barFillLayer or "front"
        ns.SpellFX:Show(wrap, "fill", nil, _fill2DCfg)
        ns.SpellFX:Hide(wrap, "bar")
    elseif prevID ~= spellID then
        ns.SpellFX:Hide(wrap, "bar")
        ns.SpellFX:Hide(wrap, "fill")
    end
    if wrap then wrap._fxAuraID = spellID end
    if aura.sparkModelID and aura.sparkModelID > 0 then
        _sparkModelCfg.alpha = aura.sparkModelA or 0.7
        _sparkModelCfg.rotation = aura.sparkModelRot or 0
        _sparkModelCfg.x = aura.sparkModelX or 0
        _sparkModelCfg.y = aura.sparkModelY or 0
        _sparkModelCfg.z = aura.sparkModelZ or 0
        _sparkModelCfg.scale = aura.sparkModelS or 0.5
        _sparkModelCfg.layer = aura.sparkModelL or "front"
        ns.SpellFX:Show(wrap, "spark", aura.sparkModelID, _sparkModelCfg)
    else ns.SpellFX:Hide(wrap, "spark") end
    -- Animated texture overlay
    if aura.barOverlayTex and aura.barOverlayTex ~= "" then
        if not wrap._barOverlay then wrap._barOverlay = ns.SpellFX:CreateBarOverlay(wrap) end
        if wrap._barOverlay then
            _overlayCfg.texture = aura.barOverlayTex
            _overlayCfg.alpha = aura.barOverlayA or 0.3
            _overlayCfg.speed = aura.barOverlaySpeed or 0.5
            _overlayCfg.color = aura.spellColor
            ns.SpellFX:ShowBarOverlay(wrap._barOverlay, _overlayCfg)
        end
    elseif wrap._barOverlay then ns.SpellFX:HideBarOverlay(wrap._barOverlay) end
end

HideRowModels = function(row)
    if not ns.SpellFX then return end
    pcall(_HideIcon, ns.SpellFX, row.iconBtn)
    if row.wrap then
        pcall(_HideBar, ns.SpellFX, row.wrap)
        pcall(_HideSpark, ns.SpellFX, row.wrap)
    end
end

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------
function Inst:Init()
    -- Cleanup old frames
    local old = ns.renderFrames.icons
    if old then
        if old.rows then for _, r in ipairs(old.rows) do r:Hide(); r:SetParent(nil) end end
        if old.container then old.container:Hide(); old.container:SetParent(nil) end
    end
    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    local maxBars = cfg.maxBars or 4
    local growth = cfg.growth or "LEFT"
    local x, y = cfg.x or -199, cfg.y or -247
    local iw, ih, _, bh, gp, rg = Dims()
    local showBar = cfg.showBarUnderIcon ~= false
    local barH = showBar and (cfg.barUnderHeight or 3) or 0
    local rowH = ih + (showBar and (gp + barH) or 0)
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local contW = isH and (maxBars * iw + (maxBars-1) * rg) or iw
    local contH = isH and rowH or (maxBars * rowH + (maxBars-1) * rg)
    local cont = CreateFrame("Frame", nil, UIParent)
    cont:SetSize(contW, contH); cont:SetFrameStrata("MEDIUM")
    cont:SetMovable(true); cont:SetClampedToScreen(true); _addon.EnableMouseOnlyOnAlt(cont)
    cont:SetPropagateMouseClicks(true)  -- click-through par défaut (caméra, sélection, etc.)
    local rows = {}
    for i = 1, maxBars do rows[i] = CreateFuryRow(cont, i, cfg) end
    cont:ClearAllPoints()
    if growth == "DOWN" then cont:SetPoint("TOP", UIParent, "CENTER", x, y)
    elseif growth == "UP" then cont:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then cont:SetPoint("RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then cont:SetPoint("LEFT", UIParent, "CENTER", x, y)
    else cont:SetPoint("TOP", UIParent, "CENTER", x, y) end
    local lbl = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("BOTTOM", cont, "TOP", 0, 2)
    lbl:SetText("|cffffcc00"..L["AURASFEAT_ALT_DRAG_HINT"].."|r"); lbl:Hide()
    cont:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            s:SetPropagateMouseClicks(false)  -- bloquer la propagation pendant le drag
            s:StartMoving(); lbl:Show()
        end
    end)
    cont:SetScript("OnMouseUp", function(s) s._aishDragging = false; s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)  -- rétablir le click-through
        lbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        if cx and cy and ns.db and ns.db.icons then
            local w, h = s:GetSize()
            local gr = (ns.renderFrames.icons and ns.renderFrames.icons.growth) or "LEFT"
            local saveX = cx*sc-sx
            local saveY = cy*sc-sy
            if gr == "DOWN" then saveY = saveY + h * sc / 2
            elseif gr == "UP" then saveY = saveY - h * sc / 2
            elseif gr == "LEFT" then saveX = saveX + w * sc / 2
            elseif gr == "RIGHT" then saveX = saveX - w * sc / 2
            end
            ns.db.icons.x = saveX; ns.db.icons.y = saveY
        end
    end)
    cont:Show()
    ns.renderFrames.icons = {container=cont, rows=rows, layout="portrait_small", growth=growth}
    ns.UpdateRenderFade("icons")
end

------------------------------------------------------------------------
-- UPDATE : rendu REEL supprime, remplace par le systeme AddAuraGroup natif
-- partage (AuraTrackerContainer.lua, ns.EnsureIconsNativeGrid/
-- RepositionIconsNativeGrid) -- flow anime natif Blizzard, fiable pour toute
-- aura, glow uniforme. Faire tourner les deux rendus en parallele causait
-- une superposition permanente.
--
-- La logique ORIGINALE est conservee telle quelle, UNIQUEMENT pour l'apercu
-- en direct dans le menu "Auras & Procs" -- cf. commentaire equivalent dans
-- Buffs.lua pour le detail complet. Le rendu reel est 100% natif. Inst:Init()
-- reste inchangee.
------------------------------------------------------------------------
function Inst:Update(auras)
    local previewActive = ns._previewBars and (ns._previewMode == "all" or ns._previewMode == "icons")
    if not previewActive then
        if ns.renderFrames.icons and ns.renderFrames.icons.container then
            ns.renderFrames.icons.container:SetAlpha(0)
            ns.renderFrames.icons.container:Hide()
        end
        return
    end

    local gfx = ns.renderFrames.icons; if not gfx then return end
    local cfg = ns.db and ns.db.icons or ns.Defaults.icons
    local rows, growth = gfx.rows, gfx.growth or "LEFT"
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local iw, ih, _, bh, gp, rg = Dims()
    local showBar = cfg.showBarUnderIcon ~= false
    local barH = showBar and (cfg.barUnderHeight or 3) or 0
    local rowH = ih + (showBar and (gp + barH) or 0)
    for _, r in ipairs(rows) do
        ns.MarkRowInactive(r)
    end
    local wl = ns.whitelistByDest and ns.whitelistByDest.icons
    if not ns._procsIDsA then ns._procsIDsA = {}; ns._procsIDsB = {}; ns._procsIDsUseA = true end
    local prevIDs = ns._procsIDsUseA and ns._procsIDsB or ns._procsIDsA
    local curIDs  = ns._procsIDsUseA and ns._procsIDsA or ns._procsIDsB
    wipe(curIDs)
    ns._procsIDsUseA = not ns._procsIDsUseA
    local vis = 0
    for i, row in ipairs(rows) do
        local a = auras[i]; if not a or not a.spellID then break end
        if a.spellID <= 900000 and not (wl and wl[a.spellID]) then break end
        vis = vis + 1
        if row._aishPosIdx ~= vis or row._aishPosGrowth ~= growth then
            row._aishPosIdx = vis
            row._aishPosGrowth = growth
            row:ClearAllPoints()
            local off = (vis - 1) * (isH and (iw + rg) or (rowH + rg))
            if growth == "RIGHT" then row:SetPoint("LEFT", gfx.container, "LEFT", off, 0)
            elseif growth == "LEFT" then row:SetPoint("RIGHT", gfx.container, "RIGHT", -off, 0)
            elseif growth == "UP" then row:SetPoint("BOTTOM", gfx.container, "BOTTOM", 0, off)
            else row:SetPoint("TOP", gfx.container, "TOP", 0, -off) end
        end

        row:Show(); row:SetAlpha(1); ns.CancelDeferredHide(row)

        if a._previewIcon then pcall(ns._SetIconTexture, row.icon, a._previewIcon)
        elseif a.aura then pcall(ns._SetIconTexture, row.icon, a.aura.icon)
        elseif a.spellID then pcall(ns._SetIconTextureFromSpellID, row.icon, a.spellID) end
        row.iconBtn.unit = a.unit or "target"; row.iconBtn.auraInstanceID = a.auraInstanceID
        if cfg.desatOverride ~= nil then row.icon:SetDesaturated(cfg.desatOverride)
        else row.icon:SetDesaturated(a.desat and true or false) end

        if a.durObj then
            pcall(ns._SetCDFromDurObj, row.iconCD, a.durObj)
        elseif a._isPreview then
            -- Les fausses entrees de preview n'ont jamais de durObj (secret,
            -- n'existe pas pour une aura fictive) -- sans ce repli, le
            -- Cooldown ne serait jamais lie, donc son texte de duree natif
            -- resterait vide/fige, peu importe timerIconEnabled.
            -- Cycle 12s synthetique, meme convention que Animation.lua::AnimateBar.
            pcall(row.iconCD.SetCooldown, row.iconCD, GetTime(), 12)
        end
        row.iconCD:SetDrawSwipe(cfg.swipeEnabled == true); row.iconCD:SetDrawEdge(cfg.swipeEnabled == true)
        row.iconCD:SetHideCountdownNumbers(not (cfg.timerIconEnabled))
        if cfg.timerIconEnabled then
            pcall(ns._StyleCountdownFS, row.iconCD,
                cfg.timerFont or ns.Media.font, cfg.timerSize or 10,
                cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
                cfg.timerPos or "CENTER", row.iconBtn, cfg.timerPos or "CENTER",
                cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
        end

        row.iconBtn:SetAlpha(cfg.iconAlpha or 1)
        if ns._ApplyStackCharges then ns._ApplyStackCharges(row.iconBtn, a, cfg) end
        ApplyIconModels(row.iconBtn, a)

        local glIdx = a.glowIdx; local glColor = a.glowColor or a.spellColor; local glAlpha = a.glowAlpha
        local glScale = a.glowScale or 1.0
        local hasGlow = a.spellGlow and glIdx and glIdx > 1
        -- Override render RETIRE, desactive via `false and` -- cf.
        -- AuraTrackerContainer.lua::ApplySpellGlow.
        if false and cfg.glowOverrideIdx and cfg.glowOverrideIdx > 1 then
            glIdx = cfg.glowOverrideIdx; hasGlow = true
            if cfg.glowOverrideR ~= nil then glColor = {cfg.glowOverrideR, cfg.glowOverrideG or 0.5, cfg.glowOverrideB or 0.5} end
            glScale = cfg.glowOverrideScale or glScale; glAlpha = cfg.glowOverrideAlpha or glAlpha
        end
        if cfg.glowEnabled ~= false and hasGlow then
            if ns.ShowGlow then ns.ShowGlow(row.iconBtn, glIdx, glColor, glAlpha, glScale) end
        else if ns.HideGlow then ns.HideGlow(row.iconBtn) end end

        curIDs[a.spellID] = true
        if not prevIDs[a.spellID] and a.procGlowIdx and a.procGlowIdx > 1 then
            if ns.PlayProcStart then ns.PlayProcStart(row.iconBtn, a.procGlowIdx, a.glowColor or a.spellColor, a.procGlowScale) end
        end

        if row.bar then
            ns.ApplyBarColor(row.bar, "icons", a)
            if row.wrap then row.wrap:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrap, a) end
        end
    end

    for _, r in ipairs(rows) do
        if not r._aishActiveNow then
            if ns.HideGlow then pcall(function() ns.HideGlow(r.iconBtn) end) end
            ns.DeferHideRow(r, 0.1)
        end
    end

    -- SetAlpha(1) explicite (pas ns.UpdateRenderFade) : cette fonction route
    -- desormais "icons" vers le conteneur NATIF (rendu reel), pas vers ce
    -- conteneur Lua de preview -- l'appeler ici ne touchait donc jamais
    -- l'alpha de CE conteneur, qui restait bloque a 0 (cf. lecon Buffs.lua).
    gfx.container:Show()
    gfx.container:SetAlpha(1)
end

------------------------------------------------------------------------
-- Debug : /rcicons — état des rows/icônes du render "icons" (survol/tooltip)
------------------------------------------------------------------------
SLASH_AISHICONSDBG1 = "/rcicons"
SlashCmdList["AISHICONSDBG"] = function()
    local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[RCIcons]|r " .. tostring(msg)) end
    local gfx = ns.renderFrames.icons
    if not gfx then p("ns.renderFrames.icons est nil (render pas encore initialisé)"); return end
    p(string.format("container: IsShown=%s Alpha=%.2f", tostring(gfx.container:IsShown()), gfx.container:GetAlpha()))
    p(string.format("ns.AuraIconOnEnter défini=%s ns.AuraIconOnLeave défini=%s",
        tostring(ns.AuraIconOnEnter ~= nil), tostring(ns.AuraIconOnLeave ~= nil)))
    for i, row in ipairs(gfx.rows) do
        local ib = row.iconBtn
        if ib then
            local onEnter = ib:GetScript("OnEnter")
            p(string.format("[row %d] row:IsShown=%s ib:IsShown=%s ib:IsVisible=%s ib:IsMouseEnabled=%s unit=%s auraInstanceID=%s OnEnter==ns.AuraIconOnEnter:%s",
                i, tostring(row:IsShown()), tostring(ib:IsShown()), tostring(ib:IsVisible()),
                tostring(ib:IsMouseEnabled()), tostring(ib.unit), tostring(ib.auraInstanceID),
                tostring(onEnter == ns.AuraIconOnEnter)))
        end
    end
end

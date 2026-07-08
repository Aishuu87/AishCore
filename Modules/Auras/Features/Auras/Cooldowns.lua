-- AishUIAura/Features/Auras/Cooldowns.lua
-- Layouts Vanguard + Sparte + Banner (barres latérales)
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local Cooldowns = {}
ns.RegisterRender("circlebars", Cooldowns)
local CreateFrame, math, pcall = CreateFrame, math, pcall
local DARK, TEXCOORD = 14/255, 0.07

-- Forward declaration : HideRowModels est defini plus bas mais reference par
-- les CreateXxxRow pour le callback _aishHideCleanup.
local HideRowModels

local function Dims()
    local c = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    return c.barW or 147, c.barH or 4, c.iconW or 28, c.iconH or 19, c.gap or 3, c.rowGap or 1
end

local function MakeIcon(parent, w, h, cfg)
    local ib = CreateFrame("Button", nil, parent); ib:SetSize(w, h)
    local icon = ib:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints()
    -- Crop centré : recadre verticalement si le frame est plus large que haut
    -- (ex. 28×19 par défaut) pour ne pas étirer l'icône carrée.
    -- Inverse pour un frame plus haut que large. Carré = trim standard.
    do
        local usable = 1 - 2 * TEXCOORD
        if w > h then
            local vSpan = (h / w) * usable
            icon:SetTexCoord(TEXCOORD, 1 - TEXCOORD, 0.5 - vSpan * 0.5, 0.5 + vSpan * 0.5)
        elseif h > w then
            local uSpan = (w / h) * usable
            icon:SetTexCoord(0.5 - uSpan * 0.5, 0.5 + uSpan * 0.5, TEXCOORD, 1 - TEXCOORD)
        else
            icon:SetTexCoord(TEXCOORD, 1 - TEXCOORD, TEXCOORD, 1 - TEXCOORD)
        end
    end
    local cd = CreateFrame("Cooldown", nil, ib, "CooldownFrameTemplate")
    cd:SetAllPoints(ib)
    cd:SetHideCountdownNumbers(true); cd:SetReverse(true)
    cd:SetDrawSwipe(cfg.swipeEnabled == true); cd:SetDrawEdge(cfg.swipeEnabled == true)
    -- Stack text (sublevel 7) — stacks d'aura
    local stCfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local st = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(st, stCfg.stackFont or ns.Media.font, stCfg.stackSize or 10, "OUTLINE")
    st:SetPoint(stCfg.stackPos or "BOTTOMRIGHT", ib, stCfg.stackPos or "BOTTOMRIGHT", stCfg.stackOffX or 0, stCfg.stackOffY or 0)
    st:SetJustifyH("RIGHT")
    st:SetTextColor(stCfg.stackColorR or 1, stCfg.stackColorG or 1, stCfg.stackColorB or 1)
    st:Hide()
    ib._stackText = st

    -- Charges text (sublevel 7) — charges de sort (Ice Barrier, Blink, etc.)
    local ct = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(ct, stCfg.chargesFont or ns.Media.font, stCfg.chargesSize or 10, "OUTLINE")
    ct:SetPoint(stCfg.chargesPos or "TOPLEFT", ib, stCfg.chargesPos or "TOPLEFT", stCfg.chargesOffX or 0, stCfg.chargesOffY or 0)
    ct:SetJustifyH("LEFT")
    ct:SetTextColor(stCfg.chargesColorR or 0.4, stCfg.chargesColorG or 0.7, stCfg.chargesColorB or 1.0)
    ct:Hide()
    ib._chargesText = ct

    -- Duration text (timer icône) — centré sur l'icône
    local dt = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(dt, stCfg.timerFont or ns.Media.font, stCfg.timerSize or 11, "OUTLINE")
    dt:SetPoint("CENTER", ib, "CENTER", stCfg.timerIconOffX or 0, stCfg.timerIconOffY or 0)
    dt:SetJustifyH("CENTER")
    dt:SetTextColor(stCfg.timerColorR or 1, stCfg.timerColorG or 1, stCfg.timerColorB or 1, 0.9)
    dt._lastText = ""
    ib._durText = dt

    return ib, icon, cd
end

local function CreateSpark(bar, cfg)
    if not cfg.sparkEnabled then return nil end
    local s = bar:CreateTexture(nil, "OVERLAY", nil, 6)
    local st = cfg.sparkTexture
    -- Atlas support (même pattern que Renders/Debuffs.lua) : si la clé commence par
    -- "atlas:", on appelle SetAtlas avec le nom de l'atlas. C'est indispensable pour
    -- le spark "honorsystem-bar-spark" qui est une atlas Blizzard, pas une texture LSM.
    -- Sans ça, ResolveBarTexFromKey retombe sur la texture par défaut (bar générique)
    -- agrandie à la taille du spark → rendu dégueulasse.
    if st and st:find("^atlas:") then
        pcall(function() s:SetAtlas(st:sub(7)) end)
    elseif st and st ~= "" then
        pcall(function() s:SetTexture(ns.ResolveBarTexFromKey(st)) end)
    else
        s:SetTexture(ns.Media.sparkTex)
    end
    s:SetSize(cfg.sparkW or 17, cfg.sparkH or 6)
    s:SetBlendMode("ADD")
    local r, g, b = ns.sparkColor[1], ns.sparkColor[2], ns.sparkColor[3]
    local userOverride = cfg.sparkColorR ~= nil
    if userOverride then r, g, b = cfg.sparkColorR, cfg.sparkColorG or 0.5, cfg.sparkColorB or 0.5 end
    -- CRITICAL : SetVertexColor sur atlas coloré = multiplication des canaux avec
    -- la teinte native (le honor-spark est jaune-doré nativement). Il faut désaturer
    -- l'atlas avant pour que la couleur demandée soit fidèle.
    if userOverride or cfg.sparkGradient then
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

local function MakeBarWrap(parent, w, h, rev, cfg)
    local wr = CreateFrame("Frame", nil, parent); wr:SetSize(w, h)
    local bar = CreateFrame("StatusBar", nil, wr); bar:SetAllPoints()
    bar:SetStatusBarTexture(ns.ResolveBarTexFromKey(cfg.texture)); bar:SetReverseFill(rev)
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:SetStatusBarColor(ns.barColor[1], ns.barColor[2], ns.barColor[3])
    local bg = wr:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints()
    local r = type(cfg.barBgR) == "number" and cfg.barBgR or DARK
    local g = type(cfg.barBgG) == "number" and cfg.barBgG or DARK
    local b = type(cfg.barBgB) == "number" and cfg.barBgB or DARK
    bg:SetColorTexture(r, g, b, type(cfg.barBgAlpha) == "number" and cfg.barBgAlpha or 1)
    wr._bar = bar
    local sparkParent = (cfg.sparkLayer ~= "back") and bar or wr
    local spark = CreateSpark(sparkParent, cfg)
    wr._spark = spark
    wr._spark2D = spark  -- alias pour ShowSparkModel (ancrage du FX3D dessous)

    return wr, bar, spark
end

local function CreateVanguardRow(cont, i, cfg)
    local bw, bh, iw, ih, gp = Dims()
    local iconR = (cfg.iconPos or "RIGHT") == "RIGHT"; local rev = cfg.reverse or false
    local row = CreateFrame("Frame", "AishFVR"..i, cont); row:SetSize(iw + gp + bw, ih)
    local ib, icon, cd = MakeIcon(row, iw, ih, cfg)
    local wr, bar, spark = MakeBarWrap(row, bw, bh, rev, cfg)
    -- ANCRAGE adapte pour l'animation pop : le wrap est ancre cote icone, ce qui
    -- permet a SetWidth(0→barW) de deployer la barre depuis l'icone vers l'exterieur.
    --   - Icone a droite : ib ancre RIGHT du row, wrap ancre RIGHT a gauche de l'icone
    --   - Icone a gauche : ib ancre LEFT du row, wrap ancre LEFT a droite de l'icone
    if iconR then
        ib:SetPoint("RIGHT")
        wr:SetPoint("RIGHT", ib, "LEFT", -gp, 0)
    else
        ib:SetPoint("LEFT")
        wr:SetPoint("LEFT", ib, "RIGHT", gp, 0)
    end
    row:Hide(); row.iconBtn=ib; row.icon=icon; row.iconCD=cd; row.bar=bar; row.wrap=wr; row.spark=spark; row._reverse=rev
    -- Callback de cleanup FX3D appele par DeferHideRow juste avant row:Hide().
    -- Cache les PlayerModels qui ne suivent pas toujours Hide() de leur parent
    -- (quirk Blizzard). Necessaire au decochage d'un sort en cours de tracking.
    row._aishHideCleanup = function() HideRowModels(row) end
    return row
end

local function CreateSparteRow(cont, i, cfg)
    local bw, bh, iw, ih, gp = Dims()
    local row = CreateFrame("Frame", "AishFSR"..i, cont); row:SetSize(bw*2+iw+gp*2, ih)
    local ib, icon, cd = MakeIcon(row, iw, ih, cfg); ib:SetPoint("CENTER")
    local wL, bL, spL = MakeBarWrap(row, bw, bh, true, cfg); wL:SetPoint("RIGHT", ib, "LEFT", -gp, 0)
    local wR, bR, spR = MakeBarWrap(row, bw, bh, false, cfg); wR:SetPoint("LEFT", ib, "RIGHT", gp, 0)
    row:Hide()
    row.iconBtn=ib; row.icon=icon; row.iconCD=cd
    row.barL=bL; row.barR=bR; row.wrapL=wL; row.wrapR=wR; row.sparkL=spL; row.sparkR=spR
    row._aishHideCleanup = function() HideRowModels(row) end
    return row
end

local function CreateBannerRow(cont, i, cfg)
    local bw, bh, iw, ih, gp = Dims()
    local row = CreateFrame("Frame", "AishFBR"..i, cont); row:SetSize(iw, ih + gp + bh)
    local ib, icon, cd = MakeIcon(row, iw, ih, cfg); ib:SetPoint("TOP")
    local wr, bar, spark = MakeBarWrap(row, iw, bh, cfg.reverse or false, cfg)
    wr:SetPoint("TOP", ib, "BOTTOM", 0, -gp)
    row:Hide(); row.iconBtn=ib; row.icon=icon; row.iconCD=cd; row.bar=bar; row.wrap=wr; row.spark=spark; row._isBanner=true
    row._aishHideCleanup = function() HideRowModels(row) end
    return row
end

------------------------------------------------------------------------
-- 3D MODELS
------------------------------------------------------------------------
-- Scratch tables réutilisées pour ShowXxxModel (évite alloc par aura par scan si fx3d on)
local _iconModelCfg = {}
local _barModelCfg = {}
local _sparkModelCfg = {}
local _fill2DCfg = {}
local _overlayCfg = {}

-- Helpers hoist pour HideRowModels (évitent 3 closures pcall par row par scan)
-- Note : on NE cache PAS les Fill 2D ici. ApplyBarModels gere Show/Hide
-- des Fill 2D selon le mode du sort. Si on les cachait ici, on aurait une
-- fenetre Hide -> Show entre 2 scans pendant laquelle UpdateFill2DPart ne
-- tourne pas, et la texture peut etre figee a une largeur incorrecte.
local function _HideBarSpark(fx, wrap)
    fx:Hide(wrap, "bar")
    fx:Hide(wrap, "spark")
end
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
    if not wrap or not ns.db or not ns.EffectsActive() or not ns.SpellFX then return end
    -- Cache spellID pour ne hider que si vraie aura change (pas a chaque scan).
    local spellID = aura.spellID
    local prevID = wrap._fxAuraID
    -- Mode FOND (front) PlayerModel 3D / Mode REMPLISSAGE (mid) Texture 2D
    local mode = aura.barModelMode or "front"
    if (mode == "front" or mode == "back") and aura.barModelID and aura.barModelID > 0 then
        _barModelCfg.alpha = aura.barModelA or 0.5
        _barModelCfg.rotation = aura.barModelRot or 0
        _barModelCfg.x = aura.barModelX or 0
        _barModelCfg.y = aura.barModelY or 0
        _barModelCfg.z = aura.barModelZ or 0
        _barModelCfg.scale = aura.barModelS or 1
        _barModelCfg.layer = aura.barModelL or "mid"
        _barModelCfg.mode = mode  -- "front" ou "back"
        _barModelCfg.fxW = aura.barFxW or 0
        _barModelCfg.fxH = aura.barFxH or 0
        _barModelCfg.durObj = aura.durObj
        _barModelCfg.barAlphaWith3D = (ns.db and ns.db.circlebars and ns.db.circlebars.barAlphaWith3D) or 1.0
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
        -- Aura change vers une sans config FX : on hide les heritages
        ns.SpellFX:Hide(wrap, "bar")
        ns.SpellFX:Hide(wrap, "fill")
    end
    wrap._fxAuraID = spellID
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
    if row.wrap then pcall(_HideBarSpark, ns.SpellFX, row.wrap) end
    if row.wrapL then pcall(_HideBarSpark, ns.SpellFX, row.wrapL) end
    if row.wrapR then pcall(_HideBarSpark, ns.SpellFX, row.wrapR) end
end

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------
function Cooldowns:Init()
    local cfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    if not ns.db or (not ns.db.circlebarsEnabled) then return end
    local old = ns.renderFrames.circlebars
    if old then
        if old.rows then for _, r in ipairs(old.rows) do r:Hide(); r:SetParent(nil) end end
        if old.container then old.container:Hide(); old.container:SetParent(nil) end
    end
    local layout = cfg.layout or "side_large"; local maxBars = cfg.maxBars or 8
    local bw, bh, iw, ih, gp, rg = Dims()
    local rowW, rowH
    if layout == "side_compact" then rowW = bw*2+iw+gp*2; rowH = ih
    elseif layout == "side_banner" then rowW = iw; rowH = ih + gp + bh
    else rowW = iw + gp + bw; rowH = ih end
    local growth = cfg.growth or "DOWN"
    if layout == "side_banner" and cfg.bannerGrowth then growth = cfg.bannerGrowth end
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local cont = CreateFrame("Frame", nil, UIParent)
    if isH then cont:SetSize(maxBars * (rowW + rg), rowH)
    else cont:SetSize(rowW, maxBars * (rowH + rg)) end
    cont:SetFrameStrata("MEDIUM"); cont:SetMovable(true); cont:SetClampedToScreen(true); cont:EnableMouse(true)
    cont:SetPropagateMouseClicks(true)  -- click-through par défaut (caméra, sélection, etc.)
    local rows = {}
    for i = 1, maxBars do
        if layout == "side_compact" then rows[i] = CreateSparteRow(cont, i, cfg)
        elseif layout == "side_banner" then rows[i] = CreateBannerRow(cont, i, cfg)
        else rows[i] = CreateVanguardRow(cont, i, cfg) end
    end
    cont:ClearAllPoints()
    local x, y = cfg.x or -502, cfg.y or 0
    if growth == "UP" then cont:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then cont:SetPoint("RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then cont:SetPoint("LEFT", UIParent, "CENTER", x, y)
    else cont:SetPoint("TOP", UIParent, "CENTER", x, y) end
    local lbl = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("BOTTOM", cont, "TOP", 0, 2); lbl:SetText("|cffffcc00Alt+Drag|r"); lbl:Hide()
    cont:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s:SetPropagateMouseClicks(false)  -- bloquer la propagation pendant le drag
            s:StartMoving(); lbl:Show()
        end
    end)
    cont:SetScript("OnMouseUp", function(s) s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)  -- rétablir le click-through
        lbl:Hide()
        local sx, sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        if cx and cy and ns.db and ns.db.circlebars then
            local w, h = s:GetSize()
            local gr = (ns.renderFrames.circlebars and ns.renderFrames.circlebars.growth) or "DOWN"
            local saveX = cx*sc-sx
            local saveY = cy*sc-sy
            if gr == "DOWN" then saveY = saveY + h * sc / 2
            elseif gr == "UP" then saveY = saveY - h * sc / 2
            elseif gr == "LEFT" then saveX = saveX + w * sc / 2
            elseif gr == "RIGHT" then saveX = saveX - w * sc / 2
            end
            ns.db.circlebars.x = saveX; ns.db.circlebars.y = saveY
        end
    end)
    cont:Show()
    ns.renderFrames.circlebars = {container=cont, rows=rows, layout=layout, growth=growth}
    ns.UpdateRenderFade("circlebars")
end

------------------------------------------------------------------------
-- UPDATE
------------------------------------------------------------------------
function Cooldowns:Update(auras)
    -- INIT FLAG
    if not ns._initComplete then
        if ns.renderFrames.circlebars and ns.renderFrames.circlebars.container then
            ns.renderFrames.circlebars.container:SetAlpha(0)
        end
        return
    end
    if ns.db and (not ns.db.circlebarsEnabled or ns.db.useNativeCDM) then
        if ns.renderFrames.circlebars and ns.renderFrames.circlebars.container then ns.renderFrames.circlebars.container:SetAlpha(0) end
        return
    end
    local gfx = ns.renderFrames.circlebars; if not gfx then return end
    local cfg = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local rows, growth = gfx.rows, gfx.growth or "DOWN"
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local bw, bh, iw, ih, gp, rg = Dims()
    local rowW, rowH
    if gfx.layout == "side_compact" then rowW = bw*2+iw+gp*2; rowH = ih
    elseif gfx.layout == "side_banner" then rowW = iw; rowH = ih+gp+bh
    else rowW = iw+gp+bw; rowH = ih end
    -- Pattern anti-flicker : on marque inactive et on défère le Hide()
    -- de 100ms. Les rows qui sont re-activées plus bas appelleront CancelDeferredHide
    -- et feront Show+alpha1. Les rows vraiment inactives (>100ms) seront cachées pour de bon.
    --
    -- FIX v268 : on ne fait PLUS HideRowModels(r) ici. Ca causait un clignotement
    -- des FX 3D toutes les 50ms en combat (release + reacquire du PlayerModel a
    -- chaque scan). Maintenant ApplyBarModels gere les transitions via _fxAuraID,
    -- et quand la row est vraiment Hide() les enfants 3D deviennent invisibles.
    -- NOTE : HideGlow est intentionnellement absent de cette boucle (meme raison
    -- que Procs.lua : appelé ici, il effacait _glowActiveIdx sur toutes les rows
    -- a chaque scan et redemarrait l'animation du glow en boucle).
    for _, r in ipairs(rows) do
        ns.MarkRowInactive(r)
    end
    local wl = ns.whitelistByDest and ns.whitelistByDest.circlebars
    if not wl then return end
    -- Double-buffer pour éviter l'allocation de curIDs à chaque scan
    if not ns._cdIDsA then ns._cdIDsA = {}; ns._cdIDsB = {}; ns._cdIDsUseA = true end
    local prevIDs = ns._cdIDsUseA and ns._cdIDsB or ns._cdIDsA
    local curIDs  = ns._cdIDsUseA and ns._cdIDsA or ns._cdIDsB
    wipe(curIDs)
    ns._cdIDsUseA = not ns._cdIDsUseA
    local vis = 0
    for i, row in ipairs(rows) do
        local a = auras[i]
        if not a or not a.spellID then break end
        if a.spellID <= 900000 and not (wl and wl[a.spellID]) then break end
        vis = vis + 1
        -- Skip le SetPoint si la row est déjà à la bonne position
        -- (évite reflow Blizzard redondant, gain perceptible en multi-rows)
        if row._aishPosIdx ~= vis or row._aishPosGrowth ~= growth then
            row._aishPosIdx = vis
            row._aishPosGrowth = growth
            row:ClearAllPoints()
            local off = (vis - 1) * (isH and (rowW + rg) or (rowH + rg))
            if growth == "RIGHT" then row:SetPoint("LEFT", gfx.container, "LEFT", off, 0)
            elseif growth == "LEFT" then row:SetPoint("RIGHT", gfx.container, "RIGHT", -off, 0)
            elseif growth == "UP" then row:SetPoint("BOTTOM", gfx.container, "BOTTOM", 0, off)
            else row:SetPoint("TOP", gfx.container, "TOP", 0, -off) end
        end

        -- IMPORTANT : row:Show() AVANT les ApplyIconModels/ApplyBarModels.
        -- Sinon les PlayerModels 3D sont Show() alors que leur parent (row)
        -- est encore Hide -> IsVisible=false -> invisibles a l'ecran jusqu'au
        -- prochain scan. Bug observe : "le 3D apparait quand je pose une 2e aura".
        row:Show(); row:SetAlpha(1); ns.CancelDeferredHide(row)

        -- Icon texture
        if a._previewIcon then pcall(ns._SetIconTexture, row.icon, a._previewIcon)
        elseif a.aura then pcall(ns._SetIconTexture, row.icon, a.aura.icon)
        elseif a.spellID then pcall(ns._SetIconTextureFromSpellID, row.icon, a.spellID) end
        row.iconBtn.unit = a.unit or "target"; row.iconBtn.auraInstanceID = a.auraInstanceID
        -- Desaturation (per-render override)
        if cfg.desatOverride ~= nil then row.icon:SetDesaturated(cfg.desatOverride)
        else row.icon:SetDesaturated(a.desat and true or false) end

        -- Cooldown swipe : pattern CDM-only "show but don't know".
        -- SetCooldownFromDurationObject prend le durObj direct (combat-safe Midnight 12.0).
        -- Blizzard gere l'idempotence cote C++ : pas besoin de cache _lastStart/_lastDur.
        if a.durObj then
            pcall(ns._SetCDFromDurObj, row.iconCD, a.durObj)
        end
        row.iconCD:SetDrawSwipe(cfg.swipeEnabled == true); row.iconCD:SetDrawEdge(cfg.swipeEnabled == true)
        -- Native countdown timer
        row.iconCD:SetHideCountdownNumbers(not (cfg.timerIconEnabled))
        if cfg.timerIconEnabled then
            pcall(ns._StyleCountdownFS, row.iconCD,
                cfg.timerFont or ns.Media.font, cfg.timerSize or 11,
                cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
                cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
        end

        row.iconBtn:SetAlpha(cfg.iconAlpha or 1)
            if ns.Anim and ns.Anim.IconPopIn and auras[i] then
                local instID = auras[i].auraInstanceID
                if row._iconPopInstID ~= instID then
                    row._iconPopInstID = instID
                    ns.Anim.IconPopIn(row.iconBtn, cfg, cfg.iconAlpha or 1)
                end
            end
        -- Stacks + charges (helper partagé hoist, évite closures par aura par scan)
        if ns._ApplyStackCharges then ns._ApplyStackCharges(row.iconBtn, a, cfg) end
        ApplyIconModels(row.iconBtn, a)

        -- Glow (with render override)
        local glIdx = a.glowIdx; local glColor = a.glowColor or a.spellColor; local glAlpha = a.glowAlpha
        local glScale = a.glowScale or 1.0
        local hasGlow = a.spellGlow and glIdx and glIdx > 1
        if cfg.glowOverrideIdx and cfg.glowOverrideIdx > 1 then
            glIdx = cfg.glowOverrideIdx; hasGlow = true
            if cfg.glowOverrideR ~= nil then glColor = {cfg.glowOverrideR, cfg.glowOverrideG or 0.5, cfg.glowOverrideB or 0.5} end
            glScale = cfg.glowOverrideScale or glScale; glAlpha = cfg.glowOverrideAlpha or glAlpha
        end
        if cfg.glowEnabled ~= false and hasGlow then
            if ns.ShowGlow then ns.ShowGlow(row.iconBtn, glIdx, glColor, glAlpha, glScale) end
        else if ns.HideGlow then ns.HideGlow(row.iconBtn) end end

        -- Proc start
        curIDs[a.spellID] = true
        if not prevIDs[a.spellID] and a.procGlowIdx and a.procGlowIdx > 1 then
            if ns.PlayProcStart then ns.PlayProcStart(row.iconBtn, a.procGlowIdx, a.glowColor or a.spellColor, a.procGlowScale) end
        end

        -- Bars
        local function SBC(bar) ns.ApplyBarColor(bar, "circlebars", a) end
        if row.barL and row.barR then
            row.barL:Show(); SBC(row.barL); row.wrapL:Show(); row.wrapL:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapL, a)
            row.barR:Show(); SBC(row.barR); row.wrapR:Show(); row.wrapR:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapR, a)
        elseif row.bar then
            row.bar:Show(); SBC(row.bar); row.wrap:Show(); row.wrap:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrap, a)
        end
        -- Pop animation : declenche si auraInstanceID a change. Le sens de
        -- deploiement est determine par l'ancrage des wraps (cf. CreateVanguardRow,
        -- CreateSparteRow, CreateBannerRow) :
        --   - Vanguard : wrap ancre cote icone → deploie depuis l'icone
        --   - Sparte (miroir) : wrapL/wrapR ancres au centre → deploie du centre
        --   - Banner : wrap ancre TOP → deploie verticalement (anim de width neanmoins)
        if a.auraInstanceID and row._popInstID ~= a.auraInstanceID then
            row._popInstID = a.auraInstanceID
            if ns.StartPopAnim then
                if row.barL and row.barR then
                    ns.StartPopAnim(row, {row.wrapL, row.wrapR}, bw, cfg.barAlpha or 1, cfg)
                elseif row.wrap then
                    -- Vanguard : barW. Banner : iw (la barre a la largeur de l'icone).
                    local tw = row._isBanner and iw or bw
                    ns.StartPopAnim(row, {row.wrap}, tw, cfg.barAlpha or 1, cfg)
                end
            end
        end
    end

    -- Defer hide pour les rows inactives (>100ms)
    -- HideGlow ici uniquement pour les rows inactives (voir pre-loop pour detail).
    for _, r in ipairs(rows) do
        if not r._aishActiveNow then
            if ns.HideGlow then pcall(function() ns.HideGlow(r.iconBtn) end) end
            ns.DeferHideRow(r, 0.1)
        end
    end

    gfx.container:Show()
    -- FIX v269 : on appelle TOUJOURS UpdateRenderFade. Voir Debuffs.lua pour le detail
    -- du fix anti-flicker container (combat sur sort CDM secret -> scan vide intermittent
    -- -> container fade out 50ms -> reapparait au scan suivant = clignotement).
    ns.UpdateRenderFade("circlebars")
end

-- Cooldowns.lua : layouts Vanguard + Sparte + Banner (barres latérales)
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
local Cooldowns = {}
ns.RegisterRender("circlebars", Cooldowns)
local CreateFrame, math, pcall = CreateFrame, math, pcall
local DARK, TEXCOORD = 14/255, 0.07

-- Forward declaration : reference par les CreateXxxRow pour _aishHideCleanup
local HideRowModels

local function Dims()
    local c = ns.db and ns.db.circlebars or ns.Defaults.circlebars
    local iw, gp = c.iconW or 28, c.gap or 3
    if c.hideIcon then iw, gp = 0, 0 end  -- collapse la place réservée à l'icône (mode "barres seules")
    return c.barW or 147, c.barH or 4, iw, c.iconH or 19, gp, c.rowGap or 1
end

local function MakeIcon(parent, w, h, cfg)
    local ib = CreateFrame("Button", nil, parent); ib:SetSize(w, h)
    -- Insets négatifs : élargit la zone de survol pour éviter une fine bande morte au tooltip
    ib:SetHitRectInsets(-1, -1, -1, -1)
    ib:SetScript("OnEnter", ns.AuraIconOnEnter)
    ib:SetScript("OnLeave", ns.AuraIconOnLeave)
    local icon = ib:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints()
    -- Crop centré selon le ratio du frame pour ne pas étirer l'icône carrée
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
    cd:EnableMouse(false) -- purement visuel (swipe) : ne doit jamais intercepter le survol de ib
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
    -- Prefixe "atlas:" = atlas Blizzard (ex. honorsystem-bar-spark), pas une texture LSM
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
    -- Désature l'atlas avant teinte, sinon SetVertexColor se multiplie avec sa couleur native
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
    -- Le sens de remplissage suit toujours le cote de l'icone (cfg.iconPos), jamais cfg.reverse
    local iconR = (cfg.iconPos or "RIGHT") == "RIGHT"; local rev = iconR
    local row = CreateFrame("Frame", "AishFVR"..i, cont); row:SetSize(iw + gp + bw, ih)
    local ib, icon, cd = MakeIcon(row, iw, ih, cfg)
    local wr, bar, spark = MakeBarWrap(row, bw, bh, rev, cfg)
    -- Wrap ancre cote icone pour que l'anim pop deploie la barre depuis l'icone vers l'exterieur
    if iconR then
        ib:SetPoint("RIGHT")
        wr:SetPoint("RIGHT", ib, "LEFT", -gp, 0)
    else
        ib:SetPoint("LEFT")
        wr:SetPoint("LEFT", ib, "RIGHT", gp, 0)
    end
    row:Hide(); row.iconBtn=ib; row.icon=icon; row.iconCD=cd; row.bar=bar; row.wrap=wr; row.spark=spark; row._reverse=rev
    -- Cleanup FX3D avant row:Hide() : les PlayerModels ne suivent pas toujours le Hide() du parent
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
    -- Banner reutilise iw comme largeur de barre ; retombe sur bw si icone masquee (iw=0)
    local barW = cfg.hideIcon and bw or iw
    local row = CreateFrame("Frame", "AishFBR"..i, cont); row:SetSize(barW, ih + gp + bh)
    local ib, icon, cd = MakeIcon(row, iw, ih, cfg); ib:SetPoint("TOP")
    local wr, bar, spark = MakeBarWrap(row, barW, bh, cfg.reverse or false, cfg)
    wr:SetPoint("TOP", ib, "BOTTOM", 0, -gp)
    row:Hide(); row.iconBtn=ib; row.icon=icon; row.iconCD=cd; row.bar=bar; row.wrap=wr; row.spark=spark; row._isBanner=true
    row._aishHideCleanup = function() HideRowModels(row) end
    return row
end

-- Scratch tables réutilisées pour ShowXxxModel (évite alloc par aura par scan si fx3d on)
local _iconModelCfg = {}
local _barModelCfg = {}
local _sparkModelCfg = {}
local _fill2DCfg = {}
local _overlayCfg = {}

-- Helpers hoist pour HideRowModels. Ne cache pas les Fill 2D : ApplyBarModels gere leur Show/Hide
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
    -- side_banner reutilise iw comme largeur (cf. CreateBannerRow), retombe sur bw si icone masquee
    elseif layout == "side_banner" then rowW = (cfg.hideIcon and bw or iw); rowH = ih + gp + bh
    else rowW = iw + gp + bw; rowH = ih end
    local growth = cfg.growth or "DOWN"
    if layout == "side_banner" and cfg.bannerGrowth then growth = cfg.bannerGrowth end
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local cont = CreateFrame("Frame", nil, UIParent)
    if isH then cont:SetSize(maxBars * (rowW + rg), rowH)
    else cont:SetSize(rowW, maxBars * (rowH + rg)) end
    cont:SetFrameStrata("MEDIUM"); cont:SetMovable(true); cont:SetClampedToScreen(true); _addon.EnableMouseOnlyOnAlt(cont)
    -- SetPropagateMouseClicks est protege en combat : pcall n'evite pas le taint, on saute l'appel
    if not InCombatLockdown() then
      cont:SetPropagateMouseClicks(true)  -- click-through par défaut (caméra, sélection, etc.)
    end
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
    lbl:SetPoint("BOTTOM", cont, "TOP", 0, 2); lbl:SetText("|cffffcc00"..L["AURASFEAT_ALT_DRAG_HINT"].."|r"); lbl:Hide()
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

-- Rendu reel remplace par le systeme AddAuraGroup natif ; cette fonction sert juste au preview du menu
function Cooldowns:Update(auras)
    local previewActive = ns._previewBars and (ns._previewMode == "all" or ns._previewMode == "circlebars")
    if not previewActive then
        if ns.renderFrames.circlebars and ns.renderFrames.circlebars.container then
            ns.renderFrames.circlebars.container:SetAlpha(0)
            ns.renderFrames.circlebars.container:Hide()
        end
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
    for _, r in ipairs(rows) do
        ns.MarkRowInactive(r)
    end
    local wl = ns.whitelistByDest and ns.whitelistByDest.circlebars
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
            -- Repli synthetique pour le preview (cf. Procs.lua)
            pcall(row.iconCD.SetCooldown, row.iconCD, GetTime(), 12)
        end
        row.iconCD:SetDrawSwipe(cfg.swipeEnabled == true); row.iconCD:SetDrawEdge(cfg.swipeEnabled == true)
        row.iconCD:SetHideCountdownNumbers(not (cfg.timerIconEnabled))
        if cfg.timerIconEnabled then
            pcall(ns._StyleCountdownFS, row.iconCD,
                cfg.timerFont or ns.Media.font, cfg.timerSize or 11,
                cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
                cfg.timerPos or "CENTER", row.iconBtn, cfg.timerPos or "CENTER",
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
        if ns._ApplyStackCharges then ns._ApplyStackCharges(row.iconBtn, a, cfg) end
        ApplyIconModels(row.iconBtn, a)

        local glIdx = a.glowIdx; local glColor = a.glowColor or a.spellColor; local glAlpha = a.glowAlpha
        local glScale = a.glowScale or 1.0
        local hasGlow = a.spellGlow and glIdx and glIdx > 1
        -- Override render DESACTIVE via `false and`, cf. AuraTrackerContainer.lua::ApplySpellGlow.
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

        local function SBC(bar) ns.ApplyBarColor(bar, "circlebars", a) end
        if row.barL and row.barR then
            row.barL:Show(); SBC(row.barL); row.wrapL:Show(); row.wrapL:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapL, a)
            row.barR:Show(); SBC(row.barR); row.wrapR:Show(); row.wrapR:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapR, a)
        elseif row.bar then
            row.bar:Show(); SBC(row.bar); row.wrap:Show(); row.wrap:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrap, a)
        end
        if a.auraInstanceID and row._popInstID ~= a.auraInstanceID then
            row._popInstID = a.auraInstanceID
            if ns.StartPopAnim then
                if row.barL and row.barR then
                    ns.StartPopAnim(row, {row.wrapL, row.wrapR}, bw, cfg.barAlpha or 1, cfg)
                elseif row.wrap then
                    local tw = row._isBanner and iw or bw
                    ns.StartPopAnim(row, {row.wrap}, tw, cfg.barAlpha or 1, cfg)
                end
            end
        end
    end

    for _, r in ipairs(rows) do
        if not r._aishActiveNow then
            if ns.HideGlow then pcall(function() ns.HideGlow(r.iconBtn) end) end
            ns.DeferHideRow(r, 0.1)
        end
    end

    -- SetAlpha(1) explicite : ns.UpdateRenderFade route vers le conteneur natif, pas celui-ci
    gfx.container:Show()
    gfx.container:SetAlpha(1)
end

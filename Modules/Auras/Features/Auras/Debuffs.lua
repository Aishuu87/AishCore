-- AishUIAura/Features/Auras/Debuffs.lua
-- Aegis (miroir) + Berserk (dual) — layouts centraux sous le cercle
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local Debuffs = {}
ns.RegisterRender("iconlist", Debuffs)
local CreateFrame, math, pcall = CreateFrame, math, pcall
local DARK, TEXCOORD = 14/255, 0.07

local function Dims()
    local c = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    return c.barW or 80, c.barH or 2, c.iconW or 25, c.iconH or 25,
           c.gap or 12, c.pairGap or 6, c.rowGap or 3
end

-- Helper top-level : évite closure pcall à chaque survol souris.
local function _SetUnitAuraTooltip(unit, instID, filter)
    GameTooltip:SetUnitAura(unit, instID, filter)
end

local function OnEnter(self)
    if GameTooltip:IsForbidden() or not self:IsVisible() then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 5, -5)
    if self.unit and self.auraInstanceID then
        pcall(_SetUnitAuraTooltip, self.unit, self.auraInstanceID,
            self.unit == "player" and "HELPFUL" or "HARMFUL")
    end
    GameTooltip:Show()
end
local function OnLeave()
    if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local function MakeIcon(parent, w, h)
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local ib = CreateFrame("Button", nil, parent)
    ib:SetSize(w, h)
    ib:SetScript("OnEnter", OnEnter)
    ib:SetScript("OnLeave", OnLeave)

    local icon = ib:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(TEXCOORD, 1 - TEXCOORD, TEXCOORD, 1 - TEXCOORD)

    local cd = CreateFrame("Cooldown", nil, ib, "CooldownFrameTemplate")
    cd:SetAllPoints(ib)
    cd:SetHideCountdownNumbers(true); cd:SetReverse(true)
    cd:SetDrawSwipe(cfg.swipeEnabled == true); cd:SetDrawEdge(cfg.swipeEnabled == true)

    -- Icon border (conditional)
    if (cfg.iconBorder or "square") ~= "none" then
        for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
            local b = parent:CreateTexture(nil, "OVERLAY", nil, 7)
            b:SetColorTexture(DARK, DARK, DARK, 1)
            if side == "TOP" then b:SetHeight(1); b:SetPoint("TOPLEFT", ib, -1, 1); b:SetPoint("TOPRIGHT", ib, 1, 1)
            elseif side == "BOTTOM" then b:SetHeight(1); b:SetPoint("BOTTOMLEFT", ib, -1, -1); b:SetPoint("BOTTOMRIGHT", ib, 1, -1)
            elseif side == "LEFT" then b:SetWidth(1); b:SetPoint("TOPLEFT", ib, -1, 1); b:SetPoint("BOTTOMLEFT", ib, -1, -1)
            else b:SetWidth(1); b:SetPoint("TOPRIGHT", ib, 1, 1); b:SetPoint("BOTTOMRIGHT", ib, 1, -1) end
        end
    end

    -- Stack text (sublevel 7, configurable font) — stacks d'aura (Bone Shield, Frenzy, etc.)
    local st = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(st, cfg.stackFont or ns.Media.font, cfg.stackSize or 10, "OUTLINE")
    st:SetPoint(cfg.stackPos or "BOTTOMRIGHT", ib, cfg.stackPos or "BOTTOMRIGHT", cfg.stackOffX or 0, cfg.stackOffY or 0)
    st:SetJustifyH("RIGHT")
    st:SetTextColor(cfg.stackColorR or 1, cfg.stackColorG or 1, cfg.stackColorB or 1)
    st:Hide()
    ib._stackText = st

    -- Charges text (sublevel 7, configurable font) — charges de sort (Ice Barrier, Blink, etc.)
    -- Position et couleur indépendantes des stacks pour différencier visuellement
    local ct = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(ct, cfg.chargesFont or ns.Media.font, cfg.chargesSize or 10, "OUTLINE")
    ct:SetPoint(cfg.chargesPos or "TOPLEFT", ib, cfg.chargesPos or "TOPLEFT", cfg.chargesOffX or 0, cfg.chargesOffY or 0)
    ct:SetJustifyH("LEFT")
    ct:SetTextColor(cfg.chargesColorR or 0.4, cfg.chargesColorG or 0.7, cfg.chargesColorB or 1.0)
    ct:Hide()
    ib._chargesText = ct

    -- Duration text (timer icône) — centré sur l'icône, piloté par UpdateTimersForRender
    local dt = ib:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(dt, cfg.timerFont or ns.Media.font, cfg.timerSize or 12, "OUTLINE")
    dt:SetPoint("CENTER", ib, "CENTER", cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
    dt:SetJustifyH("CENTER")
    dt:SetTextColor(cfg.timerColorR or 1, cfg.timerColorG or 1, cfg.timerColorB or 1, 0.9)
    dt._lastText = ""
    ib._durText = dt

    return ib, icon, cd
end

local function MakeBarWrap(parent, w, h, rev, texKey)
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local wr = CreateFrame("Frame", nil, parent); wr:SetSize(w, h)
    local tex = ns.ResolveBarTexFromKey(texKey)
    local bar = CreateFrame("StatusBar", nil, wr); bar:SetAllPoints()
    bar:SetStatusBarTexture(tex); bar:SetReverseFill(rev)
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:SetStatusBarColor(ns.barColor[1], ns.barColor[2], ns.barColor[3])
    local bg = wr:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints()
    local bgR = type(cfg.barBgR) == "number" and cfg.barBgR or DARK
    local bgG = type(cfg.barBgG) == "number" and cfg.barBgG or DARK
    local bgB = type(cfg.barBgB) == "number" and cfg.barBgB or DARK
    bg:SetColorTexture(bgR, bgG, bgB, type(cfg.barBgAlpha) == "number" and cfg.barBgAlpha or 1)
    wr._bar = bar

    return wr, bar
end

local function MakeSpark(parent)
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    if not cfg.sparkEnabled then return nil end
    -- "front" = sur la StatusBar (au-dessus du fill), "back" = sur le wrapper
    local sparkParent = (cfg.sparkLayer ~= "back" and parent._bar) or parent
    local s = sparkParent:CreateTexture(nil, "OVERLAY", nil, 7)
    local st = cfg.sparkTexture
    if st and st:find("^atlas:") then s:SetAtlas(st:sub(7))
    else s:SetTexture(st or ns.Media.sparkTex) end
    s:SetSize(cfg.sparkW or 17, cfg.sparkH or 6)
    s:SetBlendMode("ADD")
    local r, g, b = ns.sparkColor[1], ns.sparkColor[2], ns.sparkColor[3]
    local userOverride = cfg.sparkColorR ~= nil
    if userOverride then r, g, b = cfg.sparkColorR, cfg.sparkColorG or 0.5, cfg.sparkColorB or 0.5 end
    -- CRITICAL : quand l'utilisateur force une couleur (via le color picker ou le gradient),
    -- il faut désaturer l'atlas pour que SetVertexColor donne vraiment la couleur demandée.
    -- Sans ça, SetVertexColor(1,0,0) sur le honor spark (jaune-doré natif) donne du rouge
    -- très sombre car les canaux sont multipliés avec la teinte native de l'atlas.
    -- On désature seulement si override actif pour garder le look natif par défaut.
    if userOverride or cfg.sparkGradient then
        pcall(function() s:SetDesaturated(true) end)
    end
    -- Gradient on spark
    if cfg.sparkGradient then
        s:SetVertexColor(1, 1, 1, cfg.sparkAlpha or 0.9)
        pcall(function()
            if s.SetGradient then
                local gr = (cfg.sparkGradR2 or r*0.2)
                local gg = (cfg.sparkGradG2 or g*0.2)
                local gb = (cfg.sparkGradB2 or b*0.2)
                s:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(gr, gg, gb, 1))
            end
        end)
    else
        s:SetVertexColor(r, g, b, cfg.sparkAlpha or 0.9)
    end
    -- Memorise la ref du spark 2D sur le barWrap pour que le spark FX3D
    -- (ShowSparkModel dans SpellEffects.lua) puisse s'ancrer dessous.
    parent._spark2D = s
    return s
end

------------------------------------------------------------------------
-- GLOW (design pattern)
------------------------------------------------------------------------
local function EnsureGlow(ib)
    if ib._glowSetup then return end
    ib._glowSetup = true
    local gc = CreateFrame("Frame", nil, ib)
    gc:SetFrameLevel(ib:GetFrameLevel() + 2)
    ib._glowContainer = gc
    local pulse = gc:CreateTexture(nil, "OVERLAY", nil, 1)
    pulse:SetBlendMode("ADD"); pulse:SetAlpha(0); pulse:Hide()
    ib._glowPulse = pulse
    local ag = pulse:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha"); anim:SetSmoothing("IN_OUT")
    ib._glowPulseAG = ag; ib._glowPulseAnim = anim
    local flip = gc:CreateTexture(nil, "OVERLAY", nil, 2)
    flip:SetAlpha(0); flip:Hide(); flip:SetBlendMode("ADD")
    ib._glowFlip = flip
    local fag = flip:CreateAnimationGroup(); fag:SetLooping("REPEAT")
    local fa = fag:CreateAnimation("FlipBook"); fa:SetOrder(1)
    ib._glowFlipAG = fag; ib._glowFlipAnim = fa
end

local function ShowGlow(ib, idx, color, alpha, scale)
    if not ib then return end
    local def = ns.GLOW_DEFS[idx or 1]
    if not def or def.name == "Aucun" then return end
    color = color or ns.barColor; alpha = alpha or 0.7; scale = scale or 1.0
    EnsureGlow(ib)

    -- Guard : ne pas redémarrer l'animation si le même type de glow tourne déjà.
    -- Sans ce guard, ShowGlow appelé à chaque scan (plusieurs fois/seconde) redémarre
    -- l'AnimationGroup depuis le début à chaque fois, causant un reset visible en boucle.
    if ib._glowActiveIdx == idx then
        if def.useAlphaPulse then
            if ib._glowPulseAG:IsPlaying() then return end
        else
            if ib._glowFlipAG:IsPlaying() then return end
        end
    end
    ib._glowActiveIdx = idx

    local iw, ih = ib:GetSize()
    -- Marges aware de l'aspect : proportionnelles à chaque dimension
    local mx = math.max(4, math.floor(iw * 0.3 * scale))
    local my = math.max(4, math.floor(ih * 0.3 * scale))
    local gc = ib._glowContainer
    gc:ClearAllPoints()
    gc:SetPoint("TOPLEFT", ib, -mx, my)
    gc:SetPoint("BOTTOMRIGHT", ib, mx, -my)
    if def.useAlphaPulse then
        ib._glowFlipAG:Stop(); ib._glowFlip:SetAlpha(0); ib._glowFlip:Hide()
        local p = ib._glowPulse
        if def.atlas then p:SetTexture(nil); p:SetAtlas(def.atlas); p:SetTexCoord(0,1,0,1)
        else p:SetTexture(def.texture)
            if def.texCoord then p:SetTexCoord(unpack(def.texCoord)) else p:SetTexCoord(0,1,0,1) end
        end
        p:SetBlendMode(def.blendMode or "ADD")
        p:SetVertexColor(color[1], color[2], color[3], alpha)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", ib, -mx, my)
        p:SetPoint("BOTTOMRIGHT", ib, mx, -my)
        ib._glowPulseAnim:SetFromAlpha(def.fromAlpha or 0.3)
        ib._glowPulseAnim:SetToAlpha(def.toAlpha or 0.7)
        ib._glowPulseAnim:SetDuration(def.duration or 0.8)
        p:Show(); p:SetAlpha(def.fromAlpha or 0.3); ib._glowPulseAG:Play()
    else
        ib._glowPulseAG:Stop(); ib._glowPulse:SetAlpha(0); ib._glowPulse:Hide()
        local f = ib._glowFlip
        if def.atlas then f:SetTexture(nil); f:SetAtlas(def.atlas)
        elseif def.texture then f:SetTexture(def.texture) end
        local sc = (def.scale or 1) * scale
        local sw = iw * sc + mx * 2
        local sh = ih * sc + my * 2
        f:ClearAllPoints(); f:SetSize(sw, sh); f:SetPoint("CENTER", ib, 0, 0)
        f:SetVertexColor(color[1], color[2], color[3], alpha); f:SetBlendMode("ADD")
        local fa = ib._glowFlipAnim
        fa:SetFlipBookRows(def.rows or 6); fa:SetFlipBookColumns(def.columns or 5)
        fa:SetFlipBookFrames(def.frames or 30); fa:SetDuration(def.duration or 1.0)
        pcall(function() fa:SetFlipBookFrameWidth(def.frameW or 0) end)
        pcall(function() fa:SetFlipBookFrameHeight(def.frameH or 0) end)
        f:Show(); f:SetAlpha(alpha); ib._glowFlipAG:Play()
    end
end

local function HideGlow(ib)
    if not ib or not ib._glowSetup then return end
    ib._glowActiveIdx = nil
    ib._glowPulseAG:Stop(); ib._glowPulse:SetAlpha(0); ib._glowPulse:Hide()
    ib._glowFlipAG:Stop(); ib._glowFlip:SetAlpha(0); ib._glowFlip:Hide()
end

-- Expose for settings panel preview
ns.ShowGlow = ShowGlow; ns.HideGlow = HideGlow

------------------------------------------------------------------------
-- APPLY AURA  (FUSION: design + motor durObj swipe)
------------------------------------------------------------------------
-- Helpers top-level : évitent closures pcall dans ApplyAura (appelé par aura par scan).
-- Exposés sur ns pour partage entre les 3 renders (Debuffs, Cooldowns, Procs).
-- Fallback icon (question mark) si la texture demandée est nil/invalide :
-- sinon SetTexture(nil) laisse la TEXTURE PRÉCÉDENTE de l'icône, ce qui cause
-- des "icônes fantômes" quand une row est réutilisée pour une aura dont le
-- spellID est stale (typique : données obsolètes dans la SavedVariable).
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local function _SetIconTexture(icon, tex) icon:SetTexture(tex or FALLBACK_ICON) end
local function _SetIconTextureFromSpellID(icon, spellID)
    local tex = spellID and C_Spell.GetSpellTexture(spellID) or nil
    icon:SetTexture(tex or FALLBACK_ICON)
end
local function _SetCDFromDurObj(cd, durObj) cd:SetCooldownFromDurationObject(durObj) end
ns._SetIconTexture = _SetIconTexture
ns._SetIconTextureFromSpellID = _SetIconTextureFromSpellID
ns._SetCDFromDurObj = _SetCDFromDurObj

-- Cherche et cache le FontString du cooldown countdown natif Blizzard.
-- Blizzard ne l'expose pas directement, on doit le retrouver par GetRegions().
-- On cache la référence sur le cd frame lui-même (cd._aishCountdownFS) pour
-- éviter de rescanner à chaque ApplyAura.
local function GetCooldownCountdownFS(cd)
    if cd._aishCountdownFS then return cd._aishCountdownFS end
    for _, region in pairs({cd:GetRegions()}) do
        if region.GetText and region:GetObjectType() == "FontString" then
            cd._aishCountdownFS = region
            return region
        end
    end
end

local function _StyleCountdownFS(cd, font, size, r, g, b, offX, offY)
    local region = GetCooldownCountdownFS(cd)
    if not region then return end
    ns.ApplyFont(region, font, size, "OUTLINE")
    if r then region:SetTextColor(r, g or 1, b or 1) end
    region:ClearAllPoints()
    region:SetPoint("CENTER", cd, "CENTER", offX or 0, offY or 0)
end
ns._StyleCountdownFS = _StyleCountdownFS

-- Helpers hoist pour stacks/charges : évitent closure pcall par aura par scan.
local function _SetStackText(fs, unit, instID)
    fs:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, instID, 2, 999))
end
local function _ReadSpellCharges(spellID)
    return C_Spell.GetSpellCharges(spellID)
end

local function ApplyStackCharges(ib, aura, cfg)
    if ib._stackText then
        if aura and aura._isPreview and aura.stacks and aura.stacks > 0 then
            -- Entree preview : l'API Blizzard ne reconnait pas l'instID factice,
            -- on affiche directement la valeur fictive stockee dans entry.stacks.
            ib._stackText:SetText(aura.stacks)
            ib._stackText:Show()
        elseif cfg.stackEnabled ~= false and ib.unit and ib.auraInstanceID
           and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
            pcall(_SetStackText, ib._stackText, ib.unit, ib.auraInstanceID)
            ib._stackText:Show()
        else
            ib._stackText:Hide()
        end
    end
    if ib._chargesText then
        if cfg.chargesEnabled ~= false and aura.spellID and C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(_ReadSpellCharges, aura.spellID)
            if ok and info and info.maxCharges and info.maxCharges > 1 then
                ib._chargesText:SetText(info.currentCharges)
                ib._chargesText:Show()
            else
                ib._chargesText:Hide()
            end
        else
            ib._chargesText:Hide()
        end
    end
end
ns._ApplyStackCharges = ApplyStackCharges

local function ApplyAura(ib, icon, cd, aura, glowOn)
    if aura._previewIcon then pcall(_SetIconTexture, icon, aura._previewIcon)
    elseif aura.aura then pcall(_SetIconTexture, icon, aura.aura.icon)
    elseif aura.spellID then pcall(_SetIconTextureFromSpellID, icon, aura.spellID)
    end
    ib.unit = aura.unit or "target"
    ib.auraInstanceID = aura.auraInstanceID
    cd:SetReverse(true)
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    -- Desaturation (per-render override)
    if cfg.desatOverride ~= nil then icon:SetDesaturated(cfg.desatOverride)
    else icon:SetDesaturated(aura.desat and true or false) end

    -- Cooldown swipe : pattern CDM-only "show but don't know".
    -- SetCooldownFromDurationObject prend le durObj direct (combat-safe Midnight 12.0).
    -- Blizzard gere l'idempotence cote C++ : pas besoin de cache _lastStart/_lastDur.
    if aura.durObj then
        pcall(_SetCDFromDurObj, cd, aura.durObj)
    end
    cd:SetDrawSwipe(cfg.swipeEnabled == true); cd:SetDrawEdge(cfg.swipeEnabled == true)
    -- Native countdown timer
    cd:SetHideCountdownNumbers(not (cfg.timerIconEnabled))
    if cfg.timerIconEnabled then
        pcall(_StyleCountdownFS, cd,
            cfg.timerFont or ns.Media.font, cfg.timerSize or 12,
            cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
            cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
    end

    -- Glow (with render override support)
    local glIdx = aura.glowIdx
    local glColor = aura.glowColor or aura.spellColor
    local glAlpha = aura.glowAlpha
    local glScale = aura.glowScale or 1.0
    local hasGlow = aura.spellGlow and glIdx and glIdx > 1
    if cfg.glowOverrideIdx and cfg.glowOverrideIdx > 1 then
        glIdx = cfg.glowOverrideIdx; hasGlow = true
        if cfg.glowOverrideR then glColor = {cfg.glowOverrideR, cfg.glowOverrideG or 0.5, cfg.glowOverrideB or 0.5} end
        glScale = cfg.glowOverrideScale or glScale; glAlpha = cfg.glowOverrideAlpha or glAlpha
    end
    if glowOn and hasGlow then
        ShowGlow(ib, glIdx, glColor, glAlpha, glScale)
    else HideGlow(ib) end

    -- Stacks + charges (helper partagé, évite closures pcall par aura par scan)
    if ns._ApplyStackCharges then ns._ApplyStackCharges(ib, aura, cfg) end
end

local function SetBarColor(bar, aura)
    ns.ApplyBarColor(bar, "iconlist", aura)
end

------------------------------------------------------------------------
-- 3D MODEL APPLY (Step 4)
------------------------------------------------------------------------
-- Scratch tables réutilisées pour ShowIconModel/ShowBarModel/ShowSparkModel.
-- Évite l'allocation d'une nouvelle table par aura par scan quand fx3d activé.
local _iconModelCfg = {}
local _barModelCfg = {}
local _sparkModelCfg = {}
local _fill2DCfg = {}
local _overlayCfg = {}

local function ApplyIconModels(ib, aura)
    if not ns.db or not ns.EffectsActive() or not ns.SpellFX then return end
    -- Icon model
    if aura.iconModelID and aura.iconModelID ~= 0 then
        if not ib._fx3dIcon then ib._fx3dIcon = ns.SpellFX:CreateIconModel(ib) end
        if ib._fx3dIcon then
            _iconModelCfg.modelID = aura.iconModelID
            _iconModelCfg.alpha = aura.iconModelA
            _iconModelCfg.rotation = aura.iconModelRot
            _iconModelCfg.x = aura.iconModelX
            _iconModelCfg.y = aura.iconModelY
            _iconModelCfg.z = aura.iconModelZ
            _iconModelCfg.scale = aura.iconModelS
            _iconModelCfg.layer = aura.iconModelL
            _iconModelCfg.fxW = aura.iconFxW
            _iconModelCfg.fxH = aura.iconFxH
            _iconModelCfg.posX = aura.iconPosX
            _iconModelCfg.posY = aura.iconPosY
            ns.SpellFX:ShowIconModel(ib._fx3dIcon, _iconModelCfg)
        end
    elseif ib._fx3dIcon then ns.SpellFX:HideIconModel(ib._fx3dIcon) end
end

local function ApplyBarModels(barWrap, aura)
    if not barWrap or not ns.db or not ns.EffectsActive() or not ns.SpellFX then return end
    -- Cache : si la meme aura est re-appliquee sur ce wrap, pas besoin de
    -- redo Show. Evite le cycle "Show -> rien faire -> Show -> ..." a chaque
    -- scan qui spammait avant. Le spellID est utilise comme cle stable.
    local spellID = aura.spellID
    local prevID = barWrap._fxAuraID
    -- Mode FOND (front) : PlayerModel 3D plein largeur derriere la barre
    -- Mode REMPLISSAGE (mid) : Texture 2D qui se tronque avec la barre (pattern WA)
    local mode = aura.barModelMode or "front"
    if (mode == "front" or mode == "back") and aura.barModelID and aura.barModelID ~= 0 then
        -- Cache eventuel Fill 2D si on switch vers 3D
        if barWrap._fx2dFill then ns.SpellFX:HideFill2D(barWrap._fx2dFill) end
        if not barWrap._fx3dBar then barWrap._fx3dBar = ns.SpellFX:CreateBarModel(barWrap) end
        if barWrap._fx3dBar then
            _barModelCfg.modelID = aura.barModelID
            _barModelCfg.alpha = aura.barModelA
            _barModelCfg.rotation = aura.barModelRot
            _barModelCfg.x = aura.barModelX
            _barModelCfg.y = aura.barModelY
            _barModelCfg.z = aura.barModelZ
            _barModelCfg.scale = aura.barModelS
            _barModelCfg.mode = mode  -- "front" ou "back"
            _barModelCfg.layer = aura.barModelL
            _barModelCfg.fxW = aura.barFxW
            _barModelCfg.fxH = aura.barFxH
            _barModelCfg.durObj = aura.durObj
            _barModelCfg.bar = barWrap._bar  -- pour mode back : ancrer le clip sur bar:GetStatusBarTexture()
            _barModelCfg.auraInstanceID = aura.auraInstanceID  -- pour LearnedDurations (mode back)
            _barModelCfg.barAlphaWith3D = (ns.db and ns.db.iconlist and ns.db.iconlist.barAlphaWith3D) or 1.0
            ns.SpellFX:ShowBarModel(barWrap._fx3dBar, _barModelCfg)
        end
    elseif mode == "mid" and aura.barFillTex and aura.barFillTex ~= "" then
        -- Cache eventuel 3D si on switch vers 2D
        if barWrap._fx3dBar then ns.SpellFX:HideBarModel(barWrap._fx3dBar) end
        if not barWrap._fx2dFill then barWrap._fx2dFill = ns.SpellFX:CreateFill2D(barWrap) end
        if barWrap._fx2dFill then
            _fill2DCfg.texturePath = aura.barFillTex
            _fill2DCfg.alpha = aura.barFillAlpha or 0.7
            _fill2DCfg.tintR = aura.barFillTintR or 1
            _fill2DCfg.tintG = aura.barFillTintG or 1
            _fill2DCfg.tintB = aura.barFillTintB or 1
            _fill2DCfg.scrollSpeed = aura.barFillScroll or 0
            _fill2DCfg.layer = aura.barFillLayer or "front"
            _fill2DCfg.bar = barWrap._bar  -- la StatusBar pour ancrer la texture sur son fill
            ns.SpellFX:ShowFill2D(barWrap._fx2dFill, _fill2DCfg)
        end
    elseif prevID ~= spellID then
        -- L'aura courante n'a NI 3D Fond NI Fill 2D configure, ET ce n'est pas
        -- la meme aura que la precedente sur ce wrap (changement d'aura via
        -- recyclage de row). On cache les FX heritage de l'aura precedente
        -- pour ne pas afficher de texture / 3D fantome.
        if barWrap._fx3dBar then ns.SpellFX:HideBarModel(barWrap._fx3dBar) end
        if barWrap._fx2dFill then ns.SpellFX:HideFill2D(barWrap._fx2dFill) end
    end
    barWrap._fxAuraID = spellID  -- track pour le prochain scan
    -- Spark model
    if aura.sparkModelID and aura.sparkModelID ~= 0 then
        if not barWrap._fx3dSpark then barWrap._fx3dSpark = ns.SpellFX:CreateSparkModel(barWrap) end
        if barWrap._fx3dSpark then
            _sparkModelCfg.modelID = aura.sparkModelID
            _sparkModelCfg.alpha = aura.sparkModelA
            _sparkModelCfg.rotation = aura.sparkModelRot
            _sparkModelCfg.x = aura.sparkModelX
            _sparkModelCfg.y = aura.sparkModelY
            _sparkModelCfg.z = aura.sparkModelZ
            _sparkModelCfg.scale = aura.sparkModelS
            _sparkModelCfg.layer = aura.sparkModelL
            ns.SpellFX:ShowSparkModel(barWrap._fx3dSpark, _sparkModelCfg)
        end
    elseif barWrap._fx3dSpark then ns.SpellFX:HideSparkModel(barWrap._fx3dSpark) end
    -- Animated texture overlay
    if aura.barOverlayTex and aura.barOverlayTex ~= "" then
        if not barWrap._barOverlay then barWrap._barOverlay = ns.SpellFX:CreateBarOverlay(barWrap) end
        if barWrap._barOverlay then
            _overlayCfg.texture = aura.barOverlayTex
            _overlayCfg.alpha = aura.barOverlayA or 0.3
            _overlayCfg.speed = aura.barOverlaySpeed or 0.5
            _overlayCfg.color = aura.spellColor
            ns.SpellFX:ShowBarOverlay(barWrap._barOverlay, _overlayCfg)
        end
    elseif barWrap._barOverlay then ns.SpellFX:HideBarOverlay(barWrap._barOverlay) end
end

------------------------------------------------------------------------
-- ROW CREATORS
------------------------------------------------------------------------
local function CreateAegisRow(cont, i)
    local bw, bh, iw, ih, gp = Dims()
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local row = CreateFrame("Frame", "AishDebuffsAR" .. i, cont)
    row:SetSize(bw * 2 + iw + gp * 2, ih)
    local ib, icon, cd = MakeIcon(row, iw, ih)
    ib:SetPoint("CENTER")
    local wL, bL = MakeBarWrap(row, bw, bh, true, cfg.texture)
    wL:SetPoint("RIGHT", ib, "LEFT", -gp, 0)
    local sL = MakeSpark(wL)
    local wR, bR = MakeBarWrap(row, bw, bh, false, cfg.texture)
    wR:SetPoint("LEFT", ib, "RIGHT", gp, 0)
    local sR = MakeSpark(wR)
    row:Hide()
    row.iconBtn = ib; row.icon = icon; row.iconCD = cd
    row.barL = bL; row.barR = bR; row.wrapL = wL; row.wrapR = wR
    row.sparkL = sL; row.sparkR = sR
    -- Callback de cleanup FX3D appele par DeferHideRow juste avant row:Hide().
    -- Cache les PlayerModels qui ne suivent pas toujours Hide() de leur parent
    -- (quirk Blizzard). Necessaire quand un sort est decoche de la liste de
    -- tracking pendant que l'aura est encore active.
    row._aishHideCleanup = function()
        if not ns.SpellFX then return end
        if row.iconBtn and row.iconBtn._fx3dIcon then ns.SpellFX:HideIconModel(row.iconBtn._fx3dIcon) end
        if wL then
            wL._fxAuraID = nil
            if wL._fx3dBar then ns.SpellFX:HideBarModel(wL._fx3dBar) end
            if wL._fx3dSpark then ns.SpellFX:HideSparkModel(wL._fx3dSpark) end
            if wL._fx2dFill then ns.SpellFX:HideFill2D(wL._fx2dFill) end
        end
        if wR then
            wR._fxAuraID = nil
            if wR._fx3dBar then ns.SpellFX:HideBarModel(wR._fx3dBar) end
            if wR._fx3dSpark then ns.SpellFX:HideSparkModel(wR._fx3dSpark) end
            if wR._fx2dFill then ns.SpellFX:HideFill2D(wR._fx2dFill) end
        end
    end
    return row
end

local function CreateBerserkRow(cont, i)
    local bw, bh, iw, ih, gp, pg = Dims()
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local row = CreateFrame("Frame", "AishDebuffsBR" .. i, cont)
    row:SetSize(bw + gp + iw + pg + iw + gp + bw, ih)
    local hL = CreateFrame("Frame", nil, row)
    hL:SetSize(bw + gp + iw, ih)
    hL:SetPoint("RIGHT", row, "CENTER", -(pg / 2), 0)
    local ibL, iL, cL = MakeIcon(hL, iw, ih); ibL:SetPoint("RIGHT")
    local wBL, bL = MakeBarWrap(hL, bw, bh, true, cfg.texture)
    wBL:SetPoint("RIGHT", ibL, "LEFT", -gp, 0)
    local sL = MakeSpark(wBL)
    local hR = CreateFrame("Frame", nil, row)
    hR:SetSize(iw + gp + bw, ih)
    hR:SetPoint("LEFT", row, "CENTER", pg / 2, 0)
    local ibR, iR, cR = MakeIcon(hR, iw, ih); ibR:SetPoint("LEFT")
    local wBR, bR = MakeBarWrap(hR, bw, bh, false, cfg.texture)
    wBR:SetPoint("LEFT", ibR, "RIGHT", gp, 0)
    local sR = MakeSpark(wBR)
    row:Hide()
    row.halfL = hL; row.halfR = hR
    row.iconBtnL = ibL; row.iconL = iL; row.iconCDL = cL
    row.iconBtnR = ibR; row.iconR = iR; row.iconCDR = cR
    row.barL = bL; row.barR = bR
    row.wrapBarL = wBL; row.wrapBarR = wBR
    row.sparkL = sL; row.sparkR = sR
    row._isDual = true
    -- Callback de cleanup FX3D appele par DeferHideRow juste avant row:Hide().
    -- Voir commentaire du callback dans CreateRow normal.
    row._aishHideCleanup = function()
        if not ns.SpellFX then return end
        if ibL and ibL._fx3dIcon then ns.SpellFX:HideIconModel(ibL._fx3dIcon) end
        if ibR and ibR._fx3dIcon then ns.SpellFX:HideIconModel(ibR._fx3dIcon) end
        if wBL then
            wBL._fxAuraID = nil
            if wBL._fx3dBar then ns.SpellFX:HideBarModel(wBL._fx3dBar) end
            if wBL._fx3dSpark then ns.SpellFX:HideSparkModel(wBL._fx3dSpark) end
            if wBL._fx2dFill then ns.SpellFX:HideFill2D(wBL._fx2dFill) end
        end
        if wBR then
            wBR._fxAuraID = nil
            if wBR._fx3dBar then ns.SpellFX:HideBarModel(wBR._fx3dBar) end
            if wBR._fx3dSpark then ns.SpellFX:HideSparkModel(wBR._fx3dSpark) end
            if wBR._fx2dFill then ns.SpellFX:HideFill2D(wBR._fx2dFill) end
        end
    end
    return row
end

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------
function Debuffs:Init()
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    if not ns.db or (not ns.db.iconlistEnabled) then return end
    if ns.renderFrames.iconlist and ns.renderFrames.iconlist.container then
        local old = ns.renderFrames.iconlist
        if old.rows then for _, r in ipairs(old.rows) do r:Hide(); r:SetParent(nil) end end
        old.container:Hide(); old.container:SetParent(nil)
    end
    local layout = cfg.layout or "center_mirror"
    local isDual = (layout == "center_dual")
    local maxBars = cfg.maxBars or 8
    local numRows = isDual and math.ceil(maxBars / 2) or maxBars
    local bw, _, iw, ih, gp, pg, rg = Dims()
    local rowW = isDual and (bw + gp + iw + pg + iw + gp + bw) or (bw * 2 + iw + gp * 2)
    local growth = cfg.growth or "DOWN"
    local isH = (growth == "LEFT" or growth == "RIGHT")

    local cont = CreateFrame("Frame", "AishDebuffsCont", UIParent)
    if isH then cont:SetSize(numRows * (rowW + rg), ih)
    else cont:SetSize(rowW, numRows * (ih + rg)) end
    cont:SetFrameStrata("BACKGROUND")
    cont:SetMovable(true); cont:SetClampedToScreen(true); cont:EnableMouse(true)
    cont:SetPropagateMouseClicks(true)  -- click-through par défaut (caméra, sélection, etc.)

    local rows = {}
    for i = 1, numRows do
        rows[i] = isDual and CreateBerserkRow(cont, i) or CreateAegisRow(cont, i)
    end

    cont:ClearAllPoints()
    local x, y = cfg.x or 0, cfg.y or -290
    if growth == "UP" then cont:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    elseif growth == "LEFT" then cont:SetPoint("RIGHT", UIParent, "CENTER", x, y)
    elseif growth == "RIGHT" then cont:SetPoint("LEFT", UIParent, "CENTER", x, y)
    else cont:SetPoint("TOP", UIParent, "CENTER", x, y) end

    local lbl = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("BOTTOM", cont, "TOP", 0, 2)
    lbl:SetText("|cffffcc00Alt+Drag|r"); lbl:Hide()
    cont:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s:SetPropagateMouseClicks(false)  -- bloquer la propagation pendant le drag
            s:StartMoving(); lbl:Show()
        end
    end)
    cont:SetScript("OnMouseUp", function(s)
        s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)  -- rétablir le click-through
        lbl:Hide()
        local sx, sy = GetScreenWidth() / 2, GetScreenHeight() / 2
        local sc = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local cx, cy = s:GetCenter()
        if cx and cy and ns.db and ns.db.iconlist then
            local w, h = s:GetSize()
            local gr = (ns.renderFrames.iconlist and ns.renderFrames.iconlist.growth) or "DOWN"
            local saveX = cx * sc - sx
            local saveY = cy * sc - sy
            -- Aligner l'offset sauvé sur l'ancre utilisée au restore (SetPoint TOP/BOTTOM/LEFT/RIGHT)
            if gr == "DOWN" then saveY = saveY + h * sc / 2
            elseif gr == "UP" then saveY = saveY - h * sc / 2
            elseif gr == "LEFT" then saveX = saveX + w * sc / 2
            elseif gr == "RIGHT" then saveX = saveX - w * sc / 2
            end
            ns.db.iconlist.x = saveX; ns.db.iconlist.y = saveY
        end
    end)
    cont:SetScript("OnHide", function(s)
        s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        lbl:Hide()
    end)
    cont:Show()
    ns.renderFrames.iconlist = { container = cont, rows = rows, layout = layout, growth = growth }
    ns.UpdateRenderFade("iconlist")
end

------------------------------------------------------------------------
-- UPDATE
------------------------------------------------------------------------
function Debuffs:Update(auras)
    -- TRACE : entree Update + nb auras + premiers spellIDs
    -- INIT FLAG : tant que l'addon n'a pas fini son init, on cache
    -- le container et on early-return. Évite les flashes pendant le /reload.
    if not ns._initComplete then
        if ns.renderFrames.iconlist and ns.renderFrames.iconlist.container then
            ns.renderFrames.iconlist.container:SetAlpha(0)
        end
        return
    end
    if ns.db and (not ns.db.iconlistEnabled or ns.db.useNativeCDM) then
        if ns.renderFrames.iconlist and ns.renderFrames.iconlist.container then
            ns.renderFrames.iconlist.container:SetAlpha(0)
        end
        return
    end
    local gfx = ns.renderFrames.iconlist; if not gfx then return end
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local rows = gfx.rows
    local isDual = (gfx.layout == "center_dual")
    local glowOn = cfg.glowEnabled ~= false
    local growth = gfx.growth or "DOWN"
    local isH = (growth == "LEFT" or growth == "RIGHT")
    local bw, _, iw, ih, gp, pg, rg = Dims()
    local rowW = isDual and (bw + gp + iw + pg + iw + gp + bw) or (bw * 2 + iw + gp * 2)

    -- Pattern anti-flicker : on NE cache PAS immédiatement les rows.
    -- On les marque inactive et on programme un Hide différé de 100ms. Les rows qui
    -- sont re-activées plus bas dans la boucle appelleront CancelDeferredHide et
    -- seront show()+SetAlpha(1) direct. Les rows qui restent inactives pendant 100ms+
    -- seront vraiment cachées (ce qui trigge OnHide + reset timerMode correctement).
    -- Sans ce defer, un refresh rapide de Rip/Rake (30-50ms entre le remove et le
    -- re-add) causait un flash visible.
    --
    -- ApplyBarModels gere les transitions FX 3D via le cache _fxAuraID :
    --   - meme aura -> rien faire (cache hit)
    --   - row recyclee pour autre aura -> hide + show propres
    --   - row vraiment inactive -> row:Hide() cache automatiquement les enfants 3D
    for _, r in ipairs(rows) do
        ns.MarkRowInactive(r)
    end

    local wl = ns.whitelistByDest and ns.whitelistByDest.iconlist
    if not wl then return end

    -- Double-buffer pour éviter l'allocation de curIDs à chaque scan :
    -- on alterne entre 2 tables persistantes. La "curIDs" du scan précédent
    -- devient "prevIDs" du scan suivant, et vice versa.
    if not ns._debuffsIDsA then ns._debuffsIDsA = {}; ns._debuffsIDsB = {}; ns._debuffsIDsUseA = true end
    local prevIDs = ns._debuffsIDsUseA and ns._debuffsIDsB or ns._debuffsIDsA
    local curIDs  = ns._debuffsIDsUseA and ns._debuffsIDsA or ns._debuffsIDsB
    wipe(curIDs)
    ns._debuffsIDsUseA = not ns._debuffsIDsUseA
    -- Set des instIDs vues pendant ce scan (pour LearnedDurations)
    -- Permet de detecter quelles auras ont DISPARU au prochain scan.
    if not ns._dbgSeenInstIDsA then ns._dbgSeenInstIDsA = {}; ns._dbgSeenInstIDsB = {}; ns._dbgSeenUseA = true end
    local seenInstIDs = ns._dbgSeenUseA and ns._dbgSeenInstIDsA or ns._dbgSeenInstIDsB
    local prevSeenInstIDs = ns._dbgSeenUseA and ns._dbgSeenInstIDsB or ns._dbgSeenInstIDsA
    wipe(seenInstIDs)
    ns._dbgSeenUseA = not ns._dbgSeenUseA
    ns._dbgPrevSeenInstIDs = prevSeenInstIDs  -- expose pour MaybePop (detection refresh)

    local function ok(a) return a and a.spellID and (a.spellID > 900000 or (wl and wl[a.spellID])) end

    local function ProcCheck(a, anchor)
        if a and a.spellID then
            curIDs[a.spellID] = true
            if not prevIDs[a.spellID] and a.procGlowIdx and a.procGlowIdx > 1 then
                if ns.PlayProcStart then ns.PlayProcStart(anchor, a.procGlowIdx, a.glowColor or a.spellColor, a.procGlowScale) end
            end
        end
    end

    -- Helper local : declenche l'animation d'apparition (pop) si l'auraInstanceID
    -- a change sur la row. Utilise auraInstanceID (et non IsShown) car le pattern
    -- DeferHideRow rend IsShown peu fiable. On track 1 seul instID par row : pour
    -- les rows dual, on prend l'aura du side gauche (compromis simple, l'animation
    -- se declenche sur les 2 wraps en meme temps, ce qui est correct dans 95% des cas).
    -- En plus de l'anim pop, on notifie LearnedDurations pour le pattern de
    -- durees apprises (combat-safe Midnight 12.0).
    local function MaybePop(row, aura, wraps, targetW)
        if not aura or not aura.auraInstanceID then return end
        local instID = aura.auraInstanceID
        seenInstIDs[instID] = true  -- pour cleanup LearnedDurations
        -- Notifie LearnedDurations : detection refresh via _seenInstIDs
        if ns.LearnedDurations and ns.LearnedDurations.OnAuraAppeared then
            local isRefresh = ns._dbgPrevSeenInstIDs and ns._dbgPrevSeenInstIDs[instID] == true
            -- Priorite : cdmData (clean) -> SafeSpellID -> aura.spellID brut (peut etre secret)
            -- Idem pour le nom : cdmData a le nom propre, sinon on tente aura.name
            local cleanSpellID, cleanName
            if ns.cdmData and ns.cdmData.target then
                local entry = ns.cdmData.target[instID]
                if entry and entry.spellId then
                    cleanSpellID = entry.spellId
                    cleanName = entry.name
                end
            end
            -- Fallback hors-CDM : aura.spellID via SafeSpellID (gere les secrets)
            if not cleanSpellID and ns.SafeSpellID then
                cleanSpellID = ns.SafeSpellID(aura)
            end
            -- Fallback nom : aura.name peut etre secret en combat, on protege
            if not cleanName and aura.name then
                pcall(function()
                    if not (issecretvalue and issecretvalue(aura.name)) then
                        cleanName = aura.name
                    end
                end)
            end
            -- Dernier fallback : tostring du spellID
            if not cleanName and cleanSpellID then
                cleanName = tostring(cleanSpellID)
            end
            if cleanSpellID then
                ns.LearnedDurations.OnAuraAppeared(instID, cleanSpellID, cleanName, isRefresh)
            end
        end
        if row._popInstID == instID then return end
        row._popInstID = instID
        if ns.StartPopAnim then
            ns.StartPopAnim(row, wraps, targetW, cfg.barAlpha or 1, cfg)
        end
    end

    local function Pos(row, idx)
        -- Skip le SetPoint si la row est déjà à la bonne position.
        -- SetPoint déclenche un reflow Blizzard qui peut causer une frame de lag
        -- sur les rows voisines. En multi-rows, on économise N-1 reflows par scan.
        if row._aishPosIdx == idx and row._aishPosGrowth == growth then return end
        row._aishPosIdx = idx
        row._aishPosGrowth = growth
        row:ClearAllPoints()
        local off = (idx - 1) * (isH and (rowW + rg) or (ih + rg))
        if growth == "RIGHT" then row:SetPoint("LEFT", gfx.container, "LEFT", off, 0)
        elseif growth == "LEFT" then row:SetPoint("RIGHT", gfx.container, "RIGHT", -off, 0)
        elseif growth == "UP" then row:SetPoint("BOTTOM", gfx.container, "BOTTOM", 0, off)
        else row:SetPoint("TOP", gfx.container, "TOP", 0, -off) end
    end

    local vis = 0
    if isDual then
        local ai = 1
        for _, row in ipairs(rows) do
            if not ok(auras[ai]) then break end
            vis = vis + 1; Pos(row, vis)
            -- IMPORTANT : row:Show() AVANT les ApplyIconModels/ApplyBarModels.
            -- Sinon les PlayerModels 3D sont Show() alors que leur parent (row)
            -- est encore Hide -> IsVisible=false -> invisibles a l'ecran jusqu'au
            -- prochain scan. Bug observe : "le 3D apparait quand je pose une 2e aura".
            row:Show(); row:SetAlpha(1); ns.CancelDeferredHide(row)
            row.halfL:Show()
            ApplyAura(row.iconBtnL, row.iconL, row.iconCDL, auras[ai], glowOn)
            ApplyIconModels(row.iconBtnL, auras[ai])
            ProcCheck(auras[ai], row.iconBtnL)
            row.iconBtnL:SetAlpha(cfg.iconAlpha or 1)
            if ns.Anim and ns.Anim.IconPopIn then
                local instIDL = auras[ai] and auras[ai].auraInstanceID
                if row._iconPopInstIDL ~= instIDL then
                    row._iconPopInstIDL = instIDL
                    ns.Anim.IconPopIn(row.iconBtnL, cfg, cfg.iconAlpha or 1)
                end
            end
            row.barL:Show(); SetBarColor(row.barL, auras[ai])
            if row.wrapBarL then row.wrapBarL:Show(); row.wrapBarL:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapBarL, auras[ai]) end
            if ok(auras[ai + 1]) then
                row.halfR:Show()
                ApplyAura(row.iconBtnR, row.iconR, row.iconCDR, auras[ai + 1], glowOn)
                ApplyIconModels(row.iconBtnR, auras[ai + 1])
                ProcCheck(auras[ai + 1], row.iconBtnR)
                row.iconBtnR:SetAlpha(cfg.iconAlpha or 1)
                if ns.Anim and ns.Anim.IconPopIn then
                    local instIDR = auras[ai+1] and auras[ai+1].auraInstanceID
                    if row._iconPopInstIDR ~= instIDR then
                        row._iconPopInstIDR = instIDR
                        ns.Anim.IconPopIn(row.iconBtnR, cfg, cfg.iconAlpha or 1)
                    end
                end
                row.barR:Show(); SetBarColor(row.barR, auras[ai + 1])
                if row.wrapBarR then row.wrapBarR:Show(); row.wrapBarR:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapBarR, auras[ai + 1]) end
            else row.halfR:Hide() end
            -- Pop animation sur les wraps des barres (icones non animees)
            MaybePop(row, auras[ai], {row.wrapBarL, row.wrapBarR}, bw)
            ai = ai + 2
        end
    else
        for i, row in ipairs(rows) do
            if not ok(auras[i]) then break end
            vis = vis + 1; Pos(row, vis)
            -- IMPORTANT : row:Show() AVANT les ApplyIconModels/ApplyBarModels.
            -- Sinon les PlayerModels 3D sont Show() alors que leur parent (row)
            -- est encore Hide -> IsVisible=false -> invisibles a l'ecran jusqu'au
            -- prochain scan. Bug observe : "le 3D apparait quand je pose une 2e aura".
            row:Show(); row:SetAlpha(1); ns.CancelDeferredHide(row)
            ApplyAura(row.iconBtn, row.icon, row.iconCD, auras[i], glowOn)
            ApplyIconModels(row.iconBtn, auras[i])
            ProcCheck(auras[i], row.iconBtn)
            row.iconBtn:SetAlpha(cfg.iconAlpha or 1)
            if ns.Anim and ns.Anim.IconPopIn then
                local instID = auras[i] and auras[i].auraInstanceID
                if row._iconPopInstID ~= instID then
                    row._iconPopInstID = instID
                    ns.Anim.IconPopIn(row.iconBtn, cfg, cfg.iconAlpha or 1)
                end
            end
            if row.barL then row.barL:Show(); SetBarColor(row.barL, auras[i])
                row.wrapL:Show(); row.wrapL:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapL, auras[i]) end
            if row.barR then row.barR:Show(); SetBarColor(row.barR, auras[i])
                row.wrapR:Show(); row.wrapR:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapR, auras[i]) end
            -- Pop animation sur les barres miroir (mode Aegis)
            MaybePop(row, auras[i], {row.wrapL, row.wrapR}, bw)
        end
    end

    -- Defer hide : les rows qui n'ont PAS été CancelDeferredHide'd dans la boucle
    -- ci-dessus sont désormais réellement inactives. On programme leur Hide dans 100ms.
    -- Si la prochaine Update() les rend actives avant, le Cancel s'en chargera.
    for _, r in ipairs(rows) do
        if not r._aishActiveNow then
            ns.DeferHideRow(r, 0.1)
        end
    end

    -- LearnedDurations : auras qui ont disparu depuis le scan precedent
    -- (etaient dans prevSeenInstIDs, plus dans seenInstIDs) => OnAuraDisappeared.
    -- C'est ce qui declenche StopLearning et donc le stockage de la duree apprise.
    if ns.LearnedDurations and ns.LearnedDurations.OnAuraDisappeared then
        for instID in pairs(prevSeenInstIDs) do
            if not seenInstIDs[instID] then
                ns.LearnedDurations.OnAuraDisappeared(instID)
            end
        end
    end

    -- curIDs sera lu comme prevIDs au prochain scan (gestion double-buffer ci-dessus)
    gfx.container:Show()
    -- FIX v269 : on appelle TOUJOURS UpdateRenderFade qui respecte fadeIC/fadeOOC.
    -- Avant, quand vis==0 on faisait FadeTo(container, 0, 0.05) brutal -> en combat
    -- sur sort CDM, le scan peut intermittemment ne pas voir l'aura (secret values),
    -- ce qui causait : aura visible -> scan vide -> fade out 50ms -> aura redetectee
    -- au scan suivant -> fade in. Resultat : la barre clignotait apparait/disparait.
    --
    -- Maintenant le container reste a alpha fadeIC (1.0 par defaut) en combat. Les
    -- rows individuelles sont gerees par DeferHideRow (100ms de delai avant Hide())
    -- ce qui filtre les disparitions intermittentes.
    ns.UpdateRenderFade("iconlist")
end

-- AishUIAura/Features/Auras/Buffs.lua
-- Layout "Buff autour du cercle" : 2 barres miroir SANS icone, positionnees
-- a l'emplacement standard du Resource Circle (centre de l'ecran, leg. en bas).
-- L'utilisateur peut deplacer librement via Alt+clic gauche.
--
-- Auto-placement vertical par ordre d'apparition :
--   1ere row = centre (y=0)
--   2e row   = +espacement (au-dessus)
--   3e row   = -espacement (en-dessous)
--   4e row   = +2*espacement
--   5e row   = -2*espacement
--   ... (alternance haut/bas auto)
--
-- L'animation des barres est gerée par Core/Animation.lua (AnimateRender)
-- qui detecte automatiquement les rows ayant barL+barR et anime les deux.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local Buffs = {}
ns.RegisterRender("freebars", Buffs)
local CreateFrame, math, pcall = CreateFrame, math, pcall

------------------------------------------------------------------------
-- DIMENSIONS (lit ns.db.freebars)
------------------------------------------------------------------------
local function Dims()
    local c = ns.db and ns.db.freebars or ns.Defaults.freebars
    return c.barW or 60, c.barH or 2,
           c.gap or 12, c.rowGap or 6
end

------------------------------------------------------------------------
-- BARRE (StatusBar avec wrap pour fond + sparks)
-- Inspire de Debuffs.lua MakeBarWrap mais simplifie (pas d'icone-related).
------------------------------------------------------------------------
local function MakeBarWrap(parent, w, h, rev, texKey)
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local wr = CreateFrame("Frame", nil, parent)
    -- PixelUtil.SetSize : aligne sur la grille pixel pour eviter le sub-pixel rendering
    -- (cause des epaisseurs inegales entre barres a barH=2). Fallback SetSize si PixelUtil indispo.
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(wr, w, h)
    else
        wr:SetSize(w, h)
    end
    local tex = ns.ResolveBarTexFromKey(texKey)
    local bar = CreateFrame("StatusBar", nil, wr)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(bar, "TOPLEFT", wr, "TOPLEFT", 0, 0)
        PixelUtil.SetPoint(bar, "BOTTOMRIGHT", wr, "BOTTOMRIGHT", 0, 0)
    else
        bar:SetAllPoints()
    end
    bar:SetStatusBarTexture(tex); bar:SetReverseFill(rev)
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    bar:SetStatusBarColor(ns.barColor[1], ns.barColor[2], ns.barColor[3])

    -- Fond noir derriere la barre
    local bg = wr:CreateTexture(nil, "BACKGROUND", nil, 1); bg:SetAllPoints()
    local bgR = type(cfg.barBgR) == "number" and cfg.barBgR or 0
    local bgG = type(cfg.barBgG) == "number" and cfg.barBgG or 0
    local bgB = type(cfg.barBgB) == "number" and cfg.barBgB or 0
    bg:SetColorTexture(bgR, bgG, bgB, type(cfg.barBgAlpha) == "number" and cfg.barBgAlpha or 0)

    wr._bar = bar  -- utilise par MakeSpark pour reparenter le spark sur la StatusBar
    return wr, bar
end

------------------------------------------------------------------------
-- SPARK (la lueur a la pointe de remplissage de la barre)
-- Pattern bit-exact de Debuffs.lua MakeSpark : layer OVERLAY:7, couleur classe,
-- override user, gradient, desaturation auto.
-- L'ancrage et l'animation (suivi de la pointe de remplissage) sont gérés
-- par Core/Animation.lua AnimateOne (lignes 696-708).
------------------------------------------------------------------------
local function MakeSpark(parent)
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    if not cfg.sparkEnabled then return nil end
    -- "front" = sur la StatusBar (au-dessus du fill), "back" = sur le wrapper
    local sparkParent = (cfg.sparkLayer ~= "back" and parent._bar) or parent
    local s = sparkParent:CreateTexture(nil, "OVERLAY", nil, 7)
    local st = cfg.sparkTexture
    if st and st:find("^atlas:") then s:SetAtlas(st:sub(7))
    else s:SetTexture(st or ns.Media and ns.Media.sparkTex) end
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
    return s
end

------------------------------------------------------------------------
-- ROW : 2 barres miroir, pas d'icone au milieu.
-- La row est centree sur le container : barL a gauche, barR a droite,
-- avec un gap de 'gap' de chaque cote du centre (espace pour le cercle).
------------------------------------------------------------------------
local function CreateBuffRow(cont, i)
    local bw, bh, gp = Dims()
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local row = CreateFrame("Frame", "AishBuffsRow" .. i, cont)
    -- Largeur totale = barre gauche + 2*gap (espace cercle) + barre droite
    -- PixelUtil pour aligner sur la grille pixel (epaisseur uniforme entre rows)
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(row, bw * 2 + gp * 2, bh)
    else
        row:SetSize(bw * 2 + gp * 2, bh)
    end

    -- Barre gauche : vide vers la GAUCHE (rev=true)
    local wL, bL = MakeBarWrap(row, bw, bh, true, cfg.texture)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(wL, "RIGHT", row, "CENTER", -gp, 0)
    else
        wL:SetPoint("RIGHT", row, "CENTER", -gp, 0)
    end
    local sL = MakeSpark(wL)
    wL._spark2D = sL  -- pour ShowSparkModel : ancrage du FX3D Spark sous le 2D

    -- Barre droite : vide vers la DROITE (rev=false)
    local wR, bR = MakeBarWrap(row, bw, bh, false, cfg.texture)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(wR, "LEFT", row, "CENTER", gp, 0)
    else
        wR:SetPoint("LEFT", row, "CENTER", gp, 0)
    end
    local sR = MakeSpark(wR)
    wR._spark2D = sR  -- pour ShowSparkModel : ancrage du FX3D Spark sous le 2D

    -- Duree (texte) — centre sur la row, dans l'espace entre les 2 barres miroir
    -- (la ou se trouve normalement le Resource Circle). Reutilise les cles
    -- timerIcon* de cfg pour beneficier du meme code de mise a jour (Animation.lua).
    local dt = row:CreateFontString(nil, "OVERLAY", nil, 7)
    ns.ApplyFont(dt, cfg.timerFont or ns.Media.font, cfg.timerSize or 11, "OUTLINE")
    dt:SetPoint("CENTER", row, "CENTER", cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
    dt:SetJustifyH("CENTER")
    dt:SetTextColor(cfg.timerColorR or 1, cfg.timerColorG or 1, cfg.timerColorB or 1, 0.9)
    dt._lastText = ""
    row._durText = dt

    row:Hide()
    -- Champs attendus par Animation.lua AnimateRender (cf. lignes 765-767)
    row.barL = bL; row.barR = bR
    row.wrapL = wL; row.wrapR = wR
    row.sparkL = sL; row.sparkR = sR
    -- Callback de cleanup FX3D appele par DeferHideRow juste avant row:Hide().
    -- Cache les PlayerModels qui ne suivent pas toujours Hide() de leur parent
    -- (quirk Blizzard). Necessaire au decochage d'un sort en cours de tracking.
    -- Buffs n'a pas d'icone donc pas de HideIconModel.
    row._aishHideCleanup = function()
        if not ns.SpellFX then return end
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

------------------------------------------------------------------------
-- 3D MODEL APPLY (Step 4) — version Buffs : Bar + Spark seulement (pas d'icone)
------------------------------------------------------------------------
-- Pattern bit-exact de Debuffs.ApplyBarModels mais sans la branche icon
-- (Buffs n'a pas d'icone, layout 2 barres miroir simplifie) ni l'overlay anime.
--
-- Le FX3D s'applique sur les 2 wraps (gauche/droite) avec la MEME aura :
-- chaque wrap a son propre `_fx3dBar` et `_fx3dSpark`, donc le rendu est
-- symetrique et chaque cote suit son propre remplissage. Aucune
-- synchronisation specifique necessaire.
local _barModelCfgB = {}
local _sparkModelCfgB = {}
local _fill2DCfgB = {}

local function ApplyBarModels(barWrap, aura)
    if not barWrap or not ns.db or not ns.EffectsActive() or not ns.SpellFX then return end
    -- Cache : si la meme aura est re-appliquee sur ce wrap, pas besoin de
    -- redo Show. Evite le cycle "Show -> rien faire -> Show -> ..." a chaque
    -- scan qui spammait avant. Le spellID est utilise comme cle stable.
    local spellID = aura.spellID
    local prevID = barWrap._fxAuraID
    -- Mode FOND (front) / REMPLISSAGE 3D (back) : PlayerModel 3D
    -- Mode REMPLISSAGE 2D (mid) : Texture 2D qui se tronque avec la barre
    local mode = aura.barModelMode or "front"
    if (mode == "front" or mode == "back") and aura.barModelID and aura.barModelID ~= 0 then
        if barWrap._fx2dFill then ns.SpellFX:HideFill2D(barWrap._fx2dFill) end
        if not barWrap._fx3dBar then barWrap._fx3dBar = ns.SpellFX:CreateBarModel(barWrap) end
        if barWrap._fx3dBar then
            _barModelCfgB.modelID = aura.barModelID
            _barModelCfgB.alpha = aura.barModelA
            _barModelCfgB.rotation = aura.barModelRot
            _barModelCfgB.x = aura.barModelX
            _barModelCfgB.y = aura.barModelY
            _barModelCfgB.z = aura.barModelZ
            _barModelCfgB.scale = aura.barModelS
            _barModelCfgB.mode = mode
            _barModelCfgB.layer = aura.barModelL
            _barModelCfgB.fxW = aura.barFxW
            _barModelCfgB.fxH = aura.barFxH
            _barModelCfgB.durObj = aura.durObj
            _barModelCfgB.bar = barWrap._bar
            _barModelCfgB.auraInstanceID = aura.auraInstanceID
            _barModelCfgB.barAlphaWith3D = (ns.db and ns.db.freebars and ns.db.freebars.barAlphaWith3D) or 1.0
            ns.SpellFX:ShowBarModel(barWrap._fx3dBar, _barModelCfgB)
        end
    elseif mode == "mid" and aura.barFillTex and aura.barFillTex ~= "" then
        if barWrap._fx3dBar then ns.SpellFX:HideBarModel(barWrap._fx3dBar) end
        if not barWrap._fx2dFill then barWrap._fx2dFill = ns.SpellFX:CreateFill2D(barWrap) end
        if barWrap._fx2dFill then
            _fill2DCfgB.texturePath = aura.barFillTex
            _fill2DCfgB.alpha = aura.barFillAlpha or 0.7
            _fill2DCfgB.tintR = aura.barFillTintR or 1
            _fill2DCfgB.tintG = aura.barFillTintG or 1
            _fill2DCfgB.tintB = aura.barFillTintB or 1
            _fill2DCfgB.scrollSpeed = aura.barFillScroll or 0
            _fill2DCfgB.layer = aura.barFillLayer or "front"
            _fill2DCfgB.bar = barWrap._bar
            ns.SpellFX:ShowFill2D(barWrap._fx2dFill, _fill2DCfgB)
        end
    elseif prevID ~= spellID then
        -- Changement d'aura, l'ancienne avait peut-etre des FX : on cache.
        if barWrap._fx3dBar then ns.SpellFX:HideBarModel(barWrap._fx3dBar) end
        if barWrap._fx2dFill then ns.SpellFX:HideFill2D(barWrap._fx2dFill) end
    end
    barWrap._fxAuraID = spellID
    -- Spark FX3D
    if aura.sparkModelID and aura.sparkModelID ~= 0 then
        if not barWrap._fx3dSpark then barWrap._fx3dSpark = ns.SpellFX:CreateSparkModel(barWrap) end
        if barWrap._fx3dSpark then
            _sparkModelCfgB.modelID = aura.sparkModelID
            _sparkModelCfgB.alpha = aura.sparkModelA
            _sparkModelCfgB.rotation = aura.sparkModelRot
            _sparkModelCfgB.x = aura.sparkModelX
            _sparkModelCfgB.y = aura.sparkModelY
            _sparkModelCfgB.z = aura.sparkModelZ
            _sparkModelCfgB.scale = aura.sparkModelS
            _sparkModelCfgB.layer = aura.sparkModelL
            ns.SpellFX:ShowSparkModel(barWrap._fx3dSpark, _sparkModelCfgB)
        end
    elseif barWrap._fx3dSpark then
        ns.SpellFX:HideSparkModel(barWrap._fx3dSpark)
    end
end

------------------------------------------------------------------------
-- INIT : cree le container + N rows + ancre sur UIParent (deplaçable via Alt+drag)
------------------------------------------------------------------------
function Buffs:Init()
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    if not ns.db or (not ns.db.freebarsEnabled) then return end

    -- Cleanup ancien container (cas reload/refresh)
    if ns.renderFrames.freebars and ns.renderFrames.freebars.container then
        local old = ns.renderFrames.freebars
        if old.rows then
            for _, r in ipairs(old.rows) do r:Hide(); r:SetParent(nil) end
        end
        old.container:Hide(); old.container:SetParent(nil)
    end

    local maxBars = cfg.maxBars or 8
    local bw, bh, gp, rg = Dims()
    local rowW = bw * 2 + gp * 2

    -- Container : largeur = 1 row, hauteur = empilement vertical de maxBars rows
    local cont = CreateFrame("Frame", "AishBuffsCont", UIParent)
    cont:SetSize(rowW, maxBars * (bh + rg))
    cont:SetFrameStrata("BACKGROUND")
    cont:SetMovable(true); cont:SetClampedToScreen(true); cont:EnableMouse(true)
    cont:SetPropagateMouseClicks(true)  -- click-through par défaut (caméra, sélection, etc.)

    -- Position par defaut : centre de l'ecran, leg. en bas (zone Resource Circle).
    -- L'utilisateur peut deplacer via Alt+drag, la position sauvee dans cfg.x/cfg.y.
    cont:ClearAllPoints()
    local x, y = cfg.x or 0, cfg.y or -100
    cont:SetPoint("CENTER", UIParent, "CENTER", x, y)

    -- Creation des rows aux positions auto-alternees (centre, +1, -1, +2, -2, ...)
    local rows = {}
    local rowStep = bh + rg
    for i = 1, maxBars do
        local row = CreateBuffRow(cont, i)
        -- Calcul de la position Y : alternance auto haut/bas
        --   i=1 : 0           (centre)
        --   i=2 : +1*rowStep  (au-dessus)
        --   i=3 : -1*rowStep  (en-dessous)
        --   i=4 : +2*rowStep
        --   i=5 : -2*rowStep
        local yOff
        if i == 1 then
            yOff = 0
        elseif i % 2 == 0 then
            yOff = math.floor(i / 2) * rowStep
        else
            yOff = -math.floor(i / 2) * rowStep
        end
        if PixelUtil and PixelUtil.SetPoint then
            PixelUtil.SetPoint(row, "CENTER", cont, "CENTER", 0, yOff)
        else
            row:SetPoint("CENTER", cont, "CENTER", 0, yOff)
        end
        rows[i] = row
    end

    -- Drag & drop : Alt+clic gauche pour deplacer (cohérent avec Debuffs.lua)
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
        if cx and cy and ns.db and ns.db.freebars then
            ns.db.freebars.x = cx * sc - sx; ns.db.freebars.y = cy * sc - sy
        end
    end)
    cont:SetScript("OnHide", function(s)
        s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        lbl:Hide()
    end)

    cont:Show()
    ns.renderFrames.freebars = { container = cont, rows = rows, layout = "resource_circle" }
    ns.UpdateRenderFade("freebars")
end

------------------------------------------------------------------------
-- ANIMATION D'APPARITION : delegue au helper generique ns.StartPopAnim
-- (cf. Core/Animation.lua). Les parametres sont lus depuis ns.db.freebars :
--   - popEnabled, popDuration, popEaseStrength, popAlphaFade
-- L'ancrage des wraps (wrapL=RIGHT au centre, wrapR=LEFT au centre) fait que
-- le deploiement se fait du centre vers l'exterieur (effet miroir naturel).
------------------------------------------------------------------------
local function StartBuffPopAnim(row, targetW)
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    if ns.StartPopAnim then
        ns.StartPopAnim(row, {row.wrapL, row.wrapR}, targetW, cfg.barAlpha or 1, cfg)
    end
end

------------------------------------------------------------------------
-- UPDATE : montre les rows actives selon le nombre d'auras a afficher.
-- L'animation elle-meme (durees, couleurs, sparks) est geree par
-- Core/Animation.lua AnimateRender("freebars") au tick suivant.
------------------------------------------------------------------------
function Buffs:Update(auras)
    -- Init flag : on cache tant que l'addon n'est pas pret (evite flash au reload)
    if not ns._initComplete then
        if ns.renderFrames.freebars and ns.renderFrames.freebars.container then
            ns.renderFrames.freebars.container:SetAlpha(0)
        end
        return
    end
    if ns.db and (not ns.db.freebarsEnabled or ns.db.useNativeCDM) then
        if ns.renderFrames.freebars and ns.renderFrames.freebars.container then
            ns.renderFrames.freebars.container:SetAlpha(0)
        end
        return
    end

    local gfx = ns.renderFrames.freebars
    if not gfx or not gfx.rows then return end

    auras = auras or {}
    local n = #auras
    local cfg = ns.db and ns.db.freebars or ns.Defaults.freebars
    local targetW = cfg.barW or 45

    -- Montre les n premieres rows + applique couleur/gradient/alpha sur chaque barre.
    -- Pattern aligne sur Debuffs.lua Update (lignes 702-705) : pour chaque aura active,
    -- on Show() la barre, on appelle ns.ApplyBarColor() qui gere :
    --   - couleur du render (cfg.barColorR/G/B)
    --   - gradient horizontal (cfg.gradientEnabled + cfg.gradientR2/G2/B2)
    --   - couleur par sort (aura.spellColor) en fallback
    -- Et on applique l'alpha de barre (cfg.barAlpha) sur le wrap.
    -- Le row:Hide() cascade naturellement vers tous les enfants pour les rows inactives.
    for i, row in ipairs(gfx.rows) do
        if i <= n then
            local a = auras[i]
            -- Detection apparition : la row passait d'inactive a active → declenche le pop
            local wasShown = row:IsShown()
            row:Show()
            if row.barL then
                row.barL:Show()
                ns.ApplyBarColor(row.barL, "freebars", a)
                if row.wrapL then
                    row.wrapL:Show()
                    row.wrapL:SetAlpha(cfg.barAlpha or 1)
                    ApplyBarModels(row.wrapL, a)
                end
            end
            if row.barR then
                row.barR:Show()
                ns.ApplyBarColor(row.barR, "freebars", a)
                if row.wrapR then
                    row.wrapR:Show()
                    row.wrapR:SetAlpha(cfg.barAlpha or 1)
                    ApplyBarModels(row.wrapR, a)
                end
            end
            -- Si la row vient juste d'apparaitre, lance l'animation de scale horizontal
            if not wasShown then
                StartBuffPopAnim(row, targetW)
            end
        else
            -- Row inactive : on stoppe l'eventuelle anim en cours et on hide.
            -- StopPopAnim reset les wraps a targetW pour que la prochaine apparition
            -- reparte d'un etat propre.
            if ns.StopPopAnim then ns.StopPopAnim(row, targetW) end
            -- Cleanup FX3D : cache les modeles 3D des wraps non actifs (gauche + droite)
            -- pour eviter qu'ils restent visibles "fantomes" sur les rows recyclees.
            if row.wrapL then
                row.wrapL._fxAuraID = nil
                if row.wrapL._fx3dBar then ns.SpellFX:HideBarModel(row.wrapL._fx3dBar) end
                if row.wrapL._fx3dSpark then ns.SpellFX:HideSparkModel(row.wrapL._fx3dSpark) end
                if row.wrapL._fx2dFill then ns.SpellFX:HideFill2D(row.wrapL._fx2dFill) end
            end
            if row.wrapR then
                row.wrapR._fxAuraID = nil
                if row.wrapR._fx3dBar then ns.SpellFX:HideBarModel(row.wrapR._fx3dBar) end
                if row.wrapR._fx3dSpark then ns.SpellFX:HideSparkModel(row.wrapR._fx3dSpark) end
                if row.wrapR._fx2dFill then ns.SpellFX:HideFill2D(row.wrapR._fx2dFill) end
            end
            row:Hide()
        end
    end
end


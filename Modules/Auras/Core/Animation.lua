-- AishUIAura/Core/Animation.lua : driver de fade, boucle d'animation (60fps), ticker timer (10fps)
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local CreateFrame, C_Timer, GetTime = CreateFrame, C_Timer, GetTime
local pcall, ipairs, math, string = pcall, ipairs, math, string
local HAS_ISSECRET = (type(issecretvalue) == "function")

-- Render keys pré-construits, réutilisés par les boucles chaudes (évite alloc par tick)
local RENDER_KEYS = {"iconlist", "freebars", "circlebars", "icons", "totems"}

-- FADE (ticker 60fps temporaire, auto-Cancel)
local activeFades = {}
local activeFadeCount = 0
local function EaseOutCubic(t) t = t - 1; return t*t*t + 1 end

function ns.FadeTo(frame, targetAlpha, duration, delay)
    if not frame then return end
    duration = duration or 0.35; delay = delay or 0

    -- En combat : SetAlpha direct (pas de fade) pour réactivité au tab target
    if ns._inCombat then
        if activeFades[frame] then
            activeFades[frame]:Cancel()
            activeFades[frame] = nil
            activeFadeCount = math.max(0, activeFadeCount - 1)
        end
        frame:SetAlpha(targetAlpha)
        return
    end

    -- Anti-clignotement : laisse continuer une fade déjà en cours vers la même target
    local existing = activeFades[frame]
    if existing and existing._target == targetAlpha then
        return  -- déjà en train de fader vers la bonne cible
    end
    if existing then
        existing:Cancel()
        activeFades[frame] = nil
        activeFadeCount = activeFadeCount - 1
    end
    local startAlpha = frame:GetAlpha()
    if math.abs(startAlpha - targetAlpha) < 0.01 then frame:SetAlpha(targetAlpha); return end
    local startTime = GetTime() + delay
    local ticker
    ticker = _addon.NewTicker(0.016, function()
        local now = GetTime()
        if now < startTime then return end
        local progress = math.min((now - startTime) / duration, 1)
        frame:SetAlpha(startAlpha + (targetAlpha - startAlpha) * EaseOutCubic(progress))
        if progress >= 1 then
            frame:SetAlpha(targetAlpha)
            ticker:Cancel()
            if activeFades[frame] then
                activeFades[frame] = nil
                activeFadeCount = activeFadeCount - 1
                if activeFadeCount <= 0 then activeFadeCount = 0 end
            end
        end
    end)
    ticker._target = targetAlpha  -- on tag la target pour les checks ultérieurs
    activeFades[frame] = ticker
    activeFadeCount = activeFadeCount + 1
end

-- ns.renderFrames pointe l'ancien rendu manuel (caché) ; le vrai conteneur natif vient de ns.Get*NativeContainer.
local function GetRenderContainer(renderKey)
    local frames = ns.renderFrames and ns.renderFrames[renderKey]
    local container
    if renderKey == "icons" and ns.GetIconsNativeContainer then
        container = ns.GetIconsNativeContainer()
    elseif renderKey == "freebars" and ns.GetCircleBarsNativeContainer then
        container = ns.GetCircleBarsNativeContainer()
    elseif renderKey == "circlebars" and ns.GetFreeBarsNativeContainer then
        container = ns.GetFreeBarsNativeContainer()
    elseif renderKey == "iconlist" and ns.GetIconListNativeContainer then
        container = ns.GetIconListNativeContainer()
    end
    return container or (frames and frames.container), frames
end

-- SURVOL : un mode transparent (alpha hors combat < 1) repasse opaque tant que la souris est dessus.
-- Souris sur le cadre du conteneur, ou sur un de ses boutons (tooltip natif) remonte via GetMouseFoci.
local hovered = {}
local function IsSecretV(v) return HAS_ISSECRET and issecretvalue(v) end
local function MouseOverContainer(container)
    local ok, over = pcall(container.IsMouseOver, container)
    if ok and not IsSecretV(over) and over then return true end
    -- Conteneur natif (Icones, Liste d'icones) : sa taille ne couvre pas les icones qui en debordent, et
    -- leurs barres (enfants des icones) debordent encore. Rectangle englobant de tout ce qui est affiche
    -- (enfants + petits-enfants), en pixels ecran, compare au curseur.
    local minX, minY, maxX, maxY
    local function Add(f)
        local okS, shown = pcall(f.IsShown, f)
        if not okS or IsSecretV(shown) or not shown then return false end
        local okR, l, b, w, h = pcall(f.GetRect, f)
        if okR and l and not (IsSecretV(l) or IsSecretV(b) or IsSecretV(w) or IsSecretV(h)) and w > 0 and h > 0 then
            local s = f:GetEffectiveScale()
            l, b, w, h = l * s, b * s, w * s, h * s
            minX = minX and math.min(minX, l) or l
            minY = minY and math.min(minY, b) or b
            maxX = maxX and math.max(maxX, l + w) or (l + w)
            maxY = maxY and math.max(maxY, b + h) or (b + h)
        end
        return true
    end
    -- Varargs plutot que { GetChildren() } : aucune table creee (appele toutes les 0,5 s par rendu)
    local function AddSubs(...)
        for i = 1, select("#", ...) do Add((select(i, ...))) end
    end
    local function AddKids(...)
        for i = 1, select("#", ...) do
            local k = select(i, ...)
            if Add(k) then pcall(AddSubs, k:GetChildren()) end
        end
    end
    pcall(function() AddKids(container:GetChildren()) end)
    if minX then
        local cx, cy = GetCursorPosition()
        if cx >= minX and cx <= maxX and cy >= minY and cy <= maxY then return true end
    end
    local foci = GetMouseFoci and GetMouseFoci()
    if not foci then return false end
    for _, f in ipairs(foci) do
        local p, depth = f, 0
        while p and depth < 8 do
            if p == container then return true end
            local okP, parent = pcall(p.GetParent, p)
            p = okP and parent or nil
            depth = depth + 1
        end
    end
    return false
end
-- Zone de survol calculee depuis les reglages, comme le placement du conteneur natif (Reposition*NativeGrid,
-- AuraTrackerContainer.lua) : la geometrie d'un AuraContainer peut etre secrete, et les icones sans souris
-- n'apparaissent pas dans GetMouseFoci. Rectangle en unites d'UIParent, relatif a son centre.
local function AnchoredRect(point, x, y, w, h)
    local l, b
    if point == "TOP" then l, b = x - w / 2, y - h
    elseif point == "BOTTOM" then l, b = x - w / 2, y
    elseif point == "LEFT" then l, b = x, y - h / 2
    elseif point == "RIGHT" then l, b = x - w, y - h / 2
    else l, b = x - w / 2, y - h / 2 end
    return l, b, l + w, b + h
end

local function ConfigZone(key)
    local cfg = ns.db and ns.db[key] or (ns.Defaults and ns.Defaults[key])
    if not cfg then return nil end
    if key == "icons" then
        local growth = cfg.growth or "LEFT"
        local iw, ih, rg = cfg.iconW or 26, cfg.iconH or 26, cfg.rowGap or 2
        local order = ns.slotOrderByDest and ns.slotOrderByDest.icons
        local n = math.max(order and #order or 0, 1)
        local x, y = cfg.x or -199, cfg.y or -247
        if growth == "UP" or growth == "DOWN" then
            return AnchoredRect(growth == "UP" and "BOTTOM" or "TOP", x, y, iw, n * (ih + rg))
        end
        return AnchoredRect(growth == "RIGHT" and "LEFT" or "RIGHT", x, y, n * (iw + rg), ih)
    elseif key == "iconlist" then
        local bw, iw, ih = cfg.barW or 80, cfg.iconW or 25, cfg.iconH or 25
        local gp, pg, rg = cfg.gap or 12, cfg.pairGap or 6, cfg.rowGap or 3
        local maxBars = cfg.maxBars or 8
        local growth = cfg.growth or "DOWN"
        local x, y = cfg.x or 0, cfg.y or -290
        if (cfg.layout or "center_mirror") == "center_dual" then
            local half = iw + gp + bw
            local h = math.ceil(maxBars / 2) * (ih + rg)
            return AnchoredRect(growth == "UP" and "BOTTOM" or "TOP", x, y, half * 2 + pg, h)
        end
        local rowW = bw * 2 + iw + gp * 2
        if growth == "LEFT" or growth == "RIGHT" then
            return AnchoredRect(growth == "RIGHT" and "LEFT" or "RIGHT", x, y, maxBars * (rowW + rg), ih)
        end
        return AnchoredRect(growth == "UP" and "BOTTOM" or "TOP", x, y, rowW, maxBars * (ih + rg))
    end
end

local function MouseInConfigZone(key)
    local l, b, r, t = ConfigZone(key)
    if not l then return false end
    local s = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / s - UIParent:GetWidth() / 2, cy / s - UIParent:GetHeight() / 2
    return cx >= l and cx <= r and cy >= b and cy <= t
end

C_Timer.NewTicker(0.5, function()
    if not ns.db then return end
    if ns.IsAuraHidingContext and ns.IsAuraHidingContext() then return end   -- auras masquees (monture, taxi...)
    for i = 1, #RENDER_KEYS do
        local key = RENDER_KEYS[i]
        local container = GetRenderContainer(key)
        local okV, shown = false, false
        if container then okV, shown = pcall(container.IsVisible, container) end
        -- Visibilite secrete (AuraContainer natif) : consideree visible (les masquages durs sont filtres plus haut)
        local visible = okV and (IsSecretV(shown) or shown)
        local over = visible and (MouseInConfigZone(key) or MouseOverContainer(container)) or false
        if over ~= (hovered[key] or false) then
            hovered[key] = over or nil
            pcall(ns.UpdateRenderFade, key)
        end
    end
end)

-- Visibilite du cercle central (ResourceCircle.ShouldShow), nil si le module est absent
local function CircleShown()
    local RC = _addon.Modules and _addon.Modules.ResourceCircle
    if not (RC and RC.ShouldShow) then return nil end
    local ok, shown = pcall(RC.ShouldShow)
    if not ok then return nil end
    return shown == true
end

-- Rafraichit les barres de cercle a chaque changement de visibilite du cercle (cible, combat, instance...)
do
    local RC = _addon.Modules and _addon.Modules.ResourceCircle
    if RC and RC.UpdateVisibility then
        hooksecurefunc(RC, "UpdateVisibility", function()
            if ns.db then pcall(ns.UpdateRenderFade, "freebars") end
        end)
    end
end

function ns.UpdateRenderFade(renderKey)
    local cfg = ns.db and ns.db[renderKey]; if not cfg then return end
    local frames = ns.renderFrames[renderKey]
    local container
    if renderKey == "icons" and ns.GetIconsNativeContainer then
        container = ns.GetIconsNativeContainer()
    elseif renderKey == "freebars" and ns.GetCircleBarsNativeContainer then
        container = ns.GetCircleBarsNativeContainer()
    elseif renderKey == "circlebars" and ns.GetFreeBarsNativeContainer then
        container = ns.GetFreeBarsNativeContainer()
    elseif renderKey == "iconlist" and ns.GetIconListNativeContainer then
        container = ns.GetIconListNativeContainer()
    end
    container = container or (frames and frames.container)
    if not container then return end
    -- combatOnly : cache le container hors combat (sauf mode preview, forcé à 1.0)
    local previewActiveHere = ns._previewBars and (ns._previewMode == "all" or ns._previewMode == renderKey)
    -- Barres de cercle : suivent la visibilite du cercle central (ex. "Toujours visible") au lieu du
    -- seul combat. Le cercle n'a pas d'opacite propre : affiche = pleine opacite, masque = 0.
    local followCircle   -- nil = autres rendus (regle habituelle)
    if renderKey == "freebars" then followCircle = CircleShown() end
    local target
    local hidden = false   -- masquage dur (pas une simple transparence) : le survol ne le leve pas
    if previewActiveHere then
        target = 1.0
    elseif followCircle ~= nil and not ns._inCombat then
        target = followCircle and (cfg.fadeIC or 1.0) or 0
        hidden = not followCircle
    elseif cfg.combatOnly and not ns._inCombat then
        target = 0
        hidden = true
    else
        target = ns._inCombat and (cfg.fadeIC or 1.0) or (cfg.fadeOOC or 0.4)
    end
    local delay = ns._inCombat and (cfg.fadeDelayIC or 0) or (cfg.fadeDelayOOC or 0)
    -- Fade court (0.05s) en combat pour réactivité tab target, complet hors combat
    local duration = ns._inCombat and 0.05 or (cfg.fadeDuration or 0.35)
    -- Survol : opaque tout de suite (hors "combat uniquement", cache hors combat)
    if hovered[renderKey] and not hidden then target, delay, duration = 1.0, 0, 0.15 end
    ns.FadeTo(container, target, duration, delay)

    -- PlayerModel ne suit pas l'alpha parent (quirk Blizzard) : cache-le manuellement.
    -- Pas de Show() ici (géré par ShowBarModel) sinon des clips orphelins réapparaissent.
    if frames and frames.rows and target == 0 then
        for _, row in ipairs(frames.rows) do
            local function HideClip(wrap)
                if wrap and wrap._fx3dBar and wrap._fx3dBar.clip then
                    wrap._fx3dBar.clip:Hide()
                end
            end
            HideClip(row.wrap)
            HideClip(row.wrapL)
            HideClip(row.wrapR)
            HideClip(row.wrapBarL)
            HideClip(row.wrapBarR)
        end
    end
end

function ns.UpdateAllFades()
    for i = 1, #RENDER_KEYS do ns.UpdateRenderFade(RENDER_KEYS[i]) end
    pcall(function() if ns.Providers and ns.Providers.UpdateFade then ns.Providers:UpdateFade() end end)
end

-- Hide différé anti-flicker : programme un Hide() dans `delay`s, annulé si la row redevient active.
-- Hide() (pas SetAlpha) car OnHide reset _timerMode sur les bars enfants.
function ns.DeferHideRow(row, delay)
    if not row then return end
    if row._aishHidePending then return end
    row._aishHidePending = true
    C_Timer.After(delay or 0.1, function()
        if row._aishHidePending then
            row._aishHidePending = nil
            if row._aishActiveNow then return end
            row._popInstID = nil
            if ns.StopPopAnim then ns.StopPopAnim(row) end
            -- Cleanup FX3D via callback : PlayerModel ne suit pas toujours Hide() du parent
            if row._aishHideCleanup then pcall(row._aishHideCleanup) end
            row:Hide()
        end
    end)
end

-- Annule un hide différé : la row est (re)devenue active. Force aussi Show + alpha 1.
function ns.CancelDeferredHide(row)
    if not row then return end
    row._aishHidePending = nil
    row._aishActiveNow = true
end

-- Marque la row comme inactive (avant de lancer un DeferHideRow).
function ns.MarkRowInactive(row)
    if not row then return end
    row._aishActiveNow = false
end

-- Animation d'apparition "pop" : scale horizontal + fade-in alpha, easing configurable via cfg.pop*
function ns.StartPopAnim(row, wraps, targetW, targetAlpha, cfg)
    if not row or not wraps or #wraps == 0 then return end
    cfg = cfg or {}
    local tAlpha = targetAlpha or 1

    -- Mode desactive : on saute direct a l'etat final
    if cfg.popEnabled == false then
        for _, w in ipairs(wraps) do
            if w then
                if PixelUtil and PixelUtil.SetSize then
                    PixelUtil.SetSize(w, targetW, w:GetHeight() or 1)
                else
                    w:SetWidth(targetW)
                end
                w:SetAlpha(tAlpha)
            end
        end
        return
    end

    local duration = cfg.popDuration or 1.0
    local strength = cfg.popEaseStrength or 5
    local doAlpha = cfg.popAlphaFade ~= false

    -- Etat de l'anim stocke sur la row
    row._popElapsed = 0
    row._popTargetW = targetW
    row._popTargetAlpha = tAlpha
    row._popDuration = duration
    row._popStrength = strength
    row._popDoAlpha = doAlpha
    row._popWraps = wraps
    row._popActive = true

    -- Etat initial : largeur 1px, alpha 0 (ou alpha cible si fade desactive)
    for _, w in ipairs(wraps) do
        if w then
            -- Flag le wrap : ShowBarModel va respecter ce flag et garder le clip cache
            w._popInProgress = true
            if PixelUtil and PixelUtil.SetSize then
                PixelUtil.SetSize(w, 1, w:GetHeight() or 1)
            else
                w:SetWidth(1)
            end
            if doAlpha then w:SetAlpha(0) else w:SetAlpha(tAlpha) end
            -- Cache le PlayerModel 3D pendant l'anim (ne suit pas SetAlpha parent)
            if w._fx3dBar and w._fx3dBar.clip then
                w._fx3dBar.clip:Hide()
            end
        end
    end

    row:SetScript("OnUpdate", function(self, elapsed)
        self._popElapsed = (self._popElapsed or 0) + elapsed
        local t = self._popElapsed / (self._popDuration or 1.0)
        if t >= 1 then
            -- Fin d'anim : valeurs finales, stop ticker
            for _, w in ipairs(self._popWraps) do
                if w then
                    w._popInProgress = nil  -- retire le flag
                    if PixelUtil and PixelUtil.SetSize then
                        PixelUtil.SetSize(w, self._popTargetW, w:GetHeight() or 1)
                    else
                        w:SetWidth(self._popTargetW)
                    end
                    w:SetAlpha(self._popTargetAlpha)
                    -- Reaffiche le PlayerModel 3D maintenant que la barre est stable
                    if w._fx3dBar and w._fx3dBar.clip then
                        w._fx3dBar.clip:Show()
                    end
                end
            end
            self._popActive = false
            self:SetScript("OnUpdate", nil)
            return
        end
        -- Easing easeOut : départ rapide, décélération douce (ancien easeOutIn faisait 2 phases visibles)
        local eased = 1 - (1 - t) ^ self._popStrength
        local nw = math.max(1, self._popTargetW * eased)
        local na = self._popDoAlpha and (self._popTargetAlpha * eased) or self._popTargetAlpha
        for _, w in ipairs(self._popWraps) do
            if w then
                if PixelUtil and PixelUtil.SetSize then
                    PixelUtil.SetSize(w, nw, w:GetHeight() or 1)
                else
                    w:SetWidth(nw)
                end
                if self._popDoAlpha then w:SetAlpha(na) end
            end
        end
    end)
end

-- Stoppe l'anim pop en cours, reset les wraps à l'état final si resetW fourni
function ns.StopPopAnim(row, resetW)
    if not row or not row._popActive then return end
    row:SetScript("OnUpdate", nil)
    row._popActive = false
    if row._popWraps then
        for _, w in ipairs(row._popWraps) do
            if w then
                w._popInProgress = nil  -- retire le flag
                if resetW then
                    if PixelUtil and PixelUtil.SetSize then
                        PixelUtil.SetSize(w, resetW, w:GetHeight() or 1)
                    else
                        w:SetWidth(resetW)
                    end
                    w:SetAlpha(1)
                end
                -- Reaffiche le PlayerModel 3D
                if w._fx3dBar and w._fx3dBar.clip then
                    w._fx3dBar.clip:Show()
                end
            end
        end
    end
end

-- DRIVER D'ANIMATION (OnUpdate 20fps, AnimateBar dual-path)
local animDriver = CreateFrame("Frame")
animDriver._t = 0

-- SetTimerDuration (Midnight 12.x) : si dispo, Blizzard anime la barre en 60fps natif
local HAS_TIMER_DURATION = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection) and true or false
local INTERP_SMOOTH    = HAS_TIMER_DURATION and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
local INTERP_IMMEDIATE = HAS_TIMER_DURATION and Enum.StatusBarInterpolation.Immediate or nil
local TIMER_DIR_DRAIN  = HAS_TIMER_DURATION and Enum.StatusBarTimerDirection.RemainingTime or nil

-- Clé d'aura (doit changer au refresh) : combine instID + refreshCounter + durObj
local function GetAuraKey(entry)
    if not entry then return nil end
    local inst = entry.auraInstanceID or entry.instID
    local durRef = entry.durObj and tostring(entry.durObj) or ""
    local refreshCnt = (inst and ns._refreshCounter and ns._refreshCounter[inst]) or 0
    -- durRef reste dans la clé pour retrigger SetTimerDuration si Blizzard recrée le durObj
    if inst then return "i:" .. tostring(inst) .. ":" .. refreshCnt .. ":" .. durRef end
    if entry.spellID then
        return "s:" .. tostring(entry.spellID) .. ":" .. tostring(entry.unit or "?") .. ":" .. refreshCnt .. ":" .. durRef
    end
    return nil
end

-- Extrait (instID, refreshCnt) d'un auraKey pour distinguer refresh réel vs recréation durObj
local function _ExtractKeyParts(auraKey)
    if not auraKey then return nil, nil end
    local inst, cnt = auraKey:match("^i:([^:]+):([^:]+):")
    if inst then return inst, cnt end
    -- Format spellID fallback : "s:<spellID>:<unit>:<cnt>:<ref>"
    local sid, unit, cnt2 = auraKey:match("^s:([^:]+):([^:]+):([^:]+):")
    if sid then return sid .. "@" .. unit, cnt2 end
    return nil, nil
end

-- Arrête le mode timer natif Blizzard, restaure SetValue manuel
local function _StopTimerApply(bar)
    bar:SetMinMaxValues(0, 1, INTERP_IMMEDIATE)
    bar:SetValue(bar:GetValue() or 0, INTERP_IMMEDIATE)
end

local function StopTimerMode(bar)
    if not bar then return end
    if bar._timerMode then
        -- Pas de ClearTimerDuration Blizzard : on retombe sur SetValue Immediate
        pcall(_StopTimerApply, bar)
        bar._timerMode = false
        bar._timerKey = nil
    end
end

-- Hook OnHide (une fois) : reset le mode timer quand la barre devient invisible
local function EnsureHideHook(bar)
    if not bar or bar._aishHideHooked then return end
    bar._aishHideHooked = true
    bar:HookScript("OnHide", function(self)
        if self._timerMode then
            self._timerMode = false
            self._timerKey = nil
            -- Pas besoin de toucher SetValue : la barre est invisible
        end
    end)
end

-- Couleur d'urgence : color curve native Blizzard (secret-safe) par % de durée restante,
-- fallback interpolation manuelle en secondes si pas de durObj/curve.

local HAS_CURVE_UTIL = (C_CurveUtil and C_CurveUtil.CreateColorCurve) and true or false
local curveCache = {}  -- [keyHex] = curve object

-- Wipe le cache quand l'utilisateur change les couleurs d'urgence (menus Render)
function ns.InvalidateUrgencyCurves()
    wipe(curveCache)
end

-- Construit (ou récupère du cache) une color curve Blizzard (base/medium/critical)
local function GetOrBuildCurve(cR, cG, cB, mR, mG, mB, crR, crG, crB)
    if not HAS_CURVE_UTIL then return nil end
    if not cR then return nil end

    -- Defaults si couleurs urgence non fournies
    mR = mR or 1.0;  mG = mG or 0.5;  mB = mB or 0.0
    crR = crR or 1.0; crG = crG or 0.15; crB = crB or 0.05

    -- Clé de cache : packed des 3 couleurs (précision 1/255 suffisante)
    local key = string.format("%02x%02x%02x_%02x%02x%02x_%02x%02x%02x",
        math.floor((cR or 0) * 255 + 0.5),
        math.floor((cG or 0) * 255 + 0.5),
        math.floor((cB or 0) * 255 + 0.5),
        math.floor(mR * 255 + 0.5),
        math.floor(mG * 255 + 0.5),
        math.floor(mB * 255 + 0.5),
        math.floor(crR * 255 + 0.5),
        math.floor(crG * 255 + 0.5),
        math.floor(crB * 255 + 0.5))
    if curveCache[key] then return curveCache[key] end

    local ok, curve = pcall(function() return C_CurveUtil.CreateColorCurve() end)
    if not ok or not curve then return nil end

    -- Points croissants 0→1 : 0=critique, 0.20=medium, 0.50/1.00=couleur base
    pcall(function()
        curve:SetType(Enum.LuaCurveType.Linear)
        curve:AddPoint(0.00, CreateColor(crR, crG, crB, 1))
        curve:AddPoint(0.20, CreateColor(mR, mG, mB, 1))
        curve:AddPoint(0.50, CreateColor(cR, cG, cB, 1))
        curve:AddPoint(1.00, CreateColor(cR, cG, cB, 1))
    end)

    curveCache[key] = curve
    return curve
end

-- Évalue la curve et applique la couleur sur bar (pcall car durObj peut être tainted)
local function EvaluateCurveAndApply(durObj, curve, bar)
    local colorResult = durObj:EvaluateRemainingPercent(curve)
    if colorResult then
        bar:SetStatusBarColor(colorResult:GetRGB())
    end
end

-- Applique la couleur d'urgence (curve native si possible, sinon fallback manuel)
local function ApplyUrgencyColor(bar, entry, cR, cG, cB, remSeconds, cfg)
    if not cR then return end

    -- Bypass si gradient par sort actif (SetStatusBarColor l'écraserait)
    if bar._spellGradientActive then return end

    -- Même bypass pour le gradient par render (cfg.gradientEnabled)
    if cfg and cfg.gradientEnabled then return end

    -- Curve désactivée : couleur de base sans variation d'urgence
    if cfg and cfg.urgencyEnabled == false then
        bar:SetStatusBarColor(cR, cG, cB)
        return
    end

    -- Lecture des couleurs medium/critical depuis la config render (avec defaults)
    local mR, mG, mB, crR, crG, crB
    if cfg then
        mR, mG, mB = cfg.urgencyMediumR, cfg.urgencyMediumG, cfg.urgencyMediumB
        crR, crG, crB = cfg.urgencyCriticalR, cfg.urgencyCriticalG, cfg.urgencyCriticalB
    end

    -- CHEMIN PRIMAIRE : color curve native Blizzard via durObj
    if entry and entry.durObj then
        local curve = GetOrBuildCurve(cR, cG, cB, mR, mG, mB, crR, crG, crB)
        if curve then
            local ok = pcall(EvaluateCurveAndApply, entry.durObj, curve, bar)
            if ok then return end
        end
    end

    -- CHEMIN FALLBACK : interpolation manuelle en secondes (pour auras sans durObj)
    if not remSeconds then return end
    local CRIT = ns.URGENCY.CRITICAL or 2
    local MED  = ns.URGENCY.MEDIUM or 5
    local r, g, b
    if remSeconds >= MED then
        r, g, b = cR, cG, cB
    elseif remSeconds >= CRIT then
        local t = (remSeconds - CRIT) / (MED - CRIT)
        local mR = math.min(cR * 1.2, 1)
        local mG = cG * 0.7
        local mB = cB * 0.7
        r = mR + (cR - mR) * t
        g = mG + (cG - mG) * t
        b = mB + (cB - mB) * t
    else
        local t = math.max(0, remSeconds) / CRIT
        local mR = math.min(cR * 1.2, 1)
        local mG = cG * 0.7
        local mB = cB * 0.7
        local crR = math.min(cR * 1.4, 1)
        local crG = cG * 0.4
        local crB = cB * 0.4
        r = crR + (mR - crR) * t
        g = crG + (mG - crG) * t
        b = crB + (mB - crB) * t
    end
    bar:SetStatusBarColor(r, g, b)
end

-- AnimateBar : moteur d'animation des barres. Pattern "show but don't know" pour
-- les auras secret en combat — passthrough direct du durObj Blizzard, jamais lu en Lua.
-- Tier 0 : SetTimerDuration (60fps natif). Tier 1 : SetMinMaxValues/SetValue (fallback).

local function _StartTimerMode(bar, durObj, isFirstLaunch)
    -- Immediate au premier lancement (apparition instantanée), Smooth au refresh
    local interp = isFirstLaunch and INTERP_IMMEDIATE or INTERP_SMOOTH
    bar:SetMinMaxValues(0, 1, interp)
    bar:SetTimerDuration(durObj, interp, TIMER_DIR_DRAIN)
end

local function _ApplyTier1SetValue(bar, durObj)
    -- Immediate forcé (SetValue peut interpoler par défaut en Midnight 12.0)
    bar:SetMinMaxValues(0, durObj:GetTotalDuration(), INTERP_IMMEDIATE)
    bar:SetValue(durObj:GetRemainingDuration(), INTERP_IMMEDIATE)
end

-- Tier 2 (combat) : button:SetDurationBar (binding natif ElvUI-like), posé une fois
-- hors combat dans AuraTrackerContainer.lua — rien à refaire ici.

-- Diagnostic /aishdebug bars : dump l'état interne des barres de durée
function ns.DebugDurationBars()
    local P = function(s) print("|cff33aaff[Bars]|r " .. s) end
    for _, key in ipairs({ "circlebars", "freebars" }) do
        local gfx = ns.renderFrames and ns.renderFrames[key]
        local auras = ns.auraData and ns.auraData[key] or {}
        P(string.format("== %s == rows=%s auras=%d", key,
            tostring(gfx and gfx.rows and #gfx.rows or "nil"), #auras))
        if gfx and gfx.rows then
            for i, row in ipairs(gfx.rows) do
                if row:IsShown() then
                    local a = auras[i]
                    if a and a.unit and a.spellID then
                        local nativeBtn = ns.GetNativeAuraButton and ns.GetNativeAuraButton(a.unit, a.spellID)
                        local sb = ns.GetNativeShadowBar and ns.GetNativeShadowBar(a.unit, a.spellID)
                        -- Ne pas lire sb:IsShown()/GetValue() (plante en objet forbidden)
                        P(string.format(
                            "  row%d useCDMSwipe=%s spellID=%s unit=%s durObj=%s | nativeBtn=%s shadowBar=%s",
                            i, tostring(a.useCDMSwipe), tostring(a.spellID), tostring(a.unit),
                            tostring(a.durObj ~= nil),
                            tostring(nativeBtn ~= nil), tostring(sb ~= nil)))
                    end
                end
            end
        end
    end
end

-- Remplissage plein d'une aura sans durée (même texture que la barre, au-dessus du fill natif)
local function ShowFullOverlay(bar, r, g, b)
    if not r then r, g, b = bar:GetStatusBarColor() end
    local ov = bar._aishFull
    if not ov then
        ov = bar:CreateTexture(nil, "ARTWORK", nil, 7)
        ov:SetAllPoints(bar)
        bar._aishFull = ov
    end
    local fill = bar:GetStatusBarTexture()
    local path = fill and fill.GetTexture and fill:GetTexture()
    if path then ov:SetTexture(path) else ov:SetColorTexture(1, 1, 1) end
    ov:SetVertexColor(r, g, b)
    ov:Show()
end

local function HideFullOverlay(bar)
    if bar._aishFull then bar._aishFull:Hide() end
end

-- Barres natives (SetDurationBar, AuraTrackerContainer.lua) : Blizzard les pilote seul et laisse
-- vide celle d'une aura sans durée. Boutons enregistres a leur construction, recouverts apres chaque scan.
local _nativeButtons = setmetatable({}, { __mode = "k" })
function ns.RegisterNativeAuraButton(btn) _nativeButtons[btn] = true end
local NATIVE_BAR_FIELDS = { "_aishDurBar", "_aishBar", "_aishBarL", "_aishBarR" }
function ns.UpdateNoDurationBars()
    local nd = ns._noDurationSpells or {}
    for btn in pairs(_nativeButtons) do
        local sid = btn._aishSpellID
        local full = sid and nd[sid] == true
        for _, f in ipairs(NATIVE_BAR_FIELDS) do
            local bar = btn[f]
            if bar then
                if full then pcall(ShowFullOverlay, bar) else HideFullOverlay(bar) end
            end
        end
    end
end

local function AnimateBar(bar, entry, cR, cG, cB, isReverse, cfg)
    if not bar then return end

    -- Hook OnHide idempotent : sort du mode timer quand la barre devient invisible
    EnsureHideHook(bar)

    -- Tier preview (menu Effets) : simule un cycle 12s sans durObj réel pour visualiser les FX
    if entry._isPreview then
        HideFullOverlay(bar)
        if bar._timerMode then StopTimerMode(bar) end
        local CYCLE = 12
        local now = GetTime()
        local startTime = bar._previewStart
        if not startTime or (now - startTime) >= CYCLE then
            startTime = now
            bar._previewStart = startTime
        end
        local elapsed = now - startTime
        local pct = 1 - (elapsed / CYCLE)  -- 1 (plein) -> 0 (vide) sur 12s
        if pct < 0 then pct = 0 end
        if pct > 1 then pct = 1 end
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(pct)
        bar:SetStatusBarColor(cR, cG, cB)
        return
    end

    -- Aura sans durée : barre pleine. Texture par-dessus le remplissage plutôt que SetValue(1) : un
    -- binding natif (SetDurationBar, AuraTrackerContainer.lua) peut repiloter la valeur à 0 derrière nous.
    if entry.noDuration then
        if bar._timerMode then StopTimerMode(bar) end
        pcall(bar.SetMinMaxValues, bar, 0, 1)
        pcall(bar.SetValue, bar, 1)
        ShowFullOverlay(bar, cR, cG, cB)
        return
    end
    HideFullOverlay(bar)

    -- Tier 2 : binding natif déjà posé (AuraTrackerContainer.lua), rien à faire ici
    if entry.useCDMSwipe then
        return
    end

    local auraKey = GetAuraKey(entry)

    -- Tier 0 : SetTimerDuration une fois par aura, puis juste la couleur ensuite.
    -- Direction toujours RemainingTime ; l'inversion visuelle vient de SetReverseFill (création).
    if HAS_TIMER_DURATION and entry.durObj and auraKey then
        if not bar._timerMode or bar._timerKey ~= auraKey then
            -- Cas : 1=jamais utilisée, 2=nouvelle aura, 3=refresh (Smooth), 4=recréation
            -- silencieuse du durObj (Immediate) — évite un délai visuel post-tab target.
            local isFirstLaunch
            if not bar._timerMode then
                isFirstLaunch = true  -- cas 1
            else
                -- Compare inst et refreshCnt : si identiques, c'est le cas 4 (durRef seul change)
                local oldInst, oldCnt = _ExtractKeyParts(bar._timerKey)
                local newInst, newCnt = _ExtractKeyParts(auraKey)
                if oldInst ~= newInst then
                    isFirstLaunch = true   -- cas 2 : vraie nouvelle aura
                elseif oldCnt ~= newCnt then
                    isFirstLaunch = false  -- cas 3 : vrai refresh → Smooth
                else
                    isFirstLaunch = true   -- cas 4 : recréation silencieuse → Immediate
                end
            end
            local timerOK = pcall(_StartTimerMode, bar, entry.durObj, isFirstLaunch)
            if timerOK then
                bar._timerMode = true
                bar._timerKey = auraKey
            end
        end

        -- Couleur via curve native (secret-safe, pas de lecture Lua)
        if bar._timerMode then
            ApplyUrgencyColor(bar, entry, cR, cG, cB, nil, cfg)
            return
        end
        -- Si SetTimerDuration a échoué on continue vers Tier 1
    end

    -- TIER 1 : Duration Object direct (SetValue manuel, passthrough secret)
    if entry.durObj then
        -- Si on était en mode timer avant, il faut sortir proprement
        if bar._timerMode then StopTimerMode(bar) end

        local applied = pcall(_ApplyTier1SetValue, bar, entry.durObj)

        if applied then
            -- Couleur via curve native (secret-safe)
            ApplyUrgencyColor(bar, entry, cR, cG, cB, nil, cfg)
            return
        end
    end

    -- Aucun tier n'a fonctionné : sort du mode timer par sécurité (ne devrait pas arriver)
    if bar._timerMode then StopTimerMode(bar) end
end

-- Positionne le clip 3D via SetAllPoints (combat-safe, aucun calcul pixel Lua).
-- Mode "front" : ancré sur barWrap. Mode "back" : ancré sur la texture de remplissage.
local function UpdateClip3DPart(bar, barWrap, clip, mode)
    if not clip then return end
    if mode == "front" then
        clip:ClearAllPoints()
        clip:SetAllPoints(barWrap)
    elseif mode == "back" and bar and bar.GetStatusBarTexture then
        -- Ancré sur le rectangle de remplissage (anime par SetTimerDuration côté C++)
        local fillRect = bar:GetStatusBarTexture()
        if fillRect and clip._anchoredFillRect ~= fillRect then
            clip:ClearAllPoints()
            clip:SetAllPoints(fillRect)
            clip._anchoredFillRect = fillRect
        end
    end
end

-- Scrolling temporel des textures Fill 2D animées (FillFlamme, etc.). Géométrie
-- déjà gérée par l'ancrage dans ShowFill2D ; no-op si scrollSpeed=0.
local function UpdateFill2DPart(fill2d)
    if not fill2d or not fill2d.tex then return end
    if not fill2d._scrollSpeed or fill2d._scrollSpeed <= 0 then return end
    -- Decale _scrollX au fil du temps
    local now = GetTime()
    local dt = (fill2d._lastScrollTime and (now - fill2d._lastScrollTime)) or 0
    fill2d._lastScrollTime = now
    fill2d._scrollX = (fill2d._scrollX or 0) + dt * fill2d._scrollSpeed
    if fill2d._scrollX > 1 then fill2d._scrollX = fill2d._scrollX - 1 end
    -- TexCoord : decale juste le coord X selon le scroll.
    local s = fill2d._scrollX
    fill2d.tex:SetTexCoord(s, s + 1, 0, 1)
end

-- Positionne le spark 3D sur le bord de la barre via fillTex:GetWidth() (non-secret)
local function UpdateSpark3DPos(bar, barWrap, sm, isReverse)
    if not sm or not sm.active then return end
    -- Si le spark 3D est ancre sur le spark 2D (cf. ShowSparkModel), il suit
    -- nativement via Blizzard. Pas besoin de repositionner ici.
    if barWrap and barWrap._spark2D then return end
    local fillTex = bar:GetStatusBarTexture()
    if not fillTex then return end
    local barW = bar:GetWidth()
    local fillW = fillTex:GetWidth()
    if not (barW and barW > 0 and fillW) then return end
    -- Cache : skip si la position n'a pas change depuis la frame precedente
    if sm._lastFillW == fillW and sm._lastBarW == barW and sm._lastReverse == isReverse then
        return
    end
    sm._lastFillW = fillW
    sm._lastBarW = barW
    sm._lastReverse = isReverse
    -- Position du bord : si reverse, le bord est a gauche (barW-fillW), sinon a droite (fillW)
    -- xOff est calcule depuis le LEFT du barWrap pour rester precis quel que soit le mode
    local xOff = isReverse and (barW - fillW) or fillW
    sm.model:ClearAllPoints()
    sm.model:SetPoint("CENTER", barWrap, "LEFT", xOff, 0)
end

-- Fait suivre clip 3D + spark 3D quand l'aura n'est plus visible côté scan (combat secret)
local function UpdateBarFX3DOnly(bar, barWrap, isReverse)
    if not (barWrap and bar) then return end
    -- Modes 3D barre (front et back) : maintenir l'ancrage du clip
    if barWrap._fx3dBar and barWrap._fx3dBar.active and barWrap._fx3dBar.clip then
        local bm = barWrap._fx3dBar
        local mode = bm._mode or "front"
        if mode == "front" or mode == "back" then
            pcall(UpdateClip3DPart, bar, barWrap, bm.clip, mode)
        end
    end
    -- Mode REMPLISSAGE (mid) : texture 2D qui suit le remplissage
    if barWrap._fx2dFill and barWrap._fx2dFill.active then
        pcall(UpdateFill2DPart, barWrap._fx2dFill)
    end
    -- Update du modele 3D spark si actif (suit le bord de la barre)
    if barWrap._fx3dSpark and barWrap._fx3dSpark.active then
        pcall(UpdateSpark3DPos, bar, barWrap, barWrap._fx3dSpark, isReverse)
    end
end

-- Anime la barre + spark + clip 3D pour une barre unique (top-level, évite alloc/tick)

-- Ancre le spark 2D sur le bord de la statusbar fill (idempotent)
function ns.AnchorSpark2D(spark, bar, isReverse, offY)
    if not spark or not bar then return end
    local fill = bar:GetStatusBarTexture()
    if not fill then return end
    offY = offY or 0
    if spark._ancoredReverse ~= isReverse or spark._ancoredOffY ~= offY then
        spark:ClearAllPoints()
        if isReverse then
            spark:SetPoint("CENTER", fill, "LEFT", 0, offY)
        else
            spark:SetPoint("CENTER", fill, "RIGHT", 0, offY)
        end
        spark._ancoredReverse = isReverse
        spark._ancoredOffY = offY
    end
end

local function AnimateOne(bar, spark, barWrap, entry, cR, cG, cB, isReverse, cfg, fx3dOn)
    -- pcall : AnimateBar peut crash sur durObj secret en combat (CDM)
    pcall(AnimateBar, bar, entry, cR, cG, cB, isReverse, cfg)
    ns.AnchorSpark2D(spark, bar, isReverse, cfg.sparkOffY or 0)
    if fx3dOn and barWrap and barWrap._fx3dBar and barWrap._fx3dBar.active and barWrap._fx3dBar.clip and bar then
        local bm = barWrap._fx3dBar
        local mode = bm._mode or "front"
        if mode == "front" or mode == "back" then
            pcall(UpdateClip3DPart, bar, barWrap, bm.clip, mode)
        end
    end
    -- Mode Remplissage (mid) : UpdateFill2DPart gère seulement le scrolling temporel
    if fx3dOn and barWrap and barWrap._fx2dFill and barWrap._fx2dFill.active and bar then
        pcall(UpdateFill2DPart, barWrap._fx2dFill)
    end
    -- Spark 3D suit le bord de la barre (même pattern pixel non-secret que le clip)
    if fx3dOn and barWrap and barWrap._fx3dSpark and barWrap._fx3dSpark.active and bar then
        pcall(UpdateSpark3DPos, bar, barWrap, barWrap._fx3dSpark, isReverse)
    end
end

local function AnimateRender(renderKey)
    local gfx = ns.renderFrames[renderKey]; if not gfx or not gfx.rows then return end
    local auras = ns.auraData and ns.auraData[renderKey] or {}
    -- Pas d'early-exit sur #auras==0 : en combat l'aura peut être secret côté scan
    -- mais le 3D doit continuer à suivre le remplissage (early-exit géré dans AnimateOne)
    local cfg = ns.db and ns.db[renderKey]; if not cfg then return end
    local hasAuras = (#auras > 0)
    -- Si aucune aura ET aucun fx3d barre actif sur ce render : skip vraiment.
    if not hasAuras and not (ns._fx3dBarActiveCount and ns._fx3dBarActiveCount > 0) then
        return
    end
    local isDual = (gfx.layout == "center_dual")
    local fx3dOn = ns.db and ns.EffectsActive()
    -- Pré-extraction : évite de relire ns.db/ns.barColor pour chaque barre à chaque tick.
    local useSpellColors = ns.db and ns.db.useSpellColors
    local defaultR, defaultG, defaultB = ns.barColor[1], ns.barColor[2], ns.barColor[3]
    -- Override couleur par render (menu BARRE) : appliqué à toutes les barres de ce render
    local overrideR, overrideG, overrideB
    if cfg.barColorR then
        overrideR = cfg.barColorR
        overrideG = cfg.barColorG or 0.5
        overrideB = cfg.barColorB or 0.2
    end

    if isDual then
        local aIdx = 1
        for _, row in ipairs(gfx.rows) do
            if not row:IsShown() then break end
            local aL = auras[aIdx]
            if aL then
                local cR, cG, cB = defaultR, defaultG, defaultB
                if useSpellColors and aL.spellColor then cR, cG, cB = aL.spellColor[1], aL.spellColor[2], aL.spellColor[3] end
                AnimateOne(row.barL, row.sparkL, row.wrapBarL, aL, cR, cG, cB, true, cfg, fx3dOn)
            elseif fx3dOn and row.barL and row.wrapBarL then
                -- Combat secret : barre animée côté C++, FX3D doit suivre quand même
                UpdateBarFX3DOnly(row.barL, row.wrapBarL, true)
            end
            local aR = auras[aIdx + 1]
            if aR and row.barR then
                local cR2, cG2, cB2 = defaultR, defaultG, defaultB
                if useSpellColors and aR.spellColor then cR2, cG2, cB2 = aR.spellColor[1], aR.spellColor[2], aR.spellColor[3] end
                AnimateOne(row.barR, row.sparkR, row.wrapBarR, aR, cR2, cG2, cB2, false, cfg, fx3dOn)
            elseif fx3dOn and row.barR and row.wrapBarR then
                UpdateBarFX3DOnly(row.barR, row.wrapBarR, false)
            end
            aIdx = aIdx + 2
        end
    else
        -- Overrides par sort (Buffs uniquement) via cfg.spellGradients — priorité: Init.lua ApplyBarColor
        local sgTable = (renderKey == "freebars") and cfg.spellGradients or nil
        for i, row in ipairs(gfx.rows) do
            if not row:IsShown() then break end
            local a = auras[i]
            if a then
                -- Cas normal : on a une aura, animation complete (couleur + spark + fx3d clip)
                local cR, cG, cB = defaultR, defaultG, defaultB
                if useSpellColors and a.spellColor then cR, cG, cB = a.spellColor[1], a.spellColor[2], a.spellColor[3] end
                if overrideR then cR, cG, cB = overrideR, overrideG, overrideB end
                if sgTable and a.spellID and sgTable[a.spellID] then
                    local sg = sgTable[a.spellID]
                    cR, cG, cB = sg[1] or cR, sg[2] or cG, sg[3] or cB
                end
                if row.barL and row.barR and row.barL ~= row.barR then
                    AnimateOne(row.barL, row.sparkL, row.wrapL, a, cR, cG, cB, true, cfg, fx3dOn)
                    AnimateOne(row.barR, row.sparkR, row.wrapR, a, cR, cG, cB, false, cfg, fx3dOn)
                elseif row.bar then
                    AnimateOne(row.bar, row.spark, row.wrap, a, cR, cG, cB, row._reverse, cfg, fx3dOn)
                elseif row.barL then
                    AnimateOne(row.barL, row.sparkL, row.wrapL, a, cR, cG, cB, false, cfg, fx3dOn)
                end
            elseif fx3dOn then
                -- Aura secret en combat mais barre animée côté C++ : le 3D doit suivre
                if row.barL and row.barR and row.barL ~= row.barR then
                    UpdateBarFX3DOnly(row.barL, row.wrapL, true)
                    UpdateBarFX3DOnly(row.barR, row.wrapR, false)
                elseif row.bar then
                    UpdateBarFX3DOnly(row.bar, row.wrap, row._reverse)
                elseif row.barL then
                    UpdateBarFX3DOnly(row.barL, row.wrapL, false)
                end
            end
        end
    end
end

-- TEXTE DE TIMER (ticker séparé 10fps, détaint, cache, dual)
-- Lit remaining duration ; vérifie issecretvalue avant l'arithmétique (CDM secret en combat)
local function ReadRemainingOnly(durObj)
    local r = durObj:GetRemainingDuration()
    if r ~= nil and not (HAS_ISSECRET and issecretvalue(r)) then
        return r + 0
    end
end

local function GetCleanRemaining(entry)
    if not entry then return nil end
    if entry.durObj then
        local ok, val = pcall(ReadRemainingOnly, entry.durObj)
        if ok and val then return val end
    end
    return nil
end

local function FormatTimerVal(rem, decimals)
    if not rem or rem <= 0 then return "" end
    if decimals and decimals == 0 then
        if rem < 60 then return string.format("%d", math.ceil(rem)) end
        return string.format("%d:%02d", math.floor(rem/60), math.floor(rem%60))
    end
    if rem < 10 then return string.format("%.1f", rem) end
    if rem < 60 then return string.format("%d", math.ceil(rem)) end
    return string.format("%d:%02d", math.floor(rem/60), math.floor(rem%60))
end

-- Contexte timer réutilisé entre ticks (évite alloc à 10fps × 3 renders)
local _ctxIcon = { tR=1, tG=1, tB=1, decimals=1 }

-- Texte + couleur d'urgence du timer pour un FontString
local function UpdTimer(fs, entry, ctx)
    if not fs then return end
    if not entry then
        if fs._lastText ~= "" then fs:SetText(""); fs._lastText = "" end
        fs:SetAlpha(1)
        return
    end
    local rem = GetCleanRemaining(entry)
    if rem and rem > 0 then
        local newText = FormatTimerVal(rem, ctx.decimals)
        if fs._lastText ~= newText then
            fs:SetText(newText); fs._lastText = newText
        end
        local tR, tG, tB = ctx.tR, ctx.tG, ctx.tB
        local CRIT = ns.URGENCY.CRITICAL or 2
        local MED  = ns.URGENCY.MEDIUM or 5
        if rem >= MED then
            fs:SetTextColor(tR, tG, tB, 0.9)
        elseif rem >= CRIT then
            local t = (rem - CRIT) / (MED - CRIT)
            local oR, oG, oB = 1, 0.7, 0.3
            fs:SetTextColor(oR + (tR - oR) * t, oG + (tG - oG) * t, oB + (tB - oB) * t, 0.9)
        else
            local t = math.max(0, rem) / CRIT
            local oR, oG, oB = 1, 0.7, 0.3
            local cR_, cG_, cB_ = 1, 0.3, 0.3
            fs:SetTextColor(cR_ + (oR - cR_) * t, cG_ + (oG - cG_) * t, cB_ + (oB - cB_) * t, 0.9)
        end
        fs:SetAlpha(1)
    else
        if fs._lastText ~= "" then fs:SetText(""); fs._lastText = "" end
        fs:SetAlpha(1)
    end
end

-- Met à jour le timer d'une row simple (FontString sur icône ou directement sur la row)
local function UpdRow(row, entry, timerIconOn, ctx)
    local ib = row._isDual and nil or row.iconBtn
    local fs = (ib and ib._durText) or row._durText
    if fs then
        if timerIconOn ~= false then
            UpdTimer(fs, entry, ctx)
        else
            if fs._lastText ~= "" then fs:SetText(""); fs._lastText = "" end
            fs:SetAlpha(0)
        end
    end
end

local function UpdateTimersForRender(renderKey)
    local gfx = ns.renderFrames[renderKey]; if not gfx or not gfx.rows then return end
    local auras = ns.auraData and ns.auraData[renderKey] or {}
    -- Early-exit : si pas d'auras dans ce render, rien à mettre à jour.
    if #auras == 0 then return end
    local cfg = ns.db and ns.db[renderKey]; if not cfg then return end
    local isDual = (gfx.layout == "center_dual")
    local timerIconOn = cfg.timerIconEnabled

    -- Mise à jour de la table contexte réutilisée (pas d'alloc par tick)
    _ctxIcon.tR = cfg.timerColorR or 1
    _ctxIcon.tG = cfg.timerColorG or 1
    _ctxIcon.tB = cfg.timerColorB or 1
    _ctxIcon.decimals = cfg.timerDecimals or 1

    if isDual then
        local aIdx = 1
        for _, row in ipairs(gfx.rows) do
            if not row:IsShown() then break end
            -- Left side icon timer
            if row.iconBtnL and row.iconBtnL._durText then
                if timerIconOn ~= false then
                    UpdTimer(row.iconBtnL._durText, auras[aIdx], _ctxIcon)
                else
                    row.iconBtnL._durText:SetText(""); row.iconBtnL._durText._lastText = ""
                    row.iconBtnL._durText:SetAlpha(0)
                end
            end
            -- Right side icon timer
            if row.iconBtnR and row.iconBtnR._durText then
                if timerIconOn ~= false then
                    UpdTimer(row.iconBtnR._durText, auras[aIdx + 1], _ctxIcon)
                else
                    row.iconBtnR._durText:SetText(""); row.iconBtnR._durText._lastText = ""
                    row.iconBtnR._durText:SetAlpha(0)
                end
            end
            aIdx = aIdx + 2
        end
    else
        for i, row in ipairs(gfx.rows) do
            if not row:IsShown() then break end
            UpdRow(row, auras[i], timerIconOn, _ctxIcon)
        end
    end
end

-- OnUpdate 60fps auto-détaché quand inactif (zéro overhead idle), réveillé par ns.WakeAnimDriver()
animDriver._running = false

local function AnimDriverTick(self, elapsed)
    self._t = self._t + elapsed
    if self._t < 0.0166 then return end  -- 60fps
    self._t = 0
    -- Continue d'animer si un fx3d barre actif même sans aura visible (secret en combat) ;
    -- ns._fx3dBarActiveCount géré par ShowBarModel/HideBarModel (SpellEffects.lua)
    local hasActiveAuras = (ns._activeAuraCount or 0) > 0
    local hasActiveFx3d = (ns._fx3dBarActiveCount or 0) > 0
    -- Mode preview (ns._previewBars) ne passe pas par Scan.lua : garde nécessaire
    -- sinon le driver s'arrête et le spark de la fausse barre reste invisible.
    local hasPreview = ns._previewBars == true
    if not hasActiveAuras and not hasActiveFx3d and not hasPreview then
        self._running = false
        self:SetScript("OnUpdate", nil)
        return
    end
    for i = 1, #RENDER_KEYS do pcall(AnimateRender, RENDER_KEYS[i]) end
end

function ns.WakeAnimDriver()
    if not animDriver._running then
        animDriver._running = true
        animDriver._t = 0
        animDriver:SetScript("OnUpdate", AnimDriverTick)
    end
end

-- Timer texte 10fps, OnUpdate auto-détaché quand inactif, réveillé par ns.WakeTimerDriver()
local timerDriver = CreateFrame("Frame")
timerDriver._t = 0
timerDriver._running = false

local function TimerDriverTick(self, elapsed)
    self._t = self._t + elapsed
    if self._t < 0.1 then return end
    self._t = 0
    for i = 1, #RENDER_KEYS do pcall(UpdateTimersForRender, RENDER_KEYS[i]) end

    -- Pas de check expiry manuel (GetRemainingDuration secret en combat) : Blizzard
    -- gère l'expiration côté C++, notre scan réagit à UNIT_AURA.removedAuraInstanceIDs
end

function ns.WakeTimerDriver()
    if not timerDriver._running then
        timerDriver._running = true
        timerDriver._t = 0
        timerDriver:SetScript("OnUpdate", TimerDriverTick)
    end
end

-- Démarre endormi ; ScanAuras() réveille via WakeAnimDriver()/WakeTimerDriver()

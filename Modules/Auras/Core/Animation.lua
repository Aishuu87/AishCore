-- AishUIAura/Core/Animation.lua
-- Driver de fade, boucle d'animation (60 fps), ticker du texte de timer (10 fps).
-- Contient tout le travail OnUpdate qui tourne par frame en combat.
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local CreateFrame, C_Timer, GetTime = CreateFrame, C_Timer, GetTime
local pcall, ipairs, math, string = pcall, ipairs, math, string
local HAS_ISSECRET = (type(issecretvalue) == "function")

-- Table pré-construite des render keys, réutilisée par toutes les boucles chaudes
-- (UpdateAllFades, animDriver OnUpdate, timerDriver OnUpdate). Évite la création
-- d'une nouvelle table à chaque tick. Ordre : debuffs / buffs / cooldowns / procs
-- (cohérent avec l'ordre des sections dans MES SORTS).
local RENDER_KEYS = {"iconlist", "freebars", "circlebars", "icons"}

------------------------------------------------------------------------
-- FADE (ticker 60 fps temporaire, auto-Cancel)
------------------------------------------------------------------------
local activeFades = {}
local activeFadeCount = 0
local function EaseOutCubic(t) t = t - 1; return t*t*t + 1 end

function ns.FadeTo(frame, targetAlpha, duration, delay)
    if not frame then return end
    duration = duration or 0.35; delay = delay or 0

    -- En combat : SetAlpha direct, pas de fade, pour réactivité maximale au tab target.
    -- (Le fade 60fps progressif n'est utilisé qu'hors combat.)
    if ns._inCombat then
        if activeFades[frame] then
            activeFades[frame]:Cancel()
            activeFades[frame] = nil
            activeFadeCount = math.max(0, activeFadeCount - 1)
        end
        frame:SetAlpha(targetAlpha)
        return
    end

    -- Anti-clignotement : si une fade est déjà en cours VERS la même target, on la
    -- laisse continuer au lieu de la canceller/redémarrer à chaque scan. Sinon on
    -- perdait la progression et l'alpha faisait des micro-saccades sous AoE.
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
    ticker = C_Timer.NewTicker(0.016, function()
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

function ns.UpdateRenderFade(renderKey)
    local cfg = ns.db and ns.db[renderKey]; if not cfg then return end
    local frames = ns.renderFrames[renderKey]; if not frames or not frames.container then return end
    -- combatOnly : si vrai, le container est totalement cache hors combat (alpha 0).
    -- Utilise par le render Buffs notamment, pour ne pas polluer l'UI hors combat.
    --
    -- EXCEPTION mode preview : si la fake bar est active sur ce render, on force la
    -- visibilite a 1.0. Sinon le combatOnly cacherait toute la barre 2D + spark
    -- (le modele 3D bar reste visible car PlayerModel ne propage pas l'alpha parent,
    -- ce qui creait une asymetrie visuelle entre les renders).
    local previewActiveHere = ns._previewBars and (ns._previewMode == "all" or ns._previewMode == renderKey)
    local target
    if previewActiveHere then
        target = 1.0
    elseif cfg.combatOnly and not ns._inCombat then
        target = 0
    else
        target = ns._inCombat and (cfg.fadeIC or 1.0) or (cfg.fadeOOC or 0.4)
    end
    local delay = ns._inCombat and (cfg.fadeDelayIC or 0) or (cfg.fadeDelayOOC or 0)
    -- En combat : fade très court (0.05s) pour une réactivité maximale au
    -- tab target, équivalent à l'instantané ElvUI. Hors combat : durée complète
    -- (0.35s par défaut) pour garder le transitions douces du combat → OOC.
    local duration = ns._inCombat and 0.05 or (cfg.fadeDuration or 0.35)
    ns.FadeTo(frames.container, target, duration, delay)

    -- FIX combatOnly : quand le container est cache (target=0), il faut cacher
    -- MANUELLEMENT les modeles 3D bar (PlayerModel) des rows actives. Le PlayerModel
    -- ne propage pas l'alpha de son parent automatiquement (quirk Blizzard), donc il
    -- reste visible alors que la barre 2D disparait.
    --
    -- Important : on NE FAIT PAS de Show() ici quand target>0. Le Show des clips
    -- 3D est de la responsabilite de ShowBarModel (appele par les renders quand une
    -- aura est active). Faire Show ici reviendrait a reveiller des clips orphelins
    -- qui appartenaient a des rows non-actives -> PlayerModels visibles a l'ecran
    -- sans barre/icone associee (bug observe a la fermeture du menu /aa).
    if frames.rows and target == 0 then
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

------------------------------------------------------------------------
-- DEFER HIDE ROW — pattern anti-flicker
-- Au lieu de cacher instantanément une row vide, on programme un hide dans 100ms.
-- Si la row redevient active entre-temps (refresh de debuff rapide type Rip/Rake),
-- on annule le pending hide → aucun flash visible.
--
-- Usage côté Update(row) :
--   Row active   → ns.CancelDeferredHide(row); row:SetAlpha(1)
--   Row inactive → ns.DeferHideRow(row, 0.1)  -- ne cache que si toujours inactive dans 100ms
--
-- Note : on utilise SetAlpha au lieu de Hide() pour garder la row dans la hiérarchie
-- (comme dans nos corrections précédentes). Les rows deviennent juste transparentes.
------------------------------------------------------------------------

-- Programme un Hide() différé de `delay` secondes. Si la row est rendue active
-- avant, appelle CancelDeferredHide pour annuler.
-- Pourquoi Hide() et pas SetAlpha(0) : le Hide() trigger le HookScript("OnHide")
-- sur les bars enfants qui reset _timerMode. Sans ça, la barre Blizzard continue
-- d'animer avec l'ancien durObj même après disparition de l'aura.
function ns.DeferHideRow(row, delay)
    if not row then return end
    if row._aishHidePending then return end
    row._aishHidePending = true
    C_Timer.After(delay or 0.1, function()
        if row._aishHidePending then
            row._aishHidePending = nil
            -- Double-check : si la row a été rendue active entre-temps, on ne hide pas
            if row._aishActiveNow then return end
            -- Cleanup pop anim : reset l'instID tracke (pour que la prochaine apparition
            -- declenche une nouvelle anim) et stoppe l'anim en cours si elle tourne encore.
            row._popInstID = nil
            if ns.StopPopAnim then ns.StopPopAnim(row) end
            -- Cleanup FX3D explicite : sans ca, le PlayerModel reste visible
            -- meme apres row:Hide() (quirk Blizzard - PlayerModel ne propage pas
            -- toujours Hide() de son parent). Cas d'usage : decochage d'un sort
            -- dans la liste de tracking pendant que l'aura est encore active.
            -- Chaque render (Debuffs, Cooldowns, Procs, Buffs) enregistre son
            -- propre cleanup via row._aishHideCleanup pour garder la separation
            -- des couches (Animation.lua ne connait pas la structure des FX3D).
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

------------------------------------------------------------------------
-- ANIMATION D'APPARITION ("pop") — helper generique reutilisable.
-- Animation :
--   - scale horizontal : SetWidth des wraps de 1px → targetW
--   - alpha fade-in    : SetAlpha des wraps de 0 → targetAlpha (optionnel)
--   - easing easeOutIn (lent debut/fin, vif milieu) avec strength configurable
--
-- L'ancrage des wraps determine la direction de deploiement (la frame d'ancrage
-- reste fixe, la wrap croit a partir de l'ancre). Donc :
--   - Wrap ancre LEFT a X     → deploie vers la droite depuis X
--   - Wrap ancre RIGHT a X    → deploie vers la gauche depuis X
--
-- Parametres lus dans cfg :
--   cfg.popEnabled      (default true)  : on/off de l'animation
--   cfg.popDuration     (default 1.0)   : duree en secondes
--   cfg.popEaseStrength (default 5)     : intensite easeOutIn (1-12)
--   cfg.popAlphaFade    (default true)  : on/off du fade-in alpha
--
-- Si popEnabled=false : on saute direct a l'etat final (pas d'animation).
-- Le ticker s'auto-stoppe en fin d'anim. Si la row redevient inactive avant
-- la fin, appeler ns.StopPopAnim(row) pour cleanup.
------------------------------------------------------------------------
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
            -- Cache le PlayerModel 3D pendant l'anim pop (PlayerModel ne suit
            -- pas le SetAlpha parent automatiquement, donc il resterait visible
            -- alors que la barre statusbar est invisible -> visuel bizarre)
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
        -- Easing easeOut : départ rapide, décélération douce jusqu'à 100%.
        -- L'ancien easeOutIn créait deux phases perceptibles : expansion rapide
        -- jusqu'à ~50%, quasi-pause au milieu, puis reprise — visuellement moche.
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

-- Stoppe une animation pop en cours et reset les wraps a l'etat final (si
-- resetW fourni). A appeler quand une row redevient inactive avant la fin
-- de l'anim, sinon le ticker continuerait jusqu'a la fin.
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

------------------------------------------------------------------------
-- DRIVER D'ANIMATION (pattern motor : OnUpdate 20 fps, AnimateBar dual-path)
------------------------------------------------------------------------
local animDriver = CreateFrame("Frame")
animDriver._t = 0

------------------------------------------------------------------------
-- DÉTECTION DES APIs MODERNES (Midnight 12.x)
-- SetTimerDuration existe sur StatusBar depuis Midnight. Si présent → Blizzard
-- anime la barre en interpolation frame-perfect (60fps natif). Sinon fallback.
------------------------------------------------------------------------
local HAS_TIMER_DURATION = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection) and true or false
local INTERP_SMOOTH    = HAS_TIMER_DURATION and Enum.StatusBarInterpolation.ExponentialEaseOut or nil
local INTERP_IMMEDIATE = HAS_TIMER_DURATION and Enum.StatusBarInterpolation.Immediate or nil
local TIMER_DIR_DRAIN  = HAS_TIMER_DURATION and Enum.StatusBarTimerDirection.RemainingTime or nil

-- Clé d'identification d'une aura. Doit CHANGER au refresh pour que SetTimerDuration
-- soit relancé avec le nouveau durObj. Combine 3 signaux :
--   1. auraInstanceID : stable, non-secret
--   2. ns._refreshCounter[instID] : incrémenté par UNIT_AURA.updatedAuraInstanceIDs
--      (événement Blizzard, 100% non-secret). C'est notre source principale de
--      détection de refresh en combat quand les valeurs d'aura sont secret.
--   3. tostring(entry.durObj) : fallback pour les cas où refreshCounter n'existe pas
--      (première fois qu'on voit l'aura, avant qu'UNIT_AURA ne fire). Peut être
--      "LuaDurationObject: 0" constant en Midnight mais reste utile comme fallback.
local function GetAuraKey(entry)
    if not entry then return nil end
    local inst = entry.auraInstanceID or entry.instID
    local durRef = entry.durObj and tostring(entry.durObj) or ""
    local refreshCnt = (inst and ns._refreshCounter and ns._refreshCounter[inst]) or 0
    -- Le durRef reste dans la clé pour trigger un SetTimerDuration quand Blizzard
    -- recrée le durObj (sinon la barre continue de pointer vers un userdata potentiellement
    -- invalide). Mais AnimateBar distingue ces cas (voir logique _StartTimerMode).
    if inst then return "i:" .. tostring(inst) .. ":" .. refreshCnt .. ":" .. durRef end
    if entry.spellID then
        return "s:" .. tostring(entry.spellID) .. ":" .. tostring(entry.unit or "?") .. ":" .. refreshCnt .. ":" .. durRef
    end
    return nil
end

-- Helper : extrait (instID, refreshCnt) d'un auraKey format "i:<inst>:<cnt>:<ref>"
-- Utilisé pour distinguer un vrai refresh (refreshCnt change) d'une simple
-- recréation durObj Blizzard (seul durRef change) → évite l'interp parasite.
local function _ExtractKeyParts(auraKey)
    if not auraKey then return nil, nil end
    local inst, cnt = auraKey:match("^i:([^:]+):([^:]+):")
    if inst then return inst, cnt end
    -- Format spellID fallback : "s:<spellID>:<unit>:<cnt>:<ref>"
    local sid, unit, cnt2 = auraKey:match("^s:([^:]+):([^:]+):([^:]+):")
    if sid then return sid .. "@" .. unit, cnt2 end
    return nil, nil
end

-- Arrête le mode timer natif Blizzard et restaure la barre en mode SetValue manuel.
-- Appelé quand l'aura change (nouveau spellID sur la même row) ou quand elle disparaît.
-- Helper top-level pour éviter la création d'une closure à chaque StopTimerMode.
local function _StopTimerApply(bar)
    bar:SetMinMaxValues(0, 1, INTERP_IMMEDIATE)
    bar:SetValue(bar:GetValue() or 0, INTERP_IMMEDIATE)
end

local function StopTimerMode(bar)
    if not bar then return end
    if bar._timerMode then
        -- Neutralise l'animation Blizzard : on lui donne une durée 0 terminée.
        -- Blizzard n'offre pas de ClearTimerDuration, on doit retomber sur SetValue.
        -- Immediate pour éviter l'interpolation implicite qui pourrait ajouter
        -- une transition visuelle non désirée.
        pcall(_StopTimerApply, bar)
        bar._timerMode = false
        bar._timerKey = nil
    end
end

-- Enregistre (une fois) un hook OnHide sur la barre pour que le mode timer Blizzard
-- soit automatiquement réinitialisé quand la barre devient invisible.
-- Cleanup event-driven : pas besoin de polling pour détecter les auras expirées.
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

------------------------------------------------------------------------
-- COULEUR D'URGENCE — PERCENTAGE-BASED avec COLOR CURVE NATIVE BLIZZARD
------------------------------------------------------------------------
-- Système à deux chemins :
--
--   CHEMIN PRIMAIRE (C_CurveUtil disponible + durObj) :
--     On construit une color curve Blizzard en pourcentage (0..1) par couleur de base.
--     Blizzard évalue la curve via durObj:EvaluateRemainingPercent() → ColorMixin.
--     Résultat appliqué via SetStatusBarColor qui accepte les secret values.
--     → 100% secret-safe, aucune lecture en Lua, dégradé parfait.
--
--   CHEMIN FALLBACK (pas de curve ou pas de durObj) :
--     Interpolation manuelle en secondes absolues (garde le comportement existant).
--
-- Seuils en POURCENTAGE du restant total :
--   > 50%        : couleur normale
--   50% → 20%    : dégradé normal → orange
--   20% → 0%     : dégradé orange → rouge
--
-- Ces seuils en % sont plus sensés que les seuils en secondes absolues :
--   - Un buff de 3s devient "critical" à 1.5s restant (proche de la fin)
--   - Un buff de 60s devient "critical" à 12s restant (urgence proportionnelle)

local HAS_CURVE_UTIL = (C_CurveUtil and C_CurveUtil.CreateColorCurve) and true or false
local curveCache = {}  -- [keyHex] = curve object

-- Wipe le cache quand l'utilisateur change les couleurs d'urgence.
-- Appelé depuis les menus Render via SharedWidgets.
function ns.InvalidateUrgencyCurves()
    wipe(curveCache)
end

-- Construit (ou récupère du cache) une color curve Blizzard.
-- Arguments :
--   cR,cG,cB    = couleur de base (celle du sort)
--   mR,mG,mB    = couleur medium (seuil 20%) — optionnel, défaut orange
--   crR,crG,crB = couleur critical (seuil 0%) — optionnel, défaut rouge
local function GetOrBuildCurve(cR, cG, cB, mR, mG, mB, crR, crG, crB)
    if not HAS_CURVE_UTIL then return nil end
    if not cR then return nil end

    -- Defaults si couleurs urgence non fournies
    mR = mR or 1.0;  mG = mG or 0.5;  mB = mB or 0.0
    crR = crR or 1.0; crG = crG or 0.15; crB = crB or 0.05

    -- Clé de cache : packed des 3 couleurs (base + medium + critical)
    -- Précision 1/255 suffisante. Si l'utilisateur change medium ou critical dans
    -- les menus, InvalidateUrgencyCurves vide tout le cache, donc la clé n'a pas
    -- besoin d'être parfaitement unique sur les très petites variations.
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

    -- IMPORTANT : ordre CROISSANT des points (0.0 → 1.0) comme l'exemple Blizzard.
    -- EvaluateRemainingPercent retourne 0.0 quand l'aura expire, 1.0 quand elle
    -- vient d'être appliquée. Donc on map :
    --   0.00 = fin d'aura    → rouge critique
    --   0.20 = bientôt fin   → orange medium
    --   0.50 = mi-durée      → base
    --   1.00 = début d'aura  → base
    -- SetType Linear : Blizzard interpole lissement entre les points.
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

-- Helper top-level : évalue une curve et applique la couleur sur bar.
-- Hoist pour éviter closure à chaque frame (appelé 60fps × N barres).
-- Peut lever si durObj tainted, d'où le pcall autour de l'appel.
local function EvaluateCurveAndApply(durObj, curve, bar)
    local colorResult = durObj:EvaluateRemainingPercent(curve)
    if colorResult then
        bar:SetStatusBarColor(colorResult:GetRGB())
    end
end

-- Applique la couleur d'urgence à une barre.
-- Si durObj + curve disponibles → utilise le chemin natif Blizzard (secret-safe).
-- Sinon → fallback interpolation manuelle en secondes absolues.
-- Arguments :
--   cfg = config du render (ns.db[renderKey]) pour lire urgencyEnabled + couleurs
local function ApplyUrgencyColor(bar, entry, cR, cG, cB, remSeconds, cfg)
    if not cR then return end

    -- BYPASS : si la barre a un gradient par sort actif (cf. Init.lua ApplyBarColor),
    -- on ne touche PAS sa couleur. Le SetGradient applique sur la texture serait
    -- ecrase par SetStatusBarColor. Le gradient reste valable pendant toute la duree
    -- de l'aura sans variation d'urgence.
    if bar._spellGradientActive then return end

    -- v281 Q2 FIX : meme principe pour le gradient PAR RENDER (cfg.gradientEnabled).
    -- Sans cette garde, ApplyUrgencyColor ecrase le SetGradient a 60fps via
    -- SetStatusBarColor et le degrade ne s'affiche jamais visuellement.
    if cfg and cfg.gradientEnabled then return end

    -- Si la curve d'urgence est désactivée pour ce render : on applique juste
    -- la couleur de base du sort sans animer la teinte.
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

-- AnimateBar : moteur d'animation des barres de durée
-- Pattern "show but don't know" pour les auras dont les valeurs deviennent
-- secret en combat (Bone Shield, Frenzy, Soul Reaper, etc.) :
-- on passe les retours du Duration Object Blizzard DIRECTEMENT à SetMinMaxValues/SetValue
-- sans jamais les lire en Lua. Blizzard sait afficher ces valeurs même si l'addon
-- n'a pas le droit de les connaître.
--
-- ARCHITECTURE À 2 TIERS (ordre de priorité, CDM-only depuis v281) :
--   Tier 0 : SetTimerDuration(durObj) — Blizzard anime à 60fps, on ne touche plus la barre
--   Tier 1 : SetMinMaxValues + SetValue depuis durObj — fallback si SetTimerDuration absent
-- Helpers top-level pour AnimateBar (appelé à 60fps par barre).
-- Chaque pcall-closure qui capturait des locales est maintenant une fonction
-- top-level qui reçoit ses arguments explicitement → zéro alloc par tick.

local function _StartTimerMode(bar, durObj, isFirstLaunch)
    -- IMPORTANT : SetMinMaxValues accepte aussi un argument d'interpolation.
    -- Si on ne le passe pas, Blizzard utilise Immediate par défaut, MAIS si
    -- la barre avait une valeur précédente (ancienne aura), le passage 0→1
    -- peut déclencher une interpolation visuelle implicite.
    -- On force Immediate explicitement pour éliminer toute interpolation résiduelle.
    local interp = isFirstLaunch and INTERP_IMMEDIATE or INTERP_SMOOTH
    bar:SetMinMaxValues(0, 1, interp)
    -- Interpolation Immediate au premier lancement d'une barre (apparition) :
    -- la barre s'affiche INSTANTANÉMENT à sa valeur correcte, pas d'interpolation
    -- depuis 0 ou depuis l'ancienne valeur. C'est ce qui donne la sensation
    -- "instantanée" qu'ElvUI/oUF/ABE ont au tab target.
    --
    -- Interpolation Smooth (ExponentialEaseOut) aux changements d'aura (refresh
    -- de DOT) : transition douce de l'ancien fill vers le nouveau, visuellement
    -- agréable quand un DOT se refresh à pleine durée.
    bar:SetTimerDuration(durObj, interp, TIMER_DIR_DRAIN)
end

local function _ApplyTier1SetValue(bar, durObj)
    -- Tier 1 : force Immediate pour éviter l'interpolation implicite par défaut
    -- sur SetValue (nouvelle API Midnight 12.0 où SetValue peut interpoler).
    bar:SetMinMaxValues(0, durObj:GetTotalDuration(), INTERP_IMMEDIATE)
    bar:SetValue(durObj:GetRemainingDuration(), INTERP_IMMEDIATE)
end

local function AnimateBar(bar, entry, cR, cG, cB, isReverse, cfg)
    if not bar then return end

    -- Cleanup event-driven : enregistre (idempotent) un hook OnHide sur la barre
    -- pour sortir automatiquement du mode timer quand elle devient invisible.
    EnsureHideHook(bar)

    -- TIER PREVIEW : fake bar (mode preview du menu Effets).
    -- Pas de durObj reel : on simule un cycle 12s en boucle pour que l'utilisateur
    -- puisse visualiser les FX (couleur, gradient, spark, fx3d clip, etc.) sans
    -- avoir l'aura active sur la cible.
    --
    -- On utilise SetMinMaxValues + SetValue en Lua (pas SetTimerDuration) car :
    --   1. SetTimerDuration prend un durObj Blizzard, pas un timer Lua
    --   2. La boucle se reset toutes les 12s (cycle perpetuel)
    --   3. Le clip 3D et le spark suivent naturellement via fillTex (pixels)
    if entry._isPreview then
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

    local auraKey = GetAuraKey(entry)

    -- TIER 0 : Mode timer natif Blizzard (priorité maximale si API dispo + durObj)
    -- On ne lance SetTimerDuration qu'UNE FOIS par aura (au premier tick ou au refresh).
    -- Aux ticks suivants, la barre s'anime toute seule et on ne fait QUE la couleur.
    --
    -- NOTE sur la direction : on utilise TOUJOURS RemainingTime (la barre se vide avec le
    -- temps qui reste). L'INVERSION VISUELLE est gérée par SetReverseFill() sur la bar
    -- elle-même, posé à la création (MakeBarWrap). Pour les debuffs en layout mirror :
    --   - barL a SetReverseFill(true)  → se vide vers la droite (vers l'icône à droite)
    --   - barR a SetReverseFill(false) → se vide vers la gauche (vers l'icône à gauche)
    -- Les deux "drainent" (RemainingTime) — seule l'orientation visuelle diffère.
    if HAS_TIMER_DURATION and entry.durObj and auraKey then
        if not bar._timerMode or bar._timerKey ~= auraKey then
            -- 4 cas possibles :
            -- 1. Barre jamais utilisée (pas de timer mode) → Immediate (apparition)
            -- 2. Nouvelle aura différente (instID change, ex: tab target) → Immediate
            -- 3. Recast de la même aura (refreshCounter++) → Smooth (refresh visuel)
            -- 4. Recréation silencieuse du durObj (même inst, même cnt, durRef change)
            --    → Immediate (pas un vrai refresh, juste Blizzard qui recrée l'objet)
            --
            -- Cas 4 arrive notamment post-tab target : Blizzard peut fire
            -- plusieurs UNIT_AURA avec de nouveaux durObj pour la même aura,
            -- sans incrémenter ses propres compteurs. Sans ce fix, la barre
            -- re-interpolait 200ms après le tab → délai visuel perçu.
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

        -- Couleur d'urgence via color curve native (100% secret-safe).
        -- Plus besoin de lire r/t en Lua : Blizzard évalue la curve à partir du durObj.
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

    -- Aucun chemin Tier 0/1 n'a fonctionne : la barre n'a ni durObj utilisable
    -- ni Duration Object animable. On sort proprement du mode timer si on y etait.
    -- En CDM-only, ce cas n'arrive normalement pas (toutes les auras passent par
    -- GetAuraDuration qui fournit un durObj), mais on garde le filet de securite.
    if bar._timerMode then StopTimerMode(bar) end
end

-- Helper top-level : positionne le clip 3D barre selon le mode utilisateur.
--
-- PATTERN COMBAT-AWARE :
-- On utilise SetAllPoints sur la cible appropriee selon le mode. Le clip suit
-- automatiquement, sans aucun calcul Lua sur les pixels. Fonctionne meme en
-- combat sur sorts CDM ou bar:GetWidth() peut etre secret.
--
-- Mode "front" (Fond) :
--   Clip ancre sur barWrap (taille fixe pleine largeur).
--
-- Mode "back" (Remplissage 3D) :
--   Clip ancre sur bar:GetStatusBarTexture() (le rectangle anime nativement
--   par Blizzard via SetTimerDuration). Le clip retrecit avec la barre, le
--   modele 3D ancre sur barWrap est progressivement rogne par le clip.
--
-- On re-pose les ancres si necessaire (cout quasi nul) pour gerer les cas
-- ou Blizzard recreerait la statusbar texture en cours de combat.
local function UpdateClip3DPart(bar, barWrap, clip, mode)
    if not clip then return end
    if mode == "front" then
        -- Mode Fond : clip suit barWrap (taille fixe), modele visible derriere
        clip:ClearAllPoints()
        clip:SetAllPoints(barWrap)
    elseif mode == "back" and bar and bar.GetStatusBarTexture then
        -- Mode Remplissage 3D : clip ancre sur fillRect (rectangle de remplissage
        -- de la statusbar, anime par SetTimerDuration cote C++). Le modele 3D
        -- enfant du clip est rogne par les bords du clip via SetClipsChildren.
        -- Ancrage SetPoint = pas de calcul, pas de lecture secret, suit
        -- pixel-precis. Combat-safe.
        local fillRect = bar:GetStatusBarTexture()
        if fillRect and clip._anchoredFillRect ~= fillRect then
            clip:ClearAllPoints()
            clip:SetAllPoints(fillRect)
            clip._anchoredFillRect = fillRect
        end
    end
end

-- Helper top-level : applique le scrolling temporel sur une texture Fill 2D.
--
-- La GEOMETRIE (largeur, position, hauteur) est entierement geree par l'ancrage
-- SetAllPoints(bar:GetStatusBarTexture()) fait dans ShowFill2D. Ce rectangle
-- de remplissage est anime cote C++ Blizzard via SetTimerDuration : la texture
-- ancree dessus suit naturellement le retrecissement de la barre.
--
-- Pattern combat-aware : ZERO calcul Lua sur des valeurs potentiellement secret.
-- C'est Blizzard qui anime tout cote moteur natif.
--
-- Cette fonction ne sert qu'au scrolling temporel pour les textures animees
-- (FillFlamme, FillEau, FillPlasma, etc.). Si scrollSpeed = 0, elle ne fait
-- rien (return immediat) → cout CPU quasi nul pour les textures statiques.
local function UpdateFill2DPart(fill2d)
    if not fill2d or not fill2d.tex then return end
    -- Pas de scroll demande : skip total (texture statique, rien a animer)
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

-- Variante allegee : appelle UNIQUEMENT UpdateClip3DPart pour les barres dont
-- l'aura n'est plus visible cote scan (combat, valeur secret) mais dont le
-- fx3d barre est encore actif. Permet au modele 3D de continuer a suivre le
-- remplissage que Blizzard anime cote C++ via SetTimerDuration.
--
-- Pas d'AnimateBar (couleur, urgence) car sans entry on n'a pas de durObj.
-- Helper top-level : positionne le modele 3D du spark sur le bord de la barre.
-- Pattern "show but don't know" applique a la geometrie : on lit fillTex:GetWidth()
-- (mesure pixels en C++ Blizzard, NON-secret) au lieu d'un pct calcule depuis
-- expirationTime (secret en combat sur sorts CDM Midnight 12.0).
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

-- Variante allegee : appelle UNIQUEMENT UpdateClip3DPart pour les barres dont
-- l'aura n'est plus visible cote scan (combat, valeur secret) mais dont le
-- fx3d barre est encore actif. Permet au modele 3D de continuer a suivre le
-- remplissage que Blizzard anime cote C++ via SetTimerDuration.
--
-- Pas d'AnimateBar (couleur, urgence) car sans entry on n'a pas de durObj.
-- Juste le clip 3D et le spark 3D qui doivent suivre la geometrie.
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

-- Anime la barre + le spark + le clip 3D pour une barre unique.
-- Hoist en top-level pour éviter l'allocation de closure à chaque tick du
-- animDriver (60fps × 3 renders). Reçoit cfg et fx3dOn en paramètres.

-- Helper expose : ancre le spark 2D sur le bord de la statusbar fill.
-- Idempotent : skip si deja ancre dans la meme orientation/offset (cache).
-- Extracte de AnimateOne pour pouvoir etre appele en dehors du animDriver
-- si besoin (par exemple pre-positionnement avant ShowSparkModel).
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
    -- AnimateBar peut crash silencieusement sur des sorts CDM en combat (lecture
    -- de durObj qui devient secret value). On l'enveloppe dans un pcall pour que
    -- son crash n'empeche pas la suite (spark anchor, FX3D, Fill 2D, etc.).
    pcall(AnimateBar, bar, entry, cR, cG, cB, isReverse, cfg)
    -- Étape 2 : le spark suit le remplissage de la barre.
    -- Ancrage maintenu par ns.AnchorSpark2D (idempotent - skip si deja ancre).
    ns.AnchorSpark2D(spark, bar, isReverse, cfg.sparkOffY or 0)
    -- Étape 4 : modes 3D barre (front et back).
    -- Pour les deux modes, UpdateClip3DPart maintient l'ancrage du clip selon
    -- la cible appropriee (barWrap pour front, fillRect pour back).
    if fx3dOn and barWrap and barWrap._fx3dBar and barWrap._fx3dBar.active and barWrap._fx3dBar.clip and bar then
        local bm = barWrap._fx3dBar
        local mode = bm._mode or "front"
        if mode == "front" or mode == "back" then
            pcall(UpdateClip3DPart, bar, barWrap, bm.clip, mode)
        end
    end
    -- Étape 4b : Mode REMPLISSAGE (mid) — texture 2D qui se tronque avec la barre.
    -- L'ancrage SetAllPoints fait dans ShowFill2D fait suivre la texture
    -- automatiquement. UpdateFill2DPart ne sert que pour le scrolling temporel
    -- des textures animees (FillFlamme, etc.).
    if fx3dOn and barWrap and barWrap._fx2dFill and barWrap._fx2dFill.active and bar then
        pcall(UpdateFill2DPart, barWrap._fx2dFill)
    end
    -- Étape 5 : modèle 3D du spark suit le bord de la barre (en combat aussi).
    -- Meme pattern que le clip 3D : lecture pixels via fillTex:GetWidth() (non-secret).
    if fx3dOn and barWrap and barWrap._fx3dSpark and barWrap._fx3dSpark.active and bar then
        pcall(UpdateSpark3DPos, bar, barWrap, barWrap._fx3dSpark, isReverse)
    end
end

local function AnimateRender(renderKey)
    local gfx = ns.renderFrames[renderKey]; if not gfx or not gfx.rows then return end
    local auras = ns.auraData and ns.auraData[renderKey] or {}
    -- IMPORTANT : on ne peut PAS early-exit sur #auras == 0, car en combat le scan
    -- peut ne plus voir l'aura (devenue secret value sur sorts CDM Midnight 12.0).
    -- Si on retourne ici, UpdateClip3DPart n'est jamais appele et le 3D barre ne
    -- suit pas le remplissage. On continue la boucle, mais on early-exit dans
    -- AnimateOne lui-meme si la row n'a pas de fx3d barre actif (cas frequent
    -- pour les sorts sans 3D ou hors combat sans aura).
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
    -- Override couleur par render : si l'utilisateur a defini cfg.barColorR/G/B
    -- via le menu BARRE (COULEUR & TEXTURE), on l'applique a toutes les barres
    -- de ce render. Permet de differencier visuellement Debuffs / Buffs / Cooldowns / Procs.
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
                -- Combat secret : pas d'aura visible cote scan mais la barre est animee
                -- par SetTimerDuration cote C++ Blizzard. UpdateBarFX3DOnly continue
                -- a faire suivre les FX (3D Fond et Fill 2D scrolling) au remplissage.
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
        -- Pre-extraction : les overrides par sort (uniquement Buffs) sont lus dans la boucle
        -- via cfg.spellGradients[a.spellID]. Voir Init.lua ApplyBarColor pour la priorite.
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
                -- Pas d'aura visible (scan secret en combat) MAIS la barre est animee
                -- par SetTimerDuration cote C++ Blizzard. On doit quand meme continuer
                -- a appeler UpdateClip3DPart pour que le 3D suive le remplissage.
                -- Solution A pour Midnight 12.0 : pattern "show but don't know" sur la geometrie.
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

------------------------------------------------------------------------
-- TEXTE DE TIMER (A1+A2+A3+C2 : ticker séparé 10 fps, détaint, cache, dual)
------------------------------------------------------------------------
-- Helper top-level : lit uniquement remaining duration depuis durObj (pour timer text)
-- Combat sur sort CDM : GetRemainingDuration retourne secret -> r + 0 plante.
-- On verifie issecretvalue avant l'arithmetique pour eviter le crash silencieux.
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

-- Contexte timer icône réutilisé entre ticks (évite alloc table à 10fps × 3 renders).
-- Les champs sont simplement mis à jour avant chaque UpdateTimersForRender.
local _ctxIcon = { tR=1, tG=1, tB=1, decimals=1 }

-- Helper top-level : texte + couleur d'urgence du timer pour un FontString.
-- Utilise ns.URGENCY (CRITICAL, MEDIUM) qui change rarement → lu globalement.
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

-- Helper top-level : met à jour le timer d'une row simple (non-dual).
-- L'icône (iconlist/circlebars/icons) porte le FontString sur le bouton (ib._durText) ;
-- freebars n'a pas d'icône, le FontString est directement sur la row (row._durText).
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

-- Barres à 60 fps (OnUpdate) avec auto-détachement (pattern identique à timerDriver).
-- Quand aucune aura active, le OnUpdate est DÉTACHÉ (SetScript nil) au lieu de
-- juste early-exit. Blizzard n'appelle plus la closure → zéro overhead CPU idle.
-- Réveillé par ns.WakeAnimDriver() depuis ScanAuras quand des auras apparaissent.
animDriver._running = false

local function AnimDriverTick(self, elapsed)
    self._t = self._t + elapsed
    if self._t < 0.0166 then return end  -- 60fps
    self._t = 0
    -- Check direct _activeAuraCount : le animDriver ne gère QUE les color curves
    -- des bars visibles. Les fades alpha ont leur propre ticker (C_Timer.NewTicker)
    -- qui s'auto-cancel. Pas besoin d'animDriver pour eux.
    --
    -- IMPORTANT pour Solution A FX3D Bar : meme si _activeAuraCount=0 (le scan ne
    -- voit plus l'aura car secret en combat), on doit CONTINUER a animer si au
    -- moins une barre a un fx3d barre 3D actif. Sans ca, UpdateClip3DPart n'est
    -- appele qu'a la frame d'apparition (frame=1) et le 3D ne suit jamais le
    -- remplissage. ns._fx3dBarActiveCount est incremente/decremente par
    -- ShowBarModel/HideBarModel dans SpellEffects.lua.
    local hasActiveAuras = (ns._activeAuraCount or 0) > 0
    local hasActiveFx3d = (ns._fx3dBarActiveCount or 0) > 0
    if not hasActiveAuras and not hasActiveFx3d then
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

-- Timer texte à 10 fps : OnUpdate arrêtable (via SetScript nil) au lieu d'un
-- C_Timer.NewTicker qui tourne en permanence. Quand aucune aura n'est active,
-- le OnUpdate lui-même est détaché → zéro overhead CPU idle.
-- Réactivation événementielle : ns.WakeTimerDriver() depuis ScanAuras quand
-- _activeAuraCount passe de 0 à >0.
local timerDriver = CreateFrame("Frame")
timerDriver._t = 0
timerDriver._running = false

local function TimerDriverTick(self, elapsed)
    self._t = self._t + elapsed
    if self._t < 0.1 then return end
    self._t = 0
    for i = 1, #RENDER_KEYS do pcall(UpdateTimersForRender, RENDER_KEYS[i]) end

    -- Pas de double-check expiry via GetRemainingDuration : cette API retourne
    -- un secret value en combat sur les DOTs du joueur, ce qui fait crasher la
    -- comparaison `rem <= 0` (la variable rem est tainted, même dans un pcall).
    -- SetTimerDuration natif Blizzard gère l'expiration côté C++. Quand l'aura
    -- expire, Blizzard fire UNIT_AURA avec removedAuraInstanceIDs et notre scan
    -- supprime la bar normalement.
end

function ns.WakeTimerDriver()
    if not timerDriver._running then
        timerDriver._running = true
        timerDriver._t = 0
        timerDriver:SetScript("OnUpdate", TimerDriverTick)
    end
end

-- Démarrage initial : on laisse dormir tant qu'aucune aura n'est détectée.
-- Le premier ns.ScanAuras() qui trouve des auras appellera WakeAnimDriver() et WakeTimerDriver().

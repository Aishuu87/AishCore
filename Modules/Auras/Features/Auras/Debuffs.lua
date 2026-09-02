-- AishUIAura/Features/Auras/Debuffs.lua
-- Aegis (miroir) + Berserk (dual) — layouts centraux sous le cercle
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
local Debuffs = {}
ns.RegisterRender("iconlist", Debuffs)
local CreateFrame, math, pcall = CreateFrame, math, pcall
local DARK, TEXCOORD = 14/255, 0.07

local function Dims()
    local c = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    return c.barW or 80, c.barH or 2, c.iconW or 25, c.iconH or 25,
           c.gap or 12, c.pairGap or 6, c.rowGap or 3
end

local function MakeIcon(parent, w, h)
    local cfg = ns.db and ns.db.iconlist or ns.Defaults.iconlist
    local ib = CreateFrame("Button", nil, parent)
    ib:SetSize(w, h)
    -- Insets négatifs : élargit légèrement la zone de survol au-delà du cadre
    -- visuel pour absorber les écarts d'arrondi pixel entre ib et le Cooldown
    -- superposé (cd), qui pouvaient laisser une fine bande (1-2px) sur un bord
    -- comme seule zone réellement réactive au tooltip.
    ib:SetHitRectInsets(-1, -1, -1, -1)
    ib:SetScript("OnEnter", ns.AuraIconOnEnter)
    ib:SetScript("OnLeave", ns.AuraIconOnLeave)

    local icon = ib:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(TEXCOORD, 1 - TEXCOORD, TEXCOORD, 1 - TEXCOORD)

    local cd = CreateFrame("Cooldown", nil, ib, "CooldownFrameTemplate")
    cd:SetAllPoints(ib)
    cd:EnableMouse(false) -- purement visuel (swipe) : ne doit jamais intercepter le survol de ib
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
    -- CRITICAL : quand une couleur est forcée (via le color picker ou le gradient),
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
    -- IMPORTANT : ne marquer _glowSetup=true qu'APRES succes complet. Sur les
    -- auraButton natifs (AuraTrackerContainer.lua, patch 12.1),
    -- CreateFrame/CreateTexture peuvent echouer si le bouton devient
    -- transitoirement forbidden -- si _glowSetup passait a true AVANT la
    -- creation, un seul echec empoisonnerait le glow de ce bouton POUR
    -- TOUJOURS (ShowGlow suivants indexeraient des champs jamais crees,
    -- silencieusement avales par le pcall appelant) : plus aucun glow du
    -- tout apres une premiere tentative ratee.
    local ok = pcall(function()
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
    end)
    ib._glowSetup = ok
end

local function ShowGlow(ib, idx, color, alpha, scale, sizeW, sizeH)
    if not ib then return end
    local def = ns.GLOW_DEFS[idx or 1]
    if not def or def.name == "Aucun" then return end
    color = color or ns.barColor; alpha = alpha or 0.7; scale = scale or 1.0
    EnsureGlow(ib)

    -- Guard : ne pas REDEMARRER l'animation si le même type de glow tourne déjà
    -- (sans ça, un appel répété -- chaque scan, plusieurs fois/seconde --
    -- relance l'AnimationGroup depuis le début, ce qui provoque un reset
    -- visible en boucle). Ce guard ne doit PAS faire un `return` immédiat,
    -- ce qui bloquerait AUSSI toute mise à jour de couleur/opacité/échelle
    -- tant que le TYPE ne change pas -- cas le plus courant (seul le slider
    -- opacité/taille bouge). On calcule juste `sameTypePlaying` ici ;
    -- couleur/opacité/échelle sont
    -- désormais TOUJOURS réappliquées plus bas, seul le redémarrage de
    -- l'animation (Play()) reste conditionné à ce guard.
    local sameTypePlaying = false
    if ib._glowActiveIdx == idx then
        if def.useAlphaPulse then
            sameTypePlaying = ib._glowPulseAG:IsPlaying()
        else
            sameTypePlaying = ib._glowFlipAG:IsPlaying()
        end
    end
    ib._glowActiveIdx = idx

    -- sizeW/sizeH (optionnels) : a fournir explicitement pour un auraButton
    -- natif (AuraTrackerContainer.lua) -- une fois lie a une vraie aura, SA
    -- PROPRE ib:GetSize() peut renvoyer une valeur SECRETE ("attempt to
    -- perform arithmetic on ... a secret number value"), meme si le bouton
    -- reste par ailleurs accessible. On connait
    -- deja la taille (c'est nous qui l'avons posee via SetSize juste avant),
    -- pas la peine de la relire sur un objet potentiellement tainted.
    local iw, ih = sizeW, sizeH
    if not (iw and ih) then iw, ih = ib:GetSize() end
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
        if not sameTypePlaying then
            ib._glowPulseAnim:SetFromAlpha(def.fromAlpha or 0.3)
            ib._glowPulseAnim:SetToAlpha(def.toAlpha or 0.7)
            ib._glowPulseAnim:SetDuration(def.duration or 0.8)
            p:SetAlpha(def.fromAlpha or 0.3); ib._glowPulseAG:Play()
        end
        p:Show()
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
        if not sameTypePlaying then
            local fa = ib._glowFlipAnim
            fa:SetFlipBookRows(def.rows or 6); fa:SetFlipBookColumns(def.columns or 5)
            fa:SetFlipBookFrames(def.frames or 30); fa:SetDuration(def.duration or 1.0)
            pcall(function() fa:SetFlipBookFrameWidth(def.frameW or 0) end)
            pcall(function() fa:SetFlipBookFrameHeight(def.frameH or 0) end)
            ib._glowFlipAG:Play()
        end
        f:Show()
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
-- PROC START (animation d'entree, jouee UNE FOIS quand une aura/proc passe
-- de inactif -> actif). Meme moteur que ShowGlow/HideGlow ci-dessus (memes
-- champs GLOW_DEFS : atlas/texture/rows/columns/frames/duration/scale/
-- useAlphaPulse/texCoord/blendMode/fromAlpha/toAlpha), mais :
--   - AnimationGroup SANS SetLooping (donc une seule lecture, contrairement
--     a ShowGlow qui boucle en REPEAT/BOUNCE en continu tant que le glow est
--     actif) -- OnFinished cache la texture, pas besoin d'un Hide manuel.
--   - Layer/texture DEDIES (ib._procPulse/_procFlip, PAS ib._glowPulse/_glowFlip)
--     pour pouvoir jouer en meme temps que la boucle sans se marcher dessus
--     (ex: glow "Modern Glow" en continu + flourish "Proc: White Short" au
--     moment precis ou l'aura apparait), sur un FrameLevel superieur pour
--     rester visible par-dessus.
-- ns.PlayProcStart etait appele depuis 4 endroits (Tactics.lua bouton
-- "Tester Proc", Procs.lua/Debuffs.lua/Cooldowns.lua a l'apparition reelle
-- d'un proc) mais n'avait jamais ete definie nulle part -- CONFIRME EN JEU :
-- bouton test sans effet ET aucune animation d'entree jamais visible en jeu,
-- pas juste dans le popup de test.
------------------------------------------------------------------------
local function EnsureProcStart(ib)
    if ib._procSetup then return end
    ib._procSetup = true
    local pc = CreateFrame("Frame", nil, ib)
    pc:SetFrameLevel(ib:GetFrameLevel() + 3)  -- au-dessus du glow boucle (+2, cf. EnsureGlow)
    ib._procContainer = pc
    local pulse = pc:CreateTexture(nil, "OVERLAY", nil, 1)
    pulse:SetBlendMode("ADD"); pulse:SetAlpha(0); pulse:Hide()
    ib._procPulse = pulse
    local ag = pulse:CreateAnimationGroup()  -- pas de SetLooping : joue une fois
    local anim = ag:CreateAnimation("Alpha"); anim:SetSmoothing("OUT")
    ib._procPulseAG = ag; ib._procPulseAnim = anim
    ag:SetScript("OnFinished", function() pulse:SetAlpha(0); pulse:Hide() end)
    local flip = pc:CreateTexture(nil, "OVERLAY", nil, 2)
    flip:SetAlpha(0); flip:Hide(); flip:SetBlendMode("ADD")
    ib._procFlip = flip
    local fag = flip:CreateAnimationGroup()  -- pas de SetLooping : joue une fois
    local fa = fag:CreateAnimation("FlipBook"); fa:SetOrder(1)
    ib._procFlipAG = fag; ib._procFlipAnim = fa
    fag:SetScript("OnFinished", function() flip:SetAlpha(0); flip:Hide() end)
end

local function PlayProcStart(ib, idx, color, scale)
    if not ib then return end
    local def = ns.GLOW_DEFS[idx or 1]
    if not def or def.name == "Aucun" then return end
    color = color or ns.barColor; scale = scale or 1.0
    EnsureProcStart(ib)

    local iw, ih = ib:GetSize()
    -- Filet : dans le popup de test (Tactics.lua), la frame preview peut ne
    -- pas encore avoir sa taille resolue au tout premier appel.
    if not iw or iw <= 0 then iw = 32 end
    if not ih or ih <= 0 then ih = 32 end
    local mx = math.max(4, math.floor(iw * 0.3 * scale))
    local my = math.max(4, math.floor(ih * 0.3 * scale))
    local pc = ib._procContainer
    pc:ClearAllPoints()
    pc:SetPoint("TOPLEFT", ib, -mx, my)
    pc:SetPoint("BOTTOMRIGHT", ib, mx, -my)

    if def.useAlphaPulse then
        ib._procFlipAG:Stop(); ib._procFlip:SetAlpha(0); ib._procFlip:Hide()
        local p = ib._procPulse
        if def.atlas then p:SetTexture(nil); p:SetAtlas(def.atlas); p:SetTexCoord(0,1,0,1)
        else p:SetTexture(def.texture)
            if def.texCoord then p:SetTexCoord(unpack(def.texCoord)) else p:SetTexCoord(0,1,0,1) end
        end
        p:SetBlendMode(def.blendMode or "ADD")
        p:SetVertexColor(color[1], color[2], color[3], 1)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", ib, -mx, my)
        p:SetPoint("BOTTOMRIGHT", ib, mx, -my)
        ib._procPulseAnim:SetFromAlpha(def.fromAlpha or 0)
        ib._procPulseAnim:SetToAlpha(def.toAlpha or 1)
        ib._procPulseAnim:SetDuration(def.duration or 0.2)
        p:Show(); p:SetAlpha(def.fromAlpha or 0)
        ib._procPulseAG:Stop(); ib._procPulseAG:Play()
    else
        ib._procPulseAG:Stop(); ib._procPulse:SetAlpha(0); ib._procPulse:Hide()
        local f = ib._procFlip
        if def.atlas then f:SetTexture(nil); f:SetAtlas(def.atlas)
        elseif def.texture then f:SetTexture(def.texture) end
        local sc = (def.scale or 1) * scale
        local sw = iw * sc + mx * 2
        local sh = ih * sc + my * 2
        f:ClearAllPoints(); f:SetSize(sw, sh); f:SetPoint("CENTER", ib, 0, 0)
        f:SetVertexColor(color[1], color[2], color[3], 1); f:SetBlendMode("ADD")
        local fa = ib._procFlipAnim
        fa:SetFlipBookRows(def.rows or 6); fa:SetFlipBookColumns(def.columns or 5)
        fa:SetFlipBookFrames(def.frames or 30); fa:SetDuration(def.duration or 0.5)
        pcall(function() fa:SetFlipBookFrameWidth(def.frameW or 0) end)
        pcall(function() fa:SetFlipBookFrameHeight(def.frameH or 0) end)
        f:Show(); f:SetAlpha(1)
        ib._procFlipAG:Stop(); ib._procFlipAG:Play()
    end
end

ns.PlayProcStart = PlayProcStart

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

-- Abonnement au swipe CDM (aura.useCDMSwipe, cf. Scan.lua) : en combat,
-- GetAuraDuration echoue systematiquement pour un instID CDM (donc pas de
-- durObj) -- ce canal event-driven (CDMHooks.lua, alimente par le CDM
-- Blizzard lui-meme) prend le relais. Desabonne l'ancien spellID si l'icone
-- (ib, cle stable reutilisee entre scans) change de sort affiche.
local function ApplyCDMSwipe(ib, cd, aura)
    local newID = aura.useCDMSwipe and aura.spellID or nil
    if ib._cdmSwipeSpellID and ib._cdmSwipeSpellID ~= newID then
        if ns.UnsubscribeCDMAuraSwipe then ns.UnsubscribeCDMAuraSwipe(ib._cdmSwipeSpellID, ib) end
        ib._cdmSwipeSpellID = nil
    end
    if newID and ib._cdmSwipeSpellID ~= newID then
        if ns.SubscribeCDMAuraSwipe then ns.SubscribeCDMAuraSwipe(newID, ib, cd) end
        ib._cdmSwipeSpellID = newID
    end
end
ns._ApplyCDMSwipe = ApplyCDMSwipe

-- Abonnement au clone CDM des stacks (cf. CDMHooks.lua, "ABONNEMENTS CLONE
-- STACK") : filet de secours combat-safe (joueur ET cible) pour le cas ou la
-- lecture directe (_GetPlayerAuraStackValue, joueur uniquement, echoue en
-- combat sur une aura a duree limitee) ne renvoie rien. Meme pattern
-- d'abonnement/desabonnement que ApplyCDMSwipe ci-dessus, sur le spellID
-- (contrairement au swipe, pas de garde useCDMSwipe : les stacks n'ont pas
-- d'equivalent "durObj disponible" a preferer, ce canal est toujours utile
-- en repli).
-- IMPORTANT (bug corrige) : c'est ICI, pas dans ApplyStackCharges, que le
-- "reset propre" au changement de sort doit avoir lieu -- ApplyCDMStackSwipe
-- s'execute AVANT ApplyStackCharges dans ApplyAura. Un Hide() inconditionnel
-- fait APRES coup dans ApplyStackCharges ecrasait la valeur que
-- SubscribeCDMAuraStack vient de repousser immediatement ici (cache
-- cdmAuraLastApplications, cf. CDMHooks.lua) -- symptome observe en jeu :
-- une icone qui se decale (reordonnancement par priorite quand une nouvelle
-- aura apparait) perdait son affichage de stacks jusqu'au prochain
-- changement de valeur, alors que la bonne valeur etait deja disponible en
-- cache au moment meme du changement de sort sur cette icone.
local function ApplyCDMStackSwipe(ib, aura)
    local newID = aura.spellID
    if ib._cdmStackSpellID and ib._cdmStackSpellID ~= newID then
        if ns.UnsubscribeCDMAuraStack then ns.UnsubscribeCDMAuraStack(ib._cdmStackSpellID, ib) end
        ib._cdmStackSpellID = nil
        -- Nettoyage AVANT re-abonnement : si aucune valeur en cache pour le
        -- nouveau spellID, on part d'un etat propre plutot que de garder le
        -- stack de l'ancienne aura affiche par erreur.
        if ib._stackText then ib._stackText:Hide() end
    end
    if newID and ib._cdmStackSpellID ~= newID and ib._stackText then
        if ns.SubscribeCDMAuraStack then ns.SubscribeCDMAuraStack(newID, ib, ib._stackText) end
        ib._cdmStackSpellID = newID
    end
end
ns._ApplyCDMStackSwipe = ApplyCDMStackSwipe

-- Abonnement au clone CDM du remplissage de BARRE (StatusBar, cf. CDMHooks.lua
-- "ABONNEMENTS CLONE BAR") : contrairement à ApplyCDMSwipe ci-dessus (Cooldown,
-- confirmé bloqué en combat pour toute valeur secrète venant d'un addon), ce
-- canal utilise StatusBar:SetValue/SetMinMaxValues, qui ACCEPTENT le relais
-- secret -- réellement combat-safe. Utilisé pour les rendus à barres
-- (circlebars) plutôt qu'à swipe d'icône.
-- statusBar sert lui-même de clé d'abonnement (chaque widget est unique) --
-- pas besoin d'un ib/row séparé, fonctionne aussi bien pour une barre seule
-- (row.bar) que pour une paire (row.barL/row.barR, chacune abonnée
-- indépendamment avec le même spellID).
-- Nécessite que le sort soit épinglé sur le viewer "Barres"
-- (BuffBarCooldownViewer) du Cooldown Manager Blizzard (Edit Mode) -- sinon
-- aucune donnée ne circule sur ce canal pour ce spellID.
local function ApplyCDMBarSwipe(statusBar, aura)
    if not statusBar then return end
    local newID = aura.spellID
    if statusBar._cdmBarSpellID and statusBar._cdmBarSpellID ~= newID then
        if ns.UnsubscribeCDMAuraBar then ns.UnsubscribeCDMAuraBar(statusBar._cdmBarSpellID, statusBar) end
        statusBar._cdmBarSpellID = nil
        pcall(statusBar.SetValue, statusBar, 0)
    end
    if newID and statusBar._cdmBarSpellID ~= newID then
        if ns.SubscribeCDMAuraBar then ns.SubscribeCDMAuraBar(newID, statusBar, statusBar) end
        statusBar._cdmBarSpellID = newID
    end
end
ns._ApplyCDMBarSwipe = ApplyCDMBarSwipe

-- Binding natif (AuraTrackerContainer.lua, AuraButton:SetDurationCooldown/
-- SetApplicationCount) : source PRIORITAIRE, plus robuste que les canaux de
-- forward manuels ci-dessus -- Blizzard anime lui-meme le widget Cooldown ET
-- ecrit le texte de stacks, sans jamais faire transiter de valeur secrete
-- par du Lua. Ne remplace pas les canaux CDM ci-dessus (garde en repli si le
-- bouton natif n'est pas encore disponible, ex. avant le premier /reload
-- suivant l'ajout d'un sort a la liste de tracking). Rebind uniquement au
-- changement de spellID sur cette icone (evite des appels redondants a
-- chaque scan).
local function ApplyNativeAuraBindings(ib, cd, aura)
    local spellID = aura.spellID
    if ib._nativeBoundSpellID == spellID then return end
    if not spellID or not ns.GetNativeAuraButton then return end
    local nativeBtn = ns.GetNativeAuraButton(aura.unit, spellID)
    if not nativeBtn then return end
    pcall(nativeBtn.SetDurationCooldown, nativeBtn, cd)
    if ib._stackText then pcall(nativeBtn.SetApplicationCount, nativeBtn, ib._stackText) end
    ib._nativeBoundSpellID = spellID
end
ns._ApplyNativeAuraBindings = ApplyNativeAuraBindings

-- Cherche et cache le FontString du cooldown countdown natif Blizzard.
-- Blizzard ne l'expose pas directement, on doit le retrouver par GetRegions().
-- On cache la référence sur le cd frame lui-même (cd._aishCountdownFS) pour
-- éviter de rescanner à chaque ApplyAura.
-- Style + repositionne le FontString NATIF du countdown Blizzard (le texte
-- lui-meme reste rempli par le C++, meme sur une donnee secrete -- on ne
-- touche jamais la VALEUR, seulement les proprietes visuelles du FontString,
-- qui ne sont pas secretes). anchor/relFrame/relPoint : "Position (par
-- rapport a l'icone/au conteneur)" du menu Reglages, offX/offY : "Offset X/Y".
-- relFrame par defaut = cd lui-meme si non fourni (retro-compat).
-- Cherche a la fois les regions ET les enfants (CooldownFrameTemplate ajoute
-- parfois un sous-frame CooldownDisplay contenant le FontString reel selon
-- la version du client -- meme recette que TargetAuras.lua::StyleCooldownText).
local function _StyleCountdownFS(cd, font, size, r, g, b, anchor, relFrame, relPoint, offX, offY)
    local function styleFS(fs)
        if not fs or not fs.SetFont then return end
        pcall(ns.ApplyFont, fs, font, size, "OUTLINE")
        if r then pcall(fs.SetTextColor, fs, r, g or 1, b or 1) end
        fs:ClearAllPoints()
        fs:SetPoint(anchor or "CENTER", relFrame or cd, relPoint or anchor or "CENTER", offX or 0, offY or 0)
        fs:SetJustifyH("CENTER")
    end
    for i = 1, cd:GetNumRegions() do
        local region = select(i, cd:GetRegions())
        if region and region.GetObjectType and region:IsObjectType("FontString") then
            styleFS(region)
        end
    end
    for i = 1, cd:GetNumChildren() do
        local child = select(i, cd:GetChildren())
        if child then
            for j = 1, child:GetNumRegions() do
                local region = select(j, child:GetRegions())
                if region and region.GetObjectType and region:IsObjectType("FontString") then
                    styleFS(region)
                end
            end
        end
    end
end
ns._StyleCountdownFS = _StyleCountdownFS

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
        elseif ib._nativeBoundSpellID == aura.spellID then
            -- Des qu'un bouton AuraContainer natif est branche sur
            -- ib._stackText (ApplyNativeAuraBindings, appele plus haut dans
            -- ApplyAura via SetApplicationCount), Blizzard ecrit DIRECTEMENT
            -- et en temps reel dans ce FontString, combat-safe (widget
            -- "blessed" cote Blizzard). Si ce bloc-ci ecrit AUSSI dedans
            -- (SetText/Show/Hide avec la valeur cachee ci-dessous), les 2
            -- sources se battent pour le meme FontString et donnent des
            -- stacks incorrects des que le natif est actif. Une fois le binding natif etabli
            -- pour ce spellID, on ne touche plus JAMAIS ib._stackText ici --
            -- Blizzard reste seul maitre (y compris pour le masquer a 0, cf.
            -- doc officielle SetApplicationCount).

        elseif cfg.stackEnabled ~= false and aura.spellID and ib.unit == "player" then
            -- Repli tant qu'aucun bouton natif n'est encore branche sur cette
            -- ligne pour ce spellID (ex. juste apres l'ajout d'un nouveau
            -- sort a la liste de tracking, avant le prochain /reload qui
            -- laissera EnsureAuraTrackerContainer creer son slot -- cf.
            -- AuraTrackerContainer.lua) : aura.stacks vient de Scan.lua/
            -- MakeEntry, qui memorise la derniere lecture directe reussie
            -- (ns._lastKnownAura) et la reutilise telle quelle quand la
            -- lecture directe echoue (typiquement en combat) plutot que de
            -- retomber a 0 -- meme source que l'icone elle-meme.
            --
            -- Un Hide() inconditionnel ici des que stacks<=1 ecraserait la valeur que le
            -- canal CDM-forward event-driven (ApplyCDMStackSwipe, souscrit
            -- AVANT nous dans ApplyAura -- cf. son commentaire, meme piege
            -- deja corrige une fois pour ce meme fichier) vient de pousser en
            -- temps reel via SetAuraInstanceInfo -- seul canal qui continue
            -- de se mettre a jour PENDANT le combat, le cache ci-dessus etant
            -- fige jusqu'a la prochaine lecture directe reussie. Meme regle
            -- que pour la cible juste en dessous : hors combat, aura.stacks
            -- est frais et fiable pour cacher franchement ; en combat, ne
            -- JAMAIS toucher l'etat, laisser le canal CDM-forward garder la main.
            local stacks = aura.stacks
            if stacks and stacks > 1 then
                if ns.MarkStackCapable then ns.MarkStackCapable(aura.spellID) end
                ib._stackText:SetText(stacks)
                ib._stackText:Show()
            elseif not (InCombatLockdown and InCombatLockdown()) then
                if stacks == 0 and ns.MarkStackNotCapable then
                    ns.MarkStackNotCapable(aura.spellID)
                end
                ib._stackText:Hide()
            end
        elseif cfg.stackEnabled ~= false and aura.spellID and ib.unit then
            -- Cible (pas de GetPlayerAuraBySpellID equivalent cote cible) :
            -- pas de logique ici, on ne touche PAS a l'etat -- le canal
            -- CDM-forward (ApplyCDMStackSwipe, souscrit dans ApplyAura,
            -- event-driven) est la SEULE source pour ce cas et met a jour
            -- ib._stackText lui-meme de facon asynchrone. Un Hide()
            -- inconditionnel ici ecraserait ce qu'il vient de pousser.
        else
            ib._lastStackSpellID = nil
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
    ib.spellID = aura.spellID
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
    elseif aura.directStart and aura.directDuration then
        -- Repli : duration/expirationTime lus directement sur l'AuraData
        -- (cf. Scan.lua/MakeEntry) plutôt qu'un durObj -- SetCooldown classique
        -- (pas FromDurationObject), valeurs potentiellement secrètes acceptées
        -- brutes (même sink que le relais CDM ci-dessous).
        pcall(cd.SetCooldown, cd, aura.directStart, aura.directDuration)
    elseif aura._isPreview then
        -- Les fausses entrees de preview n'ont ni durObj ni
        -- directStart/directDuration (rien de secret a simuler) -- sans ce
        -- repli, le Cooldown ne serait jamais lie, texte de duree vide.
        -- Cycle 12s synthetique, meme convention que Animation.lua::AnimateBar.
        pcall(cd.SetCooldown, cd, GetTime(), 12)
    end
    pcall(ApplyCDMSwipe, ib, cd, aura)
    pcall(ApplyCDMStackSwipe, ib, aura)
    pcall(ApplyNativeAuraBindings, ib, cd, aura)
    cd:SetDrawSwipe(cfg.swipeEnabled == true); cd:SetDrawEdge(cfg.swipeEnabled == true)
    -- Native countdown timer
    cd:SetHideCountdownNumbers(not (cfg.timerIconEnabled))
    if cfg.timerIconEnabled then
        pcall(_StyleCountdownFS, cd,
            cfg.timerFont or ns.Media.font, cfg.timerSize or 12,
            cfg.timerColorR, cfg.timerColorG, cfg.timerColorB,
            cfg.timerPos or "CENTER", ib, cfg.timerPos or "CENTER",
            cfg.timerIconOffX or 0, cfg.timerIconOffY or 0)
    end

    -- Glow (with render override support)
    local glIdx = aura.glowIdx
    local glColor = aura.glowColor or aura.spellColor
    local glAlpha = aura.glowAlpha
    local glScale = aura.glowScale or 1.0
    local hasGlow = aura.spellGlow and glIdx and glIdx > 1
    -- Override render RETIRE, desactive via `false and` -- cf.
    -- AuraTrackerContainer.lua::ApplySpellGlow.
    if false and cfg.glowOverrideIdx and cfg.glowOverrideIdx > 1 then
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
    cont:SetMovable(true); cont:SetClampedToScreen(true); _addon.EnableMouseOnlyOnAlt(cont)
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
    lbl:SetText("|cffffcc00"..L["AURASFEAT_ALT_DRAG_HINT"].."|r"); lbl:Hide()
    cont:SetScript("OnMouseDown", function(s, b)
        if b == "LeftButton" and IsAltKeyDown() then
            s._aishDragging = true
            s:SetPropagateMouseClicks(false)  -- bloquer la propagation pendant le drag
            s:StartMoving(); lbl:Show()
        end
    end)
    cont:SetScript("OnMouseUp", function(s)
        s._aishDragging = false
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
        s._aishDragging = false
        s:StopMovingOrSizing()
        s:SetPropagateMouseClicks(true)
        lbl:Hide()
    end)
    cont:Show()
    ns.renderFrames.iconlist = { container = cont, rows = rows, layout = layout, growth = growth }
    ns.UpdateRenderFade("iconlist")
end

------------------------------------------------------------------------
-- UPDATE : rendu REEL supprime, meme methodologie que Icons/Circle
-- Bars/Free Bars -- migre vers un rendu natif combat-safe sans pin CDM
-- (cf. AuraTrackerContainer.lua ns.EnsureIconListNativeGrid).
--
-- La logique ORIGINALE (Aegis/Berserk) est conservee telle quelle,
-- UNIQUEMENT pour l'apercu en direct dans le menu "Auras & Procs" -- cf.
-- commentaire equivalent dans Buffs.lua pour le detail complet. Le rendu
-- reel est 100% natif. Debuffs:Init() reste inchangee (rows Aegis/Berserk,
-- utilitaires Dims/MakeIcon/MakeBarWrap partages).
------------------------------------------------------------------------
function Debuffs:Update(auras)
    local previewActive = ns._previewBars and (ns._previewMode == "all" or ns._previewMode == "iconlist")
    if not previewActive then
        if ns.renderFrames.iconlist and ns.renderFrames.iconlist.container then
            ns.renderFrames.iconlist.container:SetAlpha(0)
            ns.renderFrames.iconlist.container:Hide()
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

    for _, r in ipairs(rows) do
        ns.MarkRowInactive(r)
    end

    local wl = ns.whitelistByDest and ns.whitelistByDest.iconlist

    if not ns._debuffsIDsA then ns._debuffsIDsA = {}; ns._debuffsIDsB = {}; ns._debuffsIDsUseA = true end
    local prevIDs = ns._debuffsIDsUseA and ns._debuffsIDsB or ns._debuffsIDsA
    local curIDs  = ns._debuffsIDsUseA and ns._debuffsIDsA or ns._debuffsIDsB
    wipe(curIDs)
    ns._debuffsIDsUseA = not ns._debuffsIDsUseA
    if not ns._dbgSeenInstIDsA then ns._dbgSeenInstIDsA = {}; ns._dbgSeenInstIDsB = {}; ns._dbgSeenUseA = true end
    local seenInstIDs = ns._dbgSeenUseA and ns._dbgSeenInstIDsA or ns._dbgSeenInstIDsB
    local prevSeenInstIDs = ns._dbgSeenUseA and ns._dbgSeenInstIDsB or ns._dbgSeenInstIDsA
    wipe(seenInstIDs)
    ns._dbgSeenUseA = not ns._dbgSeenUseA
    ns._dbgPrevSeenInstIDs = prevSeenInstIDs

    local function ok(a) return a and a.spellID and (a.spellID > 900000 or (wl and wl[a.spellID])) end

    local function ProcCheck(a, anchor)
        if a and a.spellID then
            curIDs[a.spellID] = true
            if not prevIDs[a.spellID] and a.procGlowIdx and a.procGlowIdx > 1 then
                if ns.PlayProcStart then ns.PlayProcStart(anchor, a.procGlowIdx, a.glowColor or a.spellColor, a.procGlowScale) end
            end
        end
    end

    local function MaybePop(row, aura, wraps, targetW)
        if not aura or not aura.auraInstanceID then return end
        local instID = aura.auraInstanceID
        seenInstIDs[instID] = true
        if row._popInstID == instID then return end
        row._popInstID = instID
        if ns.StartPopAnim then
            ns.StartPopAnim(row, wraps, targetW, cfg.barAlpha or 1, cfg)
        end
    end

    local function Pos(row, idx)
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
            pcall(ns._ApplyCDMBarSwipe, row.barL, auras[ai])
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
                pcall(ns._ApplyCDMBarSwipe, row.barR, auras[ai + 1])
            else row.halfR:Hide() end
            MaybePop(row, auras[ai], {row.wrapBarL, row.wrapBarR}, bw)
            ai = ai + 2
        end
    else
        for i, row in ipairs(rows) do
            if not ok(auras[i]) then break end
            vis = vis + 1; Pos(row, vis)
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
                row.wrapL:Show(); row.wrapL:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapL, auras[i])
                pcall(ns._ApplyCDMBarSwipe, row.barL, auras[i]) end
            if row.barR then row.barR:Show(); SetBarColor(row.barR, auras[i])
                row.wrapR:Show(); row.wrapR:SetAlpha(cfg.barAlpha or 1); ApplyBarModels(row.wrapR, auras[i])
                pcall(ns._ApplyCDMBarSwipe, row.barR, auras[i]) end
            MaybePop(row, auras[i], {row.wrapL, row.wrapR}, bw)
        end
    end

    for _, r in ipairs(rows) do
        if not r._aishActiveNow then
            ns.DeferHideRow(r, 0.1)
        end
    end

    if ns.LearnedDurations and ns.LearnedDurations.OnAuraDisappeared then
        for instID in pairs(prevSeenInstIDs) do
            if not seenInstIDs[instID] then
                ns.LearnedDurations.OnAuraDisappeared(instID)
            end
        end
    end

    -- SetAlpha(1) explicite (pas ns.UpdateRenderFade) : cette fonction route
    -- desormais "iconlist" vers le conteneur NATIF (rendu reel), pas vers ce
    -- conteneur Lua de preview -- l'appeler ici ne touchait donc jamais
    -- l'alpha de CE conteneur, qui restait bloque a 0 (cf. lecon Buffs.lua).
    gfx.container:Show()
    gfx.container:SetAlpha(1)
end


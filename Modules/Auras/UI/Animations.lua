-- AishUIAura/UI/Animations.lua
-- ============================================================================
-- Utilitaires d'animations réutilisables.
--
-- Fournit des helpers pour :
--   • Lerp (interpolation linéaire) entre deux valeurs
--   • Easing (courbes douces : smooth, bounce)
--   • Fade in sur une frame
--   • Hover color transition (texte qui change de couleur progressivement)
--   • Scale click feedback (bouton qui se rétrécit au clic)
--
-- Tous les helpers s'appuient sur OnUpdate (~60fps). Les timers s'arrêtent
-- automatiquement quand l'anim est terminée pour économiser du CPU.
--
-- Usage :
--   ns.Anim.FadeIn(frame, 0.25)           -- fade 0 → 1 en 0.25s
--   ns.Anim.HoverColor(fs, {1,1,1}, 0.15) -- couleur target en 0.15s
--   ns.Anim.ClickFeedback(button, 0.95)   -- scale 1 → 0.95 puis → 1
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.Anim = ns.Anim or {}

local CreateFrame = CreateFrame
local math_min = math.min

-- ============================================================================
-- HELPERS DE BASE : lerp, easing
-- ============================================================================
-- Interpolation linéaire. t ∈ [0, 1]
function ns.Anim.Lerp(a, b, t)
    return a + (b - a) * t
end

-- Easing "ease-out" (commence vite, ralentit à la fin). Joli pour les apparitions.
function ns.Anim.EaseOut(t)
    return 1 - (1 - t) * (1 - t)
end

-- ============================================================================
-- FADE IN / FADE OUT
-- ============================================================================
-- Frame cachée/affichée avec fade progressif.
-- onComplete est appelé quand le fade est fini.
local function RunFade(frame, fromAlpha, toAlpha, duration, onComplete)
    if not frame then return end
    duration = duration or 0.25
    frame:SetAlpha(fromAlpha)
    if not frame:IsShown() then frame:Show() end

    -- Utilise un Updater dédié pour ne pas polluer l'OnUpdate de la frame elle-même.
    local updater = frame._animFadeUpdater
    if not updater then
        updater = CreateFrame("Frame", nil, frame)
        frame._animFadeUpdater = updater
    end
    updater._elapsed = 0
    updater:SetScript("OnUpdate", function(self, delta)
        self._elapsed = self._elapsed + delta
        local t = math_min(1, self._elapsed / duration)
        local eased = ns.Anim.EaseOut(t)
        frame:SetAlpha(ns.Anim.Lerp(fromAlpha, toAlpha, eased))
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
            frame:SetAlpha(toAlpha)
            if toAlpha <= 0 then frame:Hide() end
            if onComplete then pcall(onComplete) end
        end
    end)
end

function ns.Anim.FadeIn(frame, duration, onComplete)
    RunFade(frame, 0, 1, duration, onComplete)
end

-- ============================================================================
-- HOVER COLOR : transition douce de couleur de texte
-- ============================================================================
-- @param fs        FontString cible
-- @param targetRGB table {r, g, b} ou {r, g, b, a}
-- @param duration  en secondes (défaut 0.15)
function ns.Anim.HoverColor(fs, targetRGB, duration)
    if not fs or not fs.GetTextColor then return end
    duration = duration or 0.15
    local r0, g0, b0, a0 = fs:GetTextColor()
    local r1 = targetRGB[1] or 1
    local g1 = targetRGB[2] or 1
    local b1 = targetRGB[3] or 1
    local a1 = targetRGB[4] or a0 or 1

    local updater = fs._animColorUpdater
    if not updater then
        updater = CreateFrame("Frame")
        fs._animColorUpdater = updater
    end
    updater._elapsed = 0
    updater:SetScript("OnUpdate", function(self, delta)
        self._elapsed = self._elapsed + delta
        local t = math_min(1, self._elapsed / duration)
        fs:SetTextColor(
            ns.Anim.Lerp(r0, r1, t),
            ns.Anim.Lerp(g0, g1, t),
            ns.Anim.Lerp(b0, b1, t),
            ns.Anim.Lerp(a0 or 1, a1, t)
        )
        if t >= 1 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- ============================================================================
-- CLICK FEEDBACK : bouton qui se rétrécit au clic puis revient
-- ============================================================================
-- Usage : dans OnMouseDown -> ns.Anim.ClickFeedback(self, 0.95, 0.08)
-- @param frame    La frame à scaler (button, icon, etc.)
-- @param minScale Scale minimal pendant le click (défaut 0.94)
-- @param duration Durée aller + retour en secondes (défaut 0.12)
function ns.Anim.ClickFeedback(frame, minScale, duration)
    if not frame or not frame.SetScale then return end
    minScale = minScale or 0.94
    duration = duration or 0.12
    local halfDur = duration / 2

    local updater = frame._animClickUpdater
    if not updater then
        updater = CreateFrame("Frame")
        frame._animClickUpdater = updater
    end
    updater._elapsed = 0
    updater._phase = "shrink"
    updater:SetScript("OnUpdate", function(self, delta)
        self._elapsed = self._elapsed + delta
        if self._phase == "shrink" then
            local t = math_min(1, self._elapsed / halfDur)
            frame:SetScale(ns.Anim.Lerp(1, minScale, ns.Anim.EaseOut(t)))
            if t >= 1 then
                self._phase = "expand"
                self._elapsed = 0
            end
        else
            local t = math_min(1, self._elapsed / halfDur)
            frame:SetScale(ns.Anim.Lerp(minScale, 1, ns.Anim.EaseOut(t)))
            if t >= 1 then
                frame:SetScale(1)
                self:SetScript("OnUpdate", nil)
            end
        end
    end)
end

-- ============================================================================
-- ANIMATIONS D'ICÔNES — Apparition et disparition animées
--
-- 4 styles disponibles :
--   "standard"  → fade + glisse depuis le bas légèrement
--   "surge"     → fade + scale + montée depuis le bas (style DOTs Feral)
--   "slide"     → glisse depuis la droite + fade
--   "pop"       → scale 0.5→1 + fade (style proc rapide)
--   "none"      → aucune animation
--
-- Usage :
--   ns.Anim.IconPopIn(iconBtn, cfg, targetAlpha)
--
-- Paramètres lus dans cfg (ns.db[renderKey]) :
--   iconAnimStyle    : "standard"|"surge"|"slide"|"pop"|"none"
--   iconAnimDuration : durée en secondes (défaut 0.4)
-- ============================================================================

local _EaseOut = function(t, s) s = s or 3; return 1 - (1 - t) ^ s end
local _EaseOutIn = function(t, s)
    s = s or 5
    if t < 0.5 then local p = 1 - 2*t; return 0.5*(1 - p^s)
    else local p = 2*t-1; return 0.5 + 0.5*(p^s) end
end

local function _GetUpdater(btn)
    if not btn._iconAnimUpdater then
        btn._iconAnimUpdater = CreateFrame("Frame", nil, btn:GetParent() or UIParent)
    end
    return btn._iconAnimUpdater
end

local function _SavePoints(btn)
    if btn:GetNumPoints() > 0 then
        local ap, rf, rp, x, y = btn:GetPoint(1)
        btn._iconOrigPoint = { ap, rf, rp, x or 0, y or 0 }
    end
end

local function _ApplyOffset(btn, dx, dy)
    if not btn._iconOrigPoint then return end
    local p = btn._iconOrigPoint
    btn:ClearAllPoints()
    btn:SetPoint(p[1], p[2], p[3], (p[4] or 0) + dx, (p[5] or 0) + dy)
end

function ns.Anim.StopIconAnim(btn)
    if not btn then return end
    if btn._iconAnimUpdater then btn._iconAnimUpdater:SetScript("OnUpdate", nil) end
    btn._iconAnimActive = false
    if btn.SetScale then btn:SetScale(1) end
    if btn.SetAlpha then btn:SetAlpha(btn._iconTargetAlpha or 1) end
    if btn._iconOrigPoint then
        local p = btn._iconOrigPoint
        btn:ClearAllPoints()
        btn:SetPoint(p[1], p[2], p[3], p[4], p[5])
        btn._iconOrigPoint = nil
    end
    btn._iconAnimPhase = nil
end

function ns.Anim.IconPopIn(btn, cfg, targetAlpha)
    if not btn then return end
    cfg = cfg or {}
    local style = cfg.iconAnimStyle or "standard"
    if style == "none" then return end
    local dur = cfg.iconAnimDuration or 0.4
    local tAlpha = targetAlpha or 1
    btn._iconTargetAlpha = tAlpha
    ns.Anim.StopIconAnim(btn)
    btn._iconAnimActive = true
    btn._iconAnimPhase = "in"

    if style == "standard" then
        local offY = -(cfg.iconAnimSlideY or 10)
        _SavePoints(btn); btn:SetAlpha(0); _ApplyOffset(btn, 0, offY)
        local u = _GetUpdater(btn); u._elapsed = 0
        u:SetScript("OnUpdate", function(self, dt)
            if not btn._iconAnimActive then self:SetScript("OnUpdate", nil); return end
            self._elapsed = self._elapsed + dt
            local t = math.min(1, self._elapsed / dur)
            local e = _EaseOut(t, 3)
            btn:SetAlpha(tAlpha * e); _ApplyOffset(btn, 0, offY * (1 - e))
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                btn:SetAlpha(tAlpha); _ApplyOffset(btn, 0, 0)
                btn._iconAnimActive = false; btn._iconOrigPoint = nil
            end
        end)

    elseif style == "surge" then
        local offY = cfg.iconAnimSlideY or 20; local s0 = 0.4
        _SavePoints(btn); btn:SetAlpha(0); btn:SetScale(s0); _ApplyOffset(btn, 0, offY)
        local u = _GetUpdater(btn); u._elapsed = 0
        u:SetScript("OnUpdate", function(self, dt)
            if not btn._iconAnimActive then self:SetScript("OnUpdate", nil); return end
            self._elapsed = self._elapsed + dt
            local t = math.min(1, self._elapsed / dur)
            local e = _EaseOutIn(t, cfg.iconAnimEase or 5)
            btn:SetAlpha(tAlpha * e); btn:SetScale(s0 + (1 - s0) * e)
            _ApplyOffset(btn, 0, offY * (1 - e))
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                btn:SetAlpha(tAlpha); btn:SetScale(1)
                _ApplyOffset(btn, 0, 0)
                btn._iconAnimActive = false; btn._iconOrigPoint = nil
            end
        end)

    elseif style == "slide" then
        local offX = cfg.iconAnimSlideX or 30
        _SavePoints(btn); btn:SetAlpha(0); _ApplyOffset(btn, offX, 0)
        local u = _GetUpdater(btn); u._elapsed = 0
        u:SetScript("OnUpdate", function(self, dt)
            if not btn._iconAnimActive then self:SetScript("OnUpdate", nil); return end
            self._elapsed = self._elapsed + dt
            local t = math.min(1, self._elapsed / dur)
            local e = _EaseOut(t, 3)
            btn:SetAlpha(tAlpha * e); _ApplyOffset(btn, offX * (1 - e), 0)
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                btn:SetAlpha(tAlpha); _ApplyOffset(btn, 0, 0)
                btn._iconAnimActive = false; btn._iconOrigPoint = nil
            end
        end)

    elseif style == "pop" then
        local s0 = 0.5; btn:SetAlpha(0); btn:SetScale(s0)
        local u = _GetUpdater(btn); u._elapsed = 0
        u:SetScript("OnUpdate", function(self, dt)
            if not btn._iconAnimActive then self:SetScript("OnUpdate", nil); return end
            self._elapsed = self._elapsed + dt
            local t = math.min(1, self._elapsed / dur)
            local e = _EaseOut(t, 3)
            btn:SetAlpha(tAlpha * e); btn:SetScale(s0 + (1 - s0) * e)
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                btn:SetAlpha(tAlpha); btn:SetScale(1)
                btn._iconAnimActive = false
            end
        end)
    end
end

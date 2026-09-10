-- TargetCastBar.lua : Barre de cast de la cible
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local TargetCastBar = {}
ns.Modules.TargetCastBar = TargetCastBar

-- Wrapper taint-safe pour secret values (issecretvalue, WoW 11.0.5+, même approche qu'ElvUI/oUF).
local _issecretvalue = issecretvalue
local function IsSafeValue(value)
    if _issecretvalue then
        return not _issecretvalue(value)
    end
    return true  -- pas de système de secrets → toujours safe
end

-- Constantes visuelles
local BAR_TEXTURE   = "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\ToxiUI-clean.tga"
local BEBAS_FONT    = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\BebasNeue-Regular.ttf"
local DARK          = 14/255

-- Couleurs par type de cast cible
local COLOR_INTERRUPTIBLE    = { 0, 0.78, 0.78, 1 }   -- turquoise
local COLOR_IMPORTANT        = { 0.855, 0.239, 1, 1 }  -- #DA3DFF
local COLOR_NOT_INTERRUPTIBLE = { 0.765, 0.294, 0.290, 1 } -- #C34B4A
local COLOR_CHANNELING       = { 0.506, 0.788, 0.243, 1 } -- #81C93E

-- Helpers
local frame = nil
local dragUnlocked = false

local state = {
    active     = false,
    channeling = false,
    startTime  = 0,
    endTime    = 0,
    name       = "",
    preview    = false,
    rawNotInterruptible = nil,  -- valeur brute (possiblement secret boolean TWW)
    rawImportant        = nil,  -- valeur brute de C_Spell.IsSpellImportant (secret)
    spellId    = nil,
    durationObj = nil,
    useTimerDuration = false,
}

local function Cfg()
    local db = ns.GetCfg("targetCastBar")
    return db or {}
end

local function FormatTime(t)
    if t >= 60 then
        return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
    elseif t >= 10 then
        return string.format("%d", math.floor(t))
    else
        return string.format("%.1f", t)
    end
end

-- Texte : ancre selon justify
local function TextAnchor(justify)
    if justify == "LEFT"  then return "BOTTOMLEFT",  "TOPLEFT"  end
    if justify == "RIGHT" then return "BOTTOMRIGHT", "TOPRIGHT" end
    return "BOTTOM", "TOP"
end

-- Couleur selon type de cast : secret booleans TWW illisibles -> overlay StatusBar pilotée par SetAlphaFromBoolean.

-- Récupère la valeur brute de C_Spell.IsSpellImportant (possiblement secret boolean)
local function GetRawImportant(spellId)
    if not spellId then return nil end
    if C_Spell and C_Spell.IsSpellImportant then
        local ok, result = pcall(C_Spell.IsSpellImportant, spellId)
        if ok then return result end
    end
    return nil
end

-- Couleur de base (sans l'état notInterruptible/important, gérés par overlay)
local function GetBaseBarColor(channeling)
    local cfg = Cfg()
    if channeling then
        return cfg.colorChanneling or COLOR_CHANNELING
    else
        return cfg.colorInterruptible or COLOR_INTERRUPTIBLE
    end
end

-- Applique l'alpha overlay selon rawNI (nil / bool lua / secret boolean TWW).
local function SetOverlayAlpha(widget, rawNI)
    if not widget then return end
    if rawNI == nil then
        widget:SetAlpha(0)
    elseif _issecretvalue and _issecretvalue(rawNI) then
        if widget.SetAlphaFromBoolean then
            widget:SetAlphaFromBoolean(rawNI)
        else
            widget:SetAlpha(0)
        end
    else
        widget:SetAlpha(rawNI and 1 or 0)
    end
end

local function ApplyNotInterruptibleOverlay(rawNI)
    if not frame then return end
    SetOverlayAlpha(frame.notIntBar, rawNI)
    SetOverlayAlpha(frame.notIntNameFrame, rawNI)
    SetOverlayAlpha(frame.notIntTimerFrame, rawNI)
end

local function ApplyImportantOverlay(rawImp)
    if not frame then return end
    SetOverlayAlpha(frame.impBar, rawImp)
    SetOverlayAlpha(frame.impNameFrame, rawImp)
    SetOverlayAlpha(frame.impTimerFrame, rawImp)
end

local function ApplyBarColor()
    if not frame then return end
    local cfg = Cfg()

    -- Couleur de base (turquoise / vert channeling)
    local c = GetBaseBarColor(state.channeling)
    frame.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)

    -- Overlay rouge pour non-interruptible
    if frame.notIntBar then
        local ni = cfg.colorNotInterruptible or COLOR_NOT_INTERRUPTIBLE
        frame.notIntBar:SetStatusBarColor(ni[1], ni[2], ni[3], ni[4] or 1)
        ApplyNotInterruptibleOverlay(state.rawNotInterruptible)
    end

    -- Overlay rose pour sorts importants (priorité max, par-dessus le rouge)
    if frame.impBar then
        local imp = cfg.colorImportant or COLOR_IMPORTANT
        frame.impBar:SetStatusBarColor(imp[1], imp[2], imp[3], imp[4] or 1)
        ApplyImportantOverlay(state.rawImportant)
    end
end

-- Icône du sort
local function UpdateIcon()
    if not frame or not frame.icon then return end
    local cfg = Cfg()
    if not cfg.showIcon then
        frame.icon:Hide()
        return
    end
    if state.spellId then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(state.spellId)
        local tex = info and info.iconID
        if tex then
            frame.icon:SetTexture(tex)
            frame.icon:Show()
            return
        end
    end
    frame.icon:Hide()
end

-- Mise à jour du progrès (OnUpdate)
local function UpdateProgress()
    if not frame then return end
    local now = GetTime()

    if state.active then
        -- SetTimerDuration : Blizzard gère le progrès, on met juste à jour texte/spark.
        if state.useTimerDuration and state.durationObj then
            -- Timer texte recalculé depuis startTime/endTime (GetRemainingDuration est secret).
            local total = state.endTime - state.startTime
            if total <= 0 then total = 1 end
            local elapsed = now - state.startTime
            local progress

            if state.channeling then
                progress = 1 - (elapsed / total)
            else
                progress = elapsed / total
            end
            progress = math.max(0, math.min(1, progress))

            -- Timer
            local remaining = state.endTime - now
            if remaining < 0 then remaining = 0 end
            frame.timerTxt:SetText(FormatTime(remaining))
            if frame.notIntTimerTxt then frame.notIntTimerTxt:SetText(FormatTime(remaining)) end
            if frame.impTimerTxt then frame.impTimerTxt:SetText(FormatTime(remaining)) end

            -- Fin naturelle
            if now >= state.endTime then
                if state.preview then
                    local dur = 2 + math.random() * 2
                    state.startTime = now
                    state.endTime   = now + dur
                else
                    state.active = false
                    frame:Hide()
                end
            end
        else
            -- Fallback classique (pas de SetTimerDuration)
            local total = state.endTime - state.startTime
            if total <= 0 then total = 1 end
            local elapsed = now - state.startTime
            local progress

            if state.channeling then
                progress = 1 - (elapsed / total)
            else
                progress = elapsed / total
            end
            progress = math.max(0, math.min(1, progress))

            frame.bar:SetValue(progress)
            if frame.notIntBar then frame.notIntBar:SetValue(progress) end
            if frame.impBar then frame.impBar:SetValue(progress) end

            -- Timer
            local remaining = state.endTime - now
            if remaining < 0 then remaining = 0 end
            frame.timerTxt:SetText(FormatTime(remaining))
            if frame.notIntTimerTxt then frame.notIntTimerTxt:SetText(FormatTime(remaining)) end
            if frame.impTimerTxt then frame.impTimerTxt:SetText(FormatTime(remaining)) end

            -- Fin naturelle
            if now >= state.endTime then
                if state.preview then
                    local dur = 2 + math.random() * 2
                    state.startTime = now
                    state.endTime   = now + dur
                else
                    state.active = false
                    frame:Hide()
                end
            end
        end
    end
end

-- Démarrage/arrêt : cast times secrets, recalculés via UnitCastingDuration/UnitChannelDuration (comme Platynator).

-- Retourne (cs, ce) en secondes GetTime() et stocke l'objet duration TWW pour SetTimerDuration.
local function GetCastTimeBounds(spellId, isChannel)
    local now = GetTime()
    state.durationObj = nil
    state.useTimerDuration = false

    local durApi = isChannel and UnitChannelDuration or UnitCastingDuration
    if durApi then
        local durObj = durApi("target")
        if durObj then
            state.durationObj = durObj
            -- Extraire total/elapsed pour le timer texte et spark
            local ok1, total   = pcall(function() return durObj:GetTotalDuration() end)
            local ok2, elapsed = pcall(function() return durObj:GetElapsedDuration() end)
            -- Vérifier que ce sont des nombres normaux (pas des secrets)
            local totalOk  = ok1 and total  and (not _issecretvalue or not _issecretvalue(total))
            local elapOk   = ok2 and elapsed and (not _issecretvalue or not _issecretvalue(elapsed))
            if totalOk and type(total) == "number" and total > 0 then
                local e = (elapOk and type(elapsed) == "number") and elapsed or 0
                return now - e, now - e + total
            end
            -- Secrets : fallback durée C_Spell, mais on garde durationObj pour SetTimerDuration
        end
    end
    -- Fallback : durée de base depuis C_Spell.GetSpellInfo (sans haste)
    local dur = 3
    if spellId then
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellId)
            if ok and info and type(info.castTime) == "number" then
                local ok2, ct = pcall(function() return math.floor(info.castTime + 0) end)
                if ok2 and ct and ct > 0 then dur = ct / 1000 end
            end
        end
        if dur == 3 then
            local ok, _, _, _, castTime = pcall(GetSpellInfo, spellId)
            if ok and type(castTime) == "number" then
                local ok2, ct = pcall(function() return math.floor(castTime + 0) end)
                if ok2 and ct and ct > 0 then dur = ct / 1000 end
            end
        end
    end
    return now, now + dur
end

local function StartCast(name, spellId, notInterruptible)
    if not frame then return end
    local cfg = Cfg()
    if cfg.enabled == false then return end

    local cs, ce = GetCastTimeBounds(spellId, false)

    state.active           = true
    state.channeling       = false
    state.startTime        = cs
    state.endTime          = ce
    state.name             = name or ""
    state.spellId              = spellId
    state.rawNotInterruptible  = notInterruptible
    state.rawImportant         = GetRawImportant(spellId)

    -- Utilise SetTimerDuration si l'objet duration est disponible
    if state.durationObj and frame.bar.SetTimerDuration then
        state.useTimerDuration = true
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetTimerDuration(state.durationObj, nil, Enum.StatusBarTimerDirection.ElapsedTime)
        if frame.notIntBar then
            frame.notIntBar:SetMinMaxValues(0, 1)
            frame.notIntBar:SetTimerDuration(state.durationObj, nil, Enum.StatusBarTimerDirection.ElapsedTime)
        end
        if frame.impBar then
            frame.impBar:SetMinMaxValues(0, 1)
            frame.impBar:SetTimerDuration(state.durationObj, nil, Enum.StatusBarTimerDirection.ElapsedTime)
        end
    else
        state.useTimerDuration = false
    end

    ApplyBarColor()
    UpdateIcon()
    frame.nameTxt:SetText(state.name)
    if frame.notIntNameTxt then frame.notIntNameTxt:SetText(state.name) end
    if frame.impNameTxt then frame.impNameTxt:SetText(state.name) end
    frame:Show()
    UpdateProgress()
end

local function StartChannel(name, spellId, notInterruptible)
    if not frame then return end
    local cfg = Cfg()
    if cfg.enabled == false then return end

    local cs, ce = GetCastTimeBounds(spellId, true)

    state.active               = true
    state.channeling           = true
    state.startTime            = cs
    state.endTime              = ce
    state.name                 = name or ""
    state.spellId              = spellId
    state.rawNotInterruptible  = notInterruptible
    state.rawImportant         = GetRawImportant(spellId)

    -- Utilise SetTimerDuration si l'objet duration est disponible
    if state.durationObj and frame.bar.SetTimerDuration then
        state.useTimerDuration = true
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetTimerDuration(state.durationObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
        if frame.notIntBar then
            frame.notIntBar:SetMinMaxValues(0, 1)
            frame.notIntBar:SetTimerDuration(state.durationObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
        end
        if frame.impBar then
            frame.impBar:SetMinMaxValues(0, 1)
            frame.impBar:SetTimerDuration(state.durationObj, nil, Enum.StatusBarTimerDirection.RemainingTime)
        end
    else
        state.useTimerDuration = false
    end

    ApplyBarColor()
    UpdateIcon()
    frame.nameTxt:SetText(state.name)
    if frame.notIntNameTxt then frame.notIntNameTxt:SetText(state.name) end
    if frame.impNameTxt then frame.impNameTxt:SetText(state.name) end
    frame:Show()
    UpdateProgress()
end

local function StopCast()
    if not frame then return end
    if state.preview then return end
    state.active = false
    state.rawNotInterruptible = nil
    state.rawImportant = nil
    frame.bar:SetValue(0)
    if frame.notIntBar then frame.notIntBar:SetValue(0); frame.notIntBar:SetAlpha(0) end
    if frame.notIntNameFrame then frame.notIntNameFrame:SetAlpha(0) end
    if frame.notIntNameTxt then frame.notIntNameTxt:SetText("") end
    if frame.notIntTimerFrame then frame.notIntTimerFrame:SetAlpha(0) end
    if frame.notIntTimerTxt then frame.notIntTimerTxt:SetText("") end
    if frame.impBar then frame.impBar:SetValue(0); frame.impBar:SetAlpha(0) end
    if frame.impNameFrame then frame.impNameFrame:SetAlpha(0) end
    if frame.impNameTxt then frame.impNameTxt:SetText("") end
    if frame.impTimerFrame then frame.impTimerFrame:SetAlpha(0) end
    if frame.impTimerTxt then frame.impTimerTxt:SetText("") end
    frame.timerTxt:SetText("")
    frame.nameTxt:SetText("")
    frame:Hide()
end

local function InterruptCast()
    if not frame then return end
    if state.preview then return end
    state.active = false
    frame.timerTxt:SetText("")

    frame.bar:SetStatusBarColor(0.85, 0.15, 0.10, 1)
    if frame.notIntBar then frame.notIntBar:SetAlpha(0) end
    if frame.notIntNameFrame then frame.notIntNameFrame:SetAlpha(0) end
    if frame.notIntTimerFrame then frame.notIntTimerFrame:SetAlpha(0) end
    if frame.impBar then frame.impBar:SetAlpha(0) end
    if frame.impNameFrame then frame.impNameFrame:SetAlpha(0) end
    if frame.impTimerFrame then frame.impTimerFrame:SetAlpha(0) end
    frame.nameTxt:SetText(L["CASTBAR_INTERRUPTED"])
    frame.nameTxt:SetTextColor(0.90, 0.25, 0.15, 1)
    frame:Show()

    C_Timer.After(0.9, function()
        if not frame then return end
        if state.active then return end
        frame.bar:SetValue(0)
        frame.nameTxt:SetText("")
        frame.nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
        frame:Hide()
    end)
end

-- Détection de cast/channel en cours (TARGET_CHANGED)
local function CheckTargetCast()
    if not frame then return end
    local cfg = Cfg()
    if cfg.enabled == false then return end

    -- Cast normal
    local name, _, _, _, _, _, _, notInt, sid = UnitCastingInfo("target")
    if name then
        StartCast(name, sid, notInt)
        return
    end

    -- Canal (UnitChannelInfo n'a pas de castID → spellID est en position 8)
    name, _, _, _, _, _, notInt, sid = UnitChannelInfo("target")
    if name then
        StartChannel(name, sid, notInt)
        return
    end

    -- Rien
    StopCast()
end

-- Création de la barre
function TargetCastBar.Create(parent)
    if frame then return end

    local cfg = Cfg()
    local w   = cfg.width  or 260
    local h   = cfg.height or 3
    local pt  = cfg.point         or "BOTTOM"
    local rpt = cfg.relativePoint or "CENTER"
    local x   = cfg.x      or 260
    local y   = cfg.y      or -120

    -- Frame racine
    frame = CreateFrame("Frame", "AishCoreTargetCastBar", UIParent)
    frame:SetSize(w, h + 30)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", function(self)
        if not dragUnlocked then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not ns.DB             then ns.DB = {} end
        if not ns.DB.targetCastBar then ns.DB.targetCastBar = {} end
        -- Sauvegarder point+relativePoint (pas juste x/y) : StopMovingOrSizing peut re-ancrer ailleurs (cf. CastBar.lua).
        local point, _, relativePoint, ox, oy = self:GetPoint(1)
        ns.DB.targetCastBar.point         = point
        ns.DB.targetCastBar.relativePoint = relativePoint
        ns.DB.targetCastBar.x = ox
        ns.DB.targetCastBar.y = oy
    end)
    frame:SetPoint(pt, UIParent, rpt, x, y)
    frame:Hide()

    -- Fond
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgTex:SetSize(w, h)
    bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bgTex:SetColorTexture(DARK, DARK, DARK, 1)
    frame.bgTex = bgTex

    -- Bordure
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetPoint("TOPLEFT",     bgTex, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMRIGHT",  1, -1)
    border:SetColorTexture(DARK, DARK, DARK, 1)
    frame.border = border

    -- StatusBar
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetSize(w, h)
    sb:SetPoint("TOPLEFT", bgTex)
    sb:SetStatusBarTexture(BAR_TEXTURE)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetStatusBarColor(unpack(COLOR_INTERRUPTIBLE))
    frame.bar = sb

    -- Overlay StatusBar pour casts non-interruptibles (même taille/position que sb, alpha 0 par défaut)
    local niBar = CreateFrame("StatusBar", nil, frame)
    niBar:SetSize(w, h)
    niBar:SetPoint("TOPLEFT", bgTex)
    niBar:SetStatusBarTexture(BAR_TEXTURE)
    niBar:SetMinMaxValues(0, 1)
    niBar:SetValue(0)
    niBar:SetStatusBarColor(unpack(COLOR_NOT_INTERRUPTIBLE))
    niBar:SetFrameLevel(sb:GetFrameLevel() + 1)
    niBar:SetAlpha(0)
    frame.notIntBar = niBar

    -- Overlay StatusBar pour les sorts importants (rose, priorité max)
    local impBar = CreateFrame("StatusBar", nil, frame)
    impBar:SetSize(w, h)
    impBar:SetPoint("TOPLEFT", bgTex)
    impBar:SetStatusBarTexture(BAR_TEXTURE)
    impBar:SetMinMaxValues(0, 1)
    impBar:SetValue(0)
    impBar:SetStatusBarColor(unpack(COLOR_IMPORTANT))
    impBar:SetFrameLevel(sb:GetFrameLevel() + 2)
    impBar:SetAlpha(0)
    frame.impBar = impBar

    -- Icône du sort (à gauche de la barre)
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetSize(h + 12, h + 12)
    icon:SetPoint("RIGHT", bgTex, "LEFT", -4, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    frame.icon = icon

    -- Texte nom du sort
    local nSize    = cfg.nameSize    or 12
    local nOffX    = cfg.nameOffX    or 0
    local nOffY    = cfg.nameOffY    or 9
    local nJustify = cfg.nameJustify or "CENTER"
    local nSelf, nRel = TextAnchor(nJustify)
    local nameTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.nameTxtSlug = ns.CreateSlugRing(frame, nameTxt)
    ns.ApplyTextOutlineStyle(nameTxt, frame.nameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
    nameTxt:SetJustifyH(nJustify)
    nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
    nameTxt:SetWidth(w)
    nameTxt:SetPoint(nSelf, bgTex, nRel, nOffX, nOffY)
    nameTxt:SetText("")
    frame.nameTxt = nameTxt

    -- Overlay texte nom (rouge non-interruptible), wrappé dans un Frame car SetAlphaFromBoolean n'existe que sur Frame
    local niNameFrame = CreateFrame("Frame", nil, frame)
    niNameFrame:SetAllPoints(frame)
    niNameFrame:SetFrameLevel(sb:GetFrameLevel() + 2)
    niNameFrame:SetAlpha(0)
    local niNameTxt = niNameFrame:CreateFontString(nil, "OVERLAY")
    -- Meme anneau SLUG que nameTxt (evite l'ombre directionnelle asymetrique), parente a niNameFrame pour suivre son fondu d'alpha.
    frame.notIntNameTxtSlug = ns.CreateSlugRing(niNameFrame, niNameTxt)
    ns.ApplyTextOutlineStyle(niNameTxt, frame.notIntNameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
    niNameTxt:SetJustifyH(nJustify)
    niNameTxt:SetTextColor(COLOR_NOT_INTERRUPTIBLE[1], COLOR_NOT_INTERRUPTIBLE[2], COLOR_NOT_INTERRUPTIBLE[3], 1)
    niNameTxt:SetWidth(w)
    niNameTxt:SetPoint(nSelf, bgTex, nRel, nOffX, nOffY)
    niNameTxt:SetText("")
    frame.notIntNameFrame = niNameFrame
    frame.notIntNameTxt   = niNameTxt

    -- Overlay texte nom (rose important, wrappé dans un Frame)
    local impNameFrame = CreateFrame("Frame", nil, frame)
    impNameFrame:SetAllPoints(frame)
    impNameFrame:SetFrameLevel(sb:GetFrameLevel() + 3)
    impNameFrame:SetAlpha(0)
    local impNameTxt = impNameFrame:CreateFontString(nil, "OVERLAY")
    -- Meme anneau SLUG que nameTxt, meme raison que notIntNameTxtSlug (evite l'ombre directionnelle fixe)
    frame.impNameTxtSlug = ns.CreateSlugRing(impNameFrame, impNameTxt)
    ns.ApplyTextOutlineStyle(impNameTxt, frame.impNameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
    impNameTxt:SetJustifyH(nJustify)
    impNameTxt:SetTextColor(COLOR_IMPORTANT[1], COLOR_IMPORTANT[2], COLOR_IMPORTANT[3], 1)
    impNameTxt:SetWidth(w)
    impNameTxt:SetPoint(nSelf, bgTex, nRel, nOffX, nOffY)
    impNameTxt:SetText("")
    frame.impNameFrame = impNameFrame
    frame.impNameTxt   = impNameTxt

    -- Texte timer
    local tSize    = cfg.timerSize    or 8
    local tOffX    = cfg.timerOffX    or 1
    local tOffY    = cfg.timerOffY    or 2
    local tJustify = cfg.timerJustify or "RIGHT"
    local tSelf, tRel = TextAnchor(tJustify)
    local timerTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.timerTxtSlug = ns.CreateSlugRing(frame, timerTxt)
    ns.ApplyTextOutlineStyle(timerTxt, frame.timerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    timerTxt:SetJustifyH(tJustify)
    timerTxt:SetTextColor(0.847, 0.627, 0.380, 1)
    timerTxt:SetWidth(w)
    timerTxt:SetPoint(tSelf, bgTex, tRel, tOffX, tOffY)
    timerTxt:SetText("")
    frame.timerTxt = timerTxt

    -- Overlay texte timer (rouge non-interruptible, wrappé dans un Frame)
    local niTimerFrame = CreateFrame("Frame", nil, frame)
    niTimerFrame:SetAllPoints(frame)
    niTimerFrame:SetFrameLevel(sb:GetFrameLevel() + 2)
    niTimerFrame:SetAlpha(0)
    local niTimerTxt = niTimerFrame:CreateFontString(nil, "OVERLAY")
    frame.notIntTimerTxtSlug = ns.CreateSlugRing(niTimerFrame, niTimerTxt)
    ns.ApplyTextOutlineStyle(niTimerTxt, frame.notIntTimerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    niTimerTxt:SetJustifyH(tJustify)
    niTimerTxt:SetTextColor(COLOR_NOT_INTERRUPTIBLE[1], COLOR_NOT_INTERRUPTIBLE[2], COLOR_NOT_INTERRUPTIBLE[3], 1)
    niTimerTxt:SetWidth(w)
    niTimerTxt:SetPoint(tSelf, bgTex, tRel, tOffX, tOffY)
    niTimerTxt:SetText("")
    niTimerFrame:SetAlpha(0)
    frame.notIntTimerFrame = niTimerFrame
    frame.notIntTimerTxt   = niTimerTxt

    -- Overlay texte timer (rose important, wrappé dans un Frame)
    local impTimerFrame = CreateFrame("Frame", nil, frame)
    impTimerFrame:SetAllPoints(frame)
    impTimerFrame:SetFrameLevel(sb:GetFrameLevel() + 3)
    impTimerFrame:SetAlpha(0)
    local impTimerTxt = impTimerFrame:CreateFontString(nil, "OVERLAY")
    frame.impTimerTxtSlug = ns.CreateSlugRing(impTimerFrame, impTimerTxt)
    ns.ApplyTextOutlineStyle(impTimerTxt, frame.impTimerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    impTimerTxt:SetJustifyH(tJustify)
    impTimerTxt:SetTextColor(COLOR_IMPORTANT[1], COLOR_IMPORTANT[2], COLOR_IMPORTANT[3], 1)
    impTimerTxt:SetWidth(w)
    impTimerTxt:SetPoint(tSelf, bgTex, tRel, tOffX, tOffY)
    impTimerTxt:SetText("")
    impTimerFrame:SetAlpha(0)
    frame.impTimerFrame = impTimerFrame
    frame.impTimerTxt   = impTimerTxt

    -- OnUpdate
    frame:SetScript("OnUpdate", UpdateProgress)

    -- Événements cible
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_SPELLCAST_START")
    ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    ev:RegisterEvent("UNIT_SPELLCAST_STOP")
    ev:RegisterEvent("UNIT_SPELLCAST_FAILED")
    ev:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    ev:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    ev:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            CheckTargetCast()
            return
        end

        if unit and unit ~= "target" then return end

        if event == "UNIT_SPELLCAST_START" then
            local name, _, _, _, _, _, _, notInt, sid = UnitCastingInfo("target")
            if name then
                StartCast(name, sid, notInt)
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            local name, _, _, _, _, _, notInt, sid = UnitChannelInfo("target")
            if name then
                StartChannel(name, sid, notInt)
            end

        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            InterruptCast()

        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            StopCast()

        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE"
            or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            -- L'état interruptible a changé en cours de cast (bool Lua normal)
            state.rawNotInterruptible = (event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
            ApplyBarColor()
        end
    end)
end

function TargetCastBar.SetDragUnlocked(val)
    dragUnlocked = val and true or false
end

-- ApplySettings
function TargetCastBar.ApplySettings()
    if not frame then return end

    local cfg = Cfg()
    local w   = cfg.width  or 260
    local h   = cfg.height or 3
    local pt  = cfg.point         or "BOTTOM"
    local rpt = cfg.relativePoint or "CENTER"
    local x   = cfg.x      or 260
    local y   = cfg.y      or -120

    frame:SetSize(w, h + 30)

    frame.bgTex:SetSize(w, h)
    frame.bgTex:ClearAllPoints()
    frame.bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    frame.bar:SetSize(w, h)
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", frame.bgTex)

    if frame.notIntBar then
        frame.notIntBar:SetSize(w, h)
        frame.notIntBar:ClearAllPoints()
        frame.notIntBar:SetPoint("TOPLEFT", frame.bgTex)
    end
    if frame.impBar then
        frame.impBar:SetSize(w, h)
        frame.impBar:ClearAllPoints()
        frame.impBar:SetPoint("TOPLEFT", frame.bgTex)
    end
    ApplyBarColor()

    -- Icône
    if frame.icon then
        frame.icon:SetSize(h + 12, h + 12)
        if cfg.showIcon then
            UpdateIcon()
        else
            frame.icon:Hide()
        end
    end

    -- Texte nom
    local nSize    = cfg.nameSize    or 12
    local nOffX    = cfg.nameOffX    or 0
    local nOffY    = cfg.nameOffY    or 9
    local nJustify = cfg.nameJustify or "CENTER"
    local nSelf, nRel = TextAnchor(nJustify)
    ns.ApplyTextOutlineStyle(frame.nameTxt, frame.nameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
    frame.nameTxt:SetJustifyH(nJustify)
    frame.nameTxt:SetWidth(w)
    frame.nameTxt:ClearAllPoints()
    frame.nameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)

    if frame.notIntNameTxt then
        ns.ApplyTextOutlineStyle(frame.notIntNameTxt, frame.notIntNameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
        frame.notIntNameTxt:SetJustifyH(nJustify)
        frame.notIntNameTxt:SetWidth(w)
        frame.notIntNameTxt:ClearAllPoints()
        frame.notIntNameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)
    end

    if frame.impNameTxt then
        ns.ApplyTextOutlineStyle(frame.impNameTxt, frame.impNameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
        frame.impNameTxt:SetJustifyH(nJustify)
        frame.impNameTxt:SetWidth(w)
        frame.impNameTxt:ClearAllPoints()
        frame.impNameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)
    end

    -- Texte timer
    local tSize    = cfg.timerSize    or 8
    local tOffX    = cfg.timerOffX    or 1
    local tOffY    = cfg.timerOffY    or 2
    local tJustify = cfg.timerJustify or "RIGHT"
    local tSelf, tRel = TextAnchor(tJustify)
    ns.ApplyTextOutlineStyle(frame.timerTxt, frame.timerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    frame.timerTxt:SetJustifyH(tJustify)
    frame.timerTxt:SetWidth(w)
    frame.timerTxt:ClearAllPoints()
    frame.timerTxt:SetPoint(tSelf, frame.bgTex, tRel, tOffX, tOffY)

    if frame.notIntTimerTxt then
        ns.ApplyTextOutlineStyle(frame.notIntTimerTxt, frame.notIntTimerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
        frame.notIntTimerTxt:SetJustifyH(tJustify)
        frame.notIntTimerTxt:SetWidth(w)
        frame.notIntTimerTxt:ClearAllPoints()
        frame.notIntTimerTxt:SetPoint(tSelf, frame.bgTex, tRel, tOffX, tOffY)
    end

    if frame.impTimerTxt then
        ns.ApplyTextOutlineStyle(frame.impTimerTxt, frame.impTimerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
        frame.impTimerTxt:SetJustifyH(tJustify)
        frame.impTimerTxt:SetWidth(w)
        frame.impTimerTxt:ClearAllPoints()
        frame.impTimerTxt:SetPoint(tSelf, frame.bgTex, tRel, tOffX, tOffY)
    end

    -- Position
    frame:ClearAllPoints()
    frame:SetPoint(pt, UIParent, rpt, x, y)

    -- Preview sauf si module desactive (LiveApply peut rappeler ApplySettings pendant la preview, cf. CastBar.lua).
    if state.preview then
        if cfg.enabled == false then
            frame:Hide()
        else
            frame:Show()
            frame.nameTxt:SetText(state.name or L["CASTBAR_PREVIEW_SPELL_NAME"])
            frame.timerTxt:SetText(FormatTime(math.max(0, state.endTime - GetTime())))
        end
    end
end

-- Preview
function TargetCastBar.SetPreview(on)
    if not frame then return end
    -- Meme garde que CastBar.SetPreview : module desactive = jamais de preview.
    if on and ns.GetCfg("targetCastBar").enabled == false then return end
    state.preview = on
    if on then
        state.active           = true
        state.channeling       = false
        state.startTime        = GetTime() - 0.9
        state.endTime          = GetTime() + 2.1
        state.name                 = L["TARGETCAST_PREVIEW_SPELL_NAME"]
        state.spellId              = nil
        state.rawNotInterruptible  = false
        state.rawImportant         = nil
        state.useTimerDuration     = false
        ApplyBarColor()
        frame.nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
        frame.nameTxt:SetText(L["TARGETCAST_PREVIEW_SPELL_NAME"])
        if frame.notIntNameTxt then frame.notIntNameTxt:SetText(L["TARGETCAST_PREVIEW_SPELL_NAME"]) end
        if frame.impNameTxt then frame.impNameTxt:SetText(L["TARGETCAST_PREVIEW_SPELL_NAME"]) end
        frame.timerTxt:SetText("2.1")
        if frame.notIntTimerTxt then frame.notIntTimerTxt:SetText("2.1") end
        if frame.impTimerTxt then frame.impTimerTxt:SetText("2.1") end
        frame.bar:SetValue(0.3)
        frame:Show()
    else
        state.spellId = nil
        state.rawImportant = nil
        -- Vérifier si un vrai cast de cible est en cours
        if not (UnitCastingInfo("target") or UnitChannelInfo("target")) then
            state.active = false
            frame.bar:SetValue(0)
            frame.nameTxt:SetText("")
            frame.timerTxt:SetText("")
            frame:Hide()
        else
            CheckTargetCast()
        end
    end
end

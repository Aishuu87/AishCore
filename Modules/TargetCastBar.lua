-- TargetCastBar.lua : barres de cast d'une unite autre que le joueur -- cible (ns.Modules.TargetCastBar) et focus
-- (ns.Modules.FocusCastBar). Un meme code, une instance par unite (NewUnitCastBar, en bas du fichier) : chaque
-- instance a sa frame, son etat et sa table de reglages (targetCastBar / focusCastBar).
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}

-- Wrapper taint-safe pour secret values (issecretvalue, WoW 11.0.5+, même approche qu'ElvUI/oUF).
local _issecretvalue = issecretvalue
local function IsSafeValue(value)
    if _issecretvalue then
        return not _issecretvalue(value)
    end
    return true  -- pas de système de secrets → toujours safe
end

local function NewUnitCastBar(UNIT, CFG_KEY, FRAME_NAME, CHANGED_EVENT, PREVIEW_NAME_KEY)
local TargetCastBar = {}

-- Constantes visuelles
-- Texture de la barre : cle de config resolue a chaque appel (ns.BAR_TEXTURES),
-- pour que le choix du dropdown s'applique sans /reload.
local function BarTex()
    return ns.ResolveBarTexFromKey((ns.GetCfg(CFG_KEY) or {}).barTexture)
end
local DEFAULT_FONT    = ns.FONT_FALLBACK  -- police du jeu (2002), aucune media pack requise
local DARK          = 14/255

-- Couleurs par type de cast cible
local COLOR_INTERRUPTIBLE    = { 0, 0.78, 0.78, 1 }   -- turquoise
local COLOR_IMPORTANT        = { 0.855, 0.239, 1, 1 }  -- #DA3DFF
local COLOR_NOT_INTERRUPTIBLE = { 0.765, 0.294, 0.290, 1 } -- #C34B4A
local COLOR_CHANNELING       = { 0.506, 0.788, 0.243, 1 } -- #81C93E

local NAME_COLOR  = { 0.792, 0.639, 0.392, 1 }
local TIMER_COLOR = { 0.847, 0.627, 0.380, 1 }

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
    local db = ns.GetCfg(CFG_KEY)
    return db or {}
end

local function NameColor() return Cfg().nameColor or NAME_COLOR end
local function TimerColor() return Cfg().timerColor or TIMER_COLOR end

-- Etincelle : memes textures que la barre du joueur (CastBar.SPARK_TEXTURES) ; "none" (defaut) = aucune
local function ApplySpark()
    if not frame or not frame.spark then return end
    local cfg = Cfg()
    local CB = ns.Modules.CastBar
    local TEX = CB and CB.SPARK_TEXTURES or {}
    local key = cfg.sparkTexture or "none"
    frame._noSpark = (key == "none") or not TEX[key]
    if frame._noSpark then frame.spark:Hide(); return end
    local t = TEX[key]
    local k = (tonumber(cfg.sparkSize) or 100) / 100
    frame.spark:SetTexture(t.path or ns.Media.circle)
    frame.spark:SetSize(t.w * k, t.h * k)
    local c = cfg.sparkColor or { 1, 0.867, 0.710, 1 }
    frame.spark:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- Etincelle au bord du remplissage (progress 0..1), selon le sens de remplissage
local function PlaceSpark(progress)
    if not frame or not frame.spark then return end
    if frame._noSpark then frame.spark:Hide(); return end
    local cfg = Cfg()
    local w = cfg.width or 260
    local x = (cfg.fillDir == "RTL") and (1 - progress) * w or progress * w
    frame.spark:ClearAllPoints()
    frame.spark:SetPoint("CENTER", frame.bgTex, "LEFT", x, 0)
    frame.spark:Show()
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

local TP_FLIP = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT" }
-- Texte : ancrage 9 points sur la barre + alignement (bord du texte pose sur l'ancre ; haut / bas : le texte est a
-- l'exterieur de la barre). Sans ancre enregistree, deduite de l'ancien alignement seul (au-dessus de la barre, a gauche
-- / au centre / a droite). Renvoie le point du texte et celui de la barre.
local function TextPoints(anchor, justify)
    justify = justify or "CENTER"
    if not anchor then
        anchor = (justify == "LEFT" and "TOPLEFT") or (justify == "RIGHT" and "TOPRIGHT") or "TOP"
    end
    local v = anchor:match("^TOP") or anchor:match("^BOTTOM") or ""
    local h = (justify == "CENTER") and "" or justify
    local p
    if v ~= "" then
        p = TP_FLIP[v] .. h
    else
        p = (h ~= "" and h) or (TP_FLIP[anchor:match("LEFT$") or anchor:match("RIGHT$") or ""] or "")
    end
    return (p ~= "" and p or "CENTER"), anchor
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

-- Icône du sort : à gauche, au milieu ou à droite de la barre (écart de 4 px hors de la barre), + décalage
local function LayoutIcon()
    if not frame or not frame.icon then return end
    local cfg = Cfg()
    local ox, oy = cfg.iconOffX or 0, cfg.iconOffY or 0
    ns.StyleCastIcon(frame.icon, frame.iconBorder, cfg)
    frame.icon:ClearAllPoints()
    if cfg.iconAnchor == "RIGHT" then
        frame.icon:SetPoint("LEFT", frame.bgTex, "RIGHT", 4 + ox, oy)
    elseif cfg.iconAnchor == "CENTER" then
        frame.icon:SetPoint("CENTER", frame.bgTex, "CENTER", ox, oy)
    else
        frame.icon:SetPoint("RIGHT", frame.bgTex, "LEFT", -4 + ox, oy)
    end
end

local function UpdateIcon()
    if not frame or not frame.icon then return end
    local cfg = Cfg()
    local tex
    if cfg.showIcon == false then   -- meme lecture que la case du GUI (cochee si absente)
        tex = nil
    elseif state.preview then
        tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(116))
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    elseif state.spellId then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(state.spellId)
        tex = info and info.iconID
    end
    if tex then
        frame.icon:SetTexture(tex)
        frame.icon:Show()
    else
        frame.icon:Hide()
    end
    ns.SyncCastIconBorder(frame.icon, frame.iconBorder, cfg)
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
            PlaceSpark(progress)

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
            PlaceSpark(progress)
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
        local durObj = durApi(UNIT)
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
    if frame.spark then frame.spark:Hide() end
    frame:Hide()
end

local function InterruptCast()
    if not frame then return end
    if state.preview then return end
    if Cfg().enabled == false then return end  -- module desactive : pas d'"Interrompu" non plus
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
    if frame.spark then frame.spark:Hide() end
    frame:Show()

    C_Timer.After(0.9, function()
        if not frame then return end
        if state.active then return end
        frame.bar:SetValue(0)
        frame.nameTxt:SetText("")
        local nc = NameColor()
        frame.nameTxt:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
        frame:Hide()
    end)
end

-- Détection de cast/channel en cours (TARGET_CHANGED)
-- Nom affiche d'un cast : 2e retour de UnitCastingInfo / UnitChannelInfo (celui de la barre Blizzard), repli sur le 1er.
-- Sorts techniques "... - No Text" (ex. "Opening - No Text" sur certains objets, Forever) : nom brut non traduit,
-- remplace par le sort "Ouverture" (6478) localise, sinon prive de son suffixe.
local function CastLabel(name, text)
    local label = name
    if type(text) == "string" and not (issecretvalue and issecretvalue(text)) and text ~= "" then label = text end
    if type(label) == "string" and not (issecretvalue and issecretvalue(label)) and label:find("%- No Text$") then
        local open = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(6478)
        if label:find("^Opening") and open and open ~= "" then return open end
        return (label:gsub("%s*%- No Text$", ""))
    end
    return label
end

local function CheckTargetCast()
    if not frame then return end
    local cfg = Cfg()
    if cfg.enabled == false then return end

    -- Cast normal
    local name, txt, _, _, _, _, _, notInt, sid = UnitCastingInfo(UNIT)
    if name then
        StartCast(CastLabel(name, txt), sid, notInt)
        return
    end

    -- Canal (UnitChannelInfo n'a pas de castID → spellID est en position 8)
    name, txt, _, _, _, _, notInt, sid = UnitChannelInfo(UNIT)
    if name then
        StartChannel(CastLabel(name, txt), sid, notInt)
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
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
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
        if not ns.DB[CFG_KEY] then ns.DB[CFG_KEY] = {} end
        -- Sauvegarder point+relativePoint (pas juste x/y) : StopMovingOrSizing peut re-ancrer ailleurs (cf. CastBar.lua).
        local point, _, relativePoint, ox, oy = self:GetPoint(1)
        ns.DB[CFG_KEY].point         = point
        ns.DB[CFG_KEY].relativePoint = relativePoint
        ns.DB[CFG_KEY].x = ox
        ns.DB[CFG_KEY].y = oy
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
    sb:SetStatusBarTexture(BarTex())
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetStatusBarColor(unpack(COLOR_INTERRUPTIBLE))
    frame.bar = sb

    -- Overlay StatusBar pour casts non-interruptibles (même taille/position que sb, alpha 0 par défaut)
    local niBar = CreateFrame("StatusBar", nil, frame)
    niBar:SetSize(w, h)
    niBar:SetPoint("TOPLEFT", bgTex)
    niBar:SetStatusBarTexture(BarTex())
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
    impBar:SetStatusBarTexture(BarTex())
    impBar:SetMinMaxValues(0, 1)
    impBar:SetValue(0)
    impBar:SetStatusBarColor(unpack(COLOR_IMPORTANT))
    impBar:SetFrameLevel(sb:GetFrameLevel() + 2)
    impBar:SetAlpha(0)
    frame.impBar = impBar
    local rtl = cfg.fillDir == "RTL"
    for _, b in ipairs({ sb, niBar, impBar }) do b:SetReverseFill(rtl) end

    -- Etincelle : au-dessus des remplissages, sous l'icone
    local sparkFrame = CreateFrame("Frame", nil, frame)
    sparkFrame:SetAllPoints(frame)
    sparkFrame:SetFrameLevel(sb:GetFrameLevel() + 3)
    local spark = sparkFrame:CreateTexture(nil, "OVERLAY")
    spark:SetBlendMode("ADD")
    spark:Hide()
    frame.spark = spark
    ApplySpark()

    -- Icône du sort : dans un cadre au-dessus des overlays (sinon cachée par le remplissage quand elle est au milieu)
    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetAllPoints(frame)
    iconFrame:SetFrameLevel(sb:GetFrameLevel() + 4)
    local icon = iconFrame:CreateTexture(nil, "OVERLAY")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    frame.icon = icon
    local iconBorder = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
    iconBorder:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
    iconBorder:Hide()
    frame.iconBorder = iconBorder
    LayoutIcon()

    -- Texte nom du sort
    local nSize    = cfg.nameSize    or 12
    local nOffX    = cfg.nameOffX    or 0
    local nOffY    = cfg.nameOffY    or 9
    local nJustify = cfg.nameJustify or "CENTER"
    local nSelf, nRel = TextPoints(cfg.nameAnchor, nJustify)
    local nameTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.nameTxtSlug = ns.CreateSlugRing(frame, nameTxt)
    ns.ApplyTextOutlineStyle(nameTxt, frame.nameTxtSlug, cfg.font or DEFAULT_FONT, nSize, cfg.nameOutlineStyle, true)
    nameTxt:SetJustifyH(nJustify)
    nameTxt:SetTextColor(unpack(NameColor()))
    nameTxt:SetWidth(0)
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
    ns.ApplyTextOutlineStyle(niNameTxt, frame.notIntNameTxtSlug, cfg.font or DEFAULT_FONT, nSize, cfg.nameOutlineStyle, true)
    niNameTxt:SetJustifyH(nJustify)
    niNameTxt:SetTextColor(COLOR_NOT_INTERRUPTIBLE[1], COLOR_NOT_INTERRUPTIBLE[2], COLOR_NOT_INTERRUPTIBLE[3], 1)
    niNameTxt:SetWidth(0)
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
    ns.ApplyTextOutlineStyle(impNameTxt, frame.impNameTxtSlug, cfg.font or DEFAULT_FONT, nSize, cfg.nameOutlineStyle, true)
    impNameTxt:SetJustifyH(nJustify)
    impNameTxt:SetTextColor(COLOR_IMPORTANT[1], COLOR_IMPORTANT[2], COLOR_IMPORTANT[3], 1)
    impNameTxt:SetWidth(0)
    impNameTxt:SetPoint(nSelf, bgTex, nRel, nOffX, nOffY)
    impNameTxt:SetText("")
    frame.impNameFrame = impNameFrame
    frame.impNameTxt   = impNameTxt

    -- Texte timer
    local tSize    = cfg.timerSize    or 8
    local tOffX    = cfg.timerOffX    or 1
    local tOffY    = cfg.timerOffY    or 2
    local tJustify = cfg.timerJustify or "RIGHT"
    local tSelf, tRel = TextPoints(cfg.timerAnchor, tJustify)
    local timerTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.timerTxtSlug = ns.CreateSlugRing(frame, timerTxt)
    ns.ApplyTextOutlineStyle(timerTxt, frame.timerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    timerTxt:SetJustifyH(tJustify)
    timerTxt:SetTextColor(unpack(TimerColor()))
    timerTxt:SetWidth(0)
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
    niTimerTxt:SetWidth(0)
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
    impTimerTxt:SetWidth(0)
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
    -- Recul : cast retarde par les coups recus (DELAYED), canal raccourci (CHANNEL_UPDATE)
    ev:RegisterEvent("UNIT_SPELLCAST_DELAYED")
    ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    ev:RegisterEvent(CHANGED_EVENT)
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == CHANGED_EVENT or event == "PLAYER_ENTERING_WORLD" then
            CheckTargetCast()
            return
        end

        if unit and unit ~= UNIT then return end

        if event == "UNIT_SPELLCAST_START" then
            local name, txt, _, _, _, _, _, notInt, sid = UnitCastingInfo(UNIT)
            if name then
                StartCast(CastLabel(name, txt), sid, notInt)
            end

        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            local name, txt, _, _, _, _, notInt, sid = UnitChannelInfo(UNIT)
            if name then
                StartChannel(CastLabel(name, txt), sid, notInt)
            end

        elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            -- Recul : nouvelle duree relue aupres du jeu (objet de duree ou bornes), meme sort, meme etat
            if state.active then
                local relaunch = state.channeling and StartChannel or StartCast
                relaunch(state.name, state.spellId, state.rawNotInterruptible)
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

    local barTex = BarTex()
    frame.bar:SetSize(w, h)
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", frame.bgTex)
    frame.bar:SetStatusBarTexture(barTex)

    if frame.notIntBar then
        frame.notIntBar:SetSize(w, h)
        frame.notIntBar:ClearAllPoints()
        frame.notIntBar:SetPoint("TOPLEFT", frame.bgTex)
        frame.notIntBar:SetStatusBarTexture(barTex)
    end
    if frame.impBar then
        frame.impBar:SetSize(w, h)
        frame.impBar:ClearAllPoints()
        frame.impBar:SetPoint("TOPLEFT", frame.bgTex)
        frame.impBar:SetStatusBarTexture(barTex)
    end
    local rtl = cfg.fillDir == "RTL"
    for _, b in ipairs({ frame.bar, frame.notIntBar or false, frame.impBar or false }) do
        if b then b:SetReverseFill(rtl) end
    end
    ApplyBarColor()
    ApplySpark()
    do
        local nc, tc = NameColor(), TimerColor()
        frame.nameTxt:SetTextColor(nc[1], nc[2], nc[3], nc[4] or 1)
        frame.timerTxt:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)
    end

    -- Icône
    LayoutIcon()
    UpdateIcon()

    -- Texte nom
    local nSize    = cfg.nameSize    or 12
    local nOffX    = cfg.nameOffX    or 0
    local nOffY    = cfg.nameOffY    or 9
    local nJustify = cfg.nameJustify or "CENTER"
    local nSelf, nRel = TextPoints(cfg.nameAnchor, nJustify)
    ns.ApplyTextOutlineStyle(frame.nameTxt, frame.nameTxtSlug, cfg.font or DEFAULT_FONT, nSize, cfg.nameOutlineStyle, true)
    frame.nameTxt:SetJustifyH(nJustify)
    frame.nameTxt:SetWidth(0)
    frame.nameTxt:ClearAllPoints()
    frame.nameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)

    if frame.notIntNameTxt then
        ns.ApplyTextOutlineStyle(frame.notIntNameTxt, frame.notIntNameTxtSlug, cfg.font or DEFAULT_FONT, nSize, cfg.nameOutlineStyle, true)
        frame.notIntNameTxt:SetJustifyH(nJustify)
        frame.notIntNameTxt:SetWidth(0)
        frame.notIntNameTxt:ClearAllPoints()
        frame.notIntNameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)
    end

    if frame.impNameTxt then
        ns.ApplyTextOutlineStyle(frame.impNameTxt, frame.impNameTxtSlug, cfg.font or DEFAULT_FONT, nSize, cfg.nameOutlineStyle, true)
        frame.impNameTxt:SetJustifyH(nJustify)
        frame.impNameTxt:SetWidth(0)
        frame.impNameTxt:ClearAllPoints()
        frame.impNameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)
    end

    -- Texte timer
    local tSize    = cfg.timerSize    or 8
    local tOffX    = cfg.timerOffX    or 1
    local tOffY    = cfg.timerOffY    or 2
    local tJustify = cfg.timerJustify or "RIGHT"
    local tSelf, tRel = TextPoints(cfg.timerAnchor, tJustify)
    ns.ApplyTextOutlineStyle(frame.timerTxt, frame.timerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    frame.timerTxt:SetJustifyH(tJustify)
    frame.timerTxt:SetWidth(0)
    frame.timerTxt:ClearAllPoints()
    frame.timerTxt:SetPoint(tSelf, frame.bgTex, tRel, tOffX, tOffY)

    if frame.notIntTimerTxt then
        ns.ApplyTextOutlineStyle(frame.notIntTimerTxt, frame.notIntTimerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
        frame.notIntTimerTxt:SetJustifyH(tJustify)
        frame.notIntTimerTxt:SetWidth(0)
        frame.notIntTimerTxt:ClearAllPoints()
        frame.notIntTimerTxt:SetPoint(tSelf, frame.bgTex, tRel, tOffX, tOffY)
    end

    if frame.impTimerTxt then
        ns.ApplyTextOutlineStyle(frame.impTimerTxt, frame.impTimerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
        frame.impTimerTxt:SetJustifyH(tJustify)
        frame.impTimerTxt:SetWidth(0)
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
    if on and ns.GetCfg(CFG_KEY).enabled == false then return end
    state.preview = on
    if on then
        state.active           = true
        state.channeling       = false
        state.startTime        = GetTime() - 0.9
        state.endTime          = GetTime() + 2.1
        state.name                 = L[PREVIEW_NAME_KEY]
        state.spellId              = nil
        state.rawNotInterruptible  = false
        state.rawImportant         = nil
        state.useTimerDuration     = false
        ApplyBarColor()
        UpdateIcon()
        frame.nameTxt:SetTextColor(unpack(NameColor()))
        frame.nameTxt:SetText(L[PREVIEW_NAME_KEY])
        if frame.notIntNameTxt then frame.notIntNameTxt:SetText(L[PREVIEW_NAME_KEY]) end
        if frame.impNameTxt then frame.impNameTxt:SetText(L[PREVIEW_NAME_KEY]) end
        frame.timerTxt:SetText("2.1")
        if frame.notIntTimerTxt then frame.notIntTimerTxt:SetText("2.1") end
        if frame.impTimerTxt then frame.impTimerTxt:SetText("2.1") end
        frame.bar:SetValue(0.3)
        PlaceSpark(0.3)
        frame:Show()
    else
        state.spellId = nil
        state.rawImportant = nil
        -- Vérifier si un vrai cast de cible est en cours
        if not (UnitCastingInfo(UNIT) or UnitChannelInfo(UNIT)) then
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

return TargetCastBar
end

ns.Modules.TargetCastBar = NewUnitCastBar("target", "targetCastBar", "AishCoreTargetCastBar", "PLAYER_TARGET_CHANGED", "TARGETCAST_PREVIEW_SPELL_NAME")
ns.Modules.FocusCastBar  = NewUnitCastBar("focus",  "focusCastBar",  "AishCoreFocusCastBar",  "PLAYER_FOCUS_CHANGED",  "FOCUSCAST_PREVIEW_SPELL_NAME")

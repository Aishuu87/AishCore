-- CastBar.lua : Barre de cast du joueur
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local CastBar = {}
ns.Modules.CastBar = CastBar

---------------------------------------------------------------------------
-- Constantes visuelles 
---------------------------------------------------------------------------
local BAR_TEXTURE   = "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\ToxiUI-clean.tga"
local BEBAS_FONT    = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\BebasNeue-Regular.ttf"
local DARK          = 14/255

local DEFAULTS = {
    enabled       = true,
    locked        = false,
    width         = 260,
    height        = 3,
    point         = "BOTTOM",
    relativePoint = "CENTER",
    x             = 0,
    y             = -120,
    barColor      = { 0.471, 0.392, 0.271, 1 },
    nameSize      = 12,
    nameOffX      = 0,
    nameOffY      = 9,
    nameJustify   = "CENTER",
    timerSize     = 8,
    timerOffX     = 1,
    timerOffY     = 2,
    timerJustify  = "RIGHT",
    colorBySchool = false,
    font      = nil,   -- nil = utilise BEBAS_FONT (BebasNeue)
    timerFont = nil,   -- nil = utilise ns.Media.font (Montserrat)
    timerOutlineStyle = "OUTLINE",
}

---------------------------------------------------------------------------
-- État courant du cast
---------------------------------------------------------------------------
local frame = nil

-- Déplacement autorisé uniquement quand le mode déplacer est activé
-- depuis le panel (bouton dédié). Verrouillé par défaut.
local dragUnlocked = false

-- GUID du cast en attente de PollStart (UnitChannelInfo pas encore disponible).
-- Bloque le Hide de StopCast tant qu'un PollStart est en vol.
local pendingGUID = nil

local state = {
    active     = false,
    channeling = false,
    startTime  = 0,
    endTime    = 0,
    name       = "",
    preview    = false,   -- true quand appelé depuis le GUI
    spellId    = nil,
    spellIcon  = nil,
    castGUID   = nil,     -- GUID du cast actif (anti race-condition STOP après START)
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Cfg()
    local db = ns.GetCfg("castBar")
    return db or DEFAULTS
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

---------------------------------------------------------------------------
-- Couleurs par école de magie (Libs/SpellSchools — spellId → gradient hex)
---------------------------------------------------------------------------
local function ParseGradient(gradient)
    if not gradient then return nil end
    local lhex, rhex = strsplit(":", gradient)
    rhex = rhex or lhex
    local lr = tonumber(string.sub(lhex,1,2),16) or 0
    local lg = tonumber(string.sub(lhex,3,4),16) or 0
    local lb = tonumber(string.sub(lhex,5,6),16) or 0
    local rr = tonumber(string.sub(rhex,1,2),16) or 0
    local rg = tonumber(string.sub(rhex,3,4),16) or 0
    local rb = tonumber(string.sub(rhex,5,6),16) or 0
    return CreateColor(lr/255, lg/255, lb/255, 1),
           CreateColor(rr/255, rg/255, rb/255, 1)
end

local function ResetBarGradient()
    local tex = frame and frame.bar and frame.bar:GetStatusBarTexture()
    if tex and tex.SetGradient then
        tex:SetGradient("HORIZONTAL", CreateColor(1,1,1,1), CreateColor(1,1,1,1))
    end
end

-- Gradients par école (bitmask → "leftHex:rightHex")
-- 1=Physical 2=Holy 4=Fire 8=Nature 16=Frost 32=Shadow 64=Arcane
local SCHOOL_GRADIENTS = {
    [2]  = "ffc539:ffffcb",  -- Holy
    [4]  = "ff5500:ffc20a",  -- Fire
    [8]  = "4caf50:a5d6a7",  -- Nature
    [16] = "76b9fd:d3fcff",  -- Frost
    [32] = "9c27b0:ce93d8",  -- Shadow
    [64] = "673ab7:b39ddb",  -- Arcane
    -- Combinaisons courantes (bit dominant)
    [6]  = "ff5500:ffc20a",  -- Fire+Holy   → Fire
    [18] = "76b9fd:d3fcff",  -- Frost+Holy  → Frost
    [36] = "9c27b0:ce93d8",  -- Shadow+Holy → Shadow
    [68] = "673ab7:b39ddb",  -- Arcane+Holy → Arcane
    [20] = "ff5500:ffc20a",  -- Fire+Holy+? → Fire
    [80] = "76b9fd:d3fcff",  -- Frost+Shadow → Frost
}

local function ApplyBarColor(spellId, spellName, spellIcon)
    if not frame then return end
    local cfg = Cfg()
    -- cf. Core.lua:ns.HasHeroicFeatures -- reglage reserve, ignore meme si
    -- colorBySchool=true est deja present dans la config (config importee,
    -- ancienne valeur...).
    if cfg.colorBySchool and spellId and ns.HasHeroicFeatures and ns.HasHeroicFeatures() then
        -- Priorité 1 : gradient ZigiAuras (couleur custom pour le sort)
        local gradient = ns.SpellGradients and ns.SpellGradients[spellId]
        -- Priorité 2 : gradient par école via SpellMisc DBC
        if not gradient then
            local school = ns.SpellSchools and ns.SpellSchools[spellId]
            if school then
                gradient = SCHOOL_GRADIENTS[school]
                -- Si combinaison non listée, isoler le bit le plus haut
                if not gradient then
                    for _, mask in ipairs({64, 32, 16, 8, 4, 2}) do
                        if bit.band(school, mask) ~= 0 then
                            gradient = SCHOOL_GRADIENTS[mask]
                            break
                        end
                    end
                end
            end
        end
        if gradient then
            local tex = frame.bar:GetStatusBarTexture()
            if tex and tex.SetGradient then
                local lc, rc = ParseGradient(gradient)
                frame.bar:SetStatusBarColor(1, 1, 1, 1)
                local ok = pcall(tex.SetGradient, tex, "HORIZONTAL", lc, rc)
                if ok then return end
            end
            -- fallback solide : couleur gauche du gradient
            ResetBarGradient()
            local hex = string.sub(gradient, 1, 6)
            local r = (tonumber(string.sub(hex,1,2),16) or 0)/255
            local g = (tonumber(string.sub(hex,3,4),16) or 0)/255
            local b = (tonumber(string.sub(hex,5,6),16) or 0)/255
            frame.bar:SetStatusBarColor(r, g, b, 1)
            return
        end
    end
    ResetBarGradient()
    local bc = cfg.barColor or DEFAULTS.barColor
    frame.bar:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)
end

---------------------------------------------------------------------------
-- Ticks des sorts canalisés / étapes Evoker augmenté
---------------------------------------------------------------------------
-- Sources: ElvUI + compléments manuels
-- spellId → nombre de ticks (sorts canalisés)
local CHANNEL_TICKS = {
    -- Racials
    [291944] = 6,   -- Regeneratin (Zandalari)
    -- Evoker
    [356995] = 3,   -- Disintegrate
    -- Warlock
    [198590] = 4,   -- Drain Soul
    [755]    = 5,   -- Health Funnel
    [234153] = 5,   -- Drain Life
    -- Priest
    [64843]  = 4,   -- Divine Hymn
    [15407]  = 6,   -- Mind Flay
    [48045]  = 6,   -- Mind Sear
    [47757]  = 3,   -- Penance (soin)
    [47758]  = 3,   -- Penance (dps)
    [373129] = 3,   -- Dark Reprimand (dps)
    [400171] = 3,   -- Dark Reprimand (soin)
    [64902]  = 5,   -- Symbol of Hope
    -- Mage
    [5143]   = 4,   -- Arcane Missiles
    [12051]  = 6,   -- Evocation
    [205021] = 5,   -- Ray of Frost
    -- Druid
    [740]    = 4,   -- Tranquility
    -- DK
    [206931] = 3,   -- Blooddrinker
    -- DH
    [198013] = 10,  -- Eye Beam
    [212084] = 10,  -- Fel Devastation
    [473728] = 10,  -- Void Ray
    -- Hunter
    [120360] = 15,  -- Barrage
    [257044] = 7,   -- Rapid Fire
    -- Monk
    [113656] = 4,   -- Fists of Fury
}

local function HideTicks()
    if not frame or not frame.tickLines then return end
    for _, tick in ipairs(frame.tickLines) do
        tick:Hide()
    end
end

local function ShowTicks(numTicks)
    if not frame or not numTicks or numTicks <= 1 then
        HideTicks()
        return
    end
    local cfg = Cfg()
    local w = cfg.width or DEFAULTS.width
    local offset = w / numTicks

    for i = 1, numTicks - 1 do
        local tick = frame.tickLines[i]
        if not tick then
            tick = frame.bar:CreateTexture(nil, "OVERLAY", nil, 7)
            tick:SetColorTexture(0.055, 0.055, 0.055, 1)
            tick:SetWidth(2)
            frame.tickLines[i] = tick
        end
        tick:ClearAllPoints()
        tick:SetPoint("TOP",    frame.bar, "TOPLEFT",    offset * i, 0)
        tick:SetPoint("BOTTOM", frame.bar, "BOTTOMLEFT", offset * i, 0)
        tick:Show()
    end
    for i = numTicks, #frame.tickLines do frame.tickLines[i]:Hide() end
end

-- Ticks positionnés par pourcentage (sorts Evoker augmentés via UnitEmpoweredStagePercentages)
-- stages = table de fractions par section (ex: {0.25, 0.25, 0.25, 0.25} pour 4 étapes égales)
-- → on accumule pour obtenir la position absolue, comme oUF/UpdatePips
local function ShowTicksByPercent(stages)
    if not frame or not stages then HideTicks(); return end
    local cfg = Cfg()
    local w = cfg.width or DEFAULTS.width
    local lastOffset = 0
    local n = 0
    for _, section in ipairs(stages) do
        local offset = lastOffset + (w * section)
        lastOffset = offset
        if offset < w - 1 then
            n = n + 1
            local tick = frame.tickLines[n]
            if not tick then
                tick = frame.bar:CreateTexture(nil, "OVERLAY", nil, 7)
                tick:SetColorTexture(1, 1, 1, 0.8)
                tick:SetWidth(2)
                frame.tickLines[n] = tick
            end
            tick:ClearAllPoints()
            tick:SetPoint("TOP",    frame.bar, "TOPLEFT",    offset, 0)
            tick:SetPoint("BOTTOM", frame.bar, "BOTTOMLEFT", offset, 0)
            tick:Show()
        end
    end
    for i = n + 1, #frame.tickLines do frame.tickLines[i]:Hide() end
end

---------------------------------------------------------------------------
-- Mise à jour du progrès (appelée chaque frame via OnUpdate)
---------------------------------------------------------------------------
local function UpdateProgress()
    if not frame then return end
    local now = GetTime()

    if state.active then
        local total   = state.endTime - state.startTime
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

        -- Spark
        local cfg = Cfg()
        local w   = cfg.width or DEFAULTS.width
        local sparkX = progress * w
        frame.spark:ClearAllPoints()
        frame.spark:SetPoint("CENTER", frame.bgTex, "LEFT", sparkX, 0)
        frame.spark:Show()

        -- Timer
        local remaining = state.endTime - now
        if remaining < 0 then remaining = 0 end
        frame.timerTxt:SetText(FormatTime(remaining))

        -- Fin naturelle : masquer sauf en preview (qui boucle)
        if now >= state.endTime then
            if state.preview then
                -- Relancer la simulation en boucle (durée aléatoire 2-4s)
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

---------------------------------------------------------------------------
-- Démarrage / arrêt
---------------------------------------------------------------------------
local function StartCast(name, startTimeMS, endTimeMS, spellId, spellIcon, castGUID)
    if not frame then return end
    local cfg = Cfg()
    if cfg.enabled == false then return end
    if ns.IsInBlockedState() then return end

    state.active     = true
    state.channeling = false
    state.startTime  = (startTimeMS or 0) / 1000
    state.endTime    = (endTimeMS   or 0) / 1000
    state.name       = name or ""
    state.spellId    = spellId
    state.spellIcon  = spellIcon
    state.castGUID   = castGUID

    -- Restaurer couleurs normales (au cas où un interrupt était en cours)
    frame.nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
    ApplyBarColor(spellId, name, spellIcon)
    -- Ticks : aucun sur un cast normal (l'empower a son propre handler)
    HideTicks()

    frame.nameTxt:SetText(state.name)
    frame:Show()
    UpdateProgress()
end

local function StartChannel(name, startTimeMS, endTimeMS, spellId, spellIcon, castGUID)
    if not frame then return end
    local cfg = Cfg()
    if cfg.enabled == false then return end
    if ns.IsInBlockedState() then return end

    state.active     = true
    state.channeling = true
    state.startTime  = (startTimeMS or 0) / 1000
    state.endTime    = (endTimeMS   or 0) / 1000
    state.name       = name or ""
    state.spellId    = spellId
    state.spellIcon  = spellIcon
    state.castGUID   = castGUID

    -- Restaurer couleurs normales
    frame.nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
    ApplyBarColor(spellId, name, spellIcon)
    -- Ticks pour sorts canalisés (Pénance, Mind Flay, etc.)
    ShowTicks(CHANNEL_TICKS[spellId])

    frame.nameTxt:SetText(state.name)
    frame:Show()
    UpdateProgress()
end

-- delay : 0 pour STOP/FAILED, 0.1 pour CHANNEL_STOP/EMPOWER_STOP afin d'absorber
-- le gap serveur (~50ms) entre CHANNEL_STOP(g1) et CHANNEL_START(g2) lors d'un spam.
local function StopCast(castGUID, delay)
    if not frame then return end
    -- Ignorer ce STOP s'il ne correspond ni au cast actif ni au poll en attente.
    if castGUID then
        if state.castGUID and castGUID ~= state.castGUID then return end
        if not state.castGUID and pendingGUID and castGUID ~= pendingGUID then return end
    end
    -- Annuler le poll en attente s'il appartient à ce cast
    if castGUID and pendingGUID == castGUID then
        pendingGUID = nil
    end
    -- Capturer l'endTime courant : si un nouveau cast démarre, StartChannel/StartCast
    -- le modifiera, et le callback détectera qu'il est obsolète.
    local capturedEndTime = state.endTime
    C_Timer.After(delay or 0, function()
        if not frame then return end
        if pendingGUID   then return end   -- PollStart en cours
        if state.preview then return end
        -- Un nouveau cast a démarré si endTime a changé
        if state.endTime ~= capturedEndTime then return end
        -- Filet de sécurité : le joueur canalise/cast encore côté client
        if UnitChannelInfo("player") then return end
        if UnitCastingInfo("player") then return end
        -- Vrai arrêt
        state.active   = false
        state.castGUID = nil
        frame.bar:SetValue(0)
        frame.spark:Hide()
        frame.timerTxt:SetText("")
        HideTicks()
        frame:Hide()
    end)
end

local function InterruptCast()
    if not frame then return end
    if state.preview then return end  -- ne pas afficher en preview
    state.active = false
    frame.spark:Hide()
    frame.timerTxt:SetText("")
    HideTicks()

    -- Barre rouge figee, texte "Interrompu"
    frame.bar:SetStatusBarColor(0.85, 0.15, 0.10, 1)
    frame.nameTxt:SetText(L["CASTBAR_INTERRUPTED"])
    frame.nameTxt:SetTextColor(0.90, 0.25, 0.15, 1)
    frame:Show()

    -- Masquer apres 0.9s et restaurer les couleurs
    C_Timer.After(0.9, function()
        if not frame then return end
        if state.active then return end  -- un nouveau cast a demarre
        frame.bar:SetValue(0)
        ResetBarGradient()
        local bc2 = Cfg().barColor or DEFAULTS.barColor
        frame.bar:SetStatusBarColor(bc2[1], bc2[2], bc2[3], bc2[4] or 1)
        frame.nameTxt:SetText("")
        frame.nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
        frame:Hide()
    end)
end

---------------------------------------------------------------------------
-- Création de la barre
---------------------------------------------------------------------------
-- Retourne les ancres self/relative correspondant au justify du texte,
-- pour que LEFT/CENTER/RIGHT soit visuellement aligné sur la barre.
local function TextAnchor(justify)
    if justify == "LEFT"  then return "BOTTOMLEFT",  "TOPLEFT"  end
    if justify == "RIGHT" then return "BOTTOMRIGHT", "TOPRIGHT" end
    return "BOTTOM", "TOP"   -- CENTER (défaut)
end

function CastBar.Create(parent)
    if frame then return end

    local cfg = Cfg()
    local w   = cfg.width    or DEFAULTS.width
    local h   = cfg.height   or DEFAULTS.height
    local pt  = cfg.point         or DEFAULTS.point
    local rpt = cfg.relativePoint or DEFAULTS.relativePoint
    local x   = cfg.x        or DEFAULTS.x
    local y   = cfg.y        or DEFAULTS.y
    local bc  = cfg.barColor or DEFAULTS.barColor

    -- Frame racine
    frame = CreateFrame("Frame", "AishCoreCastBar", UIParent)
    frame:SetSize(w, h + 30)   -- marge haute pour le texte nom
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
        if not ns.DB         then ns.DB = {} end
        if not ns.DB.castBar then ns.DB.castBar = {} end
        -- IMPORTANT : StartMoving()/StopMovingOrSizing() peut re-ancrer la
        -- frame sur un point/relativePoint DIFFERENT de celui d'origine (pas
        -- garanti de rester "BOTTOM"/"CENTER") -- sauvegarder SEULEMENT ox/oy
        -- et les rejouer plus tard via un ancrage fixe "BOTTOM"/"CENTER"
        -- (comme le faisait ApplySettings/Create) teleportait la barre a un
        -- endroit incoherent des qu'on relockait -- confirme en jeu. Il faut
        -- sauvegarder ET rejouer le meme point/relativePoint que celui reellement
        -- obtenu apres le drag.
        local point, _, relativePoint, ox, oy = self:GetPoint(1)
        ns.DB.castBar.point         = point
        ns.DB.castBar.relativePoint = relativePoint
        ns.DB.castBar.x = ox
        ns.DB.castBar.y = oy
        -- dragUnlocked reste true : l'utilisateur peut replacer plusieurs fois
        -- avant de cliquer "Terminer". C'est le bouton (ou OnHide) qui verrouille.
    end)
    frame:SetPoint(pt, UIParent, rpt, x, y)
    frame:Hide()

    -- Fond (sublevel 1)
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgTex:SetSize(w, h)
    bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bgTex:SetColorTexture(DARK, DARK, DARK, 1)
    frame.bgTex = bgTex

    -- Bordure (sublevel 0)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetPoint("TOPLEFT",     bgTex, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMRIGHT",  1, -1)
    border:SetColorTexture(DARK, DARK, DARK, 1)

    -- StatusBar de remplissage
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetSize(w, h)
    sb:SetPoint("TOPLEFT", bgTex)
    sb:SetStatusBarTexture(BAR_TEXTURE)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)
    frame.bar = sb

    -- Spark
    local spark = frame:CreateTexture(nil, "OVERLAY")
    spark:SetSize(14, 12)
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetVertexColor(1, 0.867, 0.710, 1)
    spark:SetPoint("CENTER", bgTex, "LEFT", 0, 0)
    spark:Hide()
    frame.spark = spark

    -- Pool de ticks (sorts canalisés / étapes empower)
    frame.tickLines = {}

    -- Texte nom du sort (Bebas Neue, au-dessus de la barre)
    local nSize    = cfg.nameSize    or DEFAULTS.nameSize
    local nOffX    = cfg.nameOffX    or DEFAULTS.nameOffX
    local nOffY    = cfg.nameOffY    or DEFAULTS.nameOffY
    local nJustify = cfg.nameJustify or DEFAULTS.nameJustify
    local nSelf, nRel = TextAnchor(nJustify)
    local nameTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.nameTxtSlug = ns.CreateSlugRing(frame, nameTxt)
    ns.ApplyTextOutlineStyle(nameTxt, frame.nameTxtSlug, BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
    nameTxt:SetJustifyH(nJustify)
    nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
    nameTxt:SetWidth(w)
    nameTxt:SetPoint(nSelf, bgTex, nRel, nOffX, nOffY)
    nameTxt:SetText("")
    frame.nameTxt = nameTxt

    -- Texte timer (Montserrat, au-dessus de la barre)
    local tSize    = cfg.timerSize    or DEFAULTS.timerSize
    local tOffX    = cfg.timerOffX    or DEFAULTS.timerOffX
    local tOffY    = cfg.timerOffY    or DEFAULTS.timerOffY
    local tJustify = cfg.timerJustify or DEFAULTS.timerJustify
    local tSelf, tRel = TextAnchor(tJustify)
    local timerTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.timerTxtSlug = ns.CreateSlugRing(frame, timerTxt)
    ns.ApplyTextOutlineStyle(timerTxt, frame.timerTxtSlug, ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    timerTxt:SetJustifyH(tJustify)
    timerTxt:SetTextColor(0.847, 0.627, 0.380, 1)
    timerTxt:SetWidth(w)
    timerTxt:SetPoint(tSelf, bgTex, tRel, tOffX, tOffY)
    timerTxt:SetText("")
    frame.timerTxt = timerTxt

    -- OnUpdate pour le progrès fluide
    frame:SetScript("OnUpdate", UpdateProgress)

    -- Événements
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_SPELLCAST_START")
    ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    ev:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
    ev:RegisterEvent("UNIT_SPELLCAST_STOP")
    ev:RegisterEvent("UNIT_SPELLCAST_FAILED")
    ev:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    ev:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if unit and unit ~= "player" then return end

        -- TryStart : tente cast normal, canal, puis fallback C_Spell.
        -- Retourne true si un cast a pu être lancé.
        local function TryStart(g, sid)
            -- Essai 1 : cast normal
            local n, _, ic, s, e, _, _, _, si = UnitCastingInfo("player")
            if n then pendingGUID = nil; StartCast(n, s, e, si or sid, ic, g); return true end
            -- Essai 2 : canal
            n, _, ic, s, e, _, _, si = UnitChannelInfo("player")
            if n then pendingGUID = nil; StartChannel(n, s, e, si or sid, ic, g); return true end
            -- Essai 3 : fallback spellID de l'event
            if sid and sid ~= 0 then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                local fname = info and info.name
                local ficon = info and info.iconID
                -- Si le nom n'est pas en cache client mais que le sort est dans notre table
                -- CHANNEL_TICKS, on utilise GetSpellInfo (ancienne API) ou "..." en dernier recours
                if not fname and CHANNEL_TICKS[sid] then
                    fname = (GetSpellInfo and GetSpellInfo(sid)) or "..."
                end
                if fname then
                    pendingGUID = nil
                    local now = GetTime()
                    StartChannel(fname, now * 1000, (now + 5) * 1000, sid, ficon, g)
                    return true
                end
            end
            return false
        end

        -- Polling court : réessaie toutes les 50ms jusqu'à 300ms (6 tentatives).
        -- pendingGUID empêche StopCast de cacher la barre tant que le poll tourne.
        local function PollStart(g, sid, attempt)
            attempt = attempt or 0
            -- Abandonner si notre GUID n'est plus le poll actif (écrasé par un nouveau
            -- CHANNEL_START ou annulé par StopCast)
            if pendingGUID ~= g then return end
            -- Abandonner si un cast différent a déjà démarré
            if state.castGUID and state.castGUID ~= g then
                pendingGUID = nil; return
            end
            if TryStart(g, sid) then return end
            if attempt < 6 then
                C_Timer.After(0.05, function()
                    PollStart(g, sid, attempt + 1)
                end)
            else
                -- Abandon : libérer le verrou pour ne pas bloquer
                pendingGUID = nil
            end
        end

        if event == "UNIT_SPELLCAST_CHANNEL_START" then
            local name, _, icon, startMS, endMS, _, _, sid = UnitChannelInfo("player")
            if name then
                StartChannel(name, startMS, endMS, sid, icon, castGUID)
            else
                local g, si = castGUID, spellID
                pendingGUID = g
                C_Timer.After(0, function() PollStart(g, si) end)
            end

        elseif event == "UNIT_SPELLCAST_START" then
            local name, _, icon, startMS, endMS, _, _, _, sid = UnitCastingInfo("player")
            if name then
                StartCast(name, startMS, endMS, sid, icon, castGUID)
            else
                local g, si = castGUID, spellID
                pendingGUID = g
                C_Timer.After(0, function() PollStart(g, si) end)
            end

        elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
            local name, _, icon, startMS, endMS, _, _, sid = UnitChannelInfo("player")
            if name then
                StartCast(name, startMS, endMS, sid, icon, castGUID)
                if UnitEmpoweredStagePercentages then
                    local stages = UnitEmpoweredStagePercentages("player")
                    if stages then ShowTicksByPercent(stages) end
                end
            else
                local g, si = castGUID, spellID
                pendingGUID = g
                C_Timer.After(0, function() PollStart(g, si) end)
            end

        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            InterruptCast()

        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_FAILED" then
            StopCast(castGUID)

        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            -- delay 0.1s : absorbe le gap entre CHANNEL_STOP et CHANNEL_START lors d'un spam
            StopCast(castGUID, 0.1)

        elseif event == "PLAYER_ENTERING_WORLD" then
            StopCast(nil, 0)
        end
    end)
end

function CastBar.SetDragUnlocked(val)
    dragUnlocked = val and true or false
end

---------------------------------------------------------------------------
-- ApplySettings : remet à jour dimensions/position/couleurs
---------------------------------------------------------------------------
function CastBar.ApplySettings()
    if not frame then return end

    local cfg = Cfg()
    local w   = cfg.width    or DEFAULTS.width
    local h   = cfg.height   or DEFAULTS.height
    local pt  = cfg.point         or DEFAULTS.point
    local rpt = cfg.relativePoint or DEFAULTS.relativePoint
    local x   = cfg.x        or DEFAULTS.x
    local y   = cfg.y        or DEFAULTS.y

    frame:SetSize(w, h + 30)

    frame.bgTex:SetSize(w, h)
    frame.bgTex:ClearAllPoints()
    frame.bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    frame.bar:SetSize(w, h)
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", frame.bgTex)
    ApplyBarColor(state.spellId, state.name, state.spellIcon)

    -- Textes : l'ancre de la boîte de texte suit le justify pour que
    -- LEFT/CENTER/RIGHT soit visuellement cohérent par rapport à la barre.
    local nSize    = cfg.nameSize    or DEFAULTS.nameSize
    local nOffX    = cfg.nameOffX    or DEFAULTS.nameOffX
    local nOffY    = cfg.nameOffY    or DEFAULTS.nameOffY
    local nJustify = cfg.nameJustify or DEFAULTS.nameJustify
    local nSelf, nRel = TextAnchor(nJustify)
    ns.ApplyTextOutlineStyle(frame.nameTxt, frame.nameTxtSlug, cfg.font or BEBAS_FONT, nSize, cfg.nameOutlineStyle, true)
    frame.nameTxt:SetJustifyH(nJustify)
    frame.nameTxt:SetWidth(w)
    frame.nameTxt:ClearAllPoints()
    frame.nameTxt:SetPoint(nSelf, frame.bgTex, nRel, nOffX, nOffY)

    local tSize    = cfg.timerSize    or DEFAULTS.timerSize
    local tOffX    = cfg.timerOffX    or DEFAULTS.timerOffX
    local tOffY    = cfg.timerOffY    or DEFAULTS.timerOffY
    local tJustify = cfg.timerJustify or DEFAULTS.timerJustify
    local tSelf, tRel = TextAnchor(tJustify)
    ns.ApplyTextOutlineStyle(frame.timerTxt, frame.timerTxtSlug, cfg.timerFont or ns.Media.font, tSize, cfg.timerOutlineStyle, true)
    frame.timerTxt:SetJustifyH(tJustify)
    frame.timerTxt:SetWidth(w)
    frame.timerTxt:ClearAllPoints()
    frame.timerTxt:SetPoint(tSelf, frame.bgTex, tRel, tOffX, tOffY)

    -- Position
    frame:ClearAllPoints()
    frame:SetPoint(pt, UIParent, rpt, x, y)

    -- Rafraîchir le preview si actif -- SAUF si le module est desactive (ex:
    -- decocher "Activer" pendant que la preview tourne declenche ApplySettings
    -- via LiveApply, qui sans ce garde reforçait frame:Show() malgre
    -- cfg.enabled=false -- confirme en jeu). On NE remet PAS state.preview a
    -- false ici : la page de reglages est toujours ouverte sur cette
    -- categorie, donc re-cocher "Activer" doit refaire apparaitre la preview
    -- tout de suite (sinon elle restait cachee jusqu'a quitter/rerentrer la
    -- categorie -- confirme en jeu aussi).
    if state.preview then
        if cfg.enabled == false then
            frame:Hide()
        else
            frame:Show()
            -- Forcer le texte pour que les changements d'ancre/justify soient visibles
            frame.nameTxt:SetText(state.name or L["CASTBAR_PREVIEW_SPELL_NAME"])
            frame.timerTxt:SetText(FormatTime(math.max(0, state.endTime - GetTime())))
        end
    end
end

---------------------------------------------------------------------------
-- Preview : affiche la barre avec des données fictives (GUI ouvert)
---------------------------------------------------------------------------
function CastBar.SetPreview(on)
    if not frame then return end
    -- Le module desactive ne doit jamais afficher de preview (confirme en
    -- jeu : la barre apparaissait quand meme dans les reglages meme cfg.enabled=false).
    if on and ns.GetCfg("castBar").enabled == false then return end
    state.preview = on
    if on then
        state.active     = true
        state.channeling = false
        state.startTime  = GetTime() - 0.9   -- simule 30% écoulé
        state.endTime    = GetTime() + 2.1   -- total 3s
        state.name       = L["CASTBAR_PREVIEW_SPELL_NAME"]
        state.spellId    = 133               -- Fireball : utile pour colorBySchool
        state.spellIcon  = 0
        frame.nameTxt:SetTextColor(0.792, 0.639, 0.392, 1)
        ApplyBarColor(133, L["CASTBAR_PREVIEW_SPELL_NAME"], 0)
        frame.nameTxt:SetText(L["CASTBAR_PREVIEW_SPELL_NAME"])
        frame.timerTxt:SetText("2.1")
        frame.bar:SetValue(0.3)
        frame.spark:Show()
        frame:Show()
    else
        -- ne cacher que si aucun vrai cast en cours
        state.spellId   = nil
        state.spellIcon = nil
        if not (UnitCastingInfo("player") or UnitChannelInfo("player")) then
            state.active = false
            frame.bar:SetValue(0)
            frame.spark:Hide()
            frame.nameTxt:SetText("")
            frame.timerTxt:SetText("")
            frame:Hide()
        end
    end
end

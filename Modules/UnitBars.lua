-- Modules/UnitBars.lua : Barres de vie Player, Target, Focus, Pet, TargetTarget
local addonName, ns = ...

local UnitBars = {}
ns.Modules.UnitBars = UnitBars

---------------------------------------------------------------------------
-- Constantes visuelles
---------------------------------------------------------------------------
local BAR_TEXTURE  = "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\ToxiUI-clean.tga"
local BEBAS_FONT   = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\BebasNeue-Regular.ttf"
-- Couleur "noire" commune (#0e0e0e)
local DARK         = 14/255
-- Couleur de fond commune (presque noir)
local DEFAULT_BG   = { DARK, DARK, DARK, 1 }
-- Ratios de base des 3 dots (le 3e est la référence)
local DOT_BASE    = { 3, 5, 9 }
local DOT_SPACING = 3   -- gap interne (fixe) entre chaque dot

-- Spécialisations tank : recevront une largeur de barre spécifique si activé
local TANK_SPECS = {
    [250] = true,  -- DK Sang
    [581] = true,  -- DH Vengeance
    [104] = true,  -- Druide Gardien
    [66]  = true,  -- Paladin Protection
    [73]  = true,  -- Guerrier Protection
    [268] = true,  -- Moine Maître-brasseur
}
local inTankSpec = false
local inCombat   = false

local function UpdateTankSpec()
    local specID = GetSpecializationInfo(GetSpecialization() or 0)
    inTankSpec = TANK_SPECS[specID] or false
end

-- Retourne les 3 tailles de dots depuis la config globale
-- dotRatio (0=proportionnel, 100=identiques) contrôle la convergence des petits dots
local function GetDotSizes()
    local db    = ns.GetCfg("unitBars")
    local big   = (db and db.dotSize)  or DOT_BASE[3]
    local ratio = ((db and db.dotRatio ~= nil) and db.dotRatio or 0) / 100
    local sizes = {}
    for i = 1, 3 do
        local natural = big * DOT_BASE[i] / DOT_BASE[3]
        sizes[i] = math.max(1, math.floor(natural + (big - natural) * ratio + 0.5))
    end
    return sizes
end

-- Retourne l'espace entre barre et groupe de dots
local function GetDotGap()
    local db = ns.GetCfg("unitBars")
    return (db and db.dotGap) or DOT_SPACING
end

-- Vrais si les couleurs sont en mode classique (fill=couleur, bg=noir)
local function IsReversed()
    local db = ns.GetCfg("unitBars")
    return db and db.reversed or false
end

-- Couleurs de classe (alignées sur TopTargetBar / conditions WA)
local CLASS_COLORS = {
    DEATHKNIGHT = { 0.769, 0.122, 0.231, 1 },
    DEMONHUNTER = { 0.639, 0.188, 0.788, 1 },
    DRUID       = { 1.000, 0.490, 0.039, 1 },
    EVOKER      = { 0.094, 0.412, 0.345, 1 },
    HUNTER      = { 0.663, 0.824, 0.443, 1 },
    MAGE        = { 0.251, 0.780, 0.922, 1 },
    MONK        = { 0.000, 1.000, 0.588, 1 },
    PALADIN     = { 0.961, 0.549, 0.729, 1 },
    PRIEST      = { 1.000, 1.000, 1.000, 1 },
    ROGUE       = { 1.000, 0.961, 0.412, 1 },
    SHAMAN      = { 0.000, 0.439, 0.871, 1 },
    WARLOCK     = { 0.529, 0.529, 0.929, 1 },
    WARRIOR     = { 0.780, 0.612, 0.431, 1 },
}

-- Couleurs de réaction PNJ (identiques à TopTargetBar)
local REACTION_COLORS = {
    neutral  = { 0.855, 0.773, 0.361, 1 },
    friendly = { 0.294, 0.686, 0.298, 1 },
    hostile  = { 0.780, 0.251, 0.251, 1 },
}

---------------------------------------------------------------------------
-- Descripteurs de chaque barre
---------------------------------------------------------------------------
local BAR_DEFS = {
    {
        key       = "player",
        unit      = "player",
        dotsLeft  = true,   -- dots à gauche de la barre
        showText  = true,   -- affiche le % PV
        defaults  = {
            enabled   = true,
            width     = 200,
            height    = 4,
            x         = -260, y = -120,
            fillColor = { 0.78, 0.61, 0.44, 1 },
        },
    },
    {
        key         = "target",
        unit        = "target",
        dotsLeft    = false,  -- dots à droite de la barre
        showText    = true,   -- affiche le % PV
        showName    = true,
        nameJustify = "LEFT",
        defaults  = {
            enabled   = true,
            width     = 200,
            height    = 4,
            x         = 260, y = -120,
            fillColor = { 0.72, 0.59, 0.39, 1 },
        },
    },
    {
        key         = "focus",
        unit        = "focus",
        dotsLeft    = true,
        showName    = true,
        nameJustify = "LEFT",
        defaults  = {
            enabled   = true,
            width     = 200,
            height    = 4,
            x         = -260, y = -145,
            fillColor = { 0.71, 0.60, 0.49, 1 },
        },
    },
    {
        key         = "pet",
        unit        = "pet",
        dotsLeft    = true,
        showName    = true,
        nameJustify = "RIGHT",
        defaults  = {
            enabled   = true,
            width     = 143,
            height    = 4,
            x         = -260, y = -100,
            fillColor = { 0.71, 0.60, 0.49, 1 },
        },
    },
    {
        key         = "targettarget",
        unit        = "targettarget",
        dotsLeft    = false,
        noDots      = true,
        showName    = true,
        nameJustify = "LEFT",
        defaults  = {
            enabled   = true,
            width     = 80,
            height    = 4,
            x         = 260, y = -145,
            fillColor = { 0.41, 0.41, 0.41, 1 },
        },
    },
}

---------------------------------------------------------------------------
-- Tables des frames créés
---------------------------------------------------------------------------
local bars = {}   -- bars[key] = frame
local pendingSettingsApply  = false  -- re-appliquer les settings apres combat
local ubFadeTickers         = {}     -- key → ticker de fade par barre
local ubLastVisState        = {}     -- key → dernier état de visibilité (true/false)
local ubHiddenForSkyriding  = false  -- masquées pour le skyriding
local ubHiddenForGui        = false  -- onglet Animations 3D : tout masqué
local ubPreviewMode         = false  -- panneau settings ouvert → forcer affichage
local inVehicle             = false
local inPetBattle           = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Cfg(key)
    local db = ns.GetCfg("unitBars")
    return db and db.bars and db.bars[key] or {}
end

-- Calcule si une barre doit être visible selon l'état courant du jeu.
-- Pas de StateDriver : pure Lua, même pattern que ResourceCircle.ShouldShow().
local function ShouldShowBar(frame)
    if ubHiddenForGui  then return false end  -- onglet Animations 3D : masqué
    if ubPreviewMode   then return true  end
    local db  = ns.GetCfg("unitBars")
    local cfg = Cfg(frame._def.key)
    if (db and db.enabled == false) or cfg.enabled == false then return false end
    if ns.IsInBlockedState()    then return false end
    if ubHiddenForSkyriding     then return false end
    if inVehicle                then return false end
    if inPetBattle              then return false end
    local unit  = frame._def.unit
    local vMode = (db and db.visibilityMode)
    if not vMode then
        vMode = (db and db.hideOutOfCombat) and "combat" or "target"
    end
    if vMode == "always" then
        return UnitExists(unit)
    elseif vMode == "combat" then
        return UnitAffectingCombat("player") and UnitExists(unit)
    else  -- "target"
        return UnitExists(unit)
    end
end

local function GetBgColor()
    local db = ns.GetCfg("unitBars")
    return db and db.bgColor or DEFAULT_BG
end

-- Hauteur effective d'une barre : tankHeight si spé tank + option activée
local function GetEffectiveHeight(def, cfg)
    local db = ns.GetCfg("unitBars")
    if db and db.useTankHeight and inTankSpec
       and (def.key == "player" or def.key == "target" or def.key == "focus") then
        return db.tankHeight or 8
    end
    return cfg.height or def.defaults.height
end

-- Retourne la couleur d'une unité : classe pour les joueurs, réaction pour les PNJ.
-- Même logique que TopTargetBar.GetUnitColor, avec alpha (4ème composante).
local function GetClassFillColor(unit, fallback)
    if UnitIsPlayer(unit) then
        local ok, classFile = pcall(function() return select(2, UnitClass(unit)) end)
        if ok and classFile and CLASS_COLORS[classFile] then
            return CLASS_COLORS[classFile]
        end
        return fallback
    end
    local ok, reaction = pcall(function() return UnitReaction(unit, "player") end)
    if ok and reaction then
        -- UnitReaction peut retourner un nombre privé en raid : le détainter avant
        -- toute comparaison (sinon == / > lève une erreur Lua non catchée ici,
        -- interrompant l'handler d'événement et laissant la barre dans un état incohérent).
        local r = tonumber(tostring(reaction)) or 0
        if     r == 4 then return REACTION_COLORS.neutral
        elseif r  > 4 then return REACTION_COLORS.friendly
        else               return REACTION_COLORS.hostile
        end
    end
    return fallback
end

---------------------------------------------------------------------------
-- Création d'une barre (appelée une seule fois par key)
---------------------------------------------------------------------------
local function CreateUnitBar(def)
    local cfg      = Cfg(def.key)
    local w        = cfg.width or def.defaults.width
    local h        = GetEffectiveHeight(def, cfg)
    local bg       = GetBgColor()
    local dotSizes = GetDotSizes()
    local dotGap   = GetDotGap()

    -- Largeur du groupe de dots (0 si pas de dots)
    local dotsW  = (not def.noDots) and
                   (dotSizes[1] + DOT_SPACING + dotSizes[2] + DOT_SPACING + dotSizes[3]) or 0
    local totalW = w + dotsW   -- dotGap ne modifie pas la barre, seulement les dots

    -- Frame racine (draggable, taille totale incluant les dots)
    local frameH = math.max(dotsW > 0 and dotSizes[3] or 0, h) + 4
    local frame = CreateFrame("Button", "AishaddonUnitBar_" .. def.key, UIParent, "SecureUnitButtonTemplate")
    frame:SetSize(totalW, frameH)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("unit", def.unit)
    frame:SetAttribute("*type1", "target")      -- clic gauche = cibler l'unité
    frame:SetAttribute("*type2", "togglemenu")  -- clic droit  = menu contextuel
    frame:SetClampedToScreen(true)
    -- Show() appelé une seule fois à la création (hors combat, jamais bloqué).
    -- La visibilité est ensuite gérée exclusivement par SetAlpha() qui n'est
    -- jamais protégé en combat. Show/Hide/EnableMouse ne sont plus jamais rappelés.
    frame:Show()
    frame:SetAlpha(0)
    frame:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local panel = _G["AishaddonSettingsPanel"]
        if not panel or not panel:IsShown() then return end
        if ns.GetCfg("unitBars") and ns.GetCfg("unitBars").locked then return end
        self._dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:StopMovingOrSizing()
        -- Sauvegarde de la position
        local db = ns.DB and ns.DB.unitBars
        if db and db.bars and db.bars[def.key] then
            local _, _, _, ox, oy = frame:GetPoint(1)
            -- Pour le pet (ancré sur le joueur) : reconvertir en absolu
            if def.key == "pet" and bars.player then
                local pDef = BAR_DEFS[1].defaults
                local pCfg = Cfg("player")
                local px   = pCfg.x or pDef.x
                local py   = pCfg.y or pDef.y
                ox = ox + px
                oy = oy + py
            end
            db.bars[def.key].x = ox
            db.bars[def.key].y = oy
        end
    end)

    -- Position initiale (ancre bas : grandit vers le haut si hauteur augmente)
    local x = cfg.x or def.defaults.x
    local y = cfg.y or def.defaults.y
    -- La barre de pet est ancrée sur la barre du joueur (pas UIParent) pour
    -- être correcte sur tous les ratios d'écran (ultrawide, etc.).
    if def.key == "pet" and bars.player then
        local pDef = BAR_DEFS[1].defaults
        local pCfg = Cfg("player")
        local px   = pCfg.x or pDef.x
        local py   = pCfg.y or pDef.y
        frame:SetPoint("BOTTOM", bars.player, "BOTTOM", x - px, y - py)
    else
        frame:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    end

    -- -----------------------------------------------------------------------
    -- Zone de la barre (à droite ou à gauche selon dotsRight)
    -- -----------------------------------------------------------------------
    local barOffX = (not def.noDots and def.dotsLeft) and dotsW or 0  -- pas de dotGap ici
    local barH    = h

    -- Fond de la barre (sublevel 1 pour être au-dessus du border)
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgTex:SetSize(w, barH)
    bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", barOffX, (frameH - barH) / 2)
    frame.bgTex = bgTex

    -- StatusBar de remplissage HP (doit exister avant absorbTex qui s'ancre sur son fill)
    local parentLevel = frame:GetFrameLevel()
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetFrameLevel(parentLevel + 1)
    sb:SetSize(w, barH)
    sb:SetPoint("TOPLEFT", bgTex)
    sb:SetStatusBarTexture(BAR_TEXTURE)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    frame.bar = sb

    frame._barW = w

    -- Barre d'absorb : StatusBar sans REVERSE_FILL, ancrée au bord droit du fill HP.
    -- SetMinMaxValues/SetValue C-side → aucune arithmétique Lua, accepte les secret numbers.
    -- Avec mode WithAbsorbs : GetMaximumHealth()=maxHP+absorb → espace visible même à 100% HP.
    pcall(function()
        local absorbBar = CreateFrame("StatusBar", nil, frame)
        absorbBar:SetFrameLevel(parentLevel + 2)
        absorbBar:SetSize(w, barH)
        absorbBar:SetPoint("LEFT", sb:GetStatusBarTexture(), "RIGHT", 0, 0)
        absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local _ac = (ns.GetCfg("unitBars") or {}).absorbColor or { 0, 1, 0.918, 1 }
        absorbBar:SetStatusBarColor(_ac[1], _ac[2], _ac[3], _ac[4] or 1)
        absorbBar:EnableMouse(false)  -- ne pas intercepter les clics (SecureUnitButtonTemplate parent)
        absorbBar:SetMinMaxValues(0, 1)
        absorbBar:SetValue(0)
        frame.absorbBar = absorbBar
    end)
    -- Calculateur Retail : CreateUnitHealPredictionCalculator retourne hp/absorb/maxHP réguliers
    if CreateUnitHealPredictionCalculator then
        pcall(function()
            local calc = CreateUnitHealPredictionCalculator()
            if calc.SetMaximumHealthMode and Enum and Enum.UnitMaximumHealthMode then
                calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.WithAbsorbs)
            end
            if calc.SetDamageAbsorbClampMode and Enum and Enum.UnitDamageAbsorbClampMode then
                calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
            end
            frame.hpCalc = calc
        end)
    end

    -- Couleurs initiales (UpdateBarColor appliquera le bon mode)
    bgTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
    sb:SetStatusBarColor(DARK, DARK, DARK, 1)

    -- Filet de bordure (1px noir autour de la barre, sublevel 0 = derrière bgTex)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetPoint("TOPLEFT",     bgTex, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMRIGHT",  1, -1)
    border:SetColorTexture(DARK, DARK, DARK, 1)

    -- Glow au survol : BackdropTemplate + GlowTex.tga (même technique qu'ElvUI)
    local GLOW_TEX  = "Interface\\AddOns\\Aishaddon\\GlowTex.tga"
    local GLOW_SIZE = 5
    local fc0 = cfg.fillColor or def.defaults.fillColor
    local glowFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glowFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    glowFrame:SetPoint("TOPLEFT",     bgTex, "TOPLEFT",     -GLOW_SIZE,  GLOW_SIZE)
    glowFrame:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMRIGHT",  GLOW_SIZE, -GLOW_SIZE)
    glowFrame:SetBackdrop({ edgeFile = GLOW_TEX, edgeSize = GLOW_SIZE })
    glowFrame:SetBackdropColor(0, 0, 0, 0)
    glowFrame:SetBackdropBorderColor(fc0[1], fc0[2], fc0[3], 0.9)
    glowFrame:SetAlpha(0)
    frame.glowFrame = glowFrame

    -- -----------------------------------------------------------------------
    -- Trois dots décoratifs (absents pour targettarget)
    -- -----------------------------------------------------------------------
    if not def.noDots then
        local fc_dot     = cfg.fillColor or def.defaults.fillColor
        local dotColors  = { fc_dot, fc_dot, { DARK, DARK, DARK, 1 } }
        local dotYCenter = frameH / 2

        for i = 1, 3 do
            local d  = frame:CreateTexture(nil, "OVERLAY")
            local sz = dotSizes[i]
            d:SetSize(sz, sz)
            local dx
            if def.dotsLeft then
                -- dots à gauche : dotGap positif = dots s'éloignent de la barre (vont à gauche)
                local offset = 0
                for j = 1, i - 1 do offset = offset + dotSizes[j] + DOT_SPACING end
                dx = offset + sz / 2 - dotGap
            else
                -- dots à droite : dotGap positif = dots s'éloignent de la barre (vont à droite)
                local totalOff = 0
                for j = 3, i + 1, -1 do totalOff = totalOff + dotSizes[j] + DOT_SPACING end
                dx = w + dotGap + totalOff + sz / 2
            end
            d:SetPoint("CENTER", frame, "BOTTOMLEFT", dx, dotYCenter)
            d:SetTexture("Interface\\AddOns\\Aishaddon\\circleflat2.tga")
            d:SetVertexColor(dotColors[i][1], dotColors[i][2], dotColors[i][3], 1)
            frame["dot" .. i] = d
        end
    end

    -- -----------------------------------------------------------------------
    -- Texte HP% (player et target uniquement)
    -- -----------------------------------------------------------------------
    if def.showText then
        -- Fond du texte (rectangle sombre 32x17)
        local tbFrame = CreateFrame("Frame", nil, frame)
        tbFrame:SetSize(32, 17)
        tbFrame:SetFrameLevel(frame:GetFrameLevel() + 2)
        if def.dotsLeft then
            -- player : côté droit (vers le centre écran) + 1px inward
            tbFrame:SetPoint("BOTTOMRIGHT", bgTex, "TOPRIGHT", 1, 0)
        else
            -- target : côté gauche (vers le centre écran) + 1px inward
            tbFrame:SetPoint("BOTTOMLEFT", bgTex, "TOPLEFT", -1, 0)
        end
        local tbTex = tbFrame:CreateTexture(nil, "BACKGROUND")
        tbTex:SetAllPoints(tbFrame)
        tbTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
        frame.textBG    = tbFrame
        frame.textBGTex = tbTex

        -- Texte HP%
        local txt = tbFrame:CreateFontString(nil, "OVERLAY")
        local ubCfg   = ns.GetCfg("unitBars")
        local txtSize = (ubCfg and ubCfg.textSize) or 8
        txt:SetFont(ns.Media.font, txtSize, "OUTLINE")
        txt:SetAlpha(0.66)
        txt:SetJustifyH("CENTER")
        txt:SetTextColor(1, 1, 1, 1)
        txt:SetPoint("CENTER", tbFrame, "CENTER", 0, 1)
        txt:SetText("--")
        frame.hpText = txt
    end

    frame._def    = def
    frame._dotsW  = dotsW
    frame.unit    = def.unit

    -- Survol : fade in/out de la lueur (HookScript pour ne pas écraser le template)
    frame:HookScript("OnEnter", function(self)
        UIFrameFadeIn(self.glowFrame, 0.15, self.glowFrame:GetAlpha(), 1)
    end)
    frame:HookScript("OnLeave", function(self)
        UIFrameFadeOut(self.glowFrame, 0.2, self.glowFrame:GetAlpha(), 0)
    end)

    -- -----------------------------------------------------------------------
    -- Texte de nom d'unité (target, focus, pet, targettarget)
    -- -----------------------------------------------------------------------
    if def.showName then
        local db      = ns.GetCfg("unitBars")
        local cfg2    = Cfg(def.key)
        local nSize   = (db and db.nameSize)     or 14
        local nOffX   = (cfg2 and cfg2.nameOffX) or 0
        local nOffY   = (cfg2 and cfg2.nameOffY) or 2
        local justify = def.nameJustify or "LEFT"
        local anchorS = (justify == "LEFT") and "BOTTOMLEFT"  or "BOTTOMRIGHT" -- bas du texte
        local anchorA = (justify == "LEFT") and "TOPLEFT"     or "TOPRIGHT"    -- haut de bgTex

        local nameTxt = frame:CreateFontString(nil, "OVERLAY")
        nameTxt:SetFont(BEBAS_FONT, nSize, "OUTLINE")
        nameTxt:SetJustifyH(justify)
        nameTxt:SetShadowColor(0, 0, 0, 0.7)
        nameTxt:SetShadowOffset(1, -1)
        nameTxt:SetTextColor(1, 1, 1, 1)
        nameTxt:SetPoint(anchorS, bgTex, anchorA, nOffX, nOffY)
        nameTxt:SetText("")
        frame.nameTxt = nameTxt
    end

    return frame
end

---------------------------------------------------------------------------
-- Helper : mise à jour du texte HP selon le mode (pct ou value)
---------------------------------------------------------------------------
local function SetHPText(hpTextWidget, unit)
    local db   = ns.GetCfg("unitBars")
    local mode = (db and db.hpDisplayMode) or "pct"
    if mode == "value" then
        -- AbbreviateNumbers est C-side, accepte les secret numbers
        local ok, txt = pcall(function()
            return AbbreviateNumbers and AbbreviateNumbers(UnitHealth(unit)) or nil
        end)
        hpTextWidget:SetText((ok and txt) or "--")
    else
        -- pct : UnitHealthPercent (C-side) → entier 0-100
        local ok, pct = pcall(function()
            return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
        end)
        hpTextWidget:SetText((ok and pct) and format('%d', pct) or "--")
    end
end

---------------------------------------------------------------------------
-- Mise à jour d'une barre (health valeur)
---------------------------------------------------------------------------
local function UpdateBarHealth(frame)
    local unit   = frame.unit
    local barCfg = Cfg(frame._def.key)
    if barCfg.enabled == false then return end
    if not UnitExists(unit) then return end

    -- Pcall HP bar : calculateur (WithAbsorbs, mode normal) ou C-side (mode miroir/fallback).
    -- En mode miroir (absorbReversed), le HP bar ne doit pas utiliser WithAbsorbs pour éviter
    -- un gap visible à droite — on reste sur C-side pur.
    -- Pcall HP bar : calculateur (WithAbsorbs, mode normal) ou C-side (mode miroir/fallback).
    -- En mode miroir (absorbReversed), le HP bar ne doit pas utiliser WithAbsorbs pour éviter
    -- un gap visible à droite — on reste sur C-side pur.
    local calcUpdated = false
    local absorbReversed = (ns.GetCfg("unitBars") or {}).absorbReversed
    if frame.hpCalc and not absorbReversed then
        pcall(function()
            UnitGetDetailedHealPrediction(unit, nil, frame.hpCalc)
            calcUpdated = true
            frame.bar:SetMinMaxValues(0, frame.hpCalc:GetMaximumHealth())
            frame.bar:SetValue(frame.hpCalc:GetCurrentHealth())
        end)
    end
    if not calcUpdated then
        pcall(function()
            frame.bar:SetMinMaxValues(0, UnitHealthMax(unit))
            frame.bar:SetValue(UnitHealth(unit))
        end)
    end
    -- Absorb via UpdateAbsorb (appelé séparément par le ticker pour toutes les barres)

    if frame.hpText then
        SetHPText(frame.hpText, unit)
    end
end

---------------------------------------------------------------------------
-- Mise à jour absorb (commune à toutes les barres, y compris target)
---------------------------------------------------------------------------
local function UpdateAbsorb(frame)
    if not frame.hpCalc or not frame.absorbBar then return end
    local db2  = ns.GetCfg("unitBars")
    local show = db2 == nil or db2.showAbsorb ~= false
    if not show then frame.absorbBar:SetValue(0); return end
    -- UnitGetTotalAbsorbs retourne un secret number → passé directement à SetValue (C-side).
    -- Pas d'arithmetic Lua : fill = absorb / GetMaximumHealth() calculé par WoW en interne.
    local cfg2     = ns.GetCfg("unitBars") or {}
    local reversed = cfg2.absorbReversed or false
    local ac       = cfg2.absorbColor or { 0, 1, 0.918, 1 }
    pcall(function()
        local fn = UnitAbsorb or UnitGetTotalAbsorbs
        local absorb = 0
        if fn then
            local ok, v = pcall(fn, frame._def.unit)
            if ok then absorb = v end
        end
        -- Repositionnement selon sens choisi (ClearAllPoints car peut changer en live)
        frame.absorbBar:ClearAllPoints()
        if reversed then
            -- Miroir : ancré à GAUCHE de bgTex, se superpose au fill HP depuis la gauche
            frame.absorbBar:SetPoint("LEFT", frame.bgTex, "LEFT", 0, 0)
            local maxHP = UnitHealthMax(frame._def.unit) or 1  -- valeur régulière
            frame.absorbBar:SetMinMaxValues(0, maxHP)
        else
            -- Défaut : ancré au bord droit du fill HP
            frame.absorbBar:SetPoint("LEFT", frame.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
            frame.absorbBar:SetMinMaxValues(0, frame.hpCalc:GetMaximumHealth())
        end
        frame.absorbBar:SetValue(absorb)
        frame.absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], ac[4] or 1)
    end)
end

-- Met à jour la couleur de la barre (target = classe, autres = config/Colors)
local function UpdateBarColor(frame)
    local def = frame._def
    local cfg = Cfg(def.key)
    local fc  = cfg.fillColor or def.defaults.fillColor
    local bg  = GetBgColor()
    local CLR = ns.Modules.Colors

    -- Pour target/targettarget : couleur de classe ; player/pet : Colors si dispo
    if def.key == "target" or def.key == "targettarget" then
        fc = GetClassFillColor(def.unit, fc)
    elseif def.key == "player" and CLR then
        fc = CLR.Get("playerhealthbar")
    elseif def.key == "pet" and CLR then
        fc = CLR.Get("pethealthbar")
    end

    -- Couleur des dots : peut différer du fill pour player/pet
    local dc = fc
    if def.key == "player" and CLR then
        dc = CLR.Get("playerdots")
    elseif def.key == "pet" and CLR then
        dc = CLR.Get("petdots")
    end

    if IsReversed() then
        -- Mode classique : fond sombre, fill coloré
        frame.bgTex:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
        frame.bar:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
    else
        -- Mode inversé (défaut) : fond coloré, fill noir
        frame.bgTex:SetColorTexture(fc[1], fc[2], fc[3], fc[4] or 1)
        frame.bar:SetStatusBarColor(DARK, DARK, DARK, 1)
    end

    -- Couleur des petits dots (1 et 2) = dc, dot 3 reste noir
    if not def.noDots then
        for i = 1, 2 do
            if frame["dot" .. i] then
                frame["dot" .. i]:SetVertexColor(dc[1], dc[2], dc[3], 1)
            end
        end
        if frame.dot3 then frame.dot3:SetVertexColor(DARK, DARK, DARK, 1) end
    end
    -- Couleur du texte = fill color
    if frame.hpText then
        frame.hpText:SetTextColor(fc[1], fc[2], fc[3], 1)
    end
    -- Couleur du nom = fill color
    if frame.nameTxt then
        frame.nameTxt:SetTextColor(fc[1], fc[2], fc[3], 1)
    end
    -- Couleur du glow
    if frame.glowFrame then
        frame.glowFrame:SetBackdropBorderColor(fc[1], fc[2], fc[3], 0.9)
    end
end

---------------------------------------------------------------------------
-- Mise à jour du nom d'unité
---------------------------------------------------------------------------
local function UpdateBarName(frame)
    if not frame.nameTxt then return end
    local unit = frame.unit
    if UnitExists(unit) then
        -- Détainter UnitName (secret string en instance/raid) via concaténation
        -- avant de passer à SetText (sinon # ou sub planteraient).
        local rawName = UnitName(unit)
        frame.nameTxt:SetText((rawName and ("" .. rawName)) or "")
    elseif ubPreviewMode and (unit == "target" or unit == "targettarget" or unit == "focus" or unit == "pet") then
        -- Preview : nom spécifique au module quand l'unité n'existe pas
        local PREVIEW_NAMES = {
            target       = "Target Name",
            targettarget = "Target of Target Name",
            focus        = "Focus Name",
            pet          = "Pet Name",
        }
        frame.nameTxt:SetText(PREVIEW_NAMES[unit] or (unit .. " Name"))
    else
        frame.nameTxt:SetText("")
    end
end

---------------------------------------------------------------------------
-- Application des settings sur un bar déjà créé (ApplySettings)
---------------------------------------------------------------------------
local function ApplyBarSettings(frame)
    -- SetSize / ClearAllPoints / SetPoint sont bloques en combat lockdown
    if InCombatLockdown() then
        pendingSettingsApply = true
        return
    end

    local def = frame._def
    local cfg = Cfg(def.key)
    local db2 = ns.GetCfg("unitBars")

    -- Activation / desactivation (global OU par barre)
    if (db2 and db2.enabled == false) or cfg.enabled == false then
        ubLastVisState[def.key] = nil
        UnitBars.UpdateAllVisibility()
        return
    end

    local w  = cfg.width or def.defaults.width
    local h  = GetEffectiveHeight(def, cfg)

    local dotSizes = GetDotSizes()
    local dotGap   = GetDotGap()
    local showDots = db2 == nil or db2.showDots ~= false
    local dotsW    = (not def.noDots) and showDots and
                     (dotSizes[1] + DOT_SPACING + dotSizes[2] + DOT_SPACING + dotSizes[3]) or 0
    local totalW   = w + dotsW   -- dotGap ne modifie pas la barre
    local frameH   = math.max(dotsW > 0 and dotSizes[3] or 0, h) + 4
    frame:SetSize(totalW, frameH)

    -- Repositionner la barre dans le frame
    local barOffX = (not def.noDots and def.dotsLeft) and dotsW or 0  -- pas de dotGap ici
    frame.bgTex:SetSize(w, h)
    frame.bgTex:ClearAllPoints()
    frame.bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", barOffX, (frameH - h) / 2)
    frame.bar:SetSize(w, h)
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", frame.bgTex)
    frame._barW = w
    if frame.absorbBar then
        pcall(function()
            frame.absorbBar:SetSize(w, h)
            frame.absorbBar:ClearAllPoints()
            frame.absorbBar:SetPoint("LEFT", frame.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
        end)
    end

    -- Couleurs via UpdateBarColor (gère reversed)
    UpdateBarColor(frame)

    -- Repositionner les dots (si présents)
    if not def.noDots then
        -- Masquer ou afficher les dots selon la préférence
        for i = 1, 3 do
            local d = frame["dot" .. i]
            if d then d:SetShown(showDots) end
        end
        if showDots then
            local CLR2    = ns.Modules.Colors
            local fc_dot  = cfg.fillColor or def.defaults.fillColor
            if def.key == "target" or def.key == "targettarget" then
                fc_dot = GetClassFillColor(def.unit, fc_dot)
            elseif def.key == "player" and CLR2 then
                fc_dot = CLR2.Get("playerdots")
            elseif def.key == "pet" and CLR2 then
                fc_dot = CLR2.Get("petdots")
            end
            local dotColors  = { fc_dot, fc_dot, { DARK, DARK, DARK, 1 } }
            local dotYCenter = frameH / 2
            for i = 1, 3 do
                local d  = frame["dot" .. i]
                if d then
                    local sz = dotSizes[i]
                    d:SetSize(sz, sz)
                    local dx
                    if def.dotsLeft then
                        -- dots à gauche : dotGap positif = s'éloignent de la barre (vers la gauche)
                        local offset = 0
                        for j = 1, i - 1 do offset = offset + dotSizes[j] + DOT_SPACING end
                        dx = offset + sz / 2 - dotGap
                    else
                        -- dots à droite : dotGap positif = s'éloignent de la barre (vers la droite)
                        local totalOff = 0
                        for j = 3, i + 1, -1 do totalOff = totalOff + dotSizes[j] + DOT_SPACING end
                        dx = w + dotGap + totalOff + sz / 2
                    end
                    d:SetPoint("CENTER", frame, "BOTTOMLEFT", dx, dotYCenter)
                    d:SetVertexColor(dotColors[i][1], dotColors[i][2], dotColors[i][3], 1)
                end
            end
        end
    end

    -- Repositionner le fond de texte si présent + mise à jour taille police
    if frame.textBG then
        local bgc = GetBgColor()
        frame.textBG:ClearAllPoints()
        if def.dotsLeft then
            frame.textBG:SetPoint("BOTTOMRIGHT", frame.bgTex, "TOPRIGHT", 1, 0)
        else
            frame.textBG:SetPoint("BOTTOMLEFT", frame.bgTex, "TOPLEFT", -1, 0)
        end
        frame.textBGTex:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4] or 1)
        if frame.hpText then
            local ubCfg   = ns.GetCfg("unitBars")
            local txtSize = (ubCfg and ubCfg.textSize) or 8
            frame.hpText:SetFont((ubCfg and ubCfg.font) or ns.Media.font, txtSize, "OUTLINE")
        end
    end

    -- Repositionner le texte de nom si présent
    if frame.nameTxt then
        local ubCfg  = ns.GetCfg("unitBars")
        local cfg2   = Cfg(def.key)
        local nSize  = (ubCfg and ubCfg.nameSize)   or 14
        local nOffX  = (cfg2  and cfg2.nameOffX)    or 0
        local nOffY  = (cfg2  and cfg2.nameOffY)    or 2
        local justify_n = def.nameJustify or "LEFT"
        local anchorS = (justify_n == "LEFT") and "BOTTOMLEFT"  or "BOTTOMRIGHT"
        local anchorA = (justify_n == "LEFT") and "TOPLEFT"     or "TOPRIGHT"
        frame.nameTxt:SetFont((ubCfg and ubCfg.nameFont) or BEBAS_FONT, nSize, "OUTLINE")
        frame.nameTxt:SetJustifyH(justify_n)
        frame.nameTxt:ClearAllPoints()
        frame.nameTxt:SetPoint(anchorS, frame.bgTex, anchorA, nOffX, nOffY)
    end

    -- Repositionner la lueur
    if frame.glowFrame then
        frame.glowFrame:ClearAllPoints()
        frame.glowFrame:SetPoint("TOPLEFT",     frame.bgTex, "TOPLEFT",     -5,  5)
        frame.glowFrame:SetPoint("BOTTOMRIGHT", frame.bgTex, "BOTTOMRIGHT",  5, -5)
    end

    -- Position frame (ancre bas)
    local x = cfg.x or def.defaults.x
    local y = cfg.y or def.defaults.y
    frame:ClearAllPoints()
    if def.key == "pet" and bars.player then
        local pDef = BAR_DEFS[1].defaults
        local pCfg = Cfg("player")
        local px   = pCfg.x or pDef.x
        local py   = pCfg.y or pDef.y
        frame:SetPoint("BOTTOM", bars.player, "BOTTOM", x - px, y - py)
    else
        frame:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    end

    -- Réévaluer la visibilité après changement de settings
    ubLastVisState[def.key] = nil
    UnitBars.UpdateAllVisibility()
    UpdateBarHealth(frame)
    UpdateBarName(frame)
end

---------------------------------------------------------------------------
-- Animation de visibilité (fade in/out) — remplace les StateDrivers
---------------------------------------------------------------------------
local function AnimateBar(frame, shouldShow)
    local key = frame._def.key
    if ubFadeTickers[key] then ubFadeTickers[key]:Cancel(); ubFadeTickers[key] = nil end
    -- Visibilité contrôlée exclusivement via SetAlpha() sur la frame elle-même.
    -- SetAlpha() n'est JAMAIS protégé en combat. Show()/Hide() ne sont plus appelés.
    if shouldShow then
        local startA = frame:GetAlpha()
        if startA >= 1 then UpdateBarHealth(frame); return end
        local _t0 = GetTime()
        ubFadeTickers[key] = C_Timer.NewTicker(0.016, function()
            local _p = math.min((GetTime() - _t0) / 0.35, 1)
            frame:SetAlpha(startA + (1 - startA) * (1 - (1 - _p)^3))
            if _p >= 1 then ubFadeTickers[key]:Cancel(); ubFadeTickers[key] = nil end
        end)
        UpdateBarHealth(frame)
    else
        local startA = frame:GetAlpha()
        if startA <= 0 then return end
        local _t0 = GetTime()
        ubFadeTickers[key] = C_Timer.NewTicker(0.016, function()
            local _p = math.min((GetTime() - _t0) / 0.35, 1)
            frame:SetAlpha(startA * (1 - _p)^3)
            if _p >= 1 then
                ubFadeTickers[key]:Cancel(); ubFadeTickers[key] = nil
                frame:SetAlpha(0)
            end
        end)
    end
end

function UnitBars.UpdateAllVisibility()
    for _, f in pairs(bars) do
        local key        = f._def.key
        local shouldShow = ShouldShowBar(f)
        if shouldShow ~= ubLastVisState[key] then
            ubLastVisState[key] = shouldShow
            AnimateBar(f, shouldShow)
        end
    end
end
-- Interface publique
---------------------------------------------------------------------------
function UnitBars.ApplySettings()
    for _, frame in pairs(bars) do
        ApplyBarSettings(frame)
    end
end

-- Appelé par Skyriding.lua quand le skyriding commence/se termine.
-- Même approche que le véhicule : hide forcé via StateDriver puis restauration.
function UnitBars.SetSkyridingActive(active)
    if not next(bars) then return end
    ubHiddenForSkyriding = active
    -- Pas de reset de ubLastVisState : le debounce d'UpdateAllVisibility
    -- détecte naturellement le changement via ShouldShowBar().
    UnitBars.UpdateAllVisibility()
end

--- Cache (on=true) ou restaure (on=false) toutes les barres pour l'onglet Animations 3D.
function UnitBars.SetGuiHidden(on)
    ubHiddenForGui = (on == true)
    UnitBars.UpdateAllVisibility()
end

function UnitBars.Create(parent)
    for _, def in ipairs(BAR_DEFS) do
        if not bars[def.key] then
            local f = CreateUnitBar(def)
            bars[def.key] = f
            -- Affichage initial
            ApplyBarSettings(f)
        end
    end
    -- Forcer la visibilité quand le panneau config s'ouvre/se ferme
    C_Timer.After(0, function()
        local panel = _G["AishaddonSettingsPanel"]
        if panel then
            panel:HookScript("OnShow", function()
                -- Mode preview : ShouldShowBar renvoie true pour toutes les barres.
                ubPreviewMode = true
                UnitBars.UpdateAllVisibility()
                -- Injecter noms + HP de test sur les barres sans unité réelle
                for _, f in pairs(bars) do
                    local u = f._def.unit
                    if not UnitExists(u) then
                        UpdateBarName(f)
                        if f.bar then
                            f.bar:SetMinMaxValues(0, 100)
                            f.bar:SetValue(75)
                        end
                        if f.hpText then
                            local _ubdb = ns.GetCfg("unitBars")
                            local _mode = (_ubdb and _ubdb.hpDisplayMode) or "pct"
                            f.hpText:SetText(_mode == "value" and "75K" or "75")
                        end
                    end
                end
            end)
            panel:HookScript("OnHide", function()
                -- Fin de preview : nettoyer les données de test puis recalculer
                ubPreviewMode = false
                for _, f in pairs(bars) do
                    UpdateBarName(f)
                    if not UnitExists(f._def.unit) then
                        if f.hpText then f.hpText:SetText("") end
                    end
                end
                UnitBars.UpdateAllVisibility()
            end)
        end
    end)
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterUnitEvent("UNIT_HEALTH",                 "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH",               "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED",   "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_TARGET",                  "target")  -- target change de cible => mettre a jour targettarget
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
eventFrame:RegisterEvent("PET_BATTLE_CLOSE")

-- Map unité → key de barre
local UNIT_KEY = {
    player       = "player",
    target       = "target",
    focus        = "focus",
    pet          = "pet",
    targettarget = "targettarget",
}

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if not next(bars) then return end  -- pas encore initialisé

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        UnitBars.UpdateAllVisibility()   -- le debounce détecte le changement d'état
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        UnitBars.UpdateAllVisibility()   -- le debounce détecte le changement d'état
        if pendingSettingsApply then
            C_Timer.After(0.4, function()
                if pendingSettingsApply then
                    pendingSettingsApply = false
                    for _, f in pairs(bars) do ApplyBarSettings(f) end
                end
            end)
        end
        return
    end

    if event == "UNIT_ENTERED_VEHICLE" and arg1 == "player" then
        inVehicle = true
        UnitBars.UpdateAllVisibility()
        return
    end

    if event == "UNIT_EXITED_VEHICLE" and arg1 == "player" then
        inVehicle = false
        UnitBars.UpdateAllVisibility()
        return
    end

    if event == "PET_BATTLE_OPENING_START" then
        inPetBattle = true
        UnitBars.UpdateAllVisibility()
        return
    end

    if event == "PET_BATTLE_CLOSE" then
        inPetBattle = false
        UnitBars.UpdateAllVisibility()
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        local wasTank = inTankSpec
        UpdateTankSpec()
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Changement de spé complet : réappliquer systématiquement
            for _, f in pairs(bars) do ApplyBarSettings(f) end
        elseif inTankSpec ~= wasTank then
            -- Transformation : réappliquer seulement si le statut tank a changé
            -- (évite le saut visuel à chaque shapeshif druide/shaman sans impact réel)
            for _, f in pairs(bars) do ApplyBarSettings(f) end
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        UpdateTankSpec()
        -- ApplyBarSettings gère la hauteur tank + couleurs + santé + nom.
        for _, f in pairs(bars) do
            ApplyBarSettings(f)
        end
        -- Retry deferred : UnitHealthMax("player") retourne 0 juste apres un
        -- reload tant que le serveur n'a pas renvoye les donnees d'unite.
        -- On reessaie a 0.3s, 0.8s et 2.0s jusqu'a obtenir une valeur valide.
        local retryCount = 0
        local function RetryHealth()
            retryCount = retryCount + 1
            local allValid = true
            for _, f in pairs(bars) do
                -- UnitHealthMax peut retourner un "secret number" tainté si le timer
                -- se déclenche juste après une action sur une frame sécurisée.
                -- On encapsule la comparaison dans pcall pour éviter l'erreur de taint.
                local ok, maxIsZero = pcall(function()
                    return UnitExists(f.unit) and UnitHealthMax(f.unit) == 0
                end)
                -- Si pcall a échoué (valeur taintée) OU si max == 0 : données invalides, reessayer.
                if (not ok) or maxIsZero then
                    allValid = false
                end
                UpdateBarHealth(f)
                UpdateBarColor(f)
            end
            if not allValid and retryCount < 3 then
                C_Timer.After(retryCount == 1 and 0.5 or 1.2, RetryHealth)
            end
        end
        C_Timer.After(0.3, RetryHealth)
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        local f  = bars.target
        local tt = bars.targettarget
        -- Comme TopTargetBar : ne pas lire UnitHealth ici (tainté après clic secure).
        -- Le fill est géré par le ticker 0.1s. On met à jour seulement couleur + nom.
        if f  then UpdateBarColor(f);  UpdateBarName(f)  end
        if tt then UpdateBarHealth(tt); UpdateBarColor(tt); UpdateBarName(tt) end
        UnitBars.UpdateAllVisibility()   -- target appear/disappear => réévaluer visibilité
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        local f = bars.focus
        if f then UpdateBarHealth(f); UpdateBarColor(f); UpdateBarName(f) end
        UnitBars.UpdateAllVisibility()   -- focus appear/disappear => réévaluer visibilité
        return
    end

    if event == "UNIT_PET" and arg1 == "player" then
        local f = bars.pet
        if f then UpdateBarHealth(f); UpdateBarColor(f); UpdateBarName(f) end
        UnitBars.UpdateAllVisibility()   -- pet appear/disappear => réévaluer visibilité
        return
    end

    if event == "UNIT_TARGET" and arg1 == "target" then
        local tt = bars.targettarget
        if tt then UpdateBarHealth(tt); UpdateBarColor(tt); UpdateBarName(tt) end
        return
    end

    -- UNIT_HEALTH / UNIT_MAXHEALTH
    -- Pour target : ne pas lire UnitHealth ici (peut être tainté).
    -- Le fill de target vient exclusivement du ticker 0.1s (comme TopTargetBar).
    local key = UNIT_KEY[arg1]
    if key and key ~= "target" then
        local f = bars[key]
        if f then pcall(UpdateBarHealth, f) end
    end
end)

-- Fonction pré-allouée pour pcall : évite de créer une closure à chaque tick
local function _TickUBTargetHP()
    local tg  = bars.target
    local absorbReversed = (ns.GetCfg("unitBars") or {}).absorbReversed
    -- Calculateur WithAbsorbs uniquement en mode normal (pas en miroir)
    -- Calculateur WithAbsorbs uniquement en mode normal (pas en miroir)
    if tg.hpCalc and not absorbReversed then
        pcall(UnitGetDetailedHealPrediction, "target", nil, tg.hpCalc)
        pcall(function()
            tg.bar:SetMinMaxValues(0, tg.hpCalc:GetMaximumHealth())
            tg.bar:SetValue(tg.hpCalc:GetCurrentHealth())
        end)
    else
        -- C-side pur (mode miroir ou pas de calculateur)
        local cur = UnitHealth("target")
        local max = UnitHealthMax("target")
        tg.bar:SetMinMaxValues(0, max)
        tg.bar:SetValue(cur)
    end
end

-- Ticker 0.1s : fill + absorb pour target ET les autres barres avec calculateur.
C_Timer.NewTicker(0.1, function()
    if not next(bars) then return end
    -- Target : mise à jour dédiée (tainted health, tickrate élevé)
    local tg = bars.target
    if tg and tg:GetAlpha() >= 0.01 and UnitExists("target") then
        pcall(_TickUBTargetHP)
    end
    -- Toutes les barres sauf targettarget : UpdateAbsorb uniforme
    for key, f in pairs(bars) do
        if key ~= "targettarget" and f:GetAlpha() >= 0.01 and UnitExists(f._def.unit) then
            pcall(UpdateAbsorb, f)
        end
    end
end)


-- Ticker 0.5s : targettarget + texte HP% target + masquage si unité disparue
C_Timer.NewTicker(0.5, function()
    if not next(bars) then return end
    local guiOpen = _G["AishaddonSettingsPanel"] and _G["AishaddonSettingsPanel"]:IsShown()
    local tg = bars.target
    if tg then
        if UnitExists("target") then
            if tg.hpText then
                SetHPText(tg.hpText, "target")
            end
        end
        -- Pas de Hide() ici : visibilité gérée exclusivement par SetAlpha() via AnimateBar.
    end
    local tt = bars.targettarget
    if tt then UpdateBarHealth(tt); UpdateBarColor(tt); UpdateBarName(tt) end
    if tt and tt:GetAlpha() >= 0.01 and UnitExists("targettarget") then
        pcall(UpdateAbsorb, tt)
    end
end)

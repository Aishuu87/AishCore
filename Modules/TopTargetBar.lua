-- Modules/TopTargetBar.lua
-- Barre de cible détaillée (haut d'écran) + cible de la cible
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local TopTargetBar = {}
ns.Modules.TopTargetBar = TopTargetBar

-- Constantes
local BAR_TEXTURE   = "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\ToxiUI-clean.tga"
local BEBAS_FONT    = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\BebasNeue-Regular.ttf"
local MONTSERRAT_BI = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\Montserrat-BoldItalic.ttf"
local DARK          = 14 / 255   -- #0e0e0e

-- Couleurs (identiques aux conditions WA)
local CLASS_COLORS = {
    DEATHKNIGHT = { 0.769, 0.122, 0.231 },
    DEMONHUNTER = { 0.639, 0.188, 0.788 },
    DRUID       = { 1.000, 0.490, 0.039 },
    EVOKER      = { 0.094, 0.412, 0.345 },
    HUNTER      = { 0.663, 0.824, 0.443 },
    MAGE        = { 0.251, 0.780, 0.922 },
    MONK        = { 0.000, 1.000, 0.588 },
    PALADIN     = { 0.961, 0.549, 0.729 },
    PRIEST      = { 1.000, 1.000, 1.000 },
    ROGUE       = { 1.000, 0.961, 0.412 },
    SHAMAN      = { 0.000, 0.439, 0.871 },
    WARLOCK     = { 0.529, 0.529, 0.929 },
    WARRIOR     = { 0.780, 0.612, 0.431 },
}

-- Couleur des PNJ selon leur réaction envers le joueur
--   reaction == 4 → neutre, > 4 → amical, < 4 → hostile
local REACTION_COLORS = {
    neutral  = { 0.855, 0.773, 0.361 },
    friendly = { 0.294, 0.686, 0.298 },
    hostile  = { 0.780, 0.251, 0.251 },
}

-- Couleurs de difficulté de niveau (texte de niveau)
local LEVEL_COLORS = {
    skull   = { 1.000, 0.000, 0.133 },   -- diff >= 4 / elite / worldboss
    hard    = { 0.922, 0.408, 0.000 },   -- diff >= 3
    normal  = { 0.894, 0.816, 0.282 },   -- diff +/- 2
    easy    = { 0.153, 0.706, 0.275 },   -- diff <= -2
    trivial = { 0.722, 0.753, 0.686 },   -- diff <= -6
}

-- Couleurs des barres de ressource par type de puissance (fallback si PowerBarColor absent)
local POWER_COLORS = {
    MANA         = { 0.00, 0.45, 1.00 },
    RAGE         = { 0.78, 0.25, 0.25 },
    FOCUS        = { 1.00, 0.55, 0.20 },
    ENERGY       = { 1.00, 0.82, 0.00 },
    COMBO_POINTS = { 1.00, 0.82, 0.00 },
    RUNES        = { 0.55, 0.55, 0.55 },
    RUNIC_POWER  = { 0.00, 0.82, 1.00 },
    SOUL_SHARDS  = { 0.50, 0.32, 0.55 },
    LUNAR_POWER  = { 0.30, 0.52, 0.90 },
    HOLY_POWER   = { 0.95, 0.90, 0.60 },
    MAELSTROM    = { 0.00, 0.50, 1.00 },
    CHI          = { 0.71, 0.90, 0.78 },
    INSANITY     = { 0.40, 0.00, 0.80 },
    FURY         = { 0.79, 0.26, 0.99 },
    PAIN         = { 1.00, 0.61, 0.00 },
    ESSENCE      = { 0.00, 0.78, 0.87 },
}

-- Helpers couleur
local function GetUnitColor(unit)
    if UnitIsPlayer(unit) then
        -- Indexation CLASS_COLORS[classFile] dans le pcall : classFile peut etre une valeur secrete (cf. UnitBars.lua)
        local ok, color = pcall(function()
            local classFile = select(2, UnitClass(unit))
            return classFile and CLASS_COLORS[classFile]
        end)
        if ok and color then return color end
        -- UnitClass inaccessible (valeur privee/secrete) : repli sur "allie" visible plutot que DARK (sinon nom/barre invisibles)
        return REACTION_COLORS.friendly
    end
    local ok, reaction = pcall(function() return UnitReaction(unit, "player") end)
    if ok and reaction then
        -- UnitReaction peut retourner un nombre prive en raid : le detainter avant toute comparaison
        local r = tonumber(tostring(reaction)) or 0
        if     r == 4 then return REACTION_COLORS.neutral
        elseif r  > 4 then return REACTION_COLORS.friendly
        else               return REACTION_COLORS.hostile
        end
    end
    -- UnitReaction inaccessible (valeur privee en instance/raid) : supposer hostile (DARK rendrait le nom invisible)
    return REACTION_COLORS.hostile
end

local function GetPowerBarColor(unit)
    -- Meme precaution que GetUnitColor : indexation par powerToken dans le pcall (peut etre secrete)
    local ok, color = pcall(function()
        local powerToken = select(2, UnitPowerType(unit))
        if not powerToken then return nil end
        -- Privilégier le tableau officiel Blizzard (contient les couleurs localisées)
        if PowerBarColor and PowerBarColor[powerToken] then
            local c = PowerBarColor[powerToken]
            return { c.r or 1, c.g or 0.82, c.b or 0 }
        end
        return POWER_COLORS[powerToken]
    end)
    if ok and color then return color end
    return { 1.00, 0.82, 0.00 }  -- jaune (énergie) par défaut
end

local function GetLevelColor(unit)
    if UnitIsPlayer(unit) then return GetUnitColor(unit) end
    -- tonumber(tostring()) necessaire pour detainter les valeurs privees TWW (tonumber seul ne suffit pas)
    local ok1, lvl  = pcall(function() return tonumber(tostring(UnitLevel(unit)))  or 0 end)
    local ok2, plvl = pcall(function() return tonumber(tostring(UnitLevel("player"))) or 0 end)
    local classif = UnitClassification(unit) or ""
    if not ok1 then lvl = 0 end
    if not ok2 then plvl = 0 end
    if lvl == -1 or classif == "worldboss" then return LEVEL_COLORS.skull end
    local diff = lvl - plvl
    if diff >= 4 or classif == "elite" or classif == "rareelite" then
        return LEVEL_COLORS.skull
    elseif diff >= 3 then
        return LEVEL_COLORS.hard
    elseif math.abs(diff) <= 2 then
        return LEVEL_COLORS.normal
    elseif diff <= -6 then
        return LEVEL_COLORS.trivial
    else
        return LEVEL_COLORS.easy
    end
end

-- Séparateur bullet (U+2022), échappé en décimal Lua
local BULLET = "\226\128\162"

-- Retourne le préfixe de niveau : "70 • ", "RARE • 70 • ", "??? • ", etc.
local function GetLevelPrefix(unit)
    local ok1, lvl = pcall(function() return tonumber(tostring(UnitLevel(unit))) or 0 end)
    local classif = UnitClassification(unit) or ""
    if not ok1 then lvl = 0 end
    local sep = " " .. BULLET .. " "
    if     lvl == -1              then return "???" .. sep
    elseif classif == "worldboss" then return "\226\152\133" .. sep
    elseif classif == "rareelite" then return L["TOPTARGET_LABEL_RAREELITE"] .. sep .. lvl .. sep
    elseif classif == "rare"      then return L["TOPTARGET_LABEL_RARE"] .. sep .. lvl .. sep
    elseif classif == "elite"     then return lvl .. "+" .. sep
    else                               return lvl .. sep
    end
end

local function AbbreviateNumber(n)
    -- n est un nombre propre (fourni par Blizzard C via OnValueChanged), comparaisons >= sures
    n = tonumber(n) or 0
    if     n >= 1e9 then return string.format("%.1fG", n / 1e9)
    elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.0fK", n / 1e3)
    else                 return string.format("%.0f",  n)
    end
end

-- Encode une couleur RGB (0-1 floats) + texte en escape color WoW
local function Colorize(r, g, b, text)
    return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end

-- Cache HP mis à jour par le hook TargetFrame.HealthBar (valeurs propres du C engine).
-- Utilisé pour SetMinMaxValues/SetValue de notre barre de vie.
local _hp = {
    target       = { cur = 0, max = 1 },
    targettarget = { cur = 0, max = 1 },
}

-- État des frames
local f_target      = nil
local f_tt          = nil
local ttbPreviewMode = false  -- panel settings ouvert → noms de test

-- Enregistre les StateDrivers de visibilité sur f_target et f_tt (appelé après Create() et à chaque ApplySettings()).
-- RegisterStateDriver appelle SetAttribute, bloqué en combat : on diffère.
local pendingDriverUpdate = false

-- ElvUI : masquer la barre de cible ElvUI via alpha (SetAlpha jamais bloqué), pcall silencieux si absent
local function ApplyElvUITargetAlpha()
    local db = ns.GetCfg("topTargetBar")
    local alpha = (db and db.enabled == false) and 0 or 1
    local candidates = { "ElvUF_Target", "oUF_ElvUI_target" }
    for _, name in ipairs(candidates) do
        local f = _G[name]
        if f and f.SetAlpha then
            pcall(f.SetAlpha, f, alpha)
        end
    end
end

local function SetTTBVisibilityDrivers()
    if not f_target then return end
    if InCombatLockdown() then
        pendingDriverUpdate = true
        return
    end
    pendingDriverUpdate = false
    local db       = ns.GetCfg("topTargetBar")
    local disabled = db and db.enabled == false
    -- Le TTB reste visible en véhicule : on n'exclut que les pet battles.
    local blocked  = C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
    if disabled or blocked then
        RegisterStateDriver(f_target, "visibility", "hide")
        -- nameFrame et hpFrame sont parentés à UIParent → masquer explicitement
        if f_target.nameFrame then f_target.nameFrame:Hide() end
        if f_target.hpFrame   then f_target.hpFrame:Hide()   end
        if f_tt then RegisterStateDriver(f_tt, "visibility", "hide") end
    else
        RegisterStateDriver(f_target, "visibility", "[@target,exists] show; hide")
        if f_tt then
            local showTT = not (db and db.showTargetOfTarget == false)
            if showTT then
                RegisterStateDriver(f_tt, "visibility", "[@targettarget,exists] show; hide")
            else
                RegisterStateDriver(f_tt, "visibility", "hide")
            end
        end
    end
    -- Appliquer alpha sur la barre ElvUI (désactivé = 0, actif = 1)
    ApplyElvUITargetAlpha()
end

-- Création : barre target principale (WA : 525×2 px, centré horizontalement en haut d'écran)
local function CreateTargetBar()
    -- Frame conteneur (530×35 → TOP ancré sur WorldFrame pour coller au bord physique)
    local f = CreateFrame("Button", "AishCoreTopTarget", UIParent, "SecureUnitButtonTemplate")
    f:SetSize(530, 35)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(false)   -- permet de coller au bord physique
    f:SetAttribute("unit",   "target")
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")

    -- Position par défaut — ancre sur WorldFrame pour 0 = bord physique exact
    local db  = ns.GetCfg("topTargetBar")
    local ox  = (db and db.x) or 0
    local oy  = (db and db.y) or 0
    f:SetPoint("TOP", WorldFrame, "TOP", ox, oy)

    -- Drag : disponible seulement quand le panel est ouvert et hors combat
    f:HookScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local panel = _G["AishCoreSettingsPanel"]
        if not panel or not panel:IsShown() then return end
        self._dragging = true
        self:StartMoving()
    end)
    f:HookScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:StopMovingOrSizing()
        local pt, _, rpt, x, y = self:GetPoint(1)
        local cfg = ns.DB and ns.DB.topTargetBar
        if cfg then cfg.x = x; cfg.y = y end
    end)

    -- Fond sombre — taille indépendante du conteneur (depuis DB)
    local bgfW  = (db and db.bgW)  or 530
    local bgfH  = (db and db.bgH)  or 35
    local bgfOX = (db and db.bgOX) or 0
    local bgfOY = (db and db.bgOY) or 0
    local bgFull = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgFull:SetSize(bgfW, bgfH)
    bgFull:SetPoint("CENTER", f, "CENTER", bgfOX, bgfOY)
    bgFull:SetColorTexture(DARK, DARK, DARK, 1)
    f.bgFull = bgFull

    -- Barre de vie — taille et offset depuis DB
    local db2  = ns.GetCfg("topTargetBar")
    local bw   = (db2 and db2.barW)  or 525
    local bh   = (db2 and db2.barH)  or 2
    local box  = (db2 and db2.barOX) or 0
    local boy  = (db2 and db2.barOY) or -22

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(bw, bh)
    bar:SetPoint("TOP", f, "TOP", box, boy)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(DARK, DARK, DARK, 1)

    -- Fond de la barre (1px de border tout autour)
    local barBg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    barBg:SetPoint("TOPLEFT",     bar, "TOPLEFT",     -1,  1)
    barBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT",  1, -1)
    barBg:SetColorTexture(DARK, DARK, DARK, 1)

    f.bar   = bar
    f.barBg = barBg

    -- Barre de ressource (énergie / mana / rage…) — masquée par défaut
    local powerBar = CreateFrame("StatusBar", nil, f)
    powerBar:SetSize(bw, bh)
    powerBar:SetPoint("TOP", f, "TOP", box, boy)
    powerBar:SetStatusBarTexture(BAR_TEXTURE)
    powerBar:SetMinMaxValues(0, 1)
    powerBar:SetValue(0)
    powerBar:SetStatusBarColor(1, 0.82, 0, 1)
    powerBar:Hide()

    local powerBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    powerBarBg:SetPoint("TOPLEFT",     powerBar, "TOPLEFT",     -1,  1)
    powerBarBg:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMRIGHT",  1, -1)
    powerBarBg:SetColorTexture(DARK, DARK, DARK, 1)
    powerBarBg:Hide()

    f.powerBar   = powerBar
    f.powerBarBg = powerBarBg

    -- Texte Nom + Niveau : Frame indépendante parentée UIParent (SetText sur un FontString enfant d'un SecureUnitButtonTemplate est ignoré si tainté)
    local nox  = (db2 and db2.nameOX) or 0
    local noy  = (db2 and db2.nameOY) or -5

    local nameFrame = CreateFrame("Frame", "AishCoreTopTargetNameFrame", UIParent)
    nameFrame:SetSize(420, 30)
    nameFrame:SetFrameStrata("MEDIUM")
    nameFrame:SetFrameLevel(f:GetFrameLevel() + 2)
    nameFrame:SetPoint("TOP", f, "TOP", nox, noy)
    nameFrame:Hide()

    local nameTxt = nameFrame:CreateFontString(nil, "OVERLAY")
    nameTxt:SetFont(BEBAS_FONT, 15, "")
    nameTxt:SetJustifyH("CENTER")
    nameTxt:SetAlpha(1)
    nameTxt:SetShadowColor(0, 0, 0, 1)
    nameTxt:SetShadowOffset(1, -1)
    nameTxt:SetWidth(420)
    -- Ancrer en TOP comme l'ancien FontString direct, pas en CENTER du nameFrame.
    nameTxt:SetPoint("TOP", nameFrame, "TOP", 0, 0)
    f.nameFrame = nameFrame
    f.nameTxt   = nameTxt

    -- Texte HP : Frame indépendante parentée UIParent (aucun clip/strate du SecureUnitButtonTemplate ne la cache), visibilité gérée dans UpdateTarget
    local hox     = (db2 and db2.hpOX)       or 5
    local hoy     = (db2 and db2.hpOY)       or -19
    local hpts    = (db2 and db2.hpFontSize) or 10
    local hanchor = (db2 and db2.hpAnchor)   or "LEFT"

    local hpFrame = CreateFrame("Frame", "AishCoreTopTargetHP", UIParent)
    hpFrame:SetSize(bgfW, 20)
    hpFrame:SetFrameStrata("TOOLTIP")
    hpFrame:SetPoint(hanchor, bgFull, hanchor, hox, hoy)

    local hpTxt = hpFrame:CreateFontString(nil, "OVERLAY")
    if not hpTxt:SetFont(MONTSERRAT_BI, hpts, "") then
        hpTxt:SetFont("Fonts\\FRIZQT__.TTF", hpts, "")
    end
    hpTxt:SetJustifyH(hanchor)
    hpTxt:SetAlpha(1)
    hpTxt:SetShadowColor(0, 0, 0, 1)
    hpTxt:SetShadowOffset(1, -1)
    hpTxt:SetWidth(300)
    hpTxt:SetPoint(hanchor, hpFrame, hanchor, 0, 0)
    hpFrame:Hide()   -- caché par défaut comme f
    f.hpFrame = hpFrame
    f.hpTxt   = hpTxt

    f:Hide()
    return f
end

-- Création : barre TargetTarget (125×24 BG + barre 124×1.7 + nom)
local function CreateTargetTargetBar()
    -- Conteneur 125×24 cliquable (SecureUnitButtonTemplate)
    local f = CreateFrame("Button", "AishCoreTopTargetTarget", UIParent, "SecureUnitButtonTemplate")
    f:SetSize(125, 24)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForClicks("AnyUp")
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(false)   -- même logique : sans marge forcée
    f:SetAttribute("unit",   "targettarget")
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")

    local db  = ns.GetCfg("topTargetBar")
    local ttx = (db and db.ttx) or 0
    local tty = (db and db.tty) or -75
    f:SetPoint("CENTER", UIParent, "TOP", ttx, tty)

    f:HookScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local panel = _G["AishCoreSettingsPanel"]
        if not panel or not panel:IsShown() then return end
        self._dragging = true
        self:StartMoving()
    end)
    f:HookScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:StopMovingOrSizing()
        local pt, _, rpt, x, y = self:GetPoint(1)
        local cfg = ns.DB and ns.DB.topTargetBar
        if cfg then cfg.ttx = x; cfg.tty = y end
    end)

    -- Fond sombre noir TT — taille indépendante
    local ttbgW  = (db and db.ttBgW)  or 125
    local ttbgH  = (db and db.ttBgH)  or 24
    local ttbgOX = (db and db.ttBgOX) or 0
    local ttbgOY = (db and db.ttBgOY) or 0
    local bgTex = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgTex:SetSize(ttbgW, ttbgH)
    bgTex:SetPoint("CENTER", f, "CENTER", ttbgOX, ttbgOY)
    bgTex:SetColorTexture(DARK, DARK, DARK, 1)
    f.bgTex = bgTex

    -- Bordure 1px
    local border = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    border:SetPoint("TOPLEFT",     f, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  1, -1)
    border:SetColorTexture(DARK, DARK, DARK, 1)

    -- Barre de vie — taille et offset depuis DB
    local db2   = ns.GetCfg("topTargetBar")
    local tbw   = (db2 and db2.ttBarW)  or 124
    local tbh   = (db2 and db2.ttBarH)  or 1.7
    local tbox  = (db2 and db2.ttBarOX) or 0
    local tboy  = (db2 and db2.ttBarOY) or -10.161

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetSize(tbw, tbh)
    bar:SetPoint("CENTER", f, "CENTER", tbox, tboy)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarColor(DARK, DARK, DARK, 1)

    -- Nom — offset depuis DB
    local tnox  = (db2 and db2.ttNameOX) or 0
    local tnoy  = (db2 and db2.ttNameOY) or 0.860

    local nameTxt = f:CreateFontString(nil, "OVERLAY")
    nameTxt:SetFont(BEBAS_FONT, 12, "")
    nameTxt:SetJustifyH("CENTER")
    nameTxt:SetAlpha(1)
    nameTxt:SetShadowColor(0, 0, 0, 1)
    nameTxt:SetShadowOffset(1, -1)
    nameTxt:SetWidth(109)
    nameTxt:SetPoint("CENTER", f, "CENTER", tnox, tnoy)

    f.bar     = bar
    f.nameTxt = nameTxt

    f:Hide()
    return f
end

-- Mises à jour (textes + couleurs uniquement — la visibilité est gérée par RegisterStateDriver dans SetTTBVisibilityDrivers).
-- Fonctions pré-allouées pour pcall (évite 4 closures par appel, plusieurs/sec en combat), accèdent à f_target/f_tt via upvalue.
local function _UpdateTargetColor()
    local c = GetUnitColor("target")
    f_target.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    if f_target.hpTxt then f_target.hpTxt:SetTextColor(c[1], c[2], c[3], 1) end
    if f_target.hpFrame and not f_target.hpFrame:IsShown() then f_target.hpFrame:Show() end
    -- Barre de ressource : mettre à jour la couleur selon le type de puissance
    if f_target.powerBar and f_target.powerBar:IsShown() then
        local pc = GetPowerBarColor("target")
        f_target.powerBar:SetStatusBarColor(pc[1], pc[2], pc[3], 1)
    end
end
local function _UpdateTargetName()
    if not f_target then return end
    if not f_target.nameTxt then
        TopTargetBar._lastNameErr = "nameTxt nil"
        return
    end
    -- Mode preview : pas de cible réelle → noms de test
    if ttbPreviewMode and not UnitExists("target") then
        if f_target.nameFrame then f_target.nameFrame:Show() end
        local lc = LEVEL_COLORS.skull
        local nc = REACTION_COLORS.hostile
        f_target.nameTxt:SetText(string.format("|cff%02x%02x%02x90 \226\128\162 |r|cff%02x%02x%02x%s|r",
            math.floor(lc[1]*255), math.floor(lc[2]*255), math.floor(lc[3]*255),
            math.floor(nc[1]*255), math.floor(nc[2]*255), math.floor(nc[3]*255), L["TOPTARGET_PREVIEW_NAME"]))
        return
    end
    if f_target.nameFrame then f_target.nameFrame:Show() end
    -- UnitName retourne une secret string en raid : jamais de # ou sub() dessus, SetText (C-side) l'accepte directement (meme approche qu'UnitBars)
    local rawName = UnitName("target")
    f_target.nameTxt:SetText(rawName or "")
    -- Colorisation via string.format %s uniquement : concatener une secret string echoue toujours
    local _ok, _result = pcall(function()
        local lc  = GetLevelColor("target")
        local nc  = GetUnitColor("target")
        local lvl = GetLevelPrefix("target")
        return string.format("|cff%02x%02x%02x%s|r|cff%02x%02x%02x%s|r",
            math.floor(lc[1]*255), math.floor(lc[2]*255), math.floor(lc[3]*255), lvl,
            math.floor(nc[1]*255), math.floor(nc[2]*255), math.floor(nc[3]*255), rawName or "")
    end)
    TopTargetBar._lastNameErr = not _ok and _result or nil
    if _ok and _result then
        f_target.nameTxt:SetText(_result)
    else
        -- Fallback : nom brut + couleur hostile fixe (rouge) si tout échoue
        local hostile = REACTION_COLORS.hostile
        f_target.nameTxt:SetText(string.format("|cff%02x%02x%02x%s|r",
            math.floor(hostile[1]*255), math.floor(hostile[2]*255), math.floor(hostile[3]*255),
            rawName or ""))
    end
end
local function _UpdateTTColor()
    local c = GetUnitColor("targettarget")
    f_tt.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
end
local function _UpdateTTName()
    -- Mode preview : pas de cible de la cible réelle → noms de test
    if ttbPreviewMode and not UnitExists("targettarget") then
        if not f_tt then return end
        local nc = REACTION_COLORS.friendly
        f_tt.nameTxt:SetText(string.format("|cff%02x%02x%02x%s|r",
            math.floor(nc[1]*255), math.floor(nc[2]*255), math.floor(nc[3]*255), L["TOPTARGET_PREVIEW_TT_NAME"]))
        return
    end
    local rawName = UnitName("targettarget")
    local _ok2, _result2 = pcall(function()
        local nc = GetUnitColor("targettarget")
        return string.format("|cff%02x%02x%02x%s|r",
            math.floor(nc[1]*255), math.floor(nc[2]*255), math.floor(nc[3]*255), rawName or "")
    end)
    if _ok2 and _result2 then
        f_tt.nameTxt:SetText(_result2)
    else
        local hostile = REACTION_COLORS.hostile
        f_tt.nameTxt:SetText(string.format("|cff%02x%02x%02x%s|r",
            math.floor(hostile[1]*255), math.floor(hostile[2]*255), math.floor(hostile[3]*255),
            rawName or ""))
    end
end

local function UpdateTarget()
    if not f_target then return end
    local _db = ns.GetCfg("topTargetBar")
    if _db and _db.enabled == false then
        if f_target.hpFrame then f_target.hpFrame:Hide() end
        ApplyElvUITargetAlpha()
        return
    end
    if not UnitExists("target") then
        -- Mode preview (panel ouvert, pas de vraie cible) : ne pas masquer, sinon chaque reglage change fait disparaitre nameFrame/hpFrame
        if not ttbPreviewMode then
            if f_target.nameFrame then f_target.nameFrame:Hide() end
            if f_target.hpFrame   then f_target.hpFrame:Hide()   end
        end
        return
    end
    -- S'assurer que nameFrame est visible avant les updates (peut avoir ete cache par un UpdateTarget precedent)
    if f_target.nameFrame then f_target.nameFrame:Show() end
    pcall(_UpdateTargetColor)
    pcall(_UpdateTargetName)
end

local function UpdateTargetTarget()
    if not f_tt then return end
    if not UnitExists("targettarget") then return end
    pcall(_UpdateTTColor)
    pcall(_UpdateTTName)
end

-- Pré-alloué pour C_Timer.After sur les events rares (PLAYER_TARGET_CHANGED etc.)
local function _DoUpdateBoth() UpdateTarget(); UpdateTargetTarget() end

-- Helpers pour accrocher la barre HP normalisée de TargetFrame (TWW). Chemin trouvé via /ttbscan : children[2][1][1][2] (StatusBar anonyme, valeurs 0-1 jamais taintées).
local function FindTargetHealthBarInTree()
    if not TargetFrame then return nil end
    local c2 = select(2, TargetFrame:GetChildren())
    if not c2 then return nil end
    local c21 = select(1, c2:GetChildren())
    if not c21 then return nil end
    local c211 = select(1, c21:GetChildren())
    if not c211 then return nil end
    local bar = select(2, c211:GetChildren())
    if bar and bar:GetObjectType() == "StatusBar" then return bar end
    return nil
end

local function FindToTHealthBarInTree()
    local tot = (TargetFrame and TargetFrame.TargetFrameToT)
             or _G["TargetFrameToT"]
    if not tot then return nil end
    for i = 1, tot:GetNumChildren() do
        local c = select(i, tot:GetChildren())
        if c and c:GetObjectType() == "StatusBar" then return c end
    end
    return nil
end

-- Debug : /aish ttb debug
function TopTargetBar.Debug()
  local P = function(s) print("|cff00b0ff[TTB Debug]|r " .. s) end
  local unit = "target"
  if not UnitExists(unit) then P("Pas de cible."); return end

  -- 1. Etat de f_target et nameTxt
  P("f_target=" .. tostring(f_target ~= nil))
  if f_target then
    P("nameTxt=" .. tostring(f_target.nameTxt ~= nil))
    if f_target.nameTxt then
      P("nameTxt:GetText()=" .. tostring(f_target.nameTxt:GetText()))
      P("nameTxt:IsShown()=" .. tostring(f_target.nameTxt:IsShown()))
      P("nameTxt:GetAlpha()=" .. tostring(f_target.nameTxt:GetAlpha()))
    end
    P("f_target:IsShown()=" .. tostring(f_target:IsShown()))
  end

  -- 2. UnitName : tester si c'est une private string
  local rawName = UnitName(unit)
  P("UnitName type=" .. type(rawName) .. " val=" .. tostring(rawName))
  -- Tenter une concatenation (echoue sur private string)
  local okConcat, nameStr = pcall(function() return "" .. (rawName or "") end)
  P("concat ok=" .. tostring(okConcat) .. " result=" .. tostring(nameStr))
  -- Tenter SetText direct
  if f_target and f_target.nameTxt then
    local okSet, errSet = pcall(function() f_target.nameTxt:SetText(rawName or "???") end)
    P("SetText(rawName) ok=" .. tostring(okSet) .. (not okSet and " err=" .. tostring(errSet) or ""))
    P("GetText apres SetText=" .. tostring(f_target.nameTxt:GetText()))
    -- Tenter avec une string Lua pure
    local okSet2, errSet2 = pcall(function() f_target.nameTxt:SetText("TEST_NOM") end)
    P("SetText('TEST_NOM') ok=" .. tostring(okSet2) .. (not okSet2 and " err=" .. tostring(errSet2) or ""))
    P("GetText apres TEST=" .. tostring(f_target.nameTxt:GetText()))
  end

  -- 3. UnitReaction
  local ok2, react = pcall(function() return UnitReaction(unit, "player") end)
  P("UnitReaction ok=" .. tostring(ok2) .. " val=" .. tostring(react))

  if TopTargetBar._lastNameErr then
    P("Dernier err styling: " .. tostring(TopTargetBar._lastNameErr))
  end

  -- 4. Forcer UpdateTarget et relire EN CAPTURANT L'ERREUR
  pcall(_UpdateTargetColor)
  local _nok, _nerr = pcall(_UpdateTargetName)
  P("pcall(_UpdateTargetName): ok=" .. tostring(_nok) .. (not _nok and " ERR=" .. tostring(_nerr) or ""))
  if f_target and f_target.nameTxt then
    P("GetText APRES update=" .. tostring(f_target.nameTxt:GetText()))
  end
  if TopTargetBar._lastNameErr then
    P("lastNameErr=" .. tostring(TopTargetBar._lastNameErr))
  end
  P("nameFrame=" .. tostring(f_target and f_target.nameFrame ~= nil) ..
    " shown=" .. tostring(f_target and f_target.nameFrame and f_target.nameFrame:IsShown()))
  P("Fait.")
end

-- Interface publique
function TopTargetBar.GetTargetFrame()
    return f_target
end

function TopTargetBar.Create()
    if f_target then
        -- Déjà créé (PLAYER_ENTERING_WORLD multiple) : juste réappliquer les settings
        TopTargetBar.ApplySettings()
        return
    end
    f_target = CreateTargetBar()
    f_tt     = CreateTargetTargetBar()
    SetTTBVisibilityDrivers()
    UpdateTarget()
    UpdateTargetTarget()

    -- Visibilité quand le panel de config s'ouvre
    C_Timer.After(0, function()
        local panel = _G["AishCoreSettingsPanel"]
        if panel then
            panel:HookScript("OnShow", function()
                -- Preview : forcer l'affichage + noms de test
                if not InCombatLockdown() then
                    local cfg = ns.GetCfg("topTargetBar")
                    local en  = not (cfg and cfg.enabled == false)
                    if en then
                        RegisterStateDriver(f_target, "visibility", "show")
                        if f_tt then RegisterStateDriver(f_tt, "visibility", "show") end
                    end
                end
                ttbPreviewMode = true
                pcall(_UpdateTargetName)
                pcall(_UpdateTTName)
                -- Barre HP à 75 % pour la preview
                if f_target then
                    f_target.bar:SetMinMaxValues(0, 1)
                    f_target.bar:SetValue(0.75)
                    if f_target.hpFrame then f_target.hpFrame:Show() end
                    if f_target.hpTxt   then f_target.hpTxt:SetText("75K") end
                    -- Barre de ressource a 60% pour la preview (sinon vide/a
                    -- 0 tant qu'aucune vraie cible n'existe, cf. _TickTargetPower).
                    if f_target.powerBar then
                        f_target.powerBar:SetMinMaxValues(0, 1)
                        f_target.powerBar:SetValue(0.6)
                    end
                end
                if f_tt then
                    f_tt.bar:SetMinMaxValues(0, 1)
                    f_tt.bar:SetValue(0.5)
                end
            end)
            panel:HookScript("OnHide", function()
                ttbPreviewMode = false
                SetTTBVisibilityDrivers()
                UpdateTarget()
                UpdateTargetTarget()
            end)
        end
    end)

    -- Hook sur la StatusBar normalisée (0-1) de TargetFrame pour mettre à jour la barre de vie. Pas de texte HP (secret number).
    C_Timer.After(3, function()
        local hbar = FindTargetHealthBarInTree()
        -- Fonctions pré-allouées pour les hooks OnValueChanged (évite une closure inline à chaque changement de HP)
        local function _ApplyTargetBarValue(v)
            f_target.bar:SetMinMaxValues(0, 1); f_target.bar:SetValue(v)
        end
        local function _ApplyTTBarValue(v)
            f_tt.bar:SetMinMaxValues(0, 1); f_tt.bar:SetValue(v)
        end

        if hbar then
            hbar:HookScript("OnValueChanged", function(self, value)
                if not f_target then return end
                _hp.target.cur = value; _hp.target.max = 1
                pcall(_ApplyTargetBarValue, value)
            end)
        end

        local totbar = FindToTHealthBarInTree()
        if totbar then
            totbar:HookScript("OnValueChanged", function(self, value)
                if not f_tt then return end
                _hp.targettarget.cur = value; _hp.targettarget.max = 1
                pcall(_ApplyTTBarValue, value)
            end)
        end
    end)
end

-- Abréviation des HP (taint-safe) : AbbreviateNumbers (C-function) accepte les secret numbers, breakpoints localisés par défaut ("K", "M", etc.)
local function ShortenHP(value)
    if AbbreviateNumbers then
        local ok, str = pcall(AbbreviateNumbers, value)
        if ok and str then return str end
    end
    -- Fallback : essayer via pcall un formatage Lua classique
    local ok2, str2 = pcall(AbbreviateNumber, value)
    if ok2 and str2 then return str2 end
    return ""
end

-- Ticker barre de vie : UnitHealth() retourne un "secret number" non convertible en string, mais SetMinMaxValues/SetValue l'acceptent via pcall.
-- Fonctions pré-allouées pour pcall : évite de créer une closure à chaque tick (10/sec)
local function _TickTargetHP()
    local cur = UnitHealth("target")
    local max = UnitHealthMax("target")
    f_target.bar:SetMinMaxValues(0, max)
    f_target.bar:SetValue(cur)
    if f_target.hpTxt then
        local txt = ShortenHP(cur)
        f_target.hpTxt:SetText(txt)
        if f_target.hpFrame and not f_target.hpFrame:IsShown() then
            f_target.hpFrame:Show()
        end
    end
end
local function _TickTTHP()
    local cur = UnitHealth("targettarget")
    local max = UnitHealthMax("targettarget")
    f_tt.bar:SetMinMaxValues(0, max)
    f_tt.bar:SetValue(cur)
end
local function _TickTargetPower()
    if not f_target.powerBar or not f_target.powerBar:IsShown() then return end
    local cur = UnitPower("target")
    local max = UnitPowerMax("target")
    if max <= 0 then max = 1 end
    f_target.powerBar:SetMinMaxValues(0, max)
    f_target.powerBar:SetValue(cur)
end

C_Timer.NewTicker(0.1, function()
    if f_target and f_target:IsShown() and UnitExists("target") then
        pcall(_TickTargetHP)
        pcall(_TickTargetPower)
    end
    if f_tt and f_tt:IsShown() and UnitExists("targettarget") then
        pcall(_TickTTHP)
    end
end)

--- Cache (on=true) ou restaure (on=false) la barre cible pour l'onglet Animations 3D.
--- Utilise SetAlpha pour éviter tout conflit avec les StateDrivers sécurisés.
function TopTargetBar.SetGuiHidden(on)
    local a = on and 0 or 1
    if f_target     then f_target:SetAlpha(a)               end
    if f_target and f_target.nameFrame then f_target.nameFrame:SetAlpha(a) end
    if f_target and f_target.hpFrame   then f_target.hpFrame:SetAlpha(a)   end
    if f_tt         then f_tt:SetAlpha(a)                   end
end

function TopTargetBar.ApplySettings()
    local db = ns.GetCfg("topTargetBar")

    -- Module désactivé → StateDriver "hide" (sécurisé en combat)
    -- Module activé → StateDriver normal (géré en fin de fonction)

    if f_target then
        -- Conteneur — ancré sur WorldFrame
        local ox  = (db and db.x) or 0
        local oy  = (db and db.y) or 0
        f_target:ClearAllPoints()
        f_target:SetPoint("TOP", WorldFrame, "TOP", ox, oy)

        -- Fond noir
        local bgfW  = (db and db.bgW)  or 530
        local bgfH  = (db and db.bgH)  or 35
        local bgfOX = (db and db.bgOX) or 0
        local bgfOY = (db and db.bgOY) or 0
        f_target.bgFull:SetSize(bgfW, bgfH)
        f_target.bgFull:ClearAllPoints()
        f_target.bgFull:SetPoint("CENTER", f_target, "CENTER", bgfOX, bgfOY)

        -- Barre de vie
        local bw  = (db and db.barW)  or 525
        local bh  = (db and db.barH)  or 2
        local box = (db and db.barOX) or 0
        local boy = (db and db.barOY) or -22
        local showPower   = db and db.showPowerBar
        -- Quand la barre de ressource est active, la barre de vie remonte de (bh+1) px
        local healthBarOY = showPower and (boy + bh + 1) or boy
        f_target.bar:SetSize(bw, bh)
        f_target.bar:ClearAllPoints()
        f_target.bar:SetPoint("TOP", f_target, "TOP", box, healthBarOY)
        f_target.barBg:ClearAllPoints()
        f_target.barBg:SetPoint("TOPLEFT",     f_target.bar, "TOPLEFT",     -1,  1)
        f_target.barBg:SetPoint("BOTTOMRIGHT", f_target.bar, "BOTTOMRIGHT",  1, -1)

        -- Barre de ressource
        if f_target.powerBar then
            if showPower then
                f_target.powerBar:SetSize(bw, bh)
                f_target.powerBar:ClearAllPoints()
                f_target.powerBar:SetPoint("TOP", f_target, "TOP", box, boy)
                f_target.powerBarBg:ClearAllPoints()
                f_target.powerBarBg:SetPoint("TOPLEFT",     f_target.powerBar, "TOPLEFT",     -1,  1)
                f_target.powerBarBg:SetPoint("BOTTOMRIGHT", f_target.powerBar, "BOTTOMRIGHT",  1, -1)
                if UnitExists("target") then
                    local pc = GetPowerBarColor("target")
                    f_target.powerBar:SetStatusBarColor(pc[1], pc[2], pc[3], 1)
                end
                f_target.powerBar:Show()
                f_target.powerBarBg:Show()
            else
                f_target.powerBar:Hide()
                f_target.powerBarBg:Hide()
            end
        end

        -- Texte nom/niveau — repositionner nameFrame (le FontString est centré dedans)
        local nox = (db and db.nameOX) or 0
        local noy = (db and db.nameOY) or -5
        f_target.nameTxt:SetFont((db and db.nameFont) or BEBAS_FONT, 15, "")
        if f_target.nameFrame then
            f_target.nameFrame:ClearAllPoints()
            f_target.nameFrame:SetPoint("TOP", f_target, "TOP", nox, noy)
        end

        -- Texte HP
        local hox     = (db and db.hpOX)       or 5
        local hoy     = (db and db.hpOY)       or -19
        local hpts    = (db and db.hpFontSize) or 10
        local hanchor = (db and db.hpAnchor)   or "LEFT"
        if f_target.hpFrame then
            local bgfW = (db and db.bgW) or 530
            f_target.hpFrame:SetSize(bgfW, 20)
            f_target.hpFrame:ClearAllPoints()
            f_target.hpFrame:SetPoint(hanchor, f_target.bgFull, hanchor, hox, hoy)
        end
        if f_target.hpTxt then
            local _hpFont = (db and db.hpFont) or MONTSERRAT_BI
            if not f_target.hpTxt:SetFont(_hpFont, hpts, "") then
                f_target.hpTxt:SetFont("Fonts\\FRIZQT__.TTF", hpts, "")
            end
            f_target.hpTxt:SetJustifyH(hanchor)
            f_target.hpTxt:ClearAllPoints()
            f_target.hpTxt:SetPoint(hanchor, f_target.hpFrame, hanchor, 0, 0)
        end
    end

    if f_tt then
        -- Conteneur
        local ttx = (db and db.ttx) or 0
        local tty = (db and db.tty) or -75
        f_tt:ClearAllPoints()
        f_tt:SetPoint("CENTER", UIParent, "TOP", ttx, tty)

        -- Fond noir TT
        local ttbgW  = (db and db.ttBgW)  or 125
        local ttbgH  = (db and db.ttBgH)  or 24
        local ttbgOX = (db and db.ttBgOX) or 0
        local ttbgOY = (db and db.ttBgOY) or 0
        f_tt.bgTex:SetSize(ttbgW, ttbgH)
        f_tt.bgTex:ClearAllPoints()
        f_tt.bgTex:SetPoint("CENTER", f_tt, "CENTER", ttbgOX, ttbgOY)

        -- Barre de vie TT
        local tbw  = (db and db.ttBarW)  or 124
        local tbh  = (db and db.ttBarH)  or 1.7
        local tbox = (db and db.ttBarOX) or 0
        local tboy = (db and db.ttBarOY) or -10.161
        f_tt.bar:SetSize(tbw, tbh)
        f_tt.bar:ClearAllPoints()
        f_tt.bar:SetPoint("CENTER", f_tt, "CENTER", tbox, tboy)

        -- Texte nom TT
        local tnox = (db and db.ttNameOX) or 0
        local tnoy = (db and db.ttNameOY) or 0.860
        f_tt.nameTxt:SetFont((db and db.nameFont) or BEBAS_FONT, 12, "")
        f_tt.nameTxt:ClearAllPoints()
        f_tt.nameTxt:SetPoint("CENTER", f_tt, "CENTER", tnox, tnoy)
    end

    UpdateTarget()
    UpdateTargetTarget()
    SetTTBVisibilityDrivers()

    -- Force le re-rendu immédiat de la frame HP pour que la preview GUI soit à jour sans changer de cible
    local _dbE = ns.GetCfg("topTargetBar")
    if f_target and f_target.hpFrame and UnitExists("target")
    and not (_dbE and _dbE.enabled == false) then
        local cur = UnitHealth("target")
        local txt = ShortenHP(cur)
        if f_target.hpTxt then
            f_target.hpTxt:SetText("")
            f_target.hpTxt:SetText(txt)
        end
        f_target.hpFrame:Hide()
        f_target.hpFrame:Show()
    end
end

-- Événements
local evtFrame = CreateFrame("Frame")
-- UNIT_HEALTH / UNIT_MAXHEALTH retirés : mis à jour par le hook OnValueChanged sur TargetFrame.HealthBar
evtFrame:RegisterUnitEvent("UNIT_FACTION",      "target", "targettarget")
evtFrame:RegisterUnitEvent("UNIT_NAME_UPDATE",   "target", "targettarget")
evtFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "target")
evtFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
evtFrame:RegisterEvent("UNIT_TARGET")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- fin de combat : update visibility
evtFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
evtFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
evtFrame:RegisterEvent("PET_BATTLE_OPENING_START")
evtFrame:RegisterEvent("PET_BATTLE_CLOSE")

evtFrame:SetScript("OnEvent", function(self, event, arg1)
    if not f_target then return end

    if event == "PLAYER_TARGET_CHANGED" then
        C_Timer.After(0, _DoUpdateBoth)
        return
    end

    if event == "UNIT_TARGET" and arg1 == "target" then
        C_Timer.After(0, UpdateTargetTarget)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0, _DoUpdateBoth)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0, _DoUpdateBoth)
        if pendingDriverUpdate then
            C_Timer.After(0, SetTTBVisibilityDrivers)
        end
        return
    end

    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE"
    or event == "PET_BATTLE_OPENING_START" or event == "PET_BATTLE_CLOSE" then
        SetTTBVisibilityDrivers()
        return
    end

    if event == "UNIT_DISPLAYPOWER" and arg1 == "target" then
        -- Type de puissance changé (ex: métamorphose, forme aquatique…) → recalculer couleur
        C_Timer.After(0, UpdateTarget)
        return
    end

    if event == "UNIT_FACTION" then
        -- Seul UNIT_FACTION change les couleurs (réaction/classe) ; les HP sont déjà gérés par le hook OnValueChanged
        if     arg1 == "target"       then C_Timer.After(0, UpdateTarget)
        elseif arg1 == "targettarget" then C_Timer.After(0, UpdateTargetTarget)
        end
        return
    end

    if event == "UNIT_NAME_UPDATE" then
        -- Nom résolu en asynchrone (NPCs spawnés en cours d'encounter, nouveau raid).
        if     arg1 == "target"       then C_Timer.After(0, UpdateTarget)
        elseif arg1 == "targettarget" then C_Timer.After(0, UpdateTargetTarget)
        end
        return
    end
end)

-- Ticker : mise à jour visibilité + couleurs toutes les 500ms (rattrape un event manqué : cible morte, sortie combat, transition de zone)
C_Timer.NewTicker(0.5, function()
    if not f_target then return end
    -- UnitExists plutôt que IsVisible() : ce dernier peut être false si un parent est temporairement masqué
    if not UnitExists("target") then return end
    UpdateTarget()
    UpdateTargetTarget()
end)

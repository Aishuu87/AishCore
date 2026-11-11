-- Modules/UnitBars.lua : Barres de vie Player, Target, Focus, Pet, TargetTarget
-- Reglages communs (couleurs, bouclier, soins previsionnels, hauteur tank, visibilite) a la racine de ns.DB.unitBars ;
-- tout le reste est propre a chaque barre (ns.DB.unitBars.bars.<cle>, lu par BV). Le rendu d'une barre (LayoutBar)
-- sert aussi a l'apercu du GUI (UnitBars.CreatePreview / StylePreview, UI/UnitBarsPage.lua).
local addonName, ns = ...
local L = ns.L

local UnitBars = {}
ns.Modules.UnitBars = UnitBars

local DEFAULT_FONT   = ns.FONT_FALLBACK  -- police du jeu (2002), aucune media pack requise
-- Couleur "noire" commune (#0e0e0e)
local DARK         = 14/255
-- Couleur de fond commune (presque noir)
local DEFAULT_BG   = { DARK, DARK, DARK, 1 }

-- Points decoratifs : proportions des formes selon leur nombre, de la plus eloignee de la barre a la plus proche (= 1).
-- Pour 3 points : 3 / 5 / 9, le rendu historique.
local DOT_MAX   = 5
local DOT_BASES = {
    { 1 },
    { 5/9, 1 },
    { 3/9, 5/9, 1 },
    { 2/9, 3/9, 5/9, 1 },
    { 2/9, 3/9, 4/9, 6/9, 1 },
}
-- Formes : texture, rotation (rad) et echelle d'affichage (le losange est un carre tourne, ramene a la meme
-- diagonale). Le chevron (pointe en haut dans le fichier) est tourne vers l'exterieur de la barre (cf. LayoutDots).
local DOT_SHAPES = {
    circle  = { tex = "Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2.tga" },
    square  = { tex = "Interface\\Buttons\\WHITE8x8" },
    diamond = { tex = "Interface\\Buttons\\WHITE8x8", rot = math.pi / 4, scale = 0.7071 },
    chevron = { tex = "Interface\\AddOns\\AishCore\\Media\\UI\\chevron.png", outward = true },
}
UnitBars.DOT_MAX    = DOT_MAX
-- Formes combinees : { forme la plus proche de la barre, forme des suivantes }
local DOT_COMBOS = {
    circle_chevron  = { "circle", "chevron" },
    diamond_chevron = { "diamond", "chevron" },
    square_circle   = { "square", "circle" },
}
UnitBars.DOT_SHAPES = { "circle", "chevron", "diamond", "square", "circle_chevron", "diamond_chevron", "square_circle" }

-- Ombre derriere la barre (client sans cet atlas : aplat noir, opacite du reglage)
local NAME_SHADOW_ATLAS = "Banner-FiligreeShadow"

-- Formes du cadre du texte de vie (etirees a sa taille)
local HP_BOX_TEX = {
    rect    = "Interface\\Buttons\\WHITE8x8",
    diamond = "Interface\\AddOns\\AishCore\\Media\\UI\\Diamond.tga",
    circle  = "Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2.tga",
}

-- Sens de remplissage : orientation de la StatusBar, bords de depart et d'arrivee du remplissage (les soins
-- previsionnels et l'absorb s'accrochent au bord d'arrivee)
local FILL_DIRS = {
    LTR = { orient = "HORIZONTAL", rev = false, from = "LEFT",   to = "RIGHT"  },
    RTL = { orient = "HORIZONTAL", rev = true,  from = "RIGHT",  to = "LEFT"   },
    BTT = { orient = "VERTICAL",   rev = false, from = "BOTTOM", to = "TOP"    },
    TTB = { orient = "VERTICAL",   rev = true,  from = "TOP",    to = "BOTTOM" },
}
UnitBars.FILL_DIRS = { "LTR", "RTL", "BTT", "TTB" }

-- Spécialisations tank : reçoivent une HAUTEUR de barre spécifique si l'option est
-- activée (cfg.useTankHeight / cfg.tankHeight, cf. GetEffectiveHeight). La largeur,
-- elle, ne dépend pas de la spé.
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

--- Met a jour `inTankSpec`. Renvoie false si la spe n'a PAS pu etre resolue.
--- Distinction importante : juste apres un /reload, ns.GetSpecialization() repond nil
--- pendant quelques instants. L'ancienne version passait alors 0 a
--- ns.GetSpecializationInfo, recevait nil, et en concluait "pas tank" -- les barres
--- gardaient donc leur geometrie non-tank jusqu'au prochain changement de spe.
--- On ne touche plus a inTankSpec tant que la reponse n'est pas fiable.
local function UpdateTankSpec()
    local idx = ns.GetSpecialization and ns.GetSpecialization()
    if not idx or idx == 0 then return false end
    local ok, specID = pcall(ns.GetSpecializationInfo, idx)
    if not ok or not specID or specID == 0 then return false end
    -- spe issue de la seule "spe par defaut" des couleurs : ce n'est pas une vraie spe tank
    if ns.IsSpecDefaulted and ns.IsSpecDefaulted() then inTankSpec = false; return true end
    inTankSpec = TANK_SPECS[specID] or false
    return true
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

-- Couleurs de réaction PNJ : réglables (unitBars.hostileColor...), repli identique à TopTargetBar
local REACTION_DEFAULTS = {
    neutral  = { 0.855, 0.773, 0.361, 1 },
    friendly = { 0.294, 0.686, 0.298, 1 },
    hostile  = { 0.780, 0.251, 0.251, 1 },
    lowLevel = { 0.5, 0.5, 0.5, 1 },
}
local function ReactionColor(kind)
    local db = ns.GetCfg("unitBars")
    return db and db[kind .. "Color"] or REACTION_DEFAULTS[kind]
end

-- PNJ "gris" (trop bas niveau pour rapporter de l'XP) : difficulté relative si l'API existe, sinon écart de niveau
local function IsLowLevel(unit)
    local ok, low = pcall(function()
        local api = C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer
        if api and Enum and Enum.RelativeContentDifficulty then
            return api(unit) == Enum.RelativeContentDifficulty.Trivial
        end
        local lvl = tonumber(tostring(UnitLevel(unit))) or 0
        if lvl <= 0 then return false end
        local green = (GetQuestGreenRange and GetQuestGreenRange()) or 8
        return lvl < UnitLevel("player") - green
    end)
    return ok and low or false
end

-- Descripteurs de chaque barre (ordre de creation : le pet s'ancre sur le joueur). Les reglages par defaut d'une barre
-- sont dans Config/Defaults.lua (unitBars.bars) ; `defaults` ne sert que de repli de position / couleur.
local BAR_DEFS = {
    { key = "player",       unit = "player",       defaults = { x = -260, y = -120, fillColor = { 0.78, 0.61, 0.44, 1 } } },
    { key = "target",       unit = "target",       defaults = { x =  260, y = -120, fillColor = { 0.72, 0.59, 0.39, 1 } } },
    { key = "focus",        unit = "focus",        defaults = { x = -260, y = -145, fillColor = { 0.71, 0.60, 0.49, 1 } } },
    { key = "pet",          unit = "pet",          defaults = { x = -260, y = -100, fillColor = { 0.71, 0.60, 0.49, 1 } } },
    { key = "targettarget", unit = "targettarget", defaults = { x =  260, y = -145, fillColor = { 0.41, 0.41, 0.41, 1 } } },
}
local DEF_BY_KEY = {}
for _, d in ipairs(BAR_DEFS) do DEF_BY_KEY[d.key] = d end
UnitBars.BAR_KEYS = { "player", "target", "focus", "pet", "targettarget" }

-- Tables des frames créés
local bars = {}   -- bars[key] = frame
local pendingSettingsApply  = false  -- re-appliquer les settings apres combat
local FadePlayerName   -- forward (nom du joueur au survol)
local playerNameFadingOut = false   -- fondu de sortie du nom du joueur en cours : texte garde jusqu'a la fin
local ubFadeTickers         = {}     -- key → ticker de fade par barre
local ubPosPending          = {}     -- key → frame dont le snap de position finale a ete saute (combat lockdown)
local ubLastVisState        = {}     -- key → dernier état de visibilité (true/false)
local ubHovered             = {}     -- key → true si le curseur est dans la zone tolérante
local playerNameShown        = false  -- nom du personnage affiche au survol de sa barre (option showName du joueur, hors combat)
local ubHiddenForSkyriding  = false  -- masquées pour le skyriding
local ubHiddenForGui        = false  -- onglet Animations 3D : tout masqué
local ubPreviewMode         = false  -- panneau settings ouvert → forcer affichage
local inVehicle             = false
local inPetBattle           = false

-- Helpers
local function Cfg(key)
    local db = ns.GetCfg("unitBars")
    return db and db.bars and db.bars[key] or {}
end

-- Reglage d'une barre : sa valeur, sinon le defaut de cette barre (Config/Defaults.lua)
local function BV(key, prop)
    local v = Cfg(key)[prop]
    if v ~= nil then return v end
    local d = ns.Defaults and ns.Defaults.unitBars and ns.Defaults.unitBars.bars
    d = d and d[key]
    return d and d[prop]
end
UnitBars.BV = BV

-- Anciens reglages communs a toutes les barres, devenus propres a chacune : repris une fois par barre (drapeau
-- perBarSettings), pour garder le rendu du profil. A rappeler a chaque changement de profil (cf. ApplySettings).
local LEGACY_PER_BAR = {
    nameFont = "nameFont", nameOutline = "nameOutlineStyle", nameSize = "nameSize",
    hpFont = "font", hpOutline = "hpOutlineStyle", hpSize = "textSize",
    hpMode = "hpDisplayMode", hpHoverValue = "hpHoverValue",
    barTexture = "barTexture", showDots = "showDots",
    dotSize = "dotSize", dotRatio = "dotRatio", dotGap = "dotGap",
}
local function EnsurePerBar()
    local db = ns.DB and ns.DB.unitBars
    if not db or db.perBarSettings then return end
    db.perBarSettings = true
    db.bars = db.bars or {}
    for _, d in ipairs(BAR_DEFS) do
        local b = db.bars[d.key] or {}
        db.bars[d.key] = b
        for p, g in pairs(LEGACY_PER_BAR) do
            if db[g] ~= nil then b[p] = db[g] end
        end
        if db.bgTexture or db.barTexture then b.bgTexture = db.bgTexture or db.barTexture end
    end
    local bb = db.bars
    bb.player.showName = db.showPlayerNameHover == true
    bb.target.showLevel = db.showTargetLevel == true
    bb.targettarget.showDots = false   -- n'en a jamais eu
end

-- Nom du joueur (au survol de sa barre) : une seule fois, meme decalage que le nom de la barre de cible, en miroir
-- (le nom de la cible est decale de X vers la droite pour laisser la place au texte de PV ; celui du joueur, aligne a
-- droite, de -X vers la gauche). Ne touche pas a un decalage deja regle a la main (different de 0).
local function EnsurePlayerNameOffset()
    local db = ns.GetCfg("unitBars")
    if not db or db.playerNameOffsetDone then return end
    db.playerNameOffsetDone = true
    local p = db.bars and db.bars.player
    local t = db.bars and db.bars.target
    if p and (p.nameOffX or 0) == 0 then p.nameOffX = -((t and t.nameOffX) or 0) end
end

-- Tolerance de survol : la zone deborde la frame de `tol` px de chaque cote. Test maison
-- plutot que MouseIsOver(), pour couvrir exactement le meme rectangle que le pad de clic
-- (cf. ApplyHitPad) et garder des offsets symetriques quelle que soit la version du client.
-- La frame reste Shown a alpha 0 (cf. AnimateBar), donc le survol d'une barre masquee marche.
local function IsBarHovered(frame, tol)
    if not frame:IsVisible() then return false end
    local left, bottom, w, h = frame:GetRect()
    if not left then return false end
    local scale = frame:GetEffectiveScale()
    if not scale or scale <= 0 then return false end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    return cx >= left - tol and cx <= left + w + tol
       and cy >= bottom - tol and cy <= bottom + h + tol
end

-- Tolerance telle que configuree : nulle si "Au survol" est decoche, le slider n'etant
-- qu'un reglage de cette option. Ne dit rien du combat -- c'est le pad de clic ci-dessous
-- qui s'en charge, par un mecanisme que le lockdown ne peut pas bloquer.
-- Montures sans zone elargie : celles qui affichent le HUD de sieges (VehicleSeatIndicator) ou qui ont leurs
-- PNJ / services (reparation...) : ID de monture (Journal des montures), cf. wowhead.com/mount/<ID>.
local NO_TOL_MOUNTS = { 2237, 1039, 2982 }
local noTolMount = false
-- Vehicule, mini-jeu (barre de vehicule / barre de remplacement / possession) ou combat de mascottes : pas de zone
-- elargie non plus, elle gene le clic sur les elements de l'interface propre a ces modes.
local function InVehicleOrMinigame()
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return true end
    if UnitInVehicle and UnitInVehicle("player") then return true end
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return true end
    if HasVehicleActionBar and HasVehicleActionBar() then return true end
    if HasOverrideActionBar and HasOverrideActionBar() then return true end
    if IsPossessBarVisible and IsPossessBarVisible() then return true end
    return false
end

local function ComputeNoTolMount()
    if InVehicleOrMinigame() then return true end
    if _G.VehicleSeatIndicator and _G.VehicleSeatIndicator:IsShown() then return true end
    if IsMounted() and C_MountJournal and C_MountJournal.GetMountInfoByID then
        for _, id in ipairs(NO_TOL_MOUNTS) do
            local ok, _, _, _, isActive = pcall(C_MountJournal.GetMountInfoByID, id)
            if ok and isActive then return true end
        end
    end
    return false
end

-- Regles de visibilite : cases cumulables (l'une suffit a montrer la barre), en combat toujours visibles.
--   always     Toujours (prime sur les 5 suivantes)      hover      Au survol
--   friendly   cible alliee                              attackable cible attaquable
--   group      en groupe                                 instance   en instance
--   hideMount  cacher en monture                         hideRest   cacher en zone de repos
-- Invariant : always ou hover (decocher l'un coche l'autre, cf. UnitBars.SetVisRule). "Options par role"
-- (roleVisibility) : un jeu de regles par role de la spe active (DAMAGER / HEALER / TANK), sinon visRules.
-- Profil sans regles : derivees de l'ancien reglage (visibilityMode / alwaysInInstance), sans rien ecrire.
UnitBars.VIS_KEYS = { "always", "hover", "friendly", "attackable", "group", "instance", "hideMount", "hideRest" }

local function LegacyVisRules(db)
    local mode = db.visibilityMode or (db.hideOutOfCombat and "combat") or "combat"
    return {
        always = (mode == "always"), hover = true, friendly = false, attackable = (mode == "target"),
        group = false, instance = db.alwaysInInstance == true, hideMount = false, hideRest = false,
    }
end

--- Regles d'un role ("DAMAGER" / "HEALER" / "TANK"), ou les regles simples (role nil). Lecture seule.
function UnitBars.GetVisRules(role)
    local db = ns.GetCfg("unitBars") or {}
    if role then
        local t = db.visRulesRole and db.visRulesRole[role]
        if t then return t end
    end
    return db.visRules or LegacyVisRules(db)
end

--- Role dont les regles s'appliquent maintenant (nil = options par role coupees).
function UnitBars.ActiveVisRole()
    local db = ns.GetCfg("unitBars")
    if not (db and db.roleVisibility) then return nil end
    -- Augmentation (et toute spe de ns.HEALER_LIKE_SPECS) : colonne Soigneur
    if ns.IsHealerLikeSpec and ns.IsHealerLikeSpec() then return "HEALER" end
    local idx = ns.GetSpecialization and ns.GetSpecialization()
    local role = idx and ns.GetSpecializationRole and ns.GetSpecializationRole(idx)
    return (role == "HEALER" or role == "TANK") and role or "DAMAGER"
end

--- Ecrit une case (cree le jeu de regles a la premiere modification) et tient l'invariant always / hover.
function UnitBars.SetVisRule(role, key, value)
    ns.DB.unitBars = ns.DB.unitBars or {}
    local db = ns.DB.unitBars
    local t
    if role then
        db.visRulesRole = db.visRulesRole or {}
        t = db.visRulesRole[role]
        if not t then t = CopyTable(UnitBars.GetVisRules(nil)); db.visRulesRole[role] = t end
    else
        t = db.visRules
        if not t then t = CopyTable(LegacyVisRules(db)); db.visRules = t end
    end
    t[key] = value and true or false
    if key == "always" and not value then t.hover = true end
    if key == "hover" and not value then t.always = true end
end

local function ActiveVisRules() return UnitBars.GetVisRules(UnitBars.ActiveVisRole()) end

-- Survol utile seulement s'il peut reveler la barre : sans "Toujours" (qui la montre deja), ou avec un "Cacher"
-- (le survol passe avant eux)
local function HoverRevealActive()
    local r = ActiveVisRules()
    return r.hover and (not r.always or r.hideMount or r.hideRest) and true or false
end

local function ConfiguredHoverTol()
    local db = ns.GetCfg("unitBars")
    if not (db and HoverRevealActive()) then return 0 end
    -- Monture a PNJ / a passagers : pas de zone elargie, elle masquait les PNJ de la monture.
    -- Le pad est de toute facon retire en combat.
    if noTolMount then return 0 end
    return db.hoverTolerance or 0
end

--- Tolerance applicable a cet instant : nulle en combat, ou le pad est retire. La detection
--- du survol et l'apercu doivent suivre exactement la zone reellement cliquable.
local function EffectiveHoverTol()
    if InCombatLockdown() then return 0 end
    return ConfiguredHoverTol()
end

-- Zone de clic elargie : un bouton securise dedie, pas la barre elle-meme.
-- SetHitRectInsets sur la barre est refuse une fois le combat engage (frame protegee), donc
-- impossible d'y retirer la tolerance au moment ou elle gene. RegisterStateDriver, lui,
-- masque une frame protegee en plein combat -- c'est son role. Le pad porte la tolerance,
-- le driver le retire du combat, et la barre garde sa hitbox d'origine en permanence.
local function ApplyHitPad(frame, tol)
    local pad = frame._hitPad
    if not pad or InCombatLockdown() then return end
    -- Barre desactivee (module ou barre) : elle reste a alpha 0 mais captait encore les clics
    local db = ns.GetCfg("unitBars")
    local def = frame._def   -- nil a la creation : ApplyBarSettings repasse juste apres
    local off = (db and db.enabled == false) or (def and Cfg(def.key).enabled == false)
    frame:EnableMouse(not off)
    pad:ClearAllPoints()
    if off or tol <= 0 then
        UnregisterStateDriver(pad, "visibility")
        pad:Hide()
        return
    end
    pad:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -tol,  tol)
    pad:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  tol, -tol)
    RegisterStateDriver(pad, "visibility", "[combat] hide; show")
end

-- ------------------------------------------------------------------
-- Apercu de la hitbox (cadre bleute pendant le reglage de la tolerance)
-- ------------------------------------------------------------------
local HITBOX_HOLD  = 3.0            -- s a pleine opacite apres la derniere retouche
local HITBOX_FADE  = 0.6            -- s de fondu
local HITBOX_COLOR = { 0.35, 0.68, 1, 0.9 }
local hitboxTimer, hitboxTicker

-- Parent UIParent et non la barre : une barre masquee est a alpha 0, et l'alpha d'un parent
-- multiplie celui de ses enfants -- le cadre serait donc invisible la ou il sert le plus.
local function EnsureHitboxFrame(frame)
    if frame._hitPreview then return frame._hitPreview end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:Hide()
    local edges = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(unpack(HITBOX_COLOR))
        edges[i] = t
    end
    f._edges = edges
    edges[1]:SetPoint("TOPLEFT");     edges[1]:SetPoint("TOPRIGHT");    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT");  edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT");     edges[3]:SetPoint("BOTTOMLEFT");  edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT");    edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    frame._hitPreview = f
    return f
end

--- Montre le cadre de la zone cliquable sur chaque barre active, puis le fait disparaitre
--- en fondu apres HITBOX_HOLD. Rappele a chaque cran du slider : le compte a rebours
--- repart de zero tant qu'on y touche. Le cadre epouse la tolerance REELLE, donc il colle
--- a la barre quand "Au survol" est decoche -- ce qui montre que le slider n'agit pas.
function UnitBars.FlashHitbox()
    local tol = EffectiveHoverTol()
    local shown = {}
    local dbAll = ns.GetCfg("unitBars")
    if dbAll and dbAll.enabled == false then UnitBars.HideHitbox(); return end   -- module coupe : aucun apercu
    for key, f in pairs(bars) do
        -- Repartir propre : une barre decochee entre deux passages garderait son cadre
        -- allume, le ticker precedent ayant ete annule avant de pouvoir le masquer.
        if f._hitPreview then f._hitPreview:Hide() end
        if Cfg(key).enabled ~= false then
            local p = EnsureHitboxFrame(f)
            local r, g, b = ns.HitboxColor()   -- couleur des hitbox (Couleurs Thematiques, sinon bleu)
            for _, t in ipairs(p._edges) do t:SetColorTexture(r, g, b, HITBOX_COLOR[4]) end
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT",     f, "TOPLEFT",     -tol,  tol)
            p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  tol, -tol)
            p:SetAlpha(1)
            p:Show()
            shown[#shown + 1] = p
        end
    end
    if #shown == 0 then return end

    if hitboxTimer  then hitboxTimer:Cancel();  hitboxTimer  = nil end
    if hitboxTicker then hitboxTicker:Cancel(); hitboxTicker = nil end
    hitboxTimer = C_Timer.NewTimer(HITBOX_HOLD, function()
        hitboxTimer = nil
        local t0 = GetTime()
        hitboxTicker = ns.NewTicker(0.03, function()
            local a = 1 - math.min((GetTime() - t0) / HITBOX_FADE, 1)
            for _, fr in ipairs(shown) do fr:SetAlpha(a) end
            if a <= 0 then
                for _, fr in ipairs(shown) do fr:Hide() end
                if hitboxTicker then hitboxTicker:Cancel(); hitboxTicker = nil end
            end
        end)
    end)
end

--- Eteint l'apercu tout de suite (fermeture du panneau, changement de page).
function UnitBars.HideHitbox()
    if hitboxTimer  then hitboxTimer:Cancel();  hitboxTimer  = nil end
    if hitboxTicker then hitboxTicker:Cancel(); hitboxTicker = nil end
    for _, f in pairs(bars) do
        if f._hitPreview then f._hitPreview:Hide() end
    end
end

-- Calcule si une barre doit être visible selon l'état du jeu (pure Lua, pas de StateDriver)
local function ShouldShowBar(frame)
    if ubHiddenForGui  then return false end  -- onglet Animations 3D : masqué
    -- Le toggle (global ou par barre) passe AVANT le mode preview : une barre
    -- coupée depuis la page "Modules" ou "Barres de vie" doit disparaître aussi
    -- de l'aperçu du panneau, pas seulement en jeu (ubPreviewMode retournait
    -- true sans jamais regarder enabled).
    local db  = ns.GetCfg("unitBars")
    local cfg = Cfg(frame._def.key)
    if (db and db.enabled == false) or cfg.enabled == false then return false end
    if ubPreviewMode   then return true  end
    if ns.IsInBlockedState()    then return false end
    if ubHiddenForSkyriding     then return false end
    if inVehicle                then return false end
    if inPetBattle              then return false end
    local unit  = frame._def.unit
    if not UnitExists(unit) then return false end
    -- En combat : toujours visible (regle de base, aucune case ne la desactive)
    if UnitAffectingCombat("player") then return true end
    local r = ActiveVisRules()
    -- Survol : prime sur les "Cacher" (monture, repos), mais reste apres les masquages durs (skyriding, vehicule,
    -- pet battle), qui ne se rouvrent pas a la souris
    if r.hover and ubHovered[frame._def.key] then return true end
    -- Furtivite : la visibilite du Mode furtif remplace les regles ci-dessous (joueur et cible)
    local key = frame._def.key
    if (key == "player" or key == "target") and ns.StealthVisOverride then
        local ov = ns.StealthVisOverride(key)
        if ov ~= nil then return ov end
    end
    -- Les "Cacher" passent avant "Toujours" et les autres conditions
    if r.hideMount and IsMounted() then return false end
    if r.hideRest and ns.IsRestArea() then return false end
    if r.always then return true end
    local hasTarget = UnitExists("target") and not UnitIsDeadOrGhost("target")
    if r.attackable and hasTarget and UnitCanAttack("player", "target") then return true end
    if r.friendly and hasTarget and not UnitCanAttack("player", "target") and UnitIsFriend("player", "target") then return true end
    if r.group and IsInGroup() then return true end
    if r.instance and ns.inInstance then return true end
    return false
end

local function GetBgColor()
    local db = ns.GetCfg("unitBars")
    return db and db.bgColor or DEFAULT_BG
end

-- Couleurs thematiques (defaut) : couleurs du module Couleurs (classe / "PV du Familier"...). Decoche : couleur des barres
-- (barColor) et couleur de l'arriere plan (bgColor) choisies dans les reglages, pour toutes les barres.
local function IsThemedColors()
    local db = ns.GetCfg("unitBars")
    return not db or db.themedColors ~= false
end

-- Le "noir" des barres (remplissage en mode inverse, filet, point le plus proche) : couleur de fond, reglable
-- independamment des couleurs thematiques
local function GetDarkColor()
    return GetBgColor()
end

-- Textures : cles de ns.BAR_TEXTURES resolues a chaque appel, pour que le choix du dropdown s'applique sans /reload.
local function BarTex(key)
    return ns.ResolveBarTexFromKey(BV(key, "barTexture"))
end

-- Texture du FOND de la barre. Par defaut la meme que le remplissage : en mode par defaut (couleurs inversees) la
-- partie coloree EST le fond, la texture choisie doit donc la recouvrir et pas seulement le remplissage sombre.
local function BgTexPath(key)
    return ns.ResolveBarTexFromKey(BV(key, "bgTexture") or BV(key, "barTexture"))
end

-- Peint le fond : texture + teinte (a la place d'un aplat SetColorTexture, qui ignorerait toute texture)
local function PaintBg(tex, c, key)
    tex:SetTexture(BgTexPath(key))
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- Hauteur effective d'une barre : tankHeight si spé tank + option activée
local function GetEffectiveHeight(key)
    local db = ns.GetCfg("unitBars")
    if db and db.useTankHeight and inTankSpec
       and (key == "player" or key == "target" or key == "focus") then
        return db.tankHeight or 8
    end
    return BV(key, "height")
end

-- Couleur d'une unité : classe pour les joueurs, réaction pour les PNJ (cf. TopTargetBar.GetUnitColor)
local function GetClassFillColor(unit, fallback)
    if UnitIsPlayer(unit) then
        -- classFile peut être une valeur secrète (targettarget) : indexation dans le même pcall que UnitClass()
        local ok, color = pcall(function()
            local classFile = select(2, UnitClass(unit))
            return classFile and CLASS_COLORS[classFile]
        end)
        if ok and color then
            return color
        end
        -- Lecture ratée : repli "allié visible" plutôt que le gris de config par défaut (evite un gris fige)
        return ReactionColor("friendly")
    end
    local ok, reaction = pcall(function() return UnitReaction(unit, "player") end)
    if ok and reaction then
        -- UnitReaction peut être un nombre privé en raid : détainter avant comparaison (sinon erreur Lua)
        local r = tonumber(tostring(reaction)) or 0
        if r > 4 then return ReactionColor("friendly") end
        -- Bas niveau : seulement les PNJ hostiles / neutres (les amicaux gardent leur couleur)
        if IsLowLevel(unit) then return ReactionColor("lowLevel") end
        return ReactionColor(r == 4 and "neutral" or "hostile")
    end
    return fallback
end

-- Geometrie d'une barre, calculee depuis la config (jamais lue sur la frame, pour ignorer les animations) :
--   w, h            taille de la barre
--   n, sizes        nombre de points decoratifs et leurs tailles (avant echelle de la forme), du plus eloigne au plus proche
--   dotsW           largeur du groupe de points (le decalage dotGap ne change pas le cadre)
--   totalW, frameH  taille du cadre ; barOffX / barOffY : coin bas gauche de la barre dans le cadre
-- forceDots : points comptes meme desactives (apercu du GUI, ou ils restent visibles estompes).
local function Geometry(key, forceDots)
    local g = { w = BV(key, "width"), h = GetEffectiveHeight(key), sizes = {}, dotsW = 0, n = 0 }
    if forceDots or BV(key, "showDots") then
        g.n = math.max(1, math.min(DOT_MAX, math.floor(BV(key, "dotCount") or 3)))
        local big, ratio, sp = BV(key, "dotSize"), (BV(key, "dotRatio") or 0) / 100, BV(key, "dotSpacing")
        for i = 1, g.n do
            local natural = big * DOT_BASES[g.n][i]
            g.sizes[i] = math.max(1, math.floor(natural + (big - natural) * ratio + 0.5))
            g.dotsW = g.dotsW + g.sizes[i] + (i > 1 and sp or 0)
        end
    end
    local side = BV(key, "dotSide")
    g.totalW  = g.w + g.dotsW * (side == "BOTH" and 2 or 1)
    g.frameH  = math.max(g.n > 0 and g.sizes[g.n] or 0, g.h) + 4
    g.barOffX = (g.n > 0 and side ~= "RIGHT") and g.dotsW or 0
    g.barOffY = math.floor((g.frameH - g.h) / 2)   -- entier : la barre tombe sur la grille de pixels
    return g
end

-- Barre liee a une autre (disposition "mirror" = symetrie, "parent" = parentee ; jamais a elle-meme) : renvoie la barre
-- de reference (champ mirrorOf, commun aux deux modes) et le mode, sinon nil.
local function LinkSource(key)
    local cfg = Cfg(key)
    if (cfg.layout == "mirror" or cfg.layout == "parent") and cfg.mirrorOf ~= key and DEF_BY_KEY[cfg.mirrorOf] then
        return cfg.mirrorOf, cfg.layout
    end
end
local function IsLinked(key) return LinkSource(key) ~= nil end

-- Decalage de la barre dans son cadre : centre horizontal de la barre et bord bas de la barre, par rapport au point
-- d'ancrage du cadre (centre de son bord bas). Le cadre englobe aussi les points decoratifs : sa taille change avec eux.
local function BarOffset(g)
    return -g.totalW / 2 + g.barOffX + g.w / 2, g.barOffY
end

-- Position (x, y) d'une barre : centre horizontal et bord bas de la BARRE (pas de son cadre : les points decoratifs ne
-- la deplacent jamais), relatifs au centre de UIParent. La sienne ; en symetrie de sa barre de reference (axe vertical
-- au centre de l'ecran, bords bas alignes) ; ou parentee (position de la reference + relX / relY). Une chaine de liens
-- est suivie sur 5 niveaux au plus (boucle A <-> B sans fin sinon).
local function BarPos(key, depth)
    depth = depth or 0
    local src, mode = LinkSource(key)
    if src and depth < 5 then
        local sx, sy = BarPos(src, depth + 1)
        if mode == "parent" then
            local cfg = Cfg(key)
            return sx + (cfg.relX or 0), sy + (cfg.relY or 0)
        end
        return -sx, sy
    end
    local cfg, def = Cfg(key), DEF_BY_KEY[key]
    return cfg.x or def.defaults.x, cfg.y or def.defaults.y
end
UnitBars.BarPos = BarPos

-- Inverse de BarPos en symetrie : position a donner a la barre de reference pour que `key` soit en (x, y)
local function MirrorSourcePos(key, x, y)
    return -x, y
end

-- Positions enregistrees autrefois pour le CADRE (bas, centre) : converties une fois en positions de la barre
-- (drapeau barAnchorPos), sans deplacer quoi que ce soit a l'ecran.
local function EnsureBarAnchor()
    local db = ns.DB and ns.DB.unitBars
    if not db or db.barAnchorPos or not db.bars then return end
    db.barAnchorPos = true
    local off = {}
    for _, d in ipairs(BAR_DEFS) do off[d.key] = { BarOffset(Geometry(d.key)) } end
    for _, d in ipairs(BAR_DEFS) do
        local b, o = db.bars[d.key], off[d.key]
        if b then
            b.x = math.floor((b.x or d.defaults.x) + o[1] + 0.5)
            b.y = math.floor((b.y or d.defaults.y) + o[2] + 0.5)
            local so = off[b.mirrorOf]
            if so and (b.relX or b.relY) then
                b.relX = math.floor((b.relX or 0) + o[1] - so[1] + 0.5)
                b.relY = math.floor((b.relY or 0) + o[2] - so[2] + 0.5)
            end
        end
    end
end

-- Place la barre `key` en (x, y) en respectant sa disposition : libre = x / y ; parentee = decalage par rapport a sa
-- reference ; en symetrie = c'est la reference qui bouge (en miroir), recursivement.
local function SetBarPos(key, x, y, depth)
    depth = depth or 0
    local db = ns.DB and ns.DB.unitBars
    local bc = db and db.bars and db.bars[key]
    if not bc then return end
    local src, mode = LinkSource(key)
    if src and depth < 5 then
        if mode == "mirror" then
            local sx, sy = MirrorSourcePos(key, x, y)
            return SetBarPos(src, sx, sy, depth + 1)
        end
        local sx, sy = BarPos(src)
        bc.relX, bc.relY = math.floor(x - sx + 0.5), math.floor(y - sy + 0.5)
        return
    end
    bc.x, bc.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

-- Ancrage des textes : l'element accroche au point `anchor` de la barre se place a l'exterieur (au-dessus pour la
-- rangee du haut, en dessous pour celle du bas, a cote pour celle du milieu). `h` force son bord horizontal
-- (justification du nom : "LEFT", "" = centre, "RIGHT") : TOP + LEFT = le nom part du milieu de la barre vers la droite.
local FLIP = { TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT", [""] = "" }
local function OuterPoint(anchor, h)
    anchor = anchor or "CENTER"
    local v  = anchor:match("^TOP") or anchor:match("^BOTTOM") or ""
    local ah = anchor:match("LEFT$") or anchor:match("RIGHT$") or ""
    local p
    if v ~= "" then p = FLIP[v] .. (h or ah) else p = h or FLIP[ah] end
    return p ~= "" and p or "CENTER"
end

-- Creation d'une barre (appelée une seule fois par key)
-- Forward : PositionBarFrame est defini plus bas (avec les fonctions de refresh), mais OnDragStop
-- doit pouvoir le rappeler pour re-ancrer immediatement dans la convention canonique.
local PositionBarFrame

-- Elements visuels d'une barre : cadre securise en jeu, simple cadre pour l'apercu du GUI. Tailles, positions et
-- couleurs sont posees ensuite par LayoutBar.
local function NewVisual(frame)
    local lvl = frame:GetFrameLevel()

    -- Fond de la barre (sublevel 1 pour être au-dessus du border)
    frame.bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)

    -- StatusBar de remplissage HP (doit exister avant absorbTex qui s'ancre sur son fill)
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetFrameLevel(lvl + 1)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    frame.bar = sb

    -- Cadre de rognage : tout ce qui s'ajoute apres le fill HP (soins previsionnels, absorb) y est enferme, donc
    -- rien ne peut deborder de la barre de vie. Impossible de calculer la place restante en Lua : la vie courante
    -- est un secret number en combat, on ne peut ni la lire ni la soustraire -- le rognage est la seule voie fiable.
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetFrameLevel(lvl + 2)
    clip:SetPoint("TOPLEFT",     frame.bgTex, "TOPLEFT",     0, 0)
    clip:SetPoint("BOTTOMRIGHT", frame.bgTex, "BOTTOMRIGHT", 0, 0)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    frame.clipFrame = clip

    -- Soins previsionnels : segment ajoute au bord d'arrivee du fill HP, AVANT l'absorb. Meme principe que la barre
    -- d'absorb : la valeur vient du calculateur et peut etre un secret number, donc elle est passee telle quelle a
    -- SetValue, jamais lue cote Lua.
    pcall(function()
        local healBar = CreateFrame("StatusBar", nil, clip)
        healBar:SetFrameLevel(clip:GetFrameLevel() + 1)
        healBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        healBar:EnableMouse(false)  -- ne pas intercepter les clics (SecureUnitButtonTemplate parent)
        healBar:SetMinMaxValues(0, 1)
        healBar:SetValue(0)
        frame.healPredBar = healBar
    end)

    -- Barre d'absorb : StatusBar ancrée au bord d'arrivee du segment de soins (C-side, secret numbers OK)
    pcall(function()
        local absorbBar = CreateFrame("StatusBar", nil, clip)
        absorbBar:SetFrameLevel(clip:GetFrameLevel() + 2)
        absorbBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        absorbBar:EnableMouse(false)
        absorbBar:SetMinMaxValues(0, 1)
        absorbBar:SetValue(0)
        frame.absorbBar = absorbBar
    end)

    -- Filet de bordure (1px noir autour de la barre, sublevel 0 = derrière bgTex)
    local border = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    border:SetPoint("TOPLEFT",     frame.bgTex, "TOPLEFT",     -1,  1)
    border:SetPoint("BOTTOMRIGHT", frame.bgTex, "BOTTOMRIGHT",  1, -1)
    frame.border = border

    -- Points decoratifs : crees a la demande (LayoutDots), sur un calque au-dessus de la barre et de ses segments
    -- (soins, absorb) : la forme la plus proche peut recouvrir le bout de la barre, voulu pour le rendu
    frame.dots = {}
    local dotLayer = CreateFrame("Frame", nil, frame)
    dotLayer:SetAllPoints(frame)
    dotLayer:SetFrameLevel(lvl + 6)
    dotLayer:EnableMouse(false)
    frame.dotLayer = dotLayer

    -- Texte de vie, dans son cadre (fond sombre optionnel)
    local tbFrame = CreateFrame("Frame", nil, frame)
    tbFrame:SetFrameLevel(lvl + 2)
    local tbTex = tbFrame:CreateTexture(nil, "BACKGROUND")
    tbTex:SetAllPoints(tbFrame)
    frame.textBG    = tbFrame
    frame.textBGTex = tbTex
    local txt = tbFrame:CreateFontString(nil, "OVERLAY")
    frame.hpTextSlug = ns.CreateSlugRing(tbFrame, txt)
    -- Police posee sur le texte ET son anneau SLUG avant tout SetText (sinon "Font not set")
    ns.ApplyTextOutlineStyle(txt, frame.hpTextSlug, DEFAULT_FONT, 8, "OUTLINE")
    txt:SetAlpha(0.66)
    txt:SetJustifyH("CENTER")
    txt:SetTextColor(1, 1, 1, 1)
    txt:SetPoint("CENTER", tbFrame, "CENTER", 0, 1)
    txt:SetText("--")
    frame.hpText = txt

    -- Nom de l'unité, et son ombre (derriere lui, a sa taille)
    -- Ombre derriere la barre (sous le fond et le filet)
    frame.nameShadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.nameShadow:Hide()
    local nameTxt = frame:CreateFontString(nil, "OVERLAY")
    frame.nameTxtSlug = ns.CreateSlugRing(frame, nameTxt)
    ns.ApplyTextOutlineStyle(nameTxt, frame.nameTxtSlug, DEFAULT_FONT, 14, "OUTLINE")
    nameTxt:SetShadowColor(0, 0, 0, 0.7)
    nameTxt:SetTextColor(1, 1, 1, 1)
    nameTxt:SetText("")
    frame.nameTxt = nameTxt
    frame._nameEmpty = true
end

-- Opacite du nom (animations) ; en jeu, l'ombre de la barre la suit (cf. LayoutBar)
local function SetNameAlpha(frame, a)
    frame.nameTxt:SetAlpha(a)
    if frame._shadowBase then frame.nameShadow:SetAlpha(frame._shadowBase * a) end
end

-- Ombre de la barre, en jeu : seulement quand le nom s'affiche (au survol pour le joueur)
local function RefreshShadowVis(frame)
    if frame._shadowBase then frame.nameShadow:SetShown(not frame._nameEmpty) end
end

-- Soins previsionnels au bord d'arrivee du fill HP ; absorb a leur suite, ou au depart de la barre en miroir
-- (absorbReversed). Rappele a chaque passage d'UpdateAbsorb : l'option peut changer en direct.
local function AnchorAbsorb(frame)
    local fd, abs = frame._fill or FILL_DIRS.LTR, frame.absorbBar
    if not abs then return end
    abs:ClearAllPoints()
    if (ns.GetCfg("unitBars") or {}).absorbReversed then
        abs:SetPoint(fd.from, frame.bgTex, fd.from, 0, 0)
    else
        -- Derriere le segment de soins : sa texture est large de 0 quand aucun soin n'est en vol, donc l'absorb
        -- reste colle au fill HP dans ce cas.
        abs:SetPoint(fd.from, (frame.healPredBar or frame.bar):GetStatusBarTexture(), fd.to, 0, 0)
    end
end

local function AnchorPrediction(frame)
    local fd = frame._fill or FILL_DIRS.LTR
    if frame.healPredBar then
        frame.healPredBar:ClearAllPoints()
        frame.healPredBar:SetPoint(fd.from, frame.bar:GetStatusBarTexture(), fd.to, 0, 0)
    end
    AnchorAbsorb(frame)
end

-- Points decoratifs : un groupe par cote choisi (LEFT, RIGHT ou BOTH), du plus eloigne de la barre (rang 1) au plus
-- proche (rang n). dotGap positif les eloigne de la barre. Forme combinee : la plus proche differe des suivantes.
-- frame.dots[i] : textures dans l'ordre (groupe de gauche puis de droite) ; frame._dotRank[i] : rang dans son groupe.
local function LayoutDots(frame, key, g)
    local name  = BV(key, "dotShape")
    local combo = DOT_COMBOS[name]
    local near  = DOT_SHAPES[combo and combo[1] or name] or DOT_SHAPES.circle
    local far   = DOT_SHAPES[combo and combo[2] or name] or near
    local side  = BV(key, "dotSide")
    local gap, sp = BV(key, "dotGap"), BV(key, "dotSpacing")
    local yc = g.barOffY + g.h / 2   -- centre vertical de la barre
    local groups = {}
    if g.n > 0 and side ~= "RIGHT" then groups[#groups + 1] = true end
    if g.n > 0 and side ~= "LEFT" then groups[#groups + 1] = false end
    frame._dotN, frame._dotYCenter, frame._dotSizes, frame._dotRank = g.n, yc, {}, {}
    local idx = 0
    for _, left in ipairs(groups) do
        local x = 0
        for i = 1, g.n do
            idx = idx + 1
            local d = frame.dots[idx]
            if not d then
                d = (frame.dotLayer or frame):CreateTexture(nil, "OVERLAY")
                -- Pas de calage sur la grille de pixels : centre exact sur celui de la barre (sinon decale d'1 px)
                if d.SetSnapToPixelGrid then d:SetSnapToPixelGrid(false); d:SetTexelSnappingBias(0) end
                frame.dots[idx] = d
            end
            local shape = (i == g.n) and near or far
            local rot = shape.rot or 0
            if shape.outward then rot = left and math.pi / 2 or -math.pi / 2 end
            local sz = g.sizes[i]
            local dx
            if left then
                dx = x + sz / 2 - gap
                x = x + sz + sp
            else
                local off = 0
                for j = i + 1, g.n do off = off + g.sizes[j] + sp end
                dx = g.barOffX + g.w + gap + off + sz / 2
            end
            local shown = sz * (shape.scale or 1)
            d:SetTexture(shape.tex)
            d:SetRotation(rot)
            d:SetSize(shown, shown)
            d:ClearAllPoints()
            d:SetPoint("CENTER", frame, "BOTTOMLEFT", dx, yc)
            d:Show()
            frame._dotSizes[idx], frame._dotRank[idx] = shown, i
            frame["dot" .. idx .. "_dx"] = dx
        end
    end
    frame._dotCount = idx
    for j = idx + 1, #frame.dots do frame.dots[j]:Hide() end
end

-- Met à jour la couleur de la barre (target = classe, autres = config/Colors)
local function UpdateBarColor(frame)
    local def = frame._def
    local key = def.key
    local fc  = Cfg(key).fillColor or def.defaults.fillColor
    local bg  = GetBgColor()
    local CLR = ns.Modules.Colors

    -- Pour target/targettarget : couleur de classe ; player/pet : Colors si dispo
    if key == "target" or key == "targettarget" then
        fc = GetClassFillColor(def.unit, fc)
    elseif key == "player" and CLR then
        fc = CLR.Get("playerhealthbar")
    elseif key == "pet" and CLR then
        fc = CLR.Get("pethealthbar")
    end

    -- Couleur des points : peut différer du fill pour player/pet
    local dc = fc
    if key == "player" and CLR then
        dc = CLR.Get("playerdots")
    elseif key == "pet" and CLR then
        dc = CLR.Get("petdots")
    end

    -- Hors couleurs thematiques : couleur des barres unique (remplissage, points, textes) ; le "noir" suit l'arriere plan
    if not IsThemedColors() then
        local ubdb = ns.GetCfg("unitBars")
        local bc = ubdb and ubdb.barColor or fc
        fc, dc = bc, bc
    end
    local dark = GetDarkColor()

    if IsReversed() then
        -- Mode classique : fond sombre, fill coloré
        PaintBg(frame.bgTex, bg, key)
        frame.bar:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
    else
        -- Mode inversé (défaut) : fond coloré, fill noir
        PaintBg(frame.bgTex, fc, key)
        frame.bar:SetStatusBarColor(dark[1], dark[2], dark[3], dark[4] or 1)
    end

    -- Points : couleur de la barre, le plus proche d'elle en noir (sauf point unique)
    local n = frame._dotN or 0
    for i, d in ipairs(frame.dots) do
        local c = (n > 1 and frame._dotRank and frame._dotRank[i] == n) and dark or dc
        -- Alpha de vertex = alpha de la texture : l'estompage de l'apercu (_dotDim) passe donc ici
        d:SetVertexColor(c[1], c[2], c[3], frame._dotDim or 1)
    end
    if frame.border then frame.border:SetColorTexture(dark[1], dark[2], dark[3], dark[4] or 1) end
    if frame.textBGTex then
        local hc = BV(key, "hpBgColor") or bg
        frame.textBGTex:SetVertexColor(hc[1], hc[2], hc[3], hc[4] or 1)
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

-- Mise en page complete d'une barre (tailles, remplissage, points, textes, couleurs), sans toucher a sa position a
-- l'ecran. `preview` : apercu du GUI, ou les elements desactives restent visibles, estompes, pour rester survolables.
local PREVIEW_DIM = 0.2
local function LayoutBar(frame, preview)
    local key = frame._def.key
    local g = Geometry(key, preview)
    frame:SetSize(g.totalW, g.frameH)
    frame.bgTex:SetSize(g.w, g.h)
    frame.bgTex:ClearAllPoints()
    frame.bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", g.barOffX, g.barOffY)
    frame._barOffX, frame._barOffY, frame._barW = g.barOffX, g.barOffY, g.w
    frame._posDX, frame._posDY = BarOffset(g)

    -- Remplissage : textures et sens
    local fd = FILL_DIRS[BV(key, "fillDir")] or FILL_DIRS.LTR
    frame._fill = fd
    for _, sb in ipairs({ frame.bar, frame.healPredBar or false, frame.absorbBar or false }) do
        if sb then
            sb:SetSize(g.w, g.h)
            sb:SetOrientation(fd.orient)
            sb:SetReverseFill(fd.rev)
        end
    end
    frame.bar:SetStatusBarTexture(BarTex(key))
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", frame.bgTex)
    AnchorPrediction(frame)

    -- Points decoratifs
    LayoutDots(frame, key, g)
    frame._dotDim = preview and not BV(key, "showDots") and PREVIEW_DIM or nil   -- applique par UpdateBarColor

    -- Texte de vie : cadre ancre a la barre, texte centre dedans
    local hpOn, hpAnchor = BV(key, "hpShow") and true or false, BV(key, "hpAnchor")
    local tb = frame.textBG
    tb:SetSize(BV(key, "hpBoxW"), BV(key, "hpBoxH"))
    tb:ClearAllPoints()
    tb:SetPoint(OuterPoint(hpAnchor), frame.bgTex, hpAnchor, BV(key, "hpOffX"), BV(key, "hpOffY"))
    frame.textBGTex:SetTexture(HP_BOX_TEX[BV(key, "hpBgShape")] or HP_BOX_TEX.rect)
    frame.textBGTex:SetShown(BV(key, "hpBg") and true or false)
    ns.ApplyTextOutlineStyle(frame.hpText, frame.hpTextSlug, BV(key, "hpFont") or ns.Media.font, BV(key, "hpSize"), BV(key, "hpOutline"))
    tb:SetShown(hpOn or preview)
    tb:SetAlpha((hpOn or not preview) and 1 or PREVIEW_DIM)

    -- Nom : point d'ancrage sur la barre + justification (cf. OuterPoint)
    local nAnchor, just = BV(key, "nameAnchor"), BV(key, "nameJustify") or "LEFT"
    local nSize = BV(key, "nameSize")
    ns.ApplyTextOutlineStyle(frame.nameTxt, frame.nameTxtSlug, BV(key, "nameFont") or DEFAULT_FONT, nSize, BV(key, "nameOutline"))
    frame.nameTxt:SetJustifyH(just)
    -- Largeur de boite du nom : au-dela, le nom est coupe ("..."). 0 = libre
    local boxW = BV(key, "nameBoxW") or 0
    frame.nameTxt:SetWordWrap(false)
    frame.nameTxt:SetWidth(boxW > 0 and boxW or 0)
    for _, fs in ipairs(frame.nameTxtSlug or {}) do fs:SetWordWrap(false) end
    frame._nameAnchorS = OuterPoint(nAnchor, just == "CENTER" and "" or just)
    frame._nameAnchorA = nAnchor
    frame._nameOffX, frame._nameOffY = BV(key, "nameOffX"), BV(key, "nameOffY")
    frame.nameTxt:ClearAllPoints()
    frame.nameTxt:SetPoint(frame._nameAnchorS, frame.bgTex, frame._nameAnchorA, frame._nameOffX, frame._nameOffY)

    -- Ombre : derriere la barre, a sa largeur ; hauteur dans les proportions de l'atlas, donc elle deborde de la barre :
    -- vers le haut, ou vers le bas (tournee de 180 degres) si "Inversee". Ne se montre qu'avec le nom.
    local sh = frame.nameShadow
    local shadowOn = BV(key, "nameShadow") and true or false
    if shadowOn or preview then
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(NAME_SHADOW_ATLAS)
        local ratio = 0.25
        if info then
            sh:SetAtlas(NAME_SHADOW_ATLAS)
            sh:SetVertexColor(1, 1, 1, 1)
            if info.width and info.width > 0 then ratio = info.height / info.width end
        else
            sh:SetColorTexture(0, 0, 0, 1)
        end
        -- Le bord dense de l'atlas (bas de la texture non tournee) est le depart de l'ombre : pose sur le bord de la
        -- barre (haut par defaut, bas si "Inversee"), l'ombre deborde vers l'exterieur
        local down = BV(key, "nameShadowFlip") and true or false
        sh:SetRotation(down and math.pi or 0)
        sh:ClearAllPoints()
        local from, to = "BOTTOM", "TOP"
        if down then from, to = "TOP", "BOTTOM" end
        -- Centree ; largeur en % de la barre, hauteur en % de la hauteur proportionnelle (atlas non deforme a 100 / 100)
        local sw = g.w * (BV(key, "nameShadowW") or 100) / 100
        sh:SetPoint(from, frame.bgTex, to)
        sh:SetSize(math.max(1, sw), math.max(1, sw * ratio * (BV(key, "nameShadowH") or 100) / 100))
        local base = BV(key, "nameShadowAlpha") or 0.8
        if preview then
            -- Apercu : estompee si elle, ou le nom qui la porte, est desactive
            local nameOn = BV(key, "showName") or (key == "player" and BV(key, "nameAlways"))
            frame._shadowBase = nil
            sh:SetAlpha(base * ((shadowOn and nameOn) and 1 or PREVIEW_DIM))
            sh:Show()
        else
            frame._shadowBase = base
            sh:SetAlpha(base * frame.nameTxt:GetAlpha())
            RefreshShadowVis(frame)
        end
    else
        frame._shadowBase = nil
        sh:Hide()
    end

    UpdateBarColor(frame)
end

-- Glisser-deposer : la position est enregistree a chaque image (StoreDragPos), et les autres barres sont replacees en
-- direct -- celles en symetrie ou parentees suivent la barre tenue, comme si on les deplacait ensemble.
-- Sauvegarde dans le repere exact de PositionBarFrame (centre horizontal, bord bas, relatifs au centre de UIParent),
-- sans lire frame:GetPoint(1) : StartMoving re-ancre la frame dans la convention que WoW juge bonne (souvent un coin),
-- et des offsets lus dans ce repere teleportaient la barre au refresh suivant.
local dragFrame
local function StoreDragPos(frame)
    local cx, bottom = frame:GetCenter(), frame:GetBottom()
    local ucx, ucy   = UIParent:GetCenter()
    if cx and bottom and ucx and ucy then
        SetBarPos(frame._def.key, cx - ucx + (frame._posDX or 0), bottom - ucy + (frame._posDY or 0))
    end
end
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()
dragDriver:SetScript("OnUpdate", function()
    if not dragFrame or InCombatLockdown() then return end
    StoreDragPos(dragFrame)
    for _, f in pairs(bars) do
        if f ~= dragFrame then PositionBarFrame(f) end
    end
end)

local function CreateUnitBar(def)
    -- Frame racine (draggable, taille totale incluant les points)
    local frame = CreateFrame("Button", "AishCoreUnitBar_" .. def.key, UIParent, "SecureUnitButtonTemplate")
    frame._def = def
    frame.unit = def.unit
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("unit", def.unit)
    frame:SetAttribute("*type1", "target")      -- clic gauche = cibler l'unité
    frame:SetAttribute("*type2", "togglemenu")  -- clic droit  = menu contextuel
    frame:SetClampedToScreen(true)

    -- Pad de clic (cf. ApplyHitPad) : memes attributs que la barre, pose derriere elle pour
    -- qu'elle garde la priorite sur sa propre surface. Sans texture, donc invisible ; il suit
    -- l'alpha de la barre comme n'importe quel enfant.
    local pad = CreateFrame("Button", "$parentHitPad", frame, "SecureUnitButtonTemplate")
    pad:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    pad:RegisterForClicks("AnyUp")
    pad:RegisterForDrag("LeftButton")
    pad:SetAttribute("unit", def.unit)
    pad:SetAttribute("*type1", "target")
    pad:SetAttribute("*type2", "togglemenu")
    -- Le deplacement depuis la couronne doit saisir la barre, sinon on croit l'avoir
    -- attrapee et rien ne bouge.
    pad:SetScript("OnDragStart", function()
        local h = frame:GetScript("OnDragStart"); if h then h(frame) end
    end)
    pad:SetScript("OnDragStop", function()
        local h = frame:GetScript("OnDragStop"); if h then h(frame) end
    end)
    pad:Hide()
    frame._hitPad = pad
    ApplyHitPad(frame, ConfiguredHoverTol())
    -- Show() une seule fois à la création ; visibilité gérée ensuite via SetAlpha() (jamais protégé en combat)
    frame:Show()
    frame:SetAlpha(0)
    frame:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local panel = _G["AishCoreSettingsPanel"]
        if not panel or not panel:IsShown() then return end
        if ns.GetCfg("unitBars") and ns.GetCfg("unitBars").locked then return end
        self._dragging = true
        self:StartMoving()
        dragFrame = self
        dragDriver:Show()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:StopMovingOrSizing()
        StoreDragPos(self)
        dragFrame = nil
        dragDriver:Hide()
        -- Re-ancrage immediat de toutes les barres (celle-ci comprise) dans la convention canonique
        for _, f in pairs(bars) do PositionBarFrame(f) end
        UnitBars.NotifyPlayerBarMoved()
        -- Report dans les champs X/Y du panneau (UI/UnitBarsPage.lua)
        if ns.UnitBarsPagePosChanged then pcall(ns.UnitBarsPagePosChanged) end
    end)

    NewVisual(frame)

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
            -- Soins previsionnels : borner au maximum de vie, sinon un gros soin deborde
            -- largement de la barre.
            if calc.SetIncomingHealClampMode and Enum and Enum.UnitIncomingHealClampMode then
                calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)
            end
            frame.hpCalc = calc
        end)
    end

    -- Glow au survol : BackdropTemplate + GlowTex.tga (même technique qu'ElvUI)
    local GLOW_TEX  = "Interface\\AddOns\\AishCore\\Media\\UI\\GlowTex.tga"
    local GLOW_SIZE = 5
    local glowFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glowFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
    glowFrame:SetPoint("TOPLEFT",     frame.bgTex, "TOPLEFT",     -GLOW_SIZE,  GLOW_SIZE)
    glowFrame:SetPoint("BOTTOMRIGHT", frame.bgTex, "BOTTOMRIGHT",  GLOW_SIZE, -GLOW_SIZE)
    glowFrame:SetBackdrop({ edgeFile = GLOW_TEX, edgeSize = GLOW_SIZE })
    glowFrame:SetBackdropColor(0, 0, 0, 0)
    glowFrame:SetAlpha(0)
    frame.glowFrame = glowFrame

    -- Survol : fade in/out de la lueur (HookScript pour ne pas écraser le template)
    frame:HookScript("OnEnter", function(self)
        UIFrameFadeIn(self.glowFrame, 0.15, self.glowFrame:GetAlpha(), 1)
    end)
    frame:HookScript("OnLeave", function(self)
        UIFrameFadeOut(self.glowFrame, 0.2, self.glowFrame:GetAlpha(), 0)
    end)

    if def.key == "player" then EnsurePlayerNameOffset() end
    -- Forever : icone de satisfaction du familier (chasseur), a gauche du nom (cf. UpdatePetHappiness)
    if ns.IsForever and def.key == "pet" then
        local ic = frame:CreateTexture(nil, "OVERLAY")
        ic:SetPoint("RIGHT", frame.nameTxt, "LEFT", -3, 2)
        ic:Hide()
        frame.happyIcon = ic
    end

    LayoutBar(frame)
    PositionBarFrame(frame, 0)
    return frame
end

-- Helper : mise à jour du texte HP selon le mode de la barre (pct ou value)
local function SetHPText(hpTextWidget, unit, barKey)
    local mode = BV(barKey, "hpMode") or "pct"
    -- "Valeur au survol" : la barre sous le curseur passe en valeur brute, quel que soit le mode.
    if BV(barKey, "hpHoverValue") and ubHovered[barKey] then mode = "value" end
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

-- Mise à jour d'une barre (health valeur)
local function UpdateBarHealth(frame)
    local unit   = frame.unit
    local barCfg = Cfg(frame._def.key)
    if barCfg.enabled == false then return end
    if not UnitExists(unit) then return end

    -- Apercu (GUI ouvert) : barre du joueur figee a 75 %, comme les barres sans unite (cible...)
    if ubPreviewMode and frame._def.key == "player" then
        frame.bar:SetMinMaxValues(0, 100)
        ns.SmoothBarValue(frame.bar, 75)
        if frame.hpText then
            frame.hpText:SetText(BV("player", "hpMode") == "value" and "75K" or "75")
        end
        return
    end

    -- Calculateur (WithAbsorbs) en mode normal, C-side pur en mode miroir (absorbReversed) pour éviter un gap
    local calcUpdated = false
    local absorbReversed = (ns.GetCfg("unitBars") or {}).absorbReversed
    if frame.hpCalc and not absorbReversed then
        pcall(function()
            UnitGetDetailedHealPrediction(unit, nil, frame.hpCalc)
            calcUpdated = true
            frame.bar:SetMinMaxValues(0, frame.hpCalc:GetMaximumHealth())
            ns.SmoothBarValue(frame.bar, frame.hpCalc:GetCurrentHealth())
        end)
    end
    if not calcUpdated then
        pcall(function()
            frame.bar:SetMinMaxValues(0, UnitHealthMax(unit))
            ns.SmoothBarValue(frame.bar, UnitHealth(unit))
        end)
    end
    -- Absorb via UpdateAbsorb (appelé séparément par le ticker pour toutes les barres)

    if frame.hpText then
        SetHPText(frame.hpText, unit, frame._def.key)
    end
end

-- Mise à jour absorb (commune à toutes les barres, y compris target).
-- Volontairement SANS ns.SmoothSetValue : l'absorb est ancre au bord du fill HP et
-- se repositionne a chaque passage -- une valeur interpolee le ferait flotter a cote.
local function UpdateAbsorb(frame)
    if not frame.hpCalc or not frame.absorbBar then return end
    local cfg2 = ns.GetCfg("unitBars") or {}
    if cfg2.showAbsorb == false then frame.absorbBar:SetValue(0); return end
    -- UnitGetTotalAbsorbs retourne un secret number, passé directement à SetValue (C-side)
    local ac = cfg2.absorbColor or { 0, 1, 0.918, 1 }
    pcall(function()
        local fn = UnitAbsorb or UnitGetTotalAbsorbs
        local absorb = 0
        if fn then
            local ok, v = pcall(fn, frame._def.unit)
            if ok then absorb = v end
        end
        AnchorAbsorb(frame)
        if cfg2.absorbReversed then
            -- Miroir : se superpose au fill HP depuis le depart de la barre
            frame.absorbBar:SetMinMaxValues(0, UnitHealthMax(frame._def.unit) or 1)  -- valeur régulière
        else
            frame.absorbBar:SetMinMaxValues(0, frame.hpCalc:GetMaximumHealth())
        end
        frame.absorbBar:SetValue(absorb)
        frame.absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], ac[4] or 1)
    end)
end

-- Soins previsionnels. Comme UpdateAbsorb : pas de lissage (le segment est ancre au bord
-- du fill HP et se repositionne a chaque passage), et aucune valeur n'est lue cote
-- Lua -- GetIncomingHeals peut renvoyer un secret number en combat.
local function UpdateHealPrediction(frame)
    if not frame.hpCalc or not frame.healPredBar then return end
    local cfg  = ns.GetCfg("unitBars") or {}
    if cfg.showHealPrediction == false then frame.healPredBar:SetValue(0); return end
    local hc = cfg.healPredColor or { 0.15, 0.85, 0.35, 1 }
    pcall(function()
        -- "player" en 2e argument : c'est ce qui fait ventiler les soins par lanceur. On ne
        -- garde que le total, mais l'appel doit etre fait pour que GetIncomingHeals reponde.
        UnitGetDetailedHealPrediction(frame._def.unit, "player", frame.hpCalc)
        local allHeal = frame.hpCalc:GetIncomingHeals()
        frame.healPredBar:SetMinMaxValues(0, frame.hpCalc:GetMaximumHealth())
        frame.healPredBar:SetValue(allHeal)
        frame.healPredBar:SetStatusBarColor(hc[1], hc[2], hc[3], hc[4] or 1)
    end)
end

-- Forever : satisfaction du familier du chasseur (C_PetInfo.GetPetHappiness : 1 = mecontent, 2 = content, 3 = heureux).
-- Une seule texture (la patte de familier capturable) teintee selon l'etat ; repli sur les visages Blizzard si l'atlas manque.
local HAPPINESS_ICON  = "WildBattlePetCapturable"
local HAPPINESS_COLOR = { [1] = { 0.90, 0.20, 0.20 }, [2] = { 1.00, 0.85, 0.10 }, [3] = { 0.20, 0.90, 0.20 } }
local HAPPINESS_FACE  = { [1] = "UI-PetMad", [2] = "UI-PetNeutral", [3] = "UI-PetHappiness" }
local function UpdatePetHappiness(frame)
    local ic = frame.happyIcon
    if not ic then return end
    local level
    if UnitExists("pet") then
        -- seuls les familiers de chasseur ont une satisfaction (HasPetUI : 2e retour = familier de chasseur)
        if HasPetUI and C_PetInfo and C_PetInfo.GetPetHappiness then
            local _, isHunterPet = HasPetUI()
            if isHunterPet then level = C_PetInfo.GetPetHappiness() end
        end
    elseif ubPreviewMode then
        level = 3
    end
    local color = level and HAPPINESS_COLOR[level]
    if not color then ic:Hide(); return end
    local size = (BV("pet", "nameSize") or 14) + 4
    ic:SetSize(size, size)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(HAPPINESS_ICON) then
        ic:SetAtlas(HAPPINESS_ICON)
        ic:SetVertexColor(color[1], color[2], color[3], 1)
    else
        ic:SetAtlas(HAPPINESS_FACE[level])
        ic:SetVertexColor(1, 1, 1, 1)
    end
    ic:Show()
end

-- Niveau devant le nom, comme la Top Target Bar ("7 • Nom", niveau colore selon la difficulte du mob)
local function SetNameWithLevel(frame, unit, rawName, preview)
    local TTB = ns.Modules and ns.Modules.TopTargetBar
    if not (TTB and TTB.GetLevelColor and TTB.GetLevelPrefix) then return false end
    local ok = pcall(function()
        local lc, pfx
        if preview then
            lc, pfx = { 1.000, 0.000, 0.133 }, "90 \226\128\162 "
        else
            lc, pfx = TTB.GetLevelColor(unit), TTB.GetLevelPrefix(unit)
        end
        -- string.format %s : seul moyen de composer avec une chaine secrete (concatener echoue)
        frame.nameTxt:SetText(string.format("|cff%02x%02x%02x%s|r%s",
            math.floor(lc[1] * 255), math.floor(lc[2] * 255), math.floor(lc[3] * 255), pfx, rawName or ""))
        -- l'anneau SLUG recopie le texte : version sans couleur, sinon il peindrait le niveau a la place du contour noir
        ns.SetSlugRingText(frame.nameTxtSlug, string.format("%s%s", pfx, rawName or ""))
    end)
    return ok
end

-- Nom affiche quand l'unite n'existe pas (apercu)
local PREVIEW_NAMES = {
    target       = "UNITBARS_PREVIEW_TARGET",
    targettarget = "UNITBARS_PREVIEW_TARGETTARGET",
    focus        = "UNITBARS_PREVIEW_FOCUS",
    pet          = "UNITBARS_PREVIEW_PET",
}

-- Mise à jour du nom d'unité
local function UpdateBarName(frame)
    if not frame.nameTxt then return end
    UpdatePetHappiness(frame)
    local unit, key = frame.unit, frame._def.key
    local empty = true
    if key == "player" then
        -- Barre du joueur : nom au survol, hors combat (ticker plus bas), ou en permanence (nameAlways)
        local rawName
        if (playerNameShown or playerNameFadingOut or BV("player", "nameAlways")) and UnitExists(unit) then
            -- Forever : le nom de famille est porte par la partie "royaume" du nom complet (Prenom-Famille)
            local nm, fam = UnitFullName(unit)
            rawName = nm or UnitName(unit)
            if ns.IsForever and rawName and fam and fam ~= "" then rawName = rawName .. " " .. fam end
        end
        if not (rawName and BV("player", "showLevel") and SetNameWithLevel(frame, unit, rawName)) then
            frame.nameTxt:SetText(rawName or "")
        end
        empty = not rawName
    elseif not BV(key, "showName") then
        frame.nameTxt:SetText("")
    else
        local withLevel = BV(key, "showLevel")
        if UnitExists(unit) then
            empty = false
            -- parentheses : UnitName renvoie aussi le "royaume" (nom de famille sur Forever), qui serait pris pour
            -- l'argument `preview`
            if not (withLevel and SetNameWithLevel(frame, unit, (UnitName(unit)))) then
                -- Détainter UnitName (secret string en instance/raid) via concaténation avant SetText
                local rawName = UnitName(unit)
                frame.nameTxt:SetText((rawName and ("" .. rawName)) or "")
            end
        elseif ubPreviewMode and PREVIEW_NAMES[key] then
            -- Preview : nom spécifique au module quand l'unité n'existe pas
            empty = false
            local nm = L[PREVIEW_NAMES[key]]
            if not (withLevel and SetNameWithLevel(frame, unit, nm, true)) then frame.nameTxt:SetText(nm) end
        else
            frame.nameTxt:SetText("")
        end
    end
    frame._nameEmpty = empty
    RefreshShadowVis(frame)
end

-- Repositionne frame selon sa position (BarPos), avec decalage horizontal optionnel (extraX, pour l'anim slide-in/out)
function PositionBarFrame(frame, extraX)
    local key = frame._def.key
    local x, y = BarPos(key)
    -- Position de la barre -> point d'ancrage du cadre (decalage pose par LayoutBar)
    x = x + (extraX or 0) - (frame._posDX or 0)
    y = y - (frame._posDY or 0)
    frame:ClearAllPoints()
    -- Toutes les barres sur UIParent : le familier, autrefois ancre sur la barre du joueur, en suivait le glissement
    -- d'apparition et sautait avec elle. Une barre parentee a une autre suit sa position, pas ses animations.
    frame:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
end

-- Application des settings sur un bar déjà créé (ApplySettings)
local function ApplyBarSettings(frame)
    -- SetSize / ClearAllPoints / SetPoint sont bloques en combat lockdown
    if InCombatLockdown() then
        pendingSettingsApply = true
        return
    end

    local def = frame._def
    local db2 = ns.GetCfg("unitBars")

    -- Activation / desactivation (global OU par barre)
    if (db2 and db2.enabled == false) or Cfg(def.key).enabled == false then
        ubLastVisState[def.key] = nil
        ApplyHitPad(frame, 0)   -- coupe aussi la souris
        UnitBars.UpdateAllVisibility()
        return
    end

    LayoutBar(frame)

    -- Tolerance de survol : le pad de clic deborde la barre de `tol` px sur les quatre cotes,
    -- sans toucher a sa geometrie visible. Nos barres font quelques pixels de haut : sans ca
    -- elles sont penibles a viser.
    ApplyHitPad(frame, ConfiguredHoverTol())

    -- Position frame (ancre bas)
    PositionBarFrame(frame, 0)

    -- Réévaluer la visibilité après changement de settings
    ubLastVisState[def.key] = nil
    UnitBars.UpdateAllVisibility()
    UpdateBarHealth(frame)
    UpdateBarName(frame)
end

--- Apercu du GUI : simple cadre portant les memes elements qu'une barre en jeu (cf. UnitBars.StylePreview).
function UnitBars.CreatePreview(parent)
    local f = CreateFrame("Frame", nil, parent)
    NewVisual(f)
    return f
end

--- Rendu de la barre `key` dans un apercu, avec des valeurs fictives (vie a 70 %, soins et bouclier s'ils sont
--- actives). Les elements desactives restent visibles, estompes (PREVIEW_DIM).
function UnitBars.StylePreview(f, key)
    local def = DEF_BY_KEY[key]
    if not def then return end
    f._def, f.unit = def, def.unit
    LayoutBar(f, true)
    local db = ns.GetCfg("unitBars") or {}
    f.bar:SetMinMaxValues(0, 100)
    f.bar:SetValue(70)
    if f.healPredBar then
        local c = db.healPredColor or { 0.15, 0.85, 0.35, 1 }
        f.healPredBar:SetMinMaxValues(0, 100)
        f.healPredBar:SetValue(db.showHealPrediction ~= false and 12 or 0)
        f.healPredBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
    if f.absorbBar then
        local c = db.absorbColor or { 0, 1, 0.918, 1 }
        f.absorbBar:SetMinMaxValues(0, 100)
        f.absorbBar:SetValue(db.showAbsorb ~= false and 10 or 0)
        f.absorbBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    end
    f.hpText:SetText(BV(key, "hpMode") == "value" and "70K" or "70")
    local name = (key == "player") and UnitName("player") or L[PREVIEW_NAMES[key]]
    -- Joueur : son vrai niveau (l'unite existe toujours) ; autres barres : niveau fictif
    if not (BV(key, "showLevel") and SetNameWithLevel(f, def.unit, name, key ~= "player")) then
        f.nameTxt:SetText(name or "")
    end
    f._nameEmpty = false
    local nameOn = BV(key, "showName") or (key == "player" and BV(key, "nameAlways"))
    SetNameAlpha(f, nameOn and 1 or PREVIEW_DIM)
end

UnitBars.IsLinked = IsLinked


-- Animation de visibilité (fade + slide in/out) — remplace les StateDrivers
-- Sens du glissement par barre : +1 = arrive en venant de la droite, -1 = de la gauche (croisement voulu avec joueur/pet)
local SLIDE_DIR = {
    player       = 1,
    pet          = 1,
    target       = -1,
    focus        = -1,
    targettarget = -1,
}
local SLIDE_DISTANCE  = 55    -- px de glissement pour la barre elle-meme
local FADE_DURATION   = 0.75  -- s (entree)
local DOT_STAGGER     = 0.13  -- s de decalage entree entre chaque etape (gros -> moyen -> petit -> nom)
local FADE_DURATION_OUT = 0.45  -- s (sortie -- plus rapide que l'entree)
local DOT_STAGGER_OUT   = 0.08  -- s de decalage sortie entre chaque etape
local DOT_SLIDE_EXTRA = 18    -- px de glissement supplementaire des dots (meme sens que la barre)
local DOT_SCALE_START = 0.35  -- taille de depart des dots (ratio de la taille finale)
local BAR_SCALE_START = 0.15  -- largeur de depart de la barre (ratio de sa largeur finale)
local NAME_SLIDE_EXTRA = 18   -- px de glissement supplementaire du nom (meme sens que la barre)

-- Amorti ease-out QUINT (ease-out expo testé mais jugé trop agressif)
local function EaseOut(p)
    if p >= 1 then return 1 end
    if p <= 0 then return 0 end
    return 1 - (1 - p)^5
end

-- Delais d'entree (cascade barre + point le plus proche -> ... -> point le plus eloigne -> nom), en multiples de
-- DOT_STAGGER ; sortie : LIFO exact (nom en premier, barre + point le plus proche en dernier). Les points s'etalent sur
-- 2 pas quel que soit leur nombre (pour 3 : entree 2 / 1 / 0, sortie 1 / 2 / 3).
local ENTER_DELAY_NAME = 3
local LEAVE_DELAY_NAME = 0
local LEAVE_DELAY_BAR = 3
local function DotEnterSteps(i, n) return n > 1 and (n - i) * 2 / (n - 1) or 0 end
local function DotLeaveSteps(i, n) return n > 1 and 1 + (i - 1) * 2 / (n - 1) or LEAVE_DELAY_BAR end
-- Duree totale d'un cycle (dernier element demarre a 3*stagger + sa propre fade_duration)
local TOTAL_STAGGER_STEPS = 3
local TOTAL_DURATION     = FADE_DURATION + TOTAL_STAGGER_STEPS * DOT_STAGGER
local TOTAL_DURATION_OUT = FADE_DURATION_OUT + TOTAL_STAGGER_STEPS * DOT_STAGGER_OUT

-- Scale horizontal de la barre : agit sur frame.bgTex/frame.bar uniquement (jamais protégés, contrairement à frame)
-- Le cote d'ancrage suit le sens du glissement (dir) pour que grandissement et slide aillent dans le même sens
local function ApplyBarWidthScale(frame, ratio, dir)
    local fullW = frame._barW
    if not fullW then return end
    local w = fullW * ratio
    if frame.bgTex then
        if (dir or 0) > 0 then
            local offX = (frame._barOffX or 0) + (fullW - w)
            frame.bgTex:ClearAllPoints()
            frame.bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", offX, frame._barOffY or 0)
        end
        frame.bgTex:SetWidth(w)
    end
    if frame.bar then frame.bar:SetWidth(w) end
end

-- Remet un dot a son etat de repos (taille finale, decalage nul), utilise en fin/debut de cycle d'anim
local function ResetDotToRest(frame, i, dotSizes)
    local d = frame.dots[i]
    if not d then return end
    local dx = frame["dot" .. i .. "_dx"]
    if dx and frame._dotYCenter then
        d:SetPoint("CENTER", frame, "BOTTOMLEFT", dx, frame._dotYCenter)
    end
    local sz = dotSizes[i]
    d:SetSize(sz, sz)
    d:SetAlpha(1)
end

-- Meme principe pour le nom (fade + glissement, pas de scale : FontString n'a pas de SetScale independant)
local function ResetNameToRest(frame)
    local n = frame.nameTxt
    if not n or not frame._nameAnchorS then return end
    n:ClearAllPoints()
    n:SetPoint(frame._nameAnchorS, frame.bgTex, frame._nameAnchorA, frame._nameOffX, frame._nameOffY)
    SetNameAlpha(frame, 1)
end

-- Anim mise en file (jamais interrompue) : la derniere direction demandee rejoue en fin de cycle
local function AnimateBar(frame, shouldShow)
    local key = frame._def.key
    local def = frame._def

    if frame._aishAnimBusyDir ~= nil then
        if frame._aishAnimBusyDir ~= shouldShow then
            frame._aishAnimQueuedDir = shouldShow
        else
            frame._aishAnimQueuedDir = nil
        end
        return
    end

    if ubFadeTickers[key] then ubFadeTickers[key]:Cancel(); ubFadeTickers[key] = nil end
    local dir = SLIDE_DIR[key] or 0
    local dotN     = frame._dotN or 0          -- points par groupe
    local dotCount = frame._dotCount or 0      -- tous groupes
    local dotRank  = frame._dotRank or {}
    local dotSizes = dotCount > 0 and frame._dotSizes or nil
    local hasName  = frame.nameTxt ~= nil and frame._nameAnchorS ~= nil

    -- Appelee en fin de cycle (show ou hide) : libere le verrou et rejoue la derniere direction en file
    local function FinishAndMaybeReplay()
        frame._aishAnimBusyDir = nil
        local queued = frame._aishAnimQueuedDir
        frame._aishAnimQueuedDir = nil
        if queued ~= nil and queued ~= shouldShow then
            AnimateBar(frame, queued)
        end
    end

    -- Visibilité contrôlée exclusivement via SetAlpha() (jamais protégé en combat) ; Show()/Hide() jamais appelés
    if shouldShow then
        local startA = frame:GetAlpha()
        if startA >= 1 then UpdateBarHealth(frame); return end
        frame._aishAnimBusyDir = true
        local _t0 = GetTime()
        ubFadeTickers[key] = ns.NewTicker(0.016, function()
            local elapsed = GetTime() - _t0
            local p = math.min(elapsed / FADE_DURATION, 1)
            local eased = EaseOut(p)
            frame:SetAlpha(startA + (1 - startA) * eased)
            -- ClearAllPoints/SetPoint sur `frame` sont protégés en combat : on saute le glissement (fond/scale seuls)
            if not InCombatLockdown() then
                PositionBarFrame(frame, dir * SLIDE_DISTANCE * (1 - eased))
            end
            ApplyBarWidthScale(frame, BAR_SCALE_START + (1 - BAR_SCALE_START) * eased, dir)

            if dotSizes then
                for i = 1, dotCount do
                    local d = frame.dots[i]
                    local dx = frame["dot" .. i .. "_dx"]
                    if d and dx then
                        local delay = DotEnterSteps(dotRank[i] or 1, dotN) * DOT_STAGGER
                        local dp = math.min(math.max(elapsed - delay, 0) / FADE_DURATION, 1)
                        local dEased = EaseOut(dp)
                        d:SetAlpha(dEased)
                        d:SetPoint("CENTER", frame, "BOTTOMLEFT",
                            dx + dir * DOT_SLIDE_EXTRA * (1 - dEased), frame._dotYCenter)
                        local sz = dotSizes[i] * (DOT_SCALE_START + (1 - DOT_SCALE_START) * dEased)
                        d:SetSize(sz, sz)
                    end
                end
            end

            if hasName then
                local delay = ENTER_DELAY_NAME * DOT_STAGGER
                local np = math.min(math.max(elapsed - delay, 0) / FADE_DURATION, 1)
                local nEased = EaseOut(np)
                SetNameAlpha(frame, nEased)
                frame.nameTxt:ClearAllPoints()
                frame.nameTxt:SetPoint(frame._nameAnchorS, frame.bgTex, frame._nameAnchorA,
                    frame._nameOffX + dir * NAME_SLIDE_EXTRA * (1 - nEased), frame._nameOffY)
            end

            if elapsed >= TOTAL_DURATION then
                ubFadeTickers[key]:Cancel(); ubFadeTickers[key] = nil
                frame:SetAlpha(1)
                -- SetPoint final protégé en combat : si lockdown, on note la barre en attente (rattrapée à PLAYER_REGEN_ENABLED)
                if InCombatLockdown() then ubPosPending[key] = frame else PositionBarFrame(frame, 0) end
                ApplyBarWidthScale(frame, 1, dir)
                if dotSizes then
                    for i = 1, dotCount do ResetDotToRest(frame, i, dotSizes) end
                end
                if hasName then ResetNameToRest(frame) end
                FinishAndMaybeReplay()
            end
        end)
        UpdateBarHealth(frame)
    else
        local startA = frame:GetAlpha()
        if startA <= 0 then return end
        frame._aishAnimBusyDir = false
        local _t0 = GetTime()
        ubFadeTickers[key] = ns.NewTicker(0.016, function()
            local elapsed = GetTime() - _t0
            -- Cascade de sortie = LIFO exact de la cascade d'entree (nom part en premier, bar+dot3 en dernier)
            local barDelay = LEAVE_DELAY_BAR * DOT_STAGGER_OUT
            local bp = math.min(math.max(elapsed - barDelay, 0) / FADE_DURATION_OUT, 1)
            local bEased = EaseOut(bp)
            frame:SetAlpha(startA * (1 - bEased))
            if not InCombatLockdown() then
                PositionBarFrame(frame, dir * SLIDE_DISTANCE * bEased)
            end
            ApplyBarWidthScale(frame, 1 - (1 - BAR_SCALE_START) * bEased, dir)

            if dotSizes then
                for i = 1, dotCount do
                    local d = frame.dots[i]
                    local dx = frame["dot" .. i .. "_dx"]
                    if d and dx then
                        local delay = DotLeaveSteps(dotRank[i] or 1, dotN) * DOT_STAGGER_OUT
                        local dp = math.min(math.max(elapsed - delay, 0) / FADE_DURATION_OUT, 1)
                        local dEased = EaseOut(dp)
                        d:SetAlpha(1 - dEased)
                        d:SetPoint("CENTER", frame, "BOTTOMLEFT",
                            dx + dir * DOT_SLIDE_EXTRA * dEased, frame._dotYCenter)
                        local sz = dotSizes[i] * (1 - (1 - DOT_SCALE_START) * dEased)
                        d:SetSize(sz, sz)
                    end
                end
            end

            if hasName then
                local delay = LEAVE_DELAY_NAME * DOT_STAGGER_OUT
                local np = math.min(math.max(elapsed - delay, 0) / FADE_DURATION_OUT, 1)
                local nEased = EaseOut(np)
                SetNameAlpha(frame, 1 - nEased)
                frame.nameTxt:ClearAllPoints()
                frame.nameTxt:SetPoint(frame._nameAnchorS, frame.bgTex, frame._nameAnchorA,
                    frame._nameOffX + dir * NAME_SLIDE_EXTRA * nEased, frame._nameOffY)
            end

            if elapsed >= TOTAL_DURATION_OUT then
                ubFadeTickers[key]:Cancel(); ubFadeTickers[key] = nil
                frame:SetAlpha(0)
                -- Meme raisonnement que la branche show : ne pas sauter le snap final si en combat lockdown
                if InCombatLockdown() then ubPosPending[key] = frame else PositionBarFrame(frame, 0) end
                ApplyBarWidthScale(frame, 1, dir)
                if dotSizes then
                    for i = 1, dotCount do ResetDotToRest(frame, i, dotSizes) end
                end
                if hasName then ResetNameToRest(frame) end
                FinishAndMaybeReplay()
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
function UnitBars.ApplySettings()
    EnsurePerBar()   -- profil tout juste charge (changement de profil) : anciens reglages communs repris par barre
    EnsureBarAnchor()
    for _, frame in pairs(bars) do
        ApplyBarSettings(frame)   -- en combat : differe (tailles / positions), voir pendingSettingsApply
        -- Les couleurs, elles, n'ont rien de protege : on les applique tout de suite, sinon un changement de couleur en
        -- plein combat (condition Furtivite des couleurs thematiques, par exemple) attendait la fin du combat
        if InCombatLockdown() then pcall(UpdateBarColor, frame) end
    end
    UnitBars.NotifyPlayerBarMoved()
end

-- Rectangle de la barre de vie du joueur (fond de barre, hors dots), en coordonnees relatives au CENTRE
-- de UIParent : left, right, bottom, top. Calcule depuis la config et non lu sur la frame, pour ignorer
-- les animations d'apparition (glissement/scale). nil si la barre n'existe pas encore.
function UnitBars.GetPlayerBarRect()
    local f = bars.player
    if not (f and f.bgTex) then return nil end
    local x, bottom = BarPos("player")
    local w = f._barW or BV("player", "width")
    local left = x - w / 2
    return left, left + w, bottom, bottom + f.bgTex:GetHeight()
end

-- Previent les elements lies a la barre du joueur (CDs essentiels, cf. CooldownManagerEnhanced.lua)
function UnitBars.NotifyPlayerBarMoved()
    local cdme = ns.Modules and ns.Modules.CooldownManagerEnhanced
    if cdme and cdme.RefreshPlayerBarLink then pcall(cdme.RefreshPlayerBarLink) end
end

-- Appelé par Skyriding.lua quand le skyriding commence/se termine.
function UnitBars.SetSkyridingActive(active)
    if not next(bars) then return end
    ubHiddenForSkyriding = active
    UnitBars.UpdateAllVisibility()
end

--- Cache (on=true) ou restaure (on=false) toutes les barres pour l'onglet Animations 3D.
function UnitBars.SetGuiHidden(on)
    ubHiddenForGui = (on == true)
    UnitBars.UpdateAllVisibility()
end

-- /aishub : etat de la barre du joueur (animation, largeurs, ancres), a lancer quand elle reste trop courte
SLASH_AISHUB1 = "/aishub"
SlashCmdList["AISHUB"] = function()
    local P = "|cff33aaff[UB]|r "
    local f = bars.player
    if not f then print(P .. "pas de barre joueur"); return end
    local function S(fn, ...) local ok, a, b, c, d, e = pcall(fn, ...); return ok and table.concat({ tostring(a), tostring(b), tostring(c), tostring(d), tostring(e) }, " ") or "err" end
    print(P .. string.format("alpha=%s anim=%s file=%s ticker=%s vis=%s combat=%s",
        S(f.GetAlpha, f), tostring(f._aishAnimBusyDir), tostring(f._aishAnimQueuedDir), tostring(ubFadeTickers.player ~= nil),
        tostring(ubLastVisState.player), tostring(InCombatLockdown())))
    print(P .. "config largeur=" .. tostring(Cfg("player").width) .. " _barW=" .. tostring(f._barW)
        .. " | fond=" .. S(f.bgTex.GetWidth, f.bgTex) .. " | barre=" .. S(f.bar.GetWidth, f.bar) .. " | cadre=" .. S(f.GetSize, f))
    print(P .. "ancre cadre=" .. S(f.GetPoint, f, 1))
    print(P .. "ancre fond=" .. S(f.bgTex.GetPoint, f.bgTex, 1) .. " | _barOffX=" .. tostring(f._barOffX))
end

-- bars est locale a ce fichier (pas de nom global par barre) : accesseur pour le survol GUI (ModuleHoverOverlay.lua)
function UnitBars.GetBars()
    return bars
end

-- Etat de visibilite ACTUEL (pas juste la config) de "player", utilise par HealthCircle pour eviter le doublon
function UnitBars.IsPlayerBarShown()
    return ubLastVisState["player"] == true
end

--- Spe tank active ? Lu par PriorityBar pour son decalage vertical dedie.
function UnitBars.IsTankSpec()
    return inTankSpec and true or false
end

--- Resout la spe et applique la geometrie tank, en surveillant quelques secondes.
--- DOIT etre arme depuis Create() et pas depuis l'event handler : celui-ci commence par
--- `if not next(bars) then return end`, or `bars` est encore vide a PLAYER_ENTERING_WORLD
--- (UnitBars.Create est appele par AishCore.lua depuis SON propre handler du meme
--- evenement, et notre eventFrame est enregistre avant). Toute la branche
--- PLAYER_ENTERING_WORLD etait donc avalee par ce garde : seul un changement de spe
--- manuel, qui arrive une fois les barres creees, mettait `inTankSpec` a jour.
--- On surveille au lieu de s'arreter au premier succes : juste apres un /reload,
--- ns.GetSpecialization() peut rendre un index perime avant de se stabiliser.
local function WatchTankSpec()
    local tries, appliedTank = 0, nil
    local function Tick()
        tries = tries + 1
        if UpdateTankSpec() and inTankSpec ~= appliedTank then
            appliedTank = inTankSpec
            for _, f in pairs(bars) do ApplyBarSettings(f) end
            -- ApplyBarSettings ne previent pas de lui-meme : la hauteur de la barre
            -- joueur change, les CDs qui s'y ancrent doivent se repositionner.
            UnitBars.NotifyPlayerBarMoved()
        end
        if tries < 12 then C_Timer.After(0.5, Tick) end
    end
    Tick()
end

-- Les soins previsionnels sont d'abord sortis en vert translucide (alpha 0.5). Le profil
-- a garde cette valeur, donc changer le defaut ne suffit pas : on la remonte une fois a
-- l'opaque. Marque par un drapeau, pour ne jamais ecraser un alpha choisi ensuite.
local function MigrateHealPredOpaque()
    local db = ns.DB and ns.DB.unitBars
    if not db or db.healPredOpaqueFix then return end
    db.healPredOpaqueFix = true
    local c = db.healPredColor
    if type(c) == "table" and c[4] == 0.5 then c[4] = 1 end
end

function UnitBars.Create(parent)
    MigrateHealPredOpaque()
    EnsurePerBar()
    EnsureBarAnchor()
    -- Avant la boucle : CreateUnitBar lit deja GetEffectiveHeight, autant partir avec la
    -- bonne valeur quand la spe est lisible des maintenant.
    UpdateTankSpec()
    for _, def in ipairs(BAR_DEFS) do
        if not bars[def.key] then
            local f = CreateUnitBar(def)
            bars[def.key] = f
            -- Affichage initial
            ApplyBarSettings(f)
        end
    end
    WatchTankSpec()
    -- Forcer la visibilité quand le panneau config s'ouvre/se ferme
    C_Timer.After(0, function()
        local panel = _G["AishCoreSettingsPanel"]
        if panel then
            panel:HookScript("OnShow", function()
                -- Mode preview : ShouldShowBar renvoie true pour toutes les barres.
                ubPreviewMode = true
                UnitBars.UpdateAllVisibility()
                if bars.player then UpdateBarHealth(bars.player) end   -- figee a 75 % (cf. UpdateBarHealth)
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
                            f.hpText:SetText(BV(f._def.key, "hpMode") == "value" and "75K" or "75")
                        end
                    end
                end
            end)
            panel:HookScript("OnHide", function()
                -- Fin de preview : nettoyer les données de test puis recalculer
                ubPreviewMode = false
                UnitBars.HideHitbox()   -- l'apercu de hitbox n'a plus lieu d'etre
                for _, f in pairs(bars) do
                    UpdateBarName(f)
                    if not UnitExists(f._def.unit) then
                        if f.hpText then f.hpText:SetText("") end
                    end
                end
                UnitBars.UpdateAllVisibility()
                if bars.player then UpdateBarHealth(bars.player) end   -- retour a la vie reelle
            end)
        end
    end)
end

-- Événements
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterUnitEvent("UNIT_HEALTH",                 "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH",               "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED",   "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_HEAL_PREDICTION",         "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player", "target", "focus", "pet", "targettarget")
eventFrame:RegisterUnitEvent("UNIT_TARGET",                  "target")  -- target change de cible => mettre a jour targettarget
eventFrame:RegisterUnitEvent("UNIT_NAME_UPDATE",              "target", "focus", "pet", "targettarget")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")   -- niveau devant le nom du joueur
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("UNIT_PET")
if ns.IsForever then pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_HAPPINESS", "pet") end
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
ns.TrackSpecFrame(eventFrame)
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- ACTIVE_TALENT_GROUP_CHANGED se declenche aussi au login, quand le serveur confirme
-- la spe active : c'est le signal fiable que ns.GetSpecialization() devient exploitable,
-- la ou PLAYER_ENTERING_WORLD arrive trop tot.
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
eventFrame:RegisterEvent("PET_BATTLE_CLOSE")
-- Regles de visibilite (zone de repos, groupe, monture)
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
-- Village sur (zone de repos etendue, cf. ns.IsRestArea) : pas d'evenement de repos, on suit la bascule
ns.OnRestAreaChanged(function() UnitBars.UpdateAllVisibility() end)
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")

-- Debug : /ubtank, etat de la hauteur tank (pourquoi une barre ne prend pas sa taille)
SLASH_UBTANK1 = "/ubtank"
SlashCmdList["UBTANK"] = function()
    local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[UBTank]|r " .. tostring(msg)) end
    local idx = ns.GetSpecialization and ns.GetSpecialization()
    local okS, sid = pcall(ns.GetSpecializationInfo, idx or 0)
    p(string.format("ns.GetSpecialization()=%s  specID(ok=%s)=%s  TANK_SPECS[specID]=%s",
        tostring(idx), tostring(okS), tostring(sid), tostring(sid and TANK_SPECS[sid])))
    p(string.format("inTankSpec=%s  (UpdateTankSpec() vient de renvoyer %s)",
        tostring(inTankSpec), tostring(UpdateTankSpec())))
    local db = ns.GetCfg("unitBars")
    p(string.format("useTankHeight=%s  tankHeight=%s",
        tostring(db and db.useTankHeight), tostring(db and db.tankHeight)))
    local nb = 0
    for _ in pairs(bars) do nb = nb + 1 end
    p(string.format("barres creees=%d", nb))
    local f = bars.player
    if f then
        local cfg = Cfg("player")
        p(string.format("player: hauteur attendue=%s  bgTex=%.1f  bar=%.1f  cfg.height=%s",
            tostring(GetEffectiveHeight("player")),
            f.bgTex and f.bgTex:GetHeight() or -1,
            f.bar and f.bar:GetHeight() or -1,
            tostring(cfg.height)))
    else
        p("bars.player est nil")
    end
end

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
        -- Dernier instant avant le verrouillage : une barre en plein glissement (apparue en sortie de furtivite,
        -- juste avant l'attaque) restait figee a son decalage tout le combat, le cadre ne pouvant plus bouger.
        -- On la pose a sa place ; l'animation continue en fondu et en largeur.
        for k, f in pairs(bars) do
            if ubFadeTickers[k] or ubPosPending[k] then
                PositionBarFrame(f, 0)
                ubPosPending[k] = nil
            end
        end
        UnitBars.UpdateAllVisibility()   -- le debounce détecte le changement d'état
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Rattraper les snaps de position finale sautes en combat (cf. AnimateBar)
        if next(ubPosPending) then
            for k, f in pairs(ubPosPending) do
                PositionBarFrame(f, 0)
                ubPosPending[k] = nil
            end
        end
        UnitBars.UpdateAllVisibility()   -- le debounce détecte le changement d'état
        if pendingSettingsApply then
            C_Timer.After(0.4, function()
                if pendingSettingsApply then
                    pendingSettingsApply = false
                    for _, f in pairs(bars) do ApplyBarSettings(f) end
                    UnitBars.NotifyPlayerBarMoved()
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

    if event == "PLAYER_UPDATE_RESTING" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        UnitBars.UpdateAllVisibility()
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM"
       or event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_LOGIN" then
        local wasTank = inTankSpec
        UpdateTankSpec()
        if event ~= "UPDATE_SHAPESHIFT_FORM" then
            -- Changement de spé complet (ou confirmation au login) : réappliquer
            -- systématiquement, et prévenir les CDs ancrés à la barre joueur.
            for _, f in pairs(bars) do ApplyBarSettings(f) end
            UnitBars.NotifyPlayerBarMoved()
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
        -- Reapplication differee INCONDITIONNELLE. Deux raisons cumulees, qui rendent le
        -- passage synchrone ci-dessus inoperant au login :
        --   1. `bars` est encore VIDE ici. UnitBars.Create() est appele par AishCore.lua
        --      depuis SON propre handler PLAYER_ENTERING_WORLD ; or l'eventFrame de ce
        --      fichier est enregistre en premier (UnitBars.lua est charge avant
        --      AishCore.lua dans le .toc), donc on passe ici AVANT que les barres
        --      existent -- la boucle ci-dessus ne s'applique a rien.
        --   2. juste apres un /reload, ns.GetSpecialization() repond nil un court instant,
        --      donc inTankSpec vaut encore false quand AishCore cree puis configure les
        --      barres dans la foulee.
        -- On repasse donc apres coup des que la spe est lisible, sans condition sur un
        -- changement d'etat : c'est le seul passage qui voit a la fois les barres creees
        -- et la spe resolue.
        -- On SURVEILLE pendant quelques secondes au lieu de s'arreter a la premiere
        -- resolution : juste apres un /reload, ns.GetSpecialization() peut d'abord rendre
        -- un index perime (resolu, mais pas la bonne spe) avant de se stabiliser. Un
        -- retry qui s'arrete au premier succes fige alors la mauvaise hauteur -- d'ou un
        -- comportement intermittent d'un reload a l'autre.
        -- Rechargement de zone : les barres existent deja ici. Le cas du login, lui, est
        -- couvert par WatchTankSpec() arme depuis Create() -- cette branche n'y est jamais
        -- atteinte a cause du garde `next(bars)` en tete du handler.
        WatchTankSpec()
        -- Retry deferred : UnitHealthMax retourne 0 juste apres un reload tant que le serveur n'a pas repondu
        local retryCount = 0
        local function RetryHealth()
            retryCount = retryCount + 1
            local allValid = true
            for _, f in pairs(bars) do
                -- pcall car UnitHealthMax peut retourner un secret number tainté (timer après action sécurisée)
                local ok, maxIsZero = pcall(function()
                    return UnitExists(f.unit) and UnitHealthMax(f.unit) == 0
                end)
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
        -- Comme TopTargetBar : ne pas lire UnitHealth ici (tainté après clic secure), le fill vient du ticker 0.1s
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

    if event == "UNIT_HAPPINESS" then
        local f = bars.pet
        if f then UpdatePetHappiness(f) end
        return
    end

    -- UnitLevel pas encore a jour a l'evenement : rafraichi juste apres
    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0.5, function() if bars.player then UpdateBarName(bars.player) end end)
        return
    end

    -- Nom du pet/cible parfois "Unknown" à l'invocation : rafraîchir quand le nom est chargé
    if event == "UNIT_NAME_UPDATE" then
        local k = UNIT_KEY[arg1]
        local f = k and bars[k]
        if f then UpdateBarName(f) end
        return
    end

    if event == "UNIT_TARGET" and arg1 == "target" then
        local tt = bars.targettarget
        if tt then UpdateBarHealth(tt); UpdateBarColor(tt); UpdateBarName(tt) end
        return
    end

    if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        local k = UNIT_KEY[arg1]
        local f = k and bars[k]
        if f then pcall(UpdateHealPrediction, f) end
        return
    end

    -- UNIT_HEALTH / UNIT_MAXHEALTH : pour target, fill géré exclusivement par le ticker 0.1s (health tainté)
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
    if tg.hpCalc and not absorbReversed then
        pcall(UnitGetDetailedHealPrediction, "target", nil, tg.hpCalc)
        pcall(function()
            tg.bar:SetMinMaxValues(0, tg.hpCalc:GetMaximumHealth())
            ns.SmoothBarValue(tg.bar, tg.hpCalc:GetCurrentHealth())
        end)
    else
        -- C-side pur (mode miroir ou pas de calculateur)
        local cur = UnitHealth("target")
        local max = UnitHealthMax("target")
        tg.bar:SetMinMaxValues(0, max)
        ns.SmoothBarValue(tg.bar, cur)
    end
end

-- Ticker 0.1s : fill + absorb pour target ET les autres barres avec calculateur.
ns.NewTicker(0.1, function()
    if not next(bars) then return end
    -- Target : mise à jour dédiée (tainted health, tickrate élevé)
    local tg = bars.target
    if tg and tg:GetAlpha() >= 0.01 and UnitExists("target") then
        pcall(_TickUBTargetHP)
    end
    -- Toutes les barres sauf targettarget : UpdateAbsorb uniforme
    for key, f in pairs(bars) do
        if key ~= "targettarget" and f:GetAlpha() >= 0.01 and UnitExists(f._def.unit) then
            pcall(UpdateHealPrediction, f)
            pcall(UpdateAbsorb, f)
        end
    end
end)


-- Suivi du HUD de monture : retire / remet la zone elargie des barres quand il apparait / disparait.
-- Hors combat seulement (le pad est un frame protege) ; en combat il est deja retire, on rattrape a la sortie.
local seatHudWas = false
local function RefreshSeatHud()
    local now = ComputeNoTolMount()
    noTolMount = now   -- cache lu par ConfiguredHoverTol ; la zone de clic se met a jour hors combat
    if now == seatHudWas or InCombatLockdown() then return end
    seatHudWas = now
    for _, f in pairs(bars) do ApplyHitPad(f, ConfiguredHoverTol()) end
end
ns.NewTicker(0.5, function()
    if next(bars) then RefreshSeatHud() end
end)

-- Ticker de survol (0.05 s) : detecte l'entree/sortie du curseur dans la zone tolerante de
-- chaque barre, puis reevalue la visibilite et/ou le texte HP. Ne coute rien quand les deux
-- options sont eteintes -- c'est le cas par defaut.
ns.NewTicker(0.05, function()
    if not next(bars) then return end
    local db = ns.GetCfg("unitBars")
    if not db then return end
    local reveal   = HoverRevealActive()
    local hoverVal = false   -- "Valeur au survol" sur au moins une barre
    for k in pairs(bars) do if BV(k, "hpHoverValue") then hoverVal = true end end

    if not (reveal or hoverVal) then
        -- Option coupee alors qu'une barre etait survolee : effacer l'etat et rendre la main
        -- aux reglages normaux (visibilite ET texte), sinon la derniere barre survolee reste figee.
        if next(ubHovered) then
            wipe(ubHovered)
            for _, f in pairs(bars) do
                if f.hpText and UnitExists(f._def.unit) then
                    SetHPText(f.hpText, f._def.unit, f._def.key)
                end
            end
            UnitBars.UpdateAllVisibility()
        end
        return
    end

    local tol = EffectiveHoverTol()
    local changed = false
    for key, f in pairs(bars) do
        local hovered = IsBarHovered(f, tol)
        if hovered ~= (ubHovered[key] or false) then
            ubHovered[key] = hovered or nil
            changed = true
            if f.hpText and UnitExists(f._def.unit) then
                SetHPText(f.hpText, f._def.unit, key)
            end
        end
    end
    if changed and reveal then UnitBars.UpdateAllVisibility() end
end)


-- Nom du joueur au survol : fondu d'entree / de sortie (comme le nom de la cible), texte vide a la fin de la sortie.
-- Pendant une animation de la barre (reveal), c'est elle qui gere l'opacite du nom ; nom permanent : pas de fondu.
local nameFadeTicker
function FadePlayerName(f, show)
    if nameFadeTicker then nameFadeTicker:Cancel(); nameFadeTicker = nil end
    playerNameFadingOut = false
    if BV("player", "nameAlways") then
        UpdateBarName(f)
        return
    end
    local from = show and 0 or f.nameTxt:GetAlpha()
    if show then UpdateBarName(f) else playerNameFadingOut = true end
    -- Animation de la barre (reveal) en cours : elle gere l'opacite du nom, on ne fait que tenir le texte
    if show and not ubFadeTickers.player then SetNameAlpha(f, 0) end
    local dur = show and FADE_DURATION or FADE_DURATION_OUT
    local t0 = GetTime()
    nameFadeTicker = ns.NewTicker(0.016, function()
        local p = math.min((GetTime() - t0) / dur, 1)
        local e = EaseOut(p)
        if p < 1 then
            if not ubFadeTickers.player then
                SetNameAlpha(f, show and (from + (1 - from) * e) or (from * (1 - e)))
            end
            return
        end
        nameFadeTicker:Cancel(); nameFadeTicker = nil
        if not show then
            playerNameFadingOut = false
            UpdateBarName(f)
        end
        if not ubFadeTickers.player then SetNameAlpha(f, 1) end
    end)
end

-- Nom du personnage au survol de sa barre de vie (option showName de la barre du joueur), jamais en combat. Meme zone de survol que
-- la reveal "Au survol" (tolerance comprise).
ns.NewTicker(0.1, function()
    local f = bars.player
    if not f then return end
    local db = ns.GetCfg("unitBars")
    local want = false
    if db and BV("player", "showName") and not InCombatLockdown() and f:GetAlpha() > 0.05 then
        want = IsBarHovered(f, EffectiveHoverTol())
    end
    if want ~= playerNameShown then
        playerNameShown = want
        FadePlayerName(f, want)
    end
end)

-- Forever : survol de la barre du familier -> la barre d'xp passe sur le familier (niveau, xp, loyaute). Detection par
-- position du curseur, zone tolerante comprise (meme zone que la reveal "Au survol"), et non par OnEnter / OnLeave : la
-- zone elargie est un autre cadre, et passer de l'un a l'autre ferait clignoter l'affichage.
local petHoverOn = false
ns.NewTicker(0.1, function()
    if not ns.IsForever then return end
    local f = bars.pet
    local hovered = false
    if f and f:GetAlpha() > 0.05 and UnitExists("pet") then
        hovered = IsBarHovered(f, EffectiveHoverTol())
    end
    if hovered ~= petHoverOn then
        petHoverOn = hovered
        local XPB = ns.Modules and ns.Modules.XPBar
        if XPB and XPB.SetPetHover then XPB.SetPetHover(hovered) end
    end
end)

-- Ticker 0.5s : targettarget + texte HP% target + masquage si unité disparue
ns.NewTicker(0.5, function()
    if not next(bars) then return end
    local guiOpen = _G["AishCoreSettingsPanel"] and _G["AishCoreSettingsPanel"]:IsShown()
    local tg = bars.target
    if tg then
        if UnitExists("target") then
            if tg.hpText then
                SetHPText(tg.hpText, "target", "target")
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

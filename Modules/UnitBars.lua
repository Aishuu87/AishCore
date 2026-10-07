-- Modules/UnitBars.lua : Barres de vie Player, Target, Focus, Pet, TargetTarget
local addonName, ns = ...
local L = ns.L

local UnitBars = {}
ns.Modules.UnitBars = UnitBars

-- Constantes visuelles
-- Texture de la barre : cle de config resolue a chaque appel (ns.BAR_TEXTURES),
-- pour que le choix du dropdown s'applique sans /reload.
local function BarTex()
    return ns.ResolveBarTexFromKey((ns.GetCfg("unitBars") or {}).barTexture)
end
local DEFAULT_FONT   = ns.FONT_FALLBACK  -- police du jeu (2002), aucune media pack requise
-- Couleur "noire" commune (#0e0e0e)
local DARK         = 14/255
-- Couleur de fond commune (presque noir)
local DEFAULT_BG   = { DARK, DARK, DARK, 1 }
-- Ratios de base des 3 dots (le 3e est la référence)
local DOT_BASE    = { 3, 5, 9 }
local DOT_SPACING = 3   -- gap interne (fixe) entre chaque dot

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
--- Distinction importante : juste apres un /reload, GetSpecialization() repond nil
--- pendant quelques instants. L'ancienne version passait alors 0 a
--- GetSpecializationInfo, recevait nil, et en concluait "pas tank" -- les barres
--- gardaient donc leur geometrie non-tank jusqu'au prochain changement de spe.
--- On ne touche plus a inTankSpec tant que la reponse n'est pas fiable.
local function UpdateTankSpec()
    local idx = GetSpecialization and GetSpecialization()
    if not idx or idx == 0 then return false end
    local ok, specID = pcall(GetSpecializationInfo, idx)
    if not ok or not specID or specID == 0 then return false end
    inTankSpec = TANK_SPECS[specID] or false
    return true
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

-- Descripteurs de chaque barre
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

-- Tables des frames créés
local bars = {}   -- bars[key] = frame
local pendingSettingsApply  = false  -- re-appliquer les settings apres combat
local ubFadeTickers         = {}     -- key → ticker de fade par barre
local ubPosPending          = {}     -- key → frame dont le snap de position finale a ete saute (combat lockdown)
local ubLastVisState        = {}     -- key → dernier état de visibilité (true/false)
local ubHovered             = {}     -- key → true si le curseur est dans la zone tolérante
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
local function ConfiguredHoverTol()
    local db = ns.GetCfg("unitBars")
    if not (db and db.hoverReveal) then return 0 end
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
    pad:ClearAllPoints()
    if tol <= 0 then
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
    for key, f in pairs(bars) do
        -- Repartir propre : une barre decochee entre deux passages garderait son cadre
        -- allume, le ticker precedent ayant ete annule avant de pouvoir le masquer.
        if f._hitPreview then f._hitPreview:Hide() end
        if Cfg(key).enabled ~= false then
            local p = EnsureHitboxFrame(f)
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
        hitboxTicker = C_Timer.NewTicker(0.03, function()
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
    -- "Au survol" : le curseur sur la barre (tolerance comprise) la fait sortir quel que soit
    -- le mode de visibilite. Vient apres les masquages durs (skyriding, vehicule, pet battle) :
    -- ceux-la ne se laissent pas rouvrir a la souris.
    if db and db.hoverReveal and ubHovered[frame._def.key] and UnitExists(unit) then return true end
    -- "Toujours actif en instance" : ignore les transitions combat en donjon/raid, mais le unit doit exister
    if db and db.alwaysInInstance and ns.inInstance then return UnitExists(unit) end
    local vMode = (db and db.visibilityMode)
    if not vMode then
        vMode = (db and db.hideOutOfCombat) and "combat" or "target"
    end
    if vMode == "always" then
        return UnitExists(unit)
    elseif vMode == "combat" then
        return UnitAffectingCombat("player") and UnitExists(unit)
    else  -- "target" : regle commune, cf. ns.ShouldShowForTargetMode (combat sans cible,
          -- cible attaquable hors combat, spe de soin hors combat). La barre d'une unite
          -- inexistante reste masquee : en combat sans cible, seule celle du joueur sort.
        return ns.ShouldShowForTargetMode() and UnitExists(unit)
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
        return REACTION_COLORS.friendly
    end
    local ok, reaction = pcall(function() return UnitReaction(unit, "player") end)
    if ok and reaction then
        -- UnitReaction peut être un nombre privé en raid : détainter avant comparaison (sinon erreur Lua)
        local r = tonumber(tostring(reaction)) or 0
        if     r == 4 then return REACTION_COLORS.neutral
        elseif r  > 4 then return REACTION_COLORS.friendly
        else               return REACTION_COLORS.hostile
        end
    end
    return fallback
end

-- Création d'une barre (appelée une seule fois par key)
-- Forward : PositionBarFrame est defini plus bas (avec les fonctions de refresh), mais OnDragStop
-- doit pouvoir le rappeler pour re-ancrer immediatement dans la convention canonique.
local PositionBarFrame

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
    local frame = CreateFrame("Button", "AishCoreUnitBar_" .. def.key, UIParent, "SecureUnitButtonTemplate")
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
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self:StopMovingOrSizing()
        -- Sauvegarde de la position.
        -- On NE LIT PLUS frame:GetPoint(1) : StartMoving/StopMovingOrSizing re-ancre la frame dans la
        -- convention que WoW juge bonne (souvent un coin, relatif a un bord d'ecran), et l'ancien code
        -- jetait les 3 premiers retours -- donc le point ET le point relatif. Les offsets etaient donc
        -- enregistres dans un repere inconnu, alors que PositionBarFrame les reapplique toujours en
        -- BOTTOM de la frame vers CENTER de UIParent. Tant que rien ne repositionnait, l'ancre de WoW
        -- tenait et tout semblait correct ; au premier ApplyBarSettings (changer la police du nom, par
        -- exemple) la barre se teleportait. Le verrou n'y changeait rien : il bloque le drag, pas la
        -- relecture d'une valeur deja corrompue.
        -- On recalcule donc dans le repere exact de PositionBarFrame, comme le fait deja
        -- ResourceCircle.SetDraggable : centre horizontal, bord bas, relatifs au centre de UIParent.
        local db = ns.DB and ns.DB.unitBars
        if db and db.bars and db.bars[def.key] then
            local cx        = frame:GetCenter()
            local bottom    = frame:GetBottom()
            local ucx, ucy  = UIParent:GetCenter()
            if cx and bottom and ucx and ucy then
                -- Valeurs absolues (repere UIParent CENTER) : c'est deja la convention de stockage,
                -- y compris pour le pet, dont PositionBarFrame soustrait lui-meme la position du joueur.
                db.bars[def.key].x = math.floor(cx - ucx + 0.5)
                db.bars[def.key].y = math.floor(bottom - ucy + 0.5)
            end
        end
        -- Re-ancrage immediat dans la convention canonique : sans ca la frame resterait sur l'ancre
        -- posee par WoW jusqu'au prochain refresh, et on ne verrait le desaccord que plus tard.
        if PositionBarFrame then PositionBarFrame(frame) end
        if def.key == "player" then UnitBars.NotifyPlayerBarMoved() end

        -- Report dans les champs X/Y du panneau (registre rempli par UI/SettingsPanel.lua). Sans ca
        -- les sliders gardaient l'ancienne valeur apres un deplacement a la souris : impossible
        -- d'affiner au clavier ensuite, le premier ajustement renvoyait la barre a son ancien point.
        -- pcall : les widgets sont detruits/recrees a chaque reconstruction de la page.
        local sl = ns._ubPosSliders and ns._ubPosSliders[def.key]
        local saved = db and db.bars and db.bars[def.key]
        if sl and saved then
            if sl.x and saved.x then pcall(sl.x.SetValue, sl.x, saved.x) end
            if sl.y and saved.y then pcall(sl.y.SetValue, sl.y, saved.y) end
        end
    end)

    -- Position initiale (ancre bas : grandit vers le haut si hauteur augmente)
    local x = cfg.x or def.defaults.x
    local y = cfg.y or def.defaults.y
    -- Le pet est ancré sur la barre du joueur (pas UIParent) pour rester correct sur tout ratio d'écran
    if def.key == "pet" and bars.player then
        local pDef = BAR_DEFS[1].defaults
        local pCfg = Cfg("player")
        local px   = pCfg.x or pDef.x
        local py   = pCfg.y or pDef.y
        frame:SetPoint("BOTTOM", bars.player, "BOTTOM", x - px, y - py)
    else
        frame:SetPoint("BOTTOM", UIParent, "CENTER", x, y)
    end

    -- Zone de la barre (à droite ou à gauche selon dotsRight)
    local barOffX = (not def.noDots and def.dotsLeft) and dotsW or 0  -- pas de dotGap ici
    local barH    = h

    -- Fond de la barre (sublevel 1 pour être au-dessus du border)
    local bgTex = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgTex:SetSize(w, barH)
    bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", barOffX, (frameH - barH) / 2)
    frame._barOffX = barOffX
    frame._barOffY = (frameH - barH) / 2
    frame.bgTex = bgTex

    -- StatusBar de remplissage HP (doit exister avant absorbTex qui s'ancre sur son fill)
    local parentLevel = frame:GetFrameLevel()
    local sb = CreateFrame("StatusBar", nil, frame)
    sb:SetFrameLevel(parentLevel + 1)
    sb:SetSize(w, barH)
    sb:SetPoint("TOPLEFT", bgTex)
    sb:SetStatusBarTexture(BarTex())
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    frame.bar = sb

    frame._barW = w

    -- Cadre de rognage : tout ce qui s'ajoute a droite du fill HP (soins previsionnels,
    -- absorb) y est enferme, donc rien ne peut deborder de la barre de vie. Impossible de
    -- calculer la place restante en Lua : la vie courante est un secret number en combat,
    -- on ne peut ni la lire ni la soustraire -- le rognage est la seule voie fiable.
    local clip = CreateFrame("Frame", nil, frame)
    clip:SetFrameLevel(parentLevel + 2)
    clip:SetPoint("TOPLEFT",     bgTex, "TOPLEFT",     0, 0)
    clip:SetPoint("BOTTOMRIGHT", bgTex, "BOTTOMRIGHT", 0, 0)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    frame.clipFrame = clip

    -- Soins previsionnels : segment ajoute au bord droit du fill HP, AVANT l'absorb.
    -- Meme principe que la barre d'absorb : la valeur vient du calculateur et peut etre un
    -- secret number, donc elle est passee telle quelle a SetValue, jamais lue cote Lua.
    pcall(function()
        local healBar = CreateFrame("StatusBar", nil, clip)
        healBar:SetFrameLevel(clip:GetFrameLevel() + 1)
        healBar:SetSize(w, barH)
        healBar:SetPoint("LEFT", sb:GetStatusBarTexture(), "RIGHT", 0, 0)
        healBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local _hc = (ns.GetCfg("unitBars") or {}).healPredColor or { 0.15, 0.85, 0.35, 1 }
        healBar:SetStatusBarColor(_hc[1], _hc[2], _hc[3], _hc[4] or 1)
        healBar:EnableMouse(false)  -- ne pas intercepter les clics (SecureUnitButtonTemplate parent)
        healBar:SetMinMaxValues(0, 1)
        healBar:SetValue(0)
        frame.healPredBar = healBar
    end)

    -- Barre d'absorb : StatusBar sans REVERSE_FILL, ancrée au bord droit du fill HP (C-side, secret numbers OK)
    pcall(function()
        local absorbBar = CreateFrame("StatusBar", nil, clip)
        absorbBar:SetFrameLevel(clip:GetFrameLevel() + 2)
        absorbBar:SetSize(w, barH)
        -- Derriere le segment de soins : sa texture est large de 0 quand il n'y a aucun
        -- soin en vol, donc l'absorb reste colle au fill HP dans ce cas.
        absorbBar:SetPoint("LEFT", (frame.healPredBar or sb):GetStatusBarTexture(), "RIGHT", 0, 0)
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
            -- Soins previsionnels : borner au maximum de vie, sinon un gros soin deborde
            -- largement de la barre.
            if calc.SetIncomingHealClampMode and Enum and Enum.UnitIncomingHealClampMode then
                calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)
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
    local GLOW_TEX  = "Interface\\AddOns\\AishCore\\Media\\UI\\GlowTex.tga"
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

    -- Trois dots décoratifs (absents pour targettarget)
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
            d:SetTexture("Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2.tga")
            d:SetVertexColor(dotColors[i][1], dotColors[i][2], dotColors[i][3], 1)
            frame["dot" .. i] = d
            frame["dot" .. i .. "_dx"] = dx
        end
        frame._dotYCenter = dotYCenter
    end

    -- Texte HP% (player et target uniquement)
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
        frame.hpTextSlug = ns.CreateSlugRing(tbFrame, txt)
        ns.ApplyTextOutlineStyle(txt, frame.hpTextSlug, ns.Media.font, txtSize, ubCfg and ubCfg.hpOutlineStyle)
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

    -- Texte de nom d'unité (target, focus, pet, targettarget)
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
        frame.nameTxtSlug = ns.CreateSlugRing(frame, nameTxt)
        ns.ApplyTextOutlineStyle(nameTxt, frame.nameTxtSlug, DEFAULT_FONT, nSize, db and db.nameOutlineStyle)
        nameTxt:SetJustifyH(justify)
        nameTxt:SetShadowColor(0, 0, 0, 0.7)
        nameTxt:SetTextColor(1, 1, 1, 1)
        nameTxt:SetPoint(anchorS, bgTex, anchorA, nOffX, nOffY)
        nameTxt:SetText("")
        frame.nameTxt = nameTxt
        frame._nameAnchorS, frame._nameAnchorA = anchorS, anchorA
        frame._nameOffX, frame._nameOffY = nOffX, nOffY
    end

    return frame
end

-- Helper : mise à jour du texte HP selon le mode (pct ou value)
local function SetHPText(hpTextWidget, unit, barKey)
    local db   = ns.GetCfg("unitBars")
    local mode = (db and db.hpDisplayMode) or "pct"
    -- "Valeur au survol" : la barre sous le curseur passe en valeur brute, quel que soit le mode.
    if barKey and db and db.hpHoverValue and ubHovered[barKey] then mode = "value" end
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
-- Volontairement SANS ns.SmoothSetValue : l'absorb est ancre au bord droit du fill HP et
-- se repositionne a chaque passage -- une valeur interpolee le ferait flotter a cote.
local function UpdateAbsorb(frame)
    if not frame.hpCalc or not frame.absorbBar then return end
    local db2  = ns.GetCfg("unitBars")
    local show = db2 == nil or db2.showAbsorb ~= false
    if not show then frame.absorbBar:SetValue(0); return end
    -- UnitGetTotalAbsorbs retourne un secret number, passé directement à SetValue (C-side)
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
            -- Défaut : ancré au bord droit du segment de soins (donc du fill HP quand
            -- aucun soin n'est en vol -- la texture fait alors 0 de large)
            frame.absorbBar:SetPoint("LEFT", (frame.healPredBar or frame.bar):GetStatusBarTexture(), "RIGHT", 0, 0)
            frame.absorbBar:SetMinMaxValues(0, frame.hpCalc:GetMaximumHealth())
        end
        frame.absorbBar:SetValue(absorb)
        frame.absorbBar:SetStatusBarColor(ac[1], ac[2], ac[3], ac[4] or 1)
    end)
end

-- Soins previsionnels. Comme UpdateAbsorb : pas de lissage (le segment est ancre au bord
-- droit du fill HP et se repositionne a chaque passage), et aucune valeur n'est lue cote
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

-- Mise à jour du nom d'unité
local function UpdateBarName(frame)
    if not frame.nameTxt then return end
    local unit = frame.unit
    if UnitExists(unit) then
        -- Détainter UnitName (secret string en instance/raid) via concaténation avant SetText
        local rawName = UnitName(unit)
        frame.nameTxt:SetText((rawName and ("" .. rawName)) or "")
    elseif ubPreviewMode and (unit == "target" or unit == "targettarget" or unit == "focus" or unit == "pet") then
        -- Preview : nom spécifique au module quand l'unité n'existe pas
        local PREVIEW_NAMES = {
            target       = L["UNITBARS_PREVIEW_TARGET"],
            targettarget = L["UNITBARS_PREVIEW_TARGETTARGET"],
            focus        = L["UNITBARS_PREVIEW_FOCUS"],
            pet          = L["UNITBARS_PREVIEW_PET"],
        }
        frame.nameTxt:SetText(PREVIEW_NAMES[unit] or (unit .. " Name"))
    else
        frame.nameTxt:SetText("")
    end
end

-- Repositionne frame selon cfg.x/y, avec decalage horizontal optionnel (extraX, pour l'anim slide-in/out)
function PositionBarFrame(frame, extraX)
    local def = frame._def
    local cfg = Cfg(def.key)
    local x   = (cfg.x or def.defaults.x) + (extraX or 0)
    local y   = cfg.y or def.defaults.y
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
end

-- Application des settings sur un bar déjà créé (ApplySettings)
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

    -- Tolerance de survol : le pad de clic deborde la barre de `tol` px sur les quatre cotes,
    -- sans toucher a sa geometrie visible. Nos barres font quelques pixels de haut : sans ca
    -- elles sont penibles a viser.
    ApplyHitPad(frame, ConfiguredHoverTol())

    -- Repositionner la barre dans le frame
    local barOffX = (not def.noDots and def.dotsLeft) and dotsW or 0  -- pas de dotGap ici
    frame.bgTex:SetSize(w, h)
    frame.bgTex:ClearAllPoints()
    frame.bgTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", barOffX, (frameH - h) / 2)
    frame._barOffX = barOffX
    frame._barOffY = (frameH - h) / 2
    frame.bar:SetSize(w, h)
    frame.bar:SetStatusBarTexture(BarTex())
    frame.bar:ClearAllPoints()
    frame.bar:SetPoint("TOPLEFT", frame.bgTex)
    frame._barW = w
    if frame.healPredBar then
        pcall(function()
            frame.healPredBar:SetSize(w, h)
            frame.healPredBar:ClearAllPoints()
            frame.healPredBar:SetPoint("LEFT", frame.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
        end)
    end
    if frame.absorbBar then
        pcall(function()
            frame.absorbBar:SetSize(w, h)
            frame.absorbBar:ClearAllPoints()
            frame.absorbBar:SetPoint("LEFT", (frame.healPredBar or frame.bar):GetStatusBarTexture(), "RIGHT", 0, 0)
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
                    frame["dot" .. i .. "_dx"] = dx
                end
            end
            frame._dotYCenter = dotYCenter
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
            ns.ApplyTextOutlineStyle(frame.hpText, frame.hpTextSlug, (ubCfg and ubCfg.font) or ns.Media.font, txtSize, ubCfg and ubCfg.hpOutlineStyle)
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
        ns.ApplyTextOutlineStyle(frame.nameTxt, frame.nameTxtSlug, (ubCfg and ubCfg.nameFont) or DEFAULT_FONT, nSize, ubCfg and ubCfg.nameOutlineStyle)
        frame.nameTxt:SetJustifyH(justify_n)
        frame.nameTxt:ClearAllPoints()
        frame.nameTxt:SetPoint(anchorS, frame.bgTex, anchorA, nOffX, nOffY)
        frame._nameAnchorS, frame._nameAnchorA = anchorS, anchorA
        frame._nameOffX, frame._nameOffY = nOffX, nOffY
    end

    -- Repositionner la lueur
    if frame.glowFrame then
        frame.glowFrame:ClearAllPoints()
        frame.glowFrame:SetPoint("TOPLEFT",     frame.bgTex, "TOPLEFT",     -5,  5)
        frame.glowFrame:SetPoint("BOTTOMRIGHT", frame.bgTex, "BOTTOMRIGHT",  5, -5)
    end

    -- Position frame (ancre bas)
    PositionBarFrame(frame, 0)

    -- Réévaluer la visibilité après changement de settings
    ubLastVisState[def.key] = nil
    UnitBars.UpdateAllVisibility()
    UpdateBarHealth(frame)
    UpdateBarName(frame)
end

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

-- Delais d'entree (cascade bar+dot3 -> dot2 -> dot1 -> nom), en multiples de DOT_STAGGER
local ENTER_DELAY_DOT = { [3] = 0, [2] = 1, [1] = 2 }
local ENTER_DELAY_NAME = 3
-- Delais de sortie : LIFO exact de la cascade d'entree (nom part en premier, bar+dot3 en dernier)
local LEAVE_DELAY_DOT = { [1] = 1, [2] = 2, [3] = 3 }
local LEAVE_DELAY_NAME = 0
local LEAVE_DELAY_BAR = 3
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
    local d = frame["dot" .. i]
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
    n:SetAlpha(1)
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
    local dotSizes = not def.noDots and GetDotSizes() or nil
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
        ubFadeTickers[key] = C_Timer.NewTicker(0.016, function()
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
                for i = 1, 3 do
                    local d = frame["dot" .. i]
                    local dx = frame["dot" .. i .. "_dx"]
                    if d and dx then
                        local delay = (ENTER_DELAY_DOT[i] or 0) * DOT_STAGGER
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
                frame.nameTxt:SetAlpha(nEased)
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
                    for i = 1, 3 do ResetDotToRest(frame, i, dotSizes) end
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
        ubFadeTickers[key] = C_Timer.NewTicker(0.016, function()
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
                for i = 1, 3 do
                    local d = frame["dot" .. i]
                    local dx = frame["dot" .. i .. "_dx"]
                    if d and dx then
                        local delay = (LEAVE_DELAY_DOT[i] or 0) * DOT_STAGGER_OUT
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
                frame.nameTxt:SetAlpha(1 - nEased)
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
                    for i = 1, 3 do ResetDotToRest(frame, i, dotSizes) end
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
    for _, frame in pairs(bars) do
        ApplyBarSettings(frame)
    end
    UnitBars.NotifyPlayerBarMoved()
end

-- Rectangle de la barre de vie du joueur (fond de barre, hors dots), en coordonnees relatives au CENTRE
-- de UIParent : left, right, bottom, top. Calcule depuis la config et non lu sur la frame, pour ignorer
-- les animations d'apparition (glissement/scale). nil si la barre n'existe pas encore.
function UnitBars.GetPlayerBarRect()
    local f = bars.player
    if not (f and f.bgTex) then return nil end
    local def = f._def
    local cfg = Cfg("player")
    local x = cfg.x or def.defaults.x
    local y = cfg.y or def.defaults.y
    local w = f._barW or cfg.width or def.defaults.width
    local left   = x - f:GetWidth() / 2 + (f._barOffX or 0)
    local bottom = y + (f._barOffY or 0)
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
--- GetSpecialization() peut rendre un index perime avant de se stabiliser.
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
                UnitBars.HideHitbox()   -- l'apercu de hitbox n'a plus lieu d'etre
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
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
-- ACTIVE_TALENT_GROUP_CHANGED se declenche aussi au login, quand le serveur confirme
-- la spe active : c'est le signal fiable que GetSpecialization() devient exploitable,
-- la ou PLAYER_ENTERING_WORLD arrive trop tot.
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
eventFrame:RegisterEvent("PET_BATTLE_OPENING_START")
eventFrame:RegisterEvent("PET_BATTLE_CLOSE")

-- Debug : /ubtank, etat de la hauteur tank (pourquoi une barre ne prend pas sa taille)
SLASH_UBTANK1 = "/ubtank"
SlashCmdList["UBTANK"] = function()
    local function p(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[UBTank]|r " .. tostring(msg)) end
    local idx = GetSpecialization and GetSpecialization()
    local okS, sid = pcall(GetSpecializationInfo, idx or 0)
    p(string.format("GetSpecialization()=%s  specID(ok=%s)=%s  TANK_SPECS[specID]=%s",
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
            tostring(GetEffectiveHeight(f._def, cfg)),
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
        --   2. juste apres un /reload, GetSpecialization() repond nil un court instant,
        --      donc inTankSpec vaut encore false quand AishCore cree puis configure les
        --      barres dans la foulee.
        -- On repasse donc apres coup des que la spe est lisible, sans condition sur un
        -- changement d'etat : c'est le seul passage qui voit a la fois les barres creees
        -- et la spe resolue.
        -- On SURVEILLE pendant quelques secondes au lieu de s'arreter a la premiere
        -- resolution : juste apres un /reload, GetSpecialization() peut d'abord rendre
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
            pcall(UpdateHealPrediction, f)
            pcall(UpdateAbsorb, f)
        end
    end
end)


-- Ticker de survol (0.05 s) : detecte l'entree/sortie du curseur dans la zone tolerante de
-- chaque barre, puis reevalue la visibilite et/ou le texte HP. Ne coute rien quand les deux
-- options sont eteintes -- c'est le cas par defaut.
C_Timer.NewTicker(0.05, function()
    if not next(bars) then return end
    local db = ns.GetCfg("unitBars")
    if not db then return end
    local reveal   = db.hoverReveal == true
    local hoverVal = db.hpHoverValue == true

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


-- Ticker 0.5s : targettarget + texte HP% target + masquage si unité disparue
C_Timer.NewTicker(0.5, function()
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

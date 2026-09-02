-- Modules/CharacterArmory.lua : Fiche de personnage enrichie (item level,
-- enchants, gemmes, transmog, degrade d'equipement, durabilite, fond) --
-- v2 : reglages regroupes par categorie -- + largeurs separees zone-perso/
-- colonne-stats.
-- Ne touche QUE la fiche du joueur (CharacterFrame) -- l'Inspect frame d'un
-- autre joueur est hors scope.
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local CharacterArmory = {}
ns.Modules.CharacterArmory = CharacterArmory

local function cfg()
    return ns.GetCfg("characterArmory")
end

-- 18 emplacements d'equipement, dans l'ordre voulu pour le rendu 2 colonnes :
-- l'ordre determine la parite impair=GAUCHE/pair=DROITE (GEAR_DIRECTION plus
-- bas), qui doit correspondre a la vraie disposition 2 colonnes de Blizzard.
local GEAR_LIST = {
    "HeadSlot", "HandsSlot", "NeckSlot", "WaistSlot", "ShoulderSlot", "LegsSlot",
    "BackSlot", "FeetSlot", "ChestSlot", "Finger0Slot", "ShirtSlot", "Finger1Slot",
    "TabardSlot", "Trinket0Slot", "WristSlot", "Trinket1Slot",
    "SecondaryHandSlot", "MainHandSlot",
}
local GEAR_LIST_SET = {}
local GEAR_DIRECTION = {}
for i, n in ipairs(GEAR_LIST) do
    GEAR_LIST_SET[n] = true
    GEAR_DIRECTION[n] = (i % 2 == 1) and "LEFT" or "RIGHT"
end

local CAN_TRANSMOGRIFY = {
    HeadSlot = true, ShoulderSlot = true, BackSlot = true, ChestSlot = true,
    TabardSlot = true, WristSlot = true, HandsSlot = true, WaistSlot = true,
    LegsSlot = true, FeetSlot = true, MainHandSlot = true, SecondaryHandSlot = true,
}

local ENCHANTABLE_SLOTS = {
    HeadSlot = true, ShoulderSlot = true, ChestSlot = true, LegsSlot = true,
    FeetSlot = true, Finger0Slot = true, Finger1Slot = true,
    MainHandSlot = true, SecondaryHandSlot = true,
}

local MAX_GEM_SLOTS = 5
local GRADIENT_TEXTURE = "Interface\\AddOns\\AishCore\\Media\\UI\\Armory\\Gradation.tga"
local BG_TEXTURE_PATH = "Interface\\AddOns\\AishCore\\Media\\UI\\Armory\\"
local BG_ARENA_TEXTURE = [[Interface\PVPFrame\PvpBg-NagrandArena-ToastBG]]

------------------------------------------------------------------------
-- LOOK : agrandissement (largeurs separees) + fond derriere le modele 3D
------------------------------------------------------------------------
local layoutApplied = false
local applyingLayout = false
local DoApplyLayout, DoRestoreLayout
local defaultFrameW, defaultFrameH
local defaultHandsPoints, defaultMainHandPoints, defaultSecondaryHandPoints, defaultModelScenePoints, defaultInsetRightPoints
local bgTex

-- Boutons "Caracteristiques du personnage / Titres / Gestionnaire d'equipement"
-- (coin superieur droit) : confirmes en jeu via GetMouseFocus(). Leur conteneur
-- (PaperDollSidebarTabs) est etire TOPLEFT+BOTTOMRIGHT sur CharacterFrame en
-- entier -- ils suivent donc le bord BRUT de la fiche, pas le panneau de
-- stats. On les ancre nous-memes sur CharacterFrameInsetRight (dont la
-- position est verifiee correcte, cf. diagnostics precedents) pour qu'ils
-- restent fixes juste au-dessus, quel que soit zoneWidth.
local SIDEBAR_TAB_NAMES = { "PaperDollSidebarTab1", "PaperDollSidebarTab2", "PaperDollSidebarTab3" }
local defaultTabOffsets = {}
local defaultTabPoints = {}

-- CharacterStatsPane (texte des stats), et de la meme facon les panneaux
-- Titres / Gestionnaire d'equipement (PaperDollFrame.TitleManagerPane /
-- .EquipmentManagerPane -- CHAMPS de PaperDollFrame, pas des globales, cf.
-- /framestack) sont NATIVEMENT etires (TOPLEFT+BOTTOMRIGHT, tous deux
-- relatifs a CharacterFrameInsetRight) : ce n'est pas un decalage, c'est un
-- ETIREMENT -- confirme en jeu (/aisharmorydebug, numPoints=2) : le bord
-- GAUCHE d'InsetRight est FIXE (ne bouge jamais avec zoneWidth), seul son
-- bord droit suit CharacterHandsSlot -- donc ces panneaux s'ELARGISSENT au
-- lieu de se DECALER, restant visuellement sous le modele 3D. Pour un vrai
-- DECALAGE, on les ancre nous-memes sur CharacterFrame + on leur redonne
-- EXPLICITEMENT leur taille native (SetSize) puisqu'on leur retire le 2e
-- point qui la definissait -- sans ça, le retrait du point d'etirement
-- effondre la taille (constate : texte devenu invisible sans ce SetSize).
local SIDEBAR_PANES = {
    -- widthDelta retire de la largeur ; offsetXDelta compense en decalant
    -- l'ancre TOPRIGHT d'autant vers la gauche -- ensemble, ca fait retrecir
    -- le panneau par la DROITE (bord gauche fixe) plutot que par la gauche
    -- (bord droit fixe, 1ere tentative -- avait empire le chevauchement).
    { key = "stats", get = function() return CharacterStatsPane end, widthDelta = -40, offsetXDelta = -40 },
    { key = "title", get = function() return PaperDollFrame and PaperDollFrame.TitleManagerPane end },
    { key = "equip", get = function() return PaperDollFrame and PaperDollFrame.EquipmentManagerPane end },
    -- La liste des sets d'equipement (ScrollBox, boutons Equiper/Enregistrer)
    -- est un CHILD de EquipmentManagerPane mais avec sa PROPRE ancre native
    -- independante (confirme /framestack) -- repositionner le pane parent ne
    -- la deplace pas, meme remede.
    { key = "equipScroll", get = function()
        local p = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
        return p and p.ScrollBox
    end },
}
local defaultPanePoints = {}
local defaultPaneOffset = {}
local defaultPaneSize = {}

local function CaptureAllPoints(frame)
    local pts = {}
    for i = 1, frame:GetNumPoints() do pts[i] = { frame:GetPoint(i) } end
    return pts
end

local function RestoreAllPoints(frame, pts)
    if not pts then return end
    frame:ClearAllPoints()
    for _, p in ipairs(pts) do frame:SetPoint(unpack(p)) end
end

-- Decale un point (deja restaure sur son ancre d'origine) de deltaX pixels en
-- X, sans presumer du type d'ancrage utilise par Blizzard -- evite de devoir
-- connaitre/deviner la logique d'ancrage interne. Une PREMIERE tentative avait
-- casse le panneau de stats en le REDIMENSIONNANT/re-ancrant avec des valeurs
-- en dur (a la SLE) ; le translater tel quel (meme technique que pour les
-- slots) est sans risque car sa taille/son contenu interne ne changent pas.
local function NudgePointsX(frame, deltaX)
    if not deltaX or deltaX == 0 then return end
    local pts = {}
    for i = 1, frame:GetNumPoints() do pts[i] = { frame:GetPoint(i) } end
    frame:ClearAllPoints()
    for _, p in ipairs(pts) do
        local point, rel, relPoint, x, y = unpack(p)
        frame:SetPoint(point, rel, relPoint, (x or 0) + deltaX, y)
    end
end

local function EnsureBackground()
    if bgTex then return bgTex end
    bgTex = PaperDollFrame:CreateTexture("AishCharacterArmoryBG", "BACKGROUND")
    return bgTex
end

-- Branche sur background.selectedBG, mirroring CA:Update_BG de SLE (character.lua)
-- Recadre (crop) un atlas sur son ratio d'origine au lieu de l'etirer pour
-- remplir tex:GetSize() -- equivalent d'un CSS "background-size: cover".
-- zoneWidth rend le rectangle du fond arbitrairement large, et un simple
-- SetPoint TOPLEFT/BOTTOMRIGHT etire l'image de façon non-uniforme (deforme
-- visiblement l'atlas "dressingroom-background-*", jugee "tres laide" en jeu).
local function FitAtlasCover(tex, atlasName)
    local w, h = tex:GetSize()
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlasName)
    if not (ok and info and info.width and info.height and info.width > 0 and info.height > 0
            and w and h and w > 0 and h > 0) then
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    local srcAspect, dstAspect = info.width / info.height, w / h
    if dstAspect > srcAspect then
        local margin = (1 - srcAspect / dstAspect) / 2
        tex:SetTexCoord(0, 1, margin, 1 - margin)
    else
        local margin = (1 - dstAspect / srcAspect) / 2
        tex:SetTexCoord(margin, 1 - margin, 0, 1)
    end
end

-- mais recadre sur la liste retenue (Covenant/Covenant2 exclus, cf. plan).
local function ApplyBackgroundTexture(bg, c)
    local sel = c.background.selectedBG
    bg:SetVertexColor(1, 1, 1, 1)
    bg:SetTexture(nil)
    bg:SetTexCoord(0, 1, 0, 1)
    if sel == "HIDE" then
        -- rien a afficher
    elseif sel == "CUSTOM" then
        if c.background.customTexture and c.background.customTexture ~= "" then
            bg:SetTexture(c.background.customTexture)
        end
    elseif sel == "CLASS" then
        local _, classFile = UnitClass("player")
        local atlas = "dressingroom-background-" .. classFile:lower()
        bg:SetAtlas(atlas)
        FitAtlasCover(bg, atlas)
    elseif sel == "Arena-bliz" then
        bg:SetTexture(BG_ARENA_TEXTURE)
    else
        bg:SetTexture(BG_TEXTURE_PATH .. sel .. ".blp")
    end
end

-- Masque/affiche le fond d'ecran par defaut de Blizzard derriere le modele.
local function SetDefaultCornersShown(shown)
    local scene = CharacterModelScene
    if scene.BackgroundTopLeft then
        if shown then
            scene.BackgroundTopLeft:Show(); scene.BackgroundTopRight:Show()
            scene.BackgroundBotLeft:Show(); scene.BackgroundBotRight:Show()
        else
            scene.BackgroundTopLeft:Hide(); scene.BackgroundTopRight:Hide()
            scene.BackgroundBotLeft:Hide(); scene.BackgroundBotRight:Hide()
        end
    end
    if scene.backdrop then
        if shown then scene.backdrop:Show() else scene.backdrop:Hide() end
    end
end

-- Garde de reentrance : CharacterFrame:SetSize() plus bas semble declencher
-- CharacterFrame.UpdateSize en interne, ce qui re-declenche notre propre hook
-- sur UpdateSize (cf. Create()) -> CharacterArmory.ApplyLayout() -> SetSize()
-- -> UpdateSize... -> boucle infinie qui agrandit la fiche a l'infini jusqu'a
-- sortir de l'ecran (constate en jeu). Les points d'entree PUBLICS posent la
-- garde puis delegue a Do*Layout (logique reelle, non gardee) -- DoApplyLayout
-- appelle DoRestoreLayout directement (pas la version publique gardee) sinon
-- le chemin "desactive" ne restaurerait plus rien du tout.
function CharacterArmory.ApplyLayout()
    if applyingLayout then return end
    applyingLayout = true
    local ok, err = pcall(DoApplyLayout)
    applyingLayout = false
    if not ok then geterrorhandler()(err) end
end

function DoApplyLayout()
    local c = cfg()
    if not (c.enabled and c.layoutEnabled) then
        DoRestoreLayout()
        return
    end

    if not layoutApplied then
        defaultFrameW, defaultFrameH = CharacterFrame:GetSize()
        defaultHandsPoints = CaptureAllPoints(CharacterHandsSlot)
        defaultMainHandPoints = CaptureAllPoints(CharacterMainHandSlot)
        defaultSecondaryHandPoints = CaptureAllPoints(CharacterSecondaryHandSlot)
        defaultModelScenePoints = CaptureAllPoints(CharacterModelScene)
        if CharacterFrameInsetRight then
            defaultInsetRightPoints = CaptureAllPoints(CharacterFrameInsetRight)
            for _, name in ipairs(SIDEBAR_TAB_NAMES) do
                local btn = _G[name]
                if btn then defaultTabPoints[name] = CaptureAllPoints(btn) end
            end
        end
        for _, pane in ipairs(SIDEBAR_PANES) do
            local f = pane.get()
            if f then defaultPanePoints[pane.key] = CaptureAllPoints(f) end
        end
    end
    layoutApplied = true

    -- Capture de l'offset bouton<->InsetRight EN BOUCLE (pas une seule fois) :
    -- constate en jeu que GetRight()/GetTop() renvoyaient nil au tout premier
    -- ApplyLayout (avant que la disposition ne soit resolue), donc la capture
    -- one-shot echouait silencieusement et les boutons restaient sur leur
    -- ancre native pour toujours. Sans danger de re-essayer tant que la
    -- valeur n'est pas encore capturee : le bouton reste sur son ancre
    -- native (donc suit CharacterFrame 1:1) jusqu'a la 1ere capture reussie,
    -- et le nudge natif s'annule avec celui d'InsetRight (les deux montent
    -- de +zoneWidth depuis leur propre baseline), donc l'offset mesure reste
    -- correct meme capture tardivement, a zoneWidth non nul.
    -- Meme logique de capture-en-boucle pour l'offset pane<->CharacterFrame
    -- (bord droit de la fiche) : chaque pane reste sur sa chaine native
    -- (InsetRight/CharacterFrameInset) jusqu'a la 1ere capture reussie --
    -- cette chaine bouge deja de +zoneWidth (confirme en jeu), donc la
    -- difference mesuree reste la vraie baseline meme capturee tard. Taille
    -- native capturee EN MEME TEMPS (pas une valeur delta comme l'offset --
    -- si zoneWidth n'est pas 0 a la 1ere capture reussie, la taille figee
    -- sera legerement plus large que le strict necessaire, sans consequence
    -- puisqu'on ne cherche plus a "fitter" pile, juste a positionner).
    local frameRight, frameTop = CharacterFrame:GetRight(), CharacterFrame:GetTop()
    if frameRight and frameTop then
        for _, pane in ipairs(SIDEBAR_PANES) do
            if not defaultPaneOffset[pane.key] then
                local f = pane.get()
                local sx, sy = f and f:GetRight(), f and f:GetTop()
                if sx and sy then
                    defaultPaneOffset[pane.key] = { sx - frameRight, sy - frameTop }
                    defaultPaneSize[pane.key] = { f:GetWidth(), f:GetHeight() }
                end
            end
        end
    end

    if CharacterFrameInsetRight then
        local ix, iy = CharacterFrameInsetRight:GetRight(), CharacterFrameInsetRight:GetTop()
        if ix and iy then
            for _, name in ipairs(SIDEBAR_TAB_NAMES) do
                if not defaultTabOffsets[name] then
                    local btn = _G[name]
                    local bx, by = btn and btn:GetRight(), btn and btn:GetTop()
                    if bx and by then
                        defaultTabOffsets[name] = { bx - ix, by - iy }
                    end
                end
            end
        end
    end

    -- CharacterHandsSlot est ancre sur CharacterFrameInset:TOPRIGHT (frame
    -- dont la largeur grandit elle-meme avec HandsSlot, cf. plus bas) -- on
    -- le decale explicitement de zoneWidth.
    RestoreAllPoints(CharacterHandsSlot, defaultHandsPoints)
    NudgePointsX(CharacterHandsSlot, c.zoneWidth)
    RestoreAllPoints(CharacterMainHandSlot, defaultMainHandPoints)
    NudgePointsX(CharacterMainHandSlot, c.zoneWidth)
    -- SecondaryHandSlot (bouclier/off-hand, a cote de MainHandSlot en bas) :
    -- constate en jeu que le decaler EN PLUS de MainHandSlot l'envoie beaucoup
    -- trop loin -- son ancre par defaut doit deja etre relative a MainHandSlot
    -- (chainage Blizzard), donc on se contente de la restaurer, SANS la
    -- re-decaler, pour qu'elle suive MainHandSlot sans cumuler.
    RestoreAllPoints(CharacterSecondaryHandSlot, defaultSecondaryHandPoints)
    if CharacterFrameInsetRight then
        -- NE PAS nudger InsetRight ici : mesure en jeu (/aisharmorydebug a 3
        -- valeurs de zoneWidth) -- son bord droit RESOLU bougeait de 2x
        -- zoneWidth au lieu de 1x. Cause : CharacterFrameInset (sa reference
        -- d'ancrage) grandit DEJA tout seul de +zoneWidth (probablement lie a
        -- CharacterHandsSlot, que l'on decale nous-memes) -- en plus de ca on
        -- decalait EXPLICITEMENT InsetRight du meme delta, comptant zoneWidth
        -- deux fois. Simple restauration : InsetRight herite automatiquement
        -- du bon decalage via la croissance de CharacterFrameInset.
        RestoreAllPoints(CharacterFrameInsetRight, defaultInsetRightPoints)

        -- Boutons Caracteristiques/Titres/Gestionnaire d'equipement : ancres
        -- DIRECTEMENT sur InsetRight (offset fige capture au tout premier
        -- calcul), pas laisses suivre le bord etire de CharacterFrame -- ils
        -- restent donc juste au-dessus du panneau de stats, immobiles.
        for _, name in ipairs(SIDEBAR_TAB_NAMES) do
            local btn = _G[name]
            local off = defaultTabOffsets[name]
            if btn and off then
                btn:ClearAllPoints()
                btn:SetPoint("TOPRIGHT", CharacterFrameInsetRight, "TOPRIGHT", off[1], off[2])
            end
        end
    end

    -- Confirme (/aisharmorydebug, numPoints=2) : les 3 panneaux (stats/titres/
    -- gestionnaire) sont NATIVEMENT etires (TOPLEFT+BOTTOMRIGHT, tous deux
    -- relatifs a InsetRight) -- leur bord gauche est FIXE, seul leur bord
    -- droit suit HandsSlot, donc ils S'ELARGISSENT plutot que de se DECALER
    -- (et restent visuellement sous le modele 3D pour Titres/Gestionnaire,
    -- qui ne partagent pas la position d'InsetRight). Pour un vrai decalage,
    -- on les ancre nous-memes sur le bord droit de CharacterFrame -- et comme
    -- ca leur retire leur 2e point (qui definissait leur taille par
    -- etirement), on leur redonne EXPLICITEMENT leur taille native via
    -- SetSize (sinon : invisible, constate en jeu sans ce SetSize).
    for _, pane in ipairs(SIDEBAR_PANES) do
        local f = pane.get()
        local off, sz = defaultPaneOffset[pane.key], defaultPaneSize[pane.key]
        if f and off and sz then
            f:ClearAllPoints()
            f:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", off[1] + (pane.offsetXDelta or 0), off[2])
            f:SetSize(sz[1] + (pane.widthDelta or 0), sz[2])
        elseif f and defaultPanePoints[pane.key] then
            RestoreAllPoints(f, defaultPanePoints[pane.key])
        end
    end

    -- Elargit la fiche d'autant pour ne pas clipper le panneau de stats deplace.
    -- Clamp defensif : une valeur de frameHeight sauvegardee AVANT le
    -- resserrement du slider (420-480, cf. SettingsPanel.lua) resterait hors
    -- bornes tant que l'utilisateur n'a pas retouche le curseur.
    local frameH = math.max(420, math.min(480, c.frameHeight or 444))
    -- NE PAS repositionner CharacterFrame lui-meme : CharacterFrameInset (dont
    -- HandsSlot/InsetRight dependent tous les deux) est ancre relativement a
    -- CharacterFrame -- le recentrer aurait fait heriter Inset du meme
    -- decalage, annulant la moitie du nudge zoneWidth deja verifie correct
    -- (cf. diagnostic en jeu).
    -- +40 = marge fixe (PAS une mesure live -- une valeur constante est sans
    -- risque de feedback loop, contrairement aux tentatives precedentes) :
    -- une fois le double-comptage d'InsetRight corrige ci-dessus, la mesure
    -- en jeu (/aisharmorydebug) montre un manque CONSTANT d'environ 16px
    -- (ne grandit plus avec zoneWidth), donc une marge fixe suffit.
    CharacterFrame:SetSize(defaultFrameW + c.zoneWidth + 40, frameH)
    -- Force le NineSlice (bordure/fond decoratif) a se re-etirer sur la
    -- nouvelle taille : SetSize seul ne suffit pas toujours a re-tirer les
    -- textures de bordure, ce qui laissait le panneau de stats deplace
    -- deborder visuellement hors du fond noir de la fiche.
    if CharacterFrame.NineSlice and CharacterFrame.NineSlice.Layout then
        pcall(CharacterFrame.NineSlice.Layout, CharacterFrame.NineSlice)
    end

    -- 3 points d'ancrage distincts, PAS un simple
    -- TOPLEFT/BOTTOMRIGHT sur MainHandSlot : MainHandSlot est au bas-CENTRE
    -- (a cote du bouclier), pas sur la colonne de droite -- son X est donc
    -- bien plus a gauche que la vraie colonne (HandsSlot, en haut de cette
    -- colonne). Utiliser MainHandSlot pour le bord DROIT du fond le faisait
    -- s'arreter bien avant la colonne, meme a zoneWidth=0.
    local bg = EnsureBackground()
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", CharacterHeadSlot, -6, 6)
    bg:SetPoint("RIGHT", CharacterHandsSlot, 6, 0)
    bg:SetPoint("BOTTOM", CharacterMainHandSlot, 0, -6)
    ApplyBackgroundTexture(bg, c)
    bg:Show()

    -- Le modele occupe TOUT le rectangle du fond (et pas seulement sa hauteur,
    -- comme avant) : sa largeur restait figee a sa taille d'origine (~231px)
    -- meme quand zoneWidth agrandissait le fond, donc son centre calcule sur
    -- le fond ne correspondait plus a son propre centre visuel -- d'ou un
    -- perso non centre / partiellement sous la colonne gauche.
    CharacterModelScene:ClearAllPoints()
    CharacterModelScene:SetAllPoints(bg)
    CharacterModelScene:SetScale(c.modelScale or 1.0)
    SetDefaultCornersShown(not c.hideCorners)
end

function CharacterArmory.RestoreLayout()
    if applyingLayout then return end
    applyingLayout = true
    local ok, err = pcall(DoRestoreLayout)
    applyingLayout = false
    if not ok then geterrorhandler()(err) end
end

function DoRestoreLayout()
    if not layoutApplied then return end
    layoutApplied = false

    if defaultFrameW and defaultFrameH then CharacterFrame:SetSize(defaultFrameW, defaultFrameH) end
    RestoreAllPoints(CharacterHandsSlot, defaultHandsPoints)
    RestoreAllPoints(CharacterMainHandSlot, defaultMainHandPoints)
    RestoreAllPoints(CharacterSecondaryHandSlot, defaultSecondaryHandPoints)
    RestoreAllPoints(CharacterModelScene, defaultModelScenePoints)
    if CharacterFrameInsetRight then
        RestoreAllPoints(CharacterFrameInsetRight, defaultInsetRightPoints)
    end
    for _, name in ipairs(SIDEBAR_TAB_NAMES) do
        local btn = _G[name]
        if btn and defaultTabPoints[name] then
            RestoreAllPoints(btn, defaultTabPoints[name])
        end
    end
    for _, pane in ipairs(SIDEBAR_PANES) do
        local f = pane.get()
        if f and defaultPanePoints[pane.key] then
            RestoreAllPoints(f, defaultPanePoints[pane.key])
        end
    end
    if bgTex then bgTex:Hide() end
    CharacterModelScene:SetScale(1.0)
    SetDefaultCornersShown(true)
end

------------------------------------------------------------------------
-- NIVEAU D'OBJET GLOBAL (natif Blizzard) : le texte agrege affiche par
-- CharacterStatsPane juste au-dessus de "Caracteristiques" -- distinct du
-- ilvl PAR OBJET affiche sur chaque icone d'equipement (cf. ApplyIlvlTextConfig
-- plus bas, un tout autre element). Desactive par defaut (enabled=false) :
-- ne touche rien tant que l'utilisateur ne l'active pas explicitement.
------------------------------------------------------------------------
-- Confirme via /framestack (2026-08-29) : CharacterStatsPane.ItemLevelFrame
-- n'a PAS de champ nomme ".Value" -- le texte est une region ANONYME
-- (affichee "ItemLevelFrame.1ae423cb2a0" dans le framestack, a cote de
-- ".Background" et ".rightGrad" qui sont des textures). On la retrouve en
-- filtrant GetRegions() par type FontString ; au cas ou elle serait en fait
-- nichee dans un frame enfant plutot qu'une region directe, on descend aussi
-- recursivement dans GetChildren() (profondeur limitee, structure Blizzard
-- simple).
local function FindFontStringDeep(frame, depth)
    if not frame or depth > 2 then return nil end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local found = FindFontStringDeep(child, depth + 1)
        if found then return found end
    end
    return nil
end

-- PAS de cache ici (contrairement a une 1ere version) : confirme en jeu qu'avec
-- certains addons de skin tiers actifs, ItemLevelFrame peut contenir DEUX
-- FontStrings simultanement : ".Value" natif (masque, shown=false, reecrit
-- par l'addon tiers) et une AUTRE region anonyme creee/geree par cet addon
-- (visible, shown=true, c'est CELLE-LA que le joueur voit reellement).
-- Prendre ".Value" en priorite visait donc la mauvaise region -- il faut
-- choisir la FontString reellement VISIBLE parmi toutes celles trouvees,
-- pas la premiere/la nommee. Pas de cache : cet etat peut changer selon
-- l'ordre de chargement des addons de skin.
local warnedGlobalIlvlMissing = false
local function GetGlobalIlvlFontString()
    local host = CharacterStatsPane and CharacterStatsPane.ItemLevelFrame
    if not host then return nil end
    local fallback
    for _, region in ipairs({ host:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            if region:IsShown() then
                return region
            end
            fallback = fallback or region
        end
    end
    fallback = fallback or FindFontStringDeep(host, 0)
    if not fallback and not warnedGlobalIlvlMissing then
        warnedGlobalIlvlMissing = true
        print("|cffff4444[AishCore]|r Niveau d'objet global : impossible de trouver le texte natif (CharacterStatsPane.ItemLevelFrame). Le reglage restera sans effet -- merci de le signaler.")
    end
    return fallback
end

local function ApplyGlobalIlvlConfig()
    local c = cfg()
    local g = c.globalIlvl
    if not g or not g.enabled then return end
    local fs = GetGlobalIlvlFontString()
    if not fs then return end
    pcall(function()
        local curFont, curSize, curFlags = fs:GetFont()
        fs:SetFont(g.font or curFont, g.fontSize or curSize, g.fontStyle or curFlags)
    end)
    -- "Couleur de specialisation" : force la couleur configuree dans
    -- Couleurs > Cercle de Puissance (Colors.Get, meme source que le cercle
    -- de ressource) au lieu du color picker propre a cette section.
    if g.useSpecColor then
        local Colors = ns.Modules.Colors
        local color = Colors and Colors.Get and Colors.Get("powercircle")
        if color then
            pcall(function() fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end)
        end
    elseif g.color then
        pcall(function() fs:SetTextColor(unpack(g.color)) end)
    end
end

------------------------------------------------------------------------
-- TEXTES/GEOMETRIE : police + taille + contour + offsets X/Y, appliques
-- globalement (pas a chaque scan de slot), mirroring Update_ItemLevel /
-- Update_Enchant / Update_Durability / Update_Gems de SLE (character.lua).
------------------------------------------------------------------------
local function ApplyIlvlTextConfig()
    local c = cfg()
    local font = c.ilvl.font or ns.Media.fontGui
    for _, slotName in ipairs(GEAR_LIST) do
        local button = _G["Character" .. slotName]
        if button and button.iLvlText then
            if not button.AISH_IlvlSlug then
                button.AISH_IlvlSlug = ns.CreateSlugRing(button, button.iLvlText)
            end
            ns.ApplyTextOutlineStyle(button.iLvlText, button.AISH_IlvlSlug, font, c.ilvl.fontSize, c.ilvl.fontStyle)
            local dir = GEAR_DIRECTION[slotName]
            local oppDir = (dir == "LEFT") and "RIGHT" or "LEFT"
            button.iLvlText:ClearAllPoints()
            button.iLvlText:SetPoint("TOP" .. dir, button, "TOP" .. oppDir,
                (dir == "LEFT") and (2 + c.ilvl.xOffset) or (-2 - c.ilvl.xOffset), -1 + c.ilvl.yOffset)
        end
    end
end

local function ApplyEnchantTextConfig()
    local c = cfg()
    local font = c.enchant.font or ns.Media.fontGui
    for _, slotName in ipairs(GEAR_LIST) do
        local button = _G["Character" .. slotName]
        if button and button.enchantText then
            if not button.AISH_EnchantSlug then
                button.AISH_EnchantSlug = ns.CreateSlugRing(button, button.enchantText)
            end
            ns.ApplyTextOutlineStyle(button.enchantText, button.AISH_EnchantSlug, font, c.enchant.fontSize, c.enchant.fontStyle)
            local dir = GEAR_DIRECTION[slotName]
            local oppDir = (dir == "LEFT") and "RIGHT" or "LEFT"
            button.enchantText:ClearAllPoints()
            button.enchantText:SetPoint(dir, button, oppDir,
                (dir == "LEFT") and (2 + c.enchant.xOffset) or (-2 - c.enchant.xOffset), 1 + c.enchant.yOffset)
        end
    end
end

local function ApplyDurabilityTextConfig()
    local c = cfg()
    local font = c.durability.font or ns.Media.fontGui
    for _, slotName in ipairs(GEAR_LIST) do
        local button = _G["Character" .. slotName]
        if button and button.AISH_DurabilityText then
            if not button.AISH_DurabilityTextSlug then
                button.AISH_DurabilityTextSlug = ns.CreateSlugRing(button, button.AISH_DurabilityText)
            end
            ns.ApplyTextOutlineStyle(button.AISH_DurabilityText, button.AISH_DurabilityTextSlug, font, c.durability.fontSize, c.durability.fontStyle)
            local dir = GEAR_DIRECTION[slotName]
            button.AISH_DurabilityText:ClearAllPoints()
            button.AISH_DurabilityText:SetPoint("TOP" .. dir, button, "TOP" .. dir,
                (dir == "LEFT") and (2 + c.durability.xOffset) or (0 - c.durability.xOffset), -3 + c.durability.yOffset)
        end
    end
end

local function ApplyGemConfig()
    local c = cfg()
    for _, slotName in ipairs(GEAR_LIST) do
        local button = _G["Character" .. slotName]
        if button and button.textureSlot1 then
            local dir = GEAR_DIRECTION[slotName]
            local oppDir = (dir == "LEFT") and "RIGHT" or "LEFT"
            button.textureSlot1:ClearAllPoints()
            button.textureSlot1:SetPoint("BOTTOM" .. dir, button, "BOTTOM" .. oppDir,
                (dir == "LEFT") and (2 + c.gem.xOffset) or (-2 - c.gem.xOffset), 2 + c.gem.yOffset)
            for i = 1, MAX_GEM_SLOTS do
                local tex = button["textureSlot" .. i]
                if tex then tex:SetSize(c.gem.size, c.gem.size) end
            end
        end
    end
end

------------------------------------------------------------------------
-- ENCHANT "REEL" (avec icone de qualite pro) : Blizzard n'expose pas ce texte
-- via le hook PaperDollItemSlotButton_Update (il ne donne que le texte court
-- deja raccourci). Deux techniques combinees, la plus fiable en premier :
--   1) C_TooltipInfo.GetInventoryItem : donnees structurees par TYPE de
--      ligne (Enum.TooltipDataLineType.ItemEnchantment), insensible a la
--      langue/formulation -- plus robuste que le pattern-matching.
--   2) Repli : scan d'un tooltip cache + pattern ENCHANTED_TOOLTIP_LINE --
--      au cas ou l'API structuree ne renverrait pas cette ligne pour une
--      raison quelconque.
-- Ne rescanne que sur changement d'equipement/enchant (pas a chaque appel du
-- hook, cf. cout d'un scan de tooltip).
------------------------------------------------------------------------
local scanTT = CreateFrame("GameTooltip", "AishCharArmoryScanTT", nil, "GameTooltipTemplate")
scanTT:SetOwner(WorldFrame, "ANCHOR_NONE")

local MATCH_ENCHANT = ENCHANTED_TOOLTIP_LINE and ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.+)")

local function ScanRealEnchantText(slotID)
    scanTT:ClearLines()
    local hasItem = scanTT:SetInventoryItem("player", slotID)
    if not hasItem then return nil end

    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem and Enum.TooltipDataLineType then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
        if ok and data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.type == Enum.TooltipDataLineType.ItemEnchantment and line.leftText and line.leftText ~= "" then
                    return line.leftText
                end
            end
        end
    end

    if MATCH_ENCHANT then
        for i = 1, scanTT:NumLines() do
            local line = _G["AishCharArmoryScanTTTextLeft" .. i]
            local text = line and line:GetText()
            if text then
                local enchant = text:match(MATCH_ENCHANT)
                if enchant then return enchant end
            end
        end
    end
    return nil
end

-- Extrait uniquement l'icone de qualite (markup |A...|a ou |T...|t) d'un
-- texte d'enchant "reel", pour l'option "icone seulement".
local function ExtractQualityIcon(enchantText)
    if not enchantText then return nil end
    return enchantText:match("(|A.-|a)") or enchantText:match("(|T.-|t)")
end

local enchantRealCache = {}

local function RescanEnchants()
    wipe(enchantRealCache)
    for _, slotName in ipairs(GEAR_LIST) do
        if ENCHANTABLE_SLOTS[slotName] then
            enchantRealCache[slotName] = ScanRealEnchantText(GetInventorySlotInfo(slotName))
        end
    end
end

------------------------------------------------------------------------
-- EMPLACEMENTS : recoloration ilvl, gemmes (tooltip), durabilite, alerte
-- (barre laterale/basse) + quad "degrade" derriere l'icone.
------------------------------------------------------------------------
local function GetSlotNameFromButton(button)
    local name = button.GetName and button:GetName()
    if not name or name:sub(1, 9) ~= "Character" then return nil end
    return name:sub(10)
end

local function GetItemLevelColor(itemLink, c)
    if not itemLink or c.ilvl.colorType == "NONE" then return nil end
    if c.ilvl.colorType == "GRADIENT" then
        local ilvl = select(4, C_Item.GetItemInfo(itemLink))
        local avg = select(2, GetAverageItemLevel())
        if not ilvl or not avg or avg == 0 then return nil end
        local diff = ilvl - avg
        if diff >= 0 then return 0, 1, 0 end
        local t = math.max(0, math.min(1, -diff / 30))
        return 1, 1 - t, 1 - t
    else
        local quality = select(3, C_Item.GetItemInfo(itemLink))
        local qc = quality and ITEM_QUALITY_COLORS[quality]
        if not qc then return nil end
        return qc.color:GetRGB()
    end
end

local function EnsureGemHitboxes(button)
    if button.AISH_GemsSetup then return end
    button.AISH_GemsSetup = true
    for i = 1, MAX_GEM_SLOTS do
        local tex = button["textureSlot" .. i]
        if tex then
            local hit = CreateFrame("Frame", nil, button)
            hit:SetAllPoints(tex)
            hit:SetFrameLevel(button:GetFrameLevel() + 2)
            hit:SetScript("OnEnter", function(self)
                if self.gemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.gemLink)
                    GameTooltip:Show()
                end
            end)
            hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button["AISH_Gem" .. i] = hit
        end
    end
end

-- Cree la barre d'alerte (cote/bas selon le type de slot) + le quad "degrade" --
-- geometrie statique par slot (calculee une fois), seules couleur/visibilite
-- varient ensuite a chaque mise a jour.
local function EnsureOverlayWidgets(button, slotName)
    if button.AISH_Overlay then return end
    button.AISH_Overlay = true

    local dir = GEAR_DIRECTION[slotName]
    local oppDir = (dir == "LEFT") and "RIGHT" or "LEFT"

    -- SetFont immediat obligatoire : la 1ere ouverture de la fiche declenche
    -- PaperDollItemSlotButton_Update (donc UpdateSlotOverlay -> SetText) AVANT
    -- qu'ApplyDurabilityTextConfig ait pu tourner -- un FontString sans police
    -- jamais definie plante au premier SetText ("Font not set").
    local dur = button:CreateFontString(nil, "OVERLAY")
    dur:SetFont(ns.Media.fontGui, 10, "OUTLINE")
    button.AISH_DurabilityText = dur

    -- Barre d'alerte : pleine largeur en bas pour les armes, pleine hauteur
    -- sur le cote oppose a la colonne pour le reste (mirroring
    -- character.lua:75-93 de SLE -- WarningTexture y est deja une simple
    -- texture blanche recoloree, donc SetColorTexture est fidele, pas une
    -- simplification).
    local warn = button:CreateTexture(nil, "OVERLAY")
    warn:SetColorTexture(1, 1, 1, 1)
    warn:ClearAllPoints()
    -- -2 largeur / -4 hauteur (demande) : les barres depassaient legerement.
    if slotName == "MainHandSlot" or slotName == "SecondaryHandSlot" then
        warn:SetSize(39, 4)
        warn:SetPoint("TOP", button, "BOTTOM", 0, 0)
    else
        warn:SetSize(6, 37)
        warn:SetPoint(oppDir, button, dir, 0, 0)
    end
    warn:Hide()
    button.AISH_Warning = warn

    local warnHit = CreateFrame("Frame", nil, button)
    warnHit:SetAllPoints(warn)
    warnHit:SetFrameLevel(button:GetFrameLevel() + 2)
    warnHit:SetScript("OnEnter", function(self)
        if warn.reason then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(warn.reason, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    warnHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Quad "Degrade" derriere l'icone (mirroring character.lua:55-69 de SLE)
    local grad = button:CreateTexture(nil, "BACKGROUND")
    grad:SetTexture(GRADIENT_TEXTURE)
    grad:ClearAllPoints()
    grad:SetPoint(dir, button, dir, 0, 0)
    grad:SetSize(132, 41)
    if dir == "LEFT" then grad:SetTexCoord(0, 1, 0, 1) else grad:SetTexCoord(1, 0, 0, 1) end
    grad:Hide()
    button.AISH_Gradient = grad
end

local function UpdateSlotOverlay(button, slotName)
    local c = cfg()
    EnsureOverlayWidgets(button, slotName)
    EnsureGemHitboxes(button)

    if not c.enabled then
        if button.iLvlText and button.AISH_DefaultIlvlColor then
            button.iLvlText:SetTextColor(unpack(button.AISH_DefaultIlvlColor))
        end
        button.AISH_DurabilityText:SetText("")
        button.AISH_Warning:Hide()
        button.AISH_Gradient:Hide()
        for i = 1, MAX_GEM_SLOTS do
            local hit = button["AISH_Gem" .. i]
            if hit then hit.gemLink = nil end
        end
        return
    end

    local slotID = GetInventorySlotInfo(slotName)
    local itemLink = GetInventoryItemLink("player", slotID)

    -- Couleur ilvl
    if button.iLvlText then
        if not button.AISH_DefaultIlvlColor then
            button.AISH_DefaultIlvlColor = { button.iLvlText:GetTextColor() }
        end
        local r, g, b = GetItemLevelColor(itemLink, c)
        if r then
            button.iLvlText:SetTextColor(r, g, b)
        else
            button.iLvlText:SetTextColor(unpack(button.AISH_DefaultIlvlColor))
        end
    end

    -- Texte d'enchant "reel" (avec icone de qualite pro), ou icone seule
    if c.enchant.showReal and button.enchantText then
        local real = enchantRealCache[slotName]
        if real then
            if c.enchant.iconOnly then
                button.enchantText:SetText(ExtractQualityIcon(real) or "")
            else
                button.enchantText:SetText(real)
            end
        end
    end

    -- Gemmes : tooltip + detection d'emplacement vide
    local hasEmptySocket = false
    for i = 1, MAX_GEM_SLOTS do
        local hit = button["AISH_Gem" .. i]
        if hit then
            local tex = button["textureSlot" .. i]
            local hasTexture = tex and tex:GetTexture()
            local gemLink
            if itemLink and hasTexture then
                gemLink = select(2, C_Item.GetItemGem(itemLink, i))
            end
            hit.gemLink = c.gem.showTooltips and gemLink or nil
            if hasTexture and not gemLink then hasEmptySocket = true end
        end
    end

    -- Durabilite
    local durText = button.AISH_DurabilityText
    if c.durability.display ~= "Hide" then
        local cur, max = GetInventoryItemDurability(slotID)
        if cur and max and max > 0 and not (c.durability.display == "DamagedOnly" and cur == max) then
            local pct = (cur / max) * 100
            durText:SetFormattedText("%.0f%%", pct)
            if pct < (c.durability.warnPct or 30) then
                durText:SetTextColor(1, 0.2, 0.2)
            else
                durText:SetTextColor(0.8, 0.8, 0.8)
            end
        else
            durText:SetText("")
        end
    else
        durText:SetText("")
    end

    -- Alerte manque d'enchant / gemme (toggle unique showWarning)
    local reason
    if c.showWarning then
        if itemLink and ENCHANTABLE_SLOTS[slotName] then
            local enchText = button.enchantText and button.enchantText:GetText()
            if not (enchText and enchText ~= "") then
                local classID, subclassID = select(12, C_Item.GetItemInfo(itemLink))
                local isShield = slotName == "SecondaryHandSlot" and classID == 4 and subclassID == 6
                if not isShield then reason = L["CHARARMORY_NOT_ENCHANTED"] end
            end
        end
        if hasEmptySocket then
            reason = reason and (reason .. "\n" .. L["CHARARMORY_EMPTY_SOCKET"]) or L["CHARARMORY_EMPTY_SOCKET"]
        end
    end
    button.AISH_Warning.reason = reason
    if reason then
        button.AISH_Warning:SetColorTexture(unpack(c.gradient.warningBarColor))
        button.AISH_Warning:Show()
    else
        button.AISH_Warning:Hide()
    end

    -- Quad "degrade" : priorite objet-de-set > alerte active > qualite > couleur custom
    local grad = button.AISH_Gradient
    if c.gradient.enable and itemLink then
        if reason then
            grad:SetVertexColor(unpack(c.gradient.warningColor))
        elseif c.gradient.setArmor and select(16, C_Item.GetItemInfo(itemLink)) then
            grad:SetVertexColor(unpack(c.gradient.setArmorColor))
        elseif c.gradient.quality then
            local quality = select(3, C_Item.GetItemInfo(itemLink))
            local qc = quality and ITEM_QUALITY_COLORS[quality]
            if qc then grad:SetVertexColor(qc.color:GetRGB()) else grad:SetVertexColor(unpack(c.gradient.color)) end
        else
            grad:SetVertexColor(unpack(c.gradient.color))
        end
        grad:Show()
    else
        grad:Hide()
    end
end

------------------------------------------------------------------------
-- TRANSMOGRIFICATION : icone + glow quand l'apparence differe de l'item de base
------------------------------------------------------------------------
local function EnsureTransmogButton(button)
    if button.AISH_Transmog then return button.AISH_Transmog end
    local btn = CreateFrame("Button", nil, button)
    btn:SetFrameLevel(button:GetFrameLevel() + 3)
    local tex = btn:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 0.85, 1, 0.9)
    btn:SetScript("OnClick", function(self)
        if not self.itemLink then return end
        if IsShiftKeyDown() then
            HandleModifiedItemClick(self.itemLink)
        else
            SetItemRef(self.itemLink, self.itemLink, "LeftButton")
        end
    end)
    btn:SetScript("OnEnter", function(self)
        if not self.itemLink then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.itemLink)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:Hide()
    button.AISH_Transmog = btn
    return btn
end

local function GetTransmogAppearanceLink(slotID)
    local itemLink
    local ok = pcall(function()
        local transmogLocation = TransmogUtil.GetTransmogLocation(slotID, Enum.TransmogType.Appearance, Enum.TransmogModification.Main)
        if not transmogLocation then return end
        local itemBaseSourceID = select(3, C_Transmog.GetSlotVisualInfo(transmogLocation))
        if not itemBaseSourceID or itemBaseSourceID == 0 then return end
        itemLink = select(6, C_TransmogCollection.GetAppearanceSourceInfo(itemBaseSourceID))
    end)
    return ok and itemLink or nil
end

local function UpdateTransmogIndicator(button, slotName)
    local c = cfg()
    if not (c.enabled and c.transmog.enableArrow) or not CAN_TRANSMOGRIFY[slotName] then
        if button.AISH_Transmog then
            button.AISH_Transmog:Hide()
            if ns.HideGlow then ns.HideGlow(button.AISH_Transmog) end
        end
        return
    end

    local slotID = GetInventorySlotInfo(slotName)
    local itemLink = GetTransmogAppearanceLink(slotID)
    local btn = EnsureTransmogButton(button)

    if itemLink then
        btn.itemLink = itemLink
        btn:SetSize(c.transmog.iconSize, c.transmog.iconSize)
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", button, "TOPLEFT", -2, 2)
        btn:Show()
        if c.transmog.enableGlow and ns.ShowGlow then
            ns.ShowGlow(btn, c.transmog.glowStyleIdx, c.transmog.glowColor)
        elseif ns.HideGlow then
            ns.HideGlow(btn)
        end
    else
        btn:Hide()
        if ns.HideGlow then ns.HideGlow(btn) end
    end
end

------------------------------------------------------------------------
-- HOOK COMMUN + INITIALISATION
------------------------------------------------------------------------
local function OnPaperDollSlotUpdate(button)
    local slotName = button and GetSlotNameFromButton(button)
    if not slotName or not GEAR_LIST_SET[slotName] then return end
    UpdateSlotOverlay(button, slotName)
    UpdateTransmogIndicator(button, slotName)
end

function CharacterArmory.Update()
    -- Reassert la disposition a chaque rafraichissement (pas seulement au
    -- premier OnShow) : certains changements d'equipement (ex: passage
    -- 1H+bouclier <-> 2M) declenchent une re-disposition interne de Blizzard
    -- sur les slots d'arme qui peut annuler notre decalage -- idempotent et
    -- peu couteux (juste des SetPoint), donc sans risque a rejouer souvent.
    CharacterArmory.ApplyLayout()
    for _, slotName in ipairs(GEAR_LIST) do
        local button = _G["Character" .. slotName]
        if button then
            UpdateSlotOverlay(button, slotName)
            UpdateTransmogIndicator(button, slotName)
        end
    end
    ApplyIlvlTextConfig()
    ApplyEnchantTextConfig()
    ApplyDurabilityTextConfig()
    ApplyGemConfig()
    ApplyGlobalIlvlConfig()
end

local hooksInstalled = false

function CharacterArmory.Create()
    if hooksInstalled then return end
    if not (CharacterFrame and PaperDollFrame and CharacterModelScene) then return end
    hooksInstalled = true

    CharacterFrame:HookScript("OnShow", function()
        CharacterArmory.ApplyLayout()
        -- Reassert une frame plus tard : au cas ou une routine Blizzard
        -- asynchrone (C_Timer/RunNextFrame) touche la disposition des slots
        -- APRES notre hook OnShow synchrone.
        C_Timer.After(0, CharacterArmory.ApplyLayout)
        -- Filet de securite supplementaire pour le "reskin" (couleurs ilvl/
        -- degrade) : les evenements GET_ITEM_INFO_RECEIVED / PLAYER_AVG_ITEM_
        -- LEVEL_UPDATE couvrent la plupart des cas, mais un refresh differe
        -- direct sur l'ouverture evite de dependre uniquement du bon
        -- declenchement/timing de ces evenements.
        if CharacterArmory.Update then
            C_Timer.After(0.5, function()
                if CharacterFrame:IsShown() then CharacterArmory.Update() end
            end)
        end
    end)
    -- Hook egalement CharacterFrame.UpdateSize pour reappliquer notre taille
    -- APRES que Blizzard ait fait tourner sa propre logique de
    -- redimensionnement interne (bordure/NineSlice) -- filet de securite
    -- ici : si UpdateSize tourne (equipement, changement de
    -- sous-panneau...) apres notre propre ApplyLayout, on se re-applique.
    if CharacterFrame.UpdateSize then
        hooksecurefunc(CharacterFrame, "UpdateSize", function()
            if CharacterFrame:IsShown() then CharacterArmory.ApplyLayout() end
        end)
    end
    hooksecurefunc("PaperDollItemSlotButton_Update", OnPaperDollSlotUpdate)

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    eventFrame:RegisterEvent("SOCKET_INFO_UPDATE")
    eventFrame:RegisterEvent("ENCHANT_SPELL_COMPLETED")
    -- Un item tout juste equipe n'a pas forcement encore ses donnees en
    -- cache cote client : C_Item.GetItemInfo(itemLink) renvoie alors ilvl=nil
    -- (GetItemLevelColor -> return nil, colorType="GRADIENT" n'applique donc
    -- AUCUNE couleur), laissant apparaitre la couleur de RARETE native de
    -- Blizzard en dessous jusqu'au prochain refresh -- constate en jeu : le
    -- degrade "vs niveau moyen" ne s'appliquait pas tout de suite a
    -- l'equipement d'un objet. GET_ITEM_INFO_RECEIVED se declenche des que
    -- ces donnees arrivent, on re-applique alors.
    eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    -- Meme souci pour GetAverageItemLevel() lui-meme : peut renvoyer 0 quelques
    -- instants apres un /reload/connexion, independamment du cache des objets
    -- -- PLAYER_AVG_ITEM_LEVEL_UPDATE se declenche quand Blizzard le recalcule.
    eventFrame:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    -- Rafraichissement de secours best-effort : le nom de cet evenement n'est
    -- pas garanti selon la version client, la mise a jour principale repose
    -- deja sur le hook PaperDollItemSlotButton_Update + PLAYER_EQUIPMENT_CHANGED.
    pcall(eventFrame.RegisterEvent, eventFrame, "TRANSMOG_COLLECTION_UPDATED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "ENCHANT_SPELL_COMPLETED" then
            RescanEnchants()
        end
        if CharacterFrame and CharacterFrame:IsShown() then
            CharacterArmory.Update()
        end
    end)

    RescanEnchants()
end

function CharacterArmory.ApplySettings()
    if not hooksInstalled then CharacterArmory.Create() end
    if CharacterFrame and CharacterFrame:IsShown() then
        -- Update() reapplique deja la disposition en premiere etape.
        CharacterArmory.Update()
    end
end

------------------------------------------------------------------------
-- DEBUG TEMPORAIRE : /aisharmorydebug -- dump l'etat interne (variables
-- locales a ce fichier, donc invisibles depuis un simple /run exterieur) +
-- la position REELLE en jeu des boutons/InsetRight/CharacterFrame, pour
-- diagnostiquer pourquoi texte/boutons restent mal places malgre le nudge.
-- A retirer une fois le probleme resolu.
------------------------------------------------------------------------
SLASH_AISHARMORYDEBUG1 = "/aisharmorydebug"
SlashCmdList["AISHARMORYDEBUG"] = function()
    local c = cfg()
    print("|cff00ccffAishArmory Debug|r zoneWidth=" .. tostring(c.zoneWidth)
        .. " layoutApplied=" .. tostring(layoutApplied)
        .. " defaultFrameW=" .. tostring(defaultFrameW))
    if CharacterFrame then
        print("  CharacterFrame size=" .. tostring(CharacterFrame:GetWidth()) .. "x" .. tostring(CharacterFrame:GetHeight())
            .. " L/R=" .. tostring(CharacterFrame:GetLeft()) .. "/" .. tostring(CharacterFrame:GetRight()))
    end
    if CharacterFrameInsetRight then
        local p, r, rp, x, y = CharacterFrameInsetRight:GetPoint()
        print("  InsetRight point=" .. tostring(p) .. " " .. tostring(r and r.GetName and r:GetName() or r) .. " " .. tostring(rp) .. " " .. tostring(x) .. " " .. tostring(y))
        print("  InsetRight R/T=" .. tostring(CharacterFrameInsetRight:GetRight()) .. "/" .. tostring(CharacterFrameInsetRight:GetTop()))
    end
    for _, name in ipairs(SIDEBAR_TAB_NAMES) do
        local btn = _G[name]
        local off = defaultTabOffsets[name]
        print("  " .. name .. " capturedOffset=" .. (off and (off[1] .. "," .. off[2]) or "NIL"))
        if btn then
            local p, r, rp, x, y = btn:GetPoint()
            print("    currentPoint=" .. tostring(p) .. " " .. tostring(r and r.GetName and r:GetName() or r) .. " " .. tostring(rp) .. " " .. tostring(x) .. " " .. tostring(y))
        end
    end
    for _, pane in ipairs(SIDEBAR_PANES) do
        local f = pane.get()
        if f then
            local off, sz = defaultPaneOffset[pane.key], defaultPaneSize[pane.key]
            print("  " .. pane.key .. " capturedSize=" .. (sz and (sz[1] .. "x" .. sz[2]) or "NIL"))
            print("  " .. pane.key .. " capturedOffset=" .. (off and (off[1] .. "," .. off[2]) or "NIL")
                .. " numPoints=" .. tostring(f:GetNumPoints())
                .. " size=" .. tostring(f:GetWidth()) .. "x" .. tostring(f:GetHeight())
                .. " shown=" .. tostring(f:IsShown()) .. " alpha=" .. tostring(f:GetAlpha()))
            for i = 1, f:GetNumPoints() do
                local p, r, rp, x, y = f:GetPoint(i)
                print("    point" .. i .. "=" .. tostring(p) .. " " .. tostring(r and r.GetName and r:GetName() or r) .. " " .. tostring(rp) .. " " .. tostring(x) .. " " .. tostring(y))
            end
            print("    R/T=" .. tostring(f:GetRight()) .. "/" .. tostring(f:GetTop()))
        else
            print("  " .. pane.key .. " = NIL (frame introuvable)")
        end
    end

    -- Niveau d'objet global : dump de toutes les regions/enfants trouves sous
    -- CharacterStatsPane.ItemLevelFrame (type, texte, police) pour diagnostiquer
    -- pourquoi le reglage reste sans effet visible malgre une region trouvee.
    print("  --- Niveau d'objet global ---")
    print("  CharacterFrame shown=" .. tostring(CharacterFrame and CharacterFrame:IsShown()))
    local g = c.globalIlvl
    print("  cfg.globalIlvl enabled=" .. tostring(g and g.enabled)
        .. " font=" .. tostring(g and g.font) .. " size=" .. tostring(g and g.fontSize)
        .. " style=" .. tostring(g and g.fontStyle) .. " color=" .. tostring(g and g.color and table.concat(g.color, ",")))
    local host = CharacterStatsPane and CharacterStatsPane.ItemLevelFrame
    print("  ItemLevelFrame=" .. tostring(host) .. " host.Value=" .. tostring(host and host.Value))
    if host then
        print("  Regions directes de ItemLevelFrame:")
        for _, region in ipairs({ host:GetRegions() }) do
            local ot = region.GetObjectType and region:GetObjectType() or "?"
            local txt = (ot == "FontString" and region.GetText) and region:GetText() or nil
            local fnt, fsz, ffl = (ot == "FontString" and region.GetFont) and region:GetFont() or nil, nil, nil
            print("    [" .. ot .. "] name=" .. tostring(region.GetName and region:GetName())
                .. " text=" .. tostring(txt) .. " font=" .. tostring(fnt)
                .. " shown=" .. tostring(region.IsShown and region:IsShown()))
        end
        print("  Enfants (frames) de ItemLevelFrame:")
        for _, child in ipairs({ host:GetChildren() }) do
            print("    child name=" .. tostring(child.GetName and child:GetName()))
        end
    end
    local fs = GetGlobalIlvlFontString and GetGlobalIlvlFontString()
    print("  GetGlobalIlvlFontString() -> " .. tostring(fs) .. (fs and (" text=" .. tostring(fs:GetText())) or ""))
end

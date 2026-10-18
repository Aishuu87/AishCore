-- Modules/Colors.lua : gestion centralisée des couleurs par spécialisation
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local Colors = {}
ns.Modules.Colors = Colors

-- Furtivite (Camouflage, Disparition, Danse de l'ombre, Subterfuge, Rodeur...) : partage avec le Mode furtif.
-- IsStealthed() couvre la plupart des cas ; les auras connues rattrapent les autres (Camouflage, Sous camouflage...).
local STEALTH_AURAS = { 1784, 1785, 1786, 1787, 5215, 11327, 115191, 115192, 185313, 185422, 58984, 20580, 199483, 66, 32612 }
-- Renvoie (furtif, faible) : faible = detecte uniquement par la barre d'action "bonus" du Voleur, la seule regle sujette
-- aux faux positifs (monture...) : ceux-la sont confirmes apres un court delai par les appelants. IsStealthed() et les
-- auras sont fiables, donc immediates.
function ns.IsPlayerStealthed()
    -- La comparaison est faite DANS le pcall : en combat, une valeur secrete leve une erreur a la comparaison
    local ok, v = pcall(function() return (IsStealthed and IsStealthed()) == true end)
    if ok and v == true then return true end
    -- Voleur : IsStealthed() est faux en Danse de l'ombre / Subterfuge ; la barre d'action "bonus" change, elle, avec la
    -- furtivite (meme regle que les animations d'orbes, cf. SpellEffects.IsInStealth)
    -- Cette barre change aussi en monture (volante / skyriding), en vehicule ou avec une barre de remplacement : ces cas
    -- ne sont pas de la furtivite, on les exclut.
    if (ns._playerClass or select(2, UnitClass("player"))) == "ROGUE" and GetBonusBarIndex
       and not (IsMounted and IsMounted())
       and not (HasVehicleActionBar and HasVehicleActionBar())
       and not (HasOverrideActionBar and HasOverrideActionBar())
       and not (UnitInVehicle and UnitInVehicle("player"))
       and not UnitCastingInfo("player") then   -- invocation d'une monture en cours : la barre change deja, pas encore IsMounted
        local okB, inBonus = pcall(function() return GetBonusBarIndex() ~= 0 end)
        if okB and inBonus == true then return true, true end
    end
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if get then
        for _, id in ipairs(STEALTH_AURAS) do
            local okA, a = pcall(get, id)
            if okA and a then return true end
        end
    end
    return false
end

-- /sestealth : detail de chaque critere de furtivite (a coller pour diagnostiquer un faux positif, monture par exemple)
SLASH_SESTEALTH1 = "/sestealth"
SlashCmdList["SESTEALTH"] = function()
    local P = "|cff33aaff[SEstealth]|r "
    local function B(f, ...) local ok, v = pcall(f, ...); return ok and tostring(v) or "err" end
    print(P .. "final=" .. tostring(ns.IsPlayerStealthed()) .. " classe=" .. tostring(ns._playerClass) .. " monte=" .. tostring(IsMounted and IsMounted())
        .. " vol=" .. B(IsFlying) .. " vehicule=" .. B(UnitInVehicle, "player") .. " incante=" .. tostring((UnitCastingInfo("player"))))
    print(P .. "IsStealthed=" .. B(function() return IsStealthed() end) .. " | barre bonus=" .. B(GetBonusBarIndex)
        .. " | barre vehicule=" .. B(HasVehicleActionBar) .. " | barre de remplacement=" .. B(HasOverrideActionBar))
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local found = {}
    if get then
        for _, id in ipairs(STEALTH_AURAS) do
            local ok, a = pcall(get, id)
            if ok and a then found[#found + 1] = id end
        end
    end
    print(P .. "auras de furtivite presentes : " .. (#found > 0 and table.concat(found, ", ") or "aucune"))
    print(P .. "etat suivi par les couleurs : " .. tostring(ns.Modules and ns.Modules.Colors and ns.Modules.Colors._stealthed))
end

-- Éléments colorables : clés internes + labels UI
Colors.ELEMENT_KEYS = {
    "powercircle", "powertext", "powerdotsa", "powerdotsb",
    "glow", "oochealth", "oocdot", "xpbar",
    "playerhealthbar", "playerdots", "pethealthbar", "petdots", "misc",
}

Colors.ELEMENT_LABELS = {
    powercircle     = L["COLORSMOD_ELEM_POWERCIRCLE"],
    powertext       = L["COLORSMOD_ELEM_POWERTEXT"],
    powerdotsa      = L["COLORSMOD_ELEM_POWERDOTSA"],
    powerdotsb      = L["COLORSMOD_ELEM_POWERDOTSB"],
    glow            = L["COLORSMOD_ELEM_GLOW"],
    oochealth       = L["COLORSMOD_ELEM_OOCHEALTH"],
    oocdot          = L["COLORSMOD_ELEM_OOCDOT"],
    xpbar           = L["COLORSMOD_ELEM_XPBAR"],
    playerhealthbar = L["COLORSMOD_ELEM_PLAYERHEALTHBAR"],
    playerdots      = L["COLORSMOD_ELEM_PLAYERDOTS"],
    pethealthbar    = L["COLORSMOD_ELEM_PETHEALTHBAR"],
    petdots         = L["COLORSMOD_ELEM_PETDOTS"],
    misc            = L["COLORSMOD_ELEM_MISC"],
}

-- Fallback absolu : couleur de classe (quand aucune donnée de spé)
Colors.CLASS_FALLBACK = {
    DEATHKNIGHT = { 0.769, 0.122, 0.231, 1 },
    DEMONHUNTER = { 0.639, 0.188, 0.788, 1 },
    DRUID       = { 1.000, 0.490, 0.039, 1 },
    EVOKER      = { 0.200, 0.578, 0.500, 1 },
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

-- Métadonnées classes / spés (noms FR, clés EN pour la DB)
Colors.CLASSES = {
    { key = "deathknight", file = "DEATHKNIGHT", name = L["COLORSMOD_CLASS_DEATHKNIGHT"],
      specs = { {id=250,name=L["COLORSMOD_SPEC_SANG"]}, {id=251,name=L["COLORSMOD_SPEC_GIVRE"]}, {id=252,name=L["COLORSMOD_SPEC_IMPIE"]} } },
    { key = "demonhunter", file = "DEMONHUNTER", name = L["COLORSMOD_CLASS_DEMONHUNTER"],
      specs = { {id=577,name=L["COLORSMOD_SPEC_HAVOC"]}, {id=581,name=L["COLORSMOD_SPEC_VENGEANCE"]},
                {id=1480,name=L["COLORSMOD_SPEC_DEVOREUR"]},
              } },
    { key = "druid", file = "DRUID", name = L["COLORSMOD_CLASS_DRUID"],
      specs = { {id=102,name=L["COLORSMOD_SPEC_EQUILIBRE"]}, {id=103,name=L["COLORSMOD_SPEC_FAROUCHE"]},
                {id=104,name=L["COLORSMOD_SPEC_GARDIEN"]},   {id=105,name=L["COLORSMOD_SPEC_RESTAURATION"]} } },
    { key = "evoker", file = "EVOKER", name = L["COLORSMOD_CLASS_EVOKER"],
      specs = { {id=1467,name=L["COLORSMOD_SPEC_DEVASTATION_EVOKER"]}, {id=1468,name=L["COLORSMOD_SPEC_PRESERVATION"]},
                {id=1473,name=L["COLORSMOD_SPEC_AUGMENTATION"]} } },
    { key = "hunter", file = "HUNTER", name = L["COLORSMOD_CLASS_HUNTER"],
      specs = { {id=253,name=L["COLORSMOD_SPEC_BM"]}, {id=254,name=L["COLORSMOD_SPEC_TIR"]},
                {id=255,name=L["COLORSMOD_SPEC_SURVIE"]} } },
    { key = "mage", file = "MAGE", name = L["COLORSMOD_CLASS_MAGE"],
      specs = { {id=62,name=L["COLORSMOD_SPEC_ARCANE"]}, {id=63,name=L["COLORSMOD_SPEC_FEU"]}, {id=64,name=L["COLORSMOD_SPEC_GIVRE"]} } },
    { key = "monk", file = "MONK", name = L["COLORSMOD_CLASS_MONK"],
      specs = { {id=268,name=L["COLORSMOD_SPEC_BREWMASTER"]}, {id=269,name=L["COLORSMOD_SPEC_WINDWALKER"]},
                {id=270,name=L["COLORSMOD_SPEC_MISTWEAVER"]} } },
    { key = "paladin", file = "PALADIN", name = L["COLORSMOD_CLASS_PALADIN"],
      specs = { {id=65,name=L["COLORSMOD_SPEC_SACRE"]}, {id=66,name=L["COLORSMOD_SPEC_PROTECTION"]}, {id=70,name=L["COLORSMOD_SPEC_VINDICTE"]} } },
    { key = "priest", file = "PRIEST", name = L["COLORSMOD_CLASS_PRIEST"],
      specs = { {id=256,name=L["COLORSMOD_SPEC_DISCIPLINE"]}, {id=257,name=L["COLORSMOD_SPEC_SACRE"]}, {id=258,name=L["COLORSMOD_SPEC_OMBRE"]} } },
    { key = "rogue", file = "ROGUE", name = L["COLORSMOD_CLASS_ROGUE"],
      specs = { {id=259,name=L["COLORSMOD_SPEC_ASSASSINAT"]}, {id=260,name=L[ns.IsForever and "COLORSMOD_SPEC_COMBAT" or "COLORSMOD_SPEC_OUTLAW"]},
                {id=261,name=L["COLORSMOD_SPEC_SUBTILITE"]} } },
    { key = "shaman", file = "SHAMAN", name = L["COLORSMOD_CLASS_SHAMAN"],
      specs = { {id=262,name=L["COLORSMOD_SPEC_ELEMENTAIRE"]}, {id=263,name=L["COLORSMOD_SPEC_AMELIORATION"]},
                {id=264,name=L["COLORSMOD_SPEC_RESTAURATION"]} } },
    { key = "warlock", file = "WARLOCK", name = L["COLORSMOD_CLASS_WARLOCK"],
      specs = { {id=265,name=L["COLORSMOD_SPEC_AFFLICTION"]}, {id=266,name=L["COLORSMOD_SPEC_DEMONOLOGIE"]},
                {id=267,name=L["COLORSMOD_SPEC_DESTRUCTION"]} } },
    { key = "warrior", file = "WARRIOR", name = L["COLORSMOD_CLASS_WARRIOR"],
      specs = { {id=71,name=L["COLORSMOD_SPEC_ARMES"]}, {id=72,name=L["COLORSMOD_SPEC_FUREUR"]}, {id=73,name=L["COLORSMOD_SPEC_PROTECTION"]} } },
}

-- Forever : ces classes n'existent pas, on les retire de la liste (et donc du GUI)
if ns.IsForever then
    local ABSENT = { EVOKER = true, DEMONHUNTER = true, MONK = true, DEATHKNIGHT = true }
    for i = #Colors.CLASSES, 1, -1 do
        if ABSENT[Colors.CLASSES[i].file] then table.remove(Colors.CLASSES, i) end
    end
end

-- Conditions : lignes de couleurs en plus des spes (pseudo-spe d'id texte), appliquees quand la condition est vraie.
-- Furtivite : Voleur et Druide. L'id sert de cle dans ns.DB.colors.overrides[classe][id].
Colors.STEALTH_ID = "stealth"
for _, c in ipairs(Colors.CLASSES) do
    if c.file == "ROGUE" or c.file == "DRUID" then
        c.conditions = { { id = Colors.STEALTH_ID, name = L["COLORSMOD_COND_STEALTH"] } }
    end
end

-- Palette violette par defaut de la condition Furtivite (modifiable element par element dans les options)
Colors.STEALTH_DEFAULTS = {
    powercircle     = { 0.58, 0.42, 0.86, 1 },
    powertext       = { 0.64, 0.52, 0.90, 1 },
    powerdotsa      = { 0.34, 0.24, 0.60, 1 },
    powerdotsb      = { 0.46, 0.32, 0.78, 1 },
    glow            = { 0.40, 0.28, 0.75, 1 },
    oochealth       = { 0.42, 0.30, 0.76, 1 },
    oocdot          = { 0.60, 0.50, 0.85, 1 },
    xpbar           = { 0.58, 0.45, 0.85, 1 },
    playerhealthbar = { 0.44, 0.30, 0.76, 1 },
    playerdots      = { 0.48, 0.36, 0.80, 1 },
    pethealthbar    = { 0.58, 0.45, 0.85, 1 },
    petdots         = { 0.60, 0.50, 0.86, 1 },
    misc            = { 0.32, 0.22, 0.58, 1 },
}

-- Index rapides
Colors._classFileMap = {}
Colors._classKeyMap  = {}
for _, c in ipairs(Colors.CLASSES) do
    Colors._classFileMap[c.file] = c
    Colors._classKeyMap[c.key]   = c
end

-- Couleurs par défaut par spécialisation, chargées depuis ns.DB.specDefaults au PLAYER_LOGIN
Colors.SPEC_DEFAULTS = {}

-- API publique

--- Couleur de l'élément pour le joueur actuel (spé courante).
--- Chaîne de priorité : override DB → défaut de spé → couleur de classe.
function Colors.Get(element)
    -- Cache ns._playerClass/ns._specID (CachePlayerSpec), fallback API directe si pas encore init
    local classFile = ns._playerClass
    if not classFile or classFile == "" then
        local _, cls = UnitClass("player")
        classFile = cls or ""
    end
    local classKey = classFile ~= "" and classFile:lower() or nil
    if ns.DB and ns.DB.colors and ns.DB.colors.useClassDefaults then
        return Colors.CLASS_FALLBACK[classFile] or { 1, 1, 1, 1 }
    end
    -- Condition Furtivite active (Voleur / Druide) : sa ligne de couleurs remplace celle de la spe
    if classKey and Colors.StealthConditionActive(classKey) then
        return Colors.GetForSpec(classKey, Colors.STEALTH_ID, element)
    end
    local specID = ns._specID
    if not specID then
        local idx = ns.GetSpecialization and ns.GetSpecialization() or nil
        specID = idx and ns.GetSpecializationInfo and select(1, ns.GetSpecializationInfo(idx)) or nil
    end
    -- Spe absente, ou inconnue de la table des couleurs (spe "initiale" d'un perso de bas niveau sur
    -- Retail, dont l'ID n'est celui d'aucune vraie spe) : on la traite comme "aucune spe".
    if specID and classKey then
        local cd = Colors._classKeyMap[classKey]
        local known = false
        for _, sp in ipairs(cd and cd.specs or {}) do
            if sp.id == specID then known = true; break end
        end
        if not known then specID = nil end
    end
    -- Aucune spe (perso sans spe, ou egalite entre arbres sur Forever) : spe par defaut choisie
    if not specID then specID = Colors.GetDefaultSpec(classKey) end
    return Colors.GetForSpec(classKey, specID, element)
end

--- Une condition est-elle activee (case a cocher de sa ligne) ? Activee par defaut.
function Colors.IsConditionEnabled(classKey, condID)
    local c = ns.DB and ns.DB.colors and ns.DB.colors.conditions
    local cls = c and classKey and c[classKey]
    return not (cls and cls[condID] == false)
end

function Colors.SetConditionEnabled(classKey, condID, val)
    if not ns.DB then ns.DB = {} end
    local col = ns.DB.colors
    if not col then col = {}; ns.DB.colors = col end
    col.conditions = col.conditions or {}
    col.conditions[classKey] = col.conditions[classKey] or {}
    col.conditions[classKey][condID] = val and true or false
    Colors.Broadcast()
end

--- Condition Furtivite : la classe en a une, elle est activee, et le joueur est en furtivite.
function Colors.StealthConditionActive(classKey)
    local cd = Colors._classKeyMap[classKey]
    if not (cd and cd.conditions) then return false end
    if not Colors.IsConditionEnabled(classKey, Colors.STEALTH_ID) then return false end
    return Colors._stealthed == true
end

--- Spe par defaut d'une classe (clic droit sur son nom dans les couleurs thematiques), ou nil.
--- Utilisee quand le joueur n'a aucune spe determinee.
function Colors.GetDefaultSpec(classKey)
    local d = ns.DB and ns.DB.colors and ns.DB.colors.defaultSpec
    return d and classKey and d[classKey] or nil
end

--- Definit (ou retire, si deja la spe par defaut) la spe par defaut d'une classe. Renvoie le nouvel etat.
function Colors.ToggleDefaultSpec(classKey, specID)
    if not ns.DB then ns.DB = {} end
    local col = ns.DB.colors
    if not col then col = {}; ns.DB.colors = col end
    col.defaultSpec = col.defaultSpec or {}
    local nowDefault
    if col.defaultSpec[classKey] == specID then
        col.defaultSpec[classKey] = nil
        nowDefault = false
    else
        col.defaultSpec[classKey] = specID
        nowDefault = true
    end
    -- Forever : la spe deduite des talents en depend (cf. Core.lua) -> recalcul + rejeu du changement de spe
    if ns.IsForever then
        if ns.InvalidateSpecCache then ns.InvalidateSpecCache() end
        if ns.FireSpecChanged then pcall(ns.FireSpecChanged) end
    end
    Colors.Broadcast()
    return nowDefault
end

--- Couleur pour une spé/classe précise (utilisé par l'UI des options).
function Colors.GetForSpec(classKey, specID, element)
    -- 1. Override utilisateur dans la DB
    local overrides = ns.DB and ns.DB.colors and ns.DB.colors.overrides
    if overrides and classKey and specID then
        local cov = overrides[classKey]
        if cov and cov[specID] and cov[specID][element] then
            return cov[specID][element]
        end
    end
    -- 2a. Condition Furtivite : palette violette par defaut
    if specID == Colors.STEALTH_ID then
        local d = Colors.STEALTH_DEFAULTS[element]
        if d then return d end
    end
    -- 2. Défaut de spé (table SPEC_DEFAULTS)
    if classKey and specID then
        local cdef = Colors.SPEC_DEFAULTS[classKey]
        if cdef and cdef[specID] and cdef[specID][element] then
            return cdef[specID][element]
        end
    end
    -- 3. Fallback couleur de classe
    local classData = classKey and Colors._classKeyMap[classKey]
    if classData then
        return Colors.CLASS_FALLBACK[classData.file] or { 1, 1, 1, 1 }
    end
    return { 1, 1, 1, 1 }
end

--- Sauvegarde une override utilisateur dans la DB.
function Colors.SetOverride(classKey, specID, element, color)
    if not ns.DB then ns.DB = {} end
    local col = ns.DB.colors
    if not col                      then col = {}; ns.DB.colors = col end
    if not col.overrides            then col.overrides = {} end
    if not col.overrides[classKey]  then col.overrides[classKey] = {} end
    if not col.overrides[classKey][specID] then col.overrides[classKey][specID] = {} end
    col.overrides[classKey][specID][element] = color
    Colors.Broadcast()
end

--- Supprime une override (revient au défaut de spé ou de classe).
function Colors.ResetOverride(classKey, specID, element)
    local overrides = ns.DB and ns.DB.colors and ns.DB.colors.overrides
    if overrides and overrides[classKey] and overrides[classKey][specID] then
        overrides[classKey][specID][element] = nil
    end
    Colors.Broadcast()
end

-- Système de callbacks (notifie les modules quand les couleurs changent)
Colors._callbacks = {}

function Colors.RegisterCallback(fn)
    table.insert(Colors._callbacks, fn)
end

function Colors.Broadcast()
    for _, fn in ipairs(Colors._callbacks) do
        pcall(fn)
    end
end

-- Alias pour compatibilité avec ApplyAllSettings() du système de profils
Colors.ApplySettings = Colors.Broadcast

-- Suivi de la furtivite : au changement d'etat, les modules relisent leurs couleurs (si la classe a la condition)
local _stealthEvt = CreateFrame("Frame")
_stealthEvt:RegisterEvent("UPDATE_STEALTH")
_stealthEvt:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
_stealthEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
_stealthEvt:RegisterUnitEvent("UNIT_AURA", "player")
-- Rattrapage Danse de l'ombre / Subterfuge (cf. SpellEffects) : leur entree ne declenche pas toujours UPDATE_STEALTH
_stealthEvt:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
_stealthEvt:SetScript("OnEvent", function()
    local cls = ns._playerClass
    if not cls or cls == "" then cls = select(2, UnitClass("player")) end
    local cd = cls and Colors._classFileMap[cls]
    if not (cd and cd.conditions) then return end   -- classe sans condition : rien a suivre
    local now, weak = ns.IsPlayerStealthed()
    if now == Colors._stealthed then return end
    if now and not weak then
        Colors._stealthed = true
        if Colors.IsConditionEnabled(cls:lower(), Colors.STEALTH_ID) then C_Timer.After(0, Colors.Broadcast) end
        return
    end
    if now then
        -- Entree en furtivite : confirmee apres un court delai. Sur monture, la barre d'action change un instant avant
        -- IsMounted() : l'etat "furtif" passait vrai puis faux quelques secondes plus tard. Une vraie furtivite tient.
        if Colors._stealthPending then return end
        Colors._stealthPending = true
        C_Timer.After(0.4, function()
            Colors._stealthPending = false
            if Colors._stealthed or not ns.IsPlayerStealthed() then return end
            Colors._stealthed = true
            if Colors.IsConditionEnabled(cls:lower(), Colors.STEALTH_ID) then Colors.Broadcast() end
        end)
        return
    end
    Colors._stealthed = false
    if Colors.IsConditionEnabled(cls:lower(), Colors.STEALTH_ID) then
        C_Timer.After(0, Colors.Broadcast)
    end
end)

-- Réagir aux changements de spécialisation
local _colEvt = CreateFrame("Frame")
ns.TrackSpecFrame(_colEvt)
_colEvt:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
_colEvt:RegisterEvent("PLAYER_LOGIN")
_colEvt:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.1, Colors.Broadcast)
        -- Le container "resourceCircle" du panneau d'options est cache pour la session,
        -- son contenu spec-dependant ne se remet pas a jour seul : invalider explicitement
        local SP = ns.SettingsPanel
        if SP and SP.InvalidateCategory then
            C_Timer.After(0.1, function() pcall(SP.InvalidateCategory, "resourceCircle") end)
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Merge des couleurs de spés depuis SavedVariables
        local sd = ns.DB and ns.DB.specDefaults
        if sd then
            for classKey, specs in pairs(sd) do
                if not Colors.SPEC_DEFAULTS[classKey] then
                    Colors.SPEC_DEFAULTS[classKey] = {}
                end
                for specID, elements in pairs(specs) do
                    Colors.SPEC_DEFAULTS[classKey][specID] = elements
                end
            end
        end
        -- Broadcast systematique : initialise Theme.gold/accent sur la bonne couleur de spe des le 1er affichage
        C_Timer.After(0.1, Colors.Broadcast)
    end
end)

-- Câblage : propagation du Broadcast vers les modules visuels (chacun relit Colors.Get())
Colors.RegisterCallback(function()
    local RC = ns.Modules.ResourceCircle
    if RC and RC.UpdateResourceColors  then pcall(RC.UpdateResourceColors)  end
    if RC and RC.UpdateSecDotColors    then pcall(RC.UpdateSecDotColors)    end

    local OCRC = ns.Modules.OutOfCombatResourceCircle
    if OCRC and OCRC.UpdateResourceColors then pcall(OCRC.UpdateResourceColors) end
    if OCRC and OCRC.UpdateSecDotColors   then pcall(OCRC.UpdateSecDotColors)   end

    local HC = ns.Modules.HealthCircle
    if HC and HC.ApplySettings then pcall(HC.ApplySettings) end

    local UB = ns.Modules.UnitBars
    if UB and UB.ApplySettings then pcall(UB.ApplySettings) end

    local XB = ns.Modules.XPBar
    if XB and XB.ApplySettings then pcall(XB.ApplySettings) end

    -- Niveau d'objet global et Nom du joueur (AFK) : toggle "Couleur de specialisation"
    local CA = ns.Modules.CharacterArmory
    if CA and CA.ApplySettings then pcall(CA.ApplySettings) end

    local AM = ns.Modules.AFKMode
    if AM and AM.ApplySettings then pcall(AM.ApplySettings) end

    -- Glow par defaut des auras trackees (stocke par spe) : re-applique + resync le menu Tactics
    local AurasNS = ns.Auras
    if AurasNS and AurasNS.RollDefaultGlow then pcall(AurasNS.RollDefaultGlow) end
    if AurasNS and AurasNS.RefreshDefaultGlowWidgets then pcall(AurasNS.RefreshDefaultGlowWidgets) end

    -- Fond colore du logo d'en-tete du panneau d'options
    local panel = ns.SettingsPanel or _G["AishCoreSettingsPanel"]
    if panel and panel.RefreshBrandLogo then pcall(panel.RefreshBrandLogo, panel) end

    -- Accent thematique du panneau d'options (Theme.gold/accent, ~60 accents dores)
    local SW = ns.SharedWidgets
    if SW and SW.RefreshAccentTheme then pcall(SW.RefreshAccentTheme) end

    -- Meme accent, namespace separe du module Auras (sinon headers figes en blanc)
    if AurasNS and AurasNS.RefreshAccentTheme then pcall(AurasNS.RefreshAccentTheme) end
end)

-- Rechargement de SPEC_DEFAULTS au changement de profil (sinon couleurs de l'ancien profil sans /reload)
ns.CallbackRegistry:Register("PROFILE_CHANGED", function()
    wipe(Colors.SPEC_DEFAULTS)
    local sd = ns.DB and ns.DB.specDefaults
    if sd then
        for classKey, specs in pairs(sd) do
            if not Colors.SPEC_DEFAULTS[classKey] then
                Colors.SPEC_DEFAULTS[classKey] = {}
            end
            for specID, elements in pairs(specs) do
                Colors.SPEC_DEFAULTS[classKey][specID] = elements
            end
        end
    end
    Colors.Broadcast()
end)

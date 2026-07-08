-- Modules/Colors.lua
-- Gestion centralisée des couleurs par spécialisation
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local Colors = {}
ns.Modules.Colors = Colors

---------------------------------------------------------------------------
-- Éléments colorables : clés internes + labels UI
---------------------------------------------------------------------------
Colors.ELEMENT_KEYS = {
    "powercircle", "powertext", "powerdotsa", "powerdotsb",
    "glow", "oochealth", "oocdot", "xpbar",
    "playerhealthbar", "playerdots", "pethealthbar", "petdots", "misc",
}

Colors.ELEMENT_LABELS = {
    powercircle     = "Power Circle",
    powertext       = "Power Text",
    powerdotsa      = "Power Dots A",
    powerdotsb      = "Power Dots B",
    glow            = "Glow",
    oochealth       = "OoC Health",
    oocdot          = "OoC Dot",
    xpbar           = "XP Bar",
    playerhealthbar = "Player HP",
    playerdots      = "Player Dots",
    pethealthbar    = "Pet HP",
    petdots         = "Pet Dots",
    misc            = "Misc",
}

---------------------------------------------------------------------------
-- Fallback absolu : couleur de classe (quand aucune donnée de spé)
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Métadonnées classes / spés (noms FR, clés EN pour la DB)
---------------------------------------------------------------------------
Colors.CLASSES = {
    { key = "deathknight", file = "DEATHKNIGHT", name = "Chevalier de la Mort",
      specs = { {id=250,name="Sang"}, {id=251,name="Givre"}, {id=252,name="Impie"} } },
    { key = "demonhunter", file = "DEMONHUNTER", name = "Chasseur de Démons",
      specs = { {id=577,name="Dévastation"}, {id=581,name="Vengeance"},
                {id=1480,name="Dévoreur"},
              } },
    { key = "druid", file = "DRUID", name = "Druide",
      specs = { {id=102,name="Équilibre"}, {id=103,name="Farouche"},
                {id=104,name="Gardien"},   {id=105,name="Restauration"} } },
    { key = "evoker", file = "EVOKER", name = "Évocateur",
      specs = { {id=1467,name="Dévastation"}, {id=1468,name="Préservation"},
                {id=1473,name="Augmentation"} } },
    { key = "hunter", file = "HUNTER", name = "Chasseur",
      specs = { {id=253,name="Maîtrise des bêtes"}, {id=254,name="Tir"},
                {id=255,name="Survie"} } },
    { key = "mage", file = "MAGE", name = "Mage",
      specs = { {id=62,name="Arcane"}, {id=63,name="Feu"}, {id=64,name="Givre"} } },
    { key = "monk", file = "MONK", name = "Moine",
      specs = { {id=268,name="Maître brasseur"}, {id=269,name="Marcheur du vent"},
                {id=270,name="Tisseur de brume"} } },
    { key = "paladin", file = "PALADIN", name = "Paladin",
      specs = { {id=65,name="Sacré"}, {id=66,name="Protection"}, {id=70,name="Vindicte"} } },
    { key = "priest", file = "PRIEST", name = "Prêtre",
      specs = { {id=256,name="Discipline"}, {id=257,name="Sacré"}, {id=258,name="Ombre"} } },
    { key = "rogue", file = "ROGUE", name = "Voleur",
      specs = { {id=259,name="Assassinat"}, {id=260,name="Hors-la-loi"},
                {id=261,name="Subtilité"} } },
    { key = "shaman", file = "SHAMAN", name = "Chaman",
      specs = { {id=262,name="Élémentaire"}, {id=263,name="Amélioration"},
                {id=264,name="Restauration"} } },
    { key = "warlock", file = "WARLOCK", name = "Démoniste",
      specs = { {id=265,name="Affliction"}, {id=266,name="Démonologie"},
                {id=267,name="Destruction"} } },
    { key = "warrior", file = "WARRIOR", name = "Guerrier",
      specs = { {id=71,name="Armes"}, {id=72,name="Fureur"}, {id=73,name="Protection"} } },
}

-- Index rapides
Colors._classFileMap = {}
Colors._classKeyMap  = {}
for _, c in ipairs(Colors.CLASSES) do
    Colors._classFileMap[c.file] = c
    Colors._classKeyMap[c.key]   = c
end

---------------------------------------------------------------------------
-- Couleurs par défaut par spécialisation
-- Source : COLOR MASTER - AISHUI (WeakAuras export)
-- Vide par défaut — chargé depuis ns.DB.specDefaults au PLAYER_LOGIN (version Adept)
-- Les utilisateurs standard auront le fallback couleur de classe.
---------------------------------------------------------------------------
Colors.SPEC_DEFAULTS = {}

---------------------------------------------------------------------------
-- API publique
---------------------------------------------------------------------------

--- Couleur de l'élément pour le joueur actuel (spé courante).
--- Chaîne de priorité : override DB → défaut de spé → couleur de classe.
function Colors.Get(element)
    -- Utilise le cache ns._playerClass / ns._specID (mis à jour par CachePlayerSpec
    -- au login et sur PLAYER_SPECIALIZATION_CHANGED). Fallback sur API directe si
    -- le cache n'est pas encore initialisé (appels avant PLAYER_ENTERING_WORLD).
    local classFile = ns._playerClass
    if not classFile or classFile == "" then
        local _, cls = UnitClass("player")
        classFile = cls or ""
    end
    local classKey = classFile ~= "" and classFile:lower() or nil
    if ns.DB and ns.DB.colors and ns.DB.colors.useClassDefaults then
        return Colors.CLASS_FALLBACK[classFile] or { 1, 1, 1, 1 }
    end
    local specID = ns._specID
    if not specID then
        local idx = GetSpecialization and GetSpecialization() or nil
        specID = idx and GetSpecializationInfo and select(1, GetSpecializationInfo(idx)) or nil
    end
    return Colors.GetForSpec(classKey, specID, element)
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

---------------------------------------------------------------------------
-- Système de callbacks (notifie les modules quand les couleurs changent)
---------------------------------------------------------------------------
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

---------------------------------------------------------------------------
-- Réagir aux changements de spécialisation
---------------------------------------------------------------------------
local _colEvt = CreateFrame("Frame")
_colEvt:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
_colEvt:RegisterEvent("PLAYER_LOGIN")
_colEvt:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.1, Colors.Broadcast)
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- Merge des couleurs de spés depuis SavedVariables (version Adept)
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
            C_Timer.After(0.1, Colors.Broadcast)
        end
    end
end)

---------------------------------------------------------------------------
-- Câblage : propagation du Broadcast vers les modules visuels
-- Chaque module lit Colors.Get() dans sa propre fonction de couleur ;
-- ici on déclenche le re-rendu quand les couleurs changent.
---------------------------------------------------------------------------
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
end)

---------------------------------------------------------------------------
-- Rechargement de SPEC_DEFAULTS lors d'un changement de profil.
-- Ce cache est peuplé une seule fois au PLAYER_LOGIN ; sans cette
-- resynchronisation, Colors.GetForSpec() retourne les couleurs de
-- l'ancien profil après un switch sans /reload.
---------------------------------------------------------------------------
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

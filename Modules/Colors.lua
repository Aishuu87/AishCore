-- Modules/Colors.lua
-- Gestion centralisée des couleurs par spécialisation
local addonName, ns = ...
local L = ns.L

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
      specs = { {id=259,name=L["COLORSMOD_SPEC_ASSASSINAT"]}, {id=260,name=L["COLORSMOD_SPEC_OUTLAW"]},
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

-- Index rapides
Colors._classFileMap = {}
Colors._classKeyMap  = {}
for _, c in ipairs(Colors.CLASSES) do
    Colors._classFileMap[c.file] = c
    Colors._classKeyMap[c.key]   = c
end

---------------------------------------------------------------------------
-- Couleurs par défaut par spécialisation
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
        -- Le container "resourceCircle" du panneau d'options est construit une
        -- fois puis mis en cache pour toute la session (cf. GetOrBuildContainer
        -- dans SettingsPanel.lua) : son contenu spec-dependant (_arcSpec, arc de
        -- stagger, dots secondaires...) lu au moment du build ne se remet donc
        -- JAMAIS a jour tout seul apres un changement de spe -- confirme en jeu
        -- (section d'arc manquante apres bascule vers une nouvelle spe). Scope
        -- volontairement narrow (uniquement sur le vrai changement de spe, pas
        -- le Broadcast generique declenche aussi par un simple edit de couleur,
        -- qui rebuildrait sinon tout l'onglet a chaque pick de couleur).
        local SP = ns.SettingsPanel
        if SP and SP.InvalidateCategory then
            C_Timer.After(0.1, function() pcall(SP.InvalidateCategory, "resourceCircle") end)
        end
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
        end
        -- Toujours Broadcast au login (meme sans specDefaults) : c'est ce qui
        -- initialise Theme.gold/Theme.accent (cf. SW.RefreshAccentTheme, appele
        -- depuis Colors.RegisterCallback ci-dessous) sur la bonne couleur de spe
        -- des le tout premier affichage du panneau d'options, au lieu de rester
        -- sur l'ocre statique jusqu'au premier changement de spe.
        C_Timer.After(0.1, Colors.Broadcast)
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

    -- Niveau d'objet global (Fiche Personnage) et Nom du joueur (Ecran AFK) :
    -- toggle "Couleur de specialisation" (Colors.Get("powercircle")) --
    -- doivent se reappliquer en direct au changement de spe/couleur, comme
    -- les autres consommateurs de Colors.Get ci-dessus.
    local CA = ns.Modules.CharacterArmory
    if CA and CA.ApplySettings then pcall(CA.ApplySettings) end

    local AM = ns.Modules.AFKMode
    if AM and AM.ApplySettings then pcall(AM.ApplySettings) end

    -- Glow par defaut des "Auras a tracker" (Modules/Auras) : type/anim/opacite/
    -- taille/couleur sont maintenant stockes par spe (ns.db.defaultGlowBySpec,
    -- cf. GetDefaultGlowCfg dans Tactics.lua) -- on re-applique aux sorts deja
    -- actifs (RollDefaultGlow ignore ceux avec un glow personnalise,
    -- _glowCustom=true) ET on resynchronise les controles du menu Tactics s'il
    -- est deja construit/affiche, sinon ils resteraient figes sur les valeurs
    -- de l'ancienne spe jusqu'au prochain re-Build.
    local AurasNS = ns.Auras
    if AurasNS and AurasNS.RollDefaultGlow then pcall(AurasNS.RollDefaultGlow) end
    if AurasNS and AurasNS.RefreshDefaultGlowWidgets then pcall(AurasNS.RefreshDefaultGlowWidgets) end

    -- Accent thematique du panneau d'options (points de section, hairlines,
    -- fond actif de la sidebar, et ~60 autres accents dores qui lisent tous
    -- Theme.gold/Theme.accent) : un seul point de mise a jour centralise --
    -- cf. SharedWidgets.RefreshAccentTheme pour le detail (mute Theme.gold/
    -- accent EN PLACE, gate par ns.DB.colors.themeGUI). Remplace les 2 appels
    -- separes RefreshSidebarColors/RefreshSectionHeaderColors d'avant (les
    -- deux sont maintenant inclus dedans).
    local SW = ns.SharedWidgets
    if SW and SW.RefreshAccentTheme then pcall(SW.RefreshAccentTheme) end

    -- Meme accent thematique, mais pour le namespace SEPARE du module Auras
    -- (_addon.Auras.THEME, jamais partage avec ns.Theme) -- cf.
    -- Modules/Auras/Core/ClassColors.lua:RefreshAccentTheme. Sans cet appel,
    -- les headers de section des menus Auras (Tactics/Render/...) restaient
    -- figes sur un blanc fixe (confirme en jeu).
    if AurasNS and AurasNS.RefreshAccentTheme then pcall(AurasNS.RefreshAccentTheme) end
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

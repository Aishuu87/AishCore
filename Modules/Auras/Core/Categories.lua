-- AishUIAura/Core/Categories.lua
-- ============================================================================
-- Structure hiérarchique du panneau unifié (préparation fusion AishUI).
--
-- 7 catégories × 24 sections.
--
-- Chaque section a :
--   • id       : identifiant unique stable (ne pas changer — sert aux SavedVariables)
--   • label    : nom affiché en FR
--   • source   : "AishUIAura" | "Aishaddon" | "mixed"
--   • builder  : nom de la fonction ns.SettingsPanel.BuildXxxMenu à appeler
--                (ou nil si section non encore branchée)
--   • tooltip  : (optionnel) texte de l'info-bulle "?"
--
-- Note : les "builder" pointant vers des menus Aishaddon sont nil pour l'instant,
-- un placeholder "À venir" sera affiché à la place.
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

ns.CATEGORIES = {
    ----------------------------------------------------------------------------
    -- 1. JOUEUR — tout ce qui parle du joueur
    ----------------------------------------------------------------------------
    {
        id = "joueur",
        label = "JOUEUR",
        sections = {
            { id = "unitBars",       label = "Cadres d'unités",        source = "Aishaddon",
              desc = "Les barres de vie et de ressource principales de ton personnage. Tu configures ici leur taille, position, texture et couleurs." },
            { id = "castBar",        label = "Ma barre d'incantation", source = "Aishaddon",
              desc = "La barre qui s'affiche quand tu lances un sort avec temps d'incantation. Position, taille et style des polices." },
            { id = "resourceCircle", label = "Cercle de ressource",    source = "Aishaddon",
              desc = "Le cercle principal autour de ton personnage qui affiche ta ressource (mana, rage, énergie...). Deux modes : un en combat et un hors combat." },
            { id = "healthCircle",   label = "Cercle de récup",        source = "Aishaddon",
              desc = "Le cercle de récupération qui s'affiche uniquement hors combat. Utilisé pour les buffs de soin, nourriture et régénération." },
        },
    },

    ----------------------------------------------------------------------------
    -- 2. CIBLE — tout ce qui parle de la cible
    ----------------------------------------------------------------------------
    {
        id = "cible",
        label = "CIBLE",
        sections = {
            { id = "topTargetBar",  label = "Cadre de cible",         source = "Aishaddon",
              desc = "La barre de vie et les auras visibles sur ta cible actuelle. Configure la barre principale et les auras séparément dans les onglets." },
            { id = "targetCastBar", label = "Incantation de la cible", source = "Aishaddon",
              desc = "La barre qui montre ce que ta cible est en train de lancer. Pratique pour interrompre au bon moment." },
        },
    },

    ----------------------------------------------------------------------------
    -- 3. MES SORTS — containers visuels AishUIAura
    ----------------------------------------------------------------------------
    {
        id = "mesSorts",
        label = "MES SORTS",
        sections = {
            { id = "spellsTracked",  label = "Auras à tracker",        source = "AishUIAura",
              builder = "BuildTacticsMenu",
              desc = "La liste centrale de tous les sorts que l'addon surveille. Ajoute des sorts ici puis assigne-les à un emplacement (Liste d'icônes, Barres libres, Icones...)." },
            { id = "debuffs",   label = "Liste d'icônes",   source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "iconlist",
              desc = "Rangée d'icônes (style aegis) avec barre de durée. Idéal pour les DoTs et auras sur la cible. Tu choisis les sorts à y afficher depuis « Auras à tracker ».",
              tooltip = "Rangée d'icônes avec barre de durée. Tu choisis les sorts depuis Auras à tracker." },
            { id = "buffs",     label = "Barres de cercle",     source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "freebars",
              desc = "Barres miroir de part et d'autre du cercle de ressource. Idéal pour les buffs actifs continus. Tu choisis les sorts à y afficher depuis « Auras à tracker ».",
              tooltip = "Barres miroir autour du cercle de ressource. Tu choisis les sorts depuis Auras à tracker." },
            { id = "procs",     label = "Icones",     source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "icons",
              desc = "Icônes compactes en grille ou ligne. Idéal pour les procs et effets courts. Tu choisis les sorts à y afficher depuis « Auras à tracker ».",
              tooltip = "Icônes compactes. Tu choisis les sorts depuis Auras à tracker." },
            { id = "cooldowns", label = "Barres libres", source = "AishUIAura",
              builder = "BuildRenderMenu", builderArg = "circlebars",
              desc = "Barres librement positionnables (side large). Idéal pour les cooldowns et effets longue durée. Tu choisis les sorts à y afficher depuis « Auras à tracker ».",
              tooltip = "Barres librement positionnables. Tu choisis les sorts depuis Auras à tracker." },
            { id = "trinkets",  label = "Trinkets",  source = "AishUIAura",
              builder = "BuildEquipmentMenu",
              desc = "Gestion de tes trinkets (bijoux) et raciales sur cooldown. Configuration par slot d'équipement.",
              tooltip = "Trinkets et raciales. Configuration par slot depuis ce menu." },
        },
    },

    ----------------------------------------------------------------------------
    -- 4. ROTATION — aide à la décision
    ----------------------------------------------------------------------------
    {
        id = "rotation",
        label = "ROTATION",
        sections = {
            { id = "priorityBar",    label = "Slots autour du cercle", source = "Aishaddon",
              desc = "Deux groupes de slots de part et d'autre du cercle de ressource. Chaque slot affiche automatiquement le sort up en priorité dans sa liste.",
              tooltip = "2 groupes de slots de part et d'autre du cercle de ressource. Chaque slot affiche automatiquement le sort up en priorité dans sa liste." },
            { id = "rotationHelper", label = "Aide à la rotation",     source = "Aishaddon",
              desc = "L'indicateur qui te suggère le prochain sort à lancer en fonction de ta spé et de tes ressources." },
        },
    },

    ----------------------------------------------------------------------------
    -- 5. Anims 3D — animations 3D
    ----------------------------------------------------------------------------
    {
        id = "effets3D",
        label = "Anims 3D",
        sections = {
            { id = "fxOnAura",     label = "Auras",              source = "AishUIAura",
              builder = "BuildEffectsMenu",
              desc = "Animations 3D qui se jouent sur tes auras (icône, barre, étincelle) lors d'un proc, d'un cast ou d'un événement de combat. Le menu interne te permet de configurer chaque vue (icône / barre / étincelle) par sort." },
            { id = "fxOnResource", label = "Cercle de ressource", source = "Aishaddon",
              desc = "Animations 3D qui se jouent sur le cercle de ressource quand tu lances un sort." },
            { id = "fxOnSecRes",   label = "Ressource secondaire", source = "Aishaddon",
              desc = "Effets 3D sur les points secondaires : combo points (Voleur, Feral), runes (DK), chi (Monk), Puissance Sacrée (Paladin), essences (Evoker), etc.",
              tooltip = "Effets 3D sur les points secondaires : combo points (Voleur, Feral), runes (DK), chi (Monk), Puissance Sacrée (Paladin), essences (Evoker), etc." },
            { id = "fxOnRecup",    label = "Cercle de récup",     source = "Aishaddon",
              desc = "Animations 3D qui tournent en boucle autour de ton Cercle de récup (hors combat). Disparaissent dès l'entrée en combat.",
              tooltip = "Animations 3D qui tournent en boucle autour de ton Cercle de récup (hors combat). Disparaissent dès l'entrée en combat." },
        },
    },

    ----------------------------------------------------------------------------
    -- 6. MONDE — exploration et progression
    ----------------------------------------------------------------------------
    {
        id = "horsCombat",
        label = "MONDE",
        sections = {
            { id = "xpBar",     label = "Barre d'expérience", source = "Aishaddon",
              desc = "La barre d'expérience customisée qui remplace la barre Blizzard. Affiche XP, réputation et honneur selon le contexte." },
            { id = "skyriding", label = "Skyriding",          source = "Aishaddon",
              desc = "Affichage spécifique quand tu es en vol dragon : vitesse, vigueur et indicateurs d'altitude." },
        },
    },

    ----------------------------------------------------------------------------
    -- 7. GÉNÉRAL — config globale
    ----------------------------------------------------------------------------
    {
        id = "general",
        label = "GÉNÉRAL",
        sections = {
            { id = "colors",   label = "Couleurs & thème", source = "mixed",
              desc = "Palette de couleurs globale de l'addon. Personnalise les teintes or, accent, arrière-plan et couleurs de classe." },
            { id = "preview",  label = "Aperçu",           source = "AishUIAura",
              builder = "BuildPreviewMenu",
              desc = "Active un mode aperçu en jeu qui simule des auras factices dans chaque emplacement pour voir le rendu sans attendre un vrai combat." },
            { id = "profiles", label = "Profils",          source = "mixed",
              builder = "BuildProfilesMenu",
              desc = "Enregistre, charge ou partage tes configs entre personnages. Un profil = tout le setup (positions, couleurs, sorts trackés)." },
        },
    },
}

-- Helper : retourne la catégorie par son id
function ns.GetCategory(id)
    for _, cat in ipairs(ns.CATEGORIES) do
        if cat.id == id then return cat end
    end
    return nil
end

-- Helper : retourne la section par (catId, sectionId)
function ns.GetSection(catId, sectionId)
    local cat = ns.GetCategory(catId)
    if not cat then return nil end
    for _, sec in ipairs(cat.sections) do
        if sec.id == sectionId then return sec end
    end
    return nil
end

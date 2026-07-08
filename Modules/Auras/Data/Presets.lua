-- AishUIAura/Data/Presets.lua
-- Presets par specialisation : configuration pre-etablie de sorts pour un nouvel
-- utilisateur. Chaque preset est un ENSEMBLE DE REGLES qui s'applique sur les
-- sorts DEJA DECOUVERTS par le Cooldown Manager de Blizzard — jamais de creation
-- de sorts, jamais de contournement du CDM, donc aucun risque de taint.
--
-- ARCHITECTURE :
--   - Le CDM Blizzard decouvre les sorts en jouant (inchange)
--   - Les sorts apparaissent dans ns.db.discoveredSpells[specKey]
--   - L'utilisateur applique un preset via Profiles menu
--   - Le preset cherche les sorts dans discoveredSpells par NOM (pas par spellID,
--     car les noms sont plus stables entre versions et supportent le multilingue)
--   - Chaque sort trouve recoit la configuration du preset (enabled, destinations,
--     priority, color, glow)
--   - Les sorts du preset non trouves sont ignores silencieusement (talent non pris,
--     sort pas encore decouvert, etc.)
--
-- FORMAT D'UN PRESET :
--   ns.Presets["DRUID_FERAL"] = {
--       label = "Druide Feral",        -- Affiche dans le dropdown
--       desc  = "Saignements + CDs",   -- Description courte sous le dropdown
--       rules = {
--           {
--               names = {"Griffure", "Rake"},  -- Noms possibles (FR, EN, alias)
--               source = "debuff",              -- "debuff" | "buff" | "enhancement"
--               priority = 1,                   -- 1 = plus haute priorite
--               destinations = { debuffs=true, cooldowns=false, procs=false },
--               color = {0.95, 0.35, 0.25},    -- optionnel
--               glow = false,                   -- optionnel, true pour gros CDs
--           },
--           -- ... autres regles
--       }
--   }
--
-- CLES DE SPEC : format "CLASS_SPEC" (majuscules), voir ns.SPEC_MAP dans Defaults.lua
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

ns.Presets = {}

------------------------------------------------------------------------
-- PRESETS PAR SPEC — a remplir au fil du temps, en testant chaque spec en jeu
--
-- Druide :
--   ns.Presets["DRUID_BALANCE"]  = { ... }  -- Equilibre
--   ns.Presets["DRUID_FERAL"]    = { ... }  -- Feral
--   ns.Presets["DRUID_GUARDIAN"] = { ... }  -- Gardien
--   ns.Presets["DRUID_RESTO"]    = { ... }  -- Restauration
--
-- Guerrier :
--   ns.Presets["WARRIOR_ARMS"]       = { ... }  -- Armes
--   ns.Presets["WARRIOR_FURY"]       = { ... }  -- Fureur
--   ns.Presets["WARRIOR_PROTECTION"] = { ... }  -- Protection
--
-- Voleur :
--   ns.Presets["ROGUE_ASSASSINATION"] = { ... }  -- Assassinat
--   ns.Presets["ROGUE_OUTLAW"]        = { ... }  -- Hors-la-loi
--   ns.Presets["ROGUE_SUBTLETY"]      = { ... }  -- Finesse
--
-- Chevalier de la mort :
--   ns.Presets["DEATHKNIGHT_BLOOD"]  = { ... }  -- Sang
--   ns.Presets["DEATHKNIGHT_FROST"]  = { ... }  -- Givre
--   ns.Presets["DEATHKNIGHT_UNHOLY"] = { ... }  -- Impie
--
-- Chasseur :
--   ns.Presets["HUNTER_BEASTMASTERY"] = { ... }  -- Maitrise animale
--   ns.Presets["HUNTER_MARKSMANSHIP"] = { ... }  -- Precision
--   ns.Presets["HUNTER_SURVIVAL"]     = { ... }  -- Survie
--
-- Mage :
--   ns.Presets["MAGE_ARCANE"] = { ... }  -- Arcane
--   ns.Presets["MAGE_FIRE"]   = { ... }  -- Feu
--   ns.Presets["MAGE_FROST"]  = { ... }  -- Givre
--
-- Paladin :
--   ns.Presets["PALADIN_HOLY"]        = { ... }  -- Sacre
--   ns.Presets["PALADIN_PROTECTION"]  = { ... }  -- Protection
--   ns.Presets["PALADIN_RETRIBUTION"] = { ... }  -- Vindicte
--
-- Demoniste :
--   ns.Presets["WARLOCK_AFFLICTION"]  = { ... }  -- Affliction
--   ns.Presets["WARLOCK_DEMONOLOGY"]  = { ... }  -- Demonologie
--   ns.Presets["WARLOCK_DESTRUCTION"] = { ... }  -- Destruction
--
-- Pretre :
--   ns.Presets["PRIEST_DISCIPLINE"] = { ... }  -- Discipline
--   ns.Presets["PRIEST_HOLY"]       = { ... }  -- Sacre
--   ns.Presets["PRIEST_SHADOW"]     = { ... }  -- Ombre
--
-- Chaman :
--   ns.Presets["SHAMAN_ELEMENTAL"]   = { ... }  -- Elementaire
--   ns.Presets["SHAMAN_ENHANCEMENT"] = { ... }  -- Amelioration
--   ns.Presets["SHAMAN_RESTORATION"] = { ... }  -- Restauration
--
-- Moine :
--   ns.Presets["MONK_BREWMASTER"] = { ... }  -- Maitre brasseur
--   ns.Presets["MONK_WINDWALKER"] = { ... }  -- Marche-vent
--   ns.Presets["MONK_MISTWEAVER"] = { ... }  -- Tisse-brume
--
-- Chasseur de demons :
--   ns.Presets["DEMONHUNTER_HAVOC"]     = { ... }  -- Devastation
--   ns.Presets["DEMONHUNTER_VENGEANCE"] = { ... }  -- Vengeance
--
-- Evocateur :
--   ns.Presets["EVOKER_DEVASTATION"]  = { ... }  -- Devastation
--   ns.Presets["EVOKER_PRESERVATION"] = { ... }  -- Preservation
--   ns.Presets["EVOKER_AUGMENTATION"] = { ... }  -- Augmentation
------------------------------------------------------------------------


------------------------------------------------------------------------
-- API PUBLIQUE
------------------------------------------------------------------------

-- Retourne la liste des presets disponibles pour la SPEC ACTIVE du joueur.
-- Un seul preset max par spec, filtre strictement sur la spec active (pas la classe).
-- Quand le joueur change de spec, la liste change automatiquement.
--
-- Returns: table { { key, label, desc }, ... } — souvent 0 ou 1 element
function ns.GetAvailablePresets()
    local list = {}
    local specKey = nil
    pcall(function()
        local gS = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
        local gI = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
        if gS and gI then
            local specID = gI(gS())
            local m = specID and ns.SPEC_MAP and ns.SPEC_MAP[specID]
            if m then specKey = m.class .. "_" .. m.spec end
        end
    end)
    if not specKey then return list end
    local preset = ns.Presets[specKey]
    if preset then
        list[#list+1] = { key=specKey, label=preset.label, desc=preset.desc }
    end
    return list
end

-- Applique un preset aux sorts deja decouverts dans la spec active.
-- Ne CREE aucun sort. Ne TOUCHE pas aux sorts deja configures par l'utilisateur
-- si mode = "merge". En mode "replace", reset la config des sorts non-equipment.
--
-- Matching : par NOM de sort (info.name), en testant tous les alias de chaque regle.
-- Les sorts du preset non trouves dans discoveredSpells sont ignores silencieusement.
--
-- Arguments:
--   presetKey : string, clef au format "CLASS_SPEC"
--   mode      : "merge" (garde config existante) | "replace" (ecrase non-equipment)
--
-- Returns: (applied_count, error_msg, skipped_names)
--   applied_count : nombre de sorts configures
--   error_msg     : string si erreur, nil sinon
--   skipped_names : table des noms du preset non trouves (pour feedback UX)
function ns.ApplyPreset(presetKey, mode)
    local preset = ns.Presets[presetKey]
    if not preset then return 0, string.format(L["AURASDATA_PRESET_ERR_NOT_FOUND"], tostring(presetKey)), {} end

    local spells, specKey = ns.GetSpecSpells()
    if not spells then return 0, L["AURASDATA_PRESET_ERR_NO_SPEC"], {} end

    mode = mode or "merge"

    -- Mode replace : desactive tous les sorts sauf equipment (source via Providers)
    -- On garde les sorts en DB pour ne pas perdre la decouverte CDM ; l'utilisateur
    -- peut toujours les recocher manuellement dans Tactics si besoin.
    if mode == "replace" then
        for sid, si in pairs(spells) do
            if si.source ~= "equipment" then
                si.enabled = false
            end
        end
    end

    local applied = 0
    local skippedNames = {}

    for _, rule in ipairs(preset.rules or {}) do
        local matched = false
        -- Teste chaque nom alias de la regle jusqu'a trouver un match
        for _, presetName in ipairs(rule.names or {}) do
            local lower = presetName:lower()
            for sid, info in pairs(spells) do
                if info.name and info.name:lower() == lower then
                    -- Match trouve : applique la config
                    info.enabled = true
                    if rule.source then info.source = rule.source end
                    if rule.priority then info.priority = rule.priority end
                    if rule.destinations then
                        info.destinations = ns.DeepCopy and ns.DeepCopy(rule.destinations) or rule.destinations
                    end
                    if rule.color then
                        info.color = ns.DeepCopy and ns.DeepCopy(rule.color) or rule.color
                    end
                    if rule.glow ~= nil then info.glow = rule.glow end
                    if rule.glowIdx then info.glowIdx = rule.glowIdx end
                    applied = applied + 1
                    matched = true
                    break
                end
            end
            if matched then break end
        end
        if not matched then
            skippedNames[#skippedNames+1] = (rule.names and rule.names[1]) or "?"
        end
    end

    -- Rebuild whitelist et re-scan pour refleter les changements immediatement
    if ns.BuildWhitelist then ns.BuildWhitelist() end
    if ns.ScanAuras then ns.ScanAuras() end


    return applied, nil, skippedNames
end

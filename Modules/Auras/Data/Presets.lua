-- Presets.lua : config pre-etablie de sorts par spec, appliquee aux sorts deja decouverts par le CDM Blizzard
-- Format : ns.Presets["CLASS_SPEC"] = { label, desc, rules = { {names, source, priority, destinations, color, glow}, ... } }
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

ns.Presets = {}
-- Presets par spec a remplir au fil du temps (une entree par CLASS_SPEC)

-- Liste des presets pour la spec active (1 max par spec, filtre sur la spec pas la classe)
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

-- Applique un preset aux sorts deja decouverts (matching par nom, alias). mode: "merge" | "replace"
-- Returns: applied_count, error_msg, skipped_names
function ns.ApplyPreset(presetKey, mode)
    local preset = ns.Presets[presetKey]
    if not preset then return 0, string.format(L["AURASDATA_PRESET_ERR_NOT_FOUND"], tostring(presetKey)), {} end

    local spells, specKey = ns.GetSpecSpells()
    if not spells then return 0, L["AURASDATA_PRESET_ERR_NO_SPEC"], {} end

    mode = mode or "merge"

    -- Mode replace : desactive tous les sorts sauf equipment, sans perdre la decouverte CDM
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

-- AishUIAura/UI/Menus/MissingBuffs.lua
-- Ecran de reglages "Buffs manquants" : onglet General + une section par classe (buffs de groupe)
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

local function Cfg()
    return ns.MissingBuffs and ns.MissingBuffs.Cfg() or {}
end

-- Ligne "buff a ignorer" : case a cocher (coche = trace) + icone + nom
local function CreateBuffRow(parent, entry, y, W)
    local Theme = ns.THEME
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(W, 24)
    row:SetPoint("TOPLEFT", 0, -y)

    local box = row:CreateTexture(nil, "ARTWORK")
    box:SetSize(12, 12); box:SetPoint("LEFT", 4, 0)

    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(10, 10); check:SetPoint("CENTER", box)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18); icon:SetPoint("LEFT", box, "RIGHT", 6, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    pcall(function()
        local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellId)
        if t then icon:SetTexture(t) end
    end)

    local label = row:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(label, ns.Media.font, 11)
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(Theme.textNormal))
    local name = "?" .. tostring(entry.spellId)
    pcall(function()
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.spellId)
        if n then name = n end
    end)
    label:SetText(name)

    local function Refresh()
        local ignored = ns.MissingBuffs.IsIgnored(entry.settingsId)
        box:SetColorTexture(unpack(ignored and Theme.checkboxOff or Theme.checkboxOn))
        check:SetShown(not ignored)
    end
    Refresh()
    row:SetScript("OnClick", function()
        ns.MissingBuffs.SetIgnored(entry.settingsId, not ns.MissingBuffs.IsIgnored(entry.settingsId))
        Refresh()
    end)
    row:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1) end)
    row:SetScript("OnLeave", function() label:SetTextColor(unpack(Theme.textNormal)) end)
    return row
end

-- Case a cocher generique liee a une cle de ns.db.missingBuffs
local function AddDbCheckbox(sub, y, W, label, key, invert)
    local SW = ns.SharedWidgets
    local cb = SW.CreateCheckbox(sub, label, W)
    cb:SetPoint("TOPLEFT", 0, -y)
    local cfg = Cfg()
    local v = cfg[key] and true or false
    cb:SetChecked(invert and not v or v)
    cb.onChanged = function(checked)
        local c = Cfg()
        c[key] = invert and (not checked) or checked
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end
    return cb, y + 26
end

-- Sections par classe : buffs de groupe + toggles specifiques (stances/auras/attunements/pets/poisons)
local function BuildGenericClassSection(entries)
    return function(sub, W)
        local y = 0
        for _, entry in ipairs(entries) do
            CreateBuffRow(sub, entry, y, W)
            y = y + 24
        end
        sub:SetHeight(math.max(y, 1))
    end
end

local function BuildWarriorSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_STANCES"] or "Ignorer les postures", "ignoreWarriorStances")
    y = y2
    for _, entry in ipairs(ns.MISSING_CLASS_BUFFS.WARRIOR) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildPaladinSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_AURAS"] or "Ignorer les auras", "ignorePaladinAuras")
    y = y2
    for _, entry in ipairs(ns.MISSING_CLASS_BUFFS.PALADIN) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildEvokerSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_ATTUNEMENTS"] or "Ignorer les accords", "ignoreEvokerAttunements")
    y = y2
    for _, entry in ipairs(ns.MISSING_CLASS_BUFFS.EVOKER) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildHunterSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_PET"] or "Ignorer le familier", "ignoreHunterPets")
    y = y2
    sub:SetHeight(math.max(y, 1))
end

local function BuildWarlockSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_PET"] or "Ignorer le familier", "ignoreWarlockPets")
    y = y2

    -- Cas special "presence" (inverse) : resynchronise SpellEffects immediatement au clic
    local SW = ns.SharedWidgets
    local cbBurningRush = SW.CreateCheckbox(sub, L["MISSINGBUFFS_BURNING_RUSH_ALERT"] or "Alerte Ruée Ardente", W)
    cbBurningRush:SetPoint("TOPLEFT", 0, -y)
    cbBurningRush:SetChecked(Cfg().burningRushAlert and true or false)
    cbBurningRush.onChanged = function(checked)
        Cfg().burningRushAlert = checked
        -- Epingle au CDM : sans ca, la detection retombe sur GetPlayerAuraBySpellID (nil en combat)
        if checked and ns.PinAuraToCDM and ns.MISSING_WARLOCK_BURNING_RUSH then
            local ok = ns.PinAuraToCDM(ns.MISSING_WARLOCK_BURNING_RUSH, true)
            if not ok then ns.PinAuraToCDM(ns.MISSING_WARLOCK_BURNING_RUSH, false) end
        end
        -- Ancre le combo tout de suite : action protegee, impossible en combat
        if checked and ns.MissingBuffs and ns.MissingBuffs.PrepareBurningRushAnchor then
            ns.MissingBuffs.PrepareBurningRushAnchor()
        end
        if ns.MissingBuffs and ns.MissingBuffs.SyncBurningRush then ns.MissingBuffs.SyncBurningRush() end
    end
    y = y + 26

    for _, entry in ipairs(ns.MISSING_CLASS_BUFFS.WARLOCK) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildDruidSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_FORMS"] or "Ignorer le changement de forme", "ignoreDruidForms")
    y = y2
    for _, entry in ipairs(ns.MISSING_CLASS_BUFFS.DRUID) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildRogueSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_LETHAL"] or "Ignorer les poisons letaux", "ignoreLethalPoisons")
    y = y2
    local _, y3 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_NONLETHAL"] or "Ignorer les poisons non-letaux", "ignoreNonlethalPoisons")
    y = y3
    sub:SetHeight(math.max(y, 1))
end

-- Ordre d'affichage des classes + leur builder de section
local CLASS_SECTIONS = {
    { class = "WARRIOR", build = BuildWarriorSection },
    { class = "PALADIN", build = BuildPaladinSection },
    { class = "HUNTER",  build = BuildHunterSection },
    { class = "ROGUE",   build = BuildRogueSection },
    { class = "PRIEST",  build = BuildGenericClassSection(ns.MISSING_CLASS_BUFFS.PRIEST) },
    { class = "SHAMAN",  build = BuildGenericClassSection(ns.MISSING_CLASS_BUFFS.SHAMAN) },
    { class = "MAGE",    build = BuildGenericClassSection(ns.MISSING_CLASS_BUFFS.MAGE) },
    { class = "WARLOCK", build = BuildWarlockSection },
    { class = "DRUID",   build = BuildDruidSection },
    { class = "EVOKER",  build = BuildEvokerSection },
}

local function ClassLabel(token)
    local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token]
    return name or token
end

-- Builder principal
function ns.SettingsPanel.BuildMissingBuffsMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME

    local hdr = SW.CreateSectionHeader(p, L["MISSINGBUFFS_HEADER"] or "Buffs manquants", cw - 20)
    hdr:SetPoint("TOPLEFT", 10, 0)

    local y = -30
    local cfg = Cfg()

    local cbEnable = SW.CreateCheckbox(p, L["MISSINGBUFFS_ENABLE"] or "Activer", cw - 30)
    cbEnable:SetPoint("TOPLEFT", 15, y)
    cbEnable:SetChecked(cfg.enabled and true or false)
    cbEnable.onChanged = function(v)
        Cfg().enabled = v
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
        -- Reflete l'etat sur la ligne miroir de la page "Modules"
        if ns.SettingsPanel and ns.SettingsPanel.InvalidateCategory then
            ns.SettingsPanel.InvalidateCategory("modulesOverview")
        end
    end
    y = y - 26

    local cbClick = SW.CreateCheckbox(p, L["MISSINGBUFFS_CLICKABLE"] or "Icone cliquable (lance le sort manquant)", cw - 30)
    cbClick:SetPoint("TOPLEFT", 15, y)
    cbClick:SetChecked(cfg.makeIconClickable and true or false)
    cbClick.onChanged = function(v) Cfg().makeIconClickable = v end
    y = y - 26

    local cbMount = SW.CreateCheckbox(p, L["MISSINGBUFFS_IGNORE_MOUNTED"] or "Ignorer si monte", cw - 30)
    cbMount:SetPoint("TOPLEFT", 15, y)
    cbMount:SetChecked(cfg.ignoreBuffsWhileMounted and true or false)
    cbMount.onChanged = function(v)
        Cfg().ignoreBuffsWhileMounted = v
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end
    y = y - 26

    local cbResting = SW.CreateCheckbox(p, L["MISSINGBUFFS_IGNORE_RESTING"] or "Ignorer en zone de repos", cw - 30)
    cbResting:SetPoint("TOPLEFT", 15, y)
    cbResting:SetChecked(cfg.ignoreWhileResting and true or false)
    cbResting.onChanged = function(v)
        Cfg().ignoreWhileResting = v
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end
    y = y - 26

    local cbHideText = SW.CreateCheckbox(p, L["MISSINGBUFFS_HIDE_TEXT"] or "Cacher le texte sous l'icone", cw - 30)
    cbHideText:SetPoint("TOPLEFT", 15, y)
    cbHideText:SetChecked(cfg.hideText and true or false)
    cbHideText.onChanged = function(v) Cfg().hideText = v end
    y = y - 26

    local cbLock = SW.CreateCheckbox(p, L["MISSINGBUFFS_LOCK"] or "Verrouiller la position (empeche le glisser-deposer)", cw - 30)
    cbLock:SetPoint("TOPLEFT", 15, y)
    cbLock:SetChecked(cfg.locked and true or false)
    cbLock.onChanged = function(v) Cfg().locked = v end
    y = y - 34

    local slider = SW.CreateSlider(p, L["MISSINGBUFFS_THROTTLE"] or "Delai entre 2 verifications (s)", 0.1, 2.0, 0.05, cw - 30)
    slider:SetPoint("TOPLEFT", 15, y)
    slider:SetValue(cfg.debounceThrottle or 0.25)
    slider.onChanged = function(v) Cfg().debounceThrottle = v end
    y = y - 62

    -- Rappel "bientot expire" : desactive par defaut, seuil en minutes (converti en secondes a l'usage)
    local cbExpiring = SW.CreateCheckbox(p, L["MISSINGBUFFS_EXPIRING_ENABLE"] or "Rappel avant expiration", cw - 30)
    cbExpiring:SetPoint("TOPLEFT", 15, y)
    cbExpiring:SetChecked(cfg.expiringSoonEnabled and true or false)
    cbExpiring.onChanged = function(v)
        Cfg().expiringSoonEnabled = v
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end
    y = y - 26

    local slExpiring = SW.CreateSlider(p, L["MISSINGBUFFS_EXPIRING_THRESHOLD"] or "Afficher le rappel quand il reste moins de (minutes)", 1, 30, 1, cw - 30)
    slExpiring:SetPoint("TOPLEFT", 15, y)
    slExpiring:SetValue(cfg.expiringSoonThreshold or 5)
    slExpiring.onChanged = function(v)
        Cfg().expiringSoonThreshold = v
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end
    y = y - 62

    -- Apparence icone : taille / bordure / masque de forme. Chaque onChanged rafraichit en direct.
    local function Refresh()
        if ns.MissingBuffs then ns.MissingBuffs.RefreshAppearance() end
    end

    local hdrIcon = SW.CreateSectionHeader(p, L["MISSINGBUFFS_ICON_HEADER"] or "Apparence de l'icone", cw - 20)
    hdrIcon:SetPoint("TOPLEFT", 10, y)
    y = y - 30

    local slIconSize = SW.CreateSlider(p, L["MISSINGBUFFS_ICON_SIZE"] or "Taille de l'icone", 32, 128, 1, cw - 30)
    slIconSize:SetPoint("TOPLEFT", 15, y)
    slIconSize:SetValue(cfg.iconSize or 64)
    slIconSize.onChanged = function(v) Cfg().iconSize = v; Refresh() end
    y = y - 62

    local cbBorder = SW.CreateCheckbox(p, L["MISSINGBUFFS_BORDER_ENABLE"] or "Bordure", cw - 30)
    cbBorder:SetPoint("TOPLEFT", 15, y)
    cbBorder:SetChecked(cfg.borderEnabled ~= false)
    cbBorder.onChanged = function(v) Cfg().borderEnabled = v; Refresh() end
    y = y - 26

    local colBorder = SW.CreateColorButton(p, L["MISSINGBUFFS_BORDER_COLOR"] or "Couleur de bordure", cw - 30)
    colBorder:SetPoint("TOPLEFT", 15, y)
    colBorder:SetColor(unpack(cfg.borderColor or { 1, 0.15, 0.15, 0.9 }))
    colBorder.onChanged = function(rgb)
        local c = Cfg()
        local a = (c.borderColor and c.borderColor[4]) or 0.9
        c.borderColor = { rgb[1], rgb[2], rgb[3], a }
        Refresh()
    end
    y = y - 30

    local slBorderThick = SW.CreateSlider(p, L["MISSINGBUFFS_BORDER_THICKNESS"] or "Epaisseur de bordure", 1, 6, 1, cw - 30)
    slBorderThick:SetPoint("TOPLEFT", 15, y)
    slBorderThick:SetValue(cfg.borderThickness or 2)
    slBorderThick.onChanged = function(v) Cfg().borderThickness = v; Refresh() end
    y = y - 62

    local ddMask = SW.CreateDropdown(p, L["MISSINGBUFFS_ICON_SHAPE"] or "Forme", ns.MISSING_BUFF_ICON_MASKS, cw - 30)
    ddMask:SetPoint("TOPLEFT", 15, y)
    ddMask:SetValue(cfg.iconMaskIndex or 1)
    ddMask.onChanged = function(v) Cfg().iconMaskIndex = v; Refresh() end
    y = y - 48

    -- Apparence texte : police / taille / couleur / position / animation
    local hdrText = SW.CreateSectionHeader(p, L["MISSINGBUFFS_TEXT_HEADER"] or "Apparence du texte", cw - 20)
    hdrText:SetPoint("TOPLEFT", 10, y)
    y = y - 30

    local ddFont = SW.CreateDropdown(p, L["MISSINGBUFFS_TEXT_FONT"] or "Police", _addon.GetFontList(), cw - 30)
    ddFont:SetPoint("TOPLEFT", 15, y)
    ddFont:SetValue(cfg.textFont or ns.Media.font)
    ddFont.onChanged = function(v) Cfg().textFont = v; Refresh() end
    y = y - 48

    local slTextSize = SW.CreateSlider(p, L["MISSINGBUFFS_TEXT_SIZE"] or "Taille du texte", 8, 24, 1, cw - 30)
    slTextSize:SetPoint("TOPLEFT", 15, y)
    slTextSize:SetValue(cfg.textSize or 12)
    slTextSize.onChanged = function(v) Cfg().textSize = v; Refresh() end
    y = y - 62

    local colText = SW.CreateColorButton(p, L["MISSINGBUFFS_TEXT_COLOR"] or "Couleur du texte", cw - 30)
    colText:SetPoint("TOPLEFT", 15, y)
    colText:SetColor(unpack(cfg.textColor or { 1, 0.9, 0.3 }))
    colText.onChanged = function(rgb) Cfg().textColor = { rgb[1], rgb[2], rgb[3] }; Refresh() end
    y = y - 30

    local halfW = math.floor((cw - 30 - 8) / 2)
    local slOffX = SW.CreateSlider(p, L["SETTINGS_OFFSET_X"] or "Decalage X", -50, 50, 1, halfW)
    slOffX:SetPoint("TOPLEFT", 15, y)
    slOffX:SetValue(cfg.textOffsetX or 0)
    slOffX.onChanged = function(v) Cfg().textOffsetX = v; Refresh() end
    local slOffY = SW.CreateSlider(p, L["SETTINGS_OFFSET_Y"] or "Decalage Y", -50, 50, 1, halfW)
    slOffY:SetPoint("TOPLEFT", 15 + halfW + 8, y)
    slOffY:SetValue(cfg.textOffsetY or -2)
    slOffY.onChanged = function(v) Cfg().textOffsetY = v; Refresh() end
    y = y - 62

    -- Toggles combinables (pas un dropdown exclusif), sur 3 colonnes
    local w3 = math.floor((cw - 30 - 16) / 3)
    local cbPulse = SW.CreateCheckbox(p, L["MISSINGBUFFS_TEXT_ANIM_PULSE"] or "Pulsation", w3)
    cbPulse:SetPoint("TOPLEFT", 15, y)
    cbPulse:SetChecked(cfg.textAnimPulse and true or false)
    cbPulse.onChanged = function(v) Cfg().textAnimPulse = v; Refresh() end

    local cbBounce = SW.CreateCheckbox(p, L["MISSINGBUFFS_TEXT_ANIM_BOUNCE"] or "Rebond", w3)
    cbBounce:SetPoint("TOPLEFT", 15 + w3 + 8, y)
    cbBounce:SetChecked(cfg.textAnimBounce and true or false)
    cbBounce.onChanged = function(v) Cfg().textAnimBounce = v; Refresh() end

    local cbBlink = SW.CreateCheckbox(p, L["MISSINGBUFFS_TEXT_ANIM_BLINK"] or "Clignotement", w3)
    cbBlink:SetPoint("TOPLEFT", 15 + (w3 + 8) * 2, y)
    cbBlink:SetChecked(cfg.textAnimBlink and true or false)
    cbBlink.onChanged = function(v) Cfg().textAnimBlink = v; Refresh() end
    y = y - 26

    local ddOutline = SW.CreateDropdown(p, L["SETTINGS_TEXT_OUTLINE"] or "Contour", ns.GetTextOutlineStyles(), cw - 30)
    ddOutline:SetPoint("TOPLEFT", 15, y)
    ddOutline:SetValue(cfg.textOutlineStyle or "OUTLINE")
    ddOutline.onChanged = function(v) Cfg().textOutlineStyle = v; Refresh() end
    y = y - 48

    local sections = {}
    for _, cs in ipairs(CLASS_SECTIONS) do
        sections[#sections + 1] = { name = ClassLabel(cs.class), build = cs.build }
    end
    SW.CreateSectionStack(p, sections, cw, -y)

    return p
end

-- AishUIAura/UI/Menus/MissingBuffs.lua
-- Ecran de reglages "Buffs manquants" : onglet General + une section par classe (buffs de groupe)
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

local function Cfg()
    return ns.MissingBuffs and ns.MissingBuffs.Cfg() or {}
end

-- Libelle d'une entree Forever (sans spellID fixe) : noms de sort localises, lus depuis les spellIDs
-- de "casts" (valables meme pour un sort pas encore appris). Au plus 3 noms, separes par " / ".
local function ForeverEntryLabel(entry)
    if entry.kind == "item" then return L["MISSINGBUFFS_ENTRY_SHARDS"] or entry.displayName end
    if entry.kind == "ammo" then return L["MISSINGBUFFS_ENTRY_AMMO"] or entry.displayName end
    local out, seen = {}, {}
    for _, v in ipairs(entry.casts or {}) do
        if type(v) == "number" and #out < 3 then
            local ok, n = pcall(C_Spell.GetSpellName, v)
            if ok and n and not seen[n] then seen[n] = true; out[#out + 1] = n end
        end
    end
    if #out == 0 then
        if entry.displayName then return entry.displayName end
        for _, v in ipairs(entry.casts or {}) do if type(v) == "string" then return v end end
        return nil
    end
    local label = table.concat(out, " / ")
    if entry.weaponEnchantSlot == "off" then
        label = label .. " (" .. (L["MISSINGBUFFS_OFFHAND"] or "off-hand") .. ")"
    end
    return label
end

-- Forever : une entree dont AUCUN sort n'existe sur ce client (ID inconnu, ex. Aura de croise) n'a rien
-- a faire dans les options.
local function Existing(list)
    if not _addon.IsForever then return list or {} end
    local out = {}
    for _, e in ipairs(list or {}) do
        local ok = (not e.casts) or #e.casts == 0
        for _, v in ipairs(e.casts or {}) do
            if type(v) ~= "number" then ok = true; break end
            local good, n = pcall(C_Spell.GetSpellName, v)
            if good and n then ok = true; break end
        end
        if ok then out[#out + 1] = e end
    end
    return out
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
    if entry.icon then icon:SetTexture(entry.icon) end  -- Forever : entree sans spellID fixe
    pcall(function()
        local t = entry.spellId and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spellId)
        if t then icon:SetTexture(t) end
    end)

    local label = row:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(label, ns.Media.font, 11)
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(Theme.textNormal))
    local name = entry.displayName or ("?" .. tostring(entry.spellId))
    pcall(function()
        local n = entry.spellId and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.spellId)
        if n then name = n end
    end)
    if entry.casts or entry.kind then name = ForeverEntryLabel(entry) or name end
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

-- Curseur de seuil (Forever : fragments d'ame / munitions), stocke dans ns.db.missingBuffs[key]
local function AddThresholdSlider(sub, y, W, label, key, minV, maxV, step, default)
    local SW = ns.SharedWidgets
    local sl = SW.CreateSlider(sub, label, minV, maxV, step, W - 20)
    sl:SetPoint("TOPLEFT", 0, -y)
    sl:SetValue(Cfg()[key] or default)
    sl.onChanged = function(v)
        Cfg()[key] = v
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end
    return y + 56
end

-- Sections par classe : buffs de groupe + toggles specifiques (stances/auras/attunements/pets/poisons)
local function BuildGenericClassSection(entries)
    return function(sub, W)
        local y = 0
        for _, entry in ipairs(Existing(entries)) do
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
    for _, entry in ipairs(Existing(ns.MISSING_CLASS_BUFFS.PALADIN)) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    -- Forever : une ligne par aura proposable (decochee = jamais proposee, mais compte comme active)
    if _addon.IsForever then
        for _, entry in ipairs(Existing(ns.MISSING_PALADIN_AURAS)) do
            if entry.settingsId then CreateBuffRow(sub, entry, y, W); y = y + 24 end
        end
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
    for _, entry in ipairs(Existing(ns.MISSING_CLASS_BUFFS.HUNTER)) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    if _addon.IsForever then
        y = AddThresholdSlider(sub, y + 6, W, L["MISSINGBUFFS_AMMO_THRESHOLD"] or "Ammo alert threshold",
            "ammoThreshold", 20, 1000, 20, 200)
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildWarlockSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_PET"] or "Ignorer le familier", "ignoreWarlockPets")
    y = y2
    if not _addon.IsForever then
        _, y = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_HEALTHSTONE"] or "Ignorer la pierre de soins", "ignoreHealthstoneAlert")
        _, y = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_SOULSTONE"] or "Ignorer la pierre d'âme", "ignoreSoulstoneAlert")
    end

    -- Cas special "presence" (inverse) : resynchronise SpellEffects immediatement au clic
    -- Ruee ardente : n'existe pas sur Forever
    local SW = ns.SharedWidgets
    if not _addon.IsForever then
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
    end

    for _, entry in ipairs(Existing(ns.MISSING_CLASS_BUFFS.WARLOCK)) do
        CreateBuffRow(sub, entry, y, W); y = y + 24
    end
    if _addon.IsForever then
        y = AddThresholdSlider(sub, y + 6, W, L["MISSINGBUFFS_SHARDS_THRESHOLD"] or "Soul shards alert threshold",
            "shardsThreshold", 1, 20, 1, 3)
    end
    sub:SetHeight(math.max(y, 1))
end

local function BuildDruidSection(sub, W)
    local y = 0
    local _, y2 = AddDbCheckbox(sub, y, W, L["MISSINGBUFFS_IGNORE_FORMS"] or "Ignorer le changement de forme", "ignoreDruidForms")
    y = y2
    for _, entry in ipairs(Existing(ns.MISSING_CLASS_BUFFS.DRUID)) do
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

-- Forever : pas d'evocateur
if _addon.IsForever then
    for i = #CLASS_SECTIONS, 1, -1 do
        if CLASS_SECTIONS[i].class == "EVOKER" then table.remove(CLASS_SECTIONS, i) end
    end
end

local function ClassLabel(token)
    local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token]
    return name or token
end

-- Builder principal
function ns.SettingsPanel.BuildMissingBuffsMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME

    local hdr = SW.MakeSectionTitle(
        SW.CreateSectionHeader(p, L["MISSINGBUFFS_HEADER"] or "Buffs manquants", cw - 20))
    hdr:SetPoint("TOPLEFT", 10, 0)

    local y = -34
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

    -- Apparence icone / texte : deux sections repliables en tete de l'accordeon, devant
    -- les sections de classe. Chaque onChanged rafraichit l'icone en direct.
    local function Refresh()
        if ns.MissingBuffs then ns.MissingBuffs.RefreshAppearance() end
    end

    local function BuildIconSection(c, w)
        local cy, x, fw = 0, 5, w - 10

        local slIconSize = SW.CreateSlider(c, L["MISSINGBUFFS_ICON_SIZE"] or "Taille de l'icone", 32, 128, 1, fw)
        slIconSize:SetPoint("TOPLEFT", x, -cy)
        slIconSize:SetValue(cfg.iconSize or 64)
        slIconSize.onChanged = function(v) Cfg().iconSize = v; Refresh() end
        cy = cy + 62

        local cbBorder = SW.CreateCheckbox(c, L["MISSINGBUFFS_BORDER_ENABLE"] or "Bordure", fw)
        cbBorder:SetPoint("TOPLEFT", x, -cy)
        cbBorder:SetChecked(cfg.borderEnabled ~= false)
        cbBorder.onChanged = function(v) Cfg().borderEnabled = v; Refresh() end
        cy = cy + 26

        local colBorder = SW.CreateColorButton(c, L["MISSINGBUFFS_BORDER_COLOR"] or "Couleur de bordure", fw)
        colBorder:SetPoint("TOPLEFT", x, -cy)
        colBorder:SetColor(unpack(cfg.borderColor or { 1, 0.15, 0.15, 0.9 }))
        colBorder.onChanged = function(rgb)
            local c2 = Cfg()
            local a = (c2.borderColor and c2.borderColor[4]) or 0.9
            c2.borderColor = { rgb[1], rgb[2], rgb[3], a }
            Refresh()
        end
        cy = cy + 30

        local slBorderThick = SW.CreateSlider(c, L["MISSINGBUFFS_BORDER_THICKNESS"] or "Epaisseur de bordure", 1, 6, 1, fw)
        slBorderThick:SetPoint("TOPLEFT", x, -cy)
        slBorderThick:SetValue(cfg.borderThickness or 2)
        slBorderThick.onChanged = function(v) Cfg().borderThickness = v; Refresh() end
        cy = cy + 62

        local ddMask = SW.CreateDropdown(c, L["MISSINGBUFFS_ICON_SHAPE"] or "Forme", ns.MISSING_BUFF_ICON_MASKS, fw)
        ddMask:SetPoint("TOPLEFT", x, -cy)
        ddMask:SetValue(cfg.iconMaskIndex or 1)
        ddMask.onChanged = function(v) Cfg().iconMaskIndex = v; Refresh() end
        cy = cy + 48

        c:SetHeight(cy)
    end

    local function BuildTextSection(c, w)
        local cy, x, fw = 0, 5, w - 10

        local ddFont = SW.CreateDropdown(c, L["MISSINGBUFFS_TEXT_FONT"] or "Police", _addon.GetFontList(), fw)
        ddFont:SetPoint("TOPLEFT", x, -cy)
        ddFont:SetValue(cfg.textFont or ns.Media.font)
        ddFont.onChanged = function(v) Cfg().textFont = v; Refresh() end
        cy = cy + 48

        local slTextSize = SW.CreateSlider(c, L["MISSINGBUFFS_TEXT_SIZE"] or "Taille du texte", 8, 24, 1, fw)
        slTextSize:SetPoint("TOPLEFT", x, -cy)
        slTextSize:SetValue(cfg.textSize or 12)
        slTextSize.onChanged = function(v) Cfg().textSize = v; Refresh() end
        cy = cy + 62

        local colText = SW.CreateColorButton(c, L["MISSINGBUFFS_TEXT_COLOR"] or "Couleur du texte", fw)
        colText:SetPoint("TOPLEFT", x, -cy)
        colText:SetColor(unpack(cfg.textColor or { 1, 0.9, 0.3 }))
        colText.onChanged = function(rgb) Cfg().textColor = { rgb[1], rgb[2], rgb[3] }; Refresh() end
        cy = cy + 30

        local halfW = math.floor((fw - 8) / 2)
        local slOffX = SW.CreateSlider(c, L["SETTINGS_OFFSET_X"] or "Decalage X", -50, 50, 1, halfW)
        slOffX:SetPoint("TOPLEFT", x, -cy)
        slOffX:SetValue(cfg.textOffsetX or 0)
        slOffX.onChanged = function(v) Cfg().textOffsetX = v; Refresh() end
        local slOffY = SW.CreateSlider(c, L["SETTINGS_OFFSET_Y"] or "Decalage Y", -50, 50, 1, halfW)
        slOffY:SetPoint("TOPLEFT", x + halfW + 8, -cy)
        slOffY:SetValue(cfg.textOffsetY or -2)
        slOffY.onChanged = function(v) Cfg().textOffsetY = v; Refresh() end
        cy = cy + 62

        -- Toggles combinables (pas un dropdown exclusif), sur 3 colonnes
        local w3 = math.floor((fw - 16) / 3)
        local cbPulse = SW.CreateCheckbox(c, L["MISSINGBUFFS_TEXT_ANIM_PULSE"] or "Pulsation", w3)
        cbPulse:SetPoint("TOPLEFT", x, -cy)
        cbPulse:SetChecked(cfg.textAnimPulse and true or false)
        cbPulse.onChanged = function(v) Cfg().textAnimPulse = v; Refresh() end

        local cbBounce = SW.CreateCheckbox(c, L["MISSINGBUFFS_TEXT_ANIM_BOUNCE"] or "Rebond", w3)
        cbBounce:SetPoint("TOPLEFT", x + w3 + 8, -cy)
        cbBounce:SetChecked(cfg.textAnimBounce and true or false)
        cbBounce.onChanged = function(v) Cfg().textAnimBounce = v; Refresh() end

        local cbBlink = SW.CreateCheckbox(c, L["MISSINGBUFFS_TEXT_ANIM_BLINK"] or "Clignotement", w3)
        cbBlink:SetPoint("TOPLEFT", x + (w3 + 8) * 2, -cy)
        cbBlink:SetChecked(cfg.textAnimBlink and true or false)
        cbBlink.onChanged = function(v) Cfg().textAnimBlink = v; Refresh() end
        cy = cy + 26

        local ddOutline = SW.CreateDropdown(c, L["SETTINGS_TEXT_OUTLINE"] or "Contour", ns.GetTextOutlineStyles(), fw)
        ddOutline:SetPoint("TOPLEFT", x, -cy)
        ddOutline:SetValue(cfg.textOutlineStyle or "OUTLINE")
        ddOutline.onChanged = function(v) Cfg().textOutlineStyle = v; Refresh() end
        cy = cy + 48

        c:SetHeight(cy)
    end

    local sections = {
        { name = L["MISSINGBUFFS_ICON_HEADER"] or "Apparence de l'icone", build = BuildIconSection },
        { name = L["MISSINGBUFFS_TEXT_HEADER"] or "Apparence du texte",   build = BuildTextSection },
    }
    for _, cs in ipairs(CLASS_SECTIONS) do
        sections[#sections + 1] = { name = ClassLabel(cs.class), build = cs.build }
    end
    SW.CreateSectionStack(p, sections, cw, -y, "missingbuffs")

    return p
end

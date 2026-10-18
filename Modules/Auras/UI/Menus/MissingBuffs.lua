-- AishUIAura/UI/Menus/MissingBuffs.lua
-- Ecran de reglages "Buffs manquants" : reglages generaux, apparence, alertes (colonnes General + classes), seuils
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
    if entry.kind == "petHappiness" then return L["SETTINGS_PSEUDO_PET_UNHAPPY"] or entry.displayName end
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
        local sid = entry.spellId or entry.iconSpell
        local t = sid and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
        if t then icon:SetTexture(t) end
    end)

    local label = row:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(label, ns.Media.font, 11)
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)   -- borne a la ligne : "..." plutot que deborder sur la colonne voisine
    label:SetTextColor(unpack(Theme.textNormal))
    local name = entry.displayName or ("?" .. tostring(entry.spellId))
    pcall(function()
        local n = entry.spellId and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.spellId)
        if n then name = n end
    end)
    if entry.casts or entry.kind then name = ForeverEntryLabel(entry) or name end
    label:SetText(name)

    -- entry.dbKey : ligne liee a une cle "ignoreX" de ns.db.missingBuffs (cochee si absente) au lieu d'un spell ;
    -- entry.dbKeyOn : cle d'activation (cochee si vraie), entry.onToggle(valeur) appele apres le clic
    local function IsIgnored()
        if entry.dbKeyOn then return not Cfg()[entry.dbKeyOn] end
        if entry.dbKey then return Cfg()[entry.dbKey] and true or false end
        return ns.MissingBuffs.IsIgnored(entry.settingsId)
    end
    local function Refresh()
        local ignored = IsIgnored()
        box:SetColorTexture(unpack(ignored and Theme.checkboxOff or Theme.checkboxOn))
        check:SetShown(not ignored)
    end
    Refresh()
    row:SetScript("OnClick", function()
        if entry.dbKeyOn then
            local v = not Cfg()[entry.dbKeyOn]
            Cfg()[entry.dbKeyOn] = v
            if entry.onToggle then entry.onToggle(v) end
            ns.MissingBuffs.RequestCheck()
        elseif entry.dbKey then
            Cfg()[entry.dbKey] = not IsIgnored()
            ns.MissingBuffs.RequestCheck()
        else
            ns.MissingBuffs.SetIgnored(entry.settingsId, not IsIgnored())
        end
        Refresh()
    end)
    row:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1) end)
    row:SetScript("OnLeave", function() label:SetTextColor(unpack(Theme.textNormal)) end)
    return row
end

-- Section "Alertes" : une colonne "General" puis une par classe (ordre des Couleurs Thematiques), 5 colonnes par
-- rangee. Chaque ligne = une alerte (cochee = affichee) : buffs de classe, et interrupteurs propres a la classe
-- (postures, auras, familier...) en tete de colonne. Listes lues a l'ouverture : ns.MISSING_CLASS_BUFFS est
-- remplacee par sa version Forever au chargement des donnees.
local I = "Interface\\Icons\\"

local function Append(out, list)
    for _, e in ipairs(Existing(list)) do out[#out + 1] = e end
    return out
end

local function GeneralRows()
    local rows = {
        { dbKey = "ignoreBagsFull",       displayName = L["MISSINGBUFFS_BAGS_FULL"],      icon = I .. "INV_Misc_Bag_08" },
        { dbKey = "ignoreWellFedFood",    displayName = L["MISSINGBUFFS_WELLFED_FOOD"],   icon = I .. "INV_Misc_Food_15" },
        { dbKey = "ignoreFlasks",         displayName = L["MISSINGBUFFS_FLASKS"],         icon = I .. "INV_Potion_62" },
        { dbKey = "ignoreWeaponStones",   displayName = L["MISSINGBUFFS_WEAPON_STONES"],  icon = I .. "INV_Stone_SharpeningStone_05" },
        { dbKey = "ignoreGatherTracking", displayName = L["MISSINGBUFFS_GATHER_TRACKING"], icon = I .. "INV_Misc_Flower_02" },
        { dbKey = "ignoreTalentPoints",   displayName = L["MISSINGBUFFS_TALENT_POINTS"],  icon = I .. "Ability_Marksmanship" },
    }
    if _addon.IsForever then
        rows[#rows + 1] = { dbKey = "ignoreLegacyPoints", displayName = L["MISSINGBUFFS_LEGACY_POINTS"], icon = I .. "INV_Misc_Book_11" }
    end
    return rows
end

-- Ruee ardente (Retail) : alerte "presence" inverse, resynchronise SpellEffects tout de suite
local function BurningRushToggled(checked)
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

local CLASS_COLUMNS = {
    { class = "DRUID", rows = function()
        return Append({ { dbKey = "ignoreDruidForms", displayName = L["MISSINGBUFFS_ROW_FORM"], icon = I .. "Ability_Druid_CatForm" } },
            ns.MISSING_CLASS_BUFFS.DRUID)
    end },
    { class = "EVOKER", rows = function()
        return Append({ { dbKey = "ignoreEvokerAttunements", displayName = L["MISSINGBUFFS_ROW_ATTUNEMENT"], iconSpell = 403264 } },
            ns.MISSING_CLASS_BUFFS.EVOKER)
    end },
    { class = "HUNTER", rows = function()
        return Append({ { dbKey = "ignoreHunterPets", displayName = L["MISSINGBUFFS_ROW_PET"], icon = I .. "Ability_Hunter_BeastCall" } },
            ns.MISSING_CLASS_BUFFS.HUNTER)
    end },
    { class = "MAGE", rows = function() return Append({}, ns.MISSING_CLASS_BUFFS.MAGE) end },
    { class = "PALADIN", rows = function()
        local r = Append({ { dbKey = "ignorePaladinAuras", displayName = L["MISSINGBUFFS_ROW_AURA"], icon = I .. "Spell_Holy_DevotionAura" } },
            ns.MISSING_CLASS_BUFFS.PALADIN)
        -- Forever : une ligne par aura proposable (decochee = jamais proposee, mais compte comme active)
        if _addon.IsForever then
            for _, e in ipairs(Existing(ns.MISSING_PALADIN_AURAS)) do
                if e.settingsId then r[#r + 1] = e end
            end
        end
        return r
    end },
    { class = "PRIEST", rows = function() return Append({}, ns.MISSING_CLASS_BUFFS.PRIEST) end },
    { class = "ROGUE", rows = function()
        return {
            { dbKey = "ignoreLethalPoisons",    displayName = L["MISSINGBUFFS_ROW_LETHAL"],    iconSpell = 2823 },
            { dbKey = "ignoreNonlethalPoisons", displayName = L["MISSINGBUFFS_ROW_NONLETHAL"], iconSpell = 3408 },
        }
    end },
    { class = "SHAMAN", rows = function() return Append({}, ns.MISSING_CLASS_BUFFS.SHAMAN) end },
    { class = "WARLOCK", rows = function()
        local r = { { dbKey = "ignoreWarlockPets", displayName = L["MISSINGBUFFS_ROW_PET"], icon = I .. "Spell_Shadow_SummonImp" } }
        if not _addon.IsForever then
            r[#r + 1] = { dbKey = "ignoreHealthstoneAlert", displayName = L["MISSINGBUFFS_ROW_HEALTHSTONE"], icon = I .. "INV_Stone_04" }
            r[#r + 1] = { dbKey = "ignoreSoulstoneAlert",   displayName = L["MISSINGBUFFS_ROW_SOULSTONE"],   icon = I .. "Spell_Shadow_SoulGem" }
            r[#r + 1] = { dbKeyOn = "burningRushAlert", spellId = ns.MISSING_WARLOCK_BURNING_RUSH,
                          displayName = L["MISSINGBUFFS_BURNING_RUSH_ALERT"], onToggle = BurningRushToggled }
        end
        return Append(r, ns.MISSING_CLASS_BUFFS.WARLOCK)
    end },
    { class = "WARRIOR", rows = function()
        return Append({ { dbKey = "ignoreWarriorStances", displayName = L["MISSINGBUFFS_ROW_STANCE"], icon = I .. "Ability_Warrior_DefensiveStance" } },
            ns.MISSING_CLASS_BUFFS.WARRIOR)
    end },
}

local function ClassLabel(token)
    local name = _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token]
    return name or token
end

local COLS, COL_GAP, LINE_GAP, ROW_H, HEAD_H, MINI_H = 5, 8, 12, 24, 22, 18
local GENERAL_COLOR = { 0.78, 0.62, 0.30 }   -- ocre des titres de section

-- Seuil d'une alerte de quantite, affiche en ligne compacte juste sous elle : { cle, min, max, pas, defaut }
local function ThresholdOf(entry)
    if entry.dbKey == "ignoreBagsFull" then return { "bagsFreeThreshold", 0, 30, 1, 2 } end
    if entry.kind == "ammo" then return { "ammoThreshold", 20, 1000, 20, 200 } end
    if entry.kind == "item" then return { "shardsThreshold", 1, 20, 1, 3 } end
end

-- "Seuil : 2 |----|" : libelle en petit et curseur etroit, decales sous l'icone de la ligne d'alerte
local function CreateMiniThreshold(parent, y, W, t)
    local Theme = ns.THEME
    local key, minV, maxV, step, default = t[1], t[2], t[3], t[4], t[5]
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(W, MINI_H)
    f:SetPoint("TOPLEFT", 0, -y)
    local lbl = f:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(lbl, ns.Media.font, 9)
    lbl:SetPoint("LEFT", 22, 0)
    lbl:SetWidth(54)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(unpack(Theme.textDim or Theme.textNormal))
    local sl = CreateFrame("Slider", nil, f)
    sl:SetOrientation("HORIZONTAL")
    sl:SetHeight(12)
    sl:SetPoint("LEFT", lbl, "RIGHT", 2, 0)
    sl:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    local track = sl:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(2)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetColorTexture(1, 1, 1, 0.22)
    sl:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = sl:GetThumbTexture()
    thumb:SetSize(5, 10)
    local g = Theme.gold or GENERAL_COLOR
    thumb:SetVertexColor(g[1], g[2], g[3], 1)
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    sl:SetObeyStepOnDrag(true)
    local function Txt(v) lbl:SetText(string.format(L["MISSINGBUFFS_THRESHOLD_SHORT"] or "Seuil : %d", v)) end
    local v0 = Cfg()[key] or default
    sl:SetValue(v0); Txt(v0)
    sl:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        if Cfg()[key] == v then return end
        Cfg()[key] = v
        Txt(v)
        if ns.MissingBuffs then ns.MissingBuffs.RequestCheck() end
    end)
    return f
end

-- Titre de colonne : nom (couleur de classe, ocre pour "General") + filet fin dessous, comme la page Modules
local function CreateColumnHeader(parent, x, y, W, text, color)
    local Theme = ns.THEME
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(W, HEAD_H - 4)
    h:SetPoint("TOPLEFT", x, -y)
    local fs = h:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(fs, ns.Media.font, 12)
    fs:SetPoint("LEFT", 4, 1)
    fs:SetPoint("RIGHT", -2, 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetText(text)
    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    local MSW = _addon.SharedWidgets
    if MSW and MSW.PixelLine then MSW.PixelLine(line) end
    line:SetPoint("BOTTOMLEFT", 4, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetColorTexture(unpack(Theme.separator or { 1, 1, 1, 0.12 }))
    return h
end

local function BuildAlertsSection(c, w)
    local columns = { { label = L["MISSINGBUFFS_COL_GENERAL"] or "Général", color = GENERAL_COLOR, rows = GeneralRows() } }
    for _, cc in ipairs(CLASS_COLUMNS) do
        if not (_addon.IsForever and cc.class == "EVOKER") then   -- Forever : pas d'evocateur
            local rows = cc.rows()
            if #rows > 0 then
                local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cc.class]
                columns[#columns + 1] = { label = ClassLabel(cc.class), rows = rows,
                                          color = rc and { rc.r, rc.g, rc.b } or { 1, 1, 1 } }
            end
        end
    end
    local colW = math.floor((w - (COLS - 1) * COL_GAP) / COLS)
    local y, lineH = 0, 0
    for i, col in ipairs(columns) do
        local ci = (i - 1) % COLS
        if ci == 0 and i > 1 then y = y + lineH + LINE_GAP; lineH = 0 end
        local x = ci * (colW + COL_GAP)
        CreateColumnHeader(c, x, y, colW, col.label, col.color)
        local holder = CreateFrame("Frame", nil, c)
        holder:SetPoint("TOPLEFT", x, -(y + HEAD_H))
        local cy = 0
        for _, entry in ipairs(col.rows) do
            CreateBuffRow(holder, entry, cy, colW)
            cy = cy + ROW_H
            local t = ThresholdOf(entry)
            if t then CreateMiniThreshold(holder, cy - 4, colW, t); cy = cy + MINI_H - 4 end
        end
        holder:SetSize(colW, math.max(1, cy))
        lineH = math.max(lineH, HEAD_H + cy)
    end
    c:SetHeight(math.max(1, y + lineH))
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
        { name = L["MISSINGBUFFS_SEC_ALERTS"], build = BuildAlertsSection },
    }
    SW.CreateSectionStack(p, sections, cw, -y, "missingbuffs")

    return p
end

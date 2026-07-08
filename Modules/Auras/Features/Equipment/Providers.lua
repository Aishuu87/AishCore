-- AishUIAura/Features/Equipment/Providers.lua
-- War Gear : bijoux (trinkets), raciales (24 races), items on-use
-- Fournit la liste des slots trackables pour le render Equipment
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.Providers = ns.Providers or {}
local ARS = ns.Providers
local CreateFrame, pcall, math, tinsert, wipe = CreateFrame, pcall, math, table.insert, wipe
local TEXCOORD = 0.07

local RACIALS = {
    Human={59752},Dwarf={20594},NightElf={58984},Gnome={20589},Draenei={28880},
    Worgen={68992},VoidElf={256948},LightforgedDraenei={255647},DarkIronDwarf={265221},
    KulTiran={287712},Mechagnome={312924},Orc={33697},Undead={7744},Tauren={20549},
    Troll={26297},BloodElf={28730},Goblin={69041},Nightborne={260364},
    HighmountainTauren={255654},MagharOrc={274738},ZandalariTroll={291944},
    Vulpera={312411},Pandaren={107079},Dracthyr={368970},EarthenDwarf={436786},
}

local allSlots, iconFrames = {}, {}
local GCD_THRESH, initialized, groupContainer, needsLayout = 1.6, false, nil, false

local function SlotDB(key)
    local db = ns.db; if not db then return ns.SlotDefaults end
    if not db.equipmentSlots then db.equipmentSlots = {} end
    if not db.equipmentSlots[key] then db.equipmentSlots[key] = ns.DeepCopy(ns.SlotDefaults) end
    return db.equipmentSlots[key]
end

local function ScanSlots()
    wipe(allSlots); local db = ns.db; if not db or not db.equipmentEnabled then return end
    for _, s in ipairs({13,14}) do pcall(function()
        local id = GetInventoryItemID("player", s)
        if id and id > 0 then tinsert(allSlots, {key="trinket:"..s, type="trinket", slot=s, itemID=id}) end
    end) end
    pcall(function()
        local _, race = UnitRace("player"); if not race or not RACIALS[race] then return end
        for _, spID in ipairs(RACIALS[race]) do
            local ok, known = pcall(function()
                if IsPlayerSpell and IsPlayerSpell(spID) then return true end
                if C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spID) then return true end
                return false
            end)
            if ok and known then tinsert(allSlots, {key="racial:"..spID, type="racial", spellID=spID}) end
        end
    end)
    pcall(function()
        local skip = {[13]=true,[14]=true,[16]=true,[17]=true}
        for s = 1, 18 do if not skip[s] then pcall(function()
            local id = GetInventoryItemID("player", s)
            if id and id > 0 then
                local ok, u = pcall(function() return C_Item and C_Item.IsUsableItem and C_Item.IsUsableItem(id) end)
                if ok and u then tinsert(allSlots, {key="equip:"..s, type="equip", slot=s, itemID=id}) end
            end
        end) end end
    end)
end

local function GetSlotTexture(slot)
    local tex
    if slot.type == "trinket" or slot.type == "equip" then pcall(function() tex = GetInventoryItemTexture("player", slot.slot) end)
    else pcall(function() tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(slot.spellID) end) end
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetSlotName(slot)
    local name
    if slot.type == "trinket" or slot.type == "equip" then pcall(function()
        if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(slot.itemID) end
        if not name then local link = GetInventoryItemLink("player", slot.slot); if link then name = link:match("%[(.-)%]") end end
    end) else pcall(function() name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(slot.spellID) end) end
    return name or ("?"..(slot.itemID or slot.spellID or ""))
end

local function CreateArsenalIcon(slot)
    local sd = SlotDB(slot.key)
    local f = CreateFrame("Button", "AishWG_"..slot.key:gsub(":","_"), UIParent, "SecureActionButtonTemplate,BackdropTemplate")
    f:SetSize(sd.w or 31, sd.h or 25)
    f:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    -- Background
    local bg = f:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0,0,0,sd.bgAlpha or 0.7); f._bg = bg
    -- Icon
    local icon = f:CreateTexture(nil,"ARTWORK"); icon:SetAllPoints(); icon:SetTexCoord(TEXCOORD,1-TEXCOORD,TEXCOORD,1-TEXCOORD); f._icon = icon
    -- Cooldown
    local cd = CreateFrame("Cooldown",nil,f,"CooldownFrameTemplate"); cd:SetAllPoints(); cd:SetDrawEdge(true); cd:SetHideCountdownNumbers(true); cd:SetReverse(true); f._cd = cd
    -- Secure attributes
    pcall(function()
        if slot.type == "trinket" or slot.type == "equip" then f:SetAttribute("type","macro"); f:SetAttribute("macrotext","/use "..slot.slot)
        elseif slot.type == "racial" then f:SetAttribute("type","spell"); f:SetAttribute("spell",slot.spellID) end
    end)
    -- Alt+drag pour déplacer (mode individuel) — uniquement hors combat
    -- On utilise un flag _isMoving pour n'appeler StopMovingOrSizing QUE si un mouvement
    -- est effectivement en cours (sinon Blizzard bloque l'appel comme fonction protégée)
    f:SetMovable(true); f:SetClampedToScreen(true)
    f._isMoving = false
    f:HookScript("OnMouseDown",function(s,b)
        if b=="LeftButton" and IsAltKeyDown() and not InCombatLockdown() then
            local cfg2 = ns.db and ns.db.equipment
            if cfg2 and cfg2.layout == "grid_free" then
                pcall(function() s:StartMoving(); s._isMoving = true end)
            end
        end
    end)
    f:HookScript("OnMouseUp",function(s)
        -- Ne fait rien si aucun mouvement en cours — évite l'ADDON_ACTION_BLOCKED
        -- sur les clics normaux (utilisation trinket/racial via SecureFrame)
        if not s._isMoving then return end
        s._isMoving = false
        pcall(function() s:StopMovingOrSizing() end)
        local sx,sy = GetScreenWidth()/2, GetScreenHeight()/2
        local sc = s:GetEffectiveScale()/UIParent:GetEffectiveScale()
        local cx,cy = s:GetCenter()
        if cx and cy then
            local sd2 = SlotDB(slot.key)
            sd2.x = math.floor(cx*sc-sx); sd2.y = math.floor(cy*sc-sy)
        end
    end)
    f:Show(); return f
end

local function ApplyBorder(f)
    local cfg = ns.db and ns.db.equipment or {}
    local style = cfg.borderStyle or "square"
    local bw = cfg.borderWidth or 2
    local bc = cfg.borderColor or {0.055, 0.055, 0.055, 1}
    -- Clean previous
    if f._borderLines then for _,b in ipairs(f._borderLines) do b:Hide() end end
    if style == "none" then f:SetBackdrop(nil); return end
    -- Square: 4 line textures
    f:SetBackdrop(nil)
    if not f._borderLines then
        f._borderLines = {}
        for i = 1, 4 do f._borderLines[i] = f:CreateTexture(nil, "OVERLAY", nil, 7) end
    end
    for _, b in ipairs(f._borderLines) do
        b:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.8); b:Show()
    end
    local bT, bB, bL, bR = f._borderLines[1], f._borderLines[2], f._borderLines[3], f._borderLines[4]
    bT:SetHeight(bw); bT:ClearAllPoints(); bT:SetPoint("TOPLEFT", f, -bw, bw); bT:SetPoint("TOPRIGHT", f, bw, bw)
    bB:SetHeight(bw); bB:ClearAllPoints(); bB:SetPoint("BOTTOMLEFT", f, -bw, -bw); bB:SetPoint("BOTTOMRIGHT", f, bw, -bw)
    bL:SetWidth(bw); bL:ClearAllPoints(); bL:SetPoint("TOPLEFT", f, -bw, bw); bL:SetPoint("BOTTOMLEFT", f, -bw, -bw)
    bR:SetWidth(bw); bR:ClearAllPoints(); bR:SetPoint("TOPRIGHT", f, bw, bw); bR:SetPoint("BOTTOMRIGHT", f, bw, -bw)
end

local function LayoutAll()
    if InCombatLockdown() then needsLayout = true; return end
    local db = ns.db; if not db then return end
    local cfg = db.equipment or ns.Defaults.equipment
    local isGrouped = (cfg.layout or "grid_fixed") == "grid_fixed"
    if isGrouped then
        if not groupContainer then
            groupContainer = CreateFrame("Frame",nil,UIParent)
            groupContainer:SetFrameStrata("MEDIUM"); groupContainer:SetFrameLevel(50)
            groupContainer:SetMovable(true); groupContainer:SetClampedToScreen(true); groupContainer:EnableMouse(true)
            groupContainer:SetPropagateMouseClicks(true)  -- click-through par défaut
            groupContainer:SetScript("OnMouseDown",function(s,b)
                if b=="LeftButton" and IsAltKeyDown() and not InCombatLockdown() then
                    s:SetPropagateMouseClicks(false)
                    s:StartMoving()
                end
            end)
            groupContainer:SetScript("OnMouseUp",function(s) s:StopMovingOrSizing()
                s:SetPropagateMouseClicks(true)
                if ns.db and ns.db.equipment then
                    local sx,sy = GetScreenWidth()/2, GetScreenHeight()/2
                    local sc = s:GetEffectiveScale()/UIParent:GetEffectiveScale()
                    local cx,cy = s:GetCenter()
                    if cx and cy then
                        local w, h = s:GetSize()
                        local gr = ns.db.equipment.groupGrowth or "RIGHT"
                        local saveX = cx*sc-sx
                        local saveY = cy*sc-sy
                        if gr == "DOWN" then saveY = saveY + h * sc / 2
                        elseif gr == "UP" then saveY = saveY - h * sc / 2
                        elseif gr == "LEFT" then saveX = saveX + w * sc / 2
                        elseif gr == "RIGHT" then saveX = saveX - w * sc / 2
                        end
                        ns.db.equipment.groupX = math.floor(saveX); ns.db.equipment.groupY = math.floor(saveY)
                    end
                end
            end)
        end
        local gw,gh,gg = cfg.groupW or 31, cfg.groupH or 25, cfg.groupGap or 3
        local growth = cfg.groupGrowth or "RIGHT"
        -- Collect enabled slots only
        local enabledSlots = {}
        for _, slot in ipairs(allSlots) do
            local sd = SlotDB(slot.key)
            if sd.enabled ~= false then enabledSlots[#enabledSlots+1] = slot end
        end
        -- Position enabled slots
        for i, slot in ipairs(enabledSlots) do
            local f = iconFrames[slot.key]; if f then
                f:SetParent(groupContainer); f:SetSize(gw,gh); f:ClearAllPoints()
                local off = (i-1)*((growth=="RIGHT" or growth=="LEFT") and (gw+gg) or (gh+gg))
                if growth=="RIGHT" then f:SetPoint("LEFT",groupContainer,"LEFT",off,0)
                elseif growth=="LEFT" then f:SetPoint("RIGHT",groupContainer,"RIGHT",-off,0)
                elseif growth=="DOWN" then f:SetPoint("TOP",groupContainer,"TOP",0,-off)
                else f:SetPoint("BOTTOM",groupContainer,"BOTTOM",0,off) end
                -- Respecte combatOnly : invisible hors combat (sauf preview).
                -- Sans ce check, le cadre noir du slot apparaitrait hors combat
                -- meme si l'utilisateur ne veut le voir qu'en combat (default).
                local sd = SlotDB(slot.key)
                local co = sd.combatOnly
                if co == nil then co = cfg.combatOnly end
                if co == nil then co = true end
                if co and not ns._inCombat and not ns._equipmentPreview then
                    f:SetAlpha(0)
                else
                    f:SetAlpha(cfg.groupAlpha or 1.0)
                end
                pcall(ApplyBorder, f)
            end
        end
        -- Park disabled slots
        for _, slot in ipairs(allSlots) do
            local sd = SlotDB(slot.key)
            local f = iconFrames[slot.key]
            if f and sd.enabled == false then
                f:SetParent(groupContainer); f:ClearAllPoints()
                f:SetPoint("CENTER",groupContainer,"CENTER",0,0); f:SetAlpha(0)
            end
        end
        -- Resize container
        local n = #enabledSlots
        local tw,th = 1,1
        if n > 0 then
            if growth=="RIGHT" or growth=="LEFT" then tw=n*gw+(n-1)*gg; th=gh
            else tw=gw; th=n*gh+(n-1)*gg end
        end
        groupContainer:SetSize(math.max(tw,1), math.max(th,1))
        groupContainer:ClearAllPoints()
        -- Growth-aware anchor (V1 pattern)
        if growth=="RIGHT" then groupContainer:SetPoint("LEFT",UIParent,"CENTER",cfg.groupX or -167, cfg.groupY or -188)
        elseif growth=="LEFT" then groupContainer:SetPoint("RIGHT",UIParent,"CENTER",cfg.groupX or -167, cfg.groupY or -188)
        elseif growth=="DOWN" then groupContainer:SetPoint("TOP",UIParent,"CENTER",cfg.groupX or -167, cfg.groupY or -188)
        else groupContainer:SetPoint("BOTTOM",UIParent,"CENTER",cfg.groupX or -167, cfg.groupY or -188) end
        groupContainer:Show()
    else
        -- Individual (Ronin) mode
        for _, slot in ipairs(allSlots) do
            local f = iconFrames[slot.key]; if f then
                local sd = SlotDB(slot.key)
                f:SetParent(UIParent); f:SetSize(sd.w or 31, sd.h or 25)
                f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",sd.x or 0, sd.y or -188)
                -- Respecte combatOnly : invisible hors combat (sauf preview)
                if sd.enabled == false then
                    f:SetAlpha(0)
                else
                    local co = sd.combatOnly
                    if co == nil then co = cfg.combatOnly end
                    if co == nil then co = true end
                    if co and not ns._inCombat and not ns._equipmentPreview then
                        f:SetAlpha(0)
                    else
                        f:SetAlpha(sd.alpha or 1.0)
                    end
                end
                pcall(ApplyBorder, f)
            end
        end
        if groupContainer then groupContainer:Hide() end
    end
    needsLayout = false
end

-- Helper top-level : lit l'état du CD depuis la frame cooldown.
-- Retourne la durée en ms (0 si pas en CD). Hoist pour éviter closure par slot par tick.
local function _ReadCDState(cd)
    local s, d = cd:GetCooldownTimes()
    if s and d and s > 0 and d > 0 then return d end
    return 0
end

-- Helper top-level : cache un icon slot Equipment via SpellFX.
-- Hoist pour éviter closure pcall par slot par tick (jusqu'à 24/tick en worst case).
local function _HideSpellFXIcon(f)
    if ns.SpellFX then ns.SpellFX:Hide(f, "icon") end
end

-- Scratch table pour SpellFX:Show icon (évite alloc par slot par tick quand 3D actif).
local _providerIcon3DCfg = {}

local function UpdateIcon(f, slot, sd)
    -- CRITICAL anti-clignotement : on ne ré-apppelle SetTexture que si la valeur change.
    -- Cette fonction est appelée à chaque tick (toutes les 200ms-1s), et re-setter la
    -- texture à la même valeur peut causer un flash d'1 frame dans Blizzard (recharge
    -- interne). Pareil pour ShowGlow qui redémarre l'animation si appelé en boucle.
    local newTex = GetSlotTexture(slot)
    if f._lastTex ~= newTex then
        f._icon:SetTexture(newTex)
        f._lastTex = newTex
    end
    if f._bg then
        local bgA = sd.bgAlpha or 0.7
        if f._lastBgAlpha ~= bgA then
            f._bg:SetColorTexture(0, 0, 0, bgA)
            f._lastBgAlpha = bgA
        end
    end
    local onCD = false
    -- Étape 1 : lit l'état du CD depuis la frame cooldown (lecture passive, toujours safe)
    local ok, dMs = pcall(_ReadCDState, f._cd)
    if ok and dMs > 0 then onCD = (dMs / 1000 > GCD_THRESH) end
    -- Step 2: Feed CD data into cooldown frame (SetCooldown is NOT protected — safe in combat)
    pcall(function()
        local rawS, rawD
        if slot.type == "trinket" or slot.type == "equip" then
            if C_Item and C_Item.GetItemCooldown then rawS, rawD = C_Item.GetItemCooldown(slot.itemID or 0) end
            if (not rawS or rawS == 0) and slot.slot then rawS, rawD = GetInventoryItemCooldown(slot.slot) end
        elseif slot.type == "racial" then
            if C_Spell and C_Spell.GetSpellCooldown then
                local cd = C_Spell.GetSpellCooldown(slot.spellID); if cd then rawS=cd.startTime; rawD=cd.duration end
            elseif GetSpellCooldown then rawS, rawD = GetSpellCooldown(slot.spellID) end
        end
        if not rawS then return end
        -- Detaint: tonumber(tostring(val)) strips secret taint
        local sS = tonumber(tostring(rawS)) or 0
        local sD = tonumber(tostring(rawD)) or 0
        local durObj
        if (slot.type == "racial") and C_Spell and C_Spell.GetSpellCooldownDuration then
            durObj = C_Spell.GetSpellCooldownDuration(slot.spellID)
        end
        if durObj then f._cd:SetCooldownFromDurationObject(durObj, true)
        elseif sS > 0 and sD > 0 then f._cd:SetCooldown(sS, sD) end
    end)
    -- Step 3: Re-read after feeding (definitive onCD state)
    local ok2, dMs2 = pcall(_ReadCDState, f._cd)
    if ok2 and dMs2 > 0 then onCD = (dMs2 / 1000 > GCD_THRESH) end
    -- Cache local pour le ticker adaptatif (cf. activeCDCount)
    f._onCD = onCD
    -- SetDesaturated change seulement si l'état on/off CD a changé
    local desatTarget = sd.desat and onCD or false
    if f._lastDesat ~= desatTarget then
        f._icon:SetDesaturated(desatTarget)
        f._lastDesat = desatTarget
    end
    -- Effets 3D sur l'icône WG (affichés quand trinket/raciale est on CD = actif, ou pendant la config 3D)
    if ns.SpellFX and ns.db and ns.EffectsActive() then
        local sid = slot.spellID or slot.itemID or 0
        local spells = ns.GetSpecSpells()
        local si = spells and spells[sid]
        local show3D = onCD or ns._equipment3DPreview
        local wantShow = si and si.iconModelID and si.iconModelID > 0 and show3D
        -- N'appelle Show/Hide 3D que si l'état change, sinon le modèle se rejoue en boucle
        if wantShow and f._fx3dState ~= "shown" then
            _providerIcon3DCfg.alpha = si.iconModelA or 0.5
            _providerIcon3DCfg.rotation = si.iconModelRot or 0
            _providerIcon3DCfg.x = si.iconModelX or 0
            _providerIcon3DCfg.y = si.iconModelY or 0
            _providerIcon3DCfg.z = si.iconModelZ or 0
            _providerIcon3DCfg.scale = si.iconModelS or 1
            _providerIcon3DCfg.layer = si.iconModelL or "back"
            ns.SpellFX:Show(f, "icon", si.iconModelID, _providerIcon3DCfg)
            f._fx3dState = "shown"
        elseif not wantShow and f._fx3dState ~= "hidden" then
            pcall(_HideSpellFXIcon, f)
            f._fx3dState = "hidden"
        end
    end
    -- Glow (when ready / off CD) : change seulement si l'état on/off CD a changé
    local wantGlow = sd.glowEnabled and not onCD
    if wantGlow and f._lastGlow ~= true then
        if ns.ShowGlow then ns.ShowGlow(f, sd.glowIdx or 2, sd.glowColor or ns.barColor, sd.glowAlpha or 0.7, sd.glowScale or 1.0) end
        f._lastGlow = true
    elseif not wantGlow and f._lastGlow ~= false then
        if ns.HideGlow then ns.HideGlow(f) end
        f._lastGlow = false
    end
end

-- Compteur de slots actuellement en cooldown (mis à jour par UpdateAll)
-- Utilisé par le ticker adaptatif : si 0 → mode lent (1fps), sinon mode normal (5fps)
local activeCDCount = 0

local function UpdateAll()
    local db = ns.db; if not db or not db.equipmentEnabled then
        for _,f in pairs(iconFrames) do
            if f._lastAlpha ~= 0 then f:SetAlpha(0); f._lastAlpha = 0 end
            pcall(_HideSpellFXIcon, f)
        end
        activeCDCount = 0
        return
    end
    local cfg = db.equipment or ns.Defaults.equipment
    local cdCount = 0
    for _, slot in ipairs(allSlots) do
        local sd, f = SlotDB(slot.key), iconFrames[slot.key]
        if f then
            if not sd.enabled then
                if f._lastAlpha ~= 0 then f:SetAlpha(0); f._lastAlpha = 0 end
                pcall(_HideSpellFXIcon, f)
            else
                local co = sd.combatOnly
                if co == nil then co = cfg.combatOnly end
                if co == nil then co = true end  -- default: hide out of combat unless explicitly disabled
                if co and not ns._inCombat and not ns._equipmentPreview then
                    if f._lastAlpha ~= 0 then f:SetAlpha(0); f._lastAlpha = 0 end
                    pcall(_HideSpellFXIcon, f)
                else
                    UpdateIcon(f, slot, sd)
                    local targetAlpha = sd.alpha or 1.0
                    if f._lastAlpha ~= targetAlpha then f:SetAlpha(targetAlpha); f._lastAlpha = targetAlpha end
                    -- Compte les slots actuellement en CD pour ajuster la fréquence du ticker
                    if f._onCD then cdCount = cdCount + 1 end
                end
            end
        end
    end
    activeCDCount = cdCount
end

local tickerFrame = nil

-- Ticker adaptatif :
-- - Mode actif (200ms = 5fps) : au moins 1 slot en cooldown → animation fluide du swipe
-- - Mode idle (1000ms = 1fps) : aucun slot en CD → on continue de polling pour détecter le démarrage d'un nouveau CD
-- L'event SPELL_UPDATE_COOLDOWN appelle UpdateAll directement quand un CD démarre, donc le passage idle → actif est instantané.
local function GetTickInterval()
    return (activeCDCount > 0) and 0.2 or 1.0
end

-- Handler OnUpdate hoist : évite de recréer la closure à chaque SetTickerActive(true).
-- UpdateAll et GetTickInterval sont local-scoped dans ce fichier, définis au-dessus.
local function _EquipmentTickerHandler(s, e)
    s._t = s._t + e
    if s._t < GetTickInterval() then return end
    s._t = 0
    pcall(UpdateAll)
end

-- Active ou désactive le ticker OnUpdate du module Equipment.
-- Économise du CPU quand le module est désactivé (le frame ne fait plus rien).
local function SetTickerActive(active)
    if not tickerFrame then return end
    if active then
        if not tickerFrame._tickerOn then
            tickerFrame:SetScript("OnUpdate", _EquipmentTickerHandler)
            tickerFrame._tickerOn = true
        end
    else
        if tickerFrame._tickerOn then
            tickerFrame:SetScript("OnUpdate", nil)
            tickerFrame._tickerOn = false
        end
    end
end

function ARS:Init()
    local db = ns.db; if not db or not db.equipmentEnabled then return end
    ScanSlots()
    for _, slot in ipairs(allSlots) do if not iconFrames[slot.key] then iconFrames[slot.key] = CreateArsenalIcon(slot) end end
    LayoutAll()
    if not initialized then
        local t = CreateFrame("Frame"); t._t = 0
        t:RegisterEvent("SPELL_UPDATE_COOLDOWN"); t:RegisterEvent("PLAYER_REGEN_ENABLED")
        t:SetScript("OnEvent", function(_,ev) if ev=="PLAYER_REGEN_ENABLED" and needsLayout then pcall(function() ARS:Refresh() end) end; pcall(UpdateAll) end)
        tickerFrame = t
        SetTickerActive(true)
        initialized = true
    else
        -- Si déjà initialisé mais qu'on revient ici (re-enable du module), réactiver le ticker
        SetTickerActive(true)
    end
    UpdateAll()
end

function ARS:Refresh()
    local db = ns.db; if not db or not db.equipmentEnabled then
        SetTickerActive(false)  -- module désactivé : on coupe le ticker
        for _,f in pairs(iconFrames) do f:SetAlpha(0) end; return
    end
    SetTickerActive(true)  -- module actif : on s'assure que le ticker tourne
    ScanSlots()
    local active = {}; for _,s in ipairs(allSlots) do active[s.key] = true end
    for k,f in pairs(iconFrames) do if not active[k] then f:SetAlpha(0) end end
    if not InCombatLockdown() then
        for _,s in ipairs(allSlots) do if not iconFrames[s.key] then iconFrames[s.key] = CreateArsenalIcon(s) end end
    end
    LayoutAll(); UpdateAll()
end

function ARS:UpdateFade() pcall(UpdateAll) end
function ARS:Layout() pcall(LayoutAll); pcall(UpdateAll) end
function ARS:GetAllSlots() return allSlots end
function ARS:GetSlotName(s) return GetSlotName(s) end
function ARS:GetSlotTexture(s) return GetSlotTexture(s) end

local ef = CreateFrame("Frame"); ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED"); ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:SetScript("OnEvent", function(_,ev)
    if ev=="PLAYER_ENTERING_WORLD" then C_Timer.After(2,function() pcall(function() ARS:Refresh() end) end)
    else C_Timer.After(0.3,function() pcall(function() ARS:Refresh() end) end) end
end)

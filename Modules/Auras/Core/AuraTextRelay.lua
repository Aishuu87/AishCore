-- AishUIAura/Core/AuraTextRelay.lua : relais de stacks via AuraContainer natif Blizzard
-- (12.1.0+), fonctionne en combat même pour stacks/durée secrets (API C_UnitAuras bloquée).
-- Groupe filtré sur 1 spellID -> FontString reliée via SetApplicationCount, tenue à jour
-- par Blizzard même une fois le bouton "forbidden". Containers créés hors combat uniquement.
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local containers = {}  -- [unit] = AuraContainer
local overlays = {}    -- [unit.."#"..spellID] = stackFontString
local groupsAdded = {} -- [unit.."#"..spellID] = true (evite les AddAuraGroup en double)
local pendingSpells = {}  -- spellID demandes avant que le container soit pret (hors combat requis)

local function CreateContainer(unit)
    if not CreateFrame then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local ok, c = pcall(function()
        local cc = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        cc:SetSize(1, 1)
        -- Hors écran : les FontStrings sont reparentées sur nos icônes à chaque scan
        cc:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, -2000)
        cc:SetUnit(unit)
        cc:Show()
        return cc
    end)
    if not ok then
        if DPrint then DPrint("AuraTextRelay: echec creation container " .. unit .. " : " .. tostring(c)) end
        return nil
    end
    return c
end

local function EnsureContainer(unit)
    if containers[unit] then return containers[unit] end
    local c = CreateContainer(unit)
    if c then containers[unit] = c end
    return c
end

-- Idempotent. Doit réussir hors combat au moins une fois (retry via FlushPendingAuraTextOverlays)
function ns.EnsureAuraTextOverlay(unit, spellID)
    if not unit or not spellID then return end
    local key = unit .. "#" .. spellID
    if groupsAdded[key] then return end

    local c = EnsureContainer(unit)
    if not c or not c.AddAuraGroup then
        pendingSpells[key] = { unit = unit, spellID = spellID }
        return
    end

    local filterStr = (unit == "player") and "HELPFUL" or "HARMFUL"
    local ok = pcall(function()
        c:AddAuraGroup(key, filterStr, {
            maxFrameCount = 1,
            candidateFilters = { spellIds = { [spellID] = true } },
            initializeFrame = function(button)
                pcall(function()
                    if button.Icon then button.Icon:SetAlpha(0) end
                    if button.SetSize then button:SetSize(1, 1) end
                    local stackFS = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    if button.SetApplicationCount then
                        pcall(button.SetApplicationCount, button, stackFS)
                    end
                    overlays[key] = stackFS
                end)
            end,
        })
    end)
    if ok then
        groupsAdded[key] = true
        pendingSpells[key] = nil
    else
        pendingSpells[key] = { unit = unit, spellID = spellID }
    end
end

-- Rejoue les demandes échouées (container pas prêt / combat). Appelé après
-- PLAYER_REGEN_ENABLED et PLAYER_ENTERING_WORLD.
function ns.FlushPendingAuraTextOverlays()
    if InCombatLockdown and InCombatLockdown() then return end
    for key, req in pairs(pendingSpells) do
        pendingSpells[key] = nil
        ns.EnsureAuraTextOverlay(req.unit, req.spellID)
    end
end

-- Variante numérique : lit le texte déjà écrit par Blizzard (SetApplicationCount) et le
-- convertit en nombre, sans jamais lire la valeur secrète. Pour CenterArc/ResourceCircle.
-- Renvoie nil si le relais n'existe pas encore ou si le texte n'est pas un nombre.
function ns.GetAuraTextOverlayStackCount(unit, spellID)
    if not unit or not spellID then return nil end
    local key = unit .. "#" .. spellID
    local fs = overlays[key]
    if not fs then
        ns.EnsureAuraTextOverlay(unit, spellID)
        return nil
    end
    local ok, text = pcall(fs.GetText, fs)
    if not ok or not text then return nil end
    return tonumber(text)
end

-- Rattache visuellement la FontString de stack Blizzard sur notre widget (stackParent).
-- Appelé à chaque render. Renvoie true si un relais existe et a été appliqué.
function ns.ApplyAuraTextOverlay(unit, spellID, stackParent)
    if not unit or not spellID or not stackParent then return false end
    local key = unit .. "#" .. spellID
    local fs = overlays[key]
    if not fs then
        ns.EnsureAuraTextOverlay(unit, spellID)
        return false
    end
    local ok = pcall(function()
        -- Parente au PARENT de stackParent (pas stackParent lui-même, souvent caché
        -- par l'appelant) ; SetAllPoints garde la même position sans hériter du Hide.
        local hostFrame = stackParent.GetParent and stackParent:GetParent() or stackParent
        fs:SetParent(hostFrame)
        fs:ClearAllPoints()
        fs:SetAllPoints(stackParent)
        fs:SetFont(select(1, stackParent:GetFont()) or "Fonts\\FRIZQT__.TTF", select(2, stackParent:GetFont()) or 11, select(3, stackParent:GetFont()) or "OUTLINE")
        fs:SetTextColor(stackParent:GetTextColor())
        fs:SetJustifyH(stackParent:GetJustifyH() or "RIGHT")
        fs:SetDrawLayer("OVERLAY")
        fs:Show()
    end)
    return ok
end

-- Diagnostic /aatr [spellID] : état interne du relais
SLASH_AATR1 = "/aatr"
SlashCmdList["AATR"] = function(msg)
    local P = "|cff33aaff[AATR]|r "
    local function p(s) print(P .. s) end

    local nContainers, nGroups, nOverlays, nPending = 0, 0, 0, 0
    for _ in pairs(containers) do nContainers = nContainers + 1 end
    for _ in pairs(groupsAdded) do nGroups = nGroups + 1 end
    for _ in pairs(overlays) do nOverlays = nOverlays + 1 end
    for _ in pairs(pendingSpells) do nPending = nPending + 1 end
    p(string.format("containers=%d groupsAdded=%d overlays=%d pendingSpells=%d",
        nContainers, nGroups, nOverlays, nPending))
    for unit, c in pairs(containers) do
        p(string.format("  container[%s] : type=%s hasAddAuraGroup=%s",
            unit, tostring(c.GetObjectType and c:GetObjectType()), tostring(c.AddAuraGroup ~= nil)))
    end

    local sid = tonumber(msg)
    if sid then
        for _, unit in ipairs({"player", "target"}) do
            local key = unit .. "#" .. sid
            local fs = overlays[key]
            local txt, shown, parent = "n/a", "n/a", "n/a"
            if fs then
                local okT, t = pcall(fs.GetText, fs)
                txt = okT and tostring(t) or ("erreur:" .. tostring(t))
                shown = tostring(fs:IsShown())
                local p2 = fs:GetParent()
                parent = p2 and tostring(p2:GetName() or p2) or "aucun"
            end
            p(string.format("  [%s] spellID=%d groupsAdded=%s overlay=%s pending=%s texte=%s shown=%s parent=%s",
                unit, sid, tostring(groupsAdded[key]), tostring(fs ~= nil), tostring(pendingSpells[key] ~= nil),
                txt, shown, parent))
        end
    else
        p("Usage: /aatr <spellID> pour le detail d'un sort precis (ex: /aatr 344179)")
    end
end

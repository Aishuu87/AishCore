-- Debug\TestCharges.lua
-- TEST : affiche l'icone de Lava Lash (60103) avec son CD swipe.
-- Utilise C_Spell.GetSpellCooldownDuration → SetCooldownFromDurationObject,
-- pattern identique à Providers.lua (combat-safe, pas de secret numbers lus).
-- GCD filtré via GetCooldownTimes() (retourne des ms propres, comparaison sûre).
-- Supprime ce fichier (et sa ligne dans le TOC) quand le test est terminé.
------------------------------------------------------------------------
local addonName = (...)

local SPELL_ID   = 60103  -- Lava Lash
local ICON_SIZE = 52

------------------------------------------------------------------------
-- Frame principale + icône
------------------------------------------------------------------------
local f = CreateFrame("Frame", "AishTestLavaLashFrame", UIParent)
f:SetSize(ICON_SIZE, ICON_SIZE)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetFrameStrata("HIGH")

local icon = f:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints(f)
icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

-- Cooldown swipe.
-- SetCooldownFromDurationObject est appelé avec le durObj de GetSpellCooldownDuration :
-- aucune valeur n'est lue ni comparée en Lua → zéro taint.
local cd = CreateFrame("Cooldown", "AishTestLavaLashCD", f, "CooldownFrameTemplate")
cd:SetAllPoints(f)
cd:SetDrawSwipe(true)
cd:SetDrawEdge(false)
cd:SetSwipeColor(0, 0, 0, 0.8)
cd:SetHideCountdownNumbers(false)
cd:SetFrameLevel(f:GetFrameLevel() + 2)

------------------------------------------------------------------------
-- Mise à jour
------------------------------------------------------------------------
local function Update()
    -- Icône
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(SPELL_ID)
    if tex then icon:SetTexture(tex) end

    -- CD swipe : C_Spell.GetSpellCooldown détecte le vrai CD (nombres Lua propres).
    -- GetSpellCooldownDuration → SetCooldownFromDurationObject pour l'animation
    -- (durObj opaque passé directement au moteur C++ → aucune lecture de secret number).
    if C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldownDuration then
        local spellCD  = C_Spell.GetSpellCooldown(SPELL_ID)
        -- isActive est un booléen (safe) : true = vrai CD de sort, false = GCD seul.
        -- startTime/duration sont des secret numbers → ne jamais les comparer.
        local isRealCD = spellCD and spellCD.isActive
        if isRealCD then
            local durObj = C_Spell.GetSpellCooldownDuration(SPELL_ID)
            if durObj then
                local ok = pcall(cd.SetCooldownFromDurationObject, cd, durObj)
                if not ok then cd:Clear() end
            else
                cd:Clear()
            end
        else
            cd:Clear()
        end
    end
end

------------------------------------------------------------------------
-- Événements
------------------------------------------------------------------------
local evtFrame = CreateFrame("Frame")
evtFrame:RegisterEvent("ADDON_LOADED")
evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evtFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
evtFrame:RegisterEvent("SPELLS_CHANGED")

evtFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        C_Timer.After(0.5, Update)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, Update)
    else
        Update()
    end
end)

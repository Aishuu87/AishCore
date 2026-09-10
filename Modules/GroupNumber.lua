-- Modules/GroupNumber.lua : numero de sous-groupe de raid en overlay (raid uniquement).
-- Mode ElvUI (conteneurs ElvUF_Raid<N>Group<M>) : une vignette par sous-groupe affiche.
-- Sinon : repli sur une vignette flottante unique pour le sous-groupe du joueur.
-- Module autonome, s'auto-enregistre au chargement (pas d'Init central, cf. Visibility.lua).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local GroupNumber = {}
ns.Modules.GroupNumber = GroupNumber

local TEX_GRUNGE = "Interface\\AddOns\\AishCore\\Media\\XPBar\\grunge_spot1.png"

-- Badge "solo" (mode repli, position ecran fixe)
local soloBadge, soloBadgeTex, soloNumText, soloNumTextSlug

-- Pool de badges "par groupe", indexe par NOM du conteneur (pas par numero de sous-groupe,
-- au cas ou plusieurs conteneurs partageraient le meme numero)
local groupBadges = {}  -- [containerName] = { badge=, badgeTex=, numText= }

-- UnitIsUnit plutot que UnitInRaid(unit) : evite l'ambiguite d'indexation 0/1-based
local function GetPlayerSubgroup()
    if not IsInRaid() then return nil end
    for i = 1, GetNumGroupMembers() do
        if UnitIsUnit("raid" .. i, "player") then
            local _, _, subgroup = GetRaidRosterInfo(i)
            return subgroup
        end
    end
    return nil
end

-- Un conteneur ElvUI peut rester "shown" hors raid : seuls ses boutons-membres reflètent la vraie composition
local function ContainerHasVisibleMember(containerFrame)
    for _, child in ipairs({ containerFrame:GetChildren() }) do
        if child.IsVisible and child:IsVisible() then
            return true
        end
    end
    return false
end

-- Scanne _G pour les conteneurs ElvUF_Raid<N>Group<M> affiches et reellement peuples
local function ScanElvUIGroupContainers()
    local groups = {}
    if not IsInRaid() then return groups end -- jamais de vignette hors raid
    for name in pairs(_G) do
        if type(name) == "string" then
            local subgroup = name:match("^ElvUF_Raid%d+Group(%d+)$")
            if subgroup then
                local frame = _G[name]
                -- IsVisible() (pas IsShown()) : verifie toute la chaine de parents,
                -- ignore les conteneurs fantomes des presets ElvUI non utilises
                if frame and frame.IsVisible and frame:IsVisible() and ContainerHasVisibleMember(frame) then
                    groups[#groups + 1] = { name = name, frame = frame, subgroup = tonumber(subgroup) }
                end
            end
        end
    end
    return groups
end

-- Debug : /aishgroupdebug liste tous les conteneurs detectes (nom, sous-groupe, rect)
SLASH_AISHGROUPDEBUG1 = "/aishgroupdebug"
SlashCmdList["AISHGROUPDEBUG"] = function()
    local groups = ScanElvUIGroupContainers()
    print(string.format("|cff00ff00[AishCore]|r %d conteneur(s) ElvUF_Raid*Group* detecte(s) :", #groups))
    for _, g in ipairs(groups) do
        local f = g.frame
        local left, top = f:GetLeft(), f:GetTop()
        local w, h = f:GetSize()
        print(string.format("  - %s -> sous-groupe %d | rect=(%.1f,%.1f) taille=%.1fx%.1f",
            g.name, g.subgroup,
            left or -1, top or -1, w or -1, h or -1))
    end
end

-- Factory vignette+texte, reutilisee pour le badge solo et chaque badge du pool
local function CreateBadge(name)
    local badge = CreateFrame("Frame", name, UIParent)
    badge:SetFrameStrata("MEDIUM")

    local badgeTex = badge:CreateTexture(nil, "BACKGROUND")
    badgeTex:SetAllPoints()
    badgeTex:SetTexture(TEX_GRUNGE)
    badgeTex:SetRotation(math.rad(math.random(0, 359))) -- rotation esthetique figee, evite le rendu identique

    local numText = badge:CreateFontString(nil, "OVERLAY")
    numText:SetJustifyH("CENTER")
    local numTextSlug = ns.CreateSlugRing(badge, numText)

    badge:Hide()
    return badge, badgeTex, numText, numTextSlug
end

-- Applique taille/couleur/police/texte a UNE vignette (solo ou du pool),
-- puis l'ancre via `anchorFn` (differe selon le mode).
local function StyleBadge(cfg, badge, badgeTex, numText, numTextSlug, text, anchorFn)
    local size = cfg.badgeSize or 28
    badge:SetSize(size, size)
    badgeTex:SetVertexColor(unpack(cfg.badgeColor or { 0, 0, 0, 0.85 }))

    ns.ApplyTextOutlineStyle(numText, numTextSlug, cfg.font or ns.Media.font, cfg.textSize or 16, cfg.textOutlineStyle, true)
    numText:SetTextColor(unpack(cfg.textColor or { 1, 1, 1, 1 }))
    numText:ClearAllPoints()
    numText:SetPoint("CENTER", badge, "CENTER", cfg.textOffsetX or 0, cfg.textOffsetY or 0)
    numText:SetText(text)

    badge:ClearAllPoints()
    anchorFn(badge)
    badge:Show()
end

function GroupNumber.Refresh()
    local cfg = ns.GetCfg("groupNumber")
    if not cfg or cfg.enabled == false then
        if soloBadge then soloBadge:Hide() end
        for _, entry in pairs(groupBadges) do entry.badge:Hide() end
        return
    end

    local groups = ScanElvUIGroupContainers()

    if #groups > 0 then
        -- Mode ElvUI : une vignette par sous-groupe detecte, plus de badge solo.
        if soloBadge then soloBadge:Hide() end

        local seen = {}
        for _, g in ipairs(groups) do
            seen[g.name] = true
            local entry = groupBadges[g.name]
            if not entry then
                local badge, badgeTex, numText, numTextSlug = CreateBadge("AishCoreGroupNumberBadge_" .. g.name)
                entry = { badge = badge, badgeTex = badgeTex, numText = numText, numTextSlug = numTextSlug }
                groupBadges[g.name] = entry
            end
            local pos = cfg.badgePosition or "TOP"
            StyleBadge(cfg, entry.badge, entry.badgeTex, entry.numText, entry.numTextSlug, tostring(g.subgroup), function(badge)
                badge:SetPoint(pos, g.frame, pos, cfg.badgeX or 0, cfg.badgeY or 0)
            end)
        end
        -- Cache les badges du pool dont le conteneur a disparu/s'est masque
        for containerName, entry in pairs(groupBadges) do
            if not seen[containerName] then entry.badge:Hide() end
        end
    else
        -- Repli : aucun conteneur ElvUI detecte -> comportement d'origine
        -- (mon sous-groupe, position ecran fixe).
        for _, entry in pairs(groupBadges) do entry.badge:Hide() end

        local subgroup = GetPlayerSubgroup()
        if subgroup then
            if not soloBadge then
                soloBadge, soloBadgeTex, soloNumText, soloNumTextSlug = CreateBadge("AishCoreGroupNumberBadge")
            end
            StyleBadge(cfg, soloBadge, soloBadgeTex, soloNumText, soloNumTextSlug, tostring(subgroup), function(badge)
                badge:SetPoint("CENTER", UIParent, "CENTER", cfg.badgeX or 0, cfg.badgeY or 200)
            end)
        elseif soloBadge then
            soloBadge:Hide()
        end
    end
end

function GroupNumber.ApplySettings()
    GroupNumber.Refresh()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    GroupNumber.Refresh()
    if event == "GROUP_ROSTER_UPDATE" then
        -- Les conteneurs ElvUI peuvent se recalculer/afficher avec un leger
        -- delai apres un changement de composition -- un seul re-scan differe
        -- suffit (pas besoin d'un ticker permanent).
        C_Timer.After(0.2, GroupNumber.Refresh)
    end
end)

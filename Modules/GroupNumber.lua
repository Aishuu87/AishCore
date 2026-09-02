-- Modules/GroupNumber.lua : affiche le numero de sous-groupe de raid en
-- overlay -- RAID uniquement, jamais en groupe simple ni solo.
--
-- Deux modes, selon ce qui est detecte a l'ecran :
--   1) ElvUI en layout raid "par groupe" detecte (conteneurs nommes
--      ElvUF_Raid<N>Group<M>, confirme en jeu via /framestack) -> UNE
--      vignette PAR SOUS-GROUPE ACTUELLEMENT AFFICHE, ancree sur son
--      conteneur ElvUI. 6 groupes crees = 6 vignettes numerotees 1-6.
--   2) Sinon (pas ElvUI, ou ElvUI pas dans ce layout) -> repli sur le
--      comportement d'origine : UNE vignette flottante a position fixe
--      (UIParent + decalage) montrant le sous-groupe DU JOUEUR uniquement.
--
-- Meme pattern visuel que le badge de niveau de XPBar.lua
-- (CreateXPBar_Badge) : une vignette (texture) + un texte centre par-dessus,
-- tous deux positionnables independamment (memes reglages cfg.badgeX/Y et
-- cfg.textOffsetX/Y reutilises pour les DEUX modes -- en mode ElvUI, ils
-- deviennent un decalage relatif au conteneur au lieu d'une position ecran
-- absolue).
--
-- Module autonome (pas de dependance a UnitBars.lua), sur le modele de
-- Visibility.lua : pas de fonction Init() centrale, s'auto-enregistre a son
-- propre chargement, scan defensif de _G pour les frames tierces (meme
-- approche que Visibility.lua pour ses candidats ElvUI).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local GroupNumber = {}
ns.Modules.GroupNumber = GroupNumber

local TEX_GRUNGE = "Interface\\AddOns\\AishuuMedia\\grunge_spot1.png"

-- Badge "solo" (mode repli, position ecran fixe)
local soloBadge, soloBadgeTex, soloNumText, soloNumTextSlug

-- Pool de badges "par groupe" (mode ElvUI), indexe par NOM du conteneur --
-- pas par numero de sous-groupe : au cas (rare) ou plusieurs conteneurs
-- ElvUF_RaidN existeraient en parallele (layout par role par ex.), chacun
-- garde son propre badge meme si deux conteneurs partagent le meme numero
-- de sous-groupe.
local groupBadges = {}  -- [containerName] = { badge=, badgeTex=, numText= }

-- Iteration + UnitIsUnit plutot que UnitInRaid(unit) directement : evite
-- toute ambiguite sur l'indexation (0-based vs 1-based selon les sources/
-- versions client) -- on matche l'unite raidN qui EST le joueur, point.
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

-- Un conteneur de sous-groupe ElvUI peut rester "shown" structurellement
-- (element de layout toujours present) meme hors raid ou pour un sous-groupe
-- vide -- seuls ses boutons-membres enfants refletent la vraie composition.
-- Confirme en jeu : sans ce filtre, les vignettes restaient affichees hors
-- raid alors qu'aucune frame de raid n'etait visible.
local function ContainerHasVisibleMember(containerFrame)
    for _, child in ipairs({ containerFrame:GetChildren() }) do
        if child.IsVisible and child:IsVisible() then
            return true
        end
    end
    return false
end

-- Scanne _G pour les conteneurs de sous-groupe ElvUI actuellement affiches
-- ET reellement peuples. Motif confirme en jeu via /framestack :
-- "ElvUF_Raid<N>Group<M>" (le conteneur du sous-groupe M dans le
-- raid-conteneur N d'ElvUI), PAS le suffixe "...UnitButtonK" (les boutons
-- individuels, un cran plus bas).
local function ScanElvUIGroupContainers()
    local groups = {}
    -- Jamais de vignette hors raid, quoi qu'en disent les conteneurs ElvUI
    -- (garde-fou principal -- cf. ContainerHasVisibleMember pour le filtre
    -- plus fin par sous-groupe DANS un raid actif).
    if not IsInRaid() then return groups end
    for name in pairs(_G) do
        if type(name) == "string" then
            local subgroup = name:match("^ElvUF_Raid%d+Group(%d+)$")
            if subgroup then
                local frame = _G[name]
                -- IsVisible() (pas IsShown()) : IsShown() ne reflete que
                -- l'etat local du conteneur -- il peut rester "shown" meme
                -- si tout un parent (le profil de taille de raid non actif)
                -- est cache. IsVisible() verifie toute la chaine de parents,
                -- donc ignore les conteneurs "fantomes" des presets ElvUI
                -- non utilises (confirme via /aishgroupdebug : 3 conteneurs
                -- au meme rect exact pour chaque sous-groupe).
                if frame and frame.IsVisible and frame:IsVisible() and ContainerHasVisibleMember(frame) then
                    groups[#groups + 1] = { name = name, frame = frame, subgroup = tonumber(subgroup) }
                end
            end
        end
    end
    return groups
end

-- Debug : /aishgroupdebug liste tous les conteneurs actuellement detectes
-- (nom, sous-groupe, rect ecran) -- pour diagnostiquer le bug de vignettes
-- "1" empilees sans deviner a l'aveugle.
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

-- Factory vignette+texte, reutilisee pour le badge solo ET chaque badge du
-- pool -- meme structure, juste construite a la demande plutot qu'en singleton.
local function CreateBadge(name)
    local badge = CreateFrame("Frame", name, UIParent)
    badge:SetFrameStrata("MEDIUM")

    local badgeTex = badge:CreateTexture(nil, "BACKGROUND")
    badgeTex:SetAllPoints()
    badgeTex:SetTexture(TEX_GRUNGE)
    -- Rotation aleatoire figee a la creation (purement esthetique) : evite
    -- que toutes les vignettes (plusieurs a la fois en mode ElvUI) aient
    -- exactement le meme rendu -- appliquee UNE fois, pas a chaque refresh.
    badgeTex:SetRotation(math.rad(math.random(0, 359)))

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

-- Core.lua : Namespace partagé entre tous les fichiers de l'addon
local addonName, ns = ...

-- Table principale de l'addon
ns.addonName    = addonName
ns.addonVersion = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

-- Client : un seul code pour Retail et Forever (cf. docs/PLAN_MULTI_CLIENT.md). Forever = build
-- 1.60.x, numero d'interface 16001. Preferer la detection d'une API quand elle existe ; ce
-- drapeau ne sert que quand rien d'autre ne tranche.
ns.CLIENT    = (select(4, GetBuildInfo()) < 20000) and "forever" or "retail"
ns.IsForever = ns.CLIENT == "forever"

-- Disponibilite des modules selon le client. Cle = id de categorie du GUI ou nom de module
-- (initiale en minuscule : "Skyriding" -> "skyriding"). Absent de la table = disponible partout.
-- Un module indisponible ne s'enregistre pas (ns.Modules.X reste nil) et disparait du GUI
-- (page Modules, sidebar, recherche, arbre de profils, categories d'Auras).
local MODULE_RULES = {
  skyriding    = function() return not ns.IsForever end,
  cdmLayout    = function() return C_CooldownViewer ~= nil end,
  cdmEssential = function() return C_CooldownViewer ~= nil end,
  cdmUtility   = function() return C_CooldownViewer ~= nil end,
}
local _moduleAvail = {}
function ns.IsModuleAvailable(id)
  if type(id) ~= "string" or id == "" then return true end
  local key = id:sub(1, 1):lower() .. id:sub(2)
  local v = _moduleAvail[key]
  if v == nil then
    local rule = MODULE_RULES[key]
    v = (not rule) or (rule() == true)
    _moduleAvail[key] = v
  end
  return v
end

--- Retire d'une liste les entrees dont le module est indisponible (en place).
-- Une entree est soit l'id lui-meme, soit une table portant l'id dans `field` (defaut "id").
function ns.PruneUnavailable(list, field)
  if type(list) ~= "table" then return list end
  field = field or "id"
  for i = #list, 1, -1 do
    local e = list[i]
    local id = type(e) == "table" and e[field] or e
    if not ns.IsModuleAvailable(id) then table.remove(list, i) end
  end
  return list
end

-- FOREVER UNIQUEMENT. En Retail, reassigner ces globals depuis un addon les marquerait (taint)
-- et contaminerait le code securise de Blizzard qui les appelle : le bloc ne s'execute pas.
-- Globals de specialisation : sur le client Forever ils ne sont plus exposes dans le namespace
-- global, et surtout le personnage n'a PAS de specialisation -- seulement trois arbres de talents.
-- On reconstitue donc la notion de spe a partir des points investis : l'arbre le plus fourni fait
-- la spe. Tout le reste de l'addon (couleurs thematiques, profils par spe, barre de rotation)
-- continue alors de fonctionner sans une seule modification, puisqu'il interroge ces globals.
if ns.IsForever then
	local CSI = C_SpecializationInfo

	-- Ordre des arbres de talents classiques -> specID retail correspondant (cf. ns.SPEC_MAP).
	-- L'ordre des onglets suit celui des specialisations retail pour toutes les classes.
	-- Exception : le druide n'a que trois arbres pour quatre specs retail, "Combat farouche"
	-- couvrant a la fois Farouche et Gardien. Choix retenu : on le rattache a GARDIEN (104),
	-- ce qui lui donne le role tank, l'arc de Fer-poil et le profil de couleurs "Gardien".
	-- Consequence a connaitre : les points de combo du felin sont rattaches a Farouche (103)
	-- cote retail, ils sont donc reactives explicitement pour ce client (cf. UI/SettingsPanel.lua).
	local TALENT_TAB_SPECS = {
		DEATHKNIGHT = { 250, 251, 252 },
		DRUID       = { 102, 104, 105 },
		HUNTER      = { 253, 254, 255 },
		MAGE        = { 62, 63, 64 },
		MONK        = { 268, 269, 270 },
		PALADIN     = { 65, 66, 70 },
		PRIEST      = { 256, 257, 258 },
		ROGUE       = { 259, 260, 261 },
		SHAMAN      = { 262, 263, 264 },
		WARLOCK     = { 265, 266, 267 },
		WARRIOR     = { 71, 72, 73 },
	}

	-- Roles, pour GetSpecializationRole (detection healer/tank ailleurs dans l'addon).
	local SPEC_ROLES = {
		[65] = "HEALER", [256] = "HEALER", [257] = "HEALER", [264] = "HEALER",
		[105] = "HEALER", [270] = "HEALER",
		[66] = "TANK", [73] = "TANK", [250] = "TANK", [104] = "TANK", [268] = "TANK",
	}

	-- Branches de l'arbre de traits. Sur ce client il n'y a qu'un arbre de classe, sans sous-arbres :
	-- les trois branches (Combat elementaire / Amelioration / Restauration) sont exposees comme
	-- "groupes d'affichage", et CHAQUE NOEUD indique a quelle branche il appartient via son champ
	-- groupIDs. Cette liste contient aussi d'autres groupes (rangees, contraintes d'affichage) :
	-- on n'y retient que l'identifiant qui correspond a une branche connue.
	-- Une lecture geometrique (decoupage des colonnes aux plus grands ecarts) sert de dernier
	-- recours, pour le cas ou une classe n'exposerait pas ce rattachement.
	-- Cache du parcours lui-meme. Il a DEUX appelants : DominantTalentTab et
	-- GetSpecializationInfo (qui y cherche le nom et l'icone de la branche). Cacher seulement
	-- le premier laissait le second relancer un scan complet -- ~100 appels C_Traits.GetNodeInfo,
	-- soit ~100 Ko -- a chaque resolution de spe, plusieurs fois par seconde.
	local TRAIT_SCAN_TTL = 60
	local _tbpPoints, _tbpGroups, _tbpAt = nil, nil, -1

	local ComputeTraitBranchPoints
	local function TraitBranchPoints()
		local now = GetTime and GetTime() or 0
		if _tbpAt >= 0 and (now - _tbpAt) < TRAIT_SCAN_TTL then
			return _tbpPoints, _tbpGroups
		end
		_tbpAt = now
		_tbpPoints, _tbpGroups = ComputeTraitBranchPoints()
		return _tbpPoints, _tbpGroups
	end

	function ComputeTraitBranchPoints()
		if not (C_ClassTalents and C_Traits and C_Traits.GetGroupDisplayInfoByTreeID) then return nil end
		local okC, cfgID = pcall(C_ClassTalents.GetActiveConfigID)
		if not okC or not cfgID then return nil end
		local okCfg, cfg = pcall(C_Traits.GetConfigInfo, cfgID)
		if not (okCfg and cfg and cfg.treeIDs and cfg.treeIDs[1]) then return nil end
		local treeID = cfg.treeIDs[1]

		local okG, groups = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
		if not (okG and type(groups) == "table" and #groups >= 2) then return nil end
		-- orderIndex donne l'ordre d'affichage des branches, qui suit celui des specialisations.
		table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)

		local branchOfGroupID = {}
		for i, g in ipairs(groups) do
			if g.groupID then branchOfGroupID[g.groupID] = i end
		end

		local okN, nodes = pcall(C_Traits.GetTreeNodes, treeID)
		if not (okN and type(nodes) == "table") then return nil end

		local points, matched = {}, false
		local bought, xset = {}, {}
		for _, nodeID in ipairs(nodes) do
			local okI, ni = pcall(C_Traits.GetNodeInfo, cfgID, nodeID)
			if okI and type(ni) == "table" then
				local ranks = tonumber(ni.ranksPurchased) or 0
				local x = tonumber(ni.posX)
				if x then
					xset[x] = true
					if ranks > 0 then bought[#bought + 1] = { x = x, ranks = ranks } end
				end
				if ranks > 0 and type(ni.groupIDs) == "table" then
					for _, gid in ipairs(ni.groupIDs) do
						local branch = branchOfGroupID[gid]
						if branch then
							points[branch] = (points[branch] or 0) + ranks
							matched = true
							break  -- un seul groupe de branche par noeud
						end
					end
				end
			end
		end
		if matched then return points, groups end

		-- Repli geometrique : les branches occupent des blocs de colonnes nettement separes, on
		-- coupe donc aux (#groups - 1) plus grands ecarts. Aucune borne en dur, le nombre de
		-- branches et leurs coordonnees variant d'une classe a l'autre.
		if #bought == 0 then return points, groups end
		local xs = {}
		for x in pairs(xset) do xs[#xs + 1] = x end
		if #xs < #groups then return points, groups end
		table.sort(xs)
		local gaps = {}
		for i = 2, #xs do gaps[#gaps + 1] = { at = i, gap = xs[i] - xs[i - 1] } end
		table.sort(gaps, function(a, b) return a.gap > b.gap end)
		local cuts = {}
		for i = 1, math.min(#groups - 1, #gaps) do cuts[#cuts + 1] = gaps[i].at end
		table.sort(cuts)
		local bounds = {}
		for _, at in ipairs(cuts) do bounds[#bounds + 1] = xs[at] end
		for _, n in ipairs(bought) do
			local branch = 1
			for i = 1, #bounds do
				if n.x >= bounds[i] then branch = i + 1 end
			end
			points[branch] = (points[branch] or 0) + n.ranks
		end
		return points, groups
	end

	-- Branche la plus investie. nil si l'API n'existe pas, ou si aucun point n'est place : mieux vaut
	-- "pas de spe" -- les modules retombent alors sur la couleur de classe -- qu'une spe arbitraire.
	-- Resultat mis en cache : le calcul parcourt tous les noeuds de l'arbre, alors que les appelants
	-- interrogent la spe a chaque rafraichissement d'interface.
	-- TTL long ET invalidation par evenement (cf. plus bas). Il etait a 2 secondes, ce qui
	-- relancait TraitBranchPoints 30 fois par minute : ce parcours appelle C_Traits.GetNodeInfo
	-- sur CHAQUE noeud de l'arbre, et chacun renvoie une table neuve et volumineuse. Une
	-- centaine de noeuds toutes les 2 s, en permanence -- c'est ce qui faisait grimper la
	-- memoire sur ce client, et sur lui seul (retail n'a pas ce bloc).
	-- Les talents ne changent pas tout seuls : le TTL n'est qu'un filet, l'invalidation
	-- evenementielle garde la reactivite immediate.
	local SPEC_CACHE_TTL = 60
	-- Plancher absolu entre deux parcours reels, invalidation comprise. Sans lui, un evenement
	-- bruyant suffit a relancer le scan a chaque appel : c'est exactement ce qui s'est produit
	-- avec SPELLS_CHANGED dans la liste ci-dessous, et la memoire grimpait de ~600 Ko/s.
	local SPEC_SCAN_MIN = 3
	local cachedTab, cachedAt, lastScanAt = nil, -1, -1
	local function DominantTalentTab()
		local now = GetTime and GetTime() or 0
		if cachedAt >= 0 and (now - cachedAt) < SPEC_CACHE_TTL then return cachedTab end
		-- Invalide mais trop tot : on rend la derniere valeur connue plutot que de rescanner.
		if lastScanAt >= 0 and (now - lastScanAt) < SPEC_SCAN_MIN then return cachedTab end
		lastScanAt = now
		cachedAt = now
		cachedTab = nil

		-- Clients a onglets de talents classiques.
		if type(GetNumTalentTabs) == "function" and type(GetTalentTabInfo) == "function" then
			local okN, numTabs = pcall(GetNumTalentTabs)
			if okN and numTabs then
				local bestTab, bestPoints = nil, 0
				for i = 1, numTabs do
					local okT, _, _, pointsSpent = pcall(GetTalentTabInfo, i)
					local pts = okT and tonumber(pointsSpent) or 0
					-- Strictement superieur : a egalite le premier l'emporte, sinon la spe oscillerait
					-- entre deux branches au fil des points depenses.
					if pts > bestPoints then bestTab, bestPoints = i, pts end
				end
				cachedTab = bestTab
				return cachedTab
			end
		end

		-- Clients a arbre de traits unique (Forever).
		local points, groups = TraitBranchPoints()
		if points and groups then
			-- Quelle branche vient de recevoir un point ? On ne peut pas le demander au jeu,
			-- mais on peut l'observer : on compare le releve courant au precedent. Memorise dans
			-- la SavedVariable, donc conserve a travers un /reload.
			local db   = ns.DB
			local prev = db and db._talentBranchPoints
			if prev then
				for i = 1, #groups do
					if (points[i] or 0) > (prev[i] or 0) then
						if db then db._lastTalentBranch = i end
					end
				end
			end
			if db then
				local snap = {}
				for i = 1, #groups do snap[i] = points[i] or 0 end
				db._talentBranchPoints = snap
			end

			local bestBranch, bestPoints = nil, 0
			for i = 1, #groups do
				local p = points[i] or 0
				if p > bestPoints then bestBranch, bestPoints = i, p end
			end

			-- EGALITE : c'est le dernier point investi qui tranche. Sans cela la branche
			-- d'index le plus faible l'emportait, et poser un point menant a une egalite
			-- faisait basculer la spe -- couleurs et sorts avec.
			local lastB = db and db._lastTalentBranch
			if lastB and bestPoints > 0 and (points[lastB] or 0) == bestPoints then
				bestBranch = lastB
			end
			cachedTab = bestBranch
		end
		return cachedTab
	end
	ns.GetDominantTalentTab = DominantTalentTab
	ns.GetTraitBranchPoints = TraitBranchPoints

	-- Invalidation immediate : sans cela, un point depense mettrait jusqu'a deux secondes a changer
	-- la spe affichee.
	function ns.InvalidateSpecCache()
		cachedAt = -1
		_tbpAt   = -1
	end

	-- Les seuls moments ou la branche dominante peut changer. Sans cela, un TTL long
	-- retarderait l'affichage apres un changement de talents.
	local _specInvEvt = CreateFrame("Frame")
	-- SPELLS_CHANGED est VOLONTAIREMENT absent : il se declenche a chaque changement de forme,
	-- de buff ou de sort appris, donc en continu -- il vidait le cache en permanence.
	for _, e in ipairs({
		"TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_CREATED", "CONFIG_COMMIT_FAILED",
		"ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
		"PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD",
	}) do
		pcall(_specInvEvt.RegisterEvent, _specInvEvt, e)
	end
	_specInvEvt:SetScript("OnEvent", function() cachedAt = -1 end)

	local function TabSpecID(index)
		if not index then return nil end
		local _, classFile = UnitClass("player")
		local list = classFile and TALENT_TAB_SPECS[classFile]
		return list and list[index] or nil
	end
	ns.GetTalentTabSpecID = TabSpecID

	-- Ce client EXPOSE GetSpecialization et GetSpecializationInfo, mais elles ne decrivent aucune
	-- specialisation reelle : l'ID renvoye (1489) n'appartient a aucune specialisation connue.
	-- Tester leur simple existence ne suffit donc pas.
	-- Critere retenu : l'ID designe-t-il une specialisation que l'addon sait interpreter, c'est-a-dire
	-- presente dans SPEC_MAP ? Surtout PAS "existe-t-il une deuxieme specialisation" : sur ce client
	-- ces index numerotent les BUILDS de talents, dont un seul est actif a la fois -- creer un second
	-- build suffirait a faire croire a de vraies specialisations et desactiverait la detection.
	-- Les fonctions natives restent utilisees des qu'elles sont valides : comportement retail
	-- strictement inchange.
	local rawGetSpecialization     = GetSpecialization
	local rawGetSpecializationInfo = GetSpecializationInfo
	local rawGetSpecializationRole = GetSpecializationRole

	local nativeOK, nativeAt = nil, -1
	local function NativeSpecsAreReal()
		local now = GetTime and GetTime() or 0
		if nativeOK ~= nil and (now - nativeAt) < 5 then return nativeOK end
		nativeAt = now

		-- SPEC_MAP vit dans le sous-namespace Auras et se charge apres ce fichier. Tant qu'elle
		-- manque, on ne tranche pas et on privilegie l'API native : c'est le bon choix sur retail, et
		-- sur ce client la fenetre se referme bien avant le premier appel reel (PLAYER_LOGIN).
		local map = ns.Auras and ns.Auras.SPEC_MAP
		if not map then
			nativeOK = true
			return nativeOK
		end

		nativeOK = false
		if type(rawGetSpecialization) == "function" and type(rawGetSpecializationInfo) == "function" then
			local okIdx, idx = pcall(rawGetSpecialization)
			if okIdx and idx then
				local okId, id = pcall(rawGetSpecializationInfo, idx)
				nativeOK = okId and type(id) == "number" and map[id] ~= nil
			end
		end
		return nativeOK
	end
	ns.NativeSpecsAreReal = NativeSpecsAreReal

	GetSpecialization = function(...)
		if NativeSpecsAreReal() then
			if type(rawGetSpecialization) == "function" then return rawGetSpecialization(...) end
			if CSI and CSI.GetSpecialization then return CSI.GetSpecialization(...) end
		end
		return DominantTalentTab()
	end

	GetSpecializationInfo = function(index, ...)
		if NativeSpecsAreReal() then return rawGetSpecializationInfo(index, ...) end
		local specID = TabSpecID(index)
		if not specID then return nil end
		-- Meme ordre de retours que l'API retail : id, nom, description, icone, role.
		local name, icon
		if type(GetTalentTabInfo) == "function" then
			local okT, n, ic = pcall(GetTalentTabInfo, index)
			if okT then name, icon = n, ic end
		else
			local _, groups = TraitBranchPoints()
			local g = groups and groups[index]
			if g then name, icon = g.displayName, g.icon end
		end
		return specID, name, nil, icon, SPEC_ROLES[specID] or "DAMAGER"
	end

	GetSpecializationRole = function(index, ...)
		if NativeSpecsAreReal() and type(rawGetSpecializationRole) == "function" then
			return rawGetSpecializationRole(index, ...)
		end
		local specID = TabSpecID(index)
		return specID and (SPEC_ROLES[specID] or "DAMAGER") or nil
	end
end

-- /aishspec : ce que l'addon deduit de tes arbres de talents, et ce que les API repondent.
SLASH_AISHSPEC1 = "/aishspec"
SlashCmdList["AISHSPEC"] = function()
	local P = "|cff00ffff[AishCore spe]|r "
	local _, classFile = UnitClass("player")
	print(P .. "classe=" .. tostring(classFile))
	print(P .. "GetNumTalentTabs=" .. type(GetNumTalentTabs)
		.. "  GetTalentTabInfo=" .. type(GetTalentTabInfo)
		.. "  C_SpecializationInfo=" .. type(C_SpecializationInfo))
	if type(GetNumTalentTabs) == "function" and type(GetTalentTabInfo) == "function" then
		local okN, n = pcall(GetNumTalentTabs)
		print(P .. "nombre d'arbres=" .. tostring(okN and n))
		for i = 1, (okN and n or 0) do
			local okT, name, icon, pts = pcall(GetTalentTabInfo, i)
			print(P .. string.format("  arbre %d : ok=%s nom=%s points=%s icone=%s",
				i, tostring(okT), tostring(name), tostring(pts), tostring(icon)))
		end
	end
	print(P .. "specialisations natives exploitables=" .. tostring(ns.NativeSpecsAreReal and ns.NativeSpecsAreReal())
		.. "  (faux => spe deduite des branches de talents)")
	if ns.GetTraitBranchPoints then
		local pts, groups = ns.GetTraitBranchPoints()
		if pts and groups then
			for i, g in ipairs(groups) do
				print(P .. string.format("  branche %d : %s = %d point(s)", i, tostring(g.displayName), pts[i] or 0))
			end
		end
	end
	local idx = GetSpecialization and GetSpecialization()
	local sid = idx and GetSpecializationInfo and GetSpecializationInfo(idx)
	print(P .. "arbre dominant=" .. tostring(idx) .. "  specID deduit=" .. tostring(sid))
	print(P .. "cle de spe=" .. tostring(ns.Auras and ns.Auras.GetSpecKey and ns.Auras.GetSpecKey()))
	local CLR = ns.Modules and ns.Modules.Colors
	local c = CLR and CLR.Get and CLR.Get("powercircle")
	print(P .. "couleur powercircle=" .. (c and string.format("%.2f/%.2f/%.2f", c[1] or 0, c[2] or 0, c[3] or 0) or "nil"))
end

-- Identite d'un sort, independamment de son rang : nom + icone. Deux rangs la partagent, deux
-- sorts homonymes sans rapport presque jamais. nil si le nom est illisible.
function ns.SpellIdentityKey(id)
  if not id then return nil end
  local name, icon
  if C_Spell then
    if C_Spell.GetSpellName then
      local ok, n = pcall(C_Spell.GetSpellName, id)
      if ok then name = n end
    end
    if C_Spell.GetSpellTexture then
      local ok, t = pcall(C_Spell.GetSpellTexture, id)
      if ok then icon = t end
    end
  end
  if not name then return nil end
  return name .. "\0" .. tostring(icon)
end

-- Regroupement des rangs d'un meme sort. Sur les clients ou les sorts se montent en rang, chaque
-- rang porte son propre spellID tout en designant le meme sort : les listes de selection affichent
-- alors autant de lignes identiques qu'il y a de rangs appris.
-- Critere : meme nom ET meme icone. Le nom seul fusionnerait des sorts sans rapport qui partagent
-- un libelle generique ; deux rangs, eux, ne different que par leurs chiffres.
-- On conserve le spellID le PLUS ELEVE, c'est-a-dire le rang le plus haut : c'est celui que le
-- joueur lance, donc celui dont le cout, la portee et l'utilisabilite sont pertinents.
-- getID permet de traiter aussi bien une liste d'IDs qu'une liste de tables {id=...}.
function ns.DedupeSpellRanks(list, getID, setID)
  if type(list) ~= "table" then return list end
  getID = getID or function(v) return v end

  local SpellKey = ns.SpellIdentityKey

  local out, slotOfKey = {}, {}
  for _, item in ipairs(list) do
    local id = getID(item)
    local key = SpellKey(id)
    if not key then
      -- Nom illisible : on garde l'entree telle quelle plutot que de la perdre.
      out[#out + 1] = item
    else
      local at = slotOfKey[key]
      if not at then
        slotOfKey[key] = #out + 1
        out[#out + 1] = item
      else
        -- Doublon : on garde la position d'origine mais on remonte au rang le plus eleve.
        local keptID = getID(out[at])
        if id and keptID and id > keptID then
          if setID then setID(out[at], id) else out[at] = item end
        end
      end
    end
  end
  return out
end

-- Références vers les modules (remplies par chaque module)
ns.Modules = {}

-- Référence vers la config (remplie par Defaults.lua)
ns.Defaults = {}
ns.DB = {}  -- sera rempli par la SavedVariable au login

-- Reserve certains reglages (couleurs de cast par ecole, monture Vol Ascendant)
-- aux profils ayant le champ racine kfe2pr_tmtc dans le SavedVariables original.
function ns.HasHeroicFeatures()
  return AishaddonDB ~= nil and AishaddonDB.kfe2pr_tmtc == true
end

-- Marqueur discret sur les screenshots : 2e "." apres le "v" si kfe2pr_tmtc present
function ns.GetVersionString()
  local dots = (ns.HasHeroicFeatures and ns.HasHeroicFeatures()) and ".." or "."
  return "v" .. dots .. tostring(ns.addonVersion or "?")
end

-- Logo de marque : variante "hollow" AishUI sur les versions Ko-fi (cf. HasHeroicFeatures),
-- AishCore sinon. Resolu a l'appel, pas au chargement : AishaddonDB n'existe pas encore
-- quand les fichiers de l'addon sont executes. Ne concerne pas l'icone de minimap.
function ns.GetBrandLogoPath()
  local heroic = ns.HasHeroicFeatures and ns.HasHeroicFeatures()
  return "Interface\\AddOns\\AishCore\\Media\\Logo\\" .. (heroic and "aishui_hollow" or "aishcore_hollow")
end

-- Fond plein place DERRIERE le logo ajoure et teinte avec la couleur "powercircle"
-- du module Couleurs. Une seule image pour les deux variantes : les deux logos
-- partagent la meme silhouette.
function ns.GetBrandLogoBgPath()
  return "Interface\\AddOns\\AishCore\\Media\\Logo\\aishui_hollow_bg"
end

--- Couleur "powercircle" de la spe active, pour teinter ce fond. Blanc si le module
--- Couleurs n'est pas encore charge.
function ns.GetBrandLogoBgColor()
  local CLR = ns.Modules and ns.Modules.Colors
  local c = CLR and CLR.Get and CLR.Get("powercircle")
  return c or { 1, 1, 1, 1 }
end

-- Specialisations qui jouent sur des cibles alliees. Le role Blizzard "HEALER" les
-- couvre toutes sauf Augmentation (1473), classee DAMAGER mais qui cible ses allies.
local HEALER_LIKE_SPECS = { [1473] = true }

--- Vrai en spe de soin (ou assimilee, cf. HEALER_LIKE_SPECS).
function ns.IsHealerLikeSpec()
  local idx = GetSpecialization and GetSpecialization()
  if not idx or idx == 0 then return false end
  if GetSpecializationRole and GetSpecializationRole(idx) == "HEALER" then return true end
  local specID = ns._specID
  if not specID and GetSpecializationInfo then
    specID = select(1, GetSpecializationInfo(idx))
  end
  return (specID and HEALER_LIKE_SPECS[specID]) and true or false
end

--- Regle commune du mode de visibilite "Cible uniquement" (Barres de vie, Cercle
--- central, Barre de rotation, Bouton de rotation) :
---   - en combat : visible meme sans cible ;
---   - hors combat : visible seulement si la cible est attaquable ;
---   - hors combat en spe de soin : visible quelle que soit la cible (leur cible
---     naturelle est un allie, la condition "attaquable" les masquerait en permanence).
function ns.ShouldShowForTargetMode()
  if UnitAffectingCombat("player") then return true end
  if ns.IsHealerLikeSpec() then return true end
  return UnitExists("target")
     and not UnitIsDeadOrGhost("target")
     and UnitCanAttack("player", "target") and true or false
end

-- Registre d'evenements internes leger (pub/sub)
local CallbackRegistry = {}
CallbackRegistry.events = {}
ns.CallbackRegistry = CallbackRegistry

function CallbackRegistry:Register(event, func, owner)
  if not self.events[event] then self.events[event] = {} end
  table.insert(self.events[event], { func = func, owner = owner })
end

function CallbackRegistry:Trigger(event, ...)
  if not self.events[event] then return end
  for _, cb in ipairs(self.events[event]) do
    if cb.owner then
      cb.func(cb.owner, ...)
    else
      cb.func(...)
    end
  end
end

-- Accesseur config : DB d'abord, sinon Defaults
function ns.GetCfg(key)
  if ns.DB and ns.DB[key] ~= nil then return ns.DB[key] end
  return ns.Defaults[key]
end

-- Prefixe une cle "resourceCircle" pour la rendre specifique a la spec active
function ns.SecResSpecKey(baseKey, specID)
  specID = specID or ns._specID
  return specID and ("secRes_" .. specID .. "_" .. baseKey) or baseKey
end

-- Lit un reglage "resourceCircle" spec-specifique, retombe sur la cle plate partagee
function ns.GetSecResCfg(baseKey, specID)
  local cfg = ns.GetCfg("resourceCircle")
  if not cfg then return nil end
  local v = cfg[ns.SecResSpecKey(baseKey, specID)]
  if v == nil then v = cfg[baseKey] end
  return v
end

-- Règle commune "tooltip en combat seulement avec ALT" (PriorityBar + Auras)
function ns.ShouldShowSpellTooltip()
  local cfg = ns.GetCfg("priorityBar")
  if not (cfg and cfg.tooltipAltCombatOnly) then return true end
  if not UnitAffectingCombat("player") then return true end
  return IsAltKeyDown()
end

-- Table de correspondance lettre accentuée -> lettre de base ASCII, pour le tri alphabétique
local ACCENT_FOLD = {
  ["\195\128"]="A", ["\195\129"]="A", ["\195\130"]="A", ["\195\131"]="A", ["\195\132"]="A", ["\195\133"]="A", -- À Á Â Ã Ä Å
  ["\195\135"]="C", -- Ç
  ["\195\136"]="E", ["\195\137"]="E", ["\195\138"]="E", ["\195\139"]="E", -- È É Ê Ë
  ["\195\140"]="I", ["\195\141"]="I", ["\195\142"]="I", ["\195\143"]="I", -- Ì Í Î Ï
  ["\195\145"]="N", -- Ñ
  ["\195\146"]="O", ["\195\147"]="O", ["\195\148"]="O", ["\195\149"]="O", ["\195\150"]="O", -- Ò Ó Ô Õ Ö
  ["\195\153"]="U", ["\195\154"]="U", ["\195\155"]="U", ["\195\156"]="U", -- Ù Ú Û Ü
  ["\195\157"]="Y", -- Ý
  ["\195\160"]="a", ["\195\161"]="a", ["\195\162"]="a", ["\195\163"]="a", ["\195\164"]="a", ["\195\165"]="a", -- à á â ã ä å
  ["\195\167"]="c", -- ç
  ["\195\168"]="e", ["\195\169"]="e", ["\195\170"]="e", ["\195\171"]="e", -- è é ê ë
  ["\195\172"]="i", ["\195\173"]="i", ["\195\174"]="i", ["\195\175"]="i", -- ì í î ï
  ["\195\177"]="n", -- ñ
  ["\195\178"]="o", ["\195\179"]="o", ["\195\180"]="o", ["\195\181"]="o", ["\195\182"]="o", -- ò ó ô õ ö
  ["\195\185"]="u", ["\195\186"]="u", ["\195\187"]="u", ["\195\188"]="u", -- ù ú û ü
  ["\195\189"]="y", -- ý
}

-- Remplace les accents par leur lettre de base + minuscules, pour comparaison ASCII simple
function ns.FoldAccentsLower(str)
  if not str or str == "" then return "" end
  local ok, folded = pcall(string.gsub, str, "\195[\128-\191]", ACCENT_FOLD)
  return string.lower(ok and folded or str)
end

-- Ne rend le conteneur d'auras cliquable que pendant ALT (evite qu'il capte le survol
-- en permanence), sauf pendant un drag actif (frame._aishDragging).
function ns.EnableMouseOnlyOnAlt(frame)
  frame:EnableMouse(IsAltKeyDown())
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("MODIFIER_STATE_CHANGED")
  watcher:SetScript("OnEvent", function()
    if frame._aishDragging then return end
    frame:EnableMouse(IsAltKeyDown())
  end)
end

-- Police de repli universelle : 2002.TTF est livree par le client dans TOUTES les
-- locales, donc aucune dependance externe a installer.
ns.FONT_FALLBACK = "Fonts\\2002.TTF"

-- Chemins media (jamais de police SharedMedia en dur : la media pack peut etre absente)
ns.Media = {
  circle      = "Interface\\AddOns\\AishCore\\Media\\Wheel\\circleflat2.tga",
  font        = ns.FONT_FALLBACK,
  fontGui     = "Fonts\\FRIZQT__.TTF",
  fontTitle   = "Fonts\\FRIZQT__.TTF",
  -- Texture de repli des StatusBar : native au client, jamais manquante.
  fallbackBar = "Interface\\TargetingFrame\\UI-StatusBar",
}

-- Texture de barre par defaut : "Flat (WoW)" (Interface\\Buttons\\WHITE8X8),
-- native au client donc jamais manquante. Cle de ns.BAR_TEXTURES (cf. plus bas), pas un chemin.
ns.BAR_TEXTURE_DEFAULT = "flat"

-- ============================================================
-- RACCOURCIS CLAVIER DES BARRES D'ACTION
-- Partage par RotationHelper et PriorityBar : retrouve la touche assignee a un sort
-- en le localisant sur une barre d'action.
-- ============================================================

-- Barres Blizzard / ABE, puis barres ElvUI (memes boutons securises, autre nommage).
-- Les prefixes ElvUI sont presents inconditionnellement : sans ElvUI, _G[...] renvoie
-- nil et le scan les ignore, donc la detection des barres classiques reste intacte.
ns.ACTION_BUTTON_PREFIXES = {
  "ActionButton",
  "MultiBarBottomLeftButton",
  "MultiBarBottomRightButton",
  "MultiBarRightButton",
  "MultiBarLeftButton",
  "MultiBar5Button",
  "MultiBar6Button",
  "MultiBar7Button",
}
for bar = 1, 15 do
  ns.ACTION_BUTTON_PREFIXES[#ns.ACTION_BUTTON_PREFIXES + 1] = "ElvUI_Bar" .. bar .. "Button"
end

-- Binding associe a chaque prefixe, utilise seulement en repli quand le FontString
-- HotKey du bouton est vide (texte des raccourcis desactive dans les options).
local ACTION_BUTTON_BINDINGS = {
  ActionButton              = "ACTIONBUTTON",
  MultiBarBottomLeftButton  = "MULTIACTIONBAR1BUTTON",
  MultiBarBottomRightButton = "MULTIACTIONBAR2BUTTON",
  MultiBarRightButton       = "MULTIACTIONBAR3BUTTON",
  MultiBarLeftButton        = "MULTIACTIONBAR4BUTTON",
  MultiBar5Button           = "MULTIACTIONBAR5BUTTON",
  MultiBar6Button           = "MULTIACTIONBAR6BUTTON",
  MultiBar7Button           = "MULTIACTIONBAR7BUTTON",
}

-- GetMacroSpell suit le sort d'une macro mono-sort (healers) -- GetActionInfo seul ne le resout pas.
local GetMacroSpellID = (C_Macro and C_Macro.GetMacroSpell) or GetMacroSpell

--- SpellID porte par un bouton d'action (slot d'action, sinon methode GetSpellID des boutons TWW,
--- sinon macro mono-sort).
function ns.GetActionButtonSpellID(button)
  if not button then return nil end
  local action = button.action
  local aType, aId
  if action and type(action) == "number" then
    local ok
    ok, aType, aId = pcall(GetActionInfo, action)
    if ok and aType == "spell" and aId and aId > 0 then return aId end
  end
  if button.GetSpellID then
    local ok, sid = pcall(button.GetSpellID, button)
    if ok and sid and type(sid) == "number" and sid > 0 then return sid end
  end
  if aType == "macro" and aId and GetMacroSpellID then
    local ok, macroSid = pcall(GetMacroSpellID, aId)
    if ok and macroSid and macroSid > 0 then return macroSid end
  end
  return nil
end

--- Texte du raccourci d'un bouton. Le FontString HotKey est prioritaire : deja abrege,
--- correct en page de barre alternative, et il respecte les abreviations d'ElvUI. S'il est
--- vide, on resout le binding -- ElvUI expose son nom exact via keyBoundTarget
--- ("ELVUIBAR2BUTTON1"..., mais "ACTIONBUTTON1" pour sa barre 1).
function ns.GetActionButtonKeybindText(button, prefix, index)
  if not button then return nil end
  if button.HotKey then
    local ok, txt = pcall(button.HotKey.GetText, button.HotKey)
    if ok and txt and txt ~= "" and txt ~= RANGE_INDICATOR then
      return txt
    end
  end
  local action = button.keyBoundTarget or button.bindingAction
  if not action then
    local base = ACTION_BUTTON_BINDINGS[prefix]
    if base then action = base .. index end
  end
  if type(action) ~= "string" then return nil end
  local key = GetBindingKey(action)
  if not key or key == "" then return nil end
  local abbrev = GetBindingText(key, "KEY_", 1)
  return (abbrev ~= "" and abbrev) or key
end

-- Sort de base d'un ID : l'assistant de rotation renvoie parfois un override (talent,
-- forme, aura) alors que la barre porte le sort de base, et inversement.
local function GetBaseSpell(spellID)
  if not spellID then return nil end
  if FindBaseSpellByID then
    local ok, base = pcall(FindBaseSpellByID, spellID)
    if ok and base and base > 0 then return base end
  end
  return spellID
end

-- INDEX INVERSE spellID -> touche.
--
-- Une seule passe sur les barres construit la table pour TOUS les sorts qui s'y trouvent,
-- au lieu de relancer un balayage complet par sort interroge. Le cout d'une invalidation
-- ne depend donc plus du nombre de sorts affiches : ~280 lectures _G une fois, puis toutes
-- les consultations sont en O(1), y compris les sorts absents des barres (nil immediat,
-- sans rebalayage).
--
-- Priorite aux boutons VISIBLES : avec ElvUI les boutons Blizzard existent toujours mais
-- sont masques, et porteraient un binding different. Une entree issue d'un bouton masque
-- n'est donc jamais ecrasee par une autre, et ne peut jamais ecraser une entree visible.
local _keybindIndex = {}      -- [spellID] = texte de la touche
local _fromVisible  = {}      -- [spellID] = true si l'entree vient d'un bouton visible
local _indexDirty   = true
local _lastBuild    = 0

local function IndexButton(spellID, txt, visible)
  if not spellID then return end
  if _keybindIndex[spellID] and (_fromVisible[spellID] or not visible) then return end
  _keybindIndex[spellID] = txt
  _fromVisible[spellID] = visible or nil
end

local function BuildKeybindIndex()
  wipe(_keybindIndex)
  wipe(_fromVisible)
  local found = 0
  for _, prefix in ipairs(ns.ACTION_BUTTON_PREFIXES) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button then
        local sid = ns.GetActionButtonSpellID(button)
        if sid then
          local txt = ns.GetActionButtonKeybindText(button, prefix, i)
          if txt then
            local visible = button:IsVisible()
            IndexButton(sid, txt, visible)
            -- Le sort de base est indexe en plus : l'assistant de rotation renvoie
            -- parfois un override (talent, forme, aura) la ou la barre porte la base.
            local base = GetBaseSpell(sid)
            if base ~= sid then IndexButton(base, txt, visible) end
            found = found + 1
          end
        end
      end
    end
  end
  _indexDirty = false
  _lastBuild = GetTime()
  -- Index vide : les barres ne sont probablement pas encore creees (login, ElvUI pas
  -- charge). On se remet en "sale" pour retenter, avec un delai plancher pour ne pas
  -- rebalayer a chaque tick sur un personnage aux barres reellement vides.
  if found == 0 then _indexDirty = true end
end

--- Invalide l'index des raccourcis. Appele par les evenements de barre/binding, et
--- directement par les modules qui reagissent aux memes evenements (l'ordre de
--- declenchement entre plusieurs frames n'est pas garanti).
function ns.InvalidateKeybindCache()
  _indexDirty = true
  -- Remet le compteur a zero : le delai plancher ne concerne QUE la retentative d'un
  -- index vide, jamais une invalidation reelle, qui doit etre prise en compte tout de suite.
  _lastBuild = 0
end

do
  local f = CreateFrame("Frame")
  for _, ev in ipairs({
    "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "PLAYER_ENTERING_WORLD", "ACTIVE_TALENT_GROUP_CHANGED",
  }) do
    f:RegisterEvent(ev)
  end
  f:SetScript("OnEvent", ns.InvalidateKeybindCache)
end

--- Touche assignee a `spellID`, ou nil si le sort n'est sur aucune barre.
function ns.GetKeybindForSpell(spellID)
  if not spellID then return nil end
  if _indexDirty and (GetTime() - _lastBuild) > 0.5 then
    BuildKeybindIndex()
  end
  local txt = _keybindIndex[spellID]
  if txt then return txt end
  local base = GetBaseSpell(spellID)
  if base ~= spellID then return _keybindIndex[base] end
  return nil
end

--- Applique police/taille/couleur/position d'un FontString de raccourci depuis `cfg`,
--- avec le prefixe de cles `keybind*`. SetFont est protege : un chemin mort (media pack
--- desinstallee, profil importe) interromprait sinon la creation du frame appelant.
function ns.ApplyKeybindFontString(fs, anchorTo, cfg)
  if not fs or not cfg then return end
  local pos = cfg.keybindPosition or "TOP"
  fs:ClearAllPoints()
  fs:SetPoint(pos, anchorTo, pos, cfg.keybindOffsetX or 0, cfg.keybindOffsetY or 0)
  local path = cfg.keybindFont or ns.FONT_FALLBACK
  local size = cfg.keybindFontSize or 12
  if not pcall(fs.SetFont, fs, path, size, "OUTLINE") then
    fs:SetFont(ns.FONT_FALLBACK, size, "OUTLINE")
  end
  local c = cfg.keybindColor or { 1, 1, 1, 1 }
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end


-- Validation des chemins de police. FontString:SetFont() leve une erreur Lua quand le
-- fichier est absent (media pack desinstallee, profil importe d'un autre setup...) : la
-- creation du frame appelant est alors interrompue en plein milieu, d'ou les cascades
-- "attempt to index field 'text' (a nil value)". On teste chaque chemin une seule fois
-- sur un FontString jetable, resultat memorise.
local _fontProbe
local _fontValidCache = {}
function ns.IsFontValid(path)
  if type(path) ~= "string" or path == "" then return false end
  local cached = _fontValidCache[path]
  if cached ~= nil then return cached end
  if not _fontProbe then
    _fontProbe = UIParent:CreateFontString(nil, "BACKGROUND")
    _fontProbe:Hide()
  end
  -- Selon les builds, un asset invalide leve une erreur OU renvoie false : on couvre les deux.
  local ok, ret = pcall(_fontProbe.SetFont, _fontProbe, path, 12, "")
  ok = ok and (ret ~= false)
  _fontValidCache[path] = ok
  return ok
end

--- Retourne `path` s'il est reellement chargeable, sinon la police du jeu (2002).
function ns.SafeFontPath(path)
  if ns.IsFontValid(path) then return path end
  return ns.FONT_FALLBACK
end

--- Normalise la casse des chemins de police dans `tbl` (recursif).
---
--- Cette fonction REMPLACAIT auparavant toute police jugee non chargeable par la police
--- du jeu. C'etait une mauvaise idee : la sonde ns.IsFontValid produit des faux negatifs,
--- et le verdict etait ecrit dans le profil SAUVEGARDE -- une police parfaitement valide
--- pouvait donc etre effacee definitivement du choix de l'utilisateur. On ne touche plus
--- qu'a la casse, ce qui est sans risque et evite un doublon dans les menus. La protection
--- contre un chemin mort reste entiere a l'application (SetFont est enveloppe dans un
--- pcall avec repli, cf. ns.ApplyTextOutlineStyle / ns.ApplyFont).
local BROKEN_2002 = "Fonts" .. string.char(200) .. "2.TTF"

function ns.SanitizeFontPaths(tbl, _seen)
  if type(tbl) ~= "table" then return end
  _seen = _seen or {}
  if _seen[tbl] then return end
  _seen[tbl] = true
  local fallbackLower = string.lower(ns.FONT_FALLBACK)
  for k, v in pairs(tbl) do
    local tv = type(v)
    if tv == "table" then
      ns.SanitizeFontPaths(v, _seen)
    elseif tv == "string" and v == BROKEN_2002 then
      -- Valeur ecrite par un defaut mal echappe : un seul antislash dans la source Lua
      -- fait lire \\200 comme un escape decimal (caractere 200), d'ou un chemin
      -- illisible dans les dropdowns et un SetFont en echec. Reparation ciblee : cette
      -- chaine exacte ne peut venir de nulle part ailleurs.
      tbl[k] = ns.FONT_FALLBACK
    elseif tv == "string" and v ~= ns.FONT_FALLBACK and string.lower(v) == fallbackLower then
      -- Meme police, autre casse (vieux profils ecrits avec "Fonts\\2002.ttf") : on
      -- normalise, sinon le dropdown ne retrouve pas la valeur et affiche du vide.
      tbl[k] = ns.FONT_FALLBACK
    end
  end
end

-- Bar textures (~45)
ns.BAR_TEXTURES = {
    { value = "aish_grad",   text = "Aish Gradient",     path = "Interface\\AddOns\\AishCore\\Media\\Statusbars\\aish_gradient" },
    { value = "aish_grad2",  text = "Aish Gradient 2",   path = "Interface\\AddOns\\AishCore\\Media\\Statusbars\\aish_gradient2" },
    { value = "aish_grad3",  text = "Aish Gradient 3",   path = "Interface\\AddOns\\AishCore\\Media\\Statusbars\\aish_gradient3" },
    { value = "aish_fx",     text = "Aish Effect",       path = "Interface\\AddOns\\AishCore\\Media\\Statusbars\\aish_effect" },
    { value = "aish_fx2",    text = "Aish Effect 2",     path = "Interface\\AddOns\\AishCore\\Media\\Statusbars\\aish_effect2" },
    { value = "toxiui",     text = "ToxiUI Clean",     path = "Interface\\AddOns\\SharedMedia_MyMedia\\statusbar\\ToxiUI-clean.tga", lsm = "ToxiUI-clean", addon = "SharedMedia_MyMedia" },
    { value = "charcoal",   text = "Charcoal",          lsm = "Charcoal" },
    { value = "elvui",      text = "ElvUI Norm1",       lsm = "ElvUI Norm1" },
    { value = "samw00",     text = "Samw00",            lsm = "Samw00" },
    { value = "flat",       text = "Flat (WoW)",        path = "Interface\\Buttons\\WHITE8X8" },
    { value = "statusbar",  text = "StatusBar (WoW)",   path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { value = "aluminium",  text = "Aluminium",         lsm = "Aluminium" },
    { value = "armory",     text = "Armory",            lsm = "Armory" },
    { value = "blizzard",   text = "Blizzard",          path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { value = "cloud",      text = "Cloud",             lsm = "Cloud" },
    { value = "comet",      text = "Comet",             lsm = "Comet" },
    { value = "dabs",       text = "Dabs",              lsm = "Dabs" },
    { value = "darkbottom", text = "DarkBottom",        lsm = "DarkBottom" },
    { value = "diagonal",   text = "Diagonal",          lsm = "Diagonal" },
    { value = "elv_gloss",  text = "ElvUI Gloss",       lsm = "ElvUI Gloss" },
    { value = "elv_melli",  text = "ElvUI Melli",       lsm = "ElvUI Melli" },
    { value = "falcon",     text = "Falcon",            lsm = "Falcon" },
    { value = "glaze",      text = "Glaze",             lsm = "Glaze" },
    { value = "gloss",      text = "Gloss",             lsm = "Gloss" },
    { value = "gradient",   text = "Gradient",          lsm = "Gradient" },
    { value = "litestep",   text = "LiteStep",          lsm = "LiteStep" },
    { value = "lyfe",       text = "Lyfe",              lsm = "Lyfe" },
    { value = "melli",      text = "Melli",             lsm = "Melli" },
    { value = "minimalist", text = "Minimalist",        lsm = "Minimalist" },
    { value = "normtex",    text = "NormTex",           lsm = "normTex" },
    { value = "otravi",     text = "Otravi",            lsm = "Otravi" },
    { value = "outline",    text = "Outline",           lsm = "Outline" },
    { value = "perl",       text = "Perl",              lsm = "Perl" },
    { value = "rain",       text = "Rain",              lsm = "Rain" },
    { value = "round",      text = "Round",             lsm = "Round" },
    { value = "ruben",      text = "Ruben",             lsm = "Ruben" },
    { value = "skullflower",text = "Skullflower",       lsm = "Skullflower" },
    { value = "smooth",     text = "Smooth",            lsm = "Smooth" },
    { value = "smooth_v2",  text = "Smooth v2",         lsm = "Smooth v2" },
    { value = "steel",      text = "Steel",             lsm = "Steel" },
    { value = "striped",    text = "Striped",           lsm = "Striped" },
    { value = "tube",       text = "Tube",              lsm = "Tube" },
    { value = "water",      text = "Water",             lsm = "Water" },
    { value = "wglass",     text = "WGlass",            lsm = "WGlass" },
    { value = "wisps",      text = "Wisps",             lsm = "Wisps" },
}

local function GetLSM()
    local ok, LSM = pcall(function()
        return LibStub and LibStub("LibSharedMedia-3.0", true)
    end)
    return ok and LSM or nil
end

--- Une entree de ns.BAR_TEXTURES est utilisable si LSM sait la resoudre, ou si son
--- `path` est reellement present (bundlee dans AishCore, native au client, ou fournie
--- par un addon declare via `addon` ET charge).
local function BarTexEntryPath(entry, LSM)
    if entry.lsm then
        local p = LSM and LSM:Fetch("statusbar", entry.lsm, true)
        if p then return p end
    end
    if entry.path then
        -- `addon` = media pack tierce : sans elle le fichier n'existe pas, la barre
        -- s'afficherait vide (SetStatusBarTexture echoue en silence).
        if entry.addon and not (C_AddOns and C_AddOns.IsAddOnLoaded
                                and C_AddOns.IsAddOnLoaded(entry.addon)) then
            return nil
        end
        return entry.path
    end
    return nil
end

-- Resout une texture via LSM, avec repli sur la texture native du client.
function ns.ResolveLSMTexture(entry)
    return BarTexEntryPath(entry, GetLSM()) or ns.Media.fallbackBar
end

local function FindBarTexEntry(texKey)
    if not texKey then return nil end
    for _, e in ipairs(ns.BAR_TEXTURES) do
        if e.value == texKey then return e end
    end
    return nil
end

--- Chemin de texture pour une cle de ns.BAR_TEXTURES. Une cle inconnue, ou connue mais
--- devenue introuvable (media pack desinstallee), retombe sur la texture par defaut.
function ns.ResolveBarTexFromKey(texKey)
    local LSM = GetLSM()
    local entry = FindBarTexEntry(texKey)
    local path = entry and BarTexEntryPath(entry, LSM)
    if path then return path end
    local def = FindBarTexEntry(ns.BAR_TEXTURE_DEFAULT)
    return (def and BarTexEntryPath(def, LSM)) or ns.Media.fallbackBar
end

-- Liste utilisable par les dropdowns : on ecarte les entrees qu'on ne sait pas resoudre.
-- Les textures bundlees dans AishCore sont toujours la ; celles marquees `lsm`
-- n'apparaissent que si LibSharedMedia les fournit -- c'est le bonus pour qui installe
-- une media pack (SharedMedia, SharedMedia_MyMedia, ElvUI...).
local _barTexListCache
function ns.GetBarTextureList()
    if _barTexListCache then return _barTexListCache end
    local LSM = GetLSM()
    local out, complete = {}, true
    for _, e in ipairs(ns.BAR_TEXTURES) do
        if BarTexEntryPath(e, LSM) then
            out[#out + 1] = { value = e.value, text = e.text }
        else
            complete = false
        end
    end
    if #out == 0 then
        out[1] = { value = ns.BAR_TEXTURE_DEFAULT, text = "Flat (WoW)" }
    end
    -- LSM peut encore se charger apres nous : on ne met en cache que si la liste est
    -- complete, sinon on reconstruit au prochain appel.
    if complete then _barTexListCache = out end
    return out
end

-- Filtrage trilineaire (mipmaps) : réduit l'aliasing sur les cercles minifiés
function ns.SetSmoothTexture(texture, path)
  if not texture or not texture.SetTexture then return end
  texture:SetTexture(path, nil, nil, "TRILINEAR")
end

-- ============================================================
-- FOND DE TEXTE (cercle central + cercle de vie hors combat)
-- Petit cache sombre pose sous le texte pour le detacher de l'arc. Il est noir sur un
-- fond noir : invisible tant qu'on ne le regle pas. D'ou ce halo, allume le temps du
-- reglage dans le panneau, qui en revele le contour.
-- ============================================================
local TEXT_BACKDROP_GLOW_RATIO = 1.9   -- diametre du halo / diametre du cache
local TEXT_BACKDROP_GLOW_HOLD  = 2.0   -- secondes d'affichage apres le dernier reglage

--- Halo de reperage, a poser sous le cache (meme frame, sous-niveau inferieur).
function ns.CreateTextBackdropGlow(parent, anchor)
  local glow = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
  ns.SetSmoothTexture(glow, "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga")
  glow:SetBlendMode("ADD")
  glow:SetDesaturated(true)
  -- Blanc volontairement neutre : le halo doit trancher sur n'importe quelle couleur de
  -- spec, il ne suit donc pas le theme.
  glow:SetVertexColor(1, 1, 1, 1)
  glow:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  glow:Hide()
  return glow
end

function ns.SizeTextBackdropGlow(glow, backdropPx)
  if not glow then return end
  local px = math.max(1, (backdropPx or 0) * TEXT_BACKDROP_GLOW_RATIO)
  glow:SetSize(px, px)
end

-- Minuteurs indexes par texture, table faible : un halo detruit avec son cercle ne
-- retient pas son minuteur.
local _glowTimers = setmetatable({}, { __mode = "k" })

--- Allume le halo, et l'eteint apres un delai sans nouveau reglage.
function ns.FlashTextBackdropGlow(glow)
  if not glow then return end
  glow:Show()
  glow:SetAlpha(0.9)
  local t = _glowTimers[glow]
  if t then t:Cancel() end
  _glowTimers[glow] = C_Timer.NewTimer(TEXT_BACKDROP_GLOW_HOLD, function()
    _glowTimers[glow] = nil
    glow:Hide()
  end)
end

--- Eteint le halo tout de suite (fermeture du panneau, changement de page).
function ns.HideTextBackdropGlow(glow)
  if not glow then return end
  local t = _glowTimers[glow]
  if t then t:Cancel(); _glowTimers[glow] = nil end
  glow:Hide()
end

-- Idem pour une StatusBar : repasse par GetStatusBarTexture() (SetStatusBarTexture n'a pas de filterMode)
function ns.SetSmoothStatusBarTexture(bar, path)
  if not bar then return end
  bar:SetStatusBarTexture(path)
  local tex = bar:GetStatusBarTexture()
  ns.SetSmoothTexture(tex, path)
end

-- Liste shared des fonts disponibles dans les dropdowns de sélection (SettingsPanel)
-- Triée par ordre alphabétique (text)
local _SM = "Interface\\AddOns\\SharedMedia_MyMedia\\font\\"
ns.FONT_LIST = {
  { value = ns.FONT_FALLBACK,                        text = "2002 (WoW)"                    },
  { value = _SM.."AccidentalPresidency.ttf",         text = "Accidental Presidency"         },
  { value = "Fonts\\ARIALN.TTF",                     text = "Arial Narrow (WoW)"            },
  { value = _SM.."BebasNeue-Regular.ttf",            text = "Bebas Neue"                    },
  { value = _SM.."FiraMono-Medium.ttf",              text = "Fira Mono Medium"              },
  { value = _SM.."FiraSans-Black.ttf",               text = "Fira Sans Black"               },
  { value = _SM.."FiraSansCondensed-Black.ttf",      text = "Fira Sans Condensed Black"     },
  { value = _SM.."FiraSansCondensed-Medium.ttf",     text = "Fira Sans Condensed Medium"    },
  { value = _SM.."FiraSans-Medium.ttf",              text = "Fira Sans Medium"              },
  { value = _SM.."Fontin-Bold.ttf",                  text = "Fontin Bold"                   },
  { value = _SM.."Fontin-Italic.ttf",                text = "Fontin Italic"                 },
  { value = _SM.."Fontin-Regular.ttf",               text = "Fontin Regular"                },
  { value = _SM.."Fontin-SmallCaps.ttf",             text = "Fontin Small Caps"             },
  { value = _SM.."FORCED SQUARE.ttf",                text = "Forced Square"                 },
  { value = "Fonts\\FRIZQT__.TTF",                   text = "Friz Quadrata (WoW)"           },
  { value = _SM.."HARRYP__.TTF",                     text = "Harry Potter"                  },
  { value = _SM.."HomespunUPPERCASE.ttf",            text = "Homespun Uppercase"            },
  { value = _SM.."imagine_font.ttf",                 text = "Imagine"                       },
  { value = _SM.."Montserrat.ttf",                   text = "Montserrat"                    },
  { value = _SM.."Montserrat-Bold.ttf",              text = "Montserrat Bold"               },
  { value = _SM.."Montserrat-BoldItalic.ttf",        text = "Montserrat Bold Italic"        },
  { value = _SM.."Montserrat-ExtraLight.ttf",        text = "Montserrat ExtraLight"         },
  { value = _SM.."Montserrat-ExtraLightItalic.ttf",  text = "Montserrat ExtraLight Italic"  },
  { value = _SM.."Montserrat-Medium.ttf",            text = "Montserrat Medium"             },
  { value = _SM.."Montserrat-MediumItalic.ttf",      text = "Montserrat Medium Italic"      },
  { value = _SM.."Montserrat-Regular.ttf",           text = "Montserrat Regular"            },
  { value = _SM.."Montserrat-SemiBold.ttf",          text = "Montserrat SemiBold"           },
  { value = _SM.."Montserrat-SemiBoldItalic.ttf",    text = "Montserrat SemiBold Italic"    },
  { value = "Fonts\\MORPHEUS.ttf",                   text = "Morpheus (WoW)"                },
  { value = _SM.."Nueva Std Cond.ttf",               text = "Nueva Std Condensed"           },
  { value = _SM.."OblikCaps.ttf",                    text = "Oblik Caps"                    },
  { value = _SM.."Oswald-Regular.ttf",               text = "Oswald Regular"                },
  { value = _SM.."PTSansNarrow-Regular.ttf",         text = "PT Sans Narrow"                },
  { value = _SM.."PTSansNarrow-Bold.ttf",            text = "PT Sans Narrow Bold"           },
  { value = _SM.."PTSans-NarrowUppercase.ttf",       text = "PT Sans Narrow Majuscules"     },
  { value = _SM.."Roadway.ttf",                      text = "Roadway"                       },
  { value = "Fonts\\SKURRI.TTF",                     text = "Skurri (WoW)"                  },
  { value = _SM.."TrashHand.TTF",                    text = "Trash Hand"                    },
  { value = _SM.."vibrocentric bd.ttf",              text = "Vibrocentric Bold"             },
  { value = _SM.."vibrocentric bd it.ttf",           text = "Vibrocentric Bold Italic"      },
  { value = _SM.."vibrocentric rg.ttf",              text = "Vibrocentric Regular"          },
  { value = _SM.."vibrocentric rg it.ttf",           text = "Vibrocentric Regular Italic"   },
}

-- Retourne la liste des polices depuis LibSharedMedia-3.0 si disponible,
-- sinon fallback sur la liste hardcodee ci-dessus.
--
-- ATTENTION : ne JAMAIS filtrer cette liste avec ns.IsFontValid(). La sonde produit des
-- faux negatifs (fichier pas encore accessible selon le moment de l'appel, media pack
-- enregistree dans LSM apres nous, SetFont qui renvoie false a chaud) et son resultat est
-- memorise pour toute la session. Une entree ecartee a tort disparaissait donc
-- definitivement du menu : des polices parfaitement installees (Bebas, Montserrat)
-- devenaient introuvables alors que les autres addons les utilisaient sans souci.
-- Appliquer une police cassee est deja sans danger (ApplyTextOutlineStyle et ns.ApplyFont
-- enveloppent SetFont dans un pcall avec repli), donc rien ne justifie de priver
-- l'utilisateur du choix.
local _fontListCache

--- Garantit la presence de la police du jeu dans la liste, meme si LSM ne la declare pas
--- (clients zhCN/zhTW). Purement additif : ne retire jamais aucune entree.
local function WithFallbackFont(list)
    local fallbackLower = string.lower(ns.FONT_FALLBACK)
    for _, entry in ipairs(list) do
        if string.lower(entry.value or "") == fallbackLower then return list end
    end
    table.insert(list, 1, { value = ns.FONT_FALLBACK, text = "2002 (WoW)" })
    return list
end

function ns.GetFontList()
    if _fontListCache then return _fontListCache end
    local ok, LSM = pcall(function()
        return LibStub and LibStub("LibSharedMedia-3.0", true)
    end)
    if ok and LSM then
        local names = LSM:List("font")
        if names and #names > 0 then
            table.sort(names)
            local list = {}
            for _, name in ipairs(names) do
                list[#list + 1] = { value = LSM:Fetch("font", name), text = name }
            end
            _fontListCache = WithFallbackFont(list)
            return _fontListCache
        end
    end
    -- LSM absent ou vide : liste hardcodee, non mise en cache (retry au prochain appel,
    -- LSM peut encore se charger).
    return WithFallbackFont(ns.FONT_LIST)
end

-- Style de contour de texte partagé : Fin/Epais (natifs) ou SLUG (anneau de 8 copies noires,
-- plus lisible que OUTLINE a petite taille).
local SLUG_RING_OFFSETS = {
    { -1, -1 }, { 0, -1 }, { 1, -1 },
    { -1,  0 },            { 1,  0 },
    { -1,  1 }, { 0,  1 }, { 1,  1 },
}

-- Construite paresseusement : L n'est pas encore rempli quand Core.lua s'execute
local _textOutlineStylesCache
function ns.GetTextOutlineStyles()
    if _textOutlineStylesCache then return _textOutlineStylesCache end
    if not (ns.L and ns.L["TEXT_OUTLINE_THIN"]) then
        -- L pas encore charge : liste non cachee, retry au prochain appel
        return {
            { value = "OUTLINE",      text = "Fin" },
            { value = "THICKOUTLINE", text = "Epais" },
            { value = "SLUG",         text = "SLUG" },
        }
    end
    _textOutlineStylesCache = {
        { value = "OUTLINE",      text = ns.L["TEXT_OUTLINE_THIN"] },
        { value = "THICKOUTLINE", text = ns.L["TEXT_OUTLINE_THICK"] },
        { value = "SLUG",         text = ns.L["TEXT_OUTLINE_SLUG"] },
    }
    return _textOutlineStylesCache
end

--- Cree 8 FontStrings d'ombre en anneau autour de `target`. Ne fonctionne que si
--- `target` n'est jamais animé directement (anime un frame parent commun a la place).
function ns.CreateSlugRing(parent, target, layer)
    local ring = {}
    for i, off in ipairs(SLUG_RING_OFFSETS) do
        local fs = parent:CreateFontString(nil, layer or "ARTWORK")
        -- Ancre TOPLEFT+BOTTOMRIGHT (toute la boite, pas juste CENTER) pour reproduire
        -- exactement le meme rendu de glyphe qu'un texte justifie LEFT/RIGHT.
        fs:SetPoint("TOPLEFT", target, "TOPLEFT", off[1], off[2])
        fs:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", off[1], off[2])
        fs:SetJustifyH(target:GetJustifyH())
        fs:SetJustifyV(target:GetJustifyV())
        ring[i] = fs
    end
    -- Auto-synchronise texte + justification avec `target`
    hooksecurefunc(target, "SetText", function(_, text) ns.SetSlugRingText(ring, text) end)
    hooksecurefunc(target, "SetJustifyH", function(_, justify)
        for _, fs in ipairs(ring) do fs:SetJustifyH(justify) end
    end)
    hooksecurefunc(target, "SetJustifyV", function(_, justify)
        for _, fs in ipairs(ring) do fs:SetJustifyV(justify) end
    end)
    return ring
end

--- Applique le style de contour choisi a `fontString` + son eventuel anneau SLUG `ring`.
--- `applyDefaultShadow` : n'activer que pour les textes qui suivaient déjà la convention
--- d'ombre noire (1,-1)/(0,0,0,1) — l'appelant reste responsable de désactiver sa propre
--- ombre native quand `style == "SLUG"` (sinon elle se cumule avec l'anneau).
function ns.ApplyTextOutlineStyle(fontString, ring, fontPath, size, style, applyDefaultShadow)
    -- style == "" (distinct de nil) : certains menus ont deja leur propre "Aucun contour"
    local flags = "OUTLINE"
    if style == "THICKOUTLINE" then flags = "THICKOUTLINE"
    elseif style == "SLUG" or style == "" then flags = "" end
    local safePath = fontPath or (ns.Media and ns.Media.font) or "Fonts\\FRIZQT__.TTF"
    local ok = pcall(function() fontString:SetFont(safePath, size or 12, flags) end)
    if not ok then fontString:SetFont("Fonts\\FRIZQT__.TTF", size or 12, flags) end
    if applyDefaultShadow then
        if style == "SLUG" then
            fontString:SetShadowOffset(0, 0)
        else
            fontString:SetShadowColor(0, 0, 0, 1)
            fontString:SetShadowOffset(1, -1)
        end
    end
    if ring then
        local slugOn = (style == "SLUG")
        for _, fs in ipairs(ring) do
            local rok = pcall(function() fs:SetFont(safePath, size or 12, "") end)
            if not rok then fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "") end
            fs:SetTextColor(0, 0, 0, 1)
            fs:SetShown(slugOn)
        end
    end
end

--- Recopie `text` sur le FontString principal ET chaque copie de l'anneau
--- SLUG (si present) -- a appeler partout ou le texte affiche change.
function ns.SetSlugRingText(ring, text)
    if not ring then return end
    for _, fs in ipairs(ring) do fs:SetText(text) end
end

-- Pose d'une valeur de StatusBar (remplace bar:SetValue(value)).
-- Malgre son nom, cette fonction ne lisse rien : c'est la pose directe. Ses appelants sont
-- les barres qu'il ne FAUT pas interpoler -- quartiers radiaux (100 barres mises a jour
-- ensemble), arcs de stagger et de duree, et tout repoussage de valeur destine a forcer un
-- redraw. Pour une barre qu'on veut lissee, cf. ns.SmoothBarValue juste en dessous.
function ns.SmoothSetValue(bar, value)
  if not bar or value == nil then return end
  pcall(bar.SetValue, bar, value)
end

-- Lissage natif des StatusBar : barres de vie/ressource et arcs des cercles en mode vertical.
-- L'enum vit sous Enum.StatusBarInterpolation, PAS en global : un `StatusBarInterpolation`
-- tout court vaut nil, et l'interpolation passe alors silencieusement a la trappe.
local _INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

function ns.SmoothBarValue(bar, value)
  if not bar then return end
  -- Pas de test `value == nil` : la valeur peut etre un secret number (vie en combat), sur
  -- lequel toute comparaison leve. Un nil est de toute facon rattrape par le pcall.
  if _INTERP then
    if pcall(bar.SetValue, bar, value, _INTERP) then return end
    -- Client qui n'accepte pas l'argument d'interpolation : on ne le retente plus, sinon
    -- chaque barre paierait un pcall rate par frame -- et la valeur ne serait jamais posee.
    _INTERP = nil
  end
  pcall(bar.SetValue, bar, value)
end

-- Utilitaire : deep copy d'une table
function ns.DeepCopy(src)
  if type(src) ~= "table" then return src end
  local copy = {}
  for k, v in pairs(src) do
    copy[k] = ns.DeepCopy(v)
  end
  return copy
end

-- Utilitaire : fusion de deux tables (defaults + saved), sans écraser les valeurs existantes
function ns.MergeDefaults(saved, defaults)
  if type(defaults) ~= "table" then return saved end
  if type(saved) ~= "table" then return ns.DeepCopy(defaults) end
  for k, v in pairs(defaults) do
    if saved[k] == nil then
      saved[k] = ns.DeepCopy(v)
    elseif type(v) == "table" and type(saved[k]) == "table" then
      ns.MergeDefaults(saved[k], v)
    end
  end
  return saved
end

-- Retourne true si le joueur est dans un état bloquant l'affichage (véhicule ou battle pet)
function ns.IsInBlockedState()
  if UnitInVehicle and UnitInVehicle("player") then return true end
  if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return true end
  return false
end

-- Flag Skyriding : mis à jour par Modules/Skyriding.lua, utilisé par ShouldShow() pour s'effacer en vol
ns.skyridingActive = false

-- Flag "en instance" (donjon/raid) : mis en cache au chargement plutôt que d'appeler
-- IsInInstance() à chaque ShouldShow(). Sert à l'option "Toujours actif en instance".
ns.inInstance = false
local _instEvt = CreateFrame("Frame")
_instEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
_instEvt:SetScript("OnEvent", function()
  local inInst, instType = IsInInstance()
  ns.inInstance = inInst and (instType == "party" or instType == "raid") or false
end)

-- Détection des "secret values" (anti-taint) : toute arithmétique/comparaison dessus plante l'addon
local _issecretvalue = issecretvalue
function ns.IsSecret(value)
  return _issecretvalue and _issecretvalue(value) or false
end

-- frame:IsMouseOver() renvoie un booleen secret (patch 12.0) : on recalcule le survol
-- via curseur vs rect du frame, en renonçant si ces valeurs sont elles-mêmes secrètes.
function ns.IsFrameMouseOver(f)
  if not f or not f:IsShown() then return false end
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local left, bottom, width, height = f:GetRect()
  if ns.IsSecret(scale) or ns.IsSecret(cx) or ns.IsSecret(cy)
     or ns.IsSecret(left) or ns.IsSecret(bottom) or ns.IsSecret(width) or ns.IsSecret(height) then
    return false
  end
  if not left or not scale or scale == 0 then return false end
  cx, cy = cx / scale, cy / scale
  return cx >= left and cx <= left + width and cy >= bottom and cy <= bottom + height
end

-- Bibliothèque d'easing générique (formules standard, cf. easings.net)
-- ns.Ease(family, kind, t) : t dans [0,1] -> progression easée. Retombe sur Cubic/Out si inconnu.
ns.Easing = {
  Linear = {
    In    = function(t) return t end,
    Out   = function(t) return t end,
    InOut = function(t) return t end,
  },
  Sine = {
    In    = function(t) return 1 - math.cos((t * math.pi) / 2) end,
    Out   = function(t) return math.sin((t * math.pi) / 2) end,
    InOut = function(t) return -(math.cos(math.pi * t) - 1) / 2 end,
  },
  Quad = {
    In    = function(t) return t * t end,
    Out   = function(t) return 1 - (1 - t) * (1 - t) end,
    InOut = function(t)
      if t < 0.5 then return 2 * t * t end
      return 1 - ((-2 * t + 2) ^ 2) / 2
    end,
  },
  Cubic = {
    In    = function(t) return t ^ 3 end,
    Out   = function(t) return 1 - (1 - t) ^ 3 end,
    InOut = function(t)
      if t < 0.5 then return 4 * t ^ 3 end
      return 1 - ((-2 * t + 2) ^ 3) / 2
    end,
  },
  Quart = {
    In    = function(t) return t ^ 4 end,
    Out   = function(t) return 1 - (1 - t) ^ 4 end,
    InOut = function(t)
      if t < 0.5 then return 8 * t ^ 4 end
      return 1 - ((-2 * t + 2) ^ 4) / 2
    end,
  },
  Quint = {
    In    = function(t) return t ^ 5 end,
    Out   = function(t) return 1 - (1 - t) ^ 5 end,
    InOut = function(t)
      if t < 0.5 then return 16 * t ^ 5 end
      return 1 - ((-2 * t + 2) ^ 5) / 2
    end,
  },
  Expo = {
    In    = function(t) if t <= 0 then return 0 end; if t >= 1 then return 1 end; return 2 ^ (10 * t - 10) end,
    Out   = function(t) if t <= 0 then return 0 end; if t >= 1 then return 1 end; return 1 - 2 ^ (-10 * t) end,
    InOut = function(t)
      if t <= 0 then return 0 end
      if t >= 1 then return 1 end
      if t < 0.5 then return (2 ^ (20 * t - 10)) / 2 end
      return (2 - 2 ^ (-20 * t + 10)) / 2
    end,
  },
  Circ = {
    In    = function(t) return 1 - math.sqrt(1 - t ^ 2) end,
    Out   = function(t) return math.sqrt(1 - (t - 1) ^ 2) end,
    InOut = function(t)
      if t < 0.5 then return (1 - math.sqrt(1 - (2 * t) ^ 2)) / 2 end
      return (math.sqrt(1 - (-2 * t + 2) ^ 2) + 1) / 2
    end,
  },
}

function ns.Ease(family, kind, t)
  if t <= 0 then return 0 end
  if t >= 1 then return 1 end
  local fam = ns.Easing[family] or ns.Easing.Cubic
  local fn  = fam[kind] or fam.Out
  return fn(t)
end

-- Utilitaire : animation stagger générique pour un ensemble d'éléments.
-- Chaque item : { element, delay, duration, ease, easeType, slideX, slideY,
-- scaleX, scaleY, opacity, homePoint, homeRelTo, homeRelPoint, homeX, homeY,
-- homeW, homeH } ; seul `element` est obligatoire, le reste retombe sur le
-- comportement historique (Cubic/Out, scale 0.1->1, pas de slide, fondu 0<->1).
-- home* : géométrie pré-calculée par l'appelant, pour slide/scale sans jamais
-- appeler GetPoint/GetSize (recommandé en combat, où ces lectures peuvent être secrètes).
-- scaleX/scaleY non-uniformes utilisent SetSize (SetScale est uniforme) via ns.SmoothSetValue
-- pour réappliquer le crop de texture des StatusBars (SetValue seul ne suffit pas).
local function RefreshCrop(element)
  if element.GetValue and element.SetValue then
    ns.SmoothSetValue(element, element:GetValue())
  end
end

function ns.AnimateStagger(elements, shouldShow, duration, staggerInterval, onComplete)
  duration = duration or 0.35
  staggerInterval = staggerInterval or 0.04
  local startTime = GetTime()

  -- État capturé au lancement de CETTE animation (pas mis en cache entre appels)
  local homeState = {}
  for _, item in ipairs(elements) do
    if item.element then
      local st = {}
      -- Géométrie pré-calculée par l'appelant si fournie (zéro lecture GetPoint/GetSize,
      -- important en combat où ces valeurs peuvent être secrètes et bloquer tout calcul).
      if (item.slideX and item.slideX ~= 0) or (item.slideY and item.slideY ~= 0) then
        if item.homePoint then
          st.point, st.relTo, st.relPoint, st.x, st.y = item.homePoint, item.homeRelTo, item.homeRelPoint, item.homeX, item.homeY
        elseif item.element.GetPoint then
          local point, relTo, relPoint, x, y = item.element:GetPoint(1)
          -- Filet de sécurité : si secret, abandonne le slide pour cet élément plutôt que de crasher
          if point and not ns.IsSecret(point) and not ns.IsSecret(x) and not ns.IsSecret(y) then
            st.point, st.relTo, st.relPoint, st.x, st.y = point, relTo, relPoint, x, y
          end
        end
      end
      if item.scaleX and item.scaleY and item.scaleX ~= item.scaleY then
        if item.homeW then
          st.w, st.h = item.homeW, item.homeH
        elseif item.element.GetSize then
          local w, h = item.element:GetSize()
          if not ns.IsSecret(w) and not ns.IsSecret(h) then
            st.w, st.h = w, h
          end
        end
      end
      homeState[item] = st
    end
  end

  if shouldShow then
    for _, item in ipairs(elements) do
      if item.element then
        item.element:SetAlpha(item.opacity or 0)
        local sx = item.scaleX or 0.1
        local sy = item.scaleY or 0.1
        local st = homeState[item]
        if st.w then
          item.element:SetSize(st.w * sx, st.h * sy)
          RefreshCrop(item.element)
        elseif item.element.SetScale then
          item.element:SetScale(sx)
        end
      end
    end
  end

  local ticker
  ticker = C_Timer.NewTicker(0.016, function()
    local elapsed = GetTime() - startTime

    for _, item in ipairs(elements) do
      if item.element then
        local st = homeState[item]
        local itemDuration = item.duration or duration
        local elementElapsed = elapsed - (item.delay or 0)
        if elementElapsed >= 0 then
          local elementProgress = math.min(elementElapsed / itemDuration, 1)
          local easeProgress = ns.Ease(item.ease or "Cubic", item.easeType or "Out", elementProgress)
          local opacity = item.opacity or 0
          local startAlpha = shouldShow and opacity or 1
          local endAlpha   = shouldShow and 1 or opacity
          item.element:SetAlpha(startAlpha + (endAlpha - startAlpha) * easeProgress)

          local sx, sy = item.scaleX or 0.1, item.scaleY or 0.1
          local startScale = shouldShow and sx or 1
          local endScale   = shouldShow and 1 or sx
          if st.w then
            local startScaleY = shouldShow and sy or 1
            local endScaleY   = shouldShow and 1 or sy
            local curX = startScale  + (endScale  - startScale)  * easeProgress
            local curY = startScaleY + (endScaleY - startScaleY) * easeProgress
            item.element:SetSize(st.w * curX, st.h * curY)
            RefreshCrop(item.element)
          elseif item.element.SetScale then
            item.element:SetScale(startScale + (endScale - startScale) * easeProgress)
          end

          if st.point then
            local slideX, slideY = item.slideX or 0, item.slideY or 0
            local fromX = shouldShow and (st.x + slideX) or st.x
            local toX   = shouldShow and st.x or (st.x + slideX)
            local fromY = shouldShow and (st.y + slideY) or st.y
            local toY   = shouldShow and st.y or (st.y + slideY)
            item.element:ClearAllPoints()
            item.element:SetPoint(st.point, st.relTo, st.relPoint,
              fromX + (toX - fromX) * easeProgress, fromY + (toY - fromY) * easeProgress)
          end
        elseif not shouldShow then
          item.element:SetAlpha(1)
          if st.w then
            item.element:SetSize(st.w, st.h)
            RefreshCrop(item.element)
          elseif item.element.SetScale then
            item.element:SetScale(1)
          end
          if st.point then
            item.element:ClearAllPoints()
            item.element:SetPoint(st.point, st.relTo, st.relPoint, st.x, st.y)
          end
        end
      end
    end

    local maxDelay = 0
    for _, item in ipairs(elements) do
      local itemTotal = (item.delay or 0) + (item.duration or duration) - duration
      if itemTotal > maxDelay then maxDelay = itemTotal end
    end

    if elapsed >= duration + maxDelay then
      ticker:Cancel()
      for _, item in ipairs(elements) do
        if item.element then
          local st = homeState[item]
          if shouldShow then
            item.element:SetAlpha(1)
          end
          -- Taille/scale reviennent à leur valeur de repos quelle que soit la direction
          -- (sinon un hide laisse l'élément figé à son échelle "hors écran" au show suivant)
          if st.w then
            item.element:SetSize(st.w, st.h)
            RefreshCrop(item.element)
          elseif item.element.SetScale then
            item.element:SetScale(1)
          end
          if st.point then
            item.element:ClearAllPoints()
            item.element:SetPoint(st.point, st.relTo, st.relPoint, st.x, st.y)
          end
        end
      end
      if onComplete then onComplete() end
    end
  end)

  return ticker
end

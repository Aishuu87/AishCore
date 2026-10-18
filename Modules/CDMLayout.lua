-- Modules/CDMLayout.lua : "Gestionnaire de temps de recharge". Range les cooldowns du Cooldown Manager
-- Blizzard (sorts, trinkets, potions) en Essentiels / Utilitaires / non suivis, avec l'ordre des
-- Essentiels, depuis une config par spé stockée dans le profil (ns.DB.cdmLayout.specs[specID]) : elle
-- voyage avec l'export de profil. Ne touche jamais aux catégories d'auras (Buffs / Barres).
--
-- TAINT : toute écriture dans le Cooldown Manager depuis un addon taint l'exécution du CDM natif
-- (erreurs "secret value" plus tard dans la session). Les écritures (SetCooldownToCategory,
-- WriteCooldownOrderToActiveLayout, SaveLayouts) ne se font donc QUE dans Apply, immédiatement suivi
-- de ReloadUI(), comme le pin d'auras (Modules/Auras/Core/CDMHooks.lua). La lecture passe
-- exclusivement par GetDisplayData(), sans jamais déclencher sa construction (CheckBuildDisplayData),
-- que seul le code Blizzard doit exécuter.
--
-- Config : specs[specID] = { active = nom | nil, builds = { [nom] = build } }, un build étant
--   { cats = { [cooldownID] = 1 (Essentiel) | 2 (Utilitaire) }, order = { cooldownID, ... } }.
-- Un cooldown absent de cats = non suivi (catégorie masquée). order = ordre des Essentiels uniquement.
-- active = nil : "Aucun (CDM libre)", le module ne touche à rien pour cette spé. Les builds sont rangés
-- par spé : le même nom ("AishUI") désigne un build différent pour chaque spé. "AishUI" = build livré
-- avec le pack (CDMLayout.OFFICIAL), mis en avant dans la page et jamais modifié en place.
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local CDMLayout = {}
ns.Modules.CDMLayout = CDMLayout

local ESSENTIAL, UTILITY = 1, 2
CDMLayout.ESSENTIAL, CDMLayout.UTILITY = ESSENTIAL, UTILITY

local function Cfg()
  local c = ns.DB and ns.DB.cdmLayout
  if type(c) ~= "table" then return nil end
  c.specs = c.specs or {}
  return c
end

-- Spe AishCore (sur Forever : deduite des talents) ; si aucune (Forever : aucun point ou egalite entre arbres), la
-- "spe" native du client, celle que le Cooldown Manager de Blizzard utilise lui-meme (ex. "Druide - Druide").
-- Renvoie specID, nom.
-- Forever : le Cooldown Manager est par CLASSE (une seule disposition, "Druide - Druide"), comme la barre de rotation
-- et les auras a tracker. Les builds sont donc ranges sous "class:<CLASSE>". Les builds d'avant (un par spe deduite
-- des talents) sont repris une fois : celui de la spe courante, sinon le premier des arbres de la classe.
local _cdmClassMigrated = {}
local function MigrateToClassKey(key)
  if _cdmClassMigrated[key] then return end
  local c = ns.DB and ns.DB.cdmLayout
  if not (c and c.specs) then return end      -- DB pas encore prete : on retentera
  _cdmClassMigrated[key] = true
  local cands = {}
  local idx = ns.GetSpecialization and ns.GetSpecialization()
  local cur = idx and ns.GetSpecializationInfo(idx)
  if cur then cands[#cands + 1] = cur end
  for i = 1, 3 do
    local sid = ns.GetTalentTabSpecID and ns.GetTalentTabSpecID(i)
    if sid then cands[#cands + 1] = sid end
  end
  if c.specs[key] == nil then
    for _, sid in ipairs(cands) do
      if c.specs[sid] ~= nil then c.specs[key] = CopyTable(c.specs[sid]); break end
    end
  end
  -- Dernier build applique sur ce personnage : meme reprise (sinon statut "non applique" a tort)
  AishUISetupCharDB = AishUISetupCharDB or {}
  local la = AishUISetupCharDB.cdmLastApplied
  if la and la[key] == nil then
    for _, sid in ipairs(cands) do
      if la[sid] ~= nil then la[key] = la[sid]; break end
    end
  end
end

function CDMLayout.CurrentSpecID()
  if ns.IsForever then
    local className, classFile = UnitClass("player")
    if classFile then
      local key = "class:" .. classFile
      MigrateToClassKey(key)
      return key, className
    end
  end
  local idx = ns.GetSpecialization and ns.GetSpecialization()
  local id, name
  if idx then id, name = ns.GetSpecializationInfo(idx) end
  if not id and _G.GetSpecialization and _G.GetSpecializationInfo then
    local okI, nidx = pcall(_G.GetSpecialization)
    if okI and nidx then
      local okS, nid, nname = pcall(_G.GetSpecializationInfo, nidx)
      if okS and type(nid) == "number" then id, name = nid, nname end
    end
  end
  return id, name
end

CDMLayout.OFFICIAL = "AishUI"
-- Build virtuel "Défaut" : aucune catégorie forcée, donc chaque cooldown retombe sur sa catégorie
-- d'origine (e.restCategory) -- autrement dit la disposition par défaut de Blizzard. Il n'est jamais
-- stocké dans `builds` ; la clé interne reste la même quelle que soit la langue.
CDMLayout.DEFAULT = "__default"

-- Données de la spé { active, builds }. Ancien format (un seul build à plat) migré en build "AishUI".
function CDMLayout.GetSpecData(specID, create)
  local c = Cfg()
  if not (c and specID) then return nil end
  local d = c.specs[specID]
  if type(d) == "table" and d.cats then
    d = { active = CDMLayout.OFFICIAL, builds = { [CDMLayout.OFFICIAL] = { cats = d.cats, order = d.order or {} } } }
    c.specs[specID] = d
  end
  -- Profil fraîchement créé (cf. Config/Profiles.lua) : tant qu'une spé n'a aucune entrée, elle
  -- part du build Défaut -- sinon le CDM garderait la dernière config appliquée sur le personnage
  -- (typiquement celle du pack AishUI), qui n'a rien à voir avec le nouveau profil.
  if not d and c.defaultBuild then
    if not create then return { active = CDMLayout.DEFAULT, builds = {} } end
    d = { active = CDMLayout.DEFAULT, builds = {} }
    c.specs[specID] = d
  end
  if not d and create then d = { builds = {} }; c.specs[specID] = d end
  if d then d.builds = d.builds or {} end
  return d
end

-- Build actif de la spé (nil = aucun)
--- Config du build virtuel "Défaut" : chaque cooldown dans SA catégorie d'origine (côté Blizzard),
--- l'ordre restant celui du CDM courant (l'ordre d'origine n'est exposé nulle part). Table neuve a
--- chaque appel : la page la modifie en place des que l'utilisateur touche une categorie.
function CDMLayout.DefaultConf()
  local conf = { cats = {}, order = {} }
  for _, e in ipairs(CDMLayout.ListCooldowns()) do
    if e.defaultCategory ~= 0 or e.racial then conf.cats[KeyOf(e)] = e.defaultCategory end
    if e.defaultCategory == ESSENTIAL then conf.order[#conf.order + 1] = KeyOf(e) end
  end
  return conf
end

function CDMLayout.GetSpecConfig(specID)
  local d = CDMLayout.GetSpecData(specID)
  if d and d.active == CDMLayout.DEFAULT then return CDMLayout.DefaultConf() end
  local b = d and d.active and d.builds[d.active]
  if b then b.cats = b.cats or {}; b.order = b.order or {} end
  return b
end

function CDMLayout.GetActiveName(specID)
  local d = CDMLayout.GetSpecData(specID)
  if d and d.active == CDMLayout.DEFAULT then return CDMLayout.DEFAULT end
  return d and d.builds[d.active or ""] and d.active or nil
end

--- Libellé affiché d'un build (le build virtuel Défaut est traduit, les autres gardent leur nom).
function CDMLayout.BuildLabel(name)
  if name == CDMLayout.DEFAULT then return L["CDM_LAYOUT_BUILD_DEFAULT"] end
  return name
end

function CDMLayout.SetActive(specID, name)
  local d = CDMLayout.GetSpecData(specID, true)
  if not d then return end
  if name == CDMLayout.DEFAULT then d.active = CDMLayout.DEFAULT; return end
  d.active = (name and d.builds[name]) and name or nil
end

-- Noms des builds de la spé, "AishUI" en tête puis ordre alphabétique
function CDMLayout.ListBuilds(specID)
  local d, names = CDMLayout.GetSpecData(specID), {}
  for name in pairs(d and d.builds or {}) do names[#names + 1] = name end
  table.sort(names, function(a, b)
    if a == CDMLayout.OFFICIAL then return true end
    if b == CDMLayout.OFFICIAL then return false end
    return a:lower() < b:lower()
  end)
  -- Build virtuel, toujours proposé en dernier : remettre le CDM tel que Blizzard le livre.
  names[#names + 1] = CDMLayout.DEFAULT
  return names
end

function CDMLayout.DeleteBuild(specID, name)
  local d = CDMLayout.GetSpecData(specID)
  if not (d and name) or name == CDMLayout.DEFAULT then return end
  d.builds[name] = nil
  if d.active == name then d.active = nil end
end

-- Copie un build sous un nouveau nom (écrase s'il existe) et l'active
function CDMLayout.CopyBuild(specID, src, dst)
  local d = CDMLayout.GetSpecData(specID, true)
  local b = d and d.builds[src]
  if not (b and dst and dst ~= "") then return nil end
  d.builds[dst] = { cats = CopyTable(b.cats or {}), order = CopyTable(b.order or {}) }
  d.active = dst
  return d.builds[dst]
end

local function Cat(name) return Enum.CooldownViewerCategory and Enum.CooldownViewerCategory[name] end

-- Catégories "actives" (cooldowns que le joueur lance ou utilise) et leur catégorie de repos quand
-- elles ne sont pas suivies (mêmes règles que CooldownViewerSettingsDataProvider de Blizzard).
local function DomainCategories()
  local hiddenActive = Cat("HiddenActive") or -1
  local map = {}
  if Cat("Essential") then map[Cat("Essential")] = hiddenActive end
  if Cat("Utility") then map[Cat("Utility")] = hiddenActive end
  if Cat("EquipSlotEssential") then map[Cat("EquipSlotEssential")] = Cat("EquipSlotEssential") end
  if Cat("SpecAgnosticEssential") then map[Cat("SpecAgnosticEssential")] = Cat("SpecAgnosticEssential") end
  return map
end

local function Provider()
  local settings = _G.CooldownViewerSettings
  if not (settings and settings.GetDataProvider) then return nil end
  local ok, dp = pcall(settings.GetDataProvider, settings)
  if ok then return dp end
end

-- Lecture des données du CDM par l'API C (C_CooldownViewer) UNIQUEMENT. Les anciennes lectures passaient par
-- le fournisseur de données Lua de Blizzard (GetDataProvider / GetLayoutManager / GetActiveLayout /
-- GetDisplayData) : les executer depuis notre code laissait des donnees tainted dans le CDM, et tout le
-- CooldownViewer plantait ensuite au changement de spe ("execution tainted by AishCore"). L'API C ne
-- touche a aucune table Lua de Blizzard. Meme forme que l'ancien GetDisplayData :
-- { orderedCooldownIDs = {...}, cooldownInfoByID = { [id] = { category = <categorie courante>, ... } } }.
local function DisplayData()
  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
          and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return nil end
  local dd = { orderedCooldownIDs = {}, cooldownInfoByID = {} }
  local function Add(cid, cat)
    if dd.cooldownInfoByID[cid] then return end
    local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
    if okI and info then
      dd.orderedCooldownIDs[#dd.orderedCooldownIDs + 1] = cid
      dd.cooldownInfoByID[cid] = {
        category = cat, spellID = info.spellID,
        overrideSpellID = info.overrideSpellID, isKnown = info.isKnown,
      }
    end
  end
  -- Categorie COURANTE et ordre : lus sur les frames des deux viewers (simple lecture de champs, rien
  -- n'est appele cote Blizzard). Les sets de l'API C donnent, eux, la classification par defaut et pas
  -- la disposition du joueur.
  local found, built = 0, false
  for _, v in ipairs({ { "EssentialCooldownViewer", Cat("Essential") }, { "UtilityCooldownViewer", Cat("Utility") } }) do
    local viewer, cat = _G[v[1]], v[2]
    local pool = viewer and viewer.itemFramePool
    if cat and pool and pool.EnumerateActive then
      built = true
      local items = {}
      for f in pool:EnumerateActive() do
        local cid = f.cooldownID
        if type(cid) == "number" and not (issecretvalue and issecretvalue(cid)) then
          local li = f.layoutIndex
          if type(li) ~= "number" or (issecretvalue and issecretvalue(li)) then li = 1e9 end
          items[#items + 1] = { cid = cid, li = li }
        end
      end
      table.sort(items, function(a, b) if a.li ~= b.li then return a.li < b.li end return a.cid < b.cid end)
      for _, it in ipairs(items) do Add(it.cid, cat); found = found + 1 end
    end
  end
  -- Viewers pas encore construits : donnees indisponibles (et non "tout non suivi")
  if not built then return nil end
  -- Viewers construits mais sans icone active (viewer masque, spe dont les cadres n'ont pas ete peuples...) :
  -- on repart de la classification de l'API (sets Essentiels / Utilitaires) plutot que de declarer le CDM absent.
  if found == 0 then
    -- Classement par defaut de Blizzard, PAS la disposition du joueur : lecture approximative, jamais comparee
    -- pour proposer d'appliquer un build (cf. CheckSpec)
    dd.approx = true
    for _, name in ipairs({ "Essential", "Utility" }) do
      local cat = Cat(name)
      if cat then
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, false)
        if ok and type(ids) == "table" then
          for _, cid in ipairs(ids) do Add(cid, cat); found = found + 1 end
        end
      end
    end
  end
  -- Le reste de ce que connait le CDM : non suivi (categorie de repos, ni Essentiel ni Utilitaire)
  local rest = Cat("HiddenActive") or -1
  for _, name in ipairs({ "Essential", "Utility", "HiddenActive", "EquipSlotEssential", "SpecAgnosticEssential" }) do
    local cat = Cat(name)
    if cat then
      local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
      if ok and type(ids) == "table" then
        for _, cid in ipairs(ids) do Add(cid, rest) end
      end
    end
  end
  return dd
end

-- true si la disposition lue est la vraie (icones presentes dans les barres), pas le classement par defaut
function CDMLayout.IsExact()
  local dd = DisplayData()
  return dd ~= nil and not dd.approx
end

function CDMLayout.IsAvailable()
  if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return false end
  if C_CooldownViewer.IsCooldownViewerAvailable then
    local ok, avail = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
    if not (ok and avail) then return false end
  end
  return DisplayData() ~= nil
end

local function Readable(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) end

-- Raciaux : un build ne retient pas LE sort racial (son cooldown change d'une race a l'autre) mais un emplacement
-- generique "racial" : categorie et position dans les Essentiels. Sans cela, la meme classe sur une autre race voyait
-- le build "different" en boucle. Detection par le sous-texte du sort ("Raciale", "Racial"...), toutes langues.
local RACIAL_KEY = "racial"
CDMLayout.RACIAL_KEY = RACIAL_KEY
local RACIAL_WORDS = { "racial", "raciale", "razziale", "volksf", "расов", "종족", "种族", "種族" }
local _racialCache = {}
local function IsRacial(spellID)
  if not spellID then return false end
  local c = _racialCache[spellID]
  if c ~= nil then return c end
  local sub
  if C_Spell and C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(spellID)
  elseif GetSpellSubtext then sub = GetSpellSubtext(spellID) end
  local r = false
  if type(sub) == "string" and sub ~= "" then
    local low = sub:lower()
    for _, w in ipairs(RACIAL_WORDS) do
      if low:find(w, 1, true) then r = true; break end
    end
  end
  _racialCache[spellID] = r
  return r
end

-- Cle d'un cooldown dans un build : "racial" pour un racial, son cooldownID sinon
local function KeyOf(e) return e.racial and RACIAL_KEY or e.cooldownID end
CDMLayout.KeyOf = KeyOf

-- Categorie voulue par un build pour une entree ; nil = le build ne dit rien (racial d'une autre race, build ancien)
function CDMLayout.CatOf(conf, e)
  local c = conf.cats[KeyOf(e)]
  if c == nil and e.racial then c = conf.cats[e.cooldownID] end   -- builds d'avant l'emplacement generique
  return c
end
local CatOf = CDMLayout.CatOf

-- Cooldowns gérés par le module pour la spé active, dans l'ordre du CDM :
-- { cooldownID, spellID, equipSlot, isKnown, current (1/2/0), restCategory, defaultCategory (1/2/0) }
-- defaultCategory = la catégorie d'origine du cooldown côté Blizzard (static.category), celle qu'il
-- retrouve quand on remet le CDM à plat -- à ne pas confondre avec restCategory, qui est là où il
-- tombe quand on cesse de le suivre (HiddenActive pour un sort).
function CDMLayout.ListCooldowns()
  local dd = DisplayData()
  if not dd then return {} end
  local domain = DomainCategories()
  local essential, utility = Cat("Essential"), Cat("Utility")
  local list = {}
  for _, cid in ipairs(dd.orderedCooldownIDs) do
    local okS, static = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cid)
    local info = dd.cooldownInfoByID[cid]
    if okS and static and info and Readable(static.category) and domain[static.category] then
      local cur = info.category
      list[#list + 1] = {
        cooldownID = cid,
        spellID = Readable(info.overrideSpellID) and info.overrideSpellID or info.spellID,
        equipSlot = Readable(static.equipSlot) and static.equipSlot or nil,
        isKnown = info.isKnown ~= false,
        racial = IsRacial(Readable(info.overrideSpellID) and info.overrideSpellID or info.spellID),
        current = (cur == essential and ESSENTIAL) or (cur == utility and UTILITY) or 0,
        restCategory = domain[static.category],
        defaultCategory = (static.category == essential and ESSENTIAL)
                       or (static.category == utility and UTILITY) or 0,
      }
    end
  end
  return list
end

-- Dernier build appliqué par spé sur CE personnage (le CDM est propre à chaque perso) : le statut
-- "Appliqué" ne doit pas s'afficher pour un autre build au contenu identique ou proche.
local function LastAppliedTable()
  AishUISetupCharDB = AishUISetupCharDB or {}
  AishUISetupCharDB.cdmLastApplied = AishUISetupCharDB.cdmLastApplied or {}
  return AishUISetupCharDB.cdmLastApplied
end
function CDMLayout.SetLastApplied(specID, name)
  if specID then LastAppliedTable()[specID] = name end
end

-- Build construit depuis l'état actuel du CDM (sans l'enregistrer)
function CDMLayout.CaptureCurrent()
  -- Jamais sur des données indisponibles : le build vide qui en résulterait masquerait tout
  if not CDMLayout.IsAvailable() then return nil end
  local b = { cats = {}, order = {} }
  for _, e in ipairs(CDMLayout.ListCooldowns()) do
    -- le racial est toujours note, meme non suivi (0) : "non suivi" doit se distinguer de "inconnu"
    if e.current ~= 0 or e.racial then b.cats[KeyOf(e)] = e.current end
    if e.current == ESSENTIAL then b.order[#b.order + 1] = KeyOf(e) end
  end
  return b
end

-- Enregistre l'état actuel du CDM sous `name` (écrase s'il existe) et l'active
function CDMLayout.SaveCurrentAs(specID, name)
  if not (name and name ~= "") then return nil end
  local b = CDMLayout.CaptureCurrent()
  local d = b and CDMLayout.GetSpecData(specID, true)
  if not d then return nil end
  d.builds[name] = b
  d.active = name
  -- Capturé depuis le CDM : c'est, par définition, ce qui est appliqué sur ce perso
  CDMLayout.SetLastApplied(specID, name)
  return b
end

-- Essentiels de la config, dans l'ordre voulu (order d'abord, puis ceux qui n'y figurent pas)
-- Renvoie des cooldownIDs ; l'ordre du build peut contenir la cle "racial" (le racial de CE personnage).
function CDMLayout.OrderedEssentials(conf, list)
  local byKey, byCid, out, seen = {}, {}, {}, {}
  for _, e in ipairs(list) do
    byKey[KeyOf(e)] = e
    byCid[e.cooldownID] = e
  end
  for _, k in ipairs(conf.order or {}) do
    local e = byKey[k] or byCid[k]
    if e and CatOf(conf, e) == ESSENTIAL and not seen[e.cooldownID] then
      out[#out + 1] = e.cooldownID; seen[e.cooldownID] = true
    end
  end
  for _, e in ipairs(list) do
    if CatOf(conf, e) == ESSENTIAL and not seen[e.cooldownID] then out[#out + 1] = e.cooldownID; seen[e.cooldownID] = true end
  end
  return out
end

-- Cle de build d'un cooldownID (pour la page : "racial" si c'est le racial du personnage)
function CDMLayout.KeyForCid(cid)
  for _, e in ipairs(CDMLayout.ListCooldowns()) do
    if e.cooldownID == cid then return KeyOf(e) end
  end
  return cid
end

-- Écarts entre le CDM et la config de la spé : liste de { entry, want, current } (catégories), plus
-- orderDiffers si les Essentiels ne sont pas dans l'ordre voulu.
function CDMLayout.Diff(specID)
  local conf = CDMLayout.GetSpecConfig(specID)
  local diffs = {}
  if not conf then return diffs, false end
  local list = CDMLayout.ListCooldowns()
  local currentEss = {}
  for _, e in ipairs(list) do
    local want = CatOf(conf, e)
    -- Racial dont le build ne dit rien (autre race, ancien build) : pas un ecart
    local ignore = e.racial and want == nil
    want = want or 0
    -- Cooldown pas appris : le viewer ne l'affiche pas (aucune frame), sa categorie courante est donc
    -- illisible depuis les frames. On ne le compare pas ; Apply, lui, le range quand meme.
    if e.isKnown and not ignore and want ~= e.current then diffs[#diffs + 1] = { entry = e, want = want, current = e.current } end
    if e.current == ESSENTIAL then currentEss[#currentEss + 1] = e.cooldownID end
  end
  local orderDiffers = false
  if #diffs == 0 then
    -- Seuls les cooldowns appris ont une frame dans le viewer : l'ordre ne se compare que sur eux
    local known = {}
    for _, e in ipairs(list) do if e.isKnown then known[e.cooldownID] = true end end
    local wanted = {}
    for _, cid in ipairs(CDMLayout.OrderedEssentials(conf, list)) do
      if known[cid] then wanted[#wanted + 1] = cid end
    end
    for i = 1, math.max(#wanted, #currentEss) do
      if wanted[i] ~= currentEss[i] then orderDiffers = true; break end
    end
  end
  return diffs, orderDiffers
end

-- true si le CDM correspond déjà à la config de la spé (catégories + ordre des Essentiels)
function CDMLayout.IsApplied(specID)
  local diffs, orderDiffers = CDMLayout.Diff(specID)
  return #diffs == 0 and not orderDiffers
end

-- Statut du build actif pour la page :
--   "none"    : aucun build actif
--   "applied" : le CDM correspond et c'est bien ce build qui a été appliqué sur ce perso
--   "same"    : le CDM correspond, mais c'est un autre build qui a été appliqué (contenu identique)
--   "pending" : le CDM ne correspond pas
function CDMLayout.Status(specID)
  local name = CDMLayout.GetActiveName(specID)
  if not name then return "none" end
  local last = LastAppliedTable()[specID]
  -- Lecture approximative (barres du CDM vides : classement par defaut de Blizzard, pas la vraie disposition) :
  -- aucune comparaison possible, on se fie au dernier build applique sur ce personnage
  if not CDMLayout.IsExact() then
    return (last == nil or last == name) and "applied" or "pending"
  end
  if not CDMLayout.IsApplied(specID) then return "pending" end
  -- Données d'avant ce suivi : le build qui correspond est considéré comme l'appliqué
  if last == nil then CDMLayout.SetLastApplied(specID, name); return "applied" end
  return last == name and "applied" or "same"
end

-- Écrit la config dans le CDM puis recharge l'interface (obligatoire, cf. TAINT en tête de fichier).
-- Retourne false, raison en cas d'échec ; ne revient pas en cas de succès (ReloadUI).
function CDMLayout.Apply(specID)
  if InCombatLockdown() then return false, L["CDM_LAYOUT_ERR_COMBAT"] end
  local conf = CDMLayout.GetSpecConfig(specID)
  if not conf then return false, L["CDM_LAYOUT_ERR_NO_CONFIG"] end
  local dp = Provider()
  local lm = dp and dp.GetLayoutManager and dp:GetLayoutManager()
  if not (lm and CDMLayout.IsAvailable()) then return false, L["CDM_LAYOUT_ERR_UNAVAILABLE"] end

  -- Déjà identique (autre build au même contenu) : rien à écrire, pas de rechargement
  if CDMLayout.IsApplied(specID) then
    CDMLayout.SetLastApplied(specID, CDMLayout.GetActiveName(specID))
    return true, nil, true
  end

  -- À partir d'ici, le CDM a été touché : le rechargement a lieu QUOI QU'IL ARRIVE (cf. TAINT en tête
  -- de fichier). Un changement refusé par Blizzard n'arrête pas les autres ; les refus sont affichés
  -- après le rechargement (AishUISetupCharDB.cdmApplyErrors).
  local list = CDMLayout.ListCooldowns()
  local essential, utility = Cat("Essential"), Cat("Utility")
  local failures = {}
  for _, e in ipairs(list) do
    local want = CatOf(conf, e)
    local target = (want == ESSENTIAL and essential) or (want == UTILITY and utility) or e.restCategory
    -- racial dont le build ne dit rien : laisse tel quel
    if not (e.racial and want == nil) and (want or 0) ~= e.current then
      local ok, status = pcall(dp.SetCooldownToCategory, dp, e.cooldownID, target)
      if not ok or (Enum.CooldownLayoutStatus and status ~= Enum.CooldownLayoutStatus.Success) then
        local name = e.spellID and C_Spell.GetSpellName(e.spellID) or ("#" .. e.cooldownID)
        failures[#failures + 1] = string.format("%s (%s)", tostring(name), tostring(ok and status or "error"))
      end
    end
  end

  -- Ordre des Essentiels : la liste du CDM est unique (toutes catégories) ; on ne permute que les
  -- emplacements occupés par les Essentiels, le reste garde sa place.
  local okIds, ids = pcall(dp.GetOrderedCooldownIDs, dp)
  if okIds and type(ids) == "table" then
    ids = CopyTable(ids)
    local wanted = CDMLayout.OrderedEssentials(conf, list)
    local isEss, slots = {}, {}
    for _, cid in ipairs(wanted) do isEss[cid] = true end
    for i, cid in ipairs(ids) do if isEss[cid] then slots[#slots + 1] = i end end
    if #slots == #wanted then
      for k, i in ipairs(slots) do ids[i] = wanted[k] end
      pcall(lm.WriteCooldownOrderToActiveLayout, lm, ids, Enum.CDMLayoutMode and Enum.CDMLayoutMode.AllowCreate)
    end
  end

  pcall(lm.SaveLayouts, lm)
  CDMLayout.SetLastApplied(specID, CDMLayout.GetActiveName(specID))
  if #failures > 0 then
    AishUISetupCharDB = AishUISetupCharDB or {}
    AishUISetupCharDB.cdmApplyErrors = failures
  end
  ReloadUI()
  return true
end

-- Refus du dernier Apply, affichés une fois après le rechargement
local function ReportApplyErrors()
  local errs = AishUISetupCharDB and AishUISetupCharDB.cdmApplyErrors
  if not errs then return end
  AishUISetupCharDB.cdmApplyErrors = nil
  print("|cffff4444[AishCore]|r " .. string.format(L["CDM_LAYOUT_ERR_REFUSED"], table.concat(errs, ", ")))
end

-- Proposition d'application -------------------------------------------------------------------
-- Au login et au changement de spé, si le profil a une config pour la spé et que le CDM ne la reflète
-- pas : une fenêtre, une fois par spé et par session, jamais en combat. "Ne plus demander" est retenu
-- par personnage et par spé (AishUISetupCharDB.cdmLayoutSkip).
local askedThisSession = {}

local function SkipTable()
  AishUISetupCharDB = AishUISetupCharDB or {}
  AishUISetupCharDB.cdmLayoutSkip = AishUISetupCharDB.cdmLayoutSkip or {}
  return AishUISetupCharDB.cdmLayoutSkip
end

function CDMLayout.ClearSkip(specID)
  if specID then SkipTable()[specID] = nil end
end

local pendingCheck
local CheckSpec
-- Données du CDM pas encore prêtes (bascule de disposition après un changement de spé) : réessai
local function RetryLater(tries)
  if (tries or 0) < 5 then C_Timer.After(2, function() CheckSpec((tries or 0) + 1) end) end
end
CheckSpec = function(tries)
  local c = Cfg()
  if not (c and c.enabled ~= false) then return end
  local specID = CDMLayout.CurrentSpecID()
  if not specID or askedThisSession[specID] or SkipTable()[specID] then return end
  if not CDMLayout.GetSpecConfig(specID) then return end
  if not CDMLayout.IsAvailable() then RetryLater(tries); return end
  if InCombatLockdown() then pendingCheck = true; return end
  -- Barres du CDM vides (masquees, pas encore peuplees) : la vraie disposition est illisible, on ne propose rien
  if not CDMLayout.IsExact() then RetryLater(tries); return end
  if CDMLayout.IsApplied(specID) then return end
  askedThisSession[specID] = true
  if not ns.ShowSetupPopup then return end
  ns.ShowSetupPopup("AishCoreCDMLayoutPrompt", L["CDM_LAYOUT_TITLE"],
    string.format(L["CDM_LAYOUT_PROMPT"], CDMLayout.GetActiveName(specID) or "?"), {
    { L["CDM_LAYOUT_APPLY_BTN"], true, function()
        local ok, err = CDMLayout.Apply(CDMLayout.CurrentSpecID())
        if not ok then print("|cffff4444[AishCore]|r " .. tostring(err)) end
      end },
    { L["CDM_RELOAD_LATER"], false, function() end },
    { L["CDM_LAYOUT_NEVER_BTN"], false, function() SkipTable()[specID] = true end },
  })
end

-- /cdmdiff : ecarts entre le CDM et le build de la spe (diagnostic du popup qui revient)
SLASH_AISHCDMDIFF1 = "/cdmdiff"
SlashCmdList["AISHCDMDIFF"] = function()
  local P = "|cff00ccff[CDMDiff]|r "
  local specID = CDMLayout.CurrentSpecID()
  local conf = specID and CDMLayout.GetSpecConfig(specID)
  if not conf then print(P .. "aucun build pour cette spe (specID=" .. tostring(specID) .. ")"); return end
  local list = CDMLayout.ListCooldowns()
  print(P .. string.format("spe=%s build=%s | cooldowns lus=%d | dispo=%s | lecture exacte=%s", tostring(specID),
    tostring(CDMLayout.GetActiveName(specID)), #list, tostring(CDMLayout.IsAvailable()), tostring(CDMLayout.IsExact())))
  local diffs, orderDiffers = CDMLayout.Diff(specID)
  print(P .. string.format("categories differentes=%d | ordre different=%s", #diffs, tostring(orderDiffers)))
  local function nm(e) return (e.spellID and C_Spell.GetSpellName(e.spellID)) or ("#" .. e.cooldownID) end
  for i, d in ipairs(diffs) do
    if i > 15 then print(P .. "..."); break end
    print(P .. string.format("  %s (cid %d) : voulu=%d courant=%d appris=%s", nm(d.entry), d.entry.cooldownID, d.want, d.current, tostring(d.entry.isKnown)))
  end
  if orderDiffers then
    local cur, byId = {}, {}
    for _, e in ipairs(list) do byId[e.cooldownID] = e; if e.current == ESSENTIAL then cur[#cur + 1] = e end end
    local want = {}
    for _, cid in ipairs(CDMLayout.OrderedEssentials(conf, list)) do
      if byId[cid] and byId[cid].isKnown then want[#want + 1] = cid end
    end
    for i = 1, math.max(#cur, #want) do
      local w = want[i] and byId[want[i]]
      print(P .. string.format("  #%d voulu=%s courant=%s", i, w and nm(w) or "-", cur[i] and nm(cur[i]) or "-"))
    end
  end
end

function CDMLayout.ApplySettings() end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ns.TrackSpecFrame(ev)
ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_REGEN_ENABLED" then
    if pendingCheck then pendingCheck = nil; C_Timer.After(1, CheckSpec) end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    -- Laisse le CDM basculer sur la disposition de la nouvelle spé et reconstruire ses frames
    if arg1 == "player" then C_Timer.After(3, CheckSpec) end
  else
    C_Timer.After(4, CheckSpec)
    C_Timer.After(5, ReportApplyErrors)
  end
end)

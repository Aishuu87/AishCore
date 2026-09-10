-- AishUIAura/Core/Init.lua
-- Orchestrateur : DB, état global, helpers de spé, scan dispatch, slash commands
-- Les modules CDM hooks / whitelist / animation / events sont dans Core/*.lua
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

-- Upvalues (règle perf #15 : mise en cache locale des globales)
local wipe, pcall, type, math = wipe, pcall, type, math
local tonumber, tostring, string = tonumber, tostring, string

-- État global
ns._inCombat  = false
ns.auraData   = {}
ns.renderFrames = {}

-- Registre des flags de session ns._* (écrits/lus par les fichiers listés) :
--   _inCombat, _whitelistBuilt, _playerScanPending, _cdmRescanPending [Core/Scan]
--   _equipmentPreview, _equipment3DPreview, _aishPreviewOn, _aishPanelPoint [toggles preview UI]
--   _selectedFx3dSpell, _selectedFx3dLayerIdx, _selectedFx3dTab [Menu Effects, session uniquement]
--   _modelFlat [cache modèles 3D], _rebuildCurrentMenu [hook rebuild SettingsPanel]
-- Tout nouveau flag ns._* doit être ajouté ici avec son owner (à terme, migrer vers ns.state).

-- Effects 3D : flag composite `effectsEnabled` (DB) AND NOT `_effectsSuspended` (runtime).
-- Modèles GPU-intensive (jusqu'à 24 rendus 3D/frame en raid) : option auto-disable, mise à
-- jour par RefreshEffectsSuspension sur PLAYER_ENTERING_WORLD / ZONE_CHANGED.
ns._effectsSuspended = false

function ns.EffectsActive()
    -- Module "Effets 3D Auras" masqué de l'UI (voir CATEGORIES dans SettingsPanel.lua) :
    -- on force la désactivation tout en gardant le code intact pour une réactivation future.
    if true then return false end
    if not ns.db or not ns.db.effectsEnabled then return false end
    return not ns._effectsSuspended
end

function ns.RefreshEffectsSuspension()
    local db = ns.db; if not db then return end
    local shouldSuspend = false
    if db.effects3DAutoDisableInRaid then
        -- IsInInstance retourne le type : "raid", "party", "pvp", "arena", "scenario", "none"
        local ok, _, instType = pcall(IsInInstance)
        if ok and instType == "raid" then shouldSuspend = true end
    end
    if ns._effectsSuspended ~= shouldSuspend then
        ns._effectsSuspended = shouldSuspend
        -- Force un rebuild léger pour que les FX3D se cachent/réapparaissent
        if ns.RebuildDisplay then pcall(ns.RebuildDisplay) end
    end
end

-- ns.Try(tag, fn, ...) : wrapper pcall silencieux, remplacement direct de pcall(function() ... end).
function ns.Try(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    return ok, err
end

-- Lazy load de la bibliothèque de modèles 3D (~19 Mo, ~122 000 entrées) : packagée dans le
-- sous-addon AishUIAuraModels (LoadOnDemand), chargée seulement à la première ouverture du
-- ModelPicker. Partage avec AishCore via la globale pont _G.AishSharedModelFlat pour éviter le
-- doublon RAM (~5-10 Mo) ; dégrade proprement (flatten local) si absent. Retourne true si
-- ns._modelFlat est prêt à l'usage.
function ns.EnsureModelPaths()
    -- Déjà chargée et aplatie : rien à faire
    if ns._modelFlat and #ns._modelFlat > 0 then return true end

    -- PARTAGE 1 : une table aplatie existe déjà en globale pont (AishCore
    -- à jour, ou autre addon partenaire). On la référence directement, 0 copie.
    if _G.AishSharedModelFlat and #_G.AishSharedModelFlat > 0 then
        ns._modelFlat = _G.AishSharedModelFlat
        return true
    end

    -- Tente le chargement du sous-addon
    pcall(function()
        local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if loader then loader("AishUIAuraModels") end
    end)

    -- Fallback : si AishUIAuraModelPaths existe déjà (ex : injection manuelle
    -- ou présence d'un addon partenaire avec AishCoreModelPaths), on l'utilise directement
    local rawPaths = AishUIAuraModelPaths or AishCoreModelPaths
    if not rawPaths then
        return false
    end

    -- Aplatit l'arbre en tableau compact (pattern historique)
    ns._modelFlat = {}
    local function Flatten(node)
        if type(node) ~= "table" then return end
        if node.fileId then
            local fid = tonumber(node.fileId) or 0
            local txt = node.text or node.value or tostring(node.fileId)
            ns._modelFlat[#ns._modelFlat + 1] = { fileId = fid, text = txt }
        end
        if node.children then
            for _, child in ipairs(node.children) do Flatten(child) end
        end
    end
    for _, cat in pairs(rawPaths) do Flatten(cat) end

    -- Expose notre table aplatie via globale pont, pour partage inverse
    -- (si AishCore ouvre son ModelPicker après le nôtre)
    _G.AishSharedModelFlat = ns._modelFlat

    -- Libère l'arbre original : on ne garde que la version aplatie
    AishUIAuraModelPaths = nil
    AishCoreModelPaths = nil
    collectgarbage("collect")

    return true
end

-- Libère la bibliothèque de modèles 3D (appelée à la fermeture du ModelPicker, ~25-30 Mo
-- récupérés). Si notre table est en fait la globale pont partagée avec AishCore, on ne la
-- libère pas (juste notre référence) : AishCore la libérera de son côté. Ré-ouverture :
-- EnsureModelPaths recharge (~0.3-0.5s) via le sous-addon LoadOnDemand.
function ns.ReleaseModelPaths()
    if not ns._modelFlat then return false end
    local wasShared = (ns._modelFlat == _G.AishSharedModelFlat)
    ns._modelFlat = nil
    -- Si c'était la table partagée, on ne libère PAS la globale pont :
    -- AishCore (ou un autre addon partenaire) pourrait encore en avoir besoin.
    if not wasShared then
        _G.AishSharedModelFlat = nil
    end
    -- Au cas où : nettoie aussi les globales qui pourraient avoir été ré-exposées
    AishUIAuraModelPaths = nil
    AishCoreModelPaths = nil
    collectgarbage("collect")
    return true
end

-- Helpers de spécialisation. Clé = "CLASSE_SPE" uniquement (pas de nom/royaume) : la DB est
-- partagée tout le compte, donc une liste "Auras à tracker" configurée sur un personnage doit
-- être retrouvée par tout autre personnage de la même classe/spé. Ancien format (nom-realm
-- inclus) migré une fois vers ce format par MigrateSpecKeys (cf. ns.InitDB).
function ns.GetSpecKey()
    local key
    pcall(function()
        local gS = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
        local gI = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
        if not gS or not gI then return end
        local specID = gI(gS())
        if not specID then return end
        local m = ns.SPEC_MAP[specID]
        if m then
            key = m.class .. "_" .. m.spec
        end
    end)
    return key
end

-- Mode admin ("Auras à tracker") : ns.db.adminOverrides[spellID] = { source="debuff"|"buff"|"totem"
-- (reclassification manuelle, prioritaire sur l'auto-découverte), deleted=true (masque le sort, cf.
-- Tactics.lua) }. Stockage GLOBAL (pas par spec) car un spellID désigne le même sort partout.
-- Objectif final : brouillon à exporter (ns.ExportAdminOverrides) puis intégrer en dur -- un addon
-- ne peut pas réécrire ses .lua, donc ce SavedVariables reste une étape intermédiaire.
function ns.ApplyAdminOverrides(spells)
    if not spells then return end
    -- Baseline codée en dur (SpellClassificationOverrides.lua) pour tous, puis override
    -- personnel du joueur (ns.db.adminOverrides, /aishadmin) par-dessus qui garde le dernier mot.
    local hardcoded = ns.SpellClassificationOverrides
    if hardcoded then
        for spellID, o in pairs(hardcoded) do
            local info = spells[spellID]
            if info then
                if o.source then info.source = o.source end
                if o.deleted then info._adminDeleted = true end
            end
        end
    end
    local ov = ns.db and ns.db.adminOverrides
    if not ov then return end
    for spellID, o in pairs(ov) do
        local info = spells[spellID]
        if info then
            if o.source then info.source = o.source end
            -- o.deleted est toujours un booléen explicite ici (jamais nil, cf. SetAdminDeletedOverride) :
            -- même décoché (false), ce choix doit prévaloir sur une suppression codée en dur ci-dessus.
            if o.deleted ~= nil then info._adminDeleted = o.deleted or nil end
        end
    end
end

function ns.SetAdminSourceOverride(spellID, source)
    if not ns.db then return end
    ns.db.adminOverrides = ns.db.adminOverrides or {}
    local o = ns.db.adminOverrides[spellID]
    if not o then o = {}; ns.db.adminOverrides[spellID] = o end
    o.source = source
end

function ns.SetAdminDeletedOverride(spellID, deleted)
    if not ns.db then return end
    ns.db.adminOverrides = ns.db.adminOverrides or {}
    local o = ns.db.adminOverrides[spellID]
    if not o then o = {}; ns.db.adminOverrides[spellID] = o end
    -- Booléen explicite (jamais nil) : distingue "jamais touché" (clé absente) de "explicitement
    -- décoché" (false), pour qu'annuler une suppression hardcodée (SpellClassificationOverrides) tienne.
    o.deleted = deleted and true or false
end

function ns.GetSpecSpells()
    local key = ns.GetSpecKey()
    if not key or not ns.db then return nil end
    if not ns.db.discoveredSpells then ns.db.discoveredSpells = {} end
    if not ns.db.discoveredSpells[key] then ns.db.discoveredSpells[key] = {} end
    local spells = ns.db.discoveredSpells[key]
    ns.ApplyAdminOverrides(spells)
    return spells, key
end

-- /aishsourcelist : liste les sorts classés source="debuff" (cf. CDMHooks.lua::InitCDMHooks) pour
-- la spec courante, pour repérer les auto-buffs mal classifiés (ex: Rapidité de la nature/378081).
SLASH_AISHSOURCELIST1 = "/aishsourcelist"
SlashCmdList["AISHSOURCELIST"] = function()
    local P = "|cff00ffff[AishCore]|r "
    local spells, key = ns.GetSpecSpells()
    if not spells then
        print(P .. "GetSpecSpells() indisponible.")
        return
    end
    print(P .. string.format("Spec courante : %s", tostring(key)))
    local n = 0
    for spellID, info in pairs(spells) do
        if info.source == "debuff" then
            n = n + 1
            local name = (GetSpellName and GetSpellName(spellID)) or info.name or "?"
            print(P .. string.format("  %d (%s)", spellID, tostring(name)))
        end
    end
    print(P .. string.format("Total : %d sort(s) classe(s) \"debuff\".", n))
end

-- Init DB
-- Migration v3.9 : renommage des clés internes des 4 renders (debuffs/buffs/cooldowns/procs →
-- noms sémantiques), exécutée une seule fois au chargement si les vieilles clés existent encore.
local _RENDER_KEY_MAP = { debuffs="iconlist", buffs="freebars", cooldowns="circlebars", procs="icons" }
local _ENABLED_KEY_MAP = {
    debuffsEnabled="iconlistEnabled", buffsEnabled="freebarsEnabled",
    cooldownsEnabled="circlebarsEnabled", procsEnabled="iconsEnabled",
}

local function MigrateRenderKeys(raw)
    -- 1. Clés de premier niveau (sections de config render)
    for old, new in pairs(_RENDER_KEY_MAP) do
        if raw[old] ~= nil and raw[new] == nil then
            raw[new] = raw[old]
        end
        raw[old] = nil
    end
    -- 1b. Flags enabled correspondants
    for old, new in pairs(_ENABLED_KEY_MAP) do
        if raw[old] ~= nil and raw[new] == nil then
            raw[new] = raw[old]
        end
        raw[old] = nil
    end
    -- 2. Clés destinations dans chaque sort découvert
    if raw.discoveredSpells then
        for _, specSpells in pairs(raw.discoveredSpells) do
            for _, info in pairs(specSpells) do
                local dest = info.destinations
                if dest then
                    for old, new in pairs(_RENDER_KEY_MAP) do
                        if dest[old] ~= nil then
                            if dest[new] == nil then dest[new] = dest[old] end
                            dest[old] = nil
                        end
                    end
                end
            end
        end
    end
end

-- Migration : InitCDMHooks (CDMHooks.lua) étiquette tout sort découvert via un viewer
-- Essentiel/Utilitaire comme source="debuff", ce qui est faux pour les sorts qui s'octroient
-- un buff à eux-mêmes (Blizzard ne distingue pas les deux au niveau du viewer). Corrige une
-- bonne fois les sorts concernés (378081, 2825, 61295) déjà découverts sur tous les personnages ;
-- le hook auto-correcteur dans CDMHooks.lua::SetAuraInstanceInfo évite que ça se reproduise.
local _MISCLASSIFIED_SELF_BUFFS = { [378081] = true, [2825] = true, [61295] = true }
local function MigrateMisclassifiedSelfBuffSource(raw)
    if not raw or not raw.discoveredSpells then return end
    for _, specSpells in pairs(raw.discoveredSpells) do
        for spellID, info in pairs(specSpells) do
            if _MISCLASSIFIED_SELF_BUFFS[spellID] and info.source == "debuff" then
                info.source = "buff"
            end
        end
    end
end

-- Migration : Totems.lua::OnTotemSlotChanged reclassifie un sort en source="totem" à la pose
-- (PLAYER_TOTEM_UPDATE) mais ne nettoyait jusqu'ici jamais ses destinations existantes : plusieurs
-- vrais totems restaient traqués sur iconlist/circlebars/freebars/icons depuis avant leur
-- reclassification, invisibles/impossibles à décocher dans l'UI mais actifs -- chaque pose faisait
-- apparaître des barres fantômes en plus de la barre totem attendue. Fix en place côté Totems.lua
-- pour le futur ; ceci nettoie une bonne fois les entrées déjà corrompues sur tous les personnages/spés.
local function MigrateOrphanedTotemDestinations(raw)
    if not raw or not raw.discoveredSpells then return end
    for _, specSpells in pairs(raw.discoveredSpells) do
        for _, info in pairs(specSpells) do
            if info.source == "totem" and info.destinations then
                info.destinations.iconlist = false
                info.destinations.circlebars = false
                info.destinations.freebars = false
                info.destinations.icons = false
            end
        end
    end
end

-- Migration : ns.GetSpecKey() incluait auparavant nom-royaume ("Perso-Royaume_CLASSE_SPE"),
-- fragmentant par personnage une DB déjà partagée tout le compte. Nouveau format : "CLASSE_SPE"
-- seul. Fusionne additivement (n'écrase jamais une entrée déjà présente) le contenu de chaque
-- ancienne clé vers sa nouvelle clé, puis supprime les anciennes clés (mesuré : ~52% de
-- discoveredSpells sur une DB réelle, fusion sans perte). Exposée sur ns (pas locale, idempotente)
-- pour être réutilisée par Prof:Import (Profiles.lua) ; ns.InitDB pose son propre flag one-shot.
function ns.MigrateSpecKeys(raw)
    if not raw or not raw.discoveredSpells then return end

    local validKeys = {}
    for _, m in pairs(ns.SPEC_MAP) do
        validKeys[m.class .. "_" .. m.spec] = true
    end

    -- Copie des clés avant mutation : la boucle peut créer de nouvelles clés cibles dans
    -- raw.discoveredSpells, ce qu'un pairs() en cours d'itération ne garantit pas de gérer.
    local existingKeys = {}
    for key in pairs(raw.discoveredSpells) do existingKeys[#existingKeys + 1] = key end

    for _, key in ipairs(existingKeys) do
        if not validKeys[key] then
            for suffix in pairs(validKeys) do
                if key:sub(-(#suffix + 1)) == ("_" .. suffix) then
                    local specSpells = raw.discoveredSpells[key]
                    if not raw.discoveredSpells[suffix] then raw.discoveredSpells[suffix] = {} end
                    local target = raw.discoveredSpells[suffix]
                    for sid, info in pairs(specSpells) do
                        if target[sid] == nil then target[sid] = info end
                    end
                    -- Fusion terminee (additive, aucune perte) : la clé
                    -- source ne sert plus jamais à rien -- supprimée.
                    raw.discoveredSpells[key] = nil
                    break
                end
            end
        end
    end
end

-- Checkup mémoire : nettoyage one-shot distinct de _specKeyMigratedV1 (déjà consommé), nécessaire
-- pour se redéclencher sur les comptes déjà migrés. Nettoie aussi profiles[*].discoveredSpells :
-- ce champ n'est jamais lu depuis un profil (Prof:InitDB/SetActive et Prof:Export utilisent tous
-- la référence partagée db.discoveredSpells) mais reste sérialisé en double sur disque -- 100% mort.
local function CleanupDeadDBBloat(raw)
    if not raw then return end
    pcall(ns.MigrateSpecKeys, raw)
    if raw.profiles then
        for _, prof in pairs(raw.profiles) do
            if type(prof) == "table" then prof.discoveredSpells = nil end
        end
    end
end

-- Bulk glow par défaut : bascule le glow de toutes les spés déjà enregistrées dans le profil
-- "Default" (db.defaultGlowBySpec, cf. GetDefaultGlowCfg dans Tactics.lua) sur idx=6 ("Assist White")
-- /alpha=0.6, sans toucher couleur/échelle/proc. Met aussi à jour les clés "seed" defaultGlowIdx/Alpha
-- pour couvrir les spés jamais ouvertes. One-shot (raw._defaultGlowBulkSetV1), profil "Default" only.
local function BulkSetDefaultGlow(raw)
    if not raw or not raw.profiles then return end
    local profile = raw.profiles["Default"]
    if type(profile) ~= "table" then return end
    profile.defaultGlowIdx = 6
    profile.defaultGlowAlpha = 0.6
    if type(profile.defaultGlowBySpec) == "table" then
        for _, cfg in pairs(profile.defaultGlowBySpec) do
            if type(cfg) == "table" then
                cfg.idx = 6
                cfg.alpha = 0.6
            end
        end
    end
end

-- Bulk animation proc par défaut (complément de BulkSetDefaultGlow) : le glow en boucle et
-- l'animation proc (defaultProcGlowIdx/cfg.procIdx) sont deux réglages séparés, ce dernier
-- restait à 1 ("Aucun") pour toute spé non personnalisée. Bascule sur idx=75 ("Proc: White Short"
-- dans ns.GLOW_DEFS). Même portée que BulkSetDefaultGlow (profil "Default", flag one-shot distinct).
local function BulkSetDefaultProcGlow(raw)
    if not raw or not raw.profiles then return end
    local profile = raw.profiles["Default"]
    if type(profile) ~= "table" then return end
    profile.defaultProcGlowIdx = 75
    if type(profile.defaultGlowBySpec) == "table" then
        for _, cfg in pairs(profile.defaultGlowBySpec) do
            if type(cfg) == "table" then
                cfg.procIdx = 75
            end
        end
    end
end

function ns.InitDB()
    if not AishUIAuraDB then AishUIAuraDB = {} end
    local raw = AishUIAuraDB
    -- Migration des anciennes clés avant tout MergeDefaults
    MigrateRenderKeys(raw)
    if not raw._specKeyMigratedV1 then
        ns.MigrateSpecKeys(raw)
        raw._specKeyMigratedV1 = true
    end
    -- Nouveau flag distinct de _specKeyMigratedV1 (déjà consommé) : nécessaire pour redéclencher
    -- le nettoyage une fois sur les comptes déjà migrés. cf. CleanupDeadDBBloat.
    if not raw._dbCleanupV1 then
        CleanupDeadDBBloat(raw)
        raw._dbCleanupV1 = true
    end
    if not raw._defaultGlowBulkSetV1 then
        BulkSetDefaultGlow(raw)
        raw._defaultGlowBulkSetV1 = true
    end
    if not raw._defaultProcGlowBulkSetV1 then
        BulkSetDefaultProcGlow(raw)
        raw._defaultProcGlowBulkSetV1 = true
    end
    if not raw._misclassifiedSelfBuffSourceV1 then
        MigrateMisclassifiedSelfBuffSource(raw)
        raw._misclassifiedSelfBuffSourceV1 = true
    end
    if not raw._orphanedTotemDestinationsV1 then
        MigrateOrphanedTotemDestinations(raw)
        raw._orphanedTotemDestinationsV1 = true
    end
    ns.MergeDefaults(raw, ns.Defaults)
    for _, key in ipairs({"iconlist","freebars","circlebars","icons","equipment","totems"}) do
        if not raw[key] or type(raw[key]) ~= "table" then
            raw[key] = ns.DeepCopy(ns.Defaults[key])
        else
            ns.MergeDefaults(raw[key], ns.Defaults[key])
        end
    end
    local db = ns.Profiles and ns.Profiles:InitDB() or raw
    db.addonVersion = ns.ADDON_VERSION
    if not db.discoveredSpells then db.discoveredSpells = {} end
    for _, specSpells in pairs(db.discoveredSpells) do
        for _, info in pairs(specSpells) do
            if not info.destinations then info.destinations = ns.DeepCopy(ns.SpellDefaults.destinations) end
            if info.glow == nil then info.glow = false end
            if not info.glowIdx then info.glowIdx = 2 end
            if not info.glowAlpha then info.glowAlpha = 0.7 end
            if info.desat == nil then info.desat = false end
            if not info.procGlowIdx then info.procGlowIdx = 1 end
            if not info.procGlowScale then info.procGlowScale = 1.0 end
            -- Migration _glowCustom (feature glow par défaut) : verrouille (true) tout sort qui avait
            -- déjà un glow actif pour ne jamais écraser un réglage utilisateur ; sinon suit le défaut.
            if info._glowCustom == nil then info._glowCustom = (info.glow == true) end
        end
    end
    ns.db = db
end


-- Scan / dispatch de rebuild
function ns.ScanAuras()
    if not ns._whitelistBuilt then ns.BuildWhitelist() end
    if ns.Scan then ns.Try("Scan:Run", ns.Scan.Run, ns.Scan) end
    -- Scan.Run ne réveille l'animDriver que si de vraies auras sont actives ; le mode aperçu
    -- (fausses barres via ns._previewBars) n'en a aucune donc ne le réveille jamais de lui-même.
    -- Sans cet appel explicite, le spark de la fausse barre resterait créé mais jamais ancré.
    if ns._previewBars and ns.WakeAnimDriver then ns.WakeAnimDriver() end
end

function ns.InitAllRenders()
    if not ns.db or not ns.db.enabled then return end
    -- Chaque render:Init() recrée ses conteneurs, avec des appels protégés en combat (ex:
    -- SetPropagateMouseClicks -- confirmé en jeu : ADDON_ACTION_BLOCKED en plein pull après reload).
    -- On diffère tout le cycle au prochain PLAYER_REGEN_ENABLED (cf. Events.lua) plutôt que
    -- de laisser chaque render planter un à un.
    if InCombatLockdown and InCombatLockdown() then
        ns._pendingRenderInit = true
        return
    end
    if ns.db.useNativeCDM then
        for _, rf in pairs(ns.renderFrames) do
            if rf and rf.container then
                if rf.rows then for _, r in ipairs(rf.rows) do r:Hide() end end
                rf.container:Hide()
            end
        end
        return
    end
    for _, render in pairs(ns.RenderRegistry) do
        if render.Init then pcall(function() render:Init() end) end
    end
end

function ns.RebuildDisplay() ns.InitAllRenders(); ns.ScanAuras() end

-- Colorisation de barre avec dégradé (SetGradient sur StatusBarTexture). Helpers top-level pour
-- ApplyBarColor (appelé à chaque scan/Update render) : évite 2 closures pcall par appel.
local function _SetBarGradient(tex, r, g, b, gr, gg, gb)
    if tex.SetGradient then
        tex:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(gr, gg, gb, 1))
    end
end

local function _ResetBarGradient(tex)
    if tex.SetGradient then
        tex:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
    end
end

function ns.ApplyBarColor(bar, renderKey, aura)
    if not bar then return end
    local cfg = ns.db and ns.db[renderKey]
    local r, g, b = ns.barColor[1], ns.barColor[2], ns.barColor[3]

    -- Priorité 1 : couleur/gradient par sort (render Buffs uniquement, menu "Couleur par sort").
    -- Storage : ns.db.buffs.spellGradients[spellID] = {r1,g1,b1,r2,g2,b2,gradEnabled}.
    -- gradEnabled=true → gradient (r1,g1,b1)→(r2,g2,b2), sinon couleur fixe (r1,g1,b1).
    -- Flag _spellGradientActive pour qu'ApplyUrgencyColor n'écrase pas le SetGradient à chaque tick.
    if renderKey == "freebars" and aura and aura.spellID
       and cfg and cfg.spellGradients and cfg.spellGradients[aura.spellID] then
        local sg = cfg.spellGradients[aura.spellID]
        local r1, g1, b1 = sg[1] or 1, sg[2] or 1, sg[3] or 1
        if sg[7] == true then
            -- Gradient : flag actif, ApplyUrgencyColor doit skip pour cette barre
            local r2, g2, b2 = sg[4] or r1*0.3, sg[5] or g1*0.3, sg[6] or b1*0.3
            bar:SetStatusBarColor(1, 1, 1, 1)
            local tex = bar:GetStatusBarTexture()
            if tex then pcall(_SetBarGradient, tex, r1, g1, b1, r2, g2, b2) end
            bar._spellGradientActive = true
        else
            -- Couleur fixe : la curve d'urgence peut teinter normalement a partir de cette couleur,
            -- donc pas de flag bypass. ApplyUrgencyColor recevra la bonne base via cR/cG/cB
            -- (cf. Animation.lua AnimateRender).
            local tex = bar:GetStatusBarTexture()
            if tex then pcall(_ResetBarGradient, tex) end
            bar:SetStatusBarColor(r1, g1, b1)
            bar._spellGradientActive = false
        end
        return
    end

    -- Pas d'override par sort : reset le flag
    bar._spellGradientActive = false

    -- PRIORITE 2 : couleur du render override la couleur globale
    if cfg and cfg.barColorR ~= nil then r, g, b = cfg.barColorR, cfg.barColorG or g, cfg.barColorB or b end
    -- PRIORITE 3 : couleur du sort override celle du render (sauf si le render a une couleur explicite)
    if not (cfg and cfg.barColorR ~= nil) and ns.db and ns.db.useSpellColors and aura and aura.spellColor then
        r, g, b = aura.spellColor[1], aura.spellColor[2], aura.spellColor[3]
    end
    -- Mode dégradé render (override "global" pour ce render)
    if cfg and cfg.gradientEnabled then
        local gr = cfg.gradientR2 or r*0.3
        local gg = cfg.gradientG2 or g*0.3
        local gb = cfg.gradientB2 or b*0.3
        bar:SetStatusBarColor(1, 1, 1, 1)
        local tex = bar:GetStatusBarTexture()
        if tex then pcall(_SetBarGradient, tex, r, g, b, gr, gg, gb) end
    else
        -- Reset du dégradé s'il était actif
        local tex = bar:GetStatusBarTexture()
        if tex then pcall(_ResetBarGradient, tex) end
        bar:SetStatusBarColor(r, g, b)
    end
end

-- Commandes slash
SLASH_AISHUIAURA1 = "/aa"
SLASH_AISHUIAURA2 = "/aishaura"
SlashCmdList["AISHUIAURA"] = function(msg)
    if _addon.SettingsPanel then
        _addon.SettingsPanel:Toggle()
    end
end

-- Rappel reload : message chat après modification de modèles 3D. Blizzard ne libère jamais un
-- .m2 chargé (PlayerModel:SetModel) avant un /reload complet -- la RAM monte progressivement.
-- Pas de StaticPopup : ce système partage des slots avec les popups Blizzard natifs
-- (QUIT_GAME_DIALOG, CAMP, LOGOUT) et hérite parfois leur callback protégé → ADDON_ACTION_FORBIDDEN.
-- D'où un simple message chat persistant.
function ns.ShowReloadPrompt()
    if not ns._fx3dDirty then return end
    -- On affiche une seule fois par session pour ne pas spammer.
    if ns._reloadHintShown then return end
    ns._reloadHintShown = true

    -- Couleur or de la charte AishUI
    local g = (ns.THEME and ns.THEME.gold) or { 0.78, 0.62, 0.30 }
    local goldHex = string.format("%02x%02x%02x",
        math.floor(g[1] * 255), math.floor(g[2] * 255), math.floor(g[3] * 255))

    print(string.format(
        "|cff%s[AishUI]|r Modèles 3D modifiés. Un |cffffff00/reload|r est recommandé pour libérer la mémoire des anciens modèles.",
        goldHex))
end

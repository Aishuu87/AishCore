-- AishUIAura/Core/Init.lua
-- Orchestrateur : DB, état global, helpers de spé, scan dispatch, slash commands
-- Les modules CDM hooks / whitelist / animation / events sont dans Core/*.lua
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

------------------------------------------------------------------------
-- UPVALUES (règle perf #15 : mise en cache locale des globales)
------------------------------------------------------------------------
local wipe, pcall, type, math = wipe, pcall, type, math
local tonumber, tostring, string = tonumber, tostring, string

------------------------------------------------------------------------
-- ÉTAT GLOBAL
------------------------------------------------------------------------
ns._inCombat  = false
ns.auraData   = {}
ns.renderFrames = {}

------------------------------------------------------------------------
-- REGISTRE DES FLAGS DE SESSION
-- Documentation de tous les ns._* utilisés dans l'addon.
-- Écrits/lus par les fichiers listés entre crochets.
--
-- État cœur de session :
--   ns._inCombat            bool     État combat via PLAYER_REGEN_* [Core]
--   ns._whitelistBuilt      bool     Flag lazy : whitelist à reconstruire [Core/Scan]
--   ns._playerScanPending   bool     Scan joueur en attente (rate limit) [Core]
--   ns._cdmRescanPending    bool     Rescan CDM en attente [Core]
--
-- Toggles de preview (pilotés par l'UI) :
--   ns._equipmentPreview    bool     Menu Equipment actuellement visible [Equipment OnShow/OnHide]
--   ns._equipment3DPreview  bool     Flag du mode preview 3D Equipment [Menu Effects]
--   ns._aishPreviewOn       bool     Toggle preview du panneau externe [Menu Preview]
--   ns._aishPanelPoint      table    Sauvegarde de la position du panneau externe [Menu Preview]
--
-- État de l'éditeur Effects (par session, non persisté) :
--   ns._selectedFx3dSpell   number   Sort actuellement sélectionné [Menu Effects]
--   ns._selectedFx3dLayerIdx number  Index de couche actuellement sélectionné [Menu Effects]
--   ns._selectedFx3dTab     string   Nom de l'onglet éditeur actif [Menu Effects]
--
-- Caches de données :
--   ns._modelFlat           table    Cache de chemins modèles aplatis [Data/ModelPaths]
--
-- Callbacks enregistrés à l'exécution :
--   ns._rebuildCurrentMenu  function Hook de rebuild complet du menu actif [SettingsPanel]
--
-- Règle : tout nouveau flag ns._* DOIT être ajouté à cette liste avec son owner.
-- À terme, tout ceci devrait migrer vers une table unifiée ns.state.
------------------------------------------------------------------------

------------------------------------------------------------------------
-- EFFECTS 3D : flag composite `effectsEnabled` (DB) AND NOT `_effectsSuspended` (runtime)
-- Les modèles 3D sont GPU-intensive : 8 DoTs × 3 modèles par bar = 24 rendus 3D par
-- frame. En raid c'est souvent le vrai goulot. On offre une option auto-disable.
-- Mis à jour par RefreshEffectsSuspension sur PLAYER_ENTERING_WORLD / ZONE_CHANGED.
------------------------------------------------------------------------
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

------------------------------------------------------------------------
-- ns.Try(tag, fn, ...) — wrapper pcall silencieux (sans log).
-- Retourne comme pcall : (ok, result_or_error).
-- Remplacement direct pour `pcall(function() ... end)`.
------------------------------------------------------------------------
function ns.Try(tag, fn, ...)
    local ok, err = pcall(fn, ...)
    return ok, err
end

------------------------------------------------------------------------
-- LAZY LOAD DE LA BIBLIOTHÈQUE DE MODÈLES 3D
--
-- La bibliothèque AishUIAuraModelPaths (~19 MB, ~122 000 entrées) est
-- volontairement packagée dans un sous-addon AishUIAuraModels marqué
-- LoadOnDemand. Elle n'est chargée QUE lors de la première ouverture du
-- ModelPicker, ce qui économise ~25 MB de RAM pour les utilisateurs qui
-- n'ouvrent jamais le picker.
--
-- PARTAGE AVEC Aishaddon (économie ~5-10 MB de doublon RAM) :
-- Si l'user a aussi Aishaddon installé, Aishaddon expose sa table
-- aplatie sous _G.AishSharedModelFlat (globale pont). AishUIAura la
-- détecte et la réutilise sans flatten. Dégrade proprement si Aishaddon
-- n'est pas à jour (flatten local classique).
--
-- On expose aussi NOTRE _modelFlat sous _G.AishSharedModelFlat pour que
-- toute version future d'Aishaddon puisse faire le partage inverse.
--
-- Retourne true si la table est prête à l'usage (ns._modelFlat), false sinon.
------------------------------------------------------------------------
function ns.EnsureModelPaths()
    -- Déjà chargée et aplatie : rien à faire
    if ns._modelFlat and #ns._modelFlat > 0 then return true end

    -- PARTAGE 1 : une table aplatie existe déjà en globale pont (Aishaddon
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
    -- ou présence d'un addon partenaire avec AishaddonModelPaths), on l'utilise directement
    local rawPaths = AishUIAuraModelPaths or AishaddonModelPaths
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
    -- (si Aishaddon ouvre son ModelPicker après le nôtre)
    _G.AishSharedModelFlat = ns._modelFlat

    -- Libère l'arbre original : on ne garde que la version aplatie
    AishUIAuraModelPaths = nil
    AishaddonModelPaths = nil
    collectgarbage("collect")

    return true
end

------------------------------------------------------------------------
-- LIBÉRATION DE LA BIBLIOTHÈQUE DE MODÈLES 3D
--
-- Appelée à la fermeture du ModelPicker pour faire redescendre la RAM.
-- Après appel, ns._modelFlat est vide et la table aplatie est garbage-collected.
-- Le prochain usage (nouvelle ouverture du picker) re-déclenchera EnsureModelPaths
-- qui rechargera via le sous-addon LoadOnDemand.
--
-- PARTAGE : si notre table est en fait la globale pont _G.AishSharedModelFlat
-- (= partagée avec Aishaddon), on NE la libère PAS (car Aishaddon en a besoin).
-- On se contente de lâcher notre référence. Aishaddon la libérera de son côté,
-- et le GC la récupérera quand plus personne ne pointe dessus.
--
-- Coût de ré-ouverture : ~0.3-0.5s (charge + aplatissement) si on a flatten.
-- Gain : libère ~25-30 MB de RAM entre deux usages (ou 0 MB si partagée).
------------------------------------------------------------------------
function ns.ReleaseModelPaths()
    if not ns._modelFlat then return false end
    local wasShared = (ns._modelFlat == _G.AishSharedModelFlat)
    ns._modelFlat = nil
    -- Si c'était la table partagée, on ne libère PAS la globale pont :
    -- Aishaddon (ou un autre addon partenaire) pourrait encore en avoir besoin.
    if not wasShared then
        _G.AishSharedModelFlat = nil
    end
    -- Au cas où : nettoie aussi les globales qui pourraient avoir été ré-exposées
    AishUIAuraModelPaths = nil
    AishaddonModelPaths = nil
    collectgarbage("collect")
    return true
end

------------------------------------------------------------------------
-- HELPERS DE SPÉCIALISATION
------------------------------------------------------------------------
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
            local name = UnitName("player") or "?"
            local realm = GetRealmName() or "?"
            key = name .. "-" .. realm .. "_" .. m.class .. "_" .. m.spec
        end
    end)
    return key
end

function ns.GetSpecSpells()
    local key = ns.GetSpecKey()
    if not key or not ns.db then return nil end
    if not ns.db.discoveredSpells then ns.db.discoveredSpells = {} end
    if not ns.db.discoveredSpells[key] then ns.db.discoveredSpells[key] = {} end
    return ns.db.discoveredSpells[key], key
end

------------------------------------------------------------------------
-- INIT DB
------------------------------------------------------------------------
-- Migration v3.9 : renommage des clés internes des 4 renders.
-- Anciens noms (debuffs/buffs/cooldowns/procs) → nouveaux noms sémantiques.
-- Exécutée une seule fois au chargement si les vieilles clés existent encore.
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

function ns.InitDB()
    if not AishUIAuraDB then AishUIAuraDB = {} end
    local raw = AishUIAuraDB
    -- Migration des anciennes clés avant tout MergeDefaults
    MigrateRenderKeys(raw)
    ns.MergeDefaults(raw, ns.Defaults)
    for _, key in ipairs({"iconlist","freebars","circlebars","icons","equipment"}) do
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
        end
    end
    ns.db = db
end


------------------------------------------------------------------------
-- SCAN / DISPATCH DE REBUILD
------------------------------------------------------------------------
function ns.ScanAuras()
    if not ns._whitelistBuilt then ns.BuildWhitelist() end
    if ns.Scan then ns.Try("Scan:Run", ns.Scan.Run, ns.Scan) end
end

function ns.InitAllRenders()
    if not ns.db or not ns.db.enabled then return end
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

-- Colorisation de barre avec dégradé (SetGradient sur StatusBarTexture)
-- Helpers top-level pour ApplyBarColor : évite 2 closures pcall par appel.
-- ApplyBarColor est appelé à chaque scan et à chaque Update render.
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

    -- PRIORITE 1 : couleur/gradient par sort (UNIQUEMENT pour le render Buffs).
    -- Si l'utilisateur a defini un override pour ce sort dans le menu
    -- Buffs > "COULEUR PAR SORT", il override tout le reste.
    -- Storage : ns.db.buffs.spellGradients[spellID] = {r1, g1, b1, r2, g2, b2, gradEnabled}
    --   - gradEnabled = true  → gradient (r1,g1,b1) → (r2,g2,b2)
    --   - gradEnabled = false ou nil → couleur fixe (r1,g1,b1) — UX plus simple par defaut
    -- IMPORTANT : pour le mode gradient on flag la barre via _spellGradientActive
    -- afin que ApplyUrgencyColor (driver d'anim) ne vienne pas ecraser le SetGradient
    -- via SetStatusBarColor a chaque tick.
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

------------------------------------------------------------------------
-- COMMANDES SLASH
------------------------------------------------------------------------
SLASH_AISHUIAURA1 = "/aa"
SLASH_AISHUIAURA2 = "/aishaura"
SlashCmdList["AISHUIAURA"] = function(msg)
    if _addon.SettingsPanel then
        _addon.SettingsPanel:Toggle()
    end
end

------------------------------------------------------------------------
-- RAPPEL RELOAD : message chat après modification de modèles 3D.
--
-- Contexte : quand Blizzard charge un .m2 (via PlayerModel:SetModel), ce modèle
-- reste en RAM GPU/CPU pour toute la session WoW. L'API Lua n'expose aucune
-- méthode pour le décharger. Si l'user change plusieurs fois de modèle, la RAM
-- monte progressivement (chaque modèle ajouté = +500 KB à 2 MB permanents).
--
-- Le seul moyen de libérer cette RAM est un /reload qui détruit toute la session
-- Lua et force Blizzard à repartir d'un état propre.
--
-- IMPLÉMENTATION : on UTILISE PAS de StaticPopup car ce système partage des
-- slots avec les popups Blizzard natifs (QUIT_GAME_DIALOG, CAMP, LOGOUT) qui
-- ont des callbacks protégés (ForceQuit, CancelLogout). En cas de collision
-- de slot, notre popup hérite du callback Blizzard → ADDON_ACTION_FORBIDDEN
-- au moindre clic sur OK. Toutes les protections (exclusive, preferredIndex,
-- hook StaticPopup_Show) ont été tentées et ne couvrent pas tous les cas
-- edge. Solution radicale : pas de popup, juste un message chat persistant.
------------------------------------------------------------------------
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

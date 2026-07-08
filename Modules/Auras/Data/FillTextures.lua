-- AishUIAura/Data/FillTextures.lua
-- ============================================================================
-- Catalogue des 15 textures de remplissage disponibles pour le mode "Remplissage"
-- (pattern LinearProgressTexture).
--
-- Chaque entree definit :
--   - id        : cle unique (servira aussi de path)
--   - label     : texte affiche dans le dropdown
--   - scrollDef : vitesse de scroll par defaut (0 = statique, 0.3-1.0 anime)
--
-- Les textures sont en 256x64 dans Media/UI/FillTextures/, generees
-- proceduralement (Python + seed 4242 pour reproductibilite).
-- ============================================================================

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras

local TEX_BASE = "Interface\\AddOns\\Aishaddon\\Media\\UI\\FillTextures\\"

ns.FillTextures = {
    { id="FillBrique",          label="Brique",            scrollDef=0   },
    { id="FillOr",              label="Or",                scrollDef=0   },
    { id="FillBleu",            label="Bleu",              scrollDef=0   },
    { id="FillLisse",           label="Lisse",             scrollDef=0   },
    { id="FillFlamme",          label="Flamme",            scrollDef=0.7 },
    { id="FillPlasma",          label="Plasma",            scrollDef=0.5 },
    { id="FillFoudre",          label="Foudre",            scrollDef=1.0 },
    { id="FillVague",           label="Vague",             scrollDef=0.3 },
    { id="FillEau",             label="Eau",               scrollDef=0.15},
    { id="FillTrame",           label="Trame oblique",     scrollDef=0   },
    { id="FillFumee",           label="Fumee",             scrollDef=0.2 },
    { id="FillStripesFin",      label="Rayures fines",     scrollDef=0   },
    { id="FillStripesEpais",    label="Rayures epaisses",  scrollDef=0   },
    { id="FillRayuresObliques", label="Chevrons or",       scrollDef=0   },
    { id="FillBande",           label="Bande lumineuse",   scrollDef=0   },
}

-- Helper : retourne le path complet pour une texture id
function ns.GetFillTexturePath(id)
    if not id or id == "" then return "" end
    return TEX_BASE .. id
end

-- Helper : retourne le label d'une texture id (pour affichage UI)
function ns.GetFillTextureLabel(id)
    if not id or id == "" then return "(aucune)" end
    -- Si l'id contient deja le path complet, on extrait juste le nom de fichier
    local justId = id:match("([^\\/]+)$") or id
    for _, t in ipairs(ns.FillTextures) do
        if t.id == justId then return t.label end
    end
    return justId  -- fallback
end

-- Helper : retourne la vitesse de scroll par defaut pour une texture id
function ns.GetFillTextureScrollDef(id)
    if not id or id == "" then return 0 end
    local justId = id:match("([^\\/]+)$") or id
    for _, t in ipairs(ns.FillTextures) do
        if t.id == justId then return t.scrollDef or 0 end
    end
    return 0
end

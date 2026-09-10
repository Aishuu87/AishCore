-- FillTextures.lua : catalogue des textures de remplissage (mode "Remplissage", LinearProgressTexture)
-- id = cle/path, label = texte dropdown, scrollDef = vitesse de scroll (0 = statique)

local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L

local TEX_BASE = "Interface\\AddOns\\AishCore\\Media\\UI\\FillTextures\\"

ns.FillTextures = {
    { id="FillBrique",          label=L["AURASDATA_FILLTEX_BRICK"],            scrollDef=0   },
    { id="FillOr",              label=L["AURASDATA_FILLTEX_GOLD"],                scrollDef=0   },
    { id="FillBleu",            label=L["AURASDATA_FILLTEX_BLUE"],              scrollDef=0   },
    { id="FillLisse",           label=L["AURASDATA_FILLTEX_SMOOTH"],             scrollDef=0   },
    { id="FillFlamme",          label=L["AURASDATA_FILLTEX_FLAME"],             scrollDef=0.7 },
    { id="FillPlasma",          label=L["AURASDATA_FILLTEX_PLASMA"],             scrollDef=0.5 },
    { id="FillFoudre",          label=L["AURASDATA_FILLTEX_LIGHTNING"],            scrollDef=1.0 },
    { id="FillVague",           label=L["AURASDATA_FILLTEX_WAVE"],             scrollDef=0.3 },
    { id="FillEau",             label=L["AURASDATA_FILLTEX_WATER"],               scrollDef=0.15},
    { id="FillTrame",           label=L["AURASDATA_FILLTEX_DIAGONAL_WEAVE"],     scrollDef=0   },
    { id="FillFumee",           label=L["AURASDATA_FILLTEX_SMOKE"],             scrollDef=0.2 },
    { id="FillStripesFin",      label=L["AURASDATA_FILLTEX_THIN_STRIPES"],     scrollDef=0   },
    { id="FillStripesEpais",    label=L["AURASDATA_FILLTEX_THICK_STRIPES"],  scrollDef=0   },
    { id="FillRayuresObliques", label=L["AURASDATA_FILLTEX_GOLD_CHEVRONS"],       scrollDef=0   },
    { id="FillBande",           label=L["AURASDATA_FILLTEX_LUMINOUS_BAND"],   scrollDef=0   },
}

-- Helper : retourne le path complet pour une texture id
function ns.GetFillTexturePath(id)
    if not id or id == "" then return "" end
    return TEX_BASE .. id
end

-- Helper : retourne le label d'une texture id (pour affichage UI)
function ns.GetFillTextureLabel(id)
    if not id or id == "" then return L["AURASDATA_FILLTEX_NONE"] end
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

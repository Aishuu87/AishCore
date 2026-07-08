-- AishUIAura/UI/Menus/Render.lua
-- Per-render menu (Debuffs / Cooldowns / Procs / Buffs): layout cards + accordion sections
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.SettingsPanel = ns.SettingsPanel or {}

local TC = 0.07

------------------------------------------------------------------------
-- Configuration par render : sections optionnelles affichables.
--
-- BuildRenderMenu cree TOUJOURS les sections de base (DIMENSIONS, POSITION,
-- PRESETS BARRES, ETINCELLE, BARRE, OPACITE & FADE, COULEURS D'URGENCE).
-- Seules les sections OPTIONNELLES listees ici sont conditionnees par render.
--
-- Pour un render qui doit avoir tout : `= DEFAULT_OPTIONAL_SECTIONS`
-- Pour un render minimaliste (ex: Buffs) : `= {}`
------------------------------------------------------------------------
local DEFAULT_OPTIONAL_SECTIONS = {
    glow      = true,   -- override glow pour tous les sorts du render
    timerIcon = true,   -- timer texte centre sur l'icone
    stacks    = true,   -- compteur de stacks sur l'icone
    charges   = true,   -- compteur de charges sur l'icone
}

local OPTIONAL_SECTIONS_BY_RENDER = {
    iconlist   = DEFAULT_OPTIONAL_SECTIONS,
    circlebars = DEFAULT_OPTIONAL_SECTIONS,
    icons      = DEFAULT_OPTIONAL_SECTIONS,
    freebars   = { timerIcon = true },  -- freebars : pas d'icone/glow/stacks/charges, mais texte de duree dispo
}

------------------------------------------------------------------------
-- Configuration par render : sous-features optionnelles dans les sections.
-- iconSize        : sliders Largeur/Hauteur icone (section DIMENSIONS)
-- desatSwipe      : dropdown Desaturation + checkbox Swipe cooldown (section DIMENSIONS)
-- growthDirection : dropdown "Direction empilement" + slider "Max barres" (section POSITION)
--
-- Pour un render qui doit avoir tout : `= DEFAULT_OPTIONAL_FEATURES`
-- Pour un render minimaliste (ex: Buffs avec placement auto) : `= {}`
------------------------------------------------------------------------
local DEFAULT_OPTIONAL_FEATURES = {
    iconSize        = true,
    desatSwipe      = true,
    growthDirection = true,
}

local OPTIONAL_FEATURES_BY_RENDER = {
    iconlist   = DEFAULT_OPTIONAL_FEATURES,
    circlebars = DEFAULT_OPTIONAL_FEATURES,
    icons      = DEFAULT_OPTIONAL_FEATURES,
    freebars   = {},   -- freebars : pas d'icone, placement auto, aucune feature optionnelle
}

local function HasSection(rk, name)
    local t = OPTIONAL_SECTIONS_BY_RENDER[rk] or DEFAULT_OPTIONAL_SECTIONS
    return t[name] == true
end

local function HasFeature(rk, name)
    local t = OPTIONAL_FEATURES_BY_RENDER[rk] or DEFAULT_OPTIONAL_FEATURES
    return t[name] == true
end

function ns.SettingsPanel.BuildRenderMenu(p, cw, rk)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font

    local y=0
    local dispLabels={iconlist="(sous le cercle)",circlebars="(barre laterale)",icons="(sous le portrait joueur)",freebars="(autour du cercle de ressource)"}
    local dH=SW.CreateSectionHeader(p,"Disposition "..( dispLabels[rk] or ""),cw-20); dH:SetPoint("TOPLEFT",10,-y); y=y+22
    local lays=({iconlist={"center_mirror","center_dual"},circlebars={"side_large","side_compact","side_banner"},icons={"portrait_small"},freebars={"resource_circle"}})[rk] or {}
    local cardW,gap=140,15; local sx=math.max(10,(cw-#lays*(cardW+gap)+gap)/2)
    local cfg=ns.db and ns.db[rk]; local al=cfg and cfg.layout
    local layoutCards = {}
    local function RefreshLayoutCards()
        local cur = ns.db and ns.db[rk] and ns.db[rk].layout
        for _, lc in ipairs(layoutCards) do
            local isAct = (lc.key == cur)
            if isAct then
                lc.lbl:SetTextColor(unpack(Theme.textNormal))
                -- Swap TGA en version active (or)
                local tex = ns.LAYOUT_ICONS and ns.LAYOUT_ICONS[lc.key:upper()]
                if tex then pcall(function() lc.ico:SetTexture(tex) end) end
                lc.ico:SetVertexColor(1,1,1,1)
                if lc.actTx then lc.actTx:Show() end
            else
                lc.lbl:SetTextColor(unpack(Theme.textDisabled))
                -- Swap TGA en version inactive (gris)
                local tex = ns.LAYOUT_ICONS_INACTIVE and ns.LAYOUT_ICONS_INACTIVE[lc.key:upper()]
                if tex then pcall(function() lc.ico:SetTexture(tex) end) end
                lc.ico:SetVertexColor(1,1,1,1)
                if lc.actTx then lc.actTx:Hide() end
            end
        end
    end
    for i,lk in ipairs(lays) do local fb=ns.LAYOUT_ICON_FALLBACKS[lk:upper()] or "inv_misc_questionmark"
        local isAct = (al == lk)
        -- Card sans encadré par défaut : juste un Button transparent pour capturer les clics.
        -- Le halo doré apparaît uniquement au survol (hover feedback).
        local card=CreateFrame("Button",nil,p,"BackdropTemplate"); card:SetSize(cardW,110)
        card:SetPoint("TOPLEFT",sx+(i-1)*(cardW+gap),-(y+10))

        -- Halo doré de survol (caché par défaut). C'est ce qui fait le "encadré"
        -- quand on passe la souris dessus.
        local hoverGlow = card:CreateTexture(nil,"BACKGROUND",nil,0)
        hoverGlow:SetAllPoints()
        hoverGlow:SetColorTexture(Theme.gold and Theme.gold[1] or 0.78,
                                   Theme.gold and Theme.gold[2] or 0.62,
                                   Theme.gold and Theme.gold[3] or 0.30, 0.08)
        hoverGlow:Hide()

        -- Bordure invisible par défaut, devient or au survol
        local cbd = CreateFrame("Frame",nil,card,"BackdropTemplate"); cbd:SetAllPoints()
        cbd:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
        cbd:SetBackdropBorderColor(0,0,0,0)  -- invisible par défaut

        -- Icône : TGA custom du layout (proportions réelles du jeu).
        -- Taille 120×75 (ratio 128:80 préservé) pour remplir au max la card 140×110.
        -- Pas de TexCoord (on affiche l'image entière, elle contient déjà ses marges).
        local ico=card:CreateTexture(nil,"ARTWORK"); ico:SetSize(120, 75); ico:SetPoint("TOP",0,-2)
        -- Utilise la version inactive (gris) ou active (or) selon l'état
        local function _SetLayoutIcon(active)
            local tex = active
                and (ns.LAYOUT_ICONS and ns.LAYOUT_ICONS[lk:upper()])
                or  (ns.LAYOUT_ICONS_INACTIVE and ns.LAYOUT_ICONS_INACTIVE[lk:upper()])
            if tex then
                pcall(function() ico:SetTexture(tex) end)
            else
                -- Fallback Blizzard si TGA manquant
                pcall(function() ico:SetTexture("Interface\\Icons\\"..fb) end)
            end
        end
        _SetLayoutIcon(isAct)
        ico:SetVertexColor(1, 1, 1, 1)  -- pas de teinte, le TGA contient déjà sa couleur

        -- Label sous l'icône
        local clbl=card:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(clbl,FONT,12); clbl:SetPoint("BOTTOM",0,20)
        clbl:SetTextColor(unpack(isAct and Theme.textNormal or Theme.textDisabled)); clbl:SetText(ns.LAYOUT_NAMES[lk:upper()] or lk)

        -- Label "ACTIF" sous le label nom, centré (pas dans le coin)
        local actTx=nil
        if isAct then actTx=card:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(actTx,FONT,8); actTx:SetPoint("BOTTOM",0,5)
            actTx:SetTextColor(unpack(Theme.accent)); actTx:SetText("ACTIF") end

        layoutCards[#layoutCards+1] = {key=lk, card=card, ico=ico, lbl=clbl, actTx=actTx}

        card:SetScript("OnClick",function()
            if ns.db and ns.db[rk] then ns.db[rk].layout=lk end
            -- Create actTx for newly active card if missing (centré en bas)
            for _, lc in ipairs(layoutCards) do
                if not lc.actTx then
                    lc.actTx=lc.card:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lc.actTx,FONT,8)
                    lc.actTx:SetPoint("BOTTOM",0,5); lc.actTx:SetTextColor(unpack(Theme.accent)); lc.actTx:SetText("ACTIF")
                end
            end
            RefreshLayoutCards(); pcall(ns.RebuildDisplay)
        end)
        card:SetScript("OnEnter",function()
            hoverGlow:Show()
            -- Bordure or au survol
            local g = Theme.gold or {0.78,0.62,0.30}
            cbd:SetBackdropBorderColor(g[1],g[2],g[3],0.8)
            clbl:SetTextColor(1,1,1)
            -- Swap TGA en version active au survol (preview)
            _SetLayoutIcon(true)
            ico:SetVertexColor(1,1,1,1)
        end)
        card:SetScript("OnLeave",function()
            hoverGlow:Hide()
            cbd:SetBackdropBorderColor(0,0,0,0)
            RefreshLayoutCards()
        end)
    end; y=y+130
    local sections = {}
    -- GLOW : override le glow de tous les sorts dans ce render
    if HasSection(rk, "glow") then
        sections[#sections+1] = {name="GLOW",category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local info=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(info,FONT,9)
            info:SetPoint("TOPLEFT",15,-cy); info:SetTextColor(unpack(Theme.textDim))
            info:SetText("Override le glow de tous les sorts dans ce rendu"); cy=cy+18
            local pf=CreateFrame("Frame",nil,c); pf:SetSize(48,48); pf:SetPoint("TOP",0,-cy); pf:SetFrameStrata("DIALOG"); pf:SetFrameLevel(c:GetFrameLevel()+10)
            local pfIco=pf:CreateTexture(nil,"ARTWORK"); pfIco:SetAllPoints(); pfIco:SetTexCoord(TC,1-TC,TC,1-TC)
            pcall(function() pfIco:SetTexture(134154) end)
            cy=cy+55
            local function RefreshRenderGlowPreview()
                pcall(function()
                    if ns.HideGlow then ns.HideGlow(pf) end
                    local idx = cf.glowOverrideIdx or 0
                    if idx > 1 then
                        local gc = {cf.glowOverrideR or ns.barColor[1], cf.glowOverrideG or ns.barColor[2], cf.glowOverrideB or ns.barColor[3]}
                        if ns.ShowGlow then ns.ShowGlow(pf, idx, gc, cf.glowOverrideAlpha or 0.7, cf.glowOverrideScale or 1.0) end
                    end
                end)
            end
            local glOpts={{value=0,text="Par sort (defaut)"}}
            for idx,def in ipairs(ns.GLOW_DEFS) do if not def.isProcStart then glOpts[#glOpts+1]={value=idx,text=def.name} end end
            local gdd=SW.CreateDropdown(c,"Type de glow",glOpts,w-30); gdd:SetPoint("TOPLEFT",15,-cy)
            gdd:SetValue(cf.glowOverrideIdx or 0)
            gdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideIdx=(v>0 and v or nil); cf.glowOverrideIdx=(v>0 and v or nil) end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras) end
            cy=cy+50
            local gcc=SW.CreateColorButton(c,"Couleur glow",slW); gcc:SetPoint("TOPLEFT",ox,-cy)
            local gc=ns.barColor
            gcc:SetColor(cf.glowOverrideR or gc[1], cf.glowOverrideG or gc[2], cf.glowOverrideB or gc[3])
            gcc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideR=col[1]; ns.db[rk].glowOverrideG=col[2]; ns.db[rk].glowOverrideB=col[3]; cf.glowOverrideR=col[1]; cf.glowOverrideG=col[2]; cf.glowOverrideB=col[3] end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras) end
            local goa=SW.CreateSlider(c,"Opacite",0,1,0.05,slW); goa:SetPoint("TOPLEFT",ox+slW+gap,-cy); goa:SetValue(cf.glowOverrideAlpha or 0.7)
            goa.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideAlpha=v end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras) end
            cy=cy+60
            local gsc=SW.CreateSlider(c,"Taille",0.3,3.0,0.1,slW); gsc:SetPoint("TOPLEFT",ox,-cy); gsc:SetValue(cf.glowOverrideScale or 1.0)
            gsc.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideScale=v end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras) end
            cy=cy+60
            C_Timer.After(0.1, RefreshRenderGlowPreview)
            c:SetHeight(cy) end}
    end
    -- DIMENSIONS : taille des barres et icones, espacements
    -- Le titre s'adapte selon que le render a des icones ou non.
    local dimSectionName = HasFeature(rk, "iconSize") and "ICONES & DIMENSIONS" or "DIMENSIONS"
    sections[#sections+1] = {name=dimSectionName,category="STRUCTURE",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            if HasFeature(rk, "iconSize") then
                local s1=SW.CreateSlider(c,"Largeur icone",10,80,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.iconW or 25)
                s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconW=v end; pcall(ns.RebuildDisplay) end
                local s2=SW.CreateSlider(c,"Hauteur icone",10,80,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.iconH or 25)
                s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconH=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            end
            -- Bar dimensions (Debuffs/Cooldowns: barW/barH, Procs: showBar + barUnderHeight)
            if rk == "icons" then
                local cbBar=SW.CreateCheckbox(c,"Afficher barre",slW); cbBar:SetPoint("TOPLEFT",ox,-cy); cbBar:SetChecked(cf.showBarUnderIcon ~= false)
                cbBar.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].showBarUnderIcon=v end; pcall(ns.RebuildDisplay) end
                local sbh=SW.CreateSlider(c,"Hauteur barre",1,15,1,slW); sbh:SetPoint("TOPLEFT",ox+slW+gap,-cy); sbh:SetValue(cf.barUnderHeight or 3)
                sbh.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barUnderHeight=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
                local bpOpts={{value="BOTTOM",text="Sous l'icone"},{value="TOP",text="Au-dessus"}}
                local bpdd=SW.CreateDropdown(c,"Position barre",bpOpts,slW); bpdd:SetPoint("TOPLEFT",ox,-cy)
                bpdd:SetValue(cf.barPosition or "BOTTOM")
                bpdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barPosition=v end; pcall(ns.RebuildDisplay) end
                local cbRev=SW.CreateCheckbox(c,"Inverser remplissage",slW); cbRev:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbRev:SetChecked(cf.barReverseFill == true)
                cbRev.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barReverseFill=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            else
                local s3=SW.CreateSlider(c,"Largeur barre",10,300,1,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.barW or 80)
                s3.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barW=v end; pcall(ns.RebuildDisplay) end
                local s4=SW.CreateSlider(c,"Hauteur barre",1,30,1,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.barH or 4)
                s4.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barH=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            end
            local sg=SW.CreateSlider(c,"Espacement",0,150,1,slW); sg:SetPoint("TOPLEFT",ox,-cy); sg:SetValue(cf.gap or 4)
            sg.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].gap=v end; pcall(ns.RebuildDisplay) end
            local srg=SW.CreateSlider(c,"Espacement lignes",0,20,1,slW); srg:SetPoint("TOPLEFT",ox+slW+gap,-cy); srg:SetValue(cf.rowGap or 2)
            srg.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].rowGap=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            if HasFeature(rk, "desatSwipe") then
                local dsOpts={{value="nil",text="Par sort"},{value="true",text="Toujours gris"},{value="false",text="Jamais gris"}}
                local dsdd=SW.CreateDropdown(c,"Desaturation",dsOpts,slW); dsdd:SetPoint("TOPLEFT",ox,-cy)
                local dsVal = cf.desatOverride == nil and "nil" or tostring(cf.desatOverride)
                dsdd:SetValue(dsVal)
                dsdd.onChanged=function(v)
                    if ns.db and ns.db[rk] then
                        if v == "nil" then ns.db[rk].desatOverride = nil
                        elseif v == "true" then ns.db[rk].desatOverride = true
                        else ns.db[rk].desatOverride = false end
                    end; pcall(ns.ScanAuras)
                end
                local cbs=SW.CreateCheckbox(c,"Swipe cooldown",slW); cbs:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbs:SetChecked(cf.swipeEnabled == true)
                cbs.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].swipeEnabled=v end; pcall(ns.ScanAuras) end
                cy=cy+50
            end
            c:SetHeight(cy) end}
    sections[#sections+1] = {name="POSITION",category="STRUCTURE",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local s1=SW.CreateSlider(c,"Position X",-1000,1000,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.x or 0)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].x=v end; pcall(ns.RebuildDisplay) end
            local s2=SW.CreateSlider(c,"Position Y",-1000,1000,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.y or 0)
            s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].y=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            if HasFeature(rk, "growthDirection") then
                local growOpts={{value="DOWN",text="Haut vers bas"},{value="UP",text="Bas vers haut"},{value="LEFT",text="Droite vers gauche"},{value="RIGHT",text="Gauche vers droite"}}
                local gdd=SW.CreateDropdown(c,"Direction empilement",growOpts,slW); gdd:SetPoint("TOPLEFT",ox,-cy)
                gdd:SetValue(cf.growth or "DOWN")
                gdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].growth=v end; pcall(ns.RebuildDisplay) end
                local sm=SW.CreateSlider(c,"Max barres",1,12,1,slW); sm:SetPoint("TOPLEFT",ox+slW+gap,-cy); sm:SetValue(cf.maxBars or 8)
                sm.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].maxBars=v end; pcall(ns.RebuildDisplay) end
                cy=cy+55
            end
            c:SetHeight(cy) end}

    -- PRESETS BARRES : applique en un clic les DIMENSIONS (bar + spark) du preset.
    -- 25 presets distincts couvrant toutes les classes (Druid/Rogue/Shaman/Mage/etc.).
    -- La liste est peuplée depuis Data/AishUITemplates.lua.
    --
    -- IMPORTANT : les presets ne touchent JAMAIS aux couleurs. Les couleurs dans AishUIAura
    -- sont gérées à deux niveaux (couleur globale du render + couleur par sort), et elles
    -- restent propres à ta config. Les presets s'occupent uniquement du "moule visuel"
    -- (dimensions, spark type, spark taille).
    if rk ~= "icons" and ns.AishUITemplates then
    sections[#sections+1] = {name="PRESETS BARRES",category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            -- État local de la sélection (preset courant uniquement, plus de filtre classe)
            local state = ns._aishPresetState or {}
            ns._aishPresetState = state
            state[rk] = state[rk] or { preset = nil }
            local s = state[rk]

            -- Dropdown PRESET : liste complète des 25 presets avec noms thématiques
            -- Occupe toute la largeur dispo puisqu'il n'y a plus de filtre classe
            local pdd = SW.CreateDropdown(c, "Preset", {{value="", text="-- Choisir un style --"}}, w - 30); pdd:SetPoint("TOPLEFT", 15, -cy)

            local opts = {{ value = "", text = "-- Choisir un style --" }}
            for i, p in ipairs(ns.AishUITemplates) do
                -- Format simple : juste le nom du preset (ex: "Filet doré").
                -- Les détails dimensionnels et la mention "+3D" sont visibles
                -- dans la zone d'aperçu en dessous, pas la peine de surcharger
                -- la liste déroulante.
                table.insert(opts, { value = tostring(i), text = p.name or "?" })
            end
            pdd:SetOptions(opts)
            pdd:SetValue(s.preset or "")

            pdd.onChanged = function(v) s.preset = v; if s.updatePreview then s.updatePreview() end end

            cy = cy + 60

            -- ZONE DE PREVIEW : montre visuellement le preset sélectionné
            -- Une mini-barre rendue avec les vraies dimensions + son spark + le texte descriptif.
            -- Permet de voir à quoi ressemble le preset AVANT de cliquer "Appliquer".
            local previewLbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            previewLbl:SetPoint("TOPLEFT", 15, -cy)
            previewLbl:SetText("|cff888888Apercu du preset :|r")
            cy = cy + 18

            -- Container centré pour la preview (fond sombre pour faire ressortir la bar)
            local pvBg = CreateFrame("Frame", nil, c, "BackdropTemplate")
            pvBg:SetSize(w - 30, 50)
            pvBg:SetPoint("TOPLEFT", 15, -cy)
            pvBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            pvBg:SetBackdropColor(0.04, 0.04, 0.06, 0.85)

            -- La barre de preview (StatusBar) — couleur GRIS neutre pour
            -- ne pas concurrencer les couleurs custom que l'utilisateur
            -- choisira ailleurs. Le preset montre la FORME (dimensions, spark),
            -- pas la couleur.
            local _previewGray = { 0.55, 0.55, 0.55 }
            local pvBar = CreateFrame("StatusBar", nil, pvBg)
            pvBar:SetStatusBarTexture(ns.ResolveBarTexFromKey and ns.ResolveBarTexFromKey(cf.texture) or "Interface\\TargetingFrame\\UI-StatusBar")
            pvBar:SetMinMaxValues(0, 1); pvBar:SetValue(0.65)  -- 65% rempli pour montrer le spark au bon endroit
            pvBar:SetStatusBarColor(_previewGray[1], _previewGray[2], _previewGray[3])

            -- Le spark (Texture, positionné sur le fill de la bar)
            local pvSpark = pvBar:CreateTexture(nil, "OVERLAY", nil, 6)
            pvSpark:SetBlendMode("ADD")

            -- Pas de bloc descriptif sous la preview : le nom du preset est
            -- déjà visible dans le dropdown. La preview parle d'elle-même.

            -- Fonction qui redessine la preview selon le preset actuellement sélectionné
            s.updatePreview = function()
                local idx = tonumber(s.preset or "")
                local p = ns.AishUITemplates and idx and ns.AishUITemplates[idx]

                if not p then
                    pvBar:Hide()
                    pvSpark:Hide()
                    return
                end

                -- Dimensionne la bar de preview : respecte le ratio, clamp à la taille dispo
                local maxW = math.min(p.w, w - 60)
                local scale = (p.w > 0) and (maxW / p.w) or 1
                local displayW = maxW
                local displayH = math.max(2, p.h * scale)  -- min 2px pour être visible
                pvBar:SetSize(displayW, displayH)
                pvBar:ClearAllPoints()
                pvBar:SetPoint("CENTER", pvBg, "CENTER", 0, 0)
                pvBar:Show()

                -- Applique la bonne texture de spark (depuis le mapping AishUISparkTextures)
                local sparkTex = ns.AishUISparkTextures and ns.AishUISparkTextures[p.spark_type]
                if sparkTex and p.spark_w > 0 and p.spark_h > 0 then
                    if sparkTex:find("^atlas:") then
                        pcall(function() pvSpark:SetAtlas(sparkTex:sub(7)) end)
                    else
                        pvSpark:SetTexture(sparkTex)
                    end
                    -- Dimensionne le spark aussi avec le même scale
                    pvSpark:SetSize(math.max(2, p.spark_w * scale), math.max(2, p.spark_h * scale))
                    pvSpark:ClearAllPoints()
                    -- Positionne au bout du fill (65% → offset depuis la gauche)
                    local fillOff = displayW * 0.65 - displayW / 2
                    pvSpark:SetPoint("CENTER", pvBar, "CENTER", fillOff, 0)
                    -- Spark teinté en GRIS pour rester cohérent avec la barre.
                    pvSpark:SetVertexColor(_previewGray[1], _previewGray[2], _previewGray[3], 1)
                    pvSpark:Show()
                else
                    pvSpark:Hide()
                end
            end
            s.updatePreview()
            cy = cy + 55 + 10  -- preview bg + petite marge (pvDesc retiré)

            -- Bouton APPLIQUER LE PRESET — style maison (SW.CreateActionBtn)
            -- pour rester cohérent avec les autres boutons de l'addon.
            local btn = SW.CreateActionBtn(c, "Appliquer le preset", 200)
            btn:SetPoint("TOP", c, "TOP", 0, -cy)
            btn:SetScript("OnClick", function()
                local idx = tonumber(s.preset or "")
                if not idx then return end
                local p = ns.AishUITemplates and ns.AishUITemplates[idx]
                if p and ns.ApplyAishUITemplate then
                    ns.ApplyAishUITemplate(rk, p)
                    local g = (ns.THEME and ns.THEME.gold) or { 0.78, 0.62, 0.30 }
                    print("|cff" .. string.format("%02x%02x%02x", math.floor(g[1]*255), math.floor(g[2]*255), math.floor(g[3]*255)) ..
                          "[AishUI]|r Preset appliqué : " .. (p.name or "?"))
                    if ns._rebuildCurrentMenu then C_Timer.After(0.1, ns._rebuildCurrentMenu) end
                end
            end)
            cy = cy + 36

            c:SetHeight(cy) end}
    end

    -- SPARK: skip for Procs (no spark in Fury layout)
    if rk ~= "icons" then
    sections[#sections+1] = {name="ETINCELLE (SPARK)",category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cb=SW.CreateCheckbox(c,"Activer spark",w-30); cb:SetPoint("TOPLEFT",15,-cy); cb:SetChecked(cf.sparkEnabled~=false)
            cb.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkEnabled=v end; pcall(ns.RebuildDisplay) end; cy=cy+30
            local s1=SW.CreateSlider(c,"Largeur",1,40,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.sparkW or 17)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkW=v end; pcall(ns.RebuildDisplay) end
            local s2=SW.CreateSlider(c,"Hauteur",1,20,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.sparkH or 6)
            s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkH=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            local s3=SW.CreateSlider(c,"Opacite",0,1,0.05,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.sparkAlpha or 0.9)
            s3.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkAlpha=v end; pcall(ns.RebuildDisplay) end
            local s4=SW.CreateSlider(c,"Offset Y",-20,20,1,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.sparkOffY or 0)
            s4.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkOffY=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            local cc=SW.CreateColorButton(c,"Couleur spark",w-30); cc:SetPoint("TOPLEFT",15,-cy)
            cc:SetColor(cf.sparkColorR or ns.sparkColor[1], cf.sparkColorG or ns.sparkColor[2], cf.sparkColorB or ns.sparkColor[3])
            cc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].sparkColorR=col[1]; ns.db[rk].sparkColorG=col[2]; ns.db[rk].sparkColorB=col[3] end; pcall(ns.RebuildDisplay) end; cy=cy+30
            local cbSG=SW.CreateCheckbox(c,"Degrade spark",slW); cbSG:SetPoint("TOPLEFT",ox,-cy); cbSG:SetChecked(cf.sparkGradient or false)
            cbSG.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkGradient=v end; pcall(ns.RebuildDisplay) end; cy=cy+25
            local sc2=ns.sparkColor
            local cc2=SW.CreateColorButton(c,"Couleur fin degrade spark",slW*2+gap); cc2:SetPoint("TOPLEFT",ox,-cy)
            cc2:SetColor(cf.sparkGradR2 or sc2[1]*0.2, cf.sparkGradG2 or sc2[2]*0.2, cf.sparkGradB2 or sc2[3]*0.2)
            cc2.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].sparkGradR2=col[1]; ns.db[rk].sparkGradG2=col[2]; ns.db[rk].sparkGradB2=col[3] end; pcall(ns.RebuildDisplay) end; cy=cy+30
            local sparkTexOpts={
                {value="",text="CastingBar (defaut)"},
                {value="Interface\\CastingBar\\UI-CastingBar-Spark",text="CastingBar Spark"},
                {value="atlas:UI-CastingBar-Spark-Small",text="Spark Petit"},
                {value="atlas:honorsystem-bar-spark",text="Honor Spark (dore)"},
                {value="Interface\\Buttons\\WHITE8x8",text="Carre"},
                {value="Interface\\AddOns\\Aishaddon\\Media\\Statusbars\\aish_gradient",text="Gradient"},
            }
            local stdd=SW.CreateDropdown(c,"Texture spark",sparkTexOpts,w-30); stdd:SetPoint("TOPLEFT",15,-cy)
            stdd:SetValue(cf.sparkTexture or "")
            stdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkTexture=(v~="" and v or nil) end; pcall(ns.RebuildDisplay) end
            cy=cy+50
            -- Position du spark : devant ou derrière le statusbar
            local sparkLayerOpts={
                {value="front", text="Devant la barre"},
                {value="back",  text="Derriere la barre"},
            }
            local sld=SW.CreateDropdown(c,"Position du spark",sparkLayerOpts,w-30); sld:SetPoint("TOPLEFT",15,-cy)
            sld:SetValue(cf.sparkLayer or "front")
            sld.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkLayer=v end; pcall(ns.RebuildDisplay) end
            cy=cy+50; c:SetHeight(cy) end}
    end
    sections[#sections+1] = {name="BARRE (COULEUR & TEXTURE)",category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local bc=ns.barColor
            local cc1=SW.CreateColorButton(c,"Couleur barre",slW); cc1:SetPoint("TOPLEFT",ox,-cy)
            cc1:SetColor(cf.barColorR or bc[1], cf.barColorG or bc[2], cf.barColorB or bc[3])
            cc1.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].barColorR=col[1]; ns.db[rk].barColorG=col[2]; ns.db[rk].barColorB=col[3] end; pcall(ns.ScanAuras) end
            local cbG=SW.CreateCheckbox(c,"Degrade horizontal",slW); cbG:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbG:SetChecked(cf.gradientEnabled or false)
            cbG.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].gradientEnabled=v end; pcall(ns.ScanAuras) end; cy=cy+30
            local cc2=SW.CreateColorButton(c,"Couleur fin degrade",slW); cc2:SetPoint("TOPLEFT",ox,-cy)
            cc2:SetColor(cf.gradientR2 or bc[1]*0.3, cf.gradientG2 or bc[2]*0.3, cf.gradientB2 or bc[3]*0.3)
            cc2.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].gradientR2=col[1]; ns.db[rk].gradientG2=col[2]; ns.db[rk].gradientB2=col[3] end; pcall(ns.ScanAuras) end; cy=cy+30
            -- Fond de barre
            local ccBg=SW.CreateColorButton(c,"Couleur fond barre",slW); ccBg:SetPoint("TOPLEFT",ox,-cy)
            ccBg:SetColor(cf.barBgR or 0.055, cf.barBgG or 0.055, cf.barBgB or 0.055)
            ccBg.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].barBgR=col[1]; ns.db[rk].barBgG=col[2]; ns.db[rk].barBgB=col[3] end; pcall(ns.RebuildDisplay) end
            local sBgA=SW.CreateSlider(c,"Opacite fond (0=transparent)",0,1,0.05,slW); sBgA:SetPoint("TOPLEFT",ox+slW+gap,-cy); sBgA:SetValue(cf.barBgAlpha or 0)
            sBgA.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barBgAlpha=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            local texOpts={}; for _,t in ipairs(ns.BAR_TEXTURES) do texOpts[#texOpts+1]={value=t.value,text=t.text} end
            local tdd=SW.CreateDropdown(c,"Texture barre",texOpts,w-30); tdd:SetPoint("TOPLEFT",15,-cy)
            tdd:SetValue(cf.texture or ns.BAR_TEXTURES[1].value)
            tdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].texture=v end; pcall(ns.RebuildDisplay) end
            cy=cy+50; c:SetHeight(cy) end}

    -- ANIMATION D'APPARITION : disponible pour les renders qui ont des barres
    -- (Buffs, Debuffs, Cooldowns). Pas pour Procs (icones petites, animation
    -- non pertinente).
    if rk == "freebars" or rk == "iconlist" or rk == "circlebars" then
        sections[#sections+1] = {name="ANIMATION D'APPARITION",category="ANIMATION",build=function(c,w)
            local cy=0; local cf=ns.db and ns.db[rk] or {}
            local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)

            -- Ligne 1 : checkboxes Activee + Fade alpha
            local cbOn = SW.CreateCheckbox(c,"Animation activee",slW)
            cbOn:SetPoint("TOPLEFT",ox,-cy); cbOn:SetChecked(cf.popEnabled ~= false)
            cbOn.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popEnabled = v end end

            local cbAlpha = SW.CreateCheckbox(c,"Fade alpha",slW)
            cbAlpha:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbAlpha:SetChecked(cf.popAlphaFade ~= false)
            cbAlpha.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popAlphaFade = v end end
            cy = cy + 30

            -- Ligne 2 : sliders Duree + Intensite
            local sDur = SW.CreateSlider(c,"Duree (s)",0.1,2.5,0.05,slW)
            sDur:SetPoint("TOPLEFT",ox,-cy); sDur:SetValue(cf.popDuration or 1.0)
            sDur.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popDuration = v end end

            local sStr = SW.CreateSlider(c,"Intensite easing",1,12,1,slW)
            sStr:SetPoint("TOPLEFT",ox+slW+gap,-cy); sStr:SetValue(cf.popEaseStrength or 5)
            sStr.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popEaseStrength = math.floor(v + 0.5) end end
            cy = cy + 50

            c:SetHeight(cy)
        end}
    end

    -- ANIMATION ICONE
    sections[#sections+1] = {name="ANIMATION ICONE",category="ANIMATION",build=function(c,w)
        local cy=0; local cf=ns.db and ns.db[rk] or {}
        local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
        local SW = ns.SharedWidgets or {}
        local styleOpts = {
            {value="standard", text="Standard (fade+glisse)"},
            {value="surge",    text="Surge (scale+montee)"},
            {value="slide",    text="Slide (depuis droite)"},
            {value="pop",      text="Pop (echelle+fade)"},
            {value="none",     text="Aucune"},
        }
        local dd = SW.CreateDropdown and SW.CreateDropdown(c,"Style",styleOpts,w-30) or nil
        if dd then
            dd:SetPoint("TOPLEFT",15,-cy); dd:SetValue(cf.iconAnimStyle or "standard")
            dd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAnimStyle=v end end
            cy=cy+50
        end
        local sDur = SW.CreateSlider and SW.CreateSlider(c,"Duree (s)",0.1,1.5,0.05,slW) or nil
        if sDur then
            sDur:SetPoint("TOPLEFT",ox,-cy); sDur:SetValue(cf.iconAnimDuration or 0.4)
            sDur.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAnimDuration=v end end
        end
        local cbOut = SW.CreateCheckbox and SW.CreateCheckbox(c,"Animer sortie",slW) or nil
        if cbOut then
            cbOut:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbOut:SetChecked(cf.iconAnimOut ~= false)
            cbOut.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAnimOut=v end end
        end
        cy=cy+50; c:SetHeight(cy)
    end}

    -- COULEUR PAR SORT : section specifique au render Buffs.
    -- Liste tous les sorts coches [B] dans Sorts a tracker, avec pour chacun
    -- une checkbox "Degrade", 2 color buttons (debut + fin) et un bouton Reset.
    -- Si une entree est definie pour un sort, sa couleur/gradient override TOUT (cf.
    -- ApplyBarColor priorite 1). Sinon comportement standard.
    if rk == "freebars" then
        sections[#sections+1] = {name="COULEUR PAR SORT",category="APPARENCE",build=function(c,w)
            local cy = 4
            local cf = ns.db and ns.db[rk] or {}
            cf.spellGradients = cf.spellGradients or {}

            -- Collecte les sorts coches [B] (info.destinations.buffs == true).
            -- On utilise juste l'ID comme identifiant (suffisant avec l'icone visuelle).
            -- Fallback API uniquement pour l'icone si manquante.
            local spells = ns.GetSpecSpells and ns.GetSpecSpells() or {}
            local list = {}
            for sid, info in pairs(spells) do
                if info and info.enabled and info.destinations and info.destinations.buffs then
                    local sicon = info.icon
                    if not sicon and C_Spell and C_Spell.GetSpellInfo then
                        local ok, spellInfo = pcall(C_Spell.GetSpellInfo, sid)
                        if ok and spellInfo and spellInfo.iconID then sicon = spellInfo.iconID end
                    end
                    list[#list+1] = { sid = sid, icon = sicon }
                end
            end
            table.sort(list, function(a, b) return a.sid < b.sid end)

            if #list == 0 then
                local fs1 = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs1:SetPoint("TOP", c, "TOP", 0, -cy - 10)
                fs1:SetText("Aucun sort a personnaliser pour l'instant")
                fs1:SetTextColor(1, 0.85, 0.3)
                cy = cy + 40
                c:SetHeight(cy); return
            end

            -- Header (sans point final)
            local fsHdr = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fsHdr:SetPoint("TOP", c, "TOP", 0, -cy)
            fsHdr:SetText("Personnalisez la couleur ou le degrade par sort")
            cy = cy + 24

            -- ============== Layout en colonnes alignees ==============
            -- Gauche : [icone] [ID]
            -- Centre : [carre couleur] [carre couleur fin]
            -- Droite : [Degrade] [×]
            local ROW_H = 30
            local ICON_SIZE = 22
            local SWATCH = 22
            local SWATCH_GAP = 6     -- espace entre les 2 carres
            local CB_W = 90          -- checkbox "Degrade"
            local CLOSE_SIZE = 18    -- petite croix Reset
            local LEFT_MARGIN = 15
            local RIGHT_MARGIN = 15
            local SPACE = 12

            -- Colonnes fixes pour alignement vertical propre
            local COL_ICON = LEFT_MARGIN
            local COL_ID = COL_ICON + ICON_SIZE + 8
            local COL_SWATCHES = w - RIGHT_MARGIN - CLOSE_SIZE - SPACE - CB_W - SPACE - SWATCH - SWATCH_GAP - SWATCH
            local COL_DEGRADE = w - RIGHT_MARGIN - CLOSE_SIZE - SPACE - CB_W
            local COL_CLOSE = w - RIGHT_MARGIN - CLOSE_SIZE

            -- Helper local : creer un carre de couleur cliquable
            local function CreateSwatch(parent)
                local sw = CreateFrame("Button", nil, parent)
                sw:SetSize(SWATCH, SWATCH)
                local bd = sw:CreateTexture(nil, "BORDER")
                bd:SetPoint("TOPLEFT", -1, 1); bd:SetPoint("BOTTOMRIGHT", 1, -1)
                bd:SetColorTexture(0.4, 0.32, 0.18, 1)  -- bordure or sombre
                local fg = sw:CreateTexture(nil, "ARTWORK")
                fg:SetAllPoints()
                fg:SetColorTexture(1, 1, 1)
                sw._fg = fg
                sw._bd = bd
                sw.currentColor = {1, 1, 1}
                function sw:SetColor(r, g, b)
                    self.currentColor = {r or 1, g or 1, b or 1}
                    fg:SetColorTexture(r or 1, g or 1, b or 1)
                end
                function sw:SetDimmed(dim)
                    -- Mode visuel "desactive" : alpha reduit + bordure plus sombre
                    if dim then
                        self:SetAlpha(0.35)
                        self:EnableMouse(false)
                    else
                        self:SetAlpha(1.0)
                        self:EnableMouse(true)
                    end
                end
                sw:SetScript("OnClick", function()
                    local r, g, b = unpack(sw.currentColor)
                    ColorPickerFrame:SetupColorPickerAndShow({
                        r = r, g = g, b = b,
                        swatchFunc = function()
                            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                            sw:SetColor(nr, ng, nb)
                            if sw.onChanged then sw.onChanged({nr, ng, nb}) end
                        end,
                        cancelFunc = function(p)
                            if p then
                                sw:SetColor(p.r, p.g, p.b)
                                if sw.onChanged then sw.onChanged(sw.currentColor) end
                            end
                        end
                    })
                end)
                sw:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(sw, "ANCHOR_TOP")
                    GameTooltip:SetText("Cliquer pour choisir la couleur")
                    GameTooltip:Show()
                end)
                sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
                return sw
            end

            -- Helper : creer une petite croix de reset (× cliquable)
            local function CreateCloseButton(parent)
                local btn = CreateFrame("Button", nil, parent)
                btn:SetSize(CLOSE_SIZE, CLOSE_SIZE)
                local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                txt:SetPoint("CENTER", 0, 0)
                txt:SetText("×")
                txt:SetTextColor(0.6, 0.6, 0.6)
                btn:SetScript("OnEnter", function()
                    txt:SetTextColor(1, 0.4, 0.4)
                    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
                    GameTooltip:SetText("Reinitialiser cette personnalisation")
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function()
                    txt:SetTextColor(0.6, 0.6, 0.6)
                    GameTooltip:Hide()
                end)
                return btn
            end

            for _, entry in ipairs(list) do
                local sid = entry.sid
                local sg = cf.spellGradients[sid]  -- nil si pas defini
                local gradInit = sg and sg[7] == true

                -- Icone
                local ico = c:CreateTexture(nil, "ARTWORK")
                ico:SetSize(ICON_SIZE, ICON_SIZE)
                ico:SetPoint("TOPLEFT", COL_ICON, -cy - 4)
                ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                if entry.icon then
                    ico:SetTexture(entry.icon)
                else
                    ico:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end

                -- ID du sort
                local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", COL_ID, -cy - 6)
                fs:SetText(tostring(sid))

                -- Carre COULEUR (toujours visible)
                local swMain = CreateSwatch(c)
                swMain:SetPoint("TOPLEFT", COL_SWATCHES, -cy - 2)
                local r1, g1, b1 = sg and sg[1] or 1, sg and sg[2] or 1, sg and sg[3] or 1
                swMain:SetColor(r1, g1, b1)
                swMain.onChanged = function(col)
                    if not ns.db or not ns.db.buffs then return end
                    ns.db.buffs.spellGradients = ns.db.buffs.spellGradients or {}
                    local cur = ns.db.buffs.spellGradients[sid] or {1,1,1, 0.3,0.3,0.3, false}
                    cur[1], cur[2], cur[3] = col[1], col[2], col[3]
                    ns.db.buffs.spellGradients[sid] = cur
                    pcall(ns.ScanAuras)
                end

                -- Carre COULEUR FIN (toujours present, mais grise si Degrade decoche)
                local swEnd = CreateSwatch(c)
                swEnd:SetPoint("TOPLEFT", COL_SWATCHES + SWATCH + SWATCH_GAP, -cy - 2)
                local r2, g2, b2 = sg and sg[4] or r1*0.3, sg and sg[5] or g1*0.3, sg and sg[6] or b1*0.3
                swEnd:SetColor(r2, g2, b2)
                swEnd:SetDimmed(not gradInit)
                swEnd.onChanged = function(col)
                    if not ns.db or not ns.db.buffs then return end
                    ns.db.buffs.spellGradients = ns.db.buffs.spellGradients or {}
                    local cur = ns.db.buffs.spellGradients[sid] or {1,1,1, 0.3,0.3,0.3, true}
                    cur[4], cur[5], cur[6] = col[1], col[2], col[3]
                    ns.db.buffs.spellGradients[sid] = cur
                    pcall(ns.ScanAuras)
                end

                -- Checkbox DEGRADE
                local cbGrad = SW.CreateCheckbox(c, "Degrade", CB_W)
                cbGrad:SetPoint("TOPLEFT", COL_DEGRADE, -cy + 2)
                cbGrad:SetChecked(gradInit)
                cbGrad.onChanged = function(v)
                    if not ns.db or not ns.db.buffs then return end
                    ns.db.buffs.spellGradients = ns.db.buffs.spellGradients or {}
                    local cur = ns.db.buffs.spellGradients[sid] or {1,1,1, 0.3,0.3,0.3, false}
                    cur[7] = v
                    ns.db.buffs.spellGradients[sid] = cur
                    swEnd:SetDimmed(not v)
                    pcall(ns.ScanAuras)
                end

                -- Petite croix Reset
                local btnClose = CreateCloseButton(c)
                btnClose:SetPoint("TOPLEFT", COL_CLOSE, -cy)
                btnClose:SetScript("OnClick", function()
                    if ns.db and ns.db.buffs and ns.db.buffs.spellGradients then
                        ns.db.buffs.spellGradients[sid] = nil
                    end
                    pcall(ns.RebuildDisplay)
                end)

                cy = cy + ROW_H
            end

            cy = cy + 6
            c:SetHeight(cy)
        end}
    end
    sections[#sections+1] = {name="OPACITE & FADE",category="STRUCTURE",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local s1=SW.CreateSlider(c,"Opacite Combat",0,1,0.05,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.fadeIC or 1.0)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].fadeIC=v end; pcall(function() ns.UpdateRenderFade(rk) end) end
            local s2=SW.CreateSlider(c,"Opacite Hors Combat",0,1,0.05,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.fadeOOC or 0.4)
            s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].fadeOOC=v end; pcall(function() ns.UpdateRenderFade(rk) end) end; cy=cy+60
            local s3=SW.CreateSlider(c,"Opacite icone",0,1,0.05,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.iconAlpha or 1.0)
            s3.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAlpha=v end; pcall(ns.RebuildDisplay) end
            local s4=SW.CreateSlider(c,"Opacite barre",0,1,0.05,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.barAlpha or 1.0)
            s4.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barAlpha=v end; pcall(ns.RebuildDisplay) end
            cy=cy+60
            -- v281 : opacite de la statusbar quand un modele 3D est actif en mode "back"
            -- (Remplissage 3D). Defaut 1.0 = statusbar opaque, modele 3D devant. Baisser
            -- pour avoir l'effet "ArcDot3D-like" (statusbar semi-transparente).
            local s5=SW.CreateSlider(c,"Opacite barre quand 3D",0,1,0.05,slW); s5:SetPoint("TOPLEFT",ox,-cy); s5:SetValue(cf.barAlphaWith3D or 1.0)
            s5.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barAlphaWith3D=v end; pcall(ns.RebuildDisplay) end
            cy=cy+60; c:SetHeight(cy) end}
    -- TEXTE DE DUREE : texte de duree centre sur l'icone (ou centre sur la row pour freebars, qui n'a pas d'icone).
    -- Layout calque sur la section "Texte de Cooldown" de la PriorityBar : checkbox + slider taille + couleur,
    -- empiles verticalement en pleine largeur, sans choix de police ni offsets (toujours centre).
    if HasSection(rk, "timerIcon") then
        local checkboxLabel = (rk == "freebars") and "Afficher la duree" or "Afficher la duree sur l'icone"
        sections[#sections+1] = {name="TEXTE DE DUREE",category="INFO",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}
            local cbI=SW.CreateCheckbox(c,checkboxLabel,w-30); cbI:SetPoint("TOPLEFT",15,-cy); cbI:SetChecked(cf.timerIconEnabled or false)
            cbI.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerIconEnabled=v end; pcall(ns.ScanAuras) end; cy=cy+28
            local s1=SW.CreateSlider(c,"Taille police",8,24,1,w-30); s1:SetPoint("TOPLEFT",15,-cy); s1:SetValue(cf.timerSize or 12)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerSize=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local cc=SW.CreateColorButton(c,"Couleur du texte",w-30); cc:SetPoint("TOPLEFT",15,-cy)
            cc:SetColor(cf.timerColorR or 1, cf.timerColorG or 1, cf.timerColorB or 1)
            cc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].timerColorR=col[1]; ns.db[rk].timerColorG=col[2]; ns.db[rk].timerColorB=col[3] end; pcall(ns.ScanAuras) end; cy=cy+50
            c:SetHeight(cy) end}
    end

    if HasSection(rk, "stacks") then
        sections[#sections+1] = {name="STACKS",category="INFO",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cb=SW.CreateCheckbox(c,"Afficher les stacks",w-30); cb:SetPoint("TOPLEFT",15,-cy); cb:SetChecked(cf.stackEnabled ~= false)
            cb.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackEnabled=v end; pcall(ns.RebuildDisplay) end; cy=cy+28
            local sfOpts={}; for _,f in ipairs(ns.GetFontList() or {}) do sfOpts[#sfOpts+1]={value=f.value,text=f.text} end
            local sfd=SW.CreateDropdown(c,"Police",sfOpts,w-30); sfd:SetPoint("TOPLEFT",15,-cy)
            sfd:SetValue(cf.stackFont or ns.Media.font)
            sfd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackFont=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local posOpts={{value="BOTTOMRIGHT",text="Bas droite"},{value="BOTTOMLEFT",text="Bas gauche"},{value="TOPRIGHT",text="Haut droite"},{value="TOPLEFT",text="Haut gauche"},{value="CENTER",text="Centre"}}
            local pdd=SW.CreateDropdown(c,"Position",posOpts,slW); pdd:SetPoint("TOPLEFT",ox,-cy)
            pdd:SetValue(cf.stackPos or "BOTTOMRIGHT")
            pdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackPos=v end; pcall(ns.RebuildDisplay) end
            local ss=SW.CreateSlider(c,"Taille police",6,24,1,slW); ss:SetPoint("TOPLEFT",ox+slW+gap,-cy); ss:SetValue(cf.stackSize or 10)
            ss.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackSize=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local sox=SW.CreateSlider(c,"Offset X",-20,20,1,slW); sox:SetPoint("TOPLEFT",ox,-cy); sox:SetValue(cf.stackOffX or 0)
            sox.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackOffX=v end; pcall(ns.RebuildDisplay) end
            local soy=SW.CreateSlider(c,"Offset Y",-20,20,1,slW); soy:SetPoint("TOPLEFT",ox+slW+gap,-cy); soy:SetValue(cf.stackOffY or 0)
            soy.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackOffY=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            local scc=SW.CreateColorButton(c,"Couleur des stacks",w-30); scc:SetPoint("TOPLEFT",15,-cy)
            scc:SetColor(cf.stackColorR or 1, cf.stackColorG or 1, cf.stackColorB or 1)
            scc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].stackColorR=col[1]; ns.db[rk].stackColorG=col[2]; ns.db[rk].stackColorB=col[3] end; pcall(ns.RebuildDisplay) end
            cy=cy+30; c:SetHeight(cy) end}
    end

    if HasSection(rk, "charges") then
        sections[#sections+1] = {name="CHARGES",category="INFO",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cb=SW.CreateCheckbox(c,"Afficher les charges",w-30); cb:SetPoint("TOPLEFT",15,-cy); cb:SetChecked(cf.chargesEnabled ~= false)
            cb.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesEnabled=v end; pcall(ns.RebuildDisplay) end; cy=cy+28
            local cfOpts={}; for _,f in ipairs(ns.GetFontList() or {}) do cfOpts[#cfOpts+1]={value=f.value,text=f.text} end
            local cfd=SW.CreateDropdown(c,"Police",cfOpts,w-30); cfd:SetPoint("TOPLEFT",15,-cy)
            cfd:SetValue(cf.chargesFont or ns.Media.font)
            cfd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesFont=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local cposOpts={{value="BOTTOMRIGHT",text="Bas droite"},{value="BOTTOMLEFT",text="Bas gauche"},{value="TOPRIGHT",text="Haut droite"},{value="TOPLEFT",text="Haut gauche"},{value="CENTER",text="Centre"}}
            local cpdd=SW.CreateDropdown(c,"Position",cposOpts,slW); cpdd:SetPoint("TOPLEFT",ox,-cy)
            cpdd:SetValue(cf.chargesPos or "TOPLEFT")
            cpdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesPos=v end; pcall(ns.RebuildDisplay) end
            local css=SW.CreateSlider(c,"Taille police",6,24,1,slW); css:SetPoint("TOPLEFT",ox+slW+gap,-cy); css:SetValue(cf.chargesSize or 10)
            css.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesSize=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local csox=SW.CreateSlider(c,"Offset X",-20,20,1,slW); csox:SetPoint("TOPLEFT",ox,-cy); csox:SetValue(cf.chargesOffX or 0)
            csox.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesOffX=v end; pcall(ns.RebuildDisplay) end
            local csoy=SW.CreateSlider(c,"Offset Y",-20,20,1,slW); csoy:SetPoint("TOPLEFT",ox+slW+gap,-cy); csoy:SetValue(cf.chargesOffY or 0)
            csoy.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesOffY=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            local ccc=SW.CreateColorButton(c,"Couleur des charges",w-30); ccc:SetPoint("TOPLEFT",15,-cy)
            ccc:SetColor(cf.chargesColorR or 0.4, cf.chargesColorG or 0.7, cf.chargesColorB or 1.0)
            ccc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].chargesColorR=col[1]; ns.db[rk].chargesColorG=col[2]; ns.db[rk].chargesColorB=col[3] end; pcall(ns.RebuildDisplay) end
            cy=cy+30; c:SetHeight(cy) end}
    end

    -- Section Couleurs d'urgence : curve native Blizzard qui teinte la barre
    -- selon le % restant. Chaque render (debuffs/cooldowns/procs) a sa propre
    -- config indépendante : checkbox + 2 color pickers.
    -- Quand l'utilisateur change une couleur, InvalidateUrgencyCurves() vide le
    -- cache de curves pour que la prochaine build utilise les nouvelles couleurs.
    sections[#sections+1] = {name="COULEURS D'URGENCE",category="ANIMATION",build=function(c,w) local cy=10; local cf=ns.db and ns.db[rk] or {}
        local cb = SW.CreateCheckbox(c, "Activer color curve", w-30)
        cb:SetPoint("TOPLEFT", 15, -cy)
        cb:SetChecked(cf.urgencyEnabled ~= false)
        cb.onChanged = function(v)
            if ns.db and ns.db[rk] then ns.db[rk].urgencyEnabled = v end
            if ns.InvalidateUrgencyCurves then ns.InvalidateUrgencyCurves() end
            pcall(ns.RebuildDisplay)
        end
        cy = cy + 32

        local cm = SW.CreateColorButton(c, "Couleur medium (~20% restant)", w-30)
        cm:SetPoint("TOPLEFT", 15, -cy)
        cm:SetColor(cf.urgencyMediumR or 1.0, cf.urgencyMediumG or 0.5, cf.urgencyMediumB or 0.0)
        cm.onChanged = function(col)
            if ns.db and ns.db[rk] then
                ns.db[rk].urgencyMediumR = col[1]
                ns.db[rk].urgencyMediumG = col[2]
                ns.db[rk].urgencyMediumB = col[3]
            end
            if ns.InvalidateUrgencyCurves then ns.InvalidateUrgencyCurves() end
            pcall(ns.RebuildDisplay)
        end
        cy = cy + 30

        local cc = SW.CreateColorButton(c, "Couleur critique (fin d'aura)", w-30)
        cc:SetPoint("TOPLEFT", 15, -cy)
        cc:SetColor(cf.urgencyCriticalR or 1.0, cf.urgencyCriticalG or 0.15, cf.urgencyCriticalB or 0.05)
        cc.onChanged = function(col)
            if ns.db and ns.db[rk] then
                ns.db[rk].urgencyCriticalR = col[1]
                ns.db[rk].urgencyCriticalG = col[2]
                ns.db[rk].urgencyCriticalB = col[3]
            end
            if ns.InvalidateUrgencyCurves then ns.InvalidateUrgencyCurves() end
            pcall(ns.RebuildDisplay)
        end
        cy = cy + 30

        c:SetHeight(cy + 10)
    end}

    -- Tri logique des sections par categorie puis nom defini.
    -- Categories dans l'ordre : STRUCTURE > APPARENCE > ANIMATION > INFO.
    -- Dans chaque categorie, ordre custom pour que les plus utilisees soient en haut.
    local CATEGORY_ORDER = { STRUCTURE = 1, APPARENCE = 2, ANIMATION = 3, INFO = 4 }
    local NAME_ORDER = {
        -- STRUCTURE
        ["POSITION"]                 = 1,
        ["DIMENSIONS"]               = 2,
        ["ICONES & DIMENSIONS"]      = 2,
        ["OPACITE & FADE"]           = 3,
        -- APPARENCE
        ["BARRE (COULEUR & TEXTURE)"]= 1,
        ["ETINCELLE (SPARK)"]        = 2,
        ["GLOW"]                     = 3,
        ["PRESETS BARRES"]           = 4,
        ["COULEUR PAR SORT"]         = 5,
        -- ANIMATION
        ["ANIMATION D'APPARITION"]   = 1,
        ["ANIMATION ICONE"]          = 2,
        ["COULEURS D'URGENCE"]       = 3,
        -- INFO
        ["TIMER ICONE"]              = 1,
        ["STACKS"]                   = 2,
        ["CHARGES"]                  = 3,
    }
    table.sort(sections, function(a, b)
        local ca = CATEGORY_ORDER[a.category or ""] or 99
        local cb = CATEGORY_ORDER[b.category or ""] or 99
        if ca ~= cb then return ca < cb end
        local na = NAME_ORDER[a.name or ""] or 99
        local nb = NAME_ORDER[b.name or ""] or 99
        return na < nb
    end)

    SW.CreateSectionStack(p, sections, cw, y)

    -- Preview live : tant que ce menu est ouvert, remplace le contenu de la
    -- dest "rk" par 2-3 fausses entrees pour visualiser taille/position/
    -- couleurs en direct (voir BuildPreviewEntries dans Scan.lua).
    p:SetScript("OnShow", function()
        ns._previewBars = true
        ns._previewMode = rk
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
    end)
    p:SetScript("OnHide", function()
        ns._previewBars = false
        ns._previewMode = nil
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
    end)
end

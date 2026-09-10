-- AishUIAura/UI/Menus/Render.lua
-- Per-render menu (Debuffs / Cooldowns / Procs / Buffs): layout cards + accordion sections
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

local TC = 0.07

-- Sections optionnelles par render (les sections de base sont toujours creees par BuildRenderMenu)
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
    totems     = DEFAULT_OPTIONAL_SECTIONS,
    -- freebars ("Barres de cercle") : pas d'icone/glow/stacks/charges, mais a
    -- un texte de duree, positionne relatif au conteneur de barre plutot
    -- qu'a une icone.
    freebars   = { timerIcon = true },
}

-- Sous-features optionnelles par render : iconSize (sliders taille icone), desatSwipe
-- (desaturation + swipe cooldown), growthDirection (direction empilement + max barres)
local DEFAULT_OPTIONAL_FEATURES = {
    iconSize        = true,
    desatSwipe      = true,
    growthDirection = true,
}

local OPTIONAL_FEATURES_BY_RENDER = {
    iconlist   = DEFAULT_OPTIONAL_FEATURES,
    circlebars = DEFAULT_OPTIONAL_FEATURES,
    icons      = DEFAULT_OPTIONAL_FEATURES,
    totems     = DEFAULT_OPTIONAL_FEATURES,
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

    -- Destination "icons" (Procs.lua), groupe natif partage : reapplique taille/glow/swipe/duree/stacks
    -- sur tous les boutons apres un reglage, sinon rien ne bouge a l'ecran.
    local function IconsRefresh()
        if rk == "icons" and ns.RepositionIconsNativeGrid then pcall(ns.RepositionIconsNativeGrid) end
    end

    -- Meme principe pour l'onglet "Circle Bars" (freebars, backe par Buffs.lua).
    local function CircleBarsRefresh()
        if rk == "freebars" and ns.RepositionCircleBarsNativeGrid then pcall(ns.RepositionCircleBarsNativeGrid) end
    end

    -- Meme principe pour "Free Bars" (circlebars, backe par Cooldowns.lua) : niveau conteneur seulement,
    -- le style par bouton n'est ré-appliqué qu'au prochain rebuild de whitelist.
    local function FreeBarsRefresh()
        if rk == "circlebars" and ns.RepositionFreeBarsNativeGrid then pcall(ns.RepositionFreeBarsNativeGrid) end
        if rk == "totems" and ns.RepositionTotemsGrid then pcall(ns.RepositionTotemsGrid) end
    end

    -- Meme principe pour "Liste d'icones" (iconlist, backe par Debuffs.lua) : niveau conteneur seulement,
    -- un changement de taille necessite un /reload.
    local function IconListRefresh()
        if rk == "iconlist" and ns.RepositionIconListNativeGrid then pcall(ns.RepositionIconListNativeGrid) end
    end

    local y=0
    local dispLabels={iconlist=L["AURASMENU_RENDER_DISPOSITION_ICONLIST"],circlebars=L["AURASMENU_RENDER_DISPOSITION_CIRCLEBARS"],icons=L["AURASMENU_RENDER_DISPOSITION_ICONS"],freebars=L["AURASMENU_RENDER_DISPOSITION_FREEBARS"],totems=L["AURASMENU_RENDER_DISPOSITION_TOTEMS"]}
    local dH=SW.CreateSectionHeader(p,string.format(L["AURASMENU_RENDER_DISPOSITION_HEADER"], dispLabels[rk] or ""),cw-20); dH:SetPoint("TOPLEFT",10,-y); y=y+22
    local lays=({iconlist={"center_mirror","center_dual"},circlebars={"side_large","side_compact","side_banner"},icons={"portrait_small"},freebars={"resource_circle"},totems={"side_large","side_compact","side_banner"}})[rk] or {}
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
                if lc.mirrorCb then lc.mirrorCb:Show() end
            else
                lc.lbl:SetTextColor(unpack(Theme.textDisabled))
                -- Swap TGA en version inactive (gris)
                local tex = ns.LAYOUT_ICONS_INACTIVE and ns.LAYOUT_ICONS_INACTIVE[lc.key:upper()]
                if tex then pcall(function() lc.ico:SetTexture(tex) end) end
                lc.ico:SetVertexColor(1,1,1,1)
                if lc.actTx then lc.actTx:Hide() end
                if lc.mirrorCb then lc.mirrorCb:Hide() end
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
            actTx:SetTextColor(unpack(Theme.accent)); actTx:SetText(L["AURASMENU_EQUIPMENT_ACTIVE_LABEL"]) end

        -- Case "Miroir" (cfg.iconPos) pour side_large : inverse le cote de la barre vs l'icone,
        -- le sens de remplissage suit automatiquement. Uniquement circlebars/totems.
        local mirrorCb=nil
        if lk == "side_large" and (rk == "circlebars" or rk == "totems") then
            mirrorCb=SW.CreateCheckbox(card,L["AURASMENU_RENDER_MIRROR_LABEL"],80)
            mirrorCb:SetPoint("TOP",card,"BOTTOM",0,-4)
            mirrorCb:SetChecked((cfg and cfg.iconPos) == "LEFT")
            mirrorCb:SetShown(isAct)
            -- Chaine le hover existant de SW.CreateCheckbox (au lieu de le remplacer) pour garder le tooltip en plus.
            local origEnter, origLeave = mirrorCb:GetScript("OnEnter"), mirrorCb:GetScript("OnLeave")
            mirrorCb:SetScript("OnEnter",function(s)
                if origEnter then origEnter(s) end
                GameTooltip:SetOwner(s,"ANCHOR_TOP")
                GameTooltip:SetText(L["AURASMENU_RENDER_MIRROR_TOOLTIP"],1,1,1)
                GameTooltip:Show()
            end)
            mirrorCb:SetScript("OnLeave",function(s) if origLeave then origLeave(s) end; GameTooltip:Hide() end)
            mirrorCb.onChanged=function(v)
                if ns.db and ns.db[rk] then ns.db[rk].iconPos = v and "LEFT" or "RIGHT" end
                pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh()
            end
        end

        layoutCards[#layoutCards+1] = {key=lk, card=card, ico=ico, lbl=clbl, actTx=actTx, mirrorCb=mirrorCb}

        card:SetScript("OnClick",function()
            if ns.db and ns.db[rk] then ns.db[rk].layout=lk end
            -- Create actTx for newly active card if missing (centré en bas)
            for _, lc in ipairs(layoutCards) do
                if not lc.actTx then
                    lc.actTx=lc.card:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lc.actTx,FONT,8)
                    lc.actTx:SetPoint("BOTTOM",0,5); lc.actTx:SetTextColor(unpack(Theme.accent)); lc.actTx:SetText(L["AURASMENU_EQUIPMENT_ACTIVE_LABEL"])
                end
            end
            RefreshLayoutCards(); pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh()
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
    end
    -- Espace supplementaire si la case "Miroir" est visible, pour ne pas chevaucher la section suivante.
    y = y + 130 + ((rk == "circlebars" or rk == "totems") and 30 or 0)
    local sections = {}
    -- GLOW desactive (`false and`) : ecrasait silencieusement le reglage par-sort de Tactics.lua. Code garde intact au cas ou.
    if false and HasSection(rk, "glow") then
        sections[#sections+1] = {id="GLOW",name=L["AURASMENU_RENDER_SECTION_GLOW"],category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local info=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(info,FONT,9)
            info:SetPoint("TOPLEFT",15,-cy); info:SetTextColor(unpack(Theme.textDim))
            info:SetText(L["AURASMENU_RENDER_GLOW_OVERRIDE_INFO"]); cy=cy+18
            local cbGlowOn=SW.CreateCheckbox(c,L["AURASMENU_RENDER_ENABLE_GLOW"],w-30); cbGlowOn:SetPoint("TOPLEFT",15,-cy); cbGlowOn:SetChecked(cf.glowEnabled ~= false)
            cbGlowOn.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowEnabled=v end; pcall(ns.ScanAuras); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+30
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
            local glOpts={{value=0,text=L["AURASMENU_RENDER_GLOW_PER_SPELL_DEFAULT"]}}
            for idx,def in ipairs(ns.GLOW_DEFS) do if not def.isProcStart then glOpts[#glOpts+1]={value=idx,text=def.name} end end
            local gdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_GLOW_TYPE"],glOpts,w-30); gdd:SetPoint("TOPLEFT",15,-cy)
            gdd:SetValue(cf.glowOverrideIdx or 0)
            gdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideIdx=(v>0 and v or nil); cf.glowOverrideIdx=(v>0 and v or nil) end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            cy=cy+50
            local gcc=SW.CreateColorButton(c,L["AURASMENU_TACTICS_GLOW_COLOR"],slW); gcc:SetPoint("TOPLEFT",ox,-cy)
            local gc=ns.barColor
            gcc:SetColor(cf.glowOverrideR or gc[1], cf.glowOverrideG or gc[2], cf.glowOverrideB or gc[3])
            gcc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideR=col[1]; ns.db[rk].glowOverrideG=col[2]; ns.db[rk].glowOverrideB=col[3]; cf.glowOverrideR=col[1]; cf.glowOverrideG=col[2]; cf.glowOverrideB=col[3] end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local goa=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_OPACITY"],0,1,0.05,slW); goa:SetPoint("TOPLEFT",ox+slW+gap,-cy); goa:SetValue(cf.glowOverrideAlpha or 0.7)
            goa.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideAlpha=v end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            cy=cy+60
            local gsc=SW.CreateSlider(c,L["AURASMENU_RENDER_SIZE_GENERIC"],0.3,3.0,0.1,slW); gsc:SetPoint("TOPLEFT",ox,-cy); gsc:SetValue(cf.glowOverrideScale or 1.0)
            gsc.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].glowOverrideScale=v end; RefreshRenderGlowPreview(); pcall(ns.ScanAuras); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            cy=cy+60
            C_Timer.After(0.1, RefreshRenderGlowPreview)
            c:SetHeight(cy) end}
    end
    -- DIMENSIONS : taille des barres et icones, espacements
    -- Le titre s'adapte selon que le render a des icones ou non.
    local dimSectionId = HasFeature(rk, "iconSize") and "ICONES_DIMENSIONS" or "DIMENSIONS"
    local dimSectionName = HasFeature(rk, "iconSize") and L["AURASMENU_RENDER_SECTION_ICONS_DIMENSIONS"] or L["AURASMENU_RENDER_SECTION_DIMENSIONS"]
    sections[#sections+1] = {id=dimSectionId,name=dimSectionName,category="STRUCTURE",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            if HasFeature(rk, "iconSize") then
                local s1=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_ICON_WIDTH"],10,80,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.iconW or 25)
                s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconW=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
                local s2=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_ICON_HEIGHT"],10,80,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.iconH or 25)
                s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconH=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+60
            end
            -- Bar dimensions (Debuffs/Cooldowns: barW/barH, Procs: showBar + barUnderHeight)
            if rk == "icons" then
                local cbBar=SW.CreateCheckbox(c,L["AURASMENU_RENDER_SHOW_BAR"],slW); cbBar:SetPoint("TOPLEFT",ox,-cy); cbBar:SetChecked(cf.showBarUnderIcon ~= false)
                cbBar.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].showBarUnderIcon=v end; pcall(ns.RebuildDisplay) end
                local sbh=SW.CreateSlider(c,L["AURASMENU_RENDER_BAR_HEIGHT"],1,15,1,slW); sbh:SetPoint("TOPLEFT",ox+slW+gap,-cy); sbh:SetValue(cf.barUnderHeight or 3)
                sbh.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barUnderHeight=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
                local bpOpts={{value="BOTTOM",text=L["AURASMENU_RENDER_BELOW_ICON"]},{value="TOP",text=L["AURASMENU_RENDER_ABOVE"]}}
                local bpdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_BAR_POSITION"],bpOpts,slW); bpdd:SetPoint("TOPLEFT",ox,-cy)
                bpdd:SetValue(cf.barPosition or "BOTTOM")
                bpdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barPosition=v end; pcall(ns.RebuildDisplay) end
                local cbRev=SW.CreateCheckbox(c,L["AURASMENU_RENDER_REVERSE_FILL"],slW); cbRev:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbRev:SetChecked(cf.barReverseFill == true)
                cbRev.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barReverseFill=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            else
                local s3=SW.CreateSlider(c,L["AURASMENU_RENDER_BAR_WIDTH"],10,300,1,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.barW or 80)
                s3.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barW=v end; pcall(ns.RebuildDisplay); CircleBarsRefresh(); FreeBarsRefresh() end
                local s4=SW.CreateSlider(c,L["AURASMENU_RENDER_BAR_HEIGHT"],1,30,1,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.barH or 4)
                s4.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barH=v end; pcall(ns.RebuildDisplay); CircleBarsRefresh(); FreeBarsRefresh() end; cy=cy+60
                -- "Barres seules" (circlebars uniquement) : masque l'icone et
                -- retire la place qui lui etait reservee (cf. Dims() dans
                -- Cooldowns.lua).
                if rk == "circlebars" or rk == "totems" then
                    local cbHide=SW.CreateCheckbox(c,L["AURASMENU_RENDER_HIDE_ICON"],slW); cbHide:SetPoint("TOPLEFT",ox,-cy); cbHide:SetChecked(cf.hideIcon == true)
                    cbHide.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].hideIcon=v end; pcall(ns.RebuildDisplay); FreeBarsRefresh() end; cy=cy+50
                end
            end
            local sg=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_SPACING"],0,150,1,slW); sg:SetPoint("TOPLEFT",ox,-cy); sg:SetValue(cf.gap or 4)
            sg.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].gap=v end; pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local srg=SW.CreateSlider(c,L["AURASMENU_RENDER_ROW_SPACING"],0,20,1,slW); srg:SetPoint("TOPLEFT",ox+slW+gap,-cy); srg:SetValue(cf.rowGap or 2)
            srg.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].rowGap=v end; pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+60
            if HasFeature(rk, "desatSwipe") then
                local dsOpts={{value="nil",text=L["AURASMENU_RENDER_PER_SPELL"]},{value="true",text=L["AURASMENU_RENDER_ALWAYS_GRAY"]},{value="false",text=L["AURASMENU_RENDER_NEVER_GRAY"]}}
                local dsdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_DESATURATION"],dsOpts,slW); dsdd:SetPoint("TOPLEFT",ox,-cy)
                local dsVal = cf.desatOverride == nil and "nil" or tostring(cf.desatOverride)
                dsdd:SetValue(dsVal)
                dsdd.onChanged=function(v)
                    if ns.db and ns.db[rk] then
                        if v == "nil" then ns.db[rk].desatOverride = nil
                        elseif v == "true" then ns.db[rk].desatOverride = true
                        else ns.db[rk].desatOverride = false end
                    end; pcall(ns.ScanAuras)
                end
                local cbs=SW.CreateCheckbox(c,L["AURASMENU_RENDER_SWIPE_COOLDOWN"],slW); cbs:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbs:SetChecked(cf.swipeEnabled == true)
                cbs.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].swipeEnabled=v end; pcall(ns.ScanAuras); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
                cy=cy+50
            end
            c:SetHeight(cy) end}
    sections[#sections+1] = {id="POSITION",name=L["AURASMENU_RENDER_SECTION_POSITION"],category="STRUCTURE",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local s1=SW.CreateSlider(c,L["SETTINGS_POSITION_X"],-1000,1000,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.x or 0)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].x=v end; pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local s2=SW.CreateSlider(c,L["SETTINGS_POSITION_Y"],-1000,1000,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.y or 0)
            s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].y=v end; pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+60
            if HasFeature(rk, "growthDirection") then
                local growOpts={{value="DOWN",text=L["AURASMENU_RENDER_GROWTH_TOP_TO_BOTTOM"]},{value="UP",text=L["AURASMENU_RENDER_GROWTH_BOTTOM_TO_TOP"]},{value="LEFT",text=L["AURASMENU_RENDER_GROWTH_RIGHT_TO_LEFT"]},{value="RIGHT",text=L["AURASMENU_RENDER_GROWTH_LEFT_TO_RIGHT"]}}
                local gdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_STACK_DIRECTION"],growOpts,slW); gdd:SetPoint("TOPLEFT",ox,-cy)
                gdd:SetValue(cf.growth or "DOWN")
                gdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].growth=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
                local sm=SW.CreateSlider(c,L["AURASMENU_RENDER_MAX_BARS"],1,12,1,slW); sm:SetPoint("TOPLEFT",ox+slW+gap,-cy); sm:SetValue(cf.maxBars or 8)
                sm.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].maxBars=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
                cy=cy+55
            end
            c:SetHeight(cy) end}

    -- PRESETS BARRES : applique en un clic les DIMENSIONS (bar + spark) du preset, jamais les couleurs.
    -- Liste peuplee depuis Data/AishUITemplates.lua. Desactive (code garde intact via `false and`).
    if false and rk ~= "icons" and rk ~= "freebars" and ns.AishUITemplates then
    sections[#sections+1] = {id="PRESETS_BARRES",name=L["AURASMENU_RENDER_SECTION_PRESETS"],category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            -- État local de la sélection (preset courant uniquement, plus de filtre classe)
            local state = ns._aishPresetState or {}
            ns._aishPresetState = state
            state[rk] = state[rk] or { preset = nil }
            local s = state[rk]

            -- Dropdown PRESET : liste complète des 25 presets avec noms thématiques
            -- Occupe toute la largeur dispo puisqu'il n'y a plus de filtre classe
            local pdd = SW.CreateDropdown(c, L["AURASMENU_RENDER_PRESET_LABEL"], {{value="", text=L["AURASMENU_RENDER_CHOOSE_STYLE"]}}, w - 30); pdd:SetPoint("TOPLEFT", 15, -cy)

            local opts = {{ value = "", text = L["AURASMENU_RENDER_CHOOSE_STYLE"] }}
            for i, p in ipairs(ns.AishUITemplates) do
                -- Juste le nom du preset, les details sont dans la preview en dessous.
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
            previewLbl:SetText(L["AURASMENU_RENDER_PRESET_PREVIEW_LABEL"])
            cy = cy + 18

            -- Container centré pour la preview (fond sombre pour faire ressortir la bar)
            local pvBg = CreateFrame("Frame", nil, c, "BackdropTemplate")
            pvBg:SetSize(w - 30, 50)
            pvBg:SetPoint("TOPLEFT", 15, -cy)
            pvBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            pvBg:SetBackdropColor(0.04, 0.04, 0.06, 0.85)

            -- Barre de preview en gris neutre : le preset montre la forme (dimensions, spark), pas la couleur.
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
            local btn = SW.CreateActionBtn(c, L["AURASMENU_RENDER_APPLY_PRESET"], 200)
            btn:SetPoint("TOP", c, "TOP", 0, -cy)
            btn:SetScript("OnClick", function()
                local idx = tonumber(s.preset or "")
                if not idx then return end
                local p = ns.AishUITemplates and ns.AishUITemplates[idx]
                if p and ns.ApplyAishUITemplate then
                    ns.ApplyAishUITemplate(rk, p)
                    local g = (ns.THEME and ns.THEME.gold) or { 0.78, 0.62, 0.30 }
                    print("|cff" .. string.format("%02x%02x%02x", math.floor(g[1]*255), math.floor(g[2]*255), math.floor(g[3]*255)) ..
                          string.format(L["AURASMENU_RENDER_PRESET_APPLIED_PRINT"], (p.name or "?")))
                    if ns._rebuildCurrentMenu then C_Timer.After(0.1, ns._rebuildCurrentMenu) end
                end
            end)
            cy = cy + 36

            c:SetHeight(cy) end}
    end

    -- SPARK : disponible pour toutes les destinations, y compris "icons"
    -- (spark natif branche sur la barre optionnelle sous l'icone, cf.
    -- AuraTrackerContainer.lua MakeNativeBarSpark).
    do
    sections[#sections+1] = {id="ETINCELLE_SPARK",name=L["AURASMENU_RENDER_SECTION_SPARK"],category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cb=SW.CreateCheckbox(c,L["AURASMENU_RENDER_ENABLE_SPARK"],w-30); cb:SetPoint("TOPLEFT",15,-cy); cb:SetChecked(cf.sparkEnabled~=false)
            cb.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkEnabled=v end; pcall(ns.RebuildDisplay) end; cy=cy+30
            local s1=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_WIDTH"],1,40,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.sparkW or 17)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkW=v end; pcall(ns.RebuildDisplay) end
            local s2=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_HEIGHT"],1,20,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.sparkH or 6)
            s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkH=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            local s3=SW.CreateSlider(c,L["AURASMENU_EQUIPMENT_OPACITY"],0,1,0.05,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.sparkAlpha or 0.9)
            s3.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkAlpha=v end; pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local s4=SW.CreateSlider(c,L["SETTINGS_OFFSET_Y"],-20,20,1,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.sparkOffY or 0)
            s4.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkOffY=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            -- "Meme couleur que la barre" : masque le color picker spark et reprend la couleur deja
            -- resolue de la barre. IconsRefresh() est necessaire sinon le toggle reste sans effet visible
            -- sur les boutons natifs deja crees tant qu'ils ne sont pas decoches/recoches.
            local cbSame=SW.CreateCheckbox(c,L["AURASMENU_RENDER_SPARK_SAME_AS_BAR"],w-30); cbSame:SetPoint("TOPLEFT",15,-cy); cbSame:SetChecked(cf.sparkSameAsBar == true)
            cy=cy+30
            -- Largeur reduite (slW) : en pleine largeur le swatch de CreateColorButton se retrouve loin du label.
            local cc=SW.CreateColorButton(c,L["AURASMENU_RENDER_SPARK_COLOR"],slW); cc:SetPoint("TOPLEFT",15,-cy)
            cc:SetColor(cf.sparkColorR or ns.sparkColor[1], cf.sparkColorG or ns.sparkColor[2], cf.sparkColorB or ns.sparkColor[3])
            cc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].sparkColorR=col[1]; ns.db[rk].sparkColorG=col[2]; ns.db[rk].sparkColorB=col[3] end; pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            cc:SetShown(cf.sparkSameAsBar ~= true)
            cbSame.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkSameAsBar=v end; cc:SetShown(v ~= true); pcall(ns.RebuildDisplay); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            cy=cy+30
            local sparkTexOpts={
                {value="",text=L["AURASMENU_RENDER_SPARK_TEX_CASTINGBAR"]},
                {value="Interface\\CastingBar\\UI-CastingBar-Spark",text=L["AURASMENU_RENDER_SPARK_TEX_CASTINGBAR_SPARK"]},
                {value="atlas:UI-CastingBar-Spark-Small",text=L["AURASMENU_RENDER_SPARK_TEX_SMALL"]},
                {value="atlas:honorsystem-bar-spark",text=L["AURASMENU_RENDER_SPARK_TEX_HONOR"]},
                {value="Interface\\Buttons\\WHITE8x8",text=L["AURASMENU_EQUIPMENT_BORDER_SQUARE"]},
                {value="Interface\\AddOns\\AishCore\\Media\\Statusbars\\aish_gradient",text=L["AURASMENU_RENDER_SPARK_TEX_GRADIENT"]},
            }
            local stdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_SPARK_TEXTURE"],sparkTexOpts,slW); stdd:SetPoint("TOPLEFT",ox,-cy)
            stdd:SetValue(cf.sparkTexture or "")
            stdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkTexture=(v~="" and v or nil) end; pcall(ns.RebuildDisplay) end
            -- Position du spark : devant ou derrière le statusbar
            local sparkLayerOpts={
                {value="front", text=L["AURASMENU_RENDER_SPARK_LAYER_FRONT"]},
                {value="back",  text=L["AURASMENU_RENDER_SPARK_LAYER_BACK"]},
            }
            local sld=SW.CreateDropdown(c,L["AURASMENU_RENDER_SPARK_POSITION"],sparkLayerOpts,slW); sld:SetPoint("TOPLEFT",ox+slW+gap,-cy)
            sld:SetValue(cf.sparkLayer or "front")
            sld.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].sparkLayer=v end; pcall(ns.RebuildDisplay) end
            cy=cy+50; c:SetHeight(cy) end}
    end
    sections[#sections+1] = {id="BARRE_COULEUR_TEXTURE",name=L["AURASMENU_RENDER_SECTION_BAR_COLOR_TEXTURE"],category="APPARENCE",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local bc=ns.barColor
            local cc1=SW.CreateColorButton(c,L["AURASMENU_RENDER_BAR_COLOR"],slW); cc1:SetPoint("TOPLEFT",ox,-cy)
            cc1:SetColor(cf.barColorR or bc[1], cf.barColorG or bc[2], cf.barColorB or bc[3])
            cc1.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].barColorR=col[1]; ns.db[rk].barColorG=col[2]; ns.db[rk].barColorB=col[3] end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local cbG=SW.CreateCheckbox(c,L["AURASMENU_RENDER_HORIZONTAL_GRADIENT"],slW); cbG:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbG:SetChecked(cf.gradientEnabled or false)
            cbG.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].gradientEnabled=v end; pcall(ns.ScanAuras) end; cy=cy+30
            local cc2=SW.CreateColorButton(c,L["AURASMENU_RENDER_GRADIENT_END_COLOR"],slW); cc2:SetPoint("TOPLEFT",ox,-cy)
            cc2:SetColor(cf.gradientR2 or bc[1]*0.3, cf.gradientG2 or bc[2]*0.3, cf.gradientB2 or bc[3]*0.3)
            cc2.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].gradientR2=col[1]; ns.db[rk].gradientG2=col[2]; ns.db[rk].gradientB2=col[3] end; pcall(ns.ScanAuras) end; cy=cy+30
            -- Fond de barre
            local ccBg=SW.CreateColorButton(c,L["AURASMENU_RENDER_BAR_BG_COLOR"],slW); ccBg:SetPoint("TOPLEFT",ox,-cy)
            ccBg:SetColor(cf.barBgR or 0.055, cf.barBgG or 0.055, cf.barBgB or 0.055)
            ccBg.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].barBgR=col[1]; ns.db[rk].barBgG=col[2]; ns.db[rk].barBgB=col[3] end; pcall(ns.RebuildDisplay); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local sBgA=SW.CreateSlider(c,L["AURASMENU_RENDER_BG_OPACITY"],0,1,0.05,slW); sBgA:SetPoint("TOPLEFT",ox+slW+gap,-cy); sBgA:SetValue(cf.barBgAlpha or 0)
            sBgA.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barBgAlpha=v end; pcall(ns.RebuildDisplay); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+60
            local texOpts={}; for _,t in ipairs(ns.BAR_TEXTURES) do texOpts[#texOpts+1]={value=t.value,text=t.text} end
            local tdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_BAR_TEXTURE"],texOpts,w-30); tdd:SetPoint("TOPLEFT",15,-cy)
            tdd:SetValue(cf.texture or ns.BAR_TEXTURES[1].value)
            tdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].texture=v end; pcall(ns.RebuildDisplay); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            cy=cy+50; c:SetHeight(cy) end}

    -- ANIMATION D'APPARITION : pour les renders a barres (pas Procs). Desactive (code garde intact).
    if false and (rk == "freebars" or rk == "iconlist" or rk == "circlebars") then
        sections[#sections+1] = {id="ANIMATION_APPARITION",name=L["AURASMENU_RENDER_SECTION_ANIM_APPEARANCE"],category="ANIMATION",build=function(c,w)
            local cy=0; local cf=ns.db and ns.db[rk] or {}
            local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)

            -- Ligne 1 : checkboxes Activee + Fade alpha
            local cbOn = SW.CreateCheckbox(c,L["AURASMENU_RENDER_ANIM_ENABLED"],slW)
            cbOn:SetPoint("TOPLEFT",ox,-cy); cbOn:SetChecked(cf.popEnabled ~= false)
            cbOn.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popEnabled = v end end

            local cbAlpha = SW.CreateCheckbox(c,L["AURASMENU_RENDER_FADE_ALPHA"],slW)
            cbAlpha:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbAlpha:SetChecked(cf.popAlphaFade ~= false)
            cbAlpha.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popAlphaFade = v end end
            cy = cy + 30

            -- Ligne 2 : sliders Duree + Intensite
            local sDur = SW.CreateSlider(c,L["AURASMENU_RENDER_DURATION_SECONDS"],0.1,2.5,0.05,slW)
            sDur:SetPoint("TOPLEFT",ox,-cy); sDur:SetValue(cf.popDuration or 1.0)
            sDur.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popDuration = v end end

            local sStr = SW.CreateSlider(c,L["AURASMENU_RENDER_EASING_INTENSITY"],1,12,1,slW)
            sStr:SetPoint("TOPLEFT",ox+slW+gap,-cy); sStr:SetValue(cf.popEaseStrength or 5)
            sStr.onChanged = function(v) if ns.db and ns.db[rk] then ns.db[rk].popEaseStrength = math.floor(v + 0.5) end end
            cy = cy + 50

            c:SetHeight(cy)
        end}
    end

    -- ANIMATION ICONE : sans objet pour freebars ("Barres de cercle"), qui n'a pas d'icone.
    -- DESACTIVE : code garde intact, juste desactive via `false and`.
    if false and rk ~= "freebars" then
    sections[#sections+1] = {id="ANIMATION_ICONE",name=L["AURASMENU_RENDER_SECTION_ANIM_ICON"],category="ANIMATION",build=function(c,w)
        local cy=0; local cf=ns.db and ns.db[rk] or {}
        local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
        local SW = ns.SharedWidgets or {}
        local styleOpts = {
            {value="standard", text=L["AURASMENU_RENDER_ANIM_STYLE_STANDARD"]},
            {value="surge",    text=L["AURASMENU_RENDER_ANIM_STYLE_SURGE"]},
            {value="slide",    text=L["AURASMENU_RENDER_ANIM_STYLE_SLIDE"]},
            {value="pop",      text=L["AURASMENU_RENDER_ANIM_STYLE_POP"]},
            {value="none",     text=L["AURASMENU_RENDER_ANIM_STYLE_NONE"]},
        }
        local dd = SW.CreateDropdown and SW.CreateDropdown(c,L["AURASMENU_EQUIPMENT_STYLE"],styleOpts,w-30) or nil
        if dd then
            dd:SetPoint("TOPLEFT",15,-cy); dd:SetValue(cf.iconAnimStyle or "standard")
            dd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAnimStyle=v end end
            cy=cy+50
        end
        local sDur = SW.CreateSlider and SW.CreateSlider(c,L["AURASMENU_RENDER_DURATION_SECONDS"],0.1,1.5,0.05,slW) or nil
        if sDur then
            sDur:SetPoint("TOPLEFT",ox,-cy); sDur:SetValue(cf.iconAnimDuration or 0.4)
            sDur.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAnimDuration=v end end
        end
        local cbOut = SW.CreateCheckbox and SW.CreateCheckbox(c,L["AURASMENU_RENDER_ANIMATE_EXIT"],slW) or nil
        if cbOut then
            cbOut:SetPoint("TOPLEFT",ox+slW+gap,-cy); cbOut:SetChecked(cf.iconAnimOut ~= false)
            cbOut.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAnimOut=v end end
        end
        cy=cy+50; c:SetHeight(cy)
    end}
    end

    sections[#sections+1] = {id="OPACITE_FADE",name=L["AURASMENU_RENDER_SECTION_OPACITY_FADE"],category="STRUCTURE",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local s1=SW.CreateSlider(c,L["AURASMENU_RENDER_OPACITY_COMBAT"],0,1,0.05,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.fadeIC or 1.0)
            s1.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].fadeIC=v end; pcall(function() ns.UpdateRenderFade(rk) end) end
            local s2=SW.CreateSlider(c,L["AURASMENU_RENDER_OPACITY_OOC"],0,1,0.05,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.fadeOOC or 0.4)
            s2.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].fadeOOC=v end; pcall(function() ns.UpdateRenderFade(rk) end) end; cy=cy+60
            local s3=SW.CreateSlider(c,L["AURASMENU_RENDER_ICON_OPACITY"],0,1,0.05,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.iconAlpha or 1.0)
            s3.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].iconAlpha=v end; pcall(ns.RebuildDisplay) end
            local s4=SW.CreateSlider(c,L["AURASMENU_RENDER_BAR_OPACITY"],0,1,0.05,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.barAlpha or 1.0)
            s4.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barAlpha=v end; pcall(ns.RebuildDisplay) end
            cy=cy+60
            -- v281 : opacite de la statusbar quand un modele 3D est actif en mode "back"
            -- (Remplissage 3D). Defaut 1.0 = statusbar opaque, modele 3D devant. Baisser
            -- pour avoir l'effet "ArcDot3D-like" (statusbar semi-transparente).
            local s5=SW.CreateSlider(c,L["AURASMENU_RENDER_BAR_OPACITY_3D"],0,1,0.05,slW); s5:SetPoint("TOPLEFT",ox,-cy); s5:SetValue(cf.barAlphaWith3D or 1.0)
            s5.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].barAlphaWith3D=v end; pcall(ns.RebuildDisplay) end
            cy=cy+60; c:SetHeight(cy) end}
    -- TEXTE DE DUREE : countdown natif Blizzard, personnalisable sur les 4 destinations. Pour freebars
    -- (pas d'icone), la position est relative au conteneur de barre.
    if HasSection(rk, "timerIcon") then
        local checkboxLabel = (rk == "freebars") and L["AURASMENU_RENDER_SHOW_DURATION"] or L["AURASMENU_RENDER_SHOW_DURATION_ON_ICON"]
        sections[#sections+1] = {id="TEXTE_DUREE",name=L["AURASMENU_RENDER_SECTION_DURATION_TEXT"],category="INFO",build=function(c,w) local cy,cf=0,ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cbI=SW.CreateCheckbox(c,checkboxLabel,w-30); cbI:SetPoint("TOPLEFT",15,-cy); cbI:SetChecked(cf.timerIconEnabled or false)
            cbI.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerIconEnabled=v end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+28
            local tfOpts={}; for _,f in ipairs(ns.GetFontList() or {}) do tfOpts[#tfOpts+1]={value=f.value,text=f.text} end
            local tfd=SW.CreateDropdown(c,L["AURASMENU_RENDER_FONT_LABEL"],tfOpts,slW); tfd:SetPoint("TOPLEFT",ox,-cy)
            tfd:SetValue(cf.timerFont or ns.Media.font)
            tfd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerFont=v end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local cc=SW.CreateColorButton(c,L["AURASMENU_RENDER_TEXT_COLOR"],slW); cc:SetPoint("TOPLEFT",ox+slW+gap,-cy)
            cc:SetColor(cf.timerColorR or 1, cf.timerColorG or 1, cf.timerColorB or 1)
            cc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].timerColorR=col[1]; ns.db[rk].timerColorG=col[2]; ns.db[rk].timerColorB=col[3] end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+50
            local posLabel = (rk == "freebars") and L["AURASMENU_RENDER_POSITION_LABEL_BAR"] or L["AURASMENU_RENDER_POSITION_LABEL"]
            local tposOpts={{value="BOTTOMRIGHT",text=L["AURASMENU_RENDER_POS_BOTTOM_RIGHT"]},{value="BOTTOMLEFT",text=L["AURASMENU_RENDER_POS_BOTTOM_LEFT"]},{value="TOPRIGHT",text=L["AURASMENU_RENDER_POS_TOP_RIGHT"]},{value="TOPLEFT",text=L["AURASMENU_RENDER_POS_TOP_LEFT"]},{value="CENTER",text=L["AURASMENU_RENDER_POS_CENTER"]}}
            local tpdd=SW.CreateDropdown(c,posLabel,tposOpts,slW); tpdd:SetPoint("TOPLEFT",ox,-cy)
            tpdd:SetValue(cf.timerPos or "CENTER")
            tpdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerPos=v end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local ts=SW.CreateSlider(c,L["AURASMENU_RENDER_FONT_SIZE"],6,24,1,slW); ts:SetPoint("TOPLEFT",ox+slW+gap,-cy); ts:SetValue(cf.timerSize or 12)
            ts.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerSize=v end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+50
            local tox=SW.CreateSlider(c,L["SETTINGS_OFFSET_X"],-30,30,1,slW); tox:SetPoint("TOPLEFT",ox,-cy); tox:SetValue(cf.timerIconOffX or 0)
            tox.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerIconOffX=v end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local toy=SW.CreateSlider(c,L["SETTINGS_OFFSET_Y"],-30,30,1,slW); toy:SetPoint("TOPLEFT",ox+slW+gap,-cy); toy:SetValue(cf.timerIconOffY or 0)
            toy.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].timerIconOffY=v end; pcall(ns.ScanAuras); IconsRefresh(); CircleBarsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+60
            c:SetHeight(cy) end}
    end

    if HasSection(rk, "stacks") then
        sections[#sections+1] = {id="STACKS",name=L["AURASMENU_RENDER_SECTION_STACKS"],category="INFO",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cb=SW.CreateCheckbox(c,L["AURASMENU_RENDER_SHOW_STACKS"],w-30); cb:SetPoint("TOPLEFT",15,-cy); cb:SetChecked(cf.stackEnabled ~= false)
            cb.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackEnabled=v end; pcall(ns.RebuildDisplay) end; cy=cy+28
            local sfOpts={}; for _,f in ipairs(ns.GetFontList() or {}) do sfOpts[#sfOpts+1]={value=f.value,text=f.text} end
            local sfd=SW.CreateDropdown(c,L["AURASMENU_RENDER_FONT_LABEL"],sfOpts,slW); sfd:SetPoint("TOPLEFT",ox,-cy)
            sfd:SetValue(cf.stackFont or ns.Media.font)
            sfd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackFont=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local scc=SW.CreateColorButton(c,L["AURASMENU_RENDER_STACKS_COLOR"],slW); scc:SetPoint("TOPLEFT",ox+slW+gap,-cy)
            scc:SetColor(cf.stackColorR or 1, cf.stackColorG or 1, cf.stackColorB or 1)
            scc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].stackColorR=col[1]; ns.db[rk].stackColorG=col[2]; ns.db[rk].stackColorB=col[3] end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+50
            local posOpts={{value="BOTTOMRIGHT",text=L["AURASMENU_RENDER_POS_BOTTOM_RIGHT"]},{value="BOTTOMLEFT",text=L["AURASMENU_RENDER_POS_BOTTOM_LEFT"]},{value="TOPRIGHT",text=L["AURASMENU_RENDER_POS_TOP_RIGHT"]},{value="TOPLEFT",text=L["AURASMENU_RENDER_POS_TOP_LEFT"]},{value="CENTER",text=L["AURASMENU_RENDER_POS_CENTER"]}}
            local pdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_POSITION_LABEL"],posOpts,slW); pdd:SetPoint("TOPLEFT",ox,-cy)
            pdd:SetValue(cf.stackPos or "BOTTOMRIGHT")
            pdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackPos=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local ss=SW.CreateSlider(c,L["AURASMENU_RENDER_FONT_SIZE"],6,24,1,slW); ss:SetPoint("TOPLEFT",ox+slW+gap,-cy); ss:SetValue(cf.stackSize or 10)
            ss.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackSize=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+50
            local sox=SW.CreateSlider(c,L["SETTINGS_OFFSET_X"],-20,20,1,slW); sox:SetPoint("TOPLEFT",ox,-cy); sox:SetValue(cf.stackOffX or 0)
            sox.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackOffX=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end
            local soy=SW.CreateSlider(c,L["SETTINGS_OFFSET_Y"],-20,20,1,slW); soy:SetPoint("TOPLEFT",ox+slW+gap,-cy); soy:SetValue(cf.stackOffY or 0)
            soy.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].stackOffY=v end; pcall(ns.RebuildDisplay); IconsRefresh(); FreeBarsRefresh(); IconListRefresh() end; cy=cy+60
            c:SetHeight(cy) end}
    end

    if HasSection(rk, "charges") then
        sections[#sections+1] = {id="CHARGES",name=L["AURASMENU_RENDER_SECTION_CHARGES"],category="INFO",build=function(c,w) local cy=0; local cf=ns.db and ns.db[rk] or {}; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cb=SW.CreateCheckbox(c,L["AURASMENU_RENDER_SHOW_CHARGES"],w-30); cb:SetPoint("TOPLEFT",15,-cy); cb:SetChecked(cf.chargesEnabled ~= false)
            cb.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesEnabled=v end; pcall(ns.RebuildDisplay) end; cy=cy+28
            local cfOpts={}; for _,f in ipairs(ns.GetFontList() or {}) do cfOpts[#cfOpts+1]={value=f.value,text=f.text} end
            local cfd=SW.CreateDropdown(c,L["AURASMENU_RENDER_FONT_LABEL"],cfOpts,slW); cfd:SetPoint("TOPLEFT",ox,-cy)
            cfd:SetValue(cf.chargesFont or ns.Media.font)
            cfd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesFont=v end; pcall(ns.RebuildDisplay) end
            local ccc=SW.CreateColorButton(c,L["AURASMENU_RENDER_CHARGES_COLOR"],slW); ccc:SetPoint("TOPLEFT",ox+slW+gap,-cy)
            ccc:SetColor(cf.chargesColorR or 0.4, cf.chargesColorG or 0.7, cf.chargesColorB or 1.0)
            ccc.onChanged=function(col) if ns.db and ns.db[rk] then ns.db[rk].chargesColorR=col[1]; ns.db[rk].chargesColorG=col[2]; ns.db[rk].chargesColorB=col[3] end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local cposOpts={{value="BOTTOMRIGHT",text=L["AURASMENU_RENDER_POS_BOTTOM_RIGHT"]},{value="BOTTOMLEFT",text=L["AURASMENU_RENDER_POS_BOTTOM_LEFT"]},{value="TOPRIGHT",text=L["AURASMENU_RENDER_POS_TOP_RIGHT"]},{value="TOPLEFT",text=L["AURASMENU_RENDER_POS_TOP_LEFT"]},{value="CENTER",text=L["AURASMENU_RENDER_POS_CENTER"]}}
            local cpdd=SW.CreateDropdown(c,L["AURASMENU_RENDER_POSITION_LABEL"],cposOpts,slW); cpdd:SetPoint("TOPLEFT",ox,-cy)
            cpdd:SetValue(cf.chargesPos or "TOPLEFT")
            cpdd.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesPos=v end; pcall(ns.RebuildDisplay) end
            local css=SW.CreateSlider(c,L["AURASMENU_RENDER_FONT_SIZE"],6,24,1,slW); css:SetPoint("TOPLEFT",ox+slW+gap,-cy); css:SetValue(cf.chargesSize or 10)
            css.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesSize=v end; pcall(ns.RebuildDisplay) end; cy=cy+50
            local csox=SW.CreateSlider(c,L["SETTINGS_OFFSET_X"],-20,20,1,slW); csox:SetPoint("TOPLEFT",ox,-cy); csox:SetValue(cf.chargesOffX or 0)
            csox.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesOffX=v end; pcall(ns.RebuildDisplay) end
            local csoy=SW.CreateSlider(c,L["SETTINGS_OFFSET_Y"],-20,20,1,slW); csoy:SetPoint("TOPLEFT",ox+slW+gap,-cy); csoy:SetValue(cf.chargesOffY or 0)
            csoy.onChanged=function(v) if ns.db and ns.db[rk] then ns.db[rk].chargesOffY=v end; pcall(ns.RebuildDisplay) end; cy=cy+60
            c:SetHeight(cy) end}
    end

    -- Couleurs d'urgence : curve native qui teinte la barre selon le % restant. Exclue pour
    -- freebars/icons (pas pertinent). Desactive (code garde intact).
    if false and rk ~= "freebars" and rk ~= "icons" then
    sections[#sections+1] = {id="COULEURS_URGENCE",name=L["AURASMENU_RENDER_SECTION_URGENCY_COLORS"],category="ANIMATION",build=function(c,w) local cy=10; local cf=ns.db and ns.db[rk] or {}
        local cb = SW.CreateCheckbox(c, L["AURASMENU_RENDER_ENABLE_COLOR_CURVE"], w-30)
        cb:SetPoint("TOPLEFT", 15, -cy)
        cb:SetChecked(cf.urgencyEnabled ~= false)
        cb.onChanged = function(v)
            if ns.db and ns.db[rk] then ns.db[rk].urgencyEnabled = v end
            if ns.InvalidateUrgencyCurves then ns.InvalidateUrgencyCurves() end
            pcall(ns.RebuildDisplay)
        end
        cy = cy + 32

        local cm = SW.CreateColorButton(c, L["AURASMENU_RENDER_MEDIUM_COLOR"], w-30)
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

        local cc = SW.CreateColorButton(c, L["AURASMENU_RENDER_CRITICAL_COLOR"], w-30)
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
    end

    -- Tri logique des sections par categorie puis nom defini.
    -- Categories dans l'ordre : STRUCTURE > APPARENCE > ANIMATION > INFO.
    -- Dans chaque categorie, ordre custom pour que les plus utilisees soient en haut.
    local CATEGORY_ORDER = { STRUCTURE = 1, APPARENCE = 2, ANIMATION = 3, INFO = 4 }
    -- NOTE: keyed by the stable (non-localized) `id` field of each section, not by
    -- the (now localized) `name` field, so sorting doesn't break across locales.
    local NAME_ORDER = {
        -- STRUCTURE
        ["POSITION"]                 = 1,
        ["DIMENSIONS"]               = 2,
        ["ICONES_DIMENSIONS"]        = 2,
        ["OPACITE_FADE"]             = 3,
        -- APPARENCE
        ["BARRE_COULEUR_TEXTURE"]    = 1,
        ["ETINCELLE_SPARK"]          = 2,
        ["GLOW"]                     = 3,
        ["PRESETS_BARRES"]           = 4,
        ["COULEUR_PAR_SORT"]         = 5,
        -- ANIMATION
        ["ANIMATION_APPARITION"]     = 1,
        ["ANIMATION_ICONE"]          = 2,
        ["COULEURS_URGENCE"]         = 3,
        -- INFO
        ["TIMER ICONE"]              = 1,
        ["STACKS"]                   = 2,
        ["CHARGES"]                  = 3,
    }
    table.sort(sections, function(a, b)
        local ca = CATEGORY_ORDER[a.category or ""] or 99
        local cb = CATEGORY_ORDER[b.category or ""] or 99
        if ca ~= cb then return ca < cb end
        local na = NAME_ORDER[a.id or ""] or 99
        local nb = NAME_ORDER[b.id or ""] or 99
        return na < nb
    end)

    SW.CreateSectionStack(p, sections, cw, y)

    -- Preview live : remplace le contenu de "rk" par de fausses entrees tant que le menu est ouvert.
    -- "totems" ne passe pas par Scan:Run, sa grille doit etre reconstruite explicitement ici.
    p:SetScript("OnShow", function()
        ns._previewBars = true
        ns._previewMode = rk
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
        if rk == "totems" and ns.RepositionTotemsGrid then pcall(ns.RepositionTotemsGrid) end
    end)
    p:SetScript("OnHide", function()
        ns._previewBars = false
        ns._previewMode = nil
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
        if rk == "totems" and ns.RepositionTotemsGrid then pcall(ns.RepositionTotemsGrid) end
    end)
end

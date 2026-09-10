-- AishUIAura/UI/Menus/Effects.lua
-- 3D Effects menu: spell list + per-layer (bar/icon/spark) editing
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

local TC = 0.07

function ns.SettingsPanel.BuildEffectsMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font
    local panel = ns.SettingsPanel.panel

    local hdr=SW.CreateSectionHeader(p,L["AURASMENU_EFFECTS_MODULE_HEADER"],cw-20); hdr:SetPoint("TOPLEFT",10,0)
    local cbFx=SW.CreateCheckbox(p,L["AURASMENU_EFFECTS_ENABLE_3D"],cw-30)
    cbFx:SetPoint("TOPLEFT",15,-22); cbFx:SetChecked(ns.db and ns.db.effectsEnabled)
    -- Auto-disable en raid : économise le GPU dans les combats denses (opt-in)
    local cbAutoRaid=SW.CreateCheckbox(p,L["AURASMENU_EFFECTS_AUTO_DISABLE_RAID"],cw-30)
    cbAutoRaid:SetPoint("TOPLEFT",15,-44); cbAutoRaid:SetChecked(ns.db and ns.db.effects3DAutoDisableInRaid or false)
    cbAutoRaid.onChanged=function(v)
        if ns.db then ns.db.effects3DAutoDisableInRaid = v end
        if ns.RefreshEffectsSuspension then pcall(ns.RefreshEffectsSuspension) end
    end
    local fxCont=CreateFrame("Frame",nil,p); fxCont:SetPoint("TOPLEFT",10,-72); fxCont:SetPoint("TOPRIGHT",-10,-72)
    do local _sfH = (panel and panel._scrollFrame and panel._scrollFrame:GetHeight()) or 668
       fxCont:SetHeight(math.max(560, _sfH - 60)) end
    local function BuildFx()
        -- Style des onglets actifs : texture parchemin reutilisee depuis les cartouches Modules
        local PARCHEMIN_PATH = "Interface\\AddOns\\AishCore\\Media\\UI\\AishParchemin"
        local ACTIVE_TEXT = {1, 1, 1}                      -- blanc brillant pour l'actif
        local INACTIVE_TEXT = ns.THEME.textDim or {0.5, 0.5, 0.55}
        -- Fond de la row selectionnee dans la liste de sorts a gauche
        local ROW_SELECTED_BG = {0.08, 0.08, 0.10, 0.85}

        -- Applique l'etat actif/inactif a un onglet (fond parchemin vs transparent)
        -- SetTexture(nil) seul ne suffit pas a effacer (reste visible sur certains clients)
        local function SetTabActive(t, isActive)
            if not t then return end
            local bg = t.tBg or t.bg
            local tx = t.tx
            local ul = t.ul
            if isActive then
                -- Fond parchemin (texture or sur gris fonce avec liseré interne)
                bg:SetTexture(PARCHEMIN_PATH)
                if bg.SetTextureSliceMode then
                    pcall(function()
                        bg:SetTextureSliceMode(0)
                        bg:SetTextureSliceMargins(16, 16, 16, 16)
                    end)
                end
                bg:SetVertexColor(1, 1, 1, 1)
                tx:SetTextColor(unpack(ACTIVE_TEXT))
            else
                -- Efface la texture parchemin par un solide transparent (nouveau slot)
                bg:SetColorTexture(0, 0, 0, 0)
                tx:SetTextColor(unpack(INACTIVE_TEXT))
            end
            if ul then ul:Hide() end
        end

        -- Reset tous les onglets puis active celui dont .key correspond
        local function SetActiveOne(btnList, key)
            for _, t in ipairs(btnList) do
                SetTabActive(t, t.key == key)
            end
        end

        -- Cleanup RAM avant rebuild : ClearModel + Hide/SetParent(nil) recursif pour eviter les fuites .m2
        for _, c in pairs({fxCont:GetChildren()}) do
            local stack = { c }
            while #stack > 0 do
                local f = table.remove(stack)
                if f.ClearModel then pcall(f.ClearModel, f) end
                for _, reg in pairs({f:GetRegions()}) do
                    pcall(function() if reg.Hide then reg:Hide() end end)
                end
                for _, gc in pairs({f:GetChildren()}) do
                    pcall(function() if gc.Hide then gc:Hide() end end)
                    pcall(function() if gc.SetParent then gc:SetParent(nil) end end)
                    table.insert(stack, gc)
                end
            end
            c:Hide()
            c:SetParent(nil)
        end
        for _,r in pairs({fxCont:GetRegions()}) do r:Hide() end
        if not (ns.db and ns.db.effectsEnabled) then fxCont:SetHeight(1); p:SetHeight(60); return end
        local totalW = fxCont:GetWidth(); if totalW < 100 then totalW = cw - 20 end
        local LEFT_W=230
        local spells=ns.GetSpecSpells()
        local selectedSpellID = ns._selectedFx3dSpell or nil
        local activeView = "iconlist"
        local activeTab = ns._selectedFx3dTab or "icon"

        -- LEFT PANEL
        local _gdL = Theme.gold or {0.78,0.62,0.30}
        local lf=CreateFrame("Frame",nil,fxCont); lf:SetPoint("TOPLEFT"); lf:SetPoint("BOTTOMLEFT"); lf:SetWidth(LEFT_W)
        -- Pas de fond ici, on herite de celui du panel principal
        local lfH=lf:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lfH,FONT,10); lfH:SetPoint("TOPLEFT",10,-8); lfH:SetTextColor(_gdL[1],_gdL[2],_gdL[3]); lfH:SetText(L["AURASMENU_EFFECTS_ACTIVE_SPELLS"])
        local lfS=lf:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lfS,FONT,9); lfS:SetPoint("TOPLEFT",10,-22); lfS:SetTextColor(unpack(Theme.textDim)); lfS:SetText(L["AURASMENU_EFFECTS_AUTO_FROM_TACTICS"])
        local ly=38

        -- RIGHT PANEL
        local _gd = Theme.gold or {0.78,0.62,0.30}
        local rf=CreateFrame("Frame",nil,fxCont); rf:SetPoint("TOPLEFT",LEFT_W+2,0); rf:SetPoint("BOTTOMRIGHT",0,0)
        local rfIco=rf:CreateTexture(nil,"ARTWORK"); rfIco:SetSize(36,36); rfIco:SetPoint("TOPLEFT",8,-3); rfIco:SetTexCoord(TC,1-TC,TC,1-TC)
        rfIco:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        local rfNm=rf:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(rfNm,FONT,12); rfNm:SetPoint("TOPLEFT",50,-8)
        rfNm:SetPoint("RIGHT",rf,"RIGHT",-140,0); rfNm:SetTextColor(1,1,1); rfNm:SetText(L["AURASMENU_EFFECTS_SELECT_A_SPELL"]); rfNm:SetJustifyH("LEFT")

        local RefreshTabVisibility -- defini apres les anim tabs ci-dessous

        -- View tabs : anim 3D configurable par render. [TOUTES] = fallback partout.
        -- Matrice de compatibilite : BUFFS pas d'icone, PROCS pas de spark, EQUIP que l'icone.
        local viewNames={L["AURASMENU_EFFECTS_VIEW_LIST"],L["AURASMENU_EFFECTS_VIEW_CIRCLE"],L["AURASMENU_EFFECTS_VIEW_FREE"],L["AURASMENU_EFFECTS_VIEW_ICONS"],L["AURASMENU_EFFECTS_VIEW_EQUIP"],L["AURASMENU_EFFECTS_VIEW_ALL"]}
        local viewKeys={"iconlist","freebars","circlebars","icons","equipment","all"}
        local LAYER_COMPAT = {
            all        = { icon=true,  bar=true,  spark=true  },
            iconlist   = { icon=true,  bar=true,  spark=true  },
            freebars   = { icon=false, bar=true,  spark=true  },
            circlebars = { icon=true,  bar=true,  spark=true  },
            icons      = { icon=true,  bar=true,  spark=false },
            equipment  = { icon=true,  bar=false, spark=false },
        }
        local VIEW_W = 86  -- 6 onglets * 86 = 516px, tient sur la largeur du panneau droit

        local viewBtns={}
        local viewFrames={}
        for vi,vn in ipairs(viewNames) do
            local vt=CreateFrame("Button",nil,rf); vt:SetSize(VIEW_W,24); vt:SetPoint("TOPLEFT",(vi-1)*VIEW_W,-40)
            viewFrames[vi]=vt
            local vtBg=vt:CreateTexture(nil,"BACKGROUND"); vtBg:SetAllPoints()
            local vtTx=vt:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(vtTx,FONT,10); vtTx:SetAllPoints(); vtTx:SetJustifyH("CENTER")
            vtTx:SetText(vn)
            -- Soulignement legacy (toujours cache, le parchemin gere l'effet actif)
            local vtUl=vt:CreateTexture(nil,"OVERLAY"); vtUl:SetHeight(1); vtUl:SetPoint("BOTTOMLEFT"); vtUl:SetPoint("BOTTOMRIGHT")
            vtUl:Hide()
            viewBtns[vi]={bg=vtBg, tx=vtTx, ul=vtUl, key=viewKeys[vi]}
            -- Etat initial via le helper (TOUTES = actif au build)
            SetTabActive(viewBtns[vi], vi == 1)
            vt:SetScript("OnClick",function() activeView=viewKeys[vi]
                SetActiveOne(viewBtns, activeView)
                if RefreshTabVisibility then RefreshTabVisibility() end
                -- Injecte une fausse barre (preview) dans la vue active si un sort est selectionne
                if selectedSpellID then
                    ns._previewBars = true
                    ns._previewMode = activeView == "all" and "all" or activeView
                    if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
                    pcall(function() ns.ScanAuras() end)
                end
            end)
        end

        -- Separateur fin entre le bloc vues et le bloc anim tabs (gris tres dim)
        local sep=rf:CreateTexture(nil,"BORDER"); sep:SetHeight(1)
        sep:SetPoint("TOPLEFT",0,-68); sep:SetPoint("TOPRIGHT",0,-68)
        sep:SetColorTexture(0.18, 0.18, 0.20, 0.6)

        -- Recompacte les onglets visibles a gauche (evite les trous)
        local function RepositionViewTabs()
            local pos = 0
            for vi, vf in ipairs(viewFrames) do
                if vf:IsShown() then
                    vf:ClearAllPoints()
                    vf:SetPoint("TOPLEFT", pos * VIEW_W, -40)
                    pos = pos + 1
                end
            end
        end

        -- Forward declare RefreshLayers (used by tab click handlers below)
        local RefreshLayers
        local RefreshInlinePreview

        -- Anim tabs (ICONE first, then BARRE, SPARK)
        local tabBtns={}
        local tabs={{"icon",L["AURASMENU_EFFECTS_TAB_ICON"]},{"bar",L["AURASMENU_EFFECTS_TAB_BAR"]},{"spark",L["AURASMENU_EFFECTS_TAB_SPARK"]}}
        for ti,td in ipairs(tabs) do
            local tab=CreateFrame("Button",nil,rf); tab:SetSize(133,28); tab:SetPoint("TOPLEFT",(ti-1)*133,-92)
            local tBg=tab:CreateTexture(nil,"BACKGROUND"); tBg:SetAllPoints()
            local tTx=tab:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(tTx,FONT,10); tTx:SetAllPoints(); tTx:SetJustifyH("CENTER")
            tTx:SetText(td[2])
            -- Soulignement legacy (toujours cache, le parchemin gere l'effet actif)
            local ul=tab:CreateTexture(nil,"OVERLAY"); ul:SetHeight(1); ul:SetPoint("BOTTOMLEFT"); ul:SetPoint("BOTTOMRIGHT")
            ul:Hide()
            tabBtns[ti]={btn=tab, tBg=tBg, tx=tTx, ul=ul, key=td[1]}
            -- Etat initial via le helper (le 1er = actif au build)
            SetTabActive(tabBtns[ti], ti == 1)
            tab:SetScript("OnClick",function() activeTab=td[1]; ns._selectedFx3dTab=td[1]
                SetActiveOne(tabBtns, activeTab)
                RefreshInlinePreview(); RefreshLayers()
            end)
        end

        -- Cache les onglets ANIMS incompatibles avec la vue active, repositionne le reste sans trous
        function RefreshTabVisibility()
            local compat = LAYER_COMPAT[activeView] or LAYER_COMPAT.all
            local visibleTabs = {}
            for _, t in ipairs(tabBtns) do
                if compat[t.key] then table.insert(visibleTabs, t) end
            end
            local nVis = #visibleTabs
            if nVis == 0 then nVis = 1 end  -- safety, ne devrait jamais arriver
            local rfW = rf:GetWidth() or 0 -- fallback 400 si pas encore layout-e
            if rfW < 100 then rfW = 400 end
            local tabW = math.floor(rfW / nVis)
            for i, t in ipairs(visibleTabs) do
                t.btn:Show()
                t.btn:ClearAllPoints()
                t.btn:SetSize(tabW, 28)
                t.btn:SetPoint("TOPLEFT", (i-1)*tabW, -92)
            end
            -- Cache les onglets non-visibles
            for _, t in ipairs(tabBtns) do
                if not compat[t.key] then t.btn:Hide() end
            end
            -- Si l'onglet actif devient incompatible, bascule sur le premier visible
            if not compat[activeTab] and visibleTabs[1] then
                activeTab = visibleTabs[1].key
                ns._selectedFx3dTab = activeTab
            end
            -- Reset tous les tabBtns (visibles ou non) pour eviter 2 onglets actifs en meme temps
            SetActiveOne(tabBtns, activeTab)
            if RefreshInlinePreview then RefreshInlinePreview() end
            if RefreshLayers then RefreshLayers() end
        end

        RefreshTabVisibility() -- applique la visibilite pour la vue initiale ("all" par defaut)

        -- Preview 3D inline (affiche le modèle de la couche sélectionnée)
        local pvArea=CreateFrame("Frame",nil,rf,"BackdropTemplate")
        pvArea:SetPoint("TOPLEFT",5,-122); pvArea:SetPoint("TOPRIGHT",-5,-122); pvArea:SetHeight(130)
        pvArea:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
        pvArea:SetBackdropColor(0.025,0.025,0.035,0.92); pvArea:SetBackdropBorderColor(_gd[1],_gd[2],_gd[3],0.45)
        local pvLbl=pvArea:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(pvLbl,FONT,8)
        pvLbl:SetPoint("TOPLEFT",6,-3); pvLbl:SetTextColor(unpack(Theme.textDim)); pvLbl:SetText(L["AURASMENU_EFFECTS_MODEL_3D_LABEL"])
        local pvModelView=CreateFrame("PlayerModel",nil,pvArea)
        pvModelView:SetPoint("TOPLEFT",2,-14); pvModelView:SetPoint("BOTTOMRIGHT",-2,2)
        pvModelView:SetKeepModelOnHide(true); pvModelView:SetFrameLevel(pvArea:GetFrameLevel()+3)
        -- Texture preview pour le mode Fill 2D (creee a la demande dans RefreshInlinePreview)
        local pvFillPreview = nil
        -- Supprime le plancher/fond blanc rendu par PlayerModel (voir popup preview)
        pcall(function() pvModelView:SetLight(false, false) end)
        pcall(function() if pvModelView.SetFogFar then pvModelView:SetFogFar(0) end end)
        -- Mouse wheel zoom
        pvArea:EnableMouseWheel(true)
        local pvZoom = 1.0
        pvArea:SetScript("OnMouseWheel",function(_,delta) pvZoom=math.max(0.1,math.min(5.0,pvZoom+delta*0.15)); pcall(function() pvModelView:SetModelScale(pvZoom) end) end)
        -- Agrandir button
        local pvPopBtn=CreateFrame("Button",nil,pvArea); pvPopBtn:SetSize(60,14); pvPopBtn:SetPoint("TOPRIGHT",-4,-3)
        local pvPopTx=pvPopBtn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(pvPopTx,FONT,8); pvPopTx:SetAllPoints(); pvPopTx:SetJustifyH("RIGHT")
        pvPopTx:SetTextColor(unpack(Theme.accent)); pvPopTx:SetText(L["AURASMENU_EFFECTS_ENLARGE"])
        pvPopBtn:SetScript("OnEnter",function() pvPopTx:SetTextColor(1,1,1) end)
        pvPopBtn:SetScript("OnLeave",function() pvPopTx:SetTextColor(unpack(Theme.accent)) end)
        pvPopBtn:SetScript("OnClick",function()
            if not ns._fx3dPopup then
                local pp=CreateFrame("Frame","AishFX3DPopup",UIParent,"BackdropTemplate")
                pp:SetSize(350,300); pp:SetPoint("CENTER",200,0); pp:SetFrameStrata("DIALOG")
                pp:SetMovable(true); pp:SetClampedToScreen(true); pp:SetResizable(true)
                if pp.SetResizeBounds then pp:SetResizeBounds(250,200,600,500) end
                pp:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                pp:SetBackdropColor(0.03,0.03,0.05,0.95); pp:SetBackdropBorderColor(unpack(Theme.accent))
                pp:EnableMouse(true)
                local ph=CreateFrame("Frame",nil,pp); ph:SetHeight(22); ph:SetPoint("TOPLEFT"); ph:SetPoint("TOPRIGHT"); ph:EnableMouse(true)
                ph:SetScript("OnMouseDown",function(_,b) if b=="LeftButton" then pp:StartMoving() end end)
                ph:SetScript("OnMouseUp",function() pp:StopMovingOrSizing() end)
                local phBg=ph:CreateTexture(nil,"BACKGROUND"); phBg:SetAllPoints(); phBg:SetColorTexture(0.08,0.08,0.10,1)
                pp._title=ph:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(pp._title,FONT,10); pp._title:SetPoint("LEFT",8,0); pp._title:SetTextColor(unpack(Theme.accent))
                local pxB=CreateFrame("Button",nil,ph); pxB:SetSize(22,22); pxB:SetPoint("TOPRIGHT")
                local pxT=pxB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(pxT,FONT,12); pxT:SetAllPoints(); pxT:SetText("x"); pxT:SetTextColor(unpack(Theme.textDim))
                pxB:SetScript("OnClick",function() pp:Hide() end)
                local pGrip=CreateFrame("Button",nil,pp); pGrip:SetSize(16,16); pGrip:SetPoint("BOTTOMRIGHT",-2,2); pGrip:SetFrameLevel(pp:GetFrameLevel()+20)
                pGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
                pGrip:SetScript("OnMouseDown",function() pp:StartSizing("BOTTOMRIGHT") end); pGrip:SetScript("OnMouseUp",function() pp:StopMovingOrSizing() end)
                -- Icon element
                local pIco=CreateFrame("Frame",nil,pp); pIco:SetSize(120,120); pIco:SetPoint("CENTER",0,-10)
                local pIcoTex=pIco:CreateTexture(nil,"ARTWORK"); pIcoTex:SetAllPoints(); pIcoTex:SetTexCoord(TC,1-TC,TC,1-TC)
                local pIcoMdl=CreateFrame("PlayerModel",nil,pIco); pIcoMdl:SetAllPoints(); pIcoMdl:SetKeepModelOnHide(true); pIcoMdl:SetFrameLevel(pIco:GetFrameLevel()+2)
                -- Supprime le plancher/fond blanc rendu par PlayerModel (light+fog off)
                pcall(function() pIcoMdl:SetLight(false, false) end)
                pcall(function() if pIcoMdl.SetFogFar then pIcoMdl:SetFogFar(0) end end)
                pp._pIco=pIco; pp._pIcoTex=pIcoTex; pp._pIcoMdl=pIcoMdl
                -- Bar element
                local pBarWr=CreateFrame("Frame",nil,pp); pBarWr:SetSize(280,14); pBarWr:SetPoint("CENTER",0,-10)
                local pBar=CreateFrame("StatusBar",nil,pBarWr); pBar:SetAllPoints()
                pBar:SetStatusBarTexture(ns.ResolveBarTexFromKey("aish_grad3")); pBar:SetMinMaxValues(0,1); pBar:SetValue(0.65)
                pBar:SetStatusBarColor(ns.barColor[1],ns.barColor[2],ns.barColor[3])
                local pBarBg=pBarWr:CreateTexture(nil,"BACKGROUND"); pBarBg:SetAllPoints(); pBarBg:SetColorTexture(0.055,0.055,0.055,1)
                local pBarMdl=CreateFrame("PlayerModel",nil,pBarWr)
                pBarMdl:SetPoint("TOPLEFT",pBarWr,-40,40); pBarMdl:SetPoint("BOTTOMRIGHT",pBarWr,40,-40)
                pBarMdl:SetKeepModelOnHide(true); pBarMdl:SetFrameLevel(pBarWr:GetFrameLevel()+2)
                pcall(function() pBarMdl:SetLight(false, false) end)
                pcall(function() if pBarMdl.SetFogFar then pBarMdl:SetFogFar(0) end end)
                pp._pBarWr=pBarWr; pp._pBarMdl=pBarMdl
                -- Libère les modèles 3D à la fermeture (évite la fuite mémoire de SetKeepModelOnHide)
                pp:SetScript("OnHide", function(self)
                    if self._pIcoMdl then pcall(self._pIcoMdl.ClearModel, self._pIcoMdl) end
                    if self._pBarMdl then pcall(self._pBarMdl.ClearModel, self._pBarMdl) end
                end)
                ns._fx3dPopup=pp
            end
            local pp=ns._fx3dPopup
            pp._pIco:Hide(); pp._pIcoMdl:Hide(); pp._pIcoMdl:ClearModel()
            pp._pBarWr:Hide(); pp._pBarMdl:Hide(); pp._pBarMdl:ClearModel()
            pp:Show()
            if not selectedSpellID or not ns.SpellFX then pp._title:SetText(L["AURASMENU_EFFECTS_PREVIEW_3D_TITLE"]); return end
            local rk2 = (activeView == "circlebars" and "circlebars") or (activeView == "icons" and "icons") or "iconlist"
            local rcfg = ns.db and ns.db[rk2] or {}
            local iW, iH = rcfg.iconW or 26, rcfg.iconH or 26
            local bW, bH = rcfg.barW or 80, rcfg.barH or 3
            local layers = ns.SpellFX:GetSpellLayers(selectedSpellID, activeView, activeTab)
            local layer; for _, l in ipairs(layers) do if l.modelID and l.modelID > 0 then layer = l; break end end
            if activeTab == "icon" then
                local isWG = ns._selectedFx3dIsWG
                local icoW, icoH = iW, iH
                if isWG then icoW=36; icoH=36 end
                pp._title:SetText(isWG and L["AURASMENU_EFFECTS_PREVIEW_WG_ICON"] or string.format(L["AURASMENU_EFFECTS_PREVIEW_ICON_SIZE"], icoW, icoH))
                local scale = math.min(4, 200/math.max(icoW,icoH))
                pp._pIco:SetSize(icoW*scale, icoH*scale); pp._pIco:Show()
                -- Try spell texture first, then item texture
                pcall(function()
                    local tex = C_Spell.GetSpellTexture(selectedSpellID)
                    if not tex then tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(selectedSpellID) end
                    if not tex then tex = GetItemIcon and GetItemIcon(selectedSpellID) end
                    if not tex then tex = select(3, GetSpellInfo(selectedSpellID)) end
                    if tex then pp._pIcoTex:SetTexture(tex) end
                end)
                if layer then C_Timer.After(0.1, function() pcall(function()
                    pp._pIcoMdl:SetModel(layer.modelID); pp._pIcoMdl:SetPosition(layer.z or 0, layer.x or 0, layer.y or 0)
                    pp._pIcoMdl:SetFacing(math.rad(layer.rotation or 0)); pp._pIcoMdl:SetModelScale(layer.scale or 1)
                    pp._pIcoMdl:SetAlpha(layer.alpha or 0.5); pp._pIcoMdl:Show()
                end) end) end
            else
                pp._title:SetText(activeTab == "spark" and string.format(L["AURASMENU_EFFECTS_PREVIEW_SPARK_SIZE"], bW, bH) or string.format(L["AURASMENU_EFFECTS_PREVIEW_BAR_SIZE"], bW, bH))
                local bScale = math.min(3, 280/math.max(bW,1))
                pp._pBarWr:SetSize(bW*bScale, math.max(bH*bScale, 8)); pp._pBarWr:Show()
                if layer then C_Timer.After(0.1, function() pcall(function()
                    pp._pBarMdl:SetModel(layer.modelID); pp._pBarMdl:SetPosition(layer.z or 0, layer.x or 0, layer.y or 0)
                    pp._pBarMdl:SetFacing(math.rad(layer.rotation or 0)); pp._pBarMdl:SetModelScale(layer.scale or 1)
                    pp._pBarMdl:SetAlpha(layer.alpha or 0.5); pp._pBarMdl:Show()
                end) end) end
            end
        end)

        -- Preview inline simple : juste le modèle 3D
        -- Track selected layer for preview (declared before both functions)
        local selectedLayerIdx = 1
        ns._selectedFx3dLayerIdx = 1

        RefreshInlinePreview = function()
            pvModelView:Hide(); pvModelView:ClearModel()
            pcall(function() pvModelView:SetModel(0) end)  -- force clear
            pvZoom = 1.0
            -- Cache aussi la texture preview eventuelle (cleanup entre changements)
            if pvFillPreview then pvFillPreview:Hide() end
            if not selectedSpellID or not ns.SpellFX then pvLbl:SetText(L["AURASMENU_EFFECTS_PREVIEW_LABEL"]); return end
            local layers = ns.SpellFX:GetSpellLayers(selectedSpellID, activeView, activeTab)
            local layer
            -- Layer actif : le selectionne s'il l'est, sinon le 1er (modelID>0 ou fillTex non vide)
            local function IsLayerActive(l)
                if not l then return false end
                local m = l.mode or "front"
                if m == "mid" then return l.fillTex and l.fillTex ~= "" end
                return l.modelID and l.modelID > 0
            end
            if layers[selectedLayerIdx] and IsLayerActive(layers[selectedLayerIdx]) then
                layer = layers[selectedLayerIdx]
            else
                for _, l in ipairs(layers) do if IsLayerActive(l) then layer = l; break end end
            end
            if not layer then pvLbl:SetText(string.format(L["AURASMENU_EFFECTS_PREVIEW_NONE"], activeTab)); return end
            -- Mode Fill 2D : preview en texture statique
            if (layer.mode or "front") == "mid" and layer.fillTex and layer.fillTex ~= "" then
                local label = ns.GetFillTextureLabel and ns.GetFillTextureLabel(layer.fillTex) or L["AURASMENU_EFFECTS_FILL_FALLBACK"]
                pvLbl:SetText(string.format(L["AURASMENU_EFFECTS_PREVIEW_TEXTURE_2D"], label, activeTab))
                -- Lazy create de la texture preview (1 seule par UI)
                if not pvFillPreview then
                    pvFillPreview = pvModelView:GetParent():CreateTexture(nil, "ARTWORK")
                    pvFillPreview:SetPoint("CENTER", pvModelView, "CENTER", 0, 0)
                end
                pvFillPreview:SetSize(pvModelView:GetWidth() * 0.9, pvModelView:GetHeight() * 0.4)
                pvFillPreview:SetTexture(layer.fillTex)
                pvFillPreview:SetAlpha(layer.fillAlpha or 0.7)
                pvFillPreview:SetVertexColor(layer.fillTintR or 1, layer.fillTintG or 1, layer.fillTintB or 1)
                pvFillPreview:Show()
                return
            end
            -- Mode 3D : preview en PlayerModel (comportement classique)
            pvLbl:SetText(string.format(L["AURASMENU_EFFECTS_PREVIEW_MODEL_3D"], ns.SpellFX:GetModelName(layer.modelID), activeTab))
            C_Timer.After(0.05, function() pcall(function()
                pvModelView:SetModel(layer.modelID)
                pvModelView:SetPosition(layer.z or 0, layer.x or 0, layer.y or 0)
                pvModelView:SetFacing(math.rad(layer.rotation or 0))
                pvModelView:SetModelScale(layer.scale or 1)
                pvModelView:SetAlpha(layer.alpha or 0.5)
                pvModelView:Show()
            end) end)
        end

        -- Layer scroll
        local layerSF=CreateFrame("ScrollFrame",nil,rf,"UIPanelScrollFrameTemplate")
        layerSF:SetPoint("TOPLEFT",5,-256); layerSF:SetPoint("BOTTOMRIGHT",-22,40)
        local layerChild=CreateFrame("Frame",nil,layerSF); layerChild:SetWidth(totalW-LEFT_W-35); layerSF:SetScrollChild(layerChild)


        RefreshLayers = function()
            for _,ch in pairs({layerChild:GetChildren()}) do ch:Hide() end
            for _,rg in pairs({layerChild:GetRegions()}) do rg:Hide() end
            if not selectedSpellID or not ns.SpellFX then
                local emT=layerChild:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(emT,FONT,11)
                emT:SetPoint("TOP",0,-60); emT:SetTextColor(unpack(Theme.textDim)); emT:SetJustifyH("CENTER")
                emT:SetText(L["AURASMENU_EFFECTS_NO_LAYER"])
                local addB=CreateFrame("Button",nil,layerChild,"BackdropTemplate"); addB:SetHeight(28)
                addB:SetPoint("TOPLEFT",10,-130); addB:SetPoint("TOPRIGHT",-10,-130)
                addB:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}); addB:SetBackdropBorderColor(Theme.accent[1],Theme.accent[2],Theme.accent[3],0.3)
                local addT=addB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(addT,FONT,11); addT:SetAllPoints(); addT:SetJustifyH("CENTER"); addT:SetTextColor(unpack(Theme.accent)); addT:SetText(L["AURASMENU_EFFECTS_ADD_LAYER"])
                addB:SetScript("OnClick",function() if selectedSpellID and ns.SpellFX then ns.SpellFX:AddLayer(selectedSpellID,activeView,activeTab); selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers() end end)
                layerChild:SetHeight(170); return
            end
            local layers = ns.SpellFX:GetSpellLayers(selectedSpellID, activeView, activeTab)
            local cy = 5
            if #layers == 0 then
                local emT=layerChild:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(emT,FONT,11)
                emT:SetPoint("TOP",0,-40); emT:SetTextColor(unpack(Theme.textDim)); emT:SetJustifyH("CENTER")
                emT:SetText(L["AURASMENU_EFFECTS_NO_LAYER"]); cy=cy+80
            else
                if selectedLayerIdx > #layers then selectedLayerIdx = #layers end
                for li, layer in ipairs(layers) do
                    local isBar = (activeTab == "bar")
                    local LH = isBar and 200 or 240
                    local lf2=CreateFrame("Frame",nil,layerChild,"BackdropTemplate"); lf2:SetSize(layerChild:GetWidth()-10,LH); lf2:SetPoint("TOPLEFT",5,-cy)
                    lf2:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                    if li == selectedLayerIdx then
                        lf2:SetBackdropColor(0.08,0.08,0.10,0.97); lf2:SetBackdropBorderColor(Theme.accent[1],Theme.accent[2],Theme.accent[3],0.6)
                    else
                        lf2:SetBackdropColor(0.05,0.05,0.07,0.8); lf2:SetBackdropBorderColor(unpack(Theme.border))
                    end
                    lf2:EnableMouse(true)
                    lf2:SetScript("OnMouseDown",function() selectedLayerIdx=li; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers() end)
                    local lhdr=lf2:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lhdr,FONT,10); lhdr:SetPoint("TOPLEFT",8,-5)
                    lhdr:SetTextColor(unpack(Theme.accent)); lhdr:SetText(string.format(L["AURASMENU_EFFECTS_EFFECT_NUM"], li))
                    -- Status badge (right side, near X)
                    local stB=CreateFrame("Frame",nil,lf2); stB:SetSize(62,14); stB:SetPoint("TOPRIGHT",-24,-4)
                    local stBg=stB:CreateTexture(nil,"BACKGROUND"); stBg:SetAllPoints()
                    local stTx=stB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(stTx,FONT,8,"OUTLINE"); stTx:SetAllPoints(); stTx:SetJustifyH("CENTER")
                    local _gold = Theme.gold or {0.78,0.62,0.30}
                    if layer.modelID and layer.modelID > 0 then
                        stBg:SetColorTexture(_gold[1]*0.2, _gold[2]*0.2, _gold[3]*0.2, 0.8); stTx:SetText(ns.SpellFX:GetModelName(layer.modelID)); stTx:SetTextColor(_gold[1], _gold[2], _gold[3])
                    else
                        stBg:SetColorTexture(0.10, 0.10, 0.11, 0.85); stTx:SetText(L["AURASMENU_EFFECTS_NOT_APPLIED"]); stTx:SetTextColor(0.55, 0.55, 0.58)
                    end
                    local delB=CreateFrame("Button",nil,lf2); delB:SetSize(16,16); delB:SetPoint("TOPRIGHT",-4,-3)
                    local delT=delB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(delT,FONT,11); delT:SetAllPoints(); delT:SetText("x"); delT:SetTextColor(0.5, 0.5, 0.55)
                    delB:SetScript("OnClick",function() ns.SpellFX:RemoveLayer(selectedSpellID,activeView,activeTab,li); selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers()
                        pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end) end)
                    delB:SetScript("OnEnter",function() delT:SetTextColor(_gold[1], _gold[2], _gold[3]) end); delB:SetScript("OnLeave",function() delT:SetTextColor(0.5, 0.5, 0.55) end)
                    local mLbl=lf2:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(mLbl,FONT,9); mLbl:SetPoint("TOPLEFT",8,-22); mLbl:SetTextColor(unpack(Theme.textDim)); mLbl:SetText(L["AURASMENU_EFFECTS_PLANE_LABEL"])
                    local mNames, mLabels, mCols
                    if isBar then
                        -- Plans barres : mid=remplissage 2D, back=remplissage 3D (rogne), front=fond fixe
                        mNames={"mid","back","front"}
                        mLabels={L["AURASMENU_EFFECTS_FILL_2D"],L["AURASMENU_EFFECTS_FILL_3D"],L["AURASMENU_EFFECTS_BACKGROUND"]}
                        mCols={{_gold[1], _gold[2], _gold[3]},
                               {_gold[1]*0.85, _gold[2]*0.85, _gold[3]*0.85},
                               {_gold[1]*1.10, _gold[2]*1.10, _gold[3]*1.10}}
                    else
                        mNames={"back","mid","front"}; mLabels={L["AURASMENU_EFFECTS_BACK_PLANE"],L["AURASMENU_EFFECTS_MID_PLANE"],L["AURASMENU_EFFECTS_FRONT_PLANE"]}
                        mCols={{_gold[1]*0.55, _gold[2]*0.55, _gold[3]*0.55}, {_gold[1], _gold[2], _gold[3]}, {_gold[1]*1.10, _gold[2]*1.10, _gold[3]*1.10}}
                    end
                    for mi,mk in ipairs(mNames) do
                        local mb=CreateFrame("Button",nil,lf2); mb:SetSize(90,14); mb:SetPoint("TOPLEFT",55+(mi-1)*95,-20)
                        local mbBg=mb:CreateTexture(nil,"BACKGROUND"); mbBg:SetAllPoints()
                        local mbTx=mb:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(mbTx,FONT,9); mbTx:SetAllPoints(); mbTx:SetJustifyH("CENTER"); mbTx:SetText(mLabels[mi])
                        local cur=layer.mode or "front"; local isAct=(cur==mk)
                        if isAct then mbBg:SetColorTexture(mCols[mi][1]*0.3,mCols[mi][2]*0.3,mCols[mi][3]*0.3,0.8); mbTx:SetTextColor(mCols[mi][1],mCols[mi][2],mCols[mi][3])
                        else mbBg:SetColorTexture(0.05,0.05,0.07,0.5); mbTx:SetTextColor(0.35,0.35,0.40) end
                        mb:SetScript("OnClick",function() layer.mode=mk; if ns.SpellFX and selectedSpellID then pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end) end; pcall(RefreshInlinePreview); pcall(ns.ScanAuras); RefreshLayers() end)
                    end
                    -- Selecteur conditionnel : ModelPicker 3D ou dropdown de textures 2D selon le mode
                    local pickB, idLbl
                    local isFillMode = isBar and ((layer.mode or "front") == "mid")
                    if isFillMode then
                        -- Mode remplissage : dropdown des textures Fill 2D
                        local opts = {}
                        opts[#opts+1] = { value = "", text = L["AURASMENU_EFFECTS_NONE_FEM"] }
                        for _, t in ipairs(ns.FillTextures or {}) do
                            opts[#opts+1] = { value = t.id, text = t.label }
                        end
                        pickB = SW.CreateDropdown(lf2, nil, opts, 220)
                        pickB:SetPoint("TOPLEFT", 8, -40)
                        -- Valeur courante : on extrait le nom de fichier du path stocke
                        local curId = ""
                        if layer.fillTex and layer.fillTex ~= "" then
                            curId = layer.fillTex:match("([^\\/]+)$") or ""
                        end
                        pickB:SetValue(curId)
                        pickB.onChanged = function(v)
                            local newPath = (v and v ~= "") and ns.GetFillTexturePath(v) or ""
                            layer.fillTex = newPath
                            -- Auto-set scrollDef depuis le catalogue (si pas overrides par user)
                            if v and v ~= "" then
                                local def = ns.GetFillTextureScrollDef(v)
                                if layer.fillScroll == nil then layer.fillScroll = def end
                            end
                            if ns.SpellFX and selectedSpellID then
                                pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end)
                            end
                            RefreshInlinePreview(); pcall(ns.ScanAuras)
                        end
                    else
                        -- Mode fond (PlayerModel 3D) ou icon/spark/glow
                        pickB = SW.CreateActionBtn(lf2,L["AURASMENU_EFFECTS_CHOOSE_MODEL"],130,{0.05,0.05,0.06},{_gold[1],_gold[2],_gold[3],0.55},{_gold[1],_gold[2],_gold[3]})
                        pickB:SetPoint("TOPLEFT",8,-40); pickB:SetSize(130,18)
                        pickB:SetScript("OnClick",function()
                            if ns.ModelPicker and ns.ModelPicker.Open then
                                ns.ModelPicker:Open(function(mid,mname,px,py,pscale,prot)
                                    local oldMid = layer.modelID
                                    layer.modelID=mid; if px then layer.x=px end; if py then layer.y=py end
                                    if pscale then layer.scale=pscale end; if prot then layer.rotation=prot end
                                    if ns.SpellFX and selectedSpellID then pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end) end
                                    -- Modele change : propose un reload (Blizzard ne decharge pas un .m2 sans ca)
                                    if mid ~= oldMid and mid and mid > 0 then ns._fx3dDirty = true end
                                    selectedLayerIdx=li; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers(); pcall(ns.ScanAuras)
                                    -- Refresh differe : laisse le temps au .m2 de charger avant de relancer le scan
                                    C_Timer.After(0.15, function() pcall(ns.ScanAuras) end)
                                end, layer.modelID)
                            end end)
                        idLbl=lf2:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(idLbl,FONT,8); idLbl:SetPoint("LEFT",pickB,"RIGHT",8,0)
                        idLbl:SetTextColor(unpack(Theme.textDim)); idLbl:SetText(string.format(L["AURASMENU_EFFECTS_ID_LABEL"], tostring(layer.modelID or 0)))
                    end
                    local slW=math.max(70, math.floor((lf2:GetWidth()-25)/3))
                    local function OnLayerChange(key, v)
                        layer[key]=v; if ns.SpellFX and selectedSpellID then pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end) end
                        selectedLayerIdx=li; ns._selectedFx3dLayerIdx=selectedLayerIdx; pcall(RefreshInlinePreview); pcall(ns.ScanAuras)
                    end
                    local function MkSl(lbl,min,max,step,col,row,key)
                        local s=SW.CreateSlider(lf2,lbl,min,max,step,slW); s:SetPoint("TOPLEFT",5+col*(slW+5),-(65+row*60)); s:SetValue(layer[key] or 0)
                        s.onChanged=function(v) OnLayerChange(key, v) end; return s
                    end
                    if isBar then
                        if isFillMode then
                            -- Sliders pour Fill 2D (texture qui se tronque)
                            local LH2 = 200; lf2:SetHeight(LH2)
                            MkSl(L["AURASMENU_EQUIPMENT_OPACITY"], 0, 1, 0.05, 0, 0, "fillAlpha")
                            MkSl(L["AURASMENU_EFFECTS_SCROLL_SPEED"], 0, 2, 0.05, 1, 0, "fillScroll")
                            -- Color picker pour la teinte
                            local cb = SW.CreateColorButton(lf2, L["AURASMENU_EFFECTS_TINT"], slW)
                            cb:SetPoint("TOPLEFT", 5+2*(slW+5), -65)
                            cb:SetColor(layer.fillTintR or 1, layer.fillTintG or 1, layer.fillTintB or 1)
                            cb.onChanged = function(rgb)
                                layer.fillTintR = rgb[1]
                                layer.fillTintG = rgb[2]
                                layer.fillTintB = rgb[3]
                                if ns.SpellFX and selectedSpellID then
                                    pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end)
                                end
                                RefreshInlinePreview(); pcall(ns.ScanAuras)
                            end
                            -- Boutons Reset / Supprimer (style coherent avec mode 3D)
                            local rB=CreateFrame("Button",nil,lf2,"BackdropTemplate"); rB:SetSize(90,20); rB:SetPoint("BOTTOMLEFT",5,5)
                            rB:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                            rB:SetBackdropColor(0.05,0.05,0.06,0.9); rB:SetBackdropBorderColor(0.78,0.62,0.30,0.55)
                            local rT=rB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(rT,FONT,9); rT:SetAllPoints(); rT:SetJustifyH("CENTER"); rT:SetText(L["AURASMENU_EFFECTS_RESET"]); rT:SetTextColor(0.78,0.62,0.30)
                            rB:SetScript("OnClick",function()
                                layer.fillAlpha=0.7; layer.fillScroll=nil
                                layer.fillTintR=1; layer.fillTintG=1; layer.fillTintB=1
                                pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end)
                                RefreshInlinePreview(); RefreshLayers(); pcall(ns.ScanAuras)
                            end)
                            local dB=CreateFrame("Button",nil,lf2,"BackdropTemplate"); dB:SetSize(90,20); dB:SetPoint("LEFT",rB,"RIGHT",4,0)
                            dB:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                            dB:SetBackdropColor(0.10,0.04,0.04,0.9); dB:SetBackdropBorderColor(0.65,0.45,0.20,0.55)
                            local dT=dB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(dT,FONT,9); dT:SetAllPoints(); dT:SetJustifyH("CENTER"); dT:SetText(L["AURASMENU_EFFECTS_DELETE"]); dT:SetTextColor(0.85,0.65,0.30)
                            dB:SetScript("OnClick",function() ns.SpellFX:RemoveLayer(selectedSpellID,activeView,activeTab,li); selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers()
                                pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end) end)
                            cy=cy+LH2+8
                        else
                            -- Sliders pour Bar 3D (PlayerModel mode Fond)
                            local LH2 = 290; lf2:SetHeight(LH2)
                            MkSl(L["AURASMENU_EFFECTS_SCALE"],0.10,5.00,0.05,0,0,"scale"); MkSl(L["AURASMENU_EFFECTS_ROTATION"],0,360,5,1,0,"rotation"); MkSl(L["AURASMENU_EQUIPMENT_OPACITY"],0,1,0.05,2,0,"alpha")
                            MkSl(L["AURASMENU_EFFECTS_FX_WIDTH"],5,400,1,0,1,"fxW"); MkSl(L["AURASMENU_EFFECTS_FX_HEIGHT"],2,100,1,1,1,"fxH"); MkSl(L["AURASMENU_EFFECTS_Z_DEPTH"],-30,30,0.5,2,1,"z")
                            MkSl(L["AURASMENU_EFFECTS_X_MODEL"],-30,30,0.5,0,2,"x"); MkSl(L["AURASMENU_EFFECTS_Y_MODEL"],-30,30,0.5,1,2,"y")
                            -- Buttons inside card
                            local rB=CreateFrame("Button",nil,lf2,"BackdropTemplate"); rB:SetSize(90,20); rB:SetPoint("BOTTOMLEFT",5,5)
                            rB:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                            rB:SetBackdropColor(0.05,0.05,0.06,0.9); rB:SetBackdropBorderColor(0.78,0.62,0.30,0.55)
                            local rT=rB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(rT,FONT,9); rT:SetAllPoints(); rT:SetJustifyH("CENTER"); rT:SetText(L["AURASMENU_EFFECTS_RESET"]); rT:SetTextColor(0.78,0.62,0.30)
                            rB:SetScript("OnClick",function() layer.x=0;layer.y=0;layer.z=0;layer.scale=1;layer.rotation=0;layer.alpha=0.5;layer.posX=0;layer.posY=0;layer.fxW=nil;layer.fxH=nil
                                pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end); RefreshInlinePreview(); RefreshLayers(); pcall(ns.ScanAuras) end)
                            local dB=CreateFrame("Button",nil,lf2,"BackdropTemplate"); dB:SetSize(90,20); dB:SetPoint("LEFT",rB,"RIGHT",4,0)
                            dB:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                            dB:SetBackdropColor(0.10,0.04,0.04,0.9); dB:SetBackdropBorderColor(0.65,0.45,0.20,0.55)
                            local dT=dB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(dT,FONT,9); dT:SetAllPoints(); dT:SetJustifyH("CENTER"); dT:SetText(L["AURASMENU_EFFECTS_DELETE"]); dT:SetTextColor(0.85,0.65,0.30)
                            dB:SetScript("OnClick",function() ns.SpellFX:RemoveLayer(selectedSpellID,activeView,activeTab,li); selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers()
                                pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end) end)
                            cy=cy+LH2+8
                        end
                    else
                        local LH2 = 330; lf2:SetHeight(LH2)
                        MkSl(L["AURASMENU_EFFECTS_SCALE"],0.10,5.00,0.05,0,0,"scale"); MkSl(L["AURASMENU_EFFECTS_ROTATION"],0,360,5,1,0,"rotation"); MkSl(L["AURASMENU_EQUIPMENT_OPACITY"],0,1,0.05,2,0,"alpha")
                        MkSl(L["AURASMENU_EFFECTS_FX_WIDTH"],5,400,1,0,1,"fxW"); MkSl(L["AURASMENU_EFFECTS_FX_HEIGHT"],2,400,1,1,1,"fxH"); MkSl(L["AURASMENU_EFFECTS_Z_DEPTH"],-30,30,0.5,2,1,"z")
                        MkSl(L["SETTINGS_OFFSET_X"],-30,30,0.5,0,2,"x"); MkSl(L["SETTINGS_OFFSET_Y"],-30,30,0.5,1,2,"y"); MkSl(L["SETTINGS_POSITION_X"],-800,800,1,2,2,"posX")
                        MkSl(L["SETTINGS_POSITION_Y"],-800,800,1,0,3,"posY")
                        -- Buttons inside card
                        local rB=CreateFrame("Button",nil,lf2,"BackdropTemplate"); rB:SetSize(90,20); rB:SetPoint("BOTTOMLEFT",5,5)
                        rB:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                        rB:SetBackdropColor(0.05,0.05,0.06,0.9); rB:SetBackdropBorderColor(0.78,0.62,0.30,0.55)
                        local rT=rB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(rT,FONT,9); rT:SetAllPoints(); rT:SetJustifyH("CENTER"); rT:SetText(L["AURASMENU_EFFECTS_RESET"]); rT:SetTextColor(0.78,0.62,0.30)
                        rB:SetScript("OnClick",function() layer.x=0;layer.y=0;layer.z=0;layer.scale=1;layer.rotation=0;layer.alpha=0.5;layer.posX=0;layer.posY=0;layer.fxW=nil;layer.fxH=nil
                            pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end); RefreshInlinePreview(); RefreshLayers(); pcall(ns.ScanAuras) end)
                        local dB=CreateFrame("Button",nil,lf2,"BackdropTemplate"); dB:SetSize(90,20); dB:SetPoint("LEFT",rB,"RIGHT",4,0)
                        dB:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                        dB:SetBackdropColor(0.10,0.04,0.04,0.9); dB:SetBackdropBorderColor(0.65,0.45,0.20,0.55)
                        local dT=dB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(dT,FONT,9); dT:SetAllPoints(); dT:SetJustifyH("CENTER"); dT:SetText(L["AURASMENU_EFFECTS_DELETE"]); dT:SetTextColor(0.85,0.65,0.30)
                        dB:SetScript("OnClick",function() ns.SpellFX:RemoveLayer(selectedSpellID,activeView,activeTab,li); selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers()
                            pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end) end)
                        cy=cy+LH2+8
                    end
                end
            end
            local addB=CreateFrame("Button",nil,layerChild,"BackdropTemplate"); addB:SetHeight(28)
            addB:SetPoint("TOPLEFT",5,-cy); addB:SetPoint("TOPRIGHT",-5,-cy)
            addB:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}); addB:SetBackdropBorderColor(Theme.accent[1],Theme.accent[2],Theme.accent[3],0.3)
            local addT=addB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(addT,FONT,11); addT:SetAllPoints(); addT:SetJustifyH("CENTER"); addT:SetTextColor(unpack(Theme.accent)); addT:SetText(L["AURASMENU_EFFECTS_ADD_LAYER"])
            addB:SetScript("OnClick",function() if selectedSpellID and ns.SpellFX then ns.SpellFX:AddLayer(selectedSpellID,activeView,activeTab); selectedLayerIdx=#layers+1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers() end end)
            -- OVERLAY ANIME section (bar tab only)
            if activeTab == "bar" and selectedSpellID then
                cy = cy + 38
                local ovH = layerChild:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(ovH,FONT,10)
                ovH:SetPoint("TOPLEFT",8,-cy); ovH:SetTextColor(0.4,0.75,0.5); ovH:SetText(L["AURASMENU_EFFECTS_OVERLAY_ANIM"])
                cy = cy + 18
                local si = spells and spells[selectedSpellID]
                -- Texture dropdown
                local texLbl=layerChild:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(texLbl,FONT,9)
                texLbl:SetPoint("TOPLEFT",8,-cy); texLbl:SetTextColor(unpack(Theme.textDim)); texLbl:SetText(L["AURASMENU_EFFECTS_TEXTURE_LABEL"])
                local texNames = {L["AURASMENU_EFFECTS_NONE_MASC"]}; local texPaths = {""}
                for _,bt in ipairs(ns.BAR_TEXTURES) do texNames[#texNames+1]=bt.text; texPaths[#texPaths+1]=ns.ResolveLSMTexture and ns.ResolveLSMTexture(bt) or bt.path or "" end
                local curTex = si and si.overlayTex or ""
                local curIdx = 1
                for i,p in ipairs(texPaths) do if p == curTex then curIdx = i; break end end
                local texBtn=CreateFrame("Button",nil,layerChild,"BackdropTemplate"); texBtn:SetSize(200,18); texBtn:SetPoint("TOPLEFT",70,-cy)
                texBtn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                texBtn:SetBackdropColor(0.06,0.06,0.08,1); texBtn:SetBackdropBorderColor(0.15,0.15,0.20,1)
                local texTx=texBtn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(texTx,FONT,9); texTx:SetAllPoints(); texTx:SetJustifyH("LEFT")
                texTx:SetTextColor(unpack(Theme.textNormal)); texTx:SetText("  "..texNames[curIdx])
                texBtn:SetScript("OnClick",function()
                    curIdx = curIdx % #texNames + 1
                    texTx:SetText("  "..texNames[curIdx])
                    if si then si.overlayTex = texPaths[curIdx] end
                    if ns.SpellFX and selectedSpellID then pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end) end
                    pcall(ns.ScanAuras)
                end)
                cy = cy + 22
                -- Speed + Alpha sliders
                local slW2 = math.max(80, math.floor((layerChild:GetWidth()-20)/2))
                local sSpd=SW.CreateSlider(layerChild,L["AURASMENU_EFFECTS_SPEED"],0.05,3.0,0.05,slW2); sSpd:SetPoint("TOPLEFT",5,-cy)
                sSpd:SetValue(si and si.overlaySpeed or 0.5)
                sSpd.onChanged=function(v) if si then si.overlaySpeed=v end; if ns.SpellFX and selectedSpellID then pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end) end; pcall(ns.ScanAuras) end
                local sAlp=SW.CreateSlider(layerChild,L["AURASMENU_EFFECTS_OVERLAY_OPACITY"],0,1,0.05,slW2); sAlp:SetPoint("TOPLEFT",slW2+10,-cy)
                sAlp:SetValue(si and si.overlayAlpha or 0.3)
                sAlp.onChanged=function(v) if si then si.overlayAlpha=v end; if ns.SpellFX and selectedSpellID then pcall(function() ns.SpellFX:SyncToSpell(selectedSpellID) end) end; pcall(ns.ScanAuras) end
                cy = cy + 55
            end
            layerChild:SetHeight(cy+35)
        end
        RefreshLayers()
        RefreshInlinePreview()
        -- Ensure WG slots are loaded
        pcall(function() if ns.Providers and ns.Providers.Refresh then ns.Providers:Refresh() end end)
        local allEntries={}
        local seenIDs={}

        -- Set des spellID/itemID des slots Equipment actifs, pour detecter les entrées WG
        -- meme si le flag source="equipment" a été perdu dans db.spells
        local wgSidSet = {}
        local wgSlotBySid = {}  -- [sid] = slot (pour récupérer tex/name plus tard)
        if ns.Providers and ns.Providers.GetAllSlots then
            for _, slot in ipairs(ns.Providers:GetAllSlots()) do
                local sid = slot.spellID or slot.itemID or 0
                if sid > 0 then
                    wgSidSet[sid] = true
                    wgSlotBySid[sid] = slot
                end
            end
        end

        if spells then for sid,info in pairs(spells) do if info.enabled and not seenIDs[sid] then
            seenIDs[sid]=true
            local isWG = (info.source == "equipment") or (wgSidSet[sid] == true)
            if isWG and info.source ~= "equipment" then info.source = "equipment" end -- auto-heal DB
            local name = info.name or (isWG and wgSlotBySid[sid] and ns.Providers:GetSlotName(wgSlotBySid[sid])) or tostring(sid)
            local tex = isWG and wgSlotBySid[sid] and ns.Providers:GetSlotTexture(wgSlotBySid[sid]) or nil
            allEntries[#allEntries+1]={id=sid, info=info, name=name, isWG=isWG, tex=tex}
        end end end
        if ns.Providers and ns.Providers.GetAllSlots then
            for _,slot in ipairs(ns.Providers:GetAllSlots()) do
                local sd=ns.db and ns.db.equipmentSlots and ns.db.equipmentSlots[slot.key]
                if not sd or sd.enabled~=false then
                    local sid=slot.spellID or slot.itemID or 0; if sid>0 and not seenIDs[sid] then
                        seenIDs[sid]=true
                        if spells and not spells[sid] then
                            spells[sid]=ns.DeepCopy(ns.SpellDefaults); spells[sid].name=ns.Providers:GetSlotName(slot)
                            spells[sid].color={ns.barColor[1],ns.barColor[2],ns.barColor[3]}; spells[sid].priority=sid; spells[sid].source="equipment"
                        end
                        allEntries[#allEntries+1]={id=sid,info=spells[sid],name=ns.Providers:GetSlotName(slot),isWG=true,tex=ns.Providers:GetSlotTexture(slot)}
                    end end end end
        -- FoldAccentsLower : strcmputf8i seul classait mal les accents sur ce client
        table.sort(allEntries,function(a,b) return _addon.FoldAccentsLower(a.name or"") < _addon.FoldAccentsLower(b.name or"") end)
        local spellRowBgs = {}
        for _,entry in ipairs(allEntries) do
            local sr=CreateFrame("Button",nil,lf); sr:SetSize(LEFT_W,26); sr:SetPoint("TOPLEFT",0,-ly)
            local sBg=sr:CreateTexture(nil,"BACKGROUND"); sBg:SetAllPoints()
            if selectedSpellID == entry.id then sBg:SetColorTexture(unpack(ROW_SELECTED_BG)) else sBg:SetColorTexture(0,0,0,0) end
            spellRowBgs[#spellRowBgs+1] = {bg=sBg, id=entry.id}
            local sI=sr:CreateTexture(nil,"ARTWORK"); sI:SetSize(22,22); sI:SetPoint("LEFT",10,0); sI:SetTexCoord(TC,1-TC,TC,1-TC)
            if entry.tex then pcall(function() sI:SetTexture(entry.tex) end)
            else pcall(function() local t=C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id); if t then sI:SetTexture(t) end end) end
            local sN=sr:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(sN,FONT,10); sN:SetPoint("LEFT",sI,"RIGHT",5,0)
            sN:SetTextColor(unpack(Theme.textNormal)); sN:SetText(entry.name); sN:SetWidth(LEFT_W-90)
            -- Badge [E] pour les sorts Equipment (Wargear)
            local bx=5
            if entry.isWG then
                local wBadge=CreateFrame("Frame",nil,sr); wBadge:SetSize(14,14); wBadge:SetPoint("RIGHT",-bx,0)
                local wBg=wBadge:CreateTexture(nil,"BACKGROUND"); wBg:SetAllPoints(); wBg:SetColorTexture(0.15,0.10,0.05,0.6)
                local wTx=wBadge:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(wTx,FONT,8,"OUTLINE"); wTx:SetAllPoints(); wTx:SetJustifyH("CENTER")
                wTx:SetText("E"); wTx:SetTextColor(0.80,0.55,0.20); bx=bx+16
            end
            sr:SetScript("OnEnter",function() sBg:SetColorTexture(1,1,1,0.03); sN:SetTextColor(1,1,1) end)
            sr:SetScript("OnLeave",function() if selectedSpellID==entry.id then sBg:SetColorTexture(unpack(ROW_SELECTED_BG)) else sBg:SetColorTexture(0,0,0,0) end; sN:SetTextColor(unpack(Theme.textNormal)) end)
            sr:SetScript("OnClick",function()
                for _,r in ipairs(spellRowBgs) do r.bg:SetColorTexture(0,0,0,0) end
                sBg:SetColorTexture(unpack(ROW_SELECTED_BG))
                selectedSpellID=entry.id; ns._selectedFx3dSpell=entry.id
                ns._selectedFx3dIsWG = entry.isWG or false
                if entry.tex then pcall(function() rfIco:SetTexture(entry.tex) end) else pcall(function() rfIco:SetTexture(C_Spell.GetSpellTexture(entry.id)) end) end
                rfNm:SetText(entry.name)
                -- WG items: force ICONE tab + force activeView=equipment (la seule vue visible pour eux)
                if entry.isWG then
                    activeTab="icon"; ns._selectedFx3dTab="icon"
                    activeView="equipment"
                end
                for ti,tb in ipairs(tabBtns) do
                    if entry.isWG and tb.key ~= "icon" then
                        tb.btn:Hide()
                    else
                        tb.btn:Show()
                        -- Rename tab for WG items
                        if tb.key == "icon" then
                            tb.tx:SetText(entry.isWG and L["AURASMENU_EFFECTS_TAB_ICON_WG"] or L["AURASMENU_EFFECTS_TAB_ICON"])
                        end
                    end
                end
                SetActiveOne(tabBtns, activeTab)
                -- Filtrage des vues : WG -> seule [E] EQUIPMENT visible, sort normal -> tout sauf [E]
                local visibleVKeys = {}
                for vi,vk in ipairs(viewKeys) do
                    local visible
                    if entry.isWG then
                        visible = (vk == "equipment")
                    else
                        visible = (vk ~= "equipment")
                    end
                    if visible then
                        viewFrames[vi]:Show()
                        table.insert(visibleVKeys, vk)
                    else
                        viewFrames[vi]:Hide()
                    end
                end
                -- Si la vue active est devenue incompatible avec ce sort, bascule
                local found = false
                for _,vk in ipairs(visibleVKeys) do if vk == activeView then found = true; break end end
                if not found and visibleVKeys[1] then
                    activeView = visibleVKeys[1]
                end
                RepositionViewTabs()
                SetActiveOne(viewBtns, activeView)
                if RefreshTabVisibility then RefreshTabVisibility() end
                -- Switch entre WG (icones) et sort (rien de special)
                pcall(function()
                    if entry.isWG then
                        -- Hide render containers (WG = on affiche les icones via Providers)
                        for _,rk in ipairs({"iconlist","freebars","circlebars","icons"}) do
                            local gfx = ns.renderFrames and ns.renderFrames[rk]
                            if gfx and gfx.container then gfx.container:SetAlpha(0) end
                        end
                        -- Affiche les icônes WG avec 3D
                        ns._equipmentPreview = true
                        ns._equipment3DPreview = true
                        if ns.Providers then ns.Providers:Refresh() end
                    else
                        ns._equipmentPreview = false
                        ns._equipment3DPreview = false
                    end
                    -- Mode preview (fake bar) : skip pour les WG (pas de FX bar)
                    if not entry.isWG then
                        ns._previewBars = true
                        ns._previewMode = activeView == "all" and "all" or activeView
                    else
                        ns._previewBars = false
                        ns._previewMode = nil
                    end
                    -- Force la visibilite du container (override combatOnly hors combat)
                    if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
                    pcall(ns.ScanAuras)
                    -- Re-scan differe : laisse le temps au .m2 du nouveau sort de charger en GPU
                    C_Timer.After(0.15, function() pcall(ns.ScanAuras) end)
                end)
                selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers() end)
            ly=ly+27
        end
        -- Restauration auto du sort sélectionné depuis la session précédente
        if selectedSpellID then
            for _, entry in ipairs(allEntries) do
                if entry.id == selectedSpellID then
                    if entry.tex then pcall(function() rfIco:SetTexture(entry.tex) end)
                    else pcall(function() rfIco:SetTexture(C_Spell.GetSpellTexture(entry.id)) end) end
                    rfNm:SetText(entry.name)
                    ns._selectedFx3dIsWG = entry.isWG or false
                    -- WG: force icon tab + force activeView=equipment (la seule visible pour eux)
                    if entry.isWG then
                        activeTab="icon"; ns._selectedFx3dTab="icon"
                        activeView="equipment"
                    end
                    -- Anim tabs : show/hide selon WG, rename si necessaire
                    for ti, tb in ipairs(tabBtns) do
                        if entry.isWG and tb.key ~= "icon" then tb.btn:Hide()
                        else tb.btn:Show()
                            if tb.key == "icon" then tb.tx:SetText(entry.isWG and L["AURASMENU_EFFECTS_TAB_ICON_WG"] or L["AURASMENU_EFFECTS_TAB_ICON"]) end
                        end
                    end
                    -- Reset systematique de TOUS les tabBtns (visibles ou non)
                    SetActiveOne(tabBtns, activeTab)
                    -- View tabs : show/hide + reset visuel via helper
                    for vi,vf in ipairs(viewFrames) do
                        if entry.isWG then
                            vf:Show()  -- on garde [E] visible pour WG (et seulement [E])
                            -- vue equipment seule : on hide les autres
                            if viewKeys[vi] ~= "equipment" then vf:Hide() end
                        else
                            -- Pour un sort normal : tout sauf [E]
                            if viewKeys[vi] == "equipment" then vf:Hide() else vf:Show() end
                        end
                    end
                    -- Recompacte les onglets visibles a gauche (evite trous)
                    RepositionViewTabs()
                    SetActiveOne(viewBtns, activeView)
                    -- Switch WG/sort
                    pcall(function()
                        if entry.isWG then
                            for _,rk in ipairs({"iconlist","freebars","circlebars","icons"}) do
                                local gfx = ns.renderFrames and ns.renderFrames[rk]
                                if gfx and gfx.container then gfx.container:SetAlpha(0) end
                            end
                            ns._equipmentPreview = true
                            ns._equipment3DPreview = true
                        end
                        pcall(ns.ScanAuras)
                    end)
                    RefreshLayers(); RefreshInlinePreview()
                    break
                end
            end
        end

        -- Bottom: only Vider sort (auto-save on close, no need for Valider/Annuler)
        local btnDefs = {
            {label=L["AURASMENU_EFFECTS_CLEAR_SPELL"],  w=150, bg={0.18,0.14,0.06}, bdr={0.6,0.5,0.3,0.5}, tx={1.0,0.75,0.4}},
        }
        local actBtns = {}
        for bi, bd in ipairs(btnDefs) do
            local b=CreateFrame("Button",nil,rf,"BackdropTemplate"); b:SetSize(bd.w,24)
            b:SetPoint("BOTTOMRIGHT",-8,8)
            b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
            b:SetBackdropColor(bd.bg[1],bd.bg[2],bd.bg[3],0.9); b:SetBackdropBorderColor(bd.bdr[1],bd.bdr[2],bd.bdr[3],bd.bdr[4])
            local t=b:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(t,FONT,9); t:SetAllPoints(); t:SetJustifyH("CENTER"); t:SetTextColor(bd.tx[1],bd.tx[2],bd.tx[3]); t:SetText(bd.label)
            b:SetScript("OnEnter",function() b:SetBackdropBorderColor(bd.tx[1],bd.tx[2],bd.tx[3],0.8) end)
            b:SetScript("OnLeave",function() b:SetBackdropBorderColor(bd.bdr[1],bd.bdr[2],bd.bdr[3],bd.bdr[4]) end)
            actBtns[bi]=b
        end
        actBtns[1]:SetScript("OnClick",function()
            if not selectedSpellID then return end
            local si = spells and spells[selectedSpellID]
            if si then si.barModelID=0; si.iconModelID=0; si.sparkModelID=0
                si.fx3d = nil end
            selectedLayerIdx=1; ns._selectedFx3dLayerIdx=selectedLayerIdx; RefreshInlinePreview(); RefreshLayers(); pcall(ns.ScanAuras)
            pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end)
        end)

        -- Adapte la hauteur pour tenir dans la zone visible du scroll frame
        local sfH = (panel and panel._scrollFrame and panel._scrollFrame:GetHeight()) or 668
        local visH = math.max(560, sfH - 60)   -- 50 top offset + 10 bottom padding
        fxCont:SetHeight(visH); p:SetHeight(visH + 60)
    end
    cbFx.onChanged=function(v)
        if ns.db then ns.db.effectsEnabled=v end
        -- Si on desactive, hide explicitement les FX 3D actifs (sinon ils restent visibles "fantomes")
        if not v then
            pcall(function()
                if ns.HideAllFX3D then ns.HideAllFX3D() end
            end)
        end
        pcall(function() ns.ScanAuras() end)
        BuildFx()
    end
    BuildFx()
    p:SetScript("OnShow", function()
        BuildFx()
        -- Active le mode preview : fake bar dans la vue active si un sort est selectionne
        if selectedSpellID then
            ns._previewBars = true
            ns._previewMode = activeView == "all" and "all" or activeView
            if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
            pcall(function() ns.ScanAuras() end)
        end
    end)
    p:SetScript("OnHide", function()
        -- Desactive le mode preview a la fermeture (pas de fake bar qui traine en jeu)
        ns._previewBars = false
        ns._previewMode = nil
        -- Restaure les fades normaux (combatOnly redevient effectif)
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
    end)
end

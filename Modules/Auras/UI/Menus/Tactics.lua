-- AishUIAura/UI/Menus/Tactics.lua
-- Menu Tactics : liste des sorts découverts avec badges destination, glow, couleur
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.SettingsPanel = ns.SettingsPanel or {}

local TC = 0.07

------------------------------------------------------------------------
-- GLOW POPUP (floating, draggable)
-- Port depuis AishUIAura — manquant dans Aishaddon, stocké en ns._glowPopup.
------------------------------------------------------------------------
function ns.OpenGlowPopup(sid, info)
    local FONT  = ns.Media and ns.Media.font or "Fonts\\FRIZQT__.TTF"
    local Theme = ns.THEME or {}
    local SW    = ns.SharedWidgets
    if not (SW and SW.CreateDropdown) then return end

    if not ns._glowPopup then
        local gp = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        gp:SetSize(280, 440); gp:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        gp:SetFrameStrata("FULLSCREEN_DIALOG"); gp:SetMovable(true); gp:SetClampedToScreen(true); gp:SetResizable(true)
        if gp.SetResizeBounds then gp:SetResizeBounds(240, 400, 420, 580) end
        gp:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
        gp:SetBackdropColor(0.07, 0.07, 0.09, 0.97); gp:Hide()

        local h = CreateFrame("Frame", nil, gp); h:SetHeight(24); h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT"); h:EnableMouse(true)
        h:SetScript("OnMouseDown", function(_, b) if b == "LeftButton" then gp:StartMoving() end end)
        h:SetScript("OnMouseUp", function() gp:StopMovingOrSizing() end)
        local hBg = h:CreateTexture(nil,"BACKGROUND"); hBg:SetAllPoints(); hBg:SetColorTexture(0.10,0.10,0.12,1)
        gp._title = h:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(gp._title,FONT,10); gp._title:SetPoint("LEFT",8,0)
        if Theme.textDim then gp._title:SetTextColor(unpack(Theme.textDim)) end
        local xB = CreateFrame("Button",nil,h); xB:SetSize(24,24); xB:SetPoint("TOPRIGHT")
        local xT = xB:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(xT,FONT,12); xT:SetAllPoints(); xT:SetText("x")
        if Theme.textDim then xT:SetTextColor(unpack(Theme.textDim)) end
        xB:SetScript("OnClick", function() gp:Hide() end)
        xB:SetScript("OnEnter", function() xT:SetTextColor(1,0.3,0.3) end)
        xB:SetScript("OnLeave", function() if Theme.textDim then xT:SetTextColor(unpack(Theme.textDim)) end end)

        local sec = gp:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(sec,FONT,11); sec:SetPoint("TOP",0,-32)
        if Theme.accent then sec:SetTextColor(unpack(Theme.accent)) end
        sec:SetText("GLOW (EFFET DE SURBRILLANCE)")

        local prevF = CreateFrame("Frame",nil,gp); prevF:SetSize(48,48); prevF:SetPoint("TOP",0,-50)
        prevF:SetFrameLevel(gp:GetFrameLevel()+3)
        prevF:CreateTexture(nil,"BACKGROUND"):SetColorTexture(0,0,0,0.5)
        gp._iconTex = prevF:CreateTexture(nil,"ARTWORK"); gp._iconTex:SetAllPoints(); gp._iconTex:SetTexCoord(TC,1-TC,TC,1-TC)
        gp._prevFrame = prevF

        local wPad = 16
        gp._glowDD   = SW.CreateDropdown(gp,"Type de glow (boucle)",{},248); gp._glowDD:SetPoint("TOPLEFT",wPad,-110)
        gp._entryDD  = SW.CreateDropdown(gp,"Animation d'entree",{},248);    gp._entryDD:SetPoint("TOPLEFT",wPad,-158)

        gp._testProcBtn = CreateFrame("Button",nil,gp,"BackdropTemplate"); gp._testProcBtn:SetSize(120,20); gp._testProcBtn:SetPoint("TOPLEFT",wPad,-204)
        gp._testProcBtn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
        gp._testProcBtn:SetBackdropColor(0.20,0.15,0.08,0.9); gp._testProcBtn:SetBackdropBorderColor(0.80,0.55,0.20,0.7)
        local tpT = gp._testProcBtn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(tpT,FONT,9); tpT:SetAllPoints(); tpT:SetJustifyH("CENTER")
        tpT:SetTextColor(1.00,0.85,0.39); tpT:SetText("v Tester Proc")
        gp._testProcBtn:SetScript("OnEnter",function(s) s:SetBackdropColor(0.30,0.22,0.10,1) end)
        gp._testProcBtn:SetScript("OnLeave",function(s) s:SetBackdropColor(0.20,0.15,0.08,0.9) end)

        gp._procScaleSlider = SW.CreateSlider(gp,"Taille proc",0.1,3.0,0.05,248); gp._procScaleSlider:SetPoint("TOPLEFT",wPad,-228)
        gp._colorBtn        = SW.CreateColorButton(gp,"Couleur glow",248);         gp._colorBtn:SetPoint("TOPLEFT",wPad,-290)
        gp._opacSlider      = SW.CreateSlider(gp,"Opacite",0,1,0.05,248);          gp._opacSlider:SetPoint("TOPLEFT",wPad,-320)
        gp._sizeSlider      = SW.CreateSlider(gp,"Taille glow",0.1,3.0,0.05,248); gp._sizeSlider:SetPoint("TOPLEFT",wPad,-376)

        local gpGrip = CreateFrame("Button",nil,gp); gpGrip:SetSize(12,12); gpGrip:SetPoint("BOTTOMRIGHT",-2,2)
        gpGrip:SetFrameLevel(gp:GetFrameLevel()+20)
        gpGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        gpGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        gpGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        gpGrip:SetScript("OnMouseDown", function() gp:StartSizing("BOTTOMRIGHT") end)
        gpGrip:SetScript("OnMouseUp", function() gp:StopMovingOrSizing() end)
        ns._glowPopup = gp
    end

    local gp = ns._glowPopup
    local classBC = ns.barColor or {0.5,0.5,0.5}
    gp:SetBackdropBorderColor(classBC[1], classBC[2], classBC[3], 0.9)
    gp._title:SetText("Glow — "..(info.name or tostring(sid)))
    pcall(function() local t=C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid); if t then gp._iconTex:SetTexture(t) end end)

    local function RefreshGlowPreview()
        pcall(function()
            if ns.HideGlow then ns.HideGlow(gp._prevFrame) end
            local idx=info.glowIdx or 2; local gc=info.glowColor or info.color or ns.barColor
            if ns.ShowGlow and idx>1 then ns.ShowGlow(gp._prevFrame,idx,gc,info.glowAlpha or 0.7,info.glowScale or 1.0) end
        end)
    end

    local go={}; for idx,def in ipairs(ns.GLOW_DEFS or {}) do if not def.isProcStart then go[#go+1]={value=idx,text=def.name} end end
    gp._glowDD:SetOptions(go); gp._glowDD:SetValue(info.glowIdx or 2)
    gp._glowDD.onChanged=function(v) info.glowIdx=v; RefreshGlowPreview(); pcall(ns.ScanAuras) end

    local po={{value=1,text="Aucun"}}; for idx,def in ipairs(ns.GLOW_DEFS or {}) do if def.isProcStart then po[#po+1]={value=idx,text=def.name} end end
    gp._entryDD:SetOptions(po); gp._entryDD:SetValue(info.procGlowIdx or 1)
    gp._entryDD.onChanged=function(v) info.procGlowIdx=v; gp._testProcBtn:SetShown(v and v>1); gp._procScaleSlider:SetShown(v and v>1) end

    local procVisible = info.procGlowIdx and info.procGlowIdx > 1
    gp._testProcBtn:SetShown(procVisible); gp._procScaleSlider:SetShown(procVisible)
    gp._procScaleSlider:SetValue(info.procGlowScale or 1.0); gp._procScaleSlider.onChanged=function(v) info.procGlowScale=v end
    gp._testProcBtn:SetScript("OnClick",function()
        local pi=info.procGlowIdx; if not pi or pi<1 then return end
        if ns.PlayProcStart then ns.PlayProcStart(gp._prevFrame,pi,info.glowColor or info.color or ns.barColor,info.procGlowScale or 1.0) end
    end)

    local rc = info.glowColor or info.color or ns.barColor
    gp._colorBtn:SetColor(rc[1],rc[2],rc[3]); gp._colorBtn.onChanged=function(c) info.glowColor=c; RefreshGlowPreview(); pcall(ns.ScanAuras) end
    gp._opacSlider:SetValue(info.glowAlpha or 0.7); gp._opacSlider.onChanged=function(v) info.glowAlpha=v; RefreshGlowPreview() end
    gp._sizeSlider:SetValue(info.glowScale or 1.0); gp._sizeSlider.onChanged=function(v) info.glowScale=v; RefreshGlowPreview() end
    gp:Show(); C_Timer.After(0.05, RefreshGlowPreview)
end

------------------------------------------------------------------------
-- SPELL ROW (one row per discovered spell)
------------------------------------------------------------------------
local function CreateSpellRow(par,sid,info,y,W,onChg)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font
    local sc = info.color or ns.barColor
    local row = CreateFrame("Frame",nil,par); row:SetSize(W,28); row:SetPoint("TOPLEFT",0,-y)
    local rBg = row:CreateTexture(nil,"BACKGROUND"); rBg:SetAllPoints(); rBg:SetColorTexture(0,0,0,0)

    local rx = 4
    -- Checkbox (activation du sort)
    local cb = CreateFrame("Button",nil,row); cb:SetSize(14,14); cb:SetPoint("LEFT",rx,0)
    local cbBg = cb:CreateTexture(nil,"ARTWORK"); cbBg:SetAllPoints()
    local cbChk = cb:CreateTexture(nil,"OVERLAY"); cbChk:SetSize(10,10); cbChk:SetPoint("CENTER")
    cbChk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); cbChk:Hide()
    local function RCB()
        if info.enabled then cbBg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1); cbChk:Show()
        else cbBg:SetColorTexture(0.10,0.10,0.14,1); cbChk:Hide() end
    end; RCB()
    cb:SetScript("OnClick",function() info.enabled=not info.enabled; RCB(); onChg() end)
    rx = rx + 18

    -- Icône du sort (avec tooltip au survol)
    local icoF = CreateFrame("Frame",nil,row); icoF:SetSize(22,22); icoF:SetPoint("LEFT",rx,0)
    local ico = icoF:CreateTexture(nil,"ARTWORK"); ico:SetAllPoints(); ico:SetTexCoord(TC,1-TC,TC,1-TC)
    pcall(function() local t=C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid); if t then ico:SetTexture(t) end end)
    rx = rx + 26

    -- Nom du sort
    local nm = row:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(nm,FONT,11)
    nm:SetPoint("LEFT",rx,0); nm:SetPoint("RIGHT",row,"RIGHT",-205,0)
    nm:SetJustifyH("LEFT"); nm:SetWordWrap(false)
    nm:SetTextColor(unpack(Theme.textNormal))
    nm:SetText((info.name or tostring(sid)).." |cff3a3a3a("..sid..")|r")

    ------------------------------------------------------------------
    -- CÔTÉ DROIT : zones ancrées depuis la droite vers la gauche
    -- Ordre visuel : [DESTINATIONS] | [STYLE]
    -- Où STYLE = glow(type) + desat + color swatch
    ------------------------------------------------------------------

    -- Color swatch (extrême droite)
    local sw1 = CreateFrame("Button",nil,row); sw1:SetSize(16,16); sw1:SetPoint("RIGHT",-4,0)
    local sw1T = sw1:CreateTexture(nil,"ARTWORK"); sw1T:SetAllPoints(); sw1T:SetColorTexture(sc[1],sc[2],sc[3])
    local sw1B = sw1:CreateTexture(nil,"BORDER"); sw1B:SetPoint("TOPLEFT",-1,1); sw1B:SetPoint("BOTTOMRIGHT",1,-1)
    sw1B:SetColorTexture(0.18,0.16,0.14,0.7)
    sw1:SetScript("OnClick",function() ColorPickerFrame:SetupColorPickerAndShow({r=sc[1],g=sc[2],b=sc[3],
        swatchFunc=function() local r,g,b=ColorPickerFrame:GetColorRGB(); info.color={r,g,b}; info._colorDefault=false; sw1T:SetColorTexture(r,g,b); onChg() end,
        cancelFunc=function(pp) info.color={pp.r,pp.g,pp.b}; info._colorDefault=false; sw1T:SetColorTexture(pp.r,pp.g,pp.b); onChg() end}) end)
    sw1:SetScript("OnEnter",function() GameTooltip:SetOwner(sw1,"ANCHOR_TOP"); GameTooltip:SetText("Couleur de la barre",1,1,1); GameTooltip:Show() end)
    sw1:SetScript("OnLeave",function() GameTooltip:Hide() end)

    -- Bouton desat (icône ability_creature_cursed_04, pas de lettre)
    local dBtn = CreateFrame("Button",nil,row); dBtn:SetSize(16,16); dBtn:SetPoint("RIGHT",sw1,"LEFT",-4,0)
    local dBg = dBtn:CreateTexture(nil,"BACKGROUND"); dBg:SetAllPoints()
    local dIco = dBtn:CreateTexture(nil,"OVERLAY"); dIco:SetAllPoints(); dIco:SetTexCoord(TC,1-TC,TC,1-TC)
    pcall(function() dIco:SetTexture("Interface\\Icons\\ability_creature_cursed_04") end)

    -- Bouton glow fusionné : affiche le type + on/off. Clic = toggle, shift/right click = picker
    -- Remplace l'ancien couple (gBtn toggle) + (gtBtn type) qui était redondant
    local gFus = CreateFrame("Button",nil,row,"BackdropTemplate"); gFus:SetSize(70,16); gFus:SetPoint("RIGHT",dBtn,"LEFT",-6,0)
    gFus:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
    local gFusTx = gFus:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(gFusTx,FONT,8,"OUTLINE"); gFusTx:SetAllPoints(); gFusTx:SetJustifyH("CENTER")

    local function RGD()
        -- Desat button visuel
        dIco:SetDesaturated(true)
        if info.desat then
            dBg:SetColorTexture(Theme.accent[1]*0.25, Theme.accent[2]*0.25, Theme.accent[3]*0.25, 0.9)
            dIco:SetAlpha(1)
        else
            dBg:SetColorTexture(0.06,0.06,0.10,0.6)
            dIco:SetAlpha(0.35)
        end
        -- Glow fusionné visuel
        local glc = info.glowColor or info.color or ns.barColor
        if info.glow then
            local gd = ns.GLOW_DEFS or {}
            local d = gd[info.glowIdx or 2]
            local sn = d and d.name or "?"
            if #sn > 8 then sn = sn:sub(1,7).."." end
            gFus:SetBackdropColor(0.08,0.08,0.12,0.95)
            gFus:SetBackdropBorderColor(glc[1], glc[2], glc[3], 0.9)
            gFusTx:SetText(sn)
            gFusTx:SetTextColor(Theme.textNormal[1], Theme.textNormal[2], Theme.textNormal[3])
        else
            gFus:SetBackdropColor(0.06,0.06,0.10,0.6)
            gFus:SetBackdropBorderColor(0.18,0.18,0.22,0.5)
            gFusTx:SetText("Glow off")
            gFusTx:SetTextColor(0.30, 0.30, 0.34)
        end
    end
    RGD()

    -- Desat : clic = toggle
    dBtn:SetScript("OnClick",function() info.desat = not info.desat; RGD(); onChg() end)
    dBtn:SetScript("OnEnter",function() dIco:SetAlpha(1); GameTooltip:SetOwner(dBtn,"ANCHOR_TOP"); GameTooltip:SetText("Desaturer l'icone",1,1,1); GameTooltip:Show() end)
    dBtn:SetScript("OnLeave",function() RGD(); GameTooltip:Hide() end)

    -- Glow fusionné : clic gauche = toggle, clic droit = picker (si actif)
    gFus:RegisterForClicks("LeftButtonUp","RightButtonUp")
    gFus:SetScript("OnClick",function(_,btn)
        if btn == "RightButton" then
            -- Clic droit : ouvre le picker (active le glow si besoin)
            if not info.glow then info.glow=true; if not info.glowIdx or info.glowIdx<2 then info.glowIdx=2 end end
            RGD(); onChg()
            ns.OpenGlowPopup(sid, info)
        else
            -- Clic gauche : toggle on/off
            info.glow = not info.glow
            if info.glow and (not info.glowIdx or info.glowIdx<2) then info.glowIdx=2 end
            RGD(); onChg()
        end
    end)
    gFus:SetScript("OnEnter",function()
        local glc = info.glowColor or info.color or ns.barColor
        gFus:SetBackdropBorderColor(glc[1],glc[2],glc[3],1)
        GameTooltip:SetOwner(gFus,"ANCHOR_TOP")
        GameTooltip:SetText(info.glow and "Glow actif" or "Glow desactive",1,1,1)
        GameTooltip:AddLine("Clic gauche : activer/desactiver", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Clic droit : choisir le type", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    gFus:SetScript("OnLeave",function() RGD(); GameTooltip:Hide() end)

    -- Séparateur hairline or subtil entre destinations et style
    local sep = row:CreateTexture(nil,"OVERLAY"); sep:SetSize(1,14); sep:SetPoint("RIGHT",gFus,"LEFT",-5,0)
    sep:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.15)

    -- Badges destinations [L][C][I][B] harmonisés
    -- Ordre d'affichage : L | C | I | B (de gauche à droite)
    -- Comme chaque bouton est ancré "RIGHT" de prevAnchor, on itère dans l'ordre INVERSE
    -- pour obtenir l'ordre voulu à l'écran : B est rendu en premier (le plus à droite),
    -- puis I, puis C, puis L (le plus à gauche).
    local destX = 10  -- espace depuis le séparateur
    local prevAnchor = sep
    for _, bk in ipairs({"B","I","C","L"}) do
        local bd = ns.DEST_BADGES[bk]
        if bd then
            local btn = CreateFrame("Button",nil,row,"BackdropTemplate"); btn:SetSize(18,16)
            btn:SetPoint("RIGHT", prevAnchor, "LEFT", (prevAnchor == sep) and -destX or -3, 0)
            btn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
            local lbl = btn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lbl,FONT,9,"OUTLINE")
            lbl:SetAllPoints(); lbl:SetJustifyH("CENTER"); lbl:SetText(bd.label)
            local function Ref()
                local on = (info.destinations and info.destinations[bd.key])
                if on then
                    -- Actif : fond teinté accent + bordure accent + texte clair
                    btn:SetBackdropColor(Theme.accent[1]*0.30, Theme.accent[2]*0.30, Theme.accent[3]*0.30, 0.95)
                    btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.85)
                    lbl:SetTextColor(Theme.textHighlight[1], Theme.textHighlight[2], Theme.textHighlight[3])
                else
                    -- Inactif : fond sombre + bordure subtile + texte gris (reste visiblement cliquable)
                    btn:SetBackdropColor(0.07, 0.07, 0.10, 0.75)
                    btn:SetBackdropBorderColor(0.22, 0.20, 0.18, 0.7)
                    lbl:SetTextColor(0.45, 0.42, 0.38)
                end
            end
            Ref()
            btn:SetScript("OnClick",function()
                if not info.destinations then info.destinations = {iconlist=false, freebars=false, circlebars=false, icons=false} end
                info.destinations[bd.key] = not info.destinations[bd.key]
                Ref(); onChg()
            end)
            btn:SetScript("OnEnter",function()
                btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                GameTooltip:SetOwner(btn,"ANCHOR_TOP")
                local names = { iconlist = "Liste d'icônes", freebars = "Barres de cercle", circlebars = "Barres libres", icons = "Icones" }
                GameTooltip:SetText((names[bd.key] or bd.key).." : cliquer pour toggler", 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",function() Ref(); GameTooltip:Hide() end)
            prevAnchor = btn
        end
    end

    -- Hover sur la ligne entière : surlignage + tooltip du sort
    -- Le tooltip est supplanté naturellement quand on entre sur un bouton enfant
    -- (badge destination, glow, desat, couleur) qui ont leur propre OnEnter.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function()
        rBg:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.03)
        GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
        pcall(function() GameTooltip:SetSpellByID(sid) end)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        rBg:SetColorTexture(0, 0, 0, 0)
        GameTooltip:Hide()
    end)

    return row, 28
end

------------------------------------------------------------------------
-- TACTICS MENU (liste complète déroulée, pas de dropdown de section)
-- 2 sections : DEBUFFS CIBLE (auras appliquées sur la cible) + BUFFS JOUEUR
-- (auras sur le joueur : buffs et enhancements). ACTIONS toujours en bas.
------------------------------------------------------------------------
function ns.SettingsPanel.BuildTacticsMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font

    -- ● TOGGLE CDM NATIF (unique point de contrôle pour tous les renders)
    local cbCDM = SW.CreateCheckbox(p, "Utiliser le CDM natif  |cff888888(désactive toutes nos barres/icônes custom)|r", cw-20)
    cbCDM:SetPoint("TOPLEFT", 10, 0)
    cbCDM:SetChecked(ns.db and ns.db.useNativeCDM == true)
    local cdmSep = p:CreateTexture(nil, "ARTWORK"); cdmSep:SetSize(cw-20, 1)
    cdmSep:SetPoint("TOPLEFT", 10, -30); cdmSep:SetColorTexture(0.25, 0.25, 0.28, 0.8)

    -- Overlay de grisage : couvre tout le contenu sous le toggle
    local overlay = CreateFrame("Frame", nil, p)
    overlay:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -40)
    overlay:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    overlay:SetFrameLevel(p:GetFrameLevel() + 50)
    overlay:EnableMouse(true)
    local overlayBg = overlay:CreateTexture(nil, "BACKGROUND")
    overlayBg:SetAllPoints(); overlayBg:SetColorTexture(0.05, 0.05, 0.07, 0.65)
    overlay:SetShown(ns.db and ns.db.useNativeCDM == true)

    cbCDM.onChanged = function(v)
        if ns.db then ns.db.useNativeCDM = v end
        overlay:SetShown(v)
        if v then
            -- SetAlpha(0) immédiat sur tous les containers (cohérent avec le pattern
            -- des Update functions qui vérifient useNativeCDM et appliquent SetAlpha(0))
            for _, rf in pairs(ns.renderFrames or {}) do
                if rf and rf.container then rf.container:SetAlpha(0) end
            end
            pcall(ns.ScanAuras)  -- déclenche les Update functions qui finaliseront le SetAlpha(0)
        else
            pcall(ns.RebuildDisplay)
        end
        pcall(ns.RefreshCDMMask)
    end

    local dH=SW.CreateSectionHeader(p,"Auras decouvertes (CDM)",cw-20); dH:SetPoint("TOPLEFT",10,-40)
    local leg=p:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(leg,FONT,10); leg:SetPoint("TOPLEFT",10,-60)
    leg:SetTextColor(unpack(Theme.textDim)); leg:SetText("[L] Liste d'icônes  [C] Barres de cercle  [I] Icones  [B] Barres libres")

    local function Build()
        -- Nettoie l'ancien contenu avant de reconstruire
        for _,c in pairs({p:GetChildren()}) do if c._isSpellContent then c:Hide() end end

        -- Tente de corriger la source des debuffs actifs mal classés (source="buff")
        pcall(function() if ns.ReclassifyExistingSpells then ns.ReclassifyExistingSpells() end end)

        local spells=ns.GetSpecSpells()
        if not spells or not next(spells) then
            local nd=p:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(nd,FONT,11)
            nd:SetPoint("TOP",0,-100); nd:SetTextColor(unpack(Theme.textDim))
            nd:SetText("Aucun sort decouvert.")
            nd._isSpellContent = true
            p:SetHeight(160); return
        end

        local function onChg() pcall(function() ns.BuildWhitelist(); ns.ScanAuras() end) end

        -- Classement par source : 2 groupes seulement
        --   deb = debuffs cible (unit="target", source="debuff")
        --   buf = buffs joueur (unit="player", source="buff" ou "enhancement")
        local deb,buf={},{}
        for sid,info in pairs(spells) do
            if info.source ~= "equipment" then  -- skip items WG dans ce menu
                if not info.destinations then info.destinations=ns.DeepCopy and ns.DeepCopy(ns.SpellDefaults.destinations) or {iconlist=false,freebars=false,circlebars=false,icons=false} end
                if info.glow==nil then info.glow=false end
                if info.desat==nil then info.desat=false end
                local src=info.source or "debuff"
                if src=="buff" or src=="enhancement" then
                    buf[#buf+1]={id=sid,info=info}
                else
                    deb[#deb+1]={id=sid,info=info}
                end
            end
        end
        local function srt(a,b)
            if a.info.enabled~=b.info.enabled then return a.info.enabled end
            return (a.info.name or "") < (b.info.name or "")
        end
        table.sort(deb,srt); table.sort(buf,srt)

        -- Conteneur principal déroulé
        local cont=CreateFrame("Frame",nil,p); cont:SetPoint("TOPLEFT",0,-80); cont:SetSize(cw,1); cont._isSpellContent=true

        local y = 0
        local SECTION_SPACING = 10   -- espace entre 2 sections
        local HEADER_HEIGHT   = 20   -- hauteur du titre de section
        local EMPTY_HEIGHT    = 20   -- hauteur du texte "(aucun)"

        -- Rend une section (titre + liste de sorts OU message "aucun"/personnalisé)
        local function RenderSection(name, list, emptyMsg)
            -- Titre de section (discret, couleur dim + filet or)
            local hdr = cont:CreateFontString(nil,"OVERLAY")
            ns.ApplyFont(hdr,FONT,10,"OUTLINE")
            hdr:SetPoint("TOPLEFT",10,-y); hdr:SetPoint("TOPRIGHT",-10,-y)
            hdr:SetJustifyH("LEFT")
            hdr:SetTextColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.85)
            hdr:SetText(name)
            -- Filet sous le titre
            local line = cont:CreateTexture(nil,"OVERLAY")
            line:SetHeight(1); line:SetPoint("TOPLEFT",10,-y-12); line:SetPoint("TOPRIGHT",-10,-y-12)
            line:SetColorTexture(Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.25)
            y = y + HEADER_HEIGHT

            if #list > 0 then
                -- Wrapper pour les rangées de sorts (ancré sous le header)
                local wrap = CreateFrame("Frame", nil, cont)
                wrap:SetPoint("TOPLEFT", 10, -y); wrap:SetPoint("TOPRIGHT", -10, -y)
                local listY = 0
                for _, e in ipairs(list) do
                    local r, h = CreateSpellRow(wrap, e.id, e.info, listY, cw-20, onChg)
                    r:Show(); listY = listY + h
                end
                wrap:SetHeight(listY)
                y = y + listY
            else
                local t = cont:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(t,FONT,11)
                t:SetPoint("TOPLEFT",10,-y); t:SetPoint("TOPRIGHT",-10,-y)
                t:SetJustifyH("CENTER"); t:SetTextColor(unpack(Theme.textDim))
                t:SetText(emptyMsg or "(aucun)")
                local h = emptyMsg and (EMPTY_HEIGHT * 2 + 8) or EMPTY_HEIGHT
                t:SetHeight(h)
                y = y + h
            end
            y = y + SECTION_SPACING
        end

        RenderSection("DEBUFFS CIBLE", deb)
        RenderSection("BUFFS JOUEUR",  buf)

        -- Section ACTIONS à la fin (3 boutons)
        y = y + 6  -- petit espace avant les boutons
        local actHdr = cont:CreateFontString(nil,"OVERLAY")
        ns.ApplyFont(actHdr,FONT,10,"OUTLINE")
        actHdr:SetPoint("TOPLEFT",10,-y); actHdr:SetPoint("TOPRIGHT",-10,-y)
        actHdr:SetJustifyH("LEFT"); actHdr:SetTextColor(unpack(Theme.textDim))
        actHdr:SetText("ACTIONS")
        local actLine = cont:CreateTexture(nil,"OVERLAY")
        actLine:SetHeight(1); actLine:SetPoint("TOPLEFT",10,-y-12); actLine:SetPoint("TOPRIGHT",-10,-y-12)
        actLine:SetColorTexture(Theme.separator[1], Theme.separator[2], Theme.separator[3], 0.5)
        y = y + HEADER_HEIGHT + 4

        -- Boutons ACTIONS dans le thème Black & Gold :
        -- surfaces sombres uniformes, bordures et textes en accents or/neutre/rouge-brique
        local dark = {0.06, 0.06, 0.08}  -- fond commun (cohérent avec cardBg assombri)

        -- Tout cocher : accent or (action positive, principal)
        local b1 = SW.CreateActionBtn(cont, "Tout cocher", 200,
            dark,
            {Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.75},
            {Theme.accent[1], Theme.accent[2], Theme.accent[3]})
        b1:SetPoint("TOP", cont, "TOP", 0, -y)
        b1:SetScript("OnClick", function() for _,i in pairs(spells) do i.enabled=true end; onChg(); Build() end)
        y = y + 28

        -- Tout décocher : bordure neutre, texte gris clair (action neutre)
        local b2 = SW.CreateActionBtn(cont, "Tout decocher", 200,
            dark,
            {Theme.border[1], Theme.border[2], Theme.border[3], 0.8},
            {Theme.textDim[1]*1.5, Theme.textDim[2]*1.5, Theme.textDim[3]*1.5})
        b2:SetPoint("TOP", cont, "TOP", 0, -y)
        b2:SetScript("OnClick", function() for _,i in pairs(spells) do i.enabled=false end; onChg(); Build() end)
        y = y + 28

        -- Rescanner : re-classifie les debuffs actifs + redécouvre via CDM
        local b3 = SW.CreateActionBtn(cont, "Rescanner les auras", 200,
            dark,
            {0.25, 0.40, 0.55, 0.75},
            {0.55, 0.75, 0.90})
        b3:SetPoint("TOP", cont, "TOP", 0, -y)
        b3:SetScript("OnClick", function()
            pcall(function() if ns.ReclassifyExistingSpells then ns.ReclassifyExistingSpells() end end)
            pcall(function() if ns.ScanCDMViewers then ns.ScanCDMViewers() end end)
            Build()
        end)
        y = y + 28

        -- Vider sorts découverts : rouge brique désaturé (action destructive mais tenue dans le thème)
        local b4 = SW.CreateActionBtn(cont, "Vider sorts decouverts", 200,
            dark,
            {0.55, 0.22, 0.15, 0.75},
            {0.75, 0.35, 0.25})
        b4:SetPoint("TOP", cont, "TOP", 0, -y)
        b4:SetScript("OnClick", function() wipe(spells); onChg(); Build() end)
        y = y + 28

        cont:SetHeight(y + 10)
        p:SetHeight(y + 100)
    end

    p:SetScript("OnShow", function() Build() end)
    Build()
end

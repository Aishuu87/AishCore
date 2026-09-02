-- AishUIAura/UI/Menus/Tactics.lua
-- Menu Tactics : liste des sorts découverts avec badges destination, glow, couleur
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

local TC = 0.07

-- BUG CORRIGE (2026-08-16) : ns.ScanAuras (Scan.Run) ne pilote plus les 4
-- destinations natives (icons/iconlist/circlebars/freebars, migrees vers
-- AddAuraGroup -- cf. AuraTrackerContainer.lua) -- Blizzard les met a jour
-- cote C++ des que la donnee d'aura change, jamais quand on retouche juste
-- un reglage d'apparence. Chacune des 4 a sa propre fonction de refresh de
-- style par bouton (couleur/spark/glow) -- a appeler explicitement partout
-- ou un glow (par sort OU par defaut) est modifie, sinon un glow deja
-- affiche garde son ancienne couleur/opacite/echelle jusqu'au prochain
-- /reload ou decoche+recoche du sort. Partagee par OpenGlowPopup (glow par
-- sort) et ns.RollDefaultGlow (glow par defaut).
local function RefreshAllNativeGlow()
    pcall(ns.RepositionIconsNativeGrid)      -- [I] ICONES
    pcall(ns.RepositionCircleBarsNativeGrid) -- [C] CERCLE (GUI "Circle Bars", cle freebars)
    pcall(ns.RepositionFreeBarsNativeGrid)   -- [B] LIBRES (GUI "Free Bars", cle circlebars)
    pcall(ns.RepositionIconListNativeGrid)   -- [L] LISTE (GUI "Liste d'icones", cle iconlist)
end

------------------------------------------------------------------------
-- GLOW POPUP (floating, draggable)
-- Port depuis AishUIAura — manquant dans AishCore, stocké en ns._glowPopup.
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
        sec:SetText(L["AURASMENU_TACTICS_GLOW_SECTION_TITLE"])

        local prevF = CreateFrame("Frame",nil,gp); prevF:SetSize(48,48); prevF:SetPoint("TOP",0,-50)
        prevF:SetFrameLevel(gp:GetFrameLevel()+3)
        prevF:CreateTexture(nil,"BACKGROUND"):SetColorTexture(0,0,0,0.5)
        gp._iconTex = prevF:CreateTexture(nil,"ARTWORK"); gp._iconTex:SetAllPoints(); gp._iconTex:SetTexCoord(TC,1-TC,TC,1-TC)
        gp._prevFrame = prevF

        local wPad = 16
        gp._glowDD   = SW.CreateDropdown(gp,L["AURASMENU_TACTICS_GLOW_TYPE_LOOP"],{},248); gp._glowDD:SetPoint("TOPLEFT",wPad,-110)
        gp._entryDD  = SW.CreateDropdown(gp,L["AURASMENU_TACTICS_ENTRY_ANIMATION"],{},248);    gp._entryDD:SetPoint("TOPLEFT",wPad,-158)

        gp._testProcBtn = CreateFrame("Button",nil,gp,"BackdropTemplate"); gp._testProcBtn:SetSize(120,20); gp._testProcBtn:SetPoint("TOPLEFT",wPad,-204)
        gp._testProcBtn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
        gp._testProcBtn:SetBackdropColor(0.20,0.15,0.08,0.9); gp._testProcBtn:SetBackdropBorderColor(0.80,0.55,0.20,0.7)
        local tpT = gp._testProcBtn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(tpT,FONT,9); tpT:SetAllPoints(); tpT:SetJustifyH("CENTER")
        tpT:SetTextColor(1.00,0.85,0.39); tpT:SetText(L["AURASMENU_TACTICS_TEST_PROC"])
        gp._testProcBtn:SetScript("OnEnter",function(s) s:SetBackdropColor(0.30,0.22,0.10,1) end)
        gp._testProcBtn:SetScript("OnLeave",function(s) s:SetBackdropColor(0.20,0.15,0.08,0.9) end)

        gp._procScaleSlider = SW.CreateSlider(gp,L["AURASMENU_TACTICS_PROC_SIZE"],0.1,3.0,0.05,248); gp._procScaleSlider:SetPoint("TOPLEFT",wPad,-228)
        gp._colorBtn        = SW.CreateColorButton(gp,L["AURASMENU_TACTICS_GLOW_COLOR"],248);         gp._colorBtn:SetPoint("TOPLEFT",wPad,-290)
        gp._opacSlider      = SW.CreateSlider(gp,L["AURASMENU_EQUIPMENT_OPACITY"],0,1,0.05,248);          gp._opacSlider:SetPoint("TOPLEFT",wPad,-320)
        gp._sizeSlider      = SW.CreateSlider(gp,L["AURASMENU_TACTICS_GLOW_SIZE"],0.1,3.0,0.05,248); gp._sizeSlider:SetPoint("TOPLEFT",wPad,-376)

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
    gp._title:SetText(string.format(L["AURASMENU_TACTICS_GLOW_TITLE"], (info.name or tostring(sid))))
    pcall(function() local t=C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid); if t then gp._iconTex:SetTexture(t) end end)

    local function RefreshGlowPreview()
        pcall(function()
            if ns.HideGlow then ns.HideGlow(gp._prevFrame) end
            local idx=info.glowIdx or 2; local gc=info.glowColor or info.color or ns.barColor
            if ns.ShowGlow and idx>1 then ns.ShowGlow(gp._prevFrame,idx,gc,info.glowAlpha or 0.7,info.glowScale or 1.0) end
        end)
    end

    local RefreshNativeGlow = RefreshAllNativeGlow

    local go={}; for idx,def in ipairs(ns.GLOW_DEFS or {}) do if not def.isProcStart then go[#go+1]={value=idx,text=def.name} end end
    gp._glowDD:SetOptions(go); gp._glowDD:SetValue(info.glowIdx or 2)
    gp._glowDD.onChanged=function(v) info.glowIdx=v; info._glowCustom=true; RefreshGlowPreview(); pcall(ns.ScanAuras); RefreshNativeGlow() end

    local po={{value=1,text=L["AURASMENU_EQUIPMENT_BORDER_NONE"]}}; for idx,def in ipairs(ns.GLOW_DEFS or {}) do if def.isProcStart then po[#po+1]={value=idx,text=def.name} end end
    gp._entryDD:SetOptions(po); gp._entryDD:SetValue(info.procGlowIdx or 1)
    gp._entryDD.onChanged=function(v) info.procGlowIdx=v; info._glowCustom=true; gp._testProcBtn:SetShown(v and v>1); gp._procScaleSlider:SetShown(v and v>1) end

    local procVisible = info.procGlowIdx and info.procGlowIdx > 1
    gp._testProcBtn:SetShown(procVisible); gp._procScaleSlider:SetShown(procVisible)
    gp._procScaleSlider:SetValue(info.procGlowScale or 1.0); gp._procScaleSlider.onChanged=function(v) info.procGlowScale=v; info._glowCustom=true end
    gp._testProcBtn:SetScript("OnClick",function()
        local pi=info.procGlowIdx; if not pi or pi<1 then return end
        if ns.PlayProcStart then ns.PlayProcStart(gp._prevFrame,pi,info.glowColor or info.color or ns.barColor,info.procGlowScale or 1.0) end
    end)

    local rc = info.glowColor or info.color or ns.barColor
    gp._colorBtn:SetColor(rc[1],rc[2],rc[3]); gp._colorBtn.onChanged=function(c) info.glowColor=c; info._glowCustom=true; RefreshGlowPreview(); pcall(ns.ScanAuras); RefreshNativeGlow() end
    -- BUG CORRIGE (2026-08-16) : contrairement au dropdown de style et au
    -- color picker ci-dessus, ces deux sliders ne declenchaient meme pas
    -- ns.ScanAuras -- la preview du popup se mettait a jour, mais l'aura
    -- deja affichee en jeu gardait son ancienne opacite/taille de glow
    -- jusqu'au prochain rescan (decoche/recoche du sort ou /reload).
    gp._opacSlider:SetValue(info.glowAlpha or 0.7); gp._opacSlider.onChanged=function(v) info.glowAlpha=v; info._glowCustom=true; RefreshGlowPreview(); pcall(ns.ScanAuras); RefreshNativeGlow() end
    gp._sizeSlider:SetValue(info.glowScale or 1.0); gp._sizeSlider.onChanged=function(v) info.glowScale=v; info._glowCustom=true; RefreshGlowPreview(); pcall(ns.ScanAuras); RefreshNativeGlow() end
    gp:Show(); C_Timer.After(0.05, RefreshGlowPreview)
end

------------------------------------------------------------------------
-- GLOW PAR DEFAUT
-- S'applique a toute aura qui n'a pas de glow personnalise (info._glowCustom
-- reste false/nil tant que l'utilisateur n'a pas touche manuellement au glow
-- de ce sort precis, cf. CreateSpellRow / OpenGlowPopup ci-dessous). Des que
-- l'utilisateur personnalise le glow d'un sort, ce sort n'est plus jamais
-- retouche par le defaut (_glowCustom=true, verrouille comme _colorDefault
-- dans CDMHooks.lua).
------------------------------------------------------------------------
-- Couleur de repli quand l'utilisateur n'a pas choisi de couleur de glow par
-- defaut explicite (db.defaultGlowColorR nil) : couleur "Lueur" du module
-- Colors (element "glow"), qui suit deja la chaine override DB -> defaut de
-- spe -> couleur de classe -- donc change automatiquement avec la spe active.
-- ns.barColor (couleur de classe statique, Auras/Core/ClassColors.lua) ne sert
-- plus que de tout dernier filet si le module Colors n'est pas disponible.
-- Copie defensive ({c[1],c[2],c[3]}) : Colors.Get() peut renvoyer une
-- reference directe vers une table interne (CLASS_FALLBACK/SPEC_DEFAULTS/
-- overrides), jamais une valeur qu'on veut modifier/partager par accident.
local function GetDefaultGlowColorFallback()
    local CLR = _addon.Modules and _addon.Modules.Colors
    local c = CLR and CLR.Get and CLR.Get("glow")
    if c then return { c[1], c[2], c[3] } end
    return ns.barColor or { 0.5, 0.5, 0.5 }
end

-- GLOW PAR DEFAUT PAR SPE : type/anim/opacite/taille/couleur, comme la
-- personnalisation par sort, doivent pouvoir differer d'une spe a l'autre
-- (ex: glow discret en Brasseur, flashy en Devastation). Stocke sous
-- ns.db.defaultGlowBySpec[GetSpecKey()] plutot que les anciennes cles plates
-- ns.db.defaultGlow* (globales, partagees entre TOUTES les specs -- confirme
-- en jeu par l'utilisateur : une couleur choisie sur Moine restait affichee
-- sur Guerrier). GetSpecKey() (Init.lua) est deja le meme identifiant
-- (perso-realm_classe_spe) qui isole discoveredSpells par spe.
-- Migration one-shot : au premier acces pour une spe donnee, on seede depuis
-- les anciennes cles globales (comportement pre-per-spec) plutot que reset a
-- zero -- evite de perdre silencieusement le reglage deja en place pour la
-- spe active au moment de la mise a jour.
local function GetDefaultGlowCfg()
    local db = ns.db
    if not db then return {} end
    local key = ns.GetSpecKey and ns.GetSpecKey()
    if not key then
        -- Spe inconnue (rare) : table jetable reprenant les anciennes cles
        -- plates en lecture (jamais persistee -- pas de cle valable pour la
        -- stocker). db.idx/db.colorR etc n'existent pas : ne JAMAIS renvoyer
        -- db lui-meme ici, les noms de champs ne correspondent pas.
        return {
            idx     = db.defaultGlowIdx,
            colorR  = db.defaultGlowColorR,
            colorG  = db.defaultGlowColorG,
            colorB  = db.defaultGlowColorB,
            alpha   = db.defaultGlowAlpha,
            scale   = db.defaultGlowScale,
            procIdx = db.defaultProcGlowIdx,
        }
    end
    db.defaultGlowBySpec = db.defaultGlowBySpec or {}
    local cfg = db.defaultGlowBySpec[key]
    if not cfg then
        cfg = {
            idx     = db.defaultGlowIdx,
            colorR  = db.defaultGlowColorR,
            colorG  = db.defaultGlowColorG,
            colorB  = db.defaultGlowColorB,
            alpha   = db.defaultGlowAlpha,
            scale   = db.defaultGlowScale,
            procIdx = db.defaultProcGlowIdx,
        }
        db.defaultGlowBySpec[key] = cfg
    end
    return cfg
end
ns.GetDefaultGlowCfg = GetDefaultGlowCfg

function ns.ApplyDefaultGlowToSpell(info)
    if not info then return end
    local cfg = GetDefaultGlowCfg()
    local idx = cfg.idx or 2
    info.glowIdx = idx
    info.glow = idx > 1
    if cfg.colorR then
        info.glowColor = { cfg.colorR, cfg.colorG, cfg.colorB }
    else
        info.glowColor = GetDefaultGlowColorFallback()
    end
    info.glowAlpha = cfg.alpha or 0.7
    info.glowScale = cfg.scale or 1.0
    info.procGlowIdx = cfg.procIdx or 1
    info._glowCustom = false
end

function ns.RollDefaultGlow()
    local spells = ns.GetSpecSpells and ns.GetSpecSpells()
    if not spells then return end
    for _, info in pairs(spells) do
        if info._glowCustom ~= true then
            ns.ApplyDefaultGlowToSpell(info)
        end
    end
    pcall(ns.ScanAuras)
    -- BUG CORRIGE (2026-08-16) : meme lacune que le glow par-sort
    -- (OpenGlowPopup) -- ns.ScanAuras seul ne touche jamais les 4
    -- destinations natives, donc le glow par defaut (type/couleur/opacite/
    -- echelle) ne se repercutait jamais sur les boutons deja affiches.
    RefreshAllNativeGlow()
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

    -- Forward-declare : assigne plus bas (section glow fusionne), mais doit
    -- deja exister ici pour que la checkbox puisse rafraichir le badge glow
    -- quand elle applique le glow par defaut a l'activation du sort.
    local RGD

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
    cb:SetScript("OnClick",function()
        info.enabled=not info.enabled
        -- A l'activation, si ce sort n'a jamais eu de glow personnalise, on lui
        -- applique le glow par defaut courant (voir GLOW PAR DEFAUT du menu).
        if info.enabled and info._glowCustom ~= true and ns.ApplyDefaultGlowToSpell then
            ns.ApplyDefaultGlowToSpell(info)
            if RGD then RGD() end
        end
        RCB(); onChg()
    end)
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
    sw1:SetScript("OnEnter",function() GameTooltip:SetOwner(sw1,"ANCHOR_TOP"); GameTooltip:SetText(L["AURASMENU_TACTICS_BAR_COLOR_TOOLTIP"],1,1,1); GameTooltip:Show() end)
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

    RGD = function()
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
            gFusTx:SetText(L["AURASMENU_EQUIPMENT_GLOW_OFF"])
            gFusTx:SetTextColor(0.30, 0.30, 0.34)
        end
    end
    RGD()

    -- Desat : clic = toggle
    dBtn:SetScript("OnClick",function() info.desat = not info.desat; RGD(); onChg() end)
    dBtn:SetScript("OnEnter",function() dIco:SetAlpha(1); GameTooltip:SetOwner(dBtn,"ANCHOR_TOP"); GameTooltip:SetText(L["AURASMENU_EQUIPMENT_DESATURATE_TOOLTIP"],1,1,1); GameTooltip:Show() end)
    dBtn:SetScript("OnLeave",function() RGD(); GameTooltip:Hide() end)

    -- Glow fusionné : clic gauche = toggle, clic droit = picker (si actif)
    gFus:RegisterForClicks("LeftButtonUp","RightButtonUp")
    gFus:SetScript("OnClick",function(_,btn)
        -- Toute interaction manuelle sur le glow verrouille ce sort : il ne suivra
        -- plus jamais le glow par defaut (meme logique que _colorDefault pour la couleur).
        info._glowCustom = true
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
        GameTooltip:SetText(info.glow and L["AURASMENU_EQUIPMENT_GLOW_ACTIVE"] or L["AURASMENU_EQUIPMENT_GLOW_INACTIVE"],1,1,1)
        GameTooltip:AddLine(L["AURASMENU_EQUIPMENT_GLOW_TOOLTIP_LEFT"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["AURASMENU_EQUIPMENT_GLOW_TOOLTIP_RIGHT"], 0.7, 0.7, 0.7)
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
                -- Active/désactive automatiquement le toggle de gauche (info.enabled)
                -- selon qu'au moins un mode d'affichage reste actif ou plus aucun --
                -- un sort sans destination cochée n'a de toute façon aucun effet
                -- visuel, autant que le toggle principal reflète cet état sans
                -- action manuelle en plus.
                local anyDest = false
                for _, v in pairs(info.destinations) do if v then anyDest = true; break end end
                if anyDest and not info.enabled then
                    info.enabled = true
                    -- Même effet de bord que le toggle de gauche lui-même (cb
                    -- plus haut) : applique le glow par défaut si ce sort n'a
                    -- jamais eu de glow personnalisé.
                    if info._glowCustom ~= true and ns.ApplyDefaultGlowToSpell then
                        ns.ApplyDefaultGlowToSpell(info)
                        if RGD then RGD() end
                    end
                    RCB()
                elseif not anyDest and info.enabled then
                    info.enabled = false
                    RCB()
                end
                Ref(); onChg()
            end)
            btn:SetScript("OnEnter",function()
                btn:SetBackdropBorderColor(Theme.accent[1], Theme.accent[2], Theme.accent[3], 1)
                GameTooltip:SetOwner(btn,"ANCHOR_TOP")
                local names = { iconlist = L["AURASMENU_PREVIEW_RENDER_ICONLIST"], freebars = L["AURASMENU_PREVIEW_RENDER_CIRCLE_BARS"], circlebars = L["AURASMENU_PREVIEW_RENDER_FREE_BARS"], icons = L["AURASMENU_PREVIEW_RENDER_ICONS"] }
                GameTooltip:SetText(string.format(L["AURASMENU_TACTICS_DEST_TOOLTIP"], (names[bd.key] or bd.key)), 1, 1, 1)
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

    -- Forward-declare : assigne plus bas. Permet aux controles GLOW PAR DEFAUT
    -- (definis avant Build) de forcer un rafraichissement visuel des badges glow
    -- de chaque ligne apres un ns.RollDefaultGlow().
    local Build

    -- ● TOGGLE CDM NATIF (unique point de contrôle pour tous les renders)
    local cbCDM = SW.CreateCheckbox(p, L["AURASMENU_TACTICS_USE_NATIVE_CDM"], cw-20)
    cbCDM:SetPoint("TOPLEFT", 10, 0)
    cbCDM:SetChecked(ns.db and ns.db.useNativeCDM == true)
    local cdmSep = p:CreateTexture(nil, "ARTWORK"); cdmSep:SetSize(cw-20, 1)
    cdmSep:SetPoint("TOPLEFT", 10, -30); cdmSep:SetColorTexture(0.25, 0.25, 0.28, 0.8)

    -- ● TOOLTIP DES AURAS EN COMBAT SEULEMENT AVEC ALT (indépendant de l'équivalent
    -- Priority Bar) — grisé avec le reste par l'overlay CDM natif ci-dessous, puisque
    -- sans rendu custom ce réglage n'a de toute façon aucun effet.
    local cbTooltipAlt = SW.CreateCheckbox(p, L["AURASMENU_TACTICS_TOOLTIP_ALT_COMBAT"], cw-20)
    cbTooltipAlt:SetPoint("TOPLEFT", 10, -40)
    cbTooltipAlt:SetChecked(ns.db and ns.db.tooltipAltCombatOnly == true)
    cbTooltipAlt.onChanged = function(v)
        if ns.db then ns.db.tooltipAltCombatOnly = v end
    end

    -- Overlay de grisage : couvre tout le contenu sous le toggle CDM natif
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

    ------------------------------------------------------------------------
    -- ● GLOW PAR DEFAUT — s'applique a toute aura cochee qui n'a pas de glow
    -- personnalise (voir ns.ApplyDefaultGlowToSpell / ns.RollDefaultGlow plus
    -- haut dans ce fichier). Grisee avec le reste par l'overlay CDM natif
    -- puisqu'elle ne concerne que le rendu custom.
    -- Layout compact : Type de glow + Anim de proc sur une ligne, puis
    -- Opacite + Taille + Couleur sur une autre, pour limiter l'espace occupe.
    ------------------------------------------------------------------------
    local dgY = -66
    local dgH=SW.CreateSectionHeader(p,L["AURASMENU_TACTICS_DEFAULT_GLOW_HEADER"],cw-20); dgH:SetPoint("TOPLEFT",10,dgY); dgY=dgY-22
    local dgInfo=p:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(dgInfo,FONT,9)
    dgInfo:SetPoint("TOPLEFT",10,dgY); dgInfo:SetPoint("TOPRIGHT",-10,dgY)
    dgInfo:SetJustifyH("LEFT"); dgInfo:SetWordWrap(true)
    dgInfo:SetTextColor(unpack(Theme.textDim)); dgInfo:SetText(L["AURASMENU_TACTICS_DEFAULT_GLOW_INFO"])
    dgY = dgY - 28

    local dgPrev = CreateFrame("Frame",nil,p); dgPrev:SetSize(32,32); dgPrev:SetPoint("TOP",0,dgY)
    dgPrev:SetFrameLevel(p:GetFrameLevel()+10)
    local dgPrevIco = dgPrev:CreateTexture(nil,"ARTWORK"); dgPrevIco:SetAllPoints(); dgPrevIco:SetTexCoord(TC,1-TC,TC,1-TC)
    pcall(function() dgPrevIco:SetTexture(134154) end)
    dgY = dgY - 40

    local function RefreshDefaultGlowPreview()
        pcall(function()
            if ns.HideGlow then ns.HideGlow(dgPrev) end
            local cfg = GetDefaultGlowCfg()
            local idx = cfg.idx or 2
            if idx > 1 then
                local bc = GetDefaultGlowColorFallback()
                local gc = { cfg.colorR or bc[1], cfg.colorG or bc[2], cfg.colorB or bc[3] }
                if ns.ShowGlow then ns.ShowGlow(dgPrev, idx, gc, cfg.alpha or 0.7, cfg.scale or 1.0) end
            end
        end)
    end

    -- Ligne 1 : Type de glow (boucle) + Anim d'entree (proc)
    local dgSlW = math.min(260,(cw-20)/2-20); local dgGap = 20; local dgOx = math.max(10,(cw-dgSlW*2-dgGap)/2)
    local dgOpts={}
    for idx,def in ipairs(ns.GLOW_DEFS or {}) do if not def.isProcStart then dgOpts[#dgOpts+1]={value=idx,text=def.name} end end
    local dgDD = SW.CreateDropdown(p, L["AURASMENU_RENDER_GLOW_TYPE"], dgOpts, dgSlW); dgDD:SetPoint("TOPLEFT",dgOx,dgY)
    dgDD:SetValue(GetDefaultGlowCfg().idx or 2)
    dgDD.onChanged = function(v)
        GetDefaultGlowCfg().idx = v
        RefreshDefaultGlowPreview(); pcall(ns.RollDefaultGlow); if Build then Build() end
    end

    local dgEntryOpts={{value=1,text=L["AURASMENU_EQUIPMENT_BORDER_NONE"]}}
    for idx,def in ipairs(ns.GLOW_DEFS or {}) do if def.isProcStart then dgEntryOpts[#dgEntryOpts+1]={value=idx,text=def.name} end end
    local dgEntryDD = SW.CreateDropdown(p, L["AURASMENU_TACTICS_ENTRY_ANIMATION"], dgEntryOpts, dgSlW); dgEntryDD:SetPoint("TOPLEFT",dgOx+dgSlW+dgGap,dgY)
    dgEntryDD:SetValue(GetDefaultGlowCfg().procIdx or 1)
    dgEntryDD.onChanged = function(v)
        GetDefaultGlowCfg().procIdx = v
        pcall(ns.RollDefaultGlow)
    end
    dgY = dgY - 50

    -- Ligne 2 : Opacite + Taille + Couleur du glow
    local dgSlW3 = (cw-20-2*dgGap)/3; local dgOx3 = 10
    local dgAlpha = SW.CreateSlider(p, L["AURASMENU_EQUIPMENT_OPACITY"], 0,1,0.05, dgSlW3); dgAlpha:SetPoint("TOPLEFT",dgOx3,dgY)
    dgAlpha:SetValue(GetDefaultGlowCfg().alpha or 0.7)
    dgAlpha.onChanged = function(v)
        GetDefaultGlowCfg().alpha = v
        -- Pas de Build() ici : alpha/scale n'affectent pas le badge glow des lignes
        -- (RGD n'affiche que le type + la couleur), et le slider declenche onChanged
        -- en continu pendant le drag (un Build() complet a chaque tick serait couteux).
        RefreshDefaultGlowPreview(); pcall(ns.RollDefaultGlow)
    end
    local dgScale = SW.CreateSlider(p, L["AURASMENU_TACTICS_GLOW_SIZE"], 0.1,3.0,0.05, dgSlW3); dgScale:SetPoint("TOPLEFT",dgOx3+dgSlW3+dgGap,dgY)
    dgScale:SetValue(GetDefaultGlowCfg().scale or 1.0)
    dgScale.onChanged = function(v)
        GetDefaultGlowCfg().scale = v
        RefreshDefaultGlowPreview(); pcall(ns.RollDefaultGlow)
    end
    -- Largeur reduite (pas dgSlW3, contrairement aux 2 sliders de la ligne) :
    -- CreateColorButton ancre son label a LEFT+8 et son swatch a RIGHT-8 du
    -- conteneur -- avec la pleine largeur de colonne (dgSlW3, dimensionnee
    -- pour un slider), le swatch se retrouvait tres loin du label "Couleur".
    -- Le positionnement (TOPLEFT) ne depend pas de cette largeur, seule la
    -- 3e colonne se resserre.
    local dgColorW = 130
    local dgColor = SW.CreateColorButton(p, L["AURASMENU_TACTICS_GLOW_COLOR"], dgColorW); dgColor:SetPoint("TOPLEFT",dgOx3+2*(dgSlW3+dgGap),dgY)
    if dgColor._swatch then
        dgColor._swatch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["AURASMENU_TACTICS_DEFAULT_GLOW_COLOR_TOOLTIP"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        dgColor._swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    do
        local cfg = GetDefaultGlowCfg()
        local dbc = GetDefaultGlowColorFallback()
        dgColor:SetColor(cfg.colorR or dbc[1], cfg.colorG or dbc[2], cfg.colorB or dbc[3])
    end
    dgColor.onChanged = function(col)
        local cfg = GetDefaultGlowCfg()
        cfg.colorR, cfg.colorG, cfg.colorB = col[1], col[2], col[3]
        -- Pas de Build() ici : le color picker declenche onChanged en continu
        -- pendant le drag (un Build() complet a chaque tick serait couteux).
        -- Les badges des lignes se rafraichiront au prochain Build() naturel.
        RefreshDefaultGlowPreview(); pcall(ns.RollDefaultGlow)
    end
    -- Clic droit sur le swatch = reset : efface l'override manuel (cfg.colorR/G/B
    -- -> nil) pour que ApplyDefaultGlowToSpell retombe sur GetDefaultGlowColorFallback
    -- (couleur "Lueur" de la spe active, cf. plus haut).
    dgColor.onReset = function()
        local cfg = GetDefaultGlowCfg()
        cfg.colorR, cfg.colorG, cfg.colorB = nil, nil, nil
        local dbc = GetDefaultGlowColorFallback()
        dgColor:SetColor(dbc[1], dbc[2], dbc[3])
        RefreshDefaultGlowPreview(); pcall(ns.RollDefaultGlow)
    end
    dgY = dgY - 60
    C_Timer.After(0.1, RefreshDefaultGlowPreview)

    -- Resynchronise les 5 controles avec la config de la spe active : appele
    -- au changement de spe pendant que ce menu est deja construit et affiche
    -- (sinon les widgets resteraient figes sur les valeurs de l'ancienne spe
    -- jusqu'au prochain re-Build). Cf. Modules/Colors.lua (callback broadcast,
    -- deja declenche sur PLAYER_SPECIALIZATION_CHANGED).
    ns.RefreshDefaultGlowWidgets = function()
        local cfg = GetDefaultGlowCfg()
        dgDD:SetValue(cfg.idx or 2)
        dgEntryDD:SetValue(cfg.procIdx or 1)
        dgAlpha:SetValue(cfg.alpha or 0.7)
        dgScale:SetValue(cfg.scale or 1.0)
        local dbc = GetDefaultGlowColorFallback()
        dgColor:SetColor(cfg.colorR or dbc[1], cfg.colorG or dbc[2], cfg.colorB or dbc[3])
        RefreshDefaultGlowPreview()
    end

    local dgSep = p:CreateTexture(nil, "ARTWORK"); dgSep:SetSize(cw-20, 1)
    dgSep:SetPoint("TOPLEFT", 10, dgY-4); dgSep:SetColorTexture(0.25, 0.25, 0.28, 0.8)
    dgY = dgY - 16

    local dH=SW.CreateSectionHeader(p,L["AURASMENU_TACTICS_DISCOVERED_AURAS"],cw-20); dH:SetPoint("TOPLEFT",10,dgY)
    local leg=p:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(leg,FONT,10); leg:SetPoint("TOPLEFT",10,dgY-20)
    leg:SetTextColor(unpack(Theme.textDim)); leg:SetText(L["AURASMENU_TACTICS_LEGEND"])

    Build = function()
        -- Nettoie l'ancien contenu avant de reconstruire
        for _,c in pairs({p:GetChildren()}) do if c._isSpellContent then c:Hide() end end

        -- Tente de corriger la source des debuffs actifs mal classés (source="buff")
        pcall(function() if ns.ReclassifyExistingSpells then ns.ReclassifyExistingSpells() end end)

        local spells=ns.GetSpecSpells()
        if not spells or not next(spells) then
            local nd=p:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(nd,FONT,11)
            nd:SetPoint("TOP",0,dgY-60); nd:SetTextColor(unpack(Theme.textDim))
            nd:SetText(L["AURASMENU_TACTICS_NO_SPELL_DISCOVERED"])
            nd._isSpellContent = true
            p:SetHeight(-dgY + 120); return
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
            -- _addon.FoldAccentsLower (Core.lua) : replie chaque lettre
            -- accentuée sur sa lettre de base (é/è/ê/ë -> e, etc.) puis
            -- minuscule -- résultat 100% ASCII comparable au `<` normal.
            -- strcmputf8i seul NE SUFFISAIT PAS pour ce client (confirmé en
            -- jeu : classait toujours les noms accentués après Z).
            return _addon.FoldAccentsLower(a.info.name or "") < _addon.FoldAccentsLower(b.info.name or "")
        end
        table.sort(deb,srt); table.sort(buf,srt)

        -- Conteneur principal déroulé
        local cont=CreateFrame("Frame",nil,p); cont:SetPoint("TOPLEFT",0,dgY-40); cont:SetSize(cw,1); cont._isSpellContent=true

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
                t:SetText(emptyMsg or L["AURASMENU_TACTICS_EMPTY_PLACEHOLDER"])
                local h = emptyMsg and (EMPTY_HEIGHT * 2 + 8) or EMPTY_HEIGHT
                t:SetHeight(h)
                y = y + h
            end
            y = y + SECTION_SPACING
        end

        RenderSection(L["AURASMENU_TACTICS_SECTION_DEBUFFS_TARGET"], deb)
        RenderSection(L["AURASMENU_TACTICS_SECTION_BUFFS_PLAYER"],  buf)

        -- Section ACTIONS à la fin (3 boutons)
        y = y + 6  -- petit espace avant les boutons
        local actHdr = cont:CreateFontString(nil,"OVERLAY")
        ns.ApplyFont(actHdr,FONT,10,"OUTLINE")
        actHdr:SetPoint("TOPLEFT",10,-y); actHdr:SetPoint("TOPRIGHT",-10,-y)
        actHdr:SetJustifyH("LEFT"); actHdr:SetTextColor(unpack(Theme.textDim))
        actHdr:SetText(L["AURASMENU_TACTICS_SECTION_ACTIONS"])
        local actLine = cont:CreateTexture(nil,"OVERLAY")
        actLine:SetHeight(1); actLine:SetPoint("TOPLEFT",10,-y-12); actLine:SetPoint("TOPRIGHT",-10,-y-12)
        actLine:SetColorTexture(Theme.separator[1], Theme.separator[2], Theme.separator[3], 0.5)
        y = y + HEADER_HEIGHT + 4

        -- Boutons ACTIONS dans le thème Black & Gold :
        -- surfaces sombres uniformes, bordures et textes en accents or/neutre/rouge-brique
        local dark = {0.06, 0.06, 0.08}  -- fond commun (cohérent avec cardBg assombri)

        -- Tout cocher : accent or (action positive, principal)
        local b1 = SW.CreateActionBtn(cont, L["AURASMENU_TACTICS_CHECK_ALL"], 200,
            dark,
            {Theme.accent[1], Theme.accent[2], Theme.accent[3], 0.75},
            {Theme.accent[1], Theme.accent[2], Theme.accent[3]})
        b1:SetPoint("TOP", cont, "TOP", 0, -y)
        b1:SetScript("OnClick", function() for _,i in pairs(spells) do i.enabled=true end; onChg(); Build() end)
        y = y + 28

        -- Tout décocher : bordure neutre, texte gris clair (action neutre)
        local b2 = SW.CreateActionBtn(cont, L["AURASMENU_TACTICS_UNCHECK_ALL"], 200,
            dark,
            {Theme.border[1], Theme.border[2], Theme.border[3], 0.8},
            {Theme.textDim[1]*1.5, Theme.textDim[2]*1.5, Theme.textDim[3]*1.5})
        b2:SetPoint("TOP", cont, "TOP", 0, -y)
        b2:SetScript("OnClick", function() for _,i in pairs(spells) do i.enabled=false end; onChg(); Build() end)
        y = y + 28

        -- Rescanner : re-classifie les debuffs actifs + redécouvre via CDM
        local b3 = SW.CreateActionBtn(cont, L["AURASMENU_TACTICS_RESCAN_AURAS"], 200,
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
        local b4 = SW.CreateActionBtn(cont, L["AURASMENU_TACTICS_CLEAR_DISCOVERED"], 200,
            dark,
            {0.55, 0.22, 0.15, 0.75},
            {0.75, 0.35, 0.25})
        b4:SetPoint("TOP", cont, "TOP", 0, -y)
        b4:SetScript("OnClick", function() wipe(spells); onChg(); Build() end)
        y = y + 28

        cont:SetHeight(y + 10)
        p:SetHeight(y - dgY + 60)
    end

    -- Preview live : tant que ce menu est ouvert, affiche les sorts coches
    -- (avec leurs destinations reellement assignees) comme s'ils etaient
    -- actifs, a l'emplacement concerne (L/C/I/B) — meme mecanisme que les
    -- menus de rendu par emplacement (Render.lua), mais sans les icones
    -- generiques de remplissage : seuls les sorts vraiment coches previsualisent,
    -- pour rester fidele a l'etat de la liste pendant qu'on la configure.
    p:SetScript("OnShow", function()
        Build()
        ns._previewBars = true
        ns._previewMode = "all"
        ns._previewNoFallback = true
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
    end)
    p:SetScript("OnHide", function()
        ns._previewBars = false
        ns._previewMode = nil
        ns._previewNoFallback = nil
        if ns.UpdateAllFades then pcall(ns.UpdateAllFades) end
        pcall(function() ns.ScanAuras() end)
    end)
    Build()
end

-- AishUIAura/UI/Menus/Equipment.lua
-- Equipment menu: layout cards (Shield Wall / Ronin) + equipment list + position/borders
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
ns.SettingsPanel = ns.SettingsPanel or {}

function ns.SettingsPanel.BuildEquipmentMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font
    local panel = ns.SettingsPanel.panel
    local TC = 0.07

    local y=0; local cfg=ns.db and ns.db.equipment or {}; local al=cfg.layout or "grid_fixed"
    local dH=SW.CreateSectionHeader(p,"Disposition (trinkets / raciales / equip.)",cw-20); dH:SetPoint("TOPLEFT",10,-y); y=y+22
    local cards={{key="grid_fixed",name=ns.LAYOUT_NAMES.GRID_FIXED,fb="ability_warrior_shieldwall"},{key="grid_free",name=ns.LAYOUT_NAMES.GRID_FREE,fb="ability_rogue_sprint"}}
    local sx=math.max(10,(cw-2*155)/2)
    local wgCards = {}
    local function RefreshWGCards()
        local cur = ns.db and ns.db.equipment and ns.db.equipment.layout or "grid_fixed"
        for _, lc in ipairs(wgCards) do
            local isAct = (lc.key == cur)
            lc.lbl:SetTextColor(unpack(isAct and Theme.textNormal or Theme.textDisabled))
            if isAct then
                local tex = ns.LAYOUT_ICONS and ns.LAYOUT_ICONS[lc.key:upper()]
                if tex then pcall(function() lc.ico:SetTexture(tex) end) end
                lc.ico:SetVertexColor(1,1,1,1)
                if lc.actTx then lc.actTx:Show() end
            else
                local tex = ns.LAYOUT_ICONS_INACTIVE and ns.LAYOUT_ICONS_INACTIVE[lc.key:upper()]
                if tex then pcall(function() lc.ico:SetTexture(tex) end) end
                lc.ico:SetVertexColor(1,1,1,1)
                if lc.actTx then lc.actTx:Hide() end
            end
        end
    end
    for i,c in ipairs(cards) do
        local isAct=(al==c.key)
        -- Card sans encadré : juste Button transparent + icône + label.
        -- Le halo doré apparaît uniquement au survol (hover feedback).
        local card=CreateFrame("Button",nil,p,"BackdropTemplate"); card:SetSize(140,110); card:SetPoint("TOPLEFT",sx+(i-1)*155,-(y+10))

        -- Halo de survol (caché par défaut)
        local hoverGlow = card:CreateTexture(nil,"BACKGROUND",nil,0)
        hoverGlow:SetAllPoints()
        hoverGlow:SetColorTexture(Theme.gold and Theme.gold[1] or 0.78,
                                   Theme.gold and Theme.gold[2] or 0.62,
                                   Theme.gold and Theme.gold[3] or 0.30, 0.08)
        hoverGlow:Hide()

        -- Bordure invisible par défaut, devient or au survol
        local cbd = CreateFrame("Frame",nil,card,"BackdropTemplate"); cbd:SetAllPoints()
        cbd:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
        cbd:SetBackdropBorderColor(0,0,0,0)

        -- Icône : TGA custom du layout (120×75, ratio 128:80 préservé)
        local ico=card:CreateTexture(nil,"ARTWORK"); ico:SetSize(120, 75); ico:SetPoint("TOP",0,-2)
        local function _SetLayoutIcon(active)
            local tex = active
                and (ns.LAYOUT_ICONS and ns.LAYOUT_ICONS[c.key:upper()])
                or  (ns.LAYOUT_ICONS_INACTIVE and ns.LAYOUT_ICONS_INACTIVE[c.key:upper()])
            if tex then
                pcall(function() ico:SetTexture(tex) end)
            else
                pcall(function() ico:SetTexture("Interface\\Icons\\"..c.fb) end)
            end
        end
        _SetLayoutIcon(isAct)
        ico:SetVertexColor(1,1,1,1)
        local clbl=card:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(clbl,FONT,12); clbl:SetPoint("BOTTOM",0,20)
        clbl:SetTextColor(unpack(isAct and Theme.textNormal or Theme.textDisabled)); clbl:SetText(c.name)

        -- Label "ACTIF" sous le label nom si actif
        local actTx=nil
        if isAct then
            actTx = card:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(actTx,FONT,8)
            actTx:SetPoint("BOTTOM",0,5); actTx:SetTextColor(unpack(Theme.accent)); actTx:SetText("ACTIF")
        end

        wgCards[#wgCards+1] = {key=c.key, ico=ico, lbl=clbl, actTx=actTx}
        card:SetScript("OnClick",function()
            if ns.db and ns.db.equipment then ns.db.equipment.layout=c.key end
            -- Create actTx for newly active card if missing
            for _, lc in ipairs(wgCards) do
                if not lc.actTx then
                    lc.actTx = clbl:GetParent():CreateFontString(nil,"OVERLAY")
                    ns.ApplyFont(lc.actTx,FONT,8); lc.actTx:SetPoint("BOTTOM",0,5)
                    lc.actTx:SetTextColor(unpack(Theme.accent)); lc.actTx:SetText("ACTIF")
                end
            end
            RefreshWGCards(); pcall(function() if ns.Providers then ns.Providers:Refresh() end end)
            -- Rebuild pour afficher/cacher GROUPE vs INDIVIDUEL
            pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end)
        end)
        card:SetScript("OnEnter",function()
            hoverGlow:Show()
            local g = Theme.gold or {0.78,0.62,0.30}
            cbd:SetBackdropBorderColor(g[1],g[2],g[3],0.8)
            clbl:SetTextColor(1,1,1)
            _SetLayoutIcon(true)
            ico:SetVertexColor(1,1,1,1)
        end)
        card:SetScript("OnLeave",function()
            hoverGlow:Hide()
            cbd:SetBackdropBorderColor(0,0,0,0)
            RefreshWGCards()
        end)
    end; y=y+130
    local wgSections = {}
    local curLayout = ns.db and ns.db.equipment and ns.db.equipment.layout or "grid_fixed"
    -- 1. EQUIPEMENT
    wgSections[#wgSections+1] = {name="EQUIPEMENT",build=function(c,w)
            local cy=5
            local slots = ns.Providers and ns.Providers.GetAllSlots and ns.Providers:GetAllSlots() or {}
            if #slots == 0 then
                local nd=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(nd,FONT,11)
                nd:SetPoint("TOPLEFT",15,-cy); nd:SetTextColor(unpack(Theme.textDim))
                nd:SetText("Aucun element detecte (equipez trinkets, puis /reload)"); cy=cy+20
            else
                local function onSlotChg() pcall(function() ns.Providers:Refresh() end) end
                local typeOrder = { trinket=1, racial=2, equip=3 }
                local sortedSlots = {}
                for _, slot in ipairs(slots) do sortedSlots[#sortedSlots+1] = slot end
                table.sort(sortedSlots, function(a, b)
                    local sdA = ns.db.equipmentSlots and ns.db.equipmentSlots[a.key]
                    local sdB = ns.db.equipmentSlots and ns.db.equipmentSlots[b.key]
                    local enA = not sdA or sdA.enabled ~= false
                    local enB = not sdB or sdB.enabled ~= false
                    if enA ~= enB then return enA end
                    return (typeOrder[a.type] or 9) < (typeOrder[b.type] or 9)
                end)
                local typeColor = { trinket={0.95,0.85,0.55}, racial={0.78,0.62,0.30}, equip={0.65,0.50,0.20} }
                for _, slot in ipairs(sortedSlots) do
                    local sName = ns.Providers:GetSlotName(slot)
                    local sTex = ns.Providers:GetSlotTexture(slot)
                    if not ns.db.equipmentSlots then ns.db.equipmentSlots = {} end
                    if not ns.db.equipmentSlots[slot.key] then ns.db.equipmentSlots[slot.key] = ns.DeepCopy(ns.SlotDefaults) end
                    local sd = ns.db.equipmentSlots[slot.key]
                    local row=CreateFrame("Frame",nil,c); row:SetSize(w-20,26); row:SetPoint("TOPLEFT",10,-cy)
                    local rBg=row:CreateTexture(nil,"BACKGROUND"); rBg:SetAllPoints(); rBg:SetColorTexture(0,0,0,0)
                    local rx=4
                    local cb=CreateFrame("Button",nil,row); cb:SetSize(14,14); cb:SetPoint("LEFT",rx,0)
                    local cbBg=cb:CreateTexture(nil,"ARTWORK"); cbBg:SetAllPoints()
                    local cbChk=cb:CreateTexture(nil,"OVERLAY"); cbChk:SetSize(10,10); cbChk:SetPoint("CENTER"); cbChk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); cbChk:Hide(); rx=rx+20
                    local ico=row:CreateTexture(nil,"ARTWORK"); ico:SetSize(22,22); ico:SetPoint("LEFT",rx,0); ico:SetTexCoord(TC,1-TC,TC,1-TC)
                    pcall(function() ico:SetTexture(sTex) end); ico:SetDesaturated(sd.desat and true or false); rx=rx+26
                    local nm=row:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(nm,FONT,10)
                    nm:SetPoint("LEFT",rx,0); nm:SetPoint("RIGHT",row,"RIGHT",-130,0); nm:SetJustifyH("LEFT"); nm:SetWordWrap(false)
                    local tc = typeColor[slot.type] or {0.7,0.7,0.7}
                    nm:SetText(string.format("|cff%02x%02x%02x%s|r |cff444444(%s)|r", math.floor(tc[1]*255), math.floor(tc[2]*255), math.floor(tc[3]*255), sName, slot.type or "?"))
                    local function RCB() if sd.enabled~=false then cbBg:SetColorTexture(0.78,0.62,0.30,1); cbChk:Show() else cbBg:SetColorTexture(0.10,0.10,0.14,1); cbChk:Hide() end end; RCB()
                    cb:SetScript("OnClick",function() sd.enabled=not (sd.enabled~=false); RCB(); onSlotChg(); pcall(function() if ns._rebuildCurrentMenu then ns._rebuildCurrentMenu() end end) end)
                    local dBtn=CreateFrame("Button",nil,row); dBtn:SetSize(15,15); dBtn:SetPoint("RIGHT",-4,0)
                    local dBg=dBtn:CreateTexture(nil,"BACKGROUND"); dBg:SetAllPoints()
                    local dIco=dBtn:CreateTexture(nil,"OVERLAY"); dIco:SetAllPoints(); dIco:SetTexCoord(TC,1-TC,TC,1-TC)
                    pcall(function() dIco:SetTexture("Interface\\Icons\\ability_creature_cursed_04") end)
                    local function RD() dIco:SetDesaturated(true); if sd.desat then dBg:SetColorTexture(0.12,0.12,0.22,0.8); dIco:SetAlpha(1); ico:SetDesaturated(true) else dBg:SetColorTexture(0.06,0.06,0.10,0.5); dIco:SetAlpha(0.3); ico:SetDesaturated(false) end end; RD()
                    dBtn:SetScript("OnClick",function() sd.desat=not sd.desat; RD(); onSlotChg() end)
                    dBtn:SetScript("OnEnter",function() dIco:SetAlpha(1); GameTooltip:SetOwner(dBtn,"ANCHOR_TOP"); GameTooltip:SetText("Desaturer l'icone",1,1,1); GameTooltip:Show() end)
                    dBtn:SetScript("OnLeave",function() RD(); GameTooltip:Hide() end)
                    -- Bouton glow fusionné : affiche le type + on/off. Clic gauche = toggle, clic droit = picker
                    -- Style harmonisé avec le menu Sorts (Tactics)
                    local gFus = CreateFrame("Button",nil,row,"BackdropTemplate"); gFus:SetSize(70,16); gFus:SetPoint("RIGHT",dBtn,"LEFT",-6,0)
                    gFus:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1})
                    local gFusTx = gFus:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(gFusTx,FONT,8,"OUTLINE"); gFusTx:SetAllPoints(); gFusTx:SetJustifyH("CENTER")
                    local function RG()
                        local glc = sd.glowColor or ns.barColor
                        if sd.glowEnabled~=false then
                            local gd = ns.GLOW_DEFS or {}
                            local d = gd[sd.glowIdx or 2]
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
                    RG()
                    gFus:RegisterForClicks("LeftButtonUp","RightButtonUp")
                    gFus:SetScript("OnClick",function(_,btn)
                        if btn == "RightButton" then
                            -- Clic droit : ouvre le picker (active le glow si besoin)
                            if not (sd.glowEnabled~=false) then
                                sd.glowEnabled=true
                                if not sd.glowIdx or sd.glowIdx<2 then sd.glowIdx=2 end
                                RG(); onSlotChg()
                            end
                            local defGC = sd.glowColor or ns.barColor
                            local fakeInfo = {name=sName, glow=true, glowIdx=sd.glowIdx or 2, glowAlpha=sd.glowAlpha or 0.7, glowColor={defGC[1],defGC[2],defGC[3]}, glowScale=sd.glowScale or 1.0, procGlowIdx=1, color={defGC[1],defGC[2],defGC[3]}}
                            if ns.OpenGlowPopup then
                                ns.OpenGlowPopup(slot.spellID or slot.itemID or 0, fakeInfo)
                                local syncTicker; syncTicker = C_Timer.NewTicker(0.2, function()
                                    if not panel or not panel._glowPopup or not panel._glowPopup:IsShown() then if syncTicker then syncTicker:Cancel() end; return end
                                    sd.glowIdx=fakeInfo.glowIdx; sd.glowAlpha=fakeInfo.glowAlpha; sd.glowColor=fakeInfo.glowColor; sd.glowScale=fakeInfo.glowScale
                                    RG(); pcall(function() ns.Providers:Refresh() end)
                                end)
                            end
                        else
                            -- Clic gauche : toggle on/off
                            sd.glowEnabled = not (sd.glowEnabled~=false)
                            if (sd.glowEnabled~=false) and (not sd.glowIdx or sd.glowIdx<2) then sd.glowIdx=2 end
                            RG(); onSlotChg()
                        end
                    end)
                    gFus:SetScript("OnEnter",function()
                        local glc = sd.glowColor or ns.barColor
                        gFus:SetBackdropBorderColor(glc[1],glc[2],glc[3],1)
                        GameTooltip:SetOwner(gFus,"ANCHOR_TOP")
                        GameTooltip:SetText((sd.glowEnabled~=false) and "Glow actif" or "Glow desactive",1,1,1)
                        GameTooltip:AddLine("Clic gauche : activer/desactiver", 0.7, 0.7, 0.7)
                        GameTooltip:AddLine("Clic droit : choisir le type", 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    end)
                    gFus:SetScript("OnLeave",function() RG(); GameTooltip:Hide() end)
                    row:EnableMouse(true); row:SetScript("OnEnter",function() rBg:SetColorTexture(1,1,1,0.02) end)
                    row:SetScript("OnLeave",function() rBg:SetColorTexture(0,0,0,0) end)
                    cy=cy+28
                end
            end
            c:SetHeight(cy+5) end}
    -- 2. POSITION & TAILLE
    if curLayout == "grid_fixed" then
        wgSections[#wgSections+1] = {name="POSITION & TAILLE",build=function(c,w) local cy=0; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local cf = ns.db and ns.db.equipment or {}
            local s1=SW.CreateSlider(c,"Position X",-1000,1000,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(cf.groupX or -167)
            s1.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupX=v end; pcall(function() ns.Providers:Layout() end) end
            local s2=SW.CreateSlider(c,"Position Y",-1000,1000,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(cf.groupY or -188)
            s2.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupY=v end; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
            local s3=SW.CreateSlider(c,"Largeur icone",10,80,1,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(cf.groupW or 31)
            s3.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupW=v end; pcall(function() ns.Providers:Layout() end) end
            local s4=SW.CreateSlider(c,"Hauteur icone",10,80,1,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(cf.groupH or 25)
            s4.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupH=v end; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
            local s5=SW.CreateSlider(c,"Espacement",0,20,1,slW); s5:SetPoint("TOPLEFT",ox,-cy); s5:SetValue(cf.groupGap or 3)
            s5.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupGap=v end; pcall(function() ns.Providers:Layout() end) end
            local s6=SW.CreateSlider(c,"Opacite",0,1,0.05,slW); s6:SetPoint("TOPLEFT",ox+slW+gap,-cy); s6:SetValue(cf.groupAlpha or 1.0)
            s6.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupAlpha=v end; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
            local growOpts={{value="RIGHT",text="Droite"},{value="LEFT",text="Gauche"},{value="DOWN",text="Bas"},{value="UP",text="Haut"}}
            local gdd=SW.CreateDropdown(c,"Empilement",growOpts,w-30); gdd:SetPoint("TOPLEFT",15,-cy)
            gdd:SetValue(cf.groupGrowth or "RIGHT")
            gdd.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.groupGrowth=v end; pcall(function() ns.Providers:Layout() end) end
            cy=cy+50; c:SetHeight(cy) end}
    else
        wgSections[#wgSections+1] = {name="POSITION & TAILLE",build=function(c,w) local cy=0; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
            local info=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(info,FONT,9)
            info:SetPoint("TOPLEFT",15,-cy); info:SetTextColor(unpack(Theme.textDim))
            info:SetText("Alt+Drag pour deplacer individuellement"); cy=cy+18
            local slots = ns.Providers and ns.Providers.GetAllSlots and ns.Providers:GetAllSlots() or {}
            local typeColor = { trinket={0.95,0.85,0.55}, racial={0.78,0.62,0.30}, equip={0.65,0.50,0.20} }
            for _, slot in ipairs(slots) do
                if not ns.db.equipmentSlots then ns.db.equipmentSlots = {} end
                if not ns.db.equipmentSlots[slot.key] then ns.db.equipmentSlots[slot.key] = ns.DeepCopy(ns.SlotDefaults) end
                local sd = ns.db.equipmentSlots[slot.key]
                if sd.enabled ~= false then
                    local sName = ns.Providers:GetSlotName(slot)
                    local sTex = ns.Providers:GetSlotTexture(slot)
                    local tc = typeColor[slot.type] or {0.7,0.7,0.7}
                    local hdr=CreateFrame("Frame",nil,c); hdr:SetSize(w-20,20); hdr:SetPoint("TOPLEFT",10,-cy)
                    local hIco=hdr:CreateTexture(nil,"ARTWORK"); hIco:SetSize(16,16); hIco:SetPoint("LEFT",0,0); hIco:SetTexCoord(TC,1-TC,TC,1-TC)
                    pcall(function() hIco:SetTexture(sTex) end)
                    local hLbl=hdr:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(hLbl,FONT,10); hLbl:SetPoint("LEFT",20,0); hLbl:SetJustifyH("LEFT")
                    hLbl:SetText(string.format("|cff%02x%02x%02x%s|r", math.floor(tc[1]*255), math.floor(tc[2]*255), math.floor(tc[3]*255), sName)); cy=cy+22
                    local s1=SW.CreateSlider(c,"Position X",-1000,1000,1,slW); s1:SetPoint("TOPLEFT",ox,-cy); s1:SetValue(sd.x or 0)
                    s1.onChanged=function(v) sd.x=v; pcall(function() ns.Providers:Layout() end) end
                    local s2=SW.CreateSlider(c,"Position Y",-1000,1000,1,slW); s2:SetPoint("TOPLEFT",ox+slW+gap,-cy); s2:SetValue(sd.y or -188)
                    s2.onChanged=function(v) sd.y=v; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
                    local s3=SW.CreateSlider(c,"Largeur",10,80,1,slW); s3:SetPoint("TOPLEFT",ox,-cy); s3:SetValue(sd.w or 31)
                    s3.onChanged=function(v) sd.w=v; pcall(function() ns.Providers:Layout() end) end
                    local s4=SW.CreateSlider(c,"Hauteur",10,80,1,slW); s4:SetPoint("TOPLEFT",ox+slW+gap,-cy); s4:SetValue(sd.h or 25)
                    s4.onChanged=function(v) sd.h=v; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
                    local s5=SW.CreateSlider(c,"Opacite",0,1,0.05,slW); s5:SetPoint("TOPLEFT",ox,-cy); s5:SetValue(sd.alpha or 1.0)
                    s5.onChanged=function(v) sd.alpha=v; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
                end
            end
            c:SetHeight(math.max(cy, 20)) end}
    end
    -- 3. BORDURE (lit à la volée depuis la DB)
    wgSections[#wgSections+1] = {name="BORDURE",build=function(c,w) local cy=0; local slW=math.min(260,w/2-20); local gap=20; local ox=math.max(5,(w-slW*2-gap)/2)
        local cf = ns.db and ns.db.equipment or {}
        local borderOpts={{value="square",text="Carre"},{value="none",text="Aucun"}}
        local bdd=SW.CreateDropdown(c,"Style",borderOpts,slW); bdd:SetPoint("TOPLEFT",ox,-cy)
        bdd:SetValue(cf.borderStyle or "square")
        bdd.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.borderStyle=v end; pcall(function() ns.Providers:Layout() end) end
        local brs=SW.CreateSlider(c,"Epaisseur",1,6,1,slW); brs:SetPoint("TOPLEFT",ox+slW+gap,-cy)
        brs:SetValue(cf.borderWidth or 2)
        brs.onChanged=function(v) if ns.db and ns.db.equipment then ns.db.equipment.borderWidth=v end; pcall(function() ns.Providers:Layout() end) end; cy=cy+60
        local curBC = cf.borderColor or {0.055, 0.055, 0.055, 1}
        local cc=SW.CreateColorButton(c,"Couleur bordure",w-30); cc:SetPoint("TOPLEFT",15,-cy)
        cc:SetColor(curBC[1], curBC[2], curBC[3])
        cc.onChanged=function(col) if ns.db and ns.db.equipment then ns.db.equipment.borderColor={col[1],col[2],col[3],0.8} end; pcall(function() ns.Providers:Layout() end) end
        cy=cy+30; c:SetHeight(cy) end}
    SW.CreateSectionStack(p, wgSections, cw, y)
    -- Flag de preview : actif uniquement quand le menu est réellement affiché
    p:SetScript("OnShow", function() ns._equipmentPreview = true; pcall(function() ns.Providers:Refresh() end) end)
    p:SetScript("OnHide", function() ns._equipmentPreview = false; pcall(function() ns.Providers:Refresh() end) end)
end

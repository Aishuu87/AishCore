-- AishUIAura/UI/SharedWidgets.lua
-- Widgets — ASCII arrows (v / >) — zero encoding issues
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local SW = {}
ns.SharedWidgets = SW
local Theme = ns.THEME
local CreateFrame, math = CreateFrame, math
local FONT = ns.Media.font

local function ApplyBD(f, bg, edge)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}})
    f:SetBackdropColor(bg[1],bg[2],bg[3],bg[4] or 1)
    f:SetBackdropBorderColor(edge[1],edge[2],edge[3],edge[4] or 0.8)
end

------------------------------------------------------------------------
-- CHECKBOX (12x12)
------------------------------------------------------------------------
function SW.CreateCheckbox(parent, label, width)
    width = width or 260
    local row = CreateFrame("Button",nil,parent); row:SetSize(width,26)
    row.box = row:CreateTexture(nil,"ARTWORK"); row.box:SetSize(12,12)
    row.box:SetPoint("LEFT",8,0); row.box:SetColorTexture(unpack(Theme.checkboxOff))
    row.check = row:CreateTexture(nil,"OVERLAY"); row.check:SetSize(10,10)
    row.check:SetPoint("CENTER",row.box); row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check"); row.check:Hide()
    row.label = row:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(row.label,FONT,12)
    row.label:SetPoint("LEFT",row.box,"RIGHT",6,0); row.label:SetTextColor(unpack(Theme.textNormal)); row.label:SetText(label or "")
    row.checked = false
    function row:SetChecked(v) self.checked=v
        if v then self.box:SetColorTexture(unpack(Theme.checkboxOn)); self.check:Show()
        else self.box:SetColorTexture(unpack(Theme.checkboxOff)); self.check:Hide() end end
    function row:GetChecked() return self.checked end
    row:SetScript("OnEnter",function(s) s.label:SetTextColor(1,1,1) end)
    row:SetScript("OnLeave",function(s) s.label:SetTextColor(unpack(Theme.textNormal)) end)
    row:SetScript("OnClick",function(s) s:SetChecked(not s.checked); if s.onChanged then s.onChanged(s.checked) end end)
    return row
end

------------------------------------------------------------------------
-- SLIDER
------------------------------------------------------------------------
function SW.CreateSlider(parent, label, minVal, maxVal, step, width)
    width = math.min(width or 260,300); minVal=minVal or 0; maxVal=maxVal or 100; step=step or 1
    local dec = step<1 and math.max(1,math.ceil(-math.log10(step+1e-9))) or 0; local fmt = "%."..dec.."f"
    local c = CreateFrame("Frame",nil,parent); c:SetSize(width,56)
    c.label = c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(c.label,FONT,11)
    c.label:SetPoint("TOP",0,-1); c.label:SetTextColor(unpack(Theme.textNormal)); c.label:SetText(label or "")
    local sl = CreateFrame("Slider",nil,c); sl:SetSize(width-10,14); sl:SetPoint("TOP",c.label,"BOTTOM",0,-4)
    sl:SetMinMaxValues(minVal,maxVal); sl:SetValueStep(step); sl:SetObeyStepOnDrag(true); sl:SetOrientation("HORIZONTAL")
    local tr = sl:CreateTexture(nil,"BACKGROUND"); tr:SetPoint("LEFT"); tr:SetPoint("RIGHT"); tr:SetHeight(5); tr:SetColorTexture(unpack(Theme.sliderTrack))
    -- Circular white thumb (Circle_Smooth2)
    local th = sl:CreateTexture(nil,"ARTWORK"); th:SetSize(14,14)
    th:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\Wheel\\Circle_Smooth2")
    th:SetVertexColor(1, 1, 1, 1)
    sl:SetThumbTexture(th)
    local mnT = c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(mnT,FONT,9); mnT:SetPoint("TOPLEFT",sl,"BOTTOMLEFT",0,-2)
    mnT:SetTextColor(unpack(Theme.textDim)); mnT:SetText(string.format(fmt,minVal))
    local mxT = c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(mxT,FONT,9); mxT:SetPoint("TOPRIGHT",sl,"BOTTOMRIGHT",0,-2)
    mxT:SetTextColor(unpack(Theme.textDim)); mxT:SetText(string.format(fmt,maxVal))
    local eb = CreateFrame("EditBox",nil,c); eb:SetSize(48,16); eb:SetPoint("TOP",sl,"BOTTOM",0,-2); eb:SetAutoFocus(false)
    ns.ApplyFont(eb,FONT,10,""); eb:SetTextColor(1,1,1); eb:SetJustifyH("CENTER")
    local eBg = eb:CreateTexture(nil,"BACKGROUND"); eBg:SetPoint("TOPLEFT",-3,1); eBg:SetPoint("BOTTOMRIGHT",3,-1); eBg:SetColorTexture(0.06,0.06,0.08,0.9)
    local eBd = CreateFrame("Frame",nil,eb,"BackdropTemplate"); eBd:SetPoint("TOPLEFT",-3,1); eBd:SetPoint("BOTTOMRIGHT",3,-1)
    eBd:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}); eBd:SetBackdropBorderColor(unpack(Theme.border))
    c.slider=sl; c.editBox=eb; c.currentValue=minVal
    local function Snap(v) v=math.max(minVal,math.min(maxVal,v)); if step>0 then v=math.floor((v-minVal)/step+0.5)*step+minVal end; return tonumber(string.format(fmt,v)) end
    function c:SetValue(v) v=Snap(v); self.currentValue=v; self._p=true; self.slider:SetValue(v); self._p=nil; self.editBox:SetText(string.format(fmt,v)) end
    function c:GetValue() return self.currentValue end
    sl:SetScript("OnValueChanged",function(_,v) if c._p then return end; v=Snap(v); c.currentValue=v; eb:SetText(string.format(fmt,v)); if c.onChanged then c.onChanged(v) end end)
    eb:SetScript("OnEnterPressed",function(s) local v=tonumber(s:GetText()); if v then c:SetValue(v); if c.onChanged then c.onChanged(c.currentValue) end end; s:ClearFocus() end)
    eb:SetScript("OnEscapePressed",function(s) s:ClearFocus() end); return c
end

------------------------------------------------------------------------
-- DROPDOWN
------------------------------------------------------------------------
function SW.CreateDropdown(parent, label, options, width)
    width = width or 260; local c = CreateFrame("Frame",nil,parent); c:SetSize(width,label and 42 or 22); c._options=options or {}
    if label then c.label=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(c.label,FONT,11); c.label:SetPoint("TOPLEFT")
        c.label:SetTextColor(unpack(Theme.textNormal)); c.label:SetText(label) end
    local btn=CreateFrame("Button",nil,c,"BackdropTemplate"); btn:SetSize(width,22); btn:SetPoint("TOPLEFT",0,label and -18 or 0)
    ApplyBD(btn,{0.12,0.12,0.14,1},Theme.border)
    btn.text=btn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(btn.text,FONT,10); btn.text:SetPoint("LEFT",6,0); btn.text:SetPoint("RIGHT",-20,0)
    btn.text:SetJustifyH("LEFT"); btn.text:SetTextColor(1,1,1)
    local ar=btn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(ar,FONT,9); ar:SetPoint("RIGHT",-6,0); ar:SetText("v"); ar:SetTextColor(unpack(Theme.textDim))
    -- Conteneur de menu avec scroll
    local menu=CreateFrame("Frame",nil,btn,"BackdropTemplate"); menu:SetFrameStrata("TOOLTIP"); menu:Hide()
    ApplyBD(menu,{0.08,0.08,0.10,0.97},Theme.border)
    local sf=CreateFrame("ScrollFrame",nil,menu,"UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",2,-2); sf:SetPoint("BOTTOMRIGHT",-18,2)
    local sc=CreateFrame("Frame",nil,sf); sc:SetWidth(width-22); sf:SetScrollChild(sc)
    -- Hide ugly default scrollbar styling
    if sf.ScrollBar then
        if sf.ScrollBar.ScrollUpButton then sf.ScrollBar.ScrollUpButton:SetAlpha(0) end
        if sf.ScrollBar.ScrollDownButton then sf.ScrollBar.ScrollDownButton:SetAlpha(0) end
    end
    c.currentValue=nil; c._btn=btn; c._menu=menu
    local function Close() menu:Hide() end
    local function Build()
        for _,ch in pairs({sc:GetChildren()}) do ch:Hide() end
        local totalH = #c._options * 20 + 4
        local maxH = math.min(totalH, 300)
        menu:SetSize(width, maxH); menu:ClearAllPoints(); menu:SetPoint("TOPLEFT",btn,"BOTTOMLEFT",0,-1)
        sc:SetHeight(totalH)
        local yOff=2
        for _,opt in ipairs(c._options) do
            local item=CreateFrame("Button",nil,sc); item:SetSize(width-22,20); item:SetPoint("TOPLEFT",0,-yOff)
            local iBg=item:CreateTexture(nil,"BACKGROUND"); iBg:SetAllPoints(); iBg:SetColorTexture(0,0,0,0)
            local iTx=item:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(iTx,FONT,10); iTx:SetPoint("LEFT",6,0)
            iTx:SetTextColor(unpack(Theme.textNormal)); iTx:SetText(opt.text or tostring(opt.value))
            item:SetScript("OnEnter",function() iBg:SetColorTexture(unpack(Theme.rowHover)); iTx:SetTextColor(1,1,1) end)
            item:SetScript("OnLeave",function() iBg:SetColorTexture(0,0,0,0); iTx:SetTextColor(unpack(Theme.textNormal)) end)
            item:SetScript("OnClick",function() c.currentValue=opt.value; btn.text:SetText(opt.text or tostring(opt.value)); Close()
                if c.onChanged then c.onChanged(opt.value) end end)
            yOff=yOff+20
        end
    end
    function c:SetOptions(opts) self._options=opts or {}; Build() end
    function c:SetValue(v) self.currentValue=v; for _,opt in ipairs(self._options) do
        if opt.value==v then btn.text:SetText(opt.text or tostring(v)); return end end; btn.text:SetText(tostring(v or "")) end
    function c:GetValue() return self.currentValue end
    btn:SetScript("OnClick",function() if menu:IsShown() then Close() else Build(); menu:Show() end end)
    btn:SetScript("OnEnter",function(s) s:SetBackdropColor(0.16,0.16,0.18,1) end)
    btn:SetScript("OnLeave",function(s) s:SetBackdropColor(0.12,0.12,0.14,1) end); Build(); return c
end

------------------------------------------------------------------------
-- COLOR BUTTON
------------------------------------------------------------------------
function SW.CreateColorButton(parent, label, width)
    width = width or 260; local c=CreateFrame("Frame",nil,parent); c:SetSize(width,26)
    c.label=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(c.label,FONT,11); c.label:SetPoint("LEFT",8,0)
    c.label:SetTextColor(unpack(Theme.textNormal)); c.label:SetText(label or "")
    local sw=CreateFrame("Button",nil,c); sw:SetSize(20,20); sw:SetPoint("RIGHT",-8,0)
    local sc=sw:CreateTexture(nil,"ARTWORK"); sc:SetAllPoints(); sc:SetColorTexture(1,1,1)
    local sb=sw:CreateTexture(nil,"BORDER"); sb:SetPoint("TOPLEFT",-1,1); sb:SetPoint("BOTTOMRIGHT",1,-1); sb:SetColorTexture(unpack(Theme.border))
    c.currentColor={1,1,1}
    function c:SetColor(r,g,b) self.currentColor={r or 1,g or 1,b or 1}; sc:SetColorTexture(r or 1,g or 1,b or 1) end
    sw:SetScript("OnClick",function() local r,g,b=unpack(c.currentColor)
        ColorPickerFrame:SetupColorPickerAndShow({r=r,g=g,b=b,
        swatchFunc=function() local nr,ng,nb=ColorPickerFrame:GetColorRGB(); c:SetColor(nr,ng,nb); if c.onChanged then c.onChanged({nr,ng,nb}) end end,
        cancelFunc=function(p) if p then c:SetColor(p.r,p.g,p.b); if c.onChanged then c.onChanged(c.currentColor) end end end}) end)
    return c
end

------------------------------------------------------------------------
-- SECTION HEADER (WoW-style: 2 class color dots + label + gradient hairline)
-- Inspired by ornate WoW addon section dividers.
------------------------------------------------------------------------
function SW.CreateSectionHeader(parent, text, width)
    width = width or 260
    local f = CreateFrame("Frame",nil,parent); f:SetSize(width, 24)
    local g = Theme.gold or {0.78, 0.62, 0.30}
    -- Single gold dot in front
    local dot1 = f:CreateTexture(nil,"OVERLAY")
    dot1:SetSize(7,7); dot1:SetPoint("LEFT",2,0)
    dot1:SetTexture("Interface\\AddOns\\Aishaddon\\Media\\Wheel\\circleflat2")
    dot1:SetVertexColor(g[1],g[2],g[3],1)
    -- Label
    local lbl = f:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lbl,FONT,11)
    lbl:SetPoint("LEFT",14,0)
    lbl:SetTextColor(unpack(Theme.textNormal))
    lbl:SetText((text or ""):upper())
    -- Gold gradient hairline
    local line = f:CreateTexture(nil,"ARTWORK"); line:SetHeight(1)
    line:SetPoint("LEFT", lbl,"RIGHT", 10, 0); line:SetPoint("RIGHT",-2,0)
    line:SetColorTexture(1,1,1,1)
    pcall(function()
        if CreateColor then
            line:SetGradient("HORIZONTAL",
                CreateColor(g[1],g[2],g[3],0.85),
                CreateColor(g[1]*0.20, g[2]*0.20, g[3]*0.20, 0.10))
        end
    end)
    return f
end

------------------------------------------------------------------------
-- TOGGLE (labeled ON/OFF pill in gold)
------------------------------------------------------------------------
function SW.CreateToggle(parent, width)
    width = width or 40; local h = 18
    local f = CreateFrame("Button",nil,parent,"BackdropTemplate"); f:SetSize(width, h)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",
        edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
    local g = Theme.gold or {0.78, 0.62, 0.30}
    -- Label dans la pilule (ON / OFF)
    local lbl = f:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lbl,FONT,9)
    lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
    f._lbl = lbl; f._on = false
    local function Ref()
        if f._on then
            f:SetBackdropColor(g[1], g[2], g[3], 0.95)
            f:SetBackdropBorderColor(g[1]*0.6, g[2]*0.6, g[3]*0.4, 1)
            lbl:SetText("ON")
            lbl:SetTextColor(0.05, 0.05, 0.05, 1)
        else
            f:SetBackdropColor(0.06, 0.06, 0.07, 1)
            f:SetBackdropBorderColor(g[1]*0.55, g[2]*0.55, g[3]*0.45, 0.85)
            lbl:SetText("OFF")
            lbl:SetTextColor(g[1]*0.85, g[2]*0.85, g[3]*0.85, 1)
        end
    end
    Ref()
    function f:SetValue(v) self._on = v and true or false; Ref() end
    function f:GetValue() return self._on end
    f:SetScript("OnClick",function(s) s._on = not s._on; Ref()
        if s.onChanged then s.onChanged(s._on) end end)
    f:SetScript("OnEnter",function(s)
        if s._on then
            s:SetBackdropColor(g[1]*1.10, g[2]*1.10, g[3]*1.10, 1)
        else
            s:SetBackdropBorderColor(g[1], g[2], g[3], 1)
        end
    end)
    f:SetScript("OnLeave",function() Ref() end)
    return f
end

------------------------------------------------------------------------
-- SECTION ROUTER (Apple-style: minimal dropdown above swap content)
-- Replaces stacked accordions. Same input shape so call sites stay intact.
------------------------------------------------------------------------
function SW.CreateAccordionStack(parent, sections, cw, startY)
    startY = startY or 0
    local W = cw - 20
    local wrap = CreateFrame("Frame",nil,parent)
    wrap:SetPoint("TOPLEFT",10,-startY); wrap:SetPoint("TOPRIGHT",-10,-startY)
    wrap:SetHeight(60)

    local opts = {}
    for i,sec in ipairs(sections) do
        opts[i] = { value = i, text = (sec.name or ("SECTION "..i)) }
    end

    -- Petit label en majuscules au-dessus du dropdown (style groupe Apple settings)
    -- Le label est mis a jour dynamiquement avec la categorie de la section selectionnee.
    -- Format : "SECTION - <CATEGORIE>" si la section a un champ `category`, sinon "SECTION".
    local title = wrap:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(title,FONT,10)
    title:SetPoint("TOPLEFT",2,-2); title:SetTextColor(unpack(Theme.textDim))
    title:SetText("SECTION")
    local function UpdateTitle(i)
        local sec = sections[i]
        if sec and sec.category and sec.category ~= "" then
            title:SetText("SECTION - "..sec.category)
        else
            title:SetText("SECTION")
        end
    end

    -- Dropdown directement sous le label, sans carte autour
    local dd = SW.CreateDropdown(wrap, nil, opts, W)
    dd:SetPoint("TOPLEFT",0,-18)

    -- Séparateur fin sous le dropdown
    local sep = wrap:CreateTexture(nil,"OVERLAY"); sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",0,-50); sep:SetPoint("TOPRIGHT",0,-50)
    sep:SetColorTexture(Theme.separator[1],Theme.separator[2],Theme.separator[3],0.5)

    -- Content area below
    local content = CreateFrame("Frame",nil,wrap)
    content:SetPoint("TOPLEFT",0,-60); content:SetPoint("TOPRIGHT",0,-60)
    content:SetHeight(1)

    local built = {}
    local current = nil
    local function ShowSection(i)
        if current == i then return end
        if current and built[current] then built[current]:Hide() end
        current = i
        UpdateTitle(i)
        local sub = built[i]
        if not sub then
            sub = CreateFrame("Frame",nil,content)
            sub:SetPoint("TOPLEFT"); sub:SetPoint("TOPRIGHT"); sub:SetHeight(1)
            local ok, err = pcall(sections[i].build, sub, W)
            if not ok then
                local e = sub:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(e,FONT,10)
                e:SetPoint("TOPLEFT",10,-10); e:SetTextColor(1,0.4,0.4)
                e:SetText("Build error: "..tostring(err))
                sub:SetHeight(30)
            end
            built[i] = sub
        end
        sub:Show()
        local h = math.max(20, sub:GetHeight())
        content:SetHeight(h)
        wrap:SetHeight(60 + h + 16)
        parent:SetHeight((startY or 0) + wrap:GetHeight() + 20)
    end
    dd.onChanged = function(v) ShowSection(v) end
    dd:SetValue(1); ShowSection(1)
    return wrap
end

------------------------------------------------------------------------
-- SECTION STACK : empile toutes les sections verticalement, chacune
-- precedee d'un CreateSectionHeader (divider + titre uppercase + filet or).
-- Remplace CreateAccordionStack pour les menus sans selecteur deroulant.
------------------------------------------------------------------------
function SW.CreateSectionStack(parent, sections, cw, startY)
    startY = startY or 0
    local W = cw - 20
    local wrap = CreateFrame("Frame",nil,parent)
    wrap:SetPoint("TOPLEFT",10,-startY); wrap:SetPoint("TOPRIGHT",-10,-startY)
    wrap:SetHeight(1)

    local y = 0
    for i, sec in ipairs(sections) do
        if i > 1 then y = y + 18 end
        local hdr = SW.CreateSectionHeader(wrap, sec.name or ("SECTION "..i), W)
        hdr:SetPoint("TOPLEFT",0,-y)
        y = y + hdr:GetHeight() + 10

        local sub = CreateFrame("Frame",nil,wrap)
        sub:SetPoint("TOPLEFT",0,-y); sub:SetPoint("TOPRIGHT",0,-y); sub:SetHeight(1)
        local ok, err = pcall(sec.build, sub, W)
        if not ok then
            local e = sub:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(e,FONT,10)
            e:SetPoint("TOPLEFT",10,-10); e:SetTextColor(1,0.4,0.4)
            e:SetText("Build error: "..tostring(err))
            sub:SetHeight(30)
        end
        y = y + math.max(20, sub:GetHeight())
    end

    wrap:SetHeight(y)
    parent:SetHeight(startY + y + 20)
    return wrap
end

------------------------------------------------------------------------
-- ACTION BUTTON
------------------------------------------------------------------------
function SW.CreateActionBtn(parent, text, width, bgColor, borderColor, textColor)
    width=width or 160; local btn=CreateFrame("Button",nil,parent,"BackdropTemplate"); btn:SetSize(width,24)
    ApplyBD(btn, bgColor or {0.08,0.08,0.12}, borderColor or Theme.border)
    local lbl=btn:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lbl,FONT,11); lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
    if textColor then lbl:SetTextColor(textColor[1],textColor[2],textColor[3]) else lbl:SetTextColor(1,1,1) end
    lbl:SetText(text or ""); btn._lbl=lbl; return btn
end

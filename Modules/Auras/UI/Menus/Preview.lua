-- AishUIAura/UI/Menus/Preview.lua
-- Preview controls for renders + frames externes
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

function ns.SettingsPanel.BuildPreviewMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font

    local renderMap={
        {name=L["AURASMENU_PREVIEW_RENDER_ICONLIST"],key="iconlist",cfg=function() return ns.db and ns.db.iconlist end},
        {name=L["AURASMENU_PREVIEW_RENDER_CIRCLE_BARS"],key="freebars",cfg=function() return ns.db and ns.db.freebars end},
        {name=L["AURASMENU_PREVIEW_RENDER_FREE_BARS"],key="circlebars",cfg=function() return ns.db and ns.db.circlebars end},
        {name=L["AURASMENU_PREVIEW_RENDER_ICONS"],key="icons",cfg=function() return ns.db and ns.db.icons end},
        {name=L["AURASMENU_PREVIEW_RENDER_EQUIPMENT"],key="equipment",cfg=function() return ns.db and ns.db.equipment end},
    }
    SW.CreateAccordionStack(p,{
    {name=L["AURASMENU_PREVIEW_SECTION_PLACEHOLDERS"],build=function(c,w) local py=-5
        for _,rm in ipairs(renderMap) do
            local lbl=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lbl,FONT,12); lbl:SetPoint("TOPLEFT",5,py); lbl:SetTextColor(unpack(Theme.textNormal)); lbl:SetText(rm.name)
            local tog=SW.CreateToggle(c); tog:SetPoint("TOPRIGHT",-90,py+2); tog:SetValue(true)
            tog.onChanged=function(v)
                pcall(function()
                    local gfx = ns.renderFrames and ns.renderFrames[rm.key]
                    if gfx and gfx.container then
                        if v then gfx.container:SetAlpha(1) else gfx.container:SetAlpha(0) end
                    end
                    -- War Gear
                    if rm.key == "equipment" and ns.Providers then
                        if v then pcall(function() ns.Providers:Refresh() end)
                        else
                            local slots = ns.Providers.GetAllSlots and ns.Providers:GetAllSlots() or {}
                            for _,s in ipairs(slots) do
                                local f = _G["AishWG_"..s.key:gsub(":","_")]
                                if f then f:SetAlpha(0) end
                            end
                        end
                    end
                end)
            end
            local btn=SW.CreateActionBtn(c,L["AURASMENU_PREVIEW_RECENTER"],70,{0.05,0.05,0.06},{0.78,0.62,0.30,0.55},{0.78,0.62,0.30})
            btn:SetSize(70,18); btn:SetPoint("TOPRIGHT",-5,py+1)
            btn:SetScript("OnClick",function()
                local cfg=rm.cfg(); if not cfg then return end
                if rm.key=="equipment" then cfg.groupX=0; cfg.groupY=0
                else cfg.x=0; cfg.y=0 end
                pcall(ns.RebuildDisplay)
            end)
            py=py-30 end
        local btnAll=SW.CreateActionBtn(c,L["AURASMENU_PREVIEW_RECENTER_ALL"],100,{0.05,0.05,0.06},{0.78,0.62,0.30,0.55},{0.78,0.62,0.30})
        btnAll:SetSize(100,20); btnAll:SetPoint("TOPLEFT",5,py-5)
        btnAll:SetScript("OnClick",function()
            for _,rm in ipairs(renderMap) do
                local cfg=rm.cfg(); if cfg then
                    if rm.key=="equipment" then cfg.groupX=0; cfg.groupY=0
                    else cfg.x=0; cfg.y=0 end
                end
            end
            pcall(ns.RebuildDisplay)
        end)
        c:SetHeight(-py+30) end},
    {name=L["AURASMENU_PREVIEW_SECTION_AISHUI"],build=function(c,w)
        local lbl=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(lbl,FONT,11); lbl:SetPoint("TOPLEFT",5,-8)
        lbl:SetTextColor(unpack(Theme.textNormal)); lbl:SetText(L["AURASMENU_PREVIEW_TOGGLE_LABEL"])
        local tog=SW.CreateToggle(c); tog:SetPoint("TOPRIGHT",-5,-6); tog:SetValue(ns._aishPreviewOn or false)
        tog.onChanged=function(v)
            ns._aishPreviewOn = v
            pcall(function()
                if v then
                    if SlashCmdList["AISHADDON"] then SlashCmdList["AISHADDON"]("") end
                    C_Timer.After(0.15, function()
                        if AishaddonSettingsPanel then
                            -- Move off-screen so it doesn't capture clicks
                            ns._aishPanelPoint = {AishaddonSettingsPanel:GetPoint(1)}
                            AishaddonSettingsPanel:ClearAllPoints()
                            AishaddonSettingsPanel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5, -5)
                        end
                    end)
                else
                    if AishaddonSettingsPanel then
                        -- Restore position and close
                        if ns._aishPanelPoint then
                            AishaddonSettingsPanel:ClearAllPoints()
                            AishaddonSettingsPanel:SetPoint(unpack(ns._aishPanelPoint))
                            ns._aishPanelPoint = nil
                        end
                        AishaddonSettingsPanel:Hide()
                    end
                end
            end)
        end
        local info=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(info,FONT,9); info:SetPoint("TOPLEFT",5,-28)
        info:SetTextColor(0.39,0.35,0.31); info:SetText(L["AURASMENU_PREVIEW_TOGGLE_HINT"]); c:SetHeight(42) end},
},cw,0)
end

-- AishUIAura/UI/Menus/Profiles.lua
-- Profile management: active profile, create, export/import
------------------------------------------------------------------------
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local L = _addon.L
ns.SettingsPanel = ns.SettingsPanel or {}

function ns.SettingsPanel.BuildProfilesMenu(p, cw)
    local SW = ns.SharedWidgets
    local Theme = ns.THEME
    local FONT = ns.Media.font

    SW.CreateAccordionStack(p,{
    {name=L["AURASMENU_PROFILES_SECTION_ACTIVE_PROFILE"],build=function(c,w)
        local Prof=ns.Profiles; local list=(Prof and Prof.GetList) and Prof:GetList() or {"Default"}
        local opts={}; for _,n in ipairs(list) do opts[#opts+1]={value=n,text=n} end
        local dd=SW.CreateDropdown(c,nil,opts,w-10); dd:SetPoint("TOPLEFT",5,-5)
        dd:SetValue((Prof and Prof.GetActive) and Prof:GetActive() or "Default")
        dd.onChanged=function(v) if Prof and Prof.SetActive then Prof:SetActive(v) end end
        local delBtn=SW.CreateActionBtn(c,L["AURASMENU_PROFILES_BTN_DELETE_PROFILE"],160,{0.25,0.08,0.08},{0.45,0.15,0.15},{0.86,0.39,0.39})
        delBtn:SetPoint("TOPLEFT",5,-40); delBtn:SetScript("OnClick",function()
            local cur=Prof and Prof:GetActive() or "Default"
            if cur=="Default" then print("|cff00b0ffAishUIAura|r: "..L["AURASMENU_PROFILES_MSG_CANNOT_DELETE_DEFAULT"]) return end
            if Prof and Prof.Delete then Prof:Delete(cur) end end)
        c:SetHeight(70) end},
    {name=L["AURASMENU_PROFILES_SECTION_CREATE_PROFILE"],build=function(c,w)
        local eb=CreateFrame("EditBox",nil,c); eb:SetSize(w-80,-1); eb:SetHeight(20); eb:SetPoint("TOPLEFT",5,-5); eb:SetAutoFocus(false)
        ns.ApplyFont(eb,FONT,11); eb:SetTextColor(1,1,1); eb:SetJustifyH("LEFT")
        local eBg=eb:CreateTexture(nil,"BACKGROUND"); eBg:SetPoint("TOPLEFT",-2,2); eBg:SetPoint("BOTTOMRIGHT",2,-2); eBg:SetColorTexture(0.06,0.06,0.08,0.9)
        local btn=SW.CreateActionBtn(c,L["AURASMENU_PROFILES_BTN_CREATE"],60,{0.08,0.25,0.12},{0.15,0.45,0.20},{0.39,0.86,0.39})
        btn:SetPoint("TOPRIGHT",-5,-5); btn:SetScript("OnClick",function()
            local name=eb:GetText(); if name and name~="" then
                if ns.Profiles and ns.Profiles.Create then ns.Profiles:Create(name); print("|cff00b0ffAishUIAura|r: "..string.format(L["AURASMENU_PROFILES_MSG_PROFILE_CREATED"], name)) end
            end; eb:SetText(""); eb:ClearFocus() end)
        eb:SetScript("OnEnterPressed",function(s) btn:GetScript("OnClick")(); s:ClearFocus() end)
        eb:SetScript("OnEscapePressed",function(s) s:ClearFocus() end)
        c:SetHeight(30) end},
    {name=L["AURASMENU_PROFILES_SECTION_EXPORT_IMPORT"],build=function(c,w)
        local Prof=ns.Profiles
        -- Status label
        local status=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(status,FONT,9)
        status:SetPoint("TOPLEFT",5,-5); status:SetWidth(w-10); status:SetJustifyH("LEFT"); status:SetWordWrap(true)
        local function SetStatus(msg,r,g,b) status:SetTextColor(r or 0.8,g or 0.8,b or 0.8); status:SetText(msg or "") end

        -- Check libs
        if Prof and not Prof:HasLibs() then
            SetStatus(L["AURASMENU_PROFILES_MSG_LIBS_MISSING"],1,0.4,0.3)
        else SetStatus("") end

        -- Dropdown : choix du profil à exporter
        local list=(Prof and Prof.GetList) and Prof:GetList() or {"Default"}
        local expOpts={}; for _,n in ipairs(list) do expOpts[#expOpts+1]={value=n,text=n} end
        local expDD=SW.CreateDropdown(c,L["AURASMENU_PROFILES_LBL_PROFILE_TO_EXPORT"],expOpts,w-120)
        expDD:SetPoint("TOPLEFT",5,-22); expDD:SetValue((Prof and Prof.GetActive) and Prof:GetActive() or "Default")

        local expBtn=SW.CreateActionBtn(c,L["AURASMENU_PROFILES_BTN_EXPORT"],90,{0.08,0.12,0.25},{0.15,0.20,0.45},{0.50,0.70,1.00})
        expBtn:SetPoint("TOPRIGHT",-5,-22)

        -- EditBox for string
        local eb=CreateFrame("EditBox",nil,c); eb:SetSize(w-20,60); eb:SetPoint("TOPLEFT",5,-68); eb:SetAutoFocus(false); eb:SetMultiLine(true)
        ns.ApplyFont(eb,FONT,9); eb:SetTextColor(0.8,0.8,0.8); eb:SetJustifyH("LEFT")
        local eBg=eb:CreateTexture(nil,"BACKGROUND"); eBg:SetAllPoints(); eBg:SetColorTexture(0.04,0.04,0.06,0.9)
        local eBd=CreateFrame("Frame",nil,eb,"BackdropTemplate"); eBd:SetAllPoints()
        eBd:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}); eBd:SetBackdropBorderColor(unpack(Theme.border))

        -- Import target name
        local impLbl=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(impLbl,FONT,9)
        impLbl:SetPoint("TOPLEFT",5,-134); impLbl:SetTextColor(unpack(Theme.textDim)); impLbl:SetText(L["AURASMENU_PROFILES_LBL_IMPORTED_PROFILE_NAME"])
        local impNameEB=CreateFrame("EditBox",nil,c); impNameEB:SetSize(w-120,18); impNameEB:SetPoint("TOPLEFT",5,-148); impNameEB:SetAutoFocus(false)
        ns.ApplyFont(impNameEB,FONT,10); impNameEB:SetTextColor(1,1,1); impNameEB:SetJustifyH("LEFT"); impNameEB:SetText("")
        local inBg=impNameEB:CreateTexture(nil,"BACKGROUND"); inBg:SetPoint("TOPLEFT",-2,2); inBg:SetPoint("BOTTOMRIGHT",2,-2); inBg:SetColorTexture(0.06,0.06,0.08,0.9)
        impNameEB:SetScript("OnEscapePressed",function(s) s:ClearFocus() end)
        impNameEB:SetScript("OnEnterPressed",function(s) s:ClearFocus() end)

        -- Overwrite toggle
        local owLbl=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(owLbl,FONT,9)
        owLbl:SetPoint("TOPLEFT",w-110,-148); owLbl:SetTextColor(unpack(Theme.textDim)); owLbl:SetText(L["AURASMENU_PROFILES_LBL_OVERWRITE"])
        local owTog=SW.CreateToggle(c); owTog:SetPoint("TOPRIGHT",-5,-146); owTog:SetValue(false)

        -- Import button
        local impBtn=SW.CreateActionBtn(c,L["AURASMENU_PROFILES_BTN_IMPORT"],90,{0.25,0.20,0.08},{0.45,0.35,0.15},{1.00,0.85,0.39})
        impBtn:SetPoint("TOPRIGHT",-5,-170)

        -- Export handler
        expBtn:SetScript("OnClick",function()
            if not Prof then return end
            local profName = expDD:GetValue()
            local str, err = Prof:Export(profName)
            if str then
                eb:SetText(str); eb:HighlightText(); eb:SetFocus()
                SetStatus(string.format(L["AURASMENU_PROFILES_MSG_EXPORTED"], profName, #str),0.39,0.86,0.39)
            else
                SetStatus(err or L["AURASMENU_PROFILES_MSG_EXPORT_ERROR"],1,0.4,0.3)
            end
        end)

        -- Import handler
        impBtn:SetScript("OnClick",function()
            if not Prof then return end
            local str=eb:GetText(); if not str or str=="" then SetStatus(L["AURASMENU_PROFILES_MSG_PASTE_EXPORT_STRING"],1,0.7,0.3); return end
            local tgt=impNameEB:GetText(); if not tgt or tgt=="" then tgt=nil end
            local ow=owTog:GetValue()
            local ok, result = Prof:Import(str, tgt, ow)
            if ok then
                SetStatus(string.format(L["AURASMENU_PROFILES_MSG_IMPORT_SUCCESS"], tostring(result)),0.39,0.86,0.39)
                print("|cff00b0ffAishUIAura|r: "..string.format(L["AURASMENU_PROFILES_MSG_PROFILE_IMPORTED"], tostring(result)))
            else
                SetStatus(tostring(result),1,0.4,0.3)
            end
        end)

        eb:SetScript("OnEscapePressed",function(s) s:ClearFocus() end)
        c:SetHeight(195) end},
    {name=L["AURASMENU_PROFILES_SECTION_CONFIGURE_CLASS"],build=function(c,w)
        -- Description d'intro
        local info=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(info,FONT,9)
        info:SetPoint("TOPLEFT",5,-5); info:SetTextColor(unpack(Theme.textDim))
        info:SetWidth(w-10); info:SetJustifyH("LEFT"); info:SetWordWrap(true)
        info:SetText(L["AURASMENU_PROFILES_TXT_CLASS_INTRO"])

        -- Liste des presets disponibles pour la spé active
        local presets = (ns.GetAvailablePresets and ns.GetAvailablePresets()) or {}

        if #presets == 0 then
            local nd=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(nd,FONT,10)
            nd:SetPoint("TOPLEFT",5,-38); nd:SetTextColor(unpack(Theme.textDim))
            nd:SetWidth(w-10); nd:SetJustifyH("LEFT"); nd:SetWordWrap(true)
            nd:SetText(L["AURASMENU_PROFILES_TXT_NO_PRESET"])
            c:SetHeight(90)
            return
        end

        -- Affichage du preset actif (pour l'instant un seul par spé, pas de dropdown)
        local p = presets[1]
        local label=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(label,FONT,12)
        label:SetPoint("TOPLEFT",5,-38); label:SetTextColor(unpack(Theme.textNormal))
        label:SetText(p.label)

        local desc=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(desc,FONT,9)
        desc:SetPoint("TOPLEFT",5,-58); desc:SetWidth(w-10); desc:SetJustifyH("LEFT"); desc:SetWordWrap(true)
        desc:SetTextColor(unpack(Theme.textDim))
        desc:SetText(p.desc or "")

        -- Label de statut (mis à jour après clic)
        local status=c:CreateFontString(nil,"OVERLAY"); ns.ApplyFont(status,FONT,9)
        status:SetPoint("TOPLEFT",5,-120); status:SetWidth(w-10); status:SetJustifyH("LEFT"); status:SetWordWrap(true)
        status:SetText("")

        -- Bouton d'application
        local btn=SW.CreateActionBtn(c,L["AURASMENU_PROFILES_BTN_APPLY_PRESET"],180,{0.08,0.25,0.12},{0.15,0.45,0.20},{0.39,0.86,0.39})
        btn:SetPoint("TOPLEFT",5,-98)
        btn:SetScript("OnClick",function()
            if not ns.ApplyPreset then
                status:SetTextColor(1,0.4,0.3); status:SetText(L["AURASMENU_PROFILES_MSG_PRESET_API_UNAVAILABLE"])
                return
            end
            local applied, err, skipped = ns.ApplyPreset(p.key, "merge")
            if err then
                status:SetTextColor(1,0.4,0.3); status:SetText(err)
            else
                status:SetTextColor(0.39,0.86,0.39)
                if skipped and #skipped > 0 then
                    status:SetText(string.format(L["AURASMENU_PROFILES_MSG_PRESET_APPLIED_PARTIAL"], applied, #skipped))
                else
                    status:SetText(string.format(L["AURASMENU_PROFILES_MSG_PRESET_APPLIED_FULL"], applied))
                end
                print("|cff00b0ffAishUIAura|r: "..string.format(L["AURASMENU_PROFILES_MSG_PRESET_APPLIED_PRINT"], p.label, applied))
            end
        end)
        c:SetHeight(160) end},
},cw,0)
end

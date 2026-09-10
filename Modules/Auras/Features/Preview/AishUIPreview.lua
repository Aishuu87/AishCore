-- AishUIPreview.lua : preview des positions des modules, rendu visuel fidèle
local addonName, _addon = ...; _addon.Auras = _addon.Auras or {}; local ns = _addon.Auras
local AP = {}; ns.AishUIPreview = AP
local frames = {}
local FONT = "Fonts\\FRIZQT__.TTF"
local CIRCLE_TEX = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMaskSmall"
local GLOW_TEX = "Interface\\AddOns\\AishCore\\GlowTex"
local GLOW_FALLBACK = "Interface\\SpellActivationOverlay\\IconAlert"

local function GlowTex()
    local t = UIParent:CreateTexture()
    local ok = pcall(function() t:SetTexture(GLOW_TEX) end)
    t:Hide(); local tex = ok and GLOW_TEX or GLOW_FALLBACK; return tex
end
local glowTex = nil

local function MakeCircle(size, r, g, b, glR, glG, glB, label)
    if not glowTex then glowTex = GlowTex() end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(size, size); f:SetFrameStrata("BACKGROUND"); f:SetFrameLevel(2)
    -- Glow
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    glow:SetSize(size*1.5, size*1.5); glow:SetPoint("CENTER")
    glow:SetTexture(glowTex); glow:SetVertexColor(glR or 0.15, glG or 0.08, glB or 0.25, 0.3)
    glow:SetBlendMode("ADD")
    -- Outer ring
    local ring = f:CreateTexture(nil, "ARTWORK", nil, 0)
    ring:SetAllPoints(); ring:SetTexture(CIRCLE_TEX)
    ring:SetVertexColor(r*0.6, g*0.6, b*0.6, 0.55)
    -- Inner fill
    local fill = f:CreateTexture(nil, "ARTWORK", nil, 2)
    local is = size * 0.8
    fill:SetSize(is, is); fill:SetPoint("CENTER")
    fill:SetTexture(CIRCLE_TEX); fill:SetVertexColor(r, g, b, 0.6)
    -- Dark core
    local core = f:CreateTexture(nil, "ARTWORK", nil, 4)
    local cs = size * 0.55
    core:SetSize(cs, cs); core:SetPoint("CENTER")
    core:SetTexture(CIRCLE_TEX); core:SetVertexColor(0.03, 0.02, 0.05, 0.8)
    -- Label
    local lbl = f:CreateFontString(nil, "OVERLAY")
    pcall(function() lbl:SetFont(FONT, 9, "OUTLINE") end)
    lbl:SetPoint("CENTER"); lbl:SetTextColor(0.7, 0.5, 0.9, 0.6); lbl:SetText(label or "")
    f:Hide(); return f
end

local function MakeBar(w, h, r, g, b, label)
    if not glowTex then glowTex = GlowTex() end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(w, math.max(h, 6)); f:SetFrameStrata("BACKGROUND"); f:SetFrameLevel(2)
    -- Glow
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetPoint("TOPLEFT", -8, 8); glow:SetPoint("BOTTOMRIGHT", 8, -8)
    glow:SetTexture(glowTex); glow:SetVertexColor(r*0.5, g*0.5, b*0.5, 0.2); glow:SetBlendMode("ADD")
    -- Bg
    local bg = f:CreateTexture(nil, "ARTWORK"); bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.02, 0.05, 0.7)
    -- Fill
    local bar = f:CreateTexture(nil, "ARTWORK", nil, 2)
    bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("BOTTOMLEFT", 1, 1)
    bar:SetWidth((w-2)*0.6); bar:SetColorTexture(r, g, b, 0.4)
    -- Borders
    for _, s in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(r*0.7, g*0.7, b*0.7, 0.3)
        if s=="TOP" then t:SetHeight(1); t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT")
        elseif s=="BOTTOM" then t:SetHeight(1); t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT")
        elseif s=="LEFT" then t:SetWidth(1); t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT")
        else t:SetWidth(1); t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT") end
    end
    -- Label
    local lbl = f:CreateFontString(nil, "OVERLAY")
    pcall(function() lbl:SetFont(FONT, 8, "OUTLINE") end)
    lbl:SetPoint("CENTER"); lbl:SetTextColor(0.6, 0.4, 0.8, 0.5); lbl:SetText(label or "")
    f:Hide(); return f
end

local function MakeIcons(count, size, spacing, label)
    local tw = count*size + (count-1)*spacing
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(tw, size); f:SetFrameStrata("BACKGROUND"); f:SetFrameLevel(2)
    for i = 1, count do
        local ox = (i-1)*(size+spacing)
        local ico = f:CreateTexture(nil, "ARTWORK")
        ico:SetSize(size-2, size-2); ico:SetPoint("TOPLEFT", ox+1, -1)
        ico:SetColorTexture(0.1, 0.06, 0.18, 0.5)
        for _, s in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
            local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetColorTexture(0.3, 0.18, 0.45, 0.35)
            if s=="TOP" then t:SetSize(size, 1); t:SetPoint("TOPLEFT", ox, 0)
            elseif s=="BOTTOM" then t:SetSize(size, 1); t:SetPoint("BOTTOMLEFT", ox, 0)
            elseif s=="LEFT" then t:SetSize(1, size); t:SetPoint("TOPLEFT", ox, 0)
            else t:SetSize(1, size); t:SetPoint("TOPLEFT", ox+size-1, 0) end
        end
    end
    local lbl = f:CreateFontString(nil, "OVERLAY")
    pcall(function() lbl:SetFont(FONT, 8, "OUTLINE") end)
    lbl:SetPoint("TOP", 0, 12); lbl:SetTextColor(0.5, 0.3, 0.7, 0.5); lbl:SetText(label or "")
    f:Hide(); return f
end

-- Les ancres correspondent exactement aux positions des modules
function AP:Build()
    if #frames > 0 then return end
    local db = AishaddonDB
    if not db then return end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    -- Resource Circle: CENTER, UIParent, CENTER, x, y
    local rc = db.resourceCircle or {}
    local rcF = MakeCircle(rc.size or 80, 0.25, 0.12, 0.45, 0.2, 0.1, 0.35, "Resource")
    rcF:SetPoint("CENTER", UIParent, "CENTER", rc.x or 0, rc.y or 0)
    frames[#frames+1] = rcF

    -- Health Circle: CENTER, UIParent, BOTTOMLEFT, sw*pctX+x, sh*pctY+y
    local hc = db.healthCircle or {}
    local hcF = MakeCircle(hc.size or 40, 0.4, 0.12, 0.15, 0.35, 0.1, 0.12, "Health")
    local hcPctX, hcPctY = hc.anchorPctX or 0.22, hc.anchorPctY or 0.28
    hcF:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw*hcPctX + (hc.x or 0), sh*hcPctY + (hc.y or 0))
    frames[#frames+1] = hcF

    -- OOC Resource Circle: CENTER, UIParent, BOTTOMLEFT, sw*pctX+x, sh*pctY+y
    local ocrc = db.outOfCombatResourceCircle or {}
    if ocrc.enabled ~= false then
        local ocF = MakeCircle(ocrc.size or 40, 0.2, 0.15, 0.35, 0.15, 0.1, 0.3, "OOC Res")
        local ocPctX, ocPctY = ocrc.anchorPctX or 0.22, ocrc.anchorPctY or 0.28
        ocF:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sw*ocPctX + (ocrc.x or 0), sh*ocPctY + (ocrc.y or 0))
        frames[#frames+1] = ocF
    end

    -- Cast Bar: BOTTOM, UIParent, CENTER, x, y
    local cb = db.castBar or {}
    local cbF = MakeBar(cb.width or 260, cb.height or 3, 0.65, 0.45, 0.25, "CastBar")
    cbF:SetPoint("BOTTOM", UIParent, "CENTER", cb.x or 0, cb.y or 0)
    frames[#frames+1] = cbF

    -- Priority Bar Left: TOPLEFT, UIParent, CENTER, -sideOffset, verticalOffset
    local pb = db.priorityBar or {}
    local pSz, pSp = pb.iconSize or 34, pb.iconSpacing or 6
    local pSl = math.min(pb.slots or 3, 4)
    local sOff = pb.sideOffset or 150
    local vOff = pb.verticalOffset or 0
    local pbL = MakeIcons(pSl, pSz, pSp, "PB G")
    pbL:SetPoint("TOPLEFT", UIParent, "CENTER", -sOff, vOff)
    frames[#frames+1] = pbL
    local pbR = MakeIcons(pSl, pSz, pSp, "PB D")
    pbR:SetPoint("TOPRIGHT", UIParent, "CENTER", sOff, vOff)
    frames[#frames+1] = pbR

    -- Top Target: TOP, WorldFrame, TOP, x, y
    local ttb = db.topTargetBar or {}
    local ttF = MakeBar(180, 10, 0.5, 0.2, 0.2, "Target")
    ttF:SetPoint("TOP", WorldFrame, "TOP", ttb.x or 0, ttb.y or 0)
    frames[#frames+1] = ttF
end

function AP:Show()
    self:Build()
    for _, f in ipairs(frames) do f:Show() end
end

function AP:Hide()
    for _, f in ipairs(frames) do f:Hide() end
end

function AP:Toggle(on)
    if on then self:Show() else self:Hide() end
end

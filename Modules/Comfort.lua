-- Modules/Comfort.lua : confort de jeu. CVars de rendu en un clic + petits raccourcis de commandes.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local Comfort = {}
ns.Modules.Comfort = Comfort

-- Cle de reglage -> CVar, valeur activee, valeur desactivee (defaut Blizzard)
local CVAR_TOGGLES = {
  { key = "groundDensity", cvar = "groundEffectDensity",   on = 256, off = 48  },
  { key = "groundFade",    cvar = "groundEffectFade",      on = 370, off = 70  },
  { key = "groundDist",    cvar = "groundEffectDist",      on = 500, off = 320 },
  { key = "sharpen",       cvar = "ResampleAlwaysSharpen", on = 1,   off = 0   },
}

local function Cfg()
  return ns.GetCfg("comfort") or {}
end

local function GetCVarNum(name)
  local ok, v = pcall(C_CVar.GetCVar, name)
  return ok and tonumber(v) or nil
end

-- Active : pose la valeur "on". Desactive : ne restaure la valeur Blizzard que si la valeur actuelle
-- est bien la notre, pour ne jamais ecraser un reglage fait ailleurs.
local function ApplyCVars()
  local cfg = Cfg()
  for _, t in ipairs(CVAR_TOGGLES) do
    local cur = GetCVarNum(t.cvar)
    if cfg[t.key] then
      if cur ~= t.on then pcall(C_CVar.SetCVar, t.cvar, t.on) end
    elseif cur == t.on then
      pcall(C_CVar.SetCVar, t.cvar, t.off)
    end
  end
end

-- ── Raccourcis ──────────────────────────────────────────────────────────────

local function Say(msg)
  print("|cff33aaffAishCore|r " .. msg)
end

local function SlashReload()
  C_UI.Reload()
end

local function SlashEditMode()
  if InCombatLockdown() then return Say(ERR_NOT_IN_COMBAT) end
  local f = _G.EditModeManagerFrame
  if not f then return end
  if f:IsShown() then HideUIPanel(f) else ShowUIPanel(f) end
end

local function SlashCDM()
  if InCombatLockdown() then return Say(ERR_NOT_IN_COMBAT) end
  if not _G.CooldownViewerSettings and C_AddOns and C_AddOns.LoadAddOn then
    pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
  end
  local f = _G.CooldownViewerSettings
  if not f then return end
  if f:IsShown() then HideUIPanel(f) else ShowUIPanel(f) end
end

-- Enregistre / retire les commandes : SlashCmdList est relu a chaque saisie, donc un simple
-- nil rend la commande a un eventuel autre addon.
local SLASHES = {
  { name = "AISHCORE_RL",   cmd = "/rl",   fn = SlashReload   },
  { name = "AISHCORE_EDIT", cmd = "/edit", fn = SlashEditMode },
  { name = "AISHCORE_CDM",  cmd = "/cdm",  fn = SlashCDM      },
}

local function ApplySlashes()
  local on = Cfg().shortcuts and true or false
  for _, s in ipairs(SLASHES) do
    if on then
      _G["SLASH_" .. s.name .. "1"] = s.cmd
      SlashCmdList[s.name] = s.fn
    else
      SlashCmdList[s.name] = nil
    end
  end
end

-- ── Fenetre marchand multi-pages ────────────────────────────────────────────
-- Meme principe que ElvUI_WindTools (ExtendMerchantPages) : MERCHANT_ITEMS_PER_PAGE agrandi,
-- frames MerchantItem supplementaires, puis repositionnement apres chaque mise a jour Blizzard.
local PAGE_ITEMS, BUYBACK_ITEMS = 10, 12
local merchantActive, merchantHooked = false, false
local CONFLICTS = { "ExtVendor", "Krowi_ExtendedVendorUI", "CompactVendor", "ElvUI_WindTools" }

local function MerchantConflict()
  for _, a in ipairs(CONFLICTS) do
    if C_AddOns.IsAddOnLoaded(a) then return true end
  end
  -- EllesmereUI en mode "liste" remplace toute la grille native
  if C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin") and EllesmereUIDB and EllesmereUIDB.merchantShowAsList then
    return true
  end
  return false
end

-- EllesmereUI ne reskinne que MerchantItem1-12 : les cases ajoutees recoivent un habillage equivalent
-- (carte sombre, art Blizzard efface, icone carree, bordure 1 px a la couleur de qualite).
local function SkinExtraTile(item)
  if not C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin") then return end
  if not item._aishBg then
    local bg = item:CreateTexture(nil, "BACKGROUND", nil, -7)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.92)
    bg:SetPoint("TOPLEFT", 2, -1)
    bg:SetPoint("BOTTOMRIGHT", -2, 1)
    item._aishBg = bg
    local edges = {}
    for k = 1, 4 do
      edges[k] = item:CreateTexture(nil, "BORDER", nil, -7)
      edges[k]:SetColorTexture(0.2, 0.2, 0.2, 1)
    end
    edges[1]:SetPoint("TOPLEFT", bg, "TOPLEFT");     edges[1]:SetPoint("TOPRIGHT", bg, "TOPRIGHT");       edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", bg, "TOPLEFT");     edges[3]:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT");   edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", bg, "TOPRIGHT");   edges[4]:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT"); edges[4]:SetWidth(1)
    item._aishEdges = edges
  end
  -- Blizzard repeint l'art a chaque page : on le re-efface a chaque passe
  for _, r in ipairs({ item:GetRegions() }) do
    if r ~= item._aishBg and r.IsObjectType and r:IsObjectType("Texture") then
      local isEdge = false
      for _, e in ipairs(item._aishEdges) do if e == r then isEdge = true end end
      if not isEdge then r:SetAlpha(0) end
    end
  end
  local btn = item.ItemButton or _G[item:GetName() .. "ItemButton"]
  if btn then
    local nt = btn.GetNormalTexture and btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local slot = _G[item:GetName() .. "SlotTexture"]
    if slot then slot:SetAlpha(0) end
    local icon = btn.icon or btn.Icon or _G[btn:GetName() .. "IconTexture"]
    if icon then
      pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
      -- Blizzard remet le cadrage d'origine a chaque mise a jour : on le reimpose au vol
      if not icon._aishCropHook then
        icon._aishCropHook = true
        local busy = false
        local function Crop(self)
          if busy then return end
          busy = true
          pcall(self.SetTexCoord, self, 0.08, 0.92, 0.08, 0.92)
          busy = false
        end
        hooksecurefunc(icon, "SetTexCoord", Crop)
        hooksecurefunc(icon, "SetTexture", Crop)
      end
    end
    local ring = btn.IconBorder
    local r, g, b = 0.2, 0.2, 0.2
    if ring then
      if ring:IsShown() then
        local qr, qg, qb = ring:GetVertexColor()
        -- Qualite commune/pauvre (blanc ou gris 0.66) : gris sombre neutre, comme EllesmereUI.
        -- Seules les vraies couleurs de qualite (vert, bleu, violet...) sont reprises.
        if qr and (math.max(qr, qg, qb) - math.min(qr, qg, qb)) > 0.15 then r, g, b = qr, qg, qb end
      end
      ring:SetAlpha(0)
    end
    if not btn._aishEdges then
      local edges = {}
      for k = 1, 4 do edges[k] = btn:CreateTexture(nil, "OVERLAY") end
      edges[1]:SetPoint("TOPLEFT");     edges[1]:SetPoint("TOPRIGHT");     edges[1]:SetHeight(1)
      edges[2]:SetPoint("BOTTOMLEFT");  edges[2]:SetPoint("BOTTOMRIGHT");  edges[2]:SetHeight(1)
      edges[3]:SetPoint("TOPLEFT");     edges[3]:SetPoint("BOTTOMLEFT");   edges[3]:SetWidth(1)
      edges[4]:SetPoint("TOPRIGHT");    edges[4]:SetPoint("BOTTOMRIGHT");  edges[4]:SetWidth(1)
      btn._aishEdges = edges
    end
    for _, e in ipairs(btn._aishEdges) do e:SetColorTexture(r, g, b, 1) end
    -- Tout autre calque du bouton (cadre blanc de slot, surbrillances Blizzard...) est efface,
    -- comme le fait EllesmereUI : seuls l'icone et nos bordures restent.
    local keep = {}
    if icon then keep[icon] = true end
    for _, e in ipairs(btn._aishEdges) do keep[e] = true end
    for _, rg in ipairs({ btn:GetRegions() }) do
      if not keep[rg] and rg.IsObjectType and rg:IsObjectType("Texture") then rg:SetAlpha(0) end
    end
    if not btn._aishCentred then
      btn._aishCentred = true
      btn:ClearAllPoints()
      btn:SetPoint("LEFT", item, "LEFT", 0, 0)
    end
  end
end

local function MerchantPages()
  return math.max(2, math.min(4, math.floor(Cfg().merchantPages or 3)))
end

-- Etat Blizzard d'origine, capture avant la 1re modification, pour pouvoir revenir en arriere en direct
local saved
local RESTORE_FRAMES = { "MerchantBuyBackItem", "MerchantSellAllJunkButton", "MerchantPrevPageButton", "MerchantNextPageButton", "MerchantPageText" }

local function CapturePoints(f)
  local t = {}
  for i = 1, f:GetNumPoints() do t[i] = { f:GetPoint(i) } end
  return t
end

local function SaveMerchantOriginals()
  if saved then return end
  saved = { width = MerchantFrame:GetWidth(), perPage = _G.MERCHANT_ITEMS_PER_PAGE, pts = {} }
  for i = 1, 12 do
    local f = _G["MerchantItem" .. i]
    if f then saved.pts[f] = CapturePoints(f) end
  end
  for _, n in ipairs(RESTORE_FRAMES) do
    local f = _G[n]
    if f then saved.pts[f] = CapturePoints(f) end
  end
end

local function RestoreMerchant()
  if not (saved and merchantActive) or InCombatLockdown() then return end
  merchantActive = false
  _G.MERCHANT_ITEMS_PER_PAGE = saved.perPage
  MerchantFrame:SetWidth(saved.width)
  for f, pts in pairs(saved.pts) do
    f:ClearAllPoints()
    for _, p in ipairs(pts) do f:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
  end
  -- EllesmereUI avait decale MerchantItem1 de 3 px vers le bas (une seule fois)
  if C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin") and MerchantItem1 and saved.pts[MerchantItem1] then
    MerchantItem1:ClearAllPoints()
    for _, p in ipairs(saved.pts[MerchantItem1]) do MerchantItem1:SetPoint(p[1], p[2], p[3], p[4], (p[5] or 0) - 3) end
  end
  for i = 13, PAGE_ITEMS * 4 do
    local b = _G["MerchantItem" .. i]
    if b then b:Hide() end
  end
  if MerchantFrame:IsShown() and _G.MerchantFrame_Update then pcall(MerchantFrame_Update) end
end

-- Habillage protege (une erreur ne doit jamais casser la grille) : signalee une seule fois
local _skinErrShown = false
local function SafeSkinExtra(b)
  local ok, err = pcall(SkinExtraTile, b)
  if not ok and not _skinErrShown then
    _skinErrShown = true
    print("|cff33aaffAishCore|r habillage marchand : " .. tostring(err))
  end
end

local function LayoutMerchantItems()
  if not merchantActive then return end
  local numItems = GetMerchantNumItems()
  local page = MerchantFrame.page or 1
  for i = 1, _G.MERCHANT_ITEMS_PER_PAGE do
    local b = _G["MerchantItem" .. i]
    if not b then break end
    b:ClearAllPoints()
    -- Les cases 11-12 sont masquees par Blizzard (reservees au rachat) : on les remontre, mais
    -- seulement si un article existe a cet index.
    b:SetShown((page - 1) * _G.MERCHANT_ITEMS_PER_PAGE + i <= numItems)
    if i > 12 then SafeSkinExtra(b) end
    if (i % PAGE_ITEMS) == 1 then
      if i == 1 then
        b:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 11, -69)
      else
        b:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - (PAGE_ITEMS - 1))], "TOPRIGHT", 12, 0)
      end
    elseif (i % 2) == 1 then
      b:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 2)], "BOTTOMLEFT", 0, -8)
    else
      b:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", 12, 0)
    end
  end
  C_Timer.After(0, function()
    if not merchantActive then return end
    for i = 13, _G.MERCHANT_ITEMS_PER_PAGE do
      local b = _G["MerchantItem" .. i]
      if b and b:IsShown() then SafeSkinExtra(b) end
    end
  end)
end

local function LayoutBuybackItems()
  if not merchantActive then return end
  local n = GetNumBuybackItems()
  for i = BUYBACK_ITEMS + 1, _G.MERCHANT_ITEMS_PER_PAGE do
    local b = _G["MerchantItem" .. i]
    if not b then break end
    b:ClearAllPoints()
    if i <= n then
      local row, col = math.floor((i - 1) / 3), (i - 1) % 3
      if row == 0 then
        if col == 0 then
          b:SetPoint("TOPLEFT", MerchantItem1, "TOPLEFT", 0, -60)
        else
          b:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", 12, 0)
        end
      elseif col == 0 then
        b:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 3)], "BOTTOMLEFT", 0, -15)
      else
        b:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", 12, 0)
      end
      b:Show()
    else
      b:Hide()
    end
  end
end

local function ApplyMerchant()
  if not MerchantFrame then return end
  if not Cfg().merchantExtend or MerchantConflict() then
    RestoreMerchant()
    return
  end
  if InCombatLockdown() then return end
  SaveMerchantOriginals()
  local pages = MerchantPages()
  merchantActive = true
  _G.MERCHANT_ITEMS_PER_PAGE = pages * PAGE_ITEMS
  MerchantFrame:SetWidth(30 + pages * 330)
  for i = 1, _G.MERCHANT_ITEMS_PER_PAGE do
    if not _G["MerchantItem" .. i] then
      CreateFrame("Frame", "MerchantItem" .. i, MerchantFrame, "MerchantItemTemplate")
      local alt = _G["MerchantItem" .. i .. "AltCurrencyFrame"]
      if alt then alt:Hide() end
    end
  end
  -- Pages en moins : masquer les cases en trop
  for i = _G.MERCHANT_ITEMS_PER_PAGE + 1, PAGE_ITEMS * 4 do
    local b = _G["MerchantItem" .. i]
    if b then b:Hide() end
  end
  -- Rachat colle au bouton "vendre la camelote", en bas a droite pres de l'argent
  MerchantBuyBackItem:ClearAllPoints()
  if MerchantSellAllJunkButton then
    MerchantBuyBackItem:SetPoint("RIGHT", MerchantSellAllJunkButton, "LEFT", -10, 0)
  else
    MerchantBuyBackItem:SetPoint("TOPLEFT", MerchantItem10, "BOTTOMLEFT", 30, -53)
  end
  local off = 25 + ((pages - 1) * 165)
  MerchantPrevPageButton:ClearAllPoints()
  MerchantPrevPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", off, 93)
  MerchantPageText:ClearAllPoints()
  MerchantPageText:SetPoint("BOTTOM", MerchantFrame, "BOTTOM", 0, 86)
  MerchantNextPageButton:ClearAllPoints()
  MerchantNextPageButton:SetPoint("CENTER", MerchantFrame, "BOTTOMRIGHT", -off, 93)
  if not merchantHooked and _G.MerchantFrame_UpdateMerchantInfo then
    merchantHooked = true
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", LayoutMerchantItems)
    if _G.MerchantFrame_UpdateBuybackInfo then
      hooksecurefunc("MerchantFrame_UpdateBuybackInfo", LayoutBuybackItems)
    end
  end
  if MerchantFrame:IsShown() and _G.MerchantFrame_Update then pcall(MerchantFrame_Update) end
end

-- ── Horizon Suite coupe avec RestedXP ───────────────────────────────────────
-- Les modules actifs d'Horizon Suite sont coupes (DisableModule, sans /reload) tant que RestedXP
-- est charge ; ceux qu'on a coupes sont memorises pour etre rallumes quand la condition tombe.
local function RXPLoaded()
  return C_AddOns.IsAddOnLoaded("RXPGuides") or C_AddOns.IsAddOnLoaded("EUI-RestedXP")
end

local function ApplyHorizon()
  local H = _G.HorizonSuite
  if not (H and H.modules and H.DisableModule and H.EnableModule) then return end
  local cfg = ns.DB and ns.DB.comfort
  if Cfg().horizonOffWithRXP and RXPLoaded() then
    for key, m in pairs(H.modules) do
      if m.enabled then
        cfg = cfg or {}
        ns.DB.comfort = cfg
        cfg.horizonSuspended = cfg.horizonSuspended or {}
        cfg.horizonSuspended[key] = true
        pcall(H.DisableModule, H, key)
      end
    end
  elseif cfg and cfg.horizonSuspended then
    for key in pairs(cfg.horizonSuspended) do
      if H.modules[key] then pcall(H.EnableModule, H, key) end
    end
    cfg.horizonSuspended = nil
  end
end

-- Diagnostic : /aishmerchdbg [n] decrit les calques de MerchantItem<n> (13 par defaut)
SLASH_AISHMERCHDBG1 = "/aishmerchdbg"
SlashCmdList["AISHMERCHDBG"] = function(msg)
  local n = tonumber(msg) or 13
  local item = _G["MerchantItem" .. n]
  if not item then print("MerchantItem" .. n .. " introuvable") return end
  local function Key(owner, obj)
    for k, v in pairs(owner) do if v == obj and type(k) == "string" then return k end end
    return "?"
  end
  local function Dump(owner, label)
    for _, r in ipairs({ owner:GetRegions() }) do
      local layer, sub = r:GetDrawLayer()
      local tex = r.GetTexture and r:GetTexture()
      local atlas = r.GetAtlas and r:GetAtlas()
      local cr, cg, cb = 0, 0, 0
      if r.GetVertexColor then cr, cg, cb = r:GetVertexColor() end
      print(string.format("%s region %s [%s/%s] shown=%s alpha=%.2f tex=%s atlas=%s col=%.2f,%.2f,%.2f", label,
        Key(owner, r), tostring(layer), tostring(sub), tostring(r:IsShown()), r:GetAlpha(), tostring(tex), tostring(atlas), cr, cg, cb))
    end
    for _, c in ipairs({ owner:GetChildren() }) do
      print(string.format("%s child %s (%s) shown=%s alpha=%.2f", label, Key(owner, c), tostring(c:GetObjectType()), tostring(c:IsShown()), c:GetAlpha()))
    end
  end
  Dump(item, "item")
  local btn = item.ItemButton or _G[item:GetName() .. "ItemButton"]
  if btn then Dump(btn, "btn") end
end

function Comfort.ApplySettings()
  ApplyCVars()
  ApplySlashes()
  ApplyMerchant()
  -- Horizon Suite active ses modules apres nous : on attend qu'ils le soient
  C_Timer.After(2, ApplyHorizon)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", Comfort.ApplySettings)

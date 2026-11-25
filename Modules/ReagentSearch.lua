-- Modules/ReagentSearch.lua : sacs (QoL). Clic droit sur un ingredient d'artisanat (viande, poisson, plante, minerai,
-- tissu, cuir...) : ouvre la fenetre du metier qui l'utilise et y recherche son nom.
-- Metier choisi d'apres la sous-classe de l'objet (Marchandises), parmi ceux du personnage : plante -> Alchimie ou
-- Calligraphie, minerai -> Forge, Joaillerie ou Ingenierie, viande / poisson -> Cuisine, etc.
-- Post-hook de C_Container.UseContainerItem (sacs Blizzard et la plupart des addons de sacs) : l'objet n'ayant pas
-- d'effet "Utiliser", le clic natif ne fait rien. Ignore : objet utilisable (nourriture preparee, potion...),
-- touche de modification, objet en main, sort en ciblage, marchand / banque / courrier / echange / HV ouverts.
-- Retail : C_TradeSkillUI.OpenTradeSkill puis champ de recherche de ProfessionsFrame.
-- Forever : ouvrir un metier passe par un sort (protege) -> seulement si sa fenetre est deja ouverte.
-- Reglage : ns.DB.comfort.reagentSearch.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local RS = {}
ns.Modules.ReagentSearch = RS

-- Lignes de competence des metiers
local ALCH, BS, ENCH, ENGI, INSC, JC, LW, TAIL, COOK, AID = 171, 164, 333, 202, 773, 755, 165, 197, 185, 129
local ANY = "any" -- n'importe quel metier principal (le 1er du personnage)

-- Sous-classe de Marchandises (classID 7) -> metiers candidats, par ordre de priorite
local BY_SUBCLASS = {
  [0]  = ANY,                -- Marchandises (generique, clients anciens)
  [1]  = { ENGI },           -- Pieces
  [4]  = { JC },             -- Joaillerie (gemmes)
  [5]  = { TAIL, AID },      -- Tissu
  [6]  = { LW },             -- Cuir
  [7]  = { BS, JC, ENGI },   -- Metal et pierre
  [8]  = { COOK },           -- Cuisine (viande, poisson)
  [9]  = { ALCH, INSC },     -- Herbes
  [10] = ANY,                -- Elementaire
  [11] = ANY,                -- Autre
  [12] = { ENCH },           -- Enchantement
  [16] = { INSC },           -- Calligraphie
  [18] = ANY,                -- Composants optionnels
  [19] = ANY,                -- Composants de finition
}

-- Fenetres pendant lesquelles le clic droit a deja un role (vendre, deposer, joindre...)
local BUSY_FRAMES = {
  "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame", "AuctionHouseFrame", "AuctionFrame", "GuildBankFrame",
  "VoidStorageFrame", "ScrappingMachineFrame", "ItemSocketingFrame", "ItemInteractionFrame",
  "ProfessionsCustomerOrdersFrame", "ItemUpgradeFrame", "AzeriteRespecFrame",
}

local function Enabled()
  if not ns.QoLEnabled() then return false end
  local c = ns.GetCfg("comfort") or {}
  return c.reagentSearch ~= false
end

local function Busy()
  for _, n in ipairs(BUSY_FRAMES) do
    local f = _G[n]
    if f and f.IsShown and f:IsShown() then return true end
  end
  if SpellIsTargeting and SpellIsTargeting() then return true end
  if CursorHasItem and CursorHasItem() then return true end
  return false
end

-- Le clic vient bien d'un bouton sous la souris (et pas d'un addon qui utilise des objets en boucle)
local function FromMouse()
  local f
  if GetMouseFoci then
    local ok, foci = pcall(GetMouseFoci)
    f = ok and foci and foci[1]
  elseif GetMouseFocus then
    f = GetMouseFocus()
  end
  return f and f.IsObjectType and f:IsObjectType("Button")
end

local function ItemIDAt(bag, slot)
  if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
  local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
  return link and tonumber(link:match("item:(%d+)"))
end

local function ItemClass(itemID)
  local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not get then return end
  local _, _, _, _, _, classID, subclassID = get(itemID)
  return classID, subclassID
end

local function ItemUsable(itemID)
  local get = (C_Item and C_Item.GetItemSpell) or GetItemSpell
  return get and get(itemID) ~= nil
end

local function ItemName(itemID)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  if not n and GetItemInfo then n = GetItemInfo(itemID) end
  return n
end

-- Metiers du personnage : skillLine -> nom ; liste ordonnee des metiers principaux
local function PlayerProfessions()
  local known, mains = {}, {}
  if not (GetProfessions and GetProfessionInfo) then return known, mains end
  local p1, p2, a3, fish, cook, a6 = GetProfessions()
  local function Add(idx, main)
    if not idx then return end
    local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
    if skillLine and name then
      known[skillLine] = name
      if main then mains[#mains + 1] = skillLine end
    end
  end
  Add(p1, true)
  Add(p2, true)
  Add(cook)
  Add(a3) -- Forever : Premiers soins (Archeologie en Retail, jamais candidate)
  Add(a6)
  return known, mains
end

local GATHERING = { [182] = true, [186] = true, [393] = true, [356] = true, [794] = true }

local function PickProfession(itemID)
  local classID, sub = ItemClass(itemID)
  if classID ~= 7 then return end
  local cand = BY_SUBCLASS[sub or -1]
  if not cand then return end
  local known, mains = PlayerProfessions()
  if cand == ANY then
    for _, sl in ipairs(mains) do
      if not GATHERING[sl] then return sl, known[sl] end
    end
    return
  end
  for _, sl in ipairs(cand) do
    if known[sl] then return sl, known[sl] end
  end
end

-- ── Retail : ProfessionsFrame ─────────────────────────────────────────────────────────────────────────
local pending -- { skill, name, token }

local function RetailApply()
  if not pending then return end
  local pf = _G.ProfessionsFrame
  if not (pf and pf:IsShown()) then return end
  local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  if not (base and base.professionID == pending.skill) then return end
  -- Onglet Recettes (la fenetre peut s'ouvrir sur Specialisations)
  if pf.recipesTabID and pf.GetTab and pf.SetTab and pf:GetTab() ~= pf.recipesTabID then
    pcall(pf.SetTab, pf, pf.recipesTabID)
  end
  local list = pf.CraftingPage and pf.CraftingPage.RecipeList
  local sb = list and list.SearchBox
  if not sb then return end
  if sb:GetText() ~= pending.name then
    sb:SetText(pending.name)
    if C_TradeSkillUI.SetRecipeItemNameFilter then pcall(C_TradeSkillUI.SetRecipeItemNameFilter, pending.name) end
  end
end

-- La fenetre se charge et remet sa liste a jour en plusieurs temps : quelques passages, puis abandon
local function Schedule()
  local token = {}
  pending.token = token
  for _, d in ipairs({ 0, 0.15, 0.4, 0.8 }) do
    C_Timer.After(d, function()
      if pending and pending.token == token then RetailApply() end
    end)
  end
  C_Timer.After(1.2, function()
    if pending and pending.token == token then pending = nil end
  end)
end

local function RetailOpen(skill, name)
  pending = { skill = skill, name = name }
  local pf = _G.ProfessionsFrame
  local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  local open = pf and pf:IsShown() and base and base.professionID == skill
  if not open then C_TradeSkillUI.OpenTradeSkill(skill) end
  Schedule()
end

-- ── Forever : TradeSkillFrame classique, deja ouverte sur le bon metier ───────────────────────────────
local function ClassicSearchBox()
  local f = _G.TradeSkillFrame
  return (f and f.SearchBox) or _G.TradeSkillFrameSearchBox or _G.TradeSkillFrameEditBox
end

local function ClassicOpen(name, profName, itemID)
  local f = _G.TradeSkillFrame
  if not (f and f:IsShown() and GetTradeSkillLine) then return end
  if GetTradeSkillLine() ~= profName then return end
  local sb = ClassicSearchBox()
  if sb then
    sb:SetText(name)
    if SetTradeSkillItemNameFilter then pcall(SetTradeSkillItemNameFilter, name) end
    return
  end
  -- Pas de recherche sur ce client : 1re recette qui utilise l'ingredient
  if not (GetNumTradeSkills and TradeSkillFrame_SetSelection) then return end
  for i = 1, (GetNumTradeSkills() or 0) do
    local _, kind = GetTradeSkillInfo(i)
    if kind ~= "header" and kind ~= "subheader" then
      for r = 1, (GetTradeSkillNumReagents(i) or 0) do
        local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, r)
        if link and tonumber(link:match("item:(%d+)")) == itemID then
          TradeSkillFrame_SetSelection(i)
          if TradeSkillFrame_Update then TradeSkillFrame_Update() end
          return
        end
      end
    end
  end
end

-- ── Clic droit dans les sacs ──────────────────────────────────────────────────────────────────────────
local function OnUse(bag, slot, target)
  if target or not Enabled() then return end
  if IsModifierKeyDown() or Busy() or not FromMouse() then return end
  local itemID = ItemIDAt(bag, slot)
  if not itemID or ItemUsable(itemID) then return end
  local skill, profName = PickProfession(itemID)
  if not skill then return end
  local name = ItemName(itemID)
  if not name then return end
  if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
    RetailOpen(skill, name)
  else
    ClassicOpen(name, profName, itemID)
  end
end

local hooked
local function Hook()
  if hooked then return end
  if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", OnUse)
    hooked = true
  elseif _G.UseContainerItem then
    hooksecurefunc("UseContainerItem", OnUse)
    hooked = true
  end
end

function RS.ApplySettings()
  if Enabled() then Hook() end
  if not Enabled() then pending = nil end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    RS.ApplySettings()
  elseif pending and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
    RetailApply()
  end
end)

-- Modules/ExtraBars.lua : "Extra Barres". Jusqu'à 5 barres d'objets remplies automatiquement par tags
-- (potions, flacons, nourriture, objets ouvrables...). Implémentation originale : les tags sont déduits
-- des informations du jeu (classe / sous-classe d'objet, objet invoqué, butin, quête), pas de listes
-- d'objets figées, sauf les rares cas que le jeu ne distingue pas (pierres de soins).
-- Réglages : ns.DB.extraBars.bars[1..5] (cf. ExtraBarDefaults dans Config/Defaults.lua).
--
-- Boutons sécurisés (SecureActionButtonTemplate, type "item") : leurs attributs, leur nombre et leur
-- disposition ne changent QU'HORS COMBAT ; en combat, seuls les compteurs et cooldowns sont mis à jour
-- et le reste est rejoué à PLAYER_REGEN_ENABLED. Raccourcis clavier : Bindings.xml (CLICK sur les
-- boutons nommés AishCoreExtraBar<i>Button<j>, 12 par barre).
local addonName, ns = ...
local L = ns.L

ns.Modules = ns.Modules or {}
local ExtraBars = {}
ns.Modules.ExtraBars = ExtraBars

local NUM_BARS, MAX_BUTTONS, NUM_BINDINGS = 5, 24, 12
local PLACEHOLDER_ICON = 134400 -- point d'interrogation
local DEFAULT_FONT = "Fonts\\2002.TTF"
ExtraBars.NUM_BARS = NUM_BARS

-- Tags -------------------------------------------------------------------------------------------
-- Sous-classes de Enum.ItemClass.Consumable (valeurs stables depuis Dragonflight)
local CONSUMABLE = Enum.ItemClass and Enum.ItemClass.Consumable or 0
local SUB = { explosive = 0, potion = 1, elixir = 2, flask = 3, food = 5, enhancement = 6, bandage = 7, vantus = 9 }

-- Pierres de soins : rien ne les distingue des autres consommables dans les catégories du jeu
local HEALTHSTONES = { [5512] = true, [224464] = true }

-- Ordre d'affichage des tags (et de la grille de la page de réglages)
ExtraBars.TAGS = {
  "potion", "healthstone", "flask", "elixir", "food", "conjured", "vantus",
  "enhancement", "bandage", "explosive", "knowledge", "openable", "quest", "trinket",
}

-- Icône représentative de chaque tag : aperçu dans le GUI quand les sacs ne contiennent rien
ExtraBars.TAG_ICONS = {
  potion      = "Interface\\Icons\\INV_Potion_54",
  healthstone = "Interface\\Icons\\INV_Stone_04",
  flask       = "Interface\\Icons\\INV_Potion_62",
  elixir      = "Interface\\Icons\\INV_Potion_32",
  food        = "Interface\\Icons\\INV_Misc_Food_15",
  conjured    = "Interface\\Icons\\INV_Misc_Food_73CinnamonRoll",
  vantus      = "Interface\\Icons\\INV_Misc_Rune_01",
  enhancement = "Interface\\Icons\\INV_Stone_SharpeningStone_05",
  bandage     = "Interface\\Icons\\INV_Misc_Bandage_15",
  explosive   = "Interface\\Icons\\INV_Misc_Bomb_05",
  knowledge   = "Interface\\Icons\\INV_Misc_Book_11",
  openable    = "Interface\\Icons\\INV_Box_02",
  quest       = "Interface\\Icons\\INV_Misc_Note_01",
  trinket     = "Interface\\Icons\\INV_Jewelry_Talisman_07",
}

-- Libellés des tags suivis par une barre, dans l'ordre des tags ("Potions, Élixirs")
function ExtraBars.TagsLabel(bc, sep)
  local out = {}
  for _, tag in ipairs(ExtraBars.TAGS) do
    if bc and bc.tags and bc.tags[tag] then out[#out + 1] = L["EXTRABARS_TAG_" .. tag:upper()] end
  end
  return table.concat(out, sep or ", ")
end

-- Nom d'une barre avec ses tags : "Barre 1 - Potions, Flacons & fioles"
function ExtraBars.BarName(i, bc)
  local name = string.format(L["EXTRABARS_BAR_N"], i)
  local tags = ExtraBars.TagsLabel(bc)
  return tags ~= "" and (name .. " - " .. tags) or name
end

-- Objets invoqués (nourriture de mage...) : ligne "Objet invoqué" de l'infobulle, mise en cache
local conjuredCache = {}
local function IsConjured(itemID)
  local c = conjuredCache[itemID]
  if c ~= nil then return c end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not (ok and data and data.lines) then return false end -- pas encore en cache : retenté plus tard
  -- Infobulle d'un objet pas encore chargé : incomplète, ne pas mettre le résultat en cache
  if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
    C_Item.RequestLoadItemDataByID(itemID)
    return false
  end
  c = false
  for _, line in ipairs(data.lines) do
    if line.leftText == ITEM_CONJURED then c = true; break end
  end
  conjuredCache[itemID] = c
  return c
end

-- Objets de connaissance de métier (traités, carnets, objets à étudier) : leur ligne "Utiliser :"
-- parle de la connaissance du métier. Mot-clé par langue du client, cherché dans cette seule ligne
-- (le texte d'ambiance entre guillemets ne compte pas).
local KNOWLEDGE_WORD = ({
  frFR = "connaissance", deDE = "wissen", esES = "conocimiento", esMX = "conocimiento",
  itIT = "conoscenza", ptBR = "conhecimento", ruRU = "знани", koKR = "지식", zhCN = "知识", zhTW = "知識",
})[GetLocale()] or "knowledge"
local knowledgeCache = {}
local function IsKnowledge(itemID)
  local c = knowledgeCache[itemID]
  if c ~= nil then return c end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not (ok and data and data.lines) then return false end -- pas encore en cache : retenté plus tard
  -- Infobulle d'un objet pas encore chargé : incomplète, ne pas mettre le résultat en cache
  if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
    C_Item.RequestLoadItemDataByID(itemID)
    return false
  end
  c = false
  local use = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if type(text) == "string" and text:sub(1, #use) == use and text:lower():find(KNOWLEDGE_WORD, 1, true) then
      c = true
      break
    end
  end
  knowledgeCache[itemID] = c
  return c
end

local function HasUseSpell(itemID)
  local ok, spellName = pcall(C_Item.GetItemSpell, itemID)
  return ok and spellName ~= nil
end

-- Tags d'un objet du sac (bag, slot) : table [tag] = true
local function ItemTags(itemID, bag, slot)
  local tags = {}
  if HEALTHSTONES[itemID] then tags.healthstone = true end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if info and info.hasLoot then tags.openable = true end
  local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
  if quest and (quest.isQuestItem or quest.questID) and HasUseSpell(itemID) then tags.quest = true end
  if HasUseSpell(itemID) and IsKnowledge(itemID) then tags.knowledge = true end
  local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
  if classID == CONSUMABLE and HasUseSpell(itemID) then
    for tag, sub in pairs(SUB) do
      if subClassID == sub then tags[tag] = true end
    end
    if tags.food and IsConjured(itemID) then tags.conjured = true; tags.food = nil end
    if tags.healthstone then tags.potion = nil end
  end
  return tags
end

-- Configuration ----------------------------------------------------------------------------------
local function Cfg() return ns.GetCfg("extraBars") or {} end
local function BarCfg(i)
  local c = Cfg()
  return c.bars and c.bars[i]
end
ExtraBars.BarCfg = BarCfg

-- Réglages copiables d'une barre à l'autre : tout sauf l'activation, les tags et la position
local NOT_COPIED = { enabled = true, tags = true, blacklist = true, x = true, y = true }
function ExtraBars.CopySettings(from, to)
  local src, dst = BarCfg(from), BarCfg(to)
  if not (src and dst) or from == to then return end
  for k, v in pairs(src) do
    if not NOT_COPIED[k] then dst[k] = type(v) == "table" and CopyTable(v) or v end
  end
end

-- Blacklist propre à chaque barre : bc.blacklist[itemID] = true
function ExtraBars.Blacklist(bc)
  if not bc then return {} end
  bc.blacklist = bc.blacklist or {}
  return bc.blacklist
end

-- Ancienne blacklist commune (ns.DB.extraBars.blacklist) : recopiée dans chaque barre, une fois
local function MigrateBlacklist()
  local c = ns.DB and ns.DB.extraBars
  local old = c and c.blacklist
  if not old then return end
  for _, bc in ipairs(c.bars or {}) do
    local bl = ExtraBars.Blacklist(bc)
    for id in pairs(old) do bl[id] = true end
  end
  c.blacklist = nil
end

-- Collecte des objets d'une barre : liste { itemID, invSlot? }, dans l'ordre des tags
local function Collect(bc)
  local blacklist = ExtraBars.Blacklist(bc)
  local wanted = bc and bc.tags or {}
  local rank, entries, seen = {}, {}, {}
  for i, tag in ipairs(ExtraBars.TAGS) do if wanted[tag] then rank[tag] = i end end

  local function Add(entry, tags)
    local best
    for tag in pairs(tags) do
      if rank[tag] and (not best or rank[tag] < best) then best = rank[tag] end
    end
    if best then entry.rank = best; entries[#entries + 1] = entry end
  end

  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local itemID = C_Container.GetContainerItemID(bag, slot)
      if itemID and not seen[itemID] and not blacklist[itemID] then
        seen[itemID] = true
        Add({ itemID = itemID }, ItemTags(itemID, bag, slot))
      end
    end
  end
  if wanted.trinket then
    for _, invSlot in ipairs({ 13, 14 }) do
      local itemID = GetInventoryItemID("player", invSlot)
      if itemID and not blacklist[itemID] and HasUseSpell(itemID) then Add({ invSlot = invSlot, itemID = itemID }, { trinket = true }) end
    end
  end
  table.sort(entries, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.invSlot or b.invSlot then return (a.invSlot or 0) < (b.invSlot or 0) end
    return a.itemID > b.itemID
  end)
  return entries
end

-- Cache du scan des sacs : invalidé par les events de sacs / équipement / données d'objet
-- (bagGen) ou un changement de tags. Sans lui, chaque tick d'un slider du GUI re-scannait
-- tous les sacs pour les 5 barres (+ l'aperçu) : chute de FPS et RAM qui s'envole.
local bagGen = 0
local collectCache = setmetatable({}, { __mode = "k" }) -- [bc] = { gen, sig, entries }
local function TagSig(bc)
  local t = bc and bc.tags
  if not t then return "" end
  local sig = ""
  for _, tag in ipairs(ExtraBars.TAGS) do
    if t[tag] then sig = sig .. tag .. "," end
  end
  return sig
end
local function CollectCached(bc)
  if not bc then return Collect(bc) end
  local c, sig = collectCache[bc], TagSig(bc)
  if c and c.gen == bagGen and c.sig == sig then return c.entries end
  local entries = Collect(bc)
  collectCache[bc] = { gen = bagGen, sig = sig, entries = entries }
  return entries
end
ExtraBars.Collect = CollectCached

function ExtraBars.SetBlacklisted(bc, itemID, on)
  if not bc then return end
  ExtraBars.Blacklist(bc)[itemID] = on and true or nil
  bagGen = bagGen + 1
  ExtraBars.Layout()
end

-- Apparence d'un bouton (partagée avec l'aperçu du GUI) ------------------------------------------
-- Coordonnées de texture : rognage optionnel des bords, puis recadrage au ratio du bouton pour que
-- l'icône ne soit jamais déformée sur un bouton non carré.
function ExtraBars.IconTexCoord(w, h, zoom)
  local l, r, t, b = 0, 1, 0, 1
  if zoom ~= false then l, r, t, b = 0.08, 0.92, 0.08, 0.92 end
  if w > h then
    local cut = ((b - t) - (b - t) * h / w) / 2
    t, b = t + cut, b - cut
  elseif h > w then
    local cut = ((r - l) - (r - l) * w / h) / 2
    l, r = l + cut, r - cut
  end
  return l, r, t, b
end

-- Crée les régions visuelles d'un bouton (secure = bouton d'action réel, sinon aperçu du GUI)
function ExtraBars.CreateVisual(parent, name, secure)
  local b = CreateFrame(secure and "Button" or "Frame", name, parent, secure and "SecureActionButtonTemplate" or nil)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
  b.border:SetPoint("TOPLEFT", -1, 1)
  b.border:SetPoint("BOTTOMRIGHT", 1, -1)
  b.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints()
  b.cooldown:SetDrawEdge(false)
  -- Textes sur un calque AU-DESSUS du balayage du cooldown (sinon recouverts). L'anneau "SLUG"
  -- (ARTWORK) reste sous le texte (OVERLAY) : à l'envers, il noircissait tout le chiffre.
  b.textFrame = CreateFrame("Frame", nil, b)
  b.textFrame:SetAllPoints()
  b.textFrame:SetFrameLevel(b.cooldown:GetFrameLevel() + 2)
  b.count = b.textFrame:CreateFontString(nil, "OVERLAY")
  b.countSlug = ns.CreateSlugRing(b.textFrame, b.count, "ARTWORK")
  b.hotkey = b.textFrame:CreateFontString(nil, "OVERLAY")
  b.hotkeySlug = ns.CreateSlugRing(b.textFrame, b.hotkey, "ARTWORK")
  return b
end

local function StyleText(fs, ring, bc, prefix)
  ns.ApplyTextOutlineStyle(fs, ring, bc[prefix .. "Font"] or DEFAULT_FONT, bc[prefix .. "Size"] or 12,
    bc[prefix .. "Outline"] or "OUTLINE", true)
  fs:SetTextColor(unpack(bc[prefix .. "Color"] or { 1, 1, 1, 1 }))
  local pt = bc[prefix .. "Point"] or "BOTTOMRIGHT"
  fs:ClearAllPoints()
  fs:SetPoint(pt, fs:GetParent(), pt, bc[prefix .. "OffsetX"] or 0, bc[prefix .. "OffsetY"] or 0)
end

-- Arrière-plan de barre (réelle ou aperçu) ----------------------------------------------------------
-- 9-slice maison : les coins gardent bgEdge px quelle que soit la forme de la barre, donc un bord
-- flou ou grunge reste régulier sur une barre très large. `cut` = part de la texture dans un coin.
local BG_DIR = "Interface\\AddOns\\AishCore\\Media\\UI\\"
ExtraBars.BG_TEXTURES = {
  { value = "solid",      file = "Interface\\Buttons\\WHITE8x8",       cut = 0.25 },
  { value = "soft",       file = BG_DIR .. "ExtraBarSoft.tga",       cut = 0.25 },
  { value = "grunge",     file = BG_DIR .. "IconGrungeMask.png",     cut = 0.3 },
  { value = "grungeSoft", file = BG_DIR .. "ExtraBarGrungeSoft.tga", cut = 0.3 },
}
local BG_BY_KEY = {}
for _, d in ipairs(ExtraBars.BG_TEXTURES) do BG_BY_KEY[d.value] = d end
local BG_EDGE_FILE = "Interface\\Buttons\\WHITE8x8"
local BG_UV = { 0, 0, 0, 0 }

local function CreateBackground(holder)
  local bg = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  bg:SetFrameLevel(holder:GetFrameLevel()) -- les boutons (niveau +1) passent devant
  bg.parts = {}
  for k = 1, 9 do bg.parts[k] = bg:CreateTexture(nil, "BACKGROUND") end
  bg.edge = CreateFrame("Frame", nil, bg, "BackdropTemplate")
  bg.edge:SetAllPoints()
  holder.__bg = bg
  return bg
end

-- `w`, `h` : taille du contenu (grille de boutons) ; `show` = false force le masquage (barre vide)
function ExtraBars.StyleBackground(holder, bc, w, h, show)
  local bg = holder.__bg
  if not (bc and bc.bgEnabled and show ~= false) then
    if bg then bg:Hide() end
    return
  end
  bg = bg or CreateBackground(holder)
  local px, py = bc.bgPadX or 6, bc.bgPadY or 6
  local bw, bh = w + 2 * px, h + 2 * py
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT", holder, "TOPLEFT", -px, py)
  bg:SetSize(bw, bh)

  local def = BG_BY_KEY[bc.bgTexture] or BG_BY_KEY.soft
  local e = math.max(0, math.min(bc.bgEdge or 16, bw / 2, bh / 2))
  local c = def.cut
  local xs, ys = { 0, e, bw - e, bw }, { 0, e, bh - e, bh }
  BG_UV[1], BG_UV[2], BG_UV[3], BG_UV[4] = 0, c, 1 - c, 1
  local col = bc.bgColor or { 0, 0, 0, 0.6 }
  local k = 0
  for row = 1, 3 do
    for cl = 1, 3 do
      k = k + 1
      local t = bg.parts[k]
      local tw, th = xs[cl + 1] - xs[cl], ys[row + 1] - ys[row]
      if tw < 0.5 or th < 0.5 then
        t:Hide()
      else
        t:SetTexture(def.file)
        t:SetTexCoord(BG_UV[cl], BG_UV[cl + 1], BG_UV[row], BG_UV[row + 1])
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", bg, "TOPLEFT", xs[cl], -ys[row])
        t:SetSize(tw, th)
        t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
        t:Show()
      end
    end
  end

  local bs = bc.bgBorderSize or 0
  if bs > 0 then
    if bg.edge.__size ~= bs then
      bg.edge:SetBackdrop({ edgeFile = BG_EDGE_FILE, edgeSize = bs })
      bg.edge.__size = bs
    end
    bg.edge:SetBackdropBorderColor(unpack(bc.bgBorderColor or { 0, 0, 0, 1 }))
    bg.edge:Show()
  else
    bg.edge:Hide()
  end
  bg:Show()
end

-- Taille, icône, bordure, cooldown et textes d'un bouton (réel ou aperçu)
function ExtraBars.StyleButton(b, bc, w, h)
  w, h = w or bc.buttonWidth or 32, h or bc.buttonHeight or 32
  b:SetSize(w, h)
  b.icon:SetTexCoord(ExtraBars.IconTexCoord(w, h, bc.iconZoom))
  b.border:SetShown(bc.showBorder ~= false)
  b.border:SetBackdropBorderColor(unpack(bc.borderColor or { 0, 0, 0, 1 }))
  b.cooldown:SetHideCountdownNumbers(bc.showCooldownNumbers == false)
  b.cooldown:SetSwipeColor(0, 0, 0, bc.swipeAlpha or 0.7)
  local cdText = b.cooldown.GetCountdownFontString and b.cooldown:GetCountdownFontString()
  if cdText then
    -- Le compte à rebours natif ne connaît pas l'anneau "SLUG" : contour simple à la place
    local outline = bc.cooldownOutline == "THICKOUTLINE" and "THICKOUTLINE" or "OUTLINE"
    pcall(cdText.SetFont, cdText, bc.cooldownFont or DEFAULT_FONT, bc.cooldownSize or 12, outline)
    cdText:SetTextColor(unpack(bc.cooldownColor or { 1, 1, 1, 1 }))
  end
  StyleText(b.count, b.countSlug, bc, "count")
  b.count:SetShown(bc.showCount ~= false)
  StyleText(b.hotkey, b.hotkeySlug, bc, "keybind")
  b.hotkey:SetShown(bc.showKeybind ~= false)
end

-- Raccourcis clavier ---------------------------------------------------------------------------------
_G.BINDING_HEADER_AISHCOREEXTRABARS = "AishCore - " .. L["SETTINGS_CAT_EXTRA_BARS"]
for i = 1, NUM_BARS do
  for j = 1, NUM_BINDINGS do
    _G["BINDING_NAME_CLICK AishCoreExtraBar" .. i .. "Button" .. j .. ":LeftButton"] =
      string.format(L["EXTRABARS_BINDING_NAME"], i, j)
  end
end

-- Texte court d'un raccourci : "SHIFT-F" -> "SF", "BUTTON4" -> "M4"
function ExtraBars.ShortKey(key)
  if not key then return "" end
  key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("META%-", "M")
  key = key:gsub("BUTTON", "M"):gsub("MOUSEWHEELUP", "MWU"):gsub("MOUSEWHEELDOWN", "MWD")
  key = key:gsub("NUMPAD", "N"):gsub("SPACE", "Spc")
  return key
end

local function KeybindText(i, j)
  if j > NUM_BINDINGS then return "" end
  return ExtraBars.ShortKey(GetBindingKey("CLICK AishCoreExtraBar" .. i .. "Button" .. j .. ":LeftButton"))
end

-- Boutons ----------------------------------------------------------------------------------------
local bars = {}
local pendingLayout = false
local dragUnlocked = false

local function CreateButton(bar, i, j)
  local b = ExtraBars.CreateVisual(bar, "AishCoreExtraBar" .. i .. "Button" .. j, true)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.barIndex, b.buttonIndex = i, j
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.15)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.invSlot then GameTooltip:SetInventoryItem("player", self.invSlot)
    elseif self.itemID then GameTooltip:SetItemByID(self.itemID) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function GetBar(i)
  local bar = bars[i]
  if bar then return bar end
  bar = CreateFrame("Frame", "AishCoreExtraBar" .. i, UIParent, "SecureHandlerStateTemplate")
  bar:SetSize(1, 1)
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  bar.buttons = {}
  -- Poignée de déplacement (affichée seulement quand le placement est déverrouillé)
  bar.mover = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  bar.mover:SetAllPoints()
  bar.mover:SetFrameLevel(bar:GetFrameLevel() + 20)
  bar.mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  bar.mover:SetBackdropColor(0.2, 0.6, 1, 0.25)
  bar.mover:SetBackdropBorderColor(0.35, 0.75, 1, 0.9)
  bar.mover.label = bar.mover:CreateFontString(nil, "OVERLAY")
  bar.mover.label:SetFont(DEFAULT_FONT, 11, "OUTLINE")
  bar.mover.label:SetPoint("BOTTOM", bar.mover, "TOP", 0, 3)
  bar.mover:EnableMouse(true)
  bar.mover:RegisterForDrag("LeftButton")
  bar.mover:SetScript("OnDragStart", function() if not InCombatLockdown() then bar:StartMoving() end end)
  bar.mover:SetScript("OnDragStop", function()
    bar:StopMovingOrSizing()
    local bc = BarCfg(i)
    if not bc then return end
    local cx, cy = bar:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local scale = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    bc.x = math.floor(cx * scale - ux + 0.5)
    bc.y = math.floor(cy * scale - uy + 0.5)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", bc.x, bc.y)
  end)
  bar.mover:Hide()
  bars[i] = bar
  return bar
end

function ExtraBars.GetBarFrame(i) return bars[i] end

-- Compteurs et cooldowns : non protégés, mis à jour aussi en combat
local function RefreshButtonState(b)
  if not b.itemID then return end
  if b.invSlot then
    b.count:SetText("")
    local start, duration = GetInventoryItemCooldown("player", b.invSlot)
    pcall(b.cooldown.SetCooldown, b.cooldown, start or 0, duration or 0)
  else
    local count = C_Item.GetItemCount(b.itemID, false, true) or 0
    b.count:SetText(count > 1 and count or "")
    b.icon:SetDesaturated(count == 0)
    local start, duration = C_Container.GetItemCooldown(b.itemID)
    pcall(b.cooldown.SetCooldown, b.cooldown, start or 0, duration or 0)
  end
end

local function RefreshStates()
  for _, bar in pairs(bars) do
    for _, b in ipairs(bar.buttons) do
      if b:IsShown() then RefreshButtonState(b) end
    end
  end
end

local function RefreshKeybinds()
  for i, bar in pairs(bars) do
    for j, b in ipairs(bar.buttons) do b.hotkey:SetText(KeybindText(i, j)) end
  end
end

-- Grille : colonnes / rangées pour n boutons
function ExtraBars.GridSize(bc, n)
  local per = math.max(1, math.min(bc.buttonsPerRow or 12, math.max(n, 1)))
  local lines = math.max(1, math.ceil(n / per))
  if bc.vertical then return lines, per, per end
  return per, lines, per
end

-- Position (colonne, rangée) du bouton idx depuis le coin de départ
function ExtraBars.GridCell(bc, idx, cols, rows, per)
  local major, minor = (idx - 1) % per, math.floor((idx - 1) / per)
  local col, row
  if bc.vertical then col, row = minor, major else col, row = major, minor end
  local corner = bc.startCorner or "TOPLEFT"
  if corner:find("RIGHT") then col = cols - 1 - col end
  if corner:find("BOTTOM") then row = rows - 1 - row end
  return col, row
end

local function VisibilityDriver(bc)
  local base = "[petbattle][vehicleui] hide; "
  if bc.visibility == "combat" then return base .. "[combat] show; hide" end
  if bc.visibility == "nocombat" then return base .. "[combat] hide; show" end
  return base .. "show"
end

-- Reconstruit une barre (hors combat uniquement)
local function LayoutBar(i)
  local bc = BarCfg(i)
  local bar = GetBar(i)
  local enabled = Cfg().enabled ~= false and bc and bc.enabled
  if not enabled then
    UnregisterStateDriver(bar, "visibility")
    bar:Hide()
    return
  end

  local entries = CollectCached(bc)
  local shown = math.min(#entries, math.min(MAX_BUTTONS, bc.maxButtons or 12))
  -- Placement déverrouillé : une barre vide reste visible (un emplacement) pour pouvoir la déplacer
  local slots = (dragUnlocked and shown == 0) and 1 or shown
  local w, h, gap = bc.buttonWidth or 32, bc.buttonHeight or 32, bc.spacing or 4
  local cols, rows, per = ExtraBars.GridSize(bc, slots)

  for j = 1, math.max(shown, #bar.buttons) do
    local b = bar.buttons[j]
    local e = entries[j]
    if j <= shown then
      if not b then b = CreateButton(bar, i, j); bar.buttons[j] = b end
      b.itemID, b.invSlot = e.itemID, e.invSlot
      b:SetAttribute("type", "item")
      b:SetAttribute("item", e.invSlot and tostring(e.invSlot) or ("item:" .. e.itemID))
      b.icon:SetTexture(C_Item.GetItemIconByID(e.itemID) or PLACEHOLDER_ICON)
      ExtraBars.StyleButton(b, bc, w, h)
      b.hotkey:SetText(KeybindText(i, j))
      local col, row = ExtraBars.GridCell(bc, j, cols, rows, per)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (w + gap), -row * (h + gap))
      b:Show()
      RefreshButtonState(b)
    elseif b then
      b.itemID, b.invSlot = nil, nil
      b:SetAttribute("item", nil)
      b:Hide()
    end
  end

  local gw, gh = math.max(1, cols * w + (cols - 1) * gap), math.max(1, rows * h + (rows - 1) * gap)
  bar:SetSize(gw, gh)
  ExtraBars.StyleBackground(bar, bc, gw, gh, shown > 0 or dragUnlocked)
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", UIParent, "CENTER", bc.x or 0, bc.y or 0)
  bar.mover.label:SetText(ExtraBars.BarName(i, bc))
  bar.mover:SetShown(dragUnlocked)
  -- En mode survol, l'opacité appartient au fondu : la remettre à fond ferait clignoter la barre
  if not bc.mouseover or dragUnlocked then bar:SetAlpha(bc.alpha or 1) end
  bar.__cfg = bc
  if dragUnlocked then
    UnregisterStateDriver(bar, "visibility")
    bar:Show()
  else
    RegisterStateDriver(bar, "visibility", VisibilityDriver(bc))
  end
end

function ExtraBars.Layout()
  if InCombatLockdown() then pendingLayout = true; return end
  pendingLayout = false
  for i = 1, NUM_BARS do pcall(LayoutBar, i) end
end

-- Survol : fondu vers l'opacité cible (SetAlpha n'est pas protégé, fonctionne en combat).
-- Apparition rapide, disparition plus douce ; durées pour un fondu complet, en secondes.
local FADE_IN, FADE_OUT = 0.15, 0.4
local hoverFrame = CreateFrame("Frame")
local function UpdateHover(_, elapsed)
  local any = false
  for _, bar in pairs(bars) do
    local bc = bar.__cfg
    if bc and bc.mouseover and bar:IsShown() and not dragUnlocked then
      any = true
      local full, low = bc.alpha or 1, bc.mouseoverAlpha or 0
      local target = bar:IsMouseOver() and full or low
      local cur = bar:GetAlpha()
      if cur ~= target then
        local span = math.max(math.abs(full - low), 0.01)
        local step = span * elapsed / (target > cur and FADE_IN or FADE_OUT)
        if math.abs(target - cur) <= step then
          cur = target
        elseif target > cur then
          cur = cur + step
        else
          cur = cur - step
        end
        bar:SetAlpha(cur)
      end
    end
  end
  if not any then
    hoverFrame:SetScript("OnUpdate", nil)
    hoverFrame.on = false
  end
end
local function StartHover()
  if hoverFrame.on then return end
  hoverFrame.on = true
  hoverFrame:SetScript("OnUpdate", UpdateHover)
end

function ExtraBars.ApplySettings()
  MigrateBlacklist()
  ExtraBars.Layout()
  for _, bar in pairs(bars) do
    if bar.__cfg and bar.__cfg.mouseover then StartHover(); break end
  end
end

-- Placement : affiche les poignées et toutes les barres actives (même vides) pour les déplacer
function ExtraBars.SetDragUnlocked(val)
  dragUnlocked = val and true or false
  ExtraBars.Layout()
end
function ExtraBars.IsDragUnlocked() return dragUnlocked end

-- Événements ---------------------------------------------------------------------------------------
local layoutQueued = false
local function QueueLayout()
  if layoutQueued then return end
  layoutQueued = true
  C_Timer.After(0.2, function() layoutQueued = false; ExtraBars.Layout() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_BINDINGS")
ev:SetScript("OnEvent", function(_, event)
  if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
    RefreshStates()
  elseif event == "UPDATE_BINDINGS" then
    RefreshKeybinds()
  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingLayout then ExtraBars.Layout() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    ExtraBars.ApplySettings()
  else
    -- Sacs / équipement / données d'objet arrivées : en combat, seuls les compteurs bougent
    bagGen = bagGen + 1
    if InCombatLockdown() then pendingLayout = true; RefreshStates() else QueueLayout() end
  end
end)

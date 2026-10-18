-- Modules/MenuBar.lua : "Barre de menu" -- remplace la barre de menu Blizzard (micro menu) par une barre personnalisable :
-- raccourcis (personnage, grimoire, talents...) repartis en deux listes (gauche / droite) autour d'une horloge optionnelle.
-- Le "strip" (NewStrip) est partage entre la vraie barre et l'apercu epingle de la page de reglages (UI/MenuBarPage.lua),
-- qui ajoute en plus le choix de l'action au clic, le glisser-deposer et les boutons "+".
-- Les actions passent par des boutons securises (macro /click ou /run) : pas de taint, la barre marche en combat.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local MenuBar = {}
ns.Modules.MenuBar = MenuBar

local DEFAULT_FONT = "Fonts\\2002.TTF"
local HOVER_TIME, SWAP_TIME = 0.12, 0.22
local HOVER_GROW = 0.12
local TEX_COORD = { 0.08, 0.92, 0.08, 0.92 }

MenuBar.MAX_PER_SIDE = 8
-- Listes par defaut : volontairement absentes de Config/Defaults.lua (MergeDefaults ressusciterait les cases retirees)
MenuBar.DEFAULT_SLOTS = {
  left  = { "character", "spellbook" },
  right = { "achievements", "gamemenu" },
}

local function Cfg()
  return ns.GetCfg("menuBar") or {}
end

local function Loc(key)
  return (ns.L and ns.L[key]) or key
end

-- Une ligne de tooltip par commande : le texte localise separe ses lignes par "\n"
local function AddLines(text, r, g, b)
  for line in tostring(text):gmatch("[^\n]+") do GameTooltip:AddLine(line, r or 0.7, g or 0.7, b or 0.7, true) end
end

-- Couleur thematique du module Couleurs si l'option `flag` n'est pas decochee, sinon couleur propre du reglage
local function ThemeColor(cfg, flag, element, own, default)
  if cfg[flag] ~= false then
    local CL = ns.Modules.Colors
    local c = CL and CL.Get and CL.Get(element)
    if c then return c end
  end
  return own or default
end

local function Ease(v)
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  return v * v * (3 - 2 * v)
end

-- Actions ------------------------------------------------------------------------------------------
local function ClickBtn(name)
  return _G[name] and ("/click " .. name) or nil
end

local ICON_DIR = "Interface\\Icons\\"

-- Changement de specialisation (Ctrl + clic sur Talents) : hors combat, et seulement si elle n'est pas deja active
function _G.AishCoreMenuBar_Spec(index)
  if InCombatLockdown() then return end
  local get = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or _G.GetSpecialization
  local set = (C_SpecializationInfo and C_SpecializationInfo.SetSpecialization) or _G.SetSpecialization
  if not (get and set) or get() == index then return end
  set(index)
end

-- Metiers : ouvre (ou ferme) la fenetre d'un metier. which = 1 / 2 (metiers principaux), "cooking", "fishing",
-- "archaeology". Fonction globale : appelee par les macros du raccourci "Metiers" (cf. mods ci-dessous).
function _G.AishCoreMenuBar_Profession(which)
  if not _G.GetProfessions then return end
  local p1, p2, arch, fish, cook, aid = _G.GetProfessions()
  -- Forever : les Premiers soins sont renvoyes en 3e position, celle de l'Archeologie en Retail
  if ns.IsForever then aid, arch = aid or arch, nil end
  local idx = ({ [1] = p1, [2] = p2, archaeology = arch, fishing = fish, cooking = cook, firstaid = aid })[which]
  if not idx then return end
  if which == "archaeology" then
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_ArchaeologyUI") end
    local f = _G.ArchaeologyFrame
    if f then
      if f:IsShown() then HideUIPanel(f) else ShowUIPanel(f) end
    end
    return
  end
  local _, _, _, _, numSpells, spellOffset, skillLine = _G.GetProfessionInfo(idx)
  if not (skillLine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill) then
    -- Forever : pas de C_TradeSkillUI.OpenTradeSkill, on lance le premier sort du metier (ouvre sa fenetre)
    if spellOffset and (numSpells or 0) > 0 then
      if C_SpellBook and C_SpellBook.CastSpellBookItem and Enum and Enum.SpellBookSpellBank then
        pcall(C_SpellBook.CastSpellBookItem, spellOffset + 1, Enum.SpellBookSpellBank.Player)
      elseif _G.CastSpell then
        pcall(_G.CastSpell, spellOffset + 1, "spell")
      end
    end
    return
  end
  local pf = _G.ProfessionsFrame
  if pf and pf:IsShown() then
    local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
    if base and base.professionID == skillLine then HideUIPanel(pf); return end
  end
  C_TradeSkillUI.OpenTradeSkill(skillLine)
end

-- Guide de l'aventurier : ouvre (ou ferme) sur l'onglet "Journal de voyage" ; fonction globale car trop longue pour une macro
function _G.AishCoreMenuBar_Adventure()
  if not _G.ToggleEncounterJournal then return end
  local function Select()
    local e = _G.EncounterJournal
    local t = e and e.MonthlyActivitiesTab
    if t and _G.EJ_ContentTab_Select then _G.EJ_ContentTab_Select(t:GetID()) end
  end
  local f = _G.EncounterJournal
  if f and f:IsShown() then
    local t = f.MonthlyActivitiesTab
    if not t or f.selectedTab == nil or f.selectedTab == t:GetID() then HideUIPanel(f) else Select() end
  else
    _G.ToggleEncounterJournal()
    Select()
  end
end

-- macro() renvoie le texte de la macro, ou nil si l'action n'existe pas sur ce client
MenuBar.ACTIONS = {
  { id = "character", icon = "INV_Chest_Cloth_17", macro = function() return ClickBtn("CharacterMicroButton") end },
  { id = "spellbook", icon = "INV_Misc_Book_09", macro = function()
      if _G.PlayerSpellsUtil and _G.PlayerSpellsUtil.ToggleSpellBookFrame then
        return "/run PlayerSpellsUtil.ToggleSpellBookFrame()"
      end
      return ClickBtn("SpellbookMicroButton")
    end },
  { id = "talents", icon = "Ability_Marksmanship",
    mods = function()
      if ns.IsForever then return {} end   -- Forever : pas de specialisations
      local function Spec(i) return "/run AishCoreMenuBar_Spec(" .. i .. ")" end
      return { ["shift-1"] = Spec(1), ["ctrl-1"] = Spec(2), ["alt-1"] = Spec(3), ["alt-ctrl-1"] = Spec(4) }
    end,
    macro = function()
      if _G.PlayerSpellsUtil and _G.PlayerSpellsUtil.ToggleClassTalentFrame then
        return "/run PlayerSpellsUtil.ToggleClassTalentFrame()"
      end
      return ClickBtn("TalentMicroButton")
    end },
  { id = "achievements", icon = "Achievement_General", macro = function() return ClickBtn("AchievementMicroButton") end },
  { id = "quests", icon = "INV_Misc_Note_01", macro = function() return ClickBtn("QuestLogMicroButton") end },
  { id = "guild", icon = "INV_Shirt_GuildTabard_01", macro = function()
      return ClickBtn("GuildMicroButton") or ClickBtn("SocialsMicroButton")
    end },
  { id = "groupfinder", icon = "INV_Misc_GroupNeedMore", macro = function() return ClickBtn("LFDMicroButton") end },
  { id = "adventure", icon = "INV_Misc_Head_Dragon_01", macro = function()
      if _G.ToggleEncounterJournal then return "/run AishCoreMenuBar_Adventure()" end
      return ClickBtn("EJMicroButton")
    end },
  { id = "collections", icon = "Ability_Mount_RidingHorse", macro = function() return ClickBtn("CollectionsMicroButton") end },
  { id = "toybox", icon = "INV_Misc_Toy_10", macro = function()
      if not _G.ToggleCollectionsJournal then return nil end
      return "/run local f=CollectionsJournal if f and f:IsShown() then if PanelTemplates_GetSelectedTab(f)==3 then HideUIPanel(f) else CollectionsJournal_SetTab(f,3) end else ToggleCollectionsJournal(3) end"
    end },
  { id = "petjournal", icon = "INV_Box_PetCarrier_01", macro = function()
      if not _G.ToggleCollectionsJournal then return nil end
      return "/run local f=CollectionsJournal if f and f:IsShown() then if PanelTemplates_GetSelectedTab(f)==2 then HideUIPanel(f) else CollectionsJournal_SetTab(f,2) end else ToggleCollectionsJournal(2) end"
    end },
  -- Clic gauche : fenetre des metiers ; clics avec modificateur : metier precis (cf. AishCoreMenuBar_Profession)
  { id = "professions", icon = "Trade_BlackSmithing", macro = function() return ClickBtn("ProfessionMicroButton") end,
    mods = function()
      local function Run(w) return "/run AishCoreMenuBar_Profession(" .. w .. ")" end
      -- Forever : Premiers soins absent de GetProfessions sur ce client -> la macro lance directement le sort du metier
      -- (nom traduit par le jeu, tous rangs confondus), comme un clic dans le livre de sorts : sa fenetre s'ouvre.
      -- Ordre des modificateurs dans les attributs securises : alt-ctrl-shift
      return { ["shift-1"] = Run(1), ["ctrl-1"] = Run(2), ["alt-1"] = Run('"cooking"'), ["ctrl-shift-1"] = Run('"fishing"'),
               ["alt-ctrl-1"] = Run(ns.IsForever and '"firstaid"' or '"archaeology"') }
    end },
  { id = "shop", icon = "INV_Misc_Coin_01", macro = function() return ClickBtn("StoreMicroButton") end },
  { id = "housing", icon = "INV_Misc_Key_03", macro = function()
      if _G.HousingFramesUtil and _G.HousingFramesUtil.ToggleHousingDashboard then
        return "/run HousingFramesUtil.ToggleHousingDashboard()"
      end
      return ClickBtn("HousingMicroButton")
    end },
  { id = "friends", icon = "Achievement_Reputation_01", macro = function()
      return _G.ToggleFriendsFrame and "/run ToggleFriendsFrame()" or nil
    end },
  { id = "map", icon = "INV_Misc_Map_01", macro = function()
      return _G.ToggleWorldMap and "/run ToggleWorldMap()" or nil
    end },
  { id = "bags", icon = "INV_Misc_Bag_08", macro = function()
      return _G.ToggleAllBags and "/run ToggleAllBags()" or nil
    end },
  { id = "calendar", icon = "INV_Scroll_03", macro = function()
      return "/run if ToggleCalendar then ToggleCalendar() end"
    end },
  { id = "gamemenu", icon = "INV_Misc_Gear_01", macro = function()
      if not _G.GameMenuFrame then return nil end
      return "/run if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end"
    end },
  { id = "reload", icon = "INV_Misc_Gear_08", macro = function() return "/reload" end },
  { id = "hearthstone", icon = "INV_Misc_Rune_01", macro = function() return "/use item:6948" end },
  { id = "screenshot", icon = "INV_Misc_Spyglass_03", macro = function() return "/run Screenshot()" end },
  -- Clic : coupe / remet tout le son ; Maj+clic : musique ; Ctrl+clic : effets sonores (sans la musique) ;
  -- molette sur le raccourci : volume general
  { id = "volume", icon = "INV_Misc_Horn_01", macro = function()
      return '/run SetCVar("Sound_EnableAllSound", GetCVar("Sound_EnableAllSound") == "1" and "0" or "1")'
    end,
    mods = function()
      local function Toggle(c) return ('/run SetCVar("%s", GetCVar("%s") == "1" and "0" or "1")'):format(c, c) end
      return { ["shift-1"] = Toggle("Sound_EnableMusic"), ["ctrl-1"] = Toggle("Sound_EnableSFX") }
    end },
  -- Case vide : sert d'espaceur (invisible sur la vraie barre)
  { id = "none", spacer = true, macro = function() return nil end },
}
local BY_ID = {}
for _, a in ipairs(MenuBar.ACTIONS) do BY_ID[a.id] = a end

-- Forever : fonctions qui n'existent pas sur ce client (indisponibles : absentes du menu, grisees si deja posees)
if ns.IsForever then
  for _, id in ipairs({ "groupfinder", "adventure", "toybox", "petjournal", "housing", "shop" }) do
    if BY_ID[id] then BY_ID[id].macro = function() return nil end end
  end
end

function MenuBar.GetAction(id) return BY_ID[id] end
function MenuBar.ActionName(id)
  -- Forever : les hauts faits sont ceux d'"Heritage"
  if ns.IsForever and id == "achievements" then return Loc("MENUBAR_ACT_ACHIEVEMENTS_LEGACY") end
  return Loc("MENUBAR_ACT_" .. tostring(id):upper())
end
function MenuBar.ActionAvailable(id)
  local a = BY_ID[id]
  return a ~= nil and (a.spacer or a.macro() ~= nil)
end

-- Listes de raccourcis ---------------------------------------------------------------------------
function MenuBar.GetSlots(side)
  local list = Cfg()[side]
  if type(list) ~= "table" then list = MenuBar.DEFAULT_SLOTS[side] end
  return list
end

-- Liste modifiable : recopiee dans la DB au premier edit
local function EditSlots(side)
  ns.DB = ns.DB or {}
  ns.DB.menuBar = ns.DB.menuBar or {}
  local db = ns.DB.menuBar
  if type(db[side]) ~= "table" then
    db[side] = ns.DeepCopy and ns.DeepCopy(MenuBar.DEFAULT_SLOTS[side]) or { unpack(MenuBar.DEFAULT_SLOTS[side]) }
  end
  return db[side]
end

function MenuBar.SetSlot(side, idx, id)
  local list = EditSlots(side)
  if list[idx] then list[idx] = id end
end

function MenuBar.RemoveSlot(side, idx)
  table.remove(EditSlots(side), idx)
end

-- Ajout au bord exterieur du cote voulu : premier raccourci pas encore utilise
function MenuBar.AddSlot(side)
  local list = EditSlots(side)
  if #list >= MenuBar.MAX_PER_SIDE then return false end
  local used = {}
  for _, s in ipairs({ "left", "right" }) do
    for _, id in ipairs(MenuBar.GetSlots(s)) do used[id] = true end
  end
  local pick = "gamemenu"
  for _, a in ipairs(MenuBar.ACTIONS) do
    if not used[a.id] and not a.spacer and a.macro() then pick = a.id; break end
  end
  if side == "left" then table.insert(list, 1, pick) else list[#list + 1] = pick end
  return true
end

function MenuBar.SwapSlots(sideA, idxA, sideB, idxB)
  local a, b = EditSlots(sideA), EditSlots(sideB)
  if a[idxA] and b[idxB] then a[idxA], b[idxB] = b[idxB], a[idxA] end
end

-- Strip : rendu de la barre (reel ou apercu) ------------------------------------------------------
local Strip = {}
Strip.__index = Strip
local strips = {}   -- tous les strips (horloge mise a jour par un ticker commun)

local function OutlineFlags(style)
  if style == "THICKOUTLINE" then return "THICKOUTLINE" end
  if style == "NONE" then return "" end
  return "OUTLINE"
end

local function CreateClock(S)
  local c = CreateFrame("Button", nil, S.content, (not S.preview) and "SecureActionButtonTemplate" or nil)
  if S.preview then c:RegisterForClicks("AnyUp") else c:RegisterForClicks("AnyDown", "AnyUp") end
  -- Declenche au relachement quel que soit le cvar ActionButtonUseKeyDown (sinon le bouton securise ignore le clic)
  if not S.preview then c:SetAttribute("useOnKeyDown", false) end
  c.h = c:CreateFontString(nil, "OVERLAY")
  c.c = c:CreateFontString(nil, "OVERLAY")
  c.m = c:CreateFontString(nil, "OVERLAY")
  c.a = c:CreateFontString(nil, "OVERLAY")
  for _, fs in ipairs({ c.h, c.c, c.m, c.a }) do fs:SetFont(DEFAULT_FONT, 14, "OUTLINE") end
  c.c:SetText(":")
  c.h:SetJustifyH("RIGHT")
  c.m:SetJustifyH("LEFT")
  c.a:SetJustifyH("LEFT")
  c:SetScript("OnEnter", function(self)
    if S.preview and not Cfg().tooltip then return end
    if Cfg().tooltip == false then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Loc("MENUBAR_ACT_CLOCK"), 1, 1, 1)
    AddLines(Loc("MENUBAR_CLOCK_TT"))
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return c
end

function Strip:StyleClock(cfg)
  local c = self.clock
  local size = cfg.clockSize or 22
  local font = cfg.clockFont or DEFAULT_FONT
  local flags = OutlineFlags(cfg.clockOutline)
  for _, fs in ipairs({ c.h, c.c, c.m, c.a }) do
    if not pcall(fs.SetFont, fs, font, size, flags) or not fs:GetFont() then fs:SetFont(DEFAULT_FONT, size, flags) end
    local col = ThemeColor(cfg, "clockThemed", "powercircle", cfg.clockColor, { 0.95, 0.78, 0.40, 1 })
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
  end
  -- Largeur fixe (chiffres les plus larges) : l'heure ne "danse" pas quand les chiffres changent
  c.h:SetText("88")
  local dw = c.h:GetStringWidth()
  local cw = c.c:GetStringWidth()
  c.dw, c.cw = dw, cw
  c.c:ClearAllPoints()
  c.c:SetPoint("LEFT", c, "LEFT", dw, 0)
  c.h:ClearAllPoints()
  c.h:SetPoint("RIGHT", c.c, "LEFT", 0, 0)
  c.m:ClearAllPoints()
  c.m:SetPoint("LEFT", c.c, "RIGHT", 0, 0)
  c.a:ClearAllPoints()
  c.a:SetPoint("LEFT", c.m, "RIGHT", 3, 0)
  local width = dw * 2 + cw
  if cfg.clock24 == false then
    c.a:SetText("PM")
    width = width + 3 + c.a:GetStringWidth()
  end
  c.a:SetShown(cfg.clock24 == false)
  return width, size + 4
end

function Strip:UpdateClock()
  local c, cfg = self.clock, Cfg()
  if not c or not c:IsShown() then return end
  local h, m
  if cfg.clockServer then
    h, m = GetGameTime()
  else
    local t = date("*t")
    h, m = t.hour, t.min
  end
  if cfg.clock24 == false then
    c.a:SetText(h >= 12 and "PM" or "AM")
    h = h % 12
    if h == 0 then h = 12 end
    c.h:SetText(h)
  else
    c.h:SetText(string.format("%02d", h))
  end
  c.m:SetText(string.format("%02d", m))
  if cfg.clockBlink == false then
    c.c:SetAlpha(1)
  else
    c.c:SetAlpha((math.floor(GetTime() * 2) % 2 == 0) and 1 or 0.15)
  end
end

-- Couleur / echelle / decalage de l'icone selon l'etat de survol et d'animation d'echange
function Strip:Paint(b)
  local cfg = Cfg()
  local c = ThemeColor(cfg, "iconThemed", "powertext", cfg.iconColor, { 0.86, 0.86, 0.86, 1 })
  local hc = (cfg.hoverEnabled ~= false) and ThemeColor(cfg, "hoverThemed", "powerdotsb", cfg.hoverColor, { 1, 0.82, 0.2, 1 }) or c
  local h = b._h or 0
  b.icon:SetVertexColor(c[1] + (hc[1] - c[1]) * h, c[2] + (hc[2] - c[2]) * h, c[3] + (hc[3] - c[3]) * h,
                        (c[4] or 1) + ((hc[4] or 1) - (c[4] or 1)) * h)
  b.vis:SetScale(1 + ((cfg.hoverGrow ~= false) and HOVER_GROW or 0) * h)
  b.icon:ClearAllPoints()
  b.icon:SetPoint("CENTER", b.vis, "CENTER", (b._sx or 0) * (1 - Ease(b._sp or 1)), 0)
end

-- Changement de couleurs thematiques : repeint sans toucher a la mise en page (sur, meme en combat)
function Strip:Recolor()
  local cfg = Cfg()
  local col = ThemeColor(cfg, "clockThemed", "powercircle", cfg.clockColor, { 0.95, 0.78, 0.40, 1 })
  for _, fs in ipairs({ self.clock.h, self.clock.c, self.clock.m, self.clock.a }) do
    fs:SetTextColor(col[1], col[2], col[3], col[4] or 1)
  end
  for _, b in ipairs(self.pool) do
    if b:IsShown() and b.actionId then self:Paint(b) end
  end
end

function Strip:Kick()
  if self._driving then return end
  self._driving = true
  self.driver:SetScript("OnUpdate", function(_, el)
    local active = false
    for _, b in ipairs(self.pool) do
      if b:IsShown() then
        local ht = b._ht or 0
        local h = b._h or 0
        if h ~= ht then
          local step = el / HOVER_TIME
          h = (ht > h) and math.min(ht, h + step) or math.max(ht, h - step)
          b._h = h
        end
        local sp = b._sp or 1
        if sp < 1 then b._sp = math.min(1, sp + el / SWAP_TIME) end
        if h ~= ht or (b._sp or 1) < 1 then active = true end
        self:Paint(b)
      end
    end
    if not active then
      self.driver:SetScript("OnUpdate", nil)
      self._driving = false
    end
  end)
end

function Strip:SetHover(b, on)
  b._ht = on and 1 or 0
  self:Kick()
end

-- Echange anime : chaque icone glisse depuis la place de l'autre
function Strip:AnimateSwap(a, b)
  if not (a and b) then return end
  local dx = (b._cx or 0) - (a._cx or 0)
  a._sx, a._sp = dx, 0
  b._sx, b._sp = -dx, 0
  self:Kick()
end

local ghost

-- Curseur hors de l'apercu (ni sur la barre, ni sur un "+") : lacher ici retire le raccourci
local function IsOutside(S)
  if S.frame:IsMouseOver() then return false end
  if S.plusL and (S.plusL:IsMouseOver() or S.plusR:IsMouseOver()) then return false end
  return true
end

local function StartGhost(src, S)
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(1, 1)
    ghost.tex = ghost:CreateTexture(nil, "OVERLAY")
    ghost.tex:SetPoint("CENTER")
    ghost.tex:SetTexCoord(unpack(TEX_COORD))
    -- Petite croix rouge : suppression si on lache ici
    ghost.cross = ghost:CreateFontString(nil, "OVERLAY")
    ghost.cross:SetFont(DEFAULT_FONT, 16, "OUTLINE")
    ghost.cross:SetTextColor(1, 0.15, 0.15, 1)
    ghost.cross:SetText("X")
    ghost.cross:SetPoint("CENTER", ghost.tex, "TOPRIGHT", -2, -2)
    ghost.cross:Hide()
  end
  ghost.out = false
  ghost.cross:Hide()
  local sz = src.icon:GetWidth() * src.icon:GetEffectiveScale() / UIParent:GetEffectiveScale()
  ghost.tex:SetSize(sz, sz)
  ghost.tex:SetTexture(src.icon:GetTexture())
  ghost.tex:SetVertexColor(1, 1, 1, 0.9)
  ghost:SetScript("OnUpdate", function(f)
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    local out = IsOutside(S)
    if out ~= f.out then
      f.out = out
      f.cross:SetShown(out)
      f.tex:SetVertexColor(1, out and 0.6 or 1, out and 0.6 or 1, 0.9)
      if out then
        GameTooltip:SetOwner(f.tex, "ANCHOR_RIGHT")
        GameTooltip:SetText(Loc("MENUBAR_DROP_REMOVE"), 1, 0.3, 0.3)
        GameTooltip:Show()
      else
        GameTooltip:Hide()
      end
    end
  end)
  ghost:Show()
end
local function StopGhost()
  if ghost then
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
    if ghost.out then GameTooltip:Hide() end
  end
end

function Strip:NewSlot()
  local S = self
  local b = CreateFrame("Button", nil, self.content, (not self.preview) and "SecureActionButtonTemplate" or nil)
  if self.preview then b:RegisterForClicks("AnyUp") else b:RegisterForClicks("AnyDown", "AnyUp") end
  if not self.preview then b:SetAttribute("useOnKeyDown", false) end
  b.vis = CreateFrame("Frame", nil, b)
  b.vis:SetPoint("CENTER", b, "CENTER")
  b.icon = b.vis:CreateTexture(nil, "ARTWORK")
  b.icon:SetTexCoord(unpack(TEX_COORD))
  if self.preview then
    b.hl = b.vis:CreateTexture(nil, "BACKGROUND")
    b.hl:SetColorTexture(1, 1, 1, 0.10)
    b.hl:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -3, 3)
    b.hl:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 3, -3)
    b.hl:Hide()
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnClick", function(self2, button)
      if self2._dragged then return end
      if S.onSlotClick then S.onSlotClick(self2, button) end
    end)
    b:SetScript("OnDragStart", function(self2)
      self2._dragged = true
      self2.vis:SetAlpha(0.3)
      StartGhost(self2, S)
    end)
    b:SetScript("OnDragStop", function(self2)
      local removing = ghost and ghost.out
      StopGhost()
      self2.vis:SetAlpha(1)
      if removing then
        C_Timer.After(0, function() self2._dragged = false end)
        if S.onRemove then S.onRemove(self2) end
        return
      end
      local target
      for _, o in ipairs(S.pool) do
        if o ~= self2 and o:IsShown() and o:IsMouseOver() then target = o; break end
      end
      C_Timer.After(0, function() self2._dragged = false end)
      if target and S.onSwap then S.onSwap(self2, target) end
    end)
  end
  local function ShowTip(self2)
    GameTooltip:SetOwner(self2, "ANCHOR_BOTTOM")
    GameTooltip:SetText(MenuBar.ActionName(self2.actionId), 1, 1, 1)
    if S.preview then
      AddLines(Loc("MENUBAR_SLOT_HINT"))
    elseif not MenuBar.ActionAvailable(self2.actionId) then
      GameTooltip:AddLine(Loc("MENUBAR_UNAVAILABLE"), 1, 0.3, 0.3, true)
    elseif self2.actionId == "talents" then
      AddLines(Loc("MENUBAR_TALENTS_TT"))
      local mods = ns.IsForever and {} or { "MENUBAR_MOD_SHIFT", "MENUBAR_MOD_CTRL", "MENUBAR_MOD_ALT", "MENUBAR_MOD_CTRLALT" }
      local n = _G.GetNumSpecializations and _G.GetNumSpecializations() or 4
      for i = 1, ns.IsForever and 0 or math.min(4, n) do
        local name = _G.GetSpecializationInfo and select(2, _G.GetSpecializationInfo(i))
        AddLines(string.format(Loc("MENUBAR_TALENTS_SPEC"), Loc(mods[i]), name or ("#" .. i)))
      end
    elseif self2.actionId == "professions" then
      -- Noms reels des deux metiers principaux
      -- Pas de "GetProfessions and GetProfessions()" : un "and" ne garde que la 1re valeur (2e metier perdu)
      local p1, p2
      if _G.GetProfessions then p1, p2 = _G.GetProfessions() end
      local function PName(idx, fallback)
        local n = idx and _G.GetProfessionInfo and _G.GetProfessionInfo(idx)
        return n or Loc(fallback)
      end
      AddLines(string.format(Loc(ns.IsForever and "MENUBAR_PROF_TT_FOREVER" or "MENUBAR_PROF_TT"), PName(p1, "MENUBAR_PROF_MAIN"), PName(p2, "MENUBAR_PROF_SECOND")))
    elseif self2.actionId == "volume" then
      local on = GetCVar("Sound_EnableAllSound") == "1"
      local v = math.floor((tonumber(GetCVar("Sound_MasterVolume")) or 1) * 100 + 0.5)
      AddLines(string.format(Loc("MENUBAR_VOLUME_TT"), on and (v .. "%") or Loc("MENUBAR_MUTED")), 1, 0.82, 0.2)
      -- Musique / effets : "Muet" quand leur interrupteur est coupe (Maj / Ctrl + clic)
      local function Level(enableCvar, volCvar)
        if GetCVar(enableCvar) == "0" then return Loc("MENUBAR_MUTED") end
        return math.floor((tonumber(GetCVar(volCvar)) or 1) * 100 + 0.5) .. "%"
      end
      AddLines(string.format(Loc("MENUBAR_VOLUME_TT3"), Level("Sound_EnableMusic", "Sound_MusicVolume"),
        Level("Sound_EnableSFX", "Sound_SFXVolume")), 1, 0.82, 0.2)
      AddLines(Loc("MENUBAR_VOLUME_TT2"))
    end
    GameTooltip:Show()
  end
  -- Apres un clic (macro executee a ce moment) : le tooltip affiche l'etat a jour
  if not self.preview then
    b:HookScript("PostClick", function(self2)
      if self2.actionId == "volume" then
        C_Timer.After(0.05, function()
          if GameTooltip:GetOwner() == self2 then ShowTip(self2) end
        end)
      end
    end)
  end
  b:SetScript("OnMouseWheel", function(self2, delta)
    if S.preview or self2.actionId ~= "volume" then return end
    -- Maj : musique seule ; Ctrl : effets sonores seuls ; sinon volume general
    local cvar = IsShiftKeyDown() and "Sound_MusicVolume" or IsControlKeyDown() and "Sound_SFXVolume" or "Sound_MasterVolume"
    local v = tonumber(GetCVar(cvar)) or 1
    SetCVar(cvar, math.max(0, math.min(1, v + delta * 0.05)))
    if GameTooltip:GetOwner() == self2 then ShowTip(self2) end
  end)
  b:SetScript("OnEnter", function(self2)
    S:SetHover(self2, true)
    if self2.hl then self2.hl:Show() end
    if not S.preview and Cfg().tooltip == false then return end
    ShowTip(self2)
  end)
  b:SetScript("OnLeave", function(self2)
    S:SetHover(self2, false)
    if self2.hl then self2.hl:Hide() end
    GameTooltip:Hide()
  end)
  self.pool[#self.pool + 1] = b
  return b
end

local function NewPlus(S, side)
  local p = CreateFrame("Button", nil, S.frame)
  p.bg = p:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints()
  p.bg:SetColorTexture(0, 0, 0, 0.4)   -- carre noir transparent : visible sur les fonds clairs
  p.fs = p:CreateFontString(nil, "OVERLAY")
  p.fs:SetFont(DEFAULT_FONT, 16, "OUTLINE")
  p.fs:SetPoint("CENTER", 0, 1)
  p.fs:SetText("+")
  p.fs:SetTextColor(0.8, 0.8, 0.8, 1)
  p:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(1, 0.82, 0.2, 0.25)
    self.fs:SetTextColor(1, 0.82, 0.2, 1)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(Loc("MENUBAR_ADD_SLOT"), 1, 1, 1)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0, 0, 0, 0.4)
    self.fs:SetTextColor(0.8, 0.8, 0.8, 1)
    GameTooltip:Hide()
  end)
  p:SetScript("OnClick", function() if S.onAdd then S.onAdd(side) end end)
  return p
end

function Strip:Layout()
  local cfg = Cfg()
  local size = cfg.iconSize or 22
  local gap = cfg.spacing or 10
  local lefts, rights = MenuBar.GetSlots("left"), MenuBar.GetSlots("right")
  local clockOn = cfg.clockEnabled ~= false
  local pos = cfg.clockPos or "center"

  local n = 0
  local order = {}
  local function Push(side, list)
    for i, id in ipairs(list) do
      n = n + 1
      local b = self.pool[n] or self:NewSlot()
      b.side, b.idx, b.actionId = side, i, id
      order[#order + 1] = b
    end
  end
  if clockOn and pos == "left" then order[#order + 1] = self.clock end
  Push("left", lefts)
  if clockOn and pos == "center" then order[#order + 1] = self.clock end
  Push("right", rights)
  if clockOn and pos == "right" then order[#order + 1] = self.clock end
  for i = n + 1, #self.pool do self.pool[i]:Hide() end

  local cw, ch = 0, 0
  if clockOn then cw, ch = self:StyleClock(cfg) end
  self.clock:SetShown(clockOn)
  local H = math.max(size, ch, 1)

  local x = 0
  for _, it in ipairs(order) do
    local w, h
    if it == self.clock then w, h = cw, ch else w, h = size, size end
    it:ClearAllPoints()
    it:SetSize(w, h)
    it:SetPoint("TOPLEFT", self.content, "TOPLEFT", x, -(H - h) / 2)
    it._cx = x + w / 2
    if it ~= self.clock then
      local a = BY_ID[it.actionId]
      it.vis:SetSize(size, size)
      it.icon:SetSize(size, size)
      if a and a.spacer then
        -- Espaceur : un carre pale dans l'apercu, rien sur la vraie barre
        it.icon:SetTexture("Interface\\Buttons\\WHITE8x8")
        it.icon:SetTexCoord(0, 1, 0, 1)
        it.icon:SetDesaturated(false)
        it.icon:SetAlpha(0.12)
        it.icon:SetShown(self.preview)
      else
        it.icon:SetTexture(ICON_DIR .. ((a and a.icon) or "INV_Misc_QuestionMark"))
        it.icon:SetTexCoord(unpack(TEX_COORD))
        it.icon:SetDesaturated(cfg.desaturate ~= false)
        it.icon:SetAlpha(MenuBar.ActionAvailable(it.actionId) and 1 or 0.35)
        it.icon:Show()
      end
      if not self.preview then
        local macro = a and a.macro()
        it:SetAttribute("type", macro and "macro" or nil)
        it:SetAttribute("macrotext", macro)
        -- Clics avec modificateur / clic droit : attributs "<mod>-type<bouton>" (l'ordre des modificateurs est alt-ctrl-shift)
        local mods = a and a.mods and a.mods() or {}
        for _, pre in ipairs({ "", "shift-", "ctrl-", "alt-", "ctrl-shift-", "alt-ctrl-" }) do
          for btn = 1, 2 do
            if not (pre == "" and btn == 1) then
              local m = mods[pre .. btn]
              it:SetAttribute(pre .. "type" .. btn, m and "macro" or nil)
              it:SetAttribute(pre .. "macrotext" .. btn, m)
            end
          end
        end
        it:EnableMouse(not (a and a.spacer))
        it:EnableMouseWheel(it.actionId == "volume")
      end
      it:Show()
      self:Paint(it)
    end
    x = x + w + gap
  end
  if not self.preview and clockOn then
    local c = self.clock
    c:SetAttribute("type1", "macro")
    c:SetAttribute("macrotext1", "/run if ToggleCalendar then ToggleCalendar() end")
    c:SetAttribute("type2", "macro")
    c:SetAttribute("macrotext2", "/run if ToggleTimeManager then ToggleTimeManager() end")
  end

  local W = math.max(x - gap, 1)
  self.content:SetSize(W, H)
  local EB = ns.Modules.ExtraBars
  local bg = cfg.bgEnabled == true
  if EB and EB.StyleBackground then EB.StyleBackground(self.content, cfg, W, H, bg) end
  local px = bg and (cfg.bgPadX or 12) or 0
  local py = bg and (cfg.bgPadY or 8) or 0
  -- Fond grunge : la texture est plus haute que sa zone visible, on la descend de 4 px
  local bgFrame = self.content.__bg
  if bg and bgFrame and cfg.bgTexture == "grunge" then
    bgFrame:ClearAllPoints()
    bgFrame:SetPoint("TOPLEFT", self.content, "TOPLEFT", -px, py - 4)
  end
  self.frame:SetSize(W + 2 * px, H + 2 * py)
  self.contentW, self.contentH = W, H
  self.padX = px

  if self.plusL then
    self.plusL:SetSize(size, size)
    self.plusR:SetSize(size, size)
    self.plusL:ClearAllPoints()
    self.plusR:ClearAllPoints()
    self.plusL:SetPoint("RIGHT", self.content, "LEFT", -(px + 8), 0)
    self.plusR:SetPoint("LEFT", self.content, "RIGHT", px + 8, 0)
    self.plusL:SetShown(#lefts < MenuBar.MAX_PER_SIDE)
    self.plusR:SetShown(#rights < MenuBar.MAX_PER_SIDE)
  end
  self:UpdateClock()
end

-- Largeur totale, boutons "+" compris (pour ajuster l'echelle de l'apercu)
function Strip:FullWidth()
  local w = self.frame:GetWidth()
  if self.plusL then w = w + 2 * ((Cfg().iconSize or 22) + 8) end
  return w
end

function MenuBar.NewStrip(parent, preview)
  local S = setmetatable({ preview = preview and true or false, pool = {} }, Strip)
  S.frame = CreateFrame("Frame", (not preview) and "AishCoreMenuBar" or nil, parent)
  S.content = CreateFrame("Frame", nil, S.frame)
  S.content:SetPoint("CENTER", S.frame, "CENTER")
  S.driver = CreateFrame("Frame", nil, S.frame)
  S.clock = CreateClock(S)
  if preview then
    S.plusL = NewPlus(S, "left")
    S.plusR = NewPlus(S, "right")
  end
  strips[#strips + 1] = S
  return S
end

-- Horloge : un ticker commun pour tous les strips visibles
ns.NewTicker(0.25, function()
  for _, S in ipairs(strips) do
    if S.frame:IsVisible() then S:UpdateClock() end
  end
end)

-- Barre reelle -------------------------------------------------------------------------------------
local strip
local dragUnlocked = false
local pendingApply = false
local driverOn = false
local currentAlpha = 1
local fader = CreateFrame("Frame")
local hider

-- Barre de menu Blizzard : reparentee sous un cadre cache (hors combat uniquement)
local function HideBlizzard(on)
  local mc = _G.MicroMenuContainer
  if not mc then return end
  if on then
    hider = hider or CreateFrame("Frame")
    hider:Hide()
    if mc:GetParent() ~= hider then
      mc._aishParent = mc:GetParent()
      mc:SetParent(hider)
    end
  elseif mc._aishParent and hider and mc:GetParent() == hider then
    mc:SetParent(mc._aishParent)
    mc._aishParent = nil
  end
end

local function TargetAlpha(cfg)
  if dragUnlocked then return 1 end
  local alpha = cfg.alpha
  if alpha == nil then alpha = 1 end
  if cfg.mouseover and not ns.IsFrameMouseOver(strip.frame) then
    local ma = cfg.mouseoverAlpha
    if ma == nil then ma = 0 end
    return ma
  end
  return alpha
end

local function StartFader()
  fader:SetScript("OnUpdate", function(_, el)
    if not strip then return end
    local cfg = Cfg()
    local target = TargetAlpha(cfg)
    if math.abs(currentAlpha - target) > 0.002 then
      currentAlpha = currentAlpha + (target - currentAlpha) * (1 - math.exp(-8 * el))
    else
      currentAlpha = target
    end
    strip.frame:SetAlpha(currentAlpha)
    -- mode non mouseover : plus rien a suivre une fois la cible atteinte
    if currentAlpha == target and not cfg.mouseover then fader:SetScript("OnUpdate", nil) end
  end)
end

function MenuBar.Create(parent)
  if strip then return end
  strip = MenuBar.NewStrip(parent or UIParent, false)
  local frame = strip.frame
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:Hide()

  -- Poignee de placement : couvre la barre, captee uniquement en mode deplacement
  local grip = CreateFrame("Frame", nil, frame)
  grip:SetAllPoints()
  grip:SetFrameLevel(frame:GetFrameLevel() + 30)
  grip.tex = grip:CreateTexture(nil, "OVERLAY")
  grip.tex:SetAllPoints()
  grip.tex:SetColorTexture(1, 0.82, 0.2, 0.25)
  grip:EnableMouse(true)
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function() frame:StartMoving() end)
  grip:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    ns.DB.menuBar = ns.DB.menuBar or {}
    local point, _, relativePoint, ox, oy = frame:GetPoint(1)
    local db = ns.DB.menuBar
    db.point, db.relativePoint, db.x, db.y = point, relativePoint, ox, oy
  end)
  grip:Hide()
  strip.grip = grip

  MenuBar.ApplySettings()
end

function MenuBar.ApplySettings()
  if not strip then return end
  if InCombatLockdown() then pendingApply = true; return end
  pendingApply = false
  local cfg = Cfg()
  local frame = strip.frame

  HideBlizzard(cfg.enabled == true and cfg.hideBlizzard ~= false)
  if cfg.enabled ~= true then
    if driverOn then UnregisterStateDriver(frame, "visibility"); driverOn = false end
    frame:Hide()
    fader:SetScript("OnUpdate", nil)
    return
  end

  strip:Layout()
  frame:ClearAllPoints()
  frame:SetPoint(cfg.point or "BOTTOM", UIParent, cfg.relativePoint or "BOTTOM", cfg.x or 0, cfg.y or 6)

  -- Masquee en combat : pilote d'etat (agit meme en combat, sans toucher aux boutons securises)
  local want = cfg.hideInCombat == true and not dragUnlocked
  if want ~= driverOn then
    if want then RegisterStateDriver(frame, "visibility", "[combat] hide; show")
    else UnregisterStateDriver(frame, "visibility") end
    driverOn = want
  end
  if not want then frame:Show() end

  strip.grip:SetShown(dragUnlocked)
  currentAlpha = TargetAlpha(cfg)
  frame:SetAlpha(currentAlpha)
  if cfg.mouseover then StartFader() else fader:SetScript("OnUpdate", nil) end
end

-- Mode placement : poignee visible, pleine opacite, jamais masquee
function MenuBar.SetDragUnlocked(val)
  dragUnlocked = val and true or false
  MenuBar.ApplySettings()
end
function MenuBar.IsDragUnlocked() return dragUnlocked end

function MenuBar.GetHoverFrame()
  return strip and strip.frame
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" and not pendingApply then return end
  MenuBar.ApplySettings()
end)

-- Couleurs thematiques : repeindre quand le module Couleurs change (spe, profil, reglage)
do
  local CL = ns.Modules.Colors
  if CL and CL.RegisterCallback then
    CL.RegisterCallback(function()
      for _, S in ipairs(strips) do S:Recolor() end
    end)
  end
end

-- /aishprof : diagnostic des metiers (Forever : lignes de competences et GetProfessions)
SLASH_AISHPROF1 = "/aishprof"
SlashCmdList["AISHPROF"] = function()
  local P = "|cff33aaff[AishCore metiers]|r "
  print(P .. "TRADE_SKILLS=" .. tostring(_G.TRADE_SKILLS) .. " | GetNumSkillLines=" .. type(_G.GetNumSkillLines)
    .. " | GetSkillLineInfo=" .. type(_G.GetSkillLineInfo))
  if _G.GetProfessions then
    local t = { pcall(_G.GetProfessions) }
    local parts = {}
    for i = 2, 7 do
      local idx = t[i]
      local name = idx and _G.GetProfessionInfo and select(1, _G.GetProfessionInfo(idx))
      parts[#parts + 1] = tostring(idx) .. "=" .. tostring(name)
    end
    print(P .. "GetProfessions : " .. table.concat(parts, "  "))
  end
  if _G.GetNumSkillLines and _G.GetSkillLineInfo then
    for i = 1, _G.GetNumSkillLines() or 0 do
      local name, isHeader, isExpanded, rank, _, _, maxRank = _G.GetSkillLineInfo(i)
      print(P .. string.format("%d %s%s %s/%s", i, isHeader and "[EN-TETE] " or "", tostring(name),
        tostring(rank), tostring(maxRank)) .. (isHeader and (isExpanded and " (deplie)" or " (replie)") or ""))
    end
  end
end
